;;; dod-dal-pol.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— ABAC 策略元模型实体
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/core/dod-dal-pol.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 ABAC 策略相关的三个 view-class —— 属性元数据、策略元数据、
;;;;       策略-属性关联表。它们对应 DOD_AUTH_ATTR_LOOKUP / DOD_AUTH_POLICY /
;;;;       DOD_AUTH_POLICY_ATTR 表。
;;;;
;;;; 主要导出：
;;;;   dod-auth-attr-lookup    — 属性元模型（attr-func / attr-unique-func / attr-type）
;;;;   dod-auth-policy         — 策略元模型（policy-func 字符串 → Lisp 符号）
;;;;   dod-auth-policy-attr    — 策略 ↔ 属性 多对多关联（含示例值 attr-val）
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-bl-pol.lisp（CRUD/PAP）、PEP 宏 / PDP 函数
;;;;   下游依赖：dod-users、dod-company
;;;; ============================================================================
(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 实体：dod-auth-attr-lookup
;; 表：DOD_AUTH_ATTR_LOOKUP
;; 含义：属性（PIP）元数据登记表。本表只描述属性如何获取，
;;       实际取值靠 attr-func（字符串）→ intern 后 funcall 同名 Lisp 函数。
;; 关键字段：
;;   name                  属性名（约定 "com.hhub.attribute.xxx"）
;;   description           人类可读说明
;;   attr-func             属性求值函数名字符串（→ com-hhub-attribute-*）
;;   attr-unique-func      枚举所有可能值的函数名（PAP 下拉框用）
;;   attr-type             分类：subject / resource / action / context_based
;;   tenant-id             多租户隔离键
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-auth-attr-lookup ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
  (name
    :type (string 50)
    :initarg :name)
   
(description
    :type (string 100)
    :initarg :description)
  

   (attr-func
    :type (string 100)
    :initarg :attr-func)
   (attr-unique-func
    :type (string 100) 
    :initarg :attr-unique-func)

  (attr-type
    :type (string 50)
    :initarg :attr-type)

     (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)

        (active-flg
    :type (string 1)
    :void-value "Y"
    :initarg :active-flg)

   

 (created-by
    :TYPE INTEGER
    :INITARG :created-by)
   (attr-created-by
    :ACCESSOR attr-created-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
                          :HOME-KEY created-by
                          :FOREIGN-KEY row-id
                          :SET NIL))
 
  
   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR policy-attr-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET NIL)))


   (:base-table dod_auth_attr_lookup))

;;;;;;;;;;;;;;;;;;;; class dod-auth-policy

;; ----------------------------------------------------------------------------
;; 实体：dod-auth-policy
;; 表：DOD_AUTH_POLICY
;; 含义：ABAC 策略实体。policy-func 字段保存策略 Lisp 函数名字符串，
;;       PDP（has-permission）通过 (intern policy-func :nstores) → funcall 求值。
;; 关键字段：
;;   name           策略名（"com.hhub.policy.xxx"）
;;   description    描述
;;   policy-func    策略函数名字符串（→ com-hhub-policy-*）
;;   tenant-id      多租户隔离键（系统级策略 tenant_id=1）
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-auth-policy ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (name
    :type (string 50)
    :initarg :name)
   (description
    :type (string 100)
    :initarg :description)
   (policy-func
    :type (string 255)
    :initarg :policy-func)



        (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)

        (active-flg
    :type (string 1)
    :void-value "Y"
    :initarg :active-flg)



 (created-by
    :TYPE INTEGER
    :INITARG :created-by)
   (attr-created-by
    :ACCESSOR attr-created-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
                          :HOME-KEY created-by
                          :FOREIGN-KEY row-id
                          :SET NIL))
 
  
   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR policy-attr-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET NIL)))



   (:base-table dod_auth_policy))


;;;; DEFINE CLASS FOR TABLE DOD_AUTH_POLICY_ATTR

;; ----------------------------------------------------------------------------
;; 实体：dod-auth-policy-attr
;; 表：DOD_AUTH_POLICY_ATTR
;; 含义：策略 ↔ 属性 多对多关联表，附带 attr-val（PAP UI 录入的占位值，
;;       用于文档化策略关心哪些属性，并不参与 PDP 实际求值）。
;; 关键字段：
;;   policy-id      → dod-auth-policy
;;   attribute-id   → dod-auth-attr-lookup
;;   attr-val       属性的示例/占位值
;;   tenant-id      多租户隔离键
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-auth-policy-attr ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)

   (policy-id
    :type integer
    :initarg :policy-id)
  
   (attribute-id
    :type integer
    :initarg :attribute-id)
   (attr-val 
    :type (string 100)
    :initarg :attr-val)
  
   (tenant-id
    :type integer
    :initarg :tenant-id)
 

     (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)

        (active-flg
    :type (string 1)
    :void-value "Y"
    :initarg :active-flg))

   (:base-table dod_auth_policy_attr))



