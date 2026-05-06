;; -*- mode: common-lisp; coding: utf-8 -*-%
;;;; ============================================================================
;;;; 模块：invoice 发票 —— 行项业务逻辑（新 nst-* DDD/Hexagonal）
;;;; 分层：BL（业务逻辑层 / 应用服务 + 仓储 + GST 汇总）
;;;; 文件：hhub/invoice/nst-bl-itm.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：两大块功能：
;;;;   1) GST 汇总（gst-breakdown）：把多条 InvoiceItem 按 (HSN, 税率) 聚合成
;;;;      tax-entry。提供 add / remove / update / generate / get-sorted-summary。
;;;;   2) InvoiceItem 全套 CRUD（六边形架构）：Adapter / Service / DBService 三层
;;;;      的 Process* + do* 实现。利用 with-db-create/update/delete 把
;;;;      bo-knowledge（操作结果 + 拷贝）传回 service。
;;;;
;;;; 主要导出：
;;;;   %get-breakdown-key                            — HSN+三种税率组合 key
;;;;   add-item-to-tax-breakdown / remove-... / update-... / generate-gst-tax-breakdown
;;;;   get-sorted-summary                            — 按 HSN 排序导出 tax-entry 列表
;;;;   select-all-invoice-items / find-invoice-item / select-invoice-item-by-product-id
;;;;   ProcessCreateRequest / ProcessUpdateRequest / ProcessReadRequest /
;;;;   ProcessReadAllRequest / ProcessDeleteRequest / ProcessResponse / ProcessResponseList
;;;;   doCreate / doupdate / doread / doreadall / doDelete
;;;;   init / Copy-DbObject-To-BusinessObject / Copy-BusinessObject-To-DBObject /
;;;;   CreateResponseModel / CreateViewModel / CreateAllViewModel
;;;;   工具：createInvoiceItemobject / copyInvoiceItem-domaintodb / copyInvoiceItem-dbtodomain
;;;;
;;;; 关联：
;;;;   上游使用方：invoice/nst-bl-ihd.lisp（汇总 + 触发行项 CRUD）、
;;;;               invoice/nst-ui-itm.lisp、invoice/nst-ui-ihd.lisp
;;;;   下游依赖：invoice/nst-dal-itm.lisp、core 基类
;;;;
;;;; 备注：原作者标注此文件为模板代码，禁止单独 Ctrl+C Ctrl+K 编译。已纳入 nstores.asd。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)
;; METHODS FOR ENTITY CREATE
;; This file contains template code which will be used to generate for class methods.
;; DO NOT COMPILE THIS FILE USING CTRL + C CTRL + K (OR CTRL + CK)
;; DO NOT ADD THIS FILE TO COMPILE.LISP FOR MASS COMPILATION.

;; 1. The Key Helper (to ensure consistency across methods)
(defun %get-breakdown-key (item)
  "中文：构造 GST 汇总哈希表的 key：拼 'HSN-CGST-SGST-IGST'。
   保证 add/remove/update 走同一行 bucket，避免重复或漏减。"
  (format nil "~A-~A-~A-~A" 
          (hsncode item) (cgstrate item) (sgstrate item) (igstrate item)))

;; 2. Remove Method
(defmethod remove-item-from-tax-breakdown ((breakdown gst-breakdown) (item InvoiceItem))
  "Reduces totals for the specific HSN/Rate. If totals hit zero, removes the entry.
   中文：从 (HSN, 税率) 桶中扣减一条行项的 taxable/cgst/sgst/igst 金额。
   若扣减后 taxable-value <= 0.01（容许浮点误差），则把整条 entry 从汇总中移除。"
  (let* ((key (%get-breakdown-key item))
         (entry (gethash key (entries breakdown))))
    (when entry
      ;; Subtract values
      (decf (taxable-value entry) (taxablevalue item))
      (decf (cgst-amount entry)   (cgstamt item))
      (decf (sgst-amount entry)   (sgstamt item))
      (decf (igst-amount entry)   (igstamt item))
      
      ;; Clean up: If taxable value is 0 (or near zero due to float precision), 
      ;; remove the row from the summary
      (when (<= (taxable-value entry) 0.01)
        (remhash key (entries breakdown))))))

;; 3. Update Method
(defmethod update-item-in-tax-breakdown ((breakdown gst-breakdown) (old-item InvoiceItem) (new-item InvoiceItem))
  "Updates the breakdown by removing the old item data and adding the new item data.
   This handles cases where the HSN or Tax Rate might have changed.
   中文：行项被修改时增量同步汇总：先 remove old，再 add new；HSN/税率变了也能正确处理。"
  (remove-item-from-tax-breakdown breakdown old-item)
  (add-item-to-tax-breakdown breakdown new-item))

;; 4. Modified Add Method (using the new key helper)
(defmethod add-item-to-tax-breakdown ((breakdown gst-breakdown) (item InvoiceItem))
  "中文：把一条 InvoiceItem 累加进 (HSN, 税率) 汇总桶。桶不存在时新建 tax-entry。
   备注：gethash 的第三参数是 default 值 —— 这里用 (make-instance 'tax-entry ...)
   作为缺省，但默认值即使桶已存在也会被求值（无副作用，因为构造瞬态对象）。"
  (let* ((key (%get-breakdown-key item))
         (entry (gethash key (entries breakdown)
                         (make-instance 'tax-entry 
                                        :hsn-code (hsncode item)
                                        :cgst-rate (cgstrate item)
                                        :sgst-rate (sgstrate item)
                                        :igst-rate (igstrate item)))))
    (incf (taxable-value entry) (taxablevalue item))
    (incf (cgst-amount entry)   (cgstamt item))
    (incf (sgst-amount entry)   (sgstamt item))
    (incf (igst-amount entry)   (igstamt item))
    (setf (gethash key (entries breakdown)) entry)))

(defmethod  generate-gst-tax-breakdown ((invoice-header InvoiceHeader) (invoice-items list))
  "Creates a live GST breakdown from raw database records.
   中文：从原始行项列表构造 gst-breakdown 汇总对象。
   通过比较发票头的 statecode（卖家所在州）与 placeofsupply（供应地）判断
   is-interstate（跨州 → 仅 IGST；同州 → CGST + SGST）。然后 dolist 把每条行项 add 进去。
   返回：填充完毕的 gst-breakdown 实例。"
  (let* ((placeofsupply (slot-value invoice-header 'placeofsupply))
	 (statecode (slot-value invoice-header 'statecode))
	 (is-interstate (if (equal statecode placeofsupply) NIL T)) 
	 (breakdown (make-instance 'gst-breakdown :is-interstate is-interstate)))
    ;; Iterate through the items extracted from the DB
    (dolist (item invoice-items)
      (add-item-to-tax-breakdown breakdown item))
    ;; Return the populated breakdown object
    breakdown))


(defmethod get-sorted-summary ((breakdown gst-breakdown))
  "Converts hash table to a list sorted by HSN for consistent printing.
   中文：把 entries 哈希表里所有 tax-entry 抽取并按 HSN 字符串升序排序。
   返回：tax-entry 列表，发票末尾的 HSN 摘要表会按这个列表逐行渲染。"
  (let ((result nil))
    (maphash (lambda (k v) (declare (ignore k)) (push v result)) 
             (entries breakdown))
    (sort result #'string< :key #'hsn-code)))


(defun select-all-invoice-items (invoiceheader company)
  :documentation "This function stores all the currencies in a hashtable. The Key = country, Value = list of currency, code and symbol.
   中文：列出某发票头下所有未删除的行项。注意：原英文 docstring 系拷贝自 currency 模板（推测），
   实际读 dod-invoice-items 表（限 100 条 + tenant 过滤）。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (invheadid (slot-value invoiceheader 'row-id)))
    (clsql:select 'dod-invoice-items :where
		  [and
		  [= [:invheadid] invheadid]
		  [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]]
		    :limit 100
		    :caching *dod-database-caching* :flatp t )))

;; If you specifically want to search by prd-id
(defun find-invoice-item (prd-id items)
  "中文：在内存行项列表中按 prd-id 线性查找一条。返回匹配元素或 nil。"
  (find prd-id items :key #'prd-id :test #'equal))

(defun select-invoice-item-by-product-id (product-id invoiceheader company)
  :documentation "This function stores all the currencies in a hashtable. The Key = country, Value = list of currency, code and symbol.
   中文：按 (tenant, invheadid, prd-id) 在数据库中查单条行项。原英文 docstring 同样系
   currency 模板拷贝（推测）。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (invheadid (slot-value invoiceheader 'row-id)))
    (car (clsql:select 'dod-invoice-items :where
		  [and
		  [= [:prd-id] product-id]
		  [= [:invheadid] invheadid]
		  [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]]
		    :limit 100
		    :caching *dod-database-caching* :flatp t ))))




(defmethod ProcessDeleteRequest ((adapter InvoiceItemAdapter) (requestmodel InvoiceItemRequestModel))
  :description "This method is responsible for Deleting a web push notification record for a given vendor.
   中文：Delete 流的 Adapter 钩子，绑定 InvoiceItemService 后委托父类。
   备注：description 拷贝自 webpush 模板（推测），实际处理发票行项删除。"
  ;; Set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceItemService))
  (call-next-method))


(defmethod ProcessCreateRequest ((adapter InvoiceItemAdapter) (requestmodel InvoiceItemRequestModel))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created Warehouse object.
   中文：Create 流 Adapter 钩子。description 中的 'Warehouse' 系模板残留（推测），实际返回新建 InvoiceItem。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceItemService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod init ((dbas InvoiceItemDBService) (bo InvoiceItem))
  :description "Set the DB object and domain object.
   中文：DBService 初始化：构造空 dod-invoice-items 实例并挂到 dbservice，
   再 setcompany 注入租户上下文，最后调父类 init 完成 businessobject 赋值。"
  (let* ((DBObj  (make-instance 'dod-invoice-items)))
    ;; Set specific fields of the DB object if you need to. 
    ;; End set specific fields of the DB object. 
    (setf (dbobject dbas) DBObj)
    ;; Set the company context for the UPI payments DB service 
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))




(defmethod doDelete ((service InvoiceItemService) (requestmodel InvoiceItemRequestModel))
  :description "This method is responsible for Deleting a Web push notification subscription for a given vendor.
   中文：Delete 实现：按 (invheadid, prd-id) 定位单条行项，with-db-delete（:allow-idempotent T）
   软删并产出 bo-knowledge（操作真值/payload）。把 bo-knowledge 上抛 service。
   备注：description 同样为模板残留（推测），实际操作发票行项软删。"
  (let* ((comp (company requestmodel))
	 (invoiceheader (invoiceheader requestmodel))
	 (prd-id (prd-id requestmodel))
	 (domainobj (make-instance 'InvoiceItem))
	 (invoiceitemdbobj (select-invoice-item-by-product-id prd-id invoiceheader comp))
	 (InvoiceItemdbservice (make-instance 'InvoiceItemDBService)))

    (when invoiceitemdbobj
      (setf (slot-value InvoiceItemdbservice 'dbobject) invoiceitemdbobj)
      (setf (slot-value InvoiceItemdbservice 'businessobject) domainobj)
      (setcompany InvoiceItemdbservice comp)
      (let ((bk (with-db-delete (InvoiceItemdbservice :allow-idempotent T :source "Invoice item delete"))))
	;; Transfer knowledge up to the service layer
	(setf (bo-knowledge service) bk)
	(setf domainobj (bo-knowledge-payload bk))
	;; Return the newly created warehouse domain object
	domainobj))))

(defmethod doCreate ((service InvoiceItemService) (requestmodel InvoiceItemRequestModel))
  "中文：Create 实现：从 requestmodel 取所有字段 → createInvoiceItemobject 构造领域对象 →
   init DBService → 拷贝 → with-db-create 写库 → 通过 bo-knowledge 上抛创建结果给 service。"
  (let* ((InvoiceItemdbservice (make-instance 'InvoiceItemDBService))
	 (company (company requestmodel))
	 (InvoiceHeader (InvoiceHeader requestmodel))
	 (prd-id (prd-id requestmodel))
	 (prddesc (prddesc requestmodel))
	 (hsncode (hsncode requestmodel))
	 (qty (qty requestmodel))
	 (uom (uom requestmodel))
	 (price (price requestmodel))
	 (discount (discount requestmodel))
	 (taxablevalue (taxablevalue requestmodel))
	 (cgstrate (cgstrate requestmodel))
	 (cgstamt (cgstamt requestmodel))
	 (sgstrate (sgstrate requestmodel))
	 (sgstamt (sgstamt requestmodel))
	 (igstrate (igstrate requestmodel))
	 (igstamt (igstamt requestmodel))
	 (totalitemval (totalitemval requestmodel))
	 (domainobj (createInvoiceItemobject InvoiceHeader prd-id prddesc hsncode qty uom price discount taxablevalue cgstrate cgstamt sgstrate sgstamt igstrate igstamt totalitemval company )))
    ;; Initialize the DB Service
    (init InvoiceItemdbservice domainobj)
    (copy-businessobject-to-dbobject InvoiceItemdbservice)
    (let ((bk (with-db-create (InvoiceItemdbservice :source "Invoice Item create"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf domainobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      domainobj)))

(defun createInvoiceItemobject (InvoiceHeader prd-id prddesc hsncode qty uom price discount taxablevalue cgstrate cgstamt sgstrate sgstamt igstrate igstamt totalitemval  company)
  "中文：纯构造函数 —— 把字段塞进 InvoiceItem 实例并返回。新行项默认 status='PENDING'。"
  (let* ((domainobj  (make-instance 'InvoiceItem 
				    :InvoiceHeader InvoiceHeader
				    :prd-id prd-id
				    :prddesc prddesc
				    :hsncode hsncode
				    :qty qty
				    :uom uom
				    :price price
				    :discount discount
				    :taxablevalue taxablevalue
				    :cgstrate cgstrate
				    :cgstamt cgstamt 
				    :sgstrate sgstrate
				    :sgstamt sgstamt
				    :igstrate igstrate
				    :igstamt igstamt
				    :totalitemval totalitemval
				    :status "PENDING"
				    :company company)))
    domainobj))


(defmethod Copy-DbObject-To-BusinessObject ((dbas InvoiceItemDBService))
  :description "Syncs the dbobject and domain object.
   中文：DB 对象 → 领域对象 拷贝。先注入 company，再委托 copyInvoiceItem-dbtodomain。"
  (let ((dbobj (slot-value dbas 'dbobject))
        (domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value domainobj 'company) (company dbas))
    (setf (slot-value dbas 'businessobject) (copyInvoiceItem-dbtodomain dbobj domainobj))))

(defmethod Copy-BusinessObject-To-DBObject ((dbas InvoiceItemDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：领域对象 → DB 对象 拷贝。委托 copyInvoiceItem-domaintodb。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyInvoiceItem-domaintodb domainobj dbobj))))

;; source = domain destination = db
(defun copyInvoiceItem-domaintodb (source destination)
  "中文：领域对象 → DB 对象 字段拷贝。
   关联实体解包：source.company → tenant-id；source.InvoiceHeader → invheadid。
   注意 destination 的列名为 taxable-value（带连字符），与 source 的 taxablevalue 不同。"
  (let ((company (slot-value source 'company))
	(invheader (slot-value source 'InvoiceHeader)))
    (with-slots (invheadid prd-id prddesc hsncode qty uom price discount taxable-value cgstrate cgstamt sgstrate sgstamt igstrate igstamt totalitemval status tenant-id) destination
      (setf tenant-id (slot-value company 'row-id))
      (setf invheadid (slot-value invheader 'row-id))
      (setf prd-id (slot-value source 'prd-id))
      (setf prddesc (slot-value source 'prddesc))
      (setf hsncode (slot-value source 'hsncode))
      (setf qty (slot-value source 'qty))
      (setf uom (slot-value source 'uom))
      (setf price (slot-value source 'price))
      (setf discount (slot-value source 'discount))
      (setf taxable-value (slot-value source 'taxablevalue))
      (setf cgstrate (slot-value source 'cgstrate))
      (setf cgstamt (slot-value source 'cgstamt))
      (setf sgstrate (slot-value source 'sgstrate))
      (setf sgstamt (slot-value source 'sgstamt))
      (setf igstrate (slot-value source 'igstrate))
      (setf igstamt (slot-value source 'igstamt))
      (setf totalitemval (slot-value source 'totalitemval))
      (setf status (slot-value source 'status))
      destination)))


;; PROCESS UPDATE REQUEST
(defmethod ProcessUpdateRequest ((adapter InvoiceItemAdapter) (requestmodel InvoiceItemRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：Update 流 Adapter 钩子。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceItemService))
  ;; call the parent ProcessUpdate
  (call-next-method))

;; PROCESS READ ALL REQUEST.
(defmethod ProcessReadAllRequest ((adapter InvoiceItemAdapter) (requestmodel InvoiceItemRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：ReadAll 流 Adapter 钩子。description 系 UPI 模板拷贝（推测），实际批量读 InvoiceItem。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceItemService))
  (call-next-method))

(defmethod doreadall ((service InvoiceItemService) (requestmodel InvoiceItemRequestModel))
  "中文：批量读取：select-all-invoice-items 取出 DB 行项后，逐一拷贝成领域对象。
   每个领域对象都会回填 InvoiceHeader（避免再查一次发票头）。"
  (let* ((comp (company requestmodel))
	 (invoiceheader (invoiceheader requestmodel))
	 (domainobjlst (select-all-invoice-items invoiceheader comp)))
    ;; return back a list of domain objects 
    (mapcar (lambda (object)
	      (let ((domainobject (make-instance 'InvoiceItem)))
		(setf (slot-value domainobject 'InvoiceHeader) invoiceheader)
		(copyInvoiceItem-dbtodomain object domainobject))) domainobjlst)))


(defmethod CreateViewModel ((presenter InvoiceItemPresenter) (responsemodel InvoiceItemResponseModel))
  "中文：ResponseModel → ViewModel 字段同名拷贝。"
  (let ((viewmodel (make-instance 'InvoiceItemViewModel)))
    (with-slots (InvoiceHeader prd-id prddesc hsncode qty uom price discount taxablevalue cgstrate cgstamt sgstrate sgstamt igstrate igstamt totalitemval status company) responsemodel
      (setf (slot-value viewmodel 'InvoiceHeader) InvoiceHeader)
      (setf (slot-value viewmodel 'prd-id) prd-id)
      (setf (slot-value viewmodel 'prddesc) prddesc)
      (setf (slot-value viewmodel 'hsncode) hsncode)
      (setf (slot-value viewmodel 'qty) qty)
      (setf (slot-value viewmodel 'uom) uom)
      (setf (slot-value viewmodel 'price) price)
      (setf (slot-value viewmodel 'discount) discount)
      (setf (slot-value viewmodel 'taxablevalue) taxablevalue)
      (setf (slot-value viewmodel 'cgstrate) cgstrate)
      (setf (slot-value viewmodel 'cgstamt) cgstamt)
      (setf (slot-value viewmodel 'sgstrate) sgstrate)
      (setf (slot-value viewmodel 'sgstamt) sgstamt)
      (setf (slot-value viewmodel 'igstrate) igstrate)
      (setf (slot-value viewmodel 'igstamt) igstamt)
      (setf (slot-value viewmodel 'totalitemval) totalitemval)
      (setf (slot-value viewmodel 'status) status)
      (setf (slot-value viewmodel 'company) company)
      viewmodel)))
  

(defmethod ProcessResponse ((adapter InvoiceItemAdapter) (busobj InvoiceItem))
  "中文：单条 BO → ResponseModel 装配入口。"
  (let ((responsemodel (make-instance 'InvoiceItemResponseModel)))
    (createresponsemodel adapter busobj responsemodel)))

(defmethod ProcessResponseList ((adapter InvoiceItemAdapter) InvoiceItemlist)
  "中文：批量 BO → ResponseModel。"
  (mapcar (lambda (domainobj)
	    (let ((responsemodel (make-instance 'InvoiceItemResponseModel)))
	      (createresponsemodel adapter domainobj responsemodel))) InvoiceItemlist))

(defmethod CreateAllViewModel ((presenter InvoiceItemPresenter) responsemodellist)
  "中文：批量 ResponseModel → ViewModel。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))


(defmethod CreateResponseModel ((adapter InvoiceItemAdapter) (source InvoiceItem) (destination InvoiceItemResponseModel))
  :description "source = InvoiceItem destination = InvoiceItemResponseModel.
   中文：领域对象 → ResponseModel 字段透传。"
  (with-slots (InvoiceHeader prd-id prddesc hsncode qty uom price discount taxablevalue cgstrate cgstamt sgstrate sgstamt igstrate igstamt totalitemval status company) destination  
    (setf InvoiceHeader (slot-value source 'InvoiceHeader))
    (setf prd-id (slot-value source 'prd-id))
    (setf prddesc (slot-value source 'prddesc))
    (setf hsncode (slot-value source 'hsncode))
    (setf qty (slot-value source 'qty))
    (setf uom (slot-value source 'uom))
    (setf price (slot-value source 'price))
    (setf discount (slot-value source 'discount))
    (setf taxablevalue (slot-value source 'taxablevalue))
    (setf cgstrate (slot-value source 'cgstrate))
    (setf cgstamt (slot-value source 'cgstamt))
    (setf sgstrate (slot-value source 'sgstrate))
    (setf sgstamt (slot-value source 'sgstamt))
    (setf igstrate (slot-value source 'igstrate))
    (setf igstamt (slot-value source 'igstamt))
    (setf totalitemval (slot-value source 'totalitemval))
    (setf status (slot-value source 'status))
    (setf company (slot-value source 'company))
    destination))



(defmethod doupdate ((service InvoiceItemService) (requestmodel InvoiceItemRequestModel))
  "中文：Update 实现：按 (invoiceheader, prd-id) 找到现存 DB 行项，原地 setf 数量/价格/折扣/
   税额/状态等可变字段（rate 字段不更新 —— 推测：发票一旦生效行项税率不可改）。
   随后 with-db-update 写库 + 上抛 bo-knowledge。
   备注：when invoiceheader 实际应为 when InvoiceItemdbobj —— 字段判空对象不对（推测：原作者笔误）。"
  (let* ((InvoiceItemdbservice (make-instance 'InvoiceItemDBService))
	 (InvoiceHeader (InvoiceHeader requestmodel))
	 (prd-id (prd-id requestmodel))
	 (qty (qty requestmodel))
	 (price (price requestmodel))
	 (discount (discount requestmodel))
	 (taxablevalue (taxablevalue requestmodel))
	 (cgstamt (cgstamt requestmodel))
	 (sgstamt (sgstamt requestmodel))
	 (igstamt (igstamt requestmodel))
	 (totalitemval (totalitemval requestmodel))
	 (status (status requestmodel))
	 (comp (company requestmodel))
	 (InvoiceItemdbobj (select-invoice-item-by-product-id prd-id invoiceheader comp))
	 (domainobj (make-instance 'InvoiceItem)))
    ;; FIELD UPDATE CODE STARTS HERE 
    (when invoiceheader  
      (setf (slot-value InvoiceItemdbobj 'qty) qty)
      (setf (slot-value InvoiceItemdbobj 'price) price)
      (setf (slot-value InvoiceItemdbobj 'discount) discount)
      (setf (slot-value InvoiceItemdbobj 'taxable-value) taxablevalue)
      (setf (slot-value InvoiceItemdbobj 'cgstamt) cgstamt)
      (setf (slot-value InvoiceItemdbobj 'sgstamt) sgstamt)
      (setf (slot-value InvoiceItemdbobj 'igstamt) igstamt)
      (setf (slot-value InvoiceItemdbobj 'totalitemval) totalitemval)
      (setf (slot-value InvoiceItemdbobj 'status) status))
    ;;  FIELD UPDATE CODE ENDS HERE. 
    (setf (slot-value InvoiceItemdbservice 'dbobject) InvoiceItemdbobj)
    (setf (slot-value InvoiceItemdbservice 'businessobject) domainobj)
    (setcompany InvoiceItemdbservice comp)
    ;; Return the newly created Invoice Header domain object
    (let ((bk (with-db-update (InvoiceItemdbservice :source "Invoice Item Update"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf domainobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      domainobj)))


;; PROCESS THE READ REQUEST
(defmethod ProcessReadRequest ((adapter InvoiceItemAdapter) (requestmodel InvoiceItemRequestModel))
  :description "Adapter service method to read a single InvoiceItem.
   中文：Read 流 Adapter 钩子。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceItemService))
  (call-next-method))

(defmethod doread ((service InvoiceItemService) (requestmodel InvoiceItemRequestModel))
  "中文：单条读：with-db-call 包装查询并产出 bo-knowledge（含真值 :T/:F/:U/:C）。
   仅当真值为 :T（找到）时才把 DB 行项拷贝到领域对象，否则返回空骨架（含 company/InvoiceHeader）。"
  (let* ((comp (company requestmodel))
	 (invoiceheader (invoiceheader requestmodel))
	 (prd-id (prd-id requestmodel))
	 (dbInvoiceItem-knowledge (with-db-call (select-invoice-item-by-product-id  prd-id invoiceheader comp)))
	 (InvoiceItemobj (make-instance 'InvoiceItem)))
    ;; return back a Vpaymentmethod  response model
    (setf (slot-value InvoiceItemobj 'company) comp)
    (setf (slot-value InvoiceItemobj 'InvoiceHeader) invoiceheader)
    (setf (bo-knowledge service) dbInvoiceItem-knowledge)
    (when (eq (bo-knowledge-truth dbInvoiceItem-knowledge) :T)
      (let ((dbInvoiceItem (bo-knowledge-payload dbInvoiceItem-knowledge)))
	(copyInvoiceItem-dbtodomain dbInvoiceItem InvoiceItemobj)))
    InvoiceItemobj))


(defun copyInvoiceItem-dbtodomain (source destination)
  "中文：DB 对象 → 领域对象 字段拷贝。从 source.tenant-id 反查 company 注入 destination；
   注意 DB 列 'taxable-value' 在领域对象里叫 'taxablevalue'。InvoiceHeader 不在这里赋值（调用方负责）。"
  (let* ((comp (select-company-by-id (slot-value source 'tenant-id))))
    (with-slots (row-id InvoiceHeader prd-id prddesc hsncode qty uom price discount taxablevalue cgstrate cgstamt sgstrate sgstamt igstrate igstamt totalitemval status  company) destination
      (setf company comp)
      (setf row-id (slot-value source 'row-id))
      (setf prd-id (slot-value source 'prd-id))
      (setf prddesc (slot-value source 'prddesc))
      (setf hsncode (slot-value source 'hsncode))
      (setf qty (slot-value source 'qty))
      (setf uom (slot-value source 'uom))
      (setf price (slot-value source 'price))
      (setf discount (slot-value source 'discount))
      (setf taxablevalue (slot-value source 'taxable-value))
      (setf cgstrate (slot-value source 'cgstrate))
      (setf cgstamt (slot-value source 'cgstamt))
      (setf sgstrate (slot-value source 'sgstrate))
      (setf sgstamt (slot-value source 'sgstamt))
      (setf igstrate (slot-value source 'igstrate))
      (setf igstamt (slot-value source 'igstamt))
      (setf totalitemval (slot-value source 'totalitemval))
      (setf status (slot-value source 'status))
      destination)))

