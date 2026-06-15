;;; dod-ui-cad.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：sysuser —— Company Admin（CAD）后台 UI
;;;; 分层：UI（控制器 + CL-WHO 模板）
;;;; 文件：hhub/sysuser/dod-ui-cad.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：CAD 角色专用后台界面：
;;;;   - 登录 / 登出 / 主页
;;;;   - 商品审批（Approve/Reject 模态对话框）
;;;;   - 商家审批
;;;;   - 商品类目维护（nested set）
;;;;   - 个人资料 / 联系人 / 修改密码 / 公司外部 URL
;;;;   - 侧边栏 / 顶部导航 widget。
;;;;
;;;; 主要导出（按功能）：
;;;;   登录：com-hhub-transaction-cad-login-page / com-hhub-transaction-cad-login-action / dod-cad-login
;;;;   登出：com-hhub-transaction-cad-logout / create-model-for-cadlogout
;;;;   首页：com-hhub-transaction-compadmin-home（待审批商品列表）
;;;;   商品审批：com-hhub-transaction-cad-product-approve-action / -reject-action
;;;;   商家审批：com-hhub-transaction-vendor-approve-action / -reject-action
;;;;             vendor-card-for-approval / modal.approve-vendor-html / modal.reject-vendor-html
;;;;   类目：dod-controller-product-categories-page / com-hhub-transaction-prodcatg-add-action /
;;;;        dod-controller-delete-product-category / modal.product-category-add / product-category-row
;;;;   个人资料：dod-controller-cad-profile / modal.account-admin-update-details /
;;;;             create-model-for-cadupdatedetailsaction / com-hhub-transaction-compadmin-updatedetails-action
;;;;             modal.account-external-url / com-hhub-transaction-publish-account-exturl
;;;;   导航 / 侧栏：render-compadmin-sidebar-offcanvas / with-compadmin-navigation-bar
;;;;   approval 页面：dod-controller-products-approval-page / dod-controller-vendor-approval-page
;;;;
;;;; 关联：
;;;;   上游：浏览器 /hhub/hhubcad* 路径
;;;;   下游：products/dod-bl-prd.lisp（类目操作）、sysuser/dod-bl-cad.lisp（approve/reject）、
;;;;         sysuser/dod-bl-usr.lisp（用户更新）、core/dod-ui-utl.lisp（PEP 宏）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun render-compadmin-sidebar-offcanvas ()
    ;; CAD 后台左侧 offcanvas 侧栏：Home / Customer Approvals / Vendor Approvals 三个链接。
    ;; 在 :compile-toplevel 也可见，方便其他文件展开 cl-who 时使用。
    (cl-who:with-html-output (*standard-output* nil :prologue t :indent t)
      (:div :class "offcanvas offcanvas-start" :tabindex"-1" :id "offcanvasExample" :aria-labelledby "offcanvasExampleLabel"
	    (:div :class "offcanvas-header"
		  (:img :src "/img/logo.png" :alt "" :width "32" :height "32" :class "rounded-circle me-2")
		  (:h5 :class "offcanvas-title" :id "offcanvasExampleLabel" "Nine Stores")
		  (:button :type "button" :class "btn-close" :data-bs-dismiss "offcanvas" :aria-label "Close"))
	    (:div :class "offcanvas-body"
		  (:ul :class "nav nav-pills flex-column mb-auto"
		       (:li :class "nav-item"
			    (:a :href "hhubcadindex" :class "nav-link link-body-emphasis"    
				(:i :class "fa-solid fa-house")  "Home"))
		       (:li :class "nav-item" (:a :href "/hhub/dasproductapprovals" :class "nav-link link-body-emphasis"    
						  " Customer Approvals"))
		       (:li :class "nav-item"  (:a :href "/hhub/hhubvendorapprovalpage" :class "nav-link link-body-emphasis"    
						   " Vendor Approvals"))))))))


(defun com-hhub-transaction-vendor-reject-action ()
  "URL：/hhub/hhubvendorrejectaction（推测）。
   CAD 拒绝商家入驻：取 vendor-id 后调 reject-vendor，重定向回 vendor 审批页。"
  (with-cad-session-check
    (let ((params nil)
	  (companyadmin (get-login-user)))
      (setf params (acons "uri" (hunchentoot:request-uri*)  params))
      (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
   (with-hhub-transaction "com-hhub-transaction-vendor-reject-action" params
     (let* ((id (hunchentoot:parameter "vendor-id"))
	    (vendor (select-vendor-by-id id)))
       (reject-vendor vendor companyadmin)
       (hunchentoot:redirect "/hhub/hhubvendorapprovalpage"))))))
      
(defun com-hhub-transaction-vendor-approve-action ()
  "URL：/hhub/hhubvendorapproveaction（推测）。
   CAD 通过 VendorApprovalAdapter / RequestModelVendorApproval 走 ProcessUpdateRequest 链路批准商家。
   完成后重定向回 vendor 审批页。"
  (with-cad-session-check
    (let* ((params nil)
	   (vendor-id (hunchentoot:parameter "vendor-id"))
	   (companyadmin (get-login-user)))

      (setf params (acons "uri" (hunchentoot:request-uri*)  params))
      (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
      (setf params (acons "company" (get-login-company) params))
      
      (with-hhub-transaction "com-hhub-transaction-vendor-approve-action"  params
	(let* ((requestmodel (make-instance 'RequestModelVendorApproval
					    :vendor-id vendor-id
					    :companyadmin companyadmin))
	       (adapter (make-instance 'VendorApprovalAdapter)))
	  (ProcessUpdateRequest adapter requestmodel)
	  (hunchentoot:redirect "/hhub/hhubvendorapprovalpage"))))))
      
(defun test-vendor-approval ()
  "调试/测试用：硬编码 vendor-id=1、admin=user(4) tenant=2，跑一次 ProcessUpdateRequest，返回更新后的 vendor。
   不在生产路径上。"
  (let* ((vendor-id 1)
	 (companyadmin (select-user-by-id 4 2))
	 (requestmodel (make-instance 'RequestModelVendorApproval
				      :vendor-id vendor-id
				      :companyadmin companyadmin))
	 (adapter (make-instance 'VendorApprovalAdapter))
	 (updatedvendor (ProcessUpdateRequest adapter requestmodel)))
    updatedvendor))


(defun create-model-for-productcategoriespage ()
  "MVC model：读取本租户类目（不含 root）与计数，闭包返回 (categories catgcount)。"
  (let* ((company (get-login-company))
	 (categories (select-prdcatg-by-company company))
	 (catgcount (length categories)))
    (function (lambda ()
      (values categories catgcount)))))

(defun create-widgets-for-productcategoriespage (modelfunc)
  "MVC view：渲染 'Add New Category' 按钮 + 计数 + 类目列表表格。"
  (multiple-value-bind ( categories catgcount) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col
			   (:a :data-bs-toggle "modal" :data-bs-target (format nil "#dodvenaddprodcatg-modal")  :href "#"  (:i :class "fa-solid fa-plus") "Add New Category" )
			   (modal-dialog-v2 (format nil "dodvenaddprodcatg-modal") "Add New Category" (modal.product-category-add)))
			 (with-html-div-col :align "right"
			   (:span :class "badge" (cl-who:str (format nil " ~d " catgcount)))))
		       (:hr)))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (cl-who:str (display-as-table (list "Name" "Action") categories 'product-category-row)))))))
    (list widget1 widget2))))

  
(defun dod-controller-product-categories-page ()
  "URL：/hhub/hhubcadlistprodcatg（推测，与 prodcatg-add-action 重定向目标一致）。
   CAD 类目管理主页。"
  (with-cad-session-check
    (with-mvc-ui-page "Company Admin - Product Categories" #'create-model-for-productcategoriespage #'create-widgets-for-productcategoriespage :role :compadmin)))


(defun modal.product-category-add ()
  "Add Category 模态对话框 fragment：单字段 catg-name 表单，POST 到 hhubprodcatgaddaction。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-html-div-row 
      (with-html-div-col-8
	(with-html-form "form-productcategories" "hhubprodcatgaddaction"
	  (:div :class "form-group"
		(:input :class "form-control" :name "catg-name" :value "" :placeholder "Category Name" :type "text" ))
	  (:div :class "form-group" 
		(:input :type "submit"  :class "btn btn-primary" :value "Add Category")))))))

(defun product-category-row (category &rest arguments)
  "类目列表单行：name + 删除按钮（GET hhubdeleteprodcatg?id=<row-id>）。"
  (declare (ignore arguments))
  (with-slots (row-id catg-name) category
      (cl-who:with-html-output (*standard-output* nil)
	(:td  :height "10px" (cl-who:str catg-name))
	(:td :height "10px"
	     (:div :class "col-xs-2" :data-toggle "tooltip" :title "Delete" 
		   (:a :href (format nil "hhubdeleteprodcatg?id=~A" row-id) (:i :class "fa-regular fa-trash-can")))))))



(defun com-hhub-transaction-prodcatg-add-action ()
  "URL：/hhub/hhubprodcatgaddaction（推测）。
   CAD 添加类目：调 add-new-node-prdcatg 把 catg-name 插入 nested set 树（root 之下），
   完成后跳回类目列表页。"
  (with-cad-session-check
    (let* ((catg-name (hunchentoot:parameter "catg-name"))
	   (company (get-login-company))
	   (params nil))
      
      (setf params (acons "company" company params))
      (setf params (acons "uri" (hunchentoot:request-uri*)  params))
      (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
      
      (with-hhub-transaction "com-hhub-transaction-prodcatg-add-action" params
	(when catg-name (add-new-node-prdcatg catg-name company)))
      (hunchentoot:redirect "/hhub/hhubcadlistprodcatg"))))
  


(defun dod-controller-delete-product-category ()
  "URL：/hhub/hhubdeleteprodcatg?id=<row-id>。
   CAD 删除类目（调用 delete-prd-catg —— nested set 物理删除整子树），跳回列表。"
  (with-cad-session-check
    (let ((id (hunchentoot:parameter "id"))
	  (company (get-login-company)))
      (when id (delete-prd-catg id company))
      (hunchentoot:redirect "/hhub/hhubcadlistprodcatg"))))



(defun create-model-for-publishaccountexturl ()
  "MVC model：若 company.external-url 为空则 generate-account-ext-url 生成并落库；
   返回 redirectto 跳转目标（来自表单参数）。"
  (let* ((params nil))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
    (with-hhub-transaction "com-hhub-transaction-publish-account-exturl" params 
      (let* ((redirectto (hunchentoot:parameter "redirectto"))
	     (account (get-login-company))
	     (ext-url (slot-value account 'external-url)))
	(unless ext-url
	  (let ((url (generate-account-ext-url account)))
	    (setf (slot-value account 'external-url) url)
	    (update-company account)))
	(function (lambda ()
	  redirectto))))))

  
(defun com-hhub-transaction-publish-account-exturl ()
  "URL：/hhub/hhubpublishaccountexturl（推测）。生成公司 external-url 后跳转。"
  (with-cad-session-check
    (let ((uri (with-mvc-redirect-ui #'create-model-for-publishaccountexturl #'create-widgets-for-genericredirect)))
      (format nil "~A" uri))))

(defun create-model-for-cadprofile ()
  "Profile 页 model：返回当前 company 与登录姓名。"
  (let ((account (get-login-company))
	(loginusername (get-login-user-name)))
    (function (lambda ()
      (values account loginusername)))))

(defun create-widgets-for-cadprofile (modelfunc)
  "Profile 页 view：欢迎消息 + 4 个 list-group 入口（类目 / 外部 URL / 联系人 / 修改密码）。"
  (multiple-value-bind (account loginusername) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-catch-submit-event "idcadprofile" 
			 (:h3 "Welcome " (cl-who:str (format nil "~A" loginusername)))
			 (:hr)
			 (:div :class "list-group col-sm-6 col-md-6 col-lg-6"
			       (:a :class "list-group-item"  :href "hhubcadlistprodcatg"  "Product Categories")
			       (:a :data-bs-toggle "modal" :class "list-group-item"  :data-bs-target (format nil "#dodaccountexturl-modal")  :href "#"  "Account External URL")
			       (modal-dialog-v2 (format nil "dodaccountexturl-modal") "Account External URL" (modal.account-external-url account))
			       (:a :class "list-group-item" :data-bs-toggle "modal" :data-bs-target (format nil "#dodaccountadminupdate-modal")  :href "#"  "Contact Information")
			       (modal-dialog-v2 (format nil "dodaccountadminupdate-modal") "Update Account Administrator" (modal.account-admin-update-details)) 
			       (:a :class "list-group-item" :data-bs-toggle "modal" :data-bs-target (format nil "#dodaccadminchangepin-modal")  :href "#"  "Change Password")
			       (modal-dialog-v2 (format nil "dodaccadminchangepin-modal") "Change Password" (modal.account-admin-change-pin)))))))))
      (list widget1))))

(defun dod-controller-cad-profile ()
  "URL：/hhub/hhubcadprofile（推测）。CAD 个人 / 公司资料主页。"
  (with-cad-session-check
    (with-mvc-ui-page "Welcome Company Administrator" #'create-model-for-cadprofile #'create-widgets-for-cadprofile :role :compadmin)))


(defun modal.account-admin-change-pin ()
  ;; 占位：修改密码模态框，当前未实现（推测：后续填充）。
  )

(defun modal.account-external-url (account)
  :description "Update the external URL for a given account.
   中文：账户外部 URL 模态对话框 ——
         若 account.external-url 已有则只展示文本；
         否则展示 'Generate URL' 按钮 POST 到 hhubpublishaccountexturl 触发生成。"
  (let* ((ext-url (slot-value account 'external-url)))
    (when ext-url
      (cl-who:with-html-output (*standard-output* nil)
	(:div :class "row" 
	      (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		    (:p (cl-who:str (format nil "~A" ext-url)))))))
    (unless ext-url
      (cl-who:with-html-output (*standard-output* nil)
	(:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (:form :id (format nil "form-compadminupdate")  :role "form" :method "POST" :action "hhubpublishaccountexturl" :enctype "multipart/form-data" 
			 (:div :class "form-group" :style "display:none;"
			       (:input :class "form-control" :name "redirectto" :value "/hhub/hhubcadprofile" :placeholder "" :type "text"))
			 (:div :class "form-group"
			       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Generate URL")))))))))




(defun modal.account-admin-update-details ()
  "Update CAD 个人联系信息（name/phone/email）模态框，POST 到 hhubcompadminupdateaction。"
  (let* ((admin (get-login-user))
	 (name (name admin))
	 (phone  (phone-mobile admin))
	 (email (email admin)))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (:form :id (format nil "form-compadminupdate")  :role "form" :method "POST" :action "hhubcompadminupdateaction" :enctype "multipart/form-data" 
			 (:h1 :class "text-center login-title"  "Update Company Admin Details")
			 (:div :class "form-group"
			       (:input :class "form-control" :name "name" :value name :placeholder "Customer Name" :type "text"))
			 (:div :class "form-group"
			       (:input :class "form-control" :name "phone"  :value phone :placeholder "Phone"  :type "text" ))
			 (:div :class "form-group"
			       (:input :class "form-control" :name "email" :value email :placeholder "Email" :type "text"))
			 (:div :class "form-group"
			       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))

      
(defun create-model-for-cadupdatedetailsaction ()
  "MVC model：把 name/phone/email 写到当前登录 admin，update-user 落库；返回跳回 profile 页 URL。"
  (let* ((params nil)
	 (redirectlocation "/hhub/hhubcadprofile"))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
    (with-hhub-transaction "com-hhub-transaction-compadmin-updatedetails-action" params
      (let ((name (hunchentoot:parameter "name"))
	    (phone (hunchentoot:parameter "phone"))
	    (email (hunchentoot:parameter "email"))
	    (admin (get-login-user)))
	
	(when admin 
	  (setf (slot-value admin 'name) name)
	  (setf (slot-value admin 'phone-mobile) phone)
	  (setf (slot-value admin 'email) email)
	  (update-user admin))
	(function (lambda ()
	  redirectlocation))))))


(defun com-hhub-transaction-compadmin-updatedetails-action ()
  "URL：/hhub/hhubcompadminupdateaction（推测）。CAD 提交联系信息更新。"
  (with-cad-session-check
    (let ((uri (with-mvc-redirect-ui #'create-model-for-cadupdatedetailsaction #'create-widgets-for-genericredirect)))
      (format nil "~A" uri))))

(eval-when (:compile-toplevel :load-toplevel :execute)
 (defun with-compadmin-navigation-bar ()
    :documentation "This macro returns the html text for generating a navigation bar using bootstrap.
   中文：CAD 后台顶部导航栏：左侧 toggle 侧栏 / Home，右侧 通知 / Profile / Logout。
         注：函数名以 with- 开头但实为普通 defun（非 macro），原 docstring 略带误导。"
    (cl-who:with-html-output (*standard-output* nil)
       (:nav :class "navbar navbar-expand-sm  sticky-top navbar-dark bg-dark" :id "hhubcompadminnavbar"  
     	     (:div  :class "container-fluid"
		   (:a :class "navbar-brand" :href "/hhub/hhubcadindex" (:img :style "width: 30px; height: 24px;" :src "/img/logo.png" ))
		   (:button :class "navbar-toggler" :type "button" :data-bs-toggle "collapse" :data-bs-target "#navbarSupportedContent" :aria-controls "navbarSupportedContent" :aria-expanded "false" :aria-label "Toggle navigation" 
			    (:span :class "navbar-toggler-icon" ))
		   (:div :class "collapse navbar-collapse justify-content-between" :id "navbarSupportedContent"
			 (:ul :class "navbar-nav me-auto mb-2 mb-lg-0"
			      (:li :class "nav-item"
				  (:a :class "btn btn-primary" :data-bs-toggle "offcanvas" :href "#offcanvasExample" :role "button" :aria-controls "offcanvasExample" (:i :class "fa-solid fa-bars")))
			      (:li :class "nav-item" 	
				   (:a :class "nav-link active" :aria-current "page" :href "/hhub/hhubcadindex" (:i :class "fa-solid fa-house") "&nbsp;Home"))
		   	      ;;(:li :class "nav-item" :align "center" (:a :class "nav-link" :href "#" (cl-who:str (format nil "Group: ~a" (slot-value (get-login-company) 'name)))))
			      (:li :class "nav-item" :align "center" (:a :class "nav-link" :href "#" (print-web-session-timeout))))
			 (:ul :class "navbar-nav ms-auto"
			      (:li :class "nav-item"  (:a :class "nav-link" :href "#"  (:i :class "fa-regular fa-bell")))
			      (:li :class "nav-item"  (:a :class "nav-link" :href "/hhub/hhubcadprofile"  (:i :class "fa-regular fa-user")))
			      (:li :class "nav-item" (:a :class "nav-link" :href "/hhub/hhubcadlogout" (:i :class "fa-solid fa-arrow-right-from-bracket"))))))))))


(defun com-hhub-transaction-cad-login-page ()
  "URL：/hhub/cad-login.html / hhubcadloginpage（推测）。
   先做一次 'select 1' 探测数据库连接：
     - 失败且错误码 2006（MySQL server has gone away） → stop-das/start-das 重启数据库连接，跳回登录页；
     - 已登录 → 直接重定向到 /hhub/hhubcadindex；
     - 未登录 → 渲染登录表单（POST hhubcadloginaction）。"
  (handler-case
      (progn  (if (equal (caar (clsql:query "select 1" :flatp nil :field-names nil :database *dod-db-instance*)) 1) T)	      
	      (if (is-dod-session-valid?)
		  (hunchentoot:redirect "/hhub/hhubcadindex")
		  ;else
		  (with-standard-compadmin-page "Company Administrator Login"
		    (:div :id "idcompadminlogin" :class "row"
			  (:div :class "col-sm-6 col-md-4 col-md-offset-4"
				(:div :class "account-wall"
				      (:img :class "profile-img" :src "/img/logo.png" :alt "")
				      (:h1 :class "text-center login-title"  "Login to Nine Stores")
				      (:form :class "form-signin" :role "form" :method "POST" :action "hhubcadloginaction"
					     (:div :class "form-group"
						   (:input :class "form-control" :name "phone" :placeholder "Enter RMN. Ex: 9999999999" :type "text"))
					     (:div :class "form-group"
						   (:input :class "form-control" :name "password"  :placeholder "Password=demo" :type "password"))
					     (:input :type "submit"  :class "btn btn-primary" :value "Login")))))
		    (submitformevent-js "#idcompadminlogin")))) 
    (clsql:sql-database-data-error (condition)
      (if (equal (clsql:sql-error-error-id condition) 2006 )
	  (progn
	    (stop-das) 
	    (start-das)
	    (hunchentoot:redirect "/hhub/cad-login.html"))))))

;;;;;;;;;;;; com-hhub-transaction-compadmin-home ;;;;;;;;;;;;;;;
(defun create-model-for-compadminhome ()
  "首页 model：取本租户 PENDING 商品列表 + 计数 + 登录姓名。包在 with-hhub-transaction 内 PEP 鉴权。"
  (let ((params nil))
    ;; We are not checking the URI for home page, because it contains the session variable. 
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
    (with-hhub-transaction "com-hhub-transaction-compadmin-home" params
      (let* ((products (get-products-for-approval (get-login-tenant-id)))
	     (numproducts (length products))
	     (username (get-login-user-name)))
	(function (lambda ()
	  (values  products numproducts username)))))))

(defun create-widgets-for-compadminhome (modelfunc)
  "首页 view：欢迎语 + 待审批数量 badge + 商品 tile 网格（display-as-tiles + product-card-for-approval）。"
  (multiple-value-bind ( products numproducts username) (funcall  modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)   
		       (with-html-div-row
			 (with-html-div-col-6
			   (:h4 "Welcome " (cl-who:str (format nil "~A" username)))))
		       (:hr)
		       (with-html-div-row
			 (with-html-div-col-6
			   (:p "Pending Product Approvals"))
			 (with-html-div-col-6 
			   (:div :class "col-xs-6" :align "right" 
				 (:b (:span :class "position-relative translate-middle badge rounded-pill bg-success" (cl-who:str (format nil "~d" numproducts)))))))
		       (:hr)
		       (with-catch-submit-event  "idcompadminhome" 
			 (cl-who:str (display-as-tiles products 'product-card-for-approval "product-box" ))))))))
      (list widget1))))

(defun com-hhub-transaction-compadmin-home ()
  "URL：/hhub/hhubcadindex（推测）。CAD 主页（待审批商品看板）。"
  (with-cad-session-check
    (with-mvc-ui-page "Welcome Company Administrator" #'create-model-for-compadminhome #'create-widgets-for-compadminhome :role :compadmin)))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;com-hhub-transaction-cad-login-action;;;;;;;;;;;;
(defun create-model-for-cadloginaction ()
  "登录提交 model：取 phone+password，调 dod-cad-login 校验。
   成功改 redirectlocation → /hhub/hhubcadindex，失败保持 → /hhub/cad-login.html。
   备注：unless 内的 (and (or null zerop) ...) 同样属于 *任一* 字段非空时才走登录。"
  (let ((params nil)
	(redirectlocation "/hhub/cad-login.html"))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    ;; The person has not yet logged in 
    ;; (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
    (with-hhub-transaction "com-hhub-transaction-cad-login-action" params
      (let  ((phone (hunchentoot:parameter "phone"))
	     (passwd (hunchentoot:parameter "password")))
	(unless (and
		 (or (null phone) (zerop (length phone)))
		 (or (null passwd) (zerop (length passwd))))
	  (if (dod-cad-login :phone phone :password passwd)
	      (setf redirectlocation "/hhub/hhubcadindex")))))
    (function (lambda ()
      redirectlocation))))

(defun com-hhub-transaction-cad-login-action ()
  "URL：/hhub/hhubcadloginaction（推测）。返回登录后跳转 URL 字符串。"
  (let ((uri (with-mvc-redirect-ui #'create-model-for-cadloginaction #'create-widgets-for-genericredirect)))
    (format nil "~A" uri)))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun dod-cad-login (&key phone  password)
  "实际登录核心：用 phone 查 dod-users，校验密码（check-password 用存的 salt）。
   成功且当前会话尚未登录 → start-session、设置 8 小时超时、调用 set-user-session-params 注入会话。
   返回：T 表示登录成功；其他情况返回 nil 并写日志。
   备注：仅按 phone 唯一定位用户，未限定 tenant_id（推测：默认按手机号全局唯一）。"
  (let* ((login-user (car (clsql:select 'dod-users :where [and
				       [= [slot-value 'dod-users 'phone-mobile] phone]]
				       :caching nil :flatp t)))
	 (login-company (if login-user (slot-value login-user 'company)))
	 (pwd (if login-user (slot-value login-user 'password)))
	 (salt (if login-user (slot-value login-user 'salt)))
	 (password-verified (if login-user  (check-password password salt pwd))))
	 
    (unless login-user (hunchentoot:log-message* :info "Company admin user does not exist - ~A" phone))
    (unless password-verified (hunchentoot:log-message* :info "Password not verified for ~A" phone))

    (when (and   
	   login-user
	   password-verified
	   (null (hunchentoot:session-value :login-user-name))) ;; User should not be logged-in in the first place.
      (progn
	(hunchentoot:start-session)
	(setf hunchentoot:*session-max-time* (* 3600 8))
	(set-user-session-params login-company login-user)
	T))))







;;;;;;;;;;;;;;com-hhub-transaction-cad-logout;;;;;;;;;;;;;;;
(defun create-model-for-cadlogout ()
  "登出 model：dod-logout 清掉登录态、remove-session、删除 BusinessSession，重定向到登录页。"
  (let ((params nil)
	(username (get-login-user-name))
	(redirectlocation "/hhub/cad-login.html"))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
    (with-hhub-transaction "com-hhub-transaction-cad-logout" params 
      (progn
	(dod-logout username)
	(when hunchentoot:*session* (hunchentoot:remove-session hunchentoot:*session*))
	(deleteBusinessSession (getBusinessContext *HHUBBUSINESSSERVER* "compadminsite") (hunchentoot:session-value :login-user-business-session-id)) 
	(function (lambda ()
	  redirectlocation))))))

(defun com-hhub-transaction-cad-logout ()
  "URL：/hhub/hhubcadlogout（推测）。先走 model 清会话，再 302 重定向到登录页。"
  (let ((uri (with-mvc-redirect-ui #'create-model-for-cadlogout #'create-widgets-for-genericredirect)))
    (hunchentoot:redirect (format nil "~A" uri))))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun create-model-for-cadproductrejectaction ()
  "Reject Product model：调 reject-product 写状态，跳回 /hhub/hhubcadindex。"
  (let ((params nil)
	(company (get-login-company))
	(redirectlocation "/hhub/hhubcadindex"))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
    (with-hhub-transaction "com-hhub-transaction-cad-product-reject-action" params 
      (let ((id (hunchentoot:parameter "id"))
	    (description (hunchentoot:parameter "description")))
	(reject-product id description company)
	(function (lambda ()
	  redirectlocation))))))

(defun com-hhub-transaction-cad-product-reject-action ()
  "URL：/hhub/hhubcadproductrejectaction（推测）。CAD 拒绝商品上架。"
  (with-cad-session-check
    (let ((uri (with-mvc-redirect-ui #'create-model-for-cadproductrejectaction #'create-widgets-for-genericredirect)))
      (format nil "~A" uri))))



(defun create-model-for-cadproductapproveaction ()
  "Approve Product model：调 approve-product 写状态，跳回 /hhub/hhubcadindex。"
  (let ((params nil)
	(redirectlocation "/hhub/hhubcadindex"))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "rolename" (com-hhub-attribute-role-name) params))
    (with-hhub-transaction "com-hhub-transaction-cad-product-approve-action" params
      (let ((id (hunchentoot:parameter "id"))
	    (description (hunchentoot:parameter "description")))
	(approve-product id description (get-login-company))
	(function (lambda ()
	  redirectlocation))))))

(defun com-hhub-transaction-cad-product-approve-action ()
  "URL：/hhub/hhubcadproductapproveaction（推测）。CAD 批准商品上架。"
  (with-cad-session-check
    (let ((uri (with-mvc-redirect-ui #'create-model-for-cadproductapproveaction #'create-widgets-for-genericredirect)))
      (format nil "~A" uri))))


(defun dod-controller-products-approval-page ()
  :documentation "This controller function is used by the System admin and Company Admin to approve products.
   中文：URL：/hhub/dasproductapprovals（推测）。
         展示本租户 PENDING 商品列表（display-as-tiles + product-card-for-approval）。"
 (with-cad-session-check
   (let ((products (get-products-for-approval (get-login-tenant-id))))
     (with-standard-compadmin-page-v2 "New products approval" 
       (welcomemessage (get-login-user-name))
       (:hr)
       (with-html-div-row
	 (with-html-div-col (:h4 "Pending Product Approvals"))
	 (with-html-div-col :align "right"
 	   (:span :class "badge" (cl-who:str (format nil "~A" (length products))))))
       (:hr)
       (cl-who:str (display-as-tiles products 'product-card-for-approval 'product-box ))))))

(defun dod-controller-vendor-approval-page ()
  :documentation "This controller function is used by the System admin and Company Admin to approve vendors.
   中文：URL：/hhub/hhubvendorapprovalpage（推测）。展示本租户的 PENDING 商家列表。"
 (with-cad-session-check
   (let ((pendingvendors (get-vendors-for-approval (get-login-tenant-id))))
     (with-standard-compadmin-page-v2 "New Vendor approval" 
       (welcomemessage (get-login-user-name))
       (:hr)
       (with-html-div-row
	 (with-html-div-col (:h4 "Pending Vendor Approvals"))
	 (with-html-div-col :align "right"
	   (:span :class "badge" (cl-who:str (format nil "~A" (length pendingvendors))))))
       (:hr)
       (cl-who:str (display-as-tiles pendingvendors 'vendor-card-for-approval "vendor-card" ))))))



(defun vendor-card-for-approval (vendor-instance)
  "渲染单个待审批商家卡片：显示公司名 / 商家名 / 电话 + 'Reject'/'Approve' 两个按钮（带模态框）。
   仅当 approved-flag='N' 且 approval-status='PENDING' 时才输出。"
    (let* ((name (slot-value vendor-instance 'name))
	   (phone (slot-value vendor-instance 'phone))
	   (vendor-id (slot-value vendor-instance 'row-id))
	   ;; (active-flag (slot-value vendor-instance 'active-flag))
	   (approved-flag (slot-value vendor-instance 'approved-flag))
	   (tenant-id (slot-value vendor-instance 'tenant-id))
	   (company (select-company-by-id tenant-id))
	   (company-name (slot-value company 'name))
	   (approval-status (slot-value vendor-instance 'approval-status)))
      (when (and (equal approved-flag "N") (equal approval-status "PENDING"))
	(cl-who:with-html-output (*standard-output* nil)
	  (with-html-div-row
	    (with-html-div-col-12
	      (:h5 (cl-who:str (format nil "~A" company-name)))))
	  (with-html-div-row
	    (:h5 :class "product-name" (cl-who:str (if (> (length name) 30)  (subseq name  0 30) name))))
	  (with-html-div-row
	    (:h5 :class "product-name" (cl-who:str phone)))
	  (with-html-div-row
	    (with-html-div-col-6
	      (:button :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendreject-modal~A" vendor-id)  :href "#"  (:i :class "fa-solid fa-ban") "Reject")
	      (modal-dialog-v2 (format nil "dodvendreject-modal~A" vendor-id) "Reject Vendor" (modal.reject-vendor-html vendor-id)))
	    (with-html-div-col-6
	      (:button :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendaccept-modal~A" vendor-id)  :href "#"  (:i :class "fa-regular fa-thumbs-up") "Approve")
	      (modal-dialog-v2 (format nil "dodvendaccept-modal~A" vendor-id) "Approve Vendor" (modal.approve-vendor-html vendor-id ))))))))



(defun modal.reject-vendor-html (vendor-id)
  "Reject 模态框：单 hidden vendor-id + Reject 按钮，POST hhubvendorrejectaction。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-html-form "form-vendorreject" "hhubvendorrejectaction"
      (:div :class "form-group" :style "display: none"
	    (:input :class "form-control" :name "vendor-id" :value vendor-id :type "text" :readonly T ))
      (:div :class "form-group"
	    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Reject")))))

(defun modal.approve-vendor-html (vendor-id)
  "Approve 模态框：单 hidden vendor-id + Approve 按钮，POST hhubvendorapproveaction。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-html-form "form-vendorreject" "hhubvendorapproveaction"
      (:div :class "form-group" :style "display: none"
	    (:input :class "form-control" :name "vendor-id" :value vendor-id :type "text" :readonly T ))
      (:div :class "form-group"
	    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Approve")))))



      
