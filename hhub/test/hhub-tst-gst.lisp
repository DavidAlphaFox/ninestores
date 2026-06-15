;;; hhub-tst-gst.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— GST HSN 税码 CRUD 测试
;;;; 分层：测试套件（集成测试，依赖 DB 与 GSTHSNCodesAdapter）
;;;; 文件：hhub/test/hhub-tst-gst.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：以系统 company（id=1）为租户，演示对 HSN 税率表的新增 / 更新。
;;;;       使用 HSN 0405（黄油/乳制品）作为样例，sgst+cgst=igst=12% 校验。
;;;;
;;;; 主要导出：
;;;;   test-gsthsncode-DBSave    — Adapter.ProcessCreateRequest 走一遍
;;;;   test-gsthsncode-DBUpdate  — Adapter.ProcessUpdateRequest 走一遍
;;;;
;;;; 关联：
;;;;   下游依赖：products/dod-bl-gst.lisp 中的 GSTHSNCodesAdapter / RequestModel、
;;;;             account/dod-bl-cmp.lisp:select-company-by-id
;;;; ============================================================================

(in-package :nstores)

(defun test-gsthsncode-DBSave ()
  ;; 集成测试：会真实 INSERT 到 HSN 税率表；用 handler-case 包装异常并转抛业务错误。
;; (handler-case   
     (let* ((company (select-company-by-id 1))
	    (requestmodel (make-instance 'GSTHSNCodesRequestModel
					 :hsncode "0405"
					 :hsncode4digit "0405"
					 :description "Butter  and  other  fats  (i.e.  ghee,  butter  oil,etc.)   and   oils   derived   from   milk;   dairy spreads"
					 :sgst 6.0
					 :cgst 6.0
					 :igst 12.0
					 :compcess 0.0
					 :company company))
	    (gsthsncodeadapter (make-instance 'GSTHSNCodesAdapter)))

       (handler-case 
	   (ProcessCreateRequest gsthsncodeadapter requestmodel)
	 (error (c)
	   (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c))))))


(defun test-gsthsncode-DBUpdate ()
  ;; 集成测试：以同一 HSN 走更新通道（应回写已有行而非新增；推测取决于 Adapter 内部 upsert 策略）。
;; (handler-case
     (let* ((company (select-company-by-id 1))
	    (requestmodel (make-instance 'GSTHSNCodesRequestModel
					 :hsncode "0405"
					 :hsncode4digit "0405"
					 :description "Butter  and  other  fats  (i.e.  ghee,  butter  oil,etc.)   and   oils   derived   from   milk;   dairy spreads"
					 :sgst 6.0
					 :cgst 6.0
					 :igst 12.0
					 :compcess 0.0
					 :company company))
	    (gsthsncodeadapter (make-instance 'GSTHSNCodesAdapter)))

       (handler-case 
	   (ProcessUpdateRequest gsthsncodeadapter requestmodel)
	 (error (c)
	   (error 'hhub-business-function-error :errstring (format t "got an exception ~A" c))))))
