;;; nst-dal-ihd.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：invoice 发票 —— 发票头实体定义（新 nst-* DDD/Hexagonal）
;;;; 分层：DAL（数据访问层 + 领域对象）
;;;; 文件：hhub/invoice/nst-dal-ihd.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：发票头模块的全部 CLOS 类型：
;;;;   - 服务类簇：InvoiceHeaderAdapter / Service / DBService / Presenter / HTMLView
;;;;   - 视图模型：InvoiceHeaderViewModel
;;;;   - 数据传输：InvoiceHeaderRequestModel / SearchRequestModel /
;;;;     ContextIDRequestModel / StatusRequestModel / InvoiceHeaderResponseModel
;;;;   - SessionInvoice：会话内"正在编辑的发票"完整状态
;;;;   - InvoiceHeader：领域对象（带默认值 status='DRAFT' 等）
;;;;   - dod-Invoice-Header：CLSQL view-class，映射 DOD_INVOICE_HEADER 表
;;;;
;;;; 主要导出：
;;;;   类簇见上；外部最常用的：
;;;;   InvoiceHeader（业务对象）、SessionInvoice（会话状态）、dod-Invoice-Header（DAL）
;;;;
;;;; 关联：
;;;;   上游使用方：invoice/nst-bl-ihd.lisp（行为实现）、invoice/nst-ui-ihd.lisp（控制器/视图）
;;;;   下游依赖：core/hhub-bl-ent.lisp 基类、dod-cust-profile、dod-vend-profile、dod-company
;;;; ============================================================================

(in-package :nstores)


;; ----------------------------------------------------------------------------
;; 服务类簇：六边形管线具体化（行为实现在 nst-bl-ihd.lisp）
;; ----------------------------------------------------------------------------
(defclass InvoiceHeaderAdapter (AdapterService)
  ())

(defclass InvoiceHeaderDBService (DBAdapterService)
  ())

(defclass InvoiceHeaderPresenter (PresenterService)
  ())

(defclass InvoiceHeaderService (BusinessService)
  ())
(defclass InvoiceHeaderHTMLView (HTMLView)
  ())

;; ----------------------------------------------------------------------------
;; SessionInvoice：会话内的"正在编辑发票"聚合对象。
;; 持有客户 + 发票头 + 行项列表 + 商品列表 + 实时 GST 汇总；存到
;; hunchentoot 会话变量 :session-invoices-ht，按 sessioninvkey 索引。
;; 编辑时直接操作内存对象；保存时再批量持久化。
;; ----------------------------------------------------------------------------
(defclass SessionInvoice (BusinessObject)
  ((customer
    :initarg :customer
    :accessor customer)
   (invoiceheader
    :initarg :invoiceheader
    :accessor invoiceheader)
   (invoiceitems
    :initarg :inivoiceitems     ; 注意：initarg 拼写为 :inivoiceitems（少一个 'o'，模板残留）
    :accessor invoiceitems
    :initform '())
   (invoicetaxbreakdown
    :initarg :invoicetaxbreakdown
    :accessor invoicetaxbreakdown
    :initform nil)
   (invoiceproducts
    :initarg :invoiceproducts
    :accessor invoiceproducts
    :initform '())))

;; ViewModel：渲染层使用的字段集（不含 row-id / context-id 等内部字段）
(defclass InvoiceHeaderViewModel (ViewModel)
  ((invnum
    :initarg :invnum
    :accessor invnum)
   (invdate
    :initarg :invdate
    :accessor invdate)
   (context-id
    :initarg :context-id
    :accessor context-id)
   (customer
    :initarg :customer
    :accessor customer)
   (vendor
    :initarg :vendor
    :accessor vendor)
   (custname
    :initarg :custname
    :accessor custname)
   (custaddr
    :initarg :custaddr
    :accessor custaddr)
   (custgstin
    :initarg :custgstin
    :accessor custgstin)
   (statecode
    :initarg :statecode
    :accessor statecode)
   (billaddr
    :initarg :billaddr
    :accessor billaddr)
   (shipaddr
    :initarg :shipaddr
    :accessor shipaddr)
   (placeofsupply
    :initarg :placeofsupply
    :accessor placeofsupply)
   (revcharge
    :initarg :revcharge
    :accessor revcharge)
   (transmode
    :initarg :transmode
    :accessor transmode)
   (vnum
    :initarg :vnum
    :accessor vnum)
   (totalvalue
    :initarg :totalvalue
    :accessor totalvalue)
   (totalinwords
    :initarg :totalinwords
    :accessor totalinwords)
   (bankaccnum
    :initarg :bankaccnum
    :accessor bankaccnum)
   (bankifsccode
    :initarg :bankifsccode
    :accessor bankifsccode)
   (tnc
    :initarg :tnc
    :accessor tnc)
   (authsign
    :initarg :authsign
    :accessor authsign)
   (finyear
    :initarg :finyear
    :accessor finyear)
   (user-id
    :initarg :user-id
    :accessor user-id)
   (created
    :initarg :created
    :accessor created)
   (updated
    :initarg :updated
    :accessor updated)
   (deleted-state
    :initarg :deleted-state
    :accessor deleted-state)
   (external-url
    :initarg :external-url
    :accessor external-url)
   (status
    :initarg :status
    :accessor status)
   (company
    :initarg :company
    :accessor company)))

;; ResponseModel：Service 输出给 Presenter 的字段集（与 ViewModel 同构）
(defclass InvoiceHeaderResponseModel (ResponseModel)
  ((invnum
    :initarg :invnum
    :accessor invnum)
   (invdate
    :initarg :invdate
    :accessor invdate)
   (context-id
    :initarg :context-id
    :accessor context-id)
    (custname
    :initarg :custname
    :accessor custname)
   (custaddr
    :initarg :custaddr
    :accessor custaddr)
   (custgstin
    :initarg :custgstin
    :accessor custgstin)
   (statecode
    :initarg :statecode
    :accessor statecode)
   (billaddr
    :initarg :billaddr
    :accessor billaddr)
   (shipaddr
    :initarg :shipaddr
    :accessor shipaddr)
   (placeofsupply
    :initarg :placeofsupply
    :accessor placeofsupply)
   (revcharge
    :initarg :revcharge
    :accessor revcharge)
   (transmode
    :initarg :transmode
    :accessor transmode)
   (vnum
    :initarg :vnum
    :accessor vnum)
   (totalvalue
    :initarg :totalvalue
    :accessor totalvalue)
   (totalinwords
    :initarg :totalinwords
    :accessor totalinwords)
   (bankaccnum
    :initarg :bankaccnum
    :accessor bankaccnum)
   (bankifsccode
    :initarg :bankifsccode
    :accessor bankifsccode)
   (tnc
    :initarg :tnc
    :accessor tnc)
   (authsign
    :initarg :authsign
    :accessor authsign)
   (finyear
    :initarg :finyear
    :accessor finyear)
   (user-id
    :initarg :user-id
    :accessor user-id)
   (created
    :initarg :created
    :accessor created)
   (updated
    :initarg :updated
    :accessor updated)
   (status
    :initarg :status
    :accessor status)
   (deleted-state
    :initarg :deleted-state
    :accessor deleted-state)
   (external-url
    :initarg :external-url
    :accessor external-url)
   (last-viewed-by-user-id
    :initarg :last-viewed-by-user-id
    :accessor last-viewed-by-user-id)
   (last-viewed-at
    :initarg :last-viewed-at
    :accessor last-viewed-at)
   (e-invoice-required
    :initarg :e-invoice-required
    :accessor e-invoice-required)
   (irn
    :initarg :irn
    :accessor irn)
   (irn-date
    :initarg :irn-date
    :accessor irn-date)
   (ack-number
    :initarg :ack-number
    :accessor ack-number)
   (ack-date
    :initarg :ack-date
    :accessor ack-date)
   (qr-code-path
    :initarg :qr-code-path
    :accessor qr-code-path)
   (uploaded-to-gstn
    :initarg :uploaded-to-gstn
    :accessor uploaded-to-gstn)
   (gstn-upload-date
    :initarg :gstn-upload-date
    :accessor gstn-upload-date)
   (gstr1-period
    :initarg :gstr1-period
    :accessor gstr1-period)
   (in-gstr2b
    :initarg :in-gstr2b
    :accessor in-gstr2b)
   (gstr2b-match-status
    :initarg :gstr2b-match-status
    :accessor gstr2b-match-status)
   (gstr2b-verified-date
    :initarg :gstr2b-verified-date
    :accessor gstr2b-verified-date)
   (itc-eligible
    :initarg :itc-eligible
    :accessor itc-eligible)
   (itc-claimed
    :initarg :itc-claimed
    :accessor itc-claimed)
   (itc-claim-month
    :initarg :itc-claim-month
    :accessor itc-claim-month)
   (itc-amount
    :initarg :itc-amount
    :accessor itc-amount)
   (advance-adjusted
    :initarg :advance-adjusted
    :accessor advance-adjusted)
   (payment-allocated
    :initarg :payment-allocated
    :accessor payment-allocated)
   (total-allocated
    :initarg :total-allocated
    :accessor total-allocated)
   (total-tds-deducted
    :initarg :total-tds-deducted
    :accessor total-tds-deducted)
   (balance-due
    :initarg :balance-due
    :accessor balance-due)
   (advance-gst-reversed
    :initarg :advance-gst-reversed
    :accessor advance-gst-reversed)
   (payment-status
    :initarg :payment-status
    :accessor payment-status)
   (rcm-paid
    :initarg :rcm-paid
    :accessor rcm-paid)
   (rcm-paid-date
    :initarg :rcm-paid-date
    :accessor rcm-paid-date)
   ;; Merged slots
   (customer
    :initarg :customer
    :accessor customer)
   (vendor
    :initarg :vendor
    :accessor vendor)
   (company
    :initarg :company
    :accessor company)))
   

;; RequestModel：控制器封装入参后传给 Adapter（含 context-id / custid / custname 等创建用字段）
(defclass InvoiceHeaderRequestModel (RequestModel)
  ((invnum
    :initarg :invnum
    :accessor invnum)
   (invdate
    :initarg :invdate
    :accessor invdate)
   (context-id
    :initarg :context-id
    :accessor context-id)
   (custid
    :initarg :custid
    :accessor custid)
   (vendor-id
    :initarg :vendor-id
    :accessor vendor-id)
   (custname
    :initarg :custname
    :accessor custname)
   (customer
    :initarg :customer
    :accessor customer)
   (custaddr
    :initarg :custaddr
    :accessor custaddr)
   (custgstin
    :initarg :custgstin
    :accessor custgstin)
   (statecode
    :initarg :statecode
    :accessor statecode)
   (billaddr
    :initarg :billaddr
    :accessor billaddr)
   (shipaddr
    :initarg :shipaddr
    :accessor shipaddr)
   (placeofsupply
    :initarg :placeofsupply
    :accessor placeofsupply)
   (revcharge
    :initarg :revcharge
    :accessor revcharge)
   (transmode
    :initarg :transmode
    :accessor transmode)
   (vnum
    :initarg :vnum
    :accessor vnum)
   (totalvalue
    :initarg :totalvalue
    :accessor totalvalue)
   (totalinwords
    :initarg :totalinwords
    :accessor totalinwords)
   (bankaccnum
    :initarg :bankaccnum
    :accessor bankaccnum)
   (bankifsccode
    :initarg :bankifsccode
    :accessor bankifsccode)
   (tnc
    :initarg :tnc
    :accessor tnc)
   (authsign
    :initarg :authsign
    :accessor authsign)
   (finyear
    :initarg :finyear
    :accessor finyear)
   (user-id
    :initarg :user-id
    :accessor user-id)
   (status
    :initarg :status
    :accessor status)
   (tenant-id
    :initarg :tenant-id
    :accessor tenant-id)
   (external-url
    :initarg :external-url
    :accessor external-url)
   (last-viewed-by-user-id
    :initarg :last-viewed-by-user-id
    :accessor last-viewed-by-user-id)
   (last-viewed-at
    :initarg :last-viewed-at
    :accessor last-viewed-at)
   (e-invoice-required
    :initarg :e-invoice-required
    :accessor e-invoice-required)
   (irn
    :initarg :irn
    :accessor irn)
   (irn-date
    :initarg :irn-date
    :accessor irn-date)
   (ack-number
    :initarg :ack-number
    :accessor ack-number)
   (ack-date
    :initarg :ack-date
    :accessor ack-date)
   (qr-code-path
    :initarg :qr-code-path
    :accessor qr-code-path)
   (uploaded-to-gstn
    :initarg :uploaded-to-gstn
    :accessor uploaded-to-gstn)
   (gstn-upload-date
    :initarg :gstn-upload-date
    :accessor gstn-upload-date)
   (gstr1-period
    :initarg :gstr1-period
    :accessor gstr1-period)
   (in-gstr2b
    :initarg :in-gstr2b
    :accessor in-gstr2b)
   (gstr2b-match-status
    :initarg :gstr2b-match-status
    :accessor gstr2b-match-status)
   (gstr2b-verified-date
    :initarg :gstr2b-verified-date
    :accessor gstr2b-verified-date)
   (itc-eligible
    :initarg :itc-eligible
    :accessor itc-eligible)
   (itc-claimed
    :initarg :itc-claimed
    :accessor itc-claimed)
   (itc-claim-month
    :initarg :itc-claim-month
    :accessor itc-claim-month)
   (itc-amount
    :initarg :itc-amount
    :accessor itc-amount)
   (advance-adjusted
    :initarg :advance-adjusted
    :accessor advance-adjusted)
   (payment-allocated
    :initarg :payment-allocated
    :accessor payment-allocated)
   (total-allocated
    :initarg :total-allocated
    :accessor total-allocated)
   (total-tds-deducted
    :initarg :total-tds-deducted
    :accessor total-tds-deducted)
   (balance-due
    :initarg :balance-due
    :accessor balance-due)
   (advance-gst-reversed
    :initarg :advance-gst-reversed
    :accessor advance-gst-reversed)
   (payment-status
    :initarg :payment-status
    :accessor payment-status)
   (rcm-paid
    :initarg :rcm-paid
    :accessor rcm-paid)
   (rcm-paid-date
    :initarg :rcm-paid-date
    :accessor rcm-paid-date)
   ;; Merged slots
   (vendor
    :initarg :vendor
    :accessor vendor)
   (company
    :initarg :company
    :accessor company)))


;; 搜索专用 RequestModel
(defclass InvoiceHeaderSearchRequestModel (InvoiceHeaderRequestModel)
  ())

;; 按 context-id 读取专用 RequestModel（用于幂等取发票）
(defclass InvoiceHeaderContextIDRequestModel (InvoiceHeaderRequestModel)
  ())

;; 按 status 过滤专用 RequestModel（用于状态切换 UI）
(defclass InvoiceHeaderStatusRequestModel (InvoiceHeaderRequestModel)
  ())

;; 领域对象 InvoiceHeader：携带默认值 status='DRAFT'，invdate=今天，金额=0
(defclass InvoiceHeader (BusinessObject)
  ((row-id)
   (invnum
    :initarg :invnum
    :initform "000"
    :accessor invnum)
   (invdate
    :initarg :invdate
    :initform (clsql-sys::get-date)
    :accessor invdate)
   (context-id
    :initarg :context-id
    :accessor context-id)
   (custid
    :initarg :custid
    :accessor custid)
   (vendor-id
    :initarg :vendor-id
    :accessor vendor-id)
   (custname
    :initarg :custname
    :initform ""
    :accessor custname)
   (custaddr
    :initarg :custaddr
    :initform ""
    :accessor custaddr)
   (custgstin
    :initarg :custgstin
    :initform ""
    :accessor custgstin)
   (statecode
    :initarg :statecode
    :initform ""
    :accessor statecode)
   (billaddr
    :initarg :billaddr
    :initform ""
    :accessor billaddr)
   (shipaddr
    :initarg :shipaddr
    :initform ""
    :accessor shipaddr)
   (placeofsupply
    :initarg :placeofsupply
    :initform ""
    :accessor placeofsupply)
   (revcharge
    :initarg :revcharge
    :initform ""
    :accessor revcharge)
   (transmode
    :initarg :transmode
    :initform ""
    :accessor transmode)
   (vnum
    :initarg :vnum
    :initform ""
    :accessor vnum)
   (totalvalue
    :initarg :totalvalue
    :initform 0.00
    :accessor totalvalue)
   (totalinwords
    :initarg :totalinwords
    :initform ""
    :accessor totalinwords)
   (bankaccnum
    :initarg :bankaccnum
    :initform ""
    :accessor bankaccnum)
   (bankifsccode
    :initarg :bankifsccode
    :initform ""
    :accessor bankifsccode)
   (tnc
    :initarg :tnc
    :initform ""
    :accessor tnc)
   (authsign
    :initarg :authsign
    :initform ""
    :accessor authsign)
   (finyear
    :initarg :finyear
    :initform ""
    :accessor finyear)
   (user-id
    :initarg :user-id
    :accessor user-id)
   (created
    :initarg :created
    :accessor created)
   (updated
    :initarg :updated
    :accessor updated)
   (status
    :initarg :status
    :initform "DRAFT"
    :accessor status)
   (deleted-state
    :initarg :deleted-state
    :initform "N"
    :accessor deleted-state)
   (tenant-id
    :initarg :tenant-id
    :accessor tenant-id)
   (external-url
    :initarg :external-url
    :accessor external-url)
   (last-viewed-by-user-id
    :initarg :last-viewed-by-user-id
    :accessor last-viewed-by-user-id)
   (last-viewed-at
    :initarg :last-viewed-at
    :accessor last-viewed-at)
   (e-invoice-required
    :initarg :e-invoice-required
    :accessor e-invoice-required)
   (irn
    :initarg :irn
    :accessor irn)
   (irn-date
    :initarg :irn-date
    :accessor irn-date)
   (ack-number
    :initarg :ack-number
    :accessor ack-number)
   (ack-date
    :initarg :ack-date
    :accessor ack-date)
   (qr-code-path
    :initarg :qr-code-path
    :accessor qr-code-path)
   (uploaded-to-gstn
    :initarg :uploaded-to-gstn
    :accessor uploaded-to-gstn)
   (gstn-upload-date
    :initarg :gstn-upload-date
    :accessor gstn-upload-date)
   (gstr1-period
    :initarg :gstr1-period
    :accessor gstr1-period)
   (in-gstr2b
    :initarg :in-gstr2b
    :accessor in-gstr2b)
   (gstr2b-match-status
    :initarg :gstr2b-match-status
    :accessor gstr2b-match-status)
   (gstr2b-verified-date
    :initarg :gstr2b-verified-date
    :accessor gstr2b-verified-date)
   (itc-eligible
    :initarg :itc-eligible
    :accessor itc-eligible)
   (itc-claimed
    :initarg :itc-claimed
    :accessor itc-claimed)
   (itc-claim-month
    :initarg :itc-claim-month
    :accessor itc-claim-month)
   (itc-amount
    :initarg :itc-amount
    :accessor itc-amount)
   (advance-adjusted
    :initarg :advance-adjusted
    :accessor advance-adjusted)
   (payment-allocated
    :initarg :payment-allocated
    :accessor payment-allocated)
   (total-allocated
    :initarg :total-allocated
    :accessor total-allocated)
   (total-tds-deducted
    :initarg :total-tds-deducted
    :accessor total-tds-deducted)
   (balance-due
    :initarg :balance-due
    :accessor balance-due)
   (advance-gst-reversed
    :initarg :advance-gst-reversed
    :accessor advance-gst-reversed)
   (payment-status
    :initarg :payment-status
    :accessor payment-status)
   (rcm-paid
    :initarg :rcm-paid
    :accessor rcm-paid)
   (rcm-paid-date
    :initarg :rcm-paid-date
    :accessor rcm-paid-date)
   ;; Merged slots
   (customer
    :initarg :customer
    :initform ""
    :accessor customer)
   (vendor
    :initarg :vendor
    :accessor vendor)
   (company
    :initarg :company
    :accessor company)))


;; ----------------------------------------------------------------------------
;; 实体：dod-Invoice-Header
;; 表：DOD_INVOICE_HEADER
;; 含义：发票主单。一张发票包含多条 dod-invoice-items。
;; 关键字段：
;;   row-id           主键
;;   context-id       业务上下文键（用于幂等创建/查询）
;;   invnum           发票号（人类可见）
;;   invdate          发票开具日
;;   custid + custname / custaddr / custgstin  客户字段快照
;;   vendor-id (→ dod-vend-profile)            开票卖家
;;   statecode        卖家州代码（GST 计算用）
;;   billaddr / shipaddr                      账单地址 / 收货地址
;;   placeofsupply    供应地（GST 计算用，与 statecode 比较判断 intra/interstate）
;;   revcharge        反向计税标志
;;   transmode        运输方式
;;   vnum             车辆号（运输文档）
;;   totalvalue       发票总额
;;   totalinwords     金额大写
;;   bankaccnum / bankifsccode                收款银行信息
;;   tnc / authsign                           条款 / 授权签章
;;   finyear          财年（如 '2024-2025'）
;;   external-url     外部链接（推测：LiveLink / 公开预览）
;;   status           发票状态（DRAFT/PAID/CANCELLED/REFUNDED 等）
;;   deleted-state    N/Y 软删
;;   last-viewed-by-user-id / last-viewed-at  最后查看记录
;;   updated          最后更新时间（默认当前 wall-time）
;;   tenant-id        多租户隔离 → dod-company.row-id
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-Invoice-Header ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)
   (invnum
    :initarg :invnum
    :type (string 50)
    :accessor invnum)
   (invdate
    :type clsql:date
    :initarg :invdate
    :accessor invdate)
   (context-id
    :initarg :context-id
    :type (string 100)
    :accessor context-id)
   (custid
    :initarg :custid
    :type integer
    :accessor custid)
   (vendor-id
    :initarg :vendor-id
    :type integer
    :accessor vendor-id)
   (custname
    :initarg :custname
    :type (string 255)
    :accessor custname)
   (custaddr
    :initarg :custaddr
    :type string
    :accessor custaddr)
   (custgstin
    :initarg :custgstin
    :type (string 15)
    :accessor custgstin)
   (statecode
    :initarg :statecode
    :type (string 2)
    :accessor statecode)
   (billaddr
    :initarg :billaddr
    :type string
    :accessor billaddr)
   (shipaddr
    :initarg :shipaddr
    :type string
    :accessor shipaddr)
   (placeofsupply
    :initarg :placeofsupply
    :type (string 50)
    :accessor placeofsupply)
   (revcharge
    :initarg :revcharge
    :type (string 3)
    :accessor revcharge)
   (transmode
    :initarg :transmode
    :type (string 50)
    :accessor transmode)
   (vnum
    :initarg :vnum
    :type (string 20)
    :accessor vnum)
   (totalvalue
    :initarg :totalvalue
    :type float
    :accessor totalvalue)
   (totalinwords
    :initarg :totalinwords
    :type (string 255)
    :accessor totalinwords)
   (bankaccnum
    :initarg :bankaccnum
    :type (string 20)
    :accessor bankaccnum)
   (bankifsccode
    :initarg :bankifsccode
    :type (string 11)
    :accessor bankifsccode)
   (tnc
    :initarg :tnc
    :type string
    :accessor tnc)
   (authsign
    :initarg :authsign
    :type (string 100)
    :accessor authsign)
   (finyear
    :initarg :finyear
    :type (string 9)
    :accessor finyear)
   (user-id
    :initarg :user-id
    :type integer
    :accessor user-id)
   (created
    :initarg :created
    :type clsql:wall-time
    :accessor created)
   (updated
    :type clsql:wall-time
    :initarg :updated
    :void-value (clsql:get-time)
    :accessor updated)
   (status
    :initarg :status
    :type (string 20)
    :accessor status)
   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state
    :accessor deleted-state)
   (tenant-id
    :initarg :tenant-id
    :type integer
    :accessor tenant-id)
   (external-url
    :initarg :external-url
    :type (string 2048)
    :accessor external-url)
   (last-viewed-by-user-id
    :initarg :last-viewed-by-user-id
    :type integer
    :accessor last-viewed-by-user-id)
   (last-viewed-at
    :initarg :last-viewed-at
    :type clsql:wall-time
    :accessor last-viewed-at)
   (e-invoice-required
    :initarg :e-invoice-required
    :type integer
    :accessor e-invoice-required)
   (irn
    :initarg :irn
    :type (string 64)
    :accessor irn)
   (irn-date
    :initarg :irn-date
    :type clsql:wall-time
    :accessor irn-date)
   (ack-number
    :initarg :ack-number
    :type (string 20)
    :accessor ack-number)
   (ack-date
    :initarg :ack-date
    :type clsql:wall-time
    :accessor ack-date)
   (qr-code-path
    :initarg :qr-code-path
    :type (string 500)
    :accessor qr-code-path)
   (uploaded-to-gstn
    :initarg :uploaded-to-gstn
    :type integer
    :accessor uploaded-to-gstn)
   (gstn-upload-date
    :initarg :gstn-upload-date
    :type clsql:wall-time
    :accessor gstn-upload-date)
   (gstr1-period
    :initarg :gstr1-period
    :type (string 7)
    :accessor gstr1-period)
   (in-gstr2b
    :initarg :in-gstr2b
    :type integer
    :accessor in-gstr2b)
   (gstr2b-match-status
    :initarg :gstr2b-match-status
    :type (string 20)
    :accessor gstr2b-match-status)
   (gstr2b-verified-date
    :initarg :gstr2b-verified-date
    :type clsql:date
    :accessor gstr2b-verified-date)
   (itc-eligible
    :initarg :itc-eligible
    :type integer
    :accessor itc-eligible)
   (itc-claimed
    :initarg :itc-claimed
    :type integer
    :accessor itc-claimed)
   (itc-claim-month
    :initarg :itc-claim-month
    :type (string 7)
    :accessor itc-claim-month)
   (itc-amount
    :initarg :itc-amount
    :type float
    :accessor itc-amount)
   (advance-adjusted
    :initarg :advance-adjusted
    :type float
    :accessor advance-adjusted)
   (payment-allocated
    :initarg :payment-allocated
    :type float
    :accessor payment-allocated)
   (total-allocated
    :initarg :total-allocated
    :type float
    :accessor total-allocated)
   (total-tds-deducted
    :initarg :total-tds-deducted
    :type float
    :accessor total-tds-deducted)
   (balance-due
    :initarg :balance-due
    :type float
    :accessor balance-due)
   (advance-gst-reversed
    :initarg :advance-gst-reversed
    :type float
    :accessor advance-gst-reversed)
   (payment-status
    :initarg :payment-status
    :type (string 20)
    :accessor payment-status)
   (rcm-paid
    :initarg :rcm-paid
    :type integer
    :accessor rcm-paid)
   (rcm-paid-date
    :initarg :rcm-paid-date
    :type clsql:date
    :accessor rcm-paid-date)
   ;; Merged joins
   (customer
    :ACCESSOR get-customer
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-cust-profile
                          :HOME-KEY custid
                          :FOREIGN-KEY row-id
                          :SET NIL))
   (vendorobject
    :accessor odt-vendorobject
    :db-kind :join
    :db-info (:join-class dod-vend-profile
                          :home-key vendor-id
                          :foreign-key row-id
                          :set nil))
   (COMPANY
    :ACCESSOR get-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
                          :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET NIL)))
  (:BASE-TABLE dod_invoice_header))
