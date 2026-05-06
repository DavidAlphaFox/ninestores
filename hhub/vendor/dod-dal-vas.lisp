;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家预约时段（Vendor Availability Slot / Appointment）
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/vendor/dod-dal-vas.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 dod-vendor-appointment 的 CLSQL view-class，
;;;;       一一映射到 MySQL 表 DOD_VENDOR_APPOINTMENT。
;;;;       记录某 vendor 与某 customer 在某日期/时段的预约。
;;;;
;;;; 主要导出：
;;;;   dod-vendor-appointment  —— 卖家预约实体
;;;;
;;;; 关联：
;;;;   上游使用方：vendor/dod-bl-vas.lisp（预约 CRUD）
;;;;   下游依赖：vendor/dod-dal-ven.lisp（dod-vend-profile）、
;;;;             customer 模块（dod-cust-profile）、account（dod-company）、core（dod-users）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;; ----------------------------------------------------------------------------
;; 实体：dod-vendor-appointment
;; 表：DOD_VENDOR_APPOINTMENT
;; 含义：vendor ↔ customer 预约时段记录。
;; 关键字段：
;;   row-id            主键
;;   vendor-id         外键 → dod-vend-profile
;;   customer-id       外键 → dod-cust-profile
;;   appt-date         预约日期
;;   start-time / end-time   预约起止时间
;;   active-flg        Y/N 启用标志
;;   comments          备注
;;   tenant-id         多租户隔离键 → dod-company.row-id
;;   created-by        创建者 → dod-users.row-id
;;   deleted-state     N/Y 软删标志
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vendor-appointment ()
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



   (appt-date
    :accessor appt-date
    :type clsql:wall-time
    :initarg :appt-date) 
   

    (start-time
    :accessor start-time
    :type clsql:wall-time
    :initarg :start-time)
   
   (end-time
    :accessor end-time
    :type clsql:wall-time
    :initarg :end-time)

   (active-flg
    :accessor active-flg
    :type (string 1)
    :void-value "N"
    :initarg :active-flg)
   
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
   

   
  (:BASE-TABLE dod_vendor_appointment))

