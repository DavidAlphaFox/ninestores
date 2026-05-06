;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 密码重置实体
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/core/dod-dal-pas.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 dod-password-reset CLSQL view-class，对应 DOD_PASSWORD_RESET 表。
;;;;       存储用户发起密码重置时生成的一次性 token。
;;;;
;;;; 主要导出：
;;;;   dod-password-reset    — view-class（user-type/email/token/active-flg/...）
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-bl-pas.lisp（业务侧 token 生成/校验）
;;;;   下游依赖：dod-company（多租户隔离）
;;;; ============================================================================
(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 实体：dod-password-reset
;; 表：DOD_PASSWORD_RESET
;; 含义：登录方"忘记密码"流程下发的重置令牌记录。
;; 关键字段：
;;   row-id          主键
;;   user-type       用户类型：CUSTOMER / VENDOR / EMPLOYEE
;;   email           接收重置邮件的邮箱地址
;;   token           随机生成的一次性 token（URL 校验用）
;;   created         记录创建时间（用于 TTL 过期判定）
;;   active-flg      Y=token 仍可用、N=已使用或失效
;;   deleted-state   软删标志
;;   tenant-id       多租户隔离键 → dod-company.row-id
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-password-reset ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)

   ; USER-TYPE = CUSTOMER, VENDOR, EMPLOYEE
   (user-type
    :accessor user-type
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 30)
    :INITARG :user-type)

      (email
    :accessor email
    :type (string 255)
    :initarg :email)


   (created
    :accessor created
    :type clsql:wall-time
    :initarg :created)
   
   (token
    :accessor token
    :type (string 512)
    :initarg :token)
   
   (active-flg
    :accessor active-flg
    :type (string 1)
    :void-value "N"
    :initarg :active-flg)

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)
   
   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR reset-password-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET T)))

   
  (:BASE-TABLE dod_password_reset))

