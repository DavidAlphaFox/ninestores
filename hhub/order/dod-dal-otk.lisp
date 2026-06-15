;;; dod-dal-otk.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：order 订单 —— 订单状态轨迹
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/order/dod-dal-otk.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义订单整体状态变更轨迹实体 dod-order-track 的 CLSQL view-class，
;;;;       一一映射到 MySQL 表 DOD_ORDER_TRACK。每次主单状态推进会插一行。
;;;;
;;;; 主要导出：
;;;;   dod-order-track   — 订单跟踪记录（status / remarks / updated-by）
;;;;
;;;; 关联：
;;;;   上游使用方：order/dod-bl-ord.lisp（订单履约 status 变更时写轨迹）
;;;;   下游依赖：dod-company（多租户）、dod-order（被跟踪的主单）
;;;; ============================================================================

(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 实体：dod-order-track
;; 表：DOD_ORDER_TRACK
;; 含义：订单状态变更历史。每次状态推进（PEN→PRO→CMP 等）追加一条。
;; 关键字段：
;;   row-id        主键
;;   order-id      外键 → dod-order
;;   status        订单状态码（3 字符，如 PEN/CMP/CAN/PRO）
;;   updated-by    操作者标识（推测：用户名或角色字符串）
;;   remarks       备注
;;   tenant-id     多租户隔离键 → dod-company.row-id
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-order-track ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   
(order-id
    :accessor otk-order-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer
    :initarg :order-id)


(status 
    :accessor otk-status
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 3)
    :initarg :status)


(updated-by
    :accessor otk-updated-by
    :TYPE (string 70)
    :INITARG updated-by)   


 (remarks
    :ACCESSOR otk-remarks 
    :type (string 70)
    :initarg :remarks)


    (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR order-track-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET nil)))

   
  (:BASE-TABLE dod_order_track))
