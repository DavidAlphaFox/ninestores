;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 自定义异常 / 错误边界宏
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/dod-bl-err.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：集中定义所有平台级 condition（hhub-* / nst-*），提供统一的
;;;;       errstring slot + getExceptionStr reader；并提供两套错误边界宏：
;;;;       with-nst-error-handler（简版）与 with-nst-error-boundary（带 restart）。
;;;;
;;;; 主要导出：
;;;;   hhub-database-error / hhub-no-result / hhub-contradiction
;;;;   hhub-unknown
;;;;   nst-api-timeout-error / nst-api-internal-error
;;;;   hhub-business-function-error
;;;;   hhub-abac-transaction-error    — ABAC 拒绝（被 PDP 捕获）
;;;;   hhub-method-not-found / hhub-webpush-subscription-exists
;;;;   nst-shipping-error
;;;;   null-value-error / check-null / ensure-not-null
;;;;   with-nst-error-handler / with-nst-debugger / with-nst-error-boundary
;;;;   find-caller-name-from-backtrace / log-critical-error
;;;;
;;;; 关联：
;;;;   上游使用方：has-permission（捕获 hhub-abac-transaction-error）、
;;;;               全局业务函数（throw 业务级 condition）
;;;; ============================================================================
(in-package :nstores)



(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; 数据库相关的逻辑层异常基类（非系统级 fatal，业务可恢复）。
  (define-condition hhub-database-error (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))
    (:documentation "Base condition for logical database results (non-fatal).")))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; "未知"语义异常（Belnap 四值逻辑里的 :U 状态）。
  (define-condition hhub-unknown (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))
    (:documentation "Base condition for logical database results (non-fatal).")))


;; --- No Result ---
;; DB 查询返回 0 行时使用，配合 Belnap :F 状态。
(define-condition hhub-no-result (hhub-database-error)
  ()
  (:report (lambda (c s)
             (format s "No result found: ~A" (getExceptionStr c))))
  (:documentation "Raised when a DB query returns zero rows."))

;; --- Contradiction (multiple results when only one expected) ---
;; 期望唯一记录但拿到多条；对应 Belnap :C 状态。
(define-condition hhub-contradiction (hhub-database-error)
  ()
  (:report (lambda (c s)
             (format s "Contradictory results: ~A" (getExceptionStr c))))
  (:documentation "Raised when multiple inconsistent results were found."))


(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; 外部 API 调用超时。
  (define-condition nst-api-timeout-error (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; 外部 API 内部错误（HTTP 5xx 等）。
  (define-condition nst-api-internal-error (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))))


(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; 通用业务函数错误，失败原因用 errstring 携带友好文案。
  (define-condition hhub-business-function-error (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; ABAC 鉴权拒绝。策略函数主动 (error 'hhub-abac-transaction-error :errstring "...")
  ;; 时由 has-permission 捕获并把 errstring 写入业务日志。
  (define-condition hhub-abac-transaction-error (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; CLOS 派发命中不到方法时使用。
  (define-condition hhub-method-not-found (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; 浏览器 Webpush 订阅去重：同一 endpoint 已存在订阅。
  (define-condition hhub-webpush-subscription-exists (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))))


(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; 物流/运费计算失败（pincode 不可达、超出配送范围等）。
  (define-condition nst-shipping-error (error)
    ((errstring
      :initarg :errstring
      :reader getExceptionStr))))


(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro  with-nst-error-handler (expression condition)
    :description "Takes an expression, condition and error-string. Executes the expression and upon failure throws the condition and error string and also writes to file
    中文：执行 expression；任何 error 被捕获 → 写日志（含 backtrace）→
          重新 signal 指定 condition，并在 errstring 里附带原异常文本。
    展开形态：handler-case + 写文件 + (error condition :errstring ...)"
    `(handler-case 
	 ,expression
       (error (e)
  	 (let ((exceptionstr (format nil  "~&[~A] Error: ~A~%" (mysql-now) e))) 
	   (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				   :direction :output
				   :if-exists :append
				   :if-does-not-exist :create)
	     (format stream "~A. ~A" exceptionstr (sb-debug:list-backtrace)))
	   ;; return the exception.
	   (error ,condition :errstring (format nil "Caught error: ~A" e)))))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *nst-environment* :development) 
  ;; :development | :staging | :production
  (defmacro with-nst-debugger (&body body)
    "Debugger-centric NST execution boundary.
     - Development  : drop into debugger (full SLIME stack)
     - Staging      : log full stacktrace + re-signal
     - Production   : log sanitized + signal business condition
     中文：按 *nst-environment* 三种模式分别处理 error：
       :development  — 直接 invoke-debugger 进入 SBCL/SLIME 调试器
       :staging      — 写日志（含 backtrace）后 signal 原异常
       :production   — 仅写脱敏日志，对外 signal hhub-database-error 通用文案"
    `(handler-bind
         ((error
            (lambda (e)
	      (case *nst-environment*
                ;; ------------------------------------------------------------
                ;; DEVELOPMENT MODE
                ;; ------------------------------------------------------------
                (:development
                 ;; Let SBCL debugger take full control
                 (invoke-debugger e))
		;; ------------------------------------------------------------
                ;; STAGING MODE
                ;; ------------------------------------------------------------
                (:staging
                 (when (boundp '*HHUBBUSINESSFUNCTIONSLOGFILE*)
                   (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE*
                                           :direction :output
                                           :if-exists :append
                                           :if-does-not-exist :create)
                     (format stream "~&[~A] STAGING ERROR: ~A~%"
                             (mysql-now) e)
                     (when (find-package :sb-debug)
                       (funcall (intern "PRINT-BACKTRACE" :sb-debug)
                                :stream stream))))
                 (signal e))
		;; ------------------------------------------------------------
                ;; PRODUCTION MODE
                ;; ------------------------------------------------------------
                (:production
                 (when (boundp '*HHUBBUSINESSFUNCTIONSLOGFILE*)
                   (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE*
                                           :direction :output
                                           :if-exists :append
                                           :if-does-not-exist :create)
                     (format stream "~&[~A] PROD ERROR: ~A~%"
                             (mysql-now) (type-of e))))
                 (error 'hhub-database-error
                        :errstring "Unexpected system error occurred."))
		;; ------------------------------------------------------------
                ;; DEFAULT FALLBACK
                ;; ------------------------------------------------------------
                (otherwise
                 (invoke-debugger e))))))

       ,@body)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro with-nst-error-boundary ((condition &key (log-level :error) (rethrow t)) &body body)
    :description "Enterprise-grade NST error boundary. Separates logging, signaling and rethrow strategy.
    中文：企业级错误边界 —— 把 (logging / signal / abort-or-continue) 三个策略分离。
    参数：condition — 失败时对外抛出的 condition 类；
          log-level — 日志级别标签；rethrow — t 时触发 abort restart。
    提供 abort / continue 两个 restart-case，调用方可 invoke-restart 选择。"
    `(handler-bind
         ((error
            (lambda (e)
	      ;; Structured log entry
              (let ((exceptionstr
                      (format nil "~&[~A] [~A] ~A: ~A~%"
                              (mysql-now)
                              ,log-level
                              (type-of e)
                              e)))
		;; Centralized logging (no deep-layer hard dependency)
                (when (boundp '*HHUBBUSINESSFUNCTIONSLOGFILE*)
                  (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE*
                                          :direction :output
                                          :if-exists :append
                                          :if-does-not-exist :create)
                    (format stream "~A" exceptionstr)))
		;; Optional rethrow strategy
                (when ,rethrow
                  (invoke-restart 'abort))
		;; Signal domain-specific condition (Belnap compatible)
                (signal ,condition :errstring exceptionstr)))))
       (restart-case
           (progn ,@body)
	 (abort ()
           :report "Abort NST operation and propagate failure."
           (error ,condition :errstring "Operation aborted at NST boundary."))
	 (continue ()
           :report "Continue execution ignoring error."
           nil)))))


(defun check-null (value &optional (error-message "Null value encountered") (error-type 'null-value-error))
  "Safely checks if VALUE is null and signals an error if it is.
   
   Parameters:
   - VALUE: The value to check for null
   - ERROR-MESSAGE: Optional custom error message (default: 'Null value encountered')
   - ERROR-TYPE: Optional error type (default: 'null-value-error)
   
   Returns:
   - The original value if not null
   - Signals an error if value is null
   
   Example usage:
   (check-null some-value \"Expected non-null value for calculation\")"

  (when (null value)
    (error (make-condition error-type
                          :message error-message
                          :value value)))
  value)

;; Define a custom error condition
;; 自定义条件：携带 message + 触发它的 value，便于排错时打印实参。
(define-condition null-value-error (error)
  ((message :initarg :message :reader error-message)
   (value :initarg :value :reader error-value))
  (:report (lambda (condition stream)
             (format stream "~A. Value: ~S" 
                     (error-message condition) 
                     (error-value condition)))))

;; Helper macro for more concise null checking
;; check-null 的语法糖。
(defmacro ensure-not-null (value &optional message)
  `(check-null ,value ,message))

(defun find-caller-name-from-backtrace ()
  "Uses string parsing on SBCL's LIST-BACKTRACE to find the
   symbol name of the function that called the DB adapter.
   中文：通过解析 SBCL 的 LIST-BACKTRACE 字符串，找出"调 DB 适配器"的上层函数名。
         约定 frame 0 = 自己，frame 1 = log-critical-error，
         frame 2 = 适配器，frame 3 = 实际调用者（这里要返回的）。"
  (handler-case 
      ;; We need to know which frame holds the caller:
      ;; Frame 0: find-caller-name-from-backtrace
      ;; Frame 1: log-critical-error 
      ;; Frame 2: The adapter function (e.g., select-mock-data)
      ;; Frame 3: The function that called the adapter (THE CALLER WE WANT)
      (let* ((frame-to-inspect 3)
             (backtrace-list (sb-debug:list-backtrace))
             (frame-string (nth frame-to-inspect backtrace-list))) ; Get the 4th element (index 3)
        
        (if frame-string
            ;; Parse the string: Find the opening '(' and read the list head.
            ;; Example string: "  3: (CL-USER::MAIN-APP-FUNCTION 1)"
            (let* ((start-pos (position #\( frame-string :test #'char=)) 
                   (call-list (read-from-string (subseq frame-string start-pos))))
              (if (listp call-list)
                  (car call-list) ; Extract the first element (the function name)
                  :unknown-fun-object))
            :stack-too-shallow))
    (error (c)
      (format nil "Stack inspection error: ~A" c))))

(defun log-critical-error (status message &optional payload)
  "Logs a critical error, automatically including the function that initiated the DB call.
   中文：把一条关键错误日志打到 *standard-output*，自动附上发起方函数名（栈第 3 帧）。"
  (let ((caller (find-caller-name-from-backtrace)))
    (format t "~&[CRITICAL LOG ~A] Called by: ~A | ~A~%[Payload/Error]: ~A" 
            status 
            caller 
            message 
            payload)))

