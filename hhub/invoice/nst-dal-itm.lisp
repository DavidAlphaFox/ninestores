;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：invoice 发票 —— 发票行项 实体定义（新 nst-* DDD/Hexagonal）
;;;; 分层：DAL（数据访问层 + 领域对象）
;;;; 文件：hhub/invoice/nst-dal-itm.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义发票行项相关的全部 CLOS 类型：
;;;;   - tax-entry / gst-breakdown   — GST 税额按 HSN+税率聚合的内存对象
;;;;   - InvoiceItemAdapter / Service / DBService / Presenter / HTMLView
;;;;   - InvoiceItemViewModel / ResponseModel / RequestModel / SearchRequestModel
;;;;   - InvoiceItem                 — 领域对象
;;;;   - dod-invoice-items           — CLSQL view-class，映射 DOD_INVOICE_ITEMS
;;;;
;;;; 主要导出：
;;;;   tax-entry / gst-breakdown
;;;;   generate-gst-tax-breakdown / add-item-to-tax-breakdown /
;;;;   remove-item-from-tax-breakdown / update-item-in-tax-breakdown /
;;;;   get-sorted-tax-summary    — GST 汇总抽象 API（在 nst-bl-itm.lisp 实现）
;;;;   InvoiceItem 领域对象 + CRUD 类簇 + 视图模型类簇
;;;;
;;;; 关联：
;;;;   上游使用方：invoice/nst-bl-itm.lisp（行为实现）、
;;;;               invoice/nst-ui-itm.lisp（控制器/视图）、
;;;;               invoice/nst-bl-ihd.lisp（发票头组装行项）
;;;;   下游依赖：core/hhub-bl-ent.lisp（基类 BusinessObject 等）、dod-company
;;;; ============================================================================

(in-package :nstores)


;; ----------------------------------------------------------------------------
;; 内存对象：tax-entry / gst-breakdown
;; 用于把多条 InvoiceItem 按 (HSN, 税率) 聚合成 GST 汇总表（发票尾部 HSN 摘要）。
;; ----------------------------------------------------------------------------
(defclass tax-entry ()
  ((hsn-code      :initarg :hsn-code      :accessor hsn-code)
   (taxable-value :initarg :taxable-value :initform 0 :accessor taxable-value)
   (cgst-rate     :initarg :cgst-rate     :initform 0 :accessor cgst-rate)
   (sgst-rate     :initarg :sgst-rate     :initform 0 :accessor sgst-rate)
   (igst-rate     :initarg :igst-rate     :initform 0 :accessor igst-rate)
   (cgst-amount   :initarg :cgst-amount   :initform 0 :accessor cgst-amount)
   (sgst-amount   :initarg :sgst-amount   :initform 0 :accessor sgst-amount)
   (igst-amount   :initarg :igst-amount   :initform 0 :accessor igst-amount))
  (:documentation "Represents a single row in the HSN summary table.
   中文：HSN 摘要表中的单行（按 HSN 编码 + 税率聚合的应税额与税额）。"))

(defclass gst-breakdown ()
  ((entries       :initform (make-hash-table :test 'equal) :accessor entries)
   (is-interstate :initarg :is-interstate :initform nil   :accessor interstate-p))
  (:documentation "A container that groups taxes by HSN and Rate.
   中文：GST 汇总容器：HSN+税率为 key 的哈希表 + 是否跨州标志。"))

(defgeneric  generate-gst-tax-breakdown (invoice-header invoice-items)
  (:documentation "Generate the invoice tax breakdown object based on the invoice header and invoice items.
   中文：根据发票头与行项，生成 GST 汇总对象。实现见 nst-bl-itm.lisp。"))

(defgeneric add-item-to-tax-breakdown (breakdown item)
  (:documentation "Processes an InvoiceItem and aggregates it into the breakdown summary.
   中文：把一条行项的金额累加到汇总（按 HSN+税率合并）。"))

(defgeneric remove-item-from-tax-breakdown (breakdown item)
  (:documentation "Subtracts an InvoiceItem's values from the breakdown summary.
   中文：从汇总中扣减一条行项的金额（撤销聚合）。"))

(defgeneric update-item-in-tax-breakdown (breakdown old-item new-item)
  (:documentation "Adjusts the breakdown when an item is modified.
   中文：行项被修改时增量更新汇总（=移除 old + 添加 new）。"))

(defgeneric get-sorted-tax-summary (breakdown)
  (:documentation "Returns the tax entries as a list sorted by HSN code.
   中文：把汇总表按 HSN 升序导出为列表（用于 PDF/HTML 渲染）。"))



;; ----------------------------------------------------------------------------
;; 六边形架构服务类簇（Adapter / Service / DBService / Presenter / View）
;; 每个类是 core/hhub-bl-ent.lisp 通用基类的具体化空壳，行为实现在 nst-bl-itm.lisp。
;; ----------------------------------------------------------------------------
(defclass InvoiceItemAdapter (AdapterService)
  ())

(defclass InvoiceItemDBService (DBAdapterService)
  ())

(defclass InvoiceItemPresenter (PresenterService)
  ())

(defclass InvoiceItemService (BusinessService)
  ())
(defclass InvoiceItemHTMLView (HTMLView)
  ())

;; ViewModel：渲染层使用的字段集合（与 ResponseModel/RequestModel 几乎同构）
(defclass InvoiceItemViewModel (ViewModel)
  ((InvoiceHeader
    :initarg :InvoiceHeader
    :accessor InvoiceHeader)
   (prd-id
    :initarg :prd-id
    :accessor prd-id)
   (prddesc
    :initarg :prddesc
    :accessor prddesc)
   (hsncode
    :initarg :hsncode
    :accessor hsncode)
   (qty
    :initarg :qty
    :accessor qty)
   (uom
    :initarg :uom
    :accessor uom)
   (price
    :initarg :price
    :accessor price)
   (discount
    :initarg :discount
    :accessor discount)
   (taxablevalue
    :initarg :taxablevalue
    :accessor taxablevalue)
   (cgstrate
    :initarg :cgstrate
    :accessor cgstrate)
   (cgstamt
    :initarg :cgstamt
    :accessor cgstamt)
   (sgstrate
    :initarg :sgstrate
    :accessor sgstrate)
   (sgstamt
    :initarg :sgstamt
    :accessor sgstamt)
   (igstrate
    :initarg :igstrate
    :accessor igstrate)
   (igstamt
    :initarg :igstamt
    :accessor igstamt)
   (totalitemval
    :initarg :totalitemval
    :accessor totalitemval)
   (status
    :initarg :status
    :accessor status)
   (company
    :initarg :company
    :accessor company)))

;; ResponseModel：Service 层向 Presenter 输出的传输对象
(defclass InvoiceItemResponseModel (ResponseModel)
  ((InvoiceHeader
    :initarg :InvoiceHeader
    :accessor InvoiceHeader)
   (prd-id
    :initarg :prd-id
    :accessor prd-id)
   (prddesc
    :initarg :prddesc
    :accessor prddesc)
   (hsncode
    :initarg :hsncode
    :accessor hsncode)
   (qty
    :initarg :qty
    :accessor qty)
   (uom
    :initarg :uom
    :accessor uom)
   (price
    :initarg :price
    :accessor price)
   (discount
    :initarg :discount
    :accessor discount)
   (taxablevalue
    :initarg :taxablevalue
    :accessor taxablevalue)
   (cgstrate
    :initarg :cgstrate
    :accessor cgstrate)
   (cgstamt
    :initarg :cgstamt
    :accessor cgstamt)
   (sgstrate
    :initarg :sgstrate
    :accessor sgstrate)
   (sgstamt
    :initarg :sgstamt
    :accessor sgstamt)
   (igstrate
    :initarg :igstrate
    :accessor igstrate)
   (igstamt
    :initarg :igstamt
    :accessor igstamt)
   (totalitemval
    :initarg :totalitemval
    :accessor totalitemval)
   (status
    :initarg :status
    :accessor status)
   (company
    :initarg :company
    :accessor company)))
   

;; RequestModel：控制器封装入参后传给 Adapter
(defclass InvoiceItemRequestModel (RequestModel)
  ((InvoiceHeader
    :initarg :InvoiceHeader
    :accessor InvoiceHeader)
   (prd-id
    :initarg :prd-id
    :accessor prd-id)
   (prddesc
    :initarg :prddesc
    :accessor prddesc)
   (hsncode
    :initarg :hsncode
    :accessor hsncode)
   (qty
    :initarg :qty
    :accessor qty)
   (uom
    :initarg :uom
    :accessor uom)
   (price
    :initarg :price
    :accessor price)
   (discount
    :initarg :discount
    :accessor discount)
   (taxablevalue
    :initarg :taxablevalue
    :accessor taxablevalue)
   (cgstrate
    :initarg :cgstrate
    :accessor cgstrate)
   (cgstamt
    :initarg :cgstamt
    :accessor cgstamt)
   (sgstrate
    :initarg :sgstrate
    :accessor sgstrate)
   (sgstamt
    :initarg :sgstamt
    :accessor sgstamt)
   (igstrate
    :initarg :igstrate
    :accessor igstrate)
   (igstamt
    :initarg :igstamt
    :accessor igstamt)
   (totalitemval
    :initarg :totalitemval
    :accessor totalitemval)
   (status
    :initarg :status
    :accessor status)
   (company
    :initarg :company
    :accessor company)))


;; 搜索专用 RequestModel（继承自 InvoiceItemRequestModel，目前无新增字段）
(defclass InvoiceItemSearchRequestModel (InvoiceItemRequestModel)
  ())

;; 领域对象：六边形架构核心 BusinessObject
(defclass InvoiceItem (BusinessObject)
  ((row-id)
   (InvoiceHeader
    :initarg :InvoiceHeader
    :accessor InvoiceHeader)
   (prd-id
    :initarg :prd-id
    :accessor prd-id)
   (prddesc
    :initarg :prddesc
    :accessor prddesc)
   (hsncode
    :initarg :hsncode
    :accessor hsncode)
   (qty
    :initarg :qty
    :accessor qty)
   (uom
    :initarg :uom
    :accessor uom)
   (price
    :initarg :price
    :accessor price)
   (discount
    :initarg :discount
    :accessor discount)
   (taxablevalue
    :initarg :taxablevalue
    :accessor taxablevalue)
   (cgstrate
    :initarg :cgstrate
    :accessor cgstrate)
   (cgstamt
    :initarg :cgstamt
    :accessor cgstamt)
   (sgstrate
    :initarg :sgstrate
    :accessor sgstrate)
   (sgstamt
    :initarg :sgstamt
    :accessor sgstamt)
   (igstrate
    :initarg :igstrate
    :accessor igstrate)
   (igstamt
    :initarg :igstamt
    :accessor igstamt)
   (totalitemval
    :initarg :totalitemval
    :accessor totalitemval)
   (status
    :initarg :status
    :accessor status)
   (company
    :initarg :company
    :accessor company)))


;; ----------------------------------------------------------------------------
;; 实体：dod-invoice-items
;; 表：DOD_INVOICE_ITEMS
;; 含义：发票行项（一张发票包含多行商品/服务）。每行携带数量、单价、HSN 编码、
;;       折扣以及 CGST/SGST/IGST 三种 GST 速率与金额。
;; 关键字段：
;;   row-id          主键
;;   invheadid       外键 → dod-invoice-header
;;   prd-id          关联商品（业务上推测；表里无强外键）
;;   prddesc         商品描述快照（防止后续商品改名影响历史发票）
;;   hsncode         GST 商品/服务分类编码
;;   qty / uom       数量与单位
;;   price / discount / taxable-value
;;   cgstrate/cgstamt / sgstrate/sgstamt / igstrate/igstamt
;;   totalitemval    行项合计（应税额 + 税额）
;;   status          行项状态
;;   deleted-state   N/Y 软删
;;   tenant-id       多租户隔离键 → dod-company.row-id
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-invoice-items ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)
   (invheadid
    :initarg :invheadid
    :type integer
    :accessor invheadid)
   (prd-id
    :type integer
    :initarg :prd-id
    :accessor prd-id)
   (prddesc
    :type (string 200)
    :initarg :prddesc
    :accessor prddesc)
   (hsncode
    :type (string 20)
    :initarg :hsncode
    :accessor hsncode)
   (qty
    :type integer
    :initarg :qty
    :accessor qty)
   (uom
    :type (string 20)
    :initarg :uom
    :accessor uom)
   (price
    :type float
    :initarg :price
    :accessor price)
   (discount
    :type float
    :initarg :discount
    :accessor discount)
   (taxable-value
    :type float
    :initarg :taxable-value
    :accessor taxable-value)
   (cgstrate
    :type float
    :initarg :cgstrate
    :accessor cgstrate)
   (cgstamt
    :type float
    :initarg :cgstamt
    :accessor cgstamt)
   (sgstrate
    :type float
    :initarg :sgstrate
    :accessor sgstrate)
   (sgstamt
    :type float
    :initarg :sgstamt
    :accessor sgstamt)
   (igstrate
    :type float
    :initarg :igstrate
    :accessor igstrate)
   (igstamt
    :type float
    :initarg :igstamt
    :accessor igstamt)
   (totalitemval
    :type float
    :initarg :totalitemval
    :accessor totalitemval)
   (status
    :type (string 20)
    :initarg :status
    :accessor status)
   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state) 
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
  (:BASE-TABLE dod_invoice_items))


