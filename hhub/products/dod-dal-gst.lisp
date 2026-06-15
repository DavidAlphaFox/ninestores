;;; dod-dal-gst.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：products —— 印度 GST HSN/SAC 税码主数据
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/products/dod-dal-gst.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 GST（Goods and Services Tax）HSN/SAC 税率数据所需的类层级 ——
;;;;       传统的 Adapter / Presenter / Service / View / RequestModel / ResponseModel
;;;;       六件套（项目里的 Clean Architecture 风格脚手架），以及核心 CLSQL
;;;;       view-class dod-gst-hsn-codes 映射到表 DOD_GST_HSN_CODES。
;;;;
;;;; 主要导出：
;;;;   GSTHSNCodesAdapter / GSTHSNCodesDBService / GSTHSNCodesService
;;;;   GSTHSNCodesPresenter / GSTHSNCodesHTMLView
;;;;   GSTHSNCodesViewModel / GSTHSNCodesRequestModel / GSTHSNCodesSearchRequestModel
;;;;   GSTHSNCodesResponseModel / GSTHSNCodes
;;;;   dod-gst-hsn-codes  — 表 DOD_GST_HSN_CODES 的 CLSQL 视图类
;;;;
;;;; 关联：
;;;;   上游使用方：products/dod-bl-gst.lisp（CRUD）、products/dod-ui-gst.lisp（控制器）
;;;;   下游依赖：core 框架基类（AdapterService / BusinessService / ResponseModel 等）
;;;; ============================================================================

(in-package :nstores)



;; ----------------------------------------------------------------------------
;; 以下 6 个类构成 GST HSN 子系统的 Clean Architecture 脚手架：
;;   Adapter  —— 适配外部输入；DBService —— 数据库适配；
;;   Service  —— 领域业务；Presenter / HTMLView —— 展示层；
;; 业务方法都在 dod-bl-gst.lisp / dod-ui-gst.lisp 中以 defmethod 挂接。
;; ----------------------------------------------------------------------------
(defclass GSTHSNCodesAdapter (AdapterService)
  ())

(defclass GSTHSNCodesDBService (DBAdapterService)
  ())

(defclass GSTHSNCodesPresenter (PresenterService)
  ())

(defclass GSTHSNCodesService (BusinessService)
  ())
(defclass GSTHSNCodesHTMLView (HTMLView)
  ())

;; ----------------------------------------------------------------------------
;; 三个数据载体（DTO）：ViewModel/RequestModel/ResponseModel 字段相同：
;;   hsncode / hsncode4digit / description / cgst / sgst / igst / compcess / company
;; 用于在 Controller ↔ Service ↔ View 之间传递 HSN 税码与税率值。
;; cgst/sgst 是邦内交易拆分成的中央税与州税；igst 是跨邦税；compcess 是补偿税。
;; ----------------------------------------------------------------------------
(defclass GSTHSNCodesViewModel (ViewModel)
  ((hsncode
    :initarg :hsncode
    :accessor hsncode)
   (hsncode4digit
    :initarg :hsncode4digit
    :accessor hsncode4digit)
   (description
    :initarg :description
    :accessor description)
   (cgst
    :initarg :cgst
    :type float
    :accessor cgst)
   (sgst
    :initarg :sgst
    :type float
    :accessor sgst)
   (igst
    :initarg :igst
    :type float
    :accessor igst)
   (compcess
    :initarg :compcess
    :accessor compcess)
   (company
    :initarg :company
    :accessor company)))

(defclass GSTHSNCodesResponseModel (ResponseModel)
  ((hsncode
    :initarg :hsncode
    :accessor hsncode)
   (hsncode4digit
    :initarg :hsncode4digit
    :accessor hsncode4digit)
   (description
    :initarg :description
    :accessor description)
   (cgst
    :initarg :cgst
    :type float
    :accessor cgst)
   (sgst
    :initarg :sgst
    :type float
    :accessor sgst)
   (igst
    :initarg :igst
    :type float
    :accessor igst)
   (compcess
    :initarg :compcess
    :accessor compcess)
   (company
    :initarg :company
    :accessor company)))


(defclass GSTHSNCodesRequestModel (RequestModel)
  ((hsncode
    :initarg :hsncode
    :accessor hsncode)
   (hsncode4digit
    :initarg :hsncode4digit
    :accessor hsncode4digit)
   (description
    :initarg :description
    :accessor description)
   (cgst
    :initarg :cgst
    :type float
    :accessor cgst)
   (sgst
    :initarg :sgst
    :type float
    :accessor sgst)
   (igst
    :initarg :igst
    :type float
    :accessor igst)
   (compcess
    :initarg :compcess
    :accessor compcess)
   (company
    :initarg :company
    :accessor company)))

;; SearchRequestModel：把同样字段当作搜索条件复用，通常以 LIKE 模糊匹配。
(defclass GSTHSNCodesSearchRequestModel (GSTHSNCodesRequestModel)
  ())

;; 业务对象（BusinessObject 子类）：内存中纯领域模型，比 ViewModel 多一个 row-id。
(defclass GSTHSNCodes (BusinessObject)
  ((row-id)
   (hsncode
    :initarg :hsncode
    :accessor hsncode)
   (hsncode4digit
    :initarg :hsncode4digit
    :accessor hsncode4digit)
   (description
    :initarg :description
    :accessor description)
   (cgst
    :initarg :cgst
    :type float
    :accessor cgst)
   (sgst
    :initarg :sgst
    :type float
    :accessor sgst)
   (igst
    :initarg :igst
    :type float
    :accessor igst)
   (compcess
    :initarg :compcess
    :accessor compcess)
   (company
    :initarg :company
    :accessor company)))

;; ----------------------------------------------------------------------------
;; 实体：dod-gst-hsn-codes
;; 表：DOD_GST_HSN_CODES
;; 含义：每行一个 HSN/SAC 编码及对应的 GST 税率组合。
;; 关键字段：
;;   row-id           主键
;;   hsn-code         完整 HSN 编码（最多 10 位）
;;   hsn-code-4digit  HSN 4 位前缀（用于商品按章节匹配）
;;   hsn-description  说明文字
;;   cgst / sgst      邦内交易拆分的中央税 + 州税税率
;;   igst             跨邦交易税率
;;   comp-cess        补偿税（compensation cess）税率
;;   comp-cess-func   补偿税计算函数名（推测：表达式式分段公式，按字符串 intern 调用）
;;   gst-hsn-func     用以判定该 HSN 适用条件的函数名（推测：动态规则）
;;   tenant-id        多租户隔离键 → dod-company.row-id
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-gst-hsn-codes ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)
   (hsn-code
    :accessor hsn-code
    :TYPE (string 10))
   (hsn-code-4digit
    :accessor hsn-code-4digit
    :type (string 4))
   
   (hsn-description
    :accessor hsn-description
    :TYPE (string 500))

   (cgst
    :accessor cgst
    :type float
    :initarg :cgst)

   (sgst
    :accessor sgst
    :type float
    :initarg :sgst)

   (igst
    :accessor igst
    :type float
    :initarg :igst)

   (comp-cess
    :accessor comp-cess
    :type float
    :initarg :comp-cess)

   (comp-cess-func
    :accessor comp-cess-func
    :TYPE (string 255))

   (gst-hsn-func
    :accessor gst-hsn-func
    :TYPE (string 255))

   (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR get-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET NIL)))
  (:BASE-TABLE dod_gst_hsn_codes))
