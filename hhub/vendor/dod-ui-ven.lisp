;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— UI 控制器与视图（卖家中心 / 后台门店）
;;;; 分层：UI（控制器 + CL-WHO 模板）
;;;; 文件：hhub/vendor/dod-ui-ven.lisp（特大文件 ~148KB / 2700+ 行 / 150+ 函数）
;;;; ----------------------------------------------------------------------------
;;;; 职责：vendor（卖家）操作的全部 UI 控制器与对应模板。覆盖：
;;;;   - 登录 / 登出 / OTP 登录 / 切换 tenant / 修改 PIN / 忘记密码 / 重置密码
;;;;   - 卖家档案页 / 改动档案模态 / 头像与图片上传到 S3
;;;;   - 商品（vendor product）增删改查、批量上传 CSV、生成 SKU 模板
;;;;   - 订单（vendor order）查看、详情、设为已履约、取消、按商品聚合
;;;;   - 客户（vendor my customers）搜索、钱包充值、钱包查询
;;;;   - 收款设置：UPI、支付网关、付款方式开关（COD/UPI/钱包/...）
;;;;   - 配送设置：默认运费、平价运费、免邮、外部物流伙伴、运费区域 + 阶梯表
;;;;   - 推送订阅、Web REPL 入口、商品分类、商品图片上传、Excel 导出、
;;;;     vendor 控制台主页 dod-vend-index（按 context 分发不同视图）
;;;;   - vendor session 管理（缓存当前 vendor 拉的产品/订单函数列表）
;;;;
;;;; 主要导出（按业务分组，仅列代表性符号）：
;;;;   登录会话：dod-controller-vend-login / -otpstep / -with-otp /
;;;;             dod-controller-vendor-{loginpage,otploginpage,otploginpagev2,logout}
;;;;             set-vendor-session-params / get-login-vendor / get-login-vendor-id /
;;;;             get-login-vendor-tenant-id / get-login-vend-company /
;;;;             enforcevendorsession / resetvendorsessions
;;;;   档案/收款：dod-controller-vend-profile / -update-action /
;;;;             modal.vendor-update-details / modal.vendor-update-UPI-payment-settings-page /
;;;;             dod-controller-vendor-payment-methods-update-action /
;;;;             modal.vendor-payment-methods-page
;;;;   商品：    dod-controller-vendor-{products,add-product-page,delete-product,
;;;;             deactivate-product,activate-product,copy-product,search-products,
;;;;             product-categories-page,bulk-add-products-page,
;;;;             generate-products-templ,upload-product-images} /
;;;;             com-hhub-transaction-vendor-{product-add-action,upload-product-images-action,
;;;;             bulk-products-add}
;;;;   订单：    dod-controller-vendor-{order-cancel,orderdetails,revenue,
;;;;             vend-index,refresh-pending-orders,my-customers-page} /
;;;;             com-hhub-transaction-vendor-order-setfulfilled
;;;;   客户：    hhub-controller-{search-my-customer-action,
;;;;             vsearchcustbyname-for-invoice-action,vsearchcustbyphone-for-invoice-action} /
;;;;             dod-controller-vendor-search-cust-wallet-{page,action} /
;;;;             dod-controller-update-wallet-balance
;;;;   配送：    dod-controller-vend-shipping-methods / -shipzone-ratetable-page /
;;;;             dod-controller-vendor-{update-default-shipping-method,
;;;;             update-external-shipping-partner-action,
;;;;             update-flatrate-shipping-action,
;;;;             update-free-shipping-method-action,
;;;;             upload-shipping-ratetable-action}
;;;;   多 tenant：dod-controller-display-vendor-tenants /
;;;;             dod-controller-cmpsearch-for-vend-page / -action /
;;;;             dod-controller-vend-add-tenant-action /
;;;;             dod-controller-vendor-switch-tenant
;;;;   缓存：    hhub-get-cached-vendor-products / -product-categories /
;;;;             -active-vendor-products / -company-products /
;;;;             dod-get-cached-pending-orders / -completed-orders /
;;;;             -completed-orders-today / -order-items-by-{order-id,product-id} /
;;;;             dod-gen-vendor-products-functions / dod-gen-order-functions /
;;;;             dod-reset-vendor-products-functions / dod-reset-order-functions
;;;;   通用 UI：vendor-card / vendor-details-card /
;;;;             render-sidebar-offcanvas / display-my-customers-row /
;;;;             display-wallet-for-customer / vendor-product-category-row /
;;;;             ui-list-cmp-for-vend-tenant / ui-list-vend-orderdetails
;;;;   Web REPL：com-hhub-transaction-vendor-display-webrepl-page
;;;;
;;;; 关联：
;;;;   上游使用方：Hunchentoot 路由注册器（控制器名约定 dod-controller-* /
;;;;               com-hhub-transaction-* / hhub-controller-*）。
;;;;   下游依赖：vendor/dod-bl-ven.lisp、vendor/dod-bl-vpm.lisp、
;;;;             vendor/dod-bl-vad.lisp、vendor/dod-bl-vas.lisp、
;;;;             products / order / invoice / shipping / customer / paymentgateway /
;;;;             upi / webpushnotify 等模块的 BL，core 平台基础（with-vend-session-check、
;;;;             with-mvc-ui-page、with-mvc-redirect-ui、with-hhub-transaction、
;;;;             nst-get-cached-core-template-func、cl-async S3 上传等）。
;;;;
;;;; 备注：
;;;;   - 控制器多数走传统的 with-mvc-ui-page / with-mvc-redirect-ui MVC 管线，
;;;;     create-model-for-* 拉数据，create-widgets-for-* 渲染 widget 闭包。
;;;;   - modal.* 命名约定的函数返回 cl-who HTML 片段，被 modal-dialog 包裹后嵌入页面。
;;;;   - 由于本文件 CL-WHO 模板量极大，注释采用"节段说明 + 关键控制器 docstring"
;;;;     的策略，不为每条 cl-who 块都加行内注释。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


;; ----------------------------------------------------------------------------
;; 段：Web REPL 入口
;; com-hhub-transaction-vendor-display-webrepl-page —— 进入卖家在线 REPL
;; create-model-for-vdisplay-webrepl —— 拉模板号 1 的核心模板 HTML
;; create-widgets-for-vdisplay-webrepl —— 单 widget 直接 str 模板
;; ----------------------------------------------------------------------------

(defun com-hhub-transaction-vendor-display-webrepl-page ()
  "卖家 Web REPL 页面控制器。需 vendor 会话（with-vend-session-check）。
   通过 with-mvc-ui-page 渲染 'Vendor Web REPL' 页（role=:vendor）。"
  (with-vend-session-check
    (with-mvc-ui-page "Vendor Web REPL" #'create-model-for-vdisplay-webrepl  #'create-widgets-for-vdisplay-webrepl :role :vendor)))


(defun create-model-for-vdisplay-webrepl ()
  "拉取核心模板 1 号（vendor Web REPL 静态 HTML）。返回 model 闭包。"
  (let ((webrepltemplatehtml (funcall (nst-get-cached-core-template-func :templatenum 1))))
    (function (lambda ()
      (values webrepltemplatehtml)))))


(defun create-widgets-for-vdisplay-webrepl (modelfunc)
  "把模板 HTML 直接 str 输出为单 widget。"
  (multiple-value-bind (webrepltemplatehtml) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (cl-who:str webrepltemplatehtml))))))
      (list widget1))))

;; ----------------------------------------------------------------------------
;; 段：商品图片上传 & 文件上传 S3
;; ----------------------------------------------------------------------------
(defun com-hhub-transaction-vendor-upload-product-images-action ()
  "商品图片上传控制器。需 vendor 会话；以 redirect-ui 模式：
   model 完成上传后产出 redirecturl，generic redirect widget 直接 302。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vuploadprdimages  #'create-widgets-for-genericredirect)))

(defun create-model-for-vuploadprdimages ()
  "处理 prd-id 关联的商品图片：
     1) 从 multipart 中过滤 'uploadedimagefiles' 字段；
     2) 调 process-file 写到 *HHUBRESOURCESDIR*；
     3) vendor-delete-files-s3bucket 删 S3 上旧文件；
     4) async-upload-files-s3bucket 异步上传新文件；
     5) 把 uploadedfiles 列表序列化写入 product.prd-image-path 并 update-prd-details；
     6) 重建 vendor 商品缓存（dod-gen-vendor-products-functions）。
   返回 model 闭包，给出 redirecturl=/hhub/dodprddetailsforvendor?id=<prd-id>。
   副作用：S3 上传/删除、UPDATE products 表、写日志。"
    (logiamhere (format nil "Files to be uploaded are ~A" (hunchentoot:post-parameters hunchentoot:*request*)))
  (let* ((images (remove "uploadedimagefiles" (hunchentoot:post-parameters hunchentoot:*request*) :test (complement #'equal) :key #'car))
	 (prd-id (parse-integer (hunchentoot:parameter "prd-id")))
	 (productlist (hhub-get-cached-vendor-products))
	 (product (search-item-in-list 'row-id prd-id productlist))
	 (filepaths (mapcar
		     (lambda (image)
		       (let* ((newimageparams (remove "uploadedimagefiles" image :test #'equal ))
			      (newfilename (process-file  newimageparams (format nil "~A" *HHUBRESOURCESDIR*))))
			 newfilename)) images))
	 (vendor (get-login-vendor))
	 (vendor-id (get-login-vendor-id))
	 (company (get-login-vendor-company))
	 (tenant-id (get-login-vendor-tenant-id))
	 (redirecturl (format nil "/hhub/dodprddetailsforvendor?id=~d" prd-id))
	 ;; delete old files from s3 bucket.
	 (deletedfiles (vendor-delete-files-s3bucket "prd" prd-id vendor-id tenant-id))
	 (uploadedfiles (async-upload-files-s3bucket filepaths "prd" prd-id vendor)))
    ;; After the files have been uploaded, we can reference it through the session value
    (logiamhere (format nil "deleted files are ~A" deletedfiles))
    (when (and uploadedfiles (> (length uploadedfiles) 0))
      (setf (slot-value product 'prd-image-path) (write-to-string uploadedfiles :readably t))
      ;; update the database with the new file upload paths.
      (update-prd-details  product))
    (dod-gen-vendor-products-functions vendor company)
    (function (lambda ()
      (values redirecturl)))))
	 
;; ----------------------------------------------------------------------------
;; 段：vendor 全局侧边栏（offcanvas）
;; eval-when 包住，编译期就有定义，可被同文件其他控制器内联引用 sidebar 渲染。
;; ----------------------------------------------------------------------------
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun render-sidebar-offcanvas ()
    "渲染 vendor 后台 offcanvas 侧边栏（左侧伸缩菜单）。
     根据当前 vendor 公司的 cmp-type / subscription-plan 通过
     com-hhub-attribute-company-prdbulkupload-enabled 决定是否显示
     'Bulk Add Products' 入口。菜单分组：Home / Product Master / Orders /
     更多业务模块。"
    (let* ((vendor-company (get-login-vendor-company))
	   (cmp-type (slot-value vendor-company 'cmp-type))
	   (subscription-plan (slot-value vendor-company 'subscription-plan))
	   (compbulkupload-p (com-hhub-attribute-company-prdbulkupload-enabled subscription-plan cmp-type)))
      (cl-who:with-html-output (*standard-output* nil :prologue t :indent t)
	(:div :class "offcanvas offcanvas-start" :tabindex"-1" :id "offcanvasExample" :aria-labelledby "offcanvasExampleLabel" :style  "  background: rgb(222,228,255);
background: linear-gradient(171deg, rgba(222,228,255,1) 0%, rgba(224,236,255,1) 100%); "
	      (:div :class "offcanvas-header"
		    (:img :src "/img/logo.png" :alt "" :width "32" :height "32" :class "rounded-circle me-2")
		    (:h5 :class "offcanvas-title" :id "offcanvasExampleLabel" "Nine Stores")
		    (:button :type "button" :class "btn-close btn-close" :data-bs-dismiss "offcanvas" :aria-label "Close"))
	      (:div :class "offcanvas-body"
		    (:ul :class "nav nav-tabs flex-column mb-auto"
			 (:li :class "nav-item"
			      (:a :href "dodvendindex?context=home"
				  (:i :class "fa-solid fa-house")  "&nbsp;&nbsp;Home"))
			 (:li :class "nav-item"
			      (:a :href "#" :class "nav-link collapsed has-dropdown dropdown-toggle" :data-bs-toggle "collapse"
				  :data-bs-target "#productmaster" :aria-expanded "true" :aria-controls "productmaster"
				  (:i :class "fa-solid fa-rectangle-list") " Product Master")
			      (:ul :id "productmaster" :class "nav-dropdown list-unstyled collapse" :data-bs-parent "#offcanvasExample"
				   (:li :class "sidebar-item"
					(:a :href "/hhub/dodvenproducts" :class "nav-link" "Product List"))
				   (:li :class "sidebar-item"
					(:a :href "/hhub/dodvendprodcategories" :class "nav-link" "Product Categories"))
				   (:li :class "sidebar-item"
					(:a :href "/hhub/dodvenaddprodpage" :class "nav-link" "Add New Product"))
				   (when compbulkupload-p
				     (cl-who:htm
				      (:li :class "sidebar-item"
					   (:a :href "/hhub/dodvenbulkaddprodpage" :class "nav-link" "Bulk Add Products"))))))
		       (:li :class "nav-item"
			    (:a :href "#" :class "nav-link collapsed has-dropdown dropdown-toggle" :data-bs-toggle "collapse"
				:data-bs-target "#orders" :aria-expanded "true" :aria-controls "orders"
			   (:i :class "fa-solid fa-rectangle-list") " Orders")
			    (:ul :id "orders" :class "nav-dropdown list-unstyled collapse" :data-bs-parent "#offcanvasExample"
				 (:li :class "nav-item"
				      (:a :href "/hhub/dodvendindex?context=pendingorders"  :class "nav-link link-body-emphasis"
					  (:i :class "fa-regular fa-rectangle-list")  " Pending Orders"))
				 (:li :class "nav-item"
				      (:a :href "/hhub/dodvendindex?context=ctxordprd"  :class "nav-link link-body-emphasis"
					  (:i :class "fa-regular fa-rectangle-list")  " Pending Orders By Products"))
				 (:li :class "nav-item"
				      (:a :href "/hhub/dodvendindex?context=completedorders"  :class "nav-link link-body-emphasis"
					  (:i :class "fa-regular fa-rectangle-list")  " Completed Orders"))))
		       (:li :class "nav-item"
			    (:a :href "/hhub/displayinvoices"  :class "nav-link link-body-emphasis"
				(:i :class "fa-regular fa-rectangle-list")  " Sale Invoices"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/hhubvendorupitransactions"  :class "nav-link link-body-emphasis"
				(:i :class "fa-regular fa-rectangle-list")  " UPI Transactions"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/hhubvendmycustomers" :class "nav-link link-body-emphasis"
				(:i :class "fa-regular fa-user") " Customers"))
		       (:li :class "nav-item"
			    (:a :href "#" :class "nav-link collapsed has-dropdown dropdown-toggle" :data-bs-toggle "collapse"
				:data-bs-target "#reports" :aria-expanded "true" :aria-controls "reports"
				(:i :class "fa-solid fa-circle-info") " Reports")
			    (:ul :id "reports" :class "nav-dropdown list-unstyled collapse" :data-bs-parent "#offcanvasExample"
				 (:li :class "sidebar-item"
				      (:a :href "/hhub/dodvendrevenue" :class "nav-link" "Today's Revenue"))))
		       (:li :class "nav-item"
			    (:a :href "#" :class "nav-link collapsed has-dropdown dropdown-toggle" :data-bs-toggle "collapse"
				:data-bs-target "#settings" :aria-expanded "true" :aria-controls "settings"
				(:i :class "fa-solid fa-gear") " Settings")
			    (:ul :id "settings" :class "nav-dropdown list-unstyled collapse" :data-bs-parent "#offcanvasExample"
				 (:li :class "sidebar-item"
				      (:a :href "hhubvendpushsubscribepage" :class "nav-link" "Browser Push Notification"))
				 (:li :class "sidebar-item"
				      (:a :href "/hhub/dodvendprofile?context=home" :class "nav-link" "Vendor Settings"))
				 )))))))
								
		  ;; (:div :class "dropdown"
		  ;; 	(:a :href "#" :class "d-flex align-items-center link-body-emphasis text-decoration-none dropdown-toggle" :data-bs-toggle "dropdown" :aria-expanded "false"
			    
		  ;; 	    (:ul :class "dropdown-menu text-small shadow" :style=""
		  ;; 	    (:li (:a :class "dropdown-item" :href "#" "New project..."))
		  ;; 	    (:li (:a :href "/hhub/dodvendlogout" :class="nav-link"
		  ;; 		     (:i :class "fa-solid fa-arrow-right-from-bracket") (:span "Sign Out"))))))
		  ;; (:div :class "dropdown mt-3"
		  ;; 	 (:button :class "btn btn-secondary dropdown-toggle" :type "button" :data-bs-toggle "dropdown"
		  ;; 		  "Dropdown button")
		  ;; 	 (:ul :class "dropdown-menu"
		  ;; 	      (:li (:a :class "dropdown-item" :href "#" "Action"))
		  ;; 	      (:li (:a :class "dropdown-item" :href "#" "Another action")
		  ;; 		   (:li (:a :class "dropdown-item" :href "#" "Something else here")))))
		  ))


(eval-when (:compile-toplevel :load-toplevel :execute) 
  (defmacro with-vendor-sidebar ()
    `(cl-who:with-html-output (*standard-output* nil :prologue t :indent t)
       ;;<!-- sidebar -->
       ;;<!-- Sidebar -->
       (:nav :id "nstvendorsidebar" :class "collapse d-lg-block sidebar collapse bg-white" :style "width: 280px;"
	     (:a :href "dodvendindex?context=home" :class "d-flex align-items-center mb-3 mb-md-0 me-md-auto link-body-emphasis text-decoration-none"
		 (:span :class "fs-4" "Sidebar"))
	     (:hr)
	     (:ul :class "nav nav-pills flex-column mb-auto"
		  (:li :class "nav-item" (:a :href "dodvendindex?context=home" (:i :class "fa-solid fa-house")  "Home"))
		  (:li :class "nav-item" 
		       (:a :href "/hhub/dodvenproducts" :class "nav-link link-body-emphasis" 
			   (:i :class "fa-regular fa-rectangle-list") "My Products"))
		  (:li :class "nav-item"
		       (:a :href "/hhub/dodvendindex?context=completedorders"  :class "nav-link link-body-emphasis"
			   (:svg :class "bi me-2" :width "16" :height "16" (:use :xlink\:href "#table")) "Completed Orders"))
		  (:li :class "nav-item"
		       (:a :href "/hhub/hhubvendmycustomers" :class "nav-link link-body-emphasis"
			   (:svg :class "bi me-2" :width "16" :height "16" (:use :xlink\:href "#people-circle")) "Customers"))
		  (:li :class "nav-item"
		       (:a :href "/hhub/dodvendprofile" :class "nav-link link-body-emphasis"
			   (:svg :class "bi me-2" :width "16" :height "16" (:use :xlink\:href "#grid")) "Settings"))
		  (:li :class "nav-item"
		       (:a :href "#" :class "nav-link collapsed has-dropdown" :data-bs-toggle "collapse"
			   :data-bs-target "#auth" :aria-expanded "true" :aria-controls "auth"
			   (:class "fa-solid fa-person-military-pointing" (:span "Auth")))
		       (:ul :id "auth" :class "nav-dropdown list-unstyled collapse" :data-bs-parent "#nstvendorsidebar"
			    (:li :class "sidebar-item"
				 (:a :href "#" :class "nav-link" "Login")))))
	     (:div :class "dropdown" 
		   (:a :href "#" :class "d-flex align-items-center link-body-emphasis text-decoration-none dropdown-toggle" :data-bs-toggle "dropdown" :aria-expanded "false"
		       (:img :src "/img/logo.png" :alt "" :width "32" :height "32" :class "rounded-circle me-2" "Profile")
		       (:ul :class "dropdown-menu text-small shadow" :style=""
			    (:li (:a :class "dropdown-item" :href "#" "New project..."))
			    (:li (:a :class "dropdown-item" :href "#" "New project..."))
			    (:li (:a :class "dropdown-item" :href "#" "New project..."))
			    (:li (:a :class "dropdown-item" :href "#" "New project..."))
			    (:li (:a :href "/hhub/dodvendlogout" :class="nav-link"
				     (:i :class "fa-solid fa-arrow-right-from-bracket") (:span "Sign Out"))))))))))

;; ----------------------------------------------------------------------------
;; 段：vendor 顶部导航栏（v2 版）
;; ----------------------------------------------------------------------------
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun with-vendor-navigation-bar-v2 ()
    :documentation "this macro returns the html text for generating a navigation bar using bootstrap.
   中文：渲染 vendor 后台顶部 navbar（含 Home / 会话超时 / 通知铃 / Profile / Logout）。
   名字虽叫 'with-...'，实际是 defun 不是 macro（命名遗留）。"
    (cl-who:with-html-output (*standard-output* nil)
	(:nav :class "navbar navbar-expand-sm  sticky-top navbar-dark bg-dark" :id "hhubcustnavbar"  
	      (:div :class "container-fluid"
		    (:a :class "navbar-brand" :href "/hhub/dodvendindex" (:img :style "width: 30px; height: 24px;" :src "/img/logo.png" ))
		    (:button :class "navbar-toggler" :type "button" :data-bs-toggle "collapse" :data-bs-target "#navbarSupportedContent" :aria-controls "navbarSupportedContent" :aria-expanded "false" :aria-label "Toggle navigation" 
			     (:span :class "navbar-toggler-icon" ))
		    (:div :class "collapse navbar-collapse justify-content-between" :id "navbarSupportedContent"
			  (:ul :class "navbar-nav me-auto mb-2 mb-lg-0" 
			       (:li :class "nav-item"
				    (:a :class "btn btn-primary" :data-bs-toggle "offcanvas" :href "#offcanvasExample" :role "button" :aria-controls "offcanvasExample" (:i :class "fa-solid fa-bars")))
			     (:li :class "nav-item" 	
				  (:a :class "nav-link active" :aria-current "page" :href "/hhub/dodvendindex?context=home" (:i :class "fa-solid fa-house") "&nbsp;Home"))
			     ;;(:li :class "nav-item"  (:a :class "nav-link" :href "dodvenproducts" "Products/Services"))
			     ;;(:li :class "nav-item"  (:a :class "nav-link" :href "dodvendindex?context=completedorders"  "Completed Orders"))
			     (:li :class "nav-item"  (:a :class "nav-link" :href "#" (print-vendor-web-session-timeout))))
			  (:ul :class "navbar-nav ms-auto"
			       (:li :class "nav-item"  (:a :class "nav-link" :href "#"  (:i :class "fa-regular fa-bell")))
			       (:li :class "nav-item"  (:a :class "nav-link" :href "dodvendprofile?context=home" (:i :class "fa-regular fa-user")))
			       (:li :class "nav-item" (:a :class "nav-link" :href "dodvendlogout" (:i :class "fa-solid fa-arrow-right-from-bracket"))))))))))
  
;; ----------------------------------------------------------------------------
;; 段：vendor 商品价格更新
;; ----------------------------------------------------------------------------
(defun create-model-for-vendorprodpricingaction ()
  "解析表单中的 prdprice / prddiscount / startdate / enddate / prdid，
   先尝试 select-product-pricing-by-product-id，若不存在则 create-product-pricing；
   存在则更新；同时把当前价/折扣写回 product 表。最后清缓存
   （dod-reset-vendor-products-functions）。返回 redirecturl=/hhub/dodvenproducts。
   副作用：写 DOD_PRD_PRICING 与 DOD_PRODUCT 表。"
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (prd-price (float (with-input-from-string (in (hunchentoot:parameter "prdprice"))
			     (read in))))
	 (prd-discount (float (with-input-from-string (in (hunchentoot:parameter "prddiscount"))
				(read in))))
	 (start-date (get-date-from-string (hunchentoot:parameter "startdate")))
	 (end-date (get-date-from-string (hunchentoot:parameter "enddate")))
	 (prd-id (parse-integer (hunchentoot:parameter "prdid")))
	 (product (select-product-by-id prd-id company))
	 (currency (get-account-currency company))
	 (prdpricing (select-product-pricing-by-product-id prd-id company))
	 (redirectlocation "/hhub/dodvenproducts"))
    (unless prdpricing
      (create-product-pricing product prd-price prd-discount currency start-date end-date company))
    (when prdpricing
      (setf (slot-value prdpricing 'price) prd-price)
      (setf (slot-value prdpricing 'currency) currency)
      (setf (slot-value prdpricing 'discount) prd-discount)
      (setf (slot-value prdpricing 'start-date) start-date)
      (setf (slot-value prdpricing 'end-date) end-date)
      (update-prd-details prdpricing))
    (when product
      (with-slots (current-price current-discount) product
	(setf current-price prd-price)
	(setf current-discount prd-discount)
	;; Update product table with the price and discount data.
	(update-prd-details product)))
      (dod-reset-vendor-products-functions vendor company)
      (function (lambda ()
	redirectlocation))))

(defun dod-controller-vendor-product-pricing-action ()
  "商品价格更新控制器。需 vendor 会话；redirect-ui 模式：完成后跳到商品列表。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendorprodpricingaction #'create-widgets-for-genericredirect)))

(defun vendor-card (vendor)
  "渲染单个 vendor 的卡片：头像 + 名称 + 跳到 vendor 店铺的链接。"
  (let* ((vname (slot-value vendor 'name))
	 (vid (slot-value vendor 'row-id))
	 (vpicture (slot-value vendor 'picture-path)))
    (cl-who:with-html-output (*standard-output* nil)
      (:img :src vpicture :alt vname :style "align:center; width: 100px; height: 100px; border-radius: 50%;")
      (:h5 vname)
      (:span (:a :href (format nil "hhubcustvendorstore?id=~A" vid) (:i :class "fa-solid fa-store") (cl-who:str (format nil "&nbsp;~A Store" vname)))))))
    

;; ----------------------------------------------------------------------------
;; 段：vendor Webpush 订阅
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-pushsubscribe-page ()
  "vendor 浏览器推送订阅页（含 JS 客户端 pushsubscribe.js）。需 vendor 会话。"
  (with-vend-session-check
    (with-mvc-ui-page "Webpush Subscription for Vendor" #'create-model-for-vendpushsubscribepage #'create-widgets-for-vendpushsubscribepage :role :vendor)))

(defun create-model-for-vendpushsubscribepage ()
  "返回站点 URL（*siteurl*），供前端 JS 拼出订阅服务端点。"
  (let ((url *siteurl*))
    (function (lambda ()
      (values url)))))

(defun create-widgets-for-vendpushsubscribepage (modelfunc)
  "渲染推送订阅页 widget 列表：说明文案 / 状态卡 + 操作按钮 / 返回链接 / 加载 pushsubscribe.js。"
  (multiple-value-bind (url) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(:br)
			(with-html-div-row
			  (:h3 "Subscribe to Notifications on your Browser"))
			(with-html-div-row
			  (:p "Note: We send notifications for various events, for example:  when you receive a new order. Push notification will be sent to one browser only.")
			  (:p "If you would like to subscribe to notifications on a different browser, you need to unsubscribe in current browser and subscribe in other browser"))))))
	   (widget2 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
                        (:div :class "push-status-container"
			      (:h3 "📢 Push Notification Subscription Status")
			      (:p "Review the status below. The main button will guide you on the next required action based on the lifecycle state.")
			      ;; --- 1. STATUS SUMMARY CARD (ALWAYS VISIBLE) ---
			      ;; This is the primary UI element, dynamically colored by JavaScript.
			      (:div :id "sync-status-panel" :class "alert alert-info" :role "alert"
				    (:span :id "current-sync-message" "Checking subscription status..."))
			      ;; --- 2. ACTION BUTTONS (ALWAYS VISIBLE) ---
			      (:div :class "mt-3 d-flex flex-wrap gap-2"
				    ;; The main toggle button
				    (:button :id "btnPushNotifications"  :class "btn btn-sm btn-secondary"   :disabled "disabled" "Loading...")
				    ;; The secondary action button (for force cleanup/State 4)
                                    (:button :id "btnPushSubscriptionRemoveFromServer"
					     :class "btn btn-sm btn-outline-danger"
					     :style "display:none;" ; Initially hidden, shown by JS only in State 4
					     "Force Remove from Backend"))
			      ;; --- 3. COLLAPSIBLE TECHNICAL DETAILS (HIDDEN BY DEFAULT) ---
			      (:p :class "mt-4"
				  (:a :data-bs-toggle "collapse"  :href "#technicalDetailsCollapse"  :role "button" :aria-expanded "false" :aria-controls "technicalDetailsCollapse"      "Show Technical Sync Details (for troubleshooting)"))
		              (:div :class "collapse" :id "technicalDetailsCollapse"
			            (:p :class "text-muted small mt-2" "Diagnostics for IT support.")
				    (:table :class "table table-striped table-bordered"
				            (:thead
					     (:tr
					      (:th "Detail")
					      (:th "Browser Status")
					      (:th "Backend DB Status")))
					    (:tbody
					     (:tr
					      (:td (cl-who:esc "**Subscription State**"))
					      (:td :id "browser-state" "--")
					      (:td :id "backend-state" "--"))
					     (:tr
					      (:td (cl-who:esc "**Endpoint Exists**"))
					      (:td :id "browser-endpoint" "--")
					      (:td :id "backend-endpoint" "--"))
					     (:tr
					      (:td (cl-who:esc "**Expiration Time**"))
					      (:td :id "browser-expiry" "--")
					      (:td :id "backend-expiry" "--"))))))))))   

	   (widget3 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-html-div-row
			  (with-html-div-col-4
			    (:a :href "dodvendindex?context=home" "Home")))))))
	   (widget4 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(:script :src (format nil "/js/pushsubscribe.js")))))))
	   
      (list widget1 widget2 widget3 widget4))))

;; ----------------------------------------------------------------------------
;; 段：S3 异步上传 / 批量上传 CSV / 模板
;; ----------------------------------------------------------------------------
(defun async-upload-files-s3bucket-behavior (state messagefunc)
  "Actor behavior：根据 messagefunc 取出 (product images objectname object-id vendor)，
   走 vendor-upload-file-s3bucket（或本地 *HHUBUSELOCALSTORFORRES* 兜底）拿到 URL 列表，
   写回 product.prd-image-path 并 update-prd-details。state 计数器递增返回。"
  (multiple-value-bind (product images objectname object-id vendor) (funcall messagefunc)
    (let* ((vendor-id (slot-value vendor 'row-id))
	  (tenant-id (slot-value vendor 'tenant-id))
	  (uploadedfiles (if (and images (> (length images) 0))
			     (mapcar
			      (lambda (image)
				(if *HHUBUSELOCALSTORFORRES* 
				    (format nil "/img/~A" image)
				    ;;else return the path of the uploaded file in S3 bucket.
				    (vendor-upload-file-s3bucket image objectname object-id vendor-id tenant-id))) images))))
      
      (when (and uploadedfiles (> (length uploadedfiles) 0))
	(setf (slot-value product 'prd-image-path) (write-to-string uploadedfiles :readably t))
	;; update the database with the new file upload paths.
	(update-prd-details  product))
      (incf state))))

(defun async-upload-files-s3bucket (images objectname object-id vendor)
  "把 images 列表里的每个文件上传到 S3，返回 URL 列表；当 *HHUBUSELOCALSTORFORRES* 为真
   时，仅返回本地路径 /img/<filename>。备注：函数名带 async 但目前是同步 mapcar。"
  (let ((vendor-id (slot-value vendor 'row-id))
	(tenant-id (slot-value vendor 'tenant-id)))
    (logiamhere (format nil "images to upload are ~A" images))
    (if (and images (> (length images) 0))
	(mapcar
	 (lambda (image)
	   (if *HHUBUSELOCALSTORFORRES* 
	       (format nil "/img/~A" image)
	       ;;else return the path of the uploaded file in S3 bucket.
	       (vendor-upload-file-s3bucket image objectname object-id vendor-id tenant-id))) images))))

     

(defun async-upload-images-for-bulk-upload (images objectname object-id vendor)
  "批量上传图片并生成 products-ven-<vendor-id>.csv 文件。
   每个图片 URL 计算 MD5 hash 写到 'Image Hash' 列（防篡改），最终生成的 CSV
   将作为 vendor 批量添加商品的模板基础。
   副作用：写文件到 ~/temp 路径（覆盖式）。"
  (let* ((header (list "Product ID" "Product Name " "Description" "Qty Per Unit" "Unit Of Measure" "Unit Price" "Discount" "Discount Start" "Discount End" "Units In Stock" "Subscription Flag" "Image Path (DO NOT MODIFY)" "Image Hash (DO NOT MODIFY)"))
	 (vendor-id (slot-value vendor  'row-id))
	 (tenant-id (slot-value vendor 'tenant-id))
	 (filepaths (mapcar
		     (lambda (image)
		       (if *HHUBUSELOCALSTORFORRES* 
			   (format nil "/img/~A" image)
			   ;;else return the path of the uploaded file in S3 bucket.
			   (vendor-upload-file-s3bucket image objectname object-id vendor-id tenant-id))) images))
	 (image-path-hashes (mapcar
			     (lambda (filepath)
			       (string-upcase (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :MD5 (ironclad:ascii-string-to-byte-array filepath))))) filepaths)))
    (with-open-file (stream (format nil "~A/temp/products-ven-~a.csv" *HHUBRESOURCESDIR* vendor-id)  
			    :direction :output
			    :if-exists :supersede
			    :if-does-not-exist :create)
      (format stream "~A"  (create-products-csv header filepaths image-path-hashes)))))

(defun create-products-csv (header imagepaths image-path-hashes)
  "生成空模板 CSV 字符串：第一行是表头；其后每行只填 Image Path / Hash 两列，
   其余字段留空，给 vendor 在 Excel 里补全。"
  (cl-who:with-html-output-to-string (*standard-output* nil)
      (mapcar (lambda (item) (cl-who:str (format nil "~A," item ))) header)
      (cl-who:str (format nil " ~C~C" #\return #\linefeed))
      (mapcar (lambda (imagepath imagehash)
		(cl-who:str (format nil ",,,,,,,,,,,~A,~A~C~C" imagepath imagehash #\return #\linefeed)))  imagepaths image-path-hashes)))


(defun modal.upload-csv-file ()
  "渲染 CSV 上传表单（multipart/form-data）。表单 action: dodvenuploadproductscsvfileaction。
   带 jQuery 上传进度条 'fileuploadprogress'。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-catch-file-upload-event "csvfileuploadevent"  
      (:form :class "hhub-formcsvfileupload"  :role "form" :method "POST" :action "dodvenuploadproductscsvfileaction" :data-bs-toggle "validator" :enctype "multipart/form-data" 
	     (:div :class "row"
		   (:div :id "fileuploadprogress" :class "form-group" "upload progress %")
		   (:div :class "form-group"
			 (:input :type "file" :id "idprdimgfileupldctrl" :name "uploadedcsvfile"))
		   (:div :class "form-group"
			 (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save")))))))

(defun com-hhub-transaction-vendor-bulk-products-add ()
  "批量添加商品控制器。需 vendor 会话；redirect-ui 模式：处理完成后跳转。
   关联 BL：create-product / update-prd-details。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vbulkproductsadd #'create-widgets-for-genericredirect)))

(defun create-model-for-vbulkproductsadd ()
  "解析上传的 CSV 文件 → 调 product-csv-file-data-row 把每行变成 (prd-instance, price-instance) ，
   再 create-bulk-products 写入数据库。with-hhub-transaction 包鉴权 + 审计。
   清缓存后重定向到 /hhub/dodvenproducts。"
  (let* ((csvfileparams (hunchentoot:post-parameter "uploadedcsvfile"))
	 (vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (params nil)
	 (redirecturl "/hhub/dodvenproducts")
	 (tempfilewithpath (nth 0 csvfileparams))
	 (prdandpriceinfo (remove nil (cl-csv:read-csv tempfilewithpath :skip-first-p T :map-fn #'product-csv-file-data-row))))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "prdcount" (length prdandpriceinfo) params))
    (setf params (acons "company" company params))
    (with-hhub-transaction "com-hhub-transaction-vendor-bulk-products-add" params
      (when (> (length prdandpriceinfo) 0)
	(create-bulk-products (function (lambda () prdandpriceinfo)))
	(dod-reset-vendor-products-functions vendor company)))
      (function (lambda ()
	(values redirecturl)))))


(defun product-csv-file-data-row (row)
  "解析 CSV 单行：跳过表头；其他行计算 expected-md5（第 11 列）vs computed-md5
   （归一化字段 → MD5）。当两者不同（说明该行被 vendor 修改过）时，构造
   dod-prd-master + dod-product-pricing 实例对返回；否则返回 nil
   （表示行未改动，跳过）。
   备注：approved-flag='N'，approval-status='PENDING' —— 新建商品需平台审批后上架。"
  (unless (string= (string-upcase (nth 0 row)) "PRODUCTID") ;; ignore the 1st row
    (let* ((expected-md5 (nth 10 row))
	   (computed-md5
             (create-md5-from-list
              (normalize-md5-fields
               (parse-integer (nth 0 row) :junk-allowed t)
               (nth 1 row)
	       (float (with-input-from-string (in (nth 2 row)) (read in)))
               (nth 3 row)
	       (float (with-input-from-string (in (nth 4 row)) (read in)))
	       (float (with-input-from-string (in (nth 5 row)) (read in)))
               (nth 6 row)
               (nth 7 row)
               (parse-integer (nth 8 row) :junk-allowed t)
               (nth 9 row))))
	   (vendor (get-login-vendor))
	   (vendor-id (get-login-vendor-id))
	   (company (get-login-vendor-company))
	   (tenant-id (get-login-vendor-tenant-id))
	   (prd-id (parse-integer (check-null (nth 0 row)) :junk-allowed t))
	   (prd-name (nth 1 row))
	   (qty-per-unit (float (with-input-from-string (in (nth 2 row)) (read in))))
	   (unit-of-measure (nth 3 row))
	   (prdinst (make-instance 'dod-prd-master
				   :row-id prd-id
				   :prd-name prd-name
				   :vendor-id vendor-id
				   :vendor vendor 
				   :qty-per-unit qty-per-unit 
				   :unit-of-measure unit-of-measure
				   :current-price (float (with-input-from-string (in (nth 4 row)) (read in)))
				   :current-discount (float (with-input-from-string (in (nth 5 row)) (read in)))
				   :units-in-stock  (parse-integer (nth 8 row))
				   :subscribe-flag (nth 9 row)
				   :sku (generate-sku prd-name prd-name qty-per-unit unit-of-measure)
				   :tenant-id tenant-id
				   :company company
				   :active-flag "Y"
				   :approved-flag "N"
				   :approval-status "PENDING"
				   :deleted-state "N"))
	   (priceinst (if prd-id
			  (make-instance 'dod-product-pricing
					 :product-id (nth 0 row)
					 :price (float (with-input-from-string (in (nth 4 row)) (read in)))
					 :discount (float (with-input-from-string (in (nth 5 row)) (read in)))
					 :start-date (get-date-from-string (nth 6 row))
					 :end-date (get-date-from-string (nth 7 row))))))
      (unless (equal expected-md5 computed-md5)
	(list prdinst priceinst)))))
  
(defun dod-controller-vendor-bulk-add-products-page ()
  :documentation "Here we are going to add products in bulk using CSV file. This page will display options of adding CSV files in two phases.
Phase1: Temporary Image URLs creation using image files upload.
Phase2: User should copy those URLs in Products.csv and then upload that file.
中文：vendor 批量加商品页（两阶段）：
   Phase 1：上传图片，得到临时 URL；
   Phase 2：把 URL 复制到 Products.csv 后再上传 CSV。
   需 vendor 会话；with-mvc-ui-page 渲染。"
  (with-vend-session-check
    (with-mvc-ui-page "Bulk Add Products using CSV File" #'create-model-for-vbulkaddproducts #'create-widgets-for-vbulkaddproducts :role :vendor)))

(defun create-model-for-vbulkaddproducts ()
  "返回 model 闭包，提供 vendor-id 给 widget 用于探测 CSV 模板文件是否已生成。"
  (let ((vendor-id (slot-value (get-login-vendor) 'row-id)))
    (function (lambda ()
      (values vendor-id)))))

(defun create-widgets-for-vbulkaddproducts (modelfunc)
  "渲染批量加商品页：3 步骤说明 + 生成模板按钮 + 模板下载链接（若已生成）+ CSV 上传 modal。"
  (multiple-value-bind (vendor-id) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (:br) (:br)
		       (:br) (:br)
		       (with-html-div-row
			 (with-html-div-col-6
			   (:ul :class "list-group"
				(:li :class "list-group-item" "Step 1: Download Products.csv Template")
				(:li :class "list-group-item" "Step 2: Fill up other required columns of Products.csv file")
				(:li :class "list-group-item" "Step 3: Upload the Products.csv file")))
			 
			 (:div :class "list-group col-xs-12 col-sm-6 col-md-6 col-lg-6" 
			       (with-catch-submit-event "idgeneratecsvbutton"
				 (with-html-form "generateproductcsvform" "generateproductcsvaction"
				   (with-html-submit-button "Generate & Download Products Template")))
			       ;; This download will be enabled when the file is ready for download. 
			       (if (probe-file (format nil "~A/temp/products-ven-~a.csv" *HHUBRESOURCESDIR* vendor-id))
				   (cl-who:htm (:a :href (format nil "/img/temp/products-ven-~a.csv" vendor-id) :class "list-group-item list-group-item-action" "Click here to download Products.csv"))) 
			       (:a :class "list-group-item list-group-item-action"  :data-bs-toggle "modal" :data-bs-target (format nil "#hhubvendprodcsvupload-modal")  :href "#"  " Upload Products CSV File")
			       ;; Modal dialog for CSV file upload
			       (modal-dialog-v2 (format nil "hhubvendprodcsvupload-modal") " Upload Products CSV File " (modal.upload-csv-file)))))))))
    (list widget1))))




(defun dod-controller-vendor-generate-products-templ ()
  "生成 vendor 商品 CSV 模板控制器（写到 ~/temp 目录，包含当前商品全量行）。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vgenprodcttempl #'create-widgets-for-genericredirect)))

(defun create-model-for-vgenprodcttempl ()
  "把 vendor 缓存中的商品列表序列化为 CSV，写到 *HHUBRESOURCESDIR*/temp/products-ven-<id>.csv。
   每行附 MD5Digest 列防纂改：上传时若 vendor 没改动该行，MD5 与服务端一致即跳过该行。"
  (let* ((header (list "ProductID" "ProductName" "QtyPerUnit" "UnitOfMeasure" "UnitPrice" "Discount" "DiscountStart" "DiscountEnd" "UnitsInStock" "SubscriptionFlag" "MD5Digest"))
	 (vendor (get-login-vendor))
	 (vendor-id (slot-value vendor  'row-id))
	 (productlist (hhub-get-cached-vendor-products))
	 (redirecturl "/hhub/venbulkaddprodpage"))
    (with-open-file (stream (format nil "~A/temp/products-ven-~a.csv" *HHUBRESOURCESDIR* vendor-id)  
			    :direction :output
			    :if-exists :supersede
			    :if-does-not-exist :create)
      (format stream "~A"  (create-products-csv2 header productlist)))
    (function (lambda ()
      (values redirecturl)))))

(defun create-products-csv2 (header productlist)
  "把 productlist 渲染成 CSV 字符串。每行：(row-id, prd-name, qty-per-unit, unit-of-measure,
   price, discount, start-date, end-date, units-in-stock, subscribe-flag, md5digest)。
   md5digest 由 normalize-md5-fields 保证字段格式一致后计算。"
  (cl-who:with-html-output-to-string (*standard-output* nil)
    (loop for item in header
          for last = (null (cdr (member item header))) ; check if it's the last item
          do (progn
               (cl-who:str (format nil "~A" item))
               (unless last
		 (cl-who:str ","))))
    (cl-who:str (format nil "~C~C" #\return #\linefeed))
  (mapcar (lambda (product)
	    (with-slots (row-id prd-name description qty-per-unit unit-of-measure current-price sku units-in-stock subscribe-flag) product
	      (let ((db-product-pricing (select-product-pricing-by-product-id row-id (product-company product))))
		(with-slots (price discount start-date end-date) db-product-pricing
		  (let* ((md5digest (create-md5-from-list (normalize-md5-fields row-id prd-name qty-per-unit unit-of-measure price discount (get-date-string start-date) (get-date-string end-date) units-in-stock subscribe-flag))))
		    (cl-who:str (format nil "~A,~A,~A,~A,~A,~A,~A,~A,~A,~A,~A~C~C" row-id prd-name  qty-per-unit unit-of-measure price discount (get-date-string start-date) (get-date-string end-date) units-in-stock subscribe-flag md5digest  #\return #\linefeed))))))) productlist)))

(defun normalize-md5-fields (row-id prd-name qty-per-unit unit-of-measure
                            price discount start-date end-date
                            units-in-stock subscribe-flag)
  "Normalize and format all product fields to consistent strings for MD5 calculation.
   中文：把数字字段强制 1/2 位小数，字符串 trim 空格，生成稳定的字符串列表，
   用作 md5 输入。下载/上传两侧只要顺序一致 + 内容一致，MD5 即一致。"
  (list
   (princ-to-string row-id)
   (string-trim " " prd-name)
   (format nil "~,1F" (coerce qty-per-unit 'float))      ; force 1 decimal place
   (string-trim " " unit-of-measure)
   (format nil "~,2F" (coerce price 'float))             ; force 2 decimal places
   (format nil "~,2F" (coerce discount 'float))          ; force 2 decimal places
   (string-trim " " start-date)
   (string-trim " " end-date)
   (princ-to-string units-in-stock)
   (string-trim " " subscribe-flag)))

;; ----------------------------------------------------------------------------
;; 段：vendor 档案更新对话框 / 收款配置对话框
;; ----------------------------------------------------------------------------
(defun modal.vendor-update-details ()
  "渲染 vendor 档案更新表单（POST hhubvendupdateaction，multipart 含头像上传）。
   表单字段：name / address / phone / email / state / zipcode / gstnumber / picture-path。"
  (let* ((vendor (get-login-vendor))
	 (name (name vendor))
	 (address (address vendor))
	 (phone  (phone vendor))
	 (zipcode (zipcode vendor))
	 (email (email vendor))
	 (gstnumber (gstnumber vendor))
	 (state (state vendor))
	 (picture-path (picture-path vendor)))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" :style "align: center"
	    (:div :class "col-sm-12 col-xs-12 col-md-6 col-lg-6 image-responsive"
		  (:img :src  (format nil "~A" picture-path) :height "300" :width "400" :alt name " ")))
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (:form :id (format nil "form-customerupdate")  :role "form" :method "POST" :action "hhubvendupdateaction" :enctype "multipart/form-data" 
					;(:div :class "account-wall"
		 
			 (:h1 :class "text-center login-title"  "Update Vendor Details")
		      (:div :class "form-group"
			    (:input :class "form-control" :name "name" :value name :placeholder "Customer Name" :type "text"))
		      (:div :class "form-group"
			    (:label :for "address")
			    (:textarea :class "form-control" :name "address"  :placeholder "Enter Address ( max 200 characters) "  :rows "2" :onkeyup "countChar(this, 200)" (cl-who:str (format nil "~A" address))))
		      (:div :class "form-group" :id "charcount")
		      (:div :class "form-group"
			    (:label :for "state" "Select State")
			    (with-html-dropdown "state" *NSTGSTSTATECODES-HT* state))
		      (:div :class "form-group"
			    (:input :class "form-control" :name "zipcode"  :value zipcode :placeholder "Pincode"  :type "text" ))
		      (:div :class "form-group"
			    (:input :class "form-control" :name "phone"  :value phone :placeholder "Phone"  :type "text" ))
		      (:div :class "form-group"
			    (:input :class "form-control" :name "email" :value email :placeholder "Email" :type "text"))
		      (:div :class "form-group"
			    (:input :class "form-control" :name "gstnumber" :value gstnumber :placeholder "GST Number" :type "text"))
		      
		      (:div :class "form-group" (:label :for "prodimage" "Select Picture:")
			    (:input :class "form-control" :name "picturepath" :placeholder "Picture" :type "file" ))
		      
		      (:div :class "form-group"
			    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))

(defun dod-controller-vendor-update-action ()
  "vendor 档案保存控制器（POST hhubvendupdateaction）。需 vendor 会话。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendorupdateaction #'create-widgets-for-genericredirect)))

(defun create-model-for-vendorupdateaction ()
  "解析表单字段（含头像 picturepath multipart）→ 写回 vendor slot →
   update-vendor-details 落库；头像保存到 *HHUBRESOURCESDIR*，picture-path
   写为 /img/<filename>。返回 redirecturl=/hhub/dodvendprofile。"
  (let* ((name (hunchentoot:parameter "name"))
	 (address (hunchentoot:parameter "address"))
	 (phone (hunchentoot:parameter "phone"))
	 (zipcode (hunchentoot:parameter "zipcode"))
	 (state (hunchentoot:parameter "state"))
	 (gstnumber (hunchentoot:parameter "gstnumber"))
	 (email (hunchentoot:parameter "email"))
	 (vendor (get-login-vendor))
	 (prodimageparams (hunchentoot:post-parameter "picturepath"))
	 (tempfilewithpath (first prodimageparams))
	 (file-name (if tempfilewithpath (process-file prodimageparams *HHUBRESOURCESDIR*)))
	 (redirecturl "/hhub/dodvendprofile"))

    (logiamhere (format nil "picturepath is ~A" (hunchentoot:post-parameters*)))
    (setf (slot-value vendor 'name) name)
    (setf (slot-value vendor 'address) address)
    (setf (slot-value vendor 'phone) phone)
    (setf (slot-value vendor 'state) state)
    (setf (slot-value vendor 'zipcode) zipcode)
    (setf (slot-value vendor 'gstnumber) gstnumber)
    (setf (slot-value vendor 'email) email)
    (if tempfilewithpath (setf (slot-value vendor 'picture-path) (format nil "/img/~A"  file-name)))
    (update-vendor-details vendor)
    (function (lambda ()
      (values redirecturl)))))


(defun modal.vendor-update-UPI-payment-settings-page ()
  "渲染 vendor UPI 设置表单（POST hhubvendupdateupisettings；唯一字段 vendor-upi-id）。"
  (let* ((vendor (get-login-vendor))
	 (vendor-upi-id (slot-value vendor 'upi-id)))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	(:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
	  (:form :id (format nil "form-vendorupisettings")  :role "form" :method "POST" :action "hhubvendupdateupisettings" :enctype "multipart/form-data" 
	     (:div :class "form-group"
		   (:label :for "vendor-upi-id" "UPI ID")
		   (:input :class "form-control" :name "vendor-upi-id" :value vendor-upi-id  :placeholder "Vendor UPI ID" :type "text"))
	     (:div :class "form-group"
			       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))

(defun hhub-controller-save-vendor-upi-settings ()
  "vendor UPI 保存控制器（hhubvendupdateupisettings）。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendorupisettings #'create-widgets-for-genericredirect)))

(defun create-model-for-vendorupisettings ()
  "更新 vendor.upi-id 并 update-vendor-details。空字符串忽略不写。"
  (let* ((upi-id (hunchentoot:parameter "vendor-upi-id"))
	 (vendor (get-login-vendor))
	 (redirecturl "/hhub/dodvendprofile"))
    
    (when (> (length upi-id) 0)
      (setf (slot-value vendor 'upi-id) upi-id)
      (update-vendor-details vendor))
    (function (lambda ()
      (values redirecturl)))))

      
(defun modal.vendor-payment-methods-page (vpaymentmethods)
  "渲染 vendor 支付方式开关表单。
   - 若 vpaymentmethods 是 VPaymentMethods：展示 5 个 checkbox
     (codenabled / upienabled / walletenabled / payprovidersenabled / paylaterenabled)，
     POST 到 hhubvpmupdateaction。
   - 若是 BusinessObjectNIL（不存在）：展示 'Create Vendor Payment Methods' 按钮，
     携带 createvpaymentmethods=Y 给后端走创建路径。"
  (when (typep vpaymentmethods 'VPaymentMethods)
    (let* ((codenabled (slot-value vpaymentmethods 'codenabled))
	   (upienabled (slot-value vpaymentmethods 'upienabled))
	   (walletenabled (slot-value vpaymentmethods 'walletenabled))
	   (payprovidersenabled (slot-value vpaymentmethods 'payprovidersenabled))
	   (paylaterenabled (slot-value vpaymentmethods 'paylaterenabled)))
      (cl-who:with-html-output (*standard-output* nil)
	(:div :class "row" 
	      (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		    (with-html-form "form-vendpaymentmethodsupdate" "hhubvpmupdateaction"
		      (if (equal codenabled "Y")
			  (with-html-custom-checkbox "codenabled" codenabled "Cash On Demand" T )
			  ;;else
			  (with-html-custom-checkbox "codenabled" "N" "Cash On Demand" NIL))
		      
		      (if (equal upienabled "Y")
			  (with-html-custom-checkbox "upienabled" upienabled "UPI" T)
			;;else
			  (with-html-custom-checkbox "upienabled" "N" "UPI" nil))
		      
		      (if (equal walletenabled "Y")
			  (with-html-custom-checkbox "walletenabled" walletenabled "Prepaid Wallet" T)
			;;else
			  (with-html-custom-checkbox "walletenabled" "N" "Prepaid Wallet" NIL))
		      
		      (if (equal payprovidersenabled "Y")
			  (with-html-custom-checkbox "payprovidersenabled" payprovidersenabled "Payment Gateway (Details must be defined!)" T)
			  ;;else
			(with-html-custom-checkbox "payprovidersenabled" "N" "Pay Providers" nil))
		      
		      (if (equal paylaterenabled "Y")
			  (with-html-custom-checkbox "paylaterenabled" paylaterenabled "Pay Later" T)
			  ;;else
			  (with-html-custom-checkbox "paylaterenabled" "N" "Pay Later" nil))
		      (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save Settings")))))))
  ;; If Vendor payment methods are not found then create one
  (when (typep vpaymentmethods 'BusinessObjectNIL)
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row"
            (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
                  (with-html-form  "form-vendpaymentmethodscreate" "hhubvpmupdateaction"
                    (:div :class "form-group"
			  (with-html-input-text-hidden "createvpaymentmethods" "Y")
			  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Create Vendor Payment Methods"))))))))


(defun dod-controller-vendor-payment-methods-update-action ()
  "vendor 支付方式开关保存/创建控制器（hhubvpmupdateaction）。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendpaymentmethodsupdate #'create-widgets-for-genericredirect)))

(defun create-model-for-vendpaymentmethodsupdate ()
  "把 5 个 checkbox 表单值（缺省为 nil = 'N'）拼成 VPaymentMethodsRequestModel。
   - createvpaymentmethods='Y' 时走 with-entity-create（首次创建，5 项默认全 'Y'）；
   - 否则 with-entity-update（按表单值更新）。
   均成功后跳转 /hhub/dodvendprofile。"
  (let* ((codenbld (hunchentoot:parameter "codenabled"))
	 (upienbld (hunchentoot:parameter "upienabled"))
	 (walletenbld (hunchentoot:parameter "walletenabled"))
	 (payprovidersenbld (hunchentoot:parameter "payprovidersenabled"))
	 (paylaterenbld (hunchentoot:parameter "paylaterenabled"))
	 (createvpaymentmethods (hunchentoot:parameter "createvpaymentmethods"))
	 (company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (requestmodel (make-instance 'VPaymentMethodsRequestModel
				      :vendor vendor
				      :company company
				      :codenabled "Y"
				      :upienabled "Y"
				      :payprovidersenabled "Y"
				      :walletenabled "Y"
				      :paylaterenabled "Y"))
	 (redirecturl "/hhub/dodvendprofile"))
    
    (when (equal createvpaymentmethods "Y")
      (with-entity-create 'VPaymentMethodsAdapter requestmodel
	(if entity (setf redirecturl "/hhub/dodvendprofile"))))
    (unless (equal createvpaymentmethods "Y")
      ;; we are in update case now.
      (with-slots (codenabled upienabled payprovidersenabled walletenabled paylaterenabled) requestmodel
	(if codenbld (setf codenabled codenbld) (setf codenabled "N"))
	(logiamhere (format nil "value of codenabled is ~A" codenbld))
	(if upienbld (setf upienabled upienbld) (setf upienabled "N")) 
	(if payprovidersenbld (setf payprovidersenabled payprovidersenbld) (setf payprovidersenabled "N"))
	(if walletenbld (setf walletenabled walletenbld) (setf walletenabled "N"))
	(if paylaterenbld (setf paylaterenabled paylaterenbld) (setf paylaterenabled "N"))
	(with-entity-update 'VPaymentMethodsAdapter requestmodel
	  (if entity
	      (setf redirecturl "/hhub/dodvendprofile")))))
    (function (lambda ()
      (values redirecturl)))))

(defun modal.vendor-update-payment-gateway-settings-page ()
  "渲染 vendor 支付网关设置表单（POST hhubvendupdatepgsettings）。
   字段：payment-api-key、payment-api-salt、pg-mode（test / live）。
   头部带 Tyche Payments 商户账户注册链接。"
  (let* ((vendor (get-login-vendor))
	 (payment-api-key (payment-api-key vendor))
	 (payment-api-salt (payment-api-salt vendor))
	 (pg-mode (slot-value vendor 'payment-gateway-mode)))
       
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row
	(:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
	(:a  :target "_blank"  :data-bs-toggle "tooltip" :title "Create a Merchant account with our payment partner Tyche Payments. Click here."  :href "https://www.tychepayment.com/merchantform.php" (:i :class "fa-solid fa-circle-info"))))
	
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (:form :id (format nil "form-vendorpaymentgatewayupdate")  :role "form" :method "POST" :action "hhubvendupdatepgsettings" :enctype "multipart/form-data" 
					;(:div :class "account-wall"
			 (:div :class "form-group"
			       (:label :for "payment-api-key" "Payment API Key")
			       (:input :class "form-control" :name "payment-api-key" :value payment-api-key :placeholder "Payment API Key" :type "text"))
			 (:div :class "form-group"
			       (:label :for "payment-api-salt" "Payment API Salt")
			       (:input :class "form-control" :name "payment-api-salt"  :value payment-api-salt :placeholder "Payment API Salt"  :type "text" ))
			 (:div :class "form-group"
			       (:label :for "pg-mode" "Payment Gateway Mode"
				       (payment-gateway-mode-options pg-mode)))
			 
			 (:div :class "form-group"
			       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))



;; @@ deprecated : start using with-html-dropdown instead.
(defun payment-gateway-mode-options (selectedkey)
  "已弃用：渲染 pg-mode 下拉框（test/live）。建议改用 with-html-dropdown。"
  (let ((pg-mode (make-hash-table)))
    (setf (gethash "test" pg-mode) "test") 
    (setf (gethash "live" pg-mode) "live")
    (with-html-dropdown "pg-mode" pg-mode selectedkey)))


(defun dod-controller-vendor-update-payment-gateway-settings-action ()
  "vendor 支付网关 + 推送订阅状态保存（hhubvendupdatepgsettings）。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendupdatepgsettings #'create-widgets-for-genericredirect)))

(defun create-model-for-vendupdatepgsettings ()
  "更新 vendor 支付网关参数（payment-api-key/-salt/payment-gateway-mode）以及
   push-notify-subs-flag（缺省 'N'）。回跳 /hhub/dodvendprofile。"
  (let* ((payment-api-key (hunchentoot:parameter "payment-api-key"))
	 (payment-api-salt (hunchentoot:parameter "payment-api-salt"))
	 (pg-mode  (hunchentoot:parameter "pg-mode"))
	 (vpushnotifysubs (hunchentoot:parameter "vpushnotifysubs"))
	 (vendor (get-login-vendor))
	 (redirecturl "/hhub/dodvendprofile"))
    (setf (slot-value vendor 'payment-api-key) payment-api-key)
    (setf (slot-value vendor 'payment-api-salt) payment-api-salt)
    (setf (slot-value vendor 'payment-gateway-mode) pg-mode)
    (setf (slot-value vendor 'push-notify-subs-flag) (if (null vpushnotifysubs) "N" vpushnotifysubs))
    (update-vendor-details vendor)
    (function (lambda ()
      (values redirecturl)))))


;; ----------------------------------------------------------------------------
;; 段：vendor 修改密码 / 重置密码 / 忘记密码
;; ----------------------------------------------------------------------------
(defun modal.vendor-change-pin ()
  "渲染修改密码表单（POST hhubvendchangepin）。client 端用 data-match 校验
   newpassword == confirmpassword（最少 8 位）。"
  (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form "form-vendorchangepin" "hhubvendchangepin"  
					;(:div :class "account-wall"
			 (:h1 :class "text-center login-title"  "Change Password")
			 (:div :class "form-group"
			       (:label :for "password" "Password")
			       (:input :class "form-control" :name "password" :value "" :placeholder "Old Password" :type "password" :required T))
			 (:div :class "form-group"
			       (:label :for "newpassword" "New Password")
			       (:input :class "form-control" :id "newpassword" :data-minlength "8" :name "newpassword" :value "" :placeholder "New Password" :type "password" :required T))
			 (:div :class "form-group"
			       (:label :for "confirmpassword" "Confirm New Password")
			       (:input :class "form-control" :name "confirmpassword" :value "" :data-minlength "8" :placeholder "Confirm New Password" :type "password" :required T :data-match "#newpassword"  :data-match-error "Passwords dont match"  ))
			 (:div :class "form-group"
			       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save")))))))




(defun dod-controller-vendor-change-pin ()
  "vendor 修改密码控制器。先用 check-password 验证旧密码（结合现 salt），
   再用 check&encrypt 加密新密码（newpassword==confirmpassword 校验）。
   验证失败返回 dod-response-passwords-do-not-match-error，
   成功则更新 vendor 密码 + salt 并跳到 /hhub/dodvendprofile。"
  (with-vend-session-check
    (let* ((password (hunchentoot:parameter "password"))
	   (newpassword (hunchentoot:parameter "newpassword"))
	   (confirmpassword (hunchentoot:parameter "confirmpassword"))
	   (salt (createciphersalt))
	   (encryptedpass (check&encrypt newpassword confirmpassword salt))
	   (vendor (get-login-vendor))
	   (present-salt (if vendor (slot-value vendor 'salt)))
	   (present-pwd (if vendor (slot-value vendor 'password)))
	   (password-verified (if vendor  (check-password password present-salt present-pwd))))
     (cond 
       ((or
	 (not password-verified) 
	 (null encryptedpass)) (dod-response-passwords-do-not-match-error)) 
       ((and password-verified encryptedpass) (progn 
       (setf (slot-value vendor 'password) encryptedpass)
       (setf (slot-value vendor 'salt) salt) 
       (update-vendor-details vendor)
       (hunchentoot:redirect "/hhub/dodvendprofile")))))))



;; ----------------------------------------------------------------------------
;; 段：vendor 订单 / 营收 / 客户列表
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-customer-list ()
  "vendor 自己的客户列表页（来自钱包 dod-cust-wallet 反查 customer）。
   渲染 4 列表（Name / Mobile / Email / Actions），每行调 vendor-customers-card。"
  (with-vend-session-check
    (let* ((wallets (get-cust-wallets-for-vendor (get-login-vendor) (get-login-vendor-company)))
	   (customers (mapcar (lambda (wallet) 
			   (get-customer wallet)) wallets)))
      (with-standard-vendor-page  "Customers list for vendor" 
	(cl-who:str (display-as-table (list "Name" "Mobile" "Email" "Actions") customers 'vendor-customers-card))))))
 

  

(defun dod-controller-vendor-order-cancel ()
  "vendor 取消订单控制器。按 id 取主单 dod-order，再调 cancel-order-by-vendor 取消
   该 vendor 的子单，回跳 /hhub/dodvendindex?context=pendingorders。"
 (with-vend-session-check
  (let* ((id (hunchentoot:parameter "id"))
	(order (get-order-by-id id (get-login-vendor-company)))
	(order-id (slot-value order 'row-id)))
    (cancel-order-by-vendor (get-vendor-order-instance order-id (get-login-vendor)))
    (hunchentoot:redirect "/hhub/dodvendindex?context=pendingorders"))))


(defun dod-controller-vendor-revenue ()
  "vendor 当日营收页：从缓存拉今日完成订单，sum order-amt → 显示总额 + tile 卡片。"
(with-vend-session-check
    ;list all the completed orders for Today. 
    (let* ((todaysorders (dod-get-cached-completed-orders-today))
	   (total (if todaysorders (reduce #'+ (mapcar (lambda (ord) (slot-value ord 'order-amt)) todaysorders)))))
    (with-standard-vendor-page "Welcome to DAS Platform- Vendor"
      (:div :class "row"
	    (:div :class "col-xs-12 col-sm-4 col-md-4 col-lg-4" 
		  "Completed orders "
		  (:span :class "badge" (cl-who:str (format nil " ~d " (length todaysorders))))) 
	    (:div :class  "col-xs-12 col-sm-4 col-md-4 col-lg-4"  :align "right" (:h1(:span :class "label label-default" "Todays Revenue")))	  
      (:div :class  "col-xs-12 col-sm-4 col-md-4 col-lg-4"  :align "right" 
	    (:h2 (:span :class "label label-default" (cl-who:str (format nil "Total = Rs ~$" total))))))
      (:hr)
      (cl-who:str (display-as-tiles todaysorders 'vendor-order-card "order-box" ))))))


 
(defun dod-controller-refresh-pending-orders ()
  "刷新 vendor 待处理订单缓存（dod-reset-order-functions），跳回订单列表。"
  (with-vend-session-check
      (progn 
	(dod-reset-order-functions (get-login-vendor) (get-login-vendor-company))
	(hunchentoot:redirect "/hhub/dodvendindex?context=pendingorders"))))

;; ----------------------------------------------------------------------------
;; 段：vendor 多 tenant 管理 —— 列表 / 搜索 / 添加 / 切换
;; ----------------------------------------------------------------------------
(defun dod-controller-display-vendor-tenants ()
  "显示当前 vendor 已加入的所有 tenant（公司）。
   会话失效时跳到 /hhub/vendor-login.html。"
  (if (is-dod-vend-session-valid?)
      (let* ((vendor-company (get-login-vendor-company))
	     (cmplist (hunchentoot:session-value :login-vendor-tenants)))
	   
	(with-standard-vendor-page "Welcome to DAS Platform - Vendor"
	  (:a :class "btn btn-primary" :role "button" :href "dodvendsearchtenantpage" (:i :class "fa-solid fa-users-line") " Add New Group  ")
	  (:hr)
	  (:h5 (cl-who:str (format nil "Currently Logged Into Group - ~A" (slot-value vendor-company 'name))))
	  (:div :class "list-group col-sm-6 col-md-6 col-lg-6"
	 (if cmplist (mapcar (lambda (cmp)
			       (unless (equal (slot-value vendor-company 'name)  (slot-value cmp 'name))
	    (cl-who:htm  (:a :class "list-group-item" :href (format nil "dodvendswitchtenant?id=~A"  (slot-value cmp 'row-id)) (cl-who:str (format nil "Login to ~A " (slot-value cmp 'name))))
		  ))) cmplist)))))
      (hunchentoot:redirect "/hhub/vendor-login.html")))




(defun dod-controller-cmpsearch-for-vend-page ()
  "搜索可加入的 tenant（公司）页面。会话失效时跳 hhubvendloginv2。
   live search 框 id=livesearch，POST dodvendsearchtenantaction。"
  (if (is-dod-vend-session-valid?)
      (with-standard-vendor-page  "Welcome to DAS platform" 
	(:div :class "row"
	      (:h2 "Search Apartment/Group")
	      (:div :id "custom-search-input"
		    (:div :class "input-group col-md-12"
			  (:form :id "theForm" :action "dodvendsearchtenantaction" :OnSubmit "return false;" 
				 (:input :type "text" :class "  search-query form-control" :id "livesearch" :name "livesearch" :placeholder "Search for an Apartment/Group"))
			  (:span :class "input-group-btn" (:button :class "btn btn-danger" :type "button" 
								(:i :class "fa-solid fa-binoculars")))))
	      (:div :id "searchresult" "")))
      (hunchentoot:redirect "/hhub/hhubvendloginv2")))





(defun dod-controller-cmpsearch-for-vend-action ()
  "搜索 ajax 入口：拿 livesearch 关键词调 select-companies-by-name；剔除
   'vendor 已经加入的 tenant + 当前登录 tenant'，结果给 ui-list-cmp-for-vend-tenant 渲染。"
  (let*  ((qrystr (hunchentoot:parameter "livesearch"))
	  (matching-tenants-list (if (not (equal "" qrystr)) (select-companies-by-name qrystr)))
	  (existing-tenants-list (append (get-vendor-tenants-as-companies (get-login-vendor)) (list (get-login-vendor-company))))
	  (final-list (set-difference matching-tenants-list existing-tenants-list :test #'equal-companiesp)))
    (ui-list-cmp-for-vend-tenant final-list)))



(defun ui-list-cmp-for-vend-tenant (company-list)
  "把可加入的公司列表渲染为按钮网格；点击按钮提交 dodvendaddtenantaction
   表单（以公司名 cname 隐藏字段）。空列表显示 'No records found'。"
  (cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
  ; (standard-customer-page (:title "Welcome to DAS Platform")
    (if company-list 
	(cl-who:htm (:div :class "row-fluid"
			  (mapcar (lambda (cmp)
				    (cl-who:htm 
				     (:form :method "POST" :action "dodvendaddtenantaction" :id "dodvendaddtenantform" 
					    (:div :class "col-sm-4 col-lg-3 col-md-4"
						  (:div :class "form-group"
							(:input :class "form-control" :name "cname" :type "hidden" :value (cl-who:str (format nil "~A" (slot-value cmp 'name)))))
						  
						  (:div :class "form-group"
							(:button :class "btn btn-lg btn-primary btn-block" :type "submit" (cl-who:str (format nil "~A" (slot-value cmp 'name)))))))))  company-list)))
					;else
	(cl-who:htm (:div :class "col-sm-12 col-md-12 col-lg-12"
			  (:h3 "No records found"))))))

(defun dod-controller-vend-add-tenant-action ()
  "把当前 vendor 加入选中的 tenant（cname → select-company-by-name → create-vendor-tenant，
   default-flag='N'）。需 vendor 会话。"
  (with-vend-session-check
    (let* ((cname (hunchentoot:parameter "cname"))
	   (company (select-company-by-name cname)))
      (create-vendor-tenant (get-login-vendor) "N"  company))))


;; ----------------------------------------------------------------------------
;; 段：vendor 添加新商品页 / SKU 生成器对话框
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-add-product-page ()
  "vendor 添加新商品页（含 SKU 生成器 modal、HSN/SAC 输入、UOM 下拉）。需 vendor 会话。"
  (with-vend-session-check
    (with-mvc-ui-page "Add New Product/Service" #'createmodelforvendoraddnewproduct #'createwidgetsforvendoraddnewproduct :role :vendor)))

(defun createmodelforvendoraddnewproduct ()
  "返回闭包：(values 商品分类列表 字符计数器 id)。计数器 id 用随机后缀避免页面冲突。"
  (let ((catglist (hhub-get-cached-product-categories))
	(charcountid1 (format nil "idchcount~A" (hhub-random-password 3))))
    (function (lambda ()
      (values catglist charcountid1)))))

(defun createwidgetsforvendoraddnewproduct (modelfunc)
  "渲染添加商品表单 widget。表单字段含 prdname / description / prdprice /
   unitsinstock / qtyperunit / unitofmeasure / sku / hsncode / prodcatg /
   subscriptionflag(yesno) / isserviceproduct。
   action: dodvenaddproductaction（最终 com-hhub-transaction-vendor-product-add-action）。"
  (multiple-value-bind (catglist charcountid1) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-12
			   (:img :class "profile-img" :src "/img/logo.png" :alt "")
			   (:h1 :class "text-center login-title"  "Add new product")
			   (with-html-form-having-submit-event "form-vendorprodadd" "dodvenaddproductaction"
			     (:div :class "form-group"
				   (:input :class "form-control" :name "prdname" :placeholder "Enter Product Name ( max 30 characters) " :required t :type "text" ))
			     (:div :class "form-group"
				   (:label :for "description")
				   (:textarea :class "form-control" :name "description" :placeholder "Enter Product Description ( max 1000 characters) "  :required t :rows "5" :onkeyup (format nil "countChar(~A.id, this, 1000)" charcountid1)))
			     (:div :class "form-group" :id charcountid1)
			     (with-html-input-text-hidden "prd-id" "0") ;; we are adding a new product hence prd-id is 0
			     (:div :class "form-group"
				   (:label :for "prdprice" "Product Price")
				   (:input :class "form-control" :id "prdprice" :name "prdprice" :placeholder "Price" :required t :value 1.00 :type "number" :min "0.00" :max "10000.00" :step "0.01" ))
			     (:div :class "form-group"
				   (:label :for "unitsinstock" "Units In Stock")
				   (:input :class "form-control" :id "unitsinstock" :name "unitsinstock" :placeholder "Units In Stock"  :value "100" :type "number" :min "1" :max "10000" :step "1" ))
			     (:div :class "form-group"
				   (:label :for "qtyperunit" "Quantity Per Unit")
				   (:input :class "form-control" :id "qtyperunit" :name "qtyperunit" :placeholder "Qty Per Unit"  :value 1 :type "number" :min "1" :max "10000" :step "1" ))
			     (:div :class "form-group"
				   (:label :for "unitofmeasure" "Unit Of Measure")
				   (with-html-dropdown "unitofmeasure" (get-system-UOM-map) "KG"))
			     (:a :data-bs-toggle "modal" :data-bs-target (format nil "#generatesku-modal")  :href "#"  (:i :class "fa-solid fa-wand-magic-sparkles"))
			     
			     (:div :class "form-group"
				   (:label :for "sku" "SKU")
				   (:input :class "form-control" :id "sku" :name "sku" :placeholder "SKU" :value "000000" :type "text" ))
			     (:div :class "form-group"
				      (:label :for "hsncode" "HSN/SAC Code")
				   (:input :class "form-control" :id "hsncode" :name "hsncode" :placeholder "HSN Code" :value "000000" :type "text" ))
			     (:div  :class "form-group" (:label :for "prodcatg" "Select Produt Category:" )
				    (ui-list-prod-catg-dropdown catglist nil))
			     (:div :class "form-group" (:label :for "yesno" "Enable Subscription")
				   (ui-list-yes-no-dropdown "N"))
			     (:div :class "form-group"
				   (with-html-custom-checkbox "isserviceproduct" "N" "Mark as Service Product" nil))
			     (:div :class "form-group"
				   (:input :class "btn btn-lg btn-primary btn-block" :name "submit" :type "submit" :value "Save")))
			   (modal-dialog-v2 (format nil "generatesku-modal") "SKU Generator" (modal.generate-sku-dialog)))))))))
      (list widget1))))



(defun modal.generate-sku-dialog ()
  "渲染 SKU 生成器对话框（gensku.js 在前端生成）。表单字段：productName /
   productDescription / qtyperunit / unitOfMeasure；按钮 generateSkuBtn / copySkuBtn。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "input-group"
	  (with-html-input-text "productName" "Product Name" "Enter Product Name" "" T "Enter Product Name" 1))
    (:div :class "input-group"
	  (with-html-input-text "productDescription" "Product Description" "Enter Product Description" "" T "Enter Product Description" 2))
    (:div :class "input-group"
	  (with-html-input-number "qtyperunit" "Qty Per Unit" "Quantity Per Unit" "" 1 10000 t "Enter a number" 3)) 
    (:div :class "form-group"
	  (:label :for "unitofmeasure" "Unit Of Measure")
	  (with-html-dropdown "unitOfMeasure" (get-system-UOM-map) "KG"))
    (:div :class "input-group"
	  (with-html-input-text-readonly "generatedSku" "Generated SKU" "Generated SKU" "" T "Generated SKU" 4))
  (:button :class "btn btn-outline-secondary mr-1" :type "button" :id "copySkuBtn" (:i :class "fa fa-clipboard") "&nbsp;Copy&nbsp;")
  (:button :class "btn btn-primary" :type "button" :id "generateSkuBtn" "Generate SKU")
  (:script :src (format nil "~A/js/gensku.js" *siteurl*))))


;; ----------------------------------------------------------------------------
;; 段：S3 文件上传 / 删除（通过 Node fileserver 代理）
;; ----------------------------------------------------------------------------
(defun vendor-upload-file-s3bucket (filename objectname object-id vendor-id tenant-id)
  :description "Sends the filename and other parameters to the node js file server, which will upload the file to s3 bucket and return the url.
   中文：用 drakma 把文件上传请求转发给 Node 文件服务（/file/awss3v3/upload）。
   header 'auth-secret: ntstores1234' 是与 fileserver 的共享密钥。
   uuid 由 lisp 端生成（V1）作为对象唯一名。"
  (let* ((uuid (format nil "~A" (uuid:make-v1-uuid)))
	 (vendorid-str (format nil "~A" vendor-id))
	 (tenantid-str (format nil "~A" tenant-id))
	 (objectid-str (format nil "~A" object-id))
	 (type "vendor")
	 (paramnames (list "tenantid" "type" "vendorid" "objectname" "objectid" "uuid" "filename"))
         (paramvalues (list tenantid-str type vendorid-str objectname objectid-str uuid filename))
         (param-alist (pairlis paramnames paramvalues))
         (headers nil)
	 (url (format nil "~A/file/awss3v3/upload" *siteurl*))
         (headers (acons "auth-secret" "ntstores1234" headers)))   
    (drakma:http-request url
			      :method :get
			      :additional-headers headers
			      :parameters param-alist)))
 

(defun vendor-delete-files-s3bucket (objectname object-id vendor-id tenant-id)
  :description "Sends the filename and other parameters to the node js file server, which will delete the file to s3 bucket and return the url.
   中文：DELETE 请求 Node 文件服务 /file/awss3v3/deletefiles 删除该
   (tenant, vendor, object) 组合下的全部 S3 文件。"
  (let* ((vendorid-str (format nil "~A" vendor-id))
	 (tenantid-str (format nil "~A" tenant-id))
	 (objectid-str (format nil "~A" object-id))
	 (type "vendor")
	 (paramnames (list "tenantid" "type" "vendorid" "objectname" "objectid"))
         (paramvalues (list tenantid-str type vendorid-str objectname objectid-str))
         (param-alist (pairlis paramnames paramvalues))
         (headers nil)
	 (url (format nil "~A/file/awss3v3/deletefiles" *siteurl*))
         (headers (acons "auth-secret" "ntstores1234" headers)))   
    (drakma:http-request url
			 :method :DELETE 
			 :additional-headers headers
			 :parameters param-alist)))


;; ----------------------------------------------------------------------------
;; 段：商品物流信息（尺寸 / 重量）维护
;; ----------------------------------------------------------------------------
(defun com-hhub-transaction-vend-prd-shipinfo-add-action ()
  "更新商品 shipping 长宽高 + 重量控制器。仅当 vendor.shipping-enabled='Y' 时实际写库。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vprodshipinfoaddaction #'create-widgets-for-genericredirect)))


(defun create-model-for-vprodshipinfoaddaction()
  "解析 shipping-length-cms / shipping-width-cms / shipping-height-cms / shipping-weight-kg
   写入 product slot 后 update-prd-details，清缓存，跳到商品详情页。"
  (let* ((vendor (get-login-vendor))
	 (shipping-enabled (slot-value vendor 'shipping-enabled))
	 (id (hunchentoot:parameter "id"))
	 (product (if id (select-product-by-id id (get-login-vendor-company))))
	 (shipping-length-cms (parse-integer (hunchentoot:parameter "shipping-length-cms")))
	 (shipping-width-cms (parse-integer (hunchentoot:parameter "shipping-width-cms")))
	 (shipping-height-cms (parse-integer (hunchentoot:parameter "shipping-height-cms")))
	 (shipping-weight-kg (float (with-input-from-string (in (hunchentoot:parameter "shipping-weight-kg"))
				      (read in))))
	 (redirecturl (format nil "/hhub/dodprddetailsforvendor?id=~A" id))
	 (params nil))
    (setf params (acons "company" (get-login-vendor-company) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (setf params (acons "vendor" (get-login-vendor)  params))
    (with-hhub-transaction "com-hhub-transaction-vend-prd-shipinfo-add-action" params
      (when (and shipping-enabled  product) 
	(setf (slot-value product 'shipping-length-cms) shipping-length-cms)
	(setf (slot-value product 'shipping-width-cms) shipping-width-cms)
	(setf (slot-value product 'shipping-height-cms) shipping-height-cms)
	(setf (slot-value product 'shipping-weight-kg) shipping-weight-kg)
	(update-prd-details product)
	(dod-reset-vendor-products-functions vendor (get-login-vendor-company))))
	(function (lambda ()
	  (values redirecturl)))))


(defun com-hhub-transaction-vendor-product-add-action ()
  "添加/编辑商品控制器。需 vendor 会话；redirect-ui 模式。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vprodaddaction #'create-widgets-for-genericredirect)))

(defun create-model-for-vprodaddaction ()
  "解析表单字段：prdname / prd-id / description / hsn-code / sku / upc /
   isserviceproduct / qtyperunit / unitofmeasure / unitsinstock / prodcatg /
   subscriptionflag(yesno)。
   - prd-id=0 视为新建：调 create-product；
   - prd-id>0 视为编辑：根据 productlist 找到 product 后逐字段覆盖再
     update-prd-details，并 generate-product-ext-url 生成对外 URL。
   走 with-hhub-transaction 带 mode=add/edit 审计。"
  (let* ((prodname (hunchentoot:parameter "prdname"))
	 (prd-id (parse-integer (hunchentoot:parameter "prd-id")))
	 (vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (productlist (if (> prd-id 0) (hhub-get-cached-vendor-products)))
	 (product (if (> prd-id 0) (search-item-in-list 'row-id prd-id productlist)))
	 (description (hunchentoot:parameter "description"))
	 (hsn-code (hunchentoot:parameter "hsn-code"))
	 (sku (hunchentoot:parameter "sku"))
	 (upc (hunchentoot:parameter "upc"))
	 (isserviceproduct (hunchentoot:parameter "isserviceproduct"))
	 (prd-type (if (equal isserviceproduct "Y") "SERV" "SALE")) 
	 (qtyperunit (float (with-input-from-string (in (hunchentoot:parameter "qtyperunit"))
			     (read in))))
	 (unit-of-measure (hunchentoot:parameter "unitofmeasure"))
	 (units-in-stock (parse-integer (hunchentoot:parameter "unitsinstock")))
	 (catg-id (parse-integer (hunchentoot:parameter "prodcatg")))
	 (subscriptionflag (hunchentoot:parameter "yesno"))
	 (external-url (if product (generate-product-ext-url product)))
	 (redirecturl nil)
	 (params nil))
    (if product
	(setf params (acons "mode" "edit" params))
	;;else
	(setf params (acons "mode" "add" params)))

    (setf params (acons "company" company params))
    (setf params (acons "vendor" vendor params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-vendor-product-add-action" params 
      (progn 
	(if product 
	    (progn
	      (setf (slot-value product 'prd-name) prodname)
	      (setf (slot-value product 'description) description)
	      (setf (slot-value product 'catg-id) catg-id)
	      (setf (slot-value product 'qty-per-unit) qtyperunit)
	      (setf (slot-value product 'unit-of-measure) unit-of-measure)
	      (setf (slot-value product 'units-in-stock) units-in-stock)
	      (setf (slot-value product 'subscribe-flag) subscriptionflag)
	      (setf (slot-value product 'external-url) external-url)
	      (setf (slot-value product 'prd-type) prd-type)
	      (setf (slot-value product 'hsn-code) hsn-code)
	      (setf (slot-value product 'sku) sku)
	      (setf (slot-value product 'upc) upc)
	      (update-prd-details product)
	      (setf redirecturl (format nil "/hhub/dodprddetailsforvendor?id=~A" prd-id)))
	    ;;else
	    (progn 
	      (create-product prodname description vendor (select-prdcatg-by-id catg-id company) sku hsn-code qtyperunit unit-of-measure  units-in-stock (format nil "/img/~A" *HHUBDEFAULTPRDIMG*)  subscriptionflag prd-type company)
	      (setf redirecturl "/hhub/dodvenproducts")))
	(dod-reset-vendor-products-functions vendor company)))
    (function (lambda ()
      (values redirecturl)))))

;; ----------------------------------------------------------------------------
;; 段：忘记密码 / 重置密码 / 邮件链接 / 临时密码生成
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-password-reset-action ()
  "vendor 重置密码控制器（hhubvendpassresetaction）。
   流程：
     1) 用 token 取 reset-password-instance；
     2) 用旧（临时）密码验证；
     3) token 是否过期（*HHUBPASSRESETTIMEWINDOW* 分钟）；
     4) 通过则把 newpassword 加密写库，回到 vendor-login。"
  (let* ((pwdresettoken (hunchentoot:parameter "token"))
	 (rstpassinst (get-reset-password-instance-by-token pwdresettoken))
	 (user-type (if rstpassinst (slot-value rstpassinst 'user-type)))
	 (password (hunchentoot:parameter "password"))
	 (newpassword (hunchentoot:parameter "newpassword"))
	 (confirmpassword (hunchentoot:parameter "confirmpassword"))
	 (salt (createciphersalt))
	 (encryptedpass (check&encrypt newpassword confirmpassword salt))
	 (email (if rstpassinst (slot-value rstpassinst 'email)))
	 (vendor (select-vendor-by-email email))
	 (present-salt (if vendor (slot-value vendor 'salt)))
	 (present-pwd (if vendor (slot-value vendor 'password)))
	 (password-verified (if vendor  (check-password password present-salt present-pwd))))
     (cond 
       ((or  (not password-verified)  (null encryptedpass)) (dod-response-passwords-do-not-match-error)) 
       ;Token has expired
       ((and (equal user-type "VENDOR")
		 (clsql-sys:duration> (clsql-sys:time-difference (clsql-sys:get-time) (slot-value rstpassinst 'created))  (clsql-sys:make-duration :minute *HHUBPASSRESETTIMEWINDOW*))) (hunchentoot:redirect "/hhub/hhubpassresettokenexpired.html"))
       ((and password-verified encryptedpass) (progn 
       (setf (slot-value vendor 'password) encryptedpass)
       (setf (slot-value vendor 'salt) salt) 
       (update-vendor-details vendor)
       (hunchentoot:redirect "/hhub/vendor-login.html"))))))
 


(defun dod-controller-vendor-password-reset-page ()
  "渲染重置密码页（带 token）。表单 POST hhubvendpassresetaction，
   旧密码字段实际是邮件中收到的临时 OTP。"
  (let ((token (hunchentoot:parameter "token")))
(with-standard-vendor-page (:title "Password Reset") 
(:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form "form-vendorchangepin" "hhubvendpassresetaction"  
					;(:div :class "account-wall"
			 (:h1 :class "text-center login-title"  "Change Password")
			 (:div :class "form-group"
			  
			       (:input :class "form-control" :name "token" :value token :type "hidden"))
			 (:div :class "form-group"
			       (:label :for "password" "Password")
			       (:input :class "form-control" :name "password" :value "" :placeholder "Enter OTP from Email Old" :type "password" :required T))
			 (:div :class "form-group"
			       (:label :for "newpassword" "New Password")
			       (:input :class "form-control" :id "newpassword" :data-minlength "8" :name "newpassword" :value "" :placeholder "New Password" :type "password" :required T))
			 (:div :class "form-group"
			       (:label :for "confirmpassword" "Confirm New Password")
			       (:input :class "form-control" :name "confirmpassword" :value "" :data-minlength "8" :placeholder "Confirm New Password" :type "password" :required T :data-match "#newpassword"  :data-match-error "Passwords dont match"  ))
			 (:div :class "form-group"
			       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))


(defun dod-controller-vendor-generate-temp-password ()
  "生成 vendor 临时密码：根据 token 取 reset-password 记录，校验未过期后
   reset-vendor-password 生成随机密码，邮件 send-temp-password 发给 vendor，
   并跳到 hhubpassresetmailsent.html。"
  (let* ((token (hunchentoot:parameter "token"))
	 (rstpassinst (get-reset-password-instance-by-token token))
	 (user-type (if rstpassinst (slot-value rstpassinst 'user-type)))
	 (url (format nil "~A/hhub/hhubvendpassreset.html?token=~A" *siteurl*  token))
	 (email (if rstpassinst (slot-value rstpassinst 'email))))
    
	 (cond 
	   ((and (equal user-type "VENDOR")
		 (clsql-sys:duration< (clsql-sys:time-difference (clsql-sys:get-time) (slot-value rstpassinst 'created))  (clsql-sys:make-duration :minute *HHUBPASSRESETTIMEWINDOW*)))
	    (let* ((vendor (select-vendor-by-email email))
		   (newpassword (reset-vendor-password vendor)))
					;send mail to the vendor with new password 
	      (send-temp-password vendor newpassword url)
	      (hunchentoot:redirect "/hhub/hhubpassresetmailsent.html")))	  
	   ((and (equal user-type "VENDOR")
		 (clsql-sys:duration> (clsql-sys:time-difference (clsql-sys:get-time) (slot-value rstpassinst 'created))  (clsql-sys:make-duration :minute *HHUBPASSRESETTIMEWINDOW*))) (hunchentoot:redirect "/hhub/hhubpassresettokenexpired.html"))
	   ((equal user-type "CUSTOMER") ())
	   ((equal user-type "EMPLOYEE") ()))))



(defun dod-controller-vendor-reset-password-action-link ()
  "vendor '忘记密码' 入口（hhubvendforgotpassactionlink）。
   先用 reCAPTCHA v2 验证；email 找不到 vendor 则跳错误页；
   合法时 create-reset-password-instance 写表，临时禁用 vendor，
   send-password-reset-link 发邮件。"
(let* ((email (hunchentoot:parameter "email"))
       (vendor (select-vendor-by-email email))
       (token (format nil "~A" (uuid:make-v1-uuid )))
       (user-type (hunchentoot:parameter "user-type"))
       (tenant-id (if vendor (slot-value vendor 'tenant-id)))
       (captcha-resp (hunchentoot:parameter "g-recaptcha-response"))
       (paramname (list "secret" "response" ))
       (url (format nil "~A/hhub/hhubvendgentemppass?token=~A" *siteurl*  token))
       (paramvalue (list *HHUBRECAPTCHAv2SECRET*  captcha-resp))
       (param-alist (pairlis paramname paramvalue ))
       (json-response (json:decode-json-from-string  (map 'string 'code-char(drakma:http-request "https://www.google.com/recaptcha/api/siteverify"
												 :method :POST
												 :parameters param-alist  )))))
  
  
  (cond 
	 ; Check whether captcha has been solved 
    ((null (cdr (car json-response))) (dod-response-captcha-error))
    ((null vendor) (hunchentoot:redirect "/hhub/hhubinvalidemail.html"))
    ; if vendor is valid then create an entry in the password reset table. 
    ((and (equal user-type "VENDOR") vendor)
     (progn 
       (create-reset-password-instance user-type token email  tenant-id)
       ; temporarily disable the vendor record 
       (setf (slot-value vendor 'active-flag) "N")
       (update-vendor-details vendor) 
       ; Send vendor an email with password reset link. 
       (send-password-reset-link vendor url)
       (hunchentoot:redirect "/hhub/hhubpassresetmaillinksent.html"))))))





(defun modal.vendor-forgot-password()
  "渲染 '忘记密码' 表单 modal。POST hhubvendforgotpassactionlink，
   user-type 隐藏字段='VENDOR'，集成 reCAPTCHA v2。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row" 
	  (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		(:form :id (format nil "form-vendorforgotpass")  :role "form" :method "POST" :action "hhubvendforgotpassactionlink" :enctype "multipart/form-data" 
		      (:h1 :class "text-center login-title"  "Forgot Password")
		      (:div :class "form-group"
			    (:input :class "form-control" :name "email" :value "" :placeholder "Email" :type "text")
			    (:input :class "form-control" :name "user-type" :value "VENDOR"  :type "hidden" :required "true"))
		      (:div :class "form-group"
			(:div :class "g-recaptcha" :data-sitekey *HHUBRECAPTCHAV2KEY* ))
		      (:div :class "form-group"
			    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Reset Password")))))))


    

;; ----------------------------------------------------------------------------
;; 段：vendor 登录页面 / OTP 登录 / OTP 登录 v2
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-loginpage ()
  "vendor 经典手机 + 密码登录页。
   开头先 'select 1' 探活 MySQL，遇到 2013 错误（连接断开）会自动 stop-das
   + start-das 后重定向回登录页（自愈）。
   已登录则直接跳 /hhub/dodvendindex?context=home。"
  (handler-case
      (progn  (if (equal (caar (clsql:query "select 1" :flatp nil :field-names nil :database *dod-db-instance*)) 1) T)
	      (if (is-dod-vend-session-valid?)
		  (hunchentoot:redirect "/hhub/dodvendindex?context=home")
		  (with-standard-vendor-page-v2 "Welcome to Nine Stores Platform - Vendor Login "
		    (with-html-div-row
		      (with-html-div-col-12
			(with-html-card
			    (:title "Login"
			     :image-src "/img/logo.png"
			     :image-alt "Vendor Login to Nine Stores"
			     :image-style "width: 200px; height: 200px;")
			  (:form :class "form-vendorsignin" :role "form" :method "POST" :action "dodvendlogin"
				 (:div :class "form-group"
				       (:input :class "form-control" :name "phone" :placeholder "Enter RMN. Ex:9999999990" :type "text" ))
				 (:div :class "form-group"
				       (:input :class "form-control" :name "password" :placeholder "password=Welcome1" :type "password" ))
				 (:div :class "form-group"
				       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Login")))
			  (:div :class "form-group"
				(:a :data-bs-toggle "modal" :data-bs-target (format nil "#dasvendforgotpass-modal") :href "#" "Forgot Password?")
				(modal-dialog-v2 (format nil "dasvendforgotpass-modal") "Forgot Password?" (modal.vendor-forgot-password)))
			  (hhub-html-page-footer)))))))
    (clsql:sql-database-data-error (condition)
      (if (equal (clsql:sql-error-error-id condition) 2013 ) (progn
							       (stop-das) 
							       (start-das)
							       (hunchentoot:redirect "/hhub/vendor-login.html"))))))



(defun dod-controller-vendor-otploginpage ()
  "vendor OTP 登录页（手机号 + 短信 OTP）。同上自愈逻辑。
   已登录跳 home；否则渲染 v3 模板（Tailwind 样式）。"
  (handler-case
      (progn
        (when (equal (caar (clsql:query "select 1"
                                        :flatp nil :field-names nil
                                        :database *dod-db-instance*)) 1)
          t)
        (if (is-dod-vend-session-valid?)
            (hunchentoot:redirect "/hhub/dodvendindex?context=home")
            (with-standard-page-template-v3
                "Vendor OTP Login | Nine Stores"
               (lambda ()
                    (cl-who:htm
                      (:nav :class "bg-gray-950/80 backdrop-blur-md text-white p-4 shadow-md"
                        (:div :class "container mx-auto flex justify-between items-center"
                          (:div :class "text-lg font-semibold tracking-wide"
                            "Nine Stores Vendor Portal")
                          (:div
                            (:a :href "/" :class "text-gray-300 hover:text-white transition"
                                "← Back to Home"))))))
              (:div :class "bg-white/10 backdrop-blur-md border border-white/20 rounded-2xl shadow-2xl w-[90%] max-w-md p-8 text-center text-white"
                    (:img :src "/img/logo.png" :alt "Nine Stores Logo" :class "mx-auto mb-6 w-28 h-28 rounded-full shadow-lg border border-white/10 bg-white/10 p-2")
		    ;;<!-- Title -->
		    (:h1 :class "text-2xl font-bold mb-2" "Welcome to Nine Stores")
		    (:p :class "text-gray-300 mb-6" "Vendor OTP Login Portal")
		    (with-catch-submit-event "idform-vendsignin"
		      (:form :id "vendsigninwithotp" :method "POST" :action "hhubvendloginotpstep" :class "space-y-5"
			     (:div
			      (:input :type "number"
				      :id "phone"
				      :name "phone"
				      :placeholder "Enter RMN. Ex: 9999999990"
				      :required "true"
				      :class "w-full px-4 py-3 bg-white/20 border border-white/30 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#38bdf8] placeholder-gray-300 text-white"))
			     (:button :type "submit"
				      :class "w-full py-3 bg-gradient-to-r from-[#38bdf8] to-[#3b82f6] hover:opacity-90 rounded-lg text-white font-semibold text-lg shadow-md transition"
				      "Get OTP")))
			  ;;<!-- Divider -->
			  (:div :class "my-6 border-t border-white/20")
			  ;;<!-- Alternative login -->
			  
			  ;;<!-- Footer -->
		     (:footer :class "mt-8 text-xs text-gray-400" "&copy 2026 Nine Stores. All rights reserved.")))))
    (clsql:sql-database-data-error (condition)
      (when (equal (clsql:sql-error-error-id condition) 2013)
        (progn
          (stop-das)
          (start-das)
          (hunchentoot:redirect "/hhub/vendor-login.html"))))))



(defun dod-controller-vendor-otploginpagev2 ()
  (handler-case 
      (progn  
	(if (equal (caar (clsql:query "select 1" :flatp nil :field-names nil :database *dod-db-instance*)) 1) T)      
	(if (is-dod-vend-session-valid?)
	    (hunchentoot:redirect "/hhub/dodvendindex?context=home")
	    (with-standard-vendor-page-v2  "Welcome to Nine Stores Platform - Vendor Login "
	      (with-html-div-row
		(with-html-div-col-12 
		  (with-html-card
		      (:title "Vendor Login"
		       :image-src "/img/logo.png"
		       :image-alt "Vendor Login to Nine Stores"
		       :image-style "width: 200px; height: 200px;")
		    (with-html-form-having-submit-event  "form-vendorsignin" "hhubvendloginotpstep"
		      (:div :class "form-group"
			    (:input :class "form-control" :name "phone" :placeholder "Enter RMN. Ex: 9999999990" :type "number" :required "true" ))
		      (:div :class "form-group"
			    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Get OTP")))
		    (hhub-html-page-footer)))))))
    (clsql:sql-database-data-error (condition)
      (if (equal (clsql:sql-error-error-id condition) 2013 ) (progn
							       (stop-das) 
							       (start-das)
							       (hunchentoot:redirect "/hhub/hhubvendloginv2"))))))



;; ----------------------------------------------------------------------------
;; 段：vendor 客户列表 / 客户搜索 / 钱包充值
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-my-customers-page ()
  "vendor '我的客户' 页面，列出该 vendor 通过钱包关联的 STANDARD 类型客户。"
  (with-vend-session-check
    (with-mvc-ui-page "My Customers" #'create-model-for-showvendorcustomers #'create-widgets-for-showvendorcustomers :role  :vendor )))

(defun create-model-for-showvendorcustomers ()
  "从 vendor 钱包列表 wallets 反查 customer，仅保留 cust-type='STANDARD' 的客户。"
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (wallets (get-cust-wallets-for-vendor vendor company))
	 (mycustomers (remove nil (mapcar (lambda (wallet)
					    (let* ((customer (slot-value wallet 'customer))
						   (cust-type (slot-value customer 'cust-type)))
					      (when (equal cust-type "STANDARD") customer))) wallets))))
    (function (lambda ()
      (values mycustomers)))))

(defun create-widgets-for-showvendorcustomers (modelfunc)
  "渲染搜索框 + 客户列表（5 列：Name/Phone/Address/Balance/Actions）。
   搜索框 ajax 调 hhubsearchmycustomer。"
  (multiple-value-bind (mycustomers) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-html-search-form "idsearchmycustomer" "searchmycustomer" "idtxtsearchcustomer" "txtsearchcustomer" "hhubsearchmycustomer" "onkeyupsearchform1event();" "Customer Name"
			  (submitsearchform1event-js "#idtxtsearchcustomer" "#vendormycustomerssearchresult" ))
			(:div :id "vendormycustomerssearchresult"  :class "container-fluid"
			      (cl-who:str (display-as-table (list "Name" "Phone" "Address" "Balance" "Actions") mycustomers 'display-my-customers-row))))))))
      (list widget1))))



(defun hhub-controller-search-my-customer-action ()
  "ajax 搜索客户：select-customer-list-by-name LIKE %xxx%，过滤掉没有 vendor 钱包关联的，
   返回 5 列表格 HTML 片段。"
  (with-vend-session-check
    (let* ((company (get-login-vendor-company))
	   (vendor (get-login-vendor))
	   (name (hunchentoot:parameter "txtsearchcustomer"))
	   (totalcustomers (select-customer-list-by-name (format nil "%~A%" name) company))
	   (customers (remove nil (mapcar (lambda (customer)
					    (if (get-cust-wallet-by-vendor customer vendor company) customer)) totalcustomers))))
      
      (if (> (length customers) 0)
	(cl-who:with-html-output (*standard-output* nil) 
	  (cl-who:str (display-as-table (list "Name" "Phone" "Address" "Balance" "Actions") customers 'display-my-customers-row)))
	;; else
	(cl-who:with-html-output (*standard-output* nil)
	  (:h3 (cl-who:str "No Records Found")))))))
	
       
(defun hhub-controller-vsearchcustbyname-for-invoice-action ()
  "ajax 按名称搜客户（用于发票流程）。返回 'Add to Invoice' 按钮所在的 3 列表格。"
  (with-vend-session-check
    (let* ((company (get-login-vendor-company))
	   (name (hunchentoot:parameter "txtsearchcustomername"))
	   (customers (select-customer-list-by-name (format nil "%~A%" name) company)))
      (if (> (length customers) 0)
	(cl-who:with-html-output (*standard-output* nil) 
	  (cl-who:str (display-as-table (list "Name" "Phone" "Action") customers 'display-add-customer-to-invoice-row)))
	;; else
	(cl-who:with-html-output (*standard-output* nil)
	  (:h3 (cl-who:str "No Records Found")))))))

(defun hhub-controller-vsearchcustbyphone-for-invoice-action ()
  "ajax 按手机号搜客户（用于发票流程）。返回类似上面的表格。"
  (with-vend-session-check
    (let* ((company (get-login-vendor-company))
	   (name (hunchentoot:parameter "txtsearchcustomerphone"))
	   (customers (select-customer-list-by-phone (format nil "~A%" name) company)))
      (if (> (length customers) 0)
	(cl-who:with-html-output (*standard-output* nil) 
	  (cl-who:str (display-as-table (list "Name" "Phone" "Action") customers 'display-add-customer-to-invoice-row)))
	;; else
	(cl-who:with-html-output (*standard-output* nil)
	  (:h3 (cl-who:str "No Records Found")))))))



(defun display-my-customers-row (customer &rest arguments)
  "渲染单行客户：Name/Phone/Address/Balance/钱包充值按钮 + WhatsApp 链接。
   钱包充值按钮打开 modal.vendor-my-customer-wallet-recharge。"
  (declare (ignore arguments))
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (currency (get-account-currency company))
	 (cust-id (slot-value customer 'row-id))
	 (cust-phone (slot-value customer 'phone))
	 (cust-name (slot-value customer 'name))
	 (wallet (get-cust-wallet-by-vendor customer  vendor company))
	 (chatonwhatsappurl (createwhatsapplinkwithmessage cust-phone (format nil "Hi ~A" cust-name))))
    (with-slots (name phone address) customer
      (cl-who:with-html-output (*standard-output* nil)
	(:td  :height "10px" (cl-who:str name))
	(:td  :height "10px" (cl-who:str phone))
	(:td  :height "10px" (cl-who:str address))
	(:td  :height "10px" (cl-who:str (slot-value wallet 'balance)))
	(:td  :height "10px"
	      (:a :data-bs-toggle "modal" :data-bs-target (format nil "#vendormycustomerwallet~A" cust-id)  :href "#"  (:i :class (get-currency-fontawesome-symbol currency) :aria-hidden "true"))
	      (modal-dialog-v2 (format nil "vendormycustomerwallet~A" cust-id) "Recharge Wallet" (modal.vendor-my-customer-wallet-recharge wallet phone)))
	      (:td :height "10px" (:a :href chatonwhatsappurl :target "_blank" (:i :class "fa-brands fa-whatsapp fa-xl" :style "color: #39dd30;")))))))
 
(defun modal.vendor-my-customer-wallet-recharge (wallet phone)
  "钱包充值表单（POST dodupdatewalletbalance）。提示 vendor 先线下收钱再录入。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-html-div-row
      (with-html-div-col
	(:form :class "form-vendor-update-balance" :role "form" :method "POST" :action "dodupdatewalletbalance"
	       (:div :class "form-group"
		     (:input :class "form-control" :name "balance" :placeholder "recharge amount" :type "text" ))
	       (:input :class "form-control" :name "wallet-id" :value (slot-value wallet 'row-id) :type "text" :style "display:none;")
	       (:input :class "form-control" :name "phone" :value phone :type "text" :style "display:none;")
	       (:div :class "form-group"
		     (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save")))))
    (with-html-div-row
      (:h5 "Note: Receive money from customer via cash/UPI and then update the wallet balance here."))))
      
;; Deprecated.
(defun dod-controller-vendor-search-cust-wallet-page ()
  :Description "Deprecated function.
   中文：废弃——按手机号搜钱包页（已被 my-customers + 钱包充值 modal 取代）。"
  (with-vend-session-check 
    (with-standard-vendor-page "Welcome to DAS Platform- Your Demand And Supply destination."
      (:div :class "row" 
	    (:div :class "col-sm-6 col-md-4 col-md-offset-4"
		  (:form :class "form-cust-wallet-search" :role "form" :method "POST" :action "dodsearchcustwalletaction"
			 (:div :class "account-wall"
			       (:div :class "form-group"
				     (:input :class "form-control" :name "phone" :placeholder "Enter Customer Phone Number" :type "number" :size "10" ))
			       
			       (:div :class "form-group"
				     (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save")))))))))
  


;; Deprecated
(defun dod-controller-vendor-search-cust-wallet-action ()
  :description "Deprecated function.
   中文：废弃——按手机号搜钱包动作。会话失效跳 vendor-login。"
  (if (is-dod-vend-session-valid?)
  (let* ((phone (hunchentoot:parameter "phone"))
	 (customer (select-customer-by-phone phone (get-login-vendor-company)))
	 (wallet (if customer (get-cust-wallet-by-vendor customer (get-login-vendor) (get-login-vendor-company)))))
 
    (if (null wallet) 
	(with-standard-vendor-page (:title "Welcome to DAS Platform")
	  (:div :class "row" 
		(:div :class "col-sm-6 col-md-4 col-md-offset-4" (:h3 "Wallet does not exist"))))
					;else
	(with-standard-vendor-page (:title "Welcome to DAS Platform")
	  (:div :class "row" 
		(:div :class "col-sm-6 col-md-4 col-md-offset-4" (:h3 (cl-who:str (format nil "Name: ~A" (if customer (slot-value customer 'name)))))))
	  (:div :class "row" 
		(:div :class "col-sm-6 col-md-4 col-md-offset-4" (:h3 (cl-who:str (format nil "Phone: ~A" (if customer (slot-value customer 'phone)))))))
	  (:div :class "row" 
		(:div :class "col-sm-6 col-md-4 col-md-offset-4" (:h3 (cl-who:str (format nil "Address: ~A" (if customer (slot-value customer 'address)))))))
	  
	  (:div :class "row" 
		(:div :class "col-sm-6 col-md-4 col-md-offset-4" (:h3 (cl-who:str (format nil "Balance = Rs.~$" (slot-value wallet 'balance))))))
	  (:div :class "row" 
		(:div :class "col-sm-6 col-md-4 col-md-offset-4"
		      (:form :class "form-vendor-update-balance" :role "form" :method "POST" :action "dodupdatewalletbalance"
			     (:div :class "account-wall"
				   (:div :class "form-group"
					 (:input :class "form-control" :name "balance" :placeholder "recharge amount" :type "text" ))
				   (:input :class "form-control" :name "wallet-id" :value (slot-value wallet 'row-id) :type "hidden")
				   (:input :class "form-control" :name "phone" :value phone :type "hidden")
				   (:div :class "form-group"
			    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save")))))))))
  (hunchentoot:redirect "/hhub/vendor-login.html")))


(defun dod-controller-update-wallet-balance ()
  "钱包充值控制器：amount + 现 balance → set-wallet-balance。
   完成后重定向到 my-customers 列表。
   备注：注释提到 memoize 清理已不再调用，钱包查询不再走 memoize。"
  (with-vend-session-check
    (let* ((amount (parse-integer (hunchentoot:parameter "balance")))
	   (wallet (get-cust-wallet-by-id (hunchentoot:parameter "wallet-id") (get-login-vendor-company)))
	   (current-balance (slot-value wallet 'balance))
	   (latest-balance (+ current-balance amount)))
      (set-wallet-balance latest-balance wallet)
      ;; We need to clear this memoized function and again memoize it.
      ;; (memoize 'get-cust-wallet-by-vendor)
      (hunchentoot:redirect (format nil "/hhub/hhubvendmycustomers")))))
    
   
;; ----------------------------------------------------------------------------
;; 段：vendor 档案页 / 配送方式 / 运费阶梯表
;; ----------------------------------------------------------------------------
(defun dod-controller-vend-profile ()
  "vendor 档案主页（含支付方式、UPI、网关、修改密码、修改资料几个 modal）。"
  (with-vend-session-check
    (with-mvc-ui-page "Vendor Profile" #'create-model-for-vendorprofile #'create-widgets-for-vendorprofile :role :vendor)))

(defun create-model-for-vendorprofile ()
  "用 VPaymentMethodsAdapter 走 with-entity-read 拉支付开关；返回闭包提供给 widget。"
  (let* ((company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (adapter (make-instance 'VPaymentMethodsAdapter))
	 (requestmodel (make-instance 'VPaymentMethodsRequestModel
				      :company company
				      :vendor vendor))
	 (vpaymentmethods (processreadrequest adapter requestmodel))
	 (vendorname (get-login-vendor-name)))
    (function (lambda ()
      (values vendorname  vpaymentmethods)))))

(defun create-widgets-for-vendorprofile (modelfunc)
  "渲染档案页：欢迎语 + 列表组（My Groups / Contact Information / Shipping Methods /
   Payment Methods / Payment Gateway / UPI Settings）。每项弹出对应 modal 表单。"
  (multiple-value-bind (vendorname vpaymentmethods) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (:br)
		       (:h3 "Welcome " (cl-who:str (format nil "~A" vendorname)))
		       (:hr)))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-6
			   (with-catch-submit-event "idvendorprofilesubmitevents"  
			     (:a :class "list-group-item list-group-item-action" :href "dodvendortenants" "My Groups")
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendupdate-modal")  :href "#"  "Contact Information")
			     (modal-dialog-v2 (format nil "dodvendupdate-modal") "Update Vendor" (modal.vendor-update-details)) 
			     ;; Since we are enabling the OTP based login for Vendor, we do not need password. 
			     ;;(:a :class "list-group-item" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendchangepin-modal")  :href "#"  "Change Password")
			     ;;(modal-dialog-v2 (format nil "dodvendchangepin-modal") "Change Password" (modal.vendor-change-pin))
			     ;; (:a :class "list-group-item" :href "/pushsubscribe.html" "Push Notifications")
			     ;;(:a :class "list-group-item" :href "/hhub/hhubvendpushsubscribepage" "Push Notifications")
			     (:a :class "list-group-item list-group-item-action" :href "hhubvendorshipmethods" "E-Commerce Shipping Methods")
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendpaymentmethods-modal")  :href "#"  "E-Commerce Payment Methods")
			     (modal-dialog-v2 (format nil "dodvendpaymentmethods-modal") "Payment Methods " (modal.vendor-payment-methods-page vpaymentmethods))
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendsettings-modal")  :href "#"  "E-Commerce Payment Gateway")
			     (modal-dialog-v2 (format nil "dodvendsettings-modal") "Payment Gateway Settings" (modal.vendor-update-payment-gateway-settings-page))
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendupisettings-modal") :href "#" "UPI Settings")
			     (modal-dialog-v2 (format nil "dodvendupisettings-modal") "UPI Payment Settings" (modal.vendor-update-UPI-payment-settings-page))))))))))
      (list widget1 widget2))))
  

(defun dod-controller-vend-shipping-methods ()
  "vendor E-Commerce 配送方式总览页（含 5 种方法 modal：免邮 / 平价 / 阶梯
   / 外部物流 / 默认方式）。"
  (with-vend-session-check
    (with-mvc-ui-page "Vendor Shipping Methods for E-Commerce" #'create-model-for-vendshippingmethods #'create-widgets-for-vendshippingmethods :role :vendor)))

(defun create-model-for-vendshippingmethods ()
  "拉 vendor shipping-method 全部字段（flatrate / extship / freeship 子开关），
   返回闭包暴露给 widget。"
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (shippingmethod (get-shipping-method-for-vendor vendor company))
	 (flatrateshipenabled (slot-value shippingmethod 'flatrateshipenabled))
	 (flatratetype (slot-value shippingmethod 'flatratetype))
	 (flatrateprice (slot-value shippingmethod 'flatrateprice))
	 (extshipenabled (slot-value shippingmethod 'extshipenabled))
	 (shippartnerkey (slot-value shippingmethod 'shippartnerkey))
	 (shippartnersecret (slot-value shippingmethod 'shippartnersecret))
	 (minorderamt (when shippingmethod (getminorderamt shippingmethod)))
	 (freeshipenabled (when shippingmethod (slot-value shippingmethod 'freeshipenabled))))
    (function (lambda ()
      (values vendor shippingmethod flatrateshipenabled flatratetype flatrateprice extshipenabled shippartnerkey shippartnersecret minorderamt freeshipenabled )))))

(defun create-widgets-for-vendshippingmethods (modelfunc)
  "渲染 5 个 modal 入口 + 3 段 JS（启用 minorderamt 输入 / vendor shipping toggle /
   store pickup toggle）。"
  (multiple-value-bind (vendor shippingmethod flatrateshipenabled flatratetype flatrateprice extshipenabled shippartnerkey shippartnersecret minorderamt freeshipenabled) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (:br)
		       (:div :class "list-group col-6"
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendfreeshipping-modal")  :href "#"  "Free Shipping")
			     (modal-dialog-v2 (format nil "dodvendfreeshipping-modal") "Free Shipping Configuration" (modal.vendor-free-shipping-config freeshipenabled minorderamt))
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendflatrateshipping-modal")  :href "#"  "Flat Rate Shipping")
			     (modal-dialog-v2 (format nil "dodvendflatrateshipping-modal") "Flat Rate Shipping Configuration" (modal.vendor-flatrate-shipping-config flatrateshipenabled flatratetype flatrateprice))
			     (:a :class "list-group-item list-group-item-action" :href "hhubvendshipzoneratetablepage"  "Zonewise Shipping")
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendextshipping-modal")  :href "#"  "External Shipping Partners")
			     (modal-dialog-v2 (format nil "dodvendextshipping-modal") "External Shipping Partners Configuration" (modal.vendor-external-shipping-partners-config shippartnerkey shippartnersecret extshipenabled))
			     (:a :class "list-group-item list-group-item-action" :data-bs-toggle "modal" :data-bs-target (format nil "#dodvenddefaultshipmethod-modal")  :href "#"  "Select Default Shipping Method")
			     (modal-dialog-v2 (format nil "dodvenddefaultshipmethod-modal") "Default Shipping Method Configuration" (modal.vendor-default-shipping-method-config shippingmethod vendor)))))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
	     	       (:script "function enableminorderamt() {
    const freeshipenabled = document.getElementById('freeshipenabled');
    if( freeshipenabled.checked ){
	$('#minorderamtctrl').show();
        freeshipenabled.value = \"Y\";
    }else
    {
       $('#minorderamtctrl').hide();
       freeshipenabled.value = \"N\";
    }
}")))))
	  (widget3 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (:script "function enablevendorshipping() {
    const vendorshipenabled = document.getElementById('vendorshipenabled');
    if( vendorshipenabled.checked ){
         vendorshipenabled.value = \"Y\";
	$('#vendorshipenabledctrl').show();
        
    }else
    {
          vendorshipenabled.value = \"N\";
       $('#vendorshipenabledctrl').hide();
      
    }
}")))))
	  (widget4 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (:script "function enablestorepickupmethod(){
       const  enablestorepickup  = document.getElementById('storepickupenabled');
    if( enablestorepickup.checked ){
         enablestorepickup.value = \"Y\";
    }else
    {
         enablestorepickup.value = \"N\";
    }
}"))))))
      (list widget1 widget2 widget3 widget4))))

(defun dod-controller-vendor-shipzone-ratetable-page()
  "vendor 阶梯运费配置页（按 zonewise CSV）。
   表单上传两份 CSV：rate table（运费阶梯）+ zone pincodes（按邮编归区）。
   带样例 CSV 下载链接和 JS 切换显示开关。"
  (with-vend-session-check
    (let* ((vendor (get-login-vendor))
	   (company (get-login-vendor-company))
	   (shippingmethod (get-shipping-method-for-vendor vendor company))
	   (tablerateshipenabled (if shippingmethod (slot-value shippingmethod 'tablerateshipenabled)))
	   (ratetablecsv (if (and tablerateshipenabled shippingmethod) (getratetablecsv shippingmethod) (hhub-read-file (format nil "~A/~A" *HHUBRESOURCESDIR* *HHUBDEFAULTSHIPRATETABLECSV*))))
	   (shipzones (get-ship-zones-for-vendor vendor company))
	   (zipcoderanges (hhub-read-file (format nil "~A/~A" *HHUBRESOURCESDIR* *HHUBDEFAULTSHIPZONESCSV*))))

      (with-standard-vendor-page "Nine Stores - Vendor Zonewise Shipping Method"
	(with-html-form "form-vendorshipratetableupload" "hhubvenduploadshipratetableaction"
	  (:div :class "form-check"
		(if (equal tablerateshipenabled "Y")
			    (cl-who:htm (:input :type "checkbox" :id "tablerateshipenabled" :name "tablerateshipenabled" :value "Y" :onclick (parenscript:ps (enableratetableshipping)) :tabindex "1"  :checked "true"))
			    ;; else
			    (cl-who:htm
			     (:input :type "checkbox" :id "tablerateshipenabled" :name "tablerateshipenabled" :value "N" :onclick (parenscript:ps (enableratetableshipping)) :tabindex "1")))
		(:label :for "tablerageshipenabled" "&nbsp;&nbsp;&nbsp;Enable Zonewise Shipping:"))
	  (:br)
	  (cl-who:htm (:div :id "ratetablecsvuploadctrl"
			      (:div :class "form-group" (:label :for "" "Select Shipping Rate Table CSV:")
				    (:input :class "form-control" :name "ratetablecsv" :placeholder "Rate Table CSV File" :type "file" )
			      (:a :href (format nil "/img/~A"  *HHUBDEFAULTSHIPRATETABLECSV*) (:i :class "fa-solid fa-file-arrow-down fa-beat fa-lg") "&nbsp;&nbsp;Download Sample CSV File"))
			      (:div :class "form-group" (:label :for "" "Select Shipping Zones & Pincodes CSV:")
				    (:input :class "form-control" :name "zonepincodescsv" :placeholder "Shipping Zones & Pincodes CSV File" :type "file" ))
			      (:div (:a :href (format nil "/img/~A"  *HHUBDEFAULTSHIPZONESCSV*) (:i :class "fa-solid fa-file-arrow-down fa-beat fa-lg") "&nbsp;&nbsp;Download Sample CSV File"))))
			(:div :class "form-group"
			      (:button :class "btn btn-primary" :type "submit" "Save")))
	
	
	(:hr)
	(when ratetablecsv
	  (cl-who:str
	   (display-csv-as-html-table ratetablecsv)))
	(:br)
	(unless shipzones
	  (cl-who:str (display-csv-as-html-table zipcoderanges)))
	(:p
	 (:h5 "Note: You can find more information on how Indian Pincode system works "
	      (:a :target "_blank" :href "https://en.wikipedia.org/wiki/Postal_Index_Number" "Click Here")))
	(when shipzones
	  (cl-who:str (display-as-tiles shipzones 'zonezipcodesdisplayfunc "product-card" )))
	 	
	;; Zone 
	(:script "function enableratetableshipping() {
    const tablerateshipenabled = document.getElementById('tablerateshipenabled');
    if( tablerateshipenabled.checked ){
	$('#ratetablecsvuploadctrl').show();
        tablerateshipenabled.value = \"Y\";
    }else
    {
       $('#ratetablecsvuploadctrl').hide();
       tablerateshipenabled.value = \"N\";
    }
}")))))

(defun zonezipcodesdisplayfunc (shipzone)
  "渲染单个配送 zone tile：粗体 zonename + 邮编范围 zipcoderangecsv。"
  (cl-who:with-html-output (*standard-output* nil)
    (:b (:div  :height "10px" (cl-who:str (slot-value shipzone 'zonename))))
    (:div :height "10px"  (cl-who:str (slot-value shipzone 'zipcoderangecsv)))))



(defun dod-controller-vendor-upload-shipping-ratetable-action ()
  "上传 vendor 阶梯运费 CSV + zone pincodes CSV 处理控制器
   （hhubvenduploadshipratetableaction）。
   流程：解析两份 CSV → 写入 vendor shipping-method 与 ship-zones 表。"
  (let* ((ratetablecsvfileparams (hunchentoot:post-parameter "ratetablecsv"))
	 (zonepincodescsvfileparams (hunchentoot:post-parameter "zonepincodescsv"))
	 (tablerateshipenabled (hunchentoot:parameter "tablerateshipenabled"))
	 (ratetablecsvcontents (if ratetablecsvfileparams (hhub-read-file (nth 0 ratetablecsvfileparams))))
	 (zonepincodescsvcontents (if zonepincodescsvfileparams (hhub-read-file (nth 0 zonepincodescsvfileparams))))
	 (zonepincodeslst (if zonepincodescsvcontents (cl-csv:read-csv zonepincodescsvcontents :skip-first-p T)))
	 (vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (shippingmethod (get-shipping-method-for-vendor vendor company))
	 (shipzones (get-ship-zones-for-vendor vendor company)))

    ;; save the rate table csv in the shipping method table

    (if ratetablecsvcontents (setf (slot-value shippingmethod 'ratetablecsv) ratetablecsvcontents))
    (setf (slot-value shippingmethod 'tablerateshipenabled) tablerateshipenabled)
    (update-shipping-methods shippingmethod)
    ;; save the ship zones pincodes in the ship zones table
    (unless shipzones
      (mapcar (lambda (zoneinfo)
		(let ((zonename (car zoneinfo))
		      (pincodescsv (format nil "~A" (cdr zoneinfo))))
		  (create-vendor-ship-zone zonename pincodescsv vendor company))) zonepincodeslst))
    (when shipzones
      (mapcar (lambda (shipzone zoneinfo)
		(let ((zonename (car zoneinfo))
		      (pincodescsv (cdr zoneinfo)))
		  (setf (slot-value shipzone 'zipcoderangecsv) (format nil "~A" pincodescsv))
		  (setf (slot-value shipzone 'zonename) zonename)
		  (update-vendor-shipzone shipzone))) shipzones zonepincodeslst))
    (hunchentoot:redirect "/hhub/hhubvendshipzoneratetablepage")))
   

(defun dod-controller-vendor-update-default-shipping-method ()
  "更新默认配送方式（hhubvendupdatedefaultshipmethod）。
   依据 defaultshippingmethod={FSH,FRS,TRS,EXS} 设置对应启用标志互斥：
     FSH (FREE)         → freeshipenabled=Y, 其他=N
     FRS (Flat Rate)    → flatrateshipenabled=Y, 其他=N
     TRS (Tablerate)    → tablerateshipenabled=Y, 其他=N
     EXS (External)     → extshipenabled=Y, 其他=N
   同时更新 vendor.shipping-enabled、shippingmethod.storepickupenabled。"
  (let* ((storepickupenabled (hunchentoot:parameter "storepickupenabled"))
	 (vendorshipenabled (hunchentoot:parameter "vendorshipenabled"))
	 (defaultshippingmethod (hunchentoot:parameter "defaultshippingmethod"))
	 (vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (shippingmethod (get-shipping-method-for-vendor vendor company)))

    (setf (slot-value shippingmethod 'defaultshippingmethod) defaultshippingmethod)
    (if storepickupenabled
	(setf (slot-value shippingmethod 'storepickupenabled) storepickupenabled)
	;;else
	(setf (slot-value shippingmethod 'storepickupenabled) "N"))
    (if vendorshipenabled
	(setf (slot-value vendor 'shipping-enabled) vendorshipenabled)
	;;else
	(setf (slot-value vendor 'shipping-enabled) "N"))
    (when (equal defaultshippingmethod "FSH")
      (setf (slot-value shippingmethod 'freeshipenabled) "Y")
      (setf (slot-value shippingmethod 'flatrateshipenabled) "N")
      (setf (slot-value shippingmethod 'tablerateshipenabled) "N")
      (setf (slot-value shippingmethod 'extshipenabled) "N"))
          
    (when (equal defaultshippingmethod "FRS")
      (setf (slot-value shippingmethod 'flatrateshipenabled) "Y")
      (setf (slot-value shippingmethod 'tablerateshipenabled) "N")
      (setf (slot-value shippingmethod 'extshipenabled) "N"))
    
    (when (equal defaultshippingmethod "TRS")
      (setf (slot-value shippingmethod 'tablerateshipenabled) "Y")
      (setf (slot-value shippingmethod 'flatrateshipenabled) "N")
      (setf (slot-value shippingmethod 'extshipenabled) "N"))
    
    (when (equal defaultshippingmethod "EXS")
      (setf (slot-value shippingmethod 'extshipenabled) "Y")
      (setf (slot-value shippingmethod 'flatrateshipenabled) "N")
      (setf (slot-value shippingmethod 'tablerateshipenabled) "N"))
        
    (update-vendor-details vendor)
    (update-shipping-methods shippingmethod)
    (hunchentoot:redirect "/hhub/hhubvendorshipmethods")))
    


(defun modal.vendor-default-shipping-method-config (shippingmethod vendor)
  "渲染默认配送方式 modal 表单：包含 'Store Pickup' / 'Enable Shipping' 两个 checkbox
   + 默认方式下拉（FSH / FRS / TRS / EXS）。"
  (let ((storepickupenabled (slot-value shippingmethod 'storepickupenabled))
	(defaultshippingmethod (slot-value shippingmethod 'defaultshippingmethod))
	(vendorshipenabled (slot-value vendor 'shipping-enabled))
	(shippingmethods-ht (make-hash-table :test 'equal)))
    
    (setf (gethash "FSH" shippingmethods-ht) "FREE Shipping")
    (setf (gethash "FRS" shippingmethods-ht) "Flat Rate Shipping")
    (setf (gethash "TRS" shippingmethods-ht) "Zonewise Shipping")
    (setf (gethash "EXS" shippingmethods-ht) "External Shipping Partners")
    
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		(with-html-form "form-vendordefaultshippingmethod" "hhubvendupdatedefaultshipmethod" 
		  (:div :class "form-check"
			(if (equal storepickupenabled "Y")
			    (cl-who:htm
			     (:input :type "checkbox" :id "storepickupenabled" :name "storepickupenabled" :value "Y" :onclick (parenscript:ps (enablestorepickupmethod)) :tabindex "1"  :checked "true"))
			    ;; else
			    (cl-who:htm
			     (:input :type "checkbox" :id "storepickupenabled" :name "storepickupenabled" :value "N" :onclick (parenscript:ps (enablestorepickupmethod)) :tabindex "1" )))
			(:label :class "form-check-label" :for "freeshipenabled" "&nbsp;&nbsp;Enable Store Pickup"))
		  (:div :class "form-check"
			(if (equal vendorshipenabled "Y")
			    (cl-who:htm
			     (:input :type "checkbox" :id "vendorshipenabled" :name "vendorshipenabled" :value "Y" :onclick (parenscript:ps (enablevendorshipping)) :tabindex "2" :checked "true"))
			    ;; else
			    (cl-who:htm
			     (:input :type "checkbox" :id "vendorshipenabled" :name "vendorshipenabled" :value "N" :onclick (parenscript:ps (enablevendorshipping)) :tabindex "2" )))
			(:label :class "form-check-label" :for "vendorshipenabled" "&nbsp;&nbsp;Enable Shipping"))

		  (:br)
		  (:div :id "vendorshipenabledctrl" :class "form-group"
			(:label :class "form-check-label" :for "vendorshipenabled" "&nbsp;&nbsp;Select Default Shipping Method")
			(with-html-dropdown "defaultshippingmethod" shippingmethods-ht defaultshippingmethod))
			
			(:div :class "form-group"
			      (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))
  


(defun modal.vendor-external-shipping-partners-config (shippartnerkey shippartnersecret extshipenabled)
  "外部物流（如 Shiprocket）配置表单。表单字段：extshipenabled checkbox、
   shippartnerkey、shippartnersecret。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
          (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		(:p (cl-who:str (format nil "We have partnered with ~A for our shipping needs. Please enter your API key and secret here." *HHUBSHIPPINGPARTNERSITE*)))
		
		(with-html-form "form-vendorshippartnerupdate" "hhubvendupdateshippartneraction"

		  (:div :class "form-check"
			(if (equal extshipenabled "Y")
			    (cl-who:htm
			     (:input :type "checkbox" :id "extshipenabled" :name "extshipenabled" :value "Y" :onclick (parenscript:ps (enableextshipmethod)) :tabindex "1"  :checked "true"))
			    ;; else
			    (cl-who:htm
			     (:input :type "checkbox" :id "extshipenabled" :name "extshipenabled" :value "Y" :onclick (parenscript:ps (enableextshipmethod)) :tabindex "1")))
			(:label :class "form-check-label" :for "freeshipenabled" "&nbsp;&nbsp;Enable External Shipping"))
		  
		  (:div :class "form-group"
			(:input :class "form-control" :name "shippartnerkey" :value shippartnerkey :placeholder "Shipping Partner API Key" :type "text"))
		  (:div :class "form-group"                                                                  
			(:input :class "form-control" :name "shippartnersecret" :value shippartnersecret :placeholder "Shipping Partner API Secret" :type "text"))
		  (:div :class "form-group"
			(:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save")))))))

(defun dod-controller-vendor-update-external-shipping-partner-action ()
  "保存外部物流伙伴配置（hhubvendupdateshippartneraction）。"
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (shippingmethod (get-shipping-method-for-vendor vendor company))
	 (extshipenabled (hunchentoot:parameter "extshipenabled"))
	 (shippartnerkey (hunchentoot:parameter "shippartnerkey"))
	 (shippartnersecret (hunchentoot:parameter "shippartnersecret")))

    (setf (slot-value shippingmethod 'shippartnerkey) shippartnerkey)
    (setf (slot-value shippingmethod 'shippartnersecret) shippartnersecret)
    (setf (slot-value shippingmethod 'extshipenabled) extshipenabled)
    (update-shipping-methods shippingmethod)
    (hunchentoot:redirect "/hhub/hhubvendorshipmethods")))

	 
    


(defun modal.vendor-flatrate-shipping-config (flatrateshipenabled flatratetype flatrateprice)
  "平价运费 modal 表单。flatratetype: ORD = 整单 / ITM = 每件商品。"
  (let ((flatratetypedropdown-ht (make-hash-table :test 'equal)))
    (setf (gethash "ORD" flatratetypedropdown-ht) "Entire Order")
    (setf (gethash "ITM" flatratetypedropdown-ht) "Each Order Item")
    
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form "form-vendorflatrateshippingmethod" "hhubvendupdatflatrateshipmethodaction" 
		  (:div :class "form-check"
			(if (equal flatrateshipenabled "Y")
			    (cl-who:htm (:input :type "checkbox" :id "flatrateshipenabled" :name "flatrateshipenabled" :value "Y" :onclick (parenscript:ps (enableflatrateshipping)) :tabindex "1"  :checked "true"))
			    ;; else
			    (cl-who:htm (:input :type "checkbox" :id "flatrateshipenabled" :name "flatrateshipenabled" :value "Y" :onclick (parenscript:ps (enableflatrateshipping)) :tabindex "1")))
			(:label :class "form-check-label" :for "flatrateshipenabled" "&nbsp;&nbsp;Enable Flatrate Shipping")
			(:div :id "flatrateshippingctrl" :class "form-group"
			      (:label :for "flatratetype" "Flat Rate Applicable On")
			      (with-html-dropdown "flatratetype" flatratetypedropdown-ht flatratetype)
			      (:label :for "flatrateprice" "Flat Rate Price")
			      (:input :class "form-control" :name "flatrateprice" :value flatrateprice :placeholder "Flat Rate Price" :type "text"))
			(:div :class "form-group"
			      (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save")))))))))


(defun dod-controller-vendor-update-flatrate-shipping-action ()
  "保存平价运费配置（hhubvendupdatflatrateshipmethodaction）。"
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (shippingmethod (get-shipping-method-for-vendor vendor company))
	 (flatrateshipenabled (hunchentoot:parameter "flatrateshipenabled"))
	 (flatratetype (hunchentoot:parameter "flatratetype"))
	 (flatrateprice (float (with-input-from-string (in (hunchentoot:parameter "flatrateprice"))
			(read in))))) 

    ;; save the rate table csv in the shipping method table
    (if flatrateshipenabled
	(setf (slot-value shippingmethod 'flatrateshipenabled) "Y")
	;;else
	(setf (slot-value shippingmethod 'flatrateshipenabled) "N"))
    (setf (slot-value shippingmethod 'flatratetype) flatratetype)
    (setf (slot-value shippingmethod 'flatrateprice) flatrateprice)
    (update-shipping-methods shippingmethod)
    (hunchentoot:redirect "/hhub/hhubvendorshipmethods")))


(defun modal.vendor-free-shipping-config (freeshipenabled minorderamt)
  "免邮 modal 表单。免邮永远叠加在其他方式之上；带 minorderamt 最低订单门槛。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row" 
	  (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		(:p (:b "Note: Free shipping will be always applicable over and above all other shipping methods when enabled."))
		(with-html-form "form-vendorfreeshippingmethod" "hhubvendupdatfreeshipmethodaction" 
		  (:div :class "form-check"
			(if (equal freeshipenabled "Y")
			    (cl-who:htm (:input :type "checkbox" :id "freeshipenabled" :name "freeshipenabled" :value "Y" :onclick (parenscript:ps (enableminorderamt)) :tabindex "1"  :checked "true"))
			    ;; else
			    (cl-who:htm
			     (:input :type "checkbox" :id "freeshipenabled" :name "freeshipenabled" :value "N" :onclick (parenscript:ps (enableminorderamt)) :tabindex "1")))
			(:label :class "form-check-label" :for "freeshipenabled" "&nbsp;&nbsp;Enable Free Shipping")
			(:div :id "minorderamtctrl" :class "form-group"
			      (:label :for "minorderamt" "Minimum Order Amount For Free Shipping")
			      (:input :class "form-control" :name "minorderamt" :value minorderamt :placeholder "Minimum Order Amount For Free Shipping" :type "text"))
			(:div :class "form-group"
			      (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))

(defun dod-controller-vendor-update-free-shipping-method-action ()
  "保存免邮配置（hhubvendupdatfreeshipmethodaction）。"
  (with-vend-session-check
    (let* ((vendor (get-login-vendor))
	   (company (get-login-vendor-company))
	   (shippingmethod (get-shipping-method-for-vendor vendor company))
	   (freeshipenabled (hunchentoot:parameter "freeshipenabled"))
	   (minorderamt (float (with-input-from-string (in (hunchentoot:parameter "minorderamt"))
			(read in)))))  
      (setf (slot-value shippingmethod 'minorderamt) minorderamt)
      (if freeshipenabled 
	  (setf (slot-value shippingmethod 'freeshipenabled) freeshipenabled)
	  ;;else
	  (setf (slot-value shippingmethod 'freeshipenabled) "N"))
      (update-shipping-methods shippingmethod)
      (hunchentoot:redirect "/hhub/hhubvendorshipmethods"))))

    


;; ----------------------------------------------------------------------------
;; 段：vendor 顶部导航栏（v1 旧版宏）
;; 与 with-vendor-navigation-bar-v2 并存；v1 真正用了 defmacro。
;; ----------------------------------------------------------------------------
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro with-vendor-navigation-bar ()
    :documentation "This macro returns the html text for generating a navigation bar using bootstrap.
   中文：旧版 navbar 宏（Bootstrap 3 风格）。展开为 cl-who 输出。"
    `(cl-who:with-html-output (*standard-output* nil)
       (:div :class "navbar  navbar-inverse navbar-static-top"
	     (:div :class "container-fluid"
		   (:div :class "navbar-header"
			 (:button :type "button" :class "navbar-toggle" :data-bs-toggle "collapse" :data-bs-target "#navheadercollapse"
				  (:span :class "icon-bar")
				  (:span :class "icon-bar")
				  (:span :class "icon-bar"))
			 (:a :class "navbar-brand" :href "#" :title "Nine Stores" (:img :style "width: 50px; height: 50px;" :src "/img/logo.png" )))
		   ;;  (:a :class "navbar-brand" :onclick "window.history.back();"  :href "#"  (:span :class "glyphicon glyphicon-arrow-left"))
		   (:div :class "collapse navbar-collapse" :id "navheadercollapse"
			 (:ul :class "nav navbar-nav navbar-left"
			      (:li :class "active" :align "center" (:a :href "dodvendindex?context=home"  (:i :class "fa-solid fa-house-user")  "Home"))
			      (:li :align "center" (:a :href "dodvenproducts"  "My Products"))
			      (:li :align "center" (:a :href "dodvendindex?context=completedorders"  "Completed Orders"))
			      (:li :align "center" (:a :href "#" (print-vendor-web-session-timeout)))
			      (:li :align "center" (:a :href "#" (cl-who:str (format nil "Group: ~A" (get-login-vendor-company-name))))))
			 (:ul :class "nav navbar-nav navbar-right"
			      (:li :align "center" (:a :href "dodvendprofile?context=home"   (:i :class "fa-regular fa-user") "&nbsp;&nbsp;" )) 
				(:li :align "center" (:a :target "_blank" :href "https://goo.gl/forms/XaZdzF30Z6K43gQm2"  (:i :class "fa-regular fa-envelope") "&nbsp;&nbsp;"))
				(:li :align "center" (:a :target "_blank" :href "https://goo.gl/forms/SGizZXYwXDUiTgVY2"  (:i :class "fa-solid fa-bug")))
				(:li :align "center" (:a :href "dodvendlogout"  (:i :class "fa fa-sign-out" :aria-hidden "true") "&nbsp;&nbsp;")))))))))
  
  

;; ----------------------------------------------------------------------------
;; 段：vendor 登录动作（密码 / OTP / OTP v2）+ session 写入
;; ----------------------------------------------------------------------------
(defun dod-controller-vend-login ()
  "vendor 经典手机+密码登录处理（POST dodvendlogin）。
   登录失败跳 vendor-login.html，成功跳 home。"
  (let  ((phone (hunchentoot:parameter "phone"))
	 (password (hunchentoot:parameter "password")))
    (unless (and  ( or (null phone) (zerop (length phone)))
		  (or (null password) (zerop (length password))))
      (if (equal (dod-vend-login :phone  phone :password  password) NIL) 
	  (hunchentoot:redirect "/hhub/vendor-login.html")
	  ;else
	  (hunchentoot:redirect "/hhub/dodvendindex?context=home")))))


(defun dod-controller-vend-login-otpstep ()
  "OTP 登录第一步：根据 phone 生成 OTP（短信下发）并跳到 hhubvendloginwithotp 页。"
  (let* ((phone  (hunchentoot:parameter "phone"))
	 (context (format nil "hhubvendloginwithotp?phone=~A" phone)))
    (generateotp&redirect "vendor" "login" phone context)))

(defun dod-controller-vend-login-with-otp ()
  "OTP 登录第二步：phone 提交后调 dod-vend-login-with-otp；失败回到 v2 登录页，
   成功跳 home。"
  (let  ((phone (hunchentoot:parameter "phone")))
    (unless ( or (null phone) (zerop (length phone)))
      (unless (dod-vend-login-with-otp :phone phone)
	(hunchentoot:redirect "/hhub/hhubvendloginv2"))
      (hunchentoot:redirect "/hhub/dodvendindex?context=home"))))
      

(defun dod-vend-login-with-otp (&key phone)
  "OTP 登录核心：用 phone 找已审批 (approved-flag='Y' 且 status='APPROVED' 且未软删) 的
   vendor，绑定 vendor company 后调 set-vendor-session-params 写 session。
   重复登录被自身阻止（:login-vendor-name 已存在则跳过）。
   遇到 MySQL 2006 错误（连接超时）会捕获——但具体处理在 handler-case 后续；推测：
   原作者计划这里做重连，注意当前实现可能仅捕获不重连。"
  (handler-case
      (let* ((dbvendor (car (clsql:select 'dod-vend-profile :where [and
					  [= [:phone] phone]
					  [= [:approved-flag] "Y"]
					  [= [:approval-status] "APPROVED"]
					  [= [:deleted-state] "N"]]
				   :caching nil :flatp t)))
	     (vendor-company (if dbvendor  (get-vendor-company dbvendor))))
	(when (and  dbvendor
		    (null (hunchentoot:session-value :login-vendor-name))) ;; vendor should not be logged-in in the first place.
	  (set-vendor-session-params  vendor-company dbvendor)))
	;; Lets work on the domain objects here.
	;; (setup-domain-vendor *HHUBBUSINESSSERVER* phone))))
	;;handle the exception. 
    (clsql:sql-database-data-error (condition)
      (if (equal (clsql:sql-error-error-id condition) 2006 ) 
	  (progn
	    (stop-das) 
	    (start-das)
	    (hunchentoot:redirect "/hhub/hhubvendloginv2"))))))
      
(defun dod-vend-login (&key phone password )
  "经典手机+密码登录核心：phone 找已审批 vendor，check-password 验证密码后调
   set-vendor-session-params 写 session。
   2006 错误同样触发 stop/start-das 自愈跳到登录页。"
  (handler-case
      (let* ((dbvendor (car (clsql:select 'dod-vend-profile :where [and
					  [= [slot-value 'dod-vend-profile 'phone] phone]
					  [= [:approved-flag] "Y"]
					  [= [:approval-status] "APPROVED"]
					  [= [:deleted-state] "N"]]
				   :caching nil :flatp t)))
	     (pwd (if dbvendor (slot-value dbvendor 'password)))
	     (salt (if dbvendor (slot-value dbvendor 'salt)))
	     (password-verified (if dbvendor  (check-password password salt pwd)))
	     (vendor-company (if dbvendor  (get-vendor-company dbvendor))))
					;(log (if password-verified (hunchentoot:log-message* :info (format nil  "phone : ~A password : ~A" phone password)))))
	(when (and dbvendor
		   password-verified
		   (null (hunchentoot:session-value :login-vendor-name))) ;; vendor should not be logged-in in the first place.
	  (set-vendor-session-params  vendor-company dbvendor)))
    ;; handle the exception
    (clsql:sql-database-data-error (condition)
      (if (equal (clsql:sql-error-error-id condition) 2006 ) 
	  (progn
	    (stop-das) 
	    (start-das)
	    (hunchentoot:redirect "/hhub/hhubvendloginv2"))))))

(defun dod-controller-vendor-switch-tenant ()
  "切换 tenant：把当前 vendor 的 session 重新绑定到选中的 company。"
  (with-vend-session-check
    (let* ((company (select-company-by-id (hunchentoot:parameter "id")))
	   (vendor (get-login-vendor)))
      (progn
	(set-vendor-session-params company vendor)
	(hunchentoot:redirect "/hhub/dodvendindex?context=home")))))




(defun set-vendor-session-params (company  vendor)
  "vendor 登录后写入 hunchentoot session 与 BusinessContext 的核心函数。
   会把以下键写入 hunchentoot session：
     :login-vendor / :login-vendor-name / :login-vendor-id /
     :login-vendor-tenant-id / :login-vendor-company-name / :login-vendor-company /
     :login-vendor-currency / :login-vendor-invoice-settings /
     :login-vendor-tenants / :order-func-list / :vendor-order-items-hashtable /
     :login-vendor-products-functions / :login-vendor-settings-ht /
     :login-prd-cache / :session-invoices-ht / :login-shopping-cart /
     :login-vendor-business-session-id
   同时创建 VendorSessionObject 注册到 'vendorsite' BusinessContext，并通过
   enforcevendorsession 限制最大并发 vendor 登录数 *HHUBMAXVENDORLOGINS*。
   返回：sessionkey。"
  ;; Add the vendor object and the tenant to the Business Session
  ;;set vendor company related params

  (let ((vsessionobj (make-instance 'VendorSessionObject)))
    (setf (slot-value vsessionobj 'vwebsession) (hunchentoot:start-session))
    (setf hunchentoot:*session-max-time* (* 3600 8))
    (setf (hunchentoot:session-value :login-vendor ) vendor)
    (setf (slot-value vsessionobj 'vendor) vendor)
    (setf (hunchentoot:session-value :login-vendor-name) (slot-value vendor 'name))
    (setf (slot-value vsessionobj 'vendor-name) (slot-value vendor 'name))
    (setf (hunchentoot:session-value :login-vendor-id) (slot-value vendor 'row-id))
    (setf (slot-value vsessionobj 'vendor-id) (slot-value vendor 'row-id))
    (setf (hunchentoot:session-value :login-vendor-tenant-id) (slot-value company 'row-id ))
    (setf (slot-value vsessionobj 'vendor-tenant-id) (slot-value company 'row-id))
    (setf (hunchentoot:session-value :login-vendor-company-name) (slot-value company 'name))
    (setf (slot-value vsessionobj 'companyname) (slot-value company 'name))
    (setf (hunchentoot:session-value :login-vendor-company) company)
    (setf (hunchentoot:session-value :login-vendor-currency) (get-account-currency company))
    (setf (hunchentoot:session-value :login-vendor-invoice-settings) (read-from-string (slot-value vendor 'invoice-settings)))
    ;;(setf (hunchentoot:session-value :login-prd-cache )  (select-products-by-company company))
    ;;set vendor related params 
    (if vendor (setf (hunchentoot:session-value :login-vendor-tenants) (get-vendor-tenants-as-companies vendor)))
    (if vendor (setf (hunchentoot:session-value :order-func-list) (dod-gen-order-functions vendor company)))
    (if vendor (setf (hunchentoot:session-value :vendor-order-items-hashtable) (make-hash-table)))
    (if vendor (setf (hunchentoot:session-value :login-vendor-products-functions) (dod-gen-vendor-products-functions vendor company)))
    (if vendor (setf (hunchentoot:session-value :login-vendor-settings-ht) (make-hash-table :test 'equal)))
    (if vendor (setf (hunchentoot:session-value :login-prd-cache )  (remove nil (select-products-by-vendor vendor  company))))
    (if vendor (setf (hunchentoot:session-value :session-invoices-ht) (make-hash-table :test 'equal)))
    (if vendor (setf (hunchentoot:session-value :login-shopping-cart) '()))
    ;; Add vendor settings to the session. 
    (addloginvendorsettings)
    (let* ((bcontext (getBusinessContext *HHUBBUSINESSSERVER* "vendorsite"))
	   (sessionkey (createBusinessSession bcontext vsessionobj)))
      (setf (hunchentoot:session-value :login-vendor-business-session-id) sessionkey)
      (logiamhere (format nil "current web session is ~A" (slot-value vsessionobj 'vwebsession)))
      (logiamhere (format nil "current session key is ~A" sessionkey))
      (enforcevendorsession sessionkey bcontext  *HHUBMAXVENDORLOGINS*)
      (logiamhere (format nil "after enforcing sessions current web session is ~A" (slot-value vsessionobj 'vwebsession)))
      sessionkey)))


(defun get-vendor-invoice-settings ()
  "返回当前 vendor 的发票设置（plist）。若 session 中没有，则用 *invoice-settings* 兜底。"
  (let ((vinvsettingstr (hunchentoot:session-value :login-vendor-invoice-settings))
	(defaultinvsettings *invoice-settings*))
    (if (and vinvsettingstr (> (length vinvsettingstr) 0)) 
	;; if invoice settings are defined for a vendor, return it. 
	(read-from-string vinvsettingstr)
	;;else return the default invoice settings.
	defaultinvsettings)))


(defun addloginvendorsettings ()
  "把当前 vendor 的支付方式开关读出来后写入 session :login-vendor-settings-ht。
   登录时由 set-vendor-session-params 调用。"
  (let* ((company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (adapter (make-instance 'VPaymentMethodsAdapter))
	 (requestmodel (make-instance 'VPaymentMethodsRequestModel
				      :company company
				      :vendor vendor))
	(vpaymentmethods (processreadrequest adapter requestmodel)))
    (when (typep vpaymentmethods 'VPaymentMethods) 
      (with-slots (codenabled upienabled payprovidersenabled walletenabled paylaterenabled) vpaymentmethods
	(addloginvendorsetting "codenabled" codenabled)
	(addloginvendorsetting "upienabled" upienabled)
	(addloginvendorsetting "payprovidersenabled" payprovidersenabled)
	(addloginvendorsetting "walletenabled" walletenabled)
	(addloginvendorsetting "paylaterenabled" paylaterenabled)))))
  


(defun addloginvendorsetting (key value)
  "把 (key, value) 写入 vendor session 的 :login-vendor-settings-ht 哈希表。"
  (setf (gethash key (hunchentoot:session-value :login-vendor-settings-ht)) value))


(defun getloginvendorcount ()
  "返回 'vendorsite' BusinessContext 中当前活跃 vendor 数（全平台）。"
  (let* ((bcontext (getBusinessContext *HHUBBUSINESSSERVER* "vendorsite"))
	 (bsessions-ht (businesssessions-ht bcontext)))
    (hash-table-count bsessions-ht)))

(defun getloginvendorsessionstarttime ()
  "返回当前 vendor 业务 session 的 start-time（仅当 hunchentoot session 与业务 session
   一致时返回，否则返回 0）。"
  (let* ((bcontext (getBusinessContext *HHUBBUSINESSSERVER* "vendorsite"))
	 (sessionkey (hunchentoot:session-value :login-vendor-business-session-id))
	 (bsession (when sessionkey (getbusinesssession bcontext sessionkey)))
	 (start-time (if (and hunchentoot:*session* (eql bsession hunchentoot:*session*)) (start-time bsession) 0)))
    start-time))



(defun resetvendorsessions (sessionkey)
  "强制下线 vendor 的指定业务 session：先 hunchentoot:remove-session，
   再 deleteBusinessSession。"
  (let* ((bcontext (getBusinessContext *HHUBBUSINESSSERVER* "vendorsite"))
	 (bsessions-ht (businesssessions-ht bcontext))
	 (bvendorsession (gethash sessionkey bsessions-ht))
	 (vendorwebsession (slot-value bvendorsession 'vwebsession)))
    (if vendorwebsession (hunchentoot:remove-session vendorwebsession))  
    (deleteBusinessSession bcontext sessionkey)))

(defun enforcevendorsession (sessionkey bcontext maxvendorsallowed)
  "限制单个 vendor 同时活跃的 session 数。
   流程：
     1) 扫描全部业务 session，找到同一 vendor-id 的旧 session；
     2) 当数量达到 maxvendorsallowed（*HHUBMAXVENDORLOGINS*）时，
        踢掉最早的一个：remove-session + deleteBusinessSession。
   备注：当前实现只踢掉列表 nth 0（即第一个发现的），不一定是最旧的——
        推测：因为 hash-table maphash 顺序未定义，但实际效果"踢掉一个"足够。"
  (let* ((bsessions-ht (businesssessions-ht bcontext))
	 (bvendorsession (gethash sessionkey bsessions-ht))
	 (currentwebsession (slot-value bvendorsession 'vwebsession))
	 (vendor (slot-value bvendorsession 'vendor))
	 (sessionlist '())
	 (keylist '()))
    (maphash (lambda (k v)
	       (let ((prevvendorid (slot-value v 'vendor-id))
		     (prevwebsession (slot-value v 'vwebsession))
		     (loginvendorid (slot-value vendor 'row-id))
		     (vendorname (slot-value vendor 'name)))
		 (when (and
			(not (equal k sessionkey)) ;; There are 2 separate sessions from same user. 
			(= prevvendorid loginvendorid)) ;; Same user is login again.
		   (logiamhere (format nil "Vendor is ~A. key is ~A. Websession is ~A" vendorname k prevwebsession))
		   (setf sessionlist (append sessionlist (list v)))
		   (setf keylist (append keylist (list k)))))) bsessions-ht)
    ;; If there are exactly 1 item in the list that means that user has logged in previouly. 
    (when (>= (length sessionlist) maxvendorsallowed)
      (let* ((sessiontoremove (nth 0 sessionlist))
	     (websession (slot-value sessiontoremove 'vwebsession))
	     (firstkey (nth 0 keylist)))
	(logiamhere (format nil "logging off vendor websession ~A" websession))
	(hunchentoot:remove-session websession)
	(deleteBusinessSession bcontext firstkey)))
    (logiamhere (format nil "After logging off current session is ~A" currentwebsession))))

   
(defun dod-controller-vendor-delete-product ()
  "vendor 删除商品控制器。前提：该商品没有未履约订单（pending order items 长度=0）。
   删除后清商品缓存，跳到商品列表。会话失效跳 vendor-login。
   备注：从语义看，'pending=0 才能删' 是软约束，但代码并没有告知用户被拒绝原因；
        推测：原作者认为前端已禁用按钮，后端是双重保险。"
 (if (is-dod-vend-session-valid?)
  (let ((id (hunchentoot:parameter "id")))
    (if (= (length (get-pending-order-items-for-vendor-by-product (select-product-by-id id (get-login-vendor-company)) (get-login-vendor))) 0)
	(progn 
	  (delete-product id (get-login-vendor-company))
	  (setf (hunchentoot:session-value :login-vendor-products-functions) (dod-gen-vendor-products-functions (get-login-vendor) (get-login-vendor-company)))))   
    (hunchentoot:redirect "/hhub/dodvenproducts"))
     	(hunchentoot:redirect "/hhub/hhubvendloginv2"))) 

;; ----------------------------------------------------------------------------
;; 段：vendor 商品详情页 / 启用 / 禁用 / 复制
;; ----------------------------------------------------------------------------
(defun create-model-for-prddetailsforvendor ()
  "拉商品详情数据并替换核心模板 2 号中占位符（%Product Name%、
   %Unit-Of-Measure%、%Qty-Per-Unit%、%Product-SKU%、%Product-Description%、
   %Units-In-Stock%、%Product-Pricing-Control%、%Product-Images-Carousel%、
   %Product-Images-Thumbnails%）后返回。"
  (let* ((prd-id (parse-integer (hunchentoot:parameter "id")))
	 (productlist (if (> prd-id 0) (hhub-get-cached-vendor-products)))
	 (product (if (> prd-id 0) (search-item-in-list 'row-id prd-id productlist)))
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
	 (proddetailpagetempl (funcall (nst-get-cached-product-template-func :templatenum 2)))	 
	 (unit-of-measure (slot-value product 'unit-of-measure))
	 (qtyperunit-str (format nil "~A" (slot-value product 'qty-per-unit)))
	 (unitsinstock-str (format nil "~A" (slot-value product 'units-in-stock))))
	 
	 
    
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product Name%" proddetailpagetempl prd-name))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Unit-Of-Measure%" proddetailpagetempl unit-of-measure))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Qty-Per-Unit%" proddetailpagetempl qtyperunit-str))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-SKU%" proddetailpagetempl product-sku))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Description%" proddetailpagetempl description))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Units-In-Stock%" proddetailpagetempl unitsinstock-str))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Pricing-Control%" proddetailpagetempl product-pricing-widget))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Images-Carousel%" proddetailpagetempl product-images-carousel))
    (setf proddetailpagetempl (cl-ppcre:regex-replace-all "%Product-Images-Thumbnails%" proddetailpagetempl product-images-thumbnails))
    
    (function (lambda ()
      (values proddetailpagetempl  product )))))
  
(defun create-widgets-for-prddetailsforvendor (modelfunc)
  "渲染商品详情页：上方商品操作菜单（vendor-product-actions-menu），下方模板正文。"
  (multiple-value-bind (proddetailpagetempl product) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-catch-submit-event "idproductdetailsforvendor" 
			 ;; display the product actions menu
			 (vendor-product-actions-menu product))))))
	  (widget2  (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(cl-who:str proddetailpagetempl))))))
      (list widget1  widget2))))

(defun dod-controller-prd-details-for-vendor ()
  "商品详情页（dodprddetailsforvendor?id=<prd-id>）。
   注意：使用 with-cust-session-check（推测：原作者笔误，应为 with-vend-session-check）。"
  (with-cust-session-check
    (with-mvc-ui-page "Product Details for Vendor" #'create-model-for-prddetailsforvendor  #'create-widgets-for-prddetailsforvendor :role :vendor)))
		
(defun dod-controller-vendor-deactivate-product ()
  "禁用商品（active-flag='N'），清缓存后跳商品列表。"
  (with-vend-session-check
    (let ((id (parse-integer (hunchentoot:parameter "id"))))
      (deactivate-product id (get-login-vendor-company))
      (setf (hunchentoot:session-value :login-vendor-products-functions) (dod-gen-vendor-products-functions (get-login-vendor) (get-login-vendor-company)))   
      (hunchentoot:redirect "/hhub/dodvenproducts"))))

(defun dod-controller-vendor-activate-product ()
  "启用商品（active-flag='Y'），清缓存后跳商品列表。"
  (with-vend-session-check
    (let ((id (hunchentoot:parameter "id")))
      (activate-product id (get-login-vendor-company))
      (setf (hunchentoot:session-value :login-vendor-products-functions) (dod-gen-vendor-products-functions (get-login-vendor) (get-login-vendor-company)))   
      (hunchentoot:redirect "/hhub/dodvenproducts"))))

(defun dod-controller-vendor-copy-product ()
  "复制商品控制器。当前为空函数体（推测：占位，待实现）。"
)


;; ----------------------------------------------------------------------------
;; 段：vendor 商品列表 / 搜索 / 类目 / 删除/启用/禁用/复制
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-search-products ()
  "vendor 商品 ajax 搜索：search-products 模糊匹配，结果挂到 #txtvendsearchproductresult。"
  (with-vend-session-check
    (let* ((search-clause (hunchentoot:parameter "txtvendsearchproduct"))
	   (products (if (not (equal "" search-clause)) (search-products search-clause (get-login-vendor-company)))))
      (cl-who:with-html-output-to-string (*standard-output* nil)
	(:div :id "txtvendsearchproductresult" 
	      (cl-who:str (display-as-tiles products  'product-card-for-vendor "vendor-product-card")))))))
  
(defun dod-controller-vendor-product-categories-page ()
  "vendor 查看商品类目页（只读，备注：增删类目须联系平台 admin）。"
  (with-vend-session-check
    (let* ((company (get-login-vendor-company))
	   (categories (select-prdcatg-by-company company))
	   (catgcount (length categories)))
      (with-standard-vendor-page "Product Categories"
	(with-html-div-row :align "right"
	  (:span :class "badge" (cl-who:str (format nil " ~d " catgcount))))
	(:hr)
	(cl-who:str (display-as-table (list "Name") categories 'vendor-product-category-row))
	(:hr)
	(with-html-div-row
	  (:h4 "Note: Contact Administrator to create/delete the Product Categories."))
	;; We will write some javascript to give a success alert here. 
	(jscript-displaysuccess "Note: Contact Administrator to create/delete the Product Categories.")))))


	
(defun vendor-product-category-row (category &rest arguments)
  "渲染单行商品类目（仅 catg-name 一列）。"
  (declare (ignore arguments))
  (with-slots (row-id catg-name) category 
      (cl-who:with-html-output (*standard-output* nil)
	(:td  :height "10px" (cl-who:str catg-name)))))


(defun dod-controller-vendor-products ()
  "vendor 商品列表页（带搜索框 + 商品 tile 卡片）。"
  (with-vend-session-check
    (with-mvc-ui-page "Vendor Products" #'create-model-for-showvendorproducts #'create-widgets-for-showvendorproducts :role :vendor)))

(defun create-model-for-showvendorproducts ()
  "从 session 缓存拉 vendor 全部商品。"
  (let* ((vendor-products (hhub-get-cached-vendor-products))
	 (numproducts (length vendor-products)))
    (function (lambda ()
      (values vendor-products numproducts)))))
	
(defun create-widgets-for-showvendorproducts (modelfunc)
  "渲染商品页：顶部搜索框 + 数量徽章；下方商品卡片网格（display-as-tiles）。"
  (multiple-value-bind (vendor-products numproducts) (funcall modelfunc)
  (let ((widget1 (function (lambda ()
		   (cl-who:with-html-output (*standard-output* nil)    
		     (:br)
		     (with-html-div-row
		       (with-html-div-col-4
			 (with-html-search-form "idvendsearchproduct" "vendsearchproduct" "idtxtvendsearchproduct" "txtvendsearchproduct" "hhubvendsearchproduct" "onkeyupsearchform1event();" "Type few letters of Product Name"
			   (submitsearchform1event-js "#idtxtvendsearchproduct" "#txtvendsearchproductresult")))
		       (with-html-div-col-4 
			 (:span :class "position-absolute top-50 start-50 translate-middle badge rounded-pill bg-danger" (:h5 (cl-who:str (format nil "~A" numproducts))))))))))
	(widget2 (function (lambda ()
		   (cl-who:with-html-output (*standard-output* nil)    
		     (:hr)
		     (with-catch-submit-event "txtvendsearchproductresult"
		       (cl-who:str (display-as-tiles vendor-products  'product-card-for-vendor "vendor-product-card"))))))))
    (list widget1 widget2 ))))

;; ----------------------------------------------------------------------------
;; 段：vendor session 缓存生成器（products / categories / orders）
;; 用闭包延迟绑定，登录时调一次缓存数据，登出/手动刷新时 reset。
;; ----------------------------------------------------------------------------
(defun dod-gen-vendor-products-functions (vendor company)
  "生成 vendor 商品/类目缓存的 4 个闭包：
     1) vendor-products       —— select-products-by-vendor
     2) product-categories    —— select-prdcatg-by-company
     3) active-vendor-products—— select-active-products-by-vendor
     4) company-products      —— select-products-by-company"
  (let ((vendor-products (select-products-by-vendor vendor company))
	(product-categories (select-prdcatg-by-company company))
	(active-vendor-products (select-active-products-by-vendor vendor company))
	(company-products (select-products-by-company company)))
    (list (function (lambda () vendor-products))
	  (function (lambda () product-categories))
	  (function (lambda () active-vendor-products))
	  (function (lambda () company-products)))))

(defun dod-gen-order-functions (vendor company)
  "生成 vendor 订单缓存 4 个闭包：pending-orders / completed-orders /
   order-items（前后 30 天）/ completed-orders-today。每条都限制 500 条。"
(let ((pending-orders (get-orders-for-vendor vendor 500 company ))
      (completed-orders (get-orders-for-vendor vendor 500 company  "Y" ))
      (order-items (get-order-items-for-vendor  vendor  company)) ; Get order items for last 30 days and next 30 days. 
      (completed-orders-today (get-orders-for-vendor-by-shipped-date vendor (get-date-string-mysql (clsql-sys:get-date)) company "Y"))) 

  (list (function (lambda () pending-orders ))
	(function (lambda () completed-orders))
	(function (lambda () order-items))
	(function (lambda () completed-orders-today)))))


(defun dod-reset-vendor-products-functions (vendor company)
  "重生成商品缓存闭包列表并写入 session :login-vendor-products-functions。
   增/删商品后由控制器调用以使下一次缓存命中拿到最新数据。"
  (let ((vendor-products-func-list (dod-gen-vendor-products-functions vendor company)))
    (setf (hunchentoot:session-value :login-vendor-products-functions) vendor-products-func-list)))

(defun dod-reset-order-functions (vendor company)
  "重生成订单缓存闭包列表并清空 vendor-order-items-hashtable。"
  (let ((order-func-list (dod-gen-order-functions vendor company)))
    (setf (hunchentoot:session-value :order-func-list) order-func-list)
    (setf (hunchentoot:session-value :vendor-order-items-hashtable) (make-hash-table))))

(defun hhub-get-cached-vendor-products ()
  "从 session 缓存（位置 0）拉 vendor 商品列表。"
  (let ((vendor-products-func (first (hunchentoot:session-value :login-vendor-products-functions))))
    (funcall vendor-products-func)))

(defun hhub-get-cached-product-categories ()
  "从 session 缓存（位置 1）拉商品类目列表。"
  (let ((vendor-products-func (second (hunchentoot:session-value :login-vendor-products-functions))))
    (funcall vendor-products-func)))

(defun hhub-get-cached-active-vendor-products ()
  "从 session 缓存（位置 2）拉启用的 vendor 商品列表。"
  (let ((vendor-products-func (third (hunchentoot:session-value :login-vendor-products-functions))))
    (funcall vendor-products-func)))

(defun hhub-get-cached-company-products ()
  "从 session 缓存（位置 3）拉公司全部商品列表。"
  (let ((vendor-products-func (fourth (hunchentoot:session-value :login-vendor-products-functions))))
    (funcall vendor-products-func)))

(defun dod-get-cached-pending-orders()
  "从 session 缓存拉待处理订单（pending-orders）。"
  (let ((pending-orders-func (nth 0 (hunchentoot:session-value :order-func-list))))
    (funcall pending-orders-func)))


(defun dod-get-cached-completed-orders ()
  "从 session 缓存拉历史完成订单（最多 500 条）。"
  (let ((completed-orders-func (nth 1 (hunchentoot:session-value :order-func-list))))
    (funcall completed-orders-func)))

(defun dod-get-cached-completed-orders-today ()
  "从 session 缓存拉今日完成订单。"
  (let ((completed-orders-func (nth 3 (hunchentoot:session-value :order-func-list))))
    (funcall completed-orders-func)))

(defun dod-get-cached-order-items-by-order-id (order-id order-func-list)
  "按 order-id 取订单明细（带 hashtable 二级缓存，键=order-id）。
   未命中时用 order-func-list 拉全量再过滤、塞进 hashtable。"
  ;; Add the order item to a hash table. Key - order-id to improve performance.
  ;; Discovered in May 2020
  ;; If the order-items are not found in the hash table, search them and add them to hash table.
  (let ((order-items-from-ht (get-ht-val order-id (hunchentoot:session-value :vendor-order-items-hashtable))))
    (if (null order-items-from-ht) 
	(let* ((order-items-func (nth 2 order-func-list))
               (order-items-list (funcall order-items-func))
	       (order-items (remove nil (mapcar (lambda (item)
						  (if (equal (slot-value item 'order-id) order-id) item)) order-items-list))))
	  (when (> (length order-items) 0)
            ;; save in the order items hashtable for faster access next time.
	    (setf (gethash order-id (hunchentoot:session-value :vendor-order-items-hashtable)) order-items)
	    ;; return order items
	    order-items))
	;;otherwise, return the retrieved items list from the hash table.
        order-items-from-ht)))


(defun dod-get-cached-order-items-by-product-id (prd-id order-func-list)
  "按 prd-id 取订单明细（带 hashtable 二级缓存，键=prd-id）。
   备注：与 by-order-id 共享同一张 vendor-order-items-hashtable，
        因此 order-id 与 prd-id 不能撞键（实际不会撞，因为它们是不同表的主键
        但放在同一个 ht 中是潜在风险——推测：原作者认为 ID 命名空间不重叠）。"
  ;; Add the order item to a hash table. Key - product-id to improve performance.
  ;; Discovered in Nov 2024
  ;; If the order-items are not found in the hash table, search them and add them to hash table.
  (let ((order-items-from-ht (get-ht-val prd-id (hunchentoot:session-value :vendor-order-items-hashtable))))
    (if (null order-items-from-ht) 
	(let* ((order-items-func (nth 2 order-func-list))
               (order-items-list (funcall order-items-func))
	       (order-items (delete nil (mapcar (lambda (item)
						  (if (equal (slot-value item 'prd-id) prd-id) item)) order-items-list))))
	  (when (> (length order-items) 0)
            ;; save in the order items hashtable for faster access next time.
	    (setf (gethash prd-id (hunchentoot:session-value :vendor-order-items-hashtable)) order-items)
	      ;; return order items
	      order-items))
	;;otherwise, return the retrieved items list from the hash table.
        order-items-from-ht)))

;; ----------------------------------------------------------------------------
;; 段：vendor 控制台主页 dod-vend-index（按 context 参数分发不同视图）
;; ----------------------------------------------------------------------------
(defun dod-controller-vend-index ()
  "vendor 后台主控制器，URL: /hhub/dodvendindex。
   按 ?context=xxx 渲染不同视图：
     home              —— 首页 4 张快捷卡（Orders / Today's Demand / Today's Revenue / Sale Invoices）
     pendingorders     —— 待处理订单 tile 列表
     completedorders   —— 已完成订单 tile 列表
     ctxordprd         —— 按商品聚合订单
     ctxordcus         —— 打印友好版本（按客户聚合）
     btnexpexl=Y 时跳到 dodvenexpexl 导出 Excel。"
  (with-vend-session-check
    (let ((dodorders (dod-get-cached-pending-orders ))
	  (reqdate (hunchentoot:parameter "reqdate"))
	  (btnexpexl (hunchentoot:parameter "btnexpexl"))
	  (context (hunchentoot:parameter "context")))
      (with-standard-vendor-page "Welcome Vendor"
	(:h3 "Welcome " (cl-who:str (format nil "~A" (get-login-vendor-name))))
	(:hr)
	(with-html-form "form-venorders" "dodvendindex"
	  (with-html-div-row :style "display: none"
	    (:div :class "btn-group" :role "group" :aria-label "..."
		  (:button  :name "btnpendord" :type "submit" :class "btn btn-default active" "Orders" )
		  (:button  :name "btnordcomp" :type "submit" :class "btn btn-default" "Completed Orders")))
					; (:hr)
	  (with-html-div-row :style "display: none"
	    (:div :class "col-sm-12 col-xs-12 col-md-12 col-lg-12" 
		  (:input :type "text" :name "reqdate" :placeholder "yyyy/mm/dd")
		  (:button :class "btn btn-primary" :type "submit" :name "btnordprd" "Get Orders by Products")
		  (:button :class "btn btn-primary" :type "submit" :name "btnordcus" "Get Orders by Customers")
		  (if (and reqdate dodorders)
		      (cl-who:htm (:a :href (format nil "/dodvenexpexl?reqdate=~A" (cl-who:escape-string reqdate)) :class "btn btn-primary" "Export To Excel")))
		  (:button :class "btn btn-primary"  :type "submit" :name "btnprint" :onclick "javascript:window.print();" "Print")))) 
					; (:hr)
	(cond ((equal context "ctxordprd") (ui-list-vendor-orders-by-products dodorders))
	      ((and dodorders btnexpexl) (hunchentoot:redirect (format nil "/hhub/dodvenexpexl?reqdate=~A" reqdate)))
	      ((equal context "ctxordcus") (ui-list-vendor-orders-by-customers dodorders))
	      ((equal context "home")	(cl-who:htm (:div :class "list-group col-xs-6 col-sm-6 col-md-6 col-lg-6" 
							  (:a :class "list-group-item list-group-item-action" :href "dodvendindex?context=pendingorders" " Orders " (:span :class "badge" (cl-who:str (format nil " ~d " (length dodorders)))))
							  (:a :class "list-group-item list-group-item-action" :href "dodvendindex?context=ctxordprd" "Todays Demand")
							  (:a :class "list-group-item list-group-item-action" :href (cl-who:str (format nil "dodvendrevenue"))  "Today's Revenue")
							  (:a :class "list-group-item list-group-item-action" :href (cl-who:str (format nil "displayinvoices"))  "Sale Invoices"))))
							  
	      
	      ((equal context "pendingorders") 
	       (progn (cl-who:htm (cl-who:str "Pending Orders") (:span :class "badge" (cl-who:str (format nil " ~d " (length dodorders))))
				  (:a :class "btn btn-primary btn-xs" :role "button" :href "dodrefreshpendingorders" (:i :class "fa-solid fa-arrows-rotate"))
				  (:a :class "btn btn-primary btn-xs" :role "button" :href "dodvendindex?context=ctxordcus" "Printer Friendly View")
				  (:a :class "btn btn-primary btn-xs" :role "button" :href "dodvenexpexl?type=pendingorders" "Export To Excel")
				  (:hr))
		      (cl-who:str (display-as-tiles dodorders 'vendor-order-card "order-box"))))
	      ((equal context "completedorders") (let* ((vorders (dod-get-cached-completed-orders))
							(lenorders (length vorders)))
						   (progn
						     (cl-who:htm (cl-who:str (format nil "Completed orders"))
								 (:span :class "badge" (cl-who:str (format nil " ~d " lenorders))) 
								 (when (> lenorders 0) (cl-who:htm (:a :class "btn btn-primary btn-xs" :role "button" :href "dodvenexpexl?type=completedorders" "Export To Excel")))
								 (:hr))
						     (cl-who:str(display-as-tiles vorders 'vendor-order-card "order-box"))))))))))
  


(defun com-hhub-transaction-vendor-order-setfulfilled ()
  "vendor 标记订单已履约控制器（com-hhub-transaction-* 命名约定，触发 PEP/PDP）。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendorsetorderfulfilled #'create-widgets-for-genericredirect)))

(defun create-model-for-vendorsetorderfulfilled ()
  "标记订单履约：
   - 若 payment-mode='PRE'（预付/钱包），先 check-wallet-balance 验证客户余额；
     不够则跳到钱包详情页提示。
   - 否则调 set-order-fulfilled 'Y' 把履约标志写库（数据库变更走后台）。
   完成后跳到 pendingorders。"
  (let* ((id (hunchentoot:parameter "id"))
	 (company-instance (hunchentoot:session-value :login-vendor-company))
	 (order-instance (get-order-by-id id company-instance))
	 (payment-mode (slot-value order-instance 'payment-mode))
	 (customer (get-customer order-instance)) 
	 (vendor (get-login-vendor))
	 (wallet (get-cust-wallet-by-vendor customer vendor company-instance))
	 (vendor-order-items (get-order-items-for-vendor-by-order-id  order-instance (get-login-vendor) ))
	 (vorderitemstotal (get-order-items-total-for-vendor vendor  vendor-order-items))
	 (redirecturl "/hhub/dodvendindex?context=pendingorders")
	 (params nil))

	 (setf params (acons "uri" (hunchentoot:request-uri*)  params))
	 (setf params (acons "company" company-instance params))
	 (with-hhub-transaction "com-hhub-transaction-vendor-order-setfulfilled"  params   
	   (progn
	     (if (equal payment-mode "PRE")
		 (unless (check-wallet-balance vorderitemstotal wallet)
		   (display-wallet-for-customer wallet "Not enough balance for the transaction.")))
	     ;; We will make all the database changes in the background. 
	     (set-order-fulfilled "Y" vendor  order-instance company-instance)))
    (function (lambda ()
      (values redirecturl)))))

(defun display-wallet-for-customer (wallet-instance custom-message)
  "展示客户钱包卡片（用于余额不足等错误页）。"
  (with-standard-vendor-page (:title "Wallet Display")
    (wallet-card wallet-instance custom-message)))

(defun dod-controller-ven-expexl ()
  "vendor 订单导出 Excel/CSV 控制器（dodvenexpexl?type=pendingorders|completedorders）。
   返回 text/csv，文件名 Orders_<date>.csv，UTF-8 BOM。会话失效跳登录页。"
    (if (is-dod-vend-session-valid?)
	(let ((type (hunchentoot:parameter "type"))
	      (header (list "Product " "Quantity" "Qty per unit" "Unit Price" "Discount%" "Total Amt"))
	      (today (get-date-string (clsql-sys:get-date))))
	      (setf (hunchentoot:content-type*) "text/csv; charset=UTF-8; BOM")
	      (setf (hunchentoot:header-out "Content-Disposition" ) (format nil "inline; filename=Orders_~A.csv" today))
	      (cond ((equal type "pendingorders") (ui-list-orders-for-excel header (dod-get-cached-pending-orders)))
		    ((equal type "completedorders") (ui-list-orders-for-excel header (dod-get-cached-completed-orders)))))
	(hunchentoot:redirect "/hhub/hhubvendloginv2")))



;; ----------------------------------------------------------------------------
;; 段：vendor session 访问器（统一从 hunchentoot session 读出当前登录信息）
;; ----------------------------------------------------------------------------
(defun get-login-vendor ()
    :documentation "Get the login session for vendor.
   中文：从 session 取当前登录的 vendor 实例。"
    (hunchentoot:session-value :login-vendor ))
(defun get-login-vendor-id ()
  :documentation "Get the ID of the login vendor.
   中文：返回当前登录 vendor 的 row-id。"
  (let ((vendor (get-login-vendor)))
    (slot-value vendor 'row-id)))

(defun get-login-vendor-setting (key)
  :documentation "Gets the login vendor settings.
   中文：从 session :login-vendor-settings-ht 拿单条设置值。"
  (gethash key (hunchentoot:session-value :login-vendor-settings-ht)))

(defun get-login-vend-company ()
    :documentation "Get the login vendor company.
   中文：返回当前登录 vendor 所属 company（注意：与 get-login-vendor-company 不同源——
   后者是另一个键，需要核对调用一致性；本函数读 :login-vendor-company）。"
    ( hunchentoot:session-value :login-vendor-company))

(defun get-login-vendor-tenant-id ()
  :documentation "Get the login vendor tenant-id.
   中文：返回当前登录 vendor 所在 tenant 的 id（来自 :login-vendor-tenant-id session 键）。"
  (hunchentoot:session-value :login-vendor-tenant-id))

(defun is-dod-vend-session-valid? ()
    :documentation "Checks whether the current login session is valid or not.
   中文：判断当前 hunchentoot session 是否有 vendor 登录（看 :login-vendor-name 是否非 nil）。"
    (if  (null (get-login-vendor-name)) NIL T))

(defun get-login-vendor-name ()
    :documentation "Gets the name of the currently logged in vendor.
   中文：返回 :login-vendor-name session 值；nil 表示未登录。"
    (hunchentoot:session-value :login-vendor-name))


;; ----------------------------------------------------------------------------
;; 段：vendor 登出 / 卡片 / 订单详情 modal / 订单详情页
;; ----------------------------------------------------------------------------
(defun dod-controller-vendor-logout ()
    :documentation "Vendor logout.
   中文：vendor 登出：移除 hunchentoot session 与 BusinessSession，
   有 company.website 则跳到该网址，否则跳 *siteurl*。"
    (let* ((vc (get-login-vendor-company))
	   (company-website (if vc (slot-value vc 'website))))
      (when hunchentoot:*session* (hunchentoot:remove-session hunchentoot:*session*))
      (deleteBusinessSession (getBusinessContext *HHUBBUSINESSSERVER* "vendorsite") (hunchentoot:session-value :login-vendor-business-session-id)) 
      
      (if (> (length company-website) 0)  (hunchentoot:redirect (format nil "http://~A" company-website)) 
	  ;;else
	  (hunchentoot:redirect *siteurl*))))




(defun vendor-details-card (vendor-instance)
  "渲染 vendor 详情卡片（名 / 地址 / 电话 + WhatsApp / 头像）。"
  (let ((vend-name (slot-value vendor-instance 'name))
	(vend-address  (slot-value vendor-instance 'address))
	(phone (slot-value vendor-instance 'phone))
	(picture-path (slot-value vendor-instance 'picture-path)))
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row
	(with-html-div-col 
	  (:h4 (cl-who:str vend-name))))
      (with-html-div-row
	(with-html-div-col
	  (:h5 (cl-who:str vend-address))))
      (with-html-div-row
	(with-html-div-col
	  (:h4  (cl-who:str phone)))
	(with-html-div-col
	  (:a :target "_blank" :href (createwhatsapplink phone) (:img :src (format nil "/img/~A" *HHUBWHATSAPPBUTTONIMG*) :alt "Chat on WhatsApp" " "))))
      (with-html-div-row
        (:div :class "col-sm-12 col-xs-12 col-md-6 col-lg-6 image-responsive"
	      (:img :src  (format nil "~A" picture-path) :height "300" :width "400" :alt vend-name " "))))))
		  


(defun modal.vendor-order-details (vorder-instance company)
  "渲染单条 vendor 订单的详情 modal：商品列表（含 SGST/CGST/IGST）+ 总额 +
   钱包余额警告（如果是 PRE 预付且余额不足）+ '取消订单' 或 '完成订单' 按钮 +
   存储拣货标志（store pickup）戳印。"
  (let* ((customer (if vorder-instance (get-customer vorder-instance)))
	 (wallet (if customer (get-cust-wallet-by-vendor customer (get-login-vendor) company)))
	 (balance (if wallet (slot-value wallet 'balance) 0))
	 (venorderfulfilled (if vorder-instance (slot-value vorder-instance 'fulfilled)))
	 (mainorder (get-order-by-id (slot-value vorder-instance 'order-id) company))
	 (order-id (if mainorder (slot-value mainorder 'row-id)))
	 (payment-mode (if mainorder (slot-value mainorder 'payment-mode)))
	 (header (list "Product" "Product Qty" "Unit Price" "SGST" "CGST" "IGST"  "Sub-total"))
	 (odtlst (if mainorder (dod-get-cached-order-items-by-order-id (slot-value mainorder 'row-id) (hunchentoot:session-value :order-func-list) )) )
	 (order-amt (slot-value vorder-instance 'order-amt))
	 (shipping-cost (slot-value vorder-instance 'shipping-cost))
	 (storepickupenabled (slot-value vorder-instance 'storepickupenabled))
	 (total (if shipping-cost (+ order-amt shipping-cost) order-amt))
	 (lowwalletbalance (< balance total))
	 (currsymbol (get-currency-html-symbol (get-account-currency company))))
    
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row
	(:div :class "col" :align "right"
	      (when (and shipping-cost (> shipping-cost 0))
                (cl-who:htm
		 (:p (cl-who:str (format nil "Shipping: ~A ~$" currsymbol shipping-cost)))
		 (:p (cl-who:str (format nil "Sub Total: ~A ~$" currsymbol order-amt)))))))
      (with-html-div-row 
	(:div :class "col-md-12" :align "right" 
	      (if (and lowwalletbalance (equal payment-mode "PRE")) 
		  (cl-who:htm (:h2 (:span :class "label label-danger" (cl-who:str (format nil "Low wallet Balance = Rs ~$" balance))))))
					;else
	      (:h3 (:span :class "label label-success" (cl-who:str (format nil "Total: ~A ~$" currsymbol total))))
	      (if (equal venorderfulfilled "N") 
		  (cl-who:htm
		   (with-html-form "form-vendordercancel" "dodvenordcancel" 
		     (with-html-input-text-hidden "id" order-id)
		     (:div :class "form-group" :style "display:block"
			   (:input :type "submit"  :class "btn btn-primary" :value "Cancel Order")))))
	      (if (equal venorderfulfilled "Y") 
		  (cl-who:htm (:span :class "label label-info" "FULFILLED"))
		  ;; ELSE
		  ;; Convert the complete button to a submit button and introduce a form here. 
		  (cl-who:htm
		   (with-html-form "form-vendordercomplete" "dodvenordfulfilled"
		     (:input :type "hidden" :name "id" :value order-id)
		     ;; (:a :onclick "return CancelConfirm();" :href (format nil "dodvenordcancel?id=~A" (slot-value order 'row-id) ) (:span :class "btn btn-primary"  "Cancel")) "&nbsp;&nbsp;"
		     (:div :class "form-group"
			   (if mainorder ;; if the order is present only then show the complete button. 
			       (cl-who:htm (:input :type "submit"  :class "btn btn-primary" :value "Fulfill Order")))))))))
      (when (and (equal storepickupenabled "Y") (= shipping-cost 0.00))
	(cl-who:htm
	 (:div :align "right" :class "stampbox-big rotated" "Store Pickup")))
      (if odtlst (ui-list-vend-orderdetails header odtlst currsymbol) "No order details")
      (if mainorder (display-order-header-for-vendor mainorder)))))

(defun dod-controller-vendor-orderdetails ()
  "vendor 订单详情整页（带主单 header + 订单条目 + 总额操作区 widget）。"
  (with-vend-session-check
    (with-mvc-ui-page "Vendor Order Details" #'create-model-for-vendororderdetails #'create-widgets-for-vendororderdetails :role :vendor)))

(defun create-model-for-vendororderdetails ()
  "拉 vendor 订单详情数据：主单 + vendor 子单 + customer 钱包余额 + 商品条目 + 总额。
   钱包余额低于总额（PRE 模式）时设 lowwalletbalance=T，控件会提示。"
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (dodvenorder (get-vendor-orders-by-orderid (hunchentoot:parameter "id") vendor company))
	 (customer (get-customer dodvenorder))
	 (wallet (get-cust-wallet-by-vendor customer vendor company))
	 (balance (slot-value wallet 'balance))
	 (venorderfulfilled (if dodvenorder (slot-value dodvenorder 'fulfilled)))
	 (order (get-order-by-id (hunchentoot:parameter "id") company))
	 (order-id (if order (slot-value order 'row-id)))
	 (payment-mode (slot-value order 'payment-mode))
	 (header (list "Product" "Product Qty" "Unit Price"  "Sub-total"))
	 (odtlst (if order (dod-get-cached-order-items-by-order-id (slot-value order 'row-id) (hunchentoot:session-value :order-func-list)  )) )
	 (total (reduce #'+  (mapcar (lambda (odt)
				       (* (slot-value odt 'current-price) (slot-value odt 'prd-qty))) odtlst)))
	 (lowwalletbalance (< balance total))
	 (currsymbol (get-currency-html-symbol (get-account-currency company))))
    (function (lambda ()
      (values order order-id header odtlst lowwalletbalance payment-mode balance total venorderfulfilled currsymbol)))))

(defun create-widgets-for-vendororderdetails (modelfunc)
  "渲染订单详情页 3 个 widget：主单 header / 订单条目表格 / 总额 + 操作按钮。"
  (multiple-value-bind (order order-id header odtlst lowwalletbalance payment-mode balance total venorderfulfilled currsymbol) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (if order (display-order-header-for-vendor  order))))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (if odtlst (ui-list-vend-orderdetails header odtlst currsymbol) "No order details")))))
	  (widget3 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row 
			 (:div :class "col-md-12" :align "right" 
			       (if (and lowwalletbalance (equal payment-mode "PRE")) 
				   (cl-who:htm (:h2 (:span :class "label label-danger" (cl-who:str (format nil "Low wallet Balance = Rs ~$" balance))))))
			       ;; else
			       (:h2 (:span :class "label label-default" (cl-who:str (format nil "Total = Rs ~$" total))))
			       (if (equal venorderfulfilled "Y") 
				   (cl-who:htm (:span :class "label label-info" "FULFILLED"))
				   ;; ELSE
				   ;; Convert the complete button to a submit button and introduce a form here. 
				   (cl-who:htm 
				    ;; (:a :onclick "return CancelConfirm();" :href (format nil "dodvenordcancel?id=~A" (slot-value order 'row-id) ) (:span :class "btn btn-primary"  "Cancel")) "&nbsp;&nbsp;"
				    (:a :href (format nil "dodvenordfulfilled?id=~A" order-id ) (:span :class "btn btn-primary"  "Complete")))))))))))
      (list widget1 widget2 widget3))))




(defun ui-list-vend-orderdetails (header data currsymbol)
  "渲染 vendor 订单条目表格（7 列：商品名 / 数量 / 单价（taxable）/ SGST / CGST / IGST / 小计）。
   每个税都用 'amt @ pct%' 形式展示。data 可以是单条或列表。"
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class  "panel panel-default"
	    (:div :class "panel-heading" "Order Items")
	    (:div :class "panel-body"
		  (:table :class "table table-hover"  
			  (:thead (:tr
				   (mapcar (lambda (item) (cl-who:htm (:th (cl-who:str item)))) header))) 
			  (:tbody
			   (mapcar (lambda (odt)
				     (let* ((odt-product  (get-item-product odt))
					    (prd-qty (slot-value odt 'prd-qty))
					    (sgst (slot-value odt 'sgst))
					    (sgstamt (slot-value odt 'sgstamt))
					    (cgst (slot-value odt 'cgst))
					    (cgstamt (slot-value odt 'cgstamt))
					    (igst (slot-value odt 'igst))
					    (igstamt (slot-value odt 'igstamt))
					    (taxablevalue (slot-value odt 'taxablevalue))
					    (totalitemval (slot-value odt 'totalitemval)))
				       (cl-who:htm (:tr (:td  :height "12px" (cl-who:str (slot-value odt-product 'item-description)))
							(:td  :height "12px" (cl-who:str (format nil  "~d" prd-qty)))
							(:td  :height "12px" (cl-who:str (format nil  "~A ~$" currsymbol taxablevalue)))
							(:td  :height "12px" (cl-who:str (format nil  "~A ~$ @ ~$%"  currsymbol sgstamt sgst)))
							(:td  :height "12px" (cl-who:str (format nil  "~A ~$ @ ~$%"  currsymbol cgstamt cgst)))
							(:td  :height "12px" (cl-who:str (format nil  "~A ~$ @ ~$%"  currsymbol igstamt igst)))
							(:td  :height "12px" (cl-who:str (format nil "~A ~$" currsymbol (* totalitemval  prd-qty)))))))) (if (not (typep data 'list)) (list data) data))))))))
