# ROUND_PLAN_R28（阶段一+二：锁定 17 件 → 冲 500 里程碑）

## 0 盘点（2026-11-17 20:41 实测）
总库 **483/10,000**（v2.16.0；Base 74 / MathData 158 / Algo 52 / Device 88 / Motion 43 / Process 68）｜今日 **99/200**｜距 500 **差 17** → 本轮恰好 17 件，达成后回归常态（§7）。
WebSearch **0 次**（复用 ROADMAP 池 + 矩阵已收口组深化）｜ROADMAP **新增 0 条**（池内未重名可用 263 条）。

## 1 实测码位游标（grep + registry 双向核验）
| 库 | 段 | registry max | 源码 max | 起点 | 本轮区间 |
|---|---|---|---|---|---|
| DL_Base / DL_MathData | 0001_ | 0465 / 047A | 0465 / 047A | — | **0 件，不占 0001_** |
| DL_Algo | 0002_ | 3714 | 3714 | **3715** | 3715~3719 |
| DL_Device | 0003_ | 03A6 | 03A6 | **03A7** | 03A7~03BF |
| DL_Motion | 0004_ | 0326 | 0326 | **0327** | 0327~033F |
| DL_Process | 0005_ | 042F | 042F | **0430** | 0430~044D |

实测：源码 grep 与 registry 解析双向一致，区间连续无空洞，与历史撞车段（0201/0210）零交叠。**每件 5 槽**（末槽预留），`FC_` 同发 5 槽以避开机检分型改动期误报。

## 2 目标总表（17 行）
| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 码位（实测 5 槽） | 批次 |
|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_FanLawRootCalc | DL_Algo | FC | 风机相似定律三量换算（指数可组态） | roadmap-L661 / `iec-std-wrapper`(T0) | 3 | 16#0002_3715~3719 | 1 |
| 2 | FB_DL_StepperXyzGantry | DL_Motion | FB | 三轴步进开环龙门点位（逐轴确认+公差） | roadmap-L546 / T1-8 | 5 | 16#0004_0327~032B | 1 |
| 3 | FB_DL_StepperFeederBelt | DL_Motion | FB | 步进供料带间歇送料+色标补偿 | roadmap-L572 / T1-8 | 3 | 16#0004_032C~0330 | 1 |
| 4 | FB_DL_CheckweighZeroTrack | DL_Device | FB | 动态称重零点跟踪与温漂补偿 | roadmap-L719 / T1-1 | 3 | 16#0003_03A7~03AB | 1 |
| 5 | FB_DL_EfEmDoorInterlockPlus | DL_Device | FB | EFEM 门/阀/真空三域互斥与首因 | roadmap-L709 / T2-8 | 4 | 16#0003_03AC~03B0 | 1 |
| 6 | FB_DL_LaserTabWeldTrack | DL_Motion | FB | 极耳激光焊跟随误差与虚焊特征窗 | roadmap-L882 / T2-6 | 4 | 16#0004_0331~0335 | 2 |
| 7 | FB_DL_NotchAlignSeq | DL_Motion | FB | 晶圆缺口对位六相顺控（超时+限次重试） | roadmap-L823 / T1-6 | 4 | 16#0004_0336~033A | 2 |
| 8 | FB_DL_EdgeTrimTraverse | DL_Motion | FB | 修边刀架横动往复定位 | roadmap-L638 / T2-4 | 3 | 16#0004_033B~033F | 2 |
| 9 | FB_DL_NtcChannelHealth | DL_Device | FB | NTC 通道健康度 0~100 评分与预警 | roadmap-L691 / T1-2 | 3 | 16#0003_03B1~03B5 | 2 |
| 10 | FB_DL_WaferCassetteSlot | DL_Device | FB | 花篮 25 槽占用双向计数与满/空判据 | roadmap-L636 / T2-1 Counter | 2 | 16#0003_03B6~03BA | 3 |
| 11 | FB_DL_LamCtrlDualZone | DL_Device | FB | 层压机双腔真空协调与差压保护 | roadmap-L361 / T2-2 | 4 | 16#0003_03BB~03BF | 3 |
| 12 | FB_DL_LaminatorVacLeakTrend | DL_Process | FB | 真空泄漏率趋势诊断（速率 vs 基线） | roadmap-L700 / T2-1 Technology | 3 | 16#0005_0430~0434 | 3 |
| 13 | FB_DL_ChamberPumpDownProfile | DL_Process | FB | 抽气曲线三段包络监视与抽速早停 | roadmap-L708 / T2-1 Technology | 3 | 16#0005_0435~0439 | 3 |
| 14 | FB_DL_SealJawDwellTrim | DL_Process | FB | 热封刀驻留随线速自整定（限速微调） | roadmap-L716 / T2-7 | 4 | 16#0005_043A~043E | 4 |
| 15 | FB_DL_BatchDeviationAlarm | DL_Process | FB | 批次偏差四档分级+首出归因+升 P1 | roadmap-L734 / T2-8 | 3 | 16#0005_043F~0443 | 4 |
| 16 | FB_DL_InlineCheckweighGauge | DL_Process | FB | 在线称重动态窗判据与 σ 控制图 | roadmap-L379 / T2-1 Measurement | 3 | 16#0005_0444~0448 | 4 |
| 17 | FB_DL_ChillerStagingCurve | DL_Process | FB | 冷机加减机效率曲线选点 | roadmap-L385 / T1-2 | 4 | 16#0005_0449~044D | 4 |

**分类分布**：Motion **5**（43→48，最低库优先）｜Process **6**（68→74）｜Device **5**（88→93）｜Algo **1**（52→53，池内仅余 1 条 P1）｜Base/MathData **0**。理由：Base 池唯一候选 `FC_DL_ShlDwordEx` 被 ROADMAP 标「疑似同义」→ **不立**；MathData 158 件过配让位。**不注水**。
**T1/T2 配额**：T1-1(4)、T1-2(9,17)、T1-6(7)、T1-8(2,3)、T2-1(10,12,13,16)、T2-2(11)、T2-4(8)、T2-6(6)、T2-7(14)、T2-8(5,15) → **11 件带 T1/T2 源**。

## 3 组件规格（引脚级：方向 类型 含义·单位·域）

### 序 1 · FC_DL_FanLawRootCalc（DL_Algo/B1/3715~3719）
引脚：`bEnable` IN BOOL 使能，FALSE 冻结输出并保持 3715 ｜`fSpeedRef_rpm`/`fSpeedNow_rpm` IN REAL 参考转速 1~20000 rpm / 当前转速 0~30000 rpm ｜`fFlowRef_m3h`/`fPressRef_Pa`/`fPowerRef_kW` IN REAL 参考工况三量，均须 >0 ｜`fExpFlow`/`fExpPress`/`fExpPower` IN REAL 指数，默认 1/2/3，域 0.5~4.0 ｜`fRatioMax` IN REAL 转速比上限，默认 1.5（超速区失效）｜`fFlowOut_m3h`/`fPressOut_Pa`/`fPowerOut_kW` OUT REAL 换算三量 ｜`fSpeedRatio` OUT REAL 实际采用比值（已钳制）｜`eErr` OUT UDINT 错误码
边界：参考转速或任一参考量 ≤0 → 3716（防除零）；比值 >`fRatioMax` → 钳制 + 3717 信息级（不置 `bError`）；三输出非有限与 >1e12 溢出判 → 3718；`fExp*` 出域 → 钳制升 3716（组态错显式）
验收：1450 rpm/10000 m³h/800 Pa/15 kW → 现 1200 rpm（0.8276）→ 8276 m³h / 547.7 Pa / 8.50 kW + 3715；反向：参考转速改 0 → 3716 且三输出**保持上次有效值**（不是 0：0 会被上位当真实工况）

### 序 2 · FB_DL_StepperXyzGantry（DL_Motion/B1/0327~032B）
引脚：`bEnable` IN BOOL 使能，FALSE 立即中止 ｜`bStart` IN BOOL 上升沿启动一次 ｜`bReset` IN BOOL 仅 `eFault` 生效 ｜`fTargetX/Y/Z_mm` IN REAL 三轴目标 ±2000 mm ｜`fSpeed_mmS` IN REAL 1~500 mm/s ｜`fAccel_mmS2` IN REAL 10~5000 mm/s² ｜`fPosTol_mm` IN REAL 落点公差 0.001~1.0 mm ｜`tAxisMax` IN TIME 单轴到位超时 100ms~60s ｜`iAxisX/Y/Z` IN_OUT `I_DL_StepperOpenLoop` 三轴契约 ｜`fPosX/Y/Z_mm` OUT REAL 实到位 mm ｜`fErrMax_mm` OUT REAL 本次三类落点最大偏差 ｜`bDone/bBusy/bError` OUT BOOL 完成/运行/故障 ｜`eState` OUT `E_DL_GantryState` Idle/Jogging/Settling/Done/Fault(99) ｜`eErr` OUT UDINT
边界：三轴距离全零 → 直接 `eDone`（零位移指令在部分平台挂死）；目标超软限位 → 0329 **启动沿前预检拒绝**；速度/加速度/公差非法 → 0328；换轴前清上一轴 `bDone`（R27 跨轴标志教训）；单轴超时 → 032A + 中止后续轴（不再发新指令）
验收：X/Y 100 mm、Z 20 mm、50 mm/s → 依次推进、偏差 ≤0.01 mm、`bDone` 单拍；反向：Z 设 2500 mm（超限位）→ 0329 且**一轴都不动**

### 序 3 · FB_DL_StepperFeederBelt（DL_Motion/B1/032C~0330）
引脚：`bEnable` IN BOOL 使能 ｜`bIndexReq` IN BOOL 送料请求（上升沿受理，`bBusy` 期丢弃）｜`fPitch_mm` IN REAL 标称间距 1~2000 mm ｜`fMarkOffset_mm` IN REAL 色标偏差 ±20 mm，正=超前 ｜`fTrimGain` IN REAL 补偿增益 0~1（默认 0.5，>1 振荡）｜`fTrimAccumMax_mm` IN REAL 累计补偿上限 0.5~50 mm ｜`fSpeed_mmS`/`fAccel_mmS2` IN REAL 速度/加速度 ｜`tSettle` IN TIME 停稳确认 10~500 ms ｜`iAxis` IN_OUT `I_DL_StepperOpenLoop` ｜`fStepCmd_mm` OUT REAL 本次实际步距（含补偿）｜`fTrimAccum_mm` OUT REAL 累计补偿 ｜`bDone/bBusy/bError` OUT BOOL ｜`uIndexCnt` OUT UDINT 累计次数｜`eErr` OUT UDINT
边界：`fPitch_mm≤0` → 032E；补偿后步距 <0.5×Pitch 或 >1.5×Pitch → 钳制 + 032F 信息级（防倒料）；`fTrimGain` 出域 → 032E；`bBusy` 期内请求丢弃不排队（排队会让多次点动在几拍后突然连发）
验收：Pitch 100、偏差 +2、增益 0.5 → 步距 101、累计 +1、032C；反向：连续 60 拍偏差 +1 → 累计 30 超上限 20 → 0330 停送

### 序 4 · FB_DL_CheckweighZeroTrack（DL_Device/B1/03A7~03AB）
引脚：`bEnable` IN BOOL ｜`fWeightRaw_g` IN REAL 原始毛重 ±50000 g ｜`bBeltEmpty`/`bShockActive` IN BOOL 空载判据 / 冲击抑制窗｜`tStableWin` IN TIME 静载稳定窗 200ms~10s ｜`fTemp_C` IN REAL 传感器温度 -20~80 ℃ ｜`fTempRef_C` IN REAL 标定温度 ℃ ｜`fDriftCoef_gK` IN REAL 温漂系数 ±0.5 g/K ｜`fZeroDevMax_g` IN REAL 零点漂移限 0.1~50 g ｜`fZeroOut_g`/`fNetOut_g` OUT REAL 当前零点 / 去皮净重 g ｜`bInWindow` OUT BOOL 处于合法跟踪窗 ｜`uTrackCnt` OUT UDINT 零点更新次数｜`fDriftTotal_g` OUT REAL 相对标定累计漂移 ｜`bError`/`eErr` OUT
边界：`fTemp_C` 非有限 → 03A8 且**保持上次补偿值**（0 在冷库是合法值，会掩盖故障）；`fZeroDevMax_g≤0` → 03A8；窗口未满足绝不改零点；`|fDriftTotal_g|` 超限 → 03A9（继续跟踪会把误差吃掉）。滤波委托 `FB_DL_MedianFilter`
验收：空载 200.0 g 稳定 1s、温升 20→30 ℃、系数 0.02 g/K → 补偿 +0.2 g、净重归 0、`uTrackCnt`+1；反向：`bBeltEmpty=FALSE` 且放 500 g 砝码 30s → **零点不动**、净重 500 g

### 序 5 · FB_DL_EfEmDoorInterlockPlus（DL_Device/B1/03AC~03B0）
引脚：`bEnable` IN BOOL 使能，FALSE → `bRelease=FALSE`（失效即禁行）｜`uDoorStatusWord` IN WORD 门状态字（位段见头注释）｜`bValveClosed`/`bValveOpened` IN BOOL 阀关/开到位双反馈 ｜`fVacuum_kPa` IN REAL 腔体真空 0~101.3 kPa(abs) ｜`fVacuumOk_kPa` IN REAL 允许开门门限 kPa ｜`bWaferPresent` IN BOOL 腔内片在位（E84 语义）｜`bReset` IN BOOL 首因与锁存复位 ｜`bRelease` OUT BOOL 三域放行（唯一出口）｜`bDoorPermit` OUT BOOL 允许开门 ｜`uFirstCause` OUT UINT 1 门未关 2 阀位矛盾 3 真空不足 4 片在位 ｜`uBlockMask` OUT WORD 阻断域掩码（首因只报一个）｜`bError`/`eErr` OUT
边界：阀双反馈同时 TRUE 或同为 FALSE → 03AE（位置矛盾**先于**互斥判定，否则首因指错域）；真空非有限 → 按「真空不足」保守侧 + 03AF；`fVacuumOk_kPa≤0` → 03AE；首因仅未锁存时仲裁、同拍取编号最小（R11 首出三律）
验收：门关、阀开、真空 0.1 < 门限 5 → 禁行、首因 3；抽到 0.05 → 放行、首因清零；反向：阀双反馈全 FALSE → 03AE 且禁行

### 序 6 · FB_DL_LaserTabWeldTrack（DL_Motion/B2/0331~0335）
引脚：`bEnable`/`bWeldOn` IN BOOL 使能 / 出光中（仅窗内判据）｜`fPosCmd_mm`/`fPosAct_mm` IN REAL 指令/实际位置 mm ｜`fPower_W`/`fPowerRef_W` IN REAL 实测/设定功率 W ｜`fFollowErrMax_mm` IN REAL 跟随误差上限 0.01~2.0 mm ｜`fPowerDropPct` IN REAL 功率跌落阈 1~50 %（相对量）｜`fStallVel_mmS` IN REAL 停滞判据速度 0~5 mm/s ｜`tConfirm`/`tWindowMax` IN TIME 判据确认 20~500 ms / 单焊点窗口 50ms~10s ｜`bTrackOk` OUT BOOL 轨迹合格 ｜`fFollowErrPeak_mm` OUT REAL 窗内峰值 ｜`uDefectMask` OUT WORD bit0 跟超 bit1 功率跌 bit2 停滞 bit3 超时 ｜`fWeldPos_mm` OUT REAL 锁存焊点位置 ｜`eState` OUT `E_DL_WeldTrackState` Waiting/Welding/Judging/Pass/Reject/Fault(99) ｜`eErr` OUT UDINT
边界：`fFollowErrMax_mm≤0` 或 `fPowerRef_W≤0` → 0333；位置非有限 → 本拍跳过但**不清零**已累计峰值；三判据各需 `tConfirm` 连续满足；超 `tWindowMax` → bit3 + `eReject`（**不许无限期停在 eWelding**，R27 同类）
验收：指令 0→50 mm、滞后 0.3 > 上限 0.2 持续 30 ms → bit0 + `eReject` + 峰 0.3；反向：功率 2000→1500 W（跌 25% > 10%）持续 30 ms → bit1

### 序 7 · FB_DL_NotchAlignSeq（DL_Motion/B2/0336~033A）
引脚：`bEnable`/`bStart`/`bReset` IN BOOL 使能 / 上升沿启动 / 仅 `eFault` 退出 ｜`bNotchFound` IN BOOL 缺口检出（引脚注入）｜`fThetaNow_deg`/`fThetaTarget_deg` IN REAL 当前/目标转角 0~360 ° ｜`fTolDeg` IN REAL 复核公差 0.01~1.0 ° ｜`fSpinSpeed_dps` IN REAL 角速度 1~180 °/s ｜`tPhaseMax` IN TIME 单相超时 100ms~30s ｜`uRetryMax` IN UINT 0~2 ｜`iAxis` IN_OUT `I_DL_StepperOpenLoop` 旋转轴 ｜`bDone/bBusy/bError` OUT BOOL ｜`fThetaErr_deg` OUT REAL 最终偏差 ° ｜`uRetryCnt` OUT UINT ｜`eState` OUT `E_DL_NotchState` Idle/Searching/Latched/Trimming/Verifying/Done/Fault(99) ｜`eErr` OUT UDINT
边界：角度归一用**条件加减**（禁 `MOD`，负数取余三平台不一致，R11）；公差/速度 ≤0 或 `tPhaseMax`=0 → 0338；单相超时 → 0339 + `eFault`（不自动续相）；重试用尽 → 033A；`eDone` 须 `bStart` 重触发
验收：θ 10°、目标 95°、公差 0.2°、30°/s → 微调 +85°、复核 0.05° → `eDone`；反向：`bNotchFound` 恒 FALSE → 超时 0339 转 `eFault`（不空转）

### 序 8 · FB_DL_EdgeTrimTraverse（DL_Motion/B2/033B~033F）
引脚：`bEnable`/`bStart`/`bStop` IN BOOL 使能 / 启动 / 停止（段终点生效）｜`fPosMin_mm`/`fPosMax_mm` IN REAL 行程两端 ±1000 mm，须 `Max−Min≥5` ｜`fSpeed_mmS` IN REAL 0.5~200 mm/s ｜`fOverlap_mm` IN REAL 端点重叠 0~20 mm ｜`tDwell` IN TIME 端点驻留 0~5s ｜`iAxis` IN_OUT `I_DL_StepperOpenLoop` ｜`fPosOut_mm` OUT REAL 当前横动位置 ｜`bAtMin`/`bAtMax` OUT BOOL 端点到位 ｜`uTraverseCnt` OUT UDINT 累计单程数 ｜`eState` OUT `E_DL_TraverseState` Idle/RunMin/RunMax/Dwell/Stopped/Fault(99) ｜`eErr` OUT UDINT
边界：`fPosMax−fPosMin<5` → 033D（行程过窄使往复退化为抖动）；`fOverlap_mm` 出域钳制；目标一律经 `FB_DL_SoftLimitGuard` 预检再下发；`tDwell` 用 `TON` 无条件刷新；`bStop` 在**段终点**生效（半途硬切留刀痕）
验收：0~300 mm、100 mm/s、重叠 5 mm、驻留 200 ms → 单程 3s、重叠 5 mm、计数 +1；反向：行程改 0~3 mm → 033D

### 序 9 · FB_DL_NtcChannelHealth（DL_Device/B2/03B1~03B5）
引脚：`bEnable` IN BOOL ｜`fTemp_C` IN REAL 该通道温度 ℃ ｜`uChFaultMask` IN WORD 上游通道故障掩码 ｜`fDriftTotal_C` IN REAL 长期漂移 ℃（对投运基线）｜`fNoise_C` IN REAL 窗口噪声（标准差）℃ ｜`fDriftLimit_C` IN REAL 扣尽阈 0.5~20 ℃ ｜`fNoiseLimit_C` IN REAL 0.05~5 ℃ ｜`uFaultWeight`/`uDriftWeight`/`uNoiseWeight` IN UINT 0~100，和须为 100 ｜`tEvalPeriod` IN TIME 评分周期 1~60s ｜`uHealth` OUT UINT 0~100 ｜`eGrade` OUT `E_DL_HealthGrade` Good≥80 / Watch 60~79 / Warn 40~59 / Bad<40 ｜`bReplaceReq` OUT BOOL 更换建议（Bad 或断线累计 3 次）｜`bError`/`eErr` OUT
边界：三权重和 ≠100 → 03B3 并**回退默认 40/40/20**（不停摆但必须报错）；温度非有限 → 本周期不计分（记 0 分会把健康通道判死）；两个 Limit ≤0 → 03B3 防除零；整数分档禁浮点等判
验收：无故障、漂移 0.2/2.0、噪声 0.01/0.5、权重 40/40/20 → 100 Good；反向：断线位置位且漂移 5 ℃ → ≤60 且 `bReplaceReq=TRUE`

### 序 10 · FB_DL_WaferCassetteSlot（DL_Device/B3/03B6~03BA）
引脚：`bEnable` IN BOOL 使能，FALSE 锁存位图 ｜`bLoadPulse`/`bUnloadPulse` IN BOOL 进片 +1 / 出片 −1（上升沿）｜`bClear` IN BOOL 清空（换花篮，须 `bEnable=FALSE`）｜`uSlotCount` IN UINT 槽数 1~25（>25 钳制 + 03B8 信息级）｜`uOccupied`/`uEmptySlot` OUT UINT 占用 / 空槽数 ｜`bFull`/`bEmpty` OUT BOOL 满/空判据 ｜`uSlotMask` OUT WORD 占用位图（bit0=第 1 槽 … bit24=第 25 槽）｜`bCounterMismatch` OUT BOOL 计数矛盾已锁存 ｜`eErr` OUT UDINT
边界：同拍进出双沿 → 03B9 且双丢弃（物理不可能，必是抖动或逻辑错）；占用 0 时出片 → 锁 `bCounterMismatch` + 03BA，**不借位到 25**（借位把满篮误判为空篮，安全侧反）；满篮进片 → 03B9；写位图前判槽号 ≤ `uSlotCount`
验收：25 槽进满 → `bFull`、占用 25、位图 `16#01FF_FFFF`；再出 1 → 24 且 `bFull=FALSE`；反向：空篮出片 → `bCounterMismatch`、占用保持 0、03BA

### 序 11 · FB_DL_LamCtrlDualZone（DL_Device/B3/03BB~03BF）
引脚：`bEnable`/`bStartSeq` IN BOOL 使能 / 上升沿启动 ｜`fVacUpper_kPa`/`fVacLower_kPa` IN REAL 上/下腔真空 0~101.3 kPa(abs) ｜`fVacTarget_kPa` IN REAL 目标真空 0.1~101 ｜`fAmbient_kPa` IN REAL 当地大气压（组态合理性判据）｜`fDpMax_kPa` IN REAL 差压上限 0.5~20 ｜`fSpeedUpper`/`fSpeedLower` IN REAL 双泵抽速给定 %（注入）｜`tSegMax` IN TIME 各段超时 1s~600s ｜`bVacOk` OUT BOOL 双腔达标（**双侧**都达标）｜`fDp_kPa` OUT REAL 实时差压（上减下）｜`uSeg` OUT UINT 1 粗抽 2 平衡 3 精抽 4 保压 ｜`fSpeedUpCmd`/`fSpeedLowCmd` OUT REAL 双泵指令 % ｜`bDpGuardActive` OUT BOOL 差压保护介入 ｜`eErr` OUT UDINT
边界：`fDpMax_kPa≤0` → 03BC；越限**只降抽得快的一侧**（双侧同降使时长翻倍且不解决差压）；`fVacTarget_kPa ≥ fAmbient_kPa` → 03BD；段超时 → 03BE 且保持当前抽速（**不归零**，归零即放弃已有真空度）；单侧非有限 → 该侧按 0 + 03BF，双侧 → 停车
验收：目标 0.5、差压上限 3；上腔 5 / 下腔 12 → 差压 7 越限 → `bDpGuardActive` 且降上泵；双腔 0.5 → `bVacOk`；反向：目标设 105 → 03BD

### 序 12 · FB_DL_LaminatorVacLeakTrend（DL_Process/B3/0430~0434）
引脚：`bEnable`/`bHoldPhase` IN BOOL 使能 / 保压段有效（仅此段计速率）｜`fVac_kPa` IN REAL 腔体真空 kPa(abs) ｜`tSampleTime` IN TIME 10~1000 ms ｜`fLeakRateMax_kPamin` IN REAL 绝对上限 0.001~10 kPa/min ｜`fBaseK` IN REAL 基线倍率 1.1~5.0 ｜`uBaseSamples` IN UINT 基线样本数 3~20 ｜`fLeakRate_kPamin`/`fLeakBase_kPamin` OUT REAL 当前速率 / 基线 ｜`bLeakWarn`/`bLeakAlarm` OUT BOOL 越基线 / 越绝对上限 ｜`bError`/`eErr` OUT
边界：`fLeakRateMax_kPamin≤0` 或 `uBaseSamples<3` → 0432；**真空上升（负泄漏）不刷新基线**（放气抬高基线后真泄漏永不报警）；基线需满 `uBaseSamples` 样本，不足时 `bLeakAlarm` 恒 FALSE（不给未标定报警）；速率非有限 → 跳过 + 0434
验收：1.0→1.05 kPa/60s = 0.05、上限 0.1 → 不报；反向：1.0→1.5 = 0.5 > 0.1 → `bLeakAlarm`；基线 0.02、当前 0.06（3×）→ `bLeakWarn`

### 序 13 · FB_DL_ChamberPumpDownProfile（DL_Process/B3/0435~0439）
引脚：`bEnable`/`bPumpOn` IN BOOL 使能 / 泵运行中 ｜`fPress_kPa` IN REAL 腔体压强 kPa(abs) ｜`fSeg1End_kPa`/`fSeg2End_kPa` IN REAL 段界压强，须 `Seg1End > Seg2End` ｜`fSlopeMin_kPas` IN REAL 各段最小抽速 0.001~10 kPa/s ｜`tSampleTime`/`tSegMax` IN TIME 采样 10~1000 ms / 单段超时 1s~1800s ｜`fSeg1Slope_kPas`/`fSeg2Slope_kPas` OUT REAL 实测斜率 ｜`uSeg` OUT UINT 0 待机 1 粗抽 2 过渡 3 精抽 4 完成 9 故障 ｜`bSlowWarn`/`bProfileOk` OUT BOOL 低于包络（早停建议）/ 全程合格 ｜`eErr` OUT UDINT
边界：段界反置 → 0437（反置使段永远进不去）；`fSlopeMin_kPas≤0` → 0437；压强非有限 → `uSeg=9` + 0439（不可读不许推进段）；段超时 → 0438 + `bSlowWarn`（**只建议早停，不切泵**）；斜率前拦 `tSampleTime=0`
验收：101→10 kPa/30s（3.03）+ 10→1 kPa/45s（0.2）、最小 0.1 → 合格；反向：拖到 200s（0.045）→ `bSlowWarn` 且不置故障

### 序 14 · FB_DL_SealJawDwellTrim（DL_Process/B4/043A~043E）
引脚：`bEnable`/`bRunning` IN BOOL 使能 / 线运行（停机冻结自整定）｜`fLineSpeed_mpm` IN REAL 0~200 m/min ｜`fDwellNominal_ms` IN REAL 标称驻留 50~2000 ms ｜`fDwellMin_ms`/`fDwellMax_ms` IN REAL 上下限（须 Min<Max）｜`fSealQuality` IN REAL 封口质量 0~1（注入）｜`fQualityTarget` IN REAL 目标 0.7~0.99 ｜`fTrimGain` IN REAL 微调增益 0~50 ms/单位误差 ｜`fDwellRateMax_msS` IN REAL 变化率上限 1~200 ms/s ｜`fDwellOut_ms`/`fDwellTrim_ms` OUT REAL 驻留给定 / 微调分量 ｜`bAtLimit` OUT BOOL 到上下限 ｜`uTrimCnt` OUT UDINT 微调生效次数 ｜`eErr` OUT UDINT
边界：`fDwellMin_ms ≥ fDwellMax_ms` → 043C；`fQualityTarget` 出域 → 043C；质量非有限 → **冻结微调**（保持上次 + 043E，不把 NaN 积分进给定）；**先限速后钳制**（反序会让爬升带出限）；停机期不计次
验收：标称 300、线速 0→60 m/min、质量 0.85→目标 0.9 → 微调 +10、给定 310、斜率 ≤50 ms/s；反向：`Min` 设 400 > `Max` 300 → 043C

### 序 15 · FB_DL_BatchDeviationAlarm（DL_Process/B4/043F~0443）
引脚：`bEnable` IN BOOL ｜`fValue` IN REAL 批内实测值（单位由调用方定，头注释写清）｜`fTarget` IN REAL 批次目标 ｜`fTolL`/`fTolH` IN REAL 低/高容忍带宽 ｜`fTolLL`/`fTolHH` IN REAL 低低/高高带宽，须 `LL>L`、`HH>H` ｜`uSourceId` IN UINT 来源编号（多源汇总首出定位）｜`bAck` IN BOOL 确认（只清已确认，不清活跃）｜`eLevel` OUT `E_DL_DevLevel` Ok/L/LL/H/HH ｜`bActive`/`bAcked` OUT BOOL 活跃 / 已确认（正交，可同为 TRUE）｜`uFirstSource` OUT UINT 首出来源 ｜`bEscalateP1` OUT BOOL 超档升 P1 ｜`uDevCount` OUT UDINT 累计越带次数｜`eErr` OUT UDINT
边界：带序反置（`LL≤L` 或 `HH≤H`）→ 0441（反置使四档永远同档）；`fTarget` 非有限 → 0442，`eLevel=Ok`、`bActive` **保持上一拍**（不因目标丢值撤销活跃报警）；回 Ok 时两标志**同拍**清零（否则 HMI 留幽灵报警）
验收：目标 100、L/H=2、LL/HH=5；实测 106 → `eLevel=HH`+`bEscalateP1`；`bAck` 后 `bAcked=TRUE` 而 `bActive` 仍 TRUE；回 100 → 两标志同拍清零

### 序 16 · FB_DL_InlineCheckweighGauge（DL_Process/B4/0444~0448）
引脚：`bEnable`/`bSampleValid` IN BOOL 使能 / 本拍有有效样本 ｜`fWeight_g` IN REAL 0~50000 g ｜`fTarget_g` IN REAL 目标重量 g ｜`fTolUp_g`/`fTolLow_g` IN REAL 上下公差带 g，须 >0 ｜`uWinSamples` IN UINT 统计窗 5~50 ｜`fSigmaLimit_g` IN REAL σ 控制限 0.1~20 g ｜`bOutlierReject` IN BOOL ±3σ 冲击剔除开关 ｜`fMeanOut_g`/`fSigmaOut_g` OUT REAL 窗口均值 / 标准差 ｜`bUnder`/`bOver` OUT BOOL 欠重/超重（**逐件**，不平顺）｜`bSpcAlarm` OUT BOOL σ 越控制限（满窗后才判）｜`uRejectCnt`/`uSpcCnt` OUT UDINT 剔除件数 / SPC 越限次数 ｜`eErr` OUT UDINT
边界：公差 ≤0 或 `uWinSamples<5` 或 `fSigmaLimit_g≤0` → 0446；样本非有限 → 丢弃 + 0448 信息级（计入丢弃数）；**逐件判定不平顺**（平滑会漏单件超重）；**σ 仅满窗判**；分母 `n−1` 且 `n≥5` 前置保证防除零
验收：目标 500、公差 ±5；10 件 500±1 → 均值 500、σ≈0.7 无报警；一件 508 → `bOver=TRUE`、`uRejectCnt=1`、均值仍≈500；反向：σ 升至 6 > 2 → `bSpcAlarm`

### 序 17 · FB_DL_ChillerStagingCurve（DL_Process/B4/0449~044D）
引脚：`bEnable` IN BOOL ｜`fLoadPct` IN REAL 系统负荷率 0~120 % ｜`afCopCurve` IN `ARRAY[1..11] OF REAL` 单机 COP 曲线（10/20/…/100% 十一点）｜`afCapCurve` IN `ARRAY[1..11] OF REAL` 单机容量曲线 kW ｜`uUnitCnt` IN UINT 在线台数 1~8 ｜`fLoadStepPct` IN REAL 加/减机死区 1~20 %（防抖）｜`tConfirm` IN TIME 建议持续确认 10s~10min ｜`uStage` OUT UINT 建议运行台数 1~8 ｜`bAddReq`/`bDelReq` OUT BOOL 加/减机请求（单拍脉冲，顺控受理）｜`fCopNow` OUT REAL 当前负荷率推算 COP ｜`fBestLoadPct` OUT REAL 本台数最经济负荷率 % ｜`bOnCurve` OUT BOOL 曲线单调性校验通过 ｜`eErr` OUT UDINT
边界：曲线非单调（COP 随负荷率不增）→ 044B 且**不给建议**（错曲线的建议比不给更危险）；`uUnitCnt=0` → 044C 防除零；`fLoadPct` 非有限 → 044D 保持上次 `uStage`；投切须持续 `tConfirm`；减机**下限钳 1 台**（减到 0 属停机）
验收：负荷 55%、3 台在线、峰值 80% → 单机 18.3% 过轻 → `bDelReq`、`uStage=2`；反向：曲线改为非单调 → 044B 且两请求均 FALSE

## 4 派单样板

### 4.1 文件头注释样板（FB；FC 改 `FUNCTION ... : BOOL`）
```iecst
(*==============================================================================
 * 组件名称 (Component)  : FB_DL_<Name>
 * 所属子库 (Sublibrary) : DL_<Category>
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : <一句话功能 + 关键判据 + 明确不做的事>
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 *                         （T0 件写：IEC 61131-3 标准语义的道莅防御性实现）
 * 本文件内含 (Contains) : TYPE E_DL_<Name>State / E_DL_<Name>Err / FUNCTION_BLOCK FB_DL_<Name>
 * 依赖 (Depends)        : DL_<Lib>/<被复用件>（只调用，不复制其内核）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         <本件防除零/钳位/非有限三条> ｜ 枚举显式赋值 ｜ TON 无条件调用 ｜ CASE 有 ELSE
 * 错误码表 (Codes)      : 16#000X_XXXX 就绪/成功
 *                         16#000X_XXXX 故障级 <原因>（反证句：<现场怎么反证>）
 *                         16#000X_XXXX 信息级 <已钳制/跳过，bError 保持 FALSE> ｜ 末槽预留
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 <n>
 * 验收向量 (Acceptance) : 正向 <输入 → 码 + 输出> ；反向 <异常输入 → 码 + 保守侧动作>
 *============================================================================*)
```
**注**：头注释严禁出现被禁记号的字面原文（全局变量块名 / 外部变量关键字 / 物理地址百分号前缀），统一写「外部全局变量」「硬件地址直引」。

### 4.2 错误码声明样板（固定 5 槽，末槽预留）
```iecst
(*-----------------------------------------------------------------------------
 * 枚举: E_DL_<Name>Err（与 FB_DL_<Name> 同文件，码位 16#000X_XXXX 起 5 槽）
 *----------------------------------------------------------------------------*)
TYPE E_DL_<Name>Err :
(
    eReady     := 16#000X_XXXX,   // 就绪/成功 / Ready or success
    eConfigBad := 16#000X_XXXX,   // 故障级：组态非法（阈值/量程/序反置）/ Fault: bad configuration
    eInputBad  := 16#000X_XXXX,   // 故障级：输入非有限或物理不可实现 / Fault: non-finite input
    eInfoClamp := 16#000X_XXXX,   // 信息级：越界已钳制（不置 bError）/ Info: clamped
    eReserved  := 16#000X_XXXX    // 预留：本版不发码 / Reserved
);
END_TYPE
```
等价写法：改用 `eErr : UDINT` 引脚时 5 槽码值仍逐条写入码表，**两法不得同件混用**。铁律：`bError=TRUE` 每拍 `eErr` 必须在码表找到对应码（R45）。

### 4.3 双语注释样板
```iecst
VAR_INPUT
    fPress_kPa : REAL := 101.3;      // 腔体压强 kPa(abs)，域 0~101.3 / Chamber pressure, kPa abs
    tConfirm   : TIME := T#100MS;    // 判据持续确认时长 ms / Debounce time for the criterion
END_VAR
```
规则：每行声明必须有 `//` 同行注释，中文在前 `/ 英文` 在后；物理量一律带单位（ms/s/mm/kPa/rpm/%/g/°C/kW）。

### 4.4 TYPE 块语法铁律
- ENUM：`TYPE E_DL_X : ( eA := 0, eB := 10, eFault := 99 ); END_TYPE`
- **STRUCT 必须无括号**：
```iecst
TYPE ST_DL_<Name> :
STRUCT
    fPos_mm : REAL;  // 位置 mm / Position in mm
    bValid  : BOOL;  // 有效标志 / Valid flag
END_STRUCT
END_TYPE
```
- 禁止 `TYPE ST_DL_X : ( ... )`；`CASE` 每个枚举成员都要标签，`ELSE` 兜底不得为空。

## 5 批次派单表（批内：Level 1 先于 Level 2，单轴用法先于多轴组合）
- **B1（5）**：3 StepperFeederBelt → 2 StepperXyzGantry → 1 FanLawRootCalc → 4 CheckweighZeroTrack → 5 EfEmDoorInterlockPlus（先单轴再多轴组合）
- **B2（4）**：8 EdgeTrimTraverse → 6 LaserTabWeldTrack → 7 NotchAlignSeq → 9 NtcChannelHealth（序 7 是唯一完整顺控超时件，留最后单独验）
- **B3（4）**：10 WaferCassetteSlot → 11 LamCtrlDualZone → 12 LaminatorVacLeakTrend → 13 ChamberPumpDownProfile（Process 两件消费真空语义，与序 11 同批交叉验口径）
- **B4（4）**：14 SealJawDwellTrim → 15 BatchDeviationAlarm → 16 InlineCheckweighGauge → 17 ChillerStagingCurve（序 16 与 B1 序 4 同属称重族，跨批复核口径）

每批必做：写码 → `check_r28.py` 机检（POU 名=文件名 / END_* 配对 / TYPE 块种类 / 枚举⊆CASE / 5 槽码位 / 跨库撞车）→ 向量复算 → 兜底三问。

## 6 验收向量纪律 + R27 交接隔离
R27 缺陷同属「正常向量全绿、异常路径泄漏」→ **每条向量成对**：① 正向；② 反向（方向反转 / 阈值逐拍跳 / 域端点 0·负·NaN·上限+1 → 拒绝或保守侧动作）。只写正向者打回。
机检三规则（枚举⊆CASE / 安全侧取值不在判定集合 / POU 分型槽数）与六库 VERSION·MANUAL 补录债（R138）→ **终审处理，本规划不碰**。本批与「R128 挂账：6 件 eFault 缺标签」名单**零交集**（`ParticleCounterStat`/`CoolingTowerApproachCalc`/`InverterGridSync`/`HeatPumpDefrost`/`DuctStat*` 均存量件）；四个状态机件（2/6/7/8）一律 `eFault:=99` + 显式标签 + `ELSE` 兜底。

## 7 500 里程碑后节奏声明
① 停止按件数冲刺，改按「债务清偿率」考核（编译债 23 轮 / 手册 3 本 / 机检 3 条）；② 每轮上限回到 **6~8 件**，≥30% 预算给存量修订；③ 新增「族完整性审计」季度项，优先补 Motion（48 最低）与 Algo（53）。

## 8 预算与风险
规划 ≤15 min，其余预算给执行/终审/收口。风险一：4 批并行 → 若 B3/B4 超时允许「B4 减 1 件」，**不得**用低价值件顶上（差 1 件如实报 499）。风险二：三段区间属撞车高发区（R18 修 7 组）→ **每件落盘后立即回写 registry 再写下一件**，禁批末批量写。
