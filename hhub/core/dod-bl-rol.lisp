;;; dod-bl-rol.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 角色业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/dod-bl-rol.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-roles 与 dod-user-roles 两张表的轻量 CRUD。
;;;;
;;;; 主要导出：
;;;;   get-system-roles            — 列出系统全部可分配角色（不含 SUPERADMIN）
;;;;   select-role-by-id/name      — 单条查询
;;;;   select-user-role-by-userid  — 查某用户在某租户下的角色绑定
;;;;   update-user-role            — 更新用户-角色绑定
;;;;   create-user-role / create-role — 新建
;;;;
;;;; 关联：
;;;;   上游使用方：登录/注册流程、CAD/OPR 后台用户管理
;;;;   下游依赖：core/dod-dal-rol.lisp（dod-roles / dod-user-roles 实体）
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun get-system-roles ()
  "查询全部可分配的系统角色（排除 SUPERADMIN，避免被普通管理员选中）。
   过滤已软删除（deleted-state='N'）。返回：dod-roles 列表。"
(clsql:select 'dod-roles :where
	      [and
	      [= [:deleted-state] "N"]
	      [<> [:name] "SUPERADMIN"]]
	      :caching nil :flatp t ))

(defun select-role-by-id (id )
  "按主键查角色。返回单个 dod-roles / nil。"
  (car (clsql:select 'dod-roles :where
		     [= [:row-id] id]
		     :caching nil :flatp t)))


(defun select-role-by-name (name )
  "按角色名查角色。返回单个 dod-roles / nil。"
  (car (clsql:select 'dod-roles :where
		     [= [:name] name]
		     :caching nil :flatp t)))


(defun select-user-role-by-userid (user-id tenant-id)
  "查询某用户在指定租户下的角色绑定（一个用户在租户内只持有一条角色记录）。
   返回：单个 dod-user-roles / nil。"
  (car (clsql:select 'dod-user-roles :where [and
		[= [:tenant-id] tenant-id]
		[= [:user-id] user-id]]
	        :caching nil :flatp t )))



(defun update-user-role (userrole-instance); This function has side effect of modifying the database record.
  "更新已加载的 dod-user-roles 实例（例如改变其 role-id）。副作用：UPDATE。"
  (clsql:update-records-from-instance userrole-instance))


(defun create-user-role (user-id role-id tenant-id)
  "新建用户-角色绑定记录。副作用：INSERT。"
   (clsql:update-records-from-instance (make-instance 'dod-user-roles
				    :user-id user-id
				    :role-id role-id
				    :tenant-id tenant-id)))


(defun create-role (name description)
  "新建一个角色。默认 active-flg='Y'、deleted-state='N'。副作用：INSERT。"
 (clsql:update-records-from-instance (make-instance 'dod-roles
				    :name name
				    :description description
				    :active-flg "Y"
				    :deleted-state "N")))

  
