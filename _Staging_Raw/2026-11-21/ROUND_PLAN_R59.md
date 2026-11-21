# ROUND_PLAN_R59（第 59 轮 · 2026-11-21 · 无人值守 · 阶段一锁定件）

> 主控纪律：R214/R228 撞名三查已执行（registry 1053 名 6 轮全量 grep 反证 + ROADMAP 未勾项逐条核对 + R58 派单表回读）；20/20 候选三重比对 0 命中，拒单 9 件留痕见下。
> 取源结构：T0 八组 8/8 ✔ 余量 0 → 本轮零 T0 快车道件（仅 1 件 T0-2 安全语义扩展）；主力 = T2-1 LGF 未收口子族 + T1 组深化 + ROADMAP/R56 评估项落地 + 公开标准 clean-room。

## 一、R59 新件派单表（20 件 · 4 批 × 5）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_TimerFailSafe | DL_Base | FB_ | 安全侧定时器（超时自动输出安全态 + 安全侧赋值不受本闸判定量污染，T0-2 定时器安全语义扩展，与 ExtendedTimer 通用四模式分工互引） | T0-iec-std-wrapper | 轻 | 1 |
| 2 | FB_DL_TwoStepConfirm | DL_Base | FB_ | 两步确认防误触发（首按预备 + 限窗二按生效 + 窗超自动复位，IEC 60204 人机交互公开语义，与 HoldRepeatButton 按住重复分工） | self-std | 中 | 1 |
| 3 | FB_DL_MultiSegmentTimer | DL_Base | FB_ | 多段定时窗口组（N 段日历窗独立使能 + 段间重叠检测 + 当前段索引输出，LGF Date and Timer 多段定时语义 clean-room） | T2-1-lgf-date-timer | 中 | 1 |
| 4 | FC_DL_DmsAngleConvert | DL_MathData | FC_ | 度分秒 ↔ 十进制度双向换算（输入域闸 + 分秒进位钳制，Converter 组角度细分，与 WrapAngleDeg 归一化分工） | T2-1-lgf-converter | 轻 | 1 |
| 5 | FC_DL_QuadraticSolve | DL_MathData | FC_ | 二次方程实根求解（判别式三域分档 + a≈0 退化线性分支，浮点禁等号用 ABS 阈值，与 SimpsonQuad 积分分工） | T1-1-oscat-basic | 轻 | 1 |
| 6 | FC_DL_DtlStringConv | DL_MathData | FC_ | 日期时间 ↔ ASCII 串双向转换（格式定长校验 + 非法字符闸 + 255 截断标志，LGF Converter 组 DTL↔String 语义） | T2-1-lgf-converter | 中 | 2 |
| 7 | FC_DL_AsciiFrameParse | DL_MathData | FC_ | ASCII 仪表帧解析（STX/ETX 定界 + 长度闸 + 校验可选，OSCAT Network ASCII 帧族开件，与 ModbusRtuFrameCheck 二进制帧分工） | T1-3-oscat-network | 中 | 2 |
| 8 | FB_DL_DataResampler | DL_MathData | FB_ | 变周期数据重采样（新周期沿锁存 + 插值桥接 + 丢拍计数，测量评估族待挖项，与 MovingAverage 窗口滤波分工） | T2-1-lgf-measurement | 中 | 2 |
| 9 | FB_DL_SprayNozzleBank | DL_Device | FB_ | 多喷嘴组排布时序（分段分组吹扫/喷涂 + 组间搭接窗 + 喷堵压力反馈诊断，LBP 命令→监视→判定骨架） | T2-2-lbp | 中 | 2 |
| 10 | FB_DL_PathCornerBlend | DL_Motion | FB_ | 路径拐角圆滑过渡（拐角半径/误差带双约束 + 过渡段起止点解算 + 单调性自检，与 LookaheadVelPlanner 速度前瞻分工互引） | T1-6-plcopen | 中 | 2 |
| 11 | FB_DL_MracAdaptiveCtrl | DL_Algo | FB_ | 模型参考自适应控制器（参考模型跟踪误差驱动可调增益 + σ 修正防漂移，控制理论公开，与 RlsEstimator 参数辨识分工） | self（MRAC 公开） | 重 | 3 |
| 12 | FB_DL_CraneAntiSway | DL_Algo | FB_ | 桥式起重机防摆控制（摆角/摆速反馈 + 输入整形相位对消 + 防摆-定位双模切换，GitHub topics crane 线公开语义） | T1-8-github-topics | 中 | 3 |
| 13 | FB_DL_SpindleWarmupSeq | DL_Motion | FB_ | 主轴暖机顺控（阶梯升速驻留 + 轴承温升斜率闸 + 中途断电续暖，行业公开流程，与 SpindleOrientationStop 定向停分工） | self（行业公开流程） | 中 | 3 |
| 14 | FB_DL_DustCollectorPulse | DL_Device | FB_ | 布袋除尘器脉冲反吹（压差分级触发 + 脉阀轮巡 + 清灰无效劣化报警，LBP 三段骨架） | T2-2-lbp | 中 | 3 |
| 15 | FB_DL_LotoSequence | DL_Process | FB_ | LOTO 上锁挂牌流程（能量隔离点逐点确认 + 挂牌台账 + 解锁前试启验证，OSHA LOTO 公开流程语义，与 GuardLockDoor 单门互锁分工） | self-std | 中 | 3 |
| 16 | FC_DL_FftRadix2 | DL_MathData | FC_ | 基-2 FFT 频谱变换（2^N 点位反转序内排 + 窗函数可选 + 非有限拦截，与 HarmonicSpectrumBin 谐波定 bins 分工互引） | T1-1-oscat-basic | 重 | 4 |
| 17 | FC_DL_ConductivityTempComp | DL_MathData | FC_ | 电导率温度补偿（参考温归一 + 温度系数域闸 + 超域标志，OSCAT Building 水质域公开语义） | T1-2-oscat-building | 中 | 4 |
| 18 | FB_DL_VisionResultGate | DL_Process | FB_ | 视觉结果门控（OK/NG 判决窗 + 复检计数 + 超时无结果降级，TcOpen 视觉契约族范式，与 RobotGripVerify 抓取验证分工） | T1-5-tcopen | 中 | 4 |
| 19 | FB_DL_ToolLifeBudget | DL_Motion | FB_ | 刀具寿命预算（切削时长/件数双口径累计 + 寿命分档预警 + 换刀沿复位，与 AxisLubeDistTrig 润滑距离分工） | T1-8-github-topics | 中 | 4 |
| 20 | FB_DL_LotGenealogyLink | DL_Process | FB_ | 批次谱系链接（父子批次合并/拆分链维护 + 谱系深度上限 + 闭环检测，ISA-88 批次谱系公开模型，与 TrackBarcodeTrace 单件追踪分工） | T2-8-isa-88 | 中 | 4 |

## 二、拒单记录（R214 三重比对：①精确名 ②去前缀核心词 ③近义邻件）

| 被拒候选 | 三查命中 | 拒因 |
|---|---|---|
| FC_DL_LeastSquaresLineFit | ③命中 FC_DL_LinearRegression2Var | 二变量线性回归已覆盖 LS 直线拟合 → 同义邻件拒 |
| FB_DL_CusumChart | ③命中 FB_DL_CusumMonitor | CUSUM 统计监视已在册 → 拒 |
| FB_DL_EsdGroundMonitor / FB_DL_IonizerAirflowInterlock | ①精确命中 | ROADMAP R56 ESD 族评估项已落地在册 → 重复立项拒 |
| FB_DL_DeadTimeEstimator | ③命中 FB_DL_FirstOrderIdent | FOPDT 一阶辨识含纯滞后估计 → 拒 |
| FB_DL_AnnealRampProfile | ③命中 FB_DL_RampSoakProfile | 升温保温曲线族已覆盖 → 拒 |
| FC_DL_ArrayRotate | ③命中 FC_DL_BitArrayRotate | 数组循环旋转已在册 → 拒 |
| FC_DL_NormalQuantile | 无命中 | CpkCalc/CusumMonitor 已覆盖 SPC 判定域，独立件挖潜价值低 → 凑数风险拒（R228） |
| FB_DL_InputLogicInvert | 无命中 | 无工程纵深、排列组合级 → 凑数风险拒 |
| FB_DL_AxisServoHealthAudit | ③命中 FB_DL_AxisTorqueWatch/AxisTorqueRippleWatch | 轴侧转矩健康族已三件 → 同义邻件拒 |

## 三、批 1~4 分组清单（每批 5 个，批内可独立编译）

- 批 1：FB_DL_TimerFailSafe、FB_DL_TwoStepConfirm、FB_DL_MultiSegmentTimer、FC_DL_DmsAngleConvert、FC_DL_QuadraticSolve
- 批 2：FC_DL_DtlStringConv、FC_DL_AsciiFrameParse、FB_DL_DataResampler、FB_DL_SprayNozzleBank、FB_DL_PathCornerBlend
- 批 3：FB_DL_MracAdaptiveCtrl、FB_DL_CraneAntiSway、FB_DL_SpindleWarmupSeq、FB_DL_DustCollectorPulse、FB_DL_LotoSequence
- 批 4：FC_DL_FftRadix2、FC_DL_ConductivityTempComp、FB_DL_VisionResultGate、FB_DL_ToolLifeBudget、FB_DL_LotGenealogyLink

## 四、统计快照（2026-11-21 · R59 阶段一）
- 总库 1053 / 10,000（10.53%），registry v2.50.0，1053 名全唯一。
- 今日（11-21）已注册 56 / 200；距 1,050 里程碑 +3（已超额）。
- 源矩阵覆盖率：33 源组中 ✔ = 9（T0 八组 + T1-3），◐ = 24，☐ = 0 → 覆盖率 27%；本轮取自既有 ◐ 行 + R56/R57 ROADMAP 评估项 + 公开标准条款，零新开 ☐。
