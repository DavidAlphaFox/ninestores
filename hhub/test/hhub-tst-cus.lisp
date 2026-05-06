;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— 客户侧地址 / 邮编校验
;;;; 分层：测试套件（集成测试，依赖 DB 中的全国邮编表）
;;;; 文件：hhub/test/hhub-tst-cus.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：通过 Adapter / Presenter / JSONView 三件套测试邮编查询接口
;;;;       的端到端 JSON 输出。
;;;;
;;;; 主要导出：
;;;;   test-pincode-check  — 输入邮编，渲染对应城市/州/国家的 JSON 视图
;;;;
;;;; 关联：
;;;;   下游依赖：Address-Adapter、Address-Presenter、JSONView、
;;;;             core/nst-bl-pincodes.lisp（邮编解析）
;;;; ============================================================================

(in-package :nstores)


(defun test-pincode-check (pincode)
  ;; 集成测试：走 Adapter→Presenter→View 完整链路，等价于真实请求处理。
  ;; 参数：pincode — 6 位印度邮编字符串；返回：渲染后的 JSON 字符串。
  (let* ((params nil)
	 (addressadapter (make-instance 'Address-Adapter))
	 (presenter (make-instance 'Address-Presenter))
	 (jsonview (make-instance 'JSONView)))
    
    (setf params (acons "pincode" pincode params))
    (render jsonview (createviewmodel presenter (processrequest addressadapter params)))))
