# Nine Stores 架构总结

> 本文基于仓库当前代码（master 分支）梳理 Nine Stores 平台的整体架构、模块划分、运行时与数据模型。
> 涉及目录：`hhub/`（Common Lisp 主应用）、`smsserver/` `webpushserver/` `fileserver/`（Node.js 辅助服务）、`site/`（Nginx + 静态资源）、`installation/`（建库与升级脚本）、`startup/`（SBCL 启动脚本）。
>
> **本文档为总览。深入主题已拆分到独立文件，见 [§6 文档导航](#6-文档导航)。**

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

## 6. 文档导航

详细主题已按业务/技术领域拆分到独立文件，按需阅读：

| 文档 | 内容 |
| --- | --- |
| [request-handling.md](request-handling.md) | 请求处理与权限：`with-hhub-transaction` 老式 ABAC 管线（PEP/PDP/PIP/PAP）+ 新式 Context Flow Dispatcher（六边形 DDD） |
| [data-model.md](data-model.md) | 数据模型分组（约 45 张 `DOD_*` 表）+ `vendor` 新旧语义双轨共存（`DOD_VEND_PROFILE` ↔ `DOD_ORG_RELATIONS` 桥接 + Strangler Fig 演进） |
| [modules.md](modules.md) | 会话、登录、多角色登陆入口；按 account/customer/vendor/order/invoice/shipping/subscription/paymentgateway/warehouse/webpushnotify/sysuser 速览各模块文件入口 |
| [order-flow.md](order-flow.md) | 客户下单与履约端到端流程：购物车提交 → ABAC → PRE 钱包校验 → 主单/子单/行项落盘 → 卖家通知 → `set-order-fulfilled` 履约 → OPY/PRE/UPI 三种支付分支 |
| [returns-and-refunds.md](returns-and-refunds.md) | 退货 / 部分退货 / 换货 / 退款能力盘点 —— 现状评估（基本未实现）、schema 已留占位、补齐这些能力需要触动的层与文件 |
| [infrastructure.md](infrastructure.md) | Node.js 辅助微服务（`smsserver`/`webpushserver`/`fileserver`）、缓存与 Actor 并发、测试约定、配置与机密管理 |
| [comment-style.md](comment-style.md) | 源码注释风格指南（已有） |

---

## 7. 演进观察

1. **代码风格双轨并行**：`dod-` 旧 MVC 与 `nst-` 新 DDD/Hexagonal 并存，长期会向后者收敛——新模块（warehouse、customer 新接口、order 新接口、invoice 新版）均已按新风格开发。
2. **Schema 也在演进**：`DOD_ORGANIZATIONS` / `DOD_ORG_RELATIONS` 是更通用的合作伙伴模型，为取代 `DOD_VEND_PROFILE` / `DOD_CUST_PROFILE` 做铺垫；`installation/upgrades/nst-dbu-organizations.lisp` 提供数据迁移。新旧并存策略与 `vendor` 词义切换详见 [data-model.md](data-model.md)。
3. **AI 接入**：`core/nst-bl-ollama.lisp` + `*NST-VENDOR-TABLES-FOR-AGENTIC-AI*`（启动时载入 vendor 相关表结构 txt），用 Ollama 跑 agent 协助卖家。
4. **跨租户 / 多卖家订单**是核心复杂度：`DOD_ORDER` 主单 + `DOD_VENDOR_ORDERS` 子单 + `DOD_ORDER_ITEMS` 行项，配合 `set-order-fulfilled` 三段式标记。详见 [order-flow.md](order-flow.md)。
5. **运维约束**：硬编码路径、单 Lisp 进程、actor 内存态、Node 服务的内存订阅列表 → 横向扩展时需要外移到 Redis/RDS；Nginx 已经预设了多 Hunchentoot 节点的 upstream。
