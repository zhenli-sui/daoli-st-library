# ROUND_PLAN_R73（2026-11-23 · 阶段一盘点与规划）

> 规划人：道莅工控代码库产品总监（R335 收口主控直跑纪律，规划不写 .st、不动 registry/JSONL）。
> 基线：registry v2.64.0，总库 1,218 件（Base 154 / MathData 294 / Algo 135 / Device 221 / Motion 126 / Process 288）。
> 配额：**20 新件**（复杂件 C3~C5 ×6 ＋ 简单件 C1~C2 ×14），建议分布 MathData 5 / Base 3 / Device 3 / Algo 3 / Motion 2 / Process 4，覆盖 6 子库。
> 预留：candidate_queue.jsonl 当前 0 行，猎人并行补料中——**30% 名额（约 6 件）预留候选到达后替换同名件**，替换须重跑三查留痕。
> 硬闸提醒：L2 真编译闸每轮交付资格项（R72 12/13 PASS）；编码前先过 coding-standard 红线清单与 R72「多出参 FC 必带回执」新规（见 §3）。

## 1 撞名三查记录（R214，对 registry 实时精确匹配）

**过审 20 件**（精确查重 0 命中，模糊邻件已逐一判定非同义）：
FlyingSawSyncSeq / CamTableOnlineBlend / FanSurgeMarginCalc / EmergencyStopChainDiag / TankFarmTransferSeq / ConveyorAccumGateSeq / MovingRangeCalc / PressureAltitudeCalc / SoundSpeedAirCalc / ExpMovingAvgCalc / TorqueUnitConvert / BitRotateEx / SignalRouteMatrix / SignalEdgeDelayEx / SensorSupplyWatch / ValveCycleCountBank / TcToFilterCoeff / DeadtimeTapCalc / HandAutoModeGateBank / OperatorAckBank。

**本轮拒单 7 条（留痕）**：
1. `FB_DL_FurnaceRampSoakProfile` → 模糊命中在册 `FB_DL_RampSoakProfile`（曲线发生器已有属主，撤题）。
2. `FC_DL_TimeClampEx` → 精确同名在册（撤题）。
3. `FC_DL_SatHumRatioCalc` → 与 `FC_DL_HumidityRatioCalc` 同义邻件，且焓湿图原子族 R23 已 ✔ 子族收口（R228 枯竭纪律，撤题）。
4. `FC_DL_SplitRangeCalc` → 同义邻件 `FB_DL_SplitRangeControl` 在册（撤题）。
5. `FB_DL_SetpointRateLimiter` → 同义邻件 `FB_DL_MfcSetpointRamp`（撤题）。
6. `FC_DL_FeedforwardGainCalc` → 模糊命中 4 个前馈族件（撤题）。
7. `FC_DL_WeekNumIsoEx` / `FB_DL_AxisHomingOffsetAudit` → 同义邻件 `FC_DL_WeekNumIsoCalc` / `FB_DL_AxisTeachOffset`+`FB_DL_AxisHomingSeq`（撤题）。

## 2 §1 新件派单总表（20 件）

| 序号 | 组件名 | 分类 | 前缀 | 功能一句话 | 来源标签 | 复杂度 | 批次 | 复杂/简单档 |
|---|---|---|---|---|---|---|---|---|
| 1 | FB_DL_FlyingSawSyncSeq | Motion | FB_DL_ | 飞锯电子凸轮同步切入＋切割＋同步返回全序列（相对同步轴补偿） | t1-6-plcopen 深化＋S-9 工程惯例 | C4 | 1 | 复杂 |
| 2 | FB_DL_CamTableOnlineBlend | Motion | FB_DL_ | 凸轮表在线无缝切换：双表交叉渐变加权，切换期相位不跳变 | t1-6-plcopen 深化（CamDynTrim 属主已判已覆盖，本件为表级切换非相修调） | C4 | 1 | 复杂 |
| 3 | FB_DL_FanSurgeMarginCalc | Algo | FB_DL_ | 风机工况点-喘振线裕度在线计算＋分级预警（防喘振开环余量） | 自研线（风机性能曲线公开口径） | C3 | 1 | 复杂 |
| 4 | FB_DL_EmergencyStopChainDiag | Device | FB_DL_ | 急停回路多节点（按钮/继电器反馈/复位）诊断聚合与断链定位 | t2-8-isa182 深化 | C3 | 1 | 复杂 |
| 5 | FB_DL_TankFarmTransferSeq | Process | FB_DL_ | 多罐收发转罐序列编排：泵/阀联锁＋液位目标切换＋路径互斥 | 自研线（t2-2-lbp 罐区分层复用） | C4 | 1 | 复杂 |
| 6 | FB_DL_ConveyorAccumGateSeq | Process | FB_DL_ | 输送线积放闸门序列：积放/释放/满流三态编排＋下游节拍联动 | s9-conv 工程惯例深化 | C3 | 2 | 复杂 |
| 7 | FC_DL_MovingRangeCalc | MathData | FC_DL_ | 滑动极差（相邻样本差）原子计算，SPC 判稳前置原子 | t2-1-lgf-measurement 深化 | C1 | 2 | 简单 |
| 8 | FC_DL_PressureAltitudeCalc | MathData | FC_DL_ | ISA 标准大气气压↔海拔双向换算（温度域闸＋防除零） | t1-2-oscat-building 语义借用（公开 ISA 公式） | C2 | 2 | 简单 |
| 9 | FC_DL_SoundSpeedAirCalc | MathData | FC_DL_ | 空气声速（温度/湿度函数）计算，超声流量/料位计前置换算 | t1-2-oscat-building 深化 | C2 | 2 | 简单 |
| 10 | FC_DL_ExpMovingAvgCalc | MathData | FC_DL_ | 指数移动平均（EMA）无状态原子：新样本＋旧均值＋α→新均值 | t2-1-lgf-math 深化 | C1 | 2 | 简单 |
| 11 | FC_DL_TorqueUnitConvert | MathData | FC_DL_ | 转矩单位换算 N·m↔kgf·m↔lb·ft（枚举选路＋域闸） | t0-std-wrapper 单位换算族补口 | C1 | 3 | 简单 |
| 12 | FC_DL_BitRotateEx | Base | FC_DL_ | 位串循环移位（左/右×BYTE/WORD/DWORD，跨位回卷） | t0-std-wrapper 包装族补口（ShlEx/ShrEx 邻件分工声明） | C2 | 3 | 简单 |
| 13 | FB_DL_SignalRouteMatrix | Base | FB_DL_ | 2×N 可组态信号路由矩阵（使能×来源选择×断源哨兵） | t2-1-lgf-bitlogic 深化 | C2 | 3 | 简单 |
| 14 | FB_DL_SignalEdgeDelayEx | Base | FB_DL_ | 边沿延迟输出：上升/下降沿各自延迟窗（与 TpRetrigger/PulseStretch 互引分工） | t0-std-wrapper 包装族补口 | C1 | 3 | 简单 |
| 15 | FB_DL_SensorSupplyWatch | Device | FB_DL_ | 传感器供电电压窗口监视（欠压/过压分级＋NE43 出口） | t2-6-rockwell-aoi 深化 | C2 | 3 | 简单 |
| 16 | FB_DL_ValveCycleCountBank | Device | FB_DL_ | 多阀动作计数寿命台账组（循环数累计＋维护阈值预警 Bank） | t2-2-lbp 阀诊断深化 | C2 | 3 | 简单 |
| 17 | FC_DL_TcToFilterCoeff | Algo | FC_DL_ | 时间常数→离散一阶滤波系数换算原子（α=Ts/(Ts+Tc)，防除零） | 自研-std（与 FB_DL_LowPassFilter 头注释互引分工：系数原子 vs 滤波本体） | C1 | 3 | 简单 |
| 18 | FC_DL_DeadtimeTapCalc | Algo | FC_DL_ | 死区时间→离散拍数向上取整换算（Smith 预估/死区补偿前置原子，整数进位点终审必查） | 自研-std（与 FB_DL_SmithPredictor 互引分工） | C2 | 3 | 简单 |
| 19 | FB_DL_HandAutoModeGateBank | Process | FB_DL_ | 手/自动模式权限门组（每回路双钥匙确认＋模式切换沿审计） | t2-7-packml 相语义深化 | C2 | 2 | 简单 |
| 20 | FB_DL_OperatorAckBank | Process | FB_DL_ | 操作员报警确认组（成组确认/逐条确认/未确认滞留清单） | t2-8-isa182 深化 | C2 | 2 | 简单 |

> 批次注：批 1 = 复杂件优先（防后段超时只出简单件）；批 2/3 = 简单件。复杂件 6 件若单轮超时（R362 判据），如实少报不顺延凑数。
> 候选到达替换规则：猎人队列到料后，同名件按「候选替换」占用预留 30% 名额，替换时重跑三查并回写本文件 §2 追加注记。

## 3 §2 P0 点修清单（VaporPressureSat 族缺 `bValid =>` 回执，8 处，R72 挂账）

> 现状核对方式：grep 实测行号＋当前调用写法原文摘录（非凭记忆）。属主件 `FC_DL_VaporPressureSat`（DL_Algo）出参契约 = `fPvSat` / `bClamped` / `eErr` / `bValid`，`FC_DL_AirSpecificVolume.st:172` 起的四全回执写法为修复参照样板。
> 修法统一口径：8 处调用补 `bValid => <局部变量>`；`bValid = FALSE` 拍按各件既有兜底路径走（不得静默用回执值），补接收变量声明，版本 +0.0.1，逐件机检复跑。

| # | 文件（真实路径） | 行号 | 当前调用写法（原文摘录） | 修法 |
|---|---|---|---|---|
| 1 | C:\Library\DL_Algo\FC_DL_HumidityRatioCalc.st | 129 | `IF NOT FC_DL_VaporPressureSat(fTempC := fTdEff, fPvSat => fPwsIn) THEN` | 补 `bValid => _bPwsValid`，声明区补局部变量；FALSE 拍走既有 16#0002_2E12 兜底分支 |
| 2 | C:\Library\DL_Algo\FC_DL_HumidityRatioCalc.st | 145 | `IF NOT FC_DL_VaporPressureSat(fTempC := fTempC, fPvSat => fPwsDb) THEN` | 同上口径（第二处） |
| 3 | C:\Library\DL_Algo\FC_DL_MixAirStateCalc.st | 157 | `IF NOT FC_DL_VaporPressureSat(fTempC := fMixTempC, fPvSat => fPwsMix) THEN` | 补 `bValid =>`；FALSE 拍走 16#0002_3110 兜底 |
| 4 | C:\Library\DL_Algo\FC_DL_RhFromDewPoint.st | 113 | `IF NOT FC_DL_VaporPressureSat(fTempC := fTEff, fPvSat => fPwsDb) THEN` | 补 `bValid =>`；FALSE 拍走 16#0002_3010＋bValid:=FALSE 既有出口 |
| 5 | C:\Library\DL_Algo\FC_DL_RhFromDewPoint.st | 119 | `IF NOT FC_DL_VaporPressureSat(fTempC := fDewPointC, fPvSat => fPwsTd) THEN` | 同上口径（第二处） |
| 6 | C:\Library\DL_MathData\FC_DL_DewPointToPpmV.st | 63 | `bSatOk := FC_DL_VaporPressureSat(fTempC := fDewPointC, fPvSat => fPsatPa, bClamped => bClamped);` | 已收 bClamped，补 `bValid =>`；FALSE 拍既有哨兵零出口不变 |
| 7 | C:\Library\DL_Process\FB_DL_NightPurgeCtrl.st | 113 | `bSatOutOk := FC_DL_VaporPressureSat(fTempC := LREAL_TO_REAL(fTOut), fPvSat => fPwsOut);` | 补 `bValid =>`；FALSE 拍 bSatOutOk 已含拒绝语义，补注释回执用途 |
| 8 | C:\Library\DL_Process\FB_DL_NightPurgeCtrl.st | 115 | `bSatInOk := FC_DL_VaporPressureSat(fTempC := LREAL_TO_REAL(fTIn), fPvSat => fPwsIn);` | 同上口径（第二处） |

> 边界注记：`FC_DL_AirSpecificVolume.st:172` 起为四全回执样板（fPvSat/bClamped/eErr/bValid 全收），不在修单内；扩展复核 ~20 处（DryerExhaustHumidityCtl / ChamberPurgeDry / WeightClassifySort 等）按 R333 口径本轮只挂账候审不改码。
> 点修与本轮 20 新件互斥：点修优先于新件开工（R192 差额占位纪律），点修完成后逐件机检复跑并在 BATTLE_REPORT 记 PASS 数。

## 4 §3 值守与流程项（不占编码配额）

- [ ] L2 真编译闸：本轮 20 件＋点修 5 件全部过闸（交付资格项）。
- [ ] 值守三项第 4 轮顺延：oss_harvest GITHUB_TOKEN 单仓试跑 / MatIEC CI 71 方言件裁决 / GATE MAJOR 存量人核。
- [ ] R333 纪律：终审缺陷只挂账不改码；收口三步主控直跑。

## 5 §4 下轮选题储备（≤10 条）

1. `FB_DL_AxisGantrySquareSeq`（Motion C4）：龙门双轴方找正序列——若与 GantrySkewMonitor/GearInPhaseAlign 分工可立，先查重。
2. `FC_DL_EnthalpyMixAirCalc`（MathData C2）：两股湿空气混合后焓——焓湿图族已收口，需先评估是否属族内补口而非凑数。
3. `FB_DL_AirCompressorLoadSeq`（Device C4）：多空压机加卸载轮换调度——与 AirCompDutyN2 语义边界先核。
4. `FB_DL_ChillerApproachWatch`（Device C2）：冷机趋近温差监视——与 HxApproach 语义合并评估后择一。
5. `FB_DL_PumpCavitationWatch`（Device C3）：泵汽蚀裕度（NPSHa/NPSHd）在线判据。
6. `FC_DL_LintDivCeilEx`（Base C1）：LINT 域安全整除＋向上取整原子（DINT 版 IntCeilDiv 之上位扩展，先查 TriangularSolve 族）。
7. `FB_DL_BatchPhaseSkipAudit`（Process C2）：ISA-88 相跳过审计——与 PackML 深化线合并评估。
8. `FC_DL_DateDayDiffCalc`（MathData C1）：两 DATE 天数差（roadmap-t02-calendar 池）。
9. `FB_DL_TankLevelUnevenAudit`（Process C2）：多罐液位不均衡审计（罐区族延续）。
10. 扩展复核 ~20 处多出参零回执调用点（R333 候审账）：下轮若挂账 ≥3 处同型则出专项回写。

*R73 规划线 ｜ 2026-11-23 ｜ 道莅工控代码库产品总监（规划阶段一，只写本计划文件）*
