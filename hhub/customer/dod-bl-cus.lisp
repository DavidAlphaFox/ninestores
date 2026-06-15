;;; dod-bl-cus.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：customer 客户（旧风格 dod-）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/customer/dod-bl-cus.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：客户主档 dod-cust-profile + 客户钱包 dod-cust-wallet 的 CRUD 与领域规则；
;;;;       同时实现地址/邮编查询 DDD 服务（AddressService / Address-Adapter / Presenter）
;;;;       与外部 pincode API 适配器（基于 TCUF 状态码 T/F/U/C 容错）。
;;;;
;;;; 主要导出：
;;;;   客户档案：
;;;;     find-customer-by-gstin / find-customer-by-pan / find-customer-by-company-name
;;;;     get-b2b-customers / get-b2c-customers
;;;;     is-b2b-customer-p / is-b2c-customer-p / get-customer-display-name
;;;;     update-kyc-status / update-customer-metrics / get-top-customers
;;;;     validate-gstin-format / extract-pan-from-gstin / extract-state-code-from-gstin
;;;;     auto-populate-from-gstin / get-state-name-from-code
;;;;     create-b2b-customer / create-b2c-customer / create-customer / create-guest-customer
;;;;     select-customer-by-name / select-customer-list-by-name / select-customer-list-by-phone
;;;;     select-customer-by-phone / select-customers-for-company / select-customers-for-vendor
;;;;     select-customer-for-vendor-by-phone / select-guest-customer
;;;;     select-customer-by-id / select-customer-by-email / select-deleted-customer-by-id
;;;;     update-customer / duplicate-customerp / reset-customer-password
;;;;     delete-customer / restore-deleted-customer / delete-cust-profile /
;;;;     delete-cust-profiles / restore-deleted-cust-profile
;;;;   钱包：
;;;;     create-wallet / persist-wallet / check-wallet-balance / check-low-wallet-balance /
;;;;     check-zero-wallet-balance / deduct-wallet-balance / set-wallet-balance /
;;;;     update-cust-wallet-balance / get-cust-wallets / get-cust-wallets-for-vendor /
;;;;     get-cust-wallet-by-vendor / get-cust-wallet-by-id
;;;;   地址 / 邮编：
;;;;     ProcessRequest / ProcessResponse / CreateViewModel / doService（地址 DDD 链）
;;;;     get-pincode-details-adapter（外部 API 调用，TCUF 容错）/ getpincodedetails（本地缓存）/
;;;;     getpincodedetails-old（保留旧实现）
;;;;
;;;; 关联：
;;;;   上游使用方：customer/dod-ui-cus.lisp、order / invoice / paymentgateway 等。
;;;;   下游依赖：customer/dod-dal-cus.lisp、core 的 *NSTGSTSTATECODES-HT* /
;;;;             *NST-ALL-INDIA-PINCODES* 缓存、check&encrypt / hhub-random-password
;;;;             （密码工具）、drakma（HTTP 客户端）。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



;(defmacro defservicemethod  (method-name params &body body)
;  `(defmethod ,method-name ((,instance-name ,instance-of) ,params)
;    (let* ((repository (cdr (assoc "repository" ,params :test 'equal)))
;	    (bo-key (cdr (assoc "bo-key" ,params :test 'equal)))
;	    (bo-ht  (slot-value repository 'businessobjects))
;	    (busobject (gethash bo-key bo-ht)))
;      ,@body)))

;(defservicemethod (service AddressService) params
;  (let ((pincode (slot-value busobject 'pincode)))
;    (getpincodedetails pincode)))


;;; Customer Profile Queries

(defun find-customer-by-gstin (gstin)
  "按 GSTIN（印度税号，15 位）查客户。过滤 active-flag='Y' / deleted-state='N'。
   注意：未限定 tenant_id，跨租户取首条 —— 应是 B2B 全局唯一性，推测：
   原意是平台级判断 GSTIN 是否已注册过。
   返回：单个 dod-cust-profile / nil。"
  (car (clsql:select 'dod-cust-profile
                     :where [and [= [gstin] gstin]
                                 [= [active-flag] "Y"]
                                 [= [deleted-state] "N"]]
                     :flatp t)))

(defun find-customer-by-company-name (company-name)
  "按 company-name 模糊匹配（自动加 % 通配）查客户。未限定 tenant_id。返回列表。"
  (clsql:select 'dod-cust-profile
                :where [and [like [company-name] (concatenate 'string "%" company-name "%")]
                            [= [active-flag] "Y"]
                            [= [deleted-state] "N"]]
                :flatp t))

(defun find-customer-by-pan (pan-number)
  "按印度 PAN 号查客户。未限定 tenant_id。返回单个 / nil。"
  (car (clsql:select 'dod-cust-profile
                     :where [and [= [pan-number] pan-number]
                                 [= [deleted-state] "N"]]
                     :flatp t)))

(defun get-b2b-customers (&optional (tenant-id nil))
  "列出全部 B2B 客户（gst-customer-type='B2B' 且 GSTIN 非空）。
   按 company-name 升序。tenant-id 可选 —— 给定时仅在租户内查；不给则跨租户。"
  (clsql:select 'dod-cust-profile
                :where (if tenant-id
                          [and [= [gst-customer-type] "B2B"]
                               [is-not-null [gstin]]
                               [= [active-flag] "Y"]
                               [= [tenant-id] tenant-id]
                               [= [deleted-state] "N"]]
                          [and [= [gst-customer-type] "B2B"]
                               [is-not-null [gstin]]
                               [= [active-flag] "Y"]
                               [= [deleted-state] "N"]])
                :order-by '([company-name])
                :flatp t))

(defun get-b2c-customers (&optional (tenant-id nil))
  "列出全部 B2C 客户：满足 (gst-customer-type='B2C' OR GSTIN 为空 OR business-type='INDIVIDUAL')
   且 active-flag='Y' / 未软删。按 name 升序；tenant-id 可选。"
  (clsql:select 'dod-cust-profile
                :where (if tenant-id
                          [and [or [= [gst-customer-type] "B2C"]
                                   [is-null [gstin]]
                                   [= [business-type] "INDIVIDUAL"]]
                               [= [active-flag] "Y"]
                               [= [tenant-id] tenant-id]
                               [= [deleted-state] "N"]]
                          [and [or [= [gst-customer-type] "B2C"]
                                   [is-null [gstin]]
                                   [= [business-type] "INDIVIDUAL"]]
                               [= [active-flag] "Y"]
                               [= [deleted-state] "N"]])
                :order-by '([name])
                :flatp t))

;;; Customer Type Detection

(defun is-b2b-customer-p (customer)
  "判定客户是否为 B2B：必须有 GSTIN 且其去空格后长度 = 15。返回布尔。"
  (and (slot-value customer 'gstin)
       (= 15 (length (string-trim " " (slot-value customer 'gstin))))))

(defun is-b2c-customer-p (customer)
  "判定客户是否为 B2C：is-b2b-customer-p 的反义。"
  (not (is-b2b-customer-p customer)))

(defun get-customer-display-name (customer)
  "根据客户类型返回合适的展示名：
   - B2B：优先 company-name，其次 legal-name，最后 name。
   - B2C：优先 fullname，其次 name，再次 firstname+lastname。"
  (if (is-b2b-customer-p customer)
      (or (slot-value customer 'company-name)
          (slot-value customer 'legal-name)
          (slot-value customer 'name))
      (or (slot-value customer 'fullname)
          (slot-value customer 'name)
          (format nil "~A ~A" 
                  (slot-value customer 'firstname)
                  (slot-value customer 'lastname)))))

;;; KYC Management

(defun update-kyc-status (customer-id status verified-by)
  "更新客户 KYC 状态。当 status='VERIFIED' 时同时记录验证时间和验证人 verified-by
   （应为 dod-users.row-id）。
   副作用：UPDATE dod-cust-profile。返回更新后的客户实例 / nil（未找到）。"
  (let ((customer (car (clsql:select 'dod-cust-profile
                                     :where [= [row-id] customer-id]
                                     :flatp t))))
    (when customer
      (setf (slot-value customer 'kyc-status) status)
      (when (string= status "VERIFIED")
        (setf (slot-value customer 'kyc-verified-date) (clsql:get-time))
        (setf (slot-value customer 'kyc-verified-by) verified-by))
      (clsql:update-records-from-instance customer)
      customer)))

;;; Business Metrics

(defun update-customer-metrics (customer-id order-amount)
  "客户下新订单后更新统计字段：total-orders 自增、total-spent 累加 order-amount、
   last-order-date 设为当前时间。副作用：UPDATE dod-cust-profile。"
  (let ((customer (car (clsql:select 'dod-cust-profile
                                     :where [= [row-id] customer-id]
                                     :flatp t))))
    (when customer
      (incf (slot-value customer 'total-orders))
      (incf (slot-value customer 'total-spent) order-amount)
      (setf (slot-value customer 'last-order-date) (clsql:get-time))
      (clsql:update-records-from-instance customer)
      customer)))

(defun get-top-customers (limit &key (by-amount t))
  "取前 limit 名活跃客户。by-amount=T 按 total-spent 降序；为 nil 按 total-orders 降序。"
  (clsql:select 'dod-cust-profile
                :where [and [= [active-flag] "Y"]
                            [= [deleted-state] "N"]]
                :order-by (if by-amount
                             '(([total-spent] :desc))
                             '(([total-orders] :desc)))
                :limit limit
                :flatp t))

;;; GST Validation

(defun validate-gstin-format (gstin)
  "校验 GSTIN 格式：15 字符，正则
   ^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$
   （前 2 位州码、5 位 PAN 字母、4 位数字、1 位字母、1 位数字/字母、固定 'Z'、1 位校验码）。"
  (and gstin
       (= 15 (length gstin))
       (cl-ppcre:scan "^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$"
                      gstin)))

(defun extract-pan-from-gstin (gstin)
  "从 GSTIN 第 3-12 位（0-based 2..12）切出 PAN。仅在格式合法时返回，否则 nil。"
  (when (validate-gstin-format gstin)
    (subseq gstin 2 12)))

(defun extract-state-code-from-gstin (gstin)
  "从 GSTIN 前两位切出印度州代码。仅在格式合法时返回，否则 nil。"
  (when (validate-gstin-format gstin)
    (subseq gstin 0 2)))

(defun auto-populate-from-gstin (customer)
  "若 customer.gstin 合法，自动补齐 pan-number 与 registered-state（仅在它们为空时填）。
   副作用：UPDATE dod-cust-profile。常用于 B2B 客户创建后立刻派生字段。"
  (when (and (slot-value customer 'gstin)
             (validate-gstin-format (slot-value customer 'gstin)))
    (unless (slot-value customer 'pan-number)
      (setf (slot-value customer 'pan-number)
            (extract-pan-from-gstin (slot-value customer 'gstin))))
    (unless (slot-value customer 'registered-state)
      (let ((state-code (extract-state-code-from-gstin (slot-value customer 'gstin))))
        (setf (slot-value customer 'registered-state)
              (get-state-name-from-code state-code))))
    (clsql:update-records-from-instance customer)))


(defun get-state-name-from-code (state-code)
  "把 GSTIN 州代码（如 \"27\"）映射到州名，查启动期缓存的 *NSTGSTSTATECODES-HT*。"
 (gethash state-code *NSTGSTSTATECODES-HT*))



;;; Customer Creation

(defun create-b2b-customer (company-name gstin &key legal-name email phone
                                          business-type organization-type
                                          primary-contact-name tenant-id)
  "新建 B2B 客户：写入 DOD_CUST_PROFILE，关键字段固定为 gst-customer-type='B2B'，
   business-type 默认 'OTHER'、organization-type 默认 'COMPANY'。
   username 暂用 email、password 暂用占位符 'PLACEHOLDER'（注释提示后续会切到
   DOD_CUSTOMER_USERS 新表）。
   写库后立刻 auto-populate-from-gstin 补 PAN/州。返回新建客户实例。"
  (let ((customer (make-instance 'dod-cust-profile
                                 :company-name company-name
                                 :legal-name (or legal-name company-name)
                                 :name company-name
                                 :gstin gstin
                                 :gst-customer-type "B2B"
                                 :business-type (or business-type "OTHER")
                                 :organization-type (or organization-type "COMPANY")
                                 :email email
                                 :phone phone
                                 :primary-contact-name primary-contact-name
                                 :username email  ; Temporary - will use DOD_CUSTOMER_USERS
                                 :password "PLACEHOLDER"  ; Will be set via DOD_CUSTOMER_USERS
                                 :active-flag "Y"
                                 :created (clsql:get-time)
                                 :updated (clsql:get-time)
                                 :tenant-id tenant-id
                                 :deleted-state "N")))
    
    ;; Auto-populate from GSTIN
    (auto-populate-from-gstin customer)
    
    (clsql:update-records-from-instance customer)
    customer))

(defun create-b2c-customer (name email phone &key firstname lastname tenant-id)
  "构造一个 B2C 客户实例（**不写库**，仅 make-instance）。
   默认 gst-customer-type='B2C'、business-type='INDIVIDUAL'、密码占位 'PLACEHOLDER'。
   返回 dod-cust-profile 实例（调用方需要时自行 update-records-from-instance）。"
  (make-instance 'dod-cust-profile
                 :name name
                 :firstname firstname
                 :lastname lastname
                 :fullname name
                 :email email
                 :phone phone
                 :gst-customer-type "B2C"
                 :business-type "INDIVIDUAL"
                 :organization-type "INDIVIDUAL"
                 :username email
                 :password "PLACEHOLDER"
                 :active-flag "Y"
                 :created (clsql:get-time)
                 :updated (clsql:get-time)
                 :tenant-id tenant-id
                 :deleted-state "N")) 

;;更新客户的钱包余额
(defun update-cust-wallet-balance (amount wallet-id)
  "把 wallet-id 对应钱包余额加上 amount（amount 可正可负，正为充值/退款，负为扣款）。
   通过当前登录客户的 company 读权限范围内的钱包。
   副作用：UPDATE DOD_CUST_WALLET.balance。"
  (let* ((wallet (get-cust-wallet-by-id wallet-id (get-login-customer-company)))
	 (current-balance (slot-value wallet 'balance))
	 (latest-balance (+ current-balance amount)))
    (set-wallet-balance latest-balance wallet)))


;;处理客户的结果
(defmethod ProcessResponse ((service Address-Adapter)  params)
  "Address-Adapter 把 params 中名为 \"address\" 的地址领域对象转成 ResponseAddress。
   字段一一拷贝。返回 ResponseAddress 实例。"
  (let* ((address (cdr (assoc "address" params :test 'equal)))
	 (responsemodel (make-instance 'ResponseAddress)))
    
    (with-slots (house-no street locality city state pincode country longitude latitude) address
      (setf (slot-value responsemodel 'house-no) house-no)
      (setf (slot-value responsemodel 'street) street)
      (setf (slot-value responsemodel 'locality) locality)
      (setf (slot-value responsemodel 'city) city)
      (setf (slot-value responsemodel 'state) state)
      (setf (slot-value responsemodel 'pincode) pincode)
      (setf (slot-value responsemodel 'country) country)
      (setf (slot-value responsemodel 'latitude) latitude)
	(setf (slot-value responsemodel 'longitude) longitude))
    ;; return the responsemodel
    responsemodel))
    
;;显示用户地址信息
(defmethod CreateViewModel ((service Address-Presenter) (responsemodel ResponseAddress))
  "Address-Presenter 把 ResponseAddress（含全部 9 字段）压成 AddressViewModel
   （仅展示 4 字段：locality / city / state / pincode），并把结果存到 service.viewmodel。"
  (let ((viewmodel (make-instance 'AddressViewModel)))
    (with-slots (locality city state pincode) responsemodel
      (setf (slot-value viewmodel 'locality) locality)
      (setf (slot-value viewmodel 'city) city)
      (setf (slot-value viewmodel 'state) state)
      (setf (slot-value viewmodel 'pincode) pincode)
      ;;return the viewmodel
      (setf (slot-value service 'viewmodel) viewmodel)
      viewmodel)))

;; Service layer implementation for the pincode check.
;; We would need to have a BusinessService which takes requestmodel as parameter
(defmethod doService ((service AddressService) requestmodel)
  "AddressService 主用例：取 requestmodel.pincode 调 getpincodedetails 拿到 address 对象。"
  (let* ((pincode (slot-value requestmodel 'pincode)))
    (getpincodedetails pincode)))

(defmethod ProcessRequest ((service Address-Adapter)  params)
  :description "Original English. 中文：地址 Adapter 主入口。把 params 中的 pincode
   写到 RequestPincode 上、设置 businessservice / 方法名，再 call-next-method 让父类
   调 doservice 拿到 address；之后用 ProcessResponse 把 address 转成 ResponseAddress。"
  (let* ((pincode (cdr (assoc "pincode" params :test 'equal)))
	   (requestmodel (make-instance 'RequestPincode)))      
      (setf (slot-value service 'businessservice) (find-class  'AddressService))
      (setf (slot-value service 'businessservicemethod) "doservice")
      (setf (slot-value requestmodel 'pincode) pincode)
      (setf (slot-value service 'requestmodel) requestmodel)
    (let ((addressobj (call-next-method))
	    (params nil)) 
	(setf params (acons "address" addressobj params))
	(processresponse service params))))


(defun get-pincode-details-adapter (pincode)
  "TCUF Boundary Adapter for Pincode lookup. 中文：调用印度政府 pincode API
   （*hhubgetpincodeurlexternal*）的边界适配器，按 TCUF 协议返回二值
   (ADDRESS/NIL  STATUS) —— STATUS ∈ {:T 成功、:F 确定失败、:U 未知/可能瞬态、:C 矛盾/异常}。
   - HTTP 200 + 数据齐全 → :T
   - HTTP 200 + 数据缺失 → :F
   - HTTP 4xx → :F；HTTP 5xx → :U；其他 (3xx 等) → :C
   - JSON 解析错 → :C；网络超时 → :U；其他异常 → :C
   备注：解析逻辑里的 (nth 1 (nth 24 json-response)) 直接按位置访问外部 API 返回结构，
        外部 schema 变化会导致解析失败（推测：API 形态较稳定才能这么写）。"
  (let* ((address (make-instance 'address))
         (param-name (list "api-key" "format" "offset" "limit" "filters[pincode]"))
         (param-values (list *hhubapi.gov.in.key* "json" "0" "1" (format nil "~A" pincode)))
         (param-alist (pairlis param-name param-values)))

    (handler-case
        (multiple-value-bind (body status)
            ;; Drakma call. We capture the body (1st value) and status code (2nd value).
            (drakma:http-request *hhubgetpincodeurlexternal*
                                 :method :GET
                                 :parameters param-alist)

          ;; --- INTERPRETATION LOGIC (MAPPING STATUS CODE) ---

          (cond
            ;; 1. SUCCESS: HTTP 200 (Proceed to Data Quality Check)
            ((= status 200)
             (handler-case
                 (let* ((json-response (json:decode-json-from-string (map 'string 'code-char body)))
			(locality (cdr (assoc :OFFICENAME (nth 1 (nth 24 json-response)) :test 'equal)))
			(city (cdr (assoc :DISTRICTNAME (nth 1 (nth 24 json-response)) :test 'equal)))
			(division (cdr (assoc :DIVISIONNAME (nth 1 (nth 24 json-response)) :test 'equal)))
			(state (cdr (assoc :STATENAME (nth 1 (nth 24 json-response)) :test 'equal))))
		   (format t "locality=~A, city=~A, division =~A, state=~A" locality city division state)
                   ;; --- DATA QUALITY CHECK (MAPPING JSON CONTENT) ---
                   (if (and locality city state)
		       (progn
			 (setf (slot-value address 'pincode) pincode)
			 ;; Remove the S.O from the locality string.
			 (setf (slot-value address 'house-no) "")
			 (setf (slot-value address 'street) "")
			 (setf (slot-value address 'country) "")
			 (setf (slot-value address 'longitude) "")
			 (setf (slot-value address 'latitude) "")
			 (setf (slot-value address 'locality) (string-trim "S.O" locality))
			 (setf (slot-value address 'city) (format nil "~A, ~A" division city))
			 (setf (slot-value address 'state) state)
			 (values address :T))
                       ;;else
		       (progn
			 (setf (slot-value address 'pincode) pincode)
			 (setf (slot-value address 'house-no) "")
			 (setf (slot-value address 'street) "")
			 (setf (slot-value address 'country) "")
			 (setf (slot-value address 'longitude) "")
			 (setf (slot-value address 'latitude) "")
			 (setf (slot-value address 'locality) "Not Found")
			 (setf (slot-value address 'city) "Not Found")
			 (setf (slot-value address 'state) "Not Found")
			 ;; Data is partially missing (e.g., locality is nil, but city/state exist)
                         (format t "~&[ADAPTER F] Pincode ~A data incomplete. Mapping to :F." pincode)
                         (values nil :F)))) ; Treat incomplete data as a Definitive Failure (F)
               ;; Catch JSON parsing errors (Malformed response)
               (error (e)
                 (format t "~&[ADAPTER C] JSON Parsing Error: ~A. Mapping to CONTRADICTION (:C)." e)
                 (values nil :C))))
             
            
            ;; 2. DEFINITIVE FAILURE: HTTP 4xx (Client/Not Found Errors)
            ((<= 400 status 499)
             (format t "~&[ADAPTER F] HTTP ~A Pincode lookup error. Mapping to :F." status)
             (values nil :F))
            
            ;; 3. UNKNOWN: HTTP 5xx (Server Errors, potentially transient)
            ((<= 500 status 599)
             (format t "~&[ADAPTER U] HTTP ~A Pincode service error. Mapping to :U." status)
             (values nil :U))
            
            ;; 4. CONTRADICTION: Other unexpected codes (3xx redirects, etc.)
            (t
             (format t "~&[ADAPTER C] Unexpected HTTP status ~A. Mapping to :C." status)
             (values nil :C))))

      ;; --- EXCEPTION HANDLING (MAPPING CHAOS) ---
      
      ;; Maps network/timeout Lisp condition to :U
      (nst-api-timeout-error ()
        (format t "~&[ADAPTER U] Network Timeout. Mapping to UNKNOWN (:U).")
        (values nil :U))
        
      ;; Catch-all for any other Lisp error (Network issues not caught above, etc.)
      (error (e)
        (format t "~&[ADAPTER C] Unhandled Lisp Error in Adapter: ~A. Mapping to CONTRADICTION (:C)." e)
        (values nil :C)))))

(defun getpincodedetails (pincode)
  "本地缓存版：从启动期载入的 *NST-ALL-INDIA-PINCODES* HT 拿 pcodedata，
   构造并填充一个 address 对象返回。
   找不到时返回的 address 三个 locality/city/state slot 都是 \"Not Found\"。
   不发起任何 HTTP，相比 get-pincode-details-adapter 显著快。"
  (let* ((pcodedata (gethash pincode *NST-ALL-INDIA-PINCODES*))
	 (address (make-instance 'Address))
	 (locality (if pcodedata (slot-value pcodedata 'office-name)))
	 (city (if pcodedata (slot-value pcodedata 'district)))
	 (division (if pcodedata (slot-value pcodedata 'division-name)))
	 (state (if pcodedata (slot-value pcodedata 'state-name))))
    ;; Send the Area, City and State values back.
    (if (and 
	     (not (null locality))
	     (not (null city))
	     (not (null state)))
	(progn
	  (setf (slot-value address 'pincode) pincode)
	  ;; Remove the S.O from the locality string.
	  (setf (slot-value address 'house-no) "")
	  (setf (slot-value address 'street) "")
	  (setf (slot-value address 'country) "")
	  (setf (slot-value address 'longitude) "")
	  (setf (slot-value address 'latitude) "")
	  (setf (slot-value address 'locality) (string-trim "S.O" locality))
	  (setf (slot-value address 'city) (format nil "~A, ~A" division city))
	  (setf (slot-value address 'state) state))
	
	;;else
	(progn
	  (setf (slot-value address 'pincode) pincode)
	  (setf (slot-value address 'house-no) "")
	  (setf (slot-value address 'street) "")
	  (setf (slot-value address 'country) "")
	  (setf (slot-value address 'longitude) "")
	  (setf (slot-value address 'latitude) "")
	  (setf (slot-value address 'locality) "Not Found")
	  (setf (slot-value address 'city) "Not Found")
	  (setf (slot-value address 'state) "Not Found")))
    ;; return the address object
    address))
	 

(defun getpincodedetails-old (pincode)
  "保留的旧实现：与 get-pincode-details-adapter 类似但不做 TCUF 状态分类，
   异常会直接外抛。仅作历史参考；当前正常路径走 getpincodedetails / get-pincode-details-adapter。"
  (let* ((address (make-instance 'Address))
	 (param-name (list "api-key" "format" "offset" "limit" "filters[pincode]"))
	 (param-values (list *HHUBAPI.GOV.IN.KEY*  "json" "0" "1" (format nil "~A" pincode)))
	 (param-alist (pairlis param-name param-values ))
	 (json-response (json:decode-json-from-string  (map 'string 'code-char (drakma:http-request *HHUBGETPINCODEURLEXTERNAL*
												    :method :GET
												    :parameters param-alist  ))))
	 (locality (cdr (assoc :OFFICENAME (nth 1 (nth 24 json-response)) :test 'equal)))
	 (city (cdr (assoc :DISTRICTNAME (nth 1 (nth 24 json-response)) :test 'equal)))
	 (division (cdr (assoc :DIVISIONNAME (nth 1 (nth 24 json-response)) :test 'equal)))
	 (state (cdr (assoc :STATENAME (nth 1 (nth 24 json-response)) :test 'equal))))
    ;; Send the Area, City and State values back.
    (if (and 
	     (not (null locality))
	     (not (null city))
	     (not (null state)))
	(progn
	  (setf (slot-value address 'pincode) pincode)
	  ;; Remove the S.O from the locality string.
	  (setf (slot-value address 'house-no) "")
	  (setf (slot-value address 'street) "")
	  (setf (slot-value address 'country) "")
	  (setf (slot-value address 'longitude) "")
	  (setf (slot-value address 'latitude) "")
	  (setf (slot-value address 'locality) (string-trim "S.O" locality))
	  (setf (slot-value address 'city) (format nil "~A, ~A" division city))
	  (setf (slot-value address 'state) state))
	
	;;else
	(progn
	  (setf (slot-value address 'pincode) pincode)
	  (setf (slot-value address 'house-no) "")
	  (setf (slot-value address 'street) "")
	  (setf (slot-value address 'country) "")
	  (setf (slot-value address 'longitude) "")
	  (setf (slot-value address 'latitude) "")
	  (setf (slot-value address 'locality) "Not Found")
	  (setf (slot-value address 'city) "Not Found")
	  (setf (slot-value address 'state) "Not Found")))
    ;; return the address object
    address))
	  


;;使用名字选中对应的客户
(defun select-customer-by-name (name-like-clause company)
  "按 name LIKE 在 company 租户内查 STANDARD 客户首条。
   过滤 deleted-state='N' / active-flag='Y' / cust-type='STANDARD'。"
  (let ((tenant-id (slot-value company 'row-id)))
    (car (clsql:select 'dod-cust-profile :where [and
		  [= [:deleted-state] "N"]
		  [= [:tenant-id] tenant-id]
		  [= [:cust-type] "STANDARD"]
		  [= [:active-flag] "Y"]
		  [like  [:name] name-like-clause]]
					 :caching *dod-database-caching* :flatp t))))

;; 使用名字选定对应的客户列表
(defun select-customer-list-by-name (name-like-clause company)
  "按 name LIKE 在租户内查 STANDARD 客户列表。"
  (let ((tenant-id (slot-value company 'row-id)))
    (clsql:select 'dod-cust-profile :where [and
		  [= [:deleted-state] "N"]
		  [= [:cust-type] "STANDARD"]
		  [= [:tenant-id] tenant-id]
		  [= [:active-flag] "Y"]
		  [like  [:name] name-like-clause]]
				    :caching *dod-database-caching* :flatp t)))

(defun select-customer-list-by-phone (phone-like-clause company)
  "按 phone LIKE 在租户内查 STANDARD 客户列表。"
  (let ((tenant-id (slot-value company 'row-id)))
    (clsql:select 'dod-cust-profile :where [and
		  [= [:deleted-state] "N"]
		  [= [:cust-type] "STANDARD"]
		  [= [:tenant-id] tenant-id]
		  [= [:active-flag] "Y"]
		  [like  [:phone] phone-like-clause]]
					 :caching *dod-database-caching* :flatp t)))

(defun select-customer-by-phone (phone company)
  "按 phone LIKE 在租户内查 STANDARD 客户首条。
   注：where 用了 like 而非 =，phone 含通配符时会有匹配多条情况；调用方传完整号码时仍能匹配。
   字段名 :cust_type（下划线）应是为绕过 CLSQL 名称转换，与 dod-cust-profile 上 cust-type 对应。"
  (let ((tenant-id (slot-value company 'row-id)))
    (car (clsql:select 'dod-cust-profile :where [and
		       [= [:deleted-state] "N"]
		       [= [:tenant-id] tenant-id]
		       [= [:cust_type] "STANDARD"]
		       [= [:active-flag] "Y"]
		       [like  [:phone] phone]]
					 :caching *dod-database-caching* :flatp t))))



(defun select-customers-for-company (company)
  "列出租户下全部 STANDARD 客户（活跃、未软删）。"
  (let ((tenant-id (slot-value company 'row-id)))
    (clsql:select 'dod-cust-profile :where [and
		       [= [:deleted-state] "N"]
		       [= [:tenant-id] tenant-id]
		       [= [:cust-type] "STANDARD"]
		       [= [:active-flag] "Y"]]
		       :caching *dod-database-caching* :flatp t)))


(defun select-customers-for-vendor (vendor company)
  "通过 vendor 的钱包反推关联客户：从 dod-cust-wallet 找该 vendor 的所有钱包，
   再筛 STANDARD 客户。返回客户列表（去重不显式做，钱包->客户应是 1:1）。"
  (let* ((wallets (get-cust-wallets-for-vendor vendor company))
       (mycustomers (remove nil (mapcar (lambda (wallet)
                                          (let* ((customer (slot-value wallet 'customer))
                                                 (cust-type (slot-value customer 'cust-type)))
                                            (when (equal cust-type "STANDARD") customer))) wallets))))
    mycustomers))

(defun select-customer-for-vendor-by-phone (phone vendor company)
  "在 vendor 的钱包客户里按 phone 精确匹配 STANDARD 客户首条。"
  (let* ((wallets (get-cust-wallets-for-vendor vendor company))
	 (mycustomer (car (remove nil (mapcar (lambda (wallet)
                                            (let* ((customer (slot-value wallet 'customer))
                                                   (cust-type (slot-value customer 'cust-type))
						   (cust-phone (slot-value customer 'phone)))
                                              (when (and (equal cust-type "STANDARD")
							 (equal cust-phone phone)) customer))) wallets)))))
    mycustomer))


(defun select-guest-customer (company)
  "拿到租户下唯一的 GUEST 客户实例（phone=*HHUBGUESTCUSTOMERPHONE* 占位号）。
   游客购物会复用这个全局\"匿名客户\"。"
(let ((tenant-id (slot-value company 'row-id)))
  (car (clsql:select 'dod-cust-profile :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:active-flag] "Y"]
		[= [:phone] *HHUBGUESTCUSTOMERPHONE*]
		[= [:cust-type] "GUEST"]]
		:caching *dod-database-caching* :flatp t))))




(defun update-customer (customer-instance); This function has side effect of modifying the database record.
  "把 customer-instance 全字段写回 DB（UPDATE dod-cust-profile）。"
  (clsql:update-records-from-instance customer-instance))

(defun duplicate-customerp(phone company)
  "在 company 内 phone 是否已被注册（用于注册前查重）。返回 T / NIL。"
  (if (select-customer-by-phone phone company) T NIL))


(defun select-customer-by-id (id company)
  "按主键 id + tenant 在租户内查活跃客户（不限 cust-type）。"
(let ((tenant-id (slot-value company 'row-id)))
  (car (clsql:select 'dod-cust-profile :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:active-flag] "Y"]
		[=  [:row-id] id]]
		:caching *dod-database-caching* :flatp t))))



(defun select-customer-by-email (email)
  "按 email 跨租户查活跃客户首条。常用于密码重置链接验证。"
  (car (clsql:select 'dod-cust-profile :where [and
		[= [:deleted-state] "N"]
		[= [:active-flag] "Y"]
		[=  [:email] email]]
		:caching *dod-database-caching* :flatp t)))




(defun reset-customer-password (customer)
  "重置客户密码：生成 8 位随机密码 + 新 salt，加密后写回；同时把 active-flag='Y'
   （重置流程的前置步骤会先停用账户）。返回明文新密码（供调用方以邮件/短信发出）。
   副作用：UPDATE dod-cust-profile。"
  (let* ((confirmpassword (hhub-random-password 8))
	 (salt (createciphersalt))
	(encryptedpass (check&encrypt confirmpassword confirmpassword salt)))
	  
    (setf (slot-value customer 'password) encryptedpass)
    (setf (slot-value customer 'salt) salt) 
    ; Whenever we reset the customer password, we activate the customer, as he is in-activated when this process started. 
    (setf (slot-value customer 'active-flag) "Y") 
    (update-customer  customer )
    confirmpassword)) ; return the newly generated password. 

       

(defun select-deleted-customer-by-id (id company)
  "查租户内**已软删**（deleted-state='Y'）的客户。用于恢复操作前确认存在。"
(let ((tenant-id (slot-value company 'row-id)))
  (car (clsql:select 'dod-cust-profile :where [and
		[= [:deleted-state] "Y"]
		[= [:tenant-id] tenant-id]
		[=  [:row-id] id]]
		:caching *dod-database-caching* :flatp t))))


(defun delete-customer (object)
  "对外软删客户的便捷入口：从 object 上取 row-id 与 tenant-id，转交 delete-cust-profile。"
  (let ((cust-id (slot-value object 'row-id))
	 (tenant-id (slot-value object 'tenant-id)))
	 (delete-cust-profile cust-id tenant-id)))

(defun restore-deleted-customer (object)
  "恢复软删客户的便捷入口：从 object 取 ID，转交 restore-deleted-cust-profile。"
  (let ((cust-id (slot-value object 'row-id))
	(tenant-id (slot-value object 'tenant-id)))
    (restore-deleted-cust-profile (list cust-id) tenant-id)))



(defun delete-cust-profile( id tenant-id )
  "底层软删：把 (id, tenant-id) 命中的客户 deleted-state 置 'Y'。
   副作用：UPDATE dod-cust-profile。"
  (let ((dodcust (car (clsql:select 'dod-cust-profile :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value dodcust 'deleted-state) "Y")
    (clsql:update-record-from-slot dodcust 'deleted-state)))

(defun delete-cust-profiles ( list company)
  "批量软删：list 为客户 id 列表，company 提供 tenant 隔离。"
(let ((tenant-id (slot-value company 'row-id)))  
  (mapcar (lambda (id)  (let ((doduser (car (clsql:select 'dod-cust-profile :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
			  (setf (slot-value doduser 'deleted-state) "Y")
			  (clsql:update-record-from-slot doduser  'deleted-state))) list )))


(defun restore-deleted-cust-profile ( list tenant-id )
  "批量恢复（deleted-state 改回 'N'）。注意：此函数收的是 tenant-id 数值（与
   delete-cust-profiles 的入参形式不同），调用方需提前从 company 取出。"
(mapcar (lambda (id)  (let ((doduser (car (clsql:select 'dod-cust-profile :where [and [= [:row-id] id] [= [:tenant-id] tenant-id]] :flatp t :caching *dod-database-caching*))))
    (setf (slot-value doduser 'deleted-state) "N")
    (clsql:update-record-from-slot doduser 'deleted-state))) list ))




(defun create-customer(name address phone  email birthdate password salt city state zipcode company  )
  "创建 STANDARD 客户并写库（DOD_CUST_PROFILE）。
   默认 cust-type='STANDARD'、active-flag='Y'、deleted-state='N'。
   tenant-id 来自 company.row-id。
   备注：未填 firstname/lastname/fullname 等字段；调用方若需要可后续 update。"
  (let ((tenant-id (slot-value company 'row-id)))
    (clsql:update-records-from-instance (make-instance 'dod-cust-profile
						       :name name
						       :address address
						       :email email 
						       :password password 
						       :salt salt
						       :birthdate birthdate 
						       :phone phone
						       :city city 
						       :state state 
						       :zipcode zipcode
						       :tenant-id tenant-id
						       :cust-type "STANDARD"
						       :active-flag "Y"
						       :deleted-state "N"))))
 

(defun create-guest-customer(company)
  "为指定 company 创建唯一的 GUEST 客户（如已存在则跳过）。
   名字格式 \"Guest Customer - <公司名>\"，phone 固定 \"9999999999\"，cust-type='GUEST'。
   被 com-hhub-transaction-display-store / dod-cust-login-as-guest 使用。"
  (let ((tenant-id (slot-value company 'row-id))
	(customer-name (format nil "Guest Customer - ~A" (slot-value company 'name)))
	(existingguestcust (select-guest-customer company)))
    (unless existingguestcust (clsql:update-records-from-instance (make-instance 'dod-cust-profile
						    :name customer-name
						    :address (slot-value company 'address)
						    :email nil 
						    :password "demo"
						    :salt nil
						    :birthdate nil
						    :phone "9999999999"
						    :city (slot-value company 'city)
						    :state (slot-value company 'state)
						    :zipcode (slot-value company 'zipcode)
						    :tenant-id tenant-id
						    :cust-type "GUEST"
						    :active-flag "Y"
						    :deleted-state "N")))))



;;;;; Customer wallet related functions ;;;;;


(defun create-wallet(customer vendor company  )
  "为 (customer, vendor, company) 三元组创建一条 dod-cust-wallet 记录。"
  (let ((tenant-id (slot-value company 'row-id))
	(cust-id (slot-value customer 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
    (persist-wallet cust-id vendor-id tenant-id)))

(defun persist-wallet (cust-id vendor-id tenant-id)
  "底层钱包持久化：INSERT DOD_CUST_WALLET，初始余额未指定（默认 0 由 DB 控制）。"
 (clsql:update-records-from-instance (make-instance 'dod-cust-wallet
						    :cust-id cust-id
						    :vendor-id vendor-id
						    :tenant-id tenant-id
				    		    :deleted-state "N")))

(defun check-wallet-balance (amount customer-wallet)
  "判断 wallet.balance > amount（够不够支付 amount）。返回 T/NIL。"
  (let ((cur-balance (slot-value customer-wallet  'balance)))
    (if (> cur-balance amount) T nil)))

(defun check-low-wallet-balance (customer-wallet)
  "判断钱包余额是否低于 50.00（应是平台硬编码的低额阈值，推测）。"
(if (< (slot-value customer-wallet 'balance) 50.00) T nil))

(defun check-zero-wallet-balance (customer-wallet)
  "判断钱包余额是否为负（< 0.00）。注意：函数名 'zero' 但实际比较 < 0；'< 0' 表示透支。"
(if (< (slot-value customer-wallet 'balance) 0.00) T nil))


(defun deduct-wallet-balance (amount customer-wallet)
  "从钱包扣减 amount（即 balance := balance - amount），写库。
   订单履约 set-order-fulfilled 中对 PRE 支付订单调用本函数。"
(let ((cur-balance (slot-value customer-wallet 'balance)))
(progn  (setf (slot-value customer-wallet 'balance) (- cur-balance amount))
  (clsql:update-record-from-slot customer-wallet 'balance))))

(defun set-wallet-balance (amount customer-wallet)
  "把钱包余额直接设置为 amount，写库。"
 (progn  (setf (slot-value customer-wallet 'balance) amount)
	 (clsql:update-record-from-slot customer-wallet 'balance)))

(defun get-cust-wallets-for-vendor (vendor company)
  "列出指定 vendor 在 company 内的所有钱包（每个钱包对应一位客户）。"
  (let ((tenant-id (slot-value company 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
  (clsql:select 'dod-cust-wallet :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[=  [:vendor-id] vendor-id]]
		:caching *dod-database-caching* :flatp t)))


(defun get-cust-wallet-by-vendor (customer vendor company)
  "获取 (customer, vendor) 对应的钱包（一个客户在一个卖家处只有一个钱包）。"
  (let ((tenant-id (slot-value company 'row-id))
	(cust-id (slot-value customer 'row-id))
	(vendor-id (slot-value vendor 'row-id)))
  (car (clsql:select 'dod-cust-wallet :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:cust-id] cust-id]
		[=  [:vendor-id] vendor-id]]
		:caching *dod-database-caching* :flatp t))))

(defun get-cust-wallets (customer company)
  "列出某客户在 company 内的所有钱包（每个 vendor 一个）。"
  (let ((tenant-id (slot-value company 'row-id))
	(cust-id (slot-value customer 'row-id)))
   (clsql:select 'dod-cust-wallet :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:cust-id] cust-id]]
		:caching *dod-database-caching* :flatp t)))





(defun get-cust-wallet-by-id (id company)
  "按主键 row-id 在租户内取钱包。返回 dod-cust-wallet / nil。"
  (let ((tenant-id (slot-value company 'row-id)))
	
   (car (clsql:select 'dod-cust-wallet :where [and
		[= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:row-id] id]]
	
		:caching *dod-database-caching* :flatp t))))



