;;; hhub-tst-flupload.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— 文件上传 / S3 删除冒烟测试
;;;; 分层：测试套件（集成测试，依赖 AWS S3）
;;;; 文件：hhub/test/hhub-tst-flupload.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：验证 vendor 维度的 S3 对象删除流程。固定使用 vendor-id=1、tenant-id=2
;;;;       的演示数据。
;;;;
;;;; 主要导出：
;;;;   test-file-delete-s3bucket  — 触发一次真实的 S3 删除请求
;;;;
;;;; 关联：
;;;;   下游依赖：vendor-delete-files-s3bucket、select-vendor-by-id、select-company-by-id
;;;; ============================================================================

(in-package :nstores)

(defun test-file-delete-s3bucket (object-id objectname)
  ;; 集成测试：会真正调用 AWS S3 API，执行后对象不可恢复。
  ;; 参数：object-id — 业务对象主键；objectname — 资源类型名（"VENDOR"/"PRODUCT" 等）。
  (let* ((vendor (select-vendor-by-id 1))
	(company (select-company-by-id 2))
	(vendor-id (slot-value vendor 'row-id))
	(tenant-id (slot-value company 'row-id)))
    (vendor-delete-files-s3bucket objectname object-id vendor-id tenant-id)))

