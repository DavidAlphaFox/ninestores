;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：invoice 发票 —— 发票头 UI / 控制器（新 nst-* DDD/Hexagonal，特大文件）
;;;; 分层：UI（控制器 + CL-WHO 模板 + Presenter 装配）
;;;; 文件：hhub/invoice/nst-ui-ihd.lisp（约 2085 行）
;;;; ----------------------------------------------------------------------------
;;;; 职责：本文件是发票头模块的 UI 总入口，覆盖：
;;;;   - 发票设置（offcanvas 菜单 + 打印/通用/邮件/客户/折扣税/分享 等子设置面板）
;;;;   - GST 汇总表渲染（render-tax-summary-html）
;;;;   - 发票列表 / 搜索 / 创建 / 编辑 / 删除 / 状态切换
;;;;   - 选择客户 → 选择商品 → 组装会话发票 → 确认 → 持久化 全链路
;;;;   - 发票打印模板渲染（基于 nst-get-cached-invoice-template-func 模板号）
;;;;   - LiveLink 公开预览 / WhatsApp 分享 / Email 发送
;;;;
;;;; 主要导出（按职责块）：
;;;;   渲染：render-tax-summary-html / render-invoice-settings-menu
;;;;   设置：com-hhub-transaction-invoice-settings-page + 多个 model/widgets/dialog
;;;;        invoiceprintsettingswidgethtml 等子部分渲染
;;;;   列表：com-hhub-transaction-show-InvoiceHeader-page / -search-InvoiceHeader-action
;;;;   创建链路：com-hhub-transaction-add-customer-to-invoice / -add-products-to-invoice /
;;;;            -confirm-invoice / -create-InvoiceHeader-action
;;;;   编辑：com-hhub-transaction-edit-invoice-* / -update-InvoiceHeader-action
;;;;   状态：com-hhub-transaction-mark-invoice-paid / -cancelled / -refunded / -draft
;;;;   分享：com-hhub-transaction-send-invoice-* / livelink 控制器
;;;;
;;;; 关联：
;;;;   上游使用方：卖家发票后台路由（多页面 + livesearch + AJAX）
;;;;   下游依赖：invoice/nst-bl-ihd.lisp、invoice/nst-bl-itm.lisp、nst-ui-itm.lisp、
;;;;             customer / product BL、core 模板缓存、core PEP 宏
;;;;
;;;; 备注：
;;;;   - 大量 CL-WHO 模板代码 + 表单渲染细节较多。本文件因体量较大（112K，2085 行）
;;;;     未对每个 widget 函数逐一加 docstring；函数层只为 PEP 控制器和领域装配函数加注释，
;;;;     纯展示用 widget 仅在节段加 ;; 说明。
;;;;   - 下文出现的 'invoice tax breakdown'、'session invoice' 等概念见 nst-dal-ihd.lisp 的
;;;;     SessionInvoice / gst-breakdown 类。
;;;; ============================================================================

(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 节段：GST 汇总渲染
;; ----------------------------------------------------------------------------

(defun render-tax-summary-html (breakdown)
  "Generates the HTML table for the GST breakdown with a Grand Total row.
   中文：把 gst-breakdown 渲染成 HSN 摘要 HTML 表（含 Grand Total 行）。
   intra（同州）输出 CGST + SGST 两列；interstate 输出 IGST 一列。"
  (let ((sorted-entries (get-sorted-summary breakdown))
        (interstate (interstate-p breakdown))
        ;; Initialize accumulators for the footer
        (total-taxable 0)
        (total-cgst 0)
        (total-sgst 0)
        (total-igst 0))
    (function (lambda ()
      (cl-who:with-html-output-to-string (s nil :prologue nil :indent t)
	(:div :class "gst-breakdown-container" :style "margin-top: 20px;"
              (:table :class "gst-table" :style "width:100%; border-collapse: collapse; font-size: 12px;" :border "1"
		      (:thead
		       (:tr :style "background-color: #f2f2f2;"
			    (:th "HSN/SAC")
			    (:th "Taxable Value")
			    (if interstate
				(cl-who:htm (:th "IGST Rate") (:th "IGST Amount"))
				(cl-who:htm (:th "CGST Rate") (:th "CGST Amount")
					    (:th "SGST Rate") (:th "SGST Amount")))
			    (:th "Total Tax")))
		      (:tbody
		       (dolist (entry sorted-entries)
			 (let ((row-tax (+ (cgst-amount entry) (sgst-amount entry) (igst-amount entry))))
			   ;; Increment totals
			   (incf total-taxable (taxable-value entry))
			   (incf total-cgst    (cgst-amount entry))
			   (incf total-sgst    (sgst-amount entry))
			   (incf total-igst    (igst-amount entry))
			   (cl-who:htm
			    (:tr
			     (:td (cl-who:str (hsn-code entry)))
			     (:td :align "right" (cl-who:fmt "~,2F" (taxable-value entry)))
			     (if interstate
				 (cl-who:htm 
				  (:td :align "center" (cl-who:fmt "~A%"  (igst-rate entry)))
				  (:td :align "right" (cl-who:fmt "~,2F"  (igst-amount entry))))
				 (cl-who:htm
				  (:td :align "center" (cl-who:fmt "~A%" (cgst-rate entry)))
				  (:td :align "right" (cl-who:fmt "~,2F" (cgst-amount entry)))
				  (:td :align "center" (cl-who:fmt "~A%" (sgst-rate entry)))
				  (:td :align "right" (cl-who:fmt "~,2F" (sgst-amount entry)))))
			     (:td :align "right" (cl-who:fmt "~,2F" row-tax)))))))
		      ;; Grand Total Footer
		      (:tfoot
		       (:tr :style "font-weight: bold; background-color: #eee;"
			    (:td "Total")
			    (:td :align "right" (cl-who:fmt "~,2F" total-taxable))
			    (if interstate
				(cl-who:htm 
				 (:td "") ; Empty Rate cell
				 (:td :align "right" (cl-who:fmt "~,2F" total-igst)))
				(cl-who:htm
				 (:td "") (:td :align "right" (cl-who:fmt "~,2F"  total-cgst))
				 (:td "") (:td :align "right" (cl-who:fmt "~,2F"  total-sgst))))
			    (:td :align "right" 
				 (cl-who:fmt "~,2F" (+ total-cgst total-sgst total-igst))))))))))))



;; ----------------------------------------------------------------------------
;; 节段：发票设置（Invoice Settings）—— 包含 offcanvas 菜单 + 打印/通用/邮件/
;; 客户/折扣税/分享/PDF/安全/高级/通知告警 等子页面的 model/widgets/dialog/render。
;; 控制器以 com-hhub-transaction-invoice-settings-page 为主入口。
;; ----------------------------------------------------------------------------

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun render-invoice-settings-menu ()
    "中文：渲染发票设置 offcanvas 侧栏菜单（导航到各子设置页）。
     eval-when 确保编译期可用（推测：被宏间接引用）。"
    (cl-who:with-html-output (*standard-output* nil :prologue t :indent t)
      (:div :class "offcanvas offcanvas-end" :tabindex"-1" :id "idInvoiceSettingsOffCanvas" :aria-labelledby "idInvoiceSettingsOffCanvasLabel" :style  "background: rgb(222,228,255);
background: linear-gradient(171deg, rgba(222,228,255,1) 0%, rgba(224,236,255,1) 100%); "
	    (:div :class "offcanvas-header"
		  (:img :src "/img/logo.png" :alt "" :width "32" :height "32" :class "rounded-circle me-2")
		  (:h5 :class "offcanvas-title" :id "idInvoiceSettingsOffCanvasLabel" "Invoice Settings")
		  (:button :type "button" :class "btn-close btn-close" :data-bs-dismiss "offcanvas" :aria-label "Close"))
	    (:div :class "offcanvas-body"
		  (:ul :class "nav nav-tabs flex-column mb-auto"
		       (:li :class "nav-item"
			    (:a :href "displayinvoices"
				(:i :class "fa-solid fa-house")  "&nbsp;&nbsp;Invoices"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/displayinvoices"  :class "nav-link link-body-emphasis"
				(:i :class "fa-solid fa-gear")  " General Invoice Settings"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/displayinvoices"  :class "nav-link link-body-emphasis"
				(:i :class "fa-solid fa-gear")  " Design & Branding"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/displayinvoices"  :class "nav-link link-body-emphasis"
				(:i :class "fa-solid fa-gear")  " Payment & Sharing"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/displayinvoices"  :class "nav-link link-body-emphasis"
				(:i :class "fa-solid fa-gear")  " Notifications & Alerts"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/displayinvoices"  :class "nav-link link-body-emphasis"
				(:i :class "fa-solid fa-gear")  " Advanced Settings"))
		       
		       (:li :class "nav-item"
			    (:a :href "/hhub/hhubvendorupitransactions"  :class "nav-link link-body-e mphasis"
				(:i :class "fa-solid fa-gear")  " Customer Management"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/hhubvendmycustomers" :class "nav-link link-body-emphasis"
				(:i :class "fa-solid fa-gear") " Reporting & Analytics"))
		       (:li :class "nav-item"
			    (:a :href "/hhub/displayinvoices"  :class "nav-link link-body-emphasis"
				(:i :class "fa-solid fa-gear") " Security"))))))))


(defun com-hhub-transaction-invoice-settings-page ()
  "中文：发票设置主页 PEP 入口。会话：with-vend-session-check。"
  (with-vend-session-check
    (with-mvc-ui-page "Invoice Settings Page" #'create-model-for-invoicesettingspage #'create-widgets-for-invoicesettingspage :role :vendor)))

(defun create-model-for-invoicesettingspage ()
  "中文：设置页 model：从会话读取 :login-vendor-invoice-settings，把 invoice-print-settings 子段
   交给 invoiceprintsettingswidgethtml 渲染，再用模板 14 包装最终 HTML。"
  (let* ((vinvsettings (hunchentoot:session-value :login-vendor-invoice-settings))
	 (printsettings (cdr (assoc 'invoice-print-settings vinvsettings :test 'equal)))
	 (vinvsettingshtml (funcall (nst-get-cached-invoice-template-func :templatenum 14)))
	 (idinvsettings (format nil "idvinvsettings~A" (gensym))))

    (setf vinvsettingshtml (format nil vinvsettingshtml (invoiceprintsettingswidgethtml printsettings )))
    (function (lambda ()
      (values idinvsettings vinvsettingshtml)))))

(defun create-widgets-for-invoicesettingspage (modelfunc)
  "中文：设置页 widgets：用 with-catch-submit-event 包住设置 HTML，捕获子表单提交事件。"
  (multiple-value-bind (idinvsettings vinvsettingshtml) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-catch-submit-event idinvsettings
			 (cl-who:str vinvsettingshtml)))))))
      (list widget1))))



(defun invoiceprintsettingswidgethtml (printsettings)
  "中文：渲染'发票打印设置'子表单：纸张/方向/字号/页边距/页头页脚/水印 + Save 按钮。
   表单每个字段对应 *invoice-settings* 中 invoice-print-settings 子树的一项。"
  (let ((papersize-ht (make-hash-table :test 'equal))
	(orientation-ht (make-hash-table :test 'equal))
	(papersize (cdr (assoc :DEFAULTPAPERSIZE printsettings :test 'equal)))
	(orientation (cdr (assoc :ORIENTATION printsettings :test 'equal)))
	(fontsize (cdr (assoc :FONTSIZE printsettings :test 'equal)))
	(margintop (cdr (assoc :TOP (cdr (assoc :MARGIN printsettings :test 'equal)))))
	(marginbottom (cdr (assoc :BOTTOM (cdr (assoc :MARGIN printsettings :test 'equal)))))
	(marginleft (cdr (assoc :LEFT (cdr (assoc :MARGIN printsettings :test 'equal)))))
	(marginright (cdr (assoc :RIGHT (cdr (assoc :MARGIN printsettings :test 'equal)))))
	(headerenable (cdr (assoc :ENABLE (cdr (assoc :HEADER printsettings :test 'equal)))))
	(headertext (cdr (assoc :TEXT (cdr (assoc :HEADER printsettings :test 'equal)))))
	(headerlogopath (cdr (assoc :LOGO-PATH (cdr (assoc :HEADER printsettings :test 'equal)))))
	(footerenable (cdr (assoc :ENABLE (cdr (assoc :FOOTER printsettings :test 'equal)))))
	(footertext (cdr (assoc :TEXT (cdr (assoc :FOOTER printsettings :test 'equal)))))
	(watermarkenable (cdr (assoc :ENABLE (cdr (assoc :WATERMARK printsettings :test 'equal)))))
	(watermarktext (cdr (assoc :TEXT (cdr (assoc :WATERMARK printsettings :test 'equal))))))
	
    
    (setf (gethash "A4" papersize-ht) "A4")
    (setf (gethash "Letter" papersize-ht) "Letter")
    (setf (gethash "Legal" papersize-ht) "Legal")
    (setf (gethash "Portrait" orientation-ht) "Portrait")
    (setf (gethash "Landscape" orientation-ht) "Landscape")
    
    (cl-who:with-html-output-to-string (*standard-output* nil)
      ;;<!-- Default Paper Size -->
      (:div :class "mb-3"
	    (:label :for "defaultpapersize" :class "form-label" "Default Paper Size")
	    (with-html-dropdown "defaultpapersize" papersize-ht papersize))

      ;; orientation
          (:div :class "mb-3"
		(:label :for "orientation" :class "form-label" "Orientation")
		(with-html-dropdown "orientation" orientation-ht orientation))
      ;; Fontsize
      (:div :class "mb-3"
	    (:label :for "fontsize" :class "form-label" "Font Size")
	    (:input :type "number" :class "form-control" :id "fontsize" :value fontsize))

      ;; Margins
      
      (:div :class "mb-3"
	    (:label :class "form-label" "Margins (in cm)")
	    (:div :class "row g-2"
		  (:div :class "col" 
			(:label :for "margintop" :class "form-label" "Top")
			(:input :type "text" :class "form-control" :id "margintop" :value margintop))
		  (:div :class "col" 
			(:label :for "marginbottom" :class "form-label" "Bottom")
			(:input :type "text" :class "form-control" :id "marginbottom" :value marginbottom))
		  (:div :class "col" 
			(:label :for "marginleft" :class "form-label" "Left")
			(:input :type "text" :class "form-control" :id "marginleft" :value marginleft))
		  (:div :class "col" 
			(:label :for "marginright" :class "form-label" "Right")
			(:input :type "text" :class "form-control" :id "marginright" :value marginright))))
      ;; Header
      (:div :class "mb-3"
	    (:label :class "form-label" "Header")
      	    (:div :class "form-check form-switch"
		  (if headerenable
		      (cl-who:htm
		       (:input :class "form-check-input" :type "checkbox" :id "headerenable" :checked  T))
		      ;;else
		      (cl-who:htm
		       (:input :class "form-check-input" :type "checkbox" :id "headerenable")))
		       
		  (:label :class "form-check-label" :for "headerenable" "Enable Header"))
	    (:div :class "mt-2"
		  (:label :for "headertext" :class "form-label" "Header Text")
		  (:input :type "text" :class "form-control" :id "headertext" :value headertext))
	    (:div :class "mt-2"
		  (:label :for "headerlogopath" :class "form-label" "Logo Path")
		  (:input :type "file" :class "form-control" :name "headerlogopath" :id "headerlogopath" :value headerlogopath)))
      ;; Footer
      (:div :class "mb-3"
	    (:label :class "form-label" "Footer")
      	    (:div :class "form-check form-switch"
		  (if footerenable
		      (cl-who:htm
		       (:input :class "form-check-input" :type "checkbox" :id "footerenable" :checked  T))
		      ;;else
		      (cl-who:htm
		       (:input :class "form-check-input" :type "checkbox" :id "footerenable")))
		  (:div :class "mt-2"
		  (:label :for "footertext" :class "form-label" "Footer Text")
		  (:input :type "text" :class "form-control" :id "footertext" :value footertext))))
      ;; Watermark
      (:div :class "mb-3"
	    (:label :class "form-label" "Watermark")
      	    (:div :class "form-check form-switch"
		  (if watermarkenable
		      (cl-who:htm
		       (:input :class "form-check-input" :type "checkbox" :id "watermarkenable" :checked  T))
		      ;;else
		      (cl-who:htm
		       (:input :class "form-check-input" :type "checkbox" :id "watermarkenable")))
		  (:div :class "mt-2"
		  (:label :for "watermarktext" :class "form-label" "Watermark Text")
		  (:input :type "text" :class "form-control" :id "watermarktext" :value watermarktext))))
      )))

(defun com-hhub-transaction-save-invoice-print-settings-action ()
  "中文：保存发票打印设置 PEP 入口。会话：with-vend-session-check。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-invoiceprintsettingsaction #'create-widgets-for-genericredirect)))

(defun create-model-for-invoiceprintsettingsaction ()
  "中文：保存打印设置 model：解析前端 POST 的 JSON → 处理 logo 文件上传到 S3 →
   覆盖 *invoice-settings* 中的 invoice-print-settings 子段 → 写到 vendor.invoice-settings 字段
   （write-to-string 序列化），同步会话变量 :login-vendor-invoice-settings。"
  (let* ((vendor (get-login-vendor))
	 (vendor-id (get-login-vendor-id))
	 (tenant-id (get-login-vendor-tenant-id))
	 (printsettings (hunchentoot:parameter "vinvprintsettings"))
	 (json-response (with-input-from-string (stream printsettings) (cl-json:decode-json stream)))
	 (vinvsettings *invoice-settings*)
	 (imageparams (hunchentoot:post-parameter "headerlogopath"))
	 (tempfilewithpath (first imageparams))
	 (file-name (if tempfilewithpath (process-file imageparams *HHUBRESOURCESDIR*)))
	 (redirecturl "/hhub/vinvoicesettingspage"))
    ;;(logiamhere (format nil "headerlogopath is ~A" tempfilewithpath))
    (if tempfilewithpath 
	(let ((s3filelocation (vendor-upload-file-s3bucket file-name "CFG" "logo123" vendor-id tenant-id )))
	  (setf (cdr (assoc :LOGO-PATH (cdr (assoc :HEADER json-response :test 'equal)))) s3filelocation)))
    (setf (cdr (assoc 'invoice-print-settings vinvsettings)) json-response)
    (setf (slot-value vendor 'invoice-settings) (write-to-string vinvsettings :readably t))
    (setf (hunchentoot:session-value :login-vendor-invoice-settings) vinvsettings)
    (update-vendor-details vendor)
    (function (lambda ()
      (values redirecturl)))))





;; ----------------------------------------------------------------------------
;; 节段：发票分享 / 下载 / 邮件
;;   下载 PDF、复制发票（占位）、发送邮件（异步线程）、不同状态的邮件模板
;;   （DRAFT / PAID / SHIPPED / CANCELLED / REFUNDED / PAYREMINDER / PAYOVERDUEREMINDER）
;; ----------------------------------------------------------------------------

(defun com-hhub-transaction-copy-invoice ()
  "中文：复制发票 PEP 入口（占位 —— 函数体为空，未实现）。"
  )

(defun com-hhub-transaction-download-invoice()
  "中文：发票 PDF 下载 PEP 入口。会话：with-vend-session-check。
   流程：取会话发票 → 下外部链接 HTML → generatepdf 转 PDF → redirect 到 PDF URL。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-downloadinvoice #'create-widgets-for-genericredirect)))

(defun create-model-for-downloadinvoice ()
  "中文：下载发票 model：从会话取发票 + external-url → downloadhtmlfile + generatepdf 拼 PDF URL。"
  (let* ((sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (invnum (slot-value sessioninvheader 'invnum))
	 (external-url (slot-value sessioninvheader 'external-url))
	 (htmlfile (downloadhtmlfile external-url))
	 (pdffileurl (format nil "~A/img/temp/~A" *siteurl* (generatepdf htmlfile invnum))))
    (function (lambda ()
      (values pdffileurl)))))



(defun com-hhub-transaction-send-invoice-email ()
  "中文：发送发票邮件 PEP 入口。会话：with-vend-session-check。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-sendinvoiceemail #'create-widgets-for-genericredirect)))

(defun create-model-for-sendinvoiceemail ()
  "中文：发送发票邮件 model：取 to/subject/body 后用 sb-thread 异步线程调 hhubsendmail。
   线程不阻塞主请求，重定向回编辑页。"
  (let* ((sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (to (hunchentoot:parameter "invoiceto"))
	 (subject (hunchentoot:parameter "draftinvoicesubject"))
	 (emailbody (hunchentoot:parameter "draftinvoiceemailbody"))
	 (redirecturl (format nil "/hhub/editinvoicepage?invnum=~A" sessioninvkey)))
    (sb-thread:make-thread
     (lambda ()
       (hhubsendmail to subject emailbody)) :name "Invoice Email Thread")
    (function (lambda ()
      (values redirecturl)))))

(defun com-hhub-transaction-edit-invoice-email ()
  "中文：编辑发票邮件 PEP 入口（即'选择模板 + 编辑正文'页）。会话：with-vend-session-check。"
  (with-vend-session-check
    (with-mvc-ui-page "Invoice Email" #'create-model-for-displayinvoiceemail #'create-widgets-for-displayinvoiceemail :role :vendor)))

(defun create-model-for-displayinvoiceemail ()
  "中文：根据 templatenum 选择不同邮件模板（1=Draft / 2=PayReminder / 3=Overdue / 4=Paid /
   5=Shipped / 6=Cancelled / 7=Refunded），逐项 regex-replace-all 把发票字段填进模板。
   返回多值闭包：(invoicetemplate to subject idtextarea charcountid1 sessioninvkey)。"
  (let* ((templatenum (parse-integer (hunchentoot:parameter "templatenum")))
	 (invoicetemplate (funcall (nst-get-cached-invoice-template-func :templatenum templatenum)))
	 (company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (address (slot-value vendor 'address))
	 (phone (slot-value vendor 'phone))
	 (email (slot-value vendor 'email))
	 (vendorname (slot-value vendor 'name))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (sessioninvitems (slot-value sessioninvoice 'InvoiceItems))   
	 (sessioninvcustomer (slot-value sessioninvoice 'Customer))
	 (invnum (slot-value sessioninvheader 'invnum))
	 (invdate (get-date-string (slot-value sessioninvheader 'invdate)))
	 (external-url (slot-value sessioninvheader 'external-url))
	 (companyname (slot-value company 'name))
	 (customername (slot-value sessioninvcustomer 'name))
	 (totalvaluewithgst (format nil "~d" (calculate-invoice-totalaftertax sessioninvitems)))
	 (totalvaluewithoutgst (format nil "~d" (calculate-invoice-totalbeforetax sessioninvitems)))
	 (to (slot-value sessioninvcustomer 'email))
	 (idtextarea (format nil "~Atextarea" (gensym "hhub")))
	 (charcountid1 (format nil "idchcount~A" (hhub-random-password 3)))
	 (subject "Test Invoice")
	 (logo-url (format nil "~A~A" *siteurl* *HHUBDEFAULTLOGOIMG*))
	 (contact-information (format nil "~A~C~C, ~A~C~C, ~A~C~C" address #\return #\linefeed phone #\return #\linefeed email #\return #\linefeed)))


    (case templatenum
      (1 (setf subject (format nil "Proforma/Draft Invoice for Your Review ~A" invnum)))
      (2 (setf subject (format nil "Payment Reminder for Your Invoice ~A" invnum)))
      (3 (setf subject (format nil "Overdue Payment Reminder for Your Invoice ~A" invnum)))
      (4 (setf subject (format nil "Thank You for Payment of Invoice ~A" invnum)))
      (5 (setf subject (format nil "Invoice ~A has been Shipped" invnum)))
      (6 (setf subject (format nil "Invoice ~A has been Cancelled!" invnum)))
      (7 (setf subject (format nil "Invoice ~A has been Refunded!" invnum))))
      
    
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Invoice Number%" invoicetemplate invnum))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Invoice Date%" invoicetemplate invdate))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Company Name%" invoicetemplate companyname))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Customer Name%" invoicetemplate customername))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Total Amount without GST%" invoicetemplate totalvaluewithoutgst))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Total Amount with GST%" invoicetemplate totalvaluewithgst))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Your Name%" invoicetemplate vendorname))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%INVOICE_LINK%" invoicetemplate external-url))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%LOGO_URL%" invoicetemplate logo-url))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Contact Information%" invoicetemplate contact-information))
    
    (function (lambda ()
      (values invoicetemplate to subject idtextarea charcountid1 sessioninvkey)))))

(defun create-widgets-for-displayinvoiceemail (modelfunc)
  "中文：发票邮件编辑页 widgets：左右 logo + 表单（收件人 / 主题 / textarea 富文本）+ 'Send' 按钮。"
  (multiple-value-bind (draftemailtext to subject idtextarea charcountid1 sessioninvkey) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (with-html-div-col-8 :align "center"
			   (:br)
			   (:h2 (cl-who:str subject))))
		       (with-html-div-row
			 (with-html-div-col-2 "")
			 (with-html-div-col-8
			   (:img :class "profile-img" :src "/img/logo.png" :alt "")
			   (with-html-form-having-submit-event "nstdraftinvoiceemailform" "invoicemailaction"
			     (with-html-input-text-hidden "sessioninvkey" sessioninvkey) 
			     (:div :class "panel panel-default"
				   (:div :class "panel-heading" "From: support@ninestores.in"
					 (:div :class "panel-body"
					       ;;Panel content
					       (:div :class "form-group"
						     (:input :class "form-control" :name "invoiceto" :maxlength "90"  :value to :placeholder "Business Email Address " :type "email" :data-error "Invalid Email Address" :required T ))
					       (:div :class "form-group"
						     (:input :class "form-control" :name "draftinvoicesubject" :maxlength "100"  :value subject :placeholder "Subject " :type "text" :required T  ))
					       (:div  :class "form-group"
						      (:label :for idtextarea "Enter Email Text")
						      (text-editor-control idtextarea draftemailtext))
					       (:div :class "form-floating"
						     (:textarea :class "form-control" :placeholder "Enter email text" :id idtextarea :name "draftinvoiceemailbody"  :style "height: 200px" :onkeyup (format nil "countChar(~A.id, this, 5000)" charcountid1) (cl-who:str (format nil "~A" draftemailtext))))
					       (:div :class "form-group" :id charcountid1 )
					       (:div :class "form-group"
						     (:label "By clicking submit, you consent to allow Nine Stores to store and process the personal information submitted above to provide you the content requested. We will not share your information with other companies."))
					       (:div :class "form-group"
						     (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Send"))))))))
		       (:div  :class "hhub-footer" (hhub-html-page-footer)))))))
    (list widget1))))

;; ----------------------------------------------------------------------------
;; 节段：LiveLink 公开发票预览（不登录可访问）
;;   - generate-invoice-ext-url 生成带 base64 编码 (tenant-id, invnum, vendor-id) 的公开 URL
;;   - displayinvoicepublic 通过 base64 解码后查发票头/行项 → 用 invoicetemplate 模板 13 渲染
;;   - invoicetemplatefill 把发票字段批量替换到 HTML 模板占位符
;; ----------------------------------------------------------------------------

(defun generate-invoice-ext-url (invnum vendor company)
  :description "Generates an external URL for a product, which can be shared with external entities.
   中文：生成可外部分享的发票 LiveLink。把 (tenant-id, invnum, vendor-id) 三元组编码成 CSV
   再 base64 拼到 /hhub/displayinvoicepublic?key=... 查询参数，方便客户匿名打开发票预览。
   description 中说 'product' 系拷贝错（推测）。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (vendor-id (slot-value vendor 'row-id))
	 (param-csv (format nil "tenant-id,invnum,vendor-id~C~A,~A,~A" #\linefeed tenant-id invnum vendor-id))
	 (param-base64 (cl-base64:string-to-base64-string param-csv)))
    (format nil "~A/hhub/displayinvoicepublic?key=~A" *siteurl* param-base64)))


(defun create-model-for-displayinvoicepublic ()
  "中文：公开发票预览 model：
     1) 解码 base64 key → (tenant-id, invnum, vendor-id)；
     2) 查发票头 + 行项 + 生成 GST 汇总；
     3) generate-invoice-items-rows-public 渲染行项 + render-tax-summary-html 渲染汇总；
     4) 用模板 13 + invoicetemplatefill 替换占位符；
     5) 顶部贴 vendor 的 UPI 二维码（generateqrcodeforvendor）。
   返回：闭包 (values invoicetemplate)。"
  (let* ((invoicetemplate (funcall (nst-get-cached-invoice-template-func :templatenum 13)))  
    	 (parambase64 (hunchentoot:parameter "key"))
	 (param-csv (cl-base64:base64-string-to-string (hunchentoot:url-decode parambase64)))
	 (paramslist (first (cl-csv:read-csv param-csv
					     :skip-first-p T
					     :map-fn #'(lambda (row)
							 row))))
	 (tenant-id (nth 0 paramslist))
	 (invnum (nth 1 paramslist))
	 (vendor-id (nth 2 paramslist))
	 (vendor (select-vendor-by-id vendor-id))
	 (company (select-company-by-id tenant-id))
	 (hrequestmodel (make-instance 'InvoiceHeaderRequestModel
				      :invnum invnum
				      :company company))
	 (headeradapter (make-instance 'InvoiceHeaderAdapter))
	 (invheader (processreadrequest headeradapter hrequestmodel))
         (invnum (slot-value invheader 'invnum))
	 (irequestmodel (make-instance 'InvoiceItemRequestModel
				       :company company
				       :invoiceheader invheader))
	 (itemsadapter (make-instance 'InvoiceItemAdapter))
	 (invoiceitems (processreadallrequest itemsadapter irequestmodel))
	 (tax-breakdown (generate-gst-tax-breakdown invheader invoiceitems))
	 (invoiceitemshtmlfunc (generate-invoice-items-rows-public invoiceitems invoicetemplate))
	 (invoicetaxbreakdownfunc (render-tax-summary-html tax-breakdown))
	 (totalvalue (calculate-invoice-totalaftertax invoiceitems))
	 (currency (get-account-currency company))
	 (qrcodepath (format nil "~A/img~A" *siteurl* (generateqrcodeforvendor vendor "ABC" invnum totalvalue))))
    (setf invoicetemplate (remove-invoice-item-markers-from-template invoicetemplate))
    (setf invoicetemplate (funcall (invoicetemplatefill invoicetemplate invheader invoiceitems invoiceitemshtmlfunc invoicetaxbreakdownfunc qrcodepath currency vendor)))
    (function (lambda ()
      (values  invoicetemplate)))))

(defun create-widgets-for-displayinvoicepublic (modelfunc)
  "中文：公开发票预览 widgets：在顶部加一条虚线分隔后直接输出整段已替换好的发票 HTML。"
  (multiple-value-bind ( invoicetemplate) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(:hr :style "border-top: 2px dashed gray;")
			(cl-who:str invoicetemplate))))))
      (list widget1))))

(defun invoicetemplatefill (invoicetemplate invheader invoiceitems invoiceitemshtmlfunc  invoicetaxbreakdownfunc qrcodepath currency vendor)
  "中文：把发票头/行项/卖家/QR/币种等数据批量 regex-replace-all 到 HTML 模板的 %字段% 占位符。
   字段总数较多（~30 个），覆盖卖家信息、客户地址、GST 信息、金额合计、TnC、银行账户等。
   返回：闭包，调用后产出最终 HTML 字符串。"
  (function (lambda ()
    (with-slots (name address gstnumber phone email) vendor
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Vendor Name%" invoicetemplate name))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Vendor Address%" invoicetemplate address))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Vendor Phone%" invoicetemplate phone))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Vendor Email%" invoicetemplate email))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Vendor GST%" invoicetemplate gstnumber)))

    (with-slots (row-id invnum invdate customer  custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear status vendor company) invheader
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Invoice Number%" invoicetemplate invnum))
      ;;(setf invoicetemplate (cl-ppcre:regex-replace-all "%Order Number%" invoicetemplate ordernum))
      ;;(setf invoicetemplate (cl-ppcre:regex-replace-all "%Order Date%" invoicetemplate orderdate))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Invoice Date%" invoicetemplate (get-date-string invdate)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Invoice Status%" invoicetemplate status))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Date of Supply%" invoicetemplate ""))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%State Code%" invoicetemplate (gethash statecode *NSTGSTSTATECODES-HT*)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Place of Supply%" invoicetemplate (gethash placeofsupply *NSTGSTSTATECODES-HT*)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Reverse Charge%" invoicetemplate revcharge))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Vehicle Number%" invoicetemplate vnum))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Transportation Mode%" invoicetemplate transmode))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Billed To%" invoicetemplate (slot-value customer 'name)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Shipped To%" invoicetemplate (slot-value customer 'name)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Billed to Address%" invoicetemplate billaddr))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Shipped to Address%" invoicetemplate shipaddr))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Billed to GSTIN%" invoicetemplate custgstin))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Shipped to GSTIN%" invoicetemplate custgstin))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Billed to State%" invoicetemplate (gethash statecode *NSTGSTSTATECODES-HT*)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Shipped to State%" invoicetemplate (gethash statecode *NSTGSTSTATECODES-HT*)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%UPI_IMAGE_URL%" invoicetemplate qrcodepath))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Total in Words%" invoicetemplate (convert-number-to-words-INR (calculate-invoice-totalaftertax invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Total Value%" invoicetemplate (format nil "~A" (calculate-invoice-totalaftertax invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Total Value before GST/TAX%" invoicetemplate (format nil "~A" (calculate-invoice-totalbeforetax invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Total After Tax%" invoicetemplate (format nil "~A ~A" (get-currency-html-symbol currency) (calculate-invoice-totalaftertax invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Tax Amount%" invoicetemplate (format nil "~A" (calculate-invoice-totalgst invheader invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Add CGST%" invoicetemplate (format nil "~A" (calculate-invoice-totalcgst invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Add SGST%" invoicetemplate (format nil "~A" (calculate-invoice-totalsgst invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Add IGST%" invoicetemplate (format nil "~A" (calculate-invoice-totaligst invoiceitems))))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Terms and Conditions%" invoicetemplate tnc))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Authorised Signatory%" invoicetemplate authsign))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Financial Year%" invoicetemplate finyear))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Company Name%" invoicetemplate (slot-value company 'name)))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Bank IFSC Code%" invoicetemplate bankifsccode))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%Bank Account Number%" invoicetemplate bankaccnum))
      (setf invoicetemplate (cl-ppcre:regex-replace-all "%GST on Reverse Charge%" invoicetemplate revcharge)))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%Invoice Items Rows%" invoicetemplate (funcall invoiceitemshtmlfunc)))
    (setf invoicetemplate (cl-ppcre:regex-replace-all "%GST Tax Breakdown%" invoicetemplate (funcall invoicetaxbreakdownfunc)))
      invoicetemplate)))
      

(defun com-hhub-transaction-display-invoice-public ()
  "中文：公开发票预览主入口（无登录要求 —— 注意没有 with-*-session-check 包裹）。
   备注：role 仍标 :vendor，但实际无会话校验 —— 推测：依赖 PEP 内部判断或 LiveLink 设计为公开。"
    (with-mvc-ui-page "Display Invoice Public" #'create-model-for-displayinvoicepublic #'create-widgets-for-displayinvoicepublic :role :vendor))

;;;;;;;;;;;;;;;;;;;;;;;; INVOICE EMAIL OPTIONS MENU ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：发票邮件下拉菜单 —— 根据当前发票状态动态启用/禁用对应模板入口。
(defun invoice-email-options-menu (status sessioninvkey)
  "中文：渲染发票邮件下拉菜单。根据 status 启用/禁用具体模板入口：
   DRAFT → Draft/Proforma；PENDINGPAYMENT → 还款提醒/逾期；PAID → 付款致谢；
   SHIPPED → 已发货；CANCELLED → 已取消；REFUNDED → 已退款。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "dropdown"  
	      (:button :id "idinvoiceemailmenu" :class "btn  dropdown-toggle" :type "button" :data-bs-toggle "dropdown" :aria-expanded "false"
		       (:i :class "fa-regular fa-envelope"))
	      (:ul :class "dropdown-menu" :aria-labelledby "idinvoiceemailmenu" 
		   (:li (:h6 :class "dropdown-header" "Send Invoice Email Options"))
		   (if (equal status "DRAFT")
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item" :href (format nil "/hhub/displayinvoiceemail?sessioninvkey=~A&templatenum=1" sessioninvkey) (:i :class "fa-regular fa-pen-to-square") "&nbsp;Draft/Proforma Invoice")))
		       ;;else
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item disabled" :href "#" :aria-disabled "true" (:i :class "fa-regular fa-pen-to-square") "&nbsp;Draft/Proforma Invoice"))))
		   (:li (:hr :class "dropdown-divider"))
		   (if (equal status "PENDINGPAYMENT")
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item" :href (format nil "/hhub/displayinvoiceemail?sessioninvkey=~A&templatenum=2" sessioninvkey) (:i :class "fa-solid fa-indian-rupee-sign") "&nbsp;Payment Reminder"))
			(:li 
		    (:a :class "dropdown-item" :href (format nil "/hhub/displayinvoiceemail?sessioninvkey=~A&templatenum=3" sessioninvkey) (:i :class "fa-solid fa-indian-rupee-sign") "&nbsp;Overdue Payment Reminder")))
		       ;;else
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item disabled" :href "#" :aria-disabled "true" (:i :class "fa-solid fa-indian-rupee-sign") "&nbsp;Payment Reminder")
			 (:a :class "dropdown-item disabled" :href "#" :aria-disabled "true" (:i :class "fa-solid fa-indian-rupee-sign") "&nbsp;Overdue Payment Reminder"))))
		   (if (equal status "PAID")
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item" :href (format nil "/hhub/displayinvoiceemail?sessioninvkey=~A&templatenum=4" sessioninvkey) (:i :class "fa-solid fa-indian-rupee-sign") "&nbsp;Paid Invoice")))
		       ;;else
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item disabled" :href "#" :aria-disabled "true" (:i :class "fa-solid fa-indian-rupee-sign") "&nbsp;Paid Invoice"))))
		   (:li (:hr :class "dropdown-divider"))
		   (if (equal status "SHIPPED")
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item" :href (format nil "/hhub/displayinvoiceemail?sessioninvkey=~A&templatenum=5" sessioninvkey) (:i :class "fa-solid fa-truck-fast") "&nbsp;Shipped Invoice")))
		       ;;else
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item disabled" :href "#" :aria-disabled "true" (:i :class "fa-solid fa-truck-fast") "&nbsp;Shipped Invoice"))))
		   
		   (if (equal status "CANCELLED")
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item" :href (format nil "/hhub/displayinvoiceemail?sessioninvkey=~A&templatenum=6" sessioninvkey) (:i :class "fa-solid fa-xmark") "&nbsp;Cancelled Invoice")))
		       ;;else
		       (cl-who:htm
			(:li
			 (:a :class "dropdown-item disabled" :href "#" :aria-disabled "true" (:i :class "fa-solid fa-xmark") "&nbsp;Cancelled Invoice"))))
		   (if (equal status "REFUNDED")
		       (cl-who:htm
			(:li 
			 (:a :class "dropdown-item" :href (format nil "/hhub/displayinvoiceemail?sessioninvkey=~A&templatenum=7" sessioninvkey) (:i :class "fa-solid fa-arrow-rotate-left") "&nbsp;Returned/Refunded Invoice")))
		       ;;else
		       (cl-who:htm
			(:li
			 (:a :class "dropdown-item disabled" :href "#" :aria-disabled "true" (:i :class "fa-solid fa-arrow-rotate-left") "&nbsp;Returned/Refunded Invoice"))))
		   ))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;; INVOICE ACTION MENU ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：单张发票的快捷动作工具栏（打印/邮件/复制/下载/LiveLink 复制/WhatsApp/删除）
(defun invoice-header-actions-menu (external-url status sessioninvkey customer)
  "中文：渲染发票顶栏 12 列工具图标。external-url 存在时显示 'Share LIVE Invoice Link'，
   否则该位置占位。WhatsApp 通过 createwhatsapplinkwithmessage 跳转。"
  (let ((phone (slot-value customer 'phone)))
    (cl-who:with-html-output (*standard-output* nil)
    (with-html-div-row :style "border-radius: 5px;background-color:#e6f0ff; border-bottom: solid 1px; margin: 15px; padding: 5px; height: 30px; font-size: 1rem;"
      (with-html-div-col-1 :data-bs-toggle "popover" :title "Print Invoice"
	(:a :href (format nil "vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey) :onclick (format nil "window.open(this.href).print(); return false;") (:i :class "fa-solid fa-print")))
      (with-html-div-col-1
	(invoice-email-options-menu status sessioninvkey))
      (with-html-div-col-1 :data-bs-toggle "popover" :title "Duplicate Invoice"
	(:a :href "#"  (:i :class "fa-regular fa-clone")))
      (with-html-div-col-1 :data-bs-toggle "popover" :title "Download Invoice PDF"
	(with-html-form-having-submit-event "invoicedownloadform" "downloadinvoice"
	  (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
	  (:button :class "btn" :type "submit" :id "iddownloadinvoicebtn" (:i :class "fa-regular fa-file-pdf"))))
      (if external-url
	  (cl-who:htm
	   (with-html-div-col-1  :data-bs-toggle "popover" :title "Share LIVE Invoice Link" 
	     (:a :href "#" :OnClick (parenscript:ps (copy-to-clipboard (parenscript:lisp external-url))) (:i :class  "fa-solid fa-link"))))
	  ;;else
	  (cl-who:htm
	   (with-html-div-col-1 "&nbsp;")))
      
      (with-html-div-col-1 :data-bs-toggle "popover" :title "Customer WhatsApp" 
	(:a :target "_blank" :style "font-weight: bold; font-size: 1.2rem !important;"  :href (format nil "createwhatsapplinkwithmessage?phone=~A&message=Hi" phone)  (:i :class "fa-brands fa-whatsapp")))
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-2 :align "right" :data-bs-toggle "popover" :title "DELETE INVOICE!" 
	(:a :onclick "return DeleteConfirm();"  :href "#" (:i :class "fa-solid fa-trash-can")))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;ALL INVOICES ACTION MENU ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：发票列表页顶部工具栏（打印 / GSTR1 JSON 导出 / 设置入口）
(defun invoices-actions-menu (sessioninvkey)
  "中文：渲染发票列表页顶栏。包含打印 / GSTR1 JSON 导出（占位）/ 设置图标。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-html-div-row :style "border-radius: 5px;background-color:#e6f0ff; border-bottom: solid 1px; margin: 15px; padding: 5px; height: 30px; font-size: 1rem;"
      (with-html-div-col-1 :data-bs-toggle "popover" :title "Print Invoice"
	(:a :href (format nil "vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey) :onclick (format nil "window.open(this.href).print(); return false;") (:i :class "fa-solid fa-print")))
      (with-html-div-col-1 :data-bs-toggle "popover" :title "GSTR1 JSON"
	(:a :href (format nil "vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey) :onclick (format nil "window.open(this.href).print(); return false;") (:img :src  "/img/json-file-icon.png"  :height "22" :width "22" :alt "checkout")))
      
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-1 "&nbsp;")
      (with-html-div-col-2 :align "right" :data-bs-toggle "popover" :title "Settings"
	(:a :href (format nil "vinvoicesettingspage?sessioninvkey=~A" sessioninvkey) (:i :class "fa-solid fa-gear"))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;




;;;;;;;;;;;;;;;;;;;;;; INVOICE PAID ACTION ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：标记发票为'已付款'（PAID）—— 触发 InvoiceHeaderStatusRequestModel + 状态切换。
(defun com-hhub-transaction-invoice-paid-action ()
  "中文：标记发票已付款 PEP 入口。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed. 
    (let ((uri (with-mvc-redirect-ui #'create-model-for-invoicepaidaction #'create-widgets-for-genericredirect)))
      (format nil "~A" uri))))

(defun create-model-for-invoicepaidaction ()
  "中文：发票标记已付款 model：构造 InvoiceHeaderStatusRequestModel（status='PAID' + 总金额 + 大写）→
   ProcessUpdateRequest 写库 → 同步会话内 sessioninvoice + 库存扣减 →
   重定向 /hhub/displayinvoices。错误时写日志并抛 hhub-business-function-error。"
  (let* ((company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (status (hunchentoot:parameter "status"))
	 (productlist (hhub-get-cached-vendor-products))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (invoiceitems (slot-value sessioninvoice 'InvoiceItems))
	 (totalvalue (calculate-invoice-totalaftertax invoiceitems))
	 (totalinwords (convert-number-to-words-INR totalvalue))
	 (invnum (slot-value sessioninvheader 'invnum))
	 (requestmodel (make-instance 'InvoiceHeaderStatusRequestModel
					 :invnum invnum
					 :status status
					 :totalvalue totalvalue
					 :totalinwords totalinwords
					 :company company))
	 (adapterobj (make-instance 'InvoiceHeaderAdapter))
	 (redirectlocation  (format nil "/hhub/displayinvoices"))
	 (params nil))
    (setf params (acons "company" (get-login-vendor-company) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-invoice-paid-action" params
      (handler-case 
	  (let ((domainobj (ProcessUpdateRequest adapterobj requestmodel)))
	    (when sessioninvoice
	      (setf (slot-value sessioninvoice 'invoiceheader) domainobj)
	      (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
	      (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht)
	      (updateinvoiceitemsstockinventory productlist invoiceitems vendor company))
	    (function (lambda ()
	      (values redirectlocation domainobj))))
	(error (c)
	  (let ((exceptionstr (format nil  "Business Error:~A: ~a~%" (mysql-now) (getexceptionstr c))))
	    (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				    :direction :output
				    :if-exists :append
				    :if-does-not-exist :create)
	      (format stream "~A~A" exceptionstr (sb-debug:list-backtrace)))
	    ;; return the exception.
	    (error 'hhub-business-function-error :errstring exceptionstr)))))))

(defun updateinvoiceitemsstockinventory (products invoiceitems vendor company)
  "中文：发票确认/付款时按行项扣减商品库存（粗粒度）。最后 dod-reset-vendor-products-functions 重置缓存。"
  (mapcar (lambda (item)
	    (let* ((prd-id (slot-value item 'prd-id))
		   (qty (slot-value item 'qty))
		   (prd (search-item-in-list 'row-id prd-id products)))
	      (if prd (update-stock-inventory prd qty)))) invoiceitems)
  ;; reset the vendor order functions
  (dod-reset-vendor-products-functions vendor company))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;; SHOW THE INVOICE PAYMENT PAGE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：发票流程的"付款收款页"（Step 5）—— 显示二维码 + Finish 按钮。
(defun com-hhub-transaction-show-invoice-payment-page ()
  "中文：发票付款页 PEP 入口（Step 5）。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed. 
    (with-mvc-ui-page "Invoice Payment Page" #'create-model-for-showinvoicepaymentpage #'create-widgets-for-showinvoicepaymentpage :role :vendor )))

(defun create-model-for-showinvoicepaymentpage ()
  "中文：付款页 model：先把发票状态切为新值 status（推测 PENDINGPAYMENT 或 PAID）→
   同步会话内 invoiceheader → 返回 (sessioninvkey, totalvalue, invnum)。"
  (let* ((company (get-login-vendor-company))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (status (hunchentoot:parameter "status"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (invoiceheader (slot-value sessioninvoice 'invoiceheader))
	 (invnum (slot-value invoiceheader 'invnum))
	 (invoiceitems (slot-value sessioninvoice 'InvoiceItems))
	 (totalvalue (calculate-invoice-totalaftertax invoiceitems))
	 (requestmodel (make-instance 'InvoiceHeaderStatusRequestModel
					 :invnum invnum
					 :status status
					 :totalvalue totalvalue
					 :company company))
	 (headeradapter (make-instance 'InvoiceHeaderAdapter))
	 (params nil))
    
    (setf params (acons "company" company params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-show-invoice-payment-page" params
      (handler-case 
      (let ((domainobj (ProcessUpdateRequest headeradapter requestmodel)))
	(when sessioninvoice
	  (setf (slot-value sessioninvoice 'invoiceheader) domainobj)
	  (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
	  (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht))	   
	(function (lambda ()
	  (values sessioninvkey totalvalue invnum))))
	(error (c)
	  (let ((exceptionstr (format nil  "Business Error:~A: ~a~%" (mysql-now) (getexceptionstr c))))
	    (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				    :direction :output
				    :if-exists :append
				    :if-does-not-exist :create)
	      (format stream "~A~A" exceptionstr (sb-debug:list-backtrace)))
	    ;; return the exception.
	    (error 'hhub-business-function-error :errstring exceptionstr)))))))

(defun create-widgets-for-showinvoicepaymentpage (modelfunc)
  "中文：付款页 widgets：面包屑（5 步流程）+ Print/Previous/Finish 三按钮 + 付款二维码 widget。
   Finish 表单提交到 vinvoicepaidaction 把状态改为 PAID。"
  (multiple-value-bind (sessioninvkey totalvalue invnum) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		      (with-vendor-breadcrumb
			(:li :class "breadcrumb-item no-print" (:a :href "displayinvoices" "Invoices"))
			(:li :class "breadcrumb-item no-print" (:a :href (format nil "editinvoicepage?invnum=~A" invnum) "Edit Invoice"))
			(:li :class "breadcrumb-item no-print" (:a :href (format nil "vproductsforinvoicepage?sessioninvkey=~A" sessioninvkey) "Select Products"))
			(:li :class "breadcrumb-item no-print" (:a :href (format nil "vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey) "Confirm Invoice"))))))
	   (widget2 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-html-div-row
			  (with-html-div-col-4
			    (:h5 :class "no-print" "Invoice Payment - Step 5:")
			    (:a :class "btn btn-primary btn-lg" :role "button" :href (format nil "vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey) :onclick (format nil "window.open(this.href).print(); return false;")   "Print&nbsp;&nbsp;"(:i :class "fa-solid fa-print")))
			  (with-html-div-col-4
			    (:a :role "button" :class "btn btn-lg btn-primary btn-block no-print" :href (format nil "vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey) "Previous"))
			  (with-html-div-col-4
			    (with-html-form-having-submit-event "form-invoicepaidaction"  "vinvoicepaidaction" 
			      (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
			      (with-html-input-text-hidden "status" "PAID")
			      (:button :class "btn btn-lg btn-primary btn-block no-print" :type "submit" "FINISH"))))))))
      (widget3 (function (lambda ()
		 (cl-who:with-html-output (*standard-output* nil)
		   (display-invoice-payment-widget totalvalue))))))
      (list widget1 widget2 widget3))))

(defun display-invoice-payment-widget ( amountdue)
  "中文：渲染付款 widget（基于模板 8）。format 把 amountdue 填入两次 ~A。"
  (let ((filecontent (funcall (nst-get-cached-invoice-template-func :templatenum 8))))
    (setf filecontent (format nil filecontent amountdue amountdue))
    (cl-who:with-html-output (*standard-output* nil)
      (cl-who:str filecontent))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;; SHOW THE INVOICE FINAL PAGE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：发票流程"确认 + 完成"页（Step 4 → 创建持久化 / 更新发票头）。
(defun com-hhub-transaction-show-invoice-confirm-page ()
  "中文：发票确认页 PEP 入口（Step 4）。展示完整发票模板 + Finish 按钮，提交后写库。"
  (with-vend-session-check ;; delete if not needed. 
    (with-mvc-ui-page "Invoice Confirm Page" #'create-model-for-showinvoiceconfirmpage #'create-widgets-for-showinvoiceconfirmpage :role :vendor )))

(defun remove-invoice-item-markers-from-template (invoicetemplate)
  "中文：从原始模板中删除 <!--ROW_SNIPPET_BEGIN--> ... <!--ROW_SNIPPET_END--> 子模板，
   防止 generate-invoice-items-rows 渲染后在原占位重复出现一次。"
  ;; Clean the invoice item markers from original template
  (let* ((row-regex "(?s)<!--ROW_SNIPPET_BEGIN-->(.*?)<!--ROW_SNIPPET_END-->")
         (row-sub-template (cl-ppcre:register-groups-bind (snippet) (row-regex invoicetemplate) snippet)))
    (setf invoicetemplate (cl-ppcre:regex-replace-all row-sub-template invoicetemplate ""))
    invoicetemplate))

(defun create-model-for-showinvoiceconfirmpage ()
  "中文：发票确认页 model：通过 context-id 幂等查找发票头（不存在则取会话中的临时头），
   渲染完整发票 HTML（行项 + GST 汇总 + UPI 二维码）；返回多值给 widgets 用。"
  (let* ((company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (sessioninvtaxbreakdown (slot-value sessioninvoice 'invoicetaxbreakdown))
	 (context-id (slot-value sessioninvheader 'context-id)) 
	 (hrequestmodel (make-instance 'InvoiceHeaderContextIDRequestModel
				      :context-id context-id
				      :company company))
	 (headeradapter (make-instance 'InvoiceHeaderAdapter))
	 (invheader (processreadrequest headeradapter hrequestmodel))
         (invnum (slot-value invheader 'invnum))
	 (status (slot-value invheader 'status))
	 (irequestmodel (make-instance 'InvoiceItemRequestModel
				       :company company
				       :invoiceheader invheader))
	 (itemsadapter (make-instance 'InvoiceItemAdapter))
	 (sessioninvitems (processreadallrequest itemsadapter irequestmodel))
	 (totalvalue (calculate-invoice-totalaftertax sessioninvitems))
	 (qrcodepath (format nil "~A/img~A" *siteurl* (generateqrcodeforvendor vendor "ABC" invnum totalvalue)))
	 (invoicetemplate (funcall (nst-get-cached-invoice-template-func :templatenum 13)))
	 (invoiceitemshtmlfunc (generate-invoice-items-rows  sessioninvitems (if (equal status "PAID") T NIL) sessioninvkey invoicetemplate))
	 (invoicetaxbreakdownfunc (render-tax-summary-html sessioninvtaxbreakdown))
	 ;;(invoiceitemshtmlfunc (invoicetemplatefillitemrows sessioninvitems (if (equal status "PAID") T NIL) sessioninvkey))
	 (currency (get-account-currency company))
	 (params nil))
 
    (setf invoicetemplate (remove-invoice-item-markers-from-template invoicetemplate))
    (setf invoicetemplate (funcall (invoicetemplatefill invoicetemplate invheader sessioninvitems invoiceitemshtmlfunc invoicetaxbreakdownfunc qrcodepath currency vendor)))
    (setf (slot-value sessioninvoice 'InvoiceItems) sessioninvitems)
    (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
    (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht)	   
    (setf params (acons "company" (get-login-vendor-company) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    
    (with-hhub-transaction "com-hhub-transaction-show-invoice-confirm-page" params 
      (function (lambda ()
	(values sessioninvkey invnum  invoicetemplate))))))


(defun create-widgets-for-showinvoiceconfirmpage (modelfunc)
  "中文：发票确认页 widgets：3 步面包屑 + Previous / NEXT 按钮（NEXT 进入付款页）+ 整段发票模板。"
  (multiple-value-bind (sessioninvkey  invnum  invoicetemplate) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		      (with-vendor-breadcrumb
			(:li :class "breadcrumb-item no-print" (:a :href "displayinvoices" "Invoices"))
			(:li :class "breadcrumb-item no-print" (:a :href (format nil "editinvoicepage?invnum=~A" sessioninvkey) "Edit Invoice"))
			(:li :class "breadcrumb-item no-print" (:a :href (format nil "vproductsforinvoicepage?sessioninvkey=~A" sessioninvkey) "Select Products"))))))
	   (widget2 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-html-div-row
			  (with-html-div-col-4 "")
			  (with-html-div-col-4
			    (:a :role "button" :class "btn btn-lg btn-primary btn-block no-print" :href (format nil "vproductsforinvoicepage?sessioninvkey=~A" sessioninvkey) "Previous"))
			  (with-html-div-col-4
			    (with-html-form  (format nil "form-invoicepaymentpage")  "vinvoicepaymentpage" 
			      (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
			      (with-html-input-text-hidden "invnum" invnum)
			      (with-html-input-text-hidden "status" "PENDINGPAYMENT")
			      (:button :class "btn btn-lg btn-primary btn-block no-print" :type "submit" "NEXT"))))
			(:br)))))
	   (widget3 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-catch-submit-event "idinvoiceconfirmpage2"
			  (cl-who:str invoicetemplate)))))))
	   (list widget1 widget2 widget3))))
	

;; ----------------------------------------------------------------------------
;; 节段：发票金额计算辅助 —— 与 nst-bl-Order.lisp 的 calculate-order-total* 等价。
;; ----------------------------------------------------------------------------

(defun calculate-invoice-totalbeforetax (invoiceitems)
  "中文：发票税前合计 = ∑ taxablevalue（fround 取整）。"
  (fround (reduce #'+ (mapcar (lambda (item) (slot-value item 'taxablevalue)) invoiceitems))))

(defun calculate-invoice-totalaftertax (invoiceitems)
  "中文：发票税后合计 = ∑ (taxablevalue + cgstamt + sgstamt + igstamt)（fround 取整）。"
  (fround (reduce #'+ (mapcar (lambda (item)
					    (let* ((cgstamt (slot-value item 'cgstamt))
						   (sgstamt (slot-value item 'sgstamt))
						   (igstamt (slot-value item 'igstamt))
						   (taxablevalue (slot-value item 'taxablevalue)))
					      (+ taxablevalue sgstamt cgstamt igstamt))) invoiceitems))))


(defun calculate-invoice-totalcgst (invoiceitems)
  "中文：行项 CGST 金额求和。"
 (reduce #'+ (mapcar (lambda (item) (slot-value item 'cgstamt)) invoiceitems)))

(defun calculate-invoice-totalsgst (invoiceitems)
  "中文：行项 SGST 金额求和。"
 (reduce #'+ (mapcar (lambda (item) (slot-value item 'sgstamt)) invoiceitems)))

(defun calculate-invoice-totaligst (invoiceitems)
  "中文：行项 IGST 金额求和。"
  (reduce #'+ (mapcar (lambda (item) (slot-value item 'igstamt)) invoiceitems)))

(defun calculate-invoice-totalgst (invoiceheader invoiceitems)
  "中文：发票级 GST 总额。比较发票头 placeofsupply 与 statecode：
   同州 → CGST + SGST 之和；跨州 → 仅 IGST。"
  (let ((placeofsupply (slot-value invoiceheader 'placeofsupply))
	(statecode (slot-value invoiceheader 'statecode)))
    (if (equal placeofsupply statecode)
	(fround (+ (calculate-invoice-totalcgst invoiceitems) (calculate-invoice-totalsgst invoiceitems)))
	;;else
	(fround (calculate-invoice-totaligst invoiceitems)))))

(defun display-invoice-confirm-page-widget (invoiceheader invoiceitems qrcodepath sessioninvkey)
  "中文：CL-WHO 直出的'确认页'发票样式（与外部 HTML 模板 13 是两条并行的渲染路径，
   推测：保留以兼容老页面）。布局为 13 列 table，含 'TAX INVOICE' 三联式表头、客户信息、行项明细、
   合计、银行账号、UPI 二维码、印章签名等。"
  (with-slots (row-id invnum invdate customer  custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear status vendor company) invoiceheader
    (cl-who:with-html-output (*standard-output* nil)
      (:style "table {width: 100%; border-collapse: collapse;} table.center {margin-left: auto; margin-right: auto;} table, th, td {border: 0.5px dashed grey;} th, td { padding: 1px; text-align: left;} td img{ display: block; margin-left: auto; margin-right: auto; } ")
      (:table 
       (:thead
	(:tr 
	 (:th :colspan "2" "TAX INVOICE")
	 (:th :colspan "3" "Original For Recipient")
	 (:th :colspan "3" "Duplicate for Supplier")
	 (:th :colspan "3" "Triplicate for Supplier")))
	   (:tbody
	    (:tr
	     (:td :colspan "2" "Invoice No. :")
	     (:td :colspan "2" (cl-who:str invnum))
	     (:td :colspan "2" "Status: ")
	     (:td :colspan "2" (cl-who:str status))
	     (if (not (equal transmode "NA"))
		 (cl-who:htm 
		  (:td :colspan "2" "Transportation Mode:")
		  (:td :colspan "1" (cl-who:str transmode))
		  (:td :colspan "2" "Vehicle Number :")
		  (:td :colspan "1" (cl-who:str vnum)))))
	    (:tr
	     (:td :colspan "2" "Invoice Date:")
	     (:td :colspan "2" (cl-who:str (get-date-string invdate)))
	     (:td :colspan "2" "Date of Supply :")
	     (:td :colspan "2" "Place of Supply :")
	     (:td :colspan "2" (cl-who:str (gethash placeofsupply *NSTGSTSTATECODES-HT*)))
	     (:td :colspan "2" "State Code:")
	     (:td :colspan "2" (cl-who:str (gethash statecode *NSTGSTSTATECODES-HT*))))
	    (:tr
	     (:th :colspan "5" "Details of Receiver / Billed to:")
	     (:th :colspan "5" "Details of Consignee / Shipped to:"))
	    (:tr
	     (:td :colspan "2" "Name :")
	     (:td :colspan "3" (cl-who:str (slot-value customer 'name)))
	     (:td :colspan "2" "Name :")
	     (:td :colspan "3" (cl-who:str (slot-value customer 'name))))
	    (:tr
	     (:td :colspan "2" "Address :")
	     (:td :colspan "3" (cl-who:str billaddr))
	     (:td :colspan "2" "Address :")
	     (:td :colspan "3" (cl-who:str shipaddr)))
	    (:tr
	     (:td :colspan "2" "GSTIN :")
	     (:td :colspan "3" (cl-who:str custgstin))
	     (:td :colspan "2" "GSTIN :")
	     (:td :colspan "3" (cl-who:str custgstin)))
	    (:tr
	     (:td :colspan "2" "State :")
	     (:td :colspan "3" (cl-who:str (gethash statecode *NSTGSTSTATECODES-HT*)))
	     (:td :colspan "2" "State :")
	     (:td :colspan "3" (cl-who:str (gethash statecode *NSTGSTSTATECODES-HT*))))
	    (:tr
	     (:th "Sr. No")
	     (mapcar (lambda (item) (cl-who:htm (:th (cl-who:str item)))) (list "Name of Product/Service" "HSN/SAC" "Qty Per Unit" "Qty" "Rate"  "Less: Discount%" "Taxable Value" "CGST" "SGST" "IGST" "Total" "Action")))
	    (let ((incr (let ((count 0)) (lambda () (incf count)))))
	      (mapcar (lambda (item)
			(cl-who:htm (:tr (:td (cl-who:str (funcall incr))) (display-invoice-item-row item (if (equal status "PAID") T NIL) sessioninvkey))))  invoiceitems))
	    ;;<!-- Repeat <tr> as needed for more items -->
	    (:tr
	     (:td :colspan "3" "Total :")
	     (:td :colspan "3" (cl-who:str (calculate-invoice-totalaftertax invoiceitems)))
	     (:td :colspan "7"))
	    (:tr
	     (:td :colspan "3" "Total Invoice Amount in Words:")
	     (:td :colspan "3" (cl-who:str (convert-number-to-words-INR (calculate-invoice-totalaftertax invoiceitems))))
	     (:td :colspan "7"))
	    (:tr
	     (:td :colspan "7" "Bank Details :")
	     (:td :colspan "3" "Total Amount Before Tax :")
	     (:td :colspan "3" (cl-who:str (calculate-invoice-totalbeforetax invoiceitems))))
	    (:tr
	     (:td :colspan "3" "Bank Account Number:")
	     (:td :colspan "4" (cl-who:str bankaccnum))
	     (:td :colspan "3" "Add : CGST :")
	     (:td :colspan "3" (cl-who:str (calculate-invoice-totalcgst invoiceitems))))
	    (:tr
	     (:td :colspan "2" "Bank Branch IFSC :")
	     (:td :colspan "5" (cl-who:str bankifsccode))
	     (:td :colspan "3" "Add : SGST :")
	     (:td :colspan "3" (cl-who:str (calculate-invoice-totalsgst invoiceitems))))
	    (:tr
	     (:td :rowspan "6" :colspan "7" (:img :style "width: 150px; height: 150px;" :src qrcodepath (:span "Pay By UPI")))
	     (:td :colspan "3" "Add : IGST :")
	     (:td :colspan "3" (cl-who:str (calculate-invoice-totaligst invoiceitems))))
	    (:tr
	     (:td :colspan "3" "Tax Amount : GST :")
	     (:td :colspan "3" (cl-who:str (calculate-invoice-totalgst invoiceheader invoiceitems))))
	    (:tr
	     (:td :colspan "3" "Total Amount After Tax :")
	     (:td :colspan "3" (cl-who:str (calculate-invoice-totalaftertax invoiceitems))))
	    (:tr
	     (:td :colspan "3" "GST Payable on Reverse Charge :")
	     (:td :colspan "3" (cl-who:str revcharge)))
	    (:tr
	     (:td :colspan "4" "Certified that the particulars given above are true and correct.")
	     (:td :colspan "2" "(Authorized Signatory)"))
	    (:tr
	     (:td :colspan "6" "For, [Company Name]"))
	    (:tr
	     (:td :colspan "13" "Terms and Conditions :"))
	    (:tr
	     (:td :colspan "13" (cl-who:str tnc))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;; ADD PRODUCT TO CART TO CREATE AN INVOICE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：发票创建流程的 Step 3 —— 选择商品加入'购物车'（会话内 sessioninvitems）。
;; 含商品搜索（livesearch）、条码扫描入口、'Add To Cart' 弹窗（产品数量编辑）。

(defun com-hhub-transaction-add-product-to-invoice-page ()
  "中文：'选商品到发票'页 PEP 入口（Step 3）。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed.
    (with-mvc-ui-page "Add Product To Invoice" #'create-model-for-addprdtoinvoice #'create-widgets-for-addprdtoinvoice :role :vendor )))

(defun create-model-for-addprdtoinvoice ()
  "中文：'选商品'页 model：从会话取当前编辑的发票（sessioninvoice + 行项 + 商品列表 + 状态）+
   卖家全部活跃商品。返回多值供 widgets 渲染。"
  (let* ((sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (invnum (slot-value sessioninvheader 'invnum))
	 (headerstatus (slot-value sessioninvheader 'status))
	 (sessioninvitems (slot-value sessioninvoice 'InvoiceItems))
	 (sessioninvproducts (slot-value sessioninvoice 'invoiceproducts))
	 (products (hhub-get-cached-active-vendor-products)))
    (function (lambda ()
      (values products sessioninvitems sessioninvproducts  headerstatus sessioninvkey invnum)))))

(defun create-widgets-for-addprdtoinvoice (modelfunc)
  "中文：'选商品'页 widgets：面包屑 + 商品搜索框（livesearch）+ 条码扫描 input + Checkout 跳转 +
   购物车表 + 商品列表表。
   若发票状态已是 PAID/SHIPPED/CANCELLED/REFUNDED 则锁定显示状态文本，禁止增减商品。"
  (multiple-value-bind (products sessioninvitems sessioninvproducts headerstatus sessioninvkey invnum) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-vendor-breadcrumb
			  (:li :class "breadcrumb-item" (:a :href "displayinvoices" "Invoices"))
			  (:li :class "breadcrumb-item" (:a :href (format nil "editinvoicepage?invnum=~A" invnum) "Edit Invoice")))
			(with-html-div-row
			  (:div :class "col-xs-6 col-sm-6 col-md-6 col-lg-6"
				(:span "Create Invoice - Step 3:")))))))
	   (widget2 (function (lambda ()
		      (if (or (equal headerstatus "PAID")
			      (equal headerstatus "SHIPPED")
			      (equal headerstatus "CANCELLED")
			      (equal headerstatus "REFUNDED"))
			  (cl-who:with-html-output (*standard-output* nil)
			    (:h2 (cl-who:str (format nil "INVOICE IS ~A" headerstatus))))
			    ;;else
			  (cl-who:with-html-output (*standard-output* nil)
			    (with-html-div-row
			      (with-html-div-col-4 
				(with-html-search-form "idsearchproduct" "searchproduct" "idtxtsearchproduct" "txtsearchproduct" "vsearchproductforinvoice" "onkeyupsearchform1event();" "Product Name"
				  (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
				  (submitsearchform1event-js "#idtxtsearchproduct" "#vendorproductsearchforinvoiceresult" )))
			      (with-html-div-col-4
				(with-html-form-having-submit-event  "barcodescanform" "vaddtocartusingbarcode"
				  ;; here we would like to auto focus on the barcode textbox to input the next barcode upon page reload.
				  (with-html-input-text "barcodeinput" "Product Barcode/UPC/EAN" "Enter Barcode/UPC/EAN" "" NIL "" 1 :autofocus "autofocus")
				  (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
				  (:input :type "submit" :style "display: none;")))
			      (with-html-div-col-4
				    (:a :href (format nil "/hhub/vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey) 
					(:img :src  "/img/checkoutimage.png"  :height "100" :width "350" :alt "checkout"))))
			    (:h2 "Cart Items")
			    (cl-who:str (display-as-table (list "" "Name" "Qty Per Unit" "Price" "" "Discount" "In Cart") sessioninvproducts  'display-product-in-invoice-row sessioninvkey sessioninvitems))
			    (:h2 "Products")
			    (:div :id "vendorproductsearchforinvoiceresult"  :class "container-fluid"
				  (cl-who:str (display-as-table (list "" "Name" "Qty Per Unit" "Price" "" "Discount" "Action") products  'display-add-product-to-invoice-row sessioninvkey sessioninvitems))))))))
	   (widget3 (function (lambda ()
		      (submitformevent-js "#vendorproductsearchforinvoiceresult")))))
      (list widget1 widget2 widget3))))
	   
(defun display-add-product-to-invoice-row (product &rest arguments)
  "中文：'商品'表格单行渲染。已在购物车里则显示绿色对勾；否则显示 'Add To Cart' 按钮（弹窗调数量）。
   units-in-stock 为 0 时显示 'Out Of Stock'。"
  (let* ((sessioninvkey (first (first arguments)))
	 (sessioninvitems (second (first arguments)))
	 (prd-id (slot-value product 'row-id))
	 ;;(qtyincart 0)
	 (prdincart-p (prdinlist-p prd-id sessioninvitems))
	 (prdname (slot-value product 'prd-name))
	 (prd-name (subseq prdname 0 (min 20 (length prdname))))
	 (units-in-stock (slot-value product 'units-in-stock))
	 (qty-per-unit (slot-value product 'qty-per-unit))
	 (images-str (slot-value product 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (company (get-login-vendor-company))
	 (current-price (slot-value product 'current-price))
	 (current-discount (slot-value product 'current-discount))
	 (ppricing (select-product-pricing-by-product-id prd-id company))
	 (pcurr (if ppricing (slot-value ppricing 'currency))))
    (cl-who:with-html-output (*standard-output* nil)
      (:td :height "10px" (render-single-product-image prd-name imageslst images-str "50" "50"))
      (:td  :height "10px" (cl-who:str prd-name))
      (:td  :height "10px" (cl-who:str qty-per-unit))
      (:td  :height "10px" (cl-who:str current-price))
      (:td  :height "10px" (cl-who:str pcurr))
      (:td  :height "10px" (cl-who:str (if current-discount current-discount "NIL")))
      (:td  :height "10px"
	    (if  prdincart-p
		 (cl-who:htm (:a :class "btn btn-sm btn-success" :role "button"  :onclick "return false;" :href (format nil "javascript:void(0);")(:i :class "fa-solid fa-check")))
		 ;; else 
		 (if (and units-in-stock (> units-in-stock 0))
		     (cl-who:htm
		      (:div :class "form-group product-details"
			    (:button :onclick "addtocartclick(this.id);" :id (format nil "btnaddproduct_~A" prd-id) :name (format nil "btnaddproduct~A" prd-id) :type "button" :class "add-to-cart-btn" :data-bs-toggle "modal" :data-bs-target (format nil "#producteditqty-modal~A" prd-id) (:i :class "fa-solid fa-cart-shopping") "&nbsp;Add To Cart")
			    (modal-dialog-v2 (format nil "producteditqty-modal~A" prd-id) (cl-who:str (format nil "Edit Product Quantity - Available: ~A" units-in-stock)) (vproduct-qty-add-for-invoice-html product ppricing sessioninvkey))))			
		     ;; else
		     (cl-who:htm
		      (:div :class "col-6" 
			    (:h5 (:span :class "label label-danger" "Out Of Stock"))))))))))

(defun display-product-in-invoice-row (product &rest arguments)
  "中文：'购物车'表格单行渲染。已在购物车则显示数量徽章；不在则显示 'Add To Cart' 按钮。"
  (let* ((sessioninvkey (first (first arguments)))
	 (sessioninvitems (second (first arguments)))
	 (prd-id (slot-value product 'row-id))
	 ;;(qtyincart 0)
	 (prdincart-p (prdinlist-p prd-id sessioninvitems))
	 (itemincart (if prdincart-p (search-item-in-list 'prd-id prd-id sessioninvitems) nil))
	 (qtyincart (if itemincart (slot-value itemincart 'qty)))
	 (prdname (slot-value product 'prd-name))
	 (prd-name (subseq prdname 0 (min 20 (length prdname))))
	 (units-in-stock (slot-value product 'units-in-stock))
	 (qty-per-unit (slot-value product 'qty-per-unit))
	 (images-str (slot-value product 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (company (get-login-vendor-company))
	 (price (slot-value product 'current-price))
	 (ppricing (select-product-pricing-by-product-id prd-id company))
	 (pprice (if ppricing (slot-value ppricing 'price)))
	 (pdiscount (if ppricing (slot-value ppricing 'discount)))
	 (pcurr (if ppricing (slot-value ppricing 'currency))))
    (cl-who:with-html-output (*standard-output* nil)
      (:td :height "10px" (render-single-product-image prd-name imageslst images-str "30" "30"))
      (:td  :height "10px" (cl-who:str prd-name))
      (:td  :height "10px" (cl-who:str qty-per-unit))
      (:td  :height "10px" (cl-who:str (if ppricing pprice price)))
      (:td  :height "10px" (cl-who:str pcurr))
      (:td  :height "10px" (cl-who:str (if pdiscount pdiscount "NIL")))
      (:td  :height "10px"
	    (if  prdincart-p
		 (cl-who:htm  (:h4 (:span :class "badge rounded-pill bg-info" (cl-who:str (format nil "~A" qtyincart)))))
		 ;; else 
		 (if (and units-in-stock (> units-in-stock 0))
		     (cl-who:htm
		      (:div :class "form-group"
			    (:button :onclick "addtocartclick(this.id);" :id (format nil "btnaddproduct_~A" prd-id) :name (format nil "btnaddproduct~A" prd-id) :type "button" :class "add-to-cart-btn" :data-bs-toggle "modal" :data-bs-target (format nil "#producteditqty-modal~A" prd-id) (:i :class "fa-solid fa-cart-shopping") "&nbsp;Add To Cart")
			    (modal-dialog-v2 (format nil "producteditqty-modal~A" prd-id) (cl-who:str (format nil "Edit Product Quantity - Available: ~A" units-in-stock)) (vproduct-qty-add-for-invoice-html product ppricing sessioninvkey))))			
		     ;; else
		     (cl-who:htm
		      (:div :class "col-6" 
			    (:h5 (:span :class "label label-danger" "Out Of Stock"))))))))))


(defun vproduct-qty-add-for-invoice-html (product product-pricing sessioninvkey)
  "中文：'编辑商品数量'弹窗内容：商品图 / HSN / 价格-折扣 widget / 数量滑块 / Submit 按钮。
   表单 action='vaddtocartforinvoice'。"
  (let* ((prd-id (slot-value product 'row-id))
	 (images-str (slot-value product 'prd-image-path))
	 (imageslst (safe-read-from-string images-str))
	 (units-in-stock (slot-value product 'units-in-stock))
	 (prd-name (slot-value product 'prd-name))
	 (hsn-code (slot-value product 'hsn-code)))
	
  (cl-who:with-html-output (*standard-output* nil)
    (with-html-form  (format nil "form-addproduct~A" prd-id)  "vaddtocartforinvoice" 
      (with-html-input-text-hidden "prd-id" prd-id)
      (:p :class "product-name"  (cl-who:str prd-name))
      (:p :class "product-hsn-code" "HSN Code: " (cl-who:str hsn-code))
      (:a :href (format nil "prddetailsforcust?id=~A" prd-id) 
	  (render-single-product-image prd-name imageslst images-str "100" "83"))      
      (product-price-with-discount-widget product product-pricing)
      ;; Qty increment and decrement control.
      (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
      (html-range-control "prdqty" prd-id "1" (max (mod units-in-stock 20) 10) "1" "1")
      (:div :class "form-group" 
	    (:input :type "submit"  :class "btn btn-primary" :value "Add To Cart"))))))

(defun com-hhub-transaction-search-product-for-invoice-action ()
  "中文：商品搜索（在创建发票流程中）livesearch 控制器。会话：with-vend-session-check。
   按 name LIKE 模糊搜，渲染表格回填 #vendorproductsearchforinvoiceresult。"
  (with-vend-session-check
    (let* ((company (get-login-vendor-company))
	   (name (hunchentoot:parameter "txtsearchproduct"))
	   (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	   (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	   (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	   (sessioninvitems (slot-value sessioninvoice 'InvoiceItems))
	   (products (search-products (format nil "%~A%" name) company)))
      (if (> (length products) 0)
	  (cl-who:with-html-output (*standard-output* nil)
	    (cl-who:str (display-as-table (list "" "Name"  "Qty Per Unit" "Price" "" "Discount" "Action") products  'display-add-product-to-invoice-row sessioninvkey sessioninvitems)))
	  ;; else
	  (cl-who:with-html-output (*standard-output* nil)
	    (:h3 (cl-who:str "No Records Found")))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ADD TO CART BY VENDOR FOR INVOICE GENERATION ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 节段：把商品加入购物车（写库 InvoiceItem + 同步会话内 sessioninvoice 各字段）。

(defun create-model-for-vendaddtocartforinvoice ()
  "中文：添加商品到发票购物车 model：
     1) 取商品/数量；按 placeofsupply vs statecode 判 intra/inter，重算 GST；
     2) 通过 ProcessReadRequest 读取发票头（context-id）；
     3) ProcessCreateRequest 把行项写库；
     4) add-item-to-tax-breakdown 同步税额聚合；
     5) wallet 不存在则 create-wallet；
     6) 把新行项 / 商品 push 到 sessioninvoice，写回会话。
   返回：闭包 (values redirectlocation)。"
  (let* ((company (get-login-vendor-company))
	 (prd-id (parse-integer (hunchentoot:parameter "prd-id")))
	 (prdqty (parse-integer (hunchentoot:parameter "prdqty")))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (sessioninvitems (slot-value sessioninvoice 'InvoiceItems))
	 (sessioninvproducts (slot-value sessioninvoice 'invoiceproducts))
	 (sessioninvtaxbreakdown (slot-value sessioninvoice 'invoicetaxbreakdown))
	 (context-id (slot-value sessioninvheader 'context-id))
	 (customer (slot-value sessioninvoice 'customer))
	 (productlist (hhub-get-cached-vendor-products))
	 (product (search-item-in-list 'row-id prd-id productlist))
	 (gstvalues (get-gstvalues-for-product product))
	 (current-price (slot-value product 'current-price))
	 (current-discount (slot-value product 'current-discount))
	 (qty-per-unit (slot-value product 'qty-per-unit))
	 (unit-of-measure (slot-value product 'unit-of-measure))
	 (pname (slot-value product 'prd-name))
	 (prd-name (subseq pname 0 (min 30 (length pname))))
	 (hsncode (slot-value product 'hsn-code))
	 (taxablevalue (- (* prdqty current-price) (if current-discount (/ (* prdqty  current-price current-discount) 100) 0.00)))
	 (placeofsupply (slot-value sessioninvheader 'placeofsupply))
	 (statecode (slot-value sessioninvheader 'statecode))
	 (intrastate (if (equal statecode placeofsupply) T NIL))
	 (interstate (if (equal statecode placeofsupply) NIL T)) 
	 (cgstrate (if gstvalues (first gstvalues) 0.00)) 
	 (cgstamt (if intrastate (/ ( * taxablevalue cgstrate) 100) 0.00))
	 (sgstrate (if gstvalues (second gstvalues) 0.00))
	 (sgstamt (if intrastate (/ (* sgstrate taxablevalue) 100) 0.00))
	 (igstrate (if gstvalues (third gstvalues) 0.00)) 
	 (igstamt (if interstate (/ (* igstrate taxablevalue) 100) 0.00))
	 (totalitemval (+ taxablevalue (if intrastate (+ cgstamt sgstamt) igstamt)))
	 (vendor (product-vendor product))
	 (wallet (get-cust-wallet-by-vendor customer vendor company))
	 (ihdadapter (make-instance 'InvoiceHeaderAdapter))
	 (ihdrequestmodel (make-instance 'InvoiceHeaderContextIDRequestModel
					 :context-id context-id
					 :company company))
	 (invheader (ProcessReadRequest ihdadapter ihdrequestmodel))
	 (redirectlocation (format nil "/hhub/vproductsforinvoicepage?sessioninvkey=~A" sessioninvkey))
	 (invitmrequestmodel (make-instance 'InvoiceItemRequestModel
					 :InvoiceHeader invheader
					 :prd-id prd-id
					 :prddesc prd-name
					 :hsncode hsncode
					 :qty prdqty
					 :uom (format nil "~A ~A" qty-per-unit unit-of-measure)
					 :price current-price
					 :discount current-discount
					 :taxablevalue taxablevalue
					 :cgstrate cgstrate
					 :cgstamt cgstamt
					 :sgstrate sgstrate
					 :sgstamt sgstamt
					 :igstrate igstrate
					 :igstamt igstamt
					 :company company
					 :totalitemval totalitemval))
	 (invitmadapter (make-instance 'InvoiceItemAdapter))
	 (InvoiceItem (ProcessCreateRequest invitmadapter invitmrequestmodel)))
    ;;(logiamhere (format nil "Adding invoice item to cart ~A" InvoiceItem)) 
    (add-item-to-tax-breakdown sessioninvtaxbreakdown InvoiceItem)
    (unless wallet (create-wallet customer vendor company))
    (when (and wallet (> prdqty 0) sessioninvoice)
      (setf (slot-value sessioninvoice 'InvoiceItems) (append sessioninvitems (list invoiceitem)))
      (setf (slot-value sessioninvoice 'invoiceproducts) (append sessioninvproducts (list product)))
      (setf (slot-value sessioninvoice 'invoicetaxbreakdown) sessioninvtaxbreakdown)
      ;;(setf (hhub-get-cached-vendor-products) (remove product productlist))
      (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
      (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht)
      (function (lambda ()
	(values redirectlocation))))))


(defun com-hhub-transaction-vendor-addtocart-for-invoice-action ()
  :documentation "This function is responsible for adding the product and product quantity to the shopping cart.
   中文：'加入购物车'PEP 入口。会话：with-vend-session-check。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendaddtocartforinvoice #'create-widgets-for-genericredirect)))
    


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;ADD TO CART USING BARCODE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun create-model-for-vendaddtocartusingbarcode ()
  "中文：条码扫描添加商品 model：按 barcode（'upc' slot）查商品；如已在购物车则数量+1（ProcessUpdateRequest），
   否则 ProcessCreateRequest 新建行项；GST 与购物车流程同。"
  (let* ((company (get-login-vendor-company))
	 (barcode (hunchentoot:parameter "barcodeinput"))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (sessioninvitems (slot-value sessioninvoice 'InvoiceItems))
	 (sessioninvproducts (slot-value sessioninvoice 'invoiceproducts))
	 (context-id (slot-value sessioninvheader 'context-id))
	 (customer (slot-value sessioninvoice 'customer))
	 (productlist (hhub-get-cached-vendor-products))
	 (product (search-item-in-list 'upc barcode productlist))
	 (prd-id (slot-value product 'row-id))
	 (itemincart (if (iteminlist-p 'prd-id prd-id sessioninvitems) (search-item-in-list 'prd-id prd-id sessioninvitems)))
	 (newqty (if itemincart (+ (slot-value itemincart 'qty) 1) 1))
	 (gstvalues (get-gstvalues-for-product product))
	 (current-price (slot-value product 'current-price))
	 (qty-per-unit (slot-value product 'qty-per-unit))
	 (pname (slot-value product 'prd-name))
	 (prd-name (subseq pname 0 (min 30 (length pname))))
	 (hsncode (slot-value product 'hsn-code))
	 (product-pricing (select-product-pricing-by-product-id prd-id company))
	 (prd-discount (if product-pricing (slot-value product-pricing 'discount) nil))
	 (taxablevalue (- (* newqty current-price) (if prd-discount (/ (* newqty current-price prd-discount) 100) 0.00)))
	 (placeofsupply (slot-value sessioninvheader 'placeofsupply))
	 (statecode (slot-value sessioninvheader 'statecode))
	 (intrastate (if (equal statecode placeofsupply) T NIL))
	 (interstate (if (equal statecode placeofsupply) NIL T)) 
	 (cgstrate (if gstvalues (first gstvalues) 0.00)) 
	 (cgstamt (if intrastate (/ ( * taxablevalue cgstrate) 100) 0.00))
	 (sgstrate (if gstvalues (second gstvalues) 0.00))
	 (sgstamt (if intrastate (/ (* sgstrate taxablevalue) 100) 0.00))
	 (igstrate (if gstvalues (third gstvalues) 0.00)) 
	 (igstamt (if interstate (/ (* igstrate taxablevalue) 100) 0.00))
	 (totalitemval (+ taxablevalue (if intrastate (+ cgstamt sgstamt) igstamt)))
	 (vendor (product-vendor product))
	 (wallet (get-cust-wallet-by-vendor customer vendor company))
	 (ihdadapter (make-instance 'InvoiceHeaderAdapter))
	 (ihdrequestmodel (make-instance 'InvoiceHeaderContextIDRequestModel
					 :context-id context-id
					 :company company))
	 (invheader (ProcessReadRequest ihdadapter ihdrequestmodel))
	 (redirectlocation (format nil "/hhub/vproductsforinvoicepage?sessioninvkey=~A" sessioninvkey))
	 (invitmrequestmodel (make-instance 'InvoiceItemRequestModel
					 :InvoiceHeader invheader
					 :prd-id prd-id
					 :prddesc prd-name
					 :hsncode hsncode
					 :qty newqty
					 :uom qty-per-unit
					 :price current-price
					 :discount prd-discount
					 :taxablevalue taxablevalue
					 :cgstrate cgstrate
					 :cgstamt cgstamt
					 :sgstrate sgstrate
					 :sgstamt sgstamt
					 :igstrate igstrate
					 :igstamt igstamt
					 :company company
					 :totalitemval totalitemval
					 :status "PENDING"))
	 (invitmadapter (make-instance 'InvoiceItemAdapter))
	 (InvoiceItem (if itemincart (ProcessUpdateRequest invitmadapter invitmrequestmodel) (ProcessCreateRequest invitmadapter invitmrequestmodel))))
		    
    (unless wallet (create-wallet customer vendor company))
    (when (and wallet sessioninvoice)
      (when  itemincart
	;; if updated an item using barcode then, we need to replace the current item
	(setf sessioninvitems (remove itemincart sessioninvitems))
	(setf sessioninvproducts (remove product sessioninvproducts)))
	;;(setf (hunchentoot:session-value :login-prd-cache) (remove product productlist)))
      ;; if created an item using barcode use this 
      (setf (slot-value sessioninvoice 'InvoiceItems) (append sessioninvitems (list invoiceitem)))
      (setf (slot-value sessioninvoice 'invoiceproducts) (append sessioninvproducts (list product)))
      (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
      (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht)
      (function (lambda ()
	(values redirectlocation))))))

(defun create-widgets-for-vendaddtocartusingbarcode (modelfunc)
  "中文：条码扫描添加后通用 redirect widgets。"
 (funcall #'create-widgets-for-genericredirect modelfunc))


(defun com-hhub-transaction-vendor-addtocart-using-barcode-action ()
  :documentation "This function is responsible for adding the product and product quantity to the shopping cart.
   中文：通过扫描条码 UPC/EAN 添加商品到发票购物车的 PEP 入口。
   备注：会话用了 with-cust-session-check（推测：原作者笔误，应是 with-vend-session-check）。"
  (with-cust-session-check
    (let ((uri (with-mvc-redirect-ui #'create-model-for-vendaddtocartusingbarcode #'create-widgets-for-vendaddtocartusingbarcode)))
      (format nil "~A" uri))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;; ----------------------------------------------------------------------------
;; 节段：发票创建流程的 Step 1 —— 选择客户。
;;   选已有客户 / 用 GUEST 客户占位 / 弹窗新建客户。
;; ----------------------------------------------------------------------------

(defun com-hhub-transaction-add-customer-to-invoice-page ()
  "中文：'选客户到发票'页 PEP 入口（Step 1）。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed.
    (with-mvc-ui-page "Add Customer To Invoice" #'create-model-for-addcusttoinvoice #'create-widgets-for-addcusttoinvoice :role  :vendor )))

(defun create-model-for-addcusttoinvoice()
  "中文：'选客户到发票'页 model：取 GUEST 占位客户 + 卖家自有客户列表。
   返回多值供 widgets 渲染。"
  (let* ((company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (guestcustomer (select-guest-customer company))
	 (guestcustid (slot-value guestcustomer 'row-id))
	 (mycustomers (select-customers-for-vendor vendor company)))
    (function (lambda ()
      (values mycustomers guestcustid)))))

(defun create-widgets-for-addcusttoinvoice (modelfunc)
  "中文：'选客户'页 widgets：面包屑 + 'Add Customer' 弹窗按钮 + 'NEXT (用 GUEST)' 按钮 +
   按姓名/手机搜索框（双 livesearch）+ 客户列表表格。"
  (multiple-value-bind (mycustomers guestcustid) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-vendor-breadcrumb
			  (:li :class "breadcrumb-item" (:a :href "displayinvoices" "Invoices")))
			(with-html-div-row
			  (:div :class "col-xs-6 col-sm-6 col-md-6 col-lg-6"
				(:span "Create Invoice - Step 1: ")
				(:h2 "Select Customer (Optional)"))
			  (:div :class "col-xs-3 col-sm-3 col-md-3 col-lg-3"
				(:button :type "button" :class "btn btn-lg btn-primary btn-block" :data-bs-toggle "modal" :data-bs-target (format nil "#vendorcreatecustomer-modal") (:i :class "fa-solid fa-user") "&nbsp;Add Customer")
				(modal-dialog-v2 (format nil "vendorcreatecustomer-modal")  "Create Customer" (vendor-create-update-customer-dialog nil)))
			  (:div :class "col-xs-3 col-sm-3 col-md-3 col-lg-3 form-group"
				(with-html-form (format nil "invoicecreateforcust~A" guestcustid) "editinvoicepage"
				  (with-html-input-text-hidden "mode" "create")
				  (with-html-input-text-hidden "custid" guestcustid)
				  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "NEXT"))))))))
	   (widget2 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-html-div-row
			  (:div :class "col-xs-6 col-sm-6 col-md-6 col-lg-6"    
				(with-html-search-form "idsearchmycustomerbyname" "searchmycustomer" "idtxtsearchcustomername" "txtsearchcustomername" "vsearchcustbyname" "onkeyupsearchform1event();" "Customer Name"
				  (submitsearchform1event-js "#idtxtsearchcustomername" "#vendormycustomerssearchresult" )))
			  (:div :class "col-xs-6 col-sm-6 col-md-6 col-lg-6"    
				(with-html-search-form "idsearchmycustomerbyphone" "searchmycustomer" "idtxtsearchcustomerphone" "txtsearchcustomerphone" "vsearchcustbyphone" "onkeyupsearchform2event();" "Customer Phone"
				  (submitsearchform2event-js "#idtxtsearchcustomerphone" "#vendormycustomerssearchresult" ))))
			(:div :id "vendormycustomerssearchresult"  :class "container-fluid"
			      (cl-who:str (display-as-table (list "Name" "Phone" "Action") mycustomers 'display-add-customer-to-invoice-row))))))))
      (list widget1 widget2))))

(defun display-add-customer-to-invoice-row (customer &rest arguments)
  "中文：客户表格单行渲染：姓名 / 手机 / 'Create Invoice' 按钮（直接跳到 Step 2 编辑发票）。"
  (declare (ignore arguments))
  (let* ((cust-id (slot-value customer 'row-id))
	 (cust-phone (slot-value customer 'phone))
	 (cust-name (slot-value customer 'name)))
    (with-slots (name phone address) customer
      (cl-who:with-html-output (*standard-output* nil)
	(:td  :height "10px" (cl-who:str cust-name))
	(:td  :height "10px" (cl-who:str cust-phone))
	(:td  :height "10px"
	      (with-html-form (format nil "invoicecreateforcust~A" cust-id) "editinvoicepage"
		(with-html-input-text-hidden "mode" "create")
		(with-html-input-text-hidden "custid" cust-id)
		(:div :class "form-group"
			  (:button :class "btn btn-sm btn-info" :type "submit" (:i :class "fa-solid fa-user-plus" :aria-hidden "true") "&nbsp;Create Invoice&nbsp;"))))))))
	  ;;    (:a :href (format nil "/hhub/editinvoicepage?mode=create&custid=~A" cust-id) :alt "Select Customer" (:i :class "fa-solid fa-user-plus" :aria-hidden "true")))))))

	 


;; ----------------------------------------------------------------------------
;; 节段：发票头列表 / 搜索 / 编辑 / 创建（卖家发票后台主入口集合）
;; ----------------------------------------------------------------------------

(defun InvoiceHeader-search-html ()
  :description "This will create a html search box widget.
   中文：渲染发票号搜索框（livesearch + 3 字符触发）。结果渲染到 #InvoiceHeaderlivesearchresult。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
	  (:div :id "custom-search-input" :class "col-3"
		(with-html-search-form "idsyssearchInvoiceHeader" "syssearchInvoiceHeader" "idInvoiceHeaderlivesearch" "InvoiceHeaderlivesearch" "searchinvoicesaction" "onkeyupsearchform1event();" "Search By Invoice Number. Type 3 letters..."
		  (submitsearchform1event-js "#idInvoiceHeaderlivesearch" "#InvoiceHeaderlivesearchresult"))))))

(defun com-hhub-transaction-show-invoices-page ()
  :description "This is a show list page for all the InvoiceHeader entities.
   中文：发票总览页 PEP 入口（卖家后台首页）。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed. 
    (with-mvc-ui-page "InvoiceHeader" #'create-model-for-showInvoiceHeader #'create-widgets-for-showInvoiceHeader :role  :vendor )))

(defun create-model-for-showInvoiceHeader ()
  :description "This is a model function which will create a model to show InvoiceHeader entities.
   中文：发票总览 model：构造 RequestModel/Adapter/Presenter，processreadallrequest 取本卖家全部发票头 →
   CreateAllViewModel；with-hhub-transaction PEP 鉴权。"
  (let* ((company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (presenterobj (make-instance 'InvoiceHeaderPresenter))
	 (requestmodelobj (make-instance 'InvoiceHeaderRequestModel
					 :vendor vendor 
					 :company company))
	 (adapterobj (make-instance 'InvoiceHeaderAdapter))
	 (objlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj objlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'InvoiceHeaderHTMLView))
	 (params nil))

    (setf params (acons "company" (get-login-vendor-company) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-show-invoices-page" params 
      (function (lambda ()
	(values viewallmodel htmlview))))))

(defun create-widgets-for-showInvoiceHeader (modelfunc)
 :description "This is the view/widget function for show InvoiceHeader entities.
   中文：发票总览页 widgets：面包屑 + 搜索框 + 顶栏工具菜单 + 'Create Invoice' 按钮 + 列表 +
   发票设置 offcanvas。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-vendor-breadcrumb)
		       (InvoiceHeader-search-html)
		       (:hr)))))
	  (widget2 (function (lambda ()
		     (invoices-actions-menu  nil))))
	  (widget3 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (:div :id "InvoiceHeaderlivesearchresult" 
			     (with-html-div-row
			       (with-html-div-col-3
				 (:a :href "/hhub/addcusttoinvoice" :role "button" :class "btn btn-lg btn-primary btn-block" (:i :class "fa-solid fa-plus") "&nbsp;&nbsp;Create Invoice"))
			       (with-html-div-col-6 "")
			       (with-html-div-col-3 :align "right"
				 (:span :class "badge bg-info" (:h5 (cl-who:str (format nil "~A" (length viewallmodel)))))))
			     (:hr)
			     (cl-who:str (RenderListViewHTML htmlview viewallmodel)))))))
	  (widget4 (function (lambda ()
		     (render-invoice-settings-menu)))))
      (list widget1 widget2 widget3 widget4))))

(defun create-widgets-for-updateInvoiceHeader (modelfunc)
:description "This is a widgets function for update InvoiceHeader entity.
   中文：更新发票后通用 redirect widgets。"
  (funcall #'create-widgets-for-genericredirect modelfunc))


(defmethod RenderListViewHTML ((htmlview InvoiceHeaderHTMLView) viewmodellist)
  :description "This is a HTML View rendering function for InvoiceHeader entities, which will display each InvoiceHeader entity in a row.
   中文：发票头表格渲染：发票号 / 日期 / 客户名 / 状态 / 金额 / 操作 6 列。"
  (when viewmodellist
    (display-as-table (list "Invoice Number" "Date" "Customer Name" "Status" "Total Value" "Action") viewmodellist 'display-InvoiceHeader-row)))

(defun create-model-for-searchInvoiceHeader ()
  :description "This is a model function for search InvoiceHeader entities/entity.
   中文：发票号搜索 model：把 livesearch 文本作为 :invnum 装到 InvoiceHeaderSearchRequestModel。"
  (let* ((search-clause (hunchentoot:parameter "InvoiceHeaderlivesearch"))
	 (vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (presenterobj (make-instance 'InvoiceHeaderPresenter))
	 (requestmodelobj (make-instance 'InvoiceHeaderSearchRequestModel
						 :invnum search-clause
						 :vendor vendor 
						 :company company))
	 (adapterobj (make-instance 'InvoiceHeaderAdapter))
	 (domainobjlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj domainobjlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'InvoiceHeaderHTMLView))
	 (params nil))

    (setf params (acons "company" (get-login-vendor-company) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-search-invoice-action" params 
      (function (lambda ()
	(values viewallmodel htmlview))))))

(defun create-widgets-for-searchInvoiceHeader (modelfunc)
  :description "This is a widget function for search InvoiceHeader entities.
   中文：搜索结果 widgets：'Create Invoice' 按钮 + 搜索结果数 + 列表表格。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (with-html-div-col-3
			   (:a :href "/hhub/addcusttoinvoice" :role "button" :class "btn btn-lg btn-primary btn-block" (:i :class "fa-solid fa-plus") "&nbsp;&nbsp;Create Invoice"))
			 (with-html-div-col-6 "")
			 (with-html-div-col-3 :align "right"
			   (:span :class "badge bg-info" (:h5 (cl-who:str (format nil "~A" (length viewallmodel)))))))
		       (:hr)
		       (cl-who:str (RenderListViewHTML htmlview viewallmodel)))))))
      (list widget1))))

(defun com-hhub-transaction-search-invoice-action ()
  :description "This is a MVC function to search action for InvoiceHeader entities/entity.
   中文：发票搜索动作：调 model + widgets，display-search-results-with-widgets 渲染输出。"
  (let* ((modelfunc (funcall #'create-model-for-searchInvoiceHeader))
	 (widgets (funcall #'create-widgets-for-searchInvoiceHeader modelfunc)))
    (display-search-results-with-widgets widgets)))

(defun create-model-for-updateInvoiceHeader ()
  :description "This is a model function for update InvoiceHeader entity.
   中文：发票头更新 model：从 hunchentoot 取所有字段（含 totalvalue 解析为浮点），
   生成 external-url（LiveLink），调 ProcessUpdateRequest。错误时写日志并抛 hhub-business-function-error。
   重定向到 /hhub/vproductsforinvoicepage?sessioninvkey=<invnum>。"
  (let* ((invnum (hunchentoot:parameter "invnum"))
	 (invdate (get-date-from-string (hunchentoot:parameter "invdate")))
	 (custid (hunchentoot:parameter "custid"))
	 (custname (hunchentoot:parameter "custname"))
	 (custaddr (hunchentoot:parameter "custaddr"))
	 (custgstin (hunchentoot:parameter "custgstin"))
	 (statecode (hunchentoot:parameter "statecode"))
	 (billaddr (hunchentoot:parameter "billaddr"))
	 (shipaddr (hunchentoot:parameter "shipaddr"))
	 (placeofsupply (hunchentoot:parameter "placeofsupply"))
	 (revcharge (hunchentoot:parameter "revcharge"))
	 (transmode (hunchentoot:parameter "transmode"))
	 (vnum (hunchentoot:parameter "vnum"))
	 (totalvalue (float (with-input-from-string (in (hunchentoot:parameter "totalvalue"))
		     (read in))))
	 (totalinwords (hunchentoot:parameter "totalinwords"))
	 (bankaccnum (hunchentoot:parameter "bankaccnum"))
	 (bankifsccode (hunchentoot:parameter "bankifsccode"))
	 (tnc (hunchentoot:parameter "tnc"))
	 (authsign (hunchentoot:parameter "authsign"))
	 (finyear (hunchentoot:parameter "finyear"))
	 (status (hunchentoot:parameter "status"))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (company (get-login-vendor-company)) ;; or get ABAC subject specific login company function. 
	 (customer (select-customer-by-id custid company))
	 (vendor (get-login-vendor))
	 (external-url (generate-invoice-ext-url invnum vendor company)) 
	 (requestmodel (make-instance 'InvoiceHeaderRequestModel
					 :invnum invnum
					 :invdate invdate
					 :customer customer
					 :custid custid
					 :custname custname
					 :custaddr custaddr
					 :custgstin custgstin
					 :statecode statecode
					 :billaddr billaddr
					 :shipaddr shipaddr
					 :placeofsupply placeofsupply
					 :revcharge revcharge
					 :transmode transmode
					 :vnum vnum
					 :totalvalue totalvalue
					 :totalinwords totalinwords
					 :bankaccnum bankaccnum
					 :bankifsccode bankifsccode
					 :tnc tnc
					 :authsign authsign
					 :finyear finyear
					 :external-url external-url
					 :status status
					 :vendor vendor
					 :company company))
	 (adapterobj (make-instance 'InvoiceHeaderAdapter))
	 (redirectlocation  (format nil "/hhub/vproductsforinvoicepage?sessioninvkey=~A" invnum))
	 (params nil))
    (setf params (acons "company" (get-login-vendor-company) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-update-invoice-action" params 
      (handler-case 
	  (let* ((domainobj (ProcessUpdateRequest adapterobj requestmodel)))
	    (when sessioninvoice
	      (setf (slot-value sessioninvoice 'invoiceheader) domainobj)
	      (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
	      (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht))	   
	    (function (lambda ()
	      (values redirectlocation domainobj))))

	(error (c)
	  (let ((exceptionstr (format nil  "Business Error:~A: ~a~%" (mysql-now) (getexceptionstr c))))
	    (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				    :direction :output
				    :if-exists :append
				    :if-does-not-exist :create)
	      (format stream "~A~A" exceptionstr (sb-debug:list-backtrace)))
	    ;; return the exception.
	    (error 'hhub-business-function-error :errstring exceptionstr)))))))


		 

(defun com-hhub-transaction-create-invoice-action()
  :description "This is a MVC function for create InvoiceHeader entity.
   中文：发票创建动作 PEP 入口（即'编辑发票头'页表单提交后）。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed. 
    (let ((url (with-mvc-redirect-ui  #'create-model-for-createInvoiceHeader #'create-widgets-for-createInvoiceHeader)))
      (format nil "~A" url))))

(defun create-widgets-for-createInvoiceHeader (modelfunc)
  :description "This is a create widget function for InvoiceHeader entity.
   中文：创建发票后通用 redirect widgets。"
  (funcall #'create-widgets-for-genericredirect modelfunc))

(defun create-model-for-createInvoiceHeader ()
  :description "This is a create model function for creating a InvoiceHeader entity.
   中文：发票创建 model：从 hunchentoot 取所有字段构造 RequestModel → ProcessCreateRequest 写库 →
   立即 ProcessReadRequest（按 context-id）回读以拿到 row-id 与 invnum → 写入会话 sessioninvoice。
   重定向到 Step 3 的商品选择页。错误时写日志并抛 hhub-business-function-error。"
  (let* ((invdate (get-date-from-string (hunchentoot:parameter "invdate")))
	 (company (get-login-vendor-company))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (context-id (hunchentoot:parameter "context-id"))
	 (custid (hunchentoot:parameter "custid"))
	 (customer (select-customer-by-id custid company))
	 (custaddr (hunchentoot:parameter "custaddr"))
	 (custgstin (hunchentoot:parameter "custgstin"))
	 (statecode (hunchentoot:parameter "statecode"))
	 (billaddr (hunchentoot:parameter "billaddr"))
	 (shipaddr (hunchentoot:parameter "shipaddr"))
	 (placeofsupply (hunchentoot:parameter "placeofsupply"))
	 (revcharge (hunchentoot:parameter "revcharge"))
	 (transmode (hunchentoot:parameter "transmode"))
	 (vnum (hunchentoot:parameter "vnum"))
	 (totalvalue (float (with-input-from-string (in (hunchentoot:parameter "totalvalue"))
		     (read in))))
	 (totalinwords (hunchentoot:parameter "totalinwords"))
	 (bankaccnum (hunchentoot:parameter "bankaccnum"))
	 (bankifsccode (hunchentoot:parameter "bankifsccode"))
	 (tnc (hunchentoot:parameter "tnc"))
	 (authsign (hunchentoot:parameter "authsign"))
	 (finyear (hunchentoot:parameter "finyear"))
	 (company (get-login-vendor-company)) ;; or get ABAC subject specific login company function.
	 (vendor (get-login-vendor))
	 (vname (get-login-vendor-name))
	 (requestmodel (make-instance 'InvoiceHeaderRequestModel
				      :context-id context-id
				      :invnum sessioninvkey
				      :invdate invdate
				      :customer customer
				      :vendor vendor
				      :custaddr custaddr
				      :custgstin custgstin
				      :statecode statecode
				      :billaddr billaddr
				      :shipaddr shipaddr
				      :placeofsupply placeofsupply
				      :revcharge revcharge
				      :transmode transmode
				      :vnum vnum
				      :totalvalue totalvalue
				      :totalinwords totalinwords
				      :bankaccnum bankaccnum
				      :bankifsccode bankifsccode
				      :tnc tnc
				      :authsign (if authsign authsign vname)
				      :finyear finyear
				      :external-url ""
				      :company company))
	 (adapterobj (make-instance 'InvoiceHeaderAdapter))
	 (hrequestmodel (make-instance 'InvoiceHeaderContextIDRequestModel
				      :context-id context-id
				      :company company))
	 (redirectlocation  (format nil "/hhub/vproductsforinvoicepage?sessioninvkey=~A"  sessioninvkey))
	 (params nil))
    (setf params (acons "company" company params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-create-invoice-action" params 
      (handler-case 
	  (let* ((createdobj (ProcessCreateRequest adapterobj requestmodel))
		 ;; as soon as we create a invoice header object, we would like to read it as well
		 ;; this will pull in the row-id from database and also the invoice number. 
		 (domainobj (ProcessReadRequest adapterobj hrequestmodel))
		 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
		 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht)))
	    ;;  (logiamhere (format nil "~A" sessioninvoices-ht))
	    ;; (logiamhere (format nil "~A" sessioninvoice))
	    ;;  (logiamhere (format nil "session invoice customer is ~A" (slot-value (slot-value sessioninvoice 'customer) 'name)))
	    ;; set the InvoiceHeader context for the invoice being created and add to the session invoice. 
	    (when (and createdobj sessioninvoice)
	      (setf (slot-value sessioninvoice 'invoiceheader) domainobj)
	      (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
	      (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht))
	    
	    (function (lambda ()
	      (values redirectlocation domainobj))))
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	(error (c)
	  (let ((exceptionstr (format nil  "Business Error:~A: ~a~%" (mysql-now) (getExceptionStr c))))
	    (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				    :direction :output
				    :if-exists :append
				    :if-does-not-exist :create)
	      (format stream "~A~A" exceptionstr (sb-debug:list-backtrace)))
	    ;; return the exception.
	    (error 'hhub-business-function-error :errstring exceptionstr)))))))





(defun com-hhub-transaction-create-InvoiceHeader-dialog (&optional domainobj)
  :description "This function creates a dialog to create InvoiceHeader entity.
   中文：创建/编辑发票头的弹窗表单。每个字段一个 input，invnum 为 readonly。
   action：无 domainobj 时 'createinvoiceaction'，否则 'updateinvoiceaction'。"
  (let* ((invnum  (if domainobj (slot-value domainobj 'invnum)))
	 (invdate  (if domainobj (get-date-string (slot-value domainobj 'invdate))))
	 (custaddr  (if domainobj (slot-value domainobj 'custaddr)))
	 (custgstin  (if domainobj (slot-value domainobj 'custgstin)))
	 (statecode  (if domainobj (slot-value domainobj 'statecode)))
	 (billaddr  (if domainobj (slot-value domainobj 'billaddr)))
	 (shipaddr  (if domainobj (slot-value domainobj 'shipaddr)))
	 (placeofsupply  (if domainobj (slot-value domainobj 'placeofsupply)))
	 (revcharge  (if domainobj (slot-value domainobj 'revcharge)))
	 (transmode  (if domainobj (slot-value domainobj 'transmode)))
	 (vnum  (if domainobj (slot-value domainobj 'vnum)))
	 (totalvalue  (if domainobj (slot-value domainobj 'totalvalue)))
	 (totalinwords  (if domainobj (slot-value domainobj 'totalinwords)))
	 (bankaccnum  (if domainobj (slot-value domainobj 'bankaccnum)))
	 (bankifsccode  (if domainobj (slot-value domainobj 'bankifsccode)))
	 (tnc  (if domainobj (slot-value domainobj 'tnc)))
	 (authsign  (if domainobj (slot-value domainobj 'authsign))))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form (format nil "form-addInvoiceHeader~A" invnum)  (if domainobj "updateinvoiceaction" "createinvoiceaction")
		    (:img :class "profile-img" :src "/img/logo.png" :alt "")
		    (:div :class "form-group"
			  (:input :class "form-control" :name "invnum" :maxlength "20"  :value  invnum :placeholder "Invoice Number (max 20 characters) " :type "text" :readonly t))
		    
		    (:div :class "form-group" :id "charcount")
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value invdate :placeholder "invdate"  :name "invdate" ))
		    
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value custaddr :placeholder "custaddr"  :name "custaddr" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value custgstin :placeholder "custgstin"  :name "custgstin" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value statecode :placeholder "statecode"  :name "statecode" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value billaddr :placeholder "billaddr"  :name "billaddr" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value shipaddr :placeholder "shipaddr"  :name "shipaddr" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value placeofsupply :placeholder "placeofsupply"  :name "placeofsupply" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value revcharge :placeholder "revcharge"  :name "revcharge" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value transmode :placeholder "transmode"  :name "transmode" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value vnum :placeholder "vnum"  :name "vnum" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value totalvalue :placeholder "totalvalue"  :name "totalvalue" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value totalinwords :placeholder "totalinwords"  :name "totalinwords" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value bankaccnum :placeholder "bankaccnum"  :name "bankaccnum" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value bankifsccode :placeholder "bankifsccode"  :name "bankifsccode" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value tnc :placeholder "tnc"  :name "tnc" ))
		    (:div :class "form-group"
			  (:input :class "form-control" :type "text" :value authsign :placeholder "authsign"  :name "authsign" ))
		    (:div :class "form-group"
			  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))


(defun vendor-create-update-customer-dialog (&optional customer)
  :description "This function creates a dialog to create InvoiceHeader entity.
   中文：卖家创建/更新客户的弹窗表单（在发票流程中按需创建客户）。
   description 系拷贝自 InvoiceHeader 模板（推测）。"
  (let* ((firstname (when customer (slot-value customer 'firstname)))
	 (lastname (when customer (slot-value customer 'lastname)))
	 (phone (when customer (slot-value customer 'phone )))
	 (email (when customer (slot-value customer 'email)))
	 (address (when customer (slot-value customer 'address))))
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-form-having-submit-event "form-vendorcreatecustomer"  "vendorcreatecustomer"
	(with-html-input-text "firstname" "First Name" "First Name" firstname  nil "Enter First Name" 1)
	(with-html-input-text "lastname" "Last Name" "Last Name" lastname  nil "Enter Last Name" 2)
	(with-html-input-text "phone" "Phone" "Phone" phone nil "Enter Phone Number" 3)
	(with-html-input-text "email" "Email" "Email" email nil "Enter Email" 4)
	(with-html-input-textarea "address" address  "Address" "Address" nil "Enter Address" 6 3)
	(:div :class "form-group"
	      (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))
		    

(defun com-hhub-transaction-vendor-create-customer-action ()
  "中文：卖家创建/更新客户的 PEP 入口（在发票流程中按需创建）。会话：with-vend-session-check。"
  (with-vend-session-check
    (with-mvc-redirect-ui #'create-model-for-vendorcreatecustomer #'create-widgets-for-vendorcreatecustomer)))

(defun create-model-for-vendorcreatecustomer ()
  "中文：创建/更新客户 model：
     - 按 phone 查客户，存在则更新字段；不存在则随机生成密码 + 盐 + 加密 → create-customer →
       create-wallet（卖家维度的钱包）。
   返回：闭包重定向到 /hhub/addcusttoinvoice 让卖家在选客户后继续创建发票。"
  (let* ((vendor (get-login-vendor))
	 (fname (hunchentoot:parameter "firstname"))
	 (lname (hunchentoot:parameter "lastname"))
	 (cphone (hunchentoot:parameter "phone"))
	 (cemail (hunchentoot:parameter "email"))
	 (caddress (hunchentoot:parameter "address"))
	 (cname (format nil "~A ~A" fname lname))
	 (company (get-login-vendor-company))
	 (customer (select-customer-by-phone cphone company))
	 (password (hhub-random-password 8))
	 (salt (createciphersalt))
	 (encryptedpass (check&encrypt password password salt))
	 (redirectlocation "/hhub/addcusttoinvoice"))
    ;; Create customer scenario
    (unless customer
      ;; Step 1 - Create a new customer 
      (create-customer cname caddress cphone cemail nil encryptedpass salt nil nil nil company)
      ;; Step 2 - create wallet for this new customer. 
      (let ((newcustomer (select-customer-by-phone cphone company)))
	(create-wallet newcustomer vendor company)))
    
    (when customer 
      (with-slots (firstname lastname name email phone address) customer
	(setf firstname fname)
	(setf lastname lname)
	(setf name cname)
	(setf email cemail)
	(setf phone cphone)
	(setf address caddress))
      (clsql:update-records-from-instance customer))
    (function (lambda ()
      redirectlocation))))
      
(defun create-widgets-for-vendorcreatecustomer (modelfunc)
  :description "This is a widgets function for create/update customer by vendor.
   中文：创建客户后通用 redirect widgets。"
  (funcall #'create-widgets-for-genericredirect modelfunc))
  
(defun display-InvoiceHeader-row (viewmodel &rest arguments)
  "中文：发票头列表单行渲染：发票号 / 日期 / 客户名 / 状态 / 总额 / Edit 链接。"
  (declare (ignore arguments ))
  (with-slots (invnum invdate customer status totalvalue) viewmodel
    (cl-who:with-html-output (*standard-output* nil)
      (:td  :height "10px" (cl-who:str  invnum))
      (:td  :height "10px" (cl-who:str (get-date-string invdate)))
      (:td  :height "10px" (cl-who:str (slot-value customer 'name)))
      (:td  :height "10px" (cl-who:str status))
      (:td  :height "10px" (cl-who:str totalvalue))
      (:td  :height "10px" (:a :href (format nil "/hhub/editinvoicepage?invnum=~A" invnum) :alt "Edit Invoice" (:i :class "fa-solid fa-pencil"))))))

	


(defun com-hhub-transaction-update-invoice-action()
  :description "This is the MVC function to update action for InvoiceHeader entity.
   中文：发票头更新动作 PEP 入口。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed. 
    (let ((url (with-mvc-redirect-ui  #'create-model-for-updateInvoiceHeader #'create-widgets-for-updateInvoiceHeader)))
      (format nil "~A" url))))


(defun com-hhub-transaction-edit-invoice-header-page()
  :description "This is the MVC function to show invoice header page.
   中文：编辑发票头页 PEP 入口（Step 2：填写发票头）。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed. 
    (with-mvc-ui-page "Edit Invoice" #'create-model-for-editinvoiceheaderpage #'create-widgets-for-editinvoiceheaderpage :role :vendor)))



(defun create-model-for-editinvoiceheaderpage ()
  "中文：编辑/新建发票头 model：
     1) 模式判断：若有 invnum → 走读取流程；否则构造空 InvoiceHeader（带 UUID context-id +
        默认 status=DRAFT、placeofsupply/statecode 取系统默认州、tnc/authsign 默认值）；
     2) 同步获取行项列表；
     3) 生成新的 SessionInvoice（含 customer / 行项 / GST 汇总）写入 hunchentoot 会话。
     sessioninvkey 在新建时为 NST000xxxxxx 随机串，编辑时复用 invnum。"
  (let* ((company (get-login-vendor-company))
	 (vendor (get-login-vendor))
	 (custid (hunchentoot:parameter "custid"))
	 (inum (hunchentoot:parameter "invnum"))
	 (mode (hunchentoot:parameter "mode"))
	 (finyear (current-year-string))
	 (adapter (make-instance 'InvoiceHeaderAdapter))
	 (itmadapter (make-instance 'InvoiceItemAdapter))
	 (customer (if custid (select-customer-by-id custid company)))
	 (custaddress (if customer (slot-value customer 'address)))
	 (busobj (make-instance 'InvoiceHeader
				:context-id (format nil "~A" (uuid:make-v1-uuid))
				:company company
				:vendor vendor
				:customer customer
				:custaddr custaddress 
				:finyear finyear
				:external-url ""
				:status "DRAFT"
				:placeofsupply *NSTGSTBUSINESSSTATE*
				:statecode *NSTGSTBUSINESSSTATE*
				:tnc *NSTGSTINVOICETERMS*
				:authsign (get-login-vendor-name)
				:revcharge "No"))
	 (requestmodel (make-instance 'InvoiceHeaderRequestModel
				      :invnum inum
				      :company company))
	 (invoiceobj (if inum (ProcessReadRequest adapter requestmodel) busobj))
	 (invitemreqmodel (make-instance 'InvoiceItemRequestModel
					 :invoiceheader invoiceobj
					 :company company))
	 (invitems (if inum (ProcessReadAllRequest itmadapter invitemreqmodel) '()))  
	 
	 ;; When we are creating a new invoice, we would like to save it in the session with context of
	 ;; customer, invoice header and invoice items. Here we start with adding the customer context. 
	 (sessioninvkey (if inum inum (format nil "NST000~A" (hhub-random-password 10))))
	 (newsessioninvoice (make-instance 'SessionInvoice))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht)))

    ;;(logiamhere (format nil "status of invoice header is ~A" (slot-value invoiceobj 'status)))
	   ;; set the customer context for the invoice being created and add to the session invoice. 
    (setf (slot-value newsessioninvoice 'customer) (customer invoiceobj))
    (setf (slot-value newsessioninvoice 'InvoiceItems) invitems)
    (setf (slot-value newsessioninvoice 'invoiceproducts) '())
    (setf (slot-value newsessioninvoice 'InvoiceHeader) invoiceobj)
    (setf (slot-value newsessioninvoice 'invoicetaxbreakdown) (generate-gst-tax-breakdown invoiceobj invitems))
    (setf (gethash sessioninvkey sessioninvoices-ht) newsessioninvoice)
    (setf (hunchentoot:session-value :session-invoices-ht) sessioninvoices-ht)
  (with-slots (context-id invnum invdate custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear external-url status customer ) invoiceobj
    (function (lambda()
      (values context-id invnum invdate custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear external-url status customer  mode sessioninvkey))))))


(defun create-widgets-for-editinvoiceheaderpage (modelfunc)
  "中文：编辑发票头页 widgets：4 列 panel 拼接 + 顶部动作菜单 + 提交表单（create/update 切换）。
   备注：widget5 在 let* 中赋值两次（第二次覆盖第一次）—— 推测：模板演化期间残留。"
  (multiple-value-bind (context-id invnum invdate custaddr custgstin statecode billaddr shipaddr placeofsupply revcharge transmode vnum totalvalue totalinwords bankaccnum bankifsccode tnc authsign finyear external-url status customer  mode sessioninvkey) (funcall modelfunc)
    (let* ((widget1 (editinvoicewidget-section1 sessioninvkey context-id invnum invdate  custgstin finyear status customer))
	   (widget2 (editinvoicewidget-section2 custaddr billaddr shipaddr))
	   (widget3 (editinvoicewidget-section3 statecode placeofsupply revcharge transmode vnum totalvalue totalinwords))
	   (widget4 (editinvoicewidget-section4 bankaccnum bankifsccode tnc authsign))
	   (widget5 (function (lambda ()
		      (invoice-header-actions-menu external-url status sessioninvkey customer))))  
	   (widget5 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(with-vendor-breadcrumb
			  (:li :class "breadcrumb-item" (:a :href "displayinvoices" "Invoices"))
			  (:li :class "breadcrumb-item" (:a :href "addcusttoinvoice" "Select Customer")))
			(funcall widget5)
			(:span "Create Invoice - Step 2: ")
			(:span (cl-who:str sessioninvkey))
			(:h2 "Fill Invoice Details For")
			(with-html-form-having-submit-event "form-updateinvoiceheader"  (if (equal mode "create") "createinvoiceaction" "updateinvoiceaction")
			  (with-html-div-row
			    (with-html-div-col-3
			      (funcall widget1))
			    (with-html-div-col-3
			      (funcall widget2))
			    (with-html-div-col-3
			      (funcall widget3))
			    (with-html-div-col-3
			      (funcall widget4)))))))))
      (list widget5))))


(defun editinvoicewidget-section1 (sessioninvkey context-id invnum invdate  custgstin finyear status customer)
  "中文：编辑发票头页 第 1 列：财年下拉 / 状态下拉（DRAFT/PENDINGPAYMENT/PAID/SHIPPED/CANCELLED/REFUNDED）/
   发票号（只读）/ 发票日（jQuery datepicker）/ 客户 GST 编号。底部嵌入 datepicker JS。"
  (function (lambda ()
    (let ((charcountid1 (format nil "idchcount~A" (hhub-random-password 3)))
	  (idinvoicedate (format nil "idinvoicedate~A" (gensym)))
	  (finyear-ht (make-hash-table :test 'equal))
	  (status-ht (make-hash-table :test 'equal)))
      
      (setf (gethash (current-year-string--) finyear-ht) (current-year-string--))
      (setf (gethash (current-year-string) finyear-ht) (current-year-string))
      (setf (gethash (current-year-string++) finyear-ht) (current-year-string++))
      (setf (gethash "DRAFT" status-ht) "DRAFT")
      (setf (gethash "PENDINGPAYMENT" status-ht) "PENDINGPAYMENT")
      (setf (gethash "PAID" status-ht) "PAID")
      (setf (gethash "SHIPPED" status-ht) "SHIPPED")
      (setf (gethash "CANCELLED" status-ht) "CANCELLED")
      (setf (gethash "REFUNDED" status-ht) "REFUNDED")
      (cl-who:with-html-output (*standard-output* nil)
	(:div :class "form-group"
	      (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
	      (with-html-input-text-hidden "context-id" context-id)
	      (with-html-input-text-hidden "custid" (cl-who:str (slot-value customer 'row-id)))
	      (with-html-input-text-hidden "custname" (cl-who:str (slot-value customer 'name)))
	      (:h3 (:span (cl-who:str (slot-value customer 'name))))
	      (:h3 (:span (cl-who:str (slot-value customer 'phone)))))
	(:div :class "form-group"
	    (:label :for "finyear" "Financial Year")
	    (with-html-dropdown "finyear" finyear-ht finyear))
	(:div :class "form-group"
	      (:label :for "status" "Status")
	      (with-html-dropdown "status" status-ht status))
	(:div :class "form-group"
	      (:label :for "invnum" "Invoice Number")
	      (:input :class "form-control" :name "invnum" :maxlength "20"  :value  invnum :placeholder "Invoice Number (max 20 characters) " :type "text" :readonly t))
	(:div :class "form-group"
	      (:label :for idinvoicedate "Invoice Date - Click To Change" )
	      (:input :class "form-control" :name "invdate" :id idinvoicedate :placeholder  "Invoice Date"  :type "text" :value (get-date-string invdate)))
	
	(:div :class "form-group"
	      (:label :for "idcustgstin" "Customer GST Number")
	      (:input :id "idcustgstin" :class "form-control" :type "text" :value custgstin :onkeyup (format nil "countChar(~A.id, this, 15)" charcountid1) :placeholder "Customer GST Number"  :name "custgstin" )
	      (:div :class "form-group" :id charcountid1))
	(:script (cl-who:str (format nil "$(document).ready(
        function() {    
        $('#~A').datepicker({dateFormat: 'dd/mm/yy', minDate: 0} ).attr('readonly', 'true'); 
        }
);" idinvoicedate))))))))

(defun editinvoicewidget-section2 (custaddr billaddr shipaddr)
  "中文：编辑发票头页 第 2 列：客户地址 / 账单地址 / 收货地址 三个 textarea（200 字符限制 + 字数统计）。"
  (function (lambda ()
    (let ((charcountid1 (format nil "idchcount~A" (hhub-random-password 3)))
	  (charcountid2 (format nil "idchcount~A" (hhub-random-password 3)))
	  (charcountid3 (format nil "idchcount~A" (hhub-random-password 3))))
      (cl-who:with-html-output (*standard-output* nil)
	(:div :class "form-group"
	      (:label :for "custaddr" "Customer Address")
	      (:textarea :class "form-control" :name "custaddr"  :placeholder "Enter Address ( max 200 characters) "  :rows "3" :onkeyup (format nil "countChar(~A.id, this, 200)" charcountid1) (cl-who:str (format nil "~A" custaddr)))
	      (:div :class "form-group" :id charcountid1))
	(:div :class "form-group"
	      (:label :for "billaddr" "Billing Address")
	      (:textarea :class "form-control" :name "billaddr"  :placeholder "Enter Billing Address ( max 200 characters) "  :rows "3" :onkeyup (format nil "countChar(~A.id, this, 200)" charcountid2) (cl-who:str (format nil "~A" billaddr)))
	      (:div :class "form-group" :id charcountid2 ))
	(:div :class "form-group"
	      (:label :for "shipaddr" "Shipping Address")
	      (:textarea :class "form-control" :name "shipaddr"  :placeholder "Enter Shipping Address ( max 200 characters) "  :rows "3" :onkeyup (format nil "countChar(~A.id, this, 200)" charcountid3) (cl-who:str (format nil "~A" shipaddr)))
	      (:div :class "form-group" :id charcountid3)))))))
  

(defun editinvoicewidget-section3 (statecode placeofsupply revcharge transmode vnum totalvalue totalinwords)
  "中文：编辑发票头页 第 3 列：州 / 供应地（GST_STATECODES_HT 下拉）/ 反向计税 Yes/No /
   运输方式 NA/Road/Rail/Air/Ship / 车辆号 / Total（隐藏字段）/ 大写金额（隐藏字段）。
   placeofsupply-ht 在函数内构造但未使用 —— 推测：早期实现遗留。"
  (function (lambda ()
    (let ((revcharge-ht (make-hash-table :test 'equal))
	  (transmode-ht (make-hash-table :test 'equal))
	  (placeofsupply-ht (make-hash-table :test 'equal)))
      
      (setf (gethash "Yes" revcharge-ht) "Yes") 
      (setf (gethash "No" revcharge-ht) "No")
      (setf (gethash "NA" transmode-ht) "Not Applicable")
      (setf (gethash "Road" transmode-ht) "Road")
      (setf (gethash "Rail" transmode-ht) "Rail")
      (setf (gethash "Air" transmode-ht) "Air")
      (setf (gethash "Ship/Waterways" transmode-ht) "Ship/Waterways")
      (setf (gethash "INTRASTATE" placeofsupply-ht) "Intra-State (CGST + SGST)")
      (setf (gethash "INTERSTATE"  placeofsupply-ht) "Inter-State (IGST)")

      (unless statecode (setf statecode *NSTGSTBUSINESSSTATE*))
      
      (cl-who:with-html-output (*standard-output* nil)
	(:div :class "form-group"
	      (:label :for "statecode" "Select State")
	      (with-html-dropdown "statecode" *NSTGSTSTATECODES-HT* statecode))
	(:div :class "form-group"
	      (:label :for "placeofsupply" "Place Of Supply")
	      (with-html-dropdown "placeofsupply" *NSTGSTSTATECODES-HT* placeofsupply))
	;;(with-html-dropdown "placeofsupply" placeofsupply-ht placeofsupply))
	(:div :class "form-group"
	      (:label :for "revcharge" "Reverse Charge")
	      (with-html-dropdown "revcharge" revcharge-ht revcharge))
	(:div :class "form-group"
	      (:label :for "transmode" "Transport Mode")
	      (with-html-dropdown "transmode" transmode-ht transmode))
	(:div :class "form-group"
	      (:label :for "vnum" "Vehicle Number")
	      (:input :class "form-control" :type "text" :value vnum :placeholder "Vehicle Number"  :name "vnum" ))
	(:div :class "form-group" :style "display:none;"
	      (:label :for "totalvalue" "Total Value")
	      (:input :class "form-control" :type "text" :value totalvalue :placeholder "Total Value"  :name "totalvalue" ))
	(:div :class "form-group" :style "display:none;"
	      (:label :for "totalinwords" "Total In Words")
	      (:input :class "form-control" :type "text" :value totalinwords :placeholder "Total In Words"  :name "totalinwords" )))))))

(defun editinvoicewidget-section4 (bankaccnum bankifsccode tnc authsign)
  "中文：编辑发票头页 第 4 列：'NEXT' 提交按钮 / 银行账号 / IFSC / 发票条款（textarea 1000 字符）/
   授权签章。"
  (function (lambda ()
    (let ((charcountid1 (format nil "idchcount~A" (hhub-random-password 3))))
      (cl-who:with-html-output (*standard-output* nil)
	(:div :class "form-group"
	    (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "NEXT"))
	(:div :class "form-group"
	      (:label :for "bankaccnum" "Bank Account Number")
	      (:input :class "form-control" :type "text" :value bankaccnum :placeholder "bankaccnum"  :name "bankaccnum" ))
	(:div :class "form-group"
	      (:label :for "bankifsccode" "Bank IFSC Code")
	      (:input :class "form-control" :type "text" :value bankifsccode :placeholder "bankifsccode"  :name "bankifsccode" ))
	(:div :class "form-group"
	      (:label :for "tnc" "Invoice Terms")
	      (:textarea :class "form-control" :name "tnc"  :placeholder "Enter Invoice Terms (Max 200 characters) "  :rows "3" :onkeyup (format nil "countChar(~A.id, this, 1000)" charcountid1) (cl-who:str (format nil "~A" tnc)))
	      (:div :class "form-group" :id charcountid1 ))
        (:div :class "form-group"
	    (:label :for "invnum" "Authorised Signatory")
	    (:input :class "form-control" :type "text" :value authsign :placeholder "authsign"  :name "authsign" )))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
