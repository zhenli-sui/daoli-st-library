# ROUND_PLAN ｜ 道莅万级工业代码库 · 首轮冷启动需求规格书

> **文档编号**：DL-RP-2026-11-14-001
> **阶段**：Phase 1 种子冷启动 ｜ Level 0（DL_Base + DL_MathData）
> **本轮范围**：14 个组件（9 个 DL_Base + 5 个 DL_MathData）
> **撰写人**：道莅工控代码库产品总监（Daoli Library Director）
> **下游执行**：PLC 编程专家（编码 Agent）—— **本文件不含任何 .st 交付代码，禁止在此阶段产出 .st 文件**
> **编制日期**：2026-11-14
> **情报支撑**：`C:\Library\_Staging_Raw\2026-11-14\RAW_NOTES.md`

---

## 0 本轮作业定位与纪律

### 0.1 定位
这是「道莅万级工业代码库」从 0 到 1 的第一批砖。Level 0 是整个依赖金字塔的地基：任何一条接口设计缺陷，都会在 Level 1（Algo / Device / Motion）与 Level 2（Process）被放大数百倍。因此本轮**不追求数量，只追求接口契约的不可逆正确性**——这 14 个组件的引脚一旦入库，后续 9986 个组件都会照着它们抄。

### 0.2 硬性纪律（下游必须逐条遵守）

| # | 纪律 | 违反后果 |
|---|---|---|
| D1 | **本轮零 `.st` 文件**。编码由下一位 PLC 编程专家执行 | 越权交付，接口与实现脱节 |
| D2 | 接口定义**逐字**以本文件第 3 章为准，不得擅自增删引脚；确有缺陷走「变更申请」回写本文件 | 索引/手册/训练集三方漂移 |
| D3 | 任何组件不得引用 `DL_Algo` / `DL_Device` / `DL_Motion` / `DL_Process` 类型 | 破坏分层单向依赖 |
| D4 | `DL_MathData` 可依赖 `DL_Base`，反向禁止 | 循环依赖，编译顺序死锁 |
| D5 | 命名一律 `FB_DL_` / `FC_DL_` / `E_DL_` / `ST_DL_` 前缀，文件名 = POU 名 | 索引无法自动对齐 |

### 0.3 七条红线（本轮统一编号，逐组件标注）

| 编号 | 红线 | 判定口径（可机检） |
|---|---|---|
| **R1** | 零 GVL / VAR_EXTERNAL | 全文检索 `GVL`、`VAR_EXTERNAL` 命中数 = 0 |
| **R2** | 零 `%I` / `%Q` / `%M` 物理地址 | 全文检索 `%I`、`%Q`、`%M` 命中数 = 0 |
| **R3** | 纯 IEC 61131-3 跨平台语法 | 仅 `Standard.library`；无 `%X`/`%B` 位访问、无 `POINTER TO`/`REFERENCE TO`、无 `__SYSTEM`/`SysXxx`/`TcXxx`、无隐式转换 |
| **R4** | 完整防除零 / 防越界 / 浮点容差 | 除法前置 `ABS(den) > 1E-6`；数组下标有上下界双检；浮点判等用容差；`WHILE` 有防死锁计数器 |
| **R5** | 100% 变量同行**中文 + 英文**双语注释 | 每个 `VAR` 声明行尾必须同时有中文物理意义与英文术语，且标注单位 |
| **R6** | 状态机 `ENUM` + `CASE` + `ELSE` 兜底 | 存在状态机则三要素齐全；无状态机则标注「N/A」并说明 |
| **R7** | `TON` / `TOF` / `R_TRIG` / `F_TRIG` 实例**无条件周期刷新** | 所有定时器/边沿实例调用必须位于主体最前部的「无条件刷新区」，禁止嵌套在 `IF`/`CASE` 内 |

> **R5 说明（本轮对规范的加严）**：现行 `coding-standard.md` 只要求 100% 中文注释；本轮按用户口径升级为**中文 + 英文双语**，示例：
> `bEnable : BOOL := TRUE;   // 使能标志，FALSE 时输出回安全值 / Enable flag, FALSE forces safe output`
> 该加严项应回写 `AGENT_EVOLUTION_LOG.md` 规则库（建议编号 R9），后续全库生效。

---

## 1 本轮目标清单（14 项，名单锁定，不增不删不改）

| # | 组件 | 子库 | 类型 | 复杂度 |
|---|---|---|---|---|
| 1 | `FB_DL_SignalDebounce` | DL_Base | 功能块 | 5 |
| 2 | `FB_DL_DualEdgeTrig` | DL_Base | 功能块 | 2 |
| 3 | `FC_DL_BitGet` | DL_Base | 函数 | 2 |
| 4 | `FC_DL_BitSet` | DL_Base | 函数 | 3 |
| 5 | `FC_DL_BitCount` | DL_Base | 函数 | 3 |
| 6 | `FC_DL_PackBitsToWord` | DL_Base | 函数 | 2 |
| 7 | `FB_DL_UnpackWordToBits` | DL_Base | 功能块 | 2 |
| 8 | `FC_DL_GrayToBinary` | DL_Base | 函数 | 4 |
| 9 | `FC_DL_BinaryToGray` | DL_Base | 函数 | 3 |
| 10 | `FC_DL_LinearScale` | DL_MathData | 函数 | 4 |
| 11 | `FC_DL_Deadband` | DL_MathData | 函数 | 3 |
| 12 | `FC_DL_Hysteresis` | DL_MathData | 函数 | 4 |
| 13 | `FB_DL_MovingAverage` | DL_MathData | 功能块 | 6 |
| 14 | `FC_DL_Crc16Modbus` | DL_MathData | 函数 | 5 |

**依赖关系**：14 个组件之间**零内部依赖**，全部可独立编译、独立单测、独立入库。
**建议编码顺序**：2 → 3 → 4 → 7 → 6 → 5 → 9 → 8 → 10 → 11 → 12 → 1 → 14 → 13（由简入繁，先建立位运算语感再上浮点与时序）。
**建议分批入库**：批次 A（#2~#9，8 个纯位逻辑，同日可完）、批次 B（#10~#12，3 个浮点函数）、批次 C（#1、#13、#14，3 个带状态/循环的重组件）。

### 1.1 统一故障码分配表（**全库唯一，不允许各组件自造**）

| ErrorID | 含义 | 适用组件 |
|---|---|---|
| `16#0000_0000` | 无故障 | 全部 |
| `16#DL01_0001` | 参数越界（位索引 / 位宽 / 窗口长度 / 字节数超范围） | BitGet, BitSet, Gray*, MovingAverage, Crc16 |
| `16#DL01_0002` | 量程 / 分母为零或近零（`|x| ≤ 1E-6`） | LinearScale, MovingAverage |
| `16#DL01_0003` | 参数符号非法（传入负数宽度 / 负量程） | Deadband, Hysteresis |
| `16#DL01_0004` | 循环保护触发（`WHILE`/`FOR` 超出防死锁上限） | BitCount, MovingAverage |
| `16#DL01_0005` | 状态机进入非法状态（`CASE ... ELSE` 兜底命中） | SignalDebounce, MovingAverage |
| `16#DL01_0006` | 输入数据非法（NaN / Inf，仅平台支持检测时可用） | LinearScale, MovingAverage, Deadband |
| `16#DL01_0007` | 数值溢出（计数型输出翻转） | DualEdgeTrig, UnpackWordToBits |

> 编码约定：`16#DL01_xxxx` 为可读示意，实际写入 `16#0001_0001` ~ `16#0001_0007`（`DL01` = Level 0 第 1 组，用十六进制字面量实现）。手册中必须提供该映射表。

---

## 2 逐组件需求规格

> 每个组件固定 6 段：**功能定位 → 接口契约 → 边界防御 → 复杂度 → 红线自检 → AI 语料方向**。
> 接口块中所有 `:=` 值为**默认值建议**；标注 `[必填]` 者调用方必须显式传入。

---

### 2.1 `FB_DL_SignalDebounce` ｜ DL_Base ｜ 复杂度 5

**功能定位**：机械触点（按钮、限位、继电器辅助触点）的软件消抖，上升与下降延时独立可调——解决「按下抖 5 次导致计数器多加 4 次」「松手抖动被误判为二次动作」这类现场最常见的信号完整性问题。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_SignalDebounce
VAR_INPUT
    bRawInput   : BOOL;             // 原始输入信号，未经消抖 / Raw input, not debounced
    tRiseDelay  : TIME := T#20MS;   // 上升沿确认延时 [ms]，0 = 直通 / Rising confirmation delay [ms], 0 = pass-through
    tFallDelay  : TIME := T#20MS;   // 下降沿确认延时 [ms]，0 = 直通 / Falling confirmation delay [ms], 0 = pass-through
    bEnable     : BOOL := TRUE;     // 使能，FALSE 时输出直通原始值 / Enable, FALSE = bypass raw input
    bReset      : BOOL;             // 上升沿复位：输出回到未定义初态并重新采样 / Rising edge: re-initialize filter
END_VAR
VAR_OUTPUT
    bStable     : BOOL;             // 消抖后的稳定输出 / Debounced stable output
    bRiseEvent  : BOOL;             // 稳定上升沿，单扫描周期脉冲 / Stable rising edge, one-scan pulse
    bFallEvent  : BOOL;             // 稳定下降沿，单扫描周期脉冲 / Stable falling edge, one-scan pulse
    bFiltering  : BOOL;             // 正在消抖（输入≠稳定值且计时未满） / Debounce in progress
    bError      : BOOL;             // 故障标志，需 bReset 清除 / Fault flag, cleared by bReset
    uErrorId    : UDINT;            // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbTonRise   : TON;              // 上升确认定时器 / Rising confirmation timer
    fbTonFall   : TON;              // 下降确认定时器 / Falling confirmation timer
    fbTrigReset : R_TRIG;           // 复位上升沿 / Reset rising edge
    eState      : E_DL_DebounceState; // 主状态机 / Main state machine
    bLastStable : BOOL;             // 上一周期稳定值（边沿比较用） / Previous stable value
    tRiseClamped: TIME;             // 钳位后的上升延时 / Clamped rising delay
    tFallClamped: TIME;             // 钳位后的下降延时 / Clamped falling delay
END_VAR
VAR CONSTANT
    DL_DEBOUNCE_MAX_DELAY : TIME := T#10S;   // 延时上限钳位，超限按上限执行 [s] / Max delay clamp [s]
END_VAR
```

配套枚举（同文件内定义，头部注释注明归属）：

```iecst
TYPE E_DL_DebounceState :
(
    eInit       := 0,     // 上电首扫：直接采样，不产生事件 / Power-up first scan, no event
    eStable     := 10,    // 稳定态：输出 = 稳定值 / Stable, output = stable value
    eRiseWait   := 20,    // 输入已变 TRUE，等待上升延时到期 / Waiting rising delay
    eFallWait   := 30,    // 输入已变 FALSE，等待下降延时到期 / Waiting falling delay
    eFault      := 99     // 故障锁定 / Latched fault
);
END_TYPE
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 双定时器无条件刷新 | `fbTonRise` / `fbTonFall` / `fbTrigReset` 三个实例必须位于主体最前部，禁止进 `IF`/`CASE`（R7 硬约束） |
| B2 | 上电首扫不产生假边沿 | `eInit` 态直接把 `bRawInput` 写入 `bStable` 与 `bLastStable`，`bRiseEvent`/`bFallEvent` 强制 FALSE |
| B3 | 延时钳位 | `tRiseDelay` / `tFallDelay` 超过 `DL_DEBOUNCE_MAX_DELAY` 时钳到上限并置 `uErrorId := 16#0001_0001`（不中断运行，只告警） |
| B4 | 零延时合法 | `T#0S` 表示直通，不得因 `PT := T#0S` 导致 `Q` 恒 FALSE |
| B5 | 事件唯一性 | `bRiseEvent` / `bFallEvent` 每个逻辑跳变**只允许脉冲一个周期**，且二者互斥（同一周期不可能同时 TRUE） |
| B6 | 使能失效语义 | `bEnable := FALSE` 时 `bStable := bRawInput` 直通、`bFiltering := FALSE`、事件全部清零；**恢复使能时按 `eInit` 重新采样，不得补发历史边沿** |
| B7 | 复位语义 | `bReset` 上升沿：`eState := eInit`、`bError := FALSE`、`uErrorId := 0`、清两个定时器 |
| B8 | 定时器抖动 | 输入在延时未满时反复跳变，必须由 `TON.IN` 变 FALSE 自动清零 `ET`，不得出现「累积计时」 |
| B9 | 状态机兜底 | `ELSE` 分支置 `eFault` + `uErrorId := 16#0001_0005`，输出回 `bStable := FALSE` |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B3 越界钳位、B7 复位）｜ R5 ✓ ｜ R6 ✓（五态 ENUM + ELSE 兜底）｜ R7 ✓（B1，本组件核心考点）`

**AI 训练语料 instruction 方向**
> 「某产线急停按钮因触点抖动，HMI 上每按一次停机次数加 3~5 次，且偶尔误报二次停机。请用 IEC 61131-3 ST 写一个上升/下降延时独立可调的消抖功能块，要求上电首扫不产生假边沿、延时超限自动钳位告警、边沿事件只脉冲一个扫描周期，并用 ENUM+CASE 状态机实现且带 ELSE 兜底。」

---

### 2.2 `FB_DL_DualEdgeTrig` ｜ DL_Base ｜ 复杂度 2

**功能定位**：一个块同时给出上升沿、下降沿、任意跳变三种事件与电平状态，替代「一个 `R_TRIG` + 一个 `F_TRIG` + 两行 `AND`」的散乱写法，并附带边沿累计计数——解决多工位同时取沿时「有的地方用上升沿、有的地方用 `NOT` 取下降沿」导致的语义不一致。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_DualEdgeTrig
VAR_INPUT
    bSignal   : BOOL;            // 待检测信号（建议已消抖） / Signal to detect (pre-debounced recommended)
    bEnable   : BOOL := TRUE;    // 使能，FALSE 时所有事件强制 FALSE / Enable, FALSE forces all events FALSE
    bReset    : BOOL;            // 上升沿清零计数器，并抑制当周期事件 / Rising edge clears counters, suppresses current-scan events
END_VAR
VAR_OUTPUT
    bLevel     : BOOL;           // 当前电平（直通） / Current level, pass-through
    bRising    : BOOL;           // 上升沿，单周期脉冲 / Rising edge, one-scan pulse
    bFalling   : BOOL;           // 下降沿，单周期脉冲 / Falling edge, one-scan pulse
    bChanged   : BOOL;           // 任意跳变 = 上升 OR 下降 / Any transition = rising OR falling
    uRiseCount : UDINT;          // 累计上升沿次数 / Accumulated rising edges
    uFallCount : UDINT;          // 累计下降沿次数 / Accumulated falling edges
    uErrorId   : UDINT;          // 故障码（仅计数器溢出告警） / Error code (counter overflow warning only)
END_VAR
VAR
    fbTrigRise : R_TRIG;         // 上升沿检测 / Rising edge detector
    fbTrigFall : R_TRIG;         // 下降沿检测（对取反信号） / Falling edge detector on inverted signal
    bLastLevel : BOOL;           // 上周期电平 / Previous level
END_VAR
VAR CONSTANT
    DL_EDGE_COUNT_MAX : UDINT := 16#FFFF_FFFE;  // 计数器饱和上限，达上限后停增不死锁 / Saturation limit
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 双 `R_TRIG` 无条件刷新 | `fbTrigRise(CLK := bSignal)` 与 `fbTrigFall(CLK := NOT bSignal)` 必须在最前部无条件调用；`bRising := fbTrigRise.Q AND bLastLevel`（防 `bLastLevel` 未初始化时误报） |
| B2 | 上电首扫 | 首次调用（以 `bLastLevel` 初值 FALSE 判据不可靠）→ 用 `R_TRIG` 实现天然抑制：首扫 `Q = FALSE`，无需额外标志 |
| B3 | 事件互斥 | `bRising` 与 `bFalling` 同周期不可能同时 TRUE（`bChanged = bRising OR bFalling` 已隐含） |
| B4 | 计数器饱和 | 达 `DL_EDGE_COUNT_MAX` 后停止累加（`IF uRiseCount < MAX THEN uRiseCount := uRiseCount + 1; ELSE uErrorId := 16#0001_0007; END_IF`），**禁止回绕归零**（回绕会让后续基于计数的逻辑静默错乱） |
| B5 | 复位语义 | `bReset` 上升沿：计数清零、`bLastLevel := bSignal`、当周期三类事件全部 FALSE（防止「复位瞬间误报一遍边沿」） |
| B6 | 使能语义 | `bEnable := FALSE` 时事件全 FALSE，但**电平 `bLevel` 必须继续直通**，且 `bLastLevel` 继续跟踪（否则恢复使能时会补发一个假边沿） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B4 饱和、B5 复位）｜ R5 ✓ ｜ R6 N/A（无状态机，仅边沿锁存，已在 B1 说明）｜ R7 ✓（B1）`

**AI 训练语料 instruction 方向**
> 「包装机上有 8 个工位都要取同一个编码器到位信号，有人写上升沿、有人写 `NOT` 取下降沿，维护混乱。请写一个双边沿检测功能块，同时输出上升/下降/任意跳变三种单周期脉冲与当前电平，要求计数器到达上限饱和而不回绕，恢复使能时不得补发假边沿。」

---

### 2.3 `FC_DL_BitGet` ｜ DL_Base ｜ 复杂度 2

**功能定位**：从 32 位状态字中安全提取某一位，位索引越界时返回 FALSE 并给出合法性标志，而不是让越界索引在 `SHL`/`SHR` 里产生平台相关的未定义行为（CODESYS 与 TwinCAT 对移位量 ≥ 位宽的处理不一致，这是跨平台移植的经典暗坑）。

**接口契约**

```iecst
FUNCTION FC_DL_BitGet : BOOL
VAR_INPUT
    uValue    : DWORD;    // 待检测的 32 位状态字 / Source 32-bit word
    uBitIndex : USINT;    // 位序号，0 = LSB，合法域 0..31 / Bit index, 0 = LSB, valid 0..31
END_VAR
VAR_OUTPUT
    bValid    : BOOL;     // 索引合法标志，FALSE 时返回值为保底 FALSE / Index valid flag
    uErrorId  : UDINT;    // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR CONSTANT
    DL_BIT_INDEX_MAX : USINT := 31;   // 32 位字的最大位索引 / Max bit index for 32-bit word
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 越界先判后算 | `IF uBitIndex > DL_BIT_INDEX_MAX THEN bValid := FALSE; uErrorId := 16#0001_0001; FC_DL_BitGet := FALSE; RETURN; END_IF` —— **禁止先移位再校验** |
| B2 | 位提取写法 | 必须用 `SHR(uValue, uBitIndex) AND 16#0000_0001`，再 `<> 0` 转 BOOL；**禁止 `uValue.%X0`**（西门子方言，R3 违规） |
| B3 | 类型显式 | `SHR` 的第二个参数在某些平台要求 `UDINT`，需显式 `DWORD_TO_UDINT` 或统一使用 `UDINT` 入参变体；编码时选定一种并全库统一 |
| B4 | 返回值兜底 | 任何异常路径下函数返回值必须确定（FALSE），**不允许未赋值返回**（部分平台未赋值返回上次调用残值） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（B2 直接针对 `%X` 方言）｜ R4 ✓（B1 越界、B4 返回值确定）｜ R5 ✓ ｜ R6 N/A（无状态机）｜ R7 N/A（无定时器/边沿实例）`

**AI 训练语料 instruction 方向**
> 「从 Modbus 读回的状态字里取第 13 位判断气缸到位，现场换到另一品牌 PLC 后偶发误动作，怀疑是移位量越界。请写一个带位索引合法性校验的位提取函数，越界时返回 FALSE 并输出错误码，且不得使用任何厂商专有位访问语法。」

---

### 2.4 `FC_DL_BitSet` ｜ DL_Base ｜ 复杂度 3

**功能定位**：对 32 位字做「置位 / 复位」的安全纯函数（输入原值、输出新值），不修改入参、不产生副作用，便于在表达式与 `CASE` 分支中链式使用——解决「`uWord.5 := TRUE` 这种方言写法」与「就地改写导致扫描周期内多处引用看到不同值」的两类问题。

**接口契约**

```iecst
FUNCTION FC_DL_BitSet : DWORD
VAR_INPUT
    uValue    : DWORD;             // 原始状态字 / Source word
    uBitIndex : USINT;             // 位序号，0 = LSB，合法域 0..31 / Bit index, 0 = LSB, valid 0..31
    bSetValue : BOOL := TRUE;      // TRUE = 置 1，FALSE = 清 0 / TRUE = set, FALSE = clear
END_VAR
VAR_OUTPUT
    bValid    : BOOL;              // 索引合法标志 / Index valid flag
    uErrorId  : UDINT;             // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uMask     : DWORD;             // 目标位掩码 / Target bit mask
END_VAR
VAR CONSTANT
    DL_BIT_INDEX_MAX : USINT := 31;  // 最大位索引 / Max bit index
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 越界返回原值 | 索引 > 31 → 返回值 = `uValue`（**不做任何修改**，不是返回 0），`bValid := FALSE`，`uErrorId := 16#0001_0001` |
| B2 | 掩码构造 | `uMask := SHL(DWORD#1, uBitIndex)`；**必须在校验通过后才构造**，避免越界移位 |
| B3 | 置位/清零对称 | 置位 `uValue OR uMask`；清零 `uValue AND NOT uMask`（`NOT` 作用于 DWORD 全域，不得只反 8 位） |
| B4 | 不修改入参 | `VAR_INPUT` 在函数内只读，结果必须经返回值输出；**禁止声明为 `VAR_IN_OUT`**（否则调用方表达式无法使用） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（禁用 `.%X` 位写）｜ R4 ✓（B1 越界、B2 顺序）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「报警字里要让 HMI 能单独强制某一位做测试，但现有代码直接写 `uAlarm.7 := TRUE`，换平台编译不过。请写一个纯函数式的位置位/清位函数，输入原字返回新字，位索引越界时原样返回并给错误码，且清零时不得误伤其它位。」

---

### 2.5 `FC_DL_BitCount` ｜ DL_Base ｜ 复杂度 3

**功能定位**：统计 32 位字中置 1 的位数（Hamming Weight），用于「多传感器投票表决」「多工位占用统计」「报警字严重度分级」——解决现场用 `FOR i := 0 TO 31` 逐位累加导致的扫描时间浪费与越界风险。

**接口契约**

```iecst
FUNCTION FC_DL_BitCount : USINT
VAR_INPUT
    uValue   : DWORD;    // 待统计的 32 位字 / Word to count
END_VAR
VAR_OUTPUT
    bValid   : BOOL;     // 计算完整标志，FALSE 表示触发循环保护 / Calculation complete flag
    uErrorId : UDINT;    // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uTemp    : DWORD;    // 工作副本 / Working copy
    nCount   : USINT;    // 置位计数 0..32 / Population count 0..32
    nGuard   : DINT;     // 循环防死锁计数器 / Loop deadlock guard
END_VAR
VAR CONSTANT
    DL_POPCOUNT_MAX_LOOP : DINT := 32;   // 最多 32 次迭代（Brian Kernighan 上界） / Max iterations
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 算法选择 | 必须用 Brian Kernighan 法：`uTemp := uTemp AND (uTemp - 1)`，全 1 时恰好 32 次，全 0 时 0 次；**禁止逐位 `FOR` + `SHR`**（固定 32 次，且易写错边界） |
| B2 | `WHILE` 防死锁 | `WHILE uTemp <> 0 AND nGuard < DL_POPCOUNT_MAX_LOOP DO ... nGuard := nGuard + 1; END_WHILE`；退出后 `IF nGuard >= MAX THEN bValid := FALSE; uErrorId := 16#0001_0004;` |
| B3 | 无符号减法 | `uTemp - 1` 在 `uTemp = 0` 时会下溢回绕，**必须在 `uTemp <> 0` 的前提下执行**（B2 的循环条件已保证，但需在注释中写死该前提） |
| B4 | 返回类型容量 | 最大 32 位 < `USINT` 上限 255，无溢出风险；**禁止返回 `USINT` 之外的有符号类型**（下游做加法易出错） |
| B5 | 常量字面量 | 位掩码必须写 `16#0000_0001` 形式，禁止 `1`（R3 隐式类型转换风险） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B2 防死锁，本组件核心考点）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「三个光电传感器做 2oo3 表决，需要统计 32 位输入字里置 1 的个数。原代码用 32 次循环每周期扫一遍，任务周期被拖长。请用 Brian Kernighan 算法实现置位计数，要求带防死锁计数器、全 1 输入恰好 32 次迭代、全 0 输入零次迭代。」

---

### 2.6 `FC_DL_PackBitsToWord` ｜ DL_Base ｜ 复杂度 2

**功能定位**：把 16 路离散 BOOL 状态打包成一个标准报警字 `WORD`，供 Modbus / PROFINET 上传或写入状态字——解决「16 个点各写一次寄存器」「打包顺序各人各样导致 HMI 位错位」的问题。

**接口契约**

```iecst
FUNCTION FC_DL_PackBitsToWord : WORD
VAR_INPUT
    abBits     : ARRAY[0..15] OF BOOL;   // 16 路离散状态，索引 0 对应 bit0 / 16 discrete states, index 0 = bit0
    bInvertAll : BOOL := FALSE;          // 整体取反，适配低电平有效的报警点 / Invert all bits for active-low alarms
END_VAR
VAR
    uResult : WORD;    // 打包结果 / Packed word
    nIndex  : INT;     // 循环索引 / Loop index
END_VAR
VAR CONSTANT
    DL_PACK_BIT_COUNT : INT := 16;   // 打包位数，与数组维度严格一致 / Packed bit count, must match array
END_VAR
```

**决策记录（PM 视角）**：本组件**不设 `uErrorId`**。理由：唯一可能的失败态是「数组维度与循环上界不一致」，而该风险由编译期固定维度 `ARRAY[0..15]` + `VAR CONSTANT` 双重约束消除，引入一个恒为 0 的错误码引脚只会增加调用方噪音。此为对「错误统一经 uErrorId 输出」规则的**显式豁免**，须在手册与 `AGENT_EVOLUTION_LOG.md` 中备案。

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 维度硬绑定 | 数组固定 `ARRAY[0..15]`，循环上界用 `DL_PACK_BIT_COUNT - 1`，**禁止魔法数 15** |
| B2 | 位序唯一约定 | 索引 0 → bit0（LSB），必须在头注释与手册中写死；**不做「可配置位序」开关**（两种位序并存是本库最大的长期维护负担） |
| B3 | 组装写法 | 逐位 `IF abBits[i] THEN uResult := uResult OR SHL(WORD#1, i); END_IF`，或先 `BOOL_TO_WORD` 再 `SHL`；**禁止 `uResult.i := ...` 方言** |
| B4 | 取反语义 | `bInvertAll` 在**组装完成后**整体 `NOT`，不得在循环内逐位取反（两者结果等价，但前者少 16 次分支，且语义更清晰） |
| B5 | 未初始化防御 | 调用方传入未初始化 BOOL 数组时结果为 FALSE（CODESYS 默认初值 FALSE），**不得依赖该行为**，手册须提示调用方显式初始化 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B1 维度绑定、B5 未初始化提示）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「16 个气缸的到位信号要打包成一个 WORD 上传给上位机，此前每人写的位序不同，HMI 上第 3 缸总显示成第 11 缸。请写一个打包函数，明确约定索引 0 对应 bit0，并提供整体取反选项以适配低电平有效的报警点，禁止使用任何 `.%X` 位写语法。」

---

### 2.7 `FB_DL_UnpackWordToBits` ｜ DL_Base ｜ 复杂度 2

**功能定位**：把通信收到的状态字 `WORD` 解包成 16 个独立 BOOL，并给出「字内容发生跳变」的单周期事件与置位总数——解决「每周期无条件刷新导致下游边沿检测失效」「改了某一位却不知道整字变过」的问题。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_UnpackWordToBits
VAR_INPUT
    uWord       : WORD;              // 待解包的状态字 / Source status word
    uInvertMask : WORD := 16#0000;   // 位取反掩码，1 = 该位取反（适配常闭点） / Invert mask, 1 = invert that bit
    bEnable     : BOOL := TRUE;      // 使能，FALSE 时所有输出位为 FALSE / Enable, FALSE forces all bits FALSE
END_VAR
VAR_OUTPUT
    abBits      : ARRAY[0..15] OF BOOL;  // 解包结果，索引 0 = bit0 / Unpacked bits, index 0 = bit0
    bChanged    : BOOL;              // 整字内容变化，单周期脉冲 / Word changed, one-scan pulse
    uBitCount   : USINT;             // 当前置位总数 0..16，冗余校验用 / Popcount 0..16 for redundancy check
    uErrorId    : UDINT;             // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    fbTrigChange : R_TRIG;           // 变化检测 / Change detector
    uXorWord     : WORD;             // 本周期与上周期的差异位 / XOR of current and previous word
    uLastWord    : WORD;             // 上周期状态字 / Previous word
    nIndex       : INT;              // 循环索引 / Loop index
END_VAR
VAR CONSTANT
    DL_UNPACK_BIT_COUNT : INT := 16; // 解包位数 / Unpacked bit count
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 变化检测先于解包 | `uXorWord := uWord XOR uLastWord`；`fbTrigChange(CLK := (uXorWord <> 16#0000))` 必须无条件调用（R7），`bChanged := fbTrigChange.Q` |
| B2 | 上周期值更新时机 | `uLastWord := uWord` 必须在**读取 `fbTrigChange.Q` 之后**执行（顺序写错 = 变化永远检测不到） |
| B3 | 取反掩码应用 | 取反必须在 `uLastWord` 比较**之前**还是之后？→ **约定：比较用原始 `uWord`，取反只作用于输出位**。否则掩码一变就会误报 `bChanged` |
| B4 | 维度硬绑定 | 同 2.6 B1，循环上界走常量 |
| B5 | 计数一致性 | `uBitCount` 必须对**取反后**的输出位统计（与 HMI 看到的位一致），不得统计原始字 |
| B6 | 使能语义 | `bEnable := FALSE` → 所有 `abBits` 强制 FALSE、`uBitCount := 0`，但 `uLastWord` 继续跟踪（防恢复使能时假事件） |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B2 顺序、B6 使能）｜ R5 ✓ ｜ R6 N/A（无状态机，仅有沿锁存）｜ R7 ✓（B1 `R_TRIG` 无条件刷新）`

**AI 训练语料 instruction 方向**
> 「从 Modbus 收到 16 位状态字要拆成 16 个气缸信号，其中 4 个是常闭点。原来每周期无条件赋值，下游取边沿全部失效。请写一个解包功能块，支持位取反掩码，并输出整字变化的单周期事件与置位总数，注意 `R_TRIG` 必须每周期无条件刷新。」

---

### 2.8 `FC_DL_GrayToBinary` ｜ DL_Base ｜ 复杂度 4

**功能定位**：把绝对值编码器输出的格雷码转成标准二进制无符号整数，支持 1~32 位可变位宽与越界钳位——解决「把格雷码当二进制直接用导致位置值乱跳」「高位残留污染低分辨率编码器读数」两类事故。

**接口契约**

```iecst
FUNCTION FC_DL_GrayToBinary : UDINT
VAR_INPUT
    uGrayValue : UDINT;            // 格雷码原始值 / Raw Gray code
    uBitWidth  : USINT := 32;      // 有效位宽 1..32，超出按边界钳位 / Valid bit width 1..32, clamped
END_VAR
VAR_OUTPUT
    bValid     : BOOL;             // 位宽合法标志 / Width valid flag
    uErrorId   : UDINT;            // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uBinary    : UDINT;            // 转换结果 / Conversion result
    uMask      : UDINT;            // 位宽掩码 / Bit-width mask
    uWidth     : USINT;            // 钳位后的位宽 / Clamped width
    nIndex     : USINT;            // 递推索引 / Recurrence index
END_VAR
VAR CONSTANT
    DL_GRAY_WIDTH_MIN : USINT := 1;    // 最小位宽 / Min width
    DL_GRAY_WIDTH_MAX : USINT := 32;   // 最大位宽 / Max width
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 位宽钳位（非报错中断） | `uBitWidth = 0` → `uWidth := 1` + `bValid := FALSE` + `uErrorId := 16#0001_0001`；`> 32` → `uWidth := 32` + 同上。**必须继续计算并返回有效结果**，不得返回 0（返回 0 会让上位机看到「位置突然归零」的假故障） |
| B2 | 掩码构造防溢出 | 位宽 32 时 `SHL(1, 32)` 是未定义行为 → 必须特判：`IF uWidth >= 32 THEN uMask := 16#FFFF_FFFF; ELSE uMask := SHL(UDINT#1, uWidth) - 1; END_IF` |
| B3 | 递推算法 | `uBinary := uGrayValue AND uMask;` 然后 `FOR nIndex := 1 TO uWidth - 1 DO uBinary := uBinary XOR SHR(uGrayValue, nIndex); END_FOR` —— 迭代次数 ≤ 31，天然有界 |
| B4 | 空循环边界 | `uWidth = 1` 时 `FOR 1 TO 0` 不执行（IEC 语义：上界 < 下界则零次），必须在注释中写明该保证，**禁止写成 `FOR 1 TO uWidth`** |
| B5 | 结果掩码 | 转换后再次 `AND uMask`，防止 `XOR` 链带入高位 |
| B6 | Excess 偏移不做 | 本函数**不负责** 360° 编码器的 Excess 76 偏移补偿（职责单一）；手册必须写清调用顺序：转二进制 → 减 Excess 偏移 → 乘分辨率系数 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B1 越界钳位、B2 移位溢出、B4 空循环，本组件 R4 密度最高）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「绝对值编码器读数每转一圈就在某个角度跳到 900 多，怀疑把格雷码当二进制用了。请写一个格雷码转二进制的函数，支持 10/12/17 位等可变位宽，位宽越界时钳位并给错误码而不是返回 0，注意位宽 32 时移位不能溢出。」

---

### 2.9 `FC_DL_BinaryToGray` ｜ DL_Base ｜ 复杂度 3

**功能定位**：二进制转格雷码，用于「向编码器写目标位置」「生成格雷码测试序列验证 `FC_DL_GrayToBinary`」（两个函数互为逆运算，构成自校验闭环）。

**接口契约**

```iecst
FUNCTION FC_DL_BinaryToGray : UDINT
VAR_INPUT
    uBinaryValue : UDINT;         // 二进制原始值 / Raw binary value
    uBitWidth    : USINT := 32;   // 有效位宽 1..32，超出按边界钳位 / Valid bit width 1..32, clamped
END_VAR
VAR_OUTPUT
    bValid       : BOOL;          // 位宽合法标志 / Width valid flag
    uErrorId     : UDINT;         // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uMask        : UDINT;         // 位宽掩码 / Bit-width mask
    uWidth       : USINT;         // 钳位后的位宽 / Clamped width
END_VAR
VAR CONSTANT
    DL_GRAY_WIDTH_MIN : USINT := 1;    // 最小位宽 / Min width
    DL_GRAY_WIDTH_MAX : USINT := 32;   // 最大位宽 / Max width
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 位宽钳位 | 同 2.8 B1，钳位 + `bValid := FALSE` + 错误码，**继续计算** |
| B2 | 掩码特判 | 同 2.8 B2，位宽 32 时不得 `SHL(1,32)` |
| B3 | 单语句实现 | `(uBinaryValue XOR SHR(uBinaryValue, 1)) AND uMask` —— 一条表达式，禁止 `FOR` |
| B4 | 输入先掩码 | 输入值可能带高位脏数据，**必须先 `AND uMask` 再异或**，否则脏高位会渗入格雷码 |
| B5 | 互逆性自检 | 手册必须给出验证用例：对 0..N 全序列，`GrayToBinary(BinaryToGray(x)) = x`；编码 Agent 需据此写单测 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B1/B2/B4）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「要往绝对值编码器写目标位置，驱动器只认格雷码。请写二进制转格雷码函数，要求与已有的格雷码转二进制函数严格互逆，位宽 32 时不能触发移位溢出，输入带脏高位时必须先掩码。」

---

### 2.10 `FC_DL_LinearScale` ｜ DL_MathData ｜ 复杂度 4

**功能定位**：模拟量原始码（如 0~27648、0~32767、4~20mA 对应码）到工程量的线性标定，含量程为零防御与可选双侧钳位——解决「量程参数输错导致除零使 PLC 进入异常」「传感器超量程时工程量飞出发动机可接受区间」两类问题。

**接口契约**

```iecst
FUNCTION FC_DL_LinearScale : REAL
VAR_INPUT
    fIn      : REAL;                 // 原始输入值 [raw] / Raw input value
    fInMin   : REAL := 0.0;          // 输入量程下限 [raw] / Input range low
    fInMax   : REAL := 27648.0;      // 输入量程上限 [raw] / Input range high
    fOutMin  : REAL := 0.0;          // 工程量下限 [EU] / Engineering range low
    fOutMax  : REAL := 100.0;        // 工程量上限 [EU] / Engineering range high
    bClamp   : BOOL := TRUE;         // 是否双侧钳位到工程量程 / Enable two-sided clamping
END_VAR
VAR_OUTPUT
    bValid   : BOOL;                 // 换算有效标志 / Conversion valid flag
    bClamped : BOOL;                 // 结果被钳位标志 / Result was clamped
    fPercent : REAL;                 // 输入占量程百分比 [%]，范围 0~100 或超界 / Input as % of span
    uErrorId : UDINT;                // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    fSpanIn  : REAL;                 // 输入量程跨度 [raw] / Input span
    fSpanOut : REAL;                 // 输出量程跨度 [EU] / Output span
    fResult  : REAL;                 // 中间结果 [EU] / Intermediate result
    fOutLo   : REAL;                 // 输出下限（已排序） [EU] / Ordered output low
    fOutHi   : REAL;                 // 输出上限（已排序） [EU] / Ordered output high
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;   // 浮点判零容差 / Float zero tolerance
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 防除零 | `fSpanIn := fInMax - fInMin`；`IF ABS(fSpanIn) <= DL_FLOAT_EPS THEN` 返回 `fOutMin` + `bValid := FALSE` + `uErrorId := 16#0001_0002` + `RETURN` |
| B2 | 反向量程合法 | `fInMax < fInMin`（反向标定，如 20mA→0%、4mA→100%）必须**正常支持**，不得报错；`fPercent` 随之反向（0% 在 `fInMax` 侧），手册须明示 |
| B3 | 输出量程排序 | 钳位前先 `fOutLo := MIN(fOutMin, fOutMax); fOutHi := MAX(fOutMin, fOutMax);` —— 否则输出量程传反时「钳位」会把结果压到错误端点 |
| B4 | 双侧钳位 | `IF bClamp THEN fResult := MIN(MAX(fResult, fOutLo), fOutHi); 若 fResult 与钳位前不等则 bClamped := TRUE;` —— **只 `MIN` 不 `MAX` 是红线级错误**（负向冲击打穿执行机构） |
| B5 | 浮点判等 | 钳位判定不得用 `fResult <> fBefore`，须用 `ABS(diff) > DL_FLOAT_EPS` |
| B6 | 百分比除零 | `fPercent := (fIn - fInMin) / fSpanIn * 100.0` 依赖 B1 已保证 `fSpanIn` 非零，**必须在 B1 之后计算** |
| B7 | 显式类型转换 | `100.0`、`0.0` 等字面量必须带小数点；`REAL` 与 `LREAL` 不得混用 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B1 除零、B3 排序、B4 双侧、B5 容差，本组件为 R4 样板）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「4~20mA 压力变送器接 0~27648 的 AI 通道，量程 0~1.6MPa。现场把量程上下限填反了，PLC 算出负数还报了除零异常，超压时数值还冲到 3MPa 显示。请写一个带反向量程支持、量程为零防御、双侧钳位的线性标定函数，钳位判定要用浮点容差。」

---

### 2.11 `FC_DL_Deadband` ｜ DL_MathData ｜ 复杂度 3

**功能定位**：抑制零点附近的微小波动（传感器零漂、量化噪声、参数计算残差），支持移位型与归零型两种语义——解决「PID 在设定点附近持续小幅修正导致调节阀/比例阀频繁动作、寿命骤降」这个工业界最典型的执行机构损耗问题。

**接口契约**

```iecst
FUNCTION FC_DL_Deadband : REAL
VAR_INPUT
    fIn       : REAL;              // 输入值 [EU] / Input value
    fWidth    : REAL := 0.0;       // 死区半宽 [EU]，负值取绝对值 / Deadband half-width, negative taken as absolute
    fCenter   : REAL := 0.0;       // 死区中心偏移 [EU]，零点不在 0 时使用 / Deadband center offset
    bZeroMode : BOOL := FALSE;     // FALSE = 移位型（连续），TRUE = 归零型（阈值开关） / FALSE = shift type, TRUE = zero type
END_VAR
VAR_OUTPUT
    bInDeadband : BOOL;            // 当前处于死区内 / Currently inside deadband
    fDeviation  : REAL;            // 去中心后的原始偏差 [EU] / Raw deviation from center
    fEffWidth   : REAL;            // 实际生效死区半宽 [EU] / Effective half-width
    uErrorId    : UDINT;           // 故障码，0 = 无故障 / Error code
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6; // 浮点判零容差 / Float zero tolerance
END_VAR
```

**语义定义（必须写死，禁止两义并存）**

| 模式 | 条件 | 输出 |
|---|---|---|
| **移位型**（默认，`bZeroMode = FALSE`） | `ABS(fDeviation) < fEffWidth` | `0.0` |
| | 否则 | `fDeviation - SIGN(fDeviation) * fEffWidth`（**连续无跳变**） |
| **归零型**（`bZeroMode = TRUE`） | `ABS(fDeviation) < fEffWidth` | `0.0` |
| | 否则 | `fDeviation`（死区边界**有跳变**，跳变量 = 死区宽度） |

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 负宽度容错 | `IF fWidth < 0.0 THEN fEffWidth := ABS(fWidth); uErrorId := 16#0001_0003; ELSE fEffWidth := fWidth; END_IF` —— 绝对值化后继续运行，**不返回 0**（返回 0 会让死区突然消失、执行机构立刻开始抖动） |
| B2 | 零宽度语义 | `fEffWidth = 0` 时必须严格直通（`输出 = fDeviation`），且 `bInDeadband := FALSE`；判定用 `<` 而非 `<=`，避免「零宽度时 0 输入被判在死区」 |
| B3 | 符号函数跨平台 | IEC 61131-3 **无标准 `SIGN()`**，必须用 `IF ... THEN 1.0 ELSE -1.0` 自行实现；`fDeviation = 0.0` 时符号取 `+1.0` 并打注释（避免除零式未定义行为） |
| B4 | 零值浮点判等 | `fDeviation` 与 0 的比较用 `ABS(fDeviation) <= DL_FLOAT_EPS`，**禁止 `= 0.0`** |
| B5 | 死区宽度上限保护 | 借鉴 OSCAT `DEAD_BAND_A` 的 `LM` 限幅思想：`fEffWidth` 不得超过输入量程的 50%（上限以入参 `fMaxWidth` 或常量给定），防止参数误填 999 导致输出恒为 0 而现场无法察觉 |
| B6 | 失真披露 | 手册必须写明「死区会使信号失真，失真量恰为死区宽度；用于 PID 误差通道时 `fCenter` 必须为 0」，否则零点被人工搬移 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（B3 无标准 SIGN，本组件 R3 关键考点）｜ R4 ✓（B1 负值、B2 零宽、B4 判等、B5 上限）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「调节阀在设定点附近每 200ms 动作一次，阀门定位器三个月就磨损。需要在 PID 误差通道上加死区，但死区宽度填负数时阀门会突然开始剧烈抖动。请写一个死区函数，支持移位型与归零型两种语义，负宽度取绝对值并告警，且 IEC 标准里没有 SIGN 函数要自己实现。」

---

### 2.12 `FC_DL_Hysteresis` ｜ DL_MathData ｜ 复杂度 4

**功能定位**：施密特迟滞比较器（双阈值），输出在上阈值以上置 TRUE、下阈值以下置 FALSE、回差带内保持原态——解决「液位/温度在单阈值附近反复跨越导致泵、加热器、报警器高频启停」的问题。

**接口契约**

```iecst
FUNCTION FC_DL_Hysteresis : BOOL
VAR_INPUT
    fIn          : REAL;           // 输入值 [EU] / Input value
    fThreshold   : REAL;           // 设定点（回差带中心） [EU] / Setpoint, center of hysteresis band
    fHysteresis  : REAL := 0.0;    // 回差总宽度 [EU]，负值取绝对值 / Total hysteresis width, negative taken absolute
END_VAR
VAR_IN_OUT
    bState       : BOOL;           // 迟滞状态，调用方持有并每周期回传 / Hysteresis state, retained by caller
END_VAR
VAR_OUTPUT
    fUpperTrip   : REAL;           // 实际上阈值 = fThreshold + fHysteresis/2 [EU] / Effective upper trip
    fLowerTrip   : REAL;           // 实际下阈值 = fThreshold - fHysteresis/2 [EU] / Effective lower trip
    uErrorId     : UDINT;          // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    fHalfBand    : REAL;           // 半回差带宽 [EU] / Half hysteresis band
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : REAL := 1.0E-6;   // 浮点判零容差 / Float zero tolerance
    DL_HYST_MAX_RATIO : REAL := 0.5;   // 回差不超过设定点绝对值的 50%，防误填 / Max hysteresis ratio
END_VAR
```

**接口设计决策（必须写入手册）**：迟滞的输出**依赖上一周期的输出**，本质是有状态运算。因此本组件虽然是 `FC_`，但**必须**通过 `VAR_IN_OUT bState` 把状态交还调用方持有（见 `RAW_NOTES.md` C5）。调用方声明 `bHystState : BOOL;` 并每周期传入同一变量即可。这比强行做成 FB 更轻量（无实例内存、可放在 `IF` 表达式内），代价是调用方必须遵守「同一变量回传」纪律——手册须给出错误示例（每次传新变量 → 退化为纯比较器）。

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 回差负值容错 | `fHalfBand := ABS(fHysteresis) * 0.5`；`fHysteresis < 0` 时置 `uErrorId := 16#0001_0003`（继续运行） |
| B2 | 回差上限保护 | `IF fHalfBand > ABS(fThreshold) * DL_HYST_MAX_RATIO THEN` 钳到该上限 + 错误码 —— 防止参数误填导致阈值跑到物理量程之外、设备永不动作 |
| B3 | 零回差语义 | `fHysteresis = 0` 时上阈值 = 下阈值 = 设定点 → 退化为普通比较器（会抖），**允许但必须告警**（`uErrorId := 16#0001_0003` 或独立 `bNoHysteresis` 输出） |
| B4 | 严格不等号 | 置位条件用 `fIn > fUpperTrip`（严格大于），复位条件用 `fIn < fLowerTrip`（严格小于）；**等于阈值时保持原态**，这是迟滞的定义，不得写成 `>=`/`<=` |
| B5 | 状态初值 | `bState` 上电初值 FALSE 时，若 `fIn` 一开始就在回差带内，输出保持 FALSE（不会误置位）——该行为须在手册中说明，并提供「首次强制同步」调用示例（先给一个低于下阈值的假值跑一周期） |
| B6 | 浮点判等 | 阈值比较属「大小比较」不受浮点判等红线约束，但 `fUpperTrip`/`fLowerTrip` 与 `fThreshold` 的一致性自检（若做）须用容差 |
| B7 | 有状态纪律 | 头注释必须显式警告：`VAR_IN_OUT` 传入的必须是**持久变量**，禁止传表达式或临时变量 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B1/B2/B3/B6）｜ R5 ✓（B7 为 R5 附加要求）｜ R6 N/A（迟滞用状态位而非状态机，已在接口决策说明）｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「冷却水泵按单个液位阈值启停，水位在阈值附近波动时泵每分钟启停十几次，接触器已经烧了两台。请写一个施密特迟滞比较函数，用上/下双阈值加回差带，回差宽度可调但要有上限保护，注意 IEC 的 FC 不能保存状态所以要用 `VAR_IN_OUT` 把状态交还调用方。」

---

### 2.13 `FB_DL_MovingAverage` ｜ DL_MathData ｜ 复杂度 6

**功能定位**：O(1) 递推滑动平均滤波，窗口长度运行时可变，采样节拍由调用方控制——解决「大窗口 `FOR` 循环拖长扫描周期」与「上电头几秒窗口未填满导致输出比原始信号还剧烈」这两个滑动平均实现中的经典缺陷。

**接口契约**

```iecst
FUNCTION_BLOCK FB_DL_MovingAverage
VAR_INPUT
    fInput      : REAL := 0.0;      // 原始采样值 [EU] / Raw sampled value
    nWindowSize : INT := 8;         // 窗口长度，合法域 1..100 / Window length, valid 1..100
    bSample     : BOOL := TRUE;     // 采样触发：TRUE = 每周期采样；接脉冲则按事件采样 / Sample trigger
    bEnable     : BOOL := TRUE;     // 使能，FALSE 时输出保持并停止采样 / Enable, FALSE holds output
    bReset      : BOOL;             // 上升沿清空窗口与累加和 / Rising edge clears buffer and sum
END_VAR
VAR_OUTPUT
    fAverage    : REAL;             // 窗口算术平均 [EU] / Window arithmetic mean
    bBufferFull : BOOL;             // 窗口已填满标志 / Buffer full flag
    nSampleCount: INT;              // 窗口内有效样本数 0..nWindowSize / Valid sample count
    fWindowSum  : REAL;             // 窗口累加和（诊断用） [EU] / Window sum, for diagnostics
    bError      : BOOL;             // 故障标志，需 bReset 清除 / Fault flag
    uErrorId    : UDINT;            // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    afBuffer    : ARRAY[0..99] OF REAL;  // 环形缓冲区 [EU] / Ring buffer
    nWriteIndex : INT;              // 环形写指针 0..99 / Ring write index
    nFilled     : INT;              // 已填充样本数 / Filled sample count
    fSum        : REAL;             // 滑动累加和 / Running sum
    nLastWindow : INT;              // 上周期窗口长度（变更检测） / Previous window size
    fbTrigSample: R_TRIG;           // 采样上升沿 / Sample rising edge
    fbTrigReset : R_TRIG;           // 复位上升沿 / Reset rising edge
    nCorrectCnt : DINT;             // 重算校正倒计数 / Recalculation counter
    nGuard      : DINT;             // 重算循环防死锁计数 / Recalc loop guard
    fRecalcSum  : REAL;             // 重算中间和 / Recalc intermediate sum
    nIdx        : INT;              // 重算循环索引 / Recalc index
END_VAR
VAR CONSTANT
    DL_MAV_MAX_WINDOW   : INT := 100;      // 窗口上限，与数组维度一致 / Max window, must match array
    DL_MAV_MIN_WINDOW   : INT := 1;        // 窗口下限 / Min window
    DL_MAV_CORRECT_CYCLE: DINT := 10000;   // 每 N 次采样做一次全窗口重算校正 / Recalc every N samples
    DL_MAV_MAX_LOOP     : DINT := 100;     // 重算循环上限 / Recalc loop limit
    DL_FLOAT_EPS        : REAL := 1.0E-6;  // 浮点判零容差 / Float zero tolerance
END_VAR
```

**必须覆盖的边界防御点（本组件是全轮防御密度最高的）**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | **启动两阶段分离** | 窗口未满（`nFilled < nWindow`）阶段：只执行「写入 + 累加 + `nFilled + 1`」，**绝不执行「减最旧值」**；窗口已满阶段：执行「减最旧 + 加最新 + 指针递增」。两阶段必须用 `IF bBufferFull THEN ... ELSE ... END_IF` 明确分支，禁止合并写法 |
| B2 | 防除零 | `IF nFilled > 0 THEN fAverage := fSum / INT_TO_REAL(nFilled); ELSE fAverage := 0.0; END_IF`；窗口长度 0 已被 B3 钳位，**双保险不可省** |
| B3 | 窗口长度钳位 | `nWindowSize < 1` → 钳到 1 + `uErrorId := 16#0001_0001`；`> 100` → 钳到 100 + 同上。**先钳位再用于所有后续计算** |
| B4 | 窗口长度运行时变更 | `nWindowSize <> nLastWindow` → 清空缓冲区、`nFilled := 0`、`fSum := 0.0`、`nWriteIndex := 0`，重新走 B1 的未满阶段（**不清空会导致新旧窗口样本混算，输出出现台阶**） |
| B5 | 指针回绕 | `nWriteIndex := (nWriteIndex + 1) MOD nWindowEff`；`MOD` 的除数已被 B3 保证 ≥ 1；**必须用 `MOD` 而非 `IF idx >= N THEN idx := 0`**（前者不会漏分支） |
| B6 | 累加漂移校正 | 每 `DL_MAV_CORRECT_CYCLE` 次采样触发一次全窗口重算：`fRecalcSum := 0.0; nGuard := 0; FOR nIdx := 0 TO nFilled - 1 DO fSum 累加; nGuard := nGuard + 1; IF nGuard >= DL_MAV_MAX_LOOP THEN EXIT; END_IF; END_FOR`，重算后 `fSum := fRecalcSum` |
| B7 | `R_TRIG` 无条件刷新 | `fbTrigSample(CLK := bSample)` 与 `fbTrigReset(CLK := bReset)` 必须在主体最前部（R7）；`bSample := TRUE` 常 TRUE 时 `R_TRIG` 只在首周期出一次脉冲 → **该矛盾必须解决**：语义定义为「`bSample` 为电平 TRUE 且与上周期相比无变化 → 每周期采样；若调用方给出脉冲则按沿采样」，实现方式为 `bDoSample := bSample AND (NOT fbTrigSample.Q OR bSampleAlways)`…**编码 Agent 必须选择「每周期采样」为默认路径（`IF bSample THEN`）并只在注释中说明脉冲接法**，禁止用 `R_TRIG` 承担两种语义（会导致常 TRUE 只采一次的低级事故） |
| B8 | 使能语义 | `bEnable := FALSE`：停止采样、`fAverage` 保持最后值、`bBufferFull` 保持、**不清空**（恢复使能后继续用旧窗口，避免输出跳变） |
| B9 | 复位语义 | `bReset` 上升沿：清缓冲、`nFilled := 0`、`fSum := 0.0`、`fAverage := 0.0`、`bBufferFull := FALSE`、`uErrorId := 0`、`bError := FALSE` |
| B10 | 状态机兜底 | 若采用 ENUM 状态机（`eInit` / eFilling / eRunning / eFault），`ELSE` 分支必须回 `eFault` + `uErrorId := 16#0001_0005` |
| B11 | 滞后披露 | 手册必须写明：相位滞后 ≈ `(N-1)/2` 个采样周期，滤波时间窗 = `N × 采样周期`，**安全联锁回路禁止使用大窗口滤波值** |
| B12 | 断电保持提示 | 手册必须提示：缓冲区/指针/累加和若不设 RETAIN，重新上电会重走未满阶段 |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓ ｜ R4 ✓（B2 除零、B3 越界、B5 `MOD` 回绕、B6 防死锁，本组件为 R4 与 R7 双重样板）｜ R5 ✓ ｜ R6 ✓（若启用状态机则四态 + ELSE 兜底；B10）｜ R7 ✓（B7，且 B7 本身就是「`R_TRIG` 用错」的反面教材）`

**AI 训练语料 instruction 方向**
> 「压力信号要 20 点滑动平均，但原实现每周期跑 20 次加法，任务周期从 4ms 涨到 7ms；而且上电头三秒显示值比原始信号抖得更厉害。请用 O(1) 递推实现滑动平均，必须区分窗口未填满与已填满两阶段，窗口长度运行时可改且改后重建缓冲，并定期全窗口重算消除浮点累加漂移。」

---

### 2.14 `FC_DL_Crc16Modbus` ｜ DL_MathData ｜ 复杂度 5

**功能定位**：标准 Modbus RTU CRC-16 校验计算（多项式 `0xA001` / 初值 `0xFFFF` / 输入输出反射），提供字节缓冲区接口与长度越界防御——解决「自己写的 CRC 校验对不上、通信一直报校验错」「不同厂商 PLC 位移位语义不同导致同一算法表现不一致」两类问题。

**接口契约**

```iecst
FUNCTION FC_DL_Crc16Modbus : WORD
VAR_IN_OUT
    abyData : ARRAY[0..255] OF BYTE;   // 报文缓冲区，定长 256 字节，按 uByteCount 取前 N 字节 / Fixed 256-byte frame buffer
END_VAR
VAR_INPUT
    uByteCount : UINT := 0;            // 参与校验的字节数，合法域 1..256 / Number of bytes to checksum, valid 1..256
END_VAR
VAR_OUTPUT
    bValid     : BOOL;                 // 长度合法标志 / Length valid flag
    uErrorId   : UDINT;                // 故障码，0 = 无故障 / Error code
END_VAR
VAR
    uCrc       : WORD;                 // CRC 寄存器 / CRC register
    uCount     : UINT;                 // 钳位后的字节数 / Clamped byte count
    nIdx       : UINT;                 // 字节循环索引 / Byte loop index
    nBit       : USINT;                // 位循环索引 0..7 / Bit loop index
    bLsbSet    : BOOL;                 // 移位前最低位状态 / LSB state before shift
END_VAR
VAR CONSTANT
    DL_CRC16_POLY   : WORD := 16#A001;   // 反向多项式 0x8005 / Reversed polynomial
    DL_CRC16_INIT   : WORD := 16#FFFF;   // Modbus 规定初值 / Modbus initial value
    DL_CRC16_MAXLEN : UINT := 256;       // 最大字节数，与数组维度一致 / Max byte count
END_VAR
```

**必须覆盖的边界防御点**

| # | 防御点 | 具体要求 |
|---|---|---|
| B1 | 长度为零 | `uByteCount = 0` → 返回 `DL_CRC16_INIT`（`16#FFFF`）+ `bValid := FALSE` + `uErrorId := 16#0001_0001`；**不得返回 0**（返回 0 会被当成合法 CRC 值） |
| B2 | 长度超限 | `uByteCount > 256` → 钳到 256 + `bValid := FALSE` + 错误码，**继续计算 256 字节**（不中断，便于现场边通信边排错） |
| B3 | 循环边界 | `FOR nIdx := 0 TO uCount - 1`；`uCount ≥ 1` 已由 B1/B2 保证；内层 `FOR nBit := 0 TO 7` 固定 8 次；**禁止 `FOR ... BY -1` 或动态步长** |
| B4 | 移位语义跨平台 | 必须用 `SHR(uCrc, 1)`，**禁止 `/ 2`**（整数除法在不同平台对无符号/有符号处理有差异，且可读性差）；`AND 16#0001` 判断移出位，**禁止 `.%X0`** |
| B5 | 位判断时序 | 必须**先**取 `bLsbSet := (uCrc AND 16#0001) <> 0`，**再**右移，最后按 `bLsbSet` 条件异或 —— 顺序写反是最常见实现错误 |
| B6 | 输入字节转换 | `uCrc := uCrc XOR BYTE_TO_WORD(abyData[nIdx])`，必须显式 `BYTE_TO_WORD`（R3 禁隐式转换） |
| B7 | 测试向量自检 | 手册与单测必须包含两条已知向量：① 单字节 `0x0C` → `0x911E`；② 帧 `01 03 00 00 00 02` → CRC 寄存器 `0x0BC4`，**发送顺序为低字节 `0xC4` 在前** |
| B8 | 返回字节序说明 | 函数返回**寄存器值**（高字节在前语义）；拼帧时调用方须自行拆低/高字节，手册必须给出拆帧示例代码片段（非交付代码） |
| B9 | 查表法不在首版 | 首版仅实现逐位法；256 项常量表的跨平台初始化行为待验证，列入 ROADMAP |

**红线自检**：`R1 ✓ ｜ R2 ✓ ｜ R3 ✓（B4 禁 `/2` 与 `.%X0`，本组件 R3 关键考点）｜ R4 ✓（B1 长度为零、B2 超限、B3 循环边界、B5 时序）｜ R5 ✓ ｜ R6 N/A ｜ R7 N/A`

**AI 训练语料 instruction 方向**
> 「Modbus RTU 通信一直报 CRC 校验错，用别人的 C 代码算出来是对的，PLC 里算出来不一样，怀疑是移位和除法在不同平台表现不同。请用纯 IEC 61131-3 语法实现 CRC-16/MODBUS（多项式 0xA001、初值 0xFFFF），字节数越界要钳位告警，并说明结果的两个字节应按低字节先发。」

---

## 3 复杂度与工作量分布

| 复杂度 | 组件 | 数量 | 说明 |
|---|---|---|---|
| 2 | DualEdgeTrig、BitGet、PackBitsToWord、UnpackWordToBits | 4 | 单点逻辑，重点在注释与位序约定 |
| 3 | BitSet、BitCount、BinaryToGray、Deadband | 4 | 有明确算法/语义分支，需写清文档 |
| 4 | GrayToBinary、LinearScale、Hysteresis | 3 | 边界条件密集，是 R4 红线的样板组件 |
| 5 | SignalDebounce、Crc16Modbus | 2 | 时序 + 状态机 / 跨平台位运算陷阱 |
| 6 | MovingAverage | 1 | 全轮唯一，状态机 + 浮点 + 循环 + 两阶段启动 |
| **合计** | — | **14** | 平均 3.57，符合 Level 0 组件应有的难度分布 |

---

## 4 下游交付验收清单（编码 Agent 必须逐条自证）

### 4.1 文件级
- [ ] 14 个 `.st` 文件，文件名 = POU 名（含前缀），落在 `C:\Library\DL_Base\` 与 `C:\Library\DL_MathData\`
- [ ] 每个文件头部注释块七项齐全：组件名称 / 所属子库 / 当前版本 / 兼容性 / 功能描述 / 开源溯源 / 修订历史
- [ ] 一个文件只放一个 POU（`E_DL_DebounceState` 与 `FB_DL_SignalDebounce` 可同文件，头注释注明归属）

### 4.2 红线级（任一不过 → 直接打回）
- [ ] R1 全文 `GVL` / `VAR_EXTERNAL` 命中 0
- [ ] R2 全文 `%I` / `%Q` / `%M` 命中 0
- [ ] R3 无 `.%X` / `.%B` / `POINTER TO` / `REFERENCE TO` / `SysXxx` / `TcXxx` / `__SYSTEM`；无隐式类型转换
- [ ] R4 每处除法有「分母绝对值 > 1E-6」前置判断；每处数组访问有上下界；每处 `WHILE` 有防死锁计数器；浮点判等全部带容差
- [ ] R5 每个变量声明行尾同时有中文 + 英文注释与单位
- [ ] R6 有状态机的组件（#1、#13）具备 `ENUM` + `CASE` + `ELSE` 兜底
- [ ] R7 所有 `TON`/`R_TRIG` 实例都在主体最前部无条件刷新

### 4.3 契约级
- [ ] 引脚名称、类型、方向、默认值与本文第 2 章**逐字一致**
- [ ] 故障码取值落在 §1.1 分配表内，无自造码
- [ ] 每个组件在手册中有「调用示例」与「故障码表」

### 4.4 文档级（入库同批完成，不得事后补）
- [ ] `DL_Base\VERSION.md`、`DL_MathData\VERSION.md` 更新至 `1.0.0` 并列出组件清单
- [ ] `DL_Base\MANUAL_DL_Base.md`、`DL_MathData\MANUAL_DL_MathData.md` 每组件一节（功能/引脚表/故障码表/调用示例/联调要点）
- [ ] 顶层 `CHANGELOG.md`、`README.md`、`LIBRARY_MANUAL.md` 同步
- [ ] `C:\Library\INDEX_REGISTRY.json` 首次建立，写入 14 条记录（0 → 14）
- [ ] `_AI_Training_Dataset\daoli_st_sft_dataset.jsonl` 写入 14 条语料（按第 2 章 instruction 方向扩写）

---

## 5 风险与决策记录

| # | 风险 / 决策 | 结论 | 理由 |
|---|---|---|---|
| P1 | `FC_DL_Hysteresis` 是「有状态函数」的语义悖论 | 保留 `FC_` + `VAR_IN_OUT bState` | 迟滞的定义就是状态相关（`RAW_NOTES` 来源 5 结论）；做成 FB 会让「放在比较表达式里」的用法消失，得不偿失 |
| P2 | `FC_DL_Deadband` 两套语义（归零型 / 移位型） | 移位型为默认，`bZeroMode` 切换 | 移位型连续、可串入闭环不引入阶跃；归零型是阈值开关直觉，两者都有真实用户 |
| P3 | `FC_DL_PackBitsToWord` 无 `uErrorId` | 显式豁免并备案 | 维度编译期固定，无真实失败路径，恒 0 的错误码是噪音 |
| P4 | `LWORD`（64 位）支持 | 首版不做 | 汇川 InoProShop 对 `LWORD` 支持待验证（`RAW_NOTES` 第十节待查项），先保证三平台可编译 |
| P5 | CRC 查表法 | 首版不做 | 256 项 `VAR CONSTANT` 数组初始化跨平台行为未验证，逐位法确定性最高 |
| P6 | `FB_DL_MovingAverage` 的 `bSample` 双语义（电平/脉冲） | 以电平为主路径，脉冲接法写入注释 | `R_TRIG` 承担双语义会在「常 TRUE」时只采一次，是必出事故的设计（B7） |
| P7 | 位序约定（索引 0 = LSB） | 全库统一，不提供开关 | 可配置位序是长期维护灾难；有特殊需求的 OEM 自行在外层反转数组 |
| P8 | R5 升级为「中文 + 英文双语」 | 本轮执行，建议回写规则库 R9 | 用户明确口径；且双语注释对 AI 训练语料质量有直接增益 |

---

## 6 下一轮前置输入（写给产品经理自己）

1. **组件缺口**：Level 0 剩余 26 项（`DL_Base` 11 + `DL_MathData` 15），其中 `FB_DL_ExtendedTimer`、`FB_DL_AlarmManager`、`FB_DL_StepSequencer` 是 Level 1 的高频被依赖项，应排第二轮 P0。
2. **接口债**：本轮 4 个组件（Hysteresis / MovingAverage / SignalDebounce / UnpackWordToBits）都涉及「状态持有纪律」，第二轮应统一出一份《状态持有型组件调用规范》附录，避免 10000 个组件各写各的。
3. **验证债**：本轮定义了 3 条数值测试向量（CRC 两条 + 格雷码互逆序列），但库级单测体系尚未建立。第三轮前必须落一套「测试向量表」机制，否则万级组件的正确性无法证伪。
