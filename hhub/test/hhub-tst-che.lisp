;;; hhub-tst-che.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-x
;;;; ============================================================================
;;;; 模块：test —— 黄金比缓存 / 复数 OTP 实验
;;;; 分层：测试套件（实验性独立工具，不依赖 DB / 网络）
;;;; 文件：hhub/test/hhub-tst-che.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：以"黄金角螺旋"上的复数为键缓存闭包；同时实验一个基于复数 + 系统时钟
;;;;       的 OTP 生成算法（generate-complex-otp）。
;;;;       推测：文件名 *-tst-che.lisp 暗示为 checkout 测试位，但当前内容
;;;;       与 checkout 无关，实为算法 PoC，可能是 OTP 路径的探索性实现。
;;;;
;;;; 主要导出：
;;;;   *golden-cache* / *golden-ratio* / *golden-angle*  — 全局参数
;;;;   golden-rotate / cache-function / retrieve-nearest-function  — 复数键缓存操作
;;;;   next-golden-number / random-complex-in-disk          — 复数生成
;;;;   generate-complex-otp                                 — n 位 OTP（4-9 位）
;;;;   goldencacheinit                                      — 预填 1 万条缓存示例
;;;;
;;;; 关联：
;;;;   上游使用方：暂未在主流程引用（推测）
;;;;   下游依赖：仅 Common Lisp 标准库 / SBCL get-internal-real-time
;;;; ============================================================================

(in-package :nstores)

(defvar *golden-cache* (make-hash-table :test 'eql)) ;; 键=复数（黄金螺旋点），值=闭包
(defparameter *golden-ratio* (/ (+ 1 (sqrt 5)) 2))  ;; φ ≈ 1.618
(defparameter *golden-angle* (* 2 pi (- *golden-ratio* 1)))  ;; 2π(φ - 1) ≈ 137.5°

(defun hash-table-keys (ht)
  "返回 hash-table ht 的全部键（顺序不定）。"
  (let ((keys nil))
    (maphash
     #'(lambda (k v)
         (declare (ignore v))
         (push k keys))
     ht)
    keys))

(defun golden-rotate (z)
  "Rotates a complex number by the golden angle (~137.5 degrees).
   中文：把复数 z 沿黄金角旋转一次（即乘以 e^{i·黄金角}）。"
  (* z (exp (* #C(0 1) (* 2 pi (- (/ (sqrt 5) 2) 1))))))  ;; Rotation using golden ratio

(defun cache-function (fn key)
  "Stores a function (closure) in the cache with a golden-ratio rotated key.
   中文：把闭包 fn 以复数 key 存入 *golden-cache*。"
  (setf (gethash key *golden-cache*) fn))


(defun retrieve-golden-nearest (query-z stored-points)
  "Find the nearest stored complex number to query-z in stored-points.
   中文：在已存复数集合中找到欧氏距离最近的一个；返回其复数键。"
  (reduce (lambda (closest current)
            (if (< (abs (- query-z current)) (abs (- query-z closest)))
                current
                closest))
          stored-points))

(defun retrieve-nearest-function (query-z)
  "Find and execute the function closest to query-z.
   中文：取 *golden-cache* 中离 query-z 最近的键所对应的闭包并 funcall。"
  (let* ((stored-points (hash-table-keys *golden-cache*))
         (nearest (retrieve-golden-nearest (next-golden-number query-z) stored-points))
         (func (gethash nearest *golden-cache*)))
    
    (if func
        (funcall func)
        (format t "No function found near ~A~%" query-z))))

(defun rotate-golden-cache ()
  "Rotates all cached function keys by the golden ratio angle.
   中文：对 *golden-cache* 中所有键统一旋转一次黄金角。
   注意：当前实现用 mapcar 处理 hash-table 会得到 nil（推测：是 bug，应改为遍历重建）。"
  (setf *golden-cache*
        (mapcar (lambda (item)
                  (cons (golden-rotate (car item)) (cdr item)))
                *golden-cache*)))

(defun goldencacheinit ()
  "中文：示例初始化器——预先把 1..10000 在黄金螺旋上的复数点
   各注册一个打印型闭包，用于压测/可视化。"
  ;; Example Usage:
  
    ;; Store 10,000 functions in the golden spiral
    (loop for n from 1 to 10000 do
      (let ((cmplxnum (next-golden-number n)))
	(cache-function (lambda () (format t "Executing function with key  ~d" cmplxnum)) cmplxnum)))
      
    ;;(print "Before Golden Rotation:")
    ;;(print *golden-cache*)
    ;;(rotate-golden-cache)  ;; Rotate using the golden ratio
    ;;(print "After Golden Rotation:")
    ;;(print *golden-cache*)
    
    ;; Retrieve and execute the nearest function to (1+0i)
  ;;(retrieve-nearest-function (next-golden-number k))
  )

(defun next-golden-number (n)
  "Generate the nth complex number in the golden spiral sequence, seeded from z = 1 + 0i.
   中文：黄金螺旋的第 n 个复数点，半径 sqrt(n)，幅角 n×黄金角。"
  (let* ((r (sqrt n))  ;; Radius grows as sqrt(n)
         (theta (* n *golden-angle*))  ;; Rotation by golden angle
         (x (* r (cos theta)))
         (y (* r (sin theta))))
    (complex x y)))  ;; Return complex number

;; Example usage:
;; (next-golden-number 1)  ;; Generates first point in the golden spiral
;; (next-golden-number 50000)  ;; Generates the 50000th point


(defun random-complex-in-disk (R)
  "Generate a uniformly random complex number within a disk of radius R.
   中文：在半径 R 的圆盘内均匀采样一个复数（用 sqrt(u) 校正半径分布）。"
  (let* ((theta (* 2 pi (random 1.0))) ; random angle in [0, 2π)
         (u (random 1.0))               ; random number in [0, 1)
         (r (* R (sqrt u)))             ; radius scaled by sqrt(u) for uniformity
         (x (* r (cos theta)))
         (y (* r (sin theta))))
    (complex x y)))

(defun generate-complex-otp (n)
  "Generate an n-digit OTP (n between 4 and 9) using a complex number approach.
It combines a random complex number (from a unit disk) with a time-based component.
   中文：基于复数 + 高精度时间产生 n 位 OTP（4-9 位），按 10^n 取模并左侧补零。
   注意：此为实验算法，未经过密码学评审；正式 OTP 见 core/nst-bl-otp.lisp。"
  (unless (and (integerp n) (>= n 4) (<= n 9))
    (error "n must be an integer between 4 and 9."))
  (let* ((R 1.0)
         ;; Generate a random complex number within the unit disk.
         (z-rand (random-complex-in-disk R))
         ;; Get high-resolution time: get-internal-real-time returns ticks.
         (time-ticks (get-internal-real-time))
         (time-resolution (get-internal-real-time-resolution))
         (time-seconds (/ time-ticks time-resolution))
         ;; Use the fractional part of time as a number in [0,1)
         (fraction (mod time-seconds 1.0))
         ;; Represent time as a complex number (same value for real and imaginary parts)
         (z-time (complex fraction fraction))
         ;; Combine the randomness by multiplying the two complex numbers.
         (z (* z-rand z-time))
         ;; Shift the result so that the real and imaginary parts are positive.
         (x (+ (realpart z) 1.0))
         (y (+ (imagpart z) 1.0))
         ;; Combine the two components into a single number.
         (num (floor (+ (* x 1000) (* y 1000)))))
    ;; Ensure the number has exactly n digits by taking modulo 10^n and formatting with leading zeros.
    (let* ((modulus (expt 10 n))
           (otp (mod num modulus)))
      (format nil "~v,'0D" n otp))))

;; Example usage:
;;(format t "4-digit OTP: ~a~%" (generate-complex-otp 4))
;;(format t "6-digit OTP: ~a~%" (generate-complex-otp 6))
;;(format t "8-digit OTP: ~a~%" (generate-complex-otp 8))

;; does not work the way designed.
;; 中文：原作者注解——实现并未达到设计意图（见函数体的 random 除数显然不合理）。
(defun get-internal-real-time-resolution ()
  "推测：意图返回 internal-time-units-per-second，但当前实现用 random 做除数，
   不能给出稳定的分辨率。SBCL 中应使用常量 internal-time-units-per-second。"
  (let ((start (get-internal-real-time)))
    (/ (- start (get-universal-time) )  ;; Calculate difference between two calls
       (random 10)))) ; Divide by a known small time interval
