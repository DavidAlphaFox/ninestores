;;; nst-ui-Customer.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*
;;;; ============================================================================
;;;; 模块：customer 客户（新风格 nst-，DDD/Hexagonal）
;;;; 分层：UI 控制器/视图层
;;;; 文件：hhub/customer/nst-ui-Customer.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：基于六边形管线的客户管理后台 UI —— 列表 / 实时搜索 / 新增 / 修改对话框 /
;;;;       行渲染 / HTML 列表视图实现。控制器以 com-hhub-transaction-* 命名并统一
;;;;       走 with-hhub-transaction（PEP）做 ABAC 鉴权。
;;;;
;;;; 主要导出：
;;;;   com-hhub-transaction-show-Customer-page    — URL: /hhub/Customer 列表页
;;;;   com-hhub-transaction-search-Customer-action — URL: /hhub/searchCustomeraction 实时搜索
;;;;   com-hhub-transaction-create-Customer-action — URL: /hhub/createCustomeraction 新建
;;;;   com-hhub-transaction-update-Customer-action — URL: /hhub/updateCustomeraction 更新
;;;;   com-hhub-transaction-create-Customer-dialog — 新增/编辑表单对话框 HTML
;;;;   create-model-for-* / create-widgets-for-*   — MVC 模型与 widget
;;;;   display-Customer-row                        — 列表单行 HTML
;;;;   RenderListViewHTML (CustomerHTMLView)       — 表格视图实现
;;;;   Customer-search-html                        — 搜索框 widget
;;;;
;;;; 关联：
;;;;   上游使用方：客户后台路由 /hhub/Customer 等。
;;;;   下游依赖：customer/nst-{dal,bl}-Customer.lisp（领域类与方法）、
;;;;             core PEP 宏 with-hhub-transaction、with-mvc-ui-page、
;;;;             with-mvc-redirect-ui、with-cust-session-check。
;;;;
;;;; 备注：本文件在源代码注释里仍带模板提示（\"keep only one role, delete reset\"），
;;;;       推测部分代码由脚手架生成，未完全清理。
;;;; ============================================================================

(in-package :nstores)

(defun Customer-search-html ()
  :description "Original English. 中文：渲染客户列表页顶部的实时搜索框，绑定
   onkeyup 事件触发 AJAX 搜索（结果填到 #Customerlivesearchresult）。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
	  (:div :id "custom-search-input"
		(:div :class "input-group col-xs-12 col-sm-6 col-md-6 col-lg-6"
		      (with-html-search-form "idsyssearchCustomer" "syssearchCustomer" "idCustomerlivesearch" "Customerlivesearch" "searchCustomeraction" "onkeyupsearchform1event();" "Search for an Customer"
			(submitsearchform1event-js "#idCustomerlivesearch" "#Customerlivesearchresult")))))))

(defun com-hhub-transaction-show-Customer-page ()
  :description "Original English. 中文：客户列表页控制器。with-cust-session-check
   要求客户登录，再用 with-mvc-ui-page 跑 model + widgets 渲染。"
  (with-cust-session-check ;; delete if not needed.
    (with-mvc-ui-page "Customer" #'create-model-for-showCustomer #'create-widgets-for-showCustomer :role  :customer))) ;; keep only one role, delete reset.

(defun create-model-for-showCustomer ()
  :description "Original English. 中文：构造列表页模型。流程：
   ① 取登录 company；② 通过 CustomerAdapter ProcessReadAllRequest 拉客户列表；
   ③ Adapter 把列表转 ResponseModel 列表；④ Presenter 转 ViewModel 列表；
   ⑤ 在 with-hhub-transaction PEP 内返回 thunk（多值：viewallmodel + htmlview + username）。
   PEP key = \"com-hhub-transaction-Customer-page\"，由 ABAC 决定是否放行。"
  (let* ((company (get-login-company))
	 (username (get-login-user-name))
	 (presenterobj (make-instance 'CustomerPresenter))
	 (requestmodelobj (make-instance 'CustomerRequestModel
					 :company company))
	 (adapterobj (make-instance 'CustomerAdapter))
	 (objlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj objlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'CustomerHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-Customer-page" params 
      (function (lambda ()
	(values viewallmodel htmlview username))))))

(defun create-widgets-for-showCustomer (modelfunc)
  :description "Original English. 中文：列表页 widget 工厂。返回三个 widget：
   ① 面包屑 + 搜索框；② 列表区域（含 Add Customer 按钮 + 计数 + 表格）；
   ③ 一段 JS（submitformevent-js 绑定 #Customerlivesearchresult 的事件）。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-customer-breadcrumb)
		       (Customer-search-html)
			 (:hr)))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (:h4 "Showing records for Customer."))
		       (:div :id "Customerlivesearchresult" 
			     (:div :class "row"
				   (:div :class"col-xs-6"
					 (:a :href "/hhub/addCustomer" (:i :class "fa-solid fa-plus") "&nbsp;&nbsp;Create Customer"))
				   (:div :class "col-xs-6" :align "right" 
					 (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
			     (:hr)
			     (cl-who:str (RenderListViewHTML htmlview viewallmodel)))))))
	  (widget3 (function (lambda ()
		     (submitformevent-js "#Customerlivesearchresult")))))
      (list widget1 widget2 widget3))))

(defun create-widgets-for-updateCustomer (modelfunc)
  :description "Original English. 中文：更新客户的 widget 函数 —— 直接复用通用重定向
   widget create-widgets-for-genericredirect，更新成功后会跳转到 redirectlocation。"
  (funcall #'create-widgets-for-genericredirect modelfunc))


(defmethod RenderListViewHTML ((htmlview CustomerHTMLView) viewmodellist)
  :description "Original English. 中文：CustomerHTMLView 把 viewmodel 列表渲染为表格，
   表头列出 Customer 全部字段，行渲染委托给 display-Customer-row。
   备注：表头里包含 password / salt 列（仅在管理后台展示，前端表单回填用，推测）。"
  (when viewmodellist
    (display-as-table (list "row-id" "name" "address" "phone" "email" "firstname" "lastname" "salutation" "title" "birthdate" "city" "state" "country" "zipcode" "picture-path" "password" "salt" "cust-type" "email-add-verified" "company") viewmodellist 'display-Customer-row)))

(defun create-model-for-searchCustomer ()
  :description "Original English. 中文：构造搜索请求模型。读取 query 参数
   Customerlivesearch 作为搜索关键词（应放进 :field1 slot — 但目标类
   CustomerSearchRequestModel/CustomerRequestModel 上未声明此 slot；
   推测：依赖父类或运行期扩展）。
   走 PEP \"com-hhub-transaction-search-Customer-action\" 鉴权。"
  (let* ((search-clause (hunchentoot:parameter "Customerlivesearch"))
	 (company (get-login-company))
	 (presenterobj (make-instance 'CustomerPresenter))
	 (requestmodelobj (make-instance 'CustomerSearchRequestModel
						 :field1 search-clause
						 :company company))
	 (adapterobj (make-instance 'CustomerAdapter))
	 (domainobjlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj domainobjlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'CustomerHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-search-Customer-action" params 
      (function (lambda ()
	(values viewallmodel htmlview))))))



(defun com-hhub-transaction-search-Customer-action ()
  :description "Original English. 中文：客户实时搜索的 MVC 控制器。返回的 HTML 被
   AJAX 注入到 #Customerlivesearchresult。流程：modelfunc 走 PEP 拿到 viewmodel →
   widgets 函数生成 widget 列表 → 顺序调用并把输出拼成完整 HTML 字符串。"
  (let* ((modelfunc (funcall #'create-model-for-searchCustomer))
	 (widgets (funcall #'create-widgets-for-searchCustomer modelfunc)))
    (cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
      (loop for widget in widgets do
	(cl-who:str (funcall widget))))))

(defun create-model-for-updateCustomer ()
  :description "Original English. 中文：更新客户的模型。从 hunchentoot 表单参数构造
   CustomerRequestModel，调 ProcessUpdateRequest 走完领域服务；成功后返回 thunk
   告知 with-mvc-redirect-ui 重定向到 redirectlocation \"/hhub/Customer\"。
   异常分支用 hhub-business-function-error 包装上报。
   备注：format t 用于异常 errstring 应该是想用 format nil（推测：副作用而非生成字符串）。"
  (let* ((row-id (hunchentoot:parameter "row-id"))
	 (name (hunchentoot:parameter "name"))
	 (address (hunchentoot:parameter "address"))
	 (phone (hunchentoot:parameter "phone"))
	 (email (hunchentoot:parameter "email"))
	 (firstname (hunchentoot:parameter "firstname"))
	 (lastname (hunchentoot:parameter "lastname"))
	 (salutation (hunchentoot:parameter "salutation"))
	 (title (hunchentoot:parameter "title"))
	 (birthdate (hunchentoot:parameter "birthdate"))
	 (city (hunchentoot:parameter "city"))
	 (state (hunchentoot:parameter "state"))
	 (country (hunchentoot:parameter "country"))
	 (zipcode (hunchentoot:parameter "zipcode"))
	 (picture-path (hunchentoot:parameter "picture-path"))
	 (password (hunchentoot:parameter "password"))
	 (salt (hunchentoot:parameter "salt"))
	 (cust-type (hunchentoot:parameter "cust-type"))
	 (email-add-verified (hunchentoot:parameter "email-add-verified"))
	  (company (get-login-company)) ;; or get ABAC subject specific login company function. 
	 (requestmodel (make-instance 'CustomerRequestModel
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
					 :company company))
	 (adapterobj (make-instance 'CustomerAdapter))
	 (redirectlocation  "/hhub/Customer")
	 (params nil))
    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-update-Customer-action" params 
      (handler-case 
	  (let ((domainobj (ProcessUpdateRequest adapterobj requestmodel)))
	    (function (lambda ()
	      (values redirectlocation domainobj))))
	(error (c)
	  (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c)))))))


(defun create-model-for-createCustomer ()
  :description "Original English. 中文：新建客户的模型，与 update 流程对偶。从表单参数
   构造 CustomerRequestModel → ProcessCreateRequest → 重定向 /hhub/Customer。
   PEP key = \"com-hhub-transaction-create-Customer-action\"。"
  (let* ((row-id (hunchentoot:parameter "row-id"))
	 (name (hunchentoot:parameter "name"))
	 (address (hunchentoot:parameter "address"))
	 (phone (hunchentoot:parameter "phone"))
	 (email (hunchentoot:parameter "email"))
	 (firstname (hunchentoot:parameter "firstname"))
	 (lastname (hunchentoot:parameter "lastname"))
	 (salutation (hunchentoot:parameter "salutation"))
	 (title (hunchentoot:parameter "title"))
	 (birthdate (hunchentoot:parameter "birthdate"))
	 (city (hunchentoot:parameter "city"))
	 (state (hunchentoot:parameter "state"))
	 (country (hunchentoot:parameter "country"))
	 (zipcode (hunchentoot:parameter "zipcode"))
	 (picture-path (hunchentoot:parameter "picture-path"))
	 (password (hunchentoot:parameter "password"))
	 (salt (hunchentoot:parameter "salt"))
	 (cust-type (hunchentoot:parameter "cust-type"))
	 (email-add-verified (hunchentoot:parameter "email-add-verified"))
	 (company (get-login-company)) ;; or get ABAC subject specific login company function. 
	 (requestmodel (make-instance 'CustomerRequestModel
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
					 :company company))
	 (adapterobj (make-instance 'CustomerAdapter))
	 (redirectlocation  "/hhub/Customer")
	 (params nil))
    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-create-Customer-action" params 
      (handler-case 
	  (let ((domainobj (ProcessCreateRequest adapterobj requestmodel)))
	    ;; Create the GST HSN Code object if not present. 
	    (function (lambda ()
	      (values redirectlocation domainobj))))
	(error (c)
	  (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c)))))))

(defun com-hhub-transaction-create-Customer-dialog (&optional domainobj)
  :description "Original English. 中文：渲染新增/编辑客户的表单 HTML（嵌入 modal）。
   传入 domainobj 时回填字段（编辑模式），不传时全部空（新建模式）。
   表单 action：编辑 → updateCustomeraction；新建 → createCustomeraction。
   备注：表单内有重复的 email-add-verified input（两次），推测脚手架生成笔误。"
  (let* ((row-id  (if domainobj (slot-value domainobj 'row-id)))
	 (name  (if domainobj (slot-value domainobj 'name)))
	 (address  (if domainobj (slot-value domainobj 'address)))
	 (phone  (if domainobj (slot-value domainobj 'phone)))
	 (email  (if domainobj (slot-value domainobj 'email)))
	 (firstname  (if domainobj (slot-value domainobj 'firstname)))
	 (lastname  (if domainobj (slot-value domainobj 'lastname)))
	 (salutation  (if domainobj (slot-value domainobj 'salutation)))
	 (title  (if domainobj (slot-value domainobj 'title)))
	 (birthdate  (if domainobj (slot-value domainobj 'birthdate)))
	 (city  (if domainobj (slot-value domainobj 'city)))
	 (state  (if domainobj (slot-value domainobj 'state)))
	 (country  (if domainobj (slot-value domainobj 'country)))
	 (zipcode  (if domainobj (slot-value domainobj 'zipcode)))
	 (picture-path  (if domainobj (slot-value domainobj 'picture-path)))
	 (password  (if domainobj (slot-value domainobj 'password)))
	 (salt  (if domainobj (slot-value domainobj 'salt)))
	 (cust-type  (if domainobj (slot-value domainobj 'cust-type)))
	 (email-add-verified  (if domainobj (slot-value domainobj 'email-add-verified)))
	 (company  (if domainobj (slot-value domainobj 'company))))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form (format nil "form-addCustomer~A" row-id)  (if domainobj "updateCustomeraction" "createCustomeraction")
		    (:img :class "profile-img" :src "/img/logo.png" :alt "")
		    (:div :class "form-group"
			  (:input :class "form-control" :name "row-id" :maxlength "20"  :value  row-id :placeholder "Customer (max 20 characters) " :type "text" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value name :placeholder "name"  :name "name" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value address :placeholder "address"  :name "address" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value phone :placeholder "phone"  :name "phone" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value email :placeholder "email"  :name "email" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value firstname :placeholder "firstname"  :name "firstname" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value lastname :placeholder "lastname"  :name "lastname" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value salutation :placeholder "salutation"  :name "salutation" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value title :placeholder "title"  :name "title" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value birthdate :placeholder "birthdate"  :name "birthdate" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value city :placeholder "city"  :name "city" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value state :placeholder "state"  :name "state" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value country :placeholder "country"  :name "country" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value zipcode :placeholder "zipcode"  :name "zipcode" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value picture-path :placeholder "picture-path"  :name "picture-path" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value password :placeholder "password"  :name "password" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value salt :placeholder "salt"  :name "salt" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value cust-type :placeholder "cust-type"  :name "cust-type" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value email-add-verified :placeholder "email-add-verified"  :name "email-add-verified" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value email-add-verified :placeholder "email-add-verified"  :name "email-add-verified" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value company :placeholder "company"  :name "company" ))
		    (:div :class "form-group"
			  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))





(defun create-widgets-for-createCustomer (modelfunc)
  :description "Original English. 中文：新建客户成功后复用通用重定向 widget。"
  (funcall #'create-widgets-for-genericredirect modelfunc))




(defun create-widgets-for-searchCustomer (modelfunc)
  :description "Original English. 中文：搜索结果区域 widget。包含 \"Add Customer\" 按钮
   （触发 #editCustomer-modal 弹窗）+ 计数 badge + 表格视图。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (:div :class "row"
			     (:div :class"col-xs-6"
				   (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#editCustomer-modal" "Add Customer")
				   (modal-dialog "editCustomer-modal" "Add/Edit Customer" (com-hhub-transaction-create-Customer-dialog)))
			     (:div :class "col-xs-6" :align "right" 
				   (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
		       (:hr)
		       (RenderListViewHTML htmlview viewallmodel))))))
      (list widget1))))



 
(defun display-Customer-row (Customer)
  :description "Original English. 中文：渲染表格中单个客户行（一组 <td>）。最后一列是
   编辑按钮，触发 modal 弹出 com-hhub-transaction-create-Customer-dialog 表单。
   备注：with-slots 列表里出现 %20%..%37% 这种像 URL 编码遗留的占位 slot
   （推测：脚手架自动追加，未实际使用；应是无害但不优雅）。"
  (with-slots (row-id name address phone email firstname lastname salutation title birthdate city state country zipcode picture-path password salt cust-type email-add-verified company %20% %21% %22% %23% %24% %25% %26% %27% %28% %29% %30% %31% %32% %33% %34% %35% %36% %37%) Customer
    (cl-who:with-html-output (*standard-output* nil)
      (:td  :height "10px" (cl-who:str row-id))
      (:td  :height "10px" (cl-who:str name))
      (:td  :height "10px" (cl-who:str address))
      (:td  :height "10px" (cl-who:str phone))
      (:td  :height "10px" (cl-who:str email))
      (:td  :height "10px" (cl-who:str firstname))
      (:td  :height "10px" (cl-who:str lastname))
      (:td  :height "10px" (cl-who:str salutation))
      (:td  :height "10px" (cl-who:str title))
      (:td  :height "10px" (cl-who:str birthdate))
      (:td  :height "10px" (cl-who:str city))
      (:td  :height "10px" (cl-who:str state))
      (:td  :height "10px" (cl-who:str country))
      (:td  :height "10px" (cl-who:str zipcode))
      (:td  :height "10px" (cl-who:str picture-path))
      (:td  :height "10px" (cl-who:str password))
      (:td  :height "10px" (cl-who:str salt))
      (:td  :height "10px" (cl-who:str cust-type))
      (:td  :height "10px" (cl-who:str email-add-verified))
      (:td  :height "10px" 
	    (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target (format nil "#editCustomer-modal~A" row-id) (:i :class "fa-solid fa-pencil"))
	    (modal-dialog-v2 (format nil "editCustomer-modal~A" row-id) (cl-who:str (format nil "Add/Edit Customer " )) (com-hhub-transaction-create-Customer-dialog Customer))
	    (modal-dialog (format nil "editCustomer-modal~A" row-id) "Add/Edit Customer" (com-hhub-transaction-create-Customer-dialog Customer))))))


(defun com-hhub-transaction-update-Customer-action ()
  :description "Original English. 中文：更新客户的最终控制器入口。with-cust-session-check
   要求登录，with-mvc-redirect-ui 跑完 model+widgets 后返回重定向 URL，控制器把
   URL 写为响应（让客户端跳转到 \"/hhub/Customer\"）。"
  (with-cust-session-check ;; delete if not needed.
    (let ((url (with-mvc-redirect-ui  #'create-model-for-updateCustomer #'create-widgets-for-updateCustomer)))
      (format nil "~A" url))))


(defun com-hhub-transaction-create-Customer-action ()
  :description "Original English. 中文：新建客户的最终控制器入口，与 update-action 对偶。"
  (with-cust-session-check ;; delete if not needed.
    (let ((url (with-mvc-redirect-ui  #'create-model-for-createCustomer #'create-widgets-for-createCustomer)))
      (format nil "~A" url))))









