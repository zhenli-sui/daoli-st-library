# -*- coding: utf-8 -*-
"""R80 审校拒收处置：移隔离区 + 撤销登记 + 撤销语料行"""
import json, os, shutil, datetime

BASE = r"C:\Library"
REG = os.path.join(BASE, "INDEX_REGISTRY.json")
JSONL = os.path.join(BASE, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
QDIR = os.path.join(BASE, "_quarantine", "R80")
os.makedirs(QDIR, exist_ok=True)

REJ = [
    ("FC_DL_HydroPipePressDrop", "DL_Device"),
    ("FC_DL_StatsIqrCalc", "DL_MathData"),
    ("FC_DL_GeoMeanX_placeholder", None),  # 占位，实际下面用真实名
]
REJ = [("FC_DL_HydroPipePressDrop", "DL_Device"),
       ("FC_DL_StatsIqrCalc", "DL_MathData"),
       ("FC_DL_StatsGeoMeanCalc", "DL_MathData")]
names = {n for n, _ in REJ}

# 1) 文件移隔离区
for n, cat in REJ:
    src = os.path.join(BASE, cat, n + ".st")
    if os.path.exists(src):
        shutil.move(src, os.path.join(QDIR, n + ".st"))
        print("moved", n)

# 2) 撤销 registry
reg = json.load(open(REG, encoding="utf-8"))
before = len(reg["components"])
reg["components"] = [c for c in reg["components"] if c["name"] not in names]
reg["counts"] = {}
for c in reg["components"]:
    reg["counts"][c["category"]] = reg["counts"].get(c["category"], 0) + 1
reg["total_components"] = len(reg["components"])
reg["last_updated"] = datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()
assert sum(reg["counts"].values()) == reg["total_components"]
json.dump(reg, open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("registry %d -> %d" % (before, reg["total_components"]))

# 3) 撤销 JSONL
rows = []
removed = 0
for line in open(JSONL, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    try:
        o = json.loads(line)
        nm = o.get("meta", {}).get("name", "")
    except Exception:
        nm = ""
    if nm in names:
        removed += 1
        continue
    rows.append(line)
open(JSONL, "w", encoding="utf-8", newline="\n").write("\n".join(rows) + "\n")
print("jsonl removed %d -> %d lines" % (removed, len(rows)))

# 4) 三数核对
st = 0
for cat in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"):
    p = os.path.join(BASE, cat)
    if os.path.isdir(p):
        st += len([x for x in os.listdir(p) if x.endswith(".st")])
print("registry=%d jsonl=%d st=%d diff(reg-st)=%d diff(jsonl-reg)=%d"
      % (reg["total_components"], len(rows), st,
         reg["total_components"] - st, len(rows) - reg["total_components"]))
print("counts", reg["counts"])
