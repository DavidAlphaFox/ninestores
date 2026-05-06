;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：account 账户/租户
;;;; 分层：UI 控制器/视图层
;;;; 文件：hhub/account/dod-ui-cmp.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：公司/租户相关的 Hunchentoot 控制器与 cl-who 视图片段。
;;;;       覆盖：通过分享链接以游客身份进入店铺、列出系统全部公司、
;;;;             删除公司、公司卡片渲染。
;;;;       同时提供一组从 Hunchentoot session 读取登录信息的快捷访问器
;;;;       （get-login-* 系列），被几乎所有控制器使用。
;;;;
;;;; 主要导出：
;;;;   com-hhub-transaction-display-store   — URL: /hhub/displaystore?key=<base64> 游客进店
;;;;   dod-controller-delete-company        — URL: 软删公司（仅 OPR）
;;;;   dod-controller-list-companies        — URL: /list-companies 列出公司（仅 OPR）
;;;;   ui-list-companies / company-card     — 列表与卡片渲染
;;;;   get-login-user / get-login-tenant-id / get-login-user-role-name
;;;;   get-login-company / get-login-cust-tenant-id
;;;;   get-login-customer-company / get-login-customer-company-name
;;;;   get-login-customer-company-id / get-login-customer-type
;;;;   get-login-customer-company-website
;;;;   get-login-vendor-company / get-login-vendor-company-name
;;;;   get-login-vend-tenant-id
;;;;
;;;; 关联：
;;;;   上游使用方：Nginx 路由 → Hunchentoot 派发；几乎全平台的控制器读 session。
;;;;   下游依赖：account/dod-bl-cmp.lisp、customer 的 dod-cust-login-as-guest、
;;;;             core 的 with-opr-session-check / with-standard-admin-page。
;;;; ============================================================================

(in-package :nstores)

(defun com-hhub-transaction-display-store ()
  "通过分享链接以游客身份进店：解析 URL 参数 ?key=<base64>，从中取出 tenant-id，
   调用 dod-cust-login-as-guest（会话有效期 300 秒）。
   - 创建游客会话失败 → 重定向 /hhub/customer-login.html
   - 成功 → 重定向 /hhub/dodcustindex 进入客户首页。
   备注：与 generate-account-ext-url 配套使用。"
  (let* ((parambase64 (hunchentoot:parameter "key"))
	 (param-csv (cl-base64:base64-string-to-string (hunchentoot:url-decode parambase64)))
	 (paramslist (first (cl-csv:read-csv param-csv
					     :skip-first-p T
					     :map-fn #'(lambda (row)
							 row))))
	 (tenant-id (nth 0 paramslist)))
    (unless  ( or (null tenant-id) (zerop (length tenant-id)))
      (if (equal (dod-cust-login-as-guest :tenant-id tenant-id :session-time-limit 300) NIL) (hunchentoot:redirect "/hhub/customer-login.html") (hunchentoot:redirect  "/hhub/dodcustindex")))))


(defun dod-controller-delete-company ()
  "OPR 后台：软删公司控制器。URL 参数 id；操作完成后重定向 /list-companies。
   会话要求：with-opr-session-check（仅运营 OPR 角色）。
   副作用：DOD_COMPANY.deleted-state 置 'Y'。"
  (with-opr-session-check
    (let ((id (hunchentoot:parameter "id")) )
      (delete-dod-company id)
      (hunchentoot:redirect "/list-companies"))))


(defun company-card (instance)
  "渲染单个公司卡片（管理后台用）。展示名称/地址/订阅套餐/客户数/卖家数/账户天数；
   TRIAL 套餐另外显示距到期天数或 EXPIRED 印章；suspended='Y' 时盖 SUSPENDED 印章。
   右上角下拉菜单包含管理用户、冻结/恢复账户、删除等动作。
   参数：instance — dod-company 实例。
   备注：仅输出 HTML 片段（不含 prologue），由调用方包裹在管理页布局中。"
    (let ((comp-name (slot-value instance 'name))
	  (address  (slot-value instance 'address))
	  (city (slot-value instance 'city))
	  (state (slot-value instance 'state)) 
	  (country (slot-value instance 'country))
	  (zipcode (slot-value instance 'zipcode))
	  (suspended (slot-value instance 'suspend-flag))
	  (subscription-plan (slot-value instance 'subscription-plan))
	  (row-id (slot-value instance 'row-id))
	  (accountageindays (account-created-days-ago instance))
	  (trialaccexpirydays (trial-account-days-to-expiry instance)))
	(cl-who:with-html-output (*standard-output* nil)
	  (:div :class "row"
		(:div :class "col-xs-8" 
		      (:h3 (cl-who:str (if (> (length comp-name) 20)  (subseq comp-name 0 20) comp-name))))
		(:div :class "col-xs-1" :align "right" 
		      (:a  :data-toggle "modal" :data-target (format nil "#editcompany-modal~A" row-id)  :href "#"  (:i :class "fa-regular fa-pen-to-square"))
				(modal-dialog (format nil "editcompany-modal~a" row-id) "Add/Edit Group" (com-hhub-transaction-create-company-dialog row-id)))
		(:div :class "col-xs-2 dropdown" 
		      (:button :class "btn btn-primary dropdown-toggle" :type "button" :id "dropdownMenu1" :data-toggle "dropdown" :aria-haspopup "true" :aria-expanded "false" (:i :class "fa-solid fa-ellipsis-vertical "))
		      (:ul :class "dropdown-menu" :aria-labelledby "dropdownMenu1"
			   (:li (:a :href (format nil "/hhub/sadmincreateusers?tenant-id=~a" row-id) "Manage Users"))
			   (if (equal suspended "Y")
			       (cl-who:htm 
				(:li (:a :href (format nil "/hhub/restoreaccount?tenant-id=~a" row-id) "Restore Account")))
			       ;else
			       (cl-who:htm 
				(:li (:a :href (format nil "/hhub/suspendaccount?tenant-id=~a" row-id) "Suspend Account"))))
			   (:li :role "separator" :class "divider" )
			   (:li (:a :href "#" "Delete")))))
		 
	  (:div :class "row"
		(:div :class "col-xs-12"  (cl-who:str (if (> (length address) 20)  (subseq address 0 20) address))))
	  (:div :class "row"
		(:div :class "col-xs-12" (cl-who:str city)))
	  (:div :class "row"
		(:div :class "col-xs-6" (cl-who:str state))
		(:div :class "col-xs-6" (cl-who:str country)))
	  (:div :class "row"
		(:div :class "col-xs-6" (cl-who:str zipcode)))
	  (if (equal suspended "Y")
	      (cl-who:htm (:div :class "stampbox rotated" "SUSPENDED")))
	  (with-html-div-row
	    (with-html-div-col
	      (:h5 (cl-who:str (format nil "No of Customers: ~A " (count-company-customers instance)))))
	    (with-html-div-col
	      (:h5 (cl-who:str (format nil  "No of Vendors: ~A " (count-company-vendors instance ))))))
	  (with-html-div-row
	    (with-html-div-col
	      (:h5 (cl-who:str (format nil  "Subscription Plan: ~A " subscription-plan)))))
	  (with-html-div-row
	    (with-html-div-col
	      (:h5 (cl-who:str (format nil "Account Age in Days: ~A" accountageindays))))
	  (when (equal subscription-plan "TRIAL")
	    (if (> trialaccexpirydays 0)
		(cl-who:htm
		 (with-html-div-col
		   (:h5 (cl-who:str (format nil "Days to Expiry: ~A" trialaccexpirydays )))))
		;;else
		(cl-who:htm (:div :class "stampbox rotated" "EXPIRED"))))))))


(defun dod-controller-list-companies ()
  "OPR 后台：列出系统全部公司。会话要求：with-opr-session-check。
   流程：取 get-system-companies 列表 → 用 with-standard-admin-page 包装 → 调
   ui-list-companies 渲染。"
(with-opr-session-check
   (let (( companies (get-system-companies)))
    (with-standard-admin-page (:title "List companies")
      (ui-list-companies companies)))))

(defun ui-list-companies (company-list)
  "渲染公司列表为 HTML 字符串（含 prologue）。每个公司一张卡片，附 \"Sign Up\" 表单、
   游客购物链接以及（若有 external-url）复制分享链接的小按钮。空列表显示
   \"Record Not Found.\"。
   参数：company-list — dod-company 列表。返回：HTML 字符串。"
 (cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
  (if company-list 
      (cl-who:htm
       (mapcar (lambda (cmp)
		 (let ((external-url (slot-value cmp 'external-url))
		       (cname (slot-value cmp 'name)))
		   (cl-who:htm
		    (with-html-card
			(:title (format nil "~A" cname)
			 :image-src ""
			 :image-alt ""
			 :image-style "width: 200px; height: 200px;")
	    	      (with-html-form "custsignup1form" "custsignup1action" 
			  (:div :class "form-group"
				(:input :type "hidden" :name  "cname" :value (cl-who:str (format nil "~A" cname))))
			  (:div :class "form-group"
				(:button :class "btn btn-sm btn-primary btn-block" :type "submit" (cl-who:str (format nil "~A - Sign Up" cname)))))
			(:a :target "_blank" :href (format nil "dascustloginasguest?tenant-id=~A" (slot-value cmp 'row-id)) (:i :class "fa-solid fa-shopping-cart") " Shop Now")
			(when external-url
			  (cl-who:htm (:div :class "col-xs-2" :align "right" :data-toggle "tooltip" :title "Copy External URL" 
					    (:a :href "#" :OnClick (parenscript:ps (copy-to-clipboard (parenscript:lisp external-url))) (:i :class  "fa-solid fa-share-nodes"))))))))) company-list))
					;else
      (cl-who:htm (with-html-div-col
		    (:h3 "Record Not Found."))))))
  
;; ----------------------------------------------------------------------------
;; 登录会话访问器：从 Hunchentoot session 读取已登录主体的各种信息。
;; 这些是平台最高频的 helper —— 控制器、视图、策略到处使用。
;; ----------------------------------------------------------------------------

(defun get-login-user ()
  "返回当前登录的系统用户（dod-users 实例）。未登录返回 nil。"
  (hunchentoot:session-value :login-user))

(defun get-login-tenant-id ()
  "返回当前登录用户所属的 tenant-id（数值）。"
  (hunchentoot:session-value :login-user-tenant-id))

(defun get-login-user-role-name ()
  "返回当前登录用户的角色名（如 \"SUPERADMIN\" / \"COMPADMIN\" 等）。"
  (hunchentoot:session-value :login-user-role-name))

(defun get-login-company ()
  "返回当前登录用户所属的 company（dod-company 实例）。"
  (hunchentoot:session-value :login-user-company))


(defun get-login-cust-tenant-id ()
  "返回当前登录客户所属的 tenant-id。"
  (hunchentoot:session-value :login-customer-tenant-id))




(defun get-login-customer-company ()
  "返回当前登录客户所属的 company（dod-company 实例）。"
  ( hunchentoot:session-value :login-customer-company))

(defun get-login-customer-company-name ()
  "返回当前登录客户所属公司的名称字符串。"
    ( hunchentoot:session-value :login-customer-company-name))

(defun get-login-customer-company-id ()
  "返回当前登录客户所属公司的 row-id（数值）。从 session 中存的 company 实例提取。"
  (let ((company (hunchentoot:session-value :login-customer-company)))
    (slot-value company 'row-id)))

(defun get-login-customer-type ()
  "返回当前登录客户的类型（如 STANDARD / GUEST）。"
    ( hunchentoot:session-value :login-customer-type))

(defun get-login-customer-company-website ()
  "返回当前登录客户所属公司的 website 字段。"
    ( hunchentoot:session-value :login-customer-company-website))


(defun get-login-vendor-company ()
  "返回当前登录卖家所属的 company（dod-company 实例）。"
(hunchentoot:session-value :login-vendor-company))

(defun get-login-vendor-company-name ()
  "返回当前登录卖家所属公司的名称字符串。"
 (hunchentoot:session-value :login-vendor-company-name))

(defun get-login-vend-tenant-id ()
  "返回当前登录卖家所属的 tenant-id。"
  (hunchentoot:session-value :login-vendor-tenant-id))


	
    
