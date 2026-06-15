;;; hhub-tst-sms.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— 短信网关（SMS）冒烟测试
;;;; 分层：测试套件（集成测试，依赖外部 SMS 服务）
;;;; 文件：hhub/test/hhub-tst-sms.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：调用真实短信发送通道，验证 OTP 模板可被正常发送到目标手机号。
;;;;
;;;; 主要导出：
;;;;   test-otp-send  — 给指定手机号发一条 OTP 短信
;;;;
;;;; 关联：
;;;;   上游使用方：开发者在 REPL 手工执行
;;;;   下游依赖：send-sms-notification（短信网关业务函数，发件人代码 "NTSTOR"）
;;;; ============================================================================

(in-package :nstores)

(defun test-otp-send (phone transaction-name OTP)
  ;; 集成测试：会真实计费并发送短信，请用测试号码。
  ;; 参数：phone — 收件号码；transaction-name — 业务名（嵌入正文）；OTP — 验证码。
  (send-sms-notification phone "NTSTOR"  (format nil "Your OTP for ~A is ~A. Do not share this OTP with anyone. Valid for 5 minutes. -Nine Technologies" transaction-name OTP)))

