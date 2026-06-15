;;; dod-dal-usr.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：sysuser —— 系统用户主体
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/sysuser/dod-dal-usr.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 dod-users 这一系统通用用户实体的 CLSQL view-class；
;;;;       一一映射到 MySQL 表 DOD_USERS。所有内部用户（系统管理员、CAD、
;;;;       Operator 等）共用此表，区分通过 dod-user-roles 关联到的角色判定。
;;;;
;;;; 主要导出：
;;;;   dod-users   — 用户主体 view-class（含密码 + salt、email、phone、所属公司、上级 manager）
;;;;
;;;; 关联：
;;;;   上游使用方：sysuser/dod-dal-sys.lisp（角色绑定）、sysuser/dod-bl-usr.lisp（CRUD）、
;;;;               几乎所有模块都通过 created-by / updated-by JOIN 此实体
;;;;   下游依赖：dod-company（多租户）
;;;; ============================================================================

(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 实体：dod-users
;; 表：DOD_USERS
;; 含义：系统内部用户主体表。
;; 关键字段：
;;   row-id           主键
;;   name             显示名
;;   username         登录名（用于 login-user）
;;   password         密码（推测：散列值；存储与 salt 配合）
;;   salt             密码盐
;;   email            邮箱
;;   phone-mobile     手机号
;;   tenant-id        多租户隔离键 → dod-company.row-id
;;   parent-id        上级用户 → dod-users.row-id（用作组织汇报关系）
;;   created-by/updated-by → dod-users.row-id（操作审计）
;;   deleted-state    'N'/'Y' 软删标志
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-users ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)
   (name
    :accessor name
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 30)
    :INITARG :name)
   (username
    :ACCESSOR username 
    :type (string 30)
    :initarg :username)
   (password
    :accessor password
    :type (string 100)
    :initarg :password)

    (salt 
    :accessor salt
    :type (string 128)
    :initarg :salt)

   
   (email
    :accessor email
    :type (string 255)
    :initarg :email)

   (phone-mobile 
    :accessor phone-mobile
    :type (string 50)
    :initarg :phone-mobile)
   
   

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)

   (created-by
    :TYPE INTEGER
    :INITARG :created-by)
   (user-created-by
    :ACCESSOR user-created-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
                          :HOME-KEY created-by
                          :FOREIGN-KEY row-id
                          :SET NIL))
   (updated-by
    :TYPE INTEGER
    :INITARG :updated-by)
   (user-updated-by
    :ACCESSOR user-updated-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
                          :HOME-KEY updated-by
                          :FOREIGN-KEY row-id
                          :SET NIL))
   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR users-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET NIL))

   
   (parent-id
    :type integer
    :initarg :parent-id)
   (manager
    :accessor users-manager
    :db-kind :join
    :db-info (:join-class dod_users
                          :home-key parent-id
                          :foreign-key row-id
                          :set nil)))

   
  (:BASE-TABLE dod_users))



