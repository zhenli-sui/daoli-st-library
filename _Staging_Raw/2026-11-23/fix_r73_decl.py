# -*- coding: utf-8 -*-
"""R73 全回执第二步：补局部声明（首脚本误把调用文本当已声明）。"""
import re, io
FILES = [r"DL_Algo\FC_DL_HumidityRatioCalc.st", r"DL_Algo\FC_DL_MixAirStateCalc.st",
         r"DL_Algo\FC_DL_RhFromDewPoint.st", r"DL_MathData\FC_DL_DewPointToPpmV.st",
         r"DL_Process\FB_DL_NightPurgeCtrl.st"]
for p in FILES:
    s = io.open(p, encoding="utf-8").read()
    if re.search(r"^\s*_nPwsErr\s*:", s, re.M):
        print("SKIP already declared", p); continue
    m = re.search(r"^([ \t]*)_bPwsValid\s*:.*\n", s, re.M)
    if not m:
        print("SKIP no anchor", p); continue
    i = m.group(1)
    add = ("%s_bPwsClamped : BOOL;    // 属主件钳位回执（本件不消费，仅契约全回执） / Owner clamp receipt (unused, full-receipt contract)\n"
           "%s_nPwsErr     : UDINT;   // 属主件错误码回执 / Owner error-code receipt\n"
           "%s_bPwsError   : BOOL;    // 属主件故障级回执 / Owner fault-flag receipt\n") % (i, i, i)
    s = s[:m.end()] + add + s[m.end():]
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)
    print("OK", p)
