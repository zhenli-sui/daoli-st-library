# -*- coding: utf-8 -*-
"""R20 红线机检：禁记号/嵌套注释/占位符/终结符/双语注释/码位5槽/跨库撞码（增量 20 件）"""
import io, os, re, glob

FILES = {
 "FC_DL_DtToDintEpoch":"DL_MathData","FC_DL_DintEpochToDt":"DL_MathData",
 "FC_DL_DateToDintDays":"DL_MathData","FC_DL_DintDaysToDate":"DL_MathData",
 "FC_DL_UdintToLintChk":"DL_MathData","FC_DL_WordToIntSat":"DL_MathData",
 "FC_DL_DwordToIntSat":"DL_MathData","FC_DL_LwordToLintSat":"DL_MathData",
 "FC_DL_BcdToByte":"DL_MathData","FC_DL_ByteToBcd":"DL_MathData",
 "FC_DL_TodAddWrap":"DL_MathData","FC_DL_TodDiffWrap":"DL_MathData",
 "FC_DL_SwapBytes64":"DL_MathData","FC_DL_DintToStringTrim":"DL_MathData",
 "FC_DL_LrealToStringTrim":"DL_MathData","FC_DL_DateAddDays":"DL_MathData",
 "FC_DL_DateDiffDays":"DL_MathData","FC_DL_TimeAbsSat":"DL_MathData",
 "FC_DL_LeapYearChk":"DL_Base","FB_DL_SemaMutex":"DL_Base",
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
    if re.search(r"\(\*.*\(\*|\(\*.*\*\).*\(\*", s, re.S):
        fails.append("nested comment")
    for ph in ["TODO", "FIXME", "……", "「同上」", "同上"]:
        if ph in s:
            fails.append("placeholder %s" % ph)
    if cat == "DL_Base" and name == "FB_DL_SemaMutex":
        if "END_FUNCTION_BLOCK" not in s:
            fails.append("missing END_FUNCTION_BLOCK")
    else:
        if "END_FUNCTION" not in s:
            fails.append("missing END_FUNCTION")
    if not re.search(r"道莅防御性实现", s):
        fails.append("missing provenance tag")
    # VAR_OUTPUT presence
    if "VAR_OUTPUT" not in s:
        fails.append("missing VAR_OUTPUT")
    # CASE must have ELSE
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+\w+\s+OF", l, re.I):
            # find matching END_CASE
            seg = "\n".join(lines[i-1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"ELSE", block, re.I):
                fails.append("L%d CASE without ELSE" % i)
    # bilingual comment: count lines with // containing CJK and ASCII letters
    bi = 0
    for l in lines:
        if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{2,}", l):
            bi += 1
    if bi < 5:
        fails.append("bilingual comments too few: %d" % bi)
    # code slots: exactly 5 distinct 16#0001_xxxx in head
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
    print("%-28s %s" % (name, "PASS" if not fails else "FAIL: " + "; ".join(fails)))

allc = [c for v in newcodes.values() for c in v]
dup = len(allc) - len(set(allc))
print("\nsummary: fail=%d, intra-round dup=%d" % (total_fail, dup))
if dup:
    print("DUP DETAIL:", allc)
