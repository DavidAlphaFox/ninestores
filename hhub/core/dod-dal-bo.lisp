;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— ABAC 元模型实体定义
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/core/dod-dal-bo.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 ABAC 鉴权框架中三个核心元数据实体的 CLSQL view-class，
;;;;       一一映射到 MySQL 表 DOD_BUS_OBJECT / DOD_ABAC_SUBJECT / DOD_BUS_TRANSACTION。
;;;;
;;;; 主要导出：
;;;;   dod-bus-object        — 业务对象/资源类型登记（如 "ORDER"、"INVOICE"）
;;;;   dod-abac-subject      — 主体类型登记（vendor / customer / cad / opr 等）
;;;;   dod-bus-transaction   — URI ↔ trans-func 函数名 ↔ auth-policy 三方绑定
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-bl-bo.lisp（BL CRUD）、core/dod-ui-utl.lisp（PEP 宏）、
;;;;               core/dod-bl-bo.lisp:has-permission（PDP 求值）
;;;;   下游依赖：dod-users / dod-company / dod-auth-policy
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;; ----------------------------------------------------------------------------
;; 实体：dod-bus-object
;; 表：DOD_BUS_OBJECT
;; 含义：业务对象（资源）类型登记表。在 ABAC 模型中代表"对什么资源做操作"。
;; 关键字段：
;;   row-id          主键
;;   name            资源类型名（约定大写，例如 "ORDER" "INVOICE"）
;;   hhub-type       该资源的子分类标记
;;   tenant-id       多租户隔离键 → dod-company.row-id
;;   created-by      创建者用户 → dod-users.row-id
;;   active-flg      Y/N 启用标志
;;   deleted-state   N/Y 软删标志
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-bus-object ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
  (name
    :type (string 50)
    :initarg :name)

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
   (bus-obj-created-by
    :ACCESSOR get-bus-obj-created-by
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
                          :SET NIL))

  (hhub-type
   :type string
   :initarg :hhub-type))

   (:base-table dod_bus_object))


;; ----------------------------------------------------------------------------
;; 实体：dod-abac-subject
;; 表：DOD_ABAC_SUBJECT
;; 含义：主体类型登记表。ABAC 中代表"谁发起请求"，例如 vendor / customer / cad。
;; 关键字段：与 dod-bus-object 完全相同的属性集（name/hhub-type/tenant-id/...）。
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-abac-subject ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
  (name
    :type (string 50)
    :initarg :name)

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
   (bus-obj-created-by
    :ACCESSOR get-bus-obj-created-by
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
  (hhub-type
   :type string
   :initarg :hhub-type)


   (:base-table dod_abac_subject))


;; ----------------------------------------------------------------------------
;; 实体：dod-bus-transaction
;; 表：DOD_BUS_TRANSACTION
;; 含义：ABAC 事务表。把 (URI, Lisp 函数名, 主体类型, 鉴权策略) 四方绑定起来。
;;       PEP 宏 with-hhub-transaction 通过 trans-func 字段查到此实例，
;;       再用 auth-policy-id 跳转到对应策略，由 PDP 求值。
;; 关键字段：
;;   name              事务名（约定 "com.hhub.transaction.xxx"）
;;   uri               允许访问的 URL 前缀，PEP 校验请求 URI 是否匹配
;;   trans-func        Lisp 控制器函数名（字符串），通常等于 com-hhub-transaction-xxx
;;   auth-policy-id    外键 → dod-auth-policy（决定调用哪条策略）
;;   abac-subject-id   外键 → dod-abac-subject（限定可发起此事务的主体类型）
;;   trans-type        事务种类标识
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-bus-transaction ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (name
    :type (string 50)
    :initarg :name)
   
   (uri
    :type (string 100)
    :initarg :uri)
   
   (trans-func
    :type (string 100)
    :initarg :trans-func)
   
   (auth-policy-id
    :type integer
    :initarg :auth-policy-id)
   (bus-tran-policy
    :ACCESSOR get-bus-tran-policy
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-auth-policy
              :HOME-KEY auth-policy-id
                          :FOREIGN-KEY row-id
              :SET NIL))
   
   (abac-subject-id
    :type integer
    :initarg abac-subject-id)
   (bus-tran-abac-subject
    :accessor get-bus-tran-abac-subject
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-abac-subject
	      :HOME-KEY abac-subject-id
	      :FOREIGN-KEY row-id
	      :SET NIL))
   
   
   (trans-type
    :type (string 15)
    :initarg :trans-type)
   
   
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
   (bus-tran-created-by
    :ACCESSOR get-bus-tran-created-by
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
  
  
  
  (:base-table dod_bus_transaction))

   
