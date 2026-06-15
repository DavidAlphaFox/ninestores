;;; dod-dal-odt.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：order 订单 —— 订单行项轨迹
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/order/dod-dal-odt.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义订单行项（item）级状态变更轨迹实体的 CLSQL view-class。
;;;;       与 dod-order-track 不同：本实体跟踪单个 dod-order-items 的状态推进，
;;;;       多卖家订单中每个商品行可独立履约。
;;;;       注意：base-table 复用了 dod_order_track（推测：早期实现共用同一张表，
;;;;             item-id 字段写到 order-id 列；架构文档中独立列出 DOD_ORDER_ITEMS_TRACK）。
;;;;
;;;; 主要导出：
;;;;   dod-order-items-track  — 订单行项跟踪记录
;;;;
;;;; 关联：
;;;;   上游使用方：order/dod-bl-ord.lisp（行项级状态推进）
;;;;   下游依赖：dod-company、dod-order-items
;;;; ============================================================================

(in-package :nstores)
;;(clsql:file-enable-sql-reader-syntax)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Create class dod-order-details-track
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ----------------------------------------------------------------------------
;; 实体：dod-order-items-track
;; 表：DOD_ORDER_TRACK（与 dod-order-track 共表，推测早期共用）
;; 含义：订单行项级状态变更历史（每条记录对应一次行项状态推进）。
;; 关键字段：
;;   row-id      主键
;;   item-id     外键 → dod-order-items（对应"order-id"列名复用，:initarg :order-id）
;;   status      行项状态码（3 字符）
;;   updated-by  操作者
;;   remarks     备注
;;   tenant-id   多租户隔离键
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-order-items-track ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   
(item-id
    :accessor odtk-order-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer
    :initarg :order-id)


(status 
    :accessor odtk-status
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 3)
    :initarg :status)


(updated-by
    :accessor odtk-updated-by
    :TYPE (string 70)
    :INITARG updated-by)   


 (remarks
    :ACCESSOR odtk-remarks 
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
