;;; dod-dal-osh.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：shipping 运费 / 配送
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/shipping/dod-dal-osh.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 4 个数据结构：
;;;;       1. ShippingRateCheck   — 运费询价 DTO（普通 defclass，非持久化）
;;;;       2. OrderShipment       — 订单发货 DTO（与外部物流对接的报文模型）
;;;;       3. dod-shipping-methods   — 卖家级"运费方案配置"持久化实体
;;;;       4. dod-vendor-ship-zones  — 卖家级"邮编分区"持久化实体
;;;;
;;;; 主要导出：
;;;;   ShippingRateCheck         — DTO，封装询价请求字段
;;;;   OrderShipment             — DTO，封装下单到物流商的字段
;;;;   dod-shipping-methods      — view-class，对应表 DOD_SHIPPING_METHODS
;;;;   dod-vendor-ship-zones     — view-class，对应表 DOD_VENDOR_SHIP_ZONES
;;;;
;;;; 关联：
;;;;   上游使用方：shipping/dod-bl-osh.lisp（业务）、shipping/dod-ui-osh.lisp（UI）
;;;;   下游依赖：core 的 BusinessObject 基类、dod-vend-profile、dod-company
;;;; ============================================================================

(in-package :nstores)


;; ----------------------------------------------------------------------------
;; DTO：ShippingRateCheck
;; 含义：发往物流商接口的"运费询价"请求 DTO（非持久化）。
;; 字段：起止 PIN、长宽高、重量、订单类型、付款方式、商品 MRP、对接物流商的
;;       access-token / secret-key。
;; ----------------------------------------------------------------------------
(defclass ShippingRateCheck (BusinessObject)
  ((from-pincode)
   (to-pincode)
   (shipping-length-cms)
   (shipping-width-cms)
   (shipping-height-cms)
   (shipping-weight-kg)
   (order-type)
   (payment-method)
   (product-mrp)
   (access-token)
   (secret-key)))



;; ----------------------------------------------------------------------------
;; DTO：OrderShipment
;; 含义：下单到物流商时的发货单 DTO（非持久化）。
;; 关键字段（部分）：
;;   cust-order-id / vendor-order-id   关联订单主键
;;   waybill_no                         物流商分配的运单号
;;   收货 / 账单两套地址（name/addr1/addr2/addr3/pin/city/state/country/phone/email）
;;   is-billing-same-as-shipping        账单与收货是否相同
;;   ship-* / weightkg                  包裹尺寸与重量
;;   shipping/giftwrap/tran/cod-charges 各项费用
;;   advance-amount / cod-amount        预收 / 货到付款金额
;;   payment-mode                       支付方式标识（CARD/COD/UPI/...）
;;   eway-bill-no                       印度 GST eway-bill 号
;;   return-address-id / pickup-address-id  退货 / 揽收地址 ID
;;   logistics                          物流商代号
;;   order-type / s-type                订单类型 / 服务类型
;;   products                           商品行项（推测为 list / DTO）
;; ----------------------------------------------------------------------------
(defclass OrderShipment (BusinessObject)
  ((row-id)
   (cust-order-id)
   (vendor-order-id)
   (waybill_no)
   (order-date)
   (order-amt)
   (total-discount)
   (name)
   (company-name)
   (addr1)
   (addr2)
   (addr3)
   (pin)
   (city)
   (state)
   (country)
   (phone)
   (alt-phone)
   (email)
   (is-billing-same-as-shipping)
   (billing-name)
   (billing-company)
   (billing-addr1)
   (billing-addr2)
   (billing-addr3)
   (billing-pin)
   (billing-city)
   (billing-country)
   (billing-phone)
   (billing-alt-phone)
   (billing-email)
   (ship-length-cm)
   (ship-width-cm)
   (ship-height-cm)
   (weightkg)
   (shipping-charges)
   (giftwrap-charges)
   (tran-charges)
   (cod-charges)
   (advance-amount)
   (cod-amount)
   (payment-mode)
   (eway-bill-no)
   (return-address-id)
   (pickup-address-id)
   (logistics)
   (order-type)
   (s-type)
   (products)))
  


;; ----------------------------------------------------------------------------
;; 实体：dod-shipping-methods
;; 表：DOD_SHIPPING_METHODS
;; 含义：卖家维度的运费方案配置。每个 vendor 可以同时启用多种计算方式
;;       （免运费 / 平价 / 表格价 / 外部物流 API / 门店自提），并指定默认方式。
;; 关键字段：
;;   row-id                  主键
;;   name                    方案名
;;   freeshipenabled         "Y"/"N" 是否启用免运费
;;   flatrateshipenabled     是否启用平价（统一一口价）
;;   tablerateshipenabled    是否启用表格价
;;   extshipenabled          是否启用外部物流商 API（需配 shippartnerkey/secret）
;;   storepickupenabled      是否允许门店自提
;;   defaultshippingmethod   默认方式标识（推测："FRE"/"FLT"/"TBL"/"EXT"/"PCK"）
;;   shippartnerkey          物流商 API key
;;   shippartnersecret       物流商 API secret
;;   flatratetype            平价类型（订单级/件级）
;;   flatrateprice           平价金额
;;   ratetablecsv            表格价的 CSV（重量×目的地区间→价格）
;;   minorderamt             订单金额最低门槛（不足则启用 / 不启用免运费等）
;;   vendor-id               所属卖家 → dod-vend-profile
;;   tenant-id               多租户隔离键 → dod-company
;;   active-flag / deleted-state
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-shipping-methods ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)

    (name
    :accessor name
    :TYPE (string 70)
    :INITARG :name)

    (freeshipenabled
     :type (string 1)
     :initarg :freeshipenabled)

    (flatrateshipenabled
     :type (string 1)
     :initarg :flatrateshipenabled)
    (tablerateshipenabled
     :type (string 1)
     :initarg :tablerateshipenabled)
    (extshipenabled
     :type (string 1)
     :initarg :extshipenabled)
    (storepickupenabled
     :type (string 1)
     :initarg :storepickupenabled)
    
    (defaultshippingmethod
     :type (string 3)
     :initarg :defaultshippingmethod)
    
    (shippartnerkey
     :type (string 50)
     :initarg :shippartnerkey)
    (shippartnersecret
     :type (string 50)
     :initarg :shippartnersecret)
    
    (flatratetype
     :type (string 3)
     :initarg :flatratetype)
    
    (flatrateprice
     :type float
     :initarg :flatrateprice)

    (ratetablecsv
     :type (string 500)
     :initarg :ratetablecsv)
    
    (minorderamt
    :type float
    :initarg :minorderamt)


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
 

    (created
    :accessor created
    :TYPE clsql:date)
   
   (active-flag
    :type (string 1)
    :void-value "Y"
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

   
  (:BASE-TABLE dod_shipping_methods))



;; ----------------------------------------------------------------------------
;; 实体：dod-vendor-ship-zones
;; 表：DOD_VENDOR_SHIP_ZONES
;; 含义：卖家自定义"邮编分区"。一行表示一个分区名 + 一组邮编范围。
;;       配合 dod-shipping-methods.ratetablecsv 实现按地区计费。
;; 关键字段：
;;   row-id              主键
;;   zonename            区名（如 "Mumbai", "North-East"）
;;   zipcoderangecsv     CSV 字符串，列出该区涵盖的 PIN 范围
;;   vendor-id           所属卖家
;;   tenant-id           租户键
;;   active-flag / deleted-state
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vendor-ship-zones ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)

    (zonename
    :accessor zonename
    :TYPE (string 70)
    :INITARG :zonename)

    (zipcoderangecsv
     :type (string 1024)
     :initarg :zipcoderangecsv)
    
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
 

    (created
    :accessor created
    :TYPE clsql:date)
   
    (active-flag
    :type (string 1)
    :void-value "Y"
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

   
  (:BASE-TABLE dod_vendor_ship_zones))


