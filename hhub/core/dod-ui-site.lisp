;;; dod-ui-site.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 站点级公共 UI（公开页 + 营销页）
;;;; 分层：UI 控制器/视图层
;;;; 文件：hhub/core/dod-ui-site.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：渲染所有"对外公开"页面 —— 站点页脚、Cookie 政策弹窗、
;;;;       Terms / Privacy / About / Contact / Pricing 静态信息页。
;;;;       这些页面不需要登录或 ABAC，但仍走 with-standard-admin-page /
;;;;       with-mvc-ui-page 模板宏渲染。
;;;;
;;;; 主要导出：
;;;;   hhub-html-page-footer            — 全站页脚
;;;;   modal.hhub-cookie-policy         — Cookie 政策弹窗内容
;;;;   hhub-controller-tnc-page         — /hhub/tnc
;;;;   hhub-controller-privacy-page     — /hhub/privacy
;;;;   hhub-controller-aboutus-page     — /hhub/aboutuspage
;;;;   hhub-controller-contactus-page   — /hhub/contactuspage（含 reCAPTCHA v2）
;;;;   hhub-controller-contactus-action — /hhub/contactusaction（POST 提交）
;;;;   hhub-controller-pricing          — /hhub/pricing（套餐对比）
;;;;
;;;; 关联：
;;;;   上游使用方：路由派发 / 主页 / 注册流程跳转
;;;;   下游依赖：with-standard-admin-page / with-mvc-ui-page / send-contactus-email
;;;; ============================================================================
(in-package :nstores)

(defun hhub-html-page-footer ()
  "渲染全站统一页脚：导航链接 + 版权信息 + Cookie 政策模态触发。"
  (cl-who:with-html-output (*standard-output* nil)
    (:footer
        (:div :class "container"
	      (:div :class "row"
		    (:hr))
	      (:a :href *siteurl* "Home |")
	      (:a :href "/hhub/aboutuspage" "About |")
	      (:a :href "/hhub/contactuspage" "Contact Us |")
	      (:a :href "/hhub/tnc" "Terms and Conditions |")
	      (:a :href "/hhub/privacy" "Privacy Policy |")
	      (:a  :data-bs-toggle "modal" :data-bs-target (format nil "#hhubcookiepolicy-modal")  :href "#"  "Cookie Policy")
	      (modal-dialog-v2 (format nil "hhubcookiepolicy-modal") "Cookie Policy" (modal.hhub-cookie-policy)) 
	      (:div :class "row"
		    (:hr))
	      (:div :class "row"
		    (:div :class "col-lg-12" 
			  (:p :class "copyright text-muted small" "Copyright &copy; Nine Stores 2026. All Rights Reserved.")))))))
;;  (modal-dialog (format nil "hhubcookiepolicy-modal") "Accept Cookies" (modal.hhub-cookie-policy))))



(defun modal.hhub-cookie-policy ()
  "Cookie 政策模态框正文（嵌入页脚链接的弹窗）。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "panel panel-default"
	  (:div :class "panel-heading" "Cookie Policy"
	  (:div :class "row"
		(:div :class "col-lg-12"
		      (:p :class "small"  "To enrich and perfect your online experience, Nine Stores uses Cookies, similar technologies and services provided by others to display personalized content, appropriate advertising and store your preferences on your computer.")

(:p :class "small" "A cookie is a string of information that a website stores on a visitor's computer, and that the visitor's browser provides to the website each time the visitor returns. Nine Stores uses cookies to help Nine Stores identify and track visitors, their usage of https://www.ninestores.in, and their website access preferences. Nine Stores visitors who do not wish to have cookies placed on their computers should set their browsers to refuse cookies before using Nine Stores' websites, with the drawback that certain features of Nine Stores' websites may not function properly without the aid of cookies.")

(:p :class "small" "By continuing to navigate our website without changing your cookie settings, you hereby acknowledge and agree to Nine Stores' use of cookies.")))))))

(defun hhub-controller-tnc-page ()
  :documentation "Terms and Conditions Page
   中文：URL /hhub/tnc。读取静态文件 *HHUB-TERMSANDCONDITIONS-FILE* 内容并嵌入主体。"
  (let* ((tncstr (hhub-read-file (format nil "~A/~A" *HHUB-STATIC-FILES* *HHUB-TERMSANDCONDITIONS-FILE*))))
    (with-standard-admin-page "Nine Stores - Terms"
      (:div :class "row"
	    (:div :class "col-sm-12"
		  (cl-who:str tncstr)))
      (hhub-html-page-footer))))

(defun hhub-controller-privacy-page ()
  :documentation "Privacy Page
   中文：URL /hhub/privacy。读取静态文件 *HHUB-PRIVACY-FILE* 内容并嵌入主体。"
 (let* ((privacystr (hhub-read-file (format nil "~A/~A" *HHUB-STATIC-FILES* *HHUB-PRIVACY-FILE*))))
    (with-standard-admin-page "Nine Stores - Privacy"
      (:div :class "row"
	    (:div :class "col-sm-12"
		  (cl-who:str privacystr)))
      (hhub-html-page-footer))))

(defun hhub-controller-aboutus-page ()
  "URL /hhub/aboutuspage。营销介绍页（标题文案虽写 'Contact Us' 实为关于我们）。"
  (with-mvc-ui-page "Nine Stores - Contact Us" #'create-model-withnildata #'create-widgets-for-aboutuspage :role :customer))

(defun create-widgets-for-aboutuspage (modelfunc)
  "为 About Us 页构建三个 widget：标题/Logo/介绍文案 + 页脚。
   备注：modelfunc 仅作签名占位，实际不传入数据。"
  (multiple-value-bind () (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-4 "")
			 (with-html-div-col-8
			   (:h2 "Nine Stores - About Us")))))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-12
			   (:img :class "profile-img" :src "/img/logo.png" :alt "Logo")))))))
	  (widget3 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-12
			   (:h1 "Nine Stores: Empowering Small and Medium Businesses")
			   (:p (:strong "Nine Stores") "is a comprehensive, multi-paradigm platform designed to empower small and medium-sized businesses with robust ERP capabilities. Our solution caters to diverse business needs, helping sellers manage and grow their operations with ease and efficiency.")
			   (:h2 "Our Key Features")
			   (:ul
			    (:li (:strong "GST-compliant Invoice and Billing Software") ": Seamless and accurate financial management.")
			    (:li (:strong "Product Catalog Management") ": Showcase your offerings in an organized and visually appealing manner.")
			    (:li (:strong "Basic Inventory Management") ": Effortlessly track stock levels and ensure uninterrupted operations.")
			    (:li (:strong "Order and Subscription Management") ": Smooth handling of customer orders and recurring transactions.")
			    (:li (:strong "Digital Payments") ": Secure and versatile payment options.")
			    (:li (:strong "Shipping Methods") ": Streamlined logistics for timely deliveries."))
			   (:p "One of our standout offerings is the " (:strong "FREE e-commerce store") " packed with tons of features to help your business shine online. This feature allows your customers to explore and shop for your products in a professional and user-friendly digital storefront. With Nine Stores, you gain the tools and resources to take your business to new heights. Our platform is designed to reduce complexities, enhance operational efficiency, and open new opportunities for growth, giving you the competitive edge you need in today’s dynamic market.")
			   (:p "We are a passionate team of professionals dedicated to making your digital journey seamless and helping you deliver exceptional customer experiences!" (:strong "Nine Stores") " is a SaaS application offering comprehensive e-commerce services, including web hosting for your site. With our platform, you can redirect visitors from your site to" 
			       (:a :href "https://www.ninestores.in" "www.ninestores.in") "providing your customers with a smooth and enjoyable online shopping or service experience.")
			   (:div  :class "hhub-footer" (hhub-html-page-footer)))))))))
      (list widget1 widget2 widget3))))
  

(defun hhub-controller-contactus-page ()
  "URL /hhub/contactuspage。展示 contact us 表单（含 reCAPTCHA v2）。"
  (with-mvc-ui-page "Nine Stores - Contact Us" #'create-model-withnildata #'create-widgets-for-contactuspage :role :customer))

(defun create-widgets-for-contactuspage (modelfunc)
  "为 Contact Us 页构建表单 widget：firstname/lastname/companyname/email/subject/message
   + reCAPTCHA + 提交按钮。"
  (multiple-value-bind () (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row 
			 (with-html-div-col-4)
			 (with-html-div-col-4
			   (:h2 "Nine Stores - Contact Us")))))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (with-html-div-col-2 "")
			 (with-html-div-col-8
			   (:img :class "profile-img" :src "/img/logo.png" :alt "")
			   (with-html-form "hhubcontactusform" "contactusaction" 
			     (:div :class "panel panel-default"
				   (:div :class "panel-heading" "To: support@ninestores.in"
					 (:div :class "panel-body"
					       ;;Panel content
					       (:div :class "form-group"
						     (:input :class "form-control" :name "firstname" :maxlength "90"  :value "" :placeholder "First Name " :type "text" :required T ))
					       (:div :class "form-group"
						     (:input :class "form-control" :name "lastname" :maxlength "90"  :value "" :placeholder "Last Name " :type "text" :required T ))
					       (:div :class "form-group"
						     (:input :class "form-control" :name "companyname" :maxlength "90"  :value "" :placeholder "Company Name " :type "text" :required T ))
					       (:div :class "form-group"
						     (:input :class "form-control" :name "contactusemail" :maxlength "90"  :value "" :placeholder "Business Email Address " :type "email" :data-error "Invalid Email Address" :required T ))
					       (:div :class "form-group"
						     (:input :class "form-control" :name "contactusemailsubject" :maxlength "100"  :value "" :placeholder "Subject " :type "text" :required T  ))
					       (:div :class "form-group"
						     (:label :for "contactemailmessage" "Message")
						     (:textarea :class "form-control" :name "contactusemailmessage"  :placeholder "Message ( max 400 characters) "  :rows "5" :onkeyup "countChar(this, 400)" :required T ))
					       (:div :class "form-group" :id "charcount")
					       (:div :class "form-group"
						     (:div :class "g-recaptcha" :data-sitekey *HHUBRECAPTCHAV2KEY* ))
					       (:div :class "form-group"
						     (:label "By clicking submit, you consent to allow Nine Stores to store and process the personal information submitted above to provide you the content requested. We will not share your information with other companies."))
					       (:div :class "form-group"
						     (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))))))
	  (widget3 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (:div  :class "hhub-footer" (hhub-html-page-footer)))))))
      (list widget1 widget2 widget3))))

(defun hhub-controller-contactus-action ()
  "URL /hhub/contactusaction（POST）。处理 Contact Us 表单提交并展示致谢页。"
  (with-mvc-ui-page "Thank You For Contacting Us" #'create-model-for-contactusaction #'create-widgets-for-contactusaction :role :customer))

(defun create-model-for-contactusaction ()
  "Contact Us 提交流程的"模型"：
     1) 抽参；2) 调 Google reCAPTCHA siteverify 校验；
     3) 校验通过后 send-contactus-email 发送邮件；
     4) reCAPTCHA 失败时调 dod-response-captcha-error。
   返回值：返回一个空 lambda（widget 阶段不再用 model 数据）。"
  (let* ((firstname (hunchentoot:parameter "firstname"))
	 (lastname (hunchentoot:parameter "lastname"))
	 (captcha-resp (hunchentoot:parameter "g-recaptcha-response"))
	 (paramname (list "secret" "response" ) ) 
	 (paramvalue (list *HHUBRECAPTCHAV2SECRET*  captcha-resp))
	 (param-alist (pairlis paramname paramvalue ))
	 (json-response (json:decode-json-from-string  (map 'string 'code-char(drakma:http-request "https://www.google.com/recaptcha/api/siteverify"
												   :method :POST
												   :parameters param-alist  ))))
     	 (companyname (hunchentoot:parameter "companyname"))
	 (contactusemail (hunchentoot:parameter "contactusemail"))
	 (contactusemailsubject (hunchentoot:parameter "contactusemailsubject"))
	 (contactusemailmessage (hunchentoot:parameter "contactusemailmessage")))
    (unless (and (or (null firstname) (zerop (length firstname)))
		 (or (null lastname) (zerop (length lastname)))
		 (or (null companyname) (zerop (length companyname)))
		 (or (null contactusemail) (zerop (length contactusemail)))
		 (or (null contactusemailsubject) (zerop (length contactusemailsubject)))
		 (or (null contactusemailmessage) (zerop (length contactusemailmessage))))
      (cond 
	((null (cdr (car json-response))) (dod-response-captcha-error))
	(T (send-contactus-email firstname lastname companyname contactusemail contactusemailsubject contactusemailmessage))))
    (function (lambda ()
      (values nil)))))

(defun create-widgets-for-contactusaction (modelfunc)
  "Contact Us 提交后的致谢页 widgets：Logo + 文案 + 页脚。"
  (multiple-value-bind () (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-12
			   (:img :class "profile-img" :src "/img/logo.png" :alt "")))))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-html-div-row
			 (with-html-div-col-12
			   (:h3 "Thank You for contacting us. We will get back to you shortly.")))
		       (hhub-html-page-footer))))))
      (list widget1 widget2))))
		  

(defun hhub-controller-pricing ()
  "URL /hhub/pricing。展示 Trial / Basic / Professional 三档套餐对比表。
   features-active 控制每个特性是否在表中显示；'Y'/'N' 转勾叉，其他原样展示。"
  (let ((names (list  "Trial" "Basic" "Professional"))
	(prices (list "00" "19,999" "29,999"))
	(pricing-features 
	  (list  "No of Vendors" "No of Customers" "Revenue/Month" "Basic Inventory Control (Stock)" "Product Images & Zoom" "Guest Login/Phone Order"
		 "Products" "Shipping Integration" "Payment Gateway Integration" 
		 "FREE UPI Payments"  "Sub Domains" "Email/SMS (Transactional)" "Browser Notifications"
		 "Email Support" "Products Bulk Upload (CSV)" "Domain Registrations" "Product Subscriptions" "Wallets"  "COD Orders"
		 "Customer Loyalty Points" "API Access" "Blocked IPs" "Save Cart" "Customer Groups" "SEO Tools" "Facebook Store"))
	(features-active (list T T NIL T NIL T T T T T NIL NIL T T T T T T T NIL NIL NIL NIL nil nil nil))
	(pricing-table
	  (list	   
	   (list "1"  "50"   "Upto &#8377; 1 Lac"   "Y" "1"  "Y" "100"  "Y" "Y" "Y" "N" "Y" "Y" "Y" "N" "N" "N" "N" "N" "N")
	   (list "5"  "500"  "Upto &#8377; 5 Lacs"  "Y" "5"  "Y" "1000" "Y" "Y" "Y" "2" "Y" "Y" "Y" "Y" "N" "N" "N" "N" "N")
	   (list "10" "1000" "Upto &#8377; 10 Lacs" "Y" "10" "Y" "3000" "Y" "Y" "Y" "5" "Y" "Y" "Y" "Y" "Y" "Y" "Y" "Y" "Y" ))))
    (with-standard-admin-page "Nine Stores Pricing" 
      (:link :href "/css/pricing.css" :rel "stylesheet")
	   (:div :id "hhub_pt"  
		 (:section
		  (:div :class "container"
			(:div :class "row"
			      (:div :class "col-md-12"
				    (:div  :class "price-heading clearfix"
					   (:h1 "Nine Stores Pricing")))))
		  (:div  :class  "container"  
			 (:div  :class  "row"
				;; Print All the Features on LHS Header
				;;(format-pricing-features pricing-features features-active )
				;; Print Data
				(mapcar  (lambda (name price items)
					   (cl-who:with-html-output (*standard-output* nil)
					     (format-pricing-plans name price items pricing-features features-active))) names prices pricing-table)))))
      
      (:div  :class "hhub-footer" (hhub-html-page-footer)))))

(defun format-pricing-features (features features-active)
  "渲染套餐对比表的 LHS"特性列表"列（仅在 features-active 中为 T 的项展示）。
   备注：当前 hhub-controller-pricing 已注释掉对本函数的调用，保留供后续使用。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div  :class  "col-md-3"  
	   (:div  :class  "generic_content clearfix"  
		  (:div  :class  "generic_head_price clearfix"  
			 (:div  :class  "generic_head_content clearfix"  
				(:div  :class  "head_bg"  )
				(:div  :class  "head"  
				       (:span "Plan Details")))
					; price starts
			 	(:div  :class  "generic_price_tag clearfix"    
				       (:span :class  "price"  
					      (:span :class  "sign"  "")
					      (:span :class  "currency" "")
					      (:span :class  "cent"  "")
					      (:span :class  "month"  ""))))
		  
		  (:div  :class  "generic_feature_list"  
			 (:ul  
				 (mapcar (lambda (feature active)
					   (if active (cl-who:htm (:li (:span (cl-who:str feature))))))  features features-active)))))))
  

  

(defun format-pricing-plans (name price plans pricing-features features-active)
  "渲染单个套餐列。
   参数：name — 套餐名（Trial/Basic/Professional）；price — 年费；
         plans — 该套餐每个特性的取值（'Y'/'N'/数字）；
         pricing-features — 特性名列表；features-active — 对应 T/NIL 显隐。
   备注：Trial 套餐链接显示 'Sign Up - 90 Days Free!'。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div  :class  "col-md-4"  
     (:div  :class  "generic_content clearfix"  
       (:div  :class  "generic_head_price clearfix"  
	(:div  :class  "generic_head_content clearfix"  
	 (:div  :class  "head_bg"  )
	 (:div  :class  "head"  
	  (:span (cl-who:str name))))
					; price starts
	(:div  :class  "generic_price_tag clearfix"    
	       (:span :class  "price"  
		      (:span :class  "sign"  "&#8377;")
		      (:span :class  "currency" (cl-who:str price))
		      (:span :class  "cent"  "00")
		      (:span :class  "month"  "/Year"))))
       (:div  :class  "generic_feature_list"  
	      (:ul  
	       (mapcar (lambda (obj feature active)
			 (cond
			   ((and active (equal obj "Y")) (cl-who:htm (:li (:span (cl-who:str (format nil "~a  &#10003;" feature))))))
			   ((and active (equal obj "N")) (cl-who:htm (:li (:span :style "color: lightgray;" (cl-who:str (format nil "~a  &#10005;" feature))))))
			   (active (cl-who:htm (:li (:span (cl-who:str (format nil "~A - ~A" feature obj))))))))   plans pricing-features features-active)))
       (:div  :class  "generic_price_btn clearfix"  
	      (if (equal name "Trial") (cl-who:htm (:a :class ""  :href (format nil "hhubnewcompanyreqpage?cmp-type=~A" name)  "Sign Up - 90 Days Free!"))
		  ;else
		  (cl-who:htm (:a :class "" :href (format nil "hhubnewcompanyreqpage?cmp-type=~A" name) "Sign Up"))))))))

	
   
