# -*- coding: utf-8 -*-
"""R40 增量机检（仅 15 新件）规则：禁 GVL/VAR_EXTERNAL、禁 %I/%Q、ENUM 冒号、
CASE 缺 ELSE、注释嵌套、VAR_OUTPUT 缺失、TON/R_TRIG 条件分支内刷新、CRLF、码位重复"""
import os, re, io, json, glob

LIB = "C:/Library"
TARGETS = [
    ("FC_DL_MaxNanEx", "DL_MathData"), ("FC_DL_MinNanEx", "DL_MathData"),
    ("FC_DL_RealEqTolEx", "DL_MathData"), ("FC_DL_RangeCheckEx", "DL_MathData"),
    ("FC_DL_RealToDintSat", "DL_MathData"), ("FC_DL_RealToRealSat", "DL_MathData"),
    ("FC_DL_RoundBankEx", "DL_MathData"), ("FC_DL_DegToRadEx", "DL_MathData"),
    ("FC_DL_RadToDegEx", "DL_MathData"), ("FC_DL_MuxIntEx", "DL_MathData"),
    ("FC_DL_StringToLowerEx", "DL_MathData"), ("FC_DL_StringToUdintEx", "DL_MathData"),
    ("FB_DL_SrEx", "DL_Base"), ("FB_DL_RsEx", "DL_Base"),
    ("FC_DL_IndexClampEx", "DL_MathData"),
]

def strip_comments(t):
    t = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    return t

DUPCODE = {}
for f in glob.glob(os.path.join(LIB, "DL_*", "*.st")):
    h = io.open(f, encoding="utf-8", errors="ignore").read(2000)
    for m in re.finditer(r"16#0001_[0-9A-Fa-f]{4}", h):
        DUPCODE.setdefault(m.group(0).upper(), []).append(os.path.basename(f))

def check(name, cat):
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
    # TON/R_TRIG 实例在条件分支内刷新
    for m in re.finditer(r"^\s*(\w+)\s*\(\s*IN\s*:?=", body, re.M):
        inst = m.group(1)
        if re.search(r"\b%s\s*:\s*(TON|TOF|R_TRIG|F_TRIG|CTU|CTD)\b" % inst, body, re.I):
            pre = body[:m.start()]
            depth_if = 0
            for line in pre.splitlines():
                ls = line.strip()
                if re.match(r"IF\b", ls): depth_if += 1
                elif re.match(r"END_IF", ls): depth_if -= 1
            if depth_if > 0:
                errs.append("FB-INSTANCE CALL INSIDE IF %s @L%d" % (inst, body[:m.start()].count("\n") + 1))
    if not re.search(r"^\s*END_FUNCTION(_BLOCK)?\b", body, re.M):
        errs.append("NO POU TERMINATOR")
    if "IEC 61131-3 标准语义的道莅防御性实现" not in txt:
        errs.append("NO SOURCE TRACE HEADER")
    if b"\r\n" not in raw:
        errs.append("NOT CRLF")
    hdr = txt[:2000]
    for m in set(re.findall(r"16#0001_[0-9A-Fa-f]{4}", hdr)):
        others = [x for x in DUPCODE.get(m.upper(), []) if x != name + ".st"]
        if others:
            errs.append("CODE DUP %s with %s" % (m, ",".join(others)))
    return errs

rows, total = [], 0
for name, cat in TARGETS:
    e = check(name, cat)
    total += len(e)
    rows.append({"name": name, "cat": cat, "errors": e})
    print("%-28s %-13s %s" % (name, cat, "PASS" if not e else "FAIL"))
    for x in e:
        print("    - " + x)
print("=" * 60)
print("FILES=%d PASS=%d FAIL=%d ERRS=%d" % (len(rows),
    sum(1 for r in rows if not r["errors"]), sum(1 for r in rows if r["errors"]), total))
json.dump(rows, io.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_check_r40_result.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
