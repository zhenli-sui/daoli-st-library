#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r52.py —— R52 主控直跑收口（R335）：注册 20 新件 + 2 返修升版 + JSONL 增量，原子写回。"""
import io, os, json, shutil

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
NOW = "2026-11-20T13:05:00+08:00"

NEW = [
 ("FC_DL_BitCountOnes","DL_Base","FC",2,["lgf-bitlogic","popcount","clean-room"]),
 ("FC_DL_WrapIndexNeg","DL_MathData","FC",2,["ring-window","index-norm","clean-room"]),
 ("FC_DL_LogDomainNormalize","DL_MathData","FC",3,["oscat-math","log-domain","clean-room"]),
 ("FC_DL_PriorityEncodeWord","DL_Base","FC",2,["lgf-bitlogic","priority-encode","clean-room"]),
 ("FC_DL_ZnTune","DL_Algo","FC",3,["modpid-tune","zn-method","clean-room"]),
 ("FB_DL_SchmittTriggerGap","DL_Base","FB",2,["lgf-comparator","hysteresis","clean-room"]),
 ("FB_DL_EdgeIntervalMeter","DL_Base","FB",3,["lgf-dateandtimer","interval-measure","clean-room"]),
 ("FB_DL_AdaptiveDeadbandZone","DL_Algo","FB",3,["modpid-deadband","adaptive","clean-room"]),
 ("FB_DL_DerivativeNoiseWeight","DL_Algo","FB",3,["modpid-deriv","noise-weight","clean-room"]),
 ("FB_DL_ControlOutputSlewWatch","DL_Algo","FB",3,["lgf-measurement","slew-rate","clean-room"]),
 ("FB_DL_PidParamDriftAudit","DL_Algo","FB",3,["styleguide-audit","param-drift","clean-room"]),
 ("FB_DL_BrakeResistorThermal","DL_Device","FB",4,["rockwell-aoi","thermal-i2t","clean-room"]),
 ("FB_DL_PressureSwitchChatter","DL_Device","FB",3,["ne107","chatter-diag","clean-room"]),
 ("FB_DL_MeterPulseLossDetect","DL_Device","FB",3,["oscat-network","pulse-loss","clean-room"]),
 ("FB_DL_HeatTraceCircuitMon","DL_Device","FB",4,["isa182","loop-consistency","clean-room"]),
 ("FB_DL_AxisJerkLimitCheck","DL_Motion","FB",4,["plcopen-limits","jerk-limit","clean-room"]),
 ("FB_DL_AxisHomeRepeatVerify","DL_Motion","FB",4,["plcopen-homing","repeatability","clean-room"]),
 ("FB_DL_AxisSoftLimitPredict","DL_Motion","FB",4,["s7-motion","softlimit-predict","clean-room"]),
 ("FB_DL_MakeupWaterDosing","DL_Process","FB",3,["roadmap-pool","water-dosing","clean-room"]),
 ("FB_DL_DieBinCounter","DL_Process","FB",3,["roadmap-pool","semi-backend","clean-room"]),
]
REWORK = [
 ("FB_DL_ValveSeatLeakWatch","DL_Device","1.0.1"),
 ("FB_DL_MoveResumeSeg","DL_Motion","1.0.2"),
]
INSTR = {
 "FC_DL_BitCountOnes":"设备状态字/报警字常以位串形式上报，上位需统计置 1 位数以判断同时故障路数或投运台数，要求跨平台纯函数且不得依赖厂商内建 popcount；输入含任意位宽，须对 0 与全 1 两端极值给出确定结果，位宽超过容器时由调用侧钳位；纯函数无状态可重入。",
 "FC_DL_WrapIndexNeg":"环形窗口滑动时下标计算常出现负余数（IEC MOD 对负数返回负值），若直接用作数组下标会越界崩溃；需要一个统一的负值模归正纯函数，支持 0-based 与 1-based 两种口径，模数为 0 或负数时须显式拒绝并返回安全下标；纯函数无状态。",
 "FC_DL_LogDomainNormalize":"水质与化工过程量（pH、离子浓度、浊度）呈对数分布，线性归一化会把工况挤在两端，需按对数域映射到 0~1 便于趋势与报警带统一定义；输入 ≤0 属定义域外须拒绝或钳到下限，底数须校验（>0 且 ≠1），输出非有限时给确定值；纯函数无状态。",
 "FC_DL_PriorityEncodeWord":"多路故障字需按优先级取首个置位路号驱动首出报警（first-out），要求同时支持最高位优先与最低位优先两种口径，无任何置位时返回哨兵 0 号以免上位误判为第 1 路故障；位宽与容器对齐，越界不可发生；纯函数无状态可重入。",
 "FC_DL_ZnTune":"现场整定常先用临界比例度法粗调：由临界增益 Ku 与临界振荡周期 Tu 直接推算 PID 三参，作为投入自整定前的起点；Ku/Tu 非有限或 ≤0 须拒绝并保持上拍输出，三种回路类型（P/PI/PID）按组态选择，输出做上下限钳位防离谱参数下发；纯函数无状态。",
 "FB_DL_SchmittTriggerGap":"模拟量开关量转换常在阈值附近抖动（如液位、压力），单一阈值会造成输出频繁翻转；需带回差的双阈值整形，上/下阈值可组态且强制上行阈值大于下行，组态非法时按安全侧输出；输出沿与当前状态分离，供下游沿检测取用；周期刷新无内部锁存穿透。",
 "FB_DL_EdgeIntervalMeter":"产线节拍与占空比测量需要统计相邻同向沿的时间间隔、周期与高电平占空比，同时判断「长时间无沿」的停机状态；要求间隔用 TIME 累加不受扫描周期量化影响，抖动统计给出最大/最小值，无沿超时置停机标志；复位清全部统计但不清时基。",
 "FB_DL_AdaptiveDeadbandZone":"回路在低负荷时噪声小、高负荷时噪声大，固定死区要么在低负荷丢精度要么在高负荷抖阀；需按在线噪声幅值（滑动窗绝对偏差均值）自适应整定死区宽度，死区随噪声升降但有上下限与变化率限制，避免整定过程自身引起振荡；输出保持上一有效值。",
 "FB_DL_DerivativeNoiseWeight":"微分项对测量噪声极其敏感，高频噪声大时 Kd 全额投入会把噪声放大成阀位抖动；需在线估计信号高频能量占比，超阈时按比例衰减有效 Kd 并给出降权系数供上位观察，噪声回落后平滑恢复；衰减与恢复均设变化率限制防参数跳变。",
 "FB_DL_ControlOutputSlewWatch":"阀门/风门执行器的行程速率异常是卡涩与爬行的早期征兆：输出变化率长期偏低（爬行）或频繁正反换向（振荡）都应告警；需按窗口统计输出变化率均值与换向次数并分档（正常/注意/异常），分档带迟滞防临界抖动，告警只上报不干预控制。",
 "FB_DL_PidParamDriftAudit":"回路参数被现场随意改动是工艺波动的隐性根因，需把投运基准快照与现行参数持续比对，任一参数越差即留痕并计数；基准可重设（需确认位），留痕环形存档供追溯，审计只读不写控制参数；参数为 REAL 比较须用容差，避免末位噪声误报。",
 "FB_DL_BrakeResistorThermal":"变频器制动电阻按 I²t 累积热量，短时频繁制动会远超额定发热而外壳温度尚未上升，仅靠温度传感器会滞后烧毁；需按制动占空与电流平方积分估算温升，配合冷却时间常数做指数衰减，估算温度越限分级预警并在极值时请求禁止制动；参数非法时按最保守处理。",
 "FB_DL_PressureSwitchChatter":"压力开关在临界压力附近会高频抖动，触点寿命与信号可信度同时下降；需在统计窗内计翻转次数并按阈值分档（正常/注意/故障），同时给出建议阻尼时间常数供维护参考；窗口用 TON 自复位到时结算（无条件刷新），分档带迟滞防档位抖动。",
 "FB_DL_MeterPulseLossDetect":"脉冲式流量计在接线松动或叶轮卡滞时会丢脉冲，仅看瞬时流量在低流量段无法区分「真无流」与「丢脉冲」；需以指令阀位/泵状态为参照，比对期望脉冲率与实际脉冲率，偏差持续超限即报丢脉冲并累计丢包估计；低流量死区与启停过渡期须屏蔽误报。",
 "FB_DL_HeatTraceCircuitMon":"电伴热回路故障分两类：断缆（无电流）与空烧（有电流但管道温升无响应），后者更危险且电流表看不出来；需同时监视电流存在性与温升响应率，二者组合成四象限判据（正常/断缆/空烧/保温失效），判定需在升温窗口内完成并带迟滞；温度信号非有限按失效处理。",
 "FB_DL_AxisJerkLimitCheck":"高速贴装/搬运轴若加加速度（jerk）指令过大，机械冲击会导致吸嘴掉件与导轨磨损，而位置与速度环往往来不及报警；需对每拍指令做二阶差分得 jerk，超限即钳位并累计超限次数，钳位须保证位置连续（不产生台阶），同时输出钳位标志供轨迹规划回退。",
 "FB_DL_AxisHomeRepeatVerify":"回零重复性劣化是编码器松动、联轴器背隙与挡块变形的综合征兆，单次回零位置看不出来；需连续 N 次回零记录位置并算均值与标准差（或极差），超散即拒绝放行生产并置码，样本不足时不结论；统计用锁存副本，禁止与实时位置镜像混用。",
 "FB_DL_AxisSoftLimitPredict":"软限位通常只在越界后才报错，高速轴按当前速度与减速度已无法在限位前停住；需按当前速度、减速度与响应延时预判剩余可停距离，接近限位时提前请求减速并给出建议减速度，预测越界即输出急停请求；速度方向为 0 时不预测（避免除零）。",
 "FB_DL_MakeupWaterDosing":"循环水系统按补水量定比投加缓蚀阻垢药剂：补水流量累计到设定体积触发一次加药，加药量按浓度与补水体积换算并受泵额定流量限幅；加药期间重复触发须排队而非叠加，药箱低液位联锁停泵；累计量断电重启后从零起算须有明确说明。",
 "FB_DL_DieBinCounter":"晶粒分箱按 Bin 码计数，满箱须在达到上限前预警并切换空箱，切换瞬间的落料归属必须唯一（不得重复计入两箱）；满箱阈值可按箱型组态并有提前预警量，切箱请求未响应时禁止继续落料；各 Bin 计数与总量须自洽（总和 = 落料总数）。",
}
ARCH = {
 "FC_DL_BitCountOnes":"纯函数位统计算法：以容器位宽做无符号右移循环，逐位与 1 掩码累加，位移次数由常量按位宽给定，避免依赖厂商 POPCOUNT 内建；全 0 与全 1 两端极值由位移次数常量保证不越界；无状态、无定时器，可重入，位宽不符由调用侧钳位（文档注明契约）。",
 "FC_DL_WrapIndexNeg":"纯函数模运算归一：先做 IEC MOD 取余，再对负余数补模一次归正（`IF r < 0 THEN r := r + m`），避免用两次 ABS 之类的方言写法；m ≤ 0 直接返回安全下标 0 并置拒绝标志；1-based 口径通过入口偏移参数统一处理，出口保证落在 [0, m-1] 或 [1, m]。",
 "FC_DL_LogDomainNormalize":"纯函数对数映射：先做定义域三闸（x > 0、底数 >0 且 ≠1、上下限单调），再取 LOG 后线性映射到 0~1，出口钳位防止 LOG 精度导致的微小越界；非有限输入走故障分支返回下限哨兵；常量集中声明便于跨平台调容差；无状态可重入。",
 "FC_DL_PriorityEncodeWord":"纯函数优先编码：高位优先用「自顶向下首次置位即返回」的 FOR 递减循环，低位优先用递增循环，两者共用出口哨兵逻辑；无置位返回 0 号哨兵（合法路号从 1 起，文档明示契约）；循环上下界由常量按位宽给定，无数组访问故无越界风险。",
 "FC_DL_ZnTune":"纯函数参数换算：先做 Ku/Tu 有效性闸（有限且 >0），再按回路类型 CASE 分派三组经典系数，输出三参各自钳位到工程上下限；无效输入保持上拍由 FB 包装层负责（本件纯函数返回有效标志 + 原值回送）；常量集中声明便于按工艺族替换系数。",
 "FB_DL_SchmittTriggerGap":"双阈值滞回整形架构：状态量 _bOut 为唯一真值源，上行需 fIn ≥ fThrHigh、下行需 fIn ≤ fThrLow，中间带保持；组态校验（High > Low 且均有限）在复位沿一次性锁存，非法则强制安全侧 FALSE 并置码；输出沿由 R_TRIG 对 _bOut 派生（无条件刷新），副本与实时镜像分离。",
 "FB_DL_EdgeIntervalMeter":"时基+统计双段架构：段 0 无条件刷新 R_TRIG（被测沿与内部窗口沿），段 1 用 TIME 差值算间隔并更新最大/最小与占空比累加，段 2 无沿超时 TON 判停机；复位清统计量与时基同时清，避免跨复位残留；所有除法前先判分母（周期 >0）。",
 "FB_DL_AdaptiveDeadbandZone":"自适应死区架构：滑动窗内累加 |x - 上拍输出| 得噪声估计，噪声估计乘增益得目标死区，再经变化率限制与上下限钳位后生效；死区内输出保持（写回锁存副本而非实时输入，R38 范式）；窗用自复位 TON 到时结算清累加（FB33-2）；噪声为 0 时退化为最小死区防除零。",
 "FB_DL_DerivativeNoiseWeight":"高频能量估计+降权架构：对测量做一阶差分取绝对值，滑动窗均值作为高频能量表征，与阈值比得分档权重 w∈[0,1]；有效 Kd = Kd × w，w 的变化经受限斜坡平滑（防参数跳变）；降权系数与档位分离输出供上位观察；窗到时结算用自复位 TON，无条件刷新。",
 "FB_DL_ControlOutputSlewWatch":"输出行为统计架构：每拍算 Δu = u - u_prev 并累加绝对变化量，同时以符号变化计数得换向次数；窗口 TON 自复位到时结算速率均值与换向率，按双判据 CASE 分档（含 ELSE 兜底），分档带迟滞带防临界抖动；仅上报不干预，输出为只读结论与计数。",
 "FB_DL_PidParamDriftAudit":"基准快照+容差比对架构：基准参数在投入沿（或重设确认沿）从现行参数整体拷贝为锁存副本，之后每拍以容差比较差值；越差项逐项置位并累加漂移计数，事件写入环形留痕数组（写指针环回钳位，R193 配套）；重设需双确认位齐全，审计路径只读不写控制参数。",
 "FB_DL_BrakeResistorThermal":"I²t 热模型架构：制动期间按电流平方×占空累加能量，非制动期按一阶指数（乘冷却系数）衰减，得估算温升；温升对分级阈值（注意/预警/禁止）比较并带迟滞，极值输出禁止制动请求；模型参数（热容、时间常数）非法时取最保守值并置码；衰减用 REAL 乘幂近似避免 EXP 方言差异。",
 "FB_DL_PressureSwitchChatter":"窗口翻转计数架构：对开关量做 R_TRIG/F_TRIG 双沿计数（无条件刷新），统计窗用自复位 TON 到时结算翻转率并清计；翻转率按两阈值分三档（含 ELSE 兜底），档位带迟滞；同时按翻转率反算建议阻尼时间常数输出给维护；复位清计数与档位。",
 "FB_DL_MeterPulseLossDetect":"参照比对架构：以泵运行/阀位开度为参照估算期望脉冲率（额定流量×开度），与实际脉冲率（窗口脉冲数/窗口时长）比较得相对偏差；偏差持续超限（TON 到时）才报丢脉冲防瞬态误报；启停过渡期与低流量死区内屏蔽；丢包估计按偏差×窗口脉冲累加并限幅。",
 "FB_DL_HeatTraceCircuitMon":"四象限判据架构：电流存在性（>阈）与温升响应率（ΔT/Δt 超阈）两布尔组合成 CASE 四分支（正常/断缆/空烧/保温失效）+ ELSE 兜底；判定在升温窗口 TON 内完成（无条件刷新），窗口未到不结论；温度非有限或电流信号失效按失效分支处理并置码；结论带迟滞防跳变。",
 "FB_DL_AxisJerkLimitCheck":"二阶差分钳位架构：以位置指令做两次数值差分得速度与加速度，再由加速度差分得 jerk；jerk 超限时按限幅反算允许的位置增量并输出钳位后指令，保证位置连续（钳位只削增量不跳变）；超限次数与最大 jerk 累加输出；分母（Δt）为零时跳过本拍不钳位（防除零）。",
 "FB_DL_AxisHomeRepeatVerify":"样本统计架构：每次回零完成沿取位置存入环形样本窗（写指针环回钳位，R194 时间序访问），样本满 N 后算均值与极差/标准差，超散即置拒绝放行并锁存至复位；样本为锁存副本与实时位置镜像严格分离（R38）；标准差用极差近似避免开方精度问题，分母（N-1）恒 >0。",
 "FB_DL_AxisSoftLimitPredict":"运动学预判架构：由当前速度 v 与减速度 a 算停车距离 s = v²/(2a) + v·tResp，与剩余行程比较；剩余行程不足即提前请求减速并按比例给建议减速度，已不可能停住则输出急停请求；v 与 a 为 0 或符号异常时跳过预判（防除零与方向误判）；请求为单拍脉冲防粘滞。",
 "FB_DL_MakeupWaterDosing":"累计触发+定比投加架构：补水流量按扫描周期累加（Δt 用 TIME 差），累计到设定体积沿触发一次投加并扣减累计；投加量 = 体积 × 浓度，泵流量限幅后换算为投加时长（TON 定宽脉冲）；投加期间新触发置待处理位而非叠加；药箱低液位联锁立即停泵并置码。",
 "FB_DL_DieBinCounter":"分箱计数与切箱仲裁架构：落料沿按 Bin 码分派计数，满箱前预警量先置预警位，达上限置切箱请求并禁止继续落料（落料闸与计数同拍判定，保证唯一归属）；切换确认沿清当前箱计数并切空箱，各 Bin 计数与总数自洽校验（总和对不上置码）；CASE 全分支含 ELSE 兜底。",
}
REWORK_NOTE = {
 "FB_DL_ValveSeatLeakWatch":"R52 返修 v1.0.1：环形窗回归改「最旧槽起按时间序环回遍历」（R194 范式），删写入期 `_aX[_nHead] := DINT_TO_LREAL(_nHead)` 的头游标误用，补 _nOldest 推导 2 行、求和 X 用循环序 _i、Y 用 _nIdx 环回取槽，消除窗回卷后 X/Y 错配导致的斜率符号翻转（安全侧漏报）；未采用 _nSeq 全局序号方案（x~1e6 时 Σx² 灾难性相消）。",
 "FB_DL_MoveResumeSeg":"R52 文档级 v1.0.2：fStartRst 实测正文零引用（仅头注释与声明），按总监裁定保留引脚契约、注释标 reserved 并说明起点语义由 fPosNow 实时快照承担；逻辑零变更，不改大版本。",
}
ARCH_RW = {
 "FB_DL_ValveSeatLeakWatch":"环形窗 LS 回归时间序架构：观测值按槽位环回存储，自变量由「最旧槽 + 循环序」在求和时现算（不落盘 X 数组），保证窗回卷后 X/Y 严格对应；斜率与截距同款映射，判据符号与斜率定义一致；本版消除回卷符号翻转，残余风险仅在窗容量组态 <3 时的退化分支（已显式拒绝）。",
 "FB_DL_MoveResumeSeg":"恢复段方向迁相锁存架构（R51 已修）：_bDir 进入 eResume 相一次性锁存，越目标以剩余量符号反号收口；本版仅把未使用的 fStartRst 引脚标注 reserved，明确起点语义由 fPosNow 实时快照承担，避免现场误接。",
}

def main():
    shutil.copy2(REG, REG + ".bak_r52")
    shutil.copy2(JSONL, JSONL + ".bak_r52")
    reg = json.load(io.open(REG, encoding="utf-8"))
    comps = reg["components"]
    names = {c["name"].lower() for c in comps}
    added, skipped = [], []
    for name, cat, typ, cx, tags in NEW:
        if name.lower() in names:
            skipped.append(name); continue
        p = os.path.join(ROOT, cat, name + ".st")
        lines = len(io.open(p, encoding="utf-8").read().strip().splitlines())
        comps.append({"name": name, "category": cat, "type": typ,
                      "file_path": p, "function_tags": tags + [name.lower()],
                      "complexity": cx, "version": "1.0.0",
                      "registered_at": NOW, "line_count": lines,
                      "code_segment": "", "source": "r52-plan"})
        added.append(name)
    if skipped:
        print("SKIP:", skipped)
    rw_done = []
    for name, cat, ver in REWORK:
        for c in comps:
            if c["name"] == name:
                c["version"] = ver
                p = os.path.join(ROOT, cat, name + ".st")
                c["line_count"] = len(io.open(p, encoding="utf-8").read().strip().splitlines())
                rw_done.append(name + "@" + ver); break
    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["counts"] = {k: counts.get(k, 0) for k in
                     ("DL_Base","DL_MathData","DL_Algo","DL_Device","DL_Motion","DL_Process")}
    reg["total_components"] = len(comps)
    reg["version"] = "2.44.0"
    reg["last_updated"] = NOW
    tmp = REG + ".tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="") as f:
        json.dump(reg, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, REG)
    print("registry: %d comps, counts=%s, added=%d, rework=%s"
          % (len(comps), reg["counts"], len(added), rw_done))
    # ---- JSONL ----
    lines = io.open(JSONL, encoding="utf-8").read().splitlines()
    out, reinj = [], []
    rwdict = {n: c for n, c, v in REWORK}
    for ln in lines:
        if not ln.strip():
            continue
        obj = json.loads(ln)
        nm = None
        for rname, _, _ in REWORK:
            if rname in (obj.get("instruction","") + obj.get("output","")):
                nm = rname; break
        if nm and nm not in reinj:
            src = io.open(os.path.join(ROOT, rwdict[nm], nm + ".st"), encoding="utf-8").read()
            obj["output"] = src
            obj["instruction"] = obj["instruction"].rstrip() + "｜" + REWORK_NOTE[nm]
            obj["architecture_thought"] = ARCH_RW[nm]
            reinj.append(nm)
        out.append(json.dumps(obj, ensure_ascii=False))
    ap = 0
    for name, cat, typ, cx, tags in NEW:
        if name in skipped:
            continue
        src = io.open(os.path.join(ROOT, cat, name + ".st"), encoding="utf-8").read()
        out.append(json.dumps({"instruction": INSTR[name], "architecture_thought": ARCH[name], "output": src}, ensure_ascii=False))
        ap += 1
    tmp2 = JSONL + ".tmp"
    with io.open(tmp2, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(out) + "\n")
    os.replace(tmp2, JSONL)
    bad = 0
    for ln in io.open(JSONL, encoding="utf-8").read().splitlines():
        if not ln.strip(): continue
        try:
            o = json.loads(ln)
            if not o.get("output") or len(o.get("instruction","")) < 80 or len(o.get("architecture_thought","")) < 100:
                bad += 1
        except Exception:
            bad += 1
    print("jsonl: lines=%d appended=%d reinjected=%s badjson/short=%d" % (len(out), ap, reinj, bad))
    return 0 if bad == 0 else 1

main()
