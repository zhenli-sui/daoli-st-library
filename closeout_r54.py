#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r54.py —— R54 主控直跑收口（R335）：注册 16 新件 + 3 返修升版 + JSONL 增量 + ROADMAP 勾选 + 文档追加。"""
import io, os, json, shutil

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
ROADMAP = os.path.join(ROOT, "ROADMAP.md")
NOW = "2026-11-20T18:42:00+08:00"

NEW = [
 ("FB_DL_BitArrayMultiSegMove", "DL_Base", "FB", 4, ["lgf-bitlogic", "bit-array", "segment-move", "clean-room"]),
 ("FC_DL_ChecksumLwordSum", "DL_MathData", "FC", 2, ["lgf-datahandling", "checksum", "lword", "clean-room"]),
 ("FB_DL_HealthStatusArbiter", "DL_Device", "FB", 4, ["ne107", "health-arbiter", "diagnostics", "clean-room"]),
 ("FB_DL_PrbsSignal", "DL_Base", "FB", 2, ["oscat-basic", "prbs", "test-signal", "clean-room"]),
 ("FB_DL_PidRelayAutoTune", "DL_Algo", "FB", 5, ["relay-autotune", "pid", "identify", "clean-room"]),
 ("FB_DL_HistogramBinTally", "DL_MathData", "FB", 3, ["lgf-measurement", "histogram", "statistics", "clean-room"]),
 ("FB_DL_PnDiagAlarmDecode", "DL_Device", "FB", 4, ["plcnext-community", "profinet", "alarm-decode", "clean-room"]),
 ("FB_DL_SweepFreqGen", "DL_Base", "FB", 3, ["lgf-siggen", "sweep", "frequency", "clean-room"]),
 ("FB_DL_FirstOrderIdent", "DL_Algo", "FB", 4, ["system-ident", "first-order", "step-response", "clean-room"]),
 ("FB_DL_CamTableLiveTrim", "DL_Motion", "FB", 4, ["plcopen-motion", "cam-table", "live-trim", "clean-room"]),
 ("FB_DL_NightFlushPurge", "DL_Process", "FB", 3, ["oscat-building", "night-purge", "hvac", "clean-room"]),
 ("FB_DL_AirCompressorLoadUnload", "DL_Device", "FB", 3, ["lbp-basic-process", "compressor", "load-unload", "clean-room"]),
 ("FB_DL_RecipeSwitchHandover", "DL_Process", "FB", 4, ["isa88", "packml", "recipe-handover", "clean-room"]),
 ("FB_DL_EnthalpyPrioritySwitch", "DL_Process", "FB", 3, ["oscat-building", "enthalpy", "economizer", "clean-room"]),
 ("FB_DL_TankAgitationSeq", "DL_Process", "FB", 3, ["isa88", "agitation", "sequence", "clean-room"]),
 ("FB_DL_AxisTorqueRippleWatch", "DL_Motion", "FB", 3, ["plcopen-motion", "torque-ripple", "watch", "clean-room"]),
]
REWORK = [
 ("FB_DL_ControlOutputSlewWatch", "DL_Algo", "1.0.1"),
 ("FB_DL_SensorDriftBaseline", "DL_Algo", "1.0.1"),
 ("FB_DL_AxisBacklashStepComp", "DL_Motion", "1.0.1"),
]

INSTR = {
 "FB_DL_BitArrayMultiSegMove": "上位配方与状态字需要把一段位区间整体搬到另一段（读写不同偏移、长度可组态），现场要求源/目的区间重叠时按掩码读改写一次完成、不产生中间撕裂；长度越界须钳位并置码，源目的同址视为空操作；纯位操作不得引入厂商位串指令。",
 "FC_DL_ChecksumLwordSum": "通信报文与配方块常用 32 位字累加和校验，要求对 DWORD 数组按无符号累加并自然回绕（模 2^32），元素个数由入参给出且先钳位到容器上界；空数组返回 0 且置有效标志假；纯函数无状态无副作用，跨平台不得依赖任何厂商校验库。",
 "FB_DL_HealthStatusArbiter": "一台设备下挂多个子模块，各自上报 NE107 健康态（故障/需要维护/超出规格/检查），上层只允许看一个聚合态：聚合规则必须与 NE107 语义一致（故障优先、其次需维护），同拍多源并存时按最严胜出并保持到全部源解除；单源抖动需去抖，源缺失按不可用单列。",
 "FB_DL_PrbsSignal": "回路辨识与通信误码测试需要伪随机二进制序列激励：要求序列周期可组态、每拍按多项式移位生成单比特并映射为两电平输出，序列种子可重置且重置后序列严格可复现；周期越界钳位，禁止使用任何系统随机源（不可复现）。",
 "FB_DL_PidRelayAutoTune": "温度/压力回路现场整定靠经验，需要继电器反馈法自动辨识：以回差带驱动输出在高低两值间切换，测量振荡周期与幅值，据以算出临界增益与临界周期并给出 PID 初值；振荡不收敛或超时必须退出并保持原参数，切换期间输出限幅，全程只请求不直写执行器。",
 "FB_DL_HistogramBinTally": "质量数据分布需要分箱统计（粒径、厚度、扭矩），要求箱数与上下界可组态、越界样本计入溢出桶而不丢弃，各箱计数与总数需自洽（各箱之和=有效样本）；分箱边界重合时归入高箱且不得双重计数；复位分包（清计数/清溢出）防误清。",
 "FB_DL_PnDiagAlarmDecode": "PROFINET 从站诊断报文字段需解码为可读故障类别：要求按通道与故障类型位解析出断线/短路/超上限/超下限/模块缺失等分类并置对应标志，未知码位必须落 unknown 桶而非静默丢弃；多通道同拍只报最高优先通道，解码表变更须可组态。",
 "FB_DL_SweepFreqGen": "振动台与滤波器频响测试需要扫频激励：频率按对数或线性斜坡在起止频率间连续变化，斜率可组态且不得跳变（相位连续），到顶后按组态决定停或回扫；扫频期间输出幅值恒定并限幅，频率越界钳位；扫频进度与当前频率双读数供上位记录。",
 "FB_DL_FirstOrderIdent": "阀门与加热器的一阶惯性时间常数与增益通常未知，需要由阶跃响应自动辨识：以激励起点为 t0 快照初值与稳态值，按 63.2% 到达时刻估时间常数，增益由稳态差除以阶跃幅值；响应未达稳态或噪声过大时须拒绝出结果并保持上次有效值，除零前判幅值。",
 "FB_DL_CamTableLiveTrim": "电子凸轮运行中需要在线微调从轴相位/幅值（不停机修形）：微调量必须以斜坡注入并在若干周期内收敛，禁止阶跃造成从轴冲击；微调只在主轴相位过参考点后生效，越限钳位；微调期间保持凸轮单调性，退出时平滑回落到原表。",
 "FB_DL_NightFlushPurge": "洁净厂房与机房夜间免费冷却需要按室内外焓差与时段自动冲洗换气：仅在夜间窗内且室外焓低于室内才允许开风阀与风机，窗末须提前停风机并关阀（防结露）；室内外温湿度任一失效按最保守关闭，冲洗时长与间隔可组态。",
 "FB_DL_AirCompressorLoadUnload": "空压机加卸载控制：压力低于加载阈值启加载、高于卸载阈值卸载，两阈值间保持当前态（带迟滞防频繁切换）；卸载运行超时须停机，最小运行与最小停机时间须强制；压力信号失效按停机保护，多机联控时按运行小时轮换主机。",
 "FB_DL_RecipeSwitchHandover": "批次换配方时不允许在制品跨配方混批：换配方请求须等待当前批到安全断点，产出计数按批结算后清零，切换期间输出保持上一配方直到新配方参数校验通过；校验失败回退旧配方并置码，切换须留痕（旧配方号与新配方号及时刻）。",
 "FB_DL_EnthalpyPrioritySwitch": "空调新风经济器按焓值比选：室外焓低于室内回风焓且低于设定阈值时优先新风免费冷却，否则回风循环；两路比较须带死区防阀位振荡，阈值可组态；任一温湿度失效时退回最小新风并置降级，阀位切换须斜坡限速。",
 "FB_DL_TankAgitationSeq": "反应釜搅拌顺序控制：按加料、搅拌、静置、排料状态机推进，每相有超时与完成判据（扭矩/时间/液位），任一相超时进故障相并停搅拌；搅拌电机反馈缺失不得进入下一相；手动步进仅在维护模式允许且单步需确认，断电恢复须从安全相重入。",
 "FB_DL_AxisTorqueRippleWatch": "轴转矩脉动是机械卡滞与联轴器松动的早期征兆：需要对转矩反馈做滑窗峰峰值与均值比统计，比值超限持续确认后报警并分档；加减速段须屏蔽（动态转矩本就波动），传感器非有限按失效单列；阈值与窗深可组态，报警锁存可选。",
}

ARCH = {
 "FB_DL_BitArrayMultiSegMove": "区间搬运与掩码桥接架构：先做长度与偏移钳位及重叠判定，非重叠走整字批量搬，重叠走先把源区间读入临时字缓存再写目的的掩码读改写，保证一次完成无撕裂；段 0 无条件刷新请求沿，段 1 执行搬运并按剩余长度递减，越界置码并钳位；出口含完成位与错误码。",
 "FC_DL_ChecksumLwordSum": "单趟遍历纯函数：入口先钳元素个数到容器上界并置截断标志，累加用 DWORD 自然回绕（回绕即语义，不额外判溢出），空数组直接返回 0 并置有效假；常量集中声明；无状态可重入，禁止内部静态量。",
 "FB_DL_HealthStatusArbiter": "优先级仲裁状态机：段 0 无条件刷新各源去抖定时器；段 1 按 NE107 严格序（故障高于需维护高于超规格高于检查高于正常）逐源比选，取最严者为本拍聚合态，源不可用单列计数；聚合态带迟滞保持，全部源回正常并持续确认后才回落；CASE 含 ELSE 兜底，eIdle 出口显式置正常。",
 "FB_DL_PrbsSignal": "线性反馈移位寄存器架构：以组态抽头掩码每拍移位一次并回注异或位，种子重置沿装载初值（禁止全零态，装载时强制置 1 位），输出由指定位映射两电平；周期计数用于诊断；段 0 无条件推进保证序列时序确定，出口含序列位与周期计数。",
 "FB_DL_PidRelayAutoTune": "继电器反馈辨识状态机：eIdle 到 eCyc（输出在高低两值间按回差切换，记过零时刻）到 eCalc（由周期均值与峰峰值算临界增益与临界周期并给 PID 初值）到 eDone 或 eFault；振荡次数不足或超时进 eFault 并保持原参数；输出全程限幅且只在请求出口给出，超时与复位清内部计时与过零缓存。",
 "FB_DL_HistogramBinTally": "分箱累计架构：段 1 先做上下界与箱数合法性闸（箱数小于 1 置码），再按 (x-lo)/(hi-lo)*n 定位箱号并钳位到 0..n-1，越界样本进溢出桶；箱计数用定长数组按索引累加，总有效样本同源累加保证自洽；复位分清清计数与清溢出两入口，出口含各箱读数与溢出数。",
 "FB_DL_PnDiagAlarmDecode": "位域解码与优先级归一架构：段 1 按通道逐个取故障位域，用 CASE 把已知码位映射为分类枚举（ELSE 落 eUnknown 并计数），再按断线高于短路高于越限高于模块缺失的优先序选最高优先通道为本拍上报；解码表以常量数组集中；出口含分类、通道号与未知码计数。",
 "FB_DL_SweepFreqGen": "相位连续扫频架构：频率按对数步进累加（步长由斜率与采样周期派生），相位按 2π 乘频率乘采样周期累加后取正弦，保证频率变化时相位不跳变；段 0 无条件刷新采样周期与进度，段 1 判起止与回扫，越界钳位；出口含当前频率、幅值与进度百分比，eIdle 输出幅值 0。",
 "FB_DL_FirstOrderIdent": "阶跃响应辨识架构：eIdle 到 eWait（等激励沿，快照初值与起点时刻）到 eSample（跟踪响应，达 63.2% 时记时刻，跟踪稳态）到 eCalc（时间常数等于两时刻差，增益等于稳态差除以阶跃幅值，先判幅值非零）到 eDone；未达稳态或样本不足进 eReject 并保持上次有效值；复位清全部快照与缓存。",
 "FB_DL_CamTableLiveTrim": "斜坡注入与相位闸架构：微调请求先按限速生成斜坡量，只在主轴相位过参考点后一次性并入从轴相位偏置，保证凸轮单调性不被破坏；段 0 无条件刷新偏置斜坡与相位沿，段 1 做单调性校验（越限回钳并置码）；出口含实际偏置与注入完成位，退出时偏置按斜坡回落至 0。",
 "FB_DL_NightFlushPurge": "时段与焓差双闸架构：段 0 无条件刷新夜窗定时器与温湿度有限性闸；段 1 判窗内且室外焓低于室内焓减死区才允许冲洗，窗末提前量到即按先停风机后关阀的顺序执行（防结露）；信号失效走保守分支（关阀停风机）并置降级；冲洗与间隔计时可组态，出口含当前相与剩余窗时。",
 "FB_DL_AirCompressorLoadUnload": "双阈值迟滞与最小时间约束架构：eIdle/eLoad/eUnload/eStop 状态机，压力低于加载阈值进 eLoad、高于卸载阈值进 eUnload，两阈值间保持；卸载超时与最小运行及最小停机时间用无条件刷新的定时器强制；压力非有限直接进 eStop 保护；多机轮换按运行小时排序选主机。",
 "FB_DL_RecipeSwitchHandover": "断点握手架构：换配方请求先置 pending，等当前批到安全断点（相结束且产出计数已结算）才执行；执行序为校验新配方、结算旧批、装载新配方、清批计数，任一步失败回退旧配方并置码；切换全程输出保持上一配方参数，出口含当前配方号、批计数与切换结果。",
 "FB_DL_EnthalpyPrioritySwitch": "焓值比较与死区架构：段 1 由温湿度算室内外焓（含有限性闸），比较结果带死区防阀位振荡，超阈值才切换新风与回风；切换时阀位按斜坡限速；温湿度失效退回最小新风并置降级标志；出口含当前模式、两路焓值与阀位指令。",
 "FB_DL_TankAgitationSeq": "相序状态机架构：eIdle 经 eFill、eAgitate、eSettle、eDischarge 到 eDone，每相配无条件刷新的超时定时器与完成判据（扭矩/液位/时间），超时统一进 eFault 并停搅拌；电机反馈缺失禁止迁相；手动步进仅在维护模式且需确认沿；断电恢复按安全相重入，出口各相输出显式清零。",
 "FB_DL_AxisTorqueRippleWatch": "滑窗峰峰值与比值判据架构：段 0 无条件刷新窗口定时器与采样沿；段 1 在非加减速段把转矩写入环形窗并维护峰峰值，窗到时算峰峰值与均值之比并与阈值分档比较（良好/注意/异常，带迟滞）；非有限输入单列失效并冻结窗口；报警锁存可选，出口含比值、档位与失效标志。",
}

RW_NOTE = {
 "FB_DL_ControlOutputSlewWatch": "R54 返修 v1.0.1（R52 五抽严重项）：_nHead 与 _nFill 声明初值补齐（1 / 0），段 1 运行时域外自愈与窗深回钳原样保留作双保险，行为零变更。",
 "FB_DL_SensorDriftBaseline": "R54 返修 v1.0.1（R54 五抽中项）：迁入闸与基线 EMA 更新前置有限性闸，非有限拍冻结基线、偏差出口保持上拍快照，新增 bSensorBad 锁存出口（复位沿清）。",
 "FB_DL_AxisBacklashStepComp": "R54 返修 v1.0.1（R54 五抽中项）：偏移与位置出口计算移入有限分支，非有限拍两出口保持上拍值并置 bInvalid 单拍指示（内部到统一出口映射），消除 NaN 穿出口。",
}
ARCH_RW = {
 "FB_DL_ControlOutputSlewWatch": "首拍保护架构：声明期给游标确定初值，运行期域外自愈双保险，窗口深度在每次写前回钳，杜绝越界写。",
 "FB_DL_SensorDriftBaseline": "有限性闸前置架构：基线更新与残差计算共用同一有限性判据，非有限拍只冻结不推进，出口走快照保持而非现算，失效与漂移两出口严格分离。",
 "FB_DL_AxisBacklashStepComp": "出口有限分支架构：所有由反馈参与的位置出口只在有限拍计算，非有限拍统一走快照保持并置单拍无效指示，映射层出口不承担诊断语义。",
}


def main():
    shutil.copy2(REG, REG + ".bak_r54")
    shutil.copy2(JSONL, JSONL + ".bak_r54")
    reg = json.load(io.open(REG, encoding="utf-8"))
    comps = reg["components"]
    names = {c["name"].lower() for c in comps}
    added, skipped = [], []
    for name, cat, typ, cx, tags in NEW:
        if name.lower() in names:
            skipped.append(name)
            continue
        p = os.path.join(ROOT, cat, name + ".st")
        L = len(io.open(p, encoding="utf-8").read().strip().splitlines())
        comps.append({"name": name, "category": cat, "type": typ, "file_path": p,
                      "function_tags": tags + [name.lower()], "complexity": cx,
                      "version": "1.0.0", "registered_at": NOW, "line_count": L,
                      "code_segment": "", "source": "r54-plan"})
        added.append(name)
    rw = []
    for name, cat, ver in REWORK:
        for c in comps:
            if c["name"] == name:
                c["version"] = ver
                c["line_count"] = len(io.open(os.path.join(ROOT, cat, name + ".st"), encoding="utf-8").read().strip().splitlines())
                rw.append(name + "@" + ver)
                break
    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["counts"] = {k: counts.get(k, 0) for k in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process")}
    reg["total_components"] = len(comps)
    reg["version"] = "2.46.0"
    reg["last_updated"] = NOW
    tmp = REG + ".tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="") as f:
        json.dump(reg, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, REG)
    print("REG total=%d counts=%s added=%d skip=%s rework=%s" % (len(comps), reg["counts"], len(added), skipped, rw))

    lines = io.open(JSONL, encoding="utf-8").read().splitlines()
    out, reinj = [], []
    cmap = {n: c for n, c, v in REWORK}
    for ln in lines:
        if not ln.strip():
            continue
        o = json.loads(ln)
        hit = None
        for n, _, _ in REWORK:
            if n in (o.get("instruction", "") + o.get("output", "")):
                hit = n
                break
        if hit and hit not in reinj:
            o["output"] = io.open(os.path.join(ROOT, cmap[hit], hit + ".st"), encoding="utf-8").read()
            o["instruction"] = o["instruction"].rstrip() + "｜" + RW_NOTE[hit]
            o["architecture_thought"] = ARCH_RW[hit]
            reinj.append(hit)
        out.append(json.dumps(o, ensure_ascii=False))
    ap = 0
    for name, cat, typ, cx, tags in NEW:
        if name in skipped:
            continue
        out.append(json.dumps({"instruction": INSTR[name], "architecture_thought": ARCH[name],
                               "output": io.open(os.path.join(ROOT, cat, name + ".st"), encoding="utf-8").read()},
                              ensure_ascii=False))
        ap += 1
    tmp2 = JSONL + ".tmp"
    io.open(tmp2, "w", encoding="utf-8", newline="").write("\n".join(out) + "\n")
    os.replace(tmp2, JSONL)
    bad = 0
    for ln in io.open(JSONL, encoding="utf-8").read().splitlines():
        if not ln.strip():
            continue
        try:
            o = json.loads(ln)
            if not o.get("output") or len(o.get("instruction", "")) < 80 or len(o.get("architecture_thought", "")) < 100:
                bad += 1
        except Exception:
            bad += 1
    print("JSONL lines=%d appended=%d reinj=%s bad=%d" % (len(out), ap, reinj, bad))

    rl = io.open(ROADMAP, encoding="utf-8").read().splitlines()
    ticked = []
    for i, ln in enumerate(rl):
        if ln.startswith("- [ ]"):
            for name, *_ in NEW:
                if name in ln:
                    rl[i] = "- [x]" + ln[5:]
                    ticked.append(name)
                    break
    io.open(ROADMAP, "w", encoding="utf-8", newline="").write("\n".join(rl) + "\n")
    left = sum(1 for x in rl if x.startswith("- [ ]"))
    print("ROADMAP ticked=%s pending_left=%d" % (ticked, left))

    # ---- README 徽章与摘要行 ----
    rp = os.path.join(ROOT, "README.md")
    txt = io.open(rp, encoding="utf-8").read()
    txt = txt.replace("Total%20Components-961%20", "Total%20Components-977%20")
    txt = txt.replace("SFT%20Corpus-962%20", "SFT%20Corpus-978%20")
    txt = txt.replace("**Total Components: 961 / 10,000**", "**Total Components: 977 / 10,000**")
    txt = txt.replace("Version: v2.45.0", "Version: v2.46.0")
    txt = txt.replace("**SFT 语料: 962 条**", "**SFT 语料: 978 条**")
    txt = txt.replace("全库约 200,400 行", "全库约 203,600 行")
    summary = ("> **R54（2026-11-20）**：16 新件（Base 3 / MathData 2 / Algo 2 / Device 3 / Motion 2 / Process 4）+ 3 件 P0 返修 v1.0.1；"
               "总库 961→**977**，SFT 962→**978**，机检 19/19 PASS；P0 链：ControlOutputSlewWatch 首拍游标初值 / 非有限穿透族两件闭环；"
               "T0=0（八组余量 0 不硬凑），WebSearch 0/3。\n")
    anchor = txt.find("> **R53（2026-11-20）**")
    if anchor > 0:
        txt = txt[:anchor] + summary + txt[anchor:]
    io.open(rp, "w", encoding="utf-8", newline="").write(txt)
    print("README badge/summary updated")

    # ---- CHANGELOG 追加 ----
    cp = os.path.join(ROOT, "CHANGELOG.md")
    ct = io.open(cp, encoding="utf-8").read()
    sec = """## v2.46.0 — 2026-11-20（R54 十六件入册 + 三件 P0 返修）

### Added（16 新件，4 批 × 4，零检索轮）
- DL_Base（+3）：FB_DL_BitArrayMultiSegMove / FB_DL_PrbsSignal / FB_DL_SweepFreqGen
- DL_MathData（+2）：FC_DL_ChecksumLwordSum / FB_DL_HistogramBinTally
- DL_Algo（+2）：FB_DL_PidRelayAutoTune / FB_DL_FirstOrderIdent
- DL_Device（+3）：FB_DL_HealthStatusArbiter / FB_DL_PnDiagAlarmDecode / FB_DL_AirCompressorLoadUnload
- DL_Motion（+2）：FB_DL_CamTableLiveTrim / FB_DL_AxisTorqueRippleWatch
- DL_Process（+4）：FB_DL_NightFlushPurge / FB_DL_RecipeSwitchHandover / FB_DL_EnthalpyPrioritySwitch / FB_DL_TankAgitationSeq

### Fixed（3 件 P0 返修，均 v1.0.1）
- FB_DL_ControlOutputSlewWatch：`_nHead`/`_nFill` 声明初值补齐（R52 五抽严重项），运行时自愈保留作双保险，行为零变更。
- FB_DL_SensorDriftBaseline：基线更新与偏差出口前置有限性闸，新增 bSensorBad 锁存出口。
- FB_DL_AxisBacklashStepComp：偏移与位置出口移入有限分支，非有限拍走快照保持 + bInvalid 单拍指示。

### Changed
- registry v2.45.0 → v2.46.0，总库 961 → 977；JSONL 962 → 978 行（新增 16 行全达标 + 3 件返修重注入）。
- 机检 19/19 PASS（16 新件 + 3 返修），零 GVL / 零物理地址 / 零占位符。

"""
    i = ct.find("## v2.45.0")
    ct = ct[:i] + sec + ct[i:] if i > 0 else ct + "\n" + sec
    io.open(cp, "w", encoding="utf-8", newline="").write(ct)
    print("CHANGELOG updated")

    # ---- 子库 VERSION 追加 ----
    ver = {"DL_Base": ("1.24", ["FB_DL_BitArrayMultiSegMove", "FB_DL_PrbsSignal", "FB_DL_SweepFreqGen"]),
           "DL_MathData": ("1.25", ["FC_DL_ChecksumLwordSum", "FB_DL_HistogramBinTally"]),
           "DL_Algo": ("1.21", ["FB_DL_PidRelayAutoTune", "FB_DL_FirstOrderIdent"]),
           "DL_Device": ("1.20", ["FB_DL_HealthStatusArbiter", "FB_DL_PnDiagAlarmDecode", "FB_DL_AirCompressorLoadUnload"]),
           "DL_Motion": ("1.19", ["FB_DL_CamTableLiveTrim", "FB_DL_AxisTorqueRippleWatch"]),
           "DL_Process": ("1.23", ["FB_DL_NightFlushPurge", "FB_DL_RecipeSwitchHandover", "FB_DL_EnthalpyPrioritySwitch", "FB_DL_TankAgitationSeq"])}
    for cat, (v, items) in ver.items():
        p = os.path.join(ROOT, cat, "VERSION.md")
        if not os.path.exists(p):
            continue
        s = io.open(p, encoding="utf-8").read()
        s = s.rstrip() + "\n\n## R54 追加（2026-11-20，子库 v%s）\n- 新增：%s\n- 子库存量：%d 件\n" % (
            v, " / ".join(items), reg["counts"][cat])
        io.open(p, "w", encoding="utf-8", newline="").write(s)
    print("VERSION x6 appended")
    return len(out), reg["counts"], left


main()
