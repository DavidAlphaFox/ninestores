;;; nst-dal-aientfact.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— AI Entity Fact DAL —— EAV 版本化事实存储
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/core/nst-dal-aientfact.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 DOD_PROCURE_ENTITY_FACT 表的 CLSQL 视图类及配套模型类，
;;;;       实现实体-属性-值（EAV）版本化事实存储的数据访问层。
;;;;       每条事实写入后不可变，"更新" = 使旧版本过期 + 插入新版本。
;;;;       VALID_TO IS NULL 表示当前生效版本；SOURCE_TYPE 使用受控词表；
;;;;       FACT_KEY 遵循 {org}.{source}.{entity-type}.{category}.{attribute} 格式；
;;;;       CONFIDENCE 范围 0.4（弱）到 1.0（确定）。
;;;;
;;;; 主要导出：
;;;;   dod-procure-entity-fact     — CLSQL 视图类，映射 DOD_PROCURE_ENTITY_FACT 表
;;;;   *aientfact-source-types*    — 受控 SOURCE_TYPE 词表常量
;;;;   *aientfact-fact-types*     — 受控 FACT_TYPE 词表常量
;;;;   AIEntityFactRequestModel   — 事实写入/更新请求模型
;;;;   AIEntityFactSearchRequestModel — 事实查询请求模型（支持前缀搜索、历史版本）
;;;;   AIEntityFactResponseModel  — 事实查询响应模型
;;;;   AIEntityFactViewModel      — 事实展示视图模型
;;;;   AIEntityFact               — 领域业务对象
;;;;   AIEntityFactAdapter/DBService/Presenter/Service/HTMLView/JSONView — 服务层声明
;;;;
;;;; 关联：
;;;;   上游使用方：BL 层 AIEntityFact 相关服务（如 nst-bl-aientfact.lisp）
;;;;   下游依赖：CLSQL 数据库连接、nst-mult-logic.lisp 的边界宏、
;;;;             nst-bl-beltrusys.lisp 的 bo-knowledge 包装
;;;; ============================================================================
(in-package :nstores)

;;; ─── Constants: governed vocabularies ───────────────────────────────────────
;; Changing these affects downstream AI agents. Treat as a schema migration.

(defparameter *aientfact-source-types*
  '("HUMAN_ENTERED" "AI_EXTRACTED" "AI_INFERRED" "API_SYNC" "OBSERVATION")
  "Allowed SOURCE_TYPE values for DOD_PROCURE_ENTITY_FACT.")

(defparameter *aientfact-fact-types*
  '("string" "number" "boolean" "json" "date")
  "Allowed FACT_TYPE values.")

;;; ─── Request / Response / View Models ───────────────────────────────────────

(defclass AIEntityFactRequestModel (RequestModel)
  ((entityid
    :initarg :entityid    :accessor entityid)
   (factkey
    :initarg :factkey     :accessor factkey)
   (factval
    :initarg :factval     :accessor factval)
   (facttype
    :initarg :facttype    :accessor facttype
    :initform "string")
   (sourcetype
    :initarg :sourcetype  :accessor sourcetype)
   (confidence
    :initarg :confidence  :accessor confidence
    :initform 1.0)
   (validfrom
    :initarg :validfrom   :accessor validfrom
    :initform nil)
   (validto
    :initarg :validto     :accessor validto
    :initform nil)
   (assertedby
    :initarg :assertedby  :accessor assertedby
    :initform nil)
   (company
    :initarg :company     :accessor company)))

(defclass AIEntityFactSearchRequestModel (AIEntityFactRequestModel)
  ;; Search by entity-id (all current facts) or by fact-key prefix
  ((factkey-prefix
    :initarg :factkey-prefix :accessor factkey-prefix
    :initform nil)
   (include-history
    :initarg :include-history :accessor include-history
    :initform nil
    :documentation "When T, returns all versions including expired rows.")))

(defclass AIEntityFactResponseModel (ResponseModel)
  ((rowid      :initarg :rowid      :accessor rowid)
   (entityid   :initarg :entityid   :accessor entityid)
   (factkey    :initarg :factkey    :accessor factkey)
   (factval    :initarg :factval    :accessor factval)
   (facttype   :initarg :facttype   :accessor facttype)
   (sourcetype :initarg :sourcetype :accessor sourcetype)
   (confidence :initarg :confidence :accessor confidence)
   (validfrom  :initarg :validfrom  :accessor validfrom)
   (validto    :initarg :validto    :accessor validto)
   (assertedby :initarg :assertedby :accessor assertedby)
   (created    :initarg :created    :accessor created)
   (company    :initarg :company    :accessor company)))

(defclass AIEntityFactViewModel (ViewModel)
  ((rowid      :initarg :rowid      :accessor rowid)
   (entityid   :initarg :entityid   :accessor entityid)
   (factkey    :initarg :factkey    :accessor factkey)
   (factval    :initarg :factval    :accessor factval)
   (facttype   :initarg :facttype   :accessor facttype)
   (sourcetype :initarg :sourcetype :accessor sourcetype)
   (confidence :initarg :confidence :accessor confidence)
   (validfrom  :initarg :validfrom  :accessor validfrom)
   (validto    :initarg :validto    :accessor validto)
   (assertedby :initarg :assertedby :accessor assertedby)
   (created    :initarg :created    :accessor created)
   (company    :initarg :company    :accessor company)))

;;; ─── Domain / Business Object ────────────────────────────────────────────────

(defclass AIEntityFact (BusinessObject)
  ((rowid
    :initarg :rowid      :accessor rowid)
   (entityid
    :initarg :entityid   :accessor entityid)
   (factkey
    :initarg :factkey    :accessor factkey)
   (factval
    :initarg :factval    :accessor factval)
   (facttype
    :initarg :facttype   :accessor facttype
    :initform "string")
   (sourcetype
    :initarg :sourcetype :accessor sourcetype)
   (confidence
    :initarg :confidence :accessor confidence
    :initform 1.0)
   (validfrom
    :initarg :validfrom  :accessor validfrom)
   (validto
    :initarg :validto    :accessor validto
    :initform nil)
   (assertedby
    :initarg :assertedby :accessor assertedby
    :initform nil)
   (created
    :initarg :created    :accessor created)
   (company
    :initarg :company    :accessor company)))

;;; ─── CLSQL View Class ────────────────────────────────────────────────────────
;; NOTE: VALID_TO is nullable — CLSQL must handle NIL → SQL NULL correctly.
;; ROW_ID is bigint auto_increment; never set manually.

(clsql:def-view-class dod-procure-entity-fact ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id
    :accessor row-id)
   (entity-id
    :type (string 100)
    :initarg :entity-id
    :accessor entity-id)
   (tenant-id
    :type integer
    :initarg :tenant-id
    :accessor tenant-id)
   (fact-key
    :type (string 200)
    :initarg :fact-key
    :accessor fact-key)
   (fact-val
    :type (string 65535)           ; maps text column
    :initarg :fact-val
    :accessor fact-val)
   (fact-type
    :type (string 20)
    :initarg :fact-type
    :accessor fact-type
    :initform "string")
   (source-type
    :type (string 30)
    :initarg :source-type
    :accessor source-type)
   (confidence
    :type float
    :initarg :confidence
    :accessor confidence
    :initform 1.0)
   (valid-from
    :type wall-time
    :initarg :valid-from
    :accessor valid-from)
   (valid-to
    :type wall-time
    :initarg :valid-to
    :accessor valid-to
    :initform nil)
   (asserted-by
    :type (string 100)
    :initarg :asserted-by
    :accessor asserted-by
    :initform nil)
   (created
    :type wall-time
    :initarg :created
    :accessor created)
   (COMPANY
    :accessor get-company
    :db-kind :join
    :db-info (:join-class dod-company
              :home-key tenant-id
              :foreign-key row-id
              :set nil)))
  (:base-table dod_procure_entity_fact))

;;; ─── Service / Adapter / Presenter / View class declarations ─────────────────

(defclass AIEntityFactAdapter   (AdapterService)   ())
(defclass AIEntityFactDBService (DBAdapterService)  ())
(defclass AIEntityFactPresenter (PresenterService)  ())
(defclass AIEntityFactService   (BusinessService)   ())
(defclass AIEntityFactHTMLView  (HTMLView)          ())
(defclass AIEntityFactJSONView  (JSONView)          ())
