;;; dod-ui-rol.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 角色 UI 辅助
;;;; 分层：UI 控制器/视图层
;;;; 文件：hhub/core/dod-ui-rol.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：提供角色（dod-roles）的 HTML 渲染辅助函数（目前仅一个下拉框）。
;;;;
;;;; 主要导出：
;;;;   role-dropdown   — 渲染角色下拉控件
;;;;
;;;; 关联：
;;;;   上游使用方：各注册/分配角色页面（CAD/OPR 后台）
;;;;   下游依赖：hhub-get-cached-roles（core 缓存）、with-html-dropdown
;;;; ============================================================================
(in-package :nstores)

(defun role-dropdown (controlname &optional selectedkey)
  "渲染所有可选角色为 <select> 下拉控件。
   参数：controlname — 表单字段 name；selectedkey — 默认选中项，nil 时取首项。
   返回：cl-who 输出（直接写入响应流）。
   备注：从内存缓存 hhub-get-cached-roles 读取角色列表，避免每次查库。"
  (let* ((rolelist (hhub-get-cached-roles))
	 (rolenameslist (mapcar (lambda (item)
				  (slot-value item 'name)) rolelist))
	 (roleshash (make-hash-table)))
    (mapcar (lambda (key) (setf (gethash key roleshash) key)) rolenameslist)
    (with-html-dropdown controlname roleshash  (if (not selectedkey) (car rolenameslist) selectedkey))))
