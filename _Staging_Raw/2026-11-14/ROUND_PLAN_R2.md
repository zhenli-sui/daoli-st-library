# ROUND_PLAN_R2 ｜ 道莅万级工业代码库 · 第二轮需求规格书

> **文档编号**：DL-RP-2026-11-14-002
> **阶段**：Phase 1 第二轮批处理 ｜ Level 0（DL_Base + DL_MathData）
> **本轮范围**：12 个组件（7 个 DL_Base + 5 个 DL_MathData）
> **撰写人**：道莅工控代码库产品总监（Daoli Library Director）
> **下游执行**：PLC 编程专家（编码 Agent）—— **本文件不含任何 .st 实现代码，禁止在此阶段产出 .st 文件**
> **编制日期**：2026-11-14
> **情报支撑**：`C:\Library\_Staging_Raw\2026-11-14\RAW_NOTES_R2.md`（5 次检索）
> **上游输入**：首轮 `ROUND_PLAN.md` §6「下一轮前置输入」、`AGENT_EVOLUTION_LOG.md` Round 01 规则库 R1~R12

---

## 0 本轮作业定位与纪律

### 0.1 定位

首轮 14 个组件解决了「位逻辑 + 纯数学」的地基问题；本轮 12 个组件补齐 Level 0 的**另一半地基：时序引擎与数据结构**。`FB_DL_ExtendedTimer` / `FB_DL_AlarmManager` / `FB_DL_StepSequencer` / `FB_DL_WatchdogMonitor` 四件套是 Level 1（设备驱动、工艺模板）的高频被依赖项——晚一轮做，上层就多一轮返工。本轮同样**不追求数量，只追求时序语义与数据结构语义的不可逆正确性**：定时器模式切换、报警首出锁存、顺控步推进、环形缓冲回绕，这些语义一旦入库被上层照抄，修正成本是百倍级的。

### 0.2 硬性纪律（下游必须逐条遵守）

| # | 纪律 | 违反后果 |
|---|---|---|
| D1 | **本轮零 `.st` 文件**。编码由下一位 PLC 编程专家执行 | 越权交付，接口与实现脱节 |
| D2 | 接口定义**逐字**以本文件第 2 章为准，不得擅自增删引脚；确有缺陷走「变更申请」回写本文件 | 索引/手册/训练集三方漂移 |
| D3 | 任何组件不得引用 `DL_Algo` / `DL_Device` / `DL_Motion` / `DL_Process` 类型 | 破坏分层单向依赖 |
| D4 | `DL_MathData` 可依赖 `DL_Base`，反向禁止 | 循环依赖 |
| D5 | 命名一律 `FB_DL_` / `FC_DL_` / `E_DL_` / `ST_DL_` 前缀，文件名 = POU 名 | 索引无法自动对齐 |
| D6 | **允许且鼓励依赖首轮已入库的 14 个组件**，但依赖必须按 §1.2 声明清单执行，禁止清单外私自引用 | 依赖图失控，无法机检 |
| D7 | 沿用 Round 01 现行规则库 **R1~R12 全部 12 条**（含 R9 双语注释、R10 语义化自检、R11 收窄留档、R12 可复算向量），逐组件红线自检表按此填写 | 质量倒退 |

### 0.3 红线体系（沿用首轮编号，机检口径不变）

| 编号 | 红线 | 判定口径（可机检） |
|---|---|---|
| **R1** | 零全局变量表与外部变量引用 | 全文扫描命中数 = 0 |
| **R2** | 零物理 IO 地址直写 | 全文扫描命中数 = 0 |
| **R3** | 纯 IEC 61131-3，仅 `Standard.library`，无指针/引用/厂商类型/隐式转换 | 无位访问方言、无 `POINTER TO`/`REFERENCE TO`、无 `SysXxx`/`TcXxx` |
| **R4** | 完整防除零 / 防越界 / 浮点容差 / 循环防死锁 | 除法前置分母绝对值判断；数组下标双检；浮点判等带容差；`WHILE` 有计数器 |
| **R9** | 变量声明行「中文物理意义 + 英文术语 + 工程单位」三者齐全（覆盖原 R5） | 每行声明同行注释三要素 |
| **R6** | 状态机 `ENUM` + `CASE` + `ELSE` 兜底；无状态机标 N/A 并说明 | 三要素齐全 |
| **R7** | `TON`/`TOF`/`R_TRIG`/`F_TRIG` 实例无条件周期刷新 | 所有实例调用位于主体最前部「无条件刷新区」 |
| **R8** | 无魔法数 | 阈值/限幅/超时一律常量化或引脚化 |
| **R10** | 注释与文档描述红线用自然语言，不书写被禁符号 | 扫描器不自伤 |
| **R11** | 偏离本规格书须在头注释留档「收窄/扩展 + 依据条款 + 理由」 | 头注释含留档段 |
| **R12** | 验收测试向量必须实测复算并论证唯一性 | 手册向量表有复算记录 |

> **R12 本轮特别适用**：§2 中给出的全部测试向量（字节序 4 排布矩阵、环形缓冲回绕序列、格雷/字符串样例）编码侧必须逐条复算后才可写入手册，禁止照抄。

---

## 1 本轮目标清单（12 项，名单锁定，不增不删不改）

| # | 组件 | 子库 | 类型 | 复杂度 |
|---|---|---|---|---|
| 1 | `FB_DL_ExtendedTimer` | DL_Base | 功能块 | 5 |
| 2 | `FB_DL_AlarmManager` | DL_Base | 功能块 | 7 |
| 3 | `FB_DL_StepSequencer` | DL_Base | 功能块 | 8 |
| 4 | `FB_DL_WatchdogMonitor` | DL_Base | 功能块 | 4 |
| 5 | `FB_DL_PulseGenerator` | DL_Base | 功能块 | 5 |
| 6 | `FB_DL_CycleTimeMeasure` | DL_Base | 功能块 | 3 |
| 7 | `FB_DL_RuntimeMeter` | DL_Base | 功能块 | 4 |
| 8 | `FC_DL_SwapBytes16` | DL_MathData | 函数 | 2 |
| 9 | `FC_DL_SwapBytes32` | DL_MathData | 函数 | 4 |
| 10 | `FB_DL_RingBufferLReal` | DL_MathData | 功能块 | 5 |
| 11 | `FC_DL_StringTrim` | DL_MathData | 函数 | 3 |
| 12 | `FC_DL_StringSplit` | DL_MathData | 函数 | 6 |

### 1.1 统一故障码分配表（**全库唯一，延续首轮 16#0001_xxxx 体系**）

首轮已登记 `16#0000_0000` ~ `16#0001_0007`，本轮**新增 7 码**（0008~000E），全部在本表登记，不允许各组件自造：

| ErrorID | 含义 | 适用组件 | 来源轮次 |
|---|---|---|---|
| `16#0000_0000` | 无故障 | 全部 | R1 |
| `16#0001_0001` | 参数越界（位索引/窗口/预设时间/周期/占空比/优先级/最大字段数超范围） | 首轮 7 组件 + 本轮 #1 #2 #3 #4 #5 #7 #12 | R1 |
| `16#0001_0002` | 量程 / 分母为零或近零（`|x| ≤ 1E-6`） | 首轮 3 组件 + 本轮 #6 | R1 |
| `16#0001_0003` | 参数符号非法（负宽度/负量程） | 首轮 2 组件 | R1 |
| `16#0001_0004` | 循环保护触发（`WHILE`/`FOR` 超出防死锁上限） | 首轮 2 组件 + 本轮 #11 #12 | R1 |
| `16#0001_0005` | 状态机进入非法状态（`CASE ... ELSE` 兜底命中） | 首轮 2 组件 + 本轮 #1 #3 #4 #5 | R1 |
| `16#0001_0006` | 输入数据非法（NaN / Inf，仅平台支持检测时可用） | 首轮 3 组件 | R1 |
| `16#0001_0007` | 数值溢出（计数型输出饱和停增） | 首轮 2 组件 + 本轮 #2 #6 #7 | R1 |
| **`16#0001_0008`** | **输入数据非法（负/零时间增量、心跳跳变频率越界、分隔符长度非法）** | 本轮 #4 #6 #7 #12 | **R2 新增** |
| **`16#0001_0009`** | **缓冲区/容量满，写入被拒绝** | 本轮 #10 | **R2 新增** |
| **`16#0001_000A`** | **缓冲区空，读取被拒绝** | 本轮 #10 | **R2 新增** |
| **`16#0001_000B`** | **顺控步超时故障** | 本轮 #3 | **R2 新增** |
| **`16#0001_000C`** | **心跳超时（看门狗触发锁定）** | 本轮 #4 | **R2 新增** |
| **`16#0001_000D`** | **拆分字段数超出输出缓冲，结果被截断** | 本轮 #12 | **R2 新增** |
| **`16#0001_000E`** | **输入模式/枚举值非法（超出类型定义域，如被强制写入）** | 本轮 #1 #9 | **R2 新增** |

> 编码约定：实际写入 `16#0001_0001` ~ `16#0001_000E` 十六进制字面量；`FC_DL_PackBitsToWord` 的「显式豁免无故障码」决定（首轮 P3）继续有效，本轮 `FC_DL_SwapBytes16` 按同一先例豁免（见 §2.8 决策记录）。

### 1.2 组件间依赖关系声明（唯一合法依赖清单）

| 依赖方 | 被依赖方 | 用途 | 来源 |
|---|---|---|---|
| `FB_DL_AlarmManager`（#2） | `FC_DL_PackBitsToWord`（首轮 #6） | 将 16 路激活报警打包为 `uAlarmWord` 输出 | R1 |
| `FB_DL_WatchdogMonitor`（#4） | `FB_DL_DualEdgeTrig`（首轮 #2） | 心跳双沿检测（`bChanged` 判跳变、计数复用其输出口径） | R1 |

其余 10 个组件**零内部依赖**，可独立编译、独立单测、独立入库。依赖方向均为 DL_Base 内部或 DL_MathData 无依赖，符合 D4。**禁止在清单外新增任何内部调用**（D6）。

### 1.3 建议编码顺序与分批

- **顺序**：8 → 11 → 12 → 6 → 7 → 4 → 5 → 1 → 10 → 2 → 3（由简入繁；先函数后功能块；两个重组件 #2 #3 收尾——它们分别是「无状态机仲裁」与「全轮最高复杂度状态机」的两极样板）。
- **批次 A**（#8 #11 #12 #6 #7，5 个轻组件）：字符串族 + 时间注入族，验证 `STRING(255)` 与 `uDeltaTimeMs` 两个新基础约定。
- **批次 B**（#4 #5 #1，3 个时序块）：看门狗 → 脉冲发生 → 多模式定时器，共享「TON 无条件刷新 + 模式切换语义」实现语感。
- **批次 C**（#10 #9，2 个数据结构/字节序）：环形缓冲 + 32 位字节序。
- **批次 D**（#2 #3，2 个重组件）：报警仲裁 + 顺控引擎。

---

## 2 逐组件需求规格

> 每个组件固定 6 段：**功能定位 → 接口契约 → 边界防御 → 红线自检 → AI 语料方向**（接口块中所有 `:=` 为默认值建议；枚举类型与所属功能块可同文件，头注释注明归属）。

---

### 2.1 `FB_DL_ExtendedTimer` ｜ DL_Base ｜ 复杂度 5

**功能定位**：四模式工业定时器（通电延时 / 断电延时 / 单脉冲 / 保持型累加），一个实例覆盖 TON/TOF/TP/RTO 全部现场时序需求——解决「同一个计时需求在项目里散落四种定时器实现、改造时漏改某处」的维护问题。RTO（Retentive On-Delay）是 AB/Omron 生态高频模式，IEC 标准库缺失，由本块补齐。

**接口契约**

```iecst
TYPE E_DL_TimerMode :
(
    eTon := 0,    // 通电延时：输入保持 TRUE 满 PT 后输出 TRUE / On-delay
    eTof := 1,    // 断电延时：输入 TRUE 期间输出 TRUE，输入变 FALSE 后延时 PT 再复位 / Off-delay
    eTp  := 2,    // 单脉冲：输入上升沿触发 PT 时长脉冲，可重触发 / Pulse, retriggerable
    eRto := 3     // 保持型累加：输入 TRUE 累加计时，断开保持进度，仅复位可清零 / Retentive on-delay
);
END_TYPE

TYPE E_DL_ExtTimerState :
(
    eIdle   := 0,     // 待机，输出为该模式待机值 / Idle, output at mode rest value
    eTiming := 10,    // 计时进行中 / Timing in progress
    eDone   := 20,    // 完成，输出保持 / Done, output held
    eFault  := 99     // 故障锁定 / Fault latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ExtendedTimer
VAR_INPUT
    bIn       : BOOL;                  // 输入信号（电平语义） / Input signal, level semantics
    eMode     : E_DL_TimerMode := eTon;  // 工作模式 / Operating mode
    tPreset   : TIME := T#10S;         // 预设时间 [ms]，合法域 T#0S ~ 上限 / Preset time, valid range up to clamp
    bReset    : BOOL;                  // 上升沿：清零 RTO 累计与故障 / Rising edge: clear RTO accumulation and fault
END_VAR
VAR_OUTPUT
    bQ        : BOOL;    // 输出（语义随模式，见 B 系列） / Output, semantics per mode
    bTiming   : BOOL;    // 计时进行中标志 / Timing in progress
    tElapsed  : TIME;    // 当前模式下的已计时 [ms]（RTO 为累计值）/ Elapsed time in current mode, RTO = accumulated
    tRemaining: TIME;    // 距完成剩余 [ms]，完成或待机为 T#0S / Remaining time
    uErrorId  : UDINT;   // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbTrigRise  : R_TRIG;              // 输入上升沿（TP/通用沿检测） / Input rising edge
    fbTrigFall  : F_TRIG;              // 输入下降沿（TOF 启动） / Input falling edge
    fbTonPhase  : TON;                 // 相位计时器（各模式共用） / Phase timer shared by modes
    eState      : E_DL_ExtTimerState;  // 主状态机 / Main state machine
    tAccum      : TIME;                // RTO 累计时间 [ms] / RTO accumulated time
    eLastMode   : E_DL_TimerMode;      // 上周期模式（变更检测） / Previous mode for change detection
END_VAR
VAR CONSTANT
    DL_TIMER_PRESET_MAX : TIME := T#12H;   // 预设时间上限钳位 [h] / Preset clamp
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 三实例无条件刷新 | `fbTrigRise(CLK := bIn)` / `fbTrigFall(CLK := bIn)` / `fbTonPhase` 必须位于主体最前部无条件调用（R7）；`fbTonPhase.IN` 由状态与输入推导，`PT` 取当前模式所需时长 |
| B2 | 四模式输出语义表 | TON：输入 TRUE 满 PT → `bQ := TRUE`，输入 FALSE 立即 `bQ := FALSE` 且 `tElapsed := T#0S`。TOF：输入 TRUE 期间 `bQ := TRUE`；输入 FALSE 后保持 `bQ := TRUE` 计时 PT 再复位。TP：上升沿触发，`bQ` 保持 TRUE 满时长，期间输入变 FALSE **不中断**；新上升沿重触发重新计时。RTO：输入 TRUE 累加，输入 FALSE 保持 `tAccum`，达 PT 后 `bQ := TRUE` 且不再受输入影响，仅 `bReset` 清零。手册必须原样收录此表 |
| B3 | 预设钳位 | `tPreset > DL_TIMER_PRESET_MAX` → 钳到上限 + `uErrorId := 16#0001_0001`，**继续计时不中断**（P-03 范式）；`tPreset = T#0S` 合法（立即完成） |
| B4 | 运行中模式切换 | `eMode <> eLastMode` → 立即中止当前计时：`eState := eIdle`、`tElapsed := T#0S`、`tAccum := T#0S`、`bQ` 按新模式待机值输出。**不产生故障码**（属操作语义，非故障），手册写明「模式切换即计时作废」 |
| B5 | RTO 精确累计 | 输入 FALSE 时 `fbTonPhase.IN := FALSE` 会清 `ET`，因此 RTO 必须**每周期在 `fbTonPhase` 刷新后立即把 `fbTonPhase.ET` 增量并入 `tAccum`**（或采用「相位定时器 + 差分累加」），禁止直接读 `ET` 当累计值；恢复输入时从 `tAccum` 继续 |
| B6 | 复位语义 | `bReset` 上升沿：`tAccum := T#0S`、`eState := eIdle`、`uErrorId := 0`、`bQ` 回待机值；对 RTO 是唯一清零路径 |
| B7 | 非法模式兜底 | `eMode` 被强制写入枚举域外值时，模式分派 `CASE ... ELSE` → `eState := eFault` + `uErrorId := 16#0001_000E`，`bQ := FALSE` |
| B8 | 输出单一出口 | `bQ` / `tElapsed` / `tRemaining` 只在主体末尾统一赋值一次（P-05），分支内只改状态 |
| B9 | 剩余时间钳位 | `tRemaining := tPresetEff - tElapsed`，结果为负（浮点/时序竞态）时钳到 `T#0S` |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B3 钳位、B9 负值）｜ R9 ✓ ｜ R6 ✓（四态 ENUM + ELSE 兜底）｜ R7 ✓（B1，本组件核心考点）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓`

**AI 训练语料 instruction 方向**
> 「产线混用 TON/TOF/TP，改造时同一延时逻辑散落十几处漏改。请用 IEC 61131-3 ST 写一个四模式可切换定时器功能块（通电延时/断电延时/单脉冲/保持型累加），要求模式运行中切换立即作废当前计时、保持型模式的累计值在输入断开后不丢失且只能显式复位清零，所有定时器实例每周期无条件刷新，并用 ENUM+CASE 状态机带 ELSE 兜底实现。」

---

### 2.2 `FB_DL_AlarmManager` ｜ DL_Base ｜ 复杂度 7

**功能定位**：16 通道报警优先级仲裁器：区分停机级（1）/警告级（2）/提示级（3）三级优先、输出激活位图报警字、锁存首出故障（First-Out）直至确认——解决「几十个报警同时跳出、操作工不知道先处理哪个、首出原因被后续连锁报警淹没」的 ISA-18.2 典型痛点。只做仲裁与锁存，**不做**事件历史与抑制管理（见 D-R2-06）。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_AlarmManager
VAR_INPUT
    abAlarmActive : ARRAY[0..15] OF BOOL;    // 16 路报警激活态，电平敏感，TRUE = 报警中 / 16 alarm active levels, level-sensitive
    auPriority    : ARRAY[0..15] OF USINT;   // 通道优先级 0=禁用 1=停机级 2=警告级 3=提示级 / Channel priority
    bAck          : BOOL;                    // 上升沿确认：清除首出锁存 / Rising edge: acknowledge first-out latch
    bEnable       : BOOL := TRUE;            // 使能，FALSE 时全部输出清零 / Enable, FALSE clears all outputs
END_VAR
VAR_OUTPUT
    uAlarmWord    : WORD;     // 激活报警位图，bit0 = 通道 0（仅含启用通道） / Active alarm bitmap, bit0 = ch0
    uActiveCount  : USINT;    // 激活通道数 0..16 / Active channel count
    bAnyActive    : BOOL;     // 存在任意激活报警 / Any alarm active
    bShutdown     : BOOL;     // 存在停机级激活报警（联锁用）/ Any stop-level alarm active
    nFirstOutIdx  : INT;      // 首出通道索引，-1 = 无 / First-out channel index, -1 = none
    bFirstOutAck  : BOOL;     // 首出已确认标志 / First-out acknowledged
    nTopPrioIdx   : INT;      // 当前最高优先级激活通道（同级先到先得），-1 = 无 / Top-priority active channel
    uErrorId      : UDINT;    // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    auSeqNo       : ARRAY[0..15] OF UDINT;  // 通道激活序号（0 = 从未激活）/ Activation sequence number, 0 = never
    uSeqNext      : UDINT;    // 全局递增序号发生器 / Global sequence generator
    uAckSeq       : UDINT;    // 最近一次确认时刻的序号水位 / Sequence watermark at last acknowledge
    bLatchValid   : BOOL;     // 首出锁存有效 / First-out latch valid
    fbTrigAck     : R_TRIG;   // 确认上升沿 / Ack rising edge
    nIdx          : INT;      // 扫描索引 / Scan index
    nBestPrio     : USINT;    // 扫描中最优优先级 / Best priority during scan
    uBestSeq      : UDINT;    // 扫描中最优序号 / Best sequence during scan
    abPackSrc     : ARRAY[0..15] OF BOOL; // 打包用中间数组（禁用通道置 FALSE）/ Packing source, disabled = FALSE
END_VAR
VAR CONSTANT
    DL_ALM_CH_COUNT    : INT   := 16;             // 通道数，与数组维度一致 / Channel count, must match arrays
    DL_ALM_PRIO_STOP   : USINT := 1;              // 停机级 / Stop level
    DL_ALM_PRIO_WARN   : USINT := 2;              // 警告级 / Warning level
    DL_ALM_PRIO_INFO   : USINT := 3;              // 提示级 / Info level
    DL_ALM_PRIO_MAX    : USINT := 3;              // 合法优先级上限 / Max valid priority
    DL_ALM_IDX_NONE    : INT   := -1;             // 无效通道索引哨兵 / Sentinel for no channel
    DL_ALM_SEQ_MAX     : UDINT := 16#FFFF_FFFE;   // 序号饱和上限 / Sequence saturation limit
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | `R_TRIG` 无条件刷新 | `fbTrigAck(CLK := bAck)` 位于主体最前部（R7） |
| B2 | 激活沿序号分配 | 每周期对 16 通道扫描：`abAlarmActive[i] = TRUE 且 auSeqNo[i] = 0` → `auSeqNo[i] := uSeqNext` 递增取号。**电平敏感语义**：冷启动时已为 TRUE 的通道在首扫按扫描顺序依次取号（手册必须写明该行为，D-R2-04） |
| B3 | 优先级钳位 | `auPriority[i] > DL_ALM_PRIO_MAX` → 按 3（提示级）处理 + `uErrorId := 16#0001_0001`（每周期持续告警）；`0` = 通道禁用：不参与计数、不参与仲裁、报警字对应位强制 0 |
| B4 | 仲裁规则 | 首出：激活通道中 `auSeqNo[i]` 最小者（先到先得，与优先级无关）；`nTopPrioIdx`：激活通道中优先级数值最小者，同级中 `auSeqNo[i]` 最小者。扫描为有限 `FOR`（0..15），找到更优者覆盖，无 `WHILE` |
| B5 | 确认语义（三态分离） | `bAck` 上升沿：`uAckSeq := uSeqNext`（水位推进）、`bFirstOutAck := TRUE`；首出锁存重算：激活通道中序号 > 水位的最早者成为新首出，无则 `nFirstOutIdx := -1`。**确认不清除激活态**——Active / Acknowledged / First-Out 三信号正交输出（D-R2-07） |
| B6 | 序号饱和 | `uSeqNext` 达 `DL_ALM_SEQ_MAX` 停止递增 + `uErrorId := 16#0001_0007`（不回绕，回绕会破坏先到先得序） |
| B7 | 报警字打包 | 经 `FC_DL_PackBitsToWord(abPackSrc)` 生成 `uAlarmWord`（依赖声明 §1.2）；`abPackSrc[i] := abAlarmActive[i] AND (auPriority[i] > 0)`，先构造后调用 |
| B8 | 使能语义 | `bEnable := FALSE` → 全部输出清零（含首出锁存与序号表清零）；重新使能视同冷启动重扫（显式决策，手册写明，避免「禁用期间的历史报警在恢复瞬间集中爆发」） |
| B9 | 数组双检 | 所有数组访问以 `nIdx >= 0 AND nIdx < DL_ALM_CH_COUNT` 前置（R4） |
| B10 | 无状态机声明 | 本组件为纯仲裁扫描 + 锁存，**无主状态机**，红线自检 R6 标 N/A 并注明「仲裁为每周期全量重算，无跨周期状态转移」 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B3 钳位、B6 饱和、B9 双检）｜ R9 ✓ ｜ R6 N/A（B10 已说明）｜ R7 ✓（B1）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓`

**AI 训练语料 instruction 方向**
> 「包装机 16 个工位的报警同时涌进 HMI，操作工每次都先处理了警告级而放过真正的停机级故障，事后也查不出第一个跳出的原因。请写一个 16 通道报警仲裁功能块：通道可配置停机/警告/提示三级优先级，输出激活报警字、停机级联锁位与首出通道索引，首出锁存直到确认信号上升沿，确认后若还有新激活按先后顺序补位，注意冷启动时已处于报警态的通道要按扫描顺序取号。」

---

### 2.3 `FB_DL_StepSequencer` ｜ DL_Base ｜ 复杂度 8（本轮最高）

**功能定位**：通用顺控步引擎（Grafcet/SFC 的 ST 基类形态）：管理当前步号、步内计时、步超时监控、暂停/单步、故障锁存——**动作不在块内写死**，调用方按 `nCurrentStep` 执行动作、按 `abStepDone[nCurrentStep]` 回报完成（D-R2-08）。解决「顺控逻辑散落在十几个 IF 里、某一步反馈丢失后整机挂死无人知晓、现场调试没有单步手段」三大顽疾。

**接口契约**

```iecst
TYPE E_DL_SeqState :
(
    eIdle  := 0,     // 空闲待机 / Idle
    eRun   := 10,    // 顺控运行中 / Running
    eHold  := 20,    // 暂停（保持/单步等待）/ Held
    eDone  := 30,    // 全部步完成 / All steps done
    eFault := 99     // 故障锁定（步超时或非法状态）/ Fault latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_StepSequencer
VAR_INPUT
    bStart        : BOOL;                      // 上升沿：从 0 号步启动（eIdle/eDone/eFault 且已 Reset 时有效）/ Rising edge: start from step 0
    abStepDone    : ARRAY[0..15] OF BOOL;      // 步完成信号（电平，由调用方按当前步维护）/ Step-done levels, caller-maintained
    auStepTimeout : ARRAY[0..15] OF TIME;      // 每步超时 [ms]，T#0S = 该步不监控 / Per-step timeout, 0 = no monitoring
    bHold         : BOOL := FALSE;             // TRUE = 暂停：冻结推进与超时计时 / TRUE = hold advancing and timeout
    bSingleStep   : BOOL := FALSE;             // TRUE = 单步调试模式 / Single-step commissioning mode
    bAdvance      : BOOL;                      // 单步模式下上升沿推进一步 / Rising edge: advance one step in single-step mode
    bAbort        : BOOL;                      // 上升沿：中止顺控回空闲（不设故障码）/ Rising edge: abort to idle, no error raised
    bReset        : BOOL;                      // 上升沿：清除故障回空闲 / Rising edge: clear fault to idle
END_VAR
VAR_OUTPUT
    nCurrentStep  : INT;     // 当前步号 0..15，-1 = 未运行 / Current step, -1 = inactive
    bRunning      : BOOL;    // eRun 状态标志 / Running flag
    bDone         : BOOL;    // 全部步完成 / All steps done
    bError        : BOOL;    // 故障标志，bReset 清除 / Fault flag
    nFaultStep    : INT;     // 超时故障发生步号，-1 = 无 / Fault step, -1 = none
    tStepElapsed  : TIME;    // 当前步已运行时间 [ms] / Elapsed in current step
    uErrorId      : UDINT;   // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    eState        : E_DL_SeqState;   // 主状态机 / Main state machine
    fbTonStep     : TON;             // 步计时器 / Step timer
    fbTrigStart   : R_TRIG;          // 启动沿 / Start edge
    fbTrigAbort   : R_TRIG;          // 中止沿 / Abort edge
    fbTrigReset   : R_TRIG;          // 复位沿 / Reset edge
    fbTrigAdvance : R_TRIG;          // 单步推进沿 / Advance edge
    nStep         : INT;             // 内部步号 / Internal step index
    tEffTimeout   : TIME;            // 当前步生效超时（已钳位）/ Effective clamped timeout of current step
    bTimeoutArmed : BOOL;            // 当前步是否启用超时监控 / Timeout armed for current step
END_VAR
VAR CONSTANT
    DL_SEQ_MAX_STEPS : INT  := 16;      // 步数上限，与数组维度一致 / Step count, must match arrays
    DL_SEQ_IDX_NONE  : INT  := -1;      // 无效步号哨兵 / Sentinel for no step
    DL_SEQ_TOUT_MAX  : TIME := T#12H;   // 单步超时上限钳位 / Per-step timeout clamp
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 四 `R_TRIG` + `TON` 无条件刷新 | 五个实例全部位于主体最前部（R7）；`fbTonStep(IN := (eState = eRun) AND (NOT bHold) AND bTimeoutArmed AND (NOT bJustAdvanced), PT := tEffTimeout)` —— `bJustAdvanced` 为推进当周期的单周期标志，保证换步瞬间计时器清零重新起算 |
| B2 | 完成信号只采当前步 | 仅在 `eRun` 且 `nStep` 合法时读取 `abStepDone[nStep]`；读前双检下标（R4）。**步推进瞬间完成位重新采样**：换步后第一个周期不得读到旧步残留 TRUE（防「不稳定转换」连环跳步，D-R2-09），实现上由 B1 的 `bJustAdvanced` 屏蔽当周期完成判定 |
| B3 | 超时钳位与禁用 | 进入新步时取 `auStepTimeout[nStep]`：`> DL_SEQ_TOUT_MAX` → 钳到上限 + `uErrorId := 16#0001_0001`；`= T#0S` → `bTimeoutArmed := FALSE`（该步不监控，挂死风险由调用方自担，手册明示） |
| B4 | 步超时故障 | `fbTonStep.Q = TRUE` → `eState := eFault`、`nFaultStep := nStep`、`uErrorId := 16#0001_000B`、`bError := TRUE`、`nCurrentStep` 保持（便于定位现场） |
| B5 | 暂停语义 | `bHold = TRUE`：`fbTonStep.IN := FALSE`（计时冻结，恢复后**重新计时**——D-R2-10 明确「暂停不算超时」的代价是恢复后重新起算，手册给出两种语义对照表）；推进判定同样冻结；对 `eIdle/eDone/eFault` 无作用 |
| B6 | 单步模式 | `bSingleStep = TRUE` 时：每步完成条件满足后进入 `eHold`，`bAdvance` 上升沿才真正推进到下一步（先评估超时再推进）；`bHold` 与单步可叠加使用 |
| B7 | 中止语义 | `bAbort` 上升沿：`eState := eIdle`、`nStep := -1`、计时清零、**不设故障码**（操作员主动中止非故障）；`eFault` 态下 `bAbort` 无效，必须 `bReset` |
| B8 | 完成判定 | 末步（`DL_SEQ_MAX_STEPS - 1`）完成 → `eDone`、`bDone := TRUE`、`nCurrentStep` 保持末步号；`bStart` 在 `eDone` 下重新启动（自动复位 `bDone`） |
| B9 | 复位语义 | `bReset` 上升沿（仅 `eFault` 有效）：`eState := eIdle`、`uErrorId := 0`、`bError := FALSE`、`nFaultStep := -1` |
| B10 | 非法状态兜底 | `CASE ... ELSE` → `eState := eFault` + `uErrorId := 16#0001_0005`（R6） |
| B11 | 数组双检 | `auStepTimeout` / `abStepDone` 访问前 `nStep >= 0 AND nStep < DL_SEQ_MAX_STEPS`（R4） |
| B12 | 手册披露项 | 必须写明：步完成信号为电平语义时，调用方需在新步开始后撤销旧步完成位；`bDone` 后输出动作已由调用方收回；RETAIN 策略由调用方决定 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B2/B11 双检、B3 钳位）｜ R9 ✓ ｜ R6 ✓（五态 ENUM + ELSE 兜底）｜ R7 ✓（B1，五个实例全无条件）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓`

**AI 训练语料 instruction 方向**
> 「装配机顺控逻辑写了 14 个嵌套 IF，某工位光纤传感器坏掉后机器在第 7 步无限期挂死，没有任何提示，现场调试也没有单步手段。请写一个通用顺控步引擎功能块：管理 0~15 步的当前步号输出，调用方按步号执行动作并回报完成信号，每步可配独立超时且超时锁定故障并记录步号，支持暂停（暂停期间超时冻结）、单步推进调试模式与主动中止，要求所有定时器和边沿实例每周期无条件刷新，ENUM+CASE 状态机带 ELSE 兜底。」

---

### 2.4 `FB_DL_WatchdogMonitor` ｜ DL_Base ｜ 复杂度 4

**功能定位**：外部心跳信号看门狗：监控上位机/HMI/从站心跳的**跳变间隔**是否超窗——解决「通信断了但 PLC 还在给输出保持旧值」「上位机脚本卡死但 TCP 连接还在、单纯查连接状态查不出来」的静默失效问题。监控对象是**跳变**不是电平（D-R2-19）。

**接口契约**

```iecst
TYPE E_DL_WdtState :
(
    eArmed    := 0,    // 监控中 / Armed
    eFault    := 10,   // 心跳超时锁定 / Timeout latched
    eDisabled := 20    // 未启用 / Disabled
);
END_TYPE

FUNCTION_BLOCK FB_DL_WatchdogMonitor
VAR_INPUT
    bHeartbeat   : BOOL;              // 被监控心跳信号（期望周期性跳变）/ Monitored heartbeat, expected toggling
    tMaxInterval : TIME := T#2S;      // 最大允许跳变间隔 [ms] / Max allowed toggle interval
    tMinInterval : TIME := T#5MS;     // 最小合法跳变间隔 [ms]，低于视为异常信号 / Min legal interval, below = abnormal
    bEnable      : BOOL := TRUE;      // 使能 / Enable
    bReset       : BOOL;              // 上升沿：清除故障并重新武装 / Rising edge: clear fault and re-arm
END_VAR
VAR_OUTPUT
    bAlive       : BOOL;    // 心跳健康（未超时且未触发频率异常）/ Heartbeat healthy
    bTimeout     : BOOL;    // 心跳超时锁存 / Timeout latched
    tSinceToggle : TIME;    // 距上次跳变的时长 [ms] / Time since last toggle
    uToggleCount : UDINT;   // 累计跳变次数（诊断用）/ Accumulated toggles, diagnostics
    bError       : BOOL;    // 故障标志，bReset 清除 / Fault flag
    uErrorId     : UDINT;   // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    fbDual       : FB_DL_DualEdgeTrig;  // 双沿检测（依赖 R1 #2，见 §1.2）/ Dual-edge detector, R1 dependency
    fbTonWatch   : TON;                 // 看门狗窗口计时器 / Watchdog window timer
    fbTrigReset  : R_TRIG;              // 复位上升沿 / Reset rising edge
    eState       : E_DL_WdtState;       // 主状态机 / Main state machine
    tMinLast     : TIME;                // 上次跳变距上上次跳变的间隔（频率异常判定）[ms] / Last toggle interval for rate check
END_VAR
VAR CONSTANT
    DL_WDT_INTERVAL_MAX : TIME := T#1H;  // 超时窗上限钳位 / Max window clamp
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 三实例无条件刷新 | `fbDual(CLK := bHeartbeat)`、`fbTonWatch`、`fbTrigReset(CLK := bReset)` 位于主体最前部（R7）；`fbTonWatch(IN := (eState = eArmed) AND (NOT fbDual.bChanged) AND bEnable, PT := tMaxInterval)` —— 跳变当周期 `IN` 断开使 `ET` 清零重新起算 |
| B2 | 超时锁定 | `fbTonWatch.Q = TRUE` → `eState := eFault`、`bTimeout := TRUE`、`bError := TRUE`、`uErrorId := 16#0001_000C`、`bAlive := FALSE`；锁存直至 `bReset` |
| B3 | 频率异常防御 | 相邻两次跳变间隔 `< tMinInterval` → `bAlive := FALSE` 告警 + `uErrorId := 16#0001_0008`（心跳被写成恒振荡/接线抖动时能被发现，D-R2-19）；该告警**不锁存**，间隔恢复正常自动消除，但 `uToggleCount` 继续累计 |
| B4 | 窗口钳位 | `tMaxInterval > DL_WDT_INTERVAL_MAX` → 钳到上限 + `uErrorId := 16#0001_0001`；`tMaxInterval = T#0S` → 视为非法（监控无意义）+ `16#0001_0001` 且 `bTimeout` 直接受理 |
| B5 | 跳变计数复用 | `uToggleCount := fbDual.uRiseCount + fbDual.uFallCount`（依赖 #2 的饱和口径，不自行再计）；饱和行为随 `FB_DL_DualEdgeTrig`（16#0001_0007） |
| B6 | 使能语义 | `bEnable := FALSE` → `eState := eDisabled`、`bAlive/bTimeout/bError` 清 FALSE、`tSinceToggle := T#0S`；重新使能**视同首次武装**（等第一个跳变，窗口内无跳变则正常超时——心跳必须先跳变一次才建立信任，手册写明） |
| B7 | 冷启动语义 | 上电即 `eArmed`：窗口内无任何跳变 → 超时（正确行为：心跳信号必须先证明自己活着） |
| B8 | 复位语义 | `bReset` 上升沿（`eFault` 态）：清 `bTimeout/bError/uErrorId`、回 `eArmed`、看门狗窗口重新起算 |
| B9 | 非法状态兜底 | `CASE ... ELSE` → `eFault` + `16#0001_0005`（R6） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B4 钳位）｜ R9 ✓ ｜ R6 ✓（三态 ENUM + ELSE 兜底）｜ R7 ✓（B1）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓ ｜ 依赖声明 ✓（fbDual = 首轮 #2）`

**AI 训练语料 instruction 方向**
> 「上位机通过心跳信号告知 PLC 自己活着，某次上位机程序死循环但网络连接还在，PLC 拿着旧数据继续控制了两小时。请写一个心跳看门狗功能块：监控心跳信号的跳变间隔，超过设定窗口即锁定故障输出，同时检测心跳跳得过快（接线抖动或程序写错成恒振荡）并告警，故障需显式复位，所有定时器与边沿实例每周期无条件刷新，可用已有双边沿检测功能块复用其跳变计数。」

---

### 2.5 `FB_DL_PulseGenerator` ｜ DL_Base ｜ 复杂度 5

**功能定位**：可调周期与占空比的方波发生器，支持运行时改参与相位复位——解决「需要 0.3s 通 0.7s 断的间歇喷吹/闪烁灯/步进节拍，现场却用两个定时器对拼、改参数要动两处」的问题。采用 ENUM 相位状态机 + TON 实现（D-R2-02），不引入平台时刻函数。

**接口契约**

```iecst
TYPE E_DL_PulsePhase :
(
    eInit  := 0,     // 上电/未使能首态：输出低 / Power-up or disabled, output low
    eHigh  := 10,    // 高电平相位 / High phase
    eLow   := 20,    // 低电平相位 / Low phase
    eFault := 99     // 故障锁定 / Fault latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_PulseGenerator
VAR_INPUT
    bEnable     : BOOL := TRUE;    // 使能，FALSE 时输出 FALSE 并复位相位 / Enable, FALSE resets phase
    tPeriod     : TIME := T#1S;    // 周期 [ms]，合法域下限 ~ 上限 / Period
    fDutyCycle  : REAL := 0.5;     // 占空比 0.0~1.0，0 = 恒低，1 = 恒高 / Duty ratio, 0 = always low, 1 = always high
    bPhaseReset : BOOL;            // 上升沿：相位回高电平起点 / Rising edge: restart at high phase
END_VAR
VAR_OUTPUT
    bPulseOut   : BOOL;    // 方波输出 / Square-wave output
    fProgress   : REAL;    // 当前周期进度 0.0~1.0 / Cycle progress 0.0..1.0
    bError      : BOOL;    // 故障标志 / Fault flag
    uErrorId    : UDINT;   // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    fbTonPhase  : TON;               // 相位计时器 / Phase timer
    fbTrigReset : R_TRIG;            // 相位复位沿 / Phase reset edge
    ePhase      : E_DL_PulsePhase;   // 相位状态机 / Phase state machine
    tHighTime   : TIME;              // 高电平持续 [ms] / High duration
    tLowTime    : TIME;              // 低电平持续 [ms] / Low duration
    tPeriodEff  : TIME;              // 钳位后周期 / Clamped period
    fDutyEff    : REAL;              // 钳位后占空比 / Clamped duty
END_VAR
VAR CONSTANT
    DL_PULSE_PERIOD_MIN : TIME := T#2MS;    // 周期下限：至少两个任务周期可辨 / Min period
    DL_PULSE_PERIOD_MAX : TIME := T#12H;    // 周期上限 / Max period
    DL_FLOAT_EPS        : REAL := 1.0E-6;   // 浮点判零容差 / Float tolerance
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | `TON` + `R_TRIG` 无条件刷新 | 两实例位于主体最前部（R7）；`fbTonPhase.IN := (ePhase = eHigh) OR (ePhase = eLow)`，`PT` 取当前相位时长 |
| B2 | 占空比钳位 | `fDutyCycle < 0.0` → 0.0；`> 1.0` → 1.0；均 + `uErrorId := 16#0001_0001`。与 0/1 的比较用 `ABS(fDutyEff) <= DL_FLOAT_EPS` / `ABS(fDutyEff - 1.0) <= DL_FLOAT_EPS`（R4） |
| B3 | 周期钳位 | `< DL_PULSE_PERIOD_MIN` 或 `> DL_PULSE_PERIOD_MAX` → 钳到边界 + `16#0001_0001`（下限的存在理由：脉冲宽度低于两个任务周期时下游边沿检测会丢沿，手册明示） |
| B4 | 恒高/恒低退化 | 占空比 0 → `bPulseOut := FALSE` 恒低；占空比 1 → 恒高；两态直接输出，相位机仍保持 `eHigh` 且 `TON` 照常无条件刷新（行为可预期） |
| B5 | 时间-实数换算 | `tHighTime/tLowTime` 与 `fProgress` 的计算使用标准类型转换族（`TIME_TO_REAL` 毫秒语义 / `REAL_TO_TIME` 并钳位非负）。**若目标平台（重点排查 InoProShop）实测不支持该转换族，允许按 R11 收窄**：删去 `fProgress` 引脚并以 `tHighTime := tPeriodEff` 的 DINT 中间量实现（头注释留档收窄依据与影响） |
| B6 | 相位复位 | `fbTrigReset.Q` → `ePhase := eHigh`、`fbTonPhase` 当周期 `IN := FALSE` 清零重算 |
| B7 | 使能语义 | `bEnable := FALSE` → `bPulseOut := FALSE`、`ePhase := eInit`；重新使能从 `eHigh` 起步（不用中途相位续跑，避免与外设节拍错位，手册说明） |
| B8 | 非法状态兜底 | `CASE ... ELSE` → `ePhase := eFault` + `16#0001_0005`、`bPulseOut := FALSE`（R6） |
| B9 | 进度钳位 | `fProgress` 钳到 0.0~1.0（换算误差不得溢出） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（B5 转换族合规性按平台实测，必要时 R11 收窄留档）｜ R4 ✓（B2 容差、B3 钳位、B9）｜ R9 ✓ ｜ R6 ✓（四态 ENUM + ELSE 兜底）｜ R7 ✓（B1）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓`

**AI 训练语料 instruction 方向**
> 「除尘系统需要 0.3s 喷吹 0.7s 间歇的脉冲阀节拍，原来是两个定时器互相触发，改节拍要动两处还容易改错。请写一个方波脉冲发生器功能块，周期与占空比运行时可调，占空比 0 与 1 分别退化为恒低恒高，占空比越界钳位告警，周期有下限保护防止脉冲窄到下游采不到，支持相位复位与禁用重启，用 ENUM 相位状态机 + TON 实现，定时器每周期无条件刷新。」

---

### 2.6 `FB_DL_CycleTimeMeasure` ｜ DL_Base ｜ 复杂度 3

**功能定位**：PLC 任务扫描周期统计（最近/最小/最大/平均/样本数）——解决「加了滤波和通信块后任务周期悄悄超时、抖动峰值查不到」的性能劣化问题。**不读任何平台时刻函数**，时间增量由调用方注入（D-R2-01），组件保持零平台依赖。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_CycleTimeMeasure
VAR_INPUT
    uDeltaTimeMs : UDINT;           // 本任务周期实际耗时 [ms]，调用方以系统时间差提供 / Actual cycle time in ms, caller-provided
    bCapture     : BOOL := TRUE;    // TRUE = 本周期计入统计 / TRUE = include this cycle in statistics
    bReset       : BOOL;            // 上升沿清空全部统计 / Rising edge clears statistics
END_VAR
VAR_OUTPUT
    uCycleLast   : UDINT;    // 最近一个周期 [ms] / Last cycle time
    uCycleMin    : UDINT;    // 统计窗内最小周期 [ms] / Minimum in window
    uCycleMax    : UDINT;    // 统计窗内最大周期 [ms] / Maximum in window
    fCycleMean   : REAL;     // 统计窗内平均周期 [ms] / Mean in window
    nSampleCount : UDINT;    // 统计窗内样本数 / Sample count in window
    uErrorId     : UDINT;    // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uSumMs      : UDINT;    // 累计耗时总和 [ms] / Accumulated sum
    fbTrigReset : R_TRIG;   // 复位上升沿 / Reset rising edge
END_VAR
VAR CONSTANT
    DL_CYC_SAMPLE_MAX : UDINT := 1000000;   // 统计窗样本上限，达限自动重开窗并告警 / Window cap
    DL_CYC_DELTA_MAX  : UDINT := 3600000;   // 单周期合理上限 [ms]，超限视为无效数据 / Sanity cap per cycle
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | `R_TRIG` 无条件刷新 | `fbTrigReset(CLK := bReset)` 主体最前部（R7） |
| B2 | 零增量防御 | `uDeltaTimeMs = 0` → 本周期不计入（`uCycleLast` 也不更新）+ `uErrorId := 16#0001_0008`（0 表示调用方没取到时间，不是「0ms 超快周期」） |
| B3 | 离谱增量防御 | `uDeltaTimeMs > DL_CYC_DELTA_MAX` → 不计入 + `16#0001_0008`（防止调用方取错基准产生垃圾样本污染 min/max） |
| B4 | 首样本初始化 | 窗内第一个有效样本同时写入 `uCycleMin` 与 `uCycleMax`（不得用 0 当初值——否则 min 永远是 0 的经典错误） |
| B5 | 平均防除零 | `IF nSampleCount > 0 THEN fCycleMean := UDINT_TO_REAL(uSumMs) / UDINT_TO_REAL(nSampleCount); ELSE fCycleMean := 0.0; END_IF`（R4 双保险口径） |
| B6 | 统计窗滚动 | `nSampleCount` 达 `DL_CYC_SAMPLE_MAX` → 自动重开窗（min/max/sum/count 清零，`uCycleLast` 保留）+ `uErrorId := 16#0001_0007`（无符号累计上限保护，手册写明重开窗行为） |
| B7 | 复位语义 | `bReset` 上升沿：全部输出清零（`uCycleMin`/`uCycleMax` 回 0，下一有效样本重新初始化） |
| B8 | 调用方契约 | 头注释与手册写明：调用方须在同一任务内以「当前系统时刻 − 上周期系统时刻」获得 `uDeltaTimeMs`；本块自身零平台调用（R3 由结构性设计保证） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（B8 结构性保证）｜ R4 ✓（B2/B3 数据防御、B5 除零、B6 饱和）｜ R9 ✓ ｜ R6 N/A（纯统计累加，无状态转移，已说明）｜ R7 ✓（B1）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓`

**AI 训练语料 instruction 方向**
> 「产线改造后加了几个滤波块，任务周期从标称 4ms 悄悄涨到了偶发 9ms，CPU 接近超载报警但没有历史数据可查。请写一个扫描周期统计功能块：由调用方每周期传入实测耗时毫秒数，输出最近/最小/最大/平均周期与样本数，零毫秒与超上限的样本视为无效数据告警而不污染极值统计，样本数达到上限自动重开统计窗，复位沿清空全部统计。」

---

### 2.7 `FB_DL_RuntimeMeter` ｜ DL_Base ｜ 复杂度 4

**功能定位**：设备累计运行时间（分钟/小时双口径）与启停次数统计，带保养到期预警——解决「设备该保养了没人知道」「泵启停次数超过机械寿命」的预测性维护基础数据缺口。时间注入同 2.6（D-R2-01）。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_RuntimeMeter
VAR_INPUT
    bRunning         : BOOL;             // 设备运行反馈（电平，TRUE 期间累计时间）/ Equipment running feedback
    uDeltaTimeMs     : UDINT;            // 本任务周期耗时 [ms]，调用方提供 / Cycle time in ms, caller-provided
    uMaintIntervalMin: UDINT := 0;       // 保养间隔 [min]，0 = 关闭保养预警 / Maintenance interval in minutes, 0 = disabled
    bMaintAck        : BOOL;             // 上升沿：保养确认，重置保养计时 / Rising edge: acknowledge maintenance
    bReset           : BOOL;             // 上升沿：清零全部累计 / Rising edge: clear all totals
END_VAR
VAR_OUTPUT
    uRunTotalMin     : UDINT;     // 累计运行时间 [min] / Total runtime in minutes
    fRunHours        : REAL;      // 累计运行小时 [h]（HMI 直显口径）/ Total runtime in hours
    nStartCount      : UDINT;     // 累计启动次数 / Accumulated start count
    bMaintDue        : BOOL;      // 保养到期（锁存至确认）/ Maintenance due, latched until acknowledged
    uMaintRemainMin  : UDINT;     // 距下次保养剩余 [min]，未启用时为 0 / Minutes to next maintenance
    uErrorId         : UDINT;     // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uTotalSec        : UDINT;    // 累计运行秒 [s] / Total runtime seconds
    uSinceMaintSec   : UDINT;    // 距上次保养累计秒 [s] / Seconds since last maintenance
    uMsCarry         : UDINT;    // 毫秒进位缓存 [ms] / Millisecond carry buffer
    fbTrigRun        : R_TRIG;   // 启动沿检测 / Start rising edge
    fbTrigMaintAck   : R_TRIG;   // 保养确认沿 / Maintenance ack edge
    fbTrigReset      : R_TRIG;   // 复位沿 / Reset edge
END_VAR
VAR CONSTANT
    DL_RT_SEC_PER_MIN  : UDINT := 60;             // 每分钟秒数 / Seconds per minute
    DL_RT_SEC_PER_HOUR : UDINT := 3600;           // 每小时秒数 / Seconds per hour
    DL_RT_MS_PER_SEC   : UDINT := 1000;           // 每秒毫秒数 / Milliseconds per second
    DL_RT_COUNT_MAX    : UDINT := 16#FFFF_FFFE;   // 启动计数饱和上限 / Start count saturation
    DL_RT_DELTA_MAX    : UDINT := 3600000;        // 单周期合理上限 [ms] / Sanity cap per cycle
    DL_RT_HOURS_EPS    : REAL  := 1.0E-4;         // 小时值显示精度容差 / Hours display tolerance
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 三 `R_TRIG` 无条件刷新 | 全部位于主体最前部（R7） |
| B2 | 时间累加进位 | `bRunning` 为 TRUE 时：`uMsCarry += uDeltaTimeMs`；`uMsCarry >= DL_RT_MS_PER_SEC` → 折算整秒并入 `uTotalSec` 与 `uSinceMaintSec`（避免每周期做浮点累加漂移，口径与 MovingAverage 的整数化思想一致） |
| B3 | 增量防御 | `uDeltaTimeMs = 0` 或 `> DL_RT_DELTA_MAX` → 本周期不计入 + `uErrorId := 16#0001_0008`（同 2.6 B2/B3 口径） |
| B4 | 启动计数 | `fbTrigRun.Q` → `nStartCount + 1`；达 `DL_RT_COUNT_MAX` 停增 + `16#0001_0007`（饱和不回绕） |
| B5 | 保养预警 | `uMaintIntervalMin > 0` 且 `uSinceMaintSec >= uMaintIntervalMin * DL_RT_SEC_PER_MIN` → `bMaintDue := TRUE` 锁存；`bMaintAck` 上升沿 → 清 `bMaintDue`、`uSinceMaintSec := 0`；`uMaintIntervalMin = 0` → `bMaintDue := FALSE`、`uMaintRemainMin := 0`（功能关闭） |
| B6 | 溢出评估 | `UDINT` 秒计数上限约 136 年，单字段无实际溢出风险；`uMaintIntervalMin * DL_RT_SEC_PER_MIN` 乘法溢出须防御：`uMaintIntervalMin` 上限钳位（建议 525600 = 1 年）+ `16#0001_0001` |
| B7 | 小时换算 | `fRunHours := UDINT_TO_REAL(uTotalSec) / UDINT_TO_REAL(DL_RT_SEC_PER_HOUR)` —— 除数为非零常量，注释写明该除法免除零前置判断的结构性理由 |
| B8 | 复位语义 | `bReset` 上升沿：全部累计清零（含保养计时）；`bReset` 不清 `uErrorId` 以外的运行标志位以外事项须与手册一致——统一为「全部归零 + `uErrorId := 0`」 |
| B9 | RETAIN 披露 | 手册必须写明：本块全部累计量若不设 RETAIN 断电即失；推荐调用方将实例声明为 RETAIN 变量 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B3 数据防御、B6 溢出钳位、B7 结构性除零豁免已论证）｜ R9 ✓ ｜ R6 N/A（纯累计统计，无状态转移，已说明）｜ R7 ✓（B1）｜ R8 ✓（全部换算系数常量化）｜ R10 ✓ ｜ R12 ✓`

**AI 训练语料 instruction 方向**
> 「车间 30 台泵的保养全靠班长用本子记累计运行时间，漏记导致两台泵轴承报废。请写一个设备运行时长统计功能块：由调用方传入运行反馈与每周期耗时毫秒数，输出累计分钟、小时、启动次数，保养间隔以分钟设置，到期锁存预警直到保养确认复位，整数秒累加避免浮点漂移，并提示实例应声明为 RETAIN 以断电保持。」

---

### 2.8 `FC_DL_SwapBytes16` ｜ DL_MathData ｜ 复杂度 2

**功能定位**：16 位字高低字节互换——字节序家族的最小原子，是 32 位四排布转换（§2.9 BADC/DCBA 路径）的构件，也独立服务 Profibus/串口仪器的单寄存器字节序需求（D-R2-13）。

**接口契约**

```iecst
FUNCTION FC_DL_SwapBytes16 : WORD
VAR_INPUT
    uValue : WORD;   // 原始 16 位字 / Source word
END_VAR
VAR
    uLow   : WORD;   // 低字节缓存 / Low byte buffer
    uHigh  : WORD;   // 高字节缓存 / High byte buffer
END_VAR
VAR CONSTANT
    DL_SWAP_SHIFT8 : UDINT := 8;           // 字节移位量 / Byte shift width
    DL_MASK_LOW8   : WORD := 16#00FF;      // 低 8 位掩码 / Low-byte mask
END_VAR
```

**决策记录（PM 视角）**：本组件**不设 `uErrorId`**。理由：16 位字节互换不存在任何非法输入（全定义域有效），与首轮 `FC_DL_PackBitsToWord` 的显式豁免（P3）同一先例，在手册与本节备案。

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 纯移位实现 | `uLow := SHL(uValue AND DL_MASK_LOW8, DL_SWAP_SHIFT8)`（低位升为高位）；`uHigh := SHR(uValue, DL_SWAP_SHIFT8)`；返回 `uLow OR uHigh`。**禁止** `.%B0`/`.%B1` 字节访问方言（R3） |
| B2 | 移位量类型统一 | 移位量经 `VAR CONSTANT`（UDINT）给出，全库统一口径（R3 隐式转换风险） |
| B3 | 自逆性单测 | 核心验证：`SwapBytes16(SwapBytes16(x)) = x` 对全字域成立（自逆函数）；手册给出 0x1A2B → 0x2B1A 样例（按 R12 复算后落表） |
| B4 | 无副作用 | 纯函数：不修改入参、无内部状态、相同输入必得相同输出 |
| B5 | 类型恒定 | 全程 `WORD` 域内运算，无跨类型转换（R3） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（B1 禁字节访问方言）｜ R4 N/A（无除法/数组/循环/浮点，已在自检表注明）｜ R9 ✓ ｜ R6 N/A（纯函数）｜ R7 N/A（无定时器/边沿实例）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓（B3）`

**AI 训练语料 instruction 方向**
> 「从 Profibus 从站读回来的状态字高低字节反着，上位的字 0x1A2B 到 PLC 变成 0x2B1A。请写一个 16 位字高低字节互换的纯函数，只用 SHL/SHR/AND/OR 标准位运算，禁止任何字节访问方言语法，并给出自逆性验证方法（换两次等于原值）。」

---

### 2.9 `FC_DL_SwapBytes32` ｜ DL_MathData ｜ 复杂度 4

**功能定位**：32 位量四排布（ABCD/CDAB/BADC/DCBA）归一化转换——Modbus 多寄存器量「读回 1e38 天文数字」的唯一系统性解药（D-R2-11）。语义锁定为「声明原始排布 → 输出 ABCD 归一化值」。

**接口契约**

```iecst
TYPE E_DL_ByteOrder :
(
    eAbcd := 0,   // ABCD：大端大字（Modicon 事实标准），原始值无需转换 / Big-endian big-word
    eDcba := 1,   // DCBA：四字节全反序 / Full byte reverse
    eBadc := 2,   // BADC：两个寄存器内部各自字节互换 / Byte swap within each register
    eCdab := 3    // CDAB：高低字交换（寄存器字序反） / Word swap
);
END_TYPE

FUNCTION FC_DL_SwapBytes32 : DWORD
VAR_INPUT
    uRaw      : DWORD;                    // 通信侧原始 32 位拼接值 / Raw 32-bit value assembled from comms
    eRawOrder : E_DL_ByteOrder := eAbcd;  // 声明原始值所属排布 / Declared byte order of raw value
END_VAR
VAR_OUTPUT
    bValid    : BOOL;    // 排布枚举合法标志 / Order enum valid flag
    uErrorId  : UDINT;   // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uA : BYTE;   // 字节 A（uRaw 位 31..24） / Byte A, bits 31..24
    uB : BYTE;   // 字节 B（位 23..16） / Byte B, bits 23..16
    uC : BYTE;   // 字节 C（位 15..8）  / Byte C, bits 15..8
    uD : BYTE;   // 字节 D（位 7..0）   / Byte D, bits 7..0
END_VAR
VAR CONSTANT
    DL_SWAP_SHIFT8  : UDINT := 8;               // 移位量 / Shift width
    DL_SWAP_SHIFT16 : UDINT := 16;              // 移位量 / Shift width
    DL_SWAP_SHIFT24 : UDINT := 24;              // 移位量 / Shift width
    DL_MASK_BYTE    : DWORD := 16#0000_00FF;    // 字节掩码 / Byte mask
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 安全预置 | 函数入口 `FC_DL_SwapBytes32 := uRaw`（最安全确定值 = 原值直通，P-01 范式）；任何异常路径返回原值不返回 0（0 对浮点量是合法灾难值） |
| B2 | 字节提取 | 仅用 `SHR(uRaw, n) AND DL_MASK_BYTE` 再显式 `DWORD_TO_BYTE`；重装仅用 `SHL` + 显式 `BYTE_TO_DWORD` 后 `OR`。**禁止**内存切片/指针重叠/字节访问方言（R3 + D-R2-12） |
| B3 | 四排布 CASE | `eAbcd` → 原值直出；`eDcba` → D C B A；`eBadc` → B A D C；`eCdab` → C D A B。以 `CASE` 分派，**禁止** IF 链嵌套 |
| B4 | 非法枚举兜底 | `CASE ... ELSE` → 返回原值 + `bValid := FALSE` + `uErrorId := 16#0001_000E`（枚举被强制写入域外值时的结构化防御，R6 以 ELSE 形式体现） |
| B5 | 验收向量矩阵（按 R12 复算后落手册） | 以 `uRaw = 16#12345678` 为基准：ABCD → `16#12345678`；DCBA → `16#78563412`；BADC → `16#34127856`；CDAB → `16#56781234`。另附互逆矩阵：对任意排布 O1→归一化后按对称排布 O2 重灌，应还原原值（4×4 全矩阵单测） |
| B6 | 与 16 位版协作 | BADC/DCBA 路径内部可调用 `FC_DL_SwapBytes16` 构件或等价移位实现，二选一后全文件统一（手册注明实现选择） |
| B7 | 浮点量使用口径 | 手册写明：转换结果为归一化 DWORD，转 `REAL` 需调用方按平台浮点拼接规则进行；本函数不做 DWORD→REAL 转换（避免平台浮点二进制表示差异引入行为分支） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（B2 移位提取，本组件 R3 关键考点）｜ R4 N/A（无除法/数组/循环/浮点，B5 为复算向量）｜ R9 ✓ ｜ R6 ✓（B4 以 CASE-ELSE 兜底）｜ R7 N/A ｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓（B5）`

**AI 训练语料 instruction 方向**
> 「Modbus 读电表浮点功率寄存器得到 2.8e-29 这种天文数字，手册没写字序，现场试出来是 CDAB。请写一个 32 位值四排布归一化转换函数：输入原始拼接值与它实际所属的排布枚举（ABCD/DCBA/BADC/CDAB），输出统一 ABCD 大端归一化值，枚举被写坏时返回原值并报错，字节提取只允许移位与掩码，并给出 0x12345678 在四种排布下的验收向量。」

---

### 2.10 `FB_DL_RingBufferLReal` ｜ DL_MathData ｜ 复杂度 5

**功能定位**：定长 64 容量 LREAL 环形队列（FIFO）：压入/弹出/窥视/清空 O(1) 操作——解决「数组整体移位的历史缓存写法每次移 N 个元素还容易 off-by-one」「故障前最后一段数据被冲掉无法追溯」两个问题。容量固定不参数化（D-R2-15）。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_RingBufferLReal
VAR_INPUT
    fPushValue : LREAL;      // 待压入值 / Value to push
    bPush      : BOOL;       // 上升沿压入 / Push on rising edge
    bPop       : BOOL;       // 上升沿弹出 / Pop on rising edge
    bClear     : BOOL;       // 电平清空（最高优先级操作）/ Level-triggered clear, highest priority
END_VAR
VAR_OUTPUT
    fPopValue  : LREAL;    // 最近一次弹出值 / Last popped value
    fPeekValue : LREAL;    // 队首值（窥视，不弹出）；空队时为 0.0 哨兵 / Front value (peek), 0.0 sentinel when empty
    uCount     : UINT;     // 当前元素数 0..64 / Current element count
    bFull      : BOOL;     // 已满标志 / Full flag
    bEmpty     : BOOL;     // 已空标志 / Empty flag
    uErrorId   : UDINT;    // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    afBuffer   : ARRAY[0..63] OF LREAL;  // 环形存储 [EU] / Ring storage
    nReadIdx   : INT;    // 读指针（队首）0..63 / Read index (front)
    nWriteIdx  : INT;    // 写指针（下一写入位）0..63 / Write index (next slot)
    fbTrigPush : R_TRIG; // 压入沿 / Push edge
    fbTrigPop  : R_TRIG; // 弹出沿 / Pop edge
END_VAR
VAR CONSTANT
    DL_RB_CAP : INT := 64;   // 固定容量，与数组维度严格一致 / Fixed capacity, must match array
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 双 `R_TRIG` 无条件刷新 | `fbTrigPush(CLK := bPush)` / `fbTrigPop(CLK := bPop)` 主体最前部（R7） |
| B2 | 清空最高优先级 | `bClear` 电平 TRUE → 无论沿状态，立即复位双指针与计数（防清空与压入同周期的竞态歧义） |
| B3 | 满拒写 | 满时 `fbTrigPush.Q` → 拒绝 + `uErrorId := 16#0001_0009`。**不覆盖最旧值**（FIFO 数据结构语义：丢数据必须显式可见，静默覆盖违背「不静默吞错」总则；需要覆盖语义的调用方应自行先 Pop） |
| B4 | 空拒读 | 空时 `fbTrigPop.Q` → 拒绝 + `uErrorId := 16#0001_000A`；`fPopValue` 保持上次值 |
| B5 | 同周期压弹次序 | `fbTrigPush.Q` 与 `fbTrigPop.Q` 同时为 TRUE → **先压后弹**（净效果 = 换出队首），顺序固定并在注释标注「顺序不可交换」（P-06 范式） |
| B6 | 结构性回绕 | 指针更新一律 `(nIdx + 1) MOD DL_RB_CAP` 前向回绕，**全组件不存在任何指针减法**（从结构上杜绝「负数 MOD 平台差异」陷阱，D-R2-15）；`uCount` 单调受 `bFull/bEmpty` 派生 |
| B7 | 窥视语义 | `fPeekValue` 每周期输出队首（`afBuffer[nReadIdx]`，前提 `uCount > 0` 下标双检）；空队输出 0.0 哨兵 + `bEmpty := TRUE`，手册写明「0.0 是哨兵不是数据，判空必须看 `bEmpty`」 |
| B8 | 计数一致性 | `uCount` 只在压/弹成功路径上 ±1；`bFull := (uCount = DL_RB_CAP)`（INT 与 UINT 比较经显式转换，R3）；`bEmpty := (uCount = 0)` |
| B9 | 无状态机声明 | 队列操作无跨周期状态转移，R6 标 N/A（指针与计数即全部状态） |
| B10 | LREAL 平台披露 | 头注释写明：`LREAL` 为 IEC 标准类型，三平台均支持 64 位浮点；容量 64 × 8 字节 = 512 字节实例内存，手册给出内存占用量 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B6 结构性回绕、B7 下标双检）｜ R9 ✓ ｜ R6 N/A（B9 已说明）｜ R7 ✓（B1）｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓（回绕序列向量见手册）`

**AI 训练语料 instruction 方向**
> 「故障追溯需要缓存故障前最后 60 条温度采样，原实现每来一个新样本把 60 个元素整体移位一次，还出过 off-by-one 把最新数据顶掉的问题。请写一个定长 64 容量的 LREAL 环形队列功能块：支持压入/弹出/窥视/清空四种操作，压入弹出用上升沿触发，满时拒绝写入并报错（不允许静默覆盖最旧值），空时拒绝弹出，指针只用前向取模回绕杜绝负数取模的平台差异，全部操作 O(1) 无循环。」

---

### 2.11 `FC_DL_StringTrim` ｜ DL_MathData ｜ 复杂度 3

**功能定位**：去除字符串首尾空白字符（空格 / 制表 / 回车 / 换行）——扫码枪、CSV 报文、视觉结果字符串解析的前置清洗步（检索 5「validate → locate → extract」纪律的第一环）。

**接口契约**

```iecst
FUNCTION FC_DL_StringTrim : STRING(255)
VAR_INPUT
    sIn : STRING(255);    // 原始字符串 / Source string
END_VAR
VAR_OUTPUT
    bValid   : BOOL;     // 处理完整标志，FALSE = 循环保护触发 / Complete flag, FALSE = loop guard hit
    uTrimmed : UINT;     // 被去除的空白字符总数 / Total whitespace characters removed
    uErrorId : UDINT;    // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    nLen     : INT;          // 输入有效长度 / Effective input length
    nStart   : INT;          // 首个非空白位置（1 起始）/ First non-blank position, 1-based
    nEnd     : INT;          // 末个非空白位置（1 起始）/ Last non-blank position, 1-based
    sChar    : STRING(1);    // 当前检查字符 / Current character under check
    nGuard   : DINT;         // 循环防死锁计数器 / Loop deadlock guard
END_VAR
VAR CONSTANT
    DL_STR_MAX_LEN  : INT  := 255;    // 串长度上限，与类型声明一致 / Max length, must match type
    DL_STR_LOOP_MAX : DINT := 255;    // 循环防死锁上限 / Loop guard limit
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 显式长度声明 | 输入/返回/工作变量一律 `STRING(255)`；头注释警告「CODESYS 默认 STRING 为 80 字节，省略长度会被静默截断」（D-R2-17） |
| B2 | 空白字符集 | 恰好四类：空格 `'$20'`、制表 `'$09'`、回车 `'$0D'`、换行 `'$0A'`，以 IEC 转义字面量比较（字符经 `MID(sIn, 1, nPos)` 提取后按 `STRING` 判等）；字符集**不得扩充**（全角空格等多字节字符属调用方预处理职责，手册写明） |
| B3 | 位置约定 | 全程 1 起始位置（IEC 标准串函数口径）；`LEN` 结果为有效长度 |
| B4 | 双向扫描 + 防死锁 | 首扫 `WHILE` 找 `nStart`、尾扫 `WHILE` 找 `nEnd`，两个循环都带 `nGuard` 计数器，超限 → `bValid := FALSE` + `uErrorId := 16#0001_0004` 并按当前已得边界尽力返回（P-01） |
| B5 | 全空白/空串 | 空串或全空白 → 返回空串 `''`，`uTrimmed := 原有效长度`，`bValid := TRUE`（不是错误，是合法结果） |
| B6 | 截取防御 | 结果 = `MID(sIn, nEnd - nStart + 1, nStart)`；调用前 `nEnd >= nStart` 必须成立（结构性保证后仍断言一次，双保险 P-04）；长度为 0 时直接返回空串不调 `MID` |
| B7 | 返回值确定 | 所有路径（含循环保护提前退出）返回值均已赋值（P-01）；异常路径返回已处理的最长安全前缀 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（仅标准串函数）｜ R4 ✓（B4 防死锁、B6 截取钳位）｜ R9 ✓ ｜ R6 N/A（纯函数，已说明）｜ R7 N/A ｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓（手册向量：`'  AB$09CD  '` → `'AB$09CD'`，中间制表符保留，按复算落表）`

**AI 训练语料 instruction 方向**
> 「扫码枪上传的条码前后带了不可见空白，直接入库比对总是失败。请写一个字符串首尾空白清理函数：只去除首尾的空格、制表符、回车、换行四类字符，串中间的空白保留，使用显式 255 长度的字符串类型，扫描循环带防死锁计数器，全空白输入返回空串而不是报错，并说明 IEC 字符串位置从 1 开始计。」

---

### 2.12 `FC_DL_StringSplit` ｜ DL_MathData ｜ 复杂度 6

**功能定位**：按单字符分隔符拆分报文为字段数组（CSV / 扫码枪 / 视觉结果）——检索 5 确认 TwinCAT/CODESYS 均无内置 SPLIT，各项目自写解析是串口设备集成的最大重复劳动。采用「FIND 定位 → LEFT 取字段 → 工作副本 DELETE」标准循环（D-R2-18）。

**接口契约**

```iecst
FUNCTION FC_DL_StringSplit : INT    // 返回实际拆分出的字段数 0..16 / Returns actual field count, 0..16
VAR_INPUT
    sSource    : STRING(255);        // 待拆分报文 / Source message
    sDelimiter : STRING(1) := ',';   // 分隔符（单字符）/ Single-character delimiter
    uMaxFields : INT := 16;          // 最大输出字段数，合法域 1..16 / Max fields, valid 1..16
END_VAR
VAR_IN_OUT
    aFields : ARRAY[0..15] OF STRING(255);  // 输出字段缓冲，调用方持有并复用 / Caller-owned output field buffer
END_VAR
VAR_OUTPUT
    bValid   : BOOL;    // 拆分完整标志，FALSE = 发生截断（16#0001_000D）/ Complete flag, FALSE = truncated
    uErrorId : UDINT;   // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    sTmp       : STRING(255);  // 剩余段工作副本 / Working copy of remaining segment
    nDelimPos  : INT;          // 分隔符在工作副本中的位置（1 起始，0 = 未找到）/ Delimiter position, 0 = not found
    nFieldIdx  : INT;          // 当前字段索引 / Current field index
    nFieldLen  : INT;          // 当前字段长度 / Current field length
    nDelimLen  : INT;          // 分隔符长度校验值 / Delimiter length check
    nMaxEff    : INT;          // 钳位后的最大字段数 / Clamped max fields
    nGuard     : DINT;         // 循环防死锁计数器 / Loop deadlock guard
    nLoop      : INT;          // 主循环索引 / Main loop index
END_VAR
VAR CONSTANT
    DL_SP_MAX_FIELDS : INT  := 16;    // 字段数上限，与数组维度一致 / Field cap, must match array
    DL_SP_LOOP_MAX   : DINT := 64;    // 主循环防死锁上限（字段数 × 余量）/ Loop guard limit
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 分隔符合法性 | `LEN(sDelimiter) <> 1`（空串或多字符）→ `bValid := FALSE` + `uErrorId := 16#0001_0008` + 返回 0，**不拆分**（D-R2-18：单字符语义锁定，多字符分隔列入 R3+ 扩展） |
| B2 | 字段数钳位 | `uMaxFields < 1` → 钳到 1；`> 16` → 钳到 16；均 + `uErrorId := 16#0001_0001`（P-03 钳位继续拆分） |
| B3 | 空源串 | `LEN(sSource) = 0` → 返回 0、`bValid := TRUE`（空输入是合法结果非错误） |
| B4 | 主循环结构 | `FOR nLoop` 或受控 `WHILE`（带 `nGuard`，超限 `16#0001_0004`）：`nDelimPos := FIND(sTmp, sDelimiter)`；`> 0` → 字段 = `LEFT(sTmp, nDelimPos - 1)`、`sTmp := DELETE(sTmp, nDelimPos, nDelimLen)`；`= 0` → 剩余段为末字段，结束 |
| B5 | 截断语义 | 已拆出 `nMaxEff` 个字段但 `sTmp` 仍含分隔符或非空剩余 → 剩余**整段并入末字段后**置 `bValid := FALSE` + `uErrorId := 16#0001_000D`（结果不静默丢弃，调用方以 bValid 识别截断，D-R2-18） |
| B6 | 连续分隔符 | 相邻分隔符产生空字段（CSV 语义：`'A,,B'` → `'A'` `''` `'B'` 三字段），不得跳过空字段 |
| B7 | 输出缓冲纪律 | `aFields` 为 `VAR_IN_OUT`：调用方必须传入**持久数组**且每次调用前自行清场；头注释按 Round 01 案例 5 范式给出「传临时变量/每次新数组 → 上次残留字段污染」的反例警告 |
| B8 | 工作副本隔离 | 解析全程在 `sTmp` 上进行，`sSource` 不被修改（函数无副作用口径）；`DELETE` 的长度参数用 `nDelimLen` 而非魔法数 1 |
| B9 | 返回值确定 | 所有路径返回实际字段数（0 合法）；异常路径返回已完成的字段数（P-01） |
| B10 | 性能口径 | 单次调用最坏 16 次 FIND/LEFT/DELETE，无嵌套循环；手册写明 255 字节 × 16 字段 = 约 4KB 调用方内存要求 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（仅标准串函数 LEN/FIND/LEFT/DELETE）｜ R4 ✓（B4 防死锁、B2 钳位）｜ R9 ✓ ｜ R6 N/A（纯函数，已说明）｜ R7 N/A ｜ R8 ✓ ｜ R10 ✓ ｜ R12 ✓（手册向量：`'LOT=A4471;QTY=0250;'` 按 `';'` 拆分 → 2 字段 + 尾空段语义按 B4/B6 复算后落表）`

**AI 训练语料 instruction 方向**
> 「扫码枪返回 'LOT=A4471;QTY=0250;' 这类分号分隔报文，CODESYS 没有现成 SPLIT 函数，每个项目都在手写解析。请写一个字符串拆分函数：单字符分隔符，输出到调用方提供的字段数组（VAR_IN_OUT），返回实际字段数，连续分隔符产生空字段符合 CSV 语义，超出最大字段数时剩余部分并入末字段并置截断标志报错，分隔符长度不是 1 直接拒绝，扫描循环带防死锁保护，且不修改输入串。」

---

## 3 复杂度与工作量分布

| 复杂度 | 组件 | 数量 | 说明 |
|---|---|---|---|
| 2 | SwapBytes16 | 1 | 纯位运算原子，重点在 R3 方言禁令与自逆性 |
| 3 | CycleTimeMeasure、StringTrim | 2 | 注入式时间约定 / 串函数位置口径 |
| 4 | WatchdogMonitor、RuntimeMeter、SwapBytes32 | 3 | 跳变语义 / 整数化累加 / 四排布 CASE |
| 5 | ExtendedTimer、PulseGenerator、RingBufferLReal | 3 | 四模式语义表 / 相位机 / 结构性回绕 |
| 6 | StringSplit | 1 | VAR_IN_OUT 缓冲纪律 + 截断语义 |
| 7 | AlarmManager | 1 | 仲裁 + 序号锁存 + 三态确认，无状态机样板 |
| 8 | StepSequencer | 1 | 全轮最高：五态状态机 + 五实例无条件刷新 + 单步调试语义 |
| **合计** | — | **12** | 平均 4.67，高于首轮 3.57——时序/结构组件复杂度天然更高，符合预期 |

---

## 4 下游交付验收清单（编码 Agent 必须逐条自证）

### 4.1 文件级
- [ ] 12 个 `.st` 文件，文件名 = POU 名（含前缀），落在 `C:\Library\DL_Base\` 与 `C:\Library\DL_MathData\`
- [ ] 每个文件头部注释块七项齐全：组件名称 / 所属子库 / 当前版本 / 兼容性 / 功能描述 / 开源溯源 / 修订历史
- [ ] 一个文件只放一个主 POU（配套 `E_DL_` 枚举可同文件，头注释注明归属）
- [ ] 依赖清单（§1.2）之外零内部调用

### 4.2 红线级（任一不过 → 直接打回）
- [ ] R1 全文扫描全局变量表与外部变量声明命中 0
- [ ] R2 全文扫描物理地址命中 0
- [ ] R3 无位访问方言 / 无指针 / 无引用 / 无厂商类型 / 无隐式转换；移位量统一类型
- [ ] R4 每处除法有分母前置判断（结构性豁免须注释论证）；每处数组访问双检；每处 `WHILE` 有防死锁计数器；浮点判等全部带容差
- [ ] R9 每个变量声明行「中文物理意义 + 英文术语 + 工程单位」三要素齐全
- [ ] R6 有状态机组件（#1 #3 #4 #5）ENUM + CASE + ELSE 兜底；N/A 组件在自检表注明理由
- [ ] R7 所有 `TON`/`R_TRIG`/`F_TRIG` 实例在主体最前部无条件刷新
- [ ] R8 无魔法数（换算系数、钳位上限、哨兵值全部常量化）
- [ ] R11 若有对本文任何收窄/偏离，头注释留档

### 4.3 契约级
- [ ] 引脚名称、类型、方向、默认值与本文第 2 章**逐字一致**
- [ ] 故障码取值落在 §1.1 分配表内（含新增 0008~000E），无自造码
- [ ] 每个组件在手册中有「调用示例 + 故障码表 + 测试向量」

### 4.4 文档级（入库同批完成，不得事后补）
- [ ] `DL_Base\VERSION.md`、`DL_MathData\VERSION.md` 递增（Minor）并列出组件清单
- [ ] 两份 `MANUAL_DL_*.md` 每组件一节；`FC_DL_SwapBytes32` 须含四排布验收矩阵
- [ ] 顶层 `CHANGELOG.md`、`README.md`、`LIBRARY_MANUAL.md` 同步
- [ ] `INDEX_REGISTRY.json` 增至 26 条；`_AI_Training_Dataset\daoli_st_sft_dataset.jsonl` 增至 26 条（三方一致）

---

## 5 风险与决策记录

| # | 风险 / 决策 | 结论 | 理由 |
|---|---|---|---|
| P1 | 平台时刻函数（OSCAT `T_PLC_MS` 类）是否引入 | **拒绝**；CycleTimeMeasure/RuntimeMeter 用 `uDeltaTimeMs : UDINT` 注入 | InoProShop 对平台时刻函数支持未验证；注入式设计把平台差异关在调用方一处（D-R2-01） |
| P2 | `FC_DL_Hysteresis` 式「有状态函数」纪律是否扩展 | 本轮无新增有状态 FC；StepSequencer/AlarmManager 均为 FB | 首轮已确立《状态持有纪律》口径，本轮不新增 FC 状态债 |
| P3 | `FC_DL_SwapBytes16` 无故障码 | 显式豁免并备案（沿用首轮 PackBitsToWord P3 先例） | 全定义域合法输入，恒 0 错误码是噪音 |
| P4 | `FB_DL_PulseGenerator` 的 TIME-REAL 转换族 | 主路径用标准转换族；InoProShop 实测不支持则按 R11 收窄（删 `fProgress` 引脚 + DINT 中间量），头注释留档 | 转换族属 IEC 标准，但汇川支持矩阵待验证；收窄路径预先定义好，编码侧无需再决策 |
| P5 | AlarmManager 禁用通道的报警字位 | 禁用通道位强制 0（不透传原始激活态） | 报警字是给上位机的最终事实，混入「禁用但真跳了」的位会造成上位机与 PLC 状态错觉 |
| P6 | AlarmManager 使能恢复语义 | 视同冷启动重扫（序号表清零） | 避免「禁用期间积压报警恢复瞬间集中爆发 + 首出指向历史事件」的混淆；需瞬时静默的场景由调用方在输入侧处理 |
| P7 | StepSequencer 暂停期超时语义 | 冻结 + 恢复后**重新计时** | 「暂停续算」会让 TON 实例语义复杂化（ET 冻结需差分补偿）；重新计时的代价明确可文档化（D-R2-10） |
| P8 | StepSequencer 并行分支 | 首版不做，列入 R3+ | 并行分支使步引擎复杂度翻倍且调试成本剧增（检索 3 结论）；串行版覆盖 80% 工站需求 |
| P9 | RingBufferLReal 满时策略 | 拒绝写入（不覆盖最旧值） | FIFO 数据结构语义下静默覆盖违背「不静默吞错」；需要滑动窗口语义的场景已有 MovingAverage 承担 |
| P10 | StringSplit 多字符分隔符 | 首版单字符锁定 | 多字符分隔使 FIND/DELETE 循环语义与截断语义复杂化；单字符覆盖 CSV/分号/竖线全部主流场景 |
| P11 | 字符串长度统一 255 | 全字符串族显式 `STRING(255)` | CODESYS 默认 80 的静默截断是检索 5 确认的高频事故源；255 覆盖工业报文典型长度 |
| P12 | 运行时计量整数化 | RuntimeMeter 以秒 + 毫秒进位缓存累加，不做浮点累加 | 浮点逐周期累加漂移是首轮 MovingAverage B6 已验证的问题，整数化一劳永逸 |

---

## 6 下一轮前置输入（写给产品经理自己）

1. **Level 0 收口缺口**：本轮后 `DL_Base` 16/20（实缺 `FB_DL_TwoHandSafety` / `FB_DL_InterlockMatrix` / `FB_DL_RedundantSwitch` / `FB_DL_DutyStandbyRotation` 4 项，偏安全与冗余语义，建议 R3 单独成批并引入 IEC 60204 口径审查）；`DL_MathData` 10/20（缺 MultiPointLinear / PolygonArea / LineIntersection / Crc32Ethernet / LrcChecksum / LifoStack / MedianFilter / SignalStatistics / QuickSortLReal / HexStringToBytes 10 项，可一批做）。
2. **测试向量债**：首轮 + 本轮累计 6 类数值向量散落在手册，R3 前必须落 `TESTS\vectors.md` 集中管理（Round 01 §六.2 已立项，仍未偿还）。
3. **字符串族验证债**：`STRING(255)` 与串函数在三平台的边界行为（MID 越界、DELETE 长度参数）需实机验证清单，随 R3 的 `HexStringToBytes` 一并做。
4. **依赖复用首次实证**：本轮 AlarmManager→PackBitsToWord、WatchdogMonitor→DualEdgeTrig 是全库首批内部复用；终审时必须验证复用组件的版本演进不破坏被复用方（引入「依赖影响面」检查项）。

---

*Round 02 ｜ 2026-11-14 ｜ 道莅工控代码库产品总监*
