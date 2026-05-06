;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— ABAC 策略/属性 PAP 后端
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/dod-bl-pol.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-auth-attr-lookup（属性元数据）/ dod-auth-policy（策略元数据）/
;;;;       dod-auth-policy-attr（策略-属性关联）三张表的 CRUD。
;;;;       配合 PEP/PDP 和超管 PAP UI（dod-ui-pol.lisp）使用。
;;;;       create-auth-attr-lookup 还会向 core/dod-ui-attr.lisp 末尾自动追加
;;;;       一个空 defun，作为开发者补 PIP 实现的脚手架。
;;;;
;;;; 主要导出：
;;;;   get-auth-attrs / get-system-abac-attributes / select-auth-attrs-by-company
;;;;   select-auth-attr-by-id/key
;;;;   create-auth-attr-lookup       — PAP 入口（含源码脚手架联动）
;;;;   delete-auth-attr-lookup / delete-auth-attrs / restore-*
;;;;   get-system-auth-policies / get-system-auth-policies-ht
;;;;   select-auth-policy-by-id/company/name
;;;;   create-auth-policy / persist-auth-policy / seed-auth-policies
;;;;   create-auth-policy-attr      — 策略 ↔ 属性 关联 PAP 入口
;;;;   attrinlist-p                  — 属性 id 是否在列表中
;;;;
;;;; 关联：
;;;;   上游使用方：core/dod-ui-pol.lisp（PAP UI 控制器）、
;;;;               PDP has-permission（通过缓存间接使用）
;;;;   下游依赖：core/dod-dal-pol.lisp（实体定义）
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

;;;;;;;;;;;;;;;;; Functions for dod-auth-policy-attr class ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun get-auth-attrs (tenant-id)
  "查询某租户下全部未软删的属性元数据。"
  (clsql:select 'dod-auth-attr-lookup  :where [and [= [:deleted-state] "N"] [= [:tenant-id] tenant-id]]    :caching *dod-database-caching* :flatp t ))

(defun get-system-abac-attributes ()
  "获取系统级（tenant_id=1）属性元数据。被启动期 ABAC 缓存预热使用。"
  (select-auth-attrs-by-company (select-company-by-id 1)))

(defun select-auth-attrs-by-company (company-instance)
  "列出某 company 下全部未删除的属性元数据。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
 (clsql:select 'dod-auth-attr-lookup  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]]
     :caching *dod-database-caching* :flatp t )))

  (defun select-auth-attr-by-id (id)
    "按主键查属性元数据。返回单个 dod-auth-attr-lookup / nil。"
    (car (clsql:select 'dod-auth-attr-lookup :where [and
		[= [:deleted-state] "N"]
		[= [:row-id] id]]
		:caching *dod-database-caching* :flatp t)))


  (defun select-auth-attr-by-key (name-like-clause company-instance )
    "按 name LIKE 模糊匹配属性（PAP UI 搜索用）。"
      (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-auth-attr-lookup :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[like  [:name] name-like-clause]]
		:caching *dod-database-caching* :flatp t))))


(defun attrinlist-p  (attr-id list)
  "判断 attr-id 是否出现在 list 中各元素的 row-id 槽中。
   配合策略 UI 渲染"已勾选"复选框使用。"
(member attr-id  (mapcar (lambda (item)
		(slot-value item 'row-id)) list)))



(defun update-auth-attr-lookup (instance); This function has side effect of modifying the database record.
  "更新属性元数据。副作用：UPDATE。"
  (clsql:update-records-from-instance instance))

(defun delete-auth-attr-lookup( id company-instance)
  "在指定租户下软删一条属性元数据（deleted-state='Y'）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (let ((dodauthattr (car (clsql:select 'dod-auth-attr-lookup :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodauthattr 'deleted-state) "Y")
    (clsql:update-record-from-slot dodauthattr 'deleted-state))))



(defun delete-auth-attrs ( list company-instance)
  "批量软删属性元数据。list — id 列表。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodauthattr (car (clsql:select 'dod-auth-attr-lookup :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value dodauthattr 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodauthattr  'deleted-state))) list )))


(defun restore-deleted-auth-policy-attrs ( list company-instance )
  "批量恢复软删的属性元数据（deleted-state 改回 'N'）。
   备注：函数名带 -attrs 但操作的是 dod-auth-attr-lookup（属性表），命名稍有歧义。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
(mapcar (lambda (id)  (let ((dodauthattr (car (clsql:select 'dod-auth-attr-lookup :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodauthattr 'deleted-state) "N")
    (clsql:update-record-from-slot dodauthattr 'deleted-state))) list )))

(defun persist-auth-attr-lookup(name description attr-func attr-type tenant-id )
  "底层持久化：构造 dod-auth-attr-lookup 并写库。
   备注：attr-unique-func 在此版本未传入（被注释掉）。"
 (clsql:update-records-from-instance (make-instance 'dod-auth-attr-lookup
						    :name name
						    :description description
						    :attr-func attr-func
						    ;:attr-unique-func attr-unique-func 
						    :attr-type attr-type 
						    :active-flg "Y" 
						    :tenant-id tenant-id
						    :deleted-state "N")))
 


(defun create-auth-attr-lookup (name description attr-func  attr-type company-instance)
  "PAP 入口：登记一个新的 ABAC 属性元数据，并在源码末尾追加空 defun 作为开发脚手架。
   副作用：
     1) INSERT 到 DOD_AUTH_ATTR_LOOKUP；
     2) 向 ~/ninestores/hhub/core/dod-ui-attr.lisp 末尾 append 一行 (defun <attr-func> ())，
        提醒开发者去补 PIP 实现。
   备注：attr-func 为 symbol 时跳过追加（极少出现的极端情况）。"
  (let ((tenant-id (slot-value company-instance 'row-id))
	(filename "~/ninestores/hhub/core/dod-ui-attr.lisp"))
    (persist-auth-attr-lookup name description attr-func attr-type tenant-id)
     (with-open-file (stream filename :if-exists :append :direction :output)
       (unless (symbolp attr-func) (print (format stream "(defun ~A ())" attr-func)))
       (terpri stream))))






;    (with-open-file (stream "~/hhubplatform/hhub/dod-ui-attr.lisp" :if-exists nil :direction :output)
 ;     (format stream "(defun ~A ())" attr-func)
  ;    (terpri stream))))
	
	

;;;;;;;;;;;;;;;;;;;;; business logic for dod-auth-policy ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun get-system-auth-policies ()
  "获取系统级（tenant_id 写死为 1）的全部策略，用于启动期 ABAC 缓存预热。
   备注：架构文档观察到此处 tenant_id=1 是硬编码，租户级策略缓存还未落地。"
(get-auth-policies 1))


(defun get-auth-policies (tenant-id)
  "查询某租户下全部未软删的策略。"
  (clsql:select 'dod-auth-policy  :where [and [= [:deleted-state] "N"] [= [:tenant-id] tenant-id]]    :caching *dod-database-caching* :flatp t ))

(defun get-system-auth-policies-ht ()
  :documentation "This function stores all the system ABAC policies in a Hashtable. The Key = Policy ID, Value = Policy instance.
   中文：把系统级全部策略装成哈希表 row-id → policy 实例，
         供 PDP has-permission 在 O(1) 时间内查找策略。"
  (let ((ht (make-hash-table :test 'equal))
	(policies (get-system-auth-policies)))
    (loop for policy in policies do
	 (let ((key (slot-value policy 'row-id)))
	   (setf (gethash key ht) policy)))
    ; Return  the hash table. 
    ht))


(defun select-auth-policy-by-id (id)
  "按主键查策略元数据。返回单个 dod-auth-policy / nil。
   被 has-permission1（XACML 风格 PEP）使用。"
 (car  (clsql:select 'dod-auth-policy :where
		[and [= [:deleted-state] "N"]
		[= [:row-id] id]]
		     :caching *dod-database-caching* :flatp t )))

(defun select-auth-policy-by-company (company-instance)
  "列出某 company 下所有未删除的策略。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
 (clsql:select 'dod-auth-policy  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]]
     :caching *dod-database-caching* :flatp t )))

(defun select-auth-policy-by-name (name-like-clause company-instance)
  "按 name LIKE 模糊匹配策略（PAP UI 搜索）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
 (clsql:select 'dod-auth-policy  :where
		[and [= [:deleted-state] "N"]
		[like [:name] name-like-clause]
		[= [:tenant-id] tenant-id]]
     :caching *dod-database-caching* :flatp t )))




(defun update-auth-policy (instance); This function has side effect of modifying the database record.
  "更新策略元数据。副作用：UPDATE。"
  (clsql:update-records-from-instance instance))

(defun delete-auth-policy( id company-instance)
  "在指定租户下软删一条策略。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (let ((dodauthpolicy (car (clsql:select 'dod-auth-policy :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodauthpolicy 'deleted-state) "Y")
    (clsql:update-record-from-slot dodauthpolicy 'deleted-state))))



(defun delete-auth-policies ( list company-instance)
  "批量软删策略。list — id 列表。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodauthpolicy (car (clsql:select 'dod-auth-policy :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value dodauthpolicy 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodauthpolicy  'deleted-state))) list )))


(defun restore-deleted-auth-policy ( list company-instance )
  "批量恢复软删的策略（deleted-state 改回 'N'）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
(mapcar (lambda (id)  (let ((dodauthpolicy (car (clsql:select 'dod-auth-policy :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodauthpolicy 'deleted-state) "N")
    (clsql:update-record-from-slot dodauthpolicy 'deleted-state))) list )))

   

  
(defun persist-auth-policy(name description policy-func tenant-id )
  "底层持久化：构造 dod-auth-policy 并写库。
   备注：policy-func 是字符串形式的 Lisp 函数名（约定 com-hhub-policy-xxx），
         运行时 PDP 通过 (intern policy-func :nstores) 反射调用。"
 (clsql:update-records-from-instance (make-instance 'dod-auth-policy
						    :name name
						    :description description
						    :policy-func policy-func
						    :active-flg "Y" 
						    :tenant-id tenant-id
						    :deleted-state "N")))
 


(defun create-auth-policy (name description policy-func  company-instance)
  "PAP 入口：在指定租户下登记一条新策略。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (persist-auth-policy name description policy-func tenant-id)))


(defun seed-auth-policies (policylist)
  "种子数据初始化：批量创建系统策略（tenant_id=1）。
   policylist 每项 = (name description policy-func)。"
   (let ((company  (select-company-by-id 1)))
    (mapcar (lambda (policy)
	      (let ((name (nth 0 policy))
		    (description (nth 1 policy))
		    (policy-func (nth 2 policy)))
		(create-auth-policy name description policy-func company))) policylist))) 


;;;;;;;;;;;;;;;;;;;;; business logic for dod-auth-policy-attr ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun get-auth-policy-attr (tenant-id)
  "查询某租户下全部未软删的 策略-属性 关联。"
  (clsql:select 'dod-auth-policy-attr  :where [and [= [:deleted-state] "N"] [= [:tenant-id] tenant-id]]    :caching *dod-database-caching* :flatp t ))

(defun select-auth-policy-attr-by-company (company-instance)
  "列出某 company 下全部未删除的 策略-属性 关联记录。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
 (clsql:select 'dod-auth-policy-attr  :where
		[and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]]
     :caching *dod-database-caching* :flatp t )))



(defun update-auth-policy-attr (instance); This function has side effect of modifying the database record.
  "更新 策略-属性 关联记录。副作用：UPDATE。"
  (clsql:update-records-from-instance instance))

(defun delete-auth-policy-attr( id company-instance)
  "在指定租户下软删一条 策略-属性 关联。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (let ((dodauthpolicyattr (car (clsql:select 'dod-auth-policy-attr :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodauthpolicyattr 'deleted-state) "Y")
    (clsql:update-record-from-slot dodauthpolicyattr 'deleted-state))))



(defun delete-auth-policie-attrs ( list company-instance)
  "批量软删 策略-属性 关联（注意函数名 'policie' 应为 'policy'，命名笔误但保留以兼容调用方）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodauthpolicyattr (car (clsql:select 'dod-auth-policy-attr :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value dodauthpolicyattr 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodauthpolicyattr  'deleted-state))) list )))


(defun restore-deleted-auth-policy-attr ( list company-instance )
  "批量恢复软删的 策略-属性 关联。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
(mapcar (lambda (id)  (let ((dodauthpolicyattr (car (clsql:select 'dod-auth-policy-attr :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodauthpolicyattr 'deleted-state) "N")
    (clsql:update-record-from-slot dodauthpolicyattr 'deleted-state))) list )))

   

  
(defun persist-auth-policy-attr (policy-id attribute-id attr-val tenant-id )
  "底层持久化：构造 dod-auth-policy-attr 关联记录并写库。"
 (clsql:update-records-from-instance (make-instance 'dod-auth-policy-attr
						    :policy-id policy-id
						    :attribute-id attribute-id
						    :attr-val attr-val
						   :tenant-id tenant-id )))
 


(defun create-auth-policy-attr (policy-id attribute-id attr-val  company-instance)
  "PAP 入口：把一个属性挂到指定策略上，记录占位值 attr-val（用于 PAP UI 展示）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
	      (persist-auth-policy-attr policy-id attribute-id attr-val tenant-id))) 

