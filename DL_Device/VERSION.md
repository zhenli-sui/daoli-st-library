# DL_Device — 版本记录 / Version History

> **子库定位 / Role**：Level 1 标准物理设备 OOP 抽象层：以 `I_DL_*` 接口 + `FB_DL_*` 实现块的「契约/实现分离」模式，抽象气缸、电机驱动器、模拟量变送器、温控区等真实物理器件，供 DL_Process 全部机站动作层做依赖注入。
> **兼容平台 / Platforms**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop ｜ Schneider Machine Expert
> **依赖 / Depends**：仅 `Standard.library`（`TON` / `R_TRIG`）与库内 `DL_Base`（`FB_DL_SignalDebounce`，气缸磁开消抖）、`DL_Algo`（`FB_DL_PidController` / `FB_DL_PwmDutyController`，温控区实例注入，仅 `FB_DL_HeatCoolZone` 引用）。

---

> R37 增量行：组件总数 121→**128**（registry 实测口径，本轮 +7：`WaferCoolChuck` 03_2_0B / `CurtainEFEMZone` 0C / `VentPurgeDuty` 0D / `SlurryLevelBank` 0E / `FoupPurgeN2Flow` 0F / `CartonErectVacMonitor` 10 / `CoderRibbonLife` 11）；`E_DL_FailSafeDir` 由 `SlurryLevelBank` 同文件发布。

## v1.24 — 2026-11-21（R59）

R59 新增 SprayNozzleBank / DustCollectorPulse；SoftStarterDrive 升 v1.0.1（复位故障相位门、删自赋值死语句）。

## R39 返修迁移说明 ｜ 2026-11-19 ｜ 两件 P0 闭环

- `FB_DL_ElectrodeTabBendCtrl` v1.0.1 → **v1.0.2**：`tonStep` 三相共享无迁移断拍 → 拆分为 `tonStepAppr`/`tonHold`/`tonStepMeas` 三相独立实例（保压计时与步进超时分实例，测量相补步超时保护）；`eFault` 新增 `bReset` 上升沿迁出边回 `eIdle`。对外接口不变。
- `FB_DL_VavBoxZeroCal` v1.0.1 → **v1.0.2**：`tonStable`/`tonCal` 跨 `eZeroWait`/`eFullWait` 两相不复位 → 拆分为按相独立实例（`tonStableZero`/`tonStableFull`/`tonCalZero`/`tonCalFull`）。语义变化：总超时收紧为每相独立 `tCalTimeout`（合计上限 2 ×）。对外接口不变。
- 两件 R228-A/B 机检回归 0 命中。

## 当前版本 / Current Version

| 项 / Item | 值 / Value |
|---|---|
| 子库版本 / Sublibrary Version | **v1.17.0** |
| 组件总数 / Components | **133**（registry 实测口径，R35 新增 5 见 v1.14.0 增量节） |
| 发布日期 / Release Date | 2026-11-18 |
| 库总版本 / Library Version | 2.30.0 |
| 依赖层级 / Dependency Level | Level 1（依赖 Level 0 与 `Standard.library`；R13 六件仅依赖 `E_DL_ByteOrder`（DL_MathData 低层）与同层契约件 `I_DL_DeviceHealth`，无 DL_Process 反向依赖） |
| 故障码段 / Error Code Family | **`16#0003_xxxx`**（信息级 `16#0003_01xx` ｜ 故障级 `0003_02xx` 起段，R11 起扩至 `030x` 子块；**R13 本批占用 `0156`~`0165` 与 `0316`~`0329`，上界提至 `0329`**；码位级裁定：`0318`（换表）与 `0323`（稳态偏差）落故障带但语义为维护请求，**不置 `bError`**——见 MANUAL 故障码表「是否置 bError」列） |


## v1.16.0 ｜ 2026-11-18 ｜ R38：5 件（VavBoxZeroCal / ElectrodeTabBendCtrl / JunctionBoxPottingCheck / PouchSwellingGauge / FreshAirStepperDamper）

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 10 | FB_DL_VavBoxZeroCal | FB | `16#03_2_12` | t1-2-oscat-building | VAV 末端风量两点零点标定（静流稳定判据 + 标定期冻结调节） |
| 11 | FB_DL_ElectrodeTabBendCtrl | FB | `16#03_2_13` | t2-2-lbp | 极耳折弯角度与回弹学习（单向逼近，学习值限幅，迭代耗尽不冒 OK） |
| 12 | FB_DL_JunctionBoxPottingCheck | FB | `16#03_2_14` | t2-1-lgf-technology | 接线盒灌胶量积分窗 + 固化当量（°C·min）双判据独立记账 |
| 13 | FB_DL_PouchSwellingGauge | FB | `16#03_2_15` | t2-1-lgf-measurement | 软包鼓胀厚度巡检（Welford 批内统计 + Z 分数与绝对限双口径） |
| 14 | FB_DL_FreshAirStepperDamper | FB | `16#03_2_16` | t1-2-oscat-building | 新风阀步进开环（步数↔开度当量 + 反向间隙补偿 + 端点自学习） |

> R38 增量行：组件总数 → **133**（registry 实测口径）；库总版本 2.30.0。

## v1.14.0 ｜ 2026-11-18 ｜ R35 设备诊断与执行器批：5 件（1 件撞名跳件，规划 6 实际 5）

> 版本号说明：子库版本号按主控 R35 收口指令自 v0.16.0 对齐跃迁至 v1.14.0（与其他子库 SemVer 口径统一）；组件数以 registry 实测为准。

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 1 | FB_DL_GloveBoxAtmoCtrl | FB | `16#03_2_06` | t2-8-ne107 | 手套箱气氛联锁（水氧越限禁开门 + 净化循环请求，NE107 出口） |
| 2 | FB_DL_ProcessKitTimer | FB | `16#03_2_07` | t2-8-isa88 | 腔体部件保养计时器（拍数/时长双口径 + 到期锁存） |
| 3 | FB_DL_ExhaustDpTrend | FB | `16#03_2_08` | t2-1-lgf-measurement | 尾气管路压差趋势监视与堵塞预警（SignalStatistics） |
| 4 | FB_DL_BypassValveTrim | FB | `16#03_2_09` | t2-5-modpid | 旁通阀供回水压差 PI 微调（PidController + 阀位死区限幅） |
| 5 | FB_DL_CaseSealTapeMonitor | FB | `16#03_2_0A` | t2-8-isa182 | 封箱胶带缺料/断带监视（张力 + 光电双判据去抖） |

- 跳件报备：规划 #13 `FB_DL_ChamberGateValve`（`16#03_2_05`）因已于 11-17 由 roadmap-p1 泳道注册实现而撞名跳件，本子库未落盘未重复注册（R208）。

## v0.16.0 ｜ 2026-11-18 ｜ R30 半导体设备与机架诊断批：5 件（1 返修 + 4 新）

- `FB_DL_AhuFilterDpBank` v1.0.0：空调箱 4 段过滤器压差四级分档（迟滞 + 各段独立去抖 + 低风量冻结）——**R29 隔离件返修入册**：`aTonDeb : ARRAY[1..4] OF TON` 每拍无条件刷新、候选作废显式复位（码位 0003_03D9~03DD）。
- `FB_DL_FoupDoorSeq`：FOUP 开合门与载具联锁六态顺控（解锁-开门-载具在位-再锁定确认窗，故障锁存解除式可达）（0003_03DE~03E2）。
- `FB_DL_CoolantFlowAudit`：冷却水 8 支路流量审计（欠流位掩码 + 首出三律 + 传感器故障独立分型）（0003_03E3~03E7）。
- `FB_DL_ValvePdiSched`：阀岛 PDI 批量读取分槽调度（4 槽轮询 + 异常台账，调度与传输分层）（0003_03E8~03EC）。
- `FB_DL_RackDiagSummary`：机架 Axioline 8 板卡诊断汇总（首出定位 + 回绕差分归零 + 风暴/错误分离）（0003_03ED~03F1）。

> R30 增量行：组件总数 97→**102**（registry 实测口径）；终审抽 AhuFilterDpBank 验证 R40 返修范式通过，0 修。

---

## v0.11.0 ｜ 2026-11-16 ｜ R19 设备健康与参数事务批：健康仲裁/PROFINET 诊断/ESC 电流监视/参数写回事务 4 件

- `FB_DL_DeviceHealthArbiter`：多源设备健康仲裁（NE107 六态，编号即优先级）（码位见 .st 头注释码位总账）。
- `FB_DL_ProfinetAlarmDiag`：PROFINET 通道诊断八类聚合（首出通道/分类计数/NE107 出口）（码位见 .st 头注释码位总账）。
- `FB_DL_EscChuckCurrentMonitor`：半导体 ESC 静电吸附电流监视（吸附/释放三段，失吸与打火分型）（码位见 .st 头注释码位总账）。
- `FB_DL_DeviceParamWrite`：设备参数写回事务（备份→白名单写→读回复核→回滚，七态机）（码位见 .st 头注释码位总账）。
- 规格补正留档：`FB_DL_DeviceParamWrite` 补 afActual / uActiveIdx / bWriteNow 三引脚（读回通道闭环），裁定采纳（R19）。

> `16#0003_` 段游标：信息级下件起点 **0172**｜故障级下件起点 **033C**。

---

## v0.10.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：夹爪契约 + 平行夹爪实现 + 固态继电器加热驱动 3 件 / R18 Scenario Lane — Gripper Contract & SSR Heater Drive

**变更性质**：MINOR（新增 1 接口 + 2 实现块）。**契约要点**：接口件 `I_DL_Gripper` 不占码位（R67）；实现块的 5 个契约量只以 PROPERTY 对外、不设同名输出引脚（R66）。

### 新增组件（3 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `I_DL_Gripper` | I | 夹爪能力收敛为 7 只读属性 + 4 方法（Open/Close/Release/ClearFault） | `bOpened` / `fWidth` / `eHealth` |
| `FB_DL_ParallelGripper` | FB | 驱动 → 到位确认 → 夹持力保持三段动作，含超时与空夹判定 | `bCmdClose` / `bCloseFeedback` / `fForceSetpoint` |
| `FB_DL_SsrHeaterDrive` | FB | 0~100 % 功率需求转周期 PWM 通断指令，含占空比足量而不升温的判定 | `fPowerDemand` |

> 码位以注册表 `code_segment` 为准；接口条目为空（R67）；全库重叠复测 = 0。

## v0.9.0 ｜ 2026-11-16 ｜ R13 NE107 诊断族开族：设备健康契约 + 电表读侧契约 + Modbus 电表 + 阀门黏滞 + 风阀卡滞 + 泵汽蚀（6 件）/ R13 NE107 Diagnostics Family: Health Contract, Meter Contract, Modbus Meter, Stiction, Damper & Cavitation

**变更性质**：MINOR（新增 6 个组件，其中 2 个为纯契约接口），无破坏性变更，无迁移动作。对应 Round 13「统一设备健康语言（NAMUR NE107 四态 + 功能检查 + 未知）+ 三台诊断件按同一健康出口对齐」定位（来源标签 namur-ne107 / forge-devicereader / modbus-meter / stiction-diag / rockwell-aoi / lbp-basic-process，clean-room 未复制源码）。终审 **2 件契约件零缺陷零修改 PASS，4 件实现块修复后 PASS**（缺陷 9 条：中等 5 / 提示 4，全部定点修复，A3/A4/A5/A6 均升 v1.0.1）。**`E_DL_Ne107Status` 全库唯一属主为 `I_DL_DeviceHealth.st`**，其余组件只引用不重复声明（跨文件同名异型禁令）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 45 | `I_DL_DeviceHealth` | 接口 | 146 | 1.0.0 | namur-ne107 | **NE107 设备健康语言契约**（本族属主件）：「任何设备都能回答的三个问题」——健康吗（六态枚举）、证据是什么（诊断码 + 来源槽号）、持续多久了（态时长 + 锁存位）；属性 10 条全部只读 GET + 方法 2 个（CmdAck 不得应答 eFailure / CmdReset 仅锁存时受理）；**编号即仲裁优先级**（小者优先），严禁按 NE107 图标序改号；本文件同时承载 `E_DL_Ne107Status` 枚举定义 / Unified NE107 device-health language contract, sole owner of E_DL_Ne107Status |
| 46 | `I_DL_PowerMeter` | 接口 | 142 | 1.0.0 | namur-ne107 / forge-devicereader | 三相电表**读侧契约**：电量（三相平均电压/电流/有功/无功/功率因数/频率）+ 累计电能（正反向 LREAL，单调不减）+ 需量峰值 + 健康出口；属性 12 条只读 + 方法 3 个（CmdResetEnergy 故障期拒绝受理——故障期清零会同时抹掉读数与基准，事后无法追溯换表真伪）；不含写侧、不含通信调度、不做累计算法 / Three-phase power meter read-side contract |
| 47 | `FB_DL_ModbusPowerMeter` | FB | 998 | **1.0.1** | namur-ne107 / modbus-meter | **v1.0.1** —— Modbus 电表实现（IMPLEMENTS `I_DL_PowerMeter`）：三相原始值换算 + 32 位电能四字序拼装（单调性三段：大于才递推 / 小幅回退保持 / 大幅回退判换表并重载基准）+ 功率因数复算交叉校验 + 轻载抑制 + 15 min 需量窗 + NE107 六态健康出口；v1.0.1 修复 `_bPfMismatch` 无清零点（一次 015A 即永久降级）与字序枚举比较改声明区基准量（R34/R46 前身范式） / Modbus power meter with 32-bit energy stitching and PF cross-check |
| 48 | `FB_DL_ValveStictionDetect` | FB | 735 | **1.0.1** | namur-ne107 / stiction-diag | **v1.0.1** —— 阀门黏滞在线诊断：基于 OP/PV 反转点的同指令差分滞环估计黏滞带，四档严重度 + 停滞/反转双证据合取升级（单点指标越限不判重度）；文献反向结论已留档：任何单一判据都不 100% 可信，本件输出定位为**趋势判据而非计量量化**，全行程单向斜坡下判据 (a) 保守不出样本（裁定保留）；v1.0.1 裸时间字面量改常量（无魔法数） / Valve stiction on-line diagnosis with reversal-point hysteresis band |
| 49 | `FB_DL_AhuDamperStuckDiag` | FB | 615 | **1.0.1** | rockwell-aoi / namur-ne107 | **v1.0.1** —— AHU 风阀卡滞三分类诊断（T2-6 Rockwell 三分类范式落地）：`eFullStall`（指令已动、一步未动）/ `eTransitStall`（动了但没到）/ `eIoFault`（反馈失效），另带两工艺级 `eDeviation` / `eSlow`；**三类判据各带独立确认窗**；v1.0.1 修复判定相绕开 `tIoFaultTime` 确认窗直接锁存 0324（瞬时断线被升级成失效）；0323/0161 为「故障带码 + 不置 bError」首例组合 / AHU damper three-class stuck diagnosis with per-class confirmation windows |
| 50 | `FB_DL_PumpCavitationGuard` | FB | 559 | **1.0.1** | namur-ne107 / lbp-basic-process | **v1.0.1** —— 泵汽蚀三判据守卫：流量偏低 + 扬程跌落 +（振动超限 或 电流波动超限）同拍持续确认；单判据只到嫌疑不锁存（0164）；只输出 `fDerateRatio` / `bDerateRequest`，不写变频器频率（回升交上层斜坡）；v1.0.1 修复抑制窗「窗满」误当「窗内」、兜底值污染判据门出伪比值（V5 违例）、`bError=TRUE` 而 `uErrorId=0` 自相矛盾等 5 条 / Pump cavitation guard with three-criteria confirmation and derate ratio output |

### 修复 / Fixed

本子库本批无存量修复件（存量 R39 专案涉及 DL_Base / DL_Process 两件，见对应 VERSION.md）。

### 故障码台账追加（R13 码位登记，经终审全库复核 0 重叠）/ Error Code Ledger Additions (R13)

| 码位 | 级别 | 语义 / Meaning | 组件 | 置 bError |
|---|---|---|---|---|
| `0003_0156` | 信息级 | 三相电压不平衡度 > 2% 但未越限 | FB_DL_ModbusPowerMeter | 否 |
| `0003_0157` | 信息级 | 需量窗口 < 1 s 已按 1 s 兜底 | FB_DL_ModbusPowerMeter | 否 |
| `0003_0158` | 信息级 | 字序参数改变，首拍重载累计基准 | FB_DL_ModbusPowerMeter | 否 |
| `0003_0159` | 信息级 | 轻载下 PF/THD 越限被抑制 | FB_DL_ModbusPowerMeter | 否 |
| `0003_015A` | 信息级 | 复算功率因数与表值偏差 > 3% | FB_DL_ModbusPowerMeter | 否 |
| `0003_015B` | 信息级 | 频率越限（±0.5 Hz 带） | FB_DL_ModbusPowerMeter | 否 |
| `0003_015C` | 信息级 | 窗口样本不足或重建窗，未发布新等级 | FB_DL_ValveStictionDetect | 否 |
| `0003_015D` | 信息级 | 反馈失效诊断挂起提示 | FB_DL_ValveStictionDetect | 否 |
| `0003_015E` | 信息级 | 重建窗首窗不发布，保持上次等级 | FB_DL_ValveStictionDetect | 否 |
| `0003_0160` | 信息级 | 无反馈运行，尚未超失效时长 | FB_DL_AhuDamperStuckDiag | 否 |
| `0003_0161` | 信息级 | 行程偏慢或指令超域被钳位 | FB_DL_AhuDamperStuckDiag | 否 |
| `0003_0164` | 信息级 | 单判据嫌疑（不锁存） | FB_DL_PumpCavitationGuard | 否 |
| `0003_0165` | 信息级 | 抑制窗内判据被忽略 | FB_DL_PumpCavitationGuard | 否 |
| `0003_0316` | 故障级 | 电压/电流/电能标定非正 | FB_DL_ModbusPowerMeter | 是 |
| `0003_0317` | 故障级 | 原始寄存器全零且超陈旧超时 | FB_DL_ModbusPowerMeter | 是 |
| `0003_0318` | 故障级 | 电能累计回退（换表或清零）——维护语义，**不置 bError** | FB_DL_ModbusPowerMeter | **否（裁定）** |
| `0003_0319` | 故障级 | 非法状态兜底 | FB_DL_ModbusPowerMeter | 是 |
| `0003_031A` | 故障级 | 三相电流全零而有功非零（自相矛盾） | FB_DL_ModbusPowerMeter | 是 |
| `0003_031B` | 故障级 | 有功功率拼装结果非有限 | FB_DL_ModbusPowerMeter | 是 |
| `0003_031D` | 故障级 | 指令或阀位非有限 | FB_DL_ValveStictionDetect | 是 |
| `0003_031E` | 故障级 | 阈值参数非法 | FB_DL_ValveStictionDetect | 是 |
| `0003_031F` | 故障级 | 非法状态兜底 | FB_DL_ValveStictionDetect | 是 |
| `0003_0321` | 故障级 | 完全卡死（Full Stall） | FB_DL_AhuDamperStuckDiag | 是 |
| `0003_0322` | 故障级 | 行程卡滞（Transit Stall） | FB_DL_AhuDamperStuckDiag | 是 |
| `0003_0323` | 故障级 | 稳态偏差——维护语义，**不置 bError**（仍能调节 ≠ 不可运行） | FB_DL_AhuDamperStuckDiag | **否（裁定）** |
| `0003_0324` | 故障级 | I/O 反馈失效 | FB_DL_AhuDamperStuckDiag | 是 |
| `0003_0325` | 故障级 | 参数非法或非法状态兜底 | FB_DL_AhuDamperStuckDiag | 是 |
| `0003_0326` | 故障级 | 汽蚀确认（三判据同拍持续成立） | FB_DL_PumpCavitationGuard | 是 |
| `0003_0327` | 故障级 | 振动超上限两倍（急停级） | FB_DL_PumpCavitationGuard | 是 |
| `0003_0328` | 故障级 | 额定值非正或阈值倒置 | FB_DL_PumpCavitationGuard | 是 |
| `0003_0329` | 故障级 | 非法状态兜底 | FB_DL_PumpCavitationGuard | 是 |

---

## v0.8.0 ｜ 2026-11-15 ｜ R12 端口诊断看板 / 设备参数回读核对 / 电表累计与需量 / 真空计双表融合（4 件）/ R12 Port Board, Parameter Verify, Energy Meter & Vacuum Gauge Mux

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。对应 Round 12「诊断侧（端口看板 + 参数核对）与测量侧（电能 + 真空）」定位（来源标签 plcnext-diag / codesys-forge-devicereader / namur-ne43 / oscat-building，clean-room 未复制源码）。终审 **4 件中 1 件零修改 PASS，3 件修复后 PASS**（`FB_DL_VacuumGaugeMux` 1 致命、`FB_DL_EnergyMeterAccum` 1 严重、`FB_DL_DeviceParamVerify` 1 中等，均升 v1.0.1）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 41 | `FB_DL_DeviceParamVerify` | FB | 368 | **1.0.1** | codesys-forge-devicereader | **v1.0.1** —— 设备参数回读核对：组态期望块与设备回读块按逐项容差比对，单拍内完成全项遍历，结论「一致 / 不一致」锁存，不一致须人工确认；回读超时可关断（`T#0S`），回读非有限与超时置故障级；v1.0.1 每轮核对入口清信息码（R44） / Parameter readback verification with per-item tolerance and latched verdict |
| 42 | `FB_DL_PortDiagBoard` | FB | 459 | 1.0.0 | plcnext-diag | 端口诊断看板：把最多 4 组（每组 8 端口）的端口故障掩码汇总为一张看板——屏蔽超界位后的各组掩码、全局故障端口数、全局首出（组号 + 端口号 + 诊断码）与按「组号优先、端口号次之」排序的前 3 个待修端口，回答「还剩几个坏、先修哪一个」；首出锁存只认复位沿，单拍掩码跳变超阈值只作趋势提示不置故障 / Multi-group port diagnostic board with global first-out arbitration |
| 43 | `FB_DL_EnergyMeterAccum` | FB | 433 | **1.0.1** | namur-ne43 | **v1.0.1** —— 电表冻结值累计与需量：正反向各一 32 位拼装（字序可切），先判原始值单调性再做工程量换算（NE43「原始值域诊断与工程量分离」），换表 / 清零识别给单拍脉冲与累计次数，按窗口滑算平均需量与历史峰值；v1.0.1 修复暂停后剩余时间按本拍预置值求差（R40 家族） / Energy meter accumulation with demand window and meter-swap detection |
| 44 | `FB_DL_VacuumGaugeMux` | FB | 412 | **1.0.1** | namur-ne43 / oscat-building | **v1.0.1** —— 真空计双表融合：粗抽（皮拉尼）与精抽（电容膜片）按带迟滞的量程判定切换，重叠区做十倍程交叉校验并输出偏差与质量分级；单表可用降级为「不确定」而非故障；双表失效或不一致锁故障并保持上次压力；v1.0.1 取值后按本拍可用性复验（R42） / Dual vacuum gauge fusion with hysteresis switching and decade cross-check |

### 故障码台账追加（R12 码位登记，经终审全库复核）/ Error Code Ledger Additions (R12)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0003_0149` | 信息级 | 聚合组数超上限已钳位到 4（只影响显示范围，不置故障位） | FB_DL_PortDiagBoard |
| `0003_014A` | 信息级 | 某组端口数超上限已钳位到 8（组态常见，非错误） | FB_DL_PortDiagBoard |
| `0003_014B` | 信息级 | 掩码超界位已屏蔽（绝不把不存在的端口计入故障数） | FB_DL_PortDiagBoard |
| `0003_014C` | 信息级 | 组内声明首出端口与掩码推导值不一致（数据源未同步） | FB_DL_PortDiagBoard |
| `0003_014D` | 信息级 | 比对本数越界已钳位到 1~64 | FB_DL_DeviceParamVerify |
| `0003_014E` | 信息级 | 本轮核对一致（`bVerified` 为真） | FB_DL_DeviceParamVerify |
| `0003_014F` | 信息级 | 负容差已取绝对值 | FB_DL_DeviceParamVerify |
| `0003_0150` | 信息级 | 冻结值刷新抖动（差值在回退阈值内），保持上次累计不累加 | FB_DL_EnergyMeterAccum |
| `0003_0151` | 信息级 | 需量窗口小于 1 秒，已按 1 秒兜底 | FB_DL_EnergyMeterAccum |
| `0003_0152` | 信息级 | 换表回退比例越界，已钳到 0~1 | FB_DL_EnergyMeterAccum |
| `0003_0153` | 信息级 | 重叠区宽度越界，已钳到 0~3 个十倍程 | FB_DL_VacuumGaugeMux |
| `0003_0154` | 信息级 | 一致性容差越界，已钳到 0.05~3 个十倍程 | FB_DL_VacuumGaugeMux |
| `0003_0155` | 信息级 | 仅单表可用，融合质量为「不确定」（不置故障位） | FB_DL_VacuumGaugeMux |
| `0003_0309` | 故障级 | 组数小于 1，无诊断源 | FB_DL_PortDiagBoard |
| `0003_030A` | 故障级 | 某组端口数小于 1，该组掩码含义不可信 | FB_DL_PortDiagBoard |
| `0003_030B` | 故障段趋势码 | 单拍掩码变化位数超阈值，判为组态刷新（只作趋势提示，**不置 `bError`**） | FB_DL_PortDiagBoard |
| `0003_030C` | 故障级 | 非法状态兜底（终端安全态） | FB_DL_PortDiagBoard |
| `0003_030D` | 故障级 | 回读出现非有限值（NaN / 无穷） | FB_DL_DeviceParamVerify |
| `0003_030E` | 故障级 | 回读超时未就绪 | FB_DL_DeviceParamVerify |
| `0003_030F` | 故障级 | 非法相位兜底 | FB_DL_DeviceParamVerify |
| `0003_0310` | 故障级 | 每 LSB 电能非正（量纲错，含除零隐患） | FB_DL_EnergyMeterAccum |
| `0003_0311` | 故障级 | 有功功率非有限值，本拍不积分 | FB_DL_EnergyMeterAccum |
| `0003_0312` | 故障级 | 非法状态兜底（终端安全态） | FB_DL_EnergyMeterAccum |
| `0003_0313` | 故障级 | 切换点非正，量程划分无意义 | FB_DL_VacuumGaugeMux |
| `0003_0314` | 故障级 | 双表不一致或双表均失效，输出保持 | FB_DL_VacuumGaugeMux |
| `0003_0315` | 故障级 | 非法状态兜底（终端安全态） | FB_DL_VacuumGaugeMux |

**号段占用声明**：本批 `DL_Device` 依 R11 立规「`02FA`~`02FF` 封存禁填、故障级自 `0309` 顺延」，占用信息级 `0149`~`0155`（`0149` 为 R11 声明的下一可用信息级码）与故障级 `0309`~`0315`，子库故障码上界由 `0308` 提至 **`0315`**。`030B` 虽落在 `03xx` 故障子块内，语义为**趋势级提示码**（不置 `bError`），登记时按「故障段趋势码」单列，HMI 码表须按级别而非按号段着色。

### 缺陷修复 / Fixed

| 组件 / Component | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| `FB_DL_VacuumGaugeMux` | **致命** | 采信表在两相之间掉线时，`fPressurePa` 仍被写入该表原值（可能 0 或负）——工艺联锁据此可能判「已到真空」，与「不死用任一表」的契约正相反 | 非重叠取值后以「取值表的本拍可用性」门控发布（电容取 `bCapOk`、其余取 `bPirOk`）；不可用则本拍不发布、保持上次值，并回选择相下拍重裁 |
| `FB_DL_EnergyMeterAccum` | **严重** | 15 min 需量窗内暂停两次，实际窗口被拉长到约 1300 s，平均需量偏低约 31%（月结电量不受影响，峰值与平均需量失真） | 剩余时间改为 `tRemain := tPtUse - fbWindow.ET`（按本拍实际预置值求差），两种恢复模式通吃 |
| `FB_DL_DeviceParamVerify` | 中等 | 第一轮一致（`014E`）后 `uErrorId` 永久驻留，后续轮次 `014D` / `014F` 因「仅当 `uErrorId = 0` 才置码」被永久压住，出现「码说一致、结论说不一致」 | 进入新一轮核对（`eIdle → eWaiting`）时清 `uErrorId`，使信息码按核对周期重新开始 |

### 变更说明 / Change Notes

- **诊断三层分账（R12 收口）**：模块级状态字归本地总线诊断锁存件、端口级归端口聚合器与**本批看板**、参数对象级归**本批参数回读核对件**。看板只消费端口级聚合结果、不重算端口明细、不重复实例化上游聚合块。
- **两种计量语义不混用**：`FB_DL_EnergyMeterAccum` 处理 32 位两寄存器的**字间序**（高字在前 / 低字在前），`FC_DL_SwapBytes16/32` 处理**字节内序**，层次不同、不可互替。
- **真空件与温度/压力扫描件的边界**：真空件只做「双表选择 + 融合 + 质量定级」，不做通道巡检（归 NTC 巡检件）、不做报警分级（归调用方）。
- **红线状态**：R1~R44 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.7.0 ｜ 2026-11-15 ｜ R11 端口诊断聚合 / 状态字段解码 / NTC 巡检 / 辊距背隙补偿（4 件）+ 存量 4 件 PATCH / R11 Diagnostics, Decoding, Thermal Scan & Gap Trim

**变更性质**：MINOR（新增 4 个组件）+ PATCH（存量 4 件缺陷修复），无破坏性变更，无迁移动作。对应 Round 11 泳道 B「设备诊断 / 设备测量 / 设备执行」（来源标签 plcnext-community / profibus-diag / namur-ne107 / lgf-bitlogic / rockwell-aoi / oscat-building / lgf-measurement / lbp-process，均只借鉴功能分类与参数域，clean-room 未复制源码）。终审 **PASS with fixes**：`FB_DL_NtcTempScan` 1 处轻微缺陷修复后 **v1.0.1**（全扫模式扫描圈数累加缺饱和守卫，长时间运行在 32 位上限处回绕），其余 3 件零修改 PASS。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 37 | `FB_DL_PortDiagAggregator` | FB | 414 | 1.0.0 | plcnext-community / profibus-diag / namur-ne107 | 8 端口现场总线诊断聚合与首出仲裁：链路位 + 端口诊断码 + CRC 累计计数三源聚合成单一故障掩码、首出端口号、首出诊断码与错误风暴标志，解决「多端口同时报警时 HMI 只看到最后一条」；首出仅在未锁存时仲裁、同拍多故障取端口号最小者（低号端口更靠近主站，符合排故因果顺序），锁存后只认复位沿；风暴是趋势事件不锁存、只停一拍、不参与故障判定；窗口差分有硬拍序（先算增量再装载基准），计数回绕按归零处理不出假风暴 / 8-port fieldbus diagnostic aggregation with first-out arbitration |
| 38 | `FB_DL_StatusWordSegDecoder` | FB | 383 | 1.0.0 | lgf-bitlogic / rockwell-aoi / plcnext-community | 段表驱动的状态字批量解码（≤16 段，每段偏移 + 宽度 + 名称）：一次调用拿全部字段，替代「每字段调一次单段提取」的碎片写法；同拍给越界、重叠、段数三类组态诊断与段状态位，组态错误在投运首日即被拦下；入口统一 64 位宽字（DWORD 调用方高位补零即可，宽度是参数域不是语义差异）；宽度 = 64 直接取全 1 常量，**禁对 64 位字移位 64**（跨平台未定义行为）；重叠两种模式（拒绝 / 覆盖）都置段状态位与信息级码，绝不静默吞掉 / Segment-table driven status word decoder with overlap diagnostics |
| 39 | `FB_DL_NtcTempScan` | FB | 469 | **1.0.1** | rockwell-aoi / oscat-building / lgf-measurement | 1~16 路 NTC 热敏电阻温度巡检设备对象：B 值方程换算摄氏温度 + 逐通道断线/短路诊断 + 高低温柔限判定 + 最热通道定位 + 超温与断线双计数台账；扫描周期 > 0 按节拍轮询（单拍负载恒定，未扫通道沿用上次值），= 0 全通道每拍扫描；除法前先判五类零（B 常数、标称阻值、基准温度、阻值比、倒数温度），任一成立即本通道不换算；单路探头损坏只置通道掩码与信息码（整机降级运行），仅「有效通道为零」与「换算参数非法」置故障位 / Multi-channel NTC scanning with B-value conversion and per-channel diagnostics |
| 40 | `FB_DL_RollerGapAdjust` | FB | 410 | 1.0.0 | rockwell-aoi / lbp-process / lgf-technology | 辊距微调背隙补偿设备对象：单向越程逼近（先退到目标下方一个背隙）→ 反向精定位，每次调整都从同一侧逼近目标，消除双向逼近的重复定位偏差；指令只在相位跃迁拍写，其余拍不写——天然满足「反馈丢失时指令保持」（对辊距而言指令清零等于辊缝全开，属危险侧动作）；到位判定同时要求偏差在容差内且反馈有效；到位拍记残余偏差、更新偏差低通均值、超容差计数，供预测机械磨损；刻意不注入轴接口，避免设备层拖到运动层 / Roller gap trim with one-directional backlash compensation |

### 故障码台账追加（R11 码位登记，经终审全库复核）/ Error Code Ledger Additions (R11)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0003_0140` | 信息级 | 端口数超上限已钳位（只进码与趋势，不置故障位） | FB_DL_PortDiagAggregator |
| `0003_0141` | 信息级 | 统计窗口参数越界已钳位（只进码，不置故障位） | FB_DL_PortDiagAggregator |
| `0003_0142` | 信息级 | 段间重叠（拒绝模式下该段作废，覆盖模式下取后段值） | FB_DL_StatusWordSegDecoder |
| `0003_0143` | 信息级 | 段越界已拒绝（宽度为零 / 宽度超字宽 / 偏移加宽超字宽） | FB_DL_StatusWordSegDecoder |
| `0003_0144` | 信息级 | 段数越界已钳位（小于 1 或大于 16） | FB_DL_StatusWordSegDecoder |
| `0003_0145` | 信息级 | 通道数越界已钳位（小于 1 或大于 16） | FB_DL_NtcTempScan |
| `0003_0146` | 信息级 | 单通道断线或短路已跳过（保持上次温度，不写零冒充） | FB_DL_NtcTempScan |
| `0003_0147` | 信息级 | 目标间隙越界已钳位（含上下限颠倒时的自动换位） | FB_DL_RollerGapAdjust |
| `0003_0148` | 信息级 | 背隙补偿量越界已钳位（负值或超上限） | FB_DL_RollerGapAdjust |
| `0003_0300` | 故障级 | 端口故障锁存（伴随故障掩码非零，置 `bError`） | FB_DL_PortDiagAggregator |
| `0003_0301` | 故障级 | 诊断源未注入（端口数小于 1，置 `bError`） | FB_DL_PortDiagAggregator |
| `0003_0302` | 故障级 | 段表整体非法（无任何段可用）或非法状态兜底 | FB_DL_StatusWordSegDecoder |
| `0003_0303` | 故障级 | 全通道失效（有效通道数为零，置故障位） | FB_DL_NtcTempScan |
| `0003_0304` | 故障级 | 换算参数非法已锁存（B 常数 / 标称阻值 / 基准温度），需复位退出 | FB_DL_NtcTempScan |
| `0003_0305` | 故障级 | 到位超时（限时内偏差始终未进入容差带） | FB_DL_RollerGapAdjust |
| `0003_0306` | 故障级 | 位移反馈无效或丢失（指令保持，撤回到位标志） | FB_DL_RollerGapAdjust |
| `0003_0307` | 故障级 | 非法状态兜底 | FB_DL_PortDiagAggregator |
| `0003_0308` | 故障级 | 非法相位兜底（指令保持，需复位退出） | FB_DL_RollerGapAdjust |

**号段占用与上界突破声明（R11 专项，务必留档）/ Slot Allocation and Upper-Bound Break**：

- **信息级**：本批占用 `0003_0140`~`0003_0148`（连续九码，接续 R10 的 `0138`~`013F`，无空档、无回填）。
- **故障级**：本批占用 `0003_0300`~`0003_0308`（九码，按组件成组分配：`0300`/`0301`/`0307` 归端口诊断聚合、`0302` 归状态字段解码、`0303`/`0304` 归 NTC 巡检、`0305`/`0306`/`0308` 归辊距调整）。
- **上界突破**：本子库原故障码段声明为「信息级 `01xx` ｜ 故障级 `02xx` 起段」，R10 已用到 `02F9`，**`02xx` 段可用空间仅剩 `02FA`~`02FF` 六码，不足以容纳本批九码**。故本批**显式开辟 `0300`~`0308` 新子块**，并将本子库故障码上界由 `02FF` 提升至 `0308`。
- **上界新规**：`16#0003_xx00`~`xxFF` 的第二字节空间此后按「`01xx` 信息级 / `02xx` 故障级 / `03xx` 故障级扩展块」三段划分；后续本子库故障码**先顺延 `0309`~`03FF`**，该子块用尽后再开 `0400`，**禁止回填 `02FA`~`02FF` 残余六码**（避免新旧码语义交叠、HMI 码表分组错位）。此规矩已同步至 `LIBRARY_MANUAL.md` 故障码总表。
- **终审逐码求差**：`0300`~`0308` 与 `DL_Base`（`0001_xxxx` / `0002_xxxx`）、`DL_MathData`（`0001_xxxx`）、`DL_Algo`（`0002_xxxx`）、`DL_Motion`（`0004_xxxx`）、`DL_Process`（`0005_xxxx`）零交集；本批信息级九码与 R10 存量 `0138`~`013F` 亦零交集。

### 存量修复 / Fixed（R11 批次顺带治理，4 件）

| 组件 / Component | 旧 → 新 | 缺陷 / Defect |
|---|---|---|
| `FB_DL_PneumaticCylinder` | 1.0.0 → **1.0.1** | 段 2 行程计数赋值目标笔误 `_uCycleCount`（带下划线前缀但未在 `VAR` 区声明，同名输出 `uCycleCount` 全文零写入）→ 三平台编译阻断；已改为 `uCycleCount`，逻辑本体零改动 / Assignment target erratum blocking compilation on all three platforms |
| `FB_DL_SingleSolenoidCyl` | 1.0.0 → **1.0.1** | 同上（同一处笔误、同一修法、同一批次发现） / Same erratum and same fix |
| `I_DL_AnalogSensor` | 1.0.0 → **1.0.1** | 枚举成员分隔符笔误：`eWireBreakLow` / `eWireBreakHigh` 两行误写单冒号 `:`（IEC 61131-3 枚举成员赋值须 `:=`）→ 三平台编译阻断；数值与语义不变 / Enum member separator `:` → `:=` on two members |
| `I_DL_FlowMeter` | 1.0.0 → **1.0.1** | 同上：`eFlowOk` / `eLowCutoff` 两行单冒号 → `:=` / Same enum separator fix on two members |

### 变更说明 / Change Notes

- **三者数据源不同、互不可替**：`FB_DL_AxiolineDiagLatch`（本地总线**模块级**，槽号 + 位域诊断锁存）/ `FB_DL_PdiReadScheduler`（参数对象**读取调度**）/ 本批 `FB_DL_PortDiagAggregator`（**端口级**：链路位 + 端口码 + CRC 计数聚合），码段亦不共享（前者 `013x`/`02Fx`，本件 `0140`/`0141`/`030x`）。
- **位段解码族补齐「组态级」维度**：`FC_DL_BitGet`（单个位）/ `FB_DL_UnpackWordToBits`（固定 16 位）/ `FC_DL_BitFieldExtract`（单段）/ `FC_DL_WordBitPack`（单段打包）四件均为「单点」件；`FB_DL_StatusWordSegDecoder` 是 N 段批量解码 + 段间重叠诊断的组态级件，且段提取在本块内自写、不调用上述任何单段件。
- **测量与执行分离**：`FB_DL_NtcTempScan` 只做测量与判定、不产生任何控制输出；控温执行仍归 `FB_DL_HeatCoolZone`。`FB_DL_RollerGapAdjust` 只出位置指令与到位状态，不做轴级运动规划。
- **头注释版本号滞后（如实记录，本轮文档线不改 `.st`）**：`I_DL_AnalogSensor` / `I_DL_FlowMeter` 文件头「当前版本」仍为 `1.0.0`，而修订历史已记 `v1.0.1`；以修订历史与本文档为准，待代码线下次触碰时一并订正。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0（终审断言脚本复跑）。

---

## v0.6.0 ｜ 2026-11-15 ｜ R10 RFID 契约-实现对 + 现场总线诊断双件（T2-6 Rockwell AOI / T1-7 PLCnext 双开组，4 件）/ R10 RFID Pair & Fieldbus Diagnostics

**变更性质**：MINOR（新增 4 个组件；其中 3 件终审修复后 v1.0.1），无破坏性变更，无迁移动作。对应 Round 10「DL_Device RFID 族 + 现场总线诊断族」（来源标签 tcopen-component / rockwell-aoi / plcnext-community，RAW_NOTES_R10 S-6/S-7/S-8/S-9）。**本轮为两个源矩阵行的首次开组**：**T2-6 Rockwell AOI ☐→◐**（AOI 参数四分段 + External Access 等级 → 本库「方法 / 只读属性 / 诊断结构 / 局部」四段；ProgFault/OperFault → 组态类/工艺类双码段）、**T1-7 PLCnext Community ☐→◐**（Axioline 诊断寄存器位语义 + PDI 参数域 + 无环通信纪律）。终审 **PASS with fixes**：`FB_DL_RfidTagHandler`（D-11 未使用入参、D-14 诊断字段说明）、`FB_DL_AxiolineDiagLatch`（D-05 严重：屏蔽计数同拍装载又递减致屏蔽恒 0；D-09 未判使能；D-12 事件计数语义）、`FB_DL_PdiReadScheduler`（D-10 超时未钳位致重试风暴；D-13 码表语义）三件 → v1.0.1；`I_DL_RfidReader` 零修改 PASS。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 33 | `I_DL_RfidReader` | 接口 | 164 | 1.0.0 | tcopen-component / rockwell-aoi | RFID 读写头标准契约：随文件发布四 DUT（`E_DL_RfidState` 五态步长 10 / `ST_DL_RfidTag` / `ST_DL_RfidDiag` / `ST_DL_RfidCfg`）+ 只读属性 3（State/Tag/Diag）+ 方法 4（Init/ReadTag/WriteTag/Reset，均带受理返回值）；MAP 按 AOI External Access 等级落地 / RFID reader contract with AOI-style segmentation |
| 34 | `FB_DL_RfidTagHandler` | FB | 582 | **1.0.1** | tcopen-component / rockwell-aoi | RFID 读写实现（IMPLEMENTS）：五态握手（eIdle/eWaitHw/eVerify/eRetry/eFault）+ 写后回读校验 + 超时重试链 + 同标签重复读抑制窗 + 硬件原始错误码透传（`bHwError` 拍写 `uLastErrorId`，块级码非零时才覆盖）+ 请求/方向电平输出 `bHwReq`/`bHwWr` / RFID handler with verify-after-write and duplicate suppression |
| 35 | `FB_DL_AxiolineDiagLatch` | FB | 398 | **1.0.1** | plcnext-community | Axioline 诊断寄存器解析与首出锁存：7 位状态位映射（PF/PW/BUS/RUN/ACT/RDY/SYSFAIL，位序本库自有）+ 错误码/槽号双寄存器 + **128 特例（无法定位不伪装成 128 号槽）** + 四级诊断等级 + 稳定窗去抖 + 首出槽号与码同拍锁存 + 确认沿屏蔽 N 拍 / Axioline diagnostics register parser with first-out latch |
| 36 | `FB_DL_PdiReadScheduler` | FB | 411 | **1.0.1** | plcnext-community | PDI（Parameters/Diagnostics/Information）异步读取调度：Slot/Subslot/Index/Subindex 四元参数域 + 单拍只发一条（忙时拒绝不排队）+ 超时钳位（`tTmoUse := LIMIT(...)` 防 `PT = 0` 重试风暴）+ 长度校验 + 双码打包（高 16 位 AddInfo / 低 16 位 ErrorCode）+ 连续三轮失败锁故障 / PDI object read scheduler with dual-code packing |

### 故障码台账追加（R10 码位登记，经终审全库复核）/ Error Code Ledger Additions (R10)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0003_0138` | 信息级 | 同标签重复读被抑制窗拦下 | FB_DL_RfidTagHandler |
| `0003_0139` | 信息级 | 指令超时或抑制窗参数越界被钳位 | FB_DL_RfidTagHandler |
| `0003_013A` | 信息级 | 重试次数越界被钳位 | FB_DL_RfidTagHandler |
| `0003_02F0` | 故障级（组态使用类） | 未初始化、忙时重入或写入内容非法 | FB_DL_RfidTagHandler |
| `0003_02F1` | 故障级（组态类） | 超时重试耗尽 | FB_DL_RfidTagHandler |
| `0003_02F2` | 故障级（工艺类） | 读写头报错重试耗尽 | FB_DL_RfidTagHandler |
| `0003_02F3` | 故障级（工艺类） | 写后回读校验不符或非法状态兜底 | FB_DL_RfidTagHandler |
| `0003_013B` | 信息级 | 槽号非法（> 127 且 ≠ 128），按无位置处理 | FB_DL_AxiolineDiagLatch |
| `0003_013C` | 信息级 | 诊断块未使能，实时位已清零、锁存保留 | FB_DL_AxiolineDiagLatch |
| `0003_02F4` | 故障级 | 诊断位有效但错误码为 0（状态与参数寄存器不自洽） | FB_DL_AxiolineDiagLatch |
| `0003_02F5` | 故障级 | 非法状态兜底 | FB_DL_AxiolineDiagLatch |
| `0003_02F6` | 故障级 | 总线就绪丢失超时 | FB_DL_AxiolineDiagLatch |
| `0003_013D` | 信息级 | 槽号或子槽号越界被钳位 | FB_DL_PdiReadScheduler |
| `0003_013E` | 信息级 | 索引或子索引越界被钳位 | FB_DL_PdiReadScheduler |
| `0003_013F` | 信息级 | 期望长度或单次超时越界被钳位 | FB_DL_PdiReadScheduler |
| `0003_02F7` | 故障级 | 本次读取失败或超时且重试耗尽 | FB_DL_PdiReadScheduler |
| `0003_02F8` | 故障级 | 非法状态兜底 | FB_DL_PdiReadScheduler |
| `0003_02F9` | 故障级 | 同一请求连续三轮失败，锁定 | FB_DL_PdiReadScheduler |

### 变更说明 / Change Notes

- **码段扩块（R30 口径）**：R10 四件较 R9 的 `0003_013x` / `02Ex` 顺延到 **`0003_0138~013F` 与 `0003_02F0~02F9`**，新增 **`02F0~02F9` 的「AOI ProgFault / OperFault 双类故障」子块**（`02F0~02F1` 组态类 / `02F2~02F3` 工艺类），并区分「组态使用类 / 组态类 / 工艺类」三种归因，供 HMI 按类分组显示。全库求差断言通过。
- **接口契约纪律**：`I_DL_RfidReader` 的四 DUT 随接口文件同文件发布（契约优先），实现块只 `IMPLEMENTS` 不重复声明；方法均返回 BOOL 受理值且忙时拒绝，静默失败禁令（R24 家族）。
- **已知限制 / 观察项**：O-4 `FB_DL_RfidTagHandler` 的 `Init` 形参 `stCfg` 与块级引脚同名遮蔽（方法体不引用形参，组态以块级引脚为准），下一 MAJOR 改名 `stInitCfg`；`I_DL_RfidReader` 保留 METHOD 内联成员写法（与全库 152 件一致，非缺陷）。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.5.0 ｜ 2026-11-15 ｜ R9 开环步进族契约-实现对（T1-8 GitHub topics ☐→◐ 开组）/ R9 Open-Loop Stepper Pair

**变更性质**：MINOR（新增 2 个组件）+ PATCH（1 个文件终审修复 → v1.0.1），无破坏性变更，无迁移动作。对应 Round 09「DL_Device 开环步进族」（来源标签 stepper，**T1-8 GitHub topics 开组**：MIT 许可 AccelStepper 及同类公开仓库的梯形加减速脉冲频率规划算法思想 + 参数域惯例，TcOpen 分层范式复用，clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 31 | `I_DL_StepperOpenLoop` | 接口 | 130 | 1.0.0 | stepper | 开环步进（脉冲+方向）抽象契约：配套结构体 `ST_DL_StepperCfg`（脉冲当量/细分/最大速度/加减速度/堵转裕度/任务周期）+ 只读属性 3（bReady/fPosition/uAlarmWord）+ 方法 6（Init/Enable/MoveRelative/Stop/Reset/GetErrorId，恰在 ≤6 红线临界）；fPosition 强制声明「开环推算值，禁止当编码器反馈」 / Open-loop stepper interface contract |
| 32 | `FB_DL_PulseDirStepper` | 功能块 | 564 | **1.0.1** | stepper | 脉冲+方向开环步进控制器（IMPLEMENTS `I_DL_StepperOpenLoop`）：梯形加减速脉冲频率规划（短行程退化三角型）+ 限位保护（同向停发锁故障、电平判据持续拒同向）+ 堵转超时判据（理论耗时 × 1.5 + 裕度）+ 定宽一拍脉冲（R24）；**v1.0.1 致命修复：eDecel 补「频率归零即收尾」第二出口**（原仅步数归零出口，残差为小数时永久卡死无故障码），新增信息级 0003_0137 / Pulse-direction stepper with trapezoidal planning and stall judge |

### 故障码台账追加（R9 码位登记，经终审复核成立）/ Error Code Ledger Additions (R9)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0003_0130` | 信息级 | 速度指令超最大速度已钳位 | FB_DL_PulseDirStepper |
| `0003_0131` | 信息级 | 脉冲频率超任务周期上限已钳位（保证脉宽下限一拍，R24） | FB_DL_PulseDirStepper |
| `0003_0132` | 信息级 | 位移不足一个脉冲当量被忽略 | FB_DL_PulseDirStepper |
| `0003_0133` | 信息级 | 运动/复位指令被拒绝（状态不满足） | FB_DL_PulseDirStepper |
| `0003_0134` | 信息级 | 限位方向禁止（同向指令被拒，反方向恒受理） | FB_DL_PulseDirStepper |
| `0003_0135` | 信息级 | 去使能冻结脉冲输出（无半脉冲） | FB_DL_PulseDirStepper |
| `0003_0136` | 信息级 | 任务周期非法已兜底为 10 ms | FB_DL_PulseDirStepper |
| `0003_0137` | 信息级 | 减速收尾残差不足一脉冲，按到位处理（v1.0.1 新增） | FB_DL_PulseDirStepper |
| `0003_02E0` | 故障级 | 组态参数非法（Init 参数域越界） | FB_DL_PulseDirStepper |
| `0003_02E1` | 故障级 | 限位入侵停机（运动中同向限位触发） | FB_DL_PulseDirStepper |
| `0003_02E2` | 故障级 | 驱动器报警输入有效 | FB_DL_PulseDirStepper |
| `0003_02E3` | 故障级 | 堵转超时（超理论耗时乘裕度） | FB_DL_PulseDirStepper |
| `0003_02E4` | 故障级 | 非法状态兜底（枚举越界） | FB_DL_PulseDirStepper |

- **码位泳道自行顺延复核成立**：原拟 02E0~02E4 避开 VacuumEjector（0230~0232）与 StarDeltaMotor（0240~0246）占用，终审逐码回溯核实无冲突；新增 0137 复核空闲。
- **D-02 致命教训**：状态机「终态可达性」不能只查出口存在——eDecel 原出口判据（步数归零）与脉冲发生条件（频率 > 0.1 Hz）在减速段一拍归零场景下互相矛盾，属无故障码的静默死锁；验收向量必须覆盖「频率先于步数归零」的收尾路径（终审 V5 已验证）。

### 变更说明 / Change Notes

- **契约-实现分离（TcOpen 范式第四批落地）**：`ST_DL_StepperCfg` 随接口文件发布，`E_DL_StepperState` 归实现块文件，零跨文件重复声明；7 条跃迁契约（未 Init 拒绝 / 去使能本拍冻结无半脉冲 / 运行中拒新指令 / 限位电平拒同向 / Stop 受控停车 / 报警源未消失复位不解除 / 跃迁语义变化走 MAJOR）写死于接口头注释。
- **故障不切使能**：`bEnableOut` 恒透传使能指令，故障期保持力矩（垂直轴防溜车），切动力由上层安全回路决定。
- **红线状态**：R1~R8 全部通过，机检 0 命中；接口方法数 = 6（≤6 临界）；接口 3 属性 + 6 方法与实现块逐项对齐（终审第 8 项核验通过）。

---

## v0.4.0 ｜ 2026-11-15 ｜ R8 三色安灯塔契约-实现对（T1-5 TcOpen 深化）/ R8 Tower Light Pair

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 08「DL_Device 状态指示族」（来源标签 tcopen-component/stack-light，T1-5 TcOpen 组件范式深化——R7 收口线漏记 2 件经总监授权补记 T1-5 行，见 `SOURCE_HUNTING_MATRIX.md`）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 29 | `I_DL_TowerLight` | 接口 | 1.0.0 | tcopen-component/stack-light | 工业安灯塔标准契约（三/四色塔灯 + 蜂鸣）：随文件发布三枚举（`E_DL_TowerColor` 六色 / `E_DL_TowerPattern` 五模式 / `E_DL_TowerState` 七显示态）+ 只读属性 10 个（含 bBuzzer/bSilenced/bError/uErrorId）+ 方法 3 个（SetColor/SilenceBuzzer/Reset，均带受理返回值）；上层按接口编程可适配直驱型 / 模块化集束型 / IO-Link 总线型三类实现 / Andon tower light interface contract |
| 30 | `FB_DL_SignalTower` | 功能块 | 1.0.0 | tcopen-component/stack-light | 安灯塔参考实现（IMPLEMENTS `I_DL_TowerLight`）：七级主级仲裁（安全事件 > 故障未确认 > 故障已确认 > 预警 > 求助 > 手动 > 自动）+ 人工覆盖（SetColor，被更高优先级压制时拒绝）+ 消音保持窗（安全事件不受消音约束）+ 慢/快闪半周期可调（T#0S 退化常亮）+ 红绿互斥出口断言 + 五路灯电平与蜂鸣输出 / Signal tower reference implementation with 7-level arbitration |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_TowerColor` / `E_DL_TowerPattern` / `E_DL_TowerState`（随 #29，三枚举归属接口同文件发布）——共 3 个；`FB_DL_SignalTower` 引用不重复声明。

### 故障码台账追加（R8）/ Error Code Ledger Additions

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0003_0123` | 信息级 | 闪频参数为零已退化常亮 | FB_DL_SignalTower |
| `0003_0124` | 信息级 | 消音到期自动恢复蜂鸣 | FB_DL_SignalTower |
| `0003_0125` | 信息级 | 消音时长为零即永续消音 | FB_DL_SignalTower |
| `0003_0126` | 信息级 | 手动与自动同真，手动优先 | FB_DL_SignalTower |
| `0003_02D0` | 故障级 | 红绿同亮出口断言冲突（外部引脚无法构造，防御性锁存） | FB_DL_SignalTower |
| `0003_02D1` | 故障级 | 非法显示状态 | FB_DL_SignalTower |

经子库码表核对顺延（设备件十件套占用 `0003_0113~0122 / 0280~02C0`，本族 0123~0126 / 02D0~02D1 无冲突），冲突 0。

### 变更说明 / Change Notes

- **契约-实现分离（T1-5 范式第三批落地）**：接口层不做任何电平输出（灯与蜂鸣物理通道由实现块输出引脚给出）、不读任何现场输入（状态位由实现块引脚注入）；方法均为非阻塞单发语义，返回值仅表示「请求是否被受理」。
- **安全事件不消音**：`SilenceBuzzer` 在安全事件期返回 FALSE——急停/安全门/光幕引发的蜂鸣不受消音约束，消音保持窗到期自动恢复（信息级 0124）。
- **红绿互斥出口断言**：仲裁后红/绿中间电平经出口断言（IF 结构保证）校验不同真；断言对触发锁存 `0003_02D0`（正常仲裁流不可达，纯防御）。
- **方法-引脚双通道并存**：`SetColor` 方法请求与引脚状态注入二选一使用；方法请求置人工覆盖（被更高主级压制时拒绝并返回 FALSE），引脚状态走七级主级仲裁表。
- **闪频时基纪律**：慢/快闪半周期由引脚给定（`tFlashSlow`/`tFlashFast`），禁读任何内部时钟源（公约 0.10）；半周期为零退化为常亮（信息级 0123）。
- **红线状态**：R1~R7 全部通过，机检 0 命中；接口方法数 = 3（≤6）；实现块属性组 10 个逐一兑现无声明未实现/实现未声明（终审逐项核验）。

---

## v0.3.0 ｜ 2026-11-15 ｜ R7 设备件十件套（T1-5 TcOpen 组件范式 ☐→◐ 开组）/ R7 Device Ten-Piece Set

**变更性质**：MINOR（新增 10 个组件）+ PATCH（2 个文件终审修复 → v1.0.1），无破坏性变更，无迁移动作。对应 Round 07「DL_Device 扫码枪/安全门/光幕/流量计/料位开关五条产线」（来源标签 tcopen-component / scanner-handshake / safety-interlock / light-curtain-muting / flow-totalizer / level-switch-failsafe，TcOpen 分层思想 + ISO 14119 / SICK mut_p 等公开语义 clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 19 | `I_DL_BarcodeScanner` | 接口 | 1.0.0 | tcopen-component/scanner-handshake | 固定式扫码枪标准契约：`E_DL_ScannerState` 六态（步长 10）+ 属性 8 + 方法 3（Trigger/Ack/Reset）；串口收发经实现块 IN_OUT 注入 / Fixed barcode scanner interface contract |
| 20 | `FB_DL_SerialScanner` | 功能块 | **1.0.1** | tcopen-component/scanner-handshake | 扫码枪触发-结果握手状态机：NoRead 自动重试→升级故障锁存、长度校验 + CR/LF 剥离锁存、TP 定宽触发（R24 范式）、bDataAck 消费应答（v1.0.1：重试链断裂 + 应答同拍回落两处修复） / Scanner handshake state machine with retry escalation |
| 21 | `I_DL_SafetyDoor` | 接口 | 1.0.0 | tcopen-component/safety-interlock | 安全门联锁（电磁锁扣）契约：解锁时序七态 + 属性 7 + 方法 4（RequestUnlock/Relock/Reset/AuditClear）；不构成认证安全功能（公约 0.13） / Guard-lock safety door interface (ISO 14119 semantics) |
| 22 | `FB_DL_GuardLockDoor` | 功能块 | 1.0.0 | tcopen-component/safety-interlock | 安全门联锁控制器：请求停机 → 静止确认（零速/run-down 二选一）→ 解锁 → 开门审计 → 再锁定确认窗 → 复位后重启；防篡改冲突全局监视、解锁出口断言 / Guard-lock door interlock controller |
| 23 | `I_DL_LightCurtain` | 接口 | 1.0.0 | tcopen-component/light-curtain-muting | 安全光幕契约：`E_DL_CurtainState` 五态 + 属性 7（核心安全镜像位 bSafeStop）+ 方法 3（Override/Ack/Reset） / Light curtain monitoring & muting interface |
| 24 | `FB_DL_SafetyLightCurtain` | 功能块 | **1.0.1** | tcopen-component/light-curtain-muting | 序列式屏蔽状态机：2/4 传感器正向/反向序列（首遮挡传感器判向）、错乱即退出屏蔽 + 故障、屏蔽总时长超时、override 硬帽、OSSD 双通道容差窗、屏蔽灯常亮/闪烁（v1.0.1：反向判向死代码 + E2 双清离分支两处修复） / Sequential muting light curtain |
| 25 | `I_DL_FlowMeter` | 接口 | 1.0.0 | tcopen-component/flow-totalizer | 流量计契约：`E_DL_FlowMeterState` 五态 + 属性 6（fFlowRate/fTotal/nPulseCount）+ 方法 3（TotalReset/TotalPreset/Reset） / Flow meter interface with totalizer methods |
| 26 | `FB_DL_PulseFlowMeter` | 功能块 | 1.0.0 | tcopen-component/flow-totalizer | 脉冲流量计量：自重触发采样窗频率估计 → K 系数换算 [L/min]、总量脉冲计数法双缓冲读侧无撕裂、低流量截止、脉冲丢失超时、LREAL 精度边界预警 / Pulse flow meter with dual-buffer windowing |
| 27 | `I_DL_LevelSwitch` | 接口 | 1.0.0 | tcopen-component/level-switch-failsafe | 料位开关契约：`E_DL_LevelState` + `E_DL_FailSafeMode`（HIGH 防溢流 / LOW 防干转）双枚举 + 属性 6 + 方法 2（Reset/Test） / Level switch interface with fail-safe direction modes |
| 28 | `FB_DL_LevelSwitchVib` | 功能块 | **1.0.1** | tcopen-component/level-switch-failsafe | 振动叉料位开关处理：防抖 → 失效安全方向归一（IF 显式写禁 XOR 裸用）→ 覆盖/裸露双延迟确认 → 双联锁输出；使能切断强制镜像安全侧（v1.0.1：测试沿误接使能修复） / Vibrating-fork level switch conditioning |

### 变更说明 / Change Notes

- **契约-实现分离**：五条产线均为「`I_DL_*` 契约 + `FB_DL_*` 实现」，接口属性同名成员按 R22 以只读 PROPERTY GET 承载；接口层不做串口收发、不写物理输出、不读 OSSD 之外的物理输入。
- **定位声明（公约 0.13）**：安全门/光幕两族为标准 PLC 逻辑编排与诊断镜像层，不构成 ISO 13849 / IEC 62061 认证安全功能，安全回路由认证安全控制器承载。
- **故障码台账追加（R7）**：`0003_0113~0122`（信息级）、`0003_0280~0282 / 0290~0293 / 02A0~02A2 / 02B0 / 02C0`（故障级），全部经子库码表核对顺延（规格建议码位与既有组件冲突 5 处，依公约 0.8「核对结果优先」）。
- **终审修复（v1.0.1，4 个文件 6 处缺陷）**：`FB_DL_SerialScanner`（致命：重试链断裂——`_nRetry` 误在过渡态清零；工程语义：bDataAck 同拍回落恒不可见）、`FB_DL_SafetyLightCurtain`（反向判向死代码 + E2 双清离分支缺失）、`FB_DL_LevelSwitchVib`（测试沿误接使能）。
- **红线状态**：R1~R7 全部通过，机检 0 命中；接口方法数 ≤6；R23 事件型免首扫逐条落实。

## v0.2.0 ｜ 2026-11-15 ｜ R6 阀门/驱动族深化 / R6 Valve & Drive Family Deepening

**变更性质**：MINOR（新增 10 个组件），无破坏性变更，无迁移动作。对应 Round 06（R6）「DL_Device 阀门/驱动族」（来源标签 lbp-basic-process / lbp-device，T2-2 LBP clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 9 | `FB_DL_SingleSolenoidCyl` | 功能块 | 1.0.0 | lbp-basic-process+lbp-device | 单电控弹簧复位气缸驱动（复用既有 `I_DL_Cylinder` 契约）：纯时间模式 / 可选磁开双重校验、联锁失电保位、行程计数 / Single-solenoid spring-return cylinder driver |
| 10 | `I_DL_VacuumGenerator` | 接口 | 1.0.0 | lbp-basic-process+lbp-device | 真空发生器标准抽象契约：状态枚举 `E_DL_VacuumState`（随文件发布）+ 属性 5 个（含负压反馈值 [kPa]）+ 方法 4 个 / Vacuum generator interface contract |
| 11 | `FB_DL_VacuumEjector` | 功能块 | **1.0.1** | lbp-basic-process+lbp-device | 真空发生器驱动：负压迟滞判定（负压域施密特）、建立超时、TP 定宽吹气脉冲、可选开关双确认、反馈失效锁存 / Vacuum ejector driver with blow-off pulse |
| 12 | `FB_DL_StarDeltaMotor` | 功能块 | **1.0.1** | lbp-basic-process+lbp-device | 星三角降压启动（三接触器）：星角死区时间互锁（50~200 ms 域）、三路接触器反馈校验、星角互斥出口断言、过载锁存、重启抑制冷却 / Star-delta starter with dead-time interlock |
| 13 | `I_DL_VfdDrive` | 接口 | 1.0.0 | lbp-basic-process+lbp-device | 通用变频器抽象契约：状态枚举 `E_DL_VfdState` + 属性 6 个 + 方法 6 个（Run/Stop/Jog/SetFrequency/SelectPresetSpeed/Reset，达 ≤6 红线临界）/ Generic VFD interface contract |
| 14 | `FB_DL_VfdGeneric` | 功能块 | **1.0.1** | lbp-basic-process+lbp-device | 通用端子型变频器驱动：正反转互斥（冲突安全侧停止）、点动优先、多段速选择、频率模拟量 0~100% 线性映射、故障复位端子定宽脉冲 / Generic terminal-type VFD driver |
| 15 | `I_DL_ProportionalValve` | 接口 | 1.0.0 | lbp-basic-process+lbp-device | 比例调节阀抽象契约：状态枚举 `E_DL_ValveState` + 属性 6 个（含偏差报警）+ 方法 3 个 / Proportional valve interface contract |
| 16 | `FB_DL_AnalogValve` | 功能块 | **1.0.1** | lbp-basic-process+lbp-device | 模拟量调节阀指令整形层：钳位 → 零点死区补偿 → 限幅域映射（对调自修复）、偏差延时报警、反馈失效保持末次有效值；不含闭环 / Analog valve command shaping layer |
| 17 | `I_DL_MotorizedValve` | 接口 | 1.0.0 | lbp-basic-process+lbp-device | 电动调节阀抽象契约：状态枚举 `E_DL_MotorValveState` + 属性 6 个（估算开度 + 双限位）+ 方法 4 个 / Motorized valve interface contract |
| 18 | `FB_DL_ThreePointValve` | 功能块 | **1.0.1** | lbp-basic-process+lbp-device | 三点浮点式电动阀：开/关双脉冲输出、行程时间积分自动估算开度、限位锚定/端点拒绝双保险、估算-限位一致性监视 / Three-point floating valve with position estimation |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_VacuumState`（随 `I_DL_VacuumGenerator`）、`E_DL_VfdState`（随 `I_DL_VfdDrive`）、`E_DL_ValveState`（随 `I_DL_ProportionalValve`）、`E_DL_MotorValveState`（随 `I_DL_MotorizedValve`）——共 4 个，与各自接口文件同文件发布；`FB_DL_SingleSolenoidCyl` 复用既有 `E_DL_CylinderState`、`FB_DL_StarDeltaMotor` 复用既有 `E_DL_MotorState`（禁止重定义）。

### 故障码台账追加 / Error Code Ledger Additions

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0003_0106` | 信息级 | 正反转指令冲突（冲突安全侧停止） | FB_DL_VfdGeneric |
| `0003_0107` | 信息级 | 频率设定钳位 / 段速选择越界（按 0 处理） | FB_DL_VfdGeneric |
| `0003_0108` | 信息级 | 阀位设定值钳位 | FB_DL_AnalogValve |
| `0003_0109` | 信息级 | 输出限幅域对调自修复 | FB_DL_AnalogValve |
| `0003_0110` | 信息级 | 端点指令拒绝（限位确认端点 / 无限位端点双保险） | FB_DL_ThreePointValve |
| `0003_0111` | 信息级 | 开/关双向指令冲突（双脉冲全断） | FB_DL_ThreePointValve |
| `0003_0112` | 信息级 | 偏差报警激活（瞬时型每拍重算） | FB_DL_AnalogValve |
| `0003_0208` | 信息级 | 重启抑制期启动拒绝（与 `FB_DL_DolMotor` 同码同义共用，终审归一裁定；`0003_0105` 空置不分配） | FB_DL_StarDeltaMotor |
| `0003_0220` | 故障级 | 伸出到位超时（磁开窗内未确认） | FB_DL_SingleSolenoidCyl |
| `0003_0221` | 故障级 | 反馈校验失败（缩回时间到位但磁开超窗未确认） | FB_DL_SingleSolenoidCyl |
| `0003_0222` | 故障级 | 非法状态兜底 | FB_DL_SingleSolenoidCyl |
| `0003_0230` | 故障级 | 负压反馈信号无效（非有限值/失效） | FB_DL_VacuumEjector |
| `0003_0231` | 故障级 | 真空建立超时 / 反馈校验失败 | FB_DL_VacuumEjector |
| `0003_0232` | 故障级 | 非法状态兜底 | FB_DL_VacuumEjector |
| `0003_0240` | 故障级 | 主接触器拒动（校验窗内未吸合） | FB_DL_StarDeltaMotor |
| `0003_0241` | 故障级 | 星接触器拒动 | FB_DL_StarDeltaMotor |
| `0003_0242` | 故障级 | 星接触器分断失败（死区满仍吸合） | FB_DL_StarDeltaMotor |
| `0003_0243` | 故障级 | 星角互斥冲突（出口断言对触发） | FB_DL_StarDeltaMotor |
| `0003_0244` | 故障级 | 运行中反馈意外断开（失反馈脱扣） | FB_DL_StarDeltaMotor |
| `0003_0245` | 故障级 | 热继电器过载脱扣（锁存） | FB_DL_StarDeltaMotor |
| `0003_0246` | 故障级 | 星角转换失败（角接触器窗内未吸合） | FB_DL_StarDeltaMotor |
| `0003_0250` | 故障级 | 驱动故障（反馈锁存） | FB_DL_VfdGeneric |
| `0003_0251` | 故障级 | 启动反馈超时 | FB_DL_VfdGeneric |
| `0003_0252` | 故障级 | 非法状态兜底 | FB_DL_VfdGeneric |
| `0003_0260` | 故障级 | 阀位反馈信号无效 | FB_DL_AnalogValve |
| `0003_0261` | 故障级 | 非法状态兜底 | FB_DL_AnalogValve |
| `0003_0270` | 故障级 | 行程估算失准（估算与限位矛盾超容差） | FB_DL_ThreePointValve |
| `0003_0271` | 故障级 | 双限位冲突（物理不可能） | FB_DL_ThreePointValve |
| `0003_0272` | 故障级 | 非法状态兜底 | FB_DL_ThreePointValve |
| `0003_0113` | 信息级 | 低流量截止激活（瞬时型每拍重算） | FB_DL_PulseFlowMeter |
| `0003_0114` | 信息级 | 脉冲丢失超时（瞬时型） | FB_DL_PulseFlowMeter |
| `0003_0115` | 信息级 | 窗内频率超量程（提示输入层配置 HSC） | FB_DL_PulseFlowMeter |
| `0003_0116` | 信息级 | 传感器信号静默提示（预留信息级，本轮不触发） | FB_DL_LevelSwitchVib |
| `0003_0117` | 信息级 | 单次 NoRead 结果提示（瞬时型） | FB_DL_SerialScanner |
| `0003_0118` | 信息级 | override 硬帽到期退出（瞬时型） | FB_DL_SafetyLightCurtain |
| `0003_0119` | 信息级 | 条码超长截断 | FB_DL_SerialScanner |
| `0003_0120` | 信息级 | 无设备就绪门控跳过（一次性提示） | FB_DL_SerialScanner |
| `0003_0121` | 信息级 | run-down 计时器模式提示（非零速实测） | FB_DL_GuardLockDoor |
| `0003_0122` | 信息级 | override 准入拒绝（无遮挡） | FB_DL_SafetyLightCurtain |
| `0003_0280` | 故障级 | 连续 NoRead 超限 | FB_DL_SerialScanner |
| `0003_0281` | 故障级 | 设备长时间无就绪 | FB_DL_SerialScanner |
| `0003_0282` | 故障级 | 非法状态兜底 | FB_DL_SerialScanner |
| `0003_0290` | 故障级 | 静止确认超时（解锁链未达成） | FB_DL_GuardLockDoor |
| `0003_0291` | 故障级 | 门锁不合理组合（防篡改冲突） | FB_DL_GuardLockDoor |
| `0003_0292` | 故障级 | 再锁定超时 | FB_DL_GuardLockDoor |
| `0003_0293` | 故障级 | 非法状态兜底 | FB_DL_GuardLockDoor |
| `0003_02A0` | 故障级 | 屏蔽传感器序列错误 | FB_DL_SafetyLightCurtain |
| `0003_02A1` | 故障级 | 屏蔽超时 | FB_DL_SafetyLightCurtain |
| `0003_02A2` | 故障级 | OSSD 双通道不一致 | FB_DL_SafetyLightCurtain |
| `0003_02B0` | 故障级 | K 系数非法（防除零锁存） | FB_DL_PulseFlowMeter |
| `0003_02C0` | 故障级 | 失效安全模式枚举越界 | FB_DL_LevelSwitchVib |


### 变更说明 / Change Notes

- **接口契约**：4 个新接口（`I_DL_VacuumGenerator` / `I_DL_VfdDrive` / `I_DL_ProportionalValve` / `I_DL_MotorizedValve`）按「状态枚举 + 属性（PROPERTY GET）+ 方法」三段式定义，方法数全部 ≤6（`I_DL_VfdDrive` 恰为 6，临界合规）；实现块属性组逐一兑现，无声明未实现/实现未声明（终审逐项核验）。
- **终审修复（8 个文件 → v1.0.1）**：`FB_DL_VacuumEjector`（致命：吹气脉冲请求同拍置位/自清导致 TP 恒 FALSE，自清移至实例调用之后）、`FB_DL_VfdGeneric`（致命：故障复位脉冲同型缺陷，同法修复）、`FB_DL_StarDeltaMotor`（重启抑制码位归一 `0003_0208`）、`FB_DL_AnalogValve`（限幅域对调改为交换已防御生效值，杜绝非有限值穿透）、`FB_DL_ThreePointValve`（注释级对齐，逻辑零变更）。
- **TP/定宽脉冲范式（R24）**：本轮两处致命缺陷同模板，范式正式入册——触发请求自清必须位于实例调用之后；后续任何 TP/定宽脉冲组件按此执行。
- **阀门三分法（LBP 分类语义 clean-room）**：开关阀（气缸/真空）/ 比例阀（模拟量指令整形）/ 电动阀（脉冲 + 开度估算）三条产线互相独立，上层按「有没有阀位变送器、有没有定位器」选型。
- **依赖**：新增组件仅依赖 `Standard.library` 与库内既有契约（`I_DL_Cylinder` / `E_DL_MotorState`），无跨子库新依赖。

### 已知限制 / Known Limitations

1. `FB_DL_AnalogValve` 不含阀位闭环：闭环由驱动器/上层 PID 完成，本块为指令整形与诊断层（职责单一）。
2. `FB_DL_VfdGeneric` 为端子型惯例：点动频率不切换通道（段速 1 可整定为点动频率域或由驱动器内部点动组态承担）。
3. `FB_DL_ThreePointValve` 上电首扫若全关限位已压住，行程计数会即时 +1（限位态计数口径，±1 偏差，终审观察项留档）。
4. `FB_DL_StarDeltaMotor` eStopping 态反馈触点粘连时无限时等待（直至上层干预），留 ROADMAP 评估。
5. `FB_DL_VacuumEjector` 吹气采用 IEC 标准 TP（时间戳累积法经裁定弃用，需时钟基准），定宽由 TP 自身保持。

---

## v0.1.0 ｜ 2026-11-15 ｜ DL_Device 开库 / Initial Release — DL_Device Opening

**变更性质**：初始发布（Initial release），无破坏性变更，无迁移动作。全部 8 个组件自 v1.0.0（组件级）起入库，对应 Round 05（R5）「DL_Device 开库四件套」交付。

### 组件清单 / Component Inventory

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 1 | `I_DL_Cylinder` | 接口 | 1.0.0 | lbp-device | 双电控气缸标准抽象契约：状态枚举 `E_DL_CylinderState` + 只读属性 5 个 + 方法 4 个（Extend/Retract/Stop/Reset），故障态一律拒绝 / Standard double-solenoid cylinder interface contract |
| 2 | `FB_DL_PneumaticCylinder` | 功能块 | 1.0.0 | lbp-device | 双电控气缸驱动：磁开双通道消抖、双向超时自检、双传感器冲突锁存、双线圈互斥出口断言、联锁失电保位、行程计数 / Double-solenoid cylinder driver with debounce, timeout checks and conflict latch |
| 3 | `I_DL_MotorDriver` | 接口 | 1.0.0 | lbp-device | DOL 电机驱动器标准抽象契约：状态枚举 `E_DL_MotorState` + 属性 5 个（含重启抑制指示）+ 方法 3 个 / DOL motor driver interface contract |
| 4 | `FB_DL_DolMotor` | 功能块 | 1.0.0 | lbp-device | DOL 电机控制：指令-反馈校验窗、失反馈脱扣、过载锁存、最短运行时间监视、60 分钟桶滑窗每小时启动次数限制与重启抑制冷却 / DOL motor controller with contactor feedback window and restart inhibit |
| 5 | `I_DL_AnalogSensor` | 接口 | 1.0.0 | namur-ne43 | 模拟量变送器标准抽象契约（NAMUR NE43 语义域）：工程量值 + 信号质量分级枚举 + HH/H/L/LL 四级报警位 / Analog sensor interface contract with NE43 signal quality |
| 6 | `FB_DL_AnalogTransmitter` | 功能块 | 1.0.0 | namur-ne43 | NE43 语义变送器处理块：原始域四段诊断（断线/开路/欠量程/超量程）、滑动平均滤波、线性标定、故障态保持末次有效值、四级报警 / NE43 transmitter block with raw-domain diagnostics and hold-last-good-value |
| 7 | `I_DL_TemperatureZone` | 接口 | 1.0.0 | lbp-device | 加热/冷却温控区标准抽象契约：状态枚举 `E_DL_TempZoneState` + 属性 5 个 + 方法 3 个（SetSetpoint/CmdEnable/CmdReset）/ Heating/cooling temperature zone interface contract |
| 8 | `FB_DL_HeatCoolZone` | 功能块 | 1.0.0 | lbp-device | 双通道温控区控制器（R4 算法族首个上层消费者）：注入式 PID → 分程分配 → 双路 PWM SSR 驱动，断偶按方向切断并锁存 / Dual-channel zone controller composing injected PID, split-range and dual PWM instances |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_CylinderState`（随 #1）、`E_DL_MotorState`（随 #3）、`E_DL_SignalQuality`（随 #5）、`E_DL_TempZoneState`（随 #7）、`E_DL_BreakDir`（随 #6）、`E_DL_BreakAction`（随 #8）——共 6 个，与宿主文件同文件发布，导入 `.st` 即随宿主一并入库。

### 变更说明 / Change Notes

- **接口契约**：8 个组件的引脚名称、类型、方向、默认值与终审后源码声明区逐字一致；引脚级细节以 `DL_Device/*.st` 为准，完整接口表见 `MANUAL_DL_Device.md`。接口方法数全部 ≤6（`I_DL_MotionAxis` 例外归属 DL_Motion，本库拆分红线逐条通过）。
- **故障码**：全部使用 `16#0003_xxxx` 段：信息级 `0003_0101`（参数钳位/对调修复）、`0003_0102`（量程对调自修复）、`0003_0103`（欠/超量程提示）、`0003_0104`（量程退化回退）；故障级 `0003_0201`（非法状态）、`0003_0202/0203`（伸/缩超时）、`0003_0204`（双传感器冲突）、`0003_0205`（接触器拒动）、`0003_0206`（失反馈脱扣）、`0003_0209`（过载锁存）、`0003_0210`（NE43 故障态）、`0003_0211`（断偶锁存）、`0003_0212`（温控区非法状态）、`0003_0213`（传感器引用未注入）；信息级 `0003_0207/0208/020A`（启动次数超限/重启抑制拒绝/最短运行不足，不置 `bFault`）。完整表见 `MANUAL_DL_Device.md` 各节。
- **实现方式契约**：规格 OUT 列与接口属性同名的成员（如 `FB_DL_HeatCoolZone` 的 `fTempActual` 等 5 项）按 IEC 命名空间约束以只读 `PROPERTY GET` 形式实现（R11 留档 D1/D2），接口成员逐一兑现；`bExtended`/`bRetracted` 等在 `FB_DL_PneumaticCylinder` 中同时以 OUT 引脚 + 属性双形式暴露。
- **跨文件去重修复（R5 收口）**：`FB_DL_HeatCoolZone.st` 曾就地重复声明 `E_DL_SignalQuality` / `I_DL_AnalogSensor`，收口阶段已删除重复副本、统一引用 `I_DL_AnalogSensor.st` 正式定义（头注释 D2 闭环），功能与引脚零变更。
- **依赖收窄**：`FB_DL_AnalogTransmitter` 标定/滤波为内联等价实现（R11 留档③），后续可无缝外移至 `FC_DL_LinearScale` / `FB_DL_MovingAverage`；`FB_DL_PneumaticCylinder` 消抖直接消费 `DL_Base` 既有件，无重复实现。
- **红线状态**：R1~R7 全部通过，机检 0 命中；R19 首扫范式（`FB_DL_AnalogTransmitter`）、R19/R21 信息级不置故障位公约逐条落实。

### 已知限制 / Known Limitations

1. `FB_DL_DolMotor` 每小时启动次数限制采用 60 分钟桶滑窗近似（分钟级粒度），桶边界处的窗口宽度最大偏差 1 分钟。
2. `FB_DL_AnalogTransmitter` 欠/超量程门限按量程比例中点内插，非 NAMUR 原文的固定 3.8/20.5 mA 值——适配任意原始量程（mA/0~10V），与固定值口径差异已在手册注明。
3. `FB_DL_HeatCoolZone` 不内置 PID/PWM 组态，三实例全部经 `VAR_IN_OUT` 注入（零内嵌组态、零魔法数）；首次使用须先在调用方完成 `FB_DL_PidController` / `FB_DL_PwmDutyController` 参数组态。
4. `FB_DL_PneumaticCylinder` 方法与引脚双通道并存：同一拍同时给方法请求与引脚指令时，方法请求优先（单发语义），现场二选一使用。

---


## v0.13.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 6 件（健康联锁族（T2-8 NE107 多源聚合 + ROADMAP P1 设备保护））

- `FB_DL_HealthAggregator`：多源 NE107 健康聚合仲裁（至多 16 路"最差者胜"，HMI 健康横幅单一事实源，T2-8 落地）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_OvenDoorInterlock`：烘箱炉门-氮气-温区三联锁（先氮气置换后开门）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_ChamberGateValve`：真空腔闸阀互锁互斥控制（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_RobotGripVerify`：机械手夹持确认与掉片判据（真空/夹爪双反馈置位校验）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_FilterDpMonitor`：过滤器压差寿命监视（压差趋势 + 滤芯更换预警，NE107 健康出口）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_TankN2BlanketCtrl`：储罐氮封压力双分程（低压补氮比例段 / 高压泄放开关段，互斥断言；**R24 挂账：分界迟滞回差待补**）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Device] = 67，本文档原记 57（历史批次漏计，随本节一并校正）；本轮已校正为注册表口径。

> **终审留痕**：HealthAggregator 主控修注释占位符后终审 PASS（0348 组态错误路径推演过）；TankN2BlanketCtrl 终审挂账 R24（分界迟滞回差）。


## v0.13.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 6 件（健康联锁族（T2-8 NE107 多源聚合 + ROADMAP P1 设备保护））

- `FB_DL_HealthAggregator`：多源 NE107 健康聚合仲裁（至多 16 路"最差者胜"，HMI 健康横幅单一事实源，T2-8 落地）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_OvenDoorInterlock`：烘箱炉门-氮气-温区三联锁（先氮气置换后开门）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_ChamberGateValve`：真空腔闸阀互锁互斥控制（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_RobotGripVerify`：机械手夹持确认与掉片判据（真空/夹爪双反馈置位校验）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_FilterDpMonitor`：过滤器压差寿命监视（压差趋势 + 滤芯更换预警，NE107 健康出口）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_TankN2BlanketCtrl`：储罐氮封压力双分程（低压补氮比例段 / 高压泄放开关段，互斥断言；**R24 挂账：分界迟滞回差待补**）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Device] = 67，本文档原记 67（一致）；本轮已校正为注册表口径。

> **终审留痕**：HealthAggregator 主控修注释占位符后终审 PASS（0348 组态错误路径推演过）；TankN2BlanketCtrl 终审挂账 R24（分界迟滞回差）。

## 版本号约定 / Versioning Policy

子库遵循 SemVer，且与库总版本联动：

- **MAJOR**：任一组件删除引脚、改引脚语义、改默认值、改故障码含义、接口方法签名变化。
- **MINOR**：新增组件，或为已有组件新增可选输入（带默认值）。
- **PATCH**：内部实现修正、注释与手册补全、性能优化，接口与行为不变。

破坏性变更必须在本文档写明迁移指引（旧调用 → 新调用）与影响的组件清单。

---

## 后续计划 / Next

R7 已交付设备件十件套（扫码枪/安全门/光幕/流量计/料位开关，T1-5 TcOpen 开组）；R8 已交付三色安灯塔契约-实现对；R9 交付开环步进契约-实现对；R10 交付 RFID 读写契约-实现对与现场总线诊断双件；R11 交付端口诊断聚合 / 状态字段批量解码 / NTC 多通道巡检 / 辊距背隙补偿四件；v0.8.0（R12）交付参数核对 / 端口诊断板 / 电表需量 / 真空计多路融合四件，现 44 项（接口 16 ｜ 功能块 28）。

本子库故障码上界随 v0.8.0 提至 `16#0003_0315`，`02FA`~`02FF` 仍为封存禁填带。`FB_DL_PortDiagBoard` 的 `16#0003_030B` 虽落在 `03xx` 故障子块内，**语义为趋势级提示码且不置 `bError`**，HMI 须按级别着色而非按号段着色，已在 v0.8.0 段与手册中三处声明。

后续按 `ROADMAP.md` 第四章推进：`I_DL_PowerMeter` + `FB_DL_ModbusPowerMeter`（三相电表，本轮已由 `FB_DL_EnergyMeterAccum` 先接需量侧）、编码器接口族、称重传感器族等。


---

## v0.12.0 ｜ 2026-11-16 ｜ R22 结构补位轮 4 件

**批次**：本子库 R22 新增 4 件（全库 20 件 6,618 行；机检 20/20 PASS fail=0）
**码位**：本子库本轮占用见各件头注释「码位总账」；收口后全库游标（注册表实测 2026-11-16）：`0001` 信息 `0466` / 故障 `03B7`、`0002` 下一 CC `2D`、`0003` 信息 `017A` / 故障 `0348`、`0004` 信息 `01DF` / 故障 `02F9`、`0005` 信息 `01E2` / 故障 `0317`
**终审结论**：R22 抽检 14 件高风险件，4 件轻微缺陷修复升 v1.0.1（MotionCmdQueue / VirtualMasterAxis / AxisBrakeSeq / BatchTransferSeq），1 件中等安全相关挂账 R23（BatchTransferSeq 中止时序），其余零缺陷 PASS
**码位跨文件冲突断言**：R22 100 槽定向复测 CLASH=NONE；JSONL 384 条全量 sha256 MATCH（本轮另修复 2 件历史换行口径漂移）

- `FB_DL_SlitValveInterlock`：真空闸阀互斥互锁（真空度/门位/机械臂三条件同拍判据 + uBlockMask 阻塞掩码，双路指令先清后置，反馈矛盾/真空非法一律取保守侧；R22 终审推演零缺陷 PASS）。
- `FB_DL_PressureReliefMonitor`：安全阀起跳/回座监视（回座比迟滞判据 + 动作次数/累计时长台账饱和不回绕 + 最短起跳滤除 + NE107 健康分级集中映射；R22 终审推演零缺陷 PASS）。
- `FB_DL_SteamTrapMonitor`：疏水阀堵塞/泄漏温差三判据（三判据互斥重构为「正常带 / 泄漏带 / 堵塞」有序分支，冷态（阀前 < fTinMin）冻结全部故障判定防停机误报）。
- `FB_DL_LevelRadarValidate`：雷达液位回波可信度仲裁（置信度/信噪比/量程/变化率四判据全掩码不早退，初始无历史可信值不得发布 0 m）。

**终审**：本子库 2 件高风险抽检（SlitValveInterlock / PressureReliefMonitor）零缺陷 PASS。

---

## v0.14.0 ｜ 2026-11-17 ｜ R24 行业纵深轮：设备层 5 新件 + TankN2 挂账修复 + 1 终审修复

**新增 5 件 + 修复 2 件**（新件码位 0003 段：信息 0186~018F / 故障 035A~0368）：

| 组件 | 版本 | 说明 |
|---|---|---|
| `FB_DL_StepperMicroFeedPulseEquiv` | v1.0.0 | 步进细分脉冲当量换算与反向间隙组态校验（ROADMAP P2 §588） |
| `FB_DL_PumpDryRunGuard` | v1.0.0→**v1.0.1** | 泵干转保护（功率/流量双判据 + 去抖 + 学习窗 + 重启抑制窗，ROADMAP P1 §452）。**R24 终审修复**：默认参数 tLearnWin 5S > tTripDebounce 3S 自违反 R100 配比约束出厂即 035E → 默认去抖窗 3S→8S；边界行为③注释-实现漂移对齐（锁存仅 bReset 清除） |
| `FB_DL_CoilFrostWindow` | v1.0.0 | 盘管结霜窗口判定与除霜请求（霜层窗 + 露点双判据，ROADMAP P1 §727） |
| `FB_DL_ElectrolyteMoistureGuard` | v1.0.0 | 注液间露点/湿度联锁（超露点禁止注液首因锁定，ROADMAP P1 §693） |
| `FB_DL_MfcSetpointRamp` | v1.0.0 | MFC 设定值斜坡与超调抑制（斜率限制 + 量程换算，ROADMAP P2 §710） |
| `FB_DL_TankN2BlanketCtrl` | v1.0.0→**v1.0.1** | **R23 P0 挂账关闭**：泄放/补氮退出迟滞回差（新增引脚 fVentHystKpa 默认 0.2 kPa，非法回退默认仍越跨度按半宽钳定防死循环；不新占码位 0184 语义扩展）。终审 PASS：回差带数学进入/退出阈值分离正确 |

---

## v0.15.0 ｜ 2026-11-17 ｜ R25 R25 新增设备抽象 4 件 / R25 Batch

**批次**：本轮 20 件中本子库 **4 件**，合计 **1245 行**（全库 20 件 7,097 行，终审修复后 7,174 行）
**码位游标（收口后实测）**：信息级推进至 **`0198`** ｜ 故障级推进至 **`0375`**

| 组件 | 版本 | 一句话功能 / 终审结论 | 来源 |
|---|---|---|---|
| `FB_DL_InverterGridSync` | v1.0.0 | 逆变器并网四窗核对与合闸许可（只出许可不控合闸） | ROADMAP P1 §233 |
| `FB_DL_HeatPumpDefrost` | v1.0.0 | 空气源热泵三条件除霜顺控（最小间隔 + 超时强制退出） | ROADMAP P1 §290 |
| `FB_DL_VavBoxCtrl` | v1.0.0→**v1.0.1** | 压力无关型 VAV 风量闭环 + 风阀限幅（反馈无效保持开度）。**R25 终审修复**：非有限闸的安全侧赋值原写 fOpenMinPct，而下限脚本身在本闸判定集合内 → NaN 下限会把 NaN 当安全值出口；改为先算可用下限 fFloorPct（脚非有限回默认 20%） | ROADMAP P1 §289 |
| `FB_DL_WaferMapping` | v1.0.0 | 晶圆盒槽位 Mapping（片位图 + 空位/双片/斜插三分型） | ROADMAP P1 §251 |

---

## v0.17.0 ｜ 2026-11-18 ｜ R31 泵标定/PROFINET 诊断/晶圆交接/搅拌批：4 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `FB_DL_DosingPumpCalib` | v1.0.0 | 16#0003_00F7 |
| `FB_DL_PnAlarmDiagParse` | v1.0.0 | 16#0003_00FC |
| `FB_DL_WaferHandoffSeq` | v1.0.0 | 16#0003_03F2 |
| `FB_DL_SlurryStirrerCtrl` | v1.0.0 | 16#0003_03F7 |

> R31 增量行：组件总数 102→**106**（registry 实测口径）；机检 19/19 PASS fail=0；终审抽 5 件（本库 0 件），修 0 处升 v1.0.1（无）。

---

## v0.17.0 ｜ 2026-11-18 ｜ R31 泵标定/PROFINET 诊断/晶圆交接/搅拌批：4 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `FB_DL_DosingPumpCalib` | v1.0.0 | 16#0003_00F7 |
| `FB_DL_PnAlarmDiagParse` | v1.0.0 | 16#0003_00FC |
| `FB_DL_WaferHandoffSeq` | v1.0.0 | 16#0003_03F2 |
| `FB_DL_SlurryStirrerCtrl` | v1.0.0 | 16#0003_03F7 |

> R31 增量行：组件总数 102→**106**（registry 实测口径）；机检 19/19 PASS fail=0；终审抽 5 件（本库 0 件），修 0 处升 v1.0.1（无）。

### R33 增量（1.15.0 → 1.16.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_FanBeltSlipDetect` | v1.0.0 | 16#03_1_01 |
| `FB_DL_UnlockHoldTimeout` | v1.0.0 | 16#03_1_02 |
| `FB_DL_VacuumPumpBasePress` | v1.0.0 | 16#03_1_03 |
| `FB_DL_InverterDeratingCtrl` | v1.0.0 | 16#03_1_04 |
| `FB_DL_PrecursorCanisterWeight` | v1.0.0 | 16#03_1_05 |

> R33 增量行：本库 106 → **111**；机检本库新增件全 PASS；码位全窗口独占无冲突（主控实测）。

### R34 增量（1.12.0 → 1.13.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_CombinerArcDetect` | v1.0.1 | 16#03_2_00 |
| `FB_DL_CellVolumeCheck` | v1.0.0 | 16#03_2_01 |
| `FB_DL_MfcRatioCheck` | v1.0.0 | 16#03_2_02 |
| `FB_DL_PhaseNeutralImbalance` | v1.0.0 | 16#03_2_03 |
| `FB_DL_HumidifierWaterQual` | v1.0.0 | 16#03_2_04 |

> R34 增量行：本库 1.12.0 → **116**（registry 实测口径）；机检新增件全 PASS；码位全窗口独占无冲突（主控实测 06_0_80~/03_2_00~/04_0_A0~/02_3_80）。

## R39（2026-11-19）— +5（BcdFieldPanelIO / DoorInterlockHvac / ElMutingGantry / CleaningBrushWear / OrificeDpZeroTrim）；返修 ElectrodeTabBendCtrl / VavBoxZeroCal → v1.0.2

- 本轮增量已入册（registry v2.31.0），机检全 PASS；详见 CHANGELOG v2.31.0。

## v1.17.0 — 2026-11-19（R41 · 20 新件批次 4）
- 新增 2 件：FB_DL_InverterPdiPoll（逆变器 PDI 参数周期读取，单拍单发 + 站表台账）/ FB_DL_FilterSwitchLevel（过滤器液位联锁 fail-safe LOW + 再生切换闭锁）；组件总数 138 → 140。
- 码位：段 0003 推进——信息 16#0003_041C~0421、故障 16#0003_03FC~03FF（03xx 带已满，R42 规划启用 05xx 副故障带并在头注释写明分段理由）。

## v1.17.0 — 2026-11-19（R42：+5 新件）

### Added（5 新件，批次 4）
- FB_DL_RobotArmVibrationWatch：晶圆传送机械手振动特征监视（高通分量 + 特征窗分级）
- FB_DL_RoofUnitDoorSw：屋顶机检修门-风机联锁（重启抑制轻量组态）
- FB_DL_FilmSpliceCurtain：接膜工位光幕屏蔽序列（2 传感器模式屏蔽时序）
- FB_DL_DamperBitDiag：风阀执行器位诊断打包/解包（位段提取 + 位打包复用）
- FB_DL_BmsPdiGateway：楼宇侧 PDI 对象网关轮询（复用 PDI 调度 + 异常上报）

### 码位
- Device 05xx 副带首次启用（首开分段理由已逐件落头注释，R192 落地）；全文口径实扫零冲突。

### 计数
- 组件 140→145；机检 5/5 PASS。

### v1.16.0 — 2026-11-19（R43）
- 新增组件 3 件；码位窗口 052B~052D / 0431~0433 零冲突。
- 由 v1.15.0 升位，向后兼容（纯新增，无接口破坏）。

## v1.17.0 — 2026-11-19（R44 · 零检索轮）
- 新增 4 件：FB_DL_LoadcellTareCtrl（去皮/两点标定/标定超期计数）/ FB_DL_ValvePartialStrokeTest（安全阀 PST，NE107 出口引用唯一属主枚举）/ FB_DL_RotaryUnionWatch（转速/温升/泄漏三判据独立确认窗）/ FB_DL_HeaterSsrBank（SSR 调功器组：分相占空比 + 电流均衡 + 断偶降级）；组件总数 148 → 152。
- 码位：05xx 副带续编，派单建议窗口 052E~0531，registry 全文口径实测零冲突。
- 向后兼容（纯新增，无接口破坏）。

## v1.18.0 — 2026-11-19（R45）

- R45：+3 新件（SafetyRelayFeedback / ContactorWeldDetect / FlowSwitchResponseCheck）｜故障级新开 07xx 子带 16#0003_0701~0703 / 信息 0480~0482


## v1.19.0 — 2026-11-19（R46）

- R46：+3 新件（LoadCellTareDrift / TcChannelScanDiag / GripperForceVerify）｜零码位硬编码：BOOL+ENUM 出口，码位待主控统一派号｜机检 3/3 PASS
- 向后兼容（纯新增，无接口破坏）。

## v1.19.1 — 2026-11-19（R47）

- R47：+3 新件（TankBlanketPrCtrl / IvBcdExport / CassetteBcdLabel）｜零码位硬编码，码位待主控统一派号｜机检 3/3 PASS
- 向后兼容（纯新增，无接口破坏）。
---

## v1.17.0 — 2026-11-20（R48）

- 新增组件 3 件：FB_DL_SolenoidCoilHealth / FB_DL_HeaterBreakDetect / FB_DL_VibZoneClassify
- 子库组件总数：**164**（registry 实测口径）
- 机检：本轮 21/21 PASS（含 FB_DL_ModulePottingVac v1.0.1 轻返修）

## v1.18.0 — 2026-11-20（R49）

- 新增组件 3 件：FB_DL_ValveSeatLeakWatch / FB_DL_CylStrokeTimeBank / FB_DL_CaseErectFaultSeq
- 子库组件总数：**167**（registry 实测口径）
- 机检：本轮 20/20 PASS（增量仅扫本轮新增件）

## v2.42.0（R49 批次入册 · R50 收口，2026-11-20）
- 新增组件 3 件：FB_DL_ValveSeatLeakWatch / FB_DL_CylStrokeTimeBank / FB_DL_CaseErectFaultSeq
- 子库组件总数：**170**（registry v2.42.0 counts 口径）
- 机检 25/25 PASS；R50 终审本子库 CaseErectFaultSeq PASS（轻：tonDrop PT 复用暂停时长已声明）

## v1.18 — 2026-11-20（R52）
- 变更：+4（BrakeResistorThermal I²t 热累积 / PressureSwitchChatter 抖动分档 / MeterPulseLossDetect 丢脉冲 / HeatTraceCircuitMon 电伴热四象限）；返修 ValveSeatLeakWatch v1.0.1
- 子库计数：**175 件**（全库 945 / v2.44.0）
- 机检：本子库本轮新增/返修件全部 PASS（audit_r52.py，22/22 全绿）

## v1.19 — 2026-11-20（R53）

- +3：FB_DL_ValveCycleLifeCounter / FB_DL_ConveyorSlipWatch / FB_DL_GreaseLubeTimer；返修：FB_DL_HeatTraceCircuitMon v1.0.1 / FB_DL_BrakeResistorThermal v1.0.1
- 机检：本轮 20/20 PASS（含 4 件 v1.0.1 返修）；JSONL 同步 962 条。

## R54 追加（2026-11-20，子库 v1.20）
- 新增：FB_DL_HealthStatusArbiter / FB_DL_PnDiagAlarmDecode / FB_DL_AirCompressorLoadUnload
- 子库存量：181 件

## v1.21 — 2026-11-21（R56 追加）
- 新增 4 件（AccumPreChg / IonizerBalance / FanBypass / UltrasonicWeld）。
- 子库累计 185 件。
## v1.22 — 2026-11-21（R57 追加）
- 新增 3 件：FB_DL_EsdGroundMonitor / FB_DL_IonizerAirflowInterlock / FB_DL_ProofTestSeq（ESD 接地连续性 / 离子风机风速联锁 / 联锁证明试验）+ FB_DL_HydraulicAccumPreChg v1.0.1
- 子库累计 188 件。

## v1.23 — 2026-11-21（R58 追加）
- 3 件（SoftStarterDrive / ElectricLinearActuator / CondensateDrainSeq）。
- 子库累计 191 件。

## v1.25 — 2026-11-21（R60 追加）
- 新增 1 件：FB_DL_ValveTerminalDiag（阀岛在位诊断）
- 子库累计 194 件。

## v1.24 — 2026-11-21（R61 追加）
- 新增 3 件：PhaseLossGuard / SensorPairPlausibility / AirDryerDiag
- 子库累计 197 件。

## v1.25 — 2026-11-21（R62 追加）
- 新增 2 件：`FB_DL_VfdDcBusRipple`（母线均值 / 峰峰纹波率 / 欠压 / 过压四出口，`_nFill` 除子防首填偏小、变窗长全窗清）、`FB_DL_IonFanInterlock`（离子风机三判据合取许可位，**发放可延迟 / 撤除零延时**非对称写死 + NE107 分级；承接 ROADMAP R56-1086）。
- 返修 1 件：`FB_DL_SensorPairPlausibility` v1.0.0 → **v1.0.1**（变窗长全窗清零 + 除子改 `_nFill`）。
- **已知未关闭（R63 P0）**：`FB_DL_VfdDcBusRipple` 组态非法（`fUdNom ≤ 0`）仅置标志未早退，段 8 仍执行除法；`FB_DL_IonFanInterlock` 失能相未屏蔽报警 / 故障出口。详见 `REVIEW_R62.md` D1 / D3。
- 子库累计 199 件。

## v1.26 — 2026-11-21（R63 追加）
- 新增 4 件（族② 直流母线/ADC/测点监视族深化，R193 扩面；四件全部「组态域闸 → 三件套 → RETURN」结构早退出厂即正确）：`FB_DL_AdcNoiseFloorWatch`（静态期底噪标准差 + 双限值迟滞）、`FB_DL_VfdOutputImbalance`（变频输出三相不平衡/断相双判据独立迟滞）、`FB_DL_VfdCapAgingEst`（纹波率基线比长期老化趋势）、`FB_DL_VfdPrechargeSeq`（预充反馈窗/斜率/总时限三闸状态机，`E_DL_PrechargePhase` 属主本件，锁存解除式 `bResetCmd` 可达自证）。
- 返修 2 件：`FB_DL_VfdDcBusRipple` v1.0.0 → **v1.0.1**（R62-D1 严重：段 3A 结构早退封死除零直穿）；`FB_DL_IonFanInterlock` v1.0.0 → **v1.0.1**（R62-D3 中：出口串 `bEnable` + R62-D6 段序顺带消除）。R62 挂账全清，恢复可用于安全相关回路。
- 子库累计 203 件。
## v1.27 — 2026-11-21（R64 追加）

- 新增 `FB_DL_DualValveBlockSet`（v1.0.0，T2-2 LBP 阀组三段分层 clean-room）：双阀同令同闭 + 两路反馈不一致窗监视，锁存 072E、组态闸 072D 结构早退、复位沿解除可达。
- **返修 1 件**：`FB_DL_VfdPrechargeSeq` v1.0.0 → **v1.0.1**（R63-D1 宽限计时串 `NOT _bMeasBad`；R63-D2 撤令判据上移至事件优先段首位，消除同拍竞态假锁存）。
- 主库合计 204 件（+1）。本轮终审新挂账 1 处（DualValveBlockSet 的 tonMismatch 缺相位门控，R316），转 R65。
