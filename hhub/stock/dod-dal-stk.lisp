;;; dod-dal-stk.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：stock 库存
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/stock/dod-dal-stk.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：库存 DAL 占位文件。当前文件几乎为空（仅含 (in-package :nstores)）。
;;;;       推测：库存逻辑早期分散到 products / warehouse 两个模块的 view-class
;;;;       中，本目录保留下来作为后续抽离 stock 实体（如 SKU 库存数量、移库
;;;;       台账）的预留位置。
;;;;
;;;; 主要导出：
;;;;   （无）
;;;;
;;;; 关联：
;;;;   上游使用方：暂无；ASDF 系统中如未列出该文件，则不会被加载。
;;;;   下游依赖：core 平台基础。
;;;; ============================================================================

(in-package :nstores)


