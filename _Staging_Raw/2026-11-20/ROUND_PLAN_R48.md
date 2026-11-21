# R48 阶段一目标锁定（20 件）

生成：2026-11-20 01:5x ｜ 基线：总库 845 / 10,000 ｜ 今日 0/200 ｜ registry v2.39.0（Base 91 / MathData 202 / Algo 91 / Motion 89 / Device 161 / Process 211）
前置：R47 终审 5 抽挂账 1 件轻返修（FB_DL_ModulePottingVac v1.0.1，见 §4）；R47 轮 Algo 让位 0 件 → 本轮补薄 ≥5。

## 0. 选题纪律声明

- **零同名反证（R240 / R290 三处比对）**：下列 20 名全部对 `INDEX_REGISTRY.json`（v2.39.0，845 件）+ 六个 `DL_*\*.st` 文件树 + 各 `MANUAL_DL_*.md` 索引做三处比对（名单快照见本目录 `_names_r48.txt`），20/20 零命中（2026-11-20 01:5x 实测）。
- **同义邻件双查（R28 / R313）**：候选剔除 9 名（见 §2），重叠 >60% 一律不入。
- **品类纠偏（R270）**：Algo 5 / Motion 4 / Base 3 / Device 3 / MathData 2 / Process 3 —— MathData（≤2 达标）与 Process（≤5 只用 3，纠偏下探）双降配，Algo 补 R47 让位欠账。
- **T0 = 0**：矩阵 T0 八组已收口余量 0，本轮零 T0 件，不硬凑。
- **批次约束**：4 批 × 5，批内零 `.st` 文件级依赖（全部叶子件，仅引用既有存量类型或纯 Standard.library）；纯函数 FC 与底层 FB 前置，组合型 FB 后置。
- **零码位范式（R46 起延续）**：出口 BOOL + ENUM，头注释「码位待收口统一派号」，编码禁 16# 事件码。

## 1. 20 件目标清单

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次(1-4) |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_SaturateSub` | DL_Base | FC | 有符号整数饱和减法（与 FC_DL_SaturateAdd 成对，防下溢回绕，结果钳 MIN/MAX 并置溢出位） | 自研线（成对补口） | 2 | 1 |
| 2 | `FC_DL_SimpsonQuad` | DL_MathData | FC | 辛普森 1/3 抛物线数值积分（等距节点单遍求积；偶数区间数拒算、非有限样本前置闸） | T2-1 LGF · Math 数学子族 | 3 | 1 |
| 3 | `FC_DL_LagrangeInterp` | DL_MathData | FC | 任意散点拉格朗日插值（n 点多项式单点求值；与 CubicSplineInterp 分工：无样条连续性要求、点数 2~8 的小样本域） | T2-1 LGF · Math 数学子族 | 3 | 1 |
| 4 | `FB_DL_ModeArbiter` | DL_Base | FC→FB | 多源模式请求优先仲裁（手动＞自动＞远程三级抢占 + 回退降级 + 抢占/释放沿出口，与 MutexOwnerAudit 分工：模式级 ≠ 互斥锁级） | 自研线 | 4 | 1 |
| 5 | `FB_DL_HoldRepeatButton` | DL_Base | FB | HMI 按钮长按连发（初延时 + 重复周期 + 释放即停，与 MultiClickDetect 分工：连发 ≠ 连击识别） | 自研线 | 3 | 1 |
| 6 | `FB_DL_SensorFusion2` | DL_Algo | FB | 双传感器方差加权融合（按在线噪声方差倒数动态配权 + 一致性偏差闸，与 KalmanFilter1D 分工：静态双源融合 ≠ 单流递推滤波） | 自研线（公开加权融合公式） | 4 | 2 |
| 7 | `FB_DL_BiasAdaptiveTrim` | DL_Algo | FB | 稳态偏置自适应修调（误差带外积分、带内泄漏遗忘、限幅输出，与 Integrator 分工：带遗忘的闭环修调 ≠ 纯积分） | 自研线 | 4 | 2 |
| 8 | `FB_DL_FuzzyTrim2In` | DL_Algo | FB | 二维模糊规则表修调（误差/误差变化率 3×3 或 5×5 规则表 → 输出修调量，Mamdani 结构只借不抄） | 自研线（T2-5 参数域只借） | 5 | 2 |
| 9 | `FB_DL_Decouple2x2` | DL_Algo | FB | 2×2 强耦合回路静态解耦（T21/T22 解耦网注入，Bristol 相对增益只作组态参考，输出侧注入限幅） | 自研线（公开 Bristol RGA 公式） | 4 | 2 |
| 10 | `FB_DL_SolenoidCoilHealth` | DL_Device | FB | 电磁阀线圈健康诊断（吸合电流峰值 / 保持电流偏差双窗判据 + 欠流/过流分码，与 ContactorWeldDetect 分工：线圈电气健康 ≠ 触点熔焊） | T2-6 Rockwell AOI · 设备诊断粒度（只借分类） | 4 | 2 |
| 11 | `FB_DL_HeaterBreakDetect` | DL_Device | FB | 加热管断棒检测（通电电流对比 + 温升速率双判据，判据二仅在判据一存疑时介入降误报；与 SsrHeaterDrive 分工：诊断 ≠ 驱动） | T2-6 Rockwell AOI · 设备诊断粒度（只借分类） | 4 | 3 |
| 12 | `FB_DL_VibZoneClassify` | DL_Device | FB | 旋转设备振动 ISO 10816 分区（RMS 速度按机座等级分 A/B/C/D 区 + 区间跃迁迟滞，与 RobotArmVibrationWatch 分工：通用机泵分区 ≠ 机械臂专项监视） | T2-8 ISO 10816 公开分区（只借分区事实） | 3 | 3 |
| 13 | `FB_DL_GapForceSwitchover` | DL_Algo | FB | 压机位置/压力双模式无扰切换（接近段位置控 → 接触检测 → 压力段力控，切换点速度/输出保持衔接） | T2-2 LBP · 压机工艺分类（只借分类） | 6 | 3 |
| 14 | `FB_DL_LoadShareDroop` | DL_Motion | FB | 多轴负载均衡 droop 调差（按各轴负载百分比对速度基准做 droop 修正，防单轴吃载；与 GantrySyncAxis 分工：负载均衡 ≠ 几何同步） | T1-6 PLCopen MC 语义（只借语义） | 5 | 3 |
| 15 | `FB_DL_ZoneSpeedTrim` | DL_Motion | FB | 轴位置区段限速（按轴实际位置区间动态改写速度上限，出区段回默认值 + 区段表越界钳位；与 SoftLimitGuard 分工：动态限速 ≠ 静态软限位） | T1-6 PLCopen MC 语义（只借语义） | 4 | 3 |
| 16 | `FB_DL_ContourCrossCouple` | DL_Motion | FB | 双轴轮廓交叉耦合控制（两轴跟随误差合成轮廓误差 → 从轴修调注入，与 GantrySkewMonitor 分工：闭环修调 ≠ 偏差监视） | T1-6 PLCopen MC 语义（只借语义） | 6 | 4 |
| 17 | `FB_DL_LookaheadVelPlanner` | DL_Motion | FB | 多段路径前瞻速度规划（段间拐角限速 + 相邻段合并减速带 + 前瞻窗口深度可组态；与 SCurveGenerator 分工：段间衔接规划 ≠ 单段 S 曲线） | T1-6 PLCopen MC 语义（只借语义） | 6 | 4 |
| 18 | `FB_DL_AutoclaveSterilSeq` | DL_Process | FB | 灭菌釜脉动真空灭菌程序（脉动置换 → 升温 → 保压灭菌 → 排气干燥四段 + 段间 F0 值累计闸） | T2-2 LBP 工艺分层（只借分类） | 6 | 4 |
| 19 | `FB_DL_TunnelPasteurizerSeq` | DL_Process | FB | 隧道式巴氏杀菌段序（预热 → 杀菌 → 冷却三温区段推进 + 杀菌段温度带驻留闸 + 出口温降联锁） | T2-2 LBP 工艺分层（只借分类） | 5 | 4 |
| 20 | `FB_DL_PumpPrimingSeq` | DL_Process | FB | 泵引水/自吸排气顺控（灌液 → 排气 → 出口压力确认 → 转主运，引水失败重试计数上限；与 PumpChangeoverSeq 分工：引水启动 ≠ 主备切换） | T2-2 LBP 工艺分层（只借分类） | 5 | 4 |

## 2. 零同名反证句（逐条，三处比对：registry 845 件 + DL_* 文件树 + MANUAL 索引）

1. `FC_DL_SaturateSub` — 三处 0 命中；与 `FC_DL_SaturateAdd`（R4x 成对件）方向互补不重叠（减法下溢域）。
2. `FC_DL_SimpsonQuad` — 三处 0 命中（全库无数值积分 FC）；与 `FC_DL_PolyEvalHorner`（多项式求值 ≠ 求积）无重叠。
3. `FC_DL_LagrangeInterp` — 三处 0 命中；与 `FC_DL_CubicSplineInterp` / `FC_DL_MultiPointLinear` 分工：小样本多项式插值 ≠ 样条/分段线性。
4. `FB_DL_ModeArbiter` — 三处 0 命中；与 `FB_DL_MutexOwnerAudit`（互斥锁属主审计）、`FB_DL_DeviceHealthArbiter`（健康裁决）分工：运行模式请求仲裁域。
5. `FB_DL_HoldRepeatButton` — 三处 0 命中；与 `FB_DL_MultiClickDetect` 分工：长按连发 ≠ 连击计数。
6. `FB_DL_SensorFusion2` — 三处 0 命中；与 `FB_DL_KalmanFilter1D`（单流递推）与 `FB_DL_RedundantSwitch`（二选一切换）分工：双源加权融合。
7. `FB_DL_BiasAdaptiveTrim` — 三处 0 命中；与 `FB_DL_Integrator`（纯积分）分工：带泄漏遗忘的偏置修调闭环。
8. `FB_DL_FuzzyTrim2In` — 三处 0 命中（全库无 Fuzzy 族）；规则表结构公开，clean-room。
9. `FB_DL_Decouple2x2` — 三处 0 命中（无 Decouple/CrossCouple 类 Algo 件）；与 `FB_DL_CascadePid`（串级 ≠ 解耦）无重叠。
10. `FB_DL_SolenoidCoilHealth` — 三处 0 命中；与 `FB_DL_SingleSolenoidCyl`（驱动）与 `FB_DL_ContactorWeldDetect`（熔焊）分工：线圈电气健康诊断。
11. `FB_DL_HeaterBreakDetect` — 三处 0 命中（无 *Break* 诊断件）；与 `FB_DL_SsrHeaterDrive` / `FB_DL_HeaterSsrBank`（驱动/组bank）分工：断棒诊断。
12. `FB_DL_VibZoneClassify` — 三处 0 命中；与 `FB_DL_RobotArmVibrationWatch` 分工：ISO 10816 通用分区 ≠ 机械臂专项。
13. `FB_DL_GapForceSwitchover` — 三处 0 命中；与 `FB_DL_CoatingGapMeasure`（测量）与 `FB_DL_RollCompressForceBalance`（力平衡趋势）分工：位置/压力切换闭环。
14. `FB_DL_LoadShareDroop` — 三处 0 命中（无 Droop/LoadShare 件）；与 `FB_DL_GantrySyncAxis` 分工已声明。
15. `FB_DL_ZoneSpeedTrim` — 三处 0 命中；与 `FB_DL_SoftLimitGuard`（静态限位）与 `FB_DL_ConveyorZone`（输送段跟踪，Process）分工。
16. `FB_DL_ContourCrossCouple` — 三处 0 命中；与 `FB_DL_GantrySkewMonitor`（监视）分工：闭环修调。
17. `FB_DL_LookaheadVelPlanner` — 三处 0 命中（无 Lookahead 件）；与 `FB_DL_SCurveGenerator` / `FB_DL_MotionCmdQueue` 分工已声明。
18. `FB_DL_AutoclaveSterilSeq` — 三处 0 命中（无 Autoclave/Steril 件）。
19. `FB_DL_TunnelPasteurizerSeq` — 三处 0 命中（无 Pasteur 件）。
20. `FB_DL_PumpPrimingSeq` — 三处 0 命中；与 `FB_DL_PumpChangeoverSeq` / `FB_DL_PumpDryRunGuard` / `FB_DL_PumpDryRunProtect` 分工已声明。

## 2b. 被剔除候选记账（9 条，注明撞的是哪一件）

| # | 剔除候选 | 剔除原因 |
|---|---|---|
| 1 | `FB_DL_SetpointApproachBrake` | 与 `FB_DL_ThermalRampPredict` 语义重叠 >60%（升温预测与提前减速同域），剔 |
| 2 | `FC_DL_EmaUpdate` | 与 `FC_DL_WeightedMovingAvg` / `FB_DL_MovingAverage` 平滑语义重叠 >60%，剔 |
| 3 | `FB_DL_SignalBreakDetect` | 与 `FB_DL_SignalFrozenDetect`（信号恒值/断线判据）重叠 >60%，剔 |
| 4 | `FB_DL_SafetyValvePopTest` | 与 `FB_DL_PressureReliefMonitor`（泄压监视）重叠，剔 |
| 5 | `FB_DL_NgRetestQueue` | 与 `FB_DL_StringFifoRetry` / `FB_DL_ElectrolyteFifoTrace` 重试队列语义重叠 >60%，剔 |
| 6 | `FB_DL_ConveyorAccumTable` | 与 `FB_DL_BufferMagazine`（缓存缓存段）重叠 >60%，剔 |
| 7 | `FB_DL_TorqueRippleComp` | 与 `FB_DL_AxisCoggingFf`（按角度周期前馈注入）重叠 >60%，剔 |
| 8 | `FB_DL_DeadtimeCompAdaptive` | 与 `FB_DL_SmithPredictor`（纯滞后补偿）重叠 >60%，剔 |
| 9 | `FB_DL_KilnSoakHoldCtrl` | 与 `FB_DL_FiringFurnaceZone`（烧成炉区控）重叠 >60%，剔 |

## 3. 班次配额核对（R270 品类纠偏）

| 子库 | 本轮件数 | 配额 | 达成 | 收口后累计（845+20） |
|---|---|---|---|---|
| DL_Base | 3 | ≥3 | ✅ 3 | 94 |
| DL_MathData | 2 | ≤2 | ✅ 2（顶格不再加） | 204（24.2%，占比续降） |
| DL_Algo | 5 | ≥5 | ✅ 5（补 R47 让位欠账） | 96 |
| DL_Motion | 4 | ≥4 | ✅ 4 | 93 |
| DL_Device | 3 | ≥3 | ✅ 3 | 164 |
| DL_Process | 3 | ≤5 | ✅ 3（纠偏下探，未顶格） | 214（24.6%，占比续降） |
| 合计 | 20 | 20 | ✅ | 865 |

## 4. 返修项（第 21 项，不占新件额度）

**FB_DL_ModulePottingVac（DL_Process）v1.0.0 → v1.0.1 ｜ 引脚契约零变更**

- **缺陷现象（R47 终审 5 抽轻项）**：`bVacReached` / `bBreakDone` 若来自「到位脉冲」型传感器（如压力开关瞬时动作），脉冲先于 `tonEvacTo.Q` / `tonBreakTo.Q` 到来并已消失，过相判据 `tonEvacTo.Q AND bVacReached` 恒假 → 到位明明发生过仍误报 `eVacTimeout` / `eBreakTimeout`，且复位重启后若脉冲不再重现则必复锁（解除式形式可满足、实际现场难满足）。
- **修法要点 ①**：段 0 增 `rtVacIn` / `rtBreakIn` 两枚 R_TRIG（无条件刷新）+ 锁存量 `_bVacSeen` / `_bBreakSeen`；进相（eEvac / eBreak 首拍）清锁存，捕获到位沿后置位。
- **修法要点 ②**：过相判据改 `tonEvacTo.Q AND _bVacSeen`（破空相同理）；超时判据相应改 `tonEvacTo.Q AND (NOT _bVacSeen)`；持续到位信号行为不变（契约兼容）。
- **修法要点 ③**：迁出链（bReset 沿 / bStop）同时清 `_bVacSeen` / `_bBreakSeen`，防跨循环残留（R310/R311「复位沿不清状态回夹」同族预防）。
- **修法要点 ④**：头注释补边界⑥「到位信号沿锁存语义」+ 修订历史 v1.0.1 行；**零引脚增删改**；验收向量：V1 脉冲到位 + 超时到 → 过相不误报；V2 中止/复位后重启无残留锁存；V3 持续到位仍按原语义等满超时窗（兼容性自证）。
