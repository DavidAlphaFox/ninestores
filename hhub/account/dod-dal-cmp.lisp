;;; dod-dal-cmp.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：account 账户/租户
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/account/dod-dal-cmp.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义"租户/公司"主数据相关的领域对象与 CLSQL view-class。
;;;;       包含 BusinessObject 风格的 hhubstore（应是新式 DDD 领域对象，
;;;;       推测：尚处早期/部分使用），以及主流持久化实体 dod-company。
;;;;
;;;; 主要导出：
;;;;   hhubstore        — 业务对象（推测：商家/门店领域抽象，后续向 DDD 迁移用）
;;;;   communitystore   — hhubstore 的子类，社区类商家
;;;;   dod-company      — 租户/公司表 DOD_COMPANY 的 CLSQL view-class（核心 tenant 实体）
;;;;
;;;; 关联：
;;;;   上游使用方：account/dod-bl-cmp.lisp（公司 CRUD/订阅升级），
;;;;               几乎所有模块的多租户过滤都引用 dod-company.row-id
;;;;   下游依赖：core 的 BusinessObject 基类、sysuser/dod-dal-sys.lisp（dod-users）
;;;; ============================================================================

(in-package :nstores)
;;(clsql:file-enable-sql-reader-syntax)

;; ----------------------------------------------------------------------------
;; 类：hhubstore
;; 含义：应是商家/门店的领域对象（DDD 风格），可挂 logo/banner/地址/订阅套餐等元数据。
;;      推测：尚未完全替代 dod-company，目前作为 BusinessObject 派生体存在。
;; 关键 slot：
;;   name / logo / banner       展示信息
;;   address / city / state / country / zipcode    地址
;;   website / external-url     站点外链
;;   tshirt-size                规模档位（SM/MD/LG…）
;;   revenue                    营收档位
;;   subscription-plan          订阅套餐
;;   suspend-flag               是否被冻结
;;   employees / customers / vendors  关联集合
;; ----------------------------------------------------------------------------
(defclass hhubstore (BusinessObject)
  ((name
    :accessor name
    :initform "defaulthhubstore"
    :initarg :name )
   (logo
    :accessor logo
    :initform ""
    :initarg :logo)
   (banner
    :accessor banner
    :initform ""
    :initarg :banner)
   (address
    :accessor address
    :initarg :address)
   (city
    :accessor city
    :initarg :city)
   (state
    :accessor state
    :type (string 256)
    :initarg :state)
   (country
    :accessor country
    :type (string 256)
    :initarg :country)
   (zipcode
    :accessor zipcode
    :type (string 10)
    :initarg :zipcode)
   (website 
    :accessor website
    :type (string 256)
    :initarg :website)
   (tshirt-size
    :accessor website
    :initform "sm"
    :initarg :tshirt-size)
   (revenue
    :accessor revenue
    :initarg :revenue)
   (subscription-plan
    :accessor subscription-plan
    :initarg :subscription-plan)
   (external-url
    :accessor external-url
    :initarg :external-url)
   (suspend-flag
    :accessor suspend-flag
    :initarg :suspend-flag)
   (created
    :accessor created
    :initform (get-universal-time)
    :initarg :created)
   (employees
    :accessor employees
    :initarg :employees)
   (customers
    :accessor customers
    :initarg :customers)
   (vendors
    :accessor vendors
    :initarg :vendors)))

;; ----------------------------------------------------------------------------
;; 类：communitystore
;; 含义：社区型商家（cmp-type='COMMUNITY'）领域对象，目前未扩展额外 slot。
;; ----------------------------------------------------------------------------
(defclass communitystore (hhubstore)
  ())


;; Generic functions for a store.




;; ----------------------------------------------------------------------------
;; 实体：dod-company
;; 表：DOD_COMPANY
;; 含义：Nine Stores 的多租户主表 —— 一行 = 一个租户/公司。几乎所有业务表
;;       都通过 TENANT_ID 引用本表的 row-id 实现租户隔离。
;; 关键字段：
;;   row-id            主键（同时作 tenant-id 被各业务表引用）
;;   name / address / city / state / country / zipcode    地址与名称
;;   website / external-url   公司站点
;;   created / created-by / updated-by   审计字段（updated-by 为外键 → dod-users）
;;   cmp-type          公司类别（如 STANDARD / COMMUNITY / TRIAL …）
;;   suspend-flag      被运营方冻结标志（'Y' 即停用，PIP 用于策略判定）
;;   tshirt-size       规模档（SM/MD/LG…），影响订阅与配额
;;   revenue           营收档位
;;   subscription-plan 订阅套餐（BASIC/PROFESSIONAL/TRIAL …），决定配额
;;   deleted-state     软删标志（默认 'N'）
;;   employees         JOIN → dod-users（按 tenant_id 反向汇总该租户全部用户）
;; ----------------------------------------------------------------------------

(clsql:def-view-class dod-company ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (name
    :type (string 255)
    :initarg :name)
   (address
    :type (string 512)
    :initarg :address)
   (city
    :accessor city
    :type (string 256)
    :initarg :city)
   (state
    :accessor state
    :type (string 256)
    :initarg :state)
   (country
    :accessor country
    :type (string 256)
    :initarg :country)
   (zipcode
    :accessor zipcode
    :type (string 10)
    :initarg :zipcode)
   (website 
    :type (string 256)
    :initarg :website)
   (created
    :accessor created
    :type clsql:wall-time
    :initarg :created)     
   (created-by
    :TYPE INTEGER
    :INITARG :created-by)
   (user-created-by
    :ACCESSOR company-created-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
              :HOME-KEY created-by
              :FOREIGN-KEY row-id
              :SET NIL))
   (updated-by
    :TYPE INTEGER
    :INITARG :updated-by)
   (user-updated-by
    :ACCESSOR company-updated-by
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-users
              :HOME-KEY updated-by
              :FOREIGN-KEY row-id
              :SET NIL))
   (cmp-type
    :accessor cmp-type
    :type (string 30)
    :initarg :cmp-type)
   
   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)
   
   (suspend-flag
    :type (string 1)
    :void-value "N"
    :initarg :suspend-flag)
   
   (tshirt-size
    :type (string 2)
    :void-value "SM"
    :initarg :tshirt-size)
   
   (revenue
    :type integer
    :initarg :revenue)
   
   (subscription-plan
    :accessor subscription-plan
    :type (string 50)
    :initarg :subscription-plan)
   
   (external-url
    :type (string 255)
    :initarg :external-url)
   
   (employees
    :reader company-employees
    :db-kind :join
    :db-info (:join-class dod-users
              :home-key row-id
              :foreign-key tenant-id
              :set t)))
  (:base-table dod_company))






