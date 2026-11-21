# ROUND_PLAN_R34 — 阶段一派单（2026-11-18）

> 选题依据：`_CANDIDATE_POOL_R34.txt`（175 条机械去重项）+ `_REGNAMES_R34.txt`（598 已注册名全量 grep 查重）+ `SOURCE_HUNTING_MATRIX.md` §5 台账。
> **WebSearch 配额 0/0（零检索轮）**：本轮全部取 T0/ROADMAP 池与矩阵既有 ◐ 组语义，来源标签回指既有台账行，不新增外部源。
> **T0 配额如实取 0 件**：候选池内 T0 仅余 `FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx` 一项，实测与存量 `FC_DL_ShlEx` / `FC_DL_ShrEx`（32 位口径、R14 收口）同义，R61 式查重判定为**同义变体，不予立项**（写回本文件 §4 异常，不入 20 件）。
> **T2 配额**：13 件带 `t2-*` 标签，覆盖 LGF（Math/Comparator/Technology/SignalGenerators/DateTimer）/ LBP / ISA-18.2 / ISA-88 / OMAC PackML / NE107 六个族，满足「≥1 个 T2 组件族」硬约束。

## 1 目标组件清单（20 件新件）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_LaserWeldPowerSeq` | DL_Process | FB | 激光焊预焊-满焊-收弧三段功率斜坡配方序列（功率/速度/离焦三维配方切换） | `t2-1-lgf-signalgen` `t2-2-lbp` | 中 | 1 |
| 2 | `FB_DL_OcvGradingBin` | DL_Process | FB | OCV 电压+内阻双判据分档与落料位决策（档位带 + 满仓避让） | `t2-1-lgf-comparator` | 中 | 1 |
| 3 | `FB_DL_ChamberPurgeDry` | DL_Process | FB | 腔体干燥吹扫顺控（露点判据收敛 + 吹扫/静置/复测三态） | `t1-2-oscat-building` | 中 | 1 |
| 4 | `FB_DL_LoadlockPressureCross` | DL_Process | FB | Loadlock 双表压力交叉校验与误开门拦截（偏差窗 + 首出定位） | `t2-8-isa182` | 中 | 1 |
| 5 | `FB_DL_StringCurrentMismatch` | DL_Process | FB | 组串电流失配诊断与遮挡定位（中位基线 + 分级 + 异常串号输出） | `t2-1-lgf-measurement` | 中 | 1 |
| 6 | `FB_DL_PvSoilingLossRate` | DL_Process | FB | 组件积灰损失率估算与清洗提醒（功率基线衰减速率 + 清洗阈值） | `t2-1-lgf-measurement` | 中 | 2 |
| 7 | `FB_DL_TrapSealTrend` | DL_Process | FB | 枕式包装封口温度随线速前馈重置（线速→封温设定 + 限速重置） | `t2-5-modpid` `t2-1-lgf-technology` | 高 | 2 |
| 8 | `FB_DL_LamTempUniformity` | DL_Process | FB | 层压板面多测点温度均匀性诊断（极差/标准差双判据 + 分区告警） | `t2-1-lgf-measurement` | 中 | 2 |
| 9 | `FB_DL_StratificationGuard` | DL_Process | FB | 水箱温度分层监视与混温抑制（上下点温差门限 + 混水泵调节请求） | `t2-5-modpid` | 中 | 2 |
| 10 | `FB_DL_AndonRespTimeReport` | DL_Process | FB | 安灯呼叫→应答→解除三段计时与四级响应时长分档台账 | `t2-7-omac` `t2-8-isa182` | 中 | 2 |
| 11 | `FB_DL_BatchEndPointTrend` | DL_Process | FB | 批次反应终点趋势判据（斜率收敛 + 终点窗 + 超时升级） | `t2-8-isa88` | 中 | 3 |
| 12 | `FB_DL_DryerExhaustHumidityCtl` | DL_Process | FB | 干燥排湿热回收风门控制（排湿焓值判据 + 回风混风域闸） | `t1-2-oscat-building` | 中 | 3 |
| 13 | `FB_DL_CombinerArcDetect` | DL_Device | FB | 汇流箱直流拉弧特征判据（高频分量 + 波动窗 + 分级告警出口） | `t2-8-ne107` | 高 | 3 |
| 14 | `FB_DL_CellVolumeCheck` | DL_Device | FB | 电芯厚度/体积激光测距校验（NE43 质量位 + 超差分档） | `self-r34` `ne43` | 中 | 3 |
| 15 | `FB_DL_MfcRatioCheck` | DL_Device | FB | MFC 流量配比偏差核对（标定换算 + 配比窗 + 配方回读比对） | `t2-2-lbp` | 中 | 3 |
| 16 | `FB_DL_PhaseNeutralImbalance` | DL_Device | FB | 三相不平衡度与中性线电流判据（不平衡率分级 + 缺相识别） | `t2-8-ne107` | 中 | 4 |
| 17 | `FB_DL_HumidifierWaterQual` | DL_Device | FB | 加湿器水质电导率监视与排水联锁（门限 + 排水周期 + 补水禁投） | `self-r34` | 中 | 4 |
| 18 | `FB_DL_FilmTensionStepper` | DL_Motion | FB | 收卷步进张力叠加微调（叠加偏置 + 张力带 + 步进增量限幅） | `t2-1-lgf-technology` | 高 | 4 |
| 19 | `FB_DL_TrackerAngleYearWin` | DL_Motion | FB | 跟踪支架年度角度表切换（年窗+月窗双闸 + 角度表版本锁存） | `t2-1-lgf-dateandtimer` | 中 | 4 |
| 20 | `FB_DL_RfMatcherTune` | DL_Algo | FB | 射频匹配器反射比最小化步进搜索（三点探步 + 收敛判据 + 越限回退） | `self-r34` | 高 | 4 |

**分布**：DL_Process 12 ｜ DL_Device 5 ｜ DL_Motion 2 ｜ DL_Algo 1 ｜ DL_MathData 0 ｜ DL_Base 0。T0 0 件，T2 标签 13 件。

### 1.1 欠账返修件（不计入 20 件，批 4 之后单独排程）

| 件 | 分类 | 缺陷（R33 挂账） | 返修口径 |
|---|---|---|---|
| `FB_DL_SlurryViscosityComp`（**返修**） | DL_Process | ①`bRun=FALSE` 只降级不冻结输出（语义不明）；②`xClamped` 名实不符且未挂 `bClamped` 输出 | 最小改动：`bRun=FALSE` 分支改「冻结保持末次有效粘度 + 置 `bDegraded`」并写进头注释；`xClamped`→与 `bClamped` 同源赋值（**不改名，护接口**），升 PATCH v1.0.2 |

## 2 码位分配表（自上表窗口顺序递增，无跳号）

| 序号 | 组件名 | 码位 |
|---|---|---|
| 1 | `FB_DL_LaserWeldPowerSeq` | `16#06_0_80` |
| 2 | `FB_DL_OcvGradingBin` | `16#06_0_81` |
| 3 | `FB_DL_ChamberPurgeDry` | `16#06_0_82` |
| 4 | `FB_DL_LoadlockPressureCross` | `16#06_0_83` |
| 5 | `FB_DL_StringCurrentMismatch` | `16#06_0_84` |
| 6 | `FB_DL_PvSoilingLossRate` | `16#06_0_85` |
| 7 | `FB_DL_TrapSealTrend` | `16#06_0_86` |
| 8 | `FB_DL_LamTempUniformity` | `16#06_0_87` |
| 9 | `FB_DL_StratificationGuard` | `16#06_0_88` |
| 10 | `FB_DL_AndonRespTimeReport` | `16#06_0_89` |
| 11 | `FB_DL_BatchEndPointTrend` | `16#06_0_8A` |
| 12 | `FB_DL_DryerExhaustHumidityCtl` | `16#06_0_8B` |
| 13 | `FB_DL_CombinerArcDetect` | `16#03_2_00` |
| 14 | `FB_DL_CellVolumeCheck` | `16#03_2_01` |
| 15 | `FB_DL_MfcRatioCheck` | `16#03_2_02` |
| 16 | `FB_DL_PhaseNeutralImbalance` | `16#03_2_03` |
| 17 | `FB_DL_HumidifierWaterQual` | `16#03_2_04` |
| 18 | `FB_DL_FilmTensionStepper` | `16#04_0_A0` |
| 19 | `FB_DL_TrackerAngleYearWin` | `16#04_0_A1` |
| 20 | `FB_DL_RfMatcherTune` | `16#02_3_80` |

> 窗口占用明细：DL_Process `16#06_0_80`~`16#06_0_8B`（12/36 格）；DL_Device `16#03_2_00`~`16#03_2_04`（5/16 格）；DL_Motion `16#04_0_A0`~`16#04_0_A1`（2/16 格）；DL_Algo `16#02_3_80`（1/16 格）；DL_MathData / DL_Base 窗口本轮**未动**（0 件，留作 R35 与 `DateAddDays` 常量重定）。返修件 `SlurryViscosityComp` 沿用原码位，不占新格。

## 3 批次切分（4 批 × 5 件，按依赖与同族聚拢，批 1 最独立）

| 批次 | 序号 —— 组件名 | 批内复用依赖（均为已注册件） |
|---|---|---|
| **批 1**（最独立，仅依赖 Level 0） | 1 `LaserWeldPowerSeq` ｜ 2 `OcvGradingBin` ｜ 3 `ChamberPurgeDry` ｜ 4 `LoadlockPressureCross` ｜ 5 `StringCurrentMismatch` | `FB_DL_StepSequencer` / `FB_DL_ToleranceWindow` / `FC_DL_LimitClassify` / `FC_DL_DewPointCalc` / `FB_DL_InterlockMatrix` / `FB_DL_SignalStatistics` |
| **批 2**（测量-诊断族，同族连续） | 6 `PvSoilingLossRate` ｜ 7 `TrapSealTrend` ｜ 8 `LamTempUniformity` ｜ 9 `StratificationGuard` ｜ 10 `AndonRespTimeReport` | `FB_DL_SignalStatistics` / `FB_DL_Differentiator` / `FB_DL_PidController` / `FB_DL_RateLimiter` / `FB_DL_AlarmManager` |
| **批 3**（批次语义 + 设备级判据） | 11 `BatchEndPointTrend` ｜ 12 `DryerExhaustHumidityCtl` ｜ 13 `CombinerArcDetect` ｜ 14 `CellVolumeCheck` ｜ 15 `MfcRatioCheck` | `FB_DL_Differentiator` / `FC_DL_HumidAirEnthalpy` / `FB_DL_HighPassFilter` / `I_DL_AnalogSensor` / `FB_DL_DeviceParamVerify` |
| **批 4**（电力/水质监视 + 运动与算法侧） | 16 `PhaseNeutralImbalance` ｜ 17 `HumidifierWaterQual` ｜ 18 `FilmTensionStepper` ｜ 19 `TrackerAngleYearWin` ｜ 20 `RfMatcherTune` | `FC_DL_LimitClassify` / `FB_DL_TimeWindowCheck` / `FB_DL_SuperimposedMove` / `FB_DL_YearWindowCheck` + `FB_DL_MonthWindowCheck` |
| **批 5（返修，非新件）** | `FB_DL_SlurryViscosityComp` v1.0.2 | 无新增依赖，只改病灶行 |

## 4 边界安全条件（每件一句，编码专家直接引用）

| 序号 | 组件名 | 必须防的边界 |
|---|---|---|
| 1 | `LaserWeldPowerSeq` | 三段功率/速度参数须在头注释给「极限值→类型可表性」反算；段切换当拍须冻结输出功率一拍防阶跃冲击；配方越界（功率 ≤0 或 >额定）走组态闸出厂即报码，不得靠运行时钳位掩盖 |
| 2 | `OcvGradingBin` | 档位阈值必须单调递增校验（倒置即冻结 + 报码）；电压/内阻任一 NaN 时判「不可分档」而非落入最低档（`x <> x` 精确判据）；满仓档位无可用料仓时停线而非静默落最低档 |
| 3 | `ChamberPurgeDry` | 露点计算入参（温度/湿度）先过有限性与物理域闸（RH 0~100 %、温度 −40~120 °C）；吹扫计时用三实例分段 TON，每段 `IN := NOT ton.Q` 自复位（FB33-2）；复测未收敛时不得延续吹扫无限等待 → 超时升级 |
| 4 | `LoadlockPressureCross` | 双表偏差判据须先各自过 NE43 有效域，任一表无效即禁开门（禁用无效值参与偏差计算，R127）；偏差窗上下限须配比约束（上限 > 下限，否则出厂报码）；联锁输出解锁条件必须可从「双表一致 AND 压力到位」到达（FB33-2 可达性） |
| 5 | `StringCurrentMismatch` | 中位基线计算前剔除无效/停机串（电流 ≤0 或 NaN），样本数 <3 时不出诊断结论；失配率分母（基线值）近零时改绝对差判据（防除零）；遮挡定位输出须按物理串号连续编址，越界下标钳位并置码 |
| 6 | `PvSoilingLossRate` | 基线须在「辐照/温度同窗」条件下取（否则把天气当积灰）；衰减速率计算分母时间窗 >0（防除零）；辐照低于下限时冻结估算并置 `bFrozen`，禁以低辐照数据外推 |
| 7 | `TrapSealTrend` | 线速为 0 时不得外推封温设定（用最后有效线速并置 `bHold`）；重置限速斜率须与 PID 采样周期配比（超调即判组态非法）；封温设定钳到工艺窗口上下限，越限只钳位 + 报码不拒算 |
| 8 | `LamTempUniformity` | 测点数 <2 时不出极差结论（单点极差恒 0，会误判均匀）；任一测点失效须从统计中剔除并在掩码标出（禁用 0 °C 充当有效值，R42 家族）；均匀性门限按工艺窗口给常量，禁写裸数值 |
| 9 | `StratificationGuard` | 上下点温差判据须带迟滞（否则混水泵频繁启停）；两点任一无效时冻结判定并保持上次输出；混温请求与主机启动命令须互斥仲裁（同拍双真取安全侧） |
| 10 | `AndonRespTimeReport` | 三段计时器必须各自在进入相时复位，防上一轮残值续累；呼叫未应答即解除时不计入应答时长统计（分母口径须显式）；分档边界须「正好整除」与「上限+1」两点各推一条验收向量（R28 终审二式·整数进位） |
| 11 | `BatchEndPointTrend` | 斜率计算须防采样周期为 0；终点窗须带「终点超时」独立出口（趋势收敛但一直不达窗 → 超时升级，不得死等）；相 ID 非法（枚举兜底）时不得置相完成 |
| 12 | `DryerExhaustHumidityCtl` | 焓值计算前先判干球/含湿量有效域；排湿与混风阀开度互斥（同拍双开即判冲突并回安全位）；回风温度越上限时强制加大排湿并置码 |
| 13 | `CombinerArcDetect` | 高频分量提取前须确认采样率与滤波器截止频率配比合法（截止 ≥ 采样率/2 即出厂报码）；拉弧判据须多拍持续确认，单拍尖峰只计信息级不升故障；分级出口按 NE107 六态映射，未知态归 `eUnknown` 不得归 `eOk` |
| 14 | `CellVolumeCheck` | 激光测距原始域先按 NE43 判有效性（断线/欠量程/超量程），无效值不得参与超差计算；厚度基准值（标定常数）为 0 或未标定时拒测并置码；超差判定用公差带 + 迟滞，防边界抖动反复分档 |
| 15 | `MfcRatioCheck` | 配比计算前各路流量须 >0 且有限（分母防零）；配比窗上下限须配比校验（下限 ≤ 上限）；设定回读比对须带容差（浮点禁 `=` 判等），差异只报等级不改设定值 |
| 16 | `PhaseNeutralImbalance` | 三相电压/电流任一为 0 或 NaN 时改判「缺相」而非计算不平衡率（除零前置）；不平衡率定义（负序/正序 vs 最大偏差/均值）须在头注释写死；中性线电流超限与不平衡分级各自独立码值（FB33-3 归因唯一） |
| 17 | `HumidifierWaterQual` | 电导率标定参数非法（斜率 0/负）时拒算并置码；排水联锁须与补水阀互斥；电导门限带迟滞防抖，越限解除须有可到达路径（FB33-2） |
| 18 | `FilmTensionStepper` | 叠加偏置总量必须限幅到张力带允许域（防累计漂移把轴拉飞）；步进增量须限斜率，且每拍只在叠加通道写入，不改基础轴目标（叠加 ≠ 改目标）；张力反馈无效时冻结叠加并保持末次有效偏置 |
| 19 | `TrackerAngleYearWin` | 年窗/月窗参数须钳位照算（越界钳定 + 报码，不拒算）；角度表切换仅在「双窗同时生效 + 支架静止」时执行，运动中切换须排队到停止；表版本锁存防切换瞬间半新半旧 |
| 20 | `RfMatcherTune` | 反射比非有限或 >100 % 时终止搜索并回退到末次最优点；三点探步须设最大迭代计数器（`WHILE` 防死锁，R 系列硬约束）；搜索步长下限为正（防步长衰减到 0 后原地空转）；收敛判据须带「连续 N 次无改进即退出」出口 |
| — | `SlurryViscosityComp`（返修） | `bRun=FALSE` 时必须冻结输出末次有效粘度（禁输出 0 或未定义值），并置 `bDegraded`；`bClamped` 与 `xClamped` 同源赋值（同名同义） |

## 5 选题纪律自证

1. **零撞名**：20 件 + 返修件逐一 grep `_REGNAMES_R34.txt`（598 名），全部 0 命中（返修件 1 命中＝其自身在册，属预期）。跨子库同名亦已排除。
2. **同义邻件双查结果**（R61 式，命中即弃，已从候选池剔除 100 条以上的近似项）：`FB_DL_AhuEconomizer` 弃（存量 `FB_DL_EnthalpyCompareCtrl` 已覆盖焓差经济器）｜`FB_DL_VavDischargeAirReset` 弃（存量 `FB_DL_AhuSupplyAirReset`）｜`FB_DL_HeatExchangerFoulingTrend` 弃（存量 `FB_DL_FoulingResistanceEstimator`）｜`FB_DL_ChamberPumpDownSeq` 弃（存量 `FB_DL_ChamberPumpDownProfile`）｜`FB_DL_SteamTrapSurvey` 弃（存量 `FB_DL_SteamTrapDiagTrend` / `SteamTrapMonitor`）｜`FB_DL_FormationChannelQueue` 弃（存量 `FB_DL_FormationChannelMgr`）｜`FB_DL_ElectrodeGapMark` 弃（存量 `FB_DL_CoatingGapMeasure`）｜`FB_DL_CellOcvBinSort` 与序号 2 同义，只留一件｜`FB_DL_ChwDifferentialPressureReset` 弃（R30 已并案）｜`FC_DL_ShlDwordEx` / `ShrDwordEx` 弃（与存量 `ShlEx` / `ShrEx` 同义）。
3. **不用它会怎样**（逐件在表 1「一句话功能」+ §4 边界中已体现工程后果，不做「为了凑 20 件」的纯变体）。

## 6 异常与报备

- **T0 取 0 件**：候选池 T0 侧仅剩同义项，按「宁少勿滥」如实报 0，未凑数。
- **候选池规模充足**：175 条中扣除同义/近似/已并案项后可用约 60 条，本轮取 20 条，余量留 R35。
- **零撞名**，无候选不足，无越窗口分配。
- **编码侧提醒**：FB33-1（CASE 后 5 行不得无条件清零）与 FB33-2（`TON` 自复位）为本轮新固化判据，批 1 起即须遵守；`SlurryViscosityComp` 返修只改病灶行，接口一字不动。
