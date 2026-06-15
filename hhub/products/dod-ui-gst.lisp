;;; dod-ui-gst.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：products —— GST HSN 税码 PAP 后台
;;;; 分层：UI（控制器 + CL-WHO 模板）
;;;; 文件：hhub/products/dod-ui-gst.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：GST HSN 税码维护界面（仅超级管理员可访问）：
;;;;   - 列表页（含搜索）
;;;;   - 新增 / 编辑 模态对话框
;;;;   - 单条搜索结果片段
;;;; 全部页面通过 with-hhub-transaction 走 PEP/PDP 鉴权链路。
;;;;
;;;; 主要导出（com-hhub-transaction-* 即 ABAC 事务，URL 在 PAP 表中绑定）：
;;;;   com-hhub-transaction-gst-hsn-codes-page             — /hhub/gsthsncodes 列表页
;;;;   com-hhub-transaction-search-gst-hsn-codes-action    — 列表页 livesearch 后端
;;;;   com-hhub-transaction-create-gst-hsn-code-action     — 新增提交动作
;;;;   com-hhub-transaction-update-gst-hsn-code-action     — 修改提交动作
;;;;   com-hhub-transaction-create-gst-hsn-code-dialog     — Add/Edit 对话框 fragment
;;;;   create-model-* / create-widgets-*                   — MVC 三段：构造 model / widgets
;;;;   display-gst-hsn-code-row / RenderListViewHTML       — 列表渲染
;;;;
;;;; 关联：
;;;;   上游：浏览器（POST/GET /hhub/gsthsncodes 等）
;;;;   下游：products/dod-bl-gst.lisp（Adapter/Service）、core/dod-ui-utl.lisp（PEP 宏 / MVC 框架）
;;;; ============================================================================

(in-package :nstores)

(defun gst-hsn-codes-search-html ()
  "渲染列表页顶部的 livesearch 输入框（异步绑定到 hsncodeslivesearch 动作）。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
	  (:div :id "custom-search-input"
		(:div :class "input-group col-xs-12 col-sm-6 col-md-6 col-lg-6"
		      (with-html-search-form "idsyssearchhsncodes" "syssearchhsncodes" "idhsncodeslivesearch" "hsncodeslivesearch" "searchhsncodesaction" "onkeyupsearchform1event();" "Search for an GST HSN codes"
			(submitsearchform1event-js "#idhsncodeslivesearch" "#hsncodeslivesearchresult")))))))


(defun com-hhub-transaction-gst-hsn-codes-page ()
  "URL：/hhub/gsthsncodes（推测，依命名约定）。
   控制器：在 OPR 会话保护 + role=:superadmin 校验下渲染 HSN 列表 MVC 页面。"
  (with-opr-session-check
    (with-mvc-ui-page "GST HSN Codes" #'create-model-for-showgsthsncodes #'create-widgets-for-showgsthsncodes :role :superadmin)))

(defun create-model-for-showgsthsncodes ()
  "构造列表页所需 ViewModel：
     - 通过 GSTHSNCodesAdapter → ProcessReadAllRequest 拉取全部 HSN（系统租户）；
     - 用 Presenter 把 ResponseModel 转 ViewModel 列表；
     - 包在 with-hhub-transaction 内由 PDP 鉴权（事务名 com-hhub-transaction-gst-hsn-codes-page）。
   返回值（多值）：viewallmodel htmlview username。"
  (let* ((company (get-login-company))
	 (username (get-login-user-name))
	 (gsthsncodespresenter (make-instance 'GSTHSNCodesPresenter))
	 (gsthsncodesrequestmodel (make-instance 'GSTHSNCodesRequestModel
						 :company company))
	 (gsthsncodesadapter (make-instance 'GSTHSNCodesAdapter))
	 (gsthsncodesobjlst (processreadallrequest gsthsncodesadapter gsthsncodesrequestmodel))
	 (gsthsncodesresponsemodellist (processresponselist gsthsncodesadapter gsthsncodesobjlst))
	 (viewallmodel (CreateAllViewModel gsthsncodespresenter gsthsncodesresponsemodellist))
	 (htmlview (make-instance 'GSTHSNCodesHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-gst-hsn-codes-page" params 
      (function (lambda ()
	(values viewallmodel htmlview username))))))

(defun create-widgets-for-showgsthsncodes (modelfunc)
  "MVC 视图：渲染欢迎区 + 搜索框 + 表格 + 'Add HSN Code' 按钮（带模态对话框）。
   返回 (widget1 widget2) 的列表，由上层框架顺序输出。"
  ;; this is the view.
  (multiple-value-bind (viewallmodel htmlview username) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (:div :id "row"
			     (:div :id "col-xs-6" 
				   (:h3 "Welcome " (cl-who:str (format nil "~A" username)))))
		       (gst-hsn-codes-search-html)
		       (:hr)))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (:h4 "Showing records for GST HSN Codes."))
		       (:div :id "hsncodeslivesearchresult" 
			     (:div :class "row"
				   (:div :class"col-xs-6"
					 (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#edithsncode-modal" "Add GST HSN Code")
					 (modal-dialog "edithsncode-modal" "Add/Edit GST HSN CODE" (com-hhub-transaction-create-gst-hsn-code-dialog)))
				   (:div :class "col-xs-6" :align "right" 
					 (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
			     (:hr)
			     (cl-who:str (RenderListViewHTML htmlview viewallmodel))))))))
      (list widget1 widget2))))


(defun create-widgets-for-searchhsncodes (modelfunc)
  "搜索结果片段：列出匹配 HSN 与 Add 按钮，以 livesearch 异步替换原列表 div。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (:div :class "row"
			     (:div :class"col-xs-6"
				   (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#edithsncode-modal" "Add GST HSN Code")
				   (modal-dialog "edithsncode-modal" "Add/Edit GST HSN CODE" (com-hhub-transaction-create-gst-hsn-code-dialog)))
			     (:div :class "col-xs-6" :align "right" 
				   (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
		       (:hr)
		       (RenderListViewHTML htmlview viewallmodel))))))
      (list widget1))))


(defmethod RenderListViewHTML ((htmlview GSTHSNCodesHTMLView) viewmodellist)
  "把 ViewModel 列表渲染成 7 列表格（HSN/4 Digit/描述/SGST/CGST/IGST/Cess）。
   每行通过 display-gst-hsn-code-row 渲染。"
  (when viewmodellist
    (display-as-table (list "HSN Code" "4 Digit Code" "Description" "SGST" "CGST" "IGST" "Compensation Cess") viewmodellist 'display-gst-hsn-code-row)))

(defun create-model-for-searchhsncodes ()
  "构造 livesearch model：从请求参数取 hsncodeslivesearch 作为 SearchRequestModel.hsncode，
   走 ProcessReadAllRequest（搜索版 doreadall 用前缀 LIKE）。
   PEP 事务名 com-hhub-transaction-search-gst-hsn-codes-action。"
  (let* ((search-clause (hunchentoot:parameter "hsncodeslivesearch"))
	 (company (get-login-company))
	 (gsthsncodespresenter (make-instance 'GSTHSNCodesPresenter))
	 (gsthsncodesrequestmodel (make-instance 'GSTHSNCodesSearchRequestModel
						 :hsncode search-clause
						 :company company))
	 (gsthsncodesadapter (make-instance 'GSTHSNCodesAdapter))
	 (gsthsncodesobjlst (processreadallrequest gsthsncodesadapter gsthsncodesrequestmodel))
	 (gsthsncodesresponsemodellist (processresponselist gsthsncodesadapter gsthsncodesobjlst))
	 (viewallmodel (CreateAllViewModel gsthsncodespresenter gsthsncodesresponsemodellist))
	 (htmlview (make-instance 'GSTHSNCodesHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-search-gst-hsn-codes-action" params 
      (function (lambda ()
	(values viewallmodel htmlview))))))



(defun com-hhub-transaction-search-gst-hsn-codes-action ()
  "URL：/hhub/searchhsncodesaction（livesearch ajax 端点，推测）。
   把 widgets 串联输出 HTML 字符串返回给客户端 div 替换。"
  (let* ((modelfunc (funcall #'create-model-for-searchhsncodes))
	 (widgets (funcall #'create-widgets-for-searchhsncodes modelfunc)))
    (cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
      (logiamhere (format nil "length of search widgets is ~d" (length widgets)))
      (loop for widget in widgets do
	(cl-who:str (funcall widget))))))


(defun com-hhub-transaction-update-gst-hsn-code-action ()
  "URL：/hhub/updatehsncodeaction（推测）。
   提交 HSN 编辑表单，with-mvc-redirect-ui 完成持久化后跳回 /hhub/gsthsncodes。"
  (with-opr-session-check
    (let ((url (with-mvc-redirect-ui  #'create-model-for-updategsthsncode #'create-widgets-for-updategsthsncode)))
      (format nil "~A" url))))

(defun create-widgets-for-updategsthsncode (modelfunc)
  "更新动作的 widget 通用化：直接复用 create-widgets-for-genericredirect。"
  (funcall #'create-widgets-for-genericredirect modelfunc))


(defun create-model-for-updategsthsncode ()
  "更新 model：把表单字段（hsncode/4digit/description/sgst/cgst/igst/compcess）解析后
   构造 RequestModel，通过 ProcessUpdateRequest 调 doupdate 写库。
   返回：跳转 URL 与更新后的 domain 对象。
   出错时抛 hhub-business-function-error。"
  (let* ((code (hunchentoot:parameter "hsncode"))
	 (code4digit (hunchentoot:parameter "hsncode4digit"))
	 (description (hunchentoot:parameter "description"))
	 (sgst-tax (float (with-input-from-string (in (hunchentoot:parameter "sgst"))
		   (read in))))
	 (cgst-tax (float (with-input-from-string (in (hunchentoot:parameter "cgst"))
		   (read in))))
	 (igst-tax (float (with-input-from-string (in (hunchentoot:parameter "igst"))
		   (read in))))
	 (comp-cess-tax (float (with-input-from-string (in (hunchentoot:parameter "compcess"))
		   (read in))))
	 (company (get-login-company))
	 (requestmodel (make-instance 'GSTHSNCodesRequestModel
					 :hsncode code
					 :hsncode4digit code4digit
					 :description description
					 :sgst sgst-tax
					 :cgst cgst-tax
					 :igst igst-tax
					 :compcess comp-cess-tax
					 :company company))
	 (gsthsncodeadapter (make-instance 'GSTHSNCodesAdapter))
	 (redirectlocation  "/hhub/gsthsncodes")
	 (params nil))
    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-update-gst-hsn-code-action" params 
      (handler-case 
	  (let ((gsthsncodeobj (ProcessUpdateRequest gsthsncodeadapter requestmodel)))
	    (function (lambda ()
	      (values redirectlocation gsthsncodeobj))))
	(error (c)
	       (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c)))))))



(defun com-hhub-transaction-create-gst-hsn-code-action ()
  "URL：/hhub/createhsncodeaction（推测）。
   提交新增 HSN 表单，写库后跳转回列表页。"
  (with-opr-session-check
    (let ((url (with-mvc-redirect-ui  #'create-model-for-creategsthsncode #'create-widgets-for-creategsthsncode)))
      (format nil "~A" url))))




(defun create-model-for-creategsthsncode ()
  "创建 model：把表单参数构造 RequestModel，调用 ProcessCreateRequest → doCreate。
   完成后返回跳转 URL '/hhub/gsthsncodes' 与新创建对象。"
  (let* ((code (hunchentoot:parameter "hsncode"))
	 (code4digit (hunchentoot:parameter "hsncode4digit"))
	 (description (hunchentoot:parameter "description"))
	 (sgst-tax (float (with-input-from-string (in (hunchentoot:parameter "sgst"))
		   (read in))))
	 (cgst-tax (float (with-input-from-string (in (hunchentoot:parameter "cgst"))
		   (read in))))
	 (igst-tax (float (with-input-from-string (in (hunchentoot:parameter "igst"))
		   (read in))))
	 (comp-cess-tax (float (with-input-from-string (in (hunchentoot:parameter "compcess"))
		   (read in))))
	 (company (get-login-company))
	 (requestmodel (make-instance 'GSTHSNCodesRequestModel
					 :hsncode code
					 :hsncode4digit code4digit
					 :description description
					 :sgst sgst-tax
					 :cgst cgst-tax
					 :igst igst-tax
					 :compcess comp-cess-tax
					 :company company))
	 (gsthsncodeadapter (make-instance 'GSTHSNCodesAdapter))
	 (redirectlocation  "/hhub/gsthsncodes")
	 (params nil))
    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-create-gst-hsn-code-action" params 
      (handler-case 
	  (let ((gsthsncodeobj (ProcessCreateRequest gsthsncodeadapter requestmodel)))
	    ;; Create the GST HSN Code object if not present. 
	    (function (lambda ()
	      (values redirectlocation gsthsncodeobj))))
	(error (c)
	  (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c)))))))



(defun create-widgets-for-creategsthsncode (modelfunc)
  "创建动作 widget：复用通用 redirect widget。"
  (funcall #'create-widgets-for-genericredirect modelfunc))


(defun display-gst-hsn-code-row (gst-hsn-code &rest arguments)
  "渲染单行 HSN：7 个字段 td + 编辑按钮（弹出 #edithsncode-modal<HSN> 模态框）。"
  (declare (ignore arguments))
  (with-slots (hsncode hsncode4digit description sgst cgst igst compcess) gst-hsn-code 
    (cl-who:with-html-output (*standard-output* nil)
      (:td  :height "10px" (cl-who:str hsncode))
      (:td  :height "10px" (cl-who:str hsncode4digit))
      (:td  :height "10px" (cl-who:str description))
      (:td  :height "10px" (cl-who:str sgst))
      (:td  :height "10px" (cl-who:str cgst))
      (:td  :height "10px" (cl-who:str igst))
      (:td  :height "10px" (cl-who:str compcess))
      (:td  :height "10px" 
	    (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target (format nil "#edithsncode-modal~A" hsncode) (:i :class "fa-solid fa-pencil"))
	    (modal-dialog (format nil "edithsncode-modal~A" hsncode) "Add/Edit GST HSN CODE" (com-hhub-transaction-create-gst-hsn-code-dialog gst-hsn-code))))))



(defun com-hhub-transaction-create-gst-hsn-code-dialog (&optional hsncodeobj)
  "Add/Edit HSN 模态对话框 fragment。
   若传入 hsncodeobj 则预填表单（编辑模式，提交到 updatehsncodeaction）；
   否则空表单（新增模式，提交到 createhsncodeaction）。
   字段：hsncode / hsncode4digit / description / sgst / cgst / igst / compcess。"
  (let* ((code  (if hsncodeobj (slot-value hsncodeobj 'hsncode)))
	 (code-4digit  (if hsncodeobj (slot-value hsncodeobj 'hsncode4digit)))
	 (description  (if hsncodeobj (slot-value hsncodeobj 'description)))
	 (cgst  (if hsncodeobj (slot-value hsncodeobj 'cgst)))
	 (sgst  (if hsncodeobj (slot-value hsncodeobj 'sgst)))
	 (igst  (if hsncodeobj (slot-value hsncodeobj 'igst)))
	 (comp-cess  (if hsncodeobj (slot-value hsncodeobj 'compcess))))
	    
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form (format nil "form-addhsncode~A" code)  (if hsncodeobj "updatehsncodeaction" "createhsncodeaction")
		    (:img :class "profile-img" :src "/img/logo.png" :alt "")
		    (:div :class "form-group"
			  (:input :class "form-control" :name "hsncode" :maxlength "8"  :value  code :placeholder "HSN Code  ( max 6 characters) " :type "text" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :name "hsncode4digit" :maxlength "4"  :value (cl-who:str code-4digit) :placeholder "HSN Code  ( max 4 characters) " :type "text" ))
		    (:div :class "form-group"
			  (:label :for "description")
			  (:textarea :class "form-control" :name "description"  :placeholder "Description ( max 500 characters) "  :rows "5" :onkeyup "countChar(this, 500)" (cl-who:str description)))
		    (:div :class "form-group" :id "charcount")
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value sgst :placeholder "SGST"  :name "sgst" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value cgst :placeholder "CGST"  :name "cgst" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value igst :placeholder "IGST"  :name "igst" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value comp-cess :placeholder "Compensation Cess"  :name "compcess" ))
		    (:div :class "form-group"
			  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))
