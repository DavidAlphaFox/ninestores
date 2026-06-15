;;; dod-ui-push.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：webpushnotify 浏览器推送通知
;;;; 分层：UI（控制器 + 与外部 Node 边车 webpushserver/ 的 HTTP 调用）
;;;; 文件：hhub/webpushnotify/dod-ui-push.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：浏览器端订阅 / 退订 / 测试推送的 HTTP 接口入口；以及"发送推送"的
;;;;       drakma 调用——通过相对路径 /push/notify/user 反代到 Node 边车
;;;;       webpushserver/（PM2 :4345，Nginx 路径 /push/*）。
;;;;       请求头 auth-secret 携带共享密钥（当前硬编码为 \"highrisehub1234\"），
;;;;       Node 端 webpushserver 用相同密钥校验后才会调 web-push 库（VAPID）实际
;;;;       推送 P-256 加密 payload 到浏览器。
;;;;
;;;;       站内相对路径（最终代理到 Node 进程）；HTTP 方法以 Node 端实现为准：
;;;;         GET  /push/notify/user  —— 发送一条 push 通知（query 字段：
;;;;                                     title/message/clickTarget/endpoint/publicKey/auth）
;;;;                                     —— Lisp 用 drakma:http-request 不带 :method，
;;;;                                        默认就是 GET，恰好与 Node 端 app.get(...) 对齐
;;;;       兄弟模块 sms：GET /sms/sendsms 同样用 auth-secret 头（query 串携带）。
;;;;
;;;; 主要导出：
;;;;   hhub-controller-get-vendor-push-subscription   — JSON 接口：返回当前 vendor 订阅
;;;;   hhub-controller-save-vendor-push-subscription  — 接收浏览器订阅信息并入库
;;;;   hhub-controller-save-vendor-push-subscription-old — 旧版（tempstorage 路由，留底）
;;;;   hhub-save-customer-push-subscription           — customer 维度同上
;;;;   hhub-remove-customer-push-subscription
;;;;   hhub-remove-vendor-push-subscription
;;;;   test-webpush-notification-for-vendor / -for-customer  — 调试用：发欢迎通知
;;;;   send-webpush-message                            — vendor 收到新订单时被 BL 调用
;;;;   send-webpush-notification                       — 真正的 drakma GET → /push/notify/user
;;;;   send-sms-notification                           — 同范式 GET → /sms/sendsms
;;;;   Render JSONView                                 — JSON 序列化
;;;;
;;;; 关联：
;;;;   上游使用方：vendor / customer 端 ServiceWorker 注册脚本（POST notificationEndPoint
;;;;               +publicKey+auth 三参数到本模块）；订单/支付事件触发 send-webpush-message
;;;;   下游依赖：webpushnotify/dod-bl-push.lisp（Adapter/Service）、
;;;;             core 的 hhub-business-adapter / hhub-execute-business-function、
;;;;             外部 Node 服务 webpushserver/（端点 /push/notify/user，header auth-secret）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun hhub-controller-get-vendor-push-subscription ()
  "URL 控制器（JSON 接口）：返回当前登录 vendor 的 push 订阅信息（含 endpoint）。
   要求：vendor 已登录。
   流程：Adapter.processreadrequest → Presenter.createviewmodel → JSONView.render。"
  (with-vend-session-check
    (let* ((vendor (get-login-vendor))
	   (webpushadapter (make-instance 'VendorWebPushNotifyAdapter))
	   (requestmodel (make-instance 'RequestGetWebPushNofityVendor))
	   (presenter (make-instance 'GetWebPushNotifyVendorPresenter))
	   (jsonview (make-instance 'JSONView)))
      
    (setf (slot-value requestmodel 'vendor) vendor)
    (render jsonview (createviewmodel presenter (processreadrequest webpushadapter requestmodel))))))

(defmethod Render ((view JSONView) (viewmodel GetWebPushNotifyVendorViewModel))
  "把 ViewModel 渲染为 JSON 字符串：
     有 endpoint：{ \"success\":1, \"result\":[{\"endpoint\":...}] }
     无 endpoint：{ \"success\":0 }
   同时把字符串写到 view.jsondata 并返回。"
  (let* ((templist '())
	 (appendlist '())
	 (mylist '())
	 (endpoint (slot-value viewmodel 'endpoint)))
	
    (if endpoint
	(progn
	(setf templist (acons "endpoint" (format nil "~A" endpoint) templist))
	(setf appendlist (append appendlist (list templist)))
	(setf mylist (acons "result" appendlist mylist))
	(setf mylist (acons "success" 1 mylist))
	(let ((jsondata (json:encode-json-to-string mylist)))
	  (setf (slot-value view 'jsondata) jsondata)
	  ;; return jsondata
	  jsondata))
					;else 
      (progn
	(setf mylist (acons "success" 0 mylist))
 	(let ((jsondata (json:encode-json-to-string mylist)))
	  (setf (slot-value view 'jsondata) jsondata)
	  jsondata)))))


(defun hhub-save-customer-push-subscription ()
  "URL 控制器：客户端 ServiceWorker 完成订阅后回调本接口落库。
   POST 表单字段：notificationEndPoint / publicKey / auth。
   走旧式 hhub-business-adapter('create-push-notify-subscription-for-customer)
   而非 Adapter 类对象。返回字符串 \"Subscription Accepted\"。
   备注：created-by 强制写为 (select-user-by-id 1 1)（系统用户），
        tenant-id 取自登录会话。"
  (let ((endpoint (hunchentoot:parameter "notificationEndPoint"))
	(publicKey (hunchentoot:parameter "publicKey"))
	(auth (hunchentoot:parameter "auth"))
	(params nil))
	
    (setf params (acons "customer" (get-login-customer) params))
    (setf params (acons "endpoint" endpoint params))
    (setf params (acons "publickey" publickey params))
    (setf params (acons "auth" auth params))
    (setf params (acons "browser-name" "chrome" params))
    (setf params (acons "created-by" (select-user-by-id 1 1) params))
    (setf params (acons "tenant-id" (get-login-cust-tenant-id) params))

    (hhub-business-adapter 'create-push-notify-subscription-for-customer params)
    "Subscription Accepted"))


(defun hhub-controller-save-vendor-push-subscription-old ()
  "URL 控制器（旧版/已废弃）：把 vendor 订阅写到内存临时存储而非 DB。
   走 \"data-storage-in\":\"tempstorage\" 路径，挂到登录会话的
   *HHUBBUSINESSSESSIONS-HT*[business-session-id]。
   备注：保留以防回滚；新流程走 hhub-controller-save-vendor-push-subscription。"
  (let ((endpoint (hunchentoot:parameter "notificationEndPoint"))
	(publicKey (hunchentoot:parameter "publicKey"))
	(auth (hunchentoot:parameter "auth"))
	(params nil))
	
    (setf params (acons "endpoint" endpoint params))
    (setf params (acons "publickey" publickey params))
    (setf params (acons "auth" auth params))
    (setf params (acons "browser-name" "chrome" params))
    (setf params (acons "created-by" (select-user-by-id 1 1) params))
    (setf params (acons "data-storage-in" "tempstorage" params))
    (setf params (acons "business-session" (gethash (hunchentoot:session-value :login-vendor-business-session-id) *HHUBBUSINESSSESSIONS-HT*) params))

    (let ((returnlist (hhub-execute-business-function  "com.hhub.businessfunction.bl.createpushnotifysubscriptionforvendor" params)))
      (if (nth 1 returnlist)
      "Subscription Accepted"))))


(defun hhub-controller-save-vendor-push-subscription ()
  "URL 控制器：vendor 端订阅落库（新版，Adapter 类对象路径）。
   POST 表单字段：notificationEndPoint / publicKey / auth → 装进
   RequestCreateWebPushNotifyVendor → ProcessCreateRequest → doCreate。
   去重：BL 层 init 已存在订阅时抛 hhub-webpush-subscription-exists。"
  (let* ((vendor (get-login-vendor))
	 (endpoint (hunchentoot:parameter "notificationEndPoint"))
	 (publicKey (hunchentoot:parameter "publicKey"))
	 (auth (hunchentoot:parameter "auth"))
	 (requestmodel (make-instance 'RequestCreateWebPushNotifyVendor
				      :vendor vendor 
				      :auth auth
				      :endpoint endpoint
				      :publickey publickey))
	 (webpushadapter (make-instance 'VendorWebPushNotifyAdapter)))
    (processcreaterequest webpushadapter requestmodel)))




(defun hhub-remove-customer-push-subscription ()
  "URL 控制器：客户在浏览器取消推送权限后调用，软删该客户全部订阅。
   流程：先 get-push-notify-subscription-for-customer 拿到订阅列表，再调
        remove-webpush-subscription 批量软删。返回字符串 \"Customer Subscription Removed\"。"
  (let ((params nil))
    (setf params (acons "customer" (get-login-customer) params))
    (let* ((subscription-list (hhub-business-adapter 'get-push-notify-subscription-for-customer params)))
      (setf params nil)
      (if subscription-list (setf params (acons "subscription-list" subscription-list params)))
      (hhub-business-adapter 'remove-webpush-subscription params)
    "Customer Subscription Removed")))

(defun hhub-remove-vendor-push-subscription ()
  "URL 控制器：vendor 取消订阅。装 RequestDeleteWebPushNotifyVendor →
   Adapter.processdeleterequest → Service.doDelete。"
  (let* ((vendor (get-login-vendor))
	 (requestmodel (make-instance 'RequestDeleteWebPushNotifyVendor
				      :vendor vendor
				      :company (get-login-vendor-company)))
	 (webpushadapter (make-instance 'VendorWebPushNotifyAdapter)))
    (processdeleterequest webpushadapter requestmodel)))


(defun test-webpush-notification-for-vendor (vendor)
  "调试工具：给指定 vendor 当前所有订阅各发一条欢迎消息。
   消息：\"Welcome to Nine Stores - <vendor-name>\"。点击跳到 *siteurl*。
   实现：通过 hhub-execute-business-function 取订阅列表，逐条调
        send-webpush-notification → GET /push/notify/user（drakma 默认 GET）。"
  (let* ((title "Nine Stores")
	 (message (format nil "Welcome to Nine Stores - ~A" (slot-value vendor 'name)))
	 (clickTarget (format nil "~A" *siteurl*))
	 (params nil))
    (setf params (acons "vendor" vendor params))
    (let ((returnlist (hhub-execute-business-function  "com.hhub.businessfunction.bl.getpushnotifysubscriptionforvendor" (setf params (acons "vendor" vendor  params))))) 
      (if (null (nth 1 returnlist))
	  (mapcar (lambda (subscription)
		    (let ((endpoint (slot-value subscription 'endpoint))
			  (publickey (slot-value subscription 'publickey))
			  (auth  (slot-value subscription 'auth)))
		      (send-webpush-notification title message clickTarget endpoint publickey auth))) (nth 0 returnlist))))))



(defun send-webpush-message (person message)
  "面向业务事件的发送入口：给 vendor 推一条业务消息（如新订单提醒）。
   仅在 person 是 dod-vend-profile 时查订阅；clickTarget 跳到 vendor 待办订单页
   /hhub/dodvendindex?context=pendingorders。
   未订阅则静默忽略。"
  (let* ((title "Nine Stores")
	 (webpushdbservice (make-instance 'WebPushNotifyDBService))
	 (subscription (if (equal 'DOD-VEND-PROFILE (type-of person)) (db-fetch-Vendor-WebPushNotifySubscriptions webpushdbservice person)))
	 (clickTarget (format nil "~A/hhub/dodvendindex?context=pendingorders" *siteurl*)))
    ;; Send a message only if subscription is present. 
    (if subscription
	(let ((endpoint (slot-value subscription 'endpoint))
	      (publickey (slot-value subscription 'publickey))
	      (auth  (slot-value subscription 'auth)))
	  (send-webpush-notification title message clickTarget endpoint publickey auth)))))





(defun test-webpush-notification-for-customer (customer)
  "调试工具：给指定 customer 全部订阅设备各发一条欢迎消息。
   注意：get-push-notify-subscription-for-customer 期望接受 alist params，
        此处直接传入 customer 实例，与该函数实现签名不一致——推测此调用路径
        实际在测试时未被命中（或 BL 端有重载）。"
  (let* ((title "Nine Stores")
	 (message (format nil "Welcome to Nine Stores - ~A" (slot-value customer 'name)))
	 (clickTarget (format nil "~A" *siteurl*))
	 (subscriptions (get-push-notify-subscription-for-customer customer)))
    (mapcar (lambda (subscription)
	      (let ((endpoint (slot-value subscription 'endpoint))
		    (publickey (slot-value subscription 'publickey))
		    (auth  (slot-value subscription 'auth)))
		(send-webpush-notification title message clickTarget endpoint publickey auth))) subscriptions)))


					;Experiment with push notification
(defun send-webpush-notification (title message clickTarget endpoint publicKey auth)
:documentation "Test Webpush Notification.
   中文：真正发送推送的底层函数——drakma:http-request（默认 :method :GET）调用
   *siteurl*/push/notify/user。
   query 字段：title / message / clickTarget / endpoint / publicKey / auth
   （drakma 把 :parameters 编码到 URL query 串里，因为是 GET）。
   请求头：auth-secret = \"highrisehub1234\"（与 webpushserver/ 端共享密钥；推测应改读取
   *HHUBWEBPUSHAUTHSECRET* 环境变量，目前为硬编码）。
   下游：Nginx → :4345 webpushserver/index-v3.mjs（app.get '/push/notify/user'）
   → web-push 库（VAPID）→ 浏览器 push service（FCM/Mozilla AutoPush）。"
  (let* ((paramnames (list "title" "message" "clickTarget" "endpoint" "publicKey" "auth"))
	 (paramvalues (list title message clickTarget endpoint publicKey auth))
	 (param-alist (pairlis paramnames paramvalues))
	 (headers nil) 
	 (headers (acons "auth-secret" "highrisehub1234" headers)))
    ; Execution
    (drakma:http-request (format nil "~A/push/notify/user" *siteurl*)
			 :additional-headers headers
			     :parameters param-alist)))



(defun send-sms-notification (number senderid message)
  "把短信发送转给 Node 边车 smsserver/：drakma:http-request 默认 :GET 调
   *SITEURL*/sms/sendsms（与 Node 端 app.get('/sms/sendsms', ...) 对齐）。
   query 字段：number / senderid / message。
   请求头：auth-secret = \"highrisehub1234\"（同 push 共享密钥模式；smsserver
   实际并未校验该 header，但前端按统一范式带上）。
   备注：放在 webpushnotify 目录但实际属于 sms 通道；smsserver/index-v3.mjs（PM2 :4300）
   下游通过 AWS SNS 发出 Transactional SMS；印度需经 VI DLT 平台注册 SenderID/TemplateId/EntityId。"
  (let* ((paramnames (list "number" "senderid" "message"))
	 (paramvalues (list number senderid message))
	 (param-alist (pairlis paramnames paramvalues))
	 (headers nil) 
	 (headers (acons "auth-secret" "highrisehub1234" headers)))
    ; Execution
    (drakma:http-request (format nil "~A/sms/sendsms" *SITEURL*)
			 :additional-headers headers
			     :parameters param-alist)))
  
