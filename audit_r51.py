#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""audit_r51.py —— R51 轮机检（20 新件 + 4 返修），口径复用 compile_gate_v0.gate_file"""
import io, os, sys, json
from compile_gate_v0 import gate_file

ROOT = r"C:\Library"
OUT = os.path.join(ROOT, "_Staging_Raw", "2026-11-20", "_audit_r51.json")

MANIFEST = [
    ("FB_DL_AhuFanArrayTrim","DL_Process"),("FB_DL_ElectrodeGapMark","DL_Process"),
    ("FB_DL_FormationChannelQueue","DL_Process"),("FB_DL_SlurryDensityTrim","DL_Process"),
    ("FB_DL_FilmSpliceWeekPlan","DL_Process"),("FB_DL_CasePackerPatternVerify","DL_Process"),
    ("FB_DL_ChillerYearWinStart","DL_Process"),("FB_DL_ReactorYearWinClean","DL_Process"),
    ("FB_DL_LoopAuditTrailWindow","DL_Process"),("FB_DL_LamEvaGelContent","DL_Process"),
    ("FB_DL_PalletLabelVerify","DL_Process"),("FB_DL_ElectrolyteFillVacuum","DL_Process"),
    ("FB_DL_DateCoderPosition","DL_Process"),("FB_DL_SteamTrapSurvey","DL_Device"),
    ("FC_DL_PolarDecomp2D","DL_MathData"),("FB_DL_TrayLoadVacuum","DL_Process"),
    ("FB_DL_CupFillDenest","DL_Process"),("FB_DL_HumidifierAdiabat","DL_Process"),
    ("FB_DL_NgBinDosing","DL_Process"),("FC_DL_MadZScore","DL_MathData"),
    ("FB_DL_RulEstimator","DL_Algo"),("FB_DL_ExtremumSeekCtrl","DL_Algo"),
    ("FB_DL_MoveResumeSeg","DL_Motion"),("FB_DL_LoopCoupleDetect","DL_Algo"),
]
a, b = 1, len(MANIFEST)
if len(sys.argv) >= 3:
    a, b = int(sys.argv[1]), int(sys.argv[2])
res = []
for name, cat in MANIFEST[a-1:b]:
    p = os.path.join(ROOT, cat, name + ".st")
    src, issues = gate_file(p)
    ok = not issues
    res.append({"name": name, "pass": ok, "issues": issues})
    print(("PASS" if ok else "FAIL"), name, json.dumps(issues, ensure_ascii=False))
io.open(OUT, "w", encoding="utf-8", newline="").write(json.dumps(res, ensure_ascii=False, indent=1))
fail = sum(1 for x in res if not x["pass"])
print("TOTAL %d PASS %d FAIL %d" % (len(res), len(res)-fail, fail))
