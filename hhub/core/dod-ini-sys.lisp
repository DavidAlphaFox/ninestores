;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 系统初始化与全局配置
;;;; 分层：平台基础（启动 / 引导）
;;;; 文件：hhub/core/dod-ini-sys.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：集中所有平台级 defvar/defparameter（DB 连接、URL、模板路径、ABAC 前缀、
;;;;       支付网关 URL、登录超时、套餐期限、文件路径等），以及 (start-das) /
;;;;       (stop-das) —— Hunchentoot HTTP 服务的启动/停机入口、
;;;;       缓存预热（hhub-gen-globally-cached-lists-functions）、
;;;;       业务服务器/会话/Actor 初始化、模板加载（核心/发票/订单/客户/邮件/产品）。
;;;;
;;;; 主要导出（按重要性挑选）：
;;;;   start-das / stop-das                 — HTTP 服务启停（详见 docs/architecture.md 第 5 节）
;;;;   crm-db-connect                       — CLSQL MySQL 连接
;;;;   hhub-gen-globally-cached-lists-functions — 一次性预热 ABAC 6 张表的闭包列表
;;;;   hhub-get-cached-auth-policies / -roles / -transactions / ...
;;;;   hhub-get-cached-auth-policies-ht / -transactions-ht  — PEP/PDP 用的 hash table
;;;;   nst-load-{core,invoice,product,order,customer,email}-templates
;;;;   initBusinessServer / deleteBusinessServer            — DDD 业务服务器单例
;;;;   各类全局参数（DB / URL / 资源 / 限额 / OTP / 钱包等）
;;;;
;;;; 重要全局：
;;;;   *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*    — ABAC 缓存（6 闭包槽位）
;;;;   *HHUBBUSINESSSERVER*                  — DDD 业务服务器单例
;;;;   *NSTSENDORDEREMAILACTOR* / *NSTAWSS3FILEUPLOADACTOR*  — 常驻 actor
;;;;   *ABAC-{ATTRIBUTE,POLICY,TRANSACTION}-{NAME,FUNC}-PREFIX*
;;;;
;;;; 关联：
;;;;   上游使用方：startup/load.lisp → (start-das)；运维脚本调 (stop-das)
;;;;   下游依赖：几乎所有 core/* 模块；hunchentoot；clsql；webpush/sms/upload actors
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


;; You must set these variables to appropriate values.
;; ----------------------------------------------------------------------------
;; 数据库连接配置 —— 生产环境必须覆盖默认值（默认密码 'Welcome$123' 仅供开发）。
;; ----------------------------------------------------------------------------
(defvar *crm-database-type* :odbc
  "Possible values are :postgresql :postgresql-socket, :mysql,
:oracle, :odbc, :aodbc or :sqlite")
(defvar *crm-database-name* "hhubdb"
  "The name of the database we will work in.")
(defvar *crm-database-user* "hhubuser"
  "The name of the database user we will work as.")
(defvar *crm-database-server* "localhost"
  "The name of the database server if required")
(defvar *crm-database-password* "Welcome$123"
  "The password if required")
(defvar *dod-dbconn-spec* (list *crm-database-server* *crm-database-name* *crm-database-user* *crm-database-password*))


(defvar *HHUB-CUSTOMER-ORDER-CUTOFF-TIME* "23:59:00")
(defvar *HHUB-DEMO-TENANT-ID* 2)

(defvar *HHUB-COMPILE-FILES-LOCATION* "/home/ubuntu/ninestores/bin/hhubcompilelog.txt") 
(defvar *HHUB-EMAIL-CSS-FILE* "/data/www/ninestores.in/public/css")
(defvar *HHUB-EMAIL-CSS-CONTENTS* NIL)
(defvar *NST-WEBREPL-TEMPLATE* "/home/ubuntu/ninestores/hhub/core/templates/webrepltemplate.html")
(defvar *NST-ABOUTUSPAGE-TEMPLATE* "/home/ubuntu/ninestores/hhub/core/templates/aboutuspage.html")
(defvar *NST-CORE-TEMPLATES* nil)
(defvar *NST-ALL-INDIA-PINCODES* nil)
;; Email templates
(defvar *NST-EMAIL-TEMPLATES* NIL)
(defvar *HHUB-EMAIL-TEMPLATES-FOLDER* "/home/ubuntu/ninestores/hhub/email/templates")
(defvar *HHUB-CUST-REG-TEMPLATE-FILE* "cust-reg.html")
(defvar *HHUB-CUST-PASSWORD-RESET-FILE* "cust-pass-reset.html")
(defvar *HHUB-CUST-TEMP-PASSWORD-FILE* "temppass.html")
(defvar *HHUB-NEW-COMPANY-REQUEST* "newcompanyrequest.html")
(defvar *HHUB-CONTACTUS-EMAIL-TEMPLATE* "contactustemplate.html")
(defvar *HHUB-GUEST-CUST-ORDER-TEMPLATE-FILE* "guestcustorder.html")
(defvar *HHUB-TERMSANDCONDITIONS-FILE* "tnc.html")
(defvar *HHUB-PRIVACY-FILE* "privacy.html")
(defvar *HHUB-STATIC-FILES* "/home/ubuntu/ninestores/site/public")

;; This global variable represents the standard output terminal which will be used
;; to display output in multi threaded situations.
(defvar *stdoutstream* *standard-output*)
(defvar *dod-db-instance*)
(defvar *siteurl* "https://www.ninestores.in")
(defvar *sitepass* (encrypt "P@ssword1" "ninestores.in"))
(defvar *current-customer-session* nil) 
(defvar *customer-page-title* nil) 
(defvar *vendor-page-title* nil) 
(defvar *admin-page-title* nil) 
;; ----------------------------------------------------------------------------
;; ABAC 命名前缀。NAME 用于 DB 中的属性/策略/事务名（点分），
;; FUNC 用于对应 Lisp 函数名（连字符）。PDP/PIP 反射调用时按这两套前缀还原。
;; ----------------------------------------------------------------------------
(defvar *ABAC-ATTRIBUTE-NAME-PREFIX* "com.hhub.attribute.")
(defvar *ABAC-POLICY-NAME-PREFIX* "com.hhub.policy.")

(defvar *ABAC-TRANSACTION-NAME-PREFIX* "com.hhub.transaction.")
(defvar *ABAC-ATTRIBUTE-FUNC-PREFIX* "com-hhub-attribute-")
(defvar *ABAC-POLICY-FUNC-PREFIX* "com-hhub-policy-")
(defvar *ABAC-TRANSACTION-FUNC-PREFIX* "com-hhub-transaction-")
(defvar *PAYGATEWAYRETURNURL* "https://www.ninestores.in/hhub/custpaymentsuccess")
(defvar *PAYGATEWAYCANCELURL* "https://www.ninestores.in/hhub/custpaymentcancel")
(defvar *PAYGATEWAYFAILUREURL* "https://www.ninestores.in/hhub/custpaymentfailure")
(defvar *HHUBRESOURCESDIR* "/data/www/public/img")
(defvar *HHUBDEFAULTPRDIMG* "HHubDefaultPrdImg.png")
(defvar *HHUBDEFAULTLOGOIMG* "/img/logo.png")
(defvar *HHUBGLOBALLYCACHEDLISTSFUNCTIONS* NIL)
(defvar *HHUBGLOBALBUSINESSFUNCTIONS-HT* NIL)
(defvar *HHUBBUSINESSFUNCTIONSLOGFILE* "/home/hunchentoot/hhublogs/ninestores-busfunctions.log")

;;; EXPERIMENTING WITH DDD 
(defvar *HHUBENTITYINSTANCES-HT* nil)
(defvar *HHUBENTITY-WEBPUSHNOTIFYVENDOR-HT* NIL)
(defvar *HHUBBUSINESSSESSIONS-HT* NIL) 
(defvar *HHUBBUSINESSLOCATION-VENDOR* NIL)
(defvar *HHUBBUSINESSSERVER* NIL)

(defvar *HHUBGLOBALROLES* NIL) 
(defvar *HHUBFEATURESWISHLISTURL* "https://goo.gl/forms/hI9LIM9ebPSFwOrm1")
(defvar *HHUBBUGSURL* "https://goo.gl/forms/3iWb2BczvODhQiWW2") 
(defvar *HHUBCUSTLOGINPAGEURL* "/hhub/hhubcustloginv2")
(defvar *HHUBVENDLOGINPAGEURL* "/hhub/hhubvendloginv2")
(defvar *HHUBOPRLOGINPAGEURL* "/hhub/opr-login.html")
(defvar *HHUBCADLOGINPAGEURL* "/hhub/cad-login.html")
(defvar *HHUBPASSRESETTIMEWINDOW* 20) ; 20 minutes. Depicts the reset password time window. 
(defvar *HHUBGUESTCUSTOMERPHONE* "9999999999")
(defvar *HHUBSUPERADMINEMAIL* "support@ninestores.in")
(defvar *HHUBSUPPORTEMAIL* "support@ninestores.in")
(defvar *HHUBPENDINGUPIFUNCTIONS-HT* nil)
(defvar *HHUBTRIALCOMPANYEXPIRYDAYS* 90)
(defvar *HHUBOTPTESTING* NIL)
(defvar *HHUBUSELOCALSTORFORRES* NIL)
(defvar *HHUBWHATAPPLINKURLINDIA* "https://wa.me/91")
(defvar *HHUBWHATSAPPBUTTONIMG* "WhatsAppButtonGreenSmall.png")
(defvar *HHUBUPIBUTTON* "upibutton.png")
(defvar *HHUBUPILOGOIMG* "upilogo.png")
(defvar *HHUBUTRNUMHELPIMG* "phonepeutrnum.png")
(defvar *HHUBCHECKOUTBUTTON* "checkoutbutton.png")
(defvar *HHUBFREESHIPPINGIMG* "FreeShipping.jpg")
(defvar *HHUBSTANDARDSHIPPINGIMG* "StandardShipping.jpg")
(defvar *HHUBPICKUPINSTOREIMG* "PickupInStore.jpg")
(defvar *HTMLRUPEESYMBOL* "&#8377;")
(defvar *HTMLDOLLARSYMBOL* "&#36;")
(defvar *HHUBSHIPPINGZONES* nil)
(defvar *HHUBDEFAULTSHIPRATETABLECSV* "defaultshipratetable.csv")
(defvar *HHUBDEFAULTSHIPZONESCSV*  "defaultshipzonepincodes.csv")
(defvar *HHUBSHIPPINGPARTNERSITE* "https://www.ithinklogistics.com/")
(defvar *HHUBFREESHIPMINORDERAMT* 500.00)
(defvar *HHUBMAXVENDORLOGINS* 2)
(defvar *HHUBMAXUSERLOGINS* 2)
(defvar *HHUBMEMOIZEDFUNCTIONS* nil)
(defvar *HHUBDEFAULTCURRENCY* "INR")
(defvar *HHUBDEFAULTCOUNTRY* "India")
(defvar *NSTGSTSTATECODES-HT* nil)
(defvar *NSTUOM-HT* nil)
(defvar *NSTGSTBUSINESSSTATE* "29")

;;; Invoice templates 
(defvar *NSTGSTINVOICETERMS* NIL)
(defvar *NST-INVOICEDRAFT-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicedraft.html")
(defvar *NST-INVOICEPAYREMINDER-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicepayreminder.html")
(defvar *NST-INVOICEPAYOVERDUEREMINDER-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicepayoverduereminder.html")
(defvar *NST-INVOICEPAID-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicepaid.html")
(defvar *NST-INVOICESHIPPED-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoiceshipped.html")
(defvar *NST-INVOICECANCELLED-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicecancelled.html")
(defvar *NST-INVOICEREFUNDED-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicerefunded.html")
(defvar *NST-INVOICEPAYMENT-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicepayment.html")
(defvar *NST-INVOICESETTINGS-HTMLFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicesettings.html")
(defvar *NST-INVOICESETTINGS-YAMLFILE* "/home/ubuntu/ninestores/hhub/invoice/templates/invoicesettings.yaml")
(defvar *NST-GSTINVOICE-TEMPLATEFILE-1* "/home/ubuntu/ninestores/hhub/invoice/templates/gstinvoice1.html")
(defvar *NST-GSTINVOICE-TEMPLATEFILE-2* "/home/ubuntu/ninestores/hhub/invoice/templates/gstinvoice2.html")
(defvar *NST-GSTINVOICE-TEMPLATEFILE-3* "/home/ubuntu/ninestores/hhub/invoice/templates/gstinvoice3A5.html")
(defvar *NST-GSTINVOICE-TEMPLATEFILE-4* "/home/ubuntu/ninestores/hhub/invoice/templates/gstinvoice480mm.html")
(defvar *NST-GSTINVOICE-TEMPLATEFILE-5* "/home/ubuntu/ninestores/hhub/invoice/templates/gstinvoice5A4.html")
(defvar *NST-INVOICE-TEMPLATES* nil)
;; Product templates
(defvar *NST-PRDDETAILSFORCUST-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/products/templates/prddetailsforcust.html")
(defvar *NST-PRDDETAILSFORVEND-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/products/templates/prddetailsforvend.html")
(defvar *NST-PRODUCT-TEMPLATES* nil)
;; order templates
(defvar *NST-ORDER-TEMPLATEFILE-1* "/home/ubuntu/ninestores/hhub/order/templates/ordertemplate1.html")
(defvar *NST-ORDER-TEMPLATEFILE-2* "/home/ubuntu/ninestores/hhub/order/templates/ordertemplate2.html")
(defvar *NST-ORDER-TEMPLATES* nil)
;; customer templates
(defvar *NST-DUPLICATE-CUSTOMER-TEMPLATEFILE* "/home/ubuntu/ninestores/hhub/customer/templates/duplicate-customer.html")
(defvar *NST-CUSTOMER-TEMPLATES* nil)
;; NINE STORES ACTOR MODEL
(defvar  *NSTSENDORDEREMAILACTOR* NIL)
(defvar *NSTAWSS3FILEUPLOADACTOR* NIL)
(defvar *NSTAWSS3FILEDELETEACTOR* NIL)
;; NINE STORE OTP store
(defvar *otp-store* nil)
;; Agentic AI with ollama
(defvar *NST-VENDOR-TABLES-FOR-AGENTIC-AI* nil)
(defvar *DOD-VEND-PROFILE-TABLE* "/home/ubuntu/ninestores/hhub/vendor/templates/dod-vend-profile.txt")
(defvar *DOD-INVOICE-HEADER-TABLE* "/home/ubuntu/ninestores/hhub/vendor/templates/dod-invoice-header.txt")
(defvar *DOD-INVOICE-ITEMS-TABLE* "/home/ubuntu/ninestores/hhub/vendor/templates/dod-invoice-items.txt")
;; Outbound route registry
(defvar *NST-OUTBOUND-ROUTE-REGISTRY* (make-hash-table :test 'equal))

;; Connect to the database (see the CLSQL documentation for vendor
;; specific connection specs).

(defun crm-db-connect (&key strdb strusr strpwd servername strdbtype)
  "用 CLSQL 连接 MySQL（默认 hhubdb / hhubuser）。
   参数：strdb / strusr / strpwd / servername / strdbtype（连接器类型，:mysql 等）。
   副作用：clsql:connect；后续所有查询都走该连接。"
  :documentation "This function is responsibile for connecting to the CRM system. Arguments accepted are 
Database 
Username
Password 
Servername 
Database type: Supported type is ':odbc'"
  (case strdbtype
    ((:mysql :postgresql :postgresql-socket)
     (setf *dod-db-instance* (clsql:connect `(,servername
					      ,strdb
					      ,strusr
					      ,strpwd)
					    :database-type strdbtype)))
    ((:odbc :aodbc :oracle)
     (clsql:connect `(,strdb
		      ,strusr
		      ,strpwd)
		    :database-type strdbtype))
    (:sqlite
     (clsql:connect `(,strdb)
		    :database-type strdbtype))))

(defvar *http-server* nil)
(defvar *ssl-http-server* nil)
(defvar *dod-debug-mode* nil)
(defvar *dod-database-caching* nil)


(defun init-hhubplatform ()
  "平台引导（已被 start-das 内联调用，目前主要用于早期开发）。"
  (cond  ((null *dod-debug-mode*)
	  (setf *dod-database-caching* T))
	 (*dod-debug-mode*
	  (setf *dod-database-caching* nil))
	 (T
	  (setf *dod-database-caching* NIL))))


(defun start-das (&optional (withssl nil) (debug-mode T))
  "Nine Stores 的主启动入口（详见 docs/architecture.md 第 5 节）。
   流程：
     1) 起 Hunchentoot easy-acceptor（普通 4244 / SSL 9443）；
     2) 设置 access/message log 到 ~/hhublogs/；
     3) crm-db-connect 连 MySQL；
     4) 预热全局缓存：ABAC 6 张表、币种、GST state、UoM、印度 pincode、shipping zones、各模板；
     5) initbusinessserver 创建 BusinessServer 单例（CLOS DDD）；
     6) 启动两个常驻 actor：发邮件 + S3 上传；
     7) make-otp-store 初始化 *otp-store*。
   参数：withssl — t 时使用 easy-ssl-acceptor；debug-mode — t 时开 SQL 录制等开发选项。"
  :documentation "Start ninestores server with or without ssl. If withssl is T, then start the hunchentoot server with ssl settings"
  (setf *dod-debug-mode* debug-mode)
  (setf *random-state* (make-random-state t))
  ;; # this initializes the global random state by
  ;;   "some means" (e.g. current time.)
  (setf *http-server* (make-instance 'hunchentoot:easy-acceptor :port 4244 :document-root #p"~/ninestores/"))
  (setf (hunchentoot:acceptor-access-log-destination *http-server*)   #p"~/hhublogs/ninestores-access.log")
  (setf (hunchentoot:acceptor-message-log-destination *http-server*) #p"~/hhublogs/ninestores-messages.log")
  ;;Support double quotes for parenscript. 
  ;;CL-WHO leaves it up to you to escape HTML attributes.
  ;;One way to make sure that quoted strings in inline JavaScript
  ;;work inside HTML attributes is to use double quotes for HTML attributes and single quotes for JavaScript strings. 
  (setq cl-who:*attribute-quote-char* #\")
  (progn
    (init-hhubplatform)
    (if withssl  (init-httpserver-withssl))
    (if withssl  (hunchentoot:start *ssl-http-server*) (hunchentoot:start *http-server*) )
    (hunchentoot:reset-session-secret)
    (crm-db-connect :servername *crm-database-server* :strdb *crm-database-name* :strusr *crm-database-user*  :strpwd *crm-database-password* :strdbtype :mysql)
    (setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS* (hhub-gen-globally-cached-lists-functions))
    (setf *NST-CORE-TEMPLATES* (nst-load-core-templates))
    (setf *NST-INVOICE-TEMPLATES* (nst-load-invoice-templates))
    (setf *NST-PRODUCT-TEMPLATES* (nst-load-product-templates))
    (setf *NST-ORDER-TEMPLATES* (nst-load-order-templates))
    (setf *NST-EMAIL-TEMPLATES* (nst-load-email-templates))
    (setf *NST-CUSTOMER-TEMPLATES* (nst-load-customer-templates))
    (setf *NST-VENDOR-TABLES-FOR-AGENTIC-AI* (nst-load-vendor-tables-structure-for-agentic-ai))
    (setf *HHUBGLOBALBUSINESSFUNCTIONS-HT* (make-hash-table :test 'equal))
    (setf *HHUBPENDINGUPIFUNCTIONS-HT* (make-hash-table :test 'equal))
    (setf *HHUBBUSINESSSESSIONS-HT* (make-hash-table)) 
    (hhub-init-business-functions)
    (setf *HHUBBUSINESSSERVER* (initbusinessserver))
    (setf *NSTGSTSTATECODES-HT* (init-gst-statecodes))
    (setf *NSTUOM-HT* (get-system-UOM-map))
    (setf *NST-ALL-INDIA-PINCODES* (get-all-india-pincodes-ht))
    (init-gst-invoice-terms)
    (setf *otp-store* (make-otp-store))
    (define-shipping-zones)
    (setf *NSTSENDORDEREMAILACTOR* (make-instance 'nst-actor
						  :name "Send Order Email Actor"
						  :behavior #'send-order-email-behavior
						  :stateful t
						  :state-clean-callback (function (lambda () ()))
						  :initial-state 0))
    (setf *NSTAWSS3FILEUPLOADACTOR* (make-instance 'nst-actor
						  :name "AWS S3 Bucket File Upload Actor"
						  :behavior #'async-upload-files-s3bucket-behavior
						  :stateful t
						  :state-clean-callback nil
						  :initial-state (make-hash-table)))
    (start-actor *NSTSENDORDEREMAILACTOR*)
    (start-actor *NSTAWSS3FILEUPLOADACTOR*)))




(defun init-httpserver-withssl ()
  "起一个 HTTPS Hunchentoot easy-ssl-acceptor（默认 9443）。被 start-das 内部使用。"

;(ssl-accslogdest (hunchentoot:acceptor-access-log-destination *ssl-http-server* ))
;(ssl-msglogdest  (hunchentoot:acceptor-message-log-destination *ssl-http-server*)))

(progn 
  (setf *ssl-http-server* (make-instance 'hunchentoot:easy-ssl-acceptor :port 9443 
							  :document-root #p"~/ninestores/hhub/"
							  :ssl-privatekey-file #p"~/ninestores/privatekey.key"
							  :ssl-certificate-file #p"~/ninestores/certificate.crt" ))
(setf (hunchentoot:acceptor-access-log-destination *ssl-http-server* )  #p"~/hhublogs/ninestores-ssl-access.log")
       (setf  (hunchentoot:acceptor-message-log-destination *ssl-http-server*)   #p"~/hhublogs/ninestores-ssl-messages.log")))



(defun stop-das ()
  "优雅停机：关 Hunchentoot、停 actor、清空全局缓存、断 DB。
   被 startup/init.lisp 的 6200 端口监听器在收到 telnet 信号时触发。"
  (format t "******** Stopping SQL Recording *******~C"  #\linefeed)
  (clsql:stop-sql-recording :type :both)
  (format t "******** DB Disconnect ********~C" #\linefeed)
  (clsql:disconnect)
  (format t "******* Stopping HTTP Server *********~C"  #\linefeed)
  (progn (if *ssl-http-server*  (hunchentoot:stop *ssl-http-server*) (hunchentoot:stop *http-server*))
	 (setf *ssl-http-server* nil) 
	 (setf *http-server* nil)
	 (setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS* NIL)
	 (setf *NST-INVOICE-TEMPLATES* NIL)
	 (setf *NST-ORDER-TEMPLATES* NIL)
	 (setf *NST-EMAIL-TEMPLATES* NIL)
	 (setf *NST-CUSTOMER-TEMPLATES* NIL)
	 (setf *HHUBGLOBALBUSINESSFUNCTIONS-HT* NIL)
	 (setf *HHUBBUSINESSSESSIONS-HT* NIL)
	 (deletebusinessserver)
	 (destroy-actor *NSTSENDORDEREMAILACTOR*)
	 (setf *NSTSENDORDEREMAILACTOR* nil)
	 (destroy-actor *NSTAWSS3FILEUPLOADACTOR*)
	 (setf *NSTAWSS3FILEUPLOADACTOR* nil)
	 (setf *NST-ALL-INDIA-PINCODES* nil)
	 ;; clear the OTP store
	 (funcall *otp-store* :clear)))


;;;;*********** Globally Cached lists and their accessor functions *********************************

(defun hhub-gen-globally-cached-lists-functions ()
  "ABAC 缓存预热的核心函数。
   返回一个闭包列表（约 7 项）：分别封装策略、角色、事务、bus-object、abac-subject、
   attr-lookup、companies 等查询结果，对外通过 hhub-get-cached-* 系列函数访问。
   重要：策略热更新后必须 (setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS* (hhub-gen-...))
        否则新策略不会生效。"
  :documentation "These functions are list returning functions. The various lists are accessible throughout the application. For example, list of all the authorization policies, attributes, etc."
  (let ((policies (get-system-auth-policies))
	(roles (get-system-roles))
	(transactions (get-system-bus-transactions))
	(busobjects (get-system-bus-objects))
	(abacsubjects (get-system-abac-subjects))
	(abacattributes (get-system-abac-attributes))
	(transactions-ht (get-system-bus-transactions-ht))
	(policies-ht (get-system-auth-policies-ht))
	(companies (get-system-companies))
	(currencies-ht (get-system-currencies-ht))
	(curr-html-symbols-ht (get-currency-html-symbol-map))
	(curr-fa-symbols-ht (get-currency-fontawesome-map))
	(gst-hsn-codes-ht (get-system-gst-hsn-codes))
	(gst-sac-codes-ht (get-all-gst-sac-codes)))

    (list (function (lambda () policies)) ;0
	  (function (lambda () roles)) ;1
	  (function (lambda () transactions)) ;2
	  (function (lambda () busobjects)) ;3
	  (function (lambda () abacsubjects)) ;4
 	  (function (lambda () abacattributes)) ;5
	  (function (lambda () companies)) ;6
	  (function (lambda () transactions-ht)) ;7
	  (function (lambda () policies-ht)) ;8
	  (function (lambda () currencies-ht)) ;9
	  (function (lambda () curr-html-symbols-ht)) ;10
	  (function (lambda () curr-fa-symbols-ht)) ;11
	  (function (lambda () gst-hsn-codes-ht)) ;12
	  (function (lambda () gst-sac-codes-ht))))) ;13	
;;******************************************************************************************

;; 下面一组 hhub-get-cached-* 函数都是从 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*
;; 中按位置取出闭包并 funcall 拿到具体缓存数据。每个函数对应一种 ABAC/系统级数据。
(defun hhub-get-cached-auth-policies()
  "取系统级 ABAC 策略列表（缓存）。"
  :documentation "This function gets a list of all the globally cached policies."
  (let ((policiesfunc (nth 0  *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall policiesfunc)))

(defun hhub-get-cached-roles ()
  "取系统角色列表（缓存）。"
  :documentation "This function gets a list of all the globally cached roles."
  (let ((rolesfunc (nth 1 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall rolesfunc)))


(defun hhub-get-cached-transactions ()
  "取系统级 ABAC 事务列表（缓存）。"
  :documentation "This function gets a list of all the globally cached transactions."
  (let ((transfunc (nth 2 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall transfunc)))


(defun hhub-get-cached-bus-objects ()
  "取系统级业务对象（资源类型）列表。"
  :documentation "This function gets a list of all the globally cached bus objects for System"
  (let ((busobjfunc (nth 3 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall busobjfunc)))


(defun hhub-get-cached-abac-subjects ()
  "取系统级 ABAC 主体类型列表。"
  :documentation "This function gets a list of all the globally cached ABAC Subjects for System"
  (let ((abacsubjectfunc (nth 4 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall abacsubjectfunc)))


(defun hhub-get-cached-abac-attributes ()
  "取系统级属性元数据列表。"
  :documentation "This function gets a list of all the globally cached ABAC Attrributes for the system"
  (let ((abacattributesfunc (nth 5  *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall abacattributesfunc)))


(defun hhub-get-cached-companies ()
  "取系统已知公司列表（启动时一次性加载）。"
  :documentation "This function gets a list of all the globally cached transactions in a Hashtable."
 (let ((companies-func (nth 6 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
   (funcall companies-func)))

(defun hhub-get-cached-transactions-ht ()
  "取系统事务的哈希表 trans-func → transaction，PEP 用 O(1) 查找。"
  :documentation "This function gets a list of all the globally cached transactions in a Hashtable."
 (let ((transfunc-ht (nth 7 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall transfunc-ht)))

(defun hhub-get-cached-auth-policies-ht ()
  "取策略哈希表 row-id → policy 实例，被 has-permission（PDP）查找。"
  :documentation "This function gets a list of all the globally cached ABAC policies in a hashtable."
  (let ((policiesfunc-ht (nth 8 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall policiesfunc-ht)))

(defun hhub-get-cached-currencies-ht ()
  "取币种哈希表（country → (currency code symbol)）。"
  :documentation "This function gets a list of all the globally cached currencies."
  (let ((currencies-ht (nth 9 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall currencies-ht)))

(defun hhub-get-cached-currency-html-symbols-ht ()
  "取币种 HTML 实体符号哈希表（INR → '&#8377;' 等）。"
  :documentation "This function gets a list of all the globally cached currencies."
  (let ((currency-html-symbols-ht (nth 10 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall currency-html-symbols-ht)))

(defun hhub-get-cached-currency-fontawesome-symbols-ht ()
  "取币种 FontAwesome 图标 class 哈希表。"
  :documentation "This function gets a list of all the globally cached currencies."
  (let ((currency-fa-symbols-ht (nth 11 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall currency-fa-symbols-ht)))

(defun hhub-get-cached-gst-hsn-codes-ht ()
  "取 GST HSN 编码哈希表（4MB+，启动时一次性载入）。"
  :documentation "This function gets a hash table which contains gst hsn codes."
  (let ((gst-hsn-codes-func  (nth 12 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall gst-hsn-codes-func)))

(defun hhub-get-cached-gst-sac-codes-ht ()
  "取 GST SAC（服务）编码哈希表。"
  :documentation "This function gets a hash table which contains gst hsn codes."
  (let ((gst-sac-codes-func  (nth 13 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*)))
    (funcall gst-sac-codes-func)))


(defun hhub-init-business-function-registrations ()
  "启动期登记 *HHUBGLOBALBUSINESSFUNCTIONS-HT* 中的业务函数（被 start-das 调用）。"
  :documentation "This function will be called at system startup time to register all the business functions"
  (hhub-register-business-function "com.hhub.businessfunction.getpushnotifysubscriptionforvendor" "com-hhub-businessfunction-getpushnotifysubscriptionforvendor"))


(defun nst-load-core-templates ()
  "把 core/templates 下的 webrepltemplate.html / aboutuspage.html 等装载进
   *NST-CORE-TEMPLATES* 哈希表（启动时调用一次）。"
  (let ((webrepltemplatehtml (hhub-read-file *NST-WEBREPL-TEMPLATE*))
	(aboutuspagehtml (hhub-read-file *NST-ABOUTUSPAGE-TEMPLATE*)))
    (function (lambda ()
      (values (function (lambda () webrepltemplatehtml))
	      (function (lambda () aboutuspagehtml)))))))

(defun nst-get-cached-core-template-func (&key templatenum)
  "按 templatenum 索引取出 core 模板渲染闭包。"
  :documentation "returns the function responsible for invoice email HTML template. Call the returning function to get the HTML."
  (multiple-value-bind (webrepltemplatehtmlfunc aboutuspagehtmlfunc) (funcall *NST-CORE-TEMPLATES*)
    (case templatenum
      (1 webrepltemplatehtmlfunc)
      (2 aboutuspagehtmlfunc))))



;;;;;;;;;;;;;Agentic AI Experiment with ollama;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun nst-load-vendor-tables-structure-for-agentic-ai ()
  "把 vendor 相关三张表的 schema TXT 文件载入；供 nl-to-sql / Ollama agent 用作 schema 上下文。"
  (let ((vendprofiletable  (hhub-read-file *dod-vend-profile-table*))
	(invoiceheadertable (hhub-read-file *dod-invoice-header-table*))
	(invoiceitemstable (hhub-read-file *dod-invoice-items-table*)))
    (function (lambda ()
      (values (function (lambda () vendprofiletable))
	      (function (lambda () invoiceheadertable))
	      (function (lambda () invoiceitemstable)))))))

(defun nst-get-cached-vendor-tables-structure-for-agentic-ai  (&key templatenum)
  "按 templatenum 取出 vendor schema 字符串闭包（1=vend-profile / 2=invoice-header / 3=invoice-items）。"
  :documentation "returns the function responsible for invoice email HTML template. Call the returning function to get the HTML."
  (multiple-value-bind (vendprofiletablefunc invoiceheadertablefunc invoiceitemstablefunc) (funcall *NST-VENDOR-TABLES-FOR-AGENTIC-AI*)
    (case templatenum
      (1 vendprofiletablefunc)
      (2 invoiceheadertablefunc)
      (3 invoiceitemstablefunc))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun nst-load-invoice-templates ()
  "载入全部发票 HTML 模板（draft/paid/cancelled/refunded/payreminder/...）+ 5 个 GST 模板，
   存到 *NST-INVOICE-TEMPLATES* 哈希表。"
  :documentation "Load the invoice templates at startup"
  (let* ((draftemailhtml (hhub-read-file *NST-INVOICEDRAFT-TEMPLATEFILE*))
	 (invoicepaymenthtml (hhub-read-file *NST-INVOICEPAYMENT-TEMPLATEFILE*))
	 (paymentreminderhtml (hhub-read-file *NST-INVOICEPAYREMINDER-TEMPLATEFILE*))
	 (overduepaymentreminderhtml (hhub-read-file *NST-INVOICEPAYOVERDUEREMINDER-TEMPLATEFILE*))
	 (invoicepaidhtml (hhub-read-file *NST-INVOICEPAID-TEMPLATEFILE*))
	 (invoiceshippedhtml (hhub-read-file *NST-INVOICESHIPPED-TEMPLATEFILE*))
	 (invoicecancelledhtml (hhub-read-file *NST-INVOICECANCELLED-TEMPLATEFILE*))
	 (invoicerefundedhtml (hhub-read-file *NST-INVOICEREFUNDED-TEMPLATEFILE*))
	 (invoicesettingshtml (hhub-read-file *NST-INVOICESETTINGS-HTMLFILE*))
	 (invoicesettingsyaml (hhub-read-file *NST-INVOICESETTINGS-YAMLFILE*))
	 (gstinvoice1html (hhub-read-file *NST-GSTINVOICE-TEMPLATEFILE-1*))
	 (gstinvoice2html (hhub-read-file *NST-GSTINVOICE-TEMPLATEFILE-2*))
	 (gstinvoice3html (hhub-read-file *NST-GSTINVOICE-TEMPLATEFILE-3*))
	 (gstinvoice4html (hhub-read-file *NST-GSTINVOICE-TEMPLATEFILE-4*))
	 (gstinvoice5html (hhub-read-file *NST-GSTINVOICE-TEMPLATEFILE-5*)))
    (function (lambda ()
      (values (function (lambda () draftemailhtml))
	      (function (lambda () invoicepaymenthtml))
	      (function (lambda () paymentreminderhtml))
	      (function (lambda () overduepaymentreminderhtml))
	      (function (lambda () invoicepaidhtml))
	      (function (lambda () invoiceshippedhtml))
	      (function (lambda () invoicecancelledhtml))
	      (function (lambda () invoicerefundedhtml))
	      (function (lambda () gstinvoice1html))
	      (function (lambda () gstinvoice2html))
	      (function (lambda () gstinvoice3html))
	      (function (lambda () gstinvoice4html))
	      (function (lambda () gstinvoice5html))
	      (function (lambda () invoicesettingshtml))
	      (function (lambda () invoicesettingsyaml)))))))


(defun nst-get-cached-invoice-template-func (&key templatenum)
  "按 templatenum 索引取已缓存的发票模板字符串闭包。"
  :documentation "returns the function responsible for invoice email HTML template. Call the returning function to get the HTML."
  (multiple-value-bind (draftemailhtmlfunc invoicepaymenthtmlfunc paymentreminderhtmlfunc overduepaymentreminderhtmlfunc invoicepaidhtmlfunc invoiceshippedhtmlfunc invoicecancelledhtmlfunc invoicerefundedhtmlfunc gstinvoice1htmlfunc gstinvoice2htmlfunc gstinvoice3htmlfunc gstinvoice4htmlfunc gstinvoice5htmlfunc invoicesettingshtmlfunc invoicesettingsyamlfunc) (funcall *NST-INVOICE-TEMPLATES*)
    (case templatenum
      (1 draftemailhtmlfunc)
      (2 paymentreminderhtmlfunc)
      (3 overduepaymentreminderhtmlfunc)
      (4 invoicepaidhtmlfunc)
      (5 invoiceshippedhtmlfunc)
      (6 invoicecancelledhtmlfunc)
      (7 invoicerefundedhtmlfunc)
      (8 invoicepaymenthtmlfunc)
      (9 gstinvoice1htmlfunc)
      (10 gstinvoice2htmlfunc)
      (11 gstinvoice3htmlfunc)
      (12 gstinvoice4htmlfunc)
      (13 gstinvoice5htmlfunc)
      (14 invoicesettingshtmlfunc)
      (15 invoicesettingsyamlfunc))))

;;;;;;;;;;;;;; PRODUCT TEMPLATES ;;;;;;;;;;;;;;;;;;;;;;;;

(defun nst-load-product-templates ()
  "载入商品页 HTML 模板（客户视图/卖家视图）。"
  :documentation "Load the product templates at startup"
  (let* ((prddetailsforcusthtml  (hhub-read-file *NST-PRDDETAILSFORCUST-TEMPLATEFILE*))
	 (prddetailsforvendhtml  (hhub-read-file *NST-PRDDETAILSFORVEND-TEMPLATEFILE*)))
    (function (lambda ()
      (values
       (function (lambda () prddetailsforcusthtml))
       (function (lambda () prddetailsforvendhtml)))))))

(defun nst-get-cached-product-template-func (&key templatenum)
  "按 templatenum 取已缓存的商品模板闭包。"
  :documentation "returns the function responsible for product HTML template. Call the returning function to get the HTML."
  (multiple-value-bind (prddetailsforcusthtmlfunc prddetailsforvendhtmlfunc) (funcall *NST-PRODUCT-TEMPLATES*)
    (case templatenum
      (1 prddetailsforcusthtmlfunc)
      (2 prddetailsforvendhtmlfunc))))

;;;;;;;;;;;;;;;;;;;;;;;ORDER TEMPLATES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun nst-load-order-templates ()
  "载入订单 HTML 模板。"
  :documentation "Load the order templates at startup"
  (let* ((ordertemplate1  (hhub-read-file *NST-ORDER-TEMPLATEFILE-1*))
	 (ordertemplate2  (hhub-read-file *NST-ORDER-TEMPLATEFILE-2*)))
    (function (lambda ()
      (values
       (function (lambda () ordertemplate1))
       (function (lambda () ordertemplate2)))))))

(defun nst-get-cached-order-template-func (&key templatenum)
  "按 templatenum 取已缓存的订单模板闭包。"
  :documentation "returns the function responsible for order HTML template. Call the returning function to get the HTML."
  (multiple-value-bind (ordertemplate1 ordertemplate2) (funcall *NST-ORDER-TEMPLATES*)
    (case templatenum
      (1 ordertemplate1)
      (2 ordertemplate2))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;CUSTOMER TEMPLATES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun nst-load-customer-templates ()
  "载入客户自助门店相关 HTML 模板。"
  :documentation "Load the order templates at startup"
  (let* ((duplicatecustomertemplate  (hhub-read-file *NST-DUPLICATE-CUSTOMER-TEMPLATEFILE*)))
    (function (lambda ()
      (values
       (function (lambda () duplicatecustomertemplate)))))))

(defun nst-get-cached-customer-template-func (&key templatenum)
  "按 templatenum 取已缓存的客户模板闭包。"
  :documentation "returns the function responsible for order HTML template. Call the returning function to get the HTML."
  (multiple-value-bind (duplicatecustomertemplate) (funcall *NST-CUSTOMER-TEMPLATES*)
    (case templatenum
      (1 duplicatecustomertemplate))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;EMAIL TEMPLATES ;;;;;;;;;;;;;;;;;;;;;;;;

(defun nst-load-email-templates ()
  "载入邮件 HTML 模板（注册/忘记密码/临时密码/新公司请求/Contact-us 等）。"
  :documentation "Load the product templates at startup"
  (let* ((order-email-template (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER* *HHUB-GUEST-CUST-ORDER-TEMPLATE-FILE*))))
    (function (lambda ()
      (values (function (lambda () order-email-template)))))))

(defun nst-get-cached-email-template-func (&key templatenum)
  "按 templatenum 取已缓存的邮件模板闭包。"
  :documentation "returns the function responsible for product HTML template. Call the returning function to get the HTML."
  (multiple-value-bind (orderemailtempl) (funcall *NST-EMAIL-TEMPLATES*)
    (case templatenum
      (1 orderemailtempl))))








;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;; Nine Stores GLOBAL BUSINESS FUNCTIONS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun hhub-register-business-function (name funcsymbol)
  "把 (name → funcsymbol) 映射注册到 *HHUBGLOBALBUSINESSFUNCTIONS-HT*。
   备注：与 dod-bl-utl.lisp 中的 hhub-register-network-function 类似但不要求严格名字校验。"
:documentation "This function registers a new business function and adds it to the *HHUBGLOBALBUSINESSFUNCTIONS-HT* Hash Table. It should conform to naming convention com.hhub.businessfunction*"
  (multiple-value-bind (fname) (ppcre:scan "com.hhub.businessfunction.*" name)
    (when fname
      (multiple-value-bind (fsymbol) (ppcre:scan "com-hhub-businessfunction-*" funcsymbol)
	(when fsymbol
	  (setf (gethash name  *HHUBGLOBALBUSINESSFUNCTIONS-HT*) funcsymbol))))))


(defun hhub-execute-business-function (name params)
  "通用业务函数执行入口（与 dod-bl-utl.lisp 中的 -network- 同义）。
   按 name 在哈希表里取符号 → intern → funcall；统一捕获 hhub-business-function-error 与通用 error。"
  :documentation "This is a general business function adapter for HHub. It takes parameters in a association list"
(handler-case 
    (let ((funcsymbol (gethash name *HHUBGLOBALBUSINESSFUNCTIONS-HT*)))
      (if (null funcsymbol) (error 'hhub-business-function-error :errstring "Business function not registered"))
      (multiple-value-bind (returnvalues exception) (funcall (intern  (string-upcase funcsymbol) :hhub) params)
	;Return a list of return values and exception as nil. 
	(list returnvalues exception)))
  (hhub-business-function-error (condition)
    (list nil (format nil "HHUB Business Function error triggered in Function - ~A. Error: ~A" (string-upcase name) (getExceptionStr condition))))
  ; If we get any general error we will not throw it to the upper levels. Instead set the exception and log it. 
  (error (c)
    (let ((exceptionstr (format nil  "HHUB General Business Function Error: ~A  ~a~%" (string-upcase name) c)))
      (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
			   :direction :output
			   :if-exists :supersede
			   :if-does-not-exist :create)
	(format stream "~A" exceptionstr))
      (list nil (format nil "HHUB General Business Function Error. See logs for more details."))))))



(defun hhub-init-business-functions ()
  "启动期把所有业务函数批量登记到哈希表（被 start-das 调用）。"
  (hhub-register-business-function "com.hhub.businessfunction.bl.getpushnotifysubscriptionforvendor" "com-hhub-businessfunction-bl-getpushnotifysubscriptionforvendor")
;;  (hhub-register-business-function "com.hhub.businessfunction.tempstorage.getpushnotifysubscriptionforvendor" "com-hhub-businessfunction-tempstorage-getpushnotifysubscriptionforvendor")
  (hhub-register-business-function "com.hhub.businessfunction.db.getpushnotifysubscriptionforvendor" "com-hhub-businessfunction-db-getpushnotifysubscriptionforvendor")
  ;; Business functions for Creating Push Notify Subscription for Vendor 
  (hhub-register-business-function "com.hhub.businessfunction.bl.createpushnotifysubscriptionforvendor" "com-hhub-businessfunction-bl-createpushnotifysubscriptionforvendor")
  (hhub-register-business-function "com.hhub.businessfunction.tempstorage.createpushnotifysubscriptionforvendor" "com-hhub-businessfunction-tempstorage-createpushnotifysubscriptionforvendor")
  (hhub-register-business-function "com.hhub.businessfunction.db.createpushnotifysubscriptionforvendor" "com-hhub-businessfunction-db-createpushnotifysubscriptionforvendor"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;; NINE STORES GLOBAL BUSINESS FUNCTIONS END ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;; EXPERIMENTING WITH DOMAIN DRIVEN DESIGN ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defgeneric initBusinessContexts (BusinessServer ListContextNames)
  (:documentation "This generic function will initialize the business contexts for the business server"))



(defmethod initBusinessContexts ((server BusinessServer) ListContextNames)
  "按名字列表为 BusinessServer 初始化多个 BusinessContext（DDD 用）。"
  (let* ((contexts (mapcar (lambda (contextname) 
			     (let ((site (make-instance 'BusinessContext)))
			       (setf (slot-value site 'id)  (format nil "~A" (uuid:make-v1-uuid )))
			       (setf (slot-value site 'name) contextname)
			       site)) ListContextNames)))
    contexts))

    
(defun initBusinessServer ()
  "创建 BusinessServer 单例 *HHUBBUSINESSSERVER* 并初始化关键 BusinessContext 列表。
   被 start-das 调用，是 DDD 层的入口装配点。"
  (let ((business-server  (make-instance 'BusinessServer)))
    (setf (slot-value business-server 'ipaddress) "127.0.0.1") ;; Not useful Today. May be on future.
    (setf (slot-value business-server 'name) "NineStores")
    (setf (slot-value business-server 'id)  (format nil "~A" (uuid:make-v1-uuid )))
    (setf (slot-value business-server 'BusinessContexts) (initBusinessContexts business-server (list "vendorsite" "compadminsite")))
    business-server))


(defun deleteBusinessServer ()
  "停机时清空 *HHUBBUSINESSSERVER* / 业务 session HT 等 DDD 层状态。"
  (let ((businesscontexts (slot-value *HHUBBUSINESSSERVER* 'BusinessContexts)))
    (loop for bc in businesscontexts do
      (let ((name (slot-value bc 'name)))
	(deletebusinesscontext *HHUBBUSINESSSERVER* name))) 
    (setf *HHUBBUSINESSSERVER* NIL)
    (sb-ext:gc :full t)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;; EXPERIMENTING WITH DOMAIN DRIVEN DESIGN -- END  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  
