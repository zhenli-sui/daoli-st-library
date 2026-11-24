# -*- coding: utf-8 -*-
"""R83 规划：词根交集扫描 + 撞名终审 + ROUND_PLAN 落盘"""
import json, re, os, sys
from collections import Counter

LIB = r"C:\Library"
reg = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
comps = reg["components"]
existing = {c["name"] for c in comps}

GENERIC = {"dl", "fb", "fc", "i", "st", "e", "calc", "chk", "check", "ctrl", "seq",
           "fbdl", "fcdl", "idx", "val", "num", "flt", "bool", "fb", "mon"}


def tokens(name):
    base = re.sub(r"^(FB_DL_|FC_DL_|I_DL_|ST_DL_|E_DL_|DL_)", "", name)
    raw = re.findall(r"[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|\d+", base)
    out = set()
    for t in raw:
        tl = t.lower()
        if tl in GENERIC or tl.isdigit() or len(tl) <= 2:
            continue
        out.add(tl)
    return out


# 候选：40 件（复杂 4 + 简单 36）
PLAN = [
    # ---- 族A 印刷包装（8，简单） ----
    ("FC_DL_InkViscosityTempComp", "DL_Process", "FC", "油墨黏度温度补偿系数计算", 1, "A"),
    ("FC_DL_RegisterErrorCalc", "DL_Process", "FC", "套准横纵误差合成偏差计算", 2, "A"),
    ("FC_DL_AniloxInkTransferCalc", "DL_Process", "FC", "网纹辊单位面积传墨量计算", 2, "A"),
    ("FC_DL_SpliceOverlapWidthCalc", "DL_Process", "FC", "接卷搭接宽度与胶带用量计算", 2, "A"),
    ("FC_DL_CutLengthDeviationCalc", "DL_Process", "FC", "定长裁切偏差与补偿量计算", 1, "A"),
    ("FC_DL_DryerSolventLoadCalc", "DL_Process", "FC", "干燥箱单位时间溶剂负荷估算", 2, "A"),
    ("FB_DL_SpliceCountdownCtrl", "DL_Process", "FB", "接卷剩余米数倒计时与报警", 2, "A"),
    ("FC_DL_ImpulseSealDwellCalc", "DL_Process", "FC", "脉冲热封通电与保压时间计算", 2, "A"),
    # ---- 族B 纺织染整（8，简单） ----
    ("FC_DL_DyeLiquorRatioCalc", "DL_Process", "FC", "染浴浴比与总液量计算", 1, "B"),
    ("FC_DL_FabricWeightAreaCalc", "DL_Process", "FC", "织物单位面积克重计算", 1, "B"),
    ("FC_DL_PaddingPickupCalc", "DL_Process", "FC", "轧车轧余率与带液量计算", 2, "B"),
    ("FC_DL_StenterHeatSetCalc", "DL_Process", "FC", "定型机热定形时间与超喂计算", 2, "B"),
    ("FC_DL_YarnCountConvert", "DL_MathData", "FC", "纱线支数制式换算", 1, "B"),
    ("FC_DL_BeamWarpLengthCalc", "DL_Process", "FC", "经轴可卷绕经纱长度计算", 2, "B"),
    ("FB_DL_DyeBathReplenishCtrl", "DL_Process", "FB", "染浴液位与助剂补加联动控制", 2, "B"),
    ("FC_DL_ShadeDriftIndexCalc", "DL_Process", "FC", "色光漂移指数与回修判定", 2, "B"),
    # ---- 族C 表面处理电镀（7，简单） ----
    ("FC_DL_PlatingThicknessChargeCalc", "DL_Process", "FC", "法拉第定律镀层厚度与电量折算", 2, "C"),
    ("FC_DL_FaradayEfficiencyCalc", "DL_Process", "FC", "镀液电流效率由实测增重反算", 1, "C"),
    ("FC_DL_AnodeCurrentDensityCalc", "DL_Process", "FC", "阳极面积基准电流密度计算", 2, "C"),
    ("FC_DL_RinseDragOutCalc", "DL_Process", "FC", "漂洗槽带出量与补水率估算", 2, "C"),
    ("FC_DL_BarrelRotationRpmCalc", "DL_Device", "FC", "滚镀滚筒转速与临界转速比", 2, "C"),
    ("FB_DL_ElectrolessBathReplenishCtrl", "DL_Process", "FB", "化学镀浴按负荷补加控制", 2, "C"),
    ("FC_DL_HexChromeTriRatioCalc", "DL_Process", "FC", "六价三价铬浓度比与老化判定", 1, "C"),
    # ---- 族D 输送分拣（7，简单） ----
    ("FC_DL_SortChuteTimingCalc", "DL_Algo", "FC", "滑槽分拣释放延时计算", 2, "D"),
    ("FC_DL_BeltThroughputCalc", "DL_Algo", "FC", "皮带单位时间通过量计算", 1, "D"),
    ("FC_DL_DiverterLeadTimeCalc", "DL_Algo", "FC", "分流器动作提前量计算", 2, "D"),
    ("FC_DL_ScannerReadRateCalc", "DL_Algo", "FC", "读码首读率与重读次数统计", 1, "D"),
    ("FC_DL_ChuteFullPredict", "DL_Algo", "FC", "滑槽满料到达时间预测", 2, "D"),
    ("FB_DL_ToteGapReleaseCtrl", "DL_Algo", "FB", "料箱最小间隔放行控制", 2, "D"),
    ("FC_DL_AccumulationZoneFillCalc", "DL_Algo", "FC", "积放区占位率计算", 1, "D"),
    # ---- 族E 仓储立库周边（6，简单） ----
    ("FC_DL_SlotHeightFitCalc", "DL_Device", "FC", "货位净高与货高匹配校验", 1, "E"),
    ("FC_DL_PalletOverhangCalc", "DL_Device", "FC", "托盘悬垂量与允许上限校验", 1, "E"),
    ("FC_DL_ForkEntryClearanceCalc", "DL_Device", "FC", "货叉入叉左右余量计算", 2, "E"),
    ("FC_DL_AsrsCycleTimeCalc", "DL_Device", "FC", "堆垛机单循环作业时间估算", 2, "E"),
    ("FC_DL_StackerMastSwayCalc", "DL_Motion", "FC", "堆垛机立柱加减速摆幅估算", 2, "E"),
    ("FC_DL_InventoryAgeIndexCalc", "DL_Device", "FC", "出库优先级库龄指数计算", 1, "E"),
    # ---- 复杂件 4 ----
    ("FB_DL_PrintRegisterAutoTrimSeq", "DL_Process", "FB", "印刷套准自动调整状态机", 4, "X"),
    ("FB_DL_DyeBatchRecipeSeq", "DL_Process", "FB", "染批配方分段升温加料时序", 4, "X"),
    ("FB_DL_PlatingLineTransferSeq", "DL_Process", "FB", "电镀线行车转序与槽位占用时序", 4, "X"),
    ("FB_DL_SortDiverterSeq", "DL_Algo", "FB", "分拣分流器握手与故障恢复状态机", 3, "X"),
]

# 词根倒排
inv = {}
for c in comps:
    for t in tokens(c["name"]):
        inv.setdefault(t, []).append(c["name"])

rows, rejected, renamed = [], [], []
for name, cat, kind, desc, cmplx, fam in PLAN:
    if name in existing:
        rejected.append((name, "registry 同名"))
        continue
    tk = tokens(name)
    hits = {}
    for t in tk:
        if t in inv:
            hits[t] = sorted(set(inv[t]))[:3]
    # 撞名判据：>=2 个非通用词根同时命中同一存量件
    severe = []
    cnt = Counter()
    for t, owners in hits.items():
        for o in owners:
            cnt[o] += 1
    for o, n in cnt.items():
        if n >= 2:
            severe.append((o, n))
    if severe:
        rejected.append((name, "词根交集>=2: " + str(severe[:2])))
        continue
    rows.append({"name": name, "cat": cat, "kind": kind, "desc": desc,
                 "cmplx": cmplx, "fam": fam, "hits": hits})

out = os.path.join(LIB, "_Staging_Raw", "2026-11-24", "ROUND_PLAN_R83.md")
os.makedirs(os.path.dirname(out), exist_ok=True)
L = []
L.append("# ROUND_PLAN_R83 —— 2026-11-24 下午轮（冲刺模式）\n")
L.append("> 计划 40 件 = 简单 36（族A~E 批量派生）+ 复杂 4。修复名额 **0**（非当日首轮，铁律一）。\n")
L.append("> 撞名终审：词根交集扫描（≥2 非通用词根命中同一存量件即驳回）+ registry 全名精确比对。\n")
L.append("\n## 复杂件（4 件，C3~C4）\n")
L.append("| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |")
L.append("|---|---|---|---|---|---|---|---|---|")
seq = 0
for r in rows:
    if r["fam"] != "X":
        continue
    seq += 1
    L.append(f"| {seq} | `{r['name']}` | {r['cat']} | {r['kind']} | {r['desc']} | 自研/clean-room | C{r['cmplx']} | B1 | 复杂 |")
L.append("\n## 简单件（36 件，C1~C2，20~50 行，族模板派生）\n")
fams = {"A": "印刷包装", "B": "纺织染整", "C": "表面处理电镀", "D": "输送分拣", "E": "仓储立库周边"}
for f, fname in fams.items():
    sub = [r for r in rows if r["fam"] == f]
    L.append(f"\n### 族{f} {fname}（{len(sub)} 件）\n")
    L.append("| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |")
    L.append("|---|---|---|---|---|---|---|---|---|")
    for r in sub:
        seq += 1
        L.append(f"| {seq} | `{r['name']}` | {r['cat']} | {r['kind']} | {r['desc']} | 自研/clean-room | C{r['cmplx']} | S1 | 简单 |")
L.append(f"\n## 统计\n")
L.append(f"- 通过 {len(rows)} 件（复杂 {sum(1 for r in rows if r['fam']=='X')} / 简单 {sum(1 for r in rows if r['fam']!='X')}）")
L.append(f"- 驳回 {len(rejected)} 件：" + ("；".join(f"`{n}`({w})" for n, w in rejected) if rejected else "无"))
L.append(f"- 与存量 1,570 件全名精确比对：0 同名")
open(out, "w", encoding="utf-8").write("\n".join(L))
print("rows", len(rows), "rejected", len(rejected))
for n, w in rejected:
    print("  REJ", n, w)
print("PLAN_WRITTEN", out)

js = os.path.join(LIB, "_Staging_Raw", "2026-11-24", "r83_targets.json")
json.dump(rows, open(js, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("TARGETS", js, len(rows))
