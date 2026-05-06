;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：email 邮件模板
;;;; 分层：UI（HTML 邮件模板与外发函数）
;;;; 文件：hhub/email/templates/registration.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义平台所有外发邮件的 cl-who 包裹宏（with-html-email-template /
;;;;       with-single-column-email），以及若干外发函数：客户注册激活邮件、
;;;;       密码重置链接、临时密码、新公司入驻通知、联系我们、订单确认。
;;;;
;;;; 主要导出：
;;;;   with-html-email-template       — 邮件外层 HTML 包裹宏（doctype + table 居中布局）
;;;;   with-single-column-email       — 单列卡片型邮件包裹宏（带 logo）
;;;;   hhub-email-logo                — 输出页眉 logo HTML
;;;;   customer-registration-html-content — 注册欢迎邮件正文（含激活按钮）
;;;;   send-test-email                — 调试用：把注册邮件发给固定占位收件人
;;;;   send-password-reset-link       — 发送重置密码链接
;;;;   send-temp-password             — 发送临时密码
;;;;   send-new-company-registration-email — 通知运营有新租户入驻申请
;;;;   send-contactus-email           — 发送 \"联系我们\" 表单内容到 support
;;;;   send-registration-email        — 发送注册欢迎邮件（不带激活）
;;;;   send-order-mail                — 异步发送订单确认邮件
;;;;   send-order-email-behavior      — Actor 行为函数（被 *NSTSENDORDEREMAILACTOR* 使用）
;;;;
;;;; 关联：
;;;;   上游使用方：customer/vendor 注册流程、order 模块、core actor *NSTSENDORDEREMAILACTOR*。
;;;;   下游依赖：hhubsendmail（SMTP 发送）、hhub-read-file（读模板）、
;;;;             *HHUB-EMAIL-TEMPLATES-FOLDER* 等模板路径常量、nst-get-cached-email-template-func。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



(defmacro with-html-email-template ((&key title) &body body)
  "邮件外层包裹宏：输出符合 Outlook/Gmail 兼容性的 HTML 邮件骨架（含 viewport、
   字体加载、内联 CSS、640px 居中表格、\"View Online\" 顶部链接）。
   用法：(with-html-email-template (:title \"...\") body...)，body 在主表格内输出。
   返回：完整 HTML 字符串。"
  `(cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
    (:html :xmlns "http://www.w3.org/1999/xhtml"
     (:head
    (:meta :content "text/html; charset=UTF-8" :http-equiv "Content-Type")
    (:meta :content "telephone=no" :name "format-detection" )
    (:meta :content "width=device-width, initial-scale=1.0" :name "viewport")
    
    (:title ,title)
    (:link :href "https://fonts.googleapis.com/css?family=catamaran" :rel "stylesheet")
    
    (:style :type "text/css" ,*HHUB-EMAIL-CSS-CONTENTS*))
    (:body :style "margin:0; padding:0; background-color: #eeeeee;" :bgcolor "#eeeeee" 

	   (:table :width "100%" :cellpadding "0" :cellspacing "0" :border "1" :bgcolor "#eeeeee"
      (:div :class "Gmail" :style "height: 1px !important; margin-top: -1px !important; max-width: 600px !important; min-width: 600px !important; width: 600px !important;")
      (:div :style "display: none; max-height: 0px; overflow: hidden;"
        "Paste your preview text here***")
      (:div :style "display: none; max-height: 0px; overflow: hidden;" 
        "&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;")

      (:tr
        (:td :width "100%" :valign "top" :align "center" :class "padding-container" :style "padding: 18px 0px 0px 0px!important; mso-padding-alt: 18px 0px 0px 0px;"
          (:table :width "600" :cellpadding "0" :cellspacing "0" :border "1" :align "center" :class "wrapper" :bgcolor "#eeeeee"
            (:tr
              (:td :align "center" :bgcolor "#eeeeee"
                (:a :href "http://paulgoddarddesign.com/emails/material-design" :target "_blank" :style "font-size: 12px; line-height: 14px; font-weight: 500; font-family: 'Roboto Mono', monospace; color: #212121; text-decoration: underline;padding: 0px; border: 1px solid #eeeeee; display: inline-block;" "View Online"))))))
,@body)))))


(defun hhub-email-logo ()
  "输出邮件页眉 Logo 区块的 HTML 字符串（300px 宽，居中）。
   logo 路径取自 *siteurl*/img/logo.png。返回：HTML 片段字符串。"
(cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
  (:tr
    (:td :width "100%" :valign "top" :align "center" :class "padding-container" :style "padding: 18px 0px 18px 0px!important; mso-padding-alt: 18px 0px 18px 0px;" 
	 (:table :width "600" :cellpadding "0" :cellspacing "0" :border "1" :align "center" :class "wrapper"
		 (:tr
		  (:td :align "center"
		       (:table :cellpadding "0" :cellspacing "0" :border "1" 
                  (:tr
                    (:td :width "100%" :valign "top" :align "center" 
                      (:table :width "600" :cellpadding "0" :cellspacing "0" :border "1" :align "center" :class "wrapper" :bgcolor "#eeeeee" 
                        (:tr 
                          (:td :align "center" 
                            (:table :width "600" :cellpadding "0" :cellspacing "0" :border "1" :class "container" :align "center" 
                              ; START HEADER IMAGE -- 
                              (:tr 
                                (:td :align "center" :class "hund" :width "600" 
     				     (:img :src (format nil "~A/img/logo.png" *siteurl*)  :width "300" :alt "Logo" :border "1" :style "max-width: 300px; display:block; " 
                                )))))))))))))))))

(defmacro with-single-column-email ((&key title) &body body)
  "单列卡片型邮件包裹宏：在 with-html-email-template 之内先放 logo，再放一张 600px 宽
   的白色卡片，body 字符串作为卡片正文输出（用 cl-who:str 把 body 当字符串拼接）。"
 `(with-html-email-template (:title ,title)
  ;;;;;;;;;;;;;Put the logo here ;;;;;;;;;;;;;
   (cl-who:str (hhub-email-logo))
   (:tr
   (:td :width "100%" :valign "top" :align "center" :class "padding-container" :style "padding-top: 0px!important; padding-bottom: 18px!important; mso-padding-alt: 0px 0px 18px 0px;" 
	(:table :width "600" :cellpadding "0" :cellspacing "0" :border "1" :align "center" :class "wrapper" 
		(:tr
		 (:td 
		  (:table :cellpadding "0" :cellspacing "0" :border "1" 
			  (:tr
			   (:td :style ":border-radius: 3px; :border-bottom: 2px solid #d4d4d4;" :class "card-1" :width "100%" :valign "top" :align "center" 
				(:table :style ":border-radius: 3px;" :width "600" :cellpadding "0" :cellspacing "0" :border "1" :align "center" :class "wrapper" :bgcolor "#ffffff" 
					(:tr
					 (:td :align "center" 
					       (cl-who:str ,@body))))))))))))))

(defun customer-registration-html-content (customer verify-url)
  :documentation "Original English. 中文：客户注册欢迎邮件正文（HTML 片段），
   返回一段会被 with-single-column-email 拼接到卡片里的表格内容。
   参数：customer — 客户对象（取 name slot）；verify-url — 激活链接 URL。
   返回：HTML 字符串（含 \"Activate Your Account\" 按钮）。"
  (let* ((cust-name (slot-value customer 'name)))
	;(id (slot-value customer 'row-id)))
    (cl-who:with-html-output-to-string
	(*standard-output* nil :prologue t :indent t)
      (:table :width "600" :cellpadding "0" :cellspacing "0" :border "1" :class "container" 
	      (:tr 
	       (:td :class "td-padding" :align "left" (cl-who:str (format nil "Welcome ~A!" cust-name)))
	       (:tr
		(:td :class "td-padding" :align "left" :style "font-family: 'Roboto Mono', monospace; color: #212121!important; font-size: 24px; line-height: 30px; padding-top: 18px; padding-left: 18px!important; padding-right: 18px!important; padding-bottom: 0px!important; mso-line-height-rule: exactly; mso-padding-alt: 18px 18px 0px 13px;" 
		     "Thank you for registering. We appreciate your memebership. "))
	       
	       (:tr
		(:td :class "td-padding" :align "left" :style "font-family: 'Roboto Mono', monospace; color: #212121!important; font-size: 16px; line-height: 24px; padding-top: 18px; padding-left: 18px!important; padding-right: 18px!important; padding-bottom: 0px!important; mso-line-height-rule: exactly; mso-padding-alt: 18px 18px 0px 18px;" 
		     "Please click on the verification link below. "))
	       (:tr
		(:td :align "left" :style "padding: 18px 18px 18px 18px; mso-alt-padding: 18px 18px 18px 18px!important;" 
		     (:table :width "100%" :border "1" :cellspacing "0" :cellpadding "0" 
			     (:tr
			      (:td 
			       (:table :border "1" :cellspacing "0" :cellpadding "0" 
				       (:tr
					(:td :align "left" :style ":border-radius: 3px;" :bgcolor "#17bef7" 
					     (:a :class "button raised" :href verify-url :target "_blank" :style "font-size: 14px; line-height: 14px; font-weight: 500; font-family: Helvetica, Arial, sans-serif; color: #ffffff; text-decoration: none; :border-radius: 3px; padding: 10px 25px; :border: 1px solid #17bef7; display: inline-block;" "Activate Your Account") )))))))))))))

(defmethod send-test-email (customer)
  "调试用：读取注册邮件模板文件并 format 写入客户姓名，发送到一个占位地址
   \"<<enter email to send>>\"。开发者临时修改占位邮箱试发。
   副作用：调用 hhubsendmail 发起 SMTP。"
  (let* ((reg-templ-str (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER* *HHUB-CUST-REG-TEMPLATE-FILE*)))
	(cust-reg-email (format nil reg-templ-str (slot-value customer 'name))))
  (hhubsendmail "<<enter email to send>>" "Welcome to Nine Stores" cust-reg-email)))



(defun send-password-reset-link (object url)
  :documentation "Original English: object is either CUSTOMER, VENDOR OR EMPLOYEE.
   中文：发送密码重置链接邮件。object 必须含 email slot；模板文件
   *HHUB-CUST-PASSWORD-RESET-FILE* 中的两个 ~A 占位都填同一个 url（应是一个用作链接、
   一个用作可读文本，推测）。副作用：发邮件。"
  (let* ((password-reset-str (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER* *HHUB-CUST-PASSWORD-RESET-FILE* )))
	 (email (slot-value object 'email))
	 (password-reset-email (format nil password-reset-str url url)))
  (hhubsendmail email  "Your Password Reset Link" password-reset-email)))

(defun send-temp-password  (object temp-pass url)
  "把临时密码 + 登录 URL 写进 *HHUB-CUST-TEMP-PASSWORD-FILE* 模板里，发到 object.email。
   场景：管理员重置或忘记密码流程下发临时密码。"
  (let* ((temp-password-str (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER* *HHUB-CUST-TEMP-PASSWORD-FILE* )))
	 (email (slot-value object 'email))
	 (temp-password-email (format nil temp-password-str temp-pass url )))
  (hhubsendmail email  "Your Password Has Been Reset" temp-password-email)))


(defun send-new-company-registration-email  (object custname phone email )
  "通知运营邮箱（*HHUBSUPPORTEMAIL*）：有新公司提交了入驻申请。
   把申请人姓名/手机/邮箱 + 公司各字段 format 进模板 *HHUB-NEW-COMPANY-REQUEST*。
   参数：object — dod-company（或同结构）实例。"
  (let* ((temp-str (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER* *HHUB-NEW-COMPANY-REQUEST*)))
	 (cmpname (slot-value object 'name))
	 (cmpaddress (slot-value object 'address))
	 (cmpcity (slot-value object 'city))
	 (cmpstate (slot-value object 'state))
	 (cmpzipcode (slot-value object 'zipcode))
	 (cmpcountry (slot-value object 'country))
	 (cmpwebsite (slot-value object 'website))
	 (cmptype (slot-value object 'cmp-type))
	 (temp-str-email (format nil temp-str custname phone email cmpname cmpaddress cmpcity cmpstate cmpzipcode cmpcountry cmpwebsite cmptype )))
  (hhubsendmail *HHUBSUPPORTEMAIL*  "Nine Stores - New company registration request" temp-str-email)))

(defun send-contactus-email (firstname lastname businessname email subject message)
  :documentation "Original English: Send the email with data filled from the contact us form.
   中文：把网站\"联系我们\"表单内容用模板 *HHUB-CONTACTUS-EMAIL-TEMPLATE* 渲染后，
   发送到平台支持邮箱 *HHUBSUPPORTEMAIL*。"
(let* ((temp-str (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER*  *HHUB-CONTACTUS-EMAIL-TEMPLATE* )))
      (temp-str-email (format nil temp-str firstname lastname businessname email message)))
  (hhubsendmail *HHUBSUPPORTEMAIL* subject temp-str-email)))


(defun send-registration-email (name email)
  "发送基础注册欢迎邮件（仅含姓名占位，不含激活链接）。
   收件人就是参数 email；标题固定为 \"Welcome to Nine Stores\"。"
  (let* ((reg-templ-str (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER* *HHUB-CUST-REG-TEMPLATE-FILE*)))
	 (cust-reg-email (format nil reg-templ-str name)))
    (hhubsendmail email "Welcome to Nine Stores" cust-reg-email)))

(defun send-order-mail (email subject  order-disp-str)
  :documentation "Original English: cl-async asynchronous email send.
   中文：异步发送订单确认邮件 —— 用 sb-thread:make-thread 在独立线程内完成。
   注：原 docstring 写的是 cl-async，实际实现用 sb-thread（推测：早期改过）。"
  (let* ((order-templ-str (hhub-read-file (format nil "~A/~A" *HHUB-EMAIL-TEMPLATES-FOLDER* *HHUB-GUEST-CUST-ORDER-TEMPLATE-FILE*)))
	 (cust-order-email (format nil order-templ-str order-disp-str)))
    (sb-thread:make-thread
     (lambda ()
       (hhubsendmail email subject cust-order-email)) :name "Order email thread")))


(defun send-order-email-behavior (state messagefunc)
  "Actor 行为函数（被 *NSTSENDORDEREMAILACTOR* 调度）。从 messagefunc 解出收件人/标题/
   订单 HTML 三元组，使用缓存的模板函数 nst-get-cached-email-template-func 渲染后发邮件。
   副作用：发送邮件 + state 计数自增（actor 内部状态计数已发送邮件次数）。"
  (multiple-value-bind (email subject  order-disp-str) (funcall messagefunc)
    (let* ((order-email-templ (funcall  (nst-get-cached-email-template-func :templatenum 1)))
	   (cust-order-email (format nil order-email-templ order-disp-str)))
      (hhubsendmail email subject cust-order-email)
      (incf state))))



