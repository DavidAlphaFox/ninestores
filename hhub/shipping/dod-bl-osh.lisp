;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：shipping 运费 / 配送
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/shipping/dod-bl-osh.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：运费方案 (dod-shipping-methods) 与邮编分区 (dod-vendor-ship-zones)
;;;;       的 CRUD 与计费业务逻辑。包含按重量+目的 PIN 在表格价 CSV 上查运费的
;;;;       核心算法 get-shipping-rate-from-table，以及购物车重量聚合。
;;;;
;;;; 主要导出：
;;;;   get-shipping-method-for-vendor          — 取卖家当前运费方案
;;;;   create-free-shipping-method             — 新建（首次）启用免运费方案
;;;;   getratetablecsv / getflatrateprice / getflatratetype / getminorderamt
;;;;                                           — 从方案实体上的便捷读取器
;;;;   get-shipping-rate-from-table            — 表格价计费核心算法
;;;;   getdefaultshippingmethod                — 取默认配送方式标识
;;;;   update-shipping-methods                 — 更新运费方案
;;;;   get-ship-zones-for-vendor               — 列出卖家所有邮编分区
;;;;   get-zonename-from-pincode               — 把目的 PIN 映射到分区名
;;;;   create-vendor-ship-zone / update-vendor-shipzone
;;;;   calculate-cartitems-weight-kgs          — 计算购物车总重量
;;;;
;;;; 关联：
;;;;   上游使用方：order/ 的下单结算流程、shipping/dod-ui-osh.lisp（卖家配置 UI）
;;;;   下游依赖：shipping/dod-dal-osh.lisp、cl-csv（解析 ratetablecsv）、
;;;;             cl-ppcre（PIN 前缀匹配）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)

(defun get-shipping-method-for-vendor (vendor company)
  "取某 (vendor, company) 当前生效的运费方案（active-flag='Y' 且未删）。
   返回：dod-shipping-methods 实例 / nil（卖家尚未配置运费方案时）。
   备注：每个 vendor 在某租户下应只配置一条运费方案。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
    (car (clsql:select 'dod-shipping-methods  :where
		       [and
		       [= [:deleted-state] "N"]
		       [= [:active-flag] "Y"]
		       [= [:tenant-id] tenant-id]
		       [= [:vendor-id] vendor-id]] :caching *dod-debug-mode* :flatp T ))))
  

(defun persist-free-shipping-method (minordamt vendor-id tenant-id)
  "底层持久化：若该 (vendor, tenant) 还没有运费方案，新建一条 freeshipenabled='Y' 的方案。
   minordamt — 启用免运费的最低订单金额门槛。
   备注：注释里强调"每个 vendor 仅一条"。已有则不重复插入。"
  (let ((shpmethod (car (clsql:select 'dod-shipping-methods  :where
				      [and
				      [= [:deleted-state] "N"]
				      [= [:active-flag] "Y"]
				      [= [:tenant-id] tenant-id]
				      [= [:vendor-id] vendor-id]] :caching *dod-debug-mode* :flatp T ))))
    ;; if we do not have a shipping method defined for a vendor, then create one.
    ;; making sure we only have one shipping method defined per vendor.
    (unless shpmethod 		   
      (clsql:update-records-from-instance (make-instance 'dod-shipping-methods
							 :minorderamt minordamt
							 :vendor-id vendor-id
							 :tenant-id tenant-id
							 :freeshipenabled "Y"
							 :active-flag "Y"
							 :deleted-state "N")))))



(defun create-free-shipping-method (minordamt vendor company)
  "UI 入口：为某卖家在某租户下首次启用免运费方案。"
   (let ((tenant-id (slot-value company 'row-id))
	 (vendor-id (slot-value vendor 'row-id)))
     (persist-free-shipping-method minordamt vendor-id tenant-id)))


(defun getratetablecsv (shippingmethod)
  "若启用了表格价（tablerateshipenabled），返回 ratetablecsv 字符串；否则 nil。"
  (let ((tablerateshipenabled (slot-value shippingmethod 'tablerateshipenabled))
	(ratetablecsv (slot-value shippingmethod 'ratetablecsv)))
    (when tablerateshipenabled ratetablecsv)))

(defun getflatrateprice (shippingmethod)
  "若启用了平价（flatrateshipenabled），返回 flatrateprice；否则 nil。"
  (let ((flatrateshipenabled (slot-value shippingmethod 'flatrateshipenabled))
	(flatrateprice (slot-value shippingmethod 'flatrateprice)))
    (when flatrateshipenabled flatrateprice)))

(defun getflatratetype (shippingmethod)
  "若启用了平价，返回平价类型字符串（订单级 / 件级，由 flatratetype 字段决定）；否则 nil。"
  (let ((flatrateshipenabled (slot-value shippingmethod 'flatrateshipenabled))
	(flatratetype (slot-value shippingmethod 'flatratetype)))
    (when flatrateshipenabled flatratetype)))



(defun get-shipping-rate-from-table (pincode weight vendor company)
  "表格价计费核心算法：根据收件 pincode + 重量在 ratetablecsv 上查运费。
   步骤：① 用 pincode 解析 zonename（"ZONE-A".."ZONE-E"）；② 解析 CSV，
        每行格式：(minkg, maxkg, zone-a, zone-b, zone-c, zone-d, zone-e)；
        ③ 找 weight ∈ [minkg, maxkg] 的行，再按 zonename 取列。
   异常：weight < 0.5kg 时通过 with-nst-error-handler 抛 nst-shipping-error。
   返回：浮点运费；查不到 zone 时返回 0.00。"
  (let* ((zonename (get-zonename-from-pincode pincode vendor company))
	 (ratetablecsv (getratetablecsv (get-shipping-method-for-vendor vendor company)))
	 (ratetablecontent (if ratetablecsv (cl-csv:read-csv ratetablecsv :skip-first-p T))))
    (with-nst-error-handler
	(if (< weight 0.5)
	    (error "Items weight in shopping cart is less than 0.5KG.")) 'nst-shipping-error)
    (if zonename
	(car (remove nil (mapcar (lambda (raterow)
				   (let ((minkg (float (read-from-string (nth 0 raterow))))
					 (maxkg (float (read-from-string (nth 1 raterow))))
					 (zone-a (float (read-from-string (nth 2 raterow))))
					 (zone-b (float (read-from-string (nth 3 raterow))))
					 (zone-c (float (read-from-string (nth 4 raterow))))
					 (zone-d (float (read-from-string (nth 5 raterow))))
					 (zone-e (float (read-from-string (nth 6 raterow)))))
				     (when (and (>= weight minkg) (<= weight maxkg))
				       (cond ((equal zonename "ZONE-A") zone-a)
					     ((equal zonename "ZONE-B") zone-b)
					     ((equal zonename "ZONE-C") zone-c)
					     ((equal zonename "ZONE-D") zone-d)
					     ((equal zonename "ZONE-E") zone-e))))) ratetablecontent)))
	;;else
	0.00)))
		    

(defun getminorderamt (freeshippingmethod)
  "若启用免运费，返回最低订单金额门槛 minorderamt；否则 nil。"
  (let ((freeshipenabled (slot-value freeshippingmethod 'freeshipenabled))
	(minorderamt (slot-value freeshippingmethod 'minorderamt)))
    (when freeshipenabled minorderamt)))

(defun getdefaultshippingmethod (shippingmethod)
  "返回方案的默认配送方式标识（无视各启用开关，直接读 defaultshippingmethod 字段）。"
  (let ((defaultshippingmethod (slot-value shippingmethod 'defaultshippingmethod)))
defaultshippingmethod))


(defun update-shipping-methods (shippingmethod); This function has side effect of modifying the database record.
  "把内存中已修改的 dod-shipping-methods 实例写回数据库。副作用：UPDATE。"
  (clsql:update-records-from-instance shippingmethod))


;; shipzone for a vendor

(defun get-ship-zones-for-vendor (vendor company)
  "列出某 (vendor, company) 下所有未删且启用的邮编分区。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
    (clsql:select 'dod-vendor-ship-zones  :where
		  [and
		  [= [:deleted-state] "N"]
		  [= [:active-flag] "Y"]
		  [= [:tenant-id] tenant-id]
		  [= [:vendor-id] vendor-id]] :caching *dod-debug-mode* :flatp T )))


(defun get-zonename-from-pincode (pincode vendor company)
  "把目的 pincode 映射到卖家定义的分区名（如 \"ZONE-A\"）。
   实现：遍历 shipzones，每个 zone 的 zipcoderangecsv 用 read-from-string 解析为列表，
        逐项用前缀正则 ^<zip> 匹配 pincode。
   返回：第一个命中的 zonename / nil。
   备注：原作者通过 cl-ppcre:count-matches > 0 实现"前缀匹配"。"
  (let* ((shipzones (get-ship-zones-for-vendor vendor company)))
    (car (remove nil (mapcar (lambda (shipzone)
			       (let ((zipcodes (read-from-string (slot-value shipzone 'zipcoderangecsv))))
				 (when zipcodes
				   (car (remove nil (mapcar (lambda (zipcode)
							      (when (> (cl-ppcre:count-matches (format nil "^~A" zipcode) pincode) 0)
								;;(format T "~A:~A~C" zipcode pincode #\newline)
								(slot-value shipzone 'zonename))) zipcodes)))))) shipzones)))))
  

(defun persist-vendor-ship-zone (zonename zipcoderangecsv vendor-id tenant-id)
  "底层持久化：INSERT 一条 dod-vendor-ship-zones。"
  (clsql:update-records-from-instance (make-instance 'dod-vendor-ship-zones
					 	     :vendor-id vendor-id
						     :tenant-id tenant-id
						     :zonename zonename
						     :zipcoderangecsv zipcoderangecsv
						     :active-flag "Y"
						     :deleted-state "N")))



(defun create-vendor-ship-zone (zonename zipcoderangecsv vendor company)
  "UI 入口：在指定卖家 + 租户下新建一个邮编分区。"
   (let ((tenant-id (slot-value company 'row-id))
	 (vendor-id (slot-value vendor 'row-id)))
     (persist-vendor-ship-zone zonename zipcoderangecsv vendor-id tenant-id)))




(defun update-vendor-shipzone (shipzone); This function has side effect of modifying the database record.
  "把内存中已修改的 dod-vendor-ship-zones 实例写回。副作用：UPDATE。"
  (clsql:update-records-from-instance shipzone))



(defun calculate-cartitems-weight-kgs (shopping-cart products)
  "估算购物车总重量 (kg)。
   算法：(总件数 × Σ 单品 shipping-weight-kg) / 不重复商品数。
   备注：推测此公式假设购物车里同一 SKU 多次入车被聚合，再按平均权重还原；
        实际效果是\"购物车数量 × 平均单件重\"。"
  (let* ((total-items (reduce #'+ (mapcar (lambda (item) (slot-value item 'prd-qty)) shopping-cart)))
	 (unique-prd-count (length products))
	 (total-weight (/ (* total-items (get-total-of products 'shipping-weight-kg)) unique-prd-count)))
    total-weight))
