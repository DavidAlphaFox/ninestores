;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— Web REPL 安全求值后端
;;;; 分层：BL（业务逻辑层；独立 :nstores.repl 包）
;;;; 文件：hhub/vendor/nst-bl-vwebrepl.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：为 vendor 提供受限制的浏览器内 REPL（前端发来的 S-表达式字符串）。
;;;;       仅放行白名单符号，禁止 DEFUN/EVAL/LOAD 等危险操作。
;;;;       推测：被 vendor 在线设置面板调用，配合 nst-bl-vaisettings.lisp 使用。
;;;;       注意：本文件单独建立 :nstores.repl 包，与主包 :nstores 不同；
;;;;             末尾对 db: 命名空间的引用是占位（仍待真实持久化层接入）。
;;;;
;;;; 主要导出：
;;;;   evaluate-safe         —— 入口：解析并执行受限 S-表达式
;;;;   *allowed-symbols*     —— 白名单符号列表
;;;;
;;;; 关联：
;;;;   上游使用方：vendor Web REPL 控制器（推测）。
;;;;   下游依赖：占位 db: 接口（待接入真正持久化）。
;;;; ============================================================================

;; backend/repl-handler.lisp

(defpackage :nstores.repl
  (:use :cl)
  (:export #:evaluate-safe #:*allowed-symbols*))

(in-package :nstores.repl)

;; 仅放行的白名单符号——只能调用以下 setting 操作命令
(defparameter *allowed-symbols*
  '(get-setting set-setting list-settings 
    validate-setting export-settings import-settings
    reset-setting describe-setting help))

;; 禁止出现的子串模式（与前端拦截规则保持一致）；任意命中即拒绝执行
(defparameter *forbidden-patterns*
  '("DEFUN" "DEFMACRO" "EVAL" "COMPILE" "DEFPACKAGE" 
    "IN-PACKAGE" "RUN-PROGRAM" "OPEN" "DELETE-FILE" 
    "LOAD" "REQUIRE" "FUNCALL" "APPLY" "MAKE-THREAD"))

(defun check-forbidden (code-string)
  "Returns T if code contains forbidden patterns.
   中文：扫描代码字符串（已转大写）是否包含 *forbidden-patterns* 中任何模式，
   命中则返回 T。"
  (some (lambda (pattern)
          (search pattern (string-upcase code-string)))
        *forbidden-patterns*))

(defun evaluate-safe (code-string seller-id)
  "Safely evaluate user code in restricted environment.
   中文：vendor Web REPL 入口。流程：
     1) 先按 *forbidden-patterns* 黑名单拒绝；
     2) read-from-string 解析为 S-表达式；
     3) 命令必须在 *allowed-symbols* 白名单内才执行；
     4) 任何错误均捕获包成 (:error \"...\") 返回。
   返回：(:success result) 或 (:error msg)。"
  (handler-case
      (progn
        ;; Security check
        (when (check-forbidden code-string)
          (return-from evaluate-safe 
            (list :error "Security: Forbidden operation")))
        
        ;; Parse s-expression
        (let* ((expr (read-from-string code-string))
               (cmd (first expr))
               (args (rest expr)))
          
          ;; Validate command is in whitelist
          (unless (member cmd *allowed-symbols*)
            (return-from evaluate-safe
              (list :error (format nil "Unknown command: ~A" cmd))))
          
          ;; Execute in safe environment
          (let ((result (apply cmd args)))
            (list :success result))))
    
    (error (e)
      (list :error (format nil "Error: ~A" e)))))

;; ----------------------------------------------------------------------------
;; 白名单命令实现（占位/桩；db: 包尚未在本文件定义）
;; ----------------------------------------------------------------------------
(defun get-setting (key)
  "Get setting value from database.
   中文：取当前 seller 名下指定 key 的设置值。"
  (db:fetch-setting *current-seller-id* key))

(defun set-setting (key value)
  "Set setting value in database.
   中文：写入设置。返回 T 表示成功（实际持久化由 db: 实现）。"
  (db:update-setting *current-seller-id* key value)
  t)

(defun list-settings (&optional category)
  "List all settings or by category.
   中文：列出当前 seller 的全部设置；传 category 时按域过滤。"
  (db:fetch-all-settings *current-seller-id* :category category))

;; ... implement other commands
