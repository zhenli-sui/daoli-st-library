#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r58.py —— R58 主控直跑收口（R335）：机检 21 件 + 注册 16 新件 + JSONL 增量 + ROADMAP + 文档追加。"""
import io, os, json, shutil, re, sys, glob

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
ROADMAP = os.path.join(ROOT, "ROADMAP.md")
STAGE = os.path.join(ROOT, "_Staging_Raw", "2026-11-21")
NOW = "2026-11-21T05:10:00+08:00"

NEW = [
 ("FB_DL_VoteKooN","DL_Base","FB",3,["self-std","voting","moon","fail-safe","clean-room"]),
 ("FB_DL_SimInputBank","DL_Base","FB",3,["self","simulation","input-forcing","bypass","clean-room"]),
 ("FC_DL_ThermocoupleLinearization","DL_MathData","FC",3,["roadmap-p1","thermocouple","its-90","linearization","clean-room"]),
 ("FB_DL_SkewKurtosisCalc","DL_MathData","FB",3,["t2-1-lgf-math","skewness","kurtosis","welford","clean-room"]),
 ("FC_DL_SolveLinear3","DL_MathData","FC",3,["t2-1-lgf-math","linear-solve","gauss","clean-room"]),
 ("FC_DL_PmvComfortIndex","DL_Algo","FC",3,["t1-oscat-building","pmv","ppd","iso7730","clean-room"]),
 ("FB_DL_SoftStarterDrive","DL_Device","FB",4,["t2-2-lbp","soft-starter","ramp-start","motor-driver-if","clean-room"]),
 ("FB_DL_ElectricLinearActuator","DL_Device","FB",3,["t2-2-lbp","linear-actuator","stall","limit","clean-room"]),
 ("FB_DL_OptimalStartStop","DL_Algo","FB",4,["t1-oscat-building","optimal-start","hvac","self-learn","clean-room"]),
 ("FB_DL_PeriodicDisturbComp","DL_Algo","FB",4,["self","repetitive-control","internal-model","disturbance","clean-room"]),
 ("FB_DL_CondensateDrainSeq","DL_Device","FB",3,["t2-2-lbp","condensate","drain","seq","clean-room"]),
 ("FC_DL_CamTableGenSeg","DL_Motion","FC",3,["t1-6-plcopen","cam-table","segment-gen","clean-room"]),
 ("FB_DL_AxisSafetyStateMon","DL_Motion","FB",3,["t1-6-plcopen","safety-mon","sto","sls","clean-room"]),
 ("FB_DL_GowningRoomSeq","DL_Process","FB",3,["roadmap-p2","gowning","interlock","cleanroom","clean-room"]),
 ("FB_DL_MaterialHoldTimeEnforce","DL_Process","FB",3,["self","hold-time","isa88","ng-latch","clean-room"]),
 ("FB_DL_FirstArticleLock","DL_Process","FB",3,["self","first-article","fa-lock","changeover","clean-room"]),
]
REPAIR = [
 ("FB_DL_EncoderQuadCount","DL_Base"),
 ("FC_DL_RmsCalc","DL_MathData"),
 ("FB_DL_PassboxInterlockSeq","DL_Process"),
 ("FB_DL_NightPurgeSeq","DL_Process"),
 ("FC_DL_PowIntSat","DL_MathData"),
]
INSTR = {
"FB_DL_VoteKooN":"安全回路多传感器表决需要 N 中取 K 而非固定 2oo3：输入 N 路通道布尔与故障掩码，K 值可组态，当有效通道中通过数达到 K 判通过、低于 K 判跳闸；通道故障掩码把坏点剔除出表决基数，有效通道数不足以支撑 K 时按组态语义给出组态故障失效安全；通过数带迟滞防临界抖动，通道数与 K 越界钳位并置组态故障，输出表决态/跳闸/组态故障与有效通道数。",
"FB_DL_SimInputBank":"调试与试运行阶段需要在不停真实设备的前提下用手动假值替代真实输入：八通道仿真组，任一通道投入仿真即用注入值旁路真实采样并锁存仿真标志，退出仿真自动回真实值；投入与退出都走带沿确认，禁止运行态直接切换引发执行器跳变，仿真标志集中输出供上位与联锁识别测试态，通道号越界拒绝不误伤邻通道。",
"FC_DL_ThermocoupleLinearization":"热电偶测温回路需要把 mV 电势与温度双向换算：K/N/S 三分型，按 ITS-90 公开参考分度表特征点折线插值实现毫伏转温度与温度转毫伏双向；电势或温度越出分型量程置越域标志不出值，非有限输入拒绝，分型用枚举 CASE 分派各型节点表并含 ELSE 兜底；折线特征点全量集中声明不写魔数，精度口径在头注释如实声明。",
"FB_DL_SkewKurtosisCalc":"质量数据分布形态需要偏度峰度在线统计而非离线批量：Welford 高阶矩递推逐样本更新均值方差三阶四阶中心矩，偏度峰度按样本量门槛输出，样本量不足时置未就绪标志；非有限样本剔除并计数不污染统计，复位清全部累量，数值增长用增量式防大数相消，门槛与输出标志齐全供上位判可用性。",
"FC_DL_SolveLinear3":"标定与坐标变换常需解三阶线性方程组 Ax=b：部分主元高斯消元，选列最大主元提高数值稳定性，主元绝对值低于相对奇异阈值判奇异不出解；系数或右端非有限拒绝，奇异与非有限置无效标志，回代按消元后的上三角求解，全程无平台矩阵库依赖，纯函数可重入由调用方持系数。",
"FC_DL_PmvComfortIndex":"HVAC 舒适度优化需要量化指标而非只控温度：按 ISO 7730 公开 Fanger 六参数（代谢率、服装热阻、空气温度、辐射温度、风速、湿度）计算 PMV 与 PPD；服装表面温度用定点迭代求稳态（迭代次数上限防不收敛），六参数先做域闸门越界钳位并置越域标志，非有限拒绝，输出 PMV/PPD 与输入有效性供目标函数使用。",
"FB_DL_SoftStarterDrive":"大功率电机软启动需要晶闸管斜坡升压并按反馈确认旁路：实现既有 I_DL_MotorDriver 接口补齐 DOL/星三角/软启/变频四启动家族；启动相按斜坡推进电流限幅，达到全压且运行反馈确认后合旁路接触器，启动超时判堵转锁存故障；停止相撤旁路再撤斜坡，命令与反馈分离校验，旁路反馈不一致延迟判故障，接口不新建与族内三件同契约。",
"FB_DL_ElectricLinearActuator":"无位置反馈电动推杆需要纯时间/电流双模判定行程：到位判定用运行电流回落进窗确认，堵转用电流持续超限加超时双判据锁存，行程两端限位信号互锁且矛盾判传感器坏；运动命令与到位/堵转/限位三态出口分离，非有限电流拒绝参与判定并置传感器坏，到位与堵转判据均带去抖窗防瞬时误判。",
"FB_DL_OptimalStartStop":"大型建筑冷热惰性大需要提前启停预调度节能：按室内外温差与目标温度差估算最佳提前量，启动时刻随经验系数在线修正（修正限幅防漂移），达到设定提前退出防过调；温差或参数非有限退化为固定提前量并置降级标志，学习系数钳位在安全区间，输出建议启停时刻与就绪标志供上层日程调度，只建议不直接启停设备。",
"FB_DL_PeriodicDisturbComp":"轧辊偏心与卷筒周期张力等周期扰动用反馈环收敛慢：内模原理重复控制补偿器，按扰动周期建环形延迟线逐拍正反馈累加，输出与实时误差叠加前馈抵消；周期与延迟线槽位数匹配校验，收敛增益与遗忘因子钳位防爆振，扰动周期变更沿重建延迟线清历史，非有限误差拒绝参与累加，与DisturbanceObserver 非周期观测分工互引。",
"FB_DL_CondensateDrainSeq":"储气罐与空压机冷凝水积存需自动排污：定时与液位双触发任一满足即启动排放顺控，开阀排放后必须收到排放确认反馈才收口，超时未确认判阀故障锁存并禁止下一轮自动排放；排放最小间隔防频开，液位信号非有限判传感器坏按保守转定时口径，手动强制优先于自动，输出排污中/故障/累计排放次数。",
"FC_DL_CamTableGenSeg":"凸轮表从零手填易出错且段型不光滑：按边界点与段型自动生成点列，线性/五次多项式/摆线三类段型，边界连续光滑；逐点单调自检，主从位移区间与点数越界钳位，退化区间拒绝生成并置无效，输出点列与自检结果供 CamTableValidate 前置校验，段型枚举 CASE 分派含 ELSE 兜底，纯计算无状态。",
"FB_DL_AxisSafetyStateMon":"轴侧安全功能（STO/SLS/SOS）需要监视反馈一致而非另发命令：把驱动器安全状态字按固定掩码逐位比对期望组态，不一致持续去抖窗后分类锁存（使能丢失/功能激活/反馈矛盾），固定掩码禁运行期移位防误组态；仅监视零命令输出，状态字非有限或含保留位判通信坏按最保守处理，输出分类诊断供安全回路上层裁决。",
"FB_DL_GowningRoomSeq":"洁净室更衣室人流需要顺控与双门互锁：更衣流程按进入、更衣、完成、退出四相推进，更衣时限超时提醒并允许复位重计，双门互锁不变量在每相出口显式写死；更衣完成未退出不得放行外门，急停火警优先解除许可置中止态，门磁矛盾判传感器坏按最保守双门锁，与人淋室/传递窗两件构成人流三件分工互引。",
"FB_DL_MaterialHoldTimeEnforce":"中间品与批次有保持时限，超时限只能复检放行或判废：物料进站启动保持计时，超时限判 NG 锁存禁止直通放行，复检确认沿才允许放行并记台账；时限参数越界钳位，计时基准非有限拒绝并置时钟坏，复位不自动清 NG（须复检路径），输出保持剩余时间/超时态/放行许可与 NG 台账计数。",
"FB_DL_FirstArticleLock":"批量生产前首件检验是强制闸口：上电默认锁定禁止批量运行，首件放行沿解锁放行计数，换型信号沿自动重锁要求新首件；放行许可挂状态量非单拍脉冲防误放行，首件未放行期间批量启动请求被拒绝并计数留痕，复位不清放行台账，输出锁定态/放行许可/当前批次放行数与拒绝计数。",
}
ARCH = {
"FB_DL_VoteKooN":"表决器架构：段 0 无条件刷新通道沿与迟滞；先按故障掩码筛有效通道并计数，有效数不足 K 置组态故障失效安全；通过数按有效基数判达 K/低于 K 两态，迟滞带防临界抖振；K 与通道数越界钳位并置组态故障；出口含表决态/跳闸/有效通道数/组态故障，CASE 含 ELSE 落安全侧，与固定 2oo3 件分工互引不重复实现。",
"FB_DL_SimInputBank":"仿真注入组架构：段 0 无条件刷新投入/退出沿；每通道独立仿真标志锁存，投入沿装载注入值旁路真实输入，退出沿自动回真实值；运行级联锁（上位运行标志）期间拒绝切换防执行器跳变；通道号越界拒绝不误伤邻通道；出口含八通道生效值数组/仿真标志字/拒绝计数，CASE 含 ELSE 兜底，与 OutputForcingBank 输出侧成对对称。",
"FC_DL_ThermocoupleLinearization":"双向折线插值架构：入口先做有限性闸与分型枚举 CASE 分派（含 ELSE 兜底落无效）；各型 ITS-90 特征点表集中声明为常量数组，mV→温度与温度→mV 两方向共用同一节点表做分段线性插值；越出量程置越域标志不出值；节点区间定位用有序扫描索引钳位防越界；精度口径在头注释如实声明，纯函数无状态可重入。",
"FB_DL_SkewKurtosisCalc":"Welford 高阶矩架构：段 0 无条件刷新采样沿；逐样本增量更新均值/二三四阶中心矩（增量式防大数相消），非有限样本剔除计数不污染；样本量达门槛才计算偏度峰度并置就绪标志，否则标志为假不出统计量；复位沿清全部累量；除法全部带样本量下限闸防除零；出口含偏度/峰度/样本数/剔除数/就绪标志。",
"FC_DL_SolveLinear3":"部分主元消元架构：入口判系数与右端有限性（非有限置无效直接返回）；消元逐列选绝对值最大主元行交换提高稳定性，主元低于相对奇异阈值（按系数范数缩放）判奇异不出解；回代按上三角求解，除法全部经主元闸；解向量与无效标志双出口，全程局部变量无静态状态，纯函数可重入，与 Matrix3Inverse 求逆路径分工互引。",
"FC_DL_PmvComfortIndex":"Fanger 公式链架构：入口六参数域闸门四段式（非有限拒绝/越域钳位置标志/正常直通）；服装表面温度用定点迭代求稳态，迭代上限防不收敛（不收敛取末次值并置收敛标志假）； metabolic 与服装热阻越界按 ISO 公开语义钳位；PMV 线性合成后 PPD 由 PMV 幅值映射；出口含 PMV/PPD/越域标志，纯计算无状态，供 HVAC 优化目标函数调用。",
"FB_DL_SoftStarterDrive":"软启顺控状态机架构：实现 I_DL_MotorDriver 接口（cmd/ind 分离范式）；段 0 无条件刷新运行反馈沿与启动超时定时器；eIdle→eRampUp（晶闸管斜坡推进+电流限幅）→eBypassCheck（全压且反馈确认）→eRun；停止相撤旁路再撤斜坡有序退出；旁路反馈不一致经去抖判故障锁存；启动超时判堵转进 eFault 安全侧；出口含运行态/旁路态/故障码，CASE 含 ELSE 落停机安全态，接口零新建与族内三件同契约。",
"FB_DL_ElectricLinearActuator":"双模判定架构：段 0 无条件刷新电流采样窗与去抖定时器；到位判据=运行电流回落进入窗且持续去抖窗；堵转判据=电流持续超限加运动超时双条件锁存；限位两端互锁且同拍矛盾判传感器坏按最保守停机；非有限电流拒绝参与判定置传感器坏；出口含运动中/到位/堵转/限位态/传感器坏，CASE 含 ELSE 落停机安全态，无位置反馈纯时间电流双模在头注释声明。",
"FB_DL_OptimalStartStop":"最优启停调度架构：段 0 无条件刷新温差采样沿；按室内外温差与目标差查提前量曲线得基准提前量，经验学习系数在线修正（钳位 0.5~2.0 防漂移，R95 三句声明修正语义）；达到设定温度提前退出防过调；温差或参数非有限退化为固定提前量并置降级标志；出口含建议启动/停止时刻与降级标志，只建议不执行，与 EnergySavingMode 分工互引。",
"FB_DL_PeriodicDisturbComp":"内模重复控制架构：段 0 无条件刷新周期变更沿；环形延迟线按扰动周期装填槽位数（4096 上限钳位），逐拍先读后写防自吞；输出=延迟线回读乘收敛增益叠加遗忘因子衰减，与实时误差合成前馈；周期变更沿重建延迟线清历史；收敛增益与遗忘因子越界钳位防爆振；非有限误差拒绝参与累加；出口含补偿量/延迟线深度/无效标志，与 DisturbanceObserver 非周期观测分工互引。",
"FB_DL_CondensateDrainSeq":"排污顺控架构：定时与液位双触发任一满足即进 eDrain；段 0 无条件刷新排放确认超时定时器；排放确认反馈到齐才收口回 eIdle，超时未确认判阀故障锁存并禁止下一轮自动排放（须手动复位）；排放最小间隔防频开；液位非有限判传感器坏退化为保守定时口径；出口含排污中/阀故障/累计次数/状态，CASE 含 ELSE 落关阀安全态。",
"FC_DL_CamTableGenSeg":"段型生成架构：入口判边界点有序性与点数域闸（非有限/退化区间拒绝置无效）；E_DL_CamSegType 枚举 CASE 分派线性/五次/摆线三类段型（含 ELSE 兜底），按区间归一化坐标逐点求位移；生成后逐点单调自检，非单调判段型参数异常不出表；点数与位移范围越界钳位；出口含点列数组/自检标志/无效标志，纯函数无状态，供 CamTableValidate 前置。",
"FB_DL_AxisSafetyStateMon":"安全状态字监视架构：段 0 无条件刷新状态字采样沿与去抖窗；固定掩码逐位比对期望组态（掩码常量集中声明，禁运行期移位改组态）；不一致持续去抖窗后按位类分类锁存（使能丢失/功能激活/反馈矛盾）；状态字含保留位或非有限判通信坏按最保守锁存；仅监视零命令输出；出口含分类诊断枚举/一致态/通信坏标志，CASE 含 ELSE 落最保守诊断。",
"FB_DL_GowningRoomSeq":"更衣顺控架构：不变量「双门不同时开」每相出口显式写死（R98 双出口纪律）；段 0 无条件刷新门磁沿与更衣时限定时器；eIdle→eEnter（外门进）→eGowning（更衣计时，超时提醒可复位重计）→eDone（完成等待退出）→eExit；完成未退出不放行外门；急停火警优先解除许可置中止态；门磁矛盾判传感器坏双门锁；出口含双门锁/更衣中/放行许可/状态，CASE 含 ELSE 落最保守态。",
"FB_DL_MaterialHoldTimeEnforce":"保持时限强制架构：段 0 无条件刷新进站沿与时钟基准校验；进站沿启动保持计时，剩余时间实时输出；超时限判 NG 锁存禁止直通放行，仅复检确认沿可放行并记台账双计数（放行/判废）；复位不清 NG（必须走复检路径防绕闸）；时限越界钳位、时钟非有限置时钟坏冻结判定；出口含剩余时间/超时态/放行许可/NG 标志，CASE 含 ELSE 落锁定安全态。",
"FB_DL_FirstArticleLock":"首件闸口架构：上电默认锁定（安全侧初值）；段 0 无条件刷新放行沿与换型沿；放行沿解锁并放行计数递增，换型沿自动重锁要求新首件；放行许可挂状态量非单拍脉冲（R99 许可挂状态量纪律）；锁定期间批量启动请求拒绝并计数留痕；复位不清台账；出口含锁定态/放行许可/放行数/拒绝计数，CASE 含 ELSE 落锁定安全态。",
}

def main():
    # ---------- 1. 机检（增量 21 件）----------
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
    io.open(os.path.join(STAGE, "_audit_r58.json"), "w", encoding="utf-8", newline="").write(
        json.dumps(audit, ensure_ascii=False, indent=1))
    print("AUDIT %d/%d PASS" % (npass, len(audit)))
    if npass < len(audit):
        print("!!! AUDIT FAIL — STOP"); return

    # ---------- 2. 注册 ----------
    shutil.copy2(REG, REG + ".bak_r58")
    shutil.copy2(JSONL, JSONL + ".bak_r58")
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
                      "code_segment": "", "source": "r58-plan"})
        added.append(name)
    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["counts"] = {k: counts.get(k, 0) for k in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process")}
    reg["total_components"] = len(comps)
    reg["version"] = "2.50.0"
    reg["last_updated"] = NOW
    tmp = REG + ".tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="") as f:
        json.dump(reg, f, ensure_ascii=False, indent=1); f.write("\n")
    os.replace(tmp, REG)
    assert sum(reg["counts"].values()) == len(comps), "counts sum mismatch"
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
            if o.get("output", "")[:400].find(name) >= 0:
                o["output"] = body
                o["instruction"] = o.get("instruction", "") + "（v1.0.1 返修版：见 ROUND_PLAN_R58 §二修法）"
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

    # ---------- 4. ROADMAP 勾选（R247 锚定本体行正则 + 数量断言）----------
    rl = io.open(ROADMAP, encoding="utf-8").read().splitlines()
    ticked = []
    for i, ln in enumerate(rl):
        if ln.startswith("- [ ]"):
            for name, *_ in NEW:
                if re.search(r"\b" + name + r"\b", ln):
                    rl[i] = "- [x]" + ln[5:]; ticked.append(name); break
    assert len(ticked) <= 2, "ticked too many: %s" % ticked
    io.open(ROADMAP, "w", encoding="utf-8", newline="").write("\n".join(rl) + "\n")
    left = sum(1 for x in rl if x.startswith("- [ ]"))
    print("ROADMAP ticked=%s pending_left=%d" % (ticked, left))

    # ---------- 5. 全库行数 + README ----------
    total_lines = 0
    for f in glob.glob(os.path.join(ROOT, "DL_*", "*.st")):
        total_lines += len(io.open(f, encoding="utf-8", errors="ignore").read().splitlines())
    rp = os.path.join(ROOT, "README.md")
    txt = io.open(rp, encoding="utf-8").read()
    total = reg["total_components"]; sft = len(lines)
    txt = txt.replace("Total%20Components-1037%20", "Total%%20Components-%d%%20" % total)
    txt = txt.replace("SFT%20Corpus-1038%20", "SFT%%20Corpus-%d%%20" % sft)
    txt = txt.replace("**Total Components: 1037 / 10,000**", "**Total Components: %d / 10,000**" % total)
    txt = txt.replace("Version: v2.49.0", "Version: v2.50.0")
    txt = txt.replace("**SFT 语料: 1038 条**", "**SFT 语料: %d 条**" % sft)
    txt = re.sub(r"全库约 [\d,]+ 行", "全库约 %s 行" % format(total_lines, ","), txt)
    summary = ("> **R58（2026-11-21）**：16 新件（MathData 3 / Algo 3 / Device 3 / Process 3 / Base 2 / Motion 2，KooN 表决·仿真注入组·热电偶线性化·偏度峰度·三阶线性解·PMV·软启·电动推杆·最优启停·重复控制·冷凝排污·凸轮段型·轴安全监视·更衣顺控·保持时限·首件锁定）+ 5 件 v1.0.1 返修；"
               "总库 1037→**%d**，SFT %d，机检 %d/%d PASS；零检索轮，撞名拒 5 件（R214 三查留痕）。\n" % (total, sft, npass, len(audit)))
    anchor = txt.find("> **R57（2026-11-21）**")
    if anchor < 0:
        anchor = txt.find("> **R56（2026-11-20/21）**")
    if anchor > 0:
        txt = txt[:anchor] + summary + txt[anchor:]
    io.open(rp, "w", encoding="utf-8", newline="").write(txt)
    print("README updated -> %d / SFT %d / ~%d lines" % (total, sft, total_lines))

    # ---------- 6. CHANGELOG ----------
    cp = os.path.join(ROOT, "CHANGELOG.md")
    ct = io.open(cp, encoding="utf-8").read()
    add = "\n## [v2.50.0] - 2026-11-21\n\n### Added\n"
    add += "".join("- `%s`（%s，cx%d）\n" % (n, c, x) for n, c, t, x, g in NEW)
    add += "\n### Fixed\n" + "".join("- `%s` v1.0.1：R57 五抽缺陷返修（详见 ROUND_PLAN_R58 §二）\n" % n for n, c in REPAIR)
    add += "\n### Changed\n- 全库 %d 件 / v2.50.0；SFT 语料 %d 条。\n" % (total, sft)
    idx = ct.find("\n## [v2.49.0]")
    ct = (ct[:idx] + add + ct[idx:]) if idx > 0 else (ct + add)
    io.open(cp, "w", encoding="utf-8", newline="").write(ct)
    print("CHANGELOG appended")

    # ---------- 7. VERSION 子库 ----------
    for sub, ver, note in [("DL_Base", "1.29", "2 件（VoteKooN / SimInputBank）+ EncoderQuadCount v1.0.1 返修"),
                           ("DL_MathData", "1.30", "3 件（ThermocoupleLinearization / SkewKurtosisCalc / SolveLinear3）+ RmsCalc / PowIntSat v1.0.1 返修"),
                           ("DL_Algo", "1.25", "3 件（PmvComfortIndex / OptimalStartStop / PeriodicDisturbComp）"),
                           ("DL_Device", "1.23", "3 件（SoftStarterDrive / ElectricLinearActuator / CondensateDrainSeq）"),
                           ("DL_Motion", "1.22", "2 件（CamTableGenSeg / AxisSafetyStateMon）"),
                           ("DL_Process", "1.28", "3 件（GowningRoomSeq / MaterialHoldTimeEnforce / FirstArticleLock）+ PassboxInterlockSeq / NightPurgeSeq v1.0.1 返修")]:
        vp = os.path.join(ROOT, sub, "VERSION.md")
        if not os.path.exists(vp):
            vp = os.path.join(ROOT, sub, "VERSION")
        if os.path.exists(vp):
            cur = io.open(vp, encoding="utf-8").read()
            entry = "\n## v%s — 2026-11-21（R58 追加）\n- %s。\n- 子库累计 %d 件。\n" % (
                ver, note, reg["counts"].get(sub, 0))
            io.open(vp, "w", encoding="utf-8", newline="").write(cur.rstrip() + "\n" + entry)
    print("VERSION x6 appended")
    print("SUMMARY total=%d counts=%s sft=%d pending=%d" % (total, reg["counts"], sft, left))

main()
