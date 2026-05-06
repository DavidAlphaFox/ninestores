;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— Context Flow Dispatcher（六边形/DDD 调度管线）
;;;; 分层：BL（业务逻辑层 + 应用编排）
;;;; 文件：hhub/core/nst-bl-conflodis.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：提供新一代请求处理管线，把 Hunchentoot 进入 → ABAC 校验 → 业务调用
;;;;       → 响应模型 → 视图渲染 串成 CLOS 通用函数 dispatch 的 :before / 主方法
;;;;       / :after / :around 链。围绕 call-context 单一可变对象传递。
;;;;
;;;; 架构对应（详见 docs/architecture.md 第 7 节）：
;;;;     dispatch :before  → make-requestmodel / make-adapter
;;;;     dispatch (主)     → with-hhub-transaction PEP + processxxxrequest
;;;;     dispatch :after   → ProcessResponse / ProcessResponseList
;;;;     dispatch :around  → make-presenter / CreateViewModel / make-view / render
;;;;
;;;; 主要导出：
;;;;   call-context / call-context-create/-read/-readall/-update/-delete
;;;;   outbound-adapter-route                  — 路由配置类（含 ABAC、特性开关、审计）
;;;;   register-outbound-route / find-outbound-route
;;;;   *NST-OUTBOUND-ROUTE-REGISTRY*            — 全局路由表（hash table）
;;;;   collect-abac-attributes                  — 把 ctx 信息装成 PEP 的 alist params
;;;;   make-adapter / make-presenter / make-view / make-requestmodel
;;;;   route-op->method-name                    — :customer/read → processreadrequest
;;;;   create-response-from-domain / create-viewmodel-from-response
;;;;   dispatch（CLOS generic + 多组方法）
;;;;   resolve-view-for                         — 按 output-type 选 View 类
;;;;   make-call-context / dispatch-route       — 入口便利函数
;;;;
;;;; 关联：
;;;;   上游使用方：新风格控制器（warehouse / customer / order）
;;;;   下游依赖：core/hhub-bl-egn.lisp（AdapterService/BusinessService/...）、
;;;;             core/nst-bl-beltrusys.lisp（bo-knowledge 四值容错）、
;;;;             core/dod-ui-utl.lisp（with-hhub-transaction PEP 宏）
;;;; ============================================================================
(in-package :nstores)

;;; ---------------------------------------------------------------------------
;;; Call context - single mutable object passed through pipeline
;;; ---------------------------------------------------------------------------
;; call-context：贯穿整个 dispatch 管线的"工作台"对象。
;; before/primary/after/around 各方法通过它共享 requestmodel、adapter、
;; domain-object、responsemodel、presenter、viewmodel、view、bo-knowledge 等。
(defclass call-context ()
  ((route-key    :initarg :route-key    :reader ctx-route-key)
   (http-request :initarg :ctx-http-request)
   (requestmodel-params  :initarg :requestmodel-params  :reader ctx-requestmodel-params)
   (request-uri :initarg :request-uri :accessor ctx-request-uri)
   (trans-func-name :initarg :trans-func-name :reader ctx-trans-func-name)
   (requestmodel :accessor ctx-requestmodel :initform nil)
   (adapter      :accessor ctx-adapter      :initform nil)
   (domain-object :accessor ctx-domain-object :initform nil)
   (responsemodel :accessor ctx-responsemodel :initform nil)
   (presenter     :accessor ctx-presenter     :initform nil)
   (viewmodel     :accessor ctx-viewmodel     :initform nil)
   (view          :accessor ctx-view          :initform nil)
   (output-type :accessor ctx-output-type :initform nil)
   (bo-knowledge  :accessor ctx-bo-knowledge  :initform nil)
   (company :accessor ctx-company :initform nil)
   (context       :accessor ctx-context       :initform nil)))


;; 子类用于 :around 方法的 CLOS 派发，按 CRUD 走不同输出阶段（presenter→viewmodel→view→render）。
(defclass call-context-create (call-context)
  ())

(defclass call-context-read (call-context)
  ())

(defclass call-context-readall (call-context)
  ;; 列表读，需要 CreateAllViewModel + 循环渲染。
  ())

(defclass call-context-update (call-context)
  ())
(defclass call-context-delete (call-context)
  ())


;;; ---------------------------------------------------------------------------
;;; Outbound adapter route definition (DDD / Hexagonal naming)
;;; ---------------------------------------------------------------------------

;; outbound-adapter-route：单条业务路由的元数据。
;; 每个 register-outbound-route 创建一条 route 实例并塞进 *NST-OUTBOUND-ROUTE-REGISTRY*；
;; 包含 8 大类信息：标识、类绑定、CRUD、状态、ABAC、多租户覆盖、生命周期钩子、审计。
(defclass outbound-adapter-route ()
  (
   ;; ----------------------------------------------
   ;; 1. BASIC IDENTIFICATION
   ;; ----------------------------------------------
   (route-key
     :initarg :route-key
     :accessor route-key
     :documentation "Keyword identifier for the route, e.g. :customer/read")

   (description
     :initarg :description
     :accessor description
     :initform ""
     :documentation "Human-readable description for documentation & dashboards.")
   (businessobject-class 
    :initarg :businessobject-class
    :accessor businessobject-class
    :initform nil
    :documentation "Business object class associated with this route" )
   (requestmodel-class 
    :initarg :requestmodel-class
    :accessor requestmodel-class
    :initform nil
    :documentation "Requestmodel class associated with this route" )
   
   (adapter-class
    :initarg :adapter-class
    :accessor adapter-class
    :initform nil
    :documentation "Adapter class associated with this route")
   (presenter-class
    :initarg :presenter-class
    :accessor presenter-class
    :initform nil
    :documentation "Presenter class associated with this route")
   (view-classes
    :initarg :view-classes
    :accessor view-classes
    :initform nil
    :documentation "View classes associated with this route")
   
    ;; ----------------------------------------------
   ;; 2. FUNCTIONAL METADATA: CRUD / OPERATION TYPE
   ;; ----------------------------------------------
   (crud-op
     :initarg :crud-op
     :accessor crud-op
     :documentation
     "Symbol indicating the domain operation: :create :read :update :delete :list :search :custom.")

   ;; Optional business operation name for non-CRUD actions
   (operation
     :initarg :operation
     :accessor operation
     :initform nil
     :documentation
     "Optional symbolic name for non-CRUD operations (e.g. :approve, :cancel, :rate, :checkout).")

   ;; ----------------------------------------------
   ;; 3. ROUTE STATE / FEATURE FLAGS
   ;; ----------------------------------------------
   (active
     :initarg :active
     :accessor active
     :initform t
     :documentation
     "Boolean flag to activate/deactivate this route without deleting it.")

   (feature-flags
     :initarg :feature-flags
     :accessor feature-flags
     :initform nil
     :documentation
     "List of feature flags controlling conditional behavior (e.g. '(enable-email new-pricing-model)).")

   ;; ----------------------------------------------
   ;; 5. SECURITY / ACCESS CONTROL
   ;; ----------------------------------------------
   (required-roles
     :initarg :required-roles
     :accessor required-roles
     :initform nil
     :documentation
     "List of roles allowed to call this route. Example: '(admin vendor support).")

   (permission-checker
     :initarg :permission-checker
     :accessor permission-checker
     :initform nil
     :documentation
     "Optional function performing advanced ACL:
       (lambda (route ctx user) -> T/NIL).")

   ;; ----------------------------------------------
   ;; 6. MULTI-TENANT ROUTING SUPPORT
   ;; ----------------------------------------------
   (tenant-overrides
     :initarg :tenant-overrides
     :accessor tenant-overrides
     :initform nil
     :documentation
     "Association list: (tenant-id . override-plist)
       Example:
       '((tenantA . (:default-outbound-adapters (json)))
         (tenantB . (:default-outbound-adapters (json kafka email)))
         (tenantC . (:active nil)))")

   ;; ----------------------------------------------
   ;; 7. LIFECYCLE HOOKS (pre/post)
   ;; ----------------------------------------------
   (before-dispatch-hook
     :initarg :before-dispatch-hook
     :accessor before-dispatch-hook
     :initform nil
     :documentation
     "Optional function: (lambda (route ctx) -> maybe mutate ctx).
      Runs BEFORE dispatch.")

   (after-dispatch-hook
     :initarg :after-dispatch-hook
     :accessor after-dispatch-hook
     :initform nil
     :documentation
     "Optional function: (lambda (route ctx domain resp) -> NIL).
      Runs AFTER primary dispatch but before outbound adapters.")

   ;; ----------------------------------------------
   ;; 8. AUDIT / OBSERVABILITY
   ;; ----------------------------------------------
   (audit-level
     :initarg :audit-level
     :accessor audit-level
     :initform :minimal
     :documentation
     "Audit level: :none :minimal :full :debug. Controls logging & monitoring.")
   (tags
     :initarg :tags
     :accessor tags
     :initform nil
     :documentation
     "Arbitrary metadata tags for grouping/searching routes.
      Example: '(customer rest v1 read-only).")
   (version
    :initarg :version
    :accessor version
    :initform nil
    :documentation "Version number")
   (metadata
    :initarg :metadata
    :accessor metadata
    :initform nil
    :documentation "Any meta data we would like to maintain")))







(defun register-outbound-route (route-key &key
					    businessobject-class
					    requestmodel-class
					    adapter-class
					    presenter-class
					    view-classes
					    description
					    crud-op
					    operation
					    (active t)
					    feature-flags
					    required-roles
					    tenant-overrides
					    before-dispatch-hook
					    after-dispatch-hook
					    audit-level
					    tags
					    (version 1)
                                            metadata)
  "Registers an outbound adapter route in *outbound-route-registry*.
   中文：注册一条新路由到 *NST-OUTBOUND-ROUTE-REGISTRY*。
         crud-op 未显式传入时按 route-key 字符串后缀（/read /create /update /delete）自动推断，
         均无匹配则默认 :read。

Arguments:
  route-key                 - Required keyword (e.g. :customer/read)
  crud-op                   - :create :read :update :delete (optional)
  description               - Optional human description
  active                    - Whether route is active (default T)
  default-outbound-adapters - List of default output formats (e.g. '(json))
  adapter-selector          - Function(route ctx) -> list of output formats
  tags                      - Arbitrary tagging info
  version                   - Version number
  metadata                  - Extensible alist for future fields

Returns:
  The created outbound-adapter-route object."
  (assert route-key () "route-key is required")
  ;; Auto-infer CRUD-op if user didn't specify
  (let ((final-crud-op
          (or crud-op
              (cond
                ((search "/read"   (string-downcase (symbol-name route-key))) :read)
                ((search "/create" (string-downcase (symbol-name route-key))) :create)
                ((search "/update" (string-downcase (symbol-name route-key))) :update)
                ((search "/delete" (string-downcase (symbol-name route-key))) :delete)
                (t :read)))))   ;; sensible default
    (let ((route (make-instance 'outbound-adapter-route
                                :route-key route-key
                                :crud-op final-crud-op
				:requestmodel-class requestmodel-class 
				:businessobject-class businessobject-class
				:adapter-class adapter-class
				:presenter-class presenter-class
				:view-classes view-classes 
				:description description
				:operation operation
				:active active
                                :audit-level audit-level
				:feature-flags feature-flags
				:required-roles required-roles
				:before-dispatch-hook before-dispatch-hook
				:after-dispatch-hook after-dispatch-hook
				:tenant-overrides tenant-overrides
				:tags tags
                                :version version
                                :metadata metadata)))
      ;; store in registry
      (setf (gethash route-key *NST-OUTBOUND-ROUTE-REGISTRY*) route)
      route)))

(defun find-outbound-route (route-key)
  "按 keyword 在路由注册表中查 route 实例。"
  (gethash route-key *NST-OUTBOUND-ROUTE-REGISTRY*))

(defmethod collect-abac-attributes ((route outbound-adapter-route) (ctx call-context))
  "把 ctx 信息整理成 PEP 宏 with-hhub-transaction 期望的 alist params：
   uri / company / subject-id / resource / action / client-ip。
   备注：subject-id 来自 ctx-context.user-id；client-ip 出错时回落 127.0.0.1。"
  (let ((params nil))
    ;; Always include URI
    (setf params (acons "uri" (ctx-request-uri ctx) params))
    ;; Include company if available
    (let ((company (ctx-company ctx)))
      (when company
        (setf params (acons "company" company params))))
    ;; Subject attributes (example)
    (when (ctx-context ctx)
      (setf params (acons "subject-id" (slot-value (ctx-context ctx) 'user-id) params)))
    ;; Resource attributes derived from route
    (setf params (acons "resource" (symbol-name (ctx-route-key ctx)) params))
    ;; Action inferred from CRUD
    (setf params (acons "action" (symbol-name (crud-op route)) params))
    ;; Environment IP
    (setf params (acons "client-ip" 
                        (handler-case 
                            (hunchentoot:remote-addr*)
                          (error () "127.0.0.1"))
                        params))
    (format t "I am in collect-abac-attributes")
    params))

(defgeneric make-adapter (route ctx)
  (:documentation "Create adapter instance for route. Override as needed."))

(defgeneric make-presenter (route ctx)
  (:documentation "Returns a presenter instance for this request."))

(defgeneric make-view (route ctx output-type)
  (:documentation "Returns a view instance for this request."))

(defgeneric make-requestmodel (route ctx)
  (:documentation "Create requestmodel instance for a route from ctx-requestmodel-params."))

(defmethod make-requestmodel ((route outbound-adapter-route) (ctx call-context))
  "默认实现：按 route 上配置的 requestmodel-class 名 intern 出符号 → make-instance。
   ctx-requestmodel-params 是 plist 形式 initargs。class 不存在时回退 standard-object。"
  ;; By default assume requestmodel-params is a plist of initargs
  (let* ((rmclass (requestmodel-class route))
	 (requestmodel-params (ctx-requestmodel-params ctx))
         (name (string-upcase (symbol-name rmclass)))
         (cls  (intern (format nil "~A" name) :nstores)))
    (if (find-class cls nil)
        (apply #'make-instance cls requestmodel-params)
        ;; safe fallback presenter
        (make-instance 'standard-object))))

(defmethod make-presenter ((route outbound-adapter-route) (ctx call-context))
  "默认实现：按 route 上的 presenter-class 名实例化 presenter；找不到则回退 standard-object。"
  (let* ((class (presenter-class route))
         (name (string-upcase (symbol-name class)))
         (cls  (intern (format nil "~A" name) :nstores)))
    (if (find-class cls nil)
        (make-instance cls)
        ;; safe fallback presenter
        (make-instance 'standard-object))))

(defmethod make-view ((route outbound-adapter-route)
                      (ctx   call-context)
                      output-type)
  "按 ctx 中的 bo-knowledge 真值挑选不同 View 类：
     :T → resolve-view-for（按 output-type 取 route 配置的 view-classes）
     :F → ViewNIL（未找到容错视图）
     :U → ViewUnknown（不可用容错视图）
     :C → ViewContradiction（数据冲突容错视图）
   未知真值兜底为 ViewUnknown。view-class 仍找不到时直接 error。"
  (let* ((truth (bo-knowledge-truth (ctx-bo-knowledge ctx)))
         (view-class
           (case truth
             (:T  (resolve-view-for route output-type))
             (:F  'ViewNIL)
             (:U  'ViewUnknown)
             (:C  'ViewContradiction)
             (otherwise 'ViewUnknown)))       ;; safe fallback
         ;; Convert symbol → class object
         (cls-object (find-class view-class nil)))
    (if cls-object
        (make-instance cls-object)
        (error "Unknown view class: ~A" view-class))))

(defmethod make-adapter ((route outbound-adapter-route) (ctx call-context))
  "默认实现：按 route 上的 adapter-class 名实例化适配器；找不到则回退 standard-object。"
  (let* ((class (adapter-class route))
         (name (string-upcase (symbol-name class)))
         (cls  (intern (format nil "~A" name) :nstores)))
    (if (find-class cls nil)
        (make-instance cls)
        ;; safe fallback presenter
        (make-instance 'standard-object))))

(defun route-op->method-name (route-key)
  "Extract operation from keyword like :customer/read and compute method name.
   中文：从 :customer/read 形式 keyword 中取出 'read'，拼成 'processreadrequest' 符号。
         dispatch 主方法用它反射调用业务处理函数。"
  (let* ((name (string route-key))             ; ":customer/read"
         (slash-pos (position #\/ name))
         (op (subseq name (1+ slash-pos)))     ; "read"
         (method-name (format nil "process~arequest" op)))
    (intern (string-upcase method-name) :nstores)))


(defgeneric create-response-from-domain (adapter domain-result)
  (:documentation "Polymorphic response creation"))

(defmethod create-response-from-domain ((adapter AdapterService) (domain-obj BusinessObject))
  "单实体路径：调 ProcessResponse 把领域对象转成单个 ResponseModel。"
  (ProcessResponse adapter domain-obj))

(defmethod create-response-from-domain ((adapter AdapterService) (domain-list list))
  "列表路径：调 ProcessResponseList 把列表转成 ResponseModel 列表（用于 readall）。"
  (format t "I am in create-response-from-domain for a list ~C~C" #\return #\linefeed)
  (ProcessResponseList adapter domain-list))

(defgeneric create-viewmodel-from-response (presenter response-data)
  (:documentation "Polymorphic viewmodel creation - only for READ operations"))

(defmethod create-viewmodel-from-response ((presenter PresenterService) (response ResponseModel))
  "单实体：CreateViewModel 把 ResponseModel → ViewModel。"
  (CreateViewModel presenter response))

(defmethod create-viewmodel-from-response ((presenter PresenterService) (response-list list))
  "列表：CreateAllViewModel 把 ResponseModel 列表 → ViewModel 列表。"
  (CreateAllViewModel presenter response-list))

;;; ---------------------------------------------------------------------------
;;; Core dispatch pipeline (CLOS generic with method combinators)
;;; - :before: prepare requestmodel, adapter, service
;;; - primary: invoke application/business flow (adapter -> service -> produce domain object)
;;; - :after: create responsemodel from adapter/service output
;;; - :around: choose outbound adapters (routing) and run them (short-circuiting possible)
;;; ---------------------------------------------------------------------------
(defgeneric dispatch (ctx route output-type)
  (:documentation "Runs pipeline + outbound adapter selection."))

(defmethod dispatch :before ((ctx call-context) (route outbound-adapter-route) output-type)
  "前置阶段：确认 ctx-route-key 有路由 → 构造 requestmodel 与 adapter。
   备注：内层 (find-outbound-route ...) 把 route 又查了一遍以做 sanity check；
         若 register 时漏挂会在此处 error 提早拦截。"
  (let ((route (find-outbound-route (ctx-route-key ctx))))
    (unless route (error "No outbound route registered for ~a" (ctx-route-key ctx)))
    (format t "dispatch :before called ~C~C" #\return #\linefeed) 
    ;; create requestmodel and attach
    (setf (ctx-requestmodel ctx) (make-requestmodel route ctx))
    (setf (ctx-company ctx) (slot-value (ctx-requestmodel ctx) 'company))
    ;; create adapter/service if desired
    (setf (ctx-adapter ctx) (make-adapter route ctx))))


(defmethod dispatch ((ctx call-context) (route outbound-adapter-route) output-type)
  "主方法：组装 ABAC params → with-hhub-transaction PEP 校验 →
   反射调 process<op>request adapter rm 拿到 domain object → 把 adapter 的
   bo-knowledge 拷到 ctx 供 :around 选 view 使用。"
  (let ((adapter         (ctx-adapter ctx))
        (rm              (ctx-requestmodel ctx))
        (route-key       (ctx-route-key ctx))
        (trans-func-name (ctx-trans-func-name ctx))
	(params (collect-abac-attributes route ctx)))
    (format t "main dispatch function called ~C~C" #\return #\linefeed) 
    (format t "request uri is ~A  ~C~C" (cdr (assoc "uri" params :test 'equal)) #\return #\linefeed)
    (when (and adapter rm route-key trans-func-name)
      (let* ((method-symbol (route-op->method-name route-key))
             (processxxxxrequestfunc (symbol-function method-symbol)))
	;; ABAC Enforcement Layer (PEP)
        (with-hhub-transaction trans-func-name params
	  ;; Business Domain Call
	  (let ((domain (funcall processxxxxrequestfunc adapter rm)))
	    (format t "i am inside with-hhub-transaction in the context flow dispatcher... Domain object is ~A ~C~C" domain #\return #\linefeed)
	    (setf (ctx-domain-object ctx) domain))))
      ;; set the adapter bo-knowledge to the ctx bo-knowledge
      (setf (ctx-bo-knowledge ctx) (bo-knowledge adapter))
      ;; Return the updated context to the around methods
      ctx)))

(defmethod dispatch :after ((ctx call-context) (route outbound-adapter-route) output-type)
  "Response creation - polymorphic on domain type
   中文：业务执行完后由 adapter 把 domain object 转成 ResponseModel（单/列表）。"
  (let ((adapter (ctx-adapter ctx))
        (domain (ctx-domain-object ctx)))
    (when (and adapter domain)
      ;; Polymorphic - dispatches on domain type
      (let ((response (create-response-from-domain adapter domain)))
        (setf (ctx-responsemodel ctx) response)))))

;; if we have a call context for create scenario,
;; then we just call the layer upto process response and there will be no presenter here.
(defmethod dispatch :around ((ctx call-context-create) (route outbound-adapter-route) output-type)
  ;; Create 路径：跑完 :before/primary/:after 即可，无需 view 渲染（多用于 API/重定向场景）。
  (format t "dispatch :around called for specializer call-context-create ~C~C" #\return #\linefeed)
  (call-next-method))

(defmethod dispatch :around ((ctx call-context) (route outbound-adapter-route) output-type)
  ;; 通用兜底 :around：只穿透到主管线，不做额外渲染。
  (format t "dispatch :around called ~C~C" #\return #\linefeed)
  ;; Run the primary + before/after methods first.
  (call-next-method))  ;; result = ctx after primary pipeline


(defmethod dispatch :around ((ctx call-context-read) (route outbound-adapter-route) output-type)
  ;; Read 路径：跑完主管线后用 presenter 生成 viewmodel，
  ;; make-view 选合适视图，render 输出 HTML/JSON。
  (format t "dispatch :around called for specializer call-context-read ~C~C" #\return #\linefeed)
  ;; Run the primary + before/after methods first.
  (call-next-method)  ;; result = ctx after primary pipeline
  ;; Now perform OUTBOUND work
  (let* ((presenter   (ctx-presenter ctx))
	 (view        (make-view route ctx output-type)) 
	 (response    (ctx-responsemodel ctx))
         (viewmodel   nil))
    ;; Build viewmodel using presenter (domain-agnostic)
    (when presenter
      (setf viewmodel (createviewmodel presenter response))
      (setf (ctx-viewmodel ctx ) viewmodel))
     ;; Now select proper rendering
    (render view viewmodel)))

;;; ---------------------------------------------------------------------------
;;; Specialized dispatch :around for READALL operations (list handling)
;;; ---------------------------------------------------------------------------
(defmethod dispatch :around ((ctx call-context-readall) (route outbound-adapter-route) output-type)
  ;; ReadAll 路径：CreateAllViewModel 把响应列表转 viewmodel 列表，
  ;; 优先调 RenderList，其次 RenderJSONAll，再次按行 render 累计结果。
  (format t "dispatch :around called for specializer call-context-readall ~C~C" #\return #\linefeed)
    ;; Run the primary + before/after methods first
  (call-next-method)  ;; result = ctx after primary pipeline
  ;; Now perform OUTBOUND work for LIST operations
  (let* ((presenter   (ctx-presenter ctx))
         (view        (make-view route ctx output-type))
         (response-list (ctx-responsemodel ctx))  ; This is a LIST of response models
         (viewmodel-list nil))
    ;; Build viewmodel LIST using presenter (domain-agnostic)
    (when (and presenter response-list)
      ;; Use CreateAllViewModel for list transformation
      (setf viewmodel-list (CreateAllViewModel presenter response-list))
      (setf (ctx-viewmodel ctx) viewmodel-list))
    ;; Now select proper LIST rendering
    (cond
      ;; If we have a list-specific render method, use it
      ((and viewmodel-list (fboundp 'RenderList))
       (RenderList view viewmodel-list))
      ;; Fallback: Some views might implement RenderJSONAll or similar
      ((and viewmodel-list 
            (typep view 'JSONView)
            (fboundp 'RenderJSONAll))
       (RenderJSONAll view viewmodel-list))
      ;; Default: iterate and render each item (less efficient but works)
      (viewmodel-list
       (let ((results '()))
         (dolist (vm viewmodel-list)
           (push (render view vm) results))
         ;; Return aggregated results (reverse to maintain order)
         (reverse results)))
      ;; No viewmodels - return empty result
      (t
       (render view nil)))))



;; View resolver from the route
(defun resolve-view-for (route output-type)
  "按 output-type（如 'json / 'html）从 route.view-classes alist 取对应 view 类符号。"
  (cdr (assoc output-type (view-classes route) :test 'equal)))



;;; ---------------------------------------------------------------------------
;;; Convenience entry: build ctx and dispatch
;;; ---------------------------------------------------------------------------
(defun make-call-context (route-key requestmodel-params trans-func-name 
                          &key 
                            (request-uri nil))


  "Create a call context with optional request metadata.
   If request metadata is not provided, attempts to get from Hunchentoot or uses defaults.
   中文：根据 route 的 crud-op 选择 call-context 的具体子类（read/create/...），
         若 route-key 含 'readall'/'list'/'filter' 之一且为 :readall 操作则升级到 call-context-readall。
         立即构造好 requestmodel/adapter/presenter 三大件，调用方拿到的是已 'wired up' 的 ctx。"
  (let* ((route  (find-outbound-route route-key))
         ;; Try to get from Hunchentoot if not provided, otherwise use defaults
         (final-uri (or request-uri
                        (handler-case (hunchentoot:request-uri*)
                          (error () "/default/context"))))
	 (crud-op (crud-op route))
	 (ctx-class (case crud-op
                      (:read 'call-context-read)
                      (:create 'call-context-create)
                      (:update 'call-context-update)
                      (:delete 'call-context-delete)
                      (otherwise 'call-context)))
	 ;; Special handling for :read with list semantics
         (ctx-class (if (and (eq crud-op :readall)
                            (or (search "readall" (string-downcase (symbol-name route-key)))
                                (search "list" (string-downcase (symbol-name route-key)))
                                (search "filter" (string-downcase (symbol-name route-key)))))
                       'call-context-readall
                       ctx-class))
	 (ctx    (make-instance ctx-class
                                :route-key route-key
                                :requestmodel-params requestmodel-params
                                :trans-func-name trans-func-name
                                :request-uri final-uri)))

    (format t "I have created a call context of type ~A ~C~C" ctx-class #\return #\linefeed)
    ;; Build RequestModel, Adapter, Service, Presenter immediately
    (setf (ctx-requestmodel ctx) (make-requestmodel route ctx))
    (setf (ctx-adapter ctx)      (make-adapter route ctx))
    (setf (ctx-presenter ctx)    (make-presenter route ctx))
    ctx))


(defun dispatch-route (route-key raw-params
                       &key
                       trans-func-name
                       output-type
                       request-uri)
  "Dispatch a route with optional request metadata for ABAC/auditing.

   中文：新风格控制器的统一入口。
       1) make-call-context 装 ctx；
       2) 取 route；output-type 默认取 view-classes 第一个的 key；
       3) (dispatch ctx route otype) —— 走完整 :before/primary/:after/:around 链。

   Parameters:
     route-key       - Route identifier (e.g., :warehouse/create)
     raw-params      - Request model parameters
     trans-func-name - Transaction function name for auditing
     output-type     - Output format (json, html, etc.)
     request-uri     - Optional request URI (auto-detected from Hunchentoot if nil)"

  (let* ((ctx (make-call-context route-key raw-params trans-func-name
                                 :request-uri request-uri))
         (route (find-outbound-route route-key))
         (otype (or output-type (caar (view-classes route)))))
    (format t "I am in dispatch-route function")
    (dispatch ctx route otype)))


    
;;; End of nst-bl-conflodis.lisp

;; 演示用：注册 customer/read 路由（按手机号读取客户档案）。
;; 真正的 customer 路由通常由 customer/nst-ui-Customer.lisp 注册；
;; 此处保留作为模板示例。
(register-outbound-route
  :customer/read
  :crud-op :read
  :description "Reads customer profile by phone"
  :requestmodel-class 'CustomerSearchRequestModel
  :businessobject-class 'Customer
  :adapter-class 'CustomerAdapter
  :presenter-class 'CustomerPresenter
  :view-classes  '((json . CustomerAddressJSONView))
  :tags '(customer api v1)
  :required-roles '(customer support)
  :feature-flags '(new-customer-domain)
  :audit-level :full)
 
