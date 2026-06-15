;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家可用日（Vendor Availability Day）
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/vendor/dod-dal-vad.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 dod-vendor-availability-day 的 CLSQL view-class，
;;;;       一一映射到 MySQL 表 DOD_VENDOR_AVAILABILITY_DAY。
;;;;       该实体记录某 vendor 在某一日期的可工作时段（含休息时段、请假标志、备注）。
;;;;       常用于服务型 vendor（医生、上门服务、约课等）排班场景。
;;;;
;;;; 主要导出：
;;;;   dod-vendor-availability-day  —— 卖家可用日实体
;;;;
;;;; 关联：
;;;;   上游使用方：vendor/dod-bl-vad.lisp（CRUD 业务函数）
;;;;   下游依赖：vendor/dod-dal-ven.lisp（dod-vend-profile）、
;;;;             account 模块（dod-company）、core（dod-users）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;; ----------------------------------------------------------------------------
;; 实体：dod-vendor-availability-day
;; 表：DOD_VENDOR_AVAILABILITY_DAY
;; 含义：vendor 单日排班——可用起止时间 + 休息起止时间 + 请假标志 + 备注。
;; 关键字段：
;;   row-id            主键
;;   vendor-id         外键 → dod-vend-profile
;;   avail-date        当日日期
;;   start-time / end-time          当日工作起止时间
;;   break-start-time / break-end-time   当日休息起止时间
;;   leave-flag        Y/N 是否请假当日
;;   active-flg        Y/N 启用标志
;;   comments          备注
;;   tenant-id         多租户隔离键 → dod-company.row-id
;;   created-by        创建者 → dod-users.row-id
;;   deleted-state     N/Y 软删标志
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vendor-availability-day ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)

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


   (avail-date
    :accessor avail-date
    :type clsql:wall-time
    :initarg :avail-date)
   

    (start-time
    :accessor start-time
    :type clsql:wall-time
    :initarg :start-time)
   
 (end-time
    :accessor end-time
    :type clsql:wall-time
    :initarg :end-time)

(break-start-time
    :accessor break-start-time
    :type clsql:wall-time
    :initarg :break-start-time)
(break-end-time
    :accessor break-end-time
    :type clsql:wall-time
    :initarg :break-end-time)


   (active-flg
    :accessor active-flg
    :type (string 1)
    :void-value "N"
    :initarg :active-flg)
   

   (leave-flag
    :accessor leave-flag
    :type (string 1)
    :void-value "N"
    :initarg :leave-flag)


   (comments
    :accessor comments
    :type (string 500)
    :initarg comments)

   (created
    :accessor created
    :type clsql:wall-time
    :initarg :created)

(created-by 
 :accessor created-by 
 :type integer 
 :initarg :created-by)
(created-by-user
 :accessor created-by-user 
 :db-kind :join
 :db-info (:join-class dod-users
		       :home-key created-by
		       :foreign-key row-id 
		       :set nil))
   
   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)
   
   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR vendor-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET nil)))
   

   
  (:BASE-TABLE dod_vendor_availability_day))

