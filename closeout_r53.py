#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r53.py —— R53 主控直跑收口（R335）：注册 16 新件 + 4 返修升版 + JSONL 增量 + ROADMAP 三向差额勾选。"""
import io, os, json, shutil

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
ROADMAP = os.path.join(ROOT, "ROADMAP.md")
NOW = "2026-11-20T16:05:00+08:00"

NEW = [
 ("FB_DL_ValveCycleLifeCounter","DL_Device","FB",2,["isa182","valve-life","clean-room"]),
 ("FB_DL_BearingVibTrend","DL_Algo","FB",3,["lgf-measurement","vibration-iso10816","clean-room"]),
 ("FC_DL_WetBulbCalc","DL_MathData","FC",3,["oscat-building","psychrometric","clean-room"]),
 ("FB_DL_SignalStuckWatch","DL_Base","FB",2,["lgf-measurement","stuck-signal","clean-room"]),
 ("FB_DL_ConveyorSlipWatch","DL_Device","FB",3,["lbp-conveyor","slip-detect","clean-room"]),
 ("FB_DL_CaseShiftTally","DL_Process","FB",2,["roadmap-pool","shift-tally","clean-room"]),
 ("FC_DL_HaversineDistance","DL_MathData","FC",2,["lgf-math","geodesic","clean-room"]),
 ("FB_DL_PumpSurgeGuard","DL_Algo","FB",4,["oscat-basic","surge-guard","clean-room"]),
 ("FB_DL_GreaseLubeTimer","DL_Device","FB",2,["isa182","lube-window","clean-room"]),
 ("FB_DL_PulseTrainDecoder","DL_Base","FB",3,["lgf-bitlogic","pulse-decode","clean-room"]),
 ("FC_DL_PeriodJitterCalc","DL_MathData","FC",2,["lgf-math","jitter-stat","clean-room"]),
 ("FB_DL_SensorDriftBaseline","DL_Algo","FB",3,["lgf-measurement","drift-baseline","clean-room"]),
 ("FB_DL_FilterWeekWindow","DL_Process","FB",3,["roadmap-pool","week-window","clean-room"]),
 ("FB_DL_LabelWeekCode","DL_Process","FB",2,["roadmap-pool","week-code","clean-room"]),
 ("FB_DL_AxisBacklashStepComp","DL_Motion","FB",3,["plcopen-motion","backlash-comp","clean-room"]),
 ("FB_DL_BathTempHoldCtrl","DL_Process","FB",3,["industry-pool","bath-temp","clean-room"]),
]
REWORK = [
 ("FB_DL_AxisHomeRepeatVerify","DL_Motion","1.0.1"),
 ("FB_DL_PidParamDriftAudit","DL_Algo","1.0.1"),
 ("FB_DL_HeatTraceCircuitMon","DL_Device","1.0.1"),
 ("FB_DL_BrakeResistorThermal","DL_Device","1.0.1"),
]
TICK_LINES = [418,435,443,471,626,694,695,718,720,724,725,733,736,814,832,879,907,920]

INSTR = {
 "FB_DL_ValveCycleLifeCounter":"气动/电动阀门按行程次数计寿命：阀位跨越全行程阈值才算一次动作，中间抖动不得计数，扭角/力矩超限的动作须单列计数；需在达到保养阈值前分级预警，允许中途换阀清零，计数掉电保持由上层负责；计数上去重窗可组态。",
 "FB_DL_BearingVibTrend":"旋转设备轴承振动有效值长期缓升是早期磨损征兆：需要滑窗 RMS 与基线比值的双判据，并按 ISO 10816 三档（良好/注意/不合格）分级；启停瞬态与检修后重标定须能屏蔽误报，档位带迟滞防跳档；振动信号非有限按传感器失效单列。",
 "FC_DL_WetBulbCalc":"空调与冷却塔计算逼近度需要湿球温度，现场只有干球温度与相对湿度，须由焓湿关系迭代反解湿球温度；要求迭代次数与收敛容差可组态、单调收敛、超范围输入给出确定回退值；纯函数无状态，跨平台不得依赖厂商热力学库。",
 "FB_DL_SignalStuckWatch":"现场模拟量卡死（传感器冻结、通道固定值）时数值稳定得看不出异常：需同时判「值长时间不变」与「变化率恒零」两条，其中缓慢变化的正常工况不得误判；判定用超时窗，超时窗内允许微小噪声容差；恢复变化即自动解除，报警带锁存可选。",
 "FB_DL_ConveyorSlipWatch":"输送带打滑会造成堆料与磨损，仅看电机电流无法区分轻载与打滑：需比对驱动辊线速度与从动辊/带速的速差比，并在负载段（电流高于阈值）才启用判据；启动加速段须屏蔽，速差超限持续一段时间才报；传感器缺失时降级为电流单判据并置降级标志。",
 "FB_DL_CaseShiftTally":"装箱工位按班次统计箱数与计划量比对，班中需实时显示差异与达成率，超差即提醒班组长；跨班切换须自动结算上一班并清零本班，手动补记须留痕；计数只认合格箱（不合格箱单列），停线时段不计入节拍统计；班次边界由外部时标驱动。",
 "FC_DL_HaversineDistance":"AGV 与巡检机器人定位需要两点经纬度间的大圆距离，平面近似在跨区运行时误差过大：要求输入为度制、输出为米，内部按双精度计算并处理极点与跨 180 度经线；相同点返回 0，非法纬度（|lat|>90）拒绝并给哨兵值；纯函数无状态可重入。",
 "FB_DL_PumpSurgeGuard":"离心泵/风机在小流量高压比区会进入喘振，表现为流量振荡与轴振突增：需由流量与压比算工况点距喘振线的裕度，裕度不足即请求开回流阀或降转速，极端时请求跳闸；降载须斜坡进行防二次振荡，流量信号失效按最保守降载；动作只请求不直接写执行器。",
 "FB_DL_GreaseLubeTimer":"集中润滑与轴承加脂按运行小时或动作循环数触发，二者先到先报，避免只按时间导致高频工位欠脂：需双计数器并行、任一达阈值即置请求并锁存至确认；加脂泵反馈缺失时不得静默通过，需置码；换脂后双计数同清，单清会造成口径漂移。",
 "FB_DL_PulseTrainDecoder":"编码旋钮/拨码开关以脉冲串上报档位，现场需把脉冲个数与脉宽宽窄组合解码为编码值：需区分短脉冲与长脉冲（宽窄判别），并按序列还原档位；丢脉冲或超时未完序列须置错并保持上次有效值；同一拍多沿输入按最保守处理，禁止吐出中间态。",
 "FC_DL_PeriodJitterCalc":"运动控制与通信节拍的抖动直接影响插补精度：需对一串周期样本给出最大、最小、极差、均值与标准差，样本不足时返回有效标志为假而非零值；标准差用样本口径（除以 n-1），分母为 1 时退化为 0 并置标志；纯函数无状态，数组越界由入口长度钳位。",
 "FB_DL_SensorDriftBaseline":"传感器慢漂移（零点爬移、膜片老化）在单点判据下不可见：需维护一条长时常数指数基线（远慢于工艺波动），实时值与基线偏差超限即报警，并输出漂移速率供维护判断；标定后基线可重置（需确认位）；基线更新率受限，防把真实阶跃当漂移学进去。",
 "FB_DL_FilterWeekWindow":"过滤器按周维护窗与压差累计双判据提醒更换：周窗到且压差累计超阈值才置维护请求，只在周窗内允许复位；周序号由外部时标给出，跨年周序号回绕须正确处理；压差信号缺失时退化为纯周窗提醒并置降级；请求锁存至人工确认。",
 "FB_DL_LabelWeekCode":"标签打印需要周码/批码随日期滚动：周码按 ISO 周序号生成并在跨年时正确切换（含 53 周年），批码由周码与班次组合；打印触发须与打印就绪信号同步，避免半码打印；时标非法（未同步）时禁止出码并置码，宁可停线不可错码。",
 "FB_DL_AxisBacklashStepComp":"丝杠/齿轮反向间隙造成换向首段位置丢失：需在方向切换拍按组态间隙量注入一次补偿行程，补偿只加在换向首段、同向连续运动不得重复叠加；补偿量可标定与关闭，标定期间输出标定标志；位置出口必须连续，补偿注入不得形成台阶。",
 "FB_DL_BathTempHoldCtrl":"浸洗/电镀槽液温保温需与液位联锁：低液位禁止加热（防干烧），加热与循环泵启停须错时防局部过热；液温到达设定带内转保温，超温即断加热并报警；液位/温度信号失效按最保守停加热；保温期间记录超温累计时长供工艺追溯。",
}
ARCH = {
 "FB_DL_ValveCycleLifeCounter":"计数去抖 + 双源判据架构：以阀位开度跨越双阈值（开到位/关到位）的完整往复为一个循环，中间态不计数；扭角/力矩超限动作走独立累计器并置重载标志；计数与阈值比较分级（注意/预警/更换）带迟滞；复位分包（换阀清零 / 只清预警），防误清寿命账。",
 "FB_DL_BearingVibTrend":"滑窗 RMS + 基线比值双判据架构：段 0 无条件刷新窗口定时器与采样沿，段 1 累加平方和并在窗到时结算 RMS 与基线（长时常数指数基线），段 2 按 ISO 10816 三档 CASE 分档（含 ELSE 兜底）并做迟滞保持；启停/重标定屏蔽由外部使能位门控；非有限输入单列传感器失效。",
 "FC_DL_WetBulbCalc":"纯函数迭代反解架构：以干球温度与相对湿度算水汽分压，再对湿球温度做定步长牛顿/二分混合迭代，收敛判据用容差常量，迭代上限常量封顶防死循环；定义域三闸（RH∈(0,100]、T 在物理区间）先判，越界返回哨兵并置有效标志假；输出钳位为最后一次写。",
 "FB_DL_SignalStuckWatch":"双判据超时架构：段 0 无条件刷新「变化检测」与两个超时定时器；段 1 以容差判值是否变化、以差分判变化率是否恒零，二者同时成立且持续超时才置卡死；恢复任一判据即解除；报警锁存可选由组态位决定；出口在 eIdle 有确定值，不留陈旧。",
 "FB_DL_ConveyorSlipWatch":"速差比 + 负载门控架构：段 0 刷新窗口定时器与沿；段 1 算驱动辊线速度与从动速度的速差比，仅在电流高于负载阈值且已过启动加速窗时启用判据；段 2 速差比超限持续确认后置打滑并分档（轻微/严重）；传感器缺失走降级分支置降级标志，判据退化为电流单判。",
 "FB_DL_CaseShiftTally":"班次台账架构：班次边界沿触发结算（写上一班记录）并清本班累计；段 1 按合格/不合格双计数，差异 = 实绩 - 计划，达成率除零前判计划 >0；超差置提醒并锁存至确认；补记走独立入口并留痕标志；停线时段由外部使能门控不计节拍；出口量在 eIdle 显式清零。",
 "FC_DL_HaversineDistance":"纯函数球面几何架构：度转弧度后用 haversine 公式（1-cos 形式避免近距精度损失），atan2 反解中心角，乘地球平均半径得米；纬度绝对值闸（>90 拒绝）、经度按 180 环绕处理；输出钳位为非负；常量集中声明（半径、容差），无状态可重入。",
 "FB_DL_PumpSurgeGuard":"工况点裕度判据 + 斜坡降载架构：段 1 由流量与压比算距喘振线的相对裕度，裕度分三带（安全/逼近/喘振）带迟滞；逼近带请求开回流，喘振带请求降载并按斜坡限速下调设定；极端持续则请求跳闸；流量失效按最保守带处理并置码；全部为请求输出，不直写执行器。",
 "FB_DL_GreaseLubeTimer":"双计数器先到先报架构：运行小时按 Δt 累加、动作沿按次累加，任一达阈值即置请求并锁存；请求期间继续累计但不再重复置位；确认沿（或换脂信号）双计同清；加脂泵反馈超时未到置码但不解除请求；计数饱和上限防溢出回绕；出口含剩余小时与剩余次数双读数。",
 "FB_DL_PulseTrainDecoder":"脉宽分级 + 序列还原架构：段 0 无条件刷新上升沿与两个脉宽定时器；段 1 按脉宽落入门限区间判长/短脉冲，累积位串后按位权还原档位；超时未完序列或脉冲数越界置错并保持上次有效值；多沿同拍按最保守（判错）处理；输出档位只在完整序列结束时更新一次。",
 "FC_DL_PeriodJitterCalc":"纯函数统计架构：单趟遍历求 max/min/和/平方和，再据样本数算均值与样本标准差（n-1 口径），n<2 时标准差置 0 且有效标志假；极差 = max-min；分母先判再除；输出钳位为非负；数组长度入口钳位到容器上界，越界部分忽略并置截断标志。",
 "FB_DL_SensorDriftBaseline":"长时常数基线跟踪架构：基线按受限一阶滤波缓慢跟随（更新率上限防把阶跃学成漂移），残差 = 实时值 - 基线，残差绝对值超限持续确认后置漂移报警并输出漂移速率（长窗斜率）；标定确认沿重置基线并清报警；非有限输入冻结基线更新并置传感器失效。",
 "FB_DL_FilterWeekWindow":"周窗 + 累计双判据架构：周序号变化沿触发周窗开启，压差按 Δt 累加；周窗内且累计超阈值才置维护请求，请求锁存至人工确认沿；复位仅在周窗内允许（防随意清账）；跨年周序号回绕用取模归正；压差缺失走纯周窗降级分支并置降级；出口含本周累计与剩余天数。",
 "FB_DL_LabelWeekCode":"周码生成 + 打印同步架构：由外部时标算 ISO 周序号（含 53 周年判定），与班次码组合为批码；打印请求须在打印就绪电平有效时才发脉冲，脉冲宽度定宽避免半码；时标未同步（无效标志）直接拒绝出码并置码；跨周边界当拍只结算一次，防重复出码。",
 "FB_DL_AxisBacklashStepComp":"换向首段注入架构：段 1 由指令增量符号判方向，方向切换拍置补偿待发标志，随后按组态间隙量单次注入到位置指令出口（注入量与斜坡限速），同向连续运动不再叠加；补偿关闭位与标定模式位并存，标定期间输出标定标志；出口保证连续不跳变，注入后清标志。",
 "FB_DL_BathTempHoldCtrl":"温度带保温 + 液位联锁架构：段 0 无条件刷新超温/低液位两个确认定时器；段 1 状态机（eIdle/eHeat/eHold/eAlarm）按设定带与回差迁移，低液位任何相立即断加热并进 eAlarm；段 2 出口加热/循环请求与超温累计时长；信号非有限按失效停加热；出口在 eIdle 有确定值。",
}
REWORK_NOTE = {
 "FB_DL_AxisHomeRepeatVerify":"R53 返修 v1.0.1（REVIEW_R52 2.1/2.2）：bPass/bReject 段 1 无条件预清移入 eCollect 结算拍前，eDone 相保持判定电平（消除「既非 Pass 亦非 Reject」第三态）；eIdle 补清出口 nGot/bPass/bReject，与内部副本同步。",
 "FB_DL_PidParamDriftAudit":"R53 返修 v1.0.1（REVIEW_R52 3.1/3.2）：六处参数有限性闸补 `(x-x)=(x-x)` 差判拦 Inf（Inf-Inf→NaN 致越差判据静默漏报）；bDriftAny 改由三项确认位 OR 同源重算；_fHun 迁入 VAR CONSTANT 收口魔法数。",
 "FB_DL_HeatTraceCircuitMon":"R53 返修 v1.0.1（REVIEW_R52 4.1）：段 0 两定时器 IN 串 eMon 相位闸（eIdle/eFault 不再累积），消除「使能当拍即锁存断缆」与首窗即刻结算误报；eIdle→eMon 迁入拍补 _fTempT0/_bT0Ok 温升基点快照；仍保持段 0 无条件调用形式。",
 "FB_DL_BrakeResistorThermal":"R53 返修 v1.0.1（REVIEW_R52 5.1/5.2）：温升估算由「能量占额线性斜率」改热阻功率比口径（稳态功率比 × 满载温升），与一阶冷却模型量纲自洽；组态闸加 fEnergyMax 与 I²R·τ 派生量一致性校验（默认域随之重标定）；占额饱和处回夹累计能量；eIdle 补出口镜像并按 -T/tauCool 冷却衰减。",
}
ARCH_RW = {
 "FB_DL_AxisHomeRepeatVerify":"判定保持架构：结算拍内先清后置（当拍二选一），eDone 相仅保持不清，出口电平与声明一致；样本统计与实时位置镜像严格分离；复位/失能路径两出口显式清零。",
 "FB_DL_PidParamDriftAudit":"有限性闸双写法（自反 + 差判）统一范式：NaN 与 Inf 均被拦，非有限拍进安全侧报警而非静默；汇总位由分项同源 OR 派生，杜绝「分项 TRUE 汇总 FALSE」；常量集中声明。",
 "FB_DL_HeatTraceCircuitMon":"相位闸门控架构：定时器仍无条件调用但 IN 由状态相门控，跨相不累积；判定窗口起点在迁入拍显式快照，保证升温窗口只量本相温升。",
 "FB_DL_BrakeResistorThermal":"热阻功率比模型架构：稳态温升由功率比 × 满载温升给出，暂态由一阶冷却项修正；能量额度组态一致性前置校验，默认参数按 I²R·τ 派生重标定，额定工况落在 70% 以内。",
}

def main():
    shutil.copy2(REG, REG + ".bak_r53")
    shutil.copy2(JSONL, JSONL + ".bak_r53")
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
                      "code_segment": "", "source": "r53-plan"})
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
    reg["version"] = "2.45.0"
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
    # ---- ROADMAP tick ----
    rl = io.open(ROADMAP, encoding="utf-8").read().splitlines()
    ticked = 0
    for lnno in TICK_LINES:
        i = lnno - 1
        if 0 <= i < len(rl) and rl[i].startswith("- [ ]"):
            rl[i] = "- [x]" + rl[i][5:]
            ticked += 1
    io.open(ROADMAP, "w", encoding="utf-8", newline="").write("\n".join(rl) + "\n")
    left = sum(1 for x in rl if x.startswith("- [ ]"))
    print("roadmap: ticked=%d, pending_left=%d" % (ticked, left))
    return 0 if bad == 0 else 1

main()
