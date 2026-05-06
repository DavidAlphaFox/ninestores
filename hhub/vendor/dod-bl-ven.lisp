;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家档案业务逻辑（含审批 / CRUD / 多租户绑定）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/vendor/dod-bl-ven.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：vendor 模块业务函数与方法实现：
;;;;       - DTO ↔ Domain ↔ DB 三向拷贝（copyvendor-domaintodb / copyvendor-dbtodomain）
;;;;       - 审批流（doupdate VendorApprovalService、reject-vendor）
;;;;       - 服务层方法分派：ProcessCreateRequest / ProcessUpdateRequest /
;;;;         ProcessReadAllRequest 等到对应 BusinessService
;;;;       - 直接 DAL 包装：select-vendor-by-* / create-vendor / delete-vendor /
;;;;         update-vendor-details / reset-vendor-password / update-vendor-payment-params
;;;;       - DOD_VENDOR_TENANTS 桥表：create-vendor-tenant / get-vendor-tenants /
;;;;         get-vendor-tenants-as-companies
;;;;
;;;; 主要导出：
;;;;   reject-vendor / get-vendors-for-approval
;;;;   select-vendors-for-company / select-vendor-by-id / select-vendor-by-email /
;;;;     select-vendor-by-name / select-vendors-by-name
;;;;   reset-vendor-password / update-vendor-payment-params / update-vendor-details
;;;;   create-vendor / delete-vendor / delete-vendors / restore-deleted-vendors
;;;;   create-vendor-tenant / delete-vendor-tenant /
;;;;     get-vendor-tenants / get-vendor-tenants-as-companies
;;;;
;;;; 关联：
;;;;   上游使用方：vendor/dod-ui-ven.lisp、order/customer 模块（取卖家信息）。
;;;;   下游依赖：vendor/dod-dal-ven.lisp（实体）、account/dod-bl-cmp.lisp
;;;;             （select-company-by-id）、core 加密工具（hhub-random-password、
;;;;             createciphersalt、check&encrypt）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

(defmethod ProcessUpdateRequest ((adapter VendorApprovalAdapter) (requestmodel RequestModelVendorApproval))
  :description "Adapter service method to call the BusinessService Update method.
   中文：把 VendorApprovalAdapter 的 BusinessService 设为 VendorApprovalService，
   再委托父类 ProcessUpdateRequest 完成实际审批 doupdate 调用。"
  (setf (slot-value adapter 'businessservice) (find-class 'VendorApprovalService))
  ;; call the parent ProcessCreate
  (call-next-method))

(defmethod doupdate ((service VendorApprovalService) (requestmodel RequestModelVendorApproval))
  "审批通过的执行方法：把 vendor 标记为 approved-flag='Y'、approval-status='APPROVED'、
   approved-by 写为 companyadmin 的 phone-mobile，然后通过 VendorDBService 落库。
   返回：copy-DBObject-To-BusinessObject 的结果（在 dbas 上）。
   副作用：UPDATE DOD_VEND_PROFILE。"
  (let* ((dbas (make-instance 'vendorDBService))
	 (vendor-id (slot-value requestmodel 'vendor-id))
	 (companyadmin (slot-value requestmodel 'companyadmin))
	 (approved-by-phone (slot-value companyadmin 'phone-mobile))
	 (dbvendor (select-vendor-by-id vendor-id))
	 (company (get-vendor-company dbvendor))
	 (vendor (make-instance 'vendor)))
    
    (setf (slot-value dbvendor 'approved-flag) "Y")
    (setf (slot-value dbvendor 'approval-status) "APPROVED")
    (setf (slot-value dbvendor 'approved-by) approved-by-phone)
    (setf (slot-value dbas 'dbobject) dbvendor)
    (setf (slot-value dbas 'businessobject) vendor)
    ;; initialise the dbservice with vendor object. 
    (setcompany dbas company)
    (db-save dbas)
    (Copy-DBObject-To-BusinessObject dbas)))
    
(defun reject-vendor (vendor companyadmin)
  "审批拒绝：把 vendor 置为 approved-flag='N'、approval-status='REJECTED'，
   approved-by 记录拒绝者手机号，通过 VendorDBService 落库。
   副作用：UPDATE DOD_VEND_PROFILE。"
  (let ((dbas (make-instance 'vendorDBService))
	(rejected-by-phone (slot-value companyadmin 'phone)))
	
    (setf (slot-value vendor 'approved-flag) "N")
    (setf (slot-value vendor 'approval-status) "REJECTED")
    (setf (slot-value vendor 'approved-by) rejected-by-phone)
    ;; initialise the dbservice with vendor object. 
    (init dbas vendor)
    (Copy-BusinessObject-To-DBObject dbas)
    (db-save dbas)))
    

(defmethod init ((dbas vendorDBService) (bo vendor))
  :description "Set the DB object and domain object.
   中文：初始化 VendorDBService —— 创建一个空的 dod-vend-profile DB 实例挂到 dbas 上，
   再 call-next-method 让父类完成 businessobject + company 上下文初始化。"
  (let* ((vendorDBObj  (make-instance 'dod-vend-profile)))

    (setf (dbobject dbas) vendorDBObj)
    ;; Set the company context for the vendor db service 
    (call-next-method)))


(defmethod Copy-BusinessObject-To-DBObject ((dbas vendorDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：把 businessobject（Vendor）字段同步进 dbobject（dod-vend-profile）。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(businessobject (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyvendor-domaintodb businessobject dbobj))))

(defmethod Copy-DBObject-To-BusinessObject ((dbas vendorDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：把 dbobject（dod-vend-profile）字段同步进 businessobject（Vendor）。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(businessobject (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyvendor-dbtodomain dbobj  businessobject))))

  
(defun copyvendor-domaintodb (businessobj dbobj)
  "把 Vendor 业务对象的字段写入 dod-vend-profile 数据库对象。
   注意：仅同步审批/账号相关常用字段，不含 GST、地址全集字段（需要时由调用方补）。
   返回：更新后的 dbobj。"
  (let* ((company (slot-value businessobj 'company))
	 (tid (slot-value company 'row-id)))
    (with-slots
	  (row-id name address phone email  email-add-verified suspend-flag active-flag approved-flag approval-status approved-by upi-id tenant-id) dbobj
      (setf row-id (slot-value businessobj 'row-id))
      (setf (slot-value dbobj 'salt) (slot-value businessobj 'salt))
      (setf name (slot-value businessobj 'name))
      (setf address (slot-value businessobj 'address))
      (setf phone (slot-value businessobj 'phone))
      (setf email (slot-value businessobj 'email))
      (setf (slot-value dbobj 'password) (slot-value businessobj 'password))
      (setf email-add-verified (slot-value businessobj 'email-add-verified))
      (setf suspend-flag (slot-value businessobj 'suspend-flag))
      (setf active-flag (slot-value businessobj 'active-flag))
      (setf approved-flag (slot-value businessobj 'approved-flag))
      (setf approval-status (slot-value businessobj 'approval-status))
      (setf approved-by (slot-value businessobj 'approved-by))
      (setf upi-id (slot-value businessobj 'upi-id))
      (setf tenant-id tid)
      dbobj)))


(defun copyvendor-dbtodomain (dbobj businessobj)
  "把 dod-vend-profile 数据库对象字段写入 Vendor 业务对象，并把 tenant-id 解析为
   company 实例挂到 businessobj.company 上。返回：更新后的 businessobj。"
  (let* ((comp (select-company-by-id (slot-value dbobj 'tenant-id))))
    (with-slots (row-id name address phone email  email-add-verified suspend-flag active-flag approved-flag approval-status approved-by upi-id company) businessobj
      (setf row-id (slot-value dbobj 'row-id))
      (setf name (slot-value dbobj 'name))
      (setf address (slot-value dbobj 'address))
      (setf phone (slot-value dbobj 'phone))
      (setf email (slot-value dbobj 'email))
      (setf (slot-value businessobj 'password) (slot-value dbobj 'password))
      (setf (slot-value businessobj 'salt) (slot-value dbobj 'salt))
      (setf email-add-verified (slot-value dbobj 'email-add-verified))
      (setf suspend-flag (slot-value dbobj 'suspend-flag))
      (setf active-flag (slot-value dbobj 'active-flag))
      (setf approved-flag (slot-value dbobj 'approved-flag))
      (setf approval-status (slot-value dbobj 'approval-status))
      (setf approved-by (slot-value dbobj 'approved-by))
      (setf upi-id (slot-value dbobj 'upi-id))
      (setf company comp)
      businessobj)))

(defmethod ProcessCreateRequest ((adapter VendorAdapter) (requestmodel RequestVendor))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created vendor object.
   中文：把 VendorAdapter 的 BusinessService 设为 VendorProfileService，
   再委托父类做 dispatch 调用 doCreate。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'VendorProfileService))
  ;; call the parent ProcessCreate
  (call-next-method))

(defmethod ProcessUpdateRequest ((adapter VendorAdapter) (requestmodel RequestVendor))
  :description "Adapter service method to call the BusinessService Update method.
   中文：设定 BusinessService 为 VendorProfileService 并 call-next-method。"
  (setf (slot-value adapter 'businessservice) (find-class 'VendorProfileService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod ProcessReadAllRequest ((adapter VendorAdapter) (requestmodel RequestVendor))
  :description "Adapter service method to read the upi payments.
   中文：原英文 'upi payments' 系笔误（应为 vendor 列表）；
   实际把 BusinessService 设为 VendorProfileService 后委托父类调用 doreadall。"
  (setf (slot-value adapter 'businessservice) (find-class 'VendorProfileService))
  (call-next-method))

(defmethod doreadall ((service VendorProfileService) (requestmodel RequestVendor))
  "列出某 company（租户）下的全部 vendor，并把每个 dod-vend-profile 拷贝为 Vendor 业务对象。
   返回：Vendor 实例列表。"
  (let* ((comp (slot-value requestmodel 'company))
	 (vendorlist (select-vendors-for-company comp)))
	
    ;; return back a list of upi payments response model
    (mapcar (lambda (dbvendor)
	      (let ((vendor (make-instance 'vendor)))
		(copyvendor-dbtodomain dbvendor vendor))) vendorlist)))
        

(defmethod CreateViewModel ((presenter VendorPresenter) (responsemodel ResponseVendor))
  "把 ResponseVendor 拷贝到 VendorViewModel 后返回。
   备注：函数签名虽创建 viewmodel，但末尾返回的仍是 responsemodel
        （推测：原作者笔误，应返回 viewmodel；保留原行为不动）。"
  (let ((viewmodel (make-instance 'VendorViewModel)))
    (with-slots (vendor customer amount utrnum transaction-id status vendorconfirm company created) responsemodel
      (setf (slot-value viewmodel 'vendor) vendor)
      (setf (slot-value viewmodel 'customer) customer)
      (setf (slot-value viewmodel 'amount) amount)
      (setf (slot-value viewmodel 'utrnum) utrnum)
      (setf (slot-value viewmodel 'transaction-id) transaction-id)
      (setf (slot-value viewmodel 'status) status)
      (setf (slot-value viewmodel 'vendorconfirm) vendorconfirm)
      (setf (slot-value viewmodel 'company) company)
      (setf (slot-value viewmodel 'created) created)
      responsemodel)))


(defmethod ProcessResponseList ((adapter VendorAdapter) vendorlist)
  "把 Vendor 业务对象列表批量转为 ResponseVendor 列表（每条调 createresponsemodel）。"
  (mapcar (lambda (vendor)
	    (let ((responsemodel (make-instance 'ResponseVendor)))
	      (createresponsemodel adapter vendor  responsemodel))) vendorlist))
  

(defmethod CreateAllViewModel ((presenter VendorPresenter) responsemodellist)
  "批量把 ResponseVendor 列表转为 VendorViewModel 列表。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))



(defmethod CreateResponseModel ((adapter UpiPaymentsAdapter) (source UpiPayment) (destination UpiPaymentsResponseModel))
  :description "source = upipayment destination = upipaymentresponsemodel.
   中文：注意——这条方法虽然写在 vendor 文件里，但分派的是 UpiPaymentsAdapter 与
   UpiPayment 类型（属于 upi 模块）。它把 UpiPayment 业务对象拷贝到响应 DTO。
   推测：原作者把方法误写到此文件；保留位置不动避免影响装载顺序。"
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



;;; Method implementation for DBAdapterService
(defmethod db-fetch ((dbas vendorDBService) row-id)
  :description  "Fetch the DBObject based on row-id.
   中文：按 row-id 取出 dod-vend-profile，赋给 dbas.dbobject，
   并把它复制到 dbas.businessobject（Vendor 实例）。"
  (let ((dbvendor (select-vendor-by-id row-id))
	(vendor (businessobject dbas)))
    (setf (dbobject dbas) dbvendor)
    (setf (businessobject dbas) (copyvendor-dbtodomain dbvendor vendor)))) 

(defmethod db-delete ((dbas vendorDBService))
  :description "Will be implementd by the derived class objects.
   中文：实际实现——从 dbas.dbobject 取 vendor row-id 与 company，调 delete-vendor 软删。"
  (let* ((dbvendor (slot-value  dbas 'dbobject))
	(dbcompany (slot-value dbvendor 'company))
	(id (slot-value dbvendor 'row-id)))
    (delete-vendor id dbcompany)))


(defmethod select-vendor-by-phone ((dbas VendorDBService) phone)
  "按手机号查询单个有效 vendor（active-flag='Y' 且未软删），并把结果挂到 dbas.dbobject。
   返回：dod-vend-profile 实例 / nil。注意：未限定 tenant_id，跨租户取第一条。"
  (let ((dbvendor (car (clsql:select 'dod-vend-profile  :where
		       [and [= [:deleted-state] "N"]
		       [= [:phone] phone]
		       [= [:active-flag] "Y"]]
		       :caching nil :flatp t ))))
    (setf (slot-value dbas 'dbobject) dbvendor)
    dbvendor))

(defun get-vendors-for-approval (tenant-id)
:documentation "This function will be used only by the company admin user.
 中文：列出某租户内待审批 vendor（active-flag='Y'、未软删、approved-flag='N'、
   approval-status='PENDING'）。供 company admin 审批列表页使用。
   备注：缓存按 *dod-database-caching* 控制。"
  (clsql:select 'dod-vend-profile  :where 
		[and 
		[= [:deleted-state] "N"] 
		[= [:active-flag] "Y"]
		[= [:approved-flag] "N"]
		[= [:tenant-id] tenant-id]
		[= [:approval-status] "PENDING"]]
		:caching *dod-database-caching* :flatp t ))



(defun select-vendors-for-company (company)
  "列出某 company（租户）下所有未软删的 vendor。返回：dod-vend-profile 列表。"
  (let ((tenant-id (slot-value company 'row-id)))
    (clsql:select 'dod-vend-profile  :where [and [= [:deleted-state] "N"] [= [:tenant-id] tenant-id]]    :caching nil :flatp t )))


(defun select-vendor-by-id (id)
  "按主键 row-id 查 vendor，未限定 tenant_id（跨租户取第一条）。"
  (car (clsql:select 'dod-vend-profile  :where
		[and [= [:deleted-state] "N"]
		[=[:row-id] id]]    :caching nil :flatp t )))



(defun select-vendor-by-email (email)
  "按邮箱查 vendor，未限定 tenant_id。
   备注：原代码注释掉了 active-flag 过滤，因此被暂停（active-flag='N'）的也能命中。"
  (car (clsql:select 'dod-vend-profile  :where
		[and [= [:deleted-state] "N"]
		;[= [:active-flag] "Y"]
		[=[:email] email]]    :caching nil :flatp t )))


(defun select-vendor-by-name (name-like-clause company)
  "按 name LIKE %xxx% 在租户内模糊查找单个 vendor。返回：第一条命中。"
  (let ((tenant-id (slot-value company 'row-id)))
  (car (clsql:select 'dod-vend-profile :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[like  [:name] (format nil "%~a%" name-like-clause)]]
		:caching nil :flatp t))))

(defun select-vendors-by-name (name-like-clause company)
  "按 name LIKE %xxx% 在租户内模糊查找全部 vendor。返回：列表。"
  (let ((tenant-id (slot-value company 'row-id)))
    (clsql:select 'dod-vend-profile :where [and
		  [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]
		  [like  [:name] (format nil "%~a%" name-like-clause)]]
				    :caching nil :flatp t)))


(defun reset-vendor-password (vendor)
  "重置 vendor 登录密码：随机生成 8 位明文 → 生成新 salt → 加密存库；
   同时 active-flag 强制置 'Y'（重置流程默认会激活之前被禁用的账号）。
   返回：新生成的明文密码（由调用方通过短信/邮件下发）。
   副作用：UPDATE DOD_VEND_PROFILE。"
  (let* ((confirmpassword (hhub-random-password 8))
	 (salt (createciphersalt))
	 (encryptedpass (check&encrypt confirmpassword confirmpassword salt)))
	  
    (setf (slot-value vendor 'password) encryptedpass)
    (setf (slot-value vendor 'salt) salt) 
    ; Whenever we reset the vendor password, we activate the vendor, as he is in-activated when this process started. 
    (setf (slot-value vendor 'active-flag) "Y") 
    (update-vendor-details  vendor )
    confirmpassword)) ; return the newly generated password. 





(defun update-vendor-payment-params (payment-api-key payment-api-salt vendor)
  "更新 vendor 在第三方支付网关的 API key/salt。副作用：UPDATE。"
  (setf (slot-value vendor 'payment-api-key) payment-api-key)
  (setf (slot-value vendor 'payment-api-salt) payment-api-salt)
  (update-vendor-details vendor))


(defun update-vendor-details (vendor-instance); This function has side effect of modifying the database record.
  "整条更新 vendor。副作用：UPDATE DOD_VEND_PROFILE。"
  (clsql:update-records-from-instance vendor-instance))

(defun delete-vendor( id company )
  "在指定租户下软删除单个 vendor（deleted-state 改 'Y'）。"
  (let ((tenant-id (slot-value company 'row-id)))
  (let ((dodvendor (car (clsql:select 'dod-vend-profile :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
    (setf (slot-value dodvendor 'deleted-state) "Y")
    (clsql:update-record-from-slot dodvendor 'deleted-state))))



(defun delete-vendors ( list company)
  "在指定租户下批量软删 vendor。list — 主键 id 列表。"
  (let ((tenant-id (slot-value company 'row-id)))
  (mapcar (lambda (id)  (let ((dodvendor (car (clsql:select 'dod-vend-profile :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
			  (setf (slot-value dodvendor 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodvendor  'deleted-state))) list )))


(defun restore-deleted-vendors ( list company )
  "在指定租户下批量恢复软删 vendor（deleted-state 改回 'N'）。"
  (let ((tenant-id (slot-value company 'row-id)))
(mapcar (lambda (id)  (let ((dodvendor (car (clsql:select 'dod-vend-profile :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
    (setf (slot-value dodvendor 'deleted-state) "N")
    (clsql:update-record-from-slot dodvendor 'deleted-state))) list )))

  
  
(defun create-vendor(name address phone email password salt city state zipcode company )
  "新建 vendor（未审批：approved-flag 默认 'N'，approval-status 默认 'PENDING'）。
   推送订阅 push-notify-subs-flag 默认 'N'，deleted-state='N'。
   副作用：INSERT DOD_VEND_PROFILE。"
  (let ((tenant-id (slot-value company 'row-id)))
 (clsql:update-records-from-instance (make-instance 'dod-vend-profile
				    :name name
				    :address address
				    :email email 
				    :password password 
				    :salt salt
				    :phone phone
				    :city city 
				    :state state 
				    :zipcode zipcode
				    :tenant-id tenant-id
				    :push-notify-subs-flag "N"
				    :deleted-state "N"))))
 

 

; DOD_VENDOR_TENANTS related functions
;; 中文：以下为 vendor ↔ tenant 桥表（DOD_VENDOR_TENANTS）的 CRUD。
;; 一个 vendor 可同时入驻多个 tenant，每个组合在桥表里一行。
(defun create-vendor-tenant (vendor default-flag company)
  "在桥表中新增一条 (vendor, tenant, default-flag) 关联。副作用：INSERT。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
    (clsql:update-records-from-instance (make-instance 'dod-vendor-tenants
						       :vendor-id vendor-id
						       :tenant-id tenant-id
						       :default-flag default-flag
						       :deleted-state "N"))))

(defun delete-vendor-tenant (vendor-tenantlist company)
  "在指定租户下批量软删桥表记录。vendor-tenantlist — 桥表主键 id 列表。"
   (let ((tenant-id (slot-value company 'row-id)))
  (mapcar (lambda (id)  (let ((dodvendortenant (car (clsql:select 'dod-vendor-tenants :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
			  (setf (slot-value dodvendortenant 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodvendortenant  'deleted-state))) vendor-tenantlist )))




(defun get-vendor-tenants (vendor)
  "列出 vendor 关联的全部租户桥记录（未软删）。返回：dod-vendor-tenants 列表。"
  (let ((vendor-id (slot-value vendor 'row-id)))
 (clsql:select 'dod-vendor-tenants  :where
		[and [= [:deleted-state] "N"]
		[= [:vendor-id] vendor-id]]
	           :caching nil :flatp t )))



(defun get-vendor-tenants-as-companies (vendor)
  "vendor 关联租户桥记录展开为 dod-company 实例列表（按 tenant-id 逐条 select-company-by-id）。"
  (let ((vendor-tenants-list (get-vendor-tenants vendor)))
    (mapcar (lambda (vt) 
	      (let ((tenant-id (slot-value vt 'tenant-id)))
		(select-company-by-id tenant-id))) vendor-tenants-list)))

    
