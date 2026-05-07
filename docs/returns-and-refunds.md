# 退货 / 换货 / 退款能力盘点

> 拆分自 [`architecture.md`](architecture.md)。本文档梳理 Nine Stores 当前对**退货 / 部分退货 / 换货 / 退款**的支持现状，并给出补齐这些能力时需要触动的层与文件。

**结论先放**：项目目前**不实现**完整的退货 / 退款 / 换货流程。只有"整单取消"和"手动标记发票为已退款"两个轻量状态切换，**没有金额、库存、支付的联动**。仓储 schema 上预留了相关字段，但 BL/UI 未接通。

---

## 1. 订单状态机：只有 4 个状态

`hhub/order/dod-bl-ord.lisp` / `dod-bl-odt.lisp` 全文 grep，主单 / 子单 / 行项的 `status` 只取 4 个值：

| 代码 | 含义 | 谁触发 | 文件 |
| --- | --- | --- | --- |
| `PEN` | PENDING（默认） | `persist-order` 创建时 | `dod-bl-ord.lisp:435` |
| `CMP` | COMPLETED | `set-order-fulfilled` 履约完成 | `dod-bl-ord.lisp:46` |
| `CCN` | CANCELLED BY CUSTOMER | `cancel-order-by-customer` | `dod-bl-ord.lisp:364` |
| `VCN` | CANCELLED BY VENDOR | `cancel-order-by-vendor` | `dod-bl-ord.lisp:371` |

**没有** `RTN`（退货）/ `RFD`（已退款）/ `EXC`（换货）等状态。订单领域里不存在"退货"概念。

---

## 2. 取消是怎么实现的

```lisp
;; dod-bl-ord.lisp:364
(defun cancel-order-by-customer (order-instance)
  (setf (slot-value order-instance 'status) "CCN")
  (clsql:update-record-from-slot order-instance 'status))

;; dod-bl-ord.lisp:371
(defun cancel-order-by-vendor (order-instance)
  (setf (slot-value order-instance 'status) "VCN")
  (clsql:update-record-from-slot order-instance 'status))
```

只改 1 个字段，**完全没有做**：

- ❌ **库存回滚**：`update-stock-inventory` 是单向递减；没有 `restore-stock-inventory`
- ❌ **钱包 / 支付退款**：PRE 钱包扣的款不退；OPY 网关流水也不冲销
- ❌ **通知**：不发邮件、不发 Webpush 给卖家
- ❌ **发票联动**：已开发票的 status 不动
- ❌ **vendor_orders 子单**不做处理

---

## 3. 行项级"部分取消"——勉强算一点

```lisp
;; dod-bl-odt.lisp:176
(defun cancel-order-items (list company-instance)
  ;; list = row-id 列表
  (mapcar (lambda (id) ...
            (setf (slot-value dodorder 'status) "CCN")
            (clsql:update-record-from-slot dodorder 'status)) list))
```

这是**唯一**可以"部分操作"的接口 —— 调用方传一组 `dod-order-items.row-id`，逐条改成 `CCN`。但同样：

- 只改行项 `status`，**不改主单**（主单还是 PEN/CMP）
- **不改 vendor_orders 子单金额**（子单 `order-amt` 仍是初始总额）
- 不退库存、不退款、不通知
- **不能按数量部分取消**：行项的 `prd-qty` 是单值，没有"原订 5 件、退 2 件"的拆分机制

所以严格意义的"部分退货"也**没有实现**，只是"逐行整条取消"。

---

## 4. 发票的 REFUNDED 状态：装饰大于联动

`hhub/invoice/nst-ui-ihd.lisp` 涉及 `REFUNDED` 的位置：

- `status` 枚举：`'DRAFT' / 'PENDINGPAYMENT' / 'PAID' / 'SHIPPED' / 'CANCELLED' / 'REFUNDED'`（`nst-ui-ihd.lisp:2185-2201`）
- `com-hhub-transaction-mark-invoice-refunded`（文件头注释 `nst-ui-ihd.lisp:23`）
- 第 7 号邮件模板 "Returned/Refunded Invoice"（`nst-ui-ihd.lisp:661`）

但实际逻辑只有：

1. **手动**把发票状态改成 `'REFUNDED'`（一个 `setf`）
2. UI 下拉菜单允许发"已退款"邮件模板
3. **没有**：退款金额计算、按行退款、生成贷项发票（credit note）、与订单/支付/库存联动

即便业务上线下退了款，系统里也只是"我手动告诉你退过了"。

---

## 5. Schema 上有占位，BL 没接通

`installation/upgrades/nst-dbu-warehouse.lisp` 在 schema 设计上**预留**了完整的退货能力：

```sql
-- DOD_STOCK_MOVEMENT.MOVEMENT_TYPE 枚举（line 199-216）
'GOODS_RECEIPT',         -- 入库
'GOODS_ISSUE',           -- 出库
'RETURN_FROM_CUSTOMER',  -- 销售退货  ★
'RETURN_TO_VENDOR',      -- 采购退货  ★
'RESERVATION',           -- 预留
'RESERVATION_RELEASE'    -- 释放预留

-- DOD_STOCK_MOVEMENT.REFERENCE_TYPE（line 233-243）
'RETURN_ORDER'           -- ★ 退货单引用类型

-- DOD_LOCATIONS.LOCATION_TYPE（line 528-537）
'RETURN'                 -- ★ 退货专用库位
```

但 grep `hhub/warehouse/*.lisp` 与 `hhub/stock/*.lisp`：

| 字符串 | 命中数 |
| --- | --- |
| `RETURN_FROM_CUSTOMER` | 0 |
| `RETURN_TO_VENDOR` | 0 |
| `RETURN_ORDER` | 0 |

**schema 字段建好了，BL/UI 没有任何代码使用**。这是仓储模块"按新风格写但远未完工"的典型痕迹。

---

## 6. 换货：完全没有

全库 grep `exchange` / `REPLACEMENT` / `swap` / `换货` —— 业务相关命中数为 0。**根本没有概念**。

---

## 7. 能力地图汇总

| 能力 | 实现度 | 实际效果 |
| --- | --- | --- |
| 整单客户取消（CCN） | ✅ | 仅改 1 个字段，无任何联动 |
| 整单卖家取消（VCN） | ✅ | 同上 |
| 行项整条取消 | ⚠️ | `cancel-order-items` 改字段，主单 / 子单 / 库存都不动 |
| 行项**按数量**部分取消 | ❌ | `prd-qty` 不可拆 |
| 退货流程 | ❌ | 无任何状态、无 BL |
| 库存回退 | ❌ | warehouse schema 有 `RETURN_FROM_CUSTOMER`，BL 缺失 |
| 钱包 / 网关退款 | ❌ | 无 |
| 贷项发票（credit note） | ❌ | 发票 `REFUNDED` 仅手动标记 |
| 退货专用库位 | ❌ | schema `LOCATION_TYPE='RETURN'` 已建，BL 不用 |
| 退货邮件 | ⚠️ | 仅发票第 7 模板"Returned/Refunded Invoice" |
| 换货 | ❌ | 完全没有 |

---

## 8. 实现"部分退货"需要补的工作

按当前架构估算，最少这些工作量：

### 8.1 数据模型

- 给 `DOD_ORDER_ITEMS` 增加 `returned-qty`（拆分原 `prd-qty`）
- 新建 `DOD_RETURN_ORDER` + `DOD_RETURN_ITEMS`（呼应 schema 已留的 `REFERENCE_TYPE='RETURN_ORDER'`）
- 订单状态枚举扩 `RTN`/`PRT`（部分退货）/`RFD`

### 8.2 BL（业务逻辑）

- `create-return-order`：生成退货单
- `process-return-receipt`：卖家收货，触发 warehouse `RETURN_FROM_CUSTOMER` 移动
- `restore-stock-inventory`：与现有 `update-stock-inventory` 配对
- `refund-wallet-balance` / `refund-via-gateway`：呼应已有 `deduct-wallet-balance`
- `create-credit-note-invoice`：贷项发票

### 8.3 ABAC（权限）

- `com-hhub-transaction-create-return-order`（客户发起）
- `com-hhub-transaction-approve-return`（卖家批准）
- `com-hhub-policy-return-window-check`（退货时效策略 —— 例如 7 天内可退）

参考 [request-handling.md](request-handling.md) 了解 ABAC 注册流程。

### 8.4 SQL 事务

退货链路涉及钱财双向流动，**必须**包 `clsql:with-transaction`：

```
退货单状态切换 + 库存回退（写 STOCK_MOVEMENT） + 钱包回款（写 CUST_WALLET）
```

三件事必须原子化。当前订单创建都没包事务（详见 [order-flow.md §10](order-flow.md#10-设计要点)），但退货链路跳不过去 —— 失败一半会导致库存或资金不一致。

### 8.5 跨 vendor 复杂度

多卖家订单的部分退货 —— 当前 `set-order-fulfilled` 已经按 vendor 颗粒推 `CMP`（详见 [order-flow.md §7](order-flow.md#7-履约推进vendor-侧)），**退货也得按 vendor 颗粒退**：

- A 卖家的子单可以退，B 卖家的不动
- 子单 `order-amt` 需要按已退金额扣减
- 主单状态可能需要新值 `PRT`（部分退货）—— 既不是 `CMP` 也不是 `CCN`

### 8.6 选型建议

如果要做：建议直接写在 `nst-` 新风格里走 [Context Flow Dispatcher](request-handling.md#2-较新的-context-flow-dispatcher六边形架构)（注册 `:return-order/create`、`:return-order/approve` 等路由），不要再往 `dod-bl-ord.lisp` 里堆。这样：

- 走六边形管线，自动接 ABAC
- 单元测试更容易（Adapter / Service / Presenter 可独立 mock）
- 未来切到 `DOD_ORGANIZATIONS` 多组织模型时阻力更小

---

## 9. 评估结论

退货 / 换货是一个**中等偏大的领域工作**，不是几天能做完的：

- 涉及订单 / 行项 / 子单 / 库存 / 支付 / 发票 6 个领域协调
- 涉及客户 / 卖家两类用户的双向交互
- 涉及金额计算（部分退、运费按比例退、税额回冲）
- 必须补 SQL 事务原子性

如果是评估二开成本，这部分**不能用"加几个状态字段"的工作量估算**。建议把它视作一个独立 feature epic 立项。

---

[← 返回架构总览](architecture.md)
