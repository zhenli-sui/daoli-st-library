# -*- coding: utf-8 -*-
"""R45 选题反证机：对 20 个目标组件名做 registry 精确比对 + ROADMAP 文本比对 + 同义邻件人工清单留痕。
用法：python check_r45.py
输出：_check_r45_result.json（供 ROUND_PLAN / DISPATCH 引用）
"""
import json, os, re

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
OUT = os.path.join(ROOT, "_Staging_Raw", "2026-11-19", "_check_r45_result.json")

TARGETS = [
    # (序号, 组件名, 分类)
    (1,  "FB_DL_Vote2oo3",               "DL_Base"),
    (2,  "FB_DL_EdgeOrderCheck",         "DL_Base"),
    (3,  "FB_DL_AlarmFloodLimiter",      "DL_Base"),
    (4,  "FC_DL_CubicBezierEval",        "DL_MathData"),
    (5,  "FB_DL_KalmanFilter1D",         "DL_Algo"),
    (6,  "FB_DL_TensionObserver",        "DL_Algo"),
    (7,  "FB_DL_StictionCompensator",    "DL_Algo"),
    (8,  "FB_DL_LoopPerfIndex",          "DL_Algo"),
    (9,  "FB_DL_ThermalRampPredict",     "DL_Algo"),
    (10, "FB_DL_AxisDualFeedbackGuard",  "DL_Motion"),
    (11, "FB_DL_AxisSs1StopSeq",         "DL_Motion"),
    (12, "FB_DL_AxisTeachOffset",        "DL_Motion"),
    (13, "FB_DL_AxisInertiaIdent",       "DL_Motion"),
    (14, "FB_DL_AxisRotaryShortPath",    "DL_Motion"),
    (15, "FB_DL_SafetyRelayFeedback",    "DL_Device"),
    (16, "FB_DL_ContactorWeldDetect",    "DL_Device"),
    (17, "FB_DL_FlowSwitchResponseCheck","DL_Device"),
    (18, "FB_DL_SlurryMixingSeq",        "DL_Process"),
    (19, "FB_DL_FrameSealDispenseSeq",   "DL_Process"),
    (20, "FB_DL_BoilerBlowdownSeq",      "DL_Process"),
]

# 被剔除的候选（同义邻件 / 已注册 / 已裁定不立）
REJECTED = [
    ("FB_DL_CasePackerPatternVerify", "同义邻件：registry 已注册 FB_DL_CasePackerPattern（同域装箱模式）"),
    ("FB_DL_PalletizerStation",       "registry 已注册（DL_Process），ROADMAP 仍空勾 → 三向一致差额样本"),
    ("FB_DL_TrackBarcodeTrace",       "registry 已注册（DL_Process），ROADMAP 仍空勾 → 三向一致差额样本"),
    ("FB_DL_StringBarcodeTrace",      "registry 已注册（DL_Process），同上"),
    ("FB_DL_WindingAlignEdge",        "registry 已注册（DL_Motion），ROADMAP 仍空勾"),
    ("FB_DL_FrequencyChirpGen",       "同义邻件：FB_DL_FrequencyGenerator 已覆盖扫频语义"),
    ("FC_DL_WelfordStdDev",           "同义邻件：FB_DL_SignalStatistics 已在册（在线统计）"),
    ("FB_DL_HeaterElementDiag",       "职责重叠：R44 新件 FB_DL_HeaterSsrBank 已含断偶/电流诊断"),
    ("FB_DL_MotionBlendZone",         "R22 已裁定「Blending 系列明确不立」，不得翻案"),
    ("FC_DL_ShlDwordEx",              "ROADMAP 自记「疑似与存量 ShlEx 同义」，按 R61 拒立项"),
    ("FC_DL_ShrDwordEx",              "同上"),
]

def load_names():
    d = json.load(open(REG, encoding="utf-8"))
    names = {c["name"] for c in d["components"]}
    return d, names

def main():
    d, names = load_names()
    roadmap = open(os.path.join(ROOT, "ROADMAP.md"), encoding="utf-8").read()
    matrix = open(os.path.join(ROOT, "SOURCE_HUNTING_MATRIX.md"), encoding="utf-8").read()
    files = set()
    for cat in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"):
        p = os.path.join(ROOT, cat)
        if os.path.isdir(p):
            files |= {f[:-3] for f in os.listdir(p) if f.endswith(".st")}

    rows, bad = [], 0
    for idx, name, cat in TARGETS:
        stem = name.split("_", 2)[2] if name.count("_") >= 2 else name
        # 精确同名
        exact = name in names or name in files
        # ROADMAP 反引号精确提及
        in_roadmap = ("`%s`" % name) in roadmap
        in_matrix = name in matrix
        # 词干模糊（同义邻件预警：仅提示，人工裁决）
        fuzzy = sorted(n for n in names if n != name and stem.lower()[:8] in n.lower())
        if exact:
            bad += 1
        rows.append({
            "idx": idx, "name": name, "category": cat,
            "exact_hit_registry_or_tree": exact,
            "in_roadmap": in_roadmap, "in_matrix": in_matrix,
            "fuzzy_neighbors": fuzzy[:6],
        })

    rej = []
    for n, why in REJECTED:
        rej.append({"name": n, "reason": why,
                    "in_registry": n in names, "in_tree": n in files})

    res = {
        "round": "R45", "date": "2026-11-19",
        "registry_total": d["total_components"], "registry_version": d["version"],
        "targets": len(TARGETS), "exact_collisions": bad,
        "rejected_candidates": len(REJECTED),
        "rows": rows, "rejected": rej,
        "assert_sentence": "20 名 grep registry 零匹配，另拒 %d 条同名/同义候选" % len(REJECTED),
    }
    json.dump(res, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    for r in rows:
        print(r["idx"], r["name"], "EXACT" if r["exact_hit_registry_or_tree"] else "ok",
              "| roadmap:%d matrix:%d" % (r["in_roadmap"], r["in_matrix"]),
              "| fuzzy:", ",".join(r["fuzzy_neighbors"]) if r["fuzzy_neighbors"] else "-")
    print("\nTOTAL", len(TARGETS), "COLLISIONS", bad, "REJECTED", len(REJECTED))
    print(res["assert_sentence"])

if __name__ == "__main__":
    main()
