;;; memoize.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— Memoize 缓存装饰器
;;;; 分层：平台基础
;;;; 文件：hhub/core/memoize.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：函数级别的记忆化（memoization）工具。给已有 defun 加缓存层，
;;;;       同时把被 memoize 的函数登记到 *HHUBMEMOIZEDFUNCTIONS* 以便统一清理。
;;;;       源代码出自 Norvig 《Paradigms of AI Programming》(1991) 并稍作改造。
;;;;
;;;; 主要导出：
;;;;   defun-memo       — 直接定义 memoized 函数的语法糖
;;;;   memo             — 用闭包把任意函数包装成 memo 版
;;;;   memoize          — 替换全局 fn 为 memo 版，并登记
;;;;   clear-memoize    — 清空指定函数的缓存表
;;;;
;;;; 关联：
;;;;   上游使用方：通用业务函数（按需 memoize 高成本只读查询）
;;;;   下游依赖：*HHUBMEMOIZEDFUNCTIONS*（在 dod-ini-sys.lisp 声明）
;;;; ============================================================================
(in-package :nstores)

;;;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;;;; Code from Paradigms of AI Programming
;;;; Copyright (c) 1991 Peter Norvig
;;; ==============================

;;;; The Memoization facility:

(defmacro defun-memo (fn args &body body)
  "Define a memoized function.
   中文：定义函数后立即对其进行 memoize 替换。
   展开形态：(memoize (defun fn args . body))。"
  `(memoize (defun ,fn ,args . ,body)))

(defun memo (fn &key (key #'first) (test #'eql) name)
  "Return a memo-function of fn.
   中文：返回 fn 的记忆化包装闭包。
   参数：key — 从入参列表取缓存键的函数；test — 哈希等价测试；
         name — 把内部哈希表挂到该符号的 plist :memo 槽，便于外部清理。
   备注：内部用 alist + hash-table 双层结构（保留 Norvig 原版结构）。"
  (let ((table (make-hash-table :test test))
	(alist nil)
	(count 0))
    (setf (get name :memo) table)
    #'(lambda (&rest args)
	(let* ((k (funcall key args))
	       (j (cdr (assoc k alist :test #'eql))))
	  (format t "~A" args)
	  (setf count (incf count))
	  (multiple-value-bind (val found-p)
              (gethash j table)
            (if found-p
		val
		;;else
		(progn
		  (setf alist (acons k count alist))
		  (setf (gethash count table) (apply fn args)))))))))
	
(defun memoizekeyfunc (args)
  "通用 :key 函数：从 args 中取 (item alist) 形式，返回 (cdr (assoc item alist))。
   用于 memo-fn 在 alist 类参数上使用 equal 比较。"
  (let ((item (first args))
	(alist (second args)))
    (cdr (assoc item alist :test 'equal))))


(defun memoize (fn-name &key (key #'first) (test #'eql))
  "Replace fn-name's global definition with a memoized version.
   中文：把符号 fn-name 的全局函数替换为 memo 版本，并登记到全局列表。
   副作用：先清掉该函数的旧缓存；setf symbol-function；
           append 到 *HHUBMEMOIZEDFUNCTIONS*（注意此处用 append 而非 push）。"
  (clear-memoize fn-name)
  (remove fn-name *HHUBMEMOIZEDFUNCTIONS*)
  (setf (symbol-function fn-name)
        (memo (symbol-function fn-name)
              :name fn-name :key key :test test))
  (setf *HHUBMEMOIZEDFUNCTIONS* (append (list fn-name) *HHUBMEMOIZEDFUNCTIONS*)))

(defun clear-memoize (fn-name)
  "Clear the hash table from a memo function.
   中文：清空指定 memoized 函数的缓存表，并将其从全局登记表里移除。
   备注：表挂在 (get fn-name 'memo)；不存在时静默无操作。"
  (let ((table (get fn-name 'memo)))
    (when table (clrhash table))
    (delete fn-name *HHUBMEMOIZEDFUNCTIONS* :test 'equal)))


