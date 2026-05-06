;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：upi UPI 收款
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/upi/dod-dal-upi.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：UPI（Unified Payments Interface，印度统一支付接口）模块的数据模型。
;;;;       本文件采用项目较新的"DDD/六边形"风格分层：除了 view-class，还预先
;;;;       声明了 Adapter / DBService / Presenter / Service / View / ViewModel /
;;;;       RequestModel / ResponseModel / BusinessObject 等占位 class，BL 层在
;;;;       这些 class 上派发 generic methods。
;;;;
;;;; 主要导出：
;;;;   UpiPaymentsAdapter / UpiPaymentsDBService / UpiPaymentsPresenter /
;;;;   UpiPaymentsService / UpiPaymentsHTMLView          — 服务/视图占位
;;;;   UpiPaymentsViewModel / UpiPaymentsResponseModel / UpiPaymentsRequestModel
;;;;                                                     — DTO（含 vendor/customer/
;;;;                                                       amount/utrnum/status/
;;;;                                                       vendorconfirm/phone/...）
;;;;   UpiPayment                                       — 内存业务对象
;;;;   dod-upi-payments                                 — 持久化 view-class，
;;;;                                                       表 DOD_UPI_PAYMENTS
;;;;
;;;; 关联：
;;;;   上游使用方：upi/dod-bl-upi.lisp（业务）、upi/dod-ui-upi.lisp（控制器/UI）
;;;;   下游依赖：core 的 AdapterService / DBAdapterService / PresenterService /
;;;;             BusinessService / HTMLView / ViewModel / RequestModel /
;;;;             ResponseModel / BusinessObject 抽象基类，
;;;;             dod-vend-profile / dod-cust-profile / dod-company
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


;; ----------------------------------------------------------------------------
;; 服务/视图层占位类（六边形分层标记）
;; ----------------------------------------------------------------------------

(defclass UpiPaymentsAdapter (AdapterService)
  ())

(defclass UpiPaymentsDBService (DBAdapterService)
  ())

(defclass UpiPaymentsPresenter (PresenterService)
  ())

(defclass UpiPaymentsService (BusinessService)
  ())
(defclass UpiPaymentsHTMLView (HTMLView)
  ())

;; ----------------------------------------------------------------------------
;; DTO：UpiPaymentsViewModel
;; 含义：Presenter 渲染前的视图模型（实例字段已脱离持久层）。
;; 字段：vendor / customer / amount / utrnum / transaction-id / status /
;;       vendorconfirm / created / phone / company。
;; ----------------------------------------------------------------------------
(defclass UpiPaymentsViewModel (ViewModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)
   (customer
    :initarg :customer
    :accessor customer)
   (amount
    :initarg :amount
    :accessor amount)
   (utrnum
    :initarg :utrnum
    :accessor utrnum)
   (transaction-id
    :initarg :transaction-id
    :accessor transaction-id)
   (status
    :initarg :status
    :accessor status)
   (vendorconfirm
    :initarg :vendorconfirm
    :accessor vendorconfirm)
   (created
    :initarg :created
    :accessor created)
   (phone
    :initarg :phone
    :accessor phone)
   (company
    :initarg :company
    :accessor company)))
  
;; ----------------------------------------------------------------------------
;; DTO：UpiPaymentsResponseModel
;; 含义：BL/Service 层向 UI 返回的响应模型。字段同 ViewModel，但用途偏对外。
;; 注：created slot 的 :accessor 写成 :created（带冒号），与其它 slot 形成对比；
;;    推测为代码笔误，实际效果是把 :created 当作 keyword 注册为 reader。
;; ----------------------------------------------------------------------------
(defclass UpiPaymentsResponseModel (ResponseModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)
   (customer
    :initarg :customer
    :accessor customer)
   (amount
    :initarg :amount
    :accessor amount)
   (utrnum
    :initarg :utrnum
    :accessor utrnum)
   (transaction-id
    :initarg :transaction-id
    :accessor transaction-id)
   (status
    :initarg :status
    :accessor status)
   (vendorconfirm
    :initarg :vendorconfirm
    :accessor vendorconfirm)
   (created
    :accessor :created
    :initarg :created)
   (phone
    :initarg :phone
    :accessor phone)
  
   (company
    :initarg :company
    :accessor company)))


;; ----------------------------------------------------------------------------
;; DTO：UpiPaymentsRequestModel
;; 含义：UI/控制器接收外部请求时的输入模型。比 ResponseModel 多一个
;;       paymentconfirm 标志（推测：客户在前端确认已付款）。
;; ----------------------------------------------------------------------------
(defclass UpiPaymentsRequestModel (RequestModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)
   (customer
    :initarg :customer
    :accessor customer)
   (amount
    :initarg :amount
    :accessor amount)
   (utrnum
    :initarg :utrnum
    :accessor utrnum)
   (transaction-id
    :initarg :transaction-id
    :accessor transaction-id)
   (status
    :initarg :status
    :accessor status)
    (vendorconfirm
    :initarg :vendorconfirm
    :accessor vendorconfirm)
   (phone
    :initarg :phone
    :accessor phone)
   (paymentconfirm
    :initarg :paymentconfirm
    :accessor paymentconfirm)

   (company
    :initarg :company
    :accessor company)))

;; ----------------------------------------------------------------------------
;; DTO：UpiPayment
;; 含义：UPI 支付的内存域对象（BusinessObject 子类）。BL 层多用此对象传递。
;; ----------------------------------------------------------------------------
(defclass UpiPayment (BusinessObject)
  ((row-id)
   (transaction-id
    :initarg :transaction-id
    :accessor transaction-id)
   (amount
    :accessor amount 
    :initarg :amount)
   (status
    :initarg :status
    :accessor status)
   (utrnum
    :initarg :utrnum
    :accessor utrnum)
   (customer
    :accessor customer
    :initarg :customer)
   (vendor
   :accessor vendor 
   :initarg :vendor)
   (vendorconfirm
    :initarg :vendorconfirm
    :accessor vendorconfirm)
   (company
    :accessor company
    :initarg :company)
   (phone
    :initarg :phone
    :accessor phone)
  
   (created
    :accessor created)
   (deleted-state
    :accessor deleted-state
    :initarg :deleted-state)))




;; ----------------------------------------------------------------------------
;; 实体：dod-upi-payments
;; 表：DOD_UPI_PAYMENTS
;; 含义：UPI 收款流水。客户经 UPI 转账后，本表登记一条待 vendor 确认的记录。
;;       外部 UPI 应用回调或 vendor 在后台手动核对 utrnum，将 vendorconfirm
;;       置 'Y' 表示款已到账。
;; 关键字段：
;;   row-id           主键
;;   transaction-id   平台内交易号（NOT NULL，string 20）
;;   vendor-id        收款卖家 → dod-vend-profile
;;   cust-id          付款客户 → dod-cust-profile
;;   amount           交易金额
;;   status           状态码（string 3，推测 PEN/CMP/CAN）
;;   utrnum           UPI 银行流水号 UTR（客户填）
;;   vendorconfirm    Y/N 卖家是否已确认到账
;;   phone            付款手机号（用于核对）
;;   created          创建日期
;;   tenant-id        多租户键 → dod-company
;;   deleted-state    N/Y 软删
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-upi-payments ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (transaction-id
    :accessor transaction-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 20)
    :INITARG :transaction-id)
   (vendor-id
    :ACCESSOR vendor-id
    :type integer
    :initarg :vendor-id)

   (vendor
    :ACCESSOR get-vendor
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-vend-profile
	                  :HOME-KEY vendor-id
                          :FOREIGN-KEY row-id
                          :SET nil))
   (cust-id
    :accessor cust-id
    :type integer
    :initarg :cust-id)
  
   (customer
    :ACCESSOR get-customer
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-cust-profile
	                  :HOME-KEY cust-id
                          :FOREIGN-KEY row-id
                          :SET nil))

   (amount
    :type float
    :initarg :amount)
   (status
    :type (string 3)
    :initarg :status)
   (utrnum
    :accessor utrnum
    :type (string 20))
   (vendorconfirm
    :type (string 1))

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state) 

   (phone
    :type (string 20)
    :initarg :phone
    :accessor phone)
  
   (created
    :accessor created
    :TYPE clsql:date)
   
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
 (:base-table dod_upi_payments))
