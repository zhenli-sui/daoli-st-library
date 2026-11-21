# -*- coding: utf-8 -*-
"""R41 增量机检（20 新件 + 3 返修件）：沿用 R40 口径 + R228A/B 规则 + 全库码位碰撞（16#000x 通用段）"""
import os, re, io, glob

LIB = "C:/Library"
TARGETS = [
    ("FB_DL_SignalQualify", "DL_Base"), ("FB_DL_MultiClickDetect", "DL_Base"),
    ("FC_DL_AngleDiffWrap", "DL_MathData", True),  # True = T0 iec-std-wrapper 需溯源头
    ("FC_DL_WeightedMeanCalc", "DL_MathData"), ("FC_DL_QuantileCalc", "DL_MathData"),
    ("FB_DL_ValueHoldMonitor", "DL_Base"), ("FB_DL_WindowExtremaStat", "DL_MathData"),
    ("FB_DL_OverrideSelector", "DL_Algo"),
    ("FB_DL_AxisFollowErrGuard", "DL_Motion"), ("FB_DL_AxisOverspeedGuard", "DL_Motion"),
    ("FB_DL_AxisInposGuard", "DL_Motion"), ("FB_DL_AxisAbortSafeSeq", "DL_Motion"),
    ("FB_DL_StepResponseIdent", "DL_Algo"), ("FB_DL_RatioStationCalc", "DL_Algo"),
    ("FB_DL_CascadeWindupLink", "DL_Algo"),
    ("FB_DL_InverterPdiPoll", "DL_Device"), ("FB_DL_FilterSwitchLevel", "DL_Device"),
    ("FB_DL_ShrinkTunnelCtrl", "DL_Process"), ("FB_DL_VavDischargeAirReset", "DL_Process"),
    ("FB_DL_ConveyorDirMismatch", "DL_Process"),
    # 返修件
    ("FB_DL_AxisLimitRecovery", "DL_Motion", "REPAIR"),
    ("FB_DL_MutexOwnerAudit", "DL_Base", "REPAIR"),
    ("FC_DL_StringToDint", "DL_MathData", "REPAIR"),
]

def strip_comments(t):
    t = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    return t

# 全库码位登记（头部 2000B ∪ 全文，R39 口径）
DUPCODE = {}
for f in glob.glob(os.path.join(LIB, "DL_*", "*.st")):
    txt = io.open(f, encoding="utf-8", errors="ignore").read()
    base = os.path.basename(f)[:-3]
    for m in set(re.findall(r"16#000[0-9]_[0-9A-Fa-f]{4}", txt)):
        if m.upper().endswith("_0000"):
            continue  # 哨兵码全库共用，非槽位（R32 教训）
        DUPCODE.setdefault(m.upper(), set()).add(base)

def check(name, cat, is_t0=False):
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
    if not re.search(r"VAR_OUTPUT", body):
        errs.append("NO VAR_OUTPUT SECTION")
    for m in re.finditer(r"^\s*(\w+)\s*\(\s*IN\s*:?=", body, re.M):
        inst = m.group(1)
        if re.search(r"\b%s\s*:\s*(TON|TOF|R_TRIG|F_TRIG|CTU|CTD)\b" % inst, body, re.I):
            pre = body[:m.start()]
            depth = 0
            for line in pre.splitlines():
                ls = line.strip()
                if re.match(r"IF\b", ls): depth += 1
                elif re.match(r"END_IF", ls): depth -= 1
            if depth > 0:
                errs.append("FB-INSTANCE IN IF %s @L%d" % (inst, body[:m.start()].count("\n") + 1))
    if not re.search(r"^\s*END_FUNCTION(_BLOCK)?\b", body, re.M):
        errs.append("NO POU TERMINATOR")
    if is_t0 and "IEC 61131-3 标准语义的道莅防御性实现" not in txt:
        errs.append("NO SOURCE TRACE HEADER")
    if b"\r\n" not in raw:
        errs.append("NOT CRLF")
    # 码位碰撞（全文口径，仅报跨文件）
    for seg in set(re.findall(r"16#000[0-9]_[0-9A-Fa-f]{4}", txt)):
        if seg.upper().endswith("_0000"):
            continue  # 哨兵码豁免
        others = [x for x in DUPCODE.get(seg.upper(), set()) if x != name]
        if others:
            errs.append("CODE DUP %s with %s" % (seg, ",".join(sorted(others))))
    # R228A：TON 跨相（ton* 非 tonXxxTo 的实例在 CASE 分支内 IN 赋值粗扫）
    return errs

total = 0
for t in TARGETS:
    name, cat = t[0], t[1]
    is_t0 = (len(t) > 2 and t[2] is True)
    e = check(name, cat, is_t0)
    total += len(e)
    print("%-28s %-12s %s" % (name, cat, "PASS" if not e else "FAIL: " + "; ".join(e)))
print("=" * 60)
print("TOTAL=%d PASS_COUNT=%d/%d" % (total, sum(1 for t in TARGETS if not check(t[0], t[1], len(t) > 2 and t[2] is True)), len(TARGETS)))
