;;; nst-dal-Customer.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：customer 客户（新风格 nst-，DDD/Hexagonal 管线）
;;;; 分层：DAL（数据访问层 / 领域对象与服务壳）
;;;; 文件：hhub/customer/nst-dal-Customer.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义客户领域在六边形架构里的全部核心 CLOS 类壳：
;;;;       - 服务壳：CustomerAdapter / CustomerDBService / CustomerPresenter /
;;;;                 CustomerService（行为在 nst-bl-Customer.lisp 用 defmethod 给）。
;;;;       - 视图壳：CustomerHTMLView / CustomerAddressJSONView。
;;;;       - 数据载体：CustomerViewModel / CustomerResponseModel / CustomerRequestModel /
;;;;                   CustomerSearchRequestModel。
;;;;       - 业务对象：Customer（BusinessObject 子类，承载客户全部领域字段）。
;;;;
;;;; 主要导出：
;;;;   Customer                      — 客户领域对象（BusinessObject 子类）
;;;;   CustomerAdapter               — 应用服务（AdapterService）
;;;;   CustomerService               — 领域服务（BusinessService）
;;;;   CustomerDBService             — 仓储/DB 适配器（DBAdapterService）
;;;;   CustomerPresenter             — 响应模型 → 视图模型转换
;;;;   CustomerHTMLView / CustomerAddressJSONView — 视图实现
;;;;   CustomerRequestModel / CustomerSearchRequestModel — 请求模型
;;;;   CustomerResponseModel         — 响应模型
;;;;   CustomerViewModel             — 视图模型
;;;;
;;;; 关联：
;;;;   上游使用方：customer/nst-bl-Customer.lisp（行为方法）、
;;;;               customer/nst-ui-Customer.lisp（控制器）。
;;;;   下游依赖：core 的 BusinessObject / RequestModel / ResponseModel /
;;;;             ViewModel / View / AdapterService 等基类（hhub-bl-ent.lisp、
;;;;             nst-bl-conflodis.lisp）。
;;;; ============================================================================

(in-package :nstores)


;; ----------------------------------------------------------------------------
;; 服务壳类：六边形架构中的应用/领域/仓储/视图适配器入口。
;; 行为（defmethod）写在 nst-bl-Customer.lisp，本文件只声明类层级。
;; ----------------------------------------------------------------------------

;; CustomerAdapter — 应用服务（用例入口）：协调请求到领域服务的派发。
(defclass CustomerAdapter (AdapterService)
  ())

;; CustomerDBService — 仓储适配器：负责把 Customer 领域对象与 dod-cust-profile 表互相转换。
(defclass CustomerDBService (DBAdapterService)
  ())

;; CustomerPresenter — 展示服务：把 ResponseModel → ViewModel。
(defclass CustomerPresenter (PresenterService)
  ())

;; CustomerService — 领域服务：客户相关业务规则承载点。
(defclass CustomerService (BusinessService)
  ())

;; CustomerHTMLView — HTML 视图：把 ViewModel 渲染成页面 HTML。
(defclass CustomerHTMLView (HTMLView)
  ())

;; CustomerAddressJSONView — JSON 视图：用于地址等 AJAX 接口返回 JSON。
(defclass CustomerAddressJSONView (JSONView)
  ())

;; ----------------------------------------------------------------------------
;; CustomerViewModel
;; 含义：渲染层使用的客户视图模型，字段集合是 Customer 业务对象的完整投影
;;       （含 password/salt — 视图层一般不展示，但这里平铺保留以便表单回填）。
;; ----------------------------------------------------------------------------
(defclass CustomerViewModel (ViewModel)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   (name
    :initarg :name
    :accessor name)
   (address
    :initarg :address
    :accessor address)
   (phone
    :initarg :phone
    :accessor phone)
   (email
    :initarg :email
    :accessor email)
   (firstname
    :initarg :firstname
    :accessor firstname)
   (lastname
    :initarg :lastname
    :accessor lastname)
   (salutation
    :initarg :salutation
    :accessor salutation)
   (title
    :initarg :title
    :accessor title)
   (birthdate
    :initarg :birthdate
    :accessor birthdate)
   (city
    :initarg :city
    :accessor city)
   (state
    :initarg :state
    :accessor state)
   (country
    :initarg :country
    :accessor country)
   (zipcode
    :initarg :zipcode
    :accessor zipcode)
   (picture-path
    :initarg :picture-path
    :accessor picture-path)
   (password
    :initarg :password
    :accessor password)
   (salt
    :initarg :salt
    :accessor salt)
   (cust-type
    :initarg :cust-type
    :accessor cust-type)
   (email-add-verified
    :initarg :email-add-verified
    :accessor email-add-verified)
   (company
    :initarg :company
    :accessor company)))




;; ----------------------------------------------------------------------------
;; CustomerResponseModel
;; 含义：领域服务返回给上层的响应数据。比 ViewModel 少 password/salt（不外泄）。
;; ----------------------------------------------------------------------------
(defclass CustomerResponseModel (ResponseModel)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   (name
    :initarg :name
    :accessor name)
   (address
    :initarg :address
    :accessor address)
   (phone
    :initarg :phone
    :accessor phone)
   (email
    :initarg :email
    :accessor email)
   (firstname
    :initarg :firstname
    :accessor firstname)
   (lastname
    :initarg :lastname
    :accessor lastname)
   (salutation
    :initarg :salutation
    :accessor salutation)
   (title
    :initarg :title
    :accessor title)
   (birthdate
    :initarg :birthdate
    :accessor birthdate)
   (city
    :initarg :city
    :accessor city)
   (state
    :initarg :state
    :accessor state)
   (country
    :initarg :country
    :accessor country)
   (zipcode
    :initarg :zipcode
    :accessor zipcode)
   (picture-path
    :initarg :picture-path
    :accessor picture-path)
   (cust-type
    :initarg :cust-type
    :accessor cust-type)
   (email-add-verified
    :initarg :email-add-verified
    :accessor email-add-verified)
   (company
    :initarg :company
    :accessor company)))
   

;; ----------------------------------------------------------------------------
;; CustomerRequestModel
;; 含义：上层应用传给领域服务的请求载荷。包含 password/salt（创建/修改场景）。
;; ----------------------------------------------------------------------------
(defclass CustomerRequestModel (RequestModel)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   (name
    :initarg :name
    :accessor name)
   (address
    :initarg :address
    :accessor address)
   (phone
    :initarg :phone
    :accessor phone)
   (email
    :initarg :email
    :accessor email)
   (firstname
    :initarg :firstname
    :accessor firstname)
   (lastname
    :initarg :lastname
    :accessor lastname)
   (salutation
    :initarg :salutation
    :accessor salutation)
   (title
    :initarg :title
    :accessor title)
   (birthdate
    :initarg :birthdate
    :accessor birthdate)
   (city
    :initarg :city
    :accessor city)
   (state
    :initarg :state
    :accessor state)
   (country
    :initarg :country
    :accessor country)
   (zipcode
    :initarg :zipcode
    :accessor zipcode)
   (picture-path
    :initarg :picture-path
    :accessor picture-path)
   (password
    :initarg :password
    :accessor password)
   (salt
    :initarg :salt
    :accessor salt)
   (cust-type
    :initarg :cust-type
    :accessor cust-type)
   (email-add-verified
    :initarg :email-add-verified
    :accessor email-add-verified)
   (company
    :initarg :company
    :accessor company)))


;; ----------------------------------------------------------------------------
;; CustomerSearchRequestModel
;; 含义：搜索类请求模型，目前与 CustomerRequestModel 同结构；通过类型分派区分用途。
;; ----------------------------------------------------------------------------
(defclass CustomerSearchRequestModel (CustomerRequestModel)
  ())

;; ----------------------------------------------------------------------------
;; Customer（业务对象）
;; 含义：客户领域对象，承载客户在领域层的所有属性（姓名、地址、登录凭据、客户类型、
;;      所属公司等）。被 BL/Adapter/Service 在事务管线中读写。
;; 关键字段：
;;   row-id              主键（与 dod-cust-profile.row-id 对应）
;;   name / firstname / lastname / salutation / title    称呼相关
;;   phone / email / email-add-verified                  联系方式与验证状态
;;   address / city / state / country / zipcode          地址
;;   birthdate                                           生日
;;   picture-path                                        头像路径
;;   password / salt                                     登录密码摘要（不外泄）
;;   cust-type                                           STANDARD / GUEST 等
;;   company                                             所属租户 dod-company 引用
;; ----------------------------------------------------------------------------
(defclass Customer (BusinessObject)
  ((row-id
    :initarg :row-id
    :accessor row-id)
   (name
    :initarg :name
    :accessor name)
   (address
    :initarg :address
    :accessor address)
   (phone
    :initarg :phone
    :accessor phone)
   (email
    :initarg :email
    :accessor email)
   (firstname
    :initarg :firstname
    :accessor firstname)
   (lastname
    :initarg :lastname
    :accessor lastname)
   (salutation
    :initarg :salutation
    :accessor salutation)
   (title
    :initarg :title
    :accessor title)
   (birthdate
    :initarg :birthdate
    :accessor birthdate)
   (city
    :initarg :city
    :accessor city)
   (state
    :initarg :state
    :accessor state)
   (country
    :initarg :country
    :accessor country)
   (zipcode
    :initarg :zipcode
    :accessor zipcode)
   (picture-path
    :initarg :picture-path
    :accessor picture-path)
   (password
    :initarg :password
    :accessor password)
   (salt
    :initarg :salt
    :accessor salt)
   (cust-type
    :initarg :cust-type
    :accessor cust-type)
   (email-add-verified
    :initarg :email-add-verified
    :accessor email-add-verified)
    (company
    :initarg :company
    :accessor company)))




