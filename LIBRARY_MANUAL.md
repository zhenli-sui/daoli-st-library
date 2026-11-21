# LIBRARY_MANUAL — 道莅工控代码库总手册

> **Library Version**：v2.0.0 ｜ **Components**：168 / 10,000 ｜ **Level 0**：**67**（`DL_Base` 34 ｜ `DL_MathData` 33）｜ **Level 1**：`DL_Algo` **25** ｜ `DL_Device` **40** ｜ `DL_Motion` **16** ｜ **Level 2**：`DL_Process` **20**
> 本文件是全库的**跨子库调用规范**与**故障码总表**；逐组件引脚说明见各子库 `MANUAL_DL_*.md`。

---

## 一、子库分工与依赖规则 / Sublibrary Rules

| 子库 / Sublibrary | Level | 职责 / Responsibility | 允许依赖 / May Depend On |
|---|---|---|---|
| `DL_Base` | 0 | 信号整形、位运算、字打包、编码换算、时序引擎、系统诊断 | `Standard.library` |
| `DL_MathData` | 0 | 标定、滤波、迟滞判决、校验、缓冲、字节序、字符串解析 | `Standard.library`（可用 `DL_Base`） |
| `DL_Algo` | 1 | 闭环控制律、轨迹规划、状态估计 | Level 0 |
| `DL_Device` | 1 | 物理器件 OOP 抽象（`I_DL_*` + `FB_DL_*`） | Level 0 |
| `DL_Motion` | 1 | 轴、组轴、凸轮、PLCopen MC 映射 | Level 0 |
| `DL_Process` | 2 | 工站、工艺段、产线节拍、PackML | Level 0~1（经接口注入） |

**三条硬规则**：

1. 依赖方向单向，低层不得引用高层。
2. `DL_Algo` 及以上不得内联实现本应在 Level 0 提供的能力（如自己写死区、自己写 CRC）。
3. 跨层数据传递一律走 `VAR_INPUT` / `VAR_OUTPUT` / `VAR_IN_OUT` 或 `I_DL_*` 接口，禁止全局变量。

---

## 二、调用约定 / Calling Conventions

### 2.1 功能块（FB）：每周期无条件调用一次

```iecst
(* ✓ 正确：不论条件，实例永远被调用；条件只影响输入 *)
fbFilter(fInput := fRaw, bEnable := bEnableFilter);

(* ✗ 错误：把实例调用塞进 IF，扫描周期抖动时丢沿、定时器冻结 *)
IF bEnableFilter THEN
    fbFilter(fInput := fRaw);
END_IF
```

### 2.2 函数（FC）：无记忆，可放进表达式

`FC_` 组件不持有跨周期状态，可直接出现在 `IF` 条件、`CASE` 分支与赋值表达式中。**唯一例外**是 `FC_DL_Hysteresis`，它通过 `VAR_IN_OUT` 把状态交还调用方持有（见 3.1）。

### 2.3 有状态组件的三种形态 / Three Shapes of State

| 形态 / Shape | 状态驻留 / State Lives In | 代表组件 / Examples |
|---|---|---|
| 功能块实例 | 实例私有 `VAR` | `FB_DL_SignalDebounce`、`FB_DL_MovingAverage`、`FB_DL_UnpackWordToBits`、`FB_DL_DualEdgeTrig`、`FB_DL_ExtendedTimer`、`FB_DL_StepSequencer`、`FB_DL_AlarmManager`、`FB_DL_WatchdogMonitor`、`FB_DL_PulseGenerator`、`FB_DL_CycleTimeMeasure`、`FB_DL_RuntimeMeter`、`FB_DL_RingBufferLReal`、`FB_DL_TwoHandSafety`、`FB_DL_InterlockMatrix`、`FB_DL_RedundantSwitch`、`FB_DL_DutyStandbyRotation`、`FB_DL_LifoStack`、`FB_DL_MedianFilter`、`FB_DL_SignalStatistics`、`FB_DL_PidController`、`FB_DL_CascadePid`、`FB_DL_SplitRangeControl`、`FB_DL_FeedforwardComp`、`FB_DL_SmithPredictor`、`FB_DL_RateLimiter`、`FB_DL_RampGenerator`、`FB_DL_SCurveGenerator`、`FB_DL_PwmDutyController`、`FB_DL_Integrator`、`FB_DL_Differentiator`、`FB_DL_LowPassFilter`、`FB_DL_SecondOrderFilter`、`FB_DL_HighPassFilter` |
| `VAR_IN_OUT` 回传 | 调用方的持久变量 | `FC_DL_Hysteresis`（`bState`）、`FC_DL_StringSplit`（`aFields`） |
| 无状态纯函数 | 无 | 其余 21 个 `FC_` 组件（含 DL_Algo 的 `FC_DL_DewPointCalc` / `FC_DL_FlowCompensate`；缓冲区类 `VAR_IN_OUT` 数组是数据通道，不是状态） |

---

## 三、状态持有纪律 / State Retention Discipline

### 3.1 `FC_DL_Hysteresis`

```iecst
VAR
    bHystState : BOOL;    // 必须持久：实例成员、静态变量或 RETAIN 变量
END_VAR

(* ✓ 同一变量每周期回传 *)
bPump := FC_DL_Hysteresis(fIn := fLevel, fThreshold := 1.5, fHysteresis := 0.2, bState := bHystState);

(* ✗ 传表达式 / 常量 / 临时变量 → 状态每周期丢失，退化为纯比较器，边界抖动立刻回来 *)
bPump := FC_DL_Hysteresis(fIn := fLevel, fThreshold := 1.5, fHysteresis := 0.2, bState := FALSE);
```

### 3.2 断电保持

`FB_DL_MovingAverage` 的缓冲区、写指针、累加和、已填充数若不设 `RETAIN`，重启后会重走「窗口未满」阶段，表现为输出从 0 缓慢爬升。需要无扰重启的场合，把实例声明为 `VAR RETAIN`。

`FB_DL_DualEdgeTrig` 的计数器同理：需要跨班次累计时必须 `RETAIN`。

`FB_DL_StepSequencer` 的 RETAIN 策略由工艺决定：保持可续跑（断电后从中断步继续），不保持则复位到空闲（更安全）。两者都合理，但必须显式选择，不存在默认正确项。

`FB_DL_RuntimeMeter` 是**必须** `RETAIN` 的组件：不声明则每次上电累计运行时间、启动次数、保养计时全部归零，保养预警形同虚设。

`FB_DL_DutyStandbyRotation` 的运行时间账（`afRuntimeHours` / `auStartCount`）建议 `RETAIN`：不保持则每次上电轮值顺序从 0 号机重来，均衡化失效；保持则轮值跨班次延续。两种策略都合法，但必须显式选择（组件头注释已披露）。

### 3.3 采样节拍

`FB_DL_MovingAverage` 的 `bSample` 是**电平语义**（`TRUE` 即采样），把节拍控制权交还调用方。要得到真正的数字滤波器，必须放在**固定周期任务**中调用，或由等间隔脉冲驱动。

---

## 四、故障码总表 / Global Error Code Table

`uErrorId = 0` 表示无故障。所有组件共用同一张表，禁止自造码。

> **R12 增量说明（v2.1.0）/ R12 Ledger Delta**：本批 18 件共 85 码，逐条登记见本节末「R12 新增码位逐条登记」表。要点三条：① `DL_Device` 故障码上界由 `0308` 提至 **`0315`**（依 R11 立规自 `0309` 顺延，`02FA`~`02FF` 仍封存）；② `16#0003_030B` 落在 `03xx` 故障子块但语义为**趋势级提示码**（不置 `bError`），HMI 须按级别而非按号段着色；③ `FC_DL_WaterEnthalpy` 取 `0002_21xx` 新带、`FB_DL_ValveCharacteristic` 取 `0002_20xx` 新带，均未回填 `0900` / `1300` 历史空置带。
> **R11 增量说明（v2.0.0）/ R11 Ledger Delta**：本表按「语义」归并登记，**逐码权威台账以各子库 `VERSION.md` 的「故障码台账追加」为准**。R11 新增：`0001_011E`~`0124`、`0001_0218`/`0219`、`0002_1F01`~`1F03` 与 `1F10`、`0003_0140`~`0148`、`0003_0300`~`0308`、`0004_01C0`~`01C2` 与 `02D0`/`02D1`、`0005_01C0`~`01C4` 与 `02C0`~`02F2`。
> **码段上界变更**：`DL_Device` 自 R11 起故障级上界由 `02FF` 提升至 **`0308`**（`03xx` 为新开扩展块，**`02FA`~`02FF` 残余六码封存禁填**，避免新旧码语义交叠与 HMI 码表分组错位）。
> **已知重叠（R11 前存量，待整改）**：`16#0002_0001`~`0005` 在 `DL_Base`（双手同步超时 / 释放不同步 / 卡死升级 / 联锁 / 无可用源）与 `DL_Algo`（参数钳位 / 采样周期钳位 / 非有限输入 / 非法状态兜底）两条线语义不同，本表按 `DL_Base` 口径登记；`DL_Process` 亦有少量引用。整改方向：`DL_Algo` 已用 `0002_1Fxx` 开新子块，可作迁移落点。

| ErrorID | 含义 / Meaning | 使用组件 / Used By |
|---|---|---|
| `16#0000_0000` | 无故障 / No fault | 全部 |
| `16#0001_0001` | 参数越界：位索引、位宽、窗口长度、字节数、延时、预设、周期、占空比、优先级、步超时、心跳窗、折点数、顶点数、同步窗 / Parameter out of range | SignalDebounce、BitGet、BitSet、Gray×2、MovingAverage、Crc16Modbus、ExtendedTimer、AlarmManager、StepSequencer、PulseGenerator、WatchdogMonitor、RuntimeMeter、StringSplit、TwoHandSafety、InterlockMatrix、RedundantSwitch、DutyStandbyRotation、MultiPointLinear、PolygonArea、LineIntersection、Crc32Ethernet、LrcChecksum、QuickSortLReal、HexStringToBytes、MedianFilter、SignalStatistics |
| `16#0001_0002` | 量程或分母为零 / 近零 / Span or denominator near zero | LinearScale、MovingAverage |
| `16#0001_0003` | 参数符号非法：负宽度、负回差、零回差 / Illegal sign | Deadband、Hysteresis |
| `16#0001_0004` | 循环保护触发 / Loop guard tripped | BitCount、MovingAverage、StringTrim、StringSplit、QuickSortLReal |
| `16#0001_0005` | 状态机进入非法状态 / Illegal state hit | SignalDebounce、MovingAverage、ExtendedTimer、StepSequencer、WatchdogMonitor、PulseGenerator、TwoHandSafety、InterlockMatrix、RedundantSwitch、DutyStandbyRotation |
| `16#0001_0006` | 输入数据非法（NaN / Inf）/ Invalid input data | LinearScale、MovingAverage（预留）；**QuickSortLReal（v1.2.0 起实际使用：NaN 预扫描拒绝）** |
| `16#0001_0007` | 数值溢出或计数饱和 / Overflow or counter saturation | DualEdgeTrig、UnpackWordToBits、AlarmManager、WatchdogMonitor、CycleTimeMeasure、RuntimeMeter、TwoHandSafety、InterlockMatrix、RedundantSwitch、DutyStandbyRotation |
| `16#0001_0008` | 输入数据非法：零/超限时间增量、心跳跳变过快、分隔符长度非法 / Invalid input data | WatchdogMonitor、CycleTimeMeasure、RuntimeMeter、StringSplit、RedundantSwitch、DutyStandbyRotation |
| `16#0001_0009` | 缓冲区满，写入被拒绝 / Buffer full, write rejected | RingBufferLReal、LifoStack（上溢） |
| `16#0001_000A` | 缓冲区空，读取被拒绝 / Buffer empty, read rejected | RingBufferLReal、LifoStack（下溢） |
| `16#0001_000B` | 顺控步超时故障 / Step timeout | StepSequencer |
| `16#0001_000C` | 心跳超时（看门狗触发锁定）/ Heartbeat timeout | WatchdogMonitor |
| `16#0001_000D` | 拆分字段数超输出缓冲，结果被截断 / Fields truncated | StringSplit |
| `16#0001_000E` | 输入模式 / 枚举值非法 / Invalid mode or enum value | ExtendedTimer、WatchdogMonitor（连带）、SwapBytes32 |
| `16#0002_0001` | 双手同步超时 / Two-hand sync timeout | TwoHandSafety |
| `16#0002_0002` | 双手释放不同步 / Two-hand release desynchronised | TwoHandSafety |
| `16#0002_0003` | 旁路嫌疑：按钮卡死 / Bypass suspicion: button stuck | TwoHandSafety |
| `16#0002_0004` | 联锁配置非法（无停机级通道，fail-safe 禁放行）/ Interlock config invalid | InterlockMatrix |
| `16#0002_0005` | 冗余无可用通道（双失效 / 偏差即故障策略）/ Redundancy: no usable source | RedundantSwitch |
| `16#0002_0006` | 冗余切换抖振锁定 / Redundancy chatter latched | RedundantSwitch |
| `16#0002_0009` | 统计样本不足（n < 2），方差输出 0 / Insufficient samples for variance | SignalStatistics |
| `16#0002_000A` | 十六进制串非法（奇数长度 / 非法字符），`nInvalidPos` 定位 / Illegal hex string | HexStringToBytes |
| `16#0002_000B` | 折线表非法（X 非严格递增），整表拒绝 / Table not strictly increasing | MultiPointLinear |
| `16#0002_000C` | 多边形退化（点数 < 3 / 零面积）/ Degenerate polygon | PolygonArea |
| `16#0002_000D` | 两线重合（共线），无唯一交点 / Coincident lines | LineIntersection |
| `16#0001_0105` | 非法 BCD 半字节（值 10~15），返回 0 / Illegal BCD nibble | BcdToWord |
| `16#0001_0106` | BCD 溢出饱和（> 9999 返回 16#9999）/ BCD overflow saturation | WordToBcd |
| `16#0001_0107` | BCD 除基守卫命中（除基常量被误改为 0）/ Divide-base guard | WordToBcd |
| `16#0001_0108` | 位段越界拒绝（宽度 0 / 宽度>16 / 偏移>=16 / 求和>16）/ Bitfield out of range | WordBitPack |
| `16#0001_0109` | 月窗参数钳位（目标日超月长 / 窗宽越界 / 生效月越界）/ Month-window params clamped | MonthWindowCheck |
| `16#0001_010A~010D` | FIFO 容量钳位 / 满队压入被拒（丢新）/ 空队弹出被拒 / 空队窥视被拒（均单拍信息级）/ FIFO clamped & queue empty/full rejected | FifoBuffer |
| `16#0001_010E` | 线性搜索 nCount 越界，已钳位 / Search count clamped | ArraySearchFirst |
| `16#0001_010F` | 二分 nCount 越界，已钳位，查找照常执行 / Binary-search count clamped | BinarySearchLReal |
| `16#0001_0110` | 归一后温度低于绝对零度（不阻断）/ Temperature below absolute zero | TempUnitConvert |
| `16#0001_0112` | 迟滞回差越界，已钳位到 0..fTolerance/2 / Hysteresis clamped | ToleranceWindow |
| `16#0001_0203` | 月窗日期参数非法（年/月/日越界、目标日为 0）/ Illegal date | MonthWindowCheck |
| `16#0001_0204` | FIFO 指针/计数一致性破坏，已自愈清空重建 / FIFO consistency self-heal | FifoBuffer |
| `16#0001_0205` | 线性搜索守护计数超限（理论不可达）/ Linear-search guard tripped | ArraySearchFirst |
| `16#0001_0206` | 二分守护超限/下标兜底，强制返回未命中 / Binary-search guard tripped | BinarySearchLReal |
| `16#0001_0207~0208` | 源 / 目标温标枚举非法，返回 0.0 / Illegal temperature unit | TempUnitConvert |
| `16#0001_0212` | 计数预设上限 < 下限，计数冻结锁存 / Preset upper < lower latched | PresetCounterSat |
| `16#0001_0213` | 公差带宽 ≤ 0 参数非法，判定锁 eUnKnown / Tolerance band illegal | ToleranceWindow |
| `16#0001_0214` | 四阈值序非法（倒置/容差内倒置），返回 eInvalid / Threshold order illegal | LimitClassify |

> **R9 增补登记（v1.8.0，本表未逐行列出的新目录段码）**：`DL_Device` 新增 13 码——信息级 `0003_0130~0137`（速度钳位 / 频率钳位 / 亚脉冲当量忽略 / 指令被拒 / 限位方向禁止 / 去使能冻结 / 周期兜底 / 减速收尾残差按到位）+ 故障级 `0003_02E0~02E4`（组态非法 / 限位入侵 / 驱动报警 / 堵转超时 / 非法状态），`FB_DL_PulseDirStepper`；`DL_Motion` 新增 7 码——信息级 `0004_01A0~01A3` + 故障级 `0004_02B0~02B2`，`FB_DL_SuperimposedMove`；`DL_Process` 新增 11 码——信息级 `0005_0190~0193`、`0005_01A0~01A1` + 故障级 `0005_0290~0292`、`0005_02A0~02A1`，`FB_DL_ModbusPollMaster` + `FB_DL_AndonCallSystem`。**本轮码位改判 6 件 15 处**（越段/撞码全部改归 `0001_xxxx` 段顺延，改判明细见各子库 `VERSION.md` R9 小节），终审后全库跨文件码位重叠 = 0。

> **R10 增补登记（v1.9.0，本表未逐行列出的新目录段码）**：`DL_Base` 新增 8 码——信息级 `0001_0113~0118`（位偏移/位宽/跨字截断、年份/月日越界、装载值钳位）+ 故障级 `0001_0215~0216`（预设倒置 / 防御式默认码）；`DL_MathData` 新增 6 码——信息级 `0001_0119~011D` + 故障级 `0001_0217`（全量非有限无有效极值）；`DL_Algo` 新增 **四个算法件各独占一个 `1x` 编号带（R10 采纳，建议写入 coding-standard 作为算法族推荐做法）**：`0002_1B01~1B04`+`1B10~1B11`（正弦）、`1C01~1C03`+`1C10`（锯齿）、`1D01~1D04`+`1D10`（卷径）、`1E01~1E04`+`1E10`（空气密度）；`DL_Device` 新增 18 码——信息级 `0003_0138~013F` + 故障级 **`0003_02F0~02F9`（本族新子块：`02F0~02F1` AOI 组态类 / `02F2~02F3` AOI 工艺类 / `02F4~02F6` 诊断寄存器一致性 / `02F7~02F9` PDI 失败锁定）**；`DL_Motion` 新增 8 码——`0004_01B0~01B3` + `0004_02C0~02C3`；`DL_Process` 新增 13 码——`0005_01B0~01B4` + `0005_02B0~02B7`。全部经终审脚本对全库求差断言（R30 口径），跨文件重叠 = 0。

**R12 新增码位逐条登记（85 码，v2.1.0）/ R12 Ledger（85 codes）**

> 本批 18 件共占 85 码：`DL_Base` 13（`0125`~`012F`、`021A`~`021B`）｜ `DL_MathData` 16（`0130`~`013C`、`021C`~`021E`）｜ `DL_Algo` 8（`2001`~`2003`、`2010`~`2012`、`2101`~`2102`）｜ `DL_Device` 26（`0149`~`0155`、`0309`~`0315`）｜ `DL_Motion` 8（`0109`~`010C`、`0204`~`0207`）｜ `DL_Process` 14（`0104`~`010A`、`0203`~`0209`）。**`DL_Device` 故障码上界由 `0308` 提至 `0315`**；`030B` 为故障段内的**趋势码**（不置 `bError`），已单列级别。终审逐码求差，与全库既有码位零重叠。

| ErrorID | 级别 / Level | 含义 / Meaning | 使用组件 / Used By |
|---|---|---|---|
| `16#0001_0125` | 信息级 | 位窗起始位越界（负偏移或 ≥ 位流总位数），早退并输出全零 | `FC_DL_BitArrayExtract` |
| `16#0001_0126` | 信息级 | 位窗宽度越界（< 1 或 > 64），早退并输出全零 | `FC_DL_BitArrayExtract` |
| `16#0001_0127` | 信息级 | 位窗跨字截断（越过位流末端或伸展到第三个字），按可用位截断后继续计算 | `FC_DL_BitArrayExtract` |
| `16#0001_0128` | 信息级 | 写入窗口起始位越界，目标数组一字未动 | `FC_DL_BitArrayInsert` |
| `16#0001_0129` | 信息级 | 写入窗口宽度越界，目标数组一字未动 | `FC_DL_BitArrayInsert` |
| `16#0001_012A` | 信息级 | 写入窗口跨字截断，按可用位写入 | `FC_DL_BitArrayInsert` |
| `16#0001_012B` | 信息级 | 区间端点倒置（下限 > 上限），判不在区间内且不静默交换 | `FC_DL_IntervalMembership` |
| `16#0001_012C` | 信息级 | 端点或被测值为非数 / 非有限，判定不可信 | `FC_DL_IntervalMembership` |
| `16#0001_012D` | 信息级 | 监视字数超上限已钳位到 8 并照常服务（小于 1 走 `021A`） | `FB_DL_BitArrayChangeWatch` |
| `16#0001_012E` | 信息级 | 判稳拍数越界已钳位到 1~100 | `FB_DL_BitArrayChangeWatch` |
| `16#0001_012F` | 信息级 | 跳变累计饱和（到 `16#FFFF_FFFE` 停值不回绕） | `FB_DL_BitArrayChangeWatch` |
| `16#0001_021A` | 故障级 | 监视字数小于 1（组态错），锁存故障并清变化族 | `FB_DL_BitArrayChangeWatch` |
| `16#0001_021B` | 故障级 | 非法状态兜底（枚举被改坏或跨版本不兼容），冻结输出 | `FB_DL_BitArrayChangeWatch` |
| `16#0001_0130` | 信息级 | 模式串为空，不允许替换，返回 0 次 | `FC_DL_StringReplaceAll` |
| `16#0001_0131` | 信息级 | 达到替换次数上限，结果不完整 | `FC_DL_StringReplaceAll` |
| `16#0001_0132` | 信息级 | 结果被长度上限截断（含拼接超串型上限 255 的显式判据） | `FC_DL_StringReplaceAll` |
| `16#0001_0133` | 信息级 | 次数上限或结果长度参数越界已钳位 | `FC_DL_StringReplaceAll` |
| `16#0001_0134` | 信息级 | 比对项数越界已钳位到 1~64 | `FC_DL_ArrayDiffSummary` |
| `16#0001_0135` | 信息级 | 容差非法（非有限或过小）已回退到最小容差 | `FC_DL_ArrayDiffSummary` |
| `16#0001_0136` | 信息级 | 年月时分 / 经纬度 / 时区偏移越界，本拍判定不可信 | `FC_DL_SolarPositionCalc` |
| `16#0001_0137` | 信息级 | 日超出当月实际天数（含闰年判定），判定不可信 | `FC_DL_SolarPositionCalc` |
| `16#0001_0138` | 信息级 | 功能码非法或异常码未定义，帧可解释但语义未知 | `FC_DL_ModbusExceptionParse` |
| `16#0001_0139` | 信息级 | 本帧非异常帧（功能码最高位未置位） | `FC_DL_ModbusExceptionParse` |
| `16#0001_013A` | 信息级 | 切出空段（连续分隔符），序号照占 | `FB_DL_StringTokenStream` |
| `16#0001_013B` | 信息级 | 段长超限已截断，`sToken` 为前缀 | `FB_DL_StringTokenStream` |
| `16#0001_013C` | 信息级 | 末段之后再次取段，序号不回绕、内容置空 | `FB_DL_StringTokenStream` |
| `16#0001_021C` | 故障级 | 分隔符为空（`FIND` 空模式跨平台不一致），硬闸锁存 | `FB_DL_StringTokenStream` |
| `16#0001_021D` | 故障级 | 段数达到上限，继续解析会推过调用方预期，掐断游标 | `FB_DL_StringTokenStream` |
| `16#0001_021E` | 故障级 | 非法相位兜底 | `FB_DL_StringTokenStream` |
| `16#0002_2001` | 信息级 | 输出被行程下限截断（含流量给定越下限钳位） | `FB_DL_ValveCharacteristic` |
| `16#0002_2002` | 信息级 | 输出被行程上限截断（含流量给定越上限钳位） | `FB_DL_ValveCharacteristic` |
| `16#0002_2003` | 信息级 | 输出变化小于死区，保持上次阀位 | `FB_DL_ValveCharacteristic` |
| `16#0002_2010` | 故障级 | 行程配置非法（越 0~100 或上下限倒置），保持上次阀位 | `FB_DL_ValveCharacteristic` |
| `16#0002_2011` | 故障级 | 可调比对数分母的二次守卫触发（正常钳位下不可达） | `FB_DL_ValveCharacteristic` |
| `16#0002_2012` | 故障级 | 非法特性枚举兜底 | `FB_DL_ValveCharacteristic` |
| `16#0002_2101` | 信息级 | 水温越 0~150 ℃ 域，已拒绝（不返 NaN、不外插、不夹取） | `FC_DL_WaterEnthalpy` |
| `16#0002_2102` | 信息级 | 零度点平均比热退化为一次项系数（分母保护生效） | `FC_DL_WaterEnthalpy` |
| `16#0003_0149` | 信息级 | 聚合组数超上限已钳位到 4（只影响显示范围） | `FB_DL_PortDiagBoard` |
| `16#0003_014A` | 信息级 | 某组端口数超上限已钳位到 8（组态常见，非错误） | `FB_DL_PortDiagBoard` |
| `16#0003_014B` | 信息级 | 掩码超界位已屏蔽（不存在的端口不计入故障数） | `FB_DL_PortDiagBoard` |
| `16#0003_014C` | 信息级 | 组内声明首出端口与掩码推导值不一致（数据源未同步） | `FB_DL_PortDiagBoard` |
| `16#0003_014D` | 信息级 | 比对本数越界已钳位到 1~64 | `FB_DL_DeviceParamVerify` |
| `16#0003_014E` | 信息级 | 本轮核对一致（`bVerified` 为真） | `FB_DL_DeviceParamVerify` |
| `16#0003_014F` | 信息级 | 负容差已取绝对值 | `FB_DL_DeviceParamVerify` |
| `16#0003_0150` | 信息级 | 冻结值刷新抖动（回退量在阈值内），保持上次累计不累加 | `FB_DL_EnergyMeterAccum` |
| `16#0003_0151` | 信息级 | 需量窗口小于 1 秒，已按 1 秒兜底 | `FB_DL_EnergyMeterAccum` |
| `16#0003_0152` | 信息级 | 换表回退比例越界已钳到 0~1 | `FB_DL_EnergyMeterAccum` |
| `16#0003_0153` | 信息级 | 重叠区宽度越界已钳到 0~3 个十倍程 | `FB_DL_VacuumGaugeMux` |
| `16#0003_0154` | 信息级 | 一致性容差越界已钳到 0.05~3 个十倍程 | `FB_DL_VacuumGaugeMux` |
| `16#0003_0155` | 信息级 | 仅单表可用，融合质量为「不确定」（不置故障位） | `FB_DL_VacuumGaugeMux` |
| `16#0003_0309` | 故障级 | 组数小于 1，无诊断源 | `FB_DL_PortDiagBoard` |
| `16#0003_030A` | 故障级 | 某组端口数小于 1，该组掩码含义不可信 | `FB_DL_PortDiagBoard` |
| `16#0003_030B` | 故障段趋势码 | 单拍掩码变化位数超阈值（判为组态刷新，**不置 `bError`**；HMI 须按级别着色） | `FB_DL_PortDiagBoard` |
| `16#0003_030C` | 故障级 | 非法状态兜底（终端安全态） | `FB_DL_PortDiagBoard` |
| `16#0003_030D` | 故障级 | 回读出现非有限值（NaN / 无穷） | `FB_DL_DeviceParamVerify` |
| `16#0003_030E` | 故障级 | 回读超时未就绪（回读块仍为全零） | `FB_DL_DeviceParamVerify` |
| `16#0003_030F` | 故障级 | 非法相位兜底 | `FB_DL_DeviceParamVerify` |
| `16#0003_0310` | 故障级 | 每 LSB 电能非正（量纲错，含除零隐患） | `FB_DL_EnergyMeterAccum` |
| `16#0003_0311` | 故障级 | 有功功率非有限值，本拍不积分 | `FB_DL_EnergyMeterAccum` |
| `16#0003_0312` | 故障级 | 非法状态兜底（终端安全态） | `FB_DL_EnergyMeterAccum` |
| `16#0003_0313` | 故障级 | 切换点非正，量程划分无意义 | `FB_DL_VacuumGaugeMux` |
| `16#0003_0314` | 故障级 | 双表不一致或双表均失效，输出保持 | `FB_DL_VacuumGaugeMux` |
| `16#0003_0315` | 故障级 | 非法状态兜底（终端安全态） | `FB_DL_VacuumGaugeMux` |
| `16#0004_0109` | 信息级 | 路径长度为零，当拍直接完成，进度置 100 | `FB_DL_LineInterp2Axis` |
| `16#0004_010A` | 信息级 | 标称插补周期越界已钳到 0.1 ms~1 s | `FB_DL_LineInterp2Axis` |
| `16#0004_010B` | 信息级 | 单轴速度上限参与折算，合成速度已被压低 | `FB_DL_LineInterp2Axis` |
| `16#0004_010C` | 信息级 | 路径过短，速度曲线降为三角（无匀速段） | `FB_DL_LineInterp2Axis` |
| `16#0004_0204` | 故障级 | 速度 / 加速度 / 单轴限速 / 最大路径长参数非法 | `FB_DL_LineInterp2Axis` |
| `16#0004_0205` | 故障级 | 路径长度超过允许上限 | `FB_DL_LineInterp2Axis` |
| `16#0004_0206` | 故障级 | 输入含非有限值（NaN / 无穷），前置拦截 | `FB_DL_LineInterp2Axis` |
| `16#0004_0207` | 故障级 | 非法状态兜底（终端安全态） | `FB_DL_LineInterp2Axis` |
| `16#0005_0104` | 信息级 | 相内步骤数越界已钳到 1~32 | `FB_DL_BatchPhaseBase` |
| `16#0005_0105` | 信息级 | 同拍多命令，低优先命令已丢弃（不排队） | `FB_DL_BatchPhaseBase` |
| `16#0005_0106` | 信息级 | 从暂停恢复，步骤号不重置 | `FB_DL_BatchPhaseBase` |
| `16#0005_0107` | 信息级 | 单步或暂停超时监控被关闭（时间参数为 0） | `FB_DL_BatchPhaseBase` |
| `16#0005_0108` | 信息级 | 台数 / 窗口长度 / 摘除阈值越界已钳位 | `FB_DL_PollTempBank` |
| `16#0005_0109` | 信息级 | 通道连续失败达阈值已摘除（仍继续轮询以便自动恢复） | `FB_DL_PollTempBank` |
| `16#0005_010A` | 信息级 | 滤波窗口为 1，均值等于瞬时值（无滤波能力） | `FB_DL_PollTempBank` |
| `16#0005_0203` | 故障级 | 单步超时，相中止 | `FB_DL_BatchPhaseBase` |
| `16#0005_0204` | 故障级 | 步骤失败反馈，相中止（与完成反馈同拍时失败优先） | `FB_DL_BatchPhaseBase` |
| `16#0005_0205` | 故障级 | 暂停超时，相中止 | `FB_DL_BatchPhaseBase` |
| `16#0005_0206` | 故障级 | 非法状态兜底（直接进已中止，不回空闲） | `FB_DL_BatchPhaseBase` |
| `16#0005_0207` | 故障级 | 换算比例非正（量纲错，含零乘隐患） | `FB_DL_PollTempBank` |
| `16#0005_0208` | 故障级 | 有效温度域为空（任何读数都会被判无效） | `FB_DL_PollTempBank` |
| `16#0005_0209` | 故障级 | 非法状态兜底（终端安全态） | `FB_DL_PollTempBank` |

> `16#0002_xxxx` 为 v1.2.0 新启用的故障码段（业务/工艺类语义），与 `16#0001_xxxx` 参数/循环段并行分配。
> **DL_Algo 段内细分登记（v1.3.0 起，v1.5.0 增补，R8 后 20 组件）**：Level 1 `DL_Algo` 20 组件的故障码同样位于 `16#0002_xxxx` 段，按组件细分（01xx PID ~ 16xx 流量 ~ 17xx 湿空气焓值 ~ **18xx Ramp/Soak 程序曲线族——R6 终审裁定自 01xx/02xx 归位的独立族段**），公共码 `0001` 参数越界已钳位 / `0002` 采样周期已钳位 / `0004` 输入非有限值已拒绝 / `0005` 非法状态兜底；无故障基准码为 `16#0002_0000`（斜坡 / S 曲线 / PWM / 积分 / 微分五组件为 `16#0000_0000`）。完整逐码说明见 `DL_Algo/MANUAL_DL_Algo.md` 第 19 节；与上表早期登记业务语义的段内编号并行使用，判读以各子库手册为准，全库统一归并在 Phase 1 收口时完成。
>
> **新目录段位登记（v1.4.0 起，公约 0.7）**：
> | 段位 / Family | 子库 / Sublibrary | 信息级 / Info | 故障级 / Fault | 手册 / Manual |
> |---|---|---|---|---|
> | `16#0003_xxxx` | `DL_Device` | `0003_01xx` | `0003_02xx` 起 | `MANUAL_DL_Device.md` 各节 |
> | `16#0004_xxxx` | `DL_Motion` | `0004_01xx` | `0004_02xx` 起 | `MANUAL_DL_Motion.md` 各节 |
> | `16#0005_xxxx` | `DL_Process` | `0005_01xx` | `0005_02xx` 起 | `MANUAL_DL_Process.md` 各节 |
>
> 信息级码（钳位、对调修复、次数超限拒绝等）只进 `uErrorId` 不置故障位；故障级码锁存仅复位可清；接口族故障码由实现块按上述段位登记，接口文件头注释固化「不得自造码段」纪律。

**统一语义**：`uErrorId ≠ 0` 表示「参数曾被本组件修正」或「内部保护被触发」，**不表示输出不可用**。停机与否由调用方决定，库层不替现场做安全决策。

---

## 五、库级测试向量 / Library Test Vectors

库级可执行单测体系尚未建立（Phase 1 后续补齐），当前以「实算复核 + 构造序列复算」两种手段验证。**时序类组件必须按后者验证**——文本合规检查无法发现极性反接、换相不清零这类语义缺陷（第二轮终审实例，见 `AGENT_EVOLUTION_LOG.md` Round 02）。

| 组件 / Component | 向量 / Vector | 期望 / Expected | 验证方式 / Method |
|---|---|---|---|
| `FC_DL_Crc16Modbus` | `01 03 00 00 00 02` | `16#0BC4`（发 `C4 0B`）/ wire `C4 0B` | 实算复核 |
| `FC_DL_Crc16Modbus` | `01 03 00 00 00 0A` | `16#CDC5` | 实算复核 |
| `FC_DL_Crc16Modbus` | `11 03 00 6B 00 03` | `16#8776` | 实算复核 |
| `FC_DL_Crc16Modbus` | 单字节 `0x0C` | `16#45BF` | 实算复核（**勘误**：规格书原值 `0x911E` 不可复现） |
| `FC_DL_BinaryToGray` ↔ `FC_DL_GrayToBinary` | `w ∈ {1,2,3,4,10,12,16,17,19,32}` 全序列 | `G2B(B2G(x,w),w) = x` 恒成立 | 全序列互逆 |
| `FC_DL_BitCount` | `0x0000_0000` / `0xFFFF_FFFF` / `0xDEAD_BEEF` | `0` / `32` / `24` | 与参考 popcount 比对 |
| `FC_DL_LinearScale` | `fIn = 40000, 量程 0..27648, 输出 0..1.6` | `1.6`，`bClamped = TRUE` | 边界钳位 |
| `FC_DL_LinearScale` | 反向量程 `27648..0`，输入 `27648` | `0.0`，`bValid = TRUE` | 反向标定 |
| `FC_DL_SwapBytes16` | `16#1A2B` | `16#2B1A`；再换一次还原 | 自逆性 |
| `FC_DL_SwapBytes32` | `16#12345678` 按 ABCD / DCBA / BADC / CDAB | `12345678` / `78563412` / `34127856` / `56781234` | 逐排布实算 |
| `FC_DL_SwapBytes32` | 同一排布连续转两次（4×4 对角线） | 还原原值，`f(f(v,O),O) = v` | 全排布矩阵复核 |
| `FC_DL_SwapBytes32` | 两种不同排布串联（4×4 非对角） | 等价于按 `O1 XOR O2` 转一次 | 2000×16 组随机值验证 |
| `FB_DL_RingBufferLReal` | 连续压入 64 → 第 65 次压入 | 第 65 次拒绝，`16#0001_0009`，队首仍为第 1 个值 | 回绕序列 |
| `FB_DL_RingBufferLReal` | 空队弹出 | 拒绝，`16#0001_000A`，`fPopValue` 保持 | 空判据 |
| `FC_DL_StringTrim` | `'  AB$09CD  '` | `'AB$09CD'`，`uTrimmed = 4` | 中间制表符保留 |
| `FC_DL_StringSplit` | `'LOT=A4471;QTY=0250;'` 按 `';'` | 3 字段，第 3 个为空串 | 尾随分隔符语义 |
| `FB_DL_PulseGenerator` | 周期 1000 ms / 占空比 0.3（1 ms 扫描） | 高 300 ms、低 700 ms | 构造扫描序列复算（v1.0.1 后） |
| `FB_DL_DualEdgeTrig` | `F,F,T,T,F,F,T,F` | 上升 2 次、下降 2 次 | 构造扫描序列复算（v1.0.1 后） |
| `FC_DL_Crc32Ethernet` | `"123456789"`（31..39），默认参数 | `16#CBF4_3926` | 实算复核（ISO-HDLC 标准向量） |
| `FC_DL_Crc32Ethernet` | 分块链式 `"1234"`（FALSE）+ `"56789"`（TRUE） | `16#CBF4_3926`，与整包一致 | 链式语义复算 |
| `FC_DL_LrcChecksum` | `01 03 00 00 00 01` | 和 `16#05` → LRC `16#FB` | 逐字节分解复算 |
| `FC_DL_LrcChecksum` | `FF FF` | 和低 8 位 `16#FE` → LRC `16#02` | 回绕复算 |
| `FB_DL_MedianFilter` | 窗口 5，序列 10,11,10,100,10 | `fMedian = 10`（100 被剔除；均值 = 28.2 对照） | 构造序列复算 |
| `FB_DL_SignalStatistics` | 窗口 8，序列 2,4,4,4,5,5,7,9 | 均值 5.0、极差 7、方差 32/7 ≈ 4.5714 | 手工复算 |
| `FB_DL_SignalStatistics` | 1000.0 与 1000.01 交替 8 个 | 方差 ≈ 2.857e-5（两遍法无灾难性抵消） | 构造序列复算 |
| `FC_DL_QuickSortLReal` | `{3,1,2}` 升序 / 64 个 7.0 全等值 | `{1,2,3}` 有限步终止 | 构造输入复算 |
| `FC_DL_HexStringToBytes` | `"1A2B3C"` / `"1G"` / `"1A2B3"` | 3 字节 / 返回 -1 位置 2 / 返回 -1 位置 6 | 构造输入复算 |

---

## 六、常见陷阱 / Pitfalls

1. **`TON` 放进 `IF`**：条件不满足时 `ET` 冻结，产生「定时器不归零」的幽灵故障。
2. **对原始抖动值取沿**：每个抖动周期都产生一个沿，下游计数器按数量级过计。必须对消抖后的值取沿。
3. **`REAL` 直接判等**：`1.0 + 0.1 <> 1.1` 在 `REAL` 下为真，必须带容差。
4. **`CASE` 缺 `ELSE`**：在线改枚举值会卡死无输出。
5. **只用一侧钳位**：负向冲击直接打穿执行机构。
6. **用 `R_TRIG` 承担「电平/脉冲」双语义**：常 `TRUE` 信号只采到一次，是必出事故的设计。
7. **窗口未满阶段也执行「减最旧值」**：上电初期滤波值比原始信号还抖。
8. **单位混用**：`mm` 与 `m`、`ms` 与 `s` 在同一 FB 内混用且无注释，现场调试必踩。
9. **换相位只改定时器 `PT`**：标准定时器只在输入为 `FALSE` 时清 `ET`，只改预设不会清零，第二个相位会带着第一个相位的残值起算（`FB_DL_PulseGenerator` v1.0.0 就栽在这里：占空比 0.5 时低相位塌缩成一个扫描周期）。**换相必须断输入一拍。**
10. **事件输出再与「上一周期电平」相与，但极性接反**：真实上升沿那一周期上一电平必为 `FALSE`，写成 `AND bLastLevel` 就把自己屏蔽掉，事件恒 `FALSE` 且静态审查发现不了（`FB_DL_DualEdgeTrig` v1.0.0）。
11. **故障码每周期无条件清零，故障态不再重写**：`bError` 仍为 `TRUE` 但 `uErrorId` 读回 0，现场丢失根因。**故障码是锁存事实，只有复位沿能清。**
12. **用 `0.0` 判断空队列**：`0.0` 是合法数据，判空必须看 `bEmpty`。
13. **平方和减均值平方算方差**：均值远大于标准差时灾难性抵消算出负方差（SPC 经典事故），必须两遍法（`FB_DL_SignalStatistics` v1.2.0 起内置）。
14. **ST 里写递归快速排序**：嵌入式运行时与汇川 InoProShop 栈深受限或直接不支持递归，64 元素最坏分区递归深度可达 64，实验室跑得通、现场栈溢出。分治一律显式栈（`FC_DL_QuickSortLReal` 为模板）。

---

## 七、平台适配说明 / Platform Notes

| 平台 / Platform | 状态 / Status | 注意点 / Notes |
|---|---|---|
| CODESYS V3.5+ | 已验证语法 | 全部组件仅用 `Standard.library` |
| TwinCAT 3 | 已验证语法 | `TIME` 常量写法一致；无 `Tc*` 依赖 |
| 汇川 InoProShop | 已验证语法 | `LWORD` 支持待实测，故首版不做 64 位组件 |
| Schneider Machine Expert | 已验证语法 | 语义与 CODESYS 同源 |

**未验证项**：三平台的实际编译与运行需在现场工程中做一次回归；本轮为静态语法级合规，非运行时验证。

---

## 八、DL_Algo 子库交付摘要 / DL_Algo Delivery Summary（v1.3.0 已交付）

> 子库 v1.0.0 ｜ Level 1（仅依赖 Level 0）｜ 16 组件（FB 14 ｜ FC 2）｜ **完整接口表、调用示例与现场注意事项见 `DL_Algo/MANUAL_DL_Algo.md`**；版本与组件清单见 `DL_Algo/VERSION.md`。

| # | 组件 / Component | 类型 | 复杂度 | 一句话摘要 / Summary |
|---|---|---|---|---|
| 1 | `FB_DL_PidController` | FB | 8 | 单回路位置式/增量式 PID，死区 + 积分分离 + 两级抗饱和 + 手自动无扰 |
| 2 | `FB_DL_CascadePid` | FB | 8 | 主副双回路串级，内部组合两个 PidController 实例，副设定域统一钳位 |
| 3 | `FB_DL_SplitRangeControl` | FB | 5 | 分程输出分配（加热/冷却双执行器），中央死区防双阀同开 |
| 4 | `FB_DL_FeedforwardComp` | FB | 6 | 静态 + 动态前馈补偿，含 10 槽纯滞后队列 |
| 5 | `FB_DL_SmithPredictor` | FB | 9 | 史密斯预估器，一阶模型 + 20 槽滞后缓冲，长滞后对象专用 |
| 6 | `FB_DL_RateLimiter` | FB | 4 | 变化率限制，升降斜率独立，速率为 0 = 该方向不限 |
| 7 | `FB_DL_RampGenerator` | FB | 4 | 线性斜坡，斜率独立 + 暂停保持 + 跟踪投切，速率 ≤ 0 冻结 |
| 8 | `FB_DL_SCurveGenerator` | FB | 9 | 七段式 S 型轨迹，jerk→acc→vel→pos 四级积分链，bAbort 最大减速停车 |
| 9 | `FB_DL_PwmDutyController` | FB | 6 | 时间比例慢速 PWM，最小 ON/OFF 抑制（欠脉冲债务补偿），SSR 加热 |
| 10 | `FB_DL_Integrator` | FB | 4 | 梯形法积分（LREAL 双精度累加），限幅/复位/保持，流量累计 |
| 11 | `FB_DL_Differentiator` | FB | 5 | 带一阶低通 + 速率限幅的实用微分器 |
| 12 | `FB_DL_LowPassFilter` | FB | 3 | 一阶低通（PT1），时间常数运行时可调 |
| 13 | `FB_DL_SecondOrderFilter` | FB | 6 | 二阶巴特沃斯低通（双线性离散，ζ=0.7071，-40dB/dec） |
| 14 | `FB_DL_HighPassFilter` | FB | 4 | 一阶高通（HP1），动态分量提取 / 振动监测 |
| 15 | `FC_DL_DewPointCalc` | FC | 3 | Magnus-Tetens 露点计算（-40..60°C，0.1..100%RH），附水汽压输出 |
| 16 | `FC_DL_FlowCompensate` | FC | 5 | 气体/蒸汽流量温压补偿（工况 → 标况 Nm³/h），可选差压开方 |
| 17 | `FB_DL_RampSoakProfile` | FB | 6 | 多段 Ramp/Soak 程序曲线发生器（v1.5.0 增补，18xx 族段） |

**跨子库调用要点**（详见子库手册第 0 节与第 20 节）：全部 FB 每周期无条件调用、`tSampleTime` 必须显式给定且全链路统一；控制类输出量纲 `[%]`，信号类 `[EU]`；故障码 `16#0002_xxxx` 段按组件细分，判读见子库手册第 19 节；"速率为 0"在 `FB_DL_RateLimiter`（不限）与 `FB_DL_RampGenerator`（冻结）中语义刻意相反，组态时禁止互拷参数。

---

## 九、新目录导航 / New Sublibrary Navigation（v1.4.0 开库，v1.5.0 R6 组深化）

> **三大新目录于 Round 05 开库**，逐组件接口表、故障码表与调用示例见各子库手册；版本与组件清单见各 `VERSION.md`。

### 9.1 `DL_Device` — 标准物理设备 OOP 抽象（v0.3.0，28 组件）｜ `MANUAL_DL_Device.md`

契约-实现分离模式：上层工艺块只依赖 `I_DL_*` 接口编程（依赖倒置），实现块可替换；接口方法全部非阻塞单发，故障态一律拒绝；接口成员同名输出以只读 `PROPERTY GET` 落地（R11 留档）。故障码段 `16#0003_xxxx`。R6 组深化：阀门三分法（比例阀 / 电动阀 / 真空与气缸）+ 变频器接口与实现。

| # | 组件 / Component | 类型 | 一句话摘要 / Summary |
|---|---|---|---|
| 1 | `I_DL_Cylinder` | 接口 | 双电控气缸契约：状态枚举 + 属性 5 + 方法 4，故障态拒绝 |
| 2 | `FB_DL_PneumaticCylinder` | FB | 气缸驱动：磁开消抖、超时自检、双传感器冲突锁存、双线圈互斥断言、行程计数 |
| 3 | `I_DL_MotorDriver` | 接口 | DOL 电机驱动契约：状态 + 重启抑制指示 + 启停/复位方法 |
| 4 | `FB_DL_DolMotor` | FB | DOL 电机：反馈校验窗、失反馈脱扣、过载锁存、滑窗启动次数限制 |
| 5 | `I_DL_AnalogSensor` | 接口 | NE43 变送器契约：工程量值 + 质量分级 + 四级报警位 |
| 6 | `FB_DL_AnalogTransmitter` | FB | NE43 处理块：原始域四段诊断、滤波、标定、故障态保持末次有效值 |
| 7 | `I_DL_TemperatureZone` | 接口 | 温控区契约：设定值/投退/复位方法 |
| 8 | `FB_DL_HeatCoolZone` | FB | 双通道温控区：注入式 PID → 分程 → 双路 PWM SSR，断偶按方向切断锁存（R4 算法族首个上层消费者） |
| 9 | `FB_DL_SingleSolenoidCyl` | FB | 单电控弹簧复位气缸：纯时间/磁开双校验模式，复用气缸契约（R6） |
| 10 | `I_DL_VacuumGenerator` | 接口 | 真空发生器契约：吸附/吹气/停止/复位 + 负压反馈属性（R6） |
| 11 | `FB_DL_VacuumEjector` | FB | 真空发生器驱动：负压迟滞、建立超时、TP 定宽吹气脉冲（R6） |
| 12 | `FB_DL_StarDeltaMotor` | FB | 星三角启动：死区互锁、三接触器校验、过载锁存、重启抑制（R6） |
| 13 | `I_DL_VfdDrive` | 接口 | 变频器契约：正反转/点动/多段速/频率设定/复位六方法（R6） |
| 14 | `FB_DL_VfdGeneric` | FB | 通用端子型变频器：正反转互斥、点动优先、段速选择、复位定宽脉冲（R6） |
| 15 | `I_DL_ProportionalValve` | 接口 | 比例阀契约：阀位指令/反馈/偏差报警属性 + 设定/停止/复位（R6） |
| 16 | `FB_DL_AnalogValve` | FB | 模拟量调节阀指令整形：死区补偿 + 限幅域映射 + 偏差延时报警（R6） |
| 17 | `I_DL_MotorizedValve` | 接口 | 电动阀契约：开关/停止方法 + 估算开度与双限位属性（R6） |
| 18 | `FB_DL_ThreePointValve` | FB | 三点浮点阀：双脉冲输出 + 行程积分估算开度 + 端点双保险（R6） |

### 9.2 `DL_Motion` — 运动控制 OOP 封装（v0.2.0，6 组件）｜ `MANUAL_DL_Motion.md`

PLCopen 轴状态模型 clean-room；同一状态机适配虚拟运动学仿真（`bUseVirtualKinematics=TRUE`）与真实驱动（位置注入）。故障码段 `16#0004_xxxx`；`bError` 派生式仅反映 `eErrorStop`。R6：T1-6 PLCopen Motion 首次开组——回零序列（四模式）+ 相对定位 + 速度模式；`bHomed` 仍由轴实现/上层联动维护，回零时序由 `FB_DL_AxisHomingSeq` 承载。

| # | 组件 / Component | 类型 | 一句话摘要 / Summary |
|---|---|---|---|
| 1 | `I_DL_MotionAxis` | 接口 | 单轴运动契约：PLCopen 六态 + 禁用态、属性 7、方法 6（≤6 红线临界） |
| 2 | `FB_DL_SingleAxis` | FB | 单轴参考实现：指令仲裁、软限位预判、仿真/真实双模式 |
| 3 | `FB_DL_AxisJogController` | FB | 点动操作器：长按低速延时升高速、松开即停、点动软限位独立拦截 |
| 4 | `FB_DL_AxisHomingSeq` | FB | 回零序列状态机：限位/原点/Z 相/堵转四模式 + 超时·行程双护栏（R6） |
| 5 | `FB_DL_AxisRelativeMove` | FB | 相对定位：链式步进累加、中止与轴故障中断（R6） |
| 6 | `FB_DL_AxisVelocityMove` | FB | 速度模式：动态改速、速度钳位、受控停止（R6） |

### 9.3 `DL_Process` — 行业工艺与工站模板（v0.2.0，4 组件）｜ `MANUAL_DL_Process.md`

Level 2 模板层：纯状态机框架 + 命令解码 + 行业池 P0 链路闭环示范件；工艺动作由调用方按态派发或经接口注入（依赖注入原则）。故障码段 `16#0005_xxxx`。R6 新增两件直接消费 Level 0/1 能力的示范块：焓差经济器消费 `FC_DL_HumidAirEnthalpy`、作息排程复用 `FB_DL_TimeWindowCheck` + `FC_DL_DayOfWeekCalc`。

| # | 组件 / Component | 类型 | 一句话摘要 / Summary |
|---|---|---|---|
| 1 | `FB_DL_PackMlStateMachine` | FB | PackML / ISA-TR88.00.02 十七态框架：命令驱动 + acting 态自动推进，OEE 根因区分 |
| 2 | `FB_DL_PackMlCmdDecoder` | FB | 命令解码器：十离散源 + 命令字双通道收口，防抖单发化，冲突全丢弃 |
| 3 | `FB_DL_EnthalpyCompareCtrl` | FB | 焓差经济器执行块：差分焓值迟滞判据 + 最小新风位硬下限 + 高限停机（R6） |
| 4 | `FB_DL_OccScheduleWindow` | FB | 多窗作息排程：4 窗矩阵 + 星期使能 + 节假日覆盖 + 预启动占位（R6） |

### 9.4 跨新目录典型链路 / Typical Cross-Sublibrary Chain

```iecst
(* 变送器 → 温控区（DL_Device 内部组合）/ Transmitter → Zone *)
fbZone(iTempSensor := fbTx, fbPid := fbPidZone, fbPwmHeat := fbPwmH, fbPwmCool := fbPwmC);

(* 轴 → 点动器（DL_Motion 接口注入）/ Axis → Jog via interface injection *)
fbJog.iAxis := fbAxis;

(* 解码器 → PackML 状态机（DL_Process 命令链）/ Decoder → State machine *)
fbPml.eCmd := fbDec.eCmd;

(* 焓差经济器 → 新风阀（DL_Process → DL_Algo/DL_Device 组合，R6）/ Economizer chain *)
fbEco(fOaTempC := fOaT, fOaRelHum := fOaH, fRaTempC := fRaT, fRaRelHum := fRaH);
fbDamper(fPosSetpoint := fbEco.fOaDamperCmd, fPosFeedback := fPosFb);

(* 温控区设定源 ← Ramp/Soak 曲线（DL_Algo 内部组合，R6）/ RampSoak feeds zone setpoint *)
fbRampSoak(tSampleTime := T#100MS, nSegCount := 4);
fSpZone := fbRampSoak.fSetpoint;
```

---

## 十、R6 组件接入指引 / R6 Component Integration Guide

> 适用范围：v1.5.0 新增 16 组件。接口细节逐字以各 `DL_*/*.st` 声明区与对应 `MANUAL_*.md` 为准。

### 10.1 设备层（DL_Device）：接口注入优先，实现块可替换

1. **阀门三分法选型**：有阀位变送器/定位器 → `FB_DL_AnalogValve`（实现 `I_DL_ProportionalValve`，指令整形层，闭环在外部）；只有开/关脉冲与双限位 → `FB_DL_ThreePointValve`（开度自动积分估算）；真空吸附 → `I_DL_VacuumGenerator` 契约 + `FB_DL_VacuumEjector` 实现；简单伸缩 → 气缸两条契约（双电控 `I_DL_Cylinder` / 单电控复用同一契约）。
2. **变频器接入**：上层只依赖 `I_DL_VfdDrive` 六方法编程；`FB_DL_VfdGeneric` 为端子型参考实现，多段速表 `aPresetFreq[1..7]` 由现场整定注入，频率模拟量给定经 `fFreqRefPercent` 输出 0~100% 线性映射。
3. **调用纪律**：全部 FB 每周期无条件调用；`bCmd*` 引脚电平语义与接口方法并存时二选一使用（方法请求优先，单发语义）；故障态下接口方法一律拒绝并返回 FALSE。

### 10.2 运动层（DL_Motion）：三块全部经 `iAxis : I_DL_MotionAxis` 注入

1. **回零**：`FB_DL_AxisHomingSeq` 按 `eMode` 选限位开关/原点开关/Z 相脉冲/扭矩堵转四模式；启动门禁要求轴处于静止态；超时与行程双护栏故障锁存；完成/中止/故障三终态收到新启动沿自动重启（不吞沿）。
2. **定位**：`FB_DL_AxisRelativeMove` 仅在轴静止态发起；链式模式下运行中递增 `nChainTarget` 即累加步进。`FB_DL_AxisVelocityMove` 的改速是「运行中重新调用 MoveVelocity」而非重启，需 `bDynamicRetarget := TRUE`。
3. **坐标系建立**：回零完成后由上层把 `fHomePosition` 写入轴坐标系/联动 `bHomed`；本库组件不直接写轴内部状态。

### 10.3 工艺层（DL_Process）：Level 0/1 能力的直接消费者

1. **焓差经济器**：`FB_DL_EnthalpyCompareCtrl` 每拍内部调用两次 `FC_DL_HumidAirEnthalpy`；输出 `fOaDamperCmd` 恒不低于最小新风位；可直接把输出接到 `FB_DL_AnalogValve.fPosSetpoint`。负干球输入经焓值链钳位为保守安全侧偏差（D4 裁定），调用方如需高精度冷量计量另行立项。
2. **作息排程**：`FB_DL_OccScheduleWindow` 日期/时刻全部引脚注入（禁读控制器时钟）；4 窗独立使能 + 星期矩阵 + 节假日覆盖位；`bPreStart` 用于提前启机预热/预冷，`uActiveWin` 多窗同开取最小号。
3. **程序曲线**：`FB_DL_RampSoakProfile`（DL_Algo）作为温控区设定源时，`fSetpoint` 直连温控区设定引脚；`bTrack/fTrackValue` 用于温控区实际温度无扰回同步；故障码位于独立 `18xx` 族段，HMI 分组勿并入 PID/串级。

### 10.4 接入自检清单 / Integration Checklist

- [ ] 实例调用在主任务每周期无条件执行（含 R6 全部 16 组件）。
- [ ] 接口引用（`I_DL_*`）指向的实现块实例已创建并注入。
- [ ] 时间类参数（行程时间/脉冲宽度/校验窗）按现场实测整定，非默认值照抄。
- [ ] HMI 报警分组按故障码段位（`0003/0004/0005`）与信息级/故障级双维归组。
- [ ] 回零类组件验收向量含「中途跟踪脉冲」与「终态后重启」两条。


---

## 十一、R7 组件接入指引 / R7 Component Integration Guide（v1.6.0，16 组件）

> 适用范围：v1.6.0 新增 16 组件。接口细节逐字以各 `DL_*/*.st` 声明区与对应 `MANUAL_*.md` 为准。

### 11.1 总目录索引（本轮 16 项）/ Master Index of R7 Additions

| # | 组件 / Component | 子库 | 类型 | 来源标签 | 一句话摘要 / Summary |
|---|---|---|---|---|---|
| 1 | `FB_DL_EventCounter` | DL_Base | FB | lgf-counter | 双向 DINT 事件计数器：预置装载 + 阈值比较每拍重算 + 回绕/饱和双模式 |
| 2 | `FB_DL_ModuloCounter` | DL_Base | FB | lgf-counter | 取模工位索引：条件加减法回绕（跨平台一致）+ 带校验跳步 |
| 3 | `I_DL_BarcodeScanner` | DL_Device | 接口 | tcopen-component/scanner-handshake | 扫码枪契约：六态握手 + Trigger/Ack/Reset 三方法 |
| 4 | `FB_DL_SerialScanner` | DL_Device | FB | tcopen-component/scanner-handshake | 扫码枪握手状态机：NoRead 重试→升级故障、TP 定宽触发（R24） |
| 5 | `I_DL_SafetyDoor` | DL_Device | 接口 | tcopen-component/safety-interlock | 电磁锁扣安全门契约：解锁时序七态 + 四方法 |
| 6 | `FB_DL_GuardLockDoor` | DL_Device | FB | tcopen-component/safety-interlock | 安全门联锁：停机→静止确认→解锁→审计→再锁定，防篡改冲突 |
| 7 | `I_DL_LightCurtain` | DL_Device | 接口 | tcopen-component/light-curtain-muting | 光幕契约：bSafeStop 核心安全镜像位 + Override/Ack/Reset |
| 8 | `FB_DL_SafetyLightCurtain` | DL_Device | FB | tcopen-component/light-curtain-muting | 序列式屏蔽：2/4 传感器正/反向序列、屏蔽超时 + override 硬帽 |
| 9 | `I_DL_FlowMeter` | DL_Device | 接口 | tcopen-component/flow-totalizer | 流量计契约：瞬时流量/累计总量 + 总量清零/预置/复位 |
| 10 | `FB_DL_PulseFlowMeter` | DL_Device | FB | tcopen-component/flow-totalizer | 脉冲流量计量：采样窗频率估计 + K 系数换算，总量双缓冲无撕裂 |
| 11 | `I_DL_LevelSwitch` | DL_Device | 接口 | tcopen-component/level-switch-failsafe | 料位开关契约：fail-safe HIGH/LOW 方向模式 + 高/低联锁 |
| 12 | `FB_DL_LevelSwitchVib` | DL_Device | FB | tcopen-component/level-switch-failsafe | 振动叉处理：防抖→失效安全归一→双延迟确认→双联锁 |
| 13 | `FB_DL_OeeCalculator` | DL_Process | FB | packml-oee | OEE 班次统计引擎：三因子 + PackML 根因位停机分账 |
| 14 | `FB_DL_ConveyorZone` | DL_Process | FB | conveyor-accumulation | 输送线积放单区（ZPA）：级联放行 + 卡料窗 + run-on 清区 |
| 15 | `FB_DL_BatchDosingControl` | DL_Process | FB | lbp-batch-dosing/isa-88 | 配料称重：三段给料 + 空中落差自学习（误差/2）+ 超差 NG 锁存 |
| 16 | `FB_DL_SoftLimitGuard` | DL_Motion | FB | plcopen-motion | 软限位围栏：制动距离（含时延项）预警/拦截两级 + 向内恢复豁免 |

### 11.2 设备层（DL_Device）：五条「契约 + 实现」产线

1. **握手类**：上层只依赖 `I_DL_BarcodeScanner` 编程；`bDataNew/bDataAck` 是与接收层的握手对（R25 消费拍与转出拍分离），不要用扫描顺序隐式同步。
2. **安全类**：`FB_DL_GuardLockDoor` / `FB_DL_SafetyLightCurtain` 为逻辑编排与诊断镜像层（公约 0.13），安全回路必须在认证安全控制器；`bSafeStop` 永不因屏蔽置假是接口级契约。
3. **计量/开关类**：`FB_DL_PulseFlowMeter` 的 K 系数取标定证书值；`FB_DL_LevelSwitchVib` 上电前先核对传感器极性与 `E_DL_FailSafeMode` 组态一致。

### 11.3 工艺层（DL_Process）：Level 0/1 能力的直接消费者

1. **OEE**：`FB_DL_OeeCalculator` 根因位与 `FB_DL_PackMlStateMachine` 的 `bHeldByMachine`/`bSuspendedByLine` 直连（引脚注入不引实例）；`tCycleTime` 接 `FB_DL_CycleTimeMeasure` 语义供给。
2. **输送线**：中区级联 `bDownstreamReady := 下区.bZoneReady`；末区接下游工序就绪；驱动经 `iDrive : I_DL_VfdDrive` 注入，每拍至多一次方法调用（公约 0.13）。
3. **配料**：`FB_DL_BatchDosingControl` 的 `fInflightComp` 跨批次保持（学习值），换料后建议清零重学习；NG 批次 `bOutDischarge` 恒 FALSE，不得旁路。

### 11.4 运动层（DL_Motion）

1. **软限位围栏**：`FB_DL_SoftLimitGuard` 输出为建议信号，拦截执行在调用方；`tLatency` 必须按实测（默认 23 ms = 扫描 10 + IO 5 + 驱动 8 ms）；复位前提是位置回到界内。

### 11.5 接入自检清单增量 / Checklist Delta（在 10.4 基础上追加）

- [ ] 扫码枪接收层按 `bDataAck` 一拍应答清 `bDataNew`，未用扫描顺序隐式同步。
- [ ] 安全门/光幕安全回路在认证安全控制器，本库件仅承担编排与诊断镜像。
- [ ] OEE 根因位与 PackML 状态机正交位逐字对接，未自造第三根因源。
- [ ] 配料 `fInflightComp` 学习值生命周期（换料清零策略）已定义。
- [ ] 软限位 `tLatency` 已实测整定（非默认值照抄）。

---

## 十二、R9 组件接入指引 / R9 Component Integration Guide（v1.8.0，16 组件）

> 适用范围：v1.8.0 新增 16 组件（5,051 行）。接口细节逐字以各 `DL_*/*.st` 声明区与对应 `MANUAL_*.md` 为准。

### 12.1 总目录索引（本轮 16 项）/ Master Index of R9 Additions

| # | 组件 / Component | 子库 | 类型 | 来源标签 | 一句话摘要 / Summary |
|---|---|---|---|---|---|
| 1 | `FB_DL_ToleranceWindow` | DL_Base | FB | lgf-tolerance | 公差窗判定：目标带迟滞 + 中带豁免 + 判定方向四态 |
| 2 | `FC_DL_LimitClassify` | DL_Base | FC | lgf-limit | 四阈值分级器（LL/L/H/HH）：纯函数无记忆，判据表驱动 |
| 3 | `FC_DL_WordBitPack` | DL_Base | FC | lgf-bitfield | 多位段打包进 WORD：域校验 + 守护计数，拒绝越界整包 |
| 4 | `FB_DL_MonthWindowCheck` | DL_Base | FB | lgf-calendar | 月度生效窗判定：日窗 + 月窗双闸，参数钳位照算 |
| 5 | `FB_DL_PresetCounterSat` | DL_Base | FB | lgf-counter | 预设饱和计数器：上限/下限双预设，预设倒置冻结锁存 |
| 6 | `FB_DL_FifoBuffer` | DL_MathData | FB | lgf-fifo | 定长 FIFO 队列：**先弹后压**时序 + 满队丢新策略 + 指针一致性自愈 |
| 7 | `FB_DL_ArraySearchFirst` | DL_MathData | FB | lgf-search | 数组线性首搜：返回首个命中下标 + nCount 钳位 |
| 8 | `FC_DL_BinarySearchLReal` | DL_MathData | FC | lgf-search | LREAL 有序数组二分查找：纯函数 + 守护兜底强制未命中 |
| 9 | `FC_DL_TempUnitConvert` | DL_MathData | FC | lgf-unit | 四温标互转（C/F/K/R）：双向枚举 + 绝对零度守卫 |
| 10 | `FC_DL_BcdToWord` | DL_MathData | FC | lgf-bcd | BCD16 → WORD：半字节逐位校验，非法即拒绝 |
| 11 | `FC_DL_WordToBcd` | DL_MathData | FC | lgf-bcd | WORD → BCD16：除基守卫 + 9999 溢出饱和 |
| 12 | `I_DL_StepperOpenLoop` | DL_Device | 接口 | gh-topics-stepper | 开环步进轴契约：运动/复位/去使能三方法 + eStepperState 七态 |
| 13 | `FB_DL_PulseDirStepper` | DL_Device | FB | gh-topics-stepper | 脉冲+方向步进：梯形加减速规划（短行程退化三角）+ 堵转超时 + 限位保护 |
| 14 | `FB_DL_SuperimposedMove` | DL_Motion | FB | s7-motion | 叠加运动：偏移指令经限速斜坡后叠加在基础轴位置上（削顶平移不跳变） |
| 15 | `FB_DL_ModbusPollMaster` | DL_Process | FB | codesys-forge-modbus | Modbus 轮询主站调度抽象：站表轮询 + 重试台账 + 传输层接口注入 |
| 16 | `FB_DL_AndonCallSystem` | DL_Process | FB | andon-omac | 安灯呼叫系统：四级优先仲裁 + 多源重锁 + 未应答解除统计 |

### 12.2 Level 0 调用范式：FIFO 先弹后压 / Calling Paradigm: Pop-Before-Push

`FB_DL_FifoBuffer` 的队列时序为**先弹后压**：`bPop` 命令先从队头弹出旧元素（`wDataOut` 在同一拍转出新值），随后 `bPush` 才把新元素压入队尾。这样保证「读一个 + 写一个」的组合命令在同一拍内不超容量、不丢序：

```iecst
// 同一拍「读一个 + 写一个」：先弹后压，fOutVal 同拍转出队头旧值
fifo(bPop := bConsume, bPush := bProduce, fPushVal := fNew, uCapacity := 16);
// 满队压入按「丢新」策略拒绝（bOverflow 单拍脉冲，码 0001_010B），不会覆盖旧数据
```

不要把「先压后弹」的民间 FIFO 习惯带进来——那会导致同一拍写入的值立刻被自己读走。队列空时弹出/窥视均为单拍拒绝码（`0001_010C/010D`），`nCount` 是唯一可信的队列水位。配套检索组件：`FB_DL_ArraySearchFirst`（无序线性首搜）与 `FC_DL_BinarySearchLReal`（有序二分）覆盖「找位置」需求，BCD/温标组件覆盖「进换算」需求，均在 `VAR_INPUT` 层完成域校验。

### 12.3 设备层调用范式：步进开环梯形规划 / Trapezoidal Planning for Open-Loop Steppers

上层只依赖 `I_DL_StepperOpenLoop` 编程；`FB_DL_PulseDirStepper` 为参考实现。梯形规划器在**短行程时自动退化为三角型**（加速段即减速段），调用方无须自行判断行程长度：

```iecst
// 经接口注入，每拍至多一次方法调用（公约 0.13）
iStepper.MoveRelative(fDistance := fDelta, fSpeed := fSpeed);
// 限位方向禁止时指令被拒（0003_0134），反方向恒受理；堵转按理论耗时 × 1.5 判定
```

三条纪律：① 频率被任务周期钳位（`0003_0131`）保证定宽一拍脉冲（R24），不要用比 10 ms 更粗的周期调用；② 限位是「同向停发锁故障」语义，入侵后必须反向退出再复位；③ v1.0.1 已修复减速残差死锁（D-02），残差不足一脉冲按到位处理（`0003_0137`），升级到 v1.0.1 前禁止用于长位移场合。

### 12.4 运动层调用范式：叠加运动语义 / Superimposed Motion Semantics

`FB_DL_SuperimposedMove` 把**偏移指令**经限速斜坡处理后叠加在基础轴位置上，基础轴（`iAxis : I_DL_MotionAxis` 注入）的定位/点动指令不受影响——这是「叠加」与「改目标」的本质区别（T2-4 S7-1500 Motion 语义借鉴）：

```iecst
// 偏移指令削顶平移不跳变：限速斜坡保证叠加量连续
fbSuper(bEnable := TRUE, fBasePos := fAxisActPos, fOffsetCmd := fShift,
        fMaxOffset := fMaxShift, fMaxOffsetSpeed := fSlew);
// 基础轴照常独立运动；叠加量经 fOffsetAct 输出供输出级合成
```

偏移幅值上限 `fOffsetLimit` 非法即锁存（`0004_02B0`）；非有限值指令被拒绝并保持末次有效值（`0004_01A2`），不做静默穿透。

### 12.5 工艺层调用范式：Modbus 轮询调度抽象 + 安灯四级仲裁 / Modbus Polling Scheduler & Andon Arbitration

**Modbus 轮询调度抽象**：`FB_DL_ModbusPollMaster` 只做**调度**（站表轮询、重试、异常台账），不做**传输**——`DoTransaction` / `SendFrame` / `RecvFrame` 三个默认实现均为抽象桩（返回 FALSE 并锁 `0005_0290`），由派生块覆盖后落地真实传输。换 RTU/TCP 只派生新块，调度层零改动（T1-4 CODESYS Forge Modbus 族借鉴）：

```iecst
// 站表由调用方持有（VAR_IN_OUT 注入），调度参数经引脚注入
fbPoll(uStationCount := 4, tRespTimeout := T#500MS, uMaxRetry := 3,
       tPollInterval := T#100MS, aPollTable := aPollTable);
// 单站重试耗尽只累加异常台账（0005_0192），轮询不停摆；抽象桩未覆盖触发 0005_0290
```

**安灯四级仲裁**：`FB_DL_AndonCallSystem` 对呼叫源按四级优先仲裁——高优先级呼叫可抢占重锁低优先级（`0005_01A1` 单拍提示），同拍多源时高者胜；应答/解除走各自方法，未应答即解除不计入应答统计（`0005_01A0`）。呼叫线不要绕过组件直连声光输出，锁存与仲裁语义由组件保证。

### 12.6 接入自检清单增量 / Checklist Delta（在 11.5 基础上追加）

- [ ] FIFO 采用先弹后压时序，同拍「读+写」未超容量、未自读自写。
- [ ] 码位使用前已对照本表第 12.1 节与 `VERSION.md` 改判明细，无越段自造码。
- [ ] 步进轴经 `I_DL_StepperOpenLoop` 注入，任务周期 ≤ 10 ms，固件版本 ≥ v1.0.1（含 D-02 修复）。
- [ ] 叠加运动未用于替代基础轴定位目标，偏移上限 `fOffsetLimit` 已按机构行程整定。
- [ ] Modbus 传输层由派生块覆盖三个抽象桩方法落地，调度层未内联任何收发细节。
- [ ] 安灯呼叫源未绕过仲裁直连输出，优先级映射与现场等级表一致。

---

## 十三、R10 组件接入指引 / R10 Component Integration Guide（v1.9.0，16 组件）

> 适用范围：v1.9.0 新增 16 组件（送审 5,385 行 / 修后 5,528 行）。接口细节逐字以各 `DL_*/*.st` 声明区与对应 `MANUAL_*.md` 为准。

### 13.1 总目录索引（本轮 16 项）/ Master Index of R10 Additions

| # | 组件 / Component | 子库 | 类型 | 来源标签 | 一句话摘要 / Summary |
|---|---|---|---|---|---|
| 1 | `FC_DL_BitFieldExtract` | DL_Base | FC | lgf-bitlogic | DWORD 任意位段提取：满宽走常量掩码规避 `SHL(x,32)`，越界双拒 |
| 2 | `FC_DL_WeekOfYearCalc` | DL_Base | FC | lgf-datetime | ISO-8601 周年/周序：Zeller 同余 + 周四归属，跨年归属独立语义 |
| 3 | `FB_DL_BidirectionalCounter` | DL_Base | FB | lgf-counter | CTUD 全语义双向计数：双预设 + 饱和不回绕 + 加优先仲裁 |
| 4 | `FC_DL_SearchMinMax` | DL_MathData | FC | lgf-math | 极值 + 索引单遍扫描：NaN 跳过、全量非有限不返回 0 号位 |
| 5 | `FC_DL_NthRoot` | DL_MathData | FC | lgf-math | N 次根：奇偶次分治 + 偶次负底数拒绝 + 结果有限性复检 |
| 6 | `FC_DL_FactorialSat` | DL_MathData | FC | lgf-math | 阶乘饱和（0~12）：超域取 12!，显式 `INT_TO_DINT` |
| 7 | `FB_DL_SineGenerator` | DL_Algo | FB | lgf-signalgen | 相位累加正弦：回绕用减法 + 冻结相位不归零（一拍固有延迟已声明） |
| 8 | `FB_DL_SawtoothGenerator` | DL_Algo | FB | lgf-signalgen | 对称度参数化锯齿/三角：分段斜率 + 段标志 + 相位百分比 |
| 9 | `FC_DL_CoilDiameterCalc` | DL_Algo | FC | lgf-technology | 卷径瞬时反算 `D = v·i/(π·n)`：低速与卷芯双保护、首拍无滞后 |
| 10 | `FC_DL_AirDensity` | DL_Algo | FC | oscat-building | 湿空气密度：Magnus-Tetens + 分压叠加，分母恒正 |
| 11 | `I_DL_RfidReader` | DL_Device | 接口 | rockwell-aoi / tcopen | RFID 契约：四 DUT + 只读属性 3 + 方法 4（全带受理返回值） |
| 12 | `FB_DL_RfidTagHandler` | DL_Device | FB | rockwell-aoi / tcopen | RFID 实现：五态握手 + 写后回读校验 + 重复读抑制 + 原始码透传 |
| 13 | `FB_DL_AxiolineDiagLatch` | DL_Device | FB | plcnext-community | 总线诊断解析与首出锁存：7 位映射 + 128 特例 + 四级等级 |
| 14 | `FB_DL_PdiReadScheduler` | DL_Device | FB | plcnext-community | PDI 读取调度：四元参数域 + 单拍一条 + 超时钳位 + 双码打包 |
| 15 | `FB_DL_WindingTraverse` | DL_Motion | FB | s7-motion / lgf-technology | 卷径递推 + 排线往复：双源仲裁 + 方向判据 + dwell 换向 |
| 16 | `FB_DL_PickAndPlaceStation` | DL_Process | FB | packml-omac / tcopen | 拾放工站：九步序 + 七态子集 + 单步三段式 + 节拍统计 |

### 13.2 两条新范式在本轮的落地要点 / Two New Paradigms in Practice

**R31「枚举→CASE 双向映射完备性」**：任何 `ENUM` + `CASE` 结构，必须做一次**枚举值 → CASE 标签**的双向映射表，逐值核对。特别地：**代码即便写在 `CASE` 之外（如 `IF _eState = eExecute` 形式），也必须在 `CASE` 中显式列出该标签的空分支**并注释原因——因为 `CASE` 先执行，未列标签会命中 `ELSE` 兜底被非法化。

```iecst
CASE _eState OF
    E_DL_SpState.eIdle:     // 待机处理
    E_DL_SpState.eExecute:
        (* 执行态本体在段 8~11 处理。本分支必须显式列出：缺该标签会让 eExecute
           落入 ELSE 兜底被判非法并锁故障，工站将永远无法执行。禁止在此写动作。 *)
    E_DL_SpState.eFault:    // 故障处理
    ELSE
        // 安全兜底
END_CASE
```

**R32「内部状态量写入点全拍排序审计」**：对每一个内部量（方向、计数、标志、屏蔽计时），列出**本拍全部写入点**并按源码次序排列，逐条问「后写的会不会抹掉先写的」。本轮两处典型：`nDirInt := 0;` 放在待机分支最前导致启动后方向恒 0（D-02 致命）；`nAckMute := DL_ACK_MUTE;` 后紧跟同拍递减导致屏蔽窗口为 0（D-05 严重）。

### 13.3 设备层调用范式：RFID 契约与 PDI 调度 / RFID Contract & PDI Scheduling

```iecst
// ① 契约优先：上层只依赖 I_DL_RfidReader，实现块可替换（私有协议 / IO-Link / 串口）
IF bTriggerRead THEN
    bAccepted := iReader.ReadTag();      // 方法返回受理值，忙时 FALSE 且不排队
END_IF
stTag := iReader.Tag;                    // 只读属性：保持型快照（R27）
uCode := iReader.Diag.uLastErrorId;      // 诊断结构整体回读（AOI InOut 段等价物）

// ② PDI 调度：单拍只发一条，结果双码打包（高 16 位 AddInfo / 低 16 位 ErrorCode）
fbPdi(bStart := bReadReq, uSlot := 3, uSubslot := 1, uIndex := 16#AFF0,
      nExpLen := 4, tTimeout := T#1S, nMaxRetry := 1,
      bSrvReady := bRscReady, bSrvDone := bRscDone,
      uSrvError := wRscErr, uSrvAddInfo := wRscAddInfo, uSrvLen := uRscLen);
```

**现场纪律**：PDI/RSC 服务耗时以百毫秒计，**禁止在实时任务里连续调用**；重试次数上限 3（保守）；`AddInfo` 常给出「哪个子索引 / 哪个通道」的附加定位，排障时先看高 16 位。

### 13.4 工艺层调用范式：拾放工站的依赖注入 / Pick-and-Place Dependency Injection

```iecst
// 三轴 + 真空全部经接口引用注入；Y 轴可选（两轴模板可复用 X 实例占位）
// 注意：故障停机时四路逐个判空，绝不依赖聚合布尔量（D-03 教训）
fbPickPlace(bEnable := bStationOn, bStart := bStartCycle, bHold := bHoldCycle,
            bAbort := bAbortCycle, bReset := bResetFault,
            bPartPresent := bPartAtPick, bPlaceClear := bPlaceFree,
            bVacuumOk := fbVac.bVacuumOk, bZHomeOk := fbAxisZ.bHomed,
            fPickZ := -120.0, fPlaceZ := -95.0, fSafeZ := 50.0, fTravelX := 320.0,
            fPosTol := 0.5, iAxisX := fbAxisX, iAxisY := fbAxisX,
            iAxisZ := fbAxisZ, iVacuum := fbVac);
// 被注入的轴与真空实现必须每周期调用，否则接口方法不收指令
fbAxisX(); fbAxisZ(); fbVac();
```

**到位判据契约**：`I_DL_MotionAxis` **没有「到位位」属性**，本块把到位写死为「轴 `eState = eStandstill` **且**位置落在 `fPosTol` 容差窗内」——语义等价于驱动层到位位且更严格（静止但偏差异常仍判未到位）。上层若要调整精度，改 `fPosTol` 即可，不要绕过本块自建到位判据。

### 13.5 接入自检清单增量 / Checklist Delta（在 12.6 基础上追加）

- [ ] 所有 `ENUM` + `CASE` 已做「枚举全值 → CASE 标签」双向映射核对；写在 CASE 外的状态判断已在 CASE 中留空标签（R31）。
- [ ] 每个内部状态量（方向 / 计数 / 屏蔽计时 / 单拍标志）已列本拍全部写入点并排序推演（R32）。
- [ ] 故障停机路径对**每一个**可选注入接口逐个判空，未依赖聚合布尔量。
- [ ] 端点 / 到达类判据已包含「正在朝该方向运动」等物理前提条件。
- [ ] `MIN`/`MAX` 常量**全部被使用**（声明未用即「参数未钳位」的静态信号）。
- [ ] 定时器 `PT` 类入参已钳位，`PT = 0` 路径不会形成每拍立即超时。
- [ ] 所有声明为输入的引脚至少被读取一次（未使用入参 = 功能缺失信号）。
- [ ] 验收向量与逐拍推演结论一致；含固有延迟的组件已显式声明「第几拍对应什么相位」。
- [ ] 算法族故障码按「每件独占一个 `1x` 编号带」分配（R10 采纳惯例）。

---

## 十四、R12 组件接入指引 / R12 Component Integration Guide（v2.1.0，18 组件）

> **节次说明 / Numbering note**：本文件既有章节止于第十三节（R10 接入指引，R11 未追加）。本轮按**实际序列**顺延为第十四节，并在本节标题标明 R12；任务书中所称「第十八节」应按本节理解（差异已登记于 `CHANGELOG.md` 观察项 O-R12-6）。

### 14.1 总目录索引（本轮 18 项）/ Master Index of R12 Additions

| # | 组件 / Component | 子库 | 类型 | 新族 / Family | 一句话切入 / Entry Point |
|---|---|---|---|---|---|
| 1 | `FC_DL_BitArrayExtract` | DL_Base | FC | 位数组批量 | 跨字位流里取位窗，右对齐给你 |
| 2 | `FC_DL_BitArrayInsert` | DL_Base | FC | 位数组批量 | 跨字位流里写位窗，告诉你改了几个字 |
| 3 | `FC_DL_IntervalMembership` | DL_Base | FC | 区间原子 | 在不在区间内、离边界多远 |
| 4 | `FB_DL_BitArrayChangeWatch` | DL_Base | FB | 位数组批量 | 哪一位在抖、抖了多少次 |
| 5 | `FC_DL_ArrayDiffSummary` | DL_MathData | FC | 数组比对 | 两组数差在第几项、差多少 |
| 6 | `FC_DL_StringReplaceAll` | DL_MathData | FC | 字符串流 | 模板占位符全量替换 |
| 7 | `FB_DL_StringTokenStream` | DL_MathData | FB | 字符串流 | 报文逐拍切段、字段序号不错位 |
| 8 | `FC_DL_SolarPositionCalc` | DL_MathData | FC | 太阳位置 | 遮阳/日照时段的地理判据 |
| 9 | `FC_DL_ModbusExceptionParse` | DL_MathData | FC | 协议诊断 | 异常码 → 该不该重试 |
| 10 | `FC_DL_WaterEnthalpy` | DL_Algo | FC | 水焓 | 水系统能量结算的焓差 |
| 11 | `FB_DL_ValveCharacteristic` | DL_Algo | FB | 阀特性 | 流量需求 → 阀位给定 |
| 12 | `FB_DL_DeviceParamVerify` | DL_Device | FB | 参数核对 | 参数写下去到底生效没有 |
| 13 | `FB_DL_PortDiagBoard` | DL_Device | FB | 端口诊断板 | 还剩几个端口坏、先修哪个 |
| 14 | `FB_DL_EnergyMeterAccum` | DL_Device | FB | 电表需量 | 冻结值累计 + 需量窗口 |
| 15 | `FB_DL_VacuumGaugeMux` | DL_Device | FB | 真空计融合 | 两块表拼出全量程一条曲线 |
| 16 | `FB_DL_LineInterp2Axis` | DL_Motion | FB | 双轴直线插补 | 两点之间走出速度连续的一段 |
| 17 | `FB_DL_BatchPhaseBase` | DL_Process | FB | 批次相基类 | 相状态、步骤号、暂停与恢复 |
| 18 | `FB_DL_PollTempBank` | DL_Process | FB | 轮询温控组 | 一条 485 上八台温控表的采集行 |

### 14.2 位数组批量族：读-改-写严格成对 / Cross-Word Bit Batch

`FC_DL_BitArrayExtract` 与 `FC_DL_BitArrayInsert` 是**唯一一对**允许把 `DWORD` 数组当连续位流操作的组件，位号自低向高连续（第 2 元素 bit0 = 位 32）。

- **按位不按字**：`nOffset` 是位号，不是字下标。写「第 2 个字的第 4 位」要填 `36`，不是 `2`。
- **跨字截断要读 `bValid`**：`0127` / `012A` 触发时结果仍可用，只是不完整。判完整度请看 `bValid` 或 `nActualW`，不要看 `uField` 是否为零。
- **写入必须看 `nChanged`**：`nChanged = 0` 表示「值和原来一样」，不是「写失败」。用 `nChanged > 0` 判「真的改动了」是识别通讯假成功的唯一手段。
- **不要与单字件混用**：`FC_DL_BitGet` / `FC_DL_BitFieldExtract` / `FB_DL_UnpackWordToBits` 只作用于单个 32 位字，同一字段用两套件去读写会得到互相矛盾的位序口径。

### 14.3 字符串流族：一次性改全串 vs 逐拍取一段 / String Replace vs Token Stream

| 场景 / Scenario | 用哪件 / Use | 理由 / Why |
|---|---|---|
| 模板占位符替换、条码前缀规范化 | `FC_DL_StringReplaceAll` | 一次调用给完整结果与替换次数，纯函数可放表达式 |
| 协议应答多字段、需要逐段校验 | `FB_DL_StringTokenStream` | 取段摊到多拍，每段可独立处理；空段照占序号 |
| 单字符分隔、字段数固定、要保留空字段 | `FC_DL_StringSplit`（既有） | 一次性拆完，无需状态 |

两条纪律：① 分词件的 `sFrame` 若会被调用方中途改写，请**只认 `bValidToken` 与 `bDone`**，不要自行按实时 `LEN(sFrame)` 推算字段数（本轮 A-D02 致命修复即源于此，范式 R38）；② 替换件的 `bTruncated` 必须并入结果可信判定，`0132` 出现即意味着尾部字段已被裁掉（R37）。

### 14.4 太阳位置与水焓：两个「域外拒绝」的物性件 / Domain-Gated Physics

`FC_DL_SolarPositionCalc` 与 `FC_DL_WaterEnthalpy` 遵循同一条纪律——**域外拒绝，不夹取、不外插**：

- 太阳位置：日超当月天数（含闰年）判非法；经纬度与时区越界判非法；天顶不可辨（高度角 > 89.5°）方位角显式兜底。时间源由调用方注入，本件**不读平台时钟、不做夏令时换算**。
- 水焓：域 **0~150 ℃**，越域返回 0.0 且 `bValid = FALSE`。把 120 ℃ 按液态水结算会系统性高估焓值，故宁可拒算。`fCpMean` 在 0 ℃ 退化为一次项系数并置 `2102`（事实性提示，不是错误）。
- 接入要点：两件的 `bValid` 必须与结果**同权使用**。`fEnthalpy = 0.0` 既可能是「0 ℃ 的水」也可能是「域外被拒」，只看数值必然误判。

### 14.5 阀特性：流量需求到阀位给定 / Valve Characteristic Path

调用链固定为 `PID 输出（流量 %） → FB_DL_ValveCharacteristic → 阀位给定（%） → 定位器/电气转换器`。

- **特性按阀门铭牌选**：等百分比阀填 `eEqualPercent` 并给真实可调比，线性阀填 `eLinear`。特性填错会让同一条 PID 参数在不同负荷点表现迥异。
- **不做阀位回零**：投运、故障复位、掉使能三种情形一律**保持上次阀位**（R43）。想让阀门关到最小开度，请显式把 `fFlowCmd` 置 0，不要靠复位。
- **饱和要当工况看**：`2001` / `2002` 长期出现说明阀门选型偏小或工艺负荷超设计，不是控制问题。

### 14.6 参数核对：写下去 → 读回来 → 判一致 / Parameter Verify Loop

标准四步：① 写参数（任意写通道）；② 等设备回读块更新；③ 调 `FB_DL_DeviceParamVerify`；④ 用 `bVerified`（本轮）放行、用 `bMismatch`（锁存）做台账。

- **回读就绪判据是「回读块非全零」**：合法参数全为零的设备会等到超时。此类设备请设 `tVerifyTimeout := T#0S`。
- **逐项容差优先**：`afTolerance` 里填 0 或负值的项回落 `fDefaultTol`，负值取绝对值（`014F`）。
- **信息码按核对周期清除**（R44）：不要用「`uErrorId` 是否为零」判断历史是否发生过不一致，那是本轮状态；历史请看 `stVerify` 里的累计核对次数与上次结论。

### 14.7 端口诊断板：三层数据源分账 / Port Diagnostics Three Layers

| 层 / Layer | 数据源 / Source | 组件 / Component |
|---|---|---|
| 模块级 | 本地总线状态字 | 本地总线诊断锁存件（既有） |
| 端口级 | 端口聚合掩码 + 组内首出码 | `FB_DL_PortDiagAggregator`（既有）→ **`FB_DL_PortDiagBoard`（本轮）** |
| 参数对象级 | 参数回读块 | **`FB_DL_DeviceParamVerify`（本轮）** |

- 看板**只消费聚合结果**，不要在看板里重新实例化聚合器（同一批端口会被算两遍）。
- 首出只在未锁存时仲裁（组号最小 → 端口号最小），锁存后只认 `bReset`。多层同时报警时 HMI 不会跳。
- `030B` 是**趋势码**：掩码单拍跳变超 8 位（通常是整块 IO 卡被重新组态），只提示不置故障。HMI 必须按级别着色，按号段着色会把它误报成停机故障。

### 14.8 电表需量：先行诊断，再换工程量 / Meter: Diagnose Raw First

- **原始值域诊断在前**：先判 32 位拼装值的单调性（NE43 口径），再做 `fKwhPerLsb` 换算。标定系数填错只会让数值错，不会让「换表」判定失效。
- **换表按回退识别**：回退超过 `fRegressRatio` 即判换表，重置基准并给 `bMeterReset` 单拍脉冲。结算逻辑必须在该拍停算一期（基准刚重置）。
- **字间序 ≠ 字节内序**：本件处理两个 16 位寄存器的**拼装顺序**，字节内交换归 `FC_DL_SwapBytes16/32`。
- **暂停不吞窗口**：掉使能时窗口停在剩余时间处（`eHeld`），恢复后接着算（本轮 B-D03 修复）。

### 14.9 真空计融合：重叠区是互检区 / Dual Gauge: Overlap Is the Cross-Check

- 切换带迟滞：上门限 = `fSwitchPa`，下门限 = `fSwitchPa / 10^(重叠宽度/2)`。压力在带内时保持当前采信表不变。
- 重叠区做十倍程交叉校验：偏差超 `fAgreeTolDecades` 即锁「不一致」并保持上次压力。
- **单表降级不是故障**：输出 `0155` + 质量「不确定」，压力照常发布（抽真空过程中趋势仍需要）。**但工艺联锁必须看质量位**，只看压力会在单表漂移时误判「已到真空」。
- 取值一律「本拍复验可用性」（R42）：相与相之间的掉线不会被写成 0 或负值。

### 14.10 双轴直线插补：位置给定而非轴命令 / Two-Axis Interpolation Outputs Positions

- 输出 `fCmdX` / `fCmdY` 是**位置给定**，需由调用方送进 `I_DL_MotionAxis` 实现块。本件不承担使能、回零、限位。
- 周期必须与任务周期一致（`fNominalCycle`）：位移按速度积分，周期填错等于把速度和实际时间解耦。
- 暂停用 `bHold`（电平），不要用 `bStart` 反复触发；恢复按剩余量分流，不会在终点前再次加速（R41）。
- 短行程必然走三角曲线（`010C`），此时峰值速度低于 `fPathSpeed`——想提节拍请提高加速度。

### 14.11 批次相基类：动作外置的相骨架 / Phase Base With External Actions

标准接法：**相状态 → 按 `nStepNo` 派发动作 → 动作完成回 `bStepDone`（失败回 `bStepFail`） → 相推进**。

- `bRequestStep` 是**单拍脉冲**，必须当拍消费（写进 `IF bPhaseActive` 会导致整步期间每拍重发）。
- 暂停在**步骤边界**生效（`eHolding` → `eHeld`），恢复不重头（`0106`）。要立刻停用 `bAbort`。
- 已终止态（完成 / 已停 / 已中止）只认 `bReset`：给 `bStart` 不会有任何响应（B-D08 已把注释改成与实现一致）。
- 单步超时按步重计时（R40）：不要再把「相内总时长」当单步超时用。
- `uPhaseElapsed` 只在执行相累加，可直接进 MES 做相耗时与产能。

### 14.12 轮询温控组：采集行的三件套 / Polled Bank Assembly

`FB_DL_PollTempBank` = 轮询调度（内嵌 `FB_DL_ModbusPollMaster`）+ 逐通道滑动均值（内嵌 8 个 `FB_DL_MovingAverage`）+ 行级质量判定。

- **传输层必须替换**：内嵌调度以库内基类形态声明，生产部署须由具备真实串口/网口的派生块替换，否则全部通道会因轮询不成功而逐台摘除（表现为质量掩码全置位 + 在线台数为零，属**可观测失败**）。
- **摘除后仍继续轮询**：这是自动恢复的前提（连续两拍有效即复位）。定制版本若为了「省时间」停掉坏通道轮询，该通道将永远无法恢复。
- **坏通道保持上次值**：绝不用零填充（零摄氏度在锂箱/冷库是合法工况值）。判读质量请用 `uQualityMask` 与 `auCommFailCnt`。

### 14.13 接入自检清单增量 / Checklist Delta（在 13.5 基础上追加）

- [ ] 跨字位段读写成对使用，`nOffset` 按**位**填写，写入后检查 `nChanged` 而非只看返回值（R37 家族）。
- [ ] 位流数组的「有效字数」由组态保证不大于实际数组长度（全库唯一契约式前置条件）。
- [ ] 定长串替换后检查 `bTruncated`；出现 `0132` 即视为结果不完整，不得进入下游（R37）。
- [ ] 分词/核对/取值类组件：**锁存副本与实时镜像量不同名**，切片一律以锁存长度为准（R38）。
- [ ] 掉使能/停机分支不得夺走故障态或锁存态的复位通道；无条件前置赋值要先问「这拍该不该我执行」（R39）。
- [ ] 分段监控的定时器在**每一段边界断输入一拍**，不得跨段累加 `ET`（R40）。
- [ ] 恢复类相转出判据同时校验「位移到位」与「速度到位」，不得只看已完成量（R41）。
- [ ] 跨相取值（选择相 → 取值相）必须在取值拍复验数据源可用性（R42）。
- [ ] 以「保持上次值」替代「回零」时，保持值须夹进有效域后再输出（R43）。
- [ ] 周期核对件的信息码按核对周期清除，不得只靠复位沿清除（R44）。
- [ ] 物性/天文类函数：域外一律拒绝（`bValid = FALSE` 且输出确定），禁止夹取与外插。
- [ ] 趋势码（如 `0003_030B`）与故障码分级别上报，HMI 不得按号段统一着色。

## 十五、R13 组件接入指引 ｜ R13 专项：未经编译验证声明与替代验证方案 / R13 Integration Guide & the NOT COMPILER-VERIFIED Statement（v2.2.0，18 组件）

> **节次说明 / Numbering note**：本节为第十五节，含两部分——15.1 起为 R13 组件接入指引；15.2 起为 R12 观察项承诺的兑现「未经编译验证声明与替代验证方案」（`README.md` 头部提示与本节互为引用）。

### 15.1 总目录索引（本轮 18 项）/ Master Index of R13 Additions

| # | 组件 / Component | 子库 | 类型 | 新族 / Family | 一句话切入 / Entry Point |
|---|---|---|---|---|---|
| 1 | `I_DL_DeviceHealth` | DL_Device | 接口 | NE107 诊断族 | 让任何设备回答「健康吗 / 证据是什么 / 多久了」 |
| 2 | `I_DL_PowerMeter` | DL_Device | 接口 | NE107 诊断族 | 电表读侧统一契约，四类表实现可插拔 |
| 3 | `FB_DL_ModbusPowerMeter` | DL_Device | FB | NE107 诊断族 | Modbus 表实现：拼装 + 复算 + 需量 + 健康出口 |
| 4 | `FB_DL_ValveStictionDetect` | DL_Device | FB | NE107 诊断族 | 阀门黏滞四档定级，证据并发才升级 |
| 5 | `FB_DL_AhuDamperStuckDiag` | DL_Device | FB | NE107 诊断族 | 风阀卡滞三分类，「要停机」与「要排计划」分开 |
| 6 | `FB_DL_PumpCavitationGuard` | DL_Device | FB | NE107 诊断族 | 汽蚀三判据确认，只请求降速、不写频率 |
| 7 | `FC_DL_BitArrayRotate` | DL_Base | FC | 位段族三件套 | 位图整条旋转（交接班顺延、轮转显示） |
| 8 | `FC_DL_MaskCompare` | DL_Base | FC | 位段族三件套 | 状态字按掩码比对，直接报「差在第几位」 |
| 9 | `FC_DL_Crc8` | DL_MathData | FC | LGF CRC8 子族 | 短帧 8 位校验，ATM/SAE-J1850/HITAG 三变体 |
| 10 | `FC_DL_StringToLReal` | DL_MathData | FC | 严格解析 | ASCII 数值严格解析，错在第几个字符 |
| 11 | `FC_DL_StringFixedField` | DL_MathData | FC | 严格解析 | 定宽字段装填，R37「截断必置位」样板 |
| 12 | `FC_DL_Matrix3Inverse` | DL_MathData | FC | LGF Matrix 子族 | 手眼标定 / 仿射逆映射的 3×3 求逆 |
| 13 | `FB_DL_FoulingResistanceEstimator` | DL_Algo | FB | 换热器退化 | 污垢热阻 Rf 趋势，回答「该清洗了吗」 |
| 14 | `FB_DL_PassiveHomingMonitor` | DL_Motion | FB | 被动回零 | 轴被外力移动时的参考点确认 |
| 15 | `FB_DL_CapperTorqueTrend` | DL_Process | FB | 工艺判据 | 旋盖扭矩五类 NG 判别，主判定一锤定音 |
| 16 | `FB_DL_EscHeLeakCheck` | DL_Process | FB | 工艺判据 | ESC 氦背冷泄漏率三段式判定 |
| 17 | `FB_DL_ChamberSeasoningTrack` | DL_Process | FB | 工艺判据 | seasoning 台账，片数 ∧ 时长双判据放行 |
| 18 | `FB_DL_ReactorJacketDeltaT` | DL_Process | FB | 工艺判据 | 釜-夹套温差双约束 + 冷热分程 |

### 15.2 未经编译验证声明 / NOT COMPILER-VERIFIED Statement

> ⚠️ **本库全部 204 件组件未经真实编译器验证（NOT COMPILER-VERIFIED）。**
>
> 截至本轮（R13，2026-11-16），编译验证已**连续 14 轮悬置**。本机经实测探测**没有** CODESYS / TwinCAT 3 / InoProShop 中的任何一个（连安装目录、注册表卸载项与 PATH 均已核查，非「没找到图标」级排查）。本库的每一行代码都通过下述 15.3 替代验证方案的四层检查，但**替代方案不能等价于编译**——编译器专有语法差异、保留字冲突、隐式类型转换规则、`IMPLEMENTS` 接口签名的逐字匹配等，只有真实编译器能最终裁决。
>
> **生产导入前的强制动作**：在目标平台（CODESYS V3.5+ / TwinCAT 3 / InoProShop 任一）新建**空工程**，按 `DL_Base → DL_MathData → DL_Algo → DL_Device → DL_Motion → DL_Process` 依赖顺序全量导入，做一次全量编译，再接入业务代码。

### 15.3 替代验证方案（四层）/ Alternative Verification Scheme（R13 实测执行口径）

| 层 | 手段 / Means | R13 实测结果 / R13 Result |
|---|---|---|
| ① 静态机检 | `audit_library_r13.py` **16 条规则**（含 R37/R38/R39/R40 等范式规则）对**全库 204 件回归**；各泳道修复后 `fail=0 / warn=0` | 全库 r39 终值 `files=204 fail=3 warn=2`——残余 5 处经人工逐件推演**裁定误报**留档不修（3 FAIL：Integrator / PidController / PulseDirStepper，复位判据先于前置改写属合法写法；2 WARN：PortDiagBoard 首扫置安全态 / AxisVelocityMove）。未采用任何仅为让机检变绿的写法改动 |
| ② 独立验算 | 总监用 Python 独立复现算法与验收向量（不读编码者实现） | 泳道 B 六件：位旋转 **3,000 组对拍** + 矩阵 **500 组 A×A⁻¹≈I 对拍**，**41 项断言全过**；CRC8 三变体 `"123456789"` 实算 `F4/4B/B4` 与公开 CRC 目录三方一致。各件验收向量 V1~V5 手算过程留痕于源码头注释 |
| ③ 人工时序推演（双签） | 对 R39/R40/R41 等时序敏感范式逐拍推演（写入点排序、断输入拍、复位沿通道），「产品总监 + PLC 编程专家」双角色分别签署 | R39 存量专案 7 处机检命中全部逐件推演：真缺陷 2（已修升 v1.0.1）、误报 5（留档）；C4-1 延长窗失能由 R40 逐定时器核对捕获 |
| ④ 结构配平 | IF/END_IF、FOR/END_FOR、CASE/END_CASE 配平 + 终结符（`END_IF`/`END_FUNCTION(_BLOCK)`）完整性 + 嵌套注释风险扫描 | 全库 204 件配平通过；孤立分号（R26）与枚举单冒号（enum_separator）0 命中 |

### 15.4 无法替代的风险清单 / Irreplaceable Risks（编译才能发现，四层替代均无效）

- **平台专有语法与保留字**：标识符撞上平台保留字、关键字大小写约定、`%IX/%QW` 之外的平台地址写法——静态机检的 banned 词表无法穷举。
- **隐式类型转换与字面量规则**：`INT`/`DINT`/`USINT` 混算的隐式提升方向、时间字面量（`T#5S` / `TIME#`）解析差异、枚举字面量作用域。
- **`IMPLEMENTS` 接口签名逐字匹配**：属性/方法名、参数序与类型必须与接口**逐字一致**，契约件与实现件的漂移只有编译器会报（本轮 A3 曾出现语句段裸枚举引用，机检捕获属侥幸而非必然）。
- **编译器优化揭示的隐患**：未初始化变量的确定初值差异、死代码消除后的行为暴露、常量折叠引发的边界分歧。
- **数组与字符串语义**：数组形参实际长度（本库以「契约式前置条件」显式登记，调用方越界仍无编译期保护）、`STRING` 定长截断的平台差异（R37 是纪律约束，不是语言保证）。

### 15.5 接入自检清单增量 / Checklist Delta（在 14.13 基础上追加）

- [ ] NE107 六态（`E_DL_Ne107Status`）消费方必须处理全部六值，`eUnknown` 不得当 `eOk` 使用；枚举属主唯一（`I_DL_DeviceHealth`），**禁止在任何文件复制枚举体**。
- [ ] 电表/设备契约优先持有 `I_DL_PowerMeter` / `I_DL_DeviceHealth` 接口引用，不直接依赖 Modbus 实现件；换表码 `0318`、偏差码 `0323` 是维护语义——**故障带码但不置 `bError`**，HMI 按级别着色。
- [ ] `FB_DL_PumpCavitationGuard` 的 `bDerateRequest` 交上层执行降速——**任何代码不得把它接成直接写变频器频率**；复位后比率只回升一步，不自动恢复 1.0。
- [ ] 三分类诊断件（AHU 风阀 / 阀黏滞 / 汽蚀）各判据**确认窗不可合并**；「嫌疑级」信息码（`0164`/`015C`/`0160`）不锁存，不得进联锁。
- [ ] `FC_DL_BitArrayRotate` 的移位量会被对总宽取模，整圈也置 `013D`；别名（源 = 目标）安全但**不要**依赖同址写回做清零。
- [ ] `FC_DL_MaskCompare` 出现 `0140`（生效掩码为 0）说明掩码与位宽矛盾——恒匹配是「事实」不是「通过」，调用方必须检查该码。
- [ ] `FC_DL_StringToLReal` / `FC_DL_Matrix3Inverse` 的 `bValid` 与结果**同权使用**：前缀值、全零逆矩阵都可能是「拒绝」的输出形态。
- [ ] `FB_DL_EscHeLeakCheck` 稳压延长窗全程计时（R13 修复后语义）：自研同类逻辑严禁「主窗 Q OR 延长窗 Q」裁决（R40 家族）。
- [ ] `FB_DL_PassiveHomingMonitor` 只输出建议偏移，由上层按 `MC_SetPosition` 语义消费；其 `ePhase` 仅供诊断显示，**禁止**当轴状态使用。
- [ ] `FB_DL_ChamberSeasoningTrack` 双判据（片数 ∧ 时长）同时达标才放行；配方名只是校验键，不得承载工艺语义。
- [ ] `FB_DL_FoulingResistanceEstimator` 不做控制——清洗建议只进维护台账，不得自动触发阀门/泵动作；`fCp`/`fRho`/`K_clean` 按设备台账注入，禁止用缺省值蒙混。

---

*Last updated: 2026-11-16（R13 追加第十五节：18 组件接入指引 + 未经编译验证声明与替代验证方案 + 新增 81 码登记）｜ 道莅工控代码库产品总监*

---

## 十六、R20 组件接入指引 / R20 Integration Guide（v2.9.0，20 组件）

> 本章为 R20 批次（20 件、2,189 行）的接入摘要，逐件引脚与码位以各子库 `MANUAL_DL_*.md` 的「R20 追加组件接口表」与 `.st` 头注释为准。
> **附**：R18 / R19 两章尚未写入本总手册（历史欠账），按「增量优先」纪律留 R21 补齐；本章不覆盖那两批组件。

### 16.1 日历 / 时间族（DL_MathData 9 + DL_Base 1，本批最大族）

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FC_DL_DtToDintEpoch` | DATE_AND_TIME → Unix 纪元秒，Y2038 超域**饱和**并升故障级 | `dtIn` → 返回 DINT |
| `FC_DL_DintEpochToDt` | 纪元秒 → DATE_AND_TIME，超域**不饱和**、返回纪元零点 | `nEpochSec` → 返回 DT |
| `FC_DL_DateToDintDays` / `FC_DL_DintDaysToDate` | 日期 ↔ 自纪元天数双向，共用容器口径 65535 | `dateIn` / `nDays` |
| `FC_DL_TodAddWrap` / `FC_DL_TodDiffWrap` | 当日时刻加减与差值，午夜回绕/跨零点**条件加减归一** | `todIn`+`tOffset` / `todEarlier`+`todLater` |
| `FC_DL_DateAddDays` / `FC_DL_DateDiffDays` | 日期 ± 天数（减法预判溢出）/ 日期差（负差如实输出） | `dateIn`+`nDays` / `dateFrom`+`dateTo` |
| `FC_DL_TimeAbsSat` | TIME 取幅值饱和，`−MAX−1` 单值闸 | `tIn` |
| `FC_DL_LeapYearChk`（DL_Base） | 闰年原子，`bFullRule` 选两律 / 三律 | `nYear`+`bFullRule` |

**接入要点**：日历族四件共用 `DL_DATE_DAYS_MAX`，**不要跨件改口径**；`DtToDintEpoch` 与 `DintEpochToDt` 的超域策略刻意相反（饱和 / 不饱和），组态注释必须写明哪一侧进了 MES 台账。

### 16.2 域转换 / 字节序 / 字符串化（DL_MathData 9）

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FC_DL_WordToIntSat` | WORD → INT，补码解释为负 / 上饱和 32767 双出口 | `uIn`+`bTwosComplement` |
| `FC_DL_DwordToIntSat` / `FC_DL_LwordToLintSat` | 位宽饱和 + `bRequireLossless` 无损违约反升故障级 | `uIn`+`bRequireLossless` |
| `FC_DL_UdintToLintChk` | UDINT → LINT 升位 + **round-trip 验真**（识别平台 32 位符号扩展缺陷） | `uIn`+`bCheckEveryCall` |
| `FC_DL_BcdToByte` / `FC_DL_ByteToBcd` | BCD ↔ BYTE 双向，非法半字节 / 超 99 分级处理 | `uBcd` / `uIn` |
| `FC_DL_SwapBytes64` | LWORD 全字节逆序（复用 `SwapBytes32` 交叉合成） | `liIn` |
| `FC_DL_DintToStringTrim` / `FC_DL_LrealToStringTrim` | 修剪 + 四步截断样板；浮点件统一 `NaN`/`Inf+`/`Inf-` 文本 | `uTargetMax`+`bAllowTrunc` |

### 16.3 同步族（DL_Base 1）

| 组件 | 一句话功能 | 关键引脚 |
|---|---|---|
| `FB_DL_SemaMutex` | IEC SEMA 防御包装：三态机 + **超时强制归还**（故障级 0369）+ 释放优先 | `bClaim`/`bRelease`/`tHoldMax` → `bBusy`/`bTimedOut` |

**接入要点**：实例必须每周期无条件调用；超时归还占用**一个**扫描拍过渡态，此拍内申请被拒，重试节拍按 1 拍延迟设计。

### 16.4 未经编译器验证声明（沿用既有表述）/ NOT COMPILER-VERIFIED

> **⚠️ 本批次 20 件同样未经真实 CODESYS / TwinCAT / InoProShop 编译器验证**（全库 344 件一致）。验证手段仍为：16 项静态机检全库回归 + 总监独立验算 + 人工时序推演 + IF/END_IF 配平。**本批次新增风险点**：4 件日历族与 3 件时间算术件依赖平台内建口径（`DT_TO_DINT` / `DINT_TO_DT` / `DATE_TO_DINT` / `TOD_TO_DINT` / `TIME_TO_DINT`），若目标平台 DATE 以秒承载而非天承载，`DL_DATE_DAYS_MAX` 的保守口径需整体重定——**生产导入前必须在目标平台空工程做全量编译与口径实测**。完整风险清单见第十五节。

---
---

## R22 增量补记（2026-11-16 追加，不改既有内容）

- **本批 20 件接入指引**：接口表见六本子库 MANUAL 的「R22 批次接口表」节；轴侧安全层 5 件（AxisBrakeSeq / VirtualMasterAxis / MotionCmdQueue / CamTableValidate / AxisInPosMonitor）建议整机程序按「轴生命周期安全层」整体引入，MotionCmdQueue 需调用方注入 bAxisDone/bAxisError（本件不消费轴状态）。
- **v1.0.1 修订件**：MotionCmdQueue（清队竞态退出路径）/ VirtualMasterAxis（eFault 冻结门控）/ AxisBrakeSeq（注释-实现对齐 + tFbTimeout > tBrakeRelease 约束）/ BatchTransferSeq（0315 补置 bError）——对外引脚零变更。
- **未经编译器验证声明（延续）**：全库 384 件一致未经真实编译器验证（连续 18 轮悬置），替代验证方案与风险清单沿用第十五节；本批新增约束类 1 条——AxisBrakeSeq 的 tFbTimeout 与 tBrakeRelease 同拍起算，配置须满足 tFbTimeout > tBrakeRelease。
- **BatchTransferSeq 中止时序风险**：v1.0.1 终审留档——bAbort 路径泵停与关阀同拍发出，缺物理时序分隔（中等·安全相关），R23 立项修复（ROADMAP §24.1）；引入该件用于含泵管路的现场时请暂以外部联锁补足「泵惰转后才关阀」时序。


*Last updated: 2026-11-16（R22 增量补记）｜ 道莅工控代码库产品总监*
