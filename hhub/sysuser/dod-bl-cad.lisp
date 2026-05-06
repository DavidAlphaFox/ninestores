; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：sysuser —— Company Admin（CAD）业务函数
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/sysuser/dod-bl-cad.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：CAD（公司管理员）专用的少量产品管理动作 —— 生成对外分享 URL、
;;;;       审批/拒绝商品上架。
;;;;
;;;; 主要导出：
;;;;   generate-product-ext-url   — 把 (tenant-id, product-id) 编 base64 拼成访客可访问的商品详情 URL
;;;;   approve-product            — CAD 审批通过：approved-flag='Y' / approval-status='APPROVED'
;;;;   reject-product             — CAD 审批拒绝：approved-flag='N' / approval-status='REJECTED'
;;;;
;;;; 关联：
;;;;   上游使用方：sysuser/dod-ui-cad.lisp（CAD 后台审批控制器）
;;;;   下游依赖：products/dod-bl-prd.lisp（select-product-by-id / update-prd-details）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun generate-product-ext-url (product)
  :description "Generates an external URL for a product, which can be shared with external entities.
   中文：把商品的 tenant-id 与 row-id 拼成 CSV，再做 base64 编码，最终生成
         '<siteurl>/hhub/hhubprddetailsforguestcust?key=<base64>' 的访客详情链接。
   参数：product — dod-prd-master 实例。
   返回：可分享的完整 URL 字符串。"
  (let* ((tenant-id (slot-value product 'tenant-id))
	 (prd-id (slot-value product 'row-id))
	 (param-csv (format nil "tenant-id,product-id~C~A,~A" #\linefeed tenant-id prd-id))
	 (param-base64 (cl-base64:string-to-base64-string param-csv)))
    (format nil "~A/hhub/hhubprddetailsforguestcust?key=~A" *siteurl* param-base64)))


(defun approve-product (id description company)
  "CAD 审批通过商品上架。
   将 approved-flag 置为 'Y'，approval-status 置为 'APPROVED'，并把审批意见写入 description。
   参数：id — 商品 row-id；description — 审批批注；company — 当前租户公司实例。
   副作用：UPDATE dod-prd-master。"
  (let ((product (select-product-by-id id company)))
    (if product
	(progn (setf (slot-value product 'approved-flag) "Y")
	       (setf (slot-value product 'approval-status) "APPROVED")
	       (setf (slot-value product 'description) description)
	       (update-prd-details product)))))

(defun reject-product (id description company)
  "CAD 审批拒绝商品。approved-flag='N' / approval-status='REJECTED'，并将拒绝原因写入 description。
   参数：id — 商品 row-id；description — 拒绝原因；company — 当前租户公司实例。
   副作用：UPDATE dod-prd-master。"
  (let ((product (select-product-by-id id  company)))
    (if product
	(progn (setf (slot-value product 'approved-flag) "N")
	       (setf (slot-value product 'approval-status) "REJECTED")
	       (setf (slot-value product 'description) description)
	       (update-prd-details product)))))

