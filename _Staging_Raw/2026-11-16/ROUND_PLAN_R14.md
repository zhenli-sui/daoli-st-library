# R14 轮次作战计划（500 冲刺 T0 快车道）

> 制定时间：2026-11-16 02:05 ｜ 制定人：工控代码库产品总监 ｜ 预算：50 分钟收尾
> 基线事实：INDEX_REGISTRY.json v2.2.0，全库 204 组件（DL_Base 40 / DL_MathData 42 / DL_Algo 28 / DL_Device 50 / DL_Motion 18 / DL_Process 26）
> 本轮性质：**纯 T0 快车道，零检索**（T0 组 = IEC 61131-3 标准函数/功能块的道莅防御性包装，接口语义由标准定义，不构成版权文本）

---

## 1. 避重声明（与库内既有组件的边界）

以下既有组件与本轮 20 个目标**无同名冲突**，且职责边界如下：

- `FB_DL_ExtendedTimer`（on-delay/off-delay/retentive/pulse 四合一，complexity 5）：是「组合巨块」；本轮 TON/TOF/TP/RTO 为**单语义原子包装**，与库内「先原子化再矩阵化」原则（矩阵第 3 节）一致，属横向补齐而非重复造块。
- `FC_DL_BcdToWord` / `FC_DL_WordToBcd`：BCD 转换已收口，本轮不碰。
- `FB_DL_BidirectionalCounter`（CTUD 全语义超集，含双预设/饱和/三律）：本轮 `FB_DL_CtudEx` 定位不同——它是**对平台内建 CTUD 的逐引脚等义防御包装**（委托内建 + 钳位 + 错误码），非 LGF 语义扩展块；两者在 MANUAL 中互引声明边界。
- `FB_DL_EventCounter` / `ModuloCounter` / `RolloverCounter` / `PresetCounterSat`：LGF Counter 组语义件，与标准 CTU/CTD 包装无语义重叠。
- `FB_DL_DualEdgeTrig`：双沿同块输出（双沿检测器）；`FB_DL_RTrigEx`/`FTrigEx` 为单沿标准语义包装，边界清晰。

## 2. 分类归属裁定

| 族 | 归属 | 裁定依据 |
|---|---|---|
| 触发器 SR/RS/R_TRIG/F_TRIG | **DL_Base** | 矩阵 T0-1 明示 DL_Base；无工业数值语义 |
| 定时器 TON/TOF/TP/RTO | **DL_Base** | 库内惯例：`FB_DL_ExtendedTimer`、`FB_DL_PulseGenerator` 均在 DL_Base；矩阵 T0-2 归 DL_Base |
| 计数器 CTU/CTD/CTUD | **DL_Base** | 库内惯例：Counter 族 5 件全在 DL_Base（tag `lgf-counter`）；矩阵 T0-3 归 DL_Base |
| 移位 SHL/SHR/ROL/ROR | **DL_Base** | 矩阵 T0-7 归 DL_Base；与 FC_DL_BitGet/BitSet 等位操作同库 |
| 数学 SQRT/LN/TAN（+后续 EXP/SIN/COS/ASIN/ACOS/ATAN/EXPT/ABS/LOG） | **DL_MathData** | 矩阵 T0-4 归 DL_MathData |
| 取整 ROUND | **DL_MathData** | 矩阵 T0-5 归 DL_MathData |
| 字符串 MID | **DL_MathData**（对任务书初拟「DL_Base」的**改判**） | 库内分类学结论已确立（R12）：字符串归 LGF Data Handling → DL_MathData，registry 中 StringTrim/Split/ReplaceAll/TokenStream/ToLReal/FixedField 六件全在 DL_MathData；矩阵 T0-6 亦归 DL_MathData。**依「先看 registry 惯例」指令裁定改判，保持字符串族单库聚居** |

DL_Base 现 40 件不构成硬上限：本轮 +12 → 52，DL_MathData +8 → 50，可接受；后续 T0 轮按此口径继续。

## 3. 码位基线与本轮建议段

两库共享 `16#0001_xxxx` 段。R13 后最新占用（VERSION.md 台账）：
- 信息级 `01xx`：最大占用 **014C**（DL_MathData R13，0141~014C）；DL_Base R13 至 0140。
- 故障级 `02xx`：最大占用 **0225**（DL_MathData R13，0221~0225）。
- 历史空置位 0111 / 0209（不回填，避免台账歧义）。

**本轮建议**：信息级自 **014D** 起、故障级自 **0226** 起，逐组件连续分配；下表码位为**建议值**，编码阶段必须按 R30 教训以全库求差脚本终审核定，禁止以「注释写明未占用」替代脚本断言。

## 4. 目标总表（20 个，4 批 × 5）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_SRBistable | DL_Base | FB | SR 置位优先双稳态：S1/R 同拍仲裁显式化 + 仲裁诊断码 | iec-std-wrapper | 2 | 1 |
| 2 | FB_DL_RSBistable | DL_Base | FB | RS 复位优先双稳态：S/R1 同拍仲裁显式化 + 仲裁诊断码 | iec-std-wrapper | 2 | 1 |
| 3 | FB_DL_RTrigEx | DL_Base | FB | 上升沿检测防御包装：CLK 非法时序免疫 + 单拍输出保证 | iec-std-wrapper | 2 | 1 |
| 4 | FB_DL_FTrigEx | DL_Base | FB | 下降沿检测防御包装：首扫不假触发 + 单拍输出保证 | iec-std-wrapper | 2 | 1 |
| 5 | FB_DL_TonEx | DL_Base | FB | 接通延时定时器防御包装：PT 钳位 + 跨段输入断开语义统一 | iec-std-wrapper | 3 | 1 |
| 6 | FB_DL_TofEx | DL_Base | FB | 断开延时定时器防御包装：PT 钳位 + 首扫语义统一 | iec-std-wrapper | 3 | 1 |
| 7 | FB_DL_TpEx | DL_Base | FB | 脉冲定时器防御包装：PT 钳位 + 不可重触发语义显式化 | iec-std-wrapper | 3 | 1 |
| 8 | FB_DL_RtoEx | DL_Base | FB | 保持型定时器防御包装：掉保持/复位优先级 + 累计值可见 | iec-std-wrapper | 4 | 2 |
| 9 | FB_DL_CtuEx | DL_Base | FB | 加计数器防御包装：PV 钳位 + 上溢饱和不回绕 | iec-std-wrapper | 3 | 2 |
| 10 | FB_DL_CtdEx | DL_Base | FB | 减计数器防御包装：PV 钳位 + 下溢饱和不回绕 | iec-std-wrapper | 3 | 2 |
| 11 | FB_DL_CtudEx | DL_Base | FB | 双向计数器防御包装：CU/CD 同拍仲裁 + 复位/装载优先级链 | iec-std-wrapper | 4 | 3 |
| 12 | FC_DL_ShlEx | DL_Base | FC | 左移防御包装：移位量钳位归一 + 超宽结果零值显式化 | iec-std-wrapper | 2 | 3 |
| 13 | FC_DL_ShrEx | DL_Base | FC | 右移防御包装：移位量钳位归一 + 超宽结果零值显式化 | iec-std-wrapper | 2 | 3 |
| 14 | FC_DL_RolEx | DL_Base | FC | 循环左移防御包装：移位量 MOD 位宽归一（禁平台歧义取余） | iec-std-wrapper | 2 | 3 |
| 15 | FC_DL_RorEx | DL_Base | FC | 循环右移防御包装：移位量 MOD 位宽归一（禁平台歧义取余） | iec-std-wrapper | 2 | 3 |
| 16 | FC_DL_SqrtEx | DL_MathData | FC | 平方根防御包装：负数/非有限输入域闸门，内部委托内建 SQRT | iec-std-wrapper | 2 | 4 |
| 17 | FC_DL_LnEx | DL_MathData | FC | 自然对数防御包装：fX≤0 与非有限域闸门，委托内建 LN | iec-std-wrapper | 2 | 4 |
| 18 | FC_DL_TanEx | DL_MathData | FC | 正切防御包装：π/2 极点容差拦截，委托内建 SIN/COS 或 TAN | iec-std-wrapper | 3 | 4 |
| 19 | FC_DL_RoundSat | DL_MathData | FC | 四舍五入取整饱和包装：溢出钳位 + 非有限拦截 + 半值取向显式化 | iec-std-wrapper | 3 | 4 |
| 20 | FC_DL_StringMidEx | DL_MathData | FC | MID 取子串防御包装：起点/长度钳位 + 255 上限截断标志显式化 | iec-std-wrapper | 3 | 4 |

批次切分逻辑：批 1 触发器族 + TON（同族同骨架，先立「双稳态/沿/延时」三模板）；批 2 定时器收尾 + 计数器（复用定时器模板、立计数器饱和模板）；批 3 计数器收尾 + 移位族（纯函数批，立「钳位归一」模板）；批 4 数学/取整/字符串（纯函数域闸门批，立「域闸门 + 委托内建」模板）。批间无编译依赖，仅模板复用顺序。

## 5. 分批引脚级规格

> 通用要求（全部 20 件）：文件头溯源统一写「**IEC 61131-3 标准语义的道莅防御性实现**（接口语义由 IEC 61131-3 定义，clean-room 重写，参考公开标准条款）」；`function_tags` 必含 `iec-std-wrapper`；100% 中文注释 + 头注释块双语（中/英）列；严禁重实现数学/定时/计数内核——定时器/计数器/数学一律内部委托平台内建标准实例或函数，外围做钳位、域校验、错误码与语义统一。

### 批次 1（序号 1~5）：触发器族 + TON —— DL_Base

**1. FB_DL_SRBistable**（置位优先双稳态）
- 引脚：`VAR_INPUT bS1 : BOOL; // 置位主导输入（IEC S1）`｜`bR : BOOL; // 复位输入`；`VAR_OUTPUT bQ1 : BOOL; // 置位优先输出`；`VAR_OUTPUT uDiag : WORD; // 仲裁诊断字（建议 16#0001_014D：S1/R 同拍，置位胜出）`
- 边界安全：S1 与 R 同拍为 TRUE 时按 IEC 语义 S1 优先，**必须显式注释并置诊断码**（信息级，不置 bError——标准语义本就定义了胜负，诊断只为现场排查）；无浮点、无循环。
- 错误码段建议：信息级 `16#0001_014D`（终审核定）。
- 双语注释：S1/R 语义差异（SR vs RS）在头注释用中英对照表写明。

**2. FB_DL_RSBistable**（复位优先双稳态）
- 引脚：`bS : BOOL; // 置位输入`｜`bR1 : BOOL; // 复位主导输入（IEC R1）`；输出 `bQ : BOOL`｜`uDiag : WORD`（建议 `16#0001_014E`：S/R1 同拍，复位胜出）
- 边界安全/注释：同上，主导方向相反；与 FB_DL_SRBistable 头注释互引。

**3. FB_DL_RTrigEx**（上升沿）
- 引脚：`bCLK : BOOL; // 时钟输入`；输出 `bQ : BOOL; // 单拍上升沿脉冲`
- 边界安全：首扫（首次调用）按 CLK 当前值初始化记忆位，**首扫不产假边沿**（部分平台 R_TRIG 首扫行为不一致，此处统一）；输出严格单拍。
- 错误码：无（纯语义包装，无域可校验）；头注释声明「无错误码」。

**4. FB_DL_FTrigEx**（下降沿）
- 引脚/边界/码位：同 RTrigEx，取反沿；建议同批共用「无错误码」声明。

**5. FB_DL_TonEx**（接通延时）
- 引脚：`bIN : BOOL; // 定时输入`｜`tPT : TIME; // 预置延时（ms）`；输出 `bQ : BOOL; // 延时到输出`｜`tET : TIME; // 已计时（ms）`；`VAR uDiag : WORD`（建议信息级 `16#0001_014F`：tPT 负值钳 0）
- 边界安全：tPT < 0 钳 0 并置信息码（部分平台负 TIME 行为未定义）；跨段统一语义——bIN 断开当拍 ET 归零、bQ 立即 FALSE；首扫 bIN=TRUE 允许正常计时（TON 标准语义）但不产假 bQ；内部委托内建 TON 实例（VAR 实例，非 GVL）。
- 双语注释：tPT/tET 单位 ms 标注。

### 批次 2（序号 6~10）：定时器收尾 + 计数器 —— DL_Base

**6. FB_DL_TofEx**（断开延时）
- 引脚：`bIN`｜`tPT : TIME`；输出 `bQ`｜`tET : TIME`｜`uDiag`（建议 `16#0001_0150`：tPT 负钳 0）
- 边界安全：tPT 负钳 0；首扫 bIN=FALSE 时 bQ 必须为 FALSE（TOF 首扫假触发的平台差异统一）；bIN 接通当拍 ET 归零。

**7. FB_DL_TpEx**（脉冲）
- 引脚：`bIN`｜`tPT : TIME`；输出 `bQ`｜`tET : TIME`｜`uDiag`（建议 `16#0001_0151`：tPT 负钳 0）
- 边界安全：**不可重触发语义显式化**——计时中 bIN 再触发不延长（IEC 语义，但多平台实现有偏差，注释写死）；tPT 负钳 0。

**8. FB_DL_RtoEx**（保持型定时器，IEC 无标准块，按通用 RTO 语义 clean-room）
- 引脚：`bIN : BOOL; // 计时使能`｜`bRESET : BOOL; // 复位（优先级最高）`｜`tPT : TIME`；输出 `bQ : BOOL; // 累计到达`｜`tET : TIME; // 累计值（bIN 断开保持）`｜`uDiag : WORD`（建议 `16#0001_0152`：tPT 负钳 0）
- 边界安全：复位 > 使能优先级链写死并注释；tPT 负钳 0；累计用内建 TON + 保持逻辑组合（不重实现计时内核）；ET 只增不减至复位。

**9. FB_DL_CtuEx**（加计数）
- 引脚：`bCU : BOOL; // 加计数脉冲（内部 R_TRIG）`｜`bRESET : BOOL; // 复位（最高优先）`｜`nPV : INT; // 预置值（个）`；输出 `nCV : DINT; // 当前值（个）`｜`bQ : BOOL; // CV >= PV`｜`uDiag : WORD`（建议信息级 `16#0001_0153`：nPV 负值钳 0 / CV 上限饱和）
- 边界安全：**上溢饱和不回绕**——CV 达 DINT 上限停止递增并置诊断码（信息级，饱和是正常防御行为）；nPV 负值钳 0；bRESET > bCU 优先级；内部委托内建 R_TRIG 实例产脉冲。

**10. FB_DL_CtdEx**（减计数）
- 引脚：`bCD : BOOL; // 减计数脉冲`｜`bLOAD : BOOL; // 装载 PV（最高优先）`｜`nPV : INT`；输出 `nCV : DINT`｜`bQ : BOOL; // CV <= 0`｜`uDiag : WORD`（建议 `16#0001_0154`：nPV 负钳 0 / 下限饱和）
- 边界安全：**下溢饱和不回绕**——CV 至 DINT 下限停减；nPV 负钳 0；bLOAD > bCD 优先级。

### 批次 3（序号 11~15）：CTUD + 移位族 —— DL_Base

**11. FB_DL_CtudEx**（双向计数）
- 引脚：`bCU`｜`bCD`｜`bRESET`｜`bLOAD`｜`nPV : INT`；输出 `nCV : DINT`｜`bQU : BOOL; // CV >= PV`｜`bQD : BOOL; // CV <= 0`｜`uDiag : WORD`（建议信息级 `16#0001_0155`：PV 负钳 0 / 同拍仲裁记录；故障级 `16#0001_0226`：CV 越出 [DINT_MIN, DINT_MAX] 饱和触发时的异常记录）
- 边界安全：优先级链 bRESET > bLOAD > 计数；CU/CD 同拍时**先加后减或先减后加必须写死一种并注释**（取「同拍抵消净额」法：net = CU沿 − CD沿，一次性施加，天然规避顺序歧义）；双向饱和均不回绕。
- 与 FB_DL_BidirectionalCounter 边界：本件是标准 CTUD 等义防御包装（无双预设、无倒置冻结扩展），MANUAL 互引。

**12. FC_DL_ShlEx**（左移）
- 引脚：`uIn : DWORD; // 被移位位串`｜`nN : USINT; // 移位量（位）`；输出 `uOut : DWORD; // 移位结果`；`VAR_OUTPUT uDiag : WORD`（建议信息级 `16#0001_0156`：nN > 31 超宽，结果置 0）
- 边界安全：**严禁 `SHL(x, n)` 中 n≥32 的未定义/平台歧义行为**（R10 BitFieldExtract 先例：n=32 走常量路径）——nN ≥ 32 时直接置 0 并置码，不调内建；nN < 32 才委托内建 SHL。纯函数，无内部状态。

**13. FC_DL_ShrEx**（右移）
- 引脚/边界同 ShlEx；诊断建议 `16#0001_0157`。

**14. FC_DL_RolEx**（循环左移）
- 引脚：同 ShlEx；`nN` 先 `nN MOD 32` 归一（**禁用 MOD 对负数的平台歧义——nN 为 USINT 天然非负，写明该前提**）；归一后 nN=0 直接返回原值；诊断建议 `16#0001_0158`（无诊断事件时不置）。
- 边界安全：归一后委托内建 ROL 或按位合成；保证循环语义位不丢。

**15. FC_DL_RorEx**（循环右移）
- 引脚/边界同 RolEx；诊断建议 `16#0001_0159`。

### 批次 4（序号 16~20）：数学/取整/字符串 —— DL_MathData

**16. FC_DL_SqrtEx**（平方根）
- 引脚：`fX : LREAL; // 被开方数（无量纲）`；返回 `LREAL; // 平方根`；`VAR_OUTPUT eErr : WORD`（建议故障级 `16#0001_0227`：fX < 0 域外；信息级 `16#0001_015A`：fX 非有限拦截）
- 边界安全：**定义域闸门先行**——fX 非有限（x <> x 判 NaN / fX = fX + 1E308 判 Inf 参照库内既有写法）或 fX < 0 时**不调内建**、返回 0.0 并置码；域内委托内建 SQRT，结果非有限复检。
- 双语注释：输入输出无量纲，负数开方在 IEEE 下产 NaN——本库统一为「0.0 + 故障码」策略并写明与 IEEE 行为的差异。

**17. FC_DL_LnEx**（自然对数）
- 引脚：`fX : LREAL; // 真数（无量纲）`；返回 LREAL；`eErr : WORD`（建议故障级 `16#0001_0228`：fX ≤ 0；`16#0001_0229`：非有限输入/输出）
- 边界安全：fX ≤ 0 域闸门（=0 数学上趋于 −Inf，统一拦截不返回 −Inf）；域内委托内建 LN；输出非有限复检。

**18. FC_DL_TanEx**（正切）
- 引脚：`fX : LREAL; // 弧度（rad）`；返回 LREAL；`eErr : WORD`（建议故障级 `16#0001_022A`：极点邻域 |cos(fX)| < 1E-12 或非有限）
- 边界安全：**π/2 极点拦截**——先用容差判 |cos(fX)|（cos 由内建求，不自写级数），极点邻域返回 0.0 + 故障码；fX 非有限先行拦截；结果非有限复检（内建 TAN 在极点可能返回天文数字而非 Inf，容差闸门必须前置）。弧度单位标注 rad。

**19. FC_DL_RoundSat**（四舍五入取整饱和）
- 引脚：`fX : LREAL; // 输入实数`；返回 `DINT; // 取整结果（个）`；`eErr : WORD`（建议信息级 `16#0001_015B`：溢出钳位方向记录；故障级 `16#0001_022B`：非有限输入）
- 边界安全：非有限拦截；DINT 域外（> 2147483647.49… / < −2147483648.49…）**钳位到 DINT 端点并置信息码，不回绕**；「.5 半值取向」（四舍五入 = 远离零 / 银行家）在头注释写死本库取「四舍五入远离零」（多数平台 ROUND 语义），与 FLOOR/CEIL 组合可复现银行家者自便。

**20. FC_DL_StringMidEx**（取子串）
- 引脚：`sIn : STRING; // 源串`｜`iStart : INT; // 起始位序（1 基）`｜`iLen : INT; // 取长（字符数）`；返回 `STRING; // 子串`；`eErr : WORD`（建议信息级 `16#0001_015C`：参数钳位（iStart<1 钳 1 / iLen<0 钳 0 / 越出串长截断）；信息级 `16#0001_015D`：结果触 255 上限截断）
- 边界安全：LEN 一次锁存 → 参数钳位 → 越界组合（iStart > LEN 返回空串）→ 委托内建 MID；**bTruncated 截断标志经 eErr 显式化**（沿 R37 范式：截断判定先于任何写入）；空串输入直接空串返回。

## 6. 双语注释统一要求（全 20 件）

1. 头注释块：组件名称 / 所属子库 / 版本 v1.0.0 / 兼容性（CODESYS V3.5+ / TwinCAT 3 / InoProShop）/ 功能描述 / 溯源（IEC 61131-3 标准语义的道莅防御性实现）/ 修订历史——**中英双列**。
2. 每个变量声明行同行 `//` 中文注释，含物理意义与单位（TIME→ms、角度→rad、计数→个、位串→位）。
3. 与 IEEE/平台默认行为的差异点（NaN→0.0+码、饱和不回绕、首扫不假触发、n≥32 置 0）必须在头注释「防御行为声明」小节用中英对照写明——这是 T0 包装层的核心交付价值。

## 7. 验收要点（编码阶段执行）

- 八条红线逐条自检；浮点禁 `=` 判等；无魔法数（1E-12 极点容差、DINT 端点等提为常量并注释）；CASE/ENUM 不适用件（纯函数）免除。
- 码位终审：全库求差脚本断言（R30 教训），任何「建议值」撞号时顺延并在 VERSION.md 台账登记。
- 零检索留痕：本轮无外部源下载，`_Staging_Raw\2026-11-16\` 仅存本计划与 RAW_NOTES，无原始代码备份。
