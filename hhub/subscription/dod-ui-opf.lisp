;; -*- mode: common lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：subscription 周期订单（订阅）
;;;; 分层：UI（控制器 + CL-WHO 模板）
;;;; 文件：hhub/subscription/dod-ui-opf.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：客户端"我的订阅"页面控制器与渲染。基于 with-mvc-ui-page 的 MVC 三件套
;;;;       （model / component / page）展示订阅列表，并提供删除订阅的模态框。
;;;;
;;;; 主要导出：
;;;;   dod-controller-customer-subscriptions   — 入口控制器（要求客户会话）
;;;;   create-model-for-custordersubs          — 构造 model（取自 session 缓存）
;;;;   create-ui-for-custordersubs             — 渲染 UI page
;;;;   customer-subscriptions-{header-top,table}-widget / -component / -page
;;;;   cust-opf-as-row                         — 订阅在表格中的一行渲染器
;;;;   modal.delete-subscription               — 删除确认模态框
;;;;
;;;; 关联：
;;;;   上游使用方：客户主导航中的 "My Subscriptions"（推测路由名 dodcustsubs 或类似）
;;;;   下游依赖：subscription/dod-bl-opf.lisp（业务层）、core 的 with-mvc-ui-page、
;;;;             with-cust-session-check、display-as-table 等模板组件
;;;; ============================================================================

(in-package :nstores)

(defun dod-controller-customer-subscriptions ()
  "URL 控制器：渲染客户的"我的订阅"页面。
   要求：已登录客户会话（with-cust-session-check）。
   渲染：通过 MVC 框架，model 从 session 缓存读、view 调用 create-ui-for-custordersubs。"
  (with-cust-session-check
    (with-mvc-ui-page "Customer Order Subscriptions" #'create-model-for-custordersubs #'create-ui-for-custordersubs :role :customer)))


(defun create-model-for-custordersubs ()
  "构造模型函数：从 session 取缓存的订阅列表 :login-cusopf-cache 与表头。
   返回：lambda，调用后 (values dodorderprefs header)。"
  (let ((dodorderprefs (hunchentoot:session-value :login-cusopf-cache))
	(header (list  "Product"  "Day"  "Qty" "Qty Per Unit" "Actions")))
    (function (lambda ()
      (values dodorderprefs header)))))

(defun customer-subscriptions-header-top-widget ()
  "页面顶部 widget：标题"My Subscriptions"+ Shop Now 按钮（跳到 dodcustindex）。"
  (make-ui-widget (lambda ()
		    (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-4 (:h3 "My Subscriptions."))
			 (with-html-div-col-4 (:a :class "btn btn-primary" :role "button" :href (format nil "dodcustindex") "Shop Now")))))))

(defun customer-subscriptions-table-widget (header dodorderprefs)
  "订阅列表表格 widget。逐条调用 cust-opf-as-row 渲染。"
  (make-ui-widget (lambda ()
		    (cl-who:with-html-output (*standard-output* nil)
		      (with-html-div-row :id "idcustsubscriptions"
			(cl-who:str (display-as-table header dodorderprefs 'cust-opf-as-row)))))))



(defun customer-subscriptions-component ()
  "组合 header 与 table 两个 widget 成一个组件。"
  (make-ui-component :customer-subscriptions-component
		     (lambda (mf)
		       (multiple-value-bind (dodorderprefs header) (funcall mf)
			 (list (customer-subscriptions-header-top-widget)
			       (customer-subscriptions-table-widget header dodorderprefs))))))
(defun customer-subscriptions-page ()
  "把组件包成完整页面（角色 customer）。"
  (make-ui-page
   :customer
   :customer-subscriptions-page
   (customer-subscriptions-component)))

(defun create-ui-for-custordersubs (modelfunc)
  "view 入口：将 model 函数喂给 customer-subscriptions-page 渲染。"
  (render-ui-page (customer-subscriptions-page) modelfunc))

(defun cust-opf-as-row (orderpref &rest params)
  "把单个 dod-ord-pref 渲染为表格的一行 <td>...</td>。
   列：商品名 / 投递星期标记（Su,Mo,...） / 数量 / 单包数量 / 操作。
   操作列含一个删除按钮，点击弹 productsubsdelete-modal{id} 模态框。"
  (declare (ignore params))
  (let* ((opf-id (slot-value orderpref 'row-id))
	 (opf-product (get-opf-product orderpref))
	 (prd-name (slot-value opf-product  'prd-name)))
    (cl-who:with-html-output (*standard-output* nil)
      (:td  :height "12px" (cl-who:str prd-name))
      (:td :height "12px"    (cl-who:str (if (equal (slot-value orderpref 'sun) "Y") "Su, "))
	       (cl-who:str (if (equal (slot-value orderpref 'mon) "Y") "Mo, "))
	       (cl-who:str (if (equal (slot-value orderpref 'tue) "Y")  "Tu, "))
	       (cl-who:str (if (equal (slot-value orderpref 'wed) "Y") "We, "))
	       (cl-who:str (if (equal (slot-value orderpref 'thu) "Y")  "Th, "))
	       (cl-who:str (if (equal (slot-value orderpref 'fri) "Y") "Fr, "))
	       (cl-who:str (if (equal (slot-value orderpref 'sat) "Y")  "Sa ")))
      (:td  :height "12px" (cl-who:str (slot-value orderpref 'prd-qty)))      (:td  :height "12px" (cl-who:str (slot-value opf-product  'qty-per-unit)))
      (:td :height "12px"
	   (:a  :data-bs-toggle "modal" :data-bs-target (format nil "#productsubsdelete-modal~A" opf-id) :data-toggle "tooltip" :title "Delete Subscription"  :href "#"  :id (format nil "btndeletesubs_~A" opf-id) :name (format nil "btndeletesubs~A" opf-id) (:i :class "fa-regular fa-trash-can"))
	   (modal-dialog-v2 (format nil "productsubsdelete-modal~A" opf-id) (cl-who:str (format nil "Delete Product Subscription")) (modal.delete-subscription orderpref))))))
	    

(defun modal.delete-subscription (subscription)
  "删除订阅模态框正文：显示商品名 + 一个 POST 表单，提交到 dodcustdelopfaction 删除。
   隐藏字段 id 携带订阅主键。"
  (let* ((id (slot-value subscription 'row-id))
	(opf-product (get-opf-product subscription))
        (prd-name (slot-value opf-product  'prd-name)))
    (cl-who:with-html-output (*standard-output* nil)
      (:span  :height "12px" (cl-who:str prd-name))
      (with-html-form "deletesubscriptionform" "dodcustdelopfaction" 
	(with-html-input-text-hidden "id" id)
	(:input :type "submit" :class "btn btn-lg btn-danger"  :value "Delete")))))
  

