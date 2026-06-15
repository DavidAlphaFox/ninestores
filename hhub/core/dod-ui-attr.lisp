;;; dod-ui-attr.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— ABAC PIP 属性函数集合
;;;; 分层：UI 控制器/视图层（按代码归类，但承担 PIP 角色）
;;;; 文件：hhub/core/dod-ui-attr.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：ABAC 框架中 PIP（Policy Information Point）的属性求值实现 ——
;;;;       一组 com-hhub-attribute-* 函数，被 com-hhub-policy-* 策略按需 funcall。
;;;;       属性来源混合：会话上下文（角色/客户类型）、订阅套餐配额表
;;;;       （cond 纯函数）、业务表查询（get-shipping-method-for-vendor 等）。
;;;;
;;;; 警告（注释维护者必读）：
;;;;   PAP 在 PAP UI 新增属性时会向本文件**末尾**追加 (defun <attr-func> ()) 空函数。
;;;;   注释时**只能修改已有 defun**，不要在文件末尾新增任何内容，
;;;;   以免和 PAP 的 with-open-file :append 写入冲突。
;;;;
;;;; 主要导出（每个函数返回的值都会被 PDP 用于 (and...)/(or...) 决策）：
;;;;   com-hhub-attribute-role-name / role-instance
;;;;   com-hhub-attribute-customer-type / cust-order-payment-mode
;;;;   com-hhub-attribute-company-issuspended / vendor-issuspended
;;;;   com-hhub-attribute-company-{maxvendorcount, maxcustomercount,
;;;;                              maxprodcatgcount, prdbulkupload-enabled,
;;;;                              prdsubs-enabled, wallets-enabled,
;;;;                              codorders-enabled, subscription-plan}
;;;;   com-hhub-attribute-vendor-{maxproductcount, currentprodcatgcount,
;;;;                              bulk-product-count, shipping-enabled,
;;;;                              freeship-enabled, flatrateship-enabled,
;;;;                              tablerateship-enabled, externalship-enabled,
;;;;                              storepickup-enabled}
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-ui-pol.lisp 中的 com-hhub-policy-* 策略
;;;;   下游依赖：会话相关（get-login-userid / tenant-id / customer-type）；
;;;;             dod-vend-profile / dod-shipping-method / dod-prd-catg 等领域查询
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;; PIP 属性：当前登录用户的客户类型（PRE/POST 等），从会话取出。
(defun com-hhub-attribute-customer-type ()
(get-login-customer-type))

;; PIP 资源属性：返回字符串 "Order"，用作策略中"资源类型"占位符。
(defun com-hhub-attribute-order ()
  "Order")

;; PIP 动作属性：常量字符串，标记"创建订单"事务名。
(defun com-hhub-attribute-create-order ()
"com.hhub.transaction.create.order")

; This is an Action attribute functin for customer order edit.
;; PIP 动作属性：标记"客户编辑订单明细"事务名。
(defun com-hhub-attribute-cust-edit-order-item ()
"com.hhub.transaction.cust.edit.order.item")

;; PIP 环境属性：客户下单截止时间（每日 cutoff），来自全局参数。
(defun com-hhub-attribute-customer-order-cutoff-time ()
  *HHUB-CUSTOMER-ORDER-CUTOFF-TIME*)

;; PIP 资源属性：取指定订单的支付方式（PRE/POST/COD 等）；要求当前会话有 cust-company。
(defun com-hhub-attribute-cust-order-payment-mode (order-id)
 (let ((order (get-order-by-id order-id (get-login-cust-company))))
   (slot-value order 'payment-mode)))



;; PIP 主体属性：依次取 user-id / tenant-id → user-role 关联 → role 实例。
;; 每次调用都会触发数据库查询。
(defun com-hhub-attribute-role-instance ()
  (let* ((user-id (get-login-userid))
	 (tenant-id (get-login-tenant-id))
	 (userrole-instance (select-user-role-by-userid user-id tenant-id))
	 (role-id (slot-value userrole-instance 'role-id)))
    (select-role-by-id role-id)))


(defun com-hhub-attribute-role-name ()
:documentation "Role name is described. The attribute function will get the role name of the currently logged in user
中文：返回当前登录用户的角色名（SUPERADMIN / COMPADMIN / VENDOR / CUSTOMER 等）。"
(let ((role (com-hhub-attribute-role-instance)))
       (slot-value role 'name)))


;; PIP 配额属性：批量上传商品的硬上限（与套餐无关，常量 100）。
(defun com-hhub-attribute-vendor-bulk-product-count ()
  100)

;; PIP 主体属性：判定 vendor 是否被冻结（suspend-flag='Y'）。
(defun com-hhub-attribute-vendor-issuspended (vendor)
  (equal (slot-value vendor 'suspend-flag) "Y"))


;; PIP 资源属性：判定 company 是否被冻结。直接传 suspend-flag 字符串便于策略短路。
(defun com-hhub-attribute-company-issuspended (suspend-flag)
  (equal suspend-flag "Y"))


;; PIP 套餐配额：公司级最大可入驻 vendor 数。COMMUNITY 实质不限制（999）。
(defun com-hhub-attribute-company-maxvendorcount (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") 999)
    ((equal subscription-plan "BASIC") 5)
    ((equal subscription-plan "PROFESSIONAL") 10)
    ((equal subscription-plan "TRIAL") 1)))

;; PIP 套餐配额：单 vendor 最大商品数。
(defun com-hhub-attribute-vendor-maxproductcount (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") 50)
    ((equal subscription-plan "BASIC") 1000)
    ((equal subscription-plan "PROFESSIONAL") 3000)
    ((equal subscription-plan "TRIAL") 100)))


;; PIP 套餐特性：是否允许商品批量上传。
(defun com-hhub-attribute-company-prdbulkupload-enabled (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") NIL)
    ((equal subscription-plan "BASIC") T)
    ((equal subscription-plan "PROFESSIONAL") T)
    ((equal subscription-plan "TRIAL") NIL)))


;; PIP 套餐特性：是否启用商品订阅（周期下单）功能。
(defun com-hhub-attribute-company-prdsubs-enabled (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") NIL)
    ((equal subscription-plan "BASIC") T)
    ((equal subscription-plan "PROFESSIONAL") T)
    ((equal subscription-plan "TRIAL") NIL)))


;; PIP 套餐特性：是否启用客户钱包。仅 TRIAL 关闭。
(defun com-hhub-attribute-company-wallets-enabled (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") T)
    ((equal subscription-plan "BASIC") T)
    ((equal subscription-plan "PROFESSIONAL") T)
    ((equal subscription-plan "TRIAL") NIL)))


;; PIP 套餐特性：是否允许 COD（货到付款）。BASIC 不开放。
(defun com-hhub-attribute-company-codorders-enabled (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") T)
    ((equal subscription-plan "BASIC") NIL)
    ((equal subscription-plan "PROFESSIONAL") T)
    ((equal subscription-plan "TRIAL") NIL)))


;; PIP 套餐配额：公司级最大客户数。
(defun com-hhub-attribute-company-maxcustomercount (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") 100)
    ((equal subscription-plan "BASIC") 500)
    ((equal subscription-plan "PROFESSIONAL") 1000)
    ((equal subscription-plan "TRIAL") 50)))


;; PIP 资源属性：直接读 company 的 subscription-plan 槽。
(defun com-hhub-attribute-company-subscription-plan (company)
  (slot-value company 'subscription-plan))

;; PIP 套餐配额：公司级最大商品类目数。
(defun com-hhub-attribute-company-maxprodcatgcount  (subscription-plan cmp-type)
  (cond
    ((equal cmp-type "COMMUNITY") 20)
    ((equal subscription-plan "BASIC") 20)
    ((equal subscription-plan "PROFESSIONAL") 50)
    ((equal subscription-plan "TRIAL") 10)))

;; PIP 实时事实：当前 company 已有商品类目数。触发 DB 查询。
(defun com-hhub-attribute-vendor-currentprodcatgcount (company)
  (length (select-prdcatg-by-company company)))

;; PIP 资源属性：vendor 是否启用了运费功能。
(defun com-hhub-attribute-vendor-shipping-enabled (vendor)
  (let ((shipping-enabled (slot-value vendor 'shipping-enabled)))
    (if (equal shipping-enabled "Y") T NIL)))

;; PIP 资源属性：vendor 是否启用免运费策略。需要先查 shipping-method 设置。
(defun com-hhub-attribute-vendor-freeship-enabled (vendor company)
  (let* ((shipping-method (get-shipping-method-for-vendor vendor company))
	 (freeshipenabled (slot-value shipping-method 'freeshipenabled)))
    (if (equal freeshipenabled "Y") T NIL)))


;; PIP 资源属性：vendor 是否启用统一运费（flat rate）。
(defun com-hhub-attribute-vendor-flatrateship-enabled (vendor company)
  (let* ((shipping-method (get-shipping-method-for-vendor vendor company))
	 (flatrateshipenabled (slot-value shipping-method 'flatrateshipenabled)))
    (if (equal flatrateshipenabled "Y") T NIL)))

;; PIP 资源属性：vendor 是否启用 table-rate（按区/重量分级）运费。
(defun com-hhub-attribute-vendor-tablerateship-enabled (vendor company)
  (let* ((shipping-method (get-shipping-method-for-vendor vendor company))
	 (tablerateshipenabled (slot-value shipping-method 'tablerateshipenabled)))
    (if (equal tablerateshipenabled "Y") T NIL)))

;; PIP 资源属性：vendor 是否启用第三方物流（iThinkLogistics 等）。
(defun com-hhub-attribute-vendor-externalship-enabled (vendor company)
  (let* ((shipping-method (get-shipping-method-for-vendor vendor company))
	 (extshipenabled (slot-value shipping-method 'extshipenabled)))
    (if (equal extshipenabled "Y") T NIL)))

;; PIP 资源属性：vendor 是否允许门店自提。
(defun com-hhub-attribute-vendor-storepickup-enabled (vendor company)
  (let* ((shipping-method (get-shipping-method-for-vendor vendor company))
	 (storepickupenabled (slot-value shipping-method 'storepickupenabled)))
    (if (equal storepickupenabled "Y") T NIL)))

