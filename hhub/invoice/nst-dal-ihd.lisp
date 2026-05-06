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
   (customer
    :initarg :customer
    :accessor customer)
   (vendor
    :initarg :vendor
    :accessor vendor)
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
   (customer
    :initarg :customer
    :accessor customer)
   (vendor
    :initarg :vendor
    :accessor vendor)
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
   (external-url
    :initarg :external-url
    :accessor external-url)
   (status
    :initarg :status
    :accessor status)
   (company
    :initarg :company
    :accessor company)))
   

;; RequestModel：控制器封装入参后传给 Adapter（含 context-id / custid / custname 等创建用字段）
(defclass InvoiceHeaderRequestModel (RequestModel)
  ((invnum
    :initarg :invnum
    :accessor invnum)
   (context-id
    :initarg :context-id
    :accessor context-id)
   (invdate
    :initarg :invdate
    :accessor invdate)
   (custid
    :initarg :custid
    :accessor custid)
   (custname
    :initarg :custname
    :accessor custname)
   (customer
    :initarg :customer
    :accessor customer)
   (vendor
    :initarg :vendor
    :accessor vendor)
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
   (external-url
    :initarg :external-url
    :accessor external-url)
   (status
    :initarg :status
    :accessor status)
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
   (context-id
    :initarg :context-id
    :accessor context-id)
   (invnum
    :initarg :invnum
    :initform "000"
    :accessor invnum)
   (invdate
    :initarg :invdate
    :initform (clsql-sys::get-date)
    :accessor invdate)
   (customer
    :initarg :customer
    :initform ""
    :accessor customer)
   (vendor
    :initarg :vendor
    :accessor vendor)
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
   (external-url
    :initarg :external-url
    :accessor external-url)
   (status
    :initarg :status
    :initform "DRAFT"
    :accessor status)
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
   (context-id
    :initarg :context-id
    :type (string 100)
    :accessor context-id)
   (invnum
    :initarg :invnum
    :type (string 50)
    :accessor invnum)
   (invdate
    :type clsql:date
    :initarg :invdate
    :accessor invdate)
   (custid
    :type integer
    :initarg :custid
    :accessor custid)
   (customer
    :ACCESSOR get-customer
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-cust-profile
	                  :HOME-KEY custid
                          :FOREIGN-KEY row-id
                          :SET NIL))
   
   (vendor-id
    :db-constraints :NOT-NULL
    :type integer
    :initarg :vendor-id)
   
   (vendorobject
    :accessor odt-vendorobject
    :db-kind :join
    :db-info (:join-class dod-vend-profile
			  :home-key vendor-id
			  :foreign-key row-id
			  :set nil))
   
   (custname
    :type (string 255)
    :initarg :custname
    :accessor custname)
   (custaddr
    :type (string 500)
    :initarg :custaddr
    :accessor custaddr)
   (custgstin
    :type (string 15)
    :initarg :custgstin
    :accessor custgstin)
   (statecode
    :type (string 2)
    :initarg :statecode
    :accessor statecode)
   (billaddr
    :type (string 500)
    :initarg :billaddr
    :accessor billaddr)
   (shipaddr
    :type (string 500)
    :initarg :shipaddr
    :accessor shipaddr)
   (placeofsupply
    :type (string 50)
    :initarg :placeofsupply
    :accessor placeofsupply)
   (revcharge
    :type (string 3)
    :initarg :revcharge
    :accessor revcharge)
   (transmode
    :type (string 50)
    :initarg :transmode
    :accessor transmode)
   (vnum
    :type (string 20)
    :initarg :vnum
    :accessor vnum)
   (totalvalue
    :type float
    :initarg :totalvalue
    :accessor totalvalue)
   (totalinwords
    :type (string 255)
    :initarg :totalinwords
    :accessor totalinwords)
   (bankaccnum
    :type (string 20)
    :initarg :bankaccnum
    :accessor bankaccnum)
   (bankifsccode
    :type (string 11)
    :initarg :bankifsccode
    :accessor bankifsccode)
   (tnc
    :type (string 500)
    :initarg :tnc
    :accessor tnc)
   (authsign
    :type (string 100)
    :initarg :authsign
    :accessor authsign)

   (finyear
    :type (string 9)
    :initarg :finyear
    :accessor finyear)
   (external-url
    :type (string 512)
    :initarg :external-url
    :accessor external-url)
   (status
    :type (string 20)
    :initarg :status
    :accessor status)
   
   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state) 
   (last-viewed-by-user-id
    :type integer
    :initarg :last-viewed-by-user-id)
   (last-viewed-at
    :type clsql:wall-time
    :initarg :last-viewed-at)
   (updated
    :type clsql:wall-time
    :initarg :updated
    :void-value (clsql:get-time))
   
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
  (:BASE-TABLE dod_invoice_header))
