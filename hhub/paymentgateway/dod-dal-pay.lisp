;;; dod-dal-pay.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：paymentgateway 在线支付网关
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/paymentgateway/dod-dal-pay.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义在线支付交易记录实体 dod-payment-transaction，映射到 MySQL 表
;;;;       DOD_PAYMENT_TRANSACTION。一笔订单在外部网关（如 PayU/Razorpay）
;;;;       发起支付时，本表记录其请求/回调结果（金额、币种、网关 transaction-id、
;;;;       响应码与错误描述）。
;;;;
;;;; 主要导出：
;;;;   dod-payment-transaction   — 支付交易 view-class
;;;;
;;;; 关联：
;;;;   上游使用方：paymentgateway/dod-bl-pay.lisp（BL 持久化）、
;;;;               paymentgateway/dod-ui-pay.lisp（结算页 / 网关回调控制器）
;;;;   下游依赖：dod-order / dod-cust-profile / dod-vend-profile / dod-company
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


;; ----------------------------------------------------------------------------
;; 实体：dod-payment-transaction
;; 表：DOD_PAYMENT_TRANSACTION
;; 含义：在线支付网关交易日志。一行记录一次支付尝试（不论成功失败）。
;; 关键字段：
;;   row-id            主键
;;   order-id          关联订单（注：声明类型为 string 30，按字符串外键 → dod-order.row-id）
;;   amt / currency    交易金额与币种（如 INR）
;;   description       展示给网关的交易摘要
;;   customer-id       下单客户 → dod-cust-profile.row-id
;;   vendor-id         所属卖家 → dod-vend-profile.row-id
;;   payment-mode      支付方式标识（如 CARD / NB / UPI 等，由网关返回）
;;   transaction-id    网关侧返回的支付流水号
;;   response-code     网关响应码
;;   response-message  网关响应文本
;;   error-desc        失败原因描述（成功时为空）
;;   tenant-id         多租户隔离键 → dod-company.row-id
;;   deleted-state     N/Y 软删标志
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-payment-transaction ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)

   (order-id
    :type (string 30)
    :initarg :order-id)
   
   (order
    :ACCESSOR get-order
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-order
	                  :HOME-KEY order-id
                          :FOREIGN-KEY row-id
                          :SET nil))

   (amt
    :type (float)
    :initarg :amt)

   (currency
    :type (string 10)
    :initarg :currency)
   
   (description
    :type (string 200)
    :initarg :description)

   (customer-id
    :type integer
    :initarg :customer-id)
   (customer
    :ACCESSOR get-customer
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-cust-profile
	                  :HOME-KEY customer-id
                          :FOREIGN-KEY row-id
                          :SET nil))

   (vendor-id
    :type integer
    :initarg :vendor-id)
   (vendor
    :ACCESSOR get-vendor
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-vend-profile
	                  :HOME-KEY vendor-id
                          :FOREIGN-KEY row-id
                          :SET nil))

   
   (payment-mode
    :type (string 20)
    :initarg :payment-mode)
   
   (transaction-id
    :type (string 30)
    :initarg :transaction-id)

   (response-code 
    :type integer
    :initarg :response-code)

   (response-message 
    :type (string 100)
    :initarg :response-message)


   (error-desc 
    :type (string 100)
    :initarg :error-desc)

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)
   
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
  
  
  (:BASE-TABLE dod_payment_transaction))

