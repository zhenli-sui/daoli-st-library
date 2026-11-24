# DL_Process — 版本记录 / Version History

> **子库定位 / Role**：Level 2 行业工艺与通用工站模板层：以 PackML / ISA-TR88.00.02 状态机框架为首件，提供「纯状态机框架 + 命令解码」的机台层底座——本层不编排任何具体工艺动作，动作由调用方按态派发（依赖注入原则）。
> **兼容平台 / Platforms**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop ｜ Schneider Machine Expert
> **依赖 / Depends**：`Standard.library`（`TON` / `R_TRIG` / `SHR`）；框架件（PackML 两件）零库内依赖；R6 行业池示范件经既有组件复用依赖 Level 0~1——`FB_DL_EnthalpyCompareCtrl` 引用 `FC_DL_HumidAirEnthalpy`（DL_Algo），`FB_DL_OccScheduleWindow` 引用 `FB_DL_TimeWindowCheck` / `FC_DL_DayOfWeekCalc`（DL_Base），依赖方向 Level 2 → Level 1/0 合法。

---

## v1.30 — 2026-11-22（R71）

- R71 新增 1 件：`FB_DL_LaneDivertCtrl`（道岔分流四相，失能回夹先于状态机）。累计 286 件。

---
## v1.29 — 2026-11-21（R59）

R59 新增 LotoSequence / VisionResultGate / LotGenealogyLink；LotGenealogyLink 修循环配对编译阻断。

## R39 返修迁移说明 ｜ 2026-11-19 ｜ FB_DL_ModuleLamVacuumSeq v1.0.1 → v1.0.2

- 缺陷：`tonSeg` PT 误接 `tSegmentTimeout`（四段配方时长从未接入，推进与超时同拍）+ `eFault` 无迁出边（故障永久锁死）。
- 返修：配方计时拆分为四相独立 TON（PT 各接本段配方时长）；超时计时同步拆分四相独立实例；`eFault` 相新增 `bReset` 上升沿迁出边回 `eIdle`。对外接口（引脚与类型）不变。
- 迁移影响：升级后段推进按配方时长生效，超时判据不再与推进同拍；故障可经 `bReset` 解除。R228-A/B 机检两条回归通过。

## 当前版本 / Current Version

| 项 / Item | 值 / Value |
|---|---|
| 子库版本 / Sublibrary Version | **v1.17.0** |
| 组件总数 / Components | **151**（registry 实测口径，R35 新增 14 见 v1.15.0 增量节） |
| 发布日期 / Release Date | 2026-11-18 |
| 库总版本 / Library Version | 2.30.0 |
| 依赖层级 / Dependency Level | Level 2（框架件零库内依赖；R12 温控采集行内嵌 `FB_DL_ModbusPollMaster` 与本子库 `ST_DL_PollItem`，并引用 `DL_MathData` 的 `FB_DL_MovingAverage`；R13 新件引用 `E_DL_Ne107Status`（DL_Device 契约件 A1）作健康出口类型，`FB_DL_ReactorJacketDeltaT` 组合调用 `FB_DL_RateLimiter`（DL_Algo）——依赖方向 Level 2 → Level 1/0 合法） |
| 故障码段 / Error Code Family | **`16#0005_xxxx`**（信息级 `16#0005_01xx` ｜ 故障级 `16#0005_02xx` 起段；R13 占用 `01C5`~`01D1` 与 `02F3`~`02FE`，为 R12 声明的下一可用码） |


## v1.16.0 ｜ 2026-11-18 ｜ R38：6 件（HeatSealProfile / AhuEconomizer / TerminalReheatSeq / RfReflectedMonitor / StringSolderQuality / ModuleLamVacuumSeq）

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 15 | FB_DL_HeatSealProfile | FB | `16#06_0_B0` | t2-7-packml | 热封温度-压力-时间三参数配方曲线（段切换 + 超窗判废 + 配方校验） |
| 16 | FB_DL_AhuEconomizer | FB | `16#06_0_B1` | t1-2-oscat-building | 空调箱新风经济器（焓值主判据 + 干球后备 + 防冻锁存） |
| 17 | FB_DL_TerminalReheatSeq | FB | `16#06_0_B2` | t1-2-oscat-building | 末端再热级联联锁（最小风量按级降档 + 再热上限级联） |
| 18 | FB_DL_RfReflectedMonitor | FB | `16#06_0_B3` | t2-1-lgf-measurement | 射频反射比监视（双阈值迟滞 + 请求调谐，仅监视不闭环） |
| 19 | FB_DL_StringSolderQuality | FB | `16#06_0_B4` | t2-1-lgf-technology | 串焊质量三判据逐通道分级 + NG 位掩码 + 拉力抽检整批判废 |
| 20 | FB_DL_ModuleLamVacuumSeq | FB | `16#06_0_B5` | t2-7-packml | 组件层压真空四段顺控（真空-温度双到位才升压 + 段超时升级） |

> R38 增量行：组件总数 → **151**（registry 实测口径）；库总版本 2.30.0。

## v1.15.0 ｜ 2026-11-18 ｜ R35 行业池批：14 件（光伏 4 + 半导体/真空 3 + 暖通 2 + 分析仪/蒸汽 2 + 电镀/烧结/绝缘 3）

> 版本号说明：子库版本号按主控 R35 收口指令自 v0.16.0 对齐跃迁至 v1.15.0（与其他子库 SemVer 口径统一）；组件数以 registry 实测为准。

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 1 | FB_DL_TrackerWindStow | FB | `16#06_0_8C` | t2-1-lgf-technology | 跟踪支架大风保护收拢（阈值迟滞 + 爬升率趋势 → 安全角度出口） |
| 2 | FB_DL_LaminatorTempProfile | FB | `16#06_0_8D` | t2-1-lgf-technology | 层压机多温区配方曲线跟随（复用 RampSoakProfile） |
| 3 | FB_DL_StringerTrend | FB | `16#06_0_8E` | t2-1-lgf-measurement | 串焊机多通道焊接温度曲线监视（峰值窗 + 分级告警） |
| 4 | FB_DL_PottingDispenseCtrl | FB | `16#06_0_8F` | t2-2-lbp | 接线盒灌胶定量（减量法 + 双组份混合比闭环） |
| 5 | FB_DL_PileClampCtrl | FB | `16#06_0_90` | t2-2-lbp | 堆叠压紧板预压/全压两段控制（StepSequencer + I_DL_Cylinder） |
| 6 | FB_DL_CvdTempRamp | FB | `16#06_0_91` | t2-1-lgf-technology | CVD/扩散炉多段 Ramp/Soak 跟随 + 均匀性判据 |
| 7 | FB_DL_AnalyzerSampleSeq | FB | `16#06_0_92` | t2-8-isa88 | 分析仪取样-吹扫-标定三态轮换（相超时升级 + 标定过期锁存） |
| 8 | FB_DL_SteamHeaderSplit | FB | `16#06_0_93` | t2-5-modpid | 蒸汽母管多支路分程分配（SplitRangeControl 多实例） |
| 9 | FB_DL_HydronicDeltaTGuard | FB | `16#06_0_94` | t1-2-oscat-building | 水系统大/小温差失衡诊断 + 旁通泄漏确认窗 |
| 10 | FB_DL_ChillerApproachTrend | FB | `16#06_0_95` | t1-2-oscat-building | 冷机逼近度趋势诊断与性能衰减预警（SignalStatistics） |
| 11 | FB_DL_PlatingCurrentCtrl | FB | `16#06_0_96` | t2-2-lbp | 电镀槽位电流密度闭环与液位联锁 |
| 12 | FB_DL_FiringFurnaceZone | FB | `16#06_0_97` | t2-1-lgf-technology | 烧结炉多温区峰值温度跟随 + 链速前馈重置 |
| 13 | FB_DL_InvInsulTestSeq | FB | `16#06_0_98` | t2-8-isa88 | 逆变器绝缘测试加压-保持-泄放联锁顺控 |
| 14 | FB_DL_ForelinePressureCtrl | FB | `16#06_0_99` | t2-5-modpid | 真空前级压力稳定（PI + 抽速前馈 + 越窗分级） |

- 码位备注：本批 90~99 格基码与既有 80~89 格第二子码段（0690~069B）撞码，子码整段错位至 B0~B9/C0~C9/D0~D9 避让（新规则 R207），头注释逐件留档。

## v0.16.0 ｜ 2026-11-18 ｜ R30 行业工艺批：8 件（半导体 3 + 包装 3 + 锂电 1 + 流程联锁 1）

- `FB_DL_WaferScanRouter`：晶圆盒扫码分道路由（花篮位条件减法取模〔不用 MOD〕+ 扫码超时拒收 + 空串/读码失败分型）（0005_0467~046B）。
- `FB_DL_SiloLevelInterlock`：料仓高低料位-输送双联锁（防溢仓不停输送完成当前批次 + 空跑停输送 + 卡料窗；锁存解除式全部可达）（0005_046C~0470）。
- `FB_DL_PalletZoneMerge`：码垛前 4 区合流积放（顺序/先到先走两模式仲裁 + 同拍至多释放一区 + 光电去抖）（0005_0471~0475）。
- `FB_DL_WeightClassifySort`：重量四档分级剔除（判档委托 `FC_DL_LimitClassify` + 阈值单调组态闸 + 非有限 NG 安全分流）（0005_0476~047A）。
- `FB_DL_EmoAndonFab`：洁净室 EMO-安灯联动（仲裁委托 `FB_DL_AndonCallSystem` + EMO 首出定位到按钮号）（0005_047B~047F）。
- `FB_DL_FillWeightCheckweigher`：称重剔除秤（动态稳定窗 + 欠/超重四档 + 剔除脉冲可配置）（0005_0480~0484）。
- `FB_DL_FilmSpliceDetect`：薄膜接膜位检测与降速放行（位置锁存消费 + run-on 语义 + 接料计数）（0005_0485~0489）。
- `FB_DL_CoatingGapMeasure`：涂布留白宽度与窗口一致性判定（像素→mm 标定 + 带端点闭/开归属声明 + 统计消费注入）（0005_048A~048E）。

> R30 增量行：组件总数 79→**87**（registry 实测口径）；终审抽 SiloLevelInterlock（安全联锁类）通过：4 个锁存位解除式逐一自证可达，0 修。

---

## v0.11.0 ｜ 2026-11-16 ｜ R19 工艺模板批：汽包三冲量/多吸盘拾放 2 件

- `FB_DL_DrumLevelThreeElem`：汽包水位三冲量单泵轻量版（增量式给定 + 越限锁存）（码位见 .st 头注释码位总账）。
- `FB_DL_VacCupRingCtrl`：多吸盘环状拾放（逐通道确认/少吸判据/分组释放/降级放行）（码位见 .st 头注释码位总账）。
- **终审修复（v1.0.1）**：`FB_DL_DrumLevelThreeElem` 水位项符号由 + 改为 −（负反馈）；v1.0.0 构成正反馈（水位越低越不补水），安全级缺陷（R19 终审）。

> `16#0005_` 段游标：信息级下件起点 **01DA**｜故障级下件起点 **030B**。

---

## v0.10.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：五步换产顺控 + 停机原因分类 2 件 / R18 Scenario Lane — Changeover Sequence & Downtime Classifier

**变更性质**：MINOR（新增 2 个组件）+ PATCH（`FB_DL_ChangeoverSequence` 失能路径漏清放行镜像修复 v1.0.0→v1.0.1）。

### 新增组件（2 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_ChangeoverSequence` | FB | 停机→排空清洁→配方装载→参数下发→首件 五步可确认顺控，步内超时重装 | `bStart` / `tStepTimeout` / `bReadyForProduction` |
| `FB_DL_DowntimeClassifier` | FB | 停转时抓首个动作的原因源，给出停机原因序号与时长 | `bEnable` |

> 码位以注册表 `code_segment` 为准；全库重叠复测 = 0。

## v0.9.0 ｜ 2026-11-16 ｜ R13 旋盖扭矩曲线 NG 判别 + ESC 氦背冷检漏 + 腔体 seasoning 台账 + 釜夹套温差约束（4 件）+ 存量 R39 修复 1 件 / R13 Capper Torque, ESC Leak Check, Seasoning Ledger, Jacket Delta-T & Legacy R39 Fix

**变更性质**：MINOR（新增 4 个组件）+ PATCH（存量 `FB_DL_AgvDockingHandshake` v1.0.0 → v1.0.1，R39 语义修复，引脚契约零变化）。终审 **4 件中 2 件零修改 PASS，2 件修复后 PASS**（`FB_DL_CapperTorqueTrend` 状态机迁移违规格、`FB_DL_EscHeLeakCheck` 稳压延长窗全程未计时——中高·功能失效级，均升 v1.0.1）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 23 | `FB_DL_CapperTorqueTrend` | FB | 617 | **1.0.1** | rockwell-aoi / lbp-process | **v1.0.1** —— 旋盖扭矩曲线特征提取 + 五类 NG 判别：峰值 / 上升斜率 / 稳态均值 / 面积比四特征，低扭 / 高扭 / 滑牙 / 歪盖 / 曲线异常五类 NG（原因位图可并置），主判定优先级 = 滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常；不内联分位排序（批次 P10/P90 引脚注入）、不内联滤波；NG 属工件不良不置 bError；v1.0.1 修复评估相检出非有限样本后仍无条件转判定态（故障锁存语义失效，下一启动沿可绕过复位） / Capper torque curve features and five-class NG verdicts |
| 24 | `FB_DL_EscHeLeakCheck` | FB | 564 | **1.0.1** | semiconductor-esc（自研） | **v1.0.1** —— 静电吸盘氦背冷三段式泄漏率判定：升压（斜率监视 + 达压确认）→ 稳压（窗内极差稳定判据，可延长一次）→ 测量（压降率 → 漏率换算 + 温漂修正）→ OK / Warn / NG 三级判定；与通用压降工站 `FB_DL_LeakTestStation` 分工明确（压力量纲、判定门限、Warn 三级、串漏方向识别），**禁止合并**；v1.0.1 修复稳压延长窗裁决条件致主稳压 TON 恒真——延长置位后下一拍即提前进测量，延长定时器全程未计时、01C8 名存实亡（中高·功能失效，D-C4-1） / ESC helium back-cooling three-phase leak check with temperature correction |
| 25 | `FB_DL_ChamberSeasoningTrack` | FB | 435 | 1.0.0 | semiconductor-esc / isa-88 | 腔体 seasoning 台账与放行判定：逐片累计片数 / 工艺时长 / 膜厚均值与趋势，**双判据（片数 ∧ 时长）**才放行；连续越窗自动降级 eNotReady；配方名只作标签与校验键（不做配方存储、不做膜厚测量）；工艺时长由引脚注入累加而非墙钟（多腔体并行跟踪不把等待算进时长）；配方名超 32 字符显式截断置码（R37），台账不可信安全侧不放行 / Chamber seasoning ledger with dual-criteria release |
| 26 | `FB_DL_ReactorJacketDeltaT` | FB | 487 | 1.0.0 | lbp-process / isa-88 | 釜温-夹套温差约束与冷热分程：以 ΔT = 釜温 − 夹套温 为约束量做温差上限 + 变化率双约束，超温强制冷却带回差；上层 PID 输出分程为冷/热两路阀位给定，死区防冷热同开；限速能力**组合调用** `FB_DL_RateLimiter` 绝不内联；**不内联 PID**（温度闭环归 `FB_DL_CascadePid`）；传感器反装判据（温差为负且要求升温 → 02FD 锁存） / Reactor jacket delta-T constraint and split-range with rate-limited constraint path |

### 修复 / Fixed

| 组件 | 版本变化 | 内容 |
|---|---|---|
| `FB_DL_AgvDockingHandshake` | 1.0.0 → **1.0.1** | **R39 存量修复**（R13 存量专案）：段 5 使能撤销分支原先把 `_eState` 无条件改写为 `eIdle`，而故障复位沿的消化位于其后 CASE 的 `eFault` 分支——禁用期间按下的复位沿当拍被抹掉，`_bFaultLatch` 与故障码留存至操作员补按第二次复位，期间使能回升也被「有锁存」判据挡在待机（`eState` 报 eIdle 而 bError = TRUE 的自相矛盾态）。改为 `eFault` 态不被禁用覆盖；引脚契约与码位零变化 |

### 故障码台账追加（R13 码位登记，经终审全库复核 0 重叠）/ Error Code Ledger Additions (R13)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0005_01C5` | 信息级 | 点数不足未评级（不等于不合格） | FB_DL_CapperTorqueTrend |
| `0005_01C6` | 信息级 | 批次分位未下发，仅用绝对阈值 | FB_DL_CapperTorqueTrend |
| `0005_01C7` | 信息级 | 曲线噪声大，斜率可信度低 | FB_DL_CapperTorqueTrend |
| `0005_01C8` | 信息级 | 稳压未达判据已延长一次 | FB_DL_EscHeLeakCheck |
| `0005_01C9` | 信息级 | 温漂修正已启用 | FB_DL_EscHeLeakCheck |
| `0005_01CA` | 信息级 | 漏率落在 Warn 带 | FB_DL_EscHeLeakCheck |
| `0005_01CB` | 信息级 | 单片越窗但未连续 | FB_DL_ChamberSeasoningTrack |
| `0005_01CC` | 信息级 | 连续越窗达阈值降级 | FB_DL_ChamberSeasoningTrack |
| `0005_01CD` | 信息级 | 片数达标但时长未达标 | FB_DL_ChamberSeasoningTrack |
| `0005_01CE` | 信息级 | 配方名超 32 字符已显式截断 | FB_DL_ChamberSeasoningTrack |
| `0005_01CF` | 信息级 | 温差达上限升温侧冻结 | FB_DL_ReactorJacketDeltaT |
| `0005_01D0` | 信息级 | 釜温超设定加裕量强制冷却 | FB_DL_ReactorJacketDeltaT |
| `0005_01D1` | 信息级 | 分程重叠区被死区分离 | FB_DL_ReactorJacketDeltaT |
| `0005_02F3` | 故障级 | 曲线点数超上限 | FB_DL_CapperTorqueTrend |
| `0005_02F4` | 故障级 | 曲线含非有限值 | FB_DL_CapperTorqueTrend |
| `0005_02F5` | 故障级 | 非法状态兜底 | FB_DL_CapperTorqueTrend |
| `0005_02F6` | 故障级 | 升压超时或供气异常 | FB_DL_EscHeLeakCheck |
| `0005_02F7` | 故障级 | 测量段压力上升（源侧串漏或阀未关） | FB_DL_EscHeLeakCheck |
| `0005_02F8` | 故障级 | 非有限输入或非法状态兜底 | FB_DL_EscHeLeakCheck |
| `0005_02F9` | 故障级 | 配方名为空或膜厚目标非正 | FB_DL_ChamberSeasoningTrack |
| `0005_02FA` | 故障级 | 片数/时长台账溢出或量测值不可信 | FB_DL_ChamberSeasoningTrack |
| `0005_02FB` | 故障级 | 非法状态兜底 | FB_DL_ChamberSeasoningTrack |
| `0005_02FC` | 故障级 | 温度或 PID 输出非有限 | FB_DL_ReactorJacketDeltaT |
| `0005_02FD` | 故障级 | 温差为负且要求升温（传感器反装） | FB_DL_ReactorJacketDeltaT |
| `0005_02FE` | 故障级 | 非法状态兜底 | FB_DL_ReactorJacketDeltaT |

---

## v0.8.0 ｜ 2026-11-15 ｜ R12 ISA-88 相状态底座 + 温控器轮询采集行（2 件）/ R12 Batch Phase Base & Polled Temperature Bank

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 12「ISA-88 完整批次模型本体 + ROADMAP §13.6 P0 温控器轮询采集行」（来源标签 isa88-batch / roadmap-p0 + t1-4，仅借鉴公开规范的状态集合与调度分层，clean-room）。终审 **2 件中 1 件零修改 PASS，1 件修复后 PASS**（`FB_DL_BatchPhaseBase` 1 致命 + 1 轻微，升 v1.0.1）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 21 | `FB_DL_BatchPhaseBase` | FB | 530 | **1.0.1** | isa88-batch | **v1.0.1** —— ISA-88 相状态底座（11 态）：空闲 / 执行 / 收尾 / 完成 / 暂停请求 / 已暂停 / 恢复中 / 停止中 / 已停 / 中止中 / 已中止，命令全部上升沿受理、同拍多命令按优先级丢弃、暂停在**步骤边界**生效、恢复**不重头**、已终止态只认复位；单步与暂停双超时看守，相净运行时间仅在执行相累计；v1.0.1 单步超时按步骤边界断输入一拍重计时（R40） / ISA-88 phase state base with boundary-aware hold and per-step watchdog |
| 22 | `FB_DL_PollTempBank` | FB | 449 | 1.0.0 | roadmap-p0 | 温控器轮询采集行：对最多 8 台温控器轮询采过程值与设定值，做工程量换算、有效域判定、逐通道滑动均值、偏差与最差通道定位，输出通道质量掩码与在线台数；连续失败达阈值摘除通道（**摘除后仍继续轮询以便自动恢复**，连续两拍有效自动复位）；坏通道温度保持上次有效值绝不用零填充 / Polled temperature bank with quality mask, drop-and-recover and moving average |

### 故障码台账追加（R12 码位登记，经终审全库复核）/ Error Code Ledger Additions (R12)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0005_0104` | 信息级 | 相内步骤数越界，已钳到 1~32 | FB_DL_BatchPhaseBase |
| `0005_0105` | 信息级 | 同拍多命令，低优先命令已丢弃（不排队） | FB_DL_BatchPhaseBase |
| `0005_0106` | 信息级 | 从暂停恢复，步骤号不重置（继续当前步） | FB_DL_BatchPhaseBase |
| `0005_0107` | 信息级 | 单步或暂停超时监控被关闭（时间参数为 0） | FB_DL_BatchPhaseBase |
| `0005_0108` | 信息级 | 台数、窗口长度或摘除阈值越界已钳位 | FB_DL_PollTempBank |
| `0005_0109` | 信息级 | 通道连续失败达阈值已摘除（仍继续轮询以便自动恢复） | FB_DL_PollTempBank |
| `0005_010A` | 信息级 | 滤波窗口为 1，均值等于瞬时值（无滤波能力） | FB_DL_PollTempBank |
| `0005_0203` | 故障级 | 单步超时，相中止 | FB_DL_BatchPhaseBase |
| `0005_0204` | 故障级 | 步骤失败反馈，相中止（与完成反馈同拍时失败优先） | FB_DL_BatchPhaseBase |
| `0005_0205` | 故障级 | 暂停超时，相中止 | FB_DL_BatchPhaseBase |
| `0005_0206` | 故障级 | 非法状态兜底（直接进已中止，不回空闲） | FB_DL_BatchPhaseBase |
| `0005_0207` | 故障级 | 换算比例非正（量纲错，含零乘隐患） | FB_DL_PollTempBank |
| `0005_0208` | 故障级 | 有效温度域为空（任何读数都会被判无效） | FB_DL_PollTempBank |
| `0005_0209` | 故障级 | 非法状态兜底（终端安全态） | FB_DL_PollTempBank |

**号段占用声明**：本批 `DL_Process` 取 R11 声明的下一可用信息级码 `0104` 与故障级 `0203`，件内连续（`0104`~`0107` / `0203`~`0206` 归相底座，`0108`~`010A` / `0207`~`0209` 归采集行），未跳号、未借用其他子库码段。

### 缺陷修复 / Fixed

| 组件 / Component | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| `FB_DL_BatchPhaseBase` | **致命** | 3 步各 30 s、`tStepTimeout = 60S` 的**完全合规批次**在第 3 步被判 `0203` 中止；进入收尾相时定时器往往已接近或超过 `PT`，收尾「进相即超时」。根因：单步监视定时器在执行 / 收尾 / 停止三相之间 `IN` 连续为真，步骤推进与相迁移都不曾断输入，`ET` 跨步累加，「单步超时」退化为「相内累计超时」 | 新增 `bStepWatchBreak`：步骤边界（消费本次完成反馈处）置位；定时器 `IN` 串入 `NOT bStepWatchBreak`，并在 `bStepTo` 取值后自清，实现「断输入一拍、按步重计时」 |
| `FB_DL_BatchPhaseBase` | 轻微 | `bStart` 引脚注释写「仅空闲与已终止态受理」，实现只在 `eIdle` 受理（终止态须先 `bReset`），按注释接线会在终止态反复给启动沿而毫无响应 | 注释更正为「仅空闲态受理（已终止态须先复位）」，与语义要点 ④ 一致 |

### 变更说明 / Change Notes

- **相底座不做动作**：`FB_DL_BatchPhaseBase` 只输出「相状态 + 当前步骤号 + 单拍请求」，具体动作由调用方按 `bRequestStep` 派发；`FB_DL_PackMlStateMachine` 是机台级的 17 态框架，二者层级不同（相 ⊂ 机台），不可互相替代。
- **采集行只读不写**：设定值下发、自整定、超温切断属温控器内部或工艺层职责，本件只读。内嵌调度实例以库内基类形态声明，生产部署须由具备真实串口 / 网口收发的派生块替换；未替换时表现为「质量掩码全置位 + 在线台数为零」的**可观测失败**，不会给出假温度。
- **红线状态**：R1~R44 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.7.0 ｜ 2026-11-15 ｜ R11 工站四件套（伺服压装 / 分度盘节拍 / 移动载体对接 / 整线节能，4 件）/ R11 Station Quartet

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。对应 Round 11 泳道 C「工站四件套」（来源标签 lisp / PLCopen / packml-omac / 包装机械公开手册 / 批控与轻工产线公开手册，均只借鉴阶段划分、功能分类与参数域，clean-room 未复制源码）。终审 **PASS 4 件全部零修改**。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 17 | `FB_DL_PressFitStation` | FB | 580 | 1.0.0 | lisp / plcopen | 伺服精密压装工站八态（待机/接近/压入/保压/回退/判定/完成/故障）：压入段逐拍做位移-压力包络窗口校验（上下限按位移节点线性插值，节点 ≤32、防死锁二分定位），提取接触点/屈服点/峰值点/终点四特征点，一个循环给出合格结论与 NG 原因位（bit0 上包络越界 / bit1 下包络越界 / bit2 终点未达 / bit3 接触未建立 / bit4 保压压降超限）；屈服判据取「斜率回落至峰值斜率指定比例」而非压力过峰——现场屈服段多为斜率软化（铝壳/塑料件尤甚），强求过峰则单调上升曲线永远判不出 / Servo press-fit station with envelope windowing and four feature points |
| 18 | `FB_DL_RotaryIndexTable` | FB | 404 | 1.0.0 | 包装机械公开手册 | 多工位分度盘节拍调度五态（待机/停留/分度中/稳定中/故障）：管理「分度请求 → 到位确认 → 稳定等待 → 工位工艺放行」链条，维护工位启用表与工艺号映射，支持空跑（清洗）模式逐位走完；`eSettling` 单独成态隔离「到位后抖动」诊断窗，把机械抖动与分度超时分开归因；稳定窗内到位信号掉沿即判硬件松动并直接锁故障、**不做自动重试**（自动重试会把机械松动掩盖成偶发超时，现场极难定位） / Rotary index table sequencing with settling window and jitter diagnosis |
| 19 | `FB_DL_AgvDockingHandshake` | FB | 385 | 1.0.0 | packml-omac / 包装机械公开手册 | 移动载体与固定工站的会话式对接交接七态：到位须连续两拍为真、双侧就绪须同时成立且连续两拍（滤单拍毛刺），进交接监视时快照物料在位位，过程中该位由真转假即判物料丢失/错位；完成确认在到位或握手阶段提前到达按「非法请求序列」直接锁故障而不吞掉（否则上游误接线会被解释成一次成功交接）；用单一秒表记状态停留时长供现场判读卡在哪一阶段，不额外增引脚 / AGV docking handshake with snapshot consistency and out-of-order diagnosis |
| 20 | `FB_DL_EnergySavingMode` | FB | 400 | 1.0.0 | 批控 / 轻工产线公开手册 | 整线空闲节能编排四态（运行/空闲确认/节能/唤醒）：进入严格按「先降压 → 再停热 → 最后伺服休眠」分台阶执行（伺服休眠时若气源仍为工作压力，抱闸释放瞬间会顶件），退出严格反序；唤醒放行须同时满足「压力达节能目标 + 裕量」「压力低位请求已撤」「唤醒缓冲走完」三条，杜绝望唤醒即放行；三出口全为状态派生式无锁存，任何异常路径下一拍自然复位；节能或唤醒期间压力读数触零或非有限即判无反馈、禁止放行并锁故障 / Line-level idle energy orchestration with staged withdrawal and gated wake |

### 故障码台账追加（R11 码位登记，经终审全库复核）/ Error Code Ledger Additions (R11)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0005_01C0` | 信息级 | 包络表点数超上限已钳位为 32，不置故障位 | FB_DL_PressFitStation |
| `0005_01C1` | 信息级 | 包络上下限对调已在块内镜像修复，不置故障位 | FB_DL_PressFitStation |
| `0005_01C2` | 信息级 | 工位数量越界已钳位至 2~24，不置故障位 | FB_DL_RotaryIndexTable |
| `0005_01C3` | 信息级 | 超时参数越界已钳位，不置故障位 | FB_DL_AgvDockingHandshake |
| `0005_01C4` | 信息级 | 延时或压力参数越界已钳位，不置故障位 | FB_DL_EnergySavingMode |
| `0005_02C0` | 故障级 | 非法状态兜底 | FB_DL_PressFitStation |
| `0005_02C1` | 故障级 | 包络表非法（节点数小于 2、或位移非严格单调递增） | FB_DL_PressFitStation |
| `0005_02C2` | 故障级 | 阶段超时（接近 / 压入 / 保压 三段共用该码） | FB_DL_PressFitStation |
| `0005_02C3` | 故障级 | 采样非有限值（当拍拒绝更新并转故障） | FB_DL_PressFitStation |
| `0005_02D0` | 故障级 | 分度超时（到位信号未在监控窗内建立） | FB_DL_RotaryIndexTable |
| `0005_02D1` | 故障级 | 到位信号抖动或丢失（稳定窗内掉沿），不自动重试 | FB_DL_RotaryIndexTable |
| `0005_02D2` | 故障级 | 工位号越界（机械到位反馈不可信） | FB_DL_RotaryIndexTable |
| `0005_02D3` | 故障级 | 非法状态兜底 | FB_DL_RotaryIndexTable |
| `0005_02E0` | 故障级 | 到位确认超时 | FB_DL_AgvDockingHandshake |
| `0005_02E1` | 故障级 | 握手或交接超时（两处共用，均属未在期望时间内建立期望状态） | FB_DL_AgvDockingHandshake |
| `0005_02E2` | 故障级 | 物料在位信号丢失 | FB_DL_AgvDockingHandshake |
| `0005_02E3` | 故障级 | 非法请求序列（完成确认提前到达） | FB_DL_AgvDockingHandshake |
| `0005_02E4` | 故障级 | 非法状态兜底 | FB_DL_AgvDockingHandshake |
| `0005_02F0` | 故障级 | 唤醒超时（超过两倍唤醒缓冲仍未达压） | FB_DL_EnergySavingMode |
| `0005_02F1` | 故障级 | 气源压力反馈缺失（读数为零或非有限值） | FB_DL_EnergySavingMode |
| `0005_02F2` | 故障级 | 非法状态兜底 | FB_DL_EnergySavingMode |

**号段占用声明**：本批信息级占用 `0005_01C0`~`0005_01C4`（连续五码）；故障级按组件成组分配四块——`02C0`~`02C3`（压装）、`02D0`~`02D3`（分度盘）、`02E0`~`02E4`（对接交接）、`02F0`~`02F2`（节能），块内末码为非法状态兜底。此前的 `02Ax`/`02Bx` 与 `01A0`~`01B4` 为存量占用（R7~R10），本批从 `01C0` / `02C0` 起段，无跨块借用、无回填；终审逐码求差与全库零重叠。

### 变更说明 / Change Notes

- **拓扑互斥、语义不重叠**：分度盘（离散节拍与工位放行）≠ 输送积放（`FB_DL_ConveyorZone` 连续输送）≠ 料仓槽位台账（`FB_DL_BufferMagazine` 空/满/不合格）≠ 线体级联（`FB_DL_ConveyorLineLink` 固定段长连接握手）≠ 移动载体对接（本批 `FB_DL_AgvDockingHandshake` 会话式一次性交接）。五者拓扑与生命周期均不同，禁止互相替代。
- **工站态 vs 全状态机**：本批四件均只做工序自身的**最小态子集**（4~8 态，编号留 10 间隔便于插态），完整十七态包装机状态机仍由 `FB_DL_PackMlStateMachine` 承载，禁止在同一工站内并存两套全状态机。
- **不绑定轴接口**：压装件与辊距件均以工程量引脚注入（位移/压力/指令），块内零硬件与零轴库细节；分度请求以布尔脉冲出口下发，不绑定任何电机或驱动库。
- **参数与统计外置**：四件的统计结构体（`ST_DL_PressFitStat` / `ST_DL_IndexTableStat` / `ST_DL_AgvDockStat` / `ST_DL_EcoStat`）均由调用方持有并经 `VAR_IN_OUT` 传入，掉电保持由上层 `RETAIN` 声明决定，块内不做任何持久化假设。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.6.0 ｜ 2026-11-15 ｜ R10 通用拾放工站模板（九步序 + 七态，1 件）/ R10 Pick & Place Station

**变更性质**：MINOR（新增 1 个组件，终审修复后 v1.0.1），无破坏性变更，无迁移动作。对应 Round 10「DL_Process 通用工站」（来源标签 packml-omac / tcopen-component，RAW_NOTES_R10 S-9/S-10：仅借 PackML 工站级状态命名与 TcOpen 契约分离思想，九步序/码位/实现 100% clean-room）。终审 **PASS with fixes**：缺陷 3 处——**D-01【致命】主 CASE 缺 `eExecute` 标签致执行态被 ELSE 兜底锁故障（三平台永远无法执行）**、D-03【严重】故障停机对未注入的 Y 轴直接 `Stop()` 空引用、D-06【中等】步 1 下发分支清零覆盖同拍错误码；全部修复 → **v1.0.1**。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 16 | `FB_DL_PickAndPlaceStation` | FB | 629 | **1.0.1** | packml-omac / tcopen-component | 标准「取-升-移-放」上下料工站模板：注入 X/Y/Z 轴与真空发生器接口，九步序执行单件搬运（确认原点 → 移到取料位 → 下降 → 吸取确认 → 抬升 → 横移 → 下降 → 破真空 → 抬升回原点），七态最小子集（待机/启动自检/执行/保持中/已保持/中止收尾/故障）；单步三段式（下发一次 → 等条件 → 单拍推进）+ 到位判据 = 轴静止态 + 容差窗双条件 + 节拍统计 + 安灯出口 / Nine-step pick-and-place station template with seven-state subset |

### 故障码台账追加（R10 码位登记）/ Error Code Ledger Additions (R10)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0005_01B0` | 信息级 | Z 轴原点未就绪超时（保持本步重试） | FB_DL_PickAndPlaceStation |
| `0005_01B1` | 信息级 | 真空未建立，本件判 NG | FB_DL_PickAndPlaceStation |
| `0005_01B2` | 信息级 | 前置条件不满足（缺料或放料位占用），业务态加安灯 | FB_DL_PickAndPlaceStation |
| `0005_01B3` | 信息级 | 正常中止完成 | FB_DL_PickAndPlaceStation |
| `0005_01B4` | 信息级 | 节拍统计窗重建 | FB_DL_PickAndPlaceStation |
| `0005_02B0` | 故障级 | X 轴取料位超时 | FB_DL_PickAndPlaceStation |
| `0005_02B1` | 故障级 | Z 轴下降取料超时 | FB_DL_PickAndPlaceStation |
| `0005_02B2` | 故障级 | Z 轴抬升超时 | FB_DL_PickAndPlaceStation |
| `0005_02B3` | 故障级 | X 轴横移超时 | FB_DL_PickAndPlaceStation |
| `0005_02B4` | 故障级 | 搬运中掉件 | FB_DL_PickAndPlaceStation |
| `0005_02B5` | 故障级 | 破真空超时 | FB_DL_PickAndPlaceStation |
| `0005_02B6` | 故障级 | 回原点超时 | FB_DL_PickAndPlaceStation |
| `0005_02B7` | 故障级 | 非法状态或非法步号兜底（**兼循环超时兜底**，见 O-2） | FB_DL_PickAndPlaceStation |

### 变更说明 / Change Notes

- **致命缺陷教训（D-01 / R31 素材）**：枚举 `E_DL_SpState` 定义七值，主 CASE 只列六标签漏 `eExecute`；动作逻辑写在 CASE 之外用 `IF _eState = eExecute` 处理，编码者据此认为「不需标签」→ 实际 `eExecute` 命中 `ELSE` 被非法化并锁故障，随后段 8~11 整段被跳过，**九步序一行不执行**。修法：显式加入 `eExecute` 标签分支，体内**只写注释不写动作**，并在注释中固化「为何必须显式列出」防后续删除。**沉淀 R31「枚举→CASE 双向映射完备性」**。
- **接口适配（总监裁定采纳）**：① 新增 `fSafeZ` / `fPosTol` 两个输入引脚（规格只以文字描述，按「无魔法数」提为引脚，带默认值向后兼容）；② 到位判据改为「`eState = eStandstill` + 位置在容差窗内」——`I_DL_MotionAxis` 无「到位位」属性，此实现语义等价且更严格；③ 循环超时复用兜底码 `02B7`（`01B0~01B4` 与 `02B0~02B7` 已满，按 R30 不得跨块取 `02B8`）。
- **观察项 O-2**：循环超时与「非法状态」共码 `02B7`，HMI 无法区分；下一 MAJOR 为本族扩块（`02C0~02CF`）并拆分。
- **职责边界**：本块只做工站级七态最小子集，**刻意不做 17 态全集**（全集由 `FB_DL_PackMlStateMachine` 承担，避免两套全状态机在同一工站内冲突）。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v0.5.0 ｜ 2026-11-15 ｜ R9 Modbus 轮询调度抽象 + 安灯四级仲裁（T1-4 深化 + T2-7/8 开族）/ R9 Polling Scheduler & Andon Pair

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 09「DL_Process 调度抽象层双件」（来源标签 codesys-forge-modbus（T1-4 CODESYS Forge 续挖，最严口径只借组织分类与参数域）+ andon/omac（T2-7 PackML / T2-8 OMAC 人员响应域开族，ISA-TR88.00.02 公开规范），全部 clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 14 | `FB_DL_ModbusPollMaster` | 功能块 | 530 | 1.0.0 | codesys-forge-modbus | Modbus RTU 轮询主站调度器（**传输抽象层**）：按站表顺序轮询 + 响应超时重试 + 成功/异常双计数台账 + 全跳过节流空转；帧构造/CRC/收发全部归传输层（抽象方法 DoTransaction/SendFrame/RecvFrame 基类桩返回 FALSE + 锁码，杜绝静默假成功），CRC-16/Modbus 公开算法定义仅注释级引用不调用 / Modbus polling master scheduler (transport abstraction layer) |
| 15 | `FB_DL_AndonCallSystem` | 功能块 | 394 | 1.0.0 | andon/omac | 车间安灯四级呼叫系统（缺料/品质/设备/维修）：显式优先级仲裁（不依赖枚举数值序，维修 > 设备 > 品质 > 缺料）+ 抢占重锁重建升级计时 + 应答时长最近值/滚动均值统计（增量式防溢出）+ 班次清零不清激活呼叫；与 FB_DL_SignalTower（塔灯驱动）正交可配套 / Four-level Andon call system with priority arbitration |

### 故障码台账追加（R9 码位登记，经终审核实空闲）/ Error Code Ledger Additions (R9)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0005_0190` | 信息级 | 站数越界已钳位到 1..16 | FB_DL_ModbusPollMaster |
| `0005_0191` | 信息级 | 站表全部跳过，本轮无事务（按间隔节流空转） | FB_DL_ModbusPollMaster |
| `0005_0192` | 信息级 | 单站重试耗尽，异常台账已累加（继续轮询不停摆） | FB_DL_ModbusPollMaster |
| `0005_0193` | 信息级 | 超时/间隔参数非法已兜底 | FB_DL_ModbusPollMaster |
| `0005_01A0` | 信息级 | 未应答即解除（应答统计不计入） | FB_DL_AndonCallSystem |
| `0005_01A1` | 信息级 | 多源同拍或高优先级抢占重锁 | FB_DL_AndonCallSystem |
| `0005_0290` | 故障级 | 传输层未实现（抽象方法桩未被覆盖） | FB_DL_ModbusPollMaster |
| `0005_0291` | 故障级 | 站表索引越界（越界保护触发） | FB_DL_ModbusPollMaster |
| `0005_0292` | 故障级 | 非法状态兜底（枚举越界） | FB_DL_ModbusPollMaster |
| `0005_02A0` | 故障级 | 激活呼叫级别非法（内部一致性破坏） | FB_DL_AndonCallSystem |
| `0005_02A1` | 故障级 | 非法状态兜底（枚举越界） | FB_DL_AndonCallSystem |

- **偏离留档**：规格建议故障码 0005_0293 未使用（站数非法按钳位 + 信息级处置，不停机），终审接受。
- **终审双 PASS（零修改）**：ModbusPollMaster 六态全部可达可出、WHILE 回绕找站带 16 上限守卫、双定时器「先算后喂 + 调用后自清」；AndonCallSystem 抢占重锁重建、增量滚动均值防溢出、班次清零语义写死；观察项 O-03/O-04（事务中途撤销闸门、异步覆写口文档强化）留档 v1.1。

### 变更说明 / Change Notes

- **调度抽象层红线**：调度层零触碰帧内容——不解析功能码、不读写应答字节、不做 CRC 运算；「异步集成必须覆写 DoTransaction」已在文件头集成示例与手册声明（观察项 O-04 建议手册强化）。
- **安灯仲裁可维护性**：显式 IF 链仲裁而非依赖枚举数值排序——后续插入新级别时数值序与业务序脱钩不会改变仲裁结果；枚举数值仅作对外权重标识供 HMI 排序。
- **红线状态**：R1~R8 全部通过，机检 0 命中。

---

## v0.4.0 ｜ 2026-11-15 ｜ R8 线体/配方/检测/搅拌/清洗/料仓六件（T1-4 CODESYS Forge 开组 + T2-2 LBP / T2-8 ISA-88 深化）/ R8 Process Six-Piece Set

**变更性质**：MINOR（新增 6 个组件）+ PATCH（6 个文件终审修复 → v1.0.1），无破坏性变更，无迁移动作。对应 Round 08「DL_Process 线体握手 / 配方管理 / 气密检测 / 搅拌混合 / CIP 清洗 / 缓冲料仓」（来源标签 smema-handshake / codesys-forge-recipe / leak-test / isa-88-mix / cip-clean / buffer-magazine，T1-4 CODESYS Forge 开组 + T2-2 LBP / T2-8 ISA-88 深化，SMEMA·压降法·ISA-88 相语义·CIP 六相公开语义 clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 8 | `FB_DL_ConveyorLineLink` | 功能块 | **1.0.1** | smema-handshake | 相邻机台/线体段级联握手协调器（SMEMA 式 BA/MR/INH 干接点语义）：三路消抖 + 一行布尔式握手判据（同拍冲突保守侧不放行）+ 传递看门狗（小于消抖窗两倍自动提升）+ 维护直通（须审计）+ 质量 NG 透传；本块只做握手编排不驱动执行机构（v1.0.1：消抖断输入掩码误当 IN 入参致消抖完全失效修复） / SMEMA-style inter-machine handshake coordinator |
| 9 | `FB_DL_RecipeManager` | 功能块 | **1.0.1** | codesys-forge-recipe | 通用配方管理器（参数清单 + 值集 + 32 位滚动异或校验和）：校验链六层逐项（域→启用→个数→非有限值→上下限→校验和）+ 应用单拍全量写入防半套参数 + 复核回读比对 + 写回校验和清零（不伪造）+ 机台稳态切换防呆 + 变更审计；零文件 I/O，配方库与运行参数引脚注入（v1.0.1：孤立分号修复） / Recipe manager with rolling-XOR checksum chain |
| 10 | `FB_DL_LeakTestStation` | 功能块 | **1.0.1** | leak-test | 气密泄漏测试工站（压降法）：夹具确认→充气→稳压→隔离测量（温度补偿按开尔文温比）→安全排气；泄漏率 kPa·mL/min 工艺约定口径 + 大漏快判 + 设备异常与工件 NG 严格分离（NG 不置 bError）（v1.0.1：孤立分号修复） / Pressure-decay leak test station |
| 11 | `FB_DL_MixRecipeControl` | 功能块 | **1.0.1** | isa-88-mix | 搅拌配方控制（ISA-88 相语义，IMPLEMENTS 驱动经 `I_DL_VfdDrive` 注入）：前置确认→转速建立确认窗→混合计时（正反交替换向带停转间隔）→终点判据（时间 / 扭矩上升二选一）→出料→停转；最长混合时间超时判 NG（v1.0.1：致命 _bNg 符号未声明 + eNg 终态不可达死代码 + bOk/bNg 保持语义修复 + 孤立分号修复） / ISA-88 mixer recipe control consuming I_DL_VfdDrive |
| 12 | `FB_DL_CipCleaningSeq` | 功能块 | **1.0.1** | cip-clean | CIP 六相清洗序列（预冲/碱/中冲/酸/终冲/消毒）：TACT（温度/电导/流量）三路联锁暂停不计时 + 暂停上限判相失败 + 终冲回液电导率终点（超时兜底）+ 各相启用启动快照（中途改写不生效）+ CIP 完成许可放行生产（v1.0.1：孤立分号修复） / CIP six-phase cleaning sequence with TACT interlocks |
| 13 | `FB_DL_BufferMagazine` | 功能块 | **1.0.1** | buffer-magazine | 缓冲料仓三策略选层：自动（首空/首满按请求类型）+ 手动指定层 + NG 隔离位优先；升降目标层换算 + 到位消抖 + 双超时护栏；槽位状态 `E_DL_SlotState` 数组由本块维护、全满/全空/NG 计数每拍重算（v1.0.1：孤立分号修复） / Buffer magazine with three-layer selection strategies |

### 随组件同文件发布的 DUT / DUTs Shipped with Host Files

`E_DL_LineLinkState`（随 #8）；`E_DL_RecipeState` + `ST_DL_RecipeEntry`（随 #9）；`E_DL_LeakPhase`（随 #10）；`E_DL_MixPhase`（随 #11）；`E_DL_CipPhase`（随 #12）；`E_DL_MagState` + `E_DL_SlotState`（随 #13）——共 7 个枚举 + 1 个结构体，与各自宿主文件同文件发布。

### 故障码台账追加（R8）/ Error Code Ledger Additions

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0005_0130` | 信息级 | 下游抑制解除，恢复放行 | FB_DL_ConveyorLineLink |
| `0005_0131` | 信息级 | 维护直通生效（每拍重算） | FB_DL_ConveyorLineLink |
| `0005_0132` | 信息级 | 握手信号同拍冲突（保守侧不放行） | FB_DL_ConveyorLineLink |
| `0005_0133` | 信息级 | 看门狗被自动提升至消抖窗两倍 | FB_DL_ConveyorLineLink |
| `0005_0140` | 信息级 | 配方未启用校验和（uChecksum=0） | FB_DL_RecipeManager |
| `0005_0141` | 信息级 | 机台非稳态，加载被拒（切换防呆联锁） | FB_DL_RecipeManager |
| `0005_0142` | 信息级 | Load/Save 同拍冲突，双丢弃（不猜） | FB_DL_RecipeManager |
| `0005_0143` | 信息级 | 参数个数越界钳位 | FB_DL_RecipeManager |
| `0005_0150` | 信息级 | 泄漏率上限为负，取绝对值 | FB_DL_LeakTestStation |
| `0005_0151` | 信息级 | 测量窗压力回升（ΔP<0），按 0 处理 | FB_DL_LeakTestStation |
| `0005_0152` | 信息级 | 温度补偿已关闭，按原始压降判定 | FB_DL_LeakTestStation |
| `0005_0153` | 信息级 | 大漏快判触发（提前判 NG） | FB_DL_LeakTestStation |
| `0005_0160` | 信息级 | 转速设定越界钳位 | FB_DL_MixRecipeControl |
| `0005_0161` | 信息级 | 混合时间与最长混合时间对调自修复 | FB_DL_MixRecipeControl |
| `0005_0162` | 信息级 | 最长混合时间到，判 NG | FB_DL_MixRecipeControl |
| `0005_0163` | 信息级 | 以扭矩上升为终点判据触发 | FB_DL_MixRecipeControl |
| `0005_0164` | 信息级 | 交替周期被提升至两倍确认窗 | FB_DL_MixRecipeControl |
| `0005_0170` | 信息级 | 运行中跳相请求被拒（启用数组中途改写不生效） | FB_DL_CipCleaningSeq |
| `0005_0171` | 信息级 | 回路未就绪，泵指令被抑制 | FB_DL_CipCleaningSeq |
| `0005_0172` | 信息级 | TACT 信号非有限值，保守侧暂停 | FB_DL_CipCleaningSeq |
| `0005_0173` | 信息级 | 相切换停泵间隔中（防混液） | FB_DL_CipCleaningSeq |
| `0005_0180` | 信息级 | 无满槽可取（料仓空） | FB_DL_BufferMagazine |
| `0005_0181` | 信息级 | 无空槽可存（料仓满） | FB_DL_BufferMagazine |
| `0005_0182` | 信息级 | 无 NG 隔离位可用 | FB_DL_BufferMagazine |
| `0005_0183` | 信息级 | 手动指定层与请求类型不匹配 | FB_DL_BufferMagazine |
| `0005_0184` | 信息级 | 层数越界钳位 | FB_DL_BufferMagazine |
| `0005_0185` | 信息级 | 运行中改手动层，下周期生效 | FB_DL_BufferMagazine |
| `0005_0186` | 信息级 | 取/存请求同拍冲突，双丢弃 | FB_DL_BufferMagazine |
| `0005_0230` | 故障级 | 传递超时（卡料），锁存 | FB_DL_ConveyorLineLink |
| `0005_0231` | 故障级 | 非法状态兜底 | FB_DL_ConveyorLineLink |
| `0005_0240` | 故障级 | 配方号越界 / 未启用，锁存 | FB_DL_RecipeManager |
| `0005_0241` | 故障级 | 参数个数与配方定义不一致，锁存 | FB_DL_RecipeManager |
| `0005_0242` | 故障级 | 配方参数含非有限值，锁存 | FB_DL_RecipeManager |
| `0005_0243` | 故障级 | 配方参数越界，锁存 | FB_DL_RecipeManager |
| `0005_0244` | 故障级 | 校验和不匹配（配方损坏），锁存 | FB_DL_RecipeManager |
| `0005_0245` | 故障级 | 应用后复核失败（写入异常），锁存 | FB_DL_RecipeManager |
| `0005_0246` | 故障级 | 非法状态兜底 | FB_DL_RecipeManager |
| `0005_0250` | 故障级 | 夹具闭合超时，锁存 | FB_DL_LeakTestStation |
| `0005_0251` | 故障级 | 充气超时未达压（大漏常见表现），锁存 | FB_DL_LeakTestStation |
| `0005_0252` | 故障级 | 稳压结束压力超容差（设备异常），锁存 | FB_DL_LeakTestStation |
| `0005_0253` | 故障级 | 排气超时，锁存 | FB_DL_LeakTestStation |
| `0005_0254` | 故障级 | 压力/温度/容积/阈值输入非有限值，锁存 | FB_DL_LeakTestStation |
| `0005_0255` | 故障级 | 腔容积非法（≤0，除零防护），锁存 | FB_DL_LeakTestStation |
| `0005_0256` | 故障级 | 测量时长为零，锁存 | FB_DL_LeakTestStation |
| `0005_0257` | 故障级 | 非法状态兜底 | FB_DL_LeakTestStation |
| `0005_0260` | 故障级 | 前置条件不成立超时（料/阀/驱动），锁存 | FB_DL_MixRecipeControl |
| `0005_0261` | 故障级 | 转速未在确认窗内建立，锁存 | FB_DL_MixRecipeControl |
| `0005_0262` | 故障级 | 出料超时，锁存 | FB_DL_MixRecipeControl |
| `0005_0263` | 故障级 | 扭矩超保护上限（疑似卡桨），锁存 | FB_DL_MixRecipeControl |
| `0005_0264` | 故障级 | 转速/扭矩信号非有限值，锁存 | FB_DL_MixRecipeControl |
| `0005_0265` | 故障级 | 非法状态兜底 | FB_DL_MixRecipeControl |
| `0005_0270` | 故障级 | 单相联锁暂停超限（相失败），锁存 | FB_DL_CipCleaningSeq |
| `0005_0271` | 故障级 | 终冲洗超最长延时未达电导终点，锁存 | FB_DL_CipCleaningSeq |
| `0005_0272` | 故障级 | 启用相目标时长为零，锁存 | FB_DL_CipCleaningSeq |
| `0005_0273` | 故障级 | 回路未就绪强行启动，锁存 | FB_DL_CipCleaningSeq |
| `0005_0274` | 故障级 | 非法状态兜底 | FB_DL_CipCleaningSeq |
| `0005_0280` | 故障级 | 升降超时未到位，锁存 | FB_DL_BufferMagazine |
| `0005_0281` | 故障级 | 取放动作超时，锁存 | FB_DL_BufferMagazine |
| `0005_0282` | 故障级 | 升降层位置越界（限位/编码器异常），锁存 | FB_DL_BufferMagazine |
| `0005_0283` | 故障级 | 非法状态兜底 | FB_DL_BufferMagazine |

全部经子库码表核对顺延，冲突 0。

### 终审缺陷修复（6 文件 → v1.0.1）/ Final-Review Fixes

| # | 级别 | 组件 | 缺陷与修法 / Defect and fix |
|---|---|---|---|
| 1 | **致命** | `FB_DL_MixRecipeControl` | `_bNg` 输出符号未声明即赋值，编译阻断；补声明并随输出保持语义一并修复 / Undeclared `_bNg` symbol blocked compilation; declared and fixed with hold semantics |
| 2 | 严重 | `FB_DL_MixRecipeControl` | eNg 终态不可达——最长混合时间超时分支写为死代码（判据在终态外求值恒 FALSE），NG 判定永不落地；超时分支移入可达路径 / eNg terminal state unreachable; timeout branch was dead code |
| 3 | 严重 | `FB_DL_MixRecipeControl` | bOk/bNg 仅在进入态一拍置位（脉冲）而非保持，与「完成保持态」规格语义失效；改为保持态内逐拍重写、复位/新启动沿清除（R27 规则首例素材） / bOk/bNg held verdicts degraded to one-scan pulses; rewritten as held semantics (first material of rule R27) |
| 4 | 严重 | `FB_DL_ConveyorLineLink` | 三路消抖的断输入掩码误当 TON 的 IN 入参使用——消抖定时器输入恒为掩码位而非信号位，消抖完全失效、毛刺直通；危险侧（抑制/可收误动作）。修法：IN 接信号位，掩码仅用于强制 ET 归零的断输入拍 / Debounce break mask mistakenly wired as TON IN; debounce fully defeated, glitch pass-through on the dangerous side. IN rewired to signal, mask only used for the one-scan break |
| 5 | 中等 | 5 个文件 9 处 | 终端态分支内孤立分号空语句（statement_list 不容纳孤立分号，文法合规性）——MixRecipeControl / RecipeManager / LeakTestStation / CipCleaningSeq / BufferMagazine，全部改为纯注释占位分支，行为等价 / Isolated-semicolon empty statements in terminal-state branches replaced by comment-only branches (rule R26 material) |
| 6 | 注释级 | 2 处 | 头注释码位占位与观察项表述对齐终审裁定（逻辑零变更） |

修后机检 ALL PASS（fail=0，banned_hits=0，16 文件 6987 行）。

### 终审观察项（留档 v1.1）/ Final-Review Observations

泄漏率量纲 kPa·mL/min 工艺约定的「压降-流量」统一换算评估留 v1.1（详见 `DL_Motion/VERSION.md` v0.4.0 节观察项①——该观察项横跨两子库，归并在 Motion 侧登记）。

### 变更说明 / Change Notes

- **T1-4 CODESYS Forge 首次开组**：`FB_DL_RecipeManager` 借鉴 Forge/Store 公开免费示例的「配方名 / 启用位 / 参数值集 / 校验和」组织分类与「校验→应用→复核」相语义；所据示例页面未显式声明许可条款，按最严口径处置——只借结构与参数域，零代码行复制，结构体字段 / 状态机 / 码位 / 引脚契约 100% 本库独立设计。
- **接口消费**：`FB_DL_MixRecipeControl` 经 `I_DL_VfdDrive` 既有契约注入驱动（IMPLEMENTS 语义消费，每拍至多一次方法调用）；`FB_DL_ConveyorLineLink` 与 `FB_DL_ConveyorZone` 衔接约定在头注释声明（bMachineReadyOut ↔ bDownstreamReady 交叉互连），不引实例。
- **设备异常 / 工件不合格分离**：LeakTestStation 与 TorqueLimitControl（DL_Motion）同构判定层——工件 NG 不置 bError，只出判定与信息级提示，不污染设备报警链。
- **TACT 联锁暂停不计时**：CIP 各相目标时长只对「三路 TACT 全部达标」的时段累计，联锁暂停期间计时冻结——暂停上限超时判该相失败，避免「脏水凑时长」。
- **红线状态**：R1~R7 全部通过，机检 0 命中；R23 纯事件型免首扫（六件均无 bInit）；R25 单拍标志三律逐条落实；R26（孤立分号禁用）与 R27（输出保持语义）自本轮起正式生效。

---

## v0.3.0 ｜ 2026-11-15 ｜ R7 统计/输送/配料三件（T2-7 PackML / T2-2 LBP + T2-8 ISA-88 深化）/ R7 Process Trio

**变更性质**：MINOR（新增 3 个组件）+ PATCH（3 个文件终审修复 → v1.0.1），无破坏性变更，无迁移动作。对应 Round 07「DL_Process OEE 统计 + 输送线积放 + 配料称重」（来源标签 packml-oee / conveyor-accumulation / lbp-batch-dosing / isa-88，oee.com·ISO 22400-2·ZPA 工程惯例·ISA-88 批次相公开语义 clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 5 | `FB_DL_OeeCalculator` | 功能块 | **1.0.1** | packml-oee | 设备综合效率班次统计引擎（oee.com / ISO 22400-2 公开口径）：三因子 = 时间开动率 × 性能开动率 × 合格品率；停机时间经 PackML 根因位分账（计划/计划外，双真歧义入计划外保守侧）；周期基准引脚注入禁读 CPU 钟；性能率超 100 封顶置信级（v1.0.1：nGoodCount 无符号下溢防御 + tShiftLength 预留语义标注） / OEE shift statistics engine with PackML root-cause attribution |
| 6 | `FB_DL_ConveyorZone` | 功能块 | **1.0.1** | conveyor-accumulation | 单段输送线积放控制器（Zero-Pressure Accumulation）：积放单句规则「有料且下游允许才走」、run-on 清区、卡料窗锁存、级联放行 bZoneReady、浪涌防护；驱动经 `I_DL_VfdDrive` 接口引用注入、每拍至多一次方法调用（v1.0.1：手动放行绕过门控修复 + run-on 延续窗补齐契约） / ZPA conveyor zone controller consuming I_DL_VfdDrive |
| 7 | `FB_DL_BatchDosingControl` | 功能块 | **1.0.1** | lbp-batch-dosing/isa-88 | 多原料单通道配料称重控制器（ISA-88 批次相语义）：快加→慢加→落定三段顺控 + 空中落差自学习（误差/2 防振荡、钳位触限置信级）+ 超差 NG 锁存卸料禁止 + 断流诊断；非有限值重量批次中止全断；Abort 电平最高优先（v1.0.1：判稳死锁——单拍重启标志永不自清（致命，R25 家族第二例）+ 皮重/落差补偿 NaN 防御） / Batch dosing controller with in-flight compensation learning |

### 变更说明 / Change Notes

- **根因位衔接**：`FB_DL_OeeCalculator` 的 `bHeldByMachine` / `bSuspendedByLine` 与 `FB_DL_PackMlStateMachine` 的 OEE 根因正交位逐字对齐（引脚注入，不引组件实例）。
- **接口消费**：`FB_DL_ConveyorZone` 仅引用 `I_DL_VfdDrive` 既有契约文件（零修改零新增 DUT），遵守公约 0.13「每拍至多一次接口方法调用」。
- **故障码台账追加（R7）**：`0005_0110~0115`（信息级）、`0005_0200 / 0212~0214 / 0220~0223`（故障级），经子库码表核对顺延（与 OccScheduleWindow / EnthalpyCompareCtrl 冲突 3 处依公约 0.8 顺延）。
- **红线状态**：R1~R7 全部通过，机检 0 命中；R23 事件型免首扫、R24/R25 单拍标志范式逐条落实。

---

## v0.2.0 ｜ 2026-11-15 ｜ R6 行业池 P0 链路闭环示范 / R6 Industry-Pool P0 Chain Demonstrators

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 06（R6）行业池 9.5 节 P0 两件（来源标签 oscat-building / lgf-datetime / hvac）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 3 | `FB_DL_EnthalpyCompareCtrl` | 功能块 | **1.0.1** | oscat-building+hvac | 焓差经济器执行块（直接消费 `FC_DL_HumidAirEnthalpy`）：新风/回风双侧焓值 → 差分焓值施密特迟滞判据 → 新风阀位指令，最小新风位硬下限、ASHRAE 90.1 焓值高限停机、输入失效安全侧冻结 / Differential-enthalpy economizer control block |
| 4 | `FB_DL_OccScheduleWindow` | 功能块 | 1.0.0 | lgf-datetime+hvac | 多窗作息排程：内部 4 实例复用 `FB_DL_TimeWindowCheck` + `FC_DL_DayOfWeekCalc`，每日窗矩阵 + 星期使能（ISO 序）+ 节假日覆盖 + 跨零点窗预启动回绕 + 多窗最小号仲裁 / Multi-window occupancy schedule |

### 故障码台账追加 / Error Code Ledger Additions

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0005_0103` | 信息级 | 下游算法函数钳位码透传归并（温度/湿度/大气压钳位提示） | FB_DL_EnthalpyCompareCtrl |
| `0005_0201` | 故障级 | 非法状态兜底（与 PackML 同码同义复用，终审裁定留档） | FB_DL_EnthalpyCompareCtrl |
| `0005_0202` | 故障级 | 焓值计算输入失效（非有限值/越引脚域，锁存，安全侧冻结） | FB_DL_EnthalpyCompareCtrl |
| `0005_0210` | 信息级 | 日期参数越界（年/月/日，星期换算返回非法） | FB_DL_OccScheduleWindow |
| `0005_0211` | 信息级 | 窗时刻参数越界（各窗实例码不透传，本块归并自身码） | FB_DL_OccScheduleWindow |
| `0005_0110` | 信息级 | 双停机根因同真（分账歧义，计划外优先） | FB_DL_OeeCalculator |
| `0005_0111` | 信息级 | 性能率超 100 封顶（负损失提示） | FB_DL_OeeCalculator |
| `0005_0112` | 信息级 | 零计划时间（班次未激活/计划时间零） | FB_DL_OeeCalculator |
| `0005_0113` | 信息级 | 卡料预警（计时中未到窗） | FB_DL_ConveyorZone |
| `0005_0114` | 信息级 | 稳窗超时按当前值结算 | FB_DL_BatchDosingControl |
| `0005_0115` | 信息级 | 补偿学习触限 | FB_DL_BatchDosingControl |
| `0005_0200` | 故障级 | 理想节拍非法（非有限值/非正值，锁存） | FB_DL_OeeCalculator |
| `0005_0212` | 故障级 | 驱动指令-反馈失配（锁存） | FB_DL_ConveyorZone |
| `0005_0213` | 故障级 | 下游驱动故障透传（锁存） | FB_DL_ConveyorZone |
| `0005_0214` | 故障级 | 非法状态兜底 | FB_DL_ConveyorZone |
| `0005_0220` | 故障级 | 断流/堵料（监视窗内重量零进给） | FB_DL_BatchDosingControl |
| `0005_0221` | 故障级 | 秤信号无效（非有限值，批次中止全断） | FB_DL_BatchDosingControl |
| `0005_0222` | 故障级 | 非法状态兜底 | FB_DL_BatchDosingControl |
| `0005_0223` | 故障级 | 配方参数非法（fSetpoint 域外） | FB_DL_BatchDosingControl |


> `FB_DL_OccScheduleWindow` 信息级码占用 `02xx` 段为**有意裁定**：日历排程块全部事件均为信息级（无安全联锁），故障级段整体保留给后续工艺联锁件，头注释显式声明（终审维持 PASS）。

### 变更说明 / Change Notes

- **链路闭环示范定位**：两件均为行业池 9.5 节 P0 条目，直接消费 R5 落地的焓值/日历/时间窗组件——验证「Level 1 组件 → Level 2 模板」的依赖注入链路真实成立。
- **差分焓值判据（ASHRAE 90.1 公开语义 clean-room）**：开侧「新风焓 < 回风焓 − 死区」、关侧「新风焓 > 回风焓 + 死区」施密特迟滞防临界抖动；最小新风位硬下限为卫生通风底线。
- **终审修复**：`FB_DL_EnthalpyCompareCtrl` 三个参数类 REAL 输入补非有限值防御（自比检测兜底回落默认值后再钳位；高限门限补显式自比检测）→ v1.0.1；D4 专项裁定：负干球经焓值链钳位为保守安全侧偏差（经济器少开、不引入高焓空气），维持现状 PASS。
- **多窗排程边界**：跨零点窗、预启动带回绕（T#24H 回绕式，lead≤start 与 lead>start 两分支边界连续）、节假日覆盖（折入窗使能）、日期越界降级（星期表全 FALSE 自然不在窗）——逐项终审推演通过。

### 已知限制 / Known Limitations

1. `FB_DL_EnthalpyCompareCtrl` 负干球温度经焓值计算链钳位至 0 摄氏度——新风焓偏高估计，误差方向恒为保守安全侧，仅损失潜在免费冷量（能效项非安全项）；高精度冷量计量需求另行立项「冰面修正版焓值 FC」。
2. `FB_DL_EnthalpyCompareCtrl` 输出为阀位指令值，最小新风位的物理保证由调用方阀执行层完成（本块输出下限恒 ≥ `fMinOaPos`）。
3. `FB_DL_OccScheduleWindow` 无故障锁存位（全事件信息级）；`uActiveWin` 多窗同开取最小号，非并行占用指示。

---

## v0.1.0 ｜ 2026-11-15 ｜ DL_Process 立项 / Initial Release — DL_Process Opening

**变更性质**：初始发布（Initial release），无破坏性变更，无迁移动作。全部 2 个组件自 v1.0.0（组件级）起入库，对应 Round 05（R5）「DL_Process 族」交付（来源标签 packml / OMAC PackML · ISA-TR88.00.02 公开规范语义）。

### 组件清单 / Component Inventory

| # | 组件 / Component | 类型 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 1 | `FB_DL_PackMlStateMachine` | 功能块 | 1.0.0 | packml | PackML / ISA-TR88.00.02 十七态（+ Undefined 占位）状态机 clean-room 框架：命令驱动 + acting 态 `bStateComplete` 自动推进，Aborting 最高优先级出口，机内保持/机外挂起 OEE 根因区分，模式切换仅稳态受理 / PackML state machine framework, 17 states + Undefined |
| 2 | `FB_DL_PackMlCmdDecoder` | 功能块 | 1.0.0 | packml | PackML 标准命令解码器：十个离散命令源 + 可选命令字入口（bit0..bit9）双通道收口，最小脉宽防抖单发化，同拍多命令冲突位全部丢弃（安全侧「不猜」）/ PackML command decoder with one-shot emission and conflict rejection |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_PackMlState`（17 项，随 #1）、`E_DL_PackMlCmd`（11 项，随 #1）、`E_DL_UnitMode`（16 项，随 #1）——共 3 个，全部与 `FB_DL_PackMlStateMachine` 同文件发布；`FB_DL_PackMlCmdDecoder` 直接引用 `E_DL_PackMlCmd`，不在本文件重复声明（枚举依赖见该文件头注释）。

### 变更说明 / Change Notes

- **接口契约**：2 个组件的引脚名称、类型、方向、默认值与终审后源码声明区逐字一致；引脚级细节以 `DL_Process/*.st` 为准，完整接口表见 `MANUAL_DL_Process.md`。
- **故障码**：全部使用 `16#0005_xxxx` 段：信息级 `0005_0101`（非稳态模式切换被拒）、`0005_0102`（同拍多命令冲突全部丢弃，仅 `uErrorId` 可观察、无故障锁存语义）；故障级 `0005_0201`（非法状态兜底，走 Aborting 路径）。信息级码不置任何故障位（R19/R21 公约）。
- **状态编号契约**：`E_DL_PackMlState` 编号严格对齐 OMAC PackML 公开规范（eUndefined=0 … eCompleted=17），acting/wait 分类写入逐项注释；命令字位域 bit0=Reset … bit9=Complete，bit10..15 保留（掩码 `16#03FF` 截取）。
- **规格偏离留档（R11）**：两组件规格引脚表均未列 `uErrorId`，为信息级出码各补充输出引脚（无故障锁存语义）。
- **职责单一**：解码器不做跃迁判断（执行侧拒绝是状态机的职责，冲突优先级仅用于显示仲裁）；状态机不编排任何工艺动作（Level 2 依赖注入原则）。
- **红线状态**：R1~R7 全部通过，机检 0 命中；R19 首扫/跟踪范式（`IF bTrack OR (NOT bInit)`，首扫自 eUndefined 迁入 eStopped）逐条落实。

### 已知限制 / Known Limitations

1. `FB_DL_PackMlStateMachine` 是纯状态机框架，不含任何工艺动作：配方、节拍、OEE 统计等由调用方按 `eState` 派发，或待后续轮次 `FB_DL_OeeCalculator` 等组件承接。
2. `FB_DL_PackMlCmdDecoder` 冲突位 `bCmdConflict` 为瞬态输出（仅冲突拍为 TRUE），HMI 弹窗提示需调用方自行锁存——本块刻意不做锁存以免故障码污染。
3. `uLastCmd` 为「末次受理」而非「当前请求」：冲突拍与空拍均不改写。
4. 命令电平须持续 `tMinPulse` 才发放单拍脉冲：脉宽设定小于任务周期时命令可能跨拍不足被吞，默认 `T#100MS` 在 10ms 任务下有 10 拍裕量。

---


## v0.13.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 7 件（行业工艺站（锂电/光伏/公用工程/锅炉/暖通，ROADMAP P1））

- `FB_DL_BatchTransferSeq` v1.0.0→**v1.0.2**（R22 挂账修订：bAbort 中止两段化——xCoastStop + tPumpCoastTime 惰转窗→关阀，新故障码 0005_0317，五条验收向量推演通过；引脚新增 xCoastAbort/tCoastTime 向后兼容）。
- `FB_DL_ElectrolyteDosingSeq`：电解液定量注液 ISA-88 节拍链（抽液→称重→粗注→细注→静置，中止两段化，v1.0.1 补确认窗/惰转窗组态闸）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_NailMachineSeq`：打钉机送钉-打钉顺控站（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_LamHeaterZoneSync`：层压机加热板多温区同步跟随（区差阈值 + 链速联动）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_SteamCondensatePot`：凝液罐液位-排放顺控（液位双限 + 排水阀间歇）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_AirCompDutyN2`：空压机/制氮机组联产轮值（负荷排序 + 优先级投切）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_BoilerThreeElement`：锅炉三冲量给水控制（水位主回 PID + 蒸汽前馈 + 给水反馈比偏诊断，手/自无扰切换）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_HumidityOverride`：除湿优先模式仲裁（覆盖触发/释放双确认窗 + 迟滞回差，v1.0.1 注释对齐）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Process] = 41，本文档原记 32（历史批次漏计，随本节一并校正）；本轮已校正为注册表口径。

> **终审留痕**：BoilerThreeElement 主控修未声明标识符（fSteamFlow→fSteamFlowTh）后终审 PASS（前馈符号与 PID 跟踪反算自洽推演过）；ElectrolyteDosingSeq / HumidityOverride 终审升 v1.0.1；`FB_DL_BatchTransferSeq` v1.0.2（R22 挂账中止两段化闭合，见修订记录）。


## v0.13.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 7 件（行业工艺站（锂电/光伏/公用工程/锅炉/暖通，ROADMAP P1））

- `FB_DL_ElectrolyteDosingSeq`：电解液定量注液 ISA-88 节拍链（抽液→称重→粗注→细注→静置，中止两段化，v1.0.1 补确认窗/惰转窗组态闸）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_NailMachineSeq`：打钉机送钉-打钉顺控站（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_LamHeaterZoneSync`：层压机加热板多温区同步跟随（区差阈值 + 链速联动）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_SteamCondensatePot`：凝液罐液位-排放顺控（液位双限 + 排水阀间歇）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_AirCompDutyN2`：空压机/制氮机组联产轮值（负荷排序 + 优先级投切）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_BoilerThreeElement`：锅炉三冲量给水控制（水位主回 PID + 蒸汽前馈 + 给水反馈比偏诊断，手/自无扰切换）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FB_DL_HumidityOverride`：除湿优先模式仲裁（覆盖触发/释放双确认窗 + 迟滞回差，v1.0.1 注释对齐）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Process] = 41，本文档原记 41（一致）；本轮已校正为注册表口径。

> **终审留痕**：BoilerThreeElement 主控修未声明标识符（fSteamFlow→fSteamFlowTh）后终审 PASS（前馈符号与 PID 跟踪反算自洽推演过）；ElectrolyteDosingSeq / HumidityOverride 终审升 v1.0.1；`FB_DL_BatchTransferSeq` v1.0.2（R22 挂账中止两段化闭合，见修订记录）。

## 版本号约定 / Versioning Policy

子库遵循 SemVer，且与库总版本联动：

- **MAJOR**：任一组件删除引脚、改引脚语义、改默认值、改故障码含义、状态编号或跃迁语义变化。
- **MINOR**：新增组件，或为已有组件新增可选输入（带默认值）。
- **PATCH**：内部实现修正、注释与手册补全、性能优化，接口与行为不变。

破坏性变更必须在本文档写明迁移指引（旧调用 → 新调用）与影响的组件清单。

---

## 后续计划 / Next

R7 已交付统计/输送/配料三件；R8 已交付线体握手 / 配方管理 / 气密检测 / 搅拌混合 / CIP 清洗 / 缓冲料仓六件；R9 调度抽象与安灯；R10 通用拾放工站；R11 工站四件套（伺服压装 / 分度盘节拍 / 移动载体对接 / 整线节能）；v0.8.0（R12）交付批次相基类与轮询温控组两件，现 22 项（功能块 22）。

`FB_DL_BatchPhaseBase` 是本子库第一件**为派生而设计**的基类件：相序列由派生类在 `aPhase` 数组里填，基类只管转相判定、超时与掉使能复位，派生类**不得重写**转相通道（范式 R39）。`FB_DL_PollTempBank` 补的是「多路温控但只有一台表」的轮询场景，通道切换后必须**断输入一拍**再取值（范式 R40），否则会读到上一通道的残留。

后续按 `ROADMAP.md` 第六章推进：完整批次模型（Procedure/Unit/Recipe）、报警管理与追溯族、包装机全状态机与四件套的联调模板等。


---

## v0.12.0 ｜ 2026-11-16 ｜ R22 结构补位轮 4 件

**批次**：本子库 R22 新增 4 件（全库 20 件 6,618 行；机检 20/20 PASS fail=0）
**码位**：本子库本轮占用见各件头注释「码位总账」；收口后全库游标（注册表实测 2026-11-16）：`0001` 信息 `0466` / 故障 `03B7`、`0002` 下一 CC `2D`、`0003` 信息 `017A` / 故障 `0348`、`0004` 信息 `01DF` / 故障 `02F9`、`0005` 信息 `01E2` / 故障 `0317`
**终审结论**：R22 抽检 14 件高风险件，4 件轻微缺陷修复升 v1.0.1（MotionCmdQueue / VirtualMasterAxis / AxisBrakeSeq / BatchTransferSeq），1 件中等安全相关挂账 R23（BatchTransferSeq 中止时序），其余零缺陷 PASS
**码位跨文件冲突断言**：R22 100 槽定向复测 CLASH=NONE；JSONL 384 条全量 sha256 MATCH（本轮另修复 2 件历史换行口径漂移）

- `FB_DL_CompressorSurgeGuard`：压缩机防喘振（最小流量线按压比修正 + 快开慢关双斜率组合调用 `FB_DL_RateLimiter` + R36 首拍跟踪 + 回差带退出 R41；参数非法阀全开 / 非有限保持末值两条相反安全方向并列；R22 终审推演零缺陷 PASS）。
- `FB_DL_ColumnDpCtrl`：精馏塔压差增量控制（ΔP 死区 + 双向增量 + 防冲塔上限时再沸强制落 fOutMin，抗饱和钳位后不再累加）。
- `FB_DL_InertPurgeSeq`：氮气置换顺控（抽真空-充氮-保压取样三相各一只 TON 断输入转相，循环上限 + 氧分析仪无效禁止放行，bAbort 任意拍三相阀全关）。
- `FB_DL_BatchTransferSeq`：批次物料转移顺控（阀位确认 → 启泵 → 计量转移 → 排空验证 → 关阀停泵，累计量由调用方注入不内联积分；**v1.0.1**——总时长超时分支补置 `bError := TRUE`〔R45 纪律〕；中止路径「先停泵后关阀」缺物理时序分隔挂账 R23，见 ROADMAP §24.1）。

**终审**：本子库 2 件高风险抽检，命中 1 件轻微（BatchTransferSeq 0315 漏 bError）修复升 v1.0.1。

---

## v0.14.0 ｜ 2026-11-17 ｜ R24 行业纵深轮：工艺层 7 新件 + 1 终审修复

**新增 7 件**（码位 0005 段：信息 01F0~01FD / 故障 032D~0341）：

| 组件 | 版本 | 一句话功能 | 来源 |
|---|---|---|---|
| `FB_DL_StringIVTrace` | v1.0.0 | 组串 IV 曲线扫描与特征点提取（Voc/Isc/Pmax/FF 四特征 + 扫描顺控） | ROADMAP P0 §228 |
| `FB_DL_ChamberPumpDownProfile` | v1.0.0 | 腔体抽气曲线包络监视（窗口统计 + 斜率判据早停） | ROADMAP P1 §708 |
| `FB_DL_CartonErectorStation` | v1.0.0→**v1.0.1** | 开箱工站七态九步模板（ISA-88 相-步骤语义，ROADMAP P0 §652）。**R24 终审修复**：fbSeq.bReset 原恒 FALSE，步进引擎 bError 锁存型 → 步超时后故障恢复死锁；改仅 eFault 相透传复位，契约不变 |
| `FB_DL_TrackBarcodeTrace` | v1.0.0 | 托盘条码路由追溯（扫码枪契约 + 分道判据；机检 eNone 落 ELSE 判定经推演裁定为误报留档） | ROADMAP P0 §469 |
| `FB_DL_TankDosingMulti` | v1.0.0 | 多罐轮流定量投加（多实例定量 + 罐序轮值） | ROADMAP P1 §510 |
| `FB_DL_BatchDeviationAlarm` | v1.0.0 | 批次偏差四档分级报警与首出归因（去抖 + 首出锁存 R34 只置不销）。终审 PASS（轻微留档：01FA/01FB 同拍优先级互掩） | ROADMAP P1 §734 |
| `FB_DL_RollCompressForceBalance` | v1.0.0 | 辊压机两侧轧制力平衡监视与液压纠偏（压差窗 + 纠偏闭环 + 限速） | ROADMAP P1 §805 |

---

## v0.15.0 ｜ 2026-11-17 ｜ R25 R25 新增工艺模板 9 件（含 T1-2 ROOM_CONTROL 开族、电池/码垛/接膜/群控/化成/光伏）」 / R25 Batch

**批次**：本轮 20 件中本子库 **9 件**，合计 **3720 行**（全库 20 件 7,097 行，终审修复后 7,174 行）
**码位游标（收口后实测）**：信息级推进至 **`0412`** ｜ 故障级推进至 **`035D`**

| 组件 | 版本 | 一句话功能 / 终审结论 | 来源 |
|---|---|---|---|
| `FB_DL_RoomClimateCtrl` | v1.0.0→**v1.0.1** | 房间温湿度双回路耦合控制（双 PID 分程 + 防结露联锁 + 冷侧优先仲裁）。**R25 终审修复**：补失能出口收口（段 11）——PID 件失能输出回 rOutMin=−100%，经分程映射为 100% 冷却，四阀归零要等下一拍 eIdle，失能沿那一拍破坏「失能=四阀回 0%」契约 | T1-2 OSCAT ROOM_CONTROL 开族第 2 件 |
| `FB_DL_WeightCheckReject` | v1.0.0 | 动态称重与剔除控制（滤波窗 + 剔除反馈拒动诊断 + 停线判据） | ROADMAP P1 §272 |
| `FB_DL_CasePackerPattern` | v1.0.0 | 装箱排列图案生成（容量钳位 + 交错/层旋转） | ROADMAP P1 §273 |
| `FB_DL_BatteryTestCycler` | v1.0.0→**v1.0.1** | 单通道电池充放电工步机（恒流/恒压/静置 + 安时积分 + 温度电压硬判断流）。**R25 终审修复**：补 eFault 独立 CASE 标签——原 eFault(99) 落进 ELSE 兜底支路，每拍把 034B/034C 覆盖成 034D「非法状态」，激励消失后真因码丢失 | ROADMAP P1 §215 |
| `FB_DL_PalletizerLayerSeq` | v1.0.0→**v1.0.1** | 码垛层排布顺控（层容量自算 + 奇偶层旋转经 FC_DL_Affine2Apply + 取放握手重试）。**R25 终审修复**：①旋转层阵外平移量由 fPalletLengthMm 改为 (nRowsEff−1)×箱宽（原式整体多推一个箱宽致首行越界）；②bPalletDone 取消同拍自撤（原同拍置位又撤位，脉冲永不外显） | R24 增补池 §1022 |
| `FB_DL_SplicerAutoJoint` | v1.0.0→**v1.0.1** | 自动接膜零停机顺控（余量面积折算 + 同步双条件 + 未同步绝不裁切）。**R25 终审修复**：eSyncWait 补「进相前置消失」第二退出条件（bNewRollReady 撤销退回 ePreAccel）；遗留挂账：同步相无自有超时，下轮新增 tSyncMax（MINOR） | ROADMAP P1 §280 |
| `FB_DL_ChillerSeqMgr` | v1.0.0 | 冷水机组群控（双延迟加减机 + 轮值委托 FB_DL_DutyStandbyRotation + 供水低温保护） | ROADMAP P1 §288 |
| `FB_DL_FormationChannelMgr` | v1.0.0 | 化成/分容柜多通道调度（分配 + 异常通道隔离锁存 + 台账） | ROADMAP P1 §209 |
| `FB_DL_SolarStringGroundFault` | v1.0.0→**v1.0.1** | 光伏组串对地绝缘阻抗检测（不平衡电桥 + 分级确认锁存）。**R25 终审修复**：组态闸补 fWarnKOhm ≥ 上限哨兵 1.0E9 kΩ → 035A（防哨兵值被判成「低于预警阈值」误报警）；量纲链经总监独立验算裁定除式 Rb×(Vp+Vn)/(Vbus−Vp−Vn) 正确、派单乘式倒置 | R24 增补池 §1023 |

---

## v0.17.0 ｜ 2026-11-18 ｜ R31 暖通焓值夜吹 + 半导体腔体 + 流程计量行业池批：11 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `FB_DL_EnthalpyChangeover` | v1.0.0 | 16#0005_008F |
| `FB_DL_NightPurgeCtrl` | v1.0.0 | 16#0005_0094 |
| `FB_DL_ChamberLeakRate` | v1.0.1（R31 终审修复） | 16#0005_0099 |
| `FB_DL_VacuumChamberSeq` | v1.0.0 | 16#0005_009E |
| `FB_DL_CleanRoomPressure` | v1.0.0 | 16#0005_00A3 |
| `FB_DL_ReactorStepCtrl` | v1.0.1（R31 终审修复） | 16#0005_00A8 |
| `FB_DL_FlowTotalizer` | v1.0.0 | 16#0005_00AD |
| `FB_DL_TankLevelCtrl` | v1.0.0 | 16#0005_00B2 |
| `FB_DL_UtilitiesLoadMgr` | v1.0.0 | 16#0005_00B7 |
| `FB_DL_FilmTensionDancer` | v1.0.1（R31 终审修复） | 16#0005_00BC |
| `FB_DL_HydrostaticLevelComp` | v1.0.0 | 16#0005_00C1 |

> R31 增量行：组件总数 87→**98**（registry 实测口径）；机检 19/19 PASS fail=0；终审抽 5 件（本库 3 件），修 3 处升 v1.0.1（`FB_DL_ChamberLeakRate`、`FB_DL_ReactorStepCtrl`、`FB_DL_FilmTensionDancer`）。

---

## v1.13.0 ｜ 2026-11-18 ｜ R32 行业池 11 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `FB_DL_SteamTrapDiagTrend` | v1.0.0 | 16#0006_3009 |
| `FB_DL_ColumnDpSteadyWatch` | v1.0.0 | 16#0006_300A |
| `FB_DL_VavCouplingFeedforward` | v1.0.0 | 16#0006_300B |
| `FB_DL_BlindPositionCtrl` | v1.0.0 | 16#0006_300F |
| `FB_DL_CompressorFleetStaging` | v1.0.0 | 16#0006_3014 |
| `FB_DL_AhuSupplyAirReset` | v1.0.0 | 16#0006_300C |
| `FB_DL_BatteryModuleBalanceMonitor` | v1.0.0 | 16#0006_300D |
| `FB_DL_WaferThermalBudgetAccum` | v1.0.0 | 16#0006_3023 |
| `FB_DL_CaseSealerFlapFoldSeq` | v1.0.0 | 16#0006_300E |
| `FB_DL_NitrideFurnaceAmmoniaPurge` | v1.0.0 | 16#0006_3010 |
| `FB_DL_BusbarWeldMonitor` | v1.0.0 | 16#0006_3011 |

> R32 增量行：组件总数 98→**109**（registry 实测口径）；机检 20/20 PASS fail=0；终审抽 3 件（本库 3 件）→ **3 件挂账**（`BlindPositionCtrl` 安全收回方向/判据矛盾〔严重〕+ 节拍 TON 不自复位〔中等〕；`CompressorFleetStaging` 错峰 TON 不自复位〔中等〕；`WaferThermalBudgetAccum` 3024 无复位路径〔中等-严重〕+ 批次边界不清预算〔中等〕），本轮**只判不改**以保语料 sha 同步，R33 一并返修。

### R33 增量（1.13.1 → 1.14.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_ChillerLiftOptimize` | v1.0.0 | 16#06_0_37 |
| `FB_DL_FreezeStatGuard` | v1.0.0 | 16#06_0_38 |
| `FB_DL_StackPressureProfile` | v1.0.0 | 16#06_0_39 |
| `FB_DL_PilePressLimitClass` | v1.0.0 | 16#06_0_3A |
| `FB_DL_PressFitCurveArchive` | v1.0.0 | 16#06_0_3B |
| `FB_DL_CartonScannerSort` | v1.0.0 | 16#06_0_3C |
| `FB_DL_PigLauncherSeq` | v1.0.0 | 16#06_0_3D |
| `FB_DL_FormationTempRiseRate` | v1.0.0 | 16#06_0_3E |
| `FB_DL_RollChangeoverSeq` | v1.0.0 | 16#06_0_3F |
| `FB_DL_AndonLinePack` | v1.0.0 | 16#06_0_40 |

> R33 增量行：本库 109 → **119**；机检本库新增件全 PASS；码位全窗口独占无冲突（主控实测）。

### R34 增量（1.13.0 → 1.14.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_LaserWeldPowerSeq` | v1.0.0 | 16#06_0_80 |
| `FB_DL_OcvGradingBin` | v1.0.0 | 16#06_0_81 |
| `FB_DL_ChamberPurgeDry` | v1.0.0 | 16#06_0_82 |
| `FB_DL_LoadlockPressureCross` | v1.0.0 | 16#06_0_83 |
| `FB_DL_StringCurrentMismatch` | v1.0.0 | 16#06_0_84 |
| `FB_DL_PvSoilingLossRate` | v1.0.0 | 16#06_0_85 |
| `FB_DL_TrapSealTrend` | v1.0.1 | 16#06_0_86 |
| `FB_DL_LamTempUniformity` | v1.0.0 | 16#06_0_87 |
| `FB_DL_StratificationGuard` | v1.0.0 | 16#06_0_88 |
| `FB_DL_AndonRespTimeReport` | v1.0.0 | 16#06_0_89 |
| `FB_DL_BatchEndPointTrend` | v1.0.0 | 16#06_0_8A |
| `FB_DL_DryerExhaustHumidityCtl` | v1.0.0 | 16#06_0_8B |

> R34 增量行：本库 1.13.0 → **131**（registry 实测口径）；机检新增件全 PASS；码位全窗口独占无冲突（主控实测 06_0_80~/03_2_00~/04_0_A0~/02_3_80）。

## R39（2026-11-19）— +7（HjtPvdSeq / ElectrolyteFillCtrl / CartonDenestPush / RadiatorZoneValve / TankLevelStrapping / WaferBreakDetect / RoomCo2DemandVent）；返修 ModuleLamVacuumSeq → v1.0.2

- 本轮增量已入册（registry v2.31.0），机检全 PASS；详见 CHANGELOG v2.31.0。

## v1.17.0 — 2026-11-19（R41 · 20 新件批次 4）
- 新增 3 件：FB_DL_ShrinkTunnelCtrl（热收缩炉温区-网速联动三段工艺窗）/ FB_DL_VavDischargeAirReset（末端阀位加权平均送风重置）/ FB_DL_ConveyorDirMismatch（停机方向失配独立诊断窗，终审立项增强）；组件总数 158 → 161。
- 码位：段 0005 推进——故障 16#0005_0367~036F、信息 16#0005_048F~0497。
- 终审挂账：FB_DL_ConveyorDirMismatch 诊断 TON 沿门控结构性永不到时（严重，R42 P0 返修）。

## v1.17.0 — 2026-11-19（R42：+15 新件 + 3 件 v1.0.1 返修）

### Added（15 新件，批次 1~4）
批次 1：FB_DL_OcvProbeDock / FB_DL_FramingPressSeq / FB_DL_BinderFeederSeq / FB_DL_SafetyDoorAuditBank
批次 2：FB_DL_GlassFeederAccum / FB_DL_WaferCountPreset / FB_DL_SeasonMonthSched / FB_DL_HydronicMeterAudit / FB_DL_PipeScannerRoute
批次 3：FB_DL_RecipeSearchFifo / FB_DL_PollAuditBank / FB_DL_CassetteMapVerify / FB_DL_PalletGripperSafe / FB_DL_ElTestStation
批次 4：FB_DL_HeatExchangerFoulingTrend

### Fixed（3 件 v1.0.1，对外引脚契约不变）
- FB_DL_ConveyorDirMismatch：R41 终审挂账 P0 当轮修（沿直连 TON.IN 致 036D/036E 检出不可达）。
- FB_DL_ElTestStation：R42 终审当场修——新增段 4A 故障锁存相位迁移闸：0397/0398/0399 锁存后 _eState 强制迁 eFault，断 tonCamTo 跨锁存期 IN 保持（否则复位清锁后下一拍立即重锁，解除式不可达），并冻结 eTrig/eMap 相内归档副作用。
- FB_DL_HydronicMeterAudit：R42 终审当场修——补声明内部相位变量 _eState（首版漏声明，编译阻断，机检盲区）+ 段 4A 迁移闸：0385/0386/0387 锁存后强制入 eFault，冻结 eRun 相内累计递增（否则饱和锁存后 fEnergyKwh 持续越限增长）。

### 已知挂账（返修池）
- FB_DL_CassetteMapVerify：轻——04BA 失配检出沿与 04BB 首错定位沿同拍互斥，04BA 在出口不可观测（头注释已声明后到优先）；0392 组态锁存期间相位不迁 eFault（eIdle 相无副作用，无冻结需求）。R43 起排程。

### 计数
- 组件 161→176；码位段 0005 窗口 0385~0399 / 04AD~04C1 零冲突（全文口径实扫）。

### v1.18.0 — 2026-11-19（R43）
- 新增组件 9 件；码位窗口 039D~03A5 / 04C5~04CD 零冲突。
- 由 v1.17.0 升位，向后兼容（纯新增，无接口破坏）。

## v1.19.0 — 2026-11-19（R44 · 零检索轮）
- 新增 7 件：FB_DL_ChillerStagingSeq（冷机加卸载顺控，与 ChillerTempStab/CondReset 分工：稳 vs 控 vs 编组）/ FB_DL_DesiccantRegenSeq（干燥剂再生四相顺控）/ FB_DL_VacuumBakeOutSeq（真空烘烤三段 + 压升率判漏）/ FB_DL_CellAgingRestSeq（电芯老化静置 + 抽测窗口判级）/ FB_DL_LaserDescumStep（激光去渣工步）/ FB_DL_AirLeakDecayTest（气压降法泄漏测试，与 EscHeLeakCheck 分工：压降 vs 氦检）/ FB_DL_CoolingTowerReset（冷塔出水温度重置，DewpointReset 同族不同对象）；组件总数 185 → 192。
- 码位：段 0005 续编，派单建议窗口 06_0_BD~C3，registry 全文口径实测零冲突。
- 向后兼容（纯新增，无接口破坏）。

## v1.20.0 — 2026-11-19（R45）

- R45：+3 新件（SlurryMixingSeq / FrameSealDispenseSeq / BoilerBlowdownSeq）+ 2 返修 v1.0.1（CalenderRollPress / IvCurveScan，引脚契约零变更）｜码位 16#0005_03A6~03A8 / 04CE~04D0


## v1.21.0 — 2026-11-19（R46）

- R46：+4 新件（TabWeldingMonitor / CellSortingBin / ModulePottingVac / PackHousingTighten，ROADMAP B 类）｜零码位硬编码：BOOL+ENUM 出口，码位待主控统一派号｜机检 4/4 PASS
- 向后兼容（纯新增，无接口破坏）。

## v1.21.1 — 2026-11-19（R47）

- R47：+12 新件（TrayerNestingCtrl / OcvTempNormalize / ElectrolyteFifoTrace / StringFifoRetry / TempCompClassify / RfidTrayRoute / FoupRfidCheck / ChuckVacuumSeq / ChamberPumpDownSeq / EfEmoInterlock / LaminatorZoneSync / R2rRunLogAudit）+ 1 返修（TabWeldingMonitor v1.0.1）｜零码位硬编码，码位待主控统一派号｜机检 13/13 PASS
- 向后兼容（纯新增，无接口破坏）。
---

## v1.17.0 — 2026-11-20（R48）

- 新增组件 3 件：FB_DL_AutoclaveSterilSeq / FB_DL_TunnelPasteurizerSeq / FB_DL_PumpPrimingSeq
- 子库组件总数：**214**（registry 实测口径）
- 机检：本轮 21/21 PASS（含 FB_DL_ModulePottingVac v1.0.1 轻返修）

## v1.20.0 — 2026-11-20（R49）

- 新增组件 1 件：FB_DL_RoomTempClassify
- 子库组件总数：**215**（registry 实测口径）
- 机检：本轮 20/20 PASS（增量仅扫本轮新增件）

## v1.21 — 2026-11-20（R52）
- 变更：+2（MakeupWaterDosing 补水定量加药 / DieBinCounter 晶粒分箱计数切箱）
- 子库计数：**234 件**（全库 945 / v2.44.0）
- 机检：本子库本轮新增/返修件全部 PASS（audit_r52.py，22/22 全绿）

## v1.22 — 2026-11-20（R53）

- +4：FB_DL_CaseShiftTally / FB_DL_FilterWeekWindow / FB_DL_LabelWeekCode / FB_DL_BathTempHoldCtrl
- 机检：本轮 20/20 PASS（含 4 件 v1.0.1 返修）；JSONL 同步 962 条。

## R54 追加（2026-11-20，子库 v1.23）
- 新增：FB_DL_NightFlushPurge / FB_DL_RecipeSwitchHandover / FB_DL_EnthalpyPrioritySwitch / FB_DL_TankAgitationSeq
- 子库存量：242 件

## R55 追加（2026-11-20，子库 v1.24）
- 新增：FB_DL_EnergyMonthPreset / FB_DL_ChamberTempUnitBank / FB_DL_RollPressBitWord / FB_DL_FormatMonthAudit / FB_DL_TrayMonthRotate / FB_DL_ShiftMonthReport / FB_DL_FormationWeekPlan / FB_DL_StringIrrNormalize / FB_DL_BatchWeekReport / FB_DL_StringElImageMap / FB_DL_AmcMonitorStat / FB_DL_BeltHeatRecovery / FB_DL_ElectrolyteDosingTrend / FB_DL_EvaDosingTare / FB_DL_ChemDosingGrav / FB_DL_CoinCellAssembler / FB_DL_PackMlUnitMode / FB_DL_BacdHvacPoll
- 子库存量：260 件

## v1.25 — 2026-11-21（R56 追加）
- 新增 3 件（HotRunnerZone / SlurrySieve / AirShowerInterlock）。
- 子库累计 263 件。
## v1.27 — 2026-11-21（R57 追加）
- 新增 2 件：FB_DL_PassboxInterlockSeq / FB_DL_NightPurgeSeq（传递窗三段互锁 / 夜间免费制冷吹扫）
- 子库累计 265 件。

## v1.28 — 2026-11-21（R58 追加）
- 3 件（GowningRoomSeq / MaterialHoldTimeEnforce / FirstArticleLock）+ PassboxInterlockSeq / NightPurgeSeq v1.0.1 返修。
- 子库累计 268 件。

## v1.30 — 2026-11-21（R60 追加）
- 新增 1 件：FB_DL_ShiftHandoverCheck（班次交接检查）
- 子库累计 272 件。

## v1.31 — 2026-11-21（R61 追加）
- 新增 1 件：LineClearanceVerify
- 子库累计 273 件。

## v1.32 — 2026-11-21（R62 追加）
- 无新件（R62 按 R267 族避让，Process 配额让给 Base / MathData 族补口）。
- 返修 1 件：`FB_DL_LineClearanceVerify` v1.0.0 → **v1.0.1**（码 3036 口径订正为逐拍提示、不锁存、不置 `bError`；链末位不覆盖故障码）。
- 子库累计 273 件（维持）。

## v1.33 — 2026-11-21（R64 追加）

- 新增 2 件：`FB_DL_ReworkLotGate`（v1.0.0，ISA-88 批次相语义 + PackML 纪律次源）：返工登记期拦截放行，越权放行锁存 3036、放行计数饱和信息级 3037；`FB_DL_UnscramblerSeq`（v1.0.0，PackML 相语义聚合四相）：进瓶整理 → 乱瓶分拣 → 完成，卡瓶窗锁存 3038、料满停进挂相不挂故障。
- 主库合计 275 件（+2）。本轮终审两件均判「轻」（ReworkLotGate：eReleased 相不随复检失效回迁；UnscramblerSeq：`_bHold` 跨相粘滞一拍），挂 R65。

## v1.34 — 2026-11-22（R65 追加）

- 新增 `FC_DL_TankVolumeHoriCyl`（卧式圆柱罐弓形解析体积，与 TankLevelStrapping 查表法互引）。
- 点修：`FB_DL_ReworkLotGate` v1.0.1（eReleased 单拍回迁）/ `FB_DL_UnscramblerSeq` v1.0.1（段 0a 统一清 _bHold）。
- 子库累计 276 件。

## v1.35 — 2026-11-22（R66 追加）

- 新增 2 件：`FB_DL_LotMergeGate`（批次合并放行闸，双门槛 + 召回重入）/ `FB_DL_TaktPaceMonitor`（目标节拍偏差监视，EWMA + 欠产台账，ISO 22400-2）。
- 终审就地修：`FB_DL_TaktPaceMonitor` v1.0.0 → **v1.0.1**（窗面/计时面静默降级并入码 01）；LotMergeGate 2 轻挂账 R67。
- 子库累计 278 件。

## v1.35 — 2026-11-22（R67 追加）

- 点修 2 件：`FB_DL_LotMergeGate` → v1.0.1（删除 eFault 死迁出式，故障相出口只留复位沿）｜`FB_DL_TaktPaceMonitor` → v1.0.2（fExpectR 闸界 DINT 域对齐 2147483647）。R66 挂账清零。
- 子库组件数不变（278 件）。

## v1.36 — 2026-11-22（R68 追加）

- 新增 4 件：`FB_DL_StretchWrapSeq`（缠绕膜七态最小子集，圈数配方 + 圈边界暂停，PackML 全集归属主）｜`FB_DL_OutdoorTempReset`（OAT 重置供水设定 + 斜坡 + 最小水温联锁）｜`FB_DL_KilnPressureCtrl`（窑压定值闭环 + 抽力限幅 + 窑门前馈）｜`FB_DL_TruckScaleSeq`（过磅七态 + 稳定窗 + 皮毛配对台账）。
- 终审就地修：`FB_DL_TruckScaleSeq` v1.0.1（组态锁存解除可达化 + 超时重测清窗单拍化）｜`FB_DL_StretchWrapSeq` v1.0.1（总圈计数上限 255→510，消除合法配方死锁）。
- 子库累计 282 件。

## v1.37 — 2026-11-22（R69 追加）
- 新增 1 件：`FB_DL_CuringOvenSeq`（固化炉四段顺控）。
- 点修：`FB_DL_StretchWrapSeq` v1.0.1 → **v1.0.2**（eCut 切膜失败出口 03B3 + 压膜释放口径固化，R68 挂账）｜`FB_DL_TruckScaleSeq` v1.0.1 → **v1.0.2**（NaN 信号与组态闸拆拍防脏值）。

## v1.30 — 2026-11-22（R70 追加）
- 新增：FB_DL_BatchDoseSeq（五相定量给料）｜FB_DL_PumpAlternationLead（泵轮换主备）。
- 子库累计 285 件。

## v1.31 — 2026-11-23（R72 追加）

- `FB_DL_RejectBlowCtrl` / `FB_DL_SipLineSterilSeq` 两件入册（气吹执行时序对账；SIP 保温跌破从零重计）。

## v1.32 — 2026-11-23（R73）

- 新增/变更：FB_DL_TankFarmTransferSeq / FB_DL_ConveyorAccumGateSeq / FB_DL_HandAutoModeGateBank / FB_DL_OperatorAckBank + FB_DL_NightPurgeCtrl 点修
- L2 编译闸：PASS（RuSTy 1.0.8 串行）

## R76 · v2.68.0 · 2026-11-23
- 新增 1 件（冷机门吹扫联锁），本库累计 **299** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1），审校 12 项扫查 + 三道去重通过。

## R77 · v2.69.0 · 2026-11-23
- 新增 1 件（模具分区冷却时序），本库累计 **300** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。

## R79 · v2.71.0 · 2026-11-24
- 新增 冷却塔风机分级/螺旋给料计量/压机力曲线/曝气循环 4 件，本库累计 **306** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。

### R80（2026-11-24）
- 新增 18 件（称重配料 8 + 水处理 7 + 复杂 3），子库累计 324 件。
