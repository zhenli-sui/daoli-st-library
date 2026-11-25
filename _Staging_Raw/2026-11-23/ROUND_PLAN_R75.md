# ROUND_PLAN_R75（2026-11-23 11:55 起排 · 硬顶 60 分钟 · 12:53 收尾）

主控：道莅工控代码库产品总监（R335 主控直跑：规划/终审/收口直跑，子代理额度留给规划与编码）。

---

## §1 状态统计

| 指标 | 数值 | 备注 |
|---|---|---|
| 总库累计 | **1,252 / 10,000（12.52%）** | registry v2.66.0，last_updated 2026-11-23T08:40 |
| 今日交付 | **46 / 300** | R72 +12 → 12，R73 +20 → 32，R74 +14 → 46；今日余量 254 |
| R75 配额 | **40 件**（复杂 14 + 简单 26） | R74 战报 P0-4「新件配额 40，产能回调」 |
| R74 L2 通过率 | **39/42 = 92.9%**（豁免 3） | < 95% → 本轮按规预留 **4 个修复名额** |
| L2 存量缺陷 | 3 件豁免 + 1 处 VLA | SingleAxis / BatchDosingControl（E007：RuSTy 1.0.8 不解析 FB 内 PROPERTY）、CamOverrideTrim（E037：VLA→VLA 透传）；源头 `FC_DL_CamTableInterp` 缺显式点数字段 |
| 存量挂账余量 | R73 零回执候审 ~20 处 | 本轮抽 3 件点修（见 §2 S3 批修复行） |
| 源矩阵覆盖率 | 收口 9/27 = 33% | T0 八组 8/8 维持维护模式；无整组收口 |
| 开源候选队列 | **29 条**（绿区 28 / 黄区 1 / 红区 0） | brOscatLib / AixOCAT / TcOpen / WTFPL 黄区 1 |
| 本轮队列溯源占比 | **12/40 = 30%** | 达标下限（≥12 件） |
| 连续零检索轮 | 11 轮 | 本轮延续零检索（队列存量 + 矩阵未收口组供料） |
| 撞名三查 | 本计划执行 5 轮关键词扫查 | 驳回 28 条，留痕 §3 |

---

## §2 40 目标总表

列：序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档

### 复杂件批 1（5 件，C3~C5）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| C01 | FB_DL_BurnerFlameGuard | DL_Device | FB | 燃烧器火焰安全监督：吹扫→点火→火焰建立→联锁锁定状态机，火焰信号丢失锁存与安全停机序列 | self-cleanroom（行业池·热工安全） | C5 | B1 | 复杂 |
| C02 | FB_DL_InjectionMoldClampSeq | DL_Process | FB | 注塑机合模-射胶-保压-冷却-开模五段工艺序列，锁模力段间闸与模保超时出口 | self-cleanroom（行业池·塑机） | C5 | B1 | 复杂 |
| C03 | FB_DL_DeltaRobotIk | DL_Motion | FB | 并联三角洲机器人三臂逆解：末端 XYZ → 三臂关节角，行程奇异性闸 | self-cleanroom（运动学） | C5 | B1 | 复杂 |
| C04 | FB_DL_VfdStateWordMatch | DL_Device | FB | 变频器状态字与期望控制状态匹配判码，失配锁存与状态号输出 | queue:ISC_NUM（brOscatLib MIT） | C3 | B1 | 复杂 |
| C05 | FB_DL_PaintBoothAirBalance | DL_Process | FB | 喷漆房送排风平衡控制：压差带维持 + 风机联锁 + 失衡降级 | self-cleanroom（行业池·涂装） | C4 | B1 | 复杂 |

### 复杂件批 2（5 件，C3~C4）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| C06 | FC_DL_WeirFlowCalc | DL_MathData | FC | 堰流过流量计算（薄壁堰/宽顶堰公开公式，含淹没流判别） | self-cleanroom（公开公式） | C3 | B2 | 复杂 |
| C07 | FB_DL_WaterChlorineDoseTrim | DL_Process | FB | 余氯-浊度双参数加药量 trim 控制与剂量上限闸 | queue 域延伸（绿区水处理语义） | C4 | B2 | 复杂 |
| C08 | FB_DL_CentrifugeSpinSeq | DL_Process | FB | 离心机升速-恒速-降速三段序列，临界转速快跳段与不平衡停机闸 | self-cleanroom（行业池·分离设备） | C4 | B2 | 复杂 |
| C09 | FC_DL_AkimaInterp1D | DL_MathData | FC | Akima 一维插值（抗振荡非样条插值，显式点数入参防 VLA） | self-cleanroom（公开算法） | C4 | B2 | 复杂 |
| C10 | FB_DL_VfdCtrlWordBuild | DL_Device | FB | 变频器控制字编码：目标状态号 → 控制字位序（与 C04 成对） | queue:ISC_CTRL（brOscatLib MIT） | C3 | B2 | 复杂 |

### 复杂件批 3（4 行 = 3 新 + 1 修复）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| C11 | FB_DL_ManualOverride | DL_Base | FB | 手动强制覆写：手/自动信号选择 + 覆写激活提示与超时回落 | queue:MANUAL（brOscatLib MIT） | C3 | B3 | 复杂 |
| C12 | FB_DL_IoLinkPortDiag | DL_Device | FB | IO-Link 端口诊断聚合：端口状态/设备质量码/循环看门狗 | self-cleanroom（协议诊断） | C3 | B3 | 复杂 |
| C13 | FB_DL_PeltierTempCtrl | DL_Algo | FB | 半导体制冷 TEC 双向温控：冷热极性切换 + 双向抗饱和 | self-cleanroom（行业池·精密温控） | C4 | B3 | 复杂 |
| C14 | FC_DL_CamTableInterp（修复） | DL_MathData | FC | **修复名额 ①**：增显式点数字段（uPointCnt 入参）解 VLA→VLA 透传（CamOverrideTrim E037） | R74 战报 P0-② | C4 | B3 | 修复 |

### 简单件批 1（9 件，C1~C2）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| S01 | FC_DL_CabsComplexCalc | DL_MathData | FC | 复数模长计算（√(re²+im²) 防溢出实现） | queue:CABS（brOscatLib MIT） | C2 | S1 | 简单 |
| S02 | FC_DL_Exp10Calc | DL_MathData | FC | 10^x 计算（防御域闸，与 LogEx/LogBaseEx 成对） | queue:EXP10（brOscatLib MIT） | C1 | S1 | 简单 |
| S03 | FC_DL_SpeedUnitConvert | DL_MathData | FC | 速度单位互转 m/s ↔ km/h（速度类换算补口） | queue:MS_TO_KMH（brOscatLib MIT） | C2 | S1 | 简单 |
| S04 | E_DL_ControlModeSel | DL_Base | E | 手/自动/停止模式枚举（strict 限定，配 MANUAL 覆写件） | queue:CONTROL_MODE（AixOCAT MIT） | C1 | S1 | 简单 |
| S05 | FB_DL_FirstOrderImpResp | DL_MathData | FB | 一阶惯性环节脉冲响应序列计算 | queue:FT_IMP（brOscatLib MIT） | C2 | S1 | 简单 |
| S06 | FC_DL_DwRealReinterp | DL_Base | FC | DWORD↔REAL 位重解释（双向往返单件，防拆件凑数） | queue:DW_TO_REAL+REAL_TO_DW（brOscatLib MIT） | C1 | S1 | 简单 |
| S07 | FB_DL_DualWindowBandCmp | DL_Base | FB | 双窗带比较器：双独立窗口三态输出（下窗/带内/上窗） | queue:WINDOW2（brOscatLib MIT） | C2 | S1 | 简单 |
| S08 | FC_DL_QuartileCalc | DL_MathData | FC | 四分位数 Q1/Q2/Q3 计算 | self（统计族补口） | C2 | S1 | 简单 |
| S09 | FC_DL_PowerFactorCalc | DL_MathData | FC | 功率因数计算（有功/视在比，电能质量族补口） | self（公开公式） | C2 | S1 | 简单 |

### 简单件批 2（9 件 = 8 新 + 1 结构体族 2 件并入计数行分列）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| S10 | ST_DL_EtSlaveDiagBase | DL_Device | ST | EtherCAT 从站诊断基结构（clean-room 重构，去厂商哈希后缀） | queue:EtcSlaveBase_82538BE2（TcOpen MIT） | C2 | S2 | 简单 |
| S11 | ST_DL_EtSyncUnitDiagBase | DL_Device | ST | EtherCAT 同步单元诊断基结构（clean-room） | queue:SyncUnitsBase_AD6C35CE（TcOpen MIT） | C2 | S2 | 简单 |
| S12 | FB_DL_DitherSignalGen | DL_MathData | FB | 抖动信号发生（可设幅值/带宽，ADC 精度域配套） | self（信号发生族补口） | C2 | S2 | 简单 |
| S13 | FC_DL_MoistureContentCalc | DL_MathData | FC | 失重法含水率计算（湿/干重比值域闸） | self（公开公式） | C1 | S2 | 简单 |
| S14 | FB_DL_ParamSnapshotRestore | DL_Base | FB | 参数快照/恢复：双缓冲保存与一键回滚 | self（参数管理族） | C2 | S2 | 简单 |
| S15 | FB_DL_SignalCrossbar8 | DL_Base | FB | 8×8 信号交叉开关矩阵（任意路由，与 Mux2/4Ex 区分） | self（信号路由族） | C2 | S2 | 简单 |
| S16 | FC_DL_WorkdayCalendarCalc | DL_Base | FC | 工作日历计算：给定日期区间内工作日计数（含节假日表） | self（日历族补口） | C2 | S2 | 简单 |
| S17 | FB_DL_SmokeDetZoneMon | DL_Base | FB | 消防烟雾探测分区监视：分区报警/故障/屏蔽三态与锁存 | self（消防域） | C2 | S2 | 简单 |
| S18 | FB_DL_VocVentTrim | DL_Process | FB | VOC 浓度需求通风 trim（与 CO2 需求通风同构异介质） | self（HVAC 域延伸） | C2 | S2 | 简单 |

### 简单件批 3（8 行 = 5 新 + 3 修复）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| S19 | FC_DL_GearRatioCalc | DL_Motion | FC | 齿轮减速比/负载惯量比换算 | self（机械传动族） | C1 | S3 | 简单 |
| S20 | FB_DL_CrankKinFwd | DL_Motion | FB | 曲柄滑块机构正运动学（曲柄角 → 滑块位移） | self（运动学） | C2 | S3 | 简单 |
| S21 | FC_DL_BeltLengthCalc | DL_Motion | FC | 带传动节线长度计算（轮径/中心距 → 长度） | self（机械传动族） | C1 | S3 | 简单 |
| S22 | FC_DL_OvershootPctCalc | DL_Algo | FC | 阶跃响应超调量百分比计算 | self（回路 KPI 族） | C1 | S3 | 简单 |
| S23 | FC_DL_SettleTimeCalc | DL_Algo | FC | 阶跃响应整定时间计算（±容差带进入判据） | self（回路 KPI 族） | C2 | S3 | 简单 |
| S24 | FB_DL_DryerExhaustHumidityCtl（修复） | DL_Process | FB | **修复名额 ②**：R73 挂账多出参 FC 零回执调用点点修（R333 口径候审转实施） | R73 待办 | C2 | S3 | 修复 |
| S25 | FB_DL_WeightClassifySort（修复） | DL_Process | FB | **修复名额 ③**：R73 零回执候审点修 | R73 待办 | C2 | S3 | 修复 |
| S26 | FB_DL_ChamberPurgeDry（修复） | DL_Process | FB | **修复名额 ④**：R73 零回执候审点修（VaporPressureSat 族同批次回执口径对齐） | R73 待办 | C2 | S3 | 修复 |

### 分类分布核对（新件 36 + 修复 4 = 40）

| 分类 | 新件数 | 建议上限 | 判定 |
|---|---|---|---|
| DL_Base | 8（C11+S04+S06+S07+S14+S15+S16+S17） | ≤8 | ✔ 贴上限 |
| DL_MathData | 10（C06+C09+S01+S02+S03+S05+S08+S09+S12+S13） | ≤10 | ✔ 贴上限 |
| DL_Device | 6（C01+C04+C10+C12+S10+S11） | ≤8 | ✔ |
| DL_Process | 5（C02+C05+C07+C08+S18） | ≤6 | ✔ |
| DL_Motion | 4（C03+S19+S20+S21） | ≤5 | ✔ |
| DL_Algo | 3（C13+S22+S23） | ≤5 | ✔ |
| 合计新件 | **36** | — | 修复 4 件为存量文件点修，不增分类计数 |

复杂度分档：复杂 13 新（C3×5 / C4×6 / C5×3……见总表逐行）+ 简单 23 新，与配额 14+26（含 4 修复）对齐。

---

## §3 查重记录（撞名三查留痕）

对 registry（1,252 件，`components` 列表实时精确匹配）执行 5 轮关键词扫查（cabs/hypot/swap/gray/window/manual/…/burner/flame/extruder/filterpress/weekday/dateadd/blink/snapshot/crossbar 等 120+ 关键词）。**驳回 28 条**：

### 3.1 队列候选驳回（9 条）

| # | 队列候选 | 驳回原因（属主/依据） |
|---|---|---|
| 1 | HYPOT | `FC_DL_Hypot3D` 在册，且 `FC_DL_EuclidDist2DCalc`（R74）已收 2D 欧氏距离 —— 同语义 |
| 2 | SWAP_BYTE | `FC_DL_SwapBytes16/32/64` 三位宽属主在册 —— 同语义 |
| 3 | BYTE_TO_GRAY | `FC_DL_BinaryToGray` 在册（另有 `GrayToByteConv`）—— 同语义 |
| 4 | TANK_VOL1 | `FC_DL_TankVolumeHoriCyl` 在册 —— 卧式罐容积精确同语义（R74 已收 TankVolCylHoriz 系） |
| 5 | F_LIN | `FC_DL_LerpClamped` + `FC_DL_InterpolateTable2D` 家族覆盖两点线性插值 —— 同语义 |
| 6 | F_POWER | 幂函数域已有属主（R63 PowSafe 已判同义邻件，`FC_DL_PowIntSat` 在册）—— 同语义 |
| 7 | SCALE | `FC_DL_LinearScale` 在册 —— 精确同语义 |
| 8 | NEGX | `FC_DL_AbsEx`/`FC_DL_WrapIndexNeg` 域覆盖 + 无独立工程价值 —— 凑数变体 |
| 9 | REAL_TO_DW（单列件） | 并入 S06 `FC_DL_DwRealReinterp` 双向往返单件 —— 防拆件凑数（R63 AllpassFilter 判例口径） |

队列其余落选说明：InputBase/OutputBase/EtcMasterBase/SyncUnitTaskBase/SyncUnitTasksBase 5 条 TYPE 与 S10/S11 同族，本轮只取 2 件代表（从站/同步单元），余量留 ROADMAP 不硬凑（R228 枯竭阈值口径）；E_SMStatus 与 S04 语义重叠取一；FB_PI_Regler_Legacy（WTFPL 黄区）与 `FB_DL_PidController`/`TwoDofPid` 域重叠且红黄区降权，驳回。

### 3.2 非队列拟案驳回（19 条）

| # | 被否拟案 | 撞车主 |
|---|---|---|
| 10 | FB_DL_SmithPredictorDtc | FB_DL_SmithPredictor |
| 11 | FB_DL_GainSchedulerMap | FB_DL_GainScheduler / GainSchedPid |
| 12 | FB_DL_AxisBacklashComp | FB_DL_AxisBacklashComp（精确同名） |
| 13 | FB_DL_TorqueLimitGuard | FB_DL_TorqueLimitControl |
| 14 | FB_DL_FlyingCutoffSync | FB_DL_FlyingCutSync / FlyingShearSync / FlyingSawSyncSeq |
| 15 | FB_DL_LineChangeoverMatrix | FB_DL_ChangeoverSequence / LineChangeoverChecklist |
| 16 | FB_DL_OvenCureProfileSeq | FB_DL_CuringOvenSeq / DryingOvenZone |
| 17 | FB_DL_AndonStationSignal | FB_DL_AndonCallSystem 等 4 件 |
| 18 | FB_DL_CoolantSprayNozzleCtrl | FB_DL_SprayNozzleBank |
| 19 | FB_DL_BaghouseDpPulse | FB_DL_DustCollectorPulse（布袋脉冲同语义） |
| 20 | FB_DL_CarouselIndexCtrl | FB_DL_RotaryIndexTable |
| 21 | FB_DL_Vote2oo3Safety | FB_DL_Vote2oo3 / VoteKooN |
| 22 | FB_DL_BumplessHandover | FB_DL_BumplessTransfer / BumplessHandAuto |
| 23 | FB_DL_SplitRangeTrim | FB_DL_SplitRangeControl |
| 24 | FB_DL_RatioBlendCtrl | FB_DL_RatioController |
| 25 | FC_DL_QuadDecode4x | FB_DL_EncoderQuadCount |
| 26 | FC_DL_TimeOverlapCheck | FC_DL_RangeOverlapCheck |
| 27 | FB_DL_HandwheelJogTrim | FB_DL_AxisJogController |
| 28 | FC_DL_WeekdayFromDate / FC_DL_DtAddDays | FC_DL_DayOfWeekCalc / FC_DL_DateAddDays + DtAddSecondsSat |

另：FB_DL_KalmanScalarFilt（KalmanFilter1D）、FB_DL_RlsIdent（RlsEstimator）、FB_DL_GoertzelBand（GoertzelToneDetect）、FB_DL_OrificeCompCalc（OrificeFlowCalc）、FC_DL_RunningVarianceCalc（StdDevOnline）、FC_DL_PolyDividDiff（LagrangeInterp）预筛即弃，不计正式驳单。

### 3.3 必附邻件比对声明清单（R74 系统性发现 → 改名/邻件入库必附）

S04/S07→ToleranceWindow（单容差窗 vs 双窗三态）；C04/C10→StatusWordSegDecoder（通用分段 vs 变频器状态字匹配/编码）；S05→FirstOrderIdent（辨识 vs 响应）；C09→Lagrange/Hermite/CubicSpline（多项式样条族 vs Akima）；S03→Temp/Press/Flow/Angle/Torque UnitConvert（速度类缺位补口）；S08→PercentileLReal/PercentileRank（百分位 vs 四分位三值）；S09→ThdCalc/HarmonicSpectrumBin（电能质量族）；S12→SineGenerator/PulseGenerator（信号发生族）；S13→ElectrolyteMoistureGuard（防护 vs 计算）；S16→WeekNumIsoCalc/DateDiffDays（周号/差值 vs 工作日计数）；S19→GearInPhaseAlign（相位对齐 vs 传动比换算）；S21→FurnaceBeltTension/FanBeltSlipDiag（张力/打滑 vs 长度计算）；C03/S20→robot 族仅监视/抓取验证，无运动学属主；C13→PidController（通用 PID vs 冷热极性双向 TEC）；C02→PileClampCtrl（打桩夹桩 vs 注塑合模，行业域不同）；C06→OrificeFlowCalc（孔口 vs 堰流）；C07→DosingPumpCalib/BatchDosingControl（标定/批量 vs 余氯 trim）；S18→RoomCo2DemandVent（CO2 vs VOC 同构异介质）；C08→无离心序列属主；S10/S11→ProfinetAlarmDiag（PROFINET vs EtherCAT，协议域不同）；S14→DeviceParamVerify/DeviceParamWrite（验证/写入 vs 快照回滚）；S15→Mux2Ex/Mux4Ex（单选 vs 8×8 矩阵）；S06→无位重解释属主；S17→EStopMonitor（急停 vs 分区探测监视）。

---

## §4 批次派发方案

| 批次 | 内容 | 派发对象 | 时窗 |
|---|---|---|---|
| 复杂 B1（C01~C05） | C5×3 + C4×1 + C3×1，含 Device 2 / Process 2 / Motion 1 | PLC 编码专家（原生召唤 ×1） | 前 25′ |
| 复杂 B2（C06~C10） | MathData 2 + Process 2 + Device 1 | PLC 编码专家（与 B1 并行槽位） | 前 25′ |
| 复杂 B3（C11~C14） | Base 1 + Device 1 + Algo 1 + 修复 1（CamTableInterp 点数字段） | PLC 编码专家（第二次召唤：生产批+修复批合并） | 中段 15′ |
| 简单 S1（S01~S09） | 队列溯源 7 件 + self 2 件 | PLC 编码专家 | 中段 15′ |
| 简单 S2（S10~S18） | 队列 TYPE 2 件 + self 6 件 | PLC 编码专家 | 中段 15′ |
| 简单 S3（S19~S26） | 新 5 + 修复 3（R73 零回执候审） | PLC 编码专家（合并至回修批） | 后段 |
| L2 编译闸 | 串行 jobs=1，42~44 检 | 主控直跑（R74 口径） | 收尾 |
| 终审 + 收口 | 台账三向一致 + 进化周报 | 主控直跑（R335） | 12:53 前 |

派发纪律：编码前语义查重强制化（R15 候选规则）；FB 内禁 PROPERTY（R16 候选规则，预处理器未上线前新件一律规避 FB 内 PROPERTY 写法）；新件附邻件比对声明（§3.3 清单逐件核对）。

---

## §5 并行工程任务清单（不占组件名额）

| # | 任务 | 责任角色 | 说明 |
|---|---|---|---|
| P0-① | **闸侧 FB-PROPERTY 剥离预处理器**：`l2_check.py` / `iface_stub_gen.py` 增加 FB 内 PROPERTY 剥离降级（与接口桩同口径），解 SingleAxis / BatchDosingControl 两豁免件，回验 I_DL_ExternalEncoder / I_DL_MotionAxis 桩口径 | 编译验证工程师 | R74 战报 P0-①，工具改造 |
| P0-② | `FC_DL_CamTableInterp` 显式点数字段解 VLA | PLC 编码专家 | 已占名额（C14 修复行） |
| P0-③ | 「改名入库须附最近语义邻件比对声明」规则落地 PLC 编码专家 skills | 审校去重官 | R74 P0-③，不占名额 |
| P0-④ | 「同名避让」历史入库件语义复核（脚本预筛 + 人工判定） | 审校去重官 | R74 P0-④，不占名额 |
| 值守 | MatIEC CI remote 配置 / oss_harvest token 单仓试跑 / GATE MAJOR 存量人核 | 值守项 | 第 6 轮顺延，不占编码配额 |

配额外备选池（本轮验证属主为空、因配额未列，转 ROADMAP）：FB_DL_ExtruderMeltPressCtrl（Device C4）、FB_DL_FilterPressSqueezeSeq（Process C4）、FB_DL_OpcUaHealthProbe（Device C3）、FB_DL_BallMillLoadEst（Algo C4）、ST_DL_EtMasterDiagBase 等 EtherCAT 结构族余量 5 条。

---

*R75 规划 ｜ 2026-11-23 ｜ 道莅工控代码库产品总监（主控直跑 R335）｜ 只做规划，未写任何 .st，未动 INDEX_REGISTRY.json*
