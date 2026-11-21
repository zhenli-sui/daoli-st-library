# ROUND PLAN R12 ｜ 道莅工控代码库第 12 轮构建计划（阶段一盘点 + 阶段二取源与轮次计划）

> **编制人**：道莅工业代码库产品总监（R12 兜底承担，原生专家子代理不可用）
> **编制日期**：2026-11-15
> **计划性质**：本文件是 R12 编码者的**唯一依据**。凡本文件未写清的引脚、状态、码位、验收向量，编码者不得自行发挥；若发现矛盾，回退问总监，不许「边写边改规格」。
> **库状态基线**：总库 168 / 10,000 ｜ 今日 142 / 200 ｜ `INDEX_REGISTRY.json` 168 条 ｜ `.st` 168 个 ｜ registry version 2.0.0
> **分类基线**：DL_Device 40 ／ DL_Base 34 ／ DL_MathData 33 ／ DL_Algo 25 ／ DL_Process 20 ／ DL_Motion 16
> **锁**：本轮已持锁 R12（`.round.lock`），无并发冲突

---

## 0 本轮定位与配额自查

### 0.1 一句话定位

**「批量位段补全 + 协议诊断落地 + 参数域校验 + 批次相底座」**：把 Level 0 的位/区间原子算子从「单字」推到「跨字数组」，把两条 T1 待挖源（OSCAT Network 诊断帧、CODESYS Forge DeviceReader）与三条 T2 待挖子族（LGF Bit Logic 数组批量位段、LGF Data Handling 字符串、LGF Date and Timer 天文钟）在同一轮内落地，并用 ISA-88 相状态底座与两个 ROADMAP P0 件（端口诊断看板 / 温控器轮询采集行）把 Level 1 诊断侧与 Level 2 工艺侧同时接上。

### 0.2 硬性配额逐条自查

| # | 硬性要求 | 本轮落地 | 结论 |
|---|---|---|---|
| 1 | T2 非 ST 源 ≥ 1 个组件族 | T2-1 LGF 四个待挖子族（Bit Logic 数组批量位段 3 件、Data Handling 字符串 2 件、Comparator 数组批量比较 1 件、Date and Timer 天文钟 1 件）+ T2-8 ISA-88 完整批次模型本体 1 件 | ✅ 共 8 件 |
| 2 | T1 ST 原生源 ≥ 1 个 | T1-3 OSCAT Network 诊断帧解析族 1 件、T1-4 CODESYS Forge DeviceReader 族 1 件、T1-8 GitHub topics motion 线 1 件、T1-2 OSCAT Building WATER_ENTHALPY 族 1 件 | ✅ 共 4 件 |
| 3 | 行业工艺件取 ROADMAP P0 | `FB_DL_PortDiagBoard`（§15.3 唯一 P0）、`FB_DL_PollTempBank`（§13.6 P0）；另取 §7.6 / §7.3 两条无优先级标注的底座型待办（阀门特性补偿、真空计融合） | ✅ 2 件 P0 + 2 件行业池 |
| 4 | ≥ 5 个 DL_* 目录，每目录 ≤ 5 件 | DL_Base 4 ／ DL_MathData 5 ／ DL_Algo 2 ／ DL_Device 4 ／ DL_Motion 1 ／ DL_Process 2 = **6 个目录、18 件** | ✅ |
| 5 | ≥ 6 件纯函数 FC（Base/MathData 原子算子） | Base 3 件 FC + MathData 4 件 FC = **7 件**（另 DL_Algo 有 1 件 FC，合计 8 件 FC / 10 件 FB） | ✅ |
| 6 | 禁凑数变体 / 禁 MODE 巨无霸 | 见第 5 节「已主动拒绝的候选」：本轮拒了 9 个纯变体或职责重叠候选，逐条写明理由 | ✅ |

### 0.3 目录分布与类型分布

| 目录 | 件数 | FC | FB | 本轮主题 |
|---|---|---|---|---|
| `DL_Base` | 4 | 3 | 1 | 跨字位窗口读写 + 开闭区间判定 + 位图变化监视 |
| `DL_MathData` | 5 | 4 | 1 | 字符串全替换 + 数组批量比对 + 太阳位置 + Modbus 异常帧 + 报文分词 |
| `DL_Algo` | 2 | 1 | 1 | 水焓值 + 调节阀特性补偿 |
| `DL_Device` | 4 | 0 | 4 | 端口诊断看板 + 设备参数回读校验 + 电表累计 + 真空计融合 |
| `DL_Motion` | 1 | 0 | 1 | 两轴直线插补 |
| `DL_Process` | 2 | 0 | 2 | ISA-88 相底座 + 温控器轮询采集行 |

### 0.4 交付清单（18 件，按编码顺序）

| 序 | 组件名 | 目录 | 类型 | 复杂度 | 主源标签 |
|---|---|---|---|---|---|
| 1 | `FC_DL_BitArrayExtract` | DL_Base | FC | 5 | lgf-bitlogic |
| 2 | `FC_DL_BitArrayInsert` | DL_Base | FC | 6 | lgf-bitlogic |
| 3 | `FC_DL_IntervalMembership` | DL_Base | FC | 3 | lgf-comparator |
| 4 | `FB_DL_BitArrayChangeWatch` | DL_Base | FB | 5 | lgf-bitlogic |
| 5 | `FC_DL_ArrayDiffSummary` | DL_MathData | FC | 4 | lgf-comparator |
| 6 | `FC_DL_StringReplaceAll` | DL_MathData | FC | 5 | lgf-datahandling |
| 7 | `FB_DL_StringTokenStream` | DL_MathData | FB | 6 | lgf-datahandling |
| 8 | `FC_DL_SolarPositionCalc` | DL_MathData | FC | 7 | lgf-datetimer |
| 9 | `FC_DL_ModbusExceptionParse` | DL_MathData | FC | 3 | oscat-network |
| 10 | `FC_DL_WaterEnthalpy` | DL_Algo | FC | 3 | oscat-building |
| 11 | `FB_DL_ValveCharacteristic` | DL_Algo | FB | 5 | isa88-process（工艺参数域） |
| 12 | `FB_DL_DeviceParamVerify` | DL_Device | FB | 6 | codesys-forge-devicereader |
| 13 | `FB_DL_PortDiagBoard` | DL_Device | FB | 6 | plcnext-diag（P0）+ roadmap-p0 |
| 14 | `FB_DL_EnergyMeterAccum` | DL_Device | FB | 6 | namur-ne43（信号质量契约） |
| 15 | `FB_DL_VacuumGaugeMux` | DL_Device | FB | 6 | namur-ne43 + oscat-building |
| 16 | `FB_DL_LineInterp2Axis` | DL_Motion | FB | 8 | github-topics-motion |
| 17 | `FB_DL_BatchPhaseBase` | DL_Process | FB | 8 | isa88-batch |
| 18 | `FB_DL_PollTempBank` | DL_Process | FB | 7 | roadmap-p0 + t1-4（轮询组织） |

---

## 1 码位分配（先查全库，再顺延）

### 1.1 已占用段清单摘要（脚本实扫 168 个 `.st` 的 `16#XXXX_XXXX` 字面量，共 486 个码，已剔除 `16#0000_0000` 基准与 `FFFF_FFFF` / `FFFF_FFFE` / `DEAD_BEEF` / 4 个 CRC 验收常量）

**`16#0001_xxxx`（DL_Base × DL_MathData 共享 —— 本库唯一结构性撞号源）**

- 信息级已占：`0101~0110`（连续 16 码）、`0112~0124`（连续 19 码）；`0111` 空置
- 故障级已占：`0201~0208`、`0210~0219`；`0209` 空置
- 结论：两库共同的下一个可用信息级码为 **`0125`**，故障级为 **`021A`**

**`16#0002_xxxx`（DL_Base × DL_MathData × DL_Algo 共享）**

- DL_Base：`0001~0008`；DL_MathData：`0009~000D`；DL_Algo 公共：`0000~0005`
- DL_Algo 按件百位带已占：`0101~0102`、`0201`、`0301`、`0401~0402`、`0501~0502`、`0601`、`0701~0702`、`0801`
- DL_Algo 按件 `1x00` 带已占：`1001`、`1101`、`1201`、`1401`、`1501~1502`、`1601~1602`、`1701~1703`、`1801~1804`、`1810`、`1901~1904`、`1A01~1A06`、`1B01~1B04`、`1B10~1B11`、`1C01~1C03`、`1C10`、`1D01~1D04`、`1D10`、`1E01~1E04`、`1E10`、`1F01~1F03`、`1F10`
- 另有 `8011`（历史测试常量位，非分配段，避让即可）
- 结论：DL_Algo 下一个空带为 **`20xx`**（`1F` 之后的顺延），再下一个为 `21xx`；`0900` / `1300` 两带历史空置，本轮不用（避免跳号读图困难）

**`16#0003_xxxx`（DL_Device 独占）**

- 信息级已占：`0101~0104`、`0106~0109`、`0110~0115`、`0117~0126`、`0130~0148`；`0105` 为终审裁定「空置不分配」位、`0116` 为已登记预留位，二者禁占
- 故障级已占：`0201~0213`、`0220~0222`、`0230~0232`、`0240~0246`、`0250~0252`、`0260~0261`、`0270~0272`、`0280`、`0281`（预留）、`0282`、`0290~0293`、`02A0~02A2`、`02B0`、`02C0`、`02D0~02D1`、`02E0~02E4`、`02F0~02F9`、`0300~0308`
- 结论：下一个可用信息级码 **`0149`**，故障级 **`0309`**

**`16#0004_xxxx`（DL_Motion 独占）**

- 信息级已占：`0101~0108`、`0130~0132`、`0140~0142`、`0150~0152`、`0160~0164`、`0170~0171`、`0180~0184`、`01A0~01A3`、`01B0~01B3`、`01C0~01C2`
- 故障级已占：`0201~0203`、`0210~0213`、`0220~0221`、`0230`、`0240~0241`、`0250~0252`、`0260~0265`、`0270~0274`、`0280~0284`、`0290`、`0295~0299`、`02B0~02B2`、`02C0~02C3`、`02D0~02D1`
- 结论：下一个可用信息级码 **`0109`**（`0109~012F` 为本库最大连续空块），故障级 **`0204`**

**`16#0005_xxxx`（DL_Process 独占）**

- 信息级已占：`0101~0103`、`0110~0115`、`0130~0133`、`0140~0143`、`0150~0153`、`0160~0164`、`0170~0173`、`0180~0186`、`0190~0193`、`01A0~01A1`、`01B0~01B4`、`01C0~01C4`
- 故障级已占：`0200~0202`、`0210~0214`、`0220~0223`、`0230~0231`、`0240~0246`、`0250~0257`、`0260~0265`、`0270~0274`、`0280~0283`、`0290~0292`、`02A0~02A1`、`02B0~02B7`、`02C0~02C3`、`02D0~02D3`、`02E0~02E4`、`02F0~02F2`
- 结论：下一个可用信息级码 **`0104`**，故障级 **`0203`**

### 1.2 本轮分配表（18 件 / 85 个码位，件内连续，件间不重叠）

| # | 组件 | 信息级码段 | 故障级码段 | 码数 |
|---|---|---|---|---|
| 1 | `FC_DL_BitArrayExtract` | `16#0001_0125~0127` | 无（纯函数无锁存，全部信息级） | 3 |
| 2 | `FC_DL_BitArrayInsert` | `16#0001_0128~012A` | 无 | 3 |
| 3 | `FC_DL_IntervalMembership` | `16#0001_012B~012C` | 无 | 2 |
| 4 | `FB_DL_BitArrayChangeWatch` | `16#0001_012D~012F` | `16#0001_021A~021B` | 5 |
| 5 | `FC_DL_StringReplaceAll` | `16#0001_0130~0133` | 无 | 4 |
| 6 | `FC_DL_ArrayDiffSummary` | `16#0001_0134~0135` | 无 | 2 |
| 7 | `FC_DL_SolarPositionCalc` | `16#0001_0136~0137` | 无 | 2 |
| 8 | `FC_DL_ModbusExceptionParse` | `16#0001_0138~0139` | 无 | 2 |
| 9 | `FB_DL_StringTokenStream` | `16#0001_013A~013C` | `16#0001_021C~021E` | 6 |
| 10 | `FB_DL_ValveCharacteristic` | `16#0002_2001~2003` | `16#0002_2010~2012` | 6 |
| 11 | `FC_DL_WaterEnthalpy` | `16#0002_2101~2102` | 无 | 2 |
| 12 | `FB_DL_PortDiagBoard` | `16#0003_0149~014C` | `16#0003_0309~030C` | 8 |
| 13 | `FB_DL_DeviceParamVerify` | `16#0003_014D~014F` | `16#0003_030D~030F` | 6 |
| 14 | `FB_DL_EnergyMeterAccum` | `16#0003_0150~0152` | `16#0003_0310~0312` | 6 |
| 15 | `FB_DL_VacuumGaugeMux` | `16#0003_0153~0155` | `16#0003_0313~0315` | 6 |
| 16 | `FB_DL_LineInterp2Axis` | `16#0004_0109~010C` | `16#0004_0204~0207` | 8 |
| 17 | `FB_DL_BatchPhaseBase` | `16#0005_0104~0107` | `16#0005_0203~0206` | 8 |
| 18 | `FB_DL_PollTempBank` | `16#0005_0108~010A` | `16#0005_0207~0209` | 6 |

### 1.3 求差断言记录（已执行）

- 扫描口径：`glob('DL_*/*.st')` 共 168 个文件，正则 `16#([0-9A-F]{4})_([0-9A-F]{4})`，剔除哨兵与 CRC 向量后得 **486** 个已占码。
- 断言一：本轮 85 个码位**两两互不相同**（`len(set)=85`）。
- 断言二：本轮 85 个码位 ∩ 全库 486 个已占码 = **∅**（碰撞数 0）。
- 断言三：跨目录共享族专查 —— `0001` 段本轮只取 `0125~013C` 与 `021A~021E`，均落在 Base/MathData 双方都未占的空块内；`0002` 段本轮只取 `2001~2012` / `2101~2102`，与 DL_Base（`0001~0008`）、DL_MathData（`0009~000D`）零交叠。
- 断言四：三个特殊位 `0003_0105`（禁占）、`0003_0116`（预留）、`0003_0281`（预留）本轮零触碰。
- **编码者纪律**：上述断言是本文件编制时的静态结论。落盘前必须按 R30 口径**重跑一次求差**（新增码集合 ∩ 当时全库集合 = ∅），不得以本文件「已核对」为唯一依据。

---

## 2 命名与类型避让（新件取名前必查）

### 2.1 新增 ENUM（全部随宿主文件发布，禁止跨文件复制声明；全库现有 128 个类型名，下列 14 个均无同名）

| ENUM | 成员数 | 宿主 | 成员（编号 · 含义） |
|---|---|---|---|
| `E_DL_IntervalKind` | 4 | `FC_DL_IntervalMembership.st` | `eClosedClosed:=0` 双闭 ／ `eClosedOpen:=10` 左闭右开 ／ `eOpenClosed:=20` 左开右闭 ／ `eOpenOpen:=30` 双开 |
| `E_DL_BitWatchState` | 3 | `FB_DL_BitArrayChangeWatch.st` | `eIdle:=0` ／ `eSampling:=10` ／ `eFault:=99` |
| `E_DL_TokenPhase` | 4 | `FB_DL_StringTokenStream.st` | `eIdle:=0` ／ `eReady:=10` ／ `eDraining:=20` ／ `eFault:=99` |
| `E_DL_ModbusExcSeverity` | 3 | `FC_DL_ModbusExceptionParse.st` | `eInfo:=0` 提示 ／ `eWarn:=10` 告警可重试 ／ `eFault:=20` 故障须人工 |
| `E_DL_ValveCharKind` | 3 | `FB_DL_ValveCharacteristic.st` | `eLinear:=0` 线性 ／ `eEqualPercent:=10` 等百分比 ／ `eQuickOpen:=20` 快开 |
| `E_DL_ValveCharState` | 3 | `FB_DL_ValveCharacteristic.st` | `eIdle:=0` ／ `eActive:=10` ／ `eFault:=99` |
| `E_DL_ParamVerifyPhase` | 6 | `FB_DL_DeviceParamVerify.st` | `eIdle:=0` ／ `eWaiting:=10` ／ `eComparing:=20` ／ `eMatch:=30` ／ `eMismatch:=40` ／ `eFault:=99` |
| `E_DL_BoardPhase` | 3 | `FB_DL_PortDiagBoard.st` | `eIdle:=0` ／ `eScanning:=10` ／ `eFault:=99` |
| `E_DL_MeterPhase` | 4 | `FB_DL_EnergyMeterAccum.st` | `eIdle:=0` ／ `eSampling:=10` ／ `eHeld:=20` ／ `eFault:=99` |
| `E_DL_GaugeSel` | 3 | `FB_DL_VacuumGaugeMux.st` | `eNone:=0` ／ `ePirani:=10` 粗抽表 ／ `eCapacitance:=20` 精抽表 |
| `E_DL_GaugePhase` | 4 | `FB_DL_VacuumGaugeMux.st` | `eIdle:=0` ／ `eSelect:=10` ／ `eOverlapCheck:=20` ／ `eFault:=99` |
| `E_DL_LineInterpPhase` | 8 | `FB_DL_LineInterp2Axis.st` | `eIdle:=0` ／ `ePrep:=10` ／ `eAccel:=20` ／ `eCruise:=30` ／ `eDecel:=40` ／ `eDone:=50` ／ `eHeld:=60` ／ `eFault:=99` |
| `E_DL_BatchPhaseState` | 11 | `FB_DL_BatchPhaseBase.st` | 见 3.17 节成员全表 |
| `E_DL_TempBankPhase` | 3 | `FB_DL_PollTempBank.st` | `eIdle:=0` ／ `ePolling:=10` ／ `eFault:=99` |

> 枚举成员编号一律「0 起跳、段间隔 10」，与本库既有惯例一致；**禁止**不同枚举重名复用。

### 2.2 新增 STRUCT（3 个）

| STRUCT | 宿主 | 字段 |
|---|---|---|
| `ST_DL_BoardState` | `FB_DL_PortDiagBoard.st` | `nLatchedGroup`、`nLatchedPort`、`uLatchedCode`、`bLatchValid`、`anLastMask` |
| `ST_DL_ParamVerifyState` | `FB_DL_DeviceParamVerify.st` | `bLastVerdict`、`nLastDiffCount`、`nLastFirstIdx`、`fLastMaxDev`、`uVerifyCount` |
| `ST_DL_MeterState` | `FB_DL_EnergyMeterAccum.st` | `uImportPrev`、`uExportPrev`、`fImportAcc`、`fExportAcc`、`fWindowEnergy`、`tWindowElapsed`、`fDemandPeak`、`uResetCount` |

### 2.3 复用既有类型（禁止重复声明）

- `E_DL_ByteOrder`（宿主 `FC_DL_SwapBytes32.st`）：`FB_DL_EnergyMeterAccum` 的字序入参复用之。
- `ST_DL_PollItem`（宿主 `FB_DL_ModbusPollMaster.st`）：`FB_DL_PollTempBank` 的站表复用之。
- `E_DL_SignalQuality`（宿主 `I_DL_AnalogSensor.st`）：`FB_DL_VacuumGaugeMux` 的质量输出复用之（不新造质量枚举）。

### 2.4 名称避让核对（与 168 件无重名，且与高密度同族清单逐条对照）

- 位运算族现有七件（`BitGet` / `BitSet` / `BitCount` / `PackBitsToWord` / `UnpackWordToBits` / `WordBitPack` / `BitFieldExtract`）均只作用于**单个 32 位字**；本轮 `BitArrayExtract` / `BitArrayInsert` 是**跨字位流窗口**件，属「少一位都做不了」的新能力，不是变体。
- 缓冲/字符串族现有 `StringTrim` / `StringSplit`；本轮 `StringReplaceAll`（全替换计数）与 `StringTokenStream`（跨周期流式取段）二者职责互斥，且都不做「修剪」与「一次性分割」。
- 区间族现有 `ToleranceWindow`（单点公差带）、`LimitClassify`（四阈值分级）、`RangeOverlapCheck`（区间关系）；本轮 `IntervalMembership` 是「单点 × 开闭组合」判定，与三者正交。
- 计数/统计族现有 `SignalStatistics`、`SearchMinMax`、`ArraySearchFirst`；本轮 `ArrayDiffSummary` 是**双数组逐项比对**，不涉及单数组检索。
- 诊断族现有 `PortDiagAggregator`（端口级聚合）；`PortDiagBoard` 是**多聚合组看板 + 首出仲裁 + Top3**，前者不做跨组汇总。
- 运动族现有 `SingleAxis` / `Gear` / `Cam` / `Gantry` / `SuperimposedMove`；`LineInterp2Axis` 是**两轴合成路径插补**，无既有件覆盖。

---

## 3 逐件规格（18 件，编码者按此实现）

> 通用约定（每件都适用，不再逐件重复）：
> ① 头部注释块七项齐全（名称/子库/版本 1.0.0/兼容性/功能/开源溯源/修订历史），溯源字段写明 `原创实现（参考 XXX 分类与参数域）`，禁止出现「改编自 XXX 源码」字样，除非确有可商用许可的源码。
> ② 每个变量、每个枚举成员同行中文注释 + 工程单位 + 英文要点。
> ③ 严禁 `GVL` / `VAR_EXTERNAL` / `%I` `%Q` `%M` / 指针 / 厂商库 / 隐式类型转换。
> ④ `TON` / `TOF` / `R_TRIG` / `F_TRIG` 一律在 CASE 之外主周期无条件刷新。
> ⑤ 浮点判等一律 `ABS(a-b) < eps`；除法前置防零；数组下标先判界；`WHILE` / `FOR` 一律带 `DL_GUARD_MAX` 守卫。
> ⑥ 状态机 `CASE` 必须覆盖枚举**每一个**成员，并带 `ELSE` 兜底；兜底一律置终端安全态，并使用**本件故障段内的最后一个码**作为「非法状态兜底」码（禁止使用 `16#xxxx_FFFF` 等段外值——R11 已把该口子收口为段内码，编码者不得回退）。
> ⑦ 纯函数 FC 必须「同入参同结果」、可重入、无内部状态残留；返回值先预置。

---

### 3.1 `FC_DL_BitArrayExtract`（DL_Base，FC，复杂度 5，源：lgf-bitlogic）

**功能定义**：从 `DWORD` 数组构成的连续位流（LSB 起）中按「起始位 + 位宽（1~64）」提取位窗口，右对齐输出为 `LWORD` 并给出生效掩码。

**工业现场痛点**：64 位设备状态字在 Modbus 上落在两个寄存器、凸轮表位图跨 4 个 `DWORD`、远程 IO 位图跨字存放；现有 `FC_DL_BitFieldExtract` 只能取单字内 32 位，跨字必须由调用方手工拼两个移位再 OR，是现场「低位对、高位错一位」类故障的头号来源。

**引脚规格**

`VAR_IN_OUT`
- `auSource : ARRAY[1..8] OF DWORD;` // 源位流数组，第 1 元素为位 0~31，第 2 元素为位 32~63，依此类推 / Source bit stream, element 1 holds bits 0..31

`VAR_INPUT`
- `nSourceCount : INT := 1;` // 源有效字数 [个]，域 1~8，越界钳位 / Effective source word count, 1..8, clamped
- `nOffset : INT := 0;` // 位窗口起始位 [bit]，域 0~(32×nSourceCount−1) / Window start bit, zero based
- `nWidth : INT := 1;` // 位窗口宽度 [bit]，域 1~64 / Window width, 1..64

`VAR_OUTPUT`
- `uField : LWORD;` // 右对齐提取结果，bit0 起连续 nActualW 位有效 [位串] / Extracted field, right aligned
- `uMask : LWORD;` // 本次实际生效掩码，已右对齐，可直接与结果位与 [位串] / Effective right-aligned mask
- `nActualW : INT;` // 实际生效宽度，越界截断后的值 [bit] / Effective width after truncation
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code, zero means none
- `bValid : BOOL;` // 入参域全合法 = TRUE；发生截断/越界 = FALSE（截断时结果仍可用） / Inputs legal, FALSE when truncated

`VAR`（内部）
- `nTotalBits : DINT;` // 位流总位数 = nSourceCount×32，DINT 中间量防 INT 溢出 [bit] / Total bit count, DINT to avoid overflow
- `nIdxLo : INT;` // 低字下标（1 起）[索引] / Low word index
- `nIdxHi : INT;` // 高字下标（1 起），不跨字时置 0 [索引] / High word index, zero when not straddling
- `uWide : LWORD;` // 两字拼接的 64 位窗口值 [位串] / Stitched 64-bit window
- `uLo : DWORD;` // 低字快照 [位串] / Low word snapshot
- `uHi : DWORD;` // 高字快照，不跨字时为 0 [位串] / High word snapshot, zero when absent
- `nShift : INT;` // 字内移位量 = nOffset MOD 32 [bit] / Intra-word shift amount

`VAR CONSTANT`
- `DL_SRC_MAX : INT := 8;` // 源字数上限 [个] / Source word count limit
- `DL_BIT_MAX64 : INT := 64;` // 位窗宽度上限 [bit] / Window width limit
- `DL_MASK64_ALL : LWORD := 16#FFFF_FFFF_FFFF_FFFF;` // 满宽掩码常量，64 宽分支专用 [位串] / All-ones mask for the 64-bit branch
- `DL_GUARD_MAX : DINT := 64;` // 循环守卫上限 / Loop guard limit

**算法要点**

1. 参数闸门顺序：`nSourceCount` 钳位到 1~8 → 计算 `nTotalBits := DWORD_TO_DINT(nSourceCount) * 32` → 判 `nOffset < 0`（早退，码 `0125`）→ 判 `nWidth < 1 OR nWidth > 64`（早退，码 `0126`）。
2. 越界处理：`IF nOffset >= nTotalBits THEN` 早退（码 `0125`，结果 0）；`IF nOffset + nWidth > nTotalBits THEN` 截断 `nWidth := nTotalBits - nOffset`，置码 `0127`、`bValid := FALSE`（**仍继续计算可用低位**，不返回 0——现场宁可读半段也不要空值）。
3. 定位：`nIdxLo := nOffset / 32 + 1`；`nShift := nOffset MOD 32`；`nIdxHi := 0`，若 `nShift + nWidth > 32` 且 `nIdxLo < nSourceCount` 则 `nIdxHi := nIdxLo + 1`。
4. 拼接：`uWide := DWORD_TO_LWORD(uLo)`；`IF nIdxHi > 0 THEN uWide := uWide OR SHL(DWORD_TO_LWORD(uHi), 32); END_IF`（`SHL` 左操作数为 `LWORD`，移位量 32 < 64，合法）。
5. 右对齐：`uWide := SHR(uWide, INT_TO_UDINT(nShift))`。
6. 掩码：`IF nWidth = 64 THEN uMask := DL_MASK64_ALL; ELSE uMask := SHL(LWORD#1, INT_TO_UDINT(nWidth)) - 1; END_IF`（**禁止** `SHL(x, 64)`）。
7. 结果：`uField := uWide AND uMask; nActualW := nWidth;`

**边界与防错**

- 禁 `SHL(x, 64)`：宽度 64 走常量分支；禁负移位量（`nShift` 由 `MOD 32` 保证 0~31）。
- `nSourceCount` 大于实际数组时无法探测（`VAR_IN_OUT` 无长度），须在头注释写明「调用方对 nSourceCount ≤ 实际数组长度负责」——这是本库唯一允许的「契约式前置条件」，并写进 MANUAL。
- 全路径输出确定：任何早退分支必须先把 `uField/uMask/nActualW/bValid` 置 0/FALSE 再返回。
- 跨字但高字不存在（`nOffset` 落在末字、`nShift + nWidth > 32`）时按截断处理，码 `0127`。

**验收向量**

- V1：`auSource[1]=16#1234_5678`、`auSource[2]=16#9ABC_DEF0`、`nSourceCount=2`、`nOffset=28`、`nWidth=8` → 位流 `16#9ABCDEF0_12345678` 右移 28 位得 `16#9ABCDEF0_1`，取低 8 位 = `16#01`；期望 `uField=16#01`、`uMask=16#0000_0000_0000_00FF`、`nActualW=8`、`bValid=TRUE`、`uErrorId=0`。
- V2：与 V1 同两字数组、`nOffset=20`、`nWidth=16` → 右移 20 位取低 16 位 = `16#0123`；期望 `uField=16#0123`、`uMask=16#FFFF`、`bValid=TRUE`。
- V3：与 V1 同两字数组、`nOffset=56`、`nWidth=16` → 总位数 64，`56+16=72 > 64` 截断为 8；`uField=16#9A`、`nActualW=8`、`bValid=FALSE`、`uErrorId=16#0001_0127`。
- V4：`nOffset=32`、`nSourceCount=1` → 早退，`uField=0`、`bValid=FALSE`、`uErrorId=16#0001_0125`。
- V5：`nWidth=65` → 早退，`uField=0`、`bValid=FALSE`、`uErrorId=16#0001_0126`。

**来源与借鉴**：`source = lgf-bitlogic`。借鉴点：LGF Bit Logic 组「位测试/置位/复位 → 位串批量」的**分类层次**（单点 → 单段 → 批量段），以及「源 / 起位 / 宽度」三段参数域。算法、掩码构造、截断策略、错误码全部自有；LGF 为免费闭源，**零代码行、零注释、零 DB 结构**引用。

---

### 3.2 `FC_DL_BitArrayInsert`（DL_Base，FC，复杂度 6，源：lgf-bitlogic）

**功能定义**：把 `LWORD` 值按「起始位 + 位宽」写入 `DWORD` 数组位流的指定窗口，只改动窗口内位，输出实际写入值、掩码与改动字数。

**工业现场痛点**：下发 64 位使能字/报警屏蔽字时，逐位 `BitSet` 会引发「半更新」（HMI 看到中间态）、且易误清相邻位；字节级整体写入又会把别的字段一起覆盖。现场需要一个「原子位窗写」。

**引脚规格**

`VAR_IN_OUT`
- `auTarget : ARRAY[1..8] OF DWORD;` // 被写入的目标位流数组，本函数**原地修改** / Target bit stream, modified in place

`VAR_INPUT`
- `uValue : LWORD;` // 待写入值，只用低 nWidth 位，超宽位忽略 / Value to write, only the low nWidth bits are used
- `nTargetCount : INT := 1;` // 目标有效字数 [个]，域 1~8 / Effective target word count
- `nOffset : INT := 0;` // 写入窗口起始位 [bit]，域 0~(32×nTargetCount−1) / Window start bit
- `nWidth : INT := 8;` // 写入窗口宽度 [bit]，域 1~64 / Window width

`VAR_OUTPUT`
- `nChanged : INT;` // 实际发生改动的字数 [个]，值未变的字不计入 / Number of words actually modified
- `uApplied : LWORD;` // 实际写入的右对齐值（已按宽度截断）[位串] / Value actually applied
- `uMask : LWORD;` // 本次生效掩码，右对齐 [位串] / Effective right-aligned mask
- `nActualW : INT;` // 实际生效宽度 [bit] / Effective width
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `bValid : BOOL;` // 全合法 TRUE；截断或越界 FALSE / All inputs legal

`VAR`（内部）
- `nTotalBits : DINT;` // 总位数 [bit] / Total bit count
- `nIdxLo : INT;` // 低字下标 [索引] / Low word index
- `nIdxHi : INT;` // 高字下标，0 = 不跨字 / High word index, zero when not straddling
- `nShift : INT;` // 字内移位量 [bit] / Intra-word shift
- `uWinWide : LWORD;` // 已左移到窗口位置的双字掩码值 [位串] / Window value shifted into place
- `uMaskWide : LWORD;` // 已左移到窗口位置的双字掩码 [位串] / Window mask shifted into place
- `uOldLo : DWORD;` // 低字旧值 [位串] / Previous low word
- `uOldHi : DWORD;` // 高字旧值 [位串] / Previous high word
- `uNewLo : DWORD;` // 低字新值 [位串] / New low word
- `uNewHi : DWORD;` // 高字新值 [位串] / New high word

`VAR CONSTANT`
- `DL_MASK64_ALL : LWORD := 16#FFFF_FFFF_FFFF_FFFF;` // 满宽掩码 [位串] / All-ones mask
- `DL_SRC_MAX : INT := 8;` // 字数上限 [个] / Word count limit

**算法要点**

1. 闸门与截断同 3.1（码 `0128` 偏移越界 / `0129` 宽度越界 / `012A` 跨字截断），截断后仍写可用位。
2. 掩码构造：`nWidth = 64` 走 `DL_MASK64_ALL`，否则 `SHL(LWORD#1, nWidth) - 1`；`uApplied := uValue AND mask`。
3. 展开到双字：`uMaskWide := SHL(mask, nShift)`；`uWinWide := SHL(uApplied, nShift)`。
4. 读改写：`uNewLo := (uOldLo AND NOT LWORD_TO_DWORD(uMaskWide)) OR LWORD_TO_DWORD(uWinWide)`；若 `nIdxHi > 0` 则对高字用 `SHR(uMaskWide, 32)` / `SHR(uWinWide, 32)` 的低 32 位做同样运算。
5. 改动计数：`IF uNewLo <> uOldLo THEN nChanged := nChanged + 1; END_IF`（**先比较后写**，值相同不计数、也不产生写动作，减少下游无谓刷新）。
6. 写回顺序：先算完全部新值，再依次赋回 `auTarget[nIdxLo]`、`auTarget[nIdxHi]`，避免「读一半写一半」的撕裂。

**边界与防错**

- `SHL(x, 32)` 允许（LWORD 宽度 64），但 `SHL(x, 64)` 严禁：`nShift` 最大 31，`nWidth=64` 时 `nShift` 必为 0，故 `uMaskWide` 不会溢出位宽；须在断言中验证 `nShift + nWidth <= 64`。
- `nTargetCount` 大于实际数组长度属调用方违约，头注释与 MANUAL 双处声明。
- 早退分支所有输出预置（`nChanged=0`、`uApplied=0`、`uMask=0`、`nActualW=0`、`bValid=FALSE`）。
- 本件是**有副作用的函数**（写 `VAR_IN_OUT`），头注释必须写明「纯函数仅指无内部状态、同入参同结果；副作用限于形参指向的数组」，防止误当只读函数使用。

**验收向量**

- V1：`auTarget[1]=16#FFFF_FFFF`、`auTarget[2]=16#FFFF_FFFF`、`nTargetCount=2`、`nOffset=28`、`nWidth=8`、`uValue=16#A5` → 低 4 位 `16#5` 落 `auTarget[1]` 的 bit28~31 → `16#5FFF_FFFF`；高 4 位 `16#A` 落 `auTarget[2]` 的 bit0~3 → `16#FFFF_FFFA`；期望 `nChanged=2`、`uApplied=16#A5`、`nActualW=8`、`bValid=TRUE`。
- V2：`auTarget[1]=16#0000_0000`、`nTargetCount=1`、`nOffset=0`、`nWidth=4`、`uValue=16#3` → `auTarget[1]=16#0000_0003`、`nChanged=1`、`bValid=TRUE`。
- V3：`auTarget[1]=16#0000_000F`、`nOffset=0`、`nWidth=4`、`uValue=16#F` → 值未变，`nChanged=0`、`auTarget[1]` 保持 `16#0000_000F`。
- V4：`nOffset=30`、`nWidth=8`、`nTargetCount=1`、`uValue=16#FF` → 截断为宽 2，只写 bit30~31 的 `16#3`，`bValid=FALSE`、`uErrorId=16#0001_012A`。

**来源与借鉴**：`source = lgf-bitlogic`。借鉴点：批量位段的「打包/提取双向成对」组织方式（LGF 位逻辑组内 `Set_Bit` / `Reset_Bit` / 批量位串三口分工）。实现、掩码、写回时序全自有。

---

### 3.3 `FC_DL_IntervalMembership`（DL_Base，FC，复杂度 3，源：lgf-comparator）

**功能定义**：判定一个实数是否落在「开闭组合」区间内，并给出到最近边界的有符号裕量与「恰在边界」标志。

**工业现场痛点**：工艺窗口大量是半开约定（温度 `[60, 80)`、压力 `(0.4, 0.6]`），现场用 `>= AND <` 手写，边界归属靠记性，同一产线不同工位写法不一致，导致临界值既报「超限」又报「未到」；LGF Comparator 组把「开闭区间」做成独立原子函数正是为此。

**引脚规格**

`VAR_INPUT`
- `fValue : LREAL;` // 被判定值 [工程单位由调用方决定] / Value under test, unit defined by the caller
- `fLower : LREAL;` // 区间下限 [工程单位由调用方决定] / Lower bound, unit defined by the caller
- `fUpper : LREAL;` // 区间上限 [工程单位由调用方决定] / Upper bound, unit defined by the caller
- `eKind : E_DL_IntervalKind := E_DL_IntervalKind.eClosedOpen;` // 开闭组合，默认左闭右开 / Openness combination, default left-closed right-open
- `fEps : LREAL := 1.0E-9;` // 边界判定容差 [工程单位由调用方决定]，<= 0 时按 1E-9 生效 / Boundary tolerance, non-positive falls back to 1E-9

`VAR_OUTPUT`
- `bInside : BOOL;` // 落在区间内 TRUE / Inside the interval
- `bOnBoundary : BOOL;` // 与某端点距离 < fEps TRUE / Within tolerance of an endpoint
- `fMargin : LREAL;` // 到最近边界的有符号裕量，内正外负，临界为 0 [工程单位由调用方决定] / Signed margin to the nearest bound
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `bValid : BOOL;` // 端点有序且值有限 = TRUE / Bounds ordered and value finite

`VAR`（内部）
- `fLo : LREAL;` // 生效下限，容差修正后 / Effective lower bound
- `fUp : LREAL;` // 生效上限，容差修正后 / Effective upper bound
- `fEpsUse : LREAL;` // 生效容差 / Effective tolerance
- `bNearLo : BOOL;` // 贴近下限 / Near the lower bound
- `bNearUp : BOOL;` // 贴近上限 / Near the upper bound
- `bLoOk : BOOL;` // 下界侧通过 / Lower side passes
- `bUpOk : BOOL;` // 上界侧通过 / Upper side passes

`VAR CONSTANT`
- `DL_EPS_MIN : LREAL := 1.0E-9;` // 最小容差 [工程单位由调用方决定] / Minimum tolerance

**算法要点**

1. 有限性：`IF (fValue <> fValue) OR (fLower <> fLower) OR (fUpper <> fUpper) THEN` → `bValid := FALSE`、`bInside := FALSE`、码 `012C`（NaN 判定用 `x <> x`，不用 `IS_NAN`，跨平台）。
2. 端点序：`IF fLower > fUpper + fEpsUse THEN` → `bValid := FALSE`、码 `012B`（端点倒置），`bInside := FALSE`，早退。
3. 边界贴近：`bNearLo := ABS(fValue - fLower) < fEpsUse`；`bNearUp := ABS(fValue - fUpper) < fEpsUse`；`bOnBoundary := bNearLo OR bNearUp`。
4. 下界侧：`bLoOk` 按 eKind 取 —— `eClosedClosed` / `eClosedOpen` 为 `fValue >= fLower`（贴近时视为通过）；`eOpenClosed` / `eOpenOpen` 为 `fValue > fLower`（贴近时视为不通过，即 `bNearLo → FALSE`）。
5. 上界侧：`bUpOk` 同理，`eClosedClosed` / `eOpenClosed` 为 `fValue <= fUpper`；`eClosedOpen` / `eOpenOpen` 为 `fValue < fUpper`。
6. 退化区间 `ABS(fUpper - fLower) < fEpsUse`：仅当 `eKind = eClosedClosed` 且 `bOnBoundary` 时 `bInside := TRUE`，其余组合一律 FALSE（单点区间不被半开组合包含）。
7. 裕量：`fMargin := MIN(fValue - fLower, fUpper - fValue)`；若 `NOT bInside` 则取负：`fMargin := MIN(fValue - fLower, fUpper - fValue)` 中为负的那一侧自然为负值，故无需额外取反——**实现上直接输出 `MIN(fValue-fLower, fUpper-fValue)`**，外侧自然为负。

**边界与防错**

- `fEps <= 0` → 用 `DL_EPS_MIN`（防「容差为 0 时浮点永不相等」的静默失效）。
- 端点倒置只报信息级、不锁存（纯函数无锁存面）。
- 全部路径 `uErrorId` 单值输出，多事件只保留首个（顺序：NaN → 端点倒置 → 其它）。

**验收向量**

- V1：`fValue=60.0`、`fLower=60.0`、`fUpper=80.0`、`eKind=eClosedOpen` → `bInside=TRUE`、`bOnBoundary=TRUE`、`fMargin=0.0`。
- V2：`fValue=80.0`、同区间 → `bInside=FALSE`（右开）、`bOnBoundary=TRUE`、`fMargin=0.0`。
- V3：`fValue=59.5`、同区间 → `bInside=FALSE`、`fMargin=-0.5`。
- V4：`fValue=70.0` → `bInside=TRUE`、`fMargin=10.0`。
- V5：`fLower=80.0`、`fUpper=60.0` → `bValid=FALSE`、`bInside=FALSE`、`uErrorId=16#0001_012B`。
- V6：`fValue=70.0`、`eKind=eOpenOpen`、`fLower=fUpper=70.0` → `bInside=FALSE`（退化点不在双开区间内）。

**来源与借鉴**：`source = lgf-comparator`。借鉴点：LGF Comparator 组把「区间判断 / 公差窗口 / 限值」三分，且区间带开闭属性的参数域设计。实现与容差策略自有（LGF 无容差概念，本库加严）。

---

### 3.4 `FB_DL_BitArrayChangeWatch`（DL_Base，FB，复杂度 5，源：lgf-bitlogic）

**功能定义**：逐拍监视 `DWORD` 数组位图的位级变化，输出本拍变化掩码、变化位总数、首个变化位的绝对位号，并累计跳变次数与稳定标志。

**工业现场痛点**：远程 IO 位图/报警字组每拍刷新，HMI 只显示「有变化」却不定位；接触不良的端子表现为某一位反复抖动，需要单独统计跳变次数才能定位到具体端子和线号。现场靠示波器或逐位加计数器，工作量巨大。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时输出清零并退出采样态 / Enable, clears outputs when FALSE
- `bReset : BOOL;` // 上升沿复位跳变计数与稳定计时 / Rising edge resets toggles and settle timer
- `nWordCount : INT := 1;` // 监视字数 [个]，域 1~8，越界钳位 / Watched word count, 1..8, clamped
- `auWatch : ARRAY[1..8] OF DWORD;` // 当前位图快照 [位串] / Current bitmap snapshot
- `nSettleCycles : INT := 2;` // 判稳所需连续无变化拍数 [拍]，域 1~100 / Cycles required to declare steady

`VAR_OUTPUT`
- `auChangeMask : ARRAY[1..8] OF DWORD;` // 本拍变化位掩码，按字对齐 [位串] / Per-word change mask of this cycle
- `nChangeBits : INT;` // 本拍变化位总数（汉明重量之和）[位] / Total changed bits this cycle
- `nFirstBit : INT;` // 首个变化位绝对位号，−1 = 本拍无变化 [bit] / First changed absolute bit, minus one when none
- `uToggleCount : UDINT;` // 累计跳变位数 [位·次]，由 bReset 清零 / Accumulated toggled bits, cleared by reset
- `bSteady : BOOL;` // 连续 nSettleCycles 拍无变化 TRUE / No change for the settle window
- `eState : E_DL_BitWatchState;` // 主状态机当前状态 [-] / Current state of the main state machine
- `bError : BOOL;` // 故障级锁存，仅 021A 021B 置位 / Latched fault flag
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code

`VAR_IN_OUT`（无）

`VAR`（内部）
- `auPrev : ARRAY[1..8] OF DWORD;` // 上拍快照，跨周期保持 / Previous snapshot, kept across cycles
- `auXor : ARRAY[1..8] OF DWORD;` // 本拍异或结果 [位串] / XOR result of this cycle
- `fbTrigReset : R_TRIG;` // 复位沿检测，CASE 之外无条件刷新 / Reset edge detector, refreshed outside CASE
- `eStateInt : E_DL_BitWatchState := E_DL_BitWatchState.eIdle;` // 内部状态，对外经 eState 输出 / Internal state, exported via eState
- `bFirstScan : BOOL := FALSE;` // 首扫标志，初值 FALSE，判据 NOT bFirstScan / First-scan flag, initialised FALSE
- `nWordClamped : INT;` // 钳位后字数 [个] / Clamped word count
- `nSettleUse : INT;` // 生效判稳拍数 [拍] / Effective settle cycles
- `nSteadyCnt : INT;` // 已稳定拍数 [拍] / Cycles already steady
- `uWeight : UDINT;` // 单字位计数中间量 [位] / Per-word population count
- `nBitScan : INT;` // 位扫描索引 [bit] / Bit scan index
- `nGuard : DINT;` // 循环守卫计数 / Loop guard counter
- `bAnyChange : BOOL;` // 本拍是否变化 / Any change this cycle
- `bParamClamped : BOOL;` // 参数被钳位标记 / Parameter clamped flag

`VAR CONSTANT`
- `DL_WORD_MAX : INT := 8;` // 字数上限 [个] / Word count limit
- `DL_BIT_WORD : INT := 32;` // 单字位宽 [bit] / Bits per word
- `DL_GUARD_MAX : DINT := 64;` // 循环守卫上限 / Loop guard limit
- `DL_I_W : INT := 1;` // 数组首下标 / First array index

**算法要点**

- 状态机（`E_DL_BitWatchState` 三成员，`CASE` 全覆 + `ELSE` 兜底置 `eFault` + 码 `16#0001_021B`）：
  - `eIdle`：`bEnable` 上升后装载全部 `auPrev`（**只装载不产生变化**），置 `bFirstScan := TRUE`，转 `eSampling`。
  - `eSampling`：逐字 `auXor[i] := auWatch[i] XOR auPrev[i]`；`auChangeMask[i] := auXor[i]`；累计 `nChangeBits` 与 `uToggleCount`；扫首个非零字的最低置位位得 `nFirstBit := (i-1)*32 + bit`；无变化则 `nFirstBit := -1` 并累加 `nSteadyCnt`；`nSteadyCnt >= nSettleUse` 时 `bSteady := TRUE`；随后 `auPrev := auWatch`（**赋值在输出之后**，保证下一拍才生效）。
  - `eFault`：输出冻结，`bError := TRUE`，`bReset` 上升沿清故障回 `eIdle`。
- 位计数：对每字从 bit0 到 bit31 逐位 `IF (auXor[i] AND SHL(DWORD#1, bit)) <> 0` 累加，`FOR` 带 `nGuard` 守卫；**不用** `BitCount` 外部件（DL_Base 内不得反向依赖数学层，且 `FC_DL_BitCount` 现签名只吃 WORD）。
- 首变位扫描与位计数合并为同一趟循环，避免两趟扫描的节拍差。

**边界与防错**

- `nWordCount` 越界：< 1 → 钳 1 并置故障码 `021A`（数组域非法属组态错，须显式告知）；> 8 → 钳 8 并置信息码 `012D`。
- `nSettleCycles` < 1 → 钳 1，信息码 `012E`；> 100 → 钳 100，同码。
- `bFirstScan = FALSE` 期间不得向 `uToggleCount` 累加（首扫装载不构成跳变），否则上电瞬间误报「全部位跳动」。
- `uToggleCount` 饱和：累加到 `16#FFFF_FFFE` 后停住并置信息码 `012F`（**禁止回绕**，回绕会把「抖动最严重」的位算成「最干净」）。
- `bEnable` 为 FALSE 时：`auChangeMask` 清零、`nChangeBits := 0`、`nFirstBit := -1`、`bSteady := FALSE`，但 `uToggleCount` **保持**（掉使能不应抹掉诊断证据）。

**验收向量**

- V1：`nWordCount=1`，`auPrev[1]=16#0000_0001`，`auWatch[1]=16#0000_0005` → 异或 `16#0000_0004`；期望 `auChangeMask[1]=16#0000_0004`、`nChangeBits=1`、`nFirstBit=2`、`bSteady=FALSE`。
- V2：`auPrev[1]=16#FFFF_FFFF`，`auWatch[1]=16#FFFF_FFFE` → 异或 `16#0000_0001`；`nChangeBits=1`、`nFirstBit=0`。
- V3：`auPrev=auWatch=16#0000_0000`、`nSettleCycles=2` → 连续第 2 拍起 `nChangeBits=0`、`nFirstBit=-1`、`bSteady=TRUE`。
- V4：`nWordCount=0` → 钳 1，`bError=TRUE`、`uErrorId=16#0001_021A`。
- V5：`nWordCount=2`，仅第 2 字 bit5 变化 → `nChangeBits=1`、`nFirstBit=37`（第 2 字基址 32 + 5）。

**来源与借鉴**：`source = lgf-bitlogic`。借鉴点：位组「批量监视」在 LGF 位逻辑组内与「单点位测试」并列的分类位置。变化检测算法、跳变统计、饱和策略全自有。

---

### 3.5 `FC_DL_ArrayDiffSummary`（DL_MathData，FC，复杂度 4，源：lgf-comparator）

**功能定义**：两组实数数组按统一绝对容差逐项比对，输出差异项数、首个差异下标、最大绝对偏差及其下标与一致性结论。

**工业现场痛点**：配方回读、双通道冗余比对、视觉参数下发校验，现场只判「有差异」，定位不到第几项、差多少；用 `=` 判等又因浮点误差把合格品报成不合格。维修工只能逐项翻表。

**引脚规格**

`VAR_IN_OUT`
- `afExpected : ARRAY[1..64] OF REAL;` // 期望值数组（基准），只读 / Expected reference array, read only
- `afActual : ARRAY[1..64] OF REAL;` // 实际值数组（回读），只读 / Actual readback array, read only

`VAR_INPUT`
- `nCount : INT := 1;` // 参与比对项数 [项]，域 1~64，越界钳位 / Item count, 1..64, clamped
- `fAbsTol : REAL := 0.01;` // 统一绝对容差 [工程单位]，负数取绝对值 / Absolute tolerance, negative folded to positive

`VAR_OUTPUT`
- `nDiffCount : INT;` // 超差项数 [项] / Number of out-of-tolerance items
- `nFirstDiffIdx : INT;` // 首个超差项下标，0 = 无超差 [索引] / First out-of-tolerance index, zero when none
- `fMaxDev : REAL;` // 最大绝对偏差值 [工程单位] / Maximum absolute deviation
- `nMaxDevIdx : INT;` // 最大偏差所在下标，0 = 未计算 [索引] / Index of the maximum deviation
- `bEqual : BOOL;` // 全部在容差内 TRUE / All items within tolerance
- `bNonFinite : BOOL;` // 出现过 NaN / Inf 项 TRUE / NaN or Inf encountered
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `bValid : BOOL;` // 项数与容差合法 = TRUE / Count and tolerance legal

`VAR`（内部）
- `nCountUse : INT;` // 生效项数 [项] / Effective item count
- `fTolUse : REAL;` // 生效容差 [工程单位] / Effective tolerance
- `fDev : REAL;` // 单项偏差 [工程单位] / Per-item deviation
- `fA : REAL;` // 当前期望值快照 / Expected value snapshot
- `fB : REAL;` // 当前实际值快照 / Actual value snapshot
- `bFinA : BOOL;` // 期望值有限性 / Expected value finiteness
- `bFinB : BOOL;` // 实际值有限性 / Actual value finiteness
- `nGuard : DINT;` // 循环守卫 / Loop guard
- `i : INT;` // 遍历索引 / Loop index

`VAR CONSTANT`
- `DL_ITEM_MAX : INT := 64;` // 项数上限 [项] / Item count limit
- `DL_GUARD_MAX : DINT := 128;` // 循环守卫上限 / Loop guard limit

**算法要点**

1. `nCount` 钳位 1~64，越界置码 `0134`（信息级）且 `bValid := FALSE`；`fAbsTol` 取绝对值，若结果 `< 1E-9` 则用 `1E-9`（防「容差为 0」把纯浮点噪声全判超差），置码 `0135`。
2. 有限性判定用 `x <> x`（NaN）+ `ABS(x) > DL_FINITE_MAX`（Inf 近似判定，`DL_FINITE_MAX := 3.4E38`）；任一非有限 → `bNonFinite := TRUE`，该项直接计为超差，`fDev := 0.0`（不参与最大偏差竞争，避免 Inf 污染）。
3. 正常项：`fDev := ABS(fA - fB)`；`IF fDev > fTolUse THEN` 累加 `nDiffCount`，首个超差记录 `nFirstDiffIdx`（仅当为 0 时写）；同时与 `fMaxDev` 比较，严格大于才更新 `fMaxDev` / `nMaxDevIdx`（**并列取先出现者**，保证可复现）。
4. `bEqual := (nDiffCount = 0) AND NOT bNonFinite`。
5. 单循环完成全部判定，无嵌套循环、无排序。

**边界与防错**

- `nCount` 大于实际数组长度属调用方违约（`VAR_IN_OUT` 无长度），头注释声明。
- 最大偏差并列时取小下标；全项非有限时 `nMaxDevIdx := 0`、`fMaxDev := 0.0` 且 `bEqual := FALSE`。
- `fAbsTol` 为负：取绝对值为容差（不报错，容差方向无物理意义）。
- 早退预置：`nDiffCount=0`、`nFirstDiffIdx=0`、`fMaxDev=0.0`、`nMaxDevIdx=0`、`bEqual=FALSE`。

**验收向量**

- V1：`nCount=3`、`afExpected=[10.0, 20.0, 30.0]`、`afActual=[10.0, 20.005, 30.2]`、`fAbsTol=0.01` → 第 2 项偏差 0.005 ≤ 0.01 合格；第 3 项偏差 0.2 > 0.01 超差；期望 `nDiffCount=1`、`nFirstDiffIdx=3`、`fMaxDev=0.2`、`nMaxDevIdx=3`、`bEqual=FALSE`。
- V2：`nCount=2`、`afExpected=[1.0, 2.0]`、`afActual=[1.0, 2.0000001]`、`fAbsTol=0.01` → `nDiffCount=0`、`nFirstDiffIdx=0`、`fMaxDev=1.0E-7`、`bEqual=TRUE`。
- V3：`nCount=3`、`afActual[2]` 置 NaN → `bNonFinite=TRUE`、`nDiffCount` 含该项、`bEqual=FALSE`。
- V4：`nCount=0` → 钳 1，`bValid=FALSE`、`uErrorId=16#0001_0134`。

**来源与借鉴**：`source = lgf-comparator`。借鉴点：Comparator 组「数组批量比较」与「容差窗口」两个子域的划分。算法与统计口径自有（LGF 批量比较不输出最大偏差与下标）。

---

### 3.6 `FC_DL_StringReplaceAll`（DL_MathData，FC，复杂度 5，源：lgf-datahandling）

**功能定义**：在定长字符串内把全部出现的子串替换为另一子串，输出替换次数、结果串与截断标志。

**工业现场痛点**：条码前缀规范化、报表模板占位符替换（`%LOT%`、`%DATE%`）、报文关键字替换（把设备商的旧机型代号换成新代号）。IEC 61131-3 只有 `REPLACE`（按下标单次替换），现场用 `WHILE + FIND + DELETE + INSERT` 手写，替换串含模式串时直接死循环。

**引脚规格**

`VAR_INPUT`
- `sSource : STRING(255);` // 源串，最长 255 字符 / Source string, up to 255 characters
- `sPattern : STRING(32);` // 被替换子串，长度 0 视为非法 / Pattern to replace, empty is illegal
- `sReplace : STRING(64);` // 替换子串，允许为空（即删除） / Replacement, empty means delete
- `nMaxReplace : INT := 32;` // 替换次数上限 [次]，域 0~255，0 = 不限 / Replacement limit, zero means unlimited
- `nMaxLen : INT := 255;` // 结果串长度上限 [字符]，域 1~255 / Result length limit, 1..255

`VAR_OUTPUT`
- `sResult : STRING(255);` // 替换结果，超长时按 nMaxLen 截断 / Result, truncated to nMaxLen
- `nReplaced : INT;` // 实际替换次数 [次] / Replacement count
- `bTruncated : BOOL;` // 结果被截断 TRUE / Result was truncated
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `bValid : BOOL;` // 模式串非空且长度参数合法 = TRUE / Pattern non-empty and lengths legal

`VAR`（内部）
- `sBuf : STRING(255);` // 工作缓冲 / Working buffer
- `sHead : STRING(255);` // 本次替换位置之前的头部片段 / Head fragment before the hit
- `sTail : STRING(255);` // 本次替换位置之后的尾部片段 / Tail fragment after the hit
- `nPos : INT;` // 当前命中位置，1 起，0 = 未命中 [字符位] / Current hit position, one based
- `nSearchFrom : INT;` // 下一轮查找起点，1 起 [字符位] / Next search start position
- `nLenBuf : INT;` // 当前缓冲长度 [字符] / Current buffer length
- `nLenPat : INT;` // 模式串长度 [字符] / Pattern length
- `nMaxRepUse : INT;` // 生效替换上限 [次] / Effective replacement limit
- `nMaxLenUse : INT;` // 生效结果长度上限 [字符] / Effective result length limit
- `nGuard : DINT;` // 循环守卫 / Loop guard

`VAR CONSTANT`
- `DL_STR_MAX : INT := 255;` // IEC STRING(255) 上限 [字符] / IEC string limit
- `DL_GUARD_MAX : DINT := 512;` // 循环守卫上限 / Loop guard limit

**算法要点**

1. 参数闸门：`nMaxLen` 钳 1~255（码 `0133`）；`nMaxReplace` 钳 0~255（0 = 不限，映射为 `DL_STR_MAX` 次）。
2. `nLenPat := LEN(sPattern)`；`IF nLenPat = 0 THEN` → `sResult := sSource`、`bValid := FALSE`、码 `0130`（模式空，**防死循环的第一道闸**）、早退。
3. 主循环：`sBuf := sSource`；`nSearchFrom := 1`；`WHILE (nReplaced < nMaxRepUse) AND (nGuard < DL_GUARD_MAX) DO`：
   - `nPos := FIND(sBuf, sPattern)`；`IF nPos = 0 THEN EXIT; END_IF`
   - **只查找 `nSearchFrom` 之后**：若 `nSearchFrom > 1` 则先在 `MID(sBuf, nSearchFrom, LEN(sBuf)-nSearchFrom+1)` 上 `FIND`，命中位置加回偏移（防「替换串包含模式串」自增长死循环）。
   - 切分：`sHead := LEFT(sBuf, nPos-1)`；`sTail := MID(sBuf, nPos + nLenPat, nLenBuf - (nPos + nLenPat) + 1)`；`sBuf := CONCAT(sHead, sReplace); sBuf := CONCAT(sBuf, sTail)`。
   - `nSearchFrom := nPos + LEN(sReplace)`；`nReplaced := nReplaced + 1`；`sBuf := LEFT(sBuf, DL_STR_MAX)`（**每轮强制回夹**，防 CONCAT 溢出）。
4. 截断：`IF LEN(sBuf) > nMaxLenUse THEN sBuf := LEFT(sBuf, nMaxLenUse); bTruncated := TRUE; 码 0132; END_IF`
5. 达上限：`IF (nReplaced >= nMaxRepUse) AND (FIND(MID(sBuf, nSearchFrom, LEN(sBuf) - nSearchFrom + 1), sPattern) <> 0) THEN 码 0131（达替换上限，结果不完整）`。
6. `sResult := sBuf`。

**边界与防错**

- 模式空 → 早退（`0130`），绝不进循环。
- 替换串含模式串（如 `A → AA`）→ 靠 `nSearchFrom := nPos + LEN(sReplace)` 前进，天然跳过新插入段，不死循环；须有一组专门验收向量。
- 每轮 `LEFT(sBuf, 255)` 回夹，防 `CONCAT` 超长截断产生不可预期结果。
- 循环双闸：次数上限 + `nGuard` 守卫，任一触发即退出并置码。
- 长度参数钳位（`nMaxLen` 越界）置信息码 `0133`，钳位后照常执行，不早退。
- 全部路径 `sResult` 有值（早退分支赋 `sSource`）。

**验收向量**

- V1：`sSource='LOT_%L%-01'`、`sPattern='%L%'`、`sReplace='A12'` → `sResult='LOT_A12-01'`、`nReplaced=1`、`bValid=TRUE`。
- V2：`sSource='A|A|A'`、`sPattern='A'`、`sReplace='BB'` → `sResult='BB|BB|BB'`、`nReplaced=3`（**验证替换串含模式字符不死循环**）。
- V3：`sPattern=''` → `bValid=FALSE`、`sResult` 等于源串、`uErrorId=16#0001_0130`。
- V4：`sSource='A|A|A'`、`nMaxReplace=2` → `sResult='BB|BB|A'`、`nReplaced=2`、`uErrorId=16#0001_0131`（达上限，结果不完整）。
- V5：`sSource` 长 250、`sReplace` 长 10、构造 5 次替换后长度 300 → `bTruncated=TRUE`、`LEN(sResult)=255`、`uErrorId=16#0001_0132`。
- V6：`nMaxLen=0` → 钳 1，`uErrorId=16#0001_0133`、`LEN(sResult)=1`、`bTruncated=TRUE`。

**来源与借鉴**：`source = lgf-datahandling`。借鉴点：LGF Data Handling 组把「FIFO/LIFO、数组搜索、排序、字符串」并列成数据操作组的分类方式，以及字符串函数「原地 + 定长」的参数域约定（不使用动态内存）。算法自有。

---

### 3.7 `FB_DL_StringTokenStream`（DL_MathData，FB，复杂度 6，源：lgf-datahandling）

**功能定义**：按分隔符把一条定长报文逐段取出，每次调用输出一段，跨周期推进，不阻塞扫描、不动态分配。

**工业现场痛点**：扫码枪、称重仪表、在线分析仪报文（`ST,GS,+0012.5kg,OK`）字段长度不固定，现场用 `MID + FIND` 手写，空字段（连续分隔符）直接把字段序号错位，后续所有字段全错；一次解析整帧又会撑爆扫描周期。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时冻结游标并清输出 / Enable, freezes cursor when FALSE
- `bReset : BOOL;` // 上升沿复位到帧起点 / Rising edge rewinds to the frame start
- `sFrame : STRING(255);` // 待分词报文，变化沿自动重装载 / Frame to tokenise, reloaded on change
- `sDelimiter : STRING(4);` // 分隔符（1~4 字符），空 = 故障 / Delimiter of one to four characters
- `bNext : BOOL;` // 上升沿取下一段 / Rising edge advances to the next token
- `nMaxTokenLen : INT := 32;` // 单段最大长度 [字符]，域 1~64 / Maximum token length
- `nMaxTokens : INT := 32;` // 单帧最大段数 [段]，域 1~64 / Maximum token count

`VAR_OUTPUT`
- `sToken : STRING(64);` // 本段内容，超长截断 / Current token, truncated when too long
- `nTokenIdx : INT;` // 本段序号，1 起 [索引] / Token index, one based
- `nTokenCount : INT;` // 本帧已产出段数 [段] / Tokens produced so far
- `bValidToken : BOOL;` // 本段非空（连续分隔符产生的空段为 FALSE） / Non-empty token
- `bDone : BOOL;` // 已到末段之后 TRUE（单拍脉冲） / End of frame reached
- `bError : BOOL;` // 故障级锁存，仅 021C 021D 021E 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_TokenPhase;` // 主状态机当前相位 / Current phase

`VAR`（内部）
- `fbTrigNext : R_TRIG;` // bNext 上升沿，无条件刷新 / bNext rising edge, refreshed unconditionally
- `fbTrigFrame : R_TRIG;` // sFrame 变化沿（用 LEN + 首字符哈希近似「变化」不可靠，改为对整串做逐字符比较的 `bFrameChanged`，本变量仅用于单拍锁存） / Frame change edge
- `fbTrigReset : R_TRIG;` // 复位沿 / Reset edge
- `ePhase : E_DL_TokenPhase := E_DL_TokenPhase.eIdle;` // 内部相位 / Internal phase
- `sFrameLatched : STRING(255);` // 已装载的帧副本，防调用方中途改写 / Latched frame copy
- `nCursor : INT;` // 当前解析游标，1 起 [字符位] / Parse cursor
- `nFrameLen : INT;` // 帧长度 [字符] / Frame length
- `nDelimLen : INT;` // 分隔符长度 [字符] / Delimiter length
- `nMaxTokUse : INT;` // 生效段数上限 [段] / Effective token limit
- `nMaxLenUse : INT;` // 生效段长上限 [字符] / Effective token length limit
- `nSegStart : INT;` // 本段起始位置 [字符位] / Segment start
- `nSegLen : INT;` // 本段长度 [字符] / Segment length
- `bFrameChanged : BOOL;` // 帧内容与副本不同 / Frame differs from the copy
- `i : INT;` // 逐字符比较索引 / Character compare index
- `nGuard : DINT;` // 守卫 / Loop guard

`VAR CONSTANT`
- `DL_TOK_MAX : INT := 64;` // 段数/段长上限 [个/字符] / Token limits
- `DL_GUARD_MAX : DINT := 512;` // 守卫上限 / Guard limit

**算法要点**

- 状态机（`E_DL_TokenPhase` 四成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0001_021E`）：
  - `eIdle`：`bEnable` 后校验 `LEN(sDelimiter) >= 1`，合法则转 `eReady`，否则 `eFault` + `021C`。
  - `eReady`：等待帧装载或 `bNext`；帧变化（逐字符比较 `sFrame` 与 `sFrameLatched`）→ 重装载 `sFrameLatched`、`nCursor := 1`、`nTokenIdx := 0`、`nTokenCount := 0`、`bDone := FALSE`；`bNext` 上升沿 → 转 `eDraining`。
  - `eDraining`：取一段 → 输出 → `nCursor` 前移 → 回 `eReady`；若 `nCursor > nFrameLen` → `bDone := TRUE` 单拍 → 回 `eReady`。
  - `eFault`：输出冻结；`bReset` 上升沿回 `eIdle`。
- 取段：`nSegStart := nCursor`；在 `MID(sFrameLatched, nCursor, nFrameLen-nCursor+1)` 上 `FIND(sDelimiter)`：命中 → `nSegLen := 命中位-1`，`nCursor := nCursor + nSegLen + nDelimLen`；未命中 → `nSegLen := nFrameLen - nCursor + 1`，`nCursor := nFrameLen + 1`。
- 空段：`nSegLen = 0` → `sToken := ''`、`bValidToken := FALSE`、码 `013A`（信息级：连续分隔符，**仍占一个序号**，保证字段序号对齐——这是本件最重要的语义，写进头注释）。
- 截断：`nSegLen > nMaxLenUse` → `sToken := LEFT(seg, nMaxLenUse)`、码 `013B`。
- 段数上限：`nTokenCount >= nMaxTokUse` 且仍有剩余 → `eFault` + `021D`（帧结构异常，继续解析会把内存边界打穿）。

**边界与防错**

- 分隔符空 → `021C`，绝不进 `FIND`（`FIND` 空串行为跨平台不一致）。
- 段数上限 → `021D` 故障锁存；段长上限 → 截断 + 信息码（不锁存，现场宁可读到半段）。
- 帧中途被调用方改写：以「`sFrame` 与 `sFrameLatched` 逐字符不等」为唯一重装载判据，不使用 `LEN` 差值（等长改写会被漏判）。
- `bNext` 在 `bDone` 之后再按 → `nTokenIdx` 不回绕、`sToken` 保持空、`bDone` 保持 TRUE，码 `013C`。
- `ELSE` 兜底（枚举被在线改坏/跨版本不兼容）→ `eFault` + `021E`，同时把游标置 `nFrameLen + 1`，防止下一拍从中间继续解析。
- 全部输出在 `eEnable = FALSE` 时冻结（**不清零**，避免 HMI 上字段瞬间空白）。

**验收向量**

- V1：`sFrame='A,,C'`、`sDelimiter=','`；第 1 次 `bNext` → `sToken='A'`、`nTokenIdx=1`、`bValidToken=TRUE`；第 2 次 → `sToken=''`、`nTokenIdx=2`、`bValidToken=FALSE`、`uErrorId=16#0001_013A`；第 3 次 → `sToken='C'`、`nTokenIdx=3`；第 4 次 → `bDone=TRUE`。
- V2：`sFrame='12.5;OK'`、`sDelimiter=';'` → 两次取段得 `'12.5'`、`'OK'`，`nTokenCount=2`，第 3 次 `bDone=TRUE`。
- V3：`sDelimiter=''` → `bError=TRUE`、`uErrorId=16#0001_021C`、不产出任何段。
- V4：`nMaxTokens=2`、帧含 3 段 → 第 3 次取段时 `bError=TRUE`、`uErrorId=16#0001_021D`。

**来源与借鉴**：`source = lgf-datahandling`。借鉴点：字符串工具「定长缓冲 + 原地操作」的参数域（LGF 的字符串族不使用动态内存）。流式状态机、空段语义、段数上限策略全自有——LGF 无流式分词器。

---

### 3.8 `FC_DL_SolarPositionCalc`（DL_MathData，FC，复杂度 7，源：lgf-datetimer）

**功能定义**：由日期时间、纬度、经度与 UTC 偏移计算太阳赤纬、时角、高度角与方位角（NOAA 简化天文算法）。

**工业现场痛点**：光伏跟踪支架的逆跟踪、建筑遮阳、日光温室补光都需要「此刻太阳在哪」；LGF 的天文钟族在 ST 生态里几乎没有可移植实现，现场要么买专用控制器，要么写死一张时角表（每季度手工更新，跨纬度项目全部重做）。

**引脚规格**

`VAR_INPUT`
- `nYear : INT;` // 年 [年]，域 1970~2100 / Year, 1970..2100
- `nMonth : INT;` // 月 [月]，域 1~12 / Month, 1..12
- `nDay : INT;` // 日 [日]，域 1~31（按当月实际天数校验） / Day, 1..31
- `nHour : INT;` // 时 [h]，域 0~23（本地标准时） / Hour, local standard time
- `nMinute : INT;` // 分 [min]，域 0~59 / Minute
- `fLatitude : REAL;` // 纬度 [°]，北纬正，域 −90~90 / Latitude in degrees, north positive
- `fLongitude : REAL;` // 经度 [°]，东经正，域 −180~180 / Longitude in degrees, east positive
- `nUtcOffsetMin : INT := 480;` // 本地时区偏移 [min]，东八区 = 480 / Time zone offset in minutes

`VAR_OUTPUT`
- `fDeclination : REAL;` // 太阳赤纬 [°]，域约 −23.45~+23.45 / Solar declination in degrees
- `fHourAngle : REAL;` // 时角 [°]，正午为 0，下午为正 / Hour angle in degrees
- `fElevation : REAL;` // 太阳高度角 [°]，地平线上为正 / Solar elevation in degrees
- `fAzimuth : REAL;` // 方位角 [°]，正北 0、顺时针增（东 90、南 180、西 270） / Azimuth in degrees clockwise from north
- `fEquationOfTime : REAL;` // 均时差 [min] / Equation of time in minutes
- `bSunUp : BOOL;` // 高度角 > 0 TRUE / Sun above the horizon
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `bValid : BOOL;` // 日期与时区与经纬度均合法 / Inputs legal

`VAR`（内部）
- `nDoy : INT;` // 年内日序，1 = 1 月 1 日 [日] / Day of year
- `fGamma : REAL;` // 小数年角 [rad] / Fractional year angle in radians
- `fDeclRad : REAL;` // 赤纬 [rad] / Declination in radians
- `fEotMin : REAL;` // 均时差 [min] / Equation of time
- `fTstMin : REAL;` // 真太阳时 [min] / True solar time in minutes
- `fHaDeg : REAL;` // 时角 [°] / Hour angle in degrees
- `fLatRad : REAL;` // 纬度 [rad] / Latitude in radians
- `fSinElev : REAL;` // 高度角正弦中间量 [-] / Sine of elevation
- `fCosElev : REAL;` // 高度角余弦中间量 [-] / Cosine of elevation
- `fY : REAL;` // 方位角 atan2 的 y 分量 [-] / Azimuth atan2 numerator
- `fX : REAL;` // 方位角 atan2 的 x 分量 [-] / Azimuth atan2 denominator
- `fAzRad : REAL;` // 方位角 [rad] / Azimuth in radians
- `nDayMax : INT;` // 当月天数 [日] / Days in the month
- `bLeap : BOOL;` // 闰年标志 / Leap year flag
- `i : INT;` // 日序累加索引 [月] / Month accumulation index
- `nGuard : DINT;` // 守卫 / Loop guard

`VAR CONSTANT`
- `DL_RAD2DEG : REAL := 57.29577951;` // 弧度转度 [°] / Radians to degrees
- `DL_DEG2RAD : REAL := 0.01745329;` // 度转弧度 [rad] / Degrees to radians
- `DL_PI : REAL := 3.14159265;` // 圆周率 [-] / Pi
- `DL_DAYS_YEAR : REAL := 365.0;` // 平年天数 [日] / Days in a common year
- `DL_TWO_PI : REAL := 6.28318531;` // 2π [rad] / Two pi
- `DL_GUARD_MAX : DINT := 16;` // 守卫上限 / Guard limit

**算法要点**

1. 输入闸门：年月日时分范围；日按当月天数（闰年 4/100/400 三级判定）；`ABS(fLatitude) > 90.0` 或 `ABS(fLongitude) > 180.0` 或 `ABS(nUtcOffsetMin) > 840` → `bValid := FALSE` + `0136`，早退。
2. 日序：`nDoy` 用 `FOR i := 1 TO nMonth-1` 累加当月天数再 `+ nDay`（带守卫；不用查表常量数组，避免 12 元素数组在不同平台的初始化差异）。
3. 小数年角：`fGamma := DL_TWO_PI / DL_DAYS_YEAR * (INT_TO_REAL(nDoy - 1) + (INT_TO_REAL(nHour) - 12.0) / 24.0)`。
4. 赤纬（NOAA 傅里叶展开）：`fDeclRad := 0.006918 - 0.399912*COS(γ) + 0.070257*SIN(γ) - 0.006758*COS(2γ) + 0.000907*SIN(2γ) - 0.002697*COS(3γ) + 0.00148*SIN(3γ)`；`fDeclination := fDeclRad * DL_RAD2DEG`。
5. 均时差：`fEotMin := 229.18 * (0.000075 + 0.001868*COS(γ) - 0.032077*SIN(γ) - 0.014615*COS(2γ) - 0.040849*SIN(2γ))`。
6. 真太阳时：`fTstMin := INT_TO_REAL(nHour*60 + nMinute) + fEotMin + 4.0*fLongitude - INT_TO_REAL(nUtcOffsetMin)`；`fHaDeg := 15.0 * (fTstMin / 60.0 - 12.0)`；归一到 −180~+180（用条件加减，**禁用 MOD**）。
7. 高度角：`fSinElev := SIN(fLatRad)*SIN(fDeclRad) + COS(fLatRad)*COS(fDeclRad)*COS(fHaDeg*DL_DEG2RAD)`；钳位到 −1.0~1.0（防 `ASIN` 域外）；`fElevation := ASIN(fSinElev) * DL_RAD2DEG`。
8. 方位角：`fY := SIN(fHaDeg*DL_DEG2RAD)`；`fX := COS(fHaDeg*DL_DEG2RAD)*SIN(fLatRad) - TAN(fDeclRad)*COS(fLatRad)`；`fAzRad := ATAN2(fY, fX)`；`fAzimuth := fAzRad*DL_RAD2DEG + 180.0`；归一到 0~360（条件加减）。
9. 天顶不可辨：`fElevation > 89.5` 时方位角无物理意义，按本库约定置 `fAzimuth := 180.0`（正南）并在头注释写死该约定。
10. `bSunUp := fElevation > 0.0`。
11. `TAN(fDeclRad)` 的域安全：赤纬最大 ±23.45°，`TAN` 不会发散，但须在注释说明「不可把本式复用到高赤纬场景」。

**边界与防错**

- `SIN/COS` 入参先转 rad；`ASIN` 入参钳位 ±1.0（浮点误差可能给出 1.0000001，直接 `ASIN` 会返回 NaN）。
- 时角归一无 `MOD`（负数取余跨平台不一致），用 `WHILE` 条件加减带守卫（≤ 2 次）。
- 经纬度与日期域外一律早退，不返回「看似合理」的错值。
- 全部输出在早退分支预置 0.0 / FALSE。

**验收向量**

- V1：`2026-03-20 12:00`、`fLatitude=0.0`、`fLongitude=0.0`、`nUtcOffsetMin=0` → `nDoy=79`，γ=1.3425 rad；赤纬 ≈ −0.45°、均时差 ≈ −8.2 min、真太阳时 ≈ 711.8 min、时角 ≈ −2.04°；期望 `fElevation≈87.9`（±0.8）、`fAzimuth≈102.5`（±1.5）、`bSunUp=TRUE`、`bValid=TRUE`。
- V2：`2026-12-21 12:00`、`fLatitude=45.0`、`fLongitude=0.0`、`nUtcOffsetMin=0` → 赤纬 ≈ −23.42°、时角 ≈ 0.54°；期望 `fElevation≈21.6`（±0.5，解析校验：90 − 45 − 23.42 = 21.58）、`fAzimuth≈180.5`（±2.0）。
- V3：`2026-12-21 12:00`、`fLatitude=80.0` → `fElevation≈−13.4`（±0.6）、`bSunUp=FALSE`（极夜）。
- V4：`fLatitude=95.0` → `bValid=FALSE`、`uErrorId=16#0001_0136`、全部角度输出 0.0。
- V5：`nMonth=2`、`nDay=30` → `bValid=FALSE`、`0137`（当月天数非法）。

**来源与借鉴**：`source = lgf-datetimer`。借鉴点：LGF「Date and Timer」组把「日历天数/周数、天文钟、多段定时」并列的分类骨架，以及天文钟「由本地时间 + 经纬度求太阳位置」的参数域（日期时间 + 地理位置）。全部公式取 NOAA 公开算法，实现、常量、归一策略自有。

---

### 3.9 `FC_DL_ModbusExceptionParse`（DL_MathData，FC，复杂度 3，源：oscat-network）

**功能定义**：解析 Modbus 异常响应帧（功能码 bit7 置位 + 异常码），输出原始功能码、异常码中文名、严重度与可重试标志。

**工业现场痛点**：从站回 `0x83 / 0x02`（非法数据地址）与 `0x86 / 0x06`（从站忙）在通讯层都只表现为「事务失败」，但前者是组态错（改代码）、后者重试即可；现场一律当「通讯不稳」处理，反复重启总线。OSCAT Network 的诊断帧解析族就是为消除这层歧义。

**引脚规格**

`VAR_INPUT`
- `uFuncCode : USINT;` // 响应功能码原值，bit7 置位表示异常帧 / Raw response function code, bit7 set means exception
- `uExcCode : USINT;` // 异常码，仅异常帧有效 / Exception code, valid only on exception frames

`VAR_OUTPUT`
- `bIsException : BOOL;` // 是异常帧 TRUE / Exception frame detected
- `nOrigFunc : INT;` // 原始功能码（去 bit7），0 = 非法 / Original function code without bit7
- `sExcName : STRING(40);` // 异常码中文名，未定义码为「未定义异常码」 / Chinese name of the exception code
- `eSeverity : E_DL_ModbusExcSeverity;` // 严重度分级 [-] / Severity class
- `bRetryable : BOOL;` // 可原样重试 TRUE / Safe to retry unchanged
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `bValid : BOOL;` // 帧结构可解释 = TRUE / Frame interpretable

`VAR`（内部）
- `uFunc : USINT;` // 功能码快照 / Function code snapshot
- `uExc : USINT;` // 异常码快照 / Exception code snapshot
- `nOrig : INT;` // 原始功能码中间量 / Original code temporary

`VAR CONSTANT`
- `DL_MB_EXC_BIT : USINT := 16#80;` // 异常标志位 [位串] / Exception flag bit
- `DL_MB_FUNC_MASK : USINT := 16#7F;` // 功能码掩码 [位串] / Function code mask
- `DL_MB_EXC_MAX : USINT := 16#0B;` // 已定义异常码上限 [代码] / Highest defined exception code

**算法要点**

1. 预置输出（`bIsException=FALSE`、`nOrigFunc=0`、`sExcName=''`、`eSeverity=eInfo`、`bRetryable=FALSE`、`bValid=FALSE`）。
2. 异常帧判定：`bIsException := (uFuncCode AND DL_MB_EXC_BIT) <> 0`。
3. 原始功能码：`nOrigFunc := USINT_TO_INT(uFuncCode AND DL_MB_FUNC_MASK)`；`nOrigFunc = 0` → `bValid := FALSE` + `0138`（功能码非法）。
4. 非异常帧：`bIsException = FALSE` → `bValid := TRUE`、`eSeverity := eInfo`、`sExcName := '正常响应'`，码 `0139`（信息级：本帧不是异常帧），早退。
5. 异常码映射（Modbus 应用协议规范公开定义，中文名自有）：
   - `16#01` 非法功能 → `eFault`，不可重试
   - `16#02` 非法数据地址 → `eFault`，不可重试
   - `16#03` 非法数据值 → `eFault`，不可重试
   - `16#04` 从站设备故障 → `eFault`，可重试（1 次后应报警）
   - `16#05` 确认（处理中）→ `eWarn`，可重试
   - `16#06` 从站设备忙 → `eWarn`，可重试
   - `16#08` 存储奇偶校验错 → `eFault`，不可重试
   - `16#0A` 网关路径不可用 → `eWarn`，可重试
   - `16#0B` 网关目标设备无响应 → `eWarn`，可重试
   - 其它（含 `16#00`、`16#07`、`16#09`、`> 0x0B`）→ `sExcName='未定义异常码'`、`eSeverity=eFault`、不可重试、`bValid=FALSE`、码 `0138`
6. 全部为 `CASE` 分支，`ELSE` 兜底走未定义分支（**不允许**漏 `ELSE`）。

**边界与防错**

- 无算术、无除法、无循环，无溢出面。
- `uFuncCode = 0` 与 `> 0x7F` 的功能码一律按非法处理（`nOrigFunc=0`）。
- 未定义异常码不算「解析成功」：`bValid=FALSE` 但 `sExcName` 仍给出文字，便于 HMI 直接显示。
- 本件只解析不决策：是否重试由 `FB_DL_ModbusPollMaster` 的 `uMaxRetry` 决定，头注释写明边界。

**验收向量**

- V1：`uFuncCode=16#83`、`uExcCode=16#02` → `bIsException=TRUE`、`nOrigFunc=3`、`sExcName='非法数据地址'`、`eSeverity=eFault`、`bRetryable=FALSE`、`bValid=TRUE`。
- V2：`uFuncCode=16#86`、`uExcCode=16#06` → `nOrigFunc=6`、`sExcName='从站设备忙'`、`eSeverity=eWarn`、`bRetryable=TRUE`。
- V3：`uFuncCode=16#03`（正常响应）→ `bIsException=FALSE`、`nOrigFunc=3`、`sExcName='正常响应'`、`uErrorId=16#0001_0139`。
- V4：`uFuncCode=16#83`、`uExcCode=16#07` → `sExcName='未定义异常码'`、`eSeverity=eFault`、`bValid=FALSE`、`uErrorId=16#0001_0138`。
- V5：`uFuncCode=16#80` → `bIsException=TRUE`、`nOrigFunc=0`、`bValid=FALSE`、`uErrorId=16#0001_0138`。

**来源与借鉴**：`source = oscat-network`。借鉴点：OSCAT Network 把「协议帧解析 / CRC / 诊断」分成独立函数族的分类方式，以及「函数码 + 异常码」两入参的参数域。异常码语义取自 Modbus 应用协议规范的公开定义，中文名、分级、可重试判据为自有设计。

---

### 3.10 `FC_DL_WaterEnthalpy`（DL_Algo，FC，复杂度 3，源：oscat-building）

**功能定义**：计算 0~150 °C 液态水的比焓（以 0 °C 饱和液水为基准），输出比焓与平均比热。

**工业现场痛点**：冷热量表按 `Q = m·Δh` 结算，现场若用固定 `4.186 kJ/(kg·K)`，在 70~90 °C 工况下偏差 0.5~1%，热量结算每月差出真金白银；OSCAT Building 的 `WATER_ENTHALPY` 行为定义在 ST 生态里能被直接复用的实现极少。

**引脚规格**

`VAR_INPUT`
- `fTempC : REAL := 0.0;` // 水温 [°C]，域 0~150 / Water temperature in degrees Celsius, 0..150
- `bUseMeanCp : BOOL := FALSE;` // TRUE 时额外输出平均比热（供流量温差不大的简化算法用） / Also export mean specific heat

`VAR_OUTPUT`
- `fEnthalpy : REAL;` // 比焓 [kJ/kg]，0 °C 基准 / Specific enthalpy in kilojoules per kilogram
- `fCpMean : REAL;` // 0 °C 到当前温度的平均比热 [kJ/(kg·K)] / Mean specific heat from 0 °C
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `bValid : BOOL;` // 温度在域内 TRUE / Temperature inside the domain

`VAR`（内部）
- `fT : REAL;` // 温度快照 [°C] / Temperature snapshot
- `fT2 : REAL;` // 温度平方 [°C²] / Temperature squared
- `fT3 : REAL;` // 温度立方 [°C³] / Temperature cubed
- `fH : REAL;` // 比焓中间量 [kJ/kg] / Enthalpy temporary

`VAR CONSTANT`
- `DL_H_C1 : REAL := 4.2176;` // 一次项系数 [kJ/(kg·K)] / Linear coefficient
- `DL_H_C2 : REAL := 0.000718;` // 二次项系数 [kJ/(kg·K²)] / Quadratic coefficient
- `DL_H_C3 : REAL := 0.0000047333;` // 三次项系数 [kJ/(kg·K³)] / Cubic coefficient
- `DL_T_MIN : REAL := 0.0;` // 温度下限 [°C] / Lower temperature bound
- `DL_T_MAX : REAL := 150.0;` // 温度上限 [°C] / Upper temperature bound
- `DL_T_DEN : REAL := 1.0;` // 平均比热除法的温度分母保护下限 [°C] / Denominator guard for mean cp

**算法要点**

1. 闸门：`fTempC <> fTempC`（NaN）或 `fTempC < DL_T_MIN` 或 `fTempC > DL_T_MAX` → `bValid := FALSE`、`fEnthalpy := 0.0`、码 `2101`，早退。
2. 比焓（由 `cp(T) = 4.2176 − 0.001436·T + 1.42E−5·T²` 积分得到，三点拟合 0/50/100 °C 公开饱和液水比热）：
   `fH := DL_H_C1*fT − DL_H_C2*fT2 + DL_H_C3*fT3`
3. 平均比热：`IF ABS(fT) > DL_T_DEN THEN fCpMean := fH / fT; ELSE fCpMean := DL_H_C1; END_IF`（**防除零**，0 °C 时取一次项系数）。
4. 精度声明：头注释写明「0~100 °C 与 IAPWS-IF97 饱和液焓偏差 < 0.3%，100~150 °C 偏差 < 0.8%，**不得用于蒸汽或过冷水**」。
5. 无循环、无状态。

**边界与防错**

- 域外不夹取（夹取会把 200 °C 的蒸汽按 150 °C 液水算，属静默错误），一律 `bValid := FALSE` + 码 `2101`，结果 0.0。
- 温度 0 °C 时平均比热除法防零（见算法 3）。
- `fT3` 在 150 °C 时为 3.375E6，REAL 精度足够（约 7 位有效数字），头注释说明为何不用 LREAL：与既有 `FC_DL_HumidAirEnthalpy` 保持同一精度口径。
- 码 `2102`：`bUseMeanCp=TRUE` 但温度为 0（平均比热退化为常数）——信息级，仅提示。

**验收向量**

- V1：`fTempC=100.0` → `fT2=10000`、`fT3=1000000`；`fH = 4.2176*100 − 0.000718*10000 + 0.0000047333*1000000 = 421.76 − 7.18 + 4.7333 = 419.3133`；期望 `fEnthalpy=419.31`（±0.05）、`fCpMean=4.1931`（±0.002）、`bValid=TRUE`。公开饱和液水焓 419.1 kJ/kg，偏差 0.05%。
- V2：`fTempC=20.0` → `fH = 84.352 − 0.000718*400 + 0.0000047333*8000 = 84.352 − 0.2872 + 0.03787 = 84.1027`；期望 `fEnthalpy=84.10`（±0.05）。
- V3：`fTempC=0.0` → `fEnthalpy=0.0`、`fCpMean=4.2176`、`uErrorId=16#0002_2102`。
- V4：`fTempC=160.0` → `bValid=FALSE`、`fEnthalpy=0.0`、`uErrorId=16#0002_2101`。
- V5：`fTempC=50.0` → `fH = 210.88 − 1.795 + 0.59166 = 209.6767`；期望 `fEnthalpy=209.68`（±0.05，公开值 209.3，偏差 0.18%）。

**来源与借鉴**：`source = oscat-building`。借鉴点：OSCAT Building 中 `WATER_ENTHALPY` 的**行为定义**（输入温度、输出比焓、0 °C 基准）与「物性函数单独成件、不做 MODE 分支」的切分方式。系数拟合、多项式阶数、精度声明全自有，**未复制任何函数体、常量名与注释**。

---

### 3.11 `FB_DL_ValveCharacteristic`（DL_Algo，FB，复杂度 5，源：isa88-process / 工艺参数域）

**功能定义**：把「期望流量百分比」按调节阀固有特性（线性／等百分比／快开）折算为「阀位百分比」，带可调比、行程限幅与输出死区。

**工业现场痛点**：等百分比阀若按线性给定，小流量段（<10%）分辨率不足、大流量段增益过高引起振荡；DCS 普遍有特性补偿，PLC 库几乎都缺，OEM 只能让工艺员「凭经验把给定调弯」。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时阀位保持上次输出 / Enable, holds the last travel when FALSE
- `bReset : BOOL;` // 上升沿清故障 / Rising edge clears the fault
- `fFlowCmd : REAL := 0.0;` // 期望流量 [%]，域 0~100 / Desired flow in percent, 0..100
- `eChar : E_DL_ValveCharKind := E_DL_ValveCharKind.eEqualPercent;` // 固有特性 [-] / Inherent characteristic
- `fRangeability : REAL := 30.0;` // 可调比 R [-]，域 2~100，越界钳位 / Rangeability, clamped to 2..100
- `fMinTravel : REAL := 0.0;` // 最小阀位 [%]，域 0~100 / Minimum travel
- `fMaxTravel : REAL := 100.0;` // 最大阀位 [%]，域 0~100 / Maximum travel
- `fDeadband : REAL := 0.2;` // 输出死区 [%]，变化小于此值保持上次 / Output deadband in percent

`VAR_OUTPUT`
- `fTravel : REAL;` // 阀位给定 [%]，域 fMinTravel~fMaxTravel / Travel command in percent
- `bSaturated : BOOL;` // 输出被上/下限或可调比下限截断 TRUE / Output clamped
- `bError : BOOL;` // 故障级锁存，仅 2010~2012 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_ValveCharState;` // 主状态机当前状态 / Current state

`VAR`（内部）
- `fbTrigReset : R_TRIG;` // 复位沿，CASE 外刷新 / Reset edge, refreshed outside CASE
- `ePhase : E_DL_ValveCharState := E_DL_ValveCharState.eIdle;` // 内部状态 / Internal state
- `fQ : REAL;` // 归一化流量 [0~1] / Normalised flow
- `fR : REAL;` // 生效可调比 [-] / Effective rangeability
- `fRaw : REAL;` // 未限幅的阀位 [%] / Unlimited travel
- `fLast : REAL;` // 上次输出阀位 [%] / Last travel command
- `fLoTravel : REAL;` // 生效下限 [%] / Effective lower bound
- `fHiTravel : REAL;` // 生效上限 [%] / Effective upper bound
- `fQMin : REAL;` // 可调比下限对应的归一化流量 [0~1] / Normalised flow at the rangeability floor
- `bClampLo : BOOL;` // 下限截断标记 / Lower clamp flag
- `bClampHi : BOOL;` // 上限截断标记 / Upper clamp flag

`VAR CONSTANT`
- `DL_PCT_MAX : REAL := 100.0;` // 百分比满量程 [%] / Percent full scale
- `DL_R_MIN : REAL := 2.0;` // 可调比下限 [-] / Minimum rangeability
- `DL_R_MAX : REAL := 100.0;` // 可调比上限 [-] / Maximum rangeability
- `DL_EPS : REAL := 1.0E-6;` // 浮点判等容差 / Float comparison epsilon

**算法要点**

- 状态机（`E_DL_ValveCharState` 三成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0002_2012`）：
  - `eIdle`：`bEnable` 后校验行程上下限（`fMinTravel > fMaxTravel` → `eFault` + `2010`），合法转 `eActive`。
  - `eActive`：按特性折算 → 限幅 → 死区 → 输出。
  - `eFault`：输出保持 `fLast`；`bReset` 上升沿回 `eIdle`。
- 特性折算：
  - `eLinear`：`fRaw := fQ * 100.0`
  - `eEqualPercent`：`fQMin := 1.0 / fR`；`IF fQ <= fQMin THEN fRaw := 0.0; bClampLo := TRUE; ELSE fRaw := 100.0 * (1.0 + LN(fQ) / LN(fR)); END_IF`（`LN(fR)` 在 `fR >= 2` 时恒 > 0，**无除零面**）
  - `eQuickOpen`：`fRaw := 100.0 * (1.0 - SQRT(1.0 - fQ))`（`fQ <= 1` 保证 `SQRT` 域内）
- 限幅：`fRaw := MIN(MAX(fRaw, fLoTravel), fHiTravel)`；截断时 `bSaturated := TRUE` 并置信息码 `2001`（下限）/ `2002`（上限）。
- 死区：`IF ABS(fRaw - fLast) < fDeadband THEN fTravel := fLast; 码 2003; ELSE fTravel := fRaw; fLast := fRaw; END_IF`（**死区只压输出抖动，不改变内部限幅结果**，头注释写死）。
- 输入域：`fFlowCmd` 钳 0~100（码 `2004`）；`fRangeability` 钳 2~100（码 `2005`）；`fDeadband` 取绝对值并钳 ≤ 5.0（码 `2006`）。

**边界与防错**

- `LN(fR)` 除零面已在域内消除（`fR >= 2`），仍保留 `IF ABS(LN(fR)) < DL_EPS` 的二次守卫 → 码 `2011` 故障（防线冗余，防调用方绕过钳位）。
- 快开特性 `1 - fQ` 可能因浮点略小于 0 → 先 `MAX(0.0, 1.0 - fQ)` 再 `SQRT`。
- `fMinTravel > fMaxTravel` → 故障 `2010`，输出保持上次，不交换上下限（交换会掩盖组态错误）。
- 掉使能保持上次输出（阀位突跳比保持更危险），头注释写明「本件不做阀位回零，回零由上层安全逻辑负责」。
- `ELSE` 兜底 → `eFault` + `2012`，输出保持 `fLast`，等待 `bReset`。
- 死区比较用 `ABS(diff) < fDeadband`，不用 `=`。

**验收向量**

- V1：`eChar=eEqualPercent`、`fRangeability=30.0`、`fFlowCmd=50.0` → `fQ=0.5`；`fRaw = 100*(1 + LN(0.5)/LN(30)) = 100*(1 + (−0.693147)/3.401197) = 100*(1 − 0.203795) = 79.62`；期望 `fTravel≈79.6`（±0.1）、`bSaturated=FALSE`。
- V2：`eChar=eLinear`、`fFlowCmd=50.0` → `fTravel=50.0`。
- V3：`eChar=eQuickOpen`、`fFlowCmd=75.0` → `fRaw = 100*(1 − SQRT(0.25)) = 50.0`；期望 `fTravel=50.0`。
- V4：`eEqualPercent`、`fRangeability=30.0`、`fFlowCmd=2.0` → `fQ=0.02 < 1/30=0.0333` → `fTravel=0.0`、`bSaturated=TRUE`、`uErrorId=16#0002_2001`。
- V5：`fMinTravel=60.0`、`fMaxTravel=40.0` → `bError=TRUE`、`uErrorId=16#0002_2010`、`fTravel` 保持上次。

**来源与借鉴**：`source = isa88-process`（工艺参数域借自 ISA-88 批次设备「阀特性」参数化惯例与 LBP 阀门控制族的分层）。借鉴点：把「特性」做成**枚举参数域**而不是三个独立块（此处与 LGF 的「一变体一块」教条有意不同，理由：三种特性共用同一限幅/死区/状态机，拆开会产生三份重复代码，且特性切换在配方里是运行期行为）。公式全部取自公开的调节阀流量特性定义，实现自有。

---

### 3.12 `FB_DL_DeviceParamVerify`（DL_Device，FB，复杂度 6，源：codesys-forge-devicereader）

**功能定义**：把「组态期望参数块」与「设备回读参数块」逐项按逐项容差比对，给出差异项数、首差下标、最大偏差与「一致/不一致/未就绪」结论，不一致结论锁存并需显式确认。

**工业现场痛点**：伺服/变频器换板、参数被误改后设备以错误参数运行，现场靠人翻参数页逐项核对几十项；上电自动核对能把「参数被改」从「偶发工艺异常」变成「一条明确报警」。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时结论冻结 / Enable, freezes the verdict when FALSE
- `bReset : BOOL;` // 上升沿复位故障与结论锁存 / Rising edge clears fault and verdict latch
- `bAcknowledge : BOOL;` // 上升沿确认「不一致」结论，清 bMismatch / Rising edge acknowledges a mismatch
- `nItemCount : INT := 1;` // 比对本数 [项]，域 1~64 / Item count, 1..64
- `afExpected : ARRAY[1..64] OF REAL;` // 组态期望块 / Configured expectation block
- `afActual : ARRAY[1..64] OF REAL;` // 设备回读块 / Device readback block
- `afTolerance : ARRAY[1..64] OF REAL;` // 逐项容差 [工程单位]，0 或负值回落到 fDefaultTol / Per-item tolerance, falls back to the default
- `fDefaultTol : REAL := 0.01;` // 默认容差 [工程单位]，域 >= 1E-6 / Default tolerance
- `tVerifyTimeout : TIME := T#5S;` // 回读超时 [ms/s]，0 表示不监控 / Readback timeout, zero disables

`VAR_OUTPUT`
- `bVerified : BOOL;` // 全部项在容差内 TRUE / All items within tolerance
- `bMismatch : BOOL;` // 不一致结论锁存，需 bAcknowledge / Mismatch latched until acknowledged
- `nDiffCount : INT;` // 超差项数 [项] / Out-of-tolerance item count
- `nFirstDiffIdx : INT;` // 首个超差项下标，0 = 无 [索引] / First offending index, zero when none
- `fMaxDev : REAL;` // 最大绝对偏差 [工程单位] / Maximum absolute deviation
- `nMaxDevIdx : INT;` // 最大偏差下标 / Index of the maximum deviation
- `bError : BOOL;` // 故障级锁存，仅 030D~030F 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_ParamVerifyPhase;` // 主状态机当前相位 / Current phase

`VAR_IN_OUT`
- `stVerify : ST_DL_ParamVerifyState;` // 跨周期状态：上次结论与累计核对次数 / Persistent state, last verdict and counter

`VAR`（内部）
- `fbTrigReset : R_TRIG;` // 复位沿，CASE 外刷新 / Reset edge
- `fbTrigAck : R_TRIG;` // 确认沿，CASE 外刷新 / Acknowledge edge
- `fbTimeout : TON;` // 回读超时，CASE 外刷新 / Readback timeout timer
- `ePhase : E_DL_ParamVerifyPhase := E_DL_ParamVerifyPhase.eIdle;` // 内部相位 / Internal phase
- `bInit : BOOL := FALSE;` // 首扫标志 / First-scan flag
- `nCountUse : INT;` // 生效项数 [项] / Effective item count
- `fTolUse : REAL;` // 单项生效容差 [工程单位] / Per-item effective tolerance
- `fDev : REAL;` // 单项偏差 [工程单位] / Per-item deviation
- `fExp : REAL;` // 期望值快照 / Expected snapshot
- `fAct : REAL;` // 回读值快照 / Actual snapshot
- `bNonFinite : BOOL;` // 出现非有限值 / Non-finite encountered
- `nGuard : DINT;` // 守卫 / Loop guard
- `i : INT;` // 遍历索引 / Loop index

`VAR CONSTANT`
- `DL_ITEM_MAX : INT := 64;` // 项数上限 [项] / Item count limit
- `DL_TOL_MIN : REAL := 1.0E-6;` // 最小容差 [工程单位] / Minimum tolerance
- `DL_GUARD_MAX : DINT := 128;` // 守卫上限 / Guard limit

**算法要点**

- 状态机（`E_DL_ParamVerifyPhase` 六成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0003_030F`）：
  - `eIdle`：`bEnable` 后钳位参数（越界 → `014D`），转 `eWaiting`。
  - `eWaiting`：`fbTimeout` 计时；超时且未收到回读（`afActual` 全 0 视为未就绪，头注释写明该约定）→ `eFault` + `030E`。
  - `eComparing`：单循环逐项比对 → 得 `nDiffCount` / `nFirstDiffIdx` / `fMaxDev` → 转 `eMatch` 或 `eMismatch`。
  - `eMatch`：`bVerified := TRUE`、`bMismatch := FALSE`、`stVerify.bLastVerdict := TRUE`、`stVerify.uVerifyCount++`，码 `014E`（一致）。
  - `eMismatch`：`bMismatch := TRUE`、`bVerified := FALSE`，锁存结论与明细；`bAcknowledge` 上升沿 → 回 `eIdle`（**锁存清除但历史记录保留**）。
  - `eFault`：`bError := TRUE`；`bReset` 上升沿回 `eIdle`。
- 逐项容差：`fTolUse := afTolerance[i]`；`IF fTolUse <= 0.0 THEN fTolUse := fDefaultTol; END_IF`；`fTolUse := MAX(ABS(fTolUse), DL_TOL_MIN)`；负容差取绝对值的动作置信息码 `014F`。
- 非有限值：任一为 NaN/Inf → 该项计超差，`fMaxDev` 不参与竞争，`bNonFinite := TRUE`，码 `030D`（故障级：设备回读出现非有限值说明数据源已坏）。
- 与 `FC_DL_ArrayDiffSummary` 的边界：那个件是**统一容差**的通用双数组比对；本件是**逐项容差 + 结论锁存 + 回读超时**的设备参数域件，**不得**内联另一件的循环逻辑两次（本件不复用该 FC，是因为复用会导致逐项容差需要拆成 64 次函数调用，破坏单拍一致性）。此理由必须写进头注释。

**边界与防错**

- `nItemCount` 钳 1~64，越界 `014D` 信息级。
- 回读超时只在 `eWaiting` 期间计时，`TON` 主周期无条件刷新（`IN := (ePhase = eWaiting)`）。
- 结论锁存与「当前值」分离：`bMismatch` 锁存，`nDiffCount` / `fMaxDev` 每拍重算（HMI 能看到「已确认的旧结论」与「当前实时差异」两套信息）。
- `bEnable = FALSE` 时不推进状态、不改结论，输出保持。
- 首扫 `bInit = FALSE` 时不做任何比对（避免未初始化的 `afActual` 全 0 直接判不一致）。

**验收向量**

- V1：`nItemCount=3`、`afExpected=[100.0, 0.5, 1.0]`、`afActual=[100.0, 0.5, 1.0]`、`afTolerance=[0.1, 0.01, 0.001]` → `bVerified=TRUE`、`bMismatch=FALSE`、`nDiffCount=0`、`nFirstDiffIdx=0`、`fMaxDev=0.0`。
- V2：`afActual=[100.0, 0.62, 1.0]` → 第 2 项偏差 0.12 > 0.01 → `bMismatch=TRUE`、`nDiffCount=1`、`nFirstDiffIdx=2`、`fMaxDev=0.12`、`nMaxDevIdx=2`。
- V3：`afTolerance[2]=0.0`、`fDefaultTol=0.2`、`afActual[2]=0.62` → 回落默认容差，偏差 0.12 ≤ 0.2 → `bVerified=TRUE`、`nDiffCount=0`。
- V4：`afActual[1]` 置 NaN → `bError=TRUE`、`uErrorId=16#0003_030D`、`bVerified=FALSE`。
- V5：`tVerifyTimeout=1S` 且 `afActual` 全 0 → `bError=TRUE`、`uErrorId=16#0003_030E`。

**来源与借鉴**：`source = codesys-forge-devicereader`。借鉴点：CODESYS Forge `DeviceReader` 类示例把「设备参数读出 → 与工程组态比对 → 差异报告」组织成独立功能域的**参数域与流程骨架**（读、比、判三段）。状态机、逐项容差、结论锁存、码位全自有；该示例页面未显式声明许可，按最严口径处置——**零代码行复制**。

---

### 3.13 `FB_DL_PortDiagBoard`（DL_Device，FB，复杂度 6，源：plcnext-diag + roadmap-p0）

**功能定义**：把最多 4 个端口诊断聚合组（每组最多 8 端口）汇总为一张看板：总故障端口数、全局首出端口（组号 + 端口号 + 诊断码）、各组掩码，以及按「组号→端口号」稳定排序的前 3 个待修端口。

**工业现场痛点**：32 端口远程 IO 机架或交换机，HMI 上要回答两个问题——「现在还有几个端口坏」和「先修哪一个」；现状是逐个翻诊断页，首出定位靠人眼比对时间戳，交接班必丢信息。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时掩码清零、首出保持 / Enable
- `bReset : BOOL;` // 上升沿清首出锁存（清在仲裁之后，故复位当拍首出为空） / Rising edge clears the first-out latch
- `nGroupCount : INT := 1;` // 聚合组数 [组]，域 1~4 / Group count, 1..4
- `anGroupFaultMask : ARRAY[1..4] OF WORD;` // 各组端口故障掩码，位 n−1 = 端口 n / Per-group fault masks
- `anGroupPortCount : ARRAY[1..4] OF INT;` // 各组实际端口数 [个]，域 1~8 / Ports per group
- `anGroupFirstPort : ARRAY[1..4] OF INT;` // 各组内首出端口号，0 = 无 / Per-group first port
- `auGroupFirstCode : ARRAY[1..4] OF UDINT;` // 各组内首出诊断码 / Per-group first code

`VAR_OUTPUT`
- `nTotalFaultPort : INT;` // 全局故障端口总数 [个] / Total faulted ports
- `nFirstGroup : INT;` // 全局首出组号，0 = 无 / Global first-out group
- `nFirstPort : INT;` // 全局首出端口号，0 = 无 / Global first-out port
- `uFirstCode : UDINT;` // 全局首出诊断码 / Global first-out code
- `anGroupMaskOut : ARRAY[1..4] OF WORD;` // 屏蔽超界位后的各组掩码 / Sanitised per-group masks
- `anTopPortNo : ARRAY[1..3] OF INT;` // 待修端口号（按组内偏移编码：组号×10+端口号），0 = 空位 / Top repair ports, group times ten plus port
- `auTopPortCode : ARRAY[1..3] OF UDINT;` // 待修端口对应诊断码 / Codes of the top repair ports
- `bAnyFault : BOOL;` // 总故障数 > 0 / Any faulted port
- `bError : BOOL;` // 故障级锁存，仅 0309~030C 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_BoardPhase;` // 主状态机当前状态 / Current state

`VAR_IN_OUT`
- `stBoard : ST_DL_BoardState;` // 跨周期：首出锁存与上次掩码 / Persistent first-out latch and previous masks

`VAR`（内部）
- `fbTrigReset : R_TRIG;` // 复位沿，CASE 外刷新 / Reset edge
- `ePhase : E_DL_BoardPhase := E_DL_BoardPhase.eIdle;` // 内部状态 / Internal state
- `nGroupUse : INT;` // 生效组数 [组] / Effective group count
- `auPortCntUse : ARRAY[1..4] OF INT;` // 生效端口数 [个] / Effective port counts
- `uBuildMask : WORD;` // 屏蔽后掩码装配 / Sanitised mask under assembly
- `nTotal : INT;` // 故障计数累加 / Fault counter
- `nBitScan : INT;` // 位扫描索引 / Bit scan index
- `nScanGroup : INT;` // 仲裁扫描组号 / Arbitration group index
- `nScanPort : INT;` // 仲裁扫描端口号 / Arbitration port index
- `bFound : BOOL;` // 仲裁命中 / Arbitration hit
- `nTopCount : INT;` // 已填待修位 [个] / Filled top slots
- `nGuard : DINT;` // 守卫 / Loop guard
- `g : INT;` // 组循环索引 / Group loop index
- `p : INT;` // 端口循环索引 / Port loop index
- `bMaskClamped : BOOL;` // 掩码有超界位被屏蔽 / Mask bits were suppressed
- `bPortClamped : BOOL;` // 端口数被钳位 / Port count clamped

`VAR CONSTANT`
- `DL_GROUP_MAX : INT := 4;` // 组数上限 [组] / Group count limit
- `DL_PORT_MAX : INT := 8;` // 组内端口上限 [个] / Ports per group limit
- `DL_TOP_N : INT := 3;` // 待修输出位数 [个] / Top repair output slots
- `DL_GROUP_STRIDE : INT := 10;` // 端口编码步长（组号×10+端口号） / Encoding stride
- `DL_GUARD_MAX : DINT := 64;` // 守卫上限 / Guard limit

**算法要点**

- 状态机（`E_DL_BoardPhase` 三成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0003_030C`）：
  - `eIdle`：`bEnable` 后钳位组数（<1 → 1 且码 `0309`；>4 → 4 且码 `0149`）、逐组钳位端口数（<1 或 >8 → 钳位 + 码 `014A`），转 `eScanning`。
  - `eScanning`：三次遍历——① 屏蔽超界位并统计总故障数；② 首出仲裁（仅当 `NOT stBoard.bLatchValid` 时锁存，取「组号最小 → 端口号最小」的字典序）；③ 填 Top3（同一字典序，取前 3）。填完回 `eIdle` 的下一拍继续（无长驻态）。
  - `eFault`：输出保持；`bReset` 上升沿回 `eIdle`。
- 掩码屏蔽：`uBuildMask := anGroupFaultMask[g]`；`FOR p := anPortCntUse[g]+1 TO DL_PORT_MAX` 逐位清零（超界位置信息码 `014B`，**不当作故障**——掩码比端口数长是组态常见现象，不是错误）。
- 位计数：逐端口判 `(uBuildMask AND SHL(WORD#1, p-1)) <> 0`，避开 WORD 位宽边界（p 最大 8，`1..8` 安全）。
- 首出仲裁三律（与 R11 `PortDiagAggregator` 同口径，**必须逐字遵守**）：① 仅在 `NOT stBoard.bLatchValid` 时仲裁；② 同拍多个故障取组号最小、再取端口号最小；③ 复位在仲裁之后执行，故复位当拍首出为空、下一拍重新仲裁。
- Top3：按 `(组号, 端口号)` 升序填，编码 `组号*10 + 端口号`；不足 3 个的空位填 0；诊断码取 `auGroupFirstCode[g]`（组内首出码代表该组，**不逐端口另查**，因端口级明细已由 `PortDiagAggregator` 承担）。

**边界与防错**

- 组数钳位属信息级（`0149`），端口数越界属故障级（`030A`）——区别：组数是「要不要显示」，端口数是「掩码含义是否可信」。
- 掩码超界位一律屏蔽并置 `014B`，绝不把「不存在的端口」计入故障总数（否则 HMI 上会出现幽灵端口）。
- `stBoard.anLastMask` 记录上次掩码，用于 `030B`（掩码位跳变风暴：单拍变化位数 > 8 判为组态刷新，仅提示不锁存）。
- `bEnable = FALSE`：`anGroupMaskOut` 清零、`nTotalFaultPort := 0`、`bAnyFault := FALSE`，但首出锁存**保持**（掉使能不清诊断证据）。
- 三层数据源分账（模块级 / 端口级 / 参数对象级）已在 R11 收口，本件只消费端口级，**不得**再去读模块级状态字。

**验收向量**

- V1：`nGroupCount=1`、`anGroupPortCount[1]=8`、`anGroupFaultMask[1]=16#0101` → bit8 对应端口 9，超出 8 → 屏蔽；期望 `anGroupMaskOut[1]=16#0001`、`nTotalFaultPort=1`、`nFirstGroup=1`、`nFirstPort=1`、`uErrorId=16#0003_014B`。
- V2：`nGroupCount=2`、两组端口数均 8、`anGroupFaultMask[1]=16#0004`（端口 3）、`anGroupFaultMask[2]=16#0003`（端口 1、2）→ `nTotalFaultPort=3`、`nFirstGroup=1`、`nFirstPort=3`、`anTopPortNo=[13, 21, 22]`（编码 1×10+3、2×10+1、2×10+2）。
- V3：参数与 V2 相同，`bReset` 上升沿当拍 → `nFirstGroup=0`、`nFirstPort=0`（复位在仲裁之后），下一拍重新仲裁回 `1 / 3`。
- V4：`nGroupCount=0` → 钳 1，`bError=TRUE`、`uErrorId=16#0003_0309`。
- V5：`anGroupPortCount[1]=0` → 钳 1，`bError=TRUE`、`uErrorId=16#0003_030A`。

**来源与借鉴**：`source = plcnext-diag + roadmap-p0`。借鉴点：T1-7 PLCnext 的「port-based 诊断四元组（端口号/链路/诊断码/错误计数）」数据模型，以及 ROADMAP §15.3 P0 条目的「看板 + 首出」需求定义。仲裁策略、编码方式、码位全自有。

---

### 3.14 `FB_DL_EnergyMeterAccum`（DL_Device，FB，复杂度 6，源：namur-ne43 信号质量契约）

**功能定义**：按电表冻结寄存器语义拼装 32 位电能累计值，做单调性校验与换表/清零识别，并按窗口滑动计算平均需量与峰值需量。

**工业现场痛点**：Modbus 电表电能是 32 位跨两寄存器、字序厂家各异；换表或清零后累计值回退，MES 能耗报表出现负增量、月结数据作废；需量必须按窗口滑算，用瞬时功率乘时间会低估峰值。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时冻结累计 / Enable, freezes accumulation
- `bReset : BOOL;` // 上升沿清需量窗口与统计 / Rising edge resets window statistics
- `uImportHi : UINT;` // 正向有功电能高字 [LSB] / Import energy high word
- `uImportLo : UINT;` // 正向有功电能低字 [LSB] / Import energy low word
- `uExportHi : UINT;` // 反向有功电能高字 [LSB] / Export energy high word
- `uExportLo : UINT;` // 反向有功电能低字 [LSB] / Export energy low word
- `fActivePower : REAL;` // 当前有功功率 [kW] / Active power in kilowatts
- `eWordOrder : E_DL_ByteOrder := E_DL_ByteOrder.eAbcd;` // 字序约定，复用既有枚举 / Word order, reuses the existing enumeration
- `fKwhPerLsb : REAL := 0.1;` // 每个 LSB 对应电能 [kWh/LSB]，域 > 0 / Kilowatt hours per LSB
- `tDemandWindow : TIME := T#15M;` // 需量统计窗口 [ms/s/min]，域 >= 1 s / Demand window
- `fRegressRatio : REAL := 0.01;` // 判为换表的回退比例阈值 [-]，域 0~1 / Regression ratio for a meter swap
- `bFreezePulse : BOOL;` // 冻结值更新沿（电表冻结寄存器刷新） / Freeze register update pulse

`VAR_OUTPUT`
- `fImportTotal : REAL;` // 正向累计电能 [kWh] / Accumulated import energy
- `fExportTotal : REAL;` // 反向累计电能 [kWh] / Accumulated export energy
- `fNetTotal : REAL;` // 净电能 = 正向 − 反向 [kWh] / Net energy
- `fDemandAvg : REAL;` // 本窗口平均需量 [kW] / Average demand of the window
- `fDemandPeak : REAL;` // 历史峰值需量 [kW]，由 bReset 清零 / Peak demand, cleared by reset
- `fWindowEnergy : REAL;` // 本窗口累计电能 [kWh] / Energy accumulated in the window
- `bMeterReset : BOOL;` // 检测到换表/清零，单拍脉冲 / Meter swap or clear detected, one-scan pulse
- `uResetCount : UDINT;` // 换表/清零累计次数 [次] / Swap events counted
- `bError : BOOL;` // 故障级锁存，仅 0310~0312 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_MeterPhase;` // 主状态机当前状态 / Current state

`VAR_IN_OUT`
- `stMeter : ST_DL_MeterState;` // 跨周期：上次原始值、累计基准、窗口累加器 / Persistent state

`VAR`（内部）
- `fbTrigReset : R_TRIG;` // 复位沿，CASE 外刷新 / Reset edge
- `fbTrigFreeze : R_TRIG;` // 冻结沿，CASE 外刷新 / Freeze edge
- `fbWindow : TON;` // 需量窗口计时，CASE 外刷新 / Demand window timer
- `ePhase : E_DL_MeterPhase := E_DL_MeterPhase.eIdle;` // 内部状态 / Internal state
- `bInit : BOOL := FALSE;` // 首扫标志 / First-scan flag
- `uImportRaw : UDINT;` // 正向电能 32 位拼装值 [LSB] / Stitched import raw value
- `uExportRaw : UDINT;` // 反向电能 32 位拼装值 [LSB] / Stitched export raw value
- `fImportNow : REAL;` // 本次正向电能换算值 [kWh] / Converted import value
- `fExportNow : REAL;` // 本次反向电能换算值 [kWh] / Converted export value
- `fDeltaImp : REAL;` // 本拍正向增量 [kWh] / Import increment
- `tWinUse : TIME;` // 生效窗口长度 [ms/s] / Effective window
- `fRatioUse : REAL;` // 生效回退比例 [-] / Effective regression ratio
- `fWinSec : REAL;` // 窗口长度换算成秒 [s] / Window length in seconds
- `bRegress : BOOL;` // 本次读数判为回退 / Regression detected
- `bSwap : BOOL;` // 本次判定为换表/清零 / Swap detected

`VAR CONSTANT`
- `DL_LSB_MAX : UDINT := 16#FFFF_FFFF;` // 32 位满量程 [LSB] / 32-bit full scale
- `DL_DEMAND_MIN_SEC : REAL := 1.0;` // 最小窗口秒数 [s] / Minimum window in seconds
- `DL_EPS : REAL := 1.0E-6;` // 浮点容差 / Float epsilon

**算法要点**

- 状态机（`E_DL_MeterPhase` 四成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0003_0312`）：
  - `eIdle`：`bEnable` 后校验 `fKwhPerLsb > 0`（否则 `eFault` + `0310`）、`tDemandWindow >= 1 s`（否则钳位 + `0151`）、`fRegressRatio` 钳 0~1（否则 `0152`），转 `eSampling`。
  - `eSampling`：拼装 → 换算 → 增量判定 → 窗口积分 → 需量计算。
  - `eHeld`：`bEnable` 下降时冻结（不推进窗口），恢复后继续。
  - `eFault`：输出保持；`bReset` 上升沿回 `eIdle`。
- 拼装：`uImportRaw := SHL(UINT_TO_UDINT(uImportHi), 16) OR UINT_TO_UDINT(uImportLo)`；`eWordOrder` 为 `eBadc` 等非 `eAbcd` 时先交换两字（**字序 ≠ 字节序**，头注释写明与 `FC_DL_SwapBytes32` 的层次差异：那个件交换字节内序，本件交换字间序）。
- 换算：`fImportNow := UDINT_TO_REAL(uImportRaw) * fKwhPerLsb`。
- 单调性：`IF fImportNow < stMeter.fImportAcc - fRegressRatio * DL_LSB_MAX * fKwhPerLsb THEN` → 判换表/清零：`bMeterReset := TRUE` 单拍、`stMeter.uResetCount++`、`stMeter.fImportAcc := fImportNow`（**基准重载，不回填负增量**）；否则若 `fImportNow < stMeter.fImportAcc` 但差值小 → 判为冻结值刷新抖动：保持上次累计（码 `0150` 信息级），不累加。
- 窗口积分：每拍 `stMeter.fWindowEnergy += fActivePower * (cycleSeconds)`；`cycleSeconds` 由窗口定时器与累加计数推算的**固定标称周期**给出（本件不接受外部周期输入，改用 `tDemandWindow` 与拍数比：`fWinSec / nCycleCount`；`nCycleCount` 由内部计数器维护，头注释写明「需在调用方固定任务周期下使用，变周期任务会引入需量偏差」）。
- 窗口到点：`fDemandAvg := stMeter.fWindowEnergy / fWinSec * 3600.0`（kWh→平均 kW）；`fDemandPeak := MAX(fDemandPeak, fDemandAvg)`；清窗口累加器与拍计数，重启 `fbWindow`（边界拍断输入一拍）。
- `fNetTotal := fImportTotal - fExportTotal`。

**边界与防错**

- `fKwhPerLsb <= 0` → 故障 `0310`（除零面 + 量纲错）。
- 窗口秒数 `< 1.0` → 用 1.0 并在头注释声明（防需量除零）。
- 32 位满量程回绕：`uImportRaw` 从 `FFFF_FFFF` 回到 0 会被判为回退 → 走换表分支，这是**有意的保守策略**（真实场景中 0.1 kWh/LSB × 2³² ≈ 4.29 亿 kWh，回绕前必然换表）。
- `bFreezePulse` 只用于锁存「冻结值已更新」的显示位，**不改变累计逻辑**（累计每拍按原始值递推），头注释写明防止误用。
- 非有限 `fActivePower` → 本拍不积分，码 `0311` 故障级。

**验收向量**

- V1：`uImportHi=16#0001`、`uImportLo=16#86A0`（= 100000 LSB）、`fKwhPerLsb=0.1` → `uImportRaw=16#0001_86A0=100000`；`fImportTotal=100000*0.1=10000.0` kWh。
- V2：下一拍 `uImportLo=16#86A1` → `uImportRaw=100001`、`fImportTotal=10000.1` kWh、增量 0.1 kWh。
- V3：随后读回 `uImportHi=0`、`uImportLo=16#0005`（= 5 LSB = 0.5 kWh），远低于 10000.1 → `bMeterReset=TRUE` 单拍、`uResetCount=1`、`fImportTotal=0.5`（基准重载，**不出现负增量**）。
- V4：`fActivePower=100.0` kW、`tDemandWindow=T#15M`、稳定 900 s 满窗 → `fWindowEnergy=25.0` kWh（100 kW × 0.25 h）；`fDemandAvg = 25.0/900*3600 = 100.0` kW；`fDemandPeak=100.0`。
- V5：`fKwhPerLsb=0.0` → `bError=TRUE`、`uErrorId=16#0003_0310`。

**来源与借鉴**：`source = namur-ne43`（信号质量与「原始域诊断不重标定」契约）+ 电表冻结寄存器工程惯例。借鉴点：NAMUR NE43 的「原始值域诊断与工程量分离」原则——本件先判原始 32 位值的单调性，再做工程量换算，诊断结论不依赖标定系数。算法与码位自有。

---

### 3.15 `FB_DL_VacuumGaugeMux`（DL_Device，FB，复杂度 6，源：namur-ne43 + oscat-building）

**功能定义**：皮拉尼（粗抽）与电容膜片（精抽）双真空计的量程选择、重叠区交叉校验与读数融合，不一致时锁存并保持上次输出。

**工业现场痛点**：镀膜/刻蚀腔体从大气抽到 1E−3 Pa 跨 6 个数量级，单表覆盖不了；切换点附近两表读数差一个数量级时操作员不知道信谁；直接取「先到先得」会把坏表读数送进工艺联锁。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时保持上次输出 / Enable
- `bReset : BOOL;` // 上升沿清故障与不一致锁存 / Rising edge clears fault and disagreement latch
- `bAcknowledge : BOOL;` // 上升沿确认不一致（人工已核） / Rising edge acknowledges a disagreement
- `fPiraniPa : REAL;` // 皮拉尼读数 [Pa]，域 > 0 / Pirani reading in pascals
- `bPiraniValid : BOOL;` // 皮拉尼数据有效 / Pirani reading valid
- `fCapacitancePa : REAL;` // 电容膜片读数 [Pa]，域 > 0 / Capacitance gauge reading
- `bCapacitanceValid : BOOL;` // 电容膜片数据有效 / Capacitance reading valid
- `fSwitchPa : REAL := 10.0;` // 切换点（皮拉尼量程上限）[Pa]，域 > 0 / Switchover pressure
- `fOverlapDecades : REAL := 1.0;` // 重叠区宽度 [十倍程]，域 0~3 / Overlap width in decades
- `fAgreeTolDecades : REAL := 0.5;` // 交叉校验允许偏差 [十倍程]，域 0.05~3 / Agreement tolerance in decades

`VAR_OUTPUT`
- `fPressurePa : REAL;` // 融合后压力 [Pa] / Fused pressure
- `eActiveGauge : E_DL_GaugeSel;` // 当前采信表 [-] / Active gauge
- `bInOverlap : BOOL;` // 处于重叠区 TRUE / Inside the overlap band
- `bDisagree : BOOL;` // 两表不一致锁存 / Disagreement latched
- `fDeltaDecades : REAL;` // 两表偏差 [十倍程]，无效表时为 0 / Deviation in decades
- `eQuality : E_DL_SignalQuality;` // 融合结果质量，复用既有枚举 / Fused quality, reuses the existing enumeration
- `bError : BOOL;` // 故障级锁存，仅 0313~0315 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_GaugePhase;` // 主状态机当前状态 / Current state

`VAR`（内部）
- `fbTrigReset : R_TRIG;` // 复位沿，CASE 外刷新 / Reset edge
- `fbTrigAck : R_TRIG;` // 确认沿，CASE 外刷新 / Acknowledge edge
- `ePhase : E_DL_GaugePhase := E_DL_GaugePhase.eIdle;` // 内部相位 / Internal phase
- `fHiSwitch : REAL;` // 切到电容的上门限 [Pa] / Upper switch threshold
- `fLoSwitch : REAL;` // 切回皮拉尼的下门限 [Pa] / Lower switch threshold
- `fLogPir : REAL;` // 皮拉尼十倍程 [decade] / Pirani log10
- `fLogCap : REAL;` // 电容十倍程 [decade] / Capacitance log10
- `fLast : REAL;` // 上次输出压力 [Pa] / Last output pressure
- `eSel : E_DL_GaugeSel;` // 本次选择 [-] / Selected gauge
- `bBothInvalid : BOOL;` // 两表都无效 / Both gauges invalid
- `bPirOk : BOOL;` // 皮拉尼可用（有效且 > 0） / Pirani usable
- `bCapOk : BOOL;` // 电容可用 / Capacitance usable
- `fWinLo : REAL;` // 重叠区下界 [Pa] / Overlap lower bound
- `fWinHi : REAL;` // 重叠区上界 [Pa] / Overlap upper bound

`VAR CONSTANT`
- `DL_LN10 : REAL := 2.302585093;` // 自然对数 10 [-] / Natural log of ten
- `DL_P_MIN : REAL := 1.0E-9;` // 最小可接受压力 [Pa] / Minimum acceptable pressure
- `DL_SWITCH_HYST : REAL := 0.5;` // 切换迟滞（以十倍程为单位的一半） / Switch hysteresis in decades

**算法要点**

- 状态机（`E_DL_GaugePhase` 四成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0003_0315`）：
  - `eIdle`：`bEnable` 后校验 `fSwitchPa > 0`（否则 `eFault` + `0313`）、`fOverlapDecades` 钳 0~3、`fAgreeTolDecades` 钳 0.05~3（码 `0153` / `0154`），转 `eSelect`。
  - `eSelect`：有效性判定与量程选择；转 `eOverlapCheck`。
  - `eOverlapCheck`：若两表均可用且当前压力落在重叠区 → 交叉校验；不一致 → `bDisagree := TRUE` 锁存、`eFault` + `0314`、输出保持 `fLast`。`bAcknowledge` 上升沿清 `bDisagree`（**但保持故障锁存直到 `bReset`**）。
  - `eFault`：输出保持 `fLast`，`bError := TRUE`；`bReset` 上升沿回 `eIdle`。
- 切换迟滞：`fHiSwitch := fSwitchPa`；`fLoSwitch := fSwitchPa / 10^(fOverlapDecades * 0.5)`；当前为皮拉尼时，压力降到 `fLoSwitch` 以下才切电容；当前为电容时，升到 `fHiSwitch` 以上才切回（两侧不同门限，防切换点抖动）。
- 十倍程：`fLogPir := LN(fPiraniPa) / DL_LN10`（`fPiraniPa < DL_P_MIN` 时判不可用）。
- 重叠区：`[fLoSwitch, fHiSwitch]`；`bInOverlap := (fPressurePa >= fLoSwitch) AND (fPressurePa <= fHiSwitch)`。
- 交叉校验：`fDeltaDecades := ABS(fLogPir - fLogCap)`；`IF fDeltaDecades > fAgreeTolDecades THEN 不一致`。
- 融合规则：重叠区内取**电容表**（精抽段精度高一个量级，物理事实，注释写明）；重叠区外按当前选择表取原值。
- 质量码：两表均可用且在重叠区一致 → `eGood`；单表可用 → `eUncertain`；不一致锁存 → `eBad`；两表均不可用 → `eBad` + `0314`。

**边界与防错**

- 读数 `<= DL_P_MIN` 视为不可用（防 `LN(0)` 与 `LN(负数)`）。
- 两表都无效 → 故障 `0314`（两表同时失效属设备级故障），输出保持。
- 不一致时**不死用任一表**：保持上次输出，避免坏表值直接进工艺联锁。此策略必须写进头注释。
- `bAcknowledge` 只清「人工已核」标志，不清故障锁存（诊断证据保留），两套清除路径分离。
- 切换点与重叠区参数在运行期变化时，当拍立即生效（不做参数快照），头注释提示「配方切换时应先停用本件」。

**验收向量**

- V1：`fPiraniPa=15.0`、`bPiraniValid=TRUE`、`fCapacitancePa=12.0`、`bCapacitanceValid=TRUE`、`fSwitchPa=10.0`、`fOverlapDecades=1.0`、`fAgreeTolDecades=0.5` → `fLoSwitch=10/10^0.5=3.162`、`fHiSwitch=10.0`；15 Pa 高于 `fHiSwitch` 故不重叠 → 选皮拉尼；`fPressurePa=15.0`、`eActiveGauge=ePirani`、`bInOverlap=FALSE`、`bDisagree=FALSE`。
- V2：`fPiraniPa=100.0`、`fCapacitancePa=1.0`（均有效）→ `fLogPir=2.0`、`fLogCap=0.0`、`fDeltaDecades=2.0 > 0.5` → `bDisagree=TRUE`、`bError=TRUE`、`uErrorId=16#0003_0314`、`fPressurePa` 保持上次。
- V3：`fPiraniPa=6.0`、`fCapacitancePa=4.0` → 6 Pa 落在 `[3.162, 10.0]` 重叠区；`fLogPir=0.7782`、`fLogCap=0.6021`、`Δ=0.1761 ≤ 0.5` → 一致，取电容表：`fPressurePa=4.0`、`eActiveGauge=eCapacitance`、`bInOverlap=TRUE`、`eQuality=eGood`。
- V4：`bPiraniValid=FALSE`、`bCapacitanceValid=FALSE` → `bError=TRUE`、`uErrorId=16#0003_0314`、输出保持。
- V5：当前为皮拉尼、压力降到 8.0 Pa（> `fLoSwitch=3.162`）→ 仍为 `ePirani`（迟滞区不切换）。

**来源与借鉴**：`source = namur-ne43 + oscat-building`。借鉴点：NAMUR NE43 的「多段有效域 + 越域即诊断」契约形态（四段电平域思路平移到「多量程表选择」），以及 OSCAT Building 的「域外行为显式化」写法。切换迟滞、交叉校验口径、融合规则自有。

---

### 3.16 `FB_DL_LineInterp2Axis`（DL_Motion，FB，复杂度 8，源：github-topics-motion）

**功能定义**：两轴直线插补——由起点/终点、合成速度与加速度生成两轴位置给定，自动判定梯形/三角速度曲线，并按单轴速度上限缩放合成速度。

**工业现场痛点**：开源运动库要么给 Bresenham（速度不可控、有台阶、无法做加减速），要么绑厂商插补指令（换平台重写）。经济型 PLC + 脉冲轴做 XY 涂胶/点胶/搬运时，最缺的就是「合成速度恒定 + 单轴不超速 + 端点平滑减速」。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时停止输出并回 eIdle / Enable
- `bReset : BOOL;` // 上升沿清故障 / Rising edge clears the fault
- `bStart : BOOL;` // 上升沿启动（eIdle 态有效） / Rising edge starts the move
- `bHold : BOOL;` // TRUE 时暂停推进（速度归零，位置保持） / Pauses the interpolation
- `fStartX : REAL;` // 起点 X [mm] / Start X in millimetres
- `fStartY : REAL;` // 起点 Y [mm] / Start Y
- `fEndX : REAL;` // 终点 X [mm] / End X
- `fEndY : REAL;` // 终点 Y [mm] / End Y
- `fPathSpeed : REAL := 100.0;` // 期望合成速度 [mm/s]，域 > 0 / Desired path speed
- `fAccel : REAL := 500.0;` // 加减速度 [mm/s²]，域 > 0 / Acceleration
- `fMaxSpeedX : REAL := 1000.0;` // X 轴速度上限 [mm/s]，域 > 0 / X axis speed limit
- `fMaxSpeedY : REAL := 1000.0;` // Y 轴速度上限 [mm/s]，域 > 0 / Y axis speed limit
- `fNominalCycle : REAL := 0.004;` // 标称插补周期 [s]，域 1E−4~1.0 / Nominal interpolation period
- `fMaxPathLen : REAL := 100000.0;` // 允许最大路径长度 [mm]，域 > 0 / Maximum path length

`VAR_OUTPUT`
- `bBusy : BOOL;` // 插补进行中 / Interpolation running
- `bActive : BOOL;` // 位置给定有效 / Command valid
- `bDone : BOOL;` // 到达终点（保持型，直到下一次 bStart） / End reached, held until the next start
- `fCmdX : REAL;` // X 位置给定 [mm] / X position command
- `fCmdY : REAL;` // Y 位置给定 [mm] / Y position command
- `fPathProgress : REAL;` // 路径完成度 [%]，域 0~100 / Path progress
- `fPathVel : REAL;` // 当前合成速度 [mm/s] / Current path speed
- `fPathLen : REAL;` // 本次路径总长 [mm] / Total path length
- `fPeakVel : REAL;` // 本次实际峰值速度 [mm/s] / Effective peak speed
- `bError : BOOL;` // 故障级锁存，仅 0204~0207 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_LineInterpPhase;` // 主状态机当前相位 / Current phase

`VAR`（内部）
- `fbTrigStart : R_TRIG;` // 启动沿，CASE 外刷新 / Start edge
- `fbTrigReset : R_TRIG;` // 复位沿，CASE 外刷新 / Reset edge
- `ePhase : E_DL_LineInterpPhase := E_DL_LineInterpPhase.eIdle;` // 内部相位 / Internal phase
- `fDx : REAL;` // X 方向位移 [mm] / X displacement
- `fDy : REAL;` // Y 方向位移 [mm] / Y displacement
- `fLen : REAL;` // 路径长度 [mm] / Path length
- `fUx : REAL;` // X 单位向量分量 [-] / X unit component
- `fUy : REAL;` // Y 单位向量分量 [-] / Y unit component
- `fVEff : REAL;` // 生效合成速度 [mm/s] / Effective path speed
- `fVLimit : REAL;` // 单轴限速折算的合成速度上限 [mm/s] / Speed cap from axis limits
- `fAccUse : REAL;` // 生效加速度 [mm/s²] / Effective acceleration
- `fAccDist : REAL;` // 单侧加速距离 [mm] / One-sided acceleration distance
- `fPeak : REAL;` // 峰值速度 [mm/s] / Peak speed
- `fS : REAL;` // 当前路径位移 [mm] / Travelled distance
- `fV : REAL;` // 当前速度 [mm/s] / Current speed
- `fDt : REAL;` // 本拍时间增量 [s] / Time increment of this cycle
- `bTriangular : BOOL;` // 三角曲线（无匀速段） / Triangular profile
- `fTmpX : REAL;` // 单轴限速折算中间量 X [mm/s] / X cap temporary
- `fTmpY : REAL;` // 单轴限速折算中间量 Y [mm/s] / Y cap temporary

`VAR CONSTANT`
- `DL_LEN_MIN : REAL := 1.0E-6;` // 判零长度阈值 [mm] / Zero-length threshold
- `DL_DT_MIN : REAL := 1.0E-4;` // 最小周期 [s] / Minimum cycle
- `DL_DT_MAX : REAL := 1.0;` // 最大周期 [s] / Maximum cycle

**算法要点**

- 状态机（`E_DL_LineInterpPhase` 八成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0004_0207`）：
  - `eIdle`：`bStart` 上升沿 → `ePrep`。
  - `ePrep`：参数闸门（`fPathSpeed > 0`、`fAccel > 0`、`fMaxSpeedX > 0`、`fMaxSpeedY > 0`、`fNominalCycle` 钳到 `[DL_DT_MIN, DL_DT_MAX]`、`fMaxPathLen > 0`）→ 计算 `fDx/fDy/fLen/fUx/fUy`。
    - `fLen < DL_LEN_MIN` → 直接 `eDone`（零长度，码 `0109` 信息级），输出 = 起点。
    - `fLen > fMaxPathLen` → `eFault` + `0205`（路径超限）。
  - `eAccel`：`fV := MIN(fPeak, fV + fAccUse*fDt)`；`fS += fV*fDt`；`fS >= fAccDist` → `eCruise`（三角曲线时直接 `eDecel`）。
  - `eCruise`：`fV := fPeak`；`fS += fV*fDt`；`fS >= fLen - fAccDist` → `eDecel`。
  - `eDecel`：`fV := MAX(fPeak*0.05, fV - fAccUse*fDt)`（保留 5% 收尾速度防爬行无限）；`fS += fV*fDt`；`fS >= fLen` → `fS := fLen`、`eDone`。
  - `eDone`：`bDone := TRUE`、`bBusy := FALSE`、输出 = 终点；`bStart` 再次上升 → `ePrep`。
  - `eHeld`：`bHold=TRUE` 进入，`fV := 0.0`、位置保持；`bHold=FALSE` → 回 `eAccel`（**从当前速度 0 重新加速，不跳变**）。
  - `eFault`：输出保持，`bError := TRUE`；`bReset` 上升沿 → `eIdle`。
- 单轴限速折算：`fVLimit := fPathSpeed`；`IF ABS(fUx) > DL_LEN_MIN THEN fTmpX := fMaxSpeedX / ABS(fUx); fVLimit := MIN(fVLimit, fTmpX); END_IF`；Y 同理。`fVEff := fVLimit`（**这里先与 `fPathSpeed` 取 MIN 再与单轴折算取 MIN，顺序不可颠倒**，否则会取到 `fPathSpeed` 以上）。
- 加减速距离：`fAccDist := fVEff*fVEff / (2.0*fAccUse)`（除零面已由 `fAccel > 0` 与 `DL_DT_MIN` 守卫）；`IF 2.0*fAccDist > fLen THEN bTriangular := TRUE; fPeak := SQRT(fAccUse*fLen); fAccDist := fLen*0.5; ELSE fPeak := fVEff; END_IF`
- 位置给定：`fCmdX := fStartX + fUx*fS`；`fCmdY := fStartY + fUy*fS`；`fPathProgress := fS / fLen * 100.0`（`fLen` 已过判零闸门）。
- `fDt` 取 `fNominalCycle`（**不读系统时钟**，保证可复现与跨平台一致；头注释写明「调用方必须把本件放在固定周期任务中，周期值通过 fNominalCycle 注入」）。

**边界与防错**

- `fUx/fUy` 在 `fLen >= 1e-6` 后计算，除零面已消除；仍保留 `IF fLen > DL_LEN_MIN` 守卫。
- 三角/梯形判据用 `2*fAccDist > fLen`，**临界相等按梯形**（`2*fAccDist = fLen` 时 `fPeak = fVEff`，两分支结果一致，故取哪支都不跳变——注释写明）。
- 终点速度不归零会让 `fS` 越过 `fLen`，故 `eDecel` 出口强制 `fS := fLen`（钳位）且 `fPathProgress := 100.0`。
- `bHold` 期间不推进 `fS`（位置保持），恢复时从当前速度重新加速；`fDt` 仍按标称周期推进，不加累积补偿（**不做时间补偿**，避免暂停后瞬间跳位）。
- 所有非有限输入（NaN/Inf）→ `eFault` + `0206`，早退。

**验收向量**

- V1：`fStartX=0、fStartY=0、fEndX=300、fEndY=400` → `fDx=300`、`fDy=400`、`fLen=500`；`fPathSpeed=100`、`fAccel=200`、`fMaxSpeedX=fMaxSpeedY=1000` → `fVEff=100`（单轴折算 1000/0.6=1666.7、1000/0.8=1250，均 > 100）、`fAccDist=100²/(2*200)=25`；`2*25=50 < 500` → 梯形，`fPeak=100`；路径中点（`fS=250`）→ `fCmdX=0+0.6*250=150`、`fCmdY=0+0.8*250=200`、`fPathProgress=50.0`、`fPathVel=100.0`。
- V2：参数与 V1 相同但 `fMaxSpeedX=50` → `fTmpX=50/0.6=83.333`，`fVEff=83.333`；中点 → `fCmdX=150`、`fCmdY=200`、`fPathVel≈83.33`（±0.01）。单轴速度校验：`83.333*0.6=50.0 ≤ 50`。
- V3：`fStartX=fEndX=10`、`fStartY=fEndY=20` → `fLen=0 < 1e-6` → 当拍 `bDone=TRUE`、`fCmdX=10`、`fCmdY=20`、`uErrorId=16#0004_0109`。
- V4：`fStartX=0、fStartY=0、fEndX=30、fEndY=40`（`fLen=50`）、`fPathSpeed=100`、`fAccel=200` → `fAccDist=25`、`2*25=50 = fLen` 临界 → 梯形，`fPeak=100`、`bTriangular=FALSE`。
- V5：`fEndX=24、fEndY=32`（`fLen=40`）、同速度加速度 → `2*25=50 > 40` → 三角，`fPeak=SQRT(200*40)=89.44`（±0.05）、`fAccDist=20`。
- V6：`fAccel=0` → `bError=TRUE`、`uErrorId=16#0004_0204`、`bBusy=FALSE`。

**来源与借鉴**：`source = github-topics-motion`。借鉴点：GitHub `motion` / `structured-text` topics 下开源运动库的**共同形态**——「单位向量分解 + 合成速度限幅 + 梯形/三角自适应」三段结构（多份实现交叉印证这是社区共识写法，非某一家独有）。速度剖面、临界判据、暂停策略、码位全自有；逐仓许可未逐条复核，按最严口径「只借结构与参数域，零代码行复制」。

---

### 3.17 `FB_DL_BatchPhaseBase`（DL_Process，FB，复杂度 8，源：isa88-batch）

**功能定义**：ISA-88 批次相（Phase）的标准状态机底座——提供相状态迁移、相内步骤推进、暂停/恢复/停止/中止四类命令的语义裁决，具体工艺动作由调用方按 `bRequestStep` 实现（动作外置）。

**工业现场痛点**：投料、升温、搅拌、清洗每个相都手写一套状态机，Holding/Held 与 Restarting 语义各写各样，MES 采集到的「相状态」在不同工位含义不同；ISA-88 的相状态模型在 PLC 库里没有可复用底座，导致批次报表无法跨线汇总。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时冻结相状态（不推进、不响应命令） / Enable, freezes the phase when FALSE
- `bStart : BOOL;` // 上升沿启动相（eIdle → eRunning） / Rising edge starts the phase
- `bHold : BOOL;` // 上升沿请求暂停（在步骤边界生效） / Rising edge requests hold at a step boundary
- `bRestart : BOOL;` // 上升沿从 Held 恢复（继续当前步骤，不重头） / Rising edge resumes from the current step
- `bStop : BOOL;` // 上升沿请求停止（当前步骤完成后停） / Rising edge requests a controlled stop
- `bAbort : BOOL;` // 上升沿请求中止（立即，跳过步骤收尾） / Rising edge aborts immediately
- `bReset : BOOL;` // 上升沿从 eComplete / eStopped / eAborted 回 eIdle / Rising edge returns to idle
- `bStepDone : BOOL;` // 步骤完成反馈（相内动作成功） / Step completion feedback
- `bStepFail : BOOL;` // 步骤失败反馈（相内动作失败） / Step failure feedback
- `nStepCount : INT := 1;` // 相内步骤数 [步]，域 1~32 / Steps in the phase, 1..32
- `tStepTimeout : TIME := T#60S;` // 单步超时 [ms/s]，0 表示不监控 / Per-step timeout, zero disables
- `tHoldTimeout : TIME := T#600S;` // 暂停超时 [ms/s]，超时转中止，0 表示不监控 / Hold timeout, zero disables

`VAR_OUTPUT`
- `ePhase : E_DL_BatchPhaseState;` // 相状态（对外唯一状态出口） / Phase state, the only state output
- `nStepNo : INT;` // 当前步骤号，1 起，0 = 未进入 / Current step number, zero before the first step
- `bPhaseActive : BOOL;` // 相处于 Running 族（含 Holding/Held/Restarting） / Phase is active
- `bPhaseComplete : BOOL;` // 相正常完成（eComplete 保持） / Phase completed normally
- `bRequestStep : BOOL;` // 单拍：请执行第 nStepNo 步的动作 / One-scan request to execute the current step
- `bRequestAbort : BOOL;` // 单拍：请执行中止动作（关阀、停搅拌等） / One-scan abort action request
- `uPhaseElapsed : UDINT;` // 相运行累计时间（不含 Held）[s] / Accumulated running seconds, excluding held time
- `bError : BOOL;` // 故障级锁存，仅 0203~0206 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code

`VAR_IN_OUT`（无）

`VAR`（内部）
- `fbTrigStart : R_TRIG;` // 启动沿，CASE 外刷新 / Start edge
- `fbTrigHold : R_TRIG;` // 暂停沿 / Hold edge
- `fbTrigRestart : R_TRIG;` // 恢复沿 / Restart edge
- `fbTrigStop : R_TRIG;` // 停止沿 / Stop edge
- `fbTrigAbort : R_TRIG;` // 中止沿 / Abort edge
- `fbTrigReset : R_TRIG;` // 复位沿 / Reset edge
- `fbStepWatch : TON;` // 单步超时，CASE 外刷新（IN 由状态与步骤号决定） / Step timeout, refreshed outside CASE
- `fbHoldWatch : TON;` // 暂停超时，CASE 外刷新 / Hold timeout
- `fbSecBase : TON;` // 秒基准定时器，用于 uPhaseElapsed 累加（PT 固定 DL_SEC_MS，到点自复位） / One-second base timer for the elapsed counter
- `eState : E_DL_BatchPhaseState := E_DL_BatchPhaseState.eIdle;` // 主状态机状态 / Main state
- `nStep : INT;` // 当前步骤号 / Current step
- `nStepUse : INT;` // 生效步骤数 [步] / Effective step count
- `bStepAcked : BOOL;` // 本步骤的 bStepDone 已被消费（防一步多次完成） / Step completion consumed flag
- `bAbortReq : BOOL;` // 中止动作请求单拍 / Abort request pulse
- `bStepReq : BOOL;` // 步骤执行请求单拍 / Step request pulse
- `uElapsed : UDINT;` // 运行秒累计 [s] / Accumulated seconds
- `bSecTick : BOOL;` // 秒脉冲 / One-second tick
- `bHoldArmed : BOOL;` // 暂停请求已登记、待步骤边界生效 / Hold armed and pending a step boundary
- `bStopArmed : BOOL;` // 停止请求已登记 / Stop armed
- `bStateIllegal : BOOL;` // 非法状态捕获标记 / Illegal state captured flag
- `nGuard : DINT;` // 守卫 / Loop guard

`VAR CONSTANT`
- `DL_STEP_MAX : INT := 32;` // 步骤上限 [步] / Step limit
- `DL_SEC_MS : TIME := T#1S;` // 秒基准 [ms] / Second base

**ENUM 全成员（`E_DL_BatchPhaseState`，11 个，`CASE` 必须逐个覆盖 + `ELSE` 兜底）**

| 成员 | 编号 | 含义 | 出口条件 |
|---|---|---|---|
| `eIdle` | 0 | 空闲，等待启动；输出全复位 | `bStart` 上升 → `eRunning` |
| `eRunning` | 10 | 执行中，按 `nStepNo` 推进步骤 | 步骤耗尽 → `eCompleting`；`bHold` → `eHolding`；`bStop` 登记 → 步骤完成后 `eStopping`；`bAbort` → `eAborting` |
| `eCompleting` | 20 | 收尾中（最后一步已完成，等待动作收尾反馈） | `bStepDone` → `eComplete`；超时 → `eAborting` |
| `eComplete` | 30 | 相正常完成，保持直到 `bReset` | `bReset` → `eIdle` |
| `eHolding` | 40 | 暂停请求已接受，正在等步骤边界 | 进入即在本拍边界转 `eHeld`；`bAbort` → `eAborting` |
| `eHeld` | 50 | 已暂停（步骤不再推进，`bRequestStep` 停发） | `bRestart` → `eRestarting`；`bStop` → `eStopping`；`bAbort` → `eAborting`；`tHoldTimeout` → `eAborting` |
| `eRestarting` | 60 | 恢复中（重新发当前步骤请求，不重头） | 本拍发 `bRequestStep` 后 → `eRunning` |
| `eStopping` | 70 | 停止中（当前步骤收尾） | `bStepDone` → `eStopped`；`bAbort` → `eAborting`；超时 → `eAborting` |
| `eStopped` | 80 | 已停止，保持直到 `bReset` | `bReset` → `eIdle` |
| `eAborting` | 90 | 中止中（已发 `bRequestAbort` 单拍） | 本拍 → `eAborted` |
| `eAborted` | 99 | 已中止，保持直到 `bReset` | `bReset` → `eIdle` |

**算法要点**

1. 命令优先级（严格）：`Abort > Stop > Hold > Restart > Start`。同一拍多个命令到来时，高优先者胜，低优先者被丢弃且**不排队**（排队会让操作员的「停止」在几拍后突然生效，属高危行为）。
2. `Holding → Held` 的边界语义：`bHold` 只登记 `bHoldArmed := TRUE`；只有在「当前步骤的 `bStepDone` 已消费」或「步骤请求尚未发出」时才真正进 `eHeld`。**绝不在动作执行中途切断**——这是 ISA-88 相语义的核心，也是现场「暂停后物料半投」事故的根因。
3. 步骤推进：`eRunning` 中发 `bRequestStep` 单拍（本拍置 TRUE，下拍清零）；`bStepDone` 上升且 `NOT bStepAcked` → `nStep++`、`bStepAcked := FALSE`（下一拍重新允许）；`bStepFail` → `eAborting` + `0204`（步骤失败）。
4. `eRestarting`：`nStepNo` **不重置**，只把 `bStepAcked := TRUE`（视为当前步骤已执行过），本拍重新发 `bRequestStep`。
5. 超时：`fbStepWatch(IN := (eState 属于 eRunning/eCompleting/eStopping) AND tStepTimeout > 0, PT := tStepTimeout)`；到点 → `eAborting` + `0203`（单步超时）。`fbHoldWatch` 仅在 `eHeld` 计时 → `0205`（暂停超时）。
6. 计时：`fbSecBase` 每 1 s 给一拍；仅在 `eState = eRunning` 时 `uElapsed++`（**Held 不计入**，写进头注释，MES 用此值算相净运行时间）。
7. 收尾：`eCompleting` 也发 `bRequestStep`（第 `nStepCount+1` 号收尾动作按约定为 0 号，不推进步骤号），头注释写明「收尾动作由调用方以 `ePhase = eCompleting` 触发，不占步骤号」。
8. `ELSE` 兜底：`eState := eAborted`、`uErrorId := 16#0005_0206`、`bError := TRUE`（非法状态直接进最安全的终止态，**不回 eIdle**）。

**边界与防错**

- `nStepCount` 钳 1~32，越界置 `0206`? 不：越界属组态，钳位 + 信息码 `0104`（信息级），与非法状态码分开（非法状态用 `0206`）。
- 同一 `bStepDone` 不可被两步消费：`bStepAcked` 标志 + 每次推进后置 TRUE、下一拍清（R34「状态量生命周期四律」的落地）。
- `bStepDone` 与 `bStepFail` 同拍：失败优先（安全侧），进 `eAborting` + `0204`。
- `bAbort` 在 `eIdle` / `eComplete` / `eStopped` / `eAborted` 时无效（不产生 `bRequestAbort`），并在头注释写明「已终止态不接受中止命令」。
- `bEnable = FALSE`：冻结状态与输出（不清零，MES 需要看到最后相状态）。
- 本件**不实现任何工艺动作**，也**不定义配方结构**（Recipe/Procedure/Unit 的编排属上层，见 ROADMAP 待办），头注释写明边界，防止职责膨胀。

**验收向量**

- V1：`nStepCount=3`，启动后每拍给一次 `bStepDone` → 状态序列 `eIdle` → `eRunning`（`nStepNo=1`）→ `eRunning`（`nStepNo=2`）→ `eRunning`（`nStepNo=3`）→ 第 3 次 `bStepDone` 后 `eCompleting` → 收尾 `bStepDone` 后 `eComplete`；`bPhaseComplete=TRUE`；`uPhaseElapsed` 为实际秒数。
- V2：在第 2 步执行中给 `bHold` → 本拍 `eHolding`，若该步 `bStepDone` 未到则**不**转 `eHeld`（保持 `eHolding`）；`bStepDone` 到来后 → `eHeld`；此时 `bRequestStep` 不再为 TRUE；`bRestart` → `eRestarting` → 下一拍 `eRunning` 且 `nStepNo` 仍为 2（不重头）。
- V3：`eHeld` 状态下 `bAbort` → `eAborting`（`bRequestAbort` 单拍 TRUE）→ `eAborted`；`bReset` → `eIdle`，`nStepNo=0`、`bPhaseComplete=FALSE`。
- V4：`tStepTimeout=T#2S`，`nStepCount=1`、启动后不给 `bStepDone` → 2 s 后 `eAborting`、`bError=TRUE`、`uErrorId=16#0005_0203`。
- V5：`bStepDone` 与 `bStepFail` 同拍 → `eAborting` + `uErrorId=16#0005_0204`（失败优先）。

**来源与借鉴**：`source = isa88-batch`。借鉴点：ISA-88（IEC 61512）**公开的相状态模型**——Idle / Running / Complete / Holding / Held / Restarting / Stopping / Stopped / Aborting / Aborted 的状态集合与「暂停在步骤边界生效」「恢复不重头」两条语义。成员编号、状态机实现、超时策略、单拍请求语义、码位全自有；ISA-88 为公开规范（非代码），**无代码复制问题**。

---

### 3.18 `FB_DL_PollTempBank`（DL_Process，FB，复杂度 7，源：roadmap-p0 + t1-4 轮询组织）

**功能定义**：一条温控器采集行——对最多 8 台温控器轮询采集 PV/SV，输出温度、偏差、滑动均值、通道质量掩码与在线台数，连续失败通道自动摘除。

**工业现场痛点**：8 台温控器串一条 485 总线，某台掉线会拖慢整条总线，且原始寄存器值直接进控制会带入坏值；现场做法是「轮询 + 人工看哪台掉线」，台账靠手记。

**引脚规格**

`VAR_INPUT`
- `bEnable : BOOL;` // 使能，FALSE 时暂停轮询并保持输出 / Enable
- `bReset : BOOL;` // 上升沿清故障与摘除状态 / Rising edge clears fault and drop-out state
- `nDeviceCount : INT := 4;` // 温控器台数 [台]，域 1~8 / Device count, 1..8
- `anSlaveAddr : ARRAY[1..8] OF USINT;` // 各台从站地址 [1~247] / Slave addresses
- `auPvRaw : ARRAY[1..8] OF INT;` // 各台过程值原始寄存器 [LSB]（由传输层写入） / Raw process values written by the transport layer
- `auSvRaw : ARRAY[1..8] OF INT;` // 各台设定值原始寄存器 [LSB] / Raw setpoints
- `abPollOk : ARRAY[1..8] OF BOOL;` // 各台本次轮询成功标志 / Per-device poll success flags
- `fScaleGain : REAL := 0.1;` // 原始值到温度的比例 [°C/LSB]，域 > 0 / Raw to temperature gain
- `fScaleOffset : REAL := 0.0;` // 零点偏移 [°C] / Zero offset
- `fRangeMin : REAL := -50.0;` // 有效温度下限 [°C] / Valid temperature lower bound
- `fRangeMax : REAL := 200.0;` // 有效温度上限 [°C] / Valid temperature upper bound
- `nFilterLen : INT := 8;` // 滑动均值窗口长度 [拍]，域 1~32 / Moving average window
- `nDropAfterFails : INT := 3;` // 连续失败多少次摘除通道 [次]，域 1~10 / Failures before dropping a channel

`VAR_OUTPUT`
- `afTempC : ARRAY[1..8] OF REAL;` // 各台温度 [°C]，坏通道保持上次有效值 / Temperature per device, bad channels hold the last value
- `afSetpointC : ARRAY[1..8] OF REAL;` // 各台设定值 [°C] / Setpoints
- `afDeviation : ARRAY[1..8] OF REAL;` // 各台偏差 = PV − SV [°C] / Deviation
- `afTempAvg : ARRAY[1..8] OF REAL;` // 各台滑动均值 [°C] / Per-device moving average
- `auCommFailCnt : ARRAY[1..8] OF UINT;` // 各台连续失败次数 [次] / Consecutive failure counters
- `uQualityMask : WORD;` // 通道坏质量掩码，位 n−1 = 第 n 台坏 / Bad-channel mask
- `nOnlineCount : INT;` // 在线台数 [台] / Online device count
- `nWorstIdx : INT;` // 偏差绝对值最大的在线通道号，0 = 无 / Channel with the largest absolute deviation
- `fWorstDev : REAL;` // 该通道偏差值 [°C] / That deviation
- `bError : BOOL;` // 故障级锁存，仅 0207~0209 置位 / Latched fault
- `uErrorId : UDINT;` // 事件码，0 = 无事件 / Event code
- `eState : E_DL_TempBankPhase;` // 主状态机当前状态 / Current state

`VAR_IN_OUT`
- `aPollTable : ARRAY[0..15] OF ST_DL_PollItem;` // 轮询站表，交由内部调度块持有 / Poll table owned by the embedded scheduler

`VAR`（内部）
- `fbPoll : FB_DL_ModbusPollMaster;` // 内部轮询调度实例（复用既有件，不重写调度逻辑） / Embedded scheduler instance
- `afbAvg : ARRAY[1..8] OF FB_DL_MovingAverage;` // 逐通道滑动均值实例（复用既有件） / Per-channel moving average instances
- `fbTrigReset : R_TRIG;` // 复位沿 / Reset edge
- `ePhase : E_DL_TempBankPhase := E_DL_TempBankPhase.eIdle;` // 内部状态 / Internal state
- `bInit : BOOL := FALSE;` // 首扫标志 / First-scan flag
- `nDevUse : INT;` // 生效台数 [台] / Effective device count
- `fGainUse : REAL;` // 生效比例 [°C/LSB] / Effective gain
- `nFilterUse : INT;` // 生效窗口 [拍] / Effective window
- `nDropUse : INT;` // 生效摘除阈值 [次] / Effective drop threshold
- `fVal : REAL;` // 单通道温度 [°C] / Single channel temperature
- `fSp : REAL;` // 单通道设定值 [°C] / Single channel setpoint
- `fDevAbs : REAL;` // 偏差绝对值 [°C] / Absolute deviation
- `uQBuild : WORD;` // 质量掩码装配 [位串] / Quality mask under assembly
- `nOnline : INT;` // 在线计数 / Online counter
- `nWorst : INT;` // 最差通道号 / Worst channel
- `fWorst : REAL;` // 最差偏差值 / Worst deviation
- `abDropped : ARRAY[1..8] OF BOOL;` // 通道已摘除标志 / Dropped channel flags
- `nGuard : DINT;` // 守卫 / Loop guard
- `i : INT;` // 通道索引 / Channel index

`VAR CONSTANT`
- `DL_DEV_MAX : INT := 8;` // 台数上限 [台] / Device count limit
- `DL_FILT_MAX : INT := 32;` // 窗口上限 [拍] / Window limit
- `DL_GAIN_MIN : REAL := 1.0E-6;` // 比例最小正值 [°C/LSB] / Minimum gain
- `DL_GUARD_MAX : DINT := 64;` // 守卫上限 / Guard limit

**算法要点**

- 状态机（`E_DL_TempBankPhase` 三成员，`CASE` 全覆 + `ELSE` 兜底 → `eFault` + 码 `16#0005_0209`）：
  - `eIdle`：`bEnable` 后参数闸门（`fScaleGain <= DL_GAIN_MIN` → `eFault` + `0207`；`fRangeMin >= fRangeMax` → `eFault` + `0208`；`nDeviceCount` / `nFilterLen` / `nDropAfterFails` 越界 → 钳位 + 信息码 `0108`），转 `ePolling`。
  - `ePolling`：调用 `fbPoll`（主周期无条件调用）+ 逐通道换算与判定，转 `eEvaluating`。
  - `eEvaluating`：更新均值（`afbAvg[i]` 主周期无条件调用，`IN := afTempC[i]`，`bEnable := 通道可用`）、偏差、最佳/最差通道、质量掩码、在线台数；回 `ePolling`。
  - `eFault`：输出保持；`bReset` 上升沿回 `eIdle`。
- 换算：`fVal := INT_TO_REAL(auPvRaw[i]) * fGainUse + fScaleOffset`；`fSp := INT_TO_REAL(auSvRaw[i]) * fGainUse + fScaleOffset`。
- 有效性（三道闸）：① `abPollOk[i]` 为 TRUE；② `fVal` 有限；③ `fRangeMin <= fVal <= fRangeMax`。任一不过 → 该通道本拍无效：`afTempC[i]` **保持上次有效值**（`0 °C` 在锂电烘箱是合法工况值，用 0 填充会掩盖故障——此纪律与 R11 `FB_DL_NtcTempScan` 一致）。
- 失败计数：无效拍 `auCommFailCnt[i]++`（饱和 9999）；有效拍清零。达到 `nDropUse` → `abDropped[i] := TRUE`、质量位置位、码 `0109`（信息级：通道摘除）。
- 恢复：摘除后若连续 2 拍有效 → 自动恢复（`abDropped := FALSE`，头注释写明「自动恢复」策略，HMI 需提供手动禁用位时应由上层屏蔽本件输出）。
- 质量掩码：`uQBuild` 位 n−1 = 第 n 台坏（含摘除）；`nOnlineCount := nDevUse − 坏台数`。
- 最差通道：仅在线通道参与，`fDevAbs := ABS(afDeviation[i])`，严格大于才替换（并列取小号，保证可复现）。
- 轮询表组织：`aPollTable[k]` 按 `anSlaveAddr[k+1]` 填 `uSlaveAddr`、`uFuncCode := 3`、`uStartAddr := 0`、`uQuantity := 2`（PV/SV 连续两寄存器，头注释写明该约定可依机型调整，本件不改表结构，只填默认值）。

**边界与防错**

- `fScaleGain <= 0` → 故障 `0207`（量纲错 + 除零隐患）。
- `fRangeMin >= fRangeMax` → 故障 `0208`（有效域为空，任何值都会被判无效）。
- 温度保持策略：坏通道**保持上次值**并在质量掩码标记，禁止用 0 / 上限值填充。
- 窗口长度 1 时均值等于瞬时值（允许，但置信息码 `010A` 提示「无滤波能力」）。
- `bEnable = FALSE`：暂停轮询（`fbPoll.bEnable := FALSE`），输出保持。
- 内部两个复用件（`FB_DL_ModbusPollMaster`、`FB_DL_MovingAverage`）必须在主周期无条件调用，且**不得**包在 `IF` 里（红线：定时器/边沿冻结）。
- 层次边界：本件只做「采集行」，不做温控 PID（那是 `FB_DL_PidController` / 温控器内部职责），头注释写明。

**验收向量**

- V1：`nDeviceCount=1`、`auPvRaw[1]=253`、`auSvRaw[1]=250`、`fScaleGain=0.1`、`fScaleOffset=0.0` → `afTempC[1]=25.3`、`afSetpointC[1]=25.0`、`afDeviation[1]=0.3`、`uQualityMask=16#0000`、`nOnlineCount=1`。
- V2：`auPvRaw[2]=3200`（→ 320.0 °C）> `fRangeMax=200.0` → 通道 2 无效：`afTempC[2]` 保持上次值、`uQualityMask` 的 bit1（`16#0002`）置位、`auCommFailCnt[2]=1`。
- V3：通道 3 连续 3 拍 `abPollOk[3]=FALSE`、`nDropAfterFails=3` → 第 3 拍 `abDropped[3]=TRUE`、`uQualityMask` bit2 置位（`16#0004`）、`nOnlineCount` 减 1、`uErrorId=16#0005_0109`。
- V4：两通道偏差分别为 −3.5 与 +4.2（均在线）→ `nWorstIdx=4`（若为第 4 台）、`fWorstDev=4.2`。
- V5：`fScaleGain=0.0` → `bError=TRUE`、`uErrorId=16#0005_0207`、`afTempC` 全部保持。

**来源与借鉴**：`source = roadmap-p0 + t1-4`。借鉴点：ROADMAP §13.6 P0 条目「温控器轮询采集行（复用 ModbusPollMaster + MovingAverage）」的需求定义，以及 CODESYS Forge ModbusFB 族「调度与传输分层」的组织方式（调度由既有 `FB_DL_ModbusPollMaster` 承担，本件只做「行级编排 + 通道质量」）。编排逻辑、通道质量掩码、摘除/恢复策略、码位全自有；**不复制任何示例代码与注释**。

---

## 4 编码顺序、依赖与通用自检

### 4.1 推荐编码顺序（按依赖自底向上，减少返工）

1. **第一批（Level 0 原子，无内部依赖）**：`FC_DL_BitArrayExtract` → `FC_DL_BitArrayInsert` → `FC_DL_IntervalMembership` → `FC_DL_ArrayDiffSummary` → `FC_DL_StringReplaceAll` → `FC_DL_ModbusExceptionParse` → `FC_DL_SolarPositionCalc` → `FC_DL_WaterEnthalpy`
2. **第二批（Level 0/1 有状态件）**：`FB_DL_BitArrayChangeWatch` → `FB_DL_StringTokenStream` → `FB_DL_ValveCharacteristic`
3. **第三批（Level 1 设备件）**：`FB_DL_DeviceParamVerify` → `FB_DL_PortDiagBoard` → `FB_DL_EnergyMeterAccum` → `FB_DL_VacuumGaugeMux`
4. **第四批（Level 1 运动件）**：`FB_DL_LineInterp2Axis`
5. **第五批（Level 2 工艺件，依赖已收口件）**：`FB_DL_BatchPhaseBase` → `FB_DL_PollTempBank`

### 4.2 依赖合法性（对照 `directory-contract.md` 第三节依赖矩阵）

| 新件 | 允许依赖 | 本件实际依赖 | 结论 |
|---|---|---|---|
| Base 4 件 | 仅 `Standard.library` | 仅标准库（`SHL`/`SHR`/`FIND`/`LEFT`/`MID`） | ✅ |
| MathData 5 件 | Base | 仅标准库（未反向引 Base，避免循环） | ✅ |
| Algo 2 件 | Base、MathData | 仅标准库 | ✅ |
| Device 4 件 | Base、MathData | `E_DL_ByteOrder`（MathData 类型）、`E_DL_SignalQuality`（Device 内既有） | ✅ |
| Motion 1 件 | Base、MathData、Algo、Device | 仅标准库（`SQRT`） | ✅ |
| Process 2 件 | 全部低层 | `FB_DL_ModbusPollMaster`、`ST_DL_PollItem`、`FB_DL_MovingAverage` | ✅ |

> 注意：`FB_DL_PortDiagBoard` **不得**实例化 `FB_DL_PortDiagAggregator`（两者是「聚合器 → 看板」的上下游，看板只消费聚合器输出，实例化会造成 8 端口重复计算）。头注释写明「聚合器实例由调用方按组持有，本件只吃其输出」。

### 4.3 每件落盘前的自检（12 项，逐项打勾，任一不过禁止入库）

1. 文件名 = POU 名，前缀正确（`FC_DL_` / `FB_DL_`）。
2. 头部注释块七项齐全，版本 `1.0.0`，`开源溯源` 字段写明「原创实现（参考 XXX 分类与参数域）」。
3. 每个变量、每个枚举成员同行中文注释 + 单位 + 英文要点。
4. 无 `GVL` / `VAR_EXTERNAL` / `%I` `%Q` `%M` / 指针 / 厂商库。
5. 无隐式类型转换（`INT_TO_REAL` / `DINT_TO_LWORD` 等显式书写）。
6. 状态机 `CASE` 覆盖枚举**全部**成员 + `ELSE` 兜底；兜底置终端安全态 + 专用码。
7. `TON` / `R_TRIG` / `F_TRIG` 全部在 CASE 之外无条件刷新。
8. 浮点无 `=` 判等；除法有前置防零；数组先判界；循环有守卫。
9. 无魔法数（阈值/限幅/超时全部 `VAR CONSTANT` 或引脚）。
10. 全部输出路径确定（早退分支必须预置输出）。
11. 码位与本文件 1.2 节逐位一致，且已重跑求差断言。
12. 枚举/结构体名与本文件 2.1 / 2.2 节一致，未就地复制他人声明。

### 4.4 机检与语义双闸（沿用 R11 决议）

- **机检闸**：`_Staging_Raw/2026-11-15/redline_check_r11.py`（9 规则）逐件跑通。
- **语义闸**：逐件手算本文件给出的验收向量，**必须**包含三类向量——① 跟踪结束首拍（`BitArrayChangeWatch` / `StringTokenStream` / `LineInterp2Axis`）；② 锁存可达性（`DeviceParamVerify` / `VacuumGaugeMux` / `BatchPhaseBase`）；③ 终态可退出（`BatchPhaseBase` 的 `eComplete/eStopped/eAborted → eIdle`；`PortDiagBoard` 的复位仲裁顺序）。
- **求差闸**：新增码集合 ∩ 全库集合 = ∅（落盘前跑，不引用本文件结论）。

---

## 5 已主动拒绝的候选（防止下轮重复立项 / 防止编码者临场加件）

| # | 候选 | 拒绝理由 | 性质 |
|---|---|---|---|
| 1 | `FC_DL_GrayCode32ToBinary`（多字格雷码绝对编码器） | 既有 `FC_DL_GrayToBinary` / `FC_DL_BinaryToGray` 已覆盖格雷码双向；仅位宽从 16 扩到 32 属**纯变体** | 重复件 |
| 2 | `FC_DL_SwapBytes64`（LWORD 字节交换） | `FC_DL_SwapBytes16/32` + `E_DL_ByteOrder` 已覆盖字节序族；64 位版无新语义，且 LWORD 在 Modbus 场景需字序而非字节序（已由 `EnergyMeterAccum` 承担） | 重复件 |
| 3 | `FB_DL_FrequencyGenerator`（频率发生族） | 与既有 `FB_DL_PulseGenerator`（定宽脉冲）+ `FB_DL_PwmDutyController`（占空比可调）职责重叠；矩阵第 5 节原文即标注「需评估与 PulseGenerator 职责」，评估结论为**不立** | 职责重叠 |
| 4 | `FC_DL_SearchMinMaxDInt` / `SearchMinMaxUDInt`（LGF 四个重载中的整数版） | LGF 的四个重载在 ST 里可由调用方显式转换后复用 `FC_DL_SearchMinMax`，单独成件属**数据类型变体凑数**（矩阵第 5 节标为待挖，本轮经评估后明确不挖，理由入档） | 凑数变体 |
| 5 | `FB_DL_EventCounterInt` / `ModuloCounterUDInt`（Counter 组 INT/UDINT 变体） | 与 #4 同理：纯类型重载，无新增判据与状态语义 | 凑数变体 |
| 6 | `FB_DL_AlarmLifecycleManager`（ISA-18.2 报警生命周期本体） | 与既有 `FB_DL_AlarmManager` 职责高度重叠，且「抑制/搁置/停用」三态会把单个块推向 6+ 状态、5+ 定时器的巨无霸，须先拆 `AlarmSuppressor` / `AlarmShelveTimer` 两个原子件再谈本体，本轮不做 | 需先拆原子件 |
| 7 | `FB_DL_UndoRedoBuffer`（Data Handling 变长缓冲） | 库内已有 Ring/Lifo/Fifo 三点收口，变长缓冲需动态内存（红线禁 `POINTER`），不可实现 | 违反可移植性 |
| 8 | `FB_DL_RecipeSwitchSeq`（配方切换编排） | ROADMAP 明确标注「ISA-88 衔接待挖」，但前置件 `FB_DL_RecipeManager` 与 `FB_DL_BatchPhaseBase` 尚未联调，本轮只落底座不落编排（避免两套批次语义并存） | 前置未就绪 |
| 9 | `FB_DL_ModbusFrameBuilder`（组帧器） | `FB_DL_ModbusPollMaster` 已含 `SendFrame` 抽象桩，组帧属传输层派生件职责，放库内会与调用方的帧格式强耦合（RTU/TCP/ASCII 方言） | 层次越界 |

> 纪律重申：**宁少勿滥**。上述 9 条若下轮仍有人提出，先读本节。若确需立项，须先给出「与既有件的语义差」与技术评审结论。

---

## 6 与后续环节的接口（不在本轮执行）

- 勾选：本轮 18 件中，`FB_DL_PortDiagBoard`（ROADMAP §15.3）、`FB_DL_PollTempBank`（§13.6）、`FB_DL_ValveCharacteristic`（§7.6）、`FB_DL_VacuumGaugeMux`（§7.3）四条在 ROADMAP 有对应待办行，收口时由文档线就地勾选；其余 14 件属「通用原子件 / 组深化件」，按 R9~R11 同一处置口径登记于新节，**不为凑勾选写进行业语汇池**。
- 注册：`INDEX_REGISTRY.json` 由注册环节追加，`function_tags` 必须含本文件 0.4 节的 `source` 标签。
- 台账回写：`SOURCE_HUNTING_MATRIX.md` 第 5 节需回写 8 行（T2-1 的 Bit Logic / Data Handling / Comparator / Date and Timer 四行，T2-8 一行，T1-3 / T1-4 / T1-8 三行），逐行写明本轮新增件名与「待挖子族已收口/仍待挖」的新结论。
- 版本：六子库按「新增组件」升 MINOR；总库 168 → 186 件，version 2.0.0 → 2.1.0。

---

*R12 计划 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监（兜底模式）*