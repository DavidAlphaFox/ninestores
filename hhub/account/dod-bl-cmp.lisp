;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：account 账户/租户
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/account/dod-bl-cmp.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-company（租户/公司）实体的 CRUD 与领域规则。
;;;;       包含创建公司、按 id/name/pincode 查询、删除/恢复（软删）、
;;;;       公司冻结/恢复、试用期到期判定、租户内客户/卖家计数等。
;;;;
;;;; 主要导出：
;;;;   new-dod-company            — 新建公司（INSERT DOD_COMPANY）
;;;;   suspendaccount / restoreaccount — 冻结 / 恢复租户（同时刷新 ABAC 缓存）
;;;;   trial-account-days-to-expiry / trial-account-expired-p — 试用期判断
;;;;   count-company-customers / count-company-vendors        — 租户内人员计数
;;;;   select-company-by-id / select-company-by-name / select-companies-by-name
;;;;   select-companies-by-pincode / get-system-companies
;;;;   delete-dod-company / delete-dod-companies / restore-deleted-dod-companies
;;;;   update-company                — UPDATE DOD_COMPANY
;;;;   generate-account-ext-url      — 生成可分享的店铺外链
;;;;   get-account-currency          — 由公司国别推断币种
;;;;   account-created-days-ago      — 注册至今天数
;;;;   equal-companiesp              — 用 row-id 判等
;;;;
;;;; 关联：
;;;;   上游使用方：account/dod-ui-cmp.lisp、core ABAC 缓存重建、
;;;;               vendor/customer 模块创建租户时调用。
;;;;   下游依赖：account/dod-dal-cmp.lisp（dod-company 实体）、
;;;;             core 货币缓存、ABAC 属性 com-hhub-attribute-company-issuspended。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun get-account-currency (company)
  "按 company.country 在缓存的货币表里查币种，找不到则回退 *HHUBDEFAULTCURRENCY*。
   返回：币种代码字符串（如 \"INR\"、\"USD\"）。"
  (let* ((country (slot-value company 'country))
	 (currency-ht (hhub-get-cached-currencies-ht))
	 (currency (nth 1 (gethash country currency-ht))))
    (if currency currency *HHUBDEFAULTCURRENCY*)))

(defun generate-account-ext-url (account)
  :description "为 account 生成对外可分享的店铺链接，把 tenant-id 用 base64 编码后拼成
   ~A/hhub/displaystore?key=<base64>。
   参数：account — dod-company 实例。
   返回：URL 字符串。"
  (let* ((tenant-id (slot-value account 'row-id))
	 (param-csv (format nil "tenant-id~C~A" #\linefeed tenant-id))
	 (param-base64 (cl-base64:string-to-base64-string param-csv)))
    (format nil "~A/hhub/displaystore?key=~A" *siteurl* param-base64)))


(defun new-dod-company(cname caddress city state country zipcode website cmp-type subscription-plan createdby updatedby)
  "新建一个公司/租户记录到 DOD_COMPANY。默认 deleted-state='N'、suspend-flag='N'、
   tshirt-size='SM'、revenue=0；createdby/updatedby 应为 dod-users.row-id。
   副作用：INSERT DOD_COMPANY。返回：CLSQL update 的结果。"
  (let  ((company-name cname)
	 (company-address caddress))
	(clsql:update-records-from-instance (make-instance 'dod-company
							   :name company-name
							   :address company-address
							   :city city
							   :state state 
							   :country country
							   :zipcode zipcode
							   :website website 
							   :deleted-state "N"
							   :suspend-flag "N"
							   :tshirt-size "SM"
							   :revenue 0
							   :cmp-type cmp-type
							   :subscription-plan subscription-plan
							   :created-by createdby
							   :updated-by updatedby))))



(defun suspendaccount (tenant-id)
  "冻结指定租户：把 suspend-flag 置为 'Y' 并写库；之后立刻重建 ABAC 全局缓存
   *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*，使新状态在下一次 PEP/PDP 命中时生效。
   副作用：UPDATE DOD_COMPANY + 重建缓存。"
  (let* ((company (select-company-by-id tenant-id))
	(suspend-flag (slot-value company 'suspend-flag)))
    (unless (com-hhub-attribute-company-issuspended suspend-flag)
      (setf (slot-value company 'suspend-flag) "Y"))
    (update-company company)
    (setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS* (hhub-gen-globally-cached-lists-functions))))

(defun restoreaccount (tenant-id)
  "解冻租户：与 suspendaccount 对偶，把 suspend-flag 改回 'N' 并刷新 ABAC 缓存。"
  (let* ((company (select-company-by-id tenant-id))
	(suspend-flag (slot-value company 'suspend-flag)))
    (when (com-hhub-attribute-company-issuspended suspend-flag)
      (setf (slot-value company 'suspend-flag) "N"))
    (update-company company)
    (setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS* (hhub-gen-globally-cached-lists-functions))))



;(defun get-count-company-customers (company) 
;  (let ((old-func (symbol-function 'count-company-customers))
;	(previous (make-hash-table)))
;    (defun count-company-customers (company)
;      (or (gethash company previous)
;	  (setf (gethash company previous) (funcall old-func company))))))

(defun account-created-days-ago (account)
  "返回该公司账户已创建多少天（基于 created slot 与当前时间差），单位 day。"
  (let ((created (slot-value account 'created)))
    (clsql-sys:duration-reduce (clsql-sys:time-difference (clsql-sys:get-time) created) :day)))


(defun trial-account-days-to-expiry (account)
  "若账户为 TRIAL 套餐，返回距试用到期还剩多少天（可能为负，表示已过期）。
   非 TRIAL 套餐返回 nil。常量 *HHUBTRIALCOMPANYEXPIRYDAYS* 默认 90。"
  (let ((created (slot-value account 'created))
	(subsplan (slot-value account 'subscription-plan)))
    (when (equal subsplan "TRIAL")
      (- (clsql-sys:duration-reduce (clsql-sys:make-duration :day *HHUBTRIALCOMPANYEXPIRYDAYS*) :day) (clsql-sys:duration-reduce (clsql-sys:time-difference (clsql-sys:get-time) created) :day)))))


(defun trial-account-expired-p (account)
  "判定 TRIAL 账户是否已过期（now-created > *HHUBTRIALCOMPANYEXPIRYDAYS*）。
   非 TRIAL 套餐返回 nil。"
  (let ((created (slot-value account 'created))
	(subsplan (slot-value account 'subscription-plan)))
    (when (equal subsplan "TRIAL")
      (clsql-sys:duration> (clsql-sys:time-difference (clsql-sys:get-time) created)  (clsql-sys:make-duration :day *HHUBTRIALCOMPANYEXPIRYDAYS*)))))

(defun count-company-customers (company)
  "统计租户下未软删的客户数量（COUNT(*) FROM DOD_CUST_PROFILE WHERE tenant-id=...）。
   :caching nil 强制走实时数据。"
 (let ((tenant-id (slot-value company 'row-id)))
    (first (clsql:select [count [*]] :from 'dod-cust-profile  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]]   :caching nil :flatp t ))))

(defun count-company-vendors (company)
  "统计租户下未软删的卖家数量（DOD_VEND_PROFILE）。"
 (let ((tenant-id (slot-value company 'row-id)))
    (first (clsql:select [count [*]] :from 'dod-vend-profile  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]]   :caching nil :flatp t ))))



(defun equal-companiesp (cmp1 cmp2)
  "判定两个 dod-company 实例是否同一行（基于 row-id）。"
  (equal (slot-value cmp1 'row-id) (slot-value cmp2 'row-id)))


(defun select-company-by-name (name-like-clause)
  "按名称 LIKE 查公司，仅取首条。name-like-clause 调用方需自带 % 通配。
   过滤已软删除（deleted-state='N'）。返回：单个 dod-company / nil。"
(car (clsql:select 'dod-company :where [and
		[= [:deleted-state] "N"]
		[like  [:name] name-like-clause]]
		:caching *dod-database-caching* :flatp t)))


(defun select-companies-by-name (name-like-clause)
  "按名称模糊查公司（在内部包成 \"%xxx%\"），返回全部匹配。"
 (clsql:select 'dod-company :where [and
		[= [:deleted-state] "N"]
		[like  [:name] (format NIL "%~a%"  name-like-clause)]]
		:caching *dod-database-caching* :flatp t))

(defun select-companies-by-pincode (name-like-clause)
  "按邮编（zipcode）模糊查公司。常用于按地区检索就近商家。"
 (clsql:select 'dod-company :where [and
		[= [:deleted-state] "N"]
		[like  [:zipcode] (format NIL "%~a%"  name-like-clause)]]
		:caching *dod-database-caching* :flatp t))




(defun select-company-by-id (id)
  "按主键 row-id 查公司，过滤软删。返回：单个 dod-company / nil。"
(car (clsql:select 'dod-company :where [and
		[= [:deleted-state] "N"]
		[= [:row-id] id]]
		:caching *dod-database-caching* :flatp t)))



(defun get-system-companies ()
  "列出系统全部未软删公司，但排除 \"super\" 这个内部公司（避免出现在管理列表里）。"
  (clsql:select 'dod-company  :where
		[and
		[= [:deleted-state] "N"]
		[<> [:name] "super"]] ; Avoid super company in any list.
			      :caching *dod-database-caching* :flatp t ))

(defun delete-dod-company ( id )
  "软删单个公司：将 deleted-state 置 'Y'。副作用：UPDATE DOD_COMPANY。"
  (let ((company (car (clsql:select 'dod-company :where [= [:row-id] id] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value company 'deleted-state) "Y")
    (clsql:update-record-from-slot company 'deleted-state)))


(defun delete-dod-companies ( list )
  "批量软删公司。list — 主键 id 列表。"
  (mapcar (lambda (id)  (let ((company (car (clsql:select 'dod-company :where [= [:row-id] id] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value company 'deleted-state) "Y")
			  (clsql:update-record-from-slot company 'deleted-state))) list ))


(defun restore-deleted-dod-companies ( list )
  "批量恢复已软删的公司：deleted-state 改回 'N'。"
(mapcar (lambda (id)  (let ((company (car (clsql:select 'dod-company :where [= [:row-id] id] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value company 'deleted-state) "N")
    (clsql:update-record-from-slot company 'deleted-state))) list ))



(defun update-company (instance); This function has side effect of modifying the database record.
  "把内存中的 dod-company 实例所有字段写回数据库（UPDATE）。副作用：UPDATE DOD_COMPANY。"
  (clsql:update-records-from-instance instance))
