;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— AI Entity 身份管理 —— DOD_PROCURE_ENTITY 业务逻辑层
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/nst-bl-aientity.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：管理 AI 采购实体（DOD_PROCURE_ENTITY）的规范身份表，提供复合主键
;;;;       （entity-id + tenant-id）下的多租户数据边界隔离。支持按 ID 查询、
;;;;       按类型筛选、全量读取，以及完整的 CRUD 操作（创建、读取、更新、删除）。
;;;;       所有查询均通过 Belnap 四值逻辑边界宏封装，确保 DB 操作的失败/异常
;;;;       被统一捕获为 bo-knowledge 实例。ENTITY_ID 必须映射为规范字符串 ID
;;;;       （如 VEND-001、CUST-001），TENANT_ID 不得外泄。
;;;;
;;;; 主要导出：
;;;;   select-aientity-by-id      — 按复合 PK 查询单条实体
;;;;   select-all-aientities      — 查询某租户下全部实体
;;;;   select-aientities-by-type  — 按类型筛选实体
;;;;   createAIEntityobject       — 构造 AIEntity 领域对象
;;;;   updateAIEntityobject       — 更新现有实体类型
;;;;
;;;; 关联：
;;;;   上游使用方：AI Agent 助手、vendor 后台实体管理
;;;;   下游依赖：CLSQL 数据库层、nst-mult-logic.lisp（Belnap 边界宏）
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;;; ─── Query Functions ─────────────────────────────────────────────────────────

(defun select-aientity-by-id (entity-id tenant-id)
  "Fetch a single entity by composite PK (entity-id, tenant-id)."
  (car (clsql:select 'dod-procure-entity
                     :where [and [= [:entity-id] entity-id]
                                 [= [:tenant-id] tenant-id]]
                     :caching *dod-database-caching* :flatp t)))

(defun select-all-aientities (tenant-id)
  "Fetch all entities for a tenant."
  (clsql:select 'dod-procure-entity
                :where [= [:tenant-id] tenant-id]
                :caching *dod-database-caching* :flatp t))

(defun select-aientities-by-type (entity-type tenant-id)
  "Fetch entities filtered by type for a tenant."
  (clsql:select 'dod-procure-entity
                :where [and [= [:entity-type] entity-type]
                            [= [:tenant-id] tenant-id]]
                :caching *dod-database-caching* :flatp t))

;;; ─── Copy Functions ──────────────────────────────────────────────────────────

(defun copyAIEntity-domaintodb (source destination)
  "Sync domain object → DB object."
  (let ((company (slot-value source 'company)))
    (with-slots (entity-id entity-type tenant-id) destination
      (setf entity-id   (slot-value source 'entityid))
      (setf entity-type (slot-value source 'entitytype))
      (setf tenant-id   (slot-value company 'row-id))
      destination)))

(defun copyAIEntity-dbtodomain (source destination)
  "Sync DB object → domain object."
  (with-slots (entityid entitytype created) destination
    (setf entityid   (slot-value source 'entity-id))
    (setf entitytype (slot-value source 'entity-type))
    (setf created    (slot-value source 'created))
    destination))

(defun createAIEntityobject (entity-id entity-type company)
  "Construct a new AIEntity domain object."
  (make-instance 'AIEntity
                 :entityid   entity-id
                 :entitytype entity-type
                 :company    company))

;;; ─── DBAdapterService Methods ────────────────────────────────────────────────

(defmethod init ((dbas AIEntityDBService) (bo AIEntity))
  :description "Init DB object from domain object."
  (let ((dbobj (make-instance 'dod-procure-entity)))
    (setf (dbobject dbas) dbobj)
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))

(defmethod Copy-BusinessObject-To-DBObject ((dbas AIEntityDBService))
  :description "Sync domain → DB."
  (let ((dbobj    (slot-value dbas 'dbobject))
        (domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject)
          (copyAIEntity-domaintodb domainobj dbobj))))


(defmethod Copy-DbObject-To-BusinessObject ((dbas AIEntityDBService))
  :description "Syncs the dbobject and domain object"
  (let ((dbobj (slot-value dbas 'dbobject))
        (domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value domainobj 'company) (company dbas))
    (setf (slot-value dbas 'businessobject) (copyAIEntity-dbtodomain dbobj domainobj))))

;;; ─── BusinessService CRUD Methods ────────────────────────────────────────────

(defmethod doCreate ((service AIEntityService) (rm AIEntityRequestModel))
  :description "Create and persist a new AIEntity."
  (let* ((dbas    (make-instance 'AIEntityDBService))
         (entity  (createAIEntityobject (entityid rm) (entitytype rm) (company rm))))
    (init dbas entity)
    (copy-businessobject-to-dbobject dbas)
    (let ((bk (with-db-create (dbas :source "AI Entity Create"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf entity (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      entity)))


(defmethod doRead ((service AIEntityService) (rm AIEntityRequestModel))
  :description "Read a single AIEntity by composite PK."
  (let* ((comp      (company rm))
         (tenant-id (slot-value comp 'row-id))
         (knowledge (with-db-call (select-aientity-by-id (entityid rm) tenant-id)))
         (domain    (make-instance 'AIEntity :company comp)))
    (setf (bo-knowledge service) knowledge)
    (when (eq (bo-knowledge-truth knowledge) :T)
      (copyAIEntity-dbtodomain (bo-knowledge-payload knowledge) domain))
    domain))

(defmethod doReadAll ((service AIEntityService) (rm AIEntityRequestModel))
  :description "Read all AIEntity rows for the tenant."
  (let* ((comp      (company rm))
         (tenant-id (slot-value comp 'row-id))
         (rows      (select-all-aientities tenant-id)))
    (mapcar (lambda (row)
              (let ((d (make-instance 'AIEntity :company comp)))
                (copyAIEntity-dbtodomain row d))) rows)))

(defmethod doReadAll ((service AIEntityService) (rm AIEntitySearchRequestModel))
  :description "Read AIEntities filtered by type."
  (let* ((comp      (company rm))
         (tenant-id (slot-value comp 'row-id))
         (rows      (select-aientities-by-type (entitytype-filter rm) tenant-id)))
    (mapcar (lambda (row)
              (let ((d (make-instance 'AIEntity :company comp)))
                (copyAIEntity-dbtodomain row d))) rows)))

(defmethod doUpdate ((service AIEntityService) (rm AIEntityRequestModel))
  :description "Update entity-type for an existing AIEntity."
  (let* ((comp      (company rm))
         (tenant-id (slot-value comp 'row-id))
         (dbobj     (select-aientity-by-id (entityid rm) tenant-id))
         (dbas      (make-instance 'AIEntityDBService))
         (domain    (make-instance 'AIEntity :company comp)))
    (when dbobj
      (setf (slot-value dbobj 'entity-type) (entitytype rm))
      (setf (slot-value dbas 'dbobject) dbobj)
      (setf (slot-value dbas 'businessobject) domain)
      (setcompany dbas comp)
      (db-save dbas)
      (copyAIEntity-dbtodomain dbobj domain))
    domain))

(defmethod doDelete ((service AIEntityService) (rm AIEntityRequestModel))
  :description "Hard delete — AIEntity is a canonical anchor. Guard with role check."
  ;; LEGAL NOTE: Deleting an ENTITY_ID orphans all ENTITY_FACT rows.
  ;; Caller MUST cascade or archive ENTITY_FACT before calling this.
  (let* ((comp      (company rm))
         (tenant-id (slot-value comp 'row-id))
         (dbobj     (select-aientity-by-id (entityid rm) tenant-id))
         (dbas      (make-instance 'AIEntityDBService)))
    (when dbobj
      (setf (slot-value dbas 'dbobject) dbobj)
      (setcompany dbas comp)
      (db-delete dbas))))

;;; ─── Adapter Methods ─────────────────────────────────────────────────────────

(defmethod ProcessCreateRequest ((adapter AIEntityAdapter) (rm AIEntityRequestModel))
  (setf (slot-value adapter 'businessservice) (find-class 'AIEntityService))
  (call-next-method))

(defmethod ProcessReadRequest ((adapter AIEntityAdapter) (rm AIEntityRequestModel))
  (setf (slot-value adapter 'businessservice) (find-class 'AIEntityService))
  (call-next-method))

(defmethod ProcessReadAllRequest ((adapter AIEntityAdapter) (rm AIEntityRequestModel))
  (setf (slot-value adapter 'businessservice) (find-class 'AIEntityService))
  (call-next-method))

(defmethod ProcessReadAllRequest ((adapter AIEntityAdapter) (rm AIEntitySearchRequestModel))
  (setf (slot-value adapter 'businessservice) (find-class 'AIEntityService))
  (call-next-method))

(defmethod ProcessUpdateRequest ((adapter AIEntityAdapter) (rm AIEntityRequestModel))
  (setf (slot-value adapter 'businessservice) (find-class 'AIEntityService))
  (call-next-method))

(defmethod ProcessDeleteRequest ((adapter AIEntityAdapter) (rm AIEntityRequestModel))
  (setf (slot-value adapter 'businessservice) (find-class 'AIEntityService))
  (call-next-method))

;;; ─── Response / ViewModel ────────────────────────────────────────────────────

(defmethod ProcessResponse ((adapter AIEntityAdapter) (bo AIEntity))
  (let ((rm (make-instance 'AIEntityResponseModel)))
    (createresponsemodel adapter bo rm)))

(defmethod CreateResponseModel ((adapter AIEntityAdapter)
                                (source AIEntity)
                                (dest AIEntityResponseModel))
  (with-slots (entityid entitytype created company) dest
    (setf entityid   (slot-value source 'entityid))
    (setf entitytype (slot-value source 'entitytype))
    (setf created    (slot-value source 'created))
    (setf company    (slot-value source 'company))
    dest))

(defmethod ProcessResponseList ((adapter AIEntityAdapter) entity-list)
  (mapcar (lambda (bo)
            (let ((rm (make-instance 'AIEntityResponseModel)))
              (createresponsemodel adapter bo rm))) entity-list))

(defmethod CreateViewModel ((presenter AIEntityPresenter)
                            (rm AIEntityResponseModel))
  (let ((vm (make-instance 'AIEntityViewModel)))
    (with-slots (entityid entitytype created company) rm
      (setf (slot-value vm 'entityid)   entityid)
      (setf (slot-value vm 'entitytype) entitytype)
      (setf (slot-value vm 'created)    created)
      (setf (slot-value vm 'company)    company))
    vm))

(defmethod CreateAllViewModel ((presenter AIEntityPresenter) rm-list)
  (mapcar (lambda (rm) (createviewmodel presenter rm)) rm-list))
