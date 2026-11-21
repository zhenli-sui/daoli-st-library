# ROUND PLAN R18 —— 阶段一盘点 + 阶段二狩猎派单（20 件 / 4 批）

> 轮次：**R18** ｜ 生成时间：2026-11-16 12:48 ｜ 编制：道莅工控代码库产品总监（daoli-library-director）
> 性质：**非纯 T0 轮**（T0 变体快车道 8 件 + T2-1 LGF 未挖子族 5 件 + T1/T2 混合 7 件）
> 检索：**WebSearch 1 次**（CRC-16/CCITT 参数集核对）；其余全部复用既有台账，零新增抓取
> 本文性质：**派单规格书**（可直接编码，禁止再向规格要信息）；`.st` 落盘由后续批次执行

---

## 0 盘点区（Step 1 · 状态读取 · 全部实测，不沿用口头交接）

### 0.1 总库状态（`INDEX_REGISTRY.json` 实解析）

| 项 | 实测值 |
|---|---|
| `version` | **2.6.0** |
| `total_components` | **284** |
| `last_updated` | `2026-11-16T10:24:15+08:00` |
| `counts` | DL_Base **59** / DL_MathData **103** / DL_Algo **28** / DL_Device **50** / DL_Motion **18** / DL_Process **26**（合计 284 ✔ 自洽） |
| 物理 `.st` 文件数 | **284**（`DL_*/*.st` glob 实测，与 registry 一一对应） |
| 总库完成度 | **284 / 10 000 = 2.84 %** |
| 今日累计 | **98 / 200**（11-16 开账 186 → 284） |
| 距 500 冲刺差额 | **216** |
| 语料条数 | **284 条**（`daoli_st_sft_dataset.jsonl`，R17 终审 20 条 sha256 全 MATCH） |

### 0.2 源矩阵覆盖率统计（`SOURCE_HUNTING_MATRIX.md` §5 台账）

| 源组 | 状态 | 已出组件数 | 本轮是否触碰 |
|---|---|---|---|
| T0-1 双稳态/边沿 | ✔ 收口（R14）+变体 | 4 | **触碰**（分频变体，矩阵明列未挖） |
| T0-2 定时器 | ✔ 收口（R14）+变体（R16） | 8 | **触碰**（脉冲整形变体） |
| T0-3 计数器 | ✔ 收口 | 3 | 否 |
| T0-4 数学函数 | ✔ 收口 +变体（R16/R17） | 23 | 否 |
| T0-5 类型转换 | ✔ 收口 +变体（R16/R17） | 25 | 否 |
| T0-6 字符串 | ✔ 收口 | 9 | 否 |
| T0-7 位串 | ✔ 收口 +LWORD（R17） | 8 | **触碰**（跨字多段搬运，矩阵「多段一次搬待挖」） |
| T2-1 LGF · Bit Logic | ◐ | 9 | **触碰**（多段一次搬 → 子族收口） |
| T2-1 LGF · Math | ◐ | 13 | **触碰**（仿射变换组合族，矩阵明列待挖；插值子族补位） |
| T2-1 LGF · Data Handling | ◐ | 9 | **触碰**（CRC-16 族，矩阵「CRC-16 反射 / 累加和待挖」） |
| T2-1 LGF · Measurement | ◐ | 4 | **触碰**（带阻滤波为滤波族未挖一侧） |
| T2-1 LGF · Technology | ◐ | 6 | 否 |
| T2-1 LGF · Counter / Comparator / Converter / Date and Timer / Signal Generators | ◐ | 16 | 否 |
| T2-2 LBP 基础工艺 | ◐ | 25 | **触碰**（驱动参数化族 → 加热驱动） |
| T2-5 Mod_PID | ◐（参数域已取尽） | 4 | **触碰**（矩阵明列仅剩「手自动切换细节」→ 本轮 1 件收口） |
| T2-6 Rockwell AOI | ◐ | 7 | **触碰**（设备级 AOI 粒度族「阀/电机/夹爪待挖」→ 夹爪件） |
| T2-7 PackML/OMAC | ◐ | 5 | **触碰**（停机原因语义，最小子集，不做 17 态全集） |
| T2-8 ISA-88 / ISA-18.2 / NE107 | ◐ | 11 | **触碰**（ISA-18.2 首出语义 + ISA-88 配方切换） |
| T1-1 OSCAT Basic | ◐ | 6 | 次源（信号整形惯例） |
| T1-3 OSCAT Network | ◐ | 4 | 次源（校验族分类） |
| T1-5 TcOpen | ◐ | 12 | **触碰**（契约-实现四件套 → 夹爪） |
| T1-6 PLCopen Motion | ◐ | 12 | **触碰**（停止/跟随误差公开语义） |
| 半导体 ESC 自研 | ◐ | 2 | 否 |

**覆盖率结论**：六大子库中 **DL_Motion 18 / DL_Process 26 / DL_Algo 28 为三薄库**，本轮按「薄库优先 + Level 0 快车道保底」配比：Base 4 + MathData 4 + **Algo 4** + **Device 3** + **Motion 3** + **Process 2**。

### 0.3 ⚠ 码位分段裁定（R61 教训执行：**实测为准，禁口头交接**）

派单前逐段实测 284 个 `.st` 的 `16#XXXX_YYYY` 占用，**发现指令给的「全部落 0001_ 段」前提与实际不符**：库内既有惯例是**按子库分大段**，不是全库共用 `0001_`。

| 子库 | 实际码段 | 网格规则（实测归纳） | 本轮起点（实测空闲） |
|---|---|---|---|
| DL_Base / DL_MathData | `16#0001_`（共用） | 信息级 `02xx` 顺序占；故障级 `02F1` 之后顺延至 `03xx` | 信息级 **022D~0244 已占** → **`0235`**；故障级 **`0305` 已占** → **`0306`** |
| DL_Algo | `16#0002_CCSS` | 组件序号 `CC`（十六进制 01~22 已用），槽位 `01~04` 信息级、`10~12` 故障级 | 组件序号 **`CC=23~26`**（实测 `2300~26FF` 全空闲） |
| DL_Device | `16#0003_` | 信息级 `01xx` 顺序（至 `0165`）；故障级 `02xx` 组态类 / `03xx` 工艺类 | 信息级 **`0166`**；故障级 **`032A`** |
| DL_Motion | `16#0004_` | 信息级 `01xx`（至 `01C6`）；故障级 `02xx`（至 `02D4`） | 信息级 **`01C7`**；故障级 **`02D5`** |
| DL_Process | `16#0005_` | 信息级 `01xx`（至 `01D1`）；故障级 `02xx`（至 `02FE`） | 信息级 **`01D2`**；故障级 **`02FF`** |

**实测校验脚本**（`_Staging_Raw/2026-11-16/_verify_r18.py`，已落盘，可复跑）：本轮 95 个候选码位 **CLASH 全为空**，20 个新名称与 registry 284 名 + 284 个文件名 **交集为空**。

```
seg 0001 n=40 unique=40 CLASH= []
seg 0002 n=20 unique=20 CLASH= []
seg 0003 n=10 unique=10 CLASH= []
seg 0004 n=15 unique=15 CLASH= []
seg 0005 n=10 unique=10 CLASH= []
name dup vs registry: []   name dup vs files: []
```

> **与指令的偏差声明（须创始人知悉）**：指令要求「20 件全部从 `0001_0235` / `0001_0306` 顺延」。实测若照办，DL_Algo/Device/Motion/Process 的 12 件将与各自子库既有码段惯例冲突（跨段越界，R30 教训复现）。故本轮**按子库分段**，`0001_` 段只承接 Base/MathData 8 件（`0235~0244` + `0306~031D`），其余 12 件落各自子库段。此为**规格级主动收窄**，已在本表留痕，收口时不得再改判。

---

## 1 R18 20 目标一览（锁定）

| # | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 |
|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_FirstOutLatch` | DL_Base | FB_DL_ | 多源故障首出锁存（同拍多源按序号最小仲裁，复位沿清锁存） | T2-8 ISA-18.2 公开首出语义 + 自研 | M | 1 |
| 2 | `FB_DL_PulseStretch` | DL_Base | FB_DL_ | 窄脉冲展宽至最小脉宽（可重触发 / 不可重触发双模） | T0-2 定时器变体 / T1-1 整形惯例次源 | M | 1 |
| 3 | `FB_DL_EdgeDivider` | DL_Base | FB_DL_ | 输入沿 1/N 分频（N 钳位、相位复位、奇偶占空对称） | T0-1 变体（矩阵「分频变体」） | M | 1 |
| 4 | `FC_DL_BitSegmentBlockMove` | DL_Base | FC_DL_ | 跨字多段位段一次搬运（段表驱动、先快照后写、重叠目标告警） | T2-1 LGF Bit Logic 待挖「多段一次搬」 | H | 1 |
| 5 | `FC_DL_Crc16Ccitt` | DL_MathData | FC_DL_ | CRC-16 三变体（CCITT-FALSE / XMODEM / KERMIT 反射）位算法 | T2-1 LGF Data Handling 待挖「CRC-16 反射」+ T1-3 次源 | M | 1 |
| 6 | `FC_DL_InterpolateTable2D` | DL_MathData | FC_DL_ | 二维标定表双线性插值（网格单调校验、退化格防除零、边界钳位） | T2-1 LGF Math 插值/标度子族 | H | 2 |
| 7 | `FC_DL_AffineTransformPoint` | DL_MathData | FC_DL_ | 2D 仿射点变换（旋转/缩放/平移合成，角度条件加减归一） | T2-1 LGF Math 待挖「仿射变换组合族」 | M | 2 |
| 8 | `FC_DL_CpkIndex` | DL_MathData | FC_DL_ | 过程能力指数 Cp/Cpk（σ 近零饱和、规格限合法性前置） | 自研 + ISO 22400 质量口径参考（T2-8 次源） | M | 2 |
| 9 | `FB_DL_GainScheduler` | DL_Algo | FB_DL_ | 分段增益调度（断点严格递增校验 + 切换迟滞 + 单拍切换沿） | T2-5 Mod_PID 参数域（分段增益） | H | 2 |
| 10 | `FB_DL_BumplessTransfer` | DL_Algo | FB_DL_ | 手/自动无扰切换（手动期跟踪 + 斜率过渡 + 偏差窗监视） | T2-5 明列「手自动切换」+ T1-1 反作用惯例次源 | H | 2 |
| 11 | `FB_DL_NotchFilter` | DL_Algo | FB_DL_ | 二阶陷波滤波（中心频率 + Q，抑制机械共振，参数变更保持状态） | T2-1 LGF Measurement 滤波族未挖一侧 | H | 3 |
| 12 | `FB_DL_ThermalI2tModel` | DL_Algo | FB_DL_ | I²t 一阶热累积模型（冷却时间常数、分级预警、dt 钳位） | 公开工程判据 I²t（保护电器手册口径）+ 自研 | M | 3 |
| 13 | `FB_DL_AxisFollowingErrorMonitor` | DL_Motion | FB_DL_ | 跟随误差监视（阈值倒置自交换 + 断带 + 确认窗分级） | T1-6 PLCopen 公开监视语义 + T2-4 次源 | M | 3 |
| 14 | `FB_DL_AxisSynchronizedStop` | DL_Motion | FB_DL_ | 受控同步停车（减速度斜坡 + 停止距离预估 + 完成确认，不驱动伺服） | T1-6 PLCopen MC_Stop 公开语义 | H | 3 |
| 15 | `FB_DL_BacklashCompensator` | DL_Motion | FB_DL_ | 换向背隙补偿（方向翻转叠加补偿量 + 到位偏差 EWMA 自学习） | T1-6 轴级补偿语义 + T2-2 背隙两阶段次源 | M | 3 |
| 16 | `I_DL_Gripper` | DL_Device | I_DL_ | 平行夹爪契约（开/合/在位/夹持力/故障五出口，方法 4 个） | T2-6 设备级 AOI 粒度族待挖「夹爪」+ T1-5 四件套 | M | 4 |
| 17 | `FB_DL_ParallelGripper` | DL_Device | FB_DL_ | 平行夹爪实现（三段动作 + 超时 + 在位与命令矛盾判定） | 同上（契约-实现对） | H | 4 |
| 18 | `FB_DL_SsrHeaterDrive` | DL_Device | FB_DL_ | 固态继电器加热驱动（周期 PWM + 占空钳位 + 无电流断线判定） | T2-2 LBP 驱动参数化族 | H | 4 |
| 19 | `FB_DL_DowntimeClassifier` | DL_Process | FB_DL_ | 停机原因自动分类（优先仲裁 + 最短时长过滤 + 未分类兜底） | T2-7 PackML/OMAC 停机原因语义（最小子集） | H | 4 |
| 20 | `FB_DL_ChangeoverSequence` | DL_Process | FB_DL_ | 换型换产五步顺控（排空→配方→下发→首件放行，逐步 TON） | T2-7 最小子集 + T2-8 ISA-88 配方切换 | H | 4 |

**分布**：DL_Base 4（#1-4）｜ DL_MathData 4（#5-8）｜ DL_Algo 4（#9-12）｜ DL_Device 3（#16-18）｜ DL_Motion 3（#13-15）｜ DL_Process 2（#19-20）= **20**
**类型**：FB 12 ｜ FC 7 ｜ INTERFACE 1
**复杂度**：H 11 ｜ M 9 ｜ L 0（无凑数件：每件均含独立防御逻辑或独立工况语义，**零纯类型复制变体**）

## 2 四批划分（每批 5 件，按域内聚 + 依赖方向从低到高）

| 批 | 主题 | 件 | 码段 | 依赖 |
|---|---|---|---|---|
| 批 1 | **Level 0 信号/位串/校验**（T0 变体 + LGF 位串收口） | #1-5 | `0001_0235~023E` / `0001_0306~0314` | 仅 Standard.library |
| 批 2 | **Level 0 标定/统计 → Level 1 控制律切换** | #6-10 | `0001_023F~0244` / `0001_0315~031D` + `0002_23xx/24xx` | 批 1 |
| 批 3 | **Level 1 滤波/热模型 → 运动监视/停车/补偿** | #11-15 | `0002_25xx/26xx` + `0004_01C7~01CC/02D5~02DD` | 批 2 |
| 批 4 | **Level 1 设备抽象 → Level 2 工艺模板** | #16-20 | `0003_0166~0169/032A~032F` + `0005_01D2~01D5/02FF~0304` | 批 1-3 |

---

## 3 批次需求规格（引脚级，可直接编码）

> 规格约定（**全批强制，逐件不再重复**）：
> - 所有 `REAL` 物理量在注释中带**单位**与**取值域**；所有阈值/限幅/超时**禁止裸数值**，一律 `VAR CONSTANT` 或输入引脚。
> - `TON` / `TOF` / `R_TRIG` / `F_TRIG` / `RTO` **在 `CASE` 之前无条件刷新**（红线 5，R1 规则），本批 6 件含定时器/边沿，评审必查。
> - 浮点判等一律 `ABS(a-b) < DL_FLOAT_EPS`；除法一律前置防零；数组一律先判界后索引；`WHILE` 一律带守卫计数（本批仅 #4 允许 `FOR`，禁 `WHILE`）。
> - 纯函数（FC）无顺序状态机时，头注释 `状态机` 段固定写 `N/A —— 纯函数无顺序状态机，无 CASE 可写`（R6 规则，照 `FC_DL_RealToLintSat` 原文）。
> - 每件 5 槽码位：**2 信息级（1 用 1 预留）+ 3 故障级（1 用 2 预留 或 2 用 1 预留）**，预留槽在头注释写「预留禁用（不得挪用）」。**接口件不占码位**（见 #16）。

### 3.1 批 1（Level 0：信号整形 / 位串 / 校验）

---

#### #1 `FB_DL_FirstOutLatch` —— 多源故障首出锁存

- **分类**：DL_Base ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：16 路故障源并行输入，首个到来的源被锁存为「首出原因」，后续源不得覆盖；复位上升沿清锁存。同拍多源时按**源序号最小**仲裁（与 `FB_DL_PortDiagAggregator` 首出三律同口径，避免两套仲裁规则）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 清锁存并冻结 |
| `bReset` | BOOL | — | — | 上升沿清首出锁存，当拍不重新锁存（防自杀） |
| `aSrcFault` | ARRAY[0..15] OF BOOL | — | — | 16 路故障源，索引即优先级（0 最高） |
| `uSrcCount` | UINT | 16 | 路 | 有效源数，域 1~16 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bAnyFault` | BOOL | — | 任一源故障（组合值，不锁存） |
| `bLatched` | BOOL | — | 首出已被锁存 |
| `uFirstIdx` | UINT | — | 首出源序号 0~15，未锁存时 = `DL_FIRSTOUT_NONE`(16#FFFF) |
| `uFaultWord` | WORD | — | 当拍故障位图（bit0 = 源 0） |
| `eErr` | UDINT | — | 错误码，0 = 正常 |
| `bError` | BOOL | — | 故障标志，`eErr` 非 0 且为故障级时 TRUE |

- **VAR CONSTANT**：`DL_FIRSTOUT_SRC_MAX : UINT := 16`（源上限）｜`DL_FIRSTOUT_NONE : UINT := 16#FFFF`（无首出哨兵）｜`DL_FIRSTOUT_BIT_MAX : UINT := 15`（位图上限）
- **VAR**：`fbTrigReset : R_TRIG`｜`uIdx : UINT`（扫描游标）｜`bAny : BOOL`
- **边界安全条件**：① `uSrcCount = 0` 或 `> DL_FIRSTOUT_SRC_MAX` → 置 0306，全输出回安全值（`uFirstIdx = NONE`），**不索引数组**；② 数组索引一律 `uIdx <= DL_FIRSTOUT_BIT_MAX` 前置判界（`FOR uIdx := 0 TO uSrcCount-1`，上界已由 ① 保证）；③ 复位沿优先于锁存（`IF fbTrigReset.Q THEN ... ELSIF NOT bLatched THEN ...`）；④ 无状态机（`CASE` 不需要）——但 `bLatched` 本身是锁存位，头注释须写「无 CASE，锁存由单比特保持，非法状态不可能出现」。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0235` | 信息 | 同拍多源故障，已按源序号最小仲裁为唯一首出 |
| `16#0001_0236` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_0306` | 故障 | 源数量参数越界（`uSrcCount` 不在 1~16），本拍不锁存 |
| `16#0001_0307` | 故障 | **预留禁用（不得挪用）** |
| `16#0001_0308` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-8 ISA-18.2（只借公开「首出 / 确认 / 锁存」生命周期语义，零代码行）+ 本库 `PortDiagAggregator` 首出三律复用

---

#### #2 `FB_DL_PulseStretch` —— 脉冲展宽（最小脉宽保持）

- **分类**：DL_Base ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：输入脉冲窄于 `tMinPulse` 时把输出保持到满足最小脉宽，解决「PLC 输出抖动 / 执行机构最小响应时间」问题；双模：可重触发（输入新沿重新计时）与不可重触发（计时不重启）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出立即复位 |
| `bIn` | BOOL | — | — | 脉冲输入（已在别处去抖则直连） |
| `tMinPulse` | TIME | T#50MS | ms | 最小输出脉宽，域 1~10 000 ms；0 = 直通（置 0309） |
| `bRetriggerable` | BOOL | TRUE | — | TRUE 重触发 / FALSE 不重启计时 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bOut` | BOOL | — | 展宽后输出 |
| `bStretching` | BOOL | — | 正在展宽（保持期） |
| `tRemain` | TIME | ms | 保持期剩余时间 |
| `uStretchCnt` | UDINT | 次 | 累计展宽次数 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR CONSTANT**：`DL_STRETCH_MIN : TIME := T#1MS`｜`DL_STRETCH_MAX : TIME := T#10S`
- **VAR**：`fbTrigIn : R_TRIG`｜`fbHold : TON`｜`bHoldActive : BOOL`
- **边界安全条件**：① `tMinPulse < DL_STRETCH_MIN`（含 0 / 负）→ 0309，**退化为直通**（`bOut := bIn`），不得进入定时器；② `tMinPulse > DL_STRETCH_MAX` → 钳位到 `DL_STRETCH_MAX` 并置 0237（信息级），钳位后才进 `TON`；③ `fbTrigIn` / `fbHold` **在周期首部无条件调用**（红线 5 高危件：`TON` 放入 `IF` 会让 `ET` 冻结，产生幽灵保持）；④ 输入脉冲短于 1 个扫描周期不可见——必须在头注释「采样约定」段声明（本库 `SineGenerator` 同口径）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0237` | 信息 | `tMinPulse` 超上限已钳位到 10 s |
| `16#0001_0238` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_0309` | 故障 | `tMinPulse` 非法（< 1 ms 或 0），本拍退化为直通 |
| `16#0001_030A` | 故障 | **预留禁用（不得挪用）** |
| `16#0001_030B` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T0-2 定时器变体（ADR：TON 语义 + 最小脉宽工况）；T1-1 OSCAT Basic 信号整形惯例次源（不复制函数体）

---

#### #3 `FB_DL_EdgeDivider` —— 边沿 1/N 分频

- **分类**：DL_Base ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：输入每 N 个上升沿输出 1 个单周期脉冲；支持相位复位与奇偶对称占空（N 为偶数时高电平占 N/2 个输入周期——用于「双作用气缸交替」「分料器奇偶道」等现场语义）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 计数冻结并清输出 |
| `bIn` | BOOL | — | — | 待分频信号（上升沿有效） |
| `uDivide` | UINT | 2 | 倍 | 分频比 N，域 1~`DL_DIV_MAX`；1 = 直通 |
| `bPhaseReset` | BOOL | — | — | 上升沿把计数与输出相位归零 |
| `bDutyHalf` | BOOL | FALSE | — | TRUE = 偶数 N 时输出方波（N/2 拍高 / N/2 拍低），FALSE = 单拍脉冲 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bOut` | BOOL | — | 分频输出 |
| `uCounter` | UINT | 拍 | 当前计数 0~N-1 |
| `uPulseCnt` | UDINT | 次 | 累计输出脉冲数（饱和于 `DL_DIV_CNT_MAX`） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR CONSTANT**：`DL_DIV_MAX : UINT := 1000`（分频比上限）｜`DL_DIV_CNT_MAX : UDINT := 16#FFFF_FFFE`（计数饱和值）
- **VAR**：`fbTrigIn : R_TRIG`｜`fbTrigPhase : R_TRIG`
- **边界安全条件**：① `uDivide = 0` → 0310，输出强制 FALSE，**不做 `MOD 0`**；② `uDivide > DL_DIV_MAX` → 钳位到 1000 并置 0239（信息级）；③ 计数回绕**必须用「比较 + 赋值」**（`IF uCounter >= uDivide THEN uCounter := 0;`），**禁止 `MOD`**（负数/回绕取余三平台不一致，R11 `RolloverCounter` 同纪律）；④ `bDutyHalf` 且 `uDivide` 为奇数 → 退化单拍脉冲并置 0239，不报故障；⑤ `R_TRIG` 周期首部无条件刷新。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0239` | 信息 | 分频比超上限已钳位，或奇数 N 请求方波已退化单拍 |
| `16#0001_023A` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_030C` | 故障 | `uDivide = 0`，输出强制 FALSE |
| `16#0001_030D` | 故障 | **预留禁用（不得挪用）** |
| `16#0001_030E` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T0-1 变体（矩阵 §1 T0-1 明列「+ 主从沿 / 分频变体」为未挖扩产点）

---

#### #4 `FC_DL_BitSegmentBlockMove` —— 跨字多段位段一次搬运

- **分类**：DL_Base ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `BOOL`（TRUE = 全部段搬运成功）｜ **复杂度**：H
- **功能**：段表驱动，把源字数组里的 K 个位段**一次调用**搬到目标字数组的对应位置（跨 32 位字边界）。矩阵 §5 T2-1 Bit Logic 行明列「多段一次搬」为待挖子族——现有 `BitArrayInsert` 只能搬 1 段，多段场景要调用方自己循环并把中间量交给调用方管，**这就是本件存在的工程理由**。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `auSrcBit` | ARRAY[0..7] OF UINT | — | bit | 各段源起始位（相对 128 位窗口），域 0~127 |
| `auDstBit` | ARRAY[0..7] OF UINT | — | bit | 各段目标起始位，域 0~127 |
| `auWidth` | ARRAY[0..7] OF UINT | — | bit | 各段宽度，域 1~32（单字内，禁跨两字出口） |
| `uSegCount` | UINT | 1 | 段 | 有效段数，域 1~8 |
| `auSrcWord` | ARRAY[0..3] OF DWORD | — | — | 源 128 位窗口（4×32 位，索引 0 = 最低字） |

- **VAR_IN_OUT**

| 引脚 | 类型 | 说明 |
|---|---|---|
| `auDstWord` | ARRAY[0..3] OF DWORD | 目标 128 位窗口，**由调用方注入，本件不初始化**（禁止在 FC 内赋初值，红线 R5 陷阱 5） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `uMovedSeg` | UINT | 段 | 实际搬运段数 |
| `uSkippedSeg` | UINT | 段 | 因越界/重叠被跳过的段数 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR CONSTANT**：`DL_SEG_MAX : UINT := 8`（段表上限）｜`DL_SEG_WIN_BITS : UINT := 128`（窗口位宽）｜`DL_SEG_WORD_BITS : UINT := 32`（单字位宽）｜`DL_SEG_WORD_MASK : DWORD := 16#FFFF_FFFF`｜`DL_SEG_MAX_LOOP : UINT := 8`（循环守卫，与段表同值，超限即 0311）
- **边界安全条件**：① 每段先判 `auWidth[i] >= 1 AND auWidth[i] <= 32 AND auSrcBit[i] <= 127 AND auDstBit[i] <= 127 AND (auSrcBit[i] + auWidth[i]) <= 128 AND (auDstBit[i] + auWidth[i]) <= 128`，任一不满足 → 该段跳过、`uSkippedSeg + 1`、置 023B（信息级），**绝不部分写入**；② **先快照后写**：先把所有段值读进 `auSnap : ARRAY[0..7] OF DWORD`，全部读完后统一写目标，防止「段 1 的写覆盖段 2 的源」（这是本件的核心防御，也是与 `BitArrayInsert` 的语义分界）；③ 宽度 32 走常量掩码 `DL_SEG_WORD_MASK`，**禁用 `SHL(x, 32)`**（未定义行为，R48 纪律）；字内移位量一律 `< 32`（宽度 ≤32 已保证）；④ 目标段互相重叠 → 按段序后者覆盖前者，置 023B 提示，不报故障（调用方语义）；⑤ `FOR` 循环上界用 `uSegCount`（已钳 1~8），另设 `nGuard` 硬上限 `DL_SEG_MAX_LOOP` 双保险，超限 → 0311；⑥ **禁止 `WHILE`**（本库纪律：批量位操作一律 `FOR` + 定长上界）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_023B` | 信息 | 存在越界/重叠段，已跳过并计数（`uSkippedSeg` 非 0） |
| `16#0001_023C` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_030F` | 故障 | 段数为 0 或 `auWidth` 全为 0，本拍不搬运 |
| `16#0001_0310` | 故障 | 段表指针自相矛盾（`uSegCount` 与有效段计数不符），本拍不搬运 |
| `16#0001_0311` | 故障 | 循环守卫超限（防死锁计数器触发），本拍结果作废 |

- **来源标签**：T2-1 LGF · Bit Logic（只借「读 / 写 / 监视 三层粒度 + 批量段」的组内分类，矩阵 §5 已收口 Extract/Insert/ChangeWatch 三件，本件补「多段一次搬」缺口；掩码 / 段表 / 码位 100% 自有）

---

#### #5 `FC_DL_Crc16Ccitt` —— CRC-16 三变体位算法

- **分类**：DL_MathData ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `WORD` ｜ **复杂度**：M
- **功能**：单函数覆盖 CRC-16 三个最常用参数集（同一多项式 0x1021 的三种参数化），解决现场「设备手册只写 CRC-16 CCITT，不说 init / 反射」导致的对接失败；库内 `FC_DL_Crc16Modbus` 已占 0x8005 反射族，本件补 0x1021 族。
- **参数集（联网核对结论，见 RAW_NOTES_R18 §2）**

| 枚举项 | poly | init | 反射(in/out) | xorout | "123456789" 校验值 |
|---|---|---|---|---|---|
| `eCrc16CcittFalse` | `16#1021` | `16#FFFF` | 否 / 否 | `16#0000` | **`16#29B1`** |
| `eCrc16Xmodem` | `16#1021` | `16#0000` | 否 / 否 | `16#0000` | **`16#31C3`** |
| `eCrc16Kermit` | `16#8408`（0x1021 的位反形式） | `16#0000` | 是 / 是 | `16#0000` | **`16#2189`** |

- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `auData` | ARRAY[0..255] OF BYTE | — | — | 待校验字节数组（定长 256，超长由 `uLen` 截断） |
| `uLen` | UINT | 0 | 字节 | 有效长度，域 0~256；0 = 空帧，返回 init 值 |
| `eVari` | `E_DL_Crc16Vari` | `eCrc16CcittFalse` | — | 参数集选择 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 说明 |
|---|---|---|
| `eErr` | UDINT | 错误码 |
| `bError` | BOOL | 故障标志 |
| `bValid` | BOOL | 结果可用（故障态 FALSE） |

- **VAR**：`uCrc : WORD`（寄存器）｜`uIdx : UINT`（字节游标）｜`nBit : INT`（位游标）｜`uByte : BYTE`｜`bReflect : BOOL`
- **VAR CONSTANT**：`DL_CRC16_LEN_MAX : UINT := 256`｜`DL_CRC16_POLY_MSB : WORD := 16#1021`｜`DL_CRC16_POLY_LSB : WORD := 16#8408`｜`DL_CRC16_INIT_FFFF : WORD := 16#FFFF`｜`DL_CRC16_INIT_ZERO : WORD := 16#0000`｜`DL_CRC16_BIT_MSB : WORD := 16#8000`｜`DL_CRC16_BIT_LSB : WORD := 16#0001`｜`DL_CRC16_CHECK_CCITT : WORD := 16#29B1` 等三个校验值常量（头注释「验收向量」段引用）
- **边界安全条件**：① `uLen > DL_CRC16_LEN_MAX` → 钳位 256 并置 023D（信息级，禁止越界读）；② `eVari` 不在枚举内 → 0313，返回 `16#0000`、`bValid := FALSE`（**枚举兜底用 `CASE ... ELSE`**，红线 4）；③ 位循环一律 `FOR nBit := 0 TO 7`（定长 8，无 `WHILE`）；④ 反射实现**不使用位反指令**（跨平台可用性风险），用「移位 + 判 LSB」循环，头注释注明；⑤ 空帧 `uLen = 0` 返回 init 值且 `bValid := TRUE`（协议合法输入，非故障）。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_023D` | 信息 | `uLen` 超 256 已截断，仅校验前 256 字节 |
| `16#0001_023E` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_0312` | 故障 | 数据长度为 0 且调用方要求 `bValid`（保留槽，防后续扩「空帧非法」协议方言） |
| `16#0001_0313` | 故障 | 变体枚举值非法（`CASE` 落 `ELSE`），返回 0 |
| `16#0001_0314` | 故障 | **预留禁用（不得挪用）** |

> `0312` 说明：本轮**不主动产生**该码，仅登记为「空帧非法」方言的预留归属；实现体内不得出现该码赋值（避免与「预留禁用」条款冲突）——故实际使用 = 023D（信息）+ 0313（故障），其余 3 槽预留。

- **来源标签**：T2-1 LGF · Data Handling（矩阵 §5 明列「校验族尚余 CRC-16 反射 / LWORD 累加和待挖」）；T1-3 OSCAT Network 校验族分类次源（不复制实现）。参数集与校验值经 **WebSearch 1 次**核对（crccalc / embedcalc / gophertrunk 三方一致）。

### 3.2 批 2（Level 0 标定/统计 → Level 1 控制律切换）

---

#### #6 `FC_DL_InterpolateTable2D` —— 二维标定表双线性插值

- **分类**：DL_MathData ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `REAL` ｜ **复杂度**：H
- **功能**：8×8 标定网格上做双线性插值，典型场景：温度—压力二维补偿表、阀门流量特性双参数表、视觉标定畸变修正。库内 `MultiPointLinear` 只做一维，二维场景现场长期靠梯形图硬编码。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `afGridX` | ARRAY[0..7] OF REAL | — | 用户单位 | X 轴网格（**必须严格递增**），有效项 `0..uCountX-1` |
| `afGridY` | ARRAY[0..7] OF REAL | — | 用户单位 | Y 轴网格（**必须严格递增**），有效项 `0..uCountY-1` |
| `afValue` | ARRAY[0..63] OF REAL | — | 用户单位 | 值表，**行主序**：索引 = `nIy * uCountX + nIx`（不用多维数组，避免平台差异） |
| `uCountX` | UINT | 2 | 点 | X 有效点数，域 2~8 |
| `uCountY` | UINT | 2 | 点 | Y 有效点数，域 2~8 |
| `fX` | REAL | 0.0 | 用户单位 | 待插值 X |
| `fY` | REAL | 0.0 | 用户单位 | 待插值 Y |
| `bExtrapolate` | BOOL | FALSE | — | FALSE = 边界钳位（推荐）；TRUE = 单格外延 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 说明 |
|---|---|---|
| `eErr` | UDINT | 错误码 |
| `bError` | BOOL | 故障标志 |
| `bValid` | BOOL | 结果可用 |
| `bOutOfGrid` | BOOL | 输入落在网格外（钳位或外延生效） |

- **VAR**：`nIx : INT`｜`nIy : INT`｜`fTx : REAL`｜`fTy : REAL`｜`fV00..fV11 : REAL`（四角值）｜`fSpanX : REAL`｜`fSpanY : REAL`
- **VAR CONSTANT**：`DL_2D_MAX : UINT := 8`｜`DL_2D_CELLS : UINT := 64`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `uCountX/uCountY` 不在 2~8 → 0315，返回 `afValue[0]`、`bValid := FALSE`（**先判界再索引，禁止越界**）；② 网格单调校验：逐点 `afGridX[i] > afGridX[i-1]`（用 `>` 而非浮点判等），违反 → 0315；③ **退化格防除零**：`fSpanX := afGridX[nIx+1] - afGridX[nIx]`，`IF ABS(fSpanX) <= DL_FLOAT_EPS THEN fTx := 0.0; 置 023F`，`fSpanY` 同；**除法一律在防零闸之后**；④ 非有限输入（`fX`/`fY` NaN/±INF，用 `x <> x` + 幅值判）→ 0316，返回 `afValue[0]`；⑤ 定位用线性扫描（点数 ≤8，避免二分边界 off-by-one），扫描上界 `uCountX-2`；⑥ 边界钳位时置 `bOutOfGrid := TRUE` + 023F（信息级），不外插出荒谬值。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_023F` | 信息 | 输入落网格外已钳位，或遇退化格（跨度≈0）按该角值直取 |
| `16#0001_0240` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_0315` | 故障 | 点数/网格非法（越界、非严格递增），返回首值 |
| `16#0001_0316` | 故障 | 插值坐标非有限（NaN / ±INF），返回首值 |
| `16#0001_0317` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-1 LGF · Math（只借「标度 / 插值属 Math 组」的分类事实与参数域组织；双线性公式为公开数学，实现、码位、行主序约定 100% 自有）

---

#### #7 `FC_DL_AffineTransformPoint` —— 2D 仿射点变换

- **分类**：DL_MathData ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `BOOL` ｜ **复杂度**：M
- **功能**：单次完成「绕原点旋转 → 各轴缩放 → 平移」合成，输出变换后坐标。现场语义：视觉像素坐标 → 机械 mm 坐标（含相机安装角偏差）、纠偏平台坐标映射。矩阵 §5 明列「仿射变换组合族待挖」。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `fX` | REAL | 0.0 | 用户单位 | 源点 X |
| `fY` | REAL | 0.0 | 用户单位 | 源点 Y |
| `fRotDeg` | REAL | 0.0 | ° | 旋转角，域 -720.0~720.0（正 = 逆时针）；超出用条件加减归一 |
| `fScaleX` | REAL | 1.0 | 比值 | X 缩放，域 0.001~1000.0，**禁 0** |
| `fScaleY` | REAL | 1.0 | 比值 | Y 缩放，域 0.001~1000.0，**禁 0** |
| `fTx` | REAL | 0.0 | 用户单位 | X 平移量 |
| `fTy` | REAL | 0.0 | 用户单位 | Y 平移量 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fOutX` | REAL | 用户单位 | 变换后 X |
| `fOutY` | REAL | 用户单位 | 变换后 Y |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 结果可用 |

- **VAR**：`fAngNorm : REAL`（归一后角度 [°]）｜`fRad : REAL`｜`fCos : REAL`｜`fSin : REAL`
- **边界安全条件**：① 角度归一**用条件加减（`WHILE fAngNorm > 360.0 DO fAngNorm := fAngNorm - 360.0; nGuard+1;`）——但更稳妥用两次 `IF`**：`IF fAngNorm > 360.0 THEN fAngNorm := fAngNorm - 360.0 * TRUNC(fAngNorm / 360.0);`（禁 `MOD` 用于浮点；禁无限 `WHILE`，若用 `WHILE` 必带 `DL_MAX_LOOP` 守卫，本件优选 `TRUNC` 单算式路径）；② `ABS(fScaleX) < 1E-6 OR ABS(fScaleY) < 1E-6` → 0318（缩放为 0 使变换不可逆，现场必错），返回 `fX/fY` 原值不加平移、`bValid := FALSE`；③ 任一输入非有限 → 0319，输出 0、`bValid := FALSE`；④ 三角函数直接调内建 `SIN/COS`（**禁止重实现**，T0 判据 2），但角度先归一以保精度；⑤ 结果非有限复检（1e38 量级缩放 × 大坐标可溢出）→ 0319。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0241` | 信息 | 旋转角超 ±360° 已归一（不影响结果，仅提示参数域） |
| `16#0001_0242` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_0318` | 故障 | 缩放因子为 0（变换不可逆），返回原点值 |
| `16#0001_0319` | 故障 | 输入或中间结果非有限（NaN / ±INF / 溢出） |
| `16#0001_031A` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-1 LGF · Math（矩阵 §5「仿射变换组合族待挖」；旋转/缩放/平移合成顺序为本库自有规格，码位与错误分级自有）

---

#### #8 `FC_DL_CpkIndex` —— 过程能力指数 Cp / Cpk

- **分类**：DL_MathData ｜ **前缀**：`FC_DL_` ｜ **类型**：FUNCTION → `REAL`（返回 Cpk）｜ **复杂度**：M
- **功能**：由样本数组算 Cp、Cpk、均值、样本标准差（n-1 分母），供质量工站实时判工序能力（Cpk < 1.33 报警）。与 `SignalStatistics` 的分界：本件**以规格限为输入、以能力指数为出口**，不做通用统计量输出。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `afSample` | ARRAY[0..63] OF REAL | — | 用户单位 | 样本数组，有效项 `0..uCount-1` |
| `uCount` | UINT | 0 | 个 | 样本数，域 2~64 |
| `fLsl` | REAL | 0.0 | 用户单位 | 规格下限 |
| `fUsl` | REAL | 1.0 | 用户单位 | 规格上限，**必须 > fLsl** |
| `fCpkSat` | REAL | 10.0 | — | Cpk 饱和上限（σ 近零时输出此值），域 1.0~100.0 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fCp` | REAL | — | 潜在能力指数（不含偏移） |
| `fCpk` | REAL | — | 实际能力指数（返回值的镜像，便于 HMI 同拍读取） |
| `fMean` | REAL | 用户单位 | 样本均值 |
| `fSigma` | REAL | 用户单位 | 样本标准差（n-1 分母） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bValid` | BOOL | — | 结果可用 |
| `bSaturated` | BOOL | — | 因 σ 近零饱和 |

- **VAR**：`uIdx : UINT`｜`fSum : REAL`｜`fSumSq : REAL`｜`fDev : REAL`｜`fSpan : REAL`｜`fUpper : REAL`｜`fLower : REAL`
- **VAR CONSTANT**：`DL_CPK_MAX_N : UINT := 64`｜`DL_CPK_MIN_N : UINT := 2`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `uCount < 2 OR uCount > 64` → 031B（n<2 时 σ 无定义），返回 0、`bValid := FALSE`；② `fUsl <= fLsl`（浮点比较用 `<=` 而非判等，容差 `DL_FLOAT_EPS` 内视为非法）→ 031C；③ `fSigma <= DL_FLOAT_EPS` → 饱和：`fCp/fCpk := fCpkSat`、`bSaturated := TRUE`、置 0243（信息级，**不置 bError**——常数样本是合法工况，非故障）；④ 累加用 `LREAL` 中间量（`fSumSq` 声明为 LREAL）防 64 点大值平方溢出（R10 `CalcDistance3D` 同纪律）；⑤ `fSpan := 6.0 * fSigma` 后除，除数已由 ③ 保证；⑥ 非有限样本（NaN/±INF）逐点剔除并计入 `uKicked`，剔除后 `uCount < 2` → 031B。
- **错误码 5 槽**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0001_0243` | 信息 | σ 近零，Cp/Cpk 已按饱和上限输出（常数样本，合法工况） |
| `16#0001_0244` | 信息 | **预留禁用（不得挪用）** |
| `16#0001_031B` | 故障 | 有效样本数不足（<2），无法计算 |
| `16#0001_031C` | 故障 | 规格限非法（`fUsl <= fLsl`） |
| `16#0001_031D` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：自研（Cp/Cpk 为公开统计定义）；ISO 22400-2 质量口径仅作术语参考（T2-8 次源，不复制条款文本）

---

#### #9 `FB_DL_GainScheduler` —— 分段增益调度

- **分类**：DL_Algo ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：按调度变量（温度/流量/负载率）落在哪个断点区间，输出对应一组 Kp/Ki/Kd。解决「升温段要大 P、保温段要强 I」这类分段整定需求。**只输出增益，不实现积分**——无扰由 `FB_DL_BumplessTransfer` 与 PID 侧承担（职责边界写进头注释，防与 `CascadePid` 打架）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出保持末次并冻结段号 |
| `bReset` | BOOL | — | — | 上升沿强制回到段 0 并清切换沿 |
| `fScheduleVar` | REAL | 0.0 | 用户单位 | 调度变量（如温度 [°C]） |
| `afBreakpoint` | ARRAY[0..3] OF REAL | — | 用户单位 | 分段上界断点，有效项 `0..uSegCount-2`，**必须严格递增** |
| `afKp` | ARRAY[0..3] OF REAL | — | — | 各段比例增益，有效项 `0..uSegCount-1` |
| `afKi` | ARRAY[0..3] OF REAL | — | 1/s | 各段积分增益 |
| `afKd` | ARRAY[0..3] OF REAL | — | s | 各段微分增益 |
| `uSegCount` | UINT | 2 | 段 | 段数，域 2~4 |
| `fHysteresis` | REAL | 0.5 | 用户单位 | 段边界迟滞带半宽，域 0.0~100.0，0 = 无迟滞 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fKp` | REAL | — | 当前段 Kp |
| `fKi` | REAL | 1/s | 当前段 Ki |
| `fKd` | REAL | s | 当前段 Kd |
| `uActiveSeg` | UINT | 段 | 当前段号 0~3 |
| `bSwitched` | BOOL | — | 段切换单周期脉冲 |
| `uSwitchCnt` | UDINT | 次 | 累计切换次数（抖动监视） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR CONSTANT**：`DL_GS_SEG_MAX : UINT := 4`｜`DL_GS_SEG_MIN : UINT := 2`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `uSegCount` 不在 2~4 → 2311，输出全 0、不索引数组；② 断点严格递增校验 `afBreakpoint[i] > afBreakpoint[i-1]`（浮点用 `>`），违反 → 2310；③ 段定位用**迟滞判据**：当前段需 `fScheduleVar < 断点 - fHysteresis`（降段）或 `> 断点 + fHysteresis`（升段），**防止边界抖动导致增益来回跳**（这是本件的核心防御，替代「无迟滞直接比较」的常见写法）；④ 复位沿优先于定位；⑤ 非有限调度变量 → 保持末次增益并置 2310 之外的**信息级 2301**（不中断生产），仅 `bError` 不置；⑥ `bSwitched` 每拍先清后置（单周期脉冲）。
- **错误码 5 槽（`16#0002_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2301` | 信息 | 调度变量非有限或变化被迟滞带抑制（保持当前段） |
| `16#0002_2302` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2310` | 故障 | 断点表非严格递增（非法组态） |
| `16#0002_2311` | 故障 | 段数越界（不在 2~4） |
| `16#0002_2312` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-5 Mod_PID_Control（只借「参数域约束」组织方式，矩阵 §5 判定其参数域已取尽，仅剩手自动/分段这类手册细节；迟滞判据、码位、状态化输出 100% 自有）

---

#### #10 `FB_DL_BumplessTransfer` —— 手/自动无扰切换

- **分类**：DL_Algo ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：手动→自动切换时，输出从「手动末值」以限斜率过渡到「PID 输出」，杜绝阀门/变频器被给定量阶跃冲击（水锤、皮带打滑、加热丝浪涌都是这一类）。手动期持续把 PID 输出跟踪到当前实际输出（反算跟踪），使自动接管时积分项不突跳。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出 0 并清过渡 |
| `bReset` | BOOL | — | — | 上升沿放弃过渡，直接取自动值（调试用，现场慎用） |
| `bAuto` | BOOL | FALSE | — | TRUE = 自动 / FALSE = 手动 |
| `fManualOut` | REAL | 0.0 | % | 手动给定（`bAuto = FALSE` 时生效），域 -100.0~100.0 |
| `fPidOut` | REAL | 0.0 | % | PID 输出（由上层 PID 注入，**本件不内联 PID**） |
| `fTrackVal` | REAL | 0.0 | % | 手动期跟踪目标（一般接实际阀位反馈），域 -100.0~100.0 |
| `fRateMax` | REAL | 10.0 | %/s | 过渡最大变化率，域 0.01~1000.0 |
| `fDevWindow` | REAL | 5.0 | % | 过渡偏差提示窗，超出置信息码 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fOut` | REAL | % | 最终输出 |
| `bTracking` | BOOL | — | 手动期跟踪中 |
| `bInTransfer` | BOOL | — | 自动接管过渡中 |
| `fDeviation` | REAL | % | 当前输出与 PID 输出偏差 |
| `tInTransfer` | TIME | ms | 已过渡时长 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset : R_TRIG`｜`eState : E_DL_TransferState`（同文件枚举：`eIdle`/`eManual`/`eTransfer`/`eAuto`/`eFault`）｜`fLastOut : REAL`｜`fStep : REAL`｜`tLast : TIME`｜`tDelta : TIME`
- **VAR CONSTANT**：`DL_TR_MAX_RATE : REAL := 1000.0`｜`DL_TR_MIN_RATE : REAL := 0.01`｜`DL_TR_OUT_LIM : REAL := 100.0`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fRateMax` 不在 `DL_TR_MIN_RATE~DL_TR_MAX_RATE` → 2410，过渡禁用（直接取 PID 输出）并置 `bError`；② `tDelta` 计算用 `TIME_TO_LREAL` 显式换算（禁隐式），`fStep := fRateMax * tDeltaSec`，`tDelta <= T#0MS`（首拍）时 `fStep := 0.0` **不用 0 除**；③ 过渡判据用 `ABS(fPidOut - fLastOut) <= fStep + DL_FLOAT_EPS`（浮点判等**必须带容差**）→ 收敛完成转 `eAuto`；④ 输出双向限幅 `MIN(MAX(x, -DL_TR_OUT_LIM), DL_TR_OUT_LIM)`（只做单侧限幅是本库常见缺陷，头注释明写双侧）；⑤ **状态机 `CASE` + `ELSE` 兜底**（`ELSE` → `eFault` + 2411），`fbTrigReset` 周期首部无条件刷新；⑥ `fPidOut`/`fTrackVal` 非有限 → 保持 `fLastOut` + 2411。
- **错误码 5 槽（`16#0002_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2401` | 信息 | 过渡中偏差超提示窗（正常现象，非故障） |
| `16#0002_2402` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2410` | 故障 | 斜率参数非法（不在 0.01~1000 %/s），过渡禁用 |
| `16#0002_2411` | 故障 | 给定非有限（NaN/±INF）或状态机落 ELSE 兜底 |
| `16#0002_2412` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-5 Mod_PID_Control（矩阵 §5：「参数域已取尽，后续仅剩手自动切换手册细节」——本件即该细节的收口件）；T1-1 OSCAT Basic 反作用增益惯例作次源对照。无扰过渡律、状态机、码位 100% 自有。

---

### 3.3 批 3（Level 1 滤波/热模型 → 运动监视/停车/补偿）

---

#### #11 `FB_DL_NotchFilter` —— 二阶陷波滤波

- **分类**：DL_Algo ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：抑制固定频率机械共振（丝杠固有频率、皮带拍频、伺服 300~800 Hz 尖叫）的带阻滤波。库内 `LowPassFilter`/`HighPassFilter`/`SecondOrderFilter` 都不带「中心频率 + Q 可调」的带阻形态，矩阵 §5 Measurement 行明列滤波族未挖一侧。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 时输出跟随输入并保持状态 |
| `bReset` | BOOL | — | — | 上升沿清内部状态（历史值清零） |
| `fIn` | REAL | 0.0 | 用户单位 | 输入信号（一般接位置/速度反馈） |
| `fCenterFreq` | REAL | 50.0 | Hz | 陷波中心频率，域 0.1~1 000.0 |
| `fQuality` | REAL | 2.0 | — | 品质因数 Q，域 0.1~50.0（越大陷波越窄） |
| `tSampleTime` | TIME | T#10MS | ms | 采样周期，域 1~1 000 ms（**必须等于实际任务周期**） |
| `fOutLimit` | REAL | 1.0E6 | 用户单位 | 输出幅值限幅（防系数病态导致发散），域 >0 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fOut` | REAL | 用户单位 | 滤波输出 |
| `bSaturated` | BOOL | — | 输出被限幅（滤波发散前兆） |
| `uCoeffRev` | UDINT | 次 | 系数重算次数（参数在线改动监视） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset : R_TRIG`｜`fB0/fB1/fB2/fA1/fA2 : REAL`（归一化系数）｜`fX1/fX2/fY1/fY2 : REAL`（历史值）｜`fOmega : REAL`｜`fAlpha : REAL`｜`fFs : REAL`｜`fPrevFc/fPrevQ/fPrevTs : REAL`（参数变更检测）
- **VAR CONSTANT**：`DL_NOTCH_PI2 : REAL := 6.283185307`｜`DL_NOTCH_NYQ_RATIO : REAL := 0.45`（中心频率上限 = 0.45×采样频率）｜`DL_NOTCH_Q_MIN : REAL := 0.1`｜`DL_NOTCH_Q_MAX : REAL := 50.0`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `tSampleTime <= T#0MS` → 2510，输出跟随输入（旁路）并置故障；② 采样频率 `fFs := 1000.0 / tSampleTime秒`，若 `fCenterFreq >= DL_NOTCH_NYQ_RATIO * fFs` → 2511（**奈奎斯特上限硬闸**，超了陷波会变成放大器）；`fQuality` 不在 0.1~50.0 → 2511；③ 系数用公开双线性变换式在线计算，`fAlpha := SIN(fOmega) / (2.0 * fQuality)`，`a0 := 1.0 + fAlpha` **前置防零判据**（`ABS(a0) > DL_FLOAT_EPS` 才除，否则 2511）；④ 参数变更（`fPrevFc/fPrevQ/fPrevTs` 与当前比对，浮点用 `ABS(...) > DL_FLOAT_EPS`）→ 重算系数、**保留历史状态、不清零**，置 2501（信息级，在线改参会瞬时扰动但不该断控制）；⑤ 输出限幅 `MIN(MAX(y, -fOutLimit), fOutLimit)` 双侧，超限置 `bSaturated` + 2501；⑥ 差分级联式用直接 II 型（`y = b0 x + z1; z1 = b1 x - a1 y + z2; ...`）减状态量，头注释声明；⑦ `fbTrigReset` 周期首部无条件刷新。
- **错误码 5 槽（`16#0002_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2501` | 信息 | 参数在线变更已重算系数（状态保留），或输出限幅生效 |
| `16#0002_2502` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2510` | 故障 | 采样周期非法（≤0），旁路输出 |
| `16#0002_2511` | 故障 | 中心频率超奈奎斯特 0.45 倍 / Q 越界 / 系数分母近零，旁路输出 |
| `16#0002_2512` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-1 LGF · Measurement（只借「滤波归测量组」的分类事实）；陷波器双线性变换为公开数字信号处理公式，系数式、闸门顺序、码位 100% 自有

---

#### #12 `FB_DL_ThermalI2tModel` —— I²t 一阶热累积模型

- **分类**：DL_Algo ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：按 `dθ/dt = ((I/Ir)² − θ) / τ` 一阶热模型累积「热容量利用率」，超阈值分级预警/跳闸，用于电机、加热丝、线缆、制动电阻的过载热保护。与 `VfdDrive` 内部过载的分界：本件是**可复用的独立热模型**，不绑定任何驱动。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 冻结热状态（**不清零**，模拟真实冷却慢过程需保持） |
| `bReset` | BOOL | — | — | 上升沿把热容量清零并清跳闸（仅调试/检修用） |
| `fCurrent` | REAL | 0.0 | A | 实测电流（RMS 或等效），域 0.0~1.0E5 |
| `fRatedCurrent` | REAL | 1.0 | A | 额定电流 `Ir`，域 0.001~1.0E5 |
| `tThermalTimeConst` | TIME | T#60S | s | 热时间常数 τ，域 1 s~3600 s |
| `tSampleTime` | TIME | T#10MS | ms | 采样周期，域 1~1000 ms |
| `fAlarmLevel` | REAL | 0.85 | — | 预警阈值（热容量利用率），域 0.1~0.99 |
| `fTripLevel` | REAL | 1.00 | — | 跳闸阈值，域 `fAlarmLevel`+0.01~2.0 |
| `bTripEnable` | BOOL | TRUE | — | 跳闸输出使能（调试期可关，只监视不跳） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fThermalLoad` | REAL | — | 热容量利用率 θ，0.0~1.0（可短暂 >1.0 后回落） |
| `bAlarm` | BOOL | — | 预警（θ ≥ fAlarmLevel） |
| `bTrip` | BOOL | — | 跳闸（θ ≥ fTripLevel 且 bTripEnable） |
| `tCoolRemain` | TIME | s | 从当前 θ 冷却到 0.5 的估算剩余时间 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset : R_TRIG`｜`fRatioSq : REAL`｜`fDtSec : REAL`｜`fTheta : REAL`｜`fTauSec : REAL`
- **VAR CONSTANT**：`DL_I2T_LOAD_MAX : REAL := 2.0`（θ 上限钳位，防离散抖动发散）｜`DL_I2T_DT_MAX_RATIO : REAL := 0.1`（dt 不得超过 τ 的 10%，否则欧拉离散失真→判故障）｜`DL_I2T_COOL_TARGET : REAL := 0.5`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fRatedCurrent <= DL_FLOAT_EPS` → 2610，θ 冻结、置故障；② `tThermalTimeConst < T#1S` 或 `tSampleTime < T#1MS` → 2611；③ `fDtSec > DL_I2T_DT_MAX_RATIO * fTauSec` → 2611（**离散失真硬闸**：任务周期远大于 τ 时欧拉积分不可信，宁可报故障也不出假安全值）；④ 欧拉更新 `fTheta := fTheta + (fRatioSq - fTheta) * fDtSec / fTauSec`（分母已判零），随后 `fTheta := MIN(MAX(fTheta, 0.0), DL_I2T_LOAD_MAX)` 双侧钳位；⑤ `fCurrent` 非有限 → 保持 θ 并置 2610；⑥ 冷却剩余时间用对数解析解 `t = τ·ln(θ/0.5)`，**θ ≤ 0.5 时直接输出 0 不取对数**（定义域闸）；⑦ 阈值关系 `fTripLevel > fAlarmLevel` 不满足时自动交换 + 0241?（本件信息槽为 2601）→ 置 2601 并交换。
- **错误码 5 槽（`16#0002_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0002_2601` | 信息 | 阈值关系倒置已自动交换 / θ 达钳位上限已限制 |
| `16#0002_2602` | 信息 | **预留禁用（不得挪用）** |
| `16#0002_2610` | 故障 | 额定电流非法（≤EPS）或电流非有限，θ 冻结 |
| `16#0002_2611` | 故障 | 时间常数/采样周期非法，或 dt 超 τ 的 10%（离散失真） |
| `16#0002_2612` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：自研（I²t 为公开热保护工程判据，见 IEC 60255 反时限特性的一般口径，不复制条款文本）；一阶热模型离散化、闸门、码位 100% 自有

---

#### #13 `FB_DL_AxisFollowingErrorMonitor` —— 跟随误差监视

- **分类**：DL_Motion ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：消费「指令位置 + 实际位置」两个快照，算跟随误差并做三级判定（正常 / 预警 / 故障），带确认时间与静止带豁免。**不自造轴状态、不发运动指令**（R13 `PassiveHomingMonitor` 纪律：轴状态唯一属主在 `FB_DL_SingleAxis`）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 清判定并按正常输出 |
| `bReset` | BOOL | — | — | 上升沿清故障与计时 |
| `fSetPosition` | REAL | 0.0 | mm | 指令位置（由运动层注入） |
| `fActPosition` | REAL | 0.0 | mm | 实际位置反馈 |
| `fWarnLimit` | REAL | 0.5 | mm | 预警阈值（>0） |
| `fFaultLimit` | REAL | 2.0 | mm | 故障阈值（>0） |
| `tConfirmTime` | TIME | T#200MS | ms | 越限持续确认时间，0 = 立即判定 |
| `fStandstillBand` | REAL | 0.05 | mm | 静止带：误差在此内视为正常（噪声容忍） |
| `bInMotion` | BOOL | FALSE | — | 运动中标志（FALSE 时确认时间不累加，防静止噪声误跳） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fError` | REAL | mm | 跟随误差（`fSetPosition - fActPosition`） |
| `fErrorAbs` | REAL | mm | 误差绝对值 |
| `bWarn` | BOOL | — | 预警（越预警阈值超确认时间） |
| `bFault` | BOOL | — | 故障（越故障阈值超确认时间） |
| `tOverTime` | TIME | ms | 当前越限已持续时间 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志（参数类，与 bFault 区分：bFault = 工艺故障） |

- **VAR**：`fbTrigReset : R_TRIG`｜`fbConfirmWarn : TON`｜`fbConfirmFault : TON`｜`fWarnEff : REAL`｜`fFaultEff : REAL`
- **VAR CONSTANT**：`DL_FE_MIN_LIMIT : REAL := 0.001`（阈值下限 [mm]）｜`DL_FE_MAX_LIMIT : REAL := 1.0E4`（阈值上限 [mm]）｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① 阈值倒置（`fWarnLimit >= fFaultLimit`）→ **自动交换**并置 01C7（信息级，现场参数填反极常见，直接报故障会锁死生产）；② 阈值越 `DL_FE_MIN_LIMIT~DL_FE_MAX_LIMIT` → 钳位 + 01C7；③ `fSetPosition`/`fActPosition` 非有限 → 02D5，输出保持末次有效误差，判定冻结；② `bInMotion = FALSE` → 确认定时器输入强制 FALSE（**`TON` 仍在本拍无条件调用**，只改 `IN` 引脚，不得把调用放进 `IF`）；④ `fErrorAbs <= fStandstillBand` → 视为正常，`tOverTime := T#0MS`；⑤ 判定优先级：故障 > 预警；⑥ `eErr`（参数/信号类）与 `bFault`（工艺跟随超差）**分开出口**，头注释明写（HMI 分组依据）。
- **错误码 5 槽（`16#0004_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0004_01C7` | 信息 | 阈值倒置已自动交换 / 阈值超域已钳位 |
| `16#0004_01C8` | 信息 | **预留禁用（不得挪用）** |
| `16#0004_02D5` | 故障 | 位置快照非有限（NaN/±INF），判定冻结 |
| `16#0004_02D6` | 故障 | 越限持续超确认窗（与 `bFault` 同拍置位，码为可追溯标识） |
| `16#0004_02D7` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T1-6 PLCopen（只借「跟随误差监视属运动控制监视功能」的公开语义，不自造轴状态机）；T2-4 S7-1500 监视参数域次源。确认窗、静止带、交换逻辑 100% 自有

---

#### #14 `FB_DL_AxisSynchronizedStop` —— 受控同步停车

- **分类**：DL_Motion ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：给上层运动接口生成「按固定减速度斜坡停车」的指令序列，并预估停止距离与完成时刻；不直接驱动伺服（零全局耦合）。用于安全门打开、料尽、下游堵塞等需要「减速停而非自由滑行」的工况。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 清指令 |
| `bExecute` | BOOL | — | — | 上升沿启动停车序列 |
| `bAbort` | BOOL | — | — | 上升沿中止并转故障态（急停由安全回路直连，不经本件） |
| `bReset` | BOOL | — | — | 上升沿清故障回 Idle |
| `fActVelocity` | REAL | 0.0 | mm/s | 当前速度（运动层注入） |
| `fActPosition` | REAL | 0.0 | mm | 当前位置（用于算停止点） |
| `fDeceleration` | REAL | 500.0 | mm/s² | 停车减速度，域 1.0~1.0E5 |
| `tDelayTime` | TIME | T#100MS | ms | 从发出到实际减速的传动延迟，域 0~2000 ms |
| `fVelocityEps` | REAL | 0.5 | mm/s | 判静止的速度阈值，域 0.01~100.0 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bBusy` | BOOL | — | 停车进行中 |
| `bDone` | BOOL | — | 已完成（单周期脉冲） |
| `bStopped` | BOOL | — | 已静止（速度 < eps 且持续确认） |
| `fStopDistance` | REAL | mm | 预估停止距离（延迟段 + 减速段） |
| `fStopPosition` | REAL | mm | 预估停止位置 |
| `uState` | UINT | — | 状态镜像（0 Idle / 10 Ramping / 20 Settling / 30 Done / 99 Fault，仅供 HMI） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigExec / fbTrigAbort / fbTrigReset : R_TRIG`｜`fbSettle : TON`｜`eState : E_DL_StopState`（同文件枚举 `eIdle`/`eRamping`/`eSettling`/`eDone`/`eFault`）｜`fStopDistCalc : REAL`｜`tRampCalc : TIME`
- **VAR CONSTANT**：`DL_STOP_DEC_MIN : REAL := 1.0`｜`DL_STOP_DEC_MAX : REAL := 1.0E5`｜`DL_STOP_SETTLE : TIME := T#100MS`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fDeceleration < DL_STOP_DEC_MIN` → 02D8（减速度为 0/负会让「停车」永不完成，是本件的首要防御），转 `eFault`、`bBusy := FALSE`；② `fDeceleration > DL_STOP_DEC_MAX` → 钳位 + **不作为故障**（高减速度是合法急停辅助），钳位值写入头注释；③ `fStopDistance := fAbsVel * tDelay秒 + fAbsVel² / (2.0 * fDecel)`，除号前已由 ① 保证非零；④ `fActVelocity` 非有限 → 02D9，转 `eFault`；⑤ `|fActVelocity| <= fVelocityEps` → 直接 `eSettling` 并置 01C9（信息级：本来已停，无需斜坡——**避免 TON 空转与假 Done**）；⑥ `fbSettle` 在周期首部无条件刷新，`IN := (eState = eSettling)`；⑦ **`CASE` + `ELSE` 兜底**：`ELSE` 分支固定置 `02DA`（本件为此**专用兜底码**，故 02DA 不列为预留）；⑧ `bAbort` 上升沿 → `eFault` 并清 `bBusy`（急停本体不在此，头注释声明）。
- **错误码 5 槽（`16#0004_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0004_01C9` | 信息 | 启动时已静止（速度低于阈值），跳过斜坡直接判完成 |
| `16#0004_01CA` | 信息 | **预留禁用（不得挪用）** |
| `16#0004_02D8` | 故障 | 减速度非法（< 1 mm/s²），停车不可完成 |
| `16#0004_02D9` | 故障 | 速度/位置快照非有限（NaN/±INF） |
| `16#0004_02DA` | 故障 | 状态机落 `ELSE` 兜底（非法状态，一律回安全态）——**用途固定，不得改作他用** |

- **来源标签**：T1-6 PLCopen Motion（只借 `MC_Stop`/`MC_Halt` 的公开「按减速度停车 + 完成确认」语义；不实现运动核、不定义轴状态机）；距离解析式为本库自有

---

#### #15 `FB_DL_BacklashCompensator` —— 换向背隙补偿

- **分类**：DL_Motion ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：M
- **功能**：指令方向翻转瞬间在给定量上叠加一个方向性补偿量，抵消齿轮/丝杠反向间隙；并在到位后按实测偏差用 EWMA 自学习背隙估计（现场背隙会随磨损变化）。与 `FB_DL_RollerGapAdjust` 的分界：后者是**工艺辊缝调整顺控**，本件是**轴级给定量修正**。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 输出 = 指令（旁路） |
| `bReset` | BOOL | — | — | 上升沿清方向记忆与学习值 |
| `fCmdPosition` | REAL | 0.0 | mm | 指令位置（来自插补/定位） |
| `fActPosition` | REAL | 0.0 | mm | 实际位置反馈（自学习用） |
| `fBacklash` | REAL | 0.10 | mm | 背隙标称值，域 0.0~10.0 |
| `bAutoLearn` | BOOL | FALSE | — | TRUE 时按到位偏差 EWMA 更新背隙 |
| `fLearnTol` | REAL | 0.10 | mm | 学习容差：到位偏差超此值不采信（防撞件时学坏） |
| `fLearnGain` | REAL | 0.1 | — | EWMA 学习率，域 0.01~0.5 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `fOutPosition` | REAL | mm | 补偿后位置给定 |
| `bDirPositive` | BOOL | — | 当前指令方向（TRUE = 正向） |
| `fApplied` | REAL | mm | 本拍叠加的补偿量（带符号） |
| `fBacklashEst` | REAL | mm | 当前背隙估计（学习值） |
| `bLearnActive` | BOOL | — | 本次自学习被采信 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset : R_TRIG`｜`bPrevDir : BOOL`｜`bDirInit : BOOL`｜`fEst : REAL`｜`fDev : REAL`
- **VAR CONSTANT**：`DL_BL_MAX : REAL := 10.0`（背隙上限 [mm]）｜`DL_BL_MIN_LEARN : REAL := 0.001`（学习率下限）｜`DL_BL_GAIN_MAX : REAL := 0.5`｜`DL_FLOAT_EPS : REAL := 1.0E-6`
- **边界安全条件**：① `fBacklash < 0.0` → 取绝对值并置 01CB（信息级：负背隙是参数习惯差异，不是故障）；② `fBacklash > DL_BL_MAX` → 02DB（10 mm 以上必然是参数错，补偿会把轴推到撞块）；③ 方向判定 `fCmdPosition > fPrevCmd + DL_FLOAT_EPS` / `< ... - DL_FLOAT_EPS`（**浮点判等禁用**，死区内保持上一方向，防抖动翻转）；④ 首拍 `bDirInit = FALSE` 时不补偿（无历史方向，补偿会让轴凭空跳一下）；⑤ 学习：`fDev := fActPosition - fCmdPosition`，仅当 `ABS(fDev) <= fLearnTol` 且方向刚翻转后的稳定拍采信，`fEst := fEst + fLearnGain * (fDev - fEst)`，再 `MIN/MAX` 钳 `0~DL_BL_MAX`；⑥ 位置非有限 → 02DC，输出 = 指令（旁路），清方向记忆；⑦ 方向翻转当拍输出补偿量 = `(fBacklashEst - 已补偿量)` 的增量式，**不做跳变**（跳变量限幅 `DL_BL_MAX`）。
- **错误码 5 槽（`16#0004_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0004_01CB` | 信息 | 背隙标称值为负已取绝对值 / 学习值被钳位 |
| `16#0004_01CC` | 信息 | **预留禁用（不得挪用）** |
| `16#0004_02DB` | 故障 | 背隙标称值超上限（>10 mm），补偿禁用（旁路输出） |
| `16#0004_02DC` | 故障 | 位置快照非有限（NaN/±INF），旁路输出 |
| `16#0004_02DD` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T1-6 轴级补偿语义（只借「换向补偿属运动层给定量修正」的分类）；T2-2 LBP 泵/辊「背隙两阶段逼近」组织方式次源（`RollerGapAdjust` 已用）。增量式补偿、EWMA 学习、容差闸 100% 自有

---

### 3.4 批 4（Level 1 设备抽象 → Level 2 工艺模板）

---

#### #16 `I_DL_Gripper` —— 平行夹爪契约（INTERFACE）

- **分类**：DL_Device ｜ **前缀**：`I_DL_` ｜ **类型**：INTERFACE ｜ **复杂度**：M
- **功能**：把「夹爪」的对外能力收敛为 5 个只读属性 + 4 个方法，实现类可换电动/气动/伺服夹爪而工艺层零改动。矩阵 §5 T2-6 行明列「设备级 AOI 粒度族（阀/电机/夹爪）待挖」——夹爪是本轮补的缺口。
- **方法（4 个，均无返回值，结果经属性与故障属性回读）**

| 方法 | 输入 | 说明 |
|---|---|---|
| `Open()` | — | 请求张开（到位由 `bOpened` 反映） |
| `Close()` | `fForceSetpoint : REAL`（%，0~100） | 请求闭合到指定夹持力 |
| `Release()` | — | 松开并撤力（区别于 `Open()`：不放到位，只泄力） |
| `ClearFault()` | — | 清故障（热复位，物理原因需先排除） |

- **只读属性（PROPERTY GET）**

| 属性 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bOpened` | BOOL | — | 全开到位 |
| `bClosed` | BOOL | — | 闭合到位（含夹持工件） |
| `bWorkpiecePresent` | BOOL | — | 工件在位 |
| `fWidth` | REAL | mm | 当前开口宽度 |
| `eHealth` | `E_DL_Ne107Status` | — | 健康状态（**复用库内唯一属主枚举，本件只引用不重声明**，R13 纪律） |

- **故障出口**：`uErrorId : UDINT` + `bError : BOOL` 两个只读属性（接口件不占码位，码位归实现件）。
- **边界约束**：方法总数 **4 ≤ 6**（编码规范 §十陷阱 7：接口方法超 6 个即职责过载）；`ClearFault()` 不得隐式产生动作（只清锁存）。
- **码位**：**不占码位**。族内 5 槽（信息 `16#0003_0166/0167` + 故障 `16#0003_032A/032B/032C`）全部分配给实现件 #17，接口本身零码位——头注释「错误码」段固定写 `本件为接口契约，无实现无码位；码位见 FB_DL_ParallelGripper`。
- **来源标签**：T2-6 Rockwell AOI（只借「设备级 AOI 粒度 = 阀/电机/夹爪三件套」这一分类事实）；T1-5 TcOpen 契约-实现分离范式（Apache-2.0 公开资料，仅借分层思想；方法签名/属性集/枚举引用 100% 自有）

---

#### #17 `FB_DL_ParallelGripper` —— 平行夹爪实现

- **分类**：DL_Device ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK（实现 `I_DL_Gripper`）｜ **复杂度**：H
- **功能**：三段动作（驱动 → 到位确认 → 夹持力保持），含动作超时、在位与命令矛盾判定、无件闭合判定（空夹）。**不直接写输出地址**：电磁阀/伺服指令经 `bValveOut : BOOL` 输出引脚由上层映射。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 撤所有输出 |
| `bReset` | BOOL | — | — | 上升沿清故障 |
| `bCmdOpen` | BOOL | — | — | 张开请求（与 `bCmdClose` 同拍时**闭合优先**，安全侧） |
| `bCmdClose` | BOOL | — | — | 闭合请求 |
| `fForceSetpoint` | REAL | 50.0 | % | 夹持力给定，域 0.0~100.0（超域钳位） |
| `bOpenFeedback` | BOOL | — | — | 全开到位传感器 |
| `bCloseFeedback` | BOOL | — | — | 闭合到位传感器 |
| `bWorkpieceFeedback` | BOOL | — | — | 工件在位传感器 |
| `tMoveTime` | TIME | T#2S | ms | 单动作超时，域 100~10 000 ms |
| `tConfirmTime` | TIME | T#100MS | ms | 到位确认时间，域 0~1000 ms |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bValveOut` | BOOL | — | 驱动输出（TRUE = 闭合方向），由上层映射到物理点 |
| `fForceOut` | REAL | % | 实际下发夹持力（钳位后） |
| `bOpened` | BOOL | — | 全开到位（契约属性） |
| `bClosed` | BOOL | — | 闭合到位（契约属性） |
| `bWorkpiecePresent` | BOOL | — | 工件在位（契约属性） |
| `fWidth` | REAL | mm | 开口宽度（由反馈折算，本件不做模拟量换算时置 0 并声明） |
| `bBusy` | BOOL | — | 动作中 |
| `bDone` | BOOL | — | 到位单周期脉冲 |
| `tElapsed` | TIME | ms | 本动作已耗时 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |
| `bLoadOpen` | BOOL | — | 空夹（闭合到位但无工件） |

- **VAR**：`fbTrigReset : R_TRIG`｜`fbMove : TON`｜`fbConfirm : TON`｜`eState : E_DL_GripperState`（同文件枚举 `eIdle`/`eOpening`/`eClosing`/`eHolding`/`eFault`）
- **VAR CONSTANT**：`DL_GRP_FORCE_MAX : REAL := 100.0`｜`DL_GRP_MOVE_MIN : TIME := T#100MS`｜`DL_GRP_MOVE_MAX : TIME := T#10S`
- **边界安全条件**：① `tMoveTime` 越 `DL_GRP_MOVE_MIN~MAX` → 032A（超时值本身非法会让「超时保护」失效）；② 动作超时（`fbMove.Q`）→ 032A 转 `eFault`；③ `bCloseFeedback AND NOT bWorkpieceFeedback` → `bLoadOpen := TRUE` + 0166（信息级，空夹是合法工况，不能当故障停线）；④ `bCmdOpen AND bCmdClose` → 闭合优先（安全侧）+ 0166；⑤ `fForceSetpoint` 超 0~100 → 钳位 + 0166；⑥ **`CASE` + `ELSE` 兜底** → `eFault` + 032B；⑦ `TON` / `R_TRIG` 周期首部无条件刷新（两定时器分别服务超时与确认，各自 `IN` 引脚控制）；⑧ 撤使能/复位当拍必须清 `bValveOut`（防夹持件掉落，头注释写安全约定）。
- **错误码 5 槽（`16#0003_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0003_0166` | 信息 | 空夹到位 / 开合命令同拍闭合优先 / 力给定超域已钳位 |
| `16#0003_0167` | 信息 | **预留禁用（不得挪用）** |
| `16#0003_032A` | 故障 | 动作超时（含超时参数非法） |
| `16#0003_032B` | 故障 | 在位信号与命令矛盾，或状态机落 `ELSE` 兜底 |
| `16#0003_032C` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：同 #16（T2-6 粒度分类 + T1-5 契约-实现范式）；本件状态机、超时策略、空夹语义、码位 100% 自有

---

#### #18 `FB_DL_SsrHeaterDrive` —— 固态继电器加热驱动

- **分类**：DL_Device ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：把连续功率需求 `0~100 %` 变成周期 PWM 的 SSR 通断指令，并在「占空比足够大却测不到加热电流」时判 SSR 开路/加热丝断线。**过零同步不做电网采样**（零厂商依赖），改为「周期起点对齐 + 上层可用 `bSyncPulse` 注入过零信号」的声明式设计。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 强制断输出（安全侧） |
| `bReset` | BOOL | — | — | 上升沿清断线锁存 |
| `fPowerDemand` | REAL | 0.0 | % | 功率需求，域 0.0~100.0（超域钳位） |
| `tCycleTime` | TIME | T#1S | s | PWM 周期，域 500 ms~10 s（热惯性匹配） |
| `bCurrentFeedback` | BOOL | FALSE | — | 加热电流检测输入（TRUE = 有电流） |
| `fMinDutyForCurrent` | REAL | 10.0 | % | 判定「应有电流」的最小占空，域 1.0~50.0 |
| `tCurrentWindow` | TIME | T#3S | ms | 电流缺失确认窗，域 100 ms~30 s |
| `bSyncPulse` | BOOL | FALSE | — | 可选过零/同步脉冲（TRUE 时周期起点对齐该脉冲上升沿） |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bOut` | BOOL | — | SSR 驱动输出（TRUE = 导通） |
| `fDutyApplied` | REAL | % | 实际生效占空（钳位后） |
| `tOnTime` | TIME | ms | 本周期已导通时长 |
| `bLoadOpen` | BOOL | — | 加热回路开路（锁存，需 `bReset`） |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset : R_TRIG`｜`fbTrigSync : R_TRIG`｜`fbCycle : TON`｜`fbNoCurrent : TON`｜`tCycleStart : TIME`｜`tNow : TIME`｜`bCycleActive : BOOL`
- **VAR CONSTANT**：`DL_SSR_CYCLE_MIN : TIME := T#500MS`｜`DL_SSR_CYCLE_MAX : TIME := T#10S`｜`DL_SSR_DUTY_MAX : REAL := 100.0`｜`DL_SSR_ON_EPS : REAL := 0.5`（占空小于此视为全断 [%]）
- **边界安全条件**：① `tCycleTime` 不在 500 ms~10 s → 032D，`bOut := FALSE`（**参数错时宁可断热，不得满功率长通**——加热器失控是最危险失效）；② `fPowerDemand` 超 0~100 → 钳位 + 0168；③ 占空 ≥ `fMinDutyForCurrent` 且 `NOT bCurrentFeedback` 持续 `tCurrentWindow` → 032E + `bLoadOpen` 锁存（**这是本件的核心诊断**：SSR 击穿/开路在现场只表现为「温度不升」，没有电流检测永远查不出来）；④ 占空 < `DL_SSR_ON_EPS` → 强制 `bOut := FALSE` 且**不启电流监视**（零占空本来就没电流，否则误报）；⑤ `fbCycle` / `fbNoCurrent` / 两个 `R_TRIG` 全部周期首部无条件刷新；⑥ 时间比较用 `TIME` 原值相减（禁转 REAL 再比，避免 ms 精度损失）；⑦ 无状态机（PWM 是纯组合 + 定时器），头注释 `状态机` 段写「无 CASE，周期相位由 TON 承载；`bLoadOpen` 为锁存位，非法状态不可能出现」。
- **错误码 5 槽（`16#0003_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0003_0168` | 信息 | 功率需求超域已钳位 / 占空低于导通阈值强制断 |
| `16#0003_0169` | 信息 | **预留禁用（不得挪用）** |
| `16#0003_032D` | 故障 | PWM 周期参数非法，输出强制断开 |
| `16#0003_032E` | 故障 | 加热回路开路（占空足量但无电流超确认窗），锁存 |
| `16#0003_032F` | 故障 | **预留禁用（不得挪用）** |

- **来源标签**：T2-2 LBP（只借「驱动块参数化 = 给定 + 周期 + 反馈诊断」的组内组织方式）；PWM 相位逻辑、断线判据、码位 100% 自有

---

#### #19 `FB_DL_DowntimeClassifier` —— 停机原因自动分类

- **分类**：DL_Process ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：设备停转时自动抓取「哪个原因源先动」，给出停机原因序号与停机时长；同拍多源按序号最小仲裁、超时未归类标未分类。**刻意不做 OEE 三因子**（`FB_DL_OeeCalculator` 独占该职责，避免两套统计口径打架——R10 `PickAndPlaceStation` 同纪律）。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 冻结统计 |
| `bReset` | BOOL | — | — | 上升沿清累计与当前停机 |
| `bMachineRunning` | BOOL | FALSE | — | 设备运行信号（FALSE 且持续超最短时长 = 停机） |
| `aStopCause` | ARRAY[0..7] OF BOOL | — | — | 8 路停机原因源（索引即优先级，0 最高） |
| `tMinDuration` | TIME | T#5S | s | 最短停机时长（短于此不计入，滤掉换件抖动），域 0.1~600 s |
| `tMaxClassify` | TIME | T#120S | s | 归类等待上限，超过仍无源 → 未分类 |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `bDowntime` | BOOL | — | 当前处于停机且已计时 |
| `tDownElapsed` | TIME | s | 本次停机已持续时长 |
| `uActiveCause` | UINT | — | 当前原因序号 0~7，`DL_DTC_NONE`(16#FFFF) = 未知 |
| `uLastCause` | UINT | — | 上次停机最终归因 |
| `bUnclassified` | BOOL | — | 本次停机未归类（超等待上限或无源） |
| `auCauseCount` | ARRAY[0..7] OF UDINT | 次 | 各原因累计次数 |
| `auCauseTime` | ARRAY[0..7] OF TIME | s | 各原因累计停机时长 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigReset : R_TRIG`｜`fbMinDown : TON`｜`fbClassify : TON`｜`uIdx : UINT`（扫描游标）｜`bAnyCause : BOOL`｜`uFirstFound : UINT`
- **VAR CONSTANT**：`DL_DTC_SRC_MAX : UINT := 8`｜`DL_DTC_NONE : UINT := 16#FFFF`｜`DL_DTC_TIME_MAX : TIME := T#24H`（单次停机时长饱和，防累加溢出）｜`DL_DTC_MAX_LOOP : UINT := 8`
- **边界安全条件**：① `tMinDuration < T#100MS` 或 `tMaxClassify < tMinDuration` → 0300（域自相矛盾，统计不可信），统计冻结；② 无任何原因源且停机超 `tMaxClassify` → `bUnclassified := TRUE` + 02FF；③ 仲裁：单 `FOR` 扫描 0~7，取首个 TRUE 的索引（索引最小 = 优先级最高），不累积覆盖；④ 停机时长累加前先钳 `DL_DTC_TIME_MAX`（`TIME` 加法溢出在三平台行为不同，必须先钳后加，R54 纪律：**比较预判再算**）；⑤ 计数饱和：`auCauseCount[i] < DL_DTC_CNT_MAX` 才 `+1`（禁 UDINT 回绕）；⑥ `TON` 两个均周期首部无条件刷新；⑦ 停机结束拍把本次归因写入 `uLastCause` 并累计到对应槽（**只在停机结束拍累加，不在停机中累加**，否则时长会重复计）。本件含 `CASE` 主状态机：`eIdle`/`eStopped`/`eClassifying`/`eFault` + `ELSE` 兜底（兜底码 0301）。
- **错误码 5 槽（`16#0005_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0005_01D2` | 信息 | 同拍多源停机，已按源序号最小仲裁 |
| `16#0005_01D3` | 信息 | **预留禁用（不得挪用）** |
| `16#0005_02FF` | 故障 | 停机超归类等待上限仍无原因源 → 未分类（需人工补录） |
| `16#0005_0300` | 故障 | 时间参数自相矛盾（`tMaxClassify < tMinDuration` 或 ≤0），统计冻结 |
| `16#0005_0301` | 故障 | 状态机落 `ELSE` 兜底（非法状态，回 `eIdle`） |

- **来源标签**：T2-7 PackML / OMAC（只借「停机原因 / 未计划停机归因」的公开语义分类，不做 17 态全集——全集归 `FB_DL_PackMlStateMachine` 独占）；时长/计数口径本库自有

---

#### #20 `FB_DL_ChangeoverSequence` —— 换型换产五步顺控

- **分类**：DL_Process ｜ **前缀**：`FB_DL_` ｜ **类型**：FUNCTION_BLOCK ｜ **复杂度**：H
- **功能**：把换产（SMED）拆成五步可确认的顺控：① 停机确认 → ② 排空/清洁确认 → ③ 配方装载确认 → ④ 参数下发确认 → ⑤ 首件确认放行。每步独立超时，任一步条件不满足即停在该步等确认，绝不自动跳过。
- **VAR_INPUT**

| 引脚 | 类型 | 默认 | 单位 | 说明 |
|---|---|---|---|---|
| `bEnable` | BOOL | — | — | 使能，FALSE 回 `eIdle` 并清放行 |
| `bReset` | BOOL | — | — | 上升沿清故障与步序 |
| `bStart` | BOOL | — | — | 上升沿启动换产（运行中忽略） |
| `bAbort` | BOOL | — | — | 上升沿中止（回 `eIdle`，不置故障） |
| `uTargetRecipe` | UINT | 0 | — | 目标配方号（0 = 未指定 → 0303） |
| `bMachineStopped` | BOOL | FALSE | — | 步骤 1 确认：设备已停 |
| `bLinePurged` | BOOL | FALSE | — | 步骤 2 确认：物料已排空/清洁 |
| `bRecipeLoaded` | BOOL | FALSE | — | 步骤 3 确认：配方已装载且校验通过 |
| `bParamsApplied` | BOOL | FALSE | — | 步骤 4 确认：参数已下发到设备层 |
| `bFirstPieceOk` | BOOL | FALSE | — | 步骤 5 确认：首件检验合格 |
| `tStepTimeout` | TIME | T#5MIN | s | 单步超时，域 10 s~1 h |

- **VAR_OUTPUT**

| 引脚 | 类型 | 单位 | 说明 |
|---|---|---|---|
| `uStep` | UINT | — | 当前步号 0(Idle) / 1~5 / 99(Fault) |
| `bBusy` | BOOL | — | 换产进行中 |
| `bDone` | BOOL | — | 全部完成单周期脉冲 |
| `bReadyForProduction` | BOOL | — | 放行生产（`bDone` 后保持，直到 `bReset`/`bAbort`） |
| `uBlockedStep` | UINT | — | 因超时被阻塞的步号（0 = 无） |
| `tStepElapsed` | TIME | s | 当前步已耗时 |
| `eErr` | UDINT | — | 错误码 |
| `bError` | BOOL | — | 故障标志 |

- **VAR**：`fbTrigStart / fbTrigReset / fbTrigAbort : R_TRIG`｜`fbStep : TON`｜`eState : E_DL_ChangeoverState`（同文件枚举 `eIdle`/`eStep1`…`eStep5`/`eDone`/`eFault`）｜`bStepEnter : BOOL`
- **VAR CONSTANT**：`DL_CO_STEP_MAX : UINT := 5`｜`DL_CO_TIMEOUT_MIN : TIME := T#10S`｜`DL_CO_TIMEOUT_MAX : TIME := T#1H`｜`DL_CO_STEP_FAULT : UINT := 99`
- **边界安全条件**：① `tStepTimeout` 越 10 s~1 h → 0302（超时保护失效不可接受）；② `uTargetRecipe = 0` → 0303 并 A 步失败（步骤 3 起需配方号）；③ 每步进入时 `fbStep` 重装（用 `IN := bStepEnter` 单拍置位 + `PT := tStepTimeout`，`fbStep` 周期首部无条件调用，**`bStepEnter` 由状态迁移置位、本拍末尾清零**——这是本件最高危点，R40「单步超时被实现成相内累计」教训复核项）；④ 步进条件为「本步确认信号 AND 上一步已完成」，任一步确认信号中途掉线 → 退回该步（不跳过）；⑤ `bAbort` → `eIdle`，**不置故障、不置 0302**（人为中止是合法操作）；⑥ `CASE` + `ELSE` 兜底：`ELSE` 分支固定置 `eFault`、`uStep := 99`、码 `0304`（本件为此**专用兜底码**，故 0304 不列为预留）；⑦ `bReadyForProduction` 只在 `eDone` 置位，`bEnable` 掉电即清零（安全侧）。
- **错误码 5 槽（`16#0005_` 段）**

| 码 | 级别 | 语义 |
|---|---|---|
| `16#0005_01D4` | 信息 | 单步超时后等待人工确认（`uBlockedStep` 已记录，未置故障） |
| `16#0005_01D5` | 信息 | **预留禁用（不得挪用）** |
| `16#0005_0302` | 故障 | 单步超时参数非法（超时保护失效） |
| `16#0005_0303` | 故障 | 前置条件不满足（目标配方号未指定 / 确认信号缺失） |
| `16#0005_0304` | 故障 | 状态机落 `ELSE` 兜底（非法状态，回 `eIdle`）——**用途固定，不得改作他用** |

- **来源标签**：T2-7 PackML（只借「最小子集 + 明确终止态」的态组织纪律，不做 17 态全集）+ T2-8 ISA-88（只借公开条款的「配方切换需前置确认」相语义，不复制条款文本）；五步划分、超时策略、码位 100% 自有

---

---

## 4 码位总账（95 槽，逐槽列明；分 5 大段，实测空闲已核）

### 4.1 `16#0001_`（DL_Base / DL_MathData 共用段，8 件）

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 ×2 |
|---|---|---|---|---|---|
| 1 | `FB_DL_FirstOutLatch` | `0235` | `0236` | `0306` | `0307` `0308` |
| 2 | `FB_DL_PulseStretch` | `0237` | `0238` | `0309` | `030A` `030B` |
| 3 | `FB_DL_EdgeDivider` | `0239` | `023A` | `030C` | `030D` `030E` |
| 4 | `FC_DL_BitSegmentBlockMove` | `023B` | `023C` | `030F`（+`0310` `0311` 语义占用） | `—` |
| 5 | `FC_DL_Crc16Ccitt` | `023D` | `023E` | `0313` | `0312`（保留归属）`0314` |
| 6 | `FC_DL_InterpolateTable2D` | `023F` | `0240` | `0315` `0316` | `0317` |
| 7 | `FC_DL_AffineTransformPoint` | `0241` | `0242` | `0318` `0319` | `031A` |
| 8 | `FC_DL_CpkIndex` | `0243` | `0244` | `031B` `031C` | `031D` |

**0001_ 段游标终点**：信息级 **`0244`**（下一件起点 `0245`）；故障级 **`031D`**（下一件起点 `031E`）。

### 4.2 `16#0002_`（DL_Algo 段，组件序号网格，4 件）

| # | 组件 | 序号 CC | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 ×2 |
|---|---|---|---|---|---|---|
| 9 | `FB_DL_GainScheduler` | `23` | `2301` | `2302` | `2310` `2311` | `2312` |
| 10 | `FB_DL_BumplessTransfer` | `24` | `2401` | `2402` | `2410` `2411` | `2412` |
| 11 | `FB_DL_NotchFilter` | `25` | `2501` | `2502` | `2510` `2511` | `2512` |
| 12 | `FB_DL_ThermalI2tModel` | `26` | `2601` | `2602` | `2610` `2611` | `2612` |

**0002_ 段游标终点**：组件序号 **`CC = 26`**（下一件 `CC = 27`，实测 `2700~27FF` 空闲）。

### 4.3 `16#0003_`（DL_Device 段，2 件 + 1 接口）

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 ×2 |
|---|---|---|---|---|---|
| 16 | `I_DL_Gripper` | **不占**（接口） | 不占 | 不占 | 不占 |
| 17 | `FB_DL_ParallelGripper` | `0166` | `0167` | `032A` `032B` | `032C` |
| 18 | `FB_DL_SsrHeaterDrive` | `0168` | `0169` | `032D` `032E` | `032F` |

> `I_DL_Gripper` 的 5 槽**并入实现件 #17**（族内不重复登记），接口头注释写「本件为契约，无实现无码位」。

**0003_ 段游标终点**：信息级 **`0169`**（下一件 `016A`）；故障级 **`032F`**（下一件 `0330`）。

### 4.4 `16#0004_`（DL_Motion 段，3 件）

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 |
|---|---|---|---|---|---|
| 13 | `FB_DL_AxisFollowingErrorMonitor` | `01C7` | `01C8` | `02D5` `02D6` | `02D7` |
| 14 | `FB_DL_AxisSynchronizedStop` | `01C9` | `01CA` | `02D8` `02D9` `02DA`（兜底专用） | `—` |
| 15 | `FB_DL_BacklashCompensator` | `01CB` | `01CC` | `02DB` `02DC` | `02DD` |

**0004_ 段游标终点**：信息级 **`01CC`**（下一件 `01CD`）；故障级 **`02DD`**（下一件 `02DE`）。

### 4.5 `16#0005_`（DL_Process 段，2 件）

| # | 组件 | 信息-用 | 信息-预留 | 故障-用 | 故障-预留 |
|---|---|---|---|---|---|
| 19 | `FB_DL_DowntimeClassifier` | `01D2` | `01D3` | `02FF` `0300` `0301`（兜底专用） | `—` |
| 20 | `FB_DL_ChangeoverSequence` | `01D4` | `01D5` | `0302` `0303` `0304`（兜底专用） | `—` |

**0005_ 段游标终点**：信息级 **`01D5`**（下一件 `01D6`）；故障级 **`0304`**（下一件 `0305`）。

### 4.6 全局游标汇总（交接收口）

| 段 | 信息级下一可用 | 故障级下一可用 | 本轮占用槽数 |
|---|---|---|---|
| `0001_` | `0245` | `031E` | 40 |
| `0002_` | `CC = 27` | `CC = 27` | 20 |
| `0003_` | `016A` | `0330` | 10 |
| `0004_` | `01CD` | `02DE` | 15 |
| `0005_` | `01D6` | `0305` | 10 |
| **合计** | | | **95** |

> 20 件 × 5 槽 = 100 槽名义值，实占 95 槽（接口件不占 5 槽，已在 4.3 说明）——**账实差异为设计意图，非漏记**。

---

## 5 三段样板原文（R50 教训：**派单必须内嵌原文，不得只写「照既有惯例」**）

以下三段为**逐字符可复制基线**，四批 20 件一律照抄后替换 `<…>` 占位与业务主体，**禁止改造结构**。

### 5.1 样板 A｜声明区注释行样板（变量同行中文 + 英文，带单位/域）

```iecst
VAR_INPUT
    bEnable     : BOOL;                       // 使能，FALSE 时输出复位到安全值 / enable, FALSE resets outputs to safe values
    bReset      : BOOL;                       // 上升沿复位故障 / rising edge clears faults
    fSetpoint   : REAL := 0.0;                // 目标值 [mm]，范围 0.0~1000.0 / setpoint [mm], range 0.0~1000.0
    tTimeout    : TIME := T#3S;               // 超时时间 [ms]，0 表示不监控 / timeout [ms], 0 disables monitoring
    uSrcCount   : UINT := 16;                 // 有效源数 [路]，范围 1~16 / valid source count [ch], 1~16
END_VAR
VAR_OUTPUT
    bActive     : BOOL;                       // 运行中标志 / active flag
    eErr        : UDINT;                      // 错误码，0=正常 / error id, 0=ok
    bError      : BOOL;                       // 故障标志，eErr 为故障级时置位 / error flag, TRUE on fault-level eErr
    fActual     : REAL;                       // 实际输出值 [mm] / actual output [mm]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : REAL := 1.0E-6;          // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_MAX_LOOP    : DINT := 10000;           // 循环防死锁上限 [次] / loop guard limit [count]
END_VAR
```

**规则**：① 每行以 `//` 起中文注释，末尾 `/` + 英文；② 物理量必带 `[单位]`，无量纲写 `[无量纲]`/`[dimensionless]`；③ 有域的量必写「范围 a~b」或「域」；④ 常量全大写下划线，同样带单位注释；⑤ 对齐列 = 变量名后至少 2 空格。

### 5.2 样板 B｜错误码声明样板（`VAR_OUTPUT` 三件套 + 头注释 5 行码表）

```iecst
VAR_OUTPUT
    eErr    : UDINT;                          // 错误码，0=正常 / error id, 0=ok
    bError  : BOOL;                           // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid  : BOOL;                           // 输出是否有效可用 / output valid flag
END_VAR
```

```iecst
// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_<Name> := <DEFAULT_SAFE_VALUE>;         // 故障缺省返回安全值 / fault default safe value
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过闸门后置位 / preset invalid, set TRUE after gates

// 段 2｜<第一道防御闸> / segment 2, first defence gate
IF <ILLEGAL_CONDITION> THEN
    eErr   := 16#0001_<FAULT_CODE>;           // <中文语义> / <english meaning>
    bError := TRUE;                           // 置故障标志 / raise error flag
    bValid := FALSE;                          // 输出不可用 / output not usable
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF
```

**每件头注释「错误码」段固定 5 行，逐槽列全（含预留）**，格式照抄：

```iecst
    错误码    : 16#0001_0235 <中文语义>——信息级，正常防御
                16#0001_0236 预留禁用（信息级，不得挪用）
                16#0001_0306 <中文语义>——故障级，<出口行为>
                16#0001_0307 预留禁用（故障级，不得挪用）
                16#0001_0308 预留禁用（故障级，不得挪用）
```

**规则**：① 信息级**永不置 `bError`**（头注释明写）；② 预留槽写「预留禁用（不得挪用）」，实现体内**不得**出现该码赋值；③ 故障级码必须出现在头注释**且**在实现体内有唯一赋值点（可追溯，R13「`bError` 置位源必须能在 `uErrorId` 找到对应码」）；④ 单一业务语义上下两个方向**共用一个信息码**时，方向差异写进头注释（照 `FC_DL_RealToLintSat` 022E 惯例）。

### 5.3 样板 C｜头注释结构样板（照 `FC_DL_RealToLintSat.st` 结构，20 件统一）

```iecst
(*
    <POU_NAME> —— <中文短名>
    ------------------------------------------------------------------
    分类      : DL_<Category> / <子域，如 Signal / Convert / Motion>
    前缀      : <FB_DL_ / FC_DL_ / I_DL_>
    版本      : 1.0.0
    溯源      : <T 源标签>；<原始协议 / 公开规范>；
                <借鉴点一句话：只借什么，不借什么>；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · <总监 / PLC编程专家>（R18）
    ------------------------------------------------------------------
    功能说明  : <3~6 行：解决什么现场问题 → 输入输出语义 → 核心防御手段 → 与库内相邻件的职责边界>
    错误码    : <5 行，见样板 B>
    状态机    : <有状态机：E_DL_XXXState 的态清单 + 声明「CASE 含 ELSE 兜底」/ 无状态机：R6 标注 N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现>
    采样约定  : <定时器/边沿在周期首部无条件刷新；时间基准来自 tSampleTime 引脚；扫描周期依赖声明>
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
```

### 5.4 样板 D｜码位表（`.st` 内注释形式，紧接头注释的「错误码」段，供机检正则抓取）

```iecst
(*
    码位总账 : 0001_0235 用 / 0001_0236 预留 ｜ 0001_0306 用 / 0001_0307 预留 / 0001_0308 预留
*)
```

**规则**：该行必须包含全部 5 个 `16#0001_XXXX` 形态的裸码（不带 `16#` 前缀亦可，但**本库统一带 `16#`**，机检正则 `16#[0-9A-F]{4}_[0-9A-F]{4}` 才能抓到）。

---

## 6 入库自检清单（每件逐条打勾，任一不过禁止入库）

| # | 检查项 | 机检手段 |
|---|---|---|
| 1 | 文件名 = POU 名（含前缀），无拼写漂移 | `ls DL_*/*.st` 对 registry `file_path` |
| 2 | 头注释七项齐全（分类/前缀/版本/溯源/平台/作者 + 功能/错误码/状态机/修订） | 正则抓 `分类|前缀|版本|溯源|平台|错误码|状态机|修订` |
| 3 | 声明区每行变量带中文 + 英文同行注释 | 逐行 `//` 存在性检查（含 `VAR CONSTANT`） |
| 4 | 物理量带单位、带域 | 抓 `[` `]` 与「范围/域」 |
| 5 | 零 `GVL` / 零 `VAR_EXTERNAL` / 零 `%I` `%Q` `%M` | `grep -nE "GVL\\.|VAR_EXTERNAL|%[IQM][XBWDL]?[0-9]"` |
| 6 | 零厂商库 / 零 `POINTER TO` / 零 `REFERENCE TO` / 零隐式转换 | `grep -nE "Sys[A-Z]|Tc[A-Z]|SM3_|POINTER TO|REFERENCE TO"` |
| 7 | 有状态机必 `ENUM` + `CASE` + `ELSE` 兜底；无状态机必写 R6 `N/A` | 抓 `ELSE` 在 `CASE` 内 + `状态机` 段 |
| 8 | `TON`/`TOF`/`R_TRIG`/`F_TRIG` 在主周期无条件刷新（不在 `IF` 内） | 人工逐件核对调用位置（本批 6 件含定时器：2/11/13/17/18/19/20） |
| 9 | 浮点无 `=` 判等（全 `ABS(..) < EPS`） | `grep -nE "f[A-Za-z]+ *= *f[A-Za-z]+"` + 人工 |
| 10 | 除法前置防零；数组先判界；循环有守卫 | 人工逐件（#4 有 `FOR` + 守卫，#6 有跨度闸，#8 有 σ 闸，#11 有 `a0` 闸，#12 有 `τ` 闸） |
| 11 | 码位账实一致（5 槽全出现在文件内，预留槽无赋值） | 用 `_verify_r18.py` 反向正则 |
| 12 | 无魔法数（阈值/限幅/超时全在 `VAR CONSTANT` 或引脚） | 抓裸数值字面量（排除 0/1/2/16# 掩码） |
| 13 | 依赖方向合法（低层不引高层；接口引用只指低层） | 抓 `I_DL_` / `FB_DL_` 引用清单 |
| 14 | 枚举唯一属主不重声明（`E_DL_Ne107Status` 只引用） | `grep -n "TYPE E_DL_Ne107Status"` 应只 1 处 |
| 15 | 子库 `VERSION.md` / `MANUAL_DL_*.md` / 顶层 `CHANGELOG.md` / `README.md` / `LIBRARY_MANUAL.md` 五处同步 | 收口脚本比对计数 |
| 16 | registry / JSONL 同步 + sha256 复验 | `closeout_r18.py` |

## 7 禁区表（本轮明确不做，防下轮重复立项）

| 禁区 | 理由 |
|---|---|
| 纯类型复制变体（如 `FC_DL_ShlUdintEx`、`FC_DL_MinDint`、`FC_DL_AbsLreal`） | 无新增防御逻辑、无独立工况语义 = 凑数，违反「严禁无工程意义的凑数变体」 |
| `LWord 累加和` / `Int 版 SearchMinMax` / `UDInt 版 SearchMinMax` | 属纯重载，本轮不做；如要做必须附「独立防御点」说明后再立项 |
| 17 态 PackML 全集第二套 | 全集唯一属主是 `FB_DL_PackMlStateMachine`（R10 纪律） |
| OEE 三因子第二套 | 唯一属主 `FB_DL_OeeCalculator` |
| `E_DL_Ne107Status` 重声明 | 唯一属主 `I_DL_DeviceHealth`（R13） |
| 轴状态枚举 / 轴状态机 | 唯一属主 `FB_DL_SingleAxis`；#13/#14/#15 只消费快照，不自造状态 |
| `SysFile` / 文件系统 / 指针 / 厂商诊断对象 | 违反零厂商依赖红线 |
| DT/DTL 日历族（`DtToDintEpoch` 等） | R17 已判 P1 延后，须先评估三平台 `DT_TO_DTL` 内链行为（R64 门槛） |
| `FC_DL_SearchMinMaxLreal` 已有 → 不重复 | 存量 13 件 Math 族已覆盖 |

---

*ROUND PLAN R18 ｜ 2026-11-16 12:48 ｜ 20 件锁定 ｜ WebSearch 1 次 ｜ 码位 95 槽实测空闲 ｜ 待编码*

