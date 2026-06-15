;;; dod-bl-prd.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：products —— 商品 / 价格 / 类目 业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/products/dod-bl-prd.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：
;;;;   - 商品（dod-prd-master）的 CRUD、查询、激活/停用、批量导入；
;;;;   - 商品定价（dod-product-pricing）CRUD；
;;;;   - 商品类目（dod-prd-catg）的 nested-set 操作（add 根 / 子节点 / 删除子树）。
;;;;
;;;; 主要导出：
;;;;   activate-product / deactivate-product
;;;;   get-products / get-products-for-approval[-by-company]
;;;;   select-products-by-company / select-products-by-vendor / select-active-products-by-vendor
;;;;   select-product-by-id / select-product-by-name / search-products
;;;;   filter-products-by-category / filter-products-by-vendor / search-item-in-list
;;;;   update-prd-details / delete-product[s] / restore-deleted-products
;;;;   setAsSalesProduct / setAsServiceProduct
;;;;   persist-product-pricing / create-product-pricing / select-product-pricing-by-*
;;;;   persist-product / create-product / create-bulk-products
;;;;   get-prod-cat / get-root-prd-catg / select-prdcatg-by-* / persist-prdcatg / create-prdcatg
;;;;   add-root-prdcatg / add-new-node-prdcatg / add-new-prdcatg-node-as-child
;;;;   delete-prd-catg / delete-prdcatg[s] / restore-deleted-prdcatgs / update-prdcatg
;;;;   get-all-gst-sac-codes
;;;;
;;;; 关联：
;;;;   上游使用方：products/dod-ui-prd.lisp、订单 / 库存 / 购物车 / 商家仪表盘
;;;;   下游依赖：products/dod-dal-prd.lisp（实体）、core utils（hhub-random-password）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)




(defun get-all-gst-sac-codes ()
  :documentation "This function stores all the currencies in a hashtable. The Key = country, Value = list of currency, code and symbol.
   中文：把全部 dod-gst-sac-codes 装成 hashtable，Key=sac-code，Value=描述。
   备注：原英文 docstring 写的是 currencies hashtable，与实际不符（推测：复制模板未改）。"
  (let ((ht (make-hash-table :test 'equal))
	(sac-codes (clsql:select 'dod-gst-sac-codes 
		:caching *dod-database-caching* :flatp t )))
    (loop for saccd in sac-codes do
      (let ((key (slot-value saccd 'sac-code))
	    (value (slot-value saccd 'sac-description)))
	(setf (gethash key ht) value )))
    ; Return  the hash table. 
    ht))


(defun deactivate-product (id company)
  "停用商品上架（active-flag='N'）。副作用：UPDATE dod-prd-master。"
  (let ((product (select-product-by-id id company)))
    (setf (slot-value product 'active-flag) "N")
    (update-prd-details product)))

(defun activate-product (id company)
  "启用商品上架（active-flag='Y'）。副作用：UPDATE dod-prd-master。"
  (let ((product (select-product-by-id id company)))
    (setf (slot-value product 'active-flag) "Y")
    (update-prd-details product)))

(defun get-products-for-approval (tenant-id)
:documentation "This function will be used only by the superadmin user.
   中文：超级管理员视角列出指定租户下处于 PENDING 审批状态的商品 ——
         active-flag='Y' / approved-flag='N' / approval-status='PENDING' 的未删除商品。"
  (clsql:select 'dod-prd-master  :where
		[and
		[= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:approved-flag] "N"]
		[= [:tenant-id] tenant-id]
		[= [:approval-status] "PENDING"]]
		:caching *dod-database-caching* :flatp t ))



(defun get-products-for-approval-by-company (tenant-id)
  :documentation "This function will be used by the company administrator.
   中文：CAD 视角列出本租户下需要审批的商品（不限 approval-status，只看 approved-flag='N'）。"
  (clsql:select 'dod-prd-master  :where
		[and
		[= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:tenant-id] tenant-id]
		[= [:approved-flag] "N"]]
		:caching *dod-database-caching* :flatp t ))

(defun get-products (tenant-id)
  "获取租户下已上架且审批通过的商品（active-flag='Y' / approved-flag='Y'）。"
  (clsql:select 'dod-prd-master  :where
		[and
		[= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:approved-flag] "Y"]
		[= [:tenant-id] tenant-id]]    :caching *dod-database-caching* :flatp t ))

(defun select-products-by-company (company-instance)
  "列出某 company 下已上架且审批通过的商品，最多 500 条，按 row-id 倒序。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (clsql:select 'dod-prd-master  :where
		  [and 
		  [= [:active-flag] "Y"] 
		  [= [:deleted-state] "N"]
		  [= [:approved-flag] "Y"]
		  [= [:tenant-id] tenant-id]] :limit 500 :order-by '(([row-id] :desc)) 
					      :caching *dod-database-caching* :flatp t )))

(defun select-products-by-vendor (vendor company-instance)
  "列出指定商家的全部商品（含未上架/未审批），租户隔离 + 软删过滤。最多 200 条，row-id 倒序。"
  (let ((tenant-id (slot-value company-instance 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
    (clsql:select 'dod-prd-master  :where
		  [and
		  [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]
		  [=[:vendor-id] vendor-id]]  :limit 200 :order-by '( ([row-id] :desc))
					      :caching *dod-database-caching* :flatp t )))

(defun select-active-products-by-vendor (vendor company-instance)
  "列出指定商家已上架且审批通过的商品（active='Y' AND approved='Y'）。"
  (let ((tenant-id (slot-value company-instance 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
    (clsql:select 'dod-prd-master  :where
		  [and
		  [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]
		  [= [:active-flag] "Y"]
		  [= [:approved-flag] "Y"]
		  [=[:vendor-id] vendor-id]]  :limit 200 :order-by '(([row-id] :desc))
					      :caching *dod-database-caching* :flatp t )))


(defun search-item-in-list (key value list)
  "通用：在对象列表中按 (slot-value item key) 等于 value 查找首项。"
  (find value list
        :test #'equal
        :key (lambda (item) (slot-value item key))))



(defun filter-products-by-category (category-id list)
  "在内存的商品列表中过滤出 catg-id 等于 category-id 的子集。"
  (remove nil (mapcar (lambda (item)
			(if (equal category-id (slot-value item 'catg-id)) item)) list)))

(defun filter-products-by-vendor (vendor-id list)
  "在内存的商品列表中过滤出 vendor-id 等于给定值的子集。"
  (remove nil (mapcar (lambda (item)
			(if (equal vendor-id (slot-value item 'vendor-id)) item)) list)))


(defun prdinlist-p  (prd-id list)
  "判定 prd-id 是否出现在列表中（按各项的 prd-id slot 比较）。"
  (member prd-id (mapcar (lambda (item)
			   (slot-value item 'prd-id)) list) :test #'equal))

(defun iteminlist-p  (key value list)
  "通用：判断 value 是否出现在 list 各项的 key slot 中。"
  (member value (mapcar (lambda (item)
			  (slot-value item key)) list) :test #'equal))


(defun select-product-by-id (id company-instance )
  "按主键查商品（限定 tenant_id、过滤软删）。返回 dod-prd-master / nil。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
 (car (clsql:select 'dod-prd-master  :where
		[and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=[:row-id] id]]    :caching *dod-database-caching* :flatp t ))))

(defun select-product-pricing-by-id (id company-instance )
  "按主键查商品定价行（active='Y' 且未删）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (car (clsql:select 'dod-product-pricing  :where
		       [and
		       [= [:active-flag] "Y"]
		       [= [:deleted-state] "N"]
		       [= [:tenant-id] tenant-id]
		       [=[:row-id] id]]    :caching *dod-database-caching* :flatp t ))))

(defun select-product-pricing-by-product-id (product-id company-instance )
  "按 product-id 取该商品当前生效的定价（active='Y' 且未删，仅取第一条）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (car (clsql:select 'dod-product-pricing  :where
		       [and
		       [= [:active-flag] "Y"]
		       [= [:deleted-state] "N"]
		       [= [:product-id] product-id]
		       [= [:tenant-id] tenant-id]]
		        :caching *dod-database-caching* :flatp t ))))

(defun select-product-pricing-by-startdate (product-id start-date company-instance )
  "按 (product-id, start-date) 精确匹配定价记录（用以判断某起始日是否已存在记录）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (car (clsql:select 'dod-product-pricing  :where
		       [and
		       [= [:active-flag] "Y"]
		       [= [:deleted-state] "N"]
		       [= [:start-date] start-date]
		       [= [:product-id] product-id]
		       [= [:tenant-id] tenant-id]]
		        :caching *dod-database-caching* :flatp t ))))

(defun select-products-by-category (catg-id company-instance )
  "按类目 id 取已上架且审批通过的商品。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
	(clsql:select 'dod-prd-master :where [and
		 [= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:approved-flag] "Y"]
		[= [:tenant-id] tenant-id]
		[= [:catg-id] catg-id]]
				      :caching *dod-database-caching* :flatp t)))


(defun select-product-by-name (name-like-clause company-instance )
  "按 prd-name LIKE 模糊匹配，取首条。已上架 + 审批通过 + 未删。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (car (clsql:select 'dod-prd-master :where [and
		       [= [:deleted-state] "N"]
		       [= [:active-flag] "Y"]
		       [= [:approved-flag] "Y"]
		       [= [:tenant-id] tenant-id]
		       [like  [:prd-name] name-like-clause]]
				       :caching *dod-database-caching* :flatp t))))


(defun search-products ( search-string company-instance)
  "全文检索（仅商品名）：prd-name LIKE '%xxx%'。已上架 + 审批通过。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (clsql:select 'dod-prd-master :where [and
		  [= [:deleted-state] "N"]
		  [= [:active-flag] "Y"]
		  [= [:approved-flag] "Y"]
		  [= [:tenant-id] tenant-id]
		  [like [:prd-name] (format NIL "%~a%" search-string)]]
		  :caching *dod-database-caching* :flatp t)))


(defun update-prd-details (prd-instance); This function has side effect of modifying the database record.
  "把商品实例 UPDATE 回 DOD_PRD_MASTER。副作用：修改数据库记录。"
  (clsql:update-records-from-instance prd-instance))

(defun delete-product( id company-instance)
  "软删单条商品（在租户内）：deleted-state 置为 'Y'。"
  (let* ((tenant-id (slot-value company-instance 'row-id))
	 (dodproduct (car (clsql:select 'dod-prd-master :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodproduct 'deleted-state) "Y")
    (clsql:update-record-from-slot dodproduct 'deleted-state)))

(defun delete-product-pricing (id company-instance)
  "软删单条商品定价。"
  (let* ((tenant-id (slot-value company-instance 'row-id))
	 (prdpricing (car (clsql:select 'dod-product-pricing :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value prdpricing 'deleted-state) "Y")
    (clsql:update-record-from-slot prdpricing 'deleted-state)))

(defun delete-products ( list company-instance)
  "批量软删商品。list — 主键 id 列表。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodproduct (car (clsql:select 'dod-prd-master :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value dodproduct 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodproduct  'deleted-state))) list )))


(defun restore-deleted-products ( list company-instance )
  "批量恢复软删商品（deleted-state 改回 'N'）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
(mapcar (lambda (id)  (let ((dodproduct (car (clsql:select 'dod-prd-master :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodproduct 'deleted-state) "N")
    (clsql:update-record-from-slot dodproduct 'deleted-state))) list )))

(defun setAsSalesProduct (product)
  :documentation "Sets the Product type as Sales Product.
   中文：把商品标记为销售型（prd-type='SALE'）并保存。"
  (setf (slot-value product 'prd-type) "SALE")
  (update-prd-details product))


(defun setAsServiceProduct (product)
  :documentation "Sets the Product type as Service Product.
   中文：把商品标记为服务型（prd-type='SRVC'）并保存。"
  (setf (slot-value product 'prd-type) "SRVC")
  (update-prd-details product))


(defun persist-product-pricing (product-id price discount currency start-date end-date tenant-id)
  "底层持久化：构造 dod-product-pricing 并写库。默认 active-flag='Y'、deleted-state='N'。"
  (clsql:update-records-from-instance (make-instance 'dod-product-pricing
						     :product-id product-id
						     :price price
						     :discount discount
						     :currency currency
						     :start-date start-date
						     :end-date end-date
						     :active-flag "Y"
						     :tenant-id tenant-id
						     :deleted-state "N")))

(defun create-product-pricing (product price discount currency start-date end-date company)
  "在指定 product 与 company 下创建一条新的定价记录。
   参数：product — dod-prd-master；price/discount — 浮点；currency — 三字母代码；
        start-date/end-date — 生效起止日。"
  (let ((product-id (slot-value product 'row-id))
	(tenant-id (slot-value company 'row-id)))
    (persist-product-pricing product-id price discount currency start-date end-date tenant-id)))


(defun persist-product(prdname description vendor-id catg-id sku hsn-code qtyperunit unitofmeasure units-in-stock img-file-path subscribe-flag prd-type tenant-id )
  "底层持久化：构造一个 dod-prd-master 并写库。
   - current-price 默认 1.00、current-discount 默认 0.00（待 pricing 表覆盖）；
   - approved-flag 默认 'N'，approval-status 'PENDING'；
   - product-code 自动生成 'PRD-<10 位随机>'。
   副作用：INSERT DOD_PRD_MASTER。"
 (clsql:update-records-from-instance (make-instance 'dod-prd-master
				    :prd-name prdname
				    :description description
				    :vendor-id vendor-id
				    :catg-id catg-id
				    :sku sku
				    :hsn-code hsn-code
				    :qty-per-unit qtyperunit
				    :unit-of-measure unitofmeasure
				    :current-price 1.00
				    :current-discount 0.00
				    :units-in-stock units-in-stock
				    :prd-image-path img-file-path
				    :subscribe-flag subscribe-flag
				    :tenant-id tenant-id
				    :active-flag "Y"
				    :approved-flag "N"
				    :approval-status "PENDING"
				    :prd-type prd-type
				    :product-code (format nil "PRD-~A" (hhub-random-password 10))
				    :deleted-state "N")))

(defun create-bulk-products (modelfunc)
  "批量创建/更新商品。modelfunc 一次返回 productsdata 列表，每项 (product, product-pricing)；
   若数据库已存在同 row-id 的商品则更新若干字段（名称/单位/价/折扣/库存/订阅标志），
   否则直接插入。仅当对应商品存在且 product-pricing 非空时同步更新定价记录。
   副作用：批量 UPDATE / INSERT DOD_PRD_MASTER 与 DOD_PRODUCT_PRICING。"
  (multiple-value-bind (productsdata) (funcall modelfunc)
    (mapcar (lambda (prddata)
	      (let* ((product (first prddata))
		     (product-pricing (second prddata))
		     (prd-id (slot-value product 'row-id))
		     (company (product-company product))
		     (db-product (select-product-by-id prd-id company))
		     (db-product-pricing (select-product-pricing-by-product-id prd-id company)))
		(if db-product
		    (with-slots (prd-name  qty-per-unit unit-of-measure current-price current-discount units-in-stock subscribe-flag) product
		      (setf (slot-value db-product 'prd-name) prd-name)
		      (setf (slot-value db-product 'qty-per-unit) qty-per-unit)
		      (setf (slot-value db-product 'unit-of-measure) unit-of-measure)
		      (setf (slot-value db-product 'current-price) current-price)
		      (setf (slot-value db-product 'current-discount) current-discount)
		      (setf (slot-value db-product 'units-in-stock) units-in-stock)
		      (setf (slot-value db-product 'subscribe-flag) subscribe-flag)
		      (clsql:update-records-from-instance db-product))
		    ;;else
		    (clsql:update-records-from-instance product))
		;; Will update product pricing only if a product exists. 
		(if (and db-product product-pricing (check-null product-pricing))
		    (with-slots (price discount start-date end-date) product-pricing
		      (setf (slot-value db-product-pricing 'price) price)
		      (setf (slot-value db-product-pricing 'discount) discount)
		      (setf (slot-value db-product-pricing 'start-date) start-date)
		      (setf (slot-value db-product-pricing 'end-date) end-date)
		      (clsql:update-records-from-instance db-product-pricing))))) productsdata)))

(defun create-product (prdname description  vendor-instance category sku hsn-code qty-per-unit unit-of-measure units-in-stock img-file-path subscribe-flag prd-type company-instance)
  "事务包装的创建商品流程：
     1) persist-product 写主表
     2) 用 LAST_INSERT_ID() 取新商品的 row-id
     3) 调 create-product-pricing 写一条默认定价（价格 1.00、折扣 0、币种取公司账户币种、
        生效 90 天）
   失败时打印 'Transaction failed: ...'，不向上层抛异常。"
  (let ((vendor-id (slot-value vendor-instance 'row-id))
	(catg-id (if category (slot-value category 'row-id)))
	(tenant-id (slot-value company-instance 'row-id)))
    (handler-case
	(clsql:with-transaction ()
	  (persist-product prdname description vendor-id catg-id sku hsn-code qty-per-unit unit-of-measure units-in-stock img-file-path subscribe-flag prd-type  tenant-id)
	  (let* ((result (clsql:query "SELECT LAST_INSERT_ID()"))
		 (product-id (car result))
		 (newprd (select-product-by-id product-id company-instance)))
	    (create-product-pricing newprd 1.00 0.00 (get-account-currency company-instance) (clsql:get-date) (clsql:date+ (clsql:get-date) (clsql-sys:make-duration :day 90)) company-instance))) 
      (error (e)
	(format t "Transaction failed: ~A~%" e)))))

;(defun copy-products (src-company dst-company)
;    (let ((prdlist (select-products-by-company src-company)))
;	(mapcar (lambda (prd)
;		    (let ((temp  (setf (product-company prd) dst-company)))
;		    (clsql:update-records-from-instance prd ))) prdlist)))
	     
	      

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;PRODUCT CATEGORY RELATED FUNCTIONS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



(defun get-prod-cat (tenant-id)
  "列出某租户全部生效类目（active='Y' 且未删）。"
  (clsql:select 'dod-prd-catg  :where
		[and
		[= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:tenant-id] tenant-id]]    :caching nil :flatp t ))

(defun get-root-prd-catg (tenant-id)
  "取租户的 root 类目（catg-name='root'）—— nested set 树根。可能多条，按列表返回。"
  (clsql:select 'dod-prd-catg  :where
		[and
		[= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:tenant-id] tenant-id]
		[= [:catg-name] "root"]]    :caching nil :flatp t ))


(defun select-prdcatg-by-company (company-instance)
  "列出公司下除 root 外的全部类目（按 nested set 模型，root 只是占位）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (clsql:select 'dod-prd-catg  :where
		  [and
		  [= [:deleted-state] "N"]
		  [= [:active-flag] "Y"]
		  [<> [:catg-name] "root"]
		  [= [:tenant-id] tenant-id]]
     :caching nil :flatp t )))


(defun search-prdcatg-in-list (row-id list)
  "递归在 list 中按 row-id 查类目项；命中后返回该项。
   备注：list 为空或不匹配时会无限递归 / 报错（推测：调用方需保证 row-id 必然存在）。"
  (if (not (equal row-id (slot-value (car list) 'row-id))) (search-prdcatg-in-list row-id (cdr list))
	(car list)))

(defun prdcatginlist-p  (row-id list)
  "判定 row-id 是否出现在类目列表中（按 row-id 字段比较）。"
  (member row-id  (mapcar (lambda (item)
			    (slot-value item 'row-id)) list)))


(defun select-prdcatg-by-id (id company-instance )
  "按主键查类目（限定租户 + active='Y' + 未删）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
 (car (clsql:select 'dod-prd-catg  :where
		[and [= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:tenant-id] tenant-id]
		[=[:row-id] id]]    :caching *dod-database-caching* :flatp t ))))



(defun select-prdcatg-by-name (name-like-clause company-instance )
  "按 catg-name LIKE 查类目，取首条。"
      (let ((tenant-id (slot-value company-instance 'row-id)))
  (car (clsql:select 'dod-prd-catg :where [and
		[= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[= [:tenant-id] tenant-id]
		[like  [:catg-name] name-like-clause]]
		:caching *dod-database-caching* :flatp t))))

(defun add-root-prdcatg (company-instance)
  "为公司创建 nested set 根节点 (lft=1, rgt=2, catg-name='root')。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
    (persist-prdcatg "root" 1 2 tenant-id)))


(defun add-new-node-prdcatg (name company-instance)
  "在 nested set 树中往 'root' 之下追加一个叶子节点。
   流程：取 root 的 rgt 存到 @myRight；把所有 rgt > @myRight 的节点 rgt+=2，
   把 lft > @myRight 的节点 lft+=2，腾出空间；插入 (rgt+1, rgt+2) 作为新叶子。
   若 root 不存在则先 add-root-prdcatg 再 sleep 1 秒等记录可见。
   副作用：4 条 SQL 直接执行。"
  (let* ((tenant-id (slot-value company-instance 'row-id))
	 (rootprdcatg (get-root-prd-catg tenant-id))
	 (query1 (format nil "SELECT @myRight := rgt FROM DOD_PRD_CATG  WHERE catg_name = 'root' and tenant_id=~A; " tenant-id))
	 (command1 (format nil "UPDATE DOD_PRD_CATG  SET rgt = rgt + 2 WHERE rgt > @myRight;" ))
	 (command2 (format nil "UPDATE DOD_PRD_CATG SET lft = lft + 2 WHERE lft > @myRight; "))
	 (command3 (format nil "INSERT INTO DOD_PRD_CATG (catg_name, lft, rgt, tenant_id, active_flag, deleted_state ) VALUES('~A', @myRight + 1, @myRight + 2, ~A, 'Y', 'N');" name tenant-id)))
    ;; if root prd category is not present, create it first. 
    (unless rootprdcatg
      (add-root-prdcatg company-instance))
    ;; sleep for a second after creating a root prd category because we are going to query for it again. We do not want to fail.
    (sleep 1)
    (clsql:query query1 :field-names nil :flatp t)
    (clsql:execute-command command1 )
    (clsql:execute-command command2 )
    (clsql:execute-command command3 )))
    


(defun add-new-prdcatg-node-as-child (parentname childname  company-instance)
  "在 nested set 中把 childname 作为 parentname 的直接子节点插入。
   取 parent 的 lft 为 @myLeft，把所有 rgt > @myLeft 的 rgt+=2、lft > @myLeft 的 lft+=2，
   再插入 (lft=@myLeft+1, rgt=@myLeft+2) 作为新子节点。
   副作用：4 条 SQL 直接执行。"
  (let* ((tenant-id (slot-value company-instance 'row-id))
	 (query (format nil "SELECT @myLeft := lft FROM DOD_PRD_CATG WHERE catg_name = '~A' and tenant_id=~A;" parentname tenant-id))
	 (command2 (format nil "UPDATE DOD_PRD_CATG  SET rgt = rgt + 2 WHERE rgt > @myLeft;"))
	 (command3 (format nil "UPDATE DOD_PRD_CATG  SET lft = lft + 2 WHERE lft > @myLeft;"))
	 (command4 (format nil "INSERT INTO DOD_PRD_CATG (catg_name, lft, rgt, tenant_id, active_flag, deleted_state) VALUES('~A', @myLeft + 1, @myLeft + 2, ~A, 'Y', 'N');" childname tenant-id)))

  (clsql:query query :field-names nil :flatp t)
    (clsql:execute-command command2 )
    (clsql:execute-command command3 )
    (clsql:execute-command command4 )))


(defun delete-prd-catg (id company)
  "在 nested set 中删除整个子树（含给定节点）。
   取节点的 lft/rgt/width=rgt-lft+1，删除 lft∈[@myLeft,@myRight] 的所有行，
   再把 rgt > @myRight 的节点 rgt-=width、lft > @myRight 的节点 lft-=width 收紧空间。
   注意：是 *物理删除* 而非软删（与 delete-prdcatg 不同）。"
  (let* ((tenant-id (slot-value company 'row-id))
	 (query (format nil "SELECT @myLeft := lft, @myRight := rgt, @myWidth := rgt - lft + 1 FROM DOD_PRD_CATG  WHERE row_id = ~A and tenant_id=~A" id tenant-id))
	 (command1 (format nil "DELETE FROM DOD_PRD_CATG WHERE lft BETWEEN @myLeft AND @myRight;"))
	 (command2 (format nil "UPDATE DOD_PRD_CATG  SET rgt = rgt - @myWidth WHERE rgt > @myRight;"))
	 (command3 (format nil "UPDATE DOD_PRD_CATG  SET lft = lft - @myWidth WHERE lft > @myRight;")))
    
    (clsql:query query :field-names nil :flatp t)
    (clsql:execute-command command1 )
    (clsql:execute-command command2 )
    (clsql:execute-command command3 )))


(defun update-prdcatg (prdcatg-inst); This function has side effect of modifying the database record.
  "把类目实例 UPDATE 回 DOD_PRD_CATG。"
  (clsql:update-records-from-instance prdcatg-inst))

(defun delete-prdcatg( id company-instance)
  "软删单条类目（deleted-state='Y'）。注意：与 delete-prd-catg 的物理删除不同。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (let ((dodprdcatg (car (clsql:select 'dod-prd-catg :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodprdcatg 'deleted-state) "Y")
    (clsql:update-record-from-slot dodprdcatg 'deleted-state))))



(defun delete-prdcatgs ( list company-instance)
  "批量软删类目。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
  (mapcar (lambda (id)  (let ((dodprdcatg (car (clsql:select 'dod-prd-catg :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value dodprdcatg 'deleted-state) "Y")
			  (clsql:update-record-from-slot dodprdcatg  'deleted-state))) list )))


(defun restore-deleted-prdcatgs ( list company-instance )
  "批量恢复软删类目（deleted-state='N'）。"
    (let ((tenant-id (slot-value company-instance 'row-id)))
(mapcar (lambda (id)  (let ((dodprdcatg (car (clsql:select 'dod-prd-catg :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodprdcatg 'deleted-state) "N")
    (clsql:update-record-from-slot dodprdcatg 'deleted-state))) list )))




(defun persist-prdcatg(catgname lft rgt tenant-id )
  "底层持久化：构造 dod-prd-catg 并写库。供 add-root/add-new-node 等 nested set 入口使用。"
 (clsql:update-records-from-instance (make-instance 'dod-prd-catg
				    :catg-name catgname
				    :lft lft
				    :rgt rgt 
				    :tenant-id tenant-id
				    :active-flag "Y"
				    :deleted-state "N")))
 


(defun create-prdcatg (catgname lft rgt  company-instance)
  "上层包装：在指定 company 下创建一个类目（直接指定 lft/rgt，跳过 nested set 重平衡）。"
  (let ((tenant-id (slot-value company-instance 'row-id)))
      (persist-prdcatg catgname lft rgt tenant-id)))


