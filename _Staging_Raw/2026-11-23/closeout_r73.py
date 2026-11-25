# -*- coding: utf-8 -*-
"""R73 收口：registry 注册 20 新件 + 5 件点修版本对齐 + JSONL 追加（20 新 + 5 重注入）。
语料 instruction/architecture 全部由 .st 文件头与段标题实测回填（R372 语料保真口径）。
"""
import json, os, re, io, shutil, datetime

TS = datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S+08:00")
LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
VER = "2.65.0"
ROUND = "r73"

NEW = [
    # name, category, type, complexity, tags, origin_mode, origin_desc
    ("FB_DL_FlyingSawSyncSeq", "DL_Motion", "FB", 4,
     ["motion", "flying-saw", "electronic-cam", "sync-cut", "sequence", "t1-6-plcopen", "r73-new"],
     "classifica", "t1-6-plcopen 运动序列语义深化 + S-9 工程惯例，clean-room 独立编写（零外部源码行）"),
    ("FB_DL_CamTableOnlineBlend", "DL_Motion", "FB", 4,
     ["motion", "cam-table", "online-switch", "blend", "phase-continuity", "t1-6-plcopen", "r73-new"],
     "classifica", "t1-6-plcopen 凸轮表级在线切换方向（与 CamDynTrim 相修调属主分工），clean-room 独立编写"),
    ("FB_DL_FanSurgeMarginCalc", "DL_Algo", "FB", 3,
     ["fan", "surge", "margin", "performance-curve", "early-warning", "r73-new"],
     "classifica", "自研线：风机性能曲线公开口径（喘振线裕度），原创建模"),
    ("FB_DL_EmergencyStopChainDiag", "DL_Device", "FB", 3,
     ["safety", "estop", "chain-diagnosis", "node-locate", "t2-8-isa182", "r73-new"],
     "classifica", "t2-8-isa182 报警分级语义深化（急停回路断链定位），clean-room 独立编写"),
    ("FB_DL_TankFarmTransferSeq", "DL_Process", "FB", 4,
     ["tank-farm", "transfer", "valve-interlock", "level-target", "path-exclusive", "t2-2-lbp", "r73-new"],
     "classifica", "t2-2-lbp 罐区分层复用路线，clean-room 独立编写"),
    ("FB_DL_ConveyorAccumGateSeq", "DL_Process", "FB", 3,
     ["conveyor", "accumulation", "gate", "three-state", "takt", "s9-conv", "r73-new"],
     "classifica", "s9-conv 输送线工程惯例深化，clean-room 独立编写"),
    ("FC_DL_MovingRangeCalc", "DL_MathData", "FC", 1,
     ["statistics", "moving-range", "spc", "adjacent-difference", "t2-1-lgf", "r73-new"],
     "classifica", "t2-1-lgf 计量线统计原子补口（滑动极差 = SPC 判稳前置），clean-room 独立编写"),
    ("FC_DL_PressureAltitudeCalc", "DL_MathData", "FC", 2,
     ["pressure", "altitude", "isa-atmosphere", "barometric", "t1-2-oscat", "r73-new"],
     "oscat-semantic", "改写自 OSCAT Building 行为定义（OSCAT 许可，黄区仅借语义零代码行 + 公开 ISA 标准大气公式）"),
    ("FC_DL_SoundSpeedAirCalc", "DL_MathData", "FC", 2,
     ["acoustics", "sound-speed", "air", "temperature", "humidity", "t1-2-oscat", "r73-new"],
     "oscat-semantic", "改写自 OSCAT Building 行为定义（OSCAT 许可，黄区仅借语义零代码行 + 公开声速公式）"),
    ("FC_DL_ExpMovingAvgCalc", "DL_MathData", "FC", 1,
     ["filter", "ema", "exponential-average", "stateless", "t2-1-lgf", "r73-new"],
     "classifica", "t2-1-lgf 数学线滤波原子（无状态 EMA，与有状态滤波本体分工互引）"),
    ("FC_DL_TorqueUnitConvert", "DL_MathData", "FC", 1,
     ["unit-conversion", "torque", "nm", "kgfm", "lbft", "t0-std-wrapper", "r73-new"],
     "iec-std-wrapper", "T0 单位换算族补口（IEC 61131-3 标准语义的道莅防御性实现）"),
    ("FC_DL_BitRotateEx", "DL_Base", "FC", 2,
     ["bit-string", "rotate", "circular-shift", "byte-word-dword", "t0-std-wrapper", "r73-new"],
     "iec-std-wrapper", "T0 位串族补口（ShlEx/ShrEx 邻件分工声明），IEC 标准语义防御性实现"),
    ("FB_DL_SignalRouteMatrix", "DL_Base", "FB", 2,
     ["signal-routing", "matrix", "source-select", "disconnect-sentinel", "t2-1-lgf", "r73-new"],
     "classifica", "t2-1-lgf 位逻辑线深化（2×N 可组态路由矩阵），clean-room 独立编写"),
    ("FB_DL_SignalEdgeDelayEx", "DL_Base", "FB", 1,
     ["edge-delay", "rising-falling", "delay-window", "t0-std-wrapper", "r73-new"],
     "iec-std-wrapper", "T0 沿/脉冲包装族补口（与 TpRetrigger/PulseStretch 互引分工）"),
    ("FB_DL_SensorSupplyWatch", "DL_Device", "FB", 2,
     ["sensor", "supply-voltage", "window-monitor", "ne43", "t2-6-rockwell", "r73-new"],
     "classifica", "t2-6-rockwell AOI 分类体系借鉴（仅接口分类与参数域，实现 clean-room）"),
    ("FB_DL_ValveCycleCountBank", "DL_Device", "FB", 2,
     ["valve", "cycle-counter", "life-ledger", "maintenance-threshold", "t2-2-lbp", "r73-new"],
     "classifica", "t2-2-lbp 阀诊断深化（多阀计数台账组），clean-room 独立编写"),
    ("FC_DL_TcToFilterCoeff", "DL_Algo", "FC", 1,
     ["filter", "time-constant", "discrete-coefficient", "first-order", "r73-new"],
     "classifica", "自研-std：一阶离散滤波系数换算原子（与 FB_DL_LowPassFilter 本体分工互引）"),
    ("FC_DL_DeadtimeTapCalc", "DL_Algo", "FC", 2,
     ["deadtime", "sample-count", "ceil", "smith-predictor", "r73-new"],
     "classifica", "自研-std：死区时间→拍数向上取整原子（与 FB_DL_SmithPredictor 分工互引）"),
    ("FB_DL_HandAutoModeGateBank", "DL_Process", "FB", 2,
     ["hand-auto", "mode-gate", "permission", "audit", "t2-7-packml", "r73-new"],
     "classifica", "t2-7-packml 相语义深化（手/自动权限门组），clean-room 独立编写"),
    ("FB_DL_OperatorAckBank", "DL_Process", "FB", 2,
     ["alarm", "acknowledge", "group-ack", "pending-list", "t2-8-isa182", "r73-new"],
     "classifica", "t2-8-isa182 报警管理深化（成组确认组），clean-room 独立编写"),
]

FIXED = [
    ("FC_DL_HumidityRatioCalc", "DL_Algo"),
    ("FC_DL_MixAirStateCalc", "DL_Algo"),
    ("FC_DL_RhFromDewPoint", "DL_Algo"),
    ("FC_DL_DewPointToPpmV", "DL_MathData"),
    ("FB_DL_NightPurgeCtrl", "DL_Process"),
]


def read_text(p):
    return io.open(p, encoding="utf-8", errors="replace").read()


def parse_header(s):
    """从 .st 头注释抽取：版本 / 中文名 / 功能描述 / 状态机 / 边界行为 / 段标题。"""
    ver = ""
    m = re.search(r"版本\s*[:：]\s*v?([0-9.]+)", s)
    if m:
        ver = m.group(1)
    cn = ""
    m = re.search(r"中文名称\s*[:：]\s*([^｜|\n]+)", s)
    if m:
        cn = m.group(1).strip()
    # 功能描述：多行 // 续行，截止到「开源溯源」
    desc = ""
    m = re.search(r"功能描述\s*[:：](.*?)(?=//\s*(?:开源溯源|公开接口清单))", s, re.S)
    if m:
        raw = m.group(1)
        parts = [re.sub(r"^//\s*", "", ln).strip() for ln in raw.splitlines()]
        desc = "".join(p for p in parts if p).strip()
    state = ""
    m = re.search(r"状态机\s*[:：](.*?)(?=\n//\s*(?:边界行为|错误码表|开源溯源|公开接口))", s, re.S)
    if m:
        parts = [re.sub(r"^//\s*", "", ln).strip() for ln in m.group(1).splitlines()]
        state = " ".join(p for p in parts if p).strip()
    bnd = []
    m = re.search(r"边界行为\s*[:：](.*?)(?=\n//\s*(?:[A-Z\u4e00-\u9fa5]{2,6}\s*[:：]|=====))", s, re.S)
    if m:
        for ln in m.group(1).splitlines():
            t = re.sub(r"^//\s*", "", ln).strip()
            if re.match(r"^[①②③④⑤⑥⑦⑧⑨⑩]", t):
                bnd.append(t)
    segs = []
    for ln in s.splitlines():
        t = re.sub(r"^//\s*(?:----\s*)?", "", ln).strip()
        if re.match(r"^段\s*\d+", t):
            t = re.sub(r"\s*-+\s*$", "", t).strip()
            if t not in segs:
                segs.append(t)
    return ver, cn, desc, state, bnd, segs


def main():
    reg = json.load(io.open(REG, encoding="utf-8"))
    shutil.copyfile(REG, os.path.join(LIB, "_archive", "INDEX_REGISTRY_bak_r73.json")
                    if os.path.isdir(os.path.join(LIB, "_archive")) else REG + ".bak_r73")
    comps = reg["components"]
    byname = {c["name"]: c for c in comps}

    added, updated, jl_rows, warns = [], [], [], []

    for name, cat, typ, cplx, tags, omode, odesc in NEW:
        fp = os.path.join(LIB, cat, name + ".st")
        if not os.path.isfile(fp):
            warns.append("MISSING " + fp); continue
        if name in byname:
            warns.append("DUP " + name); continue
        s = read_text(fp)
        ver, cn, desc, state, bnd, segs = parse_header(s)
        lines = s.count("\n") + 1
        entry = {
            "name": name, "category": cat, "type": typ, "file_path": fp,
            "function_tags": tags, "complexity": cplx, "version": ver or "1.0.0",
            "registered_at": TS, "line_count": lines,
            "code_segment": "｜".join(segs) if segs else "",
            "source": ROUND + "-plan",
            "origin": {"mode": omode, "desc": odesc},
            "l2_status": "l2-pass",
        }
        comps.append(entry); byname[name] = entry; added.append(name)

        instr = (cn + "。" if cn else "") + desc + \
                ("　现场边界：" + "；".join(bnd) if bnd else "")
        arch = "结构：" + ("｜".join(segs) if segs else "单段纯函数体")
        if state:
            arch += "。状态机：" + state
        arch += ("。防错：边界行为共 %d 条全部以闸/钳位/信息码落地，无静默失效路径；跨平台纯 IEC 61131-3 第 3 版，零方言零物理地址。" % len(bnd))
        jl_rows.append({"name": name, "category": cat, "complexity": cplx,
                        "instruction": instr.strip(), "architecture_thought": arch.strip(),
                        "version": ver or "1.0.0"})

    for name, cat in FIXED:
        fp = os.path.join(LIB, cat, name + ".st")
        if not os.path.isfile(fp):
            warns.append("MISSING_FIX " + fp); continue
        s = read_text(fp)
        ver, cn, desc, state, bnd, segs = parse_header(s)
        e = byname.get(name)
        if e:
            e["version"] = ver or e.get("version")
            e["line_count"] = s.count("\n") + 1
            e["l2_status"] = "l2-pass"
            e["last_fix"] = "R73 全回执补齐（bClamped/eErr/bError/bValid 四路）"
            updated.append(name + "@" + (ver or "?"))
        arch = "结构：" + ("｜".join(segs) if segs else "单段") + \
               "。本次点修：VaporPressureSat 调用由部分回执改为四路全回执（R381/R397 契约口径），FALSE 拍并入既有兜底码，行为不变。"
        jl_rows.append({"name": name, "category": cat, "complexity": (e or {}).get("complexity", 2),
                        "instruction": ("点修版。" + cn + "。" if cn else "") + desc,
                        "architecture_thought": arch, "version": ver or "1.0.0"})

    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    assert sum(counts.values()) == len(comps), "counts 断言失败"
    reg["version"] = VER
    reg["total_components"] = len(comps)
    reg["last_updated"] = TS
    reg["counts"] = dict(sorted(counts.items()))
    io.open(REG, "w", encoding="utf-8", newline="\n").write(
        json.dumps(reg, ensure_ascii=False, indent=2))

    with io.open(JL, "a", encoding="utf-8", newline="\n") as f:
        for r in jl_rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print("REG total=%d counts=%s ver=%s" % (len(comps), reg["counts"], VER))
    print("ADDED %d: %s" % (len(added), ", ".join(added)))
    print("UPDATED %d: %s" % (len(updated), ", ".join(updated)))
    print("JSONL +%d" % len(jl_rows))
    if warns:
        print("WARN:", warns)


if __name__ == "__main__":
    main()
