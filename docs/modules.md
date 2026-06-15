# 会话与关键模块速览

> 拆分自 [`architecture.md`](architecture.md)。本文档汇总 Nine Stores 的会话/登录机制以及各业务模块的关键文件入口。

---

## 1. 会话、登录与多角色

- 共四类登录入口（`core/dod-ini-sys.lisp` 的 `*HHUB*LOGINPAGEURL*` 常量）：客户、卖家、运营 (OPR)、CAD（Company Admin）。
- 默认密码 + 手机号短信 OTP 双因子。OTP 经 `core/nst-bl-otp.lisp` 中的 `*otp-store*`（一个闭包式 KV 存储）暂存，并通过 `smsserver` 走 AWS SNS。`*HHUBOTPTESTING* = T` 时短路。
- 登录态保存在 Hunchentoot session（cookie），并通过 `hhub-bl-ent.lisp` 的 `*HHUBBUSINESSSESSIONS-HT*` 在内存里持有 `VendorSessionObject` / `UserSessionObject`，缓存当前订单/产品函数列表。
- 限并发登录：`*HHUBMAXVENDORLOGINS* = 2`、`*HHUBMAXUSERLOGINS* = 2`。

---

## 2. 关键模块速览

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
- ⚠️ 此模块下的 `vendor` 一律指 marketplace 卖家；新模型里 `relation_type='VENDOR'` 表示供应商，是另一套语义，详见 [data-model.md](data-model.md#2-vendor-与组织模型的双轨共存)。

### order
- `dod-dal-ord.lisp` `dod-vendor-orders`，`dod-dal-odt.lisp` `dod-order-items`，`dod-dal-otk.lisp` `dod-order-track`。
- `dod-bl-ord.lisp` 实现订单履约：`set-order-fulfilled` 多卖家时按 `dod-vendor-orders` 颗粒推进，全部 vendor 完成后主单标记 CMP，并扣减 `DOD_CUST_WALLET`（PRE 支付方式）。
- 端到端的客户下单 → 履约链路（购物车提交、按 vendor 拆子单、卖家通知、`set-order-fulfilled`、OPY/PRE/UPI 分支）详见 [order-flow.md](order-flow.md)。
- ⚠️ 反向流程（退货/部分退货/换货/退款）**基本未实现**：仅有整单取消（CCN/VCN）和发票手动标记 REFUNDED，无库存/钱包/支付联动。能力盘点与补齐路线图见 [returns-and-refunds.md](returns-and-refunds.md)。
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

[← 返回架构总览](architecture.md)
