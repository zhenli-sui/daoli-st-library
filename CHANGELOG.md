# CHANGELOG — 道莅工业自动化标准代码库

遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/) 与 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

> 版本号规则：**MAJOR** 破坏性接口变更 ｜ **MINOR** 新增组件或新增可选输入 ｜ **PATCH** 实现与文档修正。

## v2.56.0 — 2026-11-21（R64 十件入册 + 二件点修 + 终审就地修一件）

### Added（10 件：DL_Base 1 / DL_MathData 6 / DL_Device 1 / DL_Process 2）
- DL_Base 1 件：`FC_DL_TriStateCompare`（三态比较 + `fEps` 容差 + NaN 前置闸，T2-1 Comparator 深化）
- DL_MathData 6 件：`FC_DL_ArrayFindValue` / `FC_DL_ArraySliceCopy`（Data Handling 深化 +2）｜`FC_DL_IntervalGapCalc`（Comparator 深化 +1）｜`FC_DL_GcdUdintCalc`（欧几里得 + WHILE 守卫）｜`FC_DL_RunningSumCalc`（滑动和）｜`FC_DL_FlowUnitConvert`（m³/h ↔ L/min ↔ NL/min ↔ SCFM，T0-4 三件齐）
- DL_Device 1 件：`FB_DL_DualValveBlockSet`（双阀同令同闭 + 不一致窗，锁存 072E / 组态 072D）
- DL_Process 2 件：`FB_DL_ReworkLotGate`（返工拦截闸，锁存 3036 / 信息级 3037）｜`FB_DL_UnscramblerSeq`（理瓶四相顺控，锁存 3038 / 组态 3039）

### Changed（2 件点修，R63 挂账 4 处全清）
- `FB_DL_VfdPrechargeSeq` v1.0.1：宽限计时 `tonSlopeLow` IN 串 `NOT _bMeasBad`（判据挂起 = 计时挂起，R307）；`NOT bKmCmd` 撤令判据上移为 eWaitFb / eRamp 分支首个 ELSIF（R312）。
- `FB_DL_AdaptiveLmsFilter` v1.0.1：抽头数钳位上移至段 4 变更沿检测之前（消除晚一拍混算）；权重写回前 `ABS(_fCorr * _afX[_i])` 预检（374C 一次性报告，374B 收窄为持续发散监视）。

### Fixed
- `FC_DL_FlowUnitConvert` v1.0.0 → v1.0.1：`DL_FUC_LMIN` 因子方向倒置（16.666667 = [L/min 每 m³/h] 的倒数，与声明单位 [（m³/h）/（L/min）] 相反），L/min 参与换算错 277.78 倍。改为 1 L/min = 0.06 m³/h，与 Press / Temp 姊妹件口径统一；V1~V4 向量修复后自证成立。R64 终审 S1，按 R317「安全侧三条」第①条就地修。

### 统计
- 总库 1,125 → **1,135**（counts 135/267/134/204/120/275），SFT 1,142 → **1,154**，机检 12/12 PASS（含就地修增量机检）。
- 五抽：严重 1 / 中 1 / 轻 2 / PASS 1；就地修 1 件（S1），其余 3 处挂 R65。新增可判定规则 5 条（R314~R318），本轮不固化。

## v2.55.0 — 2026-11-21（R63 十三件入册 + R62 挂账七处返修全清 + 族①②扩面深化）

### Added（13 件：DL_MathData 4 / DL_Algo 5 / DL_Device 4）
- DL_MathData 4 件（T0-5 BCD 位宽补口 + 统计族）：`FC_DL_BcdToDint`（8 位 BCD→DINT，逐码元合法性闸，域证明无溢出分支）、`FC_DL_DintToBcd`（DINT→8 位 BCD，负值/越域双闸一码区分）、`FC_DL_TrimmedMeanCalc`（双端截尾均值，NaN 剔除 + 委托排序双承接 R295）、`FC_DL_PearsonCorrCalc`（双通道皮尔逊相关，配对剔除 + 常量退化闸 + |r|>1 钳回信息级）
- DL_Algo 5 件（族① 二阶/结构滤波族深化）：`FB_DL_EwmaFilter`（EWMA 统计平滑口径，α 直接入参，与连续时间常数口径的 LowPassFilter 分工写死）、`FC_DL_BiquadCoeff`（RBJ 类公开公式低通/高通/带通/陷波四型系数生成，Jury 一致性声明）、`FB_DL_OutlierFilter`（MAD 野点剔除 + 保持 + 真阶跃重基线防死锁）、`FB_DL_BiquadCascade`（≤4 节 Direct Form II 级联，逐节 Jury 稳定闸 + 死节豁免）、`FB_DL_AdaptiveLmsFilter`（LMS 在线权重更新，输入坏冻结防污染 + 发散监视）
- DL_Device 4 件（族② 直流母线/ADC/测点监视族深化）：`FB_DL_AdcNoiseFloorWatch`（静态期底噪标准差双限值监视）、`FB_DL_VfdOutputImbalance`（变频输出三相不平衡/断相双判据）、`FB_DL_VfdCapAgingEst`（纹波率基线比长期趋势，组态闸结构早退出厂即正确）、`FB_DL_VfdPrechargeSeq`（预充反馈窗/斜率/总时限三闸状态机，锁存解除式 `bResetCmd` 可达自证）

### Fixed（5 件，R62 五抽挂账 7 处全清）
- `FB_DL_VfdDcBusRipple` v1.0.0→**v1.0.1**（DL_Device）：段 3A 组态非法结构早退（三件套 + 码 0710 + RETURN），`fUdNom=0` 除法直穿路径封死（R62-D1 严重）。
- `FB_DL_BiquadFilter` v1.0.0→**v1.0.1**（DL_Algo）：稳定判据换 Jury 三条件 + V2b/V2c 双向验收向量 + 373A 不再复用 `bCfgBad`（R62-D2 严重 / D5 轻）。
- `FB_DL_IonFanInterlock` v1.0.0→**v1.0.1**（DL_Device）：出口三报警位与 `bError` 全部串 `bEnable`，失能相不外显假故障；顺带消除段 0 用后段组态位的段序瑕疵（R62-D3 中 / D6 轻）。
- `FB_DL_RailPowerSequence` v1.0.2→**v1.0.3**（DL_Base）：eRampUp 推进判据改「沿 OR 电平」双路，反馈预闭合轨电平直过，消除静默挂死（R62-D4 中）。
- `FC_DL_PercentileRank` v1.0.0→**v1.0.1**（DL_MathData）：`nNonFinite` 口径定稿「不外显，诊断请用 `FC_DL_SignalStatistics`」（R62-D7 轻）。

### Notes
- 版本偏差留痕（R305/R311 口径）：派单假设 R1/R2/R3/R5 → v1.0.2，磁盘实测基线 v1.0.0，按实测递增至 v1.0.1（registry 实测一致）；子库 VERSION 节号以文件实测最大节 +1 追加（MathData v1.35 / Algo v1.30 / Device v1.26 / Base v1.34），任务书假设数字作废。
- 终审（`_Staging_Raw/2026-11-21/REVIEW_R63.md`）：**严重 0 / 中 1 / 轻 3**，挂账 4 处 × 2 件 × R63，本轮零改码（R333）全部挂 R64 首位；挂账分散于 3 族（计时挂起门控 / 段序 / 防御溢出），按 R309 判分散型点修，R64 配额 13→10。族②「组态闸 RETURN 早退」与族①「Jury/域闸判据充分性」扩面目标达成，R62-D1/D2 缺陷家族在新件出厂层面关闭。
- R62 已知未关闭项状态更新：`FB_DL_BiquadFilter` / `FB_DL_VfdDcBusRipple` / `FB_DL_IonFanInterlock` 本版已关闭，**恢复可用于安全相关回路**（新挂账 4 处均为中/轻级，不涉及安全断言证伪）。

## v2.54.0 — 2026-11-21（R62 十一件入册 + R61 挂账五项返修 + T0 族内深化）

### Added（11 件：DL_Base 4 / DL_MathData 4 / DL_Algo 1 / DL_Device 2）
- DL_Base 4 件（T0 算术/位串族补口）：`FC_DL_SaturateMul`（LINT 宽域饱和乘，溢出前置判定 + 双标志可分）、`FC_DL_SaturateDiv`（饱和除，除零三段码 + 向零截断口径写死）、`FC_DL_ShiftArithEx`（算术右移，32 项常量掩码表避 `SHL(x,32)`）、`FC_DL_SignExtendEx`（任意窄位宽符号/零扩展，宽域早退不钳）
- DL_MathData 4 件（T0-5 转换/统计补口）：`FC_DL_RealToIntSat`（LREAL→INT 16 位饱和，与 Dint/Byte 两件构成位宽三分）、`FC_DL_SignedToUdintSat`（负值钳零 + 信息级提示，`IntToUdintSat` 并入口径写死）、`FC_DL_DtToTodWrap`（DT→当日秒/TOD，日模 86400 + 基准无效闸）、`FC_DL_PercentileRank`（值→分位定位，三口径弱/强/中位排名，分位族逆运算）
- DL_Algo 1 件：`FB_DL_BiquadFilter`（通用二阶 IIR 直接 I 型，系数下发 + 稳定域闸 + 变更沿清状态 + 抗 windup 回写）
- DL_Device 2 件：`FB_DL_VfdDcBusRipple`（母线均值/峰峰纹波率/欠压/过压，`_nFill` 除子 + 变窗长全窗清）、`FB_DL_IonFanInterlock`（离子风机三判据合取许可位，发放可延迟 / 撤除零延时 + NE107 分级）

### Fixed（5 件，R61 五抽挂账全清）
- `FB_DL_RailPowerSequence` v1.0.1→**v1.0.2**（DL_Base）：D1 空轨断电早退（eIdle/eStable 两处同口径，不迁移/不置 bDone/仅信息码 0655）+ D2 单轨超时改由逐拍 `_bRailPending` 门控。
- `FB_DL_TurretToolSelect` v1.0.0→**v1.0.1**（DL_Motion）：段 4b 统一故障迁入闸，补 eFault 死相位（R291 解除式可达自证：`bReset` 恒可达）。
- `FB_DL_SensorPairPlausibility` v1.0.0→**v1.0.1**（DL_Device）：窗长变更沿全窗清零（含环元素逐项清）+ 均值除子改 `_nFill`（首填偏小防漏报）。
- `FC_DL_WeightedPercentile` v1.0.0→**v1.0.1**（DL_MathData）：委托返回值与 `bValid` 分承后合取，禁同一实参双写（可移植性暗雷）。
- `FB_DL_LineClearanceVerify` v1.0.0→**v1.0.1**（DL_Process）：码 3036 口径订正为「窗内残留超 `nResidueMax` 逐拍提示、不锁存、不置 `bError`」，链末位不覆盖故障码。

### Notes
- 版本偏差留痕（R305）：RailPowerSequence / TurretToolSelect / SensorPairPlausibility 三件实测入库版本为 v1.0.0（派单假设 R61 已发 v1.0.1），按实测递增一次，禁跳号。
- 终审（`_Staging_Raw/2026-11-21/REVIEW_R62.md`）：**严重 2 / 中 2 / 轻 3**，本轮零改码（R333）全部挂 R63；触发 R193 扩面，R63 配额 16→13。已知未关闭项：`FB_DL_VfdDcBusRipple` 组态非法未结构早退（除零）、`FB_DL_BiquadFilter` 稳定域判据不充分（Jury 下边界缺失）。**本版两件在关闭前不建议用于安全相关回路。**

## v2.53.0 — 2026-11-21（R61 十六件入册 + R60 六项挂账返修）

### Added
- DL_Base 4 件：FC_DL_ReverseBitsLword / FC_DL_BitScanLword / FB_DL_LongPressButton / FB_DL_RailPowerSequence
- DL_MathData 5 件：FC_DL_Hypot3D / FC_DL_TrapezoidArea / FC_DL_SortIndexLReal / FC_DL_WeightedPercentile / FC_DL_MeanAbsDevCalc
- DL_Algo 1 件：FB_DL_PidParamGuard（含与 PidParamDriftAudit 在线闸/离线审计分工声明 R216）
- DL_Device 3 件：FB_DL_PhaseLossGuard / FB_DL_SensorPairPlausibility / FB_DL_AirDryerDiag
- DL_Motion 2 件：FB_DL_AxisLimitSwitchBank / FB_DL_TurretToolSelect
- DL_Process 1 件：FB_DL_LineClearanceVerify

### Fixed
- FB_DL_AxisCmdArbiter v1.0.1：非有限降级双通道同步落 eNone（D1）+ 故障级码 _bFault 锁存与复位（D2）
- FC_DL_InterpolateTable3D v1.0.1：信息级码不再置 bError（D4）+ 三轴向量逐元素有限性闸与 0629 早退（D3）+ 新增 0630 结果非有限码（D9）+ 段 6 缩进对齐（D8）
- FC_DL_Affine2DChain v1.0.1：nUsed=1 单级链奇异判补齐（D5）+ 信息级码口径统一（D6）
- FB_DL_ShiftHandoverCheck v1.0.1：_nPendingLock 仅 eIdle 迁入沿锁定，声明与实现对齐（D7）
- FB_DL_TwoStepConfirm v1.0.2：段 4 判据补 AND _bArmed 双保险

## v2.52.0 — 2026-11-21（R60 十二件入册 + P0 返修 + **FB-51 固化批次**）

### Added（12 件，DL_Base 3 / DL_MathData 5 / DL_Algo 1 / DL_Device 1 / DL_Motion 1 / DL_Process 1）
- DL_Base：`FB_DL_RolloverCounterUdint`（UDINT 回绕安全累计）、`FB_DL_ReqAckHandshake`（请求-应答握手原子）、`FC_DL_BitFieldExtractLword`（64 位位域提取）
- DL_MathData：`FC_DL_SearchMinMaxDint` / `FC_DL_SearchMinMaxUdint`（极值检索 DINT/UDINT 对称对）、`FC_DL_Affine2DChain`（仿射链复合）、`FC_DL_ThdCalc`（THD）、`FC_DL_InterpolateTable3D`（三线性插值）
- DL_Algo：`FB_DL_InputShaperZv`（ZV 输入整形）｜ DL_Device：`FB_DL_ValveTerminalDiag`（阀岛诊断）
- DL_Motion：`FB_DL_AxisCmdArbiter`（命令源仲裁）｜ DL_Process：`FB_DL_ShiftHandoverCheck`（班次交接）

### Fixed
- `FB_DL_TwoStepConfirm` v1.0.1（DL_Base）：修 **R275 同拍竞态** —— 段序改为「段 3 先消化本拍二按沿、段 4 才做超时迁移」，窗口到期拍恰有确认沿时按确认成立，不再吞掉合法二按；对外引脚与语义未变。

### Changed（内部规范，不涉接口）
- **固化批次 FB-51**：R252~R280 共 16 条可判定规则并入 `plc-st-templates/01-coding-standard.md`（+48 行，+14.33%）与 `daoli-st-standard/coding-standard.md`（+34 行，+11.45%）；人格文件微调 10.00% / 4.20%。R271 三族开闭词配对、R272 闸参数覆盖、R275 同拍竞态三项同步进机检闸。

## v2.51.0 — 2026-11-21（R59 二十件入册 + 三件 P0 返修）

### Added（20 件，DL_Base 3 / DL_MathData 8 / DL_Algo 3 / DL_Device 3 / DL_Motion 3 / DL_Process 3）
- DL_Base：`FB_DL_TimerFailSafe`（看门狗失效安全）、`FB_DL_TwoStepConfirm`（两步确认）、`FB_DL_MultiSegmentTimer`（多段时序）
- DL_MathData：`FC_DL_DmsAngleConvert`、`FC_DL_QuadraticSolve`、`FC_DL_DtlStringConv`、`FC_DL_AsciiFrameParse`、`FB_DL_DataResampler`、`FC_DL_FftRadix2`（基 2 原地 FFT）、`FC_DL_ConductivityTempComp`
- DL_Algo：`FB_DL_MracAdaptiveCtrl`（模型参考自适应）、`FB_DL_CraneAntiSway`（输入整形防摇）
- DL_Device：`FB_DL_SprayNozzleBank`、`FB_DL_DustCollectorPulse`
- DL_Motion：`FB_DL_PathCornerBlend`、`FB_DL_SpindleWarmupSeq`、`FB_DL_ToolLifeBudget`
- DL_Process：`FB_DL_LotoSequence`（上锁挂牌五步链）、`FB_DL_VisionResultGate`、`FB_DL_LotGenealogyLink`

### Fixed（v1.0.1）
- `FC_DL_PmvComfortIndex`：段 6 补 `fPpdPct` 非有限复检三件套（R258 口径，防负底数 EXPT NaN 穿透）
- `FB_DL_SoftStarterDrive`：复位沿前置故障相位门；删 3 处自赋值死语句（R261）
- `FB_DL_PeriodicDisturbComp`：头注释补环块双清同步声明；`DL_PDC_SKIPMAX` → `DL_PDC_CNTMAX` 名实对齐
- `FB_DL_LotGenealogyLink`：`END_FOR` → `END_WHILE` 循环配对修复（收口机检捕获，编译阻断，行为零变更）

### Meta
- registry 1053 → **1073**（counts 123/243/126/193/117/271，sum 断言通过）；SFT 语料 1054 → **1074**（badjson=0）
- 机检增量 23/23 PASS fail=0；ROADMAP 勾 0 条（20 名零在册），待办维持 33
- 专家进化 +9 条（PLC R271~R275 / 总监 R276~R280）

## v2.49.0 — 2026-11-21（R57 二十件入册 + 四件 P0 返修）

### Added（20 新件，4 批 × 5，零检索轮）
- DL_Base（+5）：FB_DL_TpRetrigger / FB_DL_EdgeMasterSlaveSync / FB_DL_EncoderQuadCount / FB_DL_SignalStagnationWatch / FB_DL_SensorDropoutHold
- DL_MathData（+10）：FC_DL_AsinSafe / FC_DL_AcosSafe / FC_DL_LogSafe / FC_DL_ExpSat / FC_DL_PowIntSat / FC_DL_SignumCalc / FC_DL_RmsCalc / FC_DL_ParityCalc / FC_DL_PeakToPeakCalc / FC_DL_InterpStepNearest
- DL_Device（+3）：FB_DL_EsdGroundMonitor / FB_DL_IonizerAirflowInterlock / FB_DL_ProofTestSeq
- DL_Process（+2）：FB_DL_PassboxInterlockSeq / FB_DL_NightPurgeSeq

### Fixed（4 件 v1.0.1 返修，源自 R56 五抽终审）
- FB_DL_LossInWeightFeeder（严重，安全侧）：eIdle 相 / eDose 失能迁移 / 故障锁存三路径 fRateOut 强制归零，消除失能后螺旋继续给料。
- FB_DL_TwoDofPid（中）：手动相入口补 fManOut 有限性闸（x<>x + x-x<>x-x），无效拍冻结早退，防 NaN 直通与积分永久污染。
- FB_DL_AxisAccelFeedforward（中）：有效拍内补 eInputBad 信息级成因恢复撤销，对齐 TwoDofPid 段 10 范式。
- FB_DL_HydraulicAccumPreChg（轻）：段 3 域闸补温度上界常量 DL_HAP_TEMP_HI = 150.0 摄氏度，超界判 eSensorBad。

### Changed
- registry v2.48.0 → v2.49.0，总库 1017 → 1037（counts {"DL_Base": 118, "DL_MathData": 233, "DL_Algo": 121, "DL_Device": 188, "DL_Motion": 112, "DL_Process": 265}）；JSONL 1018 → 1038 行（新增 20 行 badjson=0）。
- 机检 24/24 PASS（20 新 + 4 返修复检），零 GVL / 零物理地址 / 零占位符；撞名三查拦 19 项候选（同族 Ex/Sat 变体为主）。
- T0 防御性包装 15 件统一溯源「IEC 61131-3 标准语义的道莅防御性实现」，ASIN/ACOS/LN/EXP 全部委托平台内建，未重实现数学内核。

## v2.47.0 — 2026-11-20（R55 二十件入册）

### Added（20 新件，4 批 × 5，零检索轮）
- DL_MathData（+1）：FC_DL_NewtonRaphson
- DL_Algo（+1）：FB_DL_FopdtStepIdent
- DL_Process（+18）：FB_DL_EnergyMonthPreset / FB_DL_ChamberTempUnitBank / FB_DL_RollPressBitWord / FB_DL_FormatMonthAudit / FB_DL_TrayMonthRotate / FB_DL_ShiftMonthReport / FB_DL_FormationWeekPlan / FB_DL_StringIrrNormalize / FB_DL_BatchWeekReport / FB_DL_StringElImageMap / FB_DL_AmcMonitorStat / FB_DL_BeltHeatRecovery / FB_DL_ElectrolyteDosingTrend / FB_DL_EvaDosingTare / FB_DL_ChemDosingGrav / FB_DL_CoinCellAssembler / FB_DL_PackMlUnitMode / FB_DL_BacdHvacPoll

### Changed
- registry v2.46.0 → v2.47.0，总库 977 → 997；JSONL 978 → 998 行（新增 20 行全达标）。
- 机检 20/20 PASS，零 GVL / 零物理地址 / 零占位符；R214 撞名三查拦截 5 项（3 ROADMAP 漏勾脏项补勾 + 2 同义变体拒收）。

## v2.46.0 — 2026-11-20（R54 十六件入册 + 三件 P0 返修）

### Added（16 新件，4 批 × 4，零检索轮）
- DL_Base（+3）：FB_DL_BitArrayMultiSegMove / FB_DL_PrbsSignal / FB_DL_SweepFreqGen
- DL_MathData（+2）：FC_DL_ChecksumLwordSum / FB_DL_HistogramBinTally
- DL_Algo（+2）：FB_DL_PidRelayAutoTune / FB_DL_FirstOrderIdent
- DL_Device（+3）：FB_DL_HealthStatusArbiter / FB_DL_PnDiagAlarmDecode / FB_DL_AirCompressorLoadUnload
- DL_Motion（+2）：FB_DL_CamTableLiveTrim / FB_DL_AxisTorqueRippleWatch
- DL_Process（+4）：FB_DL_NightFlushPurge / FB_DL_RecipeSwitchHandover / FB_DL_EnthalpyPrioritySwitch / FB_DL_TankAgitationSeq

### Fixed（3 件 P0 返修，均 v1.0.1）
- FB_DL_ControlOutputSlewWatch：`_nHead`/`_nFill` 声明初值补齐（R52 五抽严重项），运行时自愈保留作双保险，行为零变更。
- FB_DL_SensorDriftBaseline：基线更新与偏差出口前置有限性闸，新增 bSensorBad 锁存出口。
- FB_DL_AxisBacklashStepComp：偏移与位置出口移入有限分支，非有限拍走快照保持 + bInvalid 单拍指示。

### Changed
- registry v2.45.0 → v2.46.0，总库 961 → 977；JSONL 962 → 978 行（新增 16 行全达标 + 3 件返修重注入）。
- 机检 19/19 PASS（16 新件 + 3 返修），零 GVL / 零物理地址 / 零占位符。

## v2.45.0 — 2026-11-20（R53 十六件入册 + 四件 P0 返修 + 三向差额回写）

### Added（16 新件，4 批 × 4，零检索轮）
- DL_Device（+3）：FB_DL_ValveCycleLifeCounter / FB_DL_ConveyorSlipWatch / FB_DL_GreaseLubeTimer
- DL_Algo（+3）：FB_DL_BearingVibTrend / FB_DL_PumpSurgeGuard / FB_DL_SensorDriftBaseline
- DL_MathData（+3）：FC_DL_WetBulbCalc / FC_DL_HaversineDistance / FC_DL_PeriodJitterCalc
- DL_Base（+2）：FB_DL_SignalStuckWatch / FB_DL_PulseTrainDecoder
- DL_Process（+4）：FB_DL_CaseShiftTally / FB_DL_FilterWeekWindow / FB_DL_LabelWeekCode / FB_DL_BathTempHoldCtrl
- DL_Motion（+1）：FB_DL_AxisBacklashStepComp（与 R44 `FB_DL_AxisBacklashComp` 分工隔离：前者换向首段阶梯注入，后者连续补偿曲线）

### Fixed（4 件 P0 返修，均 v1.0.1）
- `FB_DL_AxisHomeRepeatVerify`：判定保持族——bPass/bReject 预清移入 eCollect 结算拍，eDone 相保持电平。
- `FB_DL_PidParamDriftAudit`：有限性闸补 `(x-x)=(x-x)` 差判拦 Inf；bDriftAny 同源 OR 重算；魔法数入 VAR CONSTANT。
- `FB_DL_HeatTraceCircuitMon`：段 0 双定时器串 eMon 相位闸；迁入拍补温升基点快照。
- `FB_DL_BrakeResistorThermal`：温升估算改热阻功率比口径 + 能量额度组态一致性校验 + eIdle 冷却衰减。

### Changed
- ROADMAP 三向差额回写 18 条（registry ∪ JSONL 双向核验在位后勾选），待办 52→34。
- 机检口径：本轮 20/20 PASS，零假阳性；compile_gate_v0 六目录零告警。

---

## v2.42.0 — 2026-11-20（R49 二十件入册 + R50 固化批次 + 终审挂账）

### Added（20 新件，4 批 × 5，零检索轮）
- DL_Base（+4）：FB_DL_HeartbeatGen / FB_DL_PulseSeqVerify / FB_DL_StepTimeRecorder / FB_DL_CycleBarrierGate
- DL_MathData（+2）：FC_DL_QuatRotateVec / FC_DL_GeoMeanCalc
- DL_Algo（+5）：FB_DL_SignalReconstruct / FB_DL_LoopSignGuard / FB_DL_ExtremumSeekCtrl / FB_DL_LoopCoupleDetect / FB_DL_RulEstimator
- DL_Device（+3）：FB_DL_ValveSeatLeakWatch / FB_DL_CylStrokeTimeBank / FB_DL_CaseErectFaultSeq
- DL_Motion（+5）：FB_DL_MoveResumeSeg / FB_DL_VelFfGainIdent / FB_DL_SoftLimitCfgAudit / FB_DL_AxisLubeDistTrig / FB_DL_BrakeWearAccum
- DL_Process（+1）：FB_DL_RoomTempClassify

### Fixed（5 返修升 v1.0.1，引脚契约零变更）
- R48 终审挂账 5 件（LookaheadVelPlanner / AutoclaveSterilSeq / SensorFusion2 / ContourCrossCouple / SaturateSub）按精确修法返修，registry 与 JSONL 原地重注入，三处记账闭合。

### Verified
- 机检 25/25 PASS fail=0（audit_r50.py）；JSONL 886→906（badjson=0，存量 40 行 legacy 短 instruction 为历史遗留单独立轮）；编码自纠 10 处；R50 终审 5 抽：1 严重（FB_DL_RulEstimator 环窗乱序回归）+ 2 中（FB_DL_ExtremumSeekCtrl 相位 2× 因子与累计口径 / FB_DL_MoveResumeSeg 方向翻转）+ 2 PASS，挂账 ≥3 触发 R193 扩面（环形窗+回归统计族 R51 全量排查），无人值守轮不做行为变更。

### 固化
- 固化批次 FB-50（第 10 轮阈值触发，历史首次按轮数自动触发）：PLC 线 FB50-1~FB50-4、总监线 FB50-D1~FB50-D4 追加合并进两本 skills 规范文件；专家进化 +10 条（PLC R336~R340 / 总监 R341~R345）。


## v2.39.0 — 2026-11-19（R47 / 零检索轮 20 新件 + 4 返修）

### Added（20 新件：DL_Process +12 / DL_Device +3 / DL_Base +2 / DL_Motion +2 / DL_MathData +1）
- DL_Process（+12）：FB_DL_TrayerNestingCtrl / FB_DL_OcvTempNormalize / FB_DL_ElectrolyteFifoTrace / FB_DL_StringFifoRetry / FB_DL_TempCompClassify / FB_DL_RfidTrayRoute / FB_DL_FoupRfidCheck / FB_DL_ChuckVacuumSeq / FB_DL_ChamberPumpDownSeq / FB_DL_EfEmoInterlock / FB_DL_LaminatorZoneSync / FB_DL_R2rRunLogAudit
- DL_Device（+3）：FB_DL_TankBlanketPrCtrl / FB_DL_IvBcdExport / FB_DL_CassetteBcdLabel
- DL_Base（+2）：FC_DL_IntFloorDiv（T0 防御包装，与 FC_DL_IntCeilDiv 成对：floor 对 ceil）/ FC_DL_ByteArrayXor（T0 防御包装）
- DL_Motion（+2）：FB_DL_AxisBacklashIdent / FB_DL_AxisCoggingFf
- DL_MathData（+1）：FC_DL_CovarOnline（在线协方差）

### Fixed（4 返修 v1.0.1，引脚契约零变更）
- FB_DL_RlsEstimator / FB_DL_LuenbergerObserver（DL_Algo）/ FB_DL_TabWeldingMonitor（DL_Process）/ FB_DL_AxisFeedbackFailoverSeq（DL_Motion）：按终审双严重模式修复——状态初始化 `_bInit` 首扫执行 / 复位沿清状态域回夹，详见各件头注释返修节；registry 与 JSONL 原地重注入三处记账闭合。

### Verified（机检 + 收口）
- 机检（check_r47.py，R44/R46 固化口径：禁词、剥 // 注释、CASE-ELSE 配对、T0 溯源短语仅对 iec-std-wrapper 类、R228B 排 ':='）24/24 PASS，fail=0。
- registry 825 → 845（v2.38.0 → v2.39.0）；counts：Base 91 / MathData 202 / Algo 91 / Motion 89 / Device 161 / Process 211。
- JSONL 826 → 846 条，badjson=0，新增 20/20 MATCH，4 返修件原地重注入。
- ROADMAP B 类 15 条补勾；CovarOnline / IntFloorDiv / ByteArrayXor / AxisBacklashIdent / AxisCoggingFf 不在册，不补写（B 真缺口 ≥30 不新增待办）。
- 零码位范式延续：本轮 20 新件 16# 码位 0（BOOL+ENUM 出口，码位待主控统一派号）。

### Notes
- 零检索轮（召唤模式=原生连续第 33 轮，T0 余量 0），选题走 ROADMAP 真缺口 + 源矩阵复用行。
- 零码位维持决策落账（R309）：解除条件=事件码总线层立项，此前派号集中收口阶段。

## v2.38.0 — 2026-11-19（R46 / 零检索轮 20 新件）

### Added（20 新件：DL_Motion +5 / DL_Process +4 / DL_Algo +4 / DL_Device +3 / DL_Base +2 / DL_MathData +2）
- DL_Motion（+5）：FB_DL_AxisLoadEncoderLossMonitor / FB_DL_AxisEncoderPulseLostScore / FB_DL_AxisFeedbackFailoverSeq / FB_DL_GantrySkewMonitor / FB_DL_CamFollowerLagMonitor（双反馈族补口：断线监控 / 评分 / 切换序三分属主）
- DL_Base（+2）：FC_DL_IntCeilDiv（T0 防御包装，整数向上取整除）/ FB_DL_WatchdogPulseMon（T1-7 ◐）
- DL_MathData（+2）：FC_DL_StdDevOnline（Welford 单遍）/ FC_DL_MedianAbsDev（MAD 鲁棒离散度）
- DL_Algo（+4）：FB_DL_StribeckFrictionComp / FB_DL_LuenbergerObserver / FB_DL_RlsEstimator / FB_DL_AdaptiveLeadLag
- DL_Device（+3）：FB_DL_LoadCellTareDrift / FB_DL_TcChannelScanDiag / FB_DL_GripperForceVerify
- DL_Process（+4）：FB_DL_TabWeldingMonitor / FB_DL_CellSortingBin / FB_DL_ModulePottingVac / FB_DL_PackHousingTighten（ROADMAP B 类）

### Verified（机检 + 收口）
- 机检（audit_r46.py G1~G6 + F1~F8）20/20 PASS，fail=0；静态语法闸 v0 首跑负样本对照有效。
- 全部 20 件零码位硬编码：错误出口 BOOL+ENUM，头注释注明码位待主控统一派号（下轮专项评估）。
- registry 805 → 825（v2.37.0 → v2.38.0）；counts：Base 89 / MathData 201 / Algo 91 / Motion 87 / Device 158 / Process 199。
- JSONL 806 → 826 条，badjson=0，新增 20/20 MATCH。
- ROADMAP B 类 4 条补勾（TabWeldingMonitor / CellSortingBin / ModulePottingVac / PackHousingTighten）。

### Notes
- 零检索轮（召唤模式=原生，WebSearch 0/3），复用既有 ◐ 行（T1-6/T1-7/T2-1/T2-2/T2-4/T2-6/T2-8）+ ROADMAP B 类自研；T0=0。
- 终审线本轮未启用（如实标注），5 抽语义终审与零码位 20 件派号专项列 R47 P0。

## v2.37.0 — 2026-11-19（R45 / 零检索轮 20 新件 + 2 返修）

### Added（20 新件：DL_Algo +5 / DL_Motion +5 / DL_Base +3 / DL_Device +3 / DL_Process +3 / DL_MathData +1）
- DL_Base（+3）：FB_DL_Vote2oo3 / FB_DL_EdgeOrderCheck / FB_DL_AlarmFloodLimiter
- DL_MathData（+1）：FC_DL_CubicBezierEval（De Casteljau 求值与一阶导，纯函数零状态）
- DL_Algo（+5）：FB_DL_KalmanFilter1D / FB_DL_TensionObserver / FB_DL_StictionCompensator / FB_DL_LoopPerfIndex / FB_DL_ThermalRampPredict
- DL_Motion（+5）：FB_DL_AxisDualFeedbackGuard / FB_DL_AxisSs1StopSeq / FB_DL_AxisTeachOffset / FB_DL_AxisInertiaIdent / FB_DL_AxisRotaryShortPath
- DL_Device（+3）：FB_DL_SafetyRelayFeedback / FB_DL_ContactorWeldDetect / FB_DL_FlowSwitchResponseCheck（故障级新开 07xx 子带 0701~0703）
- DL_Process（+3）：FB_DL_SlurryMixingSeq / FB_DL_FrameSealDispenseSeq / FB_DL_BoilerBlowdownSeq

### Fixed（2 返修，PATCH 引脚契约零变更）
- FB_DL_CalenderRollPress v1.0.0 → v1.0.1：双侧同步判据加相位窗 `_bSyncWin`，消除 eIdle/eRelease 误锁 039F 与 eDone 不可达；5 个组态实数补 NaN 自反判；5 处故障分支补 bError 配对。
- FB_DL_IvCurveScan v1.0.0 → v1.0.1：复位沿按相分域；FF 计算上移段 0 单次求解 `_fFfPu`，删除同一 FC 同参双调用；eEval 改双出口，消除相位无迁出与 eDone 相 FF 恒 0。

### Verified（机检 + 收口）
- 机检 22/22 PASS，fail=0；码位全库实扫（783 件存量）零冲突；本轮交付 5,391 行。
- registry 785 → 805（v2.36.0 → v2.37.0）；counts：Base 87 / MathData 199 / Algo 87 / Motion 82 / Device 155 / Process 195。
- JSONL 786 → 806 条，badjson=0，新增 20/20 MATCH，2 返修件原地重注入 MATCH。

### Notes
- 零检索轮（WebSearch 0/3），全部复用源矩阵既有 ◐ 行，无新开组、无 ◐→✔ 收口。
- 编译验证债连续 42 轮挂账；ROADMAP 三向一致专项（空勾与 registry 差额）转下轮。

## v2.36.0 — 2026-11-19（R44 / 零检索轮 20 新件 + CassetteMapVerify 返修 + 终审 5 抽收尾）

### Added（20 新件：DL_Process +7 / DL_Motion +5 / DL_Device +4 / DL_Algo +3 / DL_MathData +1）
- DL_Process（+7）：FB_DL_ChillerStagingSeq / FB_DL_DesiccantRegenSeq / FB_DL_VacuumBakeOutSeq / FB_DL_CellAgingRestSeq / FB_DL_LaserDescumStep / FB_DL_AirLeakDecayTest / FB_DL_CoolingTowerReset
- DL_Motion（+5）：FB_DL_AxisBacklashComp / FB_DL_AxisTorqueWatch / FB_DL_AxisBrakeTest / FB_DL_AxisFrictionFf / FB_DL_CircInterp2Axis
- DL_Device（+4）：FB_DL_LoadcellTareCtrl / FB_DL_ValvePartialStrokeTest / FB_DL_RotaryUnionWatch / FB_DL_HeaterSsrBank（05xx 副带续编）
- DL_Algo（+3）：FB_DL_GainSchedPid / FB_DL_RelayAutoTune / FB_DL_BumplessHandAuto
- DL_MathData（+1）：FC_DL_DewPointToPpmV（露点→ppmV 换算，复用 VaporPressureSat 属主不重复声明常数）

### Fixed（1 返修）
- FB_DL_CassetteMapVerify → v1.0.1：按 R43 终审挂账条目轻度返修（不动引脚契约），registry/JSONL 原地重注入 MATCH。

### Verified（机检 + 终审）
- 机检 21/21 PASS fail=0（口径：头部∪全文双扫描，14 项判定表先固化后执行）；码位零冲突；JSONL 765→786（badjson=0，21/21 字节 MATCH）。
- 终审 5 抽（R43 顺延线启用）：FB_DL_IvCurveScan PASS（轻挂账 1）/ FB_DL_CalenderRollPress 中挂账（双侧同步判据未按相位门控，R281）/ FB_DL_AxisBrakeDistPredict PASS / FB_DL_BoilerFlueCondenseGuard PASS / FC_DL_TimeToCycleCeil PASS（整数进位点两向量自证通过，R282 正面案例）。挂账 2 < 3，未触发 R193 全量返修。



### Added（20 新件：DL_Process +9 / DL_Algo +5 / DL_Device +3 / DL_Motion +2 / DL_Base +1）
- DL_Process（+9）：FB_DL_StakingPressCtrl / FB_DL_PouchVacuumSeal / FB_DL_CalenderRollPress / FB_DL_QuarterCellCutSeq / FB_DL_CellOcvBinSort / FB_DL_IvCurveScan / FB_DL_ChillerCondReset / FB_DL_SampleLoopPurge / FB_DL_BundleShrinkTemp
- DL_Algo（+5）：FB_DL_DuctLeakRateEst / FB_DL_VavPressureReset / FB_DL_ChwDifferentialPressureReset / FB_DL_SelfDischargeScreen / FB_DL_FanPressureTrim
- DL_Device（+3）：FB_DL_CleanRoomRhTrim / FB_DL_BoilerFlueCondenseGuard / FB_DL_CellFeederVacuum（05xx 副带续编 052B~052D）
- DL_Motion（+2）：FB_DL_AxisBrakeDistPredict / FB_DL_GearInPhaseAlign
- DL_Base（+1）：FC_DL_TimeToCycleCeil（T0 防御性包装，委托内建判定不重实现内核）

### Fixed（质量）
- 全库码位冲突普查闭环：765 件全文实扫，占用码位 149 个，**冲突 0 处**（P1 连挂 4 轮至此清偿）。
- 机检口径修 2 处：① 枚举「漏单冒号」判定原误把 `_eState := E_DL_X.eIdle`（合法限定赋值）判违规；② IF/END_IF 计数原用 `(?<!END_)IF` 会把 `ELSIF` 计入。两处均为脚本自身误报，非代码缺陷（R171 家族第 7、8 次口径坑）。

### Notes
- 品类纠偏：DL_MathData 已占 25.7% 超配，本轮 MathData 0 件，Algo/Motion 合计补薄 7 件。
- 编译验证债仍挂账（连续 39 轮）；code_segment 字段本轮 20 件全部实填写入（历史件回填仍待专项）。

## v2.34.0 — 2026-11-19（R42 / Process+Device 偏科轮 20 新件 + 4 返修 + 终审当场修 2 件）

### Added（20 新件：DL_Process +15 / DL_Device +5）
- DL_Process（+15）：FB_DL_OcvProbeDock / FB_DL_FramingPressSeq / FB_DL_BinderFeederSeq / FB_DL_SafetyDoorAuditBank / FB_DL_GlassFeederAccum / FB_DL_WaferCountPreset / FB_DL_SeasonMonthSched / FB_DL_HydronicMeterAudit / FB_DL_PipeScannerRoute / FB_DL_RecipeSearchFifo / FB_DL_PollAuditBank / FB_DL_CassetteMapVerify / FB_DL_PalletGripperSafe / FB_DL_ElTestStation / FB_DL_HeatExchangerFoulingTrend
- DL_Device（+5）：FB_DL_RobotArmVibrationWatch / FB_DL_RoofUnitDoorSw / FB_DL_FilmSpliceCurtain / FB_DL_DamperBitDiag / FB_DL_BmsPdiGateway

### Fixed（6 件 v1.0.1）
- FB_DL_ConveyorDirMismatch（R41 挂账 P0 当轮修）/ FB_DL_AxisInposGuard / FB_DL_CascadeWindupLink / FB_DL_AxisAbortSafeSeq（R41 终审挂账）
- FB_DL_ElTestStation（R42 终审当场修：锁存相位迁移闸缺失，0397 解除式不可达）/ FB_DL_HydronicMeterAudit（R42 终审当场修：_eState 漏声明编译阻断 + 饱和锁存后 eRun 不冻结）

### 总库
- registry 725→745（v2.34.0），JSONL 745 条（badjson=0，NEW20 20/20 MATCH，返修重注入 6/6）；机检 24/24 PASS + 终审返修 2/2 PASS。

---

## v2.33.0 — 2026-11-19（R41 / 既有 ◐ 组零检索深化 20 新件 + 3 返修轮）

### Added（20 新件，4 批全部完成）
- DL_Base（+3）：FB_DL_SignalQualify / FB_DL_MultiClickDetect / FB_DL_ValueHoldMonitor
- DL_MathData（+4）：FC_DL_AngleDiffWrap / FC_DL_WeightedMeanCalc / FC_DL_QuantileCalc / FB_DL_WindowExtremaStat
- DL_Algo（+4）：FB_DL_OverrideSelector / FB_DL_StepResponseIdent / FB_DL_RatioStationCalc / FB_DL_CascadeWindupLink
- DL_Motion（+4）：FB_DL_AxisFollowErrGuard / FB_DL_AxisOverspeedGuard / FB_DL_AxisInposGuard / FB_DL_AxisAbortSafeSeq
- DL_Device（+2）：FB_DL_InverterPdiPoll / FB_DL_FilterSwitchLevel
- DL_Process（+3）：FB_DL_ShrinkTunnelCtrl / FB_DL_VavDischargeAirReset / FB_DL_ConveyorDirMismatch

### Changed
- INDEX_REGISTRY.json v2.32.0 → v2.33.0，total 705 → 725；JSONL 语料 705 → 725 条（新增 20 行 MATCH、3 返修件原地重注入、badjson = 0）。
- 机检 22/23 PASS：MutexOwnerAudit 返修暴露 4 处存量码位冲突（0102/0202/0302/0402，涉 EventCounter / TimeWindowCheck / RorLwordEx / TimeRatioCalc，R39 前历史债，记账不阻断；全库码位冲突普查列 R42 候选 P1）。
- P0 返修 3 件：FB_DL_AxisLimitRecovery（R240 解除式锁存量自指，改全当拍量）/ FB_DL_MutexOwnerAudit（R241 降型回绕，比较闸上移 UDINT 域）/ FC_DL_StringToDint（16#0001_038B 出口 bError 配对补齐，v1.0.1 → v1.0.2）。
- 事故处置：机检补丁脚本 `io.open(p,"wb").write(表达式)` 先截断后求值失败，FC_DL_AngleDiffWrap.st 被清空 0 字节，按头注释规格由主控重建；「先读全量到内存、单次原子写回」入册 R254。
- T0 头注释溯源短语（「IEC 61131-3 标准语义的道莅防御性实现」）1 件漏写被机检拦截并补正。
- 终审 4 抽（批 3/4 控制类件）：1 严重（FB_DL_ConveyorDirMismatch——诊断 TON 用 R_TRIG 单拍沿直连 IN，结构性永不到时，036D/036E 检出不可达）/ 2 中（FB_DL_AxisInposGuard 监视 TON 未随故障相门控，复位拍同拍重锁 03AF；FB_DL_CascadeWindupLink 故障期实际仍写 fbOuter.bTrack:=TRUE 而出口 bFreeze 强制 FALSE，名实不一）/ 1 轻（FB_DL_AxisAbortSafeSeq eAbortStop 相单拍迁出致 tonStopTo 分支不可达）——均挂账 R42 P0/P1，当轮不改码。
- 反证句选题机制（R40 落地）首轮生效：28 候选拒 8（3 假缺口 + 5 同义在册），零撞名零拒单。

## v2.32.0 — 2026-11-19（R40 / T0 防御包装轮）

### Added（15 新件，20 目标中 5 个与在册件重复被剔除，如实少报）
- DL_MathData（+13）：FC_DL_MaxNanEx / FC_DL_MinNanEx / FC_DL_RealEqTolEx / FC_DL_RangeCheckEx / FC_DL_RealToDintSat / FC_DL_RealToRealSat / FC_DL_RoundBankEx / FC_DL_DegToRadEx / FC_DL_RadToDegEx / FC_DL_MuxIntEx / FC_DL_StringToLowerEx / FC_DL_StringToUdintEx / FC_DL_IndexClampEx
- DL_Base（+2）：FB_DL_SrEx / FB_DL_RsEx
- 全部为 T0 iec-std-wrapper 防御包装（委托内建/平台语义，不自研内核）；剔除明细：FC_DL_LimitEx / FC_DL_TimeAddSat / FC_DL_TimeScaleSat / FB_DL_EdgeDivider / FB_DL_TpEx 与在册件同名。

### Changed
- INDEX_REGISTRY.json v2.31.0 → v2.32.0，total 705；JSONL 语料 690 → 705 条（新增 15 行 output 与磁盘源码逐字节一致）。
- 机检 15/15 PASS（禁 GVL/VAR_EXTERNAL、禁 %I/%Q、ENUM 冒号、CASE 缺 ELSE、注释嵌套、VAR_OUTPUT、TON/R_TRIG 条件分支刷新、CRLF、码位重复）。

## v2.31.0 — 2026-11-19（R39 / 20 新件 + 3 返修轮）

**新增 20 件｜总数 670 → 690**（子库：DL_Base +1、DL_MathData +2、DL_Algo +3、DL_Motion +2、DL_Device +5、DL_Process +7，合计 4,218 行）

- FB_DL_MutexOwnerAudit（DL_Base / FB / `16#01_0_02` / t0-8-sema）— 互斥锁所有权审计台账：持锁者/持有时长/越权释放/超时归还，只做事后可追出口
- FC_DL_TrendSlopeCalc（DL_MathData / FC / `16#05_0_04` / t2-1-lgf-math）— 滑窗一阶最小二乘趋势斜率：斜率/截距/R² + 非有限剔除
- FC_DL_SphericalDistance（DL_MathData / FC / `16#05_0_05` / t2-1-lgf-math）— 球面大圆距离 haversine：域钳制 + 同点零距分支
- FB_DL_FrequencyGenerator（DL_Algo / FB / `16#02_3_86` / t2-1-lgf-siggen）— 连续频率发生：方波+相位复位+占空比组态
- FB_DL_TriangleGenerator（DL_Algo / FB / `16#02_3_87` / t2-1-lgf-siggen）— 三角波发生：相位连续 + 幅值/频率引脚化
- FB_DL_LaminatorPressCtrl（DL_Algo / FB / `16#02_3_88` / t2-2-lbp）— 层压机压力-时间闭环：双目标分离 + 斜坡限速
- FB_DL_CamOverrideTrim（DL_Motion / FB / `16#04_0_A6` / t1-6-plcopen）— 凸轮动态修调：幅值/相位偏置实时叠加
- FB_DL_AxisLimitRecovery（DL_Motion / FB / `16#04_0_A7` / t1-6-plcopen）— 硬限位脱离恢复顺控：判向→低速脱离→确认→再使能
- FB_DL_BcdFieldPanelIO（DL_Device / FB / `16#03_2_17` / t2-1-lgf-converter）— 面板 BCD 拨码阵列 IO 组装：消抖+组装+校验出口
- FB_DL_DoorInterlockHvac（DL_Device / FB / `16#03_2_18` / t2-2-lbp）— 门禁-风机联锁：开门降频→关门延时恢复
- FB_DL_ElMutingGantry（DL_Device / FB / `16#03_2_19` / t1-5-tcopen）— EL 龙门光幕屏蔽：4 传感器时序判向 + 超时强制退出
- FB_DL_CleaningBrushWear（DL_Device / FB / `16#03_2_1A` / t2-6-rockwell-aoi）— 刷辊磨损/换刷里程：行程+电流双判据三分类诊断
- FB_DL_OrificeDpZeroTrim（DL_Device / FB / `16#03_2_1B` / t2-8-ne43）— 孔板差压零点漂移补偿：静流零点跟踪修正量出口
- FB_DL_HjtPvdSeq（DL_Process / FB / `16#06_0_B6` / pv-process）— HJT PVD 镀膜四段顺控：段超时升级+双到位联锁
- FB_DL_ElectrolyteFillCtrl（DL_Process / FB / `16#06_0_B7` / t2-2-lbp）— 注液量闭环：称重减量法+浸润驻留
- FB_DL_CartonDenestPush（DL_Process / FB / `16#06_0_B8` / t2-7-packml）— 纸箱分离-推箱顺控：双料位联锁
- FB_DL_RadiatorZoneValve（DL_Process / FB / `16#06_0_B9` / t2-2-lbp）— 散热器末端三点阀温控：房间闭环+最小启停间隔
- FB_DL_TankLevelStrapping（DL_Process / FB / `16#06_0_BA` / strapping）— 储罐液位-容积分层标定：越表插值拒绝
- FB_DL_WaferBreakDetect（DL_Process / FB / `16#06_0_BB` / t2-1-lgf-measurement）— 电池片隐裂判据：视觉位+峰值双判据聚合分级
- FB_DL_RoomCo2DemandVent（DL_Process / FB / `16#06_0_BC` / t1-2-oscat-building）— CO₂ 需量通风：最小新风硬下限+失效退守

**返修 3 件（R38 终审挂账，接口不变，v1.0.1 → 1.0.2）**：FB_DL_ModuleLamVacuumSeq（配方 TON 与超时 TON 成对拆分 + bReset 迁出边）、FB_DL_ElectrodeTabBendCtrl（三相 TON 独立实例 + eFault 迁出）、FB_DL_VavBoxZeroCal（tonStable/tonCal 按相独立实例）；语料原地重注入。

**质量口径**：机检 23/23 PASS fail=0（R228-A/B 首轮上线：3 返修件修复前命中→修复后 0，20 新件 0）；JSONL 670 → 690，badjson=0，23/23 字节 MATCH；码位六窗口与占用全集（头部∪全文）零交集。

## v2.30.0 — 2026-11-18（R38 / 7 续作 + 13 新件轮）

**新增 20 件｜总数 650 → 670**（子库：DL_Base +2、DL_MathData +2、DL_Algo +3、DL_Motion +2、DL_Device +5、DL_Process +6）

- FC_DL_SaturateAdd（DL_Base / FC / `16#01_0_00` / t2-1-lgf-math）— 饱和加减：以 LINT 中间量计算后按目标区间钳制，禁 DINT 相加后判回绕
- FB_DL_ToggleButtonBank（DL_Base / FB / `16#01_0_01` / t1-5-tcopen）— 多路按钮组解算：Toggle / SingleAct / Selector3 三模式 + 通道互斥 + 上电恢复策略
- FC_DL_LinearRegression2Var（DL_MathData / FC / `16#05_0_02` / t2-1-lgf-math）— 二元最小二乘回归 + 共线性判据（|r12| 越限判不可辨识，不输出斜率）
- FC_DL_OscillationIndex（DL_MathData / FC / `16#05_0_03` / t2-4-s7-motion）— 回路振荡指数（过零率 × 幅值离散度归一化 0~1），与 CpkIndex 分工：判抖 vs 判偏离
- FC_DL_PidLambdaTune（DL_Algo / FC / `16#02_3_83` / t2-1-lgf-math）— IMC/λ 整定纯换算（K/T/τ/λ → Kc/Ti/Td），不产生激励、不闭环
- FC_DL_HeatExchangerLmtd（DL_Algo / FC / `16#02_3_84` / t2-1-lgf-technology）— LMTD + ε-NTU 效能（逆流/并流/1-2 程 F 修正，端差趋零退算术平均）
- FB_DL_CrossCorrelationDelay（DL_Algo / FB / `16#02_3_85` / t2-4-s7-motion）— 互相关时延估计（峰值定位 + 抛物线亚采样插值 + 置信度门限）
- FB_DL_SpindleOrientationStop（DL_Motion / FB / `16#04_0_A4` / t1-6-plcopen）— 主轴定向停止：最短角路径寻标 → 爬行锁定 → 抱闸释放时序
- FB_DL_ElectronicCamSwitchBank（DL_Motion / FB / `16#04_0_A5` / t1-6-plcopen）— 电子凸轮开关组（位置触发 + 相位偏移 + 触发脉宽 + 单次/周期）
- FB_DL_VavBoxZeroCal（DL_Device / FB / `16#03_2_12` / t1-2-oscat-building）— VAV 末端风量两点零点标定（静流稳定判据 + 标定期冻结调节）
- FB_DL_ElectrodeTabBendCtrl（DL_Device / FB / `16#03_2_13` / t2-2-lbp）— 极耳折弯角度与回弹学习（单向逼近，学习值限幅，迭代耗尽不冒 OK）
- FB_DL_JunctionBoxPottingCheck（DL_Device / FB / `16#03_2_14` / t2-1-lgf-technology）— 接线盒灌胶量积分窗 + 固化当量（°C·min）双判据独立记账
- FB_DL_PouchSwellingGauge（DL_Device / FB / `16#03_2_15` / t2-1-lgf-measurement）— 软包鼓胀厚度巡检（Welford 批内统计 + Z 分数与绝对限双口径）
- FB_DL_FreshAirStepperDamper（DL_Device / FB / `16#03_2_16` / t1-2-oscat-building）— 新风阀步进开环（步数↔开度当量 + 反向间隙补偿 + 端点自学习）
- FB_DL_HeatSealProfile（DL_Process / FB / `16#06_0_B0` / t2-7-packml）— 热封温度-压力-时间三参数配方曲线（段切换 + 超窗判废 + 配方校验）
- FB_DL_AhuEconomizer（DL_Process / FB / `16#06_0_B1` / t1-2-oscat-building）— 空调箱新风经济器（焓值主判据 + 干球后备 + 防冻锁存）
- FB_DL_TerminalReheatSeq（DL_Process / FB / `16#06_0_B2` / t1-2-oscat-building）— 末端再热级联联锁（最小风量按级降档 + 再热上限级联）
- FB_DL_RfReflectedMonitor（DL_Process / FB / `16#06_0_B3` / t2-1-lgf-measurement）— 射频反射比监视（双阈值迟滞 + 请求调谐，仅监视不闭环）
- FB_DL_StringSolderQuality（DL_Process / FB / `16#06_0_B4` / t2-1-lgf-technology）— 串焊质量三判据逐通道分级 + NG 位掩码 + 拉力抽检整批判废
- FB_DL_ModuleLamVacuumSeq（DL_Process / FB / `16#06_0_B5` / t2-7-packml）— 组件层压真空四段顺控（真空-温度双到位才升压 + 段超时升级）

**返修 2 件（v1.0.2）**
- `FB_DL_LineShaftClutch`：脱开相耦合权重基准由硬编码 1.0 改为进入脱开相的实际权重快照（`_fW0Diseng`），消除从对齐相脱开时权重 0→1 跳变导致的反向驱动；起始权重近零时单拍收口。
- `FB_DL_CurtainEFEMZone`：间隙计时器 `tonGap` 增加断输入请求 `_bGapBreak`，随每次新遮光事件重启，修复爬行通过时相邻间隔判据失效、停留屏蔽态的安全侧缺口。

**元数据**：registry 670（v2.30.0，counts Base 77 / MathData 178 / Algo 67 / Device 133 / Motion 64 / Process 151）；JSONL +20 条（总量 670）。

## v2.29.0 — 2026-11-18（R37 / R36-RESUME 续作轮）

**新增 10 件（R36 遗留 17 件中前 10 件续作）｜总数 640 → 650**

- 子库分布：DL_Device +7（`WaferCoolChuck` 03_2_0B / `CurtainEFEMZone` 0C / `VentPurgeDuty` 0D / `SlurryLevelBank` 0E / `FoupPurgeN2Flow` 0F / `CartonErectVacMonitor` 10 / `CoderRibbonLife` 11）、DL_Motion +2（`LineShaftClutch` 04_0_A2 / `FlyingCutSync` A3）、DL_Algo +1（`ResonanceTrackNotch` 02_3_82）
- registry 640 → **650**（v2.29.0，counts 75/176/64/128/62/145）；JSONL 640 → **650** 条（badjson=0，10/10 output 与落盘文件字节级 MATCH）
- 机检 10/10 PASS fail=0：零 `VAR_EXTERNAL` / 零 `%I%Q` / 零注释嵌套 / CASE 全含 ELSE / 枚举单冒号 0 / 码位三向一致零撞车 / 双语注释达标；2 件 LF→CRLF 已修
- 码位窗口派单前**码字层实测**（R215/R216 落地）：`02_3` 82 起、`04_0` A2/A3、`03_2` 0B~11 全部实测空闲，本轮零撞码
- 编码线单窗口 10 件一轮完成（R214 定档 ≤10 件/轮），单件约 70 秒，为 R36「20 件/窗 3/20」的低产找回产能
- 依赖契约两处「派单规格 vs 已注册件」不一致，按 R203 口径以 registry 为准 + 头注释显式声明：`I_DL_MotionAxis` 无 `bStandstill`（改判 `eState = eStandstill`）；`E_DL_FailSafeDir` 全库无定义（本件同文件发布）
- 终审 4 抽 4 命中（100%）：`ResonanceTrackNotch`（锁定出口未随幅值降级）、`FlyingCutSync`（首圈标记初值吃首圈）当场修 v1.0.1；`LineShaftClutch`（脱开权重满值致安全反向）、`CurtainEFEMZone`（间隙计时器不重启致漏判）挂账 R38 并加「禁止投运」头注释
- 扩产裁决 R218：**不放量 20 件/轮**，加件须连续两轮抽检挂账率 ≤25% 且编译债清零
- 债务：编译验证债连欠 **33 轮**；MathData/Base 两本 MANUAL 接口表；ROADMAP 未勾 183 条（本轮勾 7）；故障码体例双轨

## v2.28.0 — 2026-11-18（R36）

**新增 3 件（R36 规划 20 件，编码窗口超时 3/20，17 件转 R36-RESUME）｜总数 637 → 640**

- **DL_MathData +2**：`FC_DL_HarmonicSpectrumBin`（FFT 谱线基波/谐波分箱幅值提取，窗函数 + 幅值归一 + 非有限输入拒绝，码位 05_0_00 首开段）、`FC_DL_CubicSplineInterp`（三样条插值查表：单调段三对角求解 + 端点钳位 + 区间外拒绝，码位 05_0_01）
- **DL_Algo +1**：`FB_DL_DisturbanceObserver`（扰动观测器：状态差分 + 低通估计 + 观测增益钳位 + 输出限幅前馈补偿，码位 02_3_81）

**流程事件**：① 规划线 W6（06_0_B0~B5）与 W5（03_2_10~12）码位窗口在码字层与 R35 存量冲突，总监派单扫描正则只查字面未扫码字 → 编码线拒单改派，本 3 件用实测无冲突窗口；② 编码 20 件单窗口超 30 分钟硬顶，3/20 后按超时保护收口，未完 17 件写入 RESUME。
## v2.27.0 — 2026-11-18（R35）

**新增 19 件（R35 规划 20 件，#13 撞名跳件）｜总数 618 → 637**

- **DL_Process +14**：`FB_DL_TrackerWindStow`（跟踪支架大风保护收拢：风速阈值迟滞 + 爬升率趋势双判据 → 安全角度命令出口，解除驻留可达）、`FB_DL_LaminatorTempProfile`（层压机多温区升温/保温/降温配方曲线跟随，复用 `FB_DL_RampSoakProfile`）、`FB_DL_StringerTrend`（串焊机多通道焊接温度曲线在线监视：峰值窗 + 逐通道分级告警）、`FB_DL_PottingDispenseCtrl`（接线盒灌胶定量：称重减量法 + 双组份混合比闭环 + 偏差窗安全侧停 A）、`FB_DL_PileClampCtrl`（堆叠压紧板预压/全压两段压力-位移控制，复用 `FB_DL_StepSequencer` + `I_DL_Cylinder`）、`FB_DL_CvdTempRamp`（CVD/扩散炉多段 Ramp/Soak 曲线跟随 + 均匀性判据）、`FB_DL_AnalyzerSampleSeq`（在线分析仪取样-吹扫-标定三态轮换顺控：相超时升级 + 标定过期锁存禁取样）、`FB_DL_SteamHeaderSplit`（蒸汽母管多支路分程分配，复用 `FB_DL_SplitRangeControl`）、`FB_DL_HydronicDeltaTGuard`（水系统大/小温差失衡诊断 + 旁通泄漏确认窗）、`FB_DL_ChillerApproachTrend`（冷机逼近度趋势诊断与性能衰减预警，复用 `FB_DL_SignalStatistics`）、`FB_DL_PlatingCurrentCtrl`（电镀槽位电流密度闭环与液位联锁）、`FB_DL_FiringFurnaceZone`（烧结炉多温区峰值温度跟随 + 链速前馈重置限幅）、`FB_DL_InvInsulTestSeq`（逆变器绝缘测试加压-保持-泄放联锁顺控，泄放未确认禁放行）、`FB_DL_ForelinePressureCtrl`（真空前级管路压力稳定：调节阀位 PI + 抽速前馈非有限拒绝 + 限幅反算抗饱和）
- **DL_Device +5**：`FB_DL_GloveBoxAtmoCtrl`（手套箱气氛联锁：水氧越限禁开门 + 净化循环请求，NE107 出口）、`FB_DL_ProcessKitTimer`（腔体部件保养计时器：工艺拍数/时长双口径 + 到期锁存）、`FB_DL_ExhaustDpTrend`（尾气管路压差趋势监视与堵塞预警）、`FB_DL_BypassValveTrim`（旁通阀供回水压差 PI 微调，复用 `FB_DL_PidController`）、`FB_DL_CaseSealTapeMonitor`（封箱胶带缺料/断带监视：张力 + 光电双判据去抖）
- **撞名跳件报备**：派单 #13 `FB_DL_ChamberGateValve`（DL_Device）因已于 11-17 由 roadmap-p1 泳道注册实现而撞名跳件——未落盘、未重复注册，实际入库 19/20；开批前重跑同名快照已固化为新规则 R208
- **码位子码错位惯例**：R34「+0x10 子码步进」使 Process 格 90~99 基码与既有 80~89 格第二子码段（0690~069B）撞码，本轮 90~99 格子码整段错位至 B0~B9 / C0~C9 / D0~D9 避让，全库零撞码，头注释逐件留档（新规则 R207）
- **机检口径修正 3 处（均经存量 3 件回归后入册 R204~R206）**：① 计数一律在注释剥离后执行（头注释描述文字曾致 20/20 级误报）；② VAR 开块正则补齐 `VAR CONSTANT` 双词块头；③ N1 定时器规则增加「存在同文件 `IN:=FALSE` 复位路径则豁免」限定（R40 分段断电范式，如 `PileClampCtrl` 的 `tonHold`）
- **终审抽检 4 抽 4 PASS、0 严重缺陷**（TrackerWindStow / ChillerApproachTrend / AnalyzerSampleSeq / ForelinePressureCtrl，重点核：隐性回夹 / 输出枚举 CASE 赋值 / 锁存副本与镜像混用 / 码位落窗 / 防除零 / 依赖件引脚名）；3 项轻微记账转 R36 返修池（注释-行为不符 ×1、失能经 eFault 过桥 ×2、单拍脉冲语义未标注 ×1）
- 机检 19/19 PASS fail=0；registry 618 → **637**（v2.27.0，counts 75/174/62/116/60/131）；JSONL 618 → **637** 条（badjson=0，19/19 新件 output 与落盘文件字节级 MATCH）



## v2.26.0 — 2026-11-18（R34）

**新增 20 件（R34 规划）｜返修 1 件（v1.0.2）｜总数 598 → 618** ｜ **专家进化固化批次 FB-33（10 条 → 8 簇）**

- **DL_Process +12**：`FB_DL_LaserWeldPowerSeq`（激光焊预焊-满焊-收弧三段功率斜坡配方序列（功率/速度/离焦三维配方切换））、`FB_DL_OcvGradingBin`（OCV 电压+内阻双判据分档与落料位决策（档位带 + 满仓避让））、`FB_DL_ChamberPurgeDry`（腔体干燥吹扫顺控（露点判据收敛 + 吹扫/静置/复测三态））、`FB_DL_LoadlockPressureCross`（Loadlock 双表压力交叉校验与误开门拦截（偏差窗 + 首出定位））、`FB_DL_StringCurrentMismatch`（组串电流失配诊断与遮挡定位（中位基线 + 分级 + 异常串号输出））、`FB_DL_PvSoilingLossRate`（组件积灰损失率估算与清洗提醒（功率基线衰减速率 + 清洗阈值））、`FB_DL_TrapSealTrend`（枕式包装封口温度随线速前馈重置（线速→封温设定 + 限速重置））、`FB_DL_LamTempUniformity`（层压板面多测点温度均匀性诊断（极差/标准差双判据 + 分区告警））、`FB_DL_StratificationGuard`（水箱温度分层监视与混温抑制（上下点温差门限 + 混水泵调节请求））、`FB_DL_AndonRespTimeReport`（安灯呼叫→应答→解除三段计时与四级响应时长分档台账）、`FB_DL_BatchEndPointTrend`（批次反应终点趋势判据（斜率收敛 + 终点窗 + 超时升级））、`FB_DL_DryerExhaustHumidityCtl`（干燥排湿热回收风门控制（排湿焓值判据 + 回风混风域闸））
- **DL_Device +5**：`FB_DL_CombinerArcDetect`（汇流箱直流拉弧特征判据（高频分量 + 波动窗 + 分级告警出口））、`FB_DL_CellVolumeCheck`（电芯厚度/体积激光测距校验（NE43 质量位 + 超差分档））、`FB_DL_MfcRatioCheck`（MFC 流量配比偏差核对（标定换算 + 配比窗 + 配方回读比对））、`FB_DL_PhaseNeutralImbalance`（三相不平衡度与中性线电流判据（不平衡率分级 + 缺相识别））、`FB_DL_HumidifierWaterQual`（加湿器水质电导率监视与排水联锁（门限 + 排水周期 + 补水禁投））
- **DL_Motion +2**：`FB_DL_FilmTensionStepper`（收卷步进张力叠加微调（叠加偏置 + 张力带 + 步进增量限幅））、`FB_DL_TrackerAngleYearWin`（跟踪支架年度角度表切换（年窗+月窗双闸 + 角度表版本锁存））
- **DL_Algo +1**：`FB_DL_RfMatcherTune`（射频匹配器反射比最小化步进搜索（三点探步 + 收敛判据 + 越限回退））
- **DL_MathData 返修 1 件**：`FB_DL_SlurryViscosityComp` v1.0.2（`bRun=FALSE` 改「冻结末次有效粘度 + 置 `bDegraded`」；`bClamped` 与 `xClamped` 同源赋值，接口零变更）
- **终审抽检 2 抽 2 修（v1.0.1）**：`FB_DL_TrapSealTrend`（判停误用前馈替代值致 `eHold` 相不可达 → 改按原始线速判停）、`FB_DL_CombinerArcDetect`（段 1 无条件清锁存抹掉保持型拉弧码 0310 致三出口不一致 → 按码专清 + 失能同拍清锁存 + 补两个正域闸）
- **机检口径修正 2 处**：ENUM 规则区分单冒号 `:` 与带值 `:=`（全库 463 件为带值体例）；N2 CASE 区间判定改用行锚点（原 `rfind("CASE")` 被 `END_CASE` 子串骗过致 20/20 误报）
- 机检 `check_r34.py` 21 件（20 新 + 1 返修）**21/21 PASS fail=0**；registry 598 → **618**（v2.26.0，counts 75/174/62/116/60/131）；语料 598 → **618** 条，新增 20 行 + 返修 1 行 sha256 全 MATCH、badjson=0；码位零撞车

## v2.25.0 — 2026-11-18（R33）

**新增 20 件（R33 规划）｜返修 3 件（v1.0.1）｜总数 578 → 598**

- **DL_MathData +2**：`FB_DL_SlurryViscosityComp`（浆料粘度温度补偿，基准温度退化与外推越界钳位）、`FB_DL_ShrinkFilmUsageCalc`（收缩膜用量与单位换算，含损耗率域闸）
- **DL_Algo +2**：`FB_DL_TrackerSolarAngle`（太阳时角/赤纬与逆跟踪防阴影角度解算）、`FB_DL_CoolingTowerOpt`（冷却塔群控逼近度优化，最小开机数 + 防短循环死区 + 错峰投切）
- **DL_Device +5**：`FB_DL_FanBeltSlipDetect`（风机皮带打滑转速差判据）、`FB_DL_UnlockHoldTimeout`（解锁保持超时）、`FB_DL_VacuumPumpBasePress`（真空泵本底压力趋势）、`FB_DL_InverterDeratingCtrl`（变频器热模型降额，t2-ne107 状态族）、`FB_DL_PrecursorCanisterWeight`（前驱体罐称重减量投料）
- **DL_Motion +1**：`FB_DL_FilmTaperTension`（卷径推算 + 锥度张力）
- **DL_Process +10**：`FB_DL_ChillerLiftOptimize`、`FB_DL_FreezeStatGuard`、`FB_DL_StackPressureProfile`、`FB_DL_PilePressLimitClass`、`FB_DL_PressFitCurveArchive`、`FB_DL_CartonScannerSort`、`FB_DL_PigLauncherSeq`（t2-lgf 清管发射顺控）、`FB_DL_FormationTempRiseRate`、`FB_DL_RollChangeoverSeq`（t2-isa88 配方切换）、`FB_DL_AndonLinePack`（t2-isa182 三级安灯仲裁）
- **返修（v1.0.0 → v1.0.1，接口与 VAR 顺序不变）**：`FB_DL_BlindPositionCtrl`（安全收回驱动方向改 `oMotorUp`，与位置递减/上限判据同向；`tonPace` 改 `IN := NOT tonPace.Q`）、`FB_DL_CompressorFleetStaging`（`tonStagger` 自复位振荡窗；3015/3016 改每拍重算非锁存，3017 保留锁存并加 `bSigOk` 恢复沿清码）、`FB_DL_WaferThermalBudgetAccum`（`bTempOk` 恢复沿清 3024、复位沿提前到段 1 全局、`tSample<=0` 正域闸置码不静默）
- **机检**：`check_r33.py` 增量 23 件 —— 20 新件 **20/20 PASS fail=0**；新增 2 条机器规则（N1 定时器 `IN` 不得为字面 TRUE；N2 CASE 块内禁止给输出枚举左侧赋值），首用命中 3 件历史件（`BlindPositionCtrl` 13 处输出枚举 CASE 赋值、3 件故障码旧体例 `16#3015` 类），判定为历史债务登记、不阻断本轮入库。
- **终审返修（2 件，v1.0.0 → v1.0.1）**：`FB_DL_RollChangeoverSeq`（`bSeqDone` 在 CASE 内置位、段 3 首行同拍清零致**完成脉冲恒假**〔严重〕→ 改内部 `_bDone` 置位、段 3 映射后单拍收口；`uCode` 改锁存 + 复位沿/启动沿双清；`bRejected`/`nFailIdx` 改启动沿清）、`FB_DL_InverterDeratingCtrl`（过压与过温同归 `eIRsnOverTemp`、`eIRsnOverVolt` 永不赋值 → 三处越阈分支按 `fVoltV` 分离归因）。
- **语料**：JSONL 578 → **598** 行，badjson=0，新增 20 行 + 返修 3 行原地重注入；本轮新增件 sha 全量 MATCH。
- **码位**：20 件独占 20 槽（`02_3_5C~5F` / `03_1_01~05` / `04_0_6C` / `06_0_37~40`），CLASH=NONE、INTRA=NONE；故障码 `16#0000_0101~0105`（Device 段）与存量零冲突。

---

## v2.24.0 — 2026-11-18（R32）

- registry v2.23.0 → **v2.24.0**，558 → **578** 件（counts Base 75 / MathData 172 / Algo 59 / Device 106 / Motion 57 / Process 109）；JSONL 578 行 badjson=0。
- **T0 纯函数 9 件**（DL_MathData）：`FC_DL_StringToUpperEx` / `StringStripCharsEx` / `BytesToHexString` / `HexStringToLword` / `ReverseBitsWord` / `DtAddSecondsSat` / `DivDintSafeChk` / `ModLrealSafe` / `BitArrayReverse`——字符串/十六进制/位串/日历/安全算术五组补齐，`FC_` 纯函数 4 槽码位。
- **行业池 11 件**（DL_Process）：`FB_DL_SteamTrapDiagTrend` / `ColumnDpSteadyWatch` / `VavCouplingFeedforward` / `BlindPositionCtrl` / `CompressorFleetStaging` / `AhuSupplyAirReset`（暖通·公用工程）｜ `BatteryModuleBalanceMonitor`（锂电）｜ `WaferThermalBudgetAccum`（半导体 Arrhenius 量纲链）｜ `CaseSealerFlapFoldSeq`（包装）｜ `NitrideFurnaceAmmoniaPurge` / `BusbarWeldMonitor`（热处理·锂电）。
- 机检（`check_r32.py`，增量 20 件）**20/20 PASS**，fail=0 / intra_dup=0 / 2,817 行；零检索轮（原生召唤 ×3）。
- **整改 2 项**：① 20 件补写头注释「溯源声明」（T0 用 IEC 标准语义道莅实现、行业池用 clean-room 口径）；② **真撞码** `FC_DL_StringToUpperEx` `02_3_34~37` → 改判 `02_3_58~5B`（3034~3036 → 3058~305A），registry `code_segment` 与 JSONL output 同步重注入。
- **终审 4 件抽检 → 2 挂账 / 2 PASS**：`BlindPositionCtrl`（安全收回驱动力向与到位判据矛盾）、`CompressorFleetStaging`（错峰 TON 无自复位）、`WaferThermalBudgetAccum`（3024 无复位路径 + 批次边界不清预算）挂 R33 返修；`FC_DL_ModLrealSafe` PASS（1 提示级死变量）。
- 今日 **59/200**；总库 **578/10,000（5.78%）**，500 计划达成（+78）。

---

## v2.20.0 — 2026-11-18（R31）

- registry v2.19.0 → **v2.20.0**，539 → **558** 件（counts Base 75 / MathData 163 / Algo 59 / Device 106 / Motion 57 / Process 98）。
- R31 入库 19 件（计划 20，序 1 `FB_DL_LamDoorInterlock` 与 R29 已建同名作废、零污染）：DL_Process 11 / DL_Device 4 / DL_Motion 2（T1-6 外部编码器族开族）/ DL_Algo 1 / DL_MathData 1。
- 机检 **19/19 PASS fail=0**（check_r31.py，71 码位 CLASH=NONE）；JSONL **558 条** sha256 19/19 MATCH；主控修 4 处真缺陷（枚举单冒号 / bError 未声明 / 码位撞车改判 03F2~03FB / 头注释终结符误计）。
- 终审抽 5 件：WaferHandoffSeq PASS；ReactorStepCtrl / ChamberLeakRate / FilmTensionDancer / EtchEndpointTrend 修 5 处升 v1.0.1 并回注 JSONL（4/4 MATCH）。
- 专家进化新增 **R166~R175**（PLC 5 + 总监 5）；机检规则修正四件套（R124 续：DOTALL 剥离 / 剥后计数 / I_ 豁免 / 槽型 2~5 分型）。
- 今日累计 39/200；WebSearch 0/3；本轮时长超 50 分钟上限（主控修缺陷 + 机检返工），如实披露见战报。

## v2.19.0 — 2026-11-18（R30）

**新增组件**：20（`DL_Device` 5〔含 R29 隔离件返修入册〕｜ `DL_Process` 8 ｜ `DL_Motion` 3 ｜ `DL_Algo` 2 ｜ `DL_MathData` 1 ｜ `DL_Base` 1）｜ **累计**：**539 / 10,000（5.39%）**

**返修收口**：`FB_DL_AhuFilterDpBank`（R29 quarantine 件）按裁定方案返修入册——共享单实例 `tonDeb` 改 `aTonDeb : ARRAY[1..4] OF TON`、每扫描周期对 4 实例无条件刷新、候选作废显式 `IN:=FALSE` 复位；R40/R7 复合缺陷闭环；码位由作废段 03C5~03C9 重排实测游标新段 03D9~03DD；枚举 `E_DL_FilterStage` 本文件唯一属主。

**码位**：Device `0003_03D9~03F1` ｜ Process `0005_0467~048E` ｜ Motion `0004_0354~0362` ｜ Algo `0002_3729~3732` ｜ MathData/Base `0001_048A~0491`；全库唯一（CLASH=NONE）｜ **机检**：`check_r30.py` **20/20 PASS fail=0**（收口 21 处误报三类清零：TON 形参赋值行 / 限定名 CASE 标签 / FC 返回值赋值）

**终审**：4 件定向抽查（AhuFilterDpBank 返修验证 / FoupDoorSeq / ChecksumSum64 / SiloLevelInterlock）→ **4 过 0 修**；R40 数组定时器无条件刷新范式首次返修验证通过；整数进位点两向量（T#100MS 恰好等于下限 / 恰好整除容量 uCount=uCap）与锁存解除可达式逐件自证通过；轻微缺陷 1 处留档（FoupDoorSeq `eDoorOpen` 相内门磁回落无驻留失守监视）

**数据**：registry 519→**539**（counts Algo 58 / Base 75 / Device 102 / MathData 162 / Motion 55 / Process 87）｜ JSONL **539 条** ｜ 源：ROADMAP 行业池空位为主 + 返修件，**WebSearch 0/3（零检索轮）** ｜ ROADMAP 勾选 17 行（20 件中 18 名对应；ChecksumSum64/BitArraySegCopy 取自源矩阵台账，无 ROADMAP 行）｜ 专家进化新增 **R161~R165**（固化触发已满足〔未固化 26 条 ≥20〕，按 R143 延期至 R31 排程首位）

---
## v2.17.0 — 2026-11-17（R28）

**新增组件**：17（`DL_Algo` 1 ｜ `DL_Motion` 5 ｜ `DL_Device` 5 ｜ `DL_Process` 6，合计 **4,085 行**；终审修复后 **4,140 行**）｜ **修订**：4 件升 **v1.0.1**（`FB_DL_StepperXyzGantry` / `FB_DL_LaserTabWeldTrack` / `FB_DL_PumpDownEnvelopeMonitor` / `FB_DL_ChillerStagingCurve`）｜ **累计**：**500 / 10,000（里程碑达成）**

**码位**：Algo `0002_3715~3719` ｜ Device `0003_03A7~03BF` ｜ Motion `0004_0327~033F` ｜ Process `0005_0430~044D`；轮内零重复、跨库零撞车（CLASH=NONE）｜ **机检**：`check_r28.py` 17/17 PASS fail=0（含枚举-CASE 完备性、5 槽码位、嵌套注释剥离）

**改名（撞名事件）**：`FB_DL_ChamberPumpDownProfile` → **`FB_DL_PumpDownEnvelopeMonitor`**（存量件为包络上界口径，引脚不兼容）｜`FB_DL_BatchDeviationAlarm` → **`FB_DL_BatchDeviationTierAlarm`**（存量件撞名）｜`FC_DL_FanLawRootCalc` → **`FC_DL_FanLawMultiExpCalc`**（与 DL_MathData 存量件**跨子库同名，编译阻断级**，收口注册时发现）

**终审**：4 件高风险抽 4 修（100% 命中），全部契约零变更：
- `FB_DL_ChillerStagingCurve` v1.0.1：需求台数 `TRUNC(x)+1` 在**正好整除**时多算一台（2.0→4 台而非 3 台）；补负荷率/死区域钳制（超界负荷经实数转整数溢出会翻转加减机方向）；故障解除判据 `(NOT bEnable) AND (NOT _bFaultLatch)` 恒假，组态故障永久不可恢复 → 改失能即解除 + 锁存码回放。
- `FB_DL_PumpDownEnvelopeMonitor` v1.0.1：早停建议位（`bSlowWarn`）置位后无同拍清理点，新循环仍向上位留幽灵建议 → 改段内锁存派生输出；故障码改由锁存码回放，原写法会把组态故障错报成压强故障。
- `FB_DL_LaserTabWeldTrack` v1.0.1：补 `fStallVel_mmS` 组态域闸（负值/NaN 使停滞距离门限失效、bit2 判据静默关闭）；焊点位置与停滞窗起点锁存加位置有限前置（防 NaN 写出口）。
- `FB_DL_StepperXyzGantry` v1.0.1：空闲无事件相补发就绪码，消除「头注释声明 0327 覆盖空闲、实现输出 0」的口径不一致。

**数据**：registry 483→500（counts 74/158/53/93/48/74）｜ JSONL **500 条**（改名件采用**替换行**而非追加）

**红线新增**：R148 选题双查制（全库同名 + 同义，跨子库同名按编译阻断级）｜ R149 终审必查两式（锁存解除可达 / 整数进位点）｜ R150 编码单调用负载配额 ｜ R151 域闸覆盖断言 ｜ R152 锁存解除与码回放 ｜ R153 取整余量进位

**专家进化**：固化批次 **R28**——PLC 线 R139~R147 + R151~R153 合并入 `01-coding-standard.md` 第五部分；总监线 R139~R143 + R148~R150 合并入 `daoli-st-standard` 附录 A/B；两份人格文件各微调 ≤ 6 %

## v2.18.0 — 2026-11-17（R29）

**新增组件**：19 入册 + 1 隔离（`DL_MathData` 3 ｜ `DL_Algo` 3 ｜ `DL_Device` 4 ｜ `DL_Motion` 4 ｜ `DL_Process` 5，合计 **3,940 行**；`DL_Base` 本轮 0 件，唯一候选经查同义作废，不凑数）｜ **累计**：**519 / 10,000**（5.19%）

**码位**：MathData `0001_047B~0489` ｜ Algo `0002_371A~3728` ｜ Device `0003_03C0~03D3` ｜ Motion `0004_0340~0353` ｜ Process `0005_044E~0466`；100 个码位全库唯一、跨库零撞车（CLASH=NONE）｜ **机检**：**20/20 PASS fail=0**（新增 R132 TYPE 块种类、多 ARRAY 逐表判界、STRUCT/END_STRUCT 配对、全角标点四项）

**本轮缺陷实录**：
1. **POU 终结符 20/20 全缺**（R3 库级缺陷同款复发）——编码侧文件尾部未写 `END_FUNCTION_BLOCK` / `END_FUNCTION`，编译阻断级；主控机检拦下并机械补齐，**新红线 R154：单文件写完必须自查首尾（`FUNCTION*` ↔ `END_FUNCTION*`）**。
2. **撞名第 4 起（R148 复发）**：规划书把已注册件 `FC_DL_GasFlowSqrt`（R27，DL_Algo）当新件派单，且目录写 DL_MathData → 将造成跨子库同名编译阻断。主控实测 registry 拦下，改名 `FC_DL_DpFlowSqrtCalc`，其余契约不变。**教训：规划阶段 grep 必须包含「名字已在 registry 但 ROADMAP 未勾」这一类，不能只 grep ROADMAP。**
3. **红线 7 实体违规 1 件**：`FB_DL_AhuFilterDpBank` 的 `tonDeb` 由 4 个温区共享、且仅在 `eTarget<>aeStage` 时刷新 → 无变化扫描周期 ET 冻结、跨区互相复位（R40×R7 复合）。**已 quarantine 至 `_Staging_Raw/2026-11-17/REJECTED_R29/`，不入册不入语料**，待改 `ARRAY[1..4] OF TON` 后重审。

**预算**：子代理 3 角色 / 4 次调用（总监规划 1 + PLC 编码 2〔首发空推理超时失败，重试成功〕+ 总监终审 0〔预算耗尽，改主控机检+抽查〕）｜ WebSearch 0/3（零检索轮）｜ 机检只扫 20 件增量｜ **时长超 50 分钟上限**（23:10→00:0x，主因：PLC 首发子代理 15′49″ 空转无产出）

---
## v2.16.0 — 2026-11-17（R27）

**新增组件**：19（`DL_MathData` 2 ｜ `DL_Algo` 3 ｜ `DL_Device` 5 ｜ `DL_Motion` 3 ｜ `DL_Process` 6，合计 **4,186 行**；终审修复后 **4,214 行**）｜ **修订**：`FB_DL_SplicerAutoJoint` v1.1.0→**v1.1.1**（同步相超时看门狗按相驻留）｜ **累计**：**483 / 10,000**（距 500 差 17）

**码位**：MathData `0001_0471~047A` ｜ Algo `0002_3706~3714` ｜ Device `0003_038E~03A6` ｜ Motion `0004_0318~0326` ｜ Process `0005_0412~042F`；轮内零重复、跨库零撞车（CLASH=NONE）｜ **机检**：20/20 PASS fail=0（含 R132 TYPE 块种类校验；枚举解析先去注释后误报清零）

**终审**：4 件高风险定向抽查 → **2 修 2 过**（MfcFlowCtrl 降设定必误报超调〔峰值初值取回读〕/ SplicerAutoJoint 速度差抖动致同步相看门狗漏窗，均对外引脚零变更；FillWeightCtrl 超重容器继续加注一并收敛；LoadPortSeq PASS）｜ **registry**：464→**483**（v2.16.0）｜ **JSONL**：483 条 ｜ **固化**：R139~R147 延期至 R28（50 分钟预算令，账本顶部已计数）

---
## [v2.15.0] — 2026-11-17 ｜ R26 锂电/化成 + 泵阀风机诊断 + 产线治理 + 凸轮/罐区计量 20 件 / Round 26 — 20 Components (Battery, Valve/Pump/Fan Diagnostics, Line Governance, Cam & Tank-Farm Metrology)

**新增组件**：20（`DL_Base` 1 ｜ `DL_MathData` 4 ｜ `DL_Algo` 1 ｜ `DL_Device` 7 ｜ `DL_Motion` 2 ｜ `DL_Process` 5，合计 **2,290 行**）｜ **累计**：**464 / 10,000**（4.64%）｜ **码位**：本轮 50 个码位全库唯一，轮内零重复、跨库零撞车（CLASH=NONE）｜ **机检**：20/20 PASS fail=0；**机检盲区实录：3 处 STRUCT 误写 ENUM 括号语法 `TYPE X : ( ... );` 编译阻断由主控当场修复**（FB_DL_PidGainScheduler / FC_DL_CamTableInterp / FB_DL_TankFarmInventory），立新红线 **R132**（TYPE 块种类校验）｜ **终审**：4 件高风险定向抽查 → **3 修 1 过**（TankFarmInventory 非有限值毒化保持槽、LineChangeoverChecklist 双表异界越界、CamTableInterp 周期 NaN 穿透，均升 v1.0.1 对外引脚零变更；AlarmShelving PASS）｜ **registry**：444→**464**（v2.15.0，counts 74/156/49/83/40/62）｜ **JSONL**：464 条全量 sha256 MATCH ｜ **六库 VERSION/MANUAL 同步顺延 R27 批量补（新规 R138 债务显式化）**

## [v2.10.0] — 2026-11-16 ｜ R21 数学安全原子 + LWORD 位域/校验 + 文本序列化 + 守卫 FB 20 件 / Round 21 — Math Safety Atoms, LWORD Bit Fields and Checksums, Text Serialization and Guard FBs

**阶段**：Phase 1 第二十一轮（T0 变体线 + T2-1 LGF 子族 + NE107 语义）｜ **新增组件**：20（`DL_MathData` 15 ｜ `DL_Base` 5，合计 **2,802 行**（终审修复后 **2,837 行**））｜ **累计**：**364 / 10,000**（全库约 82,758 行）｜ **子库版本**：`DL_MathData` v1.14.0→**v1.15.0**、`DL_Base` v1.14.0→**v1.16.0** ｜ **码位**：信息级至 `045C`、故障级至 `03A8`（全库唯一性求差断言 CLASH=NONE）｜ **终审**：7 件定向抽查，**3 件命中 + 1 件轻微，全部当轮修复**（1 严重 / 1 中等 / 2 轻微，均升 v1.0.1，对外引脚零变更）｜ **红线违规**：0 ｜ **机检**：`check_r21.py` **20/20 PASS fail=0**（嵌套注释判定升级为非贪婪成对剥离法，修正旧正则跨块误报）｜ **JSONL**：**364 条**，全量 sha256 MATCH ｜ **今日入库**：**178 / 200（89.0%）** ｜ **距 500 冲刺**：差 136 件

### 新增 / Added

| 子库 | 组件 | 类型 | 说明 |
|---|---|---|---|
| DL_MathData | `FC_DL_ModPos` / `FC_DL_DivLrealSafe` / `FC_DL_QuantizeStep` / `FC_DL_PolyEvalHorner` / `FC_DL_WrapAngleDeg` | FC×5 | 数学安全原子：非负取模（负数取余三平台不一致，条件加减归一）/ 浮点防御除法唯一出口（溢出用 `|分子|/MAX > |分母|` 等价判据，禁比较已溢出的商）/ 量化步长 / Horner 多项式求值 / 角度回绕（LREAL 精度归约常数） |
| DL_MathData | `FC_DL_LwordBitFieldExtract` / `FC_DL_LwordBitFieldInsert` / `FC_DL_LwordBitCount` | FC×3 | LWORD 64 位域读 / 读改写 / 汉明重计数；移位量一律按容器归一，宽 64 走常量掩码规避超宽移位未定义行为 |
| DL_MathData | `FC_DL_Crc16Generic` | FC×1 | **参数化 CRC-16**：poly / init / xorout / 输入反射 / 输出反射全部引脚化，逐位实现零查表（可移植性优先），反射不用平台专用位反指令；三组公开向量（ARC `BB3D` / CCITT-FALSE `29B1` / XMODEM `31C3`）等价脚本复算命中 |
| DL_MathData | `FC_DL_ChecksumSum8` | FC×1 | 8 位累加和校验，帧长闸 + 拒绝截断 |
| DL_MathData | `FC_DL_StringToDint` | FC×1 | 整数字符串严格解析：四态机 + 首个非法字符位置 + **升位 LINT 累加先判界**（负域上界 `2147483648` 与正域分开写，禁用单侧 ABS 判据）+ `WHILE` 守卫计数 |
| DL_MathData | `FC_DL_DwordToHexString` / `FC_DL_ArraySumLreal` / `FC_DL_TimeToHmsString` / `FC_DL_DateToIsoString` | FC×4 | 文本序列化：DWORD→十六进制文本、LREAL 数组求和（非有限剔除 + 部分和复检）、TIME→`HH:MM:SS`、DATE→`YYYY-MM-DD`（Hinnant 整数算法 + **回代自校验**） |
| DL_Base | `FB_DL_MinOnOffGuard` | FB×1 | 最短运行 / 最短停止双守卫（压缩机、泵、热泵防频繁启停公共原子）；六态机 + `ELSE` 兜底；**`eRunning` 一并纳入最短运行计时**（否则请求撤在运行态会让实际运行时长翻倍），`eIdle` 只看 `bReq`（修正样板死锁形态，见 R92 裁决） |
| DL_Base | `FB_DL_SignalChangeCounter` / `FB_DL_SamplingTrigger` / `FB_DL_SignalFrozenDetect` | FB×3 | 信号变化计数 / 采样触发（节拍注入，不假设扫描周期）/ 信号冻结检测（超时无变化报警） |
| DL_Base | `FB_DL_PulseWidthFilter` | FB×1 | 窄脉冲抑制：**双侧确认窗**（上升沿与下降沿各一只 TON），合格脉宽不失真、输出整体滞后 `tMinWidth`；失能即直通且两只看守同步复位 |

### 修复 / Fixed（R21 终审）

| 组件 | 版本 | 级别 | 缺陷 | 处置 |
|---|---|---|---|---|
| `FC_DL_DateToIsoString` | 1.0.0→1.0.1 | **严重** | 年序判据 `nYoe` 末项除数误用 `DL_ERA_DAYS = 146097`，公开算法此处应为周期内最大天序 `146096`。二者仅在 `nDoe = 146096`（每个 400 年周期最后一天 = 世纪闰日 2 月 29 日）分叉，错值使 `nYoe = 400` 越出 `[0, 399]`，回代自校验随即失败 → **2000-02-29 / 2400-02-29 等合法日期被误判 0397 故障并回退 `'1970-01-01'`** | 新增常量 `DL_ERA_LAST = 146096` 并改用于该式，其余天序取值两除数同解，零副作用；等价脚本复算 5 个向量（含 2000-02-29）全部自校验通过 |
| `FC_DL_Crc16Generic` | 1.0.0→1.0.1 | 中等 | 空帧分支原写 `uInit XOR uXorOut`，未过输出反射，与本件自身段 6 反射口径自相矛盾；在初值为回文（`0000`/`FFFF`）时看不出差异，**非回文初值 + `bReflectOut = TRUE` 的自定义从站参设下必错** | 空帧分支复用 16 次定长反射循环后再异或终值，与主体路径同构 |
| `FB_DL_PulseWidthFilter` | 1.0.0→1.0.1 | 轻微 | `bReset` 引脚注释承诺「上升沿清抑制计数」，主体却写成电平清零；HMI 上按住复位不放时抑制计数被持续压零，现场会误判「一个窄脉冲都没发生」 | 补 `rtReset : R_TRIG` 实例（与其他实例同段无条件刷新）改为沿判定；并把注释里并不存在的「饱和标志」措辞改为实情 |
| `FC_DL_StringToDint` | 1.0.0→1.0.1 | 轻微 | 溢出分支未写 `nErrPos`，导致 `eErr = 038B`（故障级）与 `nErrPos = 0`（「无错」哨兵）并存，诊断自相矛盾 | 溢出位与非法字符位同口径写入 `nErrPos` |

### 变更 / Changed
- 机检脚本 `check_r21.py`：嵌套注释判定由「正则匹配 `(* ... *)`」升级为**非贪婪成对剥离法**（先剥外层再判内层），修正旧正则在跨代码块时把两段独立注释误判为嵌套的假阳性（沉淀规则 R91）。
- 20+1 件头注释统一溯源短语：T0 件「IEC 61131-3 标准语义的道莅防御性实现」、T2 件「道莅 clean-room 防御性实现」；4 处「同上」占位词改写为显式表述（沉淀规则 R92）。

### 编译验证债 / Compile Debt（新增 3 条）
- `FC_DL_TimeToHmsString`：`TIME_TO_DINT` 毫秒口径未实测。
- `FC_DL_DateToIsoString`：`DATE_TO_DINT` 纪元口径（1970-01-01 = 0）未实测，已由回代自校验兜底为可观测故障。
- `FC_DL_LwordBitFieldExtract`：`WORD` 容器 `SHL` 语义（16 位截断 vs 32 位提升）未实测。

---

## [v2.9.0] — 2026-11-16 ｜ R20 T0 日历/时间族 + 域转换补充 + 字节序 + 同步族 20 件 / Round 20 — T0 Fast Lane: Calendar/Time Family, Domain-Conversion Supplements, Byte Order and the Sync Family

**阶段**：Phase 1 第二十轮（T0 快车道，**零检索**）｜ **新增组件**：20（`DL_MathData` 18 ｜ `DL_Base` 2，合计 2,189 行）｜ **累计**：**344 / 10,000**（全库 79,956 行）｜ **子库版本**：`DL_MathData` v1.13.0→**v1.14.0**、`DL_Base` v1.13.0→**v1.14.0** ｜ **码位**：信息级 `040C`~`0433`、故障级 `0330`~`036B`（全库求差断言零重叠），游标推进至 **信息 `0434` / 故障 `036C`** ｜ **终审**：8 件高风险抽样，**2 件命中并当轮修复**（1 中等逻辑 + 1 注释级，均升 v1.0.1，引脚零变更）｜ **红线违规**：0 ｜ **机检**：16 规则 20/20 PASS fail=0 ｜ **JSONL**：**344 条**（342 条字节级 MATCH + 2 条 CRLF 遗留记录归一化后一致；本轮 2 条修改行已重注入并 sha 复验）｜ **今日入库**：**140 / 200（70.0%）**

### 新增 / Added

| 子库 | 组件 | 类型 | 说明 |
|---|---|---|---|
| DL_MathData | `FC_DL_DtToDintEpoch` / `FC_DL_DintEpochToDt` | FC×2 | Unix 纪元秒 ↔ DATE_AND_TIME 双向防御包装；下域闸先于内建、Y2038 上域两策略分立（正向饱和并升故障级 / 反向**不饱和**，饱和会伪造时刻） |
| DL_MathData | `FC_DL_DateToDintDays` / `FC_DL_DintDaysToDate` | FC×2 | 日期 ↔ 自纪元天数双向；天数口径与 `DateAddDays`/`DateDiffDays` 共用 `DL_DATE_DAYS_MAX` 保守容器口径，四件不会错位 |
| DL_MathData | `FC_DL_TodAddWrap` / `FC_DL_TodDiffWrap` | FC×2 | 当日时刻加减并**条件加减归一**（R11 禁 MOD 纪律），输出回绕标志与圈数；偏移模长 ≥ 一日先闸 |
| DL_MathData | `FC_DL_DateAddDays` / `FC_DL_DateDiffDays` | FC×2 | 日期加天数偏移（±36500 天钳位 + 信息级）、日期天数差；溢出用**减法预判**，正向判 `nWork > 上限−nBase`、负向判 `nWork < 0−nBase`，禁「先加再判变号」 |
| DL_MathData | `FC_DL_TimeAbsSat` | FC×1 | TIME 取幅值饱和；`−MAX−1` 单值闸先行（`nIn < −2147483647` 精确命中 INT32_MIN），饱和值经 `DINT_TO_TIME` 落地不用超长字面量 |
| DL_MathData | `FC_DL_UdintToLintChk` / `FC_DL_WordToIntSat` / `FC_DL_DwordToIntSat` / `FC_DL_LwordToLintSat` | FC×4 | 无符号位串 → 有符号域转换的饱和/告警四件，覆盖 16/32/64 位宽与 UDINT→LINT 升位路径 |
| DL_MathData | `FC_DL_BcdToByte` / `FC_DL_ByteToBcd` | FC×2 | BCD ↔ BYTE 双向（半字节校验域收敛到 1 字节、非法半字节故障级拦截），补齐 R16 的 WORD/UDINT 位宽缺口 |
| DL_MathData | `FC_DL_SwapBytes64` | FC×1 | 64 位全字节逆序；**拆半区复用 `FC_DL_SwapBytes32`** 再交叉合成（`(LoRev << 32) OR HiRev`），不重实现字节序内核 |
| DL_MathData | `FC_DL_DintToStringTrim` / `FC_DL_LrealToStringTrim` | FC×2 | 整型/浮点字符串化（前导空格修剪 + R37 四步截断样板）；浮点件非有限值映射统一文本 `NaN` / `Inf+` / `Inf-`，信息级不置故障 |
| DL_Base | `FC_DL_LeapYearChk` | FC×1 | 闰年原子（4/100/400 三级判定），供年窗/天数族共用，不做纯算术的重复实现 |
| DL_Base | `FB_DL_SemaMutex` | FB×1 | IEC 标准 SEMA 的防御包装：ENUM+CASE **三态**（eFree/eHeld/eTimedOutRelease）+ ELSE 兜底；超时**强制归还**并置故障级 0369（死锁拦截 ≠ 正常防御）；TON/R_TRIG 三实例本体首部无条件刷新；释放沿优先于申请沿 |

### 修复 / Fixed（R20 终审，MINOR 升版，对外引脚零变更）

- `FC_DL_LrealToStringTrim` v1.0.0→**v1.0.1**（**中等·逻辑**）：无穷幅值判据阈值取 `1.79E308`，该值落在 LREAL 可表域内，`ABS(fIn) >= 1.79E308` 会把 `[1.79E308, 1.7976E308]` 区间的**合法有限值误判为无穷**并输出 `'Inf+'`（带宽约 7.7E305）→ 改为双判据：（a）`(fIn − fIn) <> (fIn − fIn)` 精确判据（有限值 x−x 恒为 0，无穷处产 NaN，与 NaN 自反性判据同源）；（b）幅值兜底阈值提到 LREAL 最大值，残余仅剩「恰为最大值」单值。
- `FB_DL_SemaMutex` v1.0.0→**v1.0.1**（**注释级**）：头注释状态机段「eTimedOutRelease 本拍即回 eFree」易被读成**同拍**回零；实际是超时拍 N 置过渡态、拍 N+1 回 eFree 并恢复受理（过渡态恰占一个扫描拍，其间申请被拒）。逻辑零变更，仅表述精确化——但时序描述错一拍会导致上层按错误延迟做重试节拍设计。

### 说明 / Notes

- **R20 未触及 LGF 台账行**：本轮 20 件全为 T0 快车道零检索件（IEC 标准语义 clean-room 包装），零 LGF/OSCAT/TcOpen 源输入，故 `SOURCE_HUNTING_MATRIX.md` 的 T2-1 / T1-x 各行状态列**不作 ◐→✔ 改动**（那些组仍有在挖项，改 ✔ 即虚账）；R20 登记回写到 T0-2 / T0-5 / T0-6 三行并新增 T0-8 同步/互斥行，裁定留痕见矩阵 `M-E5`。
- `LIBRARY_MANUAL.md` / 三本 Level 1 手册（Device / Motion / Process）本轮按 R19 遗留 P1 补录 **R19 批次 10 件**接口表；三库 R1~R18 历史件接口表仍缺，如实注明「下轮续补」。

---

## [v2.7.0] — 2026-11-16 ｜ R18 场景件第 5 轮 20 件 + R17 码位改判专项收口 / Round 18 — 20 Scenario Components and the Round-17 Code-Point Recast

**阶段**：Phase 1 第十八轮（场景件线，**检索 1 次**）｜ **新增组件**：20（`DL_Base` 4 ｜ `DL_MathData` 4 ｜ `DL_Algo` 4 ｜ `DL_Device` 2 + 接口 1 ｜ `DL_Motion` 3 ｜ `DL_Process` 2，合计 3,709 行）｜ **累计**：**304 / 10,000**（全库约 73,200 行）｜ **子库版本**：`DL_Base` v1.11.0→**v1.12.0**、`DL_MathData` v1.11.0→**v1.12.0**、`DL_Algo` v1.7.0→**v1.8.0**、`DL_Device` v0.9.0→**v0.10.0**、`DL_Motion` v0.9.0→**v0.10.0**、`DL_Process` v0.9.0→**v0.10.0** ｜ **码位**：信息级 `0235`~`0244`、故障级 `0306`~`0314`；**R17 改判专项已执行**：8 码改判至 `022D`~`0234`，5 个存量文件升 v1.0.1 ｜ **终审**：6 件高风险抽检 **命中 3 件缺陷并全部修复**（见下）｜ **红线违规**：0 ｜ **机检**：16 规则 20/20 PASS（4 处 `E_DL_Ne107Status` 跨文件属主按 R70 裁定误报）｜ **JSONL**：**304 条，304/304 字节级 MATCH**（含 2 条 CRLF 遗留记录归一化）｜ **今日入库**：**100 / 200（50%，2026-11-16 开账）**

### 新增 / Added

| 子库 | 组件 | 类型 | 说明 |
|---|---|---|---|
| DL_Base | `FB_DL_EdgeDivider` / `FB_DL_FirstOutLatch` / `FB_DL_PulseStretch` / `FC_DL_BitSegmentBlockMove` | FB×3·FC×1 | 边沿分频、16 路首出锁存、窄脉冲展宽、段表驱动 128 位位段块搬移 |
| DL_MathData | `FC_DL_AffineTransformPoint` / `FC_DL_CpkIndex` / `FC_DL_Crc16Ccitt` / `FC_DL_InterpolateTable2D` | FC×4 | 仿射点变换、Cp/Cpk 实时算、CRC-16 三变体（`29B1`/`31C3`/`2189` 对拍）、8×8 双线性插值 |
| DL_Algo | `FB_DL_BumplessTransfer` / `FB_DL_GainScheduler` / `FB_DL_NotchFilter` / `FB_DL_ThermalI2tModel` | FB×4 | 手自动无扰切换、按工作点增益调度、中心频率+Q 可调陷波、I²t 热容量模型 |
| DL_Device | `I_DL_Gripper` / `FB_DL_ParallelGripper` / `FB_DL_SsrHeaterDrive` | I×1·FB×2 | 夹爪契约（7 属性 + 4 方法）、平行夹爪实现（三段动作）、固态继电器 PWM 加热驱动 |
| DL_Motion | `FB_DL_AxisFollowingErrorMonitor` / `FB_DL_AxisSynchronizedStop` / `FB_DL_BacklashCompensator` | FB×3 | 跟随误差三级判定、减速度斜坡同步停、换向背隙补偿（EWMA 自学习） |
| DL_Process | `FB_DL_ChangeoverSequence` / `FB_DL_DowntimeClassifier` | FB×2 | 五步换产顺控（步内超时重装）、停机原因首动分类 |

### 修复 / Fixed（R18 终审，均为 MINOR 升版，对外引脚零变更）

- `FC_DL_Crc16Ccitt` v1.0.0→**v1.0.1**：`uLen = 0` 时 `FOR ... TO uLenEff - 1` 在 UINT 下回绕成 65535，越界读 `auData[256..65535]` 触发运行时数组越界 → 改空帧短路提前返回 init 值。
- `FB_DL_ChangeoverSequence` v1.0.0→**v1.0.1**：失能闸只清内部 `bReady`、漏清对外镜像 `bReadyForProduction`，引脚残留上一拍 TRUE（安全侧）→ RETURN 前补当拍清零。
- `FB_DL_ParallelGripper` v1.0.0→**v1.0.1**：`METHOD Close` 形参 `fForceSetpoint` 只登记请求、未落力通道，被同名引脚静默覆盖 → 新增方法力锁存，段 4 方法优先、用后即清。
- `FB_DL_BacklashCompensator` v1.0.0→**v1.0.1**：学习率下限常量 `0.001` 与引脚声明域 `0.01~0.5` 不一致 → 对齐为 `0.01`。

### 变更 / Changed

- **R17 改判专项执行完毕**：5 件存量撞车组件错误码改判至 `022D`~`0234`，双向唯一性断言（旧码查重 + 新落点全库复测）留痕，5 文件升 v1.0.1。
- 新红线 R66~R74 入账：属性优先收敛、接口不占码位、禁同上式注释、属性段落留白、唯一属主枚举措放行（PLC 账本 R66~R70）、高风险五类终审抽样、许可类输出双路径显式清零、接口形参必被消费、文档增量纪律（总监账本 R71~R74）。

## [v2.6.0] — 2026-11-16 ｜ R17 T0 纯函数第 4 轮：对数/dB + TIME/TOD + 精度/饱和 + LWORD 64 位域防御包装 20 件 / Round 17: T0 Pure-Function Lane #4 — 20 Defensive Wrappers (Log/dB, TIME/TOD, Precision/Saturation, LWORD 64-bit Fields)

**阶段**：Phase 1 第十七轮（500 冲刺 T0 纯函数线第 4 轮，**零检索**）｜ **新增组件**：20（`DL_MathData` 16 ｜ `DL_Base` 4，+20 → 103 / 59，合计 1,481 行，全部 FC_ 纯函数，输出契约 `eErr/bError/bValid` 三件套）｜ **累计**：**284 / 10,000**（全库约 69,500 行）｜ **子库版本**：`DL_MathData` v1.10.0 → **v1.11.0**，`DL_Base` v1.10.0 → **v1.11.0** ｜ **终审**：**20/20 件级人工独立验算零缺陷 PASS**（LogBaseEx 底数退化闸 + 除子复判双保险；AmpDb/PwrDb 20/10 因子分型与饱和方向；TimeToDintMs 先判后算；DintMsToTime 无上域闸论证（DINT 正域 2147483647 ms < TIME 域 4294967295 ms）留档；LintToDintSat 下界 −DL_DINT_MAX−1 计算式；RealToLintSat/LrealToLintSat 升位比较 + TRUNC 向零；Shl/ShrLwordEx 闸后调用 nN≥64 置零；Rol/RorLwordEx MOD 64 归一 + 零移位直通；LwordToLrealChk 2^53 精度口径）｜ **码位**：信息级 `01E8`~`020F`（40 码，其中 RealToLintSat 预留 0203→**0210**、LrealToLintSat 0204→**0211**/预留 0205→**021B**、ShlLwordEx 0206→**021D**/预留 0207→**021E** 撞车改判）、故障级 `02CA`~`0305`（60 码实测全空闲未动）；**收口实测（新红线 R61：注册表正则实测）发现改判落点仍与存量撞车 7 组**——存量 `FC_DL_DayOfWeekCalc`(0201)/`FB_DL_TimeWindowCheck`(0202)/`FC_DL_TempUnitConvert`(0208)/`FB_DL_EventCounter`(0210)/`FB_DL_ModuloCounter`(0211)/`FB_DL_BitArrayChangeWatch`(021B)/`FB_DL_StringTokenStream`(021D~021E) 与本轮 5 件交叉占用，**按「严重缺陷不静默大改」纪律列明 R18 改判专项方案**（改判落点 0213~0219 + 0220 经实测全空闲），本版暂维持源码现状｜ **红线违规**：0 ｜ **机检**：16 规则 20/20 全 PASS fail=0 ｜ **JSONL**：**284 条**（20 条新增 sha256 全 MATCH）｜ **今日入库**：**98 / 200（2026-11-16 开账）**

### 新增 / Added

#### DL_MathData（16 项，v1.10.0 → v1.11.0，四批归类）

| 批 | 组件 / Component | 类型 | 码位 | 说明 / Description |
|---|---|---|---|---|
| 批1 对数/dB | `FC_DL_LogEx` | FC | `01E8`/`02CA` | 底 10 常用对数，非有限 + fIn≤0 双故障闸，委托内建 LOG |
| 批1 对数/dB | `FC_DL_LogBaseEx` | FC | `01EA`/`02CD` | 任意底数对数（换底公式），底数退化闸（\|fBase−1\|<1E-6）+ 除子复判双保险，委托内建 LN |
| 批1 对数/dB | `FC_DL_AmpDbToRatio` | FC | `01EC`/`02D0` | 幅值型 dB→比（10^(dB/20)），±400 dB 双侧饱和，EXPT 结果复检复用信息码 |
| 批1 对数/dB | `FC_DL_RatioToAmpDb` | FC | `01EE`/`02D3` | 比→幅值型 dB（20·log10），比值≤0 域闸，结果钳 ±400 dB |
| 批1 对数/dB | `FC_DL_PwrDbToRatio` | FC | `01F0`/`02D6` | 功率型 dB→比（10^(dB/10)），硬限 380 dB（10^±38 在 REAL 域可表，400 dB 不可表） |
| 批2 TIME/TOD | `FC_DL_TimeToDintMs` | FC | `01F2`/`01F3` | TIME→DINT ms：TIME 域先与 2147483647 ms 比较（先判后算，禁超限值进内建转换），负结果钳 0 |
| 批2 TIME/TOD | `FC_DL_DintMsToTime` | FC | `01F4` | DINT ms→TIME：负值钳 T#0S；无上域闸（DINT 正域 < TIME 域，论证留档防误加假分支） |
| 批2 TIME/TOD | `FC_DL_TimeToLrealSec` | FC | `01F6` | TIME→LREAL s：观测语义负值照转仅记录，除子 1000.0 编译期恒非零 |
| 批2 TIME/TOD | `FC_DL_LrealSecToTime` | FC | `01F8`/`02E2` | LREAL s→TIME：非有限故障闸 + 负值钳 0 + 上界 4294967.295 s 先判后饱和（先算后判必溢出） |
| 批2 TIME/TOD | `FC_DL_TodToDintMs` | FC | `01FA` | TOD→当日 ms 偏移：标准链 TOD_TO_TIME→TIME_TO_DINT（不自实现时分秒累加），结果钳 0~86399999 ms |
| 批3 精度/饱和 | `FC_DL_DintToRealChk` | FC | `01FC` | DINT→REAL：\|nIn\|>2^24 精度告警（信息级，只告警不钳位），双侧比较禁 ABS 单侧式 |
| 批3 精度/饱和 | `FC_DL_UdintToRealChk` | FC | `01FE` | UDINT→REAL：nIn>2^24 精度告警；无符号负值分支由类型系统结构性排除 |
| 批3 精度/饱和 | `FC_DL_LintToDintSat` | FC | `0200`/`0201` | LINT→DINT 双侧饱和：LINT 域先判后转，下界 −DL_DINT_MAX−1 计算式禁负字面量直写 |
| 批3 精度/饱和 | `FC_DL_RealToLintSat` | FC | `0202`/`02F1` | REAL→LINT：升位先行（REAL 域界不可精确表示）+ TRUNC 向零截断 + 双侧饱和 |
| 批3 精度/饱和 | `FC_DL_LrealToLintSat` | FC | `0211`/`02F4` | LREAL→LINT：与 RealToLintSat 同口径双版本（IEC 无 ANY_REAL 泛型，职责边界留档） |
| 批3 精度/饱和 | `FC_DL_LwordToLrealChk` | FC | `020E` | LWORD→LREAL：nIn>2^53（双精度尾数 53 位）精度告警；无符号位串单侧比较 |

#### DL_Base（4 项，v1.10.0 → v1.11.0）

| 批 | 组件 / Component | 类型 | 码位 | 说明 / Description |
|---|---|---|---|---|
| 批4 LWORD 位域 | `FC_DL_ShlLwordEx` | FC | `021D` | LWORD 左移：nN ≥ 64 常量路径置全零不调内建（64 位口径同源 R14 32 位 ShlEx） |
| 批4 LWORD 位域 | `FC_DL_ShrLwordEx` | FC | `0208` | LWORD 逻辑右移：nN ≥ 64 常量路径置全零；无符号位串不做符号位扩展 |
| 批4 LWORD 位域 | `FC_DL_RolLwordEx` | FC | `020A` | LWORD 循环左移：nN ≥ 64 按 MOD 64 归一（与移位件「置零」口径刻意相反），归一后 0 直通不调内建 |
| 批4 LWORD 位域 | `FC_DL_RorLwordEx` | FC | `020C` | LWORD 循环右移：MOD 64 归一同口径，零移位直通 |

### 收口事件 / Closeout Events

- **码位游标教训立规（R61）**：派单规划声称「存量信息级已用至 02C9、01E8~020F 空闲」经注册表正则实测不实——存量 DL_Base/DL_MathData 分散占用 `0203`~`0207`、`0212`~`021A`、`021C`、`021F` 等；本轮 5 件撞车改判（0210/0211/021B/021D/021E）。收口全库正则复测进一步发现改判落点与另七组存量件交叉占用（详见上「码位」栏），按严重缺陷纪律列明 R18 改判专项方案，不静默大改。**教训：码位游标必须以注册表正则实测为准，不得沿用上一轮战报口头交接值。**
- R18 改判专项方案（实测落点全空闲，待 R18 执行）：LintToDintSat `0201→0220`、RealToLintSat `0202→0215`/预留 `0210→0216`、ShrLwordEx `0208→0219`、LrealToLintSat `0211→0213`/预留 `021B→0214`、ShlLwordEx `021D→0217`/预留 `021E→0218`；改判后新件信息级起点 `0221`、故障级起点 `0306`。

---

## [v2.5.0] — 2026-11-16 ｜ R16 T0 变体线开线：饱和转换 + 整数/BCD 校验 + 泛型选择 + LIMIT/TIME 算术防御包装 20 件 / Round 16: T0 Variant Lane — 20 Defensive Wrappers (Saturating Conversions, Integer/BCD Checks, Generic Select & LIMIT/TIME Arithmetic)

**阶段**：Phase 1 第十六轮（500 冲刺 T0 变体线开线，**零检索**）｜ **新增组件**：20（全部落 `DL_MathData`，+20 → 87，合计 1,436 行，全部 FC_ 纯函数，输出契约 `eErr/bError/bValid` 三件套）｜ **累计**：**264 / 10,000**（全库约 68,000 行）｜ **子库版本**：`DL_MathData` v1.9.0 → **v1.10.0** ｜ **终审**：**抽查 8 件高风险件人工逻辑复核零缺陷 PASS**（TimeAddSat 减法预判先判后算、TimeDivChk INT 最小值升位取负、SelEx 未选中通道不影响本拍、BcdToUdint 校验域 k=0..7 收敛、UdintToBcd 99999999 饱和口径、LintToLrealChk 双侧比较规避 ABS 回绕）｜ **码位**：信息级 `01C0`~`01E7`（40 码）、故障级 `028E`~`02C9`（60 码），按源码反算回写 code_segment，全库唯一无重复 ｜ **红线违规**：0 ｜ **机检**：16 规则全 PASS fail=0 ｜ **JSONL**：**264 条**（20 条新增 sha256 全 MATCH）｜ **今日入库**：**78 / 200（39.0%，2026-11-16 开账）**
**Release**: T0 variant lane opened (zero retrieval) — 20 FC pure-function defensive wrappers in DL_MathData with the eErr/bError/bValid output contract across four families (saturating conversions, integer/BCD checks, generic selection, LIMIT/TIME arithmetic); diag codes 01C0–01E7 (info) & 028E–02C9 (fault) back-calculated from source and globally unique; 8-file high-risk audit PASS with zero defects.

### 新增 / Added

#### DL_MathData（20 项，v1.9.0 → v1.10.0，四族归类）

| 族 / Family | 组件 / Component | 类型 | 码位 | 说明 / Description |
|---|---|---|---|---|
| 饱和转换（批1） | `FC_DL_LrealToRealSat` | FC | `01C0`/`028E` | LREAL→REAL 双侧饱和钳位 ±3.402823E38，非有限故障闸 / dual-side saturating LREAL→REAL |
| 饱和转换（批1） | `FC_DL_LrealToDintSat` | FC | `01C2`/`0291` | LREAL→DINT 域判定先行 + TRUNC 向零截断 / domain-first clamp then trunc |
| 饱和转换（批1） | `FC_DL_RealToUdintSat` | FC | `01C4`/`01C5`/`0294` | REAL→UDINT 负值钳零 + 超上界钳 16#FFFFFFFF / negative clamps to zero |
| 饱和转换（批1） | `FC_DL_RealToUintSat` | FC | `01C6`/`01C7`/`0297` | REAL→UINT 双侧饱和（R56 双分支范式）/ dual-side saturating REAL→UINT |
| 饱和转换（批1） | `FC_DL_RealToByteSat` | FC | `01C8`/`01C9`/`029A` | REAL→BYTE 双侧饱和（串口/PWM 字节域）/ dual-side saturating REAL→BYTE |
| 整数+BCD（批2） | `FC_DL_DintToUintSat` | FC | `01CA`/`01CB` | DINT→UINT 双侧饱和钳位 / dual-side saturating DINT→UINT |
| 整数+BCD（批2） | `FC_DL_UdintToDintChk` | FC | `01CC` | UDINT→DINT 上界单侧饱和 2147483647 / upper-bound clamp UDINT→DINT |
| 整数+BCD（批2） | `FC_DL_LintToLrealChk` | FC | `01CE` | LINT→LREAL 超 2^53 精度告警（双侧比较规避 ABS 回绕，R55）/ 53-bit precision notice |
| 整数+BCD（批2） | `FC_DL_BcdToUdint` | FC | `02A6` | 8 位 BCD→UDINT 逐半字节校验（k=0..7 收敛，R57）/ per-nibble validated BCD decode |
| 整数+BCD（批2） | `FC_DL_UdintToBcd` | FC | `01D2` | UDINT→BCD 超 99999999 饱和至 16#99999999（与 R9 WordToBcd 口径一致）/ saturating BCD encode |
| 泛型选择（批3） | `FC_DL_SelEx` | FC | `01D4`/`02AC` | 双通道选择：未选中通道异常仅记录不影响本拍 / SEL with idle-channel advisory |
| 泛型选择（批3） | `FC_DL_Mux2Ex` | FC | `01D6`/`02AF` | MUX2：选择子越界钳 1 + 选中通道非有限故障闸 / MUX2 with clamped selector |
| 泛型选择（批3） | `FC_DL_Mux4Ex` | FC | `01D8`/`02B2` | MUX4：IF/ELSIF 链实现 MUX 语义 + 越界钳 3 / MUX4 via IF/ELSIF chain |
| 泛型选择（批3） | `FC_DL_MinEx` | FC | `02B5` | MIN 防御包装：非有限输入故障闸 / defensive MIN |
| 泛型选择（批3） | `FC_DL_MaxEx` | FC | `02B8` | MAX 防御包装：非有限输入故障闸 / defensive MAX |
| LIMIT+TIME（批4） | `FC_DL_LimitEx` | FC | `01DE`/`02BB` | LIMIT 防御包装：上下限倒置自动交换 + 非有限闸 / LIMIT with auto-swap |
| LIMIT+TIME（批4） | `FC_DL_TimeAddSat` | FC | `01E0` | TIME 加法减法比较溢出预判饱和 DL_TIME_MAX（R54）/ add with subtract-compare pre-check |
| LIMIT+TIME（批4） | `FC_DL_TimeSubSat` | FC | `01E2` | TIME 减法负差钳零（无符号语义防御）/ subtract with clamp-to-zero |
| LIMIT+TIME（批4） | `FC_DL_TimeScaleSat` | FC | `01E4`/`01E5` | TIME 乘法除法比较溢出预判 + 负乘子钳零 / multiply with divide-compare pre-check |
| LIMIT+TIME（批4） | `FC_DL_TimeDivChk` | FC | `01E6`/`02C7` | TIME 除法除零故障闸 + 负除子 DINT 升位取模长 / divide with zero guard |

---

## [v2.4.0] — 2026-11-16 ｜ R15 T0 七组收口：标准函数包装族 20 件（**补记**，R16 收尾发现本条目漏更后追加）
**Release**: Round 15 closure (retroactively recorded) — 20 T0 standard-function wrappers (ABS/SIN/COS/ASIN/ACOS/ATAN/ATAN2/EXP/EXPT/TRUNC/FLOOR/CEIL + 8 string factories) closing all seven T0 matrix groups (7/7 ✔); DL_Base v1.9.0, DL_MathData v1.9.0, library 244 components / 66,644 lines; codes 015E–01BD (info) & 024B–028B (fault); final review PASS with zero fixes; paradigms R50–R53 registered. 详细组件清单见 `DL_Base/VERSION.md` v1.9.0 与 `DL_MathData/VERSION.md` v1.9.0 既有条目，本补记不重列。

---

## [v2.3.0] — 2026-11-16 ｜ R14 T0 快车道：IEC 标准件防御性包装 20 件 / Round 14: T0 Fast Lane — 20 Defensive Wrappers of IEC Standard Blocks

**阶段**：Phase 1 第十四轮（500 冲刺 T0 快车道，**零检索**）｜ **新增组件**：20（`DL_Base` +15 → 55 ｜ `DL_MathData` +5 → 47）｜ **累计**：**224 / 10,000**（全库 64,678 行）｜ **子库版本**：`DL_Base` v1.9.0 → **v1.10.0** ｜ `DL_MathData` v1.7.0 → **v1.8.0** ｜ **终审**：**20/20 PASS**（提示级 3 处留档不改码：TanEx 结果复检条件冗余、StringMidEx 255 截断闸为纵深防御死代码、诊断字 UDINT 对规划 WORD 建议的系统性偏离已按「类型裁定」节留档）｜ **码位**：信息级 `014D`~`015D`、故障级 `0226`~`022B`，全库唯一无冲突（脚本求差断言）｜ **红线违规**：0 ｜ **机检**：12 项 fail=0 ｜ **JSONL**：**224 条**（sha256 全 MATCH）｜ **今日入库**：**20 / 200（10.0%，2026-11-16 开账）**
**Release**: T0 fast lane (zero external retrieval) — 20 defensive wrappers delegating to built-in IEC kernels (SQRT/LN/TAN/ROUND/MID/TON/TOF/TP/SHL/SHR/R_TRIG), domain-gate-first + non-finite recheck four-stage template; diag codes 014D–015D (info) & 0226–022B (fault) globally unique; final review 20/20 PASS with 3 advisory notes retained.

### 新增 / Added

#### DL_Base（15 项，v1.9.0 → v1.10.0，T0-1/2/3/7 四组收口）

| 组件 / Component | 类型 | 码位 | 说明 / Description |
|---|---|---|---|
| `FB_DL_SRBistable` | FB | `014D` | SR 置位优先双稳态：S1/R 同拍仲裁显式化 + 诊断码 / SR bistable, set-dominant arbitration diag |
| `FB_DL_RSBistable` | FB | `014E` | RS 复位优先双稳态：S/R1 同拍仲裁显式化 / RS bistable, reset-dominant |
| `FB_DL_RTrigEx` | FB | —（无码位） | 上升沿包装：首扫不假触发、单拍输出 / Rising-edge wrapper, no first-scan false edge |
| `FB_DL_FTrigEx` | FB | —（无码位） | 下降沿包装：首扫不假触发 / Falling-edge wrapper |
| `FB_DL_TonEx` | FB | `014F` | TON 包装：PT 负钳 0、跨段语义统一，委托内建 TON |
| `FB_DL_TofEx` | FB | `0150` | TOF 包装：首扫零假触发，委托内建 TOF |
| `FB_DL_TpEx` | FB | `0151` | TP 包装：不可重触发语义显式化，委托内建 TP |
| `FB_DL_RtoEx` | FB | `0152` | 保持型定时器：复位>使能优先链、末拍快照冻结累加（R46 范式） |
| `FB_DL_CtuEx` | FB | `0153` | CTU 包装：PV 负钳 0、上溢饱和不回绕 |
| `FB_DL_CtdEx` | FB | `0154` | CTD 包装：下溢饱和不回绕 |
| `FB_DL_CtudEx` | FB | `0155`/`0226` | 双向计数：净额抵消法（R47）+ 双向饱和锁定故障码 |
| `FC_DL_ShlEx` | FC | `0156` | SHL 包装：n ≥ 32 常量路径置 0，不调内建 |
| `FC_DL_ShrEx` | FC | `0157` | SHR 包装：同上 |
| `FC_DL_RolEx` | FC | `0158` | ROL 包装：MOD 32 归一 + SHL/SHR 位合成（R48 范式） |
| `FC_DL_RorEx` | FC | `0159` | ROR 包装：同上 |

#### DL_MathData（5 项，v1.7.0 → v1.8.0，T0-4/5/6 组开收）

| 组件 / Component | 类型 | 码位 | 说明 / Description |
|---|---|---|---|
| `FC_DL_SqrtEx` | FC | `015A`/`0227` | 负数/非有限域闸门先行，域内委托内建 SQRT |
| `FC_DL_LnEx` | FC | `0228`/`0229` | fX ≤ 0 拦截（含 0 趋 −Inf），委托内建 LN |
| `FC_DL_TanEx` | FC | `022A` | π/2 极点容差闸（\|cos\|<1E-12）+ 幅值 1E6 双保险，委托内建 TAN |
| `FC_DL_RoundSat` | FC | `015B`/`022B` | DINT 域外钳位饱和不回绕、半值远离零取向，委托内建 ROUND |
| `FC_DL_StringMidEx` | FC | `015C`/`015D` | 起点/长度钳位 + 255 上限先置截断标志再钳长（R49 范式），委托内建 MID |

---

## [v2.2.0] — 2026-11-16 ｜ R13 NE107 设备健康族 + 电表契约/实现 + 三件现场诊断 + 工艺四件 + 位串旋转/掩码比较 + CRC-8/严格解析/矩阵求逆 + 污垢趋势 + 被动回零 / Round 13: NE107 Device-Health Family, Power-Meter Contract & Implementation, Field Diagnostics Trio, Process Quartet, Bit Rotation & Mask Compare, CRC-8 & Strict Parsing & Matrix Inverse, Fouling Trend, Passive Homing

**阶段**：Phase 1 第十三轮批处理（R13）｜ **新增组件**：18（合计 7,966 行）｜ **累计**：**204 / 10,000**（全库 62,667 行）｜ **子库版本**：`DL_Base` v1.8.0 → **v1.9.0** ｜ `DL_MathData` v1.6.0 → **v1.7.0** ｜ `DL_Algo` v1.6.0 → **v1.7.0** ｜ `DL_Device` v0.8.0 → **v0.9.0** ｜ `DL_Motion` v0.8.0 → **v0.9.0** ｜ `DL_Process` v0.8.0 → **v0.9.0** ｜ **终审**：**18/18 PASS**（确定缺陷 14 处全部修复：严重/功能失效级 2 / 中等 9 / 提示 3 / 文档级 1）｜ **升版**：**10 件升 v1.0.1**（8 新件 + 2 存量 R39 修复）｜ **R39 存量专案**：真缺陷 2 件已修，残余 **3 FAIL + 2 WARN 逐件推演裁定误报**留档不修 ｜ **红线违规**：0 ｜ **JSONL 语料**：**204 条** ｜ **今日入库**：**18 / 200（9.0%，2026-11-16 开账）｜ 累计 204**
**Release**: Phase 1 Round 13 — 18 components (7,966 lines), library total 204 / 62,667 lines; final review 18/18 PASS (14 defects all fixed: 2 severe/functional-loss, 9 medium, 3 advisory, 1 documentation); 10 files bumped to v1.0.1 (8 new + 2 legacy R39 fixes); legacy R39 campaign fixed 2 real defects and adjudicated 3 FAIL + 2 WARN machine-check residuals as false positives retained with rationale.

### 新增 / Added

#### DL_Base（2 项，子库 v1.8.0 → v1.9.0，位段族三件套收口 / Bit-family completion）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FC_DL_BitArrayRotate` | FC | `0001_013D`~`013E`、`021F` | 跨字位串整体循环旋转：1~4 个 `DWORD` 视为 32~128 位位串，左移或右移 n 位、移出位回卷对端，位序总量守恒；与 `BitArrayExtract`（「抽」）/ `BitArrayInsert`（「插」）构成位段族三件套；移位量先取绝对值再对总宽取模，永不做超宽移位；结果先落暂存区再整体写回，源与目标同址（别名）安全；整圈也报归约信息码 `013D` / Cross-word bit-string rotation with alias-safe staging |
| `FC_DL_MaskCompare` | FC | `0001_013F`~`0140`、`0220` | 状态字掩码比较与差异定位：判「值按掩码比较是否等于期望」，同出差异位图、差异位数与**首个差异位号**，报警直接定位到具体那一位；掩码 0 位为 don't-care 不参与比较；位宽 32 走满一常量分支禁 `SHL(x, 32)`；掩码为 0 恒匹配但置 `0140` 提示 / Mask compare with difference bitmap and first differing bit |

#### DL_MathData（4 项，子库 v1.6.0 → v1.7.0，CRC-8 / 严格解析 / 定宽字段 / 矩阵求逆）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FC_DL_Crc8` | FC | `0001_0141`~`0142`、`0221` | 参数化 MSB-first CRC-8 逐位算法：ATM / SAE-J1850 / HITAG 三变体，无查表、无状态、内存占用恒定，补齐 CRC 族 8 位宽度；变体非法回退 ATM 并置 `0142`；`"123456789"` 实算 `F4/4B/B4` 与公开 CRC 目录三方一致 / Parameterised bitwise CRC-8 with three variants |
| `FC_DL_StringToLReal` | FC | `0001_0143`~`0146`、`0222`~`0223` | 定长 ASCII 严格解析成 LREAL：逐字符七态状态机，拒绝一切可疑输入并报出**首个非法字符的位置**；不调用平台隐式串转数值，三平台行为完全一致；前缀合法、尾部夹脏仍给前缀值（便于判断报文截断还是字段串位）；指数超 ±38 保护域落有限上界 / Strict ASCII-to-LREAL parsing reporting first bad character |
| `FC_DL_StringFixedField` | FC | `0001_0147`~`0149`、`0224` | 定宽字段装填（左/右对齐 + 指定填充字符）：范式 **R37「截断必须显式置位」**的可复制样板——先取源长度 → 与目标宽度比较 → 先置截断标志与码 → 最后才写缓冲；超宽且不允许截断则拒绝构造留痕；填充串为空退回空格 / Fixed-width field packing as the R37 template |
| `FC_DL_Matrix3Inverse` | FC | `0001_014A`~`014C`、`0225` | **v1.0.1** —— 3×3 实数矩阵伴随法解析求逆：九元素行主序传入，全过程定长表达式（无主元选取、无嵌套循环），同一输入每一步中间量可复算；相对奇异判据（默认 1.0E-9）+ 出口夹域，失败逆矩阵整体置 0 绝不输出非数；v1.0.1 修正头注释 V7 条件数粗估数值（1.0E-18 → 实算 1.0E-6，判定结论不受影响） / Analytic 3x3 inverse with relative singularity gate |

#### DL_Algo（1 项，子库 v1.6.0 → v1.7.0，换热器退化底座）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_FoulingResistanceEstimator` | FB | `0002_2201`~`2204`、`2210`~`2212` | 换热器污垢热阻趋势底座：由热/冷侧进出口温度与体积流量算换热量 Q（量纲链复核至 kW）、对数平均温差 LMTD 与实测传热系数 K，再按 Rf = 1/K − 1/K_clean 反算污垢热阻；趋势窗内最小二乘拟合 Rf 增长斜率并给清洗建议；**只算值给建议、不做控制**——不做 PID、不动阀门泵、不内置几何与物性库，`fCp`/`fRho`/`K_clean` 由调用方按设备台账注入；LMTD ≤ 0（温度交叉或流型用错）置 `2211` 拒算 / Heat-exchanger fouling resistance estimator with least-squares trend |

#### DL_Device（6 项，子库 v0.8.0 → v0.9.0，NE107 诊断族开族）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `I_DL_DeviceHealth` | 接口 | —（契约件，无码位） | NE107 设备健康语言契约：①我现在健康吗（NE107 四态 + 功能检查 + 未知 = 六态）；②我的证据是什么（诊断码 + 证据来源槽号）；③这个状态持续多久了（当前态时长 + 锁存位）；**只定义提问方式、不定义判据**（判据留给实现者），不定义视觉呈现；同时承载 `E_DL_Ne107Status` 枚举定义，全库唯一属主，其余实现块禁止复制枚举体 / NE107 device-health language contract, sole owner of the status enum |
| `I_DL_PowerMeter` | 接口 | —（契约件，无码位） | 三相电表读侧契约：电量（电压/电流/功率/功率因数/频率）、电能质量、累计电能（正反向）、需量峰值与健康出口；上层能耗看板、需量控制、电能质量监视只需持有本接口引用，即可适配 Modbus / PROFIBUS / 脉冲 / 虚拟四类实现 / Three-phase power-meter read-side contract |
| `FB_DL_ModbusPowerMeter` | FB | `0003_0156`~`015B`、`0316`~`031B` | **v1.0.1** —— `I_DL_PowerMeter` 的 Modbus 表实现（IMPLEMENTS）：三相原始值换算 + 32 位电能四字拼装（先判单调性，回退判换表重载基准并置 `0318` 维护码——**裁定不置 `bError`**）+ 功率因数复算交叉校验（偏差 > 3% 降级）+ 轻载抑制 + 15 min 需量窗 + NE107 六态健康出口；v1.0.1 补 `_bPfMismatch` 每拍预清零（R34/R44，一次越差永久降级）与声明区枚举比较基准（机检 FAIL×2） / Modbus power-meter implementation with PF cross-check and NE107 exit |
| `FB_DL_ValveStictionDetect` | FB | `0003_015C`~`015E`、`031D`~`031F` | **v1.0.1** —— 阀门黏滞在线诊断：OP/PV 反转点同指令差分的滞环估计，累积成黏滞带估计值，给出四档严重度与停滞/反转事件统计；三判据并发升级——黏滞带定档，但 Moderate 及以上必须另有停滞或反转证据佐证（缺一不升级）；重建窗首窗不发布、保持上次等级 / Valve stiction diagnosis with concurrent-evidence severity escalation |
| `FB_DL_AhuDamperStuckDiag` | FB | `0003_0160`~`0161`、`0321`~`0325` | **v1.0.1** —— AHU 风阀三分类失效诊断：`eFullStall`（一步未动）/ `eTransitStall`（动了但没到）/ `eIoFault`（信号不可信）三类判据各带独立确认窗，另带 `eDeviation` / `eSlow` 两个工艺级；把「要停机」与「要排计划」分开报告；`0323` 稳态偏差为维护语义**裁定不置 `bError`**（仍能调节 ≠ 不可运行）；v1.0.1 修复判定相绕开 `tIoFaultTime` 确认窗直接锁存 `0324` / AHU damper three-class stuck diagnosis with per-class confirm windows |
| `FB_DL_PumpCavitationGuard` | FB | `0003_0164`~`0165`、`0326`~`0329` | **v1.0.1** —— 离心泵汽蚀三判据守卫：流量偏低 + 扬程跌落 +（振动超限或电流波动超限）同拍成立并持续 `tConfirm` 才确认；单判据只到嫌疑（`0164`，不锁存）；确认后只输出 `fDerateRatio` / `bDerateRequest`，**不写变频器频率**——每次确认降一步（默认 −0.10）、下限 0.3、不自动回升；v1.0.1 修复额定值非正时兜底值污染判据门输出伪比值（V5 违例）、`bError=TRUE` 而 `uErrorId=0` 自相矛盾（R21）、抑制窗「窗满」误当「窗内」 / Pump cavitation guard with derate request only, never writing drive frequency |

#### DL_Motion（1 项，子库 v0.8.0 → v0.9.0）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_PassiveHomingMonitor` | FB | `0004_01C3`~`01C6`、`02D2`~`02D4` | **v1.0.1** —— 被动回零旁路监听：轴被**外力**移动（手摇轮、另一驱动拖动、重力下落、维护推车）时的参考点确认——旁路监听参考事件，按「方向一致性 + 速度窗 + 多次位置一致性」三判据确认，输出建议偏移交上层按 `MC_SetPosition` 语义消费；**不发运动指令、不自造轴状态、不定义轴状态枚举**；v1.0.1 修复事件受理未排除本拍故障与掉使能，脏值可穿透至 `bReferenced` 保持位 / Passive homing monitor confirming the reference while the axis is moved by external force |

#### DL_Process（4 项，子库 v0.8.0 → v0.9.0，工艺四件）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_CapperTorqueTrend` | FB | `0005_01C5`~`01C7`、`02F3`~`02F5` | **v1.0.1** —— 旋盖扭矩曲线特征 + 五类 NG 判别：峰值 / 上升斜率 / 稳态段均值 / 面积比四特征，低扭 / 高扭 / 滑牙 / 歪盖 / 曲线异常五类，NG 原因位图可多位并置；主判定单一出口，优先级按安全/功能严重度降序（**滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常**）；分位阈值由引脚注入不内联统计；v1.0.1 修复评估相检出非有限样本仍无条件转判定相，故障锁存语义失效 / Capper torque feature extraction with five-class NG verdicts |
| `FB_DL_EscHeLeakCheck` | FB | `0005_01C8`~`01CA`、`02F6`~`02F8` | **v1.0.1** —— 静电吸盘（ESC）氦背冷泄漏率三段式判定：升压段（斜率监视 + 达压确认）→ 稳压段（窗内极差稳定判据，**可延长一次但延长窗全程计时**）→ 测量段（压降率 → 漏率换算 + 温漂修正）→ OK / Warn / NG 三级；v1.0.1 修复稳压延长窗裁决条件致主稳压 TON 恒真、延长窗全程未计时，`01C8` 名存实亡（本轮最重缺陷，R40 家族） / ESC helium leak check with one-shot stabilise extension that actually times |
| `FB_DL_ChamberSeasoningTrack` | FB | `0005_01CB`~`01CE`、`02F9`~`02FB` | 腔体 seasoning 台账与放行判定：每片完成后累计片数、累计工艺时长、膜厚均值与趋势；**双判据（片数达标 ∧ 时长达标）**才放行；连续越窗自动降级 `eNotReady`；配方名只作标签与校验键，超 32 字符显式截断置 `01CE`；台账溢出守卫 `02FA` / Chamber seasoning ledger with dual-criteria release |
| `FB_DL_ReactorJacketDeltaT` | FB | `0005_01CF`~`01D1`、`02FC`~`02FE` | 放热反应釜温-夹套温差约束：以 ΔT = 釜温 − 夹套温为约束量，升温侧做**温差上限 + 温差变化率**双约束，并把上层 PID 输出分程为冷/热两路阀位给定（分程带死区防冷热同开）；温差触限带 0.5 K 回差锁存、经 `FB_DL_RateLimiter` 限速斜坡回 0（限速非限幅）；超温强制冷却带回差；传感器反装（温差为负且要求升温）置 `02FD` / Reactor jacket delta-T constraint with split-range heating/cooling |

### 修复 / Fixed

#### 本轮终审缺陷（14 处全部修复，8 新件 + 2 存量升 v1.0.1）

| # | 组件 / Component | 级别 | 缺陷 / Defect | 处置 / Action |
|---|---|---|---|---|
| C4-1 | `FB_DL_EscHeLeakCheck` | **中高（功能失效）** | 稳压延长窗裁决条件为「主稳压 Q **或** 延长 TON Q」：延长置位后主稳压定时器 IN 未断、Q 保持 TRUE，下一拍即落入「延长后仍不稳」提前进测量——`_fbTonStabExt` 全程未计时，`01C8` 名存实亡，测量起点取在延长窗开始而非结束时刻 | ✅ 以 `_bStabExtended` 区分两窗，延长窗内仅由延长 TON 裁决；收敛路径显式清弱稳定标志（R40 家族） |
| 存-1 | `FB_DL_InterlockMatrix`（R39 存量） | **严重（功能失效）** | 段 8 未使能覆盖把 `eStateInt` 无条件改写为 `eDisabled`，而 `eLatched` / `eFault` 两态的复位沿消化在其后 CASE 分支内——禁用期间按下的复位沿被整拍吞掉，首因锁存需二次复位才清除 | ✅ 两个持有复位沿的状态不被禁用覆盖，其余态行为不变；引脚契约与码位零变化（R39） |
| A6-2 | `FB_DL_PumpCavitationGuard` | 中等（V5 直接违例） | 额定流量/扬程非正时兜底值 1.0 污染判据门（`_fFlowNomUse > EPS` 恒真），输出 `fFlow/1.0` 的**伪比值**而非 0；扬程同病 | ✅ 比值门改用原始额定值判界，兜底值只保留为除零守卫 |
| A5-1 | `FB_DL_AhuDamperStuckDiag` | 中等 | 判定相 `IF NOT _bFbOk` 绕开 `tIoFaultTime` 确认窗直接锁存 `0324`——三分类「判据须带确认延时」缺口 | ✅ 改为确认窗计时满才定性，未满窗保持上次值不发布结论 |
| C3-1 | `FB_DL_CapperTorqueTrend` | 中等 | 评估相检出非有限样本（`02F4`）置故障条件，但评估相出口无条件转判定相——下一启动沿可绕过复位直接开新周期，故障态锁存语义失效 | ✅ 出口按故障条件分流，故障转 `eFault` 等复位 |
| C2-1 | `FB_DL_PassiveHomingMonitor` | 中等（坏值穿透） | 事件受理未排除本拍故障条件与掉使能：非有限值检出置零的同一拍，参考事件沿仍可采信零化快照，极端情形把 0.0 锁进参考保持位 | ✅ 受理条件补串「使能且无故障条件」 |
| A3-1 | `FB_DL_ModbusPowerMeter` | 中等（R34/R44） | `_bPfMismatch` 全文只有 `:= TRUE` 无清零点，一次 `015A` 越差即永久 `eDegraded`、`eDegraded→eSampling` 不可达 | ✅ 段 1 增每拍预清零（R34 状态量生命周期 + R44 按窗清码） |
| A6-3 | `FB_DL_PumpCavitationGuard` | 中等（R21） | 汽蚀确认置 `bError=TRUE` 但 `uErrorId` 恒 0（`0326` 从未写入首出码寄存器），自相矛盾 | ✅ 确认分支写 `0326` 入首出码（不覆盖更高优先级的 `0327`/`0328`） |
| A6-1 | `FB_DL_PumpCavitationGuard` | 中等 | 抑制窗标志取「窗满那一拍」而非整个降速相——`0165` 仅一瞬可见、窗内四条判据实际仍在计算 | ✅ 改为「降速相或窗满」全程抑制 |
| 存-2 | `FB_DL_AgvDockingHandshake`（R39 存量） | 中等 | 禁用期前置改写致 `eState` 报 `eIdle` 而 `bError=TRUE` 自相矛盾，故障态出口不可达 | ✅ 故障态不被禁用覆盖（R39）；引脚契约零变化 |
| A3-2 | `FB_DL_ModbusPowerMeter` | 中等（机检 FAIL×2） | 语句段直写裸枚举类型名 `E_DL_ByteOrder.eAbcd/.eCdab`，子集机检 `undefined_identifier` FAIL，且与库内比较基准范式不一致 | ✅ 新增声明区比较基准，零语义变化机检转 PASS |
| A4-1/A6-4/A6-5 | `FB_DL_ValveStictionDetect` / `FB_DL_PumpCavitationGuard` | 提示 ×3 | 裸时间字面量 `T#24H`；急停级 `0327` 不受停泵抑制（邻近设备振动可误锁存）；停泵不清波动率 `_fRipple` 跨停机存活 | ✅ 三处均已修（字面量入常量、判据门补停泵抑制、停泵清 `_fRipple`） |
| B6-1 | `FC_DL_Matrix3Inverse` | 文档级 | 头注释验收向量 V7 条件数粗估写 1.0E-18，实算 1.0E-6（编码者误把阈值记成粗估）；判定结论不受影响 | ✅ 头注释数值勘误，升 v1.0.1 |

> **缺陷口径**：确定缺陷 **14 处全部修复**（严重/功能失效级 2 ｜ 中等 9 ｜ 提示 3 ｜ 文档级 1）；升版 **10 件 v1.0.1**（`FB_DL_ModbusPowerMeter`、`FB_DL_ValveStictionDetect`、`FB_DL_AhuDamperStuckDiag`、`FB_DL_PumpCavitationGuard`、`FB_DL_PassiveHomingMonitor`、`FB_DL_CapperTorqueTrend`、`FB_DL_EscHeLeakCheck`、`FC_DL_Matrix3Inverse` 8 新件 + `FB_DL_InterlockMatrix`、`FB_DL_AgvDockingHandshake` 2 存量）。最重的两处——延长窗失能与禁用期吞复位沿——同属「文本全绿、语义全错」家族，机检与逐条推演均未在修复前拦下，**再次印证机检不等于编译、也不等于语义正确**。

#### R39 存量专案裁定（真缺陷 2 件已修 ｜ 残余误报逐件推演留档不修）

| # | 文件 | 机检 | 裁定 | 升版 |
|---|---|---|---|---|
| 1 | `DL_Base/FB_DL_InterlockMatrix.st` | FAIL | **真缺陷，已修**（禁用期吞复位沿，见上表 存-1） | 1.0.0 → **1.0.1** |
| 2 | `DL_Process/FB_DL_AgvDockingHandshake.st` | FAIL | **真缺陷，已修**（矛盾态，见上表 存-2） | 1.0.0 → **1.0.1** |
| 3 | `DL_Algo/FB_DL_Integrator.st` | FAIL | **误报，不修**——复位判据在文本与执行序上都先于前置改写，属合法写法（规则缺少「状态量不参与任何复位判据」的豁免形态） | 否（已 1.0.1） |
| 4 | `DL_Algo/FB_DL_PidController.st` | FAIL | **误报，不修**——同上，复位已提到前面，属误报抑制第 2 条同类合法写法 | 否（已 1.0.1） |
| 5 | `DL_Device/FB_DL_PulseDirStepper.st` | FAIL | **误报，不修**——复位判据在 CASE 之外且先执行，真正会吞复位的形态（复位判据放进 CASE 分支、前置分支改写状态）并不存在 | 否（已 1.0.1） |

> 另 2 处 WARN（`FB_DL_PortDiagBoard` 首扫块上电置安全态、`FB_DL_AxisVelocityMove`）同批裁定误报留档。**未采用任何仅为让机检变绿的写法改动**；全库 r39 终值 `files=204 fail=3 warn=2`，残余均为裁定留档误报。

### 变更 / Changed

- **`DL_Device` 故障码上界由 `0315` 提至 `0329`**：本批占用 `0156`~`0165`（信息级）与 `0316`~`0329`（故障级）；其中 **`0318`（换表回退）与 `0323`（稳态偏差）虽落在 `03xx` 故障子块内，语义为维护级提示码（裁定不置 `bError`）**——`VERSION.md` 与 `MANUAL_DL_Device.md` 故障码表新增「是否置 bError」专列，HMI 码表按级别着色而非按号段着色。
- **三个新子族开族**：`DL_Device` **NE107 诊断族**（契约-契约-实现对三层：健康语言 + 电表读侧 + Modbus 实现）、`DL_MathData` **LGF CRC8 子族**（CRC 族补齐 8 位宽度）与 **LGF Matrix 子族**（3×3 解析求逆）；`DL_Base` 位段族收口为「抽 / 插 / 旋」三件套。
- **静态机检升级为 16 条规则**并完成**全库 204 件回归**（`audit_library_r13.py`，各泳道修复后 `fail=0 warn=0`）；R39 规则残余 5 处命中经人工逐件推演裁定为误报（见上节），并登记规则改进项：排除项判据应扩到 `THEN` 之前整段（多行条件漏读）。
- **编译验证连续 14 轮悬置，本轮起在文档显著声明**：`README.md` 头部与 `LIBRARY_MANUAL.md` 第十五节新增「⚠️ 未经编译器验证 / NOT COMPILER-VERIFIED」提示与替代验证方案（16 项静态机检全库回归 + 总监独立验算向量 + 人工时序推演双签 + IF/END_IF 配平）及无法替代的风险清单；**生产导入前必须先在目标平台空工程做一次全量编译**。
- **文档线同步范围**：6 份子库 `VERSION.md`（版本号、组件数、码位台账、R39 存量修复记录）、6 份手册（新增组件中英双语接口表 + 可编译调用示例 + 边界行为 + 故障码表；`FB_DL_InterlockMatrix` / `FB_DL_AgvDockingHandshake` 补 v1.0.1 修订记录）、`README.md`（徽章 204 / 10,000、目录计数、Round 13 摘要、明星组件索引、v2.2.0 亮点、⚠️ 未编译验证提示）、`LIBRARY_MANUAL.md`（R13 接入指引 + R13 专项声明）、本文件。`INDEX_REGISTRY.json` / JSONL / `ROADMAP.md` / `AGENT_EVOLUTION_LOG.md` / `SOURCE_HUNTING_MATRIX.md` / `OPEN_SOURCE_SHOWCASE.md` / `BATTLE_REPORT` / `DAILY_STATS` 归属另一条文档线，本次未触碰。

### 合规 / Compliance

- **来源与协议**：本批 18 件来源标签为 namur-ne107 / lgf-bitlogic / lgf-comparator / lgf-crc / lgf-matrix / oscat-network / rockwell-aoi / t1-6-plcopen / isa88-process / semiconductor-patent-semantics 等。全部只借鉴功能分类、参数分段与组织方式（含 Rockwell 三分类范式、NE107 状态语言），算法、状态机、码位与引脚契约 100% 独立实现，clean-room，无逐行改写，无 GPL/LGPL 传染风险。
- **零全局耦合**：18 件全部零全局变量表访问、零外部变量声明、零物理地址记号；Modbus 表原始值、轴位置速度、扭矩曲线等一律经引脚注入，块内不绑定任何总线驱动或轴驱动。
- **契约纪律**：故障态一律「保持上次有效值 + 锁存 + 独立复位沿」（R39 修复后 `InterlockMatrix` / `AgvDockingHandshake` 重新逐拍核验）；域外/非有限一律拒绝并显式报码，不夹取、不输出非数（`Matrix3Inverse` / `StringToLReal` / `PumpCavitationGuard` 等同一口径）。

### 观察项 / Observations（留给下轮处置，本次文档线仅登记）

| 编号 | 观察项 / Observation | 影响 | 建议 |
|---|---|---|---|
| O-R13-1 | R39 机检规则对多行条件不稳健（排除项写在第二/三行仍判 FAIL），本轮 3 FAIL 误报均由此产生 | 全库残留 3 FAIL + 2 WARN 留档命中，污染机检看板可信度 | R14 修规则：判据取 `THEN` 之前整段拼接；并裁定「复位判据先于前置改写」豁免形态入册 |
| O-R13-2 | `FB_DL_PumpCavitationGuard` 规格 V1 与默认阈值不自洽（默认扬程跌落比 0.15 下，V1 的 0.8 倍额定扬程同样成立） | 验收向量与出厂默认参数存在口径差 | 已按「不改判据语义迁就向量」裁定并在头注释留档；下轮规格书修正 V1 或默认值 |
| O-R13-3 | 编译验证悬置至第 14 轮，本轮两条最重缺陷（延长窗失能 / 吞复位沿）均属机检不可见家族 | 替代验证四层（机检 / 独立验算 / 时序推演 / 配平）已到收益边际 | 尽快建立最小编译验证通道（三平台各一台 CI 机即可），详见 `LIBRARY_MANUAL.md` 第十五节风险清单 |

---

## [v2.1.0] — 2026-11-15 ｜ R12 跨字位段 + 协议字符串 + 诊断看板/参数核对/电表需量/真空融合 + ISA-88 相底座 + 两轴插补 / Round 12: Cross-Word Bits, Protocol Strings, Diagnostics Board, Parameter Verify, Energy Demand, Vacuum Fusion, ISA-88 Phase Base, Two-Axis Interpolation

**阶段**：Phase 1 第十二轮批处理（R12）｜ **新增组件**：18（合计 5,880 行）｜ **累计**：**186 / 10,000**（全库 54,701 行）｜ **子库版本**：`DL_Base` v1.7.0 → **v1.8.0** ｜ `DL_MathData` v1.5.0 → **v1.6.0** ｜ `DL_Algo` v1.5.0 → **v1.6.0** ｜ `DL_Device` v0.7.0 → **v0.8.0** ｜ `DL_Motion` v0.7.0 → **v0.8.0** ｜ `DL_Process` v0.7.0 → **v0.8.0** ｜ **终审**：**PASS 8 件 + 修复后 PASS 10 件**（缺陷 15 条：致命 3 / 严重 5 / 中等 3 / 注释级 4；本轮定点修复 13 条、按裁定保留 2 条）｜ **升版**：**10 件升 v1.0.1** ｜ **红线违规**：0 ｜ **JSONL 语料**：**186 条** ｜ **今日入库**：**160 / 200**
**Release**: Phase 1 Round 12 — 18 components (5,880 lines), library total 186 / 54,701 lines; final review PASS for 8 files and PASS-after-fix for 10 (15 defects: 3 fatal, 5 severe, 3 medium, 4 comment-level; 13 fixed in round, 2 retained by adjudication); 10 files bumped to v1.0.1; JSONL corpus 186 records; today's intake 160 of 200.

### 新增 / Added

#### DL_Base（4 项，子库 v1.7.0 → v1.8.0，跨字位流与位图监视 / Cross-word bits and bitmap watch）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FC_DL_BitArrayExtract` | FC | `0001_0125`~`0127` | 跨字位流窗口提取：`DWORD` 数组第 1 元素承载位 0~31，按「起始位 + 位宽」取 64 位以内的位窗并右对齐，同出生效掩码与截断后宽度；闸门顺序「字数 → 偏移 → 宽度 → 越界截断」，**非法移位量绝不进入 `SHL`/`SHR`**；宽度 64 走满宽常量分支、禁 `SHL(x, 64)`；窗口伸展到第三个字时显式截断报码，不让高位静默读零 / Cross-word bit window extraction with right-aligned output |
| `FC_DL_BitArrayInsert` | FC | `0001_0128`~`012A` | 跨字位段原子写入（与提取件严格成对）：窗口跨字时先算两个字完整新值再一次性落盘，只改窗口内的位；`nChanged` 只统计**值真的变了**的字——同值写入可被识别，通讯假成功无处可藏；超宽位掩码丢弃并通过 `uApplied` 回显 / Atomic cross-word bit-field write reporting words actually changed |
| `FC_DL_IntervalMembership` | FC | `0001_012B`~`012C` | 开闭区间成员判定：四种开闭组合做成独立枚举（左闭右开 / 左开右闭 / 双闭 / 双开），同出到最近边界的有符号裕量（内正外负、临界为零）与贴边标志；端点倒置判非法**不静默交换**（交换会掩盖上下限填反）；容差只影响贴边标志、不改 `bInside` 归属 / Interval membership with four openness combinations and signed margin |
| `FB_DL_BitArrayChangeWatch` | FB | `0001_012D`~`012F`、`021A`~`021B` | **v1.0.1** —— 位图变化监视：逐字异或出本拍变化掩码、变化位数与首个变化位**绝对位号**（跨字连续、非字内位号），跳变位数累计饱和于 `16#FFFF_FFFE` 不回绕，连续无变化达门限置判稳；掉使能只清变化族而**保留跳变计数**（排故证据不能在停机时被清掉）；监视字数超上限钳位、小于 1 判故障 / Bitmap change watch with first changed bit and settle detection |

#### DL_MathData（5 项，子库 v1.5.0 → v1.6.0，协议字符串与天文钟 / Protocol strings and solar position）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FC_DL_ArrayDiffSummary` | FC | `0001_0134`~`0135` | **v1.0.1** —— 两组实数数组统一容差逐项比对：超差项数、首个超差下标、最大绝对偏差及下标、一致性结论、非有限标志；非有限项计为超差且不参与最大偏差竞争（传感器掉线时最危险的结论是「参数一致」）；容差先取绝对值再钳到最小值，防「零容差把浮点噪声全判超差」；v1.0.1 补「差本身溢出为无穷」的二次判据 / Per-item array diff with finite-difference guard |
| `FC_DL_StringReplaceAll` | FC | `0001_0130`~`0133` | **v1.0.1** —— 定长串内全部出现替换：游标**跳到插入段之后**再继续查找，从算法层消灭「替换串含模式串」的缓冲自增长死循环，另叠次数上限与守卫计数两道闸；空替换串 = 删除；v1.0.1 补拼接超串型上限（255）的显式截断判据（原实现回夹无判据，`bTruncated` 恒假） / Replace-all with cursor-jump law and dual guards |
| `FB_DL_StringTokenStream` | FB | `0001_013A`~`013C`、`021C`~`021E` | **v1.0.1** —— 报文分词流（四相：空闲 / 就绪 / 取段 / 故障）：空段**照占序号**（字段序号对齐的唯一保证），段长超限截断、段数超限锁故障、分隔符为空硬闸；帧变化判据用**逐字符比较**（等长改写靠长度判不出）；`bDone` 为保持型非单拍脉冲；v1.0.1 取段相位改以锁存副本长度切片 / Tokenising stream over a latched frame copy |
| `FC_DL_SolarPositionCalc` | FC | `0001_0136`~`0137` | 太阳位置：年月日时分 + 经纬度 + 时区偏移 → 赤纬、时角、高度角、方位角、均时差；月份天数按当月实际天数校验（含闰年），日超当月天数判非法**不夹取**（夹取会让日照统计出现无法解释的跳变）；天顶不可辨按 `89.5°` 阈值显式兜底；零平台时钟、不猜时区 / Solar position with leap-year date check |
| `FC_DL_ModbusExceptionParse` | FC | `0001_0138`~`0139` | Modbus 异常帧解析：功能码最高位判异常帧，还原原始功能码、给异常码中文名、三级严重度（`01`/`02`/`03`/`08` 故障不可重试，`04` 故障可重试，`05`/`06`/`0A`/`0B` 告警可重试）与「可原样重试」标志；未定义码仍给文字但 `bValid` 为假，**不得**按解析成功处理 / Modbus exception parsing with severity grading and retry advice |

#### DL_Algo（2 项，子库 v1.5.0 → v1.6.0，工艺参数域与建筑热工 / Valve trim and water enthalpy）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FC_DL_WaterEnthalpy` | FC | `0002_2101`~`2102` | 液态水比焓（0 ℃ 基准）与 0 ℃ 到当前温度的平均比热：三次多项式比热积分，域 **0~150 ℃**，域外一律返回 0.0 且 `bValid = FALSE`——**不把域外温度夹到边界再照算**（把 200 ℃ 蒸汽按 150 ℃ 液水结算属静默错误）；零度点平均比热分母为零，显式置 `2102` 并取零度附近比热 / Water enthalpy with a hard domain gate |
| `FB_DL_ValveCharacteristic` | FB | `0002_2001`~`2003`、`2010`~`2012` | **v1.0.1** —— 调节阀固有特性补偿：线性 / 等百分比 / 快开三特性折算阀位，行程限幅 + 输出死区 + 可调比域守护；等百分比低于可调比下限时阀位归零并记下限截断；行程上下限倒置**直接判故障而不静默交换**；故障态保持上次阀位、只认复位沿；v1.0.1 投运与复位首拍改为「保持阀位并夹进生效行程」 / Inherent valve characteristic compensation |

#### DL_Device（4 项，子库 v0.7.0 → v0.8.0，看板 / 核对 / 计量 / 融合）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_DeviceParamVerify` | FB | `0003_014D`~`014F`、`030D`~`030F` | **v1.0.1** —— 设备参数回读核对：组态期望块与回读块按**逐项容差**比对，单拍内完成全项遍历；`bVerified` 为本轮结论、`bMismatch` 为锁存结论（需确认沿）；回读就绪判据为「回读块非全零」，超时 `T#0S` 可关断；v1.0.1 信息码按核对周期清除 / Parameter readback verification with dual verdict |
| `FB_DL_PortDiagBoard` | FB | `0003_0149`~`014C`、`0309`~`030C` | 多组端口诊断看板：4 组 × 8 端口掩码汇总、屏蔽超界位后的各组掩码、全局故障端口数、全局首出（组号最小再端口号最小）与前 3 个待修端口（编码 = 组号×10 + 端口号）；首出只在未锁存时仲裁、锁存后只认复位沿；`030B` 掩码跳变是**趋势码**，与 `0309`/`030A` 同号段但**不置 `bError`** / Multi-group port diagnostic board with first-out arbitration |
| `FB_DL_EnergyMeterAccum` | FB | `0003_0150`~`0152`、`0310`~`0312` | **v1.0.1** —— 电表冻结值累计与需量：正反向各一 32 位拼装（字序可切，复用既有枚举），**先判原始值单调性再做工程量换算**（NE43 口径，标定系数错只让数值错、不让换表判定失效）；换表按回退识别并重置基准，**不做 32 位回绕无损续接**（满量程约 4.29 亿 kWh，回绕前必换表）；窗口平均需量与历史峰值，掉使能窗口停在剩余时间；v1.0.1 修正二次暂停时剩余时间基准 / Energy meter accumulation with demand window |
| `FB_DL_VacuumGaugeMux` | FB | `0003_0153`~`0155`、`0313`~`0315` | **v1.0.1** —— 真空计双表融合：粗抽（皮拉尼）与精抽（电容膜片）按带迟滞的量程判定切换（下门限 = 切换点 ÷ 10^(重叠宽度/2)），重叠区做十倍程交叉校验并输出偏差与质量三档；单表可用降级为「不确定」而非故障（趋势仍需要，但联锁必须看质量位）；双表失效或不一致锁故障并保持上次压力；v1.0.1 取值后按本拍可用性复验 / Dual vacuum gauge fusion with hysteresis and cross-check |

#### DL_Motion（1 项，子库 v0.7.0 → v0.8.0）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_LineInterp2Axis` | FB | `0004_0109`~`010C`、`0204`~`0207` | **v1.0.1** —— 两轴直线插补：单位向量分解 + 单轴限速折算合成速度上限（避免运动中临时降速造成速度台阶）+ 梯形/三角自适应三段剖面；暂停速度归零且位移保持、恢复**按剩余量分流**（剩余不足加速距离直接进减速段）；终点出口把已走距离强制钳到路径总长、进度置 100，收尾速度保留下限防「永远差最后一点」；不注入轴接口 / Two-axis linear interpolation with adaptive profile |

#### DL_Process（2 项，子库 v0.7.0 → v0.8.0）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_BatchPhaseBase` | FB | `0005_0104`~`0107`、`0203`~`0206` | **v1.0.1** —— ISA-88 相状态底座（11 态）：命令沿仲裁 **中止 > 停止 > 暂停 > 恢复 > 启动**（复位独立通道、不参与优先级），同拍低优先命令**丢弃不排队**；**暂停在步骤边界生效**（防「暂停后物料半投」）、**恢复不重头**（步骤号不变、重发当前步）、已终止态只接受复位；单步与暂停双超时看守；`uPhaseElapsed` 只在执行相累加（相净运行时间，可直接进 MES）；v1.0.1 单步超时按步骤边界断输入一拍重计时 / ISA-88 phase state base with boundary-aware hold |
| `FB_DL_PollTempBank` | FB | `0005_0108`~`010A`、`0207`~`0209` | 温控器轮询采集行：最多 8 台，工程量换算 + 有效域判定 + 逐通道滑动均值 + 偏差与最差通道定位 + 质量掩码与在线台数；连续失败达阈值摘除通道而**摘除后仍继续轮询**（否则永远无法自动恢复），连续两拍有效自动复位；坏通道温度保持上次有效值、**绝不用零填充**（零摄氏度在锂箱/冷库是合法工况值）；调度与滤波均复用既有件 / Polled temperature bank with drop-and-recover |

### 修复 / Fixed

#### 本轮终审缺陷（15 条，修复 13 条 / 保留 2 条，10 件升 v1.0.1）

| # | 组件 / Component | 级别 | 缺陷 / Defect | 处置 / Action |
|---|---|---|---|---|
| A-D01 | `FC_DL_StringReplaceAll` | **致命** | 结果拼接超过串型上限 255 时被 `LEFT` 静默回夹，`bTruncated` 恒 FALSE、`0132` 永不置位；验收 V5（250 字符 + 5 次 10 字符替换 → 300）实测 `LEN=255 / 无码`。现场后果：报表模板替换被裁掉尾部字段而调用方判定「结果完整」 | ✅ 在 `CONCAT` 之前预判长度，超限即置 `bTruncated` 与 `0132`，回夹保留为溢出护栏（R37） |
| B-D01 | `FB_DL_BatchPhaseBase` | **致命** | 3 步各 30 s、`tStepTimeout=60S` 的**完全合规批次**在第 3 步被判 `0203` 中止：单步监视定时器在执行/收尾/停止三相间 `IN` 连续为真、`ET` 跨步累加，「单步超时」退化为「相内累计超时」 | ✅ 新增步骤边界断输入一拍标志，`bStepTo` 取值后自清，按步重计时（R40） |
| B-D02 | `FB_DL_VacuumGaugeMux` | **致命** | 采信表在两相之间掉线时 `fPressurePa` 仍写入该表原值（可能 0 或负），工艺联锁可能据此判「已到真空」，与「不死用任一表」的契约正相反 | ✅ 非重叠取值后按「取值表本拍可用性」门控发布，不可用则保持上次值并下拍重裁（R42） |
| A-D02 | `FB_DL_StringTokenStream` | **严重** | 取段相位用实时帧长度做边界与 `MID` 长度却对锁存副本切片：调用方在请求拍与取段拍之间改写帧，新帧更长切出「有效但为空」的假段，新帧更短把有内容的帧判成已读完 | ✅ 取段相位入口重算锁存长度，实时长度只留给变化检测（R38） |
| A-D03 | `FB_DL_BitArrayChangeWatch` | **严重** | 使能为假的同一拍按复位：段 4 无条件把状态改回 `eIdle`，CASE 只进 eIdle 分支，`eFault` 主体整拍被跳过、复位沿一拍即失——「停机 → 按复位 → 上使能」序列下故障永不清除 | ✅ 判据补「且状态不为 `eFault`」，故障态由自身复位沿出口（R39） |
| B-D03 | `FB_DL_EnergyMeterAccum` | **严重** | 需量窗内暂停两次，窗口被拉长到约 1300 s、平均需量偏低约 31%：剩余时间按「整窗 − `ET`」算，而恢复后 `ET` 属于剩余窗，二次暂停把两个不同基准相减 | ✅ 改为按本拍实际预置值求差，两种恢复模式通吃 |
| B-D04 | `FB_DL_LineInterp2Axis` | **严重** | 暂停恢复后首拍速度由 0 直跳峰值：加速段出口只看 `fS >= fAccDist`，恢复时 `fS` 早已超过加速距离，加速段当拍判完成、下一拍赋峰值，伺服报跟随误差 | ✅ 出口改「位移到位且速度达峰值」，恢复按剩余量分流（R41） |
| B-D05 | `FB_DL_ValveCharacteristic` | **严重** | 故障复位或首次投运当拍阀位由上次值**直跳行程下限**（默认 0%），调节阀突跳（水锤/批量扰动）；冷启动时 `fTravel` 还可能落在行程域外 | ✅ 改为保持上次阀位并夹进生效行程，同时补齐出口域保证（R43） |
| A-D04 | `FC_DL_ArrayDiffSummary` | 中等 | 两项**有限**值相减仍可能溢出为无穷（近满量程异号），该偏差直接参与竞争，`fMaxDev` 被污染为无穷、下标指向该项 | ✅ 有限分支内补「差 > 有限上限即按非有限处置」二次判据 |
| B-D06 | `FB_DL_DeviceParamVerify` | 中等 | 首轮一致（`014E`）后 `uErrorId` 永久驻留，后续轮次 `014D`/`014F` 被「仅当码为 0 才置」永久压住，出现「码说一致、结论说不一致」 | ✅ 进入新一轮核对时清码，使信息码按核对周期重新开始（R44） |
| A-D05 | `FB_DL_BitArrayChangeWatch` | 中等 | `IF bFirstScan AND bAnyChange` 中 `bFirstScan` 在采样相位恒真，判据退化为 `IF bAnyChange`；「首拍不累加」实际由状态机结构承担 | ❌ **按裁定保留**：删除判据会与 R19 形式自检口径冲突并掩盖装载意图，须全库统一改判（随 R19 修订一并处理） |
| B-D07 | `FB_DL_LineInterp2Axis` | 轻微 | 零长度路径完成时 `fPathProgress` 输出 0，与验收 V3「进度 100」及完成相赋值矛盾（画面在「已完成」与「0%」间打架） | ✅ 零长度分支补「完成相满值」判定 |
| B-D08 | `FB_DL_BatchPhaseBase` | 轻微 | `bStart` 引脚注释写「仅空闲与已终止态受理」，实现只在 `eIdle` 受理，按注释接线会在终止态反复给启动沿而毫无响应 | ✅ 注释更正为「仅空闲态受理（已终止态须先复位）」 |
| A-D06 | `FC_DL_ModbusExceptionParse` | 注释级 | 异常码超出规范上限时文本为「未定义异常码（超出规范上限）」，规格只定义「未定义异常码」；HMI 若做等值文本判断会漏配 | ❌ **按裁定保留**（可读性增强不宜回退），偏离登记随文档线同步 |
| A-D07 | `FC_DL_StringReplaceAll` | 注释级 | `bValid` 兼「参数合法」与「结果可采信」两义，与规格 3.6 定义不一致 | ✅ 保留实现语义（不完整结果不可采信是本库统一口径），改引脚注释并在头注释登记「规格偏离留档 D1」 |

> **缺陷口径**：按级别计 **15 条**（致命 3 / 严重 5 / 中等 3 / 注释级 4）；按修复状态计 **13 修 / 2 留**；按文件计 **10 件升 v1.0.1**（`FC_DL_StringReplaceAll`、`FB_DL_StringTokenStream`、`FB_DL_BitArrayChangeWatch`、`FC_DL_ArrayDiffSummary`、`FB_DL_ValveCharacteristic`、`FB_DL_DeviceParamVerify`、`FB_DL_EnergyMeterAccum`、`FB_DL_VacuumGaugeMux`、`FB_DL_LineInterp2Axis`、`FB_DL_BatchPhaseBase`）。三条致命全部属「文本全绿、语义全错」家族——机检与逐条推演均未拦下，再次印证**机检不等于编译、也不等于语义正确**。

### 变更 / Changed

- **`DL_Device` 故障码上界由 `0308` 提至 `0315`**：依 R11 立规「`02FA`~`02FF` 封存禁填、故障级自 `0309` 顺延」，本批占用 `0309`~`0315` 共 13 码。其中 **`030B` 虽落在 `03xx` 故障子块内，语义为趋势级提示码（不置 `bError`）**，已在 `DL_Device/VERSION.md` 与 `MANUAL_DL_Device.md` 单列声明，HMI 码表须**按级别着色而非按号段着色**。
- **`DL_Algo` 取 `0002` 段两个新带**：阀特性族 `2001`~`2003` + `2010`~`2012`、水焓族 `2101`~`2102`，均为 R11 `1F` 带之后的顺延；未回填 `0900` / `1300` 两处历史空置带（避免跳号读图困难）。
- **两库共享 `0001` 段的全序约定**：本批 `DL_Base` 取 `0125`~`012F`、`DL_MathData` 自 `0130` 起至 `013C`，中间无空洞无重叠；故障级 `DL_Base` 取 `021A`~`021B`、`DL_MathData` 取 `021C`~`021E`。终审逐码求差，全库跨文件重叠 = 0。
- **新增全库唯一允许的契约式前置条件**：`FC_DL_BitArrayExtract` / `FC_DL_BitArrayInsert` 的数组形参在函数内无法探测实际长度，「有效字数不得大于调用方实际数组长度」由组态保证，已在两文件头注释显式登记。
- **文档线同步范围**：6 份子库 `VERSION.md`（版本号、组件数、码位台账、缺陷修复与变更说明）、6 份手册（`DL_Base/MANUAL_DL_Base.md` / `DL_MathData/MANUAL_DL_MathData.md` / `DL_Algo/MANUAL_DL_Algo.md` / `MANUAL_DL_Device.md` / `MANUAL_DL_Motion.md` / `MANUAL_DL_Process.md` 各补新增组件的中英双语接口表 + 可编译调用示例 + 边界行为 + 故障码表）、`README.md`（徽章 186 / 10,000、分类件数表、明星组件索引、v2.1.0 亮点）、`LIBRARY_MANUAL.md`（故障码总表追加 + 接入指引）、本文件。`INDEX_REGISTRY.json` / JSONL / `ROADMAP.md` / `AGENT_EVOLUTION_LOG.md` / `SOURCE_HUNTING_MATRIX.md` / `OPEN_SOURCE_SHOWCASE.md` / `BATTLE_REPORT` / `DAILY_STATS` 归属另一条文档线，本次未触碰。

### 合规 / Compliance

- **来源与协议**：本批 18 件来源标签为 lgf-bitlogic / lgf-comparator / lgf-datahandling / lgf-datetimer / oscat-network / oscat-building / isa88-process / isa88-batch / codesys-forge-devicereader / plcnext-diag / namur-ne43 / github-topics-motion / roadmap-p0。全部**只借鉴功能分类、参数分段与组织方式**，算法、状态机、码位与引脚契约 100% 独立实现，clean-room，不构成衍生作品，无逐行改写，无 GPL/LGPL 传染风险。
- **零全局耦合**：18 件全部零全局变量表访问、零外部变量声明、零物理地址记号；端口掩码、参数块、真空读数等一律经引脚注入，端口级聚合结果由调用方持有实例后传入看板，块内不绑定任何总线驱动。
- **契约纪律**：故障态一律「保持上次有效值 + 锁存」，不用零/下限填充（`ValveCharacteristic` / `VacuumGaugeMux` / `PollTempBank` 三件同一口径）；域外一律拒绝而非夹取（`WaterEnthalpy` / `SolarPositionCalc` 两件同一口径）。

### 观察项 / Observations（留给下轮处置，本次文档线仅登记）

| 编号 | 观察项 / Observation | 影响 | 建议 |
|---|---|---|---|
| O-R12-1 | `FB_DL_BitArrayChangeWatch` 的 A-D05（`bFirstScan` 恒真判据）按裁定保留，与 **R19 首扫标志范式**的形式自检口径存在张力 | 静态检查看到「首扫标志」会认为已做首扫保护，实际保护由状态机结构承担 | 随 R19 修订统一改判：明确「首扫义务可由相位结构承载」的合法形态 |
| O-R12-2 | `FC_DL_ModbusExceptionParse` 的 A-D06（未定义码文本增强）偏离未在源码登记 | 规格与实现文本不完全一致 | 已在本次文档线的手册与 VERSION 中按实现口径书写；源码头注释的「偏离留档」行仍待代码线补 |
| O-R12-3 | `FB_DL_DeviceParamVerify` 以「回读块非全零」判回读就绪 | 合法参数全为零的设备会一直等到超时 | 已在手册显式提示（`tVerifyTimeout := T#0S` 或先写一个非零参数）；后续版本可考虑增加显式就绪引脚 |
| O-R12-4 | `FB_DL_ValveCharacteristic` 计划正文提到 `2004`~`2006` 三个输入钳位码，与码位表（`2001`~`2003` + `2010`~`2012`）冲突 | 规格内部矛盾，已按「码位表为准」归并 | 下轮规格书修正：删除 `2004`~`2006` 表述，或另批码段后分列 |
| O-R12-5 | 编译验证仍是悬置项（第十二轮） | 三条致命全属「文本全绿、语义全错」家族，机检 + 推演已不足以替代三平台编译 | 尽快建立最小编译验证通道（CODESYS / TwinCAT / InoProShop 各一台 CI 机即可） |
| O-R12-6 | `LIBRARY_MANUAL.md` 的接入指引节次自 R11 起未顺延（R11 未追加第十四节），本轮按实际序号补第十四节并在标题注明 | 任务书按「第十八节」下达，与文件实际章节序列（一~十三）不符 | 下轮统一重排章节号，或在文件头加「章节索引」以免误引 |

---

## [v2.0.0] — 2026-11-15 ｜ R11 工站四件套 + 设备诊断与执行四件 + 批级工艺微调 + 年窗与环形回绕 / Round 11: Station Quartet, Device Diagnostics, Lot-Level Tuning, Window & Counter

**阶段**：Phase 1 第十一轮批处理（R11）｜ **新增组件**：16（合计 6,281 行）｜ **累计**：**168 / 10,000**（全库 48,827 行）｜ **子库版本**：`DL_Base` v1.6.0 → **v1.7.0** ｜ `DL_MathData` v1.4.0 → **v1.5.0** ｜ `DL_Algo` v1.4.0 → **v1.5.0** ｜ `DL_Device` v0.6.0 → **v0.7.0** ｜ `DL_Motion` v0.6.0 → **v0.7.0** ｜ `DL_Process` v0.6.0 → **v0.7.0** ｜ **终审**：**PASS 14 件 + 修复后 PASS 2 件**（缺陷 4 条：致命 2 / 严重 1 / 轻微 1）｜ **存量治理**：7 件（含 3 类三平台编译阻断缺陷）｜ **红线违规**：0 ｜ **JSONL 语料**：**168 条**（与 `.st` 字节级一致，168/168）｜ **机检**：9 规则全库 **168/168 PASS**
**Release**: Phase 1 Round 11 — 16 components (6,281 lines), library total 168 / 48,827 lines; final review PASS for 14 files and PASS-after-fix for 2 (4 defects: 2 fatal, 1 severe, 1 minor); 7 existing files patched including three classes of compilation-blocking defects; JSONL corpus 168 records byte-identical; all nine machine-check rules pass on all 168 files.

### 新增 / Added

#### DL_Process（4 项，子库 v0.6.0 → v0.7.0，工站四件套 / Station quartet）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_PressFitStation` | FB | `0005_01C0`/`01C1`、`02C0`~`02C3` | 伺服精密压装八态工站（4~8 态最小子集）：压入/保压段逐拍做位移-压力包络窗口校验（上下限按位移节点线性插值，节点 ≤32、防死锁二分），提取接触/屈服/峰值/终点四特征点；**屈服判据取斜率回落至峰值斜率指定比例而非压力过峰**（现场屈服段多为斜率软化，强求过峰则单调上升曲线永远判不出）；五类 NG 原因位按位或累计；包络表只读、上下限对调块内镜像纠正 / Servo press-fit station with envelope windowing and four feature points |
| `FB_DL_RotaryIndexTable` | FB | `0005_01C2`、`02D0`~`02D3` | 多工位分度盘节拍五态（待机/停留/分度中/稳定中/故障）：分度请求 → 到位确认 → 稳定等待 → 工位工艺放行；`eSettling` 单独成态隔离「到位后抖动」诊断窗；**稳定窗内到位信号掉沿即判硬件松动、直接锁故障且不自动重试**（自动重试会把机械松动掩盖成偶发超时）；空跑清洗模式逐位走完不计循环数；掩码每拍由启用表重建 / Rotary index table sequencing with settling window and jitter diagnosis |
| `FB_DL_AgvDockingHandshake` | FB | `0005_01C3`、`02E0`~`02E4` | 移动载体与固定工站会话式对接交接七态：到位与双侧就绪各需连续两拍（滤单拍毛刺）；进交接监视时快照物料在位位，过程中该位转假即判物料丢失/错位；**完成确认提前到达按非法请求序列锁故障而不吞掉**（否则上游误接线被解释成一次成功交接）；单一秒表记状态停留时长 / AGV docking handshake with snapshot consistency and out-of-order diagnosis |
| `FB_DL_EnergySavingMode` | FB | `0005_01C4`、`02F0`~`02F2` | 整线空闲节能四态：进入固定「先降压 → 再停热 → 最后伺服休眠」分台阶执行（伺服休眠时气源若仍为工作压力，抱闸释放瞬间会顶件），退出严格反序；唤醒放行须「达压 + 裕量」「低压请求已撤」「唤醒缓冲走完」三条与门；三出口全为状态派生式无锁存；节能/唤醒期间压力触零或非有限即判无反馈、禁放行并锁故障 / Line-level idle energy orchestration with staged withdrawal and gated wake |

#### DL_Device（4 项，子库 v0.6.0 → v0.7.0，诊断 / 解码 / 测量 / 执行）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_PortDiagAggregator` | FB | `0003_0140`/`0141`、`0300`/`0301`/`0307` | 8 端口现场总线诊断聚合与首出仲裁：链路位 + 端口诊断码 + CRC 累计计数三源合成故障掩码、首出端口号、首出诊断码与风暴标志，解决「多端口同时报警 HMI 只看到最后一条」；首出仅在未锁存时仲裁、同拍取端口号最小者（低号端口更近主站）、锁存后只认复位沿；风暴不锁存、只停一拍、不参与故障判定；窗口差分硬拍序（先算增量再装载基准），计数回绕按归零处理 / Eight-port fieldbus diagnostic aggregation with first-out arbitration |
| `FB_DL_StatusWordSegDecoder` | FB | `0003_0142`~`0144`、`0302` | 段表驱动状态字批量解码（≤16 段，偏移 + 宽度 + 名称）：一次调用拿全部字段，同拍给越界 / 重叠 / 段数三类组态诊断与段状态位；入口统一 64 位宽字（DWORD 高位补零即可）；**宽度 = 64 直接取全 1 常量，禁对 64 位字移位 64**；重叠拒绝/覆盖两模式都置段状态位与信息码 / Segment-table driven status word decoder with overlap diagnostics |
| `FB_DL_NtcTempScan` | FB | `0003_0145`/`0146`、`0303`/`0304` | **v1.0.1** —— 1~16 路 NTC 巡检设备对象：B 值方程换算 + 逐通道断线与短路诊断 + 高低温柔限 + 最热通道定位 + 超温/断线双计数；轮询（单拍负载恒定）与全扫两模式；除法前先判五类零；单路探头损坏只置掩码与信息码（整机降级），仅「有效通道为零」与「换算参数非法」置故障位 / Multi-channel NTC scanning with B-value conversion |
| `FB_DL_RollerGapAdjust` | FB | `0003_0147`/`0148`、`0305`/`0306`/`0308` | 辊距微调背隙补偿：单向越程逼近（先退到目标下方一个背隙）→ 反向精定位，**两段不可合并**（合并即退化为普通双向定位）；指令只在相位跃迁拍写，天然满足「反馈丢失时指令保持」——对辊距而言清零等于辊缝全开、属危险侧动作；到位判定要求偏差在容差内且反馈有效；刻意不注入轴接口以维持分层方向 / Roller gap trim with one-directional backlash compensation |

#### DL_Base（2 项，子库 v1.6.0 → v1.7.0）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_YearWindowCheck` | FB | `0001_011E`/`011F` | 年粒度区间窗判定：跨年窗（结束日早于起始日）自动补一个年度周期；按年折叠重复，多年度组态一次配置即年年生效；整数日序数法（相对 2000-01-01 的连续日序，LINT 中间量）取代浮点与时间类型，零浮点、不读平台时钟、不猜时区；三个日期全引脚注入；空窗组态置 `bInvalidConfig` 按空窗处理 / Year-granularity window with ordinal-day arithmetic |
| `FB_DL_RolloverCounter` | FB | `0001_0120`、`0218` | 环形回绕可逆计数 + 净回绕圈数（可负）：到顶加回 0、到底减回上限；回绕一律「比较 + 赋值」，**禁 `MOD`**（无符号域取模跨平台行为不一致的历史坑）；装载电平优先于复位沿与计数沿；双向同拍净变化 0 只置信息码；圈数饱和后停值不静默回绕；**无任何预设比较**（「到限冻结」属饱和件语义）/ Ring-domain reversible counter with net turn counting |

#### DL_MathData（4 项，子库 v1.4.0 → v1.5.0）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FC_DL_RangeOverlapCheck` | FC | `0001_0121` | 两个实数区间六值关系判定（相离/相接/部分重叠/包含/相等/非法）：四点入参、无序端点自动对调；判定次序写死且不可调换（相等先于包含、相离先于相接、相接先于部分重叠）；重叠长度恒非负；开闭位不改变几何关系，只由调用方合成「相接点是否属交集」；NaN 用区间比较取反识别 / Two-interval relation judge with fixed decision order |
| `FC_DL_CalcDistance3D` | FC | `0001_0122`、`0219` | 三维欧氏距离：平面场景 Z 同填 0.0 即退化，不为凑数拆二维变体；大数走缩放分支（先除最大分量再开方）规避中间溢出并置 `bSaturated`；**非有限输入返回 0.0 而非 NaN**（NaN 会沿链污染下游滤波与比较）；同出三分量差 / 3D Euclidean distance with scale-normalised branch |
| `FC_DL_RandomNext` | FC | `0001_0123` | 可复现伪随机（LCG，Numerical Recipes 公开参数）：种子经 `VAR_IN_OUT` 外置回灌，函数本体无状态、可重入；半开区间 `[0,1)` 并给下一拍种子；退化参数回退保底常数并置码；零种子给提示位 / Stateless LCG random with externally carried seed |
| `FC_DL_PercentileLReal` | FC | `0001_0124`、`0002_000E` | 定长样本任意分位值（P0~P100，R-7「排序 + 线性插值」）：**内部拷贝排序、调用方数组帧后不变**（与 `FC_DL_QuickSortLReal` 就地排序语义相反，已写入不变性声明）；非有限样本剔除、分位点越界钳位并回显 `fActualP`、单样本不外插；`nGuard` 兼防死锁与性能探针 / Percentile with copy-sort invariance |

#### DL_Algo（1 项，子库 v1.4.0 → v1.5.0）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_R2rEwmaTuner` | FB | `0002_1F01`~`1F03`、`1F10` | 批级 Run-to-Run 参数微调：一批只动一次（`bNewLot` 沿开事务，`eCompute`/`eApply` 各驻留一拍），偏差经 EWMA 平滑后按增益倒数折算修正量；**双约束次序固定**——先限单次修正量（工艺侧安全）再限参数域（设备侧安全），颠倒会把「参数到界」误报成「修正被限」；首样本直取不让 0 参与平均；批次计数饱和、偏差深 10 环缓冲审计；与拍级 PID 差三到四个数量级 / Lot-level Run-to-Run tuner with EWMA smoothing |

#### DL_Motion（1 项，子库 v0.6.0 → v0.7.0）

| 组件 / Component | 类型 | 码段 | 说明 / Description |
|---|---|---|---|
| `FB_DL_WindingTensionCtrl` | FB | `0004_01C0`~`01C2`、`02D0`/`02D1` | **v1.0.1** —— 卷绕张力给定合成器：基准 = 目标 × 锥度系数（随卷径由 1.0 衰减到 1−K），摆辊误差经**纯比例**修正环（PID 积分/微分为零）折算修正量，两层相加后限幅；卷径可速度比反算或外部注入；摆辊反馈丢失**显式**降级开环（只出锥度基准，不静默沿用），开环恢复闭环前两拍无扰跟踪；锥度分母双重校验 + 系数双向钳位；经 `VAR_IN_OUT` 注入 `DL_Algo` 的 PID 与卷径件（Motion → Algo 属允许方向） / Winding tension synthesiser with taper factor and dancer trim |

### 修复 / Fixed

#### 一、本轮终审缺陷（2 件，均升 v1.0.1）

| 组件 / Component | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| `FB_DL_WindingTensionCtrl` | **致命 ×2** | ① 投切跟踪计数器只置位不递减（`bTrack` 恒真）→ 修正量恒 0、闭环退化为开环；② 跟踪窗内过程值仍取实测 → PID 反算积分残量非零，验收向量 V3 的修正 +1.0 N 数学上不可达 | ① 闭环态逐拍递减跟踪计数；② 跟踪窗内过程值改取基准使偏差为零 |
| `FB_DL_WindingTensionCtrl` | **严重** | ③ `02D1` 判据用「大于」饱和计数上限 → 计数封顶时判据永假、锁存永不触发 | ③ 改「大于等于」，与饱和计数上限自洽 |
| `FB_DL_NtcTempScan` | 轻微 | ④ 全扫模式的扫描圈数累加缺饱和守卫（与轮询分支不一致），长期运行在 2³² 处回绕 | ④ 两条分支统一加「小于上限」守卫 |

#### 二、存量治理（7 件，含 3 类三平台编译阻断缺陷）

**A. 未声明标识符 —— 变量名笔误（4 件 5 处）**

| 组件 / Component | 旧 → 新 | 缺陷 / Defect |
|---|---|---|
| `FB_DL_PneumaticCylinder` | 1.0.0 → **1.0.1** | 段 2 行程计数赋值目标 `_uCycleCount`（带下划线前缀但未在 `VAR` 区声明，同名输出 `uCycleCount` 全文零写入）→ 编译阻断；改为 `uCycleCount`，逻辑零改动 |
| `FB_DL_SingleSolenoidCyl` | 1.0.0 → **1.0.1** | 同一处笔误、同一修法（同批次发现） |
| `FB_DL_LeakTestStation` | 1.0.1 → **1.0.2** | 压差锁存赋值目标 `_fDeltaP` → `fDeltaP`（输出 `fDeltaP` 此前全文零写入致恒 0，属功能缺口 + 编译阻断双缺陷），快判路径与测量结算路径各一处，共 2 处 |
| `FC_DL_QuickSortLReal` | 1.0.0 → **1.0.1** | **漏声明** `nPivotIdx : INT`（段 5.3 三数取中 4 处赋值 + 段 5.3a 2 处引用），补声明后逻辑本体零改动 |

**B. 枚举成员分隔符单冒号 —— 3 文件 5 行（IEC 61131-3 枚举成员赋值须 `:=`）**

| 组件 / Component | 旧 → 新 | 缺陷 / Defect |
|---|---|---|
| `I_DL_AnalogSensor` | 1.0.0 → **1.0.1** | `eWireBreakLow` / `eWireBreakHigh` 两行误写 `:`，数值与语义不变 |
| `I_DL_FlowMeter` | 1.0.0 → **1.0.1** | `eFlowOk` / `eLowCutoff` 两行误写 `:` |
| `FB_DL_AxisRelativeMove` | 1.0.0 → **1.0.1** | `eMoving` 一行误写 `:` |

> **缺陷类别口径**：按「缺陷类别」计为 **3 类**（笔误标识符 / 漏声明 / 枚举单冒号）；按「文件」计 **7 件**；按「写入点」计 **10 处**（4 + 1 + 5）。任务书原口径记为「未声明标识符 2 处」，实测源码修订历史为 4 件 5 处（是否把 `_uCycleCount` 两件并列计为同一处属统计口径差异），此处以源码为准并留档。**A 类与 B 类全部为三平台编译阻断缺陷，而本轮机检 9 规则曾全绿**——再次印证「机检不等于编译」，编译级缺陷必须由独立编译/语法审视通道兜底。

### 变更 / Changed

- **`DL_Device` 故障码上界提升（破坏"码段不可越界"惯例的显式例外）**：该子库原定「信息 `01xx` ｜ 故障 `02xx` 起段」，R10 已用至 `02F9`，仅余 `02FA`~`02FF` 六码，不足以容纳本批九码。故**显式开辟 `16#0003_0300`~`0308` 新子块**，本子库故障码上界由 `02FF` 提至 `0308`，并立规「后续先顺延 `0309`~`03FF`，**禁止回填 `02FA`~`02FF`**」（避免新旧码语义交叠、HMI 码表分组错位）。已同步至 `DL_Device/VERSION.md` 与 `MANUAL_DL_Device.md` 头部。
- **`DL_Motion` 依赖方向首次跨入 `DL_Algo`**：`FB_DL_WindingTensionCtrl` 经 `VAR_IN_OUT` 注入 `FB_DL_PidController` 与 `FC_DL_CoilDiameterCalc`。Motion → Algo 属目录契约允许方向（低层不得引高层，反向不违规），已在 `DL_Motion/VERSION.md` 依赖段与手册头部明示；子库其余 15 件仍为 Level 0 依赖。
- **文档线同步范围**：6 份子库 `VERSION.md`（含 R11 码位台账与件数统计）、6 份手册（`MANUAL_DL_Base.md` / `MANUAL_DL_MathData.md` / `DL_Algo/MANUAL_DL_Algo.md` / `MANUAL_DL_Device.md` / `MANUAL_DL_Motion.md` / `MANUAL_DL_Process.md` 各补 16 件新增组件的接口表 + 可编译调用示例 + 工艺用途/边界条件/故障码表）、`README.md`（徽章 168 / 10,000、分类件数表、亮点三条、快速上手保持可编译）、本文件。`INDEX_REGISTRY.json` / JSONL / `ROADMAP.md` / `AGENT_EVOLUTION_LOG.md` / `SOURCE_HUNTING_MATRIX.md` / `BATTLE_REPORT` 归属另一条文档线，本次未触碰。

### 合规 / Compliance

- **来源与协议**：本批 16 件来源标签为 lgf-*（bitlogic / datetime / counter / math / comparator / measurement / technology）、plcnext-community、profibus-diag、namur-ne107、rockwell-aoi、oscat-building、lbp-process、packml-omac、semiconductor-APC 与包装机械/批控公开手册；全部**只借鉴功能分类、参数分段与命名组织**，状态机、算法、码位与引脚契约 100% 独立实现，clean-room，不构成衍生作品，无逐行改写，无 GPL/LGPL 传染风险。
- **零全局耦合**：16 件全部零全局变量表访问、零外部变量声明、零物理地址记号；分度请求、张力给定、压装采样等一律以引脚或布尔出口下发，块内不绑定任何厂商库。

### 观察项 / Observations（留给代码线处理，本次文档线仅登记）

| 编号 | 观察项 / Observation | 影响 | 建议 |
|---|---|---|---|
| O-R11-1 | `16#0002_0001`~`0005` 被 `DL_Algo`（公共码：参数钳位 / 采样周期钳位 / 非有限输入 / 非法状态兜底）、`DL_Base`（双手同步超时 / 释放不同步 / 联锁 / 无可用源）、`DL_Process`（焓差）三条线共用，**同码不同义** | 与「全库码位零重叠」的断言口径冲突；HMI 按码查表会串义 | 下一轮把 `0002_000x` 明确归属并给另两条线改段；`DL_Algo` 已用 `0002_1Fxx` 开新子块，可作迁移方向 |
| O-R11-2 | `FC_DL_PercentileLReal` 的「空集」事件码 `0002_000E` 属 `0002` 段（Level 1 算法族常用段），在 `DL_MathData` 中**跨段借用** | 单点占用、全库无第二处引用，暂无冲突；但破坏「每子库单一码段」惯例 | 下一轮改归 `0001_0125` 或另立 `0001_02xx` 空集码 |
| O-R11-3 | `I_DL_AnalogSensor` / `I_DL_FlowMeter` 文件头「当前版本」仍为 `1.0.0`（修订历史已记 v1.0.1）；`FB_DL_LeakTestStation` 头为 `1.0.1`（修订历史记 v1.0.2） | 版本溯源以修订历史为准，头部滞后易误导 | 下次触碰这 4 个文件时一并订正头部版本号 |
| O-R11-4 | 三份手册的「组件索引」表自 R6 起未再扩充（`MANUAL_DL_Device.md` / `MANUAL_DL_Process.md` 索引仅列至 R6，`MANUAL_DL_Motion.md` 同） | 索引与正文章节数不一致，新读者误以为组件少 | 下一轮文档线统一重生成索引表（以 `INDEX_REGISTRY.json` 为唯一来源） |

---

## [v1.9.0] — 2026-11-15 ｜ Level 0 三组补强 + 信号发生 + 卷绕工艺 + RFID 与总线诊断 + 拾放工站 / Level 0 Extension & Signal & Winding & RFID & Pick-and-Place

**阶段**：Phase 1 第十轮批处理（R10）· 双源矩阵行首次开组（T2-6 Rockwell AOI / T1-7 PLCnext Community）｜ **新增组件**：16（送审 5,385 行；终审修复后 5,528 行，+143 全为修复注释与勘误留痕）｜ **累计**：152 / 10,000 ｜ **修复**：缺陷 17 条（**致命 2** + 严重 3 + 中等 6 + 注释级 6），8 件升 v1.0.1 ｜ **红线违规**：0 ｜ **今日（2026-11-15）累计**：126 / 200（达成率 63.0%，其中 R3 14、R4 16、R5 16、R6 16、R7 16、R8 16、R9 16、R10 16）

### 新增 / Added

#### DL_Base（3 项，子库 v1.5.0 → v1.6.0，T2-1 LGF Bit Logic / Date and Timer / Counter 三组横向补强）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FC_DL_BitFieldExtract` | FC | lgf-bitlogic | DWORD 任意位段提取（偏移 + 宽度，右对齐 + 生效掩码同出）：`nWidth = 32` 走常量掩码分支规避 `SHL(x, 32)` 跨平台未定义行为；`nWidth = 0` 与越界双重拒绝；跨字按可用位截断（PASS 零修改） / Parameterised DWORD bit-field extraction with wrap-safe full-width branch |
| `FC_DL_WeekOfYearCalc` | FC | lgf-datetime | 年月日 → ISO-8601 周年/周序/周内日（**Zeller 同余 + 周四归属法**）：跨年归属独立语义、闰年 1/2 月 31/30 折算前置、年域 1970~2099；**规格速算式两处硬错已由总监裁定改用本算法（偏离留档，O-5 要求修订规格模板）** / ISO week date with Thursday attribution and Zeller congruence |
| `FB_DL_BidirectionalCounter` | FB | lgf-counter | CTUD 全语义双向计数（DINT 域）：加/减/装载/复位四输入 + 双预设 + 饱和不回绕 + 加计数同拍优先 + 装载拍跳过计数 + 预设倒置锁存（PASS 零修改） / Full CTUD-semantics bidirectional counter with dual presets |

#### DL_MathData（3 项，子库 v1.3.0 → v1.4.0，T2-1 LGF Math 组续挖）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FC_DL_SearchMinMax` | FC | lgf-math | LREAL 数组极值单遍扫描（值 + 索引同出）：首/末次命中可切、NaN 用 `x <> x` 判据跳过、全量非有限返回首个有效位索引而非 0 号位、全等容差标志（PASS 零修改） / Single-pass min/max scan with index reporting and NaN guard |
| `FC_DL_NthRoot` | FC | lgf-math | N 次根纯函数（Newton 迭代）：奇偶次分治（偶次拒绝负底数，禁拿绝对值冒充）、零与非法根次守卫、迭代后结果有限性复检防发散穿透（PASS 零修改） / Nth root with odd/even branch and finiteness re-check |
| `FC_DL_FactorialSat` | FC | lgf-math | 阶乘饱和（域 0~12）：13! 及以上饱和到 `DL_FACT_SAT`、负数按 0、`bSat` + `nUsedN` 双出口；**v1.0.1**：`nAcc * i` → `nAcc * INT_TO_DINT(i)` 消除隐式类型提升（D-17） / Saturating factorial with explicit DINT promotion |

#### DL_Algo（4 项，子库 v1.3.0 → v1.4.0，T2-1 LGF Signal Generators / Technology + T1-2 OSCAT Building）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_SineGenerator` | FB | lgf-signalgen | 相位累加正弦发生器（三态 + CASE 兜底）：回绕用减法 + 单拍回绕上限防死锁（欠采样可一次减多圈但不得无界循环）、失能与 0 Hz 冻结相位不归零、输出双侧限幅；**v1.0.1** D-15 验收向量与逐拍推演矛盾 → 按实现改写并新增「相位采样与拍号对应」段（显式声明一拍固有延迟） / Phase-accumulating sine generator with explicit one-scan latency |
| `FB_DL_SawtoothGenerator` | FB | lgf-signalgen | 对称度参数化锯齿/三角（`fSymmetry` 0.01~0.99，0.5 = 对称三角）：分段斜率独立 + 回绕清零 + `bRising` 段标志 + 周期内相位百分比；**v1.0.1** D-16 同病根修复（向量改为逐拍序列 `0→50→100→50`）/ Symmetry-parameterised sawtooth/triangle generator |
| `FC_DL_CoilDiameterCalc` | FC | lgf-technology | 卷径瞬时反算 `D = v·i/(π·n)`：低速保护先于除法（< 0.5 rpm 沿用 `fPrevDia`）、卷芯保护判打滑、低通首拍无滞后、变化率先算再更新历史、层数与未滤波值双出口（PASS 零修改；O-1 常量 `DL_NMAX` 未使用留档） / Coil diameter inverse calculation with low-speed and core guards |
| `FC_DL_AirDensity` | FC | oscat-building | 湿空气密度（Magnus-Tetens 饱和蒸汽压 + 干/湿分压叠加）：分母 `243.12 + T` 工况域恒正、分压防负、密度 0~20 kg/m³ 钳位、精度承诺收窄至 −10~50 ℃（PASS 零修改） / Moist air density via Magnus-Tetens and partial-pressure superposition |

#### DL_Device（4 项，子库 v0.5.0 → v0.6.0，**T2-6 Rockwell AOI ☐→◐ 首次开组** + **T1-7 PLCnext Community ☐→◐ 首次开组**）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `I_DL_RfidReader` | 接口 | tcopen-component / rockwell-aoi | RFID 读写头契约：随文件发布四 DUT（`E_DL_RfidState` 五态步长 10 / `ST_DL_RfidTag` / `ST_DL_RfidDiag` / `ST_DL_RfidCfg`）+ 只读属性 3 + 方法 4；AOI 参数四分段映射为「方法（In）/ 只读属性（Out）/ 诊断结构（InOut 等价物）/ 内部量（Local）」（PASS 零修改） / RFID reader contract with AOI-style segmentation |
| `FB_DL_RfidTagHandler` | FB | tcopen-component / rockwell-aoi | RFID 实现（IMPLEMENTS）：五态握手 + **写后回读校验** + 超时重试链 + 同标签重复读抑制窗 + 硬件原始错误码透传 + `bHwReq`/`bHwWr` 指令电平输出；**v1.0.1** D-11 `uHwErrorCode` 声明后从未使用 → 透传进 `stDiag.uLastErrorId` 并改条件刷新、D-14 头注释补双码优先级 / RFID handler with verify-after-write and duplicate suppression |
| `FB_DL_AxiolineDiagLatch` | FB | plcnext-community | Axioline 诊断寄存器解析与首出锁存：7 位状态位映射（PF/PW/BUS/RUN/ACT/RDY/SYSFAIL，位序自有）+ 错误码/槽号双寄存器 + **128 特例（无法定位不伪装成 128 号槽）** + 四级诊断等级 + 稳定窗去抖 + 首出槽号与码同拍锁存；**v1.0.1** D-05 严重（屏蔽计数同拍装载又递减致 `bAckDiag` 完全失效）、D-09 锁存未判使能、D-12 事件计数语义 / Axioline diagnostics parser with first-out latch |
| `FB_DL_PdiReadScheduler` | FB | plcnext-community | PDI（Parameters/Diagnostics/Information）异步读取调度：Slot/Subslot/Index/Subindex 四元参数域 + 单拍只发一条（忙时拒绝不排队）+ 超时钳位 + 长度校验 + 双码打包（高 16 位 AddInfo / 低 16 位 ErrorCode）+ 连续三轮失败锁故障；**v1.0.1** D-10 超时未钳位致 `PT = 0` 重试风暴、D-13 码表语义 / PDI object read scheduler with dual-code packing |

#### DL_Motion（1 项，子库 v0.5.0 → v0.6.0，T2-1 LGF Technology 主源 + T2-4 S7-1500 Motion 次源）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_WindingTraverse` | FB | lgf-technology / s7-motion | 收卷卷径递推 + 排线轴往复（五态）：卷径双源仲裁 + 位移按「圈数增量 × 每圈节距」积分 + 端点**方向判据** + dwell 换向 + 端点钳位；**v1.0.1** D-02 **致命**（待机态每拍清方向量、卷绕态从不赋 ±1 → 位移恒 0、排线完全失效）、D-04 严重（A 端判据缺方向致启动首拍误判）、D-07 中等（轴等待上限 0/0 得 NaN）、D-08 中等（仲裁卷径首拍未预置） / Diameter recursion plus reciprocating traverse with direction-aware end detection |

#### DL_Process（1 项，子库 v0.5.0 → v0.6.0，T2-7 PackML/OMAC + T1-5 TcOpen 范式复用）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_PickAndPlaceStation` | FB | packml-omac / tcopen-component | 通用拾放工站模板：注入 X/Y/Z 轴与真空发生器，**九步序**（确认原点→移到取料位→下降→吸取确认→抬升→横移→下降→破真空→抬升回原点）+ 七态最小子集 + 单步三段式（只发一次）+ 到位判据 = 静止态 + 容差窗双条件 + 节拍统计 + 安灯出口；**v1.0.1** D-01 **致命**（主 CASE 漏 `eExecute` 标签被 ELSE 兜底锁故障，九步序永不执行）、D-03 严重（未注入 Y 轴直接 `Stop()` 空引用）、D-06 中等（步 1 清零覆盖同拍错误码） / Nine-step pick-and-place station template with seven-state subset |

### 修复 / Fixed

- **终审 PASS with fixes，缺陷 17 条（致命 2 + 严重 3 + 中等 6 + 注释级 6），8 件 → v1.0.1**：

| # | 级别 | 组件 | 缺陷与修法 / Defect and fix |
|---|---|---|---|
| 1 | **致命 D-01** | `FB_DL_PickAndPlaceStation` | 七态枚举漏列 `eExecute` CASE 标签，执行态命中 `ELSE` 被非法化并锁故障，随后段 8~11 的 `IF _eState = eExecute` 因状态已改写而整段跳过——**工站从 eStarting 推进到 eExecute 的当拍即自杀，九步序一行不执行**；补显式空标签分支（体内只写注释不写动作），注释固化「为何必须列出」防再删。**沉淀 R31** / Missing CASE label made the execute state unreachable on all three platforms |
| 2 | **致命 D-02** | `FB_DL_WindingTraverse` | 待机分支 `nDirInt := 0;` 位于分支体最前无条件每拍执行，卷绕态从不把方向赋回 ±1（端点 `:= -nDirInt`，0 取反仍 0）→ 位移增量恒 0、排线轴原地不动、状态在 eWinding/eDwelling 间空转抖动；**排线完全失效、收卷叠线可立即造成废料**；方向赋值移入启动成功分支。**沉淀 R32** / Direction cleared every scan left the traverse axis motionless |
| 3 | 严重 D-03 | `FB_DL_PickAndPlaceStation` | 故障停机对未注入的可选 Y 轴直接 `iAxisY.Stop()`（`bAxisValid` 只覆盖 X/Z/真空）→ 空引用，多数平台异常停机、汇川报访问违例，**恰在最需要安全停机的时刻把 PLC 打死**；四路逐个 `<> 0` 判空 / Null interface dereference at the very moment a safe stop is needed |
| 4 | 严重 D-04 | `FB_DL_WindingTraverse` | A 端判据 `fTravPos <= 0.0` 无方向条件，启动首拍 `fTravPos = 0` 即命中 → 每次启动先跑到 A 端再折返，首圈排线相位错乱；两端判据补方向条件 / End-stop judgement lacked the direction premise |
| 5 | 严重 D-05 | `FB_DL_AxiolineDiagLatch` | 确认拍先装载 `nAckMute := DL_ACK_MUTE` 再同拍无条件递减 → 屏蔽窗口 0 拍，`bAckDiag` 形同虚设（现场「怎么按都消不掉」）；装载拍不递减、仅非确认拍递减 / Acknowledge muting window collapsed to zero scans |
| 6 | 中等 D-06~D-11 | 4 件 | 步 1 清零覆盖同拍错误码（诊断不可见，改单点出口）/ 轴等待上限分母 0/0 得 NaN 致超时永不触发 / 仲裁卷径首拍未预置产生 −10 m/s 假变化率 / 锁存未判使能致检修期虚假事件 / 超时未钳位致 `PT = 0` 重试风暴（**声明了 MIN/MAX 常量却从不使用，是「参数未钳位」的静态信号**）/ `uHwErrorCode` 声明后从未使用致硬件原始码无法透传 |
| 7 | 注释级 D-12~D-17 | 4 件 + 2 件 | 6 处：事件计数语义与行为不符 / 码表 `013F` 语义扩写 / 诊断字段优先级说明 / **Sine 与 Sawtooth 验收向量与逐拍推演矛盾**（改为逐拍序列 + 相位采样约定段）/ `FC_DL_FactorialSat` 隐式类型提升改显式转换 |

- **修后机检终态**：16 文件 5,528 行，14 项文本级规则 16/16 PASS；CASE/ELSE 兜底全带；赋值目标声明性 0 未声明；孤立分号 0；浮点判等 0；**码位跨文件重叠仅 `16#0000_0000`（无事件码语义，非串台）**；JSONL 152 条字节级一致（8 条 output 重注入，其余 144 条零漂移）。

### 变更 / Changed

- 子库版本：`DL_Base` v1.5.0 → **v1.6.0** ｜ `DL_MathData` v1.3.0 → **v1.4.0** ｜ `DL_Algo` v1.3.0 → **v1.4.0** ｜ `DL_Device` v0.5.0 → **v0.6.0** ｜ `DL_Motion` v0.5.0 → **v0.6.0** ｜ `DL_Process` v0.5.0 → **v0.6.0**；总库 v1.8.0 → **v1.9.0**；registry 136 → **152**；JSONL 136 → **152 条**。
- 新范式两条正式入册 `AGENT_EVOLUTION_LOG.md`：**R31「枚举→CASE 双向映射完备性」**（CASE 分支必须覆盖枚举全部值；代码写在 CASE 之外也必须显式列出空标签并注释原因）、**R32「内部状态量写入点全拍排序审计」**（每个内部量列出本拍所有写入点并按源码次序推演，重点查「先装载后递减」「先清零后置位」类同拍冲突）。
- 故障码族段追加：DL_Base `0001_0113~0118 / 0215~0216`；DL_MathData `0001_0119~011D / 0217`；DL_Algo **四个算法件各独占 `1B/1C/1D/1E` 编号带**（`0002_1B01~1B04`+`1B10~1B11` / `1C01~1C03`+`1C10` / `1D01~1D04`+`1D10` / `1E01~1E04`+`1E10`）；DL_Device `0003_0138~013F` + **新增 `02F0~02F9` 子块**（`02F0~02F1` AOI 组态类 / `02F2~02F3` 工艺类 / `02F4~02F6` 诊断一致性 / `02F7~02F9` PDI 失败锁定）；DL_Motion `0004_01B0~01B3 / 02C0~02C3`；DL_Process `0005_01B0~01B4 / 02B0~02B7`。全部经终审逐码全库复核，冲突 0。
- 源矩阵状态回写：**T2-6 Rockwell AOI ☐→◐**（产出 RfidReader / RfidTagHandler）、**T1-7 PLCnext Community ☐→◐**（产出 AxiolineDiagLatch / PdiReadScheduler）；LGF 六组（bitlogic / datetime / counter / math / signalgen / technology）与 OSCAT Building、TcOpen、PackML、S7-Motion 标注深化与已产出组件名。
- 规格偏离裁定（总监采纳）：① `FC_DL_WeekOfYearCalc` 算法整体替换为 Zeller 同余 + 周四归属法（**规格速算式有两处硬错**：对 2026-01-01 得 3 实为 4；未对闰年 1/2 月折算），O-5 要求修订规格模板；② `FB_DL_PickAndPlaceStation` 接口适配（`fSafeZ`/`fPosTol` 提为引脚、到位判据改「静止态 + 容差窗」、循环超时复用 `02B7`）；③ `I_DL_RfidReader` 保留 METHOD 内联成员写法（全库一致，非缺陷）。
- 观察项 O-1~O-5 留档 v1.1：`DL_NMAX` 未使用 / 循环超时与非法状态共码 `02B7`（下一 MAJOR 扩块 `02C0~02CF`）/ `nPitchPerRev` 前缀与类型冲突（下一 MAJOR 改 `fPitchPerRev`）/ `Init` 形参 `stCfg` 同名遮蔽（下一 MAJOR 改 `stInitCfg`）/ 规格模板周数公式勘误。

---

## [v1.8.0] — 2026-11-15 ｜ Level 0 六组回补 + 调度抽象 + 步进族 + 安灯 / Level 0 Refill & Scheduler & Stepper & Andon

**阶段**：Phase 1 第九轮批处理（R9）· Level 0 回补 + 双源运动 + 双族工艺 ｜ **新增组件**：16（5,051 行，wc -l 口径）｜ **累计**：136 / 10,000 ｜ **修复**：缺陷 13 条（**致命 2** + 严重 8 + 轻微 3）+ 码位改判 15 处 + 全库注释定界符修复 5 处 ｜ **红线违规**：0 ｜ **今日（2026-11-15）累计**：110 / 200（达成率 55.0%，其中 R3 14 个、R4 16 个、R5 16 个、R6 16 个、R7 16 个、R8 16 个、R9 16 个）

### 新增 / Added

#### DL_MathData（6 项，子库 v1.2.0 → v1.3.0，T2-1 LGF Data Handling / Converter 组深化）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_FifoBuffer` | FB | lgf-datahandling | LREAL 元素先进先出环形队列（通用元素队列 vs RingBuffer 时间窗）：压入/弹出/窥视/清空 + 满队丢新策略（不覆盖旧数据）+ 同拍弹压「先弹后压」固定次序 + 指针一致性断言自愈（v1.0.1：码位 5 处撞码顺延 010A~010D/0204） / Element FIFO ring queue with drop-new policy |
| `FB_DL_ArraySearchFirst` | FB | lgf-datahandling | 数组线性搜索首个命中值（无序可用 O(n)）+ 全量计数模式；触发制扫描、结果族每拍先清（v1.0.1：码位 2 处越段撞 PID 族改判 0001_010E/0205） / First-hit linear search with hit counting |
| `FC_DL_BinarySearchLReal` | FC | lgf-datahandling | 升序数组二分查找（纯函数）：防溢出中点写法 + 64 次守护；**v1.0.1 致命修复 D-01：补声明缺失的 uErrorId 引脚**（原 1.0.0 三平台编译必败） / Binary search with declared error pin (fatal D-01 fix) |
| `FC_DL_TempUnitConvert` | FC | lgf-converter | ℃/℉/K 三温标互转（纯函数）：枚举对取代 MODE 巨无霸 + 单向基准链 + 绝对零度信息级不阻断（v1.0.1：码位 3 处越段撞运动轴族改判 0001_0110/0207/0208） / Temperature unit conversion |
| `FC_DL_BcdToWord` | FC | lgf-converter | BCD 码字转 UINT：逐半字节校验前置，非法码零部分结果（v1.0.1：全库唯一强制转换写法改标准 `USINT_TO_UINT`，D-13） / BCD to UINT with nibble validation |
| `FC_DL_WordToBcd` | FC | lgf-converter | UINT 转 BCD 码字：超 9999 饱和不回绕 + 除基守卫（PASS 零修改，0106/0107 核实空闲） / UINT to BCD with saturation |

#### DL_Base（5 项，子库 v1.4.0 → v1.5.0，T2-1 LGF Comparator / Bit Logic / Date and Timer / Counter 四组深化）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_ToleranceWindow` | FB | lgf-comparator | 公差窗口三态判定（合格/低差/高差）+ 迟滞回差防临界抖动 + 双向越差单拍告警（v1.0.1：码位 2 处越段撞设备族改判 0001_0112/0213） / Tolerance window three-state judge |
| `FC_DL_LimitClassify` | FC | lgf-comparator | 四阈值五档限值分档：闭区间贴线归严档 + 阈值序非法拒绝（v1.0.1：码位改判 0001_0214 + 退化组态文档勘误 D-11） / Four-limit five-band classify |
| `FC_DL_WordBitPack` | FC | lgf-bitlogic | WORD 位段参数化打包/解包（读-改-写原子语义）（v1.0.1：**D-09 严重——USINT 域 15+250 回绕为 9 绕过判界**，补四项单项判界；V5 验收向量经总监逐位验算裁定计划表笔误 16#1264→16#12A4） / Bit-field pack/unpack with wrap-safe bounds |
| `FB_DL_MonthWindowCheck` | FB | lgf-datetime | 月内第 N 天/月末倒数日期窗判定：窗口截断不跨月 + 年度模式 + 闰月长独立实现（PASS 零修改，0109/0203 核实空闲） / Monthly/annual day-window check |
| `FB_DL_PresetCounterSat` | FB | lgf-counter | 带饱和预设计数器：上下限钳位停走不回绕 + 装载优先 + bThreshold 首达单拍（v1.0.1：C6 推演文字勘误 D-12，码位 0212 核实空闲） / Saturating preset counter |

#### DL_Device（2 项，子库 v0.4.0 → v0.5.0，T1-8 GitHub topics ☐→◐ 开组）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `I_DL_StepperOpenLoop` | 接口 | stepper | 开环步进契约：ST_DL_StepperCfg（当量/细分/速度/加减速度/堵转裕度/任务周期）+ 属性 3 + 方法 6（≤6 红线临界）；fPosition 强制声明「开环推算值，禁止当编码器反馈」（PASS 零修改） / Open-loop stepper interface |
| `FB_DL_PulseDirStepper` | FB | stepper | 脉冲+方向步进控制器（IMPLEMENTS）：梯形加减速脉冲频率规划 + 限位锁向 + 堵转判据 + 定宽一拍脉冲 R24（**v1.0.1 致命修复 D-02：eDecel 补「频率归零即收尾」第二出口**，原版残差小数时永久卡死无故障码；新增信息级 0003_0137） / Pulse-direction stepper (fatal D-02 fix) |

#### DL_Motion（1 项，子库 v0.4.0 → v0.5.0，T2-4 + T1-6 双源）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_SuperimposedMove` | FB | plcopen-motion / s7-motion | 叠加运动补偿（MC_MoveSuperimposed 语义）：幅值限幅 + 斜坡限速内联实现 + 零驻留收敛判据（浮点残差硬置 0 防假偏移）+ 使能冻结不归零（PASS 零修改；偏离留档：不调用 RateLimiter，斜坡内联） / Superimposed motion compensation |

#### DL_Process（2 项，子库 v0.4.0 → v0.5.0，T1-4 深化 + T2-7/8 安灯族开族）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_ModbusPollMaster` | FB | codesys-forge-modbus | Modbus RTU 轮询主站**调度抽象层**：站表轮询 + 超时重试 + 成功/异常双计数台账 + 全跳过节流；帧构造/CRC/收发归传输层（抽象方法桩返回 FALSE + 锁码，杜绝静默假成功）（PASS 零修改，019x/029x 核实空闲） / Modbus polling master scheduler (transport abstraction) |
| `FB_DL_AndonCallSystem` | FB | andon/omac | 安灯四级呼叫系统：显式优先级仲裁（不依赖枚举数值序）+ 抢占重锁重建升级计时 + 增量式滚动均值防溢出 + 班次清零不清激活呼叫（PASS 零修改，01Ax/02Ax 核实空闲） / Four-level Andon call system |

### 修复 / Fixed

- **终审 PASS with fixes，缺陷 13 条（致命 2 + 严重 8 + 轻微 3），10 件 → v1.0.1**：

| # | 级别 | 组件 | 缺陷与修法 / Defect and fix |
|---|---|---|---|
| 1 | **致命 D-01** | `FC_DL_BinarySearchLReal` | uErrorId 未声明（函数体 5 处读写）——三平台编译期必败；补 VAR_OUTPUT 声明。**机检七轮全过、编译必败的活证据**：机检只查记号/分号/终结符，查不了赋值目标声明性（R29 素材） / Undeclared output pin blocked compilation on all three platforms |
| 2 | **致命 D-02** | `FB_DL_PulseDirStepper` | eDecel 出口仅判步数归零，减速段频率一拍归零而残差为小数 → 相位不再累加，永久停在 eDecel（bPulse 恒 FALSE、无故障码、bReady 恒 FALSE 的现场静默死锁）；出口改双条件 `(_fStepsRemain <= EPS) OR (_fFreqNow <= DL_FREQ_EPS)`，新增信息级 0003_0137 / Unreachable decel exit dead-locked the state machine silently |
| 3 | 严重 D-03~D-08 | 6 件 15 处 | 码位跨文件冲突（FifoBuffer 5 处撞计数/日期族、ArraySearchFirst + BinarySearch 4 处越段撞 DL_Algo PID 族、TempUnitConvert 3 处越段撞 DL_Motion 运动轴族、ToleranceWindow 2 处 + LimitClassify 1 处越段撞 DL_Device 设备族）——**编码者自报"经码表核对未占用"全部不可采信，逐码回溯台账与总手册码表改判顺延**（R30 素材）；终审后全库跨文件重叠 = 0 / 15 fault-code collisions re-adjudicated; self-reported "unused" claims overruled |
| 4 | 严重 D-09 | `FC_DL_WordBitPack` | 参数判界漏洞：nOffset/nWidth 为 USINT（域 0~255），只判求和 > 16 时 15+250=265 回绕为 9 漏判 → SHL(1,250) 平台未定义行为；判据扩为四项单项判界，新增验收 V7 / USINT wrap-around bypassed bounds check |
| 5 | 轻微 D-10~D-13 | 4 处 | 计划向量笔误（WordBitPack V5：16#1264 → 16#12A4，总监逐位验算裁定"代码对、向量错"）+ LimitClassify 退化组态文档语义错（正常档为空集非单点）+ PresetCounterSat C6 复位重锁前置条件勘误 + BcdToWord 全库唯一强制转换写法改标准转换函数 |
| 6 | 全库 | 5 处 | **嵌套注释风险清零（R28）**：头注释内嵌 `(* *)` 定界符（本轮 4 件 + 存量 `FC_DL_Crc16Modbus` 2 行）——非嵌套编译器会提前闭合致正文变代码；存量 Crc16Modbus → **v1.0.1**，JSONL 第 14 行 output 按修后源码再同步 / Nested comment delimiters removed library-wide (R28) |

- **修后机检终态**：16 文件 5,051 行 fail=0、banned_hits=0；终结符成对 / VAR 平衡 / 孤立分号 0 / 未声明标识符 0 / DUT 重复 0 / **码位跨文件重叠 0**（断言脚本复跑）；JSONL 136 条字节级一致。

### 变更 / Changed

- 子库版本：`DL_Base` v1.4.0 → **v1.5.0** ｜ `DL_MathData` v1.2.0 → **v1.3.0** ｜ `DL_Device` v0.4.0 → **v0.5.0** ｜ `DL_Motion` v0.4.0 → **v0.5.0** ｜ `DL_Process` v0.4.0 → **v0.5.0**（`DL_Algo` 本轮无新增）；总库 v1.7.0 → **v1.8.0**；registry 120 → **136**（v1.7.0 → v1.8.0）。
- 新范式三条正式入册 `AGENT_EVOLUTION_LOG.md`：**R28「注释不可嵌套」**（头注释示例代码内禁用同种注释定界符）、**R29「赋值目标声明性检查」**（脚本比对全部 `^标识符 :=` 左侧与声明区并集，拦截 D-01 类编译必败缺陷）、**R30「码位自证循环禁令」**（编码者自报"未占用"不可采信，必须脚本对全库求差断言）。
- 故障码族段追加：DL_Base `0001_0108~010F / 0112 / 0203~0206 / 0212~0214`；DL_MathData `0001_0105~010D / 0110 / 0204~0208`；DL_Device `0003_0130~0137`（信息级）与 `0003_02E0~02E4`（故障级）；DL_Motion `0004_01A0~01A3`（信息级）与 `0004_02B0~02B2`（故障级）；DL_Process `0005_0190~0193 / 01A0~01A1`（信息级）与 `0005_0290~0292 / 02A0~02A1`（故障级）。全部经终审逐码全库复核，冲突 0。
- 验收向量：FC 6 件 31 组 + FB 逐拍推演 6 族由总监独立代回全部通过；WordBitPack V5 计划向量笔误勘误留痕（沿用 R8「公式对、向量错」口径）；`ROUND_PLAN_R9.md` §9 勘误块落定。

---

## [v1.7.0] — 2026-11-15 ｜ 同步耦合开族 + 工艺六件 + 安灯塔 / Motion Sync Family & Process Six & Tower Light

**阶段**：Phase 1 第七轮批处理（R7）· 双 T1 开组/开族 + 双 T2 实测修正 ｜ **新增组件**：16 ｜ **累计**：120 / 10,000 ｜ **修复**：致命 1 + 严重 3 + 中等 1（5 文件 9 处孤立分号）+ 注释级 2 ｜ **红线违规**：0 ｜ **今日（2026-11-15）累计**：94 / 200（达成率 47.0%，其中 R3 14 个、R4 16 个、R5 16 个、R6 16 个、R7 16 个、R8 16 个）

### 新增 / Added

#### DL_Motion（6 项，子库 v0.3.0 → v0.4.0，T1-6 PLCopen 同步耦合族开族）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_ElectronicGear` | FB | plcopen-motion | 电子齿轮耦合（MC_GearIn/GearInPos 语义）：整数比值对全程整数保存防浮点漂移（3:7 长期运行零漂移）+ 比例式相位补偿（钳 ±fPhaseMax）+ 啮合过渡限斜率/脱开受控降速 + 指令重发去抖（每拍至多一次轴方法调用） / Electronic gear coupling with integer ratio pair and phase compensation |
| `FB_DL_ElectronicCam` | FB | plcopen-motion | 电子凸轮耦合（CamIn/CamTableSelect 语义）：16 点表分段线性插值 + 周期/非周期双模式 + 主轴固定偏移与运行相位微调（飞剪切点补偿）+ 啮合沿一次全表单调性校验；相位归一化用条件加减避负数取模（跨平台歧义禁令第二处落地） / Electronic cam coupling with 16-point table and negative-MOD-free phase normalization |
| `FB_DL_GantrySyncAxis` | FB | plcopen-motion | 龙门双驱主从同步：实时偏差监视（预警/故障双阈 + 延时确认 + 80% 回差清除）+ 比例纠偏（饱和计时判机械卡滞）+ 偏差超故障阈双轴停止（向内恢复豁免由调用方承载） / Gantry dual-drive synchronization with deviation monitoring and correction |
| `FB_DL_TorqueLimitControl` | FB | plcopen-motion | 力矩达限压装判定（运行到固定挡块语义）：接近→慢速压装→达限（三源 OR）→保持→位移窗一次锁存判定→释放归位；设备异常进故障锁存、工件不合格只出判定与方向提示 / Torque-limited press judgment with position-window verdict |
| `FB_DL_MarkPositionLatch` | FB | plcopen-motion | 印刷套准色标锁存：布防窗（T#0S=不限）+ 标记上升沿同拍单次读写轴接口 + 定长 8 槽历史前移（索引 0=最新）+ 位置增量与标记缺失提示 / Mark position latch with arm window and history shift |
| `FC_DL_CalcMoveTime` | FC | plcopen-motion | 梯形/三角运动耗时计算（纯函数，DL_Motion 首个 FC）：临界距离三角退化显式判、起始速度超上限走减速到点分支、稳定延时计入、结果超 T#24H 钳位；规格验收向量 V1/V2 与公式矛盾经总监验算裁定公式对、向量错（V1 匀速段 ≈1833 ms、V2 峰速 = 20 mm/s），向量勘误留档 / Trapezoidal/triangular move-time calculator (pure function) with vector erratum |

#### DL_Process（6 项，子库 v0.3.0 → v0.4.0，T1-4 CODESYS Forge 开组 + T2-2 LBP / T2-8 ISA-88 深化）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_ConveyorLineLink` | FB | smema-handshake | 相邻机台/线体段级联握手协调器（SMEMA 式 BA/MR/INH 干接点语义）：三路消抖 + 一行布尔式握手判据（同拍冲突保守侧不放行）+ 传递看门狗自动提升 + 维护直通须审计 + 质量 NG 透传；只做握手编排不驱动执行机构（v1.0.1：消抖断输入掩码误当 IN 入参致消抖完全失效修复） / SMEMA-style inter-machine handshake coordinator |
| `FB_DL_RecipeManager` | FB | codesys-forge-recipe | 通用配方管理器（**T1-4 开组**；所据示例页面许可未显式声明，按最严口径只借结构与参数域、零代码行复制）：校验链六层逐项 + 应用单拍全量写入防半套参数 + 复核回读比对 + 写回校验和清零（不伪造）+ 机台稳态切换防呆 + 变更审计；零文件 I/O，32 位滚动异或校验和（v1.0.1：孤立分号修复） / Recipe manager with rolling-XOR checksum chain |
| `FB_DL_LeakTestStation` | FB | leak-test | 气密泄漏测试工站（压降法）：夹具确认→充气→稳压→隔离测量（温度补偿按开尔文温比）→安全排气五相位；泄漏率 kPa·mL/min 工艺约定口径 + 大漏快判 + 设备异常与工件 NG 严格分离（v1.0.1：孤立分号修复） / Pressure-decay leak test station |
| `FB_DL_MixRecipeControl` | FB | isa-88-mix | 搅拌配方控制（ISA-88 相语义，驱动经 `I_DL_VfdDrive` 注入）：前置确认→转速建立确认窗→混合计时（正反交替换向带停转间隔）→终点判据（时间/扭矩上升二选一）→出料→停转；最长混合时间超时判 NG（v1.0.1：致命 _bNg 未声明 + eNg 终态不可达 + bOk/bNg 保持语义失效 + 孤立分号） / ISA-88 mixer recipe control consuming I_DL_VfdDrive |
| `FB_DL_CipCleaningSeq` | FB | cip-clean | CIP 六相清洗序列（预冲/碱/中冲/酸/终冲/消毒）：TACT 三路联锁暂停不计时 + 暂停上限判相失败 + 终冲回液电导率终点（超时兜底）+ 各相启用启动快照 + CIP 完成许可放行生产（v1.0.1：孤立分号修复） / CIP six-phase cleaning sequence with TACT interlocks |
| `FB_DL_BufferMagazine` | FB | buffer-magazine | 缓冲料仓三策略选层（自动首空/首满 + 手动指定层 + NG 隔离位优先）：升降目标层换算 + 到位消抖 + 双超时护栏；槽位状态数组本块维护，全满/全空/NG 计数每拍重算（v1.0.1：孤立分号修复） / Buffer magazine with three-layer selection strategies |

#### DL_Device（2 项，子库 v0.3.0 → v0.4.0，T1-5 TcOpen 深化 + R7 收口线漏记补记）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `I_DL_TowerLight` | 接口 | tcopen-component/stack-light | 工业安灯塔标准契约：随文件发布三枚举（`E_DL_TowerColor` 六色 / `E_DL_TowerPattern` 五模式 / `E_DL_TowerState` 七显示态）+ 只读属性 10 个 + 方法 3 个（SetColor/SilenceBuzzer/Reset，均带受理返回值）；可适配直驱/模块化/IO-Link 三类实现 / Andon tower light interface contract |
| `FB_DL_SignalTower` | FB | tcopen-component/stack-light | 安灯塔参考实现（IMPLEMENTS `I_DL_TowerLight`）：七级主级仲裁（安全事件最高）+ 人工覆盖 + 消音保持窗（安全事件不受消音约束）+ 慢/快闪半周期可调 + 红绿互斥出口断言 + 五路灯电平与蜂鸣输出 / Signal tower reference implementation with 7-level arbitration |

#### DL_Algo（2 项，子库 v1.2.0 → v1.3.0，T2-1 LGF Math / T2-2 LBP 深化）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_PeakDetector` | FB | lgf-math | 峰值/谷值全周期保持：线性衰减模型（fDecayRate，0=无限保持）+ 谷值独立使能 + 峰值变化率 + 阈值超限电平位 + 峰值更新单拍事件与冲击计数；与 `FB_DL_SignalStatistics` 职责分离（全周期极值 vs 窗口聚合），禁止合并成 MODE 巨无霸 / Peak/valley detector with decay model and threshold events |
| `FB_DL_StepController` | FB | lbp-step-ctrl | 多级步进控制器（1..8 级，LBP CtrlStp 语义平移）：偏差归一化分级 + 级间死区迟滞 + 最小驻留 + 累积/单级双拓扑 + 均衡轮换偏移 + 满出力/回零警示 / Multi-stage step controller with hysteresis, dwell and rotation |

### 修复 / Fixed

- **终审 16/16 PASS，共修复缺陷：致命 1 + 严重 3 + 中等 1 + 注释级 2，受影响 6 个文件 → v1.0.1**：

| # | 级别 | 组件 | 版本 | 缺陷与修法 / Defect and fix |
|---|---|---|---|---|
| 1 | **致命** | `FB_DL_MixRecipeControl` | 1.0.0 → **1.0.1** | `_bNg` 输出符号未声明即赋值——编译阻断（未声明符号是全部缺陷中唯一「连编译都过不了」的一类，其余时序缺陷机检与初读均不可见） / Undeclared `_bNg` symbol blocked compilation |
| 2 | 严重 | `FB_DL_MixRecipeControl` | 1.0.1（随 #1） | eNg 终态不可达——最长混合时间超时分支写为死代码（判据在终态外求值恒 FALSE），NG 判定永不落地；超时分支移入可达路径 / eNg terminal unreachable: timeout branch was dead code |
| 3 | 严重 | `FB_DL_MixRecipeControl` | 1.0.1（随 #1） | bOk/bNg 仅脉冲非保持——判定保持语义失效（「完成保持态」规格被降级为单拍脉冲）；改为保持态内逐拍重写、复位/新启动沿清除（**R27 规则首例素材**） / Held verdicts degraded to one-scan pulses; rewritten as held semantics (R27 material) |
| 4 | 严重 | `FB_DL_ConveyorLineLink` | 1.0.0 → **1.0.1** | 三路消抖的断输入掩码误当 TON 的 IN 入参——消抖定时器输入恒为掩码位而非信号位，消抖完全失效、毛刺直通，危险侧（抑制/可收误动作）。修法：IN 接信号位，掩码仅用于强制 ET 归零的断输入拍 / Debounce break mask mistakenly wired as TON IN; debounce fully defeated on the dangerous side |
| 5 | 中等 | 5 个文件 9 处 | （随各文件） | 终端态分支内孤立分号空语句（statement_list 不容纳孤立分号，文法合规性）——MixRecipeControl / RecipeManager / LeakTestStation / CipCleaningSeq / BufferMagazine，全部改为纯注释占位分支，行为等价（**R26 规则素材**） / Isolated-semicolon empty statements replaced by comment-only branches (R26 material) |
| 6 | 注释级 | 2 处 | （随各文件） | 头注释码位占位与观察项表述对齐终审裁定，逻辑零变更 |

- **修后机检终态**：16 文件 6987 行，fail=0，banned_hits=0（禁记号 0 / 占位符 0 / 终结符成对 / CASE-ELSE 全带 / 接口方法 ≤6 / 码位冲突 0）；受影响 6 条 JSONL 语料按修后源码重建（sha256 逐字节一致），120 条全部合法 JSON。

### 变更 / Changed

- 子库版本：`DL_Motion` v0.3.0 → **v0.4.0** ｜ `DL_Process` v0.3.0 → **v0.4.0** ｜ `DL_Device` v0.3.0 → **v0.4.0** ｜ `DL_Algo` v1.2.0 → **v1.3.0**；总库 v1.6.0 → **v1.7.0**。
- 新范式两条正式入册 `AGENT_EVOLUTION_LOG.md`：**R26「孤立分号空语句禁用」**（终端态占位一律纯注释分支；孤立分号虽多数编译器容忍但非 IEC 文法，属跨平台可移植性隐患）与 **R27「输出保持语义」**（状态保持态的输出必须每拍重置位——不得依赖转换拍脉冲；R24/R25「单拍标志」家族的镜像面：保持侧生命周期）。
- 故障码族段追加：DL_Motion `0004_0130~0132 / 0140~0142 / 0150~0152 / 0160~0164 / 0170~0171 / 0180~0184`（信息级）与 `0004_0250~0252 / 0260~0265 / 0270~0274 / 0280~0284 / 0290 / 0295~0299`（故障级）；DL_Process `0005_0130~0133 / 0140~0143 / 0150~0153 / 0160~0164 / 0170~0173 / 0180~0186`（信息级）与 `0005_0230~0231 / 0240~0246 / 0250~0257 / 0260~0265 / 0270~0274 / 0280~0283`（故障级）；DL_Device `0003_0123~0126`（信息级）与 `0003_02D0~02D1`（故障级）；DL_Algo `0002_19xx`（PeakDetector 信息级）与 `0002_1Axx`（StepController 信息级 1A01~1A05 + 故障级 1A06）。全部经子库码表核对顺延，冲突 0。
- 终审观察项 3 处留档 v1.1：泄漏率量纲 kPa·mL/min 工艺约定（压降-流量统一换算评估）、`FB_DL_ElectronicCam` 相位商域（整除落点归属）、`FB_DL_GantrySyncAxis` 同值阈值告警（是否禁止同值组态）。
- 实测驱动的源矩阵勘误：LGF V1.0.1 公开手册中统计/极值函数归 Math 组内，**无独立 Measurement 功能组**（第 2 节 11 组平移假设更正）；LBP V2.8 实测 23 块清单**无独立混合/定量功能组**（混合工艺改由 ISA-88 相语义承载）。「实测驱动的矩阵勘误」方法论价值记录于 `AGENT_EVOLUTION_LOG.md` R8 节。

### 文档 / Documentation

- 四个子库 `VERSION.md` 追加 v0.4.0/v1.3.0 节（新增组件清单 + 故障码台账 + 终审观察项）；`MANUAL_DL_Motion.md` 新增 10~15 节、`MANUAL_DL_Process.md` 新增 10~15 节、`MANUAL_DL_Device.md` 新增 33~34 节、`DL_Algo/MANUAL_DL_Algo.md` 新增 21~22 节（16 个新组件中英双语接口表 + 调用示例，引脚逐字取自源码声明区）。
- `README.md` 徽章与交付清单刷新至 120；`SOURCE_HUNTING_MATRIX.md` T1-5 TcOpen 行补记 `I_DL_TowerLight` / `FB_DL_SignalTower`（R7 收口线漏记，总监授权补记）并回写 T1-6/T1-4/T2-1/T2-2/T2-8 行 R8 状态；`OPEN_SOURCE_SHOWCASE.md` 新增 2 篇明星组件（#22 ElectronicCam / #23 CipCleaningSeq）。
- `INDEX_REGISTRY.json` total=120、version 1.7.0；`_AI_Training_Dataset/daoli_st_sft_dataset.jsonl` 120 条。

---

## [v1.6.0] — 2026-11-15 ｜ 设备件十件套 + 计数器组开组 / Device Ten-Piece Set & Counter Group

**阶段**：Phase 1 第七轮批处理（R7）· 设备件收尾 + 工艺/运动深化 ｜ **新增组件**：16 ｜ **累计**：104 / 10,000 ｜ **修复**：14 处（含 2 处致命）+ 注释级勘误 1 处 ｜ **红线违规**：0 ｜ **今日（2026-11-15）累计**：78 / 200（达成率 78.0%，其中 R3 14 个、R4 16 个、R5 16 个、R6 16 个、R7 16 个）

### 新增 / Added

#### DL_Base（2 项，子库 v1.3.0 → v1.4.0，T2-1 LGF Counter 组 ☐→◐ 开组）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_EventCounter` | FB | lgf-counter | 双向事件计数器（DINT 域）：递增/递减脉冲沿独立计数、预置装载（bLoad 优先级最高）、高/低阈值比较每拍重算、回绕/饱和双模式可选；双脉冲同拍抵消与装载覆盖计数置信级；DINT 极值先判界后运算杜绝回绕穿透 / Bidirectional DINT event counter with preset load and wrap/saturate modes |
| `FB_DL_ModuloCounter` | FB | lgf-counter | 取模工位索引计数器（转盘/弹夹）：0..nMod-1 条件加减法回绕（禁用取余运算符对负数的平台差异，DINT 域运算后显式转回）、带合法性校验的跳步、双向同拍抵消、跨零点回绕事件一拍；模数 <2 故障锁存 / Modulo station-index counter with conditional wrap arithmetic |

#### DL_Device（10 项，子库 v0.2.0 → v0.3.0，T1-5 TcOpen 组件范式 ☐→◐ 开组：扫码枪/安全门/光幕/流量计/料位开关十件套）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `I_DL_BarcodeScanner` | 接口 | tcopen-component/scanner-handshake | 工业固定式扫码枪标准契约：`E_DL_ScannerState` 六态（步长 10）+ 属性 8 个（含 bReady/bReadOk/bNoRead/sBarcode/nReadCount）+ 方法 3 个（Trigger/Ack/Reset）；串口收发由实现块 IN_OUT 注入 / Fixed industrial barcode scanner interface contract |
| `FB_DL_SerialScanner` | FB | tcopen-component/scanner-handshake | 扫码枪触发-结果握手状态机实现：一次 NoRead 自动重试、二次升级故障；结果按长度校验、先剥离 CR/LF 再锁存；触发输出 TP 定宽脉冲（R24 范式）；bDataAck 与接收层握手对齐 / Serial scanner handshake state machine with retry escalation |
| `I_DL_SafetyDoor` | 接口 | tcopen-component/safety-interlock | 安全门联锁（电磁锁扣）标准契约：`E_DL_SafetyDoorState` 七态解锁时序 + 属性 7 个 + 方法 4 个（RequestUnlock/Relock/Reset/AuditClear）；定位声明：逻辑编排与诊断镜像层，不构成认证安全功能 / Guard-lock safety door interface contract (ISO 14119 semantics) |
| `FB_DL_GuardLockDoor` | FB | tcopen-component/safety-interlock | 带电磁锁扣安全门联锁控制器：请求停机 → 静止确认（零速反馈/run-down 计时二选一）→ 解锁 → 开门审计 → 关门再锁定确认窗 → 复位后重启（禁自动重启）；防篡改冲突全局监视、解锁出口断言式硬约束 / Guard-lock door interlock controller with run-down timing and tamper diagnosis |
| `I_DL_LightCurtain` | 接口 | tcopen-component/light-curtain-muting | 安全光幕监控与屏蔽（Muting）标准契约：`E_DL_CurtainState` 五态 + 属性 7 个（核心安全镜像位 bSafeStop）+ 方法 3 个（Override/Ack/Reset）；bSafeStop 永不因屏蔽置假 / Light curtain monitoring & muting interface contract |
| `FB_DL_SafetyLightCurtain` | FB | tcopen-component/light-curtain-muting | 光幕 OSSD 监控 + 2/4 传感器序列屏蔽状态机：序列错乱立即退出屏蔽 + 故障；屏蔽总时长超时、滞留清除 override 硬帽、OSSD 双通道容差窗、屏蔽灯（屏蔽常亮/override 闪烁）（SICK mut_p / 西门子 Sequential Muting 公开语义 clean-room）/ Sequential muting light curtain with override and discrepancy window |
| `I_DL_FlowMeter` | 接口 | tcopen-component/flow-totalizer | 流量计标准契约（脉冲型/模拟型可适配）：`E_DL_FlowMeterState` 五态 + 属性 6 个（fFlowRate [L/min]/fTotal [L]/nPulseCount）+ 方法 3 个（TotalReset/TotalPreset/Reset） / Flow meter interface contract with totalizer methods |
| `FB_DL_PulseFlowMeter` | FB | tcopen-component/flow-totalizer | 脉冲型流量计瞬时流量与累计总量计量：脉冲沿计数 → 自重触发采样窗频率估计 → K 系数换算；总量按脉冲计数法累计（精度优于积分法）+ 双缓冲读侧永不撕裂；低流量截止、脉冲丢失超时、LREAL 精度边界预警 / Pulse flow meter with dual-buffer windowed frequency estimation |
| `I_DL_LevelSwitch` | 接口 | tcopen-component/level-switch-failsafe | 料位开关标准契约（振动叉/阻旋/电容通用）：`E_DL_LevelState` + `E_DL_FailSafeMode`（fail-safe HIGH 防溢流 / LOW 防干转）双枚举 + 属性 6 个（bHighAlarm/bLowAlarm 双联锁）+ 方法 2 个 / Level switch interface contract with fail-safe direction modes |
| `FB_DL_LevelSwitchVib` | FB | tcopen-component/level-switch-failsafe | 振动叉式料位开关信号处理块：原始开关防抖 → 失效安全方向归一（IF 显式写，禁 XOR 裸用）→ 覆盖/裸露双延迟确认 → 有料/无料双联锁输出；使能切断强制镜像到安全侧 / Vibrating-fork level switch signal conditioning with fail-safe normalization |

#### DL_Process（3 项，子库 v0.2.0 → v0.3.0，T2-7 PackML / T2-2 LBP + T2-8 ISA-88 深化）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_OeeCalculator` | FB | packml-oee | 设备综合效率（OEE）班次统计引擎（oee.com / ISO 22400-2 公开口径）：三因子 = 时间开动率 × 性能开动率 × 合格品率；停机时间经 PackML 根因位语义分账（计划/计划外，双真歧义入计划外保守侧）；周期基准引脚注入禁读 CPU 钟；性能率超 100 封顶置信级 / OEE shift statistics engine with PackML root-cause attribution |
| `FB_DL_ConveyorZone` | FB | conveyor-accumulation | 单段输送线积放控制器（Zero-Pressure Accumulation）：积放单句规则「有料且下游允许才走」、run-on 清区、卡料窗锁存、级联放行 bZoneReady、浪涌防护（使能沿延迟发令）；驱动经 `I_DL_VfdDrive` 接口引用注入（每拍至多一次方法调用） / ZPA conveyor zone controller consuming I_DL_VfdDrive |
| `FB_DL_BatchDosingControl` | FB | lbp-batch-dosing/isa-88 | 多原料单通道配料称重控制器（ISA-88 批次相语义）：三段给料顺控（快加→慢加→落定结算）+ 空中落差自学习（误差/2 防振荡，钳位触限置信级）+ 超差 NG 锁存卸料禁止 + 断流诊断；非有限值重量批次中止全断；Abort 电平最高优先 / Batch dosing weighing controller with in-flight compensation learning |

#### DL_Motion（1 项，子库 v0.2.0 → v0.3.0，T1-6 PLCopen 深化）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_SoftLimitGuard` | FB | plcopen-motion | 软限位安全电子围栏预判器：按当前速度与减速度实时计算双向制动距离（含扫描/IO/驱动时延项，默认 23 ms 三项口径），预警/拦截两级输出（拦截带 ⊇ 预警带，保守安全侧）；超程后仅允许反向指令（向内恢复豁免）；位置/速度经 `I_DL_MotionAxis` 接口引用读取 / Soft-limit guard with braking-distance prediction and inward-recovery exemption |

### 修复 / Fixed

- **终审 16/16 PASS，共修复缺陷 14 处（含致命 2）+ 注释级勘误 1 处，受影响 8 个文件 → v1.0.1**（表内 3 行各捆绑同组件 2 处修复）：

| # | 级别 | 组件 | 版本 | 缺陷与修法 / Defect and fix |
|---|---|---|---|---|
| 1 | **致命** | `FB_DL_SerialScanner` | 1.0.0 → **1.0.1** | 重试链断裂：`_nRetry` 误在 eTriggered 过渡态清零，重试重入即清 → 重试计数失效、无限重发、连续 NoRead 升级故障永不触发。修法：清零移至 eIdle 受理处 / Retry chain broken: retry counter cleared in the transitional state, moved to idle-accept path |
| 2 | **致命** | `FB_DL_BatchDosingControl` | 1.0.0 → **1.0.1** | 判稳死锁：`_bSettleRestart`/`_bFlowRestart` 单拍重启标志永不自清 → 稳窗 TON 输入恒被屏蔽，eSettling 永久挂起、判稳拍结算死锁，断流诊断一次后失效。修法：单拍标志移至实例调用之后自清（R24 同源范式——「单拍标志」家族第二例确认） / Settle-restart one-shots never self-cleared, settling deadlocked; self-clear moved after the instance calls |
| 3 | 严重 | `FB_DL_EventCounter` | 1.0.0 → **1.0.1** | DINT 极值 +1/-1 回绕穿透饱和/回绕判据（加算/减算先运算后判界，极值回绕为负后 >nMax 判据失效）；复位与计数脉冲同拍时计数覆盖复位。修法：先判界后运算 + 复位拍最高优先前置分支 / DINT-extremum wrap bypassed the verdict; boundary pre-check + reset-scan top priority added |
| 4 | 严重 | `FB_DL_SafetyLightCurtain` | 1.0.0 → **1.0.1** | 反向序列判向条件与偏离留档矛盾：2 传感器判向 ELSIF 与正向 IF 恒等（死代码）、4 传感器模式误查 M3（应为 M4）。修法：按「M2/M4 先遮挡 = 反向」修正判向；另修 2 传感器 E2 步双清离无分支 → 步号滞留依赖屏蔽超时误报故障，补双清离回 IDLE / Reverse-direction verdict dead code fixed; dual-clear branch restored |
| 5 | 严重 | `FB_DL_ConveyorZone` | 1.0.0 → **1.0.1** | 手动放行覆盖式赋值把使能/卡料/故障/浪涌门控一并绕过（禁用区被发出运行指令）。修法：改为仅绕过下游条件、保留全部门控；另补 run-on 清区延续窗实现（清空沿 + tRunOn 延续，使能/卡料/故障终止） / Manual release bypassed all gating; release now bypasses only downstream conditions |
| 6 | 工程语义 | `FB_DL_BatchDosingControl` | 1.0.1（随 #2） | `fTareOffset`/`fInflightComp` 缺非数防御（NaN 扩散进净重/截断点链路）。修法：新增 `_fTareEff`/`_fCompEff` 生效值，0.9 非数自比检测 / NaN defense added for tare and in-flight compensation |
| 7 | 工程语义 | `FB_DL_OeeCalculator` | 1.0.0 → **1.0.1** | `nGoodCount` 派生无下溢防御（拒绝脉冲多于完工脉冲时 UDINT 无符号下溢）。修法：补钳零分支 / Unsigned underflow guard added to good-count derivation |
| 8 | 工程语义 | `FB_DL_SoftLimitGuard` | 1.0.0 → **1.0.1** | `fMargin` 缺非数防御（NaN 时拦截比较式恒 FALSE 静默失效——安全相关静默降级）。修法：新增 `_fMarginEff` 生效值并钳制负裕量 / NaN margin silently disabled the intercept; sanitized effective value added |
| 9 | 工程语义 | `FB_DL_SerialScanner` | 1.0.1（随 #1） | `bDataAck` 以状态判据回落与置位同拍 → 应答恒不可见。修法：回落判据改为 NOT bDataNew，与接收层握手时序对齐 / Data-ack never visible; release criterion aligned with the receive-layer handshake |
| 10 | 逻辑级 | `FB_DL_LevelSwitchVib` | 1.0.0 → **1.0.1** | `_fbTrigTest` 误接 `bEnable`：每次使能上升沿（含正常开机）误置 bSensorTest 测试镜像一拍。修法：删除误接实例，bSensorTest 仅由 CmdTest 单拍承载 / Test pulse mistakenly edge-triggered on enable; instance removed |
| 11 | 注释级 | `FB_DL_OeeCalculator` | （随 #7） | `tShiftLength` 声明未参与计算 → 注释标注本轮预留语义 |
| — | 注释级勘误 | `FB_DL_SoftLimitGuard` | （随 #8） | 设计要点「预警带 ⊇ 拦截带」与实现/规格向量矛盾 → 勘误为「拦截带 ⊇ 预警带（含裕量更早触发，保守安全侧）」 |

### 变更 / Changed

- 子库版本：`DL_Base` v1.3.0 → **v1.4.0** ｜ `DL_Device` v0.2.0 → **v0.3.0** ｜ `DL_Motion` v0.2.0 → **v0.3.0** ｜ `DL_Process` v0.2.0 → **v0.3.0**；总库 v1.5.0 → **v1.6.0**。
- 新范式 **R25「单拍标志生命周期三律」** 正式入册 `AGENT_EVOLUTION_LOG.md`（R24 家族扩展）：每拍预清零 / 实例调用后自清 / 消费拍与转出拍分离——「一切单拍标志」（SerialScanner bDataAck、BatchDosing 判稳重启标志均属此家族）。
- 故障码族段追加：DL_Base `0001_0101~0104 / 0001_0210~0211`（计数器族）；DL_Device `0003_0113~0122 / 0003_0280~02C0`（设备件十件套）；DL_Process `0005_0110~0115 / 0005_0200 / 0005_0212~0214 / 0005_0220~0223`；DL_Motion `0004_0108 / 0004_0240~0241`。全部经子库码表核对顺延，冲突 0。

### 文档 / Documentation

- 四个子库 `VERSION.md` 追加 v1.4.0/v0.3.0 节与故障码台账；`MANUAL_DL_Base.md` 新增 23~24 节、`MANUAL_DL_Device.md` 新增 22~31 节（十件套中英双语接口表 + 调用示例）、`MANUAL_DL_Process.md` 新增 6~8 节、`MANUAL_DL_Motion.md` 新增 8 节。
- `LIBRARY_MANUAL.md` 新增「R7 组件接入指引」章节；`README.md` 徽章与交付清单刷新至 104；`ROADMAP.md` 勾选本轮 14 项待办 + 待办池扩容 32 条（167→199）；`SOURCE_HUNTING_MATRIX.md` 第 4/5 节回写（T2-1 Counter 开组、T1-5 TcOpen 开组、T2-7/T2-2/T2-8/T1-6 深化）；`OPEN_SOURCE_SHOWCASE.md` 新增 2 篇明星组件。
- 受影响 8 条 JSONL 语料按修后源码重建（sha256 逐字节一致），104 条全部合法 JSON；INDEX_REGISTRY.json total=104、version 1.6.0。

---

## [v1.5.0] — 2026-11-15 ｜ 组深化四线并进 / Group Deepening: Valve, VFD, Homing, Process

**阶段**：Phase 1 第六轮批处理（R6）· Level 1/2 组深化 ｜ **新增组件**：16 ｜ **累计**：88 / 10,000 ｜ **修复**：6 处（含 2 处致命）｜ **红线违规**：0 ｜ **今日（2026-11-15）累计**：62 / 200（达成率 31.0%，其中 R3 14 个、R4 16 个、R5 16 个、R6 16 个）

### 新增 / Added

#### DL_Device（10 项，子库 v0.1.0 → v0.2.0，阀门三分法 + 变频器族）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_SingleSolenoidCyl` | FB | lbp-basic-process+lbp-device | 单电控弹簧复位气缸驱动（复用既有 `I_DL_Cylinder` 契约）：纯时间模式 / 可选磁开双重校验、联锁失电保位、缩回方向磁开校验超窗独立码位 / Single-solenoid spring-return cylinder driver |
| `I_DL_VacuumGenerator` | 接口 | lbp-basic-process+lbp-device | 真空发生器标准抽象契约：状态枚举 `E_DL_VacuumState` + 属性 5 个（含负压反馈值）+ 方法 4 个（Evacuate/BlowOff/Stop/Reset）/ Vacuum generator interface contract |
| `FB_DL_VacuumEjector` | FB | lbp-basic-process+lbp-device | 真空发生器驱动：负压迟滞判定（负压域施密特）、建立超时、破真空 TP 定宽吹气脉冲、可选开关双确认 / Vacuum ejector driver with hysteresis judgment and blow-off pulse |
| `FB_DL_StarDeltaMotor` | FB | lbp-basic-process+lbp-device | 星三角降压启动（三接触器）：星角切换死区时间互锁（50~200 ms 域）、三路接触器反馈校验、星角互斥出口断言、热继过载锁存、重启抑制冷却 / Star-delta starter with dead-time interlock |
| `I_DL_VfdDrive` | 接口 | lbp-basic-process+lbp-device | 通用变频器抽象契约：状态枚举 `E_DL_VfdState` + 属性 6 个 + 方法 6 个（Run/Stop/Jog/SetFrequency/SelectPresetSpeed/Reset，达 ≤6 红线临界）/ Generic VFD interface contract |
| `FB_DL_VfdGeneric` | FB | lbp-basic-process+lbp-device | 通用端子型变频器驱动：正反转互斥（冲突安全侧停止）、点动优先、多段速选择（段速表引脚注入）、频率模拟量给定 0~100% 线性映射、故障复位端子定宽脉冲 / Generic terminal-type VFD driver |
| `I_DL_ProportionalValve` | 接口 | lbp-basic-process+lbp-device | 比例调节阀抽象契约：状态枚举 `E_DL_ValveState` + 属性 6 个（含偏差报警）+ 方法 3 个 / Proportional valve interface contract |
| `FB_DL_AnalogValve` | FB | lbp-basic-process+lbp-device | 模拟量调节阀指令整形层：设定钳位 → 零点死区补偿 → 限幅域映射（对调自修复）、偏差延时报警、反馈失效保持末次有效值；不含阀位闭环（职责单一） / Analog valve command shaping layer, closed loop excluded |
| `I_DL_MotorizedValve` | 接口 | lbp-basic-process+lbp-device | 电动调节阀抽象契约：状态枚举 `E_DL_MotorValveState` + 属性 6 个（估算开度 + 双限位）+ 方法 4 个 / Motorized valve interface contract |
| `FB_DL_ThreePointValve` | FB | lbp-basic-process+lbp-device | 三点浮点式电动阀控制器：开/关双脉冲输出 + 行程时间积分自动估算开度 + 限位锚定/端点拒绝双保险 + 估算-限位一致性监视 / Three-point floating valve with stroke-time position estimation |

#### DL_Motion（3 项，子库 v0.1.0 → v0.2.0，T1-6 PLCopen Motion 首次开组）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_AxisHomingSeq` | FB | plcopen-motion+s7-motion | 标准回零序列状态机（经 `I_DL_MotionAxis` 接口驱动）：限位开关/原点开关/Z 相脉冲/扭矩堵转四模式，逼近-回退-再逼近-标定时序，超时+行程双护栏，终态重启借道 / Industrial homing sequence with four modes and dual guards |
| `FB_DL_AxisRelativeMove` | FB | plcopen-motion+s7-motion | 单轴相对定位（MC_MoveRelative 语义）：链式步进模式、目标递增累加步进、中止与轴故障中断 / Relative move with chained stepping |
| `FB_DL_AxisVelocityMove` | FB | plcopen-motion+s7-motion | 单轴速度模式（MC_MoveVelocity 语义）：动态改速（连续运动中重发指令）、速度上限钳位、受控停止 / Velocity mode with dynamic retargeting |

#### DL_Process（2 项，子库 v0.1.0 → v0.2.0，行业池 9.5 节 P0 链路闭环示范）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_EnthalpyCompareCtrl` | FB | oscat-building+hvac | 焓差经济器执行块（直接消费 `FC_DL_HumidAirEnthalpy`）：新风/回风双侧焓值 → 差分焓值施密特迟滞判据 → 新风阀位指令，最小新风位硬下限、ASHRAE 90.1 焓值高限停机、输入失效安全侧冻结 / Differential-enthalpy economizer control block |
| `FB_DL_OccScheduleWindow` | FB | lgf-datetime+hvac | 多窗作息排程：内部 4 实例复用 `FB_DL_TimeWindowCheck` + `FC_DL_DayOfWeekCalc`，每日窗矩阵 + 星期使能 + 节假日覆盖 + 跨零点窗预启动回绕 + 多窗最小号仲裁 / Multi-window occupancy schedule with holiday overrides and pre-start |

#### DL_Algo（1 项，子库 v1.1.0 → v1.2.0，LGF Technology 组曲线族）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_RampSoakProfile` | FB | lgf-technology | 多段 Ramp/Soak 程序曲线发生器（1..16 段）：段目标+斜坡+保温三数组、段切换沿单发、外部保持/跳段/循环运行、中途跟踪无扰重启；温控区设定源，烘箱/烧结炉/化成工步共用 / Multi-segment Ramp/Soak profile generator |

### 修复 / Fixed

- **终审 16/16 PASS，共修复缺陷 6 处 + 注释级勘误 2 处，受影响 8 个文件 → v1.0.1**：

| # | 级别 | 组件 | 版本 | 缺陷与修法 / Defect and fix |
|---|---|---|---|---|
| 1 | **致命** | `FB_DL_VacuumEjector` | 1.0.0 → **1.0.1** | 吹气脉冲永不触发：触发请求在 CASE 内置位、主体末尾同拍自清，TP 实例任何扫描周期采样恒为 FALSE → `bBlowValve` 恒不输出、破真空功能整体失效。修法：自清语句移至 TP 实例调用之后（TP 本拍采样起振、下一拍入参回落、定宽由 TP 自身保持） / Blow-off pulse never fired: same-scan set and self-clear defeated the TP; clear moved after the instance call |
| 2 | **致命** | `FB_DL_VfdGeneric` | 1.0.0 → **1.0.1** | 同模板同型缺陷：故障复位脉冲请求同拍置位/自清 → 复位端子定宽脉冲恒不输出，驱动故障只能靠反馈自恢复。修法同上 / Same-template defect on the fault-reset pulse, fixed identically |
| 3 | 严重 | `FB_DL_AxisHomingSeq` | 1.0.0 → **1.0.1** | 三终态死锁：完成/中止/故障三终态无迁出路径，启动沿被吞——首次回零后本块永远无法再次回零。修法：新增「终态重启借道」段，三终态收到启动沿回空闲并由同拍门禁分支受理（不吞沿、不要求双击） / Three terminal states were dead ends; terminal-state restart bridge added |
| 4 | 工程语义 | `FB_DL_AnalogValve` | 1.0.0 → **1.0.1** | 限幅域对调分支直读未经防御的原始引脚，混合非数组态把非有限值带回生效域 → 输出非有限阀位指令且不带任何故障码。修法：对调改为经中间变量交换已防御的生效值 / Span swap read raw pins; swap now operates on defended effective values |
| 5 | 工程语义 | `FB_DL_EnthalpyCompareCtrl` | 1.0.0 → **1.0.1** | 三个参数类 REAL 输入（最小阀位/全开阀位/焓差死区）缺非有限值防御，非有限值经钳位直透新风阀位指令。修法：三参数补自比检测兜底回落默认值后再钳位；高限门限补显式自比检测（与 R4 流量补偿大气压穿透同型） / Parameter REAL inputs lacked non-finite defense; fallback defaults added before clamping |
| 6 | 逻辑级 | `FB_DL_StarDeltaMotor` | 1.0.0 → **1.0.1** | 重启抑制期启动拒绝分配 `0003_0105` 与既有口径冲突（同一事件 DOL 电机已用 `0003_0208`），HMI 同事件双映射。修法：码位语义归一为 `0003_0208`（同库同语义共用，`0105` 空置不分配），同步修订三处头注释占位表述 / Restart-inhibit refusal code normalised to the library-wide `0003_0208` |
| — | 注释级 | `FB_DL_VfdGeneric` | （随 #2） | 点动频率取段速 1 的偏离未落注释 → 引脚注释补声明（本块不切换频率通道，段速 1 兼作点动频率域） |
| — | 注释级 | `FB_DL_ThreePointValve` | 1.0.0 → **1.0.1** | 头注释码位占位表述对齐终审裁定 + 首扫行程计数 ±1 偏差观察项留档；逻辑零变更 |

- **修后机检**：`machine_check_r6.py` 全量重跑 ALL PASS（禁记号 0 ｜ 占位符 0 ｜ 终结符成对 ｜ CASE-ELSE 全带 ｜ 接口方法 ≤6 ｜ 故障码冲突 0）；受影响 8 条 JSONL 语料按源文件重建，与 `.st` sha256 逐字节一致，未改动 80 条与备份逐字节一致。

### 变更 / Changed

- **故障码族段裁定（终审）**：`FB_DL_RampSoakProfile` 的信息级码原分配落入了既有 PID/串级族段，故障级码同样侵入串级族段——数值未撞码但族段语义冲突（HMI 按族段分组会被归入错误报警组）。裁定划**独立族段 `18xx`（Ramp/Soak 程序曲线族）**：信息级 `1801`（末段跳段）/`1802`（段数钳位）/`1803`（零斜坡阶跃）/`1804`（采样周期钳位），故障级 `1810`（段目标非有限值，锁存）；`.st` 内码位常量已全部重排，`DL_Algo/VERSION.md` 族段口径行补记 `17xx`/`18xx` 两行。
- **D4 专项裁定**：`FB_DL_EnthalpyCompareCtrl` 负干球温度经焓值计算链钳位至 0 摄氏度导致新风焓偏高估计——误差方向恒为保守安全侧（经济器少开，仅损失潜在免费冷量），裁定维持现状 PASS（引脚域 -30..60 与透传钳位方案保留，头注释已声明取舍通道）。
- **信息级码占用裁定（维持）**：`FB_DL_OccScheduleWindow` 事件码占用 `02xx` 段——日历排程块全部事件均为信息级（无安全联锁），故障级段整体保留给后续工艺联锁件，头注释显式声明。
- 子库版本：`DL_Device` v0.1.0 → **v0.2.0** ｜ `DL_Motion` v0.1.0 → **v0.2.0** ｜ `DL_Process` v0.1.0 → **v0.2.0** ｜ `DL_Algo` v1.1.0 → **v1.2.0**；总库 v1.4.0 → **v1.5.0**。
- 新范式 **R24「TP/定宽脉冲触发范式」** 正式入册 `AGENT_EVOLUTION_LOG.md`：TP/自实现定宽脉冲的「单拍触发请求」标志，自清语句必须紧随实例调用之后、置位点必须在实例调用之前——禁止「同拍置位 + 主体末尾自清」；验收向量必须含「触发拍 → 脉冲输出持续 PT → 自动回落」三段逐拍推演。

### 文档 / Documentation

- `DL_Device/VERSION.md` / `DL_Motion/VERSION.md` / `DL_Process/VERSION.md` 各追加 v0.2.0 节（新增组件清单 + 故障码台账追加 + 8 个 v1.0.1 注记）；`DL_Algo/VERSION.md` 追加 v1.2.0 节。
- `MANUAL_DL_Device.md` 新增 11~20 节（10 个新组件中英双语接口表 + 调用示例）；`MANUAL_DL_Motion.md` 新增 5~7 节并更新组件索引；`MANUAL_DL_Process.md` 新增焓差/排程两节；`DL_Algo/MANUAL_DL_Algo.md` 新增 Ramp/Soak 节。
- `LIBRARY_MANUAL.md`：新增「R6 组件接入指引」章节，统计与故障码段登记同步为 88；`README.md` 徽章与交付清单全部刷新；`ROADMAP.md` 勾选第 4/5 节 8 条 + 9.5 节 2 条 + 第八节 Ramp/Soak 登记；`SOURCE_HUNTING_MATRIX.md` 第 4/5 节回写 R6 状态；`OPEN_SOURCE_SHOWCASE.md` 新增 2 篇明星组件。

### 数据 / Data

- `INDEX_REGISTRY.json`：`total_components` 72 → **88**，`version` → **1.5.0**，`last_updated` 2026-11-15；16 条新记录字段完整、来源标签挂载（lbp-basic-process / lbp-device / plcopen-motion / s7-motion / oscat-building / lgf-datetime / hvac / lgf-technology）。
- `_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`：72 → **88 条**；前 72 条字节级未变，受终审修复影响的 8 条已按修后源码重建（sha256 逐字节一致）。

### 说明 / Notes

- 无破坏性变更，无迁移动作：R5 及此前 72 个组件中仅 8 个 R6 新组件被终审修复（v1.0.1，引脚契约零变更），其余 80 个逐文件零改动。
- 子库分布：`DL_Base` 22 ｜ `DL_MathData` 20 ｜ `DL_Algo` 18 ｜ `DL_Device` 18 ｜ `DL_Motion` 6 ｜ `DL_Process` 4。
- 本轮 16 组件源码合计 **4,461 行**（`wc -l` 口径），零占位符。
- 来源口径：T2-2 LBP（阀门三分法/变频端子信号集/星三角死区时序）、T1-6 PLCopen Motion + T2-4 S7 Motion（回零组合矩阵/分步范式）、T2-1 LGF Technology（曲线族粒度）、T2-1 LGF Date and Timer（多窗排程）、T1-2 OSCAT Building（焓差经济器判据，ASHRAE 90.1 公开语义）——全部 clean-room，溯源台账见 `_Staging_Raw/2026-11-15/RAW_NOTES_R6.md`（S-1~S-5）。
- 本轮专家召唤记录：原生 `daoli-library-director` 与 `plc-programming-expert` 2×2 尝试均 not available，本轮沿用**兜底模式**（general-purpose 代理 + 强制读取人格规范，双角色分离协作），规范执行口径与原生模式一致。

---

## [v1.4.0] — 2026-11-15 ｜ 三目录开库 / Three Sublibraries Opening

**阶段**：Phase 1 第五轮批处理（R5）· Level 1 Device/Motion + Level 2 Process ｜ **新增组件**：16 ｜ **累计**：72 / 10,000 ｜ **修复**：1 处跨文件重复声明（去重）｜ **红线违规**：0 ｜ **今日（2026-11-15）累计**：46 / 200（达成率 23.0%，其中 R3 14 个、R4 16 个、R5 16 个）

### 新增 / Added

#### DL_Device（8 项，子库 v0 → v0.1.0，Level 1 设备 OOP 开库）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `I_DL_Cylinder` | 接口 | lbp-device | 双电控气缸标准抽象契约：状态枚举 `E_DL_CylinderState` + 只读属性 5 个 + 方法 4 个（Extend/Retract/Stop/Reset），故障态一律拒绝并返回 FALSE / Double-solenoid cylinder interface contract |
| `FB_DL_PneumaticCylinder` | FB | lbp-device | 双电控气缸驱动：磁开双通道消抖、伸/缩超时自检、双传感器冲突锁存、双线圈互斥出口断言、联锁失电保位、行程计数 / Cylinder driver with debounce, timeout checks and conflict latch |
| `I_DL_MotorDriver` | 接口 | lbp-device | DOL 电机驱动器标准抽象契约：状态枚举 `E_DL_MotorState` + 属性 5 个（含重启抑制）+ 方法 3 个 / DOL motor driver interface contract |
| `FB_DL_DolMotor` | FB | lbp-device | DOL 电机控制：指令-反馈校验窗（拒动）、失反馈脱扣、过载锁存、最短运行时间监视、60 分钟桶滑窗每小时启动次数限制与重启抑制冷却 / DOL motor controller with feedback window and restart inhibit |
| `I_DL_AnalogSensor` | 接口 | namur-ne43 | 模拟量变送器标准抽象契约（NAMUR NE43 语义域）：工程量值 + 信号质量分级 + HH/H/L/LL 四级报警位 / Analog sensor interface contract |
| `FB_DL_AnalogTransmitter` | FB | namur-ne43 | NE43 变送器处理块：原始域四段诊断（断线/开路/欠量程/超量程，方向可配置）、滑动平均滤波、线性标定、故障态保持末次有效值 / NE43 transmitter block with raw-domain diagnostics |
| `I_DL_TemperatureZone` | 接口 | lbp-device | 加热/冷却温控区标准抽象契约：状态枚举 `E_DL_TempZoneState` + 属性 5 个 + 方法 3 个 / Temperature zone interface contract |
| `FB_DL_HeatCoolZone` | FB | lbp-device | 双通道温控区控制器（**R4 算法族首个上层消费者**）：注入式 PID → 分程分配 → 双路 PWM SSR 驱动；断偶按 `eBreakAction` 切断对应通道并锁存 / Dual-channel zone controller composing injected PID, split-range and dual PWM |

#### DL_Motion（3 项，子库 v0 → v0.1.0，Level 1 运动控制开库）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `I_DL_MotionAxis` | 接口 | plcopen+s7-motion | 单轴运动控制标准契约：PLCopen 六态 + 禁用态枚举、只读属性 7 个、方法 6 个（Enable/Reset/Stop/MoveAbsolute/MoveRelative/MoveVelocity，达 ≤6 红线临界）；回原由后续组件承载 / Single-axis motion interface on the PLCopen state model |
| `FB_DL_SingleAxis` | FB | plcopen+s7-motion | 单轴参考实现：指令仲裁（Absolute>Relative>Velocity）、软限位预判拦截、虚拟运动学梯形积分仿真/真实位置注入双模式（同一状态机适配两种模式）/ Single-axis reference implementation with virtual kinematics |
| `FB_DL_AxisJogController` | FB | s7-motion | 轴点动操作器：长按低速、延时自动升高速、松开受控停止；点动软限位独立于轴组态，制动距离警戒区强制降速 / Axis jog controller with fast-switch delay and soft-limit guarding |

#### DL_Process（2 项，子库 v0 → v0.1.0，Level 2 工艺层开库）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FB_DL_PackMlStateMachine` | FB | packml | PackML / ISA-TR88.00.02 十七态（+ Undefined）状态机 clean-room 框架：命令驱动 + acting 态 `bStateComplete` 自动推进；Aborting 最高优先级出口；机内保持/机外挂起 OEE 根因区分；模式切换仅稳态受理 / PackML state machine framework, 17 states |
| `FB_DL_PackMlCmdDecoder` | FB | packml | PackML 标准命令解码器：十个离散命令源 + 可选命令字入口（bit0..bit9）双通道收口，最小脉宽防抖单发化，同拍多命令冲突位全部丢弃（安全侧「不猜」）/ PackML command decoder with one-shot emission |

#### DL_Base 补强（2 项，子库 v1.2.0 → v1.3.0）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FC_DL_DayOfWeekCalc` | FC | lgf-datetime | 年月日 → 星期几原子函数（ISO-8601 序周一=1，与 GB/T 7408 / MES 排产一致）：Sakamoto 公开算法 clean-room，闰年 4/100/400 判定，越界返回 `eInvalid(0)` + 码 `0001_0201` / Day-of-week atomic function, ISO-8601 |
| `FB_DL_TimeWindowCheck` | FB | lgf-datetime | 每日时间窗判定块（单一语义反 MODE 巨无霸）：跨零点窗（22:00→06:00）、开=关 24h 全开、星期使能表 ISO 序、窗口开/闭沿单发；时刻引脚注入禁读 CPU 钟 / Daily time-window check with midnight-crossing |

#### DL_Algo 补强（1 项，子库 v1.0.0 → v1.1.0）

| 组件 / Component | 类型 | 来源标签 | 说明 / Description |
|---|---|---|---|
| `FC_DL_HumidAirEnthalpy` | FC | oscat-building+psychrolib | 湿空气比焓计算：Magnus-Tetens 饱和蒸汽压（与 `FC_DL_DewPointCalc` 同系数口径）→ 含湿量 → 焓公式链；大气压引脚注入（默认 101.325 kPa）；对标 OSCAT Building AIR_ENTHALPY / PsychroLib 公开物理公式，clean-room / Moist-air enthalpy via Magnus-Tetens chain |

### 修复 / Fixed

- **跨文件去重修复（R5 收口）**：`FB_DL_HeatCoolZone.st` 曾就地重复声明 `E_DL_SignalQuality` / `I_DL_AnalogSensor`（与 `I_DL_AnalogSensor.st` 正式契约文件冲突）。收口阶段删除重复副本、统一引用正式定义（IEC 同工程内 INTERFACE/ENUM 全局可见），功能与引脚零变更，重复定义隐患清零（详见该文件头注释 D2 闭环留档）。

### 文档 / Documentation

- 新增 `DL_Device/VERSION.md`（子库 v0.1.0、8 组件清单、故障码段 `16#0003_xxxx` 登记）、`DL_Motion/VERSION.md`（v0.1.0、3 组件、段 `16#0004_xxxx`）、`DL_Process/VERSION.md`（v0.1.0、2 组件、段 `16#0005_xxxx`）。
- 新增 `MANUAL_DL_Device.md` / `MANUAL_DL_Motion.md` / `MANUAL_DL_Process.md`：13 节组件详解，每节含中英双语功能说明、完整接口表（引脚名/类型/方向/默认值，逐字取自源码声明区）、故障码表与可编译风格调用示例。
- `DL_Base/VERSION.md` 20 → 22 追加 R5 补强条目（v1.3.0）；`DL_Algo/VERSION.md` 16 → 17 追加焓值组件（v1.1.0）。
- `README.md`：徽章刷新为 72 / 10,000、Phase 1 72/100、语料 72 条；新增 DL_Device / DL_Motion / DL_Process 三枚 Level 徽章；目录结构、导入顺序、交付清单与统计表全部同步。
- `LIBRARY_MANUAL.md`：新增三目录章节导航，统计同步为 72；故障码总表登记 `0003/0004/0005` 三段。

### 数据 / Data

- `INDEX_REGISTRY.json`：`total_components` 56 → **72**，`version` → **1.4.0**，`last_updated` 2026-11-15；16 条新记录字段完整。
- `_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`：56 → **72 条**，16 条新语料 `output` 与 `.st` 字节级一致，全量机检 0 偏差。

### 说明 / Notes

- 无破坏性变更，无迁移动作：R4 及此前 56 个组件逐文件零改动（`FB_DL_HeatCoolZone` 为本轮新组件的收口修复，非既有组件变更）。
- 子库分布：`DL_Base` 22 ｜ `DL_MathData` 20 ｜ `DL_Algo` 17 ｜ `DL_Device` 8 ｜ `DL_Motion` 3 ｜ `DL_Process` 2。
- 故障码段位新规（R5 起公约 0.7）：DL_Device `16#0003_xxxx` ｜ DL_Motion `16#0004_xxxx` ｜ DL_Process `16#0005_xxxx`；信息级统一 `16#0xxx_01xx`（只进 `uErrorId` 不置故障位），故障级 `16#0xxx_02xx` 起段。
- 来源口径：仅借鉴公开规范与教学资料的通用工程语义（PackML/ISA-TR88、NAMUR NE43、PLCopen、S7 Motion 手册、OSCAT Building、LGF），实现代码 100% 独立编写（clean-room）；溯源台账见 `_Staging_Raw/2026-11-15/RAW_NOTES_R5.md`。
- 本轮专家召唤记录：原生 `daoli-library-director` not available，本轮沿用**兜底模式**（general-purpose 代理 + 强制读取人格规范），规范执行口径与原生模式一致。

---

## [v1.3.0] — 2026-11-15 ｜ Level 1 开库 / Level 1 DL_Algo Opening

**阶段**：Phase 1 第四轮批处理（R4）· Level 1 ｜ **新增组件**：16 ｜ **累计**：56 / 10,000 ｜ **修复**：16 处（含 2 处致命）｜ **红线违规**：0 ｜ **今日（2026-11-15）累计**：30 / 200（达成率 15.0%，其中 R3 14 个、R4 16 个）

### 新增 / Added

#### DL_Algo（16 项，子库 v0 → v1.0.0，Level 1 首库开库）

| 组件 / Component | 类型 | 复杂度 | 来源标签 | 说明 / Description |
|---|---|---|---|---|
| `FB_DL_PidController` | FB | 8 | mod-pid-control+oscat-basic+lgf-technology | 单回路位置式/增量式 PID：控制死区、积分分离（触限停积分）、两级抗饱和（条件积分 + 限幅反算回填）、手自动无扰与跟踪回投，fKp 为负即反作用 / Single-loop positional or incremental PID with anti-windup and bumpless transfer |
| `FB_DL_CascadePid` | FB | 8 | mod-pid-control+lgf-technology | 主副双回路串级：主回路输出经副设定域限幅后作为副回路设定值，内部组合两个 `FB_DL_PidController` 实例，采样周期与限幅统一注入 / Master-slave cascade PID composing two PidController instances |
| `FB_DL_SplitRangeControl` | FB | 5 | mod-pid-control+lgf-technology | 分程输出分配：正半区驱动加热、负半区驱动冷却，中央死区防双阀同开，两路独立量程二次映射，加热通道可反相 / Split-range allocation for heating and cooling actuators |
| `FB_DL_FeedforwardComp` | FB | 6 | lgf-technology | 静态 + 动态前馈补偿：静态增益项 + 一阶惯性/超前滞后整形 + 可选纯滞后（固定 10 槽延时队列），叠加到 PID 反馈通道 / Static and dynamic feedforward with a 10-slot dead-time queue |
| `FB_DL_SmithPredictor` | FB | 9 | lgf-technology+mod-pid-control | 史密斯预估器：一阶 + 纯滞后模型实时仿真（20 槽滞后队列），补偿后误差驱动内嵌 PID，模型静态偏差在线自适应，上电填充期自动退化为普通 PID / Smith dead-time compensator with an adaptive first-order model |
| `FB_DL_RateLimiter` | FB | 4 | lgf-technology+lgf-signalgen | 变化率限制器：升降速率独立可调，速率为 0 表示该方向不限速直通，支持跟踪回投与限速进行中标志 / Slew-rate limiter with independent rise and fall rates |
| `FB_DL_RampGenerator` | FB | 4 | lgf-signalgen+lgf-technology | 线性斜坡发生器：阶跃目标按 EU/s 斜率平滑逼近，斜率为 0 该方向冻结（绝不直通），暂停保持 + 跟踪投切 / Linear setpoint ramp with hold and track modes |
| `FB_DL_SCurveGenerator` | FB | 9 | lgf-signalgen+lgf-technology | 七段式 S 型轨迹规划器：jerk→acc→vel→pos 四级积分链真实推进，自适应减速行程估算，bAbort 按最大减速安全停车 / Seven-phase jerk-limited S-curve trajectory planner |
| `FB_DL_PwmDutyController` | FB | 6 | lgf-signalgen+mod-pid-control | 时间比例慢速 PWM：0..100% 占空比调制成布尔输出驱动 SSR/接触器，最短导通/关断抑制（欠脉冲跨周期债务补偿），可与 PID 输出直连 / Time-proportional slow PWM with min on/off pulse suppression |
| `FB_DL_Integrator` | FB | 4 | oscat-basic+lgf-math | 梯形法离散积分器：LREAL 双精度累加防长时漂移，限幅触限保持、复位、保持、跟踪回投，流量累计 / 总量表 / Trapezoidal integrator with double-precision accumulation |
| `FB_DL_Differentiator` | FB | 5 | oscat-basic+lgf-measurement | 实用微分器：差分商 + 一阶低通抑制噪声放大 + 速率限幅，温度变化速率监控 / 压装速度计算前级 / Practical differentiator with low-pass and rate clamping |
| `FB_DL_LowPassFilter` | FB | 3 | lgf-measurement | 一阶惯性低通（PT1）：时间常数运行时可调即时重算系数，T#0S 直通，首扫与跟踪无滞后 / First-order low-pass with runtime-adjustable time constant |
| `FB_DL_SecondOrderFilter` | FB | 6 | lgf-measurement | 二阶巴特沃斯低通：双二阶离散递推，双线性变换（含 TAN 预畸变）即时重算五系数，ζ=0.7071，高频滚降 -40dB/dec，直流增益恒 1 / Second-order Butterworth biquad with bilinear prewarping |
| `FB_DL_HighPassFilter` | FB | 4 | lgf-measurement | 一阶高通（HP1）：剥离静态偏置提取动态分量，振动/位移趋势剥离、结露监测漂移滤除，含输出限幅与首扫防脉冲 / First-order high-pass for dynamic component extraction |
| `FC_DL_DewPointCalc` | FC | 3 | oscat-basic+psychrometrics | Magnus-Tetens（Stull 参数化）露点计算：干球温度 + 相对湿度 → 露点，附实际水汽压供焓值链路复用，洁净室/干燥房环控与结露风险判断 / Magnus-Tetens dew point with vapor pressure output |
| `FC_DL_FlowCompensate` | FC | 5 | oscat-basic+gas-metering | 气体/蒸汽流量温压补偿：按理想气体定律工况流量 → 标况 Nm³/h，可选开方支持孔板/文丘里差压口径，绝压/温度双防御下限 / Temperature-pressure flow compensation to standard cubic meters |

### 修复 / Fixed

- **终审 16/16 PASS，共修复 16 处缺陷，其中 2 处为致命锁死级**：
  - **致命 #1**：`FB_DL_Integrator` 1.0.0 → **1.0.1** —— 首扫自动跟踪判据（`bInit`）反向：一次 `bTrack` 跟踪脉冲后首扫标志判据反转导致累加器被**永久锁死**为跟踪值，积分功能此后完全失效。
  - **致命 #2**：`FB_DL_SCurveGenerator` 1.0.0 → **1.0.1** —— 同类首扫自动跟踪判据反向，叠加 **eDone 新目标检测判据与刚吸附值恒等**（到位后置新目标永不触发），轨迹发生器到位后**永久锁死**无法接受新目标。
  - 由上述两处提炼新范式 **R19 首扫标志唯一合法范式**（本轮口径 R8）：`bInit` 声明期初值必须为 `FALSE`（语义＝「尚未初始化」），首扫判据一律写 `IF bTrack OR (NOT bInit) THEN` 且**同步动作后显式置 `TRUE`**；禁止 `IF bInit OR bTrack THEN ... bInit := TRUE` 这类反向判据——该写法首扫永不触发，且一旦被 `bTrack` 触发就每拍触发，双向皆错（详见 `AGENT_EVOLUTION_LOG.md` Round 04）。
- **其余 14 处 v1.0.1 精修**（均不改动引脚契约）：

| 组件 | 版本 | 修复要点 / Fix |
|---|---|---|
| `FB_DL_PidController` | 1.0.0 → **1.0.1** | 积分量纲统一为 `[%]`；`eIdle` 态补 `bActive` 清零防跨拍残留；信息级码（饱和/手动钳位）不再置 `bError`；首扫与手自动切换历史同步防微分踢腿 |
| `FB_DL_RampGenerator` | 1.0.0 → **1.0.1** | 首扫自动跟踪判据修复（`bInit` 判据反向导致首扫不跟踪），对齐通用约定 |
| `FB_DL_PwmDutyController` | 1.0.0 → **1.0.1** | 首次使能当拍立即结算占空比配额，消除首周期无条件关断；`bInit` 由死变量转为有效标志 |
| `FB_DL_Differentiator` | 1.0.0 → **1.0.1** | 首扫初始化标志判据恒假为死代码的修复，首扫同步端点改为显式可审计路径 |
| `FB_DL_SecondOrderFilter` | 1.0.0 → **1.0.1** | 首扫先采样直通再重算系数，消除首拍输出跳零与系数未就绪即递推的瞬态 |
| `FB_DL_FeedforwardComp` | 1.0.0 → **1.0.1** | `tLagTime = T#0S` 恢复为规格合法直通口径，不再误置 `16#0002_0401` 故障码 |
| `FB_DL_SmithPredictor` | 1.0.0 → **1.0.1** | 信息级码 `16#0002_0502`（模型滞后截断）不再置 `bError`，防下游报警误动作 |
| `FC_DL_FlowCompensate` | 1.0.0 → **1.0.1** | 非有限值防御扩展覆盖 `fAtmPress` / `rNormPressPs` / `rNormTempTs`，杜绝 NaN 带 0 码穿透 |

### 文档 / Documentation

- 新增 `DL_Algo/VERSION.md`（子库 v1.0.0、16 组件清单、Level 1 依赖声明、兼容性说明）。
- 新增 `DL_Algo/MANUAL_DL_Algo.md`：16 节组件详解，每节含中英双语功能说明、完整接口表（引脚名/类型/方向/默认值/单位，逐字取自源码声明区）、可编译风格调用示例与现场注意事项；子库故障码按组件细分登记（`16#0002_xxxx` 段，01xx~16xx 组件码）。
- `README.md`：徽章刷新为 56 / 10,000、Phase 1 56/100、语料 56 条；新增 Level 1 DL_Algo 徽章；交付清单新增 DL_Algo 16 项；「最新动态」换为 Round 04 交付与 R8 范式。
- `LIBRARY_MANUAL.md`：新增 DL_Algo 交付摘要章节，总组件数等统计同步为 56。

### 数据 / Data

- `INDEX_REGISTRY.json`：`total_components` 40 → **56**，`version` → **1.3.0**，`last_updated` 2026-11-15T02:19:18+08:00；16 条 DL_Algo 记录字段完整。
- `_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`：40 → **56 条**，16 条新语料 `output` 与 `.st` 字节级一致，全量机检 0 偏差。

### 说明 / Notes

- 无破坏性变更，无迁移动作：Level 0 两个子库 40 组件逐文件零改动。
- 子库分布：`DL_Base` 20 ｜ `DL_MathData` 20 ｜ `DL_Algo` 16 ｜ `DL_Device` 0 ｜ `DL_Motion` 0 ｜ `DL_Process` 0。
- 本轮专家召唤记录：原生 `daoli-library-director` 与 `plc-programming-expert` 两次尝试均 not available，本轮沿用**兜底模式**（general-purpose 代理 + 强制读取人格规范，双角色分离协作），规范执行口径与原生模式一致。

---

## [v1.2.0] — 2026-11-15 ｜ Level 0 收口 / Level 0 Closure

**阶段**：Phase 1 第三轮批处理（R3）· Level 0 ｜ **新增组件**：14 ｜ **累计**：40 / 10,000 ｜ **修复**：1（库级）｜ **红线违规**：0

### 新增 / Added

#### DL_Base（4 项，子库 v1.1.0 → v1.2.0，20/20 收口）

| 组件 / Component | 类型 | 复杂度 | 来源标签 | 说明 / Description |
|---|---|---|---|---|
| `FB_DL_TwoHandSafety` | FB | 6 | iec60204+iso13851 | 双手同步校验与防旁路状态机：同步窗/释放窗/卡死三级判定，卡死升级为旁路嫌疑并锁存；标准 PLC 逻辑骨架定位，合规披露留档 / Two-hand synchronism check with anti-bypass |
| `FB_DL_InterlockMatrix` | FB | 7 | isa18-2+lgf-bitlogic | 16 路联锁汇总与首因追踪：停机级/提示级双掩码、取反掩码真值表、首因通道号+位图+全局序号、复位挂起不清根因 / 16-channel interlock matrix with first-out tracking |
| `FB_DL_RedundantSwitch` | FB | 8 | lgf-comparator | 双通道冗余选择器：偏差延时确认、限速无扰切换、抖振锁定，两路矛盾默认保持最后有效值不猜谁对 / Dual-channel redundancy selector with bumpless switchover and chatter lock |
| `FB_DL_DutyStandbyRotation` | FB | 9 | lbp-basic-process+lead-lag | 8 台泵/风机主备轮值均衡调度：累计运行时间排序、先启后停、双向最小时长保护、故障机越权停机、无可用机组绝不全停 / Duty/standby rotation scheduler |

#### DL_MathData（10 项，子库 v1.1.0 → v1.2.0，20/20 收口）

| 组件 / Component | 类型 | 复杂度 | 来源标签 | 说明 / Description |
|---|---|---|---|---|
| `FC_DL_MultiPointLinear` | FC | 6 | lgf-math+lbp-basic-process | 2..16 点折线查表线性插值，二分查找 O(log2 N)；非法表整表拒绝、异常返回表首值不引入伪零 / Multi-segment table interpolation |
| `FC_DL_PolygonArea` | FC | 5 | lgf-math | 鞋带公式多边形面积与质心（LREAL 单遍累加），退化时质心回退顶点均值 / Shoelace area and centroid |
| `FC_DL_LineIntersection` | FC | 3 | lgf-math | 二维两直线/线段交点，平行容差按坐标量级配置，共线单独报码 / 2D line intersection |
| `FC_DL_Crc32Ethernet` | FC | 6 | oscat-network+crc32-iso-hdlc | CRC-32/ISO-HDLC 逐位法（以太网 FCS），分块链式调用，附 `"123456789"` → `16#CBF4_3926` 验收向量 / Bit-wise CRC-32 with chunk chaining |
| `FC_DL_LrcChecksum` | FC | 3 | oscat-network+modbus-ascii | Modbus ASCII LRC，帧头帧尾不参与计算，与 `FC_DL_HexStringToBytes` 组成两步收帧链 / Modbus ASCII LRC |
| `FB_DL_LifoStack` | FB | 5 | lgf-datahandling | 定长 64 LIFO 栈，四操作全 O(1)，满拒写不覆盖，上溢/下溢锁存，累计计数生命周期保留 / Fixed 64-slot LIFO with latched overflow/underflow |
| `FB_DL_MedianFilter` | FB | 6 | lgf-measurement+oscat-basic | 滑动窗口中值滤波（3..15 强制奇数），副本排序不打乱环形时间序，启动期不等装满即有值 / Sliding median filter |
| `FB_DL_SignalStatistics` | FB | 7 | lgf-math+oscat-basic | 滑动窗口七元组实时统计（均值/极值/峰峰值/方差/标准差/样本数），两遍法方差防灾难性抵消，n−1 样本方差口径 / Streaming statistics with two-pass variance |
| `FC_DL_QuickSortLReal` | FC | 7 | lgf-datahandling+oscat-basic | LREAL 数组原地快速排序：**显式栈替代递归**（嵌入式/汇川栈安全）、三数取中防退化、小区间插入排序兜底、失败语义显式披露 / Recursive-free quicksort |
| `FC_DL_HexStringToBytes` | FC | 4 | lgf-converter+modbus-ascii | 十六进制 ASCII 串严格解析为字节数组：两遍扫描先校验后写入、失败不写缓冲、可选剥离 Modbus ASCII 帧 / Strict hex parser, validate-then-write |

### 修复 / Fixed

- **全库 POU 缺 `END_FUNCTION` / `END_FUNCTION_BLOCK` 终结符（库级缺陷，R1/R2 两个批次 26 个旧组件全部涉及）**
  - **技术说明**：IEC 61131-3 / CODESYS 关键字规范要求 POU 声明与终结符**成对出现**——`FUNCTION_BLOCK … END_FUNCTION_BLOCK`、`FUNCTION … END_FUNCTION`。终结符缺失时编译器的 POU 边界解析无法闭合（词法分析器持续等待块结束关键字直到文件尾），单文件导入或全库编译直接报「unexpected end of file / block not closed」，**任何一个 POU 缺终结符都会让整个导入失败**，而不是该组件单独编译不过。
  - **为什么属库级而非组件级**：26 个旧组件的逐文件业务逻辑本轮**零改动**（引脚、状态机、故障码全部不变），缺陷不在任何单个组件的实现，而在 R1/R2 批处理流水线的「源码落盘」环节未按 CODESYS 导出格式补写终止关键字——即「文件合法但不符合 CODESYS 导入格式」的生成侧系统性缺口，属库级语法契约。故统一在本轮修复，**旧组件版本号不变**，新组件自 v1.0.0 起即含成对终结符。
  - 由本轮终审机检发现；修复后 40 个 `.st` 全部通过终结符成对性检查，JSONL 语料 26 条旧记录 `output` 已按源文件同步重建（与 `.st` 字节级一致，机检 0 偏差）。

### 变更 / Changed

- `DL_Base` 子库 v1.1.0 → **v1.2.0**（20/20 收口）；`DL_MathData` 子库 v1.1.0 → **v1.2.0**（20/20 收口）；总库 v1.1.0 → **v1.2.0**；注册表 `version = 1.2.0`、`total_components = 40`、`last_updated = 2026-11-15T00:14:39+08:00`。
- **故障码空间扩段**：v1.2.0 起新启用 `16#0002_xxxx` 故障码段（业务/工艺类语义：同步超时、释放不同步、按钮卡死、联锁配置非法、冗余无可用源、切换抖振、统计样本不足、十六进制串非法、折线表非法、多边形退化、两线重合），与既有 `16#0001_xxxx` 参数/循环段并行分配，全库登记于 `LIBRARY_MANUAL.md` 第四节。
- `16#0001_0006`（NaN/Inf）由「预留」转为**实际使用**：`FC_DL_QuickSortLReal` NaN 预扫描拒绝时置该码。
- 新增随组件同文件发布的枚举 10 个：`E_DL_TwoHandState`、`E_DL_InterlockState`、`E_DL_RedundancyPriority`、`E_DL_DeviationPolicy`、`E_DL_ActiveChannel`、`E_DL_RedundState`、`E_DL_RotationState`、`E_DL_StackState`、`E_DL_MedianState`、`E_DL_StatState`。

### 文档 / Documentation

- `DL_Base/MANUAL_DL_Base.md` 新增第 17~20 节（4 个新组件接口表、故障码表、调用示例、联调要点），故障码总表扩至 `16#0002_0006`；红线自检新增 R13 终结符成对项。
- `DL_MathData/MANUAL_DL_MathData.md` 新增第 11~20 节（10 个新组件完整接口表、验收向量、示例），清理 v1.1.0 遗留的无标题重复故障码表；故障码总表扩至 `16#0002_000D`。
- `LIBRARY_MANUAL.md`：状态持有表、RETAIN 纪律（`FB_DL_DutyStandbyRotation`）、故障码总表（新增 `16#0002_xxxx` 段 11 码）、库级测试向量（CRC-32 / LRC / 中值 / 统计 / 排序 / 解析 10 条）、常见陷阱（两遍法方差、ST 禁递归）同步更新。
- `README.md` 徽章与交付清单刷新为 40 项，显著位置标注「Level 0 收口，下一阶段进入 Level 1 DL_Algo」。
- `ROADMAP.md` 勾选 14 项、改写 Round 04 计划、行业待办池扩容（+34 条，覆盖锂电/光伏/半导体/包装/暖通/过程控制）。

### 数据 / Data

- `INDEX_REGISTRY.json`：`total_components` 26 → 40，`version` 1.2.0，`last_updated` 2026-11-15T00:14:39+08:00。
- `_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`：26 → **40 条**；14 条新语料 `output` 与 `.st` 字节级一致，26 条旧语料 `output` 已按终结符补全后的源文件重建，全量机检 0 偏差。

### 说明 / Notes

- 无破坏性变更，无迁移动作：终结符补全不改变任何引脚与行为；编译失败的问题随本轮修复消除。
- 本轮专家召唤记录：原生 `daoli-library-director` 与 `plc-programming-expert` 均报 not available（两次尝试 + 身份探测后仍失败），本轮为**兜底模式**执行（general-purpose 代理 + 强制读取人格规范，双角色分离），规范执行口径与原生模式一致。

---

## [v1.1.0] — 2026-11-14 ｜ 时序引擎与数据结构 / Timing Engines and Data Structures

**阶段**：Phase 1 第二轮批处理 · Level 0 ｜ **新增组件**：12 ｜ **累计**：26 / 10,000 ｜ **修复**：3 ｜ **红线违规**：0

### 新增 / Added

#### DL_Base（7 项，子库 v0.1.0 → v1.1.0）

| 组件 / Component | 类型 | 复杂度 | 说明 / Description |
|---|---|---|---|
| `FB_DL_ExtendedTimer` | FB | 5 | 四模式定时器（TON / TOF / TP / RTO），保持型用差分累加不丢进度，运行中换模式即作废计时 / Four-mode timer with delta-based retentive accumulation |
| `FB_DL_AlarmManager` | FB | 7 | 16 通道三级优先仲裁，先到先得首出锁存，激活/已确认/首出三态正交 / 16-channel arbitration with arrival-order first-out |
| `FB_DL_StepSequencer` | FB | 8 | 通用顺控步引擎：动作外置、逐步超时、暂停/单步/中止，换步屏蔽一拍杜绝连环跳步 / Generic step engine with a one-scan switch mask |
| `FB_DL_WatchdogMonitor` | FB | 4 | 心跳跳变间隔看门狗，跳变过快不锁存告警，上电即武装 / Heartbeat-interval watchdog armed at power-up |
| `FB_DL_PulseGenerator` | FB | 5 | 周期/占空比运行时可调方波，占空比 0/1 退化为恒低/恒高 / Runtime-adjustable square wave |
| `FB_DL_CycleTimeMeasure` | FB | 3 | 扫描周期统计（最近/最小/最大/平均/样本数），时间增量由调用方注入 / Scan-cycle statistics with injected delta |
| `FB_DL_RuntimeMeter` | FB | 4 | 运行分钟/小时 + 启动次数 + 保养到期锁存，整数化累加无漂移 / Runtime meter with integer accumulation |

#### DL_MathData（5 项，子库 v0.1.0 → v1.1.0）

| 组件 / Component | 类型 | 复杂度 | 说明 / Description |
|---|---|---|---|
| `FC_DL_SwapBytes16` | FC | 2 | 16 位字字节互换，纯移位、自逆，无故障码（P3 豁免）/ Shift-only self-inverse byte swap |
| `FC_DL_SwapBytes32` | FC | 4 | 32 位四排布归一化（ABCD/DCBA/BADC/CDAB），附 4×4 互逆矩阵 / Four-layout normaliser with a 4x4 composition matrix |
| `FB_DL_RingBufferLReal` | FB | 5 | 定长 64 的 LREAL 环形 FIFO，满拒写不覆盖，指针纯前向取模 / Fixed 64-slot LREAL ring FIFO |
| `FC_DL_StringTrim` | FC | 3 | 首尾四类空白清理，双向扫描带防死锁 / Two-way guarded whitespace trim |
| `FC_DL_StringSplit` | FC | 6 | 单字符分隔报文拆分，保留空字段（CSV 语义）/ Single-delimiter splitter keeping empty fields |

### 修复 / Fixed

| 组件 | 版本 | 缺陷 / Defect |
|---|---|---|
| `FB_DL_DualEdgeTrig` | 1.0.0 → **1.0.1** | **（专家上报 + 终审确认）**事件校正极性反接：`bRising` / `bFalling` 的与项写反，真实跳变周期被自身屏蔽，两路事件恒 `FALSE`、计数永不增长。构造输入序列复算：修复前 0 上升 0 下降，修复后 2/2，与理论一致 |
| `FB_DL_PulseGenerator` | 1.0.0 → **1.0.1** | **（终审抽查发现）**换相后相位定时器不清零：标准定时器只在本体输入 `FALSE` 时清 `ET`，仅改 `PT` 不会清零。占空比 0.5 时低相位塌缩为 1 个扫描周期，占空比 0.3 / 周期 1000 ms 时实际周期只有 700 ms。改为换相后断拍一拍（标志延后一拍提交） |
| `FB_DL_StepSequencer` | 1.0.0 → **1.0.1** | **（终审抽查发现）**故障码不锁存：主体开头无条件清零，故障态分支不再重写，进故障后下一拍 `bError = TRUE` 而 `uErrorId` 读回 0。改为故障期间保留进入时的故障码，仅复位沿清零 |

### 变更 / Changed

- `DL_Base` 子库 v0.1.0 → v1.1.0（16/20）；`DL_MathData` 子库 v0.1.0 → v1.1.0（10/20）；总库 v0.1.0 → v1.1.0。
- `FB_DL_WatchdogMonitor` 依赖 `FB_DL_DualEdgeTrig` 时**只取电平输出**，跳变判定本地派生（依赖收窄留档，R11）；上游 v1.0.1 修复后保留本地口径，行为等价，留待 Level 1 统一评估。
- 故障码分配表新增 `16#0001_0008` ~ `16#0001_000E` 七码，全库唯一。

### 文档 / Documentation

- 新增 `DL_Base/MANUAL_DL_Base.md` 第 10~16 节（7 个新组件完整引脚表、故障码表、示例、联调要点），故障码总表扩到 14 码。
- 新增 `DL_MathData/MANUAL_DL_MathData.md` 第 6~10 节，含 `FC_DL_SwapBytes32` 的 4×4 互逆矩阵与 `16#12345678` 复算向量、环形缓冲回绕序列表。
- `DL_Base/VERSION.md` / `DL_MathData/VERSION.md` 追加 v1.1.0 小节。
- `README.md` 徽章与交付清单刷新为 26 项；`LIBRARY_MANUAL.md` 故障码总表与测试向量表同步；`ROADMAP.md` 勾选 12 项并补行业待办池；`OPEN_SOURCE_SHOWCASE.md` 新增 StepSequencer 与 AlarmManager 两个明星组件。
- 新增 `_Staging_Raw/2026-11-14/BATTLE_REPORT_R2.md`（第二轮战报）。

### 数据 / Data

- `INDEX_REGISTRY.json`：`total_components` 14 → 26，26 条记录字段完整、路径全部存在、无重复。
- `_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`：26 条；本轮 3 条修复组件的 `output` 已按源文件重写，并补写修复根因到 `architecture_thought`。

### 说明 / Notes

- 无破坏性变更，无迁移动作：3 处修复均未改动任何引脚。
- 本轮终审新增一条经验：**文本机检通过 ≠ 语义正确**，时序类组件必须构造输入序列复算（见 `AGENT_EVOLUTION_LOG.md` Round 02）。

---

## [v0.1.0] — 2026-11-14 ｜ 首版冷启动 / Initial Seed Release

**阶段**：Phase 1 种子冷启动 · Level 0 ｜ **新增组件**：14 ｜ **累计**：14 / 10,000 ｜ **红线违规**：0

### 新增 / Added

#### DL_Base（9 项，子库 v0.1.0）

| 组件 / Component | 类型 | 复杂度 | 说明 / Description |
|---|---|---|---|
| `FB_DL_SignalDebounce` | FB | 5 | 上升/下降延时独立可调的触点消抖；首扫零假边沿、延时超限钳位告警、边沿单周期脉冲 / Debounce with independent rise and fall delays; no false edge on first scan, delay clamping, one-scan edge pulses |
| `FB_DL_DualEdgeTrig` | FB | 2 | 上升沿/下降沿/任意跳变三事件 + 当前电平 + 饱和计数（不回绕）/ Rising, falling and any-transition pulses with level and saturating counters |
| `FC_DL_BitGet` | FC | 2 | 32 位字位提取，索引越界先判后算 / Bounds-checked bit extraction, validated before any shift |
| `FC_DL_BitSet` | FC | 3 | 纯函数置位/清零，越界原样返回原字 / Pure set/clear returning the source word unchanged on illegal index |
| `FC_DL_BitCount` | FC | 3 | Brian Kernighan 置位计数，带防死锁计数器 / Kernighan popcount with a deadlock guard |
| `FC_DL_PackBitsToWord` | FC | 2 | 16 路 BOOL 打包为 `WORD`，索引 0 = LSB / Packs 16 BOOLs into a `WORD`, index 0 = LSB |
| `FB_DL_UnpackWordToBits` | FB | 2 | 状态字解包 + 取反掩码 + 整字变化脉冲 + 置位总数 / Word unpacking with invert mask, change pulse and popcount |
| `FC_DL_GrayToBinary` | FC | 4 | 1~32 位可变位宽格雷码解码，位宽 32 特判防移位溢出 / 1..32-bit Gray decoding with a width-32 shift-overflow special case |
| `FC_DL_BinaryToGray` | FC | 3 | 二进制转格雷码，与前者严格互逆 / Binary to Gray, strict inverse of the decoder |

#### DL_MathData（5 项，子库 v0.1.0）

| 组件 / Component | 类型 | 复杂度 | 说明 / Description |
|---|---|---|---|
| `FC_DL_LinearScale` | FC | 4 | 模拟量线性标定：防除零、反向量程、双侧钳位、百分比输出 / Analog scaling with divide-by-zero guard, reverse ranges, two-sided clamping and percent output |
| `FC_DL_Deadband` | FC | 3 | 移位型（连续）/ 归零型（阈值开关）双语义死区 / Shift-type and zero-type deadband in one function |
| `FC_DL_Hysteresis` | FC | 4 | 施密特迟滞比较器，状态经 `VAR_IN_OUT` 交还调用方 / Schmitt hysteresis with caller-held state via `VAR_IN_OUT` |
| `FB_DL_MovingAverage` | FB | 6 | O(1) 递推滑动平均：两阶段启动、窗口运行时重建、浮点漂移校正 / O(1) recursive moving average with two-phase startup, runtime window rebuild and drift correction |
| `FC_DL_Crc16Modbus` | FC | 5 | Modbus RTU CRC-16 逐位法，长度越界钳位，附 4 条实算验收向量 / Bit-wise Modbus CRC-16 with length clamping and four verified vectors |

### 文档 / Documentation

- 新增 `README.md`：项目定位、六大目录结构、快速开始、徽章、MIT 许可证建议。
- 新增 `LIBRARY_MANUAL.md`：跨子库调用规范、状态持有纪律、故障码总表。
- 新增 `DL_Base/VERSION.md`、`DL_Base/MANUAL_DL_Base.md`（9 个组件完整引脚表与调用示例）。
- 新增 `DL_MathData/VERSION.md`、`DL_MathData/MANUAL_DL_MathData.md`（5 个组件完整引脚表与调用示例）。
- 新增 `AGENT_EVOLUTION_LOG.md`：双专家协作流水线复盘、边界案例与编码范式沉淀。
- 新增 `OPEN_SOURCE_SHOWCASE.md`：明星组件推广文案（中英双语）。
- 新增 `_Staging_Raw/2026-11-14/BATTLE_REPORT.md`：首轮自动化构建战报。
- 更新 `ROADMAP.md`：14 项勾选完成，批处理追踪记录刷新。

### 数据 / Data

- `INDEX_REGISTRY.json`：`total_components` 0 → 14，14 条机读记录（名称、子库、类型、路径、标签、复杂度）。
- `_AI_Training_Dataset/daoli_st_sft_dataset.jsonl`：新增 14 条 SFT 语料（`instruction` / `architecture_thought` / `output` 三元组），累计 14 条。

### 修正 / Fixed

- **CRC 单字节验收向量勘误**：需求规格书给出的 `0x0C → 0x911E` 经穷举 `0..255` 复算无法复现，改为实算值 `0x0C → 0x45BF`，并在 `FC_DL_Crc16Modbus` 头注释与 `MANUAL_DL_MathData.md` 留档。

### 说明 / Notes

- 无破坏性变更，无迁移动作。
- `FC_DL_PackBitsToWord` 显式豁免 `uErrorId`（编译期无失败路径），已备案。
- `FC_DL_Hysteresis` 保持 `FC_` 形态 + `VAR_IN_OUT` 状态，未改为 FB。
- `FB_DL_MovingAverage` 按规格书 B7 刻意不设采样沿实例，采样语义统一为 `bSample` 电平。

---

## 未来版本 / Unreleased

- **v1.7.1 候选**：终审观察项 3 处评估（泄漏率压降-流量统一换算 FC / Cam 相位商域落点 / Gantry 同值阈值组态约束）；`DL_Base` / `DL_MathData` 长期未动可排回补。
- **v1.8.0 候选**：R9 计划——**P0 CODESYS 最小工程编译验证必须启动**（连续七轮悬置，全库 120 个 POU 真实编译 + R24/R25/R27 家族组件验收向量逐拍回放）；T1-7 PLCnext / T1-8 GitHub topics 开组候选；DL_Motion 运动叠加补偿、DL_Process 拾放工站。

---

## v2.8.0 ｜ 2026-11-16 ｜ R19：Level 0 补位 + 控制律/设备健康/运动/工艺 20 件

**新增 20 件（机检 20/20 PASS，JSONL 324 条 sha256 全 MATCH）**：
- `FC_DL_DintMsToTod`：DINT 当日毫秒→TOD 反向转换双向对收口（DL_MathData）。
- `FC_DL_TimeRatioCalc`：TIME 比值→LREAL 百分比，除子零故障闸（DL_MathData）。
- `FC_DL_RatioToPwrDb`：功率型 dB 反向件，与 PwrDbToRatio 成对（DL_MathData）。
- `FC_DL_LintToUdintSat`：LINT→UDINT 交叉域饱和，负值/正向双闸 + 无损模式（DL_MathData）。
- `FC_DL_ModbusRtuFrameCheck`：Modbus RTU 帧 CRC16 校验收口（DL_MathData）。
- `FB_DL_BitShiftRegister`：宽度可组态位串移位寄存器，时序层（DL_Base）。
- `FB_DL_FlowSqrtExtract` / `FB_DL_RatioController` / `FB_DL_LeadLagCompensator` / `FB_DL_AutoTuneRelay`：流量开方低切 / 比值控制 / 超前滞后 Tustin / 继电反馈自整定（DL_Algo）。
- `FB_DL_DeviceHealthArbiter` / `FB_DL_ProfinetAlarmDiag` / `FB_DL_EscChuckCurrentMonitor` / `FB_DL_DeviceParamWrite`：健康仲裁 / PROFINET 八类诊断 / ESC 电流监视 / 参数写回事务（DL_Device）。
- `FB_DL_ExternalEncoderScaler` / `FB_DL_CamPhaseTrim` / `FB_DL_FilmWebCenter` / `FB_DL_WindingLayerCounter`：编码器折算 / 凸轮相位修调 / 膜卷纠偏 / 层数计数（DL_Motion）。
- `FB_DL_DrumLevelThreeElem` / `FB_DL_VacCupRingCtrl`：汽包三冲量 / 多吸盘拾放（DL_Process）。

**终审修复（R19 抽检 6 件命中 2 件，均升 v1.0.1 并重注入 JSONL）**：
- `FB_DL_BitShiftRegister`：溢出位提取改为跟随移位方向（右移取 bit0），v1.0.0 右移方向误用最高有效位掩码。
- `FB_DL_DrumLevelThreeElem`：水位项符号 + → −（负反馈），v1.0.0 构成正反馈（水位越低越不补水），安全级缺陷。

**码位裁定**：码位总账正则限定 `16#000[1-5]_` 段重提取（掩码常量 16#8000_0000 误录教训，BitShiftRegister 码位订正为 0408/0409/032A/032B/032C）；全库 CLASH/DUP = NONE；游标更新——0001 信息 040C/故障 0330、0002 CC=2B、0003 信息 0172/故障 033C、0004 信息 01D5/故障 02EA、0005 信息 01DA/故障 030B。子库版本：Base/MathData v1.13.0、Algo v1.9.0、Device/Motion/Process v0.11.0。


## v2.11.0 ｜ 2026-11-16 ｜ R22：结构补位轮——轴侧安全层开层 + 过程单元保护/顺控 + 定宽字段族 20 件

**新增 20 件（机检 20/20 PASS fail=0，新增 6,618 行，registry 364→384，counts 73/148/38/61/30/34，JSONL 384 条全 sha256 MATCH，码位 CLASH=NONE）**：
- `FC_DL_IntToFixedField` / `FC_DL_FixedFieldToInt` / `FC_DL_LrealToFixedField`：整数→定宽零/空格填充字段（负域取模防 DINT 最小值）、定宽字段→整数（前导剥离 + 非法字符定位 + 负域累乘饱和）、浮点→定宽定点文本（禁 `LREAL_TO_STRING`、R79 精确非有限判据、round-trip 验收）——T2-1 LGF「数值→定宽字段对齐」子族 ✔ 收口（DL_MathData ×3）。
- `FC_DL_FirstSetBit` / `FB_DL_FrequencyMeasure`：位串族第四轴「搜索」（高位/低位优先 + 常量掩码避 `SHL(x,64)`）、门时计数测频（TON 门 + R_TRIG 计数 + ±1/tGateTime 不确定度显式声明）——T0 变体线零检索（DL_Base ×2）。
- `FB_DL_CrossLimitSelect` / `FB_DL_ExcessAirTrim`：燃烧双交叉限幅（空燃比先行裕度）、氧量修正（死区 + 限幅 + 负荷变化率冻结）——DL_Algo ×2。
- `FB_DL_SlitValveInterlock` / `FB_DL_PressureReliefMonitor` / `FB_DL_SteamTrapMonitor` / `FB_DL_LevelRadarValidate`：真空闸阀互斥互锁（三条件掩码 + 双路指令先清后置）、安全阀起跳/回座台账（回座比迟滞 + NE107 分级）、疏水阀温差三判据（冷态冻结判定）、雷达液位回波四判据仲裁——DL_Device ×4。
- `FB_DL_AxisBrakeSeq` / `FB_DL_VirtualMasterAxis` / `FB_DL_MotionCmdQueue` / `FC_DL_CamTableValidate` / `FB_DL_AxisInPosMonitor`：**轴侧安全层开层**——伺服抱闸时序（先释放后使能 / 先静止后抱闸再断使能）、虚拟主轴相位源（斜坡积分 + LREAL 精度门冻结）、运动指令排队（PLCopen Buffered 语义，Blending 明确不立）、凸轮表四判据校验（全掩码不早退）、到位稳定判定（bSettled 出窗即清）——DL_Motion ×5。
- `FB_DL_CompressorSurgeGuard` / `FB_DL_ColumnDpCtrl` / `FB_DL_InertPurgeSeq` / `FB_DL_BatchTransferSeq`：压缩机防喘振（最小流量线 + 快开慢关 + R36 首拍跟踪）、精馏塔压差增量控制（防冲塔优先）、氮气置换顺控（一相一只 TON）、批次转移顺控（阀到位才启泵、排空验证）——DL_Process ×4。

**终审修复（R22 抽检 10 件命中 4 件轻微 + 1 件中等，4 件升 v1.0.1 并重注入 JSONL）**：
- `FB_DL_MotionCmdQueue`（v1.0.1）：eSending 进相后队列被 bClear/轴故障清空时发令被跳过却仍转 eWaitDone，空等永不到来的轴 Done（竞态挂死）——发令被跳过时改回 eIdle。
- `FB_DL_VirtualMasterAxis`（v1.0.1）：eFault 态下 bError 仅故障检出拍为真，参数修复次拍即恢复积分，与「eFault 冻结」头注释矛盾——段 6 积分加 eFault 相位门控，恢复仅经失能复位或 bPhaseReset。
- `FB_DL_AxisBrakeSeq`（v1.0.1）：tBrakeRelease 引脚注释「有反馈时作为最短等待」与实现「反馈到达即采信」不符——注释对齐实现，并显式声明 tFbTimeout > tBrakeRelease 配置约束（两窗同拍起算）。
- `FB_DL_BatchTransferSeq`（v1.0.1）：总时长超时分支（0315）漏置 `bError := TRUE`（R45 纪律违例，bValid 误判可用）——补置。
- `FB_DL_SCurveGenerator` / `FB_DL_PulseDirStepper`：历史 JSONL 换行口径漂移（LF vs CRLF）修复，全库 sha 复验恢复全 MATCH（暴露口径：收尾脚本此前只验末 20 行，本轮起全量校验，规则 R102）。

**风险挂账（未修复，入 R23 待办）**：`FB_DL_BatchTransferSeq` 中止路径「先停泵后关阀」仅单拍赋值次序成立，缺真实物理时序分隔（中等·安全相关，修复方案见 ROADMAP §24.1）。

**源矩阵**：T1-3 OSCAT Network ◐→✔ 收口（总监签字：RTU 帧校验 R19 收口 + ASCII 帧 LRC 判薄件不立）；T2-1 Converter「数值→定宽字段」子族 ✔ 收口；其余 13 行按 RAW_NOTES_R22 §4 备注回写。码位 100 槽（信息 40 / 故障 60）跨文件零冲突；收口游标 0001 `0466`/`03B7`、0002 CC=`2D`、0003 `017A`/`0348`、0004 `01DF`/`02F9`、0005 `01E2`/`0317`。子库版本：Base v1.17.0 / MathData v1.16.0 / Algo v1.10.0 / Device v0.12.0 / Motion v0.12.0 / Process v0.12.0。

## v2.12.0 ｜ 2026-11-17 ｜ R23：行业纵深轮——焓湿图原子族 + NE107 多源聚合 + 行业工艺站 20 件 / Round 23 — Psychrometric Atoms, NE107 Aggregation and Industry Process Stations

**阶段**：Phase 1 第二十三轮（T1-2 OSCAT Building 焓湿图族 + T2-8 NE107 + ROADMAP P1 ×14）｜ **新增组件**：20（`DL_Algo` 5 ｜ `DL_Device` 6 ｜ `DL_Process` 7 ｜ `DL_Motion` 2，合计 **3,754 行**）｜ **累计**：**404 / 10,000**（距 500 冲刺差 96）｜ **子库版本**：`DL_Algo` v1.10.0→**v1.11.0**、`DL_Device` v0.12.0→**v0.13.0**、`DL_Process` v0.12.0→**v0.13.0**、`DL_Motion` v0.12.0→**v0.13.0** ｜ **JSONL**：**404 条**，全量 sha256 MATCH ｜ **机检**：fail=12 全为 `E_DL_Ne107Status` 跨文件属主误报豁免（属主 `I_DL_DeviceHealth.st`）｜ **码位**：CLASH=NONE ｜ **修复**：`FB_DL_BatchTransferSeq` v1.0.1→**v1.0.2**（R22 挂账闭合）｜ **终审**：8 件高风险定向抽查，2 PASS / 4 件轻微当场修升 v1.0.1 / 2 件严重挂账 R24 ｜ **属主裁定**：Magnus-Tetens 常数唯一属主 `FC_DL_VaporPressureSat`，`FC_DL_DewPointCalc` / `FC_DL_HumidAirEnthalpy` 头注释追加属主转移声明升 v1.0.1（逻辑零改动）

### 新增 / Added

| 子库 | 组件 | 类型 | 说明 |
|---|---|---|---|
| DL_Algo | `FC_DL_VaporPressureSat` / `FC_DL_HumidityRatioCalc` / `FC_DL_WetBulbTempCalc` / `FC_DL_RhFromDewPoint` / `FC_DL_MixAirStateCalc` | FC×5 | 焓湿图原子族（T1-2 OSCAT Building 行为定义 clean-room）：饱和压族属主（Magnus-Tetens 过水面参数化，族内唯一公式源）/ 含湿量 / 湿球温度（Stull 2011 湿度计方程）·**挂账 R24** / 露点反算 RH / 回风新风混合点（质量守恒 + 结露预警） |
| DL_Device | `FB_DL_HealthAggregator` / `FB_DL_OvenDoorInterlock` / `FB_DL_ChamberGateValve` / `FB_DL_RobotGripVerify` / `FB_DL_FilterDpMonitor` / `FB_DL_TankN2BlanketCtrl` | FB×6 | 健康联锁族：NE107 多源"最差者胜"聚合仲裁（T2-8 落地）/ 烘箱炉门三联锁 / 真空腔闸阀互锁 / 机械手夹持确认 / 过滤器压差寿命（NE107 出口）/ 储罐氮封双分程 |
| DL_Process | `FB_DL_ElectrolyteDosingSeq` / `FB_DL_NailMachineSeq` / `FB_DL_LamHeaterZoneSync` / `FB_DL_SteamCondensatePot` / `FB_DL_AirCompDutyN2` / `FB_DL_BoilerThreeElement` / `FB_DL_HumidityOverride` | FB×7 | 行业工艺站：电解液定量注液 ISA-88 节拍链 / 打钉机顺控 / 层压机多温区同步 / 凝液罐液位排放顺控 / 空压制氮联产轮值 / 锅炉三冲量给水 / 除湿优先仲裁 |
| DL_Motion | `FB_DL_WaferCountAxis` / `FB_DL_BagFeedDancerSync` | FB×2 | 晶圆计数轴（编码器分频 + 片位同步）/ 制袋供膜摆辊同步（线速前馈 + 摆辊 PI，拓扑假设头注释留档） |

### 修复 / Fixed（R23 终审 + 承接 R22 挂账）

| 组件 | 版本 | 级别 | 缺陷 | 处置 |
|---|---|---|---|---|
| `FB_DL_BatchTransferSeq` | v1.0.1→v1.0.2 | 中等（R22 挂账） | bAbort「先停泵后关阀」缺物理时序分隔 | 两段化：xCoastStop + tPumpCoastTime 惰转窗→关阀，新故障码 0005_0317，五条验收向量推演通过 |
| `FC_DL_MixAirStateCalc` | v1.0.0→v1.0.1 | 轻微 | 段 2 非有限闸漏查 fOaFrac（NaN 直通 bValid=TRUE） | 当场修：闸门补全六输入，契约不变 |
| `FB_DL_HumidityOverride` | v1.0.0→v1.0.1 | 轻微 | 注释-实现漂移（「保持末态」vs 实现「转故障退出覆盖 + 01EE 显式声明」） | 当场修：注释按实现口径对齐，逻辑零改动 |
| `FB_DL_ElectrolyteDosingSeq` | v1.0.0→v1.0.1 | 轻微 | tSettleTime > 步 1 超时 / tCoastTime=0 无组态闸（结构性超时/中止永不收口） | 当场修：段 3 补组态一致性闸归 0318，契约不变 |
| `FC_DL_DewPointCalc` / `FC_DL_HumidAirEnthalpy` | v1.0.0→v1.0.1 | 文档 | Magnus-Tetens 常数属主裁定回写 | 头注释属主转移声明，逻辑零改动 |
| `FC_DL_WetBulbTempCalc` | v1.0.0→v1.0.1（警示） | **严重（挂账 R24）** | γ 常数 1000 倍量纲错位 + 定点迭代在 e_s'(Tw)/(γ·p)>1 区间结构性发散，正常工况误报 2F11 | 头注释挂账警示（禁用于生产），R24 立项改二分法 + 量纲组合表纪律 |
| `FB_DL_TankN2BlanketCtrl` | v1.0.0（挂账 R24） | 轻微→中等 | 高压分界无迟滞回差，bVentCmd 分界处逐拍抖振（0184 仅提示不消振） | 挂账 R24：复用 DL_N2_BAND_TOL 作回差，补验收向量 |

> **R23 编码侧漏（主控收口拦下）**：①`FB_DL_BoilerThreeElement` 两处未声明标识符 `fSteamFlow`（输入名实为 `fSteamFlowTh`，编译阻断级，收口时修正）；②`FB_DL_HealthAggregator` 调用示例注释含省略号占位符（语义化改写）。

---

## v2.13.0 ｜ 2026-11-17 ｜ R24 行业纵深轮（零检索轮：ROADMAP 行业池 + LGF 仿射族）

### 新增 / Added（20 件，4,551 行）

| 子库 | 组件 | 码位 |
|---|---|---|
| DL_MathData +3 | `FC_DL_Affine2DCompose` / `FC_DL_Affine2Apply`（**T2-1 LGF 仿射变换族开族**，clean-room）/ `FC_DL_FanLawRootCalc`（§661，FB→FC 改判纯函数） | 0001_0466~046E / 03B7~03BC |
| DL_Algo +1 | `FB_DL_GasDensityComp`（理想气体密度温压补偿，M 引脚自持） | 0002_32xx（CC 0x32，实测空闲起配） |
| DL_Device +5 | `FB_DL_StepperMicroFeedPulseEquiv` / `FB_DL_PumpDryRunGuard`（§452）/ `FB_DL_CoilFrostWindow`（§727）/ `FB_DL_ElectrolyteMoistureGuard`（§693）/ `FB_DL_MfcSetpointRamp`（§710） | 0003_0186~018F / 035A~0368 |
| DL_Motion +4 | `FC_DL_TrackerBacktrackCalc`（§360）/ `FB_DL_WindingAlignEdge`（§806）/ `FB_DL_SolderRibbonTension`（§703）/ `FB_DL_TrackerSnowShedAngle`（§812） | 0004_01E3~01EA / 0300~030B |
| DL_Process +7 | `FB_DL_StringIVTrace`（P0 §228）/ `FB_DL_ChamberPumpDownProfile`（§708）/ `FB_DL_CartonErectorStation`（P0 §652）/ `FB_DL_TrackBarcodeTrace`（P0 §469）/ `FB_DL_TankDosingMulti`（§510）/ `FB_DL_BatchDeviationAlarm`（§734）/ `FB_DL_RollCompressForceBalance`（§805） | 0005_01F0~01FD / 032D~0341 |

### 修复 / Fixed（R23 P0 挂账关闭 2 件 + R24 终审 2 件）

| 组件 | 版本 | 级别 | 缺陷与处置 |
|---|---|---|---|
| `FC_DL_WetBulbTempCalc` | v1.0.1→**v1.1.0** | 严重（R23 挂账） | γ 量纲 1000 倍错位 + 定点迭代结构性发散 → **二分法重写**（g 单调增、0.05 摄氏度精度、40 次防死锁上限），引脚/码位契约全保留，收敛域声明入头注释 |
| `FB_DL_TankN2BlanketCtrl` | v1.0.0→**v1.0.1** | 中等（R23 挂账） | 泄放/补氮退出迟滞回差：新增 `fVentHystKpa`（默认 0.2 kPa），非法回退默认仍越跨度按半宽钳定，不新占码位 |
| `FB_DL_CartonErectorStation` | v1.0.0→**v1.0.1** | **严重（R24 终审）** | fbSeq.bReset 恒 FALSE × 步进引擎 bError 锁存型 → 步超时后故障恢复死锁；改仅 eFault 相透传复位 |
| `FB_DL_PumpDryRunGuard` | v1.0.0→**v1.0.1** | **严重（R24 终审）** | 默认参数自违反 R100 配比约束（学习窗 5S ≥ 去抖窗 3S）出厂即 035E → 默认去抖窗 3S→8S；③注释-实现漂移对齐 |

### 收口 / Closeout

- registry v2.12.0→**v2.13.0**，404→**424** 件（counts Base 73 / MathData 151 / Algo 44 / Device 72 / Motion 36 / Process 48）；JSONL **424 行全量 sha256 MATCH**（终审重注入 2 行后复验，20 条 noPOU 为 `INTERFACE` 历史行正则盲区留档）；CLASH=NONE；机检 fail=1 全为误报裁定（TrackBarcodeTrace eNone 落 ELSE 安全侧，RAW_NOTES_R24 §6）；真缺陷 6 处收口已修（枚举单冒号 3 / 孤立分号 3）+ 编码自检修 9 处。
- 终审 7 件定向抽查：**5 PASS / 2 件严重当场修升 v1.0.1**（上表）；轻微留档 4 条（GasDensityComp eIdle 退化相与 bReset 电平注释、BatchDeviationAlarm 01FA/01FB 同拍互掩、CartonErector 组态闸关键步抽查口径、PumpDryRunGuard 抑制窗满后跳闸保持语义）。
- 子库升版：DL_MathData v1.16.0→v1.17.0 / DL_Algo v1.11.0→v1.12.0 / DL_Device v0.13.0→v0.14.0 / DL_Motion v0.13.0→v0.14.0 / DL_Process v0.13.0→v0.14.0；五本 MANUAL 各追加 R24 接口表节；ROADMAP 勾选 16 项 + 增补 6 条。

*Last updated: 2026-11-17（R24 追加 v2.13.0 条目）*

---

## [v2.14.0] — 2026-11-17 ｜ R25 暖通深度 + 洁净室/锂电/光伏工艺 20 件 / Round 25 — HVAC Depth, Cleanroom, Lithium and PV Process Templates

**阶段**：Phase 1 第二十五轮 ｜ **新增组件**：20（`DL_MathData` 1 ｜ `DL_Algo` 4 ｜ `DL_Device` 4 ｜ `DL_Motion` 2 ｜ `DL_Process` 9，合计 **7,097 行**（终审修复后 **7,174 行**））｜ **累计**：**444 / 10,000** ｜ **子库版本**：`DL_MathData` v1.17.0→**v1.18.0**、`DL_Algo` v1.12.0→**v1.13.0**、`DL_Device` v0.14.0→**v0.15.0**、`DL_Motion` v0.14.0→**v0.15.0**、`DL_Process` v0.14.0→**v0.15.0** ｜ **码位**：0001 `0471`/`03BF`、0002 下一 CC `0x37`、0003 `0198`/`0375`、0004 `01EF`/`0312`、0005 `0412`/`035D`（CLASH=NONE）｜ **机检**：19/20 PASS，1 项为**纯函数件 4 槽码位口径误报**（`FC_DL_Affine2DInvert` 按 §3.1 只分配 4 码，「5~6 槽」规则对纯函数件不适用，裁定 PASS，规则口径列入待修）｜ **JSONL**：**444 条**全量 sha256 MATCH ｜ **终审**：8 件定向推演 → 4 PASS / 3 修 / 1 挂账，交叉扫描另命中 3 件同类缺陷一并修，合计 **6 件升 v1.0.1** ｜ **距 500 冲刺**：差 56 件

### 新增 / Added

| 子库 | 组件 | 类型 | 说明 |
|---|---|---|---|
| DL_MathData | `FC_DL_Affine2DInvert` | FC×1 | 二维仿射矩阵求逆（2×2 伴随 + 平移列反算），奇异输出全零矩阵、不泄半逆；仿射「合成-应用-逆」三元闭环齐备 |
| DL_Algo | `FB_DL_ParticleCounterStat` | FB×1 | 洁净室粒子计数 ISO 14644-1 等级判定（表驱动免幂运算 + 失采识别 + 等级清零安全侧） |
| DL_Algo | `FB_DL_CoolingTowerApproachCalc` | FB×1 | 冷却塔逼近度与加/减风机台数建议（湿球组合调用 + 逼近度为负判传感器可疑） |
| DL_Algo | `FB_DL_DuctStaticReset` | FB×1 | 风管静压设定重置（最不利阀位 + 死区 + 限斜率 + 能力不足如实上报） |
| DL_Algo | `FB_DL_DewpointReset` | FB×1 | 冷冻水供水温度按露点重置（露点 + 安全余量 + 斜率限制；除湿能力不足报出而非静默顶上限） |
| DL_Device | `FB_DL_InverterGridSync` | FB×1 | 逆变器并网四窗核对与合闸许可（只出许可不控合闸，四窗映射 WORD 掩码） |
| DL_Device | `FB_DL_HeatPumpDefrost` | FB×1 | 空气源热泵三条件除霜（最小间隔 + 超时强制退出回制热） |
| DL_Device | `FB_DL_VavBoxCtrl` | FB×1 | 压力无关型 VAV 风量闭环（PI 组合调用 + 设定/开度双限幅 + 反馈无效保持开度） |
| DL_Device | `FB_DL_WaferMapping` | FB×1 | 晶圆盒槽位 Mapping（片位图 + 空位/双片/斜插三分型 + 边界防护） |
| DL_Motion | `FB_DL_StackingAlignCtrl` | FB×1 | 叠片机 CCD 纠偏（标定阵经 `FC_DL_Affine2DInvert` 求逆 + 行程限幅 + NG 锁存至复位） |
| DL_Motion | `FB_DL_LabelApplySync` | FB×1 | 贴标同步出标（编码器提前量 + 饱和钳位 + 低速暂停出标） |
| DL_Process | `FB_DL_RoomClimateCtrl` | FB×1 | 房间温湿度双回路耦合（双 PID 带符号分程 + 防结露联锁 + 冷侧优先互斥仲裁） |
| DL_Process | `FB_DL_WeightCheckReject` | FB×1 | 动态称重与剔除（滤波窗 + 剔除器拒动诊断 + 无料跳过 + 停线判据） |
| DL_Process | `FB_DL_CasePackerPattern` | FB×1 | 装箱排列图案（容量钳位 + 交错/层旋转 + 末层留空位提示） |
| DL_Process | `FB_DL_BatteryTestCycler` | FB×1 | 单通道充放电工步机（恒流/恒压/静置七步 + 安时积分饱和 + 温度电压硬判断流） |
| DL_Process | `FB_DL_PalletizerLayerSeq` | FB×1 | 码垛层排布顺控（层容量两取向自算 + 奇偶层旋转走 `FC_DL_Affine2Apply` + 取放握手重试） |
| DL_Process | `FB_DL_SplicerAutoJoint` | FB×1 | 自动接膜零停机顺控（余量按面积折算 + 速度同步双条件 + **未同步绝不裁切**） |
| DL_Process | `FB_DL_ChillerSeqMgr` | FB×1 | 冷水机组群控（双延迟加减机 + 轮值委托 `FB_DL_DutyStandbyRotation` + 供水低温强制减机） |
| DL_Process | `FB_DL_FormationChannelMgr` | FB×1 | 化成/分容多通道调度（分配 + 异常通道隔离锁存 + 批次台账） |
| DL_Process | `FB_DL_SolarStringGroundFault` | FB×1 | 光伏组串对地绝缘阻抗（不平衡电桥 + 完全平衡退化显式分支 + 分级确认锁存） |

### 修复 / Fixed（R25 终审，对外引脚契约零变更，均升 v1.0.1）

| 组件 | 版本 | 级别 | 缺陷 | 处置 |
|---|---|---|---|---|
| `FB_DL_PalletizerLayerSeq` | v1.0.0→**v1.0.1** | 中等 | 旋转层阵外平移量用整条托盘长（1200×1000 配 400×300 箱体时首行落点得 1200，加足迹 300 越界到 1500）；且 `bPalletDone` 在 `ePalletEnd` 相内先置 TRUE 再同拍置 FALSE，脉冲永不外显 | 平移量改为 `(nRowsEff−1)×箱宽`；撤销点移交 `eIdle` 相（恰好一拍 TRUE） |
| `FB_DL_SolarStringGroundFault` | v1.0.0→**v1.0.1** | 轻微（域端点） | 预警阈值可被配到 ≥ 上限哨兵 `1.0E9 kΩ`，完全平衡退化分支的哨兵值会被判成「低于预警阈值」而误报警 | 组态闸补 `fWarnKOhm >= DL_SGF_R_MAX → 035A` |
| `FB_DL_VavBoxCtrl` | v1.0.0→**v1.0.1** | 中等 | 非有限闸的安全侧赋值写 `fOpenMinPct`，而下限脚本身在本闸判定集合内 → 下限脚为 NaN 时把 NaN 当安全值出口（安全侧自我失效） | 先算可用下限 `fFloorPct`（脚非有限回默认 20%），闸内统一用 `fFloorPct` |
| `FB_DL_RoomClimateCtrl` | v1.0.0→**v1.0.1** | 中等（安全侧） | PID 件失能时输出回 `rOutMin=−100%`，经带符号分程映射成 100% 冷却；四阀归零要等下一拍 `eIdle`，失能沿那一拍破坏「失能=四阀回 0%」契约 | CASE 之后补段 11 失能出口收口，失能电平期间四阀强制 0% |
| `FB_DL_BatteryTestCycler` | v1.0.0→**v1.0.1** | 中等（诊断保真） | `eFault(99)` 无 CASE 标签，落进 ELSE 兜底支路每拍把 034B/034C 覆盖成 034D「非法状态」，激励消失后真因码丢失 | 补 `eFault` 独立 CASE 标签，故障码改写权归入口闸 |
| `FB_DL_SplicerAutoJoint` | v1.0.0→**v1.0.1** | 中等 | `eSyncWait` 只有 `bSyncOk` 一个事件出口，`bNewRollReady` 撤销后滞留且预加速指令长期拉住空卷（R98 家族缺「进相前置消失」出口） | 补 `ELSIF NOT bNewRollReady → ePreAccel`（两相裁切指令均 FALSE，安全铁律不受影响） |

### 挂账 / Carried Over（R106 第二档，下轮立项）

| 项 | 级别 | 复现条件 | 拟修方案 |
|---|---|---|---|
| `FB_DL_SplicerAutoJoint` 同步相无自有超时 | 中等 | 新卷就绪但速度差持续超容差 → 同步相无限期停留（`tPreAccelMax` 只在预加速相计时） | 新增 `tSyncMax`（MINOR）或把同步相并入 `tPreAccelMax` 计时窗；验收向量：速度差恒定 5%、容差 2% → 超时后置 0351 且裁切指令全程 FALSE |
| 批次共性：`eFault` 枚举无 CASE 标签（6 件） | 轻-中（诊断保真） | `ParticleCounterStat` / `CoolingTowerApproachCalc` / `InverterGridSync` / `HeatPumpDefrost` / `DuctStaticReset` / `DewpointReset`：激励消失后 ELSE 兜底码覆盖真因码（安全侧不变，故障仍锁存） | 统一补 `eFault` 标签（安全侧输出照抄 ELSE、码保持、零码兜底），并新增机检规则「枚举成员集合 ⊆ CASE 标签集合」 |

### 勘误 / Spec Errata（总监独立验算裁定）

- **§4.16 层容量算术**：派单验收向量①写「托盘 1200×1000、箱 400×300 → 容量 6」，实测 `floor(1200/400)×floor(1000/300)=3×3=9`（旋转取向 `4×2=8`），编码者判定「派单算术有误」**正确**；原向量②「`nCasePerLayer=8` → 034E」随之失效（8 ≤ 9 通过），应改为大于 9 才触发 034E。
- **§4.20 绝缘公式方向**：派单乘式（`Rb×(Vbus/(Vp+Vn) − 1)`）分子分母倒置——完全平衡得 0 kΩ，等于把绝缘良好判成对地短路；单极短路得无穷。编码者改除式 `R = Rb×(Vp+Vn)/(Vbus − Vp − Vn)` **正确**：`D→0 ⇒ R→∞`、`Vp+Vn→0 ⇒ R→0` 两端极限均对，且 `Rp/Rn = Vp/Vn` 与并联自洽式 `1/(1/Rp+1/Rn) = R_t` 同时成立。退化分支哨兵 `1.0E9 kΩ`（1 TΩ）**合理**：高于真实最高读数（1e5~1e6 kΩ）3 个数量级、高于告警阈值 7 个数量级，且两极同取哨兵使失衡比恒为 1（不误报失衡）。

### 收口 / Closeout

- registry v2.13.0→**v2.14.0**，424→**444** 件（counts Base 73 / MathData 152 / Algo 48 / Device 76 / Motion 38 / Process 57）；JSONL **444 行全量 sha256 MATCH**（终审重注入 6 行后全量复验，noPOU 行 0、真漂移 0）；码位 CLASH=NONE。
- 源矩阵回写：**T2-1 仿射族逆映射补口**（三元闭环齐备）、**T1-2 ROOM_CONTROL 子族开族 2 件**。
- 五本 MANUAL 各追加 R25 接口表节（引脚名与类型由 `.st` 源码机读提取，20 件全覆盖）；ROADMAP 勾选 18 项为 `[x]` 并写落地版本，增补 10 条待办。

*Last updated: 2026-11-17（R25 追加 v2.14.0 条目）*
## v2.40.0 — 2026-11-20（R48 / 零检索轮 20 新件 + 1 返修）

### Added（20 新件：DL_Algo +5 / DL_Motion +4 / DL_Base +3 / DL_Device +3 / DL_Process +3 / DL_MathData +2）
- DL_Algo（+5，补 R47 让位欠账）：FB_DL_SensorFusion2 / FB_DL_BiasAdaptiveTrim / FB_DL_FuzzyTrim2In / FB_DL_Decouple2x2 / FB_DL_GapForceSwitchover
- DL_Motion（+4）：FB_DL_LoadShareDroop / FB_DL_ZoneSpeedTrim / FB_DL_ContourCrossCouple / FB_DL_LookaheadVelPlanner
- DL_Base（+3）：FC_DL_SaturateSub（与 SaturateAdd 成对）/ FB_DL_ModeArbiter / FB_DL_HoldRepeatButton
- DL_Device（+3）：FB_DL_SolenoidCoilHealth / FB_DL_HeaterBreakDetect / FB_DL_VibZoneClassify
- DL_Process（+3）：FB_DL_AutoclaveSterilSeq / FB_DL_TunnelPasteurizerSeq / FB_DL_PumpPrimingSeq
- DL_MathData（+2，配额纠偏 ≤2 达标）：FC_DL_SimpsonQuad / FC_DL_LagrangeInterp

### Fixed
- FB_DL_ModulePottingVac v1.0.0 → v1.0.1：到位脉冲先于 TON.Q 消失致「过相」判据恒假误报；改 `_bVacSeen`/`_bBreakSeen` 沿锁存 + 判据读锁存量 + 迁出链双清，引脚契约零变更。

### Changed
- registry 845 → **865**（v2.40.0）；JSONL 846 → **866** 行（badjson=0）。
- 机检 21/21 PASS（audit_r48.py，F3 两条多行数组初始化口径假阳性经补声明行注释后闭合）。

## v2.41.0 — 2026-11-20（R49 / 零检索轮 20 新件）

### Added（20 新件：DL_Algo +5 / DL_Motion +5 / DL_Base +4 / DL_Device +3 / DL_MathData +2 / DL_Process +1）
- DL_MathData（+2）：FC_DL_QuatRotateVec（四元数旋转向量，模长闸 + 非有限拒收）/ FC_DL_GeoMeanCalc（对数域几何均值，含零/负值拒算位）
- DL_Base（+4）：FB_DL_HeartbeatGen / FB_DL_PulseSeqVerify / FB_DL_StepTimeRecorder / FB_DL_CycleBarrierGate
- DL_Algo（+5）：FB_DL_SignalReconstruct / FB_DL_LoopSignGuard / FB_DL_ExtremumSeekCtrl / FB_DL_LoopCoupleDetect / FB_DL_RulEstimator
- DL_Device（+3）：FB_DL_ValveSeatLeakWatch / FB_DL_CylStrokeTimeBank / FB_DL_CaseErectFaultSeq
- DL_Motion（+5）：FB_DL_MoveResumeSeg / FB_DL_VelFfGainIdent / FB_DL_SoftLimitCfgAudit / FB_DL_AxisLubeDistTrig / FB_DL_BrakeWearAccum
- DL_Process（+1）：FB_DL_RoomTempClassify

### Verified
- 机检（audit_r49.py，增量 20 件）20/20 PASS，fail=0；零码位范式延续（BOOL+ENUM 出口）。
- registry 865 → **885**（v2.41.0，counts 98/206/101/167/98/215）；JSONL 866 → **886** 行（badjson=0）。
- 批次节律：单编码子代理一次调用内 4 批 × 5 件按序完成，零拒单，编码侧自纠 10 处。

## v2.43.0 (2026-11-20 R51)
- +20 组件（DL_Process 18 / DL_MathData 2）；返修 FB_DL_RulEstimator/ExtremumSeekCtrl/MoveResumeSeg/LoopCoupleDetect v1.0.1（R50 挂账闭环）。

## v2.44.0 (2026-11-20 R52)

### Added（20 新件，4 批 × 5，零检索轮 WebSearch 0/3）
- DL_Base（+4）：FC_DL_BitCountOnes / FC_DL_PriorityEncodeWord / FB_DL_SchmittTriggerGap / FB_DL_EdgeIntervalMeter
- DL_MathData（+2）：FC_DL_WrapIndexNeg / FC_DL_LogDomainNormalize
- DL_Algo（+5）：FC_DL_ZnTune / FB_DL_AdaptiveDeadbandZone / FB_DL_DerivativeNoiseWeight / FB_DL_ControlOutputSlewWatch / FB_DL_PidParamDriftAudit
- DL_Device（+4）：FB_DL_BrakeResistorThermal / FB_DL_PressureSwitchChatter / FB_DL_MeterPulseLossDetect / FB_DL_HeatTraceCircuitMon
- DL_Motion（+3）：FB_DL_AxisJerkLimitCheck / FB_DL_AxisHomeRepeatVerify / FB_DL_AxisSoftLimitPredict
- DL_Process（+2）：FB_DL_MakeupWaterDosing / FB_DL_DieBinCounter

### Fixed
- FB_DL_ValveSeatLeakWatch → **v1.0.1**（严重）：环窗回归写入期 `_aX[_nHead] := DINT_TO_LREAL(_nHead)` 把头游标当 x，回卷后 X/Y 错配致斜率符号翻转、真实上升泄漏被判非上升（安全侧漏报）；改 R194 时间序环回遍历（_nOldest 推导 + _i/_nIdx 映射），未采用 _nSeq 全局序号方案。
- FB_DL_MoveResumeSeg → **v1.0.2**（文档级）：`fStartRst` 实测正文零引用，保留引脚契约并注释标 reserved，起点语义由 `fPosNow` 实时快照承担，逻辑零变更。

### Verified
- registry 925 → **945**（counts 106/212/112/175/106/234，回读 sum=945 一致）；JSONL 926 → **946**（新增 20 行 instruction≥80 / arch≥100 / output 完整，badjson=0；R343 遗留短行只记数）。
- 机检 22/22 PASS fail=0（20 新件 + 2 返修件）；零 GVL / 零 VAR_EXTERNAL / 零 %I%Q / 零占位符 / 零嵌套注释 / CASE 全含 ELSE / 声明行中英双语注释齐备。
- 编码侧自纠 5 处：未声明标识符 / 临时占位文件 / 嵌套注释回夹 / 引用不存在常量函数 / 自乘自除失效常量。

## [v2.48.0] - 2026-11-21

### Added
- `FC_DL_HermiteInterp`（DL_MathData，cx3）
- `FC_DL_QuatSlerp`（DL_MathData，cx3）
- `FC_DL_RoundSigFigs`（DL_MathData，cx3）
- `FC_DL_RtdLinearization`（DL_MathData，cx4）
- `FB_DL_EStopDualChannel`（DL_Base，cx4）
- `FC_DL_Kalman2DSmoother`（DL_MathData，cx5）
- `FB_DL_SignalSeqGuard`（DL_Base，cx3）
- `FB_DL_TwoDofPid`（DL_Algo，cx4）
- `FB_DL_AxisAccelFeedforward`（DL_Motion，cx3）
- `FB_DL_HydraulicAccumPreChg`（DL_Device，cx3）
- `FB_DL_VacIonizerBalance`（DL_Device，cx3）
- `FB_DL_FanVfdBypassSwap`（DL_Device，cx4）
- `FB_DL_AxisCantileverComp`（DL_Motion，cx4）
- `FB_DL_HotRunnerZoneBalance`（DL_Process，cx3）
- `FB_DL_SlurrySieveClogWatch`（DL_Process，cx4）
- `FB_DL_LossInWeightFeeder`（DL_Algo，cx5）
- `FB_DL_UvDoseCtrl`（DL_Algo，cx5）
- `FB_DL_UltrasonicWeldCtrl`（DL_Device，cx5）
- `FB_DL_AxisProbeMeasCycle`（DL_Motion，cx5）
- `FB_DL_AirShowerInterlockSeq`（DL_Process，cx4）

### Fixed
- `FB_DL_BacdHvacPoll` v1.0.1：R55 五抽缺陷返修（详见 REVIEW_R55/R56）
- `FB_DL_FopdtStepIdent` v1.0.1：R55 五抽缺陷返修（详见 REVIEW_R55/R56）
- `FB_DL_CoinCellAssembler` v1.0.1：R55 五抽缺陷返修（详见 REVIEW_R55/R56）
- `FB_DL_StringElImageMap` v1.0.1：R55 五抽缺陷返修（详见 REVIEW_R55/R56）
- `FB_DL_PackMlUnitMode` v1.0.1：R55 五抽缺陷返修（详见 REVIEW_R55/R56）

### Changed
- 全库 1017 件 / v2.48.0；SFT 语料 1018 条。

## [v2.50.0] - 2026-11-21

### Added
- `FB_DL_VoteKooN`（DL_Base，cx3）
- `FB_DL_SimInputBank`（DL_Base，cx3）
- `FC_DL_ThermocoupleLinearization`（DL_MathData，cx3）
- `FB_DL_SkewKurtosisCalc`（DL_MathData，cx3）
- `FC_DL_SolveLinear3`（DL_MathData，cx3）
- `FC_DL_PmvComfortIndex`（DL_Algo，cx3）
- `FB_DL_SoftStarterDrive`（DL_Device，cx4）
- `FB_DL_ElectricLinearActuator`（DL_Device，cx3）
- `FB_DL_OptimalStartStop`（DL_Algo，cx4）
- `FB_DL_PeriodicDisturbComp`（DL_Algo，cx4）
- `FB_DL_CondensateDrainSeq`（DL_Device，cx3）
- `FC_DL_CamTableGenSeg`（DL_Motion，cx3）
- `FB_DL_AxisSafetyStateMon`（DL_Motion，cx3）
- `FB_DL_GowningRoomSeq`（DL_Process，cx3）
- `FB_DL_MaterialHoldTimeEnforce`（DL_Process，cx3）
- `FB_DL_FirstArticleLock`（DL_Process，cx3）

### Fixed
- `FB_DL_EncoderQuadCount` v1.0.1：R57 五抽缺陷返修（详见 ROUND_PLAN_R58 §二）
- `FC_DL_RmsCalc` v1.0.1：R57 五抽缺陷返修（详见 ROUND_PLAN_R58 §二）
- `FB_DL_PassboxInterlockSeq` v1.0.1：R57 五抽缺陷返修（详见 ROUND_PLAN_R58 §二）
- `FB_DL_NightPurgeSeq` v1.0.1：R57 五抽缺陷返修（详见 ROUND_PLAN_R58 §二）
- `FC_DL_PowIntSat` v1.0.1：R57 五抽缺陷返修（详见 ROUND_PLAN_R58 §二）

### Changed
- 全库 1053 件 / v2.50.0；SFT 语料 1054 条。
