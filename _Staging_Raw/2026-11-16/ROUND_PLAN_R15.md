# R15 轮次作战计划（ROUND_PLAN_R15）

> **日期**：2026-11-16 ｜ **性质**：T0 快车道（零检索，复用源矩阵既有源记录）｜ **目标**：20 件防御性标准函数包装，全部归 `DL_MathData`
> **命名纪律**：一律带 `Ex` 后缀避免与平台内建同名冲突；前缀统一 `FC_DL_`
> **核心纪律**：内部委托平台内建函数，外围统一「错误码 + 钳位 + 双语文档」，**严禁重实现数学内核**

## 一、20 件目标清单（主控已锁定）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次(1-4) |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_AbsEx | Math-Exp | FC_DL_ | 实数绝对值，含 -0.0 与 NaN 归一、±1.7e308 溢出钳位 | iec-std-math | S | 1 |
| 2 | FC_DL_SinEx | Math-Trig | FC_DL_ | 正弦计算（入参弧度），超大角度先按 2π 归约保精度 | iec-std-trig | M | 1 |
| 3 | FC_DL_CosEx | Math-Trig | FC_DL_ | 余弦计算，与 SinEx 同一 2π 归约策略 | iec-std-trig | M | 1 |
| 4 | FC_DL_AsinEx | Math-Trig | FC_DL_ | 反正弦，定义域 [-1,1] 外钳位并置错误码 | iec-std-trig | M | 1 |
| 5 | FC_DL_AcosEx | Math-Trig | FC_DL_ | 反余弦，同 AsinEx 钳位策略 | iec-std-trig | M | 1 |
| 6 | FC_DL_AtanEx | Math-Trig | FC_DL_ | 反正切，全实数域，返回 (-π/2, π/2) | iec-std-trig | S | 2 |
| 7 | FC_DL_Atan2Ex | Math-Trig | FC_DL_ | 四象限反正切（y,x），含双零输入定义（返回 0 且置信息码）、象限判别 | iec-std-trig | M | 2 |
| 8 | FC_DL_ExpEx | Math-Exp | FC_DL_ | 自然指数，上溢判据（结果 > 1.7e308 前钳位 + 置码） | iec-std-math | M | 2 |
| 9 | FC_DL_ExptEx | Math-Exp | FC_DL_ | 幂运算 base^exp，含 0^负指数、负底数非整数指数、溢出三类防护 | iec-std-math | M | 2 |
| 10 | FC_DL_TruncEx | Math-Round | FC_DL_ | 向零取整，含超出 DINT 范围钳位 | iec-std-round | S | 2 |
| 11 | FC_DL_FloorEx | Math-Round | FC_DL_ | 向下取整（向 -∞），负数边界正确 | iec-std-round | S | 3 |
| 12 | FC_DL_CeilEx | Math-Round | FC_DL_ | 向上取整（向 +∞） | iec-std-round | S | 3 |
| 13 | FC_DL_StringLenEx | String | FC_DL_ | 字符串有效长度（去尾随空格/空符），越界段防护 | iec-std-string | S | 3 |
| 14 | FC_DL_StringLeftEx | String | FC_DL_ | 取左 n 字符，n 越界钳位 | iec-std-string | S | 3 |
| 15 | FC_DL_StringRightEx | String | FC_DL_ | 取右 n 字符，n 越界钳位 | iec-std-string | S | 3 |
| 16 | FC_DL_StringConcatEx | String | FC_DL_ | 安全拼接，超 255 截断并显式置截断标志（R37 范式） | iec-std-string | M | 4 |
| 17 | FC_DL_StringInsertEx | String | FC_DL_ | 指定位置插入，位置越界钳位 | iec-std-string | M | 4 |
| 18 | FC_DL_StringDeleteEx | String | FC_DL_ | 删除指定区间，区间越界钳位 | iec-std-string | M | 4 |
| 19 | FC_DL_StringFindEx | String | FC_DL_ | 子串查找，返回 1-based 位置，未找到返回 0 且不置错误 | iec-std-string | S | 4 |
| 20 | FC_DL_StringReplaceAtEx | String | FC_DL_ | 指定位置定长替换（与既有 StringReplaceAll 全局替换职责区分） | iec-std-string | M | 4 |

**标签口径**：注册时 `function_tags` 必须同时含 `iec-std-wrapper` + 上表细化标签。

## 二、① 盘点（实测基线，不猜）

| 指标 | 数值 |
|---|---|
| 总库规模 | 224 / 10,000（2.24%） |
| 库版本 | v2.3.0（INDEX_REGISTRY.json 实测一致） |
| counts | DL_Base:55, DL_MathData:47, DL_Algo:28, DL_Device:50, DL_Motion:18, DL_Process:26 |
| JSONL / .st | 均 224 行/个，三口径一致 |
| 距 500 差额 | 276 |
| 今日（2026-11-16）已入库 | 38 / 200（R13 的 18 + R14 的 20） |

**源矩阵 T0 覆盖率**：T0-1 / T0-2 / T0-3 / T0-7 四组已收口（✔）；T0-4 ◐（余 ABS/SIN/COS/ASIN/ACOS/ATAN/EXP/EXPT 8 件——本轮批次 1/2 直接清零其中 7 件）；T0-5 ◐（仅 ROUND 收口，余 TRUNC/FLOOR/CEIL——本轮批次 2/3 清零 3 件）；T0-6 ◐（余 LEN/LEFT/RIGHT/CONCAT/INSERT/DELETE/REPLACE/FIND 8 件——本轮批次 3/4 清零其中 8 件）。**本轮完成后 T0-4 / T0-5 / T0-6 可全部转 ✔，T0 七组整体收口率 7/7。**

## 三、② 分批策略（4×5）

| 批次 | 件数 | 构成 | 收口目标 |
|---|---|---|---|
| 批次 1 | 5 | 数学三角与绝对值（Abs/Sin/Cos/Asin/Acos） | T0-4 主体清零（余 Atan/Exp/Expt 入批次 2） |
| 批次 2 | 5 | 反三角 + 指数/幂 + 向零取整（Atan/Atan2/Exp/Expt/Trunc） | T0-4 全清 + T0-5 首件 |
| 批次 3 | 5 | 取整收尾 + 字符串前段（Floor/Ceil/Len/Left/Right） | T0-5 全清 + T0-6 五件 |
| 批次 4 | 5 | 字符串后段（Concat/Insert/Delete/Find/ReplaceAt） | T0-6 全清，T0 七组 7/7 收口 |

串行推进：批次内组件彼此零依赖、可并行重构；批次间无依赖；入库顺序按序号 1→20。

## 四、③ 溯源口径声明

1. **实现路线**：内部委托各平台内建标准函数（SIN/COS/EXP/FIND 等），外围统一做防御守卫（定义域闸门、NaN/Inf 拦截、255 上限截断标志、DINT 范围钳位），**严禁重实现数学内核**（例：SINEx 直接调系统 SIN，只在入口做 2π 归约与有限性检查）。
2. **文件头溯源**：统一标注「IEC 61131-3 标准语义的道莅防御性实现」，接口语义由 IEC 61131-3 标准定义，不构成版权文本。
3. **参考实现**：只允许对照 MIT / Apache 许可开源实现（如 OSCAT Basic），**禁抄西门子 / 罗克韦尔等闭源实现**（T0 铁律 1：只借骨不抄肉）。
4. **错误码与文档**：外围统一错误码 + 钳位 + 双语文档，与 R14 已收口的域闸门四段式样板（R45）、255 截断显式置标志（R37/R49）范式保持一致。
