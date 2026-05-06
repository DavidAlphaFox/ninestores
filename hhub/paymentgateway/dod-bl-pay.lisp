;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：paymentgateway 在线支付网关
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/paymentgateway/dod-bl-pay.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-payment-transaction 实体的查询与持久化业务逻辑。覆盖按网关流水号
;;;;       查单、按客户/卖家维度查近 20 条、以及网关回调时落库新交易记录。
;;;;
;;;; 主要导出：
;;;;   get-payment-trans-by-transaction-id  — 按网关 transaction-id 查
;;;;   select-payment-trans-by-customer     — 按 customer 取近 20 条
;;;;   select-payment-trans-by-vendor       — 按 (customer, vendor) 联合取近 20 条
;;;;   persist-payment-trans                — 底层 INSERT
;;;;   create-payment-trans                 — 网关回调入口（解 customer/vendor/company）
;;;;
;;;; 关联：
;;;;   上游使用方：paymentgateway/dod-ui-pay.lisp（结算/回调控制器）
;;;;   下游依赖：paymentgateway/dod-dal-pay.lisp（实体定义）、dod-cust-profile、
;;;;             dod-vend-profile、dod-company
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



;;;;;;;;;;;;;;;;;;;;; business logic for dod-bus-object ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun get-payment-trans-by-transaction-id (trans-id company)
  "按网关返回的 transaction-id 查询单条支付记录（在指定租户下）。
   过滤：deleted-state='N'，tenant-id=company.row-id。
   返回：单个 dod-payment-transaction / nil。
   备注：网关回调来对账时常用此函数定位原始交易。"
  (let ((tenant-id (slot-value company 'row-id)))
    (car (clsql:select 'dod-payment-transaction  :where
		       [and [= [:deleted-state] "N"]
		       [= [:tenant-id] tenant-id]
		       [= [:transaction-id] trans-id]]    :caching *dod-database-caching* :flatp t ))))


(defun select-payment-trans-by-customer (customer company)
  "查询某客户在某租户下的最近 20 条支付记录。
   参数：customer — dod-cust-profile 实例；company — dod-company 实例。
   返回：dod-payment-transaction 列表（最多 20 条）。"
  (let ((customer-id (slot-value customer 'row-id))
	(tenant-id (slot-value company 'row-id)))
    (clsql:select 'dod-payment-transaction  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:customer-id] customer-id]] :limit 20
		:caching *dod-database-caching* :flatp t )))


(defun select-payment-trans-by-vendor (customer vendor company)
  "查询某 (customer, vendor) 组合在某租户下的最近 20 条支付记录。
   用于卖家中心查看与某客户之间的历史支付。"
  (let ((customer-id (slot-value customer 'row-id))
	(vendor-id (slot-value vendor 'row-id))
	(tenant-id (slot-value company 'row-id)))
    (clsql:select 'dod-payment-transaction  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:vendor-id] vendor-id]
		[= [:customer-id] customer-id]] :limit 20
		:caching *dod-database-caching* :flatp t )))





(defun persist-payment-trans(order-id amt currency description customer-id vendor-id payment-mode transaction-id response-code response-message error-desc tenant-id )
  "底层持久化：构造 dod-payment-transaction 并 INSERT。仅供 create-payment-trans 调用。
   备注：deleted-state 默认 'N'。"
 (clsql:update-records-from-instance (make-instance 'dod-payment-transaction
						    :order-id order-id
						    :amt amt
						    :currency currency
						    :description description
						    :customer-id customer-id
						    :vendor-id vendor-id
						    :payment-mode payment-mode
						    :transaction-id transaction-id
						    :response-code response-code
						    :response-message response-message
						    :error-desc error-desc
						    :deleted-state "N"
						    :tenant-id tenant-id)))




(defun create-payment-trans (order-id amt currency description customer vendor payment-mode transaction-id response-code response-message error-desc company)
  "在指定租户下落库一条新的支付交易记录。被网关回调控制器调用。
   参数：customer / vendor / company 为对应实体；其余为网关原始字段。
   副作用：写 DOD_PAYMENT_TRANSACTION。"
  (let ((tenant-id (slot-value company 'row-id))
	(customer-id (slot-value customer 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
    	      (persist-payment-trans order-id amt currency description customer-id vendor-id payment-mode transaction-id response-code response-message error-desc tenant-id)))


