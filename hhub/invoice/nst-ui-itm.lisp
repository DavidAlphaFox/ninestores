;;; nst-ui-itm.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

  ;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：invoice 发票 —— 行项 UI / 控制器（新 nst-* DDD/Hexagonal）
;;;; 分层：UI（控制器 + CL-WHO 模板 + Presenter 装配）
;;;; 文件：hhub/invoice/nst-ui-itm.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：发票行项的 Web UI 入口 + 一组 PEP 事务控制器：
;;;;   - 列表/搜索：com-hhub-transaction-show-InvoiceItem-page /
;;;;     com-hhub-transaction-search-InvoiceItem-action
;;;;   - 编辑：com-hhub-transaction-update-invoiceitem-action（含 GST 实时重算）
;;;;   - 创建：com-hhub-transaction-create-InvoiceItem-action（占位，model 函数空体）
;;;;   - 删除：com-hhub-transaction-delete-invoiceitem-action
;;;;   - 编辑/删除弹窗 HTML：edit-invoiceitem-dialog / delete-invoiceitem-dialog
;;;;   - 行渲染：display-invoice-item-row / -row-public（CL-WHO） +
;;;;     generate-invoice-items-rows / -public（基于 ROW_SNIPPET 模板）
;;;;   - 模板填充：invoicetemplatefillitemrows / -public（PDF/HTML 发票模板用）
;;;;
;;;; 主要导出：
;;;;   InvoiceItem-search-html
;;;;   com-hhub-transaction-show-InvoiceItem-page / -search-InvoiceItem-action /
;;;;   com-hhub-transaction-update-invoiceitem-action /
;;;;   com-hhub-transaction-create-InvoiceItem-action /
;;;;   com-hhub-transaction-delete-invoiceitem-action
;;;;   create-model-for-showInvoiceItem / -searchInvoiceItem /
;;;;   -updateInvoiceItem / -deleteinvoiceitem / -createInvoiceItem
;;;;   create-widgets-for-showInvoiceItem / -searchInvoiceItem / -createInvoiceItem
;;;;   edit-invoiceitem-dialog / delete-invoiceitem-dialog
;;;;   display-invoice-item-row / display-invoice-item-row-public
;;;;   generate-invoice-items-rows / -public
;;;;   invoicetemplatefillitemrows / invoicetemplatefillitemrowspublic
;;;;   RenderListViewHTML（InvoiceItemHTMLView 特化方法 —— 文件中存在两个同签名定义）
;;;;
;;;; 关联：
;;;;   上游使用方：客户/卖家发票后台路由
;;;;   下游依赖：invoice/nst-bl-itm.lisp、invoice/nst-bl-ihd.lisp（会话发票对象）、
;;;;             core PEP 宏 with-hhub-transaction、product BL（GST 速率取值）
;;;; ============================================================================

(in-package :nstores)


(defun InvoiceItem-search-html ()
  :description "This will create a html search box widget.
   中文：渲染顶部搜索框（带 keyup 触发的 livesearch）。
   表单 action='searchInvoiceItemaction'，结果 div 为 #InvoiceItemlivesearchresult。"
  (cl-who:with-html-output (*standard-output* nil)
    (:div :class "row"
	  (:div :id "custom-search-input"
		(:div :class "input-group col-xs-12 col-sm-6 col-md-6 col-lg-6"
		      (with-html-search-form "idsyssearchInvoiceItem" "syssearchInvoiceItem" "idInvoiceItemlivesearch" "InvoiceItemlivesearch" "searchInvoiceItemaction" "onkeyupsearchform1event();" "Search for an InvoiceItem"
			(submitsearchform1event-js "#idInvoiceItemlivesearch" "#InvoiceItemlivesearchresult")))))))

(defun com-hhub-transaction-show-InvoiceItem-page ()
  :description "This is a show list page for all the InvoiceItem entities.
   中文：发票行项总览页 PEP 入口。
   会话：with-vend-session-check。事务名：com-hhub-transaction-InvoiceItem-page。"
  (with-vend-session-check ;; delete if not needed. 
    (with-mvc-ui-page "InvoiceItem" #'create-model-for-showInvoiceItem #'create-widgets-for-showInvoiceItem :role :vendor))) ;; keep only one role, delete reset. 

(defun create-model-for-showInvoiceItem ()
  :description "This is a model function which will create a model to show InvoiceItem entities.
   中文：列表页 model：构造 RequestModel/Adapter/Presenter，processreadallrequest 取所有行项 →
   processresponselist → CreateAllViewModel；最后包到 with-hhub-transaction PEP。"
  (let* ((company (get-login-company))
	 (username (get-login-user-name))
	 (presenterobj (make-instance 'InvoiceItemPresenter))
	 (requestmodelobj (make-instance 'InvoiceItemRequestModel
					 :company company))
	 (adapterobj (make-instance 'InvoiceItemAdapter))
	 (objlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj objlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'InvoiceItemHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-InvoiceItem-page" params 
      (function (lambda ()
	(values viewallmodel htmlview username))))))

(defun create-widgets-for-showInvoiceItem (modelfunc)
 :description "This is the view/widget function for show InvoiceItem entities.
   中文：列表页 widgets：面包屑 + 搜索框 + 'Create Invoice' 入口 + 行项表格 + 表单提交 JS。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (with-vendor-breadcrumb)
		       (InvoiceItem-search-html)
			 (:hr)))))
	  (widget2 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (:h4 "Showing records for InvoiceItem."))
		       (:div :id "InvoiceItemlivesearchresult" 
			     (:div :class "row"
				   (:div :class"col-xs-6"
					 (:a :href "/hhub/addcusttoinvoice" (:i :class "fa-solid fa-plus") "&nbsp;&nbsp;Create Invoice"))
				   (:div :class "col-xs-6" :align "right" 
					 (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
			     (:hr)
			     (cl-who:str (RenderListViewHTML htmlview viewallmodel)))))))
	  (widget3 (function (lambda ()
		     (submitformevent-js "#InvoiceItemlivesearchresult")))))
      (list widget1 widget2 widget3))))



(defmethod RenderListViewHTML ((htmlview InvoiceItemHTMLView) viewmodellist)
  :description "This is a HTML View rendering function for InvoiceItem entities, which will display each InvoiceItem entity in a row.
   中文：列表渲染 V1（粗粒度，列出全部内部字段）。本文件后段还有第二个同签名 defmethod 定义，
   编译时后定义会覆盖此实现。"
  (when viewmodellist
    (display-as-table (list "InvoiceHeader" "prdid" "prddesc" "hsncode" "qty" "uom" "price" "discount" "taxablevalue" "cgstrate" "cgstamt" "sgstrate" "sgstamt" "igstrate" "igstamt" "totalitemval" "company" "fieldR" "fieldS") viewmodellist 'display-InvoiceItem-row)))

(defun create-model-for-searchInvoiceItem ()
  :description "This is a model function for search InvoiceItem entities/entity.
   中文：搜索 model：把 livesearch 框文本作为 :field1 装到 InvoiceItemSearchRequestModel，
   走同样的 read-all + presenter 装配链路。"
  (let* ((search-clause (hunchentoot:parameter "InvoiceItemlivesearch"))
	 (company (get-login-company))
	 (presenterobj (make-instance 'InvoiceItemPresenter))
	 (requestmodelobj (make-instance 'InvoiceItemSearchRequestModel
						 :field1 search-clause
						 :company company))
	 (adapterobj (make-instance 'InvoiceItemAdapter))
	 (domainobjlst (processreadallrequest adapterobj requestmodelobj))
	 (responsemodellist (processresponselist adapterobj domainobjlst))
	 (viewallmodel (CreateAllViewModel presenterobj responsemodellist))
	 (htmlview (make-instance 'InvoiceItemHTMLView))
	 (params nil))

    (setf params (acons "username" (get-login-user-name) params))
    (setf params (acons "rolename" (get-login-user-role-name) params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-search-InvoiceItem-action" params 
      (function (lambda ()
	(values viewallmodel htmlview))))))



(defun com-hhub-transaction-search-InvoiceItem-action ()
  :description "This is a MVC function to search action for InvoiceItem entities/entity.
   中文：搜索动作：直接调 model + widgets 拼字符串返回（livesearch 走 AJAX）。
   备注：未走 with-vend-session-check —— 由 PEP 在 model 内 with-hhub-transaction 校验。"
  (let* ((modelfunc (funcall #'create-model-for-searchInvoiceItem))
	 (widgets (funcall #'create-widgets-for-searchInvoiceItem modelfunc)))
    (cl-who:with-html-output-to-string (*standard-output* nil :prologue t :indent t)
      (loop for widget in widgets do
	(cl-who:str (funcall widget))))))

(defun create-model-for-updateInvoiceItem ()
  :description "This is a model function for update InvoiceItem entity.
   中文：编辑行项 model：
     1) 从 hunchentoot 取 prd-id / qty / price / discount；从 session 取当前会话发票
        (sessioninvoices-ht[sessioninvkey]) 与其 InvoiceHeader / InvoiceItems / taxbreakdown。
     2) 用商品 GST 速率 + 发票头的 placeofsupply vs statecode 判断 intra/interstate，
        重算 taxablevalue / cgstamt / sgstamt / igstamt / totalitemval。
     3) 构造 InvoiceItemRequestModel（status='CONFIRMED'）→ ProcessUpdateRequest
        → 用 update-item-in-tax-breakdown 同步会话内的税额汇总。
   返回：闭包 (values redirectlocation domainobj)，redirect 回 vshowinvoiceconfirmpage。"
  (let* ((company (get-login-vendor-company))
	 (prd-id (parse-integer (hunchentoot:parameter "prd-id")))
	 (prdqty (parse-integer (hunchentoot:parameter "qty")))
	 (productlist (hhub-get-cached-vendor-products))
	 (product (search-item-in-list 'row-id prd-id productlist))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (sessioninvitems (slot-value sessioninvoice 'InvoiceItems))
	 (old-invoiceitem (find-invoice-item prd-id sessioninvitems))
	 (sessioninvtaxbreakdown (slot-value sessioninvoice 'invoicetaxbreakdown))
	 (price (float (with-input-from-string (in (hunchentoot:parameter "price"))
		   (read in))))
	 (discount (float (with-input-from-string (in (hunchentoot:parameter "discount"))
			    (read in))))
	 (taxablevalue (- (* prdqty price) (if discount (/ (* prdqty price discount) 100) 0.00)))
	 (hsncode (slot-value product 'hsn-code))
	 (gstvalues (get-gstvalues-for-product product))
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
	 (requestmodel (make-instance 'InvoiceItemRequestModel
					 :InvoiceHeader sessioninvheader
					 :prd-id prd-id
					 :qty prdqty
					 :price price
					 :hsncode hsncode
					 :discount discount
					 :taxablevalue taxablevalue
					 :cgstamt cgstamt
					 :sgstamt sgstamt
					 :igstamt igstamt
					 :totalitemval totalitemval
					 :status "CONFIRMED"
					 :company company))
	 (adapterobj (make-instance 'InvoiceItemAdapter))
	 (redirectlocation  (format nil "/hhub/vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey))
	 (params nil))
    (setf params (acons "company" company params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-update-invoiceitem-action" params 
     ;; (handler-case 
      (let ((domainobj (if (> prdqty 0 ) (ProcessUpdateRequest adapterobj requestmodel))))
	(update-item-in-tax-breakdown sessioninvtaxbreakdown old-invoiceitem domainobj)
	(function (lambda ()
	  (values redirectlocation domainobj)))))))
	;;(error (c)
	 ;;(error 'hhub-business-function-error :errstring (format t "got an exception ~A" c)))))))


(defun create-model-for-createInvoiceItem ()
  :description "This is a create model function for creating a InvoiceItem entity.
   中文：占位空函数 —— 创建行项的 model 尚未实现（推测：当前业务直接由发票头组装阶段批量插入）。"
  )

(defun edit-invoiceitem-dialog (domainobj sessioninvkey)
  :description "This function creates a dialog to create InvoiceItem entity.
   中文：编辑/创建行项的弹窗表单（只读 prddesc + 可改 qty/price/discount）。
   action 在已有 domainobj 时为 updateInvoiceItemaction，否则 createInvoiceItemaction。"
  (let* ((prdid  (if domainobj (slot-value domainobj 'prd-id)))
	 (prddesc  (if domainobj (slot-value domainobj 'prddesc)))
	 (qty  (if domainobj (slot-value domainobj 'qty)))
	 (price  (if domainobj (slot-value domainobj 'price)))
	 (discount  (if domainobj (slot-value domainobj 'discount)))
	 (row-id (if domainobj (slot-value domainobj 'row-id)))
	 (form-name (format nil "form-editInvoiceItem~A" row-id))
	 (logopath (format nil "~A/img/logo.png" *siteurl*)))
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row
	(with-html-div-col-12
	  (with-html-form form-name (if domainobj "updateInvoiceItemaction" "createInvoiceItemaction")
	    (:img :class "profile-img" :src logopath :alt "Logo")
	    (with-html-input-text-hidden "prd-id" prdid)
	    (with-html-input-text-hidden "row-id" row-id)
	    (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
	    (with-html-input-text-readonly "prddesc" "Product Description" "Product Description"  prddesc nil nil 0)
	    (with-html-input-number "qty" "Quantity" "Quantity" qty 1 100 T "Enter/Update Quantity" 1)
	    (with-html-input-text "price" "Price" "Price" price T "Enter/Update Price" 2)
	    (with-html-input-text "discount" "Discount%" "Discount%" discount T "Enter/Update Discount" 3)
	    (:div :class "form-group"
		  (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Save"))))))))


(defun delete-invoiceitem-dialog (domainobj sessioninvkey)
  :description "This function creates a dialog to create InvoiceItem entity.
   中文：删除行项的弹窗确认（只读展示 prddesc / qty + 红色 DELETE 按钮）。
   action='deleteinvoiceitemaction'。description 系拷贝自 edit 模板（推测）。"
  (let* ((prddesc  (if domainobj (slot-value domainobj 'prddesc)))
	 (qty  (if domainobj (slot-value domainobj 'qty)))
	 (row-id (if domainobj (slot-value domainobj 'row-id)))
	 (prdid  (if domainobj (slot-value domainobj 'prd-id))))
    (cl-who:with-html-output (*standard-output* nil)
      (:div :class "row" 
	    (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		  (with-html-form (format nil "form-addInvoiceItem~A" row-id) "deleteinvoiceitemaction"
		    (:img :class "profile-img" :src "/img/logo.png" :alt "")
		    (with-html-input-text-hidden "prd-id" prdid)
		    (with-html-input-text-hidden "row-id" row-id)
		    (with-html-input-text-hidden "sessioninvkey" sessioninvkey)
		    (with-html-input-text-readonly "prddesc" "Description" "Description" prddesc NIL "" 1)
		    (with-html-input-text-readonly "qty" "Quantity" "Quantity" qty NIL "" 2)
		    (:div :class "form-group"
			  (:button :class "btn btn-lg btn-danger btn-block" :type "submit" "DELETE INVOICE ITEM!"))))))))




(defun create-widgets-for-createInvoiceItem (modelfunc)
  :description "This is a create widget function for InvoiceItem entity.
   中文：复用通用的 redirect widgets。"
  (funcall #'create-widgets-for-genericredirect modelfunc))




(defun create-widgets-for-searchInvoiceItem (modelfunc)
  :description "This is a widget function for search InvoiceItem entities.
   中文：搜索结果 widgets：'Add InvoiceItem' 按钮 + Bootstrap modal 编辑弹窗 + 行项表格。"
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (:div :class "row"
			     (:div :class"col-xs-6"
				   (:button :type "button" :class "btn btn-primary" :data-bs-toggle "modal" :data-bs-target "#editInvoiceItem-modal" "Add InvoiceItem")
				   (modal-dialog-v2 "editInvoiceItem-modal" "Add/Edit InvoiceItem" (com-hhub-transaction-create-InvoiceItem-dialog)))
			     (:div :class "col-xs-6" :align "right" 
				   (:span :class "badge" (cl-who:str (format nil "~A" (length viewallmodel))))))
		       (:hr)
		       (RenderListViewHTML htmlview viewallmodel))))))
      (list widget1))))


(defmethod RenderListViewHTML ((htmlview InvoiceItemHTMLView) viewmodellist)
  :description "This is a HTML View rendering function for InvoiceHeader entities, which will display each InvoiceHeader entity in a row.
   中文：列表渲染 V2（更紧凑的发票常用列）。同签名 method 的第二次定义会覆盖第一次。
   备注：description 拷贝自 InvoiceHeader 模板（推测）。"
  (when viewmodellist
    (display-as-table (list "Product" "HSN Code" "UOM" "Qty" "Rate" "Amount" "Less:Discount" "Taxable Value" "CGST" "SGST" "IGST" "Total") viewmodellist 'display-InvoiceItem-row)))



(defun display-invoice-item-row (invitem invoicepaid-p sessioninvkey)
  "中文：发票行项 <td> 渲染。invoicepaid-p=NIL 时附加 编辑/删除 modal 触发按钮（带 .no-print 类）。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-slots (prd-id prddesc hsncode qty uom price discount  taxablevalue  cgstamt  sgstamt  igstamt totalitemval) invitem
      (cl-who:htm
       (:td :height "10px" (cl-who:str prddesc))
       (:td :height "10px" (cl-who:str hsncode))
       (:td :height "10px" (cl-who:str uom))
       (:td :height "10px" (cl-who:str qty))
       (:td :height "10px" (cl-who:str price))
       (:td :height "10px" (cl-who:str discount))
       (:td :height "10px" (cl-who:str taxablevalue))
       (:td :height "10px" (cl-who:str cgstamt))
       (:td :height "10px" (cl-who:str sgstamt))
       (:td :height "10px" (cl-who:str igstamt))
       (:td :height "10px" (cl-who:str totalitemval))
       (unless invoicepaid-p
	 (cl-who:htm
	  (:td :height "10px"
	       (:a :class "no-print" :data-bs-toggle "modal" :data-bs-target (format nil "#editInvoiceItem-modal~A" prd-id) (:i :class "fa-solid fa-pencil") "&nbsp;&nbsp;")
	       (modal-dialog-v2 (format nil "editInvoiceItem-modal~A" prd-id) "Add/Edit InvoiceItem" (edit-invoiceitem-dialog invitem sessioninvkey))
	       (:a :class "no-print" :data-bs-toggle "modal" :data-bs-target (format nil "#deleteInvoiceItem-modal~A" prd-id) (:i :class "fa-solid fa-trash-can"))
	       (modal-dialog-v2 (format nil "deleteInvoiceItem-modal~A" prd-id) "Delete InvoiceItem" (delete-invoiceitem-dialog invitem sessioninvkey)))))))))

(defun display-invoice-item-row-public (invitem)
  "中文：公开（无登录）发票行项渲染：仅展示数据 <td>，不输出编辑/删除按钮。
   用于 LiveLink / 公开链接发票预览。"
  (cl-who:with-html-output (*standard-output* nil)
    (with-slots (prd-id prddesc hsncode qty uom price discount  taxablevalue  cgstamt  sgstamt  igstamt totalitemval) invitem
      (cl-who:htm
       (:td :height "10px" (cl-who:str prddesc))
       (:td :height "10px" (cl-who:str hsncode))
       (:td :height "10px" (cl-who:str uom))
       (:td :height "10px" (cl-who:str qty))
       (:td :height "10px" (cl-who:str price))
       (:td :height "10px" (cl-who:str discount))
       (:td :height "10px" (cl-who:str taxablevalue))
       (:td :height "10px" (cl-who:str cgstamt))
       (:td :height "10px" (cl-who:str sgstamt))
       (:td :height "10px" (cl-who:str igstamt))
       (:td :height "10px" (cl-who:str totalitemval))))))



(defun generate-invoice-items-rows (items-list invoicepaid-p sessioninvkey raw-template)
  "Extracts the row sub-template and repeats it for every item.
   中文：基于发票模板（HTML 字符串）的行重复机制：从 raw-template 中匹配
   <!--ROW_SNIPPET_BEGIN--> ... <!--ROW_SNIPPET_END--> 之间的子模板，
   逐行做 %srno% / %row prddesc% / %row hsncode% / ... 占位符替换；
   未支付时再注入 %row actions% 的编辑/删除 modal HTML。
   返回：闭包，调用后产出整段 HTML 字符串。
   错误：模板缺标记时直接 (error ...)。"
  (let* ((row-regex "(?s)<!--ROW_SNIPPET_BEGIN-->(.*?)<!--ROW_SNIPPET_END-->")
         (row-sub-template (cl-ppcre:register-groups-bind (snippet) (row-regex raw-template) snippet)))
    (if (not row-sub-template)
        (error "Could not find <!--ROW_SNIPPET_BEGIN--> markers in the template.")
	(function (lambda ()
	  (cl-who:with-html-output-to-string (*standard-output* nil)
            (loop for invitem in items-list 
                  for count from 1 do
		    (let ((processed-row row-sub-template))
		      (with-slots (prd-id prddesc hsncode qty uom price discount  taxablevalue  cgstamt  sgstamt  igstamt totalitemval) invitem
			;; Serial number
			(setf processed-row (cl-ppcre:regex-replace-all "%srno%" processed-row (format nil "~A" count)))
			;; Use your specific %row ...% format
			(setf processed-row (cl-ppcre:regex-replace-all "%row prddesc%" processed-row (or prddesc "")))
			(setf processed-row (cl-ppcre:regex-replace-all "%row hsncode%" processed-row (or hsncode "")))
			(setf processed-row (cl-ppcre:regex-replace-all "%row uom%" processed-row (or uom "")))
			(setf processed-row (cl-ppcre:regex-replace-all "%row qty%" processed-row (format nil "~A" qty)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row price%" processed-row (format nil "~,2F" price)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row discount%" processed-row (format nil "~,2F" (or discount 0))))
			(setf processed-row (cl-ppcre:regex-replace-all "%row taxable%" processed-row (format nil "~,2F" taxablevalue)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row cgst%" processed-row (format nil "~,2F" cgstamt)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row sgst%" processed-row (format nil "~,2F" sgstamt)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row igst%" processed-row (format nil "~,2F" igstamt)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row totalitemval%" processed-row (format nil "~,2F" totalitemval)))
			(unless invoicepaid-p
			  (setf processed-row (cl-ppcre:regex-replace-all "%row actions%" processed-row 
									  (cl-who:with-html-output-to-string (*standard-output* nil)
									    (:a :class "no-print" :data-bs-toggle "modal" :data-bs-target (format nil "#editInvoiceItem-modal~A" prd-id) (:i :class "fa-solid fa-pencil") "&nbsp;&nbsp;")
									    (modal-dialog-v2 (format nil "editInvoiceItem-modal~A" prd-id) "Add/Edit InvoiceItem" (edit-invoiceitem-dialog invitem sessioninvkey))
									    (:a :class "no-print" :data-bs-toggle "modal" :data-bs-target (format nil "#deleteInvoiceItem-modal~A" prd-id) (:i :class "fa-solid fa-trash-can") "&nbsp;&nbsp;")
									    (modal-dialog-v2 (format nil "deleteInvoiceItem-modal~A" prd-id) "Delete InvoiceItem" (delete-invoiceitem-dialog invitem sessioninvkey))))))
			(cl-who:str processed-row))))))))))


(defun invoicetemplatefillitemrows (sessioninvitems invoicepaid-p sessioninvkey)
  "中文：另一种行渲染方式：直接 CL-WHO 输出 <tr><td>序号</td>… 表格行（使用闭包自增计数器 incr）。
   返回：闭包，调用后输出 HTML 字符串。"
  (function (lambda ()
    (cl-who:with-html-output-to-string (*standard-output* nil)
      (let ((incr (let ((count 0)) (lambda () (incf count)))))
	  (mapcar (lambda (item) (cl-who:htm (:tr (:td (cl-who:str (funcall incr))) (display-invoice-item-row item invoicepaid-p sessioninvkey))))  sessioninvitems))))))

(defun generate-invoice-items-rows-public (items-list raw-template)
  "Extracts the row sub-template and repeats it for every item.
   中文：generate-invoice-items-rows 的公开版（无 actions），%row actions% 直接替换为 'N/A'。
   用于 LiveLink / PDF 发票公开预览。"
  (let* ((row-regex "(?s)<!--ROW_SNIPPET_BEGIN-->(.*?)<!--ROW_SNIPPET_END-->")
         (row-sub-template (cl-ppcre:register-groups-bind (snippet) (row-regex raw-template) snippet)))
    (if (not row-sub-template)
        (error "Could not find <!--ROW_SNIPPET_BEGIN--> markers in the template.")
	(function (lambda ()
	  (cl-who:with-html-output-to-string (*standard-output* nil)
            (loop for invitem in items-list 
                  for count from 1 do
		    (let ((processed-row row-sub-template))
		      (with-slots (prd-id prddesc hsncode qty uom price discount  taxablevalue  cgstamt  sgstamt  igstamt totalitemval) invitem
			;; Serial number
			(setf processed-row (cl-ppcre:regex-replace-all "%srno%" processed-row (format nil "~A" count)))
			;; Use your specific %row ...% format
			(setf processed-row (cl-ppcre:regex-replace-all "%row prddesc%" processed-row (or prddesc "")))
			(setf processed-row (cl-ppcre:regex-replace-all "%row hsncode%" processed-row (or hsncode "")))
			(setf processed-row (cl-ppcre:regex-replace-all "%row uom%" processed-row (or uom "")))
			(setf processed-row (cl-ppcre:regex-replace-all "%row qty%" processed-row (format nil "~A" qty)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row price%" processed-row (format nil "~,2F" price)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row discount%" processed-row (format nil "~,2F" (or discount 0))))
			(setf processed-row (cl-ppcre:regex-replace-all "%row taxable%" processed-row (format nil "~,2F" taxablevalue)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row cgst%" processed-row (format nil "~,2F" cgstamt)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row sgst%" processed-row (format nil "~,2F" sgstamt)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row igst%" processed-row (format nil "~,2F" igstamt)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row totalitemval%" processed-row (format nil "~,2F" totalitemval)))
			(setf processed-row (cl-ppcre:regex-replace-all "%row actions%" processed-row (format nil "N/A")))
			(cl-who:str processed-row))))))))))

(defun invoicetemplatefillitemrowspublic (sessioninvitems)
  "中文：invoicetemplatefillitemrows 的公开版（无操作按钮）。"
  (function (lambda ()
    (cl-who:with-html-output-to-string (*standard-output* nil)
	(let ((incr (let ((count 0)) (lambda () (incf count)))))
	  (mapcar (lambda (item) (cl-who:htm (:tr (:td (cl-who:str (funcall incr))) (display-invoice-item-row-public item))))  sessioninvitems))))))


(defun com-hhub-transaction-update-invoiceitem-action ()
  :description "This is the MVC function to update action for InvoiceItem entity.
   中文：编辑行项 PEP 入口。会话：with-vend-session-check。
   通过 with-mvc-redirect-ui 串接 model + 通用 redirect widgets。"
  (with-vend-session-check 
    (with-mvc-redirect-ui  #'create-model-for-updateInvoiceItem #'create-widgets-for-genericredirect)))
    


(defun com-hhub-transaction-create-InvoiceItem-action ()
  :description "This is a MVC function for create InvoiceItem entity.
   中文：创建行项 PEP 入口。当前 model 函数为占位（推测：业务上行项随发票头一并创建）。"
  (with-vend-session-check ;; delete if not needed. 
    (let ((url (with-mvc-redirect-ui  #'create-model-for-createInvoiceItem #'create-widgets-for-createInvoiceItem)))
      (format nil "~A" url))))



;;;;;;;;;;;;;;;;;;;;;;;;;DELETE INVOICE ITEM ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun com-hhub-transaction-delete-invoiceitem-action ()
  :description "This is a MVC function for delete InvoiceItem entity.
   中文：删除行项 PEP 入口。会话：with-vend-session-check。"
  (with-vend-session-check ;; delete if not needed. 
    (with-mvc-redirect-ui  #'create-model-for-deleteinvoiceitem #'create-widgets-for-genericredirect)))
    

(defun create-model-for-deleteinvoiceitem ()
  "中文：删除行项 model：从会话取当前发票对象 → ProcessDeleteRequest 软删 DB →
   同步会话内的 InvoiceItems / InvoiceProducts / invoicetaxbreakdown（移除税额聚合行）→
   写回 sessioninvoices-ht，跳回确认页。"
  (let* ((company (get-login-vendor-company))
	 (prd-id (parse-integer (hunchentoot:parameter "prd-id")))
	 (productlist (hhub-get-cached-vendor-products))
	 (product (search-item-in-list 'row-id prd-id productlist))
	 (sessioninvkey (hunchentoot:parameter "sessioninvkey"))
	 (sessioninvoices-ht (hunchentoot:session-value :session-invoices-ht))
	 (sessioninvoice (gethash sessioninvkey sessioninvoices-ht))
	 (sessioninvheader (slot-value sessioninvoice 'InvoiceHeader))
	 (sessioninvitems (slot-value sessioninvoice 'InvoiceItems))
	 (sessioninvtaxbreakdown (slot-value sessioninvoice 'invoicetaxbreakdown))
	 (itemtodelete (find-invoice-item prd-id sessioninvitems))
	 (sessioninvproducts (slot-value sessioninvoice 'InvoiceProducts))
	 (requestmodel (make-instance 'InvoiceItemRequestModel
					 :InvoiceHeader sessioninvheader
					 :prd-id prd-id
					 :company company))
	 (adapterobj (make-instance 'InvoiceItemAdapter))
	 (redirectlocation  (format nil "/hhub/vshowinvoiceconfirmpage?sessioninvkey=~A" sessioninvkey))
	 (params nil))
    (setf params (acons "company" company params))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (with-hhub-transaction "com-hhub-transaction-delete-invoiceitem-action" params 
      ;;(handler-case
      ;;(handler-case 
	  (let ((domainobj (ProcessDeleteRequest adapterobj requestmodel)))
	    (setf (slot-value sessioninvoice 'InvoiceItems) (delete domainobj sessioninvitems))
	    (setf (slot-value sessioninvoice 'invoiceproducts) (delete product sessioninvproducts))
	    (remove-item-from-tax-breakdown sessioninvtaxbreakdown itemtodelete)
	    (setf (gethash sessioninvkey sessioninvoices-ht) sessioninvoice)
     	    (function (lambda ()
	      (values redirectlocation)))))))
	;;(error (c)
	;; (error 'hhub-business-function-error :errstring (format t "~A:got an exception ~A" (mysql-now)  c)))))))
  


