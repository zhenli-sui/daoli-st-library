# -*- coding: utf-8 -*-
"""R80 收尾：registry 登记 + JSONL 追加 + 三数一致性核对
用法:
  python r80_closeout.py --dry            # 只打印将入库的件
  python r80_closeout.py                  # 真正写入
只登记 gate 判定为 PASS 的件。
"""
import json, os, re, sys, shutil, datetime

BASE = r"C:\Library"
STG = os.path.join(BASE, "_Staging_Raw", "2026-11-24")
REG = os.path.join(BASE, "INDEX_REGISTRY.json")
JSONL = os.path.join(BASE, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
ROUND = "R80"
NOW = datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()

# plan 元数据（与 ROUND_PLAN_R80.md 对齐）
META = {
"FC_DL_WeighNetFromGross":("DL_Process","毛重/皮重→净重换算，含零点偏置与负净重抑制",1),
"FC_DL_WeighTareDriftCheck":("DL_Process","皮重漂移超限判定（滑动均值对比标定值）",2),
"FC_DL_WeighDoseTolBand":("DL_Process","配料公差带判定（欠/合格/超），含最小有效量阈值",2),
"FB_DL_WeighHopperRefillSeq":("DL_Process","料斗补料状态机（空闲/开阀/粗加/精加/稳定/超时）",3),
"FC_DL_WeighMultiHeadSum":("DL_Process","多头秤组合求和与最优组合挑选（小数组）",2),
"FC_DL_WeighBatchYieldCalc":("DL_Process","批产率计算（实际投料/理论投料），含除零保护",1),
"FC_DL_WeighCreepCompensate":("DL_Process","蠕变补偿（按加载时长线性修正系数）",1),
"FC_DL_WeighSpanCalibRatio":("DL_Process","量程标定比值计算与合理性校验",1),
"FC_DL_HydroCylForceCalc":("DL_Device","液压缸推力/拉力计算（含背压与机械效率）",1),
"FC_DL_HydroCylFlowNeed":("DL_Device","液压缸所需流量与阀口通流能力校核",1),
"FC_DL_HydroAccumulatorSizing":("DL_Device","蓄能器容积估算（绝热/等温双口径）",3),
"FC_DL_PneuAirConsumeCalc":("DL_Device","气缸单次行程耗气量（标准状态折算）",1),
"FC_DL_PneuCvFlowCalc":("DL_Device","Cv 值→额定流量换算（含压差比临界判断）",2),
"FC_DL_HydroPipePressDrop":("DL_Device","管路沿程压降（达西-魏斯巴赫简化）",2),
"FB_DL_HydroPressRampSeq":("DL_Device","液压建压/卸压斜坡状态机（含超时与泄压确认）",3),
"FC_DL_PneuLeakRateCalc":("DL_Device","气路泄漏率估算（压降法，含温度修正）",2),
"FC_DL_RefCopCalc":("DL_Device","制冷 COP/EER 计算（含功率为零保护）",1),
"FC_DL_RefSuperheatCalc":("DL_Device","吸气过热度计算与异常判别",1),
"FC_DL_RefSubcoolCalc":("DL_Device","过冷度计算与充注量倾向判据",1),
"FC_DL_RefSatPressToTemp":("DL_Device","制冷剂饱和压力→温度（R134a/R410A 双表）",2),
"FC_DL_RefSatTempToPress":("DL_Device","制冷剂饱和温度→压力（分段线性反查）",2),
"FC_DL_RefCompressorCapacity":("DL_Device","压缩机实际输气量与容积效率估算",3),
"FC_DL_RefCondApproach":("DL_Device","冷凝器逼近温差与脏堵趋势判定",2),
"FC_DL_StatsRangeCalc":("DL_MathData","数组极差（max-min）与有效样本数",1),
"FC_DL_StatsIqrCalc":("DL_MathData","四分位距 IQR 与 Tukey 栅栏上下界",2),
"FC_DL_StatsPooledStd":("DL_MathData","两组合并标准差（pooled），含组内方差为负防护",2),
"FB_DL_StatsRollingVar":("DL_MathData","固定窗滚动方差（环形缓冲 O(1) 更新）",3),
"FC_DL_StatsGeoMeanCalc":("DL_MathData","几何均值（对数域累加，含非正值剔除）",2),
"FC_DL_StatsDevSumSq":("DL_MathData","离差平方和与自由度（供回归/ANOVA 复用）",1),
"FC_DL_MembraneFluxCalc":("DL_Process","膜通量 LMH 计算与衰减率",1),
"FC_DL_MembraneTmpCalc":("DL_Process","跨膜压差 TMP（含平均压力口径双选）",1),
"FC_DL_WaterRecoveryRatio":("DL_Process","系统回收率（产水/进水），含浓水侧校核",1),
"FC_DL_SludgeAgeCalc":("DL_Process","污泥龄 SRT（泥量/排泥速率），含除零保护",2),
"FC_DL_DoDeficitCalc":("DL_Process","溶解氧偏差与曝气需求趋势判据",1),
"FC_DL_CoagulantDoseCalc":("DL_Process","混凝剂投加量（按浊度/流量前馈）",2),
"FC_DL_WaterLangelierIndex":("DL_Process","朗格利尔饱和指数 LSI 结垢/腐蚀判定",3),
"FB_DL_MultiTankBlendSeq":("DL_Process","多罐调和序列（进料/循环/取样/放行），ENUM+CASE 全出口",4),
"FB_DL_ConveyorMergePrioritySeq":("DL_Process","汇流合流优先权仲裁（含防堵车与抢占恢复）",3),
"FB_DL_DryerZoneProfileSeq":("DL_Process","多温区烘干升温曲线执行（斜率限制+超温退避）",4),
"FB_DL_RefDefrostCycleSeq":("DL_Device","冷风机除霜循环（判霜/融霜/滴水/恢复），含超时兜底",4),
}
SCENE = {
 "DL_Process":"过程工艺（配料/水处理/反应釜）",
 "DL_Device":"设备驱动（液压气动/制冷机组）",
 "DL_MathData":"数学与数据换算",
 "DL_Base":"基础通用",
 "DL_Algo":"算法",
 "DL_Motion":"运动控制",
}
TAGMAP = {
 "DL_Process":["process"],"DL_Device":["device"],"DL_MathData":["mathdata"],
}
KEYWORD_TAGS = [
 ("weigh","weighing"),("hopper","dosing"),("dose","dosing"),("calib","calibration"),
 ("hydro","hydraulic"),("pneu","pneumatic"),("ref","refrigeration"),("cop","efficiency"),
 ("stats","statistics"),("iqr","statistics"),("var","statistics"),("std","statistics"),
 ("membrane","watertreatment"),("sludge","watertreatment"),("water","watertreatment"),
 ("langelier","watertreatment"),("blend","sequence"),("seq","sequence"),
 ("conveyor","materialflow"),("dryer","thermal"),("defrost","refrigeration"),
]


def load_gate():
    hits = {}
    for fn in ("_gate_R80_A.json", "_gate_R80_B.json"):
        p = os.path.join(STG, fn)
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        for it in d.get("items", []):
            hits[it["name"]] = it.get("result", "").upper()
    return hits


def tags_for(name, cat):
    low = name.lower()
    t = list(TAGMAP.get(cat, ["process"]))
    for kw, tag in KEYWORD_TAGS:
        if kw in low and tag not in t:
            t.append(tag)
    t.append("r80")
    return t


def strip_header(src):
    return src


def build_instruction(name, cat, func, cx):
    kind = "功能块（FB）" if name.startswith("FB_") else "函数（FC）"
    scen = SCENE.get(cat, "工业控制")
    return (
        "在%s类项目的%s场景中，需要实现 %s 组件：%s。"
        "请用 IEC 61131-3 结构化文本实现一个%s，要求零全局变量、零厂商专用指令、"
        "跨平台可移植（CODESYS 3.5 / TwinCAT 3 / 步科 / 汇川），并满足："
        "①所有除法前判分母为零；②数组下标钳位防越界；③浮点比较使用容差而非精确相等；"
        "④非法输入时返回有效标志 bValid=FALSE 并输出安全默认值，不得产生不确定输出；"
        "⑤%s"
        % (scen, cat.replace("DL_", "").lower(), name, func, kind,
           "状态机须用 ENUM+CASE 且每个状态有明确出口、故障态可复位、等待收敛相配超时兜底。"
           if name.startswith("FB_") else "纯计算不留内部状态，可重入。")
    )


def build_thought(name, cat, func, cx, src):
    is_fb = name.startswith("FB_")
    has_enum = "TYPE" in src and "END_TYPE" in src
    has_case = re.search(r"\bCASE\b", src) is not None
    has_ton = "TON" in src
    has_guard = "bValid" in src
    parts = []
    parts.append("【需求解析】%s；属 %s 子库，复杂度 C%d。" % (func, cat, cx))
    parts.append("【接口与分工】按 IEC 61131-3 %s 组织：VAR_INPUT 入参 / VAR_OUTPUT 出参%s；"
                 "全部变量行内中英双语注释，边界单位在注释中显式声明。"
                 % ("FUNCTION_BLOCK" if is_fb else "FUNCTION",
                    " / VAR 内部状态" if is_fb else ""))
    if has_enum and has_case:
        parts.append("【状态机设计】用 TYPE ... END_TYPE 定义私有 ENUM 状态集，"
                     "CASE 分相驱动，ELSE 分支兜底到故障态；每个相都有明确转移条件，"
                     "不留无界驻留相。")
    if has_ton:
        parts.append("【时序设计】TON 实例在 CASE 外无条件周期刷新，CASE 内只读 .Q/.ET，"
                     "避免相切换时定时器停摆或重复初始化。")
    parts.append("【防错设计】入口先做域闸（分母零值、下标越界、量程越限、负值非法），"
                 "任一不满足即置 bValid=FALSE 并输出安全默认值；"
                 "浮点比较使用 ABS(a-b)<=EPS 容差；非有限值用 ABS(x)>1.0E30 判定"
                 "（不使用 ABS(x-x) 这类恒假谓词）。")
    parts.append("【OOP 解耦】不引用任何 GVL/VAR_EXTERNAL，不写 %%I/%%Q 物理地址，"
                 "由调用方以接口变量注入，保证同一件可在不同硬件平台复用。")
    if is_fb:
        parts.append("【可测试性】故障码 nFaultCode 逐值可观测，复位出口唯一（复位即回 eIdle 并清零全部输出），"
                     "便于在仿真台架上穷举状态迁移。")
    return " ".join(parts)


def main():
    dry = "--dry" in sys.argv
    gate = load_gate()
    if not gate:
        print("NO GATE RESULT FOUND")
        return 1
    passed, failed = [], []
    for name in META:
        r = gate.get(name, "MISSING")
        (passed if r == "PASS" else failed).append((name, r))
    print("gate total=%d PASS=%d NOT-PASS=%d" % (len(gate), len(passed), len(failed)))
    for n, r in failed:
        print("  SKIP", n, r)
    if dry:
        print("DRY RUN — no write")
        return 0

    reg = json.load(open(REG, encoding="utf-8"))
    existing = {c["name"] for c in reg["components"]}
    bak = REG + ".bak_r80"
    if not os.path.exists(bak):
        shutil.copy2(REG, bak)
    jbak = JSONL + ".bak_r80"
    if not os.path.exists(jbak):
        shutil.copy2(JSONL, jbak)

    added, skipped_exist = [], []
    for name, _ in passed:
        if name in existing:
            skipped_exist.append(name)
            continue
        cat, func, cx = META[name]
        fp = os.path.join(BASE, cat, name + ".st")
        if not os.path.exists(fp):
            print("  !! no file", fp)
            continue
        src = open(fp, encoding="utf-8").read()
        typ = "FB" if name.startswith("FB_") else "FC"
        reg["components"].append({
            "name": name, "category": cat, "type": typ, "file_path": fp,
            "function_tags": tags_for(name, cat),
            "complexity": cx, "registered_at": NOW,
            "origin": {"mode": "internal", "source": "道莅原创（R80 批次）",
                       "license": "MIT", "ref_tag": cat.lower()},
            "l2_status": "l2-pass",
        })
        added.append(name)

    # counts
    reg["counts"] = {}
    for c in reg["components"]:
        reg["counts"][c["category"]] = reg["counts"].get(c["category"], 0) + 1
    reg["total_components"] = len(reg["components"])
    reg["version"] = "2.72.0"
    reg["last_updated"] = NOW
    assert sum(reg["counts"].values()) == reg["total_components"], "counts mismatch"
    json.dump(reg, open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("registry %d -> %d (skipped-exist %d)" % (len(existing), reg["total_components"], len(skipped_exist)))

    # JSONL
    with open(JSONL, "a", encoding="utf-8", newline="\n") as f:
        for name in added:
            cat, func, cx = META[name]
            fp = os.path.join(BASE, cat, name + ".st")
            src = open(fp, encoding="utf-8").read()
            row = {
                "instruction": build_instruction(name, cat, func, cx),
                "architecture_thought": build_thought(name, cat, func, cx, src),
                "output": src,
                "meta": {"name": name, "category": cat, "version": "1.0.0", "round": ROUND},
            }
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    n_jsonl = sum(1 for _ in open(JSONL, encoding="utf-8"))
    print("jsonl -> %d lines" % n_jsonl)

    # 三数核对
    st = 0
    for cat in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"):
        p = os.path.join(BASE, cat)
        if os.path.isdir(p):
            st += len([x for x in os.listdir(p) if x.endswith(".st")])
    print("registry=%d  jsonl=%d  st_files=%d  diff(reg-st)=%d diff(jsonl-reg)=%d"
          % (reg["total_components"], n_jsonl, st, reg["total_components"] - st, n_jsonl - reg["total_components"]))
    print("added=%d" % len(added))
    return 0


if __name__ == "__main__":
    sys.exit(main())
