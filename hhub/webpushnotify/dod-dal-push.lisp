;;; dod-dal-push.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：webpushnotify 浏览器推送通知
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/webpushnotify/dod-dal-push.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 web-push 订阅与发送相关的数据模型：
;;;;       - 域对象 WebPushNotify / WebPushNotifyCustomer / WebPushNotifyVendor
;;;;         （封装浏览器订阅 endpoint + publickey + auth 三元组）
;;;;       - 持久化 view-class dod-webpush-notify（表 DOD_WEBPUSH_NOTIFY）
;;;;       - 六边形分层占位：DBService / Adapter / Presenter / Service /
;;;;         Repository / Request/Response/ViewModel
;;;;
;;;; 主要导出：
;;;;   WebPushNotify / WebPushNotifyCustomer / WebPushNotifyVendor  — 域对象
;;;;   WebPushNotifyDBService / VendorWebPushNotifyAdapter /
;;;;   VendorWebPushNofityPresenter / VendorWebPushNotifyService    — 服务占位
;;;;   RequestGetWebPushNofityVendor / RequestCreateWebPushNotifyVendor /
;;;;   RequestDeleteWebPushNotifyVendor / ResponseGetWebPushNotifyVendor /
;;;;   GetWebPushNotifyVendorViewModel / GetWebPushNotifyVendorPresenter
;;;;   WebPushNotifyRepository                                      — DTO/Repo
;;;;   db-fetch-Vendor-WebPushNotifySubscriptions                   — 通用函数声明
;;;;   dod-webpush-notify                                           — view-class
;;;;
;;;; 关联：
;;;;   上游使用方：webpushnotify/dod-bl-push.lisp（业务）、
;;;;               webpushnotify/dod-ui-push.lisp（订阅/取消推送的客户端 JS）
;;;;   下游依赖：core 抽象基类、dod-cust-profile / dod-vend-profile / dod-users / dod-company
;;;;
;;;; 备注：本模块的实际推送动作在外部 Node 边车 webpushserver/（VAPID web-push 库）。
;;;;       Lisp 端只负责存订阅与转发触发请求，详见 dod-bl-push.lisp 的 push/notify/user 端点。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;; Generic Functions

;; Entity class
;; Webpush notify general class
;; ----------------------------------------------------------------------------
;; DTO：WebPushNotify
;; 含义：web-push 订阅域对象的基类，对应一个浏览器在 push service 上注册到的
;;       endpoint。endpoint + publickey + auth 即 web-push 协议要求的"订阅信息"。
;; 关键字段：
;;   browser-name    浏览器名（Chrome / Firefox / ...）
;;   endpoint        push service 提供的目标 URL（FCM / Mozilla AutoPush ...）
;;   publickey       客户端 P-256 公钥（Base64URL）
;;   auth            16 字节 auth secret（Base64URL）
;;   perm-granted    Y/N 用户是否已授权推送
;;   expired         Y/N 订阅是否已失效（push service 回报 410 后置 'Y'）
;; ----------------------------------------------------------------------------
(defclass WebPushNotify (BusinessObject)
  ((browser-name
    :accessor browser-name
    :initarg :browser-name)
   (endpoint
    :accessor endpoint
    :initarg :endpoint)
   (publickey
    :accessor publickey
    :initarg :publickey)
   (auth
    :accessor auth
    :initarg :auth)
   (perm-granted
    :accessor perm-granted
    :initarg :perm-granted)
   (expired
    :accessor expired
    :initarg :expired)))


;; Entity class
;; Web Push Notify Customer class represents the webpush notify subscription for the customer.
;; 中文：WebPushNotifyCustomer —— 客户维度的推送订阅域对象，附带 customer slot。
(defclass WebPushNotifyCustomer (WebPushNotify)
  ((customer
    :accessor customer
    :initarg :customer)))

;; Entity class.
;; Web Push Notify Vendor class represents the webpush notify subscription for the Vendor.
;; 中文：WebPushNotifyVendor —— 卖家维度的推送订阅域对象，附带 vendor slot。
(defclass WebPushNotifyVendor (WebPushNotify)
  ((vendor
    :accessor vendor
    :initarg :vendor)))


;; ----------------------------------------------------------------------------
;; 服务/视图层占位（六边形分层）
;; ----------------------------------------------------------------------------
(defclass WebPushNotifyDBService (DBAdapterService)
  ())

(defclass VendorWebPushNotifyAdapter (AdapterService)
  ())

(defclass VendorWebPushNofityPresenter (PresenterService)
  ())

(defclass VendorWebPushNotifyService (BusinessService)
  ())

;; ----------------------------------------------------------------------------
;; DTO：RequestGetWebPushNofityVendor
;; 含义：查询某 vendor 全部推送订阅的请求模型。注意 slot 写成 vendor（无 :initarg），
;;       推测仅作为读位用。
;; ----------------------------------------------------------------------------
(defclass RequestGetWebPushNofityVendor (RequestModel)
  (vendor))

;; ----------------------------------------------------------------------------
;; DTO：ResponseGetWebPushNotifyVendor
;; 含义：返回 vendor 推送订阅信息的响应模型（一对一，不带列表）。
;; 注：browser-name slot 上写的是 :initarg browser-name（少一个冒号），
;;    推测为代码笔误，但因关键字也可作 symbol 传入而不报错。
;; ----------------------------------------------------------------------------
(defclass ResponseGetWebPushNotifyVendor (ResponseModel)
  ((browser-name
    :initarg browser-name)
   (endpoint
    :initarg :endpoint )
   (publickey
    :initarg :publickey)
   (auth
    :initarg :auth)
   (perm-granted
    :initarg :perm-granted)
   (expired
    :initarg :expired)))

;; ----------------------------------------------------------------------------
;; DTO：RequestCreateWebPushNotifyVendor
;; 含义：vendor 端订阅推送时的请求模型，携带浏览器返回的 endpoint/publickey/auth。
;; ----------------------------------------------------------------------------
(defclass RequestCreateWebPushNotifyVendor (RequestModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)
   (endpoint
    :initarg :endpoint
    :accessor endpoint)
   (publickey
    :initarg :publickey
    :accessor publickey)
   (auth
    :initarg :auth
    :accessor auth)))

;; ----------------------------------------------------------------------------
;; DTO：RequestDeleteWebPushNotifyVendor
;; 含义：vendor 端取消推送订阅时的请求模型，携带 vendor + company。
;; ----------------------------------------------------------------------------
(defclass RequestDeleteWebPushNotifyVendor (RequestModel)
  ((vendor
    :initarg :vendor
    :accessor vendor)
   (company
    :initarg :company
    :accessor company)))


(defclass WebPushNotifyRepository (BusinessObjectRepository)
  ())

;; ViewModel：仅暴露 endpoint 字段（推测：UI 仅判断订阅是否存在，不展示其它字段）。
(defclass GetWebPushNotifyVendorViewModel (ViewModel)
  ((endpoint)))

(defclass GetWebPushNotifyVendorPresenter (PresenterService)
  ())

;;;; Generic functions
(defgeneric db-fetch-Vendor-WebPushNotifySubscriptions (WebPushNotifyDBService vendor)
  (:documentation "Gets Web Push Notify subscriptions for a given Vendor.
   中文：取某 vendor 的全部 web-push 订阅记录（接口声明，实现在 BL 层）。"))

;; This is database releated class.
;; ----------------------------------------------------------------------------
;; 实体：dod-webpush-notify
;; 表：DOD_WEBPUSH_NOTIFY
;; 含义：浏览器推送订阅表。一行 = 一个登录身份（customer 或 vendor）的某个浏览器的
;;       一条 push subscription。push 触发时本表的 endpoint/publickey/auth 会作为
;;       payload 传给 Node 边车 webpushserver/。
;; 关键字段：
;;   row-id            主键
;;   cust-id           客户主键 → dod-cust-profile（person-type='CUSTOMER' 时填）
;;   vendor-id         卖家主键 → dod-vend-profile（person-type='VENDOR' 时填）
;;   person-type       订阅者身份（CUSTOMER/VENDOR）
;;   browser-name      浏览器名（NOT NULL）
;;   endpoint          push service 目标 URL，最长 512（NOT NULL）
;;   publickey         客户端 P-256 公钥（NOT NULL）
;;   auth              客户端 auth secret（NOT NULL）
;;   expired           Y/N 订阅是否已过期（默认 'N'）
;;   active-flag       Y/N 是否仍可用于推送（默认 'N'，需经一次成功后置 'Y'？）
;;   deleted-state     N/Y 软删
;;   perm-granted      Y/N 用户授权（默认 'Y'）
;;   created           clsql:wall-time 创建时间
;;   created-by        创建用户 → dod-users
;;   tenant-id         租户键 → dod-company
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-webpush-notify ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)

   
   (cust-id
    :type integer 
    :initarg :cust-id)
   (customer
    :ACCESSOR get-customer
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-cust-profile
	                  :HOME-KEY cust-id
                          :FOREIGN-KEY row-id
                          :SET nil))

   (vendor-id
    :type integer
    :initarg :vendor-id)
   (vendor
    :ACCESSOR get-vendor
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-vend-profile
	                  :HOME-KEY vendor-id
                          :FOREIGN-KEY row-id
                          :SET nil))
   
   
   (person-type
    :type (string 30)
    :initarg :person-type) 

   (browser-name
    :accessor browser-name
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 30)
    :INITARG :browser-name)

   (endpoint
    :accessor endpoint 
    :DB-CONSTRAINTS :NOT-NULL
    :TYPE (string 512)
    :INITARG :endpoint)

   (publicKey
    :accessor publickey
    :db-constraints :not-null
    :type (string 100)
    :initarg :publickey)

   (auth
    :accessor auth
    :db-constraints :not-null
    :type (string 100)
    :initarg :auth)

   
   (expired
    :type (string 1)
    :void-value "N"
       :initarg :expired)

   (active-flag
    :type (string 1)
    :void-value "N"
       :initarg :active-flag)


   (deleted-state
    :type (string 1)
    :void-value "N"
       :initarg :deleted-state)


   (perm-granted
    :type (string 1) 
    :void-value "Y"
    :initarg :perm-granted)
   
   (created
    :type clsql:wall-time
    :initarg :created)

   (created-by
    :type integer
    :initarg :created-by)
   (created-by-user
    :accessor get-created-by-user
    :db-kind :join
    :db-info (:join-class dod-users
			  :home-key created-by
			  :foreign-key row-id
			  :set NIL))


   
    (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR get-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET T)))

   
  (:BASE-TABLE DOD_WEBPUSH_NOTIFY))


		  

      



  
