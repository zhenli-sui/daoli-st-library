#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r56.py —— R56 主控直跑收口（R335）：机检 25 件 + 注册 20 新件 + JSONL 增量 + 文档追加。"""
import io, os, json, shutil, sys

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
ROADMAP = os.path.join(ROOT, "ROADMAP.md")
STAGE = os.path.join(ROOT, "_Staging_Raw", "2026-11-20")
NOW = "2026-11-21T00:00:00+08:00"

NEW = [
 ("FC_DL_HermiteInterp", "DL_MathData", "FC", 3, ["t2-1-lgf-math", "hermite", "interpolation", "clean-room"]),
 ("FC_DL_QuatSlerp", "DL_MathData", "FC", 3, ["t2-1-lgf-math", "quaternion", "slerp", "clean-room"]),
 ("FC_DL_RoundSigFigs", "DL_MathData", "FC", 3, ["t2-1-lgf-math", "rounding", "sig-figs", "clean-room"]),
 ("FC_DL_RtdLinearization", "DL_MathData", "FC", 4, ["roadmap-r56", "rtd", "cvd", "clean-room"]),
 ("FB_DL_EStopDualChannel", "DL_Base", "FB", 4, ["t2-1-lgf-converter", "estop", "dual-channel", "clean-room"]),
 ("FC_DL_Kalman2DSmoother", "DL_MathData", "FC", 5, ["roadmap-r56", "kalman", "2d-cv", "clean-room"]),
 ("FB_DL_SignalSeqGuard", "DL_Base", "FB", 3, ["t2-1-lgf-converter", "sequence", "guard", "clean-room"]),
 ("FB_DL_TwoDofPid", "DL_Algo", "FB", 4, ["t2-5-modpid", "2dof", "setpoint-weight", "clean-room"]),
 ("FB_DL_AxisAccelFeedforward", "DL_Motion", "FB", 3, ["t1-6-plcopen", "feedforward", "accel", "clean-room"]),
 ("FB_DL_HydraulicAccumPreChg", "DL_Device", "FB", 3, ["t2-2-lbp", "accumulator", "precharge", "clean-room"]),
 ("FB_DL_VacIonizerBalance", "DL_Device", "FB", 3, ["t2-2-lbp", "esd", "ionizer", "clean-room"]),
 ("FB_DL_FanVfdBypassSwap", "DL_Device", "FB", 4, ["t2-2-lbp", "vfd", "bypass", "clean-room"]),
 ("FB_DL_AxisCantileverComp", "DL_Motion", "FB", 4, ["t1-6-plcopen", "cantilever", "gravity-comp", "clean-room"]),
 ("FB_DL_HotRunnerZoneBalance", "DL_Process", "FB", 3, ["t2-2-lbp", "hot-runner", "zone-balance", "clean-room"]),
 ("FB_DL_SlurrySieveClogWatch", "DL_Process", "FB", 4, ["t2-2-lbp", "slurry", "clog-watch", "clean-room"]),
 ("FB_DL_LossInWeightFeeder", "DL_Algo", "FB", 5, ["t2-2-lbp", "loss-in-weight", "feeder", "clean-room"]),
 ("FB_DL_UvDoseCtrl", "DL_Algo", "FB", 5, ["t2-2-lbp", "uv-dose", "lamp-aging", "clean-room"]),
 ("FB_DL_UltrasonicWeldCtrl", "DL_Device", "FB", 5, ["t2-2-lbp", "ultrasonic", "weld", "clean-room"]),
 ("FB_DL_AxisProbeMeasCycle", "DL_Motion", "FB", 5, ["t2-2-lbp", "probe", "meas-cycle", "clean-room"]),
 ("FB_DL_AirShowerInterlockSeq", "DL_Process", "FB", 4, ["t2-2-lbp", "air-shower", "interlock", "clean-room"]),
]

REPAIR = [
 ("FB_DL_BacdHvacPoll", "DL_Process"),
 ("FB_DL_FopdtStepIdent", "DL_Algo"),
 ("FB_DL_CoinCellAssembler", "DL_Process"),
 ("FB_DL_StringElImageMap", "DL_Process"),
 ("FB_DL_PackMlUnitMode", "DL_Process"),
]

INSTR = {
"FC_DL_HermiteInterp": "机械凸轮与温度补偿曲线常用离散点表，需要过点且端点斜率已知的平滑插值：给定 x 与两端点坐标和斜率，按三次 Hermite 基函数求值，返回插值结果；x 落在区间外先钳位到端点并在出口置越域标志，两点重合（区间退化）时直接返回左端点防除零，输入非有限当拍拒绝计算并保持上拍输出，全程纯函数无依赖。",
"FC_DL_QuatSlerp": "机器人姿态与相机云台路径需要按时间比例在两姿态间平滑过渡：输入两单位四元数与插值系数 t，用球面线性插值求中间姿态；先判两四元数点积，为负则取反一端走最短弧，点积接近 1 时退化为一阶线性插值防除零，t 越界钳到 0~1，任一元零范数输入拒绝并置无效标志，输出归一化后交上位使用。",
"FC_DL_RoundSigFigs": "检测报告与配方参数常需按有效数字位数显示而非按小数位：给定实数值与有效数字位数，先按数量级求 10 的幂，再用整数循环累乘求缩放因子（避免非标幂运算），缩放后取整再缩回；位数越界钳到 1~15，零值与非有限值直接透传并置无效标志，负值取绝对值缩放后回符号，纯计算无副作用。",
"FC_DL_RtdLinearization": "热电阻测温回路需要把原始电阻值反解成温度：Pt100 与 Pt1000 分型，先扣三线制引线电阻补偿量，再按 Callendar-Van Dusen 分段求解——零下含二次项、零上取线性段；电阻越上下限或非有限时拒绝出参并置越域标志，引线补偿量越界钳位，输出温度同时给有效标志供上位判坏点，纯换算不含滤波内核。",
"FB_DL_EStopDualChannel": "安全回路要求两路常闭急停信号交叉监视：两通道均确认安全才算安全态，任一路断开或两路状态不一致持续超过差异超时窗即判单通道失效并锁存故障；安全侧输出只在两通道同时确认安全时为真，任何不确定一律给假（失效安全），两路均恢复后才允许复位清锁存，通道抖动用差异窗滤除不当场跳停。",
"FC_DL_Kalman2DSmoother": "行车与龙门轴的位置滤波常用常速模型：输入本拍测量坐标、上拍状态（位置与速度）、采样周期、过程噪声与量测噪声，输出更新后的位置速度估计；协方差按对角标量近似传播以适配纯函数形态，周期或噪声参数非法、输入非有限时原样返回上拍状态并置无效标志，不引入任何平台数学库或矩阵内核。",
"FB_DL_SignalSeqGuard": "多工位启动与阀组动作有先后顺序要求，乱序会造成撞机或憋压：对四路布尔输入按组态期望序列（正序/反序/前两路/后两路）在时间窗内校验到达顺序，顺序正确完成置完成脉冲，乱序立即锁存顺序违规故障并输出故障态；窗内未齐也判超时；复位须全部输入回落后才可清，四路同时到达按允许并发处理不误判。",
"FB_DL_TwoDofPid": "张力与温度回路既要快速跟随设定值变化又要抑制超调，单自由度 PID 无法同时满足：采用设定值加权结构，比例项只对加权设定值偏差作用、微分项对加权设定值微分与实际值微分分别加权，积分项在输出限幅期间停止累积防饱和；支持手动/自动无扰切换，参数越域钳位，输出给饱和上下限双标志供上位判限幅。",
"FB_DL_AxisAccelFeedforward": "高动态轴在加减速段仅靠位置环会滞后，需要把指令加速度前馈叠加到转矩：输入指令加速度、加速度与速度前馈增益及实际速度，输出前馈叠加量；前馈量经一阶低通平滑抑制指令阶跃引起的冲击，增益越域钳位，非有限输入当拍输出零并置无效标志，使能位为假时输出零且不累积状态，纯前馈不替代闭环。",
"FB_DL_HydraulicAccumPreChg": "液压站蓄能器预充压力偏低会导致泵频繁启停、偏高则有爆囊风险：按气腔压力、油口压力与油温做等温修正后与额定预充比较，输出偏差百分比与欠充/过充/气囊疑似/传感器坏四类诊断；判据带迟滞防压力波动误报，温度非有限时退化为不修正并置传感器坏，四类码位用枚举出口不做硬编码。",
"FB_DL_VacIonizerBalance": "静电防护区离子风机正负离子不平衡会带来器件损伤或吸尘：采集正负离子电流（或电压）采样值，计算平衡偏差百分比与衰减时间，超平衡限判偏正/偏负，衰减超时判衰减缓慢；判据带迟滞防抖，采样非有限或超量程判传感器坏并不参与平衡判定，输出平衡态与偏差值供上位趋势，只监视不调压。",
"FB_DL_FanVfdBypassSwap": "变频风机故障时需要切到工频旁通维持生产，切换过程两台接触器绝不能同时闭合：按停机变频、等待惰转、合旁通、试运行、稳定的顺序推进，每步有超时与最小间隔，旁通反馈未到位即中止并锁存；中间态严格双断，重试次数与间隔可组态，切换失败转手动并保持双断安全侧，不输出任何模棱指令。",
"FB_DL_AxisCantileverComp": "悬臂式上下料轴在伸出段因自重下垂，位置精度随伸长与负载变化：按当前位置在分段线性补偿曲线上取值，再按负载质量比例缩放得到补偿量叠加到位置指令；段点退化（非单调）判曲线异常不输出补偿，负载超限钳位到最大值，上电首拍用斜坡引入防跳变，补偿上限硬钳，非有限位置当拍不补偿并置无效。",
"FB_DL_HotRunnerZoneBalance": "多腔热流道各区温度不均会造成填充差异与飞边：采集八区实测温度与设定值，计算各区偏差、最大偏差区号与平均偏差，超带宽区数达阈值判不平衡；单区温度低于环境加阈值或变化率异常判掉线并不参与平衡统计，判据带迟滞防抖，区数可组态越界钳位，输出偏差数组与四类诊断供模温机联调，只监视不直接调功。",
"FB_DL_SlurrySieveClogWatch": "涂布浆料过筛网逐渐堵塞会造成流量衰减与颗粒划伤：以筛前后压差除以流量平方做归一化堵塞指数，与清洁态学习基准比较给劣化档位，并用时间序环窗八点斜率判趋势；基准只在确认清洁的窗口内学习更新，流量过低时判流量丢失不参与指数计算，非有限采样拒收，输出指数/斜率/两级预警与四类诊断码。",
"FB_DL_LossInWeightFeeder": "连续失重式给料需要按失重速率闭环控制螺旋转速：对称重做差分求失重速率并滤波，PI 调节输出给料指令；补料相冻结计量并估计补料后速率，避免补料冲击污染控制；速率长期为零判无失重、称重噪声过大判传感器抖动、补料超时判补料故障；批量累计到目标置批次完成，输出速率/给料中/补料中/状态与诊断码。",
"FB_DL_UvDoseCtrl": "UV 固化需要保证累计剂量达标而非只看光强：按光强乘曝晒时间积分累计剂量，与目标剂量比较后调节光强输出百分比，达到目标置完成脉冲；灯管老化用外部补偿系数折算有效光强，光强非有限或低于起辉阈值判灯弱并不累计，剂量超目标一定比例判超剂，累计量做溢出保护，只输出调光指令不含镇流器驱动。",
"FB_DL_UltrasonicWeldCtrl": "超声波焊接质量取决于能量输入而非单纯时间：按下降、保压、超声、冷却、抬升顺序推进状态机，超声段用梯形法积分功率得能量，超能量与欠能量双判据加超声超时三路保护，下降超时判机械卡滞；能量与时间参数可组态越界钳位，任一段异常立即停超声并进故障态，输出超声中/焊接完成/能量值与诊断码。",
"FB_DL_AxisProbeMeasCycle": "工件测头测量需要完整循环而非单点锁存：按快进、慢探、触发锁存、退回、稳定、记录的顺序推进，快进与慢探两段速度分离保证不撞头，触发用边沿锁存值记录（锁存副本与实时镜像严格分离，不用实时值做记录），超行程立即反向退回并置故障；重复测量按离散度判稳定，输出测量位置/有效标志/状态与诊断码。",
"FB_DL_AirShowerInterlockSeq": "风淋室双门互锁是洁净区污染控制底线：内外门不得同时开启，进入序列为外门开、关、吹淋计时、内门许可；吹淋超时或中止立即撤销内门许可并保持双门锁定，急停与火警优先解除许可并置中止态；门磁信号非有限或矛盾判传感器坏按最保守处理（双门锁），输出双门锁定态/吹淋中/进入许可与状态诊断。",
}

ARCH = {
"FC_DL_HermiteInterp": "纯函数求值架构：入口先做有限性闸（任一参数非有限即置无效并返回上拍友好值），再判区间退化（x1-x0 绝对值低于容差）直接返回端点防除零；越域按钳位处理并在出口置越域标志；基函数用 h00/h10/h01/h11 四个标准多项式集中声明，系数常量不写魔数；全程无状态可重入，CASE 兜底覆盖参数异常分支。",
"FC_DL_QuatSlerp": "球面插值纯函数架构：先算点积判半球（负则取反一端保证最短弧），点积超 0.9995 退化为线性插值加归一化（避免 acos 除零与数值抖动），否则按反余弦求夹角后用正弦比求两权重；t 先钳到 0~1；任一元零范数或非有限直接置无效标志返回输入；归一化前做范数下限闸，四元数分量常量集中声明。",
"FC_DL_RoundSigFigs": "量级缩放架构：先取绝对值并判零与非有限（零直通、非有限透传置无效），按量级循环除以 10 求指数，指数与位数差决定缩放幂次，用整数循环累乘构造 10 的幂避免非标运算符；缩放后加半取整再缩回，符号回填；位数先钳到 1~15；出口含结果与无效标志，纯计算无副作用可重入。",
"FC_DL_RtdLinearization": "分段反解架构：先扣引线补偿（补偿量越界钳位），判电阻上下限与非有限（越域置标志不出温度）；按零上线性段或零下二次段选择求解式，二次项系数集中声明；选型枚举用 CASE 分派 Pt100/Pt1000 两种标定系数，含 ELSE 兜底落无效；输出温度与有效/越域双标志，纯换算每次独立计算无状态。",
"FB_DL_EStopDualChannel": "双通道一致性状态机架构：段 0 无条件刷新两路沿检测与差异超时定时器；eSafe 要求两路均闭合，单路断开即进 eSingleCh 并启动差异计时，计时到仍不一致进 eFault 锁存；任何相的安全侧输出只在两路同时确认安全时为真，其余一律假（失效安全优先于可用性）；复位需两路全闭合后的上升沿才放行，出口含安全侧/两路坏标志/诊断码，CASE 含 ELSE 落故障态。",
"FC_DL_Kalman2DSmoother": "纯函数递推架构：入口判周期正、噪声正、输入有限（任一不满足原样返回上拍状态并置无效）；预测步按常速模型推进位置，协方差按对角标量传播并加过程噪声；更新步算卡尔曼增益（分母做下限闸防除零），修正位置与速度并收缩协方差；全部中间量局部声明无静态状态，状态由调用方持有保证可重入。",
"FB_DL_SignalSeqGuard": "时序守卫状态机架构：段 0 无条件刷新时间窗定时器与四路沿检测；eIdle 收到首路后按组态序列推进指针，每拍比对该到的路是否到达，乱序立即锁存 eOrderViolation；窗到时未齐置超时；完成置单拍完成脉冲并回 eIdle；允许并发的相邻两路同时到达走同拍受理分支；复位沿清指针与锁存但要求四路全落，CASE 含 ELSE 落故障态。",
"FB_DL_TwoDofPid": "二维自由度位置式 PID 架构：段 0 无条件刷新采样沿与微分低通；比例项用加权设定值减实测，积分项在输出饱和期间冻结（抗 windup）并在切回自动时按当前输出预置防冲击，微分项对加权设定值微分与实测微分分别加权后合成再过滤波；手动态输出直通手动值且积分跟随；参数越域钳位、非有限输入保持上拍输出并置无效；出口含输出/上下饱和标志/无效标志，CASE 含 ELSE 兜底。",
"FB_DL_AxisAccelFeedforward": "前馈叠加架构：段 0 无条件刷新滤波定时器与使能沿；使能有效时按加速度乘增益加实际速度乘速度增益合成前馈基值，再经一阶低通平滑输出；使能为假输出零并清滤波器状态防残留；增益越域钳位，非有限输入当拍输出零并置无效；出口含前馈量/使能态/无效标志，纯计算不写任何执行器。",
"FB_DL_HydraulicAccumPreChg": "热修正比对架构：段 0 无条件刷新采样沿与迟滞带；先按油温做等温修正把气腔压力折算到额定温度，再与额定预充求偏差百分比；偏差超欠充/过充阈值分档带迟滞锁存诊断，气囊疑似按压力波动率异常判，任一压力温度非有限或超量程判传感器坏并冻结判定；出口含偏差百分比/四类诊断枚举/修正后压力，CASE 含 ELSE 落传感器坏。",
"FB_DL_VacIonizerBalance": "平衡偏差统计架构：段 0 无条件刷新采样沿与衰减计时；按正负采样算偏差百分比与和值，超平衡限按符号分偏正/偏负并带迟滞，采样跌落时启动衰减计时判衰减缓慢；采样非有限或超量程判传感器坏冻结平衡判定；出口含偏差百分比/平衡态/衰减时间估计/四类诊断，枚举出口配 CASE ELSE 兜底。",
"FB_DL_FanVfdBypassSwap": "切换顺控状态机架构：eIdle→eStopVfd（撤变频运行）→eWaitSpinDown（等转速低于阈值，无条件刷新定时器）→eCloseBypass（合旁通并等反馈）→eRunDurance（工频试运行）→eStable；每相有超时与最小间隔闸，超时或反馈缺失即中止回 eIdle 保持双断并置故障；重试计数达上限转手动；不变量「两接触器不同时闭合」在每相出口显式写死，CASE 含 ELSE 落双断安全态。",
"FB_DL_AxisCantileverComp": "曲线补偿架构：段 0 无条件刷新首拍斜坡定时器；按当前位置在分段线性段点数组中定位区间（索引越界钳位），线性插值取基准补偿，再按负载质量比例缩放并硬钳上限；段点非单调判曲线退化不输出补偿；首拍按斜坡引入防跳变；位置非有限当拍不补偿并置无效；出口含补偿量/退化与无效标志，纯查表计算无副作用。",
"FB_DL_HotRunnerZoneBalance": "多区偏差统计架构：段 0 无条件刷新采样沿与迟滞；逐区算偏差（实测减设定），非有限或低于环境加阈值判掉线并排除出统计；统计有效区的最大偏差区号、平均偏差与超带宽区数，超阈区数达阈值判不平衡并锁存；阈值与区数越界钳位；出口含偏差数组/最大偏差区号/平均偏差/掉线数/四类诊断，CASE 含 ELSE 落传感器坏。",
"FB_DL_SlurrySieveClogWatch": "指数与趋势双判架构：段 0 无条件刷新采样沿与环窗推进；算归一化堵塞指数（压差除流量平方，流量下限闸防除零），写时间序环窗（按写入序回卷，不用头游标当自变量）；对环窗做首尾斜率判趋势；仅清洁确认窗口内更新学习基准；非有限拒收、流量过低判流量丢失；出口含指数/斜率/两级预警/四类诊断，CASE 含 ELSE 兜底。",
"FB_DL_LossInWeightFeeder": "失重计量状态机架构：段 0 无条件刷新采样沿与补料定时器；eDose 内对称重差分求速率并低通滤波，PI 输出给料指令，速率持续低于阈值判无失重；eRefill 冻结计量、清速率积分并在补料完成后按新重量重算基准；称重噪声按短窗方差判抖动；批量累计到目标置完成；各故障锁存并可复位；出口含速率/给料中/补料中/累计/状态与诊断码，CASE 含 ELSE 落故障态。",
"FB_DL_UvDoseCtrl": "剂量积分闭环架构：段 0 无条件刷新采样沿与积分步；有效光强由实测乘老化补偿系数得，低于起辉阈值判灯弱不累计；剂量按光强乘时间步梯形积分并做上限溢出保护；达目标置完成脉冲并按超剂比例判超剂；调光输出按剂量缺口比例调节并钳 0~100%；光强非有限当拍不累计并置传感器坏；出口含剂量/调光输出/完成脉冲/诊断，CASE 含 ELSE 兜底。",
"FB_DL_UltrasonicWeldCtrl": "焊接顺控状态机架构：eIdle→eDown（下降到位或超时）→eHold（保压）→eSonicOn（超声，功率梯形积分得能量，超能量/欠能量/超时三路保护）→eCool（冷却）→eUp（抬升）→eDone；每相配无条件刷新的定时器，异常统一进 eFault 并立即停超声；能量与时间参数越界钳位；出口含超声中/完成/能量/状态与诊断码，CASE 含 ELSE 落故障安全态。",
"FB_DL_AxisProbeMeasCycle": "测量循环状态机架构：eIdle→eFastApproach（快进）→eProbeLatch（慢探，触发沿锁存位置到锁存变量，记录只用锁存值不用实时镜像）→eRetract→eSettle（稳定定时器）→eRecord→eDone；超行程立即反向退回并置故障；重复测量按多次锁存位置的离散度判稳定；段 0 无条件刷新触发沿与各段定时器；出口含测量位置/有效标志/状态/诊断，CASE 含 ELSE 落退回安全态。",
"FB_DL_AirShowerInterlockSeq": "双门互锁顺控架构：不变量「内外门不同时开」在每个出口显式写死；eIdle 等外门开，eOuterOpen 等外门关，eBlow 吹淋计时（定时器无条件刷新），到时给内门许可进 eInnerPass；吹淋超时或中止立即撤许可回 eIdle 并保持双门锁；急停火警优先解除许可；门磁矛盾或非有限判传感器坏按最保守双门锁；出口含双门锁定/吹淋中/进入许可/状态与诊断，CASE 含 ELSE 落最保守态。",
}

def main():
    # ---------- 1. 机检（增量 25 件）----------
    sys.path.insert(0, ROOT)
    from compile_gate_v0 import gate_file
    audit = []
    for name, cat, *_ in NEW:
        p = os.path.join(ROOT, cat, name + ".st")
        src, issues = gate_file(p)
        audit.append({"name": name, "kind": "new", "pass": not issues,
                      "issues": issues, "lines": len(src.strip().splitlines())})
    for name, cat in REPAIR:
        p = os.path.join(ROOT, cat, name + ".st")
        src, issues = gate_file(p)
        audit.append({"name": name, "kind": "repair", "pass": not issues,
                      "issues": issues, "lines": len(src.strip().splitlines())})
    npass = sum(1 for a in audit if a["pass"])
    for a in audit:
        print(("PASS" if a["pass"] else "FAIL"), a["name"], a["lines"], a["issues"] or "")
    io.open(os.path.join(STAGE, "_audit_r56.json"), "w", encoding="utf-8", newline="").write(
        json.dumps(audit, ensure_ascii=False, indent=1))
    print("AUDIT %d/%d PASS" % (npass, len(audit)))

    # ---------- 2. 注册 ----------
    shutil.copy2(REG, REG + ".bak_r56")
    shutil.copy2(JSONL, JSONL + ".bak_r56")
    reg = json.load(io.open(REG, encoding="utf-8"))
    comps = reg["components"]
    names = {c["name"].lower() for c in comps}
    added, skipped = [], []
    for name, cat, typ, cx, tags in NEW:
        if name.lower() in names:
            skipped.append(name); continue
        p = os.path.join(ROOT, cat, name + ".st")
        L = len(io.open(p, encoding="utf-8").read().strip().splitlines())
        comps.append({"name": name, "category": cat, "type": typ, "file_path": p,
                      "function_tags": tags + [name.lower()], "complexity": cx,
                      "version": "1.0.0", "registered_at": NOW, "line_count": L,
                      "code_segment": "", "source": "r56-plan"})
        added.append(name)
    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["counts"] = {k: counts.get(k, 0) for k in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process")}
    reg["total_components"] = len(comps)
    reg["version"] = "2.48.0"
    reg["last_updated"] = NOW
    tmp = REG + ".tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="") as f:
        json.dump(reg, f, ensure_ascii=False, indent=1); f.write("\n")
    os.replace(tmp, REG)
    print("REG total=%d counts=%s added=%d skip=%s" % (len(comps), reg["counts"], len(added), skipped))

    # ---------- 3. JSONL ----------
    lines = [ln for ln in io.open(JSONL, encoding="utf-8").read().splitlines() if ln.strip()]
    before = len(lines)
    ap = 0
    present = set()
    for ln in lines:
        head = ln[:600]
        for name, *_ in NEW:
            if name in head: present.add(name)
    for name, cat, typ, cx, tags in NEW:
        if name in present: continue
        lines.append(json.dumps({"instruction": INSTR[name], "architecture_thought": ARCH[name],
                                 "output": io.open(os.path.join(ROOT, cat, name + ".st"), encoding="utf-8").read()},
                                ensure_ascii=False))
        ap += 1
    reinj = 0
    for name, cat in REPAIR:
        body = io.open(os.path.join(ROOT, cat, name + ".st"), encoding="utf-8").read()
        hit = 0
        for i, ln in enumerate(lines):
            try: o = json.loads(ln)
            except Exception: continue
            if o.get("output", "").splitlines()[:3] and name in o.get("output", "")[:400]:
                o["output"] = body
                o["instruction"] = o.get("instruction", "") + "（v1.0.1 返修版：见 REVIEW_R56 修法）"
                lines[i] = json.dumps(o, ensure_ascii=False)
                hit = 1; break
        reinj += hit
    tmp2 = JSONL + ".tmp"
    io.open(tmp2, "w", encoding="utf-8", newline="").write("\n".join(lines) + "\n")
    os.replace(tmp2, JSONL)
    bad = 0
    for ln in io.open(JSONL, encoding="utf-8").read().splitlines():
        if not ln.strip(): continue
        try:
            o = json.loads(ln)
            if not o.get("output") or len(o.get("instruction", "")) < 80 or len(o.get("architecture_thought", "")) < 100:
                bad += 1
        except Exception:
            bad += 1
    print("JSONL before=%d now=%d appended=%d reinject=%d bad=%d" % (before, len(lines), ap, reinj, bad))

    # ---------- 4. ROADMAP 勾选 ----------
    rl = io.open(ROADMAP, encoding="utf-8").read().splitlines()
    ticked = []
    for i, ln in enumerate(rl):
        if ln.startswith("- [ ]"):
            for name, *_ in NEW:
                if name in ln:
                    rl[i] = "- [x]" + ln[5:]; ticked.append(name); break
    io.open(ROADMAP, "w", encoding="utf-8", newline="").write("\n".join(rl) + "\n")
    left = sum(1 for x in rl if x.startswith("- [ ]"))
    print("ROADMAP ticked=%s pending_left=%d" % (ticked, left))

    # ---------- 5. README ----------
    rp = os.path.join(ROOT, "README.md")
    txt = io.open(rp, encoding="utf-8").read()
    total = reg["total_components"]; sft = len(lines)
    txt = txt.replace("Total%20Components-997%20", "Total%%20Components-%d%%20" % total)
    txt = txt.replace("SFT%20Corpus-998%20", "SFT%%20Corpus-%d%%20" % sft)
    txt = txt.replace("**Total Components: 997 / 10,000**", "**Total Components: %d / 10,000**" % total)
    txt = txt.replace("Version: v2.47.0", "Version: v2.48.0")
    txt = txt.replace("**SFT 语料: 998 条**", "**SFT 语料: %d 条**" % sft)
    txt = txt.replace("全库约 209,300 行", "全库约 216,300 行")
    summary = ("> **R56（2026-11-20/21）**：20 新件（MathData 5 / Device 4 / Algo 3 / Motion 3 / Process 3 / Base 2，插值·四元数·RTD·Kalman2D + 双通道急停 + 2-DOF PID + 失重给料/UV 剂量/超声焊/探针测量/风淋联锁）+ 5 件 v1.0.1 返修；"
               "总库 997→**%d**（**突破 1,000**），SFT %d，机检 %d/%d PASS；零检索轮，拒 6 项（R214 三查）。\n" % (total, sft, npass, len(audit)))
    anchor = txt.find("> **R55（2026-11-20）**")
    if anchor > 0:
        txt = txt[:anchor] + summary + txt[anchor:]
    io.open(rp, "w", encoding="utf-8", newline="").write(txt)
    print("README updated -> %d / SFT %d" % (total, sft))

    # ---------- 6. CHANGELOG ----------
    cp = os.path.join(ROOT, "CHANGELOG.md")
    ct = io.open(cp, encoding="utf-8").read()
    add = "\n## [v2.48.0] - 2026-11-21\n\n### Added\n"
    add += "".join("- `%s`（%s，cx%d）\n" % (n, c, x) for n, c, t, x, g in NEW)
    add += "\n### Fixed\n" + "".join("- `%s` v1.0.1：R55 五抽缺陷返修（详见 REVIEW_R55/R56）\n" % n for n, c in REPAIR)
    add += "\n### Changed\n- 全库 %d 件 / v2.48.0；SFT 语料 %d 条。\n" % (total, sft)
    idx = ct.find("\n## [v2.47.0]")
    ct = (ct[:idx] + add + ct[idx:]) if idx > 0 else (ct + add)
    io.open(cp, "w", encoding="utf-8", newline="").write(ct)
    print("CHANGELOG appended")

    # ---------- 7. VERSION 子库 ----------
    for sub, ver, note in [("DL_Base", "1.25", "2 件（EStopDualChannel / SignalSeqGuard）"),
                           ("DL_MathData", "1.27", "5 件（Hermite/QuatSlerp/RoundSigFigs/RTD/Kalman2D）"),
                           ("DL_Algo", "1.23", "3 件（TwoDofPid / LossInWeightFeeder / UvDoseCtrl）"),
                           ("DL_Device", "1.21", "4 件（AccumPreChg / IonizerBalance / FanBypass / UltrasonicWeld）"),
                           ("DL_Motion", "1.20", "3 件（AccelFeedforward / CantileverComp / ProbeMeasCycle）"),
                           ("DL_Process", "1.25", "3 件（HotRunnerZone / SlurrySieve / AirShowerInterlock）")]:
        vp = os.path.join(ROOT, sub, "VERSION.md")
        if not os.path.exists(vp):
            vp = os.path.join(ROOT, sub, "VERSION")
        if os.path.exists(vp):
            cur = io.open(vp, encoding="utf-8").read()
            entry = "\n## v%s — 2026-11-21（R56 追加）\n- 新增 %s。\n- 子库累计 %d 件。\n" % (
                ver, note, reg["counts"].get(sub, 0))
            io.open(vp, "w", encoding="utf-8", newline="").write(cur.rstrip() + "\n" + entry)
    print("VERSION x6 appended")

    print("SUMMARY total=%d counts=%s sft=%d pending=%d" % (total, reg["counts"], sft, left))

main()
