;;; -*- Mode: Lisp; Package: DTRACE -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 调试用 DTRACE（详细 trace 工具）
;;;; 分层：平台基础
;;;; 文件：hhub/core/dtrace.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：CL 自带 trace/untrace 的"加详细版"替代，能在递归调用中显示缩进、
;;;;       展开函数实参、区分 defun / defmacro 入口、按层级画箭头。
;;;;       本文件改自 David S. Touretzky 1990 年《Common Lisp: A Gentle Introduction
;;;;       to Symbolic Computation》示例代码，保留原作者 API（dtrace / duntrace）。
;;;;
;;;; 主要导出（package :dtrace）：
;;;;   dtrace / duntrace                — 用户级宏（语法同 trace/untrace）
;;;;   *dtrace-print-length / -level / -circle / -pretty / -array*
;;;;
;;;; 关联：
;;;;   下游依赖：fetch-arglist 各实现（lucid/allegro/gclisp/kcl/cmu/通用）
;;;;   备注：与 ninestores 主代码低耦合，是开发期排错工具。
;;;; ============================================================================

;;; DTRACE is a portable alternative to the Common Lisp TRACE and UNTRACE
;;; macros.  It offers a more detailed display than most tracing tools.
;;;
;;; From the book "Common Lisp:  A Gentle Introduction to
;;;      Symbolic Computation" by David S. Touretzky.
;;; The Benjamin/Cummings Publishing Co., 1990.
;;;
;;; This is the generic version.  It should work in any legal Common Lisp.
;;; Revised August, 2003, to work with ANSI Common Lisp and Allegro v6.
;;;
;;; User-level routines:
;;;   DTRACE  - same syntax as TRACE
;;;   DUNTRACE - same syntax as UNTRACE

(defpackage :dtrace
  (:use :common-lisp)
  (:export dtrace duntrace
	   *dtrace-print-length* *dtrace-print-level*
	   *dtrace-print-circle* *dtrace-print-pretty*
	   *dtrace-print-array*))

(in-package :dtrace)	    

(eval-when (eval load)
  (shadowing-import '(dtrace duntrace) (find-package :common-lisp-user)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; DTRACE and subordinate routines.

(defparameter *dtrace-print-length* 7)
(defparameter *dtrace-print-level*  4)
(defparameter *dtrace-print-circle* t)
(defparameter *dtrace-print-pretty* nil)
(defparameter *dtrace-print-array* *print-array*)

(defvar *traced-functions* nil)
(defvar *trace-level* 0)

(defmacro dtrace (&rest function-names)
  "Turns on detailed tracing for specified functions.  Undo with DUNTRACE.
   中文：开启对指定函数（或宏）的详细追踪；不带参数时返回当前已追踪函数列表。"
  (if (null function-names)
      (list 'quote *traced-functions*)
      (list 'quote (mapcan #'dtrace1 function-names))))

(defun dtrace1 (name)
  "对单个函数名启用追踪：先撤销已有 trace，再按 defun/defmacro 走 trace-function 或 trace-macro。"
  (unless (symbolp name)
    (format *error-output* "~&~S is an invalid function name." name)
    (return-from dtrace1 nil))
  (unless (fboundp name)
    (format *error-output* "~&~S undefined function." name)
    (return-from dtrace1 nil))
  (eval `(untrace ,name))	;; if they're tracing it, undo their trace
  (duntrace1 name)		;; if we're tracing it, undo our trace
  (when (special-operator-p name)
    (format *error-output*
	    "~&Can't trace ~S because it's a special form." name)
    (return-from dtrace1 nil))
  (if (macro-function name)
      (trace-macro name)
      (trace-function name))
  (setf *traced-functions* (nconc *traced-functions* (list name)))
  (list name))

;;; The functions below reference DISPLAY-xxx routines that can be made
;;; implementation specific for fancy graphics.  Generic versions of
;;; these routines are defined later in this file.

(defmacro with-dtrace-printer-settings (&body body)
  "在受控的 *print-length*/level/circle/pretty/array 设置下执行 body，
   防止 trace 输出过长或被默认打印器截断成 #1=# 的循环引用。"
  `(let ((*print-length* *dtrace-print-length*)
	 (*print-level* *dtrace-print-level*)
	 (*print-circle* *dtrace-print-circle*)
	 (*print-pretty* *dtrace-print-pretty*)
	 (*print-array* *dtrace-print-array*))
     ,@body))

(defun trace-function (name)
  "把 name 绑定的 symbol-function 替换成"打印进入 → 调原函数 → 打印返回值"的包装闭包。
   原函数缓存在 (get name 'original-definition)，duntrace1 会还原。"
  (let* ((formal-arglist (fetch-arglist name))
	 (old-defn (symbol-function name))
	 (new-defn
	  #'(lambda (&rest argument-list)
	      (let ((result nil))
		(display-function-entry name)
		(let ((*trace-level* (1+ *trace-level*)))
		  (with-dtrace-printer-settings
		   (show-function-args argument-list formal-arglist))
		  (setf result (multiple-value-list
				(apply old-defn argument-list))))
		(display-function-return name result)
		(values-list result)))))
    (setf (get name 'original-definition) old-defn)
    (setf (get name 'traced-definition) new-defn)
    (setf (get name 'traced-type) 'defun)
    (setf (symbol-function name) new-defn)))

(defun trace-macro (name)
  "trace 宏：替换 macro-function 为打印展开过程的包装；与 trace-function 类似。"
  (let* ((formal-arglist (fetch-arglist name))
	 (old-defn (macro-function name))
	 (new-defn
	  #'(lambda (macro-args env)
	      (let ((result nil))
		(display-function-entry name 'macro)
		(let ((*trace-level* (1+ *trace-level*)))
		  (with-dtrace-printer-settings
		   (show-function-args macro-args formal-arglist))
		  (setf result (funcall old-defn macro-args env)))
	(display-function-return name (list result) 'macro)
		(values result)))))
    (setf (get name 'original-definition) old-defn)
    (setf (get name 'traced-definition) new-defn)
    (setf (get name 'traced-type) 'defmacro)
    (setf (macro-function name) new-defn)))

(defun show-function-args (actuals formals &optional (argcount 0))
  "把实参 actuals 与形参 formals 对齐打印；自动处理 &optional/&rest/&key/&aux。"
  (cond ((null actuals) nil)
	((null formals) (handle-args-numerically actuals argcount))
	(t (case (first formals)
	     (&optional (show-function-args
			 actuals (rest formals) argcount))
	     (&rest (show-function-args
		     (list actuals) (rest formals) argcount))
	     (&key (handle-keyword-args actuals))
	     (&aux (show-function-args actuals nil argcount))
	     (t (handle-one-arg (first actuals) (first formals))
		(show-function-args (rest actuals)
				    (rest formals)
				    (1+ argcount)))))))

(defun handle-args-numerically (actuals argcount)
  "形参用尽时按位置打印剩余实参（Arg-N = ...）。"
  (dolist (x actuals)
    (incf argcount)
    (display-arg-numeric x argcount)))

(defun handle-one-arg (val varspec)
  "处理一个形参-实参对；varspec 若是列表（&optional/&key 形式）取首项作为变量名。"
  (cond ((atom varspec) (display-one-arg val varspec))
	(t (display-one-arg val (first varspec))
	   (if (third varspec)
	       (display-one-arg t (third varspec))))))

(defun handle-keyword-args (actuals)
  "&key 部分实参的处理：按 keyword + value 成对打印，剩余打 Extra args。"
  (cond ((null actuals))
	((keywordp (first actuals))
	 (display-one-arg (second actuals) (first actuals))
	 (handle-keyword-args (rest (rest actuals))))
	(t (display-one-arg actuals "Extra args:"))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; DUNTRACE and subordinate routines.

(defmacro duntrace (&rest function-names)
  "Turns off tracing for specified functions.
   With no args, turns off all tracing.
   中文：撤销 dtrace；不带参数则撤销所有已追踪函数。"
  (setf *trace-level* 0)  ;; safety precaution
  (list 'quote
	(mapcan #'duntrace1 (or function-names *traced-functions*))))

(defun duntrace1 (name)
  "撤销单个函数/宏的追踪：从 *traced-functions* 移除，恢复 original-definition。
   若被追踪函数已被外部重定义则保留新定义、只清理 trace 元数据。"
  (unless (symbolp name)
    (format *error-output* "~&~S is an invalid function name." name)
    (return-from duntrace1 nil))
  (setf *traced-functions* (delete name *traced-functions*))
  (let ((orig-defn (get name 'original-definition 'none))
	(traced-defn (get name 'traced-definition))
	(traced-type (get name 'traced-type 'none)))
    (unless (or (eq orig-defn 'none)
		(not (fboundp name))
		(not (equal traced-defn  ;; did it get redefined?
			 (ecase traced-type
			   (defun (symbol-function name))
			   (defmacro (macro-function name))))))
      (ecase traced-type
	(defun (setf (symbol-function name) orig-defn))
	(defmacro (setf (macro-function name) orig-defn)))))
  (remprop name 'traced-definition)
  (remprop name 'traced-type)
  (remprop name 'original-definition)
  (list name))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Display routines.
;;;
;;; The code below generates vanilla character output for ordinary 
;;; displays.  It can be replaced with special graphics code if the
;;; implementation permits, e.g., on a PC you can use the IBM graphic
;;; character set to draw nicer-looking arrows.  On a color PC you 
;;; can use different colors for arrows, for function names, for 
;;; argument values, and so on.

(defparameter *entry-arrow-string* "----")
(defparameter *vertical-string*    "|   ")
(defparameter *exit-arrow-string*  " \\--")

(defparameter *trace-wraparound* 15)

(defun display-function-entry (name &optional ftype)
  "在 *trace-output* 输出"进入函数"箭头与名字。ftype='macro 时附加 'macro 标签。"
  (space-over)
  (draw-entry-arrow)
  (format *trace-output* "Enter ~S" name)
  (if (eq ftype 'macro)
      (format *trace-output* " macro")))

(defun display-one-arg (val name)
  "打印一个 (name = val) 行；name 为 keyword/string/symbol 时格式略有差异。"
  (space-over)
  (format *trace-output*
	  (typecase name
	    (keyword "  ~S ~S")
	    (string  "  ~A ~S")
	    (t "  ~S = ~S"))
	  name val))

(defun display-arg-numeric (val num)
  "打印一个无名实参（Arg-N = val），用于形参缺失时。"
  (space-over)
  (format *trace-output* "  Arg-~D = ~S" num val))

(defun display-function-return (name results &optional ftype)
  "打印"退出"箭头 + 返回值；多值时用 'values' 串联。"
  (with-dtrace-printer-settings
    (space-over)
    (draw-exit-arrow)
    (format *trace-output* "~S ~A"
	    name
	    (if (eq ftype 'macro) "expanded to" "returned"))
    (cond ((null results))
	  ((null (rest results)) (format *trace-output* " ~S" (first results)))
	  (t (format *trace-output* " values ~{~S, ~}~s"
		     (butlast results)
		     (car (last results)))))))

(defun space-over ()
  "按 *trace-level* 缩进竖线，过深时按 *trace-wraparound* 取模回绕。"
  (format *trace-output* "~&")
  (dotimes (i (mod *trace-level* *trace-wraparound*))
    (format *trace-output* "~A" *vertical-string*)))

(defun draw-entry-arrow ()
  "画"进入"箭头串。"
  (format *trace-output* "~A" *entry-arrow-string*))

(defun draw-exit-arrow ()
  "画"退出"箭头串。"
  (format *trace-output* "~A" *exit-arrow-string*))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; The function FETCH-ARGLIST is implementation dependent.  It 
;;; returns the formal argument list of a function as it would 
;;; appear in a DEFUN or lambda expression, including any lambda
;;; list keywords.  Here are versions of FETCH-ARGLIST for three
;;; Lisp implementations.

;;; Minimal generic version
#-(or lucid allegro gclisp kcl cmu)
  (defun fetch-arglist (fn)
    (declare (ignore fn))
    nil)

;;; Lucid version
#+lucid
  (defun fetch-arglist (fn)
    (system::arglist fn))


#+allegro
  (defun fetch-arglist (fn)
    (excl::arglist fn))

;;; GCLisp 1.1 version
#+gclisp
  (defun fetch-arglist (fn)
    (if (macro-function fn)
	'(&rest "Form =")
	(lambda-list fn)))

;;; KCL version
#+kcl
(defun fetch-arglist (fn)
  (let ((x (symbol-function fn)))
    (cond ((atom x) nil)
	  ((eq (first x) 'macro) (list '&rest "Form ="))
	  (t (third x)))))

;;; CMU Common Lisp version.  This version looks in a symbol's
;;; function cell and knows how to take apart lexical closures
;;; and compiled code objects found there.
#+cmu
  (defun fetch-arglist (x &optional original-x)
    (cond ((symbolp x) (fetch-arglist (symbol-function x) x))
	  ((compiled-function-p x)
	   (read-from-string
	    (lisp::%primitive header-ref x
			      lisp::%function-arg-names-slot)))
	  ((listp x) (case (first x)
		       (lambda (second x))
		       (lisp::%lexical-closure% (fetch-arglist (second x)))
		       (system:macro '(&rest "Form ="))
		       (t '(&rest "Arglist:"))))
	  (t (cerror (format nil
                        "Use a reasonable default argument list for ~S"
		        original-x)
		"Unkown object in function cell of ~S:  ~S" original-x x)
	     '())))
