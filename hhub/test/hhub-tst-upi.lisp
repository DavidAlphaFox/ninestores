;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— UPI 支付记录测试
;;;; 分层：测试套件（集成测试，依赖 DB 与 UpiPayments / WebPushNotify Adapter）
;;;; 文件：hhub/test/hhub-tst-upi.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：覆盖 UPI 支付的 写入 / vendor 维度查询 / Web 推送视图渲染 三种用例。
;;;;
;;;; 主要导出：
;;;;   test-upipayments-DBSave        — 创建一条 UPI 支付（金额 100，固定 utr/transaction-id）
;;;;   test-vendor-upipayments-fetch  — 通过 DBService 直查 vendor 的 upi 记录
;;;;   test-vendor-upipayments-get    — 通过 Adapter→Presenter→JSONView 渲染
;;;;
;;;; 关联：
;;;;   下游依赖：upi/dod-bl-upi.lisp、upi/dod-ui-upi.lisp、
;;;;             webpushnotify 相关 Adapter / Presenter（test-vendor-upipayments-get 中复用）
;;;; ============================================================================

(in-package :nstores)

(defun test-upipayments-DBSave ()
  ;; 集成测试：写一条演示支付（vendor=1, customer=1, company=2, amount=100.00）。
;; (handler-case   
     (let* ((vendor (select-vendor-by-id 1))
	    (democompany (select-company-by-id 2))
	    (customer (select-customer-by-id 1 democompany))
	    (amount 100.00)
	    (requestmodel (make-instance 'UpiPaymentsRequestModel
					 :vendor vendor
					 :customer customer
					 :amount amount
					 :transaction-id "PW93993"
					 :utrnum "383838448432"
					 :company democompany))
	    (upipaymentsadapter (make-instance 'UpiPaymentsAdapter)))
	 
       (ProcessCreateRequest upipaymentsadapter requestmodel)))
       
  ;; (error (c)
   ;;  (let ((exceptionstr (format nil  "HHUB General Business Function Error: ~a~%"  c)))
  ;;     (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
;;			       :direction :output
;;			       :if-exists :supersede
;;			       :if-does-not-exist :create)
;;	 (format stream "~A" exceptionstr))
  ;     ;; return the exception.
  ;;     c))))

(defun test-vendor-upipayments-fetch ()
  ;; 直接走 DBService（绕过 Adapter/Presenter），用于排查底层 SQL。
  (let* ((vendor (select-vendor-by-id 1))
	 (upipaymentsDBService (make-instance 'UpiPaymentsDBService))
	 (upipaymentsrecords (db-fetch-Vendor-upirecords upipaymentsDBService vendor)))
   upipaymentsrecords))

  
 

(defun test-vendor-upipayments-get ()
  ;; 注意：函数名暗示 UPI，但其实复用了 VendorWebPushNotifyAdapter——
  ;; 推测此处只是借用其 Adapter→Presenter→JSONView 路径调试 JSON 渲染。
  (let* ((vendor (select-vendor-by-id 1))
	 (params nil)
	 (webpushadapter (make-instance 'VendorWebPushNotifyAdapter))
	 (presenter (make-instance 'GetWebPushNotifyVendorPresenter))
	 (jsonview (make-instance 'JSONView)))
    
    (setf params (acons "vendor" vendor params))
    (render jsonview (createviewmodel presenter (processrequest webpushadapter params)))))

