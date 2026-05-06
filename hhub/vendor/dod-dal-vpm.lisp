;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家支付方式开关（Vendor Payment Methods）
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/vendor/dod-dal-vpm.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 vendor 支付方式开关相关的服务/适配/视图/请求/响应/业务对象类，
;;;;       以及 CLSQL 实体 dod-vpayment-methods（DOD_VPAYMENT_METHODS）。
;;;;       VPaymentMethods 表示某 vendor 在某 tenant 下启用的付款方式集合：
;;;;       COD / UPI / 第三方支付网关 / 钱包 / 先用后付。
;;;;
;;;; 主要导出：
;;;;   dod-vpayment-methods            —— 数据库实体
;;;;   VPaymentMethods                 —— 业务对象
;;;;   VPaymentMethodsRequestModel / VPaymentMethodsResponseModel /
;;;;     VPaymentMethodsViewModel       —— DTO 三件套
;;;;   VPaymentMethodsAdapter / VPaymentMethodsPresenter /
;;;;     VPaymentMethodsService / VPaymentMethodsDBService /
;;;;     VPaymentMethodsHTMLView        —— 服务/适配/展示类
;;;;
;;;; 关联：
;;;;   上游使用方：vendor/dod-bl-vpm.lisp（CRUD）、vendor/dod-ui-ven.lisp 中
;;;;               vendor 设置页面控制器（推测）。
;;;;   下游依赖：vendor/dod-dal-ven.lisp、core 平台基础。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defclass VPaymentMethodsAdapter (AdapterService)
  ())

(defclass VPaymentMethodsDBService (DBAdapterService)
  ())

(defclass VPaymentMethodsPresenter (PresenterService)
  ())

(defclass VPaymentMethodsService (BusinessService)
  ())
(defclass VPaymentMethodsHTMLView (HTMLView)
  ())

(defclass VPaymentMethodsViewModel (ViewModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)))

(defclass VPaymentMethodsResponseModel (ResponseModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)
   (codenabled
    :initarg :codenabled
    :accessor codenabled)
   (upienabled
    :accessor upienabled
    :initarg :upienabled)
   (payprovidersenabled
    :accessor payprovidersenabled 
    :initarg :payprovidersenabled)
   (walletenabled 
    :accessor walletenabled
    :initarg :walletenabled)
   (paylaterenabled 
    :accessor paylaterenabled
    :initarg :paylaterenabled)
   (company
    :accessor company
    :initarg :company)
   (active-flag
    :accessor active-flag
    :initarg :active-flag)
   (deleted-state
    :accessor deleted-state
    :initarg :deleted-state)))

(defclass VPaymentMethodsRequestModel (RequestModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)
   (codenabled
    :initarg :codenabled
    :accessor codenabled)
   (upienabled
    :accessor upienabled
    :initarg :upienabled)
   (payprovidersenabled
    :accessor payprovidersenabled 
    :initarg :payprovidersenabled)
   (walletenabled 
    :accessor walletenabled
    :initarg :walletenabled)
   (paylaterenabled 
    :accessor paylaterenabled
    :initarg :paylaterenabled)
   (company
    :accessor company
    :initarg :company)
   (active-flag
    :accessor active-flag
    :initarg :active-flag)
   (deleted-state
    :accessor deleted-state
    :initarg :deleted-state)))


(defclass VPaymentMethods (BusinessObject)
  ((row-id)
   (vendor
    :initarg :vendor
    :accessor vendor)
   (codenabled
    :initarg :codenabled
    :accessor codenabled)
   (upienabled
    :accessor upienabled
    :initarg :upienabled)
   (payprovidersenabled
    :accessor payprovidersenabled 
    :initarg :payprovidersenabled)
   (walletenabled 
    :accessor walletenabled
    :initarg :walletenabled)
   (paylaterenabled 
    :accessor paylaterenabled
    :initarg :paylaterenabled)
   (company
    :accessor company
    :initarg :company)
   (active-flag
    :accessor active-flag
    :initarg :active-flag)
   (deleted-state
    :accessor deleted-state
    :initarg :deleted-state)))
   
  
;; DOD_VPAYMENT_METHODS
;; ----------------------------------------------------------------------------
;; 实体：dod-vpayment-methods
;; 表：DOD_VPAYMENT_METHODS
;; 含义：每行表示某 vendor 在某 tenant 下的支付方式开关组合。
;; 关键字段：
;;   row-id              主键
;;   vendor-id           外键 → dod-vend-profile（NOT NULL）
;;   codenabled          Y/N 是否启用 COD（货到付款）
;;   upienabled          Y/N 是否启用 UPI 收款
;;   payprovidersenabled Y/N 是否启用第三方支付网关
;;   walletenabled       Y/N 是否启用钱包扣款
;;   paylaterenabled     Y/N 是否启用先用后付
;;   active-flag         Y/N 启用标志
;;   deleted-state       N/Y 软删
;;   tenant-id           多租户隔离键
;; 备注：upienabled slot 的 :initarg 写成 :enabled（不是 :upienabled），
;;       推测原作者笔误，已存的代码大多通过 accessor 访问，故影响仅限 make-instance 直传。
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vpayment-methods ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (codenabled
    :accessor codenabled
    :type (string 1)
    :void-value "Y"
    :initarg :codenabled )
   (upienabled
    :accessor upienabled
    :type (string 1)
    :void-value "Y"
    :initarg :enabled )
   (payprovidersenabled
    :accessor payprovidersenabled 
    :type (string 1)
    :void-value "Y"
    :initarg :payprovidersenabled)
   (walletenabled
    :accessor walletenabled
    :type (string 1)
    :void-value "Y"
    :initarg :walletenabled )
   (paylaterenabled
    :accessor paylaterenabled
    :type (string 1)
    :void-value "Y"
    :initarg :paylaterenabled )

   (active-flag
    :accessor active-flag
    :type (string 1)
    :void-value "Y"
    :initarg :active-flag ) 

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)
   (vendor-id
    :accessor vendor-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer 
    :INITARG :vendor-id)
   (vendor
    :accessor get-vendor
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-vend-profile
	      :HOME-KEY vendor-id
	      :FOREIGN-KEY row-id)
    :SET NIL)
   
   (tenant-id 
    :type integer 
    :initarg :tenant-id))
   (:BASE-TABLE DOD_VPAYMENT_METHODS))


