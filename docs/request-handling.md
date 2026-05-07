# 请求处理与权限：HHUB 事务模型

> 拆分自 [`architecture.md`](architecture.md)。本文档描述 Nine Stores 老式 MVC 与新式六边形架构两套请求管线。

---

## 1. 老式管线：`with-hhub-transaction` + ABAC

Nine Stores **不**直接使用 `define-easy-handler`。HTTP 路由是通过 Hunchentoot 的默认派发表 + 形如 `dod-controller-*` / `com-hhub-transaction-*` 命名的处理函数完成；URL 与函数名通常一一对应（例如 `/hhub/listorders` → `dod-controller-list-orders`）。

每个受保护的处理函数都被一组 **会话 + ABAC 宏** 包裹：

```
hunchentoot 入站
   ↓
with-cust-session-check / with-vend-session-check / with-opr-session-check / with-cad-session-check
   ↓
dod-controller-... / com-hhub-transaction-...   ←— 控制器
   ↓
with-hhub-transaction "<trans-func-name>" params  ←— PEP（拦截）
   ↓
查表 dod-bus-transaction（缓存为 hash table）+ URI 前缀校验
   ↓
has-permission(transaction, params)              ←— PDP（决策）
   ↓
funcall <policy-func 符号> params                 ←— 策略求值
   │     按需读取属性
   ▼
com-hhub-attribute-*                              ←— PIP（属性）
   ↓ T?
业务逻辑 / 数据库操作 (BL → DAL)
   ↓
CL-WHO 模板渲染（HTML 或 JSON 字符串）
```

> ### ⚠️ 命名澄清：`with-hhub-transaction` ≠ 数据库事务
>
> 这里 "transaction" 是 **ABAC 术语里的"业务事务"** —— 指 `DOD_BUS_TRANSACTION` 表登记的"一个被策略保护的端点/操作"，元数据是 `{URI, Lisp 函数名, 关联策略 ID, 主体类型}`。宏名字读作：「在登记为 `<name>` 的**受保护端点**上下文里运行 body」。
>
> 宏展开式（`core/dod-ui-utl.lisp:846-878`）里**没有**任何 `clsql:start-transaction` / `commit` / `rollback` / `BEGIN` / `COMMIT`，纯粹是查元数据 → URI 校验 → 调 PDP → 通过执行 body / 拒绝则 redirect。和 Spring `@PreAuthorize`、Express auth middleware 同类。
>
> | | `with-hhub-transaction` | `clsql:with-transaction` |
> | --- | --- | --- |
> | 干什么 | ABAC PEP 鉴权 | SQL 事务（BEGIN / COMMIT） |
> | 出现频次 | 几乎每个受保护控制器都有，几百处 | 全仓库仅 1 处（`products/dod-bl-prd.lisp:386`，建商品 + 建定价同一事务）|
> | 失败行为 | redirect 到 `/hhub/permissiondenied` | `handler-case` 捕获后打印日志，**不向上抛** |
> | 影响层 | HTTP 入站 | DAL / BL 内部 |
>
> **顺带的真实薄弱点**：订单创建 `create-order-from-shopcart`（`order/dod-bl-ord.lisp:622`）涉及 INSERT 主单 + INSERT 多条行项 + INSERT 多条 `dod-vendor-orders` + UPDATE 库存 + UPDATE wallet —— 全是分散语句，**没有包在 `clsql:with-transaction` 里**。中途失败会留下脏数据。这不是 ABAC 那条 `with-hhub-transaction` 能解决的，需要在 BL 层显式补 SQL 事务。

### 1.1 ABAC 角色对应

| ABAC 标准组件 | 对应实现 | 文件 |
| --- | --- | --- |
| **PEP**（Policy Enforcement Point，策略执行点） | 宏 `with-hhub-transaction` 等 | `core/dod-ui-utl.lisp` |
| **PDP**（Policy Decision Point，策略判定点） | 函数 `has-permission` / `has-permission1` | `core/dod-bl-bo.lisp` |
| **PIP**（Policy Information Point，属性信息点） | `com-hhub-attribute-*` 函数 + `DOD_AUTH_ATTR_LOOKUP` 表 | `core/dod-ui-attr.lisp` + `core/dod-bl-pol.lisp` |
| **PAP**（Policy Administration Point，策略管理点） | 超管/CAD 后台页面 + `dod-bl-pol.lisp` 持久化函数 | `core/dod-ui-pol.lisp`、`core/dod-bl-pol.lisp` |
| **策略本体** | `com-hhub-policy-*` 函数 | `core/dod-ui-pol.lisp` |

> 源码里 `has-permission` 的 docstring 写着 `:documentation "...the PEP..."`，这是注释笔误——它实际承担 PDP 角色（**被** PEP 宏调用）。

### 1.2 PEP：`with-hhub-transaction` 宏

定义见 `core/dod-ui-utl.lisp:798-824`：

```lisp
(defmacro with-hhub-transaction (name &optional params &body body)
  `(let* ((transaction (get-ht-val ,name (hhub-get-cached-transactions-ht)))
          (transaction-uri (slot-value transaction 'uri))
          (uri (cdr (assoc "uri" params :test 'equal)))
          (urimatch-p (uri-prefix-boundary-p transaction-uri uri))
          (returnlist (has-permission transaction ,params))   ; ←— 调 PDP
          (returnvalue (nth 0 returnlist))
          (exceptionstr (nth 1 returnlist))
          (redirecturl (format nil "/hhub/permissiondenied?message=~A"
                               (hunchentoot:url-encode "Permission Denied"))))
     (unless transaction
       (error 'hhub-abac-transaction-error :errstring "..."))
     (if (and returnvalue urimatch-p)
         ,@body                                                ; ←— 放行业务
         (progn (logiamhere ...)                               ; ←— 拦截
                (lambda () (values redirecturl))))))
```

PEP 的职责：

1. **查事务**：以 `name`（事务函数名字符串）为 key，从内存 HT `*HHUBGLOBALLYCACHEDLISTSFUNCTIONS*` 第 7 槽位取出 `dod-bus-transaction` 实例。
2. **URI 边界校验**：`uri-prefix-boundary-p` 比对实际请求 URI 与登记 URI，防止策略被错挂到其他端点上。
3. **委托判定**：调用 `has-permission` 把决策交给 PDP。
4. **执行结果**：通过 → 跑 `,@body`；拒绝 → 重定向到 `/hhub/permissiondenied?message=...`。

附属 PEP 变体：
- `with-hhub-pep`（同文件 830 行）：XACML 风格四元组 `(subject, resource, action, env)` 入参，调 `has-permission1`。代码里使用很少，是早期实现。
- `with-cust-session-check` / `with-vend-session-check` / `with-opr-session-check` / `with-cad-session-check`：先做认证（`hunchentoot:*session*`），未登录直接 redirect。

### 1.3 PDP：`has-permission` 函数

定义见 `core/dod-bl-bo.lisp:177`：

```lisp
(defun has-permission (transaction &optional params)
  (let* ((policy-id (slot-value transaction 'auth-policy-id))
         (policy (get-ht-val policy-id (HHUB-GET-CACHED-AUTH-POLICIES-HT)))
         (policy-name (slot-value policy 'name))
         (policy-func (slot-value policy 'policy-func)))
    (handler-case
        (multiple-value-bind (returnvalues)
            (funcall (intern (string-upcase policy-func) :nstores) params)  ; ←— 反射调用
          (list returnvalues nil))
      (hhub-abac-transaction-error (condition)
        ;; 业务级"显式拒绝"：写日志，返回友好原因
        (with-open-file (stream *HHUBBUSINESSFUNCTIONSLOGFILE* ...)
          (format stream "~A: HHUB ABAC Transaction error - ~A. Error: ~A"
                  (mysql-now) policy-name (getExceptionStr condition)))
        (list nil "Nine Stores General Authorization Error..."))
      (error (c)
        ;; 兜底：任意异常都拒绝
        (list nil "Nine Stores General Authorization Error...")))))
```

关键设计：

- **DB 存的不是策略表达式，而是函数名字符串**。`(intern (string-upcase policy-func) :nstores)` 把字符串 → Lisp 符号 → `funcall`。"代码即策略"在这里更准确：策略代码写在源文件中，DB 只持有"用哪个函数"的引用。
- **返回值约定**：`(list 返回值 异常文本)`。PEP 只取第 0 位决定放行。
- **三段式异常处理**：
  - 策略返回 `T`：放行
  - 策略返回 `NIL`：默认拒绝（无原因）
  - 策略 `(error 'hhub-abac-transaction-error :errstring "...")`：业务可读的拒绝原因，写入 `*HHUBBUSINESSFUNCTIONSLOGFILE*`
  - 策略抛任意其他错误：兜底拒绝 + 日志 + backtrace

### 1.4 策略本体：`com-hhub-policy-*`

集中在 `core/dod-ui-pol.lisp`（37K，几百个函数），所有策略**统一签名** `(&optional (params nil))`。三种典型形式：

**a) 完全开放**：

```lisp
(defun com-hhub-policy-readall-warehouse (&optional (params nil)) T)
```

**b) 角色判断（RBAC 退化形式）**：

```lisp
(defun com-hhub-policy-search-gst-hsn-codes-action (&optional (params nil))
  (let ((rolename (cdr (assoc "rolename" params :test 'equal))))
    (equal rolename "SUPERADMIN")))
```

**c) 复合属性 + 业务事实（真正的 ABAC）**：

```lisp
(defun com-hhub-policy-vendor-add-product-action (&optional (params nil))
  (let* ((company   (cdr (assoc "company" params :test 'equal)))
         (vendor    (cdr (assoc "vendor"  params :test 'equal)))
         (mode      (cdr (assoc "mode"    params :test 'equal)))
         (subs-plan (subscription-plan company))
         (cmp-type  (cmp-type company))
         (currproductcount (length (select-products-by-vendor vendor company)))
         (maxproductcount  (com-hhub-attribute-vendor-maxproductcount subs-plan cmp-type))
         (suspend-flag (slot-value company 'suspend-flag)))
    (when (and (equal mode "add")
               (<= (- maxproductcount currproductcount) 0))
      (error 'hhub-abac-transaction-error
             :errstring (format nil "Account ~A: 商品数已达套餐上限 (Max=~d, Current=~d)"
                                (slot-value company 'name) maxproductcount currproductcount)))
    (when (com-hhub-attribute-company-issuspended suspend-flag)
      (error 'hhub-abac-transaction-error :errstring "Account Suspended"))
    T))
```

策略表达力包含：subject（`rolename`、`vendor`）、resource（`company`）、environment（订阅套餐、suspend 标志）、action（`mode=add`）、**实时业务事实**（当前商品数 vs 套餐配额）。

### 1.5 PIP：`com-hhub-attribute-*` 与 `DOD_AUTH_ATTR_LOOKUP`

属性函数住在 `core/dod-ui-attr.lisp`：

```lisp
(defun com-hhub-attribute-company-issuspended (suspend-flag)
  (equal suspend-flag "Y"))

(defun com-hhub-attribute-vendor-maxproductcount (subscription-plan cmp-type)
  (cond ((equal cmp-type "COMMUNITY") 50)
        ((equal subscription-plan "BASIC") 1000)
        ((equal subscription-plan "PROFESSIONAL") 3000)
        ((equal subscription-plan "TRIAL") 100)))

(defun com-hhub-attribute-role-name ()
  (slot-value (com-hhub-attribute-role-instance) 'name))
```

DB 表 `DOD_AUTH_ATTR_LOOKUP` 只存元数据：属性名、`ATTR_FUNC`（计算函数名）、`ATTR_TYPE`（subject/resource/action/context_based）、`ATTR_UNIQUE_FUNC`（枚举所有可能值，给 PAP 下拉框）。**实际取值靠 funcall 该函数符号**——和策略同一套机制。

`create-auth-attr-lookup`（`core/dod-bl-pol.lisp:79`）有个细节：管理员在 PAP 新增属性时，会把空函数体追加到 `dod-ui-attr.lisp`，提醒开发者补实现，相当于"DB → 代码骨架"的脚手架联动：

```lisp
(unless (symbolp attr-func)
  (print (format stream "(defun ~A ())" attr-func)))
```

### 1.6 PAP：策略管理点

PAP（Policy Administration Point，策略管理点）是策略的**立法机构**——管理员在这里创建/修改/停用/删除策略和属性元数据。Nine Stores 的 PAP 由超管后台 UI（`core/dod-ui-pol.lisp`）+ 持久化函数（`core/dod-bl-pol.lisp` / `core/dod-bl-bo.lisp`）共同组成：

| 操作 | 入口函数 | 文件 |
| --- | --- | --- |
| 创建策略 | `create-auth-policy` | `core/dod-bl-pol.lisp:181` |
| 创建属性 + 在源码追加函数骨架 | `create-auth-attr-lookup` | `core/dod-bl-pol.lisp:79` |
| 创建事务（URI ↔ 函数 ↔ 策略绑定） | `create-bus-transaction` | `core/dod-bl-bo.lisp:164` |
| 关联策略与属性 | `create-auth-policy-attr` | `core/dod-bl-pol.lisp:246` |
| 删除（软删 `DELETED_STATE='Y'`） | `delete-auth-policy` / `delete-auth-attr-lookup` / `delete-bus-transaction` | `core/dod-bl-pol.lisp` / `dod-bl-bo.lisp` |
| 恢复 | `restore-deleted-auth-policy` 等 | 同上 |
| 控制器/UI | `dod-controller-add-transaction-action`、`dod-controller-trans-to-policy-link-page`、`dod-controller-policy-search-action` | `core/dod-ui-pol.lisp` |

PAP 自身**也是受 PEP 保护的端点**：所有管理控制器外面套着 `with-opr-session-check`（仅超管），避免普通 vendor 给自己开后门。这形成了一个有趣的"自我递归"——修改策略的能力本身也是一条策略管的事。

`create-auth-attr-lookup` 里的"DB 写入 + 源码追加空函数"机制最能体现 Lisp"代码即数据"的味道：

```lisp
(defun create-auth-attr-lookup (name description attr-func attr-type company-instance)
  (let ((tenant-id (slot-value company-instance 'row-id))
        (filename "~/ninestores/hhub/core/dod-ui-attr.lisp"))
    (persist-auth-attr-lookup name description attr-func attr-type tenant-id)
    (with-open-file (stream filename :if-exists :append :direction :output)
      (unless (symbolp attr-func)
        (print (format stream "(defun ~A ())" attr-func)))
      (terpri stream))))
```

—— 管理员在 Web UI 登记新属性时，系统在 `dod-ui-attr.lisp` 末尾自动写入空 `defun`，提醒开发者去补 PIP 实现。这是 PAP → 源码的脚手架联动。

PAP 相对薄弱的地方：

- 策略表达式不能在 UI 里直接编辑——只能改 `POLICY_FUNC` 字段指向**已存在的 Lisp 函数名**。真正的策略逻辑修改还是要走代码提交 + 重启缓存。
- 没有版本化、审批流、回滚机制；策略变更直接落表。
- 多租户隔离不彻底：`get-system-auth-policies` 写死 `tenant_id=1`（系统级），租户级策略表其实没用起来。

### 1.7 元模型表

| 表 | 含义 |
| --- | --- |
| `DOD_BUS_OBJECT` | 业务对象（资源）类型登记 |
| `DOD_ABAC_SUBJECT` | 主体类型（vendor / customer / cad / opr…） |
| `DOD_BUS_TRANSACTION` | URI + Lisp 函数名（`TRANS_FUNC`） + 关联策略 ID + 主体 ID |
| `DOD_AUTH_POLICY` | 策略实体（`POLICY_FUNC` 字段保存策略**函数名字符串**） |
| `DOD_AUTH_POLICY_ATTR` | 策略所引用的属性 + 占位值（用于 PAP UI 与文档化） |
| `DOD_AUTH_ATTR_LOOKUP` | 属性的取值函数 `ATTR_FUNC` 和枚举函数 `ATTR_UNIQUE_FUNC` |

前缀约定（`core/dod-ini-sys.lisp`）：

- `*ABAC-TRANSACTION-NAME-PREFIX*` = `"com.hhub.transaction."`
- `*ABAC-POLICY-NAME-PREFIX*`      = `"com.hhub.policy."`
- `*ABAC-ATTRIBUTE-NAME-PREFIX*`   = `"com.hhub.attribute."`
- 函数前缀对应 `com-hhub-transaction-` / `com-hhub-policy-` / `com-hhub-attribute-`

### 1.8 缓存与热更新

PDP 性能依赖**启动时一次性加载**（`hhub-gen-globally-cached-lists-functions`，`core/dod-ini-sys.lisp:302`）：把 6 张 ABAC 表读进闭包，封装到 `*HHUBGLOBALLYCACHEDLISTSFUNCTIONS*` 列表里。每次 PEP/PDP 决策只走内存 HT（`policy-id → policy 实例`、`trans-func 名 → transaction 实例`），**不再查 DB**。

代价：**修改策略后必须重建缓存或重启 SBCL** 才能生效——

```lisp
(setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*
      (hhub-gen-globally-cached-lists-functions))
```

### 1.9 一次完整请求的调用链

```
HTTP /hhub/addproduct
    │  params = (("uri" . "/hhub/addproduct")
    │            ("rolename" . "COMPADMIN")
    │            ("company"  . #<dod-company>)
    │            ("vendor"   . #<dod-vend-profile>)
    │            ("mode"     . "add"))
    ▼
com-hhub-transaction-vendor-add-product-action            ← 控制器（同名）
    │
    ▼
with-vend-session-check                                    ← 认证
    │
    ▼
with-hhub-transaction "com-hhub-transaction-..."           ← PEP
    │  ① cached-transactions-ht 取 transaction
    │  ② uri-prefix-boundary-p 校验 URI
    ▼
has-permission(transaction, params)                        ← PDP 入口
    │  ③ cached-auth-policies-ht 取 policy
    │  ④ (intern "com-hhub-policy-vendor-add-product-action" :nstores)
    ▼
funcall com-hhub-policy-vendor-add-product-action params   ← 策略求值
    │
    │  按需调 PIP / DAL：
    │     com-hhub-attribute-vendor-maxproductcount
    │     com-hhub-attribute-company-issuspended
    │     select-products-by-vendor (DAL 层)
    ▼
T  /  NIL  /  signal hhub-abac-transaction-error
    │
    ▼
PEP 拿到 (T   nil)        → 执行业务体（创建商品 + 渲染页面）
       拿到 (NIL "原因")   → 跳 /hhub/permissiondenied?message=...
```

### 1.10 设计取舍小结

- **优点**：策略可以是任意复杂的 Lisp 代码（含跨表查询、配额比较、自定义异常），而非受限的策略 DSL。函数式签名 `(&optional params)` 让策略可以独立测试、被组合复用（参见 `com-hhub-policy-vendor-reject-action` 直接 `(com-hhub-policy-vendor-approve-action params)`）。
- **代价**：策略热更新需要 `(setf *HHUB...*)` 重建缓存；DB 与源码耦合（DB 中的 `POLICY_FUNC` 必须对应一个真实存在的 Lisp 函数）；`intern` 在调用频次极高的路径上会创建符号（命中 package 后是 O(1)）。
- **多租户隔离**：所有 ABAC 表都带 `TENANT_ID`，但默认共享系统级 `tenant_id=1` 的策略；当前缓存键并未按 tenant 隔离（`get-system-auth-policies` 写死 tenant 1），实际策略多租户化未完全展开。

### 1.11 ABAC 四角色全景

ABAC 标准把鉴权拆成 **四个职责互不重叠的组件**，直观比喻：

| ABAC 组件 | 一句话 | 比喻 |
| --- | --- | --- |
| **PEP** Policy Enforcement Point | 拦下每一次请求并执行决策 | 门卫 |
| **PDP** Policy Decision Point | 依据策略做"允许/拒绝"判定 | 法官 |
| **PIP** Policy Information Point | 在判定时提供事实数据 | 证据柜 |
| **PAP** Policy Administration Point | 管理策略本身（创建/修改/停用） | 议会 |

完整运行时拓扑：

```
       ┌──────────────────────┐
       │  管理员（OPR / CAD） │
       └──────────┬───────────┘
                  │ 立法（CRUD 策略 + 属性 + 事务）
                  ▼
       ┌──────────────────────┐    ┌──────────────────────────┐
       │         PAP          │───▶│  策略库（MySQL）         │
       │  超管 UI / API +     │    │  DOD_AUTH_POLICY         │
       │  dod-bl-pol.lisp     │    │  DOD_BUS_TRANSACTION     │
       │  自动追加函数骨架    │    │  DOD_AUTH_ATTR_LOOKUP    │
       │  到 dod-ui-attr.lisp │    │  DOD_AUTH_POLICY_ATTR    │
       └──────────────────────┘    │  DOD_BUS_OBJECT          │
                                   │  DOD_ABAC_SUBJECT        │
                                   └────────────┬─────────────┘
                                                │ start-das 时
                                                │ hhub-gen-globally-cached-lists-functions
                                                ▼
       ┌──────────────────────┐    ┌──────────────────────────┐
       │  用户（C/V/CAD/OPR） │    │  *HHUBGLOBALLYCACHED     │
       └──────────┬───────────┘    │     LISTSFUNCTIONS*      │
                  │ HTTP 请求      │  policies-ht / trans-ht  │
                  ▼                └─────────────┬────────────┘
       ┌──────────────────────┐                  │
       │         PEP          │  ① 取 transaction │
       │ with-hhub-transaction│ ─────────────────┤
       │  (会话校验已通过)    │                  │
       └──────────┬───────────┘                  │
                  │ has-permission(transaction)  │
                  ▼                              │
       ┌──────────────────────┐  ② 取 policy     │
       │         PDP          │ ─────────────────┤
       │   has-permission     │                  │
       │   (intern + funcall) │                  ▼
       └──────────┬───────────┘    ┌──────────────────────────┐
                  │  funcall       │  策略代码（源码）        │
                  └───────────────▶│  com-hhub-policy-*       │
                                   │  在 dod-ui-pol.lisp      │
                                   └────────┬─────────┬───────┘
                                            │ 按需调  │ 按需调
                                            ▼          ▼
                          ┌──────────────────────┐  ┌──────────┐
                          │         PIP          │  │  DAL     │
                          │ com-hhub-attribute-* │  │  CLSQL   │
                          │ dod-ui-attr.lisp     │  │  查询    │
                          │ + 远程调用/纯函数    │  │  现货数据│
                          └──────────────────────┘  └──────────┘
```

**关键观察**：

- PEP / PDP / PIP **运行在请求路径上**（每次都执行）；PAP **运行在管理路径上**（管理员触发，落到 DB）。
- PIP 在 Nine Stores 里既可以是纯函数（`com-hhub-attribute-vendor-maxproductcount` 基于参数 cond），也可以触发数据库查询（`com-hhub-attribute-role-name` → SQL）。**只要是 Lisp 函数，PDP 都能 funcall**——这是 Lisp 实现 ABAC 的核心便利。
- PAP 不是单独的服务，而是"超管后台 UI + 一组 BL 函数"的虚拟角色。它本身受 PEP 保护，因此**修改策略的能力本身也是一条策略管的事**——形成自我递归。

---

## 2. 较新的 Context Flow Dispatcher（六边形架构）

`core/nst-bl-conflodis.lisp`（30K）引入了一套独立于旧 MVC 的 **DDD/Hexagonal** 调度管线，新模块（warehouse、customer 的 `nst-*Customer*`、order 的 `nst-*Order*` 等）按这个管线写。

**重点**：新管线**没有重写鉴权** —— 它只是把"如何收集 ABAC 属性、如何调用 PEP 宏"自动化了。最终落点仍是 §1 的 `with-hhub-transaction` → `has-permission` → 策略函数。

### 2.1 三个核心数据结构

#### `outbound-adapter-route`（路由元数据）

定义见 `nst-bl-conflodis.lisp:87-239`。每条业务路由是一条 `outbound-adapter-route` 实例，按 `route-key`（keyword，例如 `:customer/read`）注册到全局哈希表 `*NST-OUTBOUND-ROUTE-REGISTRY*`。8 大类字段：

```lisp
(defclass outbound-adapter-route ()
  ;; 1. 标识
  (route-key                        ; e.g. :customer/read
   description
   ;; 2. 类绑定（六边形角色）
   businessobject-class             ; 'Customer
   requestmodel-class               ; 'CustomerSearchRequestModel
   adapter-class                    ; 'CustomerAdapter
   presenter-class                  ; 'CustomerPresenter
   view-classes                     ; '((json . CustomerAddressJSONView) (html . ...))
   ;; 3. 操作
   crud-op                          ; :create :read :update :delete :list
   operation                        ; :approve :cancel :checkout（非 CRUD）
   ;; 4. 状态 / 灰度
   active feature-flags
   ;; 5. ★ 安全 / ACL
   required-roles                   ; '(admin vendor support) —— 当前装饰性，dispatch 未读取
   permission-checker               ; (lambda (route ctx user) -> T/NIL) —— 同上
   ;; 6. 多租户
   tenant-overrides                 ; ((tenantA . (:default-outbound-adapters (json))) ...)
   ;; 7. 生命周期钩子
   before-dispatch-hook after-dispatch-hook
   ;; 8. 审计
   audit-level tags version metadata))
```

注册一条路由（见 `nst-bl-conflodis.lisp:670-682` 的样例 + `core/hhub-ui-egn.lisp` 的骨架）：

```lisp
(register-outbound-route
  :customer/read
  :crud-op :read
  :requestmodel-class 'CustomerSearchRequestModel
  :businessobject-class 'Customer
  :adapter-class 'CustomerAdapter
  :presenter-class 'CustomerPresenter
  :view-classes '((json . CustomerAddressJSONView))
  :required-roles '(customer support)
  :tags '(customer api v1)
  :audit-level :full)
```

`crud-op` 未传时按 `route-key` 字符串后缀（`/read /create /update /delete`）自动推断。

#### `call-context`（贯穿管线的"工作台"对象）

```lisp
(defclass call-context ()
  (route-key requestmodel-params request-uri trans-func-name      ; 输入
   requestmodel adapter                                           ; :before 填
   domain-object                                                  ; primary 填
   responsemodel                                                  ; :after 填
   presenter viewmodel view output-type bo-knowledge              ; :around 填
   company context))
```

5 个 CRUD 子类专门用于 `:around` 方法的 CLOS 派发：`call-context-create`、`-read`、`-readall`、`-update`、`-delete`。`make-call-context` 按 `crud-op` 选择具体子类，并立即构造好 requestmodel + adapter + presenter（"wired up"）。

#### `*NST-OUTBOUND-ROUTE-REGISTRY*`

`route-key → outbound-adapter-route` 的进程内哈希表。`(register-outbound-route ...)` 写入；`(find-outbound-route key)` 读取。

### 2.2 入口：`dispatch-route`

新风格控制器只写一行（实际生产代码 `customer/dod-ui-cus.lisp:85`）：

```lisp
(dispatch-route :customer/read
                (list :phone phone :company (get-login-customer-company))
                :trans-func-name "com-hhub-transaction-customer-address"
                :request-uri (hunchentoot:request-uri*)
                :output-type 'json)
```

`dispatch-route` 内部：

```lisp
(defun dispatch-route (route-key raw-params &key trans-func-name output-type request-uri)
  (let* ((ctx   (make-call-context route-key raw-params trans-func-name :request-uri ...))
         (route (find-outbound-route route-key))
         (otype (or output-type (caar (view-classes route)))))
    (dispatch ctx route otype)))
```

### 2.3 主管线：CLOS 方法组合子

`dispatch` 是 generic function，用 4 类方法组合子拆成 4 个钩子（`nst-bl-conflodis.lisp:458-580`）：

```lisp
(defmethod dispatch :before ((ctx call-context) (route ...) output-type)
  ;; 前置：sanity check + 构造 requestmodel/adapter
  (unless (find-outbound-route (ctx-route-key ctx)) (error ...))
  (setf (ctx-requestmodel ctx) (make-requestmodel route ctx))
  (setf (ctx-company ctx) (slot-value (ctx-requestmodel ctx) 'company))
  (setf (ctx-adapter ctx) (make-adapter route ctx)))

(defmethod dispatch ((ctx call-context) (route ...) output-type)            ; ★ 主方法
  (let* ((adapter         (ctx-adapter ctx))
         (rm              (ctx-requestmodel ctx))
         (route-key       (ctx-route-key ctx))
         (trans-func-name (ctx-trans-func-name ctx))
         (params          (collect-abac-attributes route ctx)))
    (when (and adapter rm route-key trans-func-name)
      (let* ((method-symbol (route-op->method-name route-key))    ; :customer/read → 'PROCESSREADREQUEST
             (process-fn    (symbol-function method-symbol)))
        ;;━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        ;; ★★★  ABAC ENFORCEMENT LAYER (PEP)  ★★★
        ;;━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        (with-hhub-transaction trans-func-name params
          ;; ↓ 通过 PEP 才进入这里：业务领域调用
          (let ((domain (funcall process-fn adapter rm)))
            (setf (ctx-domain-object ctx) domain))))
      (setf (ctx-bo-knowledge ctx) (bo-knowledge adapter)))))

(defmethod dispatch :after ((ctx call-context) (route ...) output-type)
  ;; 后置：domain → ResponseModel（多态：单实体 vs 列表）
  (let ((response (create-response-from-domain (ctx-adapter ctx) (ctx-domain-object ctx))))
    (setf (ctx-responsemodel ctx) response)))

;; :around 按 CRUD 子类派发（不同操作走不同输出阶段）
(defmethod dispatch :around ((ctx call-context-read)    ...) ...)   ; presenter→viewmodel→view→render
(defmethod dispatch :around ((ctx call-context-readall) ...) ...)   ; CreateAllViewModel + RenderList
(defmethod dispatch :around ((ctx call-context-create)  ...) ...)   ; 通常无视图，直接跑主管线
```

CLOS 方法执行顺序：`:around` → `:before` → primary → `:after` → 回到 `:around`。`:around` 是真正的总指挥 —— 先 `(call-next-method)` 跑完 before/primary/after，再决定怎么渲染输出。

### 2.4 ABAC 集成点：`collect-abac-attributes`

这是 Dispatcher 与 ABAC 内核的接缝（`nst-bl-conflodis.lisp:322-347`）：

```lisp
(defmethod collect-abac-attributes ((route outbound-adapter-route) (ctx call-context))
  (let ((params nil))
    (setf params (acons "uri"        (ctx-request-uri ctx) params))
    (setf params (acons "company"    (ctx-company ctx)     params))   ; from requestmodel
    (setf params (acons "subject-id" (slot-value (ctx-context ctx) 'user-id) params))
    (setf params (acons "resource"   (symbol-name (ctx-route-key ctx)) params))   ; ":CUSTOMER/READ"
    (setf params (acons "action"     (symbol-name (crud-op route))    params))   ; ":READ"
    (setf params (acons "client-ip"  (hunchentoot:remote-addr*)       params))
    params))
```

与老式管线的关键差别：

| | 老式控制器 | 新式 Dispatcher |
| --- | --- | --- |
| ABAC params 构造 | 手工 `(acons "uri" ... (acons "company" ...))` | 自动从 ctx 抽取 |
| 调 `with-hhub-transaction` | 控制器自己写 | 主 dispatch 方法替你写 |
| `trans-func-name` 来源 | 控制器函数同名 | `dispatch-route` 显式传入 |
| 资源/动作 | 隐含在 trans-name 里 | 显式 `resource` + `action`，按 `route-key` + `crud-op` 派发 |

策略函数那边可以直接 `(cdr (assoc "resource" params))` 拿到 `":CUSTOMER/READ"`，写出更通用的策略（例如"对所有 `:read` 操作只看角色"）。

### 2.5 反射调用领域逻辑：`route-op->method-name`

```lisp
(defun route-op->method-name (route-key)
  ;; :customer/read → "processreadrequest" → 'PROCESSREADREQUEST
  (let* ((name (string route-key))
         (op   (subseq name (1+ (position #\/ name)))))
    (intern (string-upcase (format nil "process~arequest" op)) :nstores)))
```

PEP 通过后，反射 `(funcall #'processreadrequest adapter requestmodel)`。业务方在 `CustomerAdapter` 上实现 `ProcessReadRequest` 方法即可，**控制器和 dispatcher 都不用改**。

### 2.6 容错视图：`bo-knowledge` 4 值真值

```lisp
(defmethod make-view ((route ...) (ctx ...) output-type)
  (let* ((truth (bo-knowledge-truth (ctx-bo-knowledge ctx)))
         (view-class (case truth
                       (:T (resolve-view-for route output-type))   ; 正常
                       (:F 'ViewNIL)                                ; 找不到
                       (:U 'ViewUnknown)                            ; 不可知
                       (:C 'ViewContradiction))))                   ; 数据冲突
    (make-instance (find-class view-class))))
```

借用 4 值真值逻辑（True / False / Unknown / Contradiction）做"领域结果不确定"的统一处理 —— 每种情况配一个专用容错视图，避免每个 view 都自己处理 NIL。

### 2.7 关键参与者（六边形角色）

CLOS 类，定义在 `core/hhub-bl-ent.lisp` 与 `core/nst-bl-conflodis.lisp`：

- `BusinessServer` → `BusinessContext` → `BusinessSession`（含 `VendorSessionObject` / `UserSessionObject`）→ `BusinessObjectRepository` → `BusinessObject`
- `RequestModel` / `ResponseModel` / `ViewModel`
- `AdapterService`（应用服务）/ `BusinessService`（领域服务）/ `DBAdapterService`（仓储）
- `PresenterService`（响应 → 视图模型）
- `View` 抽象类（`HTMLView`、`JSONView`）+ `RenderListViewHTML` / `RenderJSONAll`

### 2.8 完整调用链举例（`/hhub/dodcustaddrjsonsearch/9812345678`）

```
HTTP GET /hhub/dodcustaddrjsonsearch/9812345678
          │
          ▼
hunchentoot 路由 → dod-controller-cust-address-json-search
          │
          ▼
with-cust-session-check                                       ← 客户登录态校验（不是 ABAC）
          │
          ▼
dispatch-route :customer/read                                 ← 新管线入口
   (list :phone phone :company company)
   :trans-func-name "com-hhub-transaction-customer-address"
   :output-type 'json
          │
          ▼
make-call-context → call-context-read 实例
          │
          ▼
dispatch :around (call-context-read)
   ├─ call-next-method
   │     ├─ dispatch :before    → 已在 make-call-context 里完成
   │     ├─ dispatch (primary):
   │     │     collect-abac-attributes → params
   │     │     ┌─────────────────────────────────────┐
   │     │     │ with-hhub-transaction (PEP)         │
   │     │     │   ↓                                  │
   │     │     │ has-permission(transaction params)  │ ← PDP（与老管线共用）
   │     │     │   ↓                                  │
   │     │     │ funcall com-hhub-policy-customer-   │
   │     │     │         address (params)            │ ← 策略函数
   │     │     │   ↓ (按需调 com-hhub-attribute-* PIP)│
   │     │     │   T → funcall (PROCESSREADREQUEST   │ ← 反射调领域逻辑
   │     │     │                CustomerAdapter rm)  │
   │     │     │   ctx.domain-object = <Customer>    │
   │     │     └─────────────────────────────────────┘
   │     └─ dispatch :after:
   │           CreateResponse(adapter, customer) → ResponseModel
   │
   ├─ make-view route ctx 'json   → CustomerAddressJSONView 实例
   ├─ CreateViewModel presenter response → ViewModel
   └─ render view viewmodel               → JSON 字符串
                ▼
       Hunchentoot 返回 200 + JSON
```

### 2.9 设计观察

1. **新旧管线共用同一 PEP**。`with-hhub-transaction` 是 ABAC 唯一入口；新 Dispatcher 只是自动化属性收集与宏调用。
2. **`required-roles` / `permission-checker` 字段当前装饰性**。`outbound-adapter-route` 类上声明了它们，但 `dispatch` 没读 —— 真正判定还是走 `with-hhub-transaction` + `DOD_BUS_TRANSACTION` 注册的 `trans-func-name`。这两个字段大概率是预留给未来的简化路径（declarative ACL）。
3. **`resource` / `action` 是新管线的红利**。老控制器只往 params 塞 `uri/rolename/company/vendor`；新管线显式传 `route-key`（资源类型）和 `crud-op`（动作），让策略可以横向写"对所有 `:read` 类操作放行"这样的通用规则。
4. **`:around` 把渲染外置**。老控制器手写 `(cl-who:with-html-output ...)`；新管线把视图选择和渲染留给 `dispatch :around`，业务方只关心"领域逻辑 → ResponseModel"。
5. **`bo-knowledge` 4 值真值**比一般六边形管线更高阶 —— 把"找不到/不可知/冲突"作为头等公民。
6. **`tenant-overrides` 也是预留**。和 `get-system-auth-policies` 写死 `tenant_id=1` 一样，新管线也未真正按 tenant 派发；多租户 ABAC 仍未完全展开。

### 2.10 两条风格并存

| 风格 | 代表文件 | 特征 |
| --- | --- | --- |
| 旧式过程 + 控制器 | `order/dod-ui-ord.lisp`、`order/dod-bl-ord.lisp`、`account/dod-ui-cmp.lisp` | `defun dod-controller-*` 直接 `clsql:select`、`cl-who:with-html-output`；控制器手写 `with-hhub-transaction` |
| 新式 DDD/Hexagonal | `customer/nst-{dal,bl,ui}-Customer.lisp`、`warehouse/dod-bl-wrh.lisp`、`order/nst-{dal,bl,ui}-Order.lisp` | `defclass <Entity><Adapter\|Service\|Presenter\|View\|RequestModel\|ResponseModel\|ViewModel>`，`register-outbound-route` + `dispatch-route` |

### 2.11 想动手验证

| 关注点 | 起点 |
| --- | --- |
| PEP 宏 | `hhub/core/dod-ui-utl.lisp:798-824` |
| PDP 函数 | `hhub/core/dod-bl-bo.lisp:177` |
| 新管线主分发 | `hhub/core/nst-bl-conflodis.lisp:475-498` |
| ABAC 属性收集 | `hhub/core/nst-bl-conflodis.lisp:322-347` |
| 路由注册结构 | `hhub/core/nst-bl-conflodis.lisp:87-239` |
| 注册骨架样例 | `hhub/core/hhub-ui-egn.lisp:24-90` |
| 生产调用样例 | `hhub/customer/dod-ui-cus.lisp:85` |
| 样例策略函数 | `hhub/core/dod-ui-pol.lisp` 搜 `com-hhub-policy-vendor-add-product-action` |

---

[← 返回架构总览](architecture.md)
