;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：order 订单 —— 卖家子单（旧 dod-* MVC）
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/order/dod-dal-ord.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义"按卖家拆分的订单子单"实体 dod-vendor-orders 的 CLSQL view-class。
;;;;       一笔多卖家主单（dod-order）会按 vendor 拆分成多条 dod-vendor-orders 子单，
;;;;       履约/状态/收款都在子单粒度推进，全部子单完成后主单才标记 CMP。
;;;;       注意：order 模块同时存在"旧 dod-* MVC"和"新 nst-* DDD/Hexagonal"两套，
;;;;             本文件属于前者。新风格的实体见 nst-dal-Order.lisp / nst-dal-OrderItem.lisp。
;;;;
;;;; 主要导出：
;;;;   dod-vendor-orders   — 卖家子单实体（与 DOD_VENDOR_ORDERS 表 1:1 映射）
;;;;
;;;; 关联：
;;;;   上游使用方：order/dod-bl-ord.lisp（CRUD + 履约逻辑）、
;;;;               order/dod-ui-ord.lisp（UI 控制器）、
;;;;               invoice 模块（按子单生成发票）
;;;;   下游依赖：dod-cust-profile / dod-order / dod-vend-profile / dod-company
;;;; ============================================================================

(in-package :nstores)
;;(clsql:file-enable-sql-reader-syntax)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;; CLASS - DOD-VENDOR-ORDERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ----------------------------------------------------------------------------
;; 实体：dod-vendor-orders
;; 表：DOD_VENDOR_ORDERS
;; 含义：多卖家订单中"某 vendor 的子单"。主单 dod-order 通过 order-id 关联多条子单。
;; 关键字段：
;;   row-id              主键
;;   cust-id             外键 → dod-cust-profile（下单客户）
;;   order-id            外键 → dod-order（主单）
;;   vendor-id           外键 → dod-vend-profile（承接的卖家）
;;   ord-date / req-date / shipped-date  下单日 / 期望送达日 / 实际发货日
;;   ship-*              收货地址快照（地址/邮编/城市/州/国家）
;;   bill-*              账单地址快照
;;   billsameasship      Y/N 账单是否同收货
;;   order-amt           子单金额（不含运费）
;;   shipping-cost       运费
;;   payment-mode        支付方式（COD/PRE/UPI 等 3 字符码）
;;   storepickupenabled  Y/N 是否门店自提
;;   fulfilled           Y/N 履约完成标志
;;   status              子单状态码（PEN/CMP/CAN/PRO 等 3 字符）
;;   deleted-state       N/Y 软删
;;   comments            备注
;;   tenant-id           多租户隔离键 → dod-company.row-id
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vendor-orders ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)

   (cust-id
    :type integer
    :initarg :cust-id)
   (customer 
    :accessor get-customer 
    :db-kind :join
    :db-info (:join-class dod-cust-profile
			  :home-key cust-id
			  :foreign-key row-id
			  :set nil))
   
   (order-id
    :TYPE integer
    :initarg :order-id)
   
   (order
    :accessor get-order
    :db-kind :join
    :db-info (:join-class dod-order
			  :home-key order-id
			  :foreign-key row-id
			  :set nil))
   
   (vendor-id
    :db-constraints :NOT-NULL
    :type integer
    :initarg :vendor-id)
   
   (vendorobject
    :accessor odt-vendorobject
    :db-kind :join
    :db-info (:join-class dod-vend-profile
			  :home-key vendor-id
			  :foreign-key row-id
			  :set nil))
   
   (ord-date
    :accessor order-date
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE clsql:date
    :initarg :ord-date)
   
   (req-date
    :accessor get-requested-date
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE clsql:date
    :initarg :req-date)
   
   (shipped-date
    :accessor get-shipped-date
    :TYPE clsql:date
    :INITARG :shipped-date)   
   
   
   (ship-address
    :ACCESSOR get-ship-address 
    :type (string 200)
    :initarg :ship-address)

   (shipzipcode
    :accessor get-shipzipcode
    :type (string 10)
    :initarg :shipzipcode)

   (shipcity
    :accessor get-shipcity
    :type (string 50)
    :initarg :shipcity)
   (shipstate
    :accessor get-shipstate
    :type (string 50)
    :initarg :shipstate)
   (billaddress
    :accessor get-billaddress
    :type (string 200)
    :initarg :billaddress)
   (billzipcode
    :accessor get-billzipcode
    :type (string 10)
    :initarg :billzipcode)
   (billcity
    :accessor get-billcity
    :type (string 50)
    :initarg :billcity)
   (billstate
    :accessor get-billstate
    :type (string 50)
    :initarg :billstate)
   
   (country
    :accessor get-country
    :type (string 50)
    :initarg :country)
   
   (billsameasship
    :accessor get-billsameasship
    :type (string 1)
    :initarg :billsameasship)
   
   (order-amt
    :type float
    :initarg :order-amt)

   (shipping-cost
    :type float
    :initarg :shipping-cost)

   
   (payment-mode
    :type (string 3)
    :initarg :payment-mode)
   
   (storepickupenabled
     :type (string 1)
     :initarg :storepickupenabled)
    
   (fulfilled
    :type (string 1)
    :void-value "N"
    :initarg :fulfilled)
   
   
   (status 
    :accessor odt-status
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 3)
    :initarg :status)
   
   
   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)
   
   (comments
    :accessor comments
    :type (string 250)
    :initarg :comments)
   
   
   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR get-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET nil)))
  
  
  (:BASE-TABLE dod_vendor_orders))

