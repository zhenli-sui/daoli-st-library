# R49 计划（2026-11-20 · 无人值守自动构建 · 硬预算 10 分钟）

> 基线：registry v2.40.0 count 865｜配额 MathData≤2 / Process≤4｜T0=0（八组收口余量 0，不凑数）｜ROADMAP 待办 56 ≥30 本轮禁新增（选题只用「registry 0 命中 ∩ 在册空勾或自研线真缺口」）。

## 一、20 目标锁定表（4 批 × 5，按依赖聚类）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_QuatRotateVec | DL_MathData | FC | 单位四元数旋转三维向量（机器人/跟踪支架姿态换算叶子件） | 自研线（公开四元数定义 clean-room） | 3 | 1 |
| 2 | FC_DL_GeoMeanCalc | DL_MathData | FC | 非负数组几何平均（log 域安全，非正元素拒算，良率/寿命均值） | 自研线 | 2 | 1 |
| 3 | FB_DL_HeartbeatGen | DL_Base | FB | 可组周期心跳翻转脉冲发生器（PLC↔远程 IO 喂狗侧，与 WatchdogPulseMon 监视侧成对） | 自研线（与既有监视件成对补口） | 2 | 1 |
| 4 | FB_DL_PulseSeqVerify | DL_Base | FB | 脉冲序列完整性校验（期望 n 脉冲实测 m 脉冲，步进/流量脉冲丢失判据） | 自研线 | 3 | 1 |
| 5 | FB_DL_StepTimeRecorder | DL_Base | FB | 顺控各步耗时在线采集统计（与 FB_DL_StepSequencer 配对的测量侧） | 自研线 | 3 | 1 |
| 6 | FB_DL_CycleBarrierGate | DL_Base | FB | 多设备同周期相位会合闸（全体成员就绪才统一放行下一拍，集合点原语） | 自研线 | 3 | 2 |
| 7 | FB_DL_SignalReconstruct | DL_Algo | FB | 短丢包信号重构（丢 1~2 拍线性外插 + 不确定度带，通信抖动场景） | 自研线（状态估计） | 4 | 2 |
| 8 | FB_DL_ValveSeatLeakWatch | DL_Device | FB | 阀座关闭位泄漏趋势监视（关位 dp/流量残差趋势判泄漏，与 ValvePartialStrokeTest 行程试验分工） | 自研线（诊断族深化） | 4 | 2 |
| 9 | FB_DL_CylStrokeTimeBank | DL_Device | FB | 气缸行程时间分档趋势库（多缸行程时间逐拍建档、劣化分档预警） | 自研线 | 4 | 2 |
| 10 | FB_DL_CaseErectFaultSeq | DL_Device | FB | 开箱成型失败重试与吸盘堵塞诊断（ROADMAP 在册空勾 P2，复用 VacuumEjector 判据思想） | ROADMAP 在册（R13 新增行） | 5 | 2 |
| 11 | FB_DL_LoopSignGuard | DL_Algo | FB | 回路正反作用符号在线自检（PV/CV 增量相关性判接线反接，调试期防呆） | 自研线 | 4 | 3 |
| 12 | FB_DL_ExtremumSeekCtrl | DL_Algo | FB | 极值寻优控制（扰动+梯度估计式 ES，无需模型的最优设定点漂移追踪） | 自研线（公开 ES 算法 clean-room） | 5 | 3 |
| 13 | FB_DL_LoopCoupleDetect | DL_Algo | FB | 回路耦合度在线探测（单回路激励期测邻回路响应相关，为 Decouple2x2 提供投运判据） | 自研线 | 4 | 3 |
| 14 | FB_DL_RulEstimator | DL_Algo | FB | 多特征健康指数线性外推剩余寿命估计（预测性维护 RUL，退化率+置信带输出） | 自研线 | 5 | 3 |
| 15 | FB_DL_RoomTempClassify | DL_Process | FB | 房间温度舒适带四档分级（复用 FC_DL_TempUnitConvert/FC_DL_LimitClassify，ROADMAP 在册 P1） | ROADMAP 在册（HVAC 行） | 3 | 3 |
| 16 | FB_DL_MoveResumeSeg | DL_Motion | FB | 断点续走（断电重启后从当前位置续走剩余行程，目标/进度快照恢复） | 自研线 | 5 | 4 |
| 17 | FB_DL_VelFfGainIdent | DL_Motion | FB | 速度前馈增益辨识（恒速段跟随残差回归 Kvf，与 AxisInertiaIdent/AxisFrictionFf 辨识族分工） | 自研线 | 4 | 4 |
| 18 | FB_DL_SoftLimitCfgAudit | DL_Motion | FB | 软限位组态交叉审计（软限域 ⊆ 硬限域/行程域判定，与 SoftLimitGuard 运行期守卫分工） | 自研线 | 3 | 4 |
| 19 | FB_DL_AxisLubeDistTrig | DL_Motion | FB | 轴走行距离润滑触发（按累计走行里程触发润滑泵脉冲，里程窗可组） | 自研线 | 3 | 4 |
| 20 | FB_DL_BrakeWearAccum | DL_Motion | FB | 抱闸磨损里程累计（制动投入时长/次数加权累计，与 AxisBrakeTest 周期试验分工） | 自研线 | 3 | 4 |

配额核对表（R319 成对口径）：MathData 2（顶格 ≤2）/ Process 1（≤4 未顶格，纠偏下探）/ Algo 5 / Motion 5 / Base 5 / Device 3 —— 超配件（MathData/Process）压量与薄池（Algo/Motion/Base）补量同表成对成立。

分工声明必写清单（编码时逐件进头注释）：HeartbeatGen↔WatchdogPulseMon（发生/监视）、PulseSeqVerify↔EventCounter（序列完整性/无序计数）、StepTimeRecorder↔StepSequencer（测量/编排）、CycleBarrierGate↔SemaMutex（会合闸/互斥）、ValveSeatLeakWatch↔ValvePartialStrokeTest（关位泄漏趋势/行程试验）、LoopCoupleDetect↔Decouple2x2（探测/解耦执行）、SoftLimitCfgAudit↔SoftLimitGuard（组态审计/运行守卫）、BrakeWearAccum↔AxisBrakeTest（磨损累计/周期试验）、VelFfGainIdent↔AxisFrictionFf（辨识/前馈注入，R312 模型不内嵌注入）、MoveResumeSeg↔MotionCmdQueue（断点续走/指令排队）、RulEstimator↔DeviceHealthArbiter（寿命外推/健康仲裁）。

## 反证句（20/20，grep INDEX_REGISTRY.json 实测）

候选1：grep "QuatRotateVec" registry → 0 命中（Quaternion 近义词 0 命中）
候选2：grep "GeoMeanCalc" registry → 0 命中（GeoMean 近义词 0 命中）
候选3：grep "HeartbeatGen" registry → 0 命中（HeartBeat 近义词 0 命中）
候选4：grep "PulseSeqVerify" registry → 0 命中（PulseSeq 近义词 0 命中）
候选5：grep "StepTimeRecorder" registry → 0 命中
候选6：grep "CycleBarrierGate" registry → 0 命中（Barrier 近义词 0 命中）
候选7：grep "SignalReconstruct" registry → 0 命中（Reconstruct 近义词 0 命中）
候选8：grep "ValveSeatLeakWatch" registry → 0 命中（SeatLeak 近义词 0 命中）
候选9：grep "CylStrokeTimeBank" registry → 0 命中（StrokeTime 近义词 0 命中）
候选10：grep "CaseErectFaultSeq" registry → 0 命中（ErectFault 近义词 0 命中；ROADMAP 在册空勾，非撞名）
候选11：grep "LoopSignGuard" registry → 0 命中（SignGuard 近义词 0 命中）
候选12：grep "ExtremumSeekCtrl" registry → 0 命中（Extremum 近义词 0 命中）
候选13：grep "LoopCoupleDetect" registry → 0 命中（CoupleDetect 近义词 0 命中；与 Decouple2x2/CrossCorrelationDelay 不同义：探测≠解耦≠延时辨识）
候选14：grep "RulEstimator" registry → 0 命中（RulEst 近义词 0 命中）
候选15：grep "RoomTempClassify" registry → 0 命中（Comfort 近义词 0 命中；ROADMAP L580 在册空勾）
候选16：grep "MoveResumeSeg" registry → 0 命中（ResumeSeg 近义词 0 命中）
候选17：grep "VelFfGainIdent" registry → 0 命中（VelFf 近义词 0 命中）
候选18：grep "SoftLimitCfgAudit" registry → 0 命中（CfgAudit 近义词 0 命中；与 SoftLimitGuard 名尾不同义不同）
候选19：grep "AxisLubeDistTrig" registry → 0 命中（LubeDist 近义词 0 命中）
候选20：grep "BrakeWearAccum" registry → 0 命中（BrakeWear 近义词 0 命中）

## R48 终审（5 抽）

| 件名 | 结论 | 问题一句话 | 处置 |
|---|---|---|---|
| FB_DL_LookaheadVelPlanner | 中 | 回溯步 aVelCap[i]² ≤ aVelCap[i+1]² + 2·a[i]·**L[i+1]** 用了邻段长度，与前传（a[i+1]·L[i+1] 本段加速）不对称——减速发生在第 i 段内、可用距离应为 L[i]，邻段长度低估/高估减速可达性 | 挂账R50 v1.0.1：回溯累加式改 `aSeg[i].fAccelMmS2 * aSeg[i].fLenMm` + 验收向量重跑 |
| FB_DL_AutoclaveSterilSeq | 轻 | bStop 中止清脉动计数/子态但**保留 F0 累计**（批审计口径可能是故意的），与 bReset 全清的差异未在头注释声明 | 挂账R50：头注释补 bStop/bReset 作用域逐域清单（R311 扩展） |
| FB_DL_SensorFusion2 | 轻 | fTauVar=0 端点值使方差递推静默失效（权重恒 0.5，"方差骤增→权重移向 B"验收向量失效），组态闸无告警 | 挂账R50：fTauVar=0/1 端点语义显式声明或组态告警 |
| FB_DL_ContourCrossCouple | 轻 | fDirX/fDirY 非有限仅判 NaN（x<>x），未沿用 fErr 侧 Inf 差判口径（(x-x)<>0），口径不一致 | 挂账R50：dir 侧补齐 Inf 差判（一行） |
| FC_DL_SaturateSub | 轻 | 头注释验收向量「MIN-(-1)=MIN 溢出」断言错误：MIN-(-1)=-2147483647 可表不溢出，真上溢向量为 MAX-(-1)；正文先判后算实现本身正确 | 挂账R50：头注释向量行更正（文档级） |

终审小结：0 严重 / 1 中 / 4 轻；中项为运动学公式不对称（机检盲区），全部挂账 R50 带**精确修法**，本轮无人值守不做行为变更避免未复验入库。
