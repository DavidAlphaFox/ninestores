;;; dod-bl-upi.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：upi UPI 收款
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/upi/dod-bl-upi.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：UPI 收款的业务逻辑——按六边形分层在 Adapter / Service / DBService /
;;;;       Presenter 之间路由，实现"创建支付（PEN/N）→ 卖家确认（CNF/Y 或 CAN/N）"
;;;;       状态机；并提供按客户/卖家/UTR 查询的 DAL 包装。
;;;;
;;;; 主要导出：
;;;;   ProcessCreateRequest / ProcessUpdateRequest / ProcessReadAllRequest
;;;;       — Adapter 进入点（绑定 businessservice 到 UpiPaymentsService）
;;;;   doCreate / doupdate / doreadall  — Service 主流程
;;;;   CreateViewModel / CreateAllViewModel  — Presenter
;;;;   ProcessResponseList / CreateResponseModel  — Response 装配
;;;;   init / Copy-DbObject-To-BusinessObject / Copy-BusinessObject-To-DBObject
;;;;       — DBService 上下文与 BO ↔ DBObj 同步
;;;;   select-upi-transaction-by-utrnum / select-upi-transactions-by-customer /
;;;;   select-upi-transactions-by-vendor   — 查询
;;;;   get-vendor-orders-from-upi-transactions  — 卖家维度订单号截取
;;;;   copyupipayment-dbtodomain / copyupipayment-domaintodb
;;;;   createupipaymentobject              — UpiPayment 工厂
;;;;
;;;; 关联：
;;;;   上游使用方：upi/dod-ui-upi.lisp（控制器/UI）
;;;;   下游依赖：upi/dod-dal-upi.lisp、core 的 BusinessService/AdapterService 抽象、
;;;;             account（select-company-by-id）、vendor / customer 查询
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

(defmethod (setf amount) (new-val (obj UpiPayment))
  "UpiPayment.amount 的写入器，强制业务上限：单笔不得超过 10000。
   超限：返回字符串错误信息（注意：未抛错，仅返回字符串），不写 slot；
   合法：正常 setf。"
  (if (> new-val  10000.00)
      "Amount should be less than 10000.00"
      ;;else
      (setf (slot-value obj 'amount) new-val)))
  

(defmethod ProcessCreateRequest ((adapter UpiPaymentsAdapter) (requestmodel UpiPaymentsRequestModel))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created UPI object.
   中文：在 Adapter 上把 businessservice 指到 UpiPaymentsService，再 call-next-method
        让父类执行通用 Create 流程，最终返回新建的 UpiPayment 域对象。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'UpiPaymentsService))
  ;; call the parent ProcessCreate
  (call-next-method))

(defmethod ProcessUpdateRequest ((adapter UpiPaymentsAdapter) (requestmodel UpiPaymentsRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：Update 路径——Adapter 绑定 service 后调父类。"
  (setf (slot-value adapter 'businessservice) (find-class 'UpiPaymentsService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod ProcessReadAllRequest ((adapter UpiPaymentsAdapter) (requestmodel UpiPaymentsRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：ReadAll 路径——Adapter 绑定 service 后调父类，列出 vendor 名下的 UPI 流水。"
  (setf (slot-value adapter 'businessservice) (find-class 'UpiPaymentsService))
  (call-next-method))

(defmethod doreadall ((service UpiPaymentsService) (requestmodel UpiPaymentsRequestModel))
  "Service 层 ReadAll：根据 requestmodel 中的 vendor + company，
   从 DAL 取近期 UPI 流水，并把每条 db 行复制成 UpiPayment 域对象返回。"
  (let* ((vend (vendor requestmodel))
	 (comp (company requestmodel))
	 (upitranslst (select-upi-transactions-by-vendor vend comp)))
    ;; return back a list of upi payments
    (mapcar (lambda (upitran)
	      (let ((upipayment (make-instance 'UpiPayment)))
		(copyupipayment-dbtodomain upitran upipayment))) upitranslst)))
        

(defmethod CreateViewModel ((presenter UpiPaymentsPresenter) (responsemodel UpiPaymentsResponseModel))
  "Presenter：把 ResponseModel 字段逐一拷贝到 ViewModel，供视图层渲染。"
  (let ((viewmodel (make-instance 'UpiPaymentsViewModel)))
    (with-slots (vendor customer amount utrnum transaction-id status vendorconfirm phone company created) responsemodel
      (setf (slot-value viewmodel 'vendor) vendor)
      (setf (slot-value viewmodel 'customer) customer)
      (setf (slot-value viewmodel 'amount) amount)
      (setf (slot-value viewmodel 'utrnum) utrnum)
      (setf (slot-value viewmodel 'transaction-id) transaction-id)
      (setf (slot-value viewmodel 'status) status)
      (setf (slot-value viewmodel 'vendorconfirm) vendorconfirm)
      (setf (slot-value viewmodel 'phone) phone)
      (setf (slot-value viewmodel 'company) company)
      (setf (slot-value viewmodel 'created) created)
      viewmodel)))


(defmethod ProcessResponseList ((adapter UpiPaymentsAdapter) upipaymentslist)
  "把一组 UpiPayment 域对象批量装成 ResponseModel 列表。"
  (mapcar (lambda (upipayment)
	    (let ((responsemodel (make-instance 'UpiPaymentsResponseModel)))
	      (createresponsemodel adapter upipayment responsemodel))) upipaymentslist))


(defmethod CreateAllViewModel ((presenter UpiPaymentsPresenter) responsemodellist)
  "把一组 ResponseModel 批量转 ViewModel。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))


(defmethod doupdate ((service UpiPaymentsService) (requestmodel UpiPaymentsRequestModel))
  "Service 层 Update：卖家在后台对一条 UPI 流水做"确认 / 拒绝"。
   按 utrnum 取出 dod-upi-payments，根据 paymentconfirm 标志置：
     paymentconfirm=T → vendorconfirm='Y' status='CNF'（确认到账）
     paymentconfirm=NIL → vendorconfirm='N' status='CAN'（驳回）
   再写库并返回域对象。"
  (let* ((vend (vendor requestmodel))
	 (upipaymentsdbservice (make-instance 'UpiPaymentsDBService))
	 (utrnum (utrnum requestmodel))
	 (comp (company requestmodel))
	 (paymentconfirm (paymentconfirm requestmodel))
	 (upidbobj (select-upi-transaction-by-utrnum utrnum vend comp))
	 (upiobj (make-instance 'UpiPayment)))
    
    (when paymentconfirm 
      (setf (slot-value upidbobj 'vendorconfirm) "Y")
      (setf (slot-value upidbobj 'status) "CNF"))
    
    (unless paymentconfirm
      (setf (slot-value upidbobj 'vendorconfirm) "N")
      (setf (slot-value upidbobj 'status) "CAN"))

    (setf (slot-value upipaymentsdbservice 'dbobject) upidbobj)
    (setf (slot-value upipaymentsdbservice 'businessobject) upiobj)
    
    (setcompany upipaymentsdbservice comp)
    
    (let ((bk (with-db-update (upipaymentsdbservice :source "UPI payment received status update"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf upiobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      upiobj)))
 

(defun get-vendor-orders-from-upi-transactions ()
  "取登录卖家近 60 天 UPI 流水中的订单号集合。
   实现：transaction-id 前 5 个字符是固定前缀（推测如 \"UPI##\"），subseq 5 截掉前缀
        即得订单号。
   返回：订单号字符串列表。"
  (let* ((upitrans (select-upi-transactions-by-vendor (get-login-vendor) (get-login-vendor-company)))
	 (orders (mapcar (lambda (tran)
			   (subseq (slot-value tran 'transaction-id) 5)) upitrans)))
    orders))

(defun select-upi-transaction-by-utrnum (utrnum vend company)
  "按 (utrnum, vendor, company) 查 UPI 流水。
   返回：单条 dod-upi-payments / nil。被 doupdate 用来定位待确认记录。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vend 'row-id)))
    
    (first (clsql:select 'dod-upi-payments  :where
		[and 
		[= [:deleted-state] "N"]
		[= [:vendor-id] vendor-id]
		[= [:utrnum] utrnum]
		[= [:tenant-id] tenant-id]]
     :caching *dod-database-caching* :flatp t ))))

(defun select-upi-transactions-by-customer (cust company)
  "列出某客户在某租户下的所有未删 UPI 流水（不限时间）。"
  (let ((tenant-id (slot-value company 'row-id))
	(cust-id (slot-value cust 'row-id)))
	    
    (clsql:select 'dod-upi-payments  :where
		[and 
		[= [:deleted-state] "N"]
		[= [:cust-id] cust-id]		[= [:tenant-id] tenant-id]]
     :caching *dod-database-caching* :flatp t )))


(defun select-upi-transactions-by-vendor (vend company &optional (recordsfordays 60))
  "列出某卖家近 ±recordsfordays 天的 UPI 流水（默认 60 天前到 60 天后窗口）。
   按 row-id 倒序排，最新优先。
   备注：窗口同时往前后取，未来日期一般不应有记录，推测意在覆盖时区 / 跨日。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vend 'row-id))
	(strfromdate (get-date-string-mysql (clsql-sys:date- (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays))))
	(strtodate (get-date-string-mysql (clsql-sys:date+ (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays)))))
    
    (clsql:select 'dod-upi-payments  :where
		[and 
		[= [:deleted-state] "N"]
		[= [:vendor-id] vendor-id]
		[between [:created] strfromdate strtodate]
		[= [:tenant-id] tenant-id]] :order-by '(([row-id] :desc)) 
				     :caching *dod-database-caching* :flatp t)))

(defmethod doCreate ((service UpiPaymentsService) (requestmodel UpiPaymentsRequestModel))
  "Service 层 Create：客户提交 UPI 付款信息后落库。
   流程：requestmodel → createupipaymentobject 构造 UpiPayment 域对象 →
        强制 status='PEN'、vendorconfirm='N' → init DBService → 写库 → 返回域对象。"
  (let* ((vend (vendor requestmodel))
	 (upipaymentsdbservice (make-instance 'UpiPaymentsDBService))
	 (cust (customer requestmodel))
	 (amt (amount requestmodel))
	 (phone (phone requestmodel))
	 (utrnum (utrnum requestmodel))
	 (transaction-id (transaction-id requestmodel))
	 (comp (company requestmodel))
	 (upiobj (createupipaymentobject cust vend amt transaction-id utrnum comp phone)))

    (setf (slot-value upiobj 'status) "PEN")
    (setf (slot-value upiobj 'vendorconfirm) "N")
    
    ;; Initialize the DB Service
    (init upipaymentsdbservice upiobj)
    (copy-businessobject-to-dbobject upipaymentsdbservice)
    (let ((bk (with-db-create (upipaymentsdbservice :source "UPI payments create"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf upiobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      upiobj)))


(defmethod init ((dbas UpiPaymentsDBService) (bo UpiPayment))
  :description "Set the DB object and domain object.
   中文：DBService 初始化——新建空 dod-upi-payments，挂到 dbobject slot；
        从 BO 取 company 设置 DBService 的 tenant 上下文；再 call-next-method。"
  (let* ((UpiPaymentsDBObj  (make-instance 'dod-upi-payments)))
      (setf (dbobject dbas) UpiPaymentsDBObj)
    ;; Set the company context for the UPI payments DB service
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))

(defmethod Copy-DbObject-To-BusinessObject ((dbas UpiPaymentsDBService))
  :description "Syncs the dbobject and domain object.
   中文：把 db 行（slot 名贴近列名）复制到 UpiPayment 域对象。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(upipaymentobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'businessobject) (copyupipayment-dbtodomain dbobj upipaymentobj))))

(defmethod Copy-BusinessObject-To-DBObject ((dbas UpiPaymentsDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：反向同步——把 UpiPayment 域对象的字段写到 dod-upi-payments。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(upipaymentobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyupipayment-domaintodb upipaymentobj dbobj))))

(defun copyupipayment-dbtodomain (source destination)
  "把 dod-upi-payments 实例（source）拷到 UpiPayment（destination）。
   注意：根据 db 上的 tenant-id / vendor-id / cust-id，重新查出 company /
        vendor / customer 实体填到域对象（是聚合，非单纯字段拷贝）。"
  (let* ((comp (select-company-by-id (slot-value source 'tenant-id)))
	 (vend (select-vendor-by-id (slot-value source 'vendor-id)))
	 (cust (select-customer-by-id (slot-value source 'cust-id) comp)))

    (with-slots (amount transaction-id customer vendor status utrnum vendorconfirm deleted-state company created phone) destination
      (setf vendor vend)
      (setf customer cust)
      (setf amount (slot-value source 'amount))
      (setf company comp)
      (setf transaction-id  (slot-value source 'transaction-id))
      (setf utrnum (slot-value source 'utrnum))
      (setf vendorconfirm (slot-value source 'vendorconfirm))
      (setf status (slot-value source 'status))
      (setf deleted-state (slot-value source 'deleted-state))
      (setf created (slot-value source 'created))
      (setf phone (slot-value source 'phone))
      destination)))


(defun copyupipayment-domaintodb (source destination)
  "把 UpiPayment 域对象（source）拷到 dod-upi-payments db 行（destination）。
   把 company/vendor/customer 拍扁成 tenant-id/vendor-id/cust-id；phone 取自客户。"
  (let ((vendor (slot-value source 'vendor))
	(customer (slot-value source 'customer))
	(company (slot-value source 'company)))
    
  (with-slots (transaction-id cust-id vendor-id amount status utrnum vendorconfirm deleted-state tenant-id phone) destination
    (setf vendor-id (slot-value vendor 'row-id))
    (setf cust-id  (slot-value customer 'row-id))
    (setf phone (slot-value customer 'phone))
    (setf amount (slot-value source 'amount))
    (setf tenant-id (slot-value company 'row-id))
    (setf transaction-id  (slot-value source 'transaction-id))
    (setf utrnum (slot-value source 'utrnum))
    (setf vendorconfirm (slot-value source 'vendorconfirm))
    (setf status (slot-value source 'status))
    (setf deleted-state (slot-value source 'deleted-state))
    destination)))


(defmethod CreateResponseModel ((adapter UpiPaymentsAdapter) (source UpiPayment) (destination UpiPaymentsResponseModel))
  :description "source = upipayment destination = upipaymentresponsemodel.
   中文：把 UpiPayment 域对象映射到 ResponseModel（基本是字段拷贝）。"
  (with-slots (transaction-id customer vendor amount status utrnum vendorconfirm deleted-state company created phone) destination
    (setf vendor (slot-value source 'vendor))
    (setf customer  (slot-value source 'customer))
    (setf amount (slot-value source 'amount))
    (setf company (slot-value source 'company))
    (setf transaction-id  (slot-value source 'transaction-id))
    (setf utrnum (slot-value source 'utrnum))
    (setf vendorconfirm (slot-value source 'vendorconfirm))
    (setf status (slot-value source 'status))
    (setf created (slot-value source 'created))
    (setf phone (slot-value source 'phone))
    destination))

  
(defun createupipaymentobject (customer vendor amount transaction-id utrnum  company phone)
  "工厂：构造 UpiPayment 域对象（不写库），deleted-state 默认 'N'。"
  (let* ((upipaymentobj (make-instance 'UpiPayment
				       :customer customer
				       :vendor vendor
				       :amount amount
				       :transaction-id transaction-id
				       :utrnum utrnum
				       :company company
				       :phone phone
				       :deleted-state "N")))
    upipaymentobj))
				       




