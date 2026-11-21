# MANUAL — DL_MathData 数学与数据处理子库使用手册

> **Sublibrary**：`DL_MathData` ｜ **Version**：v1.6.0 ｜ **Level**：0（零依赖）｜ **Components**：38（Phase 1 20 项收口 + R9 LGF Data Handling / Converter 组深化 6 项 + R10 LGF Math 组 3 项 + R11 区间/几何/随机/分位 4 项 + R12 字符串/数组比对/太阳位置/异常帧 5 项）
> **Platforms**：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop / Machine Expert
> **Depends**：`Standard.library` only（`ABS`、`MIN`、`MAX`、`SHL`、`SHR`、`R_TRIG`、`LEN`、`FIND`、`LEFT`、`DELETE`、`MID`）
> 配套版本记录见 `DL_MathData/VERSION.md`；全库导航见 `C:\Library\README.md`。

---

## 0. 使用前必读 / Before You Start

1. **浮点判零一律带容差**：本子库所有「等于零」的判断都用 `ABS(x) <= DL_FLOAT_EPS`（`1.0E-6`），调用方不得改用 `= 0.0`。
2. **钳位优先于报错**：参数越界时本子库采取「钳位 + 告警 + 继续运行」策略，`bValid = FALSE` 或 `uErrorId ≠ 0` 表示参数曾被修正，返回值仍可用。停机决策权留给调用方。
3. **两类组件不要搞混**：`FC_` 是纯函数（无记忆），只有 `FC_DL_Hysteresis` 例外——它通过 `VAR_IN_OUT` 把状态交还调用方持有。
4. **安全回路禁止用滤波值**：`FB_DL_MovingAverage` 的相位滞后约 `(N-1)/2` 个采样周期，急停、超压、超温等联锁必须用原始值或 `N ≤ 3` 的小窗口值。
5. **中值/统计窗口参数变更即重填**：`FB_DL_MedianFilter` / `FB_DL_SignalStatistics` 的窗口长度变更会清空整窗重走填充，运行中改参数等于丢一段历史样本，配方切换时按此预期。
6. **返回 `FALSE` 的排序函数必须丢弃结果**：`FC_DL_QuickSortLReal` 失败时数组内容未定义，调用方不得假装成功继续用。

---

## 1. FC_DL_LinearScale ｜ 模拟量线性标定

**定位**：模拟量原始码 → 工程量线性换算（如 `0..27648` → `0..1.6 MPa`），含防除零、反向量程、双侧钳位与百分比输出。

### 1.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fIn` | `REAL` | IN | 原始输入值 `[raw]` / Raw input value `[raw]` |
| `fInMin` | `REAL` | IN | 输入量程下限 `[raw]`，默认 `0.0` / Input range low `[raw]`, default `0.0` |
| `fInMax` | `REAL` | IN | 输入量程上限 `[raw]`，默认 `27648.0` / Input range high `[raw]`, default `27648.0` |
| `fOutMin` | `REAL` | IN | 工程量下限 `[EU]`，默认 `0.0` / Engineering low `[EU]`, default `0.0` |
| `fOutMax` | `REAL` | IN | 工程量上限 `[EU]`，默认 `100.0` / Engineering high `[EU]`, default `100.0` |
| `bClamp` | `BOOL` | IN | 双侧钳位使能，默认 `TRUE` / Two-sided clamping, default `TRUE` |
| `bValid` | `BOOL` | OUT | 换算有效；`FALSE` 表示量程跨度为 0 / Valid; `FALSE` means zero span |
| `bClamped` | `BOOL` | OUT | 结果被钳位标志 / Result was clamped |
| `fPercent` | `REAL` | OUT | 输入占量程百分比 `[%]`，可超 0..100 / Input as percent of span `[%]`, may exceed 0..100 |
| `uErrorId` | `UDINT` | OUT | 零跨度返回 `16#0001_0002` / `16#0001_0002` on zero span |
| 返回值 / Return | `REAL` | RET | 工程量结果 `[EU]`；异常路径为 `fOutMin` / Engineering result `[EU]`; `fOutMin` on error |
| `DL_FLOAT_EPS` | `REAL` | CONST | 浮点判零容差 `1.0E-6` / Float zero tolerance |

### 1.2 调用示例 / Example

```iecst
VAR
    fRawPressure : REAL;        // AI 通道原始码 [raw] / Raw AI channel code [raw]
    fPressureMPa : REAL;        // 转换后压力 [MPa] / Converted pressure [MPa]
    fSpanPercent : REAL;        // 量程百分比 [%] / Span percentage [%]
    bScaleValid  : BOOL;
    bScaleClamped: BOOL;
END_VAR

fPressureMPa := FC_DL_LinearScale(
    fIn     := fRawPressure,
    fInMin  := 0.0,        // 0..27648 对应 4..20mA / 0..27648 maps to 4..20 mA
    fInMax  := 27648.0,
    fOutMin := 0.0,
    fOutMax := 1.6,        // 量程 0..1.6 MPa / Range 0..1.6 MPa
    bClamp  := TRUE,
    bValid  => bScaleValid,
    bClamped=> bScaleClamped,
    fPercent=> fSpanPercent );
```

### 1.3 要点 / Notes

- **反向量程合法**：`fInMax < fInMin`（如 20 mA → 0%、4 mA → 100%）属正常配置，不报错；此时 `fPercent = 0` 落在 `fInMin` 侧。
- **钳位前必须先给输出量程排序**：`fOutMin`/`fOutMax` 传反时若不排序，钳位会把结果压到错误端点，现象是「钳位看似生效而输出全错」。
- **只用一侧钳位是安全红线错误**：只做上限会让负向冲击直接打穿执行机构。
- `fPercent` 的计算建立在跨度非零的前提上，实现内已保证该顺序。

---

## 2. FC_DL_Deadband ｜ 死区

**定位**：抑制零点附近的传感器零漂、量化噪声与计算残差，典型用途是 PID 误差通道，防止调节阀高频动作导致定位器磨损。

### 2.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fIn` | `REAL` | IN | 输入值 `[EU]` / Input value `[EU]` |
| `fWidth` | `REAL` | IN | 死区半宽 `[EU]`，默认 `0.0`，负值取绝对值 / Deadband half-width `[EU]`, default `0.0`, negative taken absolute |
| `fCenter` | `REAL` | IN | 死区中心偏移 `[EU]`，默认 `0.0` / Deadband center offset `[EU]`, default `0.0` |
| `bZeroMode` | `BOOL` | IN | `FALSE` = 移位型（默认，连续）；`TRUE` = 归零型（阈值开关）/ `FALSE` shift type (default, continuous); `TRUE` zero type (threshold switch) |
| `bInDeadband` | `BOOL` | OUT | 当前处于死区内 / Currently inside the deadband |
| `fDeviation` | `REAL` | OUT | 去中心后的原始偏差 `[EU]` / Raw deviation from the center `[EU]` |
| `fEffWidth` | `REAL` | OUT | 实际生效的死区半宽 `[EU]` / Effective half-width `[EU]` |
| `uErrorId` | `UDINT` | OUT | 负宽度或超上限返回 `16#0001_0003` / `16#0001_0003` on negative or over-limit width |
| 返回值 / Return | `REAL` | RET | 死区处理后的值 `[EU]` / Deadband-processed value `[EU]` |
| `DL_DEADBAND_MAX_WIDTH` | `REAL` | CONST | 半宽硬上限 `1000.0 [EU]` / Hard upper limit `1000.0 [EU]` |

### 2.2 两种语义 / Two Semantics

| 模式 / Mode | 条件 / Condition | 输出 / Output |
|---|---|---|
| 移位型（默认）/ Shift (default) | `ABS(fDeviation) < fEffWidth` | `0.0` |
| | 否则 / otherwise | `fDeviation - sign(fDeviation) × fEffWidth`（边界连续 / continuous at the edge） |
| 归零型 / Zero type | `ABS(fDeviation) < fEffWidth` | `0.0` |
| | 否则 / otherwise | `fDeviation`（边界跳变量 = 死区宽度 / step equals the band width） |

### 2.3 调用示例 / Example

```iecst
VAR
    fPidError   : REAL;     // PID 误差 = 设定值 - 实际值 [EU] / PID error [EU]
    fDeadbanded : REAL;     // 死区处理后的误差 [EU] / Deadband-processed error [EU]
    bInBand     : BOOL;
END_VAR

fDeadbanded := FC_DL_Deadband(
    fIn       := fPidError,
    fWidth    := 0.5,        // 半宽 0.5 [EU]，即总死区 1.0 / Half-width 0.5, total band 1.0
    fCenter   := 0.0,        // 误差通道必须为 0 / Must be 0 on an error channel
    bZeroMode := FALSE,      // 串入闭环用移位型 / Shift type for closed loops
    bInDeadband => bInBand );
```

### 2.4 要点 / Notes

- **失真披露**：死区必然使信号失真，失真量恰为死区宽度。用于 PID 误差通道时 `fCenter` 必须为 `0.0`，否则零点被人工搬移，积分项会持续累积偏置。
- 负宽度取绝对值后继续运行，**不把宽度压成 0**：宽度归零等于死区消失，阀门立刻恢复高频动作，正是现场最怕的结果。
- IEC 61131-3 无标准 `SIGN()` 函数，实现内自建符号判断；偏差为 0 时符号取 `+1.0`。
- 边界判定用严格小于，边界点算「死区外」，保证移位型在边界连续。

---

## 3. FC_DL_Hysteresis ｜ 施密特迟滞比较

**定位**：双阈值迟滞比较器，高于上阈值置 `TRUE`、低于下阈值置 `FALSE`、带内保持原态。用于液位/温度驱动的泵、加热器、报警器启停。

### 3.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fIn` | `REAL` | IN | 输入值 `[EU]` / Input value `[EU]` |
| `fThreshold` | `REAL` | IN | 设定点，回差带中心 `[EU]` / Setpoint, center of the band `[EU]` |
| `fHysteresis` | `REAL` | IN | 回差总宽度 `[EU]`，默认 `0.0`，负值取绝对值 / Total hysteresis width `[EU]`, default `0.0`, negative taken absolute |
| `bState` | `BOOL` | IN_OUT | 迟滞状态，**调用方持有并每周期回传同一变量** / Hysteresis state, **retained by the caller and passed back every scan** |
| `fUpperTrip` | `REAL` | OUT | 实际上阈值 = `fThreshold + 半回差` `[EU]` / Effective upper trip `[EU]` |
| `fLowerTrip` | `REAL` | OUT | 实际下阈值 = `fThreshold - 半回差` `[EU]` / Effective lower trip `[EU]` |
| `uErrorId` | `UDINT` | OUT | 负回差 / 零回差 / 超上限返回 `16#0001_0003` / `16#0001_0003` on negative, zero or over-limit hysteresis |
| 返回值 / Return | `BOOL` | RET | 迟滞输出（与 `bState` 同值）/ Hysteresis output (same as `bState`) |
| `DL_HYST_MAX_RATIO` | `REAL` | CONST | `0.5`，回差不超过设定点绝对值的 50% / Max ratio of the absolute setpoint |

### 3.2 调用示例 / Example

```iecst
VAR
    bLevelHystState : BOOL;     // 必须持久化！不得传表达式或临时变量 / Must be persistent, never an expression
    fWaterLevel     : REAL;     // 液位 [m] / Water level [m]
    bPumpRun        : BOOL;     // 泵运行命令 / Pump run command
END_VAR

bPumpRun := FC_DL_Hysteresis(
    fIn         := fWaterLevel,
    fThreshold  := 1.50,        // 设定点 1.50 m / Setpoint 1.50 m
    fHysteresis := 0.20,        // 回差 0.20 m，即 1.40 / 1.60 m 起停 / 0.20 m band, trips at 1.40 / 1.60 m
    bState      := bLevelHystState );
```

### 3.3 有状态纪律 / State Discipline

```iecst
(* ✗ 错误：每次传新变量或常量，状态每周期丢失，退化为普通比较器 *)
bPumpRun := FC_DL_Hysteresis(fIn := fWaterLevel, fThreshold := 1.50, fHysteresis := 0.20, bState := FALSE);

(* ✓ 正确：同一持久变量每周期回传 *)
bPumpRun := FC_DL_Hysteresis(fIn := fWaterLevel, fThreshold := 1.50, fHysteresis := 0.20, bState := bLevelHystState);
```

### 3.4 要点 / Notes

- 置位用**严格大于**、复位用**严格小于**；等于阈值时保持原态——写成 `>=` / `<=` 会让回差带退化，边界抖动立刻回来。
- 回差上限按设定点绝对值的 50% 钳位，防参数误填导致阈值跑到物理量程之外、设备永不动作；设定点接近 0 时跳过比例限幅，改用绝对约束。
- `bState` 上电初值 `FALSE`，若输入一开始就落在带内则输出保持 `FALSE`（保守方向对泵与加热器均为安全侧）。需要「首次强制同步」时，可先用一个低于下阈值的假值空跑一周期。
- 零回差允许运行但必须告警（组态缺陷而非运行故障）。

---

## 4. FB_DL_MovingAverage ｜ 滑动平均滤波

**定位**：O(1) 递推滑动平均，窗口长度运行时可改，采样节拍由调用方控制。计算量与窗口长度无关，扫描周期恒定。

### 4.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fInput` | `REAL` | IN | 原始采样值 `[EU]`，默认 `0.0` / Raw sampled value `[EU]`, default `0.0` |
| `nWindowSize` | `INT` | IN | 窗口长度 1..100，默认 `8`，越界钳位 / Window length 1..100, default `8`, clamped |
| `bSample` | `BOOL` | IN | 采样触发（**电平语义**），默认 `TRUE` = 每周期采样 / Sample trigger (**level semantics**), default `TRUE` = every scan |
| `bEnable` | `BOOL` | IN | 使能，`FALSE` 时停止采样并保持输出，不清缓冲 / Enable; `FALSE` stops sampling and holds output without clearing the buffer |
| `bReset` | `BOOL` | IN | 上升沿清空窗口与累加和 / Rising edge clears buffer and sum |
| `fAverage` | `REAL` | OUT | 窗口算术平均 `[EU]` / Window arithmetic mean `[EU]` |
| `bBufferFull` | `BOOL` | OUT | 窗口已填满标志，同时是两阶段判据 / Buffer full flag, also the two-phase discriminator |
| `nSampleCount` | `INT` | OUT | 窗口内有效样本数 0..`nWindowSize` / Valid sample count 0..`nWindowSize` |
| `fWindowSum` | `REAL` | OUT | 窗口累加和（诊断用）`[EU]` / Window sum for diagnostics `[EU]` |
| `bError` | `BOOL` | OUT | 故障标志，需 `bReset` 清除 / Fault flag, cleared by `bReset` |
| `uErrorId` | `UDINT` | OUT | `16#0001_0001` 窗口越界、`16#0001_0005` 非法状态 / `16#0001_0001` window clamp, `16#0001_0005` illegal state |
| `DL_MAV_MAX_WINDOW` | `INT` | CONST | `100`，窗口上限（与数组维度一致）/ Max window, matches the array size |
| `DL_MAV_CORRECT_CYCLE` | `DINT` | CONST | `10000`，每 N 次采样做一次全窗口重算 / Recalculation period in samples |

### 4.2 调用示例 / Example

```iecst
VAR
    fbPressureAvg : FB_DL_MovingAverage;   // 压力滤波实例 / Pressure filter instance
    fPressureRaw  : REAL;                  // 原始压力 [bar] / Raw pressure [bar]
    fPressureAvg  : REAL;                  // 滤波后压力 [bar] / Filtered pressure [bar]
    bAvgReady     : BOOL;                  // 窗口已填满 / Window filled
END_VAR

(* 放在固定周期任务中调用，采样节拍才恒定 / Call in a fixed-cycle task for a constant sample interval *)
fbPressureAvg(
    fInput      := fPressureRaw,
    nWindowSize := 20,       // 20 点窗口，滤波时间 = 20 × 采样周期 / 20-sample window
    bSample     := TRUE,     // 每周期采样；改为脉冲变量则按事件采样 / Sample every scan
    bEnable     := TRUE,
    bReset      := bResetFilter );

fPressureAvg := fbPressureAvg.fAverage;
bAvgReady    := fbPressureAvg.bBufferFull;
```

### 4.3 采样语义 / Sampling Semantics（重要）

**本组件不设采样沿实例**（这是对 `ROUND_PLAN` §2.13 VAR 清单的刻意收窄，依据 §2.13 B7 与决策 P6）：

| 接法 / Wiring | 行为 / Behaviour |
|---|---|
| `bSample := TRUE`（常 TRUE） | 每扫描周期采样一次 / Samples once per scan |
| `bSample := bPulse`（脉冲变量） | 脉冲为 `TRUE` 的那个周期采样 / Samples on scans where the pulse is `TRUE` |

若强行用 `R_TRIG` 承担两种语义，常 `TRUE` 信号经 `R_TRIG` 只会在首周期产生一次脉冲，导致「整个窗口只采到一个样本」的低级事故。

### 4.4 两阶段启动 / Two-Phase Startup

| 阶段 / Phase | 判据 / Condition | 动作 / Action |
|---|---|---|
| 填充态 `eFilling` | `bBufferFull = FALSE` | 只「写入 + 累加 + 计数」，**绝不减最旧值** / Append, accumulate and count only, **never evict** |
| 运行态 `eRunning` | `bBufferFull = TRUE` | 「减最旧 + 加最新 + 指针递增」/ Evict the oldest, add the newest, advance the pointer |

若在未满阶段也执行「减最旧值」，会减掉尚未写入的 0，输出被系统性压低，表现为上电初期滤波值比原始信号更抖——即经典的两阶段缺陷。

### 4.5 要点 / Notes

- **相位滞后** ≈ `(N-1)/2` 个采样周期，滤波时间窗 = `N × 采样周期`；联锁回路禁止使用大窗口滤波值。
- **窗口运行时变更即重建**：`nWindowSize` 变化会清空缓冲、指针与累加和，重走填充阶段，避免新旧窗口样本混算产生台阶。
- **浮点漂移校正**：每 `DL_MAV_CORRECT_CYCLE` 次采样做一次全窗口重算，循环带迭代上限与 `EXIT`。
- **断电保持**：缓冲区、指针、累加和、已填充数若不设 `RETAIN`，重新上电会重走填充阶段，表现为输出从 0 缓慢爬升。
- **除零双保险**：窗口钳位保证 `nWindowSize ≥ 1`，输出时再以 `nFilled > 0` 兜底。

---

## 5. FC_DL_Crc16Modbus ｜ Modbus RTU CRC-16

**定位**：标准 Modbus RTU CRC-16（多项式 `0xA001`、初值 `0xFFFF`、输入输出反射、结果无异或）逐位计算，提供定长缓冲区接口与长度防御。

### 5.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `abyData` | `ARRAY[0..255] OF BYTE` | IN_OUT | 报文缓冲区，定长 256 字节，按 `uByteCount` 取前 N 字节 / Fixed 256-byte frame buffer; the first `uByteCount` bytes are used |
| `uByteCount` | `UINT` | IN | 参与校验的字节数 1..256，默认 `0` / Byte count 1..256, default `0` |
| `bValid` | `BOOL` | OUT | 长度合法标志；`FALSE` 表示为零或已钳位 / Length valid flag; `FALSE` means zero or clamped |
| `uErrorId` | `UDINT` | OUT | 长度非法返回 `16#0001_0001` / `16#0001_0001` on illegal length |
| 返回值 / Return | `WORD` | RET | CRC 寄存器值；异常路径返回 `16#FFFF`（初值）/ CRC register value; `16#FFFF` on error paths |
| `DL_CRC16_POLY` | `WORD` | CONST | `16#A001` 反射多项式 / Reflected polynomial |
| `DL_CRC16_INIT` | `WORD` | CONST | `16#FFFF` Modbus 规定初值 / Modbus initial value |
| `DL_CRC16_MAXLEN` | `UINT` | CONST | `256`，与数组维度一致 / Matches the array dimension |

### 5.2 调用示例 / Example

```iecst
VAR
    abyFrame   : ARRAY[0..255] OF BYTE;   // 发送帧缓冲 / TX frame buffer
    uCrcReg    : WORD;                    // CRC 寄存器值 / CRC register value
    nFrameLen  : UINT;                    // 有效字节数（不含 CRC）/ Payload length excluding CRC
END_VAR

(* 1. 组帧：从站地址 + 功能码 + 起始地址 + 数量 *)
abyFrame[0] := 16#01;   // 从站地址 / Slave address
abyFrame[1] := 16#03;   // 读保持寄存器 / Read holding registers
abyFrame[2] := 16#00;
abyFrame[3] := 16#00;
abyFrame[4] := 16#00;
abyFrame[5] := 16#02;   // 读 2 个寄存器 / Read 2 registers
nFrameLen   := 6;

(* 2. 计算 CRC *)
uCrcReg := FC_DL_Crc16Modbus(abyData := abyFrame, uByteCount := nFrameLen);

(* 3. 拼帧：低字节先发，高字节后发 / Append CRC, low byte first *)
abyFrame[nFrameLen]     := WORD_TO_BYTE(uCrcReg AND 16#00FF);
abyFrame[nFrameLen + 1] := WORD_TO_BYTE(SHR(uCrcReg, 8) AND 16#00FF);
```

### 5.3 验收向量 / Acceptance Vectors（已实算复核）

| # | 输入 / Input | CRC 寄存器 / Register | 发送顺序 / Wire order |
|---|---|---|---|
| V1 | `01 03 00 00 00 02` | `16#0BC4` | `C4 0B` |
| V2 | `01 03 00 00 00 0A` | `16#CDC5` | `C5 CD` |
| V3 | `11 03 00 6B 00 03` | `16#8776` | `76 87` |
| V4 | 单字节 `0x0C` | `16#45BF` | `BF 45` |

> **勘误说明 / Erratum**：`ROUND_PLAN` §2.14 B7 原文给出的单字节向量「`0x0C` → `0x911E`」无法复现——穷举 `0..255` 全部单字节输入，无任何取值得到 `0x911E`，该值应源自其它多项式或其它初值的变体。本实现采用实算复核过的 V4（`0x0C → 0x45BF`）作为单字节验收基准，代码头注释已留档，详见 `AGENT_EVOLUTION_LOG.md` 与 `BATTLE_REPORT.md`。

### 5.4 要点 / Notes

- **顺序硬约束**：先取最低位 → 再右移 → 最后按标志异或多项式。顺序写反是最常见的实现错误。
- 移位必须用 `SHR(uCrc, 1)`，禁止 `/ 2`：整数除法在不同平台对无符号/有符号的处理有差异。
- 字节进 CRC 必须显式 `BYTE_TO_WORD()`，禁止隐式提升。
- 长度为零返回 `16#FFFF` 而非 `0`：`0` 在数学上是合法 CRC 值，返回它会让上层把「没算」误判成「算对了」。
- 长度超限钳到 256 后**继续计算**，便于现场边通信边排错。
- 首版只有逐位法；查表法（256 项常量数组）的跨平台初始化行为待验证，列入 `ROADMAP.md`。

---

## 6. FC_DL_SwapBytes16 ｜ 16 位字高低字节互换

**定位**：字节序家族的最小原子。既独立服务 Profibus / 串口仪器的单寄存器字节序需求，也是理解 32 位四排布（第 7 节）的入口。纯函数、自逆：换两次等于原值。

### 6.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `uValue` | `WORD` | IN | 原始 16 位字 / Source word |
| 返回值 / Return | `WORD` | — | 高低字节互换结果 / Byte-swapped result |

> 本函数**无 `uErrorId` 引脚**：16 位互换在全定义域有效，不存在非法输入与失败路径，沿用 `FC_DL_PackBitsToWord` 的 P3 豁免先例。

### 6.2 验收向量 / Acceptance Vector

`16#1A2B` → `16#2B1A`；再换一次 `16#2B1A` → `16#1A2B`（自逆，全字域成立）。

### 6.3 调用示例 / Example

```iecst
uStatusWord := FC_DL_SwapBytes16(uRawFromProfibus);
```

### 6.4 要点 / Notes

- **纯移位实现**：`SHL(uValue AND 16#00FF, 8) OR SHR(uValue, 8)`，不使用任何字节访问方言，三平台语义一致。
- **不要用于 32 位量**：32 位量请用第 7 节，按寄存器排布声明，否则会把字序与字节序两件事混在一起。

---

## 7. FC_DL_SwapBytes32 ｜ 32 位量四排布归一化

**定位**：Modbus 多寄存器量「读回 1e38 天文数字」的唯一系统性解药。语义锁定为**声明原始排布 → 输出 ABCD 归一化值**，不做目标排布选择（需要反向时以对称排布重新声明即可，见 7.3）。

### 7.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `uRaw` | `DWORD` | IN | — | 通信侧原始 32 位拼接值 / Raw 32-bit value from comms |
| `eRawOrder` | `E_DL_ByteOrder` | IN | `eAbcd` | 声明原始值所属排布 / Declared layout of the raw value |
| 返回值 / Return | `DWORD` | — | — | ABCD 归一化值 / Normalised ABCD value |
| `bValid` | `BOOL` | OUT | — | 排布枚举合法标志 / Layout enum valid |
| `uErrorId` | `UDINT` | OUT | — | 故障码 / Error code |

枚举 `E_DL_ByteOrder`：`eAbcd := 0`（大端大字，直通）、`eDcba := 1`（四字节全反序）、`eBadc := 2`（两寄存器内部各自字节互换）、`eCdab := 3`（高低字交换）。

### 7.2 验收向量 / Acceptance Vectors（已复算）

以 `uRaw = 16#12345678`（A=`16#12`、B=`16#34`、C=`16#56`、D=`16#78`）为基准：

| 声明排布 / Declared | 输出 / Output | 说明 / Note |
|---|---|---|
| `eAbcd` | `16#12345678` | 原值直通 / pass-through |
| `eDcba` | `16#78563412` | D C B A / full byte reverse |
| `eBadc` | `16#34127856` | B A D C / swap within each register |
| `eCdab` | `16#56781234` | C D A B / word swap |

**四种排布互为对合（involution）**：对同一排布再转一次即还原原值，这正是「反向转换无需第二个方向参数」的结构性依据。

### 7.3 四排布 4×4 复合矩阵 / 4×4 Composition Matrix

行 = 第一次声明的排布 `O1`，列 = 第二次声明的排布 `O2`（把第一次的输出当作原始值再声明为 `O2`）；表内为**复合结果等价于按哪一种排布转换一次**。

| O1 \ O2 | ABCD | DCBA | BADC | CDAB |
|---|---|---|---|---|
| **ABCD** | ABCD（还原） | DCBA | BADC | CDAB |
| **DCBA** | DCBA | ABCD（还原） | CDAB | BADC |
| **BADC** | BADC | CDAB | ABCD（还原） | DCBA |
| **CDAB** | CDAB | BADC | DCBA | ABCD（还原） |

**读法与结论**：

1. **对角线全部还原**：`f(f(v, O), O) = v`，四种排布都是自逆映射，这就是「互逆矩阵」的对角线。
2. **非对角线不还原**：两次不同排布叠加等于第三个排布，绝不会意外还原——所以「先按 CDAB 归一化、再按 BADC 声明」这类串联操作是可预测的，不会出现「碰巧对了」的偶发现象。
3. **群结构（复算结论）**：四个排布在同构意义下构成 Klein 四元群，复合规则等价于枚举值的按位异或：`f(f(v, O1), O2) = f(v, O1 XOR O2)`（枚举值 0~3）。实测 2000 组随机 32 位值 × 16 种组合全部成立。工程含义：**排布枚举不是随便编的序号，而是两个独立比特（字节内互换 / 字交换）的组合**，HMI 上可以用两个复选框直接映射。

### 7.4 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_000E` | `eRawOrder` 被写入枚举域外值 / Layout enum out of domain | 返回原值（`bValid = FALSE`）；检查 HMI 排布配置项的下标映射 |

### 7.5 调用示例 / Example

```iecst
VAR
    uRawPower  : DWORD;
    uNormPower : DWORD;
    bPowerValid: BOOL;
    uErr       : UDINT;
END_VAR

uNormPower := FC_DL_SwapBytes32(
    uRaw      := uRawPower,
    eRawOrder := E_DL_ByteOrder.eCdab,   // 电表实测为 CDAB / measured as CDAB
    bValid    => bPowerValid,
    uErrorId  => uErr
);
```

### 7.6 要点 / Notes

- **异常路径返回原值，不返回 0**：0 对浮点量是合法灾难值（`0x00000000` 是 `0.0`），原值直通是最安全的确定值。
- **不做 `DWORD` → `REAL` 重解释**：各平台浮点拼接规则存在差异，本层只交付归一化 `DWORD`，转浮点由调用方按其平台口径完成。
- **只有移位与掩码**：字节提取用 `SHR + AND`，重装用 `SHL + OR`，无切片、无指针重叠、无字节访问方言。
- **排查手法**：现场遇到天文数字，先把上电值按四种排布各转一次、用 `DWORD_TO_REAL` 看哪个落在量程内，再回填 `eRawOrder`——比反复下载试参数快得多。

---

## 8. FB_DL_RingBufferLReal ｜ 定长环形队列（LREAL）

**定位**：定长 64 的 LREAL FIFO，压入 / 弹出 / 窥视 / 清空全部 O(1)，用于「故障前最后 N 条采样」追溯。容量固定不参数化，指针纯前向取模，全组件不存在指针减法。

### 8.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `fPushValue` | `LREAL` | IN | 待压入值 [EU] / Value to push |
| `bPush` | `BOOL` | IN | 上升沿压入 / Push on rising edge |
| `bPop` | `BOOL` | IN | 上升沿弹出 / Pop on rising edge |
| `bClear` | `BOOL` | IN | 电平清空，最高优先级 / Level-triggered clear, highest priority |
| `fPopValue` | `LREAL` | OUT | 最近一次弹出值，空队弹出被拒时保持 / Last popped value |
| `fPeekValue` | `LREAL` | OUT | 队首值（不弹出），空队为 `0.0` 哨兵 / Front value, `0.0` sentinel when empty |
| `uCount` | `UINT` | OUT | 当前元素数 0..64 / Current element count |
| `bFull` | `BOOL` | OUT | 已满标志 / Full flag |
| `bEmpty` | `BOOL` | OUT | 已空标志 / Empty flag |
| `uErrorId` | `UDINT` | OUT | 故障码 / Error code |

### 8.2 回绕验收序列 / Wrap-Around Vector（已复算）

| 步 / Step | 操作 / Action | `uCount` | `bFull` | `bEmpty` | `uErrorId` | 说明 / Note |
|---|---|---|---|---|---|---|
| 1 | `bClear` 一拍 | 0 | FALSE | TRUE | 0 | 双指针归零 / pointers reset |
| 2 | 连续压入 1..64（64 拍） | 64 | TRUE | FALSE | 0 | 写指针回绕到 0 / write pointer wrapped |
| 3 | 第 65 次压入 | 64 | TRUE | FALSE | `16#0001_0009` | **拒绝写入，不覆盖最旧值** / rejected, oldest kept |
| 4 | 弹出 1 次 | 63 | FALSE | FALSE | 0 | `fPopValue` = 第 1 个压入值 / FIFO order kept |
| 5 | 再压入 1 次 | 64 | TRUE | FALSE | 0 | 计数回到满，队首不变 |
| 6 | 连续弹出 64 次 | 0 | FALSE | TRUE | 0 | 顺序严格 FIFO；第 65 次弹出报 `16#0001_000A` |

### 8.3 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0009` | 缓冲已满，写入被拒绝 / Buffer full | 调用方需先 `bPop` 再 `bPush`；或接受丢新数据（本块不覆盖旧值） |
| `16#0001_000A` | 缓冲已空，读取被拒绝 / Buffer empty | `fPopValue` 保持上次值；判空请用 `bEmpty`，不要用 `fPeekValue = 0.0` |

### 8.4 调用示例 / Example

```iecst
VAR
    fbTrace : FB_DL_RingBufferLReal;
    fTemp   : LREAL;
    bSample : BOOL;                      // 100 ms 采样脉冲 / 100 ms sample pulse
END_VAR

fbTrace(fPushValue := fTemp, bPush := bSample AND NOT bTraceFullStop,
        bPop := bPopReq, bClear := bTraceClear);

IF fbTrace.uCount >= 60 THEN
    bTraceReady := TRUE;                 // 够 60 条即可转存 / enough samples to dump
END_IF
```

### 8.5 要点 / Notes

- **满时拒写、不覆盖**：FIFO 语义要求「丢数据必须显式可见」。需要覆盖式行为的调用方自己先 `bPop` 再 `bPush`。
- **`0.0` 是哨兵不是数据**：空队 `fPeekValue = 0.0`，判空必须看 `bEmpty`。
- **`bClear` 是电平、最高优先级**：清空与压入同周期时结果确定为「压入一个元素」，不存在歧义。
- **同周期压弹顺序不可交换**：先压后弹（净效果是换出队首）。
- **内存口径**：64 × 8 B = 512 B 存储，加指针与两个边沿实例约 0.6 KB/实例，不要为大范围历史各开一份实例。

---

## 9. FC_DL_StringTrim ｜ 首尾空白清理

**定位**：扫码枪、CSV 报文、视觉结果字符串的前置清洗步。只去首尾四类空白，串中间的空白保留。

### 9.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `sIn` | `STRING(255)` | IN | 原始字符串 / Source string |
| 返回值 / Return | `STRING(255)` | — | 去空白后的字符串 / Trimmed string |
| `bValid` | `BOOL` | OUT | 处理完整标志，`FALSE` = 循环保护触发 / Complete flag |
| `uTrimmed` | `UINT` | OUT | 被去除的空白字符总数 / Whitespace characters removed |
| `uErrorId` | `UDINT` | OUT | 故障码 / Error code |

### 9.2 验收向量 / Acceptance Vector（已复算）

| 输入 / Input（`$` 转义） | 输出 / Output | `uTrimmed` |
|---|---|---|
| `'  AB$09CD  '` | `'AB$09CD'` | 4（前 2 空格 + 后 2 空格，中间制表符保留） |
| `'$0D$0A'` | `''` | 2 |
| `''` | `''` | 0 |
| `'ABC'` | `'ABC'` | 0 |

### 9.3 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0004` | 循环防死锁计数触发（理论上不可达）/ Loop guard tripped | 记录并上报输入串长度；本路径按已得边界尽力返回 |

### 9.4 调用示例 / Example

```iecst
sBarcode := FC_DL_StringTrim(sIn := sRawScan, bValid => bTrimOk, uTrimmed => uCut);
```

### 9.5 要点 / Notes

- **空白集固定四类**：空格 `$20`、制表 `$09`、回车 `$0D`、换行 `$0A`，不扩充。全角空格等多字节字符属调用方预处理职责。
- **位置从 1 开始**：IEC 字符串函数口径，`LEN` 结果为有效长度。
- **全空白输入返回空串并 `bValid = TRUE`**：这是合法结果，不是错误。
- **显式 255 长度**：CODESYS 默认 `STRING` 是 80 字节，省略长度会被静默截断，本库统一 `STRING(255)`。

---

## 10. FC_DL_StringSplit ｜ 单字符分隔报文拆分

**定位**：CSV / 扫码枪 / 视觉结果报文拆分。CODESYS 与 TwinCAT 均无内置 SPLIT，「FIND 定位 → LEFT 取字段 → 工作副本 DELETE」是本库统一的解析范式。

### 10.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `sSource` | `STRING(255)` | IN | — | 待拆分报文 / Source message |
| `sDelimiter` | `STRING(1)` | IN | `','` | 单字符分隔符 / Single-character delimiter |
| `uMaxFields` | `INT` | IN | `16` | 最大输出字段数 1..16 / Max fields |
| `aFields` | `ARRAY[0..15] OF STRING(255)` | **IN_OUT** | — | 调用方持有的输出缓冲 / Caller-owned output buffer |
| 返回值 / Return | `INT` | — | — | 实际字段数 0..16 / Actual field count |
| `bValid` | `BOOL` | OUT | — | 拆分完整标志，`FALSE` = 截断 / Complete flag |
| `uErrorId` | `UDINT` | OUT | — | 故障码 / Error code |

### 10.2 验收向量 / Acceptance Vector（已复算）

`'LOT=A4471;QTY=0250;'` 按 `';'` 拆分 → 返回 `3`，字段为 `'LOT=A4471'`、`'QTY=0250'`、`''`（尾随分隔符产生一个空字段，CSV 语义，**不跳过**）。

`'A,,B'` 按 `','` 拆分 → 返回 `3`，字段为 `'A'`、`''`、`'B'`。

### 10.3 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | `uMaxFields` 越界（<1 或 >16），已钳位 / Max fields clamped | 检查配置；钳位后继续拆分 |
| `16#0001_0004` | 循环防死锁触发 / Loop guard tripped | 上报报文特征；按已完成字段数返回 |
| `16#0001_0008` | 分隔符长度 ≠ 1，拒绝拆分并返回 0 / Delimiter length illegal | 单字符语义锁定；多字符分隔请先规整报文 |
| `16#0001_000D` | 字段数超缓冲，剩余整段并入末字段并置截断 / Truncated | 调大 `uMaxFields` 或改协议；结果不静默丢弃 |

### 10.4 调用示例 / Example

```iecst
VAR
    asFields : ARRAY[0..15] OF STRING(255);   // 必须持久，且每次调用前清场 / persistent, cleared before use
    nFields  : INT;
    bSpOk    : BOOL;
    uSpErr   : UDINT;
END_VAR

nFields := FC_DL_StringSplit(sSource := sScanMsg, sDelimiter := ';', uMaxFields := 16,
                             aFields := asFields, bValid => bSpOk, uErrorId => uSpErr);

IF bSpOk AND (nFields >= 2) THEN
    sLot := asFields[0];
    sQty := asFields[1];
END_IF
```

### 10.5 要点 / Notes

- **`aFields` 必须传持久数组**：传临时变量或每周期新建数组，会出现「上次残留字段污染本次结果」，编译与运行都不报错——典型的「编译通过、逻辑全错」。
- **每次调用前自行清场**：本函数只写前 `nFields` 个槽位，不清理其余槽位。
- **连续分隔符产生空字段**：符合 CSV 语义，不跳过。这对「尾随分隔符」尤其重要：`'A;B;'` 是三字段，第三为空。
- **不修改输入串**：解析全程在内部工作副本上完成，`sSource` 保持原样。
- **内存口径**：16 × 256 B ≈ 4 KB，由调用方持有，注意别在多个工站重复声明。

## 11. FC_DL_MultiPointLinear ｜ 多段折线插值

**定位**：N 段折线查表线性插值（2..16 点，二分查找 O(log2 N)）。用于热电偶分度表、异形卧式罐液位、流量计非线性修正、阀门特性补偿等「两点直线表达不了」的标定场景。输出命中段号与外推/钳位标志。

### 11.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `afX` | `ARRAY[0..15] OF LREAL` | IN_OUT | — | 折点自变量表，**须严格递增**（上限 16 点）/ Breakpoint X table, strictly increasing |
| `afY` | `ARRAY[0..15] OF LREAL` | IN_OUT | — | 折点因变量表 [EU] / Breakpoint Y table [EU] |
| `fIn` | `LREAL` | IN | — | 输入值 [EU] / Input value |
| `nCount` | `INT` | IN | — | 有效折点数，合法域 2..16 / Valid point count |
| `bClamp` | `BOOL` | IN | `TRUE` | TRUE = 区间外钳位，FALSE = 端点段线性外推 / Clamp or extrapolate |
| `nSegment` | `INT` | OUT | — | 命中段号 0..nCount-2，-1 = 无效 / Segment index |
| `bExtrapolated` / `bClamped` | `BOOL` | OUT | — | 来自外推 / 被钳位标志 / Extrapolated / clamped flags |
| `uErrorId` | `UDINT` | OUT | — | 故障码 / Error code |
| 返回值 / Return | `LREAL` | RET | — | 插值结果 [EU]；表非法时为 `afY[0]` / Result; `afY[0]` on illegal table |

### 11.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 点数越界（<2 或 >16），拒绝计算 / Point count invalid | 检查配方表长度 |
| `16#0002_000B` | **折线表非法：X 非严格递增，整表拒绝** / Table not strictly increasing | 修正折点；整表拒绝是刻意的，不做局部修补 |

### 11.3 调用示例 / Example

```iecst
VAR
    aThcX : ARRAY[0..15] OF LREAL := [0.0, 500.0, 1200.0, 2500.0];   // 折点 X [degC] / X breakpoints
    aThcY : ARRAY[0..15] OF LREAL := [0.0, 2.585, 6.204, 12.12];     // 折点 Y [mV] / Y breakpoints
    fMv   : LREAL;                                                   // 实测毫伏 [mV] / measured mV
    nSeg  : INT;
    uErr  : UDINT;
END_VAR

fDegC := FC_DL_MultiPointLinear(
    fIn     := fMv,
    afX     := aThcX,
    afY     := aThcY,
    nCount  := 4,                  // 实际折点数 / actual breakpoints
    bClamp  := TRUE,
    nSegment => nSeg,
    uErrorId => uErr );
```

### 11.4 要点 / Notes

- **表非法返回 `afY[0]` 而不是 0.0**：0.0 在液位/温度场景会被当成真实测量值参与联锁；`afY[0]` 至少落在量程内。
- **外推默认关闭**：传感器断线时 0 mA 会被外推放大成负温度，要用外推必须显式 `bClamp := FALSE` 并留档理由。
- **重复折点 = 除零根因**：整表拒绝而非跳过坏点——「斜率错误却看起来正常」比直接报错危险得多。

---

## 12. FC_DL_PolygonArea ｜ 多边形面积与质心

**定位**：平面多边形有向面积、绝对面积与质心坐标（鞋带公式离散形式），LREAL 运算。用于视觉定位的料框有效面积、零件轮廓校验、机器人平面抓取中心计算。返回值即绝对面积，绕向经 `bCcw` 输出。

### 12.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `afX` / `afY` | `ARRAY[0..31] OF LREAL` | IN_OUT | — | 顶点坐标 [mm]，**末点不重复首点**（上限 32 点）/ Vertices, not closed |
| `nCount` | `INT` | IN | — | 顶点数，合法域 3..32（超上限向下钳位）/ Vertex count |
| `fCentroidX` / `fCentroidY` | `LREAL` | OUT | — | 质心 [mm]，退化时回退顶点算术平均 / Centroid, vertex mean on degenerate |
| `bCcw` | `BOOL` | OUT | — | TRUE = 逆时针（右手系）/ Counter-clockwise |
| `bDegenerate` | `BOOL` | OUT | — | TRUE = 退化（点数 < 3、共线或零面积）/ Degenerate polygon |
| `uErrorId` | `UDINT` | OUT | — | 故障码 / Error code |
| 返回值 / Return | `LREAL` | RET | — | 绝对面积 [mm²] / Absolute area |

### 12.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 顶点数超 32，已向下钳位 / Vertex count clamped | 检查轮廓来源 |
| `16#0002_000C` | **退化：顶点数 < 3 或零面积** / Degenerate polygon | 质心已回退顶点均值；检查视觉轮廓输出 |

### 12.3 调用示例 / Example

```iecst
VAR
    aVx  : ARRAY[0..31] OF LREAL;   // 视觉轮廓顶点 X [mm] / contour X
    aVy  : ARRAY[0..31] OF LREAL;   // 顶点 Y [mm] / contour Y
    fArea: LREAL;
    fCx  : LREAL;
    fCy  : LREAL;
    bCw  : BOOL;
    uErr : UDINT;
END_VAR

fArea := FC_DL_PolygonArea(
    afX        := aVx,
    afY        := aVy,
    nCount     := 8,               // 8 顶点轮廓 / 8-vertex contour
    fCentroidX => fCx,             // 抓取中心 / pick centre
    fCentroidY => fCy,
    bCcw       => bCw,
    uErrorId   => uErr );
```

### 12.4 要点 / Notes

- **必须用 LREAL**：32 点 × 1e6 mm 坐标的叉积累加可达 1e12，REAL 在该量级丢 5 位有效数字。
- **自交多边形无几何意义**：鞋带公式返回代数面积（正负抵消），视觉轮廓应先按角度排序并去重。
- **末点不重复首点**：重复传入首点面积仍正确但质心偏移；检测办法是首末点距离 < eps 时把 `nCount` 减 1。
- **退化质心回退顶点均值而非 (0,0)**：(0,0) 会让机器人朝原点狂奔。

---

## 13. FC_DL_LineIntersection ｜ 两直线交点

**定位**：二维两直线（或两线段）交点求解，返回「是否存在唯一交点」+ 交点坐标 + 两条线段参数。用于视觉十字标定、皮带跑偏中心线求交、两台相机视场交叠区定位。

### 13.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `fX1` / `fY1` ~ `fX4` / `fY4` | `LREAL` | IN | — | mm | 线 1 起点/终点、线 2 起点/终点坐标 / Line endpoints |
| `fEps` | `LREAL` | IN | `1.0E-9` | — | 平行判定容差，**须按坐标量级配置**（经验式 ≈ 1e-9 × 量级²）/ Parallel tolerance |
| `bSegmentMode` | `BOOL` | IN | `FALSE` | — | TRUE = 按线段求交，交点须落在两段内 / Segment mode |
| `fX` / `fY` | `LREAL` | OUT | — | mm | 交点坐标，无交点时显式清 0 / Intersection |
| `fT` / `fU` | `LREAL` | OUT | — | — | 线 1 / 线 2 参数，0 = 起点、1 = 终点 / Line parameters |
| `uErrorId` | `UDINT` | OUT | — | — | 故障码 / Error code |
| 返回值 / Return | `BOOL` | RET | — | — | 存在唯一交点 / Unique intersection exists |

### 13.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 起终点重合（零长度线）或容差非法，已规整 / Degenerate line or bad tolerance | 检查标定配置 |
| `16#0002_000D` | **两线重合（共线），无唯一交点** / Coincident lines | 无穷多交点无法用单点表达；线段模式「平行不共线」返回 FALSE 且不置码（正常判定） |

### 13.3 调用示例 / Example

```iecst
VAR
    bHit : BOOL;                    // 是否有唯一交点 / unique intersection
    fIx  : LREAL;                   // 交点 X [mm] / intersection X
    fIy  : LREAL;                   // 交点 Y [mm]
    uErr : UDINT;
END_VAR

bHit := FC_DL_LineIntersection(
    fX1 := 0.0,   fY1 := 0.0,      // 线 1 / line 1
    fX2 := 100.0, fY2 := 50.0,
    fX3 := 0.0,   fY3 := 50.0,     // 线 2 / line 2
    fX4 := 100.0, fY4 := 0.0,
    fEps := 1.0E-3,                // 坐标量级 1e2 → 容差 1e-3 / scale-aware eps
    fX  => fIx, fY => fIy,
    uErrorId => uErr );
```

### 13.4 要点 / Notes

- **线段模式返回 FALSE 且 `uErrorId = 0` 是正常判定**：业务上的「两段不相交」不是故障；只有重合（共线）才报码。
- **容差必须随坐标量级放大**：坐标量级 1e6 时行列式可达 1e12，用 1e-9 去判等于把平行判据关掉。
- **无交点时输出显式清 0**：部分平台 FC 局部变量不保证每拍复位，靠默认值会让上一次的交点粘住。

---

## 14. FC_DL_Crc32Ethernet ｜ CRC-32（以太网 FCS）

**定位**：CRC-32/ISO-HDLC 逐位计算（反射多项式 `16#EDB88320`、初值与终值异或均为 `16#FFFF_FFFF`），即以太网 FCS、ZIP、PNG 使用的同一参数模型。支持分块链式调用。用于固件包完整性校验、文件传输校验、EtherCAT/Profinet 诊断帧签核。

### 14.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `aabyData` | `ARRAY[0..255] OF BYTE` | IN_OUT | — | 待校验字节缓冲，定长 256，按 `nLength` 取前 N 字节 / Data buffer |
| `nLength` | `INT` | IN | — | 本次参与计算的字节数，合法域 0..256，越界自动钳位 / Byte count, clamped |
| `uCrcSeed` | `DWORD` | IN | `16#FFFF_FFFF` | 初值或上一分块返回值（链式调用）/ Seed or previous chunk result |
| `bFinalXor` | `BOOL` | IN | `TRUE` | TRUE = 输出前异或终值，**仅最后一块置 TRUE** / Final XOR on last chunk only |
| `nBytesUsed` | `INT` | OUT | — | 钳位后实际参与计算的字节数 / Bytes actually processed |
| `uErrorId` | `UDINT` | OUT | — | `16#0001_0001` = 长度越界已钳位 / Error code |
| 返回值 / Return | `DWORD` | RET | — | CRC-32 值 / CRC-32 value |

### 14.2 验收向量 / Acceptance Vectors（已实算复核）

| # | 输入 / Input | 结果 / Result |
|---|---|---|
| V1 | `"123456789"`，默认参数 | `16#CBF4_3926` |
| V2 | 空输入（`nLength = 0`） | `16#0000_0000`（正确值，非错误） |
| V3 | 单字节 `00` | `16#D202_EF8D` |
| V4 | 分块链式 `"1234"`（FALSE）+ `"56789"`（TRUE） | `16#CBF4_3926`，与 V1 一致 |

### 14.3 调用示例 / Example

```iecst
VAR
    abyFw   : ARRAY[0..255] OF BYTE;    // 固件分块 / firmware chunk
    uCrc    : DWORD;
    uSeed   : DWORD := 16#FFFF_FFFF;
END_VAR

(* 分块链式：中间块 bFinalXor := FALSE，返回值作下一块种子 / chunk chaining *)
uCrc := FC_DL_Crc32Ethernet(aabyData := abyFw, nLength := 256,
                            uCrcSeed := uSeed, bFinalXor := FALSE);
uSeed := uCrc;   // 传给下一块 / pass to next chunk

(* 最后一块：bFinalXor := TRUE，返回值即整包 CRC / final chunk *)
uCrc := FC_DL_Crc32Ethernet(aabyData := abyFw, nLength := 80,
                            uCrcSeed := uSeed, bFinalXor := TRUE);
```

### 14.4 要点 / Notes

- **反射多项式配右移**：必须用 `16#EDB88320` + 右移；`16#04C11DB7` + 左移得到的是 CRC-32/BZIP2（"123456789" → `16#FC891918`），混搭是 CRC 实现第一大错。
- **链式契约**：中间块误置 `bFinalXor := TRUE` 相当于整体多异或一次终值，整包校验必失败且极难定位。
- **重计算，放慢任务**：256 字节 = 2048 次内层循环，不要放进 1 ms 高速任务。
- **以太网 FCS 上帧按小端填帧尾**：拆字节与摆放顺序由组帧方决定，本函数只算数值。

---

## 15. FC_DL_LrcChecksum ｜ Modbus ASCII LRC

**定位**：Modbus ASCII 模式纵向冗余校验：地址 + 功能码 + 数据字节按无符号 8 位累加，取补码（256 − 低 8 位和）。用于电表、称重仪表、老式温控器等仍走 ASCII 模式设备的收帧校验。与 `FC_DL_HexStringToBytes` 组成「先解码、后校验」两步收帧链。

### 15.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `aabyData` | `ARRAY[0..255] OF BYTE` | IN_OUT | — | **解码后**的报文字节（不含冒号与 CR/LF）/ Decoded payload, framing excluded |
| `nLength` | `INT` | IN | — | 字节数，合法域 0..256，越界自动钳位 / Byte count |
| `uSumLow` | `BYTE` | OUT | — | 累加和低 8 位（诊断用，LRC = 其补码）/ Low byte of the sum |
| `uErrorId` | `UDINT` | OUT | — | `16#0001_0001` = 长度越界已钳位 / Error code |
| 返回值 / Return | `BYTE` | RET | — | LRC 校验值 / LRC value |

### 15.2 验收向量 / Acceptance Vectors（已实算复核）

| # | 输入 / Input | 分解 / Breakdown | LRC |
|---|---|---|---|
| V1 | `01 03 00 00 00 01` | 和 = `16#05` | `16#FB` |
| V2 | `01 03 02 12 34` | 和 = `16#4C` | `16#B4` |
| V3 | 空报文 | 和 = `16#00` | `16#00`（正确值，非错误） |
| V4 | `FF FF` | 和低 8 位 = `16#FE` | `16#02` |

### 15.3 调用示例 / Example

```iecst
VAR
    abyBody  : ARRAY[0..255] OF BYTE;   // 解码后报文体 / decoded body
    uLrc     : BYTE;
    uSumDiag : BYTE;
    uErr     : UDINT;
END_VAR

(* 第一步：FC_DL_HexStringToBytes 解码（剥帧）；第二步：本函数校验 / two-step chain *)
uLrc := FC_DL_LrcChecksum(aabyData := abyBody, nLength := 6,
                          uSumLow => uSumDiag, uErrorId => uErr);

IF uLrc <> uLrcReceived THEN
    bFrameRejected := TRUE;             // 校验失败拒收 / reject frame
END_IF
```

### 15.4 要点 / Notes

- **冒号与 CR/LF 不参与计算**：误把帧头帧尾算进累加和是现场 LRC 对不上的第一原因。
- **必须传解码后字节**：误传 ASCII 字符码（'0' = `16#30` 而非 `16#00`）时累加和整体偏移，校验恒失败。
- **LRC 与 CRC-16 不可互算互验**：ASCII 模式用 LRC、RTU 模式用 CRC，切换模式时校验字段同时变。
- **空报文 LRC = `16#00` 是正确值**：本函数返回值允许为 0，与 CRC 族「返回值不得用 0 判错」的约定不同。

---

## 16. FB_DL_LifoStack ｜ LIFO 栈

**定位**：定长 64 深度 LIFO（后进先出），压栈/弹栈/窥视/清空四操作全 O(1)，无元素搬移。带上溢/下溢锁存与单调累计计数。用于工艺路径回溯、嵌套配方解析、报警确认的「撤销」语义。满栈压入拒绝且不覆盖栈底——LIFO 无「丢最旧」语义，静默覆盖会让路径回溯错位一格。

### 16.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `bPush` | `BOOL` | IN | — | 上升沿压入 / Push on rising edge |
| `fPushValue` | `LREAL` | IN | `0.0` | 待压入值 [EU] / Value to push |
| `bPop` | `BOOL` | IN | — | 上升沿弹出栈顶 / Pop on rising edge |
| `bPeek` | `BOOL` | IN | — | TRUE：`fTop` 输出当前栈顶（不改变栈）/ Peek top |
| `bClear` | `BOOL` | IN | — | TRUE：清空栈与锁存（**保留累计计数**）/ Clear, counters kept |
| `bEnable` | `BOOL` | IN | `TRUE` | 使能，FALSE 时禁止入栈/出栈 / Enable |
| `fTop` | `LREAL` | OUT | — | 栈顶值 [EU]，空栈为 0.0 哨兵 / Top value |
| `fPopValue` | `LREAL` | OUT | — | 本次弹出值，未弹出当拍清 0 / Popped value |
| `nCount` | `INT` | OUT | — | 当前深度 0..64 / Current depth |
| `bEmpty` / `bFull` | `BOOL` | OUT | — | 空栈 / 满栈标志 / Empty / full flags |
| `bOverflow` / `bUnderflow` | `BOOL` | OUT | — | 上溢 / 下溢锁存 / Latched overflow / underflow |
| `uPushCount` / `uPopCount` | `UDINT` | OUT | — | 累计成功压栈 / 弹栈次数（饱和）/ Total pushes / pops |
| `bError` / `uErrorId` | `BOOL` / `UDINT` | OUT | — | 故障标志与故障码 / Fault flag and code |
| `eState` | `E_DL_StackState` | OUT | — | `eEmpty(0)` / `eReady(10)` / `eFault(99)` / State |

### 16.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0009` | **上溢：满栈压入被拒，不覆盖栈底** / Overflow: push rejected | 调用方先 `bPop` 释放；锁存至 `bClear` |
| `16#0001_000A` | **下溢：空栈弹出被拒** / Underflow: pop rejected | 判空用 `bEmpty`；锁存至 `bClear` |

### 16.3 调用示例 / Example

```iecst
VAR
    fbPath   : FB_DL_LifoStack;         // 工位路径回溯栈 / station path stack
    fStation : LREAL;                   // 工位编号（编码为数值）/ station id
    bArrive  : BOOL;                    // 到站沿 / arrival edge
END_VAR

(* 到站压栈；离站按原路回溯弹出 / push on arrival, pop to retrace *)
fbPath(bPush := bArrive, fPushValue := fStation,
       bPop := bRetraceReq, bPeek := FALSE, bEnable := TRUE);

IF fbPath.bUnderflow THEN
    bRetraceDone := TRUE;               // 已回到起点 / back at origin
END_IF
```

### 16.4 要点 / Notes

- **同周期先压后弹**：压弹沿同拍出现时先压后弹（弹出的是刚压入值），这是「写入后立即读回校验」的用法，次序不可交换。
- **0.0 是哨兵不是数据**：判空必须看 `bEmpty` / `nCount`，不得以「栈顶等于 0」反推。
- **锁存纪律**：上溢/下溢码为锁存码，`bClear` 是唯一清锁存路径；清空保留累计计数（生命周期统计）。

---

## 17. FB_DL_MedianFilter ｜ 中值滤波

**定位**：滑动窗口中值滤波（窗口 3..15，强制奇数），对孤立脉冲干扰（变频器干扰、接触器拉弧、单次 AD 跳变）免疫——窗口内 1 个坏点被整体剔除，而均值滤波会把坏点摊到全窗。启动阶段不等装满即输出「已到样本」的中值，避免 PID 把启动期 0 误认为测量值。

### 17.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `fIn` | `REAL` | IN | — | 采样输入 [EU] / Sample input |
| `bSample` | `BOOL` | IN | `TRUE` | TRUE = 本拍采一个样本（给单周期脉冲即按需采样）/ Take one sample this scan |
| `nWindow` | `INT` | IN | `5` | 窗口长度，奇数 3..15，偶数自动加 1，越界钳位 / Window length, odd 3..15 |
| `bClear` | `BOOL` | IN | — | TRUE：清空窗口重新填充 / Clear and refill |
| `fMedian` | `REAL` | OUT | — | 中值输出 [EU] / Median output |
| `nFilled` | `INT` | OUT | — | 当前有效样本数 0..窗口长 / Valid sample count |
| `bValid` / `bWindowFull` | `BOOL` | OUT | — | 至少 1 个样本 / 窗口已满 / Valid / full flags |
| `uErrorId` | `UDINT` | OUT | — | 瞬时码，逐拍重算 / Transient code |
| `eState` | `E_DL_MedianState` | OUT | — | `eEmpty(0)` / `eFilling(10)` / `eReady(20)` / `eFault(99)` / State |

### 17.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 窗口越界或偶数（已奇数化），或窗口变更触发整窗重填 / Window clamped or changed | 偶数无唯一中值，强制加 1 变奇数是刻意的，绝不取「中间两个平均」 |

### 17.3 调用示例 / Example

```iecst
VAR
    fbMedW  : FB_DL_MedianFilter;       // 称重前端滤波 / weighing front-end filter
    fLoadcell : REAL;                   // 称重原始值 [kg] / raw loadcell [kg]
END_VAR

fbMedW(fIn := fLoadcell, bSample := bSample100ms, nWindow := 5, bClear := FALSE);

(* 启动期即有合理值：不等窗口装满 / usable median from the first samples *)
fWeightUsed := fbMedW.fMedian;
```

### 17.4 要点 / Notes

- **排序在副本上进行**：绝不原地排序环形窗——会打乱时间顺序，后续取「最近 N 个样本」取到错值。
- **偶数窗口强制加 1**：静默取「中间两个平均」会退化成均值，尖峰重新渗入。
- **选型公式**：窗口长度 ≥ 2 × 干扰持续采样数 + 1；干扰持续 ≥ 半窗宽时中值仍会被带偏。
- **窗口变更即整窗重填**：`nFilled` 归 0 重新累，配方切换时按此预期。

---

## 18. FB_DL_SignalStatistics ｜ 实时统计七元组

**定位**：滑动窗口（2..64）实时输出均值、最小、最大、峰峰值、样本方差、样本标准差、样本数。用于 PID 整定前噪声评估、SPC 过程能力分析、称重稳定性判定、振动烈度监视。方差用**两遍法**防灾难性抵消。

### 18.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `fIn` | `REAL` | IN | — | EU | 采样输入 / Sample input |
| `bSample` | `BOOL` | IN | `TRUE` | — | TRUE = 本拍采一个样本 / Take one sample this scan |
| `nWindow` | `INT` | IN | `32` | 个 | 窗口长度 2..64，越界自动钳位 / Window length |
| `bClear` | `BOOL` | IN | — | — | TRUE：清空窗口重新统计 / Clear and restart |
| `fMean` / `fMin` / `fMax` / `fRange` | `REAL` | OUT | — | EU | 均值 / 最小 / 最大 / 峰峰值 / Statistics |
| `fVariance` | `REAL` | OUT | — | EU² | 样本方差（n−1 分母）/ Sample variance |
| `fStdDev` | `REAL` | OUT | — | EU | 样本标准差 / Sample standard deviation |
| `nCount` | `INT` | OUT | — | 个 | 当前有效样本数 / Valid sample count |
| `bValid` / `bStatValid` | `BOOL` | OUT | — | — | 均值极值有效（n≥1）/ 方差有效（n≥2）/ Validity flags |
| `uErrorId` | `UDINT` | OUT | — | — | 瞬时码，逐拍重算 / Transient code |
| `eState` | `E_DL_StatState` | OUT | — | — | `eEmpty(0)` / `eFilling(10)` / `eReady(20)` / `eFault(99)` / State |

### 18.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 窗口越界已钳位（2..64）/ Window clamped | 检查参数来源 |
| `16#0002_0009` | **样本不足（n < 2），方差与标准差输出 0** / Insufficient samples for variance | 等窗口积累；瞬时码不锁存 |

### 18.3 调用示例 / Example

```iecst
VAR
    fbStat  : FB_DL_SignalStatistics;   // PID 整定前噪声评估 / noise assessment
    fPress  : REAL;                     // 压力采样 [bar] / pressure sample
END_VAR

fbStat(fIn := fPress, bSample := TRUE, nWindow := 64, bClear := FALSE);

(* 标准差即噪声水平，用于整定微分项与死区宽度 / noise level for tuning *)
IF fbStat.bStatValid THEN
    fNoiseSigma := fbStat.fStdDev;
END_IF
```

### 18.4 要点 / Notes

- **两遍法方差是硬约束**：「平方和减均值平方」在均值远大于标准差时（如 1000.0 ± 0.01）因灾难性抵消会算出负方差——SPC 场景经典事故。本块多一遍 O(n) 换数值安全。
- **样本方差（n−1）口径**：与 Excel `STDEV.S` 一致，不是 `STDEV.P`；n < 2 不做除法。
- **极值每拍随均值重算**：滑出的样本恰为极值时增量维护会残留旧极值，64 点重算代价可接受。
- **累加用 LREAL、输出转回 REAL**：抗累加误差，输出与现场模拟量量程口径一致。

---

## 19. FC_DL_QuickSortLReal ｜ 快速排序（无递归）

**定位**：定长 LREAL 数组（≤64 元素）原地快速排序，升/降序可选。**显式栈迭代实现，无任何递归**——ST 递归在嵌入式运行时与汇川 InoProShop 栈深受限或直接不支持。枢轴三数取中防最坏退化，小区间（<8 元素）自动改走插入排序。用于分位数、去极值均值、报表排序。

### 19.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `afData` | `ARRAY[0..63] OF LREAL` | IN_OUT | — | 待排序数组，**原地修改，失败时内容未定义** / Sorted in place, undefined on failure |
| `nCount` | `INT` | IN | — | 有效元素数 0..64，负值拒绝、超限钳位 / Element count |
| `bAscending` | `BOOL` | IN | `TRUE` | TRUE = 升序 / Ascending order |
| `uCompareCount` / `uSwapCount` | `UDINT` | OUT | — | 比较 / 交换次数（性能诊断，饱和）/ Comparison / swap counters |
| `bUsedFallback` | `BOOL` | OUT | — | TRUE = 显式栈溢出，子区间转插入排序兜底（降级不是缺陷）/ Insertion fallback used |
| `uErrorId` | `UDINT` | OUT | — | 故障码 / Error code |
| 返回值 / Return | `BOOL` | RET | — | 排序成功；**FALSE 时必须丢弃数组内容** / FALSE = discard the array |

### 19.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | 数量非法：负值拒绝 / 超限钳位 / Invalid count | 检查调用方计数 |
| `16#0001_0004` | 循环保护触发，**数组可能部分有序** / Loop guard tripped | 返回 FALSE，丢弃本轮结果 |
| `16#0001_0006` | 输入含 NaN/Inf，预扫描拒绝，**数组保持原样** / NaN/Inf rejected | 先清洗数据再排序；本码由「预留」转为实际使用 |

### 19.3 调用示例 / Example

```iecst
VAR
    aVal   : ARRAY[0..63] OF LREAL;     // 待排序数据 / data to sort
    nVal   : INT  := 20;                // 有效元素数 / valid count
    bSorted: BOOL;
    uErr   : UDINT;
END_VAR

bSorted := FC_DL_QuickSortLReal(afData := aVal, nCount := nVal,
                                bAscending := TRUE, uErrorId => uErr);

IF NOT bSorted THEN
    ; (* 数组内容未定义，丢弃本轮结果，禁止假装成功 / discard the result *)
END_IF
```

### 19.4 要点 / Notes

- **先压大区间、后压小区间**是栈深 O(log n) 的唯一保证；顺序写反后全等值数组会把 16 深栈打爆。
- **三数取中先交换到末位再做 Lomuto**：规格书原文「不必交换到固定位置」经实算证伪（尾元素为三数最小时会永久错位），已在头注释勘误留档。
- **快速排序不稳定**：相同值相对次序不保证；需要稳定排序时用插入排序变体（后续扩产）。
- **对规格书的一处勘误**：见该文件头注释「对 ROUND_PLAN §7.13 的一处勘误」段。

---

## 20. FC_DL_HexStringToBytes ｜ 十六进制串解析

**定位**：十六进制 ASCII 字符串到字节数组的**严格**解析（`"1A2B3C"` → `16#1A, 16#2B, 16#3C`），可选剥离 Modbus ASCII 帧头尾。两遍扫描严格模式：第一遍全量校验字符合法性，第二遍才写入输出。与 `FC_DL_LrcChecksum` 组成两步收帧链。

### 20.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 说明 / Description |
|---|---|---|---|---|
| `aabyOut` | `ARRAY[0..63] OF BYTE` | IN_OUT | — | 输出字节缓冲，**失败时不写入** / Output buffer, untouched on failure |
| `sHex` | `STRING(255)` | IN | — | 十六进制字符串，**显式 255 长度防截断** / Hex string, explicit length |
| `bStripFraming` | `BOOL` | IN | `FALSE` | TRUE：剥离首冒号与尾部回车换行 / Strip framing |
| `nMaxBytes` | `INT` | IN | `64` | 允许写入的最大字节数 1..64 / Max bytes to write |
| `nInvalidPos` | `INT` | OUT | — | 首个非法字符位置（原文 1 起，含被剥离的冒号），0 = 无 / First invalid char position |
| `uErrorId` | `UDINT` | OUT | — | 故障码 / Error code |
| 返回值 / Return | `INT` | RET | — | 解析出的字节数；失败返回 -1，空串返回 0 / Byte count; -1 on failure |

### 20.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | — |
| `16#0001_0001` | `nMaxBytes` 越界已钳位 / Capacity clamped | 检查参数 |
| `16#0001_0009` | 报文超缓冲（钳位后仍写不下），缓冲不变 / Message exceeds buffer | 缩短报文或分批 |
| `16#0002_000A` | **报文非法：奇数长度 / 非法字符**，`nInvalidPos` 定位 / Odd length or illegal char | 拿着 `nInvalidPos` 数到出错字符；不补 0、不跳过 |

### 20.3 调用示例 / Example

```iecst
VAR
    sRx     : STRING(255);              // 扫码枪原始报文 / raw scanner frame
    abyBody : ARRAY[0..63] OF BYTE;     // 解码输出 / decoded bytes
    nBytes  : INT;
    nBadPos : INT;
    uErr    : UDINT;
END_VAR

nBytes := FC_DL_HexStringToBytes(aabyOut := abyBody, sHex := sRx,
                                 bStripFraming := FALSE, nMaxBytes := 64,
                                 nInvalidPos => nBadPos, uErrorId => uErr);

IF nBytes < 0 THEN
    bScanNak := TRUE;                   // 报文非法，NAK / reject with NAK
END_IF
```

### 20.4 要点 / Notes

- **严格模式是刻意的**：不跳过空格、不跳过 `0x` 前缀、不容忍内嵌分隔符——宽容解析会把组帧错误吃进数据层，现场表现为「校验通过但数据错」，比直接报错难查一个数量级。
- **奇数长度判非法而非补 0**：补 0 会凭空造出一个字节。
- **失败不写缓冲**：调用方可能直接把缓冲拿去发报文，半截字节流比没有更危险。
- **`STRING(255)` 必须显式声明**：CODESYS 默认 STRING 仅 80 字节，省略长度会被静默截断。

---

## 21. 故障码总表 / Error Code Table

| ErrorID | 含义 / Meaning | 本子库适用组件 / Components |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | 全部 |
| `16#0001_0001` | 参数越界（窗口长度 / 字节数 / 折点数 / 顶点数 / 数量 / 容量）/ Parameter out of range | LinearScale(量程)、MovingAverage、Crc16Modbus、StringSplit、MultiPointLinear、PolygonArea、LineIntersection、Crc32Ethernet、LrcChecksum、QuickSortLReal、HexStringToBytes、MedianFilter、SignalStatistics |
| `16#0001_0002` | 量程 / 分母为零或近零 / Span or denominator near zero | LinearScale、MovingAverage |
| `16#0001_0003` | 参数符号非法（负宽度 / 负回差）/ Illegal sign | Deadband、Hysteresis |
| `16#0001_0004` | 循环保护触发 / Loop guard tripped | MovingAverage、StringTrim、StringSplit、QuickSortLReal |
| `16#0001_0005` | 状态机进入非法状态 / Illegal state hit | MovingAverage |
| `16#0001_0006` | 输入数据非法（NaN / Inf）/ Invalid input data | LinearScale、MovingAverage（预留）；**QuickSortLReal（v1.2.0 起实际使用：NaN 预扫描拒绝）** |
| `16#0001_0007` | 数值溢出 / Overflow | （DL_Base 使用） |
| `16#0001_0008` | 分隔符长度非法 / Delimiter length illegal | StringSplit |
| `16#0001_0009` | 缓冲已满，写入被拒绝 / Buffer full | RingBufferLReal、LifoStack（上溢） |
| `16#0001_000A` | 缓冲已空，读取被拒绝 / Buffer empty | RingBufferLReal、LifoStack（下溢） |
| `16#0001_000D` | 字段数超缓冲，结果被截断 / Fields truncated | StringSplit |
| `16#0001_000E` | 排布枚举值非法 / Layout enum out of domain | SwapBytes32 |
| `16#0002_0009` | 统计样本不足（n < 2），方差输出 0 / Insufficient samples for variance | SignalStatistics |
| `16#0002_000A` | 十六进制串非法（奇数长度 / 非法字符），`nInvalidPos` 定位 / Illegal hex string | HexStringToBytes |
| `16#0002_000B` | 折线表非法（X 非严格递增），整表拒绝 / Table not strictly increasing | MultiPointLinear |
| `16#0002_000C` | 多边形退化（点数 < 3 / 零面积）/ Degenerate polygon | PolygonArea |
| `16#0002_000D` | 两线重合（共线），无唯一交点 / Coincident lines | LineIntersection |

> `16#0002_xxxx` 为 v1.2.0 新启用的故障码段（业务/工艺类语义），与 `16#0001_xxxx` 参数/循环段并行分配，全库登记于 `LIBRARY_MANUAL.md` 第四节。

---

## 22. 红线自检结论 / Redline Conformance

| 红线 / Rule | 判定 | 说明 / Note |
|---|---|---|
| R1 零全局变量表与外部变量引用 | PASS | 20 个 `.st` 全文机检 0 命中 |
| R2 零物理 IO 地址直写 | PASS | 0 命中 |
| R3 纯 IEC 61131-3 | PASS | 无 `/2` 取位、无点号位访问、无厂商函数、显式类型转换 |
| R4 防除零 / 防越界 / 浮点容差 | PASS | 除法全部前置容差判断；数组下标双检；浮点判等全部带容差；`WHILE` 带防死锁 |
| R5 中英双语同行注释 | PASS | 声明行 100% 双语带单位 |
| R6 状态机 ENUM + CASE + ELSE | PASS | `FB_DL_MovingAverage` 四态 + `ELSE` 兜底；`FC_DL_SwapBytes32` 以 `CASE ... ELSE` 兜底；其余标注 N/A |
| R7 定时器 / 边沿无条件刷新 | PASS | `fbTrigReset` / `fbTrigPush` / `fbTrigPop` 均位于主体最前部 |
| R8 无魔法数 | PASS | 容量、字段数、移位量、掩码全部常量化 |
| R9 声明行三要素 | PASS | 物理意义 + 英文术语 + 单位 |
| R10 语义描述式自检 | PASS | 头注释不引用被禁符号 |
| R11 偏离留档 | PASS | `FC_DL_SwapBytes32` 纯移位自洽实现选择、`FC_DL_SwapBytes16` 无故障码豁免均已留档 |
| R12 验收向量可复算 | PASS | 四排布 4×4 矩阵、环形缓冲回绕序列、CRC-32/LRC 验收向量、统计七元组样例全部实测复算 |
| R13 POU 终结符成对 / Terminator pairing | PASS | v1.2.0 库级补全后 20 个 `.st` 全部含 `END_FUNCTION` / `END_FUNCTION_BLOCK`（见 `VERSION.md` v1.2.0 Fixed 节） |

---

## 23. FB_DL_FifoBuffer ｜ LREAL 先进先出环形队列（R9，v1.0.1）

**定位 / Positioning**：定长槽位 FIFO 环形队列（通用元素队列：离散事件 / 物料号 / 批号缓存），压入/弹出/窥视/清空四操作；满队压入「丢新」策略（拒绝并单拍告警，不覆盖旧数据——物料追溯场景丢新比丢旧更危险）。与 `FB_DL_RingBufferLReal`（时间序列滑动窗，丢旧语义）不可互相替代。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bPush` | BOOL | IN | 压入请求，上升沿生效 / Push request, rising edge |
| `fPushVal` | LREAL | IN | 待压入元素值 [工程单位随应用] / Value to push [EU] |
| `bPop` | BOOL | IN | 弹出请求，上升沿生效 / Pop request, rising edge |
| `bPeek` | BOOL | IN | 窥视请求（读队头不弹出），上升沿生效 / Peek request, rising edge |
| `bClear` | BOOL | IN | 清空请求，电平生效，最高优先级 / Clear request, level, highest priority |
| `uCapacity` | UINT | IN | 队列容量 [槽位]，2..256 越界自动钳位 / Queue capacity [slots], clamped |
| `fOutVal` | LREAL | OUT | 弹出/窥视结果值，被拒时保持上次有效值（哨兵语义：判成败看 bFound）/ Pop/peek result, held on rejection |
| `bDone` | BOOL | OUT | 操作处理完成单拍（含被拒操作） / Operation processed this scan, one pulse |
| `bFound` | BOOL | OUT | 弹出/窥视成功标志 / Pop/peek success flag |
| `bFull` / `bEmpty` | BOOL | OUT | 队列满 / 空（保持型） / Full / empty flags, held |
| `bOverflow` | BOOL | OUT | 满队压入被拒（丢新），单拍脉冲 / Push rejected when full, one pulse |
| `bUnderflow` | BOOL | OUT | 空队弹出被拒，单拍脉冲 / Pop rejected when empty, one pulse |
| `uCount` | UINT | OUT | 当前元素数 [个] / Current element count |
| `uErrorId` | UDINT | OUT | 故障码：0001_010A 容量钳位 / 010B 满队丢新 / 010C 空队弹出 / 010D 空队窥视（信息级）；0001_0204 指针一致性破坏自愈重建（故障级） / Error code |
| `afData` | ARRAY[0..255] OF LREAL | IN_OUT | 存储体，由调用方持有并注入（RETAIN 策略调用方自主决定）/ Storage array, caller-owned |

### 调用示例 / Example

```iecst
VAR
    afFifoStore : ARRAY[0..255] OF LREAL;   // 调用方持有存储体 / Caller-owned storage
    fbBatchFifo : FB_DL_FifoBuffer;         // 队列实例 / FIFO instance
    fBatchNo    : LREAL;                    // 弹出结果 / Popped value
END_VAR

fbBatchFifo(bPush := bNewBatch, fPushVal := fBatchIn,
            bPop := bConsume, bPeek := FALSE, bClear := bResetFifo,
            uCapacity := 64, afData := afFifoStore);
IF fbBatchFifo.bDone AND fbBatchFifo.bFound THEN
    fBatchNo := fbBatchFifo.fOutVal;        // 取弹出/窥视结果 / Take the result
END_IF
```

**要点 / Notes**：同拍「弹 + 压」按**先弹后压**固定次序（物料场景弹旧批号优先，净效果「换入队尾」，与 RingBuffer 的先压后弹相反，不可交换）；被拒操作同样置 bDone，成败以 bFound / bOverflow / bUnderflow 区分；同一实例每周期只能调用一次（多任务冲突会触发 0001_0204 自愈，频现即冲突征兆）；容量中途缩小到小于当前计数触发一致性断言自愈清空（契约行为，见 O-08 增 bRebuilt 事件留档 v1.1）。

---

## 24. FB_DL_ArraySearchFirst ｜ 数组线性搜索首个命中值（R9，v1.0.1）

**定位 / Positioning**：在注入数组前 nCount 个元素中线性搜索首个命中目标值的索引；可选全量计数模式统计命中总数。不要求有序，O(n) 单遍。与 `FC_DL_BinarySearchLReal`（升序 O(log n)）职责分离：高频轮询查找选二分、低频事件查找/无序数据选本块。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| `bExecute` | BOOL | IN | 执行搜索，上升沿触发一次扫描 / Execute scan, rising edge |
| `fTarget` | LREAL | IN | 目标值（与数据体同工程单位）/ Target value [EU] |
| `nCount` | DINT | IN | 搜索前缀长度 [元素]，0..1024 钳位 / Prefix length, clamped |
| `bSearchAll` | BOOL | IN | TRUE = 继续全量扫描统计命中总数 / Count all hits mode |
| `bDone` | BOOL | OUT | 搜索完成单拍（结果须在本拍内取走）/ Done one-scan pulse |
| `bFound` | BOOL | OUT | 至少命中一个 / At least one hit |
| `nIndex` | DINT | OUT | 首个命中索引，未命中恒 -1 / First-hit index, -1 if none |
| `uHitCount` | UINT | OUT | 命中总数（单命中模式为 0/1）/ Total hits |
| `uErrorId` | UDINT | OUT | 故障码：0001_010E nCount 越界钳位（信息级）/ 0001_0205 守护超限（故障级，理论不可达） / Error code |
| `afData` | ARRAY[0..1023] OF LREAL | IN_OUT | 搜索数据体，调用方持有 / Search array, caller-owned |

### 调用示例 / Example

```iecst
VAR
    afRecipeTab : ARRAY[0..1023] OF LREAL;  // 调用方持有搜索体 / Caller-owned array
    fbFindBatch : FB_DL_ArraySearchFirst;   // 搜索实例 / Search instance
    nSelRow     : DINT;                     // 命中行索引 / Hit row index
END_VAR

fbFindBatch(bExecute := bLookup, fTarget := fBatchNo,
            nCount := nLoadedRows, bSearchAll := FALSE,
            afData := afRecipeTab);
IF fbFindBatch.bDone AND fbFindBatch.bFound THEN
    nSelRow := fbFindBatch.nIndex;          // 触发拍内取走结果 / Consume within the pulse
END_IF
```

**要点 / Notes**：nCount 传「实际装载行数」而非数组全长（残留旧数据会误命中）；bExecute 保持 TRUE 不会连续扫描（R_TRIG 只认上升沿）；命中判据 ABS 容差比较禁浮点判等；未命中结果族每拍先清不残留。O-02：段 3~5 缩进与死代码守护分支留档 v1.1。

---

## 25. FC_DL_BinarySearchLReal ｜ 升序数组二分查找（R9，v1.0.1 · D-01 致命修复件）

**定位 / Positioning**：对升序 LREAL 数组做经典二分查找，返回首个命中索引（未命中 -1）；纯函数无状态。调用方保证有序（校验全序需 O(n) 会摧毁 O(log n) 价值，契约责任在调用方）。1024 元素最多 11 次比较。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| 返回值 / Return | DINT | RET | 命中索引 [元素下标]，未命中 = -1 / Hit index, -1 when not found |
| `afSorted` | ARRAY[0..1023] OF LREAL | IN_OUT | 升序数组（调用方保证有序）/ Ascending array, sorted by caller |
| `nCount` | DINT | IN | 有效元素数 [个]，0..1024 越界钳位 / Valid element count |
| `fTarget` | LREAL | IN | 目标值 [工程单位随应用] / Target value [EU] |
| `bFound` | BOOL | OUT | 命中标志（与返回值同真相） / Hit flag, same truth as return |
| `uErrorId` | UDINT | OUT | 故障码：0001_010F nCount 钳位（信息级）/ 0001_0206 守护超限（故障级）。**v1.0.1 补声明本引脚**（原 1.0.0 函数体 5 处读写未声明，三平台编译必败——D-01 致命缺陷） / Error code; declared in v1.0.1 (fatal D-01 fix) |

### 调用示例 / Example

```iecst
VAR
    afCalTab : ARRAY[0..1023] OF LREAL;     // 升序标定表 / Ascending calibration table
    nSlot    : DINT;                        // 命中槽位 / Hit slot
    bHit     : BOOL;                        // 命中标志 / Hit flag
END_VAR

nSlot := FC_DL_BinarySearchLReal(afSorted := afCalTab,
                                 nCount := nRows, fTarget := fMeas,
                                 bFound => bHit);
IF NOT bHit THEN
    nSlot := -1;                            // 未命中走线性插值等后备逻辑 / Fallback path
END_IF
```

**要点 / Notes**：中点固定写法 `nMid := nLo + (nHi - nLo) / 2` 防 `(nLo + nHi)` 溢出；重复值返回其中任一命中下标（经典二分不保证首个，需要「首个命中」语义用 ArraySearchFirst）；返回值做数组下标前必须先判 bFound（-1 会被当最后一个元素）。

---

## 26. FC_DL_TempUnitConvert ｜ ℃ / ℉ / K 三温标互转（R9，v1.0.1）

**定位 / Positioning**：摄氏 / 华氏 / 开尔文三温标两两互转（纯函数）：源/目标由枚举对单向选择（3×3 查表 + 单向基准链 4 条公式，无 MODE 巨无霸）；同标直通；低于绝对零度置信息级不阻断（诊断链留证，截断会抹掉断线故障证据）。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| 返回值 / Return | LREAL | RET | 换算结果 [目标温标单位]；枚举非法恒 0.0 / Converted result, 0.0 on illegal enum |
| `fVal` | LREAL | IN | 输入温度 [源温标单位] / Input temperature [source unit] |
| `eSrc` | E_DL_TempUnit | IN | 源温标：eCelsius(0)/eFahrenheit(1)/eKelvin(2) / Source unit selector |
| `eDst` | E_DL_TempUnit | IN | 目标温标 / Destination unit selector |
| `uErrorId` | UDINT | OUT | 故障码：0001_0110 低于绝对零度（信息级，返回值照算）/ 0001_0207 源温标非法 / 0001_0208 目标温标非法（故障级） / Error code |

### 调用示例 / Example

```iecst
VAR
    fShow : LREAL;                          // HMI 显示值 / HMI display value
    nErr  : UDINT;                          // 诊断码 / Diagnostic code
END_VAR

// 台账存摄氏，HMI 依用户语言显示华氏 / Ledger in Celsius, display in Fahrenheit
fShow := FC_DL_TempUnitConvert(fVal := fLedger, eSrc := E_DL_TempUnit.eCelsius,
                               eDst := E_DL_TempUnit.eFahrenheit,
                               uErrorId => nErr);
```

**要点 / Notes**：验收 V5 双温标交点 -40 C→F 恒 -40.0；0 K 直通为合法物理下界不置码（容差含等号）；台账口径建议全程统一摄氏存储、显示层换算，避免多级换算叠加放大舍入误差。

---

## 27. FC_DL_BcdToWord ｜ BCD 码转 UINT（R9，v1.0.1）

**定位 / Positioning**：16 位 BCD 码字（4 个十进制半字节）转 UINT [0~9999]（纯函数）；任一半字节 > 9（A~F 非法码）立即置故障返回 0，绝不返回部分累加结果。面向 BCD 拨码开关读数、BCD 编码仪表、BCD 格式寄存器解析。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| 返回值 / Return | UINT | RET | 十进制数值 [0~9999]；错误路径固定 0 / Decimal value; 0 on error path |
| `uBcd` | WORD | IN | BCD 码字，位域 [千|百|十|个]，每半字节 0~9 合法 / BCD word, one digit per nibble |
| `uErrorId` | UDINT | OUT | 故障码：0001_0105 非法半字节（瞬时码每次调用重算） / Error code |

### 调用示例 / Example

```iecst
uDipValue := FC_DL_BcdToWord(uBcd := wDipSwitchWord, uErrorId => uDipErr);
IF uDipErr <> 0 THEN
    // BCD 拨码异常：返回 0 与合法值 0 靠 uErrorId 区分，勿只看返回值
END_IF
```

**要点 / Notes**：v1.0.1 将全库唯一强制转换写法 `UINT(uDigit)` 改为标准 `USINT_TO_UINT()`（公约三显式转换，D-13）；误用警示——二进制值直接当 BCD 传入会静默错值（16#0064 实际 100 被读成 64）。

---

## 28. FC_DL_WordToBcd ｜ UINT 转 BCD 码（R9，v1.0.0）

**定位 / Positioning**：UINT [0~9999] 转 16 位 BCD 码字（纯函数）；超 9999 溢出**饱和不回绕**——返回 16#9999 满量程显示值 + 置码（回绕会让上层把「溢出」误读为「值为零」，静默危险错值）。与 BcdToWord 构成编解码原子对，互不调用保持 Level 0 零内耦。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 说明 / Description |
|---|---|---|---|
| 返回值 / Return | WORD | RET | BCD 码字 [每半字节一位十进制]；溢出路径 16#9999 / BCD word; saturates at 16#9999 |
| `uVal` | UINT | IN | 十进制输入值 [0~9999]，超限走饱和路径 / Decimal input, overflow saturates |
| `uErrorId` | UDINT | OUT | 故障码：0001_0106 溢出饱和 / 0001_0107 除基守卫命中（防御性，正常组态不触发） / Error code |

### 调用示例 / Example

```iecst
wBcdSet := FC_DL_WordToBcd(uVal := nBatchNo, uErrorId => uBcdErr);
IF uBcdErr = 16#0001_0106 THEN
    // 设定值超 BCD 量程：16#9999 是饱和显示值非真实数据，走钳位/报警链
END_IF
```

**要点 / Notes**：验收向量 V5 uVal = 4096 → 16#4096（除基取余链逐位可复算）；负数不入参域（UINT），符号处理在上层。

---

## 29. FC_DL_SearchMinMax ｜ 数组极值扫描（值 + 索引）（R10，v1.0.0）

**定位 / Positioning**：单遍扫描 LREAL 数组，一次性给出最小值 / 最大值及其**下标**，并报告有效比较个数与被跳过的非有限值个数。面向「找最冷的那支电芯」「哪一通道压力最高」「趋势极值出现在第几个采样点」这类**位置比数值更值钱**的判读。

**与同类组件选型 / Selection**：极值 + 位置本件；只要统计量（均值/方差/峰谷）用 `FB_DL_SignalStatistics`；要找「某个特定值在哪」用 `FB_DL_ArraySearchFirst`；有序数组找目标值用 `FC_DL_BinarySearchLReal`。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| 返回值 / Return | BOOL | RET | — | 存在至少一个有效极值 = TRUE；全量非有限 = FALSE / TRUE when at least one valid extremum exists |
| `afData` | ARRAY[0..255] OF LREAL | IN_OUT | — | 扫描数据体，调用方持有并注入，上界与 `DL_SMM_MAX` 一致 [工程单位] / Scanned array owned by the caller |
| `nCount` | DINT | IN | 0 | 参与扫描的元素个数，有效域 1~`DL_SMM_MAX`（256）[个] / Number of elements to scan |
| `bLastHit` | BOOL | IN | FALSE | TRUE = 索引取**末次**命中，FALSE = 取**首个**命中 [−] / TRUE selects the last hit |
| `fMin` | LREAL | OUT | — | 最小值，无有效数据时为 0.0 [工程单位随应用] / Minimum value |
| `fMax` | LREAL | OUT | — | 最大值，无有效数据时为 0.0 [工程单位随应用] / Maximum value |
| `nMinIdx` | DINT | OUT | -1 | 最小值索引，未找到为 −1 [元素下标] / Index of the minimum |
| `nMaxIdx` | DINT | OUT | -1 | 最大值索引，未找到为 −1 [元素下标] / Index of the maximum |
| `nValidCnt` | DINT | OUT | — | 实际参与比较的有效元素数 [个] / Elements actually compared |
| `nSkipCnt` | DINT | OUT | — | 因非有限值被跳过的元素数 [个] / Non-finite elements skipped |
| `bFlat` | BOOL | OUT | — | 全等标志：极值在容差内相等 [−] / TRUE when min equals max within tolerance |
| `uErrorId` | UDINT | OUT | — | 事件码：`0001_0119` 计数越界 / `0001_011A` 存在被跳过的非有限值 / `0001_0217` 全量非有限 / Event code |

### 调用示例 / Example

```iecst
VAR
    afBatteryTemp : ARRAY[0..255] OF LREAL;   // 电芯温度采样 [℃] / Cell temperatures
    fTempMax      : LREAL;                    // 最高温 / Hottest cell temperature
    nHotIndex     : DINT;                     // 最高温所在通道 / Index of the hottest cell
    fTempMin      : LREAL;                    // 最低温 / Coolest cell temperature
    nColdIndex    : DINT;                     // 最低温通道 / Index of the coolest cell
    nBadSamples   : DINT;                     // 非有限值个数 / Non-finite sample count
    bScanOk       : BOOL;                     // 扫描有效 / Scan valid
    uScanErr      : UDINT;                    // 事件码 / Event code
END_VAR

bScanOk := FC_DL_SearchMinMax(afData := afBatteryTemp, nCount := nCellCount, bLastHit := FALSE,
                              fMin => fTempMin, fMax => fTempMax,
                              nMinIdx => nColdIndex, nMaxIdx => nHotIndex,
                              nSkipCnt => nBadSamples, uErrorId => uScanErr);

IF bScanOk AND (fTempMax - fTempMin) > fCellDeltaAlarm THEN
    // 温差告警：直接指出最热通道号，HMI 可定位 / Delta alarm with the index for direct locating
END_IF
```

**要点 / Notes**：
- **NaN 判据**：用 `x <> x` 识别非有限值（NaN 参与任何比较都为 FALSE，若直接比大小会被静默当成「不是极值」）；跳过后计 `nSkipCnt` 并置 `0001_011A`。
- **全量非有限的返回策略**：返回 FALSE，`nMinIdx`/`nMaxIdx` 置 −1，且**不把 0 号位当结果**（避免上层误读第一个坏点）；`fMin`/`fMax` 为 0.0 仅作占位。
- **首/末次命中**：`bLastHit` 只影响索引，不影响极值（同值时哪个下标更有意义由工艺决定：末次命中适合「最后一次出现的峰值」类判读）。
- **`bFlat` 全等容差** `DL_FLOAT_EPS = 1E-9`；数组上界 256 为硬绑定，`nCount` 超上限按上限钳位（`0001_0119`）而非拒绝。

---

## 30. FC_DL_NthRoot ｜ N 次根（纯函数）（R10，v1.0.0）

**定位 / Positioning**：任意正整数次根 `fValue^(1/n)`，奇次根支持负底数，偶次根对负底数明确拒绝（**不拿绝对值冒充结果**）。用于几何均值、等效值折算、泵/风机相似定律（转速比的 1/3 次幂）等场景。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| 返回值 / Return | LREAL | RET | — | 计算结果；非法域返回 0.0 且 `bValid = FALSE` / Result, 0.0 with `bValid = FALSE` on illegal domain |
| `fValue` | LREAL | IN | 1.0 | 被开方数，偶次根要求 ≥ 0 [无量纲或工程单位] / Radicand, non-negative for even roots |
| `nRoot` | INT | IN | 2 | 根次数 n，有效域 1~64（正整数）[次] / Root order, 1..64 |
| `bValid` | BOOL | OUT | — | 域合法且结果有限 = TRUE [−] / Domain legal and result finite |
| `uErrorId` | UDINT | OUT | — | 事件码：`0001_011B` 根次数越界 / `0001_011C` 偶次负底数·入参非有限·结果非有限 / Event code |

### 调用示例 / Example

```iecst
VAR
    fFanSpeedRatio : LREAL;    // 风机转速比 / Fan speed ratio
    fPowerRatio    : LREAL;    // 轴功率比（三次方律反向）/ Power ratio
    bRootOk        : BOOL;     // 结果有效 / Result valid
    uRootErr       : UDINT;    // 事件码 / Event code
END_VAR

// 由功率比反推转速比：n ∝ P^(1/3)
fPowerRatio := fPowerNew / fPowerRated;
fFanSpeedRatio := FC_DL_NthRoot(fValue := fPowerRatio, nRoot := 3,
                               bValid => bRootOk, uErrorId => uRootErr);
IF NOT bRootOk THEN
    // 域非法或结果非有限：不要拿 0.0 当真实转速比用
END_IF
```

**要点 / Notes**：
- **奇偶次分治**：偶次根 + 负底数 → 拒绝（`0001_011C`）；奇次根 + 负底数 → `-((-x)^(1/n))`，保持符号对称。
- **守卫完整**：`x = 0` 直返 0（不进迭代）；`n = 1` 恒等；`n ≤ 0` 与 `n > 64` 拒绝（64 次以上对数法精度不可控）。
- **Newton 迭代 + 结果复检**：迭代结束后再判结果是否有限（`ABS(fRes) > DL_BIG` 即视为发散），拦住 `Inf`/`NaN` 穿透到控制链。
- **纯函数**：无内部状态，可放进 `IF` 条件与赋值表达式；容差 `DL_FLOAT_EPS = 1E-12`。

---

## 31. FC_DL_FactorialSat ｜ 阶乘（饱和）（R10，v1.0.1）

**定位 / Positioning**：自然数阶乘 `n!`（域 0~12），超出可算域**饱和到 12!** 并置 `bSat`，绝不回绕成负数。用于组合数计算、脉冲序列长度、配方排列数估算等「只要量级正确、不能出负数」的场合。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 说明 / Description |
|---|---|---|---|---|
| 返回值 / Return | DINT | RET | — | 阶乘结果；超域返回 `DL_FACT_SAT`（12! = 479,001,600）/ Factorial, saturates at 12! |
| `nValue` | INT | IN | 0 | 自然数 n，有效域 0~12，负数按 0 处理 [无量纲] / Natural number, 0..12 |
| `bSat` | BOOL | OUT | — | 饱和标志：入参超域或结果溢出为 TRUE [−] / TRUE when out of domain or saturated |
| `nUsedN` | INT | OUT | — | 实际参与计算并钳位后的 n [无量纲] / Effective n after clamping |
| `uErrorId` | UDINT | OUT | — | 事件码：`0001_011D` 入参超域（信息级）/ Event code |

### 调用示例 / Example

```iecst
VAR
    nOrderCount : INT;      // 配方排列阶数 / Permutation order
    nWays       : DINT;     // 排列数 / Number of arrangements
    bClamped    : BOOL;     // 是否饱和 / Saturated
    nEffN       : INT;      // 实际阶数 / Effective order
    uFactErr    : UDINT;    // 事件码 / Event code
END_VAR

nWays := FC_DL_FactorialSat(nValue := nOrderCount, bSat => bClamped,
                            nUsedN => nEffN, uErrorId => uFactErr);
IF bClamped THEN
    // n 超过 12：结果只是量级参考（12! 饱和值），不能用于精确排产
END_IF
```

**要点 / Notes**：
- **饱和边界**：`12! = 479,001,600 < 2^31−1`，正常返回；`13!` 已超 DINT 上限 → 饱和。`0! = 1` 与 `1! = 1` 由常量直接给出（不经循环）。
- **v1.0.1 修复（D-17，注释级/类型级）**：累乘语句由 `nAcc * i` 改为 `nAcc * INT_TO_DINT(i)`，消除 DINT × INT 的隐式类型提升（红线三「不用隐式类型转换」），数值结果与全部验收向量不变。
- **负数按 0 处理**（返回 1）并置 `0001_011D`，与「拒绝」策略不同——阶乘在组合公式里负号通常来自上游计数器的欠账，取 0 更接近工艺意图；若需拒绝请在调用侧先行判负。

---

## 32. FC_DL_RangeOverlapCheck ｜ 两个区间的几何关系判定（R11，v1.0.0）

**定位 / Positioning**：输入**四个端点**（区间 A 的两个端点、区间 B 的两个端点），返回六值关系枚举，同出重叠长度。服务场景：配方参数域与设备安全包络对撞检查、两班次时间窗互斥检查、来料公差带与装配公差带叠加、机器人可达包络与围栏安全距离带的重叠长度评估。

**判定次序 / Decision order（写死，不可调换）**：① 有限性闸门（全部有限才继续）→ ② 端点归一（每个区间内部排序）→ ③ **相等** → ④ **相离** → ⑤ **相接** → ⑥ **包含** → ⑦ 其余为部分重叠。相等必须先于包含（否则被包含分支吞掉），相离必须先于相接，相接必须先于部分重叠。

**开闭区间口径 / Open vs closed**：几何关系与开闭**无关**——"相接"只描述两组端点几何重合，开区间同样判相接。开闭只影响「相接处那一个点是否属于公共交集」，其判据为 `bTouching AND bIncA AND bIncB`，由调用方合成，本件不额外输出第三态。重叠长度按端点差值计算，**不做开区间减去两端的离散化折算**（连续量工程口径下端点测度为零，减去端点会引入 1 个单位误差）。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `fA1` | REAL | IN | — | 工程单位 | 区间 A 端点 1，无序自动对调 / Range A endpoint 1, auto-swapped |
| `fA2` | REAL | IN | — | 工程单位 | 区间 A 端点 2 / Range A endpoint 2 |
| `fB1` | REAL | IN | — | 工程单位 | 区间 B 端点 1，无序自动对调 / Range B endpoint 1 |
| `fB2` | REAL | IN | — | 工程单位 | 区间 B 端点 2 / Range B endpoint 2 |
| `bIncA` | BOOL | IN | `TRUE` | — | A 是否闭区间（含端点）/ A is a closed interval |
| `bIncB` | BOOL | IN | `TRUE` | — | B 是否闭区间 / B is a closed interval |
| `fOverlapSpan` | REAL | OUT | — | 工程单位 | 重叠长度，无重叠 = 0.0，**恒非负** / Overlap length, never negative |
| `bTouching` | BOOL | OUT | — | — | 仅端点相接（重叠长度 0 但边界重合）/ Endpoints touch only |
| `bValid` | BOOL | OUT | — | — | 四个输入全部有限（非 NaN、非无穷）/ All inputs finite |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无；**全部信息级** / Event code, informational only |
| 返回值 / Return | E_DL_RangeRelation | RET | — | — | `eInvalid` 0 / `eDisjoint` 10 / `eTouching` 20 / `ePartial` 30 / `eContains` 40 / `eEqual` 50 |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0121` | 信息级 | 输入含非有限值（NaN / 无穷），关系不可判，返回 `eInvalid`、重叠长度 0.0 | 上游坐标或参数来源异常；本件已保证下游拿到 0.0 而非 NaN，不会污染累加 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_RecipeEnvelopeCheck
VAR
    eRel           : E_DL_RangeRelation;  // 关系结果 / Relation result
    fSafeLo        : REAL := 0.0;         // 安全包络下限 [摄氏度] / Safe envelope low
    fSafeHi        : REAL := 80.0;        // 安全包络上限 [摄氏度] / Safe envelope high
    fNewLo         : REAL := 70.0;        // 新配方窗下限 [摄氏度] / New recipe window low
    fNewHi         : REAL := 120.0;       // 新配方窗上限 [摄氏度] / New recipe window high
    fOverlap        : REAL;               // 重叠长度 [摄氏度] / Overlap span
    bTouch         : BOOL;                // 仅端点相接 / Endpoints touching
    bCfgValid      : BOOL;                // 输入有效 / Inputs valid
    uRelErr        : UDINT;               // 事件码 / Event code
    bRejectRecipe  : BOOL := FALSE;       // 拒绝下发新配方 / Reject the new recipe
END_VAR

eRel := FC_DL_RangeOverlapCheck(fA1 := fSafeLo, fA2 := fSafeHi,
                                fB1 := fNewLo, fB2 := fNewHi,
                                bIncA := TRUE, bIncB := TRUE,
                                fOverlapSpan => fOverlap, bTouching => bTouch,
                                bValid => bCfgValid, uErrorId => uRelErr);

// 输入无效、部分重叠或包含关系一律拒绝下发（相接是否允许由工艺决定）
IF (NOT bCfgValid)
   OR (eRel = E_DL_RangeRelation.ePartial)
   OR (eRel = E_DL_RangeRelation.eContains) THEN
    bRejectRecipe := TRUE;
ELSE
    bRejectRecipe := FALSE;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **与三个单点判决件正交**：`FC_DL_LimitClassify`（单点 → 档位）/ `FC_DL_Hysteresis`（单点 + 历史 → 开关）/ `FB_DL_ToleranceWindow`（单点 → 布尔）均为单点件，本件是四点 → 关系枚举，不可互替。
- **零长度区间合法**：两端点相等的"A 点"参与全部关系判定，不特殊对待（可用来判"某设定点是否落在包络内"——本件会给 `eContains`）。
- **无除法、无开方、无循环、无数组**：不存在除零、溢出、越界三类风险，可在任意频次（含中断）调用。

---

## 33. FC_DL_CalcDistance3D ｜ 两点三维欧氏距离（R11，v1.0.0）

**定位 / Positioning**：视觉引导取料的定位偏差、三坐标/关节臂测点的空间距离、机器人工具中心点与围栏采样点的安全距离、堆垛高度校核。**平面场景不另设组件**：把两个端点的 Z 同时填 `0.0` 即为其退化情形（平方项自动为 0），不为凑数拆二维变体。

**大数缩放 / Scale guard**：先取三个分量差的最大绝对值作为量级基准；超阈值时改算 `SQRT((dX/s)² + (dY/s)² + (dZ/s)²) × s`——归一后每项绝对值不超过 1、平方和不超过 3，彻底规避「大数先平方再开方」的中间溢出，结果仍是同一数学量的稳定写法。此时 `bSaturated` 置位提示「已进入缩放置信区」，供质量追溯复核量纲。

**不返回 NaN**：非有限输入一律返回 `0.0` 并置码。NaN 会沿调用链污染下游滤波、比较与统计（历史教训），本件宁可给出一个明确的 0.0。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `fX1` | REAL | IN | — | mm | 点 1 X 坐标，量程 ±1.0E6 / Point 1 X |
| `fY1` | REAL | IN | — | mm | 点 1 Y 坐标 / Point 1 Y |
| `fZ1` | REAL | IN | — | mm | 点 1 Z 坐标，平面场景填 0.0 / Point 1 Z, 0.0 for planar use |
| `fX2` | REAL | IN | — | mm | 点 2 X 坐标 / Point 2 X |
| `fY2` | REAL | IN | — | mm | 点 2 Y 坐标 / Point 2 Y |
| `fZ2` | REAL | IN | — | mm | 点 2 Z 坐标 / Point 2 Z |
| `bValid` | BOOL | OUT | — | — | 六个输入全部有限 / All six inputs finite |
| `bSaturated` | BOOL | OUT | — | — | 本次进入大数缩放分支（结果仍有效）/ Large-number scale branch taken |
| `fDeltaX` | REAL | OUT | — | mm | X 分量差，便于判「差在哪个轴」/ X component delta |
| `fDeltaY` | REAL | OUT | — | mm | Y 分量差 / Y component delta |
| `fDeltaZ` | REAL | OUT | — | mm | Z 分量差 / Z component delta |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无；**全部信息级** / Event code, informational only |
| 返回值 / Return | REAL | RET | — | mm | 距离，恒非负；输入非法时返回 0.0 / Distance, never negative |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0122` | 信息级 | 输入含非有限值（任一轴），返回 0.0 且 `bValid` 置假，不输出有效分量差 | 查坐标源（视觉丢帧、未标定的传感器）；本件已阻断 NaN 扩散 |
| `0001_0219` | 信息级 | 模长超缩放阈值，已按缩放式求模，结果有效但进入置信区 | 复核量纲是否混用（如 mm 与 m 混算）；连续出现说明工艺量级已超出该件的设计域 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_VisionPickOffset
VAR
    fDist        : REAL;                 // 三维距离 [毫米] / 3D distance
    fNozzleX     : REAL := 120.0;        // 吸嘴当前 X [毫米] / Nozzle X
    fNozzleY     : REAL := 45.5;         // 吸嘴当前 Y [毫米] / Nozzle Y
    fNozzleZ     : REAL := -12.0;        // 吸嘴当前 Z [毫米] / Nozzle Z
    fTargetX     : REAL := 121.5;        // 视觉目标 X [毫米] / Target X
    fTargetY     : REAL := 44.0;         // 视觉目标 Y [毫米] / Target Y
    fTargetZ     : REAL := -11.0;        // 视觉目标 Z [毫米] / Target Z
    bGeomOk      : BOOL;                 // 几何有效 / Geometry valid
    bGeomScaled  : BOOL;                 // 进入缩放置信区 / Scaled branch taken
    fDx          : REAL;                 // X 偏差 [毫米] / X delta
    fDy          : REAL;                 // Y 偏差 [毫米] / Y delta
    fDz          : REAL;                 // Z 偏差 [毫米] / Z delta
    uGeomErr     : UDINT;                // 事件码 / Event code
    bMoveEnable  : BOOL := TRUE;         // 允许运动 / Motion allowed
END_VAR

fDist := FC_DL_CalcDistance3D(fX1 := fNozzleX, fY1 := fNozzleY, fZ1 := fNozzleZ,
                              fX2 := fTargetX, fY2 := fTargetY, fZ2 := fTargetZ,
                              bValid => bGeomOk, bSaturated => bGeomScaled,
                              fDeltaX => fDx, fDeltaY => fDy, fDeltaZ => fDz,
                              uErrorId => uGeomErr);

// 偏差超 50 毫米或几何无效时禁止动作（不做任何猜测性补偿）
IF (NOT bGeomOk) OR (fDist > 50.0) THEN
    bMoveEnable := FALSE;
END_IF
END_PROGRAM
```

**要点 / Notes**

- **单位随输入走**：输入输出统一按 `[mm]` 声明；调用方若用 `[m]` 注入，输出随之为 `[m]`，本件不做任何换算（换算属标定层职责）。
- **同一点是合法结果**：两点重合返回 `0.0`、`bValid = TRUE`、零码——距离为 0 不是异常。
- **负坐标天然正确**：差值平方后符号消失，`(−3, −4, 0)` 到原点得 5.0，无需任何分支。

---

## 34. FC_DL_RandomNext ｜ 可复现伪随机数与种子回灌（R11，v1.0.0）

**定位 / Positioning**：需要**可复现**的伪随机序列时使用——测试数据生成、随机抽样工位、防呆挑战码、仿真扰动注入。采用线性同余法（LCG，Numerical Recipes 公开参数：乘子 `1664525`、增量 `1013904223`，增量为奇数保证全周期）。函数本体**无内部状态**，种子经 `VAR_IN_OUT` 由调用方持有并逐拍回灌，因此可重入、可在中断里调用、结果完全可复现。

**不使用本件的场合 / Do not use**：安全相关（密钥、防作弊、真正不可预测的抽样）必须用平台提供的硬件随机源；本件 LCG 输出可被反推，**不具备密码学强度**。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `uSeed` | UDINT | IN | — | cnt | 当前种子，首次调用可给任意非零值 / Current seed |
| `bReseed` | BOOL | IN | — | — | `TRUE` 时强制从默认种子起步（序列重放）/ TRUE restarts from the default seed |
| `uNextSeed` | UDINT | OUT | — | cnt | 下一拍应回灌的种子 / Seed to feed back next call |
| `bZeroSeed` | BOOL | OUT | — | — | 输入种子为 0 的提示位（已用默认种子回退）/ Zero seed notice |
| `bSat` | BOOL | OUT | — | — | 结果已钳到上界容差内（防 `1.0` 越界）/ Result clamped below 1.0 |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无；**全部信息级** / Event code, informational only |
| 返回值 / Return | REAL | RET | — | — | 归一化随机数，半开区间 `[0.0, 1.0)` / Normalised value in `[0.0, 1.0)` |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0123` | 信息级 | 递推参数（乘子 / 增量）被改写为退化值，已回退到保底常数 | 仅在有人改过 `VAR CONSTANT` 时出现；回退后序列仍可用，但已非标准 LCG 序列 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_RandomStationPick
VAR
    fRand        : REAL;                 // 归一化随机数 [−] / Normalised random
    uSeed        : UDINT := 16#0000_0001;// 种子（由本程序持有并回灌）/ Carried seed
    uNextSeed    : UDINT;                // 下一拍种子 / Next seed
    bReseed      : BOOL := FALSE;        // 序列重放开关 / Replay switch
    bZeroSeed    : BOOL;                 // 零种子提示 / Zero seed notice
    bSat         : BOOL;                 // 上界钳位提示 / Upper clamp notice
    uRandErr     : UDINT;                // 事件码 / Event code
    nStationIdx  : INT;                  // 抽样工位号 1~8 / Sampled station 1 to 8
END_VAR

// 每周期取一个随机数，并把下一拍种子写回（顺序不可颠倒：先算后回灌）
fRand := FC_DL_RandomNext(uSeed := uSeed, bReseed := bReseed,
                          uNextSeed => uNextSeed, bZeroSeed => bZeroSeed,
                          bSat => bSat, uErrorId => uRandErr);
uSeed := uNextSeed;

// 映射到 1~8 号工位（乘 8 取整后加 1，fRand < 1.0 保证不越界）
nStationIdx := REAL_TO_INT(fRand * 8.0) + 1;
END_PROGRAM
```

**要点 / Notes**

- **种子必须回灌**：漏写 `uSeed := uNextSeed;` 会让每拍拿到同一个数（最常见的误用）。函数无内部状态，这是设计上的代价，换来可重入与可复现。
- **`bReseed` 用于重放**：调试期需要重复同一段随机序列时，给一次 `bReseed := TRUE` 即从默认种子重来。
- **零种子被兜底**：`uSeed = 0` 时用默认种子替代并置 `bZeroSeed`（LCG 在 0 种子下也能跑，但为避免"看起来没跑"的错觉而显式提示）。

---

## 35. FC_DL_PercentileLReal ｜ 定长样本任意分位值（R11，v1.0.0）

**定位 / Positioning**：节拍抖动 P95、称重偏差 P99、温度分布 P50 等现场统计判据。采用业界主流的 **R-7「排序 + 线性插值」** 口径（与主流统计库默认一致）：位置 `pos = (n − 1) × P`，取整数部分与小数部分做线性插值，单样本不外插。

**排序不变性 / Copy-sort invariance**：函数内部把有效样本**拷贝**到私有数组再排序，**调用方数组帧后保持原序**。这与库内 `FC_DL_QuickSortLReal`（就地排序、失败时内容未定义）语义**相反**，两者不可互换：前者零额外内存、后者多一份 64 元素副本但保证调用方数据不被踩。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `nCount` | INT | IN | — | 个 | 样本数，有效域 0~64；超上限按 64 截取 / Sample count, 0 to 64 |
| `fP` | REAL | IN | — | — | 分位点 0.0~1.0（0.95 即 P95），越界钳位 / Percentile, clamped |
| `afData` | ARRAY[1..64] OF LREAL | IN_OUT | — | 工程单位 | 样本数组，**只读语义**（块内拷贝，不写回）/ Sample array, read-only semantics |
| `fActualP` | REAL | OUT | — | — | 实际生效的分位点（钳位后），供 HMI 显示 / Effective percentile |
| `nGuard` | DINT | OUT | — | 次 | 排序与拷贝循环累计次数，防死锁兼性能诊断 / Loop counter |
| `bEmpty` | BOOL | OUT | — | — | 有效样本为空（含全部非有限 / 排序保护触发），返回 0.0 / Empty valid sample set |
| `uErrorId` | UDINT | OUT | — | — | 事件码，0 = 无；**全部信息级** / Event code, informational only |
| 返回值 / Return | LREAL | RET | — | 同样本 | 分位值；空集返回 0.0 / Percentile value, 0.0 when empty |

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0124` | 信息级 | 分位点或样本数越界已钳位 / 非有限样本已剔除 / 结果非有限已回退 | 查 `fActualP` 确认实际用的分位；样本数为 0 或全非有限时另见 `0002_000E` |
| `0002_000E` | 信息级 | 有效样本为空（含全部非有限与排序保护触发），返回 0.0 | 不要用 0.0 当"分位为 0"参与判据；先判 `bEmpty` 再用返回值（**跨段借用码，已在本子库版本记录登记**） |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_CycleTimeP95
VAR
    fP95          : LREAL;                       // 节拍 P95 [毫秒] / Cycle time P95
    afCycleMs     : ARRAY[1..64] OF LREAL;       // 节拍样本 [毫秒] / Cycle samples
    nSampleCnt    : INT := 32;                   // 有效样本数 / Valid sample count
    fActualP      : REAL;                        // 实际生效分位 / Effective percentile
    nGuard        : DINT;                        // 循环计数 / Loop counter
    bEmpty        : BOOL;                        // 空集 / Empty set
    uPctErr       : UDINT;                       // 事件码 / Event code
    nFillIdx      : INT := 1;                    // 采样写指针 / Sample write index
    fNewCycleMs   : LREAL := 0.0;                // 本件节拍 [毫秒] / New cycle time
    bCycleDone    : BOOL;                        // 单件完成 / Cycle finished
    bP95OverLimit : BOOL;                        // P95 超限 / P95 over limit
END_VAR

// 环形填样：满 32 个后从头覆盖，保持窗口恒定
IF bCycleDone AND (fNewCycleMs > 0.0) THEN
    afCycleMs[nFillIdx] := fNewCycleMs;
    nFillIdx := nFillIdx + 1;
    IF nFillIdx > nSampleCnt THEN
        nFillIdx := 1;
    END_IF
END_IF

// 求 P95；调用方数组不被改写，可继续用于其它统计
fP95 := FC_DL_PercentileLReal(nCount := nSampleCnt, fP := 0.95,
                              afData := afCycleMs,
                              fActualP => fActualP, nGuard => nGuard,
                              bEmpty => bEmpty, uErrorId => uPctErr);

// 空集时不判超限（0.0 不可当真实分位参与判据）
bP95OverLimit := (NOT bEmpty) AND (fP95 > LREAL#2500.0);
END_PROGRAM
```

**要点 / Notes**

- **`bEmpty` 必须先判**：空集返回 0.0 是"没有数据"的哨兵，不是"分位值为 0"；直接比较会把空集误判为合格。
- **非有限样本被剔除**：NaN / 无穷样本不参与排序，剔除后为空即按空集处理（置 `0002_000E`）。
- **`nGuard` 是性能探针**：正常 64 样本的插入排序远低于上限；若 `nGuard` 长期贴近上限，说明有人在超大窗口上调用本件（本件上限 64，更大窗口需分段统计）。

---

## 36. FC_DL_ArrayDiffSummary ｜ 数组逐项差异汇总（R12，v1.0.1）

**定位 / Positioning**：两组实数数组按**统一绝对容差**逐项比对，一次给出「超差项数、首个超差下标、最大绝对偏差及其下标、一致性结论、非有限标志」。服务对象是配方回读、双通道冗余比对、视觉参数下发校验——现场只判「有差异」却定位不到第几项、差多少；用等号判等又会被浮点噪声打成「永远不一致」。

**与搜索族边界 / Boundary**：`FC_DL_SearchMinMax` 在单数组内找极值、`FC_DL_ArraySearchFirst` 在单数组内按判据找首个命中，本件是**双数组逐项配对比较**并输出统计族，三者职责互斥。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `afExpected` | `ARRAY[1..64] OF REAL` | IN_OUT | — | 工程单位 | 期望值数组（基准侧），**只读不写** / Expected reference array, read only |
| `afActual` | `ARRAY[1..64] OF REAL` | IN_OUT | — | 工程单位 | 实际值数组（回读侧），**只读不写** / Actual readback array, read only |
| `nCount` | `INT` | IN | `1` | 项 | 参与比对项数，域 1~64，越界钳位 / Item count, 1..64, clamped |
| `fAbsTol` | `REAL` | IN | `0.01` | 工程单位 | 统一绝对容差，负值取绝对值、零值回落最小容差 / Absolute tolerance, negative folded, zero falls back |
| `nDiffCount` | `INT` | OUT | — | 项 | 超差项数（非有限项也计入）/ Out of tolerance item count |
| `nFirstDiffIdx` | `INT` | OUT | — | 索引 | 首个超差项下标，0 = 无超差 / First offending index, zero when none |
| `fMaxDev` | `REAL` | OUT | — | 工程单位 | 最大绝对偏差，只统计有限项 / Maximum absolute deviation over finite items |
| `nMaxDevIdx` | `INT` | OUT | — | 索引 | 最大偏差所在下标，0 = 未计算 / Index of the maximum deviation |
| `bEqual` | `BOOL` | OUT | — | — | 全部项在容差内**且**无非有限值 / All within tolerance and finite |
| `bNonFinite` | `BOOL` | OUT | — | — | 出现过非数或非有限项 / NaN or infinity encountered |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code, zero means none |
| `bValid` | `BOOL` | OUT | — | — | 项数与容差落在可服务域内（容差回退不否定结果）/ Count and tolerance serviceable |

状态枚举：无（纯函数）。函数返回值：`bEqual` 同值。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0134` | 信息级 | 比对项数越界，已钳到 1~64 | 超过 64 项请分段调用并自行汇总 |
| `0001_0135` | 信息级 | 容差非法（非有限或过小），已回退到最小容差 1E-9 | 容差填 0 几乎总是笔误；回退后噪声项可能被判超差 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_ParameterReadbackDiff
VAR
    afConfig     : ARRAY[1..64] OF REAL;   // 组态参数 / Configured parameters
    afReadback   : ARRAY[1..64] OF REAL;   // 设备回读参数 / Device readback
    nItems       : INT := 8;               // 比对本数 / Item count
    fTol         : REAL := 0.5;            // 统一容差 / Unified tolerance
    nBadCount    : INT;                    // 超差项数 / Out-of-tolerance count
    nFirstBad    : INT;                    // 首个超差下标 / First offender
    fWorstDev    : REAL;                   // 最大偏差 / Max deviation
    nWorstIdx    : INT;                    // 最大偏差下标 / Max deviation index
    bAllSame     : BOOL;                   // 全一致 / All consistent
    bHasBad      : BOOL;                   // 出现非有限值 / Non-finite seen
    uDiffErr     : UDINT;                  // 事件码 / Event code
    bDiffOk      : BOOL;                   // 参数可服务 / Serviceable
    bDiffDone    : BOOL;                   // 返回值（= bAllSame）/ Return value
    bCfgMismatch : BOOL;                   // 组态不一致 / Config mismatch
END_VAR

bDiffDone := FC_DL_ArrayDiffSummary(
                 afExpected := afConfig, afActual := afReadback,
                 nCount := nItems, fAbsTol := fTol,
                 nDiffCount => nBadCount, nFirstDiffIdx => nFirstBad,
                 fMaxDev => fWorstDev, nMaxDevIdx => nWorstIdx,
                 bEqual => bAllSame, bNonFinite => bHasBad,
                 uErrorId => uDiffErr, bValid => bDiffOk);

// 非有限值一律按不一致处理：NaN 会让后续任何比较都判假，不能当「差异为零」
bCfgMismatch := bDiffOk AND ((NOT bAllSame) OR bHasBad);
END_PROGRAM
```

**要点 / Notes**

- **非有限项计为超差**：NaN / 无穷不参与最大偏差竞争，但**计入** `nDiffCount` 并置 `bNonFinite`。这是有意的：传感器掉线时最危险的结论是「参数一致」，而不是「参数不一致」。
- **容差不做逐项**：本件只有一个统一绝对容差。需要逐项容差请用 `FB_DL_DeviceParamVerify`（`MANUAL_DL_Device.md`），它按项给容差并带核对周期语义。
- **偏差本身也会溢出**：v1.0.1 修的正是这条——两项**有限**值相减仍可能溢出为无穷（近满量程异号），原实现只判输入的有限性，「差」被污染成无穷后直接竞争成 `fMaxDev`（范式 R36 同源：中间量的值域是独立一层）。
- **并列取先出现者**：最大偏差并列时返回下标较小者，保证同输入同输出、便于复现与对比测试。

---

## 37. FC_DL_StringReplaceAll ｜ 定长串全量替换（R12，v1.0.1）

**定位 / Positioning**：定长字符串内**全部出现**的子串替换，一次调用给出替换次数、结果串与截断标志。服务对象是条码前缀规范化、报表模板占位符替换（百分号包裹的批次号与日期占位符）、设备商旧机型代号批量改新代号。

**推进律 / Cursor rule**：手写 `WHILE + FIND + DELETE + INSERT` 的典型事故是「替换串里含模式串」时缓冲自增长、永不退出扫描。本件把游标一律**跳到插入段之后**再继续查找，从算法层消灭该类死循环，另叠「次数上限」与「守卫计数」两道闸。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `sSource` | `STRING(255)` | IN | — | 字符 | 源串，最长 255 字符 / Source string, up to 255 characters |
| `sPattern` | `STRING(32)` | IN | — | 字符 | 被替换子串，长度为 0 视为非法 / Pattern to replace, empty is illegal |
| `sReplace` | `STRING(64)` | IN | — | 字符 | 替换子串，允许为空（即删除）/ Replacement, empty means delete |
| `nMaxReplace` | `INT` | IN | `32` | 次 | 替换次数上限，域 0~255，**0 = 不限** / Replacement limit, zero means unlimited |
| `nMaxLen` | `INT` | IN | `255` | 字符 | 结果串长度上限，域 1~255 / Result length limit |
| `sResult` | `STRING(255)` | OUT | — | 字符 | 替换结果，超长按 `nMaxLen` 截断 / Result, truncated to nMaxLen |
| `nReplaced` | `INT` | OUT | — | 次 | 实际替换次数（与函数返回值同值）/ Replacement count |
| `bTruncated` | `BOOL` | OUT | — | — | 结果被长度上限截断（含拼接超串型上限）/ Result was truncated |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code, zero means none |
| `bValid` | `BOOL` | OUT | — | — | 模式串非空、长度参数未钳位**且未达替换次数上限**（结果可直接采信）/ Result may be trusted as is |

状态枚举：无（纯函数）。函数返回值：`INT`，等于 `nReplaced`；异常路径返回 0。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0130` | 信息级 | 模式串为空，不允许替换，返回 0 次 | 空模式串在多数 `FIND` 实现上是未定义行为，本件直接拒 |
| `0001_0131` | 信息级 | 达到替换次数上限，结果不完整 | 上限用于防病态输入；正常模板替换请把上限设大于预期占位符个数 |
| `0001_0132` | 信息级 | 结果被长度上限截断（含拼接超串型上限 255），`bTruncated` 置位 | **尾部字段已被裁掉**；请缩短模板或分两段替换 |
| `0001_0133` | 信息级 | 次数上限或结果长度参数越界已钳位 | 次数上限 0~255、长度上限 1~255 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_ReportTemplateFill
VAR
    sTemplate   : STRING(255) := '%BATCH%-%DATE%';  // 报表模板 / Report template
    sBatchNo    : STRING(32) := 'B20261115';        // 批次号 / Batch number
    sOut1       : STRING(255);                      // 第一轮结果 / First pass result
    sOut2       : STRING(255);                      // 第二轮结果 / Second pass result
    nCnt1       : INT;                              // 第一轮替换次数 / First pass count
    nCnt2       : INT;                              // 第二轮替换次数 / Second pass count
    bTrunc1     : BOOL;                             // 第一轮截断 / First pass truncation
    bTrunc2     : BOOL;                             // 第二轮截断 / Second pass truncation
    uRepErr1    : UDINT;                            // 事件码 / Event code
    uRepErr2    : UDINT;                            // 事件码 / Event code
    bRepOk1     : BOOL;                             // 结果可采信 / Trustworthy
    bRepOk2     : BOOL;                             // 结果可采信 / Trustworthy
    nR1         : INT;                              // 返回值 / Return value
    nR2         : INT;                              // 返回值 / Return value
    bReportOk   : BOOL;                             // 报表可用 / Report usable
END_VAR

// 第一轮：批次号占位符
nR1 := FC_DL_StringReplaceAll(sSource := sTemplate, sPattern := '%BATCH%', sReplace := sBatchNo,
                              nMaxReplace := 8, nMaxLen := 200,
                              sResult => sOut1, nReplaced => nCnt1, bTruncated => bTrunc1,
                              uErrorId => uRepErr1, bValid => bRepOk1);

// 第二轮：日期占位符（以上一轮结果为源）
nR2 := FC_DL_StringReplaceAll(sSource := sOut1, sPattern := '%DATE%', sReplace := '2026-11-15',
                              nMaxReplace := 8, nMaxLen := 200,
                              sResult => sOut2, nReplaced => nCnt2, bTruncated => bTrunc2,
                              uErrorId => uRepErr2, bValid => bRepOk2);

// 两轮都完整、都没有截断，报表才可用
bReportOk := bRepOk1 AND bRepOk2 AND (NOT bTrunc1) AND (NOT bTrunc2)
             AND (nCnt1 = 1) AND (nCnt2 = 1);
END_PROGRAM
```

**要点 / Notes**

- **截断必须显式置位**：v1.0.1 修的正是这条（范式 R37）。原实现只在「结果长度 > 用户上限」时报 `0132`，而「拼接超过串型上限 255 被 `LEFT` 回夹」这一路**没有任何判据**——`bTruncated` 恒假、码永不置，现场表现为报表尾部字段被裁掉而调用方判定「结果完整」。现在 `CONCAT` 之前就预判长度，回夹只作溢出护栏。
- **`bValid` 是「结果可采信」而不是「参数合法」**：达次数上限（`0131`）时 `bValid` 为假，因为此时结果一定不完整。同一引脚兼两义容易误读，故引脚注释已写明（头注释另留「规格偏离留档 D1」）。
- **空替换串 = 删除**：`sReplace = ''` 合法，等价于删除所有模式串出现。若想「替换成空但要保留分隔」，请显式填一个空格。
- **返回 0 不等于没替换**：异常路径（模式为空 / 越界早退）返回 0；正常路径替换 0 次也返回 0。判定是否异常请看 `uErrorId`。

---

## 38. FB_DL_StringTokenStream ｜ 报文分词流（R12，v1.0.1）

**定位 / Positioning**：把一条报文按分隔符**逐拍**切成段，一次请求给一段。服务对象是「段数多、每段要单独处理」的协议解析：条码分段、CSV 行字段、设备应答的多字段串。与 `FC_DL_StringSplit`（一次性拆完、保留空字段）互补——本件把「拆」摊到多拍，便于每段独立做校验与入库。

**字段序号对齐 / Index alignment**：空段**照占一个序号**。这是字段序号对齐的唯一保证：`A,,C` 的第 2 段是空串而不是 `C`，否则后续所有字段错位一格。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `bEnable` | `BOOL` | IN | — | — | 使能；`FALSE` 时冻结游标并保持全部输出 / Enable, freezes the cursor when FALSE |
| `bReset` | `BOOL` | IN | — | — | 上升沿回帧起点并清故障 / Rising edge rewinds to the frame start |
| `sFrame` | `STRING(255)` | IN | — | 字符 | 待分词报文，内容变化自动重装载 / Frame to tokenise, reloaded on change |
| `sDelimiter` | `STRING(4)` | IN | — | 字符 | 分隔符（1~4 字符），**空 = 故障** / Delimiter of one to four characters |
| `bNext` | `BOOL` | IN | — | — | 上升沿取下一段 / Rising edge advances to the next token |
| `nMaxTokenLen` | `INT` | IN | `32` | 字符 | 单段最大长度，域 1~64，越界钳位 / Maximum token length, 1..64 |
| `nMaxTokens` | `INT` | IN | `32` | 段 | 单帧最大段数，域 1~64，越界钳位 / Maximum token count, 1..64 |
| `sToken` | `STRING(64)` | OUT | — | 字符 | 本段内容，超长截断 / Current token, truncated when too long |
| `nTokenIdx` | `INT` | OUT | — | 索引 | 本段序号，1 起 / Token index, one based |
| `nTokenCount` | `INT` | OUT | — | 段 | 本帧已产出段数 / Tokens produced so far |
| `bValidToken` | `BOOL` | OUT | — | — | 本段非空（连续分隔符产生的空段为 `FALSE`）/ Non-empty token |
| `bDone` | `BOOL` | OUT | — | — | 已到末段之后，保持到重装载或复位 / End of frame reached |
| `bError` | `BOOL` | OUT | — | — | 故障级锁存，仅 `021C` / `021D` / `021E` 置位 / Latched fault |
| `uErrorId` | `UDINT` | OUT | — | — | 事件 / 故障码，0 = 无 / Event or fault code |
| `eState` | `E_DL_TokenPhase` | OUT | — | — | `eIdle` 0 ／ `eReady` 10 ／ `eDraining` 20 ／ `eFault` 99 / Current phase |

状态枚举：`E_DL_TokenPhase`（`eIdle` 0 ／ `eReady` 10 ／ `eDraining` 20 ／ `eFault` 99）。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_013A` | 信息级 | 切出空段（连续分隔符），序号照占、`bValidToken` 为假 | 空段通常意味着上游多打了一个分隔符，请在字段校验里显式处理 |
| `0001_013B` | 信息级 | 段长超限已截断，`sToken` 为前缀 | 加长 `nMaxTokenLen` 或先把长字段拆开 |
| `0001_013C` | 信息级 | 末段之后再次取段，序号不回绕、内容置空、`bDone` 保持 | 正常收尾路径；若频繁出现说明取段节拍快于段数 |
| `0001_021C` | 故障级 | 分隔符为空（`FIND` 空模式跨平台不一致），硬闸锁存 | 分隔符至少 1 字符；改正后给 `bReset` |
| `0001_021D` | 故障级 | 段数达到上限，继续解析会推过调用方预期，锁存并掐断游标 | 提高 `nMaxTokens` 或核对协议段数 |
| `0001_021E` | 故障级 | 非法相位兜底（枚举被在线改坏或跨版本不兼容） | 检查在线修改与库版本，复位后恢复 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_BarcodeFields
VAR
    fbToken     : FB_DL_StringTokenStream;   // 分词实例 / Tokeniser instance
    sBarcode    : STRING(255) := 'P01;A12;;20261115';  // 扫码结果 / Scanned code
    bTakeNext   : BOOL;                      // 取下一段请求 / Take next token
    bRewind     : BOOL;                      // 回帧起点 / Rewind
    bRunning    : BOOL := TRUE;              // 采集运行 / Collector running
    sField      : STRING(64);                // 当前字段 / Current field
    nFieldNo    : INT;                       // 当前字段号 / Field number
    nFieldCnt   : INT;                       // 已取字段数 / Fields taken
    bFieldOk    : BOOL;                      // 字段非空 / Field non-empty
    bAllTaken   : BOOL;                      // 已取完 / All taken
    bTokFault   : BOOL;                      // 故障 / Fault
    uTokErr     : UDINT;                     // 事件码 / Event code
    eTokState   : E_DL_TokenPhase;           // 相位观测 / Phase
    bField3Good : BOOL;                      // 第 3 字段为空则 NG / Third field must not be empty
END_VAR

fbToken(bEnable := bRunning, bReset := bRewind,
        sFrame := sBarcode, sDelimiter := ';', bNext := bTakeNext,
        nMaxTokenLen := 32, nMaxTokens := 16,
        sToken => sField, nTokenIdx => nFieldNo, nTokenCount => nFieldCnt,
        bValidToken => bFieldOk, bDone => bAllTaken,
        bError => bTokFault, uErrorId => uTokErr, eState => eTokState);

// 第 3 字段按协议必须非空；空段仍占序号，故序号不会错位
bField3Good := (nFieldNo <> 3) OR bFieldOk;
END_PROGRAM
```

**要点 / Notes**

- **一律从锁存副本切片**：v1.0.1 修的正是这条（范式 R38）。取段相位原用**实时帧长度**做边界与 `MID` 长度，却对**锁存副本**切片——调用方在「请求拍 → 取段拍」之间改写 `sFrame`，新帧更长时会切出 `bValidToken = TRUE` 的空段，新帧更短时会把仍有内容的锁存帧判成「已读完」并吐 `013C`。现在取段相位入口重算锁存长度，实时长度只留给帧变化检测。
- **帧变化用逐字符比较**：等长改写（两个字段互换位置）会让「长度差值」判据漏判，逐字符比较是唯一可靠判据。代价是每拍一次 O(n) 扫描，255 字符以内可接受。
- **`bDone` 是保持型**：不是单拍脉冲。上层若每拍轮询 `bDone`，单拍脉冲极易漏采，故本件取「保持到重装载或复位」。
- **空段仍占序号**：不要把 `bValidToken = FALSE` 当成「跳过该字段」，它意味着「该字段是空的」。序号的连续性优先于「只给有内容的段」。
- **分隔符上限 4 字符**：多字符分隔符按整串匹配（如 `||`），不是任一字符匹配。

---

## 39. FC_DL_SolarPositionCalc ｜ 太阳位置计算（R12，v1.0.0）

**定位 / Positioning**：由「年月日时分 + 经纬度 + 时区偏移」算出太阳赤纬、时角、高度角、方位角与均时差，供遮阳控制、光伏跟踪、日照时段判定使用。全部按公开天文近似式（年角 → 赤纬与均时差 → 真太阳时 → 时角 → 高度角与方位角）实现，误差量级适合楼宇控制（分钟级），不用于天文定标。

**日期校验 / Date check**：月份天数按当月实际天数校验（含闰年二月 29 日），日超当月天数直接判非法并早退，**不做夹取**——把 2 月 30 日夹成 2 月 28 日会让日照统计出现无法解释的跳变。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `nYear` | `INT` | IN | — | 年 | 年，域 1970~2100 / Year, 1970..2100 |
| `nMonth` | `INT` | IN | — | 月 | 月，域 1~12 / Month, 1..12 |
| `nDay` | `INT` | IN | — | 日 | 日，域 1~31，按当月实际天数校验 / Day checked against the month |
| `nHour` | `INT` | IN | — | h | 时，域 0~23，**本地标准时** / Hour, local standard time |
| `nMinute` | `INT` | IN | — | min | 分，域 0~59 / Minute, 0..59 |
| `fLatitude` | `REAL` | IN | — | 度 | 纬度，北纬为正，域 −90~90 / Latitude, north positive |
| `fLongitude` | `REAL` | IN | — | 度 | 经度，东经为正，域 −180~180 / Longitude, east positive |
| `nUtcOffsetMin` | `INT` | IN | `480` | min | 本地时区偏移，东八区 = 480 / Time zone offset in minutes |
| `fDeclination` | `REAL` | OUT | — | 度 | 太阳赤纬，约 −23.45~+23.45 / Solar declination |
| `fHourAngle` | `REAL` | OUT | — | 度 | 时角，正午为 0、下午为正 / Hour angle |
| `fElevation` | `REAL` | OUT | — | 度 | 太阳高度角，地平线上为正 / Solar elevation |
| `fAzimuth` | `REAL` | OUT | — | 度 | 方位角，正北 0 顺时针增 / Azimuth clockwise from north |
| `fEquationOfTime` | `REAL` | OUT | — | min | 均时差 / Equation of time |
| `bSunUp` | `BOOL` | OUT | — | — | 高度角 > 0 / Sun above the horizon |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code |
| `bValid` | `BOOL` | OUT | — | — | 日期、时区、经纬度均合法 / All inputs legal |

状态枚举：无（纯函数）。函数返回值：`REAL`，等于 `fElevation`。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0136` | 信息级 | 年月时分 / 经纬度 / 时区偏移越界，本拍判定不可信，全部角度出口归 0 | 时区偏移上限 ±840 min；夏令时请在外层换算后再传入 |
| `0001_0137` | 信息级 | 日超出当月实际天数（含闰年判定），判定不可信 | 2 月 29 日只在闰年合法；请核对日历源 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_ShadeControl
VAR
    fDecl      : REAL;                     // 赤纬 [度] / Declination
    fHa        : REAL;                     // 时角 [度] / Hour angle
    fElev      : REAL;                     // 高度角 [度] / Elevation
    fAzim      : REAL;                     // 方位角 [度] / Azimuth
    fEot       : REAL;                     // 均时差 [min] / Equation of time
    bSunUp     : BOOL;                     // 日出后 / Sun up
    uSunErr    : UDINT;                    // 事件码 / Event code
    bSunOk     : BOOL;                     // 输入合法 / Inputs legal
    fElevOut   : REAL;                     // 返回值（= 高度角）/ Return value
    nHmiYear   : INT := 2026;              // HMI 注入 / From HMI
    nHmiMonth  : INT := 11;
    nHmiDay    : INT := 15;
    nHmiHour   : INT := 14;
    nHmiMin    : INT := 30;
    bShadeDown : BOOL;                     // 遮阳放下 / Shade deployed
END_VAR

// 上海（北纬 31.23、东经 121.47、东八区）
fElevOut := FC_DL_SolarPositionCalc(
                nYear := nHmiYear, nMonth := nHmiMonth, nDay := nHmiDay,
                nHour := nHmiHour, nMinute := nHmiMin,
                fLatitude := 31.23, fLongitude := 121.47, nUtcOffsetMin := 480,
                fDeclination => fDecl, fHourAngle => fHa, fElevation => fElev,
                fAzimuth => fAzim, fEquationOfTime => fEot,
                bSunUp => bSunUp, uErrorId => uSunErr, bValid => bSunOk);

// 西晒面（方位角 210~300 度）且太阳在 5 度以上才放遮阳；输入非法一律不放
bShadeDown := bSunOk AND bSunUp AND (fElev > 5.0) AND (fAzim > 210.0) AND (fAzim < 300.0);
END_PROGRAM
```

**要点 / Notes**

- **时区与夏令时**：本件只接受「本地标准时 + 固定偏移」，**不做夏令时换算**。有夏令时的地区请在外层把偏移量改掉（如东八区无夏令时恒 480；中欧夏令时 120 而非 60）。
- **天顶不可辨**：高度角接近 90° 时方位角在数学上病态（分母趋零），本件按 `89.5°` 阈值显式兜底，而不是输出一个乱跳的方位角。遮阳控制逻辑请对「高度角 > 85°」单独处理（此时太阳近乎当头，按方位判西晒无意义）。
- **零平台时钟**：年月日时分全部引脚注入，本件不读 `TIME` / `DT` 系统时钟，也不猜时区。时间源由调用方负责（HMI 对时、NTP 块输出）。
- **误差口径**：均时差按年角的公开近似式，年内误差约 ±30 s 量级；赤纬误差约 ±0.5°，对楼宇遮阳（阈值通常取 5~10°）足够，**不可**用于光伏跟踪的高精度对日。

---

## 40. FC_DL_ModbusExceptionParse ｜ Modbus 异常帧解析与重试建议（R12，v1.0.0）

**定位 / Positioning**：解析 Modbus 响应中的**异常帧**（功能码最高位置位），还原原始功能码、给出异常码中文名、严重度分级（提示 / 告警 / 故障）与「可原样重试」标志，直接驱动上层的重试策略。服务对象是所有 Modbus RTU / TCP 主站：把「异常码 → 该不该重试」这张表从每个项目的 `CASE` 里收回到库里。

**为什么必须分级 / Why grade**：`01` 非法功能、`02` 非法数据地址是**组态错**，重试一万次也一样；`05` 确认处理中、`06` 从站忙是**时序问题**，短退避后再发就能过。统一按「失败」处理会让组态错掩盖成通讯抖动，反之会让从站忙被当成硬件故障停机。

### 接口 / Interface

| 引脚 / Pin | 类型 / Type | 方向 / Dir | 默认 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `uFuncCode` | `USINT` | IN | — | 位串 | 响应功能码原值，**最高位置位 = 异常帧** / Raw response function code, top bit set means exception |
| `uExcCode` | `USINT` | IN | — | 代码 | 异常码，仅在异常帧有效 / Exception code, valid only on exception frames |
| `bIsException` | `BOOL` | OUT | — | — | 是异常帧为真 / Exception frame detected |
| `nOrigFunc` | `INT` | OUT | — | 代码 | 原始功能码（去掉最高位），0 = 非法 / Original function code without the top bit |
| `sExcName` | `STRING(40)` | OUT | — | 文本 | 异常码中文名，未定义码给「未定义异常码」/ Chinese name of the exception code |
| `eSeverity` | `E_DL_ModbusExcSeverity` | OUT | — | — | 严重度：`eInfo` 0 ／ `eWarn` 10 ／ `eFault` 20 / Severity class |
| `bRetryable` | `BOOL` | OUT | — | — | 可原样重试为真 / Safe to retry unchanged |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码，0 = 无事件 / Event code |
| `bValid` | `BOOL` | OUT | — | — | 帧结构可解释为真 / Frame interpretable |

状态枚举：`E_DL_ModbusExcSeverity`（`eInfo` 0 提示级 / `eWarn` 10 告警级可重试 / `eFault` 20 故障级须人工介入）。函数返回值：**解析成功标志**，仅 `uErrorId = 0` 时为 `TRUE`（即 `bValid` 同值）；非异常帧会置 `0139` 并返回 `FALSE`，属提示而非故障。

### 故障码表 / Error Code Table

| 码位 / Code | 级别 | 语义 / Meaning | 处理建议 / Action |
|---|---|---|---|
| `0001_0138` | 信息级 | 功能码非法（去标志位后为 0）或异常码未定义（超出规范上限 `16#0B`），帧可解释但语义未知 | 按故障级处理并记录原始字节；未定义码通常是厂商私有扩展 |
| `0001_0139` | 信息级 | 本帧非异常帧（功能码最高位未置位），`bIsException` 为假 | 正常路径；此时 `uExcCode` 无意义，请勿解读 |

### 调用示例 / Example（完整可编译 / Complete and compilable）

```iecst
PROGRAM PRG_ModbusRetryPolicy
VAR
    uRespFunc    : USINT := 16#83;          // 响应功能码（83 = 03 异常）/ Response function code
    uRespExc     : USINT := 16#06;          // 异常码（从站忙）/ Exception code
    bIsExc       : BOOL;                    // 是否异常帧 / Exception frame
    nOrigFunc    : INT;                     // 原始功能码 / Original function code
    sExcText     : STRING(40);              // 异常码名称 / Exception name
    eSev         : E_DL_ModbusExcSeverity;  // 严重度 / Severity
    bCanRetry    : BOOL;                    // 可重试 / Retryable
    uExcErr      : UDINT;                   // 事件码 / Event code
    bExcOk       : BOOL;                    // 可解释 / Interpretable
    bExcDone     : BOOL;                    // 返回值（= bIsExc）/ Return value
    nRetryBudget  : INT := 3;               // 剩余重试次数 / Remaining retries
    bRaiseAlarm  : BOOL;                    // 需人工介入 / Needs attention
END_VAR

bExcDone := FC_DL_ModbusExceptionParse(
                uFuncCode := uRespFunc, uExcCode := uRespExc,
                bIsException => bIsExc, nOrigFunc => nOrigFunc, sExcName => sExcText,
                eSeverity => eSev, bRetryable => bCanRetry,
                uErrorId => uExcErr, bValid => bExcOk);

// 可重试才扣预算；故障级或预算耗尽才报警
IF bIsExc AND bCanRetry AND (nRetryBudget > 0) THEN
    nRetryBudget := nRetryBudget - 1;
END_IF
bRaiseAlarm := bIsExc AND ((eSev = E_DL_ModbusExcSeverity.eFault) OR (nRetryBudget = 0));
END_PROGRAM
```

**要点 / Notes**

- **异常码 → 严重度对照**：`01` 非法功能 / `02` 非法数据地址 / `03` 非法数据值 / `08` 存储奇偶校验错 → **故障级不可重试**；`04` 从站设备故障 → 故障级**可重试**（设备可能自恢复）；`05` 确认处理中 / `06` 从站设备忙 / `0A` 网关路径不可用 / `0B` 网关目标无响应 → **告警级可重试**。
- **未定义码仍给文字**：`sExcName` 会给「未定义异常码」或「未定义异常码（超出规范上限）」，便于 HMI 直接显示；但 `bValid` 为假、`0138` 置位，**不得**按「解析成功」处理。
- **非异常帧不是故障**：`uErrorId = 0139` 表示「本帧本来就不是异常帧」，属**提示级**路径（函数返回 `FALSE`、`bValid` 为假，因为它没解析出异常语义）。若主站把每个正常响应都送进来解析，这个码会每拍出现——请在调用前先用最高位判定，或接受该码作为「无异常」的显式回执。
- **不做帧校验**：本件只解析「已确认是异常帧的两个字节」，CRC、长度、地址匹配归传输层。把 CRC 错误也送进来会让异常码被误读。

---

## 41. FC_DL_Crc8 ｜ 参数化 8 位 CRC 校验（R13，v1.0.0 ｜ CRC8 子族开族）

**定位**：参数化 MSB-first 的 CRC-8 逐位算法，覆盖 ATM、SAE-J1850、HITAG 三个变体，补齐本库 CRC 族的 8 位宽度（既有件：`FC_DL_Crc16Modbus` 16 位反射型、`FC_DL_Crc32Ethernet` 32 位、`FC_DL_LrcChecksum` 纵向加和）。逐位算法无查表、无状态、内存占用恒定。典型用途：SMBus 与多数传感器帧的 8 位校验、汽车与部分变频器状态帧的 SAE-J1850 校验、HITAG 类标签读写、自定义短帧协议「厂家只给多项式不给算法」时的快速对齐。

**变体参数表 / Variant parameters**：`eCrc8Atm` 多项式 16#07 初值 16#00 终值 16#00（SMBus 与传感器帧）｜ `eCrc8SaeJ1850` 多项式 16#1D 初值 16#FF 终值 16#FF（汽车与变频器状态帧）｜ `eCrc8Hitag` 多项式 16#1D 初值 16#FF 终值 16#00（同族不同终值约定）。**反射型 MAXIM-DOW 一族位序相反，明确不并入本件枚举**，留作后续独立件。

### 41.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `aData` | `ARRAY[1..128] OF BYTE` | IN | — | 字节 | 数据缓冲区，定长 128，未用位填 0 / Data buffer, fixed 128 bytes |
| `nLen` | `INT` | IN | — | 个 | 有效字节数，域 1~128；超上限按截断规则处理（先置标志再钳长）/ Valid byte count, truncated above the limit |
| `eVar` | `E_DL_Crc8Variant` | IN | `eCrc8Atm` | — | 变体选择；非法值回退 ATM 并置 0142 / Variant selector, illegal falls back to ATM |
| 返回值 | `BYTE` | 返回 | — | — | CRC-8 校验值 / CRC-8 value |
| `nProcessed` | `INT` | OUT | — | 个 | 实际参与计算的字节数，域 0~128 / Bytes actually processed |
| `bTruncated` | `BOOL` | OUT | — | — | 超上限被截断；截断发生时必须为真（R37：绝不静默按 128 算却报完整）/ TRUE whenever truncation happened |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码 / Event code |

### 41.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无事件 / No event | — |
| `16#0001_0141` | 信息级：长度超 128 已显式截断，校验值只覆盖前 128 字节 / Truncated to 128 | **不得**把截断下的校验值当整帧结果使用；改用分块链式或换 16 位件 |
| `16#0001_0142` | 信息级：变体非法，按 ATM 参数计算并返回 / Illegal variant, ATM fallback | 结果与 ATM 一致，便于现场与厂家校验工具对表；修正变体来源 |
| `16#0001_0221` | 故障级：有效字节数 < 1 / Illegal length | 修正帧长来源 |

### 41.3 调用示例 / Example

```iecst
PROGRAM PRG_SensorFrameCheck
VAR
    aFrame    : ARRAY[1..128] OF BYTE;  // 传感器应答帧 / Sensor reply frame
    nFrameLen : INT;                    // 有效帧长 / Frame length
    uCalcCrc  : BYTE;                   // 本件算出的校验值 / Computed CRC
    nUsed     : INT;                    // 实际参与字节数 / Bytes processed
    bCut      : BOOL;                   // 截断标志 / Truncation flag
    uCrcCode  : UDINT;                  // 事件码 / Event code
    bFrameOk  : BOOL;                   // 帧校验结论 / Frame verdict
END_VAR

uCrcCalc := FC_DL_Crc8(
                aData      := aFrame,
                nLen       := nFrameLen,
                eVar       := E_DL_Crc8Variant.eCrc8Atm,
                nProcessed => nUsed,
                bTruncated => bCut,
                uErrorId   => uCrcCode);

// 尾字节为发送端 CRC：只有非截断时才比对
bFrameOk := (NOT bCut) AND (uCrcCalc = aFrame[nFrameLen]);
END_PROGRAM
```

### 41.4 要点 / Notes

- **验收向量已三方一致**：标准串 `"123456789"` 实算 ATM = `16#F4`、SAE-J1850 = `16#4B`、HITAG = `16#B4`，与公开 CRC 参数目录 check 值一致（终审独立复现确认，规格向量无勘误）。
- **截断必须显式**：帧长超 128 时先置 `bTruncated` 再钳长——拿截断校验值当整帧比对是「校验总差一个固定值」类现场谜题的常见根源。
- **变体非法回退 ATM 而非返回零**：给一个可复算的值，现场才能与厂家工具对表定位；返回零只会制造「协议两边算的不一样」悬案。
- **「先判最高位 → 左移 → 条件异或」顺序不可颠倒**：写反会得到另一族校验值，现象是「校验总是差一个固定值」，在总线上极难查出。

---

## 42. FC_DL_StringToLReal ｜ 带校验的字符串转 LREAL（R13，v1.0.0）

**定位**：把定长 ASCII 文本严格解析成 LREAL，逐字符七态状态机推进，拒绝一切可疑输入并报出**首个非法字符的位置**。不调用平台的隐式串转数值功能，因此：① 非法输入行为三平台完全一致；② 出错能回答「错在第几个字符」；③ 前缀合法、尾部夹脏字符时仍给前缀值，便于判断是报文截断还是字段串位。典型用途：条码与二维码文本入库、CSV 报文列解析、HMI 手输设定值校验、第三方仪表 ASCII 应答的数值字段提取。

**为什么自带解析**：三家平台对「字符串转实数」的非法输入行为不一致（返回零 / 抛异常 / 静默截断），且都不告诉调用方错在第几位。现场最贵的不是「转换失败」，而是「转换成功了但值不对」。

### 42.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `sText` | `STRING(40)` | IN | — | ASCII | 待解析文本，冗余位填空格或空 / Text to parse |
| `bAllowExp` | `BOOL` | IN | `TRUE` | — | 允许指数部（大小写 E 均接受）；FALSE 时指数判非法并给前缀值 / Allow the exponent part |
| `fMin` / `fMax` | `LREAL` | IN | `−1.0E30` / `1.0E30` | 工程单位 | 出口夹域上下限（倒置自动归正，不报错）；无论成败输出必落域内 / Exit clamp bounds |
| 返回值 | `BOOL` | 返回 | — | — | TRUE = 语法与数值均通过（含夹域 0145 的成功） / TRUE on success |
| `fValue` | `LREAL` | OUT | — | 工程单位 | 解析结果；失败时保留已解析前缀值 / Parsed value, prefix kept on failure |
| `nCharUsed` | `INT` | OUT | — | 个 | 已消费字符数，域 0~40 / Characters consumed |
| `nBadPos` | `INT` | OUT | — | 位 | 首个非法字符位置（1 起），0 = 全部合法 / First invalid position, one based |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码 / Event code |

**语法 / Grammar**：可选符号、整数部、可选小数部、可选指数部；只有符号 / 只有小数点 / 只有指数标记的半截输入在终态校验被拦截。

### 42.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无事件 / No event | — |
| `16#0001_0143` | 信息级：全空白或无有效数字 / Blank or no digits | 检查字段来源；消费 0 字符 |
| `16#0001_0144` | 信息级：尾随非法字符（前缀值保留）/ Trailing junk | `nBadPos` 给出位置；判断是报文截断还是字段串位 |
| `16#0001_0145` | 信息级：结果已夹进出口域 / Clamped to exit bounds | 夹域不算失败（返回 TRUE）；检查上下限与量纲 |
| `16#0001_0146` | 信息级：指数超 ±38 保护域，值落有限上界 / Exponent out of protection band | 上电寄存器乱值常见；值已夹到 `fMax` 不输出无穷 |
| `16#0001_0222` | 故障级：小数点重复 / Repeated decimal point | `12.5.3` 类输入；消费数与错误位同时给出 |
| `16#0001_0223` | 故障级：解析结果非有限 / Non-finite result | 拦截 Inf 与 NaN，值夹域后输出 |

### 42.3 调用示例 / Example

```iecst
PROGRAM PRG_HmiSetpoint
VAR
    sEntry    : STRING(40);       // HMI 手输设定值 / HMI manual entry
    fSp       : LREAL;           // 解析结果 / Parsed value
    nUsed     : INT;             // 消费字符数 / Characters consumed
    nBad      : INT;             // 首错位 / First bad position
    uSpCode   : UDINT;           // 事件码 / Event code
    bSpOk     : BOOL;            // 解析成功 / Parse success
    bSpAccepted : BOOL;          // 最终受理 / Finally accepted
END_VAR

bSpOk := FC_DL_StringToLReal(
             sText     := sEntry,
             bAllowExp := FALSE,          // 设定值不允许指数写法 / no exponent for setpoints
             fMin      := 0.0,
             fMax      := 850.0,          // 烘箱域 [degC] / oven domain
             fValue    => fSp,
             nCharUsed => nUsed,
             nBadPos   => nBad,
             uErrorId  => uSpCode);

// 成功且整串消费才受理；夹域（0145）也算成功但提示边界
bSpAccepted := bSpOk AND (nUsed >= LEN(sEntry));
IF bSpAccepted AND (uSpCode = 16#0001_0145) THEN
    ;   // HMI 提示「已夹到限值」
END_IF
END_PROGRAM
```

### 42.4 要点 / Notes

- **失败 ≠ 值无效**：`12.5.3` 解析失败但 `fValue = 12.5`、`nCharUsed = 4`——前缀信息让现场能区分「截断」与「串位」，这是本件相对平台转换函数的核心增值。
- **出口夹域是承诺**：无论成败 `fValue` 必落 `[fMin, fMax]`，绝不输出无穷或非数；下游不需再判有限性。
- **有效数字 18 位封顶**：超出 LREAL 可表示精度后只损失超精度位，对结果无语义影响。
- **长度一次锁存（R38）**：入口取 `LEN` 存副本，其后全部循环上界取自副本；调用方在返回前改写文本缓冲不影响结果。
- 纯函数：无内部状态、同入参同结果。

---

## 43. FC_DL_StringFixedField ｜ 定宽字段填充与对齐（R13，v1.0.0 ｜ R37 全库样板件）

**定位**：把任意文本装进定宽字段（左对齐或右对齐、指定填充字符），裁剪时显式置截断标志与事件码。本件是把范式 **R37（定长串截断必须显式置位）** 变成可复制写法的样板：全库所有「往定长缓冲写串」的地方都可以照抄其四步顺序——先取一次源长度 → 与目标宽度比较 → 先置截断标志与码 → 最后才写缓冲。顺序一旦颠倒（先拼再回夹、或回夹不置标志），现场就会出现「字段看着对、内容被砍一半、日志一个字没有」的事故。典型用途：定长报文拼装、CSV 列对齐、HMI 固定列显示、条形码定长补位、打印模板等宽排版。

### 43.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `sValue` | `STRING(255)` | IN | — | ASCII | 源文本 / Source text |
| `nWidth` | `INT` | IN | — | 字符 | 目标字段宽度，域 1~255；**域外直接拒绝不钳位**（宽度是契约，猜不得）/ Target width, rejected outside |
| `sPad` | `STRING(1)` | IN | `' '` | 字符 | 填充字符，只取首字符；空串退回空格并置 0149 / Pad character |
| `bAlignRight` | `BOOL` | IN | `FALSE` | — | TRUE 右对齐（左补填充），FALSE 左对齐 / TRUE right aligns |
| `bAllowTrunc` | `BOOL` | IN | `FALSE` | — | TRUE 超宽裁剪写出（置 0147），FALSE 拒绝构造（置 0148）/ TRUE truncates and writes |
| 返回值 | `BOOL` | 返回 | — | — | TRUE = 字段已构造 / TRUE when the field was built |
| `sField` | `STRING(255)` | OUT | — | ASCII | 定宽字段，成功时长度恰为宽度 / Fixed-width field |
| `bTruncated` | `BOOL` | OUT | — | — | 是否发生裁剪；拒绝路上也为 TRUE（事实留痕）/ TRUE whenever truncation happened |
| `nWritten` | `INT` | OUT | — | 字符 | 实际字段长度，域 0~255 / Field length written |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码 / Event code |

### 43.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无事件 / No event | — |
| `16#0001_0147` | 信息级：源超宽已按允许截断 / Truncated as allowed | 结果可用但**不完整**；下游判读必须并看 `bTruncated` |
| `16#0001_0148` | 信息级：源超宽且不允许截断，拒绝构造（字段空串、写出 0）/ Rejected, refused to build | 放宽宽度或允许截断；`bTruncated` 仍为 TRUE（事实发生了，只是没写出去） |
| `16#0001_0149` | 信息级：填充串为空，退回空格 / Empty pad, space fallback | 字段仍按宽度构造 |
| `16#0001_0224` | 故障级：宽度域外（0 或 > 255） / Illegal width | 修正宽度来源；不钳位、不猜 |

码位优先级：`0224` > `0148` > `0147` > `0149`，单点写入。

### 43.3 调用示例 / Example

```iecst
PROGRAM PRG_LogLine
VAR
    sBatchId  : STRING(255);   // 批次号（来源可超宽）/ Batch id
    sField    : STRING(255);   // 定宽字段 / Fixed field
    bCut      : BOOL;          // 截断标志 / Truncation flag
    nLen      : INT;           // 实际字段长度 / Field length
    uFldCode  : UDINT;         // 事件码 / Event code
    bBuilt    : BOOL;          // 构造成功 / Built
END_VAR

// 日志列宽 12、左对齐、空格填充；超宽裁剪但必须留痕
bBuilt := FC_DL_StringFixedField(
              sValue      := sBatchId,
              nWidth      := 12,
              sPad        := ' ',
              bAlignRight := FALSE,
              bAllowTrunc := TRUE,
              sField      => sField,
              bTruncated  => bCut,
              nWritten    => nLen,
              uErrorId    => uFldCode);

// 截断进日志：0147 出现即字段不完整，审计时能对上
IF bCut THEN
    ;   // 附加「源被截断」备注列
END_IF
END_PROGRAM
```

### 43.4 要点 / Notes

- **R37 四步顺序（全库可照抄）**：`LEN` 一次锁存 → 与 `MIN(nWidth, 255)` 比较 → `bTruncated := TRUE` 先于任何写入 → 按 `bAllowTrunc` 分「截断写出 / 拒绝构造」。
- **出口长度天然等于宽度**：核心段 + 填充段恰好补齐，总长不超声明上限，不存在赋值时静默截断——「回夹凑宽度」的写法在本件被结构性消灭。
- **连续调用零残留**：入口先把结果清空，第二次纯填充不会混入上次内容。
- **宽度是契约参数**：填 0 或 300 直接 0224 拒绝，不猜、不钳、不补零。
- 与既有件边界：`FC_DL_StringTrim` / `FC_DL_StringSplit` / `FC_DL_StringReplaceAll` 改内容不改宽度；本件只改宽度与对齐，内容字符顺序不动（除裁剪尾部）。

---

## 44. FC_DL_Matrix3Inverse ｜ 3×3 矩阵解析求逆（R13，v1.0.1 ｜ Matrix 子族开族）

**定位**：3×3 实数矩阵按伴随矩阵法解析求逆，含**相对奇异判据**与出口夹域，失败时逆矩阵整体置 0 且绝不输出非数。九个元素行主序传入，全过程为定长表达式（无主元选取、无嵌套循环、无分支跳步），同一输入在同一平台上的每一步中间量都可复算。典型用途：视觉与机器人手眼标定反解、仿射变换逆映射（像素坐标反算机械坐标）、三传感器三角定位线性方程组、标定矩阵逐拍复核。

**为什么不用高斯消元**：三阶解析逆是固定九个表达式，天然满足「纯函数、确定性、可逐拍复算」；高斯消元需三层嵌套循环加主元选择分支，在三阶规模上无数值或性能收益，却引入「主元为 0 要换行」的分支面。

**数值判据（本件关键）**：不用绝对阈值判奇异。矩阵元素量纲相差一千倍时（毫米级标定矩阵 vs 微米级标定矩阵），同一个 1.0E-9 的绝对门槛对前者过严、对后者过松。本件用相对判据「`|det| ≤ fDetEps × maxAbs³`」——同一个相对容差在两种量纲下都成立。`fDetEps` 是相对量（默认 1.0E-9），**不是绝对行列式门槛，切勿按绝对值理解**。

### 44.1 接口 / Interface

| 参数 / Parameter | 类型 / Type | 方向 / Dir | 默认值 / Default | 单位 / Unit | 说明 / Description |
|---|---|---|---|---|---|
| `afM` | `ARRAY[1..9] OF LREAL` | IN | — | 同元素单位 | 行主序 3×3 矩阵：元素 1~3 第一行、4~6 第二行、7~9 第三行 / Row-major matrix |
| `fDetEps` | `LREAL` | IN | `1.0E-9` | 无量纲 | 相对奇异判据；非正时按默认处理并置 014C / Relative singularity epsilon |
| 返回值 | `BOOL` | 返回 | — | — | TRUE = 逆已给出（014A 病态提示也算成功）/ TRUE when the inverse is available |
| `afInv` | `ARRAY[1..9] OF LREAL` | OUT | — | 同元素单位 | 逆矩阵（行主序），失败时全 0 / Inverse, zeroed on failure |
| `fDet` | `LREAL` | OUT | — | 单位³ | 行列式值 / Determinant |
| `fCondEst` | `LREAL` | OUT | — | 无量纲 | 条件数粗估 `|det| / maxAbs³`，越小越病态，仅趋势参考 / Coarse condition estimate |
| `uErrorId` | `UDINT` | OUT | — | — | 事件码 / Event code |

### 44.2 故障码表 / Error Codes

| ErrorID | 含义 / Meaning | 处理建议 / Action |
|---|---|---|
| `16#0000_0000` | 无事件 / No event | — |
| `16#0001_014A` | 信息级：病态但已给出逆（`fCondEst` 超 10 倍容差且低于 1.0E-3）/ Ill-conditioned, inverse given | 逆可用但精度不保；关注 `fCondEst` 趋势 |
| `16#0001_014B` | 信息级：矩阵含非有限元素，整件拒绝 / Non-finite element | 检查上游标定数据；逆矩阵全 0（不输出毒值） |
| `16#0001_014C` | 信息级：相对容差非正，按默认 1.0E-9 继续 / Epsilon defaulted | 检查容差来源 |
| `16#0001_0225` | 故障级：矩阵奇异（相对判据） / Singular | 逆矩阵全 0；检查矩阵是否退化（行成比例等） |

### 44.3 调用示例 / Example

```iecst
PROGRAM PRG_HandEyeCalib
VAR
    afCalib    : ARRAY[1..9] OF LREAL;   // 标定矩阵（行主序）/ Calibration matrix
    afCalibInv : ARRAY[1..9] OF LREAL;   // 逆矩阵 / Inverse
    fDet       : LREAL;                  // 行列式 / Determinant
    fCond      : LREAL;                  // 条件数粗估 / Condition estimate
    uMCode     : UDINT;                  // 事件码 / Event code
    bInvOk     : BOOL;                   // 求逆成功 / Inverse available
    fPx, fPy   : LREAL;                  // 像素坐标 [px] / Pixel coordinates
    fMx, fMy   : LREAL;                  // 机械坐标 [mm] / Machine coordinates
END_VAR

bInvOk := FC_DL_Matrix3Inverse(
              afM      := afCalib,
              fDetEps  := 1.0E-9,
              afInv    => afCalibInv,
              fDet     => fDet,
              fCondEst => fCond,
              uErrorId => uMCode);

// 逆映射：机械坐标 = 逆矩阵 × [像素 x, 像素 y, 1]
IF bInvOk THEN
    fMx := afCalibInv[1] * fPx + afCalibInv[2] * fPy + afCalibInv[3];
    fMy := afCalibInv[4] * fPx + afCalibInv[5] * fPy + afCalibInv[6];
END_IF
END_PROGRAM
```

### 44.4 要点 / Notes

- **V4 是相对判据存在的唯一理由**：把奇异矩阵整体乘 1.0E-6 后，绝对阈值必然误判为可逆；相对判据仍正确拦截（终审 500 组随机 A×A⁻¹≈I 对拍全数逼近单位阵）。
- **伴随矩阵是余子式矩阵的转置**：逆矩阵第 2 个元素用「第 1 行第 2 列」的代数余子式，写反会让逆矩阵整体转置；对角阵转置后看不出错，**验证排布必须用非对角元素非零的矩阵**。
- **失败路径零毒值**：非有限元素整件拒绝、失败逆矩阵全 0——上层拿到的是「明确不可信」而非 NaN。
- **病态提示 014A 仍算成功**（返回 TRUE）：判定结论不受影响；`fCondEst` 仅供趋势，不作报警判据。
- 矩阵子族从此件开族，四阶与伪逆按 ROADMAP 另立，不复用本件判据常量。

---

---

## 45. R14 T0 快车道增量：域闸门 + 委托内建数学/字符串包装（#45~#49，5 件）

> **组归属**：T0-4 数学（SQRT/LN/TAN）｜ T0-5 取整（ROUND）｜ T0-6 字符串（MID）。三组开收，余量见 SOURCE_HUNTING_MATRIX。全部为「域闸门先行 + 委托内建内核」四段式（R45）。

### 45.1 组件速览 / Quick Reference

| # | 组件 | 标准原型 | 防御要点 | 码位 |
|---|---|---|---|---|
| 45 | `FC_DL_SqrtEx` | SQRT | 负数/非有限域闸门，NaN→0.0+故障码 | `015A`/`0227` |
| 46 | `FC_DL_LnEx` | LN | fX ≤ 0 拦截（含 0 趋 −Inf） | `0228`/`0229` |
| 47 | `FC_DL_TanEx` | TAN | π/2 极点容差 + 幅值 1E6 双保险 | `022A` |
| 48 | `FC_DL_RoundSat` | ROUND | DINT 域外钳位饱和、半值远离零 | `015B`/`022B` |
| 49 | `FC_DL_StringMidEx` | MID | LEN 一次锁存 + 255 先置截断标志再钳位 | `015C`/`015D` |

### 45.2 要点 / Notes

- **非有限判据库内统一**：NaN 用 `x <> x`、无穷用 `ABS(x) > 1.0E308`（有限性上界提为常量）。
- **TanEx 双保险**（R45 样板）：内建 TAN 在极点可能返回天文数字有限值而非 Inf——极点容差闸（|cos|<1E-12，cos 由内建求，严禁自写级数）前置 + 结果幅值闸（|tan|>1E6）兜底，三况同码 `022A` 返回 0.0。
- **RoundSat 取向声明**：半值「四舍五入远离零」（多数平台 ROUND 语义）头注释写死；DINT 域外钳到端点置信息码不回绕。
- **StringMidEx 时序安全**（R49/R37）：LEN 一次锁存防调用拍内串改写歧义；越界起点返回空串不调内建；255 截断先置标志再钳长，严禁静默回夹；首事件优先不覆盖。
- 输入单位：TanEx 为弧度 [rad]，角度制调用方先显式转换；错误字统一 UDINT（32 位码段容量裁定，头注释留档）。

---

## 四十六、T0 标准函数包装族（R15，#50~#69）

R15 新增 20 件 IEC 标准函数 T0 防御包装（四段式 R45 范式：预置 → 域闸门早退 → 委托内建 → 非有限复检），全部 FC、全部 LREAL/DINT/INT/BOOL 纯标准类型、零全局耦合。**统一输出三件套**：`eErr : UDINT`（错误码，`16#0001_XXXX` 码段）+ `bError : BOOL`（码非 0 即 TRUE）+ `bValid : BOOL`（降级/兜底时 FALSE）；下表「输出」列只列额外输出。截断类一律 R37/R49 范式（先置标志再钳位）；字符串改写类显式写 `$00` 终结符（R53）。

| # | 组件 | 入参 | 返回 | 输出（额外） | 错误码槽位 |
|---|---|---|---|---|---|
| 50 | `FC_DL_AbsEx` | `lrIn : LREAL` | LREAL | — | `015E` / `022C` |
| 51 | `FC_DL_SinEx` | `lrRad : LREAL` [rad] | LREAL | — | `0163` |
| 52 | `FC_DL_CosEx` | `lrRad : LREAL` [rad] | LREAL | — | `0168` |
| 53 | `FC_DL_AsinEx` | `lrIn : LREAL`（域 [−1,1]） | LREAL | — | `016D` |
| 54 | `FC_DL_AcosEx` | `lrIn : LREAL`（域 [−1,1]） | LREAL | — | `0172` |
| 55 | `FC_DL_AtanEx` | `lrIn : LREAL`（全实数域） | LREAL | — | `0177` |
| 56 | `FC_DL_Atan2Ex` | `lrY : LREAL`, `lrX : LREAL` | LREAL（域 (−π, π]，y=0&x<0 → +π） | — | `017C` / `017E` / `024B` |
| 57 | `FC_DL_ExpEx` | `lrIn : LREAL` | LREAL | — | `0181` / `024F` |
| 58 | `FC_DL_ExptEx` | `lrBase : LREAL`, `lrExp : LREAL` | LREAL | — | `0186` / `0187` / `0254` / `0255` |
| 59 | `FC_DL_TruncEx` | `lrIn : LREAL` | DINT | — | `018B` / `0259` |
| 60 | `FC_DL_FloorEx` | `lrIn : LREAL` | DINT | — | `0190` / `025E` |
| 61 | `FC_DL_CeilEx` | `lrIn : LREAL` | DINT | — | `0195` / `0263` |
| 62 | `FC_DL_StringLenEx` | `sIn : STRING(255)`, `bTrimTrailingSpace : BOOL` | INT [字符] | — | 无（仅 0000 正常） |
| 63 | `FC_DL_StringLeftEx` | `sIn : STRING(255)`, `nCount : INT` [字符] | BOOL（已执行） | `sResult : STRING(255)` | `019F` / `01A1` |
| 64 | `FC_DL_StringRightEx` | `sIn : STRING(255)`, `nCount : INT` [字符] | BOOL（已执行） | `sResult : STRING(255)` | `01A4` / `01A6` |
| 65 | `FC_DL_StringConcatEx` | `sA : STRING(255)`, `sB : STRING(255)` | BOOL（已执行） | `sResult : STRING(255)`, `bTruncated : BOOL` | `0277` |
| 66 | `FC_DL_StringInsertEx` | `sIn : STRING(255)`, `sIns : STRING(255)`, `nPos : INT`（1 基，合法域 [1, len+1]） | BOOL（已执行） | `sResult : STRING(255)`, `bTruncated : BOOL` | `01AE` / `027C` |
| 67 | `FC_DL_StringDeleteEx` | `sIn : STRING(255)`, `nPos : INT`（1 基）, `nCount : INT` [字符] | BOOL（已执行） | `sResult : STRING(255)` | `01B3` / `01B5` |
| 68 | `FC_DL_StringFindEx` | `sHay : STRING(255)`, `sNeedle : STRING(255)`, `nStart : INT`（1 基） | INT（1 基位置，未找到=0 且非错误） | — | `01B8` / `01BA` |
| 69 | `FC_DL_StringReplaceAtEx` | `sIn : STRING(255)`, `sRep : STRING(255)`, `nPos : INT`（1 基） | BOOL（已执行） | `sResult : STRING(255)`（总长与源串一致）, `bTruncated : BOOL` | `01BD` / `028B` |

### 46.1 要点 / Notes

- **Atan2Ex 归属口径**（R52）：双零（|x|、|y| 均 < 1.0E-12）返回 0.0 置 `017E`（信息级）；近零 x 轴判向 ±π/2；x<0 按 y 符号加/减 π，y=0 归入 `>=` 支返回 +π——返回域恒 (−π, π]。
- **ExptEx LN(0) 隐患已排**：零底闸（|base|<1.0E-9）先于 `exp*LN(|base|)` 溢出预判 RETURN，LN 实参恒 ≥ 1.0E-9，不存在 LN(0) = −Inf 污染比较的路径。
- **截断三件**（Concat/Insert/ReplaceAt）：超 255 先置 `bTruncated=TRUE` 与上溢码再钳配额（R37/R49），复制后显式写 `$00`（R53）。
- **StringFindEx 未找到语义**：返回 0 且 `eErr=0000`、`bValid=TRUE`——未找到不是错误；空针才是无效入参（`01BA`）。
- 输入单位：三角件弧度 [rad]，角度制调用方先显式转换；错误字统一 UDINT。

---

## 47. T0 变体线防御包装族（R16，#70~#89）｜ T0 Variant-Lane Defensive Wrappers

> **族定位**：20 件全部为 `FC_` 纯函数（无状态机，R60 N/A 口径），输出契约统一三件套：`eErr : UDINT`（错误码，0=正常）＋ `bError : BOOL`（eErr 非 0 时 TRUE）＋ `bValid : BOOL`（输出是否可用）。信息级码属正常防御（`bError=FALSE、bValid=TRUE`，输出为钳位后防御值）；故障级码返回安全缺省值（0 / T#0S）且 `bValid=FALSE`。来源：IEC 61131-3 标准语义 clean-room（T0 变体线，零检索）。

### 47.1 接口总表 / Interface Matrix

| # | 组件 / Component | 输入引脚 / Inputs | 返回值类型 / Return | 码位（信息/故障） | 防御要点 / Defense |
|---|---|---|---|---|---|
| 70 | `FC_DL_LrealToRealSat` | `fIn : LREAL` | REAL | `01C0` / `028E` | 双侧饱和钳 ±3.402823E38；非有限（NaN/±INF）故障闸 |
| 71 | `FC_DL_LrealToDintSat` | `fIn : LREAL` | DINT | `01C2` / `0291` | 域判定先行（±2147483647/−2147483648）+ TRUNC 向零截断 |
| 72 | `FC_DL_RealToUdintSat` | `fIn : REAL` | UDINT | `01C4`/`01C5` / `0294` | 负值钳 0（01C4）、超上界钳 16#FFFFFFFF（01C5）双分支（R56） |
| 73 | `FC_DL_RealToUintSat` | `fIn : REAL` | UINT | `01C6`/`01C7` / `0297` | 负值钳 0、超上界钳 16#FFFF 双侧饱和（R56） |
| 74 | `FC_DL_RealToByteSat` | `fIn : REAL` | BYTE | `01C8`/`01C9` / `029A` | 负值钳 16#00、超上界钳 16#FF（串口/PWM 字节域）（R56） |
| 75 | `FC_DL_DintToUintSat` | `nIn : DINT` | UINT | `01CA`/`01CB` | 负值钳 0、超上界钳 16#FFFF；整数域无故障级路径 |
| 76 | `FC_DL_UdintToDintChk` | `uIn : UDINT` | DINT | `01CC` / — | 上界单侧饱和 2147483647；无故障级路径 |
| 77 | `FC_DL_LintToLrealChk` | `nIn : LINT` | LREAL | `01CE` / — | 超 2^53（9007199254740992）置精度告警，值照常转换；双侧比较规避 ABS 极值回绕（R55） |
| 78 | `FC_DL_BcdToUdint` | `uBcd : UDINT`（每半字节 0~9） | UDINT | — / `02A6` | 逐半字节校验 k=0..7（32 位容器恰 8 半字节，R57 收敛口径）；非法半字节（16#A~F）故障返回 0 |
| 79 | `FC_DL_UdintToBcd` | `nIn : UDINT`（0..99999999） | UDINT | `01D2` / — | 超 99999999 饱和至 BCD 16#99999999（与 R9 WordToBcd 口径一致）；除子常量 10 编译期恒非零 |
| 80 | `FC_DL_SelEx` | `bG : BOOL`（FALSE 选 fI0 / TRUE 选 fI1）、`fI0 : REAL`、`fI1 : REAL` | REAL | `01D4` / `02AC` | 选中通道非有限→故障返回 0.0；未选中通道异常仅信息级记录，不影响本拍输出 |
| 81 | `FC_DL_Mux2Ex` | `uK : USINT`（0~1，越界钳 1）、`fI0 : REAL`、`fI1 : REAL` | REAL | `01D6` / `02AF` | 选择子越界信息级钳位；选中通道非有限故障闸 |
| 82 | `FC_DL_Mux4Ex` | `uK : USINT`（0~3，越界钳 3）、`fI0 : REAL`、`fI1 : REAL`、`fI2 : REAL`、`fI3 : REAL` | REAL | `01D8` / `02B2` | IF/ELSIF 链实现 MUX 语义；越界钳 3；选中通道非有限故障闸 |
| 83 | `FC_DL_MinEx` | `fA : REAL`、`fB : REAL` | REAL | — / `02B5` | 任一输入非有限故障返回 0.0；域内 `fA<=fB` 取 A 否则取 B |
| 84 | `FC_DL_MaxEx` | `fA : REAL`、`fB : REAL` | REAL | — / `02B8` | 任一输入非有限故障返回 0.0；域内取大 |
| 85 | `FC_DL_LimitEx` | `fMin : REAL`、`fIn : REAL`、`fMax : REAL`（倒置自动交换） | REAL | `01DE` / `02BB` | 三输入非有限故障闸；上下限倒置自动交换并置信息级 01DE |
| 86 | `FC_DL_TimeAddSat` | `tA : TIME`、`tB : TIME` | TIME | `01E0` / — | 溢出预判 `tA > DL_TIME_MAX − tB`（减法比较，先判后算，R54）；命中饱和 T#49D17H2M47S295MS |
| 87 | `FC_DL_TimeSubSat` | `tA : TIME`（被减数）、`tB : TIME`（减数） | TIME | `01E2` / — | `tB > tA` 负差钳零（TIME 无符号语义）；无故障级路径 |
| 88 | `FC_DL_TimeScaleSat` | `tIn : TIME`、`nScale : INT`（0~32767，负值钳零） | TIME | `01E4`/`01E5` / — | 负乘子钳零（01E5）；溢出预判 `tIn > DL_TIME_MAX / nScale`（除子先行判非零，R54）；nScale=0 合法零乘 |
| 89 | `FC_DL_TimeDivChk` | `tIn : TIME`、`nDiv : INT`（非 0） | TIME | `01E6` / `02C7` | 除零故障闸提前 RETURN（02C7，返回 T#0S 且 bValid=FALSE）；负除子经 DINT 升位取模长（01E6，规避 INT −32768 取负回绕，R55） |

### 47.2 要点 / Notes

- **TIME 溢出预判范式（R54）**：TimeAddSat/TimeScaleSat 的溢出判定在主体加/乘运算**之前**完成，比较式中不含同域加/乘运算——TIME 为 32 位无符号 ms 容器，`DL_TIME_MAX − tB` 恒 ≥ T#0S 不下溢，预判除法除子 nScale > 0 先行判定。
- **TIME 负值口径**：TIME 无负语义——减法负差钳 T#0S（01E2）、乘法负乘子钳 T#0S（01E5）、除法负除子按模长参与运算并置信息级（01E6，方向语义由调用方承担）。
- **BCD 口径**：BcdToUdint 校验域 k=0..7（UDINT 恰 8 半字节，完整覆盖 0..99999999；k=8..15 在 32 位容器中不存在，移位 ≥32 跨平台未定义故不实施——规格偏离经总监裁定 PASS，R57）；UdintToBcd 饱和口径与 R9 `FC_DL_WordToBcd` 的 9999 饱和一致，域扩大 4 位。
- **泛型选择族**：SelEx/Mux2Ex/Mux4Ex 的非有限判定仅作用于**选中通道**；未选中（备用）通道异常仅置信息级记录（SelEx 01D4），不影响本拍输出——备用通道属热备质量告警，不是本拍故障。选中与未选中同时异常时故障级优先（提前 RETURN）。
- **单位**：TIME 全族 [ms]；三角/比较件无量纲；错误码段 `16#0001_xxxx`，诊断字统一 UDINT。
- **机检与终审**：本族 20 件机检 16 规则全 PASS（fail=0）；总监终审抽查 8 件高风险件零缺陷 PASS（TimeAddSat / TimeSubSat / TimeDivChk / TimeScaleSat / SelEx / BcdToUdint / UdintToBcd / LintToLrealChk）。

---


---

## 48. T0 纯函数第 4 轮防御包装族（R17，#90~#105）｜ T0 Pure-Function Lane #4 Defensive Wrappers

> **族定位**：16 件全部为 `FC_` 纯函数（无状态机，R60 N/A 口径），输出契约统一三件套：`eErr : UDINT`（错误码，0=正常）＋ `bError : BOOL` ＋ `bValid : BOOL`。信息级码属正常防御（`bError=FALSE、bValid=TRUE`）；故障级码返回安全缺省值（0.0 / 0 / T#0S / 1.0）且 `bValid=FALSE`。来源：IEC 61131-3 标准语义 clean-room（T0 纯函数线，零检索）。另 4 件 LWORD 位域落 `DL_Base`（见其手册 §44）。

### 48.1 接口总表 / Interface Matrix

| # | 组件 / Component | 输入引脚 / Inputs | 返回值类型 / Return | 码位（信息/故障） | 防御要点 / Defense |
|---|---|---|---|---|---|
| 90 | `FC_DL_LogEx` | `fIn : REAL`（> 0） | REAL | `01E8` / `02CA`/`02CB` | 底 10 对数；非有限（NaN/±INF）与 fIn ≤ 0 双故障闸返回 0.0，域内委托内建 LOG |
| 91 | `FC_DL_LogBaseEx` | `fIn : REAL`（> 0）、`fBase : REAL`（> 0 且 ≠ 1） | REAL | `01EA` / `02CD`~`02CF` | 换底公式 LN(fIn)/LN(fBase)；底数退化闸（\|fBase−1\| < 1.0E-6，含 fBase=1）+ 除子复判双保险，绝不执行除法 |
| 92 | `FC_DL_AmpDbToRatio` | `fDb : REAL`（±400.0 dB） | REAL | `01EC` / `02D0` | 10^(dB/20) 幅值型；双侧饱和至 1.0E±20；EXPT 结果复检非有限/越界复用信息码按方向饱和 |
| 93 | `FC_DL_RatioToAmpDb` | `fRatio : REAL`（> 0） | REAL | `01EE` / `02D3`/`02D4` | 20·log10(A)；比值 ≤ 0 故障闸；结果钳 ±400.0 dB（极小比值约 −760 dB 不钳会溢出下游常量） |
| 94 | `FC_DL_PwrDbToRatio` | `fDb : REAL`（±380.0 dB） | REAL | `01F0` / `02D6` | 10^(dB/10) 功率型；硬限 380 dB（10^±38 在 REAL 域可表；400 dB 对应 10^40 超出 3.402823E38 不可表） |
| 95 | `FC_DL_TimeToDintMs` | `tIn : TIME` | DINT | `01F2`/`01F3` / — | TIME 域先与 2147483647 ms 比较（先判后算，禁超限值进内建 TIME_TO_DINT 防平台回绕）；负结果钳 0 |
| 96 | `FC_DL_DintMsToTime` | `nMs : DINT`（负值钳 0） | TIME | `01F4` / — | 负值钳 T#0S；无上域闸（DINT 正域 2147483647 ms < TIME 域 4294967295 ms，论证留档防误加假分支） |
| 97 | `FC_DL_TimeToLrealSec` | `tIn : TIME` | LREAL | `01F6` / — | TIME_TO_LREAL 取 ms ÷ 1000.0 得 s；负 TIME 照转仅记录（观测语义，钳零会掩盖上游非法减法） |
| 98 | `FC_DL_LrealSecToTime` | `fSec : LREAL`（0.0~4294967.295 s） | TIME | `01F8`/`01F9` / `02E2` | 非有限故障闸 + 负值钳 T#0S + 上界 4294967.295 s 先判后饱和 T#49D17H2M47S295MS（先算后判必溢出） |
| 99 | `FC_DL_TodToDintMs` | `todIn : TOD` | DINT | `01FA` / — | 标准链 TOD_TO_TIME→TIME_TO_DINT（不自实现时分秒累加）；结果钳 0~86399999 ms（24h−1ms） |
| 100 | `FC_DL_DintToRealChk` | `nIn : DINT` | REAL | `01FC` / — | \|nIn\| > 2^24（16777216）精度告警，只告警不钳位；双侧比较禁 ABS 单侧式（R55 同源） |
| 101 | `FC_DL_UdintToRealChk` | `nIn : UDINT` | REAL | `01FE` / — | nIn > 2^24 精度告警；无符号负值分支由类型系统结构性排除 |
| 102 | `FC_DL_LintToDintSat` | `nIn : LINT` | DINT | `0200`/`0201` / — | LINT 域先判后转双侧饱和 2147483647 / −2147483648；下界 −DL_DINT_MAX−1 计算式禁负字面量直写 |
| 103 | `FC_DL_RealToLintSat` | `fIn : REAL` | LINT | `0202` / `02F1` | REAL_TO_LREAL 升位先行（REAL 域界不可精确表示）+ TRUNC 向零截断 + 双侧饱和 ±LINT 极值 |
| 104 | `FC_DL_LrealToLintSat` | `fIn : LREAL` | LINT | `0211` / `02F4` | 与 RealToLintSat 同口径；双版本为库内既定策略（IEC 无 ANY_REAL 泛型，职责边界留档） |
| 105 | `FC_DL_LwordToLrealChk` | `nIn : LWORD` | LREAL | `020E` / — | nIn > 2^53（9007199254740992）精度告警；无符号位串单侧比较，负值分支由类型系统排除 |

### 48.2 要点 / Notes

- **对数/dB 因子分型**：幅值型 20（`AmpDbToRatio`/`RatioToAmpDb`）与功率型 10（`PwrDbToRatio`）严格分型禁混用；功率型硬限 380 dB 而非 400 dB 的理由——饱和值本身必须在目标浮点域可表（10^38 < REAL 最大有限值 3.402823E38，10^40 不可表），头注释留档。
- **TIME 域先判后算**：`TimeToDintMs`/`LrealSecToTime` 的溢出预判均在 LREAL/TIME 原域完成，比较式中不含同域换算运算（R54 同源），超限值绝不进入内建转换。
- **精度告警族口径**：DintToRealChk / UdintToRealChk（2^24，REAL 24 位尾数）与 LwordToLrealChk（2^53，双精度 53 位尾数）均为「照常转换 + 信息级告警」的观测语义，不钳位——调用方按 `eErr` 自行决策。
- **饱和转换族口径**：TRUNC 向零截断（规避内建舍入取向平台差异）+ 升位比较（域界值在源类型不可精确表示）+ 下界 `−MAX−1` 计算式（禁负字面量直写，R55 同源）。
- **交付门槛声明**：`TodToDintMs` 依赖 TOD_TO_TIME 链，头注释已声明须在三平台各编译验证一次（连续 15 轮悬置的编译验证债的一部分）。
- **码位警示**：`0201`/`0202`/`0210`/`0211`/`021B` 经 R17 收口全库正则复测与存量件撞车（`FC_DL_DayOfWeekCalc` / `FB_DL_TimeWindowCheck` / `FB_DL_EventCounter` / `FB_DL_ModuloCounter` / `FB_DL_BitArrayChangeWatch`），R18 改判专项方案已列明（0213~0216 + 0220），执行前本节码位暂维持源码现状。

### R18 新件接口一览（2026-11-16 追加）/ Round 18 Interface Summary

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FC_DL_AffineTransformPoint` | 旋转 → 缩放 → 平移一次合成的点变换 | `fRotDeg` / `fX` / `fY` |
| `FC_DL_CpkIndex` | 样本数组算 Cp/Cpk/均值/样本标准差（n−1 分母） | `uCount` / `fLsl` / `fCpk` |
| `FC_DL_Crc16Ccitt` | CRC-16 三变体，验收向量 `123456789`→`29B1`/`31C3`/`2189` | `auData` / `uLen` / `eVari` |
| `FC_DL_InterpolateTable2D` | 8×8 标定网格双线性插值 | `afGridY` / `afValue` / `fOut` |

> 用法要点：`Crc16Ccitt` 的 `uLen = 0` 是合法空帧（返回 init 值且 `bValid = TRUE`），不要当故障处理；`CpkIndex` 需 `uCount ≥ 2`，单样本返回故障码。


---


---

## R19 追加组件接口表（2026-11-16，本子库 5 件）

### `FC_DL_DintMsToTod`
- **功能**：DINT 当日毫秒→TOD 反向转换（与 TodToDintMs 构成双向对，钳 0~86399999 ms）
- **输入引脚**：nMsOfDay、bClampSilently（语义与单位见 .st 头注释）
- **输出引脚**：eErr、bError、bValid、bClamped
- **码位**：16#0001_0400 用 / 16#0001_0401 预留 ｜ 16#0001_031E 用 / 16#0001_031F 用 / 16#0001_0320 预留

### `FC_DL_TimeRatioCalc`
- **功能**：TIME 比值→LREAL 百分比（除子 tB=0 故障闸，LREAL 承载防溢出）
- **输入引脚**：tNumerator、tDenominator、bAsPercent、fRatioSpan（语义与单位见 .st 头注释）
- **输出引脚**：eErr、bError、bValid、fRatioAbs、bSaturated
- **码位**：16#0001_0402 用 / 16#0001_0403 用 ｜ 16#0001_0321 用 / 16#0001_0322 用 / 16#0001_0323 预留

### `FC_DL_RatioToPwrDb`
- **功能**：功率型反向件 dB = 10·log10(P)（与 PwrDbToRatio 构成双向对）
- **输入引脚**：fP1、fP2、fDbSpan、fDbFloor（语义与单位见 .st 头注释）
- **输出引脚**：eErr、bError、bValid、bSaturated、bZeroPower
- **码位**：16#0001_0404 用 / 16#0001_0405 用 ｜ 16#0001_0324 用 / 16#0001_0325 用 / 16#0001_0326 预留

### `FC_DL_LintToUdintSat`
- **功能**：LINT→UDINT 交叉域饱和（负值/正向两个独立饱和闸 + bRequireLossless 无损模式）
- **输入引脚**：liIn、bRequireLossless（语义与单位见 .st 头注释）
- **输出引脚**：eErr、bError、bValid、bSatLow、bSatHigh
- **码位**：16#0001_0406 用 / 16#0001_0407 用 ｜ 16#0001_0327 用 / 16#0001_0328 预留 / 16#0001_0329 预留

### `FC_DL_ModbusRtuFrameCheck`
- **功能**：Modbus RTU 帧 CRC16 校验与帧完整性判定
- **输入引脚**：auFrame、uLen、eFc、uQty（语义与单位见 .st 头注释）
- **输出引脚**：eErr、bError、bValid、uByteCount、bIsException、bBroadcast
- **码位**：16#0001_040A 用 / 16#0001_040B 用 ｜ 16#0001_032D 用 / 16#0001_032E 用 / 16#0001_032F 用


---

## R20 追加组件接口表（2026-11-16，本子库 18 件）

> 一律 `FC_DL_` 纯函数，输出契约 `eErr` / `bError` / `bValid` 三件套（下表不再重复列出）。**日历/天数族四件共用同一容器口径常量** `DL_DATE_DAYS_MAX = 65535`，互相之间不会错位；涉及平台内建口径（DT_TO_DINT / DATE_TO_DINT / TOD_TO_DINT）的件均在头注释「编译门槛」段声明实测锚定要求。

### `FC_DL_DtToDintEpoch` / `FC_DL_DintEpochToDt`
- **功能**：Unix 纪元秒 ↔ DATE_AND_TIME 双向对。正向**饱和**（Y2038 超域钳上限并升故障级），反向**不饱和**（超域返回纪元零点）——饱和会伪造时刻、毁掉故障证据，两方向策略刻意分立。
- **输入引脚**：`dtIn`（DT）｜ `nEpochSec`（DINT，0~2147483647）
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `040C`/`040E`（Y2038 邻近 / 域端点）｜ 故障 `0330`~`0331` / `0333`~`0334`

### `FC_DL_DateToDintDays` / `FC_DL_DintDaysToDate`
- **功能**：DATE ↔ 自 1970-01-01 起天数双向对，供保质期、保养周期、数据库整型列落库。
- **输入引脚**：`dateIn`（DATE）｜ `nDays`（DINT）
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `0410`（超容器口径已钳位）/`0412`（域端点）｜ 故障 `0336`~`0337` / `0339`~`033A`

### `FC_DL_TodAddWrap` / `FC_DL_TodDiffWrap`
- **功能**：当日时刻加偏移（含午夜回绕）与两时刻差（含跨零点折算）。回绕一律**条件加减**，禁用 MOD（负数取余三平台不一致）。
- **输入引脚**：`todIn` + `tOffset`（TIME，模长须 < 一日）｜ `todEarlier` + `todLater`
- **输出引脚**：`bWrapped`、`nWrapCircles`（±1 圈）｜ `bCrossMidnight`
- **码位**：信息 `0420` / `0422` ｜ 故障 `034E`~`034F`（仅 Add 件）

### `FC_DL_DateAddDays` / `FC_DL_DateDiffDays`
- **功能**：日期 ± 天数（±36500 天钳位）、日期差天数（负差如实输出）。溢出用**减法预判**：正向判 `nWork > 上限 − nBase`，负向判 `nWork < 0 − nBase`，禁「先加再判变号」。
- **输入引脚**：`dateIn` + `nDays` ｜ `dateFrom` + `dateTo`
- **输出引脚**：`bClamped` ｜ `bNegative`
- **码位**：信息 `042A` / `042C` ｜ 故障 `035D`~`035E`（仅 Add 件）

### `FC_DL_TimeAbsSat`
- **功能**：TIME 取幅值并饱和。`nIn < −2147483647` 单值闸精确拦截 INT32_MIN（`−MAX−1` 的相反数不可表），饱和值经 `DINT_TO_TIME` 落地而非超长字面量。
- **输入引脚**：`tIn`（TIME，平台 32 位毫秒口径）
- **输出引脚**：`bNegative`
- **码位**：信息 `042E`（负输入已取幅值）｜ 故障 `0363`（不可表达，已饱和）

### `FC_DL_UdintToLintChk`
- **功能**：UDINT → LINT 升位 + **round-trip 验真**（回程比对，识别平台把中间量走 32 位有符号路径的符号扩展缺陷）。
- **输入引脚**：`uIn`（UDINT）、`bCheckEveryCall`（默认 TRUE；FALSE 时本拍不验真并置 0414）
- **输出引脚**：`bRoundTripFail`
- **码位**：信息 `0414` ｜ 故障 `033C`（验真失败）

### `FC_DL_WordToIntSat`
- **功能**：WORD → INT 超域双出口：补码解释为负值（0416）或上饱和 32767（0417），由 `bTwosComplement` 决定，**两种口径都如实登记**。
- **输入引脚**：`uIn`（WORD）、`bTwosComplement`
- **输出引脚**：`bInterpreted`
- **码位**：信息 `0416` / `0417` ｜ 故障槽全预留（本件不升故障级）

### `FC_DL_DwordToIntSat` / `FC_DL_LwordToLintSat`
- **功能**：DWORD → INT（饱和 32767）、LWORD → LINT（饱和 9223372036854775807）；`bRequireLossless = TRUE` 时一旦饱和即反升故障级（无损是调用方的硬要求，不能只发信息码）。
- **输入引脚**：`uIn`、`bRequireLossless`
- **输出引脚**：`bSatHigh`
- **码位**：信息 `0418` / `041A` ｜ 故障 `0342` / `0345`（无损违约）

### `FC_DL_BcdToByte` / `FC_DL_ByteToBcd`
- **功能**：BCD ↔ BYTE 双向。半字节 > 9 判故障级拦截；满量程 99 与域端点发信息级（多拨码开关调试残留的典型现象）。补齐 R16 的 WORD/UDINT 位宽缺口。
- **输入引脚**：`uBcd`（BCD）｜ `uIn`（0~99）
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `041C` / `041E` ｜ 故障 `0348` / `034B`

### `FC_DL_SwapBytes64`
- **功能**：LWORD 全字节逆序。**拆半区复用 `FC_DL_SwapBytes32`** 各自反序，再交叉合成 `(LoRev << 32) OR HiRev`——字节序族内复用而非重实现内核；全域双射，五槽码位全预留。
- **输入引脚**：`liIn`（LWORD，全域）
- **输出引脚**：`eErr`（恒 0）、`bError`（恒 FALSE）、`bValid`（恒 TRUE）
- **码位**：`16#0001_0424`~`0425` / `0354`~`0356` 全预留

### `FC_DL_DintToStringTrim` / `FC_DL_LrealToStringTrim`
- **功能**：整型 / 浮点字符串化：前导空格修剪 + R37 四步截断样板（长度锁存 → 宽度比较 → 标志先置 → 按允许分路）。浮点件把非有限值映射成统一文本 `NaN` / `Inf+` / `Inf-`（信息级、`bValid` 仍 TRUE——采样坏点不该牵动整条报警链）。
- **输入引脚**：`nIn` / `fIn`、`uTargetMax`（1~255 字符）、`bAllowTrunc`
- **输出引脚**：`bTrimmed`、`bTruncated` ｜ 浮点件另有 `bNonFinite`
- **码位**：信息 `0426`~`0429` ｜ 故障 `0357`~`0358` / `035A`
- **用法要点**：`bAllowTrunc = FALSE` 时宁可返回空串也不返回半截数值；`LrealToStringTrim` 的无穷判据为 `(x−x) <> (x−x)` + LREAL 最大值兜底（v1.0.1，勿改回单一 1.79E308 阈值）。

---

## R21 追加接口表 / R21 Interface Tables

> R21 数学安全原子 / LWORD 位域与校验 / 文本序列化 15 件（v1.15.0 追加）。以下引脚表由源码声明区**自动抽取**（`_Staging_Raw/2026-11-16/_r21_doc.py`），不做人工转述，避免文档与代码漂移。

### `FC_DL_ModPos`
- **功能**：恒正取模原子，返回恒非负余数 r ∈ [0, |m|-1]，消灭「负数取余」在三大平台上的符号歧义。（v1.0.0，R21 入库）
- **输入引脚**：`nValue`、`nModulus`
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0434`/`16#0001_0435` ｜ 故障 `16#0001_036C`/`16#0001_036D`/`16#0001_036E`

### `FC_DL_DivLrealSafe`
- **功能**：浮点防御除法原子，把「除法前置防零」这条红线从散落各件的内联 IF 收成唯一出口。（v1.0.0，R21 入库）
- **输入引脚**：`fNum`、`fDen`、`fDenEps`
- **输出引脚**：`eErr`、`bError`、`bValid`、`fRatio`
- **码位**：信息 `16#0001_0436`/`16#0001_0437` ｜ 故障 `16#0001_036F`/`16#0001_0370`/`16#0001_0371`

### `FC_DL_QuantizeStep`
- **功能**：按非整数步距量化，把任意给定值对齐到 n × step（编码器分辨率、给定值网格、成本最小单位的通用内核）。（v1.0.0，R21 入库）
- **输入引脚**：`fIn`、`fStep`、`bRoundHalfUp`
- **输出引脚**：`eErr`、`bError`、`bValid`、`fResidual`
- **码位**：信息 `16#0001_0438`/`16#0001_0439` ｜ 故障 `16#0001_0372`/`16#0001_0373`/`16#0001_0374`

### `FC_DL_PolyEvalHorner`
- **功能**：Horner 法多项式求值内核，PT100 Callendar-Van Dusen、热电偶 NIST 多项式、传感器多点拟合的公共出口。（v1.0.0，R21 入库）
- **输入引脚**：`nOrder`、`fX`
- **输出引脚**：`eErr`、`bError`、`bValid`、`nEffOrder`
- **码位**：信息 `16#0001_043A`/`16#0001_043B` ｜ 故障 `16#0001_0375`/`16#0001_0376`/`16#0001_0377`

### `FC_DL_WrapAngleDeg`
- **功能**：角度归一原子，把任意角度折算到 (−180, 180]（缺省）或 [0, 360)，并顺带出口圈数供多圈相位追溯。（v1.0.0，R21 入库）
- **输入引脚**：`fAngleDeg`、`bZeroTo360`
- **输出引脚**：`eErr`、`bError`、`bValid`、`nTurns`
- **码位**：信息 `16#0001_043C`/`16#0001_043D` ｜ 故障 `16#0001_0378`/`16#0001_0379`/`16#0001_037A`

### `FC_DL_LwordBitFieldExtract`
- **功能**：LWORD 单字位段读取（起始位 0~63，字段宽 1~64），补齐库内位操作族只覆盖 BYTE/WORD/DWORD 的缺口。（v1.0.0，R21 入库）
- **输入引脚**：`uWord`、`nStartBit`、`nWidth`
- **输出引脚**：`eErr`、`bError`、`bValid`、`bTruncated`
- **码位**：信息 `16#0001_043E`/`16#0001_043F` ｜ 故障 `16#0001_037B`/`16#0001_037C`/`16#0001_037D`

### `FC_DL_LwordBitFieldInsert`
- **功能**：LWORD 单字位段读改写（清位 → 取值 → 合成），与 FC_DL_LwordBitFieldExtract 构成读写对偶。（v1.0.0，R21 入库）
- **输入引脚**：`uBase`、`uField`、`nStartBit`、`nWidth`
- **输出引脚**：`eErr`、`bError`、`bValid`、`bChanged`
- **码位**：信息 `16#0001_0440`/`16#0001_0441` ｜ 故障 `16#0001_037E`/`16#0001_037F`/`16#0001_0380`

### `FC_DL_LwordBitCount`
- **功能**：LWORD 汉明重量（置位个数 0~64），补齐存量 FC_DL_BitCount 只覆盖 DWORD 的位宽缺口。（v1.0.0，R21 入库）
- **输入引脚**：`uValue`
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0442`/`16#0001_0443` ｜ 故障 `16#0001_0381`/`16#0001_0382`/`16#0001_0383`

### `FC_DL_Crc16Generic`
- **功能**：参数化 CRC-16，poly / init / xorout / 输入反射 / 输出反射全部引脚化，一张实现覆盖任意从站协议。（v1.0.1，R21 入库）
- **输入引脚**：`nLen`、`uPoly`、`uInit`、`uXorOut`、`bReflectIn`、`bReflectOut`
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0445`/`16#0001_0444` ｜ 故障 `16#0001_0384`/`16#0001_0385`/`16#0001_0386`

### `FC_DL_ChecksumSum8`
- **功能**：8 位累加和校验，覆盖 DL/T 645、水表/电表自定义帧这类「不用 CRC、只用累加和」的协议形态。（v1.0.0，R21 入库）
- **输入引脚**：`nLen`、`bTwosComplement`
- **输出引脚**：`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0446`/`16#0001_0447` ｜ 故障 `16#0001_0387`/`16#0001_0388`/`16#0001_0389`

### `FC_DL_StringToDint`
- **功能**：整数字符串严格解析，补 FC_DL_StringToLReal 的整数族缺口（配方号 / 站号 / 批次号）。（v1.0.2，R41 P0-3 配对修复）
- **输入引脚**：`sIn`、`bAllowSign`
- **输出引脚**：`eErr`、`bError`、`bValid`、`nErrPos`
- **码位**：信息 `16#0001_0448`/`16#0001_0449` ｜ 故障 `16#0001_038A`/`16#0001_038B`/`16#0001_038C`

### `FC_DL_DwordToHexString`
- **功能**：DWORD → 8 位定宽十六进制文本，是 FC_DL_HexStringToBytes 的逆向对偶。（v1.0.0，R21 入库）
- **输入引脚**：`uValue`、`bUpperCase`、`bPrefix`
- **输出引脚**：`eErr`、`bError`、`bValid`、`nLength`
- **码位**：信息 `16#0001_044A`/`16#0001_044B` ｜ 故障 `16#0001_038D`/`16#0001_038E`/`16#0001_038F`

### `FC_DL_ArraySumLreal`
- **功能**：静态数组一次性求和与均值，带非有限样本剔除与有效样本计数出口。（v1.0.0，R21 入库）
- **输入引脚**：`nCount`
- **输出引脚**：`eErr`、`bError`、`bValid`、`fMean`、`nValidCount`
- **码位**：信息 `16#0001_044C`/`16#0001_044D` ｜ 故障 `16#0001_0390`/`16#0001_0391`/`16#0001_0392`

### `FC_DL_TimeToHmsString`
- **功能**：TIME 时长 → 'HH:MM:SS.mmm' 定宽文本，负时长统一带负号，并把总小时数单独出口供报表使用。（v1.0.0，R21 入库）
- **输入引脚**：`tIn`
- **输出引脚**：`eErr`、`bError`、`bValid`、`bNegative`、`nTotalHours`
- **码位**：信息 `16#0001_044E`/`16#0001_044F` ｜ 故障 `16#0001_0393`/`16#0001_0394`/`16#0001_0395`

### `FC_DL_DateToIsoString`
- **功能**：DATE → 'YYYY-MM-DD' 十字符定宽文本，同时把年/月/日分解结果单出口，供 MES 台账与文件名直接取用。（v1.0.1，R21 入库）
- **输入引脚**：`dateIn`
- **输出引脚**：`eErr`、`bError`、`bValid`、`nYear`、`nMonth`、`nDay`
- **码位**：信息 `16#0001_0450`/`16#0001_0451` ｜ 故障 `16#0001_0396`/`16#0001_0397`/`16#0001_0398`
---

## R22 批次接口表（R22 追加 · 3 件 · 定宽数值字段族）

### FC_DL_IntToFixedField ｜ 整数→定宽字段（DL_MathData / DataFormat ｜ FUNCTION → BOOL）
- **输入引脚**：`nValue`（DINT 全域）、`uWidth`（UINT 缺省 8，1~20 钳位）、`bZeroPad`（BOOL 缺省 TRUE）、`bForceSign`（BOOL）
- **输出引脚**：`sField`（STRING(20) 右对齐）、`uFieldLen`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_045C`（宽度已钳位）｜ 故障 `16#0001_03A8`（宽度不足拒绝编码，不输出半截数字）
- **要点**：负域取模分解防 DINT 最小值；与 `FixedFieldToInt` 构成 round-trip 验收对。

### FC_DL_FixedFieldToInt ｜ 定宽字段→整数（DL_MathData / DataFormat ｜ FUNCTION → BOOL）
- **输入引脚**：`sField`（STRING(20)）、`uWidth`（UINT 缺省 8）、`bAllowLeadingSpace`、`bAllowSign`
- **输出引脚**：`nValue`（DINT）、`uParsedLen`、`nErrPos`（1 基首个非法字符位置）、`bSaturated`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_045E`（已剥离前导填充）/ `045F`（超域已饱和）｜ 故障 `16#0001_03AB`（非法字符）/ `03AC`（有效字符数为 0 或宽度非法）

### FC_DL_LrealToFixedField ｜ 浮点→定宽定点文本（DL_MathData / DataFormat ｜ FUNCTION → BOOL）
- **输入引脚**：`fValue`（LREAL）、`uIntDigits`（UINT 缺省 6，1~15）、`uDecDigits`（UINT 缺省 3，0~6）、`bRound`、`bForceSign`
- **输出引脚**：`sField`（STRING(24)）、`uFieldLen`、`bSaturated`、`eErr`、`bError`、`bValid`
- **码位**：信息 `16#0001_0460`（钳位或舍入进位复用）/ `0461`（整数部分已饱和）｜ 故障 `16#0001_03AE`（非有限输入，不输出 'NaN' 冒充报文）/ `03AF`（字段装不下）
- **要点**：禁 `LREAL_TO_STRING`；非有限用 R79 精确判据；整数 > 15 位时输入本身已失真（遗留假设段留档）。


*Last updated: 2026-11-16（R22 追加接口表）｜ 道莅工控代码库产品总监*

---

## 附录 · R25 批次接口表（2026-11-17，共 1 件）

> 引脚名与类型均由 `.st` 源码 VAR_INPUT / VAR_OUTPUT 段机读提取（不凭记忆）；单位与工程量纲见各件头注释「单位表」。

### FC_DL_Affine2DInvert ｜ 二维仿射变换矩阵求逆（DL_MathData v1.0.0）
- **输入引脚**：`afM`（ARRAY[0..2, 0..2] OF LREAL）、`fDetEps`（LREAL 缺省 1.0E-6）
- **输出引脚**：`afMInv`（ARRAY[0..2, 0..2] OF LREAL）、`fDet`（LREAL）、`eErr`（UDINT）、`bError`（BOOL）、`bValid`（BOOL）
- **码位**：`16#0001_046F` ｜ `16#0001_03BD`

*Last updated: 2026-11-17（R25 追加接口表 20 件）｜ 道莅工控代码库产品总监*
