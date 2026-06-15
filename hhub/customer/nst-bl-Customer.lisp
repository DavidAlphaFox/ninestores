;;; nst-bl-Customer.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：customer 客户（新风格 nst-，DDD/Hexagonal）
;;;; 分层：BL（业务逻辑层 — 领域服务方法实现）
;;;; 文件：hhub/customer/nst-bl-Customer.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：为 nst-dal-Customer.lisp 中声明的服务/视图/模型类实现 CLOS 方法，
;;;;       串起六边形架构里的 Adapter → Service → DBService 流程，覆盖客户
;;;;       Create / Read / ReadAll / Update 用例，以及 Presenter 的 ResponseModel
;;;;       → ViewModel 转换、JSONView 渲染。
;;;;
;;;; 主要导出：
;;;;   ProcessCreateRequest / ProcessReadRequest / ProcessReadAllRequest /
;;;;   ProcessUpdateRequest             — Adapter 派发到 BusinessService
;;;;   doCreate / doread / doreadall / doupdate    — Service 用例实现
;;;;   init (CustomerDBService Customer)            — DBService 初始化
;;;;   Copy-BusinessObject-To-DBObject              — DB 对象与领域对象同步
;;;;   copyCustomer-domaintodb / copyCustomer-dbtodomain  — 字段拷贝辅助
;;;;   createCustomerobject                         — 领域对象工厂
;;;;   ProcessResponse / ProcessResponseList        — 领域对象 → ResponseModel
;;;;   CreateResponseModel / CreateViewModel / CreateAllViewModel — Presenter 流程
;;;;   Render (JSONView CustomerViewModel)          — 输出 JSON（地址 AJAX 接口）
;;;;
;;;; 关联：
;;;;   上游使用方：customer/nst-ui-Customer.lisp（控制器）。
;;;;   下游依赖：nst-dal-Customer.lisp（类壳）、core 调度管线、
;;;;             dod-bl-cus.lisp 中的 select-customer-by-phone /
;;;;             select-customers-for-company（DAL 查询），select-company-by-id。
;;;;
;;;; 备注：文件顶部原英文注释提示这是\"模板代码\"，不要在批量编译中混入。
;;;;       推测：曾有 PAP 自动生成机制；目前文件已成为正式实现并可加载。
;;;; ============================================================================

(in-package :nstores)

;; METHODS FOR ENTITY CREATE
;; This file contains template code which will be used to generate for class methods.
;; DO NOT COMPILE THIS FILE USING CTRL + C CTRL + K (OR CTRL + CK)
;; DO NOT ADD THIS FILE TO COMPILE.LISP FOR MASS COMPILATION.


(defmethod ProcessCreateRequest ((adapter CustomerAdapter) (requestmodel CustomerRequestModel))
  :description  "Original English. 中文：CustomerAdapter 处理 Create 请求 —— 把
   businessservice 槽设为 CustomerService 类，再 call-next-method 走父类通用流程
   (parent ProcessCreate)。返回值由父类决定（应是新建的 Customer 领域对象）。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'CustomerService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod init ((dbas CustomerDBService) (bo Customer))
  :description "Original English. 中文：初始化 CustomerDBService —— 创建 DB 表对象壳、
   绑定领域对象 bo，再设置租户上下文 setcompany。
   注意：源码这里 make-instance 'database-table-object-name-here 是模板占位符
   （应为 dod-cust-profile，推测：模板未替换，运行到本路径时会报 class-not-found 错；
    实际项目里是否经过此处尚未确定）。
   call-next-method 走父类公共初始化。"
  (let* ((DBObj  (make-instance 'database-table-object-name-here)))
    ;; Set specific fields of the DB object if you need to. 
    ;; End set specific fields of the DB object. 
    (setf (dbobject dbas) DBObj)
    ;; Set the company context for the UPI payments DB service 
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))



(defmethod doCreate ((service CustomerService) (requestmodel CustomerRequestModel))
  "CustomerService 创建用例：从 requestmodel 抽出全部客户字段 + vendor/customer 上下文，
   通过 createCustomerobject 构造领域对象，再用 CustomerDBService init → 拷字段 →
   db-save 写库。返回新建的 Customer 领域对象。
   注：requestmodel 上的 vendor / customer slot 不在 nst-dal 声明的 CustomerRequestModel
       中（应是父类或运行期 setf 进去的，推测）。"
  (let* ((Customerdbservice (make-instance 'CustomerDBService))
	 (vendor (vendor requestmodel))
	 (customer (customer requestmodel))
	 (row-id (row-id requestmodel))
	 (name (name requestmodel))
	 (address (address requestmodel))
	 (phone (phone requestmodel))
	 (email (email requestmodel))
	 (firstname (firstname requestmodel))
	 (lastname (lastname requestmodel))
	 (salutation (salutation requestmodel))
	 (title (title requestmodel))
	 (birthdate (birthdate requestmodel))
	 (city (city requestmodel))
	 (state (state requestmodel))
	 (country (country requestmodel))
	 (zipcode (zipcode requestmodel))
	 (picture-path (picture-path requestmodel))
	 (password (password requestmodel))
	 (salt (salt requestmodel))
	 (cust-type (cust-type requestmodel))
	 (email-add-verified (email-add-verified requestmodel))
	 (company (company requestmodel))
	 (domainobj (createCustomerobject row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path password salt cust-type email-add-verified vendor customer company )))
         ;; Initialize the DB Service
    (init Customerdbservice domainobj)
    (copy-businessobject-to-dbobject Customerdbservice)
    (db-save Customerdbservice)
    ;; Return the newly created warehouse domain object
    domainobj))


(defun createCustomerobject (row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path password salt cust-type email-add-verified vendor customer company)
  "工厂函数：把所有客户字段 + vendor / customer 上下文一次性 :initarg 给 Customer 类，
   并默认 deleted-state='N'、active-flag='Y'。
   返回：新构造的 Customer 实例。"
  (let* ((domainobj  (make-instance 'Customer
				       :row-id row-id
				       :name name
				       :address address
				       :phone phone
				       :email email
				       :firstname firstname
				       :lastname lastname
				       :salutation salutation
				       :title title
				       :birthdate birthdate
				       :city city 
				       :state state
				       :country country
				       :zipcode zipcode
				       :picture-path picture-path
				       :password password
				       :salt salt
				       :cust-type cust-type
				       :email-add-verified email-add-verified
				       :deleted-state "N"
				       :active-flag "Y"
				       :vendor vendor
				       :customer customer
				       :company company)))
    domainobj))

(defmethod Copy-BusinessObject-To-DBObject ((dbas CustomerDBService))
  :description "Original English. 中文：把 DBService 中的领域对象字段拷到 DB 对象上，
   保证写库时使用最新值。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyCustomer-domaintodb domainobj dbobj))))

;; source = domain destination = db
(defun copyCustomer-domaintodb (source destination)
  "把领域对象 source 上的全部客户字段拷到 DB 对象 destination，返回 destination。
   注：source/destination 字段名一致，因此通过 with-slots 分别取值。"
  (with-slots (row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path password salt cust-type email-add-verified company) destination
    (setf company (slot-value source 'company))
    (setf row-id (slot-value source 'row-id))
    (setf name (slot-value source 'name))
    (setf address (slot-value source 'address))
    (setf phone (slot-value source 'phone))
    (setf email (slot-value source 'email))
    (setf firstname (slot-value source 'firstname))
    (setf lastname (slot-value source 'lastname))
    (setf salutation (slot-value source 'salutation))
    (setf title (slot-value source 'title))
    (setf birthdate (slot-value source 'birthdate))
    (setf city (slot-value source 'city))
    (setf state (slot-value source 'state))
    (setf country (slot-value source 'country))
    (setf zipcode (slot-value source 'zipcode))
    (setf picture-path (slot-value source 'picture-path))
    (setf password (slot-value source 'password))
    (setf salt (slot-value source 'salt))
    (setf cust-type (slot-value source 'cust-type))
    (setf email-add-verified (slot-value source 'email-add-verified))
    destination))


;; PROCESS UPDATE REQUEST
(defmethod ProcessUpdateRequest ((adapter CustomerAdapter) (requestmodel CustomerRequestModel))
  :description "Original English. 中文：CustomerAdapter Update 用例派发。
   设置 businessservice 槽为 CustomerService，再 call-next-method 进入父类 ProcessUpdate。"
  (setf (slot-value adapter 'businessservice) (find-class 'CustomerService))
  ;; call the parent ProcessUpdate
  (call-next-method))

;; PROCESS READ ALL REQUEST.
(defmethod ProcessReadAllRequest ((adapter CustomerAdapter) (requestmodel CustomerRequestModel))
  :description "Original English mentions UPI Payments. 中文：CustomerAdapter ReadAll
   用例派发 —— 设置 CustomerService 后委托给父类。
   注：原英文 docstring 写 \"UPI Payments\" 应是从 UPI 模块复制粘贴的笔误。"
  (setf (slot-value adapter 'businessservice) (find-class 'CustomerService))
  (call-next-method))

(defmethod doreadall ((service CustomerService) (requestmodel CustomerRequestModel))
  "CustomerService ReadAll 用例：取 requestmodel 中的 company，调 DAL
   select-customers-for-company 拿到 dod-cust-profile 列表，再逐条复制为 Customer
   领域对象返回。"
  (let* ((comp (company requestmodel))
	 (domainobjlst (select-customers-for-company comp)))
    ;; return back a list of domain objects 
    (mapcar (lambda (object)
	      (let ((domainobject (make-instance 'Customer)))
		(copyCustomer-dbtodomain object domainobject))) domainobjlst)))

;; ----------------------------------------------------------------------------
;; Presenter：把 ResponseModel 投影成 ViewModel。下面三个 NIL/Unknown/Contradiction
;; 变体把容错路径委托给父类（视图层会渲染相应的容错页面）。
;; ----------------------------------------------------------------------------
(defmethod CreateViewModel ((presenter CustomerPresenter) (responsemodel ResponseModelNIL))
  "ResponseModelNIL 路径：业务无结果，委托父类生成 ViewModelNIL。"
  (call-next-method))

(defmethod CreateViewModel ((presenter CustomerPresenter) (responsemodel ResponseModelUnknown))
  "ResponseModelUnknown 路径：业务结果未知，委托父类生成 ViewModelUnknown。"
  (call-next-method))

(defmethod CreateViewModel ((presenter CustomerPresenter) (responsemodel ResponseModelContradiction))
  "ResponseModelContradiction 路径：业务结果矛盾，委托父类生成 ViewModelContradiction。"
  (call-next-method))

(defmethod CreateViewModel ((presenter CustomerPresenter) (responsemodel CustomerResponseModel))
  "把 CustomerResponseModel 全部公开字段拷到一个新建的 CustomerViewModel 上返回。
   不含 password / salt（响应模型本身就不携带，避免外泄到视图层）。"
  (let ((viewmodel (make-instance 'CustomerViewModel)))
    (with-slots (row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path cust-type email-add-verified  company ) responsemodel
      (setf (slot-value viewmodel 'row-id) row-id)
      (setf (slot-value viewmodel 'name) name)
      (setf (slot-value viewmodel 'address) address)
      (setf (slot-value viewmodel 'phone) phone)
      (setf (slot-value viewmodel 'email) email)
      (setf (slot-value viewmodel 'firstname) firstname)
      (setf (slot-value viewmodel 'lastname) lastname)
      (setf (slot-value viewmodel 'salutation) salutation)
      (setf (slot-value viewmodel 'title) title)
      (setf (slot-value viewmodel 'birthdate) birthdate)
      (setf (slot-value viewmodel 'city) city)
      (setf (slot-value viewmodel 'state) state)
      (setf (slot-value viewmodel 'country) country)
      (setf (slot-value viewmodel 'zipcode) zipcode)
      (setf (slot-value viewmodel 'picture-path) picture-path)
      (setf (slot-value viewmodel 'cust-type) cust-type)
      (setf (slot-value viewmodel 'email-add-verified) email-add-verified)
      (setf (slot-value viewmodel 'company) company)
      viewmodel)))
  

(defmethod ProcessResponse ((adapter CustomerAdapter) (busobj Customer))
  "把单个 Customer 领域对象转成 CustomerResponseModel（用 createresponsemodel 拷字段）。"
  (let ((responsemodel (make-instance 'CustomerResponseModel)))
    (setf responsemodel (createresponsemodel adapter busobj responsemodel))
    responsemodel))
(defmethod ProcessResponse ((adapter CustomerAdapter) (busobj BusinessObjectNIL))
  "领域对象为空（NIL）时委托父类生成 ResponseModelNIL。"
  (call-next-method))

(defmethod ProcessResponseList ((adapter CustomerAdapter) Customerlist)
  "把 Customer 领域对象列表批量转换为 CustomerResponseModel 列表。"
  (mapcar (lambda (domainobj)
	    (let ((responsemodel (make-instance 'CustomerResponseModel)))
	      (createresponsemodel adapter domainobj responsemodel))) Customerlist))

(defmethod CreateAllViewModel ((presenter CustomerPresenter) responsemodellist)
  "把 ResponseModel 列表批量交给 createviewmodel 转换为 ViewModel 列表。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))

(defmethod CreateResponseModel ((adapter CustomerAdapter) (source Customer) (destination ResponseModelNIL))
  "ResponseModelNIL 容错分支：委托父类。"
  (call-next-method))

(defmethod CreateResponseModel ((adapter CustomerAdapter) (source Customer) (destination ResponseModelUnknown))
  "ResponseModelUnknown 容错分支：委托父类。"
  (call-next-method))

(defmethod CreateResponseModel ((adapter CustomerAdapter) (source Customer) (destination ResponseModelContradiction))
  "ResponseModelContradiction 容错分支：委托父类。"
  (call-next-method))


(defmethod CreateResponseModel ((adapter CustomerAdapter) (source Customer) (destination CustomerResponseModel))
  :description "Original English. 中文：把 Customer 领域对象 source 的字段拷到
   CustomerResponseModel destination 上（不含 password/salt，避免外泄）。返回 destination。"
  (with-slots (row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path  cust-type email-add-verified company) destination  
    (setf row-id (slot-value source 'row-id))
    (setf name (slot-value source 'name))
    (setf address (slot-value source 'address))
    (setf phone (slot-value source 'phone))
    (setf email (slot-value source 'email))
    (setf firstname (slot-value source 'firstname))
    (setf lastname (slot-value source 'lastname))
    (setf salutation (slot-value source 'salutation))
    (setf title (slot-value source 'title))
    (setf birthdate (slot-value source 'birthdate))
    (setf city (slot-value source 'city))
    (setf state (slot-value source 'state))
    (setf country (slot-value source 'country))
    (setf zipcode (slot-value source 'zipcode))
    (setf picture-path (slot-value source 'picture-path))
    (setf cust-type (slot-value source 'cust-type))
    (setf email-add-verified (slot-value source 'email-add-verified))
    (setf company (slot-value source 'company))
    destination))

(defmethod doupdate ((service CustomerService) (requestmodel CustomerRequestModel))
  "CustomerService 更新用例：以 phone+company 为业务键去 DAL 找已存在的 dod-cust-profile，
   把 requestmodel 字段写到该 DB 对象上，再 db-save。
   返回：刷新后映射回 Customer 领域对象的实例。
   备注：业务键依赖 phone+company 是 Nine Stores 客户的天然唯一约束。"
  (with-slots (row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path password salt cust-type email-add-verified  company) requestmodel
  (let* ((Customerdbservice (make-instance 'CustomerDBService))
	 (Customerdbobj (select-customer-by-phone phone company))
	 (domainobj (make-instance 'Customer)))
    ;; FIELD UPDATE CODE STARTS HERE 
    (when Customerdbobj 
      (setf (slot-value Customerdbobj 'row-id) row-id)
      (setf (slot-value Customerdbobj 'name) name)
      (setf (slot-value Customerdbobj 'address) address)
      (setf (slot-value Customerdbobj 'phone) phone)
      (setf (slot-value Customerdbobj 'email) email)
      (setf (slot-value Customerdbobj 'firstname) firstname)
      (setf (slot-value Customerdbobj 'lastname) lastname)
      (setf (slot-value Customerdbobj 'salutation) salutation)
      (setf (slot-value Customerdbobj 'title) title)
      (setf (slot-value Customerdbobj 'birthdate) birthdate)
      (setf (slot-value Customerdbobj 'city) city)
      (setf (slot-value Customerdbobj 'state) state)
      (setf (slot-value Customerdbobj 'country) country)
      (setf (slot-value Customerdbobj 'zipcode) zipcode)
      (setf (slot-value Customerdbobj 'picture-path) picture-path)
      (setf (slot-value Customerdbobj 'password) password)
      (setf (slot-value Customerdbobj 'salt) salt)
      (setf (slot-value Customerdbobj 'cust-type) cust-type)
      (setf (slot-value Customerdbobj 'email-add-verified) email-add-verified))

     ;;  FIELD UPDATE CODE ENDS HERE. 
    
    (setf (slot-value Customerdbservice 'dbobject) Customerdbobj)
    (setf (slot-value Customerdbservice 'businessobject) domainobj)
    
    (setcompany Customerdbservice company)
    (db-save Customerdbservice)
    ;; Return the newly created UPI domain object
    (copyCustomer-dbtodomain Customerdbobj domainobj))))


;; PROCESS THE READ REQUEST
(defmethod ProcessReadRequest ((adapter CustomerAdapter) (requestmodel CustomerRequestModel))
  :description "Original English. 中文：CustomerAdapter Read 用例派发，设置
   CustomerService 后委托父类。"
  (setf (slot-value adapter 'businessservice) (find-class 'CustomerService))
  (call-next-method))

(defmethod doread ((service CustomerService) (requestmodel CustomerRequestModel))
  "CustomerService 单读用例：以 phone+company 调 DAL，并用 with-db-call 把结果包成
   bo-knowledge（含 truth value: T/F/U/C — 配合容错视图）。
   命中（T）时把 dod-cust-profile 拷到 Customer 领域对象、把 payload 替换为该领域对象返回。
   未命中：service 上的 bo-knowledge 仍被设置，让上层选择对应的 NIL/Unknown 视图。"
  (let* ((comp (company requestmodel))
	 (phone (phone requestmodel))
	 (dbCustomerKnowledge (with-db-call (select-customer-by-phone phone comp) "DB/Customer"))
	 (Customerobj (make-instance 'Customer)))
    (setf (bo-knowledge service) dbCustomerKnowledge)
    (setf (slot-value Customerobj 'company) comp)
    (when (eq (bo-knowledge-truth dbCustomerKnowledge) :T)
      (let ((dbCustomer (bo-knowledge-payload dbCustomerKnowledge)))
	(copyCustomer-dbtodomain dbCustomer Customerobj)
	;; set the bo knowledget payload as the domain object
	(setf (bo-knowledge-payload dbCustomerKnowledge) Customerobj)
	Customerobj))))


(defun copyCustomer-dbtodomain (source destination)
  "把 dod-cust-profile（DB 实体）source 上的所有字段拷到 Customer 领域对象 destination。
   tenant-id → company：用 select-company-by-id 把 tenant-id 解引用为 dod-company 实例
   写入 company slot，免得视图层再查库。返回 destination。"
  (let* ((comp (select-company-by-id (slot-value source 'tenant-id))))
    (with-slots (row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path password salt cust-type email-add-verified  company) destination
      (setf company comp)
      (setf row-id (slot-value source 'row-id))
      (setf name (slot-value source 'name))
      (setf address (slot-value source 'address))
      (setf phone (slot-value source 'phone))
      (setf email (slot-value source 'email))
      (setf firstname (slot-value source 'firstname))
      (setf lastname (slot-value source 'lastname))
      (setf salutation (slot-value source 'salutation))
      (setf title (slot-value source 'title))
      (setf birthdate (slot-value source 'birthdate))
      (setf city (slot-value source 'city))
      (setf state (slot-value source 'state))
      (setf country (slot-value source 'country))
      (setf zipcode (slot-value source 'zipcode))
      (setf picture-path (slot-value source 'picture-path))
      (setf password (slot-value source 'password))
      (setf salt (slot-value source 'salt))
      (setf cust-type (slot-value source 'cust-type))
      (setf email-add-verified (slot-value source 'email-add-verified))
      destination)))

;; ----------------------------------------------------------------------------
;; Render：视图渲染。NIL/Unknown/Contradiction 委托父类的容错视图，CustomerViewModel
;; 在 JSONView 上实现地址 JSON 输出（被前端结算页 AJAX 拉取地址）。
;; ----------------------------------------------------------------------------
(defmethod Render ((view View) (viewmodel ViewModelNIL))
  "ViewModelNIL：委托父类渲染（应是 \"Record Not Found\" 或空响应，推测）。"
  (call-next-method))

(defmethod Render ((view View) (viewmodel ViewModelUnknown))
  "ViewModelUnknown：委托父类渲染容错视图。"
  (call-next-method))

(defmethod Render ((view View) (viewmodel ViewModelContradiction))
  "ViewModelContradiction：委托父类渲染容错视图。"
  (call-next-method))

(defmethod Render ((view JSONView) (viewmodel CustomerViewModel))
  "把 CustomerViewModel 渲染为前端结算页可用的地址 JSON：
   {\"success\": 1|0, \"addresses\": [{...}]}。
   字段齐备（phone+city+state+zipcode 都有）则 success=1，否则 success=0、addresses=[]。
   返回：JSON 字符串；并把它存到 view.jsondata slot 以便 dispatcher 取出写回响应。"
  (let* ((templist '())
         (appendlist '())
         (mylist '())
         (firstname (slot-value viewmodel 'firstname))
         (lastname (slot-value viewmodel 'lastname))
	 (custname (slot-value viewmodel 'name))
	 (email (slot-value viewmodel 'email))
	 (address (slot-value viewmodel 'address))
         (phone (slot-value viewmodel 'phone))
         (city (slot-value viewmodel 'city))
         (state (slot-value viewmodel 'state))
         (zipcode (slot-value viewmodel 'zipcode)))

    ;; If minimum address fields exist
    (if (and phone city state zipcode)
        (progn
          ;; Combine first + last name as "name"
	  (setf templist (acons "custname" (format nil "~A" custname) templist))
	  (setf templist (acons "fullname"
                                (format nil "~A ~A"
                                        (or firstname "")
                                        (or lastname ""))
                                templist))
	  (setf templist (acons "email" (format nil "~A" email) templist))
          (setf templist (acons "address"  (format nil "~A" address) templist))
          (setf templist (acons "city"     (format nil "~A" city)    templist))
          (setf templist (acons "state"    (format nil "~A" state)   templist))
          (setf templist (acons "zipcode"  (format nil "~A" zipcode) templist))
          (setf templist (acons "phone"    (format nil "~A" phone)   templist))

          (push templist appendlist)

          ;; API format expected by JS
          (setf mylist (acons "addresses" appendlist mylist))
          (setf mylist (acons "success" 1 mylist)))

        ;; Else: failure response
        (progn
          (setf mylist (acons "addresses" '() mylist))
          (setf mylist (acons "success" 0 mylist))))

    ;; Encode JSON
    (let ((jsondata (json:encode-json-to-string mylist)))
      (setf (slot-value view 'jsondata) jsondata)
      jsondata)))


