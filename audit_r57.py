#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""audit_r57.py —— R57 增量机检（20 新件 + 4 返修件），口径复用 compile_gate_v0.gate_file"""
import io, os, sys, json
from compile_gate_v0 import gate_file

ROOT = r"C:\Library"
OUT = os.path.join(ROOT, "_Staging_Raw", "2026-11-21", "_audit_r57.json")

MANIFEST = [
    ("FB_DL_TpRetrigger","DL_Base"),
    ("FB_DL_EdgeMasterSlaveSync","DL_Base"),
    ("FB_DL_EncoderQuadCount","DL_Base"),
    ("FB_DL_SignalStagnationWatch","DL_Base"),
    ("FB_DL_SensorDropoutHold","DL_Base"),
    ("FC_DL_AsinSafe","DL_MathData"),
    ("FC_DL_AcosSafe","DL_MathData"),
    ("FC_DL_LogSafe","DL_MathData"),
    ("FC_DL_ExpSat","DL_MathData"),
    ("FC_DL_PowIntSat","DL_MathData"),
    ("FC_DL_SignumCalc","DL_MathData"),
    ("FC_DL_RmsCalc","DL_MathData"),
    ("FC_DL_ParityCalc","DL_MathData"),
    ("FC_DL_PeakToPeakCalc","DL_MathData"),
    ("FC_DL_InterpStepNearest","DL_MathData"),
    ("FB_DL_EsdGroundMonitor","DL_Device"),
    ("FB_DL_IonizerAirflowInterlock","DL_Device"),
    ("FB_DL_ProofTestSeq","DL_Device"),
    ("FB_DL_PassboxInterlockSeq","DL_Process"),
    ("FB_DL_NightPurgeSeq","DL_Process"),
    ("FB_DL_LossInWeightFeeder","DL_Algo"),
    ("FB_DL_TwoDofPid","DL_Algo"),
    ("FB_DL_AxisAccelFeedforward","DL_Motion"),
    ("FB_DL_HydraulicAccumPreChg","DL_Device"),
]
a, b = 1, len(MANIFEST)
if len(sys.argv) >= 3:
    a, b = int(sys.argv[1]), int(sys.argv[2])
res = []
for name, cat in MANIFEST[a-1:b]:
    p = os.path.join(ROOT, cat, name + ".st")
    if not os.path.exists(p):
        res.append({"name": name, "pass": False, "issues": ["FILE_MISSING"]})
        print("FAIL", name, "FILE_MISSING"); continue
    src, issues = gate_file(p)
    ok = not issues
    res.append({"name": name, "pass": ok, "issues": issues, "lines": len(src.strip().splitlines())})
    print(("PASS" if ok else "FAIL"), name, len(src.strip().splitlines()), json.dumps(issues, ensure_ascii=False))
io.open(OUT, "w", encoding="utf-8", newline="").write(json.dumps(res, ensure_ascii=False, indent=1))
fail = sum(1 for x in res if not x["pass"])
print("TOTAL %d PASS %d FAIL %d" % (len(res), len(res)-fail, fail))
