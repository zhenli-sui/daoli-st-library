# 道莅工业自动化标准代码库 / Daoli Industrial ST Library

[![Total Components](https://img.shields.io/badge/Total%20Components-1135%20%2F%2010%2C000-blue)](CHANGELOG.md)
[![Level 0](https://img.shields.io/badge/Level%200%20DL--Base-135%20open-success)](DL_Base/VERSION.md)
[![Level 0 DL_MathData](https://img.shields.io/badge/Level%200%20DL--MathData-267%20open-success)](DL_MathData/VERSION.md)
[![Level 1 DL_Algo](https://img.shields.io/badge/Level%201%20DL--Algo-134%20open-yellow)](DL_Algo/VERSION.md)
[![Level 1 DL_Device](https://img.shields.io/badge/Level%201%20DL--Device-204%20open-yellow)](DL_Device/VERSION.md)
[![Level 1 DL_Motion](https://img.shields.io/badge/Level%201%20DL--Motion-120%20open-yellow)](DL_Motion/VERSION.md)
[![Level 2 DL_Process](https://img.shields.io/badge/Level%202%20DL--Process-275%20open-yellow)](DL_Process/VERSION.md)
[![SFT Corpus](https://img.shields.io/badge/SFT%20Corpus-1154%20records-informational)](_AI_Training_Dataset/daoli_st_sft_dataset.jsonl)
[![Platform](https://img.shields.io/badge/Platform-CODESYS%20%7C%20TwinCAT%203%20%7C%20InoProShop-informational)](README.md)
[![IEC 61131-3](https://img.shields.io/badge/IEC-61131--3%20ST-orange)](README.md)
![License](https://img.shields.io/badge/License-MIT-green)

> **Total Components: 1,135 / 10,000 (11.35%)** ｜ **Phase 2: 常态节奏 16~20 件/轮（R60 起按 R249/R193 动态下调）** ｜ **Version: v2.56.0** ｜ **SFT 语料: 1,154 条** ｜ **全库约 232,700 行**

> **R62（2026-11-21）**：11 新件（Base 4 / MathData 4 / Algo 1 / Device 2，饱和乘除·算术右移·符号扩展·INT 饱和转换·有符号转 UDINT·DT 提取·百分位排名·通用二阶节·母线纹波·离子风机联锁）+ 5 项返修（RailPowerSequence v1.0.2 / TurretToolSelect·SensorPairPlausibility·WeightedPercentile·LineClearanceVerify v1.0.1，R61 挂账全清）；总库 1,101→**1,112**，SFT 1,124，机检 16/16 PASS；零检索轮，T0 族内深化 8 件 + T1 1 件 + T2 2 件，撞名拒 7 条（留痕 ROUND_PLAN_R62 §2.3）；**终审 4 抽 7 处挂账（严重 2 / 中 2 / 轻 3）**，R63 配额 16→13。
> **R64（2026-11-21）**：10 新件（Base 1 / MathData 6 / Device 1 / Process 2，三态比较·数组首匹配·切片拷贝·区间间隙·整数 GCD·滑动和·流量四单位互转·双阀冗余组控·返工放行闸·理瓶四相顺控）+ 2 项点修（VfdPrechargeSeq / AdaptiveLmsFilter v1.0.1，R63 挂账 4 处全清）+ **1 项终审就地修**（FlowUnitConvert v1.0.1：L/min 因子方向倒置 277.78 倍，R317 安全侧第①条）；总库 1,125→**1,135**（135/267/134/204/120/275），SFT **1,154**，机检 12/12 PASS；零检索轮（T0 三组 + LGF Comparator/Data Handling ◐ 深化 4 件 + LBP/ISA-88/PackML 次源），撞名拒 6 + 配额顺延 1；**终审 5 抽：严重 1 / 中 1 / 轻 2 / PASS 1**，就地修 1、挂 R65 3 处；新增可判定规则 5 条（R314~R318），不固化（距 FB-51 第 4 轮）。
> **R63（2026-11-21）**：13 新件（MathData 4 / Algo 5 / Device 4，BCD 双向转换·双端截尾均值·皮尔逊相关·EWMA·MAD 野点剔除·RBJ 二阶节系数·多节级联·LMS 自适应·ADC 底噪·三相不平衡·电容老化·预充时序）+ 5 项返修（VfdDcBusRipple·BiquadFilter·IonFanInterlock v1.0.1 / RailPowerSequence v1.0.3 / PercentileRank v1.0.1，R62 挂账 7 处全清）；总库 1,112→**1,125**，SFT **1,142**，机检 18/18 PASS；零检索轮，族①②扩面深化 7 件 + T0-BCD 补口 2 件 + 统计族 2 件 + self 2 件；**终审 5 抽：严重 0 / 中 1 / 轻 3**（挂账 4 处挂 R64，分散型按 R309 点修，R64 配额 13→10）；族②组态早退 / 族①Jury 判据两族扩面目标达成，R62-D1/D2 家族在新件出厂层面关闭。
> **R61（2026-11-21）**：16 新件（Base 4 / MathData 5 / Device 3 / Motion 2 / Algo 1 / Process 1，64 位位图反转·位扫描·三维模长·梯形积分·索引排序·加权分位·平均绝对偏差·长按识别·导轨分级上电·限位开关组·PID 参数闸·缺相保护·双传感器合理性·冷干机诊断·刀塔选刀·清线确认）+ 6 项 v1.0.1 返修（R60 挂账全清）；总库 1085→**1,101**，SFT 1,107，机检 16/16 PASS；零检索轮，撞名拒 24/40=60%（R267 双族避让）；R249/R193 联动下调 20→16。
>
> **R60（2026-11-21）**：12 新件（MathData 5 / Base 3 / Algo 1 / Device 1 / Motion 1 / Process 1）+ **FB-51 固化批次**（16 条规则并入 skills 规范，人格微调 ≤10%）；总库 1073→**1,085**，SFT 1,086，机检 13/13 PASS；子代理 4/3 超预算（立 R291 固化轮预算前置申报）。
>
> **R59（2026-11-21）**：20 新件（Base 3 / MathData 8 / Algo 3 / Device 3 / Motion 3 / Process 3，看门狗·两步确认·多段定时·度分秒·二次求根·DTL 串·ASCII 帧·重采样·喷嘴组·拐角过渡·MRAC·防摇·主轴暖机·脉冲喷吹·上锁挂牌·基2 FFT·电导温补·视觉闸门·刀具预算·批次谱系）+ 3 件 v1.0.1 返修；总库 1053→**1073**，SFT 1074，机检 23/23 PASS；零检索轮，撞名拒 9 件（R214 三查留痕）；收口机检出 LotGenealogyLink 循环配对编译阻断并就地修复（R333 例外）。
>
> **R58（2026-11-21）**：16 新件（MathData 3 / Algo 3 / Device 3 / Process 3 / Base 2 / Motion 2，KooN 表决·仿真注入组·热电偶线性化·偏度峰度·三阶线性解·PMV·软启·电动推杆·最优启停·重复控制·冷凝排污·凸轮段型·轴安全监视·更衣顺控·保持时限·首件锁定）+ 5 件 v1.0.1 返修；总库 1037→**1053**，SFT 1054，机检 21/21 PASS；零检索轮，撞名拒 5 件（R214 三查留痕）。
> **R57（2026-11-21）**：20 新件（Base 5 / MathData 10 / Device 3 / Process 2，T0 Safe 族闭环 15 件——ASIN/ACOS/LN/EXP/整数幂/符号/RMS/奇偶/峰峰/最近邻阶梯插值 + 正交四倍频计数·主从沿同步·信号呆滞·掉线保持 + ESD 接地监视/离子风机风速联锁/证明试验/传递窗互锁/夜间吹扫）+ 4 件 v1.0.1 返修；总库 1017→**1037**，SFT 1038，机检 24/24 PASS；零检索轮，规划拒 19 项（R214 三查）。
> **R56（2026-11-20/21）**：20 新件（MathData 5 / Device 4 / Algo 3 / Motion 3 / Process 3 / Base 2，插值·四元数·RTD·Kalman2D + 双通道急停 + 2-DOF PID + 失重给料/UV 剂量/超声焊/探针测量/风淋联锁）+ 5 件 v1.0.1 返修；总库 997→**1017**（**突破 1,000**），SFT 1018，机检 25/25 PASS；零检索轮，拒 6 项（R214 三查）。
> **R55（2026-11-20）**：20 新件（MathData 1 / Algo 1 / Process 18，电池月窗族 + 光伏/半导体/暖通扩面 + PackML/BACnet 轮询）；总库 977→**997**，SFT 978→**998**，机检 20/20 PASS；零检索轮，选题拒 5 项（R214 三查）；距 1,000 差 3。
> **R54（2026-11-20）**：16 新件（Base 3 / MathData 2 / Algo 2 / Device 3 / Motion 2 / Process 4）+ 3 件 P0 返修 v1.0.1；总库 961→**977**，SFT 962→**978**，机检 19/19 PASS；P0 链：ControlOutputSlewWatch 首拍游标初值 / 非有限穿透族两件闭环；T0=0（八组余量 0 不硬凑），WebSearch 0/3。
> **R53（2026-11-20）**：16 新件（Device 3 / Algo 3 / MathData 3 / Base 2 / Process 4 / Motion 1）+ 4 件 P0 返修 v1.0.1；总库 945→**961**，SFT 946→**962**，机检 20/20 PASS；ROADMAP 三向差额回写 18 条（待办 52→34）；P0 链：判定保持族 / 有限性闸 Inf 差判 / 定时器相位闸 / 热模型量纲四族闭环；T0=0（八组余量 0 不硬凑），WebSearch 0/3。

> **Round 52（2026-11-20）：四批 20 件收口 + ValveSeatLeakWatch 严重缺陷返修 + 环窗回归族治理收官**——registry 925→**945**（v2.44.0，counts Base 106/MathData 212/Algo 112/Device 175/Motion 106/Process 234），20 新件 4 批 × 5 单调用按序完成零拒单；Base 4（BitCountOnes/PriorityEncodeWord/SchmittTriggerGap/EdgeIntervalMeter）· MathData 2（WrapIndexNeg 环窗下标归正/LogDomainNormalize 对数域归一）· Algo 5（ZnTune/AdaptiveDeadbandZone/DerivativeNoiseWeight/ControlOutputSlewWatch/PidParamDriftAudit）· Device 4（BrakeResistorThermal/压力开关抖动/脉冲丢失/电伴热四象限）· Motion 3（jerk 钳位/回零重复性/软限位预测）· Process 2（补水定量加药/晶粒分箱）；JSONL 926→**946**（badjson=0）；机检 **22/22 PASS fail=0**；返修 ValveSeatLeakWatch v1.0.1（环窗 X 用头游标致斜率符号翻转→时间序遍历）· MoveResumeSeg v1.0.2（fStartRst 标 reserved，逻辑零变更）；编码自纠 5 处；专家进化 +10 条（PLC R200~R204 / 总监 R205~R209）；总库 **v2.44.0 / 945 件 / 9.45%**（距 1000 差 55，500 里程碑已超额 +445）。

> **Round 50（2026-11-20）：R49 二十件收口 + 固化批次 FB-50 + 终审 5 抽挂账 R51**——registry 885→**905**（v2.42.0，counts Base 102/MathData 208/Algo 107/Device 170/Motion 103/Process 215），20 新件注册（function_tags 含来源标签），5 返修件升 v1.0.1；JSONL 886→**906**（badjson=0）；机检 **25/25 PASS fail=0**；编码自纠 10 处；**固化批次 FB-50（第 10 轮阈值触发）**：PLC 线 FB50-1~4 / 总监线 FB50-D1~D4 追加合并进两本 skills 规范文件；终审 5 抽 1 严重（RulEstimator 环窗乱序回归）2 中 2 PASS，全部挂账 R51（无人值守轮不做行为变更）；专家进化 +10 条（PLC R336~R340 / 总监 R341~R345），未固化轮次清零；总库 **v2.42.0 / 905 件 / 8.05%**（距 1000 差 95，500 里程碑已超额 +405）。
>
> **Round 49（2026-11-20）：零检索轮 20 件——四元数/几何均值原子 + 脉冲·节拍·屏障基础层 + 回路诊断与 RUL 算法 + 设备健康建档 + 运动恢复/前馈辨识/软限位审计 20 件**——DL_MathData 2（QuatRotateVec 四元数旋转 / GeoMeanCalc 对数域几何均值）、DL_Base 4（HeartbeatGen / PulseSeqVerify / StepTimeRecorder / CycleBarrierGate）、DL_Algo 5（SignalReconstruct 外插重建 / LoopSignGuard 皮尔逊判向 / ExtremumSeekCtrl 同步解调极值搜索 / LoopCoupleDetect 激励期互相关 / RulEstimator 四特征 HI 剩余寿命）、DL_Device 3（ValveSeatLeakWatch / CylStrokeTimeBank / CaseErectFaultSeq）、DL_Motion 5（MoveResumeSeg / VelFfGainIdent / SoftLimitCfgAudit / AxisLubeDistTrig / BrakeWearAccum）、DL_Process 1（RoomTempClassify）；合计 3,448 行，机检 20/20 PASS fail=0；批次 4×5 单调用按序完成，零拒单；R48 五抽终审 1 中 4 轻全挂账（LookaheadVelPlanner 回溯步邻段口径 → R50 P0）；专家进化 +10 条（PLC R325~R329 / 总监 R330~R334）；总库 **v2.41.0 / 885 件**。
>
> **Round 17（2026-11-16）：T0 纯函数第 4 轮——对数/dB + TIME/TOD + 精度/饱和 + LWORD 64 位域 20 件**——批1 对数/dB（DL_MathData 5：LogEx / LogBaseEx / AmpDbToRatio / RatioToAmpDb / PwrDbToRatio，20/10 因子严格分型、功率型硬限 380 dB 按 REAL 域可表性反算）、批2 TIME/TOD（5：TimeToDintMs / DintMsToTime / TimeToLrealSec / LrealSecToTime / TodToDintMs，先判后算 + DINT→TIME 无上域闸论证留档）、批3 精度/饱和（6：DintToRealChk / UdintToRealChk / LintToDintSat / RealToLintSat / LrealToLintSat / LwordToLrealChk，2^24 与 2^53 精度告警、升位比较、TRUNC 向零、下界 −MAX−1 计算式）、批4 LWORD 64 位域（DL_Base 4 + DL_MathData 1：Shl/ShrLwordEx 超宽置零、Rol/RorLwordEx MOD 64 归一）；合计 1,481 行，机检 16 规则 20/20 PASS fail=0；码位信息级 `01E8`~`020F`（撞车改判 `0210`/`0211`/`021B`/`021D`/`021E`）、故障级 `02CA`~`0305`；**收口实测发现改判落点仍与存量撞车 7 组（0201/0202/0208/0210/0211/021B/021D/021E 交叉），已列明 R18 改判专项方案并立新红线 R61「码位游标注册表实测」**；终审 20/20 件级零缺陷 PASS；总库 v2.6.0。
> **Round 18（2026-11-16）：场景件第 5 轮——基础整形 / 标定插值 / 控制补偿 / 设备 OOP / 运动保护 / 换产时序 20 件**——DL_Base 4（EdgeDivider / FirstOutLatch / PulseStretch / BitSegmentBlockMove）、DL_MathData 4（AffineTransformPoint / CpkIndex / Crc16Ccitt / InterpolateTable2D）、DL_Algo 4（BumplessTransfer / GainScheduler / NotchFilter / ThermalI2tModel）、DL_Device 3（I_DL_Gripper + ParallelGripper / SsrHeaterDrive）、DL_Motion 3（AxisFollowingErrorMonitor / AxisSynchronizedStop / BacklashCompensator）、DL_Process 2（ChangeoverSequence / DowntimeClassifier）；合计 3,709 行，机检 16 规则 20/20 PASS（4 处 E_DL_Ne107Status 跨文件属主按 R70 裁定为误报）；**R17 改判专项完成**（8 码改判 022D~0234，5 文件升 v1.0.1）；码位信息级 `0235`~`0244`、故障级 `0306`~`0314`；**R18 终审 6 件抽检命中 3 件缺陷并全部修复**（CRC 空帧 UINT 下溢越界 / 换型失能路径漏清放行镜像 / 夹爪 Close 形参静默丢弃），见新红线 R66~R74；总库 **v2.7.0 / 304 件**。
> **Round 19（2026-11-16）：Level 0 补位 + 控制律/设备健康/运动/工艺 20 件**——DL_Base 1（BitShiftRegister）、DL_MathData 5（DintMsToTod / TimeRatioCalc / RatioToPwrDb / LintToUdintSat / ModbusRtuFrameCheck）、DL_Algo 4（FlowSqrtExtract / RatioController / LeadLagCompensator / AutoTuneRelay）、DL_Device 4（DeviceHealthArbiter / ProfinetAlarmDiag / EscChuckCurrentMonitor / DeviceParamWrite）、DL_Motion 4（ExternalEncoderScaler / CamPhaseTrim / FilmWebCenter / WindingLayerCounter）、DL_Process 2（DrumLevelThreeElem / VacCupRingCtrl）；合计 4,484 行，机检 20/20 PASS；**R19 终审 6 件抽检命中 2 件缺陷并全部修复**（BitShiftRegister 右移溢出位 / DrumLevelThreeElem 水位项正反馈，均升 v1.0.1）；码位台账游标更新见各子库 VERSION.md；总库 **v2.8.0 / 324 件**。
> **Round 20（2026-11-16）：T0 日历/时间族 + 域转换补充 + 字节序 + 同步族 20 件（T0 快车道零检索）**——DL_MathData 18（日历/纪元族 4：DtToDintEpoch / DintEpochToDt / DateToDintDays / DintDaysToDate，秒域与天数域双向、Y2038 上域饱和与不饱和两策略分立；时间算术 3：TodAddWrap / TodDiffWrap / TimeAbsSat，回绕归一禁 MOD 走条件加减、−MAX−1 单值闸；日期算术 2：DateAddDays / DateDiffDays，溢出用减法预判双向方向判据；域转换 6：UdintToLintChk / WordToIntSat / DwordToIntSat / LwordToLintSat / BcdToByte / ByteToBcd；字节序 1：SwapBytes64，拆半区复用 SwapBytes32 组合；字符串化 2：DintToStringTrim / LrealToStringTrim）、DL_Base 2（LeapYearChk 闰年原子 / SemaMutex 三态互斥 + 超时强制归还）；合计 2,189 行，机检 16 规则 20/20 PASS fail=0；码位信息级 `040C`~`0433`、故障级 `0330`~`036B`，全库唯一性求差断言零重叠，游标推进至 **信息 `0434` / 故障 `036C`**；**R20 终审 8 件高风险抽样命中 2 件并修复**（LrealToStringTrim 无穷幅值阈值落在 LREAL 域内致极大有限值误判 `Inf+`〔中等·逻辑，改双判据〕/ SemaMutex 过渡态「本拍即回」跨拍语义表述不精确〔注释级〕，均升 v1.0.1，对外引脚零变更）；归档 `_Staging_Raw/2026-11-16/BATTLE_REPORT_R20.md`；总库 **v2.9.0 / 344 件**，Phase 1 今日 140/200。
> **Round 22（2026-11-16）：结构补位轮——轴侧安全层开层 / 过程单元保护顺控 / 定宽字段族 / 位串搜索·测频 20 件**——DL_MathData 3（IntToFixedField 负域取模防 DINT 最小值 / FixedFieldToInt 前导剥离+非法字符定位+负域累乘 / LrealToFixedField 禁 `LREAL_TO_STRING`+R79 精确非有限判据，T2-1 LGF「数值→定宽字段」子族 ✔ 收口）、DL_Base 2（FirstSetBit 位串搜索轴：高低位优先 + 8/16/32/64 位宽 + 常量掩码避 `SHL(x,64)`；FrequencyMeasure 门时测频：±1/tGateTime 不确定度显式声明）、DL_Algo 2（CrossLimitSelect 燃烧双交叉限幅 / ExcessAirTrim 氧量修正）、DL_Device 4（SlitValveInterlock 真空闸阀互斥互锁 / PressureReliefMonitor 安全阀起跳台账 / SteamTrapMonitor 温差三判据冷态冻结 / LevelRadarValidate 回波四判据仲裁）、DL_Motion 5（**轴侧安全层开层**：AxisBrakeSeq 抱闸时序两序、VirtualMasterAxis 主值源 LREAL 精度门冻结、MotionCmdQueue PLCopen Buffered 排队、CamTableValidate 四判据全掩码、AxisInPosMonitor bSettled 出窗即清）、DL_Process 4（CompressorSurgeGuard 防喘振 / ColumnDpCtrl 压差增量控制防冲塔 / InertPurgeSeq 氮气置换一相一只 TON / BatchTransferSeq 阀到位才启泵）；合计 6,618 行，机检（check_r22.py）20/20 PASS fail=0；registry 364→**384**（v2.11.0，counts 73/148/38/61/30/34），JSONL 384 条全 sha256 MATCH（本轮修复 2 件历史 LF/CRLF 口径漂移后全量复验），R22 码位 100 槽跨文件 CLASH=NONE，游标推进至 0001 `0466`/`03B7`、0002 CC=`2D`、0003 `017A`/`0348`、0004 `01DF`/`02F9`、0005 `01E2`/`0317`；**R22 终审 10 件高风险抽样命中 4 件轻微缺陷并全部修复升 v1.0.1**（MotionCmdQueue 清队竞态 eWaitDone 挂死 / VirtualMasterAxis eFault 态复积分 / AxisBrakeSeq 注释-实现不符 / BatchTransferSeq 超时分支漏 bError），1 件中等安全相关挂账 R23（BatchTransferSeq 中止先停泵后关阀缺物理时序）；源矩阵 T1-3 ◐→✔ 收口（总监签字）、T2-1 Converter 定宽字段子族 ✔ 收口，其余 13 行备注回写；归档 `_Staging_Raw/2026-11-16/BATTLE_REPORT_R22.md`；总库 **v2.11.0 / 384 件**，Phase 1 今日 **198/200（99.0%）**，距 500 冲刺差 **116 件**。
> **Round 23（2026-11-17）：行业纵深轮——焓湿图原子族开族 / NE107 多源健康聚合 / 锂电·光伏·半导体·公用工程·锅炉·暖通工艺站 20 件**——DL_Algo 5（**T1-2 OSCAT Building 焓湿图族开族收口**：VaporPressureSat 饱和压族属主 / HumidityRatioCalc / WetBulbTempCalc / RhFromDewPoint / MixAirStateCalc，Magnus-Tetens 常数属主裁定并回写 DewPointCalc·HumidAirEnthalpy 属主转移声明）、DL_Device 6（HealthAggregator **T2-8 NE107 多源聚合落地** / OvenDoorInterlock / ChamberGateValve / RobotGripVerify / FilterDpMonitor / TankN2BlanketCtrl）、DL_Process 7（ElectrolyteDosingSeq ISA-88 节拍链 / NailMachineSeq / LamHeaterZoneSync / SteamCondensatePot / AirCompDutyN2 / BoilerThreeElement 三冲量 / HumidityOverride）、DL_Motion 2（WaferCountAxis / BagFeedDancerSync）；合计 3,754 行；`FB_DL_BatchTransferSeq` 升 v1.0.2（中止两段化，R22 挂账闭合）；registry 384→**404**（v2.12.0，counts 73/148/43/67/32/41），JSONL **404 条全量 sha256 MATCH**，CLASH=NONE，机检 fail=12 全为 E_DL_Ne107Status 属主误报豁免（属主 I_DL_DeviceHealth.st）；**R23 终审 8 件高风险定向抽查：2 PASS / 4 件轻微当场修升 v1.0.1 / 2 件严重挂账 R24**（WetBulb 定点迭代结构性发散 + γ 常数千倍量纲错位；TankN2 分界迟滞回差），主控收口另拦下 2 处编码侧漏（未声明标识符 fSteamFlow、注释省略号占位）；子库版本 DL_Algo v1.11.0 / DL_Device v0.13.0 / DL_Process v0.13.0 / DL_Motion v0.13.0；总库 **v2.12.0 / 404 件**，距 500 冲刺差 **96 件**。

> **Round 25（2026-11-17）：暖通深度 + 洁净室/锂电/光伏工艺 20 件（4 批）**——DL_MathData 1（Affine2DInvert 仿射逆映射，仿射「合成-应用-逆」三元闭环齐备）、DL_Algo 4（ParticleCounterStat 洁净室 ISO 14644-1 等级 / CoolingTowerApproachCalc 逼近度与换台建议 / DuctStaticReset 静压重置 / DewpointReset 露点重置）、DL_Device 4（InverterGridSync 并网四窗许可 / HeatPumpDefrost 三条件除霜 / VavBoxCtrl 压力无关 VAV / WaferMapping 晶圆盒 Mapping）、DL_Motion 2（StackingAlignCtrl CCD 纠偏 / LabelApplySync 贴标同步）、DL_Process 9（RoomClimateCtrl 双回路耦合 + 防结露联锁 / WeightCheckReject / CasePackerPattern / BatteryTestCycler 工步机 / PalletizerLayerSeq 层排布 / SplicerAutoJoint 接膜 / ChillerSeqMgr 群控 / FormationChannelMgr 通道调度 / SolarStringGroundFault 绝缘阻抗）；合计 **7,097 行**（终审修复后 7,174 行），机检 19/20 PASS（1 项为纯函数件 4 槽码位口径误报，已裁定合法）；**R25 终审定审 8 件定向推演 → 4 PASS / 3 修 / 1 挂账**，另 3 件由同批交叉扫描命中同类缺陷一并修，**6 件升 v1.0.1**（PalletizerLayerSeq 旋转层平移量越界 + bPalletDone 同拍自撤 / SolarStringGroundFault 预警阈值越过上限哨兵 / VavBoxCtrl NaN 下限当安全值 / RoomClimateCtrl 失能沿 100% 冷却 / BatteryTestCycler eFault 无 CASE 标签致真因码被兜底覆盖 / SplicerAutoJoint 同步相缺前置消失退出），**1 项挂账**（SplicerAutoJoint 同步相无自有超时，下轮新增 tSyncMax，MINOR）+ **1 项批次共性挂账**（6 件 eFault 枚举无 CASE 标签，下轮统一修并新增机检规则）；registry 424→**444**（v2.14.0，counts 73/152/48/76/38/57），JSONL **444 条全量 sha256 MATCH**（修复 6 行重注入后全量复验），码位 CLASH=NONE，游标 0001 `0471`/`03BF`、0002 下一 CC `0x37`、0003 `0198`/`0375`、0004 `01EF`/`0312`、0005 `0412`/`035D`；总库 **v2.14.0 / 444 件**，距 500 冲刺差 **56 件**。
> **Round 21（2026-11-16）：数学安全原子 + LWORD 位域/校验 + 文本序列化 + 守卫 FB 20 件**——DL_MathData 15：批1 数学安全原子 5（`FC_DL_ModPos` 非负取模 / `FC_DL_DivLrealSafe` 除法唯一出口 / `FC_DL_QuantizeStep` 量化步长 / `FC_DL_PolyEvalHorner` Horner 多项式 / `FC_DL_WrapAngleDeg` 角度回绕）、批2 LWORD 位域+校验 5（`FC_DL_LwordBitFieldExtract`/`Insert`、`FC_DL_LwordBitCount` 汉明重、**`FC_DL_Crc16Generic` 参数化 CRC-16 一张实现覆盖任意从站**、`FC_DL_ChecksumSum8` 累加和，挂 T2-1 LGF Bit Logic / Data Handling / Converter 三子族）、批3 文本序列化 5（`FC_DL_StringToDint` 整数字符串严格解析、`FC_DL_DwordToHexString`、`FC_DL_ArraySumLreal`、`FC_DL_TimeToHmsString`、`FC_DL_DateToIsoString` ISO 日期文本 + 回代自校验）；DL_Base 4 批守卫 FB 5（`FB_DL_MinOnOffGuard` 最短运行/停止双守卫、`FB_DL_SignalChangeCounter`、`FB_DL_SamplingTrigger`、`FB_DL_SignalFrozenDetect`、`FB_DL_PulseWidthFilter` 双侧确认脉宽守恒）；合计 **2,802 行**，机检（`_Staging_Raw/2026-11-16/check_r21.py`，嵌套注释判定升级为**非贪婪成对剥离法**）**20/20 PASS fail=0**；registry 344→**364**（v2.10.0，counts 71/145/36/57/25/30），JSONL 364 条全 sha256 MATCH、码位 CLASH=NONE，游标推进至 **信息 `045C` / 故障 `03A8`**；**R21 终审 7 件定向抽查命中 3 件并全部修复**（`FC_DL_DateToIsoString` 年序判据末项除数误用 146097 致 **2000-02-29 等世纪闰日误判 0397 故障**〔严重〕/ `FC_DL_Crc16Generic` 空帧分支漏输出反射〔中等〕/ `FC_DL_PulseWidthFilter` `bReset` 电平清零与引脚注释「上升沿」不符〔轻微〕，另 `FC_DL_StringToDint` 溢出未写 `nErrPos`〔轻微〕一并修，四件升 v1.0.1，对外引脚零变更）；归档 `_Staging_Raw/2026-11-16/BATTLE_REPORT_R21.md`；总库 **v2.10.0 / 364 件**，Phase 1 今日 **178/200（89.0%）**，距 500 冲刺差 **136 件**。
>
> **Round 16（2026-11-16）：T0 变体线开线——20 件防御性包装全部落 DL_MathData（1,436 行，FC_ 纯函数，输出契约 eErr/bError/bValid 三件套）**——批1 饱和转换 LrealToRealSat/LrealToDintSat/RealToUdintSat/RealToUintSat/RealToByteSat、批2 整数+BCD DintToUintSat/UdintToDintChk/LintToLrealChk/BcdToUdint/UdintToBcd、批3 泛型选择 SelEx/Mux2Ex/Mux4Ex/MinEx/MaxEx、批4 LIMIT+TIME LimitEx/TimeAddSat/TimeSubSat/TimeScaleSat/TimeDivChk；机检 16 规则全 PASS fail=0；码位信息级 01C0~01E7（40 码）、故障级 028E~02C9（60 码）经源码反算回写全库唯一；终审抽查 8 件零缺陷 PASS；总库 v2.5.0。
>
> **Round 15: T0 fast-lane closure — absolute/sin/cos/asin/acos/atan/atan2, exp/pow, trunc/floor/ceil and eight string factories (len/left/right/concat/insert/delete/find/replace-at)** — 20 components added (~1,966 lines), taking the library to 244 components; all seven T0 source-matrix groups now closed; 16-rule machine check 20/20 PASS; error-code layer normalised to the library convention (UDINT + 16#0001_xxxx) before registration.
>
> **R14（2026-11-16）**：T0 快车道 20 件入库——SR/RS 双稳态、R/F 沿检测、TON/TOF/TP/RTO、CTU/CTD/CTUD、SHL/SHR/ROL/ROR（DL_Base +15）；SQRT/LN/TAN/ROUND/MID 防御包装（DL_MathData +5）；码位信息级 `014D`~`015D`、故障级 `0226`~`022B`；机检 fail=0；总库 v2.3.0。
>
> **⚠️ 未经编译器验证 / NOT COMPILER-VERIFIED**：本库全部 384 件组件**未经真实 CODESYS / TwinCAT / InoProShop 编译器编译验证**（连续 18 轮悬置，本机无对应环境，已实测探测）。替代验证方案（16 项静态机检全库回归 + 总监独立验算 + 人工时序推演 + IF/END_IF 配平）与**无法替代的风险清单**详见 `LIBRARY_MANUAL.md` 第十五节「R13 专项：未经编译验证声明与替代验证方案」。生产导入前请先在目标平台空工程做一次全量编译。
>
> **Round 13：NE107 设备健康契约 + 电表读侧契约 + Modbus 电表 + 阀门黏滞诊断 + AHU 风阀卡滞三分类 + 泵汽蚀守卫 + 位串整串旋转 + 掩码比较 + CRC-8 + 带校验字符串解析 + 定宽字段 + 3×3 矩阵求逆 + 换热器污垢趋势 + 被动回零监听 + 旋盖扭矩 NG 判别 + ESC 氦检漏 + seasoning 台账 + 釜夹套温差约束**——新增 18 个组件（DL_Device 6 ｜ DL_MathData 4 ｜ DL_Process 4 ｜ DL_Base 2 ｜ DL_Algo 1 ｜ DL_Motion 1，合计 7,966 行），全库 204 件 / 62,667 行；终审 **18/18 PASS**（缺陷 14 处：严重/功能失效级 2 ｜ 中等 9 ｜ 提示 3 ｜ 文档级 1，最重为 `FB_DL_EscHeLeakCheck` 稳压延长窗全程未计时与 `FB_DL_InterlockMatrix` 禁用期吞复位沿，均为修复后 PASS）；**10 件升 v1.0.1**（8 新件 + 2 存量 R39 修复）；R39 存量专案另裁定 3 处 FAIL 误报留档不修；新开子族 **NE107 诊断族 / LGF Matrix 子族 / LGF CRC8 子族**。
>
> **Round 13: NE107 device-health contract, power-meter read-side contract, Modbus power meter, valve stiction diagnosis, AHU damper three-class stuck diagnosis, pump cavitation guard, cross-word bit-string rotation, mask compare, CRC-8, validated string parsing, fixed-width fields, 3x3 matrix inverse, fouling resistance trend, passive homing monitor, capper torque NG verdicts, ESC helium leak check, chamber seasoning ledger and reactor jacket delta-T constraint** — 18 components added (7,966 lines), taking the library to 204 components / 62,667 lines; final review 18/18 PASS (14 defects fixed, the heaviest being a stabilisation-extension window that never timed in the ESC leak check and a reset edge swallowed while disabled in the interlock matrix, both PASS-after-fix); 10 files bumped to v1.0.1 (8 new + 2 legacy R39 fixes); 3 residual R39 machine-check hits adjudicated as false positives and retained with rationale.
> **Round 12：跨字位流窗口读写 + 开闭区间成员判定 + 位图变化监视 + 字符串全替换与报文分词流 + 数组逐项比对 + 太阳位置 + Modbus 异常帧 + 水比焓 + 阀特性补偿 + 端口诊断看板 + 参数回读核对 + 电表累计与需量 + 真空计双表融合 + 两轴直线插补 + ISA-88 相底座 + 温控器轮询采集行**——新增 18 个组件（DL_MathData 5 ｜ DL_Base 4 ｜ DL_Device 4 ｜ DL_Algo 2 ｜ DL_Process 2 ｜ DL_Motion 1，合计 5,880 行），全库 186 件 / 54,701 行；终审 **PASS 8 件 + 修复后 PASS 10 件**（缺陷 15 条：致命 3 / 严重 5 / 中等 3 / 注释级 4，`FB_DL_StringReplaceAll` 致命截断未置位、`FB_DL_BatchPhaseBase` 单步超时跨步累加、`FB_DL_VacuumGaugeMux` 掉线表值直发布三条为致命级）；新增范式 **R37~R44** 八条入册。
> **Round 12: cross-word bit windows, interval membership, bitmap change watch, string replace-all and token stream, array diff, solar position, Modbus exception frames, water enthalpy, valve characteristic, port diagnostic board, parameter readback verify, energy meter with demand, dual vacuum gauge fusion, two-axis linear interpolation, ISA-88 phase base and a polled temperature bank** — 18 components added (5,880 lines), taking the library to 186 components / 54,701 lines; final review PASS for 8 files and PASS-after-fix for 10 (15 defects: 3 fatal, 5 severe, 3 medium, 4 comment-level); eight new paradigms R37 to R44 registered.
> **Round 10：Level 0 三组横向补强 + 信号发生族 + 卷绕/空气密度工艺算法 + RFID 契约-实现对 + 现场总线诊断双件 + 排线轴工步 + 通用拾放工站**——新增 16 个组件（DL_Base 3 ｜ DL_MathData 3 ｜ DL_Algo 4 ｜ DL_Device 4 ｜ DL_Motion 1 ｜ DL_Process 1，送审 5,385 行 / 修后 5,528 行）；终审 **PASS with fixes**：缺陷 17 条（**致命 2**——`FB_DL_PickAndPlaceStation` 主 CASE 漏 `eExecute` 标签被 ELSE 兜底锁故障致九步序永不执行（D-01）、`FB_DL_WindingTraverse` 待机态每拍清方向量致排线位移恒 0（D-02）），**8 件升 v1.0.1**，JSONL 8 条字节级再同步（累计 152 条）；两个源矩阵行首次开组（**T2-6 Rockwell AOI**、**T1-7 PLCnext Community**）；新范式 **R31「枚举→CASE 双向映射完备性」** / **R32「内部状态量写入点全拍排序审计」** 入册。
> **Round 10: Level 0 three-group extension, signal generators, winding/air-density process algorithms, RFID contract-implementation pair, fieldbus diagnostics duo, traverse axis step, and a generic pick-and-place station** — 16 components added (5,385 lines submitted / 5,528 after fixes); final review PASS with fixes: 17 defects including 2 fatal (a missing `eExecute` CASE label making the pick-and-place station unreachable on all three platforms, and a direction value cleared every scan leaving the traverse axis motionless); 8 files bumped to v1.0.1; two source-matrix rows opened for the first time (T2-6 Rockwell AOI, T1-7 PLCnext Community); new paradigms R31 (enum-to-CASE total mapping) and R32 (per-scan write-order audit of internal state).
> **Round 09：Level 0 回补（LGF Data Handling / Comparator / Converter / Bit Logic / Date and Timer / Counter 六组横向铺量）+ 运动叠加补偿 + 开环步进族契约-实现对 + Modbus 轮询调度抽象 + 安灯四级仲裁**——新增 16 个组件（DL_MathData 6 ｜ DL_Base 5 ｜ DL_Device 2 ｜ DL_Motion 1 ｜ DL_Process 2，合计 5,051 行）；终审 **PASS with fixes**：缺陷 13 条（**致命 2**——`FC_DL_BinarySearchLReal` 缺 uErrorId 声明三平台编译必败（D-01）、`FB_DL_PulseDirStepper` eDecel 终态死锁（D-02）），**码位改判 6 件 15 处**（编码者"未占用"自证全部推翻），终审后全库跨文件重叠 = 0；全库嵌套注释风险清零（5 处头注释定界符修复，存量 Crc16Modbus → v1.0.1）；新范式 R28 注释不可嵌套 / R29 赋值目标声明性检查 / R30 码位自证循环禁令入册。
> **Round 09: Level 0 refill across six LGF groups, superimposed motion, open-loop stepper pair, Modbus polling scheduler abstraction and four-level Andon arbitration** — 16 components added (5,051 lines); final review PASS with fixes: 13 defects including 2 fatal (missing output declaration blocking compilation on all three platforms, and an unreachable decel exit dead-locking the state machine); 15 fault-code collisions re-adjudicated across 6 files; new paradigms R28/R29/R30 registered.

---

## 一、项目定位 / What This Is

道莅（Daoli）工业自动化标准代码库是一套**面向万级规模的 IEC 61131-3 结构化文本（ST）组件库**，目标是把工业现场反复重写的「消抖、取沿、标定、滤波、校验、设备抽象、状态机」沉淀成一套可复用、可审计、可跨平台编译的企业核心数字资产，并同步产出用于工业 AI 编程大模型微调的高质量语料。

This is a **library of IEC 61131-3 Structured Text components designed to scale to 10,000 units**. It turns the code that field engineers rewrite on every project — debouncing, edge detection, scaling, filtering, checksums, device abstraction, state machines — into portable, auditable, reusable assets, and ships a curated SFT corpus for industrial code LLMs.

### 核心承诺 / Guarantees

| 承诺 / Commitment | 判定口径 / How It Is Enforced |
|---|---|
| **零全局耦合** / Zero global coupling | 全文不出现全局变量表访问、外部变量引用与物理 IO 地址；外部数据一律经引脚或 `I_DL_` 接口注入 |
| **三平台同源编译** / Compiles on three platforms | 只用 `Standard.library` 与 IEC 标准类型；CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop 直接编译 |
| **防御性优先** / Defensive by default | 除法防零、数组双检、浮点容差、循环防死锁，四类保护是入库门槛而非加分项 |
| **无魔法数** / No magic numbers | 阈值、限幅、超时一律提为 `VAR CONSTANT` 或输入引脚 |
| **文档代码同源** / Docs ship with code | 代码入库必须同步 `VERSION.md` / `MANUAL_*.md` / `CHANGELOG.md` / `INDEX_REGISTRY.json` |
| **100% 中英双语注释** / Bilingual comments | 每个声明行同行中文物理意义 + 英文术语 + 工程单位 |

---

## 二、目录结构 / Repository Layout

```text
C:\Library\
├── README.md                     # 总览：定位、结构、快速开始、许可证 / Overview and quick start
├── CHANGELOG.md                  # 总库语义化版本演进历史 / Library-wide SemVer history
├── LIBRARY_MANUAL.md             # 总手册：跨子库调用规范与故障码总表 / Cross-sublibrary manual
├── ROADMAP.md                    # 100 项 Phase 1 清单与 10,000 项目标路线图 / Roadmap
├── AGENT_EVOLUTION_LOG.md        # 每轮复盘、编码范式沉淀与吞吐优化 / Retrospectives and evolution notes
├── INDEX_REGISTRY.json           # 组件索引：名称、子库、类型、路径、标签、复杂度（机读）
├── OPEN_SOURCE_SHOWCASE.md       # 明星组件与技术推广文案 / Star components for community posts
│
├── _Staging_Raw\                 # 暂存区：按日期存放需求规格、情报笔记与战报（永不作为交付物）
│   └── 2026-11-14\
│       ├── ROUND_PLAN.md         # 第一轮需求规格书 / Round 1 requirements spec
│       ├── RAW_NOTES.md          # 第一轮狩猎情报与协议台账 / Round 1 research notes
│       ├── BATTLE_REPORT.md      # 第一轮战报 / Round 1 battle report
│       ├── ROUND_PLAN_R2.md      # 第二轮需求规格书 / Round 2 requirements spec
│       ├── RAW_NOTES_R2.md       # 第二轮情报与协议台账 / Round 2 research notes
│       └── BATTLE_REPORT_R2.md   # 第二轮战报 / Round 2 battle report
│
├── _AI_Training_Dataset\         # AI 语料：instruction / architecture_thought / output 三元组（JSONL）
│   └── daoli_st_sft_dataset.jsonl
│
├── DL_Base\                      # 【Level 0】基础逻辑、时序、诊断、安全联锁、事件计数与公差/限值/位段/月窗/年窗类库（40，Phase 1 20 项收口 + R5 补强 2 + R7 计数器组 2 + R9 四组深化 5 + R10 三组补强 3 + R11 年窗/环形回绕 2 + R12 跨字位段/区间成员/位图变化 4 + R13 位串旋转/掩码比较 2）
│   ├── VERSION.md
│   ├── MANUAL_DL_Base.md
│   └── FB_DL_*.st / FC_DL_*.st
│
├── DL_MathData\                  # 【Level 0】数学运算、数据结构与协议解析类库（42 / 20 ✅ 收口扩容：R9 元素 FIFO / 搜索 / 温标 / BCD 族 + R10 LGF Math 极值/根/阶乘 + R11 区间/几何/随机/分位 + R12 字符串/数组比对/太阳位置/异常帧 5 + R13 CRC-8/严格解析/定宽字段/矩阵求逆 4）
│   ├── VERSION.md
│   ├── MANUAL_DL_MathData.md
│   └── FB_DL_*.st / FC_DL_*.st
│
├── DL_Algo\                      # 【Level 1】工业控制算法类库（28，Level 1 首库 16 项 + R5/R6 补强 2 + R8 峰值/步进 2 + R10 信号发生/卷绕/空气密度 4 + R11 R2R 批级微调 1 + R12 阀特性/水焓 2 + R13 换热器污垢趋势 1，依赖 Level 0）
│   ├── VERSION.md
│   ├── MANUAL_DL_Algo.md
│   └── FB_DL_*.st / FC_DL_*.st
│
├── DL_Device\                    # 【Level 1】标准物理设备抽象与 OOP 接口类库（50 开库：气缸/电机三型/变频器/阀门三类/真空/变送器/温控区 + R7 十件套 + R8 安灯塔 + R9 步进 + R10 RFID 契约-实现对与总线诊断双件 + R11 端口诊断/段解码/NTC 巡检/辊距补偿 + R12 端口看板/参数核对/电表需量/真空融合 + R13 NE107 健康契约/电表契约与实现/阀黏滞/AHU 卡滞/泵汽蚀）
│   ├── VERSION.md
│   ├── MANUAL_DL_Device.md
│   └── I_DL_*.st / FB_DL_*.st
│
├── DL_Motion\                    # 【Level 1】运动控制 OOP 封装类库（18 开库：PLCopen 轴状态机 + 点动 + 回零 + 相对/速度定位 + 软限位围栏 + R8 同步耦合族 + R9 叠加补偿 + R10 排线工步 + R11 卷绕张力 + R12 两轴直线插补 + R13 被动回零旁路监听，基于 I_DL_MotionAxis）
│   ├── VERSION.md
│   ├── MANUAL_DL_Motion.md
│   └── I_DL_*.st / FB_DL_*.st
│
└── DL_Process\                   # 【Level 2】行业工艺与通用工站模板库（26 开库：PackML 状态机 + 命令解码器 + 行业池 + R8 六件 + R9 调度抽象/安灯 + R10 通用拾放工站 + R11 工站四件套 + R12 相底座/温控采集行 + R13 旋盖扭矩/氦检漏/seasoning 台账/夹套温差，依赖 Level 0~1）
    ├── VERSION.md
    ├── MANUAL_DL_Process.md
    └── FB_DL_*.st
```

**依赖方向单向**：Level 0 → Level 1 → Level 2。低层不得引用高层；`DL_Algo` 及以上不得内联实现本应在 `DL_Base` / `DL_MathData` 的能力。

---

## 三、快速开始 / Quick Start

### 3.1 导入 / Import

1. 在 CODESYS / TwinCAT 3 / InoProShop 中新建或打开工程。
2. 按依赖顺序导入：`DL_Base` → `DL_MathData` → `DL_Algo` → `DL_Device` → `DL_Motion` → `DL_Process`（Level 1 仅依赖 Level 0；子库内部 `FB_DL_CascadePid` / `FB_DL_SmithPredictor` 依赖 `FB_DL_PidController`，`FB_DL_PneumaticCylinder` 依赖 `FB_DL_SignalDebounce`，`FB_DL_HeatCoolZone` 依赖 `FB_DL_PidController` / `FB_DL_PwmDutyController`，`FB_DL_WindingTensionCtrl` 依赖 `FB_DL_PidController` / `FC_DL_CoilDiameterCalc`，随子库整体导入即可）。
3. 每个 `.st` 文件对应一个 POU，文件名即 POU 名；`FB_DL_SignalDebounce.st` 同时包含 `E_DL_DebounceState` 枚举。
4. 无需任何厂商库；确认工程引用 `Standard.library` 即可。

### 3.2 第一个调用 / First Call

```iecst
PROGRAM PRG_Demo
VAR
    fbDebounce : FB_DL_SignalDebounce;   // 消抖实例 / Debounce instance
    bButtonRaw : BOOL;                   // 原始按钮输入 / Raw button input
    nPressCount: UDINT;                  // 按下次数 / Press count
END_VAR

(* 每周期无条件调用；只对消抖后的边沿计数 *)
fbDebounce(bRawInput := bButtonRaw, tRiseDelay := T#20MS, tFallDelay := T#20MS, bEnable := TRUE);

IF fbDebounce.bRiseEvent THEN
    nPressCount := nPressCount + 1;
END_IF
END_PROGRAM
```

### 3.3 命名速查 / Naming Cheat Sheet

| 前缀 / Prefix | 含义 / Meaning | 示例 / Example |
|---|---|---|
| `FB_DL_` | 功能块（带内部状态）/ Function block with state | `FB_DL_MovingAverage` |
| `FC_DL_` | 函数（无状态、有返回值）/ Stateless function | `FC_DL_LinearScale` |
| `I_DL_` | 接口 / Interface | `I_DL_Cylinder` |
| `ST_DL_` | 结构体 / Struct | `ST_DL_PidParams` |
| `E_DL_` | 枚举 / Enum | `E_DL_DebounceState` |
| `b` `n` `u` `f` `s` `t` `a` `st` `e` `fb` `i` | BOOL / 有符号 / 无符号 / 浮点 / 字符串 / 时间 / 数组 / 结构体 / 枚举 / FB 实例 / 接口引用 | `bEnable`、`tRiseDelay`、`afBuffer` |

---

## 四、当前交付清单 / Current Inventory

### DL_Base（40 项 · R12 跨字位段 / 区间成员 / 位图变化 + R13 位串旋转 / 掩码比较）

| 组件 / Component | 类型 | 一句话 / Summary |
|---|---|---|
| `FB_DL_SignalDebounce` | FB | 上升/下降延时独立可调的触点消抖，首扫零假边沿 |
| `FB_DL_DualEdgeTrig` | FB | 上升/下降/跳变三事件 + 饱和计数（v1.0.1 修复事件极性） |
| `FB_DL_ExtendedTimer` | FB | 四模式定时器：TON / TOF / TP / RTO，换模式即作废计时 |
| `FB_DL_AlarmManager` | FB | 16 通道三级优先仲裁 + 先到先得首出锁存 |
| `FB_DL_StepSequencer` | FB | 通用顺控步引擎：动作外置、逐步超时、单步调试 |
| `FB_DL_WatchdogMonitor` | FB | 心跳跳变间隔看门狗 + 跳变过快告警 |
| `FB_DL_PulseGenerator` | FB | 周期/占空比可调方波，占空比 0/1 退化为恒低/恒高 |
| `FB_DL_CycleTimeMeasure` | FB | 扫描周期统计（最近/最小/最大/平均），时间增量注入 |
| `FB_DL_RuntimeMeter` | FB | 运行分钟/小时 + 启动次数 + 保养到期预警 |
| `FB_DL_TwoHandSafety` | FB | 双手同步校验与防旁路：同步窗/释放窗/卡死三级判定（v1.2.0） |
| `FB_DL_InterlockMatrix` | FB | 16 路联锁汇总与首因追踪，复位挂起不清根因（v1.2.0） |
| `FB_DL_RedundantSwitch` | FB | 双通道冗余选择器：偏差确认、无扰切换、抖振锁定（v1.2.0） |
| `FB_DL_DutyStandbyRotation` | FB | 8 台泵/风机主备轮值均衡，先启后停 + 双向最小时长保护（v1.2.0） |
| `FC_DL_BitGet` | FC | 带索引校验的位提取 |
| `FC_DL_BitSet` | FC | 纯函数置位/清零 |
| `FC_DL_BitCount` | FC | Brian Kernighan 置位计数 |
| `FC_DL_PackBitsToWord` | FC | 16 路 BOOL → `WORD` |
| `FB_DL_UnpackWordToBits` | FB | `WORD` → 16 路 BOOL，带取反掩码与变化脉冲 |
| `FC_DL_GrayToBinary` | FC | 1~32 位格雷码解码 |
| `FC_DL_BinaryToGray` | FC | 格雷码编码（与前者严格互逆） |
| `FC_DL_DayOfWeekCalc` | FC | 年月日 → 星期几（ISO-8601 周一=1），Sakamoto clean-room + 闰年判定（v1.4.0） |
| `FB_DL_TimeWindowCheck` | FB | 每日时间窗判定：跨零点窗 + 星期使能表 + 开/闭沿单发（v1.4.0） |
| `FB_DL_EventCounter` | FB | 双向 DINT 事件计数器：预置装载、阈值比较每拍重算、回绕/饱和双模式，极值先判界后运算（v1.6.0） |
| `FB_DL_ModuloCounter` | FB | 取模工位索引计数器：条件加减法回绕（跨平台一致）、带校验跳步、双向同拍抵消（v1.6.0） |
| `FB_DL_ToleranceWindow` | FB | 公差窗口三态判定 + 迟滞回差防抖 + 双向越差单拍告警（v1.8.0） |
| `FC_DL_LimitClassify` | FC | 四阈值五档限值分档：闭区间贴线归严档 + 阈值序非法拒绝（v1.8.0） |
| `FC_DL_WordBitPack` | FC | WORD 位段参数化打包/解包：读-改-写原子语义，USINT 回绕安全判界（v1.8.0） |
| `FB_DL_MonthWindowCheck` | FB | 月内第 N 天/月末倒数窗判定：窗口截断不跨月 + 年度模式 + 闰年独立实现（v1.8.0） |
| `FB_DL_PresetCounterSat` | FB | 带饱和预设计数器：上下限钳位停走不回绕，批次/满载专用（v1.8.0） |
| `FC_DL_BitFieldExtract` | FC | DWORD 任意位段提取（偏移 + 宽度）：满宽走常量掩码规避 `SHL(x,32)`、越界双重拒绝、跨字按可用位截断（v1.9.0） |
| `FC_DL_WeekOfYearCalc` | FC | 年月日 → ISO-8601 周年/周序（Zeller 同余 + 周四归属法），跨年归属独立语义、闰年 1/2 月折算前置（v1.9.0） |
| `FB_DL_BidirectionalCounter` | FB | CTUD 全语义双向计数：加/减/装载/复位 + 双预设 + 饱和不回绕 + 加优先仲裁（v1.9.0） |
| `FB_DL_YearWindowCheck` | FB | 年粒度区间窗判定：跨年窗自动补周期 + 按年折叠重复（多年度一次配置）+ 整数日序数法零浮点 + 空窗组态拦截（v2.0.0） |
| `FB_DL_RolloverCounter` | FB | 环形回绕计数 + 净圈数：到顶回 0 / 到底回上限，比较赋值禁 `MOD`，圈数饱和不静默回绕，无预设比较（v2.0.0） |
| `FC_DL_BitArrayExtract` | FC | 跨字位流窗口提取：位窗可达 64 位并右对齐，同出生效掩码与截断后宽度；闸门顺序「字数→偏移→宽度→越界截断」，宽度 64 走满宽常量禁移位 64（v2.1.0） |
| `FC_DL_BitArrayInsert` | FC | 跨字位段原子写入：与提取件严格成对，窗口跨字先算齐两字新值再落盘，只改窗口内位并回报实际改动字数（v2.1.0） |
| `FC_DL_IntervalMembership` | FC | 开闭区间成员判定：四种开闭组合 + 到边界有符号裕量（内正外负）+ 恰在边界标志，端点倒置判非法不交换（v2.1.0） |
| `FB_DL_BitArrayChangeWatch` | FB | 位图变化监视：逐字异或出变化掩码/变化位数/首变位绝对位号 + 跳变累计与判稳，v1.0.1 修复掉使能屏蔽故障复位通道（v2.1.0） |
| `FC_DL_BitArrayRotate` | FC | 跨字位串整串循环旋转：1~4 个 `DWORD` 视作一条 32~128 位位串整体平移、移出位回卷对端，位序总量守恒，与提取/插入件构成位段族三件套（v2.2.0） |
| `FC_DL_MaskCompare` | FC | 状态字掩码比较与差异定位：掩码 0 位为 don't-care 不参与比较，给出差异位图/差异位数/首个差异位号，报警直接定位到具体那一位（v2.2.0） |

### DL_MathData（42 项 · R12 字符串 / 数组比对 / 太阳位置 / 异常帧 + R13 CRC-8 / 严格解析 / 定宽字段 / 矩阵求逆）

| 组件 / Component | 类型 | 一句话 / Summary |
|---|---|---|
| `FC_DL_LinearScale` | FC | 线性标定：防除零 + 反向量程 + 双侧钳位 |
| `FC_DL_Deadband` | FC | 移位型 / 归零型双语义死区 |
| `FC_DL_Hysteresis` | FC | 施密特迟滞，状态经 `VAR_IN_OUT` 交还调用方 |
| `FB_DL_MovingAverage` | FB | O(1) 递推滑动平均，两阶段启动 + 漂移校正 |
| `FC_DL_Crc16Modbus` | FC | Modbus RTU CRC-16 逐位法，带实算验收向量 |
| `FC_DL_SwapBytes16` | FC | 16 位字高低字节互换，纯移位且自逆 |
| `FC_DL_SwapBytes32` | FC | 32 位四排布归一化，附 4×4 互逆矩阵 |
| `FB_DL_RingBufferLReal` | FB | 定长 64 的 LREAL 环形 FIFO，满拒写不覆盖 |
| `FC_DL_StringTrim` | FC | 首尾四类空白清理，双向扫描带防死锁 |
| `FC_DL_StringSplit` | FC | 单字符分隔报文拆分，保留空字段（CSV 语义） |
| `FC_DL_MultiPointLinear` | FC | 2..16 点折线查表插值，二分查找，非法表整表拒绝（v1.2.0） |
| `FC_DL_PolygonArea` | FC | 鞋带公式多边形面积与质心，LREAL 运算（v1.2.0） |
| `FC_DL_LineIntersection` | FC | 二维两直线/线段交点，容差按坐标量级配置（v1.2.0） |
| `FC_DL_Crc32Ethernet` | FC | CRC-32/ISO-HDLC 逐位法，分块链式调用（v1.2.0） |
| `FC_DL_LrcChecksum` | FC | Modbus ASCII LRC，帧头帧尾不参与计算（v1.2.0） |
| `FB_DL_LifoStack` | FB | 定长 64 LIFO 栈，满拒写不覆盖，上溢/下溢锁存（v1.2.0） |
| `FB_DL_MedianFilter` | FB | 滑动中值滤波（3..15 强制奇数），启动期即有值（v1.2.0） |
| `FB_DL_SignalStatistics` | FB | 滑动窗口七元组统计，两遍法方差防灾难性抵消（v1.2.0） |
| `FC_DL_QuickSortLReal` | FC | 无递归快速排序（显式栈 + 三数取中 + 插入兜底）（v1.2.0） |
| `FC_DL_HexStringToBytes` | FC | 十六进制串严格解析，先校验后写入（v1.2.0） |
| `FB_DL_FifoBuffer` | FB | LREAL 元素先进先出环形队列：满队丢新不覆盖旧数据，同拍弹压先弹后压（v1.8.0） |
| `FB_DL_ArraySearchFirst` | FB | 数组线性搜索首个命中值 + 可选全量计数模式（O(n)，无序可用）（v1.8.0） |
| `FC_DL_BinarySearchLReal` | FC | 升序数组二分查找（纯函数）：防溢出中点写法 + 守护计数，v1.0.1 补致命缺失引脚（v1.8.0） |
| `FC_DL_TempUnitConvert` | FC | ℃/℉/K 三温标互转：枚举对选择器 + 单向基准链，绝对零度信息级不阻断（v1.8.0） |
| `FC_DL_BcdToWord` | FC | BCD 码字转 UINT：逐半字节校验，非法码零部分结果返回（v1.8.0） |
| `FC_DL_WordToBcd` | FC | UINT 转 BCD 码字：超 9999 饱和不回绕，与 BcdToWord 构成编解码原子对（v1.8.0） |
| `FC_DL_SearchMinMax` | FC | 数组极值单遍扫描（值 + 索引同出）：首/末次命中可切、NaN 用 `x <> x` 跳过、全量非有限不返回 0 号位（v1.9.0） |
| `FC_DL_NthRoot` | FC | N 次根纯函数：奇偶次分治 + 偶次负底数拒绝 + Newton 迭代后结果有限性复检（v1.9.0） |
| `FC_DL_FactorialSat` | FC | 阶乘饱和（域 0~12）：12! 通过、13! 及以上饱和、负数按 0；v1.0.1 显式 `INT_TO_DINT`（v1.9.0） |
| `FC_DL_RangeOverlapCheck` | FC | 两个实数区间的六值关系判定（相离/相接/部分重叠/包含/相等）：四点入参 + 判定次序写死 + 重叠长度恒非负（v2.0.0） |
| `FC_DL_CalcDistance3D` | FC | 三维欧氏距离：大数走缩放分支防中间溢出，非有限输入返回 0.0 而非 NaN，同出三分量差（v2.0.0） |
| `FC_DL_RandomNext` | FC | 可复现 LCG 伪随机（NR 公开参数）：种子外置回灌、半开区间 `[0,1)`、退化参数回退保底（v2.0.0） |
| `FC_DL_PercentileLReal` | FC | 定长样本任意分位值（R-7 插值）：内部拷贝排序、调用方数组不变、非有限样本剔除、`nGuard` 兼性能探针（v2.0.0） |
| `FC_DL_ArrayDiffSummary` | FC | 两组实数数组统一容差逐项比对：超差项数 + 首个超差下标 + 最大偏差及下标 + 非有限标志，v1.0.1 补「差本身溢出」二次判据（v2.1.0） |
| `FC_DL_StringReplaceAll` | FC | 定长串全量替换：游标跳到插入段之后消灭「替换串含模式串」死循环，次数上限 + 守卫计数双闸，v1.0.1 补拼接超串型上限的显式截断置位（v2.1.0） |
| `FB_DL_StringTokenStream` | FB | 报文分词流：四相状态机逐拍取段，空段照占序号保字段对齐，帧变化逐字符比对，v1.0.1 取段改以锁存副本长度切片（v2.1.0） |
| `FC_DL_SolarPositionCalc` | FC | 太阳位置：年月日时分 + 经纬度 + 时区算赤纬/时角/高度角/方位角/均时差，当月实际天数校验含闰年，天顶不可辨显式兜底（v2.1.0） |
| `FC_DL_ModbusExceptionParse` | FC | Modbus 异常帧解析：还原原始功能码 + 异常码中文名 + 三级严重度 + 可重试标志，驱动上层重试策略（v2.1.0） |
| `FC_DL_Crc8` | FC | 参数化 MSB-first CRC-8 逐位算法（ATM / SAE-J1850 / HITAG 三变体），无查表无状态，补齐 CRC 族 8 位宽度（v2.2.0） |
| `FC_DL_StringToLReal` | FC | 定长 ASCII 严格解析成 LREAL：逐字符七态状态机 + 报出首个非法字符位置，前缀合法尾部夹脏仍给前缀值（v2.2.0） |
| `FC_DL_StringFixedField` | FC | 定宽字段装填（左/右对齐 + 指定填充字符）：R37「截断必须显式置位」范式的可复制样板——先置标志与码、最后才写缓冲（v2.2.0） |
| `FC_DL_Matrix3Inverse` | FC | 3×3 实数矩阵伴随法解析求逆：相对奇异判据 + 出口夹域，失败逆矩阵整体置 0 绝不输出非数，定长表达式全程可复算（v2.2.0） |

### DL_Algo（28 项 · Level 1 首库开库 + R5/R6/R8/R10/R11/R12/R13 补强）

| 组件 / Component | 类型 | 复杂度 | 一句话 / Summary |
|---|---|---|---|
| `FB_DL_PidController` | FB | 8 | 单回路位置式/增量式 PID，积分分离 + 两级抗饱和 + 手自动无扰 |
| `FB_DL_CascadePid` | FB | 8 | 主副双回路串级，内部组合两个 `FB_DL_PidController` 实例 |
| `FB_DL_SplitRangeControl` | FB | 5 | 分程输出分配（加热/冷却双执行器），中央死区防双阀同开 |
| `FB_DL_FeedforwardComp` | FB | 6 | 静态 + 动态前馈补偿，含 10 槽纯滞后队列 |
| `FB_DL_SmithPredictor` | FB | 9 | 史密斯预估器，一阶模型 + 滞后缓冲，长滞后对象专用 |
| `FB_DL_RateLimiter` | FB | 4 | 变化率限制，升降斜率独立 + 保持，速率为 0 表示该方向不限 |
| `FB_DL_RampGenerator` | FB | 4 | 线性斜坡发生器，斜率独立 + 暂停保持 + 跟踪投切 |
| `FB_DL_SCurveGenerator` | FB | 9 | 七段式 S 型轨迹，jerk→acc→vel→pos 四级积分链真实推进 |
| `FB_DL_PwmDutyController` | FB | 6 | 时间比例慢速 PWM，最小 ON/OFF 抑制，SSR 加热驱动 |
| `FB_DL_Integrator` | FB | 4 | 梯形法积分（LREAL 双精度累加），限幅/复位/保持，流量累计 |
| `FB_DL_Differentiator` | FB | 5 | 带一阶低通 + 速率限幅的实用微分器 |
| `FB_DL_LowPassFilter` | FB | 3 | 一阶低通（PT1），时间常数运行时可调 |
| `FB_DL_SecondOrderFilter` | FB | 6 | 二阶巴特沃斯低通（双线性离散，ζ=0.7071，-40dB/dec） |
| `FB_DL_HighPassFilter` | FB | 4 | 一阶高通（HP1），动态分量提取 / 振动监测 |
| `FC_DL_DewPointCalc` | FC | 3 | Magnus-Tetens 露点计算（-40..60°C，0.1..100%RH） |
| `FC_DL_FlowCompensate` | FC | 5 | 气体/蒸汽流量温压补偿（工况 → 标况 Nm³/h） |
| `FC_DL_HumidAirEnthalpy` | FC | 4 | 湿空气比焓计算（Magnus-Tetens 链），焓差控制与表冷功率预算（v1.4.0） |
| `FB_DL_RampSoakProfile` | FB | 6 | 多段 Ramp/Soak 程序曲线发生器（1..16 段），段切换沿/暂停/跳段/循环，烘箱·烧结炉·化成工步设定源（v1.5.0） |
| `FB_DL_PeakDetector` | FB | 4 | 峰值/谷值全周期保持 + 线性衰减模型 + 阈值事件，冲击计数，与窗口统计职责分离（v1.7.0） |
| `FB_DL_StepController` | FB | 6 | 多级步进控制器（1..8 级）：偏差分级 + 级间死区迟滞 + 最小驻留 + 累积/单级双拓扑 + 均衡轮换（v1.7.0） |
| `FB_DL_SineGenerator` | FB | 6 | 相位累加正弦发生器：回绕用减法 + 单拍回绕上限防死锁 + 失能/0 Hz 冻结相位不归零（v1.9.0） |
| `FB_DL_SawtoothGenerator` | FB | 6 | 对称度参数化锯齿/三角（0.01~0.99）：分段斜率独立 + 段标志 + 周期内相位百分比（v1.9.0） |
| `FC_DL_CoilDiameterCalc` | FC | 5 | 卷径瞬时反算 `D = v·i/(π·n)`：低速保护先于除法、卷芯保护判打滑、低通首拍无滞后（v1.9.0） |
| `FC_DL_AirDensity` | FC | 4 | 湿空气密度（Magnus-Tetens + 干湿分压叠加）：分母恒正、分压防负、密度域钳位（v1.9.0） |
| `FB_DL_R2rEwmaTuner` | FB | 7 | 批级 Run-to-Run 参数微调：一批只动一次 + EWMA 平滑 + 首样本直取 + 双约束（先限修正量再限参数域）+ 批次饱和计数与环缓冲审计（v2.0.0） |
| `FC_DL_WaterEnthalpy` | FC | 3 | 液态水比焓与平均比热：三次多项式比热积分、0 ℃ 基准、域 0~150 ℃，域外拒绝不外插不夹取（v2.1.0） |
| `FB_DL_ValveCharacteristic` | FB | 5 | 调节阀固有特性补偿：线性/等百分比/快开折算 + 行程限幅 + 输出死区 + 可调比守护，v1.0.1 投运复位改为保持阀位夹进行程（v2.1.0） |
| `FB_DL_FoulingResistanceEstimator` | FB | 7 | 换热器污垢热阻趋势底座：换热量 Q / LMTD / 实测 K → Rf = 1/K − 1/K_clean，趋势窗最小二乘拟合增长斜率并给清洗建议；不做 PID 不做控制，物性与清洁基准由调用方注入（v2.2.0） |

完整引脚表、调用示例与现场注意事项见 `DL_Algo/MANUAL_DL_Algo.md`；引脚级细节以 `DL_Algo/*.st` 源码为准。

### DL_Device（50 项 · Level 1 设备 OOP + R6 阀门/驱动族 + R7 十件套 + R8 安灯塔 + R9 步进 + R10 RFID/总线诊断 + R11 诊断/测量/执行 + R12 看板/核对/计量/真空 + R13 NE107 健康族）

| 组件 / Component | 类型 | 一句话 / Summary |
|---|---|---|
| `I_DL_Cylinder` | 接口 | 双电控气缸标准契约：状态枚举 + 属性 5 + 方法 4，故障态一律拒绝 |
| `FB_DL_PneumaticCylinder` | FB | 双电控气缸驱动：磁开消抖、超时自检、双传感器冲突锁存、双线圈互斥断言 |
| `I_DL_MotorDriver` | 接口 | DOL 电机驱动契约：状态 + 重启抑制指示 + 启停/复位方法 |
| `FB_DL_DolMotor` | FB | DOL 电机控制：反馈校验窗、失反馈脱扣、过载锁存、滑窗启动次数限制 |
| `I_DL_AnalogSensor` | 接口 | 模拟量变送器契约（NAMUR NE43）：质量分级 + 四级报警位 |
| `FB_DL_AnalogTransmitter` | FB | NE43 变送器处理：原始域四段诊断、滑动平均滤波、故障态保持末次有效值 |
| `I_DL_TemperatureZone` | 接口 | 加热/冷却温控区契约：设定值/投退/复位方法 |
| `FB_DL_HeatCoolZone` | FB | 双通道温控区（R4 算法族首个上层消费者）：注入式 PID → 分程 → 双路 PWM SSR |
| `FB_DL_SingleSolenoidCyl` | FB | 单电控弹簧复位气缸：纯时间模式 / 可选磁开双重校验，复用 `I_DL_Cylinder` 契约（v1.5.0） |
| `I_DL_VacuumGenerator` | 接口 | 真空发生器标准契约：吸附/吹气/停止/复位方法 + 负压反馈属性（v1.5.0） |
| `FB_DL_VacuumEjector` | FB | 真空发生器驱动：负压迟滞判定、建立超时、破真空定宽吹气脉冲（v1.5.0） |
| `FB_DL_StarDeltaMotor` | FB | 星三角降压启动：星角死区互锁、三接触器反馈校验、过载锁存、重启抑制（v1.5.0） |
| `I_DL_VfdDrive` | 接口 | 通用变频器契约：使能/正反转/点动/多段速/频率设定/复位六方法（v1.5.0） |
| `FB_DL_VfdGeneric` | FB | 通用端子型变频器驱动：正反转互斥、点动优先、多段速选择、故障复位定宽脉冲（v1.5.0） |
| `I_DL_ProportionalValve` | 接口 | 比例调节阀契约：阀位指令/反馈/偏差报警属性 + 设定/停止/复位方法（v1.5.0） |
| `FB_DL_AnalogValve` | FB | 模拟量调节阀指令整形：死区补偿 + 限幅域映射 + 偏差延时报警（不含闭环，v1.5.0） |
| `I_DL_MotorizedValve` | 接口 | 电动阀契约：开关/停止方法 + 估算开度与双限位反馈属性（v1.5.0） |
| `FB_DL_ThreePointValve` | FB | 三点浮点电动阀：开关脉冲输出 + 行程时间积分自动估算开度 + 端点双保险（v1.5.0） |
| `I_DL_BarcodeScanner` | 接口 | 固定式扫码枪契约：六态握手状态 + Trigger/Ack/Reset 三方法，串口收发外置（v1.6.0） |
| `FB_DL_SerialScanner` | FB | 扫码枪握手状态机：NoRead 自动重试→升级故障、CR/LF 剥离锁存、TP 定宽触发（R24 范式）（v1.6.0） |
| `I_DL_SafetyDoor` | 接口 | 电磁锁扣安全门契约：解锁时序七态 + RequestUnlock/Relock/Reset/AuditClear 四方法（v1.6.0） |
| `FB_DL_GuardLockDoor` | FB | 安全门联锁：停机请求→静止确认→解锁→开门审计→再锁定窗，防篡改冲突与出口断言（v1.6.0） |
| `I_DL_LightCurtain` | 接口 | 安全光幕契约：通光/遮挡/屏蔽/override 四态 + bSafeStop 核心安全镜像位（v1.6.0） |
| `FB_DL_SafetyLightCurtain` | FB | 序列式屏蔽状态机：2/4 传感器正向/反向序列、错乱即故障、屏蔽超时 + override 硬帽（v1.6.0） |
| `I_DL_FlowMeter` | 接口 | 流量计契约：瞬时流量/累计总量属性 + 总量清零/预置/复位三方法（v1.6.0） |
| `FB_DL_PulseFlowMeter` | FB | 脉冲流量计量：自重触发采样窗频率估计 + K 系数换算，总量脉冲计数法双缓冲无撕裂（v1.6.0） |
| `I_DL_LevelSwitch` | 接口 | 料位开关契约：fail-safe HIGH/LOW 失效安全方向模式 + 高/低联锁输出（v1.6.0） |
| `FB_DL_LevelSwitchVib` | FB | 振动叉料位开关处理：防抖→失效安全归一→双延迟确认→双联锁，使能切断强制镜像（v1.6.0） |
| `I_DL_TowerLight` | 接口 | 安灯塔标准契约：三枚举（色/模式/显示态）+ 只读属性 10 + 方法 3（SetColor/SilenceBuzzer/Reset）（v1.7.0） |
| `FB_DL_SignalTower` | FB | 安灯塔实现（IMPLEMENTS）：七级主级仲裁 + 消音保持窗（安全事件不消音）+ 红绿互斥断言 + 五路灯直驱（v1.7.0） |
| `I_DL_StepperOpenLoop` | 接口 | 开环步进契约：组态结构体 + 属性 3（bReady/fPosition/uAlarmWord）+ 方法 6，fPosition 强制声明非编码器反馈（v1.8.0） |
| `FB_DL_PulseDirStepper` | FB | 脉冲+方向步进控制器（IMPLEMENTS）：梯形加减速规划 + 限位锁向 + 堵转判据，v1.0.1 修复减速段终态死锁（v1.8.0） |
| `I_DL_RfidReader` | 接口 | RFID 读写头契约（AOI 四分段映射）：四 DUT 随文件发布 + 只读属性 3 + 方法 4，方法均返回受理值（v1.9.0） |
| `FB_DL_RfidTagHandler` | FB | RFID 实现（IMPLEMENTS）：五态握手 + 写后回读校验 + 超时重试链 + 重复读抑制窗 + 硬件原始码透传（v1.9.0） |
| `FB_DL_AxiolineDiagLatch` | FB | 总线模块诊断解析与首出锁存：7 位状态位映射 + 错误码/槽号双寄存器 + 128 特例 + 四级等级（v1.9.0） |
| `FB_DL_PdiReadScheduler` | FB | PDI 异步读取调度：四元参数域 + 单拍只发一条 + 超时钳位防重试风暴 + 双码打包 + 三轮失败锁定（v1.9.0） |
| `FB_DL_PortDiagAggregator` | FB | 8 端口诊断聚合与首出仲裁：链路位/端口码/CRC 计数三源合成掩码，首出取最小端口号且锁存不覆盖，风暴只留一拍（v2.0.0） |
| `FB_DL_StatusWordSegDecoder` | FB | 段表驱动状态字批量解码（≤16 段）：一次拿全部字段 + 越界/重叠/段数三类组态诊断，宽度 64 禁移位（v2.0.0） |
| `FB_DL_NtcTempScan` | FB | 1~16 路 NTC 巡检：B 值换算 + 断线/短路诊断 + 最热通道 + 轮询或全扫两模式，v1.0.1 补扫描圈数饱和守卫（v2.0.0） |
| `FB_DL_RollerGapAdjust` | FB | 辊距背隙补偿：单向越程逼近 + 反向精定位两段不可合并，反馈丢失时指令保持不清零（v2.0.0） |
| `FB_DL_PortDiagBoard` | FB | 多组端口诊断看板：4 组 × 8 端口掩码汇总 + 全局首出（组号/端口号/诊断码）+ 前 3 个待修端口，超界位屏蔽绝不虚增故障数（v2.1.0） |
| `FB_DL_DeviceParamVerify` | FB | 设备参数回读核对：逐项容差 + 单拍全遍历 + 一致/不一致双结论锁存，v1.0.1 信息码按核对周期清除（v2.1.0） |
| `FB_DL_EnergyMeterAccum` | FB | 电表累计与需量：正反向 32 位拼装（先判原始值单调性再换算）+ 换表识别 + 窗口平均/峰值需量，v1.0.1 修正暂停后窗口剩余时间基准（v2.1.0） |
| `FB_DL_VacuumGaugeMux` | FB | 真空计双表融合：带迟滞量程切换 + 重叠区十倍程交叉校验 + 质量三档，v1.0.1 取值后按本拍可用性复验（v2.1.0） |
| `I_DL_DeviceHealth` | 接口 | NE107 设备健康语言契约：六态（四态+功能检查+未知）+ 诊断码证据 + 当前态时长与锁存；只定义提问方式不定义判据，`E_DL_Ne107Status` 全库唯一属主（v2.2.0） |
| `I_DL_PowerMeter` | 接口 | 三相电表读侧契约：电量/电能质量/正反向累计电能/需量峰值 + 健康出口，上层看板与需量控制可插拔适配四类表实现（v2.2.0） |
| `FB_DL_ModbusPowerMeter` | FB | Modbus 三相电表实现（IMPLEMENTS）：原始值换算 + 32 位电能四字拼装 + 功率因数复算交叉校验 + 轻载抑制 + 15 min 需量窗 + NE107 六态健康出口（v2.2.0） |
| `FB_DL_ValveStictionDetect` | FB | 阀门黏滞在线诊断：OP/PV 反转点同指令差分滞环估计 + 四档严重度，Moderate 及以上须另有停滞/反转证据佐证，不因单点指标越限判重度（v2.2.0） |
| `FB_DL_AhuDamperStuckDiag` | FB | AHU 风阀三分类卡滞诊断：一步未动/动了没到/信号不可信三类各带独立确认窗，另带偏差/缓慢两个工艺级；「要停机」与「要排计划」分开报告（v2.2.0） |
| `FB_DL_PumpCavitationGuard` | FB | 泵汽蚀三判据守卫：流量偏低 + 扬程跌落 + 振动或电流波动同拍确认；单判据只报嫌疑不锁存；确认后只出降速请求不写变频器频率（v2.2.0） |

### DL_Motion（18 项 · Level 1 运动控制 + R6 回零/定位族 + R7 软限位围栏 + R8 同步耦合族 + R10 排线工步 + R11 卷绕张力 + R12 两轴插补 + R13 被动回零监听）

| 组件 / Component | 类型 | 一句话 / Summary |
|---|---|---|
| `I_DL_MotionAxis` | 接口 | 单轴运动标准契约：PLCopen 六态 + 禁用态，属性 7 + 方法 6（≤6 红线临界） |
| `FB_DL_SingleAxis` | FB | 单轴参考实现：指令仲裁、软限位预判、虚拟运动学仿真/真实位置注入双模式 |
| `FB_DL_AxisJogController` | FB | 轴点动操作器：长按低速延时升高速、松开即停、点动软限位独立拦截 |
| `FB_DL_AxisHomingSeq` | FB | 标准回零序列状态机：限位开关/原点开关/Z 相脉冲/扭矩堵转四模式 + 超时·行程双护栏（v1.5.0） |
| `FB_DL_AxisRelativeMove` | FB | 相对定位（MC_MoveRelative 语义）：链式步进累加、中止与轴故障中断（v1.5.0） |
| `FB_DL_AxisVelocityMove` | FB | 速度模式（MC_MoveVelocity 语义）：动态改速、速度钳位、受控停止（v1.5.0） |
| `FB_DL_SoftLimitGuard` | FB | 软限位电子围栏预判器：制动距离（含时延项）双向预警/拦截两级，向内恢复豁免（v1.6.0） |
| `FB_DL_ElectronicGear` | FB | 电子齿轮耦合：整数比值对零漂移 + 相位补偿 + 限斜率啮合/受控脱开（v1.7.0） |
| `FB_DL_ElectronicCam` | FB | 电子凸轮耦合：16 点表插值 + 周期/非周期 + 飞剪相位微调，禁负数取模（v1.7.0） |
| `FB_DL_GantrySyncAxis` | FB | 龙门双驱同步：偏差双阈监视 + 比例纠偏（饱和判卡滞）+ 超阈双轴停止（v1.7.0） |
| `FB_DL_TorqueLimitControl` | FB | 力矩达限压装判定：三源达限 OR + 位移窗一次锁存判定，设备异常/工件 NG 分离（v1.7.0） |
| `FB_DL_MarkPositionLatch` | FB | 印刷套准色标锁存：布防窗 + 同拍单次读写 + 8 槽历史前移 + 缺失提示（v1.7.0） |
| `FC_DL_CalcMoveTime` | FC | 梯形/三角运动耗时计算（纯函数），三角退化显式判，验收向量经总监验算勘误（v1.7.0） |
| `FB_DL_SuperimposedMove` | FB | 叠加运动补偿（MC_MoveSuperimposed 语义）：幅值限幅 + 斜坡限速 + 零驻留收敛，使能冻结不归零（v1.8.0） |
| `FB_DL_WindingTraverse` | FB | 收卷卷径递推 + 排线轴往复：双源仲裁 + 节距积分 + 端点方向判据 + dwell 换向，v1.0.1 修复方向量清零致命缺陷（v1.9.0） |
| `FB_DL_WindingTensionCtrl` | FB | 卷绕锥度张力 + 摆辊修正闭环：锥度随卷径衰减、纯比例修正环、开环降级显式上报、两拍无扰投切，v1.0.1 修复跟踪计数不递减与积分残量（v2.0.0） |
| `FB_DL_LineInterp2Axis` | FB | 两轴直线插补：单位向量分解 + 单轴限速折算 + 梯形/三角自适应三段剖面，暂停保位移、恢复按剩余量分流、终点钳位防爬行，v1.0.1 修复恢复首拍速度阶跃（v2.1.0） |
| `FB_DL_PassiveHomingMonitor` | FB | 被动回零旁路监听：轴被外力移动（手摇轮/拖动/重力下落）时的参考点确认，方向一致性 + 速度窗 + 多次位置一致性三判据；不发运动指令、不自造轴状态，偏移交上层按 `MC_SetPosition` 语义消费（v2.2.0） |

### DL_Process（26 项 · Level 2 工艺层 + R6 行业池 P0 + R7 统计/输送/配料 + R8 六件 + R10 拾放工站 + R11 工站四件套 + R12 相底座/温控采集行 + R13 工艺四件）

| 组件 / Component | 类型 | 一句话 / Summary |
|---|---|---|
| `FB_DL_PackMlStateMachine` | FB | PackML / ISA-TR88.00.02 十七态状态机框架：命令驱动 + acting 态自动推进，OEE 根因区分 |
| `FB_DL_PackMlCmdDecoder` | FB | PackML 命令解码器：十离散源 + 命令字双通道收口，防抖单发化，冲突全丢弃 |
| `FB_DL_EnthalpyCompareCtrl` | FB | 焓差经济器执行块：直接消费 `FC_DL_HumidAirEnthalpy`，差分焓值迟滞判据 + 最小新风位硬下限 + ASHRAE 90.1 高限停机（v1.5.0） |
| `FB_DL_OccScheduleWindow` | FB | 多窗作息排程：4 窗矩阵 + 星期使能 + 节假日覆盖 + 预启动占位，复用 `FB_DL_TimeWindowCheck`/`FC_DL_DayOfWeekCalc`（v1.5.0） |
| `FB_DL_OeeCalculator` | FB | OEE 班次统计引擎：三因子 + PackML 根因位停机分账，性能率超 100 封顶（v1.6.0） |
| `FB_DL_ConveyorZone` | FB | 输送线积放单区（ZPA）：有料且下游允许才走 + run-on 清区 + 卡料窗，驱动经 `I_DL_VfdDrive` 注入（v1.6.0） |
| `FB_DL_BatchDosingControl` | FB | 配料称重控制器：快加/慢加/落定三段顺控 + 空中落差自学习（误差/2）+ 超差 NG 锁存（v1.6.0） |
| `FB_DL_ConveyorLineLink` | FB | 线体级联握手协调器（SMEMA 式 BA/MR/INH）：三路消抖 + 传递看门狗 + 维护直通 + NG 透传（v1.7.0） |
| `FB_DL_RecipeManager` | FB | 通用配方管理器：六层校验链 + 单拍全量应用 + 复核回读 + 32 位滚动异或校验和（v1.7.0） |
| `FB_DL_LeakTestStation` | FB | 气密泄漏测试工站（压降法）：五相位 + 温度补偿 + 大漏快判，设备异常/工件 NG 分离（v1.7.0） |
| `FB_DL_MixRecipeControl` | FB | 搅拌配方控制（ISA-88 相语义）：交替换向 + 时间/扭矩终点双判据，驱动经 I_DL_VfdDrive 注入（v1.7.0） |
| `FB_DL_CipCleaningSeq` | FB | CIP 六相清洗序列：TACT 三路联锁暂停不计时 + 回液电导率终点 + 清洁许可放行（v1.7.0） |
| `FB_DL_BufferMagazine` | FB | 缓冲料仓三策略选层：自动/手动/NG 隔离 + 升降调度 + 槽位状态台账（v1.7.0） |
| `FB_DL_ModbusPollMaster` | FB | Modbus 轮询主站调度抽象层：站表轮询 + 超时重试 + 双计数台账，帧/CRC 归传输层（v1.8.0） |
| `FB_DL_AndonCallSystem` | FB | 安灯四级呼叫系统：显式优先级仲裁 + 抢占重锁 + 滚动均值统计 + 班次清零不清呼叫（v1.8.0） |
| `FB_DL_PickAndPlaceStation` | FB | 通用拾放工站模板：注入三轴 + 真空，九步序 + 七态最小子集 + 单步三段式 + 节拍统计 + 安灯出口，v1.0.1 修复 CASE 漏 `eExecute` 致命缺陷（v1.9.0） |
| `FB_DL_PressFitStation` | FB | 伺服精密压装八态工站：位移-压力包络插值 + 四特征点（接触/屈服/峰值/终点）+ 五类 NG 原因位，屈服取斜率回落不取压力过峰（v2.0.0） |
| `FB_DL_RotaryIndexTable` | FB | 多工位分度盘节拍五态：分度请求→到位→稳定→工位放行 + 空跑清洗模式，稳定窗掉沿判硬件松动且不自动重试（v2.0.0） |
| `FB_DL_AgvDockingHandshake` | FB | 载体对接交接七态：到位与双侧就绪各需连续两拍 + 物料在位快照一致性 + 完成确认提前到达判失序（v2.0.0） |
| `FB_DL_EnergySavingMode` | FB | 整线空闲节能四态：先降压→再停热→最后伺服休眠（反序退出）+ 唤醒三条与门控 + 反馈缺失禁放行（v2.0.0） |
| `FB_DL_BatchPhaseBase` | FB | ISA-88 相状态底座（11 态）：命令沿仲裁（中止>停止>暂停>恢复>启动，复位独立）+ 暂停在步骤边界生效 + 恢复不重头 + 相净运行计时，v1.0.1 修复单步超时跨步累加（v2.1.0） |
| `FB_DL_PollTempBank` | FB | 温控器轮询采集行：8 台轮询 + 工程量换算 + 有效域 + 逐通道滑动均值 + 质量掩码/在线台数 + 摘除后仍轮询以便自动恢复（v2.1.0） |
| `FB_DL_CapperTorqueTrend` | FB | 旋盖扭矩曲线特征 + 五类 NG 判别（低扭/高扭/滑牙/歪盖/曲线异常）：NG 原因位图可多位并置，主判定按安全/功能严重度降序（滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常）（v2.2.0） |
| `FB_DL_EscHeLeakCheck` | FB | 静电吸盘氦背冷泄漏率三段式判定：升压段斜率监视 → 稳压段极差判稳（可延长一次）→ 测量段压降率换算 + 温漂修正，OK/Warn/NG 三级（v2.2.0） |
| `FB_DL_ChamberSeasoningTrack` | FB | 腔体 seasoning 台账与放行：片数 + 工艺时长 + 膜厚均值/趋势累计，双判据（片数 ∧ 时长）才放行，连续越窗自动降级 `eNotReady`（v2.2.0） |
| `FB_DL_ReactorJacketDeltaT` | FB | 放热反应釜温-夹套温差约束：ΔT 上限与变化率双约束 + 上层 PID 输出冷/热分程带死区防同开，超温强制冷却带回差（v2.2.0） |

完整引脚表、调用示例与现场注意事项见各子库 `MANUAL_DL_*.md`；引脚级细节以各 `DL_*/*.st` 源码为准。

---

## 五、版本与状态 / Version and Status

| 维度 / Dimension | 当前 / Current |
|---|---|
| 库版本 / Library Version | v2.2.0（2026-11-16） |
| 组件总数 / Total Components | 204 / 10,000 |
| 全库代码行数 / Total Lines | 62,667 行（`wc -l` 口径；本轮 18 件合计 7,966 行） |
| Phase 1 进度 / Phase 1 Progress | **204 / 200（102% ✅ 超额完成）** |
| Level 0 进度 / Level 0 Progress | **82 / 40 ✅ 收口+扩容**（`DL_Base` **40** ｜ `DL_MathData` **42**） |
| Level 1 进度 / Level 1 Progress | `DL_Algo` **28** ｜ `DL_Device` **50 开库** ｜ `DL_Motion` **18 开库** |
| Level 2 进度 / Level 2 Progress | `DL_Process` **26 开库**（PackML 框架 + 行业池 + R8 工艺六件 + R9 调度抽象/安灯 + R10 拾放工站 + R11 工站四件套 + R12 ISA-88 相底座 / 温控采集行 + R13 旋盖扭矩 / 氦检漏 / seasoning 台账 / 夹套温差） |
| AI 训练语料 / SFT Records | 204 条（output 与 `.st` 字节级一致；R13 终审后按修后源码重注入） |
| 今日入库 / Today's Intake | **160 / 200**（R4~R12 累计：14 + 16 × 8 + 18，达成率 80.0%） |
| 红线违规 / Redline Violations | 0 |

**分类件数表 / Inventory by Sublibrary（v2.2.0）**

| 子库 / Sublibrary | Level | 件数 / Count | 本轮增量 / Delta | 子库版本 / Version | 故障码段 / Code Family |
|---|---|---|---|---|---|
| `DL_Base` | 0 | **40** | +2（位串旋转 / 掩码比较） | v1.9.0 | `0001_xxxx`（+`013D`~`0140`、`021F`~`0220`） |
| `DL_MathData` | 0 | **42** | +4（CRC-8 / 严格解析 / 定宽字段 / 矩阵求逆） | v1.7.0 | `0001_xxxx`（+`0141`~`014C`、`0221`~`0225`） |
| `DL_Algo` | 1 | **28** | +1（换热器污垢趋势） | v1.7.0 | `0002_xxxx`（+`2201`~`2204`、`2210`~`2212`） |
| `DL_Device` | 1 | **50** | +6（NE107 健康契约 / 电表契约与实现 / 阀黏滞 / AHU 卡滞 / 泵汽蚀） | v0.9.0 | `0003_xxxx`（+`0156`~`0165`、`0316`~`0329`，上界提至 `0329`） |
| `DL_Motion` | 1 | **18** | +1（被动回零旁路监听） | v0.9.0 | `0004_xxxx`（+`01C3`~`01C6`、`02D2`~`02D4`） |
| `DL_Process` | 2 | **26** | +4（旋盖扭矩 / 氦检漏 / seasoning 台账 / 夹套温差） | v0.9.0 | `0005_xxxx`（+`01C5`~`01D1`、`02F3`~`02FE`） |
| **合计 / Total** | — | **204** | **+18** | **v2.2.0** | — |

### 明星组件索引 / Star Components of Round 13

| 组件 / Component | 看点 / Why It Stands Out | 手册 / Manual |
|---|---|---|
| `I_DL_DeviceHealth` | 给全库立起「设备健康」的统一语言：NE107 六态 + 诊断码证据 + 当前态时长——上层看板/联锁/维护三方可对话；**只定义提问方式、不定义判据**（判据留给实现者，统一判据会把正确行为判错），`E_DL_Ne107Status` 枚举全库唯一属主，禁复制枚举体 | `MANUAL_DL_Device.md` §49 |
| `FB_DL_ModbusPowerMeter` | `I_DL_PowerMeter` 的 Modbus 表实现：32 位电能四字拼装沿用既有口径但码位严禁复制；功率因数复算交叉校验（P/(U·I) 与 Q/(U·I) 互证）+ 轻载抑制 + 15 min 需量窗 + NE107 六态出口，换表诊断「故障带码 + 不置 bError」裁定落册 | `MANUAL_DL_Device.md` §50~§51 |
| `FB_DL_PumpCavitationGuard` | 汽蚀确认后**只出降速请求、不写变频器频率**——执行权归上层，每次确认降一步、不自动回升；单判据只报嫌疑（不锁存），抑制窗内判据被忽略但降速请求保持——安全动作与控制权限的边界一次划清 | `MANUAL_DL_Device.md` §54 |
| `FB_DL_EscHeLeakCheck` | ESC 氦背冷泄漏率三段式判定：稳压段可延长一次但**延长窗全程计时**（终审修复「延长窗失能」——窗可以长，但绝不能名存实亡）；测量段压降率换算 + 温漂修正，OK/Warn/NG 三级 | `MANUAL_DL_Process.md` §26 |
| `FC_DL_MaskCompare` | 状态字比对不止给「相等/不等」：差异位图 + 差异位数 + **首个差异位号**——报警直接定位到「差在第几位」；don't-care 位不参与比较，远程 IO 状态字忽略保留位整字比对一行完成 | `MANUAL_DL_Base.md` §42 |

### 明星组件索引 / Star Components of Round 12

| 组件 / Component | 看点 / Why It Stands Out | 手册 / Manual |
|---|---|---|
| `FB_DL_PortDiagBoard` | 把「多组端口同时报警、HMI 只看到最后一个」这个现场老问题一次解决：4 组 × 8 端口掩码汇总 + 全局首出（组号优先、端口号次之）+ 前 3 个待修端口编码；超界位显式屏蔽，绝不虚增故障数。ROADMAP §15.3 唯一 P0 件 | `MANUAL_DL_Device.md` §46 |
| `FB_DL_BatchPhaseBase` | ISA-88 相状态模型本体：11 态、命令沿仲裁（中止 > 停止 > 暂停 > 恢复 > 启动，复位独立）、**暂停在步骤边界生效、恢复不重头**——直指「暂停后物料半投」事故根因；相净运行时间可直接进 MES 产能核算 | `MANUAL_DL_Process.md` §23 |
| `FB_DL_StringTokenStream` | 报文分词从「一次拆完」推进到「逐拍取段」：空段照占序号保证字段对齐，帧变化用逐字符比对（等长改写无法靠长度判出），取段一律从锁存副本切片 | `MANUAL_DL_MathData.md` §38 |
| `FB_DL_LineInterp2Axis` | 两轴直线的完整速度剖面：单轴限速折算合成速度、梯形/三角自适应、暂停保位移、终点钳位防「永远差最后一点」；不注入轴接口，换伺服品牌不动插补逻辑 | `MANUAL_DL_Motion.md` §19 |
| `FC_DL_BitArrayExtract` + `FC_DL_BitArrayInsert` | 把位操作从「单字」推到「跨字位流」：位窗可达 64 位、可跨两个双字，读-改-写严格成对，且写入回报「实际改了几个字」——同值写入可被识别，通讯假成功无处藏身 | `MANUAL_DL_Base.md` §37~§38 |

**v2.2.0 亮点 / Round 13 NE107 设备健康族·工艺四件·CRC 与解析·污垢趋势·被动回零（NE107 Health Family · Process Quartet · CRC & Parsing · Fouling Trend · Passive Homing）**

> **① 设备层开「NE107 诊断族」，故障码上界提至 `0329`**：契约-契约-实现对三层——`I_DL_DeviceHealth`（六态健康语言契约，只定义提问方式不定义判据）+ `I_DL_PowerMeter` / `FB_DL_ModbusPowerMeter`（电表读侧契约与 Modbus 实现：32 位电能四字拼装 + 功率因数复算交叉校验 + 15 min 需量窗 + NE107 六态出口），加三件现场诊断：`FB_DL_ValveStictionDetect`（OP/PV 反转点差分滞环估计，Moderate 以上须停滞/反转证据佐证）、`FB_DL_AhuDamperStuckDiag`（三分类卡滞，各带独立确认窗，「要停机」与「要排计划」分开）、`FB_DL_PumpCavitationGuard`（三判据同拍确认，只出降速请求不写频率）。
>
> **② 工艺层四件直击现场判据空白**：`FB_DL_CapperTorqueTrend`（旋盖扭矩五类 NG，主判定按严重度降序）、`FB_DL_EscHeLeakCheck`（三段式氦检漏，稳压延长窗全程计时）、`FB_DL_ChamberSeasoningTrack`（seasoning 台账，双判据放行）、`FB_DL_ReactorJacketDeltaT`（釜-夹套温差双约束 + 冷热分程带死区）。运动层 `FB_DL_PassiveHomingMonitor` 补上「轴被外力移动」的参考点确认：旁路监听、三判据确认、偏移交上层——不发指令、不自造轴状态。
>
> **③ Level 0 补六个原子件，算法层开换热器退化底座**：`FC_DL_BitArrayRotate`（位段族第三件：整串循环旋转、位序守恒）、`FC_DL_MaskCompare`（差异定位到首个差异位号）、`FC_DL_Crc8`（三变体参数化，CRC 族补齐 8 位）、`FC_DL_StringToLReal`（七态严格解析 + 报首个非法字符位置）、`FC_DL_StringFixedField`（R37「截断必须显式置位」的样板件）、`FC_DL_Matrix3Inverse`（伴随法 + 相对奇异判据，失败整置 0 不出非数）；`FB_DL_FoulingResistanceEstimator`（Rf = 1/K − 1/K_clean + 最小二乘趋势斜率，只算值给建议、不做控制）。
>
> **④ 终审 18/18 PASS（14 处缺陷），10 件升 v1.0.1，存量 R39 专案收口**：最重的两处——`FB_DL_EscHeLeakCheck` 稳压延长窗全程未计时（窗形同虚设）、`FB_DL_InterlockMatrix` 禁用期吞复位沿（R39 存量修复，接口零变更）；另裁定 3 处机检 FAIL 为误报留档不修（Integrator / PidController / PulseDirStepper，复位通道有显式独立路径）。新增「是否置 bError」裁定列：换表（0318）与偏差（0323）等信息类诊断**故障带码但不置 bError**。本轮专家召唤为**兜底模式**（原生专家 not available，全程 general-purpose + 强制读人格，双角色分离）。

**v2.1.0 亮点 / Round 12 跨字位段·协议字符串·诊断与计量·相底座·两轴插补（Cross-Word Bits · Protocol Strings · Diagnostics & Metering · Phase Base · Two-Axis Interpolation）**

> **① Level 0 位算子从「单字」推到「跨字数组」，并补齐区间与位图两个原子面**：`FC_DL_BitArrayExtract` / `FC_DL_BitArrayInsert`（严格成对，位窗可达 64 位、可跨两个双字；闸门顺序「字数→偏移→宽度→越界截断」，宽度 64 走满宽常量分支、**禁 `SHL(x, 64)`**；写入回报实际改动字数，同值写入不再被当成「已生效」）、`FC_DL_IntervalMembership`（四种开闭组合 + 到边界有符号裕量，端点倒置判非法**不静默交换**）、`FB_DL_BitArrayChangeWatch`（位级变化掩码 + 首变位绝对位号 + 跳变累计与判稳，掉使能**刻意保留**跳变计数——排故证据不能在停机时被清掉）。
>
> **② 协议与物性两侧同时落子**：`FC_DL_StringReplaceAll`（游标跳到插入段之后，从算法层消灭「替换串含模式串」的自增长死循环）、`FB_DL_StringTokenStream`（逐拍取段，空段照占序号）、`FC_DL_ArrayDiffSummary`（统一容差逐项比对 + 首个超差 + 最大偏差）、`FC_DL_SolarPositionCalc`（年角→赤纬/均时差→真太阳时→时角→高度角/方位角，零平台时钟、天顶不可辨显式兜底）、`FC_DL_ModbusExceptionParse`（异常码 → 三级严重度 + 可重试标志，把「该不该重试」从每个项目的 `CASE` 收回库里）、`FC_DL_WaterEnthalpy`（三次比热积分，域外拒绝而不夹取——把 120 ℃ 按液态水结算会系统性高估焓值）、`FB_DL_ValveCharacteristic`（线性/等百分比/快开三特性 + 行程限幅 + 死区 + 可调比守护）。
>
> **③ 设备层把「看板—核对—计量—融合」四种诊断/测量能力补齐，故障码上界提至 `0315`**：`FB_DL_PortDiagBoard`（4 组 × 8 端口看板 + 全局首出 + 前 3 待修；`030B` 掩码跳变是**趋势码**，与 `0309`/`030A` 同号段但**不置 `bError`**，HMI 必须按级别着色）、`FB_DL_DeviceParamVerify`（逐项容差 + 双结论：`bVerified` 本轮、`bMismatch` 锁存）、`FB_DL_EnergyMeterAccum`（先判原始值单调性再做工程量换算，NE43 口径；换表按回退识别、不回绕续接）、`FB_DL_VacuumGaugeMux`（带迟滞量程切换 + 重叠区十倍程交叉校验；单表降级为「不确定」而非故障，但工艺联锁必须看质量位）。工艺与运动侧：`FB_DL_BatchPhaseBase`（ISA-88 相底座）、`FB_DL_PollTempBank`（温控器采集行，摘除后仍轮询才能自动恢复）、`FB_DL_LineInterp2Axis`（两轴直线插补）。
>
> **④ 终审 15 条缺陷（致命 3 / 严重 5 / 中等 3 / 注释级 4），10 件升 v1.0.1，沉淀 8 条新范式**：三条致命分别是——`FC_DL_StringReplaceAll` 拼接超串型上限被 `LEFT` 静默回夹而 `bTruncated` 恒假（报表尾部字段被裁仍判「完整」）；`FB_DL_BatchPhaseBase` 单步监视定时器跨步累加，3 步各 30 s 的合规批次在第 3 步被误判 `0203` 中止；`FB_DL_VacuumGaugeMux` 采信表在两相之间掉线后仍直取原值发布，联锁可能据此判「已到真空」。新范式 **R37** 定长串截断必须显式置位 ｜ **R38** 锁存副本与实时镜像量禁同名混用 ｜ **R39** 停机/掉使能分支不得屏蔽故障复位通道 ｜ **R40** 分段监控定时器必须按段断输入一拍 ｜ **R41** 恢复相转出判据不得只看已完成量 ｜ **R42** 跨相取值必须本拍复验数据源 ｜ **R43** 以保持替代回零时保持值须夹进有效域 ｜ **R44** 周期核对件信息码按核对周期清除。

> **v2.0.0 亮点 / Round 11 工站四件套·设备诊断与执行·批级微调·时间窗与计数闭环（Station Quartet · Device Diagnostics · Lot-Level Tuning · Window & Counter）**
>
> **① 工站层首次成套交付「四件套」，覆盖四条互不重叠的产线拓扑**：`FB_DL_PressFitStation`（伺服精密压装，八态 + 包络插值 + 四特征点 + 五类 NG 原因位，**屈服判据取斜率回落而非压力过峰**——现场屈服段多为斜率软化，强求过峰则单调上升曲线永远判不出）、`FB_DL_RotaryIndexTable`（分度盘节拍，`eSettling` 独立成态隔离到位后抖动，**稳定窗掉沿即判机械松动且不自动重试**——自动重试会把松动掩盖成偶发超时）、`FB_DL_AgvDockingHandshake`（会话式对接交接，物料在位快照一致性 + 完成确认提前到达判失序，不静默吞掉）、`FB_DL_EnergySavingMode`（整线节能，**先降压→再停热→最后伺服休眠**、反序退出 + 唤醒三条与门控）。四件均为最小态子集（4~8 态），不与十七态 PackML 全状态机争位。
>
> **② 设备层补齐「诊断—解码—测量—执行」四种能力，并首次突破故障码上界**：`FB_DL_PortDiagAggregator`（8 端口诊断聚合与首出仲裁，解决「多端口同时报警 HMI 只看到最后一条」，首出取最小端口号且锁存不覆盖）、`FB_DL_StatusWordSegDecoder`（段表驱动 16 段批量解码 + 重叠/越界/段数三类组态诊断，宽度 64 直接取全 1 常量、**禁对 64 位字移位 64**）、`FB_DL_NtcTempScan`（1~16 路 NTC 巡检，五类除法零守卫 + 单路损坏降级不整机停机）、`FB_DL_RollerGapAdjust`（辊距背隙补偿，**单向越程→反向精定位两段不可合并**，反馈丢失时指令保持不变、绝不清零）。R10 已占至 `0003_02F9`，`02xx` 仅余六码，故本批**显式开辟 `0003_0300`~`0308` 新子块并把本子库故障码上界提到 `0308`**，同时立规「后续先顺延 `0309`~`03FF`，禁止回填 `02FA`~`02FF`」。
>
> **③ Level 0 完成时间窗三粒度闭环与计数器五件族，算法层开「批级」新时间尺度**：`FB_DL_YearWindowCheck`（年粒度窗，跨年合法 + 按年折叠重复 + 整数日序数法零浮点，与月窗「跨月非法」语义相反、不可复用）、`FB_DL_RolloverCounter`（环形回绕 + 净圈数，比较赋值禁 `MOD`，与四件既有计数器五件互斥）、`FC_DL_RangeOverlapCheck` / `FC_DL_CalcDistance3D` / `FC_DL_RandomNext` / `FC_DL_PercentileLReal`（区间关系 / 点量距离 / 可复现随机 / R-7 分位）、`FB_DL_R2rEwmaTuner`（**批级** Run-to-Run，与拍级 PID 差三到四个数量级，双约束次序固定）、`FB_DL_WindingTensionCtrl`（锥度张力 + 摆辊纯比例修正，开环降级显式上报、两拍无扰投切）。终审 **PASS 14 件 + 修复后 PASS 2 件**：`FB_DL_WindingTensionCtrl` **2 致命 + 1 严重**（跟踪计数只置位不递减致闭环退化为开环；跟踪窗内过程值未取基准致积分残量非零、验收向量不可达；`02D1` 判据用「大于」饱和上限致锁存永不触发）、`FB_DL_NtcTempScan` **1 轻微**（全扫分支缺扫描圈数饱和守卫），均升 v1.0.1。存量 **7 件**治理：`FB_DL_PneumaticCylinder` / `FB_DL_SingleSolenoidCyl`（`_uCycleCount` 前缀笔误）、`FB_DL_LeakTestStation`（`_fDeltaP` 笔误，2 处，升 v1.0.2）、`FC_DL_QuickSortLReal`（`nPivotIdx` 漏声明）、`I_DL_AnalogSensor` / `I_DL_FlowMeter` / `FB_DL_AxisRelativeMove`（枚举成员单冒号，3 文件 5 行）——**三类均为三平台编译阻断缺陷**，机检全绿却全部漏网，再次印证「机检不等于编译」。

> **v1.9.0 亮点 / Round 10 Level 0 三组补强·信号发生·卷绕工艺·RFID 与总线诊断·拾放工站（Level 0 Extension · Signal Generation · Winding · RFID & Fieldbus · Pick & Place）**：本轮新增 16 个组件（送审 5,385 行 / 修后 5,528 行）——`DL_Base` 3 项（**T2-1 LGF Bit Logic / Date and Timer / Counter 三组横向补强**：位段提取 / ISO 周数 / CTUD 双向计数）、`DL_MathData` 3 项（LGF Math 组续挖：极值搜索 / N 次根 / 阶乘饱和）、`DL_Algo` 4 项（LGF Signal Generators 波形族开族 + Technology 卷径 + OSCAT Building 空气密度）、`DL_Device` 4 项（**T2-6 Rockwell AOI ☐→◐ 首次开组** RFID 契约-实现对 + **T1-7 PLCnext Community ☐→◐ 首次开组** 总线诊断双件）、`DL_Motion` 1 项（卷绕排线工步）、`DL_Process` 1 项（通用拾放工站模板）。终审 **PASS with fixes**：缺陷 17 条（致命 2 / 严重 3 / 中等 6 / 注释级 6）——**D-01** PickAndPlace 主 CASE 漏 `eExecute` 标签被 ELSE 兜底判非法锁故障，工站从启动推进到执行态当拍即自杀、九步序一行不执行；**D-02** WindingTraverse 待机态每拍清方向量、卷绕态从不重新赋值，位移增量恒 0（排线完全失效、收卷叠线）；另 D-03 未注入 Y 轴直接 `Stop()` 空引用、D-04 端点判据缺方向、D-05 屏蔽计数同拍装载又递减致确认失效。**8 件升 v1.0.1**，JSONL 8 条 output 字节级再注入（累计 152 条，sha256 `57c479…`）。新范式 **R31「枚举→CASE 双向映射完备性」**（CASE 分支必须覆盖枚举全部值，代码在 CASE 外处理也必须显式列空标签）与 **R32「内部状态量写入点全拍排序审计」**（每个内部量列出本拍所有写入点并按源码次序推演）。观察项 O-1~O-5 留档 v1.1（含 `ROUND_PLAN` 规格模板 WeekOfYearCalc 速算式勘误）。本轮专家召唤为**兜底模式**（原生专家两次尝试均 not available，全程 general-purpose + 强制读人格，双角色分离）。

> **v1.8.0 亮点 / Round 09 Level 0 回补·调度抽象·步进族·安灯（Level 0 Refill · Scheduler · Stepper · Andon）**：本轮新增 16 个组件（5,051 行）——`DL_MathData` 6 项（**T2-1 LGF Data Handling / Converter 组深化**：元素 FIFO / 线性搜索 / 二分查找 / 温标换算 / BCD 编解码原子对）、`DL_Base` 5 项（LGF Comparator / Bit Logic / Date and Timer / Counter 四组深化：公差窗 / 限值分档 / 位段打包 / 月窗 / 饱和计数）、`DL_Device` 2 项（**T1-8 GitHub topics ☐→◐ 开组**：开环步进契约-实现对，AccelStepper MIT 算法思想 clean-room）、`DL_Motion` 1 项（叠加运动补偿，T2-4 + T1-6 双源）、`DL_Process` 2 项（**T1-4 CODESYS Forge 深化** Modbus 轮询调度抽象 + **T2-7/8 安灯族开族**）。终审 **PASS with fixes**：缺陷 13 条（致命 2 / 严重 8 / 轻微 3）——**D-01** BinarySearchLReal 缺 uErrorId 声明三平台编译必败（机检七轮全过的活证据）、**D-02** PulseDirStepper eDecel 无频率归零出口静默死锁；**码位改判 6 件 15 处**（编码者"经核对未占用"自证全部推翻，终审后全库跨文件重叠 = 0）；全库嵌套注释风险清零（5 处头注释定界符修复，存量 `FC_DL_Crc16Modbus` → v1.0.1）。新范式 **R28「注释不可嵌套」** / **R29「赋值目标声明性检查」** / **R30「码位自证循环禁令」** 入册。观察项 O-01~O-11 留档 v1.1。本轮专家召唤为**兜底模式**（原生两位专家各两次尝试均 not available，全程 general-purpose + 强制读人格，双角色分离）。

> **v1.7.0 亮点 / Round 08 同步耦合开族·工艺六件·安灯塔·算法补强（Motion Sync · Process Six · Tower Light）**：本轮新增 16 个组件——`DL_Motion` 6 项（**T1-6 PLCopen 同步耦合族开族**：电子齿轮/电子凸轮/龙门同步 + 压装力矩/色标锁存/耗时计算，其中 `FC_DL_CalcMoveTime` 为 DL_Motion 首个 FC 形态组件）、`DL_Process` 6 项（**T1-4 CODESYS Forge 开组** RecipeManager + 线体握手/气密检测/搅拌混合/CIP 清洗/缓冲料仓五件，T2-2/T2-8 深化）、`DL_Device` 2 项（安灯塔契约-实现对，T1-5 TcOpen 深化 + R7 收口线漏记补记）、`DL_Algo` 2 项（T2-1 LGF Math 统计族 PeakDetector + T2-2 LBP CtrlStp 平移 StepController）。终审 16 文件 6987 行 fail=0、banned_hits=0；缺陷 **致命 1 + 严重 3 + 中等 1（5 文件 9 处孤立分号）+ 注释级 2**，受影响 6 个文件修后 v1.0.1。新范式 **R26「孤立分号空语句禁用」** 与 **R27「输出保持语义：状态保持态的输出必须每拍重置位，不得依赖转换拍脉冲」** 正式入册（R24/R25「单拍标志」家族的镜像面——保持侧生命周期）。实测驱动的源矩阵勘误：LGF V1.0.1 无独立 Measurement 组（归并 Math）、LBP V2.8 无混合/定量组（混合改走 ISA-88）。终审观察项 3 处（泄漏率量纲 kPa·mL/min、Cam 相位商域、Gantry 同值阈值）留档 v1.1。本轮专家召唤为**兜底模式**（原生两位专家各两次尝试均 not available），执行口径与原生模式一致。

> **v1.6.0 亮点 / Round 07 设备件十件套·计数器组·工艺统计三线并进（Device Set · Counter · Process Stats）**：本轮新增 16 个组件——`DL_Device` 10 项（**T1-5 TcOpen 组件范式首次开组**：扫码枪/安全门/光幕/流量计/料位开关「契约 + 实现」五条产线十件套）、`DL_Base` 2 项（**T2-1 LGF Counter 组开组**：双向事件计数 + 取模工位索引）、`DL_Process` 3 项（T2-7 PackML 深化 OeeCalculator、输送线 accumulation 的 ConveyorZone、T2-2 LBP + T2-8 ISA-88 深化 BatchDosingControl）、`DL_Motion` 1 项（T1-6 PLCopen 深化 SoftLimitGuard 制动距离预判）。终审 16/16 PASS，修复缺陷 14 处（**致命 2**：SerialScanner 重试链断裂、BatchDosing 判稳死锁——R24「单拍标志」家族第二例确认；严重 3：EventCounter 极值回绕穿透 / SafetyLightCurtain 反向判向死代码 / ConveyorZone 手动放行绕过门控；工程语义 4；逻辑级 1；注释级 1），另注释级勘误 1 处；8 个文件修后 v1.0.1。新范式 **R25「单拍标志生命周期三律：每拍预清零 / 实例调用后自清 / 消费拍与转出拍分离」** 正式入册（R24 扩展至「一切单拍标志」）。本轮专家召唤为**兜底模式**（原生两位专家均 not available），执行口径与原生模式一致。

> **v1.4.0 亮点 / Round 05 三目录开库（Three Sublibraries Opened）**：本轮新增 16 个组件，**六大目录全部开库**——`DL_Device` 8 项（气缸/DOL 电机/NE43 变送器/温控区四件套，契约-实现分离模式）、`DL_Motion` 3 项（PLCopen 轴状态机 + 点动操作器，虚拟运动学仿真与真实驱动同一状态机）、`DL_Process` 2 项（PackML 状态机框架 + 命令解码器，OEE 根因语义），`DL_Base` / `DL_Algo` 补强 3 项（星期换算、时间窗、湿空气焓值）。故障码段位体系扩展：DL_Device `16#0003_xxxx` ｜ DL_Motion `16#0004_xxxx` ｜ DL_Process `16#0005_xxxx`。R5 收口完成跨文件去重修复（`FB_DL_HeatCoolZone` 就地重复声明的 `E_DL_SignalQuality` / `I_DL_AnalogSensor` 已删除并统一引用正式契约文件）。本轮专家召唤为**兜底模式**：原生 `daoli-library-director` 不可用，改用 general-purpose 代理强制读取人格与规范，执行口径与原生模式一致。

> **v1.3.0 亮点 / Level 1 DL_Algo 首库开库（Round 04）**：本轮新增 16 个控制算法组件（源码合计 4035 行，`wc -l` 口径），覆盖 T2-1 LGF Signal Generators / Technology / Measurement、T2-5 Mod_PID_Control 与 T1-1 OSCAT Basic 的算法语义，终审 16/16 PASS、修复 16 处缺陷（含 `FB_DL_Integrator`、`FB_DL_SCurveGenerator` 两处「首扫判据反向 → 一次跟踪脉冲后永久锁死」的致命缺陷），并沉淀新范式 **R19 首扫标志唯一合法范式**（本轮口径 R8：`bInit` 初值 `FALSE`，判据 `IF bTrack OR (NOT bInit)`，同步后置 `TRUE`；禁止 `IF bInit OR bTrack` 这类反向判据——首扫永不触发且一旦触发就每拍触发）。本轮专家召唤为**兜底模式**：原生 `daoli-library-director` / `plc-programming-expert` 两次尝试均 not available，改用 general-purpose 代理强制读取人格与规范、双角色分离协作，执行口径与原生模式一致。

> **v1.2.0 回顾 / Level 0 Closure（历史）**：Level 0 两个子库 40/40 全线收口——`DL_Base` 补齐安全联锁四件套（双手安全、联锁矩阵、冗余切换、轮值调度），`DL_MathData` 补齐几何、CRC-32/LRC、LIFO、中值滤波、统计与无递归排序，并完成库级语法补全：全库 40 个 POU 补齐 `END_FUNCTION` / `END_FUNCTION_BLOCK` 终结符（详见 `CHANGELOG.md` v1.2.0 Fixed）。

版本号规则：MAJOR 破坏性接口变更；MINOR 新增组件或新增可选输入；PATCH 实现与文档修正。详见 `CHANGELOG.md`。

---

## 六、贡献与合规 / Contributing and Compliance

- **入库八条红线**是可执行的验收门槛，不是风格建议。未通过任一红线的代码宁可进 `ROADMAP.md` 待办，也不降标准入库。
- **开源溯源**：外部来源只借鉴算法语义与接口习惯，实现代码 100% 独立编写；LGPL/GPL 来源禁止逐行改写。每轮溯源台账见 `_Staging_Raw/<日期>/RAW_NOTES.md`。
- **`_Staging_Raw` 永不作为交付物**，也不被正式目录引用。

---

## 七、许可证建议 / License

本项目建议采用 **MIT License**。

**理由 / Rationale**：本库定位为基础设施，商业价值来自生态采用率而非许可限制；MIT 允许 OEM 与设备厂在闭源工程中直接引用而不产生合规争议，同时保留版权声明与免责条款。所有组件均为独立实现，不含 LGPL/GPL 衍生代码，具备 MIT 授权的完整权利基础。

```text
MIT License

Copyright (c) 2026 Daoli Industrial Automation Standard Library

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

> 正式发布前需在仓库根目录落 `LICENSE` 文件，并逐组件确认头部「开源溯源」字段与许可证声明一致。

---

*道莅（Daoli）工业自动化标准代码库 ｜ 由「工控代码库产品总监」与「PLC 编程专家」双专家流水线维护 ｜ Last updated: 2026-11-17*

**Round 26（2026-11-17）：锂电/化成 + 泵阀风机诊断 + 产线治理 + 凸轮/罐区计量 20 件（4 批）**——DL_Base 1（MinPulseWidthFilter 脉宽滤波）、DL_MathData 4（StringPad / EventRateCalc / HistogramAccum / WeightedMovingAvg）、DL_Algo 1（PidGainScheduler 增益调度）、DL_Device 7（ControlValveDiag / MotorPtcThermistProtect / ElectrolyteTankLevel / PumpDryRunProtect / FanBeltSlipDiag / VfdThermalDerate / DustFreehoodPress）、DL_Motion 2（AxisLoadTorqueMonitor / CamTableInterp 凸轮表插值）、DL_Process 5（AlarmShelving ISA-18.2 搁置 / ChillerTempStab / LineChangeoverChecklist 换型清单 / TankFarmInventory 罐区计量 / EnergyKpiAggregator）；合计 **2,290 行**；机检 20/20 PASS（3 处 STRUCT 语法阻断由主控人工修复，立红线 R132）；终审 4 抽 → **3 修 1 过**（均升 v1.0.1）；registry 444→**464**（v2.15.0）；六库 VERSION/MANUAL 同步顺延 R27 批量补（R138 债务显式化）。
> **Round 27（2026-11-17）：暖通 N+1 与防冻 · 包装灌装/制袋/开箱 · 半导体 LoadPort/MFC · 特气与孔板流量 19 新件 + 1 修订（4 批）**——DL_MathData 2（OrificeFlowCalc 孔板温压补偿 / WaferCountYield 良率分档）、DL_Algo 3（GasFlowSqrt / AirDensityFanPower / LoopWaveInject）、DL_Device 5（FanArrayStageCtrl N+1 轮值 / FrostProtectFreeze 五态防冻 / MfcFlowCtrl 跟踪窗 / DateCoderSync 分频喷码 / SealIntegrityMonitor 三参数窗）、DL_Motion 3（UnwinderDiameterCalc 卷径递推 / StringCutAlign 裁切对位 / StepperZLiftMicron 微米步进）、DL_Process 6（FillWeightCtrl 落差学习 / VffsBagLength 色标袋长 / CartonErectSeq 开箱四相 / LoadPortSeq 七相 + 25 位映射 / PumpChangeoverSeq 加减机 / MachineGuardAudit 门开审计）；`FB_DL_SplicerAutoJoint` 升 **v1.1.1**（v1.1.0 同步相 tSyncMax 欠账 R112 收口 + 终审补看门狗按相驻留）。
> **Round 28（2026-11-17）：500 件里程碑收口轮——半导体/锂电/层压/公用工程 17 件（4 批）**——DL_Algo 1（FanLawMultiExpCalc 三量指数可组态换算）｜DL_Motion 5（StepperXyzGantry 三轴开环龙门 / StepperFeederBelt 色标补偿送料 / LaserTabWeldTrack 焊缝三类缺陷窗 / NotchAlignSeq 缺口六相顺控 / EdgeTrimTraverse 修边横动）｜DL_Device 5（CheckweighZeroTrack 零点跟踪温漂 / EfEmDoorInterlockPlus 三门域首因 / NtcChannelHealth 通道健康评分 / WaferCassetteSlot 25 槽双向计数 / LamCtrlDualZone 双腔差压）｜DL_Process 6（LaminatorVacLeakTrend 泄漏率趋势 / PumpDownEnvelopeMonitor 抽气段界包络 / SealJawDwellTrim 驻留自整定 / BatchDeviationTierAlarm 四档分级 / InlineCheckweighGauge σ 控制图 / ChillerStagingCurve 冷机台数曲线）；合计 **4,085 行**（终审修复后 **4,140 行**），机检 check_r28.py **17/17 PASS fail=0**；**R28 终审 4 件高风险抽 4 修，全部升 v1.0.1**（冷机台数在「正好整除」点多投一台 / 冷机故障解除判据恒假致组态故障永久不可恢复 / 抽气早停建议位永不清理留幽灵建议 / 焊件停滞速度漏入域闸致 bit2 判据静默关闭）；**撞名 3 起**：ChamberPumpDownProfile→PumpDownEnvelopeMonitor、BatchDeviationAlarm→BatchDeviationTierAlarm 由编码侧另立名，FanLawRootCalc 与 DL_MathData 存量件跨子库同名（编译阻断级）于收口注册时发现并改名 FanLawMultiExpCalc，立新红线 R148「选题双查制」；registry 483→**500**（v2.17.0，counts 74/158/53/93/48/74），JSONL **500 条**；码位 0002_3715~3719 / 0003_03A7~03BF / 0004_0327~033F / 0005_0430~044D，CLASH=NONE；专家进化固化批次 R28（PLC 线 R139~R147+R151~R153、总监线 R139~R143+R148~R150 合并入规范）；**总库 500 / 10,000 里程碑达成，R29 起回归 20 件/轮常态节奏**。
> 合计 **4,214 行**，机检 **20/20 PASS** fail=0（码位 100 个零重复零撞车，含 R132 TYPE 块种类校验）；**R27 终审 4 抽 → 2 修 2 过**（MfcFlowCtrl 降设定误报超调 / SplicerAutoJoint 抖动漏窗，均升补丁版、对外引脚零变更；FillWeightCtrl 超重中止一并修；LoadPortSeq PASS）。
> registry 464→**483**（v2.16.0）；**距离 500 件里程碑仅差 17 件**；下一步 R28：固化 R139~R147 + 17 件冲 500 + 偿还编译验证债。

> **Round 29（2026-11-17）：半导体/锂电/暖通 19 新件 + 1 隔离**——registry 500→519（v2.18.0），AhuFilterDpBank quarantine 未入册（详见 CHANGELOG v2.18.0）。
> **Round 30（2026-11-18）：半导体阀岛诊断 + 包装称重剔除 + 光伏锂电 + 暖通水系统 20 件（1 返修 + 19 新，4 批）**——DL_Device 5（AhuFilterDpBank **R29 隔离件返修入册**〔aTonDeb 数组化每拍无条件刷新〕/ FoupDoorSeq / CoolantFlowAudit / ValvePdiSched / RackDiagSummary）｜DL_Process 8（WaferScanRouter / SiloLevelInterlock / PalletZoneMerge / WeightClassifySort / EmoAndonFab / FillWeightCheckweigher / FilmSpliceDetect / CoatingGapMeasure）｜DL_Motion 3（TrackerBacktrackCalc / LamStepperFeed / ElectrodeRollDiameter）｜DL_Algo 2（FanArraySeq / ChwDifferentialPressure）｜DL_MathData 1（ChecksumSum64）｜DL_Base 1（BitArraySegCopy）；机检 **20/20 PASS fail=0**（收口 21 处误报三类清零）；**终审 4 抽 → 4 过 0 修**（R40 返修范式首次验证通过，1 处轻微留档）；registry 519→**539**（v2.19.0，counts 75/162/58/102/55/87），JSONL **539 条**；码位 CLASH=NONE；专家进化新增 **R161~R165**；WebSearch 0/3 零检索轮。

> **Round 31（2026-11-18）：泵标定/PROFINET 诊断/晶圆交接/半导体腔体/暖通/流程计量 19 件（计划 20，序 1 与 R29 同名作废，4 批）**——DL_Process 11｜DL_Device 4｜DL_Motion 2（外部编码器族开族）｜DL_Algo 1｜DL_MathData 1；机检 **19/19 PASS fail=0**（71 码位 CLASH=NONE）；**终审 5 抽 → 4 修 1 过**（ReactorStepCtrl/ChamberLeakRate/FilmTensionDancer/EtchEndpointTrend 升 v1.0.1，WaferHandoffSeq PASS）；registry 539→**558**（v2.20.0，counts 75/163/59/106/57/98），JSONL **558 条**；专家进化新增 **R166~R175**；WebSearch 0/3 零检索轮。

- 2026-11-20T10:44:00+08:00 R51：+20 新件（Process 18/MathData 2）+4 返修 v1.0.1，registry 905→925（v2.43.0），SFT 906→926，机检 24/24 PASS。

---

## 质量门禁与工具链 / Quality Gate

自 R64 起，入库不再依赖人工抽检，改为**双层机器门**：

| 层 | 命令 | 内容 | 状态 |
|---|---|---|---|
| L1 静态门 | `python _tools/dl_gate.py --changed-only --hours 3` | 自研 ST 结构化解析（构造栈 + 声明解析）+ 7 项红线 + 声明完整性 F 检 + 版本/码段一致性 | ✅ 已启用，15 例回归自检 |
| L2 真编译门 | `python _tools/matic_runner.py --manifest …` | MatIEC `iec2iec` 全库解析（CI 构建） | ⏳ GitHub Actions（`.github/workflows/iec-compile.yml`） |
| L3 向量门 | `_TESTS/<Name>.json` + `vector_runner` | 除零/NaN/越界/复位/状态机兜底断言 | 🚧 逐步铺开 |

**首次全库扫描结论（2026-11-21）**：1,135 件 → PASS 1,005｜MAJOR 26｜BLOCK 104。其中 **34 件缺 `END_VAR`（编译级真缺陷）已机械修复**；剩余 71 个 BLOCK 为 `METHOD/PROPERTY` 闭合词方言问题，待 MatIEC CI 裁决。详见 `_Staging_Raw/2026-11-21/GATE_BASELINE_R64.md`。

**开源资产管线**：`python _tools/oss_harvest.py --search`（GitHub 检索 → 许可证三色分级 → 签名抽取 → 三道去重 → 候选队列）。匿名 API 限 60 次/小时；规模化需 GitHub PAT。
