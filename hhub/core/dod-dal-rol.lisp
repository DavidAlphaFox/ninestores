;;; dod-dal-rol.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 角色实体
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/core/dod-dal-rol.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义两张角色相关的 view-class —— DOD_ROLES（角色字典）和
;;;;       DOD_USER_ROLES（用户-角色绑定）。
;;;;
;;;; 主要导出：
;;;;   dod-roles         — 角色字典 view-class
;;;;   dod-user-roles    — 用户-角色绑定 view-class（多租户）
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-bl-rol.lisp、core/dod-ui-rol.lisp、登录会话流程
;;;;   下游依赖：dod-users、dod-company
;;;; ============================================================================
(in-package :nstores)


;; ----------------------------------------------------------------------------
;; 实体：dod-roles
;; 表：DOD_ROLES
;; 含义：角色字典（如 SUPERADMIN / COMPADMIN / VENDOR / CUSTOMER）。
;; 关键字段：
;;   row-id        主键
;;   name          角色名（约定大写）
;;   description   描述（slot 名为 description 但 :initarg 为 :address，推测命名笔误）
;;   created-by / updated-by  审计字段（→ dod-users）
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-roles ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (name
    :type (string 30)
    :initarg :name)
   (description
    :type (string 255)
    :initarg :address)

 (created-by
    :TYPE INTEGER
    :INITARG :created-by)
   (user-created-by
    :ACCESSOR role-created-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
                          :HOME-KEY created-by
                          :FOREIGN-KEY row-id
                          :SET NIL))
   (updated-by
    :TYPE INTEGER
    :INITARG :updated-by)
   (user-updated-by
    :ACCESSOR role-updated-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
                          :HOME-KEY updated-by
                          :FOREIGN-KEY row-id
                          :SET NIL)))
  

   (:base-table dod_roles))


;; ----------------------------------------------------------------------------
;; 实体：dod-user-roles
;; 表：DOD_USER_ROLES
;; 含义：用户在某租户下持有的角色（多对多关系表，但实际每用户每租户一条）。
;; 关键字段：
;;   user-id       → dod-users
;;   role-id       → dod-roles
;;   tenant-id     多租户隔离键 → dod-company
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-user-roles ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (user-id
    :type integer
    :initarg :user-id)

   (user
    :ACCESSOR GET-USER-ROLES.USER
    :DB-KIND :JOIN 
    :DB-INFO (:JOIN-CLASS dod-users
			  :HOME-KEY user-id
			  :FOREIGN-KEY row-id
			  :SET NIL))
   
			  
   (role-id 
    :type integer
    :initarg :role-id)
   
   (role
    :ACCESSOR GET-USER-ROLES.ROLE
    :DB-KIND :JOIN 
    :DB-INFO (:JOIN-CLASS dod-roles
			  :HOME-KEY role-id
			  :FOREIGN-KEY row-id
			  :SET NIL))

   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR user-roles-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET NIL)))

   (:base-table dod_user_roles))
