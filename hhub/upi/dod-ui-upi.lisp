;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：upi UPI 收款
;;;; 分层：UI（控制器 + CL-WHO 模板 + 二维码生成 + 充值/确认动作）
;;;; 文件：hhub/upi/dod-ui-upi.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：客户端 UPI 支付与卖家端 UPI 流水管理的全部 UI / 控制器：
;;;;       - 客户结算 UPI 页（QR + 4 个 App URL Scheme + UTR 输入）
;;;;       - 钱包充值 UPI 页（同上 + 写入挂起任务，确认到账时执行 set-balance）
;;;;       - 卖家近 60 天 UPI 流水列表 + 行内"已收/未收"操作
;;;;       - 通过 *HHUBPENDINGUPIFUNCTIONS-HT* 在 utrnum 维度暂存待执行的回调
;;;;
;;;; 主要导出（控制器）：
;;;;   com-hhub-transaction-show-customer-upi-page  — 客户 UPI 结算页
;;;;   hhub-controller-upi-customer-order-payment-page — 客户订单付款页（同模板较精简）
;;;;   hhub-controller-upi-recharge-wallet-page / -action — 钱包 UPI 充值
;;;;   hhub-controller-vendor-upi-confirm / -cancel  — 卖家确认/驳回流水
;;;;   hhub-controller-show-vendor-upi-transactions  — 卖家 UPI 流水列表页
;;;;
;;;; 主要导出（构件）：
;;;;   generateqrcodeforvendor      — 用 qrencode CLI 生成 upi://pay PNG
;;;;   generateupiurlsforvendor     — 生成 phonepe/paytmmp/gpay/upi 4 个深链
;;;;   display-upi-widget           — QR + 链接 + 倒计时 + UTR 提示
;;;;   save-upi-transaction         — 把 UTR 信息落库的薄包装
;;;;   vendor-upi-payment-confirm / -cancel — 卖家侧状态机切换
;;;;   hhub-add-pending-upi-task / hhub-execute-pending-upi-task
;;;;       — 基于 *HHUBPENDINGUPIFUNCTIONS-HT* 的"待支付 → 确认后执行"机制
;;;;   RenderListViewHTML / display-upi-transaction-row /
;;;;   modal.vendor-upi-payment-confirm — 列表视图 + 行渲染 + 确认弹窗
;;;;
;;;; 关联：
;;;;   上游使用方：路由 dodcustshopcart → dodcustordershipaddrpage → 本页；
;;;;               卖家路由 hhubvendorupitransactions / hhubvendupipayconfirm / hhubvendupipaycancel
;;;;   下游依赖：upi/dod-bl-upi.lisp（六边形 Adapter / Service / Presenter）、
;;;;             cust 钱包 BL（set-wallet-balance）、order/ vendor / customer / company
;;;; ============================================================================

(in-package :nstores)

(defun com-hhub-transaction-show-customer-upi-page ()
  "URL 控制器：渲染客户的 UPI 结算页面（购物车 → 地址 → 本页）。
   要求：客户登录会话。
   渲染：通过 with-mvc-ui-page，model 由 create-model-for-showcustomerupipage 构造，
        view 由 create-widgets-for-showcustomerupipage 渲染。"
  (with-cust-session-check ;; delete if not needed.
    (with-mvc-ui-page "Customer UPI page" #'create-model-for-showcustomerupipage #'create-widgets-for-showcustomerupipage :role :customer )))

(defun create-model-for-showcustomerupipage ()
  "客户 UPI 结算页 model：
   - 从 :customer-orderparams session 取购物车 / 地址 / 物流费等多达 30+ 字段
   - 用 createorderobject 临时拼出一个 DRAFT 状态的 order 实体（仅用于渲染）
   - 调 generateqrcodeforvendor + generateupiurlsforvendor 生成扫码图与 4 个 App 深链
   - 取订单模板 #2，把 order + items 渲染成 HTML 块
   返回：lambda → (values ordertemplate qrcodepath upiappurls charcountid1 order-amt currency)。
   备注：order-cxt 为 \"#ORDER:UPI<universal-time>\" 形式。"
  (let* ((orderparams-ht (get-cust-order-params))
	 (order-items (gethash "shoppingcart" orderparams-ht))
	 (shopcart-products (gethash "shopcartproducts" orderparams-ht))
	 (context-id "")
	 (vendor-list (get-shopcart-vendorlist order-items))
	 (vendor (first vendor-list))
	 (shipaddr (gethash "shipaddress" orderparams-ht))
	 (shipzipcode (gethash "shipzipcode" orderparams-ht))
	 (shipcity (gethash "shipcity" orderparams-ht))
	 (shipstate (gethash "shipstate" orderparams-ht))
	 (billaddr (gethash "billaddress" orderparams-ht))
	 (billzipcode (gethash "billzipcode" orderparams-ht))
	 (billcity (gethash "billcity" orderparams-ht))
	 (billstate (gethash "billstate" orderparams-ht))
	 (billsameasship (gethash "billsameasshipchecked" orderparams-ht))
	 (gstnumber (gethash "gstnumber" orderparams-ht))
	 (gstorgname (gethash "gstorgname" orderparams-ht))
	 (shipping-cost (gethash "shipping-cost" orderparams-ht))
	 (order-amt (+ shipping-cost (gethash "shopcart-total" orderparams-ht)))
	 (ord-date (gethash "orddate" orderparams-ht))
	 (req-date (gethash "reqdate" orderparams-ht))
	 (shipped-date (gethash "shipdate" orderparams-ht))
	 (expected-delivery-date (gethash "expected-delivery-date" orderparams-ht))
	 (order-type (gethash "order-type" orderparams-ht))
	 (payment-mode (gethash "paymentmode" orderparams-ht))
	 (comments (gethash "comments" orderparams-ht))
	 (storepickupenabled (gethash "orderpickupinstore" orderparams-ht))
	 (customer (get-login-customer))
	 (company (get-login-customer-company))
	 (custname (slot-value customer 'name))
	 (is-cancelled nil)
	 (cancel-reason nil)
	 (external-url "NIL")
	 (is-converted-to-invoice "NO")
	 (ordnum "000")
	 (order-fulfilled " ")
	 (status "DRAFT")
	 (order-source (gethash "order-source" orderparams-ht))
	 (total-discount (gethash "total-discount" orderparams-ht))
	 (total-tax (gethash "total-tax" orderparams-ht))
	 (orderheader (createorderobject (function (lambda () (values  ord-date req-date shipped-date expected-delivery-date ordnum shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-fulfilled order-amt shipping-cost total-discount total-tax payment-mode comments context-id  status is-converted-to-invoice is-cancelled cancel-reason order-type external-url order-source custname customer company)))))
	 (order-cxt (format nil "#ORDER:UPI~A" (get-universal-time)))
	 (qrcodepath (format nil "~A/img~A" *siteurl* (generateqrcodeforvendor vendor "ABC" order-cxt  order-amt)))
	 (upiappurls (generateupiurlsforvendor vendor "ABC" order-cxt order-amt))
	 (ordertemplate (funcall (nst-get-cached-order-template-func :templatenum 2)))  
	 (orderitemshtmlfunc (ordertemplatefillitemrows order-items shopcart-products))
	 (currency (get-account-currency company))
	 (charcountid1 (format nil "idchcount~A" (hhub-random-password 3)))
	 (params nil))
    (setf ordertemplate (funcall (ordertemplatefill ordertemplate orderheader order-items orderitemshtmlfunc qrcodepath currency vendor)))
    (setf params (acons "uri" (hunchentoot:request-uri*)  params))
    (function (lambda ()
      (values ordertemplate qrcodepath upiappurls charcountid1 order-amt currency)))))


(defun create-widgets-for-showcustomerupipage (modelfunc)
  "客户 UPI 结算页 view：3 个 widget——
   1. 面包屑（Cart → Address）
   2. UPI 表单：display-upi-widget + 隐藏字段 paymentmode/amount + UTR 输入框 + Place Order
      表单 action = dodmyorderaddaction（订单提交）
   3. 订单模板 HTML 预览。"
  (multiple-value-bind (ordertemplate qrcodepath upiappurls charcountid1 order-amt currency) (funcall modelfunc)
    (let* ((widget1 (function (lambda ()
		     (with-customer-breadcrumb
		       (:li :class "breadcrumb-item" (:a :href "dodcustshopcart" "Cart"))
		       (:li :class "breadcrumb-item" (:a :href "dodcustordershipaddrpage" "Address"))))))
	   (widget2 (function (lambda()
		      (with-html-form-having-submit-event  "customerupipaymentform" "dodmyorderaddaction" 
			(with-html-div-row 
			  (with-html-div-col-12
			    (display-upi-widget order-amt currency qrcodepath upiappurls)))
			(with-html-div-row
			  (with-html-div-col-10
			    ;;(:div :class "col-sm-8" :style "text-align: center;"
			    (:input :class "form-control" :name "paymentmode" :value "UPI" :type "hidden")
			    (:input :class "form-control" :name "amount" :value order-amt :type "hidden")
			    (:div :class "input-group mb-3"
				  (:label :for "utrnum" "UTR No")
				  (:input :class "form-control" :name "utrnum" :value "" :placeholder "12 Digit UTR Number" :type "number" :onkeyup (format nil "countChar(~A.id, this, 12)" charcountid1)  :max "999999999999" :maxlength "12"  :required T)
				  (:div :id charcountid1 :class "input-group-text" :style "font-size: 1.2rem; font-weight: bold; color: purple;"))))
			(with-html-div-row 
			  (with-html-div-col-12
			    (:input :type "submit" :class "btn btn-lg btn-primary btn-block checkout-button"  :value "Place Order")))
			(:hr)))))
	   
	   (widget3 (function (lambda ()
		      (cl-who:with-html-output (*standard-output* nil)
			(cl-who:str ordertemplate))))))
	   (list widget1 widget2 widget3 ))))



(defun generateqrcodeforvendor  (vendor retailer-category-code transaction-id amount)
  "为指定 vendor 生成一张 upi://pay 协议的二维码 PNG。
   实现：拼出 upi://pay?pa=<upi-id>&pn=<vendor>&am=<amount>&tr=<txid>&cu=INR&mc=<mcc>，
        再用系统命令 qrencode -s 5 -l L -v 5 -o /tmp/upiqr<ts>.png 落到
        *HHUBRESOURCESDIR* 之下。
   返回：相对 /img 的图片文件名（caller 拼成绝对 URL）；vendor 无 upi-id 时返回 nil。
   副作用：sb-ext:run-program 调用外部 qrencode；写文件。"
  ;; upiapp values are phonepe, paytmmp, gpay, upi
  (let* ((upi-id (slot-value vendor 'upi-id))
	 (vendor-name (slot-value vendor 'name))
	 (paymentstr (format nil "\'upi://pay?pa=~A&pn=~A&am=~d&tr=~A&cu=INR&mc=~A\'" upi-id vendor-name amount transaction-id retailer-category-code))
	 (filename (format nil "/temp/upiqr~A.png" (get-universal-time)))
	 (filepath (format nil "~A~A" *HHUBRESOURCESDIR* filename))
	 (qrcodecmd (format nil "qrencode -s 5 -l L -v 5 -o ~A ~A" filepath paymentstr)))
	 
    (when upi-id
      (sb-ext:run-program "/bin/sh" (list "-c" qrcodecmd ) :input nil :output *standard-output*)
      filename)))




(defun generateupiurlsforvendor  (vendor retailer-category-code transaction-id amount)
  :description "Generates the UPI payment URLs for a vendor and returns an url list containing one url per app. upiapp values are phonepe, paytmmp, gpay, upi.
   中文：为 vendor 生成 4 个 App 专属深链：phonepe:// / paytmmp:// / gpay:// / upi://，
        每个都带 pa/pn/am/tr/cu/mc。点击对应链接会拉起手机端的 UPI 应用直接付款。
        若 vendor 未配置 upi-id，返回 nil。"
  (let* ((paymentapps (list "phonepe" "paytmmp" "gpay" "upi"))
	 (upi-id (slot-value vendor 'upi-id))
	 (vendor-name (slot-value vendor 'name)))
    (when upi-id 
      (mapcar (lambda (upiapp)
		(let ((paymenturl (format nil "~A://pay?pa=~A&pn=~A&am=~d&tr=~A&cu=INR&mc=~A" upiapp upi-id vendor-name amount transaction-id retailer-category-code)))
		  paymenturl)) paymentapps))))


(defun display-upi-widget (amount currency qrcodepath upiappurls)
  "渲染统一的 UPI 支付块：
   - 标题 + 总金额
   - 5 分钟倒计时（window.onload → countdowntimer(0,0,5,0)）
   - 4 个 App 深链 + 一张二维码图（同一交易号，二者择一支付即可）
   - 三段说明：扫码 → 复制 12 位 UTR → 粘贴到下方表单
   - 找不到 UTR 的帮助图链接（*HHUBUTRNUMHELPIMG*）"
  (let ((upiappnames (list "Phone Pe" "Pay TM" "Google Pay" "UPI"))
	(utrnumhelplinkimage (format nil "~A/img/~A" *siteurl* *HHUBUTRNUMHELPIMG* )))
    (cl-who:with-html-output (*standard-output* nil)
      (:hr)
      (:h5 (cl-who:str (format nil "Complete Your Payment")))
      (:h4 (cl-who:str (format nil "Total Amount = ~A ~$" (get-currency-html-symbol currency) amount)))
      (:hr)
      (:div :id "withCountDownTimerExpired" 
	    (with-html-div-row 
	      (with-html-div-col :style "text-align: center;"
		(:p "This session will expire in" (:div :id "withCountDownTimer"))))
	    (when (> (length upiappurls) 0)
	      (mapcar
	       (lambda (url appname)
		 (cl-who:htm
		  (with-html-div-row 
		    (with-html-div-col :style "text-align: center;"
		      (:a :href url (cl-who:str appname)))))) upiappurls upiappnames)
	      (with-html-div-row 
		(with-html-div-col :style "text-align: center;"
		  (:img :style "width: 200px; height: 200px;" :src qrcodepath)))))
      (:hr)
      (:p
       (:small "1. Pay Now: Scan the UPI QR or click a link above to pay. You will not be redirected back."))
      (:p
       (:small "2. Confirm Order: After successful payment, locate the 12-digit Reference ID (or UTR) in your payment app. You must paste this ID into the box below and click 'Place Order' to complete your order."))
      (:p
       (:small "Having trouble? Click here for a step-by-step guide to finding your Reference ID.")
       (:a :href utrnumhelplinkimage :target "_blank" "Click Here"))
      (:script "window.onload = function() {countdowntimer(0,0,5,0);}"))))


(defun create-model-for-custorderpaymentpage  ()
  "客户付款页（精简版）model：仅算合计金额、生成 QR + 4 个深链。
   订单合计 = 税后小计 + 物流费。订单上下文同样为 \"#ORDER:UPI<ts>\"。
   返回 lambda → (values upitotal currency qrcodepath upiurls vendor charcountid1)。"
  (let* ((orderparams-ht (get-cust-order-params))
	 (odts (gethash "shoppingcart" orderparams-ht))
	 (shipping-cost (gethash "shipping-cost" orderparams-ht))
	 (totalaftertax (calculate-invoice-totalaftertax odts))
	 (upitotal (+ totalaftertax shipping-cost))
	 (order-cxt (format nil "#ORDER:UPI~A" (get-universal-time)))
	 (vendor-list (get-shopcart-vendorlist odts))
	 (vendor (first vendor-list))
	 (company (get-login-customer-company))
	 (upiurls (generateupiurlsforvendor vendor "ABC" order-cxt upitotal))
	 (qrcodepath (format nil "~A/img~A" *siteurl* (generateqrcodeforvendor vendor "ABC" order-cxt  upitotal)))
	 (currency (get-account-currency company))
	 (charcountid1 (format nil "idchcount~A" (hhub-random-password 3))))
    (function (lambda ()
      (values  upitotal currency qrcodepath upiurls vendor charcountid1)))))


(defun create-widgets-for-custorderpaymentpage (modelfunc)
  "客户付款页 view：
   widget1 — 面包屑；
   widget2 — UPI 卡片，含 display-upi-widget + UTR 表单（action=dodmyorderaddaction）+ Previous 链。
   边界：vendor 未配置 upi-id 时直接 hunchentoot:redirect 到 /hhub/vendorupinotfound。"
  (multiple-value-bind
	( upitotal currency qrcodepath upiurls vendor charcountid1)
      (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (with-customer-breadcrumb
		       (:li :class "breadcrumb-item" (:a :href "dodcustshopcart" "Cart"))
		       (:li :class "breadcrumb-item" (:a :href "dodcustordershipaddrpage" "Address"))))))
	  (widget2 (function (lambda ()
		     (with-html-card
			     (:title "UPI Payment"
			      :image-src (format nil "/img/~A" *HHUBUPILOGOIMG*)
			      :image-alt "UPI Payment"
			      :image-style  "width: 150px; height: 150px; background-size: cover; background-repeat: no-repeat; background-position: center;")
	    	       (with-html-div-row-fluid :style "box-shadow: rgba(17, 17, 26, 0.1) 0px 0px 16px;"
			 (display-upi-widget  upitotal currency qrcodepath upiurls))
		       (with-html-form-having-submit-event  "customerupipaymentform" "dodmyorderaddaction" 
			 (:div :class "row mb-3"
			       (:div :class "col-sm-8" :style "text-align: center;"
				     (:label :for "utrnum" "UTR No")
				     (:input :class "form-control" :name "paymentmode" :value "UPI" :type "hidden")
				     (:input :class "form-control" :name "amount" :value upitotal :type "hidden")
				     (:div :class "input-group mb-3"
				     	   (:input :class "form-control" :name "utrnum" :value "" :placeholder "12 Digit UTR Number" :type "number" :onkeyup (format nil "countChar(~A.id, this, 12)" charcountid1)  :max "999999999999" :maxlength "12"  :required T)
					   (:div :id charcountid1 :class "input-group-text" :style "font-size: 1.2rem; font-weight: bold; color: purple;"))))
			 (with-html-div-row
			   (with-html-div-col-6
			     (:a :role "button" :class "btn btn-lg btn-primary btn-block" :href "hhubcustpaymentmethodspage" "Previous"))
			   (with-html-div-col-6
			     (:input :type "submit" :class "btn btn-lg btn-primary btn-block checkout-button"  :value "Place Order")))))))))
	  ;; If Vendor UPI ID is not defined, then redirect to the UPI ID not found page. 
	  (unless (slot-value vendor 'upi-id) (hunchentoot:redirect "/hhub/vendorupinotfound"))
	  (list widget1 widget2 ))))

(defun hhub-controller-upi-customer-order-payment-page ()
  "URL 控制器：客户结算 UPI 简化页（卡片样式）。要求客户登录。"
  (with-cust-session-check
    (with-mvc-ui-page "Customer UPI Payment Page" #'create-model-for-custorderpaymentpage #'create-widgets-for-custorderpaymentpage :role :customer)))

(defun create-model-for-upirechargewalletpage ()
  "钱包 UPI 充值页 model：
   从 query string 取 wallet-id 与 amount；wallet 反查 vendor；
   交易号格式 \"#WAL:<universal-time>\"。生成同样的 QR + App URL。"
  (let* ((wallet-id (hunchentoot:parameter "wallet-id"))
	 (amount (hunchentoot:parameter "amount"))
	 (custcomp (get-login-customer-company))
	 (currency (get-account-currency custcomp))
	 (wallet (get-cust-wallet-by-id wallet-id custcomp))
	 (vendor (get-vendor wallet))
	 (transaction-id (format nil "#WAL:~A" (get-universal-time)))
	 (upiurls (generateupiurlsforvendor vendor "ABC" transaction-id amount))
	 (charcountid1 (format nil "idchcount~A" (hhub-random-password 3)))
	 (qrcodepath (format nil "~A/img~A" *siteurl* (generateqrcodeforvendor vendor "ABC" transaction-id amount))))
    (function (lambda ()
      (values amount currency qrcodepath upiurls wallet-id transaction-id charcountid1)))))

(defun create-widgets-for-upirechargewalletpage (modelfunc)
  "钱包 UPI 充值页 view：
   - 有 qrcodepath：渲染 UPI 卡片 + 表单（action=hhubcustwalletrechargeaction，
     隐藏字段 wallet-id / amount / transaction-id + UTR 输入）
   - 无 qrcodepath：只显示\"vendor 未配置 UPI\"的占位提示。"
  (multiple-value-bind (amount currency qrcodepath upiurls wallet-id transaction-id charcountid1)
      (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (if qrcodepath
			 (with-html-card
			     (:title "UPI Payment"
			      :image-src "/img/UPI.png"
			      :image-alt "UPI Payment"
			      :image-style "width: 200px; height: 200px;")
	    		   (with-html-div-row-fluid :style "box-shadow: rgba(17, 17, 26, 0.1) 0px 0px 16px;"
			     (display-upi-widget amount currency qrcodepath upiurls)
			     (with-html-form "customerupipaymentform" "hhubcustwalletrechargeaction"
			       (:div :class "row mb-3"
				     (:div :class "col" :style "text-align: center;"
					   (:input :class "form-control" :name "wallet-id" :value wallet-id :type "hidden")
					   (:input :class "form-control" :name "amount" :value amount :type "hidden")
					   (:input :class "form-control" :name "transaction-id" :value transaction-id :type "hidden")
					   (:label :for "utrnum" "UTR No")
					   (:div :class "input-group mb-3"
						 (:input :class "form-control" :name "utrnum" :value "" :placeholder "12 Digit UTR Number" :type "number" :onkeyup (format nil "countChar(~A.id, this, 12)" charcountid1)  :max "999999999999" :maxlength "12"  :required T)
					   (:div :id charcountid1 :class "input-group-text" :style "font-size: 1.2rem; font-weight: bold; color: purple;"))))
			     (:div :class "row mb-3"
				   (:div :class "col" :style "text-align: center;"
					 (:button :class "btn btn-lg btn-primary btn-block" :type "submit" (cl-who:str (format nil "Recharge Wallet for ~A" amount))))))))
			 ;;else
			 (with-html-div-row-fluid :style "box-shadow: rgba(17, 17, 26, 0.1) 0px 0px 16px;"
			   (:h2 (cl-who:str "UPI Details for Vendor Missing"))))))))
      (list widget1))))
  
(defun hhub-controller-upi-recharge-wallet-page ()
  "URL 控制器：客户钱包 UPI 充值页。要求客户登录。"
  (with-cust-session-check
    (with-mvc-ui-page "Customer Recharge Wallet - UPI Payment Page" #'create-model-for-upirechargewalletpage #'create-widgets-for-upirechargewalletpage :role :customer)))

(defun hhub-controller-upi-recharge-wallet-action ()
  "URL 控制器（POST 动作）：处理钱包充值表单提交。
   流程：
     1. 读 wallet-id / transaction-id / amount / utrnum；
     2. 通过 UpiPaymentsRequestModel + UpiPaymentsAdapter.ProcessCreateRequest 落库一条
        UPI 流水（PEN/N）；
     3. 把"卖家确认到账后才执行"的回调 (set-wallet-balance latest-balance wallet) 注册到
        *HHUBPENDINGUPIFUNCTIONS-HT*[utrnum]；
     4. redirect 到 /hhub/dodcustwallet。
   备注：钱包余额并非立即增加，必须等卖家在 vendor 端 confirm 后才会执行回调。"
  (with-cust-session-check
    (let* ((wallet-id (hunchentoot:parameter "wallet-id"))
	   (transaction-id (hunchentoot:parameter "transaction-id"))
	   (amount (with-input-from-string (in (hunchentoot:parameter "amount"))
		     (read in)))
	   (utrnum (hunchentoot:parameter "utrnum"))
	   (custcomp (get-login-customer-company))
	   (wallet (get-cust-wallet-by-id wallet-id custcomp))
	   (vendor (get-vendor wallet))
	   (customer (get-customer wallet))
	   (phone (slot-value customer 'phone))
	   (current-balance (slot-value wallet 'balance))
	   (latest-balance (+ current-balance amount))
	   (requestmodel (make-instance 'UpiPaymentsRequestModel
					:vendor vendor
					:customer customer
					:amount amount
					:phone phone
					:transaction-id transaction-id
					:utrnum utrnum
					:company custcomp))
	   (upipaymentsadapter (make-instance 'UpiPaymentsAdapter)))
      
      (when wallet
	;; We are creating the UPI domain model object. It also saves the UPI payment transaction to DB.
	(ProcessCreateRequest upipaymentsadapter requestmodel)
	  ;; Update the wallet balance in future.
	(hhub-add-pending-upi-task utrnum (function (lambda () (set-wallet-balance latest-balance wallet))))
	(hunchentoot:redirect (format nil "/hhub/dodcustwallet"))))))


(defun hhub-add-pending-upi-task (utrnum pendingfunction)
  "把 utrnum → 待执行回调 注册到全局哈希 *HHUBPENDINGUPIFUNCTIONS-HT*。
   后续卖家 confirm/cancel 时会查表执行/丢弃。"
  (setf (gethash utrnum *HHUBPENDINGUPIFUNCTIONS-HT*) pendingfunction))

(defun hhub-execute-pending-upi-task (utrnum &optional (cancel nil))
  "按 utrnum 取出回调：
     cancel=nil（确认到账）→ 执行回调，再从表中移除；
     cancel=T（驳回）       → 不执行，仅移除。
   备注：移除是无条件的，避免下次误触发。"
  (let ((func (gethash utrnum *HHUBPENDINGUPIFUNCTIONS-HT*)))
    (if (and func (not cancel))
	(funcall func))
    (remhash utrnum *HHUBPENDINGUPIFUNCTIONS-HT*)))

(defun save-upi-transaction (amount utrnum transaction-id customer vendor company phone)
  :description "Save the UPI transaction to the DB and return the domain object.
   中文：通用包装——构造 RequestModel 与 Adapter，调 ProcessCreateRequest 落库；
        并注册一个 no-op 的 pending task（占位，未来可改为业务回调）。"
  (let* ((requestmodel (make-instance 'UpiPaymentsRequestModel
					:vendor vendor
					:customer customer
					:amount amount
					:transaction-id transaction-id
					:utrnum utrnum
					:phone phone
					:company company))
	     (upipaymentsadapter (make-instance 'UpiPaymentsAdapter)))
	
      ;; We are creating the UPI domain model object. It also saves the UPI payment transaction to DB.
      (ProcessCreateRequest upipaymentsadapter requestmodel)
      ;; currently we do not have any pending task. 
      (hhub-add-pending-upi-task utrnum (function (lambda () ())))))



(defun vendor-upi-payment-confirm (utrnum vendor company)
  :description "Update the UPI transaction with vendorconfirm and status fields set.
   中文：卖家会话内调用，把指定 utrnum 的 UPI 流水标记为已收款（vendorconfirm='Y',
        status='CNF'）。底层走 Adapter.ProcessUpdateRequest → Service.doupdate。"
  (with-vend-session-check
    (let* ((requestmodel (make-instance 'UpiPaymentsRequestModel
					:vendor vendor
					:utrnum utrnum
					:paymentconfirm T
					:company company))
	   (upipaymentsadapter (make-instance 'UpiPaymentsAdapter)))
	
      ;; We are creating the UPI domain model object. It also saves the UPI payment transaction to DB.
	(ProcessUpdateRequest upipaymentsadapter requestmodel))))
    
(defun vendor-upi-payment-cancel (utrnum vendor company)
  :description "Update the UPI transaction with vendorconfirm and status fields set.
   中文：卖家驳回某 UPI 流水，置 vendorconfirm='N'、status='CAN'（doupdate 内部完成）。"
  (with-vend-session-check
    (let* ((requestmodel (make-instance 'UpiPaymentsRequestModel
					:vendor vendor
					:utrnum utrnum
					:paymentconfirm NIL
					:company company))
	   (upipaymentsadapter (make-instance 'UpiPaymentsAdapter)))
	
      ;; We are creating the UPI domain model object. It also saves the UPI payment transaction to DB.
	(ProcessUpdateRequest upipaymentsadapter requestmodel))))

(defun hhub-controller-vendor-upi-cancel ()
  "URL 控制器：路由 hhubvendupipaycancel。卖家驳回某 utrnum：
   ① 改库 (CAN/N)；② cancel=T 丢弃 pending task；③ redirect 回流水列表。"
  (with-vend-session-check
    (let* ((utrnum (hunchentoot:parameter "utrnum"))
	   (vendor (get-login-vendor))
	   (company (get-login-vendor-company)))
      (vendor-upi-payment-cancel utrnum vendor company)
      (hhub-execute-pending-upi-task utrnum T)
      (hunchentoot:redirect "/hhub/hhubvendorupitransactions"))))


(defun hhub-controller-vendor-upi-confirm ()
  "URL 控制器：路由 hhubvendupipayconfirm。卖家确认到账某 utrnum：
   ① 改库 (CNF/Y)；② 执行该 utrnum 上注册的 pending task（如钱包加余额）；
   ③ redirect 回流水列表。"
  (with-vend-session-check
    (let* ((utrnum (hunchentoot:parameter "utrnum"))
	   (vendor (get-login-vendor))
	   (company (get-login-vendor-company)))
      (vendor-upi-payment-confirm utrnum vendor company)
      (hhub-execute-pending-upi-task utrnum)
      (hunchentoot:redirect "/hhub/hhubvendorupitransactions"))))

(defun create-model-for-showvendorupitransactions ()
  "卖家 UPI 流水列表 model：
   通过 Adapter.ProcessReadAllRequest 取近 60 天 UPI 流水，
   再经 Presenter.CreateAllViewModel 生成 ViewModel 列表。
   返回：lambda → (values viewallmodel htmlview)。"
  (let* ((vendor (get-login-vendor))
	 (company (get-login-vendor-company))
	 (upipaymentspresenter (make-instance 'UpiPaymentsPresenter))
	 (upipaymentrequestmodel (make-instance 'UpiPaymentsRequestModel
						:vendor vendor
						:company company))
	 (upipaymentsadapter (make-instance 'UpiPaymentsAdapter))
	 (upipaymentobjlst (processreadallrequest upipaymentsadapter upipaymentrequestmodel))
	 (upipaymentsresponsemodellist (processresponselist upipaymentsadapter upipaymentobjlst))
	 (viewallmodel (CreateAllViewModel upipaymentspresenter upipaymentsresponsemodellist))
	 (htmlview (make-instance 'UPIPaymentsHTMLView)))
    (function (lambda ()
      (values viewallmodel htmlview)))))

(defun create-widgets-for-showvendorupitransactions (modelfunc)
  "卖家 UPI 流水列表 view：单个 widget，调 RenderListViewHTML 把列表渲染成表格。"
	   ;; this is the view.
  (multiple-value-bind (viewallmodel htmlview) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil) 
		       (with-html-div-row
			 (:h4 "Showing records for last 60 Days"))
		       (cl-who:str (RenderListViewHTML htmlview viewallmodel)))))))
      (list widget1))))


(defun hhub-controller-show-vendor-upi-transactions ()
  "URL 控制器：路由 hhubvendorupitransactions。卖家维度 UPI 流水列表页。"
  (with-vend-session-check
    (with-mvc-ui-page "Vendor UPI Transactions" #'create-model-for-showvendorupitransactions #'create-widgets-for-showvendorupitransactions :role :vendor)))

(defmethod RenderListViewHTML ((htmlview UPIPaymentsHTMLView) viewmodellist)
  "把 ViewModel 列表渲染成 7 列表格：Date / Customer / Phone / Amount / UTR / Status / Action。
   空列表时不渲染。"
  (unless (= (length viewmodellist) 0)
    (display-as-table (list "Date" "Customer" "Phone" "Amount" "UTR Number" "Status" "Action") viewmodellist 'display-upi-transaction-row)))


(defun display-upi-transaction-row (upiviewmodel &rest arguments)
  "渲染流水表格的一行：
   - 7 个 td 字段；
   - Action 列含订单详情模态框 + 根据 (vendorconfirm, status) 三态：
     · ('N','CAN') → \"Payment Not Received\"；
     · ('N',_)    → \"Confirm UPI Payment\" 模态触发器（弹 modal.vendor-upi-payment-confirm）；
     · ('Y','CNF') → \"Received\"。"
  (declare (ignore arguments))
  (let* ((vendor (slot-value upiviewmodel 'vendor))
	 (company (slot-value upiviewmodel 'company))
	 (order-id (subseq (slot-value upiviewmodel 'transaction-id) 5))
	 (vorder (if order-id (get-vendor-order-instance order-id vendor))))
	    
    (with-slots (amount vendor customer utrnum status vendorconfirm created phone) upiviewmodel
      (cl-who:with-html-output (*standard-output* nil)
	(:td  :height "10px" (cl-who:str (get-date-string created)))
	(:td  :height "10px" (cl-who:str (slot-value customer  'name)))
	(:td  :height "10px" (cl-who:str (if phone phone))
	(:td  :height "10px" (cl-who:str amount))
	(:td  :height "10px" (cl-who:str utrnum))
	(:td  :height "10px" (cl-who:str status))
	(:td :height "10px"
	     (with-modal-dialog-link
		 (format nil "hhubvendorderdetails~A-modal"  order-id)
	       (function (lambda () (cl-who:with-html-output (*standard-output* nil) (:span :class "label label-info" (format nil "~A" (cl-who:str order-id))))))
	       "Vendor Order Details" (function (lambda () (if vorder (modal.vendor-order-details vorder company)))))
	     (cond ((and (equal vendorconfirm "N") (equal status "CAN"))
	       (cl-who:htm
		(:td :height "10px" (:i :class "fa fa-inr" :aria-hidden "true") "Payment Not Received")))
	      ((equal vendorconfirm "N") 
	       (cl-who:htm
		(:td  :height "10px"
		      (with-modal-dialog-link (format nil "vendorupipaymentconfirm~A" utrnum)
			(function (lambda () (cl-who:with-html-output (*standard-output* nil) (:i :class "fa fa-inr" :aria-hidden "true"))))
			"Confirm UPI Payment"
			(function (lambda () (modal.vendor-upi-payment-confirm upiviewmodel))))))) 
	      ((and (equal vendorconfirm "Y") (equal status "CNF"))
	       (cl-who:htm
		(:td :height "10px" (:i :class "fa fa-inr" :aria-hidden "true") " Received"))))))))))

(defun modal.vendor-upi-payment-confirm (upiviewmodel)
  "卖家"确认 UPI 到账"模态框正文：内含两个 POST 表单（utrnum 隐藏字段）：
   - 主按钮 \"Payment Received\" → action=hhubvendupipayconfirm
   - 次按钮 \"Payment Not Received\" → action=hhubvendupipaycancel
   两个表单 id 同名（form-vendorupiconfirm），实际是不同的 <form> 元素。"
  (with-slots (utrnum status) upiviewmodel
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row 
	(with-html-div-col-10
	  (:h3 (cl-who:str (format nil "UTR Number - ~A." utrnum)))
	  (:form :id (format nil "form-vendorupiconfirm") :data-toggle "validator"  :role "form" :method "POST" :action "hhubvendupipayconfirm" :enctype "multipart/form-data"
		 (:div :class "form-group" :style "display: none"
		       (:input :class "form-control":name "utrnum" :value utrnum :placeholder "UTR Number" :type "text" :readonly T ))
		 (:div :class "form-group"
		       (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Payment Received")))))
	(with-html-div-row
	  (with-html-div-col-10
	    (:form :id (format nil "form-vendorupiconfirm") :data-toggle "validator"  :role "form" :method "POST" :action "hhubvendupipaycancel" :enctype "multipart/form-data"
		   (:div :class "form-group" :style "display: none"
			 (:input :class "form-control" :name "utrnum" :value utrnum :placeholder "UTR Number" :type "numeric"   :readonly T ))
		   (:div :class "form-group"
			 (:button :class "btn btn-lg btn-danger btn-block" :type "submit" "Payment Not Received"))))))))


