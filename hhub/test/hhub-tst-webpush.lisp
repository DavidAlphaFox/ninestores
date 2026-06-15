;;; hhub-tst-webpush.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— Web Push 订阅信息（WebPushNotifyVendor）测试
;;;; 分层：测试套件（集成测试，依赖 DB；样例 endpoint 指向 FCM）
;;;; 文件：hhub/test/hhub-tst-webpush.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：模拟 Chrome 给 vendor=1 注册 Web Push 订阅，并演示
;;;;       订阅写入 / DBService 读取 / Adapter+Presenter+View 渲染 三种路径。
;;;;
;;;; 主要导出：
;;;;   test-vendor-push-notification-DBSave   — 用硬编码 endpoint/publickey/auth 写库
;;;;   test-vendor-push-notification-fetch    — 通过 DBService 直查订阅
;;;;   test-vendor-push-notification-get      — 通过 Adapter→Presenter→JSONView 渲染
;;;;
;;;; 关联：
;;;;   下游依赖：webpushnotify/dod-bl-push.lisp（DBService / BO）、
;;;;             webpushnotify/dod-ui-push.lisp（Adapter / Presenter）
;;;; ============================================================================

(in-package :nstores)

(defun test-vendor-push-notification-DBSave ()
  ;; 集成测试：会真实写入 dod_webpush_notify 类表；endpoint 是真实 FCM URL，请勿向其推送。
 (handler-case   
  (let* ((vendor (select-vendor-by-id 1))
	 (endpoint "https://fcm.googleapis.com/fcm/send/cOiXZdFN1L8:APA91bG6ihZdVprLygSkCmrG1dYKoLMYPLukqBx1HUt-ibJqRUq8Naa2DiuAh9vIZCU149mhED6Yq6AN2G50ODSplT7GlzkMMs9MU4d-y4E7xyqdDKPXHFVzkLcSYRJdQSWNNexUfns4")
	 (publickey "BL4da60XNvMouIndK7QyVwP9UT3upM+xdkWF+4+HvRChOIcl46Pk23pHstMGigxhOHg/ayeZ/uTnqbocwjiJIcA=")
	 (auth "AXLmPcLxtGxbBdcP4lvT6g==")
	 (browser-name "chrome")
	 (webpushnotifyobj (make-instance 'WebPushNotifyVendor
					  :vendor vendor
					  :endpoint endpoint
					  :publickey publickey
					  :auth auth 
					  :browser-name browser-name 
					  :perm-granted "Y"
					  :expired "N"))
	 (webpushdbservice (make-instance 'WebPushNotifyDBService)))
    
    ;; Initialize the DB Service
    (init webpushdbservice webpushnotifyobj)
    (copy-businessobject-to-dbobject webpushdbservice)
    (db-save webpushdbservice))
   (error (c)
     (let ((exceptionstr (format nil  "HHUB General Business Function Error: ~a~%"  c)))
       (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
			       :direction :output
			       :if-exists :supersede
			       :if-does-not-exist :create)
	 (format stream "~A" exceptionstr))
         c))))

(defun test-vendor-push-notification-fetch ()
  ;; 读取：直接走 DBService.db-fetch-Vendor-WebPushNotifySubscriptions（不经 Adapter）。
  (let* ((vendor (select-vendor-by-id 1))
	 (webpushdbservice (make-instance 'WebPushNotifyDBService))
	 (subscription (db-fetch-Vendor-WebPushNotifySubscriptions webpushdbservice vendor)))
   subscription))

  
 

(defun test-vendor-push-notification-get ()
  ;; 读取 + 渲染：走 Adapter→Presenter→JSONView 完整链路，等价于真实请求处理。
  (let* ((vendor (select-vendor-by-id 1))
	 (webpushadapter (make-instance 'VendorWebPushNotifyAdapter))
	 (presenter (make-instance 'GetWebPushNotifyVendorPresenter))
	 (requestmodel (make-instance 'RequestGetWebPushNofityVendor))
	 (jsonview (make-instance 'JSONView)))

    (setf (slot-value requestmodel 'vendor) vendor)
    (render jsonview (createviewmodel presenter (processreadrequest  webpushadapter requestmodel)))))
