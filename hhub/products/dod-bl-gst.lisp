;;; dod-bl-gst.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：products —— 印度 GST HSN/SAC 业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/products/dod-bl-gst.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：HSN 税码的查询/创建/更新业务，以及商品 GST 税率取值。
;;;;       同时承接 Clean-Architecture 风格的 Adapter→Service→DBService 调用链
;;;;       （ProcessXxxRequest / doRead / doCreate / doUpdate / doReadAll）。
;;;;       注意：HSN 税码统一存于系统租户 tenant_id=1，对全平台共享。
;;;;
;;;; 主要导出：
;;;;   select-hsn-code-by-id / select-hsn-code-by-code
;;;;   select-hsn-codes-by-text / select-matching-hsn-codes
;;;;   select-all-GSTHSNCodes / get-system-gst-hsn-codes
;;;;   get-gstvalues-for-product   — 商品取 (cgst sgst igst compcess) 列表
;;;;   ProcessCreateRequest / ProcessUpdateRequest / ProcessReadRequest
;;;;   ProcessReadAllRequest（普通 + 搜索版） / doCreate / doUpdate / doRead / doreadall
;;;;   createGSTHSNCodesobject / copyGSTHSNCodes-domaintodb / copyGSTHSNCodes-dbtodomain
;;;;   CreateResponseModel / CreateViewModel / CreateAllViewModel / ProcessResponse[List]
;;;;
;;;; 关联：
;;;;   上游使用方：products/dod-ui-gst.lisp（PAP UI）、订单/发票模块计算税额时
;;;;   下游依赖：products/dod-dal-gst.lisp（实体定义、DTO）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

(defun select-hsn-codes-by-text (hsn-desc-like)
  "按 hsn-description LIKE '%xxx%' 模糊匹配。仅查系统租户 tenant_id=1。"
  (clsql:select 'dod-gst-hsn-codes :where 
		[and
		[= [:tenant-id] 1]
		[like [:hsn-description] (format NIL "%~a%"  hsn-desc-like)]]
		:caching *dod-database-caching* :flatp t))

(defun select-hsn-code-by-id (id)
  "按主键查 HSN（限定 tenant_id=1）。返回 dod-gst-hsn-codes / nil。"
(car (clsql:select 'dod-gst-hsn-codes :where
		   [and
		   [=  [:row-id] id]
		   [= [:tenant-id] 1]]
		     		      :caching *dod-database-caching* :flatp t)))

(defun select-matching-hsn-codes (hsn-code-like)
  "按 hsn-code 前缀 LIKE 'xxx%' 检索（前 200 条）。tenant_id=1。"
(clsql:select 'dod-gst-hsn-codes :where
	      [and
	      [like  [:hsn-code] (format NIL "~a%"  hsn-code-like)]
	      [= [:tenant-id] 1]]
	      :limit 200
	      :caching *dod-database-caching* :flatp t))

(defun select-hsn-code-by-code (hsn-code )
  "按完整 hsn-code 精确查（tenant_id=1）。返回单个实例 / nil。"
(car (clsql:select 'dod-gst-hsn-codes :where
		   [and
		   [=  [:hsn-code] hsn-code]
		   [= [:tenant-id] 1]]
				      :caching *dod-database-caching* :flatp t)))


(defun select-all-GSTHSNCodes ()
:documentation "This function stores all the currencies in a hashtable. The Key = country, Value = list of currency, code and symbol.
   中文：取系统租户 (tenant_id=1) 下的全部 HSN 税码（前 200 条）。
   备注：原英文 docstring 描述 currencies hashtable，与实际不符（推测：复制自 currency 模板未改）。"
(clsql:select 'dod-gst-hsn-codes :where
	      [= [:tenant-id] 1]
				 :limit 200
				 :caching *dod-database-caching* :flatp t ))


(defun get-system-gst-hsn-codes ()
  "获取系统级 HSN 税码（包装 select-all-GSTHSNCodes）。"
  (select-all-GSTHSNCodes))


(defun get-gstvalues-for-product (product)
  "查商品对应的 GST 税率列表 (cgst sgst igst comp-cess)。
   走 Adapter → Service 链路通过 ProcessReadRequest 拉 HSN 数据；
   依据 bo-knowledge 三态返回：
     :T 命中 → 返回真实税率列表
     :F 未找到 → 返回 (0.0 0.0 0.0 0.0)
     :U 未知 / :C 矛盾 → 抛 hhub-unknown / hhub-contradiction。
   参数：product — dod-prd-master 实例。"
  (let* ((hsncode (slot-value product 'hsn-code))
	 (adapter (make-instance 'GSTHSNCodesAdapter))
	 (requestmodel (make-instance 'GSTHSNCodesRequestModel
				      :hsncode hsncode
				      :company (product-company product)))
	 (gsthsncodeobj (processreadrequest adapter requestmodel))
	 (gstknowledge (bo-knowledge adapter)))
    (with-bo-knowledge-check gstknowledge
      (:T
       (let ((cgst (slot-value gsthsncodeobj 'cgst))
             (sgst (slot-value gsthsncodeobj 'sgst))
             (igst (slot-value gsthsncodeobj 'igst))
             (compcess (slot-value gsthsncodeobj 'comp-cess)))
         (list cgst sgst igst compcess)))
      (:F (list 0.0 0.0 0.0 0.0))
      (:U (error 'hhub-unknown :errstring (format nil "Unknown error while fetching GST values for HSN code ~A." hsncode)))
      (:C (error 'hhub-contradiction :errstring (format nil "Contradiction while fetching GST values for HSN code ~A." hsncode))))))

;; METHODS FOR ENTITY CREATE 
;; This file contains template code which will be used to generate for class methods.


(defmethod ProcessCreateRequest ((adapter GSTHSNCodesAdapter) (requestmodel GSTHSNCodesRequestModel))
  :description  "Adapter Service method to call the BusinessService Create method. Returns the created GSTHSNCodes  object.
   中文：Adapter 在创建请求时把 businessservice 绑定到 GSTHSNCodesService，再走父类的通用 ProcessCreate 流程。"
    ;; set the business service
  (setf (slot-value adapter 'businessservice) (find-class 'GSTHSNCodesService))
  ;; call the parent ProcessCreate
  (call-next-method))


(defmethod init ((dbas GSTHSNCodesDBService) (bo GSTHSNCodes))
  :description "Set the DB object and domain object.
   中文：DBService 初始化：构造空 dod-gst-hsn-codes 当作 dbobject，并把 domain 对象的 company 注入 DBService 上下文，再调父类。"
  (let* ((DBObj  (make-instance 'dod-gst-hsn-codes)))
    ;; Set specific fields of the DB object if you need to. 
    ;; End set specific fields of the DB object. 
    (setf (dbobject dbas) DBObj)
    ;; Set the company context for the HSN codes  DB service 
    (setcompany dbas (slot-value bo 'company))
    (call-next-method)))


(defmethod doreadall ((service GSTHSNCodesService) (requestmodel GSTHSNCodesRequestModel))
  "查询全部 HSN（系统租户 1），逐条把 db 对象拷贝成 domain GSTHSNCodes 列表。"
  (let* ((comp (company requestmodel))
	 (readalllst (select-all-GSTHSNCodes)))
    ;; return back a list of GST HSN Codes response model
    (mapcar (lambda (object)
	      (let ((domainobj (make-instance 'GSTHSNCodes)))
		(setf (slot-value domainobj 'company) comp)
		(copyGSTHSNCodes-dbtodomain object domainobj))) readalllst)))

(defmethod doreadall ((service GSTHSNCodesService) (requestmodel GSTHSNCodesSearchRequestModel))
  "搜索版 doreadall：用 requestmodel 的 hsncode 作为前缀模糊匹配。"
  (let* ((comp (company requestmodel))
	 (hsn-code-like (hsncode requestmodel))
	 (readalllst (select-matching-hsn-codes hsn-code-like)))
    ;; return back a list of GST HSN Codes response model
    (mapcar (lambda (dbobject)
	      (let ((domainobj (make-instance 'GSTHSNCodes)))
		(setf (slot-value domainobj 'company) comp)
		(copyGSTHSNCodes-dbtodomain dbobject domainobj))) readalllst)))

(defmethod doCreate ((service GSTHSNCodesService) (requestmodel GSTHSNCodesRequestModel))
  "Service 创建动作：从 requestmodel 取字段构造 domain GSTHSNCodes，初始化 DBService，
   把 domain 复制到 db 对象，db-save 写库。
   返回：刚创建的 domain 对象。副作用：INSERT DOD_GST_HSN_CODES。"
  (let* ((GSTHSNCodesdbservice (make-instance 'GSTHSNCodesDBService))
	 (hsncode (hsncode requestmodel))
	 (hsncode4digit (hsncode4digit requestmodel))
	 (description (description requestmodel))
	 (cgst (cgst requestmodel))
	 (sgst (sgst requestmodel))
	 (igst (igst requestmodel))
	 (compcess (compcess requestmodel))
	 (comp (company requestmodel))
	 (domainobj (createGSTHSNCodesobject hsncode hsncode4digit description cgst sgst igst compcess comp)))
         ;; Initialize the DB Service
    (init GSTHSNCodesdbservice domainobj)
    (copy-businessobject-to-dbobject GSTHSNCodesdbservice)
    (db-save GSTHSNCodesdbservice)
    ;; Return the newly created warehouse domain object
    domainobj))


(defun createGSTHSNCodesobject (hsncode hsncode4digit hsndescription cgst sgst igst compcess company)
  "在内存中构造一个 GSTHSNCodes domain 对象（不写库）。
   被 doCreate 调用，封装 make-instance 字段名映射。"
  (let* ((domainobj  (make-instance 'GSTHSNCodes
				       :hsncode hsncode
				       :hsncode4digit hsncode4digit
				       :description hsndescription
				       :cgst cgst
				       :sgst sgst
				       :igst igst
				       :compcess compcess
				       :company company)))

    domainobj))

(defmethod Copy-BusinessObject-To-DBObject ((dbas GSTHSNCodesDBService))
  :description "Syncs the dbobject and the domainobject.
   中文：把 DBService 中的 domain 对象字段同步到 db 对象，方便随后 db-save。"
  (let ((dbobj (slot-value dbas 'dbobject))
	(domainobj (slot-value dbas 'businessobject)))
    (setf (slot-value dbas 'dbobject) (copyGSTHSNCodes-domaintodb domainobj dbobj))))

;; source = domain destination = db
;; 把 domain GSTHSNCodes 的字段拷到 dod-gst-hsn-codes 实例的对应 slot；
;; tenant-id 取 company.row-id 完成多租户绑定。
(defun copyGSTHSNCodes-domaintodb (source destination)
  (let ((company (slot-value source 'company)))
    (with-slots (hsn-code hsn-code-4digit hsn-description cgst sgst igst comp-cess tenant-id) destination
      (setf hsn-code (slot-value source 'hsncode))
      (setf hsn-code-4digit (slot-value source 'hsncode4digit))
      (setf hsn-description (slot-value source 'description))
      (setf cgst (slot-value source 'cgst))
      (setf sgst (slot-value source 'sgst))
      (setf igst (slot-value source 'igst))
      (setf comp-cess (slot-value source 'compcess))
      (setf tenant-id (slot-value company 'row-id))
      destination)))


;; PROCESS UPDATE REQUEST
(defmethod ProcessUpdateRequest ((adapter GSTHSNCodesAdapter) (requestmodel GSTHSNCodesRequestModel))
  :description "Adapter service method to call the BusinessService Update method.
   中文：Update 入口，把 businessservice 绑成 GSTHSNCodesService 后调父类的通用 ProcessUpdate。"
  (setf (slot-value adapter 'businessservice) (find-class 'GSTHSNCodesService))
  ;; call the parent ProcessUpdate
  (call-next-method))

;; PROCESS READ ALL REQUEST.
(defmethod ProcessReadAllRequest ((adapter GSTHSNCodesAdapter) (requestmodel GSTHSNCodesRequestModel))
  :description "Adapter service method to read UPI Payments.
   中文：ReadAll 入口（备注：原英文 docstring 写的是 'UPI Payments'，疑似复制粘贴遗留，实际读取的是 HSN 列表）。"
  (setf (slot-value adapter 'businessservice) (find-class 'GSTHSNCodesService))
  (call-next-method))

(defmethod ProcessReadAllRequest ((adapter GSTHSNCodesAdapter) (requestmodel GSTHSNCodesSearchRequestModel))
  :description "Adapter service method to search HSN Codes.
   中文：搜索式 ReadAll 入口，requestmodel 是 SearchRequestModel 子类，会触发模糊匹配的 doreadall。"
  (setf (slot-value adapter 'businessservice) (find-class 'GSTHSNCodesService))
  (call-next-method))



(defmethod CreateViewModel ((presenter GSTHSNCodesPresenter) (responsemodel GSTHSNCodesResponseModel))
  "Presenter：把 ResponseModel 字段拷到 ViewModel，供 HTML 视图渲染。"
  (let ((viewmodel (make-instance 'GSTHSNCodesViewModel)))
    (with-slots (hsncode hsncode4digit description cgst sgst igst compcess company) responsemodel
      (setf (slot-value viewmodel 'hsncode) hsncode)
      (setf (slot-value viewmodel 'hsncode4digit) hsncode4digit)
      (setf (slot-value viewmodel 'description) description)
      (setf (slot-value viewmodel 'cgst) cgst)
      (setf (slot-value viewmodel 'sgst) sgst)
      (setf (slot-value viewmodel 'igst) igst)
      (setf (slot-value viewmodel 'compcess) compcess)
      (setf (slot-value viewmodel 'company) company))
    viewmodel))
  

(defmethod ProcessResponse ((adapter GSTHSNCodesAdapter) (busobj GSTHSNCodes))
  "把 domain 对象包装为 ResponseModel（构造 + createresponsemodel 复制字段）。"
  (let ((responsemodel (make-instance 'GSTHSNCodesResponseModel)))
    (createresponsemodel adapter busobj responsemodel)))

(defmethod ProcessResponseList ((adapter GSTHSNCodesAdapter) GSTHSNCodeslist)
  "批量版本：把一组 domain 对象转成 ResponseModel 列表。"
  (mapcar (lambda (domainobj)
	    (let ((responsemodel (make-instance 'GSTHSNCodesResponseModel)))
	      (createresponsemodel adapter domainobj responsemodel))) GSTHSNCodeslist))

(defmethod CreateAllViewModel ((presenter GSTHSNCodesPresenter) responsemodellist)
  "批量版本：ResponseModel 列表 → ViewModel 列表。"
  (mapcar (lambda (responsemodel)
	    (createviewmodel presenter responsemodel)) responsemodellist))


(defmethod CreateResponseModel ((adapter GSTHSNCodesAdapter) (source GSTHSNCodes) (destination GSTHSNCodesResponseModel))
  :description "source = GSTHSNCodes destination = GSTHSNCodesResponseModel.
   中文：把 domain GSTHSNCodes 的字段逐个拷贝到 ResponseModel。"
  (with-slots (hsncode hsncode4digit description sgst cgst igst compcess company) destination  
    (setf hsncode (slot-value source 'hsncode))
    (setf hsncode4digit (slot-value source 'hsncode4digit))
    (setf description (slot-value source 'description))
    (setf sgst  (slot-value source 'sgst))
    (setf cgst (slot-value source 'cgst))
    (setf igst (slot-value source 'igst))
    (setf compcess (slot-value source 'compcess))
    (setf company (slot-value source 'company))
    destination))

(defmethod doupdate ((service GSTHSNCodesService) (requestmodel GSTHSNCodesRequestModel))
  "Service 更新动作：以 hsncode 为键找出现存 db 对象，更新各税率字段并 db-save。
   返回：同步后的 domain 对象。副作用：UPDATE DOD_GST_HSN_CODES。"
  (let* ((GSTHSNCodesdbservice (make-instance 'GSTHSNCodesDBService))
	 (hsncode (hsncode requestmodel))
	 (hsncode4digit (hsncode4digit requestmodel))
	 (description (description requestmodel))
	 (cgst (cgst requestmodel))
	 (sgst (sgst requestmodel))
	 (igst (igst requestmodel))
	 (compcess (compcess requestmodel))
	 (comp (company requestmodel))
	 (GSTHSNCodesdbobj (select-hsn-code-by-code hsncode))
	 (domainobj (make-instance 'GSTHSNCodes)))
    ;; FIELD UPDATE CODE STARTS HERE 
    (when GSTHSNCodesdbobj
      (setf (slot-value GSTHSNCodesdbobj 'hsn-code) hsncode)
      (setf (slot-value GSTHSNCodesdbobj 'hsn-code-4digit) hsncode4digit)
      (setf (slot-value GSTHSNCodesdbobj 'hsn-description) description)
      (setf (slot-value GSTHSNCodesdbobj 'cgst) cgst)
      (setf (slot-value GSTHSNCodesdbobj 'sgst) sgst)
      (setf (slot-value GSTHSNCodesdbobj 'igst) igst)
      (setf (slot-value GSTHSNCodesdbobj 'comp-cess) compcess)
      (setf (slot-value GSTHSNCodesdbobj 'company) comp))
 
    ;;  FIELD UPDATE CODE ENDS HERE. 
    
    (setf (slot-value GSTHSNCodesdbservice 'dbobject) GSTHSNCodesdbobj)
    (setf (slot-value GSTHSNCodesdbservice 'businessobject) domainobj)
    
    (setcompany GSTHSNCodesdbservice comp)
    (db-save GSTHSNCodesdbservice)
    ;; Return the newly created UPI domain object
    (copyGSTHSNCodes-dbtodomain GSTHSNCodesdbobj domainobj)))


;; PROCESS THE READ REQUEST
(defmethod ProcessReadRequest ((adapter GSTHSNCodesAdapter) (requestmodel GSTHSNCodesRequestModel))
  :description "Adapter service method to read a single GSTHSNCodes.
   中文：读单个 HSN 的入口，绑定 businessservice 后调父类。"
  (setf (slot-value adapter 'businessservice) (find-class 'GSTHSNCodesService))
  (call-next-method))

(defmethod doread ((service GSTHSNCodesService) (requestmodel GSTHSNCodesRequestModel))
  "Service 读单条：按 hsncode 查 db，封装到 bo-knowledge（三态）。
   :T 时把 db 对象拷贝到 domain；:F 时返回带 company 的空 GSTHSNCodes。
   返回：GSTHSNCodes 实例（其外部判定靠 service 上的 bo-knowledge）。"
  (let* ((comp (company requestmodel))
	 (code (hsncode requestmodel))
	 (dbGSTHSNCode-knowledge (with-db-call (select-hsn-code-by-code code)))
	 (GSTHSNCodesobj (make-instance 'GSTHSNCodes)))

    (setf (bo-knowledge service) dbGSTHSNCode-knowledge)
    ;; return back a Vpaymentmethod  response model
    (setf (slot-value GSTHSNCodesobj 'company) comp)
    (when (eq (bo-knowledge-truth dbGSTHSNCode-knowledge) :T)
      (let ((dbGSTHSNCode (bo-knowledge-payload dbGSTHSNCode-knowledge)))
	(copyGSTHSNCodes-dbtodomain dbGSTHSNCode GSTHSNCodesobj)))
    GSTHSNCodesobj))

(defun copyGSTHSNCodes-dbtodomain (source destination)
  "把 db 对象 dod-gst-hsn-codes 字段映射到 domain GSTHSNCodes（命名差异：hsn-code → hsncode 等）。"
  (with-slots (row-id hsncode hsncode4digit description sgst cgst igst compcess company) destination
    (setf row-id (slot-value source 'row-id))
    (setf hsncode (slot-value source 'hsn-code))
    (setf hsncode4digit  (slot-value source 'hsn-code-4digit))
    (setf description (slot-value source 'hsn-description))
    (setf sgst (slot-value source 'sgst))
    (setf cgst (slot-value source 'cgst))
    (setf igst (slot-value source 'igst))
    (setf compcess (slot-value source 'comp-cess))
    destination))
