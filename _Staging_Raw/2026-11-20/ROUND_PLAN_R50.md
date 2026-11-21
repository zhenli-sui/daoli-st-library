# R50 轮次计划（2026-11-20 · 无人值守批处理 · 阶段一规划）

> 规划人：工控代码库产品总监（阶段一规划代理）
> 硬性预算：禁全库扫描，仅读 INDEX_REGISTRY.json（name 字段提取）/ ROADMAP.md / SOURCE_HUNTING_MATRIX.md 三件。
> 品类纠偏执行：MathData = 2（上限 2 ✔）｜ Algo = 6 / Motion = 5（补位 R32~R35 连续四轮 Process/MathData 重产让位）｜ Base = 4 ｜ Device = 3 ｜ Process = 0（让位补偿）｜ T0 八组 ✔ 余量 0，不硬凑。
> 待办纪律：ROADMAP 未新增任何待办条目；本轮 20 件全部取自源矩阵 ◐ 行已登记的「待挖」子项（拆到可独立验收粒度）+ 自研线缺口，零重复开挖、零凑数变体。
> 检索成本：WebSearch 0 次（零检索轮，与 R27/R30/R32 先例同口径），全部候选源自矩阵既有条目与公开规范语义。

## 0 选题双查纪律执行（R28 固化 3）

每件候选均执行「全库同名 grep -c = 0 + 同义邻件扫描」双查，**本轮双查共拦截 21 个候选名**，全部剔除换补，逐条反证句如下表（grep 对象：INDEX_REGISTRY.json 全部 885 个 name 字段）：

| # | 组件名 | 反证句 | 被拦截的弃名（同义邻件，已剔除） |
|---|---|---|---|
| 1 | FB_DL_FrequencySweepGen | grep -c 'FrequencySweepGen' = 0 | FrequencyGenerator / FrequencyMeasure / PulseGenerator / SineGenerator 均存量，职责边界见派单表 |
| 2 | FB_DL_FirFilter | grep -c 'FirFilter' = 0 | LowPassFilter / SecondOrderFilter / HighPassFilter / NotchFilter 均存量 |
| 3 | FB_DL_CusumMonitor | grep -c 'CusumMonitor' = 0 | PeakDetector / SignalStatistics / R2rEwmaTuner 均存量 |
| 4 | FB_DL_ShewhartRules | grep -c 'ShewhartRules' = 0 | OscillationIndex / LoopPerfIndex 均存量（判异≠性能指数） |
| 5 | FB_DL_FlowBalanceCheck | grep -c 'FlowBalanceCheck' = 0 | PhaseNeutralImbalance / BatteryModuleBalanceMonitor 均存量 |
| 6 | FB_DL_GoertzelToneDetect | grep -c 'GoertzelToneDetect' = 0 | 无 FFT/tone/spectrum 族（grep 空集） |
| 7 | FB_DL_GearDecouple | grep -c 'GearDecouple' = 0 | ElectronicGear（耦合侧）/ Decouple2x2（MIMO 过程解耦）均存量 |
| 8 | FB_DL_CamDynTrim | grep -c 'CamDynTrim' = 0 | ElectronicCam / CamTableValidate 均存量 |
| 9 | FB_DL_AxisTorqueFeedforward | grep -c 'AxisTorqueFeedforward' = 0 | AxisTorqueWatch / AxisLoadTorqueMonitor（诊断）/ AxisInertiaIdent（辨识）均存量 |
| 10 | FB_DL_AxisScrewPitchComp | grep -c 'AxisScrewPitchComp' = 0 | AxisBacklashComp（反向间隙）存量，螺距误差为独立语义 |
| 11 | FB_DL_AxisThermalComp | grep -c 'AxisThermalComp' = 0 | ThermalI2tModel / VfdThermalDerate / ThermalRampPredict 均存量且域不同（电机/变频/工艺） |
| 12 | FB_DL_DebounceBank | grep -c 'DebounceBank' = 0 | FB_DL_SignalDebounce（单通道）存量，NtcTempScan 粗粒度先例 |
| 13 | FB_DL_EStopMonitor | grep -c 'EStopMonitor' = 0 | 无 EStop/emergency 族（grep 空集） |
| 14 | FB_DL_OutputForcingBank | grep -c 'OutputForcingBank' = 0 | 无 forcing/force-maintain 族（GapForceSwitchover 等为工艺域不同语义） |
| 15 | FB_DL_SignalHoldResume | grep -c 'SignalHoldResume' = 0 | HoldRepeatButton / ToggleButtonBank（HMI 按钮域）存量且不同域 |
| 16 | FC_DL_PressUnitConvert | grep -c 'PressUnitConvert' = 0 | TempUnitConvert（温标域）存量 |
| 17 | FC_DL_CircleFit3Pt | grep -c 'CircleFit3Pt' = 0 | PolygonArea / LineIntersection / CubicSplineInterp 均存量 |
| 18 | FB_DL_SafetyMuteZone | grep -c 'SafetyMuteZone' = 0 | SafetyDoor / SafetyLightCurtain（本体）存量，muting 联动语义独立 |
| 19 | FB_DL_HydraulicPowerUnit | grep -c 'HydraulicPowerUnit' = 0 | 无 hydraulic 族（grep 空集） |
| 20 | FB_DL_SensorSupplyMon | grep -c 'SensorSupplyMon' = 0 | 无 supply-mon 族（grep 空集） |

**双查拦截记录**（弃名→撞名证据，下轮防重复立项）：RelayAutoTune→RelayAutoTune/AutoTuneRelay 双存量｜StepResponseIdent 存量｜LoopPerfMonitor→LoopPerfIndex/OscillationIndex｜PressureLeakTest→LeakTestStation/AirLeakDecayTest/ChamberLeakRate｜AxisVibrationGuard→RobotArmVibrationWatch｜ValveSeatLeakMon→ValveSeatLeakWatch｜CpCpkCalc→CpkCalc/CpkIndex｜AxisRotaryWrap→AxisRotaryShortPath/RotaryIndexModulo｜HomeOffsetTeach→AxisTeachOffset｜LineRegress→LinearRegression2Var｜GripperDualCheck→I_DL_Gripper/ParallelGripper｜AirMixPointCalc→MixAirStateCalc｜WetBulbCalc→WetBulbTempCalc｜AutoZeroCal→CheckweighZeroTrack/OrificeDpZeroTrim/VavBoxZeroCal｜ButtonPressGen→HoldRepeatButton/ToggleButtonBank｜CmdPriorityArb→ModeArbiter/FirstOutLatch｜HealthArbiter→DeviceHealthArbiter｜EscCurrentMonitor→EscChuckCurrentMonitor｜PnAlarmDiagParse→PnAlarmDiagParse/ProfinetAlarmDiag｜NotchFilter/LeadLagComp/CamSwitchBank/AxisBacklashComp/HistogramBin/HermiteInterp→各自存量。

## 1 源账目（逐件）

| 来源标签 | 件数 | 提取点 |
|---|---|---|
| T2-1 LGF Signal Generators（频率发生族待挖收口） | 1 | #1 FrequencySweepGen |
| T2-1 LGF Measurement（滤波/统计族待挖） | 3 | #2 FirFilter、#3 CusumMonitor、#4 ShewhartRules（判异规则取 Western Electric 公开规则集，clean-room） |
| T2-1 LGF Technology / 自研 | 1 | #5 FlowBalanceCheck（自研线：质量守恒核对语义） |
| T1-8 GitHub topics DSP 线（自研 clean-room） | 1 | #6 GoertzelToneDetect（Goertzel 算法为公开 DSP 经典，零代码行复制） |
| T1-6 PLCopen Motion（脱耦/修调待挖） | 2 | #7 GearDecouple（MC_GearOut 语义）、#8 CamDynTrim（R8 留扩产项「凸轮动态修调」收口） |
| T2-4 S7 Motion 语义（次源） | 1 | #9 AxisTorqueFeedforward |
| 自研线（CNC 精补族开线） | 2 | #10 AxisScrewPitchComp、#11 AxisThermalComp |
| 自研线（批量粒度先例 NtcTempScan 范式） | 2 | #12 DebounceBank、#20 SensorSupplyMon |
| 自研线（安全/维护运维缺口） | 3 | #13 EStopMonitor、#14 OutputForcingBank、#18 SafetyMuteZone（muting 时序判据取 IEC 60204-1 / ISO 13849 公开条款，不作安全认证） |
| 自研线 | 1 | #15 SignalHoldResume |
| T2-1 LGF Converter（单位换算域平移） | 1 | #16 PressUnitConvert |
| 自研线（几何族扩族） | 1 | #17 CircleFit3Pt |
| 自研线（设备族空位） | 1 | #19 HydraulicPowerUnit |

配额结论：T2 源 5 件 + T1 源 2 件 + 自研线 13 件；零 ☐ 新开组，T1-6「凸轮动态修调」与 T2-1 LGF「频率发生族」两子族本轮收口；状态列全部不动（无整行 ✔）。

## 2 批次表（4 批 × 5，低复杂度在前，按依赖排序）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_PressUnitConvert | DL_MathData | FC | Pa/kPa/bar/psi/mmHg 五压力单位互转，含负压域与绝对零点守卫 | LGF Converter 域平移 | 2 | 1 |
| 2 | FB_DL_SignalHoldResume | DL_Base | FB | 暂停工况下对 N 路关键信号快照保持，恢复时带一致性校验释放 | 自研线 | 2 | 1 |
| 3 | FB_DL_SensorSupplyMon | DL_Device | FB | 多通道传感器供电压/公共端断线监视，逐通道掩码诊断出口 | 自研线 | 2 | 1 |
| 4 | FB_DL_DebounceBank | DL_Base | FB | 1~16 通道批量防抖（每通道独立升/降延时，粗粒度数组进数组出） | 自研线（NtcTempScan 范式） | 3 | 1 |
| 5 | FC_DL_CircleFit3Pt | DL_MathData | FC | 三点外接圆：圆心/半径求解 + 三点共线判（分母近零防御） | 自研线（几何族扩族） | 3 | 1 |
| 6 | FB_DL_CusumMonitor | DL_Algo | FB | CUSUM 累积和小偏移双向检测（正/负决策区间 + h 判限 + 复位） | LGF Measurement 统计族 | 3 | 2 |
| 7 | FB_DL_AxisScrewPitchComp | DL_Motion | FB | 丝杠螺距误差分段补偿表（按位置查表前馈补偿，方向无关） | 自研线（CNC 精补族开线） | 3 | 2 |
| 8 | FB_DL_AxisThermalComp | DL_Motion | FB | 轴热伸长补偿（温升一阶模型 + 行程比例分段，可禁用直通） | 自研线（CNC 精补族开线） | 3 | 2 |
| 9 | FB_DL_FirFilter | DL_Algo | FB | N 阶 FIR 系数数组滤波器（系数归一校验 + 窗口数组边界防御） | LGF Measurement 滤波族 | 4 | 2 |
| 10 | FB_DL_EStopMonitor | DL_Base | FB | 急停双通道一致性监视（失配确认窗 + 复位顺控 + 首出通道记录） | 自研线（IEC 60204-1 公开条款） | 4 | 2 |
| 11 | FB_DL_FlowBalanceCheck | DL_Algo | FB | 多进多出质量流量平衡核对（累计差 + 容差带 + 偏差分级出口） | 自研线 | 4 | 3 |
| 12 | FB_DL_OutputForcingBank | DL_Base | FB | 输出强制管理（逐点强制 + 强制激活告警字 + 使能撤除自动恢复） | 自研线 | 4 | 3 |
| 13 | FB_DL_FrequencySweepGen | DL_Algo | FB | 扫频发生器（输出频率按斜坡往返扫描，边界/方向/驻留可配） | LGF Signal Generators 频率发生族收口 | 4 | 3 |
| 14 | FB_DL_GearDecouple | DL_Motion | FB | 电子齿轮斜坡脱开（耦合比例按斜坡渐降至 1:1 再脱，防机械冲击） | T1-6 PLCopen（MC_GearOut 语义） | 4 | 3 |
| 15 | FB_DL_AxisTorqueFeedforward | DL_Motion | FB | 转矩前馈给定计算（惯量×加速度 + 粘滞摩擦模型，J 由辨识件注入） | T2-4 S7 Motion 次源 | 4 | 3 |
| 16 | FB_DL_ShewhartRules | DL_Algo | FB | 休哈特控制图判异（Western Electric 四条公开规则 + 违规位图 + 连长计数） | Western Electric 公开规则集 clean-room | 5 | 4 |
| 17 | FB_DL_SafetyMuteZone | DL_Device | FB | 安全区 muting 管理（双传感器顺序时序判据 + 静默窗超时 + 状态出口） | 自研线（ISO 13849 公开条款） | 4 | 4 |
| 18 | FB_DL_HydraulicPowerUnit | DL_Device | FB | 液压站驱动（电机卸荷阀压力带顺控 + 蓄能器监视 + 油温油位联锁） | 自研线（设备族空位） | 4 | 4 |
| 19 | FB_DL_CamDynTrim | DL_Motion | FB | 电子凸轮在线动态修调（运行中相位/比例小量 trim，斜坡生效防跳变） | T1-6 PLCopen（R8 留扩产项收口） | 5 | 4 |
| 20 | FB_DL_GoertzelToneDetect | DL_Algo | FB | Goertzel 单频点幅值检测（给定频率单 Bin 能量，用于共振/泄漏声学信号） | 公开 DSP 经典算法 clean-room | 5 | 4 |

## 3 并入派单的 5 件挂账返修（规格已定，非本轮新选）

| # | 组件名 | 返修内容 | 目标版本 |
|---|---|---|---|
| R-1 | FB_DL_LookaheadVelPlanner | 回溯步误用邻段长度 L[i+1]，减速距离改取本段 L[i]（前后对称修正）【中】 | v1.0.1 |
| R-2 | FB_DL_AutoclaveSterilSeq | 头注释补「bStop 保留 F0 累计」口径声明，逻辑如需微调保持兼容【轻】 | v1.0.1 |
| R-3 | FB_DL_SensorFusion2 | fTauVar=0 端点防护（下限钳位）【轻】 | v1.0.1 |
| R-4 | FB_DL_ContourCrossCouple | 非有限判据 NaN 补 Inf 判（统一口径）【轻】 | v1.0.1 |
| R-5 | FC_DL_SaturateSub | 头注释验收向量溢出断言更正（实现不动）【轻】 | v1.0.1 |

## 4 统计行

- 总库：885 / 10,000（v2.41.0）→ 本轮收口后预期 905 / 10,000（建议升 v2.42.0）。
- 今日（2026-11-20）：40 / 200 → 本轮 +20 后预期 60 / 200。
- 语料：886 条（本轮 20 新件 + 5 返修预期同步增补）。
- 距 1,000 差额：95（500 里程碑已超额 385）。
- 源矩阵覆盖率变化：零 WebSearch、零新源开组，各行状态列不动；T1-6「凸轮动态修调」、T2-1 LGF「频率发生族」两子族由「待挖」转收口（仅备注回写）。

## 5 派单红线提醒（编码专家必读）

1. 闭源只借分类/参数域/命名组织，clean-room；RAW_NOTES_R50 逐件记 来源/URL/许可证/提取点。
2. 七项红线：零 GVL/VAR_EXTERNAL、零 %I/%Q、纯 IEC 61131-3、防除零/越界/浮点容差、变量同行中英双语注释、ENUM+CASE 含 ELSE 兜底、TON/R_TRIG 实例无条件周期刷新。
3. 前缀 FB_DL_/FC_DL_/I_DL_/ST_DL_/E_DL_；变量声明后必须注册登记。
4. 本轮规则游标 R335，新规则从 R336 起。
5. 返修 5 件只按规格动最小范围，保持对外引脚契约不变，v1.0.1 记账。
