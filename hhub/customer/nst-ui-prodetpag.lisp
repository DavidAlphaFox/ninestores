;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：customer 客户
;;;; 分层：UI 控制器/视图层
;;;; 文件：hhub/customer/nst-ui-prodetpag.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：客户端商品详情页（PWA 自助门店）的 UI 组件、模型与控制器。
;;;;       负责渲染顶部菜单条（返回 / 订阅 / 分享 / 联系卖家 / 进店）+
;;;;       商品详情主体（图片轮播、缩略图、价格、加购按钮）。
;;;;       使用 nst- 风格的 ui-widget / ui-component / ui-page 抽象。
;;;;
;;;; 主要导出：
;;;;   dod-controller-prd-details-for-customer   — 控制器入口（客户登录后查看商品详情）
;;;;   create-model-for-prddetailsforcustomer    — 构造商品详情模型 thunk
;;;;   create-widgets-for-prddetailsforcustomer  — 渲染商品详情页面
;;;;   customer-product-detail-page              — 组装 ui-page
;;;;   customer-product-detail-page-component    — 组件：菜单 widget + 主体 widget
;;;;   customer-product-detail-menu-widget       — 顶部操作栏 widget
;;;;   customer-product-detail-content-widget    — 商品详情主体 widget
;;;;
;;;; 关联：
;;;;   上游使用方：客户 PWA 路由 /hhub/dodprddetailsforcustomer
;;;;   下游依赖：products/* BL（产品/价格/库存查询）、core 的 with-mvc-ui-page、
;;;;             nst-get-cached-product-template-func（产品详情模板缓存）、
;;;;             com-hhub-attribute-company-prdsubs-enabled（PIP 属性）
;;;; ============================================================================

(in-package :nstores)


;; Product details for customer page

(defun customer-product-detail-menu-widget (prd-id cmp-type subscribe-flag cust-type subscription-plan external-url  vendor-id)
  "构造商品详情页顶部操作栏 widget（返回购物 / 订阅 / 分享 / 联系卖家 / 进店）。
   参数：prd-id — 商品主键；cmp-type — 商家分类（如 COMMUNITY/STANDARD）；
        subscribe-flag — 商品是否可订阅（'Y'/'N'）；cust-type — 客户类型；
        subscription-plan — 商家订阅套餐；external-url — 商品外链；
        vendor-id — 卖家主键。
   返回：ui-widget 实例。
   备注：订阅按钮仅在 subscribe-flag='Y'、PIP 允许、客户为 STANDARD 时显示。"
  (make-ui-widget
   (lambda ()
     (cl-who:with-html-output (*standard-output* nil)        
       (with-html-div-row :style "border-radius: 5px;background-color:#e6f0ff; border-bottom: solid 1px; margin: 15px; padding: 10px; height: 35px; font-size: 1rem;background-image: linear-gradient(to top, #accbee 0%, #e7f0fd 100%);"
	 (with-html-div-col-2 :data-bs-toggle "tooltip" :title "Back to Shopping"
	   (:a  :href "/hhub/dodcustindex" (:i :class "fa-solid fa-arrow-left")))
	 (with-html-div-col-2 
	   ;; display the subscribe button under certain conditions. 
	   (when (and (equal subscribe-flag "Y")
		      (com-hhub-attribute-company-prdsubs-enabled subscription-plan cmp-type) 
		      (equal cust-type "STANDARD"))
	     (cl-who:htm
	      (:button :data-bs-toggle "modal" :data-bs-target (format nil "#productsubscribe-modal~A" prd-id)  :href "#"   :class "subscription-btn" :id (format nil "btnsubscribe~A" prd-id) :name (format nil "btnsubscribe~A" prd-id) "Subscribe&nbsp;" (:i :class "fa-solid fa-hand-point-up"))
	      (modal-dialog-v2 (format nil "productsubscribe-modal~A" prd-id) "Subscribe Product/Service" (product-subscribe-html prd-id)))))
	 (with-html-div-col-2
	   (when external-url
	     (cl-who:htm
	      (:div  :data-toggle "tooltip" :title "Share Product"
		     (:a :id "idshareexturl" :href "#" (:i :class  "fa-solid fa-arrow-up-from-bracket")))
	      (sharetextorurlonclick "#idshareexturl" (parenscript:lisp external-url)))))
	 (with-html-div-col-2 :data-toggle "tooltip" :title "Contact Seller"  
	   (:a :data-bs-toggle "modal" :data-bs-target (format nil "#vendordetails-modal~A" vendor-id)  :href "#" :name "btnvendormodal"  (:i :class "fa-solid fa-address-card"))
	   (modal-dialog-v2 (format nil "vendordetails-modal~A" vendor-id) (cl-who:str (format nil "Vendor Details")) (modal.vendor-details vendor-id)))
	 (with-html-div-col-3 :data-toggle "tooltip" :title "Visit Store"  
	   (:p (:a :href (format nil "hhubcustvendorstore?id=~A" vendor-id) (:i :class "fa-solid fa-store")))))
       (:hr)))))

(defun customer-product-detail-content-widget (proddetailpagetempl)
  "构造商品详情主体 widget。proddetailpagetempl 是已经把所有 %占位% 替换完的 HTML 字符串。"
  (make-ui-widget
   (lambda ()
     (product-card-with-details-for-customer2  proddetailpagetempl))))

(defun product-card-with-details-for-customer2 (proddetailpagetempl)
  "把已渲染的商品详情 HTML 串原样写入 *standard-output*。"
  (cl-who:with-html-output (*standard-output* nil)
    (cl-who:str proddetailpagetempl)))

(defun customer-product-detail-page-component ()
  "组装客户端商品详情页 UI 组件：在调用模型 thunk 取出多值后，分别构造顶部菜单
   widget 与主体 widget，按顺序返回。"
  (make-ui-component :customer-product-detail-page-component
		     (lambda (mf)
		       (multiple-value-bind (proddetailpagetempl prd-id cmp-type subscribe-flag cust-type subscription-plan external-url  vendor-id) (funcall mf)
			 (list (customer-product-detail-menu-widget prd-id cmp-type subscribe-flag cust-type subscription-plan external-url  vendor-id)
			       (customer-product-detail-content-widget proddetailpagetempl))))))

(defun customer-product-detail-page ()
  "构造 :customer 角色下的商品详情 ui-page，使用上面定义的组件。"
  (make-ui-page :customer
		:customer-product-detail-page
		(customer-product-detail-page-component)))

(defun create-widgets-for-prddetailsforcustomer (modelfunc)
  "with-mvc-ui-page 回调：把 modelfunc 喂给 ui-page 渲染器。"
  (render-ui-page (customer-product-detail-page) modelfunc))


(defun create-model-for-prddetailsforcustomer ()
  "构造商品详情页的模型。从 query string 取 id，到 session 缓存里找商品对象，
   读取价格、图片、库存、订阅、卖家等数据，再用模板 #1 做占位符替换得到最终 HTML。
   返回：thunk，调用产生 8 个值（详情 HTML、prd-id、cmp-type、subscribe-flag、
        cust-type、subscription-plan、external-url、vendor-id）。
   备注：模板里的 %xxx% 占位符通过 cl-ppcre:regex-replace-all 替换为实际控件 HTML。"
  (let* ((prd-id (parse-integer (hunchentoot:parameter "id")))
	 (productlist (if (> prd-id 0) (hunchentoot:session-value :login-prd-cache)))
	 (lstshopcart (hunchentoot:session-value :login-shopping-cart))
	 (numitemsincart (Length lstshopcart))
	 (product (if (> prd-id 0) (search-item-in-list 'row-id prd-id productlist)))
	 (prdincart-p (prdinlist-p (slot-value product 'row-id)  lstshopcart))
	 (customer (get-login-customer))
	 (company (product-company product))
	 (description (slot-value product 'description))   
	 (product-sku (slot-value product 'sku))
	 (images-str (slot-value product 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (product-pricing (select-product-pricing-by-product-id prd-id company))
	 (product-pricing-widget (cl-who:with-html-output-to-string  (*standard-output* nil)
				   (product-price-with-discount-widget product product-pricing)))
	 (prd-name (slot-value product 'prd-name))
	 (product-images-carousel (cl-who:with-html-output-to-string  (*standard-output* nil)
				    (render-multiple-product-images prd-name imageslst images-str)))
	 (product-images-thumbnails (cl-who:with-html-output-to-string  (*standard-output* nil)
				  (render-multiple-product-thumbnails prd-name imageslst images-str)))
	 (proddetailpagetempl (funcall (nst-get-cached-product-template-func :templatenum 1)))	 
	 (qtyperunit-str  (format nil "~A" (slot-value product 'qty-per-unit)))
	 (unit-of-measure (slot-value product 'unit-of-measure))
	 (unitsinstock-str (format nil "~A" (slot-value product 'units-in-stock)))
	 (units-in-stock (slot-value product 'units-in-stock))
	 (addtocart-widget (cl-who:with-html-output-to-string  (*standard-output* nil)
			     (customer-add-to-cart-widget units-in-stock product product-pricing prd-id prdincart-p numitemsincart)))
	 (external-url (slot-value product 'external-url))
	 (subscribe-flag (slot-value product 'subscribe-flag))
	 (cust-type (slot-value customer 'cust-type))
	 (prd-vendor (product-vendor product))
	 (subscription-plan (slot-value company 'subscription-plan))
	 (cmp-type (slot-value company 'cmp-type))
	 (vendor-id (slot-value prd-vendor 'row-id)))
    
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product Name%" proddetailpagetempl prd-name))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Qty-Per-Unit%" proddetailpagetempl qtyperunit-str))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Unit-Of-Measure%" proddetailpagetempl unit-of-measure))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-SKU%" proddetailpagetempl product-sku))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Description%" proddetailpagetempl description))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Units-In-Stock%" proddetailpagetempl unitsinstock-str))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Add-to-Cart-Button%" proddetailpagetempl addtocart-widget))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Pricing-Control%" proddetailpagetempl product-pricing-widget))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Images-Carousel%" proddetailpagetempl product-images-carousel))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Images-Thumbnails%" proddetailpagetempl product-images-thumbnails))
    
    (function (lambda ()
      (values proddetailpagetempl  prd-id  cmp-type subscribe-flag cust-type subscription-plan external-url  vendor-id)))))

(defun dod-controller-prd-details-for-customer ()
  "客户端商品详情页控制器。需要客户已登录；URL 参数 ?id=<prd-id>。
   通过 with-mvc-ui-page 串联 model + widgets 完成渲染。"
   (with-cust-session-check
     (with-mvc-ui-page "Product Details Customer" #'create-model-for-prddetailsforcustomer #'create-widgets-for-prddetailsforcustomer :role :customer)))
