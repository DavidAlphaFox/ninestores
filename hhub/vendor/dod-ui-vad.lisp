;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— 卖家可用日（Vendor Availability Day）UI
;;;; 分层：UI（控制器/视图层）
;;;; 文件：hhub/vendor/dod-ui-vad.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：vendor availability day 的 UI 控制器/视图占位文件。
;;;;       目前仅做 in-package 与 SQL reader 语法启用，未实现任何控制器；
;;;;       推测：未来会承载 com-hhub-transaction-* 形式的可用日管理控制器。
;;;;
;;;; 主要导出：（暂无）
;;;;
;;;; 关联：
;;;;   上游使用方：（暂无）
;;;;   下游依赖：vendor/dod-bl-vad.lisp（vendor availability day 业务逻辑）、
;;;;             vendor/dod-dal-vad.lisp（实体）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



