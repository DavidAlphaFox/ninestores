;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 系统级业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/dod-bl-sys.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：系统级零散功能 —— ABAC/IAM 缓存刷新、币种缓存、印度 GST 邦代码、
;;;;       发票通用条款字符串。
;;;;
;;;; 主要导出：
;;;;   refreshiamsettings              — 重建 ABAC 全局缓存（策略热更新入口）
;;;;   get-system-currencies-ht        — 启动时读 dod-currncy 装哈希表
;;;;   get-currency-html-symbol        — 取币种 HTML 符号（如 &#8377;）
;;;;   get-currency-fontawesome-symbol — 取币种 FontAwesome 图标
;;;;   init-gst-statecodes             — 初始化印度 GST 邦代码表（哈希表）
;;;;   init-gst-invoice-terms          — 设置发票标准条款 *NSTGSTINVOICETERMS*
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-ini-sys.lisp 启动期 / 发票模块 / UI 渲染
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

(defun refreshiamsettings ()
  "重建 ABAC/IAM 全局缓存 *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*。
   超管在 PAP 修改策略/属性/事务后必须调用本函数才能生效。"
  (setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS* (hhub-gen-globally-cached-lists-functions)))

(defun get-system-currencies-ht ()
  :documentation "This function stores all the currencies in a hashtable. The Key = country, Value = list of currency, code and symbol.
   中文：把 dod-currncy 表全表装成哈希表 country → (currency code curr-symbol)。
   启动时调用一次，运行期直接走内存缓存。"
  (let ((ht (make-hash-table :test 'equal))
	(currencies (clsql:select 'dod-currncy :caching *dod-database-caching* :flatp t )))
    (loop for curr in currencies do
      (let ((key (slot-value curr 'country))
	    (currency (slot-value curr 'currency))
	    (code (slot-value curr 'code))
	    (curr-symbol (slot-value curr 'curr-symbol)))
	   (setf (gethash key ht) (list currency code curr-symbol))))
    ; Return  the hash table. 
    ht))

(defun get-currency-html-symbol (currency)
  "按币种代码查 HTML 实体符号（用于网页渲染）。"
  (gethash currency (hhub-get-cached-currency-html-symbols-ht)))

(defun get-currency-fontawesome-symbol (currency)
  "按币种代码查对应的 FontAwesome 图标 class。"
  (gethash currency (hhub-get-cached-currency-fontawesome-symbols-ht)))


(defun init-gst-statecodes ()
  "初始化印度 GST 邦代码 → 邦名 的哈希表。
   返回该哈希表（启动时由 *NSTGSTSTATECODES-HT* 持有）。
   备注：邦代码取自 GSTIN 的前两位；含特殊代码 26*、97（其他）、99（中央管辖）。"
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash  "1" ht) "JAMMU AND KASHMIR")
    (setf (gethash  "2" ht) "HIMACHAL PRADESH")
    (setf (gethash  "3" ht) "PUNJAB")
    (setf (gethash  "4" ht) "CHANDIGARH")
    (setf (gethash  "5" ht) "UTTARAKHAND")
    (setf (gethash  "6" ht) "HARYANA")
    (setf (gethash  "7" ht) "DELHI")
    (setf (gethash  "8" ht) "RAJASTHAN")
    (setf (gethash  "9" ht) "UTTAR PRADESH")
    (setf (gethash  "10" ht) "BIHAR")
    (setf (gethash  "11" ht) "SIKKIM")
    (setf (gethash  "12" ht) "ARUNACHAL PRADESH")
    (setf (gethash  "13" ht) "NAGALAND")
    (setf (gethash  "14" ht) "MANIPUR")
    (setf (gethash  "15" ht) "MIZORAM")
    (setf (gethash  "16" ht) "TRIPURA")
    (setf (gethash  "17" ht) "MEGHALAYA")
    (setf (gethash  "18" ht) "ASSAM")
    (setf (gethash  "19" ht) "WEST BENGAL")
    (setf (gethash  "20" ht) "JHARKHAND")
    (setf (gethash  "21" ht) "ODISHA")
    (setf (gethash  "22" ht) "CHATTISGARH")
    (setf (gethash  "23" ht) "MADHYA PRADESH")
    (setf (gethash  "24" ht) "GUJARAT")
    (setf (gethash  "26*" ht) "DADRA AND NAGAR HAVELI AND DAMAN AND DIU (NEWLY MERGED UT)")
    (setf (gethash  "27" ht) "MAHARASHTRA")
    (setf (gethash  "28" ht) "ANDHRA PRADESH(BEFORE DIVISION)")
    (setf (gethash  "29" ht) "KARNATAKA")
    (setf (gethash  "30" ht) "GOA")
    (setf (gethash  "31" ht) "LAKSHADWEEP")
    (setf (gethash  "32" ht) "KERALA")
    (setf (gethash  "33" ht) "TAMIL NADU")
    (setf (gethash  "34" ht) "PUDUCHERRY")
    (setf (gethash  "35" ht) "ANDAMAN AND NICOBAR ISLANDS")
    (setf (gethash  "36" ht) "TELANGANA")
    (setf (gethash  "37" ht) "ANDHRA PRADESH (NEWLY ADDED)")
    (setf (gethash  "38" ht) "LADAKH (NEWLY ADDED)")
    (setf (gethash  "97" ht) "OTHER TERRITORY")
    (setf (gethash  "99" ht) "CENTRE JURISDICTION")
    ht))

(defun init-gst-invoice-terms ()
  "设置发票标准条款字符串 *NSTGSTINVOICETERMS*（GST 中性英文模板，含付款期、争议条款）。
   方括号内为可替换占位符（[10]、[7]、[Bengaluru/Bangalore City] 等）。"
  (setf *NSTGSTINVOICETERMS* "**Standard Invoice Terms:**
Payment is due within [10] days from the invoice date. Late payments may attract interest at [2]% per month. GST will be applied as per Indian tax laws. Ownership of goods remains with the seller until full payment is received. Any disputes regarding the invoice must be raised within [7] days of receipt. Cancellations or returns are subject to prior approval and may incur additional charges. The invoice is governed by Indian law, and the courts of [Bengaluru/Bangalore City] shall have exclusive jurisdiction over any disputes arising from this transaction."))



    
    
