;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家预约时段（Vendor Appointment / Availability Slot）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/vendor/dod-bl-vas.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-vendor-appointment 的 CRUD 业务函数。提供按 vendor / 日期查询、
;;;;       软删、批量软删、恢复以及预约创建。
;;;;
;;;; 主要导出：
;;;;   get-vendor-appointment-instance    —— 按日期查单条预约
;;;;   get-vendor-appointments            —— 列出某 vendor 全部预约
;;;;   create-vendor-appointment          —— 新建预约
;;;;   update-vendor-appointment-instance —— 更新预约
;;;;   delete-vendor-appointment-instance / -instances     —— 软删
;;;;   restore-deleted-vendor-appointment-instances        —— 恢复
;;;;
;;;; 关联：
;;;;   上游使用方：vendor 预约相关控制器（推测）。
;;;;   下游依赖：vendor/dod-dal-vas.lisp（实体定义）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;;;;;;; High level functions to be implemented
;;;;;;; create vendor availability day
;;;;;;; get vendor availability day
;;;;;;; delete vendor availability day


(defun get-vendor-appointment-instance (vendor-id appt-date tenant-id)
  "按 (vendor-id, appt-date, tenant-id) 查单条已启用、未软删的预约。
   返回：dod-vendor-appointment 实例 / nil。备注：未启用 CLSQL 缓存。"
  (car (clsql:select 'dod-vendor-appointment :where [and 
		     [= [:deleted-state] "N"] 
		     [= [:active-flg] "Y"] 
		     [= [:appt-date] appt-date] 
		     [= [:tenant-id] tenant-id] 
		     [= [:vendor-id] vendor-id]]    :caching nil :flatp t )))

(defun get-vendor-appointments  (vendor-id tenant-id)
  "列出某 vendor 在某租户下所有已启用、未软删的预约。返回列表。"
 (clsql:select 'dod-vendor-appointment :where [and 
		     [= [:deleted-state] "N"] 
		     [= [:active-flg] "Y"] 
		      [= [:tenant-id] tenant-id] 
		     [= [:vendor-id] vendor-id]]    :caching nil :flatp t ))


(defun delete-vendor-appointment-instance (id)
  "单条软删除：把 deleted-state 改为 'Y'。副作用：UPDATE。"
  (let ((object (car (clsql:select 'dod-vendor-appointment :where [= [:row-id] id] :flatp t :caching nil))))
    (setf (slot-value object 'deleted-state) "Y")
    (clsql:update-record-from-slot object 'deleted-state)))

(defmethod update-vendor-appointment-instance (instance); This function has side effect of modifying the database record.
  "更新整条预约记录。副作用：UPDATE 数据库。"
  (clsql:update-records-from-instance instance))

(defun delete-vendor-appointment-instances (list)
  "批量软删除。list — 主键 id 列表。"
  (mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-vendor-appointment :where [= [:row-id] id] :flatp t :caching nil))))
			  (setf (slot-value object 'deleted-state) "Y")
			  (clsql:update-record-from-slot object  'deleted-state))) list ))


(defun restore-deleted-vendor-appointment-instances( list )
  "批量恢复软删的预约（deleted-state 改回 'N'）。"
(mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-vendor-appointment :where [= [:row-id] id] :flatp t :caching nil))))
			  (setf (slot-value object 'deleted-state) "N")
			  (clsql:update-record-from-slot object  'deleted-state))) list ))


  
(defun create-vendor-appointment  (vendor-id appt-date start-time end-time  comments tenant-id created-by)
  "新建预约（active-flg='Y'、deleted-state='N'）。
   参数：vendor-id — 卖家；appt-date — 预约日期；start-time/end-time — 起止；
        comments — 备注；tenant-id — 租户；created-by — 创建者。
   副作用：INSERT。"
 (clsql:update-records-from-instance (make-instance 'dod-vendor-appointment
				    :vendor-id vendor-id 
				    :appt-date appt-date 
				    :start-time start-time 
				    :end-time end-time 
				    :comments comments
				    :tenant-id tenant-id 
				    :created-by created-by 
				    :deleted-state "N"
				    :active-flg "Y")))
