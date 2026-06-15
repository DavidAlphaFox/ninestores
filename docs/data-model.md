# 数据模型

> 拆分自 [`architecture.md`](architecture.md)。本文档梳理 Nine Stores 的整体表分组以及 `vendor` 新旧模型双轨共存策略。

---

## 1. 数据模型概览

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

## 2. vendor 与组织模型的双轨共存

`vendor` 在仓库里有**两种不同语义**，对应新旧两套数据模型。两者目前并存，通过 `DOD_ORG_RELATIONS` 上的桥接外键互通。读代码时务必先判断所在模块属于哪一轨。

### 2.1 同名异义

| 出现位置 | `vendor` 含义 | 视角 |
| --- | --- | --- |
| 老链路：`DOD_VEND_PROFILE`、`DOD_VENDOR_ORDERS`、`DOD_VENDOR_SETTINGS`、ABAC subject | **入驻 marketplace 的卖家**（B2C：vendor → customer） | 平台视角 |
| 新链路：`DOD_ORG_RELATIONS.relation_type = 'VENDOR'` | **本租户的供应商**（B2B：本公司从对方采购） | 单租户视角 |

新模型还把"供应商"进一步细分到 `business_type` 枚举（`installation/upgrades/nst-dbu-organizations.lisp:92-106`）：`SUPPLIER` / `MANUFACTURER` / `DISTRIBUTOR` / `WHOLESALER` / `RESELLER` / `DROPSHIPPER` …。

### 2.2 新模型三件套

`installation/upgrades/nst-dbu-organizations.lisp` 引入了一组通用合作伙伴主档：

```
DOD_ORGANIZATIONS   —— 统一的"法人/组织"主档（不再区分卖家/客户/供应商）
DOD_ORG_RELATIONS   —— "租户 ↔ 组织"关系记录，relation_type 决定语义
DOD_CONTACTS        —— 挂在 organization 上的联系人
DOD_ADDRESSES       —— 挂在 organization 上的多地址（BILLING / SHIPPING / WAREHOUSE …）
```

`DOD_ORG_RELATIONS.relation_type` 枚举（line 90）定义关系语义：

| relation_type | 含义 | 中文 |
| --- | --- | --- |
| `PRIMARY`  | 本租户自身                  | 自有公司 |
| `VENDOR`   | "buy from"（对方向我方供货）| **供应商** |
| `CUSTOMER` | "sell to"（我方卖给对方）   | 客户 |
| `BOTH`     | 双向                        | 既买又卖 |

唯一键 `uk_company_org_relation (tenant_id, org_id, relation_type)` 约束**同一组织对同一租户的每种关系只能有一条**，但同一组织可以**同时**作为 VENDOR 和 CUSTOMER 各登记一条 —— 把老系统里 "vendor = 固定身份" 升级成 "组织 + 上下文角色"。

### 2.3 桥接机制：legacy FK

新旧并不是孤岛。`DOD_ORG_RELATIONS` 上保留两根**指回老表**的外键（`nst-dbu-organizations.lisp:109-110, 195-198`）：

```sql
vendor_profile_id   mediumint  COMMENT 'Link to legacy DOD_VEND_PROFILE',
customer_profile_id mediumint  COMMENT 'Link to DOD_CUST_PROFILE (for B2C migrated customers)',
...
CONSTRAINT fk_rel_vendor_profile   FOREIGN KEY (vendor_profile_id)
    REFERENCES DOD_VEND_PROFILE(row_id)   ON DELETE SET NULL,
CONSTRAINT fk_rel_customer_profile FOREIGN KEY (customer_profile_id)
    REFERENCES DOD_CUST_PROFILE(row_id)   ON DELETE SET NULL,
```

每条老 `DOD_VEND_PROFILE` 行可以一一对应到 `DOD_ORGANIZATIONS` 里某条 org，再通过 `DOD_ORG_RELATIONS` 把卖家身份重新表达成 `VENDOR/CUSTOMER` 关系。新链路需要兼容老业务时，由此反查回老 profile。

### 2.4 迁移现状（按领域）

| 领域 | 仍走老 `DOD_VEND_PROFILE` | 已切到新 `DOD_ORGANIZATIONS` |
| --- | --- | --- |
| Marketplace 下单 / 履约 | ✅ `dod-bl-ord.lisp` 中 `set-order-fulfilled` 按 `dod-vendor-orders` 颗粒推进 | — |
| 卖家会话 / 登录          | ✅ `VendorSessionObject`、`*HHUBMAXVENDORLOGINS*`              | — |
| 卖家设置                 | ✅ `DOD_VENDOR_SETTINGS.VENDOR_ID` 指向 `DOD_VEND_PROFILE`      | — |
| ABAC 主体                | ✅ subject `vendor`                                            | — |
| 仓储 / 进货              | —                                                              | ✅ `DOD_INVENTORY_BATCH.SUPPLIER_ID`、`GOODS_RECEIPT` "Inbound from supplier"（`nst-dbu-warehouse.lisp:200,451`） |
| B2B 关系 / 多组织        | —                                                              | ✅ `DOD_ORG_RELATIONS` |
| 采购角色                 | —                                                              | ✅ `PROCUREMENT_MANAGER` / `PROCUREMENT_EXECUTIVE`（`nst-dbu-custusers.lisp:97-98`） |

### 2.5 演进策略：Strangler Fig

```
            ┌─────────────────────────────────────┐
            │  老系统(marketplace 主链路)          │
            │  DOD_VEND_PROFILE   ← vendor=卖家    │
            │  DOD_VENDOR_ORDERS                   │
            │  DOD_VENDOR_SETTINGS                 │
            └──────────────┬──────────────────────┘
                           │ vendor_profile_id (legacy FK)
                           ▼
            ┌─────────────────────────────────────┐
            │  新系统(B2B / 采购抽象层)            │
            │  DOD_ORGANIZATIONS   ← 统一主档      │
            │  DOD_ORG_RELATIONS   ← relation_type │
            │      VENDOR=供应商 / CUSTOMER=客户   │
            │  DOD_WAREHOUSE.SUPPLIER_ID           │
            └─────────────────────────────────────┘
```

**做法**：老表不动 + 新表叠加 + 关系表通过 `vendor_profile_id` / `customer_profile_id` 桥接回老表 —— 典型的 **Strangler Fig** 演进：新模型在外层逐步"包裹"老模型，业务按领域逐个迁移，老链路在迁完之前继续工作。

**读代码提示**：marketplace / 订单 / 会话 / ABAC 语境下的 `vendor` 一律是"卖家"；organizations / warehouse / 采购语境下的 `vendor` 才是"供应商"。同一英文词、两种语义，差别完全由所在模块决定。

---

[← 返回架构总览](architecture.md)
