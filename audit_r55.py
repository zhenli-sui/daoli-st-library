#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""audit_r55.py —— R55 轮机检（20 新件），口径复用 compile_gate_v0.gate_file"""
import io, os, sys, json
from compile_gate_v0 import gate_file

ROOT = r"C:\Library"
OUT = os.path.join(ROOT, "_Staging_Raw", "2026-11-20", "_audit_r55.json")

MANIFEST = [
    ("FC_DL_NewtonRaphson","DL_MathData"),
    ("FB_DL_FopdtStepIdent","DL_Algo"),
    ("FB_DL_EnergyMonthPreset","DL_Process"),
    ("FB_DL_ChamberTempUnitBank","DL_Process"),
    ("FB_DL_RollPressBitWord","DL_Process"),
    ("FB_DL_FormatMonthAudit","DL_Process"),
    ("FB_DL_TrayMonthRotate","DL_Process"),
    ("FB_DL_ShiftMonthReport","DL_Process"),
    ("FB_DL_FormationWeekPlan","DL_Process"),
    ("FB_DL_StringIrrNormalize","DL_Process"),
    ("FB_DL_BatchWeekReport","DL_Process"),
    ("FB_DL_StringElImageMap","DL_Process"),
    ("FB_DL_AmcMonitorStat","DL_Process"),
    ("FB_DL_BeltHeatRecovery","DL_Process"),
    ("FB_DL_ElectrolyteDosingTrend","DL_Process"),
    ("FB_DL_EvaDosingTare","DL_Process"),
    ("FB_DL_ChemDosingGrav","DL_Process"),
    ("FB_DL_CoinCellAssembler","DL_Process"),
    ("FB_DL_PackMlUnitMode","DL_Process"),
    ("FB_DL_BacdHvacPoll","DL_Process"),
]
a, b = 1, len(MANIFEST)
if len(sys.argv) >= 3:
    a, b = int(sys.argv[1]), int(sys.argv[2])
res = []
for name, cat in MANIFEST[a-1:b]:
    p = os.path.join(ROOT, cat, name + ".st")
    if not os.path.exists(p):
        res.append({"name": name, "pass": False, "issues": ["FILE_MISSING"]})
        print("FAIL", name, "FILE_MISSING")
        continue
    src, issues = gate_file(p)
    ok = not issues
    res.append({"name": name, "pass": ok, "issues": issues, "lines": len(src.strip().splitlines())})
    print(("PASS" if ok else "FAIL"), name, len(src.strip().splitlines()), json.dumps(issues, ensure_ascii=False))
io.open(OUT, "w", encoding="utf-8", newline="").write(json.dumps(res, ensure_ascii=False, indent=1))
fail = sum(1 for x in res if not x["pass"])
print("TOTAL %d PASS %d FAIL %d" % (len(res), len(res)-fail, fail))
