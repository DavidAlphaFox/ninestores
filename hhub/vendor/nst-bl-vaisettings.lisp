;;; nst-bl-vaisettings.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：vendor —— AI 自然语言驱动的设置管理（Vendor AI Settings）
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/vendor/nst-bl-vaisettings.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：把 vendor 自然语言指令交给 LLM 抽取为结构化 intent，
;;;;       再用关键词评分匹配到 *vendor-setting-registry* 中已注册的 setting，
;;;;       最后做类型校验并落地（execute-setting 当前为占位）。
;;;;       推测：与 nst-bl-vwebrepl.lisp 一起构成 vendor 设置 AI 入口。
;;;;
;;;; 主要导出：
;;;;   *vendor-setting-registry*   —— 设置项注册表
;;;;   intent / make-intent        —— 意图 CLOS 类与构造器
;;;;   prompt-for-llm              —— 喂给 LLM 的固定 prompt 模板
;;;;   build-llm-prompt / llm->intent      —— prompt 渲染 + LLM 调用桩
;;;;   tokenize / score-setting / resolve-setting / select-setting
;;;;                               —— 关键词打分匹配
;;;;   execute-setting / build-execution-context
;;;;                               —— 类型校验 + 持久化占位
;;;;   run-intent                  —— 总编排入口
;;;;
;;;; 关联：
;;;;   上游使用方：vendor 控制器（推测）。
;;;;   下游依赖：core/nst-bl-ollama.lisp 的 ollama-generate；split-sequence、cl-ppcre。
;;;; ============================================================================

(in-package :nstores)

;;;; ----------------------------
;;;; Vendor setting registry
;;;; vendor 设置项注册表：每条记录一个可配置开关，含 key/域/类型/描述/匹配关键词
;;;; ----------------------------

(defparameter *vendor-setting-registry*
  '((:key nst.vendor.invoicesetting.send-invoice-email-after-paid
     :domain :invoice
     :data-type :boolean
     :description "Send invoice email immediately after payment"
     :keywords ("send" "email" "invoice" "paid"))

    (:key nst.vendor.invoicesetting.attach-pdf-to-invoice-email
     :domain :invoice
     :data-type :boolean
     :description "Attach invoice PDF to email"
     :keywords ("attach" "pdf" "invoice" "email"))))


;;;; ----------------------------
;;;; Intent CLOS class
;;;; 由 LLM 抽取出的意图对象：actor / domain / operation / description / raw-text / trace
;;;; ----------------------------

(defclass intent ()
  ((actor       :initarg :actor       :accessor intent-actor)
   (domain      :initarg :domain      :accessor intent-domain)
   (operation   :initarg :operation   :accessor intent-operation)
   (description :initarg :description :accessor intent-description)
   (raw-text    :initarg :raw-text    :accessor intent-raw-text)
   (trace       :initarg :trace       :accessor intent-trace)))


(defun make-intent (&key actor domain operation description raw-text trace)
  "构造 intent 实例。各参数对应 LLM 返回的 plist 槽位。"
  (make-instance 'intent
                 :actor actor
                 :domain domain
                 :operation operation
                 :description description
                 :raw-text raw-text
                 :trace trace))


;; LLM 系统提示词模板：要求 LLM 仅返回固定结构的 plist；正文 %user-input%
;; 会在 build-llm-prompt 中被替换为用户实际输入。
(defparameter prompt-for-llm "You are an intent extraction engine for a Common Lisp system.

Your task:
- Convert user text into a structured intent object.
- Do NOT infer system-specific identifiers.
- Do NOT guess setting keys.
- Do NOT execute actions.
- Preserve the user's words faithfully.

Return output ONLY as a Common Lisp property list.

Schema (MANDATORY):
(:actor <number>
 :domain <keyword>
 :operation <keyword>
 :description <string>
 :raw-text <string>
 :trace ((:origin . <keyword>)
         (:session . <string>)))

Rules:
- :actor is always a number.
- :domain must be a single keyword.
- :operation must be one keyword.
- :description is a short normalized summary.
- :raw-text is %user-input%.
- If uncertain, choose the most likely domain but NEVER invent new fields.
- No explanations.
- No markdown.")


(defun build-llm-prompt (text user-input)
  "把 prompt 模板里的 %user-input% 占位符替换为真实用户输入。
   注意：直接 setf 入参，不复制；调用方传 *prompt-for-llm* 时不会破坏全局值，
        因为 cl-ppcre 返回新串。"
  (setf text (cl-ppcre:regex-replace-all "%user-input%" text user-input))
  text)
 
;;;; ----------------------------
;;;; Naive LLM stub
;;;; Replace later with real LLM
;;;; LLM 调用桩：调 ollama-generate 拿响应，read-from-string 当 plist 解析
;;;; ----------------------------

(defun llm->intent (text)
  "把用户文本喂给 Ollama LLM 抽取意图。
   流程：build-llm-prompt → ollama-generate → read-from-string → make-intent。
   返回：intent 实例。
   备注：依赖 LLM 严格按 prompt 返回合法 plist；非法输出会触发 read 异常。"
  (let* ((prompt (build-llm-prompt prompt-for-llm text))
         (response (ollama-generate prompt))
         (plist (read-from-string response)))
    (apply #'make-intent plist)))


;;;; ----------------------------
;;;; Scoring & resolution
;;;; ----------------------------

(defun tokenize (text)
  "把 text 按空格切分并转小写，作为关键词匹配的 token 列表。"
  (mapcar #'string-downcase
          (split-sequence:split-sequence #\Space text)))

(defun score-setting (intent setting)
  "对单条 setting 评分：intent.description 切词后与 setting :keywords 命中数 / 关键词总数。
   返回：[0,1] 区间内 float 分数。"
  (let* ((intent-tokens (tokenize (intent-description intent)))
         (keywords (getf setting :keywords))
         (matches (count-if (lambda (k)
                              (member k intent-tokens :test #'string=))
                            keywords)))
    (/ (float matches) (max 1 (length keywords)))))




(defun resolve-setting (intent)
  "把意图对照 *vendor-setting-registry* 全表打分并按分数降序排列。
   返回：plist 候选列表，每条含 :key :score :data-type。"
  (let ((candidates
          (mapcar (lambda (s)
                    (list :key (getf s :key)
                          :score (score-setting intent s)
                          :data-type (getf s :data-type)))
                  *vendor-setting-registry*)))
    (sort candidates #'> :key (lambda (c) (getf c :score)))))


(defun select-setting (candidates)
  "从打分结果决定下一步：
     score >= 0.9       → 直接返回该候选；
     0.7 <= score < 0.9 → 返回 (:needs-confirmation candidates)，需要用户确认；
     其他               → 返回 (:ambiguous candidates)，提示语义模糊。"
  (let ((top (first candidates)))
    (cond
      ((>= (getf top :score) 0.9)
       top)
      ((>= (getf top :score) 0.7)
       (list :needs-confirmation candidates))
      (t
       (list :ambiguous candidates)))))


;;;; ----------------------------
;;;; Execution layer
;;;; ----------------------------

(defun execute-setting (&key vendor-id setting-key value data-type context-id trace)
  "占位执行函数：先按 data-type 校验 value 类型，再用 format 打印一条调试日志。
   备注：当前只 stdout 输出，未真正写库；待替换为持久化实现。"
  ;; type validation
  (unless (typep value
                 (ecase data-type
                   (:boolean 'boolean)
                   (:number 'number)
                   (:string 'string)
                   (:json 'list)))
    (error "Invalid value type"))

  ;; placeholder for real persistence
  (format t "~%[EXECUTE] vendor=~A key=~A value=~A context=~A trace=~A~%"
          vendor-id setting-key value context-id trace)

  t)


(defun build-execution-context (intent resolved-setting value)
  "把 intent + 已解析的 setting + 用户提供的 value 组装为 execute-setting 需要的关键字参数并调用。"
  (execute-setting
   :vendor-id (intent-actor intent)
   :setting-key (getf resolved-setting :key)
   :value value
   :data-type (getf resolved-setting :data-type)
   :context-id (cdr (assoc :session (intent-trace intent)))
   :trace (intent-trace intent)))


;;;; ----------------------------
;;;; Orchestration
;;;; ----------------------------

(defun run-intent (text)
  "总编排：自然语言文本 → LLM 抽取意图 → 关键词打分 → 决策。
   高置信直接执行；中置信返回 :needs-confirmation；低置信返回 :ambiguous。
   返回：执行结果 / 决策 plist。
   备注：当前 build-execution-context 第三个参数硬编码为 t（推测：占位，
        实际应从用户输入抽取 boolean/数值/字符串 value）。"
  (let* ((intent (llm->intent text))
         (candidates (resolve-setting intent))
         (decision (select-setting candidates)))
    (cond
      ((eq (first decision) :needs-confirmation)
       decision)
      ((eq (first decision) :ambiguous)
       decision)
      (t
       (build-execution-context intent decision t)))))


;;;; ----------------------------
;;;; Example
;;;; ----------------------------

;; (run-intent  "set vendor invoice setting send email after invoice payment is done")
