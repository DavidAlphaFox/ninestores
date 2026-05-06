;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：order 订单 —— 订单履约 / CRUD / 邮件 / 批处理（旧 dod-* MVC）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/order/dod-bl-ord.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：旧 MVC 体系下订单子系统的核心业务逻辑：
;;;;   - 履约推进：set-order-fulfilled（多卖家订单按子单逐步标 CMP，全部完成后主单 CMP；
;;;;     PRE 预付方式自动扣 wallet）
;;;;   - 查询：get-orders-by-company / get-orderids-for-vendor / get-orders-for-vendor /
;;;;     get-orders-for-vendor-by-shipped-date / get-all-orders-for-vendor /
;;;;     get-vendor-order-by-status / get-order-by-status / get-order-by-shipped-date /
;;;;     get-order-by-id / get-all-vendor-orders-by-orderid / get-vendor-orders-by-orderid /
;;;;     get-vendors-by-orderid / get-order-by-context-id / get-orders-for-customer /
;;;;     get-orders-by-req-date / get-latest-order-for-customer / get-max-order-id
;;;;   - 计数：count-vendor-orders-completed / -pending
;;;;   - 软删/恢复/取消：delete-order / cancel-order-by-customer (CCN) /
;;;;     cancel-order-by-vendor (VCN) / delete-vendor-orders / delete-orders /
;;;;     restore-deleted-orders
;;;;   - 创建：persist-order / create-order / create-order-from-pref /
;;;;     create-order-from-shopcart / create-daily-orders-for-company /
;;;;     persist-vendor-orders / save-order-items-in-db / save-vendor-orders-in-db
;;;;   - 邮件正文：create-order-email-content / -for-vendor / process-shipping-information-for-email
;;;;   - 商品类型：setAsSalesOrder / setAsServiceOrder
;;;;   - 库存：update-stock-inventory（粗粒度，扣减 units-in-stock）
;;;;   - 订阅周期单：prefpresent-p / run-daily-orders-batch（cron 触发）
;;;;
;;;; 主要导出（按业务热点）：
;;;;   set-order-fulfilled   — 多卖家履约推进 + wallet 扣款
;;;;   create-order-from-shopcart — 结账主入口（购物车 → 订单 + 行项 + 卖家子单 + 邮件 + Webpush）
;;;;   create-order-from-pref / create-daily-orders-for-company / run-daily-orders-batch
;;;;     — 订阅型周期订单 cron 流水线
;;;;
;;;; 关联：
;;;;   上游使用方：客户结账 / 卖家发货页 / 客户'我的订单'页 / 订阅 cron
;;;;   下游依赖：order/dod-dal-ord.lisp（DAL）、wallet BL（PRE 扣款）、
;;;;             webpush BL（推送通知）、email actor（异步发邮件）、
;;;;             upi BL（UTR 转账记录）、product BL（库存更新）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



(defun set-order-fulfilled ( value vendor order-instance company-instance)
    :documentation "value should be Y or N, followed by order instance and company instance.
   中文：履约推进核心函数。在多卖家订单中，把指定 vendor 的子单 + 所有归属该 vendor 的行项
   都标记为 CMP/履约（status='CMP', fulfilled=value）；同时记录发货日。
   联动：
     1) 当全订单的 pending 行项数 = 0（即所有 vendor 都完成）时，主单 dod-order 也标 CMP；
     2) PRE（预付钱包）方式下，按该 vendor 的小计扣减 wallet 余额；
     3) dod-reset-order-functions 重置缓存的订单函数列表。
   备注：函数仅在 (get-company order-instance) 与 company-instance 同名时执行 ——
        防止跨 tenant 误推进。"
  (let* ((vendor-order (get-vendor-order-instance (slot-value order-instance 'row-id) vendor))
	 ;;(order-id (slot-value order-instance 'row-id))
	 (customer (get-customer order-instance)) 
	 (payment-mode (slot-value order-instance 'payment-mode))
	 (wallet (get-cust-wallet-by-vendor customer vendor company-instance))
	 (vendor-order-items (get-order-items-for-vendor-by-order-id  order-instance vendor ))
	 (total   (reduce #'+  (mapcar (lambda (voitem)
					 (* (slot-value voitem 'unit-price) (slot-value voitem 'prd-qty))) vendor-order-items))))
        (if (equal (slot-value (get-company order-instance) 'name) (slot-value  company-instance 'name))
	(progn
	  ;; complete the order items for that particular vendor.  	
	  (mapcar (lambda (voitem)
		    (progn
		      (setf (slot-value voitem 'status) "CMP")
		      (setf (slot-value voitem 'fulfilled) value)
		      (update-order-item voitem)))   vendor-order-items)
	  ;; complete the vendor_order  
	  (if vendor-order 
	      (progn  
		(setf (slot-value vendor-order 'status) "CMP")
		(setf (slot-value vendor-order 'fulfilled) value)
		(setf (slot-value vendor-order 'shipped-date) (clsql-sys:get-date))
		(update-order vendor-order)))
	  ;; Complete the main order only if all other vendor-order-items have been completed. 
	  (if (equal (count-order-items-pending order-instance company-instance) 0 ) 
	      (progn (setf (slot-value order-instance 'order-fulfilled) value)
		     (setf (slot-value order-instance 'shipped-date) (clsql-sys:get-date))
		     (setf (slot-value order-instance 'status ) "CMP")
		     (update-order order-instance)))
	  (dod-reset-order-functions vendor company-instance)
	  ;; Deduct the money from the wallet. 
	  (if (equal payment-mode "PRE") (deduct-wallet-balance total wallet))))))

    
    


(defun get-orders-by-company (company-instance &optional (fulfilled "N"))
  "中文：列出某 tenant 下指定履约状态（默认未履约 N）的全部 dod-order。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
      (clsql:select 'dod-order  :where [and [= [:deleted-state] "N"]
	  [= [:tenant-id] tenant-id]
	  [= [:order-fulfilled] fulfilled]]    :caching *dod-debug-mode* :flatp t )))


(defun count-vendor-orders-completed (vendor order company)
  "中文：统计某 vendor 在某主单下已完成（CMP+履约）的子单数。
   备注：from 子句 'dod-vendor-order' 系单数（非实际表 dod-vendor-orders）—— 推测：原作者笔误，
   该函数运行时可能报无表错误。"
 (let ((tenant-id (slot-value company 'row-id)) 
       (vendor-id (slot-value vendor 'row-id))
       (order-id (slot-value order 'row-id)))
    
    (first (clsql:select [count [*]] :from 'dod-vendor-order :where 
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:status] "CMP"]
		[= [:fulfilled] "Y"]
		[= [:vendor-id] vendor-id]
		[=[:order-id] order-id]]    :caching nil :flatp t ))))


(defun count-vendor-orders-pending (vendor order company)
  "中文：统计某 vendor 在某主单下待处理（PEN+未履约）的子单数。
   同上：from 子句 'dod-vendor-order' 单数（推测笔误）。"
 (let ((tenant-id (slot-value company 'row-id)) 
       (vendor-id (slot-value vendor 'row-id))
       (order-id (slot-value order 'row-id)))
    
    (first (clsql:select [count [*]] :from 'dod-vendor-order :where 
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:status] "PEN"]
		[= [:fulfilled] "N"]
		[= [:vendor-id] vendor-id]
		[=[:order-id] order-id]]    :caching nil :flatp t ))))

(defun get-vendor-order-instance (order-id vendor)
  "中文：按 (order-id, vendor-id) 取该 vendor 在某主单下的子单（一对一）。"
  (let ((vendor-id (slot-value vendor  'row-id)))
    (car (clsql:select 'dod-vendor-orders :where
		       [and [= [:vendor-id] vendor-id]
		       [= [:order-id] order-id]] 
		       :caching nil :flatp t))))



(defun get-orderids-for-vendor (vendor-instance  company &optional (fulfilled "N")  (recordsfordays 30))
  "中文：取卖家最近 recordsfordays 天内的子单 order-id 列表（窗口在 today±N 之间）。
   ORDER-BY row-id DESC。返回：order-id 列表。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (strfromdate (get-date-string-mysql (clsql-sys:date- (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays))))
	 (strtodate (get-date-string-mysql (clsql-sys:date+ (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays))))
	 (vendor-id (slot-value vendor-instance 'row-id)))
	 (clsql:select [order-id] :from  'dod-vendor-orders :where
		       [and [= [:tenant-id] tenant-id]
		       [between [:created] strfromdate strtodate ]
		       [= [:vendor-id] vendor-id]
		       [= [:deleted-state] "N"]
		       [= [:fulfilled] fulfilled]]  :order-by '( ([row-id] :desc)) 
		       :caching nil :flatp t)))


(defun get-orders-for-vendor (vendor-instance   rowcount company &optional   (fulfilled "N")  (recordsfordays 30))
  "中文：取卖家最近 recordsfordays 天内的子单（dod-vendor-orders）实例列表（最多 rowcount 条）。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (strfromdate (get-date-string-mysql (clsql-sys:date- (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays))))
	 (strtodate (get-date-string-mysql (clsql-sys:date+ (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays))))
	 (vendor-id (slot-value vendor-instance 'row-id)))
	 (clsql:select  'dod-vendor-orders :where
			[and [= [:tenant-id] tenant-id]
			[between [:created] strfromdate strtodate ]
			[= [:vendor-id] vendor-id]
			[= [:deleted-state] "N"]
			[= [:fulfilled] fulfilled]] :limit rowcount :order-by '( ([row-id] :desc)) 
			:caching nil :flatp t)))
    



(defun get-orders-for-vendor-by-shipped-date (vendor-instance shipped-date company &optional (fulfilled "N"))
  "中文：按发货日精确匹配，取卖家在该日期的子单。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (vendor-id (slot-value vendor-instance 'row-id)))

	   (clsql:select 'dod-vendor-orders :where
	    [and [= [:tenant-id] tenant-id]
		  [= [:vendor-id] vendor-id]
		  [= [:shipped-date] shipped-date]
		  [= [:fulfilled] fulfilled]] 
			  :caching nil :flatp t)))



(defun get-all-orders-for-vendor (vendor-instance &optional (rowcount "NULL"))
  "中文：取卖家全部子单对应的主单 dod-order 列表（不限时间窗口）。
   先查 vendor_orders 拿 order-id 列表，再逐条 get-order-by-id。
   备注：rowcount 默认 'NULL' 字符串（推测：CLSQL :limit 当作无限制）。"
  (let* ((tenant-id (slot-value vendor-instance 'tenant-id))
	 (company (car (get-vendor-company vendor-instance)))
	 (vendor-id (slot-value vendor-instance 'row-id))
	 (ordidlist     (clsql:select  [order-id] :from  'dod-vendor-orders :where
	    [and [= [:tenant-id] tenant-id]
		  [= [:vendor-id] vendor-id]] :limit rowcount
		  
			  :caching nil :flatp t)))
    (remove nil (mapcar (lambda (ord-id) 
			  (get-order-by-id ord-id company)) ordidlist))))



(defun get-vendor-order-by-status (order company-instance fulfilled)
  "中文：按 (order-id, fulfilled) 在指定 tenant 下查 vendor_orders 单条。
   注：where 条件用了 :order-fulfilled，但实际表列名是 :fulfilled —— 推测：原作者笔误。"
 (let ((tenant-id (slot-value company-instance 'row-id))
       (order-id (slot-value order 'row-id)))
  (car (clsql:select 'dod-vendor-orders  :where
		     [and 
		     [= [:order-fulfilled] fulfilled]
		     [= [:tenant-id] tenant-id]
		     [=[:order-id] order-id]]    :caching *dod-debug-mode* :flatp t ))))


(defun get-order-by-status (id company-instance fulfilled)
  "中文：按 (row-id, order-fulfilled, tenant) 查主单。"
 (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-order  :where
		     [and [= [:deleted-state] "N"]
		     [= [:order-fulfilled] fulfilled]
		     [= [:tenant-id] tenant-id]
		     [=[:row-id] id]]    :caching *dod-debug-mode* :flatp t ))))
  




(defun get-order-by-shipped-date (id shipped-date company-instance)
  "中文：按 (row-id, shipped-date) 查主单（用于卖家按发货日检索）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
	 (car (clsql:select 'dod-order  :where
		     [and [= [:deleted-state] "N"]
		     [= [:shipped-date] shipped-date]
		     [= [:tenant-id] tenant-id]
		     [=[:row-id] id]]    :caching *dod-debug-mode* :flatp t ))))
  


(defun get-order-by-id (id company-instance)
  "中文：按主键在 tenant 内查主单。返回：dod-order / nil。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-order  :where
		     [and [= [:deleted-state] "N"]
		     [= [:tenant-id] tenant-id]
		     [=[:row-id] id]]    :caching nil :flatp t ))))

(defun get-all-vendor-orders-by-orderid (id company-instance)
  "中文：按主单 id 在 tenant 内取所有 vendor 子单（多卖家订单的子单集合）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
	
    (clsql:select 'dod-vendor-orders  :where
	   [and [= [:tenant-id] tenant-id]
	   [=[:deleted-state] "N"]
	   [=[:order-id] id]]    :caching nil :flatp t )))


(defun get-vendor-orders-by-orderid (id vendor company-instance)
  "中文：按 (order-id, vendor-id, tenant) 取该 vendor 在主单下的子单（一对一）。
   函数名复数有误导，实际只返回 car（单条）。"
  (let ((tenant-id (slot-value company-instance 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
	
    (car (clsql:select 'dod-vendor-orders  :where
	   [and [= [:tenant-id] tenant-id]
	   [=[:deleted-state] "N"]
	   [= [:vendor-id] vendor-id]
	   [=[:order-id] id]]    :caching nil :flatp t ))))


(defun get-vendors-by-orderid (order-id company-instance)
  "中文：取主单涉及的所有 vendor。先查 vendor_orders 拿 vendor-id 列表，再 select-vendor-by-id。"
  (let* ((tenant-id (slot-value company-instance 'row-id))
	(vendorids (clsql:select [:vendor-id] :from 'dod-vendor-orders :where
		      [and 
		      [=[:deleted-state] "N"]
		      [=[:order-id] order-id]
		      [= [:tenant-id] tenant-id]] :caching nil :flatp t)))

	(mapcar (lambda (vendor-id) (select-vendor-by-id vendor-id)) vendorids))) 


(defun get-order-by-context-id (context-id company-instance)
  "中文：按 context-id 在 tenant 内查主单（context-id = 创建时生成的 UUID 字符串，幂等定位用）。"
 (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-order  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:context-id] context-id]]    :caching nil :flatp t ))))

(defun setAsSalesOrder (order)
  :documentation "Sets the order type as Sales Order.
   中文：把订单标记为销售单（order-type='SALE'）并写库。"
  (setf (slot-value order 'order-type) "SALE")
  (update-order order))

(defun setAsServiceOrder (order)
  :documentation "Sets the order type as Service Order.
   中文：把订单标记为服务单（order-type='SRVC'）并写库。"
  (setf (slot-value order 'order-type) "SRVC")
  (update-order order))



(defun get-orders-for-customer (customer &optional (recordsfordays 30))
  "中文：取客户最近 recordsfordays 天内的订单（窗口为 today±N），按 row-id DESC 排序。"
  (let ((tenant-id (slot-value customer 'tenant-id))
	(strfromdate (get-date-string-mysql (clsql-sys:date- (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays))))
	(strtodate (get-date-string-mysql (clsql-sys:date+ (clsql-sys:get-date) (clsql-sys:make-duration :day recordsfordays))))
	(cust-id (slot-value customer 'row-id)))
    (clsql:select 'dod-order  :where
		  [and [= [:deleted-state] "N"]
		  [between [:created] strfromdate strtodate ]
		  [= [:tenant-id] tenant-id]
		  [=[:cust-id] cust-id ]] :order-by '(([row-id] :desc))
		  :caching nil :flatp t )))

(defun get-orders-by-req-date (req-date company-instance)
  "中文：按期望送达日（req-date）在 tenant 内取订单。"
(let ((tenant-id (slot-value company-instance 'row-id)))
(clsql:select 'dod-order  :where
    [and [= [:deleted-state] "N"]
    [= [:tenant-id] tenant-id]
    [=[:req-date] req-date]]
		:caching nil :flatp t )))


(defun get-latest-order-for-customer (customer)
  "中文：取客户最新订单（按 max(row-id) 子查询定位）。"
  (let ((tenant-id (slot-value customer 'tenant-id))
	(cust-id (slot-value customer 'row-id)))
(car (clsql:select 'dod-order  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:cust-id] cust-id ]
		[= [:row-id] (get-max-order-id cust-id tenant-id)]]    :caching nil :flatp t ))))
  
(defun get-max-order-id (customer-id tenant-id)
  "中文：返回客户在 tenant 内未删除订单的最大 row-id（聚合查询）。"
  (clsql:select [max [row-id]] :from 'dod-order  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:cust-id] customer-id]]    :caching nil :flatp t ))
  



(defun update-order (order-instance); This function has side effect of modifying the database record.
  "中文：把订单实例的所有字段写回数据库（UPDATE）。"
  (clsql:update-records-from-instance order-instance))



(defun delete-order( order-instance )
  "中文：软删单条订单（deleted-state='Y'）。"
  (progn
    (setf (slot-value order-instance 'deleted-state) "Y")
    (clsql:update-record-from-slot order-instance 'deleted-state)))


(defun cancel-order-by-customer( order-instance )
  "中文：客户取消订单：status='CCN' (CANCELLED BY CUSTOMER)。"
  (progn
    (setf (slot-value order-instance 'status) "CCN")
    (clsql:update-record-from-slot order-instance 'status)))


(defun cancel-order-by-vendor( order-instance )
  "中文：卖家取消订单：status='VCN' (CANCELLED BY VENDOR)。"
  (progn
    (setf (slot-value order-instance 'status) "VCN")
    (clsql:update-record-from-slot order-instance 'status)))


(defun delete-vendor-orders ( list)
  "中文：批量软删 vendor_orders 子单（参数 list 为子单实例列表，非 id 列表）。"
    (mapcar (lambda (vo)  (progn
			    (setf (slot-value vo 'deleted-state) "Y")
			    (clsql:update-record-from-slot vo  'deleted-state))) list ))


(defun delete-orders ( orderid-list company-instance)
  "中文：按 row-id 批量软删主单（限定 tenant）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodorder (car (clsql:select 'dod-order :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
			  (setf (slot-value dodorder 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodorder  'deleted-state))) orderid-list )))


(defun restore-deleted-orders ( list tenant-id )
  "中文：批量把软删订单恢复（deleted-state='N'）。注意此函数直接收 tenant-id 整数，
   而非 company-instance（与 delete-orders 不一致）。"
(mapcar (lambda (id)  (let ((dodorder (car (clsql:select 'dod-order :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching nil))))
    (setf (slot-value dodorder 'deleted-state) "N")
    (clsql:update-record-from-slot dodorder 'deleted-state))) list ))

  

  
(defun persist-order(modelfunc)
  "中文：底层订单 INSERT。从多值闭包 modelfunc 取所有字段构造 dod-order 并写库。
   新订单默认 order-fulfilled='N'、status='PEN'、is-converted-to-invoice='N'、is-cancelled='N'。
   备注：clsql 自增 row-id 由 update-records-from-instance 在 INSERT 后回填。"
  (multiple-value-bind
	(order-date request-date shipped-date expected-delivery-date shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship storepickupenabled gstnumber gstorgname order-amt shipping-cost total-discount total-tax payment-mode comments context-id customer-id order-type  order-source customer-name tenant-id) (funcall modelfunc)
    (clsql:update-records-from-instance (make-instance 'dod-order
						       :ord-date order-date
						       :req-date request-date
						       :shipped-date shipped-date
						       :expected-delivery-date expected-delivery-date
						       :shipaddr shipaddr
						       :shipzipcode shipzipcode
						       :shipcity shipcity
						       :shipstate shipstate
						       :billaddr billaddr
						       :billzipcode billzipcode
						       :billcity billcity
						       :billstate billstate
						       :billsameasship billsameasship
						       :storepickupenabled storepickupenabled
						       :gstnumber gstnumber
						       :gstorgname gstorgname
						       :order-fulfilled "N"
						       :order-amt order-amt
						       :shipping-cost shipping-cost
						       :total-discount total-discount
						       :total-tax total-tax
						       :payment-mode payment-mode
						       :comments comments
						       :context-id context-id
						       :cust-id customer-id
						       :status "PEN"
						       :deleted-state "N" 
						       :is-converted-to-invoice "N"
						       :is-cancelled "N"
						       :order-type order-type
						       :order-source order-source
						       :customer-name customer-name
						       :tenant-id tenant-id)))) 


(defun create-order (modelfunc)
  "中文：业务级创建订单：解包 customer / company → 提取 cust-id / tenant-id → 调 persist-order。
   备注：modelfunc 的字段顺序与 persist-order 略有不同（contains customer 实例而非 customer-id）。"
  (multiple-value-bind
	(order-date request-date shipped-date expected-delivery-date shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship orderpickupinstore gstnumber gstorgname order-amt shipping-cost total-discount total-tax payment-mode comments context-id customer order-type  order-source customer-name company) (funcall modelfunc) 
  (let ((customer-id (slot-value  customer 'row-id) )
	(tenant-id (slot-value company 'row-id)))
    (persist-order (function (lambda ()
		     (values order-date request-date shipped-date expected-delivery-date shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship orderpickupinstore gstnumber gstorgname order-amt shipping-cost total-discount total-tax payment-mode comments context-id customer-id order-type  order-source customer-name tenant-id)))))))


(defun create-order-from-pref (order-pref-list order-date request-date ship-date ship-address order-amt discount shipping-cost orderpickupinstore customer-instance company-instance)
  "中文：订阅周期单创建：根据客户的订单偏好（order-pref-list = dod-order-subscription 列表）
   生成一笔正式订单。
   流程：
     1) 生成 UUID context-id；create-order 写主单（PRE 预付，order-pref 不含 vendor 信息）；
     2) 取回主单后，按 prefpresent-p 判断 request-date 落在哪些 weekday，过滤适用偏好；
     3) 为每个适用偏好按当前价创建行项（create-order-items）；
     4) 把所有涉及 vendor 取出，每个 vendor 一条 vendor_orders 子单（status='Y'，已履约）。
   备注：调用 create-order 的字段顺序与 create-order 自身的解包顺序不一致 ——
        推测：原作者在重构时未对齐参数列表。运行实例上行为可能与命名不符。"
  (let ((uuid (uuid:make-v1-uuid ))
	(tenant-id (slot-value company-instance 'row-id)))
      (progn  (create-order (function (lambda () (values order-date customer-instance request-date ship-date ship-address (print-object uuid nil) order-amt shipping-cost "PRE" nil orderpickupinstore  company-instance))))
	      (let ((order (get-order-by-context-id (print-object uuid nil) company-instance))
		    (vendors (get-opref-vendorlist order-pref-list))
		    (cust-id (slot-value customer-instance 'row-id)))
		(mapcar (lambda (preference)
			  (let* ((prd (get-opf-product preference))
				 (current-price (slot-value prd 'current-price))
				 (prd-qty (slot-value preference 'prd-qty)))
			    (if (prefpresent-p preference (clsql-sys:date-dow request-date)) (create-order-items order prd  prd-qty current-price discount company-instance)))) order-pref-list)
		
					; Create one row per vendor in the vendor_orders table. 
		(mapcar (lambda (vendor) 
			  (let* ((vitems (filter-opref-items-by-vendor vendor order-pref-list))
				 (total (get-opref-items-total-for-vendor vendor vitems))) 
			    
			    (persist-vendor-orders (slot-value order 'row-id) cust-id (slot-value vendor 'row-id) tenant-id order-date request-date ship-date ship-address "PREPAID"  total shipping-cost "Y")))  vendors)
      
		))))


(defun prefpresent-p (preference day)
  "中文：判断订阅偏好是否在指定 weekday（0=Sun..6=Sat）激活。
   逐 sun/mon/.../sat 标志位转成数字 lst，若 day ∈ lst 则返回 T。"
    (let  ((lst  (list (if (equal (slot-value preference 'sun) "Y") 0 )
	     (if (equal (slot-value preference 'mon) "Y")  1)
		(if (equal (slot-value preference 'tue) "Y") 2)
	     (if (equal (slot-value preference 'wed) "Y") 3)
		(if (equal (slot-value preference 'thu) "Y") 4)
	     (if (equal (slot-value preference 'fri) "Y") 5) 
		(if (equal (slot-value preference 'sat) "Y") 6))))
	(if (member day lst) t nil)))


(defun create-order-email-content (vproducts vitems customer order-id shipping-cost sub-total paymentmode)
  "中文：拼装客户订单确认邮件正文 HTML。
   三段：客户/订单信息表 + 商品列表（with 价格/数量）+ 运费 / 小计 / 总计页脚。"
  (with-slots (zipcode address phone email city state name company) customer
    (let* ((currsymbol (get-currency-html-symbol (get-account-currency company)))
	   (headerstr (with-html-table "" (list "Particulars" "Details") "1"
			(:tr (:td (cl-who:str (format nil "Order No")))
			     (:td (cl-who:str (format nil "~A" order-id))))
			(:tr (:td (cl-who:str (format nil "Payment Mode")))
			     (:td (cl-who:str (format nil "~A" paymentmode))))
			(:tr (:td (cl-who:str (format nil "Name")))
			     (:td (cl-who:str (format nil "~A" name))))
			(:tr (:td (cl-who:str (format nil "Address")))
			     (:td (cl-who:str (format nil "~A, ~A, ~A, ~A" address city zipcode state))))
			(:tr (:td (cl-who:str (format nil "Phone")))
			     (:td (cl-who:str (format nil "~A" phone))))
			(:tr (:td (cl-who:str (format nil "Email")))
			     (:td (cl-who:str (format nil "~A" email))))))
	   (datastr (ui-list-shopcart-for-email vproducts vitems))
	   (footer (cl-who:with-html-output-to-string (*standard-output* nil)
		     (:tr (:td :align "right"
			       (:span  :class "label label-default" (cl-who:str (format nil "Shipping: ~A ~$" currsymbol shipping-cost)))))
		     (:tr (:td :align "right"
			       (:span  :class "label label-default" (cl-who:str (format nil "Sub Total: ~A ~$" currsymbol sub-total)))))
		     (:tr (:td :align "right"
			       (:h2  (:span  :class "label label-default" (cl-who:str (format nil "Total = ~A ~$" currsymbol (+ shipping-cost sub-total))))))))))
      ;;(hhub-log-message  (format nil "~A~A~A" headerstr datastr footer))
      (format nil "~A~A~A" headerstr datastr footer))))

(defun create-order-email-content-for-vendor (vproducts vitems customer order-id shipping-info total)
  "中文：拼装卖家收到新订单的邮件正文 HTML（含运输信息表 / 含 Total 印章）。"
  (with-slots (zipcode address phone email city state name) customer
    (let* ((headerstr (with-html-table "" (list "Particulars" "Details") "1"
			(:tr (:td (cl-who:str (format nil "Order No")))
			     (:td (cl-who:str (format nil "~A" order-id))))
			(:tr (:td (cl-who:str (format nil "Name")))
			     (:td (cl-who:str (format nil "~A" name)))
			     (:tr (:td (cl-who:str (format nil "Address")))
				  (:td (cl-who:str (format nil "~A, ~A, ~A, ~A" address city zipcode state))))
			     (:tr (:td (cl-who:str (format nil "Phone")))
				  (:td (cl-who:str (format nil "~A" phone))))
			     (:tr (:td (cl-who:str (format nil "Email")))
				  (:td (cl-who:str (format nil "~A" email)))))))
	   (datastr (ui-list-shopcart-for-email vproducts vitems))
	   (footer (cl-who:with-html-output-to-string (*standard-output* nil)
		     (:tr (:td :align "right"
			       (:h2  (:span  :class "label label-default" (cl-who:str (format nil "Total = Rs ~$" total))))))))
	   (shipstr (process-shipping-information-for-email shipping-info)))
      ;;(hhub-log-message  (format nil "~A~A~A" headerstr datastr footer))
      (format nil "~A~A~A~A" headerstr datastr footer shipstr))))

(defun process-shipping-information-for-email (shipping-info)
  "中文：把多条运输方案（每条是一个嵌套列表，nth 索引取字段）渲染成 HTML 表格。
   nth 索引含义见各 shipping 模块 BL 函数（推测：0=Provider, 8=Weight Limit, 9=Rate, 10=Zone, 11=Timeline）。"
  (when shipping-info
    (with-html-table "" (list "Provider" "Weight Limit" "Rate" "Zone" "Timeline") "1"  
      (mapcar (lambda (shipinfo)
		(cl-who:htm
		 (:tr
		  (:td (cl-who:str (nth 0 shipinfo)))
		  (:td (cl-who:str (nth 8 shipinfo)))
		  (:td (cl-who:str (nth 9 shipinfo)))
		  (:td (cl-who:str (nth 10 shipinfo)))
		  (:td (cl-who:str (nth 11 shipinfo)))))) shipping-info))))
  


(defun save-order-items-in-db (order order-items products company-instance)
  "中文：把购物车 order-items（瞬态 dod-order-items 实例）批量持久化到 DOD_ORDER_ITEMS。
   同时调 update-stock-inventory 扣减商品库存。"
  (mapcar (lambda (odt)
	    (let* ((prd (search-item-in-list 'row-id (slot-value odt 'prd-id) products)))
		   (with-slots (unit-price disc-rate prd-qty sgst sgstamt cgst cgstamt igst igstamt taxablevalue totalitemval) odt 
		     (create-order-items order prd  prd-qty unit-price disc-rate sgst sgstamt cgst cgstamt igst igstamt taxablevalue totalitemval company-instance)
		     (update-stock-inventory prd prd-qty)))) order-items))


(defun update-stock-inventory (product prd-qty)
  :description "A rudimentary stock inventory update function.
   中文：粗粒度库存更新：units-in-stock = max(0, units-in-stock - prd-qty)，写库。
   备注：原作者注释 'rudimentary' —— 这是简化实现，没有库存预留 / 多仓位 / 锁定机制；
        新版仓储能力请见 warehouse 模块。"
  (let* ((units-in-stock (slot-value product 'units-in-stock))
	(updated-units-in-stock  (if (and units-in-stock (> units-in-stock 0)) (- units-in-stock  prd-qty) 0)))
    (setf (slot-value product 'units-in-stock) updated-units-in-stock)
    (update-prd-details product)))


(defun save-vendor-orders-in-db (order order-date request-date ship-date ship-address payment-mode  orderpickupinstore  order-items products  shipping-info shipping-cost  guest-customer customer-instance company-instance utrnum)
  "中文：把购物车的 order-items 按 vendor 拆分，逐个 vendor 写一条 vendor_orders 子单，
   并触发：
     1) UPI 转账（utrnum 非空时）—— save-upi-transaction；
     2) 卖家邮件（with HTML 订单详情 + shipping-info）；
     3) Webpush 浏览器推送。
   GUEST 客户用 guest-customer 占位（不暴露 PII）。"
  (let* ((order-id (slot-value order 'row-id))
	 (cust-id (slot-value customer-instance 'row-id))
	 (cust-type (slot-value customer-instance 'cust-type))
	 (vendors (get-shopcart-vendorlist order-items))
	 (tenant-id (slot-value company-instance 'row-id)))
    (mapcar (lambda (vendor) 
	      (let* ((vendor-email (slot-value vendor 'email))
		     (vitems (filter-order-items-by-vendor vendor order-items))
		     (vproducts (mapcar (lambda (odt)
					  (let ((prd-id (slot-value odt 'prd-id)))
					    (search-item-in-list 'row-id prd-id products))) vitems))
		     (total (get-order-items-total-for-vendor vendor vitems))
		     (vendor-id (slot-value vendor 'row-id))
		     (custinst (if (equal cust-type "GUEST") guest-customer customer-instance))
		     (order-disp-str (create-order-email-content vproducts vitems custinst order-id shipping-cost total payment-mode))
		     (shipstr (process-shipping-information-for-email shipping-info))) 
      		
		(persist-vendor-orders order-id cust-id vendor-id  tenant-id order-date request-date ship-date ship-address payment-mode total shipping-cost orderpickupinstore)
		;; Save the UPI Transaction 
		(when utrnum (save-upi-transaction total utrnum (format nil "#ORD:~A" order-id) custinst vendor company-instance (slot-value custinst 'phone)))
		;;Send a mail to the vendor
		(when vendor-email (send-order-mail vendor-email (format nil "You have received new order ~A" order-id)  (format nil "~A~A" order-disp-str shipstr)))
		;; Send a push notification on the vendor's browser
		(send-webpush-message vendor (format nil "You have received a new order ~A" order-id))))  vendors)))


(defun create-order-from-shopcart (modelfunc)
  "中文：购物车结账主入口。
   流程：
     1) 用 UUID 生成 context-id；
     2) create-order 写主单 → get-order-by-context-id 取回；
     3) save-order-items-in-db 写行项 + 扣库存；
     4) save-vendor-orders-in-db 按 vendor 拆子单 + UPI/邮件/Webpush。
   返回：新建主单的 row-id。"
  (multiple-value-bind
	(order-items shopcart-products shipping-info temp-customer utrnum order-date request-date shipped-date expected-delivery-date shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship orderpickupinstore gstnumber gstorgname order-amt shipping-cost total-discount total-tax payment-mode comments customer order-type  order-source customer-name company) (funcall modelfunc)
    (let ((context-id (uuid:make-v1-uuid)))
      ;; Create an order in the database. 
      (create-order (function (lambda ()
		      (values order-date request-date shipped-date expected-delivery-date shipaddr shipzipcode shipcity shipstate billaddr billzipcode billcity billstate billsameasship orderpickupinstore gstnumber gstorgname order-amt shipping-cost total-discount total-tax payment-mode comments (print-object context-id nil) customer order-type  order-source customer-name company))))
      (let* ((order (get-order-by-context-id (print-object context-id nil) company))
	     (order-id (slot-value order 'row-id)))
	;; Create the order-items and also update the current products in stock. 
	(save-order-items-in-db order order-items shopcart-products company)
	;; Create one row per vendor in the vendor_orders table. Send an order received email to each vendor. 
	(save-vendor-orders-in-db order  order-date request-date shipped-date shipaddr payment-mode  orderpickupinstore  order-items shopcart-products  shipping-info shipping-cost  temp-customer customer company utrnum)
    order-id))))
   
(defun persist-vendor-orders(order-id cust-id vendor-id tenant-id ord-date req-date ship-date ship-address payment-mode order-amt shipping-cost orderpickupinstore)
  "中文：底层 vendor_orders INSERT。新子单默认 status='PEN'、fulfilled='N'、deleted-state='N'。"
 (clsql:update-records-from-instance (make-instance 'dod-vendor-orders
					 :order-id order-id
					 :cust-id cust-id
					 :vendor-id vendor-id
					 :status "PEN"
					 :fulfilled "N"
					 :ord-date ord-date 
					 :req-date req-date
					 :shipped-date ship-date
					 :ship-address ship-address
					 :payment-mode payment-mode 
					 :order-amt order-amt
					 :shipping-cost shipping-cost
					 :storepickupenabled orderpickupinstore
					 :deleted-state "N"
					 :tenant-id tenant-id )))



(defun create-daily-orders-for-company (&key company-id odtstr reqstr)
    :documentation "odtstr and reqstr are of the format \"dd/mm/yyyy\".
   中文：为某 company 的全部客户在指定日期生成订阅型订单。
   行为：取 company → 客户列表 → 每个客户的偏好（按 reqstr 的 weekday 过滤）→ create-order-from-pref。
   被 cron 通过 run-daily-orders-batch 触发。"
    (let* ((orderdate (get-date-from-string odtstr))
	      (requestdate (get-date-from-string reqstr))
	      (dodcompany (select-company-by-id company-id))
	      (customers (select-customers-for-company dodcompany)))
					;Get a list of all the customers belonging to the current company. 
					; For each customer, get the order preference list and pass to the below function.
	      (mapcar (lambda (customer)
			  (let ((custopflist (remove-if-not (lambda (preference)
							      (let  ((lst  (list (if (equal (slot-value preference 'sun) "Y") 0 )
										 (if (equal (slot-value preference 'mon) "Y")  1)
										 (if (equal (slot-value preference 'tue) "Y") 2)
										 (if (equal (slot-value preference 'wed) "Y") 3)
										 (if (equal (slot-value preference 'thu) "Y") 4)
										 (if (equal (slot-value preference 'fri) "Y") 5) 
										 (if (equal (slot-value preference 'sat) "Y") 6))))
								(if (member (clsql-sys:date-dow requestdate) lst) t nil)))
							    (get-opreflist-for-customer customer))))
			    (if custopflist  (create-order-from-pref custopflist orderdate requestdate nil (slot-value customer 'address) 0.0 0.0 0.0 "N" customer dodcompany)) )) customers)))



(defun run-daily-orders-batch (numdays)
  :documentation "datestr is of the format \"dd/mm/yyyy\".
   中文：cron 入口（参考 installation/cronjobs.txt 的 'rundailyordersbatch'）。
   行为：把今天起未来 numdays 天，对每个系统 company 调 create-daily-orders-for-company 生成订单。"
  (let ((cmplist (get-system-companies)))
    (loop for i from 1 to numdays do (mapcar (lambda (cmp) 
	      (let ((id (slot-value cmp 'row-id)))
		(create-daily-orders-for-company :company-id id :odtstr (get-date-string (clsql-sys:get-date)) :reqstr (get-date-string (clsql-sys:date+ (clsql-sys:get-date) (clsql-sys:make-duration :day i)))))) cmplist)))) 



