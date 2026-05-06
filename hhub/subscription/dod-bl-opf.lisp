;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：subscription 周期订单（订阅）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/subscription/dod-bl-opf.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-ord-pref 订阅偏好的 CRUD 业务逻辑。提供按租户/客户/主键查询、
;;;;       软删除、恢复以及按 7 天 boolean 列表创建偏好的入口。
;;;;
;;;; 主要导出：
;;;;   get-opreflist-by-company        — 按租户列出全部偏好
;;;;   get-opref-by-id                 — 按主键查
;;;;   get-opreflist-for-customer      — 列出某客户的全部偏好
;;;;   get-latest-opref-for-customer   — 取该客户最近一条偏好
;;;;   update-opref / delete-opref / delete-oprefs / restore-deleted-orderprefs
;;;;   persist-orderpref / create-opref — 新建偏好
;;;;
;;;; 关联：
;;;;   上游使用方：subscription/dod-ui-opf.lisp（订阅设置 UI）、
;;;;               以及周期订单调度器（actor / 定时任务）
;;;;   下游依赖：subscription/dod-dal-opf.lisp（实体定义）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)




(defun get-opreflist-by-company (company-instance)
  "列出某租户下所有未删除的订阅偏好。
   参数：company-instance — dod-company；返回：dod-ord-pref 列表。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
(clsql:select 'dod-ord-pref  :where [and [= [:deleted-state] "N"] [= [:tenant-id] tenant-id]]    :caching *dod-database-caching* :flatp t )))


(defun get-opref-by-id (id company-instance)
  "按主键 row-id 在指定租户下查订阅偏好。
   返回：单个 dod-ord-pref / nil。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-ord-pref  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:row-id] id]]    :caching *dod-database-caching* :flatp t ))))

(defun get-opreflist-for-customer (customer &optional (pdbcaching nil))
  "列出某客户的全部订阅偏好。
   参数：customer — dod-cust-profile；pdbcaching — CLSQL 缓存开关，
        UI 通常传 nil 以拿到最新数据。"
  (let ((tenant-id (slot-value customer 'tenant-id))
	(cust-id (slot-value customer 'row-id)))
    (clsql:select 'dod-ord-pref  :where
		  [and [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]
		  [=[:cust-id] cust-id ]]
				 :caching pdbcaching :flatp t )))





(defun get-latest-opref-for-customer (customer)
  "取该客户最新一条订阅偏好（max(row-id)）。
   备注：实现先调用 get-max-opref-id 求最大主键，再据此条件 SELECT。"
  (let ((tenant-id (slot-value customer 'tenant-id))
	(cust-id (slot-value customer 'row-id)))
(car (clsql:select 'dod-ord-pref  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:cust-id] cust-id ]
		[= [:row-id] (get-max-opref-id cust-id tenant-id)]]    :caching *dod-database-caching* :flatp t ))))

(defun get-max-opref-id (customer-id tenant-id)
  "求某 (customer, tenant) 下订阅偏好的最大 row-id。
   备注：源码 :from 写的是 'dod-opref（与类名 dod-ord-pref 不一致），
        推测为旧表别名/笔误；如该函数仍能工作，可能存在该别名映射。"
 (clsql:select [max [row-id]] :from 'dod-opref  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:cust-id] customer-id]]    :caching *dod-database-caching* :flatp t ))




(defun update-opref (opref-instance); This function has side effect of modifying the database record.
  "把内存中已修改的 dod-ord-pref 实例写回数据库。副作用：UPDATE。"
  (clsql:update-records-from-instance opref-instance))



(defun delete-opref( opref-instance )
  "软删单条订阅偏好（按其 tenant-id + row-id 查回再置 deleted-state='Y'）。"
  (let ((tenant-id (slot-value opref-instance 'tenant-id))
	(id (slot-value opref-instance 'row-id)))
  (let ((dodorderpref (car (clsql:select 'dod-ord-pref :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodorderpref 'deleted-state) "Y")
    (clsql:update-record-from-slot dodorderpref 'deleted-state))))



(defun delete-oprefs ( list company-instance)
  "批量软删订阅偏好。list — row-id 列表。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodorderpref (car (clsql:select 'dod-ord-pref :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value dodorderpref 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodorderpref  'deleted-state))) list )))


(defun restore-deleted-orderprefs ( list tenant-id )
  "批量恢复已软删的订阅偏好（deleted-state 改回 'N'）。
   备注：与同模块其他函数不同，此处直接接收 tenant-id 整数。"
(mapcar (lambda (id)  (let ((dodorderpref (car (clsql:select 'dod-ord-pref :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodorderpref 'deleted-state) "N")
    (clsql:update-record-from-slot dodorderpref 'deleted-state))) list ))




(defun persist-orderpref( customer-id product-id prd-qty mon tue wed thu fri sat sun tenant-id )
  "底层持久化：INSERT 一条 dod-ord-pref。布尔参数 mon..sun 转 'Y'/'N' 字符串。
   副作用：写库后 sleep 1 秒（推测为避免与调度器抢同一秒生成多条）。"
 (clsql:update-records-from-instance (make-instance 'dod-ord-pref
						    :cust-id customer-id
						    :prd-id product-id
					 :prd-qty prd-qty
					 :sun (if sun "Y" "N")
					 :mon (if mon "Y" "N")
					 :tue  (if tue "Y" "N")
					 :wed  (if wed "Y" "N")
					 :thu  (if thu "Y" "N")
					 :fri  (if fri "Y" "N")
					 :sat  (if sat "Y" "N")
						    :tenant-id tenant-id
						    :deleted-state "N"))
  (sleep 1))



(defun create-opref (customer product prd-qty wdlist company-instance)
  "UI 入口：为某 (customer, product) 在指定租户下新建订阅偏好。
   参数：wdlist — 长度 7 的布尔列表，依次为 mon/tue/wed/thu/fri/sat/sun。
   副作用：写 DOD_ORDER_SUBSCRIPTION。"
  (let ((customer-id (slot-value  customer 'row-id) )
	(tenant-id (slot-value company-instance 'row-id))
	(product-id (slot-value product 'row-id)))
    (persist-orderpref customer-id product-id prd-qty (nth 0 wdlist) (nth 1 wdlist) (nth 2 wdlist) (nth 3 wdlist) (nth 4 wdlist) (nth 5 wdlist) (nth 6 wdlist)  tenant-id )))



