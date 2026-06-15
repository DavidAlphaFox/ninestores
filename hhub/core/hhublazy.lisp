;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 惰性求值
;;;; 分层：平台基础
;;;; 文件：hhub/core/hhublazy.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：提供"按需计算"的惰性序列工具：lazy / force / lazy-cons / lazy-car
;;;;       / lazy-cdr / lazy-mapcar / take 等。可用于无穷流（如自然数 *integers*）。
;;;;       源代码思路出自 Conrad Barski《Land of Lisp》一书。
;;;;
;;;; 主要导出：
;;;;   lazy / force                 — 创建/强制求值惰性单元
;;;;   lazy-cons / lazy-car/cdr     — 惰性 cons 单元
;;;;   make-lazy                    — 普通 list → 惰性 list
;;;;   take / take-all              — 取前 n 项 / 全部强制求值
;;;;   lazy-mapcar / lazy-mapcan / lazy-find-if / lazy-nth
;;;;   *integers*                   — 全体正整数惰性流
;;;;
;;;; 关联：
;;;;   上游使用方：少量需要惰性流的工具/示例代码
;;;; ============================================================================

(in-package :nstores)
(defmacro lazy (&body body)
  "惰性单元构造宏。展开成一个闭包，首次调用时计算 body，结果缓存于内部变量。
   返回的闭包可用 force 触发求值。"
  (let ((forced (gensym))
	(value (gensym)))
    `(let ((,forced nil)
	   (,value nil))
       (lambda ()
	 (unless ,forced
	   (setf ,value (progn ,@body))
	   (setf ,forced t))
	 ,value))))

(defun force (lazy-value)
  "强制求值：调用 lazy 包装的闭包，得到实际值。"
  (funcall lazy-value))

(defmacro lazy-cons (a d)
  "构造惰性 cons：cons 形式整体被 lazy 包装，car/cdr 在被访问时才计算。"
  `(lazy (cons ,a ,d)))

(defun lazy-car (x)
  "取惰性 cons 的 car（先 force 再 car）。"
  (car (force x)))

(defun lazy-cdr (x)
  "取惰性 cons 的 cdr。"
  (cdr (force x)))

(defparameter *integers*
  ;; 1, 2, 3, ... 的无穷惰性流，按需展开。
  (labels ((f (n)
	      (lazy-cons n (f (1+ n)))))
	  (f 1)))

(defun lazy-nil ()
  "返回一个惰性 nil（用作惰性列表的空尾）。"
  (lazy nil))

(defun lazy-null (x)
  "判断惰性列表是否为空。"
  (not (force x)))

(defun make-lazy (lst)
  "把普通 list 转成惰性 list（每个 cons 都被 lazy 包装，按需展开）。"
  (lazy (when lst
          (cons (car lst) (make-lazy (cdr lst))))))

(defun take (n lst)
  "取惰性 list 前 n 项为普通 list；遇到惰性 nil 提前结束。"
  (unless (or (zerop n) (lazy-null lst))
    (cons (lazy-car lst) (take (1- n) (lazy-cdr lst)))))

(defun take-all (lst)
  "强制取出整个惰性列表为普通 list。注意：对无穷流会死循环。"
  (unless (lazy-null lst)
    (cons (lazy-car lst) (take-all (lazy-cdr lst)))))

(defun lazy-mapcar (fun lst)
  "对惰性列表的每个元素应用 fun，结果仍是惰性列表。"
  (lazy (unless (lazy-null lst)
          (cons (funcall fun (lazy-car lst))
                (lazy-mapcar fun (lazy-cdr lst))))))

(defun lazy-mapcan (fun lst)
  "类似 mapcan 的惰性版本：fun 返回惰性 list，结果展平。"
  (labels ((f (lst-cur)
	      (if (lazy-null lst-cur)
                  (force (lazy-mapcan fun (lazy-cdr lst)))
                (cons (lazy-car lst-cur) (lazy (f (lazy-cdr lst-cur)))))))
    (lazy (unless (lazy-null lst)
	    (f (funcall fun (lazy-car lst)))))))

(defun lazy-find-if (fun lst)
  "在惰性列表中找到第一个满足 fun 的元素；找不到返回 nil。
   备注：fun 为真的元素会被原样返回（不是惰性单元）。"
  (unless (lazy-null lst)
    (let ((x (lazy-car lst)))
      (if (funcall fun x)
          x
        (lazy-find-if fun (lazy-cdr lst))))))

(defun lazy-nth (n lst)
  "取惰性列表第 n 个元素（从 0 计数）。"
  (if (zerop n)
      (lazy-car lst)
    (lazy-nth (1- n) (lazy-cdr lst))))
