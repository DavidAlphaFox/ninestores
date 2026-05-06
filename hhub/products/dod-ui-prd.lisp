;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：products —— 商品 / 类目 通用 UI Widgets
;;;; 分层：UI（CL-WHO 模板组件库）
;;;; 文件：hhub/products/dod-ui-prd.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：提供商品域复用的 HTML 渲染组件。被 customer / vendor / cad / order /
;;;;       shopcart 多个模块的控制器调用 —— 本文件本身基本没有 com-hhub-transaction-*
;;;;       入口，只是组件库。
;;;;       内容大致分四类：
;;;;         (1) 下拉/输入：ui-list-prod-catg-dropdown / ui-list-yes-no-dropdown
;;;;         (2) 商品卡片：product-card / product-card-with-details-for-customer /
;;;;             product-card-for-vendor / product-card-for-approval /
;;;;             product-card-shopcart / product-card-shopcart-readonly /
;;;;             product-card-for-email
;;;;         (3) 商品/商家管理模态框：modal.vendor-product-edit-html /
;;;;             modal.vendor-product-shipping-html / modal.vendor-upload-product-images /
;;;;             modal.vendor-product-reject-html / modal.vendor-product-accept-html /
;;;;             modal.vendor-product-pricing / modal.product-remove-from-shopcart
;;;;             vendor-product-actions-menu（操作菜单聚合）
;;;;         (4) 列表/网格：ui-list-prod-catg / ui-list-customer-products /
;;;;             ui-list-cust-products-horizontal / render-products-list /
;;;;             display-product-cards / prdcatg-card
;;;;         (5) 价格 widget：create-model-for-prdpricewithdiscount /
;;;;             create-widgets-for-prdpricewithdiscount / product-price-with-discount-widget
;;;;         (6) 图片渲染：render-single-product-image / render-multiple-product-images /
;;;;             render-multiple-product-thumbnails
;;;;
;;;; 关联：
;;;;   上游使用方：customer / vendor / cad / order / shopcart 各模块的 UI 控制器
;;;;   下游依赖：products/dod-bl-prd.lisp（取数）、order/* 计算函数 calculate-order-item-cost、
;;;;             core/* 视图工具
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun ui-list-prod-catg-dropdown (catglist selectedvalue)
  "渲染 <select name='prodcatg'> 下拉框，遍历 catglist 输出 <option>，
   selectedvalue 命中的选项加 :selected。"
  (cl-who:with-html-output (*standard-output* nil)
    (cl-who:htm (:select :class "form-control" :name "prodcatg" 
      (loop for catg in catglist
	    do (if (and selectedvalue (equal (slot-value catg 'row-id) (slot-value selectedvalue 'row-id)))
		    (cl-who:htm  (:option :selected "true"  :value  (slot-value catg 'row-id) (cl-who:str (slot-value catg 'catg-name))))
		    ;;else
		    (cl-who:htm  (:option :value  (slot-value catg 'row-id) (cl-who:str (slot-value catg 'catg-name))))))))))

(defun ui-list-yes-no-dropdown (value)
  "通用 Y/N 下拉：value='N' 时 NO 选中，否则 YES 选中。"
  (cl-who:with-html-output (*standard-output* nil)
    (:select :class "form-control" :name "yesno"
	     (if (equal value "N") (cl-who:htm (:option :value "N" "NO" :selected)
					       (:option :value "Y" "YES"))
		 (cl-who:htm (:option :value "Y" "YES" :selected)
			     (:option :value "N" "NO"))))))
	   
(defun ui-list-prod-catg (catglist)
  "横向滚动展示一组类目卡片（每个调用 prdcatg-card），下方加 hr 分割。"
  (cl-who:with-html-output (*standard-output* nil)
    (:span (:h5 "Product Categories"))
    (:div :class "prd-catg-container" :style "width: 100%; display:flex; overflow:auto;"
	  (with-html-div-row :style "padding: 30px 20px; display: flex; align-items:center; justify-content:center; flex-wrap: nowrap;"  
	    (mapcar (lambda (prdcatg)
		      (cl-who:htm
		       (:div :class "prd-catg-card" (prdcatg-card prdcatg ))))
		    catglist)))
    (:hr)))


(defun ui-list-customer-products (data lstshopcart)
  "C 端商品列表外层 div（id=prdlivesearchresult，供 livesearch 异步替换）。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :id "prdlivesearchresult"
	  (cl-who:str (render-products-list data lstshopcart)))))

(defun render-products-list (data lstshopcart)
  "渲染 .all-products 容器内的商品卡片网格。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "all-products"
	  (display-product-cards data lstshopcart))))



(defun ui-list-cust-products-horizontal (data lstshopcart)
  "横向滚动版商品列表（首页 banner 等场景使用）。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :id "idprd-catg-container" :class "prd-catg-container" :style "width: 100%; display:flex; overflow:auto;"
	  (with-html-div-row :style "padding: 30px 20px; display: flex; align-items:center; justify-content:center; flex-wrap: nowrap;"
	    (display-product-cards data lstshopcart)))))


(defun display-product-cards (data lstshopcart)
  "遍历 data，对每个商品调 product-card 渲染。
   若 session 中设置了 :login-active-vendor（仅展示某个商家的商品），过滤掉非该商家的商品。
   prdincart-p 由 lstshopcart 中是否含此商品决定（用于在卡片上显示已加购图标）。"
  (cl-who:with-html-output (*standard-output* nil)
    (mapcar (lambda (product)
	      (let* ((vendor-id (slot-value (product-vendor product) 'row-id))
		     (active-vendor (hunchentoot:session-value :login-active-vendor))
		     (active-vendor-id (when active-vendor (slot-value active-vendor 'row-id))))
		(when (or (null active-vendor) (equal vendor-id active-vendor-id))
		  (cl-who:htm
		   (:div :class "product-card" (product-card product  (prdinlist-p (slot-value product 'row-id)  lstshopcart))))))) data )))

(defun product-card-shopcart (product-instance odt-instance)
  "购物车页中的单行商品卡片：图片 / 名称价格 / 数量 / 折扣 / 小计 + 编辑/删除按钮。
   小计 = prd-qty × calculate-order-item-cost(odt-instance)，币种符号取自公司账户。"
  (let* ((prd-name (slot-value product-instance 'prd-name))
	 (qty-per-unit (slot-value product-instance 'qty-per-unit))
	 (prdqty (slot-value odt-instance 'prd-qty))
	 (units-in-stock (slot-value product-instance 'units-in-stock))
	 (images-str (slot-value product-instance 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (prd-id (slot-value product-instance 'row-id))
	 (current-price (slot-value product-instance 'current-price))
	 (current-discount (slot-value product-instance 'current-discount))
	 (uom (slot-value product-instance 'unit-of-measure))
	 (pricewith-discount (calculate-order-item-cost odt-instance))
	 (company (product-company product-instance))
	 (currsymbol (get-currency-html-symbol (get-account-currency company)))
	 (subtotal (* prdqty pricewith-discount)))
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-col-2
	(:span (:a :href (format nil "prddetailsforcust?id=~A" prd-id) (render-single-product-image prd-name imageslst images-str "70" "50"))))
      (with-html-div-col-2
	(:span (cl-who:str (format nil "~A: ~A/~A ~A" prd-name current-price qty-per-unit uom))))
      (with-html-div-col-2
	(:span (cl-who:str (format nil "~A" prdqty))))
      (with-html-div-col-1
	(:span (cl-who:str (format nil "~d%" current-discount))))
      ;;(:div (:p  (cl-who:str (format nil "  ~A. Fulfilled By: ~A" qty-per-unit (name prd-vendor)))))
      (with-html-div-col-2
	(:div
	 (:span (:p (:span :class "label label-success" (cl-who:str (format nil "~A ~$" currsymbol subtotal)))))
	 (:span 
	  (:a  :data-bs-toggle "modal" :data-bs-target (format nil "#producteditqty-modal~A" prd-id) :data-toggle "tooltip" :title "Modify"  :href "#" :onclick "addtocartclick(this.id);" :id (format nil "btnaddproduct_~A" prd-id) :name (format nil "btnaddproduct~A" prd-id) (:i :style "width: 15px; height: 15px; font-size: 20px;" :class "fa-regular fa-pen-to-square") "&nbsp;&nbsp;")
	  (modal-dialog-v2 (format nil "producteditqty-modal~A" prd-id) (cl-who:str (format nil "Edit Product Quantity - Available: ~A" units-in-stock)) (product-qty-edit-html product-instance odt-instance)))
	 (:span 
	  (:a  :data-bs-toggle "modal" :data-bs-target (format nil "#productremoveshopcart-modal~A" prd-id) :data-toggle "tooltip" :title "Remove From Shopcart"  :href "#" :id (format nil "btnremoveproduct_~A" prd-id) :name (format nil "btnremoveproduct~A" prd-id) (:i :style "width: 15px; height: 15px; font-size: 20px;" :class "fa-solid fa-trash-can") "&nbsp;&nbsp;")
	  (modal-dialog-v2 (format nil "productremoveshopcart-modal~A" prd-id) (cl-who:str (format nil "Remove Product From Shopcart"))  (modal.product-remove-from-shopcart product-instance))))))))

(defun modal.product-remove-from-shopcart (product)
  "Remove 商品确认模态框：缩略图 + 红色 Remove 按钮 → POST dodcustremshctitem (action=remitem)。"
  (let* ((id (slot-value product 'row-id))
	(prd-name (slot-value product 'prd-name))
	(images-str (slot-value product 'prd-image-path))
	(imageslst (safe-read-from-string images-str)))
    (cl-who:with-html-output (*standard-output* nil)
      (:span (:p (:a :href "#" (render-single-product-image prd-name imageslst images-str "50" "70"))))
      (with-html-form "removeproductfromshopcart" "dodcustremshctitem" 
	(with-html-input-text-hidden "id" id)
	(with-html-input-text-hidden "action" "remitem")
	(:input :type "submit" :class "btn btn-lg btn-danger"  :value "Remove")))))
  

(defun product-card-for-email (product-instance odt-instance)
  "邮件订单确认中的单行商品 <tr>：缩略图 + 名称 + 履约商家 + 数量 + 小计。"
  (let* ((prd-name (slot-value product-instance 'prd-name))
	 (qty-per-unit (slot-value product-instance 'qty-per-unit))
	 (prdqty (slot-value odt-instance 'prd-qty))
	 (images-str (slot-value product-instance 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (subtotal (calculate-order-item-cost odt-instance))
	 (prd-vendor (product-vendor product-instance)))
    (cl-who:with-html-output (*standard-output* nil)
      (:tr 
       (:td (render-single-product-image prd-name imageslst images-str "50" "50"))
					;Product name and other details
       (:td
	(:h5 :class "product-name"  (cl-who:str prd-name))
	(:p   (cl-who:str (format nil "  ~A. Fulfilled By: ~A" qty-per-unit (name prd-vendor)))))
       (:td
	(:h5 :class "product-name" (cl-who:str prdqty)))
       (:td
	(:h3 (:span :class "label label-default" (cl-who:str (format nil "~$" subtotal)))))))))






(defun product-card-shopcart-readonly (product-instance odt-instance)
  "只读购物车视图（订单确认页等）：图片 / 名称 / 三档税额行 / 数量 / 应税值。"
  (let* ((prd-name (slot-value product-instance 'prd-name))
	 (qty-per-unit (slot-value product-instance 'qty-per-unit))
	 (prdqty (slot-value odt-instance 'prd-qty))
	 (images-str (slot-value product-instance 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (sgstrate (slot-value odt-instance 'sgst))
	 (sgstamt (slot-value odt-instance 'sgstamt))
	 (cgstrate (slot-value odt-instance 'cgst))
	 (cgstamt (slot-value odt-instance 'cgstamt))
	 (igstrate (slot-value odt-instance 'igst))
	 (igstamt (slot-value odt-instance 'igstamt))
	 (taxablevalue (slot-value odt-instance 'taxablevalue))
	 (company (product-company product-instance))
	 (currsymbol (get-currency-html-symbol (get-account-currency company)))) 
    (cl-who:with-html-output (*standard-output* nil)
      (:a :href "#" (render-single-product-image prd-name imageslst images-str "83" "100"))
      (:p  (cl-who:str (format nil "~A-~A" prd-name qty-per-unit)))
      (:p (cl-who:str (format nil "~A ~d @ ~d%" currsymbol sgstamt sgstrate)))
      (:p (cl-who:str (format nil "~A ~d @ ~d%" currsymbol cgstamt cgstrate)))
      (:p (cl-who:str (format nil "~A ~d @ ~d%" currsymbol igstamt igstrate)))
      (:p  (cl-who:str (format nil "~A" prdqty )))
      (:div :class "txt-bg-success p3" (cl-who:str (format nil "~A ~$"  currsymbol taxablevalue))))))



(defun prdcatg-card (prdcatg-instance)
  "类目卡片：链接 dodproductsbycatg?id=<row-id>，文本为类目名。"
    (let ((catg-name (slot-value prdcatg-instance 'catg-name))
	  (row-id (slot-value prdcatg-instance 'row-id)))
	(cl-who:with-html-output (*standard-output* nil)
	  (:a :href (format nil "dodproductsbycatg?id=~A" row-id) (cl-who:str catg-name)))))


(defun modal.vendor-product-edit-html (product mode)
  "Vendor 添加/编辑商品的模态对话框 fragment。
   mode='NEW' 隐藏 prd-id；mode='EDIT' 写入 hidden prd-id。
   表单字段：prd-name / 类目下拉 / hsn-code / sku / upc / qty-per-unit / unit-of-measure /
            units-in-stock / 是否服务 / 是否可订阅 / description（带字数统计）。
   POST 到 dodvenaddproductaction。"
  (let* ((description (slot-value product 'description))
	 (subscribe-flag (slot-value product 'subscribe-flag))
	 (qty-per-unit (slot-value product 'qty-per-unit))
	 (unit-of-measure (slot-value product 'unit-of-measure))
	 (units-in-stock (slot-value product 'units-in-stock))
	 (prd-id (slot-value product 'row-id))
	 (catg-id (slot-value product 'catg-id))
	 (prd-name (slot-value product 'prd-name))
	 (prd-type (slot-value product 'prd-type))
	 (hsncode (slot-value product 'hsn-code))
	 (sku (slot-value product 'sku))
	 (upc (slot-value product 'upc))
	 (catglist (hhub-get-cached-product-categories))
	 (idtextarea (format nil "~Atextarea~A" (gensym "hhub") prd-id))
	 (idisserviceproduct (format nil "idserviceproduct~A~A" (gensym "hhub") prd-id))
	 (prdcategory (when catg-id (search-prdcatg-in-list catg-id catglist)))
	 (charcountid1 (format nil "idchcount~A" (hhub-random-password 3))))
 (cl-who:with-html-output (*standard-output* nil)
   (with-html-div-row 
     (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
	   (with-html-form (format nil "form-vendorprod~A" mode) "dodvenaddproductaction" 
	     (if (and product (equal mode "EDIT"))
		 (cl-who:htm (:input :class "form-control" :type "hidden" :value prd-id :name "prd-id"))
		 ;; else
		 (cl-who:htm (:input :class "form-control" :type "hidden" :value 0 :name "prd-id")))
	     (:div :class "form-group"
		   (:label :for idisserviceproduct "This is a Service&nbsp;")
		   (if (equal prd-type "SERV")
		       (cl-who:htm
			(:input :type "checkbox" :id idisserviceproduct :name "isserviceproduct" :checked "true" :value "Y"  :onclick (parenscript:ps (togglecheckboxvalueyn (parenscript:lisp idisserviceproduct)))))
		       ;;else
		       (cl-who:htm 
			(:input :type "checkbox" :id idisserviceproduct :name "isserviceproduct" :value "N"  :onclick (parenscript:ps (togglecheckboxvalueyn (parenscript:lisp idisserviceproduct))))))
		   (:input :class "form-control" :name "prdname" :value prd-name :placeholder "Enter Product Name ( max 30 characters) " :type "text" ))
	     (:div  :class "form-group"
		    (:label :for "description" "Description")
		    (text-editor-control idtextarea  description))
	     (:textarea :style "display: block;" :id idtextarea :class "form-control" :name "description"  :placeholder "Enter Product Description (max 5000 characters) "  :rows "5" :onkeyup (format nil "countChar(~A.id, this, 5000)" charcountid1) (cl-who:str (format nil "~A" description)))
	     (:div :class "form-group" :id charcountid1 )
	     (:div :class "form-group"
		   (with-html-input-text "hsn-code" "HSN/SAC Code" "HSN/SAC Code" hsncode T "Enter HSN/SAC Code" 4))
	     (:div :class "form-group"
		   (with-html-input-text "sku" "SKU" "SKU" sku nil "Enter SKU" 5))
	     (:div :class "form-group"
		   (with-html-input-text "upc" "UPC Barcode" "UPC Barcode" upc nil "Enter UPC Barcode" 6))
	     (:div :class "form-group"
		   (:label :for "qtyperunit" "Qty Per Unit")
		   (:input :class "form-control" :name "qtyperunit"  :value qty-per-unit :type  "number" :min 1 :max 10000  ))
	     (:div :class "form-group"
		   (:label :for "unitofmeasure" "Unit Of Measure")
		   (with-html-dropdown "unitofmeasure" (get-system-UOM-map) unit-of-measure))
	     (:div  :class "form-group" (:label :for "prodcatg" "Select Produt Category:" )
		    (ui-list-prod-catg-dropdown catglist prdcategory))
	     (:div :class "form-group"
		   (:input :class "form-control" :name "unitsinstock" :placeholder "Units In Stock"  :value units-in-stock  :type "number" :min "1" :max "10000" :step "1"  ))
	     
	     (:br) 
	     (:div :class "form-group" (:label :for "yesno" "Enable Subscription")
		   (if (equal subscribe-flag "Y") (ui-list-yes-no-dropdown "Y")
		       (ui-list-yes-no-dropdown "N")))
	     (:div :class "form-group"
		   (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))
;; We need to write all the details of the file upload logic here.
;; Need to support upload of 5 files
;; 商家批量上传商品图片（最多 5 张）的模态框 ——
;;   表单 multipart 提交到 vuploadprdimagesaction，前端 JS 校验大小、生成预览缩略图。
(defun modal.vendor-upload-product-images (product)
  "商品图片批量上传对话框：file input 支持 multiple，5 个 <img> 占位用于即时预览。"
  (let* ((prd-id (slot-value product 'row-id)))
    (cl-who:with-html-output (*standard-output* nil)
      (with-catch-file-upload-event "fileUploadForm"
	(with-html-div-row 
	  (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12" 
		(with-html-form "fileUploadForm" "vuploadprdimagesaction" 
		  (if product (cl-who:htm (:input :class "form-control" :type "hidden" :id "prd-id" :value prd-id :name "prd-id")))
		  (:div :class "form-group" :id "fileuploadprogress")
		  (:div :class "form-group" (:label :for "prdimage1" "Select Upto 5 Product Images:")
			(:input :id "idprdimgfileupldctrl" :class "form-control"  :name "uploadedimagefiles" :placeholder "Product Image" :onchange "validateFileSize(event);" :type "file" :multiple t ))
		  (:div :class "form-group"
			(:button :id "btnprdimageuploadreset"  :class "btn btn-lg btn-primary btn-block" :onclick "resetFileUpload(event);" :type "button" "Reset")
			(:button :id "btnprdimageupload"  :class "btn btn-lg btn-primary btn-block"  :type "submit" "Upload"))
		  ;; Image previews
		  (:div 
		   (:img :src "" :id "img_url_1" :alt "Preview 1" :style "width:100px; height:100px; display:none")
		   (:img :src "" :id "img_url_2" :alt "Preview 2" :style "width:100px; height:100px; display:none")
		   (:img :src "" :id "img_url_3" :alt "Preview 3" :style "width:100px; height:100px; display:none")
		   (:img :src "" :id "img_url_4" :alt "Preview 4" :style "width:100px; height:100px; display:none") 
		   (:img :src "" :id "img_url_5" :alt "Preview 5" :style "width:100px; height:100px; display:none")))))))))


(defun modal.vendor-product-shipping-html (product mode)
  "Vendor 配置商品物流信息（长 / 宽 / 高 cm + 重量 kg）的模态框；
   POST 到 hhubvendaddprodshipinfoaction。"
  (let* ((prd-id (slot-value product 'row-id))
	 (prd-name (slot-value product 'prd-name))
	 (images-str (slot-value product 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (shipping-length-cms (slot-value product 'shipping-length-cms))
	 (shipping-width-cms (slot-value product 'shipping-width-cms))
	 (shipping-height-cms (slot-value product 'shipping-height-cms))
	 (shipping-weight-kg (slot-value product 'shipping-weight-kg)))
    (cl-who:with-html-output (*standard-output* nil)
   (with-html-div-row 
     (with-html-div-col-12
       (with-html-form (format nil "form-vendorprodship~A" mode) "hhubvendaddprodshipinfoaction" 
	 (if (and product (equal mode "EDIT"))
	     (cl-who:htm (with-html-input-text-hidden "id" prd-id)))
	 (:h1 :class "text-center login-title"  "Shipping Information")
	 (:div :align "center"  :class "form-group" 
	       (render-single-product-image prd-name imageslst images-str "100" "83"))
	 (:div :class "form-group"
	       (with-html-input-text "shipping-length-cms" "Shipping Length" "Enter Product length in CM" shipping-length-cms T "Enter Shipping Length in CM" 1))
	 (:div :class "form-group"
	       (with-html-input-text "shipping-width-cms" "Shipping Width" "Enter Product width in CM" shipping-width-cms T "Enter Shipping Width in CM" 2))
	 (:div :class "form-group"
	       (with-html-input-text "shipping-height-cms" "Shipping Height" "Enter Product height in CM" shipping-height-cms T "Enter Shipping Height in CM" 3))
	 (:div :class "form-group"
	       (with-html-input-text "shipping-weight-kg" "Shipping Weight" "Enter Product weight in KG" shipping-weight-kg T "Enter Shipping Weight in KG" 1))
	 (:div :class "form-group"
	       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))




		    

(defun modal.vendor-product-reject-html (prd-id tenant-id)
  "（CAD 视角）拒绝商家提交的商品：模态框含商品缩略图 + 只读名称 + 拒绝原因 textarea；
   POST hhubcadprdrejectaction。"
  (let* ((company (select-company-by-id tenant-id))
	 (product (select-product-by-id prd-id company))
	 (images-str (slot-value product 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (description (slot-value product 'description))
	 (prd-name (slot-value product 'prd-name))
	 (prd-id (slot-value product 'row-id)))
 (cl-who:with-html-output (*standard-output* nil)
   (with-html-div-row 
     (with-html-div-col-12
       (:form :id (format nil "form-vendorprod")  :role "form" :method "POST" :action "hhubcadprdrejectaction" :enctype "multipart/form-data" 
					;(:div :class "account-wall"
	      (:input :class "form-control" :type "hidden" :value prd-id :name "id")
	      (:div :align "center"  :class "form-group"
		    (render-single-product-image prd-name imageslst images-str "100" "83"))
	      
	      (:h1 :class "text-center login-title"  "Reject Product")
	      (:div :class "form-group"
		    (:input :class "form-control" :name "prdname" :value prd-name :placeholder "Enter Product Name ( max 30 characters) " :type "text" :readonly "true" ))
	      (:div :class "form-group"
		    (:label :for "description" "Enter Rejection Reason")
		    (:textarea :class "form-control" :name "description"  :placeholder "Enter Reject Reason "  :rows "5" :onkeyup "countChar(this, 1000)" (cl-who:str (format nil "~A" description))))
	      (:div :class "form-group" :id "charcount")
	      (:div :class "form-group"
		    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Reject"))))))))


(defun modal.vendor-product-accept-html (prd-id tenant-id)
  "（CAD 视角）批准商家提交的商品：模态框，POST hhubcadprdapproveaction。"
  (let* ((company (select-company-by-id tenant-id))
	 (product (select-product-by-id prd-id company))
	 (images-str (slot-value product 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (description (slot-value product 'description))
	 (prd-name (slot-value product 'prd-name))
	 (prd-id (slot-value product 'row-id)))
 (cl-who:with-html-output (*standard-output* nil)
   (with-html-div-row
     (with-html-div-col-12
       (:form :id (format nil "form-vendorprod")  :role "form" :method "POST" :action "hhubcadprdapproveaction" :enctype "multipart/form-data" 
					;(:div :class "account-wall"
	      (:input :class "form-control" :type "hidden" :value prd-id :name "id")
	      (:div :align "center"  :class "form-group"
		    (render-single-product-image prd-name imageslst images-str "100" "83"))
	      (:h1 :class "text-center login-title"  "Accept Product")
	      (:div :class "form-group"
		    (:input :class "form-control" :name "prdname" :value prd-name :placeholder "Enter Product Name ( max 30 characters) " :type "text" :readonly "true" ))
	      (:div :class "form-group"
		    (:label :for "description")
		    (:textarea :class "form-control" :name "description"  :placeholder "Description "  :rows "5" :onkeyup "countChar(this, 1000)" (cl-who:str (format nil "~A" description))))
	      (:div :class "form-group" :id "charcount")
	      (:div :class "form-group"
		    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Approve"))))))))


(defun modal.vendor-product-pricing (product product-pricing)
  "Vendor 维护商品价格的模态框。无现存定价时显示 New 模式（提交 dodvenprdpricingaddaction），
   有现存定价时显示 Edit 模式（提交 dodvenprdpricingupdateaction，附 hidden pricing-id）。
   字段：price / discount / start-date / end-date。"
  (let* ((prd-id (slot-value product 'row-id))
	(images-str (slot-value product 'prd-image-path))
	(imageslst (safe-read-from-string images-str))
	(prd-name (slot-value product 'prd-name))
	(current-price (slot-value product 'current-price))
	(pricing-id (if product-pricing (slot-value product-pricing 'row-id)))
	(price (if product-pricing (slot-value product-pricing 'price)))
	(discount (if product-pricing (slot-value product-pricing 'discount)))
	(start-date (if product-pricing (get-date-string (slot-value product-pricing 'start-date))))
	(end-date (if product-pricing (get-date-string (slot-value product-pricing 'end-date))))
	(vendprodpricingform-id (format nil "vendprodpricingform~A" (gensym)))
	(idpricingstartdate (format nil "idpricingstartdate~A" (gensym)))
	(idpricingenddate (format nil "idpricingenddate~A" (gensym)))
	(startdateplaceholder (format nil "~A. Click to change" (get-date-string (clsql-sys::get-date))))
	(enddateplaceholder (format nil "~A. Click to change" (get-date-string (clsql::date+ (clsql::get-date) (clsql::make-duration :day 180))))))
			    
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row
        (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"                                                                                                                                                     
	      (with-html-form vendprodpricingform-id "hhubvendprodpricingsaveaction"
		(:input :class "form-control" :type "hidden" :value prd-id :name "prdid")
		(:input :class "form-control" :type "hidden" :value pricing-id :name "pricingid")
		(:div :align "center"  :class "form-group"
		      (render-single-product-image prd-name imageslst images-str "100" "83"))
		(:div :class "form-group"
		      (:label :for "prdprice" "Price" )
		      (:input :class "form-control" :name "prdprice"  :value (if product-pricing (format nil "~$" price) (format nil "~$" current-price))  :type "number" :step "0.05" :min "0.00" :max "10000.00" :step "0.10"  ))
		(:div :class "form-group"
		      (:label :for "prddiscount" "Discount % - Enter a number" )
		      (:input :class "form-control" :name "prddiscount"  :value (format nil "~$" discount)  :type "number" :step "0.05" :min "0.00" :max "10000.00" :step "0.10"  ))
		(:div :class "form-group"  (:label :for "startdate" "Start Date - Click To Change" )
		      (:input :class "form-control" :name "startdate" :id idpricingstartdate :placeholder  (cl-who:str startdateplaceholder)  :type "text" :value (if start-date start-date (get-date-string (clsql-sys::get-date)))))
		(:div :class "form-group"  (:label :for "enddate" "End Date - Click To Change" )
		      (:input :class "form-control" :name "enddate" :id idpricingenddate :placeholder  (cl-who:str enddateplaceholder)  :type "text" :value (if end-date end-date (get-date-string (clsql-sys:date+ (clsql-sys:get-date) (clsql-sys:make-duration :day 180))))))
				 
		(:div :class "form-group"
		      (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))
	(:script (cl-who:str (format nil "$(document).ready(
        function() {    
        $('#~A').datepicker({dateFormat: 'dd/mm/yy', minDate: 0} ).attr('readonly', 'true'); 
        $('#~A' ).datepicker({dateFormat: 'dd/mm/yy', minDate: 1} ).attr('readonly', 'true');    
         }
);" idpricingstartdate idpricingenddate)))))))
		

(defun vendor-product-actions-menu (product-instance)
  "Vendor 商品行的操作菜单（一行图标）：开关上架 / 复制 / 编辑 / SKU 生成 / 上传图片 /
   分享外链 / 物流 / 折扣 / 删除。多数项是带 modal 的 toggle，删除按钮带 JS 二次确认。
   shipping-weight-kg=0 时图标变红提示未填物流；product-pricing 为空时 Discount 图标亦变红。
   服务型商品（prd-type='SERV'）隐藏物流入口。"
  (let* ((prd-id (slot-value product-instance 'row-id))
	 (active-flag (slot-value product-instance 'active-flag))
	 (external-url (slot-value product-instance 'external-url))
	 (prd-type (slot-value product-instance 'prd-type))
	 (prdisservice-p (if (equal prd-type "SERV") T NIL))
	 (shipping-weight-kg (slot-value product-instance 'shipping-weight-kg))
	 (company (product-company product-instance))
	 (currency (get-account-currency company))
	 (product-pricing (select-product-pricing-by-product-id prd-id company)))
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row :style "border-radius: 5px;background-color:#e6f0ff; border-bottom: solid 1px; margin: 15px; padding: 10px; height: 35px; font-size: 1rem;background-image: linear-gradient(to top, #accbee 0%, #e7f0fd 100%);"
	(if (equal active-flag "Y")
	    (cl-who:htm
	     (with-html-div-col-1 :data-bs-toggle "tooltip" :title "Turn Off" 
	       (:a   :href (format nil "dodvenddeactivateprod?id=~A" prd-id) (:i :class "fa-solid fa-power-off"))))
					;else
	    (cl-who:htm
	     (with-html-div-col-1 :data-bs-toggle "tooltip" :title "Turn On" 
	       (:a :href (format nil "dodvendactivateprod?id=~A" prd-id) (:i :class "fa-solid fa-power-off")))))
	(with-html-div-col-1 :data-bs-toggle "tooltip" :title "Copy" 
	  (:a :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendcopyprod-modal~A" prd-id)  :href "#"  (:i :class "fa-regular fa-clone"))
	  (modal-dialog-v2 (format nil "dodvendcopyprod-modal~A" prd-id) "Copy Product" (modal.vendor-product-edit-html  product-instance "COPY")))
	
	(with-html-div-col-1  :data-bs-toggle "tooltip" :title "Edit" 
	  (:a :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendeditprod-modal~A" prd-id)  :href "#"  (:i :class "fa-solid fa-pencil"))
	  (modal-dialog-v2 (format nil "dodvendeditprod-modal~A" prd-id) "Edit Product" (modal.vendor-product-edit-html product-instance  "EDIT"))) 
	(with-html-div-col-1  :data-bs-toggle "tooltip" :title "SKU Generator" 
	(:a :data-bs-toggle "modal" :data-bs-target (format nil "#generatesku-modal")  :href "#"  (:i :class "fa-solid fa-wand-magic-sparkles"))
	  (modal-dialog-v2 (format nil "generatesku-modal") "SKU Generator" (modal.generate-sku-dialog)))
	(with-html-div-col-1  :data-bs-toggle "tooltip" :title "Upload Product Images" 
	  (:a :data-bs-toggle "modal" :data-bs-target (format nil "#dodvenduploadprodimages-modal~A" prd-id)  :href "#"  (:i :class "fa-solid fa-upload"))
	  (modal-dialog-v2 (format nil "dodvenduploadprodimages-modal~A" prd-id) "Upload Product Images" (modal.vendor-upload-product-images product-instance)))
	(unless external-url
	  (cl-who:htm 
	   (with-html-div-col-1 :data-bs-toggle "tooltip" :title "Information: Edit & Save to enable sharing" 
	     (:a :href "#" (:i :class  "fa-solid fa-share-nodes")))))
	(when external-url
	  (cl-who:htm
	   (with-html-div-col-1  :data-bs-toggle "tooltip" :title "Copy External URL" 
	     (:a :href "#" :OnClick (parenscript:ps (copy-to-clipboard (parenscript:lisp external-url))) (:i :class  "fa-solid fa-share-nodes")))))
	(with-html-div-col-1  :data-bs-toggle "tooltip" :title "Shipping" 
	  (unless prdisservice-p ;; Display the shipping truck for SALE product type only. 
	    (if (and shipping-weight-kg (> shipping-weight-kg 0)) 
		(cl-who:htm
		 (:a :data-bs-toggle "modal" :data-bs-target (format nil "#dodprodshipping-modal~A" prd-id)  :href "#"  (:i :class "fa-solid fa-truck")))
		;;else
		(cl-who:htm
		 (:a :style "color:red;" :data-bs-toggle "modal" :data-bs-target (format nil "#dodprodshipping-modal~A" prd-id)  :href "#"  (:i :class "fa-solid fa-truck"))))
	    (modal-dialog-v2 (format nil "dodprodshipping-modal~A" prd-id) "Shipping" (modal.vendor-product-shipping-html product-instance "EDIT"))))
	    
	(with-html-div-col-1  :data-bs-toggle "tooltip" :title "Discounts" 
		(if product-pricing 
		    (cl-who:htm
		     (:a :data-bs-toggle "modal" :data-bs-target (format nil "#dodprodpricing-modal~A" prd-id)  :href "#"  (:i :class (get-currency-fontawesome-symbol currency)))
		     (modal-dialog-v2 (format nil "dodprodpricing-modal~A" prd-id) "Pricing" (modal.vendor-product-pricing product-instance product-pricing)))
		    ;; else
		    (cl-who:htm
		     (:a :style "color:red;" :data-bs-toggle "modal" :data-bs-target (format nil "#dodprodpricing-modal~A" prd-id)  :href "#"  (:i :class (get-currency-fontawesome-symbol currency)))
		     (modal-dialog-v2 (format nil "dodprodpricing-modal~A" prd-id) "Pricing" (modal.vendor-product-pricing product-instance product-pricing)))))
	(with-html-div-col-1 "&nbsp;")
	(with-html-div-col-1 "&nbsp;")
	(with-html-div-col-2 :align "right" :data-bs-toggle "tooltip" :title "Delete" 
	  (:a :onclick "return DeleteConfirm();"  :href (format nil "dodvenddelprod?id=~A" prd-id) (:i :class "fa-solid fa-trash-can")))))))


(defun product-card-for-vendor (product-instance)
  "Vendor 自家商品列表的单卡片：上方控制行（开关 / 详情链接） + 库存徽章 + 图片 + 价格 widget +
   名称 + 订阅标志 + 描述。状态戳：库存=0 显示 NO STOCK；active-flag='N' 显示 INACTIVE；
   approved-flag='N' 显示当前 approval-status。"
  (let* ((prd-name (slot-value product-instance 'prd-name))
	 (units-in-stock (slot-value product-instance 'units-in-stock))
	 (description (slot-value product-instance 'description))
	 (images-str (slot-value product-instance 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (prd-id (slot-value product-instance 'row-id))
	 (active-flag (slot-value product-instance 'active-flag))
	 (approved-flag (slot-value product-instance 'approved-flag))
	 (approval-status (slot-value product-instance 'approval-status))
	 (subscribe-flag (slot-value product-instance 'subscribe-flag))
	 (company (product-company product-instance))
	 (product-pricing (select-product-pricing-by-product-id prd-id company)))
      (cl-who:with-html-output (*standard-output* nil)
	(with-html-div-row :style "border-radius: 5px;background-color:#e6f0ff; border-bottom: solid 1px; margin: -2px;background-image: linear-gradient(to top, #accbee 0%, #e7f0fd 100%); "
	    (if (equal active-flag "Y")
		(cl-who:htm
		 (with-html-div-col-1 :data-bs-toggle "tooltip" :title "Turn Off" 
		   (:a   :href (format nil "dodvenddeactivateprod?id=~A" prd-id) (:i :class "fa-solid fa-power-off"))))
		;;else
		(cl-who:htm
		 (with-html-div-col-1 :data-bs-toggle "tooltip" :title "Turn On" 
		   (:a :href (format nil "dodvendactivateprod?id=~A" prd-id) (:i :class "fa-solid fa-power-off")))))
	  (with-html-div-col-8 "&nbsp;")
	  (with-html-div-col-1 "&nbsp;")
	  (with-html-div-col-1 :align "right" :data-bs-toggle "tooltip" :title "Product Details"
	  (:a :href (format nil "dodprddetailsforvendor?id=~A" prd-id) (:i :class "fa-solid fa-chevron-right"))))
	(with-html-div-row
	  (if (<= units-in-stock 0) 
	      (cl-who:htm (:div :class "stampbox rotated" "NO STOCK" ))
					;else
	      (cl-who:htm (with-html-div-col (:h5 (:span :class "badge badge-pill badge-light" (cl-who:str (format nil "In stock ~A  units"  units-in-stock ))))))))
		      
	(with-html-div-row
	  (with-html-div-col-6 
	    (render-single-product-image prd-name imageslst images-str "100" "83"))
	  (with-html-div-col-6 (product-price-with-discount-widget product-instance product-pricing)))
	(with-html-div-row
	  (with-html-div-col-6
		(:p (:h5 :class "product-name" (cl-who:str (if (> (length prd-name) 30)  (subseq prd-name  0 30) prd-name)))))
	  (with-html-div-col-6
		(if (equal subscribe-flag "Y") (cl-who:htm (:p (:h5 (:span :class "label label-default" "Can be Subscribed")))))))
	(with-html-div-row 
	  (with-html-div-col-12 
		(:h6 (cl-who:str (if (> (length description) 90)  (subseq description  0 90) description)))))
	(if (equal active-flag "N") 
	    (cl-who:htm (:div :class "stampbox rotated" "INACTIVE" )))
	(if (equal approved-flag "N")
	    (cl-who:htm (:div :class "stampbox rotated" (cl-who:str (format nil "~A" approval-status))))))))


(defun product-card-for-approval (product-instance &rest arguments)
  "CAD/超管审批列表里的单商品卡片：所属公司名 + 图片 + 价格 + 名称 + 订阅徽章 +
   下方两个按钮（拒绝 / 批准模态框）。仅当 approved-flag='N' 时显示按钮。"
  (declare (ignore arguments))
    (let* ((prd-name (slot-value product-instance 'prd-name))
	   (current-price (slot-value product-instance 'current-price))
	   (images-str (slot-value product-instance 'prd-image-path))
	   (imageslst (safe-read-from-string images-str))
	   (prd-id (slot-value product-instance 'row-id))
	   ;;(active-flag (slot-value product-instance 'active-flag))
	   (approved-flag (slot-value product-instance 'approved-flag))
	   (tenant-id (slot-value product-instance 'tenant-id))
	   (company (select-company-by-id tenant-id))
	   (company-name (slot-value company 'name))
	   (approval-status (slot-value product-instance 'approval-status))
	   (subscribe-flag (slot-value product-instance 'subscribe-flag)))
	    
	(cl-who:with-html-output (*standard-output* nil)
	  (:div :style "background-color:#E2DBCD; border-bottom: solid 1px; margin-bottom: 3px;" :class "row"
		(:div :class "col-12" (:h5 (cl-who:str (format nil "~A" company-name)))))
	  (with-html-div-row
	    (with-html-div-col-6
	      (render-single-product-image prd-name imageslst images-str "100" "83"))
	    (with-html-div-col-4
	      (:h3 (:span :class "label label-default" (cl-who:str (format nil "Rs. ~$"  current-price))))))
	  
	  (with-html-div-row
	    (:div :class "col-xs-6"
		  (:h5 :class "product-name" (cl-who:str (if (> (length prd-name) 30)  (subseq prd-name  0 30) prd-name))))
	    (:div :class "col-xs-6"
		  (if (equal subscribe-flag "Y") (cl-who:htm (:div :class "col-xs-6"  (:h5 (:span :class "label label-default" "Can be Subscribed")))))))
	  (if (equal approved-flag "N")
	      (cl-who:htm (:div :class "stampbox rotated" (cl-who:str (format nil "~A" approval-status)))))
	  
	  (with-html-div-row
	    (:div :class "col-xs-6"
		  (:button :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendrejectprod-modal~A" prd-id)  :href "#"  (:i :class "fa-solid fa-ban") " Reject")
		  (modal-dialog-v2 (format nil "dodvendrejectprod-modal~A" prd-id) "Reject Product" (modal.vendor-product-reject-html  prd-id tenant-id)))
	    (:div :class "col-xs-6"
		  (:button :data-bs-toggle "modal" :data-bs-target (format nil "#dodvendacceptprod-modal~A" prd-id)  :href "#"  (:i :class "fa-regular fa-thumbs-up") " Approve")
		  (modal-dialog-v2 (format nil "dodvendacceptprod-modal~A" prd-id) "Approve Product" (modal.vendor-product-accept-html  prd-id tenant-id)))))))



(defun create-model-for-prdpricewithdiscount (product product-pricing)
  "价格 widget 的 model：判断 product-pricing 是否过期（today 不在 [start,end]）；
   计算折后价 = current-price - current-price*current-discount/100。
   返回闭包返回多值：(discountexpired-p 原价 折扣% 币符 qty-per-unit uom 折后价)。"
  (let* ((qty-per-unit (slot-value product 'qty-per-unit))
	 (unit-of-measure (slot-value product 'unit-of-measure))
	 (current-price (slot-value product 'current-price))
	 (current-discount (slot-value product 'current-discount))
	 (today-date (clsql:get-date))
	 (start-date (if product-pricing (slot-value product-pricing 'start-date)))
	 (end-date (if product-pricing (slot-value product-pricing 'end-date)))
	 (discountexpired-p (if product-pricing (not (and (clsql:date>= today-date start-date) (clsql:date<= today-date end-date)))))
	 (company (product-company product))
	 (currsymbol (get-currency-html-symbol (get-account-currency company)))
	 (pricewith-discount (if product (- current-price (/ (* current-price current-discount) 100)))))
    (function (lambda ()
      (values discountexpired-p current-price current-discount currsymbol  qty-per-unit unit-of-measure  pricewith-discount)))))
    
(defun create-widgets-for-prdpricewithdiscount (modelfunc)
  "价格 widget 的 view：
     - 折扣未过期：折后价（粗体新价）+ 删除线原价 + N% off；
     - 折扣已过期：'Price discounts are expired.' + 原价。"
  (multiple-value-bind ( discountexpired-p current-price current-discount currsymbol  qty-per-unit unit-of-measure  pricewith-discount) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output  (*standard-output* nil)
		       (unless discountexpired-p
			 (cl-who:htm
			  (:p :class "new-price" (:strong (cl-who:str (format nil "~A ~$ / ~A ~A" currsymbol  pricewith-discount qty-per-unit unit-of-measure))))
			  (:p :class "old-price" (:i (:del (cl-who:str (format nil "~A ~$ / ~A" currsymbol  current-price qty-per-unit)))))
			  (:p :class "new-price" (cl-who:str (format nil "~$% off" current-discount)))))
		       (when discountexpired-p
			 (cl-who:htm
			  (:p :class "new-price" (:strong "Price discounts are expired."))
			  (:p :class "new-price" (cl-who:str (format nil "~A ~$ / ~A ~A" currsymbol  current-price qty-per-unit unit-of-measure))))))))))
      (list widget1))))

(defun product-price-with-discount-widget (product product-pricing)
  "价格 widget 公共入口：把 model + view 包成 with-mvc-ui-component 一并渲染。"
  (with-mvc-ui-component #'create-widgets-for-prdpricewithdiscount #'create-model-for-prdpricewithdiscount product product-pricing))

(defun product-card (product-instance prdincart-p)
  "C 端商品瓦片：图片 / 价格 widget / 名称（截 20 字）/ 'Subscribe' 按钮（仅订阅型 + 客户类型 STANDARD + 公司订阅功能开启时显示）。
   购物车状态分支：
     - 已在购物车 → 显示绿色 'In Cart' 静态按钮；
     - 在售有库存 → 'Add' 按钮 + 数量编辑模态框；
     - 库存=0 → 'Out of Stock' 红字。"
  (let* ((prd-name (slot-value product-instance 'prd-name))
         (images-str (slot-value product-instance 'prd-image-path))
         (imageslst (safe-read-from-string images-str))
         (units-in-stock (slot-value product-instance 'units-in-stock))
         (prd-id (slot-value product-instance 'row-id))
         (subscribe-flag (slot-value product-instance 'subscribe-flag))
         (customer-type (get-login-customer-type))
         (company (product-company product-instance))
         (subscription-plan (slot-value company 'subscription-plan))
         (cmp-type (slot-value company 'cmp-type))
         (product-pricing (select-product-pricing-by-product-id prd-id company)))
    (cl-who:with-html-output (*standard-output* nil)
      ;; ⬇️ Outer tile wrapper
      ;; Product image section
      (:a :href (format nil "prddetailsforcust?id=~A" prd-id)
          (render-single-product-image prd-name imageslst images-str "100" "83"))
      ;; Product details section
      (:div :class "product-details"
            ;; price section
            (product-price-with-discount-widget product-instance product-pricing)
            ;; product title
            (:p :class "product-title"
                (:a :href (format nil "prddetailsforcust?id=~A" prd-id)
		    (cl-who:str (if (> (length prd-name) 20)  (subseq prd-name  0 20) prd-name))))
            ;; subscription button (if eligible)
            (when (and
                   (com-hhub-attribute-company-prdsubs-enabled subscription-plan cmp-type)
                   (equal subscribe-flag "Y")
                   (equal customer-type "STANDARD"))
              (cl-who:htm
               (:button :data-bs-toggle "modal"
                        :data-bs-target (format nil "#productsubscribe-modal~A" prd-id)
                        :class "btn btn-sm btn-primary"
                        :id (format nil "btnsubscribe~A" prd-id)
                        :name (format nil "btnsubscribe~A" prd-id)
			(:i :class "fa-solid fa-hand-point-up")
			" Subscribe")
               (modal-dialog-v2 (format nil "productsubscribe-modal~A" prd-id)
                                "Subscribe Product/Service"
                                (product-subscribe-html prd-id))))
            ;; add-to-cart / already-in-cart / out-of-stock logic
            (cond
              (prdincart-p
               (cl-who:htm
                (:a :class "btn btn-sm btn-success"
                    :role "button"
                    :onclick "return false;"
                    :href "javascript:void(0);"
                    (:i :class "fa-solid fa-check")
                    " In Cart")))
	      
              ((and units-in-stock (> units-in-stock 0))
               (cl-who:htm
                (:button :data-bs-toggle "modal"
                         :data-bs-target (format nil "#producteditqty-modal~A" prd-id)
                         :class "btn btn-sm btn-outline-primary add-to-cart-btn"
                         :onclick "addtocartclick(this.id);"
                         :id (format nil "btnaddproduct_~A" prd-id)
                         :name (format nil "btnaddproduct~A" prd-id)
                         "Add "
                         (:i :class "fa-solid fa-plus"))
                (modal-dialog-v2
                 (format nil "producteditqty-modal~A" prd-id)
                 (format nil "Edit Product Quantity - Available: ~A" units-in-stock)
                 (product-qty-add-html product-instance product-pricing))))
              (t
               (cl-who:htm
                (:div :class "text-danger small fw-bold mt-2"
                      "Out of Stock"))))))))
  
(defun product-card-with-details-for-customer (product-instance customer  prdincart-p)
  "商品详情大卡（C 端商品详情页）：多图轮播 + 名称 + 单位 + 商家信息（链接到店铺）+ 描述 +
   订阅按钮 + 加购/已加购 / 缺货 等状态分支。
   subscribe 与 product-card 同样要符合 com-hhub-attribute-company-prdsubs-enabled 等条件。"
  (let* ((prd-name (slot-value product-instance 'prd-name))
	 (qty-per-unit (slot-value product-instance 'qty-per-unit))
	 (units-in-stock (slot-value product-instance 'units-in-stock))
	 (description (slot-value product-instance 'description))
	 (external-url (slot-value product-instance 'external-url))
	 (images-str (slot-value product-instance 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (prd-id (slot-value product-instance 'row-id))
	 (subscribe-flag (slot-value product-instance 'subscribe-flag))
	 (cust-type (slot-value customer 'cust-type))
	 (prd-vendor (product-vendor product-instance))
	 (vendor-name (slot-value prd-vendor 'name))
	 (company (product-company product-instance))
	 (product-pricing (select-product-pricing-by-product-id prd-id company))
	 (subscription-plan (slot-value company 'subscription-plan))
	 (cmp-type (slot-value company 'cmp-type))
	 (vendor-id (slot-value prd-vendor 'row-id)))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :id "idsingle-product-card" :class "single-product-card"
	    (render-multiple-product-images prd-name imageslst images-str )
	    (:div :class "product-details"
		  (with-html-div-row
	      	    (with-html-div-col-12
		      (:p :class "product-title"
			  (:span (cl-who:str prd-name) "&nbsp;" (:strong (cl-who:str qty-per-unit))))))
		  (:p (:a :data-bs-toggle "modal" :data-bs-target (format nil "#vendordetails-modal~A" vendor-id)  :href "#"   :class "btn btn-sm btn-primary" :onclick "addtocartclick(this.id);" :name "btnvendormodal" (cl-who:str vendor-name)))  
		  (modal-dialog-v2 (format nil "vendordetails-modal~A" vendor-id) (cl-who:str (format nil "Vendor Details")) (modal.vendor-details vendor-id))
		  (:p (:a :href (format nil "hhubcustvendorstore?id=~A" vendor-id) (:i :class "fa-solid fa-store") (cl-who:str (format nil "&nbsp;~A Store" vendor-name))))
		  (:hr)
		  
		  (product-price-with-discount-widget product-instance product-pricing)
		  (:hr)
		  (:p (cl-who:str description))
		  
		  (with-html-div-row
		    (with-html-div-col-4
		      (if  prdincart-p 
			   (cl-who:htm (:a :class "btn btn-sm btn-success" :role "button"  :onclick "return false;" :href (format nil "javascript:void(0);")(:i :class "fa-solid fa-check")))
			   ;; else 
			   (if (and units-in-stock (> units-in-stock 0))
			       (cl-who:htm
				(:button  :data-bs-toggle "modal" :data-bs-target (format nil "#producteditqty-modal~A" prd-id)  :href "#"   :class "add-to-cart-btn" :onclick "addtocartclick(this.id);" :id (format nil "btnaddproduct_~A" prd-id) :name (format nil "btnaddproduct~A" prd-id)  "Add to cart&nbsp; " (:i :class "fa-solid fa-plus"))
				(modal-dialog-v2 (format nil "producteditqty-modal~A" prd-id) (cl-who:str (format nil "Edit Product Quantity - Available: ~A" units-in-stock)) (product-qty-add-html product-instance product-pricing)))
			   ;; else
			   (cl-who:htm (:div :class "col-6" 
					     (:h5 (:span :class "label label-danger" "Out Of Stock")))))))
		    (with-html-div-col-4
		      ;; display the subscribe button under certain conditions. 
		      (when (and (equal subscribe-flag "Y")
				 (com-hhub-attribute-company-prdsubs-enabled subscription-plan cmp-type) 
				 (equal cust-type "STANDARD"))
			(cl-who:htm
			 (:button :data-bs-toggle "modal" :data-bs-target (format nil "#productsubscribe-modal~A" prd-id)  :href "#"   :class "subscription-btn" :id (format nil "btnsubscribe~A" prd-id) :name (format nil "btnsubscribe~A" prd-id) "Subscribe&nbsp;" (:i :class "fa-solid fa-hand-point-up"))
			 (modal-dialog-v2 (format nil "productsubscribe-modal~A" prd-id) "Subscribe Product/Service" (product-subscribe-html prd-id)))))
		    (with-html-div-col-4
		      (when external-url
			(cl-who:htm
			 (:div  :data-toggle "tooltip" :title "Copy External URL"
				(:a :id "idshareexturl" :href "#" (:i :class  "fa-solid fa-arrow-up-from-bracket")))
			 (sharetextorurlonclick "#idshareexturl" (parenscript:lisp external-url)))))))))))

    
(defun render-multiple-product-images (prd-name imageslst images-str)
  :description "Sometimes we store the product image as a list of strings when we want multiple images. other times we store them as a string for backward compatibility reasons.
   中文：把商品图片字段渲染为多图轮播 / 网格。
         imageslst 为列表 → 多图（推测：调用方先 safe-read-from-string 解析）；
         否则按字符串视为单图，按旧版兼容路径处理。"
  ;; if we have images stored as a list 
  (cl-who:with-html-output (*standard-output* nil) 
    (if (and imageslst  (listp imageslst))
    	(cl-who:htm 
	 (:img :src (format nil "~A" (first imageslst))  :alt prd-name  :class "img-fluid rounded mb-3 product-detail-image" :id "mainImage"))
	;; if we are not storing the images as a list, then display a single image. 
	(when (stringp images-str)
	  (cl-who:htm 
	   (:img :src  (format nil "~A" images-str) :class "img-fluid rounded mb-3 product-detail-image" :alt prd-name " "))))))

(defun render-multiple-product-thumbnails (prd-name imageslst images-str)
  :description "Sometimes we store the product image as a list of strings when we want multiple images. other times we store them as a string for backward compatibility reasons.
   中文：渲染商品缩略图条（点击切换主图）。imageslst 列表 → 多缩略图；
         否则按 images-str 渲染单图。"
  ;; if we have images stored as a list 
  (cl-who:with-html-output (*standard-output* nil) 
    (:div :class "d-flex justify-content-between"
	  (if (and imageslst (listp imageslst))
	      (loop for img in imageslst do
		(cl-who:htm
		 (:img :src  (format nil "~A" img)  :alt prd-name :class "thumbnail rounded" :onclick "changeImage(event, this.src);")))
	      ;; if we are not storing the images as a list, then display a single image. 
	      (when (stringp images-str)
		(cl-who:htm 
		 (:img :src  (format nil "~A" images-str)  :alt prd-name :class "thumbnail rounded" :onclick "changeImage(event, this.src);")))))))

(defun render-single-product-image (prd-name imageslst images-str widthstr heightstr)
  :description "Sometimes we store the product image as a list of strings when we want multiple images. other times we store them as a string for backward compatibility reasons.
   中文：渲染单张固定尺寸图片。优先取 imageslst[0]（多图存储情况），
         否则按 images-str 渲染。widthstr/heightstr 控制 :width / :height 属性。"
  ;; if we have images stored as a list 
  (cl-who:with-html-output (*standard-output* nil) 
    (if (and imageslst  (listp imageslst))
	(cl-who:htm 
	 (:img :src (format nil "~A" (first imageslst))  :height heightstr :width widthstr  :class "img-fluid rounded mb-3 product-detail-image" :alt prd-name " "))
	;; if we are not storing the images as a list, then display a single image. 
	(when (stringp images-str)
	  (cl-who:htm 
	   (:img :src  (format nil "~A" images-str) :height heightstr  :width widthstr  :class "img-fluid rounded mb-3 product-detail-image" :alt prd-name " "))))))
