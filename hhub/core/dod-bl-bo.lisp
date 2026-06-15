;;; dod-bl-bo.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— ABAC 元模型业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/dod-bl-bo.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：为 dod-bus-object / dod-abac-subject / dod-bus-transaction 三个实体
;;;;       提供 CRUD；并实现 ABAC 框架最关键的两个 PDP 入口：
;;;;       has-permission（基于 transaction + alist params）
;;;;       has-permission1（XACML 风格四元组）。
;;;;
;;;; 主要导出：
;;;;   get-bus-object / get-bus-object-by-name / select-bus-object-by-company
;;;;   create-bus-object / persist-bus-object
;;;;   get-bus-transaction / get-system-bus-transactions / get-system-bus-transactions-ht
;;;;   select-bus-trans-by-trans-func / create-bus-transaction
;;;;   create-abac-subject / get-system-abac-subjects
;;;;   has-permission     —— 主 PDP 入口（被 PEP 宏 with-hhub-transaction 调用）
;;;;   has-permission1    —— XACML 风格 PDP（subject/resource/action/env）
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-ui-utl.lisp 的 PEP 宏、各模块的 com-hhub-transaction-*
;;;;   下游依赖：core/dod-dal-bo.lisp（实体定义）、
;;;;             core/dod-bl-pol.lisp（auth-policy CRUD）、
;;;;             core/dod-ui-pol.lisp（com-hhub-policy-* 策略函数）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;;;;;;;;;;;;;;;;;;;;; business logic for dod-bus-object ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun get-bus-object (id)
  "按主键 row-id 查询业务对象（资源类型）。
   过滤已软删除记录（deleted-state='N'）。
   返回：单个 dod-bus-object 实例 / nil。"
  (car (clsql:select 'dod-bus-object  :where [and [= [:deleted-state] "N"] [= [:row-id] id]]    :caching *dod-database-caching* :flatp t )))

(defun get-system-bus-objects ()
  "获取系统级（tenant_id=1）注册的全部资源类型。被启动期 ABAC 缓存预热使用。"
  (select-bus-object-by-company (select-company-by-id 1)))

(defun get-bus-object-by-name (name)
  "按名称（如 \"ORDER\"）精确查找资源类型。注意：未限定 tenant_id，跨租户取第一条。
   返回：单个 dod-bus-object 实例 / nil。"
  (car (clsql:select 'dod-bus-object  :where [and [= [:deleted-state] "N"] [= [:name] name]]    :caching *dod-database-caching* :flatp t )))

(defun select-bus-object-by-company (company-instance)
  "列出某 company（租户）下所有未删除的资源类型，按 name 升序。
   参数：company-instance — dod-company 实例。
   返回：dod-bus-object 列表。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (clsql:select 'dod-bus-object  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]] :ORDER-BY '([:name])
		:caching *dod-database-caching* :flatp t )))


(defun persist-bus-object(name hhub-type tenant-id )
  "底层持久化：构造 dod-bus-object 并写库。新建记录默认 active-flg='Y'、deleted-state='N'。
   副作用：执行 INSERT。仅供 create-bus-object 内部使用。"
 (clsql:update-records-from-instance (make-instance 'dod-bus-object
						    :name name
						    :active-flg "Y"
						    :tenant-id tenant-id
						    :hhub-type hhub-type
						    :deleted-state "N")))



(defun create-bus-object (name hhub-type company-instance)
  "PAP 入口：在指定租户下登记一种新的业务资源类型。name 会被转大写以保持约定。
   参数：name — 资源类型名；hhub-type — 子分类；company-instance — 所属租户。
   副作用：写 DOD_BUS_OBJECT 表。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
	      (persist-bus-object (string-upcase name) hhub-type tenant-id)))



;;;;;;;;;;;;;;;;;;;;; Functions for dod-abac-subject ;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun get-abac-subject (id)
  "按主键查 ABAC 主体类型。返回单个 dod-abac-subject / nil。"
  (car (clsql:select 'dod-abac-subject  :where [and [= [:deleted-state] "N"] [= [:row-id] id]]    :caching *dod-database-caching* :flatp t )))

(defun get-system-abac-subjects ()
  "获取系统级（tenant_id=1）登记的全部主体类型，用于启动期 ABAC 缓存预热。"
  (select-abac-subject-by-company (select-company-by-id 1)))

(defun get-abac-subject-by-name (name)
  "按名称精确查主体类型。未限定 tenant_id。"
  (car (clsql:select 'dod-abac-subject  :where [and [= [:deleted-state] "N"] [= [:name] name]]    :caching *dod-database-caching* :flatp t )))

(defun select-abac-subject-by-company (company-instance)
  "列出某 company 下所有未删除的主体类型，按 name 升序。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (clsql:select 'dod-abac-subject  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]] :ORDER-BY '([:name])
		:caching *dod-database-caching* :flatp t )))


(defun persist-abac-subject(name hhub-type tenant-id )
  "底层持久化：构造 dod-abac-subject 并写库。仅供 create-abac-subject 使用。"
 (clsql:update-records-from-instance (make-instance 'dod-abac-subject
						    :name name
						    :active-flg "Y"
						    :tenant-id tenant-id
						    :deleted-state "N"
						    :hhub-type hhub-type)))



(defun create-abac-subject (name hhub-type)
  "PAP 入口：登记一种新的 ABAC 主体类型（写到系统租户 tenant_id=1）。
   name 会被转大写。"
  (let ((tenant-id (slot-value (select-company-by-id 1) 'row-id)))
	      (persist-abac-subject (string-upcase name) hhub-type tenant-id)))



;;;;;;;;;;;;;;;;; Functions for dod-bus-transaction ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun get-bus-transaction (id)
  "按主键查 ABAC 事务记录。"
 (car  (clsql:select 'dod-bus-transaction  :where [and [= [:deleted-state] "N"] [= [:row-id] id]]    :caching *dod-database-caching* :flatp t )))

(defun get-system-bus-transactions ()
  "获取系统级（tenant_id=1）已登记的全部 ABAC 事务，用于启动期缓存预热。"
(select-bus-trans-by-company (select-company-by-id 1)))

(defun get-system-bus-transactions-ht ()
  "把系统全部 ABAC 事务装成哈希表，key=trans-func（控制器函数名字符串），value=事务实例。
   PEP 宏 with-hhub-transaction 通过此 HT 在 O(1) 时间定位事务。"
  (let ((ht (make-hash-table :test 'equal))
	(transactions (get-system-bus-transactions)))
    (loop for tran in transactions do
	 (let ((key (slot-value tran 'trans-func)))
	   (setf (gethash key ht) tran)))
    ht))


(defun select-bus-trans-by-trans-func (name)
  "按 trans-func 字段（控制器函数名）查事务。注意：未限定 tenant_id，跨租户取第一条。
   被 with-hhub-pep（XACML 风格 PEP）使用。"
  (car (clsql:select 'dod-bus-transaction  :where
		[and [= [:deleted-state] "N"]
		[= [:trans-func] name]]
     :caching *dod-database-caching* :flatp t )))



(defun select-bus-trans-by-company (company-instance)
  "列出某 company 下所有未删除的事务。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (clsql:select 'dod-bus-transaction  :where
		  [and [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]]
		  :caching *dod-database-caching* :flatp t )))

(defun select-bus-trans-by-name (name-like-clause company-instance )
  "按 name LIKE 模糊匹配事务（PAP UI 搜索用）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-bus-transaction :where [and
		     [= [:deleted-state] "N"]
		     [= [:tenant-id] tenant-id]
		     [like  [:name] name-like-clause]]
					  :caching *dod-database-caching* :flatp t))))

(defun select-bus-trans-by-id (id company-instance )
  "按 row-id 在租户内查事务。注意：where 用了 like，应当为 =（推测原作者笔误，实际仍能匹配）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-bus-transaction :where [and
		     [= [:deleted-state] "N"]
		     [= [:tenant-id] tenant-id]
		     [like  [:row-id] id]]
					  :caching *dod-database-caching* :flatp t))))

(defun update-bus-transaction (instance)
  "更新事务记录到数据库。副作用：UPDATE。"
  (clsql:update-records-from-instance instance))



(defun delete-bus-transaction( id company-instance)
  "软删单条事务（在指定租户下）。仅置 deleted-state='Y'，不真删。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (let ((object (car (clsql:select 'dod-bus-transaction :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value object 'deleted-state) "Y")
    (clsql:update-record-from-slot object 'deleted-state))))



(defun delete-bus-transactions ( list company-instance)
  "批量软删事务。list — 主键 id 列表。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-bus-transaction :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value object 'deleted-state) "Y")
			  (clsql:update-record-from-slot object  'deleted-state))) list )))


(defun restore-deleted-bus-transactions ( list company-instance )
  "恢复已软删的事务（deleted-state 改回 'N'）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
(mapcar (lambda (id)  (let ((object (car (clsql:select 'dod-bus-transaction :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value object 'deleted-state) "N")
    (clsql:update-record-from-slot object 'deleted-state))) list )))

(defun persist-bus-transaction(name  uri  trans-type trans-func tenant-id )
  "底层持久化：构造 dod-bus-transaction 并写库。
   备注：bo-id / auth-policy-id 都硬编码为 1 —— 创建时挂占位策略，
        管理员后续在 PAP 把策略关系改成实际策略。"
 (clsql:update-records-from-instance (make-instance 'dod-bus-transaction
						    :name name
						    :uri uri
						    :bo-id 1
						    :auth-policy-id 1
						    :trans-type trans-type
						    :active-flg "Y"
						    :trans-func trans-func
						    :tenant-id tenant-id
						    :deleted-state "N")))



(defun create-bus-transaction (name  uri trans-type trans-func company-instance)
  "PAP 入口：在指定租户下登记一条新事务（URL ↔ 控制器函数 ↔ 占位策略）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (persist-bus-transaction name  uri trans-type trans-func  tenant-id)))



;; ----------------------------------------------------------------------------
;; PDP（Policy Decision Point）—— 策略求值入口
;; ----------------------------------------------------------------------------
;; 注：源码原注释写的是 "POLICY ENFORCEMENT POINT"，但函数实际承担 PDP 角色
;;    （被 PEP 宏 with-hhub-transaction / with-hhub-pep 调用）。
;;
;; has-permission1  —— XACML 风格四元组：(subject, resource, action, env)
;; has-permission   —— 主流路径：基于 transaction + alist params
;; ----------------------------------------------------------------------------

(defun has-permission1 (policy-id subject resource action env)
  "PDP（XACML 风格）：根据 policy-id 取出策略，funcall 其 policy-func 求值。
   被旧版 PEP 宏 with-hhub-pep 使用，主路径已不再走这个变体。
   返回：策略函数返回值（T/NIL），policy-func 为空时返回 NIL。"
  (let* ((policy (if policy-id (select-auth-policy-by-id policy-id)))
	(policy-func (if policy (slot-value policy 'policy-func))))
     (if policy-func (funcall (intern  (string-upcase policy-func)) subject resource action env))))


(defun has-permission (transaction &optional params)
  :documentation "PDP（Policy Decision Point）主入口：根据传入的 transaction
   实例取出 auth-policy-id，从内存缓存 HHUB-GET-CACHED-AUTH-POLICIES-HT 找到策略，
   再 funcall 其 policy-func（DB 中存的字符串 → intern 成 :nstores 包符号）。
   策略可返回 T / NIL，或显式抛 hhub-abac-transaction-error 携带拒绝原因。
   返回：(list 返回值 异常文本) —— PEP 只取第 0 位决定放行。
   副作用：策略抛错时写日志到 *HHUBBUSINESSFUNCTIONSLOGFILE*。
   注：本函数 docstring 原写 'PEP'，实为 PDP（笔误，被 PEP 调用）。"
  ;; Execute permission logic here.
  (let* ((policy-id (if transaction (slot-value transaction 'auth-policy-id)))
	 (policy (if policy-id (get-ht-val policy-id (HHUB-GET-CACHED-AUTH-POLICIES-HT))))
	 (policy-name (if policy (slot-value policy 'name)))
	 (policy-func (if policy (slot-value policy 'policy-func)))
	 (exceptionstr nil))
    (handler-case 
	(multiple-value-bind (returnvalues)
	    (funcall (intern  (string-upcase policy-func) :nstores) params)
	  ;; Return a list of return values and exception as nil. 
	  ;;(logiamhere (format nil "Executing Policy - ~A" policy-func))
	  (list returnvalues nil))

      ;; If we get an ABAC Transaction exception
      (hhub-abac-transaction-error (condition)
	(setf exceptionstr (format nil "~A: HHUB ABAC Transaction error - ~A. Error: ~A~%" (mysql-now) (string-upcase policy-name) (getExceptionStr condition)))
	(with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				:direction :output
				:if-exists :append
				:if-does-not-exist :create)
	  (format stream "~A: ~A~A" (mysql-now) exceptionstr (sb-debug:list-backtrace)))
	(list nil (format nil "Nine Stores General Authorization Error. Contact your system administrator.")))
  
      ;; If we get any general error we will not throw it to the upper levels. Instead set the exception and log it. 
      (error (c)
	(setf exceptionstr (format nil  "~A: HHUB General ABAC Policy Error: ~A :: ~A~%" (mysql-now) (string-upcase policy-name) c))
	(with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				:direction :output
				:if-exists :append
				:if-does-not-exist :create)
	  (format stream "~A: ~A~A" (mysql-now)  exceptionstr (sb-debug:list-backtrace)))
	(list nil (format nil "Nine Stores General Authorization Error. Contact your system administrator."))))))


