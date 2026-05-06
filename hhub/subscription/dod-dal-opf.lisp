;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：subscription 周期订单（订阅）
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/subscription/dod-dal-opf.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义订阅偏好实体 dod-ord-pref，映射到 MySQL 表 DOD_ORDER_SUBSCRIPTION。
;;;;       一行表示某客户对某商品的"按周/按日定期下单"偏好（频率 + 周一至周日
;;;;       七个标志位 + 起止日期 + 数量）。后台调度器据此生成实际订单。
;;;;       注：类名 opf/ord-pref 沿用早期命名，类对应表却叫 dod_order_subscription。
;;;;
;;;; 主要导出：
;;;;   dod-ord-pref   — 订阅偏好 view-class
;;;;
;;;; 关联：
;;;;   上游使用方：subscription/dod-bl-opf.lisp（CRUD 与调度）、
;;;;               subscription/dod-ui-opf.lisp（客户端订阅设置 UI）
;;;;   下游依赖：dod-cust-profile / dod-prd-master / dod-company
;;;; ============================================================================

(in-package :nstores)
;;(clsql:file-enable-sql-reader-syntax)


;; ----------------------------------------------------------------------------
;; 实体：dod-ord-pref
;; 表：DOD_ORDER_SUBSCRIPTION
;; 含义：客户的周期下单偏好。
;; 关键字段：
;;   row-id           主键
;;   cust-id          客户 → dod-cust-profile.row-id
;;   prd-id           商品 → dod-prd-master.row-id
;;   prd-qty          每次定期下单的数量
;;   start-date       起始日期（不早于此日开始生成订单）
;;   end-date         结束日期（之后停止）
;;   frequency        频率枚举（默认 "WEEKLY"，推测还可能有 DAILY/MONTHLY）
;;   sun..sat         七个 Y/N 位，标记本周哪几天投递（按 frequency=WEEKLY 时使用）
;;   tenant-id        多租户隔离键 → dod-company.row-id
;;   deleted-state    N/Y 软删标志
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-ord-pref ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)

   (cust-id
    :type integer
    :initarg :cust-id)
   (customer
    :ACCESSOR get-opf-customer
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-cust-profile
	                  :HOME-KEY cust-id
                          :FOREIGN-KEY row-id
                          :SET nil))

   (prd-id
    :accessor get-opf-prd-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer
    :initarg :prd-id)
   (productobject
    :ACCESSOR get-opf-product
    :db-kind :join
    :db-info (:join-class dod-prd-master
	      :home-key prd-id
	      :foreign-key row-id
	      :set nil))

   (prd-qty
    :accessor get-product-qty
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer
    :initarg :prd-qty)

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

   (frequency
    :accessor frequency
    :type (string 10)
    :void-value "WEEKLY"
    :initarg :frequency)
   
   (sun
    :type (string 1)
    :void-value "N"
    :initarg :sun)
   (mon
    :type (string 1)
    :void-value "N"
    :initarg :mon)
   (tue
    :type (string 1)
    :void-value "N"
    :initarg :tue)
   (wed
    :type (string 1)
    :void-value "N"
    :initarg :wed)
   (thu
    :type (string 1)
    :void-value "N"
    :initarg :thu)
   (fri
    :type (string 1)
    :void-value "N"
    :initarg :fri)
   (sat
    :type (string 1)
    :void-value "N"
    :initarg :sat)


    (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR customer-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET nil))

   

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state))
  (:base-table dod_order_subscription))





