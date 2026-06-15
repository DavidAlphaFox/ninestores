;;; hhub-tst-vpm.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— Vendor 支付方式（VPaymentMethods）CRUD 测试
;;;; 分层：测试套件（集成测试，依赖 DB 与 with-entity-* 框架宏）
;;;; 文件：hhub/test/hhub-tst-vpm.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：覆盖 vendor 启用 / 禁用某种支付方式的 4 种典型用例：
;;;;       create / readall / read / update。
;;;;
;;;; 主要导出：
;;;;   test-vpayment-methods-DBSave    — 创建（默认 COD/UPI/聚合/钱包/先付后买全部启用）
;;;;   test-allvpayment-methods-fetch  — 列表读取
;;;;   test-vpayment-methods-fetch     — 单条读取
;;;;   test-vpayment-methods-update    — 更新（演示关闭 codenabled）
;;;;
;;;; 关联：
;;;;   下游依赖：vendor/dod-bl-vpm.lisp（VPaymentMethodsAdapter / RequestModel）、
;;;;             with-entity-create / with-entity-read / with-entity-readall / with-entity-update 宏
;;;; ============================================================================

(in-package :nstores)

(defun test-vpayment-methods-DBSave ()
  ;; 集成测试：固定 vendor=1, company=2，所有支付方式启用为 "Y"。
  (let* ((democompany (select-company-by-id 2))
	 (vendor (select-vendor-by-id 1))
	 (requestmodel (make-instance 'VPaymentMethodsRequestModel
				      :vendor vendor
				      :company democompany
				      :codenabled "Y"
				      :upienabled "Y"
				      :payprovidersenabled "Y"
				      :walletenabled "Y"
				      :paylaterenabled "Y")))
    (with-entity-create 'VPaymentMethodsAdapter requestmodel
      entity)))

(defun test-allvpayment-methods-fetch ()
  ;; 列表读取：用 with-entity-readall 框架宏，按 vendor + company 过滤。
  (let* ((company (select-company-by-id 2))
	 (vendor (select-vendor-by-id 1))
	 (requestmodel (make-instance 'VPaymentMethodsRequestModel)))
    (setf (slot-value requestmodel 'company) company)
    (setf (slot-value requestmodel 'vendor) vendor)
    (with-entity-readall 'VPaymentMethodsAdapter requestmodel
      allentities)))


(defun test-vpayment-methods-fetch (vendor)
  ;; 单条读取：参数 vendor 由调用方传入，便于在 REPL 里换 vendor 调试。
  (let* ((company (select-company-by-id 2))
	 (requestmodel (make-instance 'VPaymentMethodsRequestModel)))
    (setf (slot-value requestmodel 'company) company)
    (setf (slot-value requestmodel 'vendor) vendor)
    (with-entity-read 'VPaymentMethodsAdapter requestmodel
      entity)))

(defun test-vpayment-methods-update ()
  ;; 更新：演示关闭 vendor=1 的 COD（codenabled "N"），其它字段保持原值。
  (let* ((company (select-company-by-id 2))
	 (vendor (select-vendor-by-id 1)) 
	 (requestmodel (make-instance 'VPaymentMethodsRequestModel)))
    
    (setf (slot-value requestmodel 'company) company)
    (setf (slot-value requestmodel 'vendor) vendor)
    (setf (slot-value requestmodel 'codenabled) "N")

    (with-entity-update 'VPaymentMethodsAdapter requestmodel
      entity)))

	  
