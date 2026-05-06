;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：shipping 运费 / 配送
;;;; 分层：UI / 控制器（部分函数实为对外部物流商 API 的封装）
;;;; 文件：hhub/shipping/dod-ui-osh.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：与外部物流聚合接口（如 Shiprocket / iThink 类）对接：
;;;;       - 体积重换算（5000 因子）
;;;;       - 全国分区 A..F 的展示标签初始化
;;;;       - 询价：按区（zonewise）+ 按 PIN 的两种 rate-check API 调用
;;;;       - 结果排序：用最大堆挑选离实际重量最近的 K 个 weight-slab 报价
;;;;
;;;; 主要导出：
;;;;   get-volumetric-weight                — l*b*h/5000 体积重
;;;;   define-shipping-zones                — 初始化 *HHUBSHIPPINGZONES* 哈希表
;;;;   order-shipping-rate-check-zonewise   — 调用 *HHUBLOGISTICSRATECHECKZONEWISEURL_PROD*
;;;;   order-shipping-rate-check            — 调用 *HHUBLOGISTICSRATECHECKURL_PROD*
;;;;   find-nearest-shipping-options        — 选 K 个最接近 weight 的报价
;;;;   find-nearest-elements                — 通用 K 近邻（数值列表版）
;;;;
;;;; 关联：
;;;;   上游使用方：order/ 下单结算前的运费询价、卖家后台对账
;;;;   下游依赖：drakma（HTTP）、cl-json、priority-queue、
;;;;             特殊变量 *HHUBLOGISTICSKEY* / *HHUBLOGISTICSSECRET* /
;;;;             *HHUBLOGISTICSRATECHECKURL_PROD* / *HHUBLOGISTICSRATECHECKZONEWISEURL_PROD*
;;;; ============================================================================

(in-package :nstores)


(defun get-volumetric-weight (l b h)
  "计算体积重 (kg) = (长 × 宽 × 高 cm³) / 5000。
   5000 是国际快递行业通用的体积重换算因子。"
  (float (/ (* l b h) 5000)))


(defun define-shipping-zones ()
  "初始化全局哈希表 *HHUBSHIPPINGZONES*，键为 \"A\"..\"F\"，值为分区中文/英文显示名。
   印度物流分区惯例：A 同城 / B 同州 / C 都市间 / D 其余 / E J&K+东北 / F 未定义。
   副作用：覆盖 *HHUBSHIPPINGZONES*。"
  (setf *HHUBSHIPPINGZONES* (make-hash-table :test 'equal))
  (setf (gethash "A" *HHUBSHIPPINGZONES*) "Zone A (Within City)")
  (setf (gethash "B" *HHUBSHIPPINGZONES*) "Zone B (Within State/region)")
  (setf (gethash "C" *HHUBSHIPPINGZONES*) "Zone C (Metro to Metro)")
  (setf (gethash "D" *HHUBSHIPPINGZONES*) "Zone D (Rest of India)")
  (setf (gethash "E" *HHUBSHIPPINGZONES*) "Zone E (J & K, North East)")
  (setf (gethash "F" *HHUBSHIPPINGZONES*) "Zone F (Undefined)"))
  


(defun order-shipping-rate-check-zonewise (products from-pincode)
  "调用外部物流询价 API（按分区版本）：拼装 JSON 并 POST 到
   *HHUBLOGISTICSRATECHECKZONEWISEURL_PROD*。
   payload：from-pincode、长宽高合计、总重量、商品 MRP、订单类型 forward/payment_method prepaid，
            以及鉴权字段 access_token / secret_key。
   返回：物流商响应原文（已用 code-char 解码为字符串，未做 JSON 解析）。"
  (let* ((total-length (format nil "~d" (get-total-of products 'shipping-length-cms)))
	 (total-width (format nil "~d" (get-total-of products 'shipping-width-cms)))
	 (total-height (format nil "~d" (get-total-of products 'shipping-height-cms)))
	 (total-weight (format nil "~d" (get-total-of products 'shipping-weight-kg)))
	 (total-price (format nil "~d" (get-total-of products 'unit-price)))
	 (order-type "forward")
	 (payment-method "prepaid")
	 (paramname (list "from_pincode" "shipping_length_cms" "shipping_width_cms" "shipping_height_cms" "shipping_weight_kg" "order_type" "payment_method" "product_mrp" "access_token" "secret_key"))
	 (paramvalue (list from-pincode  total-length total-width total-height total-weight order-type payment-method total-price *HHUBLOGISTICSKEY*   *HHUBLOGISTICSSECRET* ))
	 (param-alist (pairlis paramname paramvalue))
	 (datajson nil))
    
    (setf datajson (acons "data" param-alist datajson))
    (setf datajson (json:encode-json-to-string datajson))
    (map 'string 'code-char (drakma:http-request  *HHUBLOGISTICSRATECHECKZONEWISEURL_PROD*
			 :content-type "application/json"
			 :content datajson
			 :method :POST))))





(defun order-shipping-rate-check (shopping-cart products from-pincode to-pincode)
  "结算页询价（PIN-to-PIN）：根据购物车与商品列表估算长宽高，POST 到
   *HHUBLOGISTICSRATECHECKURL_PROD* 取多家物流商可选报价。
   尺寸推算：从总重量反推等长方体三边 final-lwh = ³√(5000 × weight)，
            再做 5cm 步长对齐，得到 dimension1/2/3。
   备注：注释中提到 \"There is a bug in the rate check API\"——重量 > 5kg 时
        外部 API 不返回数据，本函数因此用 (unless (> total-weight 5.0) ...) 跳过。
   返回：经 find-nearest-shipping-options 排序与去重后，每家物流商一条最接近实际
        重量的 weight-slab 报价行；外部跳过时返回 nil。"
  (let* ((total-items (reduce #'+ (mapcar (lambda (item) (slot-value item 'prd-qty)) shopping-cart)))
	 (total-weight (calculate-cartitems-weight-kgs shopping-cart products))
	 (final-lwh (expt (* 5000 total-weight) 1/3))
	 (dimension1 (floor (- final-lwh (mod final-lwh 5))))
	 (dimension2 dimension1)
	 (dimension3 (floor (/ (* 5000 total-weight) (* dimension1 dimension2))))
	 (total-price (format nil "~d" (* total-items (get-total-of products 'current-price))))
	 (order-type "forward")
	 (payment-method "prepaid")
	 (paramname (list "from_pincode" "to_pincode" "shipping_length_cms" "shipping_width_cms" "shipping_height_cms" "shipping_weight_kg" "order_type" "payment_method" "product_mrp" "access_token" "secret_key"))
	 (paramvalue (list from-pincode to-pincode  (format nil "~d" dimension3) (format nil "~d" dimension1) (format nil "~d" dimension2)  total-weight order-type payment-method total-price *HHUBLOGISTICSKEY*   *HHUBLOGISTICSSECRET* ))
	 (param-alist (pairlis paramname paramvalue))
	 (datajson nil))

    ;;(logiamhere (format nil "from ~A to ~A ~C " from-pincode to-pincode #\newline))
    ;;(logiamhere (format nil "Total items - ~d ~C" total-items #\newline))
    ;;(logiamhere (format nil  "Length - ~d ~C" dimension3  #\newline))
    ;;(logiamhere (format nil "width - ~d ~C" dimension1 #\newline))
    ;;(logiamhere (format nil "height - ~d ~C" dimension2 #\newline))
    ;;(logiamhere (format nil "total weight - ~d ~C" total-weight #\newline))
    ;;(logiamhere (format nil "volumetric weight - ~d ~C" (/ (expt final-lwh 3) 5000) #\newline))
       
    (setf datajson (acons "data" param-alist datajson))
    (setf datajson (json:encode-json-to-string datajson))
    ;;(format t "~A" datajson)
    ;; There is a bug in the rate check API, where we are not getting response if the total weight is beyond 5 KG. 
    (unless (> total-weight 5.0)
      (let* ((json-response (json:decode-json-from-string  (map 'string 'code-char (drakma:http-request *HHUBLOGISTICSRATECHECKURL_PROD*
													:content-type "application/json"
													:content datajson
													:method :POST))))
	     (data (cdr (nth 2 json-response)))
	     (zone (cdr (nth 3 json-response)))
	     (exp-delivery-date (cdr (nth 4 json-response)))
	     (shippingoptions (sort (remove nil (mapcar (lambda (logistic-alist)
							  (let ((logistic-name (cdr (nth 0 logistic-alist)))
								(logistic-service-type (cdr (nth 1 logistic-alist)))
								(logistic-id (cdr (nth 2 logistic-alist)))
								(rtocharges (cdr (nth 3 logistic-alist))) 
								(prepaid-p (cdr (nth 4 logistic-alist))) 
								(cod-p (cdr (nth 5 logistic-alist)))  
								(pickup-p (cdr (nth 6 logistic-alist)))   
								(reverse-pickup-p (cdr (nth 7 logistic-alist)))
								(weight-slab (float (with-input-from-string (in (cdr (nth 8 logistic-alist)))
										      (read in))))   
								(rate (cdr (nth 9 logistic-alist))))    
							    (when (<= total-weight weight-slab)
							      (list logistic-name logistic-service-type logistic-id rtocharges prepaid-p cod-p pickup-p reverse-pickup-p weight-slab rate zone exp-delivery-date)))) data)) #'< :key (lambda (elem) (nth 8 elem))))
	     (uniqueshipproviders (remove-duplicates (mapcar (lambda (elem)
							       (nth 0 elem)) shippingoptions) :test #'equal))
             (nearestweightslabs (find-nearest-shipping-options shippingoptions total-weight (length uniqueshipproviders))))
	;;(logiamhere (format nil "shipping options: ~A" shippingoptions))
	;;(logiamhere (format nil "nearest weight slabs : ~A" nearestweightslabs))
	;;(logiamhere (format nil  "unique shipping providers = ~d" (length uniqueshipproviders)))
	nearestweightslabs))))


(defun find-nearest-shipping-options (list x k)
  "在物流报价列表中挑选 weight-slab（每行第 9 项，即 (nth 8 elem)）最接近 x 的 K 条。
   算法：用最大堆，priority = |x - slab|；超出 K 个就弹出最远的。
   输出顺序与堆弹出顺序相反（reverse），让最接近的排在前面。"
  ;; Create a priority queue to store the K nearest numbers of a list.
  (let ((maxheap (priority-queue:make-pqueue #'>))
	(targetlist nil))
    (loop for elem in list do
      (priority-queue:pqueue-push elem (abs (- x (nth 8 elem))) maxheap)
	(if (> (priority-queue:pqueue-length maxheap) k)
	    (priority-queue:pqueue-pop maxheap)))

    (loop for i from 1 to (priority-queue:pqueue-length maxheap)
	  do
	     (setf targetlist (append targetlist (list (priority-queue:pqueue-front-value maxheap))))
	     (priority-queue:pqueue-pop maxheap))
    (reverse (remove nil targetlist))))


(defun find-nearest-elements (list x k)
  "K 近邻通用版（数值元素）：返回 list 中最接近 x 的 K 个数。
   备注：与 find-nearest-shipping-options 算法相同，但元素本身就是数。
   输出未做 reverse —— 顺序按堆弹出 (即从远到近)。"
  ;; Create a priority queue to store the K nearest numbers of a list.
  (let ((maxheap (priority-queue:make-pqueue #'>))
	(targetlist nil))
    (loop for elem in list do
      (priority-queue:pqueue-push elem (abs (- x elem)) maxheap)
	(if (> (priority-queue:pqueue-length maxheap) k)
	    (priority-queue:pqueue-pop maxheap)))

    (loop for i from 1 to (priority-queue:pqueue-length maxheap)
	  do (setf targetlist (append targetlist (list (priority-queue:pqueue-front-value maxheap)))))
    (remove nil targetlist)))
