# -*- coding: utf-8 -*-
"""R44 增量机检（20 新件 + 1 返修件）：R41 口径 + 禁词 + 溯源短语（本轮全 T1/T2/自研，无 T0）"""
import os, re, io, glob

LIB = "C:/Library"
TARGETS = [
    ("FC_DL_DewPointToPpmV", "DL_MathData"),
    ("FB_DL_GainSchedPid", "DL_Algo"), ("FB_DL_RelayAutoTune", "DL_Algo"),
    ("FB_DL_BumplessHandAuto", "DL_Algo"),
    ("FB_DL_AxisBacklashComp", "DL_Motion"), ("FB_DL_AxisTorqueWatch", "DL_Motion"),
    ("FB_DL_AxisBrakeTest", "DL_Motion"), ("FB_DL_AxisFrictionFf", "DL_Motion"),
    ("FB_DL_CircInterp2Axis", "DL_Motion"),
    ("FB_DL_LoadcellTareCtrl", "DL_Device"), ("FB_DL_ValvePartialStrokeTest", "DL_Device"),
    ("FB_DL_RotaryUnionWatch", "DL_Device"), ("FB_DL_HeaterSsrBank", "DL_Device"),
    ("FB_DL_ChillerStagingSeq", "DL_Process"), ("FB_DL_DesiccantRegenSeq", "DL_Process"),
    ("FB_DL_VacuumBakeOutSeq", "DL_Process"), ("FB_DL_CellAgingRestSeq", "DL_Process"),
    ("FB_DL_LaserDescumStep", "DL_Process"), ("FB_DL_AirLeakDecayTest", "DL_Process"),
    ("FB_DL_CoolingTowerReset", "DL_Process"),
    ("FB_DL_CassetteMapVerify", "DL_Process", "REPAIR"),
]
BANNED_WORDS = [r"\bTODO\b", r"\bFIXME\b", r"待补[充善]", r"\bXXX\b"]

def strip_comments(t):
    t = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    return t

DUPCODE = {}
for f in glob.glob(os.path.join(LIB, "DL_*", "*.st")):
    txt = io.open(f, encoding="utf-8", errors="ignore").read()
    base = os.path.basename(f)[:-3]
    for m in set(re.findall(r"16#000[0-9]_[0-9A-Fa-f]{4}", txt)):
        if m.upper().endswith("_0000"):
            continue
        DUPCODE.setdefault(m.upper(), set()).add(base)

def check(name, cat, repair=False):
    p = os.path.join(LIB, cat, name + ".st")
    if not os.path.exists(p):
        return ["MISSING FILE"]
    raw = io.open(p, "rb").read()
    txt = raw.decode("utf-8", "replace")
    body = strip_comments(txt)
    errs = []
    for b in [r"\bVAR_EXTERNAL\b", r"\bGVL\b", r"%[IQM][XBWDL]?\d"]:
        for m in re.finditer(b, body):
            errs.append("BANNED %s @L%d" % (b, body[:m.start()].count("\n") + 1))
    for m in re.finditer(r"TYPE\s+\w+\s*:\s*\(([^)]*)\)", body, flags=re.S):
        for mem in m.group(1).split(","):
            if re.search(r":(?!s*=)", mem):
                errs.append("ENUM COLON %s" % mem.strip()[:24])
    ncase = len(re.findall(r"^\s*CASE\b", body, re.M))
    nelse = len(re.findall(r"^\s*ELSE\s*$", body, re.M))
    if ncase and nelse < ncase:
        errs.append("CASE WITHOUT ELSE ncase=%d nelse=%d" % (ncase, nelse))
    if re.search(r"\(\*(?:(?!\*\)).)*\(\*", txt, flags=re.S):
        errs.append("NESTED COMMENT")
    if not repair and not re.search(r"VAR_OUTPUT", body):
        errs.append("NO VAR_OUTPUT SECTION")
    for m in re.finditer(r"^\s*(\w+)\s*\(\s*IN\s*:?=", body, re.M):
        inst = m.group(1)
        if re.search(r"\b%s\s*:\s*(TON|TOF|R_TRIG|F_TRIG|CTU|CTD)\b" % inst, body, re.I):
            depth = 0
            for line in body[:m.start()].splitlines():
                ls = line.strip()
                if re.match(r"IF\b", ls): depth += 1
                elif re.match(r"END_IF", ls): depth -= 1
            if depth > 0:
                errs.append("FB-INSTANCE IN IF %s @L%d" % (inst, body[:m.start()].count("\n") + 1))
    if not re.search(r"^\s*END_FUNCTION(_BLOCK)?\b", body, re.M):
        errs.append("NO POU TERMINATOR")
    for w in BANNED_WORDS:
        for m in re.finditer(w, txt):
            errs.append("BANNED WORD %s @L%d" % (w, txt[:m.start()].count("\n") + 1))
    if b"\r\n" not in raw:
        errs.append("NOT CRLF")
    for seg in set(re.findall(r"16#000[0-9]_[0-9A-Fa-f]{4}", txt)):
        if seg.upper().endswith("_0000"):
            continue
        others = [x for x in DUPCODE.get(seg.upper(), set()) if x != name]
        if others:
            errs.append("CODE DUP %s with %s" % (seg, ",".join(sorted(others))))
    return errs

total = 0; npass = 0
for t in TARGETS:
    name, cat = t[0], t[1]
    repair = (len(t) > 2 and t[2] == "REPAIR")
    e = check(name, cat, repair)
    total += len(e)
    if not e: npass += 1
    print("%-30s %-12s %s" % (name, cat, "PASS" if not e else "FAIL: " + "; ".join(e)))
print("=" * 60)
print("TOTAL=%d PASS=%d/%d" % (total, npass, len(TARGETS)))
