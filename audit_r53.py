#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""audit_r52.py —— R52 轮机检（20 新件 + 2 返修），口径复用 compile_gate_v0.gate_file"""
import io, os, sys, json
from compile_gate_v0 import gate_file

ROOT = r"C:\Library"
OUT = os.path.join(ROOT, "_Staging_Raw", "2026-11-20", "_audit_r53.json")

MANIFEST = [
    ("FB_DL_ValveCycleLifeCounter","DL_Device"),
    ("FB_DL_BearingVibTrend","DL_Algo"),
    ("FC_DL_WetBulbCalc","DL_MathData"),
    ("FB_DL_SignalStuckWatch","DL_Base"),
    ("FB_DL_ConveyorSlipWatch","DL_Device"),
    ("FB_DL_CaseShiftTally","DL_Process"),
    ("FC_DL_HaversineDistance","DL_MathData"),
    ("FB_DL_PumpSurgeGuard","DL_Algo"),
    ("FB_DL_GreaseLubeTimer","DL_Device"),
    ("FB_DL_PulseTrainDecoder","DL_Base"),
    ("FC_DL_PeriodJitterCalc","DL_MathData"),
    ("FB_DL_SensorDriftBaseline","DL_Algo"),
    ("FB_DL_FilterWeekWindow","DL_Process"),
    ("FB_DL_LabelWeekCode","DL_Process"),
    ("FB_DL_AxisBacklashStepComp","DL_Motion"),
    ("FB_DL_BathTempHoldCtrl","DL_Process"),
    ("FB_DL_AxisHomeRepeatVerify","DL_Motion"),
    ("FB_DL_PidParamDriftAudit","DL_Algo"),
    ("FB_DL_HeatTraceCircuitMon","DL_Device"),
    ("FB_DL_BrakeResistorThermal","DL_Device"),
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
