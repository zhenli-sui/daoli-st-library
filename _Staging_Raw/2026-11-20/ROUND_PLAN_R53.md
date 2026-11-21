# ROUND_PLAN_R53 — R53 轮规划（无人值守，2026-11-20）

- 轮次：R53 ｜ 性质：规划轮（只写本文件，零编码 / 零 registry / 零 README）
- 预算：本轮新增组件下调至 16 件（R193 扩面占用产能）；T0 = 0 件（八组余量 0，严禁硬凑 T0 防御包装）
- 品类配额上限：DL_Process ≤ 4 / DL_MathData ≤ 3 / DL_Base ≤ 4 / DL_Algo ≤ 5 / DL_Device ≤ 3 / DL_Motion ≤ 3
- 来源纪律：零 WebSearch（0/3）；源全部复用 SOURCE_HUNTING_MATRIX 既有 ◐ 行 + ROADMAP 未勾真缺口 + RAW_NOTES（R39~R52），零新建源组

## 一、16 件新组件目标

撞名反证：**16 名均未出现在 INDEX_REGISTRY components（945 名，_names_r53.txt 逐一 grep 反证）与 ROADMAP 条目主件名中**（ElectrodeGapMark / SteamTrapSurvey / HumidifierAdiabat / ChillerYearWinStart / FormationChannelQueue / PalletLabelVerify 等 18 条 ROADMAP 主件经查已在 registry，全部排除出本批选题，见第四节三向差额清单）。

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度(1-6) | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_ValveCycleLifeCounter | DL_Device | FB_DL_ | 阀门动作循环寿命计数（行程+扭角双源去抖）与保养阈值预警 | T2-8 ISA-18.2 ◐ | 2 | 1 |
| 2 | FB_DL_BearingVibTrend | DL_Algo | FB_DL_ | 轴承振动 RMS 滑窗趋势分级预警（ISO 10816 三档） | T2-1 LGF Measurement ◐ | 3 | 1 |
| 3 | FC_DL_WetBulbCalc | DL_MathData | FC_DL_ | 干球温/湿度的湿球温度迭代估算（焓湿图原子补口） | T1-2 OSCAT Building ◐ | 3 | 1 |
| 4 | FB_DL_SignalStuckWatch | DL_Base | FB_DL_ | 信号卡死监视：值超窗时长不变/变化率恒零则报警 | T2-1 LGF ◐ | 2 | 1 |
| 5 | FB_DL_ConveyorSlipWatch | DL_Device | FB_DL_ | 输送带打滑检测（带速/驱动辊速差 + 电流负载判据） | T2-2 LBP ◐ | 3 | 2 |
| 6 | FB_DL_CaseShiftTally | DL_Process | FB_DL_ | 班次箱数台账与计划差异告警（复用 BidirectionalCounter + OeeCalculator 口径） | ROADMAP P2 | 2 | 2 |
| 7 | FC_DL_HaversineDistance | DL_MathData | FC_DL_ | 球面两点大圆距离（AGV/巡检定位换算，双精度） | T2-1 LGF Math ◐/自研 | 2 | 2 |
| 8 | FB_DL_PumpSurgeGuard | DL_Algo | FB_DL_ | 泵喘振区逼近保护：工况点距喘振线裕度判据 + 自动降载 | T1-1 OSCAT Basic ◐/自研 | 4 | 2 |
| 9 | FB_DL_GreaseLubeTimer | DL_Device | FB_DL_ | 加脂保养窗：运行小时与循环数双触发，先到先报 | T2-8 ◐/自研 | 2 | 3 |
| 10 | FB_DL_PulseTrainDecoder | DL_Base | FB_DL_ | 脉冲串解码：脉冲计数 + 间隔宽窄判别输出编码（编码旋钮/拨码开关） | T2-1 LGF Bit Logic ◐ | 3 | 3 |
| 11 | FC_DL_PeriodJitterCalc | DL_MathData | FC_DL_ | 周期序列抖动统计（max-min/均值/标准差，双精度数组） | T2-1 LGF Math ◐ | 2 | 3 |
| 12 | FB_DL_SensorDriftBaseline | DL_Algo | FB_DL_ | 传感器慢漂移基线跟踪（长窗指数基线）与快偏差越限报警 | T2-1 Measurement ◐ | 3 | 3 |
| 13 | FB_DL_FilterWeekWindow | DL_Process | FB_DL_ | 过滤器周维护窗与压差累计（复用 WeekOfYearCalc + RuntimeMeter） | ROADMAP P2 | 3 | 4 |
| 14 | FB_DL_LabelWeekCode | DL_Process | FB_DL_ | 标签周码/批码打印窗（复用 WeekOfYearCalc + DateCoderSync） | ROADMAP P2 | 2 | 4 |
| 15 | FB_DL_AxisBacklashComp | DL_Motion | FB_DL_ | 轴反向间隙补偿：方向切换拍注入补偿行程（PLCopen 映射层） | T1-6 PLCopen Motion ◐ | 3 | 4 |
| 16 | FB_DL_BathTempHoldCtrl | DL_Process | FB_DL_ | 浸洗槽液温保温与液位-加热联锁（低液位禁加热，复用 I_DL_TemperatureZone） | 自研/行业池 | 3 | 4 |

四批品类分布：批1 = Device1/Algo1/MathData1/Base1；批2 = Device1/Process1/MathData1/Algo1；批3 = Device1/Base1/MathData1/Algo1；批4 = Process3/Motion1。
配额核对：Process 4≤4 ✓ / MathData 3≤3 ✓ / Base 2≤4 ✓ / Algo 3≤5 ✓ / Device 3≤3 ✓ / Motion 1≤3 ✓，合计 16。

## P0 返修规格（4 件）

依据 REVIEW_R52.md（1-5 节行号全部采信），版本一律 v1.0.1，破坏行为仅收敛不外扩。

### P0-1 DL_Motion/FB_DL_AxisHomeRepeatVerify（中，R52-02/R52-03）
- 主症：`97-98` 段 1 每拍无条件 `bPass := FALSE; bReject := FALSE;`，置位仅在 `166/168`（eCollect 结算拍），`171` 迁入 eDone 后下拍起双 FALSE，与 `173` 注释「完成相：保持判定」及 `44-45` 声明相悖（R191 名实不符 + 判定保持族②）。
- 修法（行级）：① 删除 `97-98` 两行段 1 无条件预清；② 在 eCollect 分支结算行（`166` 前）加 `bPass := FALSE; bReject := FALSE;`（结算拍前预清，确保当拍二选一赋值）；③ 修 2.2 轻项：`122` eIdle 分支补 `nGot := 0;`（出口与内部 `_nGot` 同步）。
- 自检要点：eDone 相 `bPass XOR bReject` 恒成立（上电到复位全程）；复位/失能路径两出口均清；R_TRIG 两实例仍在段 0 无条件刷新（`83-84` 不动）。

### P0-2 DL_Algo/FB_DL_PidParamDriftAudit（轻，R52-05/R52-06）
- 主症：`83-84` 六处 `x = x` 自反闸只拦 NaN 不拦 Inf；`fTi=Inf, fTiRef=Inf` 时 `ABS(Inf-Inf)=NaN` → `NaN > 阈值` = FALSE，越差判据静默漏报（非安全侧窄口）。
- 修法（行级）：① `83` 起六条判据各补差判 `AND ((fX - fX) = (fX - fX))`（与 FB_DL_AxisHomeRepeatVerify:85 范式统一，六变量逐一套用）；② 3.2 自洽：`92` `bDriftAny` 预清改为「由 bDriftKp/Ti/Td 三位 OR 重算」而非独立清零（同源自洽）；③ `71/85` `_fHun` 由可变 VAR 迁入 `VAR CONSTANT c_fHun : LREAL := 100.0;`（无魔法数收口）。
- 自检要点：注入 Inf/Inf、Inf/有限、NaN 三类向量，`_bExTi/_bExTd/_bExKp` 全部安全侧报警；`fTolAbs=0` 且基准远离零时不锁存（3.2 可用性项若本轮不修须在头注释声明遗留）。

### P0-3 DL_Device/FB_DL_HeatTraceCircuitMon（中，R52-07）
- 主症：`83` `tonObs(IN := NOT tonObs.Q, PT := tObserve)` 与 `84` `tonNoCur(IN := bHeatCmd AND NOT _bCur, PT := DL_HTC_CONF)` 段 0 全相位运行（eIdle/eFault 亦计时）→ 使能当拍即 `tonNoCur.Q=TRUE` 锁存 bOpenCirc（确认延时被绕过）；tonObs 自由跑致首窗 1~2 拍即结算 bNoRise 误报。
- 修法（行级）：① `83` 改 `tonObs(IN := (_eState = E_DL_HtcState.eMon) AND NOT tonObs.Q, PT := tObserve);`；② `84` 改 `tonNoCur(IN := (_eState = E_DL_HtcState.eMon) AND bHeatCmd AND NOT _bCur, PT := DL_HTC_CONF);`（上拍相位闸，1 拍延迟可接受）；③ eIdle→eMon 迁入拍（`114-165` CASE 的 eMon 分支入口或迁入沿处）补 `_fTempT0 := fTemp; _bT0Ok := TRUE;`。保持 `82-84` 段 0 无 IF 包裹形式不变。
- 自检要点：eIdle 期给 bHeatCmd+零电流 10s → 使能后不立即锁存 bOpenCirc（先经 CONF 延时）；退出 eMon 当拍 tonObs/tonNoCur 断输入归零；`4.2` 传感器 NaN 单列 eSensorBad 仅评估不入本轮（不扩 scope）。

### P0-4 DL_Device/FB_DL_BrakeResistorThermal（中，R52-09/R52-10）
- 主症：`141` `_fRiseEst := fRiseRated * (_fAccKj / fEnergyMax);` 把「满载稳态温升」当能量占额线性斜率，与 `127` 一阶冷却模型量纲不自洽；默认域（fRatedCurrent=20A, fResistance=50Ω, fTauCool=300s, fEnergyMax=20kJ）下额定电流即 100% 饱和误报过载，fDeratePct 恒 0。
- 修法（行级）：① `141` 改热阻口径：`_fRiseEst := fRiseRated * (_fPowerW / (fRatedCurrent * fRatedCurrent * fResistance));`（稳态功率比 × 满载温升；`_fPowerW` 为 `127` 已有的 I²R 瞬时功率，若无则以 `fCurrent*fCurrent*fResistance` 就地计算并中文注释单位 W）；② 组态闸（`79-83` 除子集）追加一致性校验：`fEnergyMax > fRatedCurrent*fRatedCurrent*fResistance*fTauCool/1000.0` 时进 eFault 并在头注释注明「能量额度应 ≈ I²R·τ 派生量」（kJ 口径）；③ 5.2 轻项：`134-139` `_fPct` 饱和 100 处同步回夹 `_fAccJ := fEnergyMax*1000.0`（能量上界）；eIdle 分支（`114-120`）补 `fEnergyPct/fDeratePct` 镜像，并让 eIdle 期 `_fAccJ` 按 `dT/dt = -T/tauCool` 衰减（停机即冷却，物理一致）。
- 自检要点：默认参数 + 额定 20A 稳态 → `fTempRise` ≈ fRiseRated、`bOverload` = FALSE、fDeratePct ≈ 0；1.5 倍额定 → 温升按功率比 2.25 倍爬升、告警方向正确；`fTauCool=0` 等除子组态闸仍首拍拦截。

## R193 四族扩面（R53 检查项）——只排查不修改

### 族① 环窗初值/回钳（`_nHead` 声明无初值 + 窗深变更回钳）
| 文件 | 命中行 | 判断 |
|---|---|---|
| DL_Algo/FB_DL_ControlOutputSlewWatch.st | 61（`: INT;` 无初值）/152/161-165 | **需修**（R52-01 已挂账，本轮 P0 收口件外首个） |
| DL_Algo/FB_DL_LoopCoupleDetect.st | 93（无初值）但 139 复位 `:= 1`、177 回卷 | 疑似（需证「复位先于首写」路径成立，成立则无需修） |
| DL_Algo/FB_DL_LoopSignGuard.st | 87（无初值）但 134 复位 `:= 1`、172 回卷 | 疑似（同上） |
| DL_Algo/FB_DL_RulEstimator.st | 107（无初值）但 173 复位 `:= 1`、213 回卷 | 疑似（同上） |
| DL_Device/FB_DL_ValveSeatLeakWatch.st | 89（无初值）但 145 复位 `:= 1`、163 回卷 | 疑似（同上） |

### 族② 判定保持（eDone 相出口电平回落）
| 文件 | 命中行 | 判断 |
|---|---|---|
| DL_Motion/FB_DL_AxisHomeRepeatVerify.st | 97-98（每拍预清）/166/168/171 | **需修**（本轮 P0-1） |
| DL_Device/FB_DL_CylStrokeTimeBank.st | 89（`_bReject := FALSE` 当拍量预清） | 疑似（需核 89 是「当拍量」还是「出口电平」，若为单拍脉冲语义则无需修） |
| DL_Device/FB_DL_GripperForceVerify.st | 138（`bOk := FALSE` 出口预清） | 疑似（需核预清位置是否导致完成相回落） |
| DL_Process/FB_DL_PileClampCtrl.st / FB_DL_InvInsulTestSeq.st | eDone+bPass 同现，预清行未定位 | 疑似（R53 返修时顺带 5 分钟定位） |

### 族③ 段 0 定时器相位闸（自复位 TON 未挂状态相位）
| 文件 | 命中行 | 判断 |
|---|---|---|
| DL_Device/FB_DL_HeatTraceCircuitMon.st | 83/84 | **需修**（本轮 P0-3） |
| DL_Device/FB_DL_MeterPulseLossDetect.st | 78 `tonWin(IN := NOT tonWin.Q, PT := tSample)` | 疑似（纯测量窗、判定在窗结算拍取快照则无需修；若 `tonWin.Q` 直接触发锁存则需修） |
| DL_Device/FB_DL_FanBeltSlipDetect.st | 54 `tonWin(IN := NOT tonWin.Q, ...)` | 疑似（同上口径） |
| DL_Base/FB_DL_EdgeIntervalMeter.st | 79 `tonFree`（自由时基，设计即全相位） | 无需修（R188 设计声明在案，跨天回卷已钳 0） |

### 族④ 热模型量纲（能量↔温升换算不自洽）
| 文件 | 命中行 | 判断 |
|---|---|---|
| DL_Device/FB_DL_BrakeResistorThermal.st | 127/141 | **需修**（本轮 P0-4） |
| DL_Device/FB_DL_HeaterBreakDetect.st | 66/107（温升速率判据，非能量积分式） | 无需修（判据为 ΔT/min 直接口径，无能量-温升映射） |
| DL_Device/FB_DL_RotaryUnionWatch.st | 58/101（温升直接测量口径 + 相位闸已挂 `eRun`） | 无需修（测量型温升 + 相位联锁在位，反例自证） |
| DL_Process/FB_DL_SlurryMixingSeq.st | 命中 fTempRise 类符号 | 疑似（需核是否能量积分→温升线性映射；若仅为温度设定斜率则无需修） |

## 三向差额回写（只列不改）

比对口径：ROADMAP `- [ ]` 条目主件名（行内首个反引号 POU 名）∈ INDEX_REGISTRY components（945 名）→ 「已在 registry 但 ROADMAP 仍空勾」。实测 **18 条**（预期约 7，超出部分按 R192 逐条列账，收尾阶段勾选）：

| ROADMAP 行号 | 组件名 |
|---|---|
| 418 | FB_DL_TrayLoadVacuum |
| 435 | FB_DL_CupFillDenest |
| 443 | FB_DL_HumidifierAdiabat |
| 471 | FB_DL_NgBinDosing |
| 626 | FB_DL_ElectrodeGapMark |
| 694 | FB_DL_FormationChannelQueue |
| 695 | FB_DL_SlurryDensityTrim |
| 718 | FB_DL_FilmSpliceWeekPlan |
| 720 | FB_DL_CasePackerPatternVerify |
| 724 | FB_DL_AhuFanArrayTrim |
| 725 | FB_DL_ChillerYearWinStart |
| 733 | FB_DL_ReactorYearWinClean |
| 736 | FB_DL_LoopAuditTrailWindow |
| 814 | FB_DL_LamEvaGelContent |
| 832 | FB_DL_PalletLabelVerify |
| 879 | FB_DL_ElectrolyteFillVacuum |
| 907 | FB_DL_DateCoderPosition |
| 920 | FB_DL_SteamTrapSurvey |

附注：本清单即为「三向一致」（INDEX_REGISTRY ∪ 文件树 ∪ ROADMAP 勾选）差额的 registry→ROADMAP 单向差额；勾选时须同步核对该件手册接口表与 JSONL 行在位，防「registry 有、手册无」的第二向差额。
