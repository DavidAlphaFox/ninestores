# Nine Stores 架构总结

> 本文基于仓库当前代码（master 分支）梳理 Nine Stores 平台的整体架构、模块划分、运行时与数据模型。
> 涉及目录：`hhub/`（Common Lisp 主应用）、`smsserver/` `webpushserver/` `fileserver/`（Node.js 辅助服务）、`site/`（Nginx + 静态资源）、`installation/`（建库与升级脚本）、`startup/`（SBCL 启动脚本）。

---

## 1. 平台定位

Nine Stores 是面向印度市场的 SaaS 电商 + 数字市场（Marketplace）平台：

- **多租户**：每个 `DOD_COMPANY` 是一个 tenant；几乎所有业务表都带 `TENANT_ID`。
- **B2B2C 角色**：
  - **System Admin / CAD**：平台运营方
  - **Vendor**：在租户下入驻的卖家
  - **Customer**：购买者
  - **Operator (OPR)**：超级管理员
- **业务范围**：商品/库存/订单/发货/订阅/钱包/支付（在线网关 + COD + UPI + 钱包）/GST 发票/Webpush 通知/SMS OTP/PWA。

技术栈：

| 层 | 技术 |
| --- | --- |
| 主应用 | SBCL + Hunchentoot（HTTP/HTTPS）+ CL-WHO（HTML 模板）+ CLSQL（ORM）+ Quicklisp |
| 辅助服务 | Node.js (Express) — SMS / Webpush / S3 文件代理 |
| 边缘 | Nginx（反向代理 + Let's Encrypt + 反代到 PM2 管理的 Node 服务和 Hunchentoot 集群） |
| 进程管理 | `/etc/init.d/hunchentoot`（SBCL）、`pm2`（Node 服务） |
| 数据库 | MySQL 8.0（CLSQL 通过 `:mysql` 直连） |
| 模板/UI | Bootstrap 5.3、jQuery、部分 Tailwind（v3 模板）、Parenscript（内联 JS） |
| 异步 | `cl-async`、`blackbird`，自研 Actor（`nst-actor`，见 `core/nst-bl-act.lisp`） |
| AI | Ollama 集成（`core/nst-bl-ollama.lisp`） |
| 远程开发 | Swank（SLIME），端口 4016，可热修运行实例 |

---

## 2. 物理部署拓扑

```
                    Internet
                       │
                       ▼
               ┌──────────────┐
               │    Nginx     │   site/nginx/ninestores.in
               │  (443 / 80)  │
               └──────┬───────┘
        ┌─────────────┼─────────────┬─────────────────┐
        ▼             ▼             ▼                 ▼
   /hhub/* →   /push/* →      /sms/* →           static (PWA)
   Hunchentoot Webpush Node   SMS Node           site/public/
   :4244, :3333  :4345         :4300
        │             │             │
        ▼             ▼             ▼
     MySQL        web-push      AWS SNS
     (CLSQL)      (VAPID)       (印度需 VI 注册 SenderID)

  独立服务：File Server (:4301) → AWS S3 (上传/删除商家与客户图片)
  Hunchentoot 内嵌：SBCL Swank :4016（远程 REPL）
                    shutdown listener :6200（用于优雅停机）
```

Nginx 关键转发（`site/nginx/ninestores.in`）：
- `if (!-f ...) { rewrite ^/(.*)$ /hhub/$1 last; }`：未命中静态文件即转交 Hunchentoot。
- `upstream hunchentoot` 默认就绪两台 `127.0.0.1:4244` / `:3333`，按 `$remote_addr` 做粘性哈希，方便横向扩展。

---

## 3. 仓库布局

```
ninestores/
├── hhub/                ← 主 Common Lisp 系统（ASDF 系统名 :nstores）
│   ├── nstores.asd      ← 模块装载顺序（DAL → BL → UI）
│   ├── package/         ← 包定义 + 编译辅助
│   ├── core/            ← 平台基础（ABAC、授权、模板、Actor、调度等）
│   ├── account/         ← Company/租户
│   ├── customer/        ← 客户主数据 & 自助门店
│   ├── vendor/          ← 卖家档案 / 网站设置 / 在线 REPL
│   ├── products/        ← 商品 + 类目 + GST HSN/SAC
│   ├── order/           ← 订单 + 订单明细 + 卖家订单
│   ├── invoice/         ← GST 发票头/明细 + PDF 模板
│   ├── shipping/        ← 运费/分区
│   ├── stock/           ← 库存（轻量）
│   ├── warehouse/       ← 仓库（包含较新的领域模型）
│   ├── subscription/    ← 周期订单
│   ├── paymentgateway/  ← 在线支付集成
│   ├── upi/             ← UPI 收款
│   ├── sysuser/         ← 平台用户/管理员
│   ├── webpushnotify/   ← 浏览器推送订阅记录
│   ├── email/templates/ ← HTML 邮件模板（注册、发票通知等）
│   └── test/            ← `hhub-tst-*` 单元/集成测试
├── smsserver/           ← Node.js Express，AWS SNS 短信
├── webpushserver/       ← Node.js Express，VAPID web-push
├── fileserver/          ← Node.js Express，AWS S3 文件代理
├── site/
│   ├── public/          ← 静态门户、PWA manifest、offline.html、tnc.html
│   └── nginx/           ← 站点级 Nginx 配置
├── installation/
│   ├── hhubplatform.sql ← 主 DDL（drop + create 全部 DOD_* 表）
│   ├── DOD_*.sql        ← 主数据 / 种子数据（HSN 4MB+、Auth Policy、Roles…）
│   ├── createseeddatasqlfiles.sh / deploysite.sh
│   ├── upgrades/        ← `nst-dbu-*` 增量升级脚本
│   ├── cronjobs.txt / dailyorderscron.txt
│   └── Design diagrams.vsdx
└── startup/
    ├── load.lisp        ← Quicklisp 装载依赖 → 加载 :nstores → (start-das)
    ├── init.lisp        ← Swank server + shutdown 端口 + 调用 load.lisp
    ├── nst-start.sh     ← 启动 PM2 + hunchentoot
    └── nst-stop.sh / hunchentoot / start-hunchentoot（detachtty 包装）
```

---

## 4. 命名约定与分层模式

`hhub/<module>/` 下的源文件遵循三层命名前缀：

| 前缀 | 角色 | 典型内容 |
| --- | --- | --- |
| `dod-dal-*` / `nst-dal-*` | **Data Access Layer (DAL)** | `clsql:def-view-class`，`:JOIN` 关联，表映射 |
| `dod-bl-*` / `nst-bl-*` | **Business Logic (BL)** | CRUD 方法、领域计算、跨表聚合 |
| `dod-ui-*` / `nst-ui-*` | **UI / Controller** | Hunchentoot 控制器函数（以 `dod-controller-…` 或 `com-hhub-transaction-…` 命名）+ CL-WHO 模板 |

> **`dod-` 与 `nst-` 的区别**：`dod-` 是更早期的代码（Door On Demand 时代留下的命名），`nst-` 是 Nine Stores 时代新增的代码。两者并存——较新的 `nst-bl-*` 文件中已经引入了基于 CLOS 的领域服务（`AdapterService`、`BusinessService`、`PresenterService`、`HTMLView` / `JSONView`），更接近六边形/Clean Architecture。

`hhub/nstores.asd` 严格按照 **packages → core → account → customer → email → invoice → order → paymentgateway → products → shipping → stock → subscription → sysuser → upi → vendor → warehouse → webpushnotify** 的顺序串行编译，保证 BL 可用 DAL，UI 可用 BL。

---

## 5. 运行时启动流程

`startup/load.lisp` → `(in-package :nstores)` → `(start-das)`：

`(start-das)` 在 `hhub/core/dod-ini-sys.lisp` 中定义，主要动作：

1. 创建 Hunchentoot easy-acceptor，端口 4244（`withssl=t` 时 9443，使用 `easy-ssl-acceptor`）。
2. 设置 access/message log 到 `~/hhublogs/`。
3. `crm-db-connect`：用 CLSQL 连接 MySQL（`hhubdb` / `hhubuser`）。
4. 预热缓存：
   - `*HHUBGLOBALLYCACHEDLISTSFUNCTIONS*`、`*NSTGSTSTATECODES-HT*`、`*NSTUOM-HT*`、`*NST-ALL-INDIA-PINCODES*`、`*HHUBSHIPPINGZONES*`。
   - 加载 HTML 模板（订单/发票/邮件/客户/产品/核心）到内存哈希表。
5. 初始化业务服务器：`(initbusinessserver)` 创建 `BusinessServer` 单例（见 `core/hhub-bl-ent.lisp`），管理 `BusinessContext` / `BusinessSession` / `BusinessObjectRepository`（DDD 风格）。
6. 启动两个 Actor（`core/nst-bl-act.lisp`）：
   - `*NSTSENDORDEREMAILACTOR*`：异步发送订单邮件
   - `*NSTAWSS3FILEUPLOADACTOR*`：异步把上传文件推到 S3
7. `make-otp-store` 初始化进程内 OTP 存储。

`(stop-das)` 反向：停止 SQL recording，`hunchentoot:stop`，关闭 actor，清空缓存。

`startup/init.lisp` 还会绑定 `127.0.0.1:6200` 用于优雅停机：`telnet localhost 6200` 即触发 `sb-ext:quit`。

---

## 6. 请求处理与权限：HHUB 事务模型

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

### 6.1 ABAC 角色对应

| ABAC 标准组件 | 对应实现 | 文件 |
| --- | --- | --- |
| **PEP**（Policy Enforcement Point，策略执行点） | 宏 `with-hhub-transaction` 等 | `core/dod-ui-utl.lisp` |
| **PDP**（Policy Decision Point，策略判定点） | 函数 `has-permission` / `has-permission1` | `core/dod-bl-bo.lisp` |
| **PIP**（Policy Information Point，属性信息点） | `com-hhub-attribute-*` 函数 + `DOD_AUTH_ATTR_LOOKUP` 表 | `core/dod-ui-attr.lisp` + `core/dod-bl-pol.lisp` |
| **PAP**（Policy Administration Point，策略管理点） | 超管/CAD 后台页面 + `dod-bl-pol.lisp` 持久化函数 | `core/dod-ui-pol.lisp`、`core/dod-bl-pol.lisp` |
| **策略本体** | `com-hhub-policy-*` 函数 | `core/dod-ui-pol.lisp` |

> 源码里 `has-permission` 的 docstring 写着 `:documentation "...the PEP..."`，这是注释笔误——它实际承担 PDP 角色（**被** PEP 宏调用）。

### 6.2 PEP：`with-hhub-transaction` 宏

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

### 6.3 PDP：`has-permission` 函数

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

### 6.4 策略本体：`com-hhub-policy-*`

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

### 6.5 PIP：`com-hhub-attribute-*` 与 `DOD_AUTH_ATTR_LOOKUP`

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

### 6.6 PAP：策略管理点

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

### 6.7 元模型表

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

### 6.8 缓存与热更新

PDP 性能依赖**启动时一次性加载**（`hhub-gen-globally-cached-lists-functions`，`core/dod-ini-sys.lisp:302`）：把 6 张 ABAC 表读进闭包，封装到 `*HHUBGLOBALLYCACHEDLISTSFUNCTIONS*` 列表里。每次 PEP/PDP 决策只走内存 HT（`policy-id → policy 实例`、`trans-func 名 → transaction 实例`），**不再查 DB**。

代价：**修改策略后必须重建缓存或重启 SBCL** 才能生效——

```lisp
(setf *HHUBGLOBALLYCACHEDLISTSFUNCTIONS*
      (hhub-gen-globally-cached-lists-functions))
```

### 6.9 一次完整请求的调用链

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

### 6.10 设计取舍小结

- **优点**：策略可以是任意复杂的 Lisp 代码（含跨表查询、配额比较、自定义异常），而非受限的策略 DSL。函数式签名 `(&optional params)` 让策略可以独立测试、被组合复用（参见 `com-hhub-policy-vendor-reject-action` 直接 `(com-hhub-policy-vendor-approve-action params)`）。
- **代价**：策略热更新需要 `(setf *HHUB...*)` 重建缓存；DB 与源码耦合（DB 中的 `POLICY_FUNC` 必须对应一个真实存在的 Lisp 函数）；`intern` 在调用频次极高的路径上会创建符号（命中 package 后是 O(1)）。
- **多租户隔离**：所有 ABAC 表都带 `TENANT_ID`，但默认共享系统级 `tenant_id=1` 的策略；当前缓存键并未按 tenant 隔离（`get-system-auth-policies` 写死 tenant 1），实际策略多租户化未完全展开。

### 6.11 ABAC 四角色全景

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

## 7. 较新的 Context Flow Dispatcher（六边形架构）

`core/nst-bl-conflodis.lisp` 引入了一套独立于旧 MVC 的 **DDD/Hexagonal** 调度管线，新模块（warehouse、customer 的 `nst-*Customer*`、order 的 `nst-*Order*` 等）按这个管线写：

```
call-context (request-uri, params, route-key, trans-func-name)
        │
        ▼
dispatch :before  → make-requestmodel / make-adapter
        │
        ▼
dispatch (primary)
   ├─ 查找 *NST-OUTBOUND-ROUTE-REGISTRY* 中的 outbound-adapter-route
   ├─ collect-abac-attributes (uri / company / subject-id / resource / action / client-ip)
   ├─ with-hhub-transaction <trans-func-name> params  ←— ABAC 检查
   ├─ funcall (process<op>request adapter requestmodel) → BusinessObject / list
   └─ ProcessResponse / ProcessResponseList → ResponseModel
        │
        ▼
dispatch :after  → 把 response 存入 ctx
        │
        ▼
dispatch :around (specialized on call-context-read / -readall / -create…)
   ├─ make-presenter
   ├─ presenter.CreateViewModel(s) → ViewModel(s)
   ├─ make-view (基于 bo-knowledge truth value: T/F/U/C 选 View 类，含 NIL/Unknown/Contradiction 容错视图)
   └─ render(view, viewmodel) → HTML / JSON
```

关键参与者（CLOS 类，`core/hhub-bl-ent.lisp` 与 `core/nst-bl-conflodis.lisp`）：

- `BusinessServer` → `BusinessContext` → `BusinessSession`（含 `VendorSessionObject` / `UserSessionObject`）→ `BusinessObjectRepository` → `BusinessObject`
- `RequestModel` / `ResponseModel` / `ViewModel`
- `AdapterService`（应用服务）/ `BusinessService`（领域服务）/ `DBAdapterService`（仓储）
- `PresenterService`（响应 → 视图模型）
- `View` 抽象类（`HTMLView`、`JSONView`）+ `RenderListViewHTML` / `RenderJSONAll`

这样新代码呈现出**两条并行风格**：

| 风格 | 代表文件 | 特征 |
| --- | --- | --- |
| 旧式过程 + 控制器 | `order/dod-ui-ord.lisp`、`order/dod-bl-ord.lisp`、`account/dod-ui-cmp.lisp` | `defun dod-controller-*` 直接 `clsql:select`、`cl-who:with-html-output` |
| 新式 DDD/Hexagonal | `customer/nst-{dal,bl,ui}-Customer.lisp`、`warehouse/dod-bl-wrh.lisp`、`order/nst-{dal,bl,ui}-Order.lisp` | `defclass <Entity><Adapter|Service|Presenter|View|RequestModel|ResponseModel|ViewModel>`，`with-mvc-ui-page` + `with-hhub-transaction` + 路由注册 |

---

## 8. 数据模型概览

主键风格：所有 `DOD_*` 表都是 `row_id mediumint AUTO_INCREMENT`，业务上常见 `TENANT_ID` + `DELETED_STATE`（软删）+ `ACTIVE_FLG` + `CREATED/UPDATED`。

主要分组（来自 `installation/hhubplatform.sql`，约 45 张表）：

| 分组 | 表 |
| --- | --- |
| 租户与人员 | `DOD_COMPANY`, `DOD_USERS`, `DOD_ROLES`, `DOD_USER_ROLES`, `DOD_PASSWORD_RESET`, `DOD_VEND_PROFILE`, `DOD_CUST_PROFILE`, `DOD_VENDOR_TENANTS` |
| 商品/库存 | `DOD_PRD_CATG`, `DOD_PRD_MASTER`, `DOD_PRODUCT_PRICING`, `DOD_PRD_STOCK`, `DOD_WAREHOUSE`, `DOD_STOCK`, `DOD_STOCK_MOVEMENT` |
| 订单 | `DOD_ORDER`, `DOD_ORDER_ITEMS`, `DOD_VENDOR_ORDERS`, `DOD_ORDER_TRACK`, `DOD_ORDER_ITEMS_TRACK`, `DOD_ORDER_SUBSCRIPTION`, `DOD_ORDER_SHIPMENT` |
| 发票/GST | `DOD_INVOICE_HEADER`, `DOD_INVOICE_ITEMS`, `DOD_GST_HSN_CODES`(70K+ 行), `DOD_GST_SAC_CODES`, `DOD_CURRENCY` |
| 物流与支付 | `DOD_VENDOR_SHIP_ZONES`, `DOD_SHIPPING_METHODS`, `DOD_VPAYMENT_METHODS`, `DOD_VPAYMENT_PROVIDERS`, `DOD_PAYMENT_TRANSACTION`, `DOD_UPI_PAYMENTS`, `DOD_CUST_WALLET` |
| 通知与会员体验 | `DOD_REVIEWS`, `DOD_WEBPUSH_NOTIFY`, `DOD_VENDOR_AVAILABILITY_DAY`, `DOD_VENDOR_APPOINTMENT` |
| ABAC | `DOD_BUS_OBJECT`, `DOD_ABAC_SUBJECT`, `DOD_BUS_TRANSACTION`, `DOD_AUTH_POLICY`, `DOD_AUTH_POLICY_ATTR`, `DOD_AUTH_ATTR_LOOKUP` |
| 多组织扩展（新） | `DOD_ORGANIZATIONS`, `DOD_ORG_RELATIONS`, `DOD_VENDOR_SETTINGS`, `DOD_SCHEMA_MIGRATIONS` |

`DOD_SCHEMA_MIGRATIONS` 与 `installation/upgrades/nst-dbu-*.lisp` 共同构成了**版本化 schema 升级**机制：每个 `nst-dbu-*` 文件按需对一个领域执行幂等升级（`pricingengine`、`gstupgrades`、`organizations`、`warehouse`、`custusers`、`custwallets`、`orderitem`、`vendorsettings`、`eventtrace`）。

---

## 9. 会话、登录与多角色

- 共四类登录入口（`core/dod-ini-sys.lisp` 的 `*HHUB*LOGINPAGEURL*` 常量）：客户、卖家、运营 (OPR)、CAD（Company Admin）。
- 默认密码 + 手机号短信 OTP 双因子。OTP 经 `core/nst-bl-otp.lisp` 中的 `*otp-store*`（一个闭包式 KV 存储）暂存，并通过 `smsserver` 走 AWS SNS。`*HHUBOTPTESTING* = T` 时短路。
- 登录态保存在 Hunchentoot session（cookie），并通过 `hhub-bl-ent.lisp` 的 `*HHUBBUSINESSSESSIONS-HT*` 在内存里持有 `VendorSessionObject` / `UserSessionObject`，缓存当前订单/产品函数列表。
- 限并发登录：`*HHUBMAXVENDORLOGINS* = 2`、`*HHUBMAXUSERLOGINS* = 2`。

---

## 10. 关键模块速览

### account / company
- `dod-dal-cmp.lisp` 定义 `dod-company`（关联 USERS、PROFILE 等）。
- `dod-bl-cmp.lisp` 提供 trial 公司创建、订阅升级、`*HHUBTRIALCOMPANYEXPIRYDAYS*` (90) 期限校验。

### customer
- 旧：`dod-{dal,bl,ui}-cus.lisp`（`dod-cust-profile`、客户钱包、地址）。
- 新：`nst-*Customer*.lisp` 走六边形管线，`CustomerAdapter`/`CustomerService`/`CustomerDBService`/`CustomerHTMLView`。
- 客户 PWA 自助门店：`nst-ui-cuswall.lisp`、`nst-ui-prodetpag.lisp`。

### vendor
- `dod-dal-ven.lisp` 含 `dod-vend-profile`（和 `dod-company` 通过 `dod-vendor-tenants` 多对多）。
- `nst-bl-vaisettings.lisp`、`nst-bl-vwebrepl.lisp`：卖家专属 Web REPL（运行时定制能力）。
- `dod-ui-ven.lisp`（148K，最大 UI 文件）承载卖家后台几乎所有页面。

### order
- `dod-dal-ord.lisp` `dod-vendor-orders`，`dod-dal-odt.lisp` `dod-order-items`，`dod-dal-otk.lisp` `dod-order-track`。
- `dod-bl-ord.lisp` 实现订单履约：`set-order-fulfilled` 多卖家时按 `dod-vendor-orders` 颗粒推进，全部 vendor 完成后主单标记 CMP，并扣减 `DOD_CUST_WALLET`（PRE 支付方式）。
- 新版面向对象：`nst-{dal,bl,ui}-Order.lisp` + `nst-{dal,bl,ui}-OrderItem.lisp`。

### invoice
- `nst-{dal,bl,ui}-ihd.lisp`（发票头）+ `*-itm.lisp`（发票行）。
- 7 个 GST 模板（A4/A5/80mm/经典）+ 多种状态模板（draft/paid/cancelled/refunded/payreminder/payoverduereminder/shipped/payment）。
- HSN/SAC 码内置（`installation/DOD_GST_HSN_CODES.sql` ~4MB）。

### shipping
- `dod-dal-osh.lisp` `dod-shipping-methods`、`dod-vendor-ship-zones`，支持 free / flat-rate / table-rate / pickup-in-store / 第三方（iThinkLogistics）。
- 印度全国 pincode 索引由 `core/nst-bl-pincodes.lisp` + `nst-dal-pincodes.lisp` 启动时载入 `*NST-ALL-INDIA-PINCODES*`。

### subscription
- `dod-dal-opf.lisp` `dod-order-subscription`：每周 SUN..SAT bitmask + start/end + WEEKLY/MONTHLY frequency。
- 由 cron `5 0 * * sun curl http://www.ninestores.in/hhub/rundailyordersbatch` 触发批处理生成订单。

### paymentgateway / upi
- `dod-dal-pay.lisp` `dod-payment-transaction` 记录所有网关回调。
- `dod-dal-upi.lisp` `dod-upi-payments` 处理 UPI 转账 UTR 提交、卖家确认。
- 在线网关返回 URL 集中在 `*PAYGATEWAYRETURNURL*` / `*PAYGATEWAYCANCELURL*` / `*PAYGATEWAYFAILUREURL*`。

### warehouse
- 仅次于 vendor 的最大子系统（`dod-bl-wrh.lisp` 45K，`dod-ui-wrh.lisp` 62K）；DAL 已经按新风格写。包含 `DOD_WAREHOUSE` / `DOD_STOCK` / `DOD_STOCK_MOVEMENT`。

### webpushnotify
- 表 `DOD_WEBPUSH_NOTIFY` 存订阅 endpoint/auth/publickey；推送实际由 Node `webpushserver` 通过 VAPID 触发。Lisp 侧负责生成/调用 `/push/notify/user` 并带 `auth-secret`。

### sysuser / cad / opr
- `dod-dal-sys.lisp` 定义 `dod-users`、`dod-roles`、`dod-user-roles`。
- CAD（Company Admin）页面在 `dod-ui-cad.lisp`；超级管理员页面在 `dod-ui-sys.lisp`（63K，所有 ABAC、Schema 迁移、运维入口）。

---

## 11. Node.js 辅助微服务

### `smsserver/index-v3.mjs`（端口 4300）
- `GET /sms/status` — 健康检查
- `GET /sms/sendsms?number=&message=` — 调用 AWS SNS Publish（`+91` 前缀；附带 `SenderID` / `TemplateId` / `EntityId`，配合印度 VI 的 DLT 注册）。
- 所有敏感参数走 `.env`：`AWS_REGION` / `SENDERID` / `TEMPLATEID` / `ENTITYID`。

### `webpushserver/index-v3.mjs`（端口 4345）
- VAPID（`web-push` 库）。`/push/notify/user` 受 `auth-secret` header 保护（默认 `highrisehub1234`）。
- `/subscribe` / `/unsubscribe` 提供给浏览器端，CORS `*`。
- 内存 subscribers 数组，单进程；持久化由 Lisp 侧 `DOD_WEBPUSH_NOTIFY` 完成。

### `fileserver/index-v3.mjs`（端口 4301）
- `GET /file/awss3v3/upload` / `DELETE /file/awss3v3/deletefiles`，按 `tenantid/{vnd|cust}/{id}/{OBJECT}/{objectid}/{uuid}` 路径写入 `process.env.AWS_S3_BUCKET`。
- 仅接受 objectname ∈ {`ord`, `prd`, `cfg`}；type ∈ {`vendor`, `customer`}。
- 本地缓存目录 `/data/www/public/img/`，与 Lisp Actor `*NSTAWSS3FILEUPLOADACTOR*` 协作完成「先落本地 → 异步推 S3」。

> 三个服务都通过 `pm2 start index-v3.mjs --name "..."` 由 `startup/nst-start.sh` 拉起。

---

## 12. 缓存、Actor 与并发

- **缓存**：`*HHUBGLOBALLYCACHEDLISTSFUNCTIONS*`、`*HHUBGLOBALBUSINESSFUNCTIONS-HT*`、模板哈希（`*NST-*-TEMPLATES*`），加上 `core/memoize.lisp` 提供的 `memoize` 装饰器。`*dod-database-caching*` 控制 CLSQL 自身的查询缓存（debug 模式下关闭）。
- **Actor 模型**：`core/nst-bl-act.lisp` 定义 `nst-actor`（`name`、`behavior` 函数、`stateful`、`state-clean-callback`、`initial-state`），用 `start-actor` / `destroy-actor` 启停。当前两个常驻 actor：邮件发送 + S3 上传。
- **OTP 闭包存储**：`make-otp-store` 返回带 `:put / :get / :clear` 协议的闭包，配合 `core/nst-bl-otp.lisp` 校验。
- **数据库重连**：登录页的 `nst-generic-login-with-password` 在遇到 CLSQL 2013 错误时会 `(stop-das)` + `(start-das)` 自我恢复并重定向重登。

---

## 13. 测试

`hhub/test/` 下 `hhub-tst-*.lisp` 覆盖：订单、客户、签到、文件上传、GST、SMS、UPI、卖家支付、Webpush、仓储等。  
`core/unit-tests.lisp` 是聚合脚本；`core/xref.lisp`（125K）是符号交叉引用辅助。  
未发现独立的 CI 配置 —— 测试依赖在 SBCL/SLIME 内手动运行。

---

## 14. 配置 / 私密信息

绝大多数运行常量集中在 `core/dod-ini-sys.lisp` 顶端的 `defvar`，包含：

- DB：`*crm-database-*`（默认 `hhubuser` / `Welcome$123`，**生产环境务必覆盖**）。
- 站点：`*siteurl*`、`*HHUBSUPPORTEMAIL*`、`*HHUBGUESTCUSTOMERPHONE*`。
- 资源路径：`*HHUB-EMAIL-TEMPLATES-FOLDER*`、`*HHUB-STATIC-FILES*`、`*NST-INVOICESETTINGS-*`。
- 业务参数：`*HHUBFREESHIPMINORDERAMT*`、`*HHUBMAXVENDORLOGINS*`、`*HHUBTRIALCOMPANYEXPIRYDAYS*`。
- 路径多以 `/home/ubuntu/ninestores/...` 硬编码——开发/部署目录必须保持一致，或在生产前显式覆盖。

Node 服务的密钥放各自 `.env`（`smsserver/.env.example` 是唯一签入示例）。

---

## 15. 演进观察

1. **代码风格双轨并行**：`dod-` 旧 MVC 与 `nst-` 新 DDD/Hexagonal 并存，长期会向后者收敛——新模块（warehouse、customer 新接口、order 新接口、invoice 新版）均已按新风格开发。
2. **Schema 也在演进**：`DOD_ORGANIZATIONS` / `DOD_ORG_RELATIONS` 是更通用的合作伙伴模型，为取代 `DOD_VEND_PROFILE` / `DOD_CUST_PROFILE` 做铺垫；`installation/upgrades/nst-dbu-organizations.lisp` 提供数据迁移。
3. **AI 接入**：`core/nst-bl-ollama.lisp` + `*NST-VENDOR-TABLES-FOR-AGENTIC-AI*`（启动时载入 vendor 相关表结构 txt），用 Ollama 跑 agent 协助卖家。
4. **跨租户 / 多卖家订单**是核心复杂度：`DOD_ORDER` 主单 + `DOD_VENDOR_ORDERS` 子单 + `DOD_ORDER_ITEMS` 行项，配合 `set-order-fulfilled` 三段式标记。
5. **运维约束**：硬编码路径、单 Lisp 进程、actor 内存态、Node 服务的内存订阅列表 → 横向扩展时需要外移到 Redis/RDS；Nginx 已经预设了多 Hunchentoot 节点的 upstream。
