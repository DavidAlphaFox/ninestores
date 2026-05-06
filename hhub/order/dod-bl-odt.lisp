;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：order 订单 —— 订单行项业务逻辑（旧 dod-* MVC）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/order/dod-bl-odt.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-order-items 行项的查询/创建/更新/取消/软删/恢复，以及单行 GST
;;;;       重算（CGST/SGST/IGST 按本州/跨州拆分）。属于旧版 MVC 风格，新代码请用
;;;;       nst-bl-OrderItem.lisp。
;;;;
;;;; 主要导出：
;;;;   get-order-items / get-order-item-by-id          — 行项查询
;;;;   count-order-items-completed / -pending          — 完成/待处理计数（履约判定用）
;;;;   get-pending-order-items-for-vendor-by-product   — 卖家维度的待处理行项
;;;;   get-order-items-for-vendor / -by-order-id       — 卖家可见的行项视图
;;;;   create-order-items / persist-order-items        — 新增行项
;;;;   create-odtinst-shopcart                         — 购物车阶段构造瞬态对象（不入库）
;;;;   update-order-item / cancel-order-items          — 修改 / CCN 取消
;;;;   delete-order-items / restore-deleted-order-details — 软删 / 恢复
;;;;   update-gst-for-order-lineitem                   — 行项 GST 重算
;;;;
;;;; 关联：
;;;;   上游使用方：order/dod-bl-ord.lisp（履约推进时按行项汇总）、
;;;;               order/dod-ui-odt.lisp、invoice 模块（按订单转发票）
;;;;   下游依赖：order/dod-dal-odt.lisp（实体）、product BL（GST 速率取值）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



(defun get-order-items (order-instance)
:documentation "Returns the list of order details instances given order-instance as input.
   中文：返回某订单下所有未软删的行项列表。
   过滤：deleted-state='N' AND tenant-id 来自 order-instance.tenant-id。
   返回：dod-order-items 列表。"
  (let ((tenant-id (slot-value order-instance 'tenant-id))
	(order-id (slot-value order-instance 'row-id)))
 (clsql:select 'dod-order-items  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:order-id] order-id]]    :caching nil :flatp t )))


(defun get-order-item-by-id  (item-id )
:documentation "Returns the order item by id.
   中文：按主键 row-id 查询单条行项。注意：未限定 tenant-id，跨租户取第一条。
   返回：dod-order-items 实例 / nil。"
(first (clsql:select 'dod-order-items  :where
		[and [= [:deleted-state] "N"]
		[=[:row-id] item-id]]    :caching nil :flatp t )))




(defun delete-all-order-items (order-instance company)
  "中文：把订单下所有行项软删。
   参数：order-instance — 主单；company — 租户。
   副作用：批量 UPDATE 设置 deleted-state='Y'。"
  (let ((order-items (get-order-items order-instance)))
    (if order-items (delete-order-items  order-items company))))


(defun count-order-items-completed (order-instance company)
  :documentation "Checks whether all the order items are in completed status for a given order.
   中文：统计订单中已完成（status='CMP' AND fulfilled='Y'）的行项数。
   返回：整数。被履约逻辑用来判断主单可否标记 CMP。"
(let ((tenant-id (slot-value company 'row-id))
      (order-id (slot-value order-instance 'row-id)))
  (first (clsql:select [count [*]] :from 'dod-order-items :where 
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:status] "CMP"]
		[= [:fulfilled] "Y"]
		[=[:order-id] order-id]]    :caching nil :flatp t ))))


(defun count-order-items-pending (order-instance company)
  :documentation "Checks whether all the order items are in completed status for a given order.
   中文：统计订单中待处理（status='PEN' AND fulfilled='N'）的行项数。
   返回：整数。备注：原英文 docstring 抄自上一函数，实际过滤的是 PEN 状态。"
(let ((tenant-id (slot-value company 'row-id))
      (order-id (slot-value order-instance 'row-id)))
  (first (clsql:select [count [*]] :from 'dod-order-items :where 
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:status] "PEN"]
		[= [:fulfilled] "N"]
		[=[:order-id] order-id]]    :caching nil :flatp t ))))



(defun get-pending-order-items-for-vendor-by-product (product-instance vendor-instance )
  "中文：列出某卖家针对某商品的全部待处理行项（PEN+未履约）。
   过滤：deleted-state='N'、tenant-id 取自 vendor、vendor-id、prd-id。
   返回：dod-order-items 列表。"
(let* ((tenant-id (slot-value vendor-instance 'tenant-id))
       (product-id (slot-value product-instance 'row-id))
       (vendor-id (slot-value vendor-instance 'row-id)))
  	
 (clsql:select 'dod-order-items  :where
		[and [= [:deleted-state] "N"]
		     [= [:tenant-id] tenant-id]
		     [= [:vendor-id] vendor-id]
		     [= [:status] "PEN"]
		     [= [:fulfilled] "N"]
		     [=[:prd-id] product-id]]    :caching nil :flatp t )))

  
(defun get-order-items-for-vendor-by-order-id (order-instance vendor-instance)
  "中文：列出某订单中归属指定卖家的所有未删行项。
   多卖家订单中卖家只看到自己的行项。"
    (let* ((tenant-id (slot-value order-instance 'tenant-id))
	     (vendor-id (slot-value vendor-instance 'row-id))
	      (order-id (slot-value order-instance 'row-id)))
	
 (clsql:select 'dod-order-items  :where
		[and [= [:deleted-state] "N"]
		     [= [:tenant-id] tenant-id]
		     [= [:vendor-id] vendor-id]
		     [=[:order-id] order-id]]    :caching nil :flatp t )))


(defun get-completed-order-items-for-vendor (vendor-instance rowcount company)
  "中文：取卖家已完成（CMP+履约）行项的最新 rowcount 条，按 order-id 排序。
   参数：rowcount — LIMIT；只查 fulfilled='Y' 的卖家子单内的行项。
   返回：dod-order-items 列表。"
    (let* ((tenant-id (slot-value company 'row-id))
	     (vendor-id (slot-value vendor-instance 'row-id)))
 (clsql:select 'dod-order-items  :where
	       [and [= [:deleted-state] "N"]
	       [= [:status] "CMP"]
	       [= [:fulfilled] "Y"]
	       [in [:order-id] (get-orderids-for-vendor vendor-instance company "Y")]
	       [= [:tenant-id] tenant-id]
	       [= [:vendor-id] vendor-id]] :order-by :order-id  :limit rowcount
	       :caching nil :flatp t )))


(defun get-order-items-for-vendor (vendor-instance  company &optional  (recordsfordays 30))
  "中文：取卖家最近 recordsfordays 天内的待处理行项（PEN+未履约）。
   时间窗口以 created 字段在 [今天-N, 今天+N] 范围内为准。
   参数：vendor-instance、company；recordsfordays 默认 30。
   返回：dod-order-items 列表，按 order-id 排序。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (strfromdate (get-date-string-mysql (clsql-sys:date- (clsql-sys::get-date) (clsql-sys:make-duration :day recordsfordays))))
	 (strtodate (get-date-string-mysql (clsql-sys:date+ (clsql-sys::get-date) (clsql-sys:make-duration :day recordsfordays))))
	 (vendor-id (slot-value vendor-instance 'row-id)))
 (clsql:select 'dod-order-items  :where
	       [and [= [:deleted-state] "N"]
	       [between [:created] strfromdate strtodate]
	       [= [:status] "PEN"]
	       [= [:fulfilled] "N"]
	       ;; [in [:order-id] (get-orderids-for-vendor vendor-instance company fulfilled recordsfordays)]
	       [= [:tenant-id] tenant-id]
	       [= [:vendor-id] vendor-id]] :order-by :order-id
	       :caching nil :flatp t )))



(defun get-order-items-by-product-id (prd-id order-id tenant-id)
  "中文：在指定订单中按 (tenant-id, prd-id) 查找单条行项（用于购物车合并/重复商品判断）。
   返回：dod-order-items 实例 / nil。"
 (car (clsql:select 'dod-order-items  :where
		[and [= [:deleted-state] "N"]
     [= [:tenant-id] tenant-id]
     [= [:prd-id] prd-id]
		[=[:order-id] order-id]]    :caching nil :flatp t )))
    

(defun update-order-item (odt-instance); This function has side effect of modifying the database record.
  "中文：把行项实例的所有字段写回数据库（UPDATE）。副作用：修改 DB。"
  (clsql:update-records-from-instance odt-instance))

(defun cancel-order-items (list company-instance)
  "中文：批量把行项状态置为 CCN（CANCELLED BY CUSTOMER）。
   参数：list — row-id 列表；company-instance 决定 tenant-id 过滤。
   副作用：UPDATE DOD_ORDER_ITEMS.status。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (mapcar (lambda (id)  (let ((dodorder (car (clsql:select 'dod-order-items :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
			  (setf (slot-value dodorder 'status) "CCN") ; CCN = CANCELLED BY CUSTOMER
			  (clsql:update-record-from-slot dodorder  'status))) list )))

(defun delete-order-items (list company-instance)
  "中文：按 row-id 批量软删行项（deleted-state='Y'）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodorder (car (clsql:select 'dod-order-items :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
			  (setf (slot-value dodorder 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodorder  'deleted-state))) list )))


(defun restore-deleted-order-details ( list company-instance )
  "中文：批量把已软删的行项恢复（deleted-state='N'）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
(mapcar (lambda (id)  (let ((dodorder (car (clsql:select 'dod-order-items :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
    (setf (slot-value dodorder 'deleted-state) "N")
    (clsql:update-record-from-slot dodorder 'deleted-state))) list )))

  

  
(defun persist-order-items(order-id product-id vendor-id unit-price discount product-qty sgst sgstamt cgst cgstamt igst igstamt taxablevalue totalitemval tenant-id )
  "中文：底层持久化：构造 dod-order-items 并 INSERT。新建行项默认 status='PEN'、fulfilled='N'。
   仅供 create-order-items 调用。"
  (clsql:update-records-from-instance (make-instance 'dod-order-items
						    :order-id order-id
						    :prd-id product-id
						    :vendor-id vendor-id
						    :unit-price unit-price
						    :disc-rate discount
						    :sgst sgst
						    :sgstamt sgstamt
						    :cgst cgst
						    :cgstamt cgstamt
						    :igst igst
						    :igstamt igstamt
						    :taxablevalue taxablevalue
						    :totalitemval totalitemval
						    :status "PEN"
						    :fulfilled "N"
						    :prd-qty product-qty
						    :tenant-id tenant-id
						    :deleted-state "N")))





 ;This is a clean function with no side effect.
(defun create-order-items (order product  product-qty unit-price discount sgst sgstamt cgst cgstamt igst igstamt taxablevalue totalitemval company-instance)
  "中文：在某订单下创建一条行项。从 product 推断 vendor-id，从 company 取 tenant-id。
   注释里 'no side effect' 与实际不符 —— 实际会通过 persist-order-items 写库。
   参数：order/product 为实体，金额/GST 字段在调用方算好后传入。"
  (let ((order-id (slot-value order 'row-id))
	(product-id (slot-value product 'row-id))
	(vendor-id (slot-value (product-vendor product) 'row-id))
	(tenant-id (slot-value company-instance 'row-id)))
    (persist-order-items order-id product-id vendor-id unit-price discount product-qty sgst sgstamt cgst cgstamt igst igstamt taxablevalue totalitemval tenant-id)))



(defun update-gst-for-order-lineitem (lineitem product placeofsupply vstate)
  "中文：根据当前商品价格/折扣 + 供应地（placeofsupply）vs 卖家所在州（vstate）
   重算行项的应税额、CGST/SGST/IGST 速率与税额、合计。
   intrastate（同州）：CGST + SGST 各半；interstate（跨州）：仅 IGST。
   副作用：直接 setf 修改 lineitem 的多个 slot（不写库）。
   返回：修改后的 lineitem。"
  (let* ((product-qty (slot-value lineitem 'prd-qty))
	 (current-price (slot-value product 'current-price))
	 (current-discount (slot-value product 'current-discount))
	 (gstvalues (get-gstvalues-for-product product))
	 (cgstrate (if gstvalues (first gstvalues) 0.00)) 
	 (sgstrate (if gstvalues (second gstvalues) 0.00))
	 (igstrate (if gstvalues (third gstvalues) 0.00)) 
	 (txvalue (- (* product-qty current-price) (if current-discount (/ (* product-qty  current-price current-discount) 100) 0.00)))
	 (intrastate (if (equal vstate placeofsupply) T NIL))
	 (interstate (if (equal vstate placeofsupply) NIL T)) 
	 (cgstamount (if intrastate (/ ( * txvalue cgstrate) 100) 0.00))
	 (sgstamount (if intrastate (/ (* sgstrate txvalue) 100) 0.00))
	 (igstamount (if interstate (/ (* igstrate txvalue) 100) 0.00))
	 (totalitemvalue (+ txvalue (if intrastate (+ cgstamount sgstamount) igstamount))))
    (with-slots (taxablevalue sgst cgst igst sgstamt cgstamt igstamt totalitemval) lineitem
      (setf taxablevalue txvalue)
      (setf sgst sgstrate)
      (setf cgst cgstrate)
      (setf igst igstrate)
      (setf sgstamt sgstamount)
      (setf cgstamt cgstamount)
      (setf igstamt igstamount)
      (setf totalitemval totalitemvalue)
      lineitem)))

 ;This is a clean function with no side effect.
(defun create-odtinst-shopcart (order product product-qty unit-price discount-rate company-instance)
  "中文：购物车阶段构造一个瞬态 dod-order-items 实例（不入库），GST 各项先置 0，
   等结账时再 update-gst-for-order-lineitem 重算。order 为 nil 时 order-id 为 nil。
   返回：未持久化的 dod-order-items 对象。"
  (let* ((product-id (slot-value product 'row-id))
	 (vendor (product-vendor product))
	 (vendor-id (slot-value vendor 'row-id))
	 (tenant-id (slot-value company-instance 'row-id))
	 (order-id (if order (slot-value order 'row-id) nil)))
    (make-instance 'dod-order-items
		   :order-id order-id
		   :vendor-id vendor-id
		   :prd-id product-id
		   :unit-price unit-price
		   :disc-rate discount-rate
		   :prd-qty product-qty
		   :cgst 0.00
		   :cgstamt 0.00
		   :sgst 0.00
		   :sgstamt 0.00
		   :igst 0.00
		   :igstamt 0.00
		   :taxable-value 0.00
		   :totalitemval 0.00
		   :tenant-id tenant-id
		   :deleted-state "N")))

(defun search-odt-by-prd-id (prd-id list)
  "中文：在行项列表中按 prd-id 线性查找。
   注意：递归无 nil 终止条件，list 用尽时会触发 (slot-value nil ...) 异常。"
    (if (not (equal prd-id (slot-value (car list) 'prd-id))) (search-odt-by-prd-id prd-id (cdr list))
    (car list)))


(defun search-odt-by-order-id (order-id list)
  "中文：在行项列表中按 order-id 线性查找。同上：无 nil 终止条件，调用方需保证存在。"
   (if (not (equal order-id (slot-value (car list) 'order-id))) (search-odt-by-order-id  order-id (cdr list))
    (car list)))
