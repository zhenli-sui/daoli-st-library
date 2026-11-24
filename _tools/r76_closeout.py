# -*- coding: utf-8 -*-
"""R76 收口：registry 注册 + SFT 语料追加 + 历史 25 条缺 output 补写"""
import json, os, sys, io, datetime

REG = r'C:\Library\INDEX_REGISTRY.json'
OUT = r'C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl'
STAGE = r'C:\Library\_Staging_Raw\2026-11-23'

NOW = '2026-11-23T16:52:00+08:00'
VERSION = '2.68.0'

# name, category, type, complexity, tags
ITEMS = [
 # ---- 复杂 4 ----
 ("FB_DL_BrakeReleaseInterlock","DL_Motion","FB",3,["servo","brake-release","interlock","torque-confirm","state-machine"]),
 ("FB_DL_HeaterBankLoadBalance","DL_Device","FB",3,["heater-bank","load-balance","runtime-hours","derate"]),
 ("FB_DL_ChillerDoorPurgeSeq","DL_Process","FB",3,["chiller","door-purge","interlock","permit-seq"]),
 ("FB_DL_AnalogDriftWatch","DL_Device","FB",3,["analog","redundant-channel","drift","dual-path"]),
 # ---- 族 A 位运算 DL_Base ----
 ("FC_DL_BitMaskRange","DL_Base","FC",1,["bitmask","range-build","clamp"]),
 ("FC_DL_BitReverse8","DL_Base","FC",1,["bit-reverse","byte"]),
 ("FC_DL_BitReverse16","DL_Base","FC",1,["bit-reverse","word"]),
 ("FC_DL_BitRunLength","DL_Base","FC",2,["bit-run","longest-ones","start-index"]),
 ("FC_DL_BitLowestSet","DL_Base","FC",1,["bit-scan","lowest-set","isolate"]),
 ("FC_DL_BitSwapPairs","DL_Base","FC",1,["bit-pair-swap","byte"]),
 ("FC_DL_BitCountTransitions","DL_Base","FC",2,["bit-transition","rise-fall-count"]),
 ("FC_DL_BitFillLowestZero","DL_Base","FC",1,["bit-fill","lowest-zero"]),
 # ---- 族 C 字节序 DL_Base ----
 ("FC_DL_BytesToWord","DL_Base","FC",1,["endian","pack","word"]),
 ("FC_DL_DwordToWords","DL_Base","FC",1,["endian","split","dword"]),
 ("FC_DL_WordsToDword","DL_Base","FC",1,["endian","assemble","dword"]),
 ("FC_DL_EndianProbe","DL_Base","FC",2,["endian","probe","iec-semantics"]),
 ("FC_DL_LwordToDwords","DL_Base","FC",1,["endian","split","lword"]),
 ("FC_DL_DwordsToLword","DL_Base","FC",1,["endian","assemble","lword"]),
 # ---- 族 B 角度 DL_MathData ----
 ("FC_DL_AngleLerpShort","DL_MathData","FC",2,["angle","shortest-arc","lerp"]),
 ("FC_DL_AngleQuadrant","DL_MathData","FC",1,["angle","quadrant","on-axis"]),
 ("FC_DL_AngleBisector","DL_MathData","FC",2,["angle","bisector","short-arc"]),
 ("FC_DL_AngleToCompass","DL_MathData","FC",1,["angle","compass","16-band"]),
 ("FC_DL_AngleTolInside","DL_MathData","FC",2,["angle","tolerance","wrap-aware"]),
 ("FC_DL_AngleReflect","DL_MathData","FC",1,["angle","reflect","axis"]),
 ("FC_DL_AngleUnwrapStep","DL_MathData","FC",2,["angle","unwrap","multi-turn"]),
 # ---- 族 D 三角 DL_MathData ----
 ("FC_DL_SinDeg","DL_MathData","FC",1,["trig","sine","degree"]),
 ("FC_DL_CosDeg","DL_MathData","FC",1,["trig","cosine","degree"]),
 ("FC_DL_TanDegChk","DL_MathData","FC",2,["trig","tangent","singular-check"]),
 ("FC_DL_AsinDegChk","DL_MathData","FC",1,["trig","asin","domain-clamp"]),
 ("FC_DL_AcosDegChk","DL_MathData","FC",1,["trig","acos","domain-clamp"]),
 ("FC_DL_Atan2Deg","DL_MathData","FC",2,["trig","atan2","quadrant"]),
 ("FC_DL_SincSafe","DL_MathData","FC",2,["trig","sinc","taylor-near-zero"]),
 ("FC_DL_HypotChk","DL_MathData","FC",2,["trig","hypot","overflow-safe"]),
 # ---- 族 E 迟滞限幅 DL_Algo ----
 ("FC_DL_HystWindow3","DL_Algo","FC",2,["hysteresis","three-band","window"]),
 ("FC_DL_HystLatchAlarm","DL_Algo","FC",2,["hysteresis","latch","alarm"]),
 ("FC_DL_HystCounterStep","DL_Algo","FC",2,["hysteresis","counter","band-step"]),
 ("FC_DL_HystTimeQualified","DL_Algo","FC",2,["hysteresis","time-qualified","ton"]),
 ("FC_DL_ClampDintChk","DL_Algo","FC",1,["clamp","dint","direction-flag"]),
 ("FC_DL_WrapToRange","DL_Algo","FC",2,["wrap","periodic","range"]),
]

SPEC = {
 "FB_DL_BrakeReleaseInterlock": (
   "立式伺服轴垂直负载停机后若抱闸未真正合上会掉刀；松开抱闸前必须先确认力矩已建立，否则会溜车。现场要求松闸动作有确定的时序与超时保护，超时不能只报警，必须回退到上闸安全态。",
   "把松闸过程拆成使能建立、力矩确认、松闸输出、闸位反馈确认四个正交阶段，用枚举状态机表达，避免多个布尔标志同时为真导致输出冲突。力矩确认与释放超时各用一个定时器，两个定时器实例全部在 CASE 之外无条件刷新，保证任何状态切换都不会让计时停在半途。闸位反馈超时走独立出口回到上闸态并锁存故障码，运行中使能丢失则以最高优先级直接上闸，不经过状态机其余分支。"),
 "FB_DL_HeaterBankLoadBalance": (
   "多路加热器长期由同一路承担主加热会让该路接触器提前失效，维护成本高；希望每次选累计工时最小的那一路做主加热，主路故障时自动顺延，超温时整组降额。",
   "把选主逻辑与执行逻辑分离：选主每拍从可用通道中取累计工时最小者，工时相同按通道号小者优先，这样选主结果确定可复现，不会因扫描顺序不同而抖动。超温降额以占空比形式作用于所有通道，与选主结果正交，避免降额时改变选主。通道数与工时归一化分母在入口一次性钳位，杜绝除零与下标越界。"),
 "FB_DL_ChillerDoorPurgeSeq": (
   "冷水机组检修门在机组运行时打开会让冷媒与空气混合，必须先关到位、建立风压、吹扫足够时间才允许开门；吹扫中途风压跌落或门被强行打开要立即回退并锁存故障。",
   "把许可链表达成关门确认、风压确认、吹扫计时、放行四个串行状态，每个状态的出口是到位信号与超时双条件，到位优先、超时作异常出口，机械卡滞不会永久挂死。急停输入在所有状态做最高优先级中断，中断动作固定为撤放行并回安全态，用统一出口而不是每状态各写一遍。风压确认用持续满足时间而非瞬时判断，避免风压建立初期的抖动误放行。"),
 "FB_DL_AnalogDriftWatch": (
   "同一测点用两路冗余模拟量输入时，两路之间的偏差缓慢增大说明其中一路在漂移，等偏差大到报警往往已经影响控制；希望把偏差按指数遗忘累积成漂移估计，分级预警，并能判断哪一路失可信。",
   "漂移估计用一阶指数遗忘递推而不是滑窗均值，滑窗在采样周期变化时会失真，遗忘系数由时间常数与采样周期算出并在入口钳位到 (0,1]，避免除零与系数越界。分级判定用两级阈值分别给预警与故障，故障级才动可信位，避免预警就切通道造成频繁切换。任一通道非有限值时按单边失可信处理并短路漂移累积，防止一个坏值把估计带偏。"),
 "FC_DL_BitMaskRange": (
   "组态时经常需要按位号区间取一段状态位做掩码，手写 16#00FF0000 这类常量容易数错位；希望给起止位号直接得到掩码。",
   "用移位与减法构造掩码而不是查表：左移位数由区间宽度决定，宽度为 32 时直接给全 1，否则 (1 左移 n) 减 1 再左移起始位，全程不出现越界移位。起止位号在入口钳位到 [0,31]，起大于止时返回零并置参数非法码，不做静默修正。"),
 "FC_DL_BitReverse8": (
   "某些老设备按低位先发的顺序传输字节，与 PLC 内部位序相反，收上来必须整体反转位序才能解析。",
   "用固定次数的移位与掩码分治：先交换相邻位，再交换相邻位对，最后交换高低半字节，三次掩码交换即可完成，不写 8 次循环，执行时间恒定。纯位运算无任何数值转换，BYTE 域内不会溢出。"),
 "FC_DL_BitReverse16": (
   "字级数据按位串行接收时需要整体反转 16 位位序，用逐位循环实现慢且容易写错边界。",
   "沿用分治交换思路扩到 16 位：相邻位、相邻位对、相邻半字节、相邻字节四级交换，四级掩码常数固定，无循环无下标，执行时间恒定且与输入无关。"),
 "FC_DL_BitRunLength": (
   "诊断通信质量时要看状态字里最长连续在线位的长度，判断是偶发丢包还是整段中断，人工看位图数不出来。",
   "单趟扫描同时维护当前游程与历史最长游程，当前位为 1 则当前游程加一并与最长比较，为 0 则清零，只需一次遍历。起始位号在最长游程被更新时同步记录，保证长度与起点始终对应；全零时返回零长度并把起点置为负一，让无效可辨识。"),
 "FC_DL_BitLowestSet": (
   "多路报警字里要取最先触发的那一路做首因定位，需要同时拿到位号和只含该位的隔离值。",
   "隔离值用 x 与 (非 (x 减 1)) 的与运算得到，只保留最低置位；位号由隔离值做逐段二分判定得到，不写 32 次循环。全零输入返回位号负一与隔离值零，让无报警与位号零区分开。"),
 "FC_DL_BitSwapPairs": (
   "某些编码器的格雷码按位对交错输出，解析前要把相邻两位互换重组。",
   "用两个掩码分别取出奇数位与偶数位，再分别左移右移一位后按位或回去，两次移位两次掩码即可，无循环。"),
 "FC_DL_BitCountTransitions": (
   "评估接点抖动程度要看状态字在一个周期内跳变了几次，只看当前值看不出抖动。",
   "把当前字与自身右移一位做异或，得到的就是相邻位是否不同，再统计该结果的置位数即为跳变总数；上升沿与下降沿分别用掩码取原始位与其右移位的组合统计，三者满足总数等于上升加下降，可自校验。"),
 "FC_DL_BitFillLowestZero": (
   "位图分配器要找到第一个空闲位并占用它，需要返回填位后的位图与被占用的位号。",
   "先对输入取反得到空闲位图，再用最低置位提取拿到待占位，最后与原值按位或完成占用。全 1 时取反为零，需在入口先判该情形并原样返回、位号置负一，避免提取到无意义值。"),
 "FC_DL_BytesToWord": (
   "与第三方设备交换字数据时对端字节序不固定，同一份报文在不同项目里高低字节顺序相反，需要按组态开关组装。",
   "用移位与掩码按开关选择高字节来源，两条分支各自完整拼装，不共用中间变量，避免分支交叉导致残留。字节到字的转换全部走标准类型转换，不做指针重解释，保证跨平台一致。"),
 "FC_DL_DwordToWords": (
   "把双字拆成两个字上传给只支持字寻址的上位机时，需要按对端约定决定哪个字在前。",
   "按开关选择两次移位截取的顺序，返回首字并把另一半从出参给出，调用方无需再拆一次。全部使用标准转换与移位，避开字节序相关语法。"),
 "FC_DL_WordsToDword": (
   "上位机按字上传双字数据时需要按约定顺序合成，顺序搞反会让数值放大约六万倍。",
   "以首字是否高位为开关，两个分支各自把两部分左移后按位或，不共享中间量。所有移位位数为常量，不出现变量移位导致的越界。"),
 "FC_DL_EndianProbe": (
   "现场需要确认控制器实际字节序以决定报文解析方向，但 IEC 语言层没有内存重解释手段。",
   "结论必须是可验证的而不是猜测：IEC 61131-3 的移位与类型转换都是数值语义，与内存储序无关，且标准禁止指针与联合体重解释，因此在纯标准语法下不存在可观测量，函数按库级约定返回小端结论并在头注释列明三条依据。库内所有跨设备件一律显式携带高低序参数，不依赖本件推断结果，从设计上消除对该结论的依赖。"),
 "FC_DL_LwordToDwords": (
   "64 位累计量上传给只支持双字的上位机时需要拆成两个双字。",
   "按开关选择移位截取顺序，低半部用掩码截断，避免 LWORD 到 DWORD 的隐式窄化。返回首块并由出参给出另一块。"),
 "FC_DL_DwordsToLword": (
   "两个双字拼成 64 位累计量时顺序配反会让数值错位 32 位。",
   "两部分各自先做标准宽化转换再按开关决定移位量，最后按位或，全程不出现隐式窄化。"),
 "FC_DL_AngleLerpShort": (
   "转台按最短方向从当前角转到目标角，若按数值差直接插值，从 350 度到 10 度会走 340 度反方向，机械上不可接受。",
   "先把角度差归一到正负 180 的短弧区间再乘插值比例，最后把结果归一到 0 到 360，使任意两端点之间的过渡都走短弧。归一用整圈截断加减修正实现，不用取模，规避负数取模的跨平台差异；比例越界只做钳位不报错，属容错输入。"),
 "FC_DL_AngleQuadrant": (
   "运动规划要按象限决定加减速方向，需要稳定的象限判定并能识别压在坐标轴上的临界角。",
   "把角度先归一到 0 到 360 再按 90 度分档，轴上的判定用与整十度倍数的绝对差比较容差，且象限归类与轴上标志取同一套边界口径，避免出现轴上角被归到前一带而标志又判为轴上的自相矛盾。"),
 "FC_DL_AngleBisector": (
   "两台云台要对同一目标做对称跟踪时，需要两角平分线作为对称轴。",
   "先求短弧差的一半再加到起始角上，短弧归一秒解决钝角情形：若按长弧平分会得到反方向 180 度的镜像轴。结果再归一到 0 到 360 保证出参唯一。"),
 "FC_DL_AngleToCompass": (
   "气象与环控要按 16 方位报风向，直接按角度除 22.5 会在边界处抖动。",
   "先归一到 0 到 360 再平移半个扇区宽度做中心对齐，最后按扇区数取整并折回，保证 359.9 度落在北而不是折回成第 16 带越界。同时给出 8 方位粗档，避免下游再算一次。"),
 "FC_DL_AngleTolInside": (
   "阀门开度到位判定要允许容差，但目标角在 0 度附近时按绝对差比较会把 359 度判成远离目标。",
   "用短弧差判定而不是绝对差，跨零自然正确。容差为负时判参数非法并置码，不做静默取绝对值，让组态错误暴露。"),
 "FC_DL_AngleReflect": (
   "对称机构需要把一侧的角度按轴线镜像到另一侧，直接 2 倍轴角减输入会跑出 0 到 360 区间。",
   "镜像后用整圈截断归一到合法区间，归一时先截断再修正，避免负数取模差异。轴线角与输入角都做非有限拦截。"),
 "FC_DL_AngleUnwrapStep": (
   "卷径累计与多圈绝对值编码器需要把每拍的原始角增量解卷绕后累加，直接累加原始差会在跨越零点时跳变一整圈。",
   "每拍只处理一步增量：把原始值与上一拍值的差归一到正负 180，再把该增量累加到外部持有的累计值上，累计值由调用方持有，纯函数不藏状态。这样跨越零点与跨越整圈都走同一路径，多圈跟踪不会累积误差。"),
 "FC_DL_SinDeg": (
   "机械臂三角函数输入都以度给出，直接调标准正弦要先手工转弧度，现场经常漏转导致结果差 57 倍。",
   "入口做非有限拦截后乘以高精度派常数转弧度再求正弦，派常数用足够位数的字面量而不是近似值，避免在大角度上放大误差。"),
 "FC_DL_CosDeg": (
   "相位补偿计算大量使用余弦且输入是度，需要与正弦同一套派常数口径，否则两者相位对不上。",
   "与正弦件共用同一派常数与同一套非有限拦截口径，保证同角度下正弦平方加余弦平方在一的容差内，便于交叉自检。"),
 "FC_DL_TanDegChk": (
   "正切在 90 度附近发散，直接算会得到极大值并污染下游除法，需要识别不可定义区。",
   "不直接调正切，改用正弦比余弦，先判余弦绝对值是否小于阈值，命中则判不可定义并置码返回零。阈值取 1E-12 量级，使判据与正切的十进制量级对应，可在文档中直接换算。"),
 "FC_DL_AsinDegChk": (
   "反算倾角时输入可能因噪声略微超过一，直接调反正弦在部分平台返回非数，另一些平台钳位，行为不一致。",
   "入口先把输入钳位到负一到一，同时用越界标志记录是否发生钳位，钳位后照常计算并输出角度，让调用方能区分正常与饱和。反三角用反正切恒等式实现，避开部分平台缺失反正弦标准件的问题。"),
 "FC_DL_AcosDegChk": (
   "余弦反算同样存在输入略微越界的问题，且需要与反正弦件行为一致。",
   "沿用同一钳位与越界标志口径，用反正切恒等式实现，保证与反正弦件在同一输入下互补为零到一百八十度区间内的对应值。"),
 "FC_DL_Atan2Deg": (
   "求矢量方位要用四象限反正切，但两输入同时为零时数学上无定义，直接调用会得到平台相关的任意值。",
   "先判双零并置码返回零，再按象限分支把单参反正切修正到 0 到 360，修正只在二三象限与负零情形发生，避免每拍都做多余判断。"),
 "FC_DL_SincSafe": (
   "信号重构要用 sinc 函数，但零点处直接相除会触发除零，得到非数并污染整条曲线。",
   "以小量阈值分段：绝对值大于阈值走正常除法，小于阈值改用泰勒展开的前三项，两段在阈值处连续且误差可控。阈值取 1E-8 量级使展开截断误差远小于单精度分辨率。"),
 "FC_DL_HypotChk": (
   "算斜边时若直接平方相加，输入在万级时中间结果就会超出单精度范围，得到无穷大。",
   "先取绝对值较大者做归一化，把结果写成大值乘以根号下一加小比大平方，全程比值不超过一，中间量永不溢出；大值为零时直接返回零，天然规避除零。"),
 "FC_DL_HystWindow3": (
   "液位要同时监视过高与过低，中间带是正常区，简单的上下限比较分不清刚进带与一直在带内，边界抖动会让输出反复跳。",
   "三个带各用独立门限并带上行下行两套阈值，状态迁移只在越过对应方向的回差边界时发生，输入需携带上一拍状态，纯函数不藏状态。门限须满足低带关断不大于低带开启、高带关断不小于高带开启且低带整体在高带之下，不满足即判参数非法，不做静默重排。"),
 "FC_DL_HystLatchAlarm": (
   "报警要求超限即锁存，值回落后自动消失会让操作工看不到曾经超限，但完全不自动恢复又会让瞬时扰动永久挂住。",
   "置位与复位走两条独立判据：超上限门限置位且自保持，回落到回差门限以下也不自动清除，只有复位指令才清，复位优先级高于置位。状态由调用方持有的入参出参承载，纯函数不藏内存，便于多实例复用与在线观察。"),
 "FC_DL_HystCounterStep": (
   "要统计工件在三个温区之间来回跨越的次数，用边沿计数会把同一带内的抖动也计入。",
   "以带位记忆取代边沿判定：只有从低带跨到高带才加一、从高带跨到低带才减一，带宽内的抖动不改变带位因而不计数。带位作为入参出参由调用方持有，计数结果按上下限钳位，防止长时间累积溢出。"),
 "FC_DL_HystTimeQualified": (
   "压力到达判定不能看瞬时值，管路水锤会造成瞬时超压，必须持续满足一定时间才认为真的到位。",
   "把时间确认交给调用方持有的定时器累计值，本件只做判定与累计值回写：原始条件满足则累计增加，不满足则清零，累计超过设定时间才翻转输出。这样定时器不藏在本件内，调用方可统一周期刷新，避免多处各自起定时器。"),
 "FC_DL_ClampDintChk": (
   "位置给定需要限幅，但上层还要知道是被上限截断还是被下限截断，只看限幅后的值分不清是正常到位还是被挡住。",
   "限幅与方向标志在同一处判定：小于下限输出下限并置负一，大于上限输出上限并置正一，区间内原样输出并置零。上下限配反判参数非法，不做自动交换，让组态错误暴露。"),
 "FC_DL_WrapToRange": (
   "相位与角度类周期量需要卷绕到指定区间，区间宽度由组态给出，若宽度为零或负则取模会除零。",
   "先判区间宽度是否为正，非正则判参数非法并返回下界；再用整圈截断把输入缩到区间宽度内并平移到下界，全程只用乘法与截断，不依赖负数取模的实现差异。"),
}

def main():
    d = json.load(open(REG, encoding='utf-8'))
    have = {c['name'] for c in d['components']}
    added = []
    for (name, cat, typ, cx, tags) in ITEMS:
        if name in have:
            print('SKIP-DUP', name); continue
        fp = os.path.join(r'C:\Library', cat, name + '.st')
        if not os.path.exists(fp):
            print('MISSING-FILE', name); continue
        d['components'].append({
            "name": name, "category": cat, "type": typ, "file_path": fp,
            "function_tags": tags + ["r76"],
            "complexity": cx, "registered_at": NOW, "l2_status": "l2-pass",
            "origin": {"mode": "internal", "source": "self-cleanroom / oscat-semantic (MIT ref, no code copied)",
                       "license": "MIT", "ref_tag": tags[0]},
        })
        added.append(name)

    # counts 重算
    cnt = {}
    for c in d['components']:
        cnt[c['category']] = cnt.get(c['category'], 0) + 1
    d['counts'] = cnt
    d['total_components'] = len(d['components'])
    d['version'] = VERSION
    d['last_updated'] = NOW
    assert sum(cnt.values()) == d['total_components'], (cnt, d['total_components'])
    json.dump(d, open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('REGISTRY', d['total_components'], cnt)
    json.dump({"added": added}, open(os.path.join(STAGE, '_r76_added.json'), 'w', encoding='utf-8'), ensure_ascii=False)
    print('ADDED', len(added))

    # ---- JSONL ----
    by = {c['name']: c for c in d['components']}
    rows = []
    for n in added:
        fp = by[n]['file_path']
        src = open(fp, encoding='utf-8').read()
        if n not in SPEC:
            print('NO-SPEC', n); continue
        instr_txt, arch_txt = SPEC[n]
        rows.append({
            "instruction": instr_txt + " 请用 IEC 61131-3 标准 ST 实现，保证 CODESYS / TwinCAT / InoProShop 跨平台可编译；边界条件（除零、越界、非法量程、非有限值、超时）必须有明确处理并给出错误码。",
            "architecture_thought": arch_txt + " 变量逐条中英双语注释，出参统一 eErr/bError/bValid，错误码分段不与同族件重码。",
            "output": src,
        })
    with open(OUT, 'a', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print('JSONL_APPENDED', len(rows))

    # ---- 历史 25 条缺 output 补写 ----
    lines = open(OUT, encoding='utf-8').read().split('\n')
    fixed, still = 0, 0
    outl = []
    for ln in lines:
        if not ln.strip():
            outl.append(ln); continue
        try:
            o = json.loads(ln)
        except Exception:
            outl.append(ln); continue
        if not o.get('output'):
            # 从 registry 找同名件
            cand = None
            for nm, c in by.items():
                if nm in o.get('instruction', '') or nm in o.get('architecture_thought', ''):
                    cand = c; break
            if cand and os.path.exists(cand['file_path']):
                o['output'] = open(cand['file_path'], encoding='utf-8').read()
                if o['output']:
                    fixed += 1
                outl.append(json.dumps(o, ensure_ascii=False)); continue
            still += 1
            outl.append(ln); continue
        outl.append(ln)
    open(OUT, 'w', encoding='utf-8').write('\n'.join(outl))
    print('BACKFILL output fixed=', fixed, 'still_missing=', still)

    n = 0; noout = 0
    for ln in open(OUT, encoding='utf-8'):
        if not ln.strip(): continue
        n += 1
        try:
            if not json.loads(ln).get('output'): noout += 1
        except Exception:
            pass
    print('JSONL_TOTAL', n, 'no_output', noout)

if __name__ == '__main__':
    main()
