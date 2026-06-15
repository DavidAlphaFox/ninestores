;;; dod-sto-zip.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：根目录工具 —— 邮编值对象
;;;; 分层：平台基础（独立小工具，未挂入主编译列表）
;;;; 文件：hhub/dod-sto-zip.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义一个最小化的 pincode 值对象（邮编 + 城市 + 州 + 国家）以及
;;;;       一个把所有槽初始化为 nil 的构造器。
;;;;       推测：早期版本的邮编结构占位，正式邮编模型已迁移到
;;;;       core/nst-dal-pincodes.lisp 与 core/nst-bl-pincodes.lisp。
;;;;
;;;; 主要导出：
;;;;   pincode        — 值对象类
;;;;   init-pincode   — 返回一个空 pincode 实例
;;;;
;;;; 关联：
;;;;   上游使用方：当前未在 package/compile.lisp 中编译，疑似遗留
;;;;   下游依赖：无
;;;; ============================================================================

(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 类：pincode
;; 含义：邮编值对象，非持久化（无 db-kind 标注，并非 view-class）。
;; 槽：pincode/city/state/country —— 全部为字符串（推测）。
;; ----------------------------------------------------------------------------
(defclass pincode ()
  ((pincode
    :accessor pincode
    :initarg pincode)
   (city
    :accessor city
    :initarg city)
   (state
    :accessor state
    :initarg state)
   (country
    :accessor country
    :initarg country)))

(defun init-pincode ()
  "构造一个所有槽均为 nil 的空 pincode 实例。返回：pincode 实例。"
  (let ((pincode-inst (make-instance 'pincode
				     :pincode nil
				     :city nil
				     :state nil
				     :country nil)))
    pincode-inst))
     
    


	

  
