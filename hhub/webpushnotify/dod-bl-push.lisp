;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：webpushnotify 浏览器推送通知
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/webpushnotify/dod-bl-push.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：web-push 订阅 CRUD + 与外部 Node 边车 webpushserver/ 的对接业务。
;;;;       六边形分层：VendorWebPushNotifyAdapter / Service / DBService /
;;;;       Presenter 各司其职。提供按 vendor / customer 维度的订阅查询、
;;;;       重复订阅校验（抛 hhub-webpush-subscription-exists）。
;;;;
;;;;       重要：实际"发送推送"的 HTTP 调用并不在本文件，而是由 dod-ui-push.lisp
;;;;       的 send-webpush-notification 函数发出。Node 边车 webpushserver/index-v3.mjs
;;;;       仅暴露以下端点：
;;;;         GET  /push/status        —— 健康检查
;;;;         GET  /push/notify/user   —— 唯一发推接口（query 串带 endpoint/publicKey/
;;;;                                      auth/title/message/clickTarget；header
;;;;                                      auth-secret 带 *HHUBWEBPUSHAUTHSECRET* 值）
;;;;         POST /subscribe          —— 浏览器侧前端调用，注册新订阅
;;;;         POST /unsubscribe        —— 浏览器侧前端调用，注销订阅
;;;;       Lisp 侧通过 drakma:http-request（默认 :method :GET）调 /push/notify/user，
;;;;       Node 端校验 auth-secret 后用 web-push 库（VAPID）真正发出。
;;;;
;;;; 主要导出：
;;;;   ProcessCreateRequest / ProcessDeleteRequest / ProcessReadRequest
;;;;       — Adapter 入口
;;;;   doCreate / doDelete / doRead   — Service 主流程（含 bo-knowledge 包装）
;;;;   ProcessResponse / CreateViewModel
;;;;   db-fetch-Vendor-WebPushNotifySubscriptions
;;;;   db-fetch-Customer-WebPushNotifySubscriptions
;;;;   db-fetch / db-fetch-all
;;;;   Copy-BusinessObject-To-DBObject / Copy-DbObject-To-BusinessObject
;;;;   init (vendor / customer 两个分派)
;;;;   persist-push-notify-subscription
;;;;   create-push-notify-subscription-for-customer
;;;;   delete-subscriptions / remove-webpush-subscription
;;;;   get-push-notify-subscription-for-customer
;;;;   com-hhub-businessfunction-bl-createpushnotifysubscriptionforvendor
;;;;   com-hhub-businessfunction-bl-getpushnotifysubscriptionforvendor
;;;;   com-hhub-businessfunction-db-getpushnotifysubscriptionforvendor
;;;;
;;;; 关联：
;;;;   上游使用方：webpushnotify/dod-ui-push.lisp（订阅注册、退订、消息推送 UI）、
;;;;               vendor / customer 通知中心
;;;;   下游依赖：webpushnotify/dod-dal-push.lisp（实体）、core 的 hhub-execute-business-function、
;;;;             with-db-call / bo-knowledge / bo-knowledge-truth、外部 Node 服务
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

(defmethod ProcessDeleteRequest ((adapter VendorWebPushNotifyAdapter) (requestmodel RequestDeleteWebPushNotifyVendor))
  :description "This method is responsible for Deleting a web push notification record for a given vendor.
   中文：Adapter Delete 入口——绑定 service 后 call-next-method。"
  ;; Set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'VendorWebPushNotifyService))
  (call-next-method))

(defmethod doDelete ((service VendorWebPushNotifyService) (requestmodel RequestDeleteWebPushNotifyVendor))
  :description "This method is responsible for Deleting a Web push notification subscription for a given vendor.
   中文：Service Delete 主流程——查出 vendor 当前订阅 → 走 db-delete（推测软删）。
   subscription 不存在则跳过。"
  (let* ((vendor (vendor requestmodel))
	 (company (company requestmodel))
	 (webpushdbservice (make-instance 'WebPushNotifyDBService))
	 (subscription (db-fetch-Vendor-WebPushNotifySubscriptions webpushdbservice vendor)))
    (when subscription 
      (setf (dbobject webpushdbservice) subscription)
      (setf (company webpushdbservice) company)
      ;; Delete the record
      (db-delete webpushdbservice))))
    	

(defmethod ProcessCreateRequest ((adapter VendorWebPushNotifyAdapter)  (requestmodel RequestCreateWebPushNotifyVendor))
  :description "This method is responsible for Creating a web push request.
   中文：Adapter Create 入口——绑定 service 后 call-next-method。"
  ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'VendorWebPushNotifyService))                                                                                                                     
  ;; call the parent ProcessCreate
  (call-next-method))

    
(defmethod doCreate ((service VendorWebPushNotifyService) (requestmodel RequestCreateWebPushNotifyVendor))
  "Service Create 主流程：从 requestmodel 取 vendor + endpoint/auth/publickey，
   构造 WebPushNotifyVendor 域对象（默认 browser-name=\"chrome\"、perm-granted='Y'、
   expired='N'），调 init 初始化 DBService 并写库。
   备注：init 内部会做\"已存在订阅则抛 hhub-webpush-subscription-exists\"的去重。"
  (let* ((vendor (slot-value requestmodel 'vendor))
	 (webpushdbservice (make-instance 'WebPushNotifyDBService))
	 (ep (endpoint requestmodel))
	 (auth (auth requestmodel))
	 (pkey (publickey requestmodel))
	 (browser-name "chrome")
	 (webpushnotifyobj (make-instance 'WebPushNotifyVendor
					  :vendor vendor
					  :endpoint ep
					  :publickey pkey
					  :auth auth 
					  :browser-name browser-name 
					  :perm-granted "Y"
					  :expired "N")))
    
    ;; Initialize the DB Service
    (init webpushdbservice webpushnotifyobj)
    (copy-businessobject-to-dbobject webpushdbservice)
    (db-save webpushdbservice)))
  
(defmethod CreateViewModel ((service GetWebPushNotifyVendorPresenter) (responsemodel ResponseGetWebPushNotifyVendor))
  "Presenter：把 ResponseModel 中的 endpoint 字段拷到 ViewModel；同时也存进
   service.viewmodel slot（推测让上层无需 funcall 也可读到结果）。"
  (let ((viewmodel (make-instance 'GetWebPushNotifyVendorViewModel)))
    (with-slots (endpoint) responsemodel
      (setf (slot-value viewmodel 'endpoint) endpoint)
      ;;return the viewmodel
      (setf (slot-value service 'viewmodel) viewmodel)
      viewmodel)))


(defmethod ProcessResponse ((service VendorWebPushNotifyAdapter)  params)
  "Adapter 响应装配：从 params 取 webpushsubscription（dod-webpush-notify 实例），
   生成 ResponseGetWebPushNotifyVendor，并把订阅字段拷过去。
   返回：responsemodel；订阅缺失时 endpoint 为空字符串。"
  (let* ((webpushsubscription (cdr (assoc "webpushsubscription" params :test 'equal)))
	 (responsemodel (make-instance 'ResponseGetWebPushNotifyVendor
				       :endpoint "")))
    (if webpushsubscription
	(copywebpushnotification webpushsubscription responsemodel))
    ;; return the responsemodel
    responsemodel))


(defmethod doRead ((service VendorWebPushNotifyService) requestmodel)
  "Service Read：用 with-db-call 包住 DAL 查询并把结果落到 service.bo-knowledge
   （知识捕获包装），仅当 truth=:T 时拿出 payload 返回。"
  (let* ((vendor (slot-value requestmodel 'vendor))
	 (webpushdbservice (make-instance 'WebPushNotifyDBService))
	 (dbsubscription-knowledge (with-db-call (db-fetch-Vendor-WebPushNotifySubscriptions webpushdbservice vendor))))
    (setf (bo-knowledge service) dbsubscription-knowledge)
    (when (eq (bo-knowledge-truth dbsubscription-knowledge) :T)
      (let ((dbsubscription (bo-knowledge-payload dbsubscription-knowledge)))
	dbsubscription))))

(defmethod ProcessReadRequest ((adapter VendorWebPushNotifyAdapter)  (requestmodel RequestGetWebPushNofityVendor))
  :description "This function is responsible for initializaing the BusinessService and calling its doService method. It then creates an instance of outboundwebservice.
   中文：Adapter Read 入口——绑定 service + 缓存 requestmodel；调 call-next-method 拿到
        订阅 db 行；再把它包进 alist 调 ProcessResponse 装成 ResponseModel 返回。"
  (setf (slot-value adapter 'businessservice) (find-class 'VendorWebPushNotifyService))
  (setf (slot-value adapter 'requestmodel) requestmodel)
  
  (let ((webpushsubscription (call-next-method))
	(params nil)) 
    (setf params (acons "webpushsubscription" webpushsubscription params))
    (processresponse adapter params)))



(defmethod db-fetch-Vendor-WebPushNotifySubscriptions ((dbas WebPushNotifyDBService) vendor)
  "查询某 vendor 的活跃推送订阅（最多一条；person-type='VENDOR'，active-flag='Y'）。
   返回：单个 dod-webpush-notify / nil。"
  (let* ((vendor-id (slot-value vendor 'row-id))
	 (company (get-vendor-company vendor)) 
	 (tenant-id (slot-value company 'row-id))
	 (db-vendorpushsub (car (clsql:select 'dod-webpush-notify :where
					 [and
					 [= [:deleted-state] "N"]
					 [= [:active-flag] "Y"]
					 [= [:vendor-id] vendor-id]
					 [= [:person-type] "VENDOR"]
					 [= [:tenant-id] tenant-id]] :caching *dod-database-caching* :flatp T))))
    db-vendorpushsub))


(defmethod db-fetch-Customer-WebPushNotifySubscriptions ((dbas WebPushNotifyDBService) customer)
  "查询某 customer 的全部活跃推送订阅（同一客户可能在多设备订阅，所以是列表）。
   返回：dod-webpush-notify 列表。"
  (let* ((cust-id (slot-value customer 'row-id))
	 (company (customer-company customer)) 
	 (tenant-id (slot-value company 'row-id))
	 (db-customerpushsubs (clsql:select 'dod-webpush-notify :where
					 [and
					 [= [:deleted-state] "N"]
					 [= [:active-flag] "Y"]
					 [= [:cust-id] cust-id]
					 [= [:person-type] "CUSTOMER"]
					 [= [:tenant-id] tenant-id]] :caching *dod-database-caching* :flatp NIL)))
    db-customerpushsubs))


(defmethod db-fetch ((dbas WebPushNotifyDBService) row-id)
  :description  "Fetch the DBObject based on row-id.
   中文：按主键 row-id + DBService 上的 tenant-id 查回订阅，并写到 dbobject slot。"
  (let* ((tenant-id (slot-value dbas 'tenant-id))
	 (dbobj (clsql:select 'dod-webpush-notify :where
				      [and
				      [= [:deleted-state] "N"]
				      [= [:active-flag] "Y"]
				      [= [:tenant-id] tenant-id]
				      [= [:row-id] row-id]] :caching *dod-database-caching* :flatp t)))
    (setf (slot-value dbas 'dbobject) dbobj)))

(defmethod db-fetch-all ((dbas WebPushNotifyDBService)(rm RequestGetWebPushNofityVendor))
  :description "Fetch records by COMPANY.
   中文：列出当前租户全部活跃订阅（含 customer + vendor）。返回：dod-webpush-notify 列表。"
  (let* ((tenant-id (slot-value dbas 'tenant-id))
	 (dbobjs (clsql:select 'dod-webpush-notify :where
				      [and
				      [= [:deleted-state] "N"]
				      [= [:active-flag] "Y"]
				      [= [:tenant-id] tenant-id]] :caching *dod-database-caching* :flatp t)))
    dbobjs))

(defmethod Copy-BusinessObject-To-DBObject ((dbas WebPushNotifyDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：把域对象 6 个字段（browser-name/endpoint/publickey/auth/perm-granted/expired）
        拷到 dbobject。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(webpushobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copywebpushnotification webpushobj dbobj))))


(defun copywebpushnotification (source destination)
  "字段拷贝（双向通用）：6 个推送相关字段从 source 写到 destination。
   返回：destination。"
    (with-slots (browser-name endpoint publickey auth perm-granted expired) destination
      (setf browser-name (slot-value source 'browser-name))
      (setf endpoint (slot-value source 'endpoint))
      (setf publickey  (slot-value source 'publickey ))
      (setf auth (slot-value source 'auth))
      (setf perm-granted (slot-value source 'perm-granted))
      (setf expired (slot-value source 'expired))
      destination))


(defmethod Copy-DbObject-To-BusinessObject ((dbas WebPushNotifyDBService))
  "把 dbobject 拷到 businessobject。
   注：实现里 setf 写到 (slot-value dbas 'webpushobj)，但 DBService 类上并未定义 webpushobj
       slot，businessobject 才是标准 slot —— 推测此处为代码笔误，应为 'businessobject'。"
 (let ((dbobj (slot-value dbas 'dbobject))
	(webpushobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'webpushobj) (copywebpushnotification dbobj webpushobj))))
 

(defmethod init ((dbas WebPushNotifyDBService) (bo WebPushNotifyVendor))
  :description "Set the DB object and domain object.
   中文：vendor 路径的初始化——构造一个空的 dod-webpush-notify
        （person-type='VENDOR'，active-flag/expired/deleted-state 默认值），
        并查重：若 vendor 已有订阅则抛 hhub-webpush-subscription-exists；
        否则把 dbobj 与 company 上下文挂到 DBService，再 call-next-method 走父类 save。"
  (let* ((vendor (vendor bo))
	 (vendor-id (slot-value vendor 'row-id))
	 (webpushnotifyDBobj (make-instance 'dod-webpush-notify
					    :cust-id nil
					    :vendor-id vendor-id
					    :person-type "VENDOR"
					    :active-flag "Y"
					    :expired "N"
					    :deleted-state "N")))
   
    ;; Fetch already existing subscriptions for the vendor if any. 
    (let* ((previoussub (db-fetch-Vendor-WebPushNotifySubscriptions dbas vendor)))
      (unless previoussub
	(setf (slot-value dbas 'dbobject) webpushnotifyDBobj)
	 ;; Set the company context for the web push notification DB service 
	(setcompany dbas (get-vendor-company vendor))
	(call-next-method))
      (when previoussub
	(error 'hhub-webpush-subscription-exists :errstring (format nil "Web Push Subscription for vendor: ~A, already exists" (name vendor)))))))

    
	  

(defmethod init ((dbas WebPushNotifyDBService) (bo WebPushNotifyCustomer))
  :description "Set the DB object and domain object.
   中文：customer 路径的初始化——同上，但 person-type='CUSTOMER'。
        查重时 db-fetch-Customer-WebPushNotifySubscriptions 返回列表，故取 (car ...)。
        异常文案沿用 vendor 模板（写 \"vendor:\"），推测为复制粘贴。"
  (let* ((customer (customer bo))
	(cust-id (slot-value customer 'row-id))
	(webpushnotifyDBobj (make-instance 'dod-webpush-notify
					   :vendor-id nil
					   :cust-id cust-id
					   :person-type "CUSTOMER"
					   :active-flag "Y"
					   :deleted-state "N")))

        ;; Fetch already existing subscriptions for the vendor if any. 
    (let* ((previoussub (car (db-fetch-Customer-WebPushNotifySubscriptions dbas customer))))
      (unless previoussub
	(setf (dbobject dbas) webpushnotifyDBobj)
	;; Set the company context for the web push notification DB service 
	(setcompany dbas (customer-company customer))
	(call-next-method))
      (when previoussub
	(error 'hhub-webpush-subscription-exists :errstring (format nil "Web Push Subscription for vendor: ~A, already exists" (name customer)))))))


(defun persist-push-notify-subscription(cust-id vendor-id person-type endpoint publickey auth  browser-name created-by tenant-id)
  "底层持久化：构造 dod-webpush-notify 并 INSERT。
   备注：默认 perm-granted='Y'、expired='N'、active-flag='Y'、deleted-state='N'。
   传 cust-id 或 vendor-id 之一即可（另一个传 nil）。"
  (clsql:update-records-from-instance (make-instance 'dod-webpush-notify
							 :cust-id cust-id
							 :vendor-id vendor-id
							 :person-type person-type 
							 :endpoint endpoint
							 :publickey publickey
							 :auth auth 
							 :browser-name browser-name 
							 :perm-granted "Y"
							 :expired "N"
							 :tenant-id tenant-id
							 :active-flag "Y"
							 :created-by created-by
							 :deleted-state "N")))
  



(defun create-push-notify-subscription-for-customer (params)
  "面向 hhub-execute-business-function 调度风格的入口：从 alist params 取
   customer / endpoint / publickey / auth / browser-name / created-by / tenant-id，
   调用 persist-push-notify-subscription 落库（person-type='CUSTOMER'）。"
   (let* ((customer (cdr (assoc "customer" params :test 'equal)))
	 (endpoint (cdr (assoc "endpoint" params :test 'equal)))
	 (publickey (cdr (assoc "publickey" params :test 'equal)))
	 (auth (cdr (assoc "auth" params :test 'equal)))
	 (browser-name (cdr (assoc "browser-name" params :test 'equal)))
	 (created-by (cdr (assoc "created-by" params :test 'equal)))
	 (tenant-id (cdr (assoc "tenant-id" params :test 'equal)))
	 (cust-id (if customer (slot-value customer 'row-id)))
	 (user-id (slot-value created-by 'row-id)))
     ;Here we are going to call the DB layer. We will call the DB Adapter here in future. 
     (persist-push-notify-subscription cust-id nil "CUSTOMER" endpoint publickey auth browser-name user-id tenant-id)))



  

(defun com-hhub-businessfunction-bl-createpushnotifysubscriptionforvendor (params)
  :documentation "Business layer function to create the push notification subscriptions for a given vendor. This function is responsible for creating the push notify subscription for vendor and save it current business session for further requirement within the session.
   中文：BL 调度入口——根据 params.\"data-storage-in\" 选择路由：
        \"tempstorage\"  → com.hhub.businessfunction.tempstorage.createpushnotifysubscriptionforvendor
        其它（默认 db）→ com.hhub.businessfunction.db.createpushnotifysubscriptionforvendor
        二者均通过 hhub-execute-business-function 派发。返回 returnlist[0]，
        失败时抛 hhub-business-function-error。"
  (let ((datastoragein (cdr (assoc "data-storage-in" params :test 'equal))))
    (if (equal datastoragein "tempstorage") 
	(let ((returnlist (hhub-execute-business-function "com.hhub.businessfunction.tempstorage.createpushnotifysubscriptionforvendor" params)))
	  (if (null (nth 1 returnlist))
	      (nth 0 returnlist) ; return this value 
	      ;; else if condition is signalled
	      (error 'hhub-business-function-error :errstring "Error during vendor subscription create in temporary storage")))
					;else data is stored in database
	(let ((returnlist (hhub-execute-business-function  "com.hhub.businessfunction.db.createpushnotifysubscriptionforvendor" params)))
	  (if (null (nth 1 returnlist))
	      (nth 0 returnlist) ; return this value
	      ;; else if condition is signalled
	      (error 'hhub-business-function-error :errstring "Error during vendor subscription create in  database."))))))



(defun com-hhub-business-function-db-getpushnotifysubscriptionforvendor  (params)
:documentation "This function will create push notify subscription in a temporary storage.
   中文：占位实现，调用即抛 'Function not implemented'。docstring 与函数名提示
        \"create push notify subscription in temporary storage\"——
        但函数名是 db-get... —— 推测原作者把这两个错放函数贴混了，仍未补齐。"
  (if params
      (error 'hhub-business-function-error :errstring "Function not implemented")))




(defun delete-subscriptions ( list)
  "批量软删订阅：把 list 中每条 dod-webpush-notify 的 deleted-state 置 'Y' 并 UPDATE 该列。"
  (mapcar (lambda (object)
		(setf (slot-value object 'deleted-state) "Y")
		(clsql:update-record-from-slot object  'deleted-state)) list ))


(defun remove-webpush-subscription (params)
  "从 params alist 取 subscription-list 后批量软删。"
  (let ((subscription-list (cdr (assoc "subscription-list" params :test 'equal))))
  (delete-subscriptions subscription-list)))

(defun get-push-notify-subscription-for-customer (params)
  "查询某 customer 的活跃推送订阅。从 params 取 customer，按 cust-id + person-type='CUSTOMER'
   过滤。返回：dod-webpush-notify 列表。"
  (let* ((customer (cdr (assoc "customer" params :test 'equal)))
	 (cust-id (slot-value customer 'row-id))
	 (tenant-id (slot-value customer 'tenant-id)))
    (clsql:select 'dod-webpush-notify :where
		  [and
		  [= [:deleted-state] "N"]
		  [= [:active-flag] "Y"]
		  [= [:cust-id] cust-id]
		  [= [:person-type] "CUSTOMER"]
		  [= [:tenant-id] tenant-id]] :caching *dod-database-caching* :flatp t)))



(defun com-hhub-businessfunction-bl-getpushnotifysubscriptionforvendor (params)
  :documentation "Business layer function to get the push notification subscriptions for a given vendor. This function will act like a proxy and pass on the params to DB layer function.
   中文：BL 读取调度——同 create 的双路由风格，按 data-storage-in 选 db / tempstorage。"
  (let ((datastoragein (cdr (assoc "data-storage-in" params :test 'equal))))
    (if (equal datastoragein "tempstorage") 
	(let ((returnlist (hhub-execute-business-function "com.hhub.businessfunction.tempstorage.getpushnotifysubscriptionforvendor" params)))
	  (if (null (nth 1 returnlist))
	      (nth 0 returnlist) ; return this value 
	      ;; else if condition is signalled
	      (error 'hhub-business-function-error :errstring "Error during vendor subscription fetch from temporary storage")))
					;else data is stored in database
	(let ((returnlist (hhub-execute-business-function  "com.hhub.businessfunction.db.getpushnotifysubscriptionforvendor" params)))
	  (if (null (nth 1 returnlist))
	      (nth 0 returnlist) ; return this value
	      ;; else if condition is signalled
	      (error 'hhub-business-function-error :errstring "Error during vendor subscription fetch from database."))))))
	  
(defun com-hhub-businessfunction-db-getpushnotifysubscriptionforvendor (params)
  :documentation "This function will fetch the push notify subscription from Database.
   中文：DB 路径实现——按 vendor + tenant + person-type='VENDOR' 查活跃订阅。
        以 multiple-values 返回 (values 结果 异常)。"
  (let* ((vendor (cdr (assoc "vendor" params :test 'equal)))
	 (vendor-id (slot-value vendor  'row-id))
	 (tenant-id (slot-value vendor 'tenant-id))
	 (exceptions nil)
	 (returnvalues  (clsql:select 'dod-webpush-notify :where
				      [and
				      [= [:deleted-state] "N"]
				      [= [:active-flag] "Y"]
				      [= [:vendor-id] vendor-id]
				      [= [:person-type] "VENDOR"]
				      [= [:tenant-id] tenant-id]] :caching *dod-database-caching* :flatp t)))
	(values returnvalues exceptions)))
   

(defun com-hhub-business-function-tempstorage-getpushnotifysubscriptionforvendor  (params)
:documentation "This function will fetch the push notify subscription from a temporary storage.
   中文：占位实现，未真正用临时存储。任意非空 params 都会抛 'Function not implemented'。"
  (if params
      (error 'hhub-business-function-error :errstring "Function not implemented")))



