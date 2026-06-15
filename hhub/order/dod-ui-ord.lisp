;;; dod-ui-ord.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：order 订单 —— 订单视图与列表 UI（旧 dod-* MVC）
;;;; 分层：UI（控制器 + CL-WHO 模板）
;;;; 文件：hhub/order/dod-ui-ord.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：渲染各角色（客户/卖家）下的订单列表、订单详情入口、Excel 导出文本，
;;;;       以及卖家维度按商品聚合 / 按客户聚合的订单列表。属于旧版 MVC 风格。
;;;;
;;;; 主要导出：
;;;;   dod-controller-list-orders        — 控制器：当前公司订单总览（旧客户后台）
;;;;   ui-list-orders                    — 渲染订单表格（HTML）
;;;;   ui-list-orders-for-excel          — 把订单/行项渲染成 CSV 文本（导出 Excel）
;;;;   ui-list-vendor-orders-by-products — 卖家视图：按商品聚合订单
;;;;   ui-list-vendor-orders-by-customers— 卖家视图：按客户聚合订单
;;;;   ui-list-customer-orders           — 客户"我的订单"列表
;;;;   concat-ord-dtl-name               — 拼接订单内所有商品名（导出/邮件用）
;;;;   vendor-order-card                 — 单个 vendor-order 简卡
;;;;
;;;; 关联：
;;;;   上游使用方：客户后台 / 卖家后台路由（同名控制器）
;;;;   下游依赖：order/dod-bl-ord.lisp、order/dod-bl-odt.lisp、product BL
;;;; ============================================================================

(in-package :nstores)
;;(clsql:file-enable-sql-reader-syntax)


(defun dod-controller-list-orders ()
  "中文：旧客户/CAD 后台订单总览控制器。
   会话校验：is-dod-session-valid?，未登录跳转 /login。
   行为：取当前 login-company 下所有订单，调用 ui-list-orders 渲染表格；空集返回 'No orders'。"
(if (is-dod-session-valid?)
   (let (( dodorders (get-orders-by-company  (get-login-company)))
	 (header (list  "Order No" "Order Date" "Customer" "Request Date"  "Ship Date" "Ship Address" "Action")))
     (if dodorders (ui-list-orders header dodorders) "No orders"))
     (hunchentoot:redirect "login")))


(defun ui-list-orders (header data)
  "中文：把订单列表渲染成 Bootstrap 'table table-striped'。
   header — 列标题列表；data — 单个订单或订单列表。
   行尾给出 'Cancel Order' / 'Details' 两个按钮（链接到 delorder?id=... / orderdetails?id=...）。"
  (cl-who:with-html-output (*standard-output* nil)
      (:a :class "btn btn-primary" :role "button" :href (format nil "/dodcustindex") "Shop Now")
    (:h3 "Orders")
    (:table :class "table table-striped"
     (:thead
      (:tr
       (mapcar (lambda (item) (cl-who:htm (:th (cl-who:str item)))) header)))
     (:tbody
      (mapcar
       (lambda (order)
	 (let ((ord-customer  (get-customer order)))
	   (cl-who:htm
	    (:tr
	     (:td  :height "12px" (cl-who:str (slot-value order 'row-id)))
	     (:td  :height "12px" (cl-who:str (slot-value order 'ord-date)))
	     (:td  :height "12px" (cl-who:str (slot-value ord-customer 'name)))
	     (:td  :height "12px" (cl-who:str (slot-value order 'req-date)))
	     (:td  :height "12px" (cl-who:str (slot-value order 'shipped-date)))
	     (:td  :height "12px" (cl-who:str (slot-value order 'ship-address)))
	     (:td :height "12px" (:a :class "btn btn-primary" :role "button" :href  (format nil  "delorder?id=~A" (slot-value order 'row-id)) "Cancel Order")
		  (:a  :class "btn btn-primary" :role "button" :href  (format nil  "orderdetails?id=~A" (slot-value order 'row-id)) "Details"))
	     )))) (if (not (typep data 'list)) (list data) data))))))



(defun ui-list-orders-for-excel (header ordlist)
  "中文：把卖家订单列表导出成 CSV 风格字符串（用于 Excel 下载）。
   每个订单输出一段：订单号 + 客户 + 状态（Fulfilled/Pending）+ 多行商品 + Total。
   返回：含 \\r\\n 行分隔的整段文本。"
  (cl-who:with-html-output-to-string (*standard-output* nil)
      (mapcar (lambda (item) (cl-who:str (format nil "~A," item ))) header)
      (cl-who:str (format nil " ~C~C" #\return #\linefeed))
      (mapcar (lambda (vord )
		(let* ((odtlst (dod-get-cached-order-items-by-order-id (slot-value vord 'order-id) (hunchentoot:session-value :order-func-list)  ))
		       (total   (reduce #'+  (mapcar (lambda (odt)
						       (calculate-order-item-cost odt)) odtlst)))
		       (customer (get-customer vord)))
		  (if (> (length odtlst) 0) 
		      (progn  
			(cl-who:str (format nil "Order: ~A Customer: ~A. ~A." (slot-value vord 'order-id)  (slot-value customer 'name) (slot-value customer 'address) )) 
			(if (equal (slot-value vord 'fulfilled) "Y") 
			    (cl-who:str (format nil "Order status - Fulfilled ~C~C" #\return #\linefeed )) 
			    ;else
			    (cl-who:str (format nil "Order status - Pending ~C~C" #\return #\linefeed)))
			(mapcar (lambda (odt)
				  (let* ((prd (get-odt-product odt))
					 (subtotal (calculate-order-item-cost odt))
					 (prd-name (slot-value prd 'prd-name))
					 (prd-qty (slot-value odt 'prd-qty))
					 (qty-per-unit (slot-value prd 'qty-per-unit))
					 (disc-rate (slot-value odt 'disc-rate))
					 (unit-price (slot-value odt 'unit-price)))
				    (cl-who:str (format nil "~a,~a,~a,Rs. ~$,~$,Rs. ~$,~C~C" prd-name prd-qty qty-per-unit unit-price disc-rate subtotal  #\return #\linefeed)))) odtlst)
			(cl-who:str (format nil ",,,,Total, Rs. ~$~C~C" total #\return #\linefeed)))))) ordlist)))


;; This function takes more time, please make it more efficient in future.
(defun ui-list-vendor-orders-by-products (ordlist)
  "中文：卖家维度，把订单按"商品"聚合展示：每行商品 = 总销售数量 + 小计 + 涉及订单链接。
   依赖会话变量 :login-prd-cache、:order-func-list 做产品/订单缓存。
   性能注：原作者注释提示这个函数较慢（嵌套 mapcar + 数据库查询），有优化余地。"
    (let*  ((vendor (get-login-vendor))
	    (tenant-id (get-login-vendor-tenant-id))
	    (company (get-login-vendor-company))
	    (currsymbol (get-currency-html-symbol (get-account-currency company)))
	    (products  (hunchentoot:session-value :login-prd-cache))
	    (odtlst (mapcar (lambda (prd)
			      (let ((prd-id (slot-value prd 'row-id)))
				(delete nil (mapcar (lambda (ord)
						      (let ((order-id (slot-value ord 'order-id)))
							(get-order-items-by-product-id  prd-id  order-id tenant-id)))  ordlist) :test #'equal)))
			    products)))

	 (cl-who:with-html-output (*standard-output* nil)	       
	   (mapcar (lambda (prd odtlstbyprd)
		     (let ((quantity (reduce #'+ (mapcar (lambda (odt)
							   (if odt (slot-value odt 'prd-qty)))   odtlstbyprd)))
			   (subtotal (reduce #'+ (mapcar (lambda (odt)
							   (if odt (* (slot-value odt 'unit-price) (slot-value odt 'prd-qty))  )) odtlstbyprd)))
			   (orders (remove-duplicates (mapcar (lambda (odt)
								(let* ((order-id (slot-value odt 'order-id)))
								       (get-vendor-order-instance order-id vendor))) odtlstbyprd))))
		       (if (>  subtotal 0)  
			   (cl-who:htm  (:div :class "thumbnail row"
					      (with-html-div-col-2
						(cl-who:str (slot-value prd 'prd-name)))
					      (with-html-div-col-2
						(cl-who:str (slot-value prd 'qty-per-unit)))
					      (with-html-div-col-2
					   	(:h5 (cl-who:str (format nil "~A ~$ " currsymbol ( slot-value prd 'current-price)))))
					      (with-html-div-col-2
					  	(:span :class "badge" (cl-who:str quantity)))
					      (with-html-div-col-2
						(:h4 (:span :class "label label-default" (cl-who:str (format nil "~A ~$" currsymbol subtotal))))))
					
					(:div :class "row"
					      (mapcar (lambda (order)
						  (let ((order-id (slot-value order 'row-id)))
						    (cl-who:htm
						     (with-html-div-col-2
						       (:a :data-bs-toggle "modal" :data-bs-target (format nil "#hhubvendorderdetails~A-modal"  order-id)  :href "#"  (:span :class "label label-info" (format nil "~A" (cl-who:str order-id))))
						       (modal-dialog-v2 (format nil "hhubvendorderdetails~A-modal" order-id) "Vendor Order Details" (modal.vendor-order-details order company)))))) orders))
					(:hr))))) products odtlst))))



(defun ui-list-vendor-orders-by-customers (ordlist)
  "中文：卖家维度按客户聚合订单。每条订单单独一段：客户/电话/收货地址，行项明细，门店自提提示，最后 Total。
   GUEST 客户只显示订单号 + 备注，不暴露 PII。"
 (cl-who:with-html-output (*standard-output* nil)
   (:a :class "btn btn-primary btn-xs" :role "button" :onclick "window.print();" :href "#" "Print&nbsp;&nbsp;"(:i :class "fa-solid fa-print"))
   ;; For every vendor order
   (mapcar (lambda (vord)
	     (let*  ((order-id (slot-value vord 'order-id))
		     (odtlst (dod-get-cached-order-items-by-order-id order-id (hunchentoot:session-value :order-func-list)))
		     (total   (reduce #'+  (mapcar (lambda (odt)
						     (calculate-order-item-cost odt)) odtlst)))
		     (storepickupenabled (if (equal (slot-value vord 'storepickupenabled) "Y") T NIL))
		     (customer (get-customer vord))
		     (cust-order (get-order vord))
		     (cust-name (slot-value customer 'name))
		     (cust-phone (slot-value customer 'phone))
		     (company (customer-company customer))
		     (currsymbol (get-currency-html-symbol (get-account-currency company)))
		     (ship-address (slot-value vord 'ship-address))
		     (order-comments (slot-value cust-order 'comments)))

	       ;(if (>  (length odtlst) 0) 
		   (progn 
		     (if (equal (slot-value customer 'cust-type) "GUEST")
			 (cl-who:htm (:div :class "row"
			    (:div :class "col-sm-12 col-xs-12 col-md-4 col-lg-2"
			     (:h5 (cl-who:str (format nil "Order: ~A ~A. " order-id order-comments))))))
			 ;else
		     (cl-who:htm (:div :class "row"
			    (:div :class "col-sm-12 col-xs-12 col-md-4 col-lg-2"
			     (:h5 (cl-who:str (format nil "Order: ~A ~A. ~A. ~A. " order-id cust-name cust-phone ship-address)))))))
		     (when storepickupenabled
			 (cl-who:htm (:div :class "row"
					   (:div :class "col-sm-12"
						 (:h4 (:span :class "label label-default" (cl-who:str (format nil "THIS IS STORE PICKUP ORDER. NO SHIPPING."))))))))
		     (mapcar (lambda (odt)
			       (let* ((prd (get-odt-product odt))
				      (prd-name (slot-value prd 'prd-name))
				      (current-price (slot-value prd 'current-price))
				      (prd-qty (slot-value odt 'prd-qty))
				      (qty-per-unit (slot-value prd 'qty-per-unit)))
				 (cl-who:htm 
				  (with-html-div-row :style "border: solid 0.5px;"
				    (with-html-div-col
				      (cl-who:str (format nil "~A | ~A | ~A | ~A " prd-name prd-qty qty-per-unit current-price))
				      (:h5 (cl-who:str (format nil "~A ~$ " currsymbol (slot-value odt 'unit-price))))))))) odtlst)
					; Display the total for an order
			  
		     (cl-who:htm (:div :class "row"
				       (:div :class "col-sm-12" 
					     (:h4 (:span :class "label label-default" (cl-who:str (format nil "Total ~$" total)))))))
		     
		     ))) ordlist)))


    

(defun ui-list-customer-orders (header data)
  "中文：客户'我的订单'列表。每行：订单号 / 下单日 / 期望日 + 详情链接 + FULFILLED 标签。
   详情链接到 hhubcustmyorderdetails?id=。"
  (cl-who:with-html-output (*standard-output* nil)
    (:h3 "Orders")
    (:table :class "table table-striped table-hover"
	    (:thead (:tr
		     (mapcar (lambda (item) (cl-who:htm (:th (cl-who:str item)))) header)))
	      (:tbody
	       (mapcar (lambda (order)
			 (cl-who:htm (:tr (:td  :height "12px" (cl-who:str (slot-value order 'row-id)))
				   (:td  :height "12px" (cl-who:str (get-date-string (slot-value order 'ord-date))))
				   (:td  :height "12px" (cl-who:str (get-date-string (slot-value order 'req-date))))
				   (if (equal (slot-value order 'order-fulfilled) "Y")
				       (cl-who:htm  (:td :height "12px"
						  (:a :href  (format nil  "hhubcustmyorderdetails?id=~A" (slot-value order 'row-id)) (:span :class "label label-primary" "Details" ))  "&nbsp;&nbsp;" (:span :class "label label-info" "FULFILLED")))
					; ELSE
				       (cl-who:htm  (:td :height "12px" (:a :href  (format nil  "hhubcustmyorderdetails?id=~A" (slot-value order 'row-id)) (:span :class "label label-primary" "Details" ))))
				       )))) (if (not (typep data 'list)) (list data) data) )))))




(defun concat-ord-dtl-name (order-instance)
  "中文：把订单内所有行项的商品名以逗号尾接的字符串列表返回（导出/邮件正文展示用）。
   返回：字符串列表（每项末尾带逗号，调用方自行拼接）。"
  (let ((odt ( get-order-items order-instance)))
    (mapcar (lambda (odt-ins)
	      (concatenate 'string (slot-value (get-odt-product odt-ins) 'prd-name) ",")) odt)))

; This is a pure function.
(defun vendor-order-card (vorder-instance)
  "中文：渲染单条 vendor-order 的简要卡片：客户名 + 截断地址 + 订单号链接（弹出详情 modal）。
   storepickupenabled='Y' 时附 luggage 图标。原注释 'pure function' 与实际不符（HTML 输出有副作用）。"
  (let* ((customer (get-customer vorder-instance))
	 (company (get-company vorder-instance))
	 (order-id (slot-value vorder-instance 'order-id))
	 (name (if customer (slot-value customer 'name)))
	 (storepickupenabled (if (equal (slot-value vorder-instance 'storepickupenabled) "Y") T NIL))
	 (address (if customer (slot-value customer 'address))))
    (cl-who:with-html-output (*standard-output* nil)
      (with-html-div-row
	    (with-html-div-col-8  (cl-who:str name)))
      (with-html-div-row
	    (with-html-div-col-8 (cl-who:str (if (> (length address) 20)  (subseq (slot-value customer 'address) 0 20) address))))
      (with-html-div-row
	    (with-html-div-col-8
		  (:a :data-bs-toggle "modal" :data-bs-target (format nil "#hhubvendorderdetails~A-modal"  order-id)  :href "#"  (:span :class "label label-info" (format nil "~A" (cl-who:str order-id))))
		  (modal-dialog-v2 (format nil "hhubvendorderdetails~A-modal" order-id) "Vendor Order Details" (modal.vendor-order-details vorder-instance company))
		  (if storepickupenabled
		      (cl-who:htm (:a :data-toggle "tooltip" :title "Store Pickup" :href "#" (:i :class "fa-solid fa-person-walking-luggage")))))))))
      


