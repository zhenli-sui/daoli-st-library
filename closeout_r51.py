#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r51.py —— R51 主控直跑收口（R335）：注册 20 新件 + 4 返修升版 + JSONL 增量，原子写回。"""
import io, os, json, shutil

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
NOW = "2026-11-20T10:40:00+08:00"

NEW = [
 ("FB_DL_AhuFanArrayTrim","DL_Process","FB",4,["roadmap-pool","hvac-fab","clean-room"]),
 ("FB_DL_ElectrodeGapMark","DL_Process","FB",4,["roadmap-pool","battery-fab","clean-room"]),
 ("FB_DL_FormationChannelQueue","DL_Process","FB",4,["roadmap-pool","battery-fab","queue-sched","clean-room"]),
 ("FB_DL_SlurryDensityTrim","DL_Process","FB",3,["roadmap-pool","battery-fab","clean-room"]),
 ("FB_DL_FilmSpliceWeekPlan","DL_Process","FB",3,["roadmap-pool","maintenance-win","clean-room"]),
 ("FB_DL_CasePackerPatternVerify","DL_Process","FB",3,["roadmap-pool","packaging","clean-room"]),
 ("FB_DL_ChillerYearWinStart","DL_Process","FB",3,["roadmap-pool","hvac-fab","clean-room"]),
 ("FB_DL_ReactorYearWinClean","DL_Process","FB",3,["roadmap-pool","process-win","clean-room"]),
 ("FB_DL_LoopAuditTrailWindow","DL_Process","FB",4,["roadmap-pool","audit-trail","isa-18-2","clean-room"]),
 ("FB_DL_LamEvaGelContent","DL_Process","FB",3,["roadmap-pool","pv-fab","clean-room"]),
 ("FB_DL_PalletLabelVerify","DL_Process","FB",3,["roadmap-pool","packaging","ean-verify","clean-room"]),
 ("FB_DL_ElectrolyteFillVacuum","DL_Process","FB",3,["roadmap-pool","battery-fab","clean-room"]),
 ("FB_DL_DateCoderPosition","DL_Process","FB",3,["roadmap-pool","packaging","clean-room"]),
 ("FB_DL_SteamTrapSurvey","DL_Device","FB",3,["roadmap-pool","utility-health","clean-room"]),
 ("FC_DL_PolarDecomp2D","DL_MathData","FC",3,["lgf-math","matrix-decomp","clean-room"]),
 ("FB_DL_TrayLoadVacuum","DL_Process","FB",3,["roadmap-pool","pv-fab","clean-room"]),
 ("FB_DL_CupFillDenest","DL_Process","FB",4,["roadmap-pool","packaging","clean-room"]),
 ("FB_DL_HumidifierAdiabat","DL_Process","FB",3,["roadmap-pool","hvac-fab","clean-room"]),
 ("FB_DL_NgBinDosing","DL_Process","FB",4,["roadmap-pool","weigh-dosing","clean-room"]),
 ("FC_DL_MadZScore","DL_MathData","FC",2,["lgf-measurement","robust-stat","clean-room"]),
]
REWORK = [
 ("FB_DL_RulEstimator","DL_Algo"),
 ("FB_DL_ExtremumSeekCtrl","DL_Algo"),
 ("FB_DL_MoveResumeSeg","DL_Motion"),
 ("FB_DL_LoopCoupleDetect","DL_Algo"),
]
INSTR = {
 "FB_DL_AhuFanArrayTrim":"洁净室空调箱多台风机并联运行，风压随开启台数与滤网压差漂移，需要按台数分级投切并用静压闭环微调转速维持设定静压；投切须防相邻档位频繁震荡，最小运行台数与最大台数组态钳位，静压偏差带内保持不动；边界：档位防抖、台数钳位、偏差死区。",
 "FB_DL_ElectrodeGapMark":"涂布极片需在留白区打标记并判定与对齐基准的偏差，传感器采样在高速走带下存在毛刺，标记位置须做沿锁存与容差窗判定，超窗记错位计数不联动停机（联动由上游决策）；边界：沿锁存、容差窗、错位计数、非有限位置预检。",
 "FB_DL_FormationChannelQueue":"化成柜数十通道共享工装位，需按优先级排队并支持故障通道自动摘除重排；队列深度组态钳位，同优先级按到达序 FIFO，摘除通道的在制数据保留供追溯；边界：队列越界钳位、故障摘除沿、FIFO 次序稳定。",
 "FB_DL_SlurryDensityTrim":"浆料面密度与密度计双源交叉校核，两源偏差超限说明单源漂移须分档告警（信息/预警/故障）而非直接采信某一路；偏差窗口重算防瞬时波动误报，容差组态非法（≤0）冻结判定置故障码；边界：双源交叉、窗口重算、三级分档。",
 "FB_DL_FilmSpliceWeekPlan":"接膜/耗材保养按自然周窗排程，窗口起始日与时长可组态，到期提醒锁存直至确认；跨班次只提醒一次防刷屏，非窗期请求被拒并置码；边界：周窗计算、提醒锁存、单次提醒。",
 "FB_DL_CasePackerPatternVerify":"装箱机按图案模式（行列位图）排列纸箱，错位/重叠即拒绝启动并指出首个错误位；位图尺寸与实际托盘一致性在复位沿校验，数组下标全程钳位；边界：位图校验、首错定位、下标钳位。",
 "FB_DL_ChillerYearWinStart":"冷机年度保养窗内才允许启动大修操作，非窗启动请求拒绝并留码；窗口由年计划日期+时长生成，跨年边界正确处理；互锁与运行反馈分离输出；边界：年窗跨年、请求拒绝锁存、互锁分离。",
 "FB_DL_ReactorYearWinClean":"反应釜年度清洗窗与批次闸门联动：窗内放行清洗批，窗外批次请求冻结并置码；清洗轮次计数与窗内超时告警独立；边界：批次闸门、轮次计数、超时告警、复位全清。",
 "FB_DL_LoopAuditTrailWindow":"控制回路参数整定需审计留痕：变更请求须双人确认位齐全才落账，审计窗内参数快照环形存档供追溯；确认位超时未齐则请求失效重计；边界：双人确认、环形留痕钳位、快照副本隔离。",
 "FB_DL_LamEvaGelContent":"层压件 EVA 交联度按工艺模型估算并判合格窗，模型输出非有限或超物理域（0~100%）直接判故障不外推；采样节拍 TON 无条件刷新，合格窗迟滞防临界抖动；边界：域钳位、非有限防护、迟滞窗。",
 "FB_DL_PalletLabelVerify":"托盘标签 EAN 校验位验证与错标拦截，字符串逐位提取禁用 ORD 方言，用 LEN+MID 标准口径（R196 先例）；长度非法或校验位不符即拦截并记录错误类别；边界：长度闸、校验位、逐位防越界。",
 "FB_DL_ElectrolyteFillVacuum":"注液工序真空度需静置计时台账：真空到位沿启动静置 TON（无条件刷新），中途破空则计时冻结保留进度，恢复后续走；台账条目环形存档钳位；边界：到位沿、冻结续走、环形台账。",
 "FB_DL_DateCoderPosition":"喷码日期字符位置偏移与缺失检测：基准位与容差窗组态，字符缺失（空窗）与偏移超窗分别置不同错误码便于定位；图像触发沿锁存单帧判定；边界：容差窗、缺失/偏移双码、沿锁存。",
 "FB_DL_SteamTrapSurvey":"疏水阀周期性温度特征普查判失效分级（健康/亚健康/失效）：按周期窗采样温度特征并与健康基线带比较，基线可组态，连续多周期越带才降级防误判；边界：周期窗、迟滞带、连续越带判据。",
 "FC_DL_PolarDecomp2D":"2D 矩阵极分解（正交因子×对称因子）用于应力主方向提取：奇异值由不变量解析式给出，病态矩阵（行列式近零）显式拒绝防除零；主方向角归一到约定区间；纯函数无状态，容差常量化便于移植调参。",
 "FB_DL_TrayLoadVacuum":"电池片花篮真空取放：真空到位沿锁存后升降动作，放件先破真空吹气定宽脉冲（独立 TON 单稳）再撤离，破空不齐即中止并置码；边界：到位沿、定宽脉冲、中止码。",
 "FB_DL_CupFillDenest":"杯装灌装机取杯-灌装-封口节拍链顺控：缺杯检测旁站触发补杯重试有限次后故障锁存；各工位完成信号沿触发推进，CASE 全分支含 ELSE 兜底；边界：缺杯重试上限、节拍链状态机、完成沿。",
 "FB_DL_HumidifierAdiabat":"绝热加湿器补水顺控：水位双限（启停带）控制补水阀，排水周期窗独立节拍，水位信号失效（非有限/长时间无变化）按失效保护停补水；边界：双限带、排水周期、失效保护。",
 "FB_DL_NgBinDosing":"NG 料返投称重定量：目标量与快加/精加切换点组态，称重传感器非有限保持上拍，超差自动学习禁用（组态开关）防劣化发散；落差自动补偿限幅；边界：双段给料、非有限防护、学习禁用组态。",
 "FC_DL_MadZScore":"中位数绝对偏差（MAD）稳健离群评分纯函数：中位数由排序副本计算不改原数组，MAD=0 时退化为恒等比较并显式处理防除零；评分 = |x-median|/(1.4826·MAD)，容差与一致性常量集中声明；边界：副本排序、MAD=0 退化、非有限预检。",
}
ARCH = {
 "FB_DL_AhuFanArrayTrim":"分级投切+静压闭环双环架构：台数档位状态机含防抖驻留窗（TON 无条件刷新）防相邻档震荡，静压 PI 微调在档内闭环；台数组态入口钳位只读副本；偏差死区带内冻结积分防抖动；档位/转速/告警三线分离出口。",
 "FB_DL_ElectrodeGapMark":"沿锁存+容差窗判定架构：标记位置由 R_TRIG 沿锁存（无条件刷新），偏差对基准窗比较，超窗只累加错位计数不直接联锁；非有限位置入口预检置码；留痕计数器出口供 MES 追溯；锁存副本与实时镜像严格分离（R38 范式）。",
 "FB_DL_FormationChannelQueue":"优先级队列环形数组架构：入队按优先级分档、同档 FIFO 到达序，故障摘除沿把在制条目标记保留位不物理删除；队列深度钳位、头尾下标全程环回钳位；派发优先级锁存 _nPrioDispL 保证同拍一致；摘除/入队/派发三事件分离置码。",
 "FB_DL_SlurryDensityTrim":"双源交叉校核架构：偏差=|面密度-密度换算值|在窗口 TON 到时重算（无条件刷新），三级分档 CASE 含 ELSE 兜底；容差≤0 组态闸冻结判定置故障码；非有限样本跳过并保持上拍结论；分档结论锁存至下窗。",
 "FB_DL_FilmSpliceWeekPlan":"周窗计算架构：系统日期换算周序号，窗起点+时长组态校验（时长>0）在复位沿一次性锁存；到期提醒沿锁存单次防刷屏，确认沿清除；非窗期请求拒绝置码；纯日历逻辑+少量 TON，无复杂状态机。",
 "FB_DL_CasePackerPatternVerify":"位图校验架构：模式位图与实际尺寸一致性复位沿校验锁存，逐格扫描首错即停并记录行列索引，下标全程钳位；重叠=相邻格同置位判据；校验结果沿输出锁存一拍；纯组合扫描无定时器，扫描周期确定。",
 "FB_DL_ChillerYearWinStart":"年窗生成+闸门架构：计划日期+时长生成窗口（跨年用年序号递推），窗内 bInWin 直通闸门；非窗启动请求沿锁存拒绝码直至窗内清除；互锁判定先于启动判据形成优先级短路；年序号换算集中一个纯函数便于测试。",
 "FB_DL_ReactorYearWinClean":"批次闸门+轮次计数架构：清洗窗内放行、窗外冻结置码；轮次计数器随清洗完成沿递增，窗内超时 TON（无条件刷新）告警；复位全清轮次与告警；闸门结论与运行反馈分离输出，便于上游分权。",
 "FB_DL_LoopAuditTrailWindow":"双人确认+环形留痕架构：变更请求需两确认位齐（沿触发）才落账，任一确认超时 TON 到时请求失效重计；参数快照写入环形存档数组，写指针环回钳位，快照为锁存副本与实时参数分离（R38）；留痕条目带时间序号供追溯。",
 "FB_DL_LamEvaGelContent":"模型估算+合格窗迟滞架构：交联度估算输出先做物理域钳位（0~100%）与非有限预检，超域直接故障不外推；合格窗上/下限带迟滞防临界抖动；采样节拍 TON 循环体内无条件刷新；估算模型系数常量化集中声明。",
 "FB_DL_PalletLabelVerify":"字符串逐位标准口径架构：LEN 长度闸先行，MID 单字符提取+10 分支 ELSIF 值链（禁 ORD 方言，R196 先例）；校验位按 EAN 加权规则累加比较；错误类别（长度/校验位/非数字字符）分码输出；纯函数核+拦截沿锁存。",
 "FB_DL_ElectrolyteFillVacuum":"真空到位沿+冻结续走架构：到位沿锁存启动静置 TON（循环体内无条件刷新），破空信号使计时保持（清 IN 前锁存已计时长，恢复后按剩余时长续走）；台账环形数组写指针环回钳位；中止/恢复/完成三事件分别置码。",
 "FB_DL_DateCoderPosition":"基准窗双判架构：字符位置对基准+容差窗比较，缺失（空窗）与偏移超窗输出不同错误码便于定位；图像触发沿锁存单帧判定，帧间结果不穿透；容差组态>0 校验在复位沿一次性完成；纯比较逻辑无内部状态机。",
 "FB_DL_SteamTrapSurvey":"周期窗采样+基线带分级架构：周期 TON 到时采样温度特征入环形窗，特征量与基线带比较，连续 N 周期越带才降级（计数器防御）；分级三档 CASE 含 ELSE 兜底；基线组态域校验复位沿锁存；采样副本与实时镜像分离。",
 "FC_DL_PolarDecomp2D":"解析式极分解架构：2D 矩阵不变量（迹/行列式）直接给出奇异值与旋转角，避免迭代；行列式绝对值<容差判定病态拒绝防除零；角度归一化到 [-π,π) 区间纯算术实现；无状态纯函数，输出正交因子与主方向角，容差常量化。",
 "FB_DL_TrayLoadVacuum":"单稳脉冲+沿锁存架构：真空到位沿锁存后才允许升降推进；破空吹气用独立 TON 单稳定宽脉冲（IN 带 NOT 自复位范式 FB33-2），脉冲完成沿才撤离；破空不齐（吹气中真空回升）中止置码；取放两态状态机 CASE 含 ELSE。",
 "FB_DL_CupFillDenest":"节拍链状态机（Denest/Fill/Seal/Eject）：各工位完成信号 R_TRIG 沿触发推进（无条件刷新）；缺杯旁站检测触发补杯重试计数上限，超限故障锁存需显式复位；CASE 全分支含 ELSE 兜底；工位间握手指令单拍脉冲防粘滞。",
 "FB_DL_HumidifierAdiabat":"双限带+失效保护架构：水位启停带回差控制补水阀（防频繁切换），排水周期窗独立 TON 节拍（无条件刷新）；水位信号非有限或长时间无变化判失效，按失效保护关阀停补水并置码；阀反馈与指令分离输出。",
 "FB_DL_NgBinDosing":"双段给料+落差补偿架构：快加到切换点（目标-落差）转精加，落差补偿量自动学习但受组态开关禁用与限幅钳位防劣化发散；称重非有限保持上拍并置信息码；超差结论锁存至下次给料；给料完成沿输出单拍。",
 "FC_DL_MadZScore":"稳健统计纯函数架构：中位数用排序副本（不改原数组）取中元素；MAD 乘一致性常量 1.4826，MAD≈0 显式退化分支（退化为阈值比较）防除零；非有限输入入口预检直接故障码；排序用标准 FOR 冒烟插排（规模小），无状态可重入。",
}
REWORK_NOTE = {
 "FB_DL_RulEstimator":"R51 返修 v1.0.1：LS 回归改自最旧样本槽按时间序环回遍历（R194：环窗自变量用时间序号，禁用环形槽位号），统计段与残差段同款映射，验收向量补环回一致性 V4，消除窗回卷后斜率符号翻转。",
 "FB_DL_ExtremumSeekCtrl":"R51 返修 v1.0.1：删相位推进 2.0 倍因子（扰动频率与组态周期一致）；tonWin 改自复位（IN 带 NOT tonWin.Q）到时单拍清窗统计，bWindowFull 语义同步为窗到时单拍脉冲，与头注释滚动窗口径对齐。",
 "FB_DL_MoveResumeSeg":"R51 返修 v1.0.1：_bDir 改进入 eResume 相锁存（删每拍重派生与段 1 预清），越目标（剩余量符号与锁定方向反号）一律收口，与边界③一致。遗留：fStartRst 引脚未被读取属存量死引脚，挂 R52 裁决。",
 "FB_DL_LoopCoupleDetect":"R51 返修 v1.0.1：文档级更正 3 处禁词注释引文（逻辑零变更）。",
}
ARCH_RW = {
 "FB_DL_RulEstimator":"环形窗 LS 回归时间序架构：自变量由 _nHead-_nFill 反推最旧槽起按时间序环回遍历（R194 范式），统计段与残差段同款映射保证符号一致；验收向量 V1 线性精确复原+V4 环回一致性双验；本版消除窗回卷符号翻转。",
 "FB_DL_ExtremumSeekCtrl":"极值搜索扰动+梯度估计架构：相位推进与组态周期严格一致（删 2 倍因子）；滚动窗改自复位 TON（IN 带 NOT tonWin.Q，FB33-2 范式）到时单拍结算清窗；bWindowFull 单拍脉冲语义；梯度符号判据与窗结算同步。",
 "FB_DL_MoveResumeSeg":"恢复段方向迁相锁存架构：_bDir 在进入 eResume 相一次性锁存（删每拍重派生），越目标判定以剩余量符号与锁定方向反号为准统一收口；段推进游标与方向解耦；本版消除重派生导致的方向抖动。",
 "FB_DL_LoopCoupleDetect":"环路耦合检测：以指令-反馈互相关窗口判耦合方向与强度，窗口 TON 无条件刷新；本版仅文档注释更正（禁词引文转述化，R195），逻辑零变更。",
}

def main():
    shutil.copy2(REG, REG + ".bak_r51")
    shutil.copy2(JSONL, JSONL + ".bak_r51")
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
                      "code_segment": "", "source": "r51-plan"})
        added.append(name)
    if skipped:
        print("SKIP:", skipped)
    rw_done = []
    for name, cat in REWORK:
        for c in comps:
            if c["name"] == name:
                c["version"] = "1.0.1"
                p = os.path.join(ROOT, cat, name + ".st")
                c["line_count"] = len(io.open(p, encoding="utf-8").read().strip().splitlines())
                rw_done.append(name); break
    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["counts"] = {k: counts.get(k, 0) for k in
                     ("DL_Base","DL_MathData","DL_Algo","DL_Device","DL_Motion","DL_Process")}
    reg["total_components"] = len(comps)
    reg["version"] = "2.43.0"
    reg["last_updated"] = NOW
    tmp = REG + ".tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="") as f:
        json.dump(reg, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, REG)
    print("registry: %d comps, counts=%s, added=%d, rework=%d"
          % (len(comps), reg["counts"], len(added), len(rw_done)))
    # ---- JSONL ----
    lines = io.open(JSONL, encoding="utf-8").read().splitlines()
    out, reinj = [], []
    rwdict = dict(REWORK)
    for ln in lines:
        if not ln.strip():
            continue
        obj = json.loads(ln)
        nm = None
        for rname, _ in REWORK:
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

if __name__ == "__main__":
    sys.exit(main()) if False else main()
