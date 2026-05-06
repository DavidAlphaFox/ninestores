# Nine Stores 中文注释风格指南

> 给代码加中文注释时遵守此文档。**只加注释，绝不改动业务代码逻辑、参数、签名**。

## 文件头注释模板

每个 `.lisp` 文件**最顶端**（在 `(in-package :nstores)` 之前）插入下述格式块。原有 `;; -*- mode:` 模式行保留：

```lisp
;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：<account|customer|order|invoice|product|vendor|warehouse|...>
;;;; 分层：<DAL 数据访问层 | BL 业务逻辑层 | UI 控制器/视图层 | 平台基础>
;;;; 文件：<相对仓库根的路径，例如 hhub/order/dod-dal-ord.lisp>
;;;; ----------------------------------------------------------------------------
;;;; 职责：<1-2 句话概括本文件的作用>
;;;;
;;;; 主要导出：
;;;;   <符号名>          — <一句话>
;;;;   <符号名>          — <一句话>
;;;;   ...               (列出最重要的 5-10 个，函数/宏/类/特殊变量都可以)
;;;;
;;;; 关联：
;;;;   上游使用方：<调用本文件的模块>
;;;;   下游依赖：<本文件依赖的模块>
;;;; ============================================================================
```

**判断分层的简单规则：**

| 文件名前缀模式 | 分层 |
| --- | --- |
| `dod-dal-*` / `nst-dal-*` | DAL（数据访问层 — `def-view-class`、表映射、CRUD SQL） |
| `dod-bl-*` / `nst-bl-*` / `hhub-bl-*` | BL（业务逻辑层 — 领域计算、聚合、事务） |
| `dod-ui-*` / `nst-ui-*` / `hhub-ui-*` | UI（控制器 + CL-WHO 模板） |
| `dod-ini-*` / `nst-sch-*` / `compile.lisp` / `packages.lisp` | 平台基础（启动、缓存、迁移、包定义） |

模块（account / customer / order / …）即文件所在的子目录名；`core/` 下统一标 "core 平台基础"。

## 函数级注释

### Common Lisp 标准 docstring（首选）

```lisp
(defun some-fn (arg1 arg2)
  "中文一句话说明：函数做什么。
   参数：arg1 — 含义；arg2 — 含义。
   返回：返回值含义。
   备注：副作用 / 边界 / 重要假设。"
  ...)
```

### 项目里的非标准 `:documentation` 形式（保持兼容）

代码库现存大量这种写法：

```lisp
(defun foo (a b)
  :documentation "..."
  ...)
```

`:documentation "..."` 在 Common Lisp 里实际是个 noop 表达式（`:documentation` 是关键字、字符串是常量），不是真正的 docstring。**已有这种写法的函数请保留 `:documentation` 关键字格式**，只把英文换成中文或在英文后追加中文：

```lisp
(defun foo (a b)
  :documentation "中文：foo 做什么。参数 a — ...，b — ...。"
  ...)
```

如果原本英文写得很有用，可以并存：

```lisp
:documentation "Original English. 中文：补充说明。"
```

### 函数类型 → 注释要点

| 类型 | 必写要点 |
| --- | --- |
| DAL CRUD（`select-*-by-*` / `persist-*` / `update-*` / `delete-*`） | 哪张表 + 软删过滤 + 多租户过滤的 tenant_id 来源 |
| BL 领域函数 | 业务规则 / 输入输出 / 副作用（写库 / 写日志 / 触发 actor） |
| UI 控制器（`dod-controller-*` / `com-hhub-transaction-*`） | URL（如能从命名推断）+ 必需会话 + 调用的 BL/PEP |
| 策略 `com-hhub-policy-*` | 主体 / 资源 / 动作 / 拒绝条件（PDP 视角） |
| 属性 `com-hhub-attribute-*` | 取值来源（DB 查询 / 纯函数） + ATTR_TYPE |
| 宏 `defmacro` | 展开形态 + 使用场景 |

## 类 / View-class 注释

`clsql:def-view-class` 与 `defclass` 上方加 `;;` 注释块：

```lisp
;; ----------------------------------------------------------------------------
;; 实体：dod-vendor-orders
;; 表：DOD_VENDOR_ORDERS
;; 含义：多卖家订单中"某 vendor 的子单"，主单 dod-order 通过 row-id 关联。
;; 关键字段：
;;   row-id            主键
;;   order-id          外键 → dod-order
;;   vendor-id         外键 → dod-vend-profile
;;   tenant-id         多租户隔离键 → dod-company.row-id
;;   status            订单状态：PEN/CMP
;;   fulfilled         履约标志：Y/N
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-vendor-orders ()
  ...)
```

各 slot 旁如有非显然语义可加行内 `; 注释`（不要超出 80 列）。

## 行内注释

- 用 `;;` 双分号顶格或与代码同级缩进（节段说明）。
- 用 `;` 单分号写**当前行末尾**的简短说明（不超 50 列）。
- 解释 **为什么** 这么写，不要解释代码本身在做什么（变量名应当自解释）。

## 严格红线（违反就是 bug）

1. **禁止改动**任何函数/宏/类的代码体、参数、返回逻辑。
2. **禁止改动**任何 `clsql` SQL 表达式、`cl-who` 模板、`format` 字符串。
3. **禁止改动** `(in-package :nstores)`、`(clsql:file-enable-sql-reader-syntax)` 等编译期指令的位置。
4. 若无法确定函数语义，**注释里必须用"应是 / 推测："等措辞**，不要伪造确定性。
5. **禁止删除**已有的英文 docstring；可以保留+补中文，或翻译替换（保持信息不丢）。
6. **禁止给所有函数都贴一样的模板话**——每条注释要反映函数实际行为。

## 特殊文件

- `core/xref.lisp`（125K，自动生成的交叉引用）—— **只加文件头**，不要逐函数注释。
- `core/nst-bl-funloodat.lisp`（251K，多半是数据/生成代码）—— 先 Read 头部 200 行判断；若是数据型，**只加文件头**。
- `core/dod-ui-attr.lisp` —— PIP 属性函数集合，注意每加一个属性，PAP 会 append 空 `defun` 到此文件末尾。注释时**不要**触发追加机制。
- `package/packages.lisp` / `package/compile.lisp` —— 这两个用文件头描述即可，逐函数注释意义不大。

## 校验

每完成一个文件，自检：

1. `(in-package :nstores)` 之后的代码字符是否原封不动？（git diff 核对）
2. 文件头注释是否符合上面模板？
3. 每个 `defun` / `defmethod` / `defmacro` / `defclass` / `def-view-class` 是否都有中文说明？
