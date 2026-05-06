;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家可用日（Vendor Availability Day）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/vendor/dod-bl-vad.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-vendor-availability-day 的 CRUD 业务函数。
;;;;       提供按 vendor / 日期 / 主键查询、软删除、恢复、批量操作和创建。
;;;;
;;;; 主要导出：
;;;;   get-vendor-availability-day-by-avail-date   —— 按日期查
;;;;   get-vendor-availability-day-by-id           —— 按主键查
;;;;   get-vendor-availability-days                —— 列出某 vendor 全部排班
;;;;   create-vendor-availability-day              —— 新建一条排班
;;;;   update-vendor-availability-day-instance     —— 更新
;;;;   delete-vendor-availability-day-instance     —— 单条软删
;;;;   delete-vendor-availability-day-instances    —— 批量软删
;;;;   restore-deleted-vendor-availability-day-instances —— 批量恢复
;;;;
;;;; 关联：
;;;;   上游使用方：vendor 模块控制器（推测：暂未在 dod-ui-vad.lisp 体现）。
;;;;   下游依赖：vendor/dod-dal-vad.lisp（实体定义）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;;;;;;; High level functions to be implemented
;;;;;;; create vendor availability day
;;;;;;; get vendor availability day
;;;;;;; delete vendor availability day


(defun get-vendor-availability-day-by-avail-date (vendor-id avail-date tenant-id)
  "按 (vendor-id, avail-date, tenant-id) 精确查询单条已启用、未软删的排班。
   返回：dod-vendor-availability-day 实例 / nil。备注：未启用 CLSQL 缓存。"
  (car (clsql:select 'dod-vendor-availability-day  :where [and 
		     [= [:deleted-state] "N"] 
		     [= [:active-flg] "Y"] 
		     [= [:avail-date] avail-date] 
		     [= [:tenant-id] tenant-id] 
		     [= [:vendor-id] vendor-id]]    :caching nil :flatp t )))


(defun get-vendor-availability-day-by-id (row-id )
  "按主键 row-id 查询单条已启用、未软删的排班。
   注意：未限定 tenant_id，跨租户取第一条。"
  (car (clsql:select 'dod-vendor-availability-day  :where [and 
		     [= [:deleted-state] "N"] 
		     [= [:active-flg] "Y"] 
		     [= [:row-id] row-id]]  :caching nil :flatp t )))


(defun get-vendor-availability-days  (vendor-id tenant-id)
  "列出某 vendor 在某租户下所有已启用、未软删的排班。返回列表。"
 (clsql:select 'dod-vendor-availability-day  :where [and 
		     [= [:deleted-state] "N"] 
		     [= [:active-flg] "Y"] 
		      [= [:tenant-id] tenant-id] 
		     [= [:vendor-id] vendor-id]]    :caching nil :flatp t ))


(defun delete-vendor-availability-day-instance (id)
  "单条软删除：把 deleted-state 改为 'Y'。副作用：UPDATE。
   注意：未做租户过滤，调用方应自行保证 id 属于当前租户。"
  (let ((object (car (clsql:select 'dod-vendor-availability-day :where [= [:row-id] id] :flatp t :caching nil))))
    (setf (slot-value object 'deleted-state) "Y")
    (clsql:update-record-from-slot object 'deleted-state)))

(defun update-vendor-availability-day-instance (instance); This function has side effect of modifying the database record.
  "更新整条排班记录。副作用：UPDATE 数据库。"
  (clsql:update-records-from-instance instance))

(defun delete-vendor-availability-day-instances (list)
  "批量软删除。list — 主键 id 列表。"
  (mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-vendor-availability-day :where [= [:row-id] id] :flatp t :caching nil))))
			  (setf (slot-value object 'deleted-state) "Y")
			  (clsql:update-record-from-slot object  'deleted-state))) list ))


(defun restore-deleted-vendor-availability-day-instances( list )
  "批量恢复软删的排班记录（deleted-state 改回 'N'）。"
(mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-vendor-availability-day :where [= [:row-id] id] :flatp t :caching nil))))
			  (setf (slot-value object 'deleted-state) "N")
			  (clsql:update-record-from-slot object  'deleted-state))) list ))


  
(defun create-vendor-availability-day  (vendor-id avail-date start-time end-time break-start-time break-end-time leave-flag comments tenant-id created-by)
  "新建一条排班记录（active-flg='Y'、deleted-state='N'）。
   参数：vendor-id — 卖家；avail-date — 日期；start-time/end-time — 工作起止；
        break-start-time/break-end-time — 休息起止；leave-flag — 是否请假；
        comments — 备注；tenant-id — 租户；created-by — 创建者。
   副作用：INSERT。"
 (clsql:update-records-from-instance (make-instance 'dod-vendor-availability-day
				    :vendor-id vendor-id 
				    :avail-date avail-date 
				    :start-time start-time 
				    :end-time end-time 
				    :break-start-time break-start-time
				    :break-end-time break-end-time 
				    :leave-flag leave-flag
				    :comments comments
				    :tenant-id tenant-id 
				    :created-by created-by 
				    :deleted-state "N"
				    :active-flg "Y")))

