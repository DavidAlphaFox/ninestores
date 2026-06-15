;;; nst-ui-OrderItem.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*
;;;; ============================================================================
;;;; 模块：order 订单 —— 行项 UI / 控制器（新 nst-* DDD/Hexagonal）
;;;; 分层：UI（控制器 + CL-WHO 模板 + Presenter 装配）
;;;; 文件：hhub/order/nst-ui-OrderItem.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：订单行项的 Web UI / 控制器层。属于六边形管线的 UI 端：
;;;;   - 列表/搜索：com-hhub-transaction-show-OrderItems-page /
;;;;     com-hhub-transaction-search-OrderItem-action
;;;;   - 创建/更新：com-hhub-transaction-create-OrderItem-action /
;;;;     com-hhub-transaction-update-OrderItem-action
;;;;   - 表单弹窗：com-hhub-transaction-create-OrderItem-dialog
;;;;   - 行渲染：display-OrderItem-row
;;;;   - List 视图渲染：RenderListViewHTML（OrderItemHTMLView 特化）
;;;;
;;;; 备注：本文件存在若干符号不一致（OrderItems vs OrderItem），属于代码生成模板
;;;;       残留（推测）—— 例如 show 用 OrderItemsAdapter，搜索/更新用 OrderItemAdapter；
;;;;       同样 widgets-for-showOrderItem 与 model-for-showOrderItems 名字不严格匹配。
;;;;       注释只如实说明，不修改代码。
;;;;
;;;; 关联：
;;;;   上游使用方：客户/卖家订单后台路由
;;;;   下游依赖：order/nst-bl-OrderItem.lisp、core PEP 宏 with-hhub-transaction
;;;; ============================================================================

(in-package :nstores)

(defun OrderItems-search-html ()
  :description "This will create a html search box widget.
   中文：渲染顶部搜索框。表单 action='searchOrderItemsaction'，结果 div 为 #OrderItemslivesearchresult。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
	  (:div :id "custom-search-input"
		(:div :class "input-group col-xs-12 col-sm-6 col-md-6 col-lg-6"
		      (with-html-search-form "idsyssearchOrderItems" "syssearchOrderItems" "idOrderItemslivesearch" "OrderItemslivesearch" "searchOrderItemsaction" "onkeyupsearchform1event();" "Search for an OrderItems"
			(submitsearchform1event-js "#idOrderItemslivesearch" "#OrderItemslivesearchresult")))))))

(defun com-hhub-transaction-show-OrderItems-page ()
  :description "This is a show list page for all the OrderItems entities.
   中文：客户视角行项列表 PEP 入口。会话：with-cust-session-check。"
  (with-cust-session-check ;; delete if not needed. 
    (with-mvc-ui-page "OrderItems" #'create-model-for-showOrderItems #'create-widgets-for-showOrderItems :role :customer ))) ;; keep only one role, delete reset. 

(defun create-model-for-showOrderItems ()
  :description "This is a model function which will create a model to show OrderItems entities.
   中文：行项列表 model：构造 RequestModel/Adapter/Presenter，processreadallrequest 获取
   行项列表 → CreateAllViewModel；with-hhub-transaction PEP 鉴权。
   备注：使用 'OrderItemsAdapter' / 'OrderItemsRequestModel' / 'OrderItemsPresenter'，
   而 nst-dal-OrderItem.lisp 实际定义的类名是 'OrderItemAdapter'（无 s）—— 推测：
   此模板代码尚未与现有类名对齐，运行此控制器会报 'no such class'。"
  (let* ((company (get-login-company))
	 (username (get-login-user-name))
	 (presenterobj (make-instance 'OrderItemsPresenter))
	 (requestmodelobj (make-instance 'OrderItemsRequestModel
					 :company company))
	 (adapterobj (make-instance 'OrderItemsAdapter))
	 (objlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj objlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'OrderItemHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-OrderItem-page" params 
      (function (lambda ()
	(values viewallmodel htmlview username))))))

(defun create-widgets-for-showOrderItem (modelfunc)
 :description "This is the view/widget function for show OrderItem entities.
   中文：列表 widgets：面包屑 + 搜索框 + 'Create OrderItem' 链接 + 列表 + 表单提交 JS。
   备注：函数名是 'showOrderItem' 单数，但被 'showOrderItems' 控制器经 with-mvc-ui-page 间接调用 ——
   命名不一致（推测：模板生成残留）。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-vendor-breadcrumb)
		       (OrderItem-search-html)
			 (:hr)))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (:h4 "Showing records for OrderItem."))
		       (:div :id "OrderItemlivesearchresult" 
			     (:div :class "row"
				   (:div :class"col-xs-6"
					 (:a :href "/hhub/addOrderItem" (:i :class "fa-solid fa-plus") "&nbsp;&nbsp;Create OrderItem"))
				   (:div :class "col-xs-6" :align "right" 
					 (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
			     (:hr)
			     (cl-who:str (RenderListViewHTML htmlview viewallmodel)))))))
	  (widget3 (function (lambda ()
		     (submitformevent-js "#OrderItemlivesearchresult")))))
      (list widget1 widget2 widget3))))

(defun create-widgets-for-updateOrderItem (modelfunc)
:description "This is a widgets function for update OrderItem entity.
   中文：更新行项后通用重定向 widgets。"
  (funcall #'create-widgets-for-genericredirect modelfunc))

(defmethod RenderListViewHTML ((htmlview OrderItemHTMLView) viewmodellist)
  :description "This is a HTML View rendering function for OrderItem entities, which will display each OrderItem entity in a row.
   中文：行项表格渲染。表头列长度（38 列）含大量 %N% 占位（推测：模板生成器输出，
   实际 ViewModel 没有这些字段，仅为占位列名）。"
  (when viewmodellist
    (display-as-table (list "row-id" "order" "product" "vendor" "prd-qty" "unit-price" "disc-rate" "cgst" "sgst" "igst" "addl-tax1-rate" "comments" "fulfilled" "status" "deleted-state" "company" "%16%" "%17%" "%18%" "%19%" "%20%" "%21%" "%22%" "%23%" "%24%" "%25%" "%26%" "%27%" "%28%" "%29%" "%30%" "%31%" "%32%" "%33%" "%34%" "%35%" "%36%" "%37%") viewmodellist 'display-OrderItem-row)))

(defun create-model-for-searchOrderItem ()
  :description "This is a model function for search OrderItem entities/entity.
   中文：搜索 model：把 livesearch 输入文本作为 :field1 装到 OrderItemSearchRequestModel。"
  (let* ((search-clause (hunchentoot:parameter "OrderItemlivesearch"))
	 (company (get-login-company))
	 (presenterobj (make-instance 'OrderItemPresenter))
	 (requestmodelobj (make-instance 'OrderItemSearchRequestModel
						 :field1 search-clause
						 :company company))
	 (adapterobj (make-instance 'OrderItemAdapter))
	 (domainobjlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj domainobjlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'OrderItemHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-search-OrderItem-action" params 
      (function (lambda ()
	(values viewallmodel htmlview))))))



(defun com-hhub-transaction-search-OrderItem-action ()
  :description "This is a MVC function to search action for OrderItem entities/entity.
   中文：搜索动作：调 model + widgets 拼字符串返回（livesearch 走 AJAX）。"
  (let* ((modelfunc (funcall #'create-model-for-searchOrderItem))
	 (widgets (funcall #'create-widgets-for-searchOrderItem modelfunc)))
    (cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
      (loop for widget in widgets do
	(cl-who:str (funcall widget))))))

(defun create-model-for-updateOrderItem ()
  :description "This is a model function for update OrderItem entity.
   中文：更新行项 model：从 hunchentoot 取所有字段（unit-price/disc-rate 走 read 解析浮点），
   构造 RequestModel 调 ProcessUpdateRequest；handler-case 兜底。
   重定向：/hhub/OrderItem。"
  (let* ((row-id (hunchentoot:parameter "row-id"))
	 (order (hunchentoot:parameter "order"))
	 (product (hunchentoot:parameter "product"))
	 (vendor (hunchentoot:parameter "vendor"))
	 (prd-qty (hunchentoot:parameter "prd-qty"))
	 (unit-price (float (with-input-from-string (in (hunchentoot:parameter "unit-price"))
			      (read in))))
	 (disc-rate (float (with-input-from-string (in (hunchentoot:parameter "disc-rate"))
		   (read in))))
	 (cgst (hunchentoot:parameter "cgst"))
	 (sgst (hunchentoot:parameter "sgst"))
	 (igst (hunchentoot:parameter "igst"))
	 (addl-tax1-rate (hunchentoot:parameter "addl-tax1-rate"))
	 (comments (hunchentoot:parameter "comments"))
	 (fulfilled (hunchentoot:parameter "fulfilled"))
	 (status (hunchentoot:parameter "status"))
	 (deleted-state (hunchentoot:parameter "deleted-state"))
	 (company (get-login-company)) ;; or get ABAC subject specific login company function. 
	 (requestmodel (make-instance 'OrderItemRequestModel
					 :row-id row-id
					 :order order
					 :product product
					 :vendor vendor
					 :prd-qty prd-qty
					 :unit-price unit-price
					 :disc-rate disc-rate
					 :cgst cgst
					 :sgst sgst
					 :igst igst
					 :addl-tax1-rate addl-tax1-rate
					 :comments comments
					 :fulfilled fulfilled
					 :status status
					 :deleted-state deleted-state
					 :company company))
	 (adapterobj (make-instance 'OrderItemAdapter))
	 (redirectlocation  "/hhub/OrderItem")
	 (params nil))
    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-update-OrderItem-action" params 
      (handler-case 
	  (let ((domainobj (ProcessUpdateRequest adapterobj requestmodel)))
	    (function (lambda ()
	      (values redirectlocation domainobj))))
	(error (c)
	  (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c)))))))


(defun create-model-for-createOrderItem ()
  :description "This is a create model function for creating a OrderItem entity.
   中文：创建行项 model：与 update 同样从 hunchentoot 取参数，构造 RequestModel 后
   ProcessCreateRequest。备注：:company 在 :initargs 中出现两次（模板残留，无害）。"
  (let* ((row-id (hunchentoot:parameter "row-id"))
	 (order (hunchentoot:parameter "order"))
	 (product (hunchentoot:parameter "product"))
	 (vendor (hunchentoot:parameter "vendor"))
	 (prd-qty (hunchentoot:parameter "prd-qty"))
	 (unit-price (float (with-input-from-string (in (hunchentoot:parameter "unit-price"))
			      (read in))))
	 (disc-rate (float (with-input-from-string (in (hunchentoot:parameter "disc-rate"))
		   (read in))))
	 (cgst (hunchentoot:parameter "cgst"))
	 (sgst (hunchentoot:parameter "sgst"))
	 (igst (hunchentoot:parameter "igst"))
	 (addl-tax1-rate (hunchentoot:parameter "addl-tax1-rate"))
	 (comments (hunchentoot:parameter "comments"))
	 (fulfilled (hunchentoot:parameter "fulfilled"))
	 (status (hunchentoot:parameter "status"))
	 (deleted-state (hunchentoot:parameter "deleted-state"))
	 (company (get-login-company)) ;; or get ABAC subject specific login company function. 
	 (requestmodel (make-instance 'OrderItemRequestModel
					 :row-id row-id
					 :order order
					 :product product
					 :vendor vendor
					 :prd-qty prd-qty
					 :unit-price unit-price
					 :disc-rate disc-rate
					 :cgst cgst
					 :sgst sgst
					 :igst igst
					 :addl-tax1-rate addl-tax1-rate
					 :comments comments
					 :fulfilled fulfilled
					 :status status
					 :deleted-state deleted-state
					 :company company
					 :company company))
	 (adapterobj (make-instance 'OrderItemAdapter))
	 (redirectlocation  "/hhub/OrderItem")
	 (params nil))
    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-create-OrderItem-action" params 
      (handler-case 
	  (let ((domainobj (ProcessCreateRequest adapterobj requestmodel)))
	    ;; Create the GST HSN Code object if not present. 
	    (function (lambda ()
	      (values redirectlocation domainobj))))
	(error (c)
	  (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c)))))))

(defun com-hhub-transaction-create-OrderItem-dialog (&optional domainobj)
  :description "This function creates a dialog to create OrderItem entity.
   中文：创建/编辑行项的弹窗表单。每个字段一个 input。无 domainobj 时 action='createOrderItemaction'，
   有 domainobj 时 action='updateOrderItemaction'。备注：表单含全部内部字段（含 deleted-state /
   fulfilled / company），属于模板自动生成的样式，业务上是否合适需要 review。"
  (let* ((row-id  (if domainobj (slot-value domainobj 'row-id)))
	 (order  (if domainobj (slot-value domainobj 'order)))
	 (product  (if domainobj (slot-value domainobj 'product)))
	 (vendor  (if domainobj (slot-value domainobj 'vendor)))
	 (prd-qty  (if domainobj (slot-value domainobj 'prd-qty)))
	 (unit-price  (if domainobj (slot-value domainobj 'unit-price)))
	 (disc-rate  (if domainobj (slot-value domainobj 'disc-rate)))
	 (cgst  (if domainobj (slot-value domainobj 'cgst)))
	 (sgst  (if domainobj (slot-value domainobj 'sgst)))
	 (igst  (if domainobj (slot-value domainobj 'igst)))
	 (addl-tax1-rate  (if domainobj (slot-value domainobj 'addl-tax1-rate)))
	 (comments  (if domainobj (slot-value domainobj 'comments)))
	 (fulfilled  (if domainobj (slot-value domainobj 'fulfilled)))
	 (status  (if domainobj (slot-value domainobj 'status)))
	 (deleted-state  (if domainobj (slot-value domainobj 'deleted-state)))
	 (company  (if domainobj (slot-value domainobj 'company))))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form (format nil "form-addOrderItem~A" row-id)  (if domainobj "updateOrderItemaction" "createOrderItemaction")
		    (:img :class "profile-img" :src "/img/logo.png" :alt "")
		    (:div :class "form-group"
			  (:input :class "form-control" :name "row-id" :maxlength "20"  :value  row-id :placeholder "OrderItem (max 20 characters) " :type "text" ))
		    
		    (:div :class "form-group" :id "charcount")
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value order :placeholder "order"  :name "order" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value product :placeholder "product"  :name "product" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value vendor :placeholder "vendor"  :name "vendor" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value prd-qty :placeholder "prd-qty"  :name "prd-qty" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value unit-price :placeholder "unit-price"  :name "unit-price" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value disc-rate :placeholder "disc-rate"  :name "disc-rate" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value cgst :placeholder "cgst"  :name "cgst" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value sgst :placeholder "sgst"  :name "sgst" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value igst :placeholder "igst"  :name "igst" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value addl-tax1-rate :placeholder "addl-tax1-rate"  :name "addl-tax1-rate" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value comments :placeholder "comments"  :name "comments" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value fulfilled :placeholder "fulfilled"  :name "fulfilled" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value status :placeholder "status"  :name "status" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value deleted-state :placeholder "deleted-state"  :name "deleted-state" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value company :placeholder "company"  :name "company" ))
		    (:div :class "form-group"
			  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))





(defun create-widgets-for-createOrderItem (modelfunc)
  :description "This is a create widget function for OrderItem entity.
   中文：创建后通用 redirect widgets。"
  (funcall #'create-widgets-for-genericredirect modelfunc))




(defun create-widgets-for-searchOrderItem (modelfunc)
  :description "This is a widget function for search OrderItem entities.
   中文：搜索结果 widgets：'Add OrderItem' 按钮 + Bootstrap modal 编辑弹窗 + 行项表格。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (:div :class "row"
			     (:div :class"col-xs-6"
				   (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target "#editOrderItem-modal" "Add OrderItem")
				   (modal-dialog "editOrderItem-modal" "Add/Edit OrderItem" (com-hhub-transaction-create-OrderItem-dialog)))
			     (:div :class "col-xs-6" :align "right" 
				   (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
		       (:hr)
		       (RenderListViewHTML htmlview viewallmodel))))))
      (list widget1))))



 
(defun display-OrderItem-row (OrderItem)
  :description "This function has HTML row code for OrderItem entity row.
   中文：单行 <td> 渲染：所有字段平铺成 16+ 列，最后一列两个 modal-dialog（v2 + v1）打开编辑弹窗。
   备注：同一 row-id 下挂了两个 modal（modal-dialog-v2 + modal-dialog），容易冲突 ——
   推测：模板转换期间残留，运行实例上以 v2 为准。"
  (with-slots (row-id order product vendor prd-qty unit-price disc-rate cgst sgst igst addl-tax1-rate comments fulfilled status deleted-state company %16% %17% %18% %19% %20% %21% %22% %23% %24% %25% %26% %27% %28% %29% %30% %31% %32% %33% %34% %35% %36% %37%) OrderItem 
    (cl-who:with-html-output (*standard-output* nil)
      (:td  :height "10px" (cl-who:str row-id))
      (:td  :height "10px" (cl-who:str order))
      (:td  :height "10px" (cl-who:str product))
      (:td  :height "10px" (cl-who:str vendor))
      (:td  :height "10px" (cl-who:str prd-qty))
      (:td  :height "10px" (cl-who:str unit-price))
      (:td  :height "10px" (cl-who:str disc-rate))
      (:td  :height "10px" (cl-who:str cgst))
      (:td  :height "10px" (cl-who:str sgst))
      (:td  :height "10px" (cl-who:str igst))
      (:td  :height "10px" (cl-who:str addl-tax1-rate))
      (:td  :height "10px" (cl-who:str comments))
      (:td  :height "10px" (cl-who:str fulfilled))
      (:td  :height "10px" (cl-who:str status))
      (:td  :height "10px" (cl-who:str deleted-state))
      (:td  :height "10px" (cl-who:str company))
      (:td  :height "10px" 
	    (:button :type "button" :class "btn btn-primary" :data-toggle "modal" :data-target (format nil "#editOrderItem-modal~A" row-id) (:i :class "fa-solid fa-pencil"))
	    (modal-dialog-v2 (format nil "editOrderItem-modal~A" row-id) (cl-who:str (format nil "Add/Edit OrderItem " )) (com-hhub-transaction-create-OrderItem-dialog OrderItem))
	    (modal-dialog (format nil "editOrderItem-modal~A" row-id) "Add/Edit OrderItem" (com-hhub-transaction-create-OrderItem-dialog OrderItem))))))


(defun com-hhub-transaction-update-OrderItem-action ()
  :description "This is the MVC function to update action for OrderItem entity.
   中文：更新行项 PEP 入口。会话：with-cust-session-check。返回：重定向 URL。"
  (with-cust-session-check ;; delete if not needed. 
    (let ((url (with-mvc-redirect-ui  #'create-model-for-updateOrderItem #'create-widgets-for-updateOrderItem)))
      (format nil "~A" url))))


(defun com-hhub-transaction-create-OrderItem-action ()
  :description "This is a MVC function for create OrderItem entity.
   中文：创建行项 PEP 入口。会话：with-cust-session-check。"
  (with-cust-session-check ;; delete if not needed. 
    (let ((url (with-mvc-redirect-ui  #'create-model-for-createOrderItem #'create-widgets-for-createOrderItem)))
      (format nil "~A" url))))









