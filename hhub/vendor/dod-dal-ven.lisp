;;; dod-dal-ven.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家档案（Vendor Profile）核心实体定义
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/vendor/dod-dal-ven.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 vendor 模块的：
;;;;       1) 服务/适配/视图模型 CLOS 占位类（VendorAdapter / VendorPresenter / ...）；
;;;;       2) Vendor / RequestVendor / ResponseVendor / VendorViewModel 等领域 + DTO；
;;;;       3) CLSQL 实体 dod-vend-profile（DOD_VEND_PROFILE）和
;;;;          dod-vendor-tenants（DOD_VENDOR_TENANTS，多租户绑定）；
;;;;       4) 通用方法签名 select-vendor-by-phone。
;;;;
;;;; 主要导出：
;;;;   dod-vend-profile / dod-vendor-tenants  —— 数据库实体
;;;;   Vendor / HHUBVendorTenants             —— 业务对象
;;;;   RequestVendor / ResponseVendor / VendorViewModel  —— DTO
;;;;   VendorAdapter / VendorPresenter / VendorProfileService /
;;;;     VendorApprovalService / VendorPushnotificationService /
;;;;     VendorDBService / VendorRepository                —— 服务/仓储类
;;;;   select-vendor-by-phone                  —— 泛函数（具体在 BL 实现）
;;;;
;;;; 关联：
;;;;   上游使用方：vendor/dod-bl-ven.lisp（CRUD、审批、密码重置等）、
;;;;               vendor/dod-ui-ven.lisp（控制器/视图）。
;;;;   下游依赖：account/dod-company（dod-company）、core 平台基础类
;;;;             （AdapterService、BusinessService、BusinessObject、ResponseModel...）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;;;;; Vendor Profile Update related classes
;; ----------------------------------------------------------------------------
;; 请求/响应/视图 DTO：HTTP 入参 → RequestVendor，业务输出 → ResponseVendor，
;; 渲染层 → VendorViewModel。VendorApproval* 是审批专用变体。
;; ----------------------------------------------------------------------------

(defclass RequestVendor (RequestModel)
  ((name)
   (address)
   (phone) 
   (email)
   (firstname)
   (lastname)
   (salutation)
   (title)
   (birthdate)
   (city)
   (state)
   (country)
   (zipcode)
   (gstnumber)
   (picture-path)
   (password)
   (salt)
   (payment-gateway-mode)
   (payment-api-key)
   (payment-api-salt)
   (push-notify-subs-flag)
   (email-add-verified)
   (legal-name)
   (trade-name)
   (pan-number)
   (gst-state-code)
   (gst-registration-type)
   (gst-filing-frequency)
   (company)))

(defclass RequestModelVendorApproval (RequestModel)
  ((vendor-id
    :initarg :vendor-id)
   (companyadmin
    :initarg :companyadmin)))


(defclass ResponseVendor (ResponseModel)
  ((name)
   (address)
   (phone) 
   (email)
   (firstname)
   (lastname)
   (salutation)
   (title)
   (birthdate)
   (city)
   (state)
   (country)
   (zipcode)
   (gstnumber)
   (picture-path)
   (password)
   (salt)
   (payment-gateway-mode)
   (payment-api-key)
   (payment-api-salt)
   (push-notify-subs-flag)
   (email-add-verified)
   (legal-name)
   (trade-name)
   (pan-number)
   (gst-state-code)
   (gst-registration-type)
   (gst-filing-frequency)
   (fy-start-month)
   (company)))
  
(defclass VendorViewModel (ViewModel)
  ((name)
   (address)
   (phone) 
   (email)
   (firstname)
   (lastname)
   (salutation)
   (title)
   (birthdate)
   (city)
   (state)
   (country)
   (zipcode)
   (gstnumber)
   (picture-path)
   (password)
   (salt)
   (payment-gateway-mode)
   (payment-api-key)
   (payment-api-salt)
   (push-notify-subs-flag)
   (email-add-verified)
   (legal-name)
   (trade-name)
   (pan-number)
   (gst-state-code)
   (gst-registration-type)
   (gst-filing-frequency)
   (fy-start-month)))
  

;; ----------------------------------------------------------------------------
;; vendor 服务/适配/展示类（占位 CLOS 类，方法在 dod-bl-ven.lisp 中分派）
;;   VendorAdapter           —— 处理 RequestVendor → BL 调用 → ResponseVendor 的适配器
;;   VendorApprovalAdapter   —— 卖家审批专用 Adapter
;;   VendorPresenter         —— 把 ResponseVendor 转 VendorViewModel
;;   VendorProfileService    —— 卖家档案 CRUD 业务服务
;;   VedorPasscodeService    —— 卖家密码/验证码服务（注：原文件类名拼写为 Vedor）
;;   VendorPushnotificationService —— 卖家推送服务
;;   VendorApprovalService   —— 卖家审批业务服务
;; ----------------------------------------------------------------------------
(defclass VendorAdapter (AdapterService)
  ())
(defclass VendorApprovalAdapter (AdapterService)
  ())

(defclass VendorPresenter (PresenterService)
  ())

(defclass VendorProfileService (BusinessService)
  ())
(defclass VedorPasscodeService (BusinessService)
  ())
(defclass VendorPushnotificationService (BusinessService)
  ())
(defclass VendorApprovalService (BusinessService)
  ())


;;; Business Service classes for Vendor 


(defclass VendorDBService (DBAdapterService)
  ())

;;; VendorRepository class
(defclass VendorRepository (BusinessObjectRepository)
  ())

;;; Business object for Vendor

(defclass Vendor (BusinessObject)
  ((row-id)
   (name)
   (address)
   (phone) 
   (email)
   (firstname)
   (lastname)
   (salutation)
   (title)
   (birthdate)
   (city)
   (state)
   (country)
   (zipcode)
   (gstnumber)
   (picture-path)
   (password)
   (salt)
   (payment-gateway-mode)
   (payment-api-key)
   (payment-api-salt)
   (push-notify-subs-flag)
   (email-add-verified)
   (suspend-flag)
   (active-flag)
   (approved-flag)
   (approved-by)
   (approval-status)
   (upi-id)
   (legal-name)
   (trade-name)
   (pan-number)
   (gst-state-code)
   (gst-registration-type)
   (gst-filing-frequency)
   (fy-start-month)
   (company
    :accessor company
    :initarg :company)))

;;; Database object for Vendor profile
;; ----------------------------------------------------------------------------
;; 实体：dod-vend-profile
;; 表：DOD_VEND_PROFILE
;; 含义：卖家档案主表。除登录账户/联系信息外，还存：
;;       - 支付网关参数（payment-api-key/salt/mode）
;;       - 审批流（approved-flag / approval-status / approved-by）
;;       - GST 合规字段（gstnumber / legal-name / trade-name / pan-number /
;;         gst-state-code / gst-registration-type / gst-filing-frequency / fy-start-month）
;;       - 财年起始月（fy-start-month），用于 GST 报表生成
;;       - invoice-settings：序列化的发票设置 JSON/字符串
;; 关键字段：
;;   row-id            主键
;;   name              卖家展示名（NOT NULL）
;;   phone / email     登录用主键之一
;;   password / salt   口令哈希与盐
;;   active-flag       Y/N 是否启用
;;   suspend-flag      Y/N 是否被暂停
;;   approved-flag     Y/N 是否已审批
;;   approval-status   PENDING/APPROVED/REJECTED
;;   email-add-verified Y/N 邮箱是否已验证
;;   shipping-enabled  Y/N 是否启用配送
;;   tenant-id         多租户隔离键 → dod-company.row-id
;;   deleted-state     N/Y 软删
;; 备注：country slot 的 :accessor 写成 city（推测原作者笔误，但保留不动）。
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vend-profile ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (name
    :accessor name
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 70)
    :INITARG :name)
   (address
    :ACCESSOR address 
    :type (string 70)
    :initarg :address)
   (phone
    :accessor phone
    :type (string 30)
    :initarg :phone)

   (email
    :accessor email
    :type (string 255)
    :initarg :email)
   (firstname
    :accessor firstname
    :type (string 50)
    :initarg :firstname)
   (lastname
    :accessor lastname
    :type (string 50)
    :initarg :lastname)
   (salutation
    :accessor salutation
    :type (string 10)
    :initarg :salutation)
   (title
    :accessor title
    :type (string 255)
    :initarg :title)
   (birthdate
    :accessor birthdate
    :type clsql:date
    :initarg :birthdate)
   (city
    :accessor city
    :type (string 256)
    :initarg :city)
   (state
    :accessor state
    :type (string 256)
    :initarg :state)
   (country
    :accessor city
    :type (string 256)
    :initarg :country)
   (zipcode
    :accessor zipcode
    :type (string 10)
    :initarg :zipcode)

   (gstnumber
    :accessor gstnumber
    :type (string 20)
    :initarg :gstnumber)
   
   (picture-path
    :accessor picture-path
    :type (string 256)
    :initarg :picture-path)
   
   (password 
    :accessor password
    :type (string 128) 
    :initarg :password)
   
   (salt 
    :accessor salt
    :type (string 128)
    :initarg :salt)
   
   (payment-gateway-mode
    :accessor payment-gateway-mode
    :type (string 10)
    :initarg :payment-gateway-mode)
   
   (payment-api-key 
    :accessor payment-api-key
    :type (string 40)
    :initarg :payment-api-key)
   
   (payment-api-salt 
    :accessor payment-api-salt
    :type (string 40)
    :initarg :payment-api-salt)
   
   (active-flag
    :accessor active-flag
    :type (string 1)
    :void-value "N"
    :initarg :active-flag ) 

    (suspend-flag
    :accessor suspend-flag
    :type (string 1)
    :void-value "N"
    :initarg :suspend-flag ) 

   (upi-id
    :accessor upi-id
    :type (string 70)
    :initarg :upi-id)
   

   (approved-flag
    :accessor approved-flag
    :type (string 1)
    :void-value "N"
    :initarg :approved-flag)

   (approval-status
    :accessor approval-status
    :type (string 20)
    :void-value "PENDING"
    :initarg :approval-status)

   (approved-by
    :accessor approved-by
    :type (string 30)
    :initarg :approved-by)
   
   (push-notify-subs-flag
    :accessor push-notify-subs-flag 
    :type (string 1)
    :void-value "N"
    :initarg :push-notify-subs-flag)

   (email-add-verified
    :type (string 1)
    :void-value "N"
    :initarg :email-add-verified)

   (shipping-enabled
    :type (string 1)
    :void-value "N"
    :initarg :shipping-enabled)
   
   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state)
   
   (invoice-settings
    :type (string 4000)
    :void-value "undefined"
    :initarg :invoice-settings)

   (legal-name
    :type (string 255)
    :initarg :legal-name)

   (trade-name
    :type (string 255)
    :initarg :trade-name)

   (pan-number
    :type (string 10)
    :initarg :pan-number)

   (gst-state-code
    :type (string 2)
    :initarg :gst-state-code)

   (gst-registration-type
    :type (string 20)
    :void-value "REGULAR"
    :initarg :gst-registration-type)

   (gst-filing-frequency
    :type (string 10)
    :void-value "MONTHLY"
    :initarg :gst-filing-frequency)

   (fy-start-month
    :type integer
    :initarg :fy-start-month)
   
   (tenant-id
    :type integer
    :initarg :tenant-id)
   
   (COMPANY
    :ACCESSOR get-vendor-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
              :SET NIL)))
   (:BASE-TABLE dod_vend_profile))




; DOD_VENDOR_TENANTS table is created to support multiple tenants for a given vendor.
;; 中文：vendor ↔ tenant 的多对多桥表，支持一个 vendor 入驻多个商城（tenant）。
;; ----------------------------------------------------------------------------
;; 业务对象：HHUBVendorTenants
;; 含义：vendor 与 tenant 的关联，标记是否默认 tenant（default-flag）。
;; ----------------------------------------------------------------------------

(defclass HHUBVendorTenants (BusinessObject)
  ((vendor)
   (tenant)
   (default-flag)))

;; ----------------------------------------------------------------------------
;; 实体：dod-vendor-tenants
;; 表：DOD_VENDOR_TENANTS
;; 含义：vendor ↔ tenant 多对多桥表。
;; 关键字段：
;;   row-id            主键
;;   vendor-id         外键 → dod-vend-profile（NOT NULL）
;;   tenant-id         外键 → dod-company.row-id
;;   default-flag      Y/N 是否该 vendor 的默认 tenant
;;   deleted-state     N/Y 软删
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vendor-tenants ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg :row-id)
   (vendor-id
    :accessor vendor-id
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE integer 
    :INITARG :vendor-id)
   (tenant-id 
    :type integer 
    :initarg :tenant-id)
    (COMPANY
    :ACCESSOR get-vendor-tenants-list
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET T))
   (default-flag 
       :type (string 1) 
     :void-value "N" 
     :initarg :default-flag)

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state))
  (:BASE-TABLE dod_vendor_tenants))

;;;;;;;;;;; Generic functions ;;;;;;;;;;;;;;;;;;;;;;;;;
;; 中文：vendor 模块的泛型函数声明，具体方法分派在 dod-bl-ven.lisp 中实现。
(defgeneric select-vendor-by-phone (VendorDBService Phone)
  (:documentation "Load Vendor from Database given the phone number.
   中文：根据手机号加载 vendor 数据库对象，并把它绑到入参的 VendorDBService 上。"))






