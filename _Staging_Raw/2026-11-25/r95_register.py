# -*- coding: utf-8 -*-
"""R95 入库脚本：registry 追加 + counts 校准 + JSONL 追加。
只读业务代码，不改 .st。"""
import io, json, os, re, shutil, datetime, sys

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-25")
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JSN = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")

targets = json.load(io.open(os.path.join(STG, "r95_targets.json"), encoding="utf-8"))
reg = json.load(io.open(REG, encoding="utf-8"))
have = {c["name"] for c in reg["components"]}

FAMILY = {
    "DLF-A-RTCP": ("五轴 CNC 机床的 RTCP 刀尖点跟随与刀具补偿链", "五轴联动加工中心", "刀尖点跟随误差、摆轴行程与进给速度匹配"),
    "DLF-B-ROOTSTEP": ("迭代求解器的单步算子与终止判据", "过程控制中的在线方程求解", "区间收缩、括号保持与收敛终止"),
    "DLF-C-SEVENSEG": ("七段数码管字形译码与多路动态扫描", "面板仪表与操作台显示", "段码映射、多路分时与残影抑制"),
    "DLF-D-WATERANA": ("在线水质分析仪的测量换算与标定诊断", "水处理与制药纯水在线监测", "电极斜率/不对称电位、温补与标定周期"),
}

now = datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()
added, skipped = [], []

def build_instruction(t):
    fam = FAMILY.get(t["source_tag"], ("工业控制", "产线", "边界条件"))
    scen, site, focus = fam
    return (
        "%s现场需要新增一个标准件：%s。\n"
        "工况与边界：%s；要求纯 IEC 61131-3（CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop 均可导入），"
        "不得引用任何厂商库、不得出现 %%I/%%Q 物理地址、不得使用全局变量表。\n"
        "输入可能来自传感器或上位机，必须假定存在非有限值（NaN/Inf）、超量程、零分母与非法组态，"
        "出口不得把非有限值直接透出给下游执行机构；任何故障要落到信息码/故障码出口并可复位。\n"
        "请给出完整可编译的 ST 实现（含中英双语变量注释），并说明关键防错设计。" % (site, t["function"], focus)
    )

def build_thought(t, src):
    has_case = "CASE " in src
    has_enum = bool(re.search(r"TYPE\s+E_DL_", src))
    has_nan = ("<> " in src and ")" in src) or "NaN" in src or ("- " in src)
    inf_guard = bool(re.search(r"\(\s*\w+\s*-\s*\w+\s*\)\s*<>\s*0", src))
    has_limit = "LIMIT(" in src
    has_rt = ("R_TRIG" in src) or ("TON" in src)
    methods = len(re.findall(r"(?m)^\s*METHOD\s+\w+", src))
    parts = []
    parts.append("算法层：%s。输入先做量纲与量程归一，再进入核心算式，所有除法前置于分母判据，避免除零。" % t["function"])
    if has_enum and has_case:
        parts.append("状态机层：用 E_DL_* 枚举 + CASE 表达离散相，ELSE 分支回安全态并置故障位，杜绝非法相静默穿透。")
    else:
        parts.append("状态机层：本件为单拍纯函数，无跨周期状态驻留，因此以「前置域闸 + 单一出口裁决」替代状态机。")
    g = []
    if inf_guard:
        g.append("非有限值用 `(x<>x) OR ((x-x)<>0.0)` 双判（NaN 与 ±Inf 一并拦截），并在同一拍把实值出口改写到安全值")
    else:
        g.append("非有限值在入口统一拦截，故障时出口改写安全值而非透传")
    if has_limit:
        g.append("量程用 LIMIT 夹定后才参与运算与出口")
    g.append("所有保持量给安全侧初值，避免上电 0.0 被当作有效指令")
    if has_rt:
        g.append("定时器/沿实例每周期无条件调用，IN 与本相许可做与运算，防跨相累加")
    parts.append("防错层：" + "；".join(g) + "。")
    if methods:
        parts.append("解耦层：把可复用的中间计算拆为 %d 个 METHOD，主块只负责相位调度与出口裁决，便于单测与复用。" % methods)
    else:
        parts.append("解耦层：以常量集中声明（VAR CONSTANT）替代散落魔数，工艺参数变更只改一处。")
    return "".join(parts)

for t in targets:
    name, cat = t["name"], t["category"]
    path = os.path.join(LIB, cat, name + ".st")
    if not os.path.exists(path):
        skipped.append((name, "file missing")); continue
    if name in have:
        skipped.append((name, "already registered")); continue
    src = io.open(path, encoding="utf-8").read()
    reg["components"].append({
        "name": name,
        "category": cat,
        "type": "FB" if name.startswith("FB_DL_") else ("FC" if name.startswith("FC_DL_") else "OTHER"),
        "file_path": path,
        "function_tags": [t["source_tag"], cat.lower(), "r95", "round-95"] + re.findall(r"[a-z]+", t["function"].split("；")[0].lower())[:3],
        "complexity": int(t.get("complexity", 2)),
        "registered_at": now,
        "origin": {"mode": "internal", "source": "道莅原创（自研线/R95 规划族 %s）" % t["source_tag"],
                   "license": "MIT", "ref_tag": t["source_tag"]},
    })
    added.append({"t": t, "src": src})

# counts 校准
cnt = {}
for c in reg["components"]:
    cnt[c["category"]] = cnt.get(c["category"], 0) + 1
reg["counts"] = cnt
reg["total_components"] = len(reg["components"])
reg["last_updated"] = now

shutil.copy2(REG, REG + ".bak_r95")
io.open(REG, "w", encoding="utf-8").write(json.dumps(reg, ensure_ascii=False, indent=1))

# JSONL 追加
with io.open(JSN, "a", encoding="utf-8", newline="\n") as f:
    for a in added:
        t = a["t"]
        rec = {"instruction": build_instruction(t), "architecture_thought": build_thought(t, a["src"]), "output": a["src"]}
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

print("registered:", len(added), "skipped:", skipped)
print("counts:", reg["counts"], "total:", reg["total_components"])
print("jsonl lines:", sum(1 for _ in io.open(JSN, encoding="utf-8")))
