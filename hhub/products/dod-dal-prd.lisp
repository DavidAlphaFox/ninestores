;;; dod-dal-prd.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：products —— 商品主数据 / 价格 / 类目 / SAC 税码
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/products/dod-dal-prd.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义商品域核心 CLSQL view-class —— 商品主表、定价、商品 GST、商品类目、
;;;;       SAC 税码 —— 一一映射到对应数据库表。
;;;;
;;;; 主要导出：
;;;;   dod-prd-master       — 商品主表 DOD_PRD_MASTER
;;;;   dod-product-pricing  — 商品定价表 DOD_PRODUCT_PRICING
;;;;   dod-product-gst      — 商品 GST 税率表（注意：base-table 同名 dod_product_pricing，疑似复用同表存税率字段）
;;;;   dod-prd-catg         — 商品类目表 DOD_PRD_CATG（含 nested set lft/rgt 用于树形）
;;;;   dod-gst-sac-codes    — 服务类 SAC 税码表 DOD_GST_SAC_CODES
;;;;
;;;; 关联：
;;;;   上游使用方：products/dod-bl-prd.lisp（CRUD/业务）、订单/库存/购物车模块
;;;;   下游依赖：dod-vend-profile（商家）、dod-prd-catg（类目）、dod-company（租户）
;;;; ============================================================================

(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 实体：dod-prd-master
;; 表：DOD_PRD_MASTER
;; 含义：商品主数据（每行一个 SKU 级商品）。承载基本属性、价格、库存、上架审批
;;       状态、各种条码（SKU/UPC/EAN/JAN/ISBN）、物流尺寸、所属商家、所属类目。
;; 关键字段：
;;   row-id            主键
;;   prd-name          商品名（NOT NULL）
;;   description       描述
;;   vendor-id         外键 → dod-vend-profile.row-id（所属商家）
;;   catg-id           外键 → dod-prd-catg.row-id（类目）
;;   qty-per-unit      每单位数量（如 1 瓶=500ml 时为 500）
;;   unit-of-measure   单位（KG/G/L/PCS 等）
;;   prd-image-path    图片路径
;;   current-price / current-discount  当前价 / 折扣（与 dod-product-pricing 配合）
;;   units-in-stock    库存
;;   hsn-code          GST HSN 编码（用于查税率）
;;   sku/upc/ean/jan/isbn/serial-no   各类外部条码
;;   external-url      外部商品地址
;;   shipping-*        物流尺寸/重量
;;   active-flag       Y/N 上架激活
;;   deleted-state     Y/N 软删
;;   subscribe-flag    Y/N 是否订阅型商品
;;   approved-flag     Y/N CAD 审批通过
;;   approval-status   PENDING/APPROVED/REJECTED
;;   prd-type          SALE/PUR 等
;;   product-code      系统编码（默认 NST-<10 位随机>，由 :void-value 表达式生成）
;;   tenant-id         多租户隔离键 → dod-company.row-id
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-prd-master ()
  ((row-id
    :db-kind :key
    :db-constraints :primary-key 
    :type integer
    :accessor row-id
    :initarg :row-id)

   (prd-name
    :accessor prd-name
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 70)
    :INITARG :prd-name)

   (description
    :type (string 1024)
    :initarg :description)

   (vendor-id
    :type integer 
    :initarg :vendor-id)
   (vendor
    :ACCESSOR product-vendor
    :initarg :vendor
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-vend-profile
	                  :HOME-KEY vendor-id
                          :FOREIGN-KEY row-id
                          :SET NIL))

   (catg-id
    :type integer
    :initarg :catg-id)
   (category
    :initarg :category
    :accessor product-category
    :db-kind :join
    :db-info (:join-class dod-prd-catg
			  :home-key catg-id 
			  :foreign-key row-id
			  :set nil))

   (qty-per-unit
    :accessor qty-per-unit
    :type float
    :initarg :qty-per-unit)
   (unit-of-measure
    :ACCESSOR unit-of-measure
    :type (string 20)
    :INITARG :unit-of-measure)
   
   (prd-image-path
    :accessor prd-image-path
    :type (string 1024)
    :initarg :prd-image-path)
   
   (current-price
    :accessor current-price
    :type float
    :initarg :current-price)

   (current-discount
    :accessor :current-discount
    :type float
    :initarg :current-discount)
   
   (units-in-stock
    :type integer
    :initarg :units-in-stock)

   (hsn-code
    :type (string 8)
    :initarg :hsn-code)

   (sku
    :type (string 20)
    :initarg :sku)

   (upc
    :type (string 20)
    :initarg :upc)
   (ean
    :type (string 20)
    :initarg :ean)
   (jan
    :type (string 20)
    :initarg :jan)
   (isbn
    :type (string 20)
    :initarg :isbn)
   (serial-no
    :type (string 20)
    :initarg :serial-no)
   
   (external-url
    :type (string 255)
    :initarg :external-url)

   (shipping-length-cms
    :type integer
    :initarg :shipping-length-cms)

   (shipping-width-cms
    :type integer
    :initarg :shipping-width-cms)

   (shipping-height-cms
    :type integer
    :initarg :shipping-height-cms)

   (shipping-weight-kg
    :type float
    :initarg :shipping-weight-kg)
 
   (active-flag
    :type (string 1)
    :void-value "N"
    :initarg :active-flag)


   (deleted-state
    :type (string 1)
    :void-value "N"
       :initarg :deleted-state)

   (subscribe-flag
	  :type (string 1)
	  :void-value "N"
	  :initarg :subscribe-flag)

   (approved-flag 
    :type (string 1) 
    :void-value "N"
    :initarg :approved-flag) 
   (approval-status 
    :type (string 20) 
    :void-value "PENDING"
    :initarg :approval-status)

   (prd-type
    :type (string 4)
    :void-value "SALE"
    :initarg :prd-type)

   (product-code
    :type (string 50) 
    :void-value (format nil "NST-~A" (hhub-random-password 10))
    :initarg :product-code)
   
   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR product-company
    :initarg :company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
              :SET NIL)))
  (:BASE-TABLE dod_prd_master)
  (:keys row-id))


;; ----------------------------------------------------------------------------
;; 实体：dod-product-pricing
;; 表：DOD_PRODUCT_PRICING
;; 含义：商品分时段定价。同一商品可叠加多条不同 [start-date, end-date] 的价格。
;; 关键字段：
;;   product-id    外键 → dod-prd-master.row-id
;;   price         价格
;;   discount      折扣
;;   currency      币种（默认 INR）
;;   start-date / end-date  生效起止日期
;;   active-flag   Y/N 启用
;;   tenant-id     多租户键
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-product-pricing ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)

   (product-id
    :accessor product-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer
    :INITARG :product-id)

   (price
    :type float
    :initarg :price)

   (discount
    :type float
    :initarg :discount)
   
   (currency
    :type (string 3)
    :void-value "INR"
    :initarg :currency)

   (start-date
    :accessor start-date
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE clsql:date
    :initarg :start-date)
   (end-date
    :accessor end-date
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE clsql:date
    :initarg :end-date)
      
   (active-flag
    :type (string 1)
    :void-value "N"
    :initarg :active-flag)


   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)

   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR product-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET T)))

   
  (:BASE-TABLE dod_product_pricing))


;;;;;;;;;;;; PRODUCT GST ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ----------------------------------------------------------------------------
;; 实体：dod-product-gst
;; 表：DOD_PRODUCT_PRICING（注意 base-table 名字与 dod-product-pricing 相同 ——
;;     推测：早期实现复用同张表来存税率，与 pricing 字段并存；新代码不一定使用）
;; 含义：商品在某时段的 GST 税率快照（cgst/sgst/igst/compcess + 同期 price/discount）。
;; 关键字段：cgstrate / sgstrate / igstrate / compcess + price / discount + 时间窗。
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-product-gst ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)

   (product-id
    :accessor product-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer
    :INITARG :product-id)

   (cgstrate
    :initarg :cgstrate
    :type float
    :accessor cgstrate)
   (sgstrate
    :initarg :sgstrate
    :type float
    :accessor sgstrate)
   (igst
    :initarg :igstrate
    :type float
    :accessor igstrate)
   (compcess
    :initarg :compcess
    :accessor compcess)

   
   (price
    :type float
    :initarg :price)

   (discount
    :type float
    :initarg :discount)
   
   (currency
    :type (string 3)
    :void-value "INR"
    :initarg :currency)

   (start-date
    :accessor start-date
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE clsql:date
    :initarg :start-date)
   (end-date
    :accessor end-date
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE clsql:date
    :initarg :end-date)
      
   (active-flag
    :type (string 1)
    :void-value "N"
    :initarg :active-flag)


   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)

   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR product-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET T)))

   
  (:BASE-TABLE dod_product_pricing))

;;;;;;;;;;;;; END PRODUCT GST TABLE ;;;;;;;;;;;;;;;;;;;;;;;;;

; Product category
;; ----------------------------------------------------------------------------
;; 实体：dod-prd-catg
;; 表：DOD_PRD_CATG
;; 含义：商品类目，使用 nested set 模型 (lft / rgt) 存树形结构 ——
;;       祖先/后代查询通过 BETWEEN [lft,rgt] 区间实现。
;; 关键字段：
;;   catg-name      类目名（NOT NULL）
;;   lft / rgt      nested set 左右边界整型
;;   active-flag    Y/N
;;   deleted-state  软删
;;   tenant-id      多租户键
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-prd-catg ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)

      (catg-name
    :accessor catg-name
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 70)
    :INITARG :catg-name)

   (lft 
    :accessor get-left
    :type integer 
    :initarg :lft) 
   
   (rgt 
    :accessor get-right
    :type integer 
    :initarg :rgt) 
   

   (active-flag
    :type (string 1)
    :void-value "N"
       :initarg :active-flag)


   (deleted-state
    :type (string 1)
    :void-value "N"
       :initarg :deleted-state)

    (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR product-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET T)))

   
  (:BASE-TABLE dod_prd_catg))





;; ----------------------------------------------------------------------------
;; 实体：dod-gst-sac-codes
;; 表：DOD_GST_SAC_CODES
;; 含义：服务类（Service Accounting Code）税码与对应 GST 税率。
;; 关键字段：sac-code / sac-description / sac-code-4digit / cgst / sgst / igst /
;;          condition-txt（适用条件）/ gst-sac-func（动态规则函数名 —— 推测：与
;;          HSN 表相似，按字符串 intern 调用）。
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-gst-sac-codes ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)
   (sac-code
    :accessor sac-code
    :TYPE (string 10))

   (sac-description
    :accessor sac-description
    :TYPE (string 500))

   (sac-code-4digit
    :accessor sac-code-4digit
    :type (string 4))

   (condition-txt
    :accessor condition-txt
    :TYPE (string 500))
   
   (cgst
    :accessor cgst
    :type float
    :initarg :cgst)

   (sgst
    :accessor sgst
    :type float
    :initarg :sgst)

   (igst
    :accessor igst
    :type float
    :initarg :igst)

   (gst-sac-func
    :accessor gst-hsn-func
    :TYPE (string 255)))


  (:BASE-TABLE dod_gst_sac_codes))

