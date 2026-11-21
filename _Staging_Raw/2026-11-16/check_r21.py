# -*- coding: utf-8 -*-
"""R21 红线机检：禁记号/嵌套注释/占位符/终结符/双语注释/码位5槽/跨库撞码（增量 20 件）"""
import io, os, re, glob

FILES = {
 "FC_DL_ModPos":"DL_MathData","FC_DL_DivLrealSafe":"DL_MathData",
 "FC_DL_QuantizeStep":"DL_MathData","FC_DL_PolyEvalHorner":"DL_MathData",
 "FC_DL_WrapAngleDeg":"DL_MathData","FC_DL_LwordBitFieldExtract":"DL_MathData",
 "FC_DL_LwordBitFieldInsert":"DL_MathData","FC_DL_LwordBitCount":"DL_MathData",
 "FC_DL_Crc16Generic":"DL_MathData","FC_DL_ChecksumSum8":"DL_MathData",
 "FC_DL_StringToDint":"DL_MathData","FC_DL_DwordToHexString":"DL_MathData",
 "FC_DL_ArraySumLreal":"DL_MathData","FC_DL_TimeToHmsString":"DL_MathData",
 "FC_DL_DateToIsoString":"DL_MathData","FB_DL_MinOnOffGuard":"DL_Base",
 "FB_DL_SignalChangeCounter":"DL_Base","FB_DL_SamplingTrigger":"DL_Base",
 "FB_DL_SignalFrozenDetect":"DL_Base","FB_DL_PulseWidthFilter":"DL_Base",
}
CODE_RE = re.compile(r"16#000[1-5]_[0-9A-F]{4}")
total_fail = 0
newcodes = {}
oldcodes = set()
for f in glob.glob("DL_*/*.st"):
    base = f.replace("\\", "/").split("/")[-1][:-3]
    if base in FILES:
        continue
    for m in CODE_RE.finditer(io.open(f, encoding="utf-8").read()):
        oldcodes.add(m.group(0).upper())

for name, cat in FILES.items():
    path = os.path.join(cat, name + ".st")
    s = io.open(path, encoding="utf-8").read()
    lines = s.splitlines()
    fails = []
    for tok in ["GVL", "VAR_EXTERNAL"]:
        if tok in s:
            fails.append("banned %s" % tok)
    if re.search(r"%[IQM][XBWDL]?\d", s):
        fails.append("physical addr")
    if re.search(r"\bg_[A-Za-z]", s):
        fails.append("global g_*")
    _stripped = re.sub(r"\(\*.*?\*\)", "", s, flags=re.S)
    if "(*" in _stripped or "*)" in _stripped:
        fails.append("nested comment")
    for ph in ["TODO", "FIXME", "……", "「同上」", "同上"]:
        if ph in s:
            fails.append("placeholder %s" % ph)
    endt = "END_FUNCTION_BLOCK" if name.startswith("FB_") else "END_FUNCTION"
    if endt not in s:
        fails.append("missing " + endt)
    if not re.search(r"道莅.{0,20}防御性实现", s):
        fails.append("missing provenance tag")
    if "VAR_OUTPUT" not in s:
        fails.append("missing VAR_OUTPUT")
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+\w+\s+OF", l, re.I):
            seg = "\n".join(lines[i-1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"ELSE", block, re.I):
                fails.append("L%d CASE without ELSE" % i)
    bi = 0
    for l in lines:
        if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{2,}", l):
            bi += 1
    if bi < 5:
        fails.append("bilingual comments too few: %d" % bi)
    head = s[:4000]
    seen = []
    for m in CODE_RE.finditer(head):
        u = m.group(0).upper()
        if u not in seen:
            seen.append(u)
    if len(seen) != 5:
        fails.append("code slots=%d (expect 5)" % len(seen))
    newcodes[name] = seen
    clash = [c for c in seen if c in oldcodes]
    if clash:
        fails.append("code clash %s" % clash)
    total_fail += len(fails)
    print("%-30s %s" % (name, "PASS" if not fails else "FAIL: " + "; ".join(fails)))

allc = [c for v in newcodes.values() for c in v]
dup = len(allc) - len(set(allc))
print("\nsummary: fail=%d, intra-round dup=%d" % (total_fail, dup))
if dup:
    print("DUP DETAIL:", allc)
