;;; dod-bl-vpm.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家支付方式开关业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/vendor/dod-bl-vpm.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：VPaymentMethods 服务层方法（Adapter / Service / DBService 协作）：
;;;;       Create / Update / Read / ReadAll，以及 DTO ↔ Domain ↔ DB 拷贝。
;;;;       直接 DAL 包装：select-vpayment-methods / select-allvpayment-methods。
;;;;
;;;; 主要导出：
;;;;   createVPaymentMethodsobject     —— 构造 VPaymentMethods 业务对象
;;;;   copyVPaymentMethods-domaintodb  —— 业务对象 → dod-vpayment-methods
;;;;   copyvpaymentmethods-dbtodomain  —— dod-vpayment-methods → 业务对象
;;;;   select-vpayment-methods         —— 单条查询（按 vendor + tenant，最近一条）
;;;;   select-allvpayment-methods      —— 列表查询
;;;;
;;;; 关联：
;;;;   上游使用方：vendor/dod-ui-ven.lisp（卖家设置页面）。
;;;;   下游依赖：vendor/dod-dal-vpm.lisp（实体）、vendor/dod-bl-ven.lisp。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;; METHODS FOR ENTITY CREATE
;; This file contains template code which will be used to generate for class methods.


(defmethod ProcessCreateRequest ((adapter VPaymentMethodsAdapter) (requestmodel VPaymentMethodsRequestModel))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created Vendor Payment Methods object.
   中文：把 Adapter 的 BusinessService 设为 VPaymentMethodsService，再委托父类 dispatch 调用 doCreate。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'VPaymentMethodsService))
  ;; call the parent ProcessCreate
  (call-next-method))

(defmethod init ((dbas VPaymentMethodsDBService) (bo VPaymentMethods))
  :description "Set the DB object and domain object.
   中文：初始化 DBService —— 创建空 dod-vpayment-methods 挂到 dbas，并把 company 上下文绑上去。"
  (let* ((DBObj  (make-instance 'dod-vpayment-methods))
	 (company (slot-value bo 'company)))
    ;; Set specific fields of the DB object if you need to. 
    ;; End set specific fields of the DB object. 
    (setf (dbobject dbas) DBObj)
    ;; Set the company context for the VPaymentMethods DB service 
    (setcompany dbas company)
    (call-next-method)))

(defmethod doCreate ((service VPaymentMethodsService) (requestmodel VPaymentMethodsRequestModel))
  "新建一条 vendor 支付方式开关：从 requestmodel 取各开关字段构造业务对象，
   通过 DBService 拷贝到 DB 对象后保存。返回：新建的业务对象。"
  (let* ((VPaymentMethodsdbservice (make-instance 'VPaymentMethodsDBService))
	 (vendor (vendor requestmodel))
	 (codenabled (codenabled requestmodel))
	 (upienabled (upienabled requestmodel))
	 (payprovidersenabled (payprovidersenabled requestmodel))
	 (walletenabled (walletenabled requestmodel))
	 (paylaterenabled (paylaterenabled requestmodel))
	 (company (company requestmodel))
	 (domainobj (createVPaymentMethodsobject vendor codenabled upienabled payprovidersenabled walletenabled paylaterenabled company))) 
         ;; Initialize the DB Service
    (init VPaymentMethodsdbservice domainobj)
    (copy-businessobject-to-dbobject VPaymentMethodsdbservice)
    (db-save VPaymentMethodsdbservice)
    ;; Return the newly created domain object
    domainobj))


(defun createVPaymentMethodsobject (vendor codenabled upienabled payprovidersenabled walletenabled paylaterenabled company)
  "构造 VPaymentMethods 业务对象（active-flag='Y'、deleted-state='N'）。"
  (let* ((domainobj  (make-instance 'VPaymentMethods
				       :vendor vendor 
				       :codenabled codenabled
				       :upienabled upienabled
				       :payprovidersenabled payprovidersenabled
				       :walletenabled walletenabled
				       :paylaterenabled paylaterenabled
				       :deleted-state "N"
				       :active-flag "Y"
				       :company company)))
    domainobj))



(defmethod Copy-BusinessObject-To-DBObject ((dbas VPaymentMethodsDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：把 VPaymentMethods 业务对象的字段拷贝到 dod-vpayment-methods 数据库对象。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyVPaymentMethods-domaintodb domainobj dbobj))))

(defun copyVPaymentMethods-domaintodb (source destination) ;; source = domain destination = db
  "domain → db 字段拷贝：从 vendor 取 vendor-id，从 company 取 tenant-id；
   其他开关字段一一搬运。返回：destination。"
  (let ((vendor (slot-value source 'vendor))
	(company (slot-value source 'company)))
    (with-slots (vendor-id codenabled upienabled payprovidersenabled walletenabled paylaterenabled  deleted-state active-flag tenant-id) destination
      (setf vendor-id (slot-value vendor 'row-id))
      (setf codenabled (slot-value source 'codenabled))
      (setf upienabled (slot-value source 'upienabled))
      (setf payprovidersenabled (slot-value source 'payprovidersenabled))
      (setf walletenabled (slot-value source 'walletenabled))
      (setf paylaterenabled (slot-value source 'paylaterenabled))
      (setf tenant-id (slot-value company 'row-id))
      (setf deleted-state (slot-value source 'deleted-state))
      (setf active-flag (slot-value source 'active-flag))
      destination)))
  

;; PROCESS UPDATE REQUEST
(defmethod ProcessUpdateRequest ((adapter VPaymentMethodsAdapter) (requestmodel VPaymentMethodsRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：把 BusinessService 设为 VPaymentMethodsService，再委托父类调 doupdate。"
  (setf (slot-value adapter 'businessservice) (find-class 'VPaymentMethodsService))
  ;; call the parent ProcessUpdate
  (call-next-method))

(defmethod doupdate ((service VPaymentMethodsService) (requestmodel VPaymentMethodsRequestModel))
  "更新某 vendor 在某租户下的支付开关：先 select 旧记录，逐字段覆盖后 db-save。
   返回：拷回的业务对象。副作用：UPDATE。"
  (let* ((vend (vendor requestmodel))
	 (comp (company requestmodel))
	 (codenabled (codenabled requestmodel))
	 (upienabled (upienabled requestmodel))
	 (payprovidersenabled (payprovidersenabled requestmodel))
	 (walletenabled (walletenabled requestmodel))
	 (paylaterenabled (paylaterenabled requestmodel))
	 (vpaymentmethodsdbservice (make-instance 'VPaymentMethodsDBService))
	 (vpaymentmethodsdbobj (select-vpayment-methods vend comp))
	 (vpaymentmethodsobj (make-instance 'VPaymentMethods)))
    
    (setf (slot-value vpaymentmethodsdbobj 'codenabled) codenabled)
    (setf (slot-value vpaymentmethodsdbobj 'upienabled) upienabled)
    (setf (slot-value vpaymentmethodsdbobj 'payprovidersenabled) payprovidersenabled)
    (setf (slot-value vpaymentmethodsdbobj 'walletenabled) walletenabled)
    (setf (slot-value vpaymentmethodsdbobj 'paylaterenabled) paylaterenabled)
  
    (setf (slot-value vpaymentmethodsdbservice 'dbobject) vpaymentmethodsdbobj)
    (setf (slot-value vpaymentmethodsdbservice 'businessobject) vpaymentmethodsobj)
    
    (setcompany vpaymentmethodsdbservice comp)
    (db-save vpaymentmethodsdbservice)
    ;; Return the newly created vendor payment methods domain object
    (copyvpaymentmethods-dbtodomain vpaymentmethodsdbobj vpaymentmethodsobj)))


;; PROCESS READ ALL REQUEST.
(defmethod ProcessReadAllRequest ((adapter VPaymentMethodsAdapter) (requestmodel VPaymentMethodsRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：原英文 'UPI Payments' 系笔误（应为 vendor 支付方式列表）。
   设定 BusinessService 后委托父类调用 doreadall。"
  (setf (slot-value adapter 'businessservice) (find-class 'VPaymentMethodsService))
  (call-next-method))

(defmethod doreadall ((service VPaymentMethodsService) (requestmodel VPaymentMethodsRequestModel))
  "列出某 vendor 在某租户下全部支付方式记录，并把每条 dod-vpayment-methods 拷贝为业务对象。"
  (let* ((vend (vendor requestmodel))
	 (comp (company requestmodel))
	 (domainobjlst (select-allvpayment-methods vend comp)))
    ;; return back a list of VpaymentMethods business objects 
    (mapcar (lambda (object)
	      (let ((vpaymentmethod (make-instance 'VPaymentMethods)))
		(copyvpaymentmethods-dbtodomain object vpaymentmethod))) domainobjlst)))

(defmethod ProcessReadRequest ((adapter VPaymentMethodsAdapter) (requestmodel VPaymentMethodsRequestModel))
  :description "Adapter service method to read a single VPaymentMethods.
   中文：把 BusinessService 设为 VPaymentMethodsService 后委托父类调 doread。"
  (setf (slot-value adapter 'businessservice) (find-class 'VPaymentMethodsService))
  (call-next-method))

(defmethod doread ((service VPaymentMethodsService) (requestmodel VPaymentMethodsRequestModel))
  "读取某 vendor 在某 tenant 下的支付方式开关；包装为 bo-knowledge 形态。
   备注：当 bo-knowledge-truth = :T 时把 DB 字段拷到业务对象。
   写日志：调用 with-db-call 记录知识捕获。"
  (let* ((comp (company requestmodel))
	 (vend (vendor requestmodel))
	 (dbvpayments-knowledge  (with-db-call (select-vpayment-methods vend comp)))
	 (vpaymentmethodsobj (make-instance 'VPaymentMethods)))
    
    (setf (bo-knowledge service) dbvpayments-knowledge)
    ;; return back a Vpaymentmethod  response model
    (setf (slot-value vpaymentmethodsobj 'company) comp)
    (when (eq (bo-knowledge-truth dbvpayments-knowledge) :T)
      (let ((dbvpayments (bo-knowledge-payload dbvpayments-knowledge)))
	(copyvpaymentmethods-dbtodomain dbvpayments vpaymentmethodsobj)))
     vpaymentmethodsobj))

(defun copyvpaymentmethods-dbtodomain (source destination)
  "db → domain 字段拷贝：从 tenant-id/vendor-id 反向解析为 company/vendor 实例后填入。
   返回：destination。"
  (let* ((comp (select-company-by-id (slot-value source 'tenant-id)))
	 (vend (select-vendor-by-id (slot-value source 'vendor-id))))
    (with-slots (vendor codenabled upienabled payprovidersenabled walletenabled paylaterenabled  deleted-state active-flag company) destination 
      (setf vendor vend)
      (setf company comp)
      (setf codenabled (slot-value source 'codenabled))
      (setf upienabled (slot-value source 'upienabled))
      (setf payprovidersenabled (slot-value source 'payprovidersenabled))
      (setf walletenabled (slot-value source 'walletenabled))
      (setf paylaterenabled (slot-value source 'paylaterenabled))
      (setf deleted-state (slot-value source 'deleted-state))
      (setf active-flag (slot-value source 'active-flag))
      destination)))

(defun select-vpayment-methods (vend company)
  "按 (vendor, company) 取最新一条未软删的支付开关记录（按 row-id desc）。
   返回：dod-vpayment-methods / nil。缓存按 *dod-database-caching*。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vend 'row-id)))
    (car (clsql:select 'dod-vpayment-methods  :where
		[and 
		[= [:deleted-state] "N"]
		[= [:vendor-id] vendor-id]
		[= [:tenant-id] tenant-id]] :order-by '(([row-id] :desc)) 
					 :caching *dod-database-caching* :flatp t))))

(defun select-allvpayment-methods (vend company)
  "按 (vendor, company) 取全部未软删支付开关记录（按 row-id desc）。返回：列表。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vend 'row-id)))
    (clsql:select 'dod-vpayment-methods  :where
		  [and 
		  [= [:deleted-state] "N"]
		  [= [:vendor-id] vendor-id]
		  [= [:tenant-id] tenant-id]] :order-by '(([row-id] :desc)) 
					 :caching *dod-database-caching* :flatp t)))


