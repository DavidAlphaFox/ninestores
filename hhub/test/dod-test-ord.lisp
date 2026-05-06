;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— 客户登录 + 我的订单 端到端压力脚本
;;;; 分层：测试套件（集成 / 压测，依赖运行中的 HTTP 服务 *siteurl*）
;;;; 文件：hhub/test/dod-test-ord.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：通过 drakma 模拟客户重复登录 → 查我的订单 → 登出 100 次，
;;;;       用于会话/Cookie/订单查询路径的稳定性观察。
;;;;
;;;; 主要导出：
;;;;   loginandgetorders  — 100 次循环的登录/查单/登出
;;;;
;;;; 关联：
;;;;   下游依赖：drakma（HTTP 客户端）、运行中的 nstores Web Server，
;;;;             URL: /hhub/dodcustlogin、/hhub/dodmyorders、/hhub/dodcustlogout
;;;; ============================================================================

(in-package :nstores)

(defun loginandgetorders ()
  ;; 集成/压测：固定使用 phone=9972022281 / password=demo 演示账号；
  ;; 每次循环 sleep 1 秒，避免触发限流。
  ;; 注意：脚本结尾的 logout 必须最后执行，因为执行后 cookie-jar 即失效。
  (loop for i from 1 to 100 do   
       (let* ((cookie-jar (make-instance 'drakma:cookie-jar)))
       (drakma:http-request (format nil "~A/hhub/dodcustlogin" *siteurl*) 
                         :method :post
			 :parameters '(("phone" . "9972022281")
					 ("password" . "demo"))
    :cookie-jar cookie-jar)
       (drakma:http-request (format nil "~A/hhub/dodmyorders" *siteurl*)
                         :cookie-jar cookie-jar)
       (sleep 1)
       (drakma:cookie-jar-cookies cookie-jar)

    ; This should be the last call, since we are deleting the cookies by this time. 
   (drakma:http-request (format nil "~A/hhub/dodcustlogout" *siteurl*)))))






			 
