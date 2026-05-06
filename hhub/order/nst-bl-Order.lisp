;; -*- mode: common-lisp; coding: utf-8 -*-%
;;;; ============================================================================
;;;; 模块：order 订单 —— 订单业务逻辑（新 nst-* DDD/Hexagonal）
;;;; 分层：BL（业务逻辑层 / 应用服务 + 仓储 + 表现层装配）
;;;; 文件：hhub/order/nst-bl-Order.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：六边形架构下的 order 领域 CRUD 实现：
;;;;   - Adapter（应用服务层）方法：ProcessCreateRequest / ProcessUpdateRequest /
;;;;     ProcessReadRequest / ProcessReadAllRequest / ProcessResponse / ProcessResponseList
;;;;   - Service（领域服务层）方法：doCreate / doread / doreadall / doupdate
;;;;   - DBService（仓储层）方法：init / Copy-BusinessObject-To-DBObject /
;;;;     CreateResponseModel / CreateViewModel / CreateAllViewModel
;;;;   - 拷贝工具：createorderobject / copyorder-domaintodb / copyorder-dbtodomain
;;;;   - GST 合计辅助：calculate-order-total{gst,cgst,sgst,igst,beforetax,aftertax}
;;;;
;;;; 主要导出：
;;;;   六边形 CRUD 类簇方法（同上）
;;;;   calculate-order-totalgst / -totalcgst / -totalsgst / -totaligst
;;;;   calculate-order-totalbeforetax / -totalaftertax
;;;;
;;;; 关联：
;;;;   上游使用方：order/nst-ui-Order.lisp（控制器/视图）
;;;;   下游依赖：order/nst-dal-Order.lisp（实体）、order/dod-bl-ord.lisp（旧函数复用：
;;;;             get-orders-for-customer / get-order-by-context-id 等）、
;;;;             customer 模块（select-customer-by-id）、core 基类
;;;;
;;;; 备注：原作者标注模板代码，禁止单独 Ctrl+C Ctrl+K 编译；已纳入 nstores.asd 加载。
;;;; ============================================================================

(in-package :nstores)

;; METHODS FOR ENTITY CREATE
;; This file contains template code which will be used to generate for class methods.
;; DO NOT COMPILE THIS FILE USING CTRL + C CTRL + K (OR CTRL + CK)
;; DO NOT ADD THIS FILE TO COMPILE.LISP FOR MASS COMPILATION.


(defmethod ProcessCreateRequest ((adapter orderAdapter) (requestmodel orderRequestModel))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created Warehouse object.
   中文：Create 流 Adapter 钩子。description 中的 'Warehouse' 系模板残留（推测），实际返回新建 order。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'orderService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod init ((dbas orderDBService) (bo order))
  :description "Set the DB object and domain object.
   中文：DBService 初始化：构造空 dod-order DB 对象 + 注入 company 上下文 → call-next-method。"
  (let* ((DBObj  (make-instance 'dod-order)))
    ;; Set specific fields of the DB object if you need to. 
    ;; End set specific fields of the DB object. 
    (setf (dbobject dbas) DBObj)
    ;; Set the company context for the UPI payments DB service 
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))



(defmethod doCreate ((service orderService) (requestmodel orderRequestModel))
  "中文：Create 实现：从 requestmodel 抽取所有字段，包装成多值闭包 → createorderobject 构造领域对象 →
   init DBService → 拷贝到 DB 对象 → db-save。返回新建领域对象。"
  (let* ((orderdbservice (make-instance 'orderDBService))
	 (customer (customer requestmodel))
	 (ord-date (ord-date requestmodel))
	 (req-date (req-date requestmodel))
	 (shipped-date (shipped-date requestmodel))
	 (expected-delivery-date (expected-delivery-date requestmodel))
	 (ordnum (ordnum requestmodel))
	 (shipaddr (shipaddr requestmodel))
	 (shipzipcode (shipzipcode requestmodel))
	 (shipcity (shipcity requestmodel))
	 (shipstate (shipstate requestmodel))
	 (billaddr (billaddr requestmodel))
	 (billzipcode (billzipcode requestmodel))
	 (billcity (billcity requestmodel))
	 (billstate (billstate requestmodel))
	 (billsameasship (billsameasship requestmodel))
	 (storepickupenabled (storepickupenabled requestmodel))
	 (gstnumber (gstnumber requestmodel))
	 (gstorgname (gstorgname requestmodel))
	 (order-fulfilled (order-fulfilled requestmodel))
	 (order-amt (order-amt requestmodel))
	 (shipping-cost (shipping-cost requestmodel))
	 (total-discount (total-discount requestmodel))
	 (total-tax (total-tax requestmodel))
	 (payment-mode (payment-mode requestmodel))
	 (comments (comments requestmodel))
	 (context-id (context-id requestmodel))
	 (status (status requestmodel))
	 (is-converted-to-invoice (is-converted-to-invoice requestmodel))
	 (is-cancelled (is-cancelled requestmodel))
	 (cancel-reason (cancel-reason requestmodel))
	 (order-type (order-type requestmodel))
	 (external-url (external-url requestmodel))
	 (order-source (order-source requestmodel))
	 (custname (custname requestmodel))
	 (company (company requestmodel))
	 (domainobj (createorderobject (function (lambda () (values  ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id  status is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname customer company))))))
         ;; Initialize the DB Service
    (init orderdbservice domainobj)
    (copy-businessobject-to-dbobject orderdbservice)
    (db-save orderdbservice)
    ;; Return the newly created warehouse domain object
    domainobj))


(defun createorderobject (modelfunc)
  "中文：以多值闭包接收所有字段，构造一个 order 实例。新订单默认 deleted-state='N'。
   备注：:company 在 :initargs 中出现两次（后者覆盖前者）—— 与 OrderItem 同样的小冗余。"
  (multiple-value-bind (ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id  status  is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname customer company) (funcall modelfunc)
  (let* ((domainobj  (make-instance 'order 
				    :ord-date ord-date
				    :req-date req-date
				    :shipped-date shipped-date
				    :expected-delivery-date expected-delivery-date
				    :ordnum ordnum
				    :shipaddr shipaddr
				    :shipzipcode shipzipcode
				    :shipcity shipcity
				    :shipstate shipstate
				    :billaddr billaddr 
				    :billzipcode billzipcode
				    :billcity billcity
				    :billstate billstate
				    :billsameasship billsameasship
				    :storepickupenabled storepickupenabled
				    :gstnumber gstnumber
				    :gstorgname gstorgname
				    :order-fulfilled order-fulfilled
				    :order-amt order-amt
				    :shipping-cost shipping-cost
				    :total-discount total-discount
				    :total-tax total-tax
				    :payment-mode payment-mode
				    :comments comments
				    :context-id context-id
				    :customer customer
				    :status status
				    :is-converted-to-invoice is-converted-to-invoice
				    :is-cancelled is-cancelled
				    :cancel-reason cancel-reason
				    :order-type order-type
				    :external-url external-url
				    :order-source order-source
				    :custname custname
				    :company company
				    :deleted-state "N"
				    :company company)))
    domainobj)))

(defmethod Copy-BusinessObject-To-DBObject ((dbas orderDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：领域对象 → DB 对象 拷贝。委托 copyorder-domaintodb。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyorder-domaintodb domainobj dbobj))))

;; source = domain destination = db
(defun copyorder-domaintodb (source destination)
  "中文：领域对象 → DB 对象 拷贝。把 source.company / customer 解包成 tenant-id / cust-id。
   注意：customer slot 同时 setf 到 destination.customer 与 destination.cust-id（前者用于查询访问，
   后者是真正的外键列）。"
  (let ((company (slot-value source 'company)))
    (with-slots (ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id customer status  is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname cust-id  tenant-id) destination
      (setf ord-date (slot-value source 'ord-date))
      (setf req-date (slot-value source 'req-date))
      (setf shipped-date (slot-value source 'shipped-date))
      (setf expected-delivery-date (slot-value source 'expected-delivery-date))
      (setf ordnum (slot-value source 'ordnum))
      (setf shipaddr (slot-value source 'shipaddr))
      (setf shipzipcode (slot-value source 'shipzipcode))
      (setf shipcity (slot-value source 'shipcity))
      (setf shipstate (slot-value source 'shipstate))
      (setf billaddr (slot-value source 'billaddr))
      (setf billzipcode (slot-value source 'billzipcode))
      (setf billcity (slot-value source 'billcity))
      (setf billstate (slot-value source 'billstate))
      (setf billsameasship (slot-value source 'billsameasship))
      (setf storepickupenabled (slot-value source 'storepickupenabled))
      (setf gstnumber (slot-value source 'gstnumber))
      (setf gstorgname (slot-value source 'gstorgname))
      (setf order-fulfilled (slot-value source 'order-fulfilled))
      (setf order-amt (slot-value source 'order-amt))
      (setf shipping-cost (slot-value source 'shipping-cost))
      (setf total-discount (slot-value source 'total-discount))
      (setf total-tax (slot-value source 'total-tax))
      (setf payment-mode (slot-value source 'payment-mode))
      (setf comments (slot-value source 'comments))
      (setf context-id (slot-value source 'context-id))
      (setf customer (slot-value source 'customer))
      (setf status (slot-value source 'status))
      (setf is-converted-to-invoice (slot-value source 'is-converted-to-invoice))
      (setf is-cancelled (slot-value source 'is-cancelled))
      (setf cancel-reason (slot-value source 'cancel-reason))
      (setf order-type (slot-value source 'order-type))
      (setf external-url (slot-value source 'external-url))
      (setf order-source (slot-value source 'order-source))
      (setf custname (slot-value source 'custname))
      (setf tenant-id (slot-value company 'row-id))
      (setf cust-id (slot-value customer 'row-id))
      destination)))


;; PROCESS UPDATE REQUEST
(defmethod ProcessUpdateRequest ((adapter orderAdapter) (requestmodel orderRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：Update 流 Adapter 钩子。"
  (setf (slot-value adapter 'businessservice) (find-class 'orderService))
  ;; call the parent ProcessUpdate
  (call-next-method))

;; PROCESS READ ALL REQUEST.
(defmethod ProcessReadAllRequest ((adapter orderAdapter) (requestmodel orderRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：ReadAll 流 Adapter 钩子。description 系 UPI 模板拷贝（推测）。"
  (setf (slot-value adapter 'businessservice) (find-class 'orderService))
  (call-next-method))

(defmethod doreadall ((service orderService) (requestmodel orderRequestModel))
  "中文：批量读：调旧 BL 的 get-orders-for-customer 拿 DB 行列表，逐一拷贝成 order 领域对象列表。"
  (let* ((cust (customer requestmodel))
	 (domainobjlst (get-orders-for-customer cust)))
    ;; return back a list of domain objects 
    (mapcar (lambda (object)
	      (let ((domainobject (make-instance 'order)))
		(copyorder-dbtodomain object domainobject))) domainobjlst)))


(defmethod CreateViewModel ((presenter orderPresenter) (responsemodel orderResponseModel))
  "中文：ResponseModel → ViewModel 字段透传（含 vendor / customer / created 等附加字段）。"
  (let ((viewmodel (make-instance 'orderViewModel)))
    (with-slots (row-id ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id  status deleted-state is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname  vendor customer company created) responsemodel
      (setf (slot-value viewmodel 'vendor) vendor)
      (setf (slot-value viewmodel 'customer) customer)
      (setf (slot-value viewmodel 'row-id) row-id)
      (setf (slot-value viewmodel 'ord-date) ord-date)
      (setf (slot-value viewmodel 'req-date) req-date)
      (setf (slot-value viewmodel 'shipped-date) shipped-date)
      (setf (slot-value viewmodel 'expected-delivery-date) expected-delivery-date)
      (setf (slot-value viewmodel 'ordnum) ordnum)
      (setf (slot-value viewmodel 'shipaddr) shipaddr)
      (setf (slot-value viewmodel 'shipzipcode) shipzipcode)
      (setf (slot-value viewmodel 'shipcity) shipcity)
      (setf (slot-value viewmodel 'shipstate) shipstate)
      (setf (slot-value viewmodel 'billaddr) billaddr)
      (setf (slot-value viewmodel 'billzipcode) billzipcode)
      (setf (slot-value viewmodel 'billcity) billcity)
      (setf (slot-value viewmodel 'billstate) billstate)
      (setf (slot-value viewmodel 'billsameasship) billsameasship)
      (setf (slot-value viewmodel 'storepickupenabled) storepickupenabled)
      (setf (slot-value viewmodel 'gstnumber) gstnumber)
      (setf (slot-value viewmodel 'gstorgname) gstorgname)
      (setf (slot-value viewmodel 'order-fulfilled) order-fulfilled)
      (setf (slot-value viewmodel 'order-amt) order-amt)
      (setf (slot-value viewmodel 'shipping-cost) shipping-cost)
      (setf (slot-value viewmodel 'total-discount) total-discount)
      (setf (slot-value viewmodel 'total-tax) total-tax)
      (setf (slot-value viewmodel 'payment-mode) payment-mode)
      (setf (slot-value viewmodel 'comments) comments)
      (setf (slot-value viewmodel 'context-id) context-id)
      (setf (slot-value viewmodel 'customer) customer)
      (setf (slot-value viewmodel 'status) status)
      (setf (slot-value viewmodel 'deleted-state) deleted-state)
      (setf (slot-value viewmodel 'is-converted-to-invoice) is-converted-to-invoice)
      (setf (slot-value viewmodel 'is-cancelled) is-cancelled)
      (setf (slot-value viewmodel 'cancel-reason) cancel-reason)
      (setf (slot-value viewmodel 'order-type) order-type)
      (setf (slot-value viewmodel 'external-url) external-url)
      (setf (slot-value viewmodel 'order-source) order-source)
      (setf (slot-value viewmodel 'custname) custname)
      (setf (slot-value viewmodel 'company) company)
      (setf (slot-value viewmodel 'created) created)
      viewmodel)))
  

(defmethod ProcessResponse ((adapter orderAdapter) (busobj order))
  "中文：单条 BO → ResponseModel 装配。"
  (let ((responsemodel (make-instance 'orderResponseModel)))
    (createresponsemodel adapter busobj responsemodel)))

(defmethod ProcessResponseList ((adapter orderAdapter) orderlist)
  "中文：批量 BO → ResponseModel。"
  (mapcar (lambda (domainobj)
	    (let ((responsemodel (make-instance 'orderResponseModel)))
	      (createresponsemodel adapter domainobj responsemodel))) orderlist))

(defmethod CreateAllViewModel ((presenter orderPresenter) responsemodellist)
  "中文：批量 ResponseModel → ViewModel。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))


(defmethod CreateResponseModel ((adapter orderAdapter) (source order) (destination orderResponseModel))
  :description "source = order destination = orderResponseModel.
   中文：领域对象 → ResponseModel 字段透传。"
  (with-slots (row-id ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id  status deleted-state is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname  vendor customer company created) destination  
    (setf row-id (slot-value source 'row-id))
    (setf ord-date (slot-value source 'ord-date))
    (setf req-date (slot-value source 'req-date))
    (setf shipped-date (slot-value source 'shipped-date))
    (setf expected-delivery-date (slot-value source 'expected-delivery-date))
    (setf ordnum (slot-value source 'ordnum))
    (setf shipaddr (slot-value source 'shipaddr))
    (setf shipzipcode (slot-value source 'shipzipcode))
    (setf shipcity (slot-value source 'shipcity))
    (setf shipstate (slot-value source 'shipstate))
    (setf billaddr (slot-value source 'billaddr))
    (setf billzipcode (slot-value source 'billzipcode))
    (setf billcity (slot-value source 'billcity))
    (setf billstate (slot-value source 'billstate))
    (setf billsameasship (slot-value source 'billsameasship))
    (setf storepickupenabled (slot-value source 'storepickupenabled))
    (setf gstnumber (slot-value source 'gstnumber))
    (setf gstorgname (slot-value source 'gstorgname))
    (setf order-fulfilled (slot-value source 'order-fulfilled))
    (setf order-amt (slot-value source 'order-amt))
    (setf shipping-cost (slot-value source 'shipping-cost))
    (setf total-discount (slot-value source 'total-discount))
    (setf total-tax (slot-value source 'total-tax))
    (setf payment-mode (slot-value source 'payment-mode))
    (setf comments (slot-value source 'comments))
    (setf context-id (slot-value source 'context-id))
    (setf customer (slot-value source 'customer))
    (setf status (slot-value source 'status))
    (setf deleted-state (slot-value source 'deleted-state))
    (setf is-converted-to-invoice (slot-value source 'is-converted-to-invoice))
    (setf is-cancelled (slot-value source 'is-cancelled))
    (setf cancel-reason (slot-value source 'cancel-reason))
    (setf order-type (slot-value source 'order-type))
    (setf external-url (slot-value source 'external-url))
    (setf order-source (slot-value source 'order-source))
    (setf custname (slot-value source 'custname))
    (setf company (slot-value source 'company))
    destination))



(defmethod doupdate ((service orderService) (requestmodel orderRequestModel))
  "中文：Update 实现：按 (context-id, company) 在 DB 中定位 dod-order，逐字段 setf 更新后 db-save。
   备注：context-id 是稳定业务键；row-id 也被覆盖（推测）但这里反向写入 DB row-id 通常无意义，
   且 row-id 是主键，按经验不应被改 —— 此处可能是历史代码遗留，使用时需确保 requestmodel.row-id
   与 orderdbobj.row-id 一致。"
  (with-slots (row-id ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id  status deleted-state is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname  vendor customer company created) requestmodel
    (let* ((orderdbservice (make-instance 'orderDBService))
	   (orderdbobj (get-order-by-context-id context-id company))
	   (domainobj (make-instance 'order)))
    ;; FIELD UPDATE CODE STARTS HERE 
      (when orderdbobj
	(setf (slot-value orderdbobj 'row-id) row-id)
	(setf (slot-value orderdbobj 'ord-date) ord-date)
	(setf (slot-value orderdbobj 'req-date) req-date)
	(setf (slot-value orderdbobj 'shipped-date) shipped-date)
	(setf (slot-value orderdbobj 'expected-delivery-date) expected-delivery-date)
	(setf (slot-value orderdbobj 'ordnum) ordnum)
	(setf (slot-value orderdbobj 'shipaddr) shipaddr)
	(setf (slot-value orderdbobj 'shipzipcode) shipzipcode)
	(setf (slot-value orderdbobj 'shipcity) shipcity)
	(setf (slot-value orderdbobj 'shipstate) shipstate)
	(setf (slot-value orderdbobj 'billaddr) billaddr)
	(setf (slot-value orderdbobj 'billzipcode) billzipcode)
	(setf (slot-value orderdbobj 'billcity) billcity)
	(setf (slot-value orderdbobj 'billstate) billstate)
	(setf (slot-value orderdbobj 'billsameasship) billsameasship)
	(setf (slot-value orderdbobj 'storepickupenabled) storepickupenabled)
	(setf (slot-value orderdbobj 'gstnumber) gstnumber)
	(setf (slot-value orderdbobj 'gstorgname) gstorgname)
	(setf (slot-value orderdbobj 'order-fulfilled) order-fulfilled)
	(setf (slot-value orderdbobj 'order-amt) order-amt)
	(setf (slot-value orderdbobj 'shipping-cost) shipping-cost)
	(setf (slot-value orderdbobj 'total-discount) total-discount)
	(setf (slot-value orderdbobj 'total-tax) total-tax)
	(setf (slot-value orderdbobj 'payment-mode) payment-mode)
	(setf (slot-value orderdbobj 'comments) comments)
	;;(setf (slot-value orderdbobj 'context-id) \"SOMEVALUE\")
	(setf (slot-value orderdbobj 'customer) customer)
	(setf (slot-value orderdbobj 'status) status)
	(setf (slot-value orderdbobj 'deleted-state) deleted-state)
	(setf (slot-value orderdbobj 'is-converted-to-invoice) is-converted-to-invoice)
	(setf (slot-value orderdbobj 'is-cancelled) is-cancelled)
	(setf (slot-value orderdbobj 'cancel-reason) cancel-reason)
	(setf (slot-value orderdbobj 'order-type) order-type)
	(setf (slot-value orderdbobj 'external-url) external-url)
	(setf (slot-value orderdbobj 'order-source) order-source)
	(setf (slot-value orderdbobj 'custname) custname)
	(setf (slot-value orderdbobj 'company) company))
      ;;  FIELD UPDATE CODE ENDS HERE. 
    
    (setf (slot-value orderdbservice 'dbobject) orderdbobj)
    (setf (slot-value orderdbservice 'businessobject) domainobj)
    
    (setcompany orderdbservice company)
    (db-save orderdbservice)
    ;; Return the newly created UPI domain object
    (copyorder-dbtodomain orderdbobj domainobj))))


;; PROCESS THE READ REQUEST
(defmethod ProcessReadRequest ((adapter orderAdapter) (requestmodel orderRequestModel))
  :description "Adapter service method to read a single order.
   中文：Read 流 Adapter 钩子。"
  (setf (slot-value adapter 'businessservice) (find-class 'orderService))
  (call-next-method))

(defmethod doread ((service orderService) (requestmodel orderRequestModel))
  "中文：单条读：按 context-id 在 company 内查 dod-order，再 copyorder-dbtodomain 转领域对象。"
  (let* ((company (company requestmodel))
	 (context-id (context-id requestmodel))
	 (dborder (get-order-by-context-id context-id company))
	 (orderobj (make-instance 'order)))
    ;; return back a Vpaymentmethod  response model
    (setf (slot-value orderobj 'company) company)
    (copyorder-dbtodomain dborder orderobj)))


(defun copyorder-dbtodomain (source destination)
  "中文：DB 对象 → 领域对象 字段拷贝。从 source.tenant-id 反查 company；
   再用 cust-id 从 company 内查 customer 实例注入 destination。其它字段透传。"
  (let* ((comp (select-company-by-id (slot-value source 'tenant-id)))
	 (cust (select-customer-by-id (slot-value source 'cust-id) comp)))
    (with-slots (row-id ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id  status deleted-state is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname vendor customer company) destination
      (setf customer cust)
      (setf company comp)
      (setf row-id (slot-value source 'row-id))
      (setf ord-date (slot-value source 'ord-date))
      (setf req-date (slot-value source 'req-date))
      (setf shipped-date (slot-value source 'shipped-date))
      (setf expected-delivery-date (slot-value source 'expected-delivery-date))
      (setf ordnum (slot-value source 'ordnum))
      (setf shipaddr (slot-value source 'shipaddr))
      (setf shipzipcode (slot-value source 'shipzipcode))
      (setf shipcity (slot-value source 'shipcity))
      (setf shipstate (slot-value source 'shipstate))
      (setf billaddr (slot-value source 'billaddr))
      (setf billzipcode (slot-value source 'billzipcode))
      (setf billcity (slot-value source 'billcity))
      (setf billstate (slot-value source 'billstate))
      (setf billsameasship (slot-value source 'billsameasship))
      (setf storepickupenabled (slot-value source 'storepickupenabled))
      (setf gstnumber (slot-value source 'gstnumber))
      (setf gstorgname (slot-value source 'gstorgname))
      (setf order-fulfilled (slot-value source 'order-fulfilled))
      (setf order-amt (slot-value source 'order-amt))
      (setf shipping-cost (slot-value source 'shipping-cost))
      (setf total-discount (slot-value source 'total-discount))
      (setf total-tax (slot-value source 'total-tax))
      (setf payment-mode (slot-value source 'payment-mode))
      (setf comments (slot-value source 'comments))
      (setf context-id (slot-value source 'context-id))
      (setf customer (slot-value source 'customer))
      (setf status (slot-value source 'status))
      (setf deleted-state (slot-value source 'deleted-state))
      (setf is-converted-to-invoice (slot-value source 'is-converted-to-invoice))
      (setf is-cancelled (slot-value source 'is-cancelled))
      (setf cancel-reason (slot-value source 'cancel-reason))
      (setf order-type (slot-value source 'order-type))
      (setf external-url (slot-value source 'external-url))
      (setf order-source (slot-value source 'order-source))
      (setf custname (slot-value source 'custname))
      (setf company (slot-value source 'company))
      destination)))
 
(defun calculate-order-totalgst (order orderitems vendor)
  "中文：订单层 GST 总额计算。比较卖家州（vendor.state）与收货州（order.shipstate）：
   同州 → CGST + SGST 之和；跨州 → 仅 IGST 之和。"
  (let ((placeofsupply (string-upcase (slot-value vendor 'state)))
	(statecode (string-upcase (slot-value order 'shipstate))))
    (if (equal placeofsupply statecode)
	(+ (calculate-order-totalcgst orderitems) (calculate-order-totalsgst orderitems))
	;;else
	(calculate-order-totaligst orderitems))))

(defun calculate-order-totalcgst (orderitems)
  "中文：行项 CGST 金额求和。"
  (reduce #'+ (mapcar (lambda (item) (slot-value item 'cgstamt)) orderitems)))

(defun calculate-order-totalsgst (orderitems)
  "中文：行项 SGST 金额求和。"
  (reduce #'+ (mapcar (lambda (item) (slot-value item 'sgstamt)) orderitems)))

(defun calculate-order-totaligst (orderitems)
  "中文：行项 IGST 金额求和。"
  (reduce #'+ (mapcar (lambda (item) (slot-value item 'igstamt)) orderitems)))


(defun calculate-order-totalbeforetax (orderitems)
  "中文：税前合计 = 各行项 taxablevalue 之和（fround 取整以减小浮点误差）。"
  (fround (reduce #'+ (mapcar (lambda (item) (slot-value item 'taxablevalue)) orderitems))))

(defun calculate-order-totalaftertax (orderitems)
  "中文：税后合计 = 各行项 (taxablevalue + cgstamt + sgstamt + igstamt) 之和（fround）。
   注意此处对所有 GST 项做了相加 —— 若是跨州订单 cgst/sgst 应为 0，因此结果在两种场景下等价。"
  (fround (reduce #'+ (mapcar (lambda (item)
				(let* ((cgstamt (slot-value item 'cgstamt))
				       (sgstamt (slot-value item 'sgstamt))
				       (igstamt (slot-value item 'igstamt))
				       (taxablevalue (slot-value item 'taxablevalue)))
				  (+ taxablevalue sgstamt cgstamt igstamt))) orderitems))))

