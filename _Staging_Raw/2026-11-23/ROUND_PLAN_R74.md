# ROUND_PLAN_R74（2026-11-23 07:54 启动，60′ 硬顶，TARGET=40）

## 0. 前置状态
- 总库 1,238/10,000（v2.65.0），今日 11-23 累计 32/300，SFT 语料 1,277。
- 锁：R74 / 07:54:40 / target=40。五角色串行保质量、猎人∥编码并行提吞吐。
- 上轮 L2 通过率 100%（≥85%，不强制预留修复名额，但 P0 存量账占本轮主轴）。

## 1. 存量修复批（P0，dl_gate --hours 3 实测清单，编码专家优先执行）
| # | 文件 | 缺陷 | 处置 |
|---|------|------|------|
| P1 | DL_Motion/FB_DL_AxisDualFeedbackGuard.st | L68 _fDev 未声明；fDev 未赋值 | 补声明+每拍赋值 |
| P2 | DL_Motion/FB_DL_AxisLoadEncoderLossMonitor.st | _fPosDelta 未声明；fPosDelta 未赋值 | 补声明+每拍赋值 |
| P3 | DL_Motion/FB_DL_ScreenPrintAlign.st | L123 __ISVALIDREF | 换 (iAxisX<>0)/(iAxisY<>0) 口径 |
| P4 | FB_DL_BacdHvacPoll.st | _nOfflineCnt 未声明 | 补声明（VER 由 registry 侧同步） |
| P5 | FB_DL_HeatExchangerFoulingTrend.st | _eState 未声明 | 补声明（按实况选枚举或复用 eState） |
| P6 | FB_DL_InlineCheckweighGauge.st | _fMeanOut_g 未声明；fMeanOut_g 未赋值 | 补声明+赋值 |
| P7 | FB_DL_PackMlUnitMode.st | _eAccepted 未声明 | 补声明 |
| P8 | FB_DL_PalletGripperSafe.st | _eState 未声明 | 补声明 |
| P9 | FB_DL_PalletizerStation.st | __ISVALIDREF ×2 | 换 (iCylGrip<>0)/(iCylLift<>0) |
| P10 | DL_Process/FB_DL_PileClampCtrl.st | L88 __ISVALIDREF | 换 (ipCyl<>0) |
| P11 | FB_DL_RecipeSearchFifo.st | _eState 未声明 | 补声明 |
| P12 | FB_DL_RollPressBitWord.st | _bAnyAlarm 未声明 | 补声明 |
| P13 | FB_DL_RoomCo2DemandVent.st | _bSensorFail 未声明 | 补声明 |
| P14 | FB_DL_SeasonMonthSched.st | L133 CASE 无 ELSE；_eState 未声明 | 补 ELSE 兜底+声明 |
| P15 | FB_DL_SlurrySieveClogWatch.st | _fTrendSlope 未声明 | 补声明 |
| P16 | FB_DL_SingleAxis.st | L358 SYN_CROSS_END | 修正 PROPERTY/END_FUNCTION_BLOCK 交叉 |
| P17 | FB_DL_BatchDosingControl.st | L440 SYN_CROSS_END | 同上 |
| P18 | I_DL_ExternalEncoder.st | L78 END_INTERFACE 与 PROPERTY L60 交叉 | PROPERTY 在接口内闭合 |
| P19 | I_DL_MotionAxis.st | L212 同类 | 同上 |
| P20 | FB_DL_CamOverrideTrim.st | bInRange 未赋值 | 每拍赋值 |
| P21 | FB_DL_NailMachineSeq.st | eSeqState 未赋值 | 每拍赋值 |
| P22 | FB_DL_DisturbanceObserver.st | 缺 END_FUNCTION_BLOCK（R73 NO_TAIL） | 补收尾 |

- VER_MISMATCH 7 件（CassetteMapVerify/CoinCellAssembler/NightPurgeSeq/PassboxInterlockSeq/StringElImageMap/BacdHvacPoll/PackMlUnitMode）：文件头 1.0.1 为历史点修真版本 → closeout 脚本 registry 侧同步 1.0.1，不改代码。
- TIME_TO_DWORD：grep 实测残留 0（仅注释提及），R73 已清账 ✔。

## 2. 新件批（20 目标 = 复杂 8 + 简单 12；队列溯源 6/20 = 30%）
| # | 组件名 | 分类 | 复杂度 | 功能 | 来源标签 |
|---|--------|------|--------|------|----------|
| 1 | FB_DL_MultiPumpRotationCtrl | Device | C4 | 多泵轮换均衡+故障退出 | self-std |
| 2 | FB_DL_WinderTensionTaperCtrl | Motion | C4 | 收卷锥度张力控制 | self-std |
| 3 | FB_DL_SafetyLightCurtainMute | Device | C4 | 光栅消隐/静默状态机 | self-std |
| 4 | FB_DL_KilnTempZoneCascade | Process | C4 | 窑炉多温区串级 | roadmap-industry-pool |
| 5 | FB_DL_CompressorSurgeGuard | Process | C4 | 压缩机喘振防护 | self-std |
| 6 | FB_DL_BatchPhaseStepper | Algo | C3 | ISA-88 相序步进器 | packml/isa88 |
| 7 | FB_DL_TankCipCleanSeq | Process | C4 | CIP 清洗时序 | isa88 |
| 8 | FB_DL_HydrostaticLevelComp | Process | C3 | 静压液位密度/温度补偿 | self-std |
| 9 | FC_DL_EuclidDist2DCalc | MathData | C1 | 2D 欧氏距离 | queue:brOscatLib HYPOT |
| 10 | FC_DL_Log10Safe | MathData | C1 | 安全 log10（防负零域） | queue:EXP10 镜像 |
| 11 | FC_DL_SwapNibbles | Base | C1 | 字节半字交换 | queue:SWAP_BYTE |
| 12 | FC_DL_GrayToByteConv | Base | C1 | 格雷码→二进制反演 | queue:BYTE_TO_GRAY |
| 13 | FC_DL_TankVolCylHoriz | MathData | C2 | 卧式圆柱罐容积 | queue:TANK_VOL1 |
| 14 | FB_DL_SensorGlitchFilter | Device | C2 | 传感器毛刺一阶滤波 | queue:FT_IMP |
| 15 | FC_DL_WrapAngleDeg | MathData | C1 | 角度归一 [-180,180) | self-std |
| 16 | FC_DL_InvSqrtApprox | MathData | C2 | 快速平方根倒数近似 | self-std |
| 17 | FC_DL_Median3Vote | Algo | C1 | 三取二中值表决 | self-std |
| 18 | FC_DL_DewPointSpreadCalc | MathData | C1 | 露点温差 | self-std |
| 19 | FB_DL_ValveStrokeTimeWatch | Device | C2 | 阀门行程时间监视 | self-std |
| 20 | FB_DL_BeltSlipWatch | Device | C2 | 皮带打滑监视 | self-std |

## 3. 执行顺序
1. 编码专家：P1~P22 存量修复 → 新件 1~20 顺序写盘（一批一次派发）。
2. 主控串行 L2 闸（l2_check.py 默认 jobs=1，禁 --jobs>1）→ 失败回退最多 2 轮。
3. 审校去重官 12 项扫查+三道去重（注意同族/精度变体不误杀）。
4. 总监 closeout（registry+JSONL+VER 同步+ROADMAP+文档）。
5. 进化账本 ≤5 条/角色 → 每日复盘 → 飞书播报 → 删锁。

## 4. 预算
WebSearch ≤3；单轮 ≤60′（08:55 收口）；战报 ≤100 行；到点未完写 RESUME。
