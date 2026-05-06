
;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— 发票头（InvoiceHeader）持久化测试
;;;; 分层：测试套件（集成测试，依赖 DB 与 invoice 模块全套 Adapter）
;;;; 文件：hhub/test/hhub-test-inv.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：用预置 vendor=1、company=2、customer=1 构造一条 InvoiceHeader
;;;;       请求模型，走 InvoiceHeaderAdapter.ProcessCreateRequest 写入。
;;;;
;;;; 主要导出：
;;;;   test-invoiceheader-DBSave  — 创建一张演示发票头
;;;;
;;;; 关联：
;;;;   下游依赖：invoice/nst-bl-ihd.lisp、invoice/nst-ui-ihd.lisp（Adapter 层）、
;;;;             customer/account/vendor 三个域的 select-*-by-id
;;;; ============================================================================

(in-package :nstores)
(defun test-invoiceheader-DBSave ()
  ;; 集成测试：会真实写库；演示日期 06/09/2024、固定金额 1000.0。
;; (handler-case   
  (let* ((company (select-company-by-id 2))
	 (customer (select-customer-by-id 1 company))
	 (vendor (select-vendor-by-id 1))
	 (requestmodel (make-instance 'InvoiceHeaderRequestModel
				      :invnum ""
				      :invdate (get-date-from-string "06/09/2024")
				      :custaddr "Mahalaxmi layout, Bangalore"
				      :custgstin ""
				      :statecode "02"
				      :billaddr "Mahalaxmi layout"
				      :shipaddr "Mahalaxmi layout"
				      :placeofsupply "Bangalore"
				      :revcharge "No"
				      :transmode ""
				      :vnum ""
				      :totalvalue 1000.0
				      :totalinwords "One thousand only"
				      :bankaccnum ""
				      :bankifsccode ""
				      :tnc ""
				      :finyear "2024"
				      :authsign "Demo Vendor"
				      :vendor vendor
				      :customer customer
				      :company company))
	 
	 (adapterobj (make-instance 'InvoiceHeaderAdapter)))
    (ProcessCreateRequest adapterobj requestmodel)))
