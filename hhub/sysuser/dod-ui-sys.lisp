;;; dod-ui-sys.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：sysuser —— 超级管理员（OPR / SADMIN）后台 + 系统级路由表
;;;; 分层：UI（控制器 + CL-WHO 模板）
;;;; 文件：hhub/sysuser/dod-ui-sys.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：本文件是整个 Nine Stores 的 *中心路由* 与 *系统超管 (SADMIN/OPR) 后台*：
;;;;   - 通用：权限拒绝页、OTP 流程（请求 / 提交 / 重发）
;;;;   - 超管：登录 / 注销 / 主页 / 个人资料 / 仪表盘
;;;;   - 公司账户运维：suspend / restore / 创建公司 / 新公司申请页 / 列表搜索
;;;;   - 系统运维：DB 重置页 + 动作、daily orders 批处理触发
;;;;   - ABAC 后台：业务对象 / 主体 / 事务 / 属性 列表页
;;;;   - 路由：在文件末尾用一长串 hunchentoot:create-regex-dispatcher 注册全平台 URL
;;;;     —— 包括 SADMIN / CAD / Customer / Vendor 各模块所有控制器（约 220 条）。
;;;;
;;;; 主要导出：
;;;;   hhub-controller-permission-denied
;;;;   dod-controller-OTP-request-page / dod-controller-otp-submit-action /
;;;;   dod-controller-otp-regenerate-action / generateotp&redirect
;;;;   com-hhub-transaction-suspend-account / -restore-account
;;;;   com-hhub-transaction-system-dashboard / -sadmin-profile / -sadmin-home /
;;;;     -sadmin-login / -refresh-iam-settings / -create-company / -create-company-dialog /
;;;;     -request-new-company
;;;;   dod-controller-run-daily-orders-batch
;;;;   dod-controller-dbreset-page / -dbreset-action
;;;;   company-search-html / company-subscription-plan-dropdown / company-type-dropdown
;;;;   dod-controller-new-company-request-page / -new-store-request-step2 /
;;;;     -new-company-request-email / -company-search-for-sys-action
;;;;   hhub-controller-new-community-store-request-page
;;;;   dod-controller-abac-security / -list-busobjs / -list-abac-subjects /
;;;;     -list-bustrans / -list-attrs
;;;;   dod-controller-loginpage / -logout
;;;;   IAM-security-page-header
;;;;   create-model-for-sadminhome / create-widgets-for-sadminhome
;;;;   create-model-for-sadminlogin / create-model-for-sadminlogout
;;;;   is-dod-session-valid? / dod-login / get-tenant-id / get-tenant-name /
;;;;     get-login-user-object / is-user-already-login? / add-login-user / dod-logout
;;;;   *logged-in-users* / *current-user-session*
;;;;   hunchentoot:*dispatch-table* —— 平台总路由表（在文件末尾 setq 一次写完）
;;;;
;;;; 关联：
;;;;   上游：浏览器（基本所有 /hhub/* 路径）
;;;;   下游：core/dod-ui-utl.lisp（PEP 宏 / MVC 框架）、
;;;;         products/order/customer/vendor/invoice 等所有控制器（被路由表绑定）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;; ----------------------------------------------------------------------------
;; 全局：本进程内已登录用户表（哈希/列表 表示，由 add-login-user / dod-logout 维护）
;; 与当前活跃 user-session 引用。
;; ----------------------------------------------------------------------------
(defvar *logged-in-users* nil)
(defvar *current-user-session* nil)

(defun hhub-controller-permission-denied ()
  "URL：/hhub/permissiondenied。
   渲染权限拒绝页：图片 + 'Permission Denied' 标题 + 返回按钮，
   query 参数 message 由 jscript-displayerror 弹窗展示具体原因。"
  (let ((message (hunchentoot:parameter "message")))
    (with-no-navbar-page-v2 "Permission Denied"
      (:div :class "card"
	    (:img :src "/img/permissiondenied.jpg"  :class "rounded-lg  mx-auto d-block mt-3" :alt "Standard Shipping" :style "width: 300px; height: 300px;")
	    (:div :class "card-body text-center"
		  (:h2 :class "card-title" "Permission Denied")
		  (:h3 :class "card-text"
		       (cl-who:str (html-back-button)))))
      (jscript-displayerror message))))


(defun dod-controller-OTP-request-page ()
  "URL：/hhub/otppage?session=<id>&phone=<10digit>。
   OTP 输入页：展示掩码电话、输入框、倒计时 + 重发按钮（POST hhubotpregenerateaction）。
   提交 OTP 走 hhubotpsubmitaction。"
  (let ((session-id (hunchentoot:parameter "session"))
	(phone (hunchentoot:parameter "phone")))
    (with-no-navbar-page-v2  "OTP Page"
      (:br)
      (:div :class "account-wall" :align "center"
	    (with-html-card
		(:title "OTP Login Page"
		 :image-src "/img/logo.png"
		 :image-alt "OTP Login to Nine Stores"
		 :image-style "width: 200px; height: 200px;")
	      (:h3 (cl-who:str (format nil "OTP has been sent to your phone ~A" (concatenate 'string "xxxxx" (subseq phone 6)))))
	      (with-html-form-having-submit-event  "form-hhubotppage" "hhubotpsubmitaction" 
		(:div :id "withCountDownTimerExpired"
		      (with-html-input-text-hidden "session" session-id)
		      (with-html-input-text "otp" "One Time Password" "Enter OTP" nil T "Please enter OTP" "1" :autocomplete "one-time-code" :inputmode "numeric" :pattern "[0-9]*" :maxlength "6")
		      (:p :id "withCountDownTimer" :style "color: crimson;")
		      (:div :class "form-group"
			    (:button :class "submit center-block btn btn-primary btn-block" :type "submit" "Send OTP"))))
	      (with-html-form-having-submit-event  "form-hhubotpresendpage" "hhubotpregenerateaction"
		(:div :class "form-group"
		      (with-html-input-text-hidden "session" session-id)
		      (with-html-input-text-hidden "phone" phone)
		      (:button :class "submit center-block btn btn-primary btn-block" :type "submit" (cl-who:str  (format nil "Regenerate OTP for ~A " (concatenate 'string "xxxxx" (subseq phone 6)))))))
	      (hhub-html-page-footer)))
      (:script "window.onload = function() {countdowntimer(0,0,2,0);}"))))

(defun dod-controller-otp-submit-action ()
  "URL：/hhub/hhubotpsubmitaction。校验 OTP，根据保存的 context 跳转。"
  (with-mvc-redirect-ui #'create-model-for-otpsubmitaction #'create-widgets-for-genericredirect))

(defun create-model-for-otpsubmitaction ()
  "OTP 提交 model：从 *otp-store* 取出与 session 绑定的 OTP 与 context；
   - 与用户输入一致 → 跳转到 /hhub/<context>（之前发起 OTP 时记下的目的地）；
   - 不一致 → 跳回 *siteurl* 首页。"
  (let* ((otp (hunchentoot:parameter "otp"))
	 (session (hunchentoot:parameter "session"))
	 (context (funcall *otp-store* :get-context :session-id session))
	 (sessionotp (funcall *otp-store* :get-otp :session-id session))
	 (redirecturl nil))
    
    (hunchentoot:log-message* :info (format nil "context is ~A otp is ~A sessionotp is ~A" context otp sessionotp))
    (if (equal (parse-integer otp) sessionotp)
	(setf redirecturl (format nil "/hhub/~A" context))
	;; else
	(setf redirecturl *siteurl*))
    (function (lambda ()
      (values redirecturl)))))
  

(defun dod-controller-otp-regenerate-action ()
  "URL：/hhub/hhubotpregenerateaction。
   重发 OTP：从原 session 中取 persona/purpose/context，调用 generateotp&redirect 重新生成。"
  (let* ((session (hunchentoot:parameter "session"))
	 (phone (hunchentoot:parameter "phone"))
	 (context (funcall *otp-store* :get-context :session-id session))
	 (persona (funcall *otp-store* :get-persona :session-id session))
	 (purpose (funcall *otp-store* :get-purpose :session-id session)))
    (generateotp&redirect persona purpose phone context)))
   

(defun generateotp&redirect (persona purpose phone context)
  :description "This function will generate OTP, save it to the session, send SMS to the phone number with OTP message and then redirect to OTP entering page, also remembering the context where to redirect after entering the OTP successfully.
   中文：生成 6 位 OTP（random 999999） + 8 位会话 id，写入 *otp-store*；
         若 *HHUBOTPTESTING* 真则只写日志（测试模式），否则通过 AWS SNS 发短信。
         返回字符串：'/hhub/otppage?session=<id>&phone=<phone>' 跳转目标。"
  (let ((otp (random 999999))
	(session-id (hhub-random-password 8)))
    ;; Set the otp to the session value 
    (funcall *otp-store* :set
	     :session-id session-id 
	     :persona persona
             :purpose purpose
             :phone phone
             :otp otp
             :context context
             :ip (hunchentoot:real-remote-addr))
    ;; Send SMS to the phone with OTP template text 
    (if *HHUBOTPTESTING*
	(hunchentoot:log-message* :info (format nil "sessionotp is ~A" otp))
	;;else 
	(send-sms-notification phone *HHUBAWSSNSSENDERID* (format nil *HHUBAWSSNSOTPTEMPLATETEXT* "Login Transaction" otp)))
    ;; redirect to the OTP page 
    (format nil "/hhub/otppage?session=~A&phone=~A" session-id phone)))

(defun com-hhub-transaction-suspend-account ()
  :documentation "This is a controller method which will suspend an Account.
   中文：URL：/hhub/suspendaccount?tenant-id=<id>。SADMIN/OPR 暂停某租户账户（调 suspendaccount BL）。"
  (with-opr-session-check
    (let ((params nil)
	  (tenant-id (hunchentoot:parameter "tenant-id")))
      (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
      (setf params (acons "uri" (hunchentoot:request-uri*)  params))
      (with-hhub-transaction "com-hhub-transaction-suspend-account" params 
	(suspendaccount tenant-id))
      (hunchentoot:redirect "/hhub/sadminhome"))))

(defun com-hhub-transaction-restore-account ()
  :documentation "This is a controller method which will suspend an Account.
   中文：URL：/hhub/restoreaccount?tenant-id=<id>。
         恢复一个被 suspend 的租户账户（注：原 docstring 文案误写 'suspend'）。"
  (with-opr-session-check
    (let ((params nil)
	  (tenant-id (hunchentoot:parameter "tenant-id")))
      (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
      (setf params (acons "uri" (hunchentoot:request-uri*)  params))
      (with-hhub-transaction "com-hhub-transaction-restore-account" params 
	(restoreaccount tenant-id))
      (hunchentoot:redirect "/hhub/sadminhome"))))


(defun com-hhub-transaction-system-dashboard ()
  ;; URL：/hhub/hhubdiagnostics（推测）。占位：系统诊断/仪表盘控制器，目前空实现。
)


(defun com-hhub-transaction-sadmin-profile ()
  "URL：/hhub/hhubsadminprofile。SADMIN 个人资料页：list-group 入口
   GST HSN 维护 / 项目符号查找 / 重置密码（占位）/ Feature Wishlist / Bug 反馈。"
 (with-opr-session-check
    (with-standard-admin-page (:title "welcome to Nine Stores")
       (:h3 "Welcome " (cl-who:str (format nil "~a" (get-login-user-name))))
       (:hr)
      (:div :class "list-group col-sm-6 col-md-6 col-lg-6 col-xs-12"
	    (:a :class "list-group-item" :href "/hhub/gsthsncodes" "GST HSN & SAC Codes")
	    (:a :class "list-group-item" :href "/hhub/projsymlookup" "Project Symbol Lookup")
	    (:a :class "list-group-item" :href "#" "Reset Password")
	    (:a :class "list-group-item" :href *HHUBFEATURESWISHLISTURL* "Feature Wishlist")
	    (:a :class "list-group-item" :href *HHUBBUGSURL* "Report Issues")))))

(defun dod-controller-run-daily-orders-batch ()
 :documentation "This controller function is responsible to run the daily orders batch against all the subscriptions customers have made for a particular group/apartment/tenant.
   中文：URL：/hhub/rundailyordersbatch。手动触发 daily-orders 批处理（前 7 天 lookback），返回 JSON。"
  (let ((batchresult (run-daily-orders-batch 7)))
    (json:encode-json-to-string batchresult)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro with-admin-navigation-bar ()
    :documentation "This macro returns the html text for generating a navigation bar using bootstrap.
   中文：超管后台顶部 Bootstrap 导航栏宏 —— 左侧 Home / IAM Security，
         右侧 My Profile / Logout。被 with-standard-admin-page 等模板使用。"
    `(cl-who:with-html-output (*standard-output* nil)
       (:div :class "navbar navbar-default navbar-inverse navbar-static-top"
	     (:div :class "container-fluid"
		   (:div :class "navbar-header"
			 (:button :type "button" :class "navbar-toggle" :data-toggle "collapse" :data-target "#navHeaderCollapse"
				  (:span :class "icon-bar")
				  (:span :class "icon-bar")
				  (:span :class "icon-bar"))
			 (:a :class "navbar-brand" :href "#" :title "Nine Stores" (:img :style "width: 30px; height: 30px;" :src "/img/logo.png" )  ))
		   (:div :class "collapse navbar-collapse" :id "navHeaderCollapse"
			 (:ul :class "nav navbar-nav navbar-left"
			      (:li :class "active" :align "center" (:a :href "/hhub/sadminhome"  (:i :class "fa-solid fa-house")  "&nbsp;Home"))
			      (:li  (:a :href "/hhub/dasabacsecurity" "IAM Security"))
			      (:li :align "center" (:a :href "#" (print-web-session-timeout))))
			 
			 (:ul :class "nav navbar-nav navbar-right"
			      (:li :align "center" (:a :href "hhubsadminprofile"   (:i :class "fa-regular fa-user") "&nbsp;My Profile" )) 
			      (:li :align "center" (:a :href "dodlogout"  (:i :class "fa-solid fa-arrow-right-from-bracket"))))))))))
  
  
(defun dod-controller-dbreset-page ()
  :documentation "No longer used now.
   中文：URL：/hhub/dbreset.html（推测）。已弃用 —— 旧版 'restart 站点' 表单。"
  (with-standard-admin-page (:title "Restart Higirisehub.com")
    (:div :class "row"
	  (:div :class "col-sm-12 col-md-12 col-lg-12"
		(:form :id "restartsiteform" :method "POST" :action "dbresetaction"
		       (:div :class "form-group"
			     (:input :class "form-control" :name "password" :placeholder "password"  :type "password"))
		       (:div :class "form-group"
			     (:input :type "submit" :name "submit" :class "btn btn-primary" :value "Go...      ")))))))




(defun dod-controller-dbreset-action ()
  :documentation "No longer used now.
   中文：URL：/hhub/dbresetaction（已弃用）。校验 password 与 *sitepass* 后 stop-das + start-das 重启 DB 连接。"
  (let ((pass (hunchentoot:parameter "password")))
    (if (equal (encrypt  pass "ninestores.in") *sitepass*)
       (progn  (stop-das) 
	      (start-das) 
	      (with-standard-admin-page (:title "Restart Ninestores")
		(:h3 "DB Reset successful"))))))







(defun company-search-html ()
  "渲染 SADMIN 主页顶部公司 livesearch 输入框，AJAX 提交到 dodsyssearchtenantaction
   并替换 #accountlivesearchresult。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
	  (:div :id "custom-search-input"
		(:div :class "input-group col-xs-12 col-sm-6 col-md-6 col-lg-6"
		      (with-html-search-form "idsyssearchtenant" "syssearchtenant" "idaccountlivesearch" "accountlivesearch" "dodsyssearchtenantaction" "onkeyupsearchform1event();" "Search for an Apartment/Group"
			(submitsearchform1event-js "#idaccountlivesearch" "#accountlivesearchresult")))))))

(defun com-hhub-transaction-create-company-dialog (&optional id)
  "Add/Edit Company 模态对话框 fragment（创建租户公司）。
   传 id 表示编辑现有公司，预填字段；不传则空表单。
   字段：cmpname / cmpaddress / city / state / country（默认 IND）/ zipcode / website /
        cmp-type / subscription-plan。POST 到 /hhub/createcompanyaction。"
  (let* ((company (if id (select-company-by-id id)))
	 (cmpname (if company (slot-value company 'name)))
	 (cmpaddress (if company(slot-value company 'address)))
	 (cmpcity (if company (slot-value company 'city)))
	 (cmpstate (if company (slot-value company 'state)))
	 (cmpwebsite (if company (slot-value company 'website)))
	 (cmpzipcode (if company (slot-value company 'zipcode)))
	 (cmp-type (if company (slot-value company 'cmp-type)))
	 (subscription-plan (if company (slot-value company 'subscription-plan))))
    
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form "form-addcompany" "createcompanyaction"
		    (if company (cl-who:htm (:input :class "form-control" :type "hidden" :value id :name "id")))
		    (:img :class "profile-img" :src "/img/logo.png" :alt "")
		    (:div :class "form-group"
			  (:input :class "form-control" :name "cmpname" :maxlength "30"  :value cmpname :placeholder "Name ( max 30 characters) " :type "text" ))
		    (:div :class "form-group"
			  (:label :for "cmpaddress")
			  (:textarea :class "form-control" :name "cmpaddress"  :placeholder "Address ( max 400 characters) "  :rows "5" :onkeyup "countChar(this, 400)" (cl-who:str cmpaddress) ))
		    (:div :class "form-group" :id "charcount")
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value cmpcity :placeholder "City"  :name "cmpcity" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value cmpstate :placeholder "State"  :name "cmpstate" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value "INDIA" :readonly "true"  :name "cmpcountry" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :maxlength "6" :value cmpzipcode :placeholder "Pincode" :name "cmpzipcode" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :maxlength "256" :value cmpwebsite :placeholder "Website" :name "cmpwebsite" ))
		    (with-html-div-row
		      (with-html-div-col
			(company-type-dropdown "cmp-type" cmp-type)))
		    
		    (with-html-div-row
		      (with-html-div-col
			(company-subscription-plan-dropdown "subscription-plan" subscription-plan )))
		    (:div :class "form-group"
			  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))

(defun company-subscription-plan-dropdown (name selectedkey)
  "渲染订阅计划下拉框（TRIAL / BASIC / PROFESSIONAL）。selectedkey 命中预选。"
  (let ((subsplan-ht (make-hash-table)))
    (setf (gethash "TRIAL" subsplan-ht) "TRIAL")
    (setf (gethash "BASIC" subsplan-ht) "BASIC")
    (setf (gethash "PROFESSIONAL" subsplan-ht)  "PROFESSIONAL")
    (with-html-dropdown name subsplan-ht selectedkey)))
    
    

(defun company-type-dropdown (name selectedkey)
  "公司业态下拉框（DEFAULT / GROCERY / APPAREL / MOBILE / FASHION JEWELLERY /
   HYPERMARKET / COMPUTER HARDWARE / SPORTS / FURNITURE / COMMUNITY / STATIONARY /
   PHOTO SHOP / FARMERS MARKET）。"
  (let ((cmptype-ht (make-hash-table)))
    (setf (gethash "DEFAULT" cmptype-ht) "DEFAULT")
    (setf (gethash "GROCERY" cmptype-ht) "GROCERY") 
    (setf (gethash "APPAREL" cmptype-ht) "APPAREL")
    (setf (gethash "MOBILE" cmptype-ht) "MOBILE")
    (setf (gethash "FASHION JEWELLERY" cmptype-ht) "FASHION JEWELLERY")
    (setf (gethash "HYPERMARKET" cmptype-ht) "HYPERMARKET")
    (setf (gethash "COMPUTER HARDWARE" cmptype-ht) "COMPUTER HARDWARE")
    (setf (gethash "SPORTS" cmptype-ht) "SPORTS")
    (setf (gethash "FURNITURE" cmptype-ht) "FURNITURE")
    (setf (gethash "COMMUNITY" cmptype-ht) "APARTMENT/COMMUNITY")
    (setf (gethash "STATIONARY" cmptype-ht) "STATIONARY")
    (setf (gethash "PHOTO SHOP" cmptype-ht) "PHOTO SHOP")
    (setf (gethash "FARMERS MARKET" cmptype-ht) "FARMERS MARKET")
    (with-html-dropdown name cmptype-ht selectedkey)))




(defun dod-controller-new-company-request-page ()
  "URL：/hhub/hhubnewcompanyreqpage?cmp-type=...。
   游客版 'New Store Request' 表单：店主姓名/电话/邮箱、店铺名/地址/Pincode（联动 city/state）、
   网站、TnC 勾选、ReCAPTCHA。提交到 hhubnewstorerequeststep2。"
  (let ((cmp-type (hunchentoot:parameter "cmp-type")))
    ;; Since we came to the new company request page, we will create new session here
    (with-no-navbar-page-v2  "New Store Request"  
      (with-html-form  "form-hhubnewcompanyemail" "hhubnewstorerequeststep2"
	(:img :class "profile-img" :src "/img/logo.png" :alt "")
	
	(with-html-div-row
	  (with-html-div-col-4 "")
	  (with-html-div-col-8 
	    (:h4 (:span :class "label label-primary" "Store Owner Details"))))
	
	(with-html-div-row
	  (with-html-div-col-8
	    (with-html-input-text "custname" "Name" "Full Name" nil T "Please fill your full name" "1")))
	    	
	(with-html-div-row
	  (with-html-div-col-8
	    (with-html-input-text "phone" "Mobile Phone (+91)" "Enter 10 digit phone number" nil T "Please enter phone number" 2))	
	  (with-html-div-col-8
	    (with-html-input-text "email" "Email" "Email" nil T "Please enter email" 3)))
	
	(with-html-div-row (:hr))
	
	(with-html-div-row
	  (with-html-div-col
	    (:h4 (:span :class "label label-primary" "Store Details"))))
	
	(with-html-div-row
	  (with-html-div-col-8
	    (with-html-input-text "cmpname" "Store Name" "Store Name" nil T "Please enter company name" 4 :maxlength "40")))
	
	
	(with-html-div-row
	  (with-html-div-col-8
	    (with-html-input-textarea "cmpaddress" "Address" "Address" "Enter Address" T "Enter Address" 5 3))
	  (:div :class "form-group" :id "charcount"))
	
	(:input  :type "hidden" :value cmp-type :name "cmptype")

	(:h4 (:span :class "label label-primary" "Confirm Pincode"))
	(with-html-div-row
	  (with-html-div-col
	    (:input :class "form-control" :type "text" :class "form-control" :inputmode "numeric" :maxlength "6" :id "cmpzipcode" :name "cmpzipcode" :value "" :placeholder "Pincode" :tabindex "8"  :oninput "this.value=this.value.replace(/[^0-9]/g,'');")))
	
	(with-html-div-row
	  (with-html-div-col
	    (:input :class "form-control" :type "text" :class "form-control" :name "cmpcity" :value "" :id "cmpcity" :placeholder "City" :readonly T :required T)))
		
	(with-html-div-row
	  (with-html-div-col
	    (:input :class "form-control" :type "text" :class "form-control" :name "cmpstate" :value "" :id "cmpstate"  :placeholder "State"  :readonly T :required T )))
	
	(with-html-div-row
	  (with-html-div-col
	    (:input :class "form-control" :type "text" :value "INDIA" :readonly "true"  :name "cmpcountry" )))
	(with-html-div-row
	  (with-html-div-col-8
	    (with-html-input-text "website" nil "Website" nil nil nil nil :maxlength "250")))
	

	(with-html-div-row
	  (with-html-div-col
	    (with-html-checkbox "tnccheck" "tncagreed" T  T
	      (:label :class "form-check-label" :for "tnccheck" "&nbsp;&nbsp;Agree Terms and Conditions&nbsp;&nbsp;")
	      (:a :target "_blank"  :href (format nil "~A/hhub/tnc" *siteurl*)  (:i :class "fa-solid fa-scale-balanced") "&nbsp;Terms"))))

	
	(with-html-div-row
	  (with-html-div-col
	    (:div :class "form-group"
		  (:div :class "g-recaptcha" :data-sitekey *HHUBRECAPTCHAV2KEY* ))))
	
	(with-html-div-row
	  (with-html-div-col-12
	    (:div :class "form-group"
		  (:button :class "submit center-block btn btn-lg btn-primary btn-block" :type "submit" "Send Request"))))

	(hhub-html-page-footer)))))



(defun hhub-controller-new-community-store-request-page ()
  "URL：/hhub/hhubnewcommstorerequest?cmp-type=...。
   类似 dod-controller-new-company-request-page，但用于 'COMMUNITY' 业态（无店铺名/地址等字段）。"
  (let ((cmp-type (hunchentoot:parameter "cmp-type")))
    ;; Since we came to the new company request page, we will create new session here
    (with-no-navbar-page  "New Store Request"  
      (with-html-form  "form-hhubnewcompanyemail" "hhubnewstorerequeststep2"
	(:img :class "profile-img" :src "/img/logo.png" :alt "")
		    	
	(with-html-div-row
	  (with-html-div-col 
	    (:h4 (:span :class "label label-primary" "Store Requester Details"))))
	
	(with-html-div-row
	  (with-html-div-col
	    (with-html-input-text "custname" "Name" "Full Name" nil T "Please fill your full name" "1")))
	
	(with-html-div-row
	  (with-html-div-col
	    (with-html-input-text "phone" "Mobile Phone (+91)" "Enter 10 digit phone number" nil T "Please enter phone number" 2))	
	  (with-html-div-col
	    (with-html-input-text "email" "Email" "Email" nil T "Please enter email" 3)))
	
	(with-html-div-row (:hr))

	(with-html-div-row
	  (with-html-div-col
	    (:h4 (:span :class "label label-primary" "Store Details"))))
	
	(with-html-input-text-hidden "cmptype" cmp-type) 
	
	(with-html-div-row
	  (with-html-div-col
	    (:input :class "form-control" :type "text" :class "form-control" :inputmode "numeric" :maxlength "6" :id "cmpzipcode" :name "cmpzipcode" :value "" :placeholder "Pincode" :tabindex "8"  :oninput "this.value=this.value.replace(/[^0-9]/g,'');")
	    (:span :id "areaname" :class "label label-info")))
	
	(with-html-div-row
	  (with-html-div-col
	    (:input :class "form-control" :type "text" :class "form-control"  :id "cmpcity" :name "cmpcity" :value "" :placeholder "City" :tabindex "9")))
		
	(with-html-div-row
	  (with-html-div-col
	        (:input :class "form-control" :type "text" :class "form-control"  :id "cmpstate" :name "cmpstate" :value "" :placeholder "State" :tabindex "10")))

	(with-html-div-row
	  (with-html-div-col
	    (:input :class "form-control" :type "text" :value "INDIA" :readonly "true"  :name "cmpcountry" )))
	
	(with-html-div-row
	  (with-html-div-col
	    (with-html-checkbox "tnccheck" "tncagreed" T  T
	      (:label :class "form-check-label" :for "tnccheck" "&nbsp;&nbsp;Agree Terms and Conditions&nbsp;&nbsp;")
	      (:a  :href (format nil "~A/hhub/tnc" *siteurl*)  (:i :class "fa-solid fa-scale-balanced")  "&nbsp;Terms."))))

	
	(with-html-div-row
	  (with-html-div-col
	    (:div :class "form-group"
		  (:div :class "g-recaptcha" :required T :data-sitekey *HHUBRECAPTCHAV2KEY* ))))
	
	(with-html-div-row
	  (with-html-div-col
	    (:div :class "form-group"
		  (:button :class "submit center-block btn btn-primary btn-block" :type "submit" "Send Request"))))

	(hhub-html-page-footer)))))




(defun com-hhub-transaction-request-new-company (type)
  "新公司请求表单 fragment（type 由调用方传入，cmptype hidden 字段）。
   POST 到 hhubnewcompreqemailaction（推测：发邮件给 SADMIN 进行人工审核）。"
  (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form  "form-hhubnewcompanyemail" "hhubnewcompreqemailaction"
		    (:img :class "profile-img" :src "/img/logo.png" :alt "")
		    (:div :class "form-group"
			  (:input :class "form-control" :name "cmpname" :maxlength "30"  :value "" :required T  :placeholder "Enter Store Name ( max 30 characters) " :type "text" ))
		    (:div :class "form-group"
			  (:label :for "cmpaddress")
			  (:textarea :class "form-control" :name "cmpaddress"  :placeholder "Enter Address ( max 400 characters) " :required T  :rows "5" :onkeyup "countChar(this, 400)" "" ))
		    (:div :class "form-group" :id "charcount")
		    (:div :class "form-group"
			  (:input :class "form-control" :type "hidden" :value type :name "cmptype" :readonly T))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value "" :placeholder "City"  :required T :name "cmpcity" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value "" :placeholder "State" :required T  :name "cmpstate" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value "INDIA" :readonly "true"  :name "cmpcountry" ))
		    (:div :class "form-group"
			      (:input :class "form-control" :type "text" :maxlength "6" :value "" :placeholder "Pincode" :required T  :name "cmpzipcode" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :maxlength "256" :value "" :placeholder "Website" :name "cmpwebsite" ))
		    (:div :class "form-group checkbox" 
			  (:input :type "checkbox" :name "tnccheck" :value  "tncagreed" :required T "Agree Terms and Conditions.  "))
		    (:a  :href (format nil "~A/tnc.html" *siteurl*)  (:i :class "fa-solid fa-scale-balanced") "&nbsp;Terms")
		    (:div :class "form-group checkbox" 
			  (:input :type "checkbox" :name "privacycheck" :value "privacyagreed" :required T  "Agree Privacy Policy.  "))
		   
		    (:a  :href (format nil "~A/tnc.html" *siteurl*)  (:i :class "fa-solid fa-eye") "&nbsp;Privacy Policy. ")
		    (:div :class "form-group"
			  (:div :class "g-recaptcha" :data-sitekey *HHUBRECAPTCHAV2KEY* ))
		    (:div :class "form-group"
			  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit")))))))
    
    
(defun dod-controller-company-search-for-sys-action ()
  "URL：/hhub/dodsyssearchtenantaction。SADMIN 主页 livesearch 后端：按名称模糊查公司，渲染 tile 网格。"
  (let*  ((qrystr (hunchentoot:parameter "accountlivesearch"))
	  (company-list (if (not (equal "" qrystr)) (select-companies-by-name qrystr))))
    (display-as-tiles company-list 'company-card "tenant-box")))

(defun com-hhub-transaction-refresh-iam-settings ()
  "URL：/hhub/refreshiamsettings。SADMIN 触发 refreshiamsettings —— 重载 ABAC 缓存（policies/transactions/attributes/objects/subjects），再跳回 /hhub/dasabacsecurity。"
  (with-opr-session-check
      (progn
	(refreshiamsettings)
	(hunchentoot:redirect "/hhub/dasabacsecurity"))))

(defun dod-controller-abac-security ()
  "URL：/hhub/dasabacsecurity。SADMIN ABAC 主页 —— 顶部 IAM 子模块导航 +
   策略列表表格（含 Add Policy 按钮 + 模态框）。"
  (let ((policies (hhub-get-cached-auth-policies)))
    (with-opr-session-check 
      (with-standard-admin-page "Welcome to Nine Stores"
	(iam-security-page-header)
	(:hr)
	(:div :class "row"
	      (:div :class "col-xs-3" (:h4 "Business Policies"))
	      (:div :class "col-xs-3" 
		    (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#addpolicy-modal" "Add New Policy")))
	(cl-who:str (display-as-table (list  "Name" "Description" "Policy Function" "Action")  policies 'policy-row))
	(modal-dialog "addpolicy-modal" "Add/Edit Policy" (com-hhub-transaction-policy-create-dialog))))))



(defun com-hhub-transaction-sadmin-home ()
  "URL：/hhub/sadminhome。SADMIN 主页（公司列表 + 添加按钮）。"
  (with-opr-session-check
    (with-mvc-ui-page "Welcome Super Administrator" #'create-model-for-sadminhome #'create-widgets-for-sadminhome :role :superadmin)))

(defun create-model-for-sadminhome ()
  "model：从 IAM 缓存 hhub-get-cached-companies 取所有公司列表。"
  (let ((companies (hhub-get-cached-companies))
	(params nil))
    (setf params (acons "username" (get-login-username) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-sadmin-home" params 
      (function (lambda ()
	(values companies))))))

(defun create-widgets-for-sadminhome (modelfunc)
  "view：欢迎语 + livesearch 输入框 + 'Add New Group' 按钮 + 公司 tile 网格 + 编辑模态框。"
  (multiple-value-bind (companies) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)   
		       (:div :id "row"
			     (:div :id "col-xs-6" 
				   (:h3 "Welcome " (cl-who:str (format nil "~A" (get-login-user-name))))))
		       (company-search-html)
		       (:div :id "row"
			     (:div :id "col-xs-6"
				   (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#editcompany-modal" "Add New Group"))
			     (:div :id "col-xs-6" :align "right" 
				   (:span :class "badge" (cl-who:str (format nil "~A" (length companies))))))
		       (:hr)
		       (modal-dialog "editcompany-modal" "Add/Edit Group" (com-hhub-transaction-create-company-dialog))
		       (:div :id "accountlivesearchresult"
			     (cl-who:str (display-as-tiles companies 'company-card "tenant-box"))))))))
      (list widget1))))



(defun IAM-security-page-header ()
  "ABAC 子模块统一顶部导航条：Policies / Attributes / Business Objects / Personas /
   Transactions + 黄色提示（IAM 缓存需要 refresh 才生效）+ 刷新按钮。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
	  (:div :class "col-sm-12"
		(:h4 (:span :class "label label-warning" "Note: Any changes saved will not get reflected unless you click the refresh button."))))
    (:div :class "row"
	  (:div :class "col-xs-2"
		(:a :class "btn btn-primary" :role "button" :href "/hhub/dasabacsecurity"  "Policies"))
	  (:div :class "col-xs-2"
		(:a :class "btn btn-primary" :role "button" :href "/hhub/listattributes"  "Attributes/Tags"))
	  (:div :class "col-xs-2"
		(:a :class "btn btn-primary" :role "button" :href "/hhub/listbusobjects"  "Business Objects"))
	  (:div :class "col-xs-2"
		(:a :class "btn btn-primary" :role "button" :href "/hhub/listabacsubjects"  "Business Personas"))
	  (:div :class "col-xs-2"
		(:a :class "btn btn-primary" :role "button" :href "/hhub/listbustrans"  "Transactions"))
	  (:div :class "col-xs-2"
		(:a :class "btn btn-primary btn-xs" :role "button" :href "/hhub/refreshiamsettings" (:i :class "fa-solid fa-rotate-right"))))
    (:div :class "row" )))

;; 把 *logged-in-users* 初始化为 equal-hash-table（之前 defvar 给的初值是 nil，这里覆盖）。
(setq *logged-in-users* (make-hash-table :test 'equal))


(defun dod-controller-list-busobjs ()
:documentation "List all the business objects.
   中文：URL：/hhub/listbusobjects。列出系统全部 dod-bus-object（资源类型）。
         注释提示了如何从 REPL (create-bus-object) 添加新条目。"
(with-opr-session-check 
  (let ((busobjs (hhub-get-cached-bus-objects)))
    (with-standard-admin-page "Business Objects ..."
			      (IAM-security-page-header)
			      (:div :class "row"
				    (:div :class "col-md-12" (:h4 "Business Objects")))
			      (cl-who:str (display-as-table (list "Name")  busobjs 'busobj-card))
			      (:h4 "Note: To add new business objects to the system, follow these steps.")
			      (:h4 "In the Lisp REPL call the function, (create-bus-object)")))))



(defun dod-controller-list-abac-subjects ()
:documentation "List all the business objects.
   中文：URL：/hhub/listabacsubjects。列出当前公司下的 dod-abac-subject（业务主体类型）。
         备注：原英文 docstring 写的是 'business objects'，与实际显示 'Business Personas' 不符（推测：复制粘贴遗留）。"
(with-opr-session-check 
  (let ((abacsubjects (select-abac-subject-by-company (get-login-company))))
    (with-standard-admin-page "Business Personas ..."
      (IAM-security-page-header)
      (:hr)
      (with-html-div-row
	    (:div :class "col-md-12" (:h4 "Business Personas")))
      (cl-who:str (display-as-table (list "Name")  abacsubjects 'busobj-card))
      (:h4 "Note: To add new Business Persona to the system, follow these steps.")
      (:h4 "In the Lisp REPL call the function, (create-abac-subject)")))))


(defun dod-controller-list-bustrans ()
:documentation "List all the business transactions.
   中文：URL：/hhub/listbustrans。列出系统全部 dod-bus-transaction（URI ↔ 函数 ↔ 策略 绑定）。
         附 'New Transaction' 按钮 + 模态框（new-transaction-html）。"
(with-opr-session-check 
  (let ((bustrans (hhub-get-cached-transactions)))
    (with-standard-admin-page "Business Transactions..."
      (IAM-security-page-header)
      (:hr)
      (with-html-div-row
	(:div :class "col-md-12" 
		  (:div :class "col-md-12" (:h4 "Business Transactions"))))
      (:div :class "col-md-12" 
	    (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#addtransaction-modal" "New Transaction"))
      
      (cl-who:str (display-as-table (list "Name" "URI" "Function" "Action")  bustrans 'bustrans-card))
      (modal-dialog "addtransaction-modal" "Add/Edit Transaction" (new-transaction-html))))))

(defun dod-controller-list-attrs ()
:documentation "This function lists the attributes used in policy making.
   中文：URL：/hhub/listattributes。列出 PIP 缓存的 ABAC 属性条目（name/desc/func/type）+
         新增按钮 + 模态框 com-hhub-transaction-create-attribute-dialog。"
 (with-opr-session-check 
   (let ((lstattributes (hhub-get-cached-abac-attributes)))
     (with-standard-admin-page  "attributes ..."
			       (iam-security-page-header)
       (:div :class "row"
	     (:div :class "col-md-12" (:h4 "Attributes"))
	     (:div :class "col-md-12" 
		   (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#addattribute-modal" "Add New Attribute")))
       (:hr)		       
       (cl-who:str (display-as-table (list "Name" "Description" "Function" "Type" )  lstattributes 'attribute-card))
					;  (ui-list-attributes lstattributes)
       (modal-dialog "addattribute-modal" "Add/Edit Attribute" (com-hhub-transaction-create-attribute-dialog))))))

(defun dod-controller-loginpage ()
  "URL：/hhub/opr-login.html。SADMIN/OPR 登录页。
   预先 'select 1' 探测 DB 连接：
     - 已登录 → 跳 /hhub/sadminhome；
     - 未登录 → 渲染登录表单（POST sadminlogin）。"
  (handler-case
      (progn  (if (equal (caar (clsql:query "select 1" :flatp nil :field-names nil :database *dod-db-instance*)) 1) T)	      
	      (if (is-dod-session-valid?)
		  (hunchentoot:redirect "/hhub/sadminhome")
		  ;else
		  (with-standard-admin-page "Welcome to Nine Stores"
		    (:div :class "row background-image: url(resources/login-background.png);background-color:lightblue;" :id "idoprlogin" 
			  (:div :class "col-sm-6 col-md-4 col-md-offset-4"
				(:div :class "account-wall"
				      (:img :class "profile-img" :src "/img/logo.png" :alt "")
				      (:h1 :class "text-center login-title"  "Login to Nine Stores")
				      (with-html-form "formoperatorlogin" "sadminlogin" 
					(:div :class "form-group"
					      (:input :class "form-control" :name "company" :placeholder "Company Name"  :type "text"))
					(:div :class "form-group"
					      (:input :class "form-control" :name "username" :placeholder "User name" :type "text"))
					(:div :class "form-group"
					      (:input :class "form-control" :name "password"  :placeholder "Password" :type "password"))
					(:input :type "submit"  :class "btn btn-lg btn-block btn-primary" :value "Login")))))
		    (submitformevent-js "#idoprlogin")))) 
    (clsql:sql-database-data-error (condition)
      (if (equal (clsql:sql-error-error-id condition) 2006)
	  (progn
	    (stop-das) 
	    (start-das)
	    (hunchentoot:redirect "/hhub/opr-login.html"))))))

(defun com-hhub-transaction-sadmin-login ()
  "URL：/hhub/sadminlogin。SADMIN 登录提交动作，返回跳转 URL。"
  (let ((uri (with-mvc-redirect-ui #'create-model-for-sadminlogin #'create-widgets-for-genericredirect)))
    (format nil "~A" uri)))

(defun create-model-for-sadminlogin ()
  "登录 model：取 username/password/company 三参数 → dod-login 校验。
   成功改 redirectlocation 为 /hhub/sadminhome；失败保持登录页。"
 (let  ((uname (hunchentoot:parameter "username"))
	(passwd (hunchentoot:parameter "password"))
	(cname (hunchentoot:parameter "company"))
	(redirectlocation "/hhub/opr-login.html")
	(params nil))
   (setf params (acons "uri" (hunchentoot:request-uri*)  params))
   (setf params (acons "username" uname params))
   (setf params (acons "company" cname params))
   (with-hhub-transaction "com-hhub-transaction-sadmin-login"  params   
      (unless (and
	       ( or (null cname) (zerop (length cname)))
	       ( or (null uname) (zerop (length uname)))
	       ( or (null passwd) (zerop (length passwd))))
	(if (dod-login :company-name cname :username uname :password passwd)
	    (setf redirectlocation "/hhub/sadminhome"))
	(function (lambda ()
	  (values redirectlocation)))))))


;;;;;;;;;;;;;;com-hhub-transaction-cad-logout;;;;;;;;;;;;;;;
(defun create-model-for-sadminlogout ()
  "SADMIN 登出 model：dod-logout 清登录态、remove-session、删除 BusinessSession，
   重定向 /hhub/opr-login.html。"
  (let ((username (get-login-username))
	(redirectlocation "/hhub/opr-login.html"))
    (progn
      (dod-logout username)
      (when hunchentoot:*session* (hunchentoot:remove-session hunchentoot:*session*))
      (deleteBusinessSession (getBusinessContext *HHUBBUSINESSSERVER* "compadminsite") (hunchentoot:session-value :login-user-business-session-id)) 
      (function (lambda ()
	redirectlocation)))))

(defun dod-controller-logout ()
  "URL：/hhub/dodlogout。SADMIN 登出主入口（model 后做 302 跳转）。"
  (let ((uri (with-mvc-redirect-ui #'create-model-for-sadminlogout #'create-widgets-for-genericredirect)))
    (hunchentoot:redirect (format nil "~A" uri))))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun is-dod-session-valid? ()
  "判定 hunchentoot 当前是否有 session。返回 T/NIL。"
  (if hunchentoot:*session* T NIL))


(defun dod-login (&key company-name username password)
  "SADMIN/通用登录核心：按 username 查 dod-users（仅未删除）；同时校验 company 名匹配 + 密码匹配 +
   当前 session 未登录三条件。通过则 start-session、设置 8 小时超时、调 set-user-session-params 注入会话。
   返回 T 表示登录成功；其他情况 nil。"
  (let* ((login-user (car (clsql:select 'dod-users :where [and
					[= [slot-value 'dod-users 'username] username]
					[= [:deleted-state] "N"]]
					:caching nil :flatp t)))
	 (pwd (if login-user (slot-value login-user 'password)))
	 (salt (if login-user (slot-value login-user 'salt)))
	 (password-verified (if login-user  (check-password password salt pwd)))
	 (login-company (if login-user (slot-value login-user 'company)))
	 (login-company-name (if login-user (slot-value login-company 'name))))
    (when (and   
	   login-user
	   (equal login-company-name company-name)
	   password-verified
	   (null (hunchentoot:session-value :login-user-name))) ;; User should not be logged-in in the first place.
      (progn
	(hunchentoot:start-session)
	(setf hunchentoot:*session-max-time* (* 3600 8))
	(set-user-session-params login-company login-user)
	T))))
  
(defun get-tenant-id (company-name)
  "按公司名查 row-id（仅取第一条）。"
  ( car ( clsql:select [row-id] :from [dod-company] :where [= [slot-value 'dod-company 'name] company-name]
		       :flatp t)))

(defun get-tenant-name (company-id)
  "按公司主键查 name。"
  ( car ( clsql:select [name] :from [dod-company] :where [= [slot-value 'dod-company 'row-id] company-id]
		       :flatp t)))


(defun get-login-user-object (username)
  "从 *logged-in-users* 哈希表读取已登录的 user 对象。"
  (gethash username *logged-in-users*))


(defun is-user-already-login? (username)
  "判断 username 是否已在登录态。"
(if (equal (gethash username *logged-in-users*) NIL ) NIL T))


(defun add-login-user(username object)
  "把 user 对象注册到 *logged-in-users*；若该 username 已登录则不覆盖。"
  (unless (is-user-already-login? username)
	   (setf (gethash username *logged-in-users*) object)))


(defun dod-logout (username)
  "登出：从 *logged-in-users* 中移除 username 对应的项。"
  (remhash username *logged-in-users*))


(defun dod-controller-new-store-request-step2 ()
  "URL：/hhub/hhubnewstorerequeststep2。
   游客提交 'New Store Request' 第一步表单后的处理：
     1) 调 Google ReCAPTCHA v2 校验 captcha；
     2) 构造内存 dod-company（不写库），把店主信息+公司对象写入 hunchentoot session；
     3) 调 generateotp&redirect 给 phone 发 OTP；OTP 验证通过后跳到 'hhubnewcompreqemailaction'。
   备注：cmpzipcode 用 parse-integer 解析，空字符串会抛错（推测：调用方表单已校验非空）。"
(let*  ((custname (hunchentoot:parameter "custname"))
	(email (hunchentoot:parameter "email"))
	(phone (hunchentoot:parameter "phone"))
	(cmpname (hunchentoot:parameter "cmpname"))
	(cmptype (hunchentoot:parameter "cmptype"))
	(cmpaddress (hunchentoot:parameter "cmpaddress"))
	(cmpcity (hunchentoot:parameter "cmpcity"))
	(cmpstate (hunchentoot:parameter "cmpstate"))
	(cmpcountry (hunchentoot:parameter "cmpcountry"))
	(cmpzipcode (parse-integer (hunchentoot:parameter "cmpzipcode")))
	(tnccheck (hunchentoot:parameter "tnccheck"))
	(captcha-resp (hunchentoot:parameter "g-recaptcha-response"))
	(paramname (list "secret" "response" ) ) 
	(paramvalue (list *HHUBRECAPTCHAV2SECRET*  captcha-resp))
	(param-alist (pairlis paramname paramvalue ))
	(json-response (json:decode-json-from-string  (map 'string 'code-char(drakma:http-request "https://www.google.com/recaptcha/api/siteverify"
												  :method :POST
												  :parameters param-alist  ))))
     	(cmpwebsite (hunchentoot:parameter "cmpwebsite"))
	(company (make-instance 'dod-company
				:name cmpname
				:address cmpaddress
				:city cmpcity
				:state cmpstate 
				:country cmpcountry
				:zipcode cmpzipcode
				:website cmpwebsite
				:cmp-type cmptype
				:deleted-state "N"
				:created-by nil
				:updated-by nil)))
  (unless(and  ( or (null cmpname) (zerop (length cmpname)))
	       ( or (null cmpaddress) (zerop (length cmpaddress)))
	       (null cmpzipcode))
    (cond 
      ((null (cdr (car json-response))) (dod-response-captcha-error))
      ((and company
	    (equal tnccheck "tncagreed"))
       (let ((context "hhubnewcompreqemailaction"))
	 (hunchentoot:start-session)
	 (setf (hunchentoot:session-value :newstorerequest-company) company)
	 (setf (hunchentoot:session-value :newstorerequest-custname) custname )
	 (setf (hunchentoot:session-value :newstorerequest-phone) phone )
	 (setf (hunchentoot:session-value :newstorerequest-email) email)
	 (generateotp&redirect "vendor" "newstore" phone context)))))))
	 




(defun dod-controller-new-company-request-email ()
  "URL：/hhub/hhubnewcompreqemailaction。
   OTP 校验通过后被回调：从 session 取出 step2 缓存的公司对象与店主信息，
   send-new-company-registration-email 通知 SADMIN 走人工审核，清掉 session，跳转到 hhubnewcompreqemailsent 提示页。"
  (let*  ((company (hunchentoot:session-value :newstorerequest-company))
	  (custname (hunchentoot:session-value :newstorerequest-custname))
	  (phone (hunchentoot:session-value :newstorerequest-phone))
	  (email (hunchentoot:session-value :newstorerequest-email)))
	  
    (when company (send-new-company-registration-email company custname phone email))
    ;; When an email is sent, we will clear the session. 
    (hunchentoot:remove-session hunchentoot:*session*)
    (hunchentoot:redirect "/hhub/hhubnewcompreqemailsent")))

	  

(defun 	com-hhub-transaction-create-company ()
  "URL：/hhub/createcompanyaction。SADMIN 创建/更新公司：
     - 若传 id 则更新现存公司字段并 update-company；
     - 否则 new-dod-company 新建（同时会创建 default vendor 与 guest customer）。
   备注：unless 内 (and (or null zerop) ...) 复合判定为 *任一* 字段非空时才执行 ——
   行为与多处 add-user/login 相同。完成后跳 /hhub/sadminhome。"
  (with-opr-session-check
    (let ((params nil))
      (setf params (acons "uri" (hunchentoot:request-uri*)  params))
      (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
      (with-hhub-transaction "com-hhub-transaction-create-company" params  
      (let*  ((id (hunchentoot:parameter "id"))
	      (company (if id (select-company-by-id id)))
	      (cmpname (hunchentoot:parameter "cmpname"))
	      (cmpaddress (hunchentoot:parameter "cmpaddress"))
	      (cmpcity (hunchentoot:parameter "cmpcity"))
	      (cmpstate (hunchentoot:parameter "cmpstate"))
	      (cmpcountry (hunchentoot:parameter "cmpcountry"))
	      (cmpzipcode (hunchentoot:parameter "cmpzipcode"))
	      (cmpwebsite (hunchentoot:parameter "cmpwebsite"))
	      (cmp-type (hunchentoot:parameter "cmp-type"))
	      (subscription-plan (hunchentoot:parameter "subscription-plan"))
	      (loginuser (get-login-userid)))

	(unless(and  ( or (null cmpname) (zerop (length cmpname)))
		     ( or (null cmpaddress) (zerop (length cmpaddress)))
		     ( or (null cmpzipcode) (zerop (length cmpzipcode))))
	  (if company 
	      (progn (setf (slot-value company 'name) cmpname)
		     (setf (slot-value company 'address) cmpaddress)
		     (setf (slot-value company 'city) cmpcity)
		     (setf (slot-value company 'state) cmpstate)
		     (setf (slot-value company 'zipcode) cmpzipcode)
		     (setf (slot-value company 'website) cmpwebsite)
		     (setf (slot-value company 'cmp-type) cmp-type)
		     (setf (slot-value company 'subscription-plan) subscription-plan)
		     (create-guest-customer company)
		     (update-company company))
					;else
	      (progn
		(new-dod-company cmpname cmpaddress cmpcity cmpstate cmpcountry cmpzipcode cmpwebsite cmp-type subscription-plan loginuser loginuser))))
	
	;; once a new company is created, create the Company Administrator
	;; Once a new company is created, we will create a default Vendor with the same name, phone number as the company admin)))
	
	;; once a new company is created, we need to create a new guest customer for that company.
	
	      (hunchentoot:redirect  "/hhub/sadminhome"))))))



;; ============================================================================
;; 全平台路由表（Hunchentoot dispatch-table）—— 一次性 setq 完成
;; ----------------------------------------------------------------------------
;; 每条 (create-regex-dispatcher "^/hhub/<path>" 'controller) 把一个 URL 前缀绑定到
;; 对应控制器函数。下方按角色分段：
;;   - SUPERADMIN/OPERATOR
;;   - COMPADMIN/COMPANYHELPDESK/COMPANYOPERATOR
;;   - CUSTOMER
;;   - VENDOR
;;
;; 注意：
;; (1) 由于使用 ^/hhub/<path> 正则匹配，路径相互前缀重合时会发生误匹配。
;;     文件中后段有红字 WARNING 说明：URI 不能存在公共子串。
;; (2) 以 'com-hhub-transaction-*' 命名的控制器同时是 ABAC 事务的 trans-func 字段值；
;;     请求被 PEP 宏 with-hhub-transaction 拦截后会查 dod-bus-transaction 取策略
;;     并交由 PDP 求值。
;; ============================================================================
(setq hunchentoot:*dispatch-table*
    (list
	;***************** SUPERADMIN/OPERATOR RELATED ********************
     
	(hunchentoot:create-regex-dispatcher "^/hhub/sadminhome" 'com-hhub-transaction-sadmin-home)
	(hunchentoot:create-regex-dispatcher "^/hhub/dasabacsecurity" 'dod-controller-abac-security)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubnewcompanyreqpage" 'dod-controller-new-company-request-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubnewstorerequeststep2" 'dod-controller-new-store-request-step2)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubnewcompreqemailaction" 'dod-controller-new-company-request-email)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubnewcompreqemailsent" 'dod-controller-new-company-registration-email-sent) 
	(hunchentoot:create-regex-dispatcher "^/hhub/createcompanyaction" 'com-hhub-transaction-create-company)
	(hunchentoot:create-regex-dispatcher "^/hhub/opr-login.html" 'dod-controller-loginpage)
	(hunchentoot:create-regex-dispatcher "^/hhub/sadminlogin" 'com-hhub-transaction-sadmin-login)
	(hunchentoot:create-regex-dispatcher "^/hhub/list-customers" 'dod-controller-list-customers)
	(hunchentoot:create-regex-dispatcher "^/hhub/orderdetails" 'dod-controller-list-order-details)
	(hunchentoot:create-regex-dispatcher "^/hhub/list-vendors" 'dod-controller-list-vendors)
	(hunchentoot:create-regex-dispatcher "^/hhub/list-products" 'dod-controller-list-products)
	(hunchentoot:create-regex-dispatcher "^/hhub/user-added" 'dod-controller-user-added)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodlogout" 'dod-controller-logout)
	(hunchentoot:create-regex-dispatcher "^/hhub/delcomp" 'dod-controller-delete-company)
	(hunchentoot:create-regex-dispatcher "^/hhub/journal-entry-added" 'dod-controller-journal-entry-added)
        (hunchentoot:create-regex-dispatcher "^/hhub/account-added" 'dod-controller-account-added)
	(hunchentoot:create-regex-dispatcher "^/hhub/sadmincreateusers" 'com-hhub-transaction-sadmin-create-users-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/list-accounts" 'dod-controller-list-accounts)
	(hunchentoot:create-regex-dispatcher "^/hhub/listattributes" 'dod-controller-list-attrs)
	(hunchentoot:create-regex-dispatcher "^/hhub/dbreset.html" 'dod-controller-dbreset-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dbresetaction" 'dod-controller-dbreset-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodsyssearchtenantaction" 'dod-controller-company-search-for-sys-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dasaddattribute" 'com-hhub-transaction-create-attribute)
	(hunchentoot:create-regex-dispatcher "^/hhub/listbusobjects" 'dod-controller-list-busobjs)
	(hunchentoot:create-regex-dispatcher "^/hhub/listabacsubjects" 'dod-controller-list-abac-subjects)
	(hunchentoot:create-regex-dispatcher "^/hhub/listbustrans" 'dod-controller-list-bustrans)
	(hunchentoot:create-regex-dispatcher "^/hhub/dasaddpolicyaction" 'com-hhub-transaction-policy-create)
	(hunchentoot:create-regex-dispatcher "^/hhub/dasaddtransactionaction" 'dod-controller-add-transaction-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dassearchpolicies" 'dod-controller-policy-search-action )
	(hunchentoot:create-regex-dispatcher "^/hhub/transtopolicylinkpage" 'dod-controller-trans-to-policy-link-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/transtopolicylinkaction" 'dod-controller-trans-to-policy-link-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dasproductapprovals" 'dod-controller-products-approval-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dasadduseraction" 'dod-controller-add-user-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubsadminprofile" 'com-hhub-transaction-sadmin-profile)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubdiagnostics" 'com-hhub-transaction-system-dashboard)
	(hunchentoot:create-regex-dispatcher "^/hhub/suspendaccount" 'com-hhub-transaction-suspend-account)
	(hunchentoot:create-regex-dispatcher "^/hhub/restoreaccount" 'com-hhub-transaction-restore-account)
	(hunchentoot:create-regex-dispatcher "^/hhub/refreshiamsettings" 'com-hhub-transaction-refresh-iam-settings)
	(hunchentoot:create-regex-dispatcher "^/hhub/pricing" 'hhub-controller-pricing)
	(hunchentoot:create-regex-dispatcher "^/hhub/contactuspage" 'hhub-controller-contactus-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/aboutuspage" 'hhub-controller-aboutus-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/contactusaction" 'hhub-controller-contactus-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/tnc" 'hhub-controller-tnc-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/privacy" 'hhub-controller-privacy-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/otppage" 'dod-controller-OTP-request-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubotpregenerateaction" 'dod-controller-otp-regenerate-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubotpsubmitaction" 'dod-controller-otp-submit-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/displaystore" 'com-hhub-transaction-display-store)
	(hunchentoot:create-regex-dispatcher "^/hhub/createwhatsapplinkwithmessage" 'hhub-controller-create-whatsapp-link-with-message)
	(hunchentoot:create-regex-dispatcher "^/hhub/permissiondenied" 'hhub-controller-permission-denied)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubnewcommstorerequest" 'hhub-controller-new-community-store-request-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/list-companies" 'dod-controller-list-companies)
	(hunchentoot:create-regex-dispatcher "^/hhub/gsthsncodes" 'com-hhub-transaction-gst-hsn-codes-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/searchhsncodesaction" 'com-hhub-transaction-search-gst-hsn-codes-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/createhsncodeaction" 'com-hhub-transaction-create-gst-hsn-code-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/updatehsncodeaction" 'com-hhub-transaction-update-gst-hsn-code-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/projsymlookup" 'com-hhub-controller-project-symbols-lookup-page)
	
	
	;***************** COMPADMIN/COMPANYHELPDESK/COMPANYOPERATOR  RELATED ********************
     
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcadindex" 'com-hhub-transaction-compadmin-home)
	(hunchentoot:create-regex-dispatcher "^/hhub/cad-login.html" 'com-hhub-transaction-cad-login-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcadloginaction" 'com-hhub-transaction-cad-login-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcadlogout" 'com-hhub-transaction-cad-logout) 
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcadprdrejectaction" 'com-hhub-transaction-cad-product-reject-action )
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcadprdapproveaction" 'com-hhub-transaction-cad-product-approve-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubpublishaccountexturl" 'com-hhub-transaction-publish-account-exturl)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcadprofile" 'dod-controller-cad-profile)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcompadminupdateaction" 'com-hhub-transaction-compadmin-updatedetails-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcadlistprodcatg" 'dod-controller-product-categories-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubprodcatgaddaction" 'com-hhub-transaction-prodcatg-add-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubdeleteprodcatg" 'dod-controller-delete-product-category)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendorapprovalpage" 'dod-controller-vendor-approval-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendorapproveaction" 'com-hhub-transaction-vendor-approve-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendorrejectaction" 'com-hhub-transaction-vendor-reject-action)
	
	;************CUSTOMER LOGIN RELATED ********************
	(hunchentoot:create-regex-dispatcher  "^/hhub/customer-login.html" 'dod-controller-customer-loginpage)
	(hunchentoot:create-regex-dispatcher  "^/hhub/dodcustlogin"  'dod-controller-cust-login)
	(hunchentoot:create-regex-dispatcher  "^/hhub/dascustloginasguest"  'dod-controller-cust-login-as-guest)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustindex" 'dod-controller-cust-index)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustlogout" 'dod-controller-customer-logout)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodguestcustlogout" 'dod-controller-guest-customer-logout)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodmyorders" 'dod-controller-my-orders)
	(hunchentoot:create-regex-dispatcher "^/hhub/delorder" 'dod-controller-del-order) ;; not used. 
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustordsuccess" 'dod-controller-cust-ordersuccess)
	(hunchentoot:create-regex-dispatcher "^/hhub/custsubscriptions" 'dod-controller-customer-subscriptions)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustmyorderdetails" 'hhub-controller-customer-my-orderdetails)
	;;(hunchentoot:create-regex-dispatcher "^/hhub/dodcustaddorderpref" 'dod-controller-cust-add-orderpref-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustaddopfaction" 'dod-controller-cust-add-orderpref-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustdelopfaction" 'dod-controller-cust-del-orderpref-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustordershipaddrpage" 'dod-controller-cust-order-shipping-address-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustshopcartotpstep" 'dod-controller-cust-add-order-otpstep)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodmyorderaddaction" 'com-hhub-transaction-create-order)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustaddtocart" 'dod-controller-cust-add-to-cart)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustupdatecart" 'dod-controller-cust-update-cart)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustshopcartro" 'dod-controller-cust-show-shopcart-readonly)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustshopcart" 'dod-controller-cust-show-shopcart)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustremshctitem" 'dod-controller-remove-shopcart-item )
	;;(hunchentoot:create-regex-dispatcher "^/hhub/dodcustplaceorder" 'dod-controller-cust-placeorder )
	;;(hunchentoot:create-regex-dispatcher "^/hhub/dodvendordetails" 'dod-controller-vendor-details)
	(hunchentoot:create-regex-dispatcher "^/hhub/prddetailsforcust" 'dod-controller-prd-details-for-customer)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubprddetailsforguestcust" 'dod-controller-prd-details-for-guest-customer)
	;;(hunchentoot:create-regex-dispatcher "^/hhub/dodprodsubscribe" 'dod-controller-cust-add-orderpref-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodproductsbycatg" 'dod-controller-customer-products-by-category)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodsearchproducts" 'dod-controller-search-products)
	(hunchentoot:create-regex-dispatcher "^/hhub/doddelcustorditem" 'dod-controller-del-cust-ord-item)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustlowbalanceshopcart" 'dod-controller-low-wallet-balance-for-shopcart)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustlowbalanceorderitems" 'dod-controller-low-wallet-balance-for-orderitems)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustwallet" 'dod-controller-cust-wallet-display)
	(hunchentoot:create-regex-dispatcher "^/hhub/custsignup1action" 'dod-controller-cust-register-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/custsignup1step2" 'com-hhub-transaction-customer&vendor-create-otpstep)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustregisteraction" 'com-hhub-transaction-customer&vendor-create)
	(hunchentoot:create-regex-dispatcher "^/hhub/duplicate-cust.html" 'dod-controller-duplicate-customer)
	(hunchentoot:create-regex-dispatcher "^/hhub/custsignup1.html" 'dod-controller-company-search-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/companysearchaction" 'dod-controller-company-search-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/createcustwallet" 'dod-controller-create-cust-wallet)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustprofile" 'dod-controller-customer-profile)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustorditemedit" 'com-hhub-transaction-cust-edit-order-item )
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustorderscal" 'dod-controller-cust-orders-calendar) 
	(hunchentoot:create-regex-dispatcher "^/hhub/dodcustordersdata" 'dod-controller-cust-order-data-json)
	(hunchentoot:create-regex-dispatcher "^/hhub/dasmakepaymentrequest" 'dod-controller-make-payment-request-html)
	(hunchentoot:create-regex-dispatcher "^/hhub/custpaymentsuccess" 'dod-controller-customer-payment-successful-page )
	(hunchentoot:create-regex-dispatcher "^/hhub/custpaymentfailure" 'dod-controller-customer-payment-failure-page )
	(hunchentoot:create-regex-dispatcher "^/hhub/custpaymentcancel" 'dod-controller-customer-payment-cancel-page )
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustupdateaction" 'dod-controller-customer-update-action )
	(hunchentoot:create-regex-dispatcher "^/hhub/rundailyordersbatch" 'dod-controller-run-daily-orders-batch)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustomerchangepin" 'dod-controller-customer-change-pin)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustforgotpassactionlink" 'dod-controller-customer-reset-password-action-link)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustpassreset.html" 'dod-controller-customer-password-reset-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustgentemppass"   'dod-controller-customer-generate-temp-password) 
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustpassreset"   'dod-controller-customer-password-reset-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubinvalidemail.html"   'dod-controller-invalid-email-error)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubpassresettokenexpired.html"   'dod-controller-password-reset-token-expired )
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubpassresetmailsent.html"   'dod-controller-password-reset-mail-sent )
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubpassresetmaillinksent.html"   'dod-controller-password-reset-mail-link-sent)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustsavepushsubscription"   'hhub-save-customer-push-subscription)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustremovepushsubscription"   'hhub-remove-vendor-push-subscription)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustonlinepayment"   'hhub-cust-online-payment)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubpincodecheck"   'hhub-controller-pincode-check)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustupipage"   'hhub-controller-upi-customer-order-payment-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustorderupipage"   'com-hhub-transaction-show-customer-upi-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendorupinotfound"   'dod-controller-vendor-upi-notfound)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustpaymentmethodspage"   'dod-controller-customer-payment-methods-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustwalletrechargepage"   'hhub-controller-upi-recharge-wallet-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustwalletrechargeaction"   'hhub-controller-upi-recharge-wallet-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcarouseltest"   'hhub-controller-carousel-test)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustshippingmethodspage"   'dod-controller-cust-shipping-methods-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustloginotpstep"  'dod-controller-cust-login-otpstep)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustloginwithotp"  'dod-controller-cust-login-with-otp)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustloginv2"  'dod-controller-customer-otploginpage)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustvendorstore"  'dod-controller-customer-products-by-vendor)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubcustvendorsearch"  'dod-controller-customer-search-vendor)
	(hunchentoot:create-regex-dispatcher "^/hhub/nstcustomeraddress/([0-9]{10})$" 'dod-controller-customer-address)
	(hunchentoot:create-regex-dispatcher "^/hhub/nstcustinvoices" 'com-hhub-transaction-customer-invoice-register-page)


;;***************************************************************************************************************************
;; WARNING: Two URIs should not have a common substring. For example hhubcustpassreset and hhubcustpassresetmail.html 
;;          has got hhubcustpassreset as a common string. When a call for hhubcustpassresetmail.html is made, then 
;;          hhubcustpassreset may get invoked. Keep the URIs unique. 
;;***************************************************************************************************************************	
	

;************VENDOR RELATED ********************
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenddeactivateprod" 'dod-controller-vendor-deactivate-product)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendactivateprod" 'dod-controller-vendor-activate-product)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendcopyprod" 'dod-controller-vendor-copy-product)
	(hunchentoot:create-regex-dispatcher "^/hhub/vendor-login.html" 'dod-controller-vendor-loginpage)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendsearchtenantpage" 'dod-controller-cmpsearch-for-vend-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodrefreshpendingorders" 'dod-controller-refresh-pending-orders)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendrevenue" 'dod-controller-vendor-revenue)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenddelprod" 'dod-controller-vendor-delete-product)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendsearchtenantaction" 'dod-controller-cmpsearch-for-vend-action )
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendaddtenantaction" 'dod-controller-vend-add-tenant-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendortenants" 'dod-controller-display-vendor-tenants)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendswitchtenant" 'dod-controller-vendor-switch-tenant)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendlogin" 'dod-controller-vend-login)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendloginpage" 'dod-controller-vendor-loginpage)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendindex" 'dod-controller-vend-index)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendlogout" 'dod-controller-vendor-logout)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenexpexl" 'dod-controller-ven-expexl)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenproducts" 'dod-controller-vendor-products)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodprddetailsforvendor" 'dod-controller-prd-details-for-vendor)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenordfulfilled" 'com-hhub-transaction-vendor-order-setfulfilled)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendprofile" 'dod-controller-vend-profile)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendmycustomers" 'dod-controller-vendor-my-customers-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodsearchcustwalletpage" 'dod-controller-vendor-search-cust-wallet-page )
	(hunchentoot:create-regex-dispatcher "^/hhub/dodsearchcustwalletaction" 'dod-controller-vendor-search-cust-wallet-action )
	(hunchentoot:create-regex-dispatcher "^/hhub/dodupdatewalletbalance" 'dod-controller-update-wallet-balance)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendororderdetails" 'dod-controller-vendor-orderdetails)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenaddprodpage" 'dod-controller-vendor-add-product-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenbulkaddprodpage" 'dod-controller-vendor-bulk-add-products-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/generateproductcsvaction" 'dod-controller-vendor-generate-products-templ)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenaddproductaction" 'com-hhub-transaction-vendor-product-add-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenuploadproductscsvfileaction" 'com-hhub-transaction-vendor-bulk-products-add)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvenordcancel" 'dod-controller-vendor-order-cancel)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupdateaction" 'dod-controller-vendor-update-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupdatepgsettings" 'dod-controller-vendor-update-payment-gateway-settings-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendchangepin" 'dod-controller-vendor-change-pin)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendforgotpassactionlink" 'dod-controller-vendor-reset-password-action-link)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendpassreset.html" 'dod-controller-vendor-password-reset-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendgentemppass"   'dod-controller-vendor-generate-temp-password) 
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendpassreset"   'dod-controller-vendor-password-reset-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendpushsubscribepage"   'dod-controller-vendor-pushsubscribe-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendsavepushsubscription"   'hhub-controller-save-vendor-push-subscription )
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendremovepushsubscription"   'hhub-remove-vendor-push-subscription )
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendgetpushsubscription"   'hhub-controller-get-vendor-push-subscription )
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupdateupisettings"   'hhub-controller-save-vendor-upi-settings)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendorupitransactions"   'hhub-controller-show-vendor-upi-transactions)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupipayconfirm"   'hhub-controller-vendor-upi-confirm)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupipaycancel"   'hhub-controller-vendor-upi-cancel)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendsearchproduct"   'dod-controller-vendor-search-products)
	(hunchentoot:create-regex-dispatcher "^/hhub/dodvendprodcategories"   'dod-controller-vendor-product-categories-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendaddprodshipinfoaction"  'com-hhub-transaction-vend-prd-shipinfo-add-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendorshipmethods"  'dod-controller-vend-shipping-methods)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupdatfreeshipmethodaction"  'dod-controller-vendor-update-free-shipping-method-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendshipzoneratetablepage"  'dod-controller-vendor-shipzone-ratetable-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvenduploadshipratetableaction"  'dod-controller-vendor-upload-shipping-ratetable-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupdatedefaultshipmethod"  'dod-controller-vendor-update-default-shipping-method)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupdatflatrateshipmethodaction"  'dod-controller-vendor-update-flatrate-shipping-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendupdateshippartneraction"  'dod-controller-vendor-update-external-shipping-partner-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendloginotpstep"  'dod-controller-vend-login-otpstep)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendloginwithotp"  'dod-controller-vend-login-with-otp)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendloginv2"  'dod-controller-vendor-otploginpage)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvendprodpricingsaveaction"  'dod-controller-vendor-product-pricing-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubvpmupdateaction"  'dod-controller-vendor-payment-methods-update-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/displayinvoices" 'com-hhub-transaction-show-invoices-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/searchinvoicesaction" 'com-hhub-transaction-search-invoice-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/createinvoiceaction" 'com-hhub-transaction-create-invoice-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/editinvoicepage" 'com-hhub-transaction-edit-invoice-header-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/updateinvoiceaction" 'com-hhub-transaction-update-invoice-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/addcusttoinvoice" 'com-hhub-transaction-add-customer-to-invoice-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/vendorcreatecustomer" 'com-hhub-transaction-vendor-create-customer-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/hhubsearchmycustomer"   'hhub-controller-search-my-customer-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vsearchcustbyname"   'hhub-controller-vsearchcustbyname-for-invoice-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vsearchcustbyphone"   'hhub-controller-vsearchcustbyphone-for-invoice-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vproductsforinvoicepage"   'com-hhub-transaction-add-product-to-invoice-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/vsearchproductforinvoice"   'com-hhub-transaction-search-product-for-invoice-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vaddtocartforinvoice"   'com-hhub-transaction-vendor-addtocart-for-invoice-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vaddtocartusingbarcode"   'com-hhub-transaction-vendor-addtocart-using-barcode-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vshowinvoiceconfirmpage"   'com-hhub-transaction-show-invoice-confirm-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/updateInvoiceItemaction"   'com-hhub-transaction-update-invoiceitem-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/deleteinvoiceitemaction"   'com-hhub-transaction-delete-invoiceitem-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vinvoicepaymentpage"   'com-hhub-transaction-show-invoice-payment-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/vinvoicepaidaction"   'com-hhub-transaction-invoice-paid-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/displayinvoicepublic"   'com-hhub-transaction-display-invoice-public)
	(hunchentoot:create-regex-dispatcher "^/hhub/displayinvoiceemail"   'com-hhub-transaction-edit-invoice-email)
	(hunchentoot:create-regex-dispatcher "^/hhub/invoicemailaction"   'com-hhub-transaction-send-invoice-email)
	(hunchentoot:create-regex-dispatcher "^/hhub/downloadinvoice"   'com-hhub-transaction-download-invoice)
	(hunchentoot:create-regex-dispatcher "^/hhub/vinvoicesettingspage"   'com-hhub-transaction-invoice-settings-page)
	(hunchentoot:create-regex-dispatcher "^/hhub/vsaveinvprintsettings"   'com-hhub-transaction-save-invoice-print-settings-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vuploadprdimagesaction"   'com-hhub-transaction-vendor-upload-product-images-action)
	(hunchentoot:create-regex-dispatcher "^/hhub/vwebrepl"   'com-hhub-transaction-vendor-display-webrepl-page)
))



