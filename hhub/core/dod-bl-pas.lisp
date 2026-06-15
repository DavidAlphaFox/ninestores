;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 密码重置业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/dod-bl-pas.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：DOD_PASSWORD_RESET 表的 CRUD —— 创建/查询/软删/恢复重置 token 记录。
;;;;
;;;; 主要导出：
;;;;   create-reset-password-instance        — 写入新 token
;;;;   get-reset-password-instance-by-token  — 凭 token 反查（验证邮件链接）
;;;;   get-reset-password-instance-by-email  — 凭邮箱查现存 token（防重复发起）
;;;;   update-reset-password-instance        — 更新（如标记已使用）
;;;;   delete-reset-password-instance(s)     — 软删
;;;;   restore-deleted-reset-password-instances
;;;;
;;;; 关联：
;;;;   上游使用方：登录页"忘记密码"流程、邮件回链处理
;;;;   下游依赖：core/dod-dal-pas.lisp（dod-password-reset view-class）
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun get-reset-password-instance-by-token (token)
  "凭 token 查询未删除的重置请求记录。被邮件回链入口使用以验证 token 有效性。
   返回：单个 dod-password-reset / nil。"
  (car (clsql:select 'dod-password-reset  :where [and [= [:deleted-state] "N"]
		[= [:token] token]]    :caching nil :flatp t )))

(defun get-reset-password-instance-by-email (email tenant-id)
  "在指定租户内按邮箱查询现存的重置请求；用于避免短期内重复生成 token。"
 (car (clsql:select 'dod-password-reset  :where [and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:email] email]]    :caching nil :flatp t )))

(defun delete-reset-password-instance ( id )
  "按主键软删（deleted-state='Y'）。token 使用后通常立刻软删避免重放。"
  (let ((object (car (clsql:select 'dod-password-reset :where [= [:row-id] id] :flatp t :caching nil))))
    (setf (slot-value object 'deleted-state) "Y")
    (clsql:update-record-from-slot object 'deleted-state)))

(defmethod update-reset-password-instance (reset-password-instance); This function has side effect of modifying the database record.
  "更新重置 token 记录到库。副作用：UPDATE。"
  (clsql:update-records-from-instance reset-password-instance))

(defmethod delete-reset-password-instances  ( list )
  "批量软删。list — id 列表。"
  (mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-password-reset :where [= [:row-id] id] :flatp t :caching nil))))
			  (setf (slot-value object 'deleted-state) "Y")
			  (clsql:update-record-from-slot object  'deleted-state))) list ))


(defun restore-deleted-reset-password-instances( list )
  "批量恢复软删（deleted-state 改回 'N'）。"
(mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-password-reset :where [= [:row-id] id] :flatp t :caching nil))))
			  (setf (slot-value object 'deleted-state) "N")
			  (clsql:update-record-from-slot object  'deleted-state))) list ))



(defun create-reset-password-instance (user-type token email  tenant-id)
  "新建一条密码重置记录。
   参数：user-type — CUSTOMER/VENDOR/EMPLOYEE；token — 一次性令牌；
         email — 接收邮件地址；tenant-id — 多租户隔离键。
   副作用：INSERT。"
 (clsql:update-records-from-instance (make-instance 'dod-password-reset
				    :user-type user-type
				    :email email
				    :token token
				    :tenant-id tenant-id
				    :deleted-state "N"
				    :active-flg "Y")))
				    
 
