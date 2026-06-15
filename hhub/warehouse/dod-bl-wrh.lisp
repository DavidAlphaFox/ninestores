;;; dod-bl-wrh.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：warehouse —— 仓库业务逻辑（含所有权 / GST / 多类型，41 字段）
;;;; 分层：BL（业务逻辑层）—— 新风格（DDD：BusinessService / Adapter / Presenter / DBService）
;;;; 文件：hhub/warehouse/dod-bl-wrh.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：warehouse 模块全套业务方法：
;;;;       - DBService：db-fetch / db-fetch-all
;;;;       - 查询：select-warehouse-by-{id,name,code,uuid,gstin}、
;;;;               select-matching-warehouses / -by-city / -by-state-code、
;;;;               select-primary-warehouse / select-all-warehouses /
;;;;               select-vendor-warehouses / select-warehouses-by-ownership /
;;;;               get-active-warehouses
;;;;       - ID 生成：generate-warehouse-uuid / generate-warehouse-short-code
;;;;       - CRUD 服务方法：doCreate / doRead / doReadAll / doUpdate / doDelete
;;;;         （配合 ProcessXxxRequest Adapter dispatch）
;;;;       - 拷贝：createWarehouseObject、copyWarehouse-domaintodb、copyWarehouse-dbtodomain
;;;;       - 响应/视图：ProcessResponse / ProcessResponseList / CreateResponseModel /
;;;;                   CreateViewModel / CreateAllViewModel / RenderJSON / RenderJSONAll
;;;;
;;;; 主要导出：
;;;;   select-warehouse-by-id / -by-name / -by-code / -by-uuid / -by-gstin
;;;;   select-matching-warehouses / select-warehouses-by-city / -by-state-code
;;;;   select-primary-warehouse / select-all-warehouses / select-vendor-warehouses
;;;;   select-warehouses-by-ownership / get-active-warehouses
;;;;   generate-warehouse-uuid / generate-warehouse-short-code
;;;;   createWarehouseObject / copyWarehouse-domaintodb / copyWarehouse-dbtodomain
;;;;
;;;; 关联：
;;;;   上游使用方：warehouse/dod-ui-wrh.lisp（控制器 / JSON API）。
;;;;   下游依赖：warehouse/dod-dal-wrh.lisp（实体 + 类）、core knowledge framework
;;;;             （with-db-create / with-db-update / with-db-delete / with-db-call-list /
;;;;              with-db-read-one / bo-knowledge / bo-knowledge-truth /
;;;;              bo-knowledge-payload）。
;;;;
;;;; 备注：本文件为项目"新风格"——所有 CRUD 走 BusinessService + DBService 协作，
;;;;       并把 with-db-* 宏返回的"知识对象"挂回 service 以供上游调用方读取真值/payload。
;;;; ============================================================================

;; nst-bl-warehouse.lisp
;; Business Logic Layer for Warehouse entity (UPDATED with ownership fields - 41 fields)
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;;; ===========================================================================
;;; DATABASE SERVICE METHODS
;;; ===========================================================================

(defmethod db-fetch ((dbas WarehouseDBService) row-id)
  :description "Fetch the DBObject based on row-id.
   中文：按 (tenant-id, row-id) 取一条已启用、未软删的 dod-warehouse，
   并把它挂到 dbas.dbobject。tenant-id 来自 dbas.company.row-id。"
  (let* ((company (slot-value dbas 'company))
         (tenant-id (slot-value company 'row-id))
         (dbobj (car (clsql:select 'dod-warehouse :where
                                   [and
                                   [= [:deleted-state] "N"]
                                   [= [:active-flag] "Y"]
                                   [= [:tenant-id] tenant-id]
                                   [= [:row-id] row-id]] 
                                   :caching *dod-database-caching* :flatp t))))
    (setf (slot-value dbas 'dbobject) dbobj)))

(defmethod db-fetch-all ((dbas WarehouseDBService) (rm WarehouseRequestModel))
  :description "Fetch records by COMPANY.
   中文：按 (tenant-id, owner-entity-id=vendor-id) 列出该 vendor 在该租户下的全部仓库
   （已启用、未软删）。注意：tenant-id 直接从 dbas 取，不是从 rm.company 取。"
  (let* ((tenant-id (slot-value dbas 'tenant-id))
         (vendor (slot-value rm 'vendor))
         (vendor-id (slot-value vendor 'row-id))
         (dbobjs (clsql:select 'dod-warehouse :where
                               [and
                               [= [:deleted-state] "N"]
                               [= [:active-flag] "Y"]
                               [= [:owner-entity-id] vendor-id]
                               [= [:tenant-id] tenant-id]] 
                               :caching *dod-database-caching* :flatp t)))
    dbobjs))

;;; ===========================================================================
;;; QUERY FUNCTIONS
;;; ===========================================================================

(defun select-warehouse-by-id (id tenant-id)
  "Select warehouse by row-id.
   中文：按 (tenant-id, row-id) 取单条未软删 dod-warehouse。返回实例 / nil。
   注意：未过滤 active-flag，被禁用仓库也能命中。"
  (car (clsql:select 'dod-warehouse :where 
                     [and 
		      [= [:tenant-id] tenant-id]
		      [= [:row-id] id]
                      [= [:deleted-state] "N"]]
                     :caching *dod-database-caching* :flatp t)))

(defun select-warehouse-by-name (wname tenant-id)
  "Select warehouse by name.
   中文：按 w-name 精确匹配，返回租户下未软删的第一条仓库。"
  (car (clsql:select 'dod-warehouse :where
                     [and 
                      [= [:w-name] wname]
                      [= [:tenant-id] tenant-id]
                      [= [:deleted-state] "N"]]
                     :caching *dod-database-caching* :flatp t)))

(defun select-warehouse-by-code (warehouse-code tenant-id)
  "Select warehouse by business code.
   中文：按业务码 warehouse-code（如 WH-XXXXXXXX）在租户内查仓库。未启用 CLSQL 缓存。"
  (car (clsql:select 'dod-warehouse 
                     :where [and
                             [= [:warehouse-code] warehouse-code]
                             [= [:tenant-id] tenant-id]
                             [= [:deleted-state] "N"]]
                     :flatp t)))

(defun select-warehouse-by-uuid (warehouse-uuid tenant-id)
  "Select warehouse by UUID.
   中文：按系统 UUID 在租户内查仓库。未启用 CLSQL 缓存。"
  (car (clsql:select 'dod-warehouse 
                     :where [and
                             [= [:warehouse-uuid] warehouse-uuid]
                             [= [:tenant-id] tenant-id]
                             [= [:deleted-state] "N"]]
                     :flatp t)))

(defun select-warehouse-by-gstin (gstin)
  "Select warehouse by GSTIN.
   中文：按 GSTIN 全局查仓库（未限定 tenant_id，跨租户取第一条）。"
  (car (clsql:select 'dod-warehouse :where
                     [and 
                      [= [:warehouse-gstin] gstin]
                      [= [:deleted-state] "N"]]
                     :caching *dod-database-caching* :flatp t)))

(defun select-matching-warehouses (wname-like tenant-id)
  "Select warehouses matching partial name.
   中文：按 w-name LIKE %xxx% 模糊查仓库，最多 200 条。供搜索框用。"
  (clsql:select 'dod-warehouse :where
                [and 
                 [like [:w-name] (format nil "%~a%" wname-like)]
                 [= [:tenant-id] tenant-id]
                 [= [:deleted-state] "N"]]
                :limit 200
                :caching *dod-database-caching* :flatp t))

(defun select-warehouses-by-city (city tenant-id)
  "Select warehouses by city.
   中文：按城市精确查询，返回最多 200 条仓库列表。"
  (clsql:select 'dod-warehouse :where
                [and 
                 [= [:w-city] city]
                 [= [:tenant-id] tenant-id]
                 [= [:deleted-state] "N"]]
                :limit 200
                :caching *dod-database-caching* :flatp t))

(defun select-warehouses-by-state-code (state-code tenant-id)
  "Select warehouses by state code.
   中文：按 GST 州代码（state-code，2 位字符串）查仓库列表。"
  (clsql:select 'dod-warehouse :where
                [and 
                 [= [:state-code] state-code]
                 [= [:tenant-id] tenant-id]
                 [= [:deleted-state] "N"]]
                :caching *dod-database-caching* :flatp t))

(defun select-primary-warehouse (tenant-id)
  "Select primary warehouse location.
   中文：查租户的主仓（is-primary-location=1，integer 1 而非 'Y'）。返回单条 / nil。"
  (car (clsql:select 'dod-warehouse :where
                     [and
                      [= [:tenant-id] tenant-id]
                      [= [:is-primary-location] 1]
                      [= [:deleted-state] "N"]]
                     :caching *dod-database-caching* :flatp t)))

(defun select-all-warehouses (tenant-id)
  "Select all warehouses for a tenant.
   中文：列出某租户全部未软删仓库（最多 200）。不限制 active-flag。"
  (clsql:select 'dod-warehouse :where
                [and
                 [= [:tenant-id] tenant-id]
                 [= [:deleted-state] "N"]]
                :limit 200
                :caching *dod-database-caching* :flatp t))

(defun select-vendor-warehouses (vendor-id tenant-id)
  "Select all warehouses owned by a vendor.
   中文：列出某 vendor（owner-entity-type='SELLER' 且 owner-entity-id=vendor-id）
   在某租户下的全部未软删仓库（最多 200）。"
  (clsql:select 'dod-warehouse :where
                [and
                 [= [:tenant-id] tenant-id]
                 [= [:owner-entity-id] vendor-id]
                 [= [:owner-entity-type] "SELLER"]
                 [= [:deleted-state] "N"]]
                :limit 200
                :caching *dod-database-caching* :flatp t))

(defun select-warehouses-by-ownership (ownership-type owner-entity-type owner-entity-id tenant-id)
  "Select warehouses by ownership criteria.
   中文：按 (ownership-type, owner-entity-type, owner-entity-id, tenant-id) 全字段精准筛选，
   适用于诸如 'BONDED + GOVERNMENT' 等组合查询。"
  (clsql:select 'dod-warehouse :where
                [and
                 [= [:ownership-type] ownership-type]
                 [= [:owner-entity-type] owner-entity-type]
                 [= [:owner-entity-id] owner-entity-id]
                 [= [:tenant-id] tenant-id]
                 [= [:deleted-state] "N"]]
                :caching *dod-database-caching* :flatp t))

(defun get-active-warehouses (tenant-id)
  "Get all active warehouses for a tenant.
   中文：列出租户下 active-flag='Y' 且未软删的全部仓库；不带 200 上限。"
  (clsql:select 'dod-warehouse :where
                [and
                 [= [:tenant-id] tenant-id]
                 [= [:active-flag] "Y"]
                 [= [:deleted-state] "N"]]
                :caching *dod-database-caching* :flatp t))

;;; ===========================================================================
;;; CODE GENERATION FUNCTIONS
;;; ===========================================================================

(defun generate-warehouse-uuid ()
  "Generate UUID for warehouse.
   中文：生成 v4 UUID 字符串作为 warehouse-uuid 主键。"
  (format nil "~A" (uuid:make-v4-uuid)))

(defun generate-warehouse-short-code ()
  "Generate short alphanumeric code: WH-XXXXXXXX.
   中文：截取 v4 UUID 前 8 位转大写，加 'WH-' 前缀。仅用作业务展示码。"
  (let* ((uuid (uuid:make-v4-uuid))
         (uuid-str (format nil "~A" uuid))
         (short-id (subseq uuid-str 0 8)))
    (format nil "WH-~A" (string-upcase short-id))))

;;; ===========================================================================
;;; CREATE Operations
;;; ===========================================================================

(defmethod ProcessCreateRequest ((adapter WarehouseAdapter) (requestmodel WarehouseRequestModel))
  :description "Adapter Service method to call the BusinessService Create method. Returns the created Warehouse object.
   中文：把 Adapter 的 BusinessService 设为 WarehouseService，再委托父类 dispatch 调 doCreate。"
  (setf (slot-value adapter 'businessservice) (find-class 'WarehouseService))
  (call-next-method))

(defmethod init ((dbas WarehouseDBService) (bo Warehouse))
  :description "Set the DB object and domain object.
   中文：初始化 WarehouseDBService —— 创建一个空的 dod-warehouse 挂到 dbas，
   再用 bo.company 做 setcompany 设定租户上下文。"
  (let* ((dbobj (make-instance 'dod-warehouse)))
    (setf (dbobject dbas) dbobj)
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))

(defmethod doCreate ((service WarehouseService) (requestmodel WarehouseRequestModel))
  :description "Create a new warehouse with ownership fields.
   中文：从 requestmodel 抽出全部字段，自动生成 uuid + warehouse-code，
   构造 Warehouse 业务对象，通过 with-db-create 落库；同时把返回的"知识对象"
   挂到 service.bo-knowledge 供上层读取真值/payload。返回：新建的业务对象。
   副作用：INSERT DOD_WAREHOUSE，写日志。"
  (let* ((warehousedbservice (make-instance 'WarehouseDBService))
         ;; Basic fields
         (wname (slot-value requestmodel 'wname))
         (waddr1 (slot-value requestmodel 'waddr1))
         (waddr2 (slot-value requestmodel 'waddr2))
         (wpin (slot-value requestmodel 'wpin))
         (wcity (slot-value requestmodel 'wcity))
         (wstate (slot-value requestmodel 'wstate))
         (wcountry (slot-value requestmodel 'wcountry))
         (wmanager (slot-value requestmodel 'wmanager))
         (wphone (slot-value requestmodel 'wphone))
         (waltphone (slot-value requestmodel 'waltphone))
         (wemail (slot-value requestmodel 'wemail))
         (activeflag (slot-value requestmodel 'activeflag))
         
         ;; Ownership fields
         (ownership-type (slot-value requestmodel 'ownership-type))
         (owner-entity-type (slot-value requestmodel 'owner-entity-type))
         (owner-entity-id (slot-value requestmodel 'owner-entity-id))
         (operator-entity-type (slot-value requestmodel 'operator-entity-type))
         (operator-entity-id (slot-value requestmodel 'operator-entity-id))
         (legal-entity-type (slot-value requestmodel 'legal-entity-type))
         
         ;; GST and Advanced Fields
         (warehouse-gstin (slot-value requestmodel 'warehouse-gstin))
         (gstin-status (slot-value requestmodel 'gstin-status))
         (legal-name (slot-value requestmodel 'legal-name))
         (is-primary-location (slot-value requestmodel 'is-primary-location))
         (state-code (slot-value requestmodel 'state-code))
         (registration-type (slot-value requestmodel 'registration-type))
         (warehouse-type (slot-value requestmodel 'warehouse-type))
         (warehouse-purpose (slot-value requestmodel 'warehouse-purpose))
         (default-transporter-id (slot-value requestmodel 'default-transporter-id))
         (default-transporter-name (slot-value requestmodel 'default-transporter-name))
         (eway-bill-enabled (slot-value requestmodel 'eway-bill-enabled))
         (latitude (slot-value requestmodel 'latitude))
         (longitude (slot-value requestmodel 'longitude))
         (valuation-method (slot-value requestmodel 'valuation-method))
         (hsn-wise-stock (slot-value requestmodel 'hsn-wise-stock))
         (pan-number (slot-value requestmodel 'pan-number))
         
         ;; Auto-generate identifiers
         (warehouse-uuid (generate-warehouse-uuid))
         (warehouse-code (generate-warehouse-short-code))
         (comp (company requestmodel))
         
         ;; Create domain object
         (warehouseobj (createWarehouseObject 
                        wname waddr1 waddr2 wpin wcity wstate wcountry 
                        wmanager wphone waltphone wemail activeflag
                        ownership-type owner-entity-type owner-entity-id
                        operator-entity-type operator-entity-id legal-entity-type
                        warehouse-gstin gstin-status legal-name 
                        is-primary-location state-code registration-type
                        warehouse-type warehouse-purpose 
                        default-transporter-id default-transporter-name
                        eway-bill-enabled latitude longitude 
                        valuation-method hsn-wise-stock pan-number 
                        warehouse-uuid warehouse-code comp)))
    
    ;; Initialize the DB Service
    (init warehousedbservice warehouseobj)
    (copy-businessobject-to-dbobject warehousedbservice)
    (format t "doCreate called for warehouse: ~A~%" wname)
    
    (let ((bk (with-db-create (warehousedbservice :source "Warehouse create"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf warehouseobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      warehouseobj)))

(defmethod doCreate :around ((service WarehouseService) (requestmodel WarehouseRequestModel))
  ":around 钩子，目前只是 call-next-method（占位，方便后续插入审计/锁等逻辑）。"
  (call-next-method))

(defun createWarehouseObject (wname waddr1 waddr2 wpin wcity wstate wcountry 
                               wmanager wphone waltphone wemail activeflag
                               ownership-type owner-entity-type owner-entity-id
                               operator-entity-type operator-entity-id legal-entity-type
                               warehouse-gstin gstin-status legal-name 
                               is-primary-location state-code registration-type
                               warehouse-type warehouse-purpose 
                               default-transporter-id default-transporter-name
                               eway-bill-enabled latitude longitude 
                               valuation-method hsn-wise-stock pan-number 
                               warehouse-uuid warehouse-code company)
  "Create a warehouse domain object with ownership fields.
   中文：纯构造函数——把所有 41 字段塞进新建的 Warehouse 业务对象。
   不做持久化。"
  (make-instance 'Warehouse 
                 :wname wname
                 :waddr1 waddr1
                 :waddr2 waddr2
                 :wpin wpin
                 :wcity wcity
                 :wstate wstate
                 :wcountry wcountry
                 :wmanager wmanager
                 :wphone wphone
                 :waltphone waltphone
                 :wemail wemail
                 :activeflag activeflag
                 ;; Ownership fields
                 :ownership-type ownership-type
                 :owner-entity-type owner-entity-type
                 :owner-entity-id owner-entity-id
                 :operator-entity-type operator-entity-type
                 :operator-entity-id operator-entity-id
                 :legal-entity-type legal-entity-type
                 ;; GST fields
                 :warehouse-gstin warehouse-gstin
                 :gstin-status gstin-status
                 :legal-name legal-name
                 :is-primary-location is-primary-location
                 :state-code state-code
                 :registration-type registration-type
                 :warehouse-type warehouse-type
                 :warehouse-purpose warehouse-purpose
                 :default-transporter-id default-transporter-id
                 :default-transporter-name default-transporter-name
                 :eway-bill-enabled eway-bill-enabled
                 :latitude latitude
                 :longitude longitude
                 :valuation-method valuation-method
                 :hsn-wise-stock hsn-wise-stock
                 :pan-number pan-number
                 :warehouse-uuid warehouse-uuid
                 :warehouse-code warehouse-code
                 :company company))

(defmethod Copy-BusinessObject-To-DBObject ((dbas WarehouseDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：把 Warehouse 业务对象字段同步进 dod-warehouse 数据库对象。"
  (let ((dbobj (slot-value dbas 'dbobject))
        (domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyWarehouse-domaintodb domainobj dbobj))))

(defun copyWarehouse-domaintodb (source destination)
  "Copy warehouse domain object to database object with ownership fields.
   中文：业务对象字段（wname/waddr1/...）→ DB 字段（w-name/w-addr1/...，加连字符）。
   同时设置 deleted-state='N' 与 tenant-id（来自 source.company）。返回 destination。"
  (let ((company (slot-value source 'company)))
    (with-slots (w-name w-addr1 w-addr2 w-pin w-city w-state w-country 
                 w-manager w-phone w-alt-phone w-email active-flag deleted-state
                 ownership-type owner-entity-type owner-entity-id
                 operator-entity-type operator-entity-id legal-entity-type
                 warehouse-gstin gstin-status legal-name is-primary-location
                 state-code registration-type warehouse-type warehouse-purpose
                 default-transporter-id default-transporter-name eway-bill-enabled
                 latitude longitude valuation-method hsn-wise-stock pan-number 
                 warehouse-uuid warehouse-code tenant-id) destination
      ;; Basic fields
      (setf w-name (slot-value source 'wname))
      (setf w-addr1 (slot-value source 'waddr1))
      (setf w-addr2 (slot-value source 'waddr2))
      (setf w-pin (slot-value source 'wpin))
      (setf w-city (slot-value source 'wcity))
      (setf w-state (slot-value source 'wstate))
      (setf w-country (slot-value source 'wcountry))
      (setf w-manager (slot-value source 'wmanager))
      (setf w-phone (slot-value source 'wphone))
      (setf w-alt-phone (slot-value source 'waltphone))
      (setf w-email (slot-value source 'wemail))
      (setf active-flag (slot-value source 'activeflag))
      (setf deleted-state "N")
      
      ;; Ownership fields
      (setf ownership-type (slot-value source 'ownership-type))
      (setf owner-entity-type (slot-value source 'owner-entity-type))
      (setf owner-entity-id (slot-value source 'owner-entity-id))
      (setf operator-entity-type (slot-value source 'operator-entity-type))
      (setf operator-entity-id (slot-value source 'operator-entity-id))
      (setf legal-entity-type (slot-value source 'legal-entity-type))
      
      ;; GST and Advanced Fields
      (setf warehouse-gstin (slot-value source 'warehouse-gstin))
      (setf gstin-status (slot-value source 'gstin-status))
      (setf legal-name (slot-value source 'legal-name))
      (setf is-primary-location (slot-value source 'is-primary-location))
      (setf state-code (slot-value source 'state-code))
      (setf registration-type (slot-value source 'registration-type))
      (setf warehouse-type (slot-value source 'warehouse-type))
      (setf warehouse-purpose (slot-value source 'warehouse-purpose))
      (setf default-transporter-id (slot-value source 'default-transporter-id))
      (setf default-transporter-name (slot-value source 'default-transporter-name))
      (setf eway-bill-enabled (slot-value source 'eway-bill-enabled))
      (setf latitude (slot-value source 'latitude))
      (setf longitude (slot-value source 'longitude))
      (setf valuation-method (slot-value source 'valuation-method))
      (setf hsn-wise-stock (slot-value source 'hsn-wise-stock))
      (setf pan-number (slot-value source 'pan-number))
      (setf warehouse-uuid (slot-value source 'warehouse-uuid))
      (setf warehouse-code (slot-value source 'warehouse-code))
      (setf tenant-id (slot-value company 'row-id))
      destination)))

;;; ===========================================================================
;;; READ Operations
;;; ===========================================================================

(defmethod ProcessReadRequest ((adapter WarehouseAdapter) (requestmodel WarehouseRequestModel))
  :description "Adapter service method to read a single Warehouse.
   中文：把 BusinessService 设为 WarehouseService，再 call-next-method 调 doRead。"
  (setf (slot-value adapter 'businessservice) (find-class 'WarehouseService))
  (call-next-method))

(defmethod doRead ((service WarehouseService) (requestmodel WarehouseRequestModel))
  :description "Read a warehouse by row-id.
   中文：用 with-db-read-one 宏读单条 warehouse，并把知识对象挂到 service。
   当 truth=:T 时返回 payload（拷过的 Warehouse 业务对象），否则返回 nil。"
  (let* ((warehousedbservice (make-instance 'WarehouseDBService))
         (comp (company requestmodel))
         (row-id (row-id requestmodel))
         (warehouseobj (make-instance 'Warehouse)))
    (setf (slot-value warehouseobj 'company) comp)
    (init warehousedbservice warehouseobj)
    (let ((dbWarehouse-knowledge (with-db-read-one (warehousedbservice row-id))))
      (setf (bo-knowledge service) dbWarehouse-knowledge)
      (when (eq (bo-knowledge-truth dbWarehouse-knowledge) :T)
        (setf warehouseobj (bo-knowledge-payload dbWarehouse-knowledge))
	warehouseobj))))

(defmethod Copy-DbObject-To-BusinessObject ((dbas WarehouseDBService))
  :description "Syncs the dbobject and domain object.
   中文：把 DB 对象字段同步回 Warehouse 业务对象，并把 dbas.company 挂上去。"
  (let ((dbobj (slot-value dbas 'dbobject))
        (domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value domainobj 'company) (company dbas))
    (setf (slot-value dbas 'businessobject) (copyWarehouse-dbtodomain dbobj domainobj))))

(defun copyWarehouse-dbtodomain (source destination)
  "Copy database object to warehouse domain object with ownership fields.
   中文：DB 字段 w-name → 业务字段 wname 等的反向拷贝。返回 destination。"
  (with-slots (row-id wname waddr1 waddr2 wpin wcity wstate wcountry 
               wmanager wphone waltphone wemail activeflag
               ownership-type owner-entity-type owner-entity-id
               operator-entity-type operator-entity-id legal-entity-type
               warehouse-gstin gstin-status legal-name is-primary-location
               state-code registration-type warehouse-type warehouse-purpose
               default-transporter-id default-transporter-name eway-bill-enabled
               latitude longitude valuation-method hsn-wise-stock pan-number 
               warehouse-uuid warehouse-code) destination
    ;; Basic fields
    (setf row-id (slot-value source 'row-id))
    (setf wname (slot-value source 'w-name))
    (setf waddr1 (slot-value source 'w-addr1))
    (setf waddr2 (slot-value source 'w-addr2))
    (setf wpin (slot-value source 'w-pin))
    (setf wcity (slot-value source 'w-city))
    (setf wstate (slot-value source 'w-state))
    (setf wcountry (slot-value source 'w-country))
    (setf wmanager (slot-value source 'w-manager))
    (setf wphone (slot-value source 'w-phone))
    (setf waltphone (slot-value source 'w-alt-phone))
    (setf wemail (slot-value source 'w-email))
    (setf activeflag (slot-value source 'active-flag))
    
    ;; Ownership fields
    (setf ownership-type (slot-value source 'ownership-type))
    (setf owner-entity-type (slot-value source 'owner-entity-type))
    (setf owner-entity-id (slot-value source 'owner-entity-id))
    (setf operator-entity-type (slot-value source 'operator-entity-type))
    (setf operator-entity-id (slot-value source 'operator-entity-id))
    (setf legal-entity-type (slot-value source 'legal-entity-type))
    
    ;; GST and Advanced Fields
    (setf warehouse-gstin (slot-value source 'warehouse-gstin))
    (setf gstin-status (slot-value source 'gstin-status))
    (setf legal-name (slot-value source 'legal-name))
    (setf is-primary-location (slot-value source 'is-primary-location))
    (setf state-code (slot-value source 'state-code))
    (setf registration-type (slot-value source 'registration-type))
    (setf warehouse-type (slot-value source 'warehouse-type))
    (setf warehouse-purpose (slot-value source 'warehouse-purpose))
    (setf default-transporter-id (slot-value source 'default-transporter-id))
    (setf default-transporter-name (slot-value source 'default-transporter-name))
    (setf eway-bill-enabled (slot-value source 'eway-bill-enabled))
    (setf latitude (slot-value source 'latitude))
    (setf longitude (slot-value source 'longitude))
    (setf valuation-method (slot-value source 'valuation-method))
    (setf hsn-wise-stock (slot-value source 'hsn-wise-stock))
    (setf pan-number (slot-value source 'pan-number))
    (setf warehouse-uuid (slot-value source 'warehouse-uuid))
    (setf warehouse-code (slot-value source 'warehouse-code))
    destination))

;;; ===========================================================================
;;; READ ALL Operations
;;; ===========================================================================

(defmethod ProcessReadAllRequest ((adapter WarehouseAdapter) (requestmodel WarehouseRequestModel))
  :description "Adapter service method to read all Warehouses.
   中文：列出 vendor 拥有的所有仓库；BusinessService 设为 WarehouseService 后调 doReadAll。"
  (setf (slot-value adapter 'businessservice) (find-class 'WarehouseService))
  (call-next-method))

(defmethod doReadAll ((service WarehouseService) (requestmodel WarehouseRequestModel))
  :description "Read all warehouses for a vendor/owner.
   中文：with-db-call-list 包裹 select-vendor-warehouses 的结果，
   再把每条 dod-warehouse 拷为 Warehouse 业务对象返回列表。
   备注：当 truth=:T 才返回，否则隐式返回 nil。"
  (let* ((comp (company requestmodel))
         (tenant-id (slot-value comp 'row-id))
         (vendor (vendor requestmodel))
         (vendor-id (slot-value vendor 'row-id))
         (dbWarehouse-knowledge (with-db-call-list (select-vendor-warehouses vendor-id tenant-id))))
    (setf (bo-knowledge service) dbWarehouse-knowledge)
    (when (eq (bo-knowledge-truth dbWarehouse-knowledge) :T)
      (let ((readalllst (bo-knowledge-payload dbWarehouse-knowledge)))
        (mapcar (lambda (dbobject)
                  (let ((domainobj (make-instance 'Warehouse)))
                    (setf (slot-value domainobj 'company) comp)
                    (copyWarehouse-dbtodomain dbobject domainobj))) readalllst)))))

(defmethod ProcessReadAllRequest ((adapter WarehouseAdapter) (requestmodel WarehouseSearchRequestModel))
  :description "Adapter service method to search Warehouses.
   中文：搜索专用版本，dispatch 到 doReadAll/WarehouseSearchRequestModel 实现。"
  (setf (slot-value adapter 'businessservice) (find-class 'WarehouseService))
  (call-next-method))

(defmethod doReadAll ((service WarehouseService) (requestmodel WarehouseSearchRequestModel))
  :description "Search warehouses by name.
   中文：从 requestmodel 取 wname 作为 LIKE 模糊条件，调 select-matching-warehouses
   后拷成业务对象列表。注意：本方法不像无搜索版本那样使用 with-db-call-list 包装。"
  (let* ((comp (company requestmodel))
         (wname-like (slot-value requestmodel 'wname))
         (tenant-id (slot-value comp 'row-id))
         (readalllst (select-matching-warehouses wname-like tenant-id)))
    (mapcar (lambda (dbobject)
              (let ((domainobj (make-instance 'Warehouse)))
                (setf (slot-value domainobj 'company) comp)
                (copyWarehouse-dbtodomain dbobject domainobj))) readalllst)))

;;; ===========================================================================
;;; UPDATE Operations
;;; ===========================================================================

(defmethod ProcessUpdateRequest ((adapter WarehouseAdapter) (requestmodel WarehouseRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：把 BusinessService 设为 WarehouseService 并 dispatch 到 doUpdate。"
  (setf (slot-value adapter 'businessservice) (find-class 'WarehouseService))
  (call-next-method))

(defmethod doUpdate ((service WarehouseService) (requestmodel WarehouseRequestModel))
  :description "Update an existing warehouse with ownership fields.
   中文：先 select-warehouse-by-id 取出旧记录，逐字段覆盖（含 GST/物流/经纬度/库存），
   updated 字段写入 mysql-now()，再用 with-db-update 落库（同时挂回 service.bo-knowledge）。
   返回：更新后的 Warehouse 业务对象。
   副作用：UPDATE DOD_WAREHOUSE。"
  (let* ((warehousedbservice (make-instance 'WarehouseDBService))
         ;; Basic fields
	 (row-id (slot-value requestmodel 'row-id))
	 (wname (slot-value requestmodel 'wname))
         (waddr1 (slot-value requestmodel 'waddr1))
         (waddr2 (slot-value requestmodel 'waddr2))
         (wpin (slot-value requestmodel 'wpin))
         (wcity (slot-value requestmodel 'wcity))
         (wstate (slot-value requestmodel 'wstate))
         (wcountry (slot-value requestmodel 'wcountry))
         (wmanager (slot-value requestmodel 'wmanager))
         (wphone (slot-value requestmodel 'wphone))
         (waltphone (slot-value requestmodel 'waltphone))
         (wemail (slot-value requestmodel 'wemail))
         (activeflag (slot-value requestmodel 'activeflag))
         
         ;; Ownership fields
         (ownership-type (slot-value requestmodel 'ownership-type))
         (owner-entity-type (slot-value requestmodel 'owner-entity-type))
         (owner-entity-id (slot-value requestmodel 'owner-entity-id))
         (operator-entity-type (slot-value requestmodel 'operator-entity-type))
         (operator-entity-id (slot-value requestmodel 'operator-entity-id))
         (legal-entity-type (slot-value requestmodel 'legal-entity-type))
         
         ;; GST and Advanced Fields
         (warehouse-gstin (slot-value requestmodel 'warehouse-gstin))
         (gstin-status (slot-value requestmodel 'gstin-status))
         (legal-name (slot-value requestmodel 'legal-name))
         (is-primary-location (slot-value requestmodel 'is-primary-location))
         (state-code (slot-value requestmodel 'state-code))
         (registration-type (slot-value requestmodel 'registration-type))
         (warehouse-type (slot-value requestmodel 'warehouse-type))
         (warehouse-purpose (slot-value requestmodel 'warehouse-purpose))
         (default-transporter-id (slot-value requestmodel 'default-transporter-id))
         (default-transporter-name (slot-value requestmodel 'default-transporter-name))
         (eway-bill-enabled (slot-value requestmodel 'eway-bill-enabled))
         (latitude (slot-value requestmodel 'latitude))
         (longitude (slot-value requestmodel 'longitude))
         (valuation-method (slot-value requestmodel 'valuation-method))
         (hsn-wise-stock (slot-value requestmodel 'hsn-wise-stock))
         (pan-number (slot-value requestmodel 'pan-number))
         (warehouse-uuid (slot-value requestmodel 'warehouse-uuid))
         (warehouse-code (slot-value requestmodel 'warehouse-code))
         (comp (company requestmodel))
         (tenant-id (slot-value comp 'row-id))
         (warehousedbobj (select-warehouse-by-id row-id tenant-id))
         (domainobj (make-instance 'Warehouse)))

    ;; Update all fields
    (when warehousedbobj
      ;; Basic fields
      (setf (slot-value warehousedbobj 'w-name) wname)
      (setf (slot-value warehousedbobj 'w-addr1) waddr1)
      (setf (slot-value warehousedbobj 'w-addr2) waddr2)
      (setf (slot-value warehousedbobj 'w-pin) wpin)
      (setf (slot-value warehousedbobj 'w-city) wcity)
      (setf (slot-value warehousedbobj 'w-state) wstate)
      (setf (slot-value warehousedbobj 'w-country) wcountry)
      (setf (slot-value warehousedbobj 'w-manager) wmanager)
      (setf (slot-value warehousedbobj 'w-phone) wphone)
      (setf (slot-value warehousedbobj 'w-alt-phone) waltphone)
      (setf (slot-value warehousedbobj 'w-email) wemail)
      (setf (slot-value warehousedbobj 'active-flag) activeflag)
      
      ;; Ownership fields
      (setf (slot-value warehousedbobj 'ownership-type) ownership-type)
      (setf (slot-value warehousedbobj 'owner-entity-type) owner-entity-type)
      (setf (slot-value warehousedbobj 'owner-entity-id) owner-entity-id)
      (setf (slot-value warehousedbobj 'operator-entity-type) operator-entity-type)
      (setf (slot-value warehousedbobj 'operator-entity-id) operator-entity-id)
      (setf (slot-value warehousedbobj 'legal-entity-type) legal-entity-type)
      
      ;; GST and Advanced Fields
      (setf (slot-value warehousedbobj 'warehouse-gstin) warehouse-gstin)
      (setf (slot-value warehousedbobj 'gstin-status) gstin-status)
      (setf (slot-value warehousedbobj 'legal-name) legal-name)
      (setf (slot-value warehousedbobj 'is-primary-location) is-primary-location)
      (setf (slot-value warehousedbobj 'state-code) state-code)
      (setf (slot-value warehousedbobj 'registration-type) registration-type)
      (setf (slot-value warehousedbobj 'warehouse-type) warehouse-type)
      (setf (slot-value warehousedbobj 'warehouse-purpose) warehouse-purpose)
      (setf (slot-value warehousedbobj 'default-transporter-id) default-transporter-id)
      (setf (slot-value warehousedbobj 'default-transporter-name) default-transporter-name)
      (setf (slot-value warehousedbobj 'eway-bill-enabled) eway-bill-enabled)
      (setf (slot-value warehousedbobj 'latitude) latitude)
      (setf (slot-value warehousedbobj 'longitude) longitude)
      (setf (slot-value warehousedbobj 'valuation-method) valuation-method)
      (setf (slot-value warehousedbobj 'hsn-wise-stock) hsn-wise-stock)
      (setf (slot-value warehousedbobj 'pan-number) pan-number)
      (setf (slot-value warehousedbobj 'warehouse-uuid) warehouse-uuid)
      (setf (slot-value warehousedbobj 'warehouse-code) warehouse-code)
      (setf (slot-value warehousedbobj 'updated) (mysql-now)))
    
    (setf (slot-value warehousedbservice 'dbobject) warehousedbobj)
    (setf (slot-value warehousedbservice 'businessobject) domainobj)
    (setcompany warehousedbservice comp)

    (let ((bk (with-db-update (warehousedbservice :source "Warehouse Update"))))
      ;; Transfer knowledge up to the service layer
      (setf (bo-knowledge service) bk)
      (setf domainobj (bo-knowledge-payload bk))
      ;; Return the newly created warehouse domain object
      domainobj)))
    

;;; ===========================================================================
;;; DELETE Operations
;;; ===========================================================================

(defmethod ProcessDeleteRequest ((adapter WarehouseAdapter) (requestmodel WarehouseRequestModel))
  :description "Adapter service method to call the BusinessService Delete method.
   中文：把 BusinessService 设为 WarehouseService 并 dispatch 到 doDelete。"
  (setf (slot-value adapter 'businessservice) (find-class 'WarehouseService))
  (call-next-method))

(defmethod doDelete ((service WarehouseService) (requestmodel WarehouseRequestModel))
  :description "Soft delete a warehouse.
   中文：取 row-id 与租户后调 select-warehouse-by-id；with-db-delete 宏完成软删
   （:allow-idempotent T 表示重复删除不报错）。返回：业务对象。"
  (let* ((warehousedbservice (make-instance 'WarehouseDBService))
         (row-id  (slot-value requestmodel 'row-id))
         (comp (company requestmodel))
         (tenant-id (slot-value comp 'row-id))
	 (domainobj (make-instance 'Warehouse))
         (warehousedbobj (select-warehouse-by-id row-id tenant-id)))
    (when warehousedbobj
      (setf (slot-value warehousedbservice 'dbobject) warehousedbobj)
      (setf (slot-value warehousedbservice 'businessobject) domainobj)
      (setcompany warehousedbservice comp)

      (let ((bk (with-db-delete (warehousedbservice :allow-idempotent T :source "Warehouse Update"))))
	;; Transfer knowledge up to the service layer
	(setf (bo-knowledge service) bk)
	(setf domainobj (bo-knowledge-payload bk))
	;; Return the newly created warehouse domain object
	domainobj))))


;;; ===========================================================================
;;; Response Processing
;;; ===========================================================================

(defmethod ProcessResponse ((adapter WarehouseAdapter) (busobj Warehouse))
  :description "Process warehouse business object to response model.
   中文：把 Warehouse 业务对象拷成 WarehouseResponseModel 返回。"
  (let ((responsemodel (make-instance 'WarehouseResponseModel)))
    (createresponsemodel adapter busobj responsemodel)))

(defmethod ProcessResponseList ((adapter WarehouseAdapter) warehouselist)
  :description "Process list of warehouse business objects.
   中文：批量把 Warehouse 业务对象列表转为 WarehouseResponseModel 列表。"
  (mapcar (lambda (domainobj)
            (let ((responsemodel (make-instance 'WarehouseResponseModel)))
              (createresponsemodel adapter domainobj responsemodel))) warehouselist))

(defmethod CreateResponseModel ((adapter WarehouseAdapter) (source Warehouse) (destination WarehouseResponseModel))
  :description "Create response model from warehouse business object with ownership fields.
   中文：业务对象 → 响应 DTO 的全字段拷贝。"
  (with-slots (row-id wname waddr1 waddr2 wpin wcity wstate wcountry 
               wmanager wphone waltphone wemail activeflag
               ownership-type owner-entity-type owner-entity-id
               operator-entity-type operator-entity-id legal-entity-type
               warehouse-gstin gstin-status legal-name is-primary-location
               state-code registration-type warehouse-type warehouse-purpose
               default-transporter-id default-transporter-name eway-bill-enabled
               latitude longitude valuation-method hsn-wise-stock pan-number 
               warehouse-uuid warehouse-code company) destination
    ;; Basic fields
    (setf row-id (slot-value source 'row-id))
    (setf wname (slot-value source 'wname))
    (setf waddr1 (slot-value source 'waddr1))
    (setf waddr2 (slot-value source 'waddr2))
    (setf wpin (slot-value source 'wpin))
    (setf wcity (slot-value source 'wcity))
    (setf wstate (slot-value source 'wstate))
    (setf wcountry (slot-value source 'wcountry))
    (setf wmanager (slot-value source 'wmanager))
    (setf wphone (slot-value source 'wphone))
    (setf waltphone (slot-value source 'waltphone))
    (setf wemail (slot-value source 'wemail))
    (setf activeflag (slot-value source 'activeflag))
    
    ;; Ownership fields
    (setf ownership-type (slot-value source 'ownership-type))
    (setf owner-entity-type (slot-value source 'owner-entity-type))
    (setf owner-entity-id (slot-value source 'owner-entity-id))
    (setf operator-entity-type (slot-value source 'operator-entity-type))
    (setf operator-entity-id (slot-value source 'operator-entity-id))
    (setf legal-entity-type (slot-value source 'legal-entity-type))
    
    ;; GST and Advanced Fields
    (setf warehouse-gstin (slot-value source 'warehouse-gstin))
    (setf gstin-status (slot-value source 'gstin-status))
    (setf legal-name (slot-value source 'legal-name))
    (setf is-primary-location (slot-value source 'is-primary-location))
    (setf state-code (slot-value source 'state-code))
    (setf registration-type (slot-value source 'registration-type))
    (setf warehouse-type (slot-value source 'warehouse-type))
    (setf warehouse-purpose (slot-value source 'warehouse-purpose))
    (setf default-transporter-id (slot-value source 'default-transporter-id))
    (setf default-transporter-name (slot-value source 'default-transporter-name))
    (setf eway-bill-enabled (slot-value source 'eway-bill-enabled))
    (setf latitude (slot-value source 'latitude))
    (setf longitude (slot-value source 'longitude))
    (setf valuation-method (slot-value source 'valuation-method))
    (setf hsn-wise-stock (slot-value source 'hsn-wise-stock))
    (setf pan-number (slot-value source 'pan-number))
    (setf warehouse-uuid (slot-value source 'warehouse-uuid))
    (setf warehouse-code (slot-value source 'warehouse-code))
    (setf company (slot-value source 'company))
    destination))

;;; ===========================================================================
;;; ViewModel Processing
;;; ===========================================================================

(defmethod CreateViewModel ((presenter WarehousePresenter) (responsemodel WarehouseResponseModel))
  :description "Create view model from response model with ownership fields.
   中文：响应 DTO → 视图 DTO 的全字段拷贝。返回 viewmodel（与 vendor 那边的笔误不同，
   本文件正确返回 viewmodel）。"
  (let ((viewmodel (make-instance 'WarehouseViewModel)))
    (with-slots (row-id wname waddr1 waddr2 wpin wcity wstate wcountry 
                 wmanager wphone waltphone wemail activeflag
                 ownership-type owner-entity-type owner-entity-id
                 operator-entity-type operator-entity-id legal-entity-type
                 warehouse-gstin gstin-status legal-name is-primary-location
                 state-code registration-type warehouse-type warehouse-purpose
                 default-transporter-id default-transporter-name eway-bill-enabled
                 latitude longitude valuation-method hsn-wise-stock pan-number 
                 warehouse-uuid warehouse-code company) responsemodel
      ;; Basic fields
      (setf (slot-value viewmodel 'row-id) row-id)
      (setf (slot-value viewmodel 'wname) wname)
      (setf (slot-value viewmodel 'waddr1) waddr1)
      (setf (slot-value viewmodel 'waddr2) waddr2)
      (setf (slot-value viewmodel 'wpin) wpin)
      (setf (slot-value viewmodel 'wcity) wcity)
      (setf (slot-value viewmodel 'wstate) wstate)
      (setf (slot-value viewmodel 'wcountry) wcountry)
      (setf (slot-value viewmodel 'wmanager) wmanager)
      (setf (slot-value viewmodel 'wphone) wphone)
      (setf (slot-value viewmodel 'waltphone) waltphone)
      (setf (slot-value viewmodel 'wemail) wemail)
      (setf (slot-value viewmodel 'activeflag) activeflag)
      
      ;; Ownership fields
      (setf (slot-value viewmodel 'ownership-type) ownership-type)
      (setf (slot-value viewmodel 'owner-entity-type) owner-entity-type)
      (setf (slot-value viewmodel 'owner-entity-id) owner-entity-id)
      (setf (slot-value viewmodel 'operator-entity-type) operator-entity-type)
      (setf (slot-value viewmodel 'operator-entity-id) operator-entity-id)
      (setf (slot-value viewmodel 'legal-entity-type) legal-entity-type)
      
      ;; GST and Advanced Fields
      (setf (slot-value viewmodel 'warehouse-gstin) warehouse-gstin)
      (setf (slot-value viewmodel 'gstin-status) gstin-status)
      (setf (slot-value viewmodel 'legal-name) legal-name)
      (setf (slot-value viewmodel 'is-primary-location) is-primary-location)
      (setf (slot-value viewmodel 'state-code) state-code)
      (setf (slot-value viewmodel 'registration-type) registration-type)
      (setf (slot-value viewmodel 'warehouse-type) warehouse-type)
      (setf (slot-value viewmodel 'warehouse-purpose) warehouse-purpose)
      (setf (slot-value viewmodel 'default-transporter-id) default-transporter-id)
      (setf (slot-value viewmodel 'default-transporter-name) default-transporter-name)
      (setf (slot-value viewmodel 'eway-bill-enabled) eway-bill-enabled)
      (setf (slot-value viewmodel 'latitude) latitude)
      (setf (slot-value viewmodel 'longitude) longitude)
      (setf (slot-value viewmodel 'valuation-method) valuation-method)
      (setf (slot-value viewmodel 'hsn-wise-stock) hsn-wise-stock)
      (setf (slot-value viewmodel 'pan-number) pan-number)
      (setf (slot-value viewmodel 'warehouse-uuid) warehouse-uuid)
      (setf (slot-value viewmodel 'warehouse-code) warehouse-code)
      (setf (slot-value viewmodel 'company) company))
    viewmodel))

(defmethod CreateAllViewModel ((presenter WarehousePresenter) responsemodellist)
  :description "Create view models from list of response models.
   中文：批量响应 DTO → 视图 DTO。"
  (mapcar (lambda (responsemodel)
            (createviewmodel presenter responsemodel)) responsemodellist))

;;; ===========================================================================
;;; View Rendering - JSON
;;; ===========================================================================

(defmethod RenderJSON ((view WarehouseJSONView) (viewmodel WarehouseViewModel))
  :description "Render warehouse view model as JSON with ownership fields.
   中文：把 viewmodel 转 (rowId/warehouseUuid/warehouseCode/...) camelCase 键 alist，
   再 json:encode-json-to-string 打包为 {success, failure, truth, payload} 形态。
   备注：用于 JSON API 响应；与 RenderJSONAll 的 payload 字段差异较大，
        单条版本字段更完整。"
  (with-slots (row-id wname waddr1 waddr2 wpin wcity wstate wcountry 
               wmanager wphone waltphone wemail activeflag
               ownership-type owner-entity-type owner-entity-id
               operator-entity-type operator-entity-id legal-entity-type
               warehouse-gstin gstin-status legal-name is-primary-location
               state-code registration-type warehouse-type warehouse-purpose
               default-transporter-id default-transporter-name eway-bill-enabled
               latitude longitude valuation-method hsn-wise-stock pan-number 
               warehouse-uuid warehouse-code) viewmodel
    (let* ((payload (list 
                     (cons "rowId" row-id)
                     (cons "warehouseUuid" warehouse-uuid)
                     (cons "warehouseCode" warehouse-code)
                     (cons "name" wname)
                     (cons "address1" waddr1)
                     (cons "address2" waddr2)
                     (cons "pin" wpin)
                     (cons "city" wcity)
                     (cons "state" wstate)
                     (cons "country" wcountry)
                     (cons "manager" wmanager)
                     (cons "phone" wphone)
                     (cons "altPhone" waltphone)
                     (cons "email" wemail)
                     (cons "activeFlag" activeflag)
                     ;; Ownership fields
                     (cons "ownershipType" ownership-type)
                     (cons "ownerEntityType" owner-entity-type)
                     (cons "ownerEntityId" owner-entity-id)
                     (cons "operatorEntityType" operator-entity-type)
                     (cons "operatorEntityId" operator-entity-id)
                     (cons "legalEntityType" legal-entity-type)
                     ;; GST and Advanced Fields
                     (cons "warehouseGstin" warehouse-gstin)
                     (cons "gstinStatus" gstin-status)
                     (cons "legalName" legal-name)
                     (cons "isPrimaryLocation" is-primary-location)
                     (cons "stateCode" state-code)
                     (cons "registrationType" registration-type)
                     (cons "warehouseType" warehouse-type)
                     (cons "warehousePurpose" warehouse-purpose)
                     (cons "defaultTransporterId" default-transporter-id)
                     (cons "defaultTransporterName" default-transporter-name)
                     (cons "ewayBillEnabled" eway-bill-enabled)
                     (cons "latitude" latitude)
                     (cons "longitude" longitude)
                     (cons "valuationMethod" valuation-method)
                     (cons "hsnWiseStock" hsn-wise-stock)
                     (cons "panNumber" pan-number)))
           (jsondata (json:encode-json-to-string
                      `(("success" . 1)
                        ("failure" . 0)
                        ("truth" . "T")
                        ("payload" . ,payload)))))
      jsondata)))

(defmethod RenderJSONAll ((view WarehouseJSONView) viewmodellist)
  :description "Render list of warehouse view models as JSON with ownership fields.
   中文：批量版 JSON 输出；每条只包含 (rowId, name, city, state, phone,
   ownership-*, warehouse-gstin, warehouse-type, isPrimaryLocation, activeFlag) 等
   摘要字段。最终响应携带 count 计数。"
  (let* ((payload (mapcar (lambda (vm)
                            (with-slots (row-id wname waddr1 waddr2 wpin wcity wstate 
                                         wcountry wmanager wphone waltphone wemail 
                                         activeflag ownership-type owner-entity-type 
                                         owner-entity-id warehouse-gstin gstin-status 
                                         legal-name is-primary-location state-code
                                         registration-type warehouse-type warehouse-purpose
                                         default-transporter-id default-transporter-name
                                         eway-bill-enabled latitude longitude 
                                         valuation-method hsn-wise-stock pan-number 
                                         warehouse-uuid warehouse-code) vm
                              (list 
                               (cons "rowId" row-id)
                               (cons "warehouseUuid" warehouse-uuid)
                               (cons "warehouseCode" warehouse-code)
                               (cons "name" wname)
                               (cons "city" wcity)
                               (cons "state" wstate)
                               (cons "phone" wphone)
                               (cons "ownershipType" ownership-type)
                               (cons "ownerEntityType" owner-entity-type)
                               (cons "ownerEntityId" owner-entity-id)
                               (cons "warehouseGstin" warehouse-gstin)
                               (cons "warehouseType" warehouse-type)
                               (cons "isPrimaryLocation" is-primary-location)
                               (cons "activeFlag" activeflag)))) viewmodellist))
         (jsondata (json:encode-json-to-string
                    `(("success" . 1)
                      ("failure" . 0)
                      ("truth" . "T")
                      ("count" . ,(length viewmodellist))
                      ("payload" . ,payload)))))
    jsondata))

;;; End of nst-bl-warehouse.lisp


