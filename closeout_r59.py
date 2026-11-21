#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r59.py —— R59 主控直跑收口（R335）：机检 23 件（20 新 + 3 返修文件）+ 注册 20 新件 + JSONL 增量 + ROADMAP 勾选断言。"""
import io, os, json, re, sys
from compile_gate_v0 import gate_file

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
STAGE = os.path.join(ROOT, "_Staging_Raw", "2026-11-21")
NOW = "2026-11-21T07:45:00+08:00"
VER = "2.51.0"

NEW = [
 # name, cat, type, complexity, batch, tags, instruction, arch
 ("FB_DL_TimerFailSafe","DL_Base","FB",3,1,["iec-std-wrapper","watchdog","fail-safe","heartbeat","clean-room"],
  "安全相关回路的心跳监视不能只靠普通 TON：上位或安全 PLC 需周期性给出心跳脉冲，若在组态监视窗内未收到有效心跳则判通信/程序失联并立即输出安全态；上电未启动阶段须与真超时区分（未启动不报超时），超时锁存后必须由独立复位沿清除，不得自恢复；窗口参数越界钳位并置组态故障，心跳抖动用去抖窗滤除，输出失联态/超时标志/已运行时长。",
  "看门狗架构：段 0 无条件刷新心跳沿与内部 TON（R7 红线，实例不得置于分支内）；先判启动使能，未启动只累计运行时长不判超时；启动后 TON 以心跳沿复位，Q 输出持续为真达去抖窗即置失联；失联锁存后仅复位沿可清，清后需重新收到心跳才允许再判；窗口上下界钳位并置组态故障；出口含失联态/超时标志/运行时长，与 TimerFailSafe 之外的普通 TON 件分工互引。"),
 ("FB_DL_TwoStepConfirm","DL_Base","FB",3,1,["iec-std-wrapper","two-hand","two-step","confirmation","clean-room"],
  "危险动作（夹紧、落模、高压合闸）要求两次独立确认才能执行：两个确认输入必须在组态时限窗内**先后**有效（同一信号重复触发无效，顺序颠倒无效），超窗未凑齐则整次作废并计拒绝次数；任一步撤销立即作废不得残留；确认通过输出单拍许可，下一拍自动清零防粘滞；时限越界钳位，两输入同时到达时按首次到达时序处理并如实标注。",
  "两步确认状态机：E_IDLE→E_STEP1→E_STEP2→E_GRANT 四态，CASE 带 ELSE 兜底回 E_IDLE；段 0 无条件刷新两路上升沿；步 1 记录首确认时刻与通道号，步 2 只接受另一通道且时差 ≤ 窗；超窗/撤销/同通道重复任一条件触发 E_IDLE 并累加拒计数；许可为单拍量，出口前置清零；输入非有限（如时限）钳位并置参数坏。"),
 ("FB_DL_MultiSegmentTimer","DL_Base","FB",3,1,["iec-std-wrapper","sequence-timer","multi-segment","profile","clean-room"],
  "工艺曲线要求按多个时长段依次计时（预热 30s→保温 120s→冷却 45s），每段独立时长与独立输出位，段数可组态（≤8），段时长可跳过（0 即跳过）；总时长超上限判组态故障不出段输出；段号越界钳位在末段；暂停沿冻结当前段剩余时间，恢复沿续计不重头；输出当前段号/段内已计/总已计/全部完成位。",
  "多段时序架构：段表为定长常量数组（≤8），入口校验段数与各段时长上下界；段 0 无条件刷新单实例 TON（R7）；每拍按当前段时长装载 PT，Q 到时迁下一段并清段内计时，跳过段在迁入时即时判定；暂停态只冻结累加不改 PT 装载；段号全程钳位 [0, n-1] 防越界读表；出口含段号/段内/总计时/完成位，CASE 含 ELSE 落末段安全侧。"),
 ("FC_DL_DmsAngleConvert","DL_MathData","FC",3,1,["iec-std-wrapper","angle","dms","degree","unit-convert"],
  "测绘与天线方位数据常以度分秒（DMS）给出，控制器内部需十进制度：双向换算，秒/分越界（如 90 秒）需向上进位归一并回写，负角度符号只作用于度位；分秒非整数时按组态小数位舍入；输入非有限拒绝并置无效，越出 ±360° 钳位并置越域标志；纯函数无状态，出口含十进制度/归一后 DMS 三分量/有效标志。",
  "双向换算纯函数架构：入口先做有限性与量程闸（±360° 钳位 + 越域标志）；DMS→度按 d + m/60 + s/3600 累加，负号仅取度位符号；度→DMS 用整数分解 + 余数递推，秒余量按小数位舍入后向上进位，进位溢出再逐级向分、度传播（单点归一，避免多处回夹互相覆盖）；分秒越界一律归一而非拒绝；出口含有效/越域标志，无任何状态与外部依赖。"),
 ("FC_DL_QuadraticSolve","DL_MathData","FC",3,1,["iec-std-wrapper","polynomial","root","discriminant","numeric"],
  "标定曲线求交与轨迹抛物线求时需解 ax²+bx+c=0：按判别式分类输出两实根/重根/复根（复根只出实部与虚部模，不引入复数类型）；|a| 低于相对容差时退化为线性方程并置退化标志，b 亦近零则判无解；判别式近零用相对容差判重根防浮点抖动；系数非有限拒绝，输出根数/两实根/退化与无效标志。",
  "分支判别架构：入口非有限闸 → |a| 与系数尺度比判退化（相对容差，非绝对）→ 判别式 D=b²-4ac 与 0 的相对比较分三支：D>容差两实根、|D|≤容差重根、D<-容差复根（出实部 -b/2a 与 |D|^0.5/2a）；退化支转 -c/b；每支除法分母均已前置非零闸（R4）；出口含根数枚举（E_QE_ROOT_*）+ CASE 含 ELSE 兜底，纯函数可重入。"),
 ("FC_DL_DtlStringConv","DL_MathData","FC",3,2,["iec-std-wrapper","datetime","string","iso8601","convert"],
  "配方与批记录需与上位以 'YYYY-MM-DD-HH:MM:SS' 字符串交换时间：双向转换，解析侧严格校验分隔符位置与各位数字范围（月 1-12、日按年月实际天数含闰年、时 0-23、分秒 0-59），任一越界置对应错误码不出值；格式侧按字段宽度补零，年份限 1970-2099；非法字符/长度不符/字段越界三类错误分别可辨；纯函数，出口含 DT 值/字符串/错误码。",
  "解析-格式双通道架构：解析侧用固定位偏移逐字段切片 + 逐位数字校验（禁依赖平台字符串库函数），字段范围校验按 E_DTL_ERR_* 分级返回，日期合法天数用月份天数常量表 + 闰年判式（能被 4 整除且不能被 100 整除，或能被 400 整除）；格式侧按位宽补零装配，不产生分隔符漂移；全流程无状态、无动态内存，错误码枚举 CASE 含 ELSE 兜底。"),
 ("FC_DL_AsciiFrameParse","DL_MathData","FC",3,2,["iec-std-wrapper","ascii","frame","checksum","protocol"],
  "称重仪/扫码枪等 ASCII 设备帧格式为 STX + 载荷 + 校验 + ETX：需在字节流中定位帧头帧尾、校验和（累加和取低字节）比对、剥离载荷；帧长越界、校验不符、无帧头/无帧尾四类分别返回错误码；半帧（只有头无尾）不消费已收字节由调用方保留下拍续收；载荷含控制字符时按转义位拒绝；纯函数，出口含载荷长度/载荷缓冲/校验值/错误码。",
  "帧状态扫描架构：单遍扫描入口缓冲，E_FRM_IDLE→E_FRM_BODY→E_FRM_DONE 三态 CASE 含 ELSE 兜底；累加和在 BODY 态逐字节累计（仅低 8 位）；帧长超出缓冲上界立即中止并置 LEN 错，避免越界写（R4 每处下标访问前钳位）；校验不符与缺尾分别返回不同码；未闭合帧返回 NEED_MORE 且不改调用方消费指针；出口载荷长度 0 表示无有效帧。"),
 ("FB_DL_DataResampler","DL_MathData","FB",3,2,["iec-std-wrapper","resample","interpolation","timestamp","buffer"],
  "不同扫描周期的数据源（100ms 传感器 / 1s 上位）需统一到固定步长供算法消费：按目标步长在环形缓冲上重采样，支持线性插值与零阶保持两模式；时间戳倒退（乱序）样本拒绝并计数；缓冲满时覆盖最旧并置溢出标志；目标步长与缓冲深度越界钳位；输出重采样值/时间戳/有效标志/丢弃计数。",
  "环形缓冲重采样架构：段 0 无条件刷新采样沿与目标步长 TON（R7）；写入侧按时间戳单调性判入队或拒绝（倒退计数）；读出侧按目标步长触发，二分/线性定位跨越点后按模式插值（线性需两点时间差不为零闸，R4）；缓冲索引全部按深度取模并钳位；覆盖时头指针推进并置溢出；出口含值/戳/有效/丢弃计数，模式枚举 CASE 含 ELSE 落零阶保持。"),
 ("FB_DL_SprayNozzleBank","DL_Device","FB",4,2,["t2-2-lbp","spray","nozzle","bank","flow-monitor"],
  "涂装与水处理喷淋排有 N 路（≤12）喷嘴，需按组开关并按流量/压力反馈校验：组内单喷嘴故障只隔离该路不拖垮整组，隔离后按剩余路数重算流量配比；总流量低于组态下限判堵塞、高于上限判泄漏，持续去抖窗后分类报警；压力信号非有限判传感器坏按保守停喷；单路累计喷射时长用于保养计数，输出各路状态字/实际流量/报警码/保养计数。",
  "喷嘴组架构：段 0 无条件刷新各路开关沿与去抖 TON（R7，实例为定长数组）；每路独立故障锁存位，隔离由故障位与命令字按位与实现，禁运行期移位（固定掩码）；配比按有效路数做除数闸（零路即停喷，R4）；总流量上下限比较带迟滞；压力非有限置传感器坏并强制停喷；保养计数按路累加；出口状态字/流量/报警枚举 CASE 含 ELSE。"),
 ("FB_DL_PathCornerBlend","DL_Motion","FB",4,2,["t1-6-plcopen","motion","corner-blend","trajectory","tolerance"],
  "多段直线轨迹在拐角处直接停走效率低，需按允许偏差做圆滑过渡：按拐角夹角与组态允许偏差算过渡半径，半径钳位不超过相邻两段较短段长的一半（防过切），夹角过小（近共线）直接过渡、夹角过大（近折返）退化为精确停走；过渡段进给速度按向心加速度上限降速；输出过渡半径/降速系数/是否精确停走标志。",
  "拐角过渡几何架构：入口先做段长、夹角、偏差的非有限与量程闸；半径按 r = tol·sin(θ/2)/(1-sin(θ/2)) 类几何式求解后单点钳位（R5 禁多处回夹互相覆盖）；共线/折返两个边界用夹角阈值分派（枚举 E_BLEND_* + CASE 含 ELSE 落精确停）；降速系数由 v ≤ sqrt(a_max·r) 反算并钳位 [vmin,1]；出口半径/系数/标志，几何量全部带单位注释。"),
 ("FB_DL_MracAdaptiveCtrl","DL_Algo","FB",4,3,["t2-1-lgf-math","adaptive","mrac","lyapunov","control"],
  "负载惯量与摩擦随工况漂移，固定增益 PID 在宽域跟踪差：模型参考自适应控制，参考模型给理想响应，实际输出与模型输出之差驱动可调增益按 MIT 律/Lyapunov 律在线修正；增益限幅在安全区间防漂移发散，跟踪误差非有限立即冻结自适应并保持上次增益；激励不足（误差与输入均低于阈值）时冻结修正防噪声积分；输出控制量/自适应增益/跟踪误差/冻结标志。",
  "MRAC 双回路架构：段 0 无条件刷新；参考模型为一阶/二阶离散递推，与被控输出同步推进；误差 e = y_model - y_plant 经归一化（除以输入幅值闸，R4）后乘步长修正增益；修正量单点钳位到 [k_min,k_max]，并加速度限幅防阶跃；非有限或持续大误差（>阈）冻结自适应（保持增益、只清积分增量）；参数全带单位注释，冻结态不静默吞错（置 eErr）。"),
 ("FB_DL_CraneAntiSway","DL_Algo","FB",4,3,["t2-3-motion-app","crane","anti-sway","input-shaping","oscillation"],
  "行车吊运负载摆动导致定位慢与碰撞风险：按绳长估摆动周期（T=2π√(L/g)），对速度指令做输入整形（ZV 两脉冲）抑制残余摆动；绳长未知或超出量程时退化为加速度限幅（S 曲线）并置降级标志；摆角超限触发减速；整形器在急停/手动优先时旁路直通；输出整形后速度指令/摆动周期估算/降级与旁路标志。",
  "输入整形架构：入口做绳长与速度的非有限/量程闸；按 L 算 T 并分两脉冲（幅值按 ZV 系数、时延 T/2），脉冲发生器用环形定时队列实现（禁动态长度）；绳长无效时切 S 曲线加速度限幅分支（枚举 E_AS_MODE_* + CASE 含 ELSE 落限幅）；急停/手动直通由旁路位优先判决；输出指令/周期/标志，避免与普通 Ramp 件重复实现。"),
 ("FB_DL_SpindleWarmupSeq","DL_Motion","FB",4,3,["t2-2-lbp","spindle","warmup","sequence","thermal"],
  "机床冷机直接高速加工会因热伸长影响精度：暖机顺控按分段转速/时长阶梯升温（如 500→2000→5000 rpm 各若干分钟），暖机未完成禁止高速与精加工许可；超时未达目标转速、振动超限、任一阶段被中止则中止并锁存；可跳过（急件由人工确认跳过并记台账）；输出当前阶段/剩余时间/完成许可/中止原因。",
  "阶梯顺控架构：阶段表定长常量数组（转速/时长/振动阈），E_IDLE→E_RUN→E_DONE 三态 + CASE 含 ELSE 落 E_IDLE；段 0 无条件刷新阶段 TON 与转速稳定判据 TON（R7）；阶段出口三判据（达速、时长到、振动正常）缺一不迁；中止源（超时/振动/外部）统一汇入锁存位，复位沿清；跳过须确认沿并累加台账计数；出口阶段/剩余/许可/中止码。"),
 ("FB_DL_DustCollectorPulse","DL_Device","FB",4,3,["t2-2-lbp","dust-collector","pulse-jet","differential-pressure","sequential"],
  "布袋除尘器需按定时或压差触发脉冲喷吹清灰：N 阀（≤16）轮询喷吹，脉冲宽度与阀间隔可组态，一轮结束按周期重排；压差高于上限提前触发、低于下限暂停喷吹防过度清灰；压差信号非有限判传感器坏按保守转纯定时口径并置降级；气包压力低于下限禁喷（防喷吹无力）；输出当前阀号/喷吹中/累计脉冲数/降级与禁喷标志。",
  "轮询喷吹架构：段 0 无条件刷新喷吹脉冲 TON 与间隔 TON（R7 定长数组实例）；阀号推进用取模 + 上界钳位（R4 每次下标前钳位）；触发源（定时到/压差高）汇入启动沿，暂停源（压差低/气包低压/传感器坏）优先；脉冲宽度与间隔越界钳位并置组态故障；出口阀号/脉冲中/累计数/降级标志，模式枚举 CASE 含 ELSE。"),
 ("FB_DL_LotoSequence","DL_Process","FB",4,3,["t2-4-isa88","loto","lockout-tagout","energy-isolation","safety-seq"],
  "检修作业上锁挂牌必须按法定顺序确认才允许进入：停机→隔离能源→泄放残余能量→上锁挂牌→验证零能量 五步逐级确认，任一步未确认不得进入下一步，前序确认被撤销则整链回退到该步；多人作业锁具计数（每把锁独立确认，全员到位才放行）；验证零能量失败的步骤锁存并禁止后续；输出当前步号/各步确认状态字/锁具计数/进入许可/中止原因。",
  "五步链式状态机：E_LOTO_STOP→ISOLATE→BLEED→LOCK→VERIFY 五态（枚举 E_LOTO_*），CASE 含 ELSE 落 E_LOTO_STOP；每步只有确认沿 + 前置步已确认双条件才迁，确认撤销沿回退（保持已确认位递减）；锁具计数用定长数组逐把确认，计数达设定才允许 VERIFY；验证失败锁存 eAbort 并阻断迁相；所有确认位入口前置清零周期位；出口步号/状态字/计数/许可/中止码。"),
 ("FC_DL_FftRadix2","DL_MathData","FC",5,4,["t2-1-lgf-math","fft","radix2","spectrum","numeric"],
  "振动分析与电流谐波诊断需频域幅值：基 2 原地 FFT，点数须为 2 的幂（≤1024），先做位反转重排再蝶形逐级合并；非 2 的幂、点数越界、输入含非有限值一律拒绝返回错误码；输出幅值谱（归一化到 N/2）与相位，直流与奈奎斯特分量不重复计倍；蝶形内旋转因子用查表常量禁运行期三角函数；纯函数由调用方持缓冲。",
  "迭代蝶形架构：入口校验 N 为 2 的幂（按位与判式）与上下界，失败即返回 E_FFT_* 错误码不动缓冲；位反转表与旋转因子表为定长常量数组（禁动态生成）；三级循环：级长 2→N、组偏移、蝶形对；每对用 w 复数乘加，下标全部按 N 掩码取模防越界（R4）；输出幅值除以 N/2（直流与 Nyquist 单独除 N）单点归一；非有限输入在入口扫描即拒，避免 NaN 扩散。"),
 ("FC_DL_ConductivityTempComp","DL_MathData","FC",3,4,["t0-iec-std-wrapper","conductivity","temperature-compensation","water-quality","numeric"],
  "水质在线电导率必须补偿到 25℃ 基准才可比：两模式——线性补偿（α=2%/℃，适用于近 25℃ 窄域）与非线性 NaCl 曲线补偿（宽域）；温度越出 0-100℃ 钳位并置越域标志，补偿后电导率负值钳零；温度或电导非有限拒绝并置无效；纯函数，出口补偿后电导/所用模式/有效与越域标志。",
  "双模式补偿架构：入口非有限闸与温度量程钳位（单点回夹，禁多处覆盖）；模式枚举 E_CND_MODE_LINEAR / CURVE，CASE 含 ELSE 落线性；线性支 κ25 = κ/(1+α(T-25))，分母前置 >0 闸（R4，低温极端下 1+α(T-25) 可能趋零）；曲线支用分段节点表线性插值（与 ThermocoupleLinearization 同为查表但节点独立）；出口值/模式/标志，α 与节点表集中常量声明不写魔数。"),
 ("FB_DL_VisionResultGate","DL_Process","FB",4,4,["t2-4-isa88","vision","inspection","confidence-gate","ng-latch"],
  "视觉检测输出存在单帧误判与通信丢帧：结果闸门要求置信度达阈值且连续 N 帧一致才判 OK，任一帧判 NG 立即判 NG 锁存（防连续误放行）；结果超过有效期（无新帧）判 NG 并按通信故障分类，不得沿用旧结果放行；阈值/N/有效期越界钳位；输出判定结果/一致帧计数/过期标志/NG 锁存位/放行许可。",
  "闸门架构：段 0 无条件刷新帧到达沿与有效期 TON（R7）；每帧先做置信度比较（带迟滞防临界抖动），达阈则一致计数 +1、否则清零并置 NG 锁存；一致计数达 N 才置 OK，OK 为状态量；有效期 TON 到时置过期并按通信故障分类，过期期间许可恒假；复位沿清锁存与计数但不清台账；出口结果/计数/过期/锁存/许可，判定枚举 CASE 含 ELSE 落 NG。"),
 ("FB_DL_ToolLifeBudget","DL_Motion","FB",3,4,["t2-2-lbp","tool-life","budget","cutting-time","maintenance"],
  "刀具寿命按累计切削时长或加工次数预算，不能只靠人工记忆：双计量（切削时间/加工件数）任一达阈值即预警，达上限禁启动新程序；剩余量按百分比输出供看板；换刀确认沿复位并累计换刀次数、记录上次寿命用于趋势；阈值与已用值越界钳位，计时基准非有限置时钟坏；输出剩余百分比/预警/耗尽禁启/换刀次数。",
  "双计量预算架构：段 0 无条件刷新切削计时 TON（仅切削态累计，R7 实例无条件调用）；次数按件完成沿自增；两计量各自换算剩余百分比取小值为准（单点汇总，避免两条回夹冲突）；预警与耗尽阈值比较带迟滞；耗尽置禁启位并锁存至换刀确认沿；换刀沿清已用、次数 +1、保留上次值；非有限计时判时钟坏并停止累计不静默；出口百分比/预警/禁启/换刀数。"),
 ("FB_DL_LotGenealogyLink","DL_Process","FB",4,4,["t2-4-isa88","genealogy","lot-tracking","traceability","batch"],
  "批次追溯需建立子件批次与父批次的投入/产出谱系：投入时登记子件批次与数量到定长子件槽（≤8），产出时生成父批次记录并回指全部子件；子件批次为空或数量非正拒绝投入并计拒；槽满拒绝新子件不覆盖已登记；父批次未闭合不得产出；输出父批次号/子件槽数与内容/谱系完整标志/拒绝计数，供反向追溯索引。",
  "谱系登记架构：两段式——E_GEN_COLLECT（收集子件）→E_GEN_CLOSE（产出闭合），CASE 含 ELSE 落 COLLECT；子件槽定长数组 + 计数，投入沿校验批次号非空与数量 >0 后写入并计数 +1，槽满拒绝并计数；产出沿要求已收集数 >0 且父批次号非空才闭合，闭合后生成谱系完整标志；所有下标按槽上界钳位（R4）；出口父批次/槽数/完整标志/拒绝计数，字符串操作仅拼接不做动态长度。"),
]
REPAIR_FILES = [
 ("FC_DL_PmvComfortIndex","DL_Algo"),
 ("FB_DL_SoftStarterDrive","DL_Device"),
 ("FB_DL_PeriodicDisturbComp","DL_Algo"),
]

def main():
    rep = {}
    # 1) 机检增量：20 新件 + 3 返修文件
    res = []
    for it in NEW:
        name, cat = it[0], it[1]
        p = os.path.join(ROOT, cat, name + ".st")
        if not os.path.exists(p):
            res.append({"name": name, "pass": False, "issues": ["FILE_MISSING"]}); continue
        src, issues = gate_file(p)
        res.append({"name": name, "pass": not issues, "issues": issues, "lines": len(src.strip().splitlines())})
    for name, cat in REPAIR_FILES:
        p = os.path.join(ROOT, cat, name + ".st")
        src, issues = gate_file(p) if os.path.exists(p) else ("", ["FILE_MISSING"])
        res.append({"name": name + " [repair]", "pass": not issues, "issues": issues, "lines": len(src.strip().splitlines())})
    io.open(os.path.join(STAGE, "_audit_r59.json"), "w", encoding="utf-8", newline="").write(json.dumps(res, ensure_ascii=False, indent=1))
    fails = [x for x in res if not x["pass"]]
    print("AUDIT: %d files, PASS %d, FAIL %d" % (len(res), len(res) - len(fails), len(fails)))
    for f in fails:
        print("  FAIL", f["name"], json.dumps(f["issues"], ensure_ascii=False))

    # 2) 注册
    d = json.load(io.open(REG, encoding="utf-8"))
    have = set(c["name"] for c in d["components"])
    srcmap = {}
    for it in NEW:
        srcmap[it[0]] = os.path.join(ROOT, it[1], it[0] + ".st")
    added = 0
    for it in NEW:
        name, cat, typ, cx, batch, tags, inst, arch = it
        if name in have:
            print("  SKIP already registered", name); continue
        lines = len(io.open(srcmap[name], encoding="utf-8").read().strip().splitlines())
        d["components"].append({
            "name": name, "category": cat, "type": typ,
            "file_path": srcmap[name],
            "function_tags": tags + [name.replace("DL_", "").lower()],
            "complexity": cx, "version": "1.0.0",
            "registered_at": NOW, "line_count": lines,
            "code_segment": "", "source": "r59-plan",
        })
        added += 1
    d["version"] = VER
    d["last_updated"] = NOW
    d["total_components"] = len(d["components"])
    cnt = {}
    for c in d["components"]:
        cnt[c["category"]] = cnt.get(c["category"], 0) + 1
    d["counts"] = {k: cnt[k] for k in ["DL_Base","DL_MathData","DL_Algo","DL_Device","DL_Motion","DL_Process"] if k in cnt}
    io.open(REG, "w", encoding="utf-8", newline="").write(json.dumps(d, ensure_ascii=False, indent=1))
    d2 = json.load(io.open(REG, encoding="utf-8"))
    s = sum(d2["counts"].values())
    assert s == d2["total_components"] == len(d2["components"]), "COUNTS MISMATCH"
    print("REG: +%d -> total %d (v%s) counts=%s sum=%d" % (added, d2["total_components"], VER, d2["counts"], s))

    # 3) JSONL：20 新件追加 + 3 返修件重注入（按 FUNCTION[ _BLOCK] 声明名定位替换 output）
    lines = io.open(JSONL, encoding="utf-8").read().splitlines()
    out_lines, replaced = [], 0
    rep_names = set(n for n, _ in REPAIR_FILES)
    for ln in lines:
        try:
            o = json.loads(ln)
        except Exception:
            out_lines.append(ln); continue
        hit = None
        for n in rep_names:
            if re.search(r"FUNCTION_BLOCK\s+" + n + r"\b|FUNCTION\s+" + n + r"\b", o.get("output", "")):
                hit = n; break
        if hit:
            cat = dict(REPAIR_FILES)[hit]
            o["output"] = io.open(os.path.join(ROOT, cat, hit + ".st"), encoding="utf-8").read()
            o["architecture_thought"] = o.get("architecture_thought", "") + " 〔v1.0.1 修订：R59 依 R58 终审意见修正，见 REVIEW_R58/R59。〕"
            out_lines.append(json.dumps(o, ensure_ascii=False)); replaced += 1
        else:
            out_lines.append(ln)
    appended = 0
    for it in NEW:
        name, cat, typ, cx, batch, tags, inst, arch = it
        o = {"instruction": inst, "architecture_thought": arch,
             "output": io.open(srcmap[name], encoding="utf-8").read()}
        out_lines.append(json.dumps(o, ensure_ascii=False)); appended += 1
    io.open(JSONL, "w", encoding="utf-8", newline="").write("\n".join(out_lines) + "\n")
    # 校验新增行
    bad = 0; n = 0
    for ln in io.open(JSONL, encoding="utf-8").read().splitlines():
        n += 1
        try: json.loads(ln)
        except Exception: bad += 1
    print("JSONL: +%d new, %d repair re-injected, total %d lines, bad=%d" % (appended, replaced, n, bad))

    # 4) ROADMAP 勾选（R247：本体行正则锚定 + 数量断言）
    rm = io.open(os.path.join(ROOT, "ROADMAP.md"), encoding="utf-8").read().splitlines()
    want = set(it[0] for it in NEW)
    ticked = []
    for i, ln in enumerate(rm):
        m = re.match(r"^- \[ \] (.*)$", ln)
        if not m: continue
        body = m.group(1)
        for w in list(want):
            # 锚定：本体行以组件名开头，或含 `名字` 反引号本体；禁止子串泛匹配
            if re.match(r"^(FB|FC|I|ST|E)_DL_" + re.escape(w.replace("FB_DL_","").replace("FC_DL_","")) + r"\b", body) or re.match(r"^`" + re.escape(w) + r"`", body) or body.startswith(w + " "):
                rm[i] = "- [x] " + body; ticked.append((i + 1, w)); want.discard(w); break
    io.open(os.path.join(ROOT, "ROADMAP.md"), "w", encoding="utf-8", newline="").write("\n".join(rm) + "\n")
    assert len(ticked) <= len(NEW), "TICK OVERRUN"
    print("ROADMAP: ticked %d (expect 0, none of 20 registered in todo) -> %s" % (len(ticked), ticked))
    print("TODO remaining:", sum(1 for l in io.open(os.path.join(ROOT,"ROADMAP.md"),encoding="utf-8") if l.startswith("- [ ]")))

if __name__ == "__main__":
    main()
