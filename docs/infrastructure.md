# 基础设施：辅助服务、运行时与配置

> 拆分自 [`architecture.md`](architecture.md)。本文档汇总 Node.js 微服务、缓存与并发机制、测试约定，以及配置与机密管理。

---

## 1. Node.js 辅助微服务

### 1.1 `smsserver/index-v3.mjs`（端口 4300）
- `GET /sms/status` — 健康检查
- `GET /sms/sendsms?number=&message=` — 调用 AWS SNS Publish（`+91` 前缀；附带 `SenderID` / `TemplateId` / `EntityId`，配合印度 VI 的 DLT 注册）。
- 所有敏感参数走 `.env`：`AWS_REGION` / `SENDERID` / `TEMPLATEID` / `ENTITYID`。

### 1.2 `webpushserver/index-v3.mjs`（端口 4345）
- VAPID（`web-push` 库）。`/push/notify/user` 受 `auth-secret` header 保护（默认 `highrisehub1234`）。
- `/subscribe` / `/unsubscribe` 提供给浏览器端，CORS `*`。
- 内存 subscribers 数组，单进程；持久化由 Lisp 侧 `DOD_WEBPUSH_NOTIFY` 完成。

### 1.3 `fileserver/index-v3.mjs`（端口 4301）
- `GET /file/awss3v3/upload` / `DELETE /file/awss3v3/deletefiles`，按 `tenantid/{vnd|cust}/{id}/{OBJECT}/{objectid}/{uuid}` 路径写入 `process.env.AWS_S3_BUCKET`。
- 仅接受 objectname ∈ {`ord`, `prd`, `cfg`}；type ∈ {`vendor`, `customer`}。
- 本地缓存目录 `/data/www/public/img/`，与 Lisp Actor `*NSTAWSS3FILEUPLOADACTOR*` 协作完成「先落本地 → 异步推 S3」。

> 三个服务都通过 `pm2 start index-v3.mjs --name "..."` 由 `startup/nst-start.sh` 拉起。

---

## 2. 缓存、Actor 与并发

- **缓存**：`*HHUBGLOBALLYCACHEDLISTSFUNCTIONS*`、`*HHUBGLOBALBUSINESSFUNCTIONS-HT*`、模板哈希（`*NST-*-TEMPLATES*`），加上 `core/memoize.lisp` 提供的 `memoize` 装饰器。`*dod-database-caching*` 控制 CLSQL 自身的查询缓存（debug 模式下关闭）。
- **Actor 模型**：`core/nst-bl-act.lisp` 定义 `nst-actor`（`name`、`behavior` 函数、`stateful`、`state-clean-callback`、`initial-state`），用 `start-actor` / `destroy-actor` 启停。当前两个常驻 actor：邮件发送 + S3 上传。
- **OTP 闭包存储**：`make-otp-store` 返回带 `:put / :get / :clear` 协议的闭包，配合 `core/nst-bl-otp.lisp` 校验。
- **数据库重连**：登录页的 `nst-generic-login-with-password` 在遇到 CLSQL 2013 错误时会 `(stop-das)` + `(start-das)` 自我恢复并重定向重登。

---

## 3. 测试

`hhub/test/` 下 `hhub-tst-*.lisp` 覆盖：订单、客户、签到、文件上传、GST、SMS、UPI、卖家支付、Webpush、仓储等。  
`core/unit-tests.lisp` 是聚合脚本；`core/xref.lisp`（125K）是符号交叉引用辅助。  
未发现独立的 CI 配置 —— 测试依赖在 SBCL/SLIME 内手动运行。

---

## 4. 配置 / 私密信息

绝大多数运行常量集中在 `core/dod-ini-sys.lisp` 顶端的 `defvar`，包含：

- DB：`*crm-database-*`（默认 `hhubuser` / `Welcome$123`，**生产环境务必覆盖**）。
- 站点：`*siteurl*`、`*HHUBSUPPORTEMAIL*`、`*HHUBGUESTCUSTOMERPHONE*`。
- 资源路径：`*HHUB-EMAIL-TEMPLATES-FOLDER*`、`*HHUB-STATIC-FILES*`、`*NST-INVOICESETTINGS-*`。
- 业务参数：`*HHUBFREESHIPMINORDERAMT*`、`*HHUBMAXVENDORLOGINS*`、`*HHUBTRIALCOMPANYEXPIRYDAYS*`。
- 路径多以 `/home/ubuntu/ninestores/...` 硬编码——开发/部署目录必须保持一致，或在生产前显式覆盖。

Node 服务的密钥放各自 `.env`（`smsserver/.env.example` 是唯一签入示例）。

---

[← 返回架构总览](architecture.md)
