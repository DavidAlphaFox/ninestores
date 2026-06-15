;;; nst-dal-aientity.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.


;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— AI 采购实体 DAL —— DOD_PROCURE_ENTITY 数据访问层
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/core/nst-dal-aientity.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 DOD_PROCURE_ENTITY 表的 CLSQL 视图类、请求/响应/视图模型、
;;;;       适配器、服务、展示器及视图类。复合主键 (ENTITY_ID, TENANT_ID)，
;;;;       无软删除（实体为权威记录）。为 AI 采购锚点/身份识别提供数据层支撑。
;;;;
;;;; 主要导出：
;;;;   dod-procure-entity         — CLSQL 视图类，映射 dod_procure_entity 表
;;;;   AIEntityRequestModel         — 创建/更新请求模型
;;;;   AIEntitySearchRequestModel   — 搜索请求模型（含 entitytype-filter）
;;;;   AIEntityResponseModel        — 响应模型
;;;;   AIEntityViewModel            — 视图模型
;;;;   AIEntityHTMLView             — HTML 视图类
;;;;   AIEntity / AIEntityAdapter / AIEntityDBService / AIEntityPresenter / AIEntityService / AIEntityJSONView — 领域对象及服务层类
;;;;
;;;; 关联：
;;;;   上游使用方：BL 层业务逻辑（如 nst-bl-aientity.lisp）
;;;;   下游依赖：CLSQL、nstores 包基础设施（RequestModel/ResponseModel/ViewModel/BusinessObject 等）
;;;; ============================================================================
(in-package :nstores)

;; nst-dal-aientity.lisp
;; DAL layer for DOD_PROCURE_ENTITY — AI procurement anchor/identity table.
;; Composite PK: (ENTITY_ID, TENANT_ID). No soft-delete; entities are canonical.

;;; ─── Request / Response / View Models ───────────────────────────────────────

(defclass AIEntityRequestModel (RequestModel)
  ((entityid
    :initarg :entityid
    :accessor entityid)
   (entitytype
    :initarg :entitytype
    :accessor entitytype)
   (company
    :initarg :company
    :accessor company)))

(defclass AIEntitySearchRequestModel (AIEntityRequestModel)
  ((entitytype-filter
    :initarg :entitytype-filter
    :accessor entitytype-filter
    :initform nil)))

(defclass AIEntityResponseModel (ResponseModel)
  ((entityid   :initarg :entityid   :accessor entityid)
   (entitytype :initarg :entitytype :accessor entitytype)
   (created    :initarg :created    :accessor created)
   (company    :initarg :company    :accessor company)))

(defclass AIEntityViewModel (ViewModel)
  ((entityid   :initarg :entityid   :accessor entityid)
   (entitytype :initarg :entitytype :accessor entitytype)
   (created    :initarg :created    :accessor created)
   (company    :initarg :company    :accessor company)))

;;; ─── Domain / Business Object ────────────────────────────────────────────────

(defclass AIEntity (BusinessObject)
  ((entityid
    :initarg :entityid
    :accessor entityid)
   (entitytype
    :initarg :entitytype
    :accessor entitytype)
   (created
    :initarg :created
    :accessor created)
   (company
    :initarg :company
    :accessor company)))

;;; ─── CLSQL View Class (DB Mapping) ──────────────────────────────────────────
;; NOTE: Composite PK (entity-id, tenant-id). CLSQL marks only one :db-kind :key;
;; the WHERE clause in fetch queries must always include both columns.

(clsql:def-view-class dod-procure-entity ()
  ((entity-id
    :db-kind :key
    :db-constraints :not-null
    :type (string 100)
    :initarg :entity-id
    :accessor entity-id)
   (entity-type
    :type (string 50)
    :initarg :entity-type
    :accessor entity-type)
   (tenant-id
    :type integer
    :initarg :tenant-id
    :accessor tenant-id)
   (created
    :type (string 30)
    :initarg :created
    :accessor created)
   (deleted-state
    :type (string 1)
    :initarg :deleted-state
    :accessor deleted-state)
   (COMPANY
    :accessor get-company
    :db-kind :join
    :db-info (:join-class dod-company
              :home-key tenant-id
              :foreign-key row-id
              :set nil)))
  (:base-table dod_procure_entity))

;;; ─── Adapter / Service / Presenter / View Classes ───────────────────────────

(defclass AIEntityAdapter   (AdapterService)  ())
(defclass AIEntityDBService (DBAdapterService) ())
(defclass AIEntityPresenter (PresenterService) ())
(defclass AIEntityService   (BusinessService)  ())
(defclass AIEntityHTMLView  (HTMLView)         ())
(defclass AIEntityJSONView  (JSONView)         ())
