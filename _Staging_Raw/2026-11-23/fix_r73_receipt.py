# -*- coding: utf-8 -*-
"""R73 全回执补齐：8 处 VaporPressureSat 调用补 bClamped/eErr/bError，达到 6 参全给（E032 消除）。"""
import re, io, sys

LOCALS = ("{i}_bPwsClamped : BOOL;   // 属主件钳位回执（本件不消费，仅契约全回执） / Owner clamp receipt (unused, full-receipt contract)\n"
          "{i}_nPwsErr     : UDINT;  // 属主件错误码回执 / Owner error-code receipt\n"
          "{i}_bPwsError   : BOOL;   // 属主件故障级回执 / Owner fault-flag receipt\n")

TARGETS = [
    (r"DL_Algo\FC_DL_HumidityRatioCalc.st", "bValid => _bPwsValid)", "bValid => _bPwsValid, bClamped => _bPwsClamped, eErr => _nPwsErr, bError => _bPwsError)", 2, False),
    (r"DL_Algo\FC_DL_MixAirStateCalc.st",  "bValid => _bPwsValid)", "bValid => _bPwsValid, bClamped => _bPwsClamped, eErr => _nPwsErr, bError => _bPwsError)", 1, False),
    (r"DL_Algo\FC_DL_RhFromDewPoint.st",   "bValid => _bPwsValid)", "bValid => _bPwsValid, bClamped => _bPwsClamped, eErr => _nPwsErr, bError => _bPwsError)", 2, False),
    (r"DL_MathData\FC_DL_DewPointToPpmV.st","bValid => _bPwsValid)", "bValid => _bPwsValid, eErr => _nPwsErr, bError => _bPwsError)", 1, False),
    (r"DL_Process\FB_DL_NightPurgeCtrl.st", "bValid => _bPwsValid)", "bValid => _bPwsValid, bClamped => _bPwsClamped, eErr => _nPwsErr, bError => _bPwsError)", 2, True),
]

for rel, old, new, expect, real2lreal in TARGETS:
    p = rel
    s = io.open(p, encoding="utf-8").read()
    n = s.count(old)
    if n != expect:
        print("SKIP %s count=%d expect=%d" % (rel, n, expect)); continue
    s = s.replace(old, new)
    # 补局部声明（插在 _bPwsValid 声明行之后）
    m = re.search(r"^([ \t]*)_bPwsValid\s*:\s*BOOL;.*\n", s, re.M)
    if not m:
        print("SKIP decl %s" % rel); continue
    indent = m.group(1)
    if "_nPwsErr" not in s:
        s = s[:m.end()] + LOCALS.format(i=indent) + s[m.end():]
    if real2lreal:
        s = s.replace("fTempC := LREAL_TO_REAL(fTOut)", "fTempC := REAL_TO_LREAL(fTOut)")
        s = s.replace("fTempC := LREAL_TO_REAL(fTIn)",  "fTempC := REAL_TO_LREAL(fTIn)")
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)
    print("OK %s sites=%d" % (rel, n))
