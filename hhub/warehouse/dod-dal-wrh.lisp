;;; dod-dal-wrh.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：warehouse —— 仓库（含所有权 / GST 合规 / 多类型）
;;;; 分层：DAL（数据访问层）—— 新风格（DDD：RequestModel / Response / View / BO + DBService）
;;;; 文件：hhub/warehouse/dod-dal-wrh.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 warehouse 模块的全套 DDD 类与 CLSQL 实体：
;;;;       - 服务层：WarehouseAdapter / WarehousePresenter / WarehouseService /
;;;;                 WarehouseDBService / WarehouseHTMLView / WarehouseJSONView
;;;;       - DTO：WarehouseViewModel / WarehouseResponseModel /
;;;;              WarehouseRequestModel / WarehouseSearchRequestModel
;;;;       - 业务对象：Warehouse（41 字段：基础信息 + 所有权模型 + GST + 仓库分类
;;;;                                   + 物流 + 经纬度 + 库存计价 + 多租户）
;;;;       - 数据库实体：dod-warehouse → DOD_WAREHOUSE
;;;;
;;;; 主要导出：
;;;;   dod-warehouse                 —— 数据库实体
;;;;   Warehouse                     —— 业务对象
;;;;   WarehouseViewModel / -ResponseModel / -RequestModel /
;;;;     WarehouseSearchRequestModel —— DTO 四件套
;;;;   WarehouseAdapter / WarehousePresenter / WarehouseService /
;;;;     WarehouseDBService / WarehouseHTMLView / WarehouseJSONView
;;;;
;;;; 关联：
;;;;   上游使用方：warehouse/dod-bl-wrh.lisp（业务方法）、warehouse/dod-ui-wrh.lisp。
;;;;   下游依赖：vendor/dod-dal-ven.lisp（dod-vend-profile，所有者关联）、
;;;;             account/dod-company。
;;;;
;;;; 备注：本文件采用项目"新风格"（DDD 层分明，所有 BO/DTO 一一对应；
;;;;       与传统 dod-dal-* 文件相比，DTO 更细分、字段含义更清晰）。
;;;; ============================================================================

;; nst-dal-warehouse.lisp
;; Data Access Layer for Warehouse entity (UPDATED with ownership fields - 41 fields)
(in-package :nstores)

;;; ---------------------------------------------------------------------------
;;; Service Layer Classes
;;; 中文：仓库模块服务层占位 CLOS 类，方法分派在 dod-bl-wrh.lisp 中实现。
;;;       Adapter   —— 接收 RequestModel → 调用 BusinessService → 输出 ResponseModel
;;;       Presenter —— ResponseModel → ViewModel
;;;       Service   —— BusinessService 业务方法主体
;;;       DBService —— 业务对象 ↔ DB 实体的桥
;;;       HTMLView / JSONView —— 渲染层
;;; ---------------------------------------------------------------------------
(defclass WarehouseAdapter (AdapterService)
  ())

(defclass WarehouseDBService (DBAdapterService)
  ())

(defclass WarehousePresenter (PresenterService)
  ())

(defclass WarehouseService (BusinessService)
  ())

(defclass WarehouseHTMLView (HTMLView)
  ())

(defclass WarehouseJSONView (JSONView)
  ())

;;; ---------------------------------------------------------------------------
;;; ViewModel Classes
;;; 中文：渲染层 DTO，字段为 warehouse 业务的展示视图（控件 prefix w*：wname/waddr1/...）。
;;; ---------------------------------------------------------------------------
(defclass WarehouseViewModel (ViewModel)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   
   ;; UNIQUE IDENTIFIERS
   (warehouse-uuid
    :accessor warehouse-uuid
    :initarg :warehouse-uuid
    :documentation "System UUID for internal/API use")
   
   (warehouse-code
    :accessor warehouse-code
    :initarg :warehouse-code
    :documentation "Business-friendly code (e.g., MH-MUM-WH-001)")
   
   ;; BASIC INFO
   (wname
    :initarg :wname
    :accessor wname)
   (waddr1
    :initarg :waddr1
    :accessor waddr1)
   (waddr2
    :initarg :waddr2
    :accessor waddr2)
   (wpin
    :initarg :wpin
    :accessor wpin)
   (wcity
    :initarg :wcity
    :accessor wcity)
   (wstate
    :initarg :wstate
    :accessor wstate)
   (wcountry
    :initarg :wcountry
    :accessor wcountry)
   (wmanager
    :initarg :wmanager
    :accessor wmanager)
   (wphone
    :initarg :wphone
    :accessor wphone)
   (waltphone
    :initarg :waltphone
    :accessor waltphone)
   (wemail
    :initarg :wemail
    :accessor wemail)
   
   ;; AUDIT FIELDS
   (activeflag
    :initarg :activeflag
    :accessor activeflag)
   
   ;; OWNERSHIP MODEL (NEW FIELDS)
   (ownership-type
    :initarg :ownership-type
    :accessor ownership-type
    :documentation "Who owns the warehouse: SELLER_OWNED, BUYER_OWNED, THIRD_PARTY, PLATFORM_OWNED, BONDED, CONTRACT_MFG")
   
   (owner-entity-type
    :initarg :owner-entity-type
    :accessor owner-entity-type
    :documentation "Type of owner: SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS, GOVERNMENT")
   
   (owner-entity-id
    :initarg :owner-entity-id
    :accessor owner-entity-id
    :documentation "Foreign key to owner entity")
   (vendor
    :initarg :vendor
    :accessor vendor
    :documentation "By default the vendor is the owner of this warehouse")
   (operator-entity-type
    :initarg :operator-entity-type
    :accessor operator-entity-type
    :documentation "Who operates: SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS")
   
   (operator-entity-id
    :initarg :operator-entity-id
    :accessor operator-entity-id
    :documentation "Foreign key to operator entity")
   
   (legal-entity-type
    :initarg :legal-entity-type
    :accessor legal-entity-type
    :documentation "Entity registered for GST: SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS")
   
   ;; GST COMPLIANCE
   (warehouse-gstin
    :initarg :warehouse-gstin
    :accessor warehouse-gstin)
   (gstin-status
    :initarg :gstin-status
    :accessor gstin-status)
   (legal-name
    :initarg :legal-name
    :accessor legal-name)
   (is-primary-location
    :initarg :is-primary-location
    :accessor is-primary-location)
   (state-code
    :initarg :state-code
    :accessor state-code)
   (registration-type
    :initarg :registration-type
    :accessor registration-type)
   (pan-number
    :initarg :pan-number
    :accessor pan-number)
   
   ;; WAREHOUSE CLASSIFICATION
   (warehouse-type
    :initarg :warehouse-type
    :accessor warehouse-type)
   (warehouse-purpose
    :initarg :warehouse-purpose
    :accessor warehouse-purpose)
   
   ;; LOGISTICS
   (default-transporter-id
    :initarg :default-transporter-id
    :accessor default-transporter-id)
   (default-transporter-name
    :initarg :default-transporter-name
    :accessor default-transporter-name)
   (eway-bill-enabled
    :initarg :eway-bill-enabled
    :accessor eway-bill-enabled)
   
   ;; LOCATION
   (latitude
    :initarg :latitude
    :accessor latitude)
   (longitude
    :initarg :longitude
    :accessor longitude)
   
   ;; INVENTORY MANAGEMENT
   (valuation-method
    :initarg :valuation-method
    :accessor valuation-method)
   (hsn-wise-stock
    :initarg :hsn-wise-stock
    :accessor hsn-wise-stock)
   
   ;; TENANT
   (company
    :initarg :company
    :accessor company)))

;;; ---------------------------------------------------------------------------
;;; ResponseModel Classes
;;; 中文：业务层向外输出的 DTO（与 ViewModel 同字段，但语义为业务返回）。
;;; ---------------------------------------------------------------------------
(defclass WarehouseResponseModel (ResponseModel)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   
   ;; UNIQUE IDENTIFIERS
   (warehouse-uuid
    :accessor warehouse-uuid
    :initarg :warehouse-uuid
    :documentation "System UUID for internal/API use")
   
   (warehouse-code
    :accessor warehouse-code
    :initarg :warehouse-code
    :documentation "Business-friendly code (e.g., MH-MUM-WH-001)")
   
   ;; BASIC INFO
   (wname
    :initarg :wname
    :accessor wname)
   (waddr1
    :initarg :waddr1
    :accessor waddr1)
   (waddr2
    :initarg :waddr2
    :accessor waddr2)
   (wpin
    :initarg :wpin
    :accessor wpin)
   (wcity
    :initarg :wcity
    :accessor wcity)
   (wstate
    :initarg :wstate
    :accessor wstate)
   (wcountry
    :initarg :wcountry
    :accessor wcountry)
   (wmanager
    :initarg :wmanager
    :accessor wmanager)
   (wphone
    :initarg :wphone
    :accessor wphone)
   (waltphone
    :initarg :waltphone
    :accessor waltphone)
   (wemail
    :initarg :wemail
    :accessor wemail)
   
   ;; AUDIT FIELDS
   (activeflag
    :initarg :activeflag
    :accessor activeflag)
   
   ;; OWNERSHIP MODEL
   (ownership-type
    :initarg :ownership-type
    :accessor ownership-type)
   
   (owner-entity-type
    :initarg :owner-entity-type
    :accessor owner-entity-type)
   
   (owner-entity-id
    :initarg :owner-entity-id
    :accessor owner-entity-id)
   (vendor
    :initarg :vendor
    :accessor vendor
    :documentation "By default the vendor is the owner of this warehouse")
   (operator-entity-type
    :initarg :operator-entity-type
    :accessor operator-entity-type)
   
   (operator-entity-id
    :initarg :operator-entity-id
    :accessor operator-entity-id)
   
   (legal-entity-type
    :initarg :legal-entity-type
    :accessor legal-entity-type)
   
   ;; GST COMPLIANCE
   (warehouse-gstin
    :initarg :warehouse-gstin
    :accessor warehouse-gstin)
   (gstin-status
    :initarg :gstin-status
    :accessor gstin-status)
   (legal-name
    :initarg :legal-name
    :accessor legal-name)
   (is-primary-location
    :initarg :is-primary-location
    :accessor is-primary-location)
   (state-code
    :initarg :state-code
    :accessor state-code)
   (registration-type
    :initarg :registration-type
    :accessor registration-type)
   (pan-number
    :initarg :pan-number
    :accessor pan-number)
   
   ;; WAREHOUSE CLASSIFICATION
   (warehouse-type
    :initarg :warehouse-type
    :accessor warehouse-type)
   (warehouse-purpose
    :initarg :warehouse-purpose
    :accessor warehouse-purpose)
   
   ;; LOGISTICS
   (default-transporter-id
    :initarg :default-transporter-id
    :accessor default-transporter-id)
   (default-transporter-name
    :initarg :default-transporter-name
    :accessor default-transporter-name)
   (eway-bill-enabled
    :initarg :eway-bill-enabled
    :accessor eway-bill-enabled)
   
   ;; LOCATION
   (latitude
    :initarg :latitude
    :accessor latitude)
   (longitude
    :initarg :longitude
    :accessor longitude)
   
   ;; INVENTORY MANAGEMENT
   (valuation-method
    :initarg :valuation-method
    :accessor valuation-method)
   (hsn-wise-stock
    :initarg :hsn-wise-stock
    :accessor hsn-wise-stock)
   
   ;; TENANT
   (company
    :initarg :company
    :accessor company)))

;;; ---------------------------------------------------------------------------
;;; RequestModel Classes
;;; 中文：HTTP/控制器接收的入参 DTO；ownership-type / owner-entity-type / legal-entity-type
;;;       带默认值（SELLER_OWNED / SELLER / SELLER），适用于自营卖家直接建仓。
;;;       WarehouseSearchRequestModel 复用同一组字段做查询条件。
;;; ---------------------------------------------------------------------------
(defclass WarehouseRequestModel (RequestModel)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   
   ;; UNIQUE IDENTIFIERS
   (warehouse-uuid
    :accessor warehouse-uuid
    :initarg :warehouse-uuid
    :documentation "System UUID for internal/API use")
   
   (warehouse-code
    :accessor warehouse-code
    :initarg :warehouse-code
    :documentation "Business-friendly code (e.g., MH-MUM-WH-001)")
   
   ;; BASIC INFO
   (wname
    :initarg :wname
    :accessor wname)
   (waddr1
    :initarg :waddr1
    :accessor waddr1)
   (waddr2
    :initarg :waddr2
    :accessor waddr2)
   (wpin
    :initarg :wpin
    :accessor wpin)
   (wcity
    :initarg :wcity
    :accessor wcity)
   (wstate
    :initarg :wstate
    :accessor wstate)
   (wcountry
    :initarg :wcountry
    :accessor wcountry)
   (wmanager
    :initarg :wmanager
    :accessor wmanager)
   (wphone
    :initarg :wphone
    :accessor wphone)
   (waltphone
    :initarg :waltphone
    :accessor waltphone)
   (wemail
    :initarg :wemail
    :accessor wemail)
   
   ;; AUDIT FIELDS
   (activeflag
    :initarg :activeflag
    :accessor activeflag)
   
   ;; OWNERSHIP MODEL
   (ownership-type
    :initarg :ownership-type
    :accessor ownership-type
    :initform "SELLER_OWNED")
   
   (owner-entity-type
    :initarg :owner-entity-type
    :accessor owner-entity-type
    :initform "SELLER")
   
   (owner-entity-id
    :initarg :owner-entity-id
    :accessor owner-entity-id)
   (vendor
    :initarg :vendor
    :accessor vendor
    :documentation "By default the vendor is the owner of this warehouse")
   (operator-entity-type
    :initarg :operator-entity-type
    :accessor operator-entity-type)
   
   (operator-entity-id
    :initarg :operator-entity-id
    :accessor operator-entity-id)
   
   (legal-entity-type
    :initarg :legal-entity-type
    :accessor legal-entity-type
    :initform "SELLER")
   
   ;; GST COMPLIANCE
   (warehouse-gstin
    :initarg :warehouse-gstin
    :accessor warehouse-gstin)
   (gstin-status
    :initarg :gstin-status
    :accessor gstin-status)
   (legal-name
    :initarg :legal-name
    :accessor legal-name)
   (is-primary-location
    :initarg :is-primary-location
    :accessor is-primary-location)
   (state-code
    :initarg :state-code
    :accessor state-code)
   (registration-type
    :initarg :registration-type
    :accessor registration-type)
   (pan-number
    :initarg :pan-number
    :accessor pan-number)
   
   ;; WAREHOUSE CLASSIFICATION
   (warehouse-type
    :initarg :warehouse-type
    :accessor warehouse-type)
   (warehouse-purpose
    :initarg :warehouse-purpose
    :accessor warehouse-purpose)
   
   ;; LOGISTICS
   (default-transporter-id
    :initarg :default-transporter-id
    :accessor default-transporter-id)
   (default-transporter-name
    :initarg :default-transporter-name
    :accessor default-transporter-name)
   (eway-bill-enabled
    :initarg :eway-bill-enabled
    :accessor eway-bill-enabled)
   
   ;; LOCATION
   (latitude
    :initarg :latitude
    :accessor latitude)
   (longitude
    :initarg :longitude
    :accessor longitude)
   
   ;; INVENTORY MANAGEMENT
   (valuation-method
    :initarg :valuation-method
    :accessor valuation-method)
   (hsn-wise-stock
    :initarg :hsn-wise-stock
    :accessor hsn-wise-stock)
   
   ;; TENANT
   (company
    :initarg :company
    :accessor company)))

(defclass WarehouseSearchRequestModel (WarehouseRequestModel)
  ())

;;; ---------------------------------------------------------------------------
;;; Business Object (Domain Model)
;;; 中文：仓库领域模型。包含：
;;;   - 唯一标识：warehouse-uuid（系统 UUID）/ warehouse-code（业务码 MH-MUM-WH-001）
;;;   - 基础信息：wname / waddr1/2 / wpin / wcity / wstate / wcountry / wmanager / wphone / waltphone / wemail
;;;   - 所有权模型（OWNERSHIP MODEL）：
;;;       ownership-type      —— SELLER_OWNED / BUYER_OWNED / THIRD_PARTY / PLATFORM_OWNED / BONDED / CONTRACT_MFG
;;;       owner-entity-type   —— SELLER / BUYER / PLATFORM / THIRD_PARTY_LOGISTICS / GOVERNMENT
;;;       owner-entity-id     —— 外键到所有者实体（默认指向 vendor）
;;;       operator-entity-*   —— 实际运营方（与所有者可不同）
;;;       legal-entity-type   —— GST 注册主体类型
;;;   - GST 合规：warehouse-gstin / gstin-status / legal-name / is-primary-location /
;;;               state-code / registration-type / pan-number
;;;   - 仓库分类：warehouse-type（按场地）/ warehouse-purpose（按用途）
;;;   - 物流：default-transporter-id/-name / eway-bill-enabled
;;;   - 经纬度：latitude / longitude
;;;   - 库存计价：valuation-method / hsn-wise-stock
;;;   - 多租户：company（关联 dod-company）
;;; ---------------------------------------------------------------------------
(defclass Warehouse (BusinessObject)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   
   ;; UNIQUE IDENTIFIERS
   (warehouse-uuid
    :accessor warehouse-uuid
    :initarg :warehouse-uuid
    :documentation "System UUID for internal/API use")
   
   (warehouse-code
    :accessor warehouse-code
    :initarg :warehouse-code
    :documentation "Business-friendly code (e.g., MH-MUM-WH-001)")
   
   ;; BASIC INFO
   (wname
    :initarg :wname
    :accessor wname)
   (waddr1
    :initarg :waddr1
    :accessor waddr1)
   (waddr2
    :initarg :waddr2
    :accessor waddr2)
   (wpin
    :initarg :wpin
    :accessor wpin)
   (wcity
    :initarg :wcity
    :accessor wcity)
   (wstate
    :initarg :wstate
    :accessor wstate)
   (wcountry
    :initarg :wcountry
    :accessor wcountry)
   (wmanager
    :initarg :wmanager
    :accessor wmanager)
   (wphone
    :initarg :wphone
    :accessor wphone)
   (waltphone
    :initarg :waltphone
    :accessor waltphone)
   (wemail
    :initarg :wemail
    :accessor wemail)
   
   ;; AUDIT FIELDS
   (activeflag
    :initarg :activeflag
    :accessor activeflag)
   
   ;; OWNERSHIP MODEL
   (ownership-type
    :initarg :ownership-type
    :accessor ownership-type
    :documentation "SELLER_OWNED, BUYER_OWNED, THIRD_PARTY, PLATFORM_OWNED, BONDED, CONTRACT_MFG")
   
   (owner-entity-type
    :initarg :owner-entity-type
    :accessor owner-entity-type
    :documentation "SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS, GOVERNMENT")
   
   (owner-entity-id
    :initarg :owner-entity-id
    :accessor owner-entity-id
    :documentation "FK to owner entity")

   (vendor
    :initarg :vendor
    :accessor vendor
    :documentation "By default the vendor is the owner of this warehouse")
   
   (operator-entity-type
    :initarg :operator-entity-type
    :accessor operator-entity-type
    :documentation "SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS")
   
   (operator-entity-id
    :initarg :operator-entity-id
    :accessor operator-entity-id
    :documentation "FK to operator entity")
   
   (legal-entity-type
    :initarg :legal-entity-type
    :accessor legal-entity-type
    :documentation "SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS")
   
   ;; GST COMPLIANCE
   (warehouse-gstin
    :initarg :warehouse-gstin
    :accessor warehouse-gstin)
   (gstin-status
    :initarg :gstin-status
    :accessor gstin-status)
   (legal-name
    :initarg :legal-name
    :accessor legal-name)
   (is-primary-location
    :initarg :is-primary-location
    :accessor is-primary-location)
   (state-code
    :initarg :state-code
    :accessor state-code)
   (registration-type
    :initarg :registration-type
    :accessor registration-type)
   (pan-number
    :initarg :pan-number
    :accessor pan-number)
   
   ;; WAREHOUSE CLASSIFICATION
   (warehouse-type
    :initarg :warehouse-type
    :accessor warehouse-type)
   (warehouse-purpose
    :initarg :warehouse-purpose
    :accessor warehouse-purpose)
   
   ;; LOGISTICS
   (default-transporter-id
    :initarg :default-transporter-id
    :accessor default-transporter-id)
   (default-transporter-name
    :initarg :default-transporter-name
    :accessor default-transporter-name)
   (eway-bill-enabled
    :initarg :eway-bill-enabled
    :accessor eway-bill-enabled)
   
   ;; LOCATION
   (latitude
    :initarg :latitude
    :accessor latitude)
   (longitude
    :initarg :longitude
    :accessor longitude)
   
   ;; INVENTORY MANAGEMENT
   (valuation-method
    :initarg :valuation-method
    :accessor valuation-method)
   (hsn-wise-stock
    :initarg :hsn-wise-stock
    :accessor hsn-wise-stock)
   
   ;; TENANT
   (company
    :initarg :company
    :accessor company)))

;;; ---------------------------------------------------------------------------
;;; Database View Class (ORM Mapping) - COMPLETE with ownership fields
;;; 中文：CLSQL 实体映射 DOD_WAREHOUSE 表，41 字段。
;;; ----------------------------------------------------------------------------
;;; 实体：dod-warehouse
;;; 表：DOD_WAREHOUSE
;;; 含义：仓库主表。命名约定：DB 列名前缀 w-*（w-name/w-addr1/...），
;;;       但业务对象/DTO 用 wname/waddr1（无连字符）。拷贝层负责适配。
;;; 关键字段：
;;;   row-id            主键
;;;   warehouse-uuid    系统 UUID（NOT NULL UNIQUE）
;;;   warehouse-code    业务码（NOT NULL UNIQUE）
;;;   tenant-id         多租户隔离键 → dod-company.row-id
;;;   active-flag       Y/N 启用
;;;   deleted-state     N/Y 软删
;;;   created / updated wall-time 字符串（30 位）
;;;   owner-entity-id   join 到 dod-vend-profile（accessor 为 vendor）
;;; 备注：created/updated 用 string-30 而不是 wall-time 类型，是为了
;;;       既能存入"YYYY-MM-DD HH:MM:SS"又支持其它来源的字符串（见 commit 854607e）。
;;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-warehouse ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id
    :accessor row-id)
   
   ;; UNIQUE IDENTIFIERS
   (warehouse-uuid
    :accessor warehouse-uuid
    :type (string 36)
    :initarg :warehouse-uuid
    :db-constraints (:not-null :unique))
   
   (warehouse-code
    :accessor warehouse-code
    :type (string 20)
    :initarg :warehouse-code
    :db-constraints (:not-null :unique))
   
   ;; BASIC INFO
   (w-name
    :accessor w-name
    :type (string 100)
    :initarg :w-name)
   (w-addr1
    :accessor w-addr1
    :type (string 100)
    :initarg :w-addr1)
   (w-addr2
    :accessor w-addr2
    :type (string 100)
    :initarg :w-addr2)
   (w-pin
    :accessor w-pin
    :type (string 6)
    :initarg :w-pin)
   (w-city
    :accessor w-city
    :type (string 30)
    :initarg :w-city)
   (w-state
    :accessor w-state
    :type (string 30)
    :initarg :w-state)
   (w-country
    :accessor w-country
    :type (string 30)
    :initarg :w-country)
   (w-manager
    :accessor w-manager
    :type (string 100)
    :initarg :w-manager)
   (w-phone
    :accessor w-phone
    :type (string 16)
    :initarg :w-phone)
   (w-alt-phone
    :accessor w-alt-phone
    :type (string 16)
    :initarg :w-alt-phone)
   (w-email
    :accessor w-email
    :type (string 100)
    :initarg :w-email)
   
   ;; AUDIT FIELDS
   (created
    :accessor created
    :type (string 30)
    :initarg :created
    :db-kind :base)
   (updated
    :accessor updated
    :type (string 30)
    :initarg :updated
    :db-kind :base)
   (deleted-state
    :accessor deleted-state
    :type (string 1)
    :initarg :deleted-state)
   (active-flag
    :accessor active-flag
    :type (string 1)
    :initarg :active-flag)
   
   ;; MULTI-TENANCY
   (tenant-id
    :type integer
    :initarg :tenant-id
    :accessor tenant-id)
   
   ;; OWNERSHIP MODEL (NEW FIELDS)
   (ownership-type
    :accessor ownership-type
    :type (string 30)
    :initarg :ownership-type
    :documentation "SELLER_OWNED, BUYER_OWNED, THIRD_PARTY, PLATFORM_OWNED, BONDED, CONTRACT_MFG")
   
   (owner-entity-type
    :accessor owner-entity-type
    :type (string 30)
    :initarg :owner-entity-type
    :documentation "SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS, GOVERNMENT")
   
   (owner-entity-id
    :accessor owner-entity-id
    :type integer
    :initarg :owner-entity-id
    :documentation "FK to owner entity")
   (vendor 
    :accessor vendor
    :db-kind :join
    :db-info (:join-class dod-vend-profile
                          :home-key owner-entity-id
                          :foreign-key row-id
                          :set nil))
   
   
   (operator-entity-type
    :accessor operator-entity-type
    :type (string 30)
    :initarg :operator-entity-type
    :documentation "SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS")
   
   (operator-entity-id
    :accessor operator-entity-id
    :type integer
    :initarg :operator-entity-id
    :documentation "FK to operator entity")
   
   (legal-entity-type
    :accessor legal-entity-type
    :type (string 30)
    :initarg :legal-entity-type
    :documentation "SELLER, BUYER, PLATFORM, THIRD_PARTY_LOGISTICS")
   
   ;; GST COMPLIANCE
   (warehouse-gstin
    :accessor warehouse-gstin
    :type (string 15)
    :initarg :warehouse-gstin)
   (gstin-status
    :accessor gstin-status
    :type (string 20)
    :initarg :gstin-status)
   (legal-name
    :accessor legal-name
    :type (string 200)
    :initarg :legal-name)
   (is-primary-location
    :accessor is-primary-location
    :type integer
    :initarg :is-primary-location)
   (state-code
    :accessor state-code
    :type (string 2)
    :initarg :state-code)
   (registration-type
    :accessor registration-type
    :type (string 30)
    :initarg :registration-type)
   (pan-number
    :accessor pan-number
    :type (string 10)
    :initarg :pan-number)
   
   ;; WAREHOUSE CLASSIFICATION
   (warehouse-type
    :accessor warehouse-type
    :type (string 30)
    :initarg :warehouse-type)
   (warehouse-purpose
    :accessor warehouse-purpose
    :type (string 30)
    :initarg :warehouse-purpose)
   
   ;; LOGISTICS
   (default-transporter-id
    :accessor default-transporter-id
    :type (string 15)
    :initarg :default-transporter-id)
   (default-transporter-name
    :accessor default-transporter-name
    :type (string 200)
    :initarg :default-transporter-name)
   (eway-bill-enabled
    :accessor eway-bill-enabled
    :type integer
    :initarg :eway-bill-enabled)
   
   ;; LOCATION
   (latitude
    :accessor latitude
    :type float
    :initarg :latitude)
   (longitude
    :accessor longitude
    :type float
    :initarg :longitude)
   
   ;; INVENTORY MANAGEMENT
   (valuation-method
    :accessor valuation-method
    :type (string 20)
    :initarg :valuation-method)
   (hsn-wise-stock
    :accessor hsn-wise-stock
    :type integer
    :initarg :hsn-wise-stock)
   
   ;; COMPANY JOIN
   (company
    :accessor get-company
    :db-kind :join
    :db-info (:join-class dod-company
                          :home-key tenant-id
                          :foreign-key row-id
                          :set nil)))
  (:base-table dod_warehouse))

;;; End of nst-dal-warehouse.lisp

