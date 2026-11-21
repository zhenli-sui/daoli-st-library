# -*- coding: utf-8 -*-
"""R28 红线机检（17 件）：禁记号/物理地址/嵌套注释/占位符/相对指代/终结符/双语/码位槽/撞码 + 枚举-CASE 完备性"""
import io, os, re, glob

FILES = [
 ("FC_DL_FanLawMultiExpCalc","DL_Algo"),
 ("FB_DL_StepperXyzGantry","DL_Motion"),
 ("FB_DL_StepperFeederBelt","DL_Motion"),
 ("FB_DL_CheckweighZeroTrack","DL_Device"),
 ("FB_DL_EfEmDoorInterlockPlus","DL_Device"),
 ("FB_DL_LaserTabWeldTrack","DL_Motion"),
 ("FB_DL_NotchAlignSeq","DL_Motion"),
 ("FB_DL_EdgeTrimTraverse","DL_Motion"),
 ("FB_DL_NtcChannelHealth","DL_Device"),
 ("FB_DL_WaferCassetteSlot","DL_Device"),
 ("FB_DL_LamCtrlDualZone","DL_Device"),
 ("FB_DL_LaminatorVacLeakTrend","DL_Process"),
 ("FB_DL_PumpDownEnvelopeMonitor","DL_Process"),
 ("FB_DL_SealJawDwellTrim","DL_Process"),
 ("FB_DL_BatchDeviationTierAlarm","DL_Process"),
 ("FB_DL_InlineCheckweighGauge","DL_Process"),
 ("FB_DL_ChillerStagingCurve","DL_Process"),
]
CODE_RE = re.compile(r"16#000[1-5]_[0-9A-F]{4}")
ENUM_RE = re.compile(r"TYPE\s+(\w+)\s*:\s*\(\s*(.*?)\)\s*(?:UINT|UDINT|INT|DINT)?\s*;\s*END_TYPE", re.S)
mine = set(n for n, c in FILES)
oldcodes = {}
for f in glob.glob("DL_*/*.st"):
    base = f.replace("\\", "/").split("/")[-1][:-3]
    if base in mine:
        continue
    txt = io.open(f, encoding="utf-8").read()
    for m in CODE_RE.finditer(txt):
        oldcodes.setdefault(m.group(0).upper(), base)

total_fail = 0
newcodes = {}
for name, cat in FILES:
    path = os.path.join(cat, name + ".st")
    if not os.path.exists(path):
        print("%-32s MISSING" % name); total_fail += 1; continue
    s = io.open(path, encoding="utf-8").read()
    lines = s.splitlines()
    fails = []
    for tok in ["GVL", "VAR_EXTERNAL", "VAR_GLOBAL"]:
        if re.search(r"\b" + tok + r"\b", s):
            fails.append("banned " + tok)
    if re.search(r"%[IQM][XBWDL]?\d", s):
        fails.append("physical addr")
    if re.search(r"\bg_[A-Za-z]", s):
        fails.append("global g_*")
    stripped = re.sub(r"\(\*.*?\*\)", "", s, flags=re.S)
    if "(*" in stripped or "*)" in stripped:
        fails.append("nested comment")
    for ph in ["TODO", "FIXME", "......", "同上", "同前", "见上", "待补", "<...>", "ditto", "idem"]:
        if ph in s:
            fails.append("placeholder " + ph)
    endt = "END_FUNCTION_BLOCK" if "END_FUNCTION_BLOCK" in s else "END_FUNCTION"
    tail = [l for l in lines if l.strip()]
    if not tail or tail[-1].strip() != endt:
        fails.append("terminator not last line")
    if not re.search(r"道莅.{0,40}防御性实现", s):
        fails.append("missing provenance tag")
    if "VAR_OUTPUT" not in s:
        fails.append("missing VAR_OUTPUT")
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+[\w.]+\s+OF", l, re.I):
            seg = "\n".join(lines[i-1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"ELSE", block, re.I):
                fails.append("L%d CASE without ELSE" % i)
        if re.fullmatch(r"\s*;\s*", l):
            fails.append("L%d bare semicolon" % i)
    bi = sum(1 for l in lines if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{2,}", l))
    if bi < 5:
        fails.append("bilingual too few: %d" % bi)
    nc = re.sub(r"//[^\n]*", "", s)
    nc2 = re.sub(r"\(\*.*?\*\)", "", nc, flags=re.S)
    for m in ENUM_RE.finditer(nc2):
        body = m.group(2)
        for chunk in body.split(","):
            if ":" in chunk.replace(":=", ""):
                fails.append("enum %s member single colon" % m.group(1))
                break
        members = []
        for chunk in body.split(","):
            if ":=" in chunk:
                mm = re.match(r"\s*([A-Za-z_]\w*)", chunk)
                if mm:
                    members.append(mm.group(1))
        for mem in members:
            if not re.search(r"\b" + re.escape(mem) + r"\s*:", nc2):
                fails.append("enum %s member %s no CASE label" % (m.group(1), mem))
    for m in re.finditer(r"TYPE\s+(\w+)\s*:\s*\(", s):
        if m.group(1).upper().startswith("ST_"):
            fails.append("struct %s written as enum" % m.group(1))
    for m in re.finditer(r"TYPE\s+(\w+)\s*:\s*STRUCT", s):
        if "END_STRUCT" not in s[m.end():]:
            fails.append("struct %s without END_STRUCT" % m.group(1))
    seen = []
    for m in CODE_RE.finditer(s):
        u = m.group(0).upper()
        if u not in seen:
            seen.append(u)
    if not (2 <= len(seen) <= 6):
        fails.append("code slots=%d (expect 2~6)" % len(seen))
    newcodes[name] = seen
    clash = [c for c in seen if c in oldcodes]
    if clash:
        fails.append("code clash %s" % [(c, oldcodes[c]) for c in clash])
    total_fail += len(fails)
    print("%-32s %-12s %4d lines %2d codes  %s" % (name, cat, len(lines), len(seen), "PASS" if not fails else "FAIL: " + "; ".join(fails)))

allc = [c for v in newcodes.values() for c in v]
dup = [c for c in set(allc) if allc.count(c) > 1]
print("\nsummary: fail=%d intra-round dup=%d %s files=%d" % (total_fail, len(dup), dup if dup else "", len(newcodes)))
print("total lines: %d" % sum(len(io.open(os.path.join(c, n + ".st"), encoding="utf-8").read().splitlines()) for n, c in FILES if os.path.exists(os.path.join(c, n + ".st"))))
