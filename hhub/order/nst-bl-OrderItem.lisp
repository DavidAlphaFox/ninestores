;;; nst-bl-OrderItem.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：order 订单 —— 订单行项业务逻辑（新 nst-* DDD/Hexagonal）
;;;; 分层：BL（业务逻辑层 / 应用服务 + 仓储 + 表现层装配）
;;;; 文件：hhub/order/nst-bl-OrderItem.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：基于 CLOS 的 OrderItem 领域服务集合，覆盖 Create / Read / ReadAll / Update
;;;;       的 Adapter（应用服务）+ Service（领域服务）+ DBService（仓储）+
;;;;       Presenter（视图模型装配）+ ResponseModel/ViewModel 拷贝。属于六边形架构，
;;;;       对接 core/nst-bl-conflodis.lisp 的 dispatch 管线。
;;;;
;;;; 主要导出：
;;;;   OrderItemAdapter / OrderItemService / OrderItemDBService / OrderItemPresenter
;;;;   方法 ProcessCreateRequest / ProcessUpdateRequest / ProcessReadRequest /
;;;;        ProcessReadAllRequest / ProcessResponse / ProcessResponseList
;;;;   方法 doCreate / doupdate / doread / doreadall
;;;;   方法 init（DBService 初始化）/ Copy-BusinessObject-To-DBObject /
;;;;        CreateResponseModel / CreateViewModel / CreateAllViewModel
;;;;   工具 createOrderItemobject / copyOrderItem-domaintodb / copyOrderItem-dbtodomain
;;;;
;;;; 关联：
;;;;   上游使用方：order/nst-ui-OrderItem.lisp（控制器 / 视图渲染）
;;;;   下游依赖：order/nst-dal-OrderItem.lisp（DAL）、order/dod-bl-odt.lisp（部分查询函数复用）
;;;;
;;;; 备注：文件顶部原作者警告 —— "本文件仅作模板代码模板，禁止 Ctrl+C Ctrl+K 单独编译，
;;;;       禁止纳入 compile.lisp 批编译"。该文件已经在 nstores.asd 中按需加载。
;;;; ============================================================================

(in-package :nstores)

;; METHODS FOR ENTITY CREATE
;; This file contains template code which will be used to generate for class methods.
;; DO NOT COMPILE THIS FILE USING CTRL + C CTRL + K (OR CTRL + CK)
;; DO NOT ADD THIS FILE TO COMPILE.LISP FOR MASS COMPILATION.


(defmethod ProcessCreateRequest ((adapter OrderItemAdapter) (requestmodel OrderItemRequestModel))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created Warehouse object.
   中文：Create 流的 Adapter 钩子。绑定 businessservice = OrderItemService 后委托给父类 ProcessCreate。
   返回：创建后的 OrderItem 业务对象。备注：原 description 中的 'Warehouse' 系拷贝自模板（推测）。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'OrderItemService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod init ((dbas OrderItemDBService) (bo OrderItem))
  :description "Set the DB object and domain object.
   中文：DBService 初始化：构造一个 DB 对象（表名为 'database-table-object-name-here'，
   推测为模板未填实占位 —— 写入会出错；当前 doCreate 后立即被 copyOrderItem-domaintodb 覆盖）。
   随后 setcompany 注入租户上下文，再 call-next-method 走父类 init。"
  (let* ((DBObj  (make-instance 'database-table-object-name-here)))
    ;; Set specific fields of the DB object if you need to. 
    ;; End set specific fields of the DB object. 
    (setf (dbobject dbas) DBObj)
    ;; Set the company context for the UPI payments DB service 
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))



(defmethod doCreate ((service OrderItemService) (requestmodel OrderItemRequestModel))
  "中文：Service 层 Create 实现。从 requestmodel 取所有字段，先构造领域对象 OrderItem，
   再 init DBService → 把领域字段拷贝到 DB 对象 → db-save。
   返回：刚创建的领域对象（未补 row-id 自增值）。"
  (let* ((OrderItemdbservice (make-instance 'OrderItemDBService))
	 (company (company requestmodel))
	 (row-id (row-id requestmodel))
	 (order (order requestmodel))
	 (product (product requestmodel))
	 (vendor (vendor requestmodel))
	 (prd-qty (prd-qty requestmodel))
	 (unit-price (unit-price requestmodel))
	 (disc-rate (disc-rate requestmodel))
	 (cgst (cgst requestmodel))
	 (sgst (sgst requestmodel))
	 (igst (igst requestmodel))
	 (addl-tax1-rate (addl-tax1-rate requestmodel))
	 (comments (comments requestmodel))
	 (fulfilled (fulfilled requestmodel))
	 (status (status requestmodel))
	 (deleted-state (deleted-state requestmodel))
	 (domainobj (createOrderItemobject row-id order product vendor prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state company)))
         ;; Initialize the DB Service
    (init OrderItemdbservice domainobj)
    (copy-businessobject-to-dbobject OrderItemdbservice)
    (db-save OrderItemdbservice)
    ;; Return the newly created orderitems domain object
    domainobj))


(defun createOrderItemobject (row-id order product vendor prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state company)
  "中文：纯构造函数 —— 把所有字段塞进一个 OrderItem 实例并返回。
   备注：vendor 在 :initargs 中出现两次（两个 :vendor），初始化器后者覆盖前者，等价于一次。"
  (let* ((domainobj  (make-instance 'OrderItem 
				       :row-id row-id
				       :order order
				       :product product
				       :vendor vendor
				       :prd-qty prd-qty
				       :unit-price unit-price
				       :disc-rate disc-rate
				       :cgst cgst
				       :sgst sgst
				       :igst igst
				       :addl-tax1-rate addl-tax1-rate 
				       :comments comments
				       :fulfilled fulfilled
				       :status status
				       :deleted-state deleted-state
				       :vendor vendor
				       :company company)))
    domainobj))

(defmethod Copy-BusinessObject-To-DBObject ((dbas OrderItemDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：把 dbservice 内的领域对象（businessobject）字段拷贝到 dbobject。委托给 copyOrderItem-domaintodb。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyOrderItem-domaintodb domainobj dbobj))))

;; source = domain destination = db
(defun copyOrderItem-domaintodb (source destination)
  "中文：领域对象 → DB 对象 字段拷贝。把 vendor/company/order/product 这类关联实体
   解构成 *-id 外键，塞进 destination 的 vendor-id/order-id/prd-id/tenant-id。"
  (let ((vendor (slot-value source 'vendor))
	(company (slot-value source 'company))
	(product (slot-value source 'product))
	(order (slot-value source 'order)))
    (with-slots (row-id order-id prd-id vendor-id prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state tenant-id) destination
      (setf vendor-id (slot-value vendor 'row-id))
      (setf tenant-id (slot-value company 'row-id))
      (setf order-id (slot-value order 'row-id))
      (setf prd-id (slot-value product 'row-id))
      (setf prd-qty (slot-value source 'prd-qty))
      (setf unit-price (slot-value source 'unit-price))
      (setf disc-rate (slot-value source 'disc-rate))
      (setf cgst (slot-value source 'cgst))
      (setf sgst (slot-value source 'sgst))
      (setf igst (slot-value source 'igst))
      (setf addl-tax1-rate (slot-value source 'addl-tax1-rate))
      (setf comments (slot-value source 'comments))
      (setf fulfilled (slot-value source 'fulfilled))
      (setf status (slot-value source 'status))
      (setf deleted-state (slot-value source 'deleted-state))
      destination)))


;; PROCESS UPDATE REQUEST
(defmethod ProcessUpdateRequest ((adapter OrderItemAdapter) (requestmodel OrderItemRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：Update 流的 Adapter 钩子，绑定 OrderItemService 后委托给父类 ProcessUpdate。"
  (setf (slot-value adapter 'businessservice) (find-class 'OrderItemService))
  ;; call the parent ProcessUpdate
  (call-next-method))

;; PROCESS READ ALL REQUEST.
(defmethod ProcessReadAllRequest ((adapter OrderItemAdapter) (requestmodel OrderItemRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：ReadAll 流的 Adapter 钩子。description 系拷贝自 UPI 模板（推测），
   实际处理 OrderItem 的批量读取。"
  (setf (slot-value adapter 'businessservice) (find-class 'OrderItemService))
  (call-next-method))

(defmethod doreadall ((service OrderItemService) (requestmodel OrderItemRequestModel))
  "中文：批量读：按 (order, vendor) 取卖家在某订单中的所有行项（复用旧 BL 函数）。
   返回：领域对象 OrderItem 列表。"
  (let* ((vendor (vendor requestmodel))
	 (order (order requestmodel))
	 (dbobjlst (get-order-items-for-vendor-by-order-id order vendor)))
    ;; return back a list of domain objects 
    (mapcar (lambda (dbobject)
	      (let ((domainobject (make-instance 'OrderItem)))
		(copyOrderItem-dbtodomain dbobject domainobject))) dbobjlst)))


(defmethod CreateViewModel ((presenter OrderItemPresenter) (responsemodel OrderItemResponseModel))
  "中文：把 ResponseModel 的字段全部 setf 到一个新建 ViewModel；分离层是为了 View 渲染
   只依赖 ViewModel 接口。"
  (let ((viewmodel (make-instance 'OrderItemViewModel)))
    (with-slots (row-id order product vendor prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state company) responsemodel
      (setf (slot-value viewmodel 'vendor) vendor)
      (setf (slot-value viewmodel 'row-id) row-id)
      (setf (slot-value viewmodel 'order) order)
      (setf (slot-value viewmodel 'product) product)
      (setf (slot-value viewmodel 'vendor) vendor)
      (setf (slot-value viewmodel 'prd-qty) prd-qty)
      (setf (slot-value viewmodel 'unit-price) unit-price)
      (setf (slot-value viewmodel 'disc-rate) disc-rate)
      (setf (slot-value viewmodel 'cgst) cgst)
      (setf (slot-value viewmodel 'sgst) sgst)
      (setf (slot-value viewmodel 'igst) igst)
      (setf (slot-value viewmodel 'addl-tax1-rate) addl-tax1-rate)
      (setf (slot-value viewmodel 'comments) comments)
      (setf (slot-value viewmodel 'fulfilled) fulfilled)
      (setf (slot-value viewmodel 'status) status)
      (setf (slot-value viewmodel 'deleted-state) deleted-state)
      (setf (slot-value viewmodel 'company) company)
       viewmodel)))
  

(defmethod ProcessResponse ((adapter OrderItemAdapter) (busobj OrderItem))
  "中文：单个领域对象 → ResponseModel 装配入口。"
  (let ((responsemodel (make-instance 'OrderItemResponseModel)))
    (createresponsemodel adapter busobj responsemodel)))

(defmethod ProcessResponseList ((adapter OrderItemAdapter) OrderItemlist)
  "中文：领域对象列表 → ResponseModel 列表。每条都走 createresponsemodel 拷贝。"
  (mapcar (lambda (domainobj)
	    (let ((responsemodel (make-instance 'OrderItemResponseModel)))
	      (createresponsemodel adapter domainobj responsemodel))) OrderItemlist))

(defmethod CreateAllViewModel ((presenter OrderItemPresenter) responsemodellist)
  "中文：批量装配 ViewModel（逐条 createviewmodel）。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))


(defmethod CreateResponseModel ((adapter OrderItemAdapter) (source OrderItem) (destination OrderItemResponseModel))
  :description "source = OrderItem destination = OrderItemResponseModel.
   中文：把领域对象的全部业务字段拷贝到 ResponseModel（同字段透传）。"
  (with-slots (row-id order product vendor prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state company) destination  
    (setf row-id (slot-value source 'row-id))
    (setf order (slot-value source 'order))
    (setf product (slot-value source 'product))
    (setf vendor (slot-value source 'vendor))
    (setf prd-qty (slot-value source 'prd-qty))
    (setf unit-price (slot-value source 'unit-price))
    (setf disc-rate (slot-value source 'disc-rate))
    (setf cgst (slot-value source 'cgst))
    (setf sgst (slot-value source 'sgst))
    (setf igst (slot-value source 'igst))
    (setf addl-tax1-rate (slot-value source 'addl-tax1-rate))
    (setf comments (slot-value source 'comments))
    (setf fulfilled (slot-value source 'fulfilled))
    (setf status (slot-value source 'status))
    (setf deleted-state (slot-value source 'deleted-state))
    (setf company (slot-value source 'company))
    destination))



(defmethod doupdate ((service OrderItemService) (requestmodel OrderItemRequestModel))
  "中文：Update 实现：先用 (prd-id, order-id, tenant-id) 在表中定位现有 DB 行项，
   再原地 setf 各字段，db-save 后转回领域对象。
   备注：定位用的是 get-order-items-by-product-id —— 即按商品+订单查行项，
   而非按行项主键 row-id；这意味着同一订单中不能同一商品有多行（业务约束推测）。"
  (with-slots (row-id order product vendor prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state company) requestmodel
    (let* ((OrderItemdbservice (make-instance 'OrderItemDBService))
	   (prd-id (slot-value product 'row-id))
	   (order-id (slot-value order 'row-id))
	   (vendor-id (slot-value vendor 'row-id))
	   (tenant-id (slot-value company 'row-id))
	   (OrderItemdbobj (get-order-items-by-product-id prd-id order-id tenant-id))
	   (domainobj (make-instance 'OrderItem)))
    ;; FIELD UPDATE CODE STARTS HERE 
    (when OrderItemdbobj 
      (setf (slot-value OrderItemdbobj 'vendor-id) vendor-id)
      (setf (slot-value OrderItemdbobj 'prd-qty) prd-qty)
      (setf (slot-value OrderItemdbobj 'unit-price) unit-price)
      (setf (slot-value OrderItemdbobj 'disc-rate) disc-rate)
      (setf (slot-value OrderItemdbobj 'cgst) cgst)
      (setf (slot-value OrderItemdbobj 'sgst) sgst)
      (setf (slot-value OrderItemdbobj 'igst) igst)
      (setf (slot-value OrderItemdbobj 'addl-tax1-rate) addl-tax1-rate)
      (setf (slot-value OrderItemdbobj 'comments) comments)
      (setf (slot-value OrderItemdbobj 'fulfilled) fulfilled)
      (setf (slot-value OrderItemdbobj 'status) status)
      (setf (slot-value OrderItemdbobj 'deleted-state) deleted-state))
       
     ;;  FIELD UPDATE CODE ENDS HERE. 
    
    (setf (slot-value OrderItemdbservice 'dbobject) OrderItemdbobj)
    (setf (slot-value OrderItemdbservice 'businessobject) domainobj)
    
    (setcompany OrderItemdbservice company)
    (db-save OrderItemdbservice)
    ;; Return the newly created UPI domain object
    (copyOrderItem-dbtodomain OrderItemdbobj domainobj))))


;; PROCESS THE READ REQUEST
(defmethod ProcessReadRequest ((adapter OrderItemAdapter) (requestmodel OrderItemRequestModel))
  :description "Adapter service method to read a single OrderItem.
   中文：Read 流的 Adapter 钩子，绑定 OrderItemService 后委托父类。"
  (setf (slot-value adapter 'businessservice) (find-class 'OrderItemService))
  (call-next-method))

(defmethod doread ((service OrderItemService) (requestmodel OrderItemRequestModel))
  "中文：单条读取：按 row-id 查 DB 行项，然后 copyOrderItem-dbtodomain 转领域对象。
   注意 company / order 由 requestmodel 直接提供，无需重新查。"
  (let* ((row-id (row-id requestmodel))
	 (company (company requestmodel))
	 (order (order requestmodel))
	 (dbOrderItem (get-order-item-by-id row-id))
	 (OrderItemobj (make-instance 'OrderItem)))
    ;; return back a Vpaymentmethod  response model
    (setf (slot-value OrderItemobj 'company) company)
    (setf (slot-value OrderItemobj 'order) order) 
    (copyOrderItem-dbtodomain dbOrderItem OrderItemobj)))


(defun copyOrderItem-dbtodomain (source destination)
  "中文：DB 对象 → 领域对象。把外键 *-id 还原成实体（通过 select-* 查询）：
   tenant-id → company；prd-id → product；order-id → order；vendor-id → vendor。
   返回填充好的 destination 实例。"
  (let* ((dbcomp (select-company-by-id (slot-value source 'tenant-id)))
	 (prd-id (slot-value source 'prd-id))
	 (dbproduct (select-product-by-id prd-id dbcomp))
	 (dborder (get-order-by-id (slot-value source 'order-id) dbcomp))
	 (dbvend (select-vendor-by-id (slot-value source 'vendor-id))))
    (with-slots (row-id order product vendor prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state company) destination
      (setf vendor dbvend)
      (setf product dbproduct)
      (setf order dborder)
      (setf company dbcomp)
      (setf row-id (slot-value source 'row-id))
      (setf prd-qty (slot-value source 'prd-qty))
      (setf unit-price (slot-value source 'unit-price))
      (setf disc-rate (slot-value source 'disc-rate))
      (setf cgst (slot-value source 'cgst))
      (setf sgst (slot-value source 'sgst))
      (setf igst (slot-value source 'igst))
      (setf addl-tax1-rate (slot-value source 'addl-tax1-rate))
      (setf comments (slot-value source 'comments))
      (setf fulfilled (slot-value source 'fulfilled))
      (setf status (slot-value source 'status))
      (setf deleted-state (slot-value source 'deleted-state))
      destination)))

