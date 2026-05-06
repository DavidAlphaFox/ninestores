;; -*- mode: common-lisp; coding: utf-8 -*-%
;;;; ============================================================================
;;;; 模块：invoice 发票 —— 发票头业务逻辑（新 nst-* DDD/Hexagonal）
;;;; 分层：BL（业务逻辑层 / 应用服务 + 仓储 + 表现层装配）
;;;; 文件：hhub/invoice/nst-bl-ihd.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：发票头模块的查询函数 + 完整六边形 CRUD 实现：
;;;;   - 查询：search-invoice-header-by-invnum / select-invoice-header-by-invnum /
;;;;           select-invoice-header-by-context-id / select-all-invoice-headers
;;;;   - Adapter 钩子：ProcessCreateRequest / ProcessUpdateRequest（含 Status 重载）/
;;;;     ProcessReadAllRequest（含 Search 重载）/ ProcessReadRequest（含 ContextID 重载）/
;;;;     ProcessResponse / ProcessResponseList
;;;;   - Service 实现：doCreate / doupdate（含 Status 重载）/ doread（含 ContextID 重载）/
;;;;     doreadall（含 Search 重载）
;;;;   - DBService：init / Copy-BusinessObject-To-DBObject / Copy-DbObject-To-BusinessObject
;;;;   - Presenter：CreateViewModel / CreateAllViewModel / CreateResponseModel
;;;;   - 工具：createInvoiceHeaderobject / copyInvoiceHeader-domaintodb /
;;;;          copyInvoiceHeader-dbtodomain
;;;;
;;;; 主要导出：上面所有函数；最常被外部调用的是 select-invoice-header-by-context-id
;;;; （订单转发票时根据 context-id 幂等定位）和 select-all-invoice-headers（卖家发票列表）。
;;;;
;;;; 关联：
;;;;   上游使用方：invoice/nst-ui-ihd.lisp、invoice/nst-ui-itm.lisp（行项操作前查发票头）
;;;;   下游依赖：invoice/nst-dal-ihd.lisp、invoice/nst-bl-itm.lisp（行项），core 基类
;;;;
;;;; 备注：原作者标注模板代码，禁止单独 Ctrl+C Ctrl+K 编译；已纳入 nstores.asd 加载。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

(defun search-invoice-header-by-invnum (invnum-like vendor company)
  "中文：按 invnum LIKE %x% 模糊匹配发票头（限定 vendor + tenant）。
   注意：未过滤 deleted-state（推测：调用方/UI 自行处理）。返回：dod-invoice-header 列表。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (vendor-id (slot-value vendor 'row-id)))
    (clsql:select 'dod-invoice-header :where 
		  [and
		  [= [:vendor-id] vendor-id]
		  [= [:tenant-id] tenant-id]
		  [like [:invnum] (format NIL "%~a%"  invnum-like)]]
	       :caching *dod-database-caching* :flatp t)))

(defun select-invoice-header-by-invnum (invnum company)
  "中文：按 (invnum, tenant) 精确查单条发票头。返回：dod-invoice-header 实例 / nil。"
  (let* ((tenant-id (slot-value company 'row-id)))
    (car (clsql:select 'dod-invoice-header :where
		       [and 
		       [=  [:invnum] invnum]
		       [= [:tenant-id] tenant-id]]
					   :caching *dod-database-caching* :flatp t))))

(defun select-invoice-header-by-context-id (context-id company)
  "中文：按 (context-id, tenant) 查单条发票头（订单转发票时用 context-id 幂等定位）。
   返回：dod-invoice-header / nil。"
  (let* ((tenant-id (slot-value company 'row-id)))
    (car (clsql:select 'dod-invoice-header :where
		       [and 
		       [=  [:context-id] context-id]
		       [= [:tenant-id] tenant-id]]
					  :caching *dod-database-caching* :flatp t))))

(defun select-all-invoice-headers (vendor company)
  :documentation "This function stores all the currencies in a hashtable. The Key = country, Value = list of currency, code and symbol.
   中文：列出某 vendor 在某 tenant 下的发票头（限 200 条）。原 docstring 系 currency 模板拷贝（推测）。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (vendor-id (slot-value vendor 'row-id))
	 (invheaders (clsql:select 'dod-invoice-header :where
				   [and
				   [= [:vendor-id] vendor-id]
				   [= [:tenant-id] tenant-id]]
				 :limit 200
				 :caching *dod-database-caching* :flatp t )))
    invheaders))


;; METHODS FOR ENTITY CREATE 
;; This file contains template code which will be used to generate for class methods.
;; DO NOT COMPILE THIS FILE USING CTRL + C CTRL + K (OR CTRL + CK)
;; DO NOT ADD THIS FILE TO COMPILE.LISP FOR MASS COMPILATION. 


(defmethod ProcessCreateRequest ((adapter InvoiceHeaderAdapter) (requestmodel InvoiceHeaderRequestModel))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created Warehouse object.
   中文：Create 流 Adapter 钩子。description 中 'Warehouse' 系模板残留（推测）。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceHeaderService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod init ((dbas InvoiceHeaderDBService) (bo InvoiceHeader))
  :description "Set the DB object and domain object.
   中文：DBService 初始化：构造空 dod-invoice-header → 注入 company → call-next-method。"
  (let* ((DBObj  (make-instance 'dod-invoice-header)))
    ;; Set specific fields of the DB object if you need to. 
    ;; End set specific fields of the DB object. 
    (setf (dbobject dbas) DBObj)
    ;; Set the company context for the UPI payments DB service 
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))



(defmethod doCreate ((service InvoiceHeaderService) (requestmodel InvoiceHeaderRequestModel))
  "中文：Create 实现：从 requestmodel 取所有字段构造领域对象 → init DBService → 拷贝 →
   with-db-create 写库 → bo-knowledge 上抛创建结果。"
  (let* ((InvoiceHeaderdbservice (make-instance 'InvoiceHeaderDBService))
	 (context-id (context-id requestmodel))
	 (vendor (vendor requestmodel))
	 (company (company requestmodel))
	 (customer (customer requestmodel))
	 (invnum (invnum requestmodel))
	 (invdate (invdate requestmodel))
	 (custaddr (custaddr requestmodel))
	 (custgstin (custgstin requestmodel))
	 (statecode (statecode requestmodel))
	 (billaddr (billaddr requestmodel))
	 (shipaddr (shipaddr requestmodel))
	 (placeofsupply (placeofsupply requestmodel))
	 (revcharge (revcharge requestmodel))
	 (transmode (transmode requestmodel))
	 (vnum (vnum requestmodel))
	 (totalvalue (totalvalue requestmodel))
	 (totalinwords (totalinwords requestmodel))
	 (bankaccnum (bankaccnum requestmodel))
	 (bankifsccode (bankifsccode requestmodel))
	 (tnc (tnc requestmodel))
	 (authsign (authsign requestmodel))
	 (finyear (finyear requestmodel))
	 (domainobj (createInvoiceHeaderobject context-id invnum invdate customer custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear vendor company)))
    ;; Initialize the DB Service
    (init InvoiceHeaderdbservice domainobj)
    (copy-businessobject-to-dbobject InvoiceHeaderdbservice)
    (let ((bk (with-db-create (InvoiceHeaderdbservice :source "Invoice Header  create"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf domainobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      domainobj)))

(defun createInvoiceHeaderobject (context-id invnum invdate customer custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear vendor company)
  "中文：纯构造函数：创建 InvoiceHeader 实例。新发票默认 status='DRAFT'，external-url=''。"
  (let* ((domainobj  (make-instance 'InvoiceHeader 
				    :context-id context-id
				    :invnum invnum
				    :invdate invdate
				    :custaddr custaddr
				    :custgstin custgstin
				    :statecode statecode
				    :billaddr billaddr
				    :shipaddr shipaddr
				    :placeofsupply placeofsupply
				    :revcharge revcharge 
				    :transmode transmode
				    :vnum vnum
				    :totalvalue totalvalue
				    :totalinwords totalinwords
				    :bankaccnum bankaccnum
				    :bankifsccode bankifsccode
				    :tnc tnc
				    :authsign authsign
				    :finyear finyear
				    :external-url ""
				    :vendor vendor
				    :customer customer
				    :status "DRAFT"
				    :company company)))
    domainobj))

(defmethod Copy-BusinessObject-To-DBObject ((dbas InvoiceHeaderDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：领域对象 → DB 对象 拷贝。委托 copyInvoiceHeader-domaintodb。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyInvoiceHeader-domaintodb domainobj dbobj))))

;; source = domain destination = db
(defun copyInvoiceHeader-domaintodb (source destination)
  "中文：领域对象 → DB 对象 字段拷贝。
   解包：source.vendor → vendor-id；source.customer → custid + custname 快照；
   source.company → tenant-id。新建时 deleted-state='N'。"
  (let ((vendor (slot-value source 'vendor))
	(customer (slot-value source 'customer))
	(company (slot-value source 'company)))
    (with-slots (context-id invdate custname custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear external-url status deleted-state  custid vendor-id tenant-id) destination
      (setf context-id (slot-value source 'context-id))
      (setf vendor-id (slot-value vendor 'row-id))
      (setf tenant-id (slot-value company 'row-id))
      (setf custid (slot-value customer 'row-id))
      (setf invdate (slot-value source 'invdate))
      (setf custname (slot-value customer 'name))
      (setf custaddr (slot-value source 'custaddr))
      (setf custgstin (slot-value source 'custgstin))
      (setf statecode (slot-value source 'statecode))
      (setf billaddr (slot-value source 'billaddr))
      (setf shipaddr (slot-value source 'shipaddr))
      (setf placeofsupply (slot-value source 'placeofsupply))
      (setf revcharge (slot-value source 'revcharge))
      (setf transmode (slot-value source 'transmode))
      (setf vnum (slot-value source 'vnum))
      (setf totalvalue (slot-value source 'totalvalue))
      (setf totalinwords (slot-value source 'totalinwords))
      (setf bankaccnum (slot-value source 'bankaccnum))
      (setf bankifsccode (slot-value source 'bankifsccode))
      (setf tnc (slot-value source 'tnc))
      (setf authsign (slot-value source 'authsign))
      (setf finyear (slot-value source 'finyear))
      (setf external-url (slot-value source 'external-url))
      (setf status (slot-value source 'status))
      (setf deleted-state "N")
      destination)))


;; PROCESS UPDATE REQUEST
(defmethod ProcessUpdateRequest ((adapter InvoiceHeaderAdapter) (requestmodel InvoiceHeaderRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：Update 流（全字段）Adapter 钩子。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceHeaderService))
  ;; call the parent ProcessUpdate
  (call-next-method))

(defmethod ProcessUpdateRequest ((adapter InvoiceHeaderAdapter) (requestmodel InvoiceHeaderStatusRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：Update 流（仅 totalvalue + status）Adapter 钩子，用于发票状态切换（DRAFT→PAID 等）。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceHeaderService))
  ;; call the parent ProcessUpdate
  (call-next-method))

;; PROCESS READ ALL REQUEST.
(defmethod ProcessReadAllRequest ((adapter InvoiceHeaderAdapter) (requestmodel InvoiceHeaderRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：ReadAll 流 Adapter 钩子（按 vendor 列出全部发票头）。description 系 UPI 模板拷贝（推测）。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceHeaderService))
  (call-next-method))

(defmethod ProcessReadAllRequest ((adapter InvoiceHeaderAdapter) (requestmodel InvoiceHeaderSearchRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：ReadAll 流 Adapter 钩子（按 invnum LIKE 模糊搜索）。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceHeaderService))
  (call-next-method))

(defmethod doreadall ((service InvoiceHeaderService) (requestmodel InvoiceHeaderRequestModel))
  "中文：批量读：select-all-invoice-headers 取 DB 行 → 逐一 dbtodomain 转领域对象。"
  (let* ((comp (company requestmodel))
	 (vendor (vendor requestmodel))
	 (domainobjlst (select-all-invoice-headers vendor comp)))
    ;; return back a list of domain objects 
    (mapcar (lambda (object)
	      (let ((domainobject (make-instance 'InvoiceHeader)))
		(copyInvoiceHeader-dbtodomain object domainobject))) domainobjlst)))

(defmethod doreadall ((service InvoiceHeaderService) (requestmodel InvoiceHeaderSearchRequestModel))
  "中文：搜索批量读：search-invoice-header-by-invnum 后转领域对象。"
  (let* ((comp (company requestmodel))
	 (vendor (vendor requestmodel))
	 (invnum (invnum requestmodel))
	 (domainobjlst (search-invoice-header-by-invnum invnum vendor comp)))
    ;; return back a list of domain objects 
    (mapcar (lambda (object)
	      (let ((domainobject (make-instance 'InvoiceHeader)))
		(copyInvoiceHeader-dbtodomain object domainobject))) domainobjlst)))


(defmethod CreateViewModel ((presenter InvoiceHeaderPresenter) (responsemodel InvoiceHeaderResponseModel))
  "中文：ResponseModel → ViewModel 字段透传。vendor 在最末尾被覆盖一次（无副作用，模板残留）。"
  (let ((viewmodel (make-instance 'InvoiceHeaderViewModel)))
    (with-slots (invnum invdate  custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear status vendor customer company) responsemodel
      (setf (slot-value viewmodel 'vendor) vendor)
      (setf (slot-value viewmodel 'customer) customer)
      (setf (slot-value viewmodel 'invnum) invnum)
      (setf (slot-value viewmodel 'invdate) invdate)
      (setf (slot-value viewmodel 'custaddr) custaddr)
      (setf (slot-value viewmodel 'custgstin) custgstin)
      (setf (slot-value viewmodel 'statecode) statecode)
      (setf (slot-value viewmodel 'billaddr) billaddr)
      (setf (slot-value viewmodel 'shipaddr) shipaddr)
      (setf (slot-value viewmodel 'placeofsupply) placeofsupply)
      (setf (slot-value viewmodel 'revcharge) revcharge)
      (setf (slot-value viewmodel 'transmode) transmode)
      (setf (slot-value viewmodel 'vnum) vnum)
      (setf (slot-value viewmodel 'totalvalue) totalvalue)
      (setf (slot-value viewmodel 'totalinwords) totalinwords)
      (setf (slot-value viewmodel 'bankaccnum) bankaccnum)
      (setf (slot-value viewmodel 'bankifsccode) bankifsccode)
      (setf (slot-value viewmodel 'tnc) tnc)
      (setf (slot-value viewmodel 'authsign) authsign)
      (setf (slot-value viewmodel 'finyear) finyear)
      (setf (slot-value viewmodel 'status) status)
      (setf (slot-value viewmodel 'company) company)
      (setf (slot-value viewmodel 'vendor) vendor)
      viewmodel)))
  

(defmethod ProcessResponse ((adapter InvoiceHeaderAdapter) (busobj InvoiceHeader))
  "中文：单条 BO → ResponseModel。"
  (let ((responsemodel (make-instance 'InvoiceHeaderResponseModel)))
    (createresponsemodel adapter busobj responsemodel)))

(defmethod ProcessResponseList ((adapter InvoiceHeaderAdapter) InvoiceHeaderlist)
  "中文：批量 BO → ResponseModel。"
  (mapcar (lambda (domainobj)
	    (let ((responsemodel (make-instance 'InvoiceHeaderResponseModel)))
	      (createresponsemodel adapter domainobj responsemodel))) InvoiceHeaderlist))

(defmethod CreateAllViewModel ((presenter InvoiceHeaderPresenter) responsemodellist)
  "中文：批量 ResponseModel → ViewModel。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))


(defmethod CreateResponseModel ((adapter InvoiceHeaderAdapter) (source InvoiceHeader) (destination InvoiceHeaderResponseModel))
  :description "source = InvoiceHeader destination = InvoiceHeaderResponseModel.
   中文：领域对象 → ResponseModel 字段透传。with-slots 含 'created'，但 source 中并未设置（推测：模板字段，无害）。"
  (with-slots (invnum invdate  custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear status vendor customer company created) destination  
    (setf invnum (slot-value source 'invnum))
    (setf invdate (slot-value source 'invdate))
    (setf custaddr (slot-value source 'custaddr))
    (setf custgstin (slot-value source 'custgstin))
    (setf statecode (slot-value source 'statecode))
    (setf billaddr (slot-value source 'billaddr))
    (setf shipaddr (slot-value source 'shipaddr))
    (setf placeofsupply (slot-value source 'placeofsupply))
    (setf revcharge (slot-value source 'revcharge))
    (setf transmode (slot-value source 'transmode))
    (setf vnum (slot-value source 'vnum))
    (setf totalvalue (slot-value source 'totalvalue))
    (setf totalinwords (slot-value source 'totalinwords))
    (setf bankaccnum (slot-value source 'bankaccnum))
    (setf bankifsccode (slot-value source 'bankifsccode))
    (setf tnc (slot-value source 'tnc))
    (setf authsign (slot-value source 'authsign))
    (setf finyear (slot-value source 'finyear))
    (setf status (slot-value source 'status))
    (setf vendor (slot-value source  'vendor))
    (setf customer (slot-value source 'customer))
    (setf company (slot-value source 'company))
    destination))



(defmethod doupdate ((service InvoiceHeaderService) (requestmodel InvoiceHeaderRequestModel))
  "中文：Update 实现（全字段）：按 invnum 在 tenant 内定位 DB 行 → 逐字段更新（含 updated=now）→
   db-save。注意发票号 invnum 也被覆盖（推测：保留以便未来允许重新编号）。"
  (let* ((InvoiceHeaderdbservice (make-instance 'InvoiceHeaderDBService))
	 (invnum (invnum requestmodel))
	 (invdate (invdate requestmodel))
	 (custaddr (custaddr requestmodel))
	 (custgstin (custgstin requestmodel))
	 (statecode (statecode requestmodel))
	 (billaddr (billaddr requestmodel))
	 (shipaddr (shipaddr requestmodel))
	 (placeofsupply (placeofsupply requestmodel))
	 (revcharge (revcharge requestmodel))
	 (transmode (transmode requestmodel))
	 (vnum (vnum requestmodel))
	 (totalvalue (totalvalue requestmodel))
	 (totalinwords (totalinwords requestmodel))
	 (bankaccnum (bankaccnum requestmodel))
	 (bankifsccode (bankifsccode requestmodel))
	 (tnc (tnc requestmodel))
	 (authsign (authsign requestmodel))
	 (customer (customer requestmodel))
	 (custid (slot-value customer 'row-id))
	 (vendor (vendor requestmodel))
	 (vendor-id (slot-value vendor 'row-id))
	 (comp (company requestmodel))
	 (tenant-id (slot-value comp 'row-id))
	 (finyear (finyear requestmodel))
	 (external-url (external-url requestmodel))
	 (status (status requestmodel))
	 (InvoiceHeaderdbobj (select-invoice-header-by-invnum invnum comp))
	 (domainobj (make-instance 'InvoiceHeader)))
    ;; FIELD UPDATE CODE STARTS HERE 
    (when InvoiceHeaderdbobj
      (setf (slot-value InvoiceHeaderdbobj 'invnum) invnum)
      (setf (slot-value InvoiceHeaderdbobj 'invdate) invdate)
      (setf (slot-value InvoiceHeaderdbobj 'custaddr) custaddr)
      (setf (slot-value InvoiceHeaderdbobj 'custgstin) custgstin)
      (setf (slot-value InvoiceHeaderdbobj 'statecode) statecode)
      (setf (slot-value InvoiceHeaderdbobj 'billaddr) billaddr)
      (setf (slot-value InvoiceHeaderdbobj 'shipaddr) shipaddr)
      (setf (slot-value InvoiceHeaderdbobj 'placeofsupply) placeofsupply)
      (setf (slot-value InvoiceHeaderdbobj 'revcharge) revcharge)
      (setf (slot-value InvoiceHeaderdbobj 'transmode) transmode)
      (setf (slot-value InvoiceHeaderdbobj 'vnum) vnum)
      (setf (slot-value InvoiceHeaderdbobj 'totalvalue) totalvalue)
      (setf (slot-value InvoiceHeaderdbobj 'totalinwords) totalinwords)
      (setf (slot-value InvoiceHeaderdbobj 'bankaccnum) bankaccnum)
      (setf (slot-value InvoiceHeaderdbobj 'bankifsccode) bankifsccode)
      (setf (slot-value InvoiceHeaderdbobj 'tnc) tnc)
      (setf (slot-value InvoiceHeaderdbobj 'authsign) authsign)
      (setf (slot-value InvoiceHeaderdbobj 'custid) custid)
      (setf (slot-value InvoiceHeaderdbobj 'vendor-id) vendor-id)
      (setf (slot-value InvoiceHeaderdbobj 'tenant-id) tenant-id)
      (setf (slot-value InvoiceHeaderdbobj 'finyear) finyear)
      (setf (slot-value InvoiceHeaderdbobj 'external-url) external-url)
      (setf (slot-value InvoiceHeaderdbobj 'updated) (clsql:get-time))
      (setf (slot-value InvoiceHeaderdbobj 'status) status))
    ;;  FIELD UPDATE CODE ENDS HERE. 
    (setf (slot-value InvoiceHeaderdbservice 'dbobject) InvoiceHeaderdbobj)
    (setf (slot-value InvoiceHeaderdbservice 'businessobject) domainobj)
    (setcompany InvoiceHeaderdbservice comp)
    ;; Return the newly created Invoice Header domain object
    (let ((bk (with-db-update (InvoiceHeaderdbservice :source "Invoice Header Update"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf domainobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      domainobj)))

(defmethod doupdate ((service InvoiceHeaderService) (requestmodel InvoiceHeaderStatusRequestModel))
  "中文：Update 实现（轻量）：仅更新 totalvalue 与 status。
   用于发票状态切换（DRAFT → CONFIRMED → PAID 等）+ 同步金额。"
  (let* ((InvoiceHeaderdbservice (make-instance 'InvoiceHeaderDBService))
	 (invnum (invnum requestmodel))
	 (totalvalue (totalvalue requestmodel))
	 (status (status requestmodel))
	 (comp (company requestmodel))	 
	 (InvoiceHeaderdbobj (select-invoice-header-by-invnum invnum comp))
	 (domainobj (make-instance 'InvoiceHeader)))
	 
    ;; FIELD UPDATE CODE STARTS HERE 
    (when InvoiceHeaderdbobj
      (setf (slot-value InvoiceHeaderdbobj 'totalvalue) totalvalue)
      (setf (slot-value InvoiceHeaderdbobj 'status) status))
    ;;  FIELD UPDATE CODE ENDS HERE. 
    (setf (slot-value InvoiceHeaderdbservice 'dbobject) InvoiceHeaderdbobj)
    (setf (slot-value InvoiceHeaderdbservice 'businessobject) domainobj)
    (setcompany InvoiceHeaderdbservice comp)
    ;; Return the newly created Invoice Header domain object
    (let ((bk (with-db-update (InvoiceHeaderdbservice :source "Invoice Header update"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf domainobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      domainobj)))


;; PROCESS THE READ REQUEST
(defmethod ProcessReadRequest ((adapter InvoiceHeaderAdapter) (requestmodel InvoiceHeaderRequestModel))
  :description "Adapter service method to read a single InvoiceHeader.
   中文：单条读 Adapter 钩子（按 invnum）。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceHeaderService))
  (call-next-method))

(defmethod ProcessReadRequest ((adapter InvoiceHeaderAdapter) (requestmodel InvoiceHeaderContextIDRequestModel))
  :description "Adapter service method to read a single InvoiceHeader.
   中文：单条读 Adapter 钩子（按 context-id）。订单转发票路径用此变体。"
  (setf (slot-value adapter 'businessservice) (find-class 'InvoiceHeaderService))
  (call-next-method))

(defmethod doread ((service InvoiceHeaderService) (requestmodel InvoiceHeaderRequestModel))
  "中文：单条读（按 invnum）。with-db-call 包查询并产出 bo-knowledge；命中（:T）时拷贝到领域对象。"
  (let* ((comp (company requestmodel))
	 (invnum (invnum requestmodel))
	 (dbInvoiceHeader-knowledge (with-db-call (select-invoice-header-by-invnum invnum comp)))
	 (InvoiceHeaderobj (make-instance 'InvoiceHeader)))
    ;; return back a Invoice Header  object
    (setf (slot-value InvoiceHeaderobj 'company) comp)
    (setf (bo-knowledge service) dbInvoiceHeader-knowledge)
    (when (eq (bo-knowledge-truth dbInvoiceHeader-knowledge) :T)
      (let ((dbInvoiceHeader (bo-knowledge-payload dbInvoiceHeader-knowledge)))
	(copyInvoiceHeader-dbtodomain dbInvoiceHeader InvoiceHeaderobj)
	;; set the bo knowledget payload as the domain object
        (setf (bo-knowledge-payload dbInvoiceHeader-knowledge) InvoiceHeaderobj) 
	InvoiceHeaderobj))))

(defmethod doread ((service InvoiceHeaderService) (requestmodel InvoiceHeaderContextIDRequestModel))
  "中文：单条读（按 context-id）。订单转发票时通过 context-id 幂等查询，避免重复创建。"
  (let* ((comp (company requestmodel))
	 (context-id (context-id requestmodel))
	 (dbInvoiceHeader-knowledge (with-db-call (select-invoice-header-by-context-id context-id comp)))
	 (InvoiceHeaderobj (make-instance 'InvoiceHeader)))
    ;; return back a Invoice Header  object
    (setf (slot-value InvoiceHeaderobj 'company) comp)
    (setf (bo-knowledge service) dbInvoiceHeader-knowledge)
    (when (eq (bo-knowledge-truth dbInvoiceHeader-knowledge) :T)
      (let ((dbInvoiceHeader (bo-knowledge-payload dbInvoiceHeader-knowledge)))
	(copyInvoiceHeader-dbtodomain dbInvoiceHeader InvoiceHeaderobj)
	;; set the bo knowledget payload as the domain object
        (setf (bo-knowledge-payload dbInvoiceHeader-knowledge) InvoiceHeaderobj) 
	InvoiceHeaderobj))))


(defmethod Copy-DbObject-To-BusinessObject ((dbas InvoiceHeaderDBService))
  :description "Syncs the dbobject and domain object.
   中文：DB 对象 → 领域对象 拷贝。先注入 company，再委托 copyInvoiceHeader-dbtodomain。"
  (let ((dbobj (slot-value dbas 'dbobject))
        (domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value domainobj 'company) (company dbas))
    (setf (slot-value dbas 'businessobject) (copyInvoiceHeader-dbtodomain dbobj domainobj))))

(defun copyInvoiceHeader-dbtodomain (dbsrc domaindest)
  "中文：DB 对象 → 领域对象。从 tenant-id / vendor-id / custid 反查实体注入 destination。
   返回填充好的 domaindest。"
  (let* ((comp (select-company-by-id (slot-value dbsrc 'tenant-id)))
	 (vend (select-vendor-by-id (slot-value dbsrc 'vendor-id)))
	 (cust (select-customer-by-id (slot-value dbsrc 'custid) comp)))

    (with-slots (context-id row-id invnum invdate customer  custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear external-url status vendor company) domaindest
      (setf vendor vend)
      (setf customer cust)
      (setf company comp)
      (setf context-id (slot-value dbsrc 'context-id))
      (setf row-id (slot-value dbsrc 'row-id))
      (setf invnum (slot-value dbsrc 'invnum))
      (setf invdate (slot-value dbsrc 'invdate))
      (setf custaddr (slot-value dbsrc 'custaddr))
      (setf custgstin (slot-value dbsrc 'custgstin))
      (setf statecode (slot-value dbsrc 'statecode))
      (setf billaddr (slot-value dbsrc 'billaddr))
      (setf shipaddr (slot-value dbsrc 'shipaddr))
      (setf placeofsupply (slot-value dbsrc 'placeofsupply))
      (setf revcharge (slot-value dbsrc 'revcharge))
      (setf transmode (slot-value dbsrc 'transmode))
      (setf vnum (slot-value dbsrc 'vnum))
      (setf totalvalue (slot-value dbsrc 'totalvalue))
      (setf totalinwords (slot-value dbsrc 'totalinwords))
      (setf bankaccnum (slot-value dbsrc 'bankaccnum))
      (setf bankifsccode (slot-value dbsrc 'bankifsccode))
      (setf tnc (slot-value dbsrc 'tnc))
      (setf authsign (slot-value dbsrc 'authsign))
      (setf finyear (slot-value dbsrc 'finyear))
      (setf external-url (slot-value dbsrc 'external-url))
      (setf status (slot-value dbsrc 'status))
      domaindest)))

