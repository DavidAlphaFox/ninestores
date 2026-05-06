;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— Ollama AI 集成
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/nst-bl-ollama.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：通过 HTTP 调用本地 Ollama 服务（默认 qwen2.5:3b 模型），
;;;;       支持自然语言 → SQL 生成（带 schema 约束 + 危险语句过滤）以及
;;;;       Common Lisp 代码解释场景。
;;;;
;;;; 主要导出：
;;;;   ollama-generate         — 通用 prompt → 文本生成
;;;;   parse-ollama-ndjson     — 解析 NDJSON 流式响应
;;;;   nl-to-sql               — 自然语言 → SQL（注入 vendor 表 schema）
;;;;   ollama-lisp-help        — 发 Lisp 代码给模型解释
;;;;   safe-nl-to-sql          — 在 nl-to-sql 外加 DROP/TRUNCATE/ALTER/DELETE 拦截
;;;;   *ollama-url* / *ollama-model* — 端点 + 模型名
;;;;
;;;; 关联：
;;;;   上游使用方：vendor 后台 AI Agent 助手
;;;;   下游依赖：drakma、cl-json、split-sequence；
;;;;             nst-get-cached-vendor-tables-structure-for-agentic-ai 缓存函数
;;;; ============================================================================
(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



(defparameter *ollama-url* "http://192.168.0.100:11434/api/generate")
(defparameter *ollama-model* "qwen2.5:3b")
(defvar *dod-vend-profile-table* "/home/ubuntu/ninestores/hhub/vendor/templates/dod-vend-profile.txt")
(defvar *dod-invoice-header-table* "/home/ubuntu/ninestores/hhub/vendor/templates/dod-invoice-header.txt")
(defvar *dod-invoice-items-table* "/home/ubuntu/ninestores/hhub/vendor/templates/dod-invoice-items.txt")


(defun ollama-generate (prompt &key system)
  "向 Ollama 服务发送 generate 请求并返回拼接后的纯文本响应。
   参数：prompt — 用户提示；system — 系统消息（角色/约束）。
   备注：stream=nil 时 Ollama 仍会返回 NDJSON，故内部仍调 parse-ollama-ndjson。"
  (let* ((payload
           (json:encode-json-to-string
            `((:model . ,*ollama-model*)
              (:prompt . ,prompt)
              (:system . ,system)
              (:stream . nil))))
	 (raw-response
           (drakma:http-request
            *ollama-url*
            :method :POST
	    :content payload
            :content-type "application/json"))
         (json-response
           ;;(json:decode-json-from-string
            (parse-ollama-ndjson (map 'string #'code-char raw-response))))
    json-response))


(defun parse-ollama-ndjson (string)
  "解析 Ollama 的 NDJSON 响应（按行分隔），把每行 JSON 中的 :RESPONSE 字段拼成单一字符串。"
  (let ((out ""))
    (dolist (line (split-sequence:split-sequence #\Newline string))
      (when (> (length line) 0)
        (let* ((obj (json:decode-json-from-string line))
              (chunk (cdr (assoc :RESPONSE obj))))
            (setf out (concatenate 'string out chunk)))))
    out))



  


(defparameter *sql-schema-rules*
  "Rules:
- Use only tables and columns from the schema
- Do not invent tables or columns
- Do not explain the query
- Vendors are identified by VENDOR_ID
- Soft deletes use DELETED_STATE = 'N'
- ACTIVE_FLAG = 'Y' means active
- Monetary fields are DECIMAL
- Never select PASSWORD, SALT, API keys
- Default tenant isolation: TENANT_ID = :tenant_id
- Return only SQL
If the request cannot be answered using the schema,
return:
ERROR: CANNOT_GENERATE_SQL")

(defun nl-to-sql (natural-language)
  "把自然语言请求翻译成 SQL。先注入 vendor/invoice/invoice-items 三张表的 schema，
   再带上 *sql-schema-rules* 约束（软删过滤、tenant 隔离、禁止 DROP 等）。
   返回：字符串 SQL；模型无法生成时返回 'ERROR: CANNOT_GENERATE_SQL'。"
  (let ((sql-schema (format nil "~A ~A ~A "
	  (funcall (nst-get-cached-vendor-tables-structure-for-agentic-ai :templatenum 1))
	  (funcall (nst-get-cached-vendor-tables-structure-for-agentic-ai :templatenum 2))
	  (funcall (nst-get-cached-vendor-tables-structure-for-agentic-ai :templatenum 3)))))
    (ollama-generate
     (format nil
             "Database Schema:
~A
~A 
User Request:
~A"
           sql-schema *sql-schema-rules* natural-language)
   :system
   "You are a MySQL query generator. Return a complete SQL query.
The query must end with a semicolon.")))

(defun ollama-lisp-help (code)
  "把 Lisp 代码片段交给模型，请求精炼的解释；system 角色锁定为 senior CL 开发者。"
  (ollama-generate
   code
   :system
   "You are a senior Common Lisp developer.
Explain idiomatic Lisp usage, macros, closures,
and functional design. Be precise and concise."))

(defun unsafe-sql-p (sql)
  "检测 SQL 是否包含写/破坏性操作（DROP / TRUNCATE / ALTER / DELETE）。"
  (or (search "DROP" sql :test #'char-equal)
      (search "TRUNCATE" sql :test #'char-equal)
      (search "ALTER" sql :test #'char-equal)
      (search "DELETE" sql :test #'char-equal)))

(defun safe-nl-to-sql (input)
  "nl-to-sql 的安全包装：若结果含危险语句直接 error，避免误执行破坏性 SQL。"
  (let ((sql (nl-to-sql input)))
    (if (unsafe-sql-p sql)
        (error "Unsafe SQL generated: ~A" sql)
        sql)))


