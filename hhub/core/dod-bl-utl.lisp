;;; dod-bl-utl.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 业务通用工具
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/dod-bl-utl.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：跨模块的通用工具函数集合：
;;;;       - 货币与数字格式：paise-to-rupees-string、convert-number-to-words-INR
;;;;       - URI 前缀匹配：uri-prefix-p / uri-prefix-boundary-p（被 PEP 用）
;;;;       - JSON / PDF / 文件 I/O 工具：return-json、generatepdf、hhub-read-file
;;;;       - 实体名/SKU/分支名生成器
;;;;       - YAML 配置读写
;;;;       - 通用业务函数注册/反射调用：hhub-register/-execute-network-function
;;;;       - 哈希表/列表/统计工具
;;;;       - 日期/时间格式化（DD/MM/YYYY、YYYY-MM-DD、HH:MM:SS、MySQL now）
;;;;       - 加解密与摘要：generatehashkey、encrypt/decrypt、create-digest-sha1/-md5
;;;;       - 模板代码生成：create-domain-entity-from-template
;;;;
;;;; 主要导出（约 50 个函数；以下挑核心列出）：
;;;;   uri-prefix-p / uri-prefix-boundary-p   — 被 with-hhub-transaction PEP 校验 URI
;;;;   return-json                            — 直接终止请求并返回 JSON 串
;;;;   convert-number-to-words-INR            — 印度计数（lakh/crore）转英文
;;;;   create-domain-entity-from-template     — 用 hhub-{ui,bl,dal}-egn.lisp 模板生成新实体
;;;;   hhub-register-network-function / hhub-execute-network-function
;;;;   mysql-now / mysql-now+days             — 给 CLSQL 用的字符串时间戳
;;;;   generatehashkey / hashcalculate / responsehashcheck  — 支付网关签名相关
;;;;   encrypt / decrypt / check-password     — Blowfish ECB 密码加解密
;;;;
;;;; 关联：
;;;;   上游使用方：几乎所有模块；尤其支付/发票/订单
;;;;   下游依赖：clsql / hunchentoot / ironclad / cl-ppcre / yaml / split-sequence /
;;;;             secure-random / drakma / json
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun paise-to-rupees-string (paise)
  "把整数 paise（卢比的 1/100）格式化为带 2 位小数的卢比字符串。"
  (format nil "~,2F" (/ paise 100.0)))

(defun round-to-2-decimal (n)
  "Standard rounding to 2 decimal places."
  (/ (round (* n 100)) 100.0))

;; URI 前缀匹配的"边界字符"：/ ? # ;。被 with-hhub-transaction 用于
;; 防止 /hhub/admin 被误匹配到 /hhub/admincreate 等长前缀路径。
(defparameter *uri-boundary-chars* '(#\/ #\? #\# #\;))


(defun uri-prefix-boundary-p (prefix uri)
  "判断 prefix 是否是 uri 的"前缀+边界"匹配：要么完全相等，要么 prefix 末尾紧跟边界字符。
   被 PEP 宏 with-hhub-transaction 用作 URL 命中判定。"
  (and (uri-prefix-p prefix uri)
       (let ((plen (length prefix)))
         (or (= plen (length uri))
             (not (null
                   (find (aref uri plen)
                         *uri-boundary-chars*)))))))

(defun uri-prefix-p (prefix uri)
  "纯前缀字符串匹配（不考虑边界）。"
  (let ((plen (length prefix)))
    (and (<= plen (length uri))
         (string= prefix uri :end2 plen))))

(defun return-json (data &optional (status 200))
  "立即终止当前 Hunchentoot 请求，返回 JSON 响应。
   data 可以是任意 cl-json 可序列化结构。status 默认 200。"
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (setf (hunchentoot:return-code*) status)
  (hunchentoot:abort-request-handler
   (json:encode-json-to-string data)))


(defun generate-entity-tla (entity-name)
  "Generate a unique 3-letter acronym (TLA) from an entity name like 'order header'.
   中文：从实体英文名生成 3 字母缩写（用于文件名）。
         规则：3+ 词取每词前 3 字符；2 词取 3+4；1 词取前 3。"
  (let* ((tokens (remove-if #'(lambda (s) (string= s "")) 
                            (split-sequence:split-sequence #\Space (string-downcase entity-name))))
         (abbr ""))
    (cond
     ((>= (length tokens) 3)
      (setf abbr (concatenate 'string
                              (subseq (nth 0 tokens) 0 3)
                              (subseq (nth 1 tokens) 0 3)
                              (subseq (nth 2 tokens) 0 3))))
     ((= (length tokens) 2)
      (setf abbr (concatenate 'string
                              (subseq (nth 0 tokens) 0 3)
                              (subseq (nth 1 tokens) 0 4))))
     ((= (length tokens) 1)
      (setf abbr (subseq (nth 0 tokens) 0 (min 3 (length (nth 0 tokens))))))
     (t (setf abbr "obj")))
    abbr))

(defun generate-lisp-filename (entity-name layer-name)
  "Generates the Lisp file name like nst-dal-odt.lisp from 'order details' and 'dal'.
   中文：拼出 nst-<layer>-<TLA>.lisp 风格的源文件名。"
  (let ((tla (generate-entity-tla entity-name)))
    (format nil "nst-~A-~A.lisp" (string-downcase layer-name) (string-downcase tla))))

(defun generate-descriptive-filename (entity-name layer)
  "拼出 nst-<layer>-<entity-name 用-连接>.lisp 风格的描述性文件名。"
  (let ((normalized-name (string-downcase (cl-ppcre:regex-replace-all "[ _]" entity-name "-"))))
    (format nil "nst-~A-~A.lisp" layer normalized-name)))


;; Example 1: Creating a branch for a UI feature with an identifier
;; This is for the UI layer, adding a new OTP-based login using HTMX
;; (generate-branch-name
;; :scope "ui"                 ;; Area of the codebase — e.g., "core", "ui", "api", etc.
;; :type "feat"                ;; Type of work — e.g., "feat", "fix", "chore", etc.
;; :id "otp2"                  ;; Optional ticket/issue ID or short code (e.g., JIRA/issue number)
;; :desc "htmx integration")   ;; Description of the work
;; => "ui/feat/otp2-htmx-integration"
;; (generate-branch-name :scope "ui" :type "feat" :id "otp2" :desc "htmx integration")
;; (generate-branch-name :scope "core" :type "fix" :desc "login crash")

(defun generate-branch-name (&key scope type id desc (max-length 50))
  "Generate a validated Git branch name: scope/type/id-desc.
   中文：按白名单校验 scope（cus/ven/cad/super/core/...）和 type（feat/fix/...），
         拼成 git 分支名。超长直接 error。"
  (let* ((allowed-scopes '("cus" "ven" "cad" "super" "core" "ui" "api" "lisp" "infra" "test" "doc"))
         (allowed-types  '("feat" "fix" "chore" "refactor" "perf" "test" "docs" "hotfix"))
         (scope (string-downcase (string scope)))
         (type (string-downcase (string type)))
         (id (when id (string-downcase (string id))))
         (desc (string-downcase (string desc)))
         (safe-desc (substitute #\- #\Space desc)))

    ;; Validate scope
    (unless (member scope allowed-scopes :test #'string=)
      (error "Invalid scope: ~A. Allowed: ~{~A~^, ~}" scope allowed-scopes))

    ;; Validate type
    (unless (member type allowed-types :test #'string=)
      (error "Invalid type: ~A. Allowed: ~{~A~^, ~}" type allowed-types))

    ;; Generate base name
    (let ((branch-name
            (if id
                (format nil "~A/~A/~A-~A" scope type id safe-desc)
                (format nil "~A/~A/~A" scope type safe-desc))))
      ;; Enforce max length
      (if (> (length branch-name) max-length)
          (error "Branch name too long (~A chars): ~A" (length branch-name) branch-name)
          branch-name))))

(defun generate-sku-anusthup (name desc qty unit)
  (let* ((prefix (lambda (string length)                     ; 1-7
                   (subseq (string-upcase string) 0 length))) ; 8-13
         (code-n (funcall prefix name 4))                    ; 14-18
         (code-d (funcall prefix desc 4))                    ; 19-23
         (random (format nil "~4,'0D" (random 10000))))      ; 24-29
    (format nil "~A-~A-~A~A-~A"                              ; 30-31
            code-n code-d qty unit random)))                 ; 32

(defun generate-sku (product-name description qty-per-unit unit-of-measure)
  "Generate an SKU from product information by taking 2 chars from each word.

  中文：根据商品名 + 描述 + 规格 + 计量单位生成 SKU 字符串：
        <名前缀>-<描述前缀>-<qty><uom>-<4位随机数>。

  Arguments:
  - PRODUCT-NAME: String (e.g., \"Organic Apples\")
  - DESCRIPTION: String or NIL (e.g., \"Red Delicious\")
  - QTY-PER-UNIT: Number (e.g., 1, 100, 2.5)
  - UNIT-OF-MEASURE: String (e.g., \"KG\", \"G\", \"L\")

  Returns:
  - A generated SKU string in format NN-DD-QTY-UOM-RANDOM
    Where NN is from product name words, DD from description words
  "
  (flet ((process-words (string max-words)
           (when string
             (let ((words (remove-if #'uiop:emptyp 
                                   (split-sequence:split-sequence #\Space string))))
               (subseq (apply #'concatenate 'string
                             (mapcar (lambda (word) 
                                       (subseq (string-upcase word) 0 (min 2 (length word))))
                                     words))
                       0 (* 2 (min max-words (length words))))))))
    
    (let* ((name-code (process-words product-name 3))  ; Take max 3 words from name
           (desc-code (process-words description 2))   ; Take max 2 words from description
           (random-num (+ 1000 (random 9000))))
      
      (format nil "~A~@[-~A~]-~A~A-~D"
              name-code
              desc-code
              qty-per-unit
              (string-upcase unit-of-measure)
              random-num))))

(defun read-yaml-file (filepath)
  "Read a YAML file and return its parsed content.
   中文：读取 YAML 文件并 yaml:parse 成嵌套 hash-table。"
  (let ((contents (hhub-read-file filepath)))
    (yaml:parse contents)))

(defun write-yaml-file (filepath data)
  "Write a Lisp data structure to a YAML file.
   中文：把 Lisp 数据 emit 成 YAML。注意当前实现写到 *standard-output* 而非 stream（推测为遗留 bug）。"
  (with-open-file (stream filepath :direction :output :if-exists :supersede)
    (yaml:emit data *standard-output*)))

(defun update-invoice-settings (yaml-file output-file)
  "Read, modify, and save YAML settings.
   中文：示例函数 —— 把发票通用设置中的默认币种改为 INR、日期格式改为 DD/MM/YYYY。"
  (let ((data (read-yaml-file yaml-file)))
    ;; Update specific settings
    (setf (gethash "default_currency" (gethash "invoice_general_settings" (gethash "invoice_settings" data))) "INR")
    (setf (gethash "date_format" (gethash "invoice_general_settings" (gethash "invoice_settings" data))) "DD/MM/YYYY")
    ;; Save the updated data
    (write-yaml-file output-file data)))

;; Use the function
;;(update-invoice-settings "config.yaml" "updated_config.yaml")


(defun generatepdf (inputhtmlfile outpdffilename)
  "调用本机 wkhtmltopdf 把 *HHUBRESOURCESDIR*/temp/inputhtmlfile 渲染成 PDF。
   返回生成的 PDF 文件名（仅文件名，不含路径）。文件名后缀加 universal-time 防重名。
   副作用：通过 sb-ext:run-program 起 shell 进程；--disable-javascript 关 JS。"
  (let* ((filename (format nil "~A~A.pdf" outpdffilename (get-universal-time)))
	 (filepath (format nil "~A/temp/~A" *HHUBRESOURCESDIR* filename))
	 (htmlpath (format nil "~A/temp/~A" *HHUBRESOURCESDIR* inputhtmlfile))
	 (pdfcmd (format nil "wkhtmltopdf --disable-javascript ~A ~A" htmlpath filepath)))
    (sb-ext:run-program "/bin/sh" (list "-c" pdfcmd) :input nil :output *standard-output*)
    filename))


(defun downloadhtmlfile (url)
  "用 wget 把 url 下载到 *HHUBRESOURCESDIR*/temp/，文件名为 downloadXXXXXXXX.html。"
  (let* ((filename (format nil "download~A.html" (get-universal-time)))
	 (filepath (format nil "~A/temp/~A" *HHUBRESOURCESDIR* filename))
	 (command (format nil "wget -O ~A ~A" filepath url)))
    (sb-ext:run-program "/bin/sh" (list "-c" command) :input nil :output *standard-output*)
    filename))

(defun inr-to-words-anusthup (amount crore lakh)
  (multiple-value-bind (rupees paise) (floor amount)  ; 1-7
    (let ((say (lambda (val unit)                     ; 8-12
                 (if (> val 0)                        ; 13-14
                     (format nil "~R ~A " val unit)   ; 15-18
                     ""))))                           ; 19
      (format nil "Rupees ~A~A~A~:[ and ~R paise~;~]" ; 20-26
              (funcall say (floor rupees crore) "crore") ; 27-29
              (funcall say (rem (floor rupees lakh) 100) "lakh") ; 30-31
              (funcall say (rem rupees lakh) "")      ; 32
              (zerop paise) (round (* paise 100))))))

(defun make-inr-mantra (amount)
  (let ((crore 10000000) (lakh 100000))
    (lambda ()
      (inr-to-words-anusthup amount crore lakh))))


(defun convert-number-to-words-INR (number)
  "把数字（含小数）转成印度英文金额读法（含 lakh / crore 计数体系）。
   返回示例：'One hundred twenty three rupees and forty five paise'。
   备注：上限到 100 crore（10^9）；超界返回部分结果。被发票模板用于'金额大写'字段。"
  (let* ((ones (make-array '(10) :initial-contents (list ""  "one"  "two"  "three"  "four"  "five"  "six"  "seven"  "eight"  "nine")))
	 (tens (make-array '(10) :initial-contents (list  ""  "ten"  "twenty"  "thirty"  "forty"  "fifty"  "sixty"  "seventy"  "eighty"  "ninety")))
	 (teens (make-array '(10) :initial-contents (list ""  "eleven"  "twelve"  "thirteen"  "fourteen"  "fifteen"  "sixteen"  "seventeen"  "eighteen"  "nineteen"))))
    (labels ((convert-hundreds (number)
	       (cond
		 ((equal number 0) "")
		 ((< number 10) (aref ones number))
		 ((and (> number 10) (< number 20)) (aref teens (- number 10)))
		 ((and (>= number 10) (< number 100))
		  (format nil "~A ~A" (aref tens (floor number 10)) (if (not (equal (mod number 10) 0)) (aref ones (mod number 10)) "")))
		 ((>= number 100)
		  (multiple-value-bind (q r) (floor number 100)
		      (declare (ignore r))
		    (let* ((firstpart (aref ones q))
			   (secondpart (convert-hundreds (mod number 100))))
		      (format nil "~A hundred ~A" firstpart secondpart))))))
	     (convert-thousands (number)
	       (let ((thousand 1000)
		     (lakh 100000))
	       (cond
		 ((< number thousand) (convert-hundreds number))
		 ((< number lakh)
		  (format nil "~A thousand ~A" (convert-hundreds (floor number thousand)) (convert-hundreds (mod number thousand)))))))
	     (convert-lakhs (number)
	       (let ((lakh 100000)
		     (crore 10000000))
	       (cond
		   ((< number lakh) (convert-thousands number))
		   ((< number crore)
		    (format nil "~A lakh ~A" (convert-hundreds (floor number lakh)) (convert-thousands (mod number lakh)))))))
	     (convert-crores (number)
	       (let ((crore 10000000)
		     (hundredcrore 1000000000))
	       (cond
		   ((< number crore) (convert-lakhs number))
		   ((< number hundredcrore)
		    (format nil "~A crores ~A" (convert-hundreds (floor number crore)) (convert-lakhs (mod number crore))))))))

      (let* ((rupees (floor number))
	     (paise (round (* (- number rupees) 100)))
	     (rupees-words (if (equal rupees 0) "zero rupees" (format nil "~A rupees" (convert-crores rupees))))
	     (paise-words (if (> paise 0) (format nil "~A paise" (convert-hundreds paise)))))
	(format nil "~A~A" (string-capitalize rupees-words) (if paise-words (concatenate 'string " and " paise-words) ""))))))

(defun convert-number-to-words-USD (number)
  "USD 金额英文大写 —— 当前未实现，保留占位。"
  (declare (ignore number))
  "not implemented" )

(defun create-domain-entity-from-template (entityname fieldnames &key (output-dir "/home/ubuntu/ninestores/hhub/output"))
  "Generates domain code for UI, BL, and DAL by replacing placeholders in templates.
   中文：脚手架生成器 —— 读取 hhub-{ui,bl,dal}-egn.lisp 三个模板，
         把 %0% %1% ... 替换成 fieldnames 中的字段名，把 %entity-name% 替换成 entityname，
         分别输出到 output-dir/nst-{ui,bl,dal}-<entityname>.lisp。"
  (let* ((template-paths '((:ui . "/home/ubuntu/ninestores/hhub/core/hhub-ui-egn.lisp")
                           (:bl . "/home/ubuntu/ninestores/hhub/core/hhub-bl-egn.lisp")
                           (:dal . "/home/ubuntu/ninestores/hhub/core/hhub-dal-egn.lisp")))
         (output-files '((:ui . "nst-ui-")
                         (:bl . "nst-bl-")
                         (:dal . "nst-dal-"))))
    
    ;; Iterate over each layer and process its template
    (loop for (layer . template-path) in template-paths
          for (layer2 . prefix) in output-files
          do (let* ((filecontent (hhub-read-file template-path))
                    (outfile (merge-pathnames (format nil "~A~A.lisp" prefix entityname) output-dir)))

               ;; Replace placeholders %0%, %1%, ... with actual field names
               (loop for field in fieldnames
                     for i from 0
                     for placeholder = (format nil "%~d%" i)
                     do (setf filecontent (cl-ppcre:regex-replace-all placeholder filecontent field)))

               ;; Replace 'xxxx' with the entity name
               (setf filecontent (cl-ppcre:regex-replace-all "%entity-name%" filecontent entityname))

               ;; Write the processed content to the output file
               (with-open-file (stream outfile
                                       :if-does-not-exist :create
                                       :if-exists :supersede
                                       :direction :output
                                       :external-format :utf-8)
                 (format stream "~A" filecontent)
                 (terpri stream))))))


(defun hhub-register-network-function (name funcsymbol)
:documentation "This function registers a new business function and adds it to the *HHUBGLOBALBUSINESSFUNCTIONS-HT* Hash Table. It should conform to naming convention com.hhub.businessfunction*
中文：登记一个'业务网络函数'到全局哈希表。
      校验 name 必须以 'com.hhub.businessfunction' 开头，funcsymbol 以 'com-hhub-businessfunction-' 开头；
      不符合则静默跳过。"
  (multiple-value-bind (fname) (ppcre:scan "com.hhub.businessfunction.*" name)
    (when fname
      (multiple-value-bind (fsymbol) (ppcre:scan "com-hhub-businessfunction-*" funcsymbol)
	(when fsymbol
	  (setf (gethash name  *HHUBGLOBALBUSINESSFUNCTIONS-HT*) funcsymbol))))))

(defun hhub-init-network-functions ()
  "启动期登记 webpush 相关的业务函数（bl/tempstorage/db 三层）。
   备注：此函数当前调用的是 hhub-register-business-function（与上面的 -network- 不同），
         可能命名漂移；运行时若该函数存在则照常注册，否则需要补齐。"
  (hhub-register-business-function "com.hhub.nwfunc.bl.getpushnotifysubscriptionforvendor" "com-hhub-businessfunction-bl-getpushnotifysubscriptionforvendor")
;;  (hhub-register-business-function "com.hhub.businessfunction.tempstorage.getpushnotifysubscriptionforvendor" "com-hhub-businessfunction-tempstorage-getpushnotifysubscriptionforvendor")
  (hhub-register-business-function "com.hhub.businessfunction.db.getpushnotifysubscriptionforvendor" "com-hhub-businessfunction-db-getpushnotifysubscriptionforvendor")
  ;; Business functions for Creating Push Notify Subscription for Vendor 
  (hhub-register-business-function "com.hhub.businessfunction.bl.createpushnotifysubscriptionforvendor" "com-hhub-businessfunction-bl-createpushnotifysubscriptionforvendor")
  (hhub-register-business-function "com.hhub.businessfunction.tempstorage.createpushnotifysubscriptionforvendor" "com-hhub-businessfunction-tempstorage-createpushnotifysubscriptionforvendor")
  (hhub-register-business-function "com.hhub.businessfunction.db.createpushnotifysubscriptionforvendor" "com-hhub-businessfunction-db-createpushnotifysubscriptionforvendor"))

(defun hhub-execute-network-function (name input-params)
  :documentation "This is a general business function adapter for HHub. It takes parameters in a association list
   中文：通用业务函数适配器。
       1) 在 *HHUBGLOBALBUSINESSFUNCTIONS-HT* 取出 funcsymbol（字符串）；
       2) intern 到 :hhub 包；
       3) funcall 并捕获 hhub-business-function-error / 通用 error；
   返回：(returnvalues exception)。
   备注：hhub package 名与项目实际包 :nstores 不一致，可能是历史遗留；如未注册函数则直接 error。"
  (handler-case 
      (let ((funcsymbol (gethash name *HHUBGLOBALBUSINESSFUNCTIONS-HT*)))
	(if (null funcsymbol) (error 'hhub-business-function-error :errstring "Business function not registered"))
	(multiple-value-bind (returnvalues exception) (funcall (intern (string-upcase funcsymbol) :hhub) input-params)
	  ;;Return a list of return values and exception as nil. 
	  (list returnvalues exception)))
    (hhub-business-function-error (condition)
      (list nil (format nil "HHUB Business Function error triggered in Function - ~A. Error: ~A" (string-upcase name) (getExceptionStr condition))))
					; If we get any general error we will not throw it to the upper levels. Instead set the exception and log it. 
    (error (c)
      (let ((exceptionstr (format nil  "HHUB General Business Function Error: ~A  ~a~%" (string-upcase name) c)))
	(with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* 
				:direction :output
				:if-exists :supersede
				:if-does-not-exist :create)
	  (format stream "~A" exceptionstr))
	(list nil (format nil "HHUB General Business Function Error. See logs for more details."))))))


(defun max-item (list)
  "返回数字列表中的最大值。"
  (loop for item in list
        maximizing item))

(defun min-item (list)
  "返回数字列表中的最小值。"
  (loop for item in list
	minimizing item))


(defun average (list)
  "返回数字列表的算术平均值；空列表返回 nil。"
  (when (and list (> (length list) 0))
    (/ (reduce #'+ list) (length list))))

(defun get-max-of (objlist fieldname)
  "在对象列表中按指定 slot 名取最大值。"
  (reduce #'max (mapcar (lambda (object)
			(let ((fieldvalue (slot-value object fieldname)))
			  fieldvalue)) objlist)))


(defun get-total-of (objlist fieldname)
  "在对象列表中对指定 slot 求和；slot 为 nil 视作 0。"
  (reduce #'+ (mapcar (lambda (object)
			(let ((fieldvalue (slot-value object fieldname)))
			  (if fieldvalue fieldvalue 0))) objlist)))


(defun createwhatsapplink (phone)
  "拼出 WhatsApp 单击对话链接（无消息体）。"
  (format nil "~A~A" *HHUBWHATAPPLINKURLINDIA* phone))

(defun createwhatsapplinkwithmessage (phone message)
  "拼出 WhatsApp 链接 + 预填消息（自动 URL encode）。"
  (format nil "~A~A?text=~A" *HHUBWHATAPPLINKURLINDIA* phone (hunchentoot:url-encode message)))

(defun search-in-hashtable (search-string hashtable)
  :documentation "Search for a string in hashtable. Returns a list of all the values where the key contains the substring
  中文：把哈希表中所有 key 含 search-string 的 value 收集成列表返回。"
  (let ((retlist '()))
    (maphash (lambda (key value)
	       (if (search search-string key) (setf retlist (append retlist (list value))))) hashtable)
  retlist))

(defun hhub-function-memoize (function-symbol)
  "把单参函数 function-symbol 替换为 memo 版本（仅按第一参数键化）。
   备注：与 core/memoize.lisp 中更通用的 memoize 区别：本函数只支持单 key、不登记到全局表。"
  (let ((original-function (symbol-function function-symbol))
        (values            (make-hash-table)))
    (setf (symbol-function function-symbol)
          (lambda (arg &rest args)
            (or (gethash arg values)
                (setf (gethash arg values)
                      (apply original-function arg args)))))))
(defun check&encrypt (password confirmpass salt)
  "校验 password = confirmpass，通过则用 salt 加密；任一为空或不匹配返回 nil。"
  (when
	 (and (or  password  (length password))
	      (or  confirmpass (length confirmpass))
	      (equal password confirmpass))

       (encrypt password salt)))


(defun hhub-random-password (length)
  "返回长度为 length 的 base-36 随机字符串（用于临时密码/盐值）。"
  (with-output-to-string (stream)
    (let ((*print-base* 36))
      (loop repeat length do (princ (random 36) stream)))))


(defun hhub-read-file (filename)
 :documentation "Reads a file and returns a string
  中文：一次性读完整个文件并返回字符串（按 file-length 分配缓冲）。"
  (with-open-file (stream filename)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

(defun hhub-log-message (str)
  "把字符串 append 到业务函数日志文件 *HHUBBUSINESSFUNCTIONSLOGFILE*。"
  (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE*
			      :direction :output
			      :if-exists :append
			      :if-does-not-exist :create)
	(format stream "~A" str)))

(defun hhub-write-file-for-css-inlining (contents)
  "把 HTML 写到 emailtemplate.html，供外部 CSS-inline 工具处理后用于邮件。
   路径硬编码到 ninestores.in 站点目录。"
  (with-open-file (stream "/data/www/ninestores.in/public/emailtemplate.html"
                     :direction :output
                     :if-exists :supersede
                     :if-does-not-exist :create)
  (format stream "~A" contents)))


(defun process-file (file move-to)
  "把上传的临时文件 (tempfilewithpath tempfilename) 重命名/搬到 move-to 目录。
   仅在文件 < 1 MB 时执行；返回新文件名（带 universal-time 时间戳防重）。"
  (let* ((tempfilewithpath (nth 0 file))
	 (tempfilename (nth 1 file))
	 (final-file-name (format nil "~A-~A" (get-universal-time) tempfilename)))
   ;; Only if the file size is less than 1 mb do the operation. 
   (when (and (probe-file  tempfilewithpath) (with-open-file (s tempfilewithpath) (< (/ (file-length s) 1000000.0) 1)))  
     (rename-file tempfilewithpath (make-pathname :directory move-to  :name final-file-name)))
   final-file-name))




(defun get-ht-val (key hash-table)
    :documentation "If the key is found in the hash table, then return the value. Otherwise it returns nil in two cases. One- the key was present and value was nil. Second - key itself is not present
    中文：从哈希表读取 key 对应的 value；
          present=T 时返回 value（即使 value 为 nil 也返回 nil），
          present=NIL（key 不存在）时同样返回 nil —— 调用方无法区分这两种 nil。"
  (multiple-value-bind (value present) (gethash key hash-table)
      (if present value )))

(defun get-ht-values (hashtable)
  "返回哈希表第一个 value 的字符串表示（注意 loop ... return 仅返回首项，而非全部）。"
  (loop for v being the hash-value in hashtable
	return (format nil "~A" v)))


(defun parse-date-string (datestr)
  "Read a date string of the form \"DD/MM/YYYY\" and return the
corresponding universal time.
   中文：把 'DD/MM/YYYY' 字符串解析成 universal-time（秒数）。"
  (let ((date (parse-integer datestr :start 0 :end 2))
        (month (parse-integer datestr :start 3 :end 5))
        (year (parse-integer datestr :start 6 :end 10)))
    (encode-universal-time 0 0 0 date month year)))

(defun parse-date-string-yyyymmdd (datestr)
  "Read a date string of the form \"YYYY-MM-DD\" and return the
corresponding universal time.
   中文：把 'YYYY-MM-DD' 字符串解析成 universal-time。"
  (let ((year (parse-integer datestr :start 0 :end 4))
        (month (parse-integer datestr :start 5 :end 7))
        (date (parse-integer datestr :start 8 :end 10)))
    (encode-universal-time 0 0 0 date month year)))



(defun parse-time-string (timestr)
  :documentation "Read a time string of the form \"HH:MM:SS\" and return the corresponding universal time
  中文：把 'HH:MM:SS' 解析成 universal-time（日期固定为 1900-01-01）。"
 (let ((hour (parse-integer timestr :start 0 :end 2))
       (minute (parse-integer timestr :start 3 :end 5))
       (second (parse-integer timestr :start 6 :end 8)))
   (encode-universal-time second minute hour 1 1 0)))

(defun get-time-string-from-dateobj (dateobj)
"Returns current time  as a string in HH:MM:SS  format"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
      dateobj
    (declare (ignore day mon yr dow dst-p tz))
    (format nil "~2,'0d:~2,'0d:~2,'0d" hr min  sec)))
 
(defun current-time-string ()
  "Returns current time  as a string in HH:MM:SS  format
   中文：当前时刻字符串 HH:MM:SS。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore day mon yr dow dst-p tz))
      (format nil "~2,'0d:~2,'0d:~2,'0d" hr min  sec)))


(defun get-date-from-string (datestr)
    :documentation  "Read a date string of the form \"DD/MM/YYYY\" and return the corresponding date object.
    中文：'DD/MM/YYYY' → clsql wall-time date 对象。空串返回 nil。"
  (if (not (equal datestr ""))
      (let ((date (parse-integer datestr :start 0 :end 2))
            (month (parse-integer datestr :start 3 :end 5))
            (year (parse-integer datestr :start 6 :end 10)))
	(clsql-sys:make-date :year year :month month :day date :hour 0 :minute 0 :second 0 ))))

(defun get-dateobj-from-string-yyyymmdd (datestr)
    :documentation  "Read a date string of the form \"YYYY-MM-DD\" and return the corresponding date object.
    中文：'YYYY-MM-DD' → clsql date 对象。"
(if (not (equal datestr ""))
    (let ((year (parse-integer datestr :start 0 :end 4))
          (month (parse-integer datestr :start 5 :end 7))
          (date (parse-integer datestr :start 8 :end 10)))
      (clsql-sys:make-date :year year :month month :day date :hour 0 :minute 0 :second 0 ))))

(defun current-date-object ()
  "返回当前日期的 clsql date 对象（时分秒置 0）。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore sec min hr dow dst-p tz))
    (clsql-sys:make-date :year yr :month mon :day day :hour 0 :minute 0 :second 0)))
    

(defun current-date-string ()
  "Returns current date as a string in YYYY/MM/DD format
   中文：当前日期 YYYY/MM/DD。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore sec min hr dow dst-p tz))
    (format nil "~4,'0d/~2,'0d/~2,'0d" yr mon day)))

(defun current-date-string-yyyymmdd ()
  "Returns current date as a string in YYYY-MM-DD format
   中文：当前日期 YYYY-MM-DD。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore sec min hr dow dst-p tz))
      (format nil "~4,'0d-~2,'0d-~2,'0d" yr mon day)))

(defun current-date-string-ddmmyyyy ()
  "Returns current date as a string in DD-MM-YYYY format
   中文：当前日期 DD-MM-YYYY。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore sec min hr dow dst-p tz))
    (format nil "~2,'0d-~2,'0d-~4,'0d" day mon yr )))

(defun current-year-string ()
"Returns current year as a string in YYYY format
 中文：当前年份 YYYY。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore day mon sec min hr dow dst-p tz))
    (format nil "~4,'0d" yr )))

(defun current-year-string-- ()
"Returns current year as a string in YYYY format
 中文：当前年份 - 1（前一年）的 YYYY 字符串。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore day mon sec min hr dow dst-p tz))
    (format nil "~4,'0d" (decf yr))))

(defun current-year-string++ ()
"Returns current year as a string in YYYY format
 中文：当前年份 + 1（后一年）的 YYYY 字符串。"
  (multiple-value-bind (sec min hr day mon yr dow dst-p tz)
                       (get-decoded-time)
    (declare (ignore day mon sec min hr dow dst-p tz))
    (format nil "~4,'0d" (incf yr))))
  

(defun get-date-string (dateobj)
  "Returns current date as a string in DD/MM/YYYY format.
   中文：把 clsql date 对象格式化为 DD/MM/YYYY。"
  (multiple-value-bind (yr mon day)
      (clsql-sys:date-ymd dateobj)  (format nil "~2,'0d/~2,'0d/~4,'0d" day mon yr)))


(defun get-datestr-from-obj-yyyymmdd (dateobj)
  "Returns current date as a string in YYYY-MM-DD format.
   中文：把 clsql date 对象格式化为 YYYY-MM-DD。"
  (multiple-value-bind (yr mon day)
      (clsql-sys:date-ymd dateobj)   (format nil "~4,'0d-~2,'0d-~2,'0d" yr mon day)))


(defun mysql-now ()
  "返回当前时间的 MySQL DATETIME 字符串 'YYYY-MM-DD HH:MM:SS'。
   各处 INSERT/UPDATE 默认时间戳都用此函数。"
  (multiple-value-bind
        (second minute hour date month year day-of-week dst-p tz)
      (get-decoded-time)
    (declare (ignore day-of-week dst-p tz))
    ;; ~2,'0d is the designator for a two-digit, zero-padded number
    (format nil "~a-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d"
                 year month date hour minute second)))

(defun mysql-now+days (numdays)
  "返回 (当前 + numdays 天) 的 MySQL DATETIME 字符串。"
  (multiple-value-bind
        (second minute hour date month year day-of-week dst-p tz)
      (clsql-sys:decode-date (clsql-sys:date+ (clsql-sys:get-date) (clsql-sys:make-duration :day numdays)))
     (declare (ignore day-of-week dst-p tz))
    ;; ~2,'0d is the designator for a two-digit, zero-padded number
(format nil "~a-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d"
                 year month date hour minute second)))





(defun get-date-string-mysql (dateobj)
  "Returns current date as a string in DD-MM-YYYY format.
   中文：把 clsql date 对象格式化为 'YYYY-MM-DD'（注意 docstring 与实际格式不一致，
         实际输出的是 YYYY-MM-DD）。"
  (multiple-value-bind (yr mon day)
                       (clsql-sys:date-ymd dateobj)  (format nil "~4,'0d-~2,'0d-~2,'0d" yr mon day)))


(defun get-universal-time-from-date (dateobj)
  "把 clsql date 对象转回 Lisp universal-time（秒数）。"
  (multiple-value-bind (day mon year)
	  (clsql-sys:decode-date dateobj)
	    (encode-universal-time  0 0 0 day mon year)))



;; Lisp universal-time（1900-01-01 起算）与 Unix epoch（1970-01-01）的秒差。
(defvar *unix-epoch-difference*
  (encode-universal-time 0 0 0 1 1 1970 0))

(defun universal-to-unix-time (universal-time)
  "Lisp universal-time → Unix 时间戳。"
  (- universal-time *unix-epoch-difference*))

(defun unix-to-universal-time (unix-time)
  "Unix 时间戳 → Lisp universal-time。"
  (+ unix-time *unix-epoch-difference*))

(defun get-unix-time ()
  "返回当前 Unix 时间戳。"
  (universal-to-unix-time (get-universal-time)))

    


(defun generatehashkey (params-alist salt hashmethod)
  "把 (key . value) 列表按 key 排序后，用 '|' 拼接 value 与 salt，对结果做 hashmethod 摘要并返回大写 hex。
   注：值取自 (cdr str)，未做空值过滤，与 hashcalculate 行为不同；常用于支付网关签名。"
  (let* ((msg salt)
	(param-names (mapcar (lambda (param)
				(car param)) params-alist)))
    (setf param-names (sort param-names  #'string-lessp))
    (loop for item in param-names do 
	 (let ((str (find item params-alist :test #'equal :key #'car)))
	 (setf msg (concatenate 'string msg "|" (cdr str)))))
    (string-upcase (ironclad:byte-array-to-hex-string 
     (ironclad:digest-sequence
      hashmethod
      (ironclad:ascii-string-to-byte-array msg))))))

(defun hashcalculate (params-alist salt hashmethod)
  "类似 generatehashkey，但跳过空 value，并对每个 value 做 string-trim。
   适用于支付网关响应签名校验场景。"
  (let* ((msg salt)
	 (param-names (mapcar (lambda (param)
				(car param)) params-alist)))
    (setf param-names (sort param-names  #'string-lessp))
    (loop for item in param-names do 
	 (let* ((key (find item params-alist :test #'equal :key #'car))
	       (value (cdr key)))
	   (if (and value (> (length value) 0))
	   (setf msg (concatenate 'string msg "|" (string-trim " " value))))))
    (string-upcase (ironclad:byte-array-to-hex-string 
     (ironclad:digest-sequence
      hashmethod
      (ironclad:ascii-string-to-byte-array msg))))))
  



(defun responsehashcheck (params-alist salt hashmethod)
  "校验支付网关回调响应的 hash 是否合法。
   流程：从 params-alist 取出 'hash' 项 → 移除后用 hashcalculate 重算 → 比对一致返回 T。"
  (let* ((received-hash (cdr (find "hash" params-alist :test #'equal :key #'car)))
	 (new-params-alist (remove (find "hash" params-alist :test #'equal :key #'car) params-alist))
	 (newhash (hashcalculate new-params-alist salt hashmethod)))
    (equal newhash received-hash)))
    
	

(defun createciphersalt ()
  "生成 28 字节加密学安全随机盐值（hex 字符串）。"
  (let ((salt-octet (secure-random:bytes 28 secure-random:*generator*)))
    (ironclad:byte-array-to-hex-string salt-octet)))

(defun get-cipher (salt)
  "构造 Blowfish ECB 模式的 cipher（key 直接用 salt 字符串字节）。
   注：ECB 模式不抗模式分析；本项目仅作密码核验用途，敏感数据不应只靠它保护。"
  (ironclad:make-cipher :blowfish
    :mode :ecb
    :key (ironclad:ascii-string-to-byte-array salt)))

(defun encrypt (plaintext salt)
  "用 salt 加密 plaintext；返回 hex 字符串。
   配合 check-password 用于用户密码核验。"
  (let ((cipher (get-cipher salt))
        (msg (ironclad:ascii-string-to-byte-array plaintext)))
    (ironclad:byte-array-to-hex-string (ironclad:encrypt-message cipher msg))))

(defun create-digest-sha1 (plaintext)
  "返回 plaintext 的 SHA-1 摘要 hex 字符串。"
  (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha1 (ironclad:ascii-string-to-byte-array plaintext))))

(defun create-digest-md5 (plaintext)
  "返回 plaintext 的 MD5 摘要 hex 字符串。"
  (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :md5 (ironclad:ascii-string-to-byte-array plaintext))))

(defun create-md5-from-list (items)
  "Takes a list of strings, joins them with commas, and returns the MD5 digest.
   中文：把字符串列表用逗号 join 后做 MD5。"
  (let ((joined (format nil "~{~A~^,~}" items)))
    (create-digest-md5 joined)))

(defun decrypt (ciphertext key)
  "使用 key（盐）对 hex 形式的 ciphertext 做 Blowfish ECB 解密，返回明文字符串。"
  (let ((cipher (get-cipher key))
        (msg (ironclad:integer-to-octets (ironclad:octets-to-integer (ironclad:ascii-string-to-byte-array ciphertext)))))
    (ironclad:decrypt-in-place cipher msg)
    (coerce (mapcar #'code-char (coerce msg 'list)) 'string)))

(defun check-password (plaintext salt ciphertext)
  "登录核验：(encrypt plaintext salt) 是否与库中 ciphertext 完全相等。"
  (if (equal (encrypt plaintext salt) ciphertext) T NIL))





;;;; Virtual host related things ;;;; 
  
