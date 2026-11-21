# R11 可用码位与命名避让清单 / CODE SLOT & NAMING AVOIDANCE MAP (R11)

> **用途**：R11 及后续新增组件在**动笔前**先查本表，取码位与取名一次到位，杜绝历史多轮「码位撞号返工」。
> **生成日期**：2026-11-15 ｜ **轮次**：R11 备料 ｜ **生成方式**：脚本扫描 `DL_*/*.st` 字面量 + 六份 `VERSION.md` 台账 + `INDEX_REGISTRY.json` 三方交叉
> **数据基准**：全库 152 组件 / 六个子库全部 `.st` / 102 个 TYPE（95 ENUM + 7 STRUCT），与 `INDEX_REGISTRY.json` 的 counts 一致

## 0. 结论速览（先看这一节）

| 目录 | 下一个可用码位（信息级 / 故障级） | 建议号段 |
|---|---|---|
| `DL_Base` | **`0001_011E`** ／ **`0001_0218`** | 信息 `0001_011E~012D`；故障 `0001_0218~0227` |
| `DL_MathData` | **`0001_012E`** ／ **`0001_0228`** | 信息 `0001_012E~013D`；故障 `0001_0228~0237` |
| `DL_Algo` | **`0002_1F01`** ／ **`0002_1F10`** | 信息 `0002_1F01~1F0E`；故障 `0002_1F10~1F1F` |
| `DL_Device` | **`0003_010A`** ／ **`0003_0214`** | 信息 `0003_010A~010F`；故障 `0003_0214~021F` |
| `DL_Motion` | **`0004_0109`** ／ **`0004_0204`** | 信息 `0004_0109~012F`；故障 `0004_0204~020F` |
| `DL_Process` | **`0005_0104`** ／ **`0005_0203`** | 信息 `0005_0104~010F`；故障 `0005_0203~020F` |

**三条铁律（违反任一条即返工）**

1. **先查共享族**：`16#0001_xxxx` 由 `DL_Base` + `DL_MathData` **共用**；`16#0002_xxxx` 由 `DL_Base` + `DL_MathData` + `DL_Algo` **三家共用**。跨目录取码只查本目录必撞（§2 是唯一权威视图）。
2. **禁占三个特殊位**：`0003_0105` 为终审裁定的「空置不分配」位；`0003_0116`、`0003_0281` 为**已登记预留位**（头注释登记、代码未触发）。三位均不得改作他用。
3. **落码前跑求差断言**：本表是静态快照，会随轮次过期。落码前必须对本表 + 全库 `.st` 求差（R30 口径）；不得以「注释里写了经核对未占用」为据——历史 6 件 15 处冲突正是这样产生的。

---

## 1. 码族分配总览 / Family Allocation

| 码族 | 归属子库 | 信息级约定 | 故障级约定 | 段内现状 |
|---|---|---|---|---|
| `16#0001_xxxx` | `DL_Base` + `DL_MathData`（共享） | `0001_01xx` | `0001_02xx` | 参数/循环/数据类公共语义，两库并行分配 |
| `16#0002_xxxx` | `DL_Base`(0001~0008) + `DL_MathData`(0009~000D) + `DL_Algo`(0000~0005 及 `1x00` 带) | 见各库 | 见各库 | 业务/工艺语义 + 算法族按件独占 `1x00` 带 |
| `16#0003_xxxx` | `DL_Device` 独占 | `0003_01xx` | `0003_02xx` 起 | 设备件按件连续占块 |
| `16#0004_xxxx` | `DL_Motion` 独占 | `0004_01xx` | `0004_02xx` 起 | 运动件按件连续占块 |
| `16#0005_xxxx` | `DL_Process` 独占 | `0005_01xx` | `0005_02xx` 起 | 工站/工艺件按件连续占块 |
| `16#0000_xxxx` | 全库 | 无故障基准 `0000_0000` | — | 不作为分配段 |

> `0003` / `0004` / `0005` 三族**库间零共享**，取码只需查本目录；`0001` / `0002` 两族**跨库共享**，是本库唯一的结构性撞号源。
>
> 另注：各族的 `xxxx_0001~00FF` 为**公共/预留区**（下方空闲块表会把它列为大块空闲），新组件**不得**占用，一律在 `01xx`（信息级）/ `02xx`（故障级）内取号。

---

## 2. 共享码族风险矩阵 / Shared-Family Collision Matrix

### 2.1 `16#0001_xxxx`（DL_Base × DL_MathData）

**信息级 `0001_01xx`**

- `DL_Base`：`0101~0104`、`0108~0109`、`0112~0118`
- `DL_MathData`：`0105~0107`、`010A~0110`、`0119~011D`
- **共享空闲块（≥3 码）**：`011E~01FF`（226 码）

**故障级 `0001_02xx`**

- `DL_Base`：`0201~0203`、`0210~0216`
- `DL_MathData`：`0204~0208`、`0217`
- **共享空闲块（≥3 码）**：`0209~020F`（7 码）、`0218~02FF`（232 码）

### 2.2 `16#0002_xxxx`（DL_Base × DL_MathData × DL_Algo）

| 子库 | 占用带 |
|---|---|
| `DL_Base` | `0002_0001~0008`（双手安全 / 联锁 / 冗余语义） |
| `DL_MathData` | `0002_0009~000D`（统计 / 解析 / 几何语义） |
| `DL_Algo` | `0002_0000~0005`（公共码）+ `0101`~`0801`（按件百位带）+ `1001`~`1E10`（按件 `1x00` 带） |

**共用空闲块（≥3 码）**：`0002_000E~00FF`（242 码）、`0002_0103~01FF`、`0002_0202~02FF`

> ⚠ `0002_000E~00FF` 虽大，但属三库共用公共语义区，**不建议**新件占用；`DL_Algo` 新件按「一件一个 `1x00` 带」惯例取 `1F00` 带（见 §3.3）。

---

## 3. 逐目录明细 / Per-Directory Detail

### 3.1 `DL_Base`

Level 0 基础逻辑层｜32 组件｜码族 `0001`（与 MathData 共享）+ `0002_0001~0008`

#### 3.1.1 已占用码段（精确到号段，按归属组件切分）

| 码段 | 码数 | 归属组件（`.st` 内实际字面量） |
|---|---|---|
| `0001_0001` | 1 | `FB_DL_AlarmManager`、`FB_DL_DutyStandbyRotation`、`FB_DL_ExtendedTimer`、`FB_DL_PulseGenerator`、`FB_DL_RedundantSwitch`、`FB_DL_RuntimeMeter`、`FB_DL_SignalDebounce`、`FB_DL_StepSequencer`、`FB_DL_TwoHandSafety`、`FB_DL_WatchdogMonitor`、`FC_DL_BinaryToGray`、`FC_DL_BitGet`、`FC_DL_BitSet`、`FC_DL_GrayToBinary` |
| `0001_0004` | 1 | `FC_DL_BitCount` |
| `0001_0005` | 1 | `FB_DL_DutyStandbyRotation`、`FB_DL_ExtendedTimer`、`FB_DL_InterlockMatrix`、`FB_DL_PulseGenerator`、`FB_DL_RedundantSwitch`、`FB_DL_SignalDebounce`、`FB_DL_StepSequencer`、`FB_DL_TwoHandSafety`、`FB_DL_WatchdogMonitor` |
| `0001_0007` | 1 | `FB_DL_AlarmManager`、`FB_DL_CycleTimeMeasure`、`FB_DL_DualEdgeTrig`、`FB_DL_DutyStandbyRotation`、`FB_DL_InterlockMatrix`、`FB_DL_RedundantSwitch`、`FB_DL_RuntimeMeter`、`FB_DL_TwoHandSafety`、`FB_DL_UnpackWordToBits`、`FB_DL_WatchdogMonitor` |
| `0001_0008` | 1 | `FB_DL_CycleTimeMeasure`、`FB_DL_DutyStandbyRotation`、`FB_DL_RedundantSwitch`、`FB_DL_RuntimeMeter`、`FB_DL_WatchdogMonitor` |
| `0001_000B` | 1 | `FB_DL_StepSequencer` |
| `0001_000C` | 1 | `FB_DL_WatchdogMonitor` |
| `0001_000E` | 1 | `FB_DL_ExtendedTimer` |
| `0001_0101~0102` | 2 | `FB_DL_EventCounter` |
| `0001_0103~0104` | 2 | `FB_DL_ModuloCounter` |
| `0001_0108` | 1 | `FC_DL_WordBitPack` |
| `0001_0109` | 1 | `FB_DL_MonthWindowCheck` |
| `0001_0112` | 1 | `FB_DL_ToleranceWindow` |
| `0001_0113~0115` | 3 | `FC_DL_BitFieldExtract` |
| `0001_0116~0117` | 2 | `FC_DL_WeekOfYearCalc` |
| `0001_0118` | 1 | `FB_DL_BidirectionalCounter` |
| `0001_0201` | 1 | `FC_DL_DayOfWeekCalc` |
| `0001_0202` | 1 | `FB_DL_TimeWindowCheck` |
| `0001_0203` | 1 | `FB_DL_MonthWindowCheck` |
| `0001_0210` | 1 | `FB_DL_EventCounter` |
| `0001_0211` | 1 | `FB_DL_ModuloCounter` |
| `0001_0212` | 1 | `FB_DL_PresetCounterSat` |
| `0001_0213` | 1 | `FB_DL_ToleranceWindow` |
| `0001_0214` | 1 | `FC_DL_LimitClassify` |
| `0001_0215~0216` | 2 | `FB_DL_BidirectionalCounter` |
| `0002_0001~0003` | 3 | `FB_DL_TwoHandSafety` |
| `0002_0004` | 1 | `FB_DL_InterlockMatrix` |
| `0002_0005~0006` | 2 | `FB_DL_RedundantSwitch` |
| `0002_0007~0008` | 2 | `FB_DL_DutyStandbyRotation` |

> 本目录 `.st` 字面量码位合计 **39** 个（含预留未触发位，见 §附 说明）。

#### 3.1.2 连续空闲块（≥3 码）

| 空闲块 | 码数 |
|---|---|
| `0001_000F~0100` | 242 |
| `0001_011E~0200` | 227 |
| `0001_0209~020F` | 7 |
| `0001_0218~02FF` | 232 |
| `0002_000E~0100` | 243 |
| `0002_0103~0200` | 254 |
| `0002_0202~02FF` | 254 |

#### 3.1.3 下一个可用码位建议

| 级别 | 主推码位 | 建议号段 |
|---|---|---|
| 信息级 | **`0001_011E`** | `0001_011E~012D（16 码，与 DL_MathData 按 §2 分界）` |
| 故障级 | **`0001_0218`** | `0001_0218~0227（16 码）` |

> 备选：即时单码空隙 `0001_0111`（1 码）／`0001_0209~020F`（7 码）

#### 3.1.4 现有组件命名全清单（避让重名）

- **功能块 FB（21）**：`FB_DL_AlarmManager`、`FB_DL_BidirectionalCounter`、`FB_DL_CycleTimeMeasure`、`FB_DL_DualEdgeTrig`、`FB_DL_DutyStandbyRotation`、`FB_DL_EventCounter`、`FB_DL_ExtendedTimer`、`FB_DL_InterlockMatrix`、`FB_DL_ModuloCounter`、`FB_DL_MonthWindowCheck`、`FB_DL_PresetCounterSat`、`FB_DL_PulseGenerator`、`FB_DL_RedundantSwitch`、`FB_DL_RuntimeMeter`、`FB_DL_SignalDebounce`、`FB_DL_StepSequencer`、`FB_DL_TimeWindowCheck`、`FB_DL_ToleranceWindow`、`FB_DL_TwoHandSafety`、`FB_DL_UnpackWordToBits`、`FB_DL_WatchdogMonitor`
- **函数 FC（11）**：`FC_DL_BinaryToGray`、`FC_DL_BitCount`、`FC_DL_BitFieldExtract`、`FC_DL_BitGet`、`FC_DL_BitSet`、`FC_DL_DayOfWeekCalc`、`FC_DL_GrayToBinary`、`FC_DL_LimitClassify`、`FC_DL_PackBitsToWord`、`FC_DL_WeekOfYearCalc`、`FC_DL_WordBitPack`


### 3.2 `DL_MathData`

Level 0 数学与数据处理层｜29 组件｜码族 `0001`（与 Base 共享）+ `0002_0009~000D`

#### 3.2.1 已占用码段（精确到号段，按归属组件切分）

| 码段 | 码数 | 归属组件（`.st` 内实际字面量） |
|---|---|---|
| `0001_0001` | 1 | `FB_DL_MedianFilter`、`FB_DL_MovingAverage`、`FB_DL_SignalStatistics`、`FC_DL_Crc16Modbus`、`FC_DL_Crc32Ethernet`、`FC_DL_HexStringToBytes`、`FC_DL_LineIntersection`、`FC_DL_LrcChecksum`、`FC_DL_MultiPointLinear`、`FC_DL_PolygonArea`、`FC_DL_QuickSortLReal`、`FC_DL_StringSplit` |
| `0001_0002` | 1 | `FC_DL_LinearScale` |
| `0001_0003` | 1 | `FC_DL_Deadband`、`FC_DL_Hysteresis` |
| `0001_0004` | 1 | `FB_DL_MedianFilter`、`FB_DL_SignalStatistics`、`FC_DL_MultiPointLinear`、`FC_DL_PolygonArea`、`FC_DL_QuickSortLReal`、`FC_DL_StringSplit`、`FC_DL_StringTrim` |
| `0001_0005` | 1 | `FB_DL_LifoStack`、`FB_DL_MedianFilter`、`FB_DL_MovingAverage`、`FB_DL_SignalStatistics` |
| `0001_0006` | 1 | `FB_DL_MedianFilter`、`FB_DL_SignalStatistics`、`FC_DL_LinearScale`、`FC_DL_QuickSortLReal` |
| `0001_0007` | 1 | `FB_DL_LifoStack`、`FC_DL_QuickSortLReal` |
| `0001_0008` | 1 | `FC_DL_StringSplit` |
| `0001_0009` | 1 | `FB_DL_LifoStack`、`FB_DL_RingBufferLReal`、`FC_DL_HexStringToBytes` |
| `0001_000A` | 1 | `FB_DL_LifoStack`、`FB_DL_RingBufferLReal` |
| `0001_000D` | 1 | `FC_DL_StringSplit` |
| `0001_000E` | 1 | `FC_DL_SwapBytes32` |
| `0001_0105` | 1 | `FC_DL_BcdToWord` |
| `0001_0106~0107` | 2 | `FC_DL_WordToBcd` |
| `0001_010A~010D` | 4 | `FB_DL_FifoBuffer` |
| `0001_010E` | 1 | `FB_DL_ArraySearchFirst` |
| `0001_010F` | 1 | `FC_DL_BinarySearchLReal` |
| `0001_0110` | 1 | `FC_DL_TempUnitConvert` |
| `0001_0119~011A` | 2 | `FC_DL_SearchMinMax` |
| `0001_011B~011C` | 2 | `FC_DL_NthRoot` |
| `0001_011D` | 1 | `FC_DL_FactorialSat` |
| `0001_0204` | 1 | `FB_DL_FifoBuffer` |
| `0001_0205` | 1 | `FB_DL_ArraySearchFirst` |
| `0001_0206` | 1 | `FC_DL_BinarySearchLReal` |
| `0001_0207~0208` | 2 | `FC_DL_TempUnitConvert` |
| `0001_0217` | 1 | `FC_DL_SearchMinMax` |
| `0002_0009` | 1 | `FB_DL_SignalStatistics` |
| `0002_000A` | 1 | `FC_DL_HexStringToBytes` |
| `0002_000B` | 1 | `FC_DL_MultiPointLinear` |
| `0002_000C` | 1 | `FC_DL_PolygonArea` |
| `0002_000D` | 1 | `FC_DL_LineIntersection` |

> 本目录 `.st` 字面量码位合计 **38** 个（含预留未触发位，见 §附 说明）。

#### 3.2.2 连续空闲块（≥3 码）

| 空闲块 | 码数 |
|---|---|
| `0001_000F~0100` | 242 |
| `0001_011E~0200` | 227 |
| `0001_0209~020F` | 7 |
| `0001_0218~02FF` | 232 |
| `0002_000E~0100` | 243 |
| `0002_0103~0200` | 254 |
| `0002_0202~02FF` | 254 |

#### 3.2.3 下一个可用码位建议

| 级别 | 主推码位 | 建议号段 |
|---|---|---|
| 信息级 | **`0001_012E`** | `0001_012E~013D（16 码，Base 取 011E 起后的顺延段）` |
| 故障级 | **`0001_0228`** | `0001_0228~0237（16 码）` |

> 备选：即时单码空隙 `0001_0111`（1 码）／`0001_0209~020F`（7 码）

#### 3.2.4 现有组件命名全清单（避让重名）

- **功能块 FB（7）**：`FB_DL_ArraySearchFirst`、`FB_DL_FifoBuffer`、`FB_DL_LifoStack`、`FB_DL_MedianFilter`、`FB_DL_MovingAverage`、`FB_DL_RingBufferLReal`、`FB_DL_SignalStatistics`
- **函数 FC（22）**：`FC_DL_BcdToWord`、`FC_DL_BinarySearchLReal`、`FC_DL_Crc16Modbus`、`FC_DL_Crc32Ethernet`、`FC_DL_Deadband`、`FC_DL_FactorialSat`、`FC_DL_HexStringToBytes`、`FC_DL_Hysteresis`、`FC_DL_LineIntersection`、`FC_DL_LinearScale`、`FC_DL_LrcChecksum`、`FC_DL_MultiPointLinear`、`FC_DL_NthRoot`、`FC_DL_PolygonArea`、`FC_DL_QuickSortLReal`、`FC_DL_SearchMinMax`、`FC_DL_StringSplit`、`FC_DL_StringTrim`、`FC_DL_SwapBytes16`、`FC_DL_SwapBytes32`、`FC_DL_TempUnitConvert`、`FC_DL_WordToBcd`


### 3.3 `DL_Algo`

Level 1 工业控制算法层｜24 组件｜码族 `0002`（与 Base/MathData 共享，按件独占 `1x00` 带）

#### 3.3.1 已占用码段（精确到号段，按归属组件切分）

| 码段 | 码数 | 归属组件（`.st` 内实际字面量） |
|---|---|---|
| `0002_0000` | 1 | `FB_DL_CascadePid`、`FB_DL_FeedforwardComp`、`FB_DL_HighPassFilter`、`FB_DL_LowPassFilter`、`FB_DL_PidController`、`FB_DL_RateLimiter`、`FB_DL_SecondOrderFilter`、`FB_DL_SmithPredictor`、`FB_DL_SplitRangeControl`、`FC_DL_DewPointCalc`、`FC_DL_FlowCompensate`、`FC_DL_HumidAirEnthalpy` |
| `0002_0001` | 1 | `FB_DL_CascadePid`、`FB_DL_Differentiator`、`FB_DL_FeedforwardComp`、`FB_DL_HighPassFilter`、`FB_DL_Integrator`、`FB_DL_PidController`、`FB_DL_PwmDutyController`、`FB_DL_RampGenerator`、`FB_DL_RateLimiter`、`FB_DL_SmithPredictor`、`FB_DL_SplitRangeControl`、`FC_DL_FlowCompensate` |
| `0002_0002` | 1 | `FB_DL_CascadePid`、`FB_DL_Differentiator`、`FB_DL_FeedforwardComp`、`FB_DL_HighPassFilter`、`FB_DL_Integrator`、`FB_DL_LowPassFilter`、`FB_DL_PidController`、`FB_DL_PwmDutyController`、`FB_DL_RampGenerator`、`FB_DL_RateLimiter`、`FB_DL_SCurveGenerator`、`FB_DL_SecondOrderFilter`、`FB_DL_SmithPredictor`、`FB_DL_SplitRangeControl` |
| `0002_0004` | 1 | `FB_DL_CascadePid`、`FB_DL_Differentiator`、`FB_DL_FeedforwardComp`、`FB_DL_HighPassFilter`、`FB_DL_Integrator`、`FB_DL_LowPassFilter`、`FB_DL_PidController`、`FB_DL_RampGenerator`、`FB_DL_RateLimiter`、`FB_DL_SCurveGenerator`、`FB_DL_SecondOrderFilter`、`FB_DL_SmithPredictor`、`FB_DL_SplitRangeControl`、`FC_DL_DewPointCalc`、`FC_DL_FlowCompensate`、`FC_DL_HumidAirEnthalpy` |
| `0002_0005` | 1 | `FB_DL_CascadePid`、`FB_DL_Differentiator`、`FB_DL_FeedforwardComp`、`FB_DL_HighPassFilter`、`FB_DL_Integrator`、`FB_DL_LowPassFilter`、`FB_DL_PidController`、`FB_DL_PwmDutyController`、`FB_DL_RampGenerator`、`FB_DL_RampSoakProfile`、`FB_DL_RateLimiter`、`FB_DL_SCurveGenerator`、`FB_DL_SecondOrderFilter`、`FB_DL_SmithPredictor`、`FB_DL_SplitRangeControl` |
| `0002_0101~0102` | 2 | `FB_DL_PidController` |
| `0002_0201` | 1 | `FB_DL_CascadePid` |
| `0002_0301` | 1 | `FB_DL_SplitRangeControl` |
| `0002_0401~0402` | 2 | `FB_DL_FeedforwardComp` |
| `0002_0501~0502` | 2 | `FB_DL_SmithPredictor` |
| `0002_0601` | 1 | `FB_DL_RampGenerator` |
| `0002_0701~0702` | 2 | `FB_DL_SCurveGenerator` |
| `0002_0801` | 1 | `FB_DL_PwmDutyController` |
| `0002_1001` | 1 | `FB_DL_LowPassFilter` |
| `0002_1101` | 1 | `FB_DL_SecondOrderFilter` |
| `0002_1201` | 1 | `FB_DL_HighPassFilter` |
| `0002_1401` | 1 | `FB_DL_Differentiator` |
| `0002_1501~1502` | 2 | `FC_DL_DewPointCalc` |
| `0002_1601~1602` | 2 | `FC_DL_FlowCompensate` |
| `0002_1701~1703` | 3 | `FC_DL_HumidAirEnthalpy` |
| `0002_1801~1804` | 4 | `FB_DL_RampSoakProfile` |
| `0002_1810` | 1 | `FB_DL_RampSoakProfile` |
| `0002_1901~1904` | 4 | `FB_DL_PeakDetector` |
| `0002_1A01~1A06` | 6 | `FB_DL_StepController` |
| `0002_1B01~1B04` | 4 | `FB_DL_SineGenerator` |
| `0002_1B10~1B11` | 2 | `FB_DL_SineGenerator` |
| `0002_1C01~1C03` | 3 | `FB_DL_SawtoothGenerator` |
| `0002_1C10` | 1 | `FB_DL_SawtoothGenerator` |
| `0002_1D01~1D04` | 4 | `FC_DL_CoilDiameterCalc` |
| `0002_1D10` | 1 | `FC_DL_CoilDiameterCalc` |
| `0002_1E01~1E04` | 4 | `FC_DL_AirDensity` |
| `0002_1E10` | 1 | `FC_DL_AirDensity` |

> 本目录 `.st` 字面量码位合计 **63** 个（含预留未触发位，见 §附 说明）。

#### 3.3.2 连续空闲块（≥3 码）

| 空闲块 | 码数 |
|---|---|
| `0002_000E~0100` | 243 |
| `0002_0103~0200` | 254 |
| `0002_0202~02FF` | 254 |

#### 3.3.3 下一个可用码位建议

| 级别 | 主推码位 | 建议号段 |
|---|---|---|
| 信息级 | **`0002_1F01`** | `0002_1F01~1F0E（14 码，新开 1F00 编号带）` |
| 故障级 | **`0002_1F10`** | `0002_1F10~1F1F（16 码，带内故障级）` |

> 备选：中段整带空置 `0002_0901~09FF` / `0002_1301~13FF`

#### 3.3.4 现有组件命名全清单（避让重名）

- **功能块 FB（19）**：`FB_DL_CascadePid`、`FB_DL_Differentiator`、`FB_DL_FeedforwardComp`、`FB_DL_HighPassFilter`、`FB_DL_Integrator`、`FB_DL_LowPassFilter`、`FB_DL_PeakDetector`、`FB_DL_PidController`、`FB_DL_PwmDutyController`、`FB_DL_RampGenerator`、`FB_DL_RampSoakProfile`、`FB_DL_RateLimiter`、`FB_DL_SCurveGenerator`、`FB_DL_SawtoothGenerator`、`FB_DL_SecondOrderFilter`、`FB_DL_SineGenerator`、`FB_DL_SmithPredictor`、`FB_DL_SplitRangeControl`、`FB_DL_StepController`
- **函数 FC（5）**：`FC_DL_AirDensity`、`FC_DL_CoilDiameterCalc`、`FC_DL_DewPointCalc`、`FC_DL_FlowCompensate`、`FC_DL_HumidAirEnthalpy`


### 3.4 `DL_Device`

Level 1 物理设备 OOP 抽象层｜36 组件｜码族 `0003`（独占）

#### 3.4.1 已占用码段（精确到号段，按归属组件切分）

| 码段 | 码数 | 归属组件（`.st` 内实际字面量） |
|---|---|---|
| `0003_0101` | 1 | `FB_DL_HeatCoolZone` |
| `0003_0102~0104` | 3 | `FB_DL_AnalogTransmitter` |
| `0003_0106~0107` | 2 | `FB_DL_VfdGeneric` |
| `0003_0108~0109` | 2 | `FB_DL_AnalogValve` |
| `0003_0110~0111` | 2 | `FB_DL_ThreePointValve` |
| `0003_0112` | 1 | `FB_DL_AnalogValve` |
| `0003_0113~0115` | 3 | `FB_DL_PulseFlowMeter` |
| `0003_0117` | 1 | `FB_DL_SerialScanner` |
| `0003_0118` | 1 | `FB_DL_SafetyLightCurtain` |
| `0003_0119` | 1 | `FB_DL_SerialScanner` |
| `0003_0120` | 1 | `FB_DL_SerialScanner` |
| `0003_0121` | 1 | `FB_DL_GuardLockDoor` |
| `0003_0122` | 1 | `FB_DL_SafetyLightCurtain` |
| `0003_0123~0126` | 4 | `FB_DL_SignalTower` |
| `0003_0130~0137` | 8 | `FB_DL_PulseDirStepper` |
| `0003_0138~013A` | 3 | `FB_DL_RfidTagHandler` |
| `0003_013B~013C` | 2 | `FB_DL_AxiolineDiagLatch` |
| `0003_013D~013F` | 3 | `FB_DL_PdiReadScheduler` |
| `0003_0201` | 1 | `FB_DL_DolMotor`、`FB_DL_PneumaticCylinder`、`FB_DL_StarDeltaMotor` |
| `0003_0202~0204` | 3 | `FB_DL_PneumaticCylinder` |
| `0003_0205~0207` | 3 | `FB_DL_DolMotor` |
| `0003_0208` | 1 | `FB_DL_DolMotor`、`FB_DL_StarDeltaMotor` |
| `0003_0209~020A` | 2 | `FB_DL_DolMotor` |
| `0003_0210` | 1 | `FB_DL_AnalogTransmitter` |
| `0003_0211~0213` | 3 | `FB_DL_HeatCoolZone` |
| `0003_0220~0222` | 3 | `FB_DL_SingleSolenoidCyl` |
| `0003_0230~0232` | 3 | `FB_DL_VacuumEjector` |
| `0003_0240~0246` | 7 | `FB_DL_StarDeltaMotor` |
| `0003_0250~0252` | 3 | `FB_DL_VfdGeneric` |
| `0003_0260~0261` | 2 | `FB_DL_AnalogValve` |
| `0003_0270~0272` | 3 | `FB_DL_ThreePointValve` |
| `0003_0280` | 1 | `FB_DL_SerialScanner` |
| `0003_0282` | 1 | `FB_DL_SerialScanner` |
| `0003_0290~0293` | 4 | `FB_DL_GuardLockDoor` |
| `0003_02A0~02A2` | 3 | `FB_DL_SafetyLightCurtain` |
| `0003_02B0` | 1 | `FB_DL_PulseFlowMeter` |
| `0003_02C0` | 1 | `FB_DL_LevelSwitchVib` |
| `0003_02D0~02D1` | 2 | `FB_DL_SignalTower` |
| `0003_02E0~02E4` | 5 | `FB_DL_PulseDirStepper` |
| `0003_02F0~02F3` | 4 | `FB_DL_RfidTagHandler` |
| `0003_02F4~02F6` | 3 | `FB_DL_AxiolineDiagLatch` |
| `0003_02F7~02F9` | 3 | `FB_DL_PdiReadScheduler` |

> 本目录 `.st` 字面量码位合计 **103** 个（含预留未触发位，见 §附 说明）。

#### 3.4.2 连续空闲块（≥3 码）

| 空闲块 | 码数 |
|---|---|
| `0003_0001~0100` | 256 |
| `0003_010A~010F` | 6 |
| `0003_011A~011F` | 6 |
| `0003_0127~012F` | 9 |
| `0003_0140~0200` | 193 |
| `0003_020B~020F` | 5 |
| `0003_0214~021F` | 12 |
| `0003_0223~022F` | 13 |
| `0003_0233~023F` | 13 |
| `0003_0247~024F` | 9 |
| `0003_0253~025F` | 13 |
| `0003_0262~026F` | 14 |
| `0003_0273~027F` | 13 |
| `0003_0283~028F` | 13 |
| `0003_0294~029F` | 12 |
| `0003_02A3~02AF` | 13 |
| `0003_02B1~02BF` | 15 |
| `0003_02C1~02CF` | 15 |
| `0003_02D2~02DF` | 14 |
| `0003_02E5~02EF` | 11 |
| `0003_02FA~02FF` | 6 |

#### 3.4.3 下一个可用码位建议

| 级别 | 主推码位 | 建议号段 |
|---|---|---|
| 信息级 | **`0003_010A`** | `0003_010A~010F（6 码，紧邻 0109 之后）` |
| 故障级 | **`0003_0214`** | `0003_0214~021F（12 码）` |

> 备选：批量块 `0003_0140~014F`（16 码，全新子块，新族件优先）

#### 3.4.4 现有组件命名全清单（避让重名）

- **接口 INTERFACE（16）**：`I_DL_AnalogSensor`、`I_DL_BarcodeScanner`、`I_DL_Cylinder`、`I_DL_FlowMeter`、`I_DL_LevelSwitch`、`I_DL_LightCurtain`、`I_DL_MotorDriver`、`I_DL_MotorizedValve`、`I_DL_ProportionalValve`、`I_DL_RfidReader`、`I_DL_SafetyDoor`、`I_DL_StepperOpenLoop`、`I_DL_TemperatureZone`、`I_DL_TowerLight`、`I_DL_VacuumGenerator`、`I_DL_VfdDrive`
- **功能块 FB（20）**：`FB_DL_AnalogTransmitter`、`FB_DL_AnalogValve`、`FB_DL_AxiolineDiagLatch`、`FB_DL_DolMotor`、`FB_DL_GuardLockDoor`、`FB_DL_HeatCoolZone`、`FB_DL_LevelSwitchVib`、`FB_DL_PdiReadScheduler`、`FB_DL_PneumaticCylinder`、`FB_DL_PulseDirStepper`、`FB_DL_PulseFlowMeter`、`FB_DL_RfidTagHandler`、`FB_DL_SafetyLightCurtain`、`FB_DL_SerialScanner`、`FB_DL_SignalTower`、`FB_DL_SingleSolenoidCyl`、`FB_DL_StarDeltaMotor`、`FB_DL_ThreePointValve`、`FB_DL_VacuumEjector`、`FB_DL_VfdGeneric`


### 3.5 `DL_Motion`

Level 1 运动控制封装层｜15 组件｜码族 `0004`（独占）

#### 3.5.1 已占用码段（精确到号段，按归属组件切分）

| 码段 | 码数 | 归属组件（`.st` 内实际字面量） |
|---|---|---|
| `0004_0101` | 1 | `FB_DL_SingleAxis` |
| `0004_0102` | 1 | `FB_DL_AxisJogController` |
| `0004_0103` | 1 | `FB_DL_AxisJogController`、`FB_DL_SingleAxis` |
| `0004_0104` | 1 | `FB_DL_SingleAxis` |
| `0004_0105` | 1 | `FB_DL_AxisJogController`、`FB_DL_SingleAxis` |
| `0004_0106` | 1 | `FB_DL_AxisHomingSeq`、`FB_DL_AxisRelativeMove`、`FB_DL_AxisVelocityMove` |
| `0004_0107` | 1 | `FB_DL_AxisVelocityMove` |
| `0004_0108` | 1 | `FB_DL_SoftLimitGuard` |
| `0004_0130~0132` | 3 | `FB_DL_ElectronicGear` |
| `0004_0140~0142` | 3 | `FB_DL_ElectronicCam` |
| `0004_0150~0152` | 3 | `FB_DL_GantrySyncAxis` |
| `0004_0160~0164` | 5 | `FB_DL_TorqueLimitControl` |
| `0004_0170~0171` | 2 | `FB_DL_MarkPositionLatch` |
| `0004_0180~0184` | 5 | `FC_DL_CalcMoveTime` |
| `0004_01A0~01A3` | 4 | `FB_DL_SuperimposedMove` |
| `0004_01B0~01B3` | 4 | `FB_DL_WindingTraverse` |
| `0004_0201` | 1 | `FB_DL_AxisRelativeMove`、`FB_DL_AxisVelocityMove`、`FB_DL_SingleAxis` |
| `0004_0202~0203` | 2 | `FB_DL_SingleAxis` |
| `0004_0210~0213` | 4 | `FB_DL_AxisHomingSeq` |
| `0004_0220~0221` | 2 | `FB_DL_AxisRelativeMove` |
| `0004_0230` | 1 | `FB_DL_AxisVelocityMove` |
| `0004_0240~0241` | 2 | `FB_DL_SoftLimitGuard` |
| `0004_0250~0252` | 3 | `FB_DL_ElectronicGear` |
| `0004_0260~0265` | 6 | `FB_DL_ElectronicCam` |
| `0004_0270~0274` | 5 | `FB_DL_GantrySyncAxis` |
| `0004_0280~0284` | 5 | `FB_DL_TorqueLimitControl` |
| `0004_0290` | 1 | `FB_DL_MarkPositionLatch` |
| `0004_0295` | 1 | `FB_DL_MarkPositionLatch` |
| `0004_0296` | 1 | `FB_DL_TorqueLimitControl` |
| `0004_0297` | 1 | `FB_DL_GantrySyncAxis` |
| `0004_0298` | 1 | `FB_DL_ElectronicCam` |
| `0004_0299` | 1 | `FB_DL_ElectronicGear` |
| `0004_02B0~02B2` | 3 | `FB_DL_SuperimposedMove` |
| `0004_02C0~02C3` | 4 | `FB_DL_WindingTraverse` |

> 本目录 `.st` 字面量码位合计 **81** 个（含预留未触发位，见 §附 说明）。

#### 3.5.2 连续空闲块（≥3 码）

| 空闲块 | 码数 |
|---|---|
| `0004_0001~0100` | 256 |
| `0004_0109~012F` | 39 |
| `0004_0133~013F` | 13 |
| `0004_0143~014F` | 13 |
| `0004_0153~015F` | 13 |
| `0004_0165~016F` | 11 |
| `0004_0172~017F` | 14 |
| `0004_0185~019F` | 27 |
| `0004_01A4~01AF` | 12 |
| `0004_01B4~0200` | 77 |
| `0004_0204~020F` | 12 |
| `0004_0214~021F` | 12 |
| `0004_0222~022F` | 14 |
| `0004_0231~023F` | 15 |
| `0004_0242~024F` | 14 |
| `0004_0253~025F` | 13 |
| `0004_0266~026F` | 10 |
| `0004_0275~027F` | 11 |
| `0004_0285~028F` | 11 |
| `0004_0291~0294` | 4 |
| `0004_029A~02AF` | 22 |
| `0004_02B3~02BF` | 13 |
| `0004_02C4~02FF` | 60 |

#### 3.5.3 下一个可用码位建议

| 级别 | 主推码位 | 建议号段 |
|---|---|---|
| 信息级 | **`0004_0109`** | `0004_0109~012F（39 码，本库最大连续空块）` |
| 故障级 | **`0004_0204`** | `0004_0204~020F（12 码）` |

> 备选：批量块 `0004_02D0~02DF`

#### 3.5.4 现有组件命名全清单（避让重名）

- **接口 INTERFACE（1）**：`I_DL_MotionAxis`
- **功能块 FB（13）**：`FB_DL_AxisHomingSeq`、`FB_DL_AxisJogController`、`FB_DL_AxisRelativeMove`、`FB_DL_AxisVelocityMove`、`FB_DL_ElectronicCam`、`FB_DL_ElectronicGear`、`FB_DL_GantrySyncAxis`、`FB_DL_MarkPositionLatch`、`FB_DL_SingleAxis`、`FB_DL_SoftLimitGuard`、`FB_DL_SuperimposedMove`、`FB_DL_TorqueLimitControl`、`FB_DL_WindingTraverse`
- **函数 FC（1）**：`FC_DL_CalcMoveTime`


### 3.6 `DL_Process`

Level 2 行业工艺与工站模板层｜16 组件｜码族 `0005`（独占）

#### 3.6.1 已占用码段（精确到号段，按归属组件切分）

| 码段 | 码数 | 归属组件（`.st` 内实际字面量） |
|---|---|---|
| `0005_0101` | 1 | `FB_DL_PackMlStateMachine` |
| `0005_0102` | 1 | `FB_DL_PackMlCmdDecoder` |
| `0005_0103` | 1 | `FB_DL_EnthalpyCompareCtrl` |
| `0005_0110~0112` | 3 | `FB_DL_OeeCalculator` |
| `0005_0113` | 1 | `FB_DL_ConveyorZone` |
| `0005_0114~0115` | 2 | `FB_DL_BatchDosingControl` |
| `0005_0130~0133` | 4 | `FB_DL_ConveyorLineLink` |
| `0005_0140~0143` | 4 | `FB_DL_RecipeManager` |
| `0005_0150~0153` | 4 | `FB_DL_LeakTestStation` |
| `0005_0160~0164` | 5 | `FB_DL_MixRecipeControl` |
| `0005_0170~0173` | 4 | `FB_DL_CipCleaningSeq` |
| `0005_0180~0186` | 7 | `FB_DL_BufferMagazine` |
| `0005_0190~0193` | 4 | `FB_DL_ModbusPollMaster` |
| `0005_01A0~01A1` | 2 | `FB_DL_AndonCallSystem` |
| `0005_01B0~01B4` | 5 | `FB_DL_PickAndPlaceStation` |
| `0005_0200` | 1 | `FB_DL_OeeCalculator` |
| `0005_0201` | 1 | `FB_DL_EnthalpyCompareCtrl`、`FB_DL_PackMlStateMachine` |
| `0005_0202` | 1 | `FB_DL_EnthalpyCompareCtrl` |
| `0005_0210~0211` | 2 | `FB_DL_OccScheduleWindow` |
| `0005_0212~0214` | 3 | `FB_DL_ConveyorZone` |
| `0005_0220~0223` | 4 | `FB_DL_BatchDosingControl` |
| `0005_0230~0231` | 2 | `FB_DL_ConveyorLineLink` |
| `0005_0240~0246` | 7 | `FB_DL_RecipeManager` |
| `0005_0250~0257` | 8 | `FB_DL_LeakTestStation` |
| `0005_0260~0265` | 6 | `FB_DL_MixRecipeControl` |
| `0005_0270~0274` | 5 | `FB_DL_CipCleaningSeq` |
| `0005_0280~0283` | 4 | `FB_DL_BufferMagazine` |
| `0005_0290~0292` | 3 | `FB_DL_ModbusPollMaster` |
| `0005_02A0~02A1` | 2 | `FB_DL_AndonCallSystem` |
| `0005_02B0~02B7` | 8 | `FB_DL_PickAndPlaceStation` |

> 本目录 `.st` 字面量码位合计 **105** 个（含预留未触发位，见 §附 说明）。

#### 3.6.2 连续空闲块（≥3 码）

| 空闲块 | 码数 |
|---|---|
| `0005_0001~0100` | 256 |
| `0005_0104~010F` | 12 |
| `0005_0116~012F` | 26 |
| `0005_0134~013F` | 12 |
| `0005_0144~014F` | 12 |
| `0005_0154~015F` | 12 |
| `0005_0165~016F` | 11 |
| `0005_0174~017F` | 12 |
| `0005_0187~018F` | 9 |
| `0005_0194~019F` | 12 |
| `0005_01A2~01AF` | 14 |
| `0005_01B5~01FF` | 75 |
| `0005_0203~020F` | 13 |
| `0005_0215~021F` | 11 |
| `0005_0224~022F` | 12 |
| `0005_0232~023F` | 14 |
| `0005_0247~024F` | 9 |
| `0005_0258~025F` | 8 |
| `0005_0266~026F` | 10 |
| `0005_0275~027F` | 11 |
| `0005_0284~028F` | 12 |
| `0005_0293~029F` | 13 |
| `0005_02A2~02AF` | 14 |
| `0005_02B8~02FF` | 72 |

#### 3.6.3 下一个可用码位建议

| 级别 | 主推码位 | 建议号段 |
|---|---|---|
| 信息级 | **`0005_0104`** | `0005_0104~010F（12 码）` |
| 故障级 | **`0005_0203`** | `0005_0203~020F（13 码）` |

> 备选：批量块 `0005_01C0~01CF` / `0005_02C0~02CF`（全新子块）

#### 3.6.4 现有组件命名全清单（避让重名）

- **功能块 FB（16）**：`FB_DL_AndonCallSystem`、`FB_DL_BatchDosingControl`、`FB_DL_BufferMagazine`、`FB_DL_CipCleaningSeq`、`FB_DL_ConveyorLineLink`、`FB_DL_ConveyorZone`、`FB_DL_EnthalpyCompareCtrl`、`FB_DL_LeakTestStation`、`FB_DL_MixRecipeControl`、`FB_DL_ModbusPollMaster`、`FB_DL_OccScheduleWindow`、`FB_DL_OeeCalculator`、`FB_DL_PackMlCmdDecoder`、`FB_DL_PackMlStateMachine`、`FB_DL_PickAndPlaceStation`、`FB_DL_RecipeManager`


---

## 4. 全库 ENUM 类型名清单（95 个，禁重复定义同名异型副本）

> 历史教训：曾出现同名 ENUM 在多个文件中各自声明且成员编号不一致（`FB_DL_HeatCoolZone.st` 就地重复声明 `E_DL_SignalQuality` / `I_DL_AnalogSensor`，收口阶段删除重复副本）。**新件引用既有 ENUM 一律 import 宿主文件，禁止就地复制声明**。

| # | ENUM 名称 | 成员数 | 宿主文件 | 所属子库 |
|---|---|---|---|---|
| 1 | `E_DL_RotationState` | 4 | `FB_DL_DutyStandbyRotation.st` | `DL_Base` |
| 2 | `E_DL_ExtTimerState` | 4 | `FB_DL_ExtendedTimer.st` | `DL_Base` |
| 3 | `E_DL_TimerMode` | 4 | `FB_DL_ExtendedTimer.st` | `DL_Base` |
| 4 | `E_DL_InterlockState` | 5 | `FB_DL_InterlockMatrix.st` | `DL_Base` |
| 5 | `E_DL_PulsePhase` | 4 | `FB_DL_PulseGenerator.st` | `DL_Base` |
| 6 | `E_DL_ActiveChannel` | 3 | `FB_DL_RedundantSwitch.st` | `DL_Base` |
| 7 | `E_DL_DeviationPolicy` | 4 | `FB_DL_RedundantSwitch.st` | `DL_Base` |
| 8 | `E_DL_RedundState` | 5 | `FB_DL_RedundantSwitch.st` | `DL_Base` |
| 9 | `E_DL_RedundancyPriority` | 3 | `FB_DL_RedundantSwitch.st` | `DL_Base` |
| 10 | `E_DL_DebounceState` | 5 | `FB_DL_SignalDebounce.st` | `DL_Base` |
| 11 | `E_DL_SeqState` | 5 | `FB_DL_StepSequencer.st` | `DL_Base` |
| 12 | `E_DL_TolJudge` | 4 | `FB_DL_ToleranceWindow.st` | `DL_Base` |
| 13 | `E_DL_TwoHandState` | 5 | `FB_DL_TwoHandSafety.st` | `DL_Base` |
| 14 | `E_DL_WdtState` | 3 | `FB_DL_WatchdogMonitor.st` | `DL_Base` |
| 15 | `E_DL_Weekday` | 8 | `FC_DL_DayOfWeekCalc.st` | `DL_Base` |
| 16 | `E_DL_LimitBand` | 6 | `FC_DL_LimitClassify.st` | `DL_Base` |
| 17 | `E_DL_StackState` | 3 | `FB_DL_LifoStack.st` | `DL_MathData` |
| 18 | `E_DL_MedianState` | 4 | `FB_DL_MedianFilter.st` | `DL_MathData` |
| 19 | `E_DL_MovingAverageState` | 3 | `FB_DL_MovingAverage.st` | `DL_MathData` |
| 20 | `E_DL_StatState` | 4 | `FB_DL_SignalStatistics.st` | `DL_MathData` |
| 21 | `E_DL_ByteOrder` | 4 | `FC_DL_SwapBytes32.st` | `DL_MathData` |
| 22 | `E_DL_TempUnit` | 3 | `FC_DL_TempUnitConvert.st` | `DL_MathData` |
| 23 | `E_DL_CascadeState` | 4 | `FB_DL_CascadePid.st` | `DL_Algo` |
| 24 | `E_DL_DiffState` | 4 | `FB_DL_Differentiator.st` | `DL_Algo` |
| 25 | `E_DL_FfState` | 4 | `FB_DL_FeedforwardComp.st` | `DL_Algo` |
| 26 | `E_DL_HpfState` | 4 | `FB_DL_HighPassFilter.st` | `DL_Algo` |
| 27 | `E_DL_IntState` | 5 | `FB_DL_Integrator.st` | `DL_Algo` |
| 28 | `E_DL_LpfState` | 4 | `FB_DL_LowPassFilter.st` | `DL_Algo` |
| 29 | `E_DL_PidState` | 4 | `FB_DL_PidController.st` | `DL_Algo` |
| 30 | `E_DL_PwmState` | 4 | `FB_DL_PwmDutyController.st` | `DL_Algo` |
| 31 | `E_DL_RampState` | 6 | `FB_DL_RampGenerator.st` | `DL_Algo` |
| 32 | `E_DL_RampSoakPhase` | 5 | `FB_DL_RampSoakProfile.st` | `DL_Algo` |
| 33 | `E_DL_RateState` | 5 | `FB_DL_RateLimiter.st` | `DL_Algo` |
| 34 | `E_DL_SCurveState` | 10 | `FB_DL_SCurveGenerator.st` | `DL_Algo` |
| 35 | `E_DL_SawState` | 3 | `FB_DL_SawtoothGenerator.st` | `DL_Algo` |
| 36 | `E_DL_SofState` | 5 | `FB_DL_SecondOrderFilter.st` | `DL_Algo` |
| 37 | `E_DL_SigGenState` | 3 | `FB_DL_SineGenerator.st` | `DL_Algo` |
| 38 | `E_DL_SmithState` | 5 | `FB_DL_SmithPredictor.st` | `DL_Algo` |
| 39 | `E_DL_SplitState` | 5 | `FB_DL_SplitRangeControl.st` | `DL_Algo` |
| 40 | `E_DL_BreakDir` | 2 | `FB_DL_AnalogTransmitter.st` | `DL_Device` |
| 41 | `E_DL_DiagFsm` | 4 | `FB_DL_AxiolineDiagLatch.st` | `DL_Device` |
| 42 | `E_DL_DiagLevel` | 4 | `FB_DL_AxiolineDiagLatch.st` | `DL_Device` |
| 43 | `E_DL_BreakAction` | 2 | `FB_DL_HeatCoolZone.st` | `DL_Device` |
| 44 | `E_DL_PdiFsm` | 5 | `FB_DL_PdiReadScheduler.st` | `DL_Device` |
| 45 | `E_DL_StepperState` | 5 | `FB_DL_PulseDirStepper.st` | `DL_Device` |
| 46 | `E_DL_RfidFsm` | 5 | `FB_DL_RfidTagHandler.st` | `DL_Device` |
| 47 | `E_DL_RfidReq` | 3 | `FB_DL_RfidTagHandler.st` | `DL_Device` |
| 48 | `E_DL_SignalQuality` | 4 | `I_DL_AnalogSensor.st` | `DL_Device` |
| 49 | `E_DL_ScannerState` | 6 | `I_DL_BarcodeScanner.st` | `DL_Device` |
| 50 | `E_DL_CylinderState` | 6 | `I_DL_Cylinder.st` | `DL_Device` |
| 51 | `E_DL_FlowMeterState` | 2 | `I_DL_FlowMeter.st` | `DL_Device` |
| 52 | `E_DL_FailSafeMode` | 2 | `I_DL_LevelSwitch.st` | `DL_Device` |
| 53 | `E_DL_LevelState` | 3 | `I_DL_LevelSwitch.st` | `DL_Device` |
| 54 | `E_DL_CurtainState` | 2 | `I_DL_LightCurtain.st` | `DL_Device` |
| 55 | `E_DL_MotorState` | 6 | `I_DL_MotorDriver.st` | `DL_Device` |
| 56 | `E_DL_MotorValveState` | 6 | `I_DL_MotorizedValve.st` | `DL_Device` |
| 57 | `E_DL_ValveState` | 3 | `I_DL_ProportionalValve.st` | `DL_Device` |
| 58 | `E_DL_RfidState` | 5 | `I_DL_RfidReader.st` | `DL_Device` |
| 59 | `E_DL_SafetyDoorState` | 7 | `I_DL_SafetyDoor.st` | `DL_Device` |
| 60 | `E_DL_TempZoneState` | 6 | `I_DL_TemperatureZone.st` | `DL_Device` |
| 61 | `E_DL_TowerColor` | 6 | `I_DL_TowerLight.st` | `DL_Device` |
| 62 | `E_DL_TowerPattern` | 5 | `I_DL_TowerLight.st` | `DL_Device` |
| 63 | `E_DL_TowerState` | 7 | `I_DL_TowerLight.st` | `DL_Device` |
| 64 | `E_DL_VacuumState` | 5 | `I_DL_VacuumGenerator.st` | `DL_Device` |
| 65 | `E_DL_VfdState` | 6 | `I_DL_VfdDrive.st` | `DL_Device` |
| 66 | `E_DL_HomingMode` | 4 | `FB_DL_AxisHomingSeq.st` | `DL_Motion` |
| 67 | `E_DL_HomingStep` | 2 | `FB_DL_AxisHomingSeq.st` | `DL_Motion` |
| 68 | `E_DL_RelStep` | 1 | `FB_DL_AxisRelativeMove.st` | `DL_Motion` |
| 69 | `E_DL_VelStep` | 2 | `FB_DL_AxisVelocityMove.st` | `DL_Motion` |
| 70 | `E_DL_CamState` | 7 | `FB_DL_ElectronicCam.st` | `DL_Motion` |
| 71 | `E_DL_GearState` | 5 | `FB_DL_ElectronicGear.st` | `DL_Motion` |
| 72 | `E_DL_GantryState` | 6 | `FB_DL_GantrySyncAxis.st` | `DL_Motion` |
| 73 | `E_DL_MarkState` | 4 | `FB_DL_MarkPositionLatch.st` | `DL_Motion` |
| 74 | `E_DL_OverlayState` | 3 | `FB_DL_SuperimposedMove.st` | `DL_Motion` |
| 75 | `E_DL_PressState` | 7 | `FB_DL_TorqueLimitControl.st` | `DL_Motion` |
| 76 | `E_DL_WindState` | 5 | `FB_DL_WindingTraverse.st` | `DL_Motion` |
| 77 | `E_DL_AxisState` | 3 | `I_DL_MotionAxis.st` | `DL_Motion` |
| 78 | `E_DL_AndonLevel` | 5 | `FB_DL_AndonCallSystem.st` | `DL_Process` |
| 79 | `E_DL_AndonState` | 4 | `FB_DL_AndonCallSystem.st` | `DL_Process` |
| 80 | `E_DL_DosingPhase` | 8 | `FB_DL_BatchDosingControl.st` | `DL_Process` |
| 81 | `E_DL_MagState` | 7 | `FB_DL_BufferMagazine.st` | `DL_Process` |
| 82 | `E_DL_SlotState` | 4 | `FB_DL_BufferMagazine.st` | `DL_Process` |
| 83 | `E_DL_CipPhase` | 10 | `FB_DL_CipCleaningSeq.st` | `DL_Process` |
| 84 | `E_DL_LineLinkState` | 6 | `FB_DL_ConveyorLineLink.st` | `DL_Process` |
| 85 | `E_DL_ZoneState` | 4 | `FB_DL_ConveyorZone.st` | `DL_Process` |
| 86 | `E_DL_EnthalpyHyst` | 2 | `FB_DL_EnthalpyCompareCtrl.st` | `DL_Process` |
| 87 | `E_DL_LeakPhase` | 10 | `FB_DL_LeakTestStation.st` | `DL_Process` |
| 88 | `E_DL_MixPhase` | 10 | `FB_DL_MixRecipeControl.st` | `DL_Process` |
| 89 | `E_DL_MbTxnResult` | 4 | `FB_DL_ModbusPollMaster.st` | `DL_Process` |
| 90 | `E_DL_PollState` | 6 | `FB_DL_ModbusPollMaster.st` | `DL_Process` |
| 91 | `E_DL_PackMlCmd` | 12 | `FB_DL_PackMlStateMachine.st` | `DL_Process` |
| 92 | `E_DL_PackMlState` | 2 | `FB_DL_PackMlStateMachine.st` | `DL_Process` |
| 93 | `E_DL_UnitMode` | 16 | `FB_DL_PackMlStateMachine.st` | `DL_Process` |
| 94 | `E_DL_SpState` | 7 | `FB_DL_PickAndPlaceStation.st` | `DL_Process` |
| 95 | `E_DL_RecipeState` | 6 | `FB_DL_RecipeManager.st` | `DL_Process` |

**按目录计数**：`DL_Base` 16 个 ｜ `DL_MathData` 6 个 ｜ `DL_Algo` 17 个 ｜ `DL_Device` 26 个 ｜ `DL_Motion` 12 个 ｜ `DL_Process` 18 个（合计 95）

### 4.1 结构体类型清单（ST_，禁重复声明）

| 结构体 | 宿主文件 | 所属子库 |
|---|---|---|
| `ST_DL_ModbusTxn` | `FB_DL_ModbusPollMaster.st` | `DL_Process` |
| `ST_DL_PollItem` | `FB_DL_ModbusPollMaster.st` | `DL_Process` |
| `ST_DL_RecipeEntry` | `FB_DL_RecipeManager.st` | `DL_Process` |
| `ST_DL_RfidCfg` | `I_DL_RfidReader.st` | `DL_Device` |
| `ST_DL_RfidDiag` | `I_DL_RfidReader.st` | `DL_Device` |
| `ST_DL_RfidTag` | `I_DL_RfidReader.st` | `DL_Device` |
| `ST_DL_StepperCfg` | `I_DL_StepperOpenLoop.st` | `DL_Device` |

### 4.2 全部 TYPE 汇总校验

- `TYPE` 声明总数：**102**（ENUM 95 + STRUCT 7）
- 跨目录同名重复：**0**（脚本对 102 个类型名做全集去重校验）
- 命名前缀合规：ENUM 全部 `E_DL_`、STRUCT 全部 `ST_DL_`，无例外

---

## 5. 命名避让规则 / Naming Avoidance

### 5.1 强制前缀（本库口径，优先于专家模板的裸 `FB_` / `E_` 口径）

| 实体 | 前缀 | 现有数量 | 说明 |
|---|---|---|---|
| 功能块 | `FB_DL_` | 96 | 模板中的 `FB_PneumaticCylinder` 入库时必须改 `FB_DL_PneumaticCylinder` |
| 函数 | `FC_DL_` | 39 | 模板 `FC_LinearScale` → `FC_DL_LinearScale` |
| 接口 | `I_DL_` | 17 | 模板 `I_Cylinder` → `I_DL_Cylinder` |
| 结构体 | `ST_DL_` | 7 | — |
| 枚举 | `E_DL_` | 95 | — |
| 全局变量表 | **禁止** | 0 | `GVL` 前缀在本库为红线禁记号 |

### 5.2 高密度同族清单（新件取名前必查，避免「换皮重复件」）

| 语义族 | 已有件 | 新件避让提示 |
|---|---|---|
| 计数器 | `FB_DL_EventCounter`、`FB_DL_ModuloCounter`、`FB_DL_PresetCounterSat`、`FB_DL_BidirectionalCounter` | 新计数器必须说清与四者的语义差，否则属重复件 |
| 位运算 | `FC_DL_BitGet`、`FC_DL_BitSet`、`FC_DL_BitCount`、`FC_DL_PackBitsToWord`、`FB_DL_UnpackWordToBits`、`FC_DL_WordBitPack`、`FC_DL_BitFieldExtract` | 七点已正交（单读 / 单写 / 统计 / 全字打包 / 全字解包 / 读改写 / 任意位段） |
| 滤波器 | `FB_DL_MovingAverage`、`FB_DL_MedianFilter`、`FB_DL_LowPassFilter`、`FB_DL_SecondOrderFilter`、`FB_DL_HighPassFilter`、`FB_DL_Differentiator` | 新增须落在「陷波 / 自适应」等空位，禁再加一阶低通副本 |
| 阀门 | `FB_DL_AnalogValve`、`FB_DL_ThreePointValve`、`FB_DL_SingleSolenoidCyl`、`FB_DL_VacuumEjector` | 三分法已定：开关阀 / 比例阀 / 电动阀 |
| 缓冲器 | `FB_DL_RingBufferLReal`、`FB_DL_LifoStack`、`FB_DL_FifoBuffer` | 环形 / 后进先出 / 先进先出三点已满 |
| 信号发生器 | `FB_DL_RampGenerator`、`FB_DL_SCurveGenerator`、`FB_DL_SineGenerator`、`FB_DL_SawtoothGenerator`、`FB_DL_PulseGenerator`、`FB_DL_PwmDutyController` | 六种波形已定，新件须新波形形状 |
| 安全件 | `FB_DL_TwoHandSafety`、`FB_DL_SafetyLightCurtain`、`FB_DL_GuardLockDoor`、`FB_DL_LevelSwitchVib`、`FB_DL_InterlockMatrix` | 均须带「非认证安全功能」披露段 |
| 运动耦合 | `FB_DL_ElectronicGear`、`FB_DL_ElectronicCam`、`FB_DL_GantrySyncAxis` | 速度耦合 / 位置耦合 / 双驱监视三层已满 |

### 5.3 R11 命名建议模板

```
新功能块 : FB_DL_<领域><对象><动作>    例 FB_DL_ConveyorJamTracker（先查 5.2 表确认不重复）
新函数   : FC_DL_<动词><对象>          例 FC_DL_InterpCubic
新接口   : I_DL_<对象>                 方法数 ≤ 6（红线临界）
新枚举   : E_DL_<对象><状态/类别>      随宿主文件同文件发布，禁跨文件复制声明
新结构体 : ST_DL_<对象><用途>          同上
```

---

## 6. 落码前三步（缺一不可）

1. **查本表**：确认目标码位落在 §3.x.3 的「主推码位」或「备选」范围内，且不在 §2 共享族的他人分界内。
2. **跑红线机检**：`python redline_check_r11.py <新件 .st>`，9 项全过再谈终审（脚本见同目录 `redline_check_r11.py`）。
3. **跑求差断言**：对全库 `.st` 与 `INDEX_REGISTRY.json` 求差，断言「新增码位集合 ∩ 全库既有集合 = ∅」——**本表静态结论不可作为唯一依据**（R30 教训：冲突处的编码者注释均写着「经核对未占用」）。

---

## 附：生成口径与已知边界

- **码位来源**：逐文件正则抓取 `16#XXXX_XXXX` 字面量（含头注释中的码表说明），故「已占」= 文档登记 ∪ 代码落地，取并集，**偏保守**（宁可少用不可撞）。
- **已排除的伪码**：`16#0000_0000`（无故障基准）、`16#FFFF_FFFF` / `16#FFFF_FFFE`（哨兵值）、`16#DEAD_BEEF`（测试魔数）、`DL_MathData` 的 CRC 验收向量（`16#CBF4_3926` / `16#D202_EF8D` / `16#EDB8_8320` / `16#641C_1F5C`）。
- **预留位**：`0003_0105`（空置不分配，禁占）、`0003_0116`（`FB_DL_LevelSwitchVib` 预留信息级，代码未触发）、`0003_0281`（`FB_DL_SerialScanner` 预留故障级「设备长时间无就绪」，头注释登记但代码未落地）。三位在表中按「已登记」处理。
- **快照时效**：本表随 `.st` 与台账变动而失效，R11 落码后须重跑生成脚本刷新。

---

*本文件仅作码位与命名决策依据，不构成入库凭据；入库以终审求差断言为准。*
