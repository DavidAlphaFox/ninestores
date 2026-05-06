;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— Schema 迁移引擎（核心列表与执行器）
;;;; 分层：平台基础（启动/运维）
;;;; 文件：hhub/core/nst-sch-mig.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：内置一份 *migrations* 注册表（每条 = (版本号字符串 函数符号 描述)），
;;;;       提供 apply-migrations 统一执行；用 DOD_SCHEMA_MIGRATIONS 表记录已应用版本，
;;;;       保证幂等。同时提供一组 information_schema 查询工具：
;;;;       column-exists-p / column-type-equals-p / index-exists-p /
;;;;       foreign-key-exists-p / table-exists-p。
;;;;
;;;; 主要导出：
;;;;   *migrations*                — 全部待跑/已跑的迁移列表
;;;;   apply-migrations            — 主入口；连接 DB 后逐条幂等执行
;;;;   get-applied-migrations      — 读取 DOD_SCHEMA_MIGRATIONS.version 列
;;;;   migrate-2025May-add-product-code 等 —— 各条迁移函数本体
;;;;
;;;; 关联：
;;;;   上游使用方：超管运维入口（手动调 apply-migrations）
;;;;   下游依赖：crm-db-connect / installation/upgrades 中按需引入的 nst-dbu-*
;;;; ============================================================================
(in-package :nstores)



;; *migrations*：迁移目录。每个元素为 (版本号 函数符号 描述)。
;; 版本号用日期前缀（DDMMYYYY-）保证排序；apply-migrations 按列表顺序运行。
;; 已经在 DOD_SCHEMA_MIGRATIONS 表中登记的版本号会被跳过，达到幂等效果。
(defparameter *migrations*
  '(("05082025-add-product-code"  migrate-2025May-add-product-code "Added human readable Product code to DOD_PRD_MASTER table")
    ;; Add more migrations here
    ("09052025-add-price&discount-columns"  migrate-2025May-add-discount-column "Added current price and current discount to DOD_PRD_MASTER table")
    ("16062025-modify-dod_order-table"  migrate-2025Jun-dod-order-schema "Modify dod_order table add many columns, drop columns, add indexes and foreign keys")
    ("22082025-modify-dod_order_items-table"  migrate-2025Aug-OrderItem-upgrade "Modify dod_order_items table add many columns")
    ("02092025-modify-dod_order_items-sgst"  migrate-2025Sep-orderitem-upgrade-sgst "Modify dod_order_items table modify the sgst column to decimal(4,2) and drop taxable_value column")
    ("08022026-create-vendor-settings-definition-table"  migrate-2026Feb-create-vendor-settings-definition-table "Create vendor settings definitions table")
    ("08022026-create-vendor-settings-table"  migrate-2026Feb-create-vendor-settings-table "Create vendor settings table")
    ("26012026-create-organizations-table"  migrate-2026Jan-create-organization-tables "Create organization tables")
    ("26012026-create-contacts and addresses-table"  migrate-2026Jan-create-contacts&addresses-tables "Create contacts and addresses  tables")
    ("27012026-create-gstupgrade-tables"  migrate-2026Jan-create-gstupgrade-tables "Create gst upgrade tables")
    ("27012026-update-customer-table"  migrate-2026Jan-update-customer-table "Update Customer table to support GST changes for B2B support")
    ("30012026-update-customer-wallet-table"  migrate-2026Feb-update-customer-wallet-table "Update Customer wallet table to support vendor management in B2B use cases")
    ("02022026-create-customer-users-table"   migrate-2026Feb-create-customer-users-table "Create customer users table for B2B use cases")
    ("02022026-update-customer-users-table"   migrate-2026Feb-update-customer-users-table "Update customer users table for B2B use cases. Copy data from DOD_CUST_PROFILE table.")
    ("08022026-update-customer-users-table"   migrate-2026Feb-create-event-trace-table "Create event trace table which will help taking decisions using AI.")

    ("11022026-update-customer-wallet-table"   migrate-2026Feb-update-customer-wallet-table "Update the customer wallet table to support advance receipt payments.")
    ("11022026-create-proforma-invoice-table"   migrate-2026Feb-create-proforma-invoices-table "Create proforma invoice table.")
    ("11022026-create-advance-receipt-vouchers-table"   migrate-2026Feb-create-advance-receipt-vouchers-table "Create advance receipt vouchers table.")
    ("11022026-create-invoice-advance-adjustments-table"   migrate-2026Feb-create-invoice-advance-adjustments-table "Create invoice advance adjustments table.")
    ("13022026-create-buyer-vendor-account-table"   migrate-2026Feb-create-buyer-vendor-account-table  "Create buyer vendor relationship table where we capture the advance payments.")
    ("13022026-create-gst-reconciliation-table"   migrate-2026Feb-create-gst-reconciliation-table  "Create gst reconciliation table for the customer.")
    ("13022026-create-invoice-gst-reconciliation-table"   migrate-2026Feb-create-invoice-gst-reconciliation-table   "Create invoice gst reconciliation table for the customer.")
    ("13022026-create-vendor-gstr1-status-table"   migrate-2026Feb-create-vendor-gstr1-status-table   "Create vendor gstr1 status check table for a customer.")
    ("13022026-update-invoice-header-table"   migrate-2026Feb-update-invoice-header-table    "Update invoice header to support GST changes.")
    ("13022026-create-eway-bill-tabl"   migrate-2026Feb-create-eway-bill-table    "Create eway bill table.")
    ("13022026-create-tds-certificates-table"   migrate-2026Feb-create-tds-certificates-table    "Create tds certificates table.")
    ("13022026-modify-payment-transactions-table"   migrate-2026Feb-modify-payment-transaction-table    "Modify the payment transaction table.")
    ("13022026-modify-customer-order-table"   migrate-2026Feb-modify-customer-order-table    "Modify the customer order table.")
    ("13022026-modify-customer-order-items-table"   migrate-2026Feb-modify-customer-order-items-table    "Modify the customer order items table.")
    ("16022026-modify-warehouse-table"   migrate-2026Feb-update-warehouse-table "Modify the warehouse table.")
    ("16022026-create-warehouse-location-table"   migrate-2026Feb-create-warehouse-location-table "Create warehouse location table.")
    ("22022026-create-batch-lot-table"   migrate-2026Feb-create-batch-lot-table "Create batch lot table.")
    ("22022026-create-stock-table"   migrate-2026Feb-create-stock-table "Create stock table.")
    ("22022026-create-stock-movement-table"   migrate-2026Feb-create-stock-movement-table "Create stock movement table.")
    ("22022026-create-stock-reservation-table"   migrate-2026Feb-create-stock-reservation-table "Create stock reservation table.")
    ("22022026-create-stock-count-table"   migrate-2026Feb-create-stock-count-table "Create stock count table.")
    ))




(defun get-applied-migrations ()
  "查询 DOD_SCHEMA_MIGRATIONS 表已应用的版本号列表。"
  (mapcar #'first
          (clsql:query "SELECT version FROM DOD_SCHEMA_MIGRATIONS ORDER BY row_id ASC" :field-names nil)))

(defun apply-migrations (username password)
  "运维入口：按 *migrations* 顺序执行所有未应用的迁移。
   流程：crm-db-connect → 取已应用版本集合 → 跳过已应用 → 调用迁移函数 → 写 DOD_SCHEMA_MIGRATIONS。
   错误兜底：遇任何 error 打到 *error-output* 后停止当前批次。
   清理：unwind-protect 保证连接最终被 disconnect。"
  (unwind-protect
       (progn
         (crm-db-connect :servername *crm-database-server*
                         :strdb *crm-database-name*
                         :strusr username
                         :strpwd password
                         :strdbtype :mysql)
         (handler-case
             (let ((applied (get-applied-migrations)))
               (dolist (migration *migrations*)
                 (destructuring-bind (version fn description) migration
                   (unless (member version applied :test #'string=)
                     (format t "Applying migration ~A...~%" version)
                     (format t "Description: ~A~%" description)
                     (funcall fn)
		     (sleep 1)
                     (clsql:execute-command
                      (format nil "INSERT INTO DOD_SCHEMA_MIGRATIONS (version) VALUES ('~A');" version))
                     (format t "Migration ~A applied.~%" version)))))
           (error (e)
             (format *error-output* "Migration error: ~A~%" e))))
    (when (clsql:connected-databases)
      (clsql:disconnect))))

(defun column-exists-p (table column)
  "查 information_schema 判断指定列是否存在（幂等迁移的护栏）。"
  (let* ((sql (format nil
                      "SELECT COUNT(*) FROM information_schema.columns
                       WHERE table_schema = DATABASE()
                         AND table_name = '~A'
                         AND column_name = '~A'"
                      table column))
         (result (clsql:query sql :flatp t)))
    (> (first result) 0)))


(defun column-type-equals-p (table-name column-name expected-type)
  "查 information_schema 判断列类型是否等于 expected-type（如 'DECIMAL(15,2)'）。
   按 'DATA_TYPE(NUMERIC_PRECISION,NUMERIC_SCALE)' 拼成实际类型与 expected-type 比对。"
  (let* ((query (format nil
                        "SELECT DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
                         FROM information_schema.columns
                         WHERE table_name = '~A' AND column_name = '~A' AND table_schema = DATABASE();"
                        table-name column-name))
         (result (clsql:query query :flatp t)))
    (when result
      (destructuring-bind (data-type precision scale) result
        (let ((actual (format nil "~A(~A,~A)" (string-upcase data-type) precision scale)))
          (string= actual (string-upcase expected-type)))))))


(defun index-exists-p (table-name index-name)
  "查 information_schema.statistics 判断索引是否存在。"
  (let* ((query (format nil
                        "SELECT 1 FROM information_schema.statistics
                         WHERE table_name = '~A' AND index_name = '~A' AND table_schema = DATABASE();"
                        table-name index-name))
         (result (clsql:query query :flatp t)))
    (not (null result))))

(defun foreign-key-exists-p (table-name fk-name)
  "查 information_schema.table_constraints 判断外键是否存在。"
  (let* ((query (format nil
                        "SELECT 1 FROM information_schema.table_constraints
                         WHERE table_name = '~A' AND constraint_name = '~A'
                         AND constraint_type = 'FOREIGN KEY' AND table_schema = DATABASE();"
                        table-name fk-name))
         (result (clsql:query query :flatp t)))
    (not (null result))))

(defun table-exists-p (table)
  "查 information_schema.tables 判断表是否存在。"
  (let* ((sql (format nil
                      "SELECT COUNT(*) FROM information_schema.tables
                       WHERE table_schema = DATABASE()
                         AND table_name = '~A'"
                      table))
         (result (clsql:query sql :flatp t)))
    (> (first result) 0)))


(defun migrate-2025Sep-orderitem-upgrade-sgst ()
  "迁移 2025-09：把 DOD_ORDER_ITEMS.SGST 类型改为 decimal(4,2)，并删除 TAXABLE_VALUE 列。"
  (when (column-exists-p "DOD_ORDER_ITEMS" "SGST")
    (clsql:execute-command "ALTER TABLE DOD_ORDER_ITEMS MODIFY COLUMN SGST decimal(4,2);"))
  (when (column-exists-p "DOD_ORDER_ITEMS" "TAXABLE_VALUE")
    (clsql:execute-command "ALTER TABLE DOD_ORDER_ITEMS DROP COLUMN TAXABLE_VALUE;")))

(defun migrate-2025Aug-OrderItem-upgrade ()
  "迁移 2025-08：给 DOD_ORDER_ITEMS 增加 TAXABLEVALUE / SGSTAMT / CGSTAMT / IGSTAMT / TOTALITEMVAL 五列。"
  ;; 1 - Add column - TAXABLE_VALUE
  (unless (column-exists-p "DOD_ORDER_ITEMS" "TAXABLEVALUE")
    (clsql:execute-command "ALTER TABLE DOD_ORDER_ITEMS ADD COLUMN TAXABLEVALUE  decimal(15,2);"))
  ;; 2 - Add column - SGSTAMT
  (unless (column-exists-p "DOD_ORDER_ITEMS" "SGSTAMT")
    (clsql:execute-command "ALTER TABLE DOD_ORDER_ITEMS ADD COLUMN SGSTAMT decimal(15,2);"))
  ;; 2 - Add column - CGSTAMT
  (unless (column-exists-p "DOD_ORDER_ITEMS" "CGSTAMT")
    (clsql:execute-command "ALTER TABLE DOD_ORDER_ITEMS ADD COLUMN CGSTAMT decimal(15,2);"))
  ;; 2 - Add column - IGSTAMT
  (unless (column-exists-p "DOD_ORDER_ITEMS" "IGSTAMT")
    (clsql:execute-command "ALTER TABLE DOD_ORDER_ITEMS ADD COLUMN IGSTAMT decimal(15,2);"))
  ;; 2 - Add column - TOTALITEMVAL
  (unless (column-exists-p "DOD_ORDER_ITEMS" "TOTALITEMVAL")
    (clsql:execute-command "ALTER TABLE DOD_ORDER_ITEMS ADD COLUMN TOTALITEMVAL decimal(15,2);")))


(defun migrate-2025May-add-discount-column ()
  "迁移 2025-05：DOD_PRD_MASTER 增加 current_price / current_discount 两列；
   原 unit_price 列若仍存在则删除。
   备注：第一处 unless 条件似乎与意图相反（unless column-exists-p drop column）—— 推测为笔误。"
  ;; Add Current pricing and Current discount columns to dod_prd_master table
  (unless (column-exists-p "DOD_PRD_MASTER" "unit-price")
    (clsql:execute-command "ALTER TABLE DOD_PRD_MASTER DROP COLUMN unit_price;"))
  (unless (column-exists-p "DOD_PRD_MASTER" "current_price")
    (clsql:execute-command
     "ALTER TABLE DOD_PRD_MASTER ADD COLUMN current_price DECIMAL(10, 2);"))
  (unless (column-exists-p "DOD_PRD_MASTER" "current_discount")
    (clsql:execute-command
     "ALTER TABLE DOD_PRD_MASTER ADD COLUMN current_discount DECIMAL(5, 2);")))


(defun migrate-2025May-add-product-code ()
  "迁移 2025-05：给 DOD_PRD_MASTER 增加可读的 PRODUCT_CODE（PRDxxxxxx 格式）。
   流程：加列 → 用 row_id 反填唯一值 → MODIFY NOT NULL → 加 UNIQUE 约束。"
  ;; 1 - Add column
  (unless (column-exists-p "DOD_PRD_MASTER" "PRODUCT_CODE")
    (clsql:execute-command "ALTER TABLE DOD_PRD_MASTER ADD COLUMN PRODUCT_CODE VARCHAR(50);"))
  ;; 2. Update with unique values 
  (clsql:execute-command "UPDATE DOD_PRD_MASTER SET product_code = CONCAT('PRD', LPAD(row_id, 6, '0')) WHERE product_code IS NULL OR product_code = '';")
  ;; 3. Set NOT NULL  
  (clsql:execute-command "ALTER TABLE DOD_PRD_MASTER MODIFY COLUMN PRODUCT_CODE VARCHAR(50) NOT NULL;")
  ;; 4. Add UNIQUE constraint 
  (clsql:execute-command "ALTER TABLE DOD_PRD_MASTER ADD UNIQUE (PRODUCT_CODE);"))



(defun migrate-2025Jun-dod-order-schema ()
  "迁移 2025-06：DOD_ORDER 表大改 —— 增加 ORDNUM / CUSTNAME / IS_CONVERTED_TO_INVOICE
   / IS_CANCELLED / CANCEL_REASON / ORDER_SOURCE / EXPECTED_DELIVERY_DATE
   / EXTERNAL_URL / TOTAL_DISCOUNT / TOTAL_TAX / SHIPADDR / BILLADDR 等列；
   修改 ORDER_AMT 与 SHIPPING_COST 类型为 decimal(15,2)。"
  ;; Add missing columns to DOD_ORDER table based on the target schema

  ;; ORDNUM
  (unless (column-exists-p "DOD_ORDER" "ORDNUM")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN ORDNUM VARCHAR(50);"))
  
  ;; CUSTNAME
  (unless (column-exists-p "DOD_ORDER" "CUSTNAME")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN CUSTNAME VARCHAR(255);"))

  ;; IS_CONVERTED_TO_INVOICE
  (unless (column-exists-p "DOD_ORDER" "IS_CONVERTED_TO_INVOICE")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN IS_CONVERTED_TO_INVOICE CHAR(1) DEFAULT 'N';"))

  ;; IS_CANCELLED
  (unless (column-exists-p "DOD_ORDER" "IS_CANCELLED")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN IS_CANCELLED CHAR(1) DEFAULT 'N';"))

  ;; CANCEL_REASON
  (unless (column-exists-p "DOD_ORDER" "CANCEL_REASON")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN CANCEL_REASON TEXT DEFAULT NULL;"))

  ;; ORDER_SOURCE
  (unless (column-exists-p "DOD_ORDER" "ORDER_SOURCE")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN ORDER_SOURCE ENUM('POS', 'ONLINE', 'WHATSAPP', 'API') DEFAULT 'ONLINE';"))

  ;; EXPECTED_DELIVERY_DATE
  (unless (column-exists-p "DOD_ORDER" "EXPECTED_DELIVERY_DATE")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN EXPECTED_DELIVERY_DATE TIMESTAMP DEFAULT NULL;"))
  
  ;; EXTERNAL_URL
  (unless (column-exists-p "DOD_ORDER" "EXTERNAL_URL")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN EXTERNAL_URL VARCHAR(2048) CHARACTER SET utf8 COLLATE utf8_general_ci DEFAULT NULL;"))

  (clsql:execute-command
   "ALTER TABLE DOD_ORDER MODIFY COLUMN ORDER_AMT DECIMAL(15,2) DEFAULT 0.00;")

  ;; TOTAL_DISCOUNT
  (unless (column-exists-p "DOD_ORDER" "TOTAL_DISCOUNT")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN TOTAL_DISCOUNT DECIMAL(15,2) DEFAULT 0.00;"))

    ;; TOTAL_TAX
  (unless (column-exists-p "DOD_ORDER" "TOTAL_TAX")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN TOTAL_TAX DECIMAL(15,2) DEFAULT 0.00;"))

  (clsql:execute-command
   "ALTER TABLE DOD_ORDER MODIFY COLUMN SHIPPING_COST DECIMAL(15,2) DEFAULT 0.00;")

  (unless (column-exists-p "DOD_ORDER" "SHIPADDR")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN SHIPADDR TEXT;"))
  (unless (column-exists-p "DOD_ORDER" "BILLADDR")
    (clsql:execute-command
     "ALTER TABLE DOD_ORDER ADD COLUMN BILLADDR TEXT;"))
  )



  
