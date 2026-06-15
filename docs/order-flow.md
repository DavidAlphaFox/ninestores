# 客户下单与履约流程

> 拆分自 [`architecture.md`](architecture.md)。本文档梳理从 customer 提交购物车到 vendor 标记发货、主单 CMP 的端到端链路，涉及 customer / order / paymentgateway / shipping / sysuser / smsserver / webpushserver 等多模块。

---

## 1. 入口与路由

```
POST /hhub/dodmyorderaddaction
   ↓ Hunchentoot dispatcher           hhub/sysuser/dod-ui-sys.lisp:1092
com-hhub-transaction-create-order      hhub/customer/dod-ui-cus.lisp:2738
   ↓ with-cust-session-check           ← 客户登录态校验
   ↓ with-mvc-redirect-ui              ← M+V+重定向管线
create-model-for-custordercreate       hhub/customer/dod-ui-cus.lisp:~2680
```

控制器只是壳，实际逻辑在 model 函数里。

## 2. ABAC 关卡

进入 model 后第一道关是 PEP（`dod-ui-cus.lisp:2694`）：

```lisp
(with-hhub-transaction "com-hhub-transaction-create-order" params ...)
```

走 [request-handling.md](request-handling.md) 描述的标准 ABAC 流程：从 `DOD_BUS_TRANSACTION` 取策略函数 → 求值 `com-hhub-policy-create-order-action` → 通过则放行。

## 3. 预支付校验（PRE 模式）

`payment-mode='PRE'`（钱包预付）时先校验余额：

```lisp
(check-all-vendors-wallet-balance vendor-list wallet-list order-items)
```

**按每个 vendor 单独算钱包余额**（每个 vendor-customer 对持有独立 wallet）。任一不足 → 重定向 `/hhub/dodcustlowbalanceshopcart`，**不创建订单**。

## 4. 核心：create-order-from-shopcart

校验通过后进入 `dod-bl-ord.lisp:622`：

```
create-order-from-shopcart
  │
  ① uuid:make-v1-uuid                    生成 context-id（幂等键）
  │
  ② create-order ─→ persist-order        INSERT DOD_ORDER（主单）
  │                                      status='PEN', fulfilled='N'
  │
  ③ get-order-by-context-id              用 UUID 取回主单 row-id
  │
  ④ save-order-items-in-db               逐行 INSERT DOD_ORDER_ITEMS
  │     └─ update-stock-inventory        units_in_stock -= prd_qty
  │                                      （注释自标 "rudimentary"，无锁/无预留）
  │
  ⑤ save-vendor-orders-in-db             ★ 按 vendor 拆子单
  │     for each vendor in shopcart:
  │     ├─ persist-vendor-orders         INSERT DOD_VENDOR_ORDERS
  │     │                                status='PEN', fulfilled='N'
  │     ├─ save-upi-transaction          若有 UTR 号（UPI 转账）
  │     ├─ send-order-mail               HTML 邮件给卖家
  │     └─ send-webpush-message          浏览器推送给卖家
  │
  return order-id
```

**关键**：购物车内若有 N 个 vendor 的商品，会写 **1 条主单 + N 条子单 + M 条行项**。

## 5. 客户侧通知

回到 controller（`dod-ui-cus.lisp:2719-2731`），按 `cust-type` 分流：

| 客户类型 | 邮件                                          | 短信                                          |
| ---      | ---                                           | ---                                           |
| GUEST    | `send-order-email-guest-customer`（有 email） | `send-order-sms-guest-customer`（phone 必填） |
| STANDARD | `send-order-email-standard-customer`（有 email）| `send-order-sms-standard-customer`（有 phone）|

短信走 `smsserver`（4300）→ AWS SNS；Webpush 走 `webpushserver`（4345）。

## 6. 收尾与重定向

```
reset-cust-order-params                  清 session :customer-clipboard
session :login-cusord-cache  ← get-orders-for-customer
session :login-shopping-cart ← nil       清空购物车
   ↓
redirect /hhub/dodcustordsuccess
```

## 7. 履约推进（vendor 侧）

下单完成时主单仍为 `PEN` / `fulfilled='N'`。当 vendor 在自己后台点击"已发货"时调 `set-order-fulfilled`（`dod-bl-ord.lisp:46`）：

```
set-order-fulfilled(value, vendor, order, company)
  ① tenant 校验：order.company.name == company.name 才放行
  ② 该 vendor 的所有 order_items     → status='CMP', fulfilled='Y'
  ③ 该 vendor 的 vendor_orders 子单  → status='CMP', fulfilled='Y', shipped_date=today
  ④ count-order-items-pending == 0?
       是 → 主单 DOD_ORDER  → status='CMP', fulfilled='Y'
  ⑤ payment_mode='PRE' → deduct-wallet-balance(vendor 小计, wallet)
  ⑥ dod-reset-order-functions          清缓存的订单函数列表
```

**履约按 vendor 颗粒分段推进**：A 卖家发完货只动 A 的子单；所有 vendor 都完成才回写主单 CMP。

## 8. 在线支付（OPY）变体

`payment-mode='OPY'` 时，购物车页直接跳 Razorpay 网关（`make-payment-request-html`，`dod-ui-cus.lisp:3272-3275`）。网关回调成功后才 redirect 回 `/hhub/dodmyorderaddaction`（`hhub/paymentgateway/dod-ui-pay.lisp:267`），再触发 §1–§6 主链。

## 9. 全流程时序

```
 Customer            Hunchentoot           BL                  DAL/MySQL           其他卖家/服务
    │ POST /dodmyorderaddaction                │                    │                    │
    ├──────► com-hhub-transaction-create-order                      │                    │
    │       with-cust-session-check                                 │                    │
    │       with-hhub-transaction (ABAC PEP/PDP)                    │                    │
    │       check-all-vendors-wallet-balance (PRE only)             │                    │
    │       create-order-from-shopcart  ►                           │                    │
    │                              create-order                     │                    │
    │                              persist-order ──────────────────► INSERT DOD_ORDER   │
    │                              get-order-by-context-id ◄──────── SELECT              │
    │                              save-order-items-in-db ─────────► INSERT DOD_ORDER_ITEMS
    │                              update-stock-inventory ─────────► UPDATE DOD_PRD_MASTER
    │                              save-vendor-orders-in-db ───────► INSERT DOD_VENDOR_ORDERS×N
    │                              send-order-mail ────────────────────────────────────► 卖家邮箱
    │                              send-webpush-message ────────────────────────────────► 卖家浏览器
    │       send-order-{email,sms}-{guest,standard}-customer ────────────────────────► 客户邮箱/短信
    │ ◄──── redirect /hhub/dodcustordsuccess ──┤                    │                    │
    .                                                                                       
    .  …稍后…                                                                               
    .                                                                                       
    │                              set-order-fulfilled ◄──── 卖家点"已发货"             │
    │                                 UPDATE order_items + vendor_orders                  │
    │                                 IF all done → UPDATE DOD_ORDER status=CMP           │
    │                                 IF PRE → deduct-wallet-balance                      │
```

## 10. 设计要点

1. **三层数据落盘**：`DOD_ORDER` 主单 + `DOD_VENDOR_ORDERS` 子单（按 vendor 拆）+ `DOD_ORDER_ITEMS` 行项 —— 多卖家是核心复杂度。
2. **PRE 支付双重校验**：下单前查总余额，履约时按 vendor 小计扣钱包。
3. **库存扣减简陋**：`update-stock-inventory` 注释自标 "rudimentary"，无库存预留 / 无锁 / 无多仓位。新版仓储能力在 warehouse 模块（`DOD_STOCK` / `DOD_STOCK_MOVEMENT` / `GOODS_RECEIPT`），但**老订单流程未切换**。
4. **履约是 vendor 颗粒状态机**：子单 PEN→CMP；全部完成才回写主单 CMP。
5. **副作用全在主流程内**（邮件、短信、Webpush、UPI 落账）—— 无事件总线，失败处理朴素（异常即抛）。`core/nst-bl-act.lisp` 提供自研 actor，但订单流程未使用。
6. **订阅型订单走另一条路**：`create-order-from-pref`（`dod-bl-ord.lisp:456`）由 cron `run-daily-orders-batch` 触发，按 `dod-order-subscription` 偏好为客户批量生成订单（默认 PRE、子单创建即 `fulfilled='Y'`）。
7. **下单链路反向操作（退货 / 部分退货 / 换货 / 退款）基本未实现** —— 当前只有"整单取消"（`CCN`/`VCN`，仅改 status 字段，无库存 / 钱包 / 通知联动）和"手动标记发票为 REFUNDED"。仓储 schema 留有 `RETURN_FROM_CUSTOMER`、`RETURN_TO_VENDOR`、`RETURN_ORDER` 等占位字段但 BL 未接通。完整盘点见 [returns-and-refunds.md](returns-and-refunds.md)。

---

[← 返回架构总览](architecture.md)
