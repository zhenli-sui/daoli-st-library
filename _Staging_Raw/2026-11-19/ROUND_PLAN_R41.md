# ROUND_PLAN_R41（第 41 轮无人值守构建规划 · 2026-11-19 07:16）

> 本轮性质：**阶段一盘点 + 20 目标锁定 + P0 返修清单**。规划轮禁止编码。
> 检索预算：WebSearch 0/3（**零检索轮**），全部复用源矩阵既有 ◐ 组语义深化 + ROADMAP 实证真缺口。

## 1. 盘点统计

| 项 | 数值 |
|---|---|
| 总库规模 | 705 / 10,000（registry v2.32.0，last_updated 2026-11-19T05:12） |
| 今日产出 | 35 / 200（11-19 当日）；500 件阶段计划已达成并超额 +205 |
| 各池 counts | Base 80 / MathData 193 / Algo 70 / Device 138 / Motion 66 / Process 158 |
| ROADMAP 未勾项 | 159 条（有名条目 138，其中第一轮脚本判真缺口 104 —— **经逐名复核含至少 3 条假缺口**，见 §4 教训） |
| 源矩阵覆盖 | T0 七组 7/7 ✔（R40 清账）；T1-3 ✔ 收口；T1-2 子族级 ✔；其余 T1/T2 均 ◐ 深化中 |
| 进化游标 | DIRECTOR_EVOLUTION 至 [R244]；PLC_EXPERT_EVOLUTION 至 R40（5 条） |

## 2. P0 返修 3 件（不占 20 新件名额，file_path 全部 registry 实测）

| # | 组件 | 实测路径 | 缺陷（来源） | 修复要求 |
|---|---|---|---|---|
| P0-1 | FB_DL_AxisLimitRecovery | `C:\Library\DL_Motion\FB_DL_AxisLimitRecovery.st` | R240 高危：段 4 解除式「rtReset.Q AND NOT _bFault」引用锁存位自身当解除条件，锁存后恒假永久锁死（R28-1 反例复发） | 解除式全部改当拍量（rtReset.Q 直连 eState 迁出边）；每个解除式 BOOL 逐个标注「锁存量/当拍量」；头注释自证句与实现逐字对照（R240/R234） |
| P0-2 | FB_DL_MutexOwnerAudit | `C:\Library\DL_Base\FB_DL_MutexOwnerAudit.st` | R241 高危：UDINT_TO_DINT(16#FFFF_FFFE) 降型回绕为负，且 UDINT ms 累加器数学上永远达不到 SEC_MAX×1000 —— 饱和闸整段失效 | 比较闸整体上移到 UDINT 域消除降型；派单规格写明「判定值域 + 可达性向量」；降型溢出按编译阻断级预检（R241） |
| P0-3 | FC_DL_StringToDint | `C:\Library\DL_MathData\FC_DL_StringToDint.st` | R40 发现：出口段 eErr:=16#0001_038B 未配对 bError 置位（R101 配对缺失） | 出口段故障码赋值行 3 行内显式补 `bError := TRUE`；版本 1.0.1 → 1.0.2，VERSION/MANUAL 同步 |

## 3. 20 新目标总表（每名已过 R40/R244 强制双查）

双查方法：① INDEX_REGISTRY.json 全名精确匹配；② `DL_*/*.st` 全库文本子串匹配；③ 同义词干在册名扫描（命中即拒）。20 名全部 **REG 0 命中 / ST 0 命中**。

| 序 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_SignalQualify | DL_Base | FB | 模拟量信号有效性三态联合判定（超量程/断线冻结/卡死） | t2-1-lgf-measurement | 6 | 1 |
| 2 | FB_DL_MultiClickDetect | DL_Base | FB | 按钮短按/长按/双击三形态判定（调试盘刚需） | t1-5-tcopen | 4 | 1 |
| 3 | FC_DL_AngleDiffWrap | DL_MathData | FC | 角度差环绕归一至 ±180°（相机/回零判角共用底座） | iec-std-wrapper | 3 | 1 |
| 4 | FC_DL_WeightedMeanCalc | DL_MathData | FC | 数组加权平均（权重和防零） | t2-1-lgf-math | 3 | 1 |
| 5 | FC_DL_QuantileCalc | DL_MathData | FC | 排序数组分位数（线性插值法，P50/P95 工艺窗） | t2-1-lgf-math | 5 | 1 |
| 6 | FB_DL_ValueHoldMonitor | DL_Base | FB | 信号冻结保持：域外/超时保持最后有效值 + 掩码标记 | t1-2-oscat（域外显式化纪律） | 5 | 2 |
| 7 | FB_DL_WindowExtremaStat | DL_MathData | FB | 滑动窗极值/均值聚合（基于 FB_DL_RingBufferLReal） | t2-1-lgf-datahandling | 6 | 2 |
| 8 | FB_DL_OverrideSelector | DL_Algo | FB | 高选/低选超驰选择器（多路输出竞优先仲裁） | t2-5-modpid | 4 | 2 |
| 9 | FB_DL_AxisFollowErrGuard | DL_Motion | FB | 轴跟随误差窗口监视（位置环偏差带 + 超窗故障锁存） | t1-6-plcopen | 5 | 2 |
| 10 | FB_DL_AxisOverspeedGuard | DL_Motion | FB | 轴超速守卫（速度窗 + 加速度窗双判据） | t2-4-s7motion | 5 | 2 |
| 11 | FB_DL_AxisInposGuard | DL_Motion | FB | 到位窗口判定守卫（MC_InPosition 语义 + 驻留确认） | t1-6-plcopen | 4 | 3 |
| 12 | FB_DL_AxisAbortSafeSeq | DL_Motion | FB | 运动中止安全序列（Abort→Stop→禁能三段迁出边齐全） | t1-6-plcopen | 7 | 3 |
| 13 | FB_DL_StepResponseIdent | DL_Algo | FB | 一阶+纯滞后阶跃响应辨识（切线法，K/T/θ 三参数） | t2-5-modpid | 8 | 3 |
| 14 | FB_DL_RatioStationCalc | DL_Algo | FB | 比值站：随动设定 = K×主流量 + 偏置（比值/固定双模式） | t2-2-lbp | 4 | 3 |
| 15 | FB_DL_CascadeWindupLink | DL_Algo | FB | 串级外环→内环设定传递抗饱和联动（外环输出钳=内环限幅镜像） | t2-5-modpid | 7 | 3 |
| 16 | FB_DL_InverterPdiPoll | DL_Device | FB | 逆变器 PDI 参数周期读取（单拍单发 + 站表台账） | t1-7-plcnext | 6 | 4 |
| 17 | FB_DL_FilterSwitchLevel | DL_Device | FB | 过滤器液位/料位联锁（fail-safe LOW + 再生切换闭锁） | t2-2-lbp | 5 | 4 |
| 18 | FB_DL_ShrinkTunnelCtrl | DL_Process | FB | 热收缩炉温区-网速联动（收缩膜工艺窗口三段窗） | t1-2-oscat | 7 | 4 |
| 19 | FB_DL_VavDischargeAirReset | DL_Process | FB | 送风温度重置（末端阀位加权平均 → 送风设定值） | t1-2-oscat | 6 | 4 |
| 20 | FB_DL_ConveyorDirMismatch | DL_Process | FB | 输送线停机方向失配独立诊断窗（反窜/倒滑） | t2-7-packml（终审立项） | 6 | 4 |

分布：Base 3 / MathData 4 / Algo 4 / Motion 4 / Device 2 / Process 3 —— 回补近四轮产出偏少的 MathData/Algo/Motion/Base 池，无单一池独大。
T2 组件族要求：满足（t2-5 ModPID 族 4 件、t2-1 LGF 族 5 件、t1-6 PLCopen 族 4 件均为既有 ◐ 组零检索深化）。

### 每名反证句（R40 强制）

1 SignalQualify：grep registry 0 命中；全库 .st 0 命中；词干 Qualify 在册名 0。
2 MultiClickDetect：grep registry 0；全库 .st 0；词干 MultiClick 0（ToggleButtonBank 为开关组，语义不同）。
3 AngleDiffWrap：grep registry 0；全库 .st 0；词干 AngleDiff 0。
4 WeightedMeanCalc：grep registry 0；全库 .st 0；词干 WeightedMean 0（SignalStatistics 无权重口）。
5 QuantileCalc：grep registry 0；全库 .st 0；词干 Quantile 0（MedianFilter 为滑动中值滤波，非分位数函数）。
6 ValueHoldMonitor：grep registry 0；全库 .st 0；词干 ValueHold 0（LevelRadarValidate 为雷达专用件，本件为 Base 通用化）。
7 WindowExtremaStat：grep registry 0；全库 .st 0；词干 Extrema 在册名 0（PeakDetector 只检峰不聚合）。
8 OverrideSelector：grep registry 0；全库 .st 0；词干 Override 命中 CamOverrideTrim/HumidityOverride —— 凸轮修调与湿度超驰，与本件「多路高/低选仲裁」语义不同，判非同义。
9 AxisFollowErrGuard：grep registry 0；全库 .st 0；词干 FollowErr 在册名 0（SoftLimitGuard 管位置越程，非跟随误差）。
10 AxisOverspeedGuard：grep registry 0；全库 .st 0；词干 Overspeed 0。
11 AxisInposGuard：grep registry 0；全库 .st 0；词干 InposGuard 0（SingleAxis 内部到位标志 ≠ 独立守卫件）。
12 AxisAbortSafeSeq：grep registry 0；全库 .st 0；词干 AbortSafe 0。
13 StepResponseIdent：grep registry 0；全库 .st 0；词干 StepResponse 0。
14 RatioStationCalc：grep registry 0；全库 .st 0；词干 RatioStation 0（MfcRatioCheck 为配比窗校验，非比值站控制件）。
15 CascadeWindupLink：grep registry 0；全库 .st 0；词干 WindupLink 0（CascadePid 为串级主件，本件为其抗饱和联动补件，非同义变体）。
16 InverterPdiPoll：grep registry 0；全库 .st 0；词干 PdiPoll 0（PdiReadScheduler 为调度底座，本件为逆变器域应用件）。
17 FilterSwitchLevel：grep registry 0；全库 .st 0；词干 SwitchLevel 0（LevelSwitchVib 为传感器件，本件为联锁逻辑件）。
18 ShrinkTunnelCtrl：grep registry 0；全库 .st 0；词干 ShrinkTunnel 0（HeatSealProfile 为热封曲线，非收缩炉联动）。
19 VavDischargeAirReset：grep registry 0；全库 .st 0；词干 DischargeAirReset 0（VavBoxZeroCal 为标定件，非送风重置）。
20 ConveyorDirMismatch：grep registry 0；全库 .st 0；词干 DirMismatch 0（ConveyorZone 为区段主件，本件为其终审立项的独立诊断增强）。

## 4. 双查方法摘要与 R41 教训（写派单前必读）

- 第一轮「ROADMAP 真缺口批量过滤脚本」存在**漏检缺陷**：104 条「真缺口」中抽查 5 条即发现 3 条为已注册假缺口（FB_DL_PumpDryRunGuard / FB_DL_TrackBarcodeTrace / FB_DL_StepperMicroFeedPulseEquiv 均在册）。
- **R41-1 新规候选**：规划侧不再信任批量脚本单查，一律「registry 精确名 + 全库 .st 文本 + 同义词干」三段逐名独立 grep，命中即拒（R40 五件拒单教训 + 本轮 3 条假缺口实证）。
- 本轮因同义在册件被拒的候选 8 件（留档防重提）：FB_DL_HistogramBinCount（≈HistogramAccum）、FB_DL_GainSchedulePid（≈GainScheduler/PidGainScheduler）、FB_DL_BumplessHandover（≈BumplessTransfer）、FB_DL_AxisTorqueMonitor（≈AxisLoadTorqueMonitor）、FB_DL_TankBlanketPrCtrl（≈TankN2BlanketCtrl）、FB_DL_BacklashComp（≈BacklashCompensator）、FB_DL_PumpDryRunGuard/TrackBarcodeTrace（在册）、FB_DL_LaminatorZoneSync（≈LamHeaterZoneSync）。

## 5. 4 批划分 × 每批 5 件完整规格

### 批 1（Level 0 零依赖，纯函数/纯信号整形）
| # | 名称 | 规格要点 | 边界安全条件 | 码位窗口（段 0001） |
|---|---|---|---|---|
| 1 | FB_DL_SignalQualify | 输入 fRaw + 量程上下限 + 卡死带；输出 eQual（eOk/eOverRange/eFrozen/eWireBreak 三态联合）+ bValid；TON 判冻结 | 量程下限必须 < 上限（组态闸）；断线判据=fRaw 低于传感器零点域；卡死=TON 采样方差 < 带 | 故障 16#0001_03DB~03DD / 信息 16#0001_049E~04A0 |
| 2 | FB_DL_MultiClickDetect | 输入 bBtn + tLong/tDouble 窗；输出 bShortPulse/bLong/bDouble | tLong > tDouble 且均 >T#0ms（组态闸）；双击窗内第二沿判据用当拍量 | 故障 16#0001_03DE~03DF / 信息 16#0001_04A1~04A2 |
| 3 | FC_DL_AngleDiffWrap | FC(角度差)→[-180.0,180.0]；fMod 归一口径，360° 环绕 | 输入 ±Inf 先差值自减判非有限（LREAL 口径 R40）；正好 180.0 归 +180 不归 -180（进位点向量） | 故障 16#0001_03E0 / 信息 16#0001_04A3 |
| 4 | FC_DL_WeightedMeanCalc | FC(aVals,aWeights,n)→fMean；LREAL 累加 | 权重和=0 返回 0+bValid FALSE（防除零）；n<=0 或越界判界先行 | 故障 16#0001_03E1 / 信息 16#0001_04A4 |
| 5 | FC_DL_QuantileCalc | FC(aSorted,n,fQ)→fQuantile；线性插值 (n-1)*q 落位 | n<=0 拒；q∉[0,1] 钳位+信息码；正好整除点 (n-1)*q 为整数时直接取位（进位点） | 故障 16#0001_03E2~03E3 / 信息 16#0001_04A5~04A6 |

### 批 2（Level 0 收口 + Level 1 独立监视件）
| # | 名称 | 规格要点 | 边界安全条件 | 码位窗口 |
|---|---|---|---|---|
| 6 | FB_DL_ValueHoldMonitor（Base） | 域外/超时→保持最后有效值 + uMask 置位；恢复新值需域内连续 m 拍 | 域判据用当拍量；掩码位序与故障码一一对应；m>=1 组态闸 | Base 段 0001：03E4~03E6 / 04A7~04A9 |
| 7 | FB_DL_WindowExtremaStat（MathData） | 基于 FB_DL_RingBufferLReal 的滑窗 min/max/mean；窗满前 bValid=FALSE | 窗容量 >=1 组态闸（0 值判据恒真反例 R227）；空窗判据显式短路 | MathData 段 0001：03E7~03E9 / 04AA~04AC |
| 8 | FB_DL_OverrideSelector（Algo） | n 路输入 eSel∈{eHigh,eLow}→fOut+胜出通道号 uWin；平值取首路 | n<=0 拒且 bValid FALSE；uWin=0 表示无有效输入 | Algo 段 0002：03A3~03A4 / 0489~048A |
| 9 | FB_DL_AxisFollowErrGuard（Motion） | 经 I_DL_MotionAxis 读 fPosAct/fPosSet；误差带 + 超窗 TON → 故障锁存；解除式全当拍量（P0-1 教训落地） | 误差带下移 >=0.0 语义显式化；解除式逐 BOOL 标注锁存量/当拍量 | Motion 段 0004：03A8~03AA / 04A8~04AA |
| 10 | FB_DL_AxisOverspeedGuard（Motion） | fVelAct 超速窗 + 加速度窗双判据；独立 TON；故障锁存解除可达 | 速度窗下限 >0 组态闸；加速度窗按 (v-v1)/dt 离散差分并写明采样周期单位 | Motion 段 0004：03AB~03AD / 04AB~04AD |

### 批 3（Algo 控制律 + Motion 序列 + Device 首件）
| # | 名称 | 规格要点 | 边界安全条件 | 码位窗口 |
|---|---|---|---|---|
| 11 | FB_DL_AxisInposGuard（Motion） | 到位带 + 驻留 TON 双判据 → bInpos；驻留期目标变更即复位 | 到位带 >0 组态闸；目标变更判据用当拍量比较（禁锁存量自指） | Motion 段 0004：03AE~03B0 / 04AE~04B0 |
| 12 | FB_DL_AxisAbortSafeSeq（Motion） | Abort→Stop→Disable 三段状态机；每段 TON 超时独立实例（R233 成对纪律）；eFault 相承载复位迁出边 | 每段迁出条件可满足性自证逐字入头注释；配方推进与超时 TON 分实例 | Motion 段 0004：03B1~03B3 / 04B1~04B3 |
| 13 | FB_DL_StepResponseIdent（Algo） | 阶跃注入后按切线法辨识 K/T/θ；采样数组经内部缓冲 | 阶跃幅值 !=0 组态闸（防除零）；T>=0、θ>=0 判据；辨识未完成输出保持 + bValid FALSE | Algo 段 0002：03A5~03A8 / 048B~048E |
| 14 | FB_DL_RatioStationCalc（Algo） | fMaster×K+fOffset 双模式（比值/固定）；主流量无效时切固定并置信息码 | K 组态域钳位；fMaster 非有限差值自减判定；模式切换 bTrigger 边沿检测 | Algo 段 0002：03A9~03AA / 048F~0490 |
| 15 | FB_DL_CascadeWindupLink（Algo） | 外环输出钳制值镜像内环限幅；内环饱和时外环冻结积分（引用 FB_DL_PidController 引脚契约，不改其对外接口） | 内环限幅值 <=0 语义显式化；镜像钳制仅在 bTrack=FALSE 相生效（R242 跟踪相退化推演） | Algo 段 0002：03AB~03AE / 0491~0494 |

### 批 4（Device 收口 + Process 工艺联动）
| # | 名称 | 规格要点 | 边界安全条件 | 码位窗口 |
|---|---|---|---|---|
| 16 | FB_DL_InverterPdiPoll（Device） | 基于 FB_DL_PdiReadScheduler 单拍单发 + FB_DL_ModbusPollMaster 站表台账；读-比-判三段 | 站表容量下限 >=1；单拍单发禁批量并发；超时 TON 独立实例 | Device 段 0003：信息 041C~041E / 故障 03FC~03FD（03xx 带仅余 2 位，不够则启用 051C~） |
| 17 | FB_DL_FilterSwitchLevel（Device） | FB_DL_LevelSwitchVib fail-safe LOW 判据 + 再生切换闭锁；双表冗余可选 | fail-safe 断线=LOW 语义入头注释；切换闭锁用当拍量边沿 | Device 段 0003：信息 041F~0421 / 故障 03FE~03FF |
| 18 | FB_DL_ShrinkTunnelCtrl（Process） | 温区（FB_DL_HeatCoolZone 多实例）-网速联动三段工艺窗（预缩/主缩/定型） | 网速下限 >0 组态闸；温区数 >=1；配方推进 TON 与超时 TON 成对分实例 | Process 段 0005：故障 0367~0369 / 信息 048F~0491 |
| 19 | FB_DL_VavDischargeAirReset（Process） | 末端阀位加权平均 → 送风设定值重置；权重=末端数量的有效性门控 | 末端数 >=1；权重和=0 防除零退回默认设定值+信息码 | Process 段 0005：故障 036A~036C / 信息 0492~0494 |
| 20 | FB_DL_ConveyorDirMismatch（Process） | 停机后出口光电变化但方向与运行方向不符 → 反窜/倒滑独立诊断窗（复用 FB_DL_ConveyorZone 光电与 run-on 语义） | 独立诊断窗 TON 与运行窗分实例；停机判据用当拍量 | Process 段 0005：故障 036D~036F / 信息 0495~0497 |

## 6. 各子库实测可用码位窗口（口径：.st 头部 1504 字节 ∪ 全文，R39 定档）

| 子库（段前缀） | 实测占用上限（head∪full 全库实扫） | 本轮分配窗口 | 备注 |
|---|---|---|---|
| DL_Base ∪ DL_MathData（段 0001 共用 Level 0 游标） | 信息 04xx → 049D；故障 03xx → 03DA；01xx→01FF、02xx→02FF 已饱和 | 故障 03DB~03E9 / 信息 049E~04AC（Base 3 件 + MathData 4 件，共 9 故障 + 13 信息位） | 01xx/02xx 带禁用；派单侧与编码线各自复扫（R75②），两值不一致即拒单 |
| DL_Algo（段 0002） | 故障 03xx → 03A2；信息 04xx → 0488 | 故障 03A3~03AE / 信息 0489~0494 | 4 件 |
| DL_Device（段 0003） | 故障 03xx → 03FB（**仅余 03FC~03FF 4 位，紧张**）；信息 04xx → 041B；05xx → 051B | 信息 041C~0421 / 故障 03FC~03FF（不够则溢至 051C~） | Device 故障带将满，建议 R42 规划启用 05xx 副故障带并在头注释写明分段理由（R192） |
| DL_Motion（段 0004） | 故障 03xx → 03A7；信息 04xx → 04A7 | 故障 03A8~03B3 / 信息 04A8~04B3 | 4 件 |
| DL_Process（段 0005） | 故障 03xx → 0366；信息 04xx → 048E；段 0006 B 带 30xx → 3035 | 故障 0367~036F / 信息 048F~0497 | 3 件 |

## 7. 依赖核查结论

批内引用的全部底座件均在册：FB_DL_SignalStatistics / FB_DL_RingBufferLReal / I_DL_MotionAxis / FB_DL_PidController / FB_DL_CascadePid / FB_DL_PdiReadScheduler / FB_DL_ModbusPollMaster / FB_DL_LevelSwitchVib / FB_DL_ConveyorZone / FB_DL_HeatCoolZone / FC_DL_TempUnitConvert / FB_DL_StepSequencer / FB_DL_ToleranceWindow（registry 实测 OK）。无跨层反向依赖。

## 8. 本轮执行顺序建议

1. P0 返修 3 件（先行，机检 + R240/R241 两式推演复核）。
2. 批 1 → 批 2 → 批 3 → 批 4，每批收口链固定：落盘 → CRLF → 六项机检 → 演进账本（R40 收口链固化）。
3. 单窗 <=15 件纪律（R239）：20 件若超时按 R239 双窗拆分，P0 3 件不并入编码窗计时。
