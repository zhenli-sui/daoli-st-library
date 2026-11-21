# -*- coding: utf-8 -*-
"""R26 红线机检（增量 20 件）：禁记号/物理地址/嵌套注释/占位符/终结符/双语/码位槽/跨库撞码 + 枚举-CASE 完备性"""
import io, os, re, glob

FILES = {
 "FB_DL_MinPulseWidthFilter":"DL_Base",
 "FC_DL_StringPad":"DL_MathData",
 "FB_DL_EventRateCalc":"DL_MathData",
 "FB_DL_HistogramAccum":"DL_MathData",
 "FC_DL_WeightedMovingAvg":"DL_MathData",
 "FB_DL_PidGainScheduler":"DL_Algo",
 "FB_DL_ControlValveDiag":"DL_Device",
 "FB_DL_MotorPtcThermistProtect":"DL_Device",
 "FB_DL_ElectrolyteTankLevel":"DL_Device",
 "FB_DL_PumpDryRunProtect":"DL_Device",
 "FB_DL_AxisLoadTorqueMonitor":"DL_Motion",
 "FC_DL_CamTableInterp":"DL_Motion",
 "FB_DL_AlarmShelving":"DL_Process",
 "FB_DL_ChillerTempStab":"DL_Process",
 "FB_DL_LineChangeoverChecklist":"DL_Process",
 "FB_DL_TankFarmInventory":"DL_Process",
 "FB_DL_EnergyKpiAggregator":"DL_Process",
 "FB_DL_FanBeltSlipDiag":"DL_Device",
 "FB_DL_VfdThermalDerate":"DL_Device",
 "FB_DL_DustFreehoodPress":"DL_Device",
}
CODE_RE = re.compile(r"16#000[1-5]_[0-9A-F]{4}")
ALGO_CC_RE = re.compile(r"16#0002_[0-9A-F]{2}[0-9A-F]{2}")
total_fail = 0
newcodes = {}
oldcodes = set()
oldcc = set()
mine = set(FILES)

for f in glob.glob("DL_*/*.st"):
    base = f.replace("\\", "/").split("/")[-1][:-3]
    if base in mine:
        continue
    txt = io.open(f, encoding="utf-8").read()
    for m in CODE_RE.finditer(txt):
        oldcodes.add(m.group(0).upper())
for f in glob.glob("DL_Algo/*.st"):
    if f.replace("\\", "/").split("/")[-1][:-3] in mine:
        continue
    txt = io.open(f, encoding="utf-8").read()
    for m in re.finditer(r"16#0002_[0-9A-Fa-f]{4}", txt):
        oldcc.add(m.group(0).upper())

for name, cat in FILES.items():
    path = os.path.join(cat, name + ".st")
    if not os.path.exists(path):
        print("%-32s MISSING" % name); total_fail += 1; continue
    s = io.open(path, encoding="utf-8").read()
    lines = s.splitlines()
    fails = []
    # R1 禁记号（语义替代）
    for tok in ["GVL", "VAR_EXTERNAL", "VAR_GLOBAL"]:
        if re.search(r"\b" + tok + r"\b", s):
            fails.append("banned %s" % tok)
    if re.search(r"%[IQM][XBWDL]?\d", s):
        fails.append("physical addr")
    if re.search(r"\bg_[A-Za-z]", s):
        fails.append("global g_*")
    # R28 嵌套注释（非贪婪成对剥离）
    _st = re.sub(r"\(\*.*?\*\)", "", s, flags=re.S)
    if "(*" in _st or "*)" in _st:
        fails.append("nested comment")
    # 占位符
    for ph in ["TODO", "FIXME", "……", "同上", "待补", "<...>"]:
        if ph in s:
            fails.append("placeholder %s" % ph)
    # R2 终结符在最末行
    endt = "END_FUNCTION_BLOCK" if "END_FUNCTION_BLOCK" in s else "END_FUNCTION"
    tail = [l for l in lines if l.strip()]
    if not tail or tail[-1].strip() != endt:
        fails.append("terminator not last line")
    # 溯源短语
    if not re.search(r"道莅.{0,30}防御性实现", s):
        fails.append("missing provenance tag")
    # VAR_OUTPUT
    if "VAR_OUTPUT" not in s:
        fails.append("missing VAR_OUTPUT")
    # R31 CASE 必含 ELSE
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+[\w.]+\s+OF", l, re.I):
            seg = "\n".join(lines[i-1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"ELSE", block, re.I):
                fails.append("L%d CASE without ELSE" % i)
    # R26 孤立分号分支
    for i, l in enumerate(lines, 1):
        if re.fullmatch(r"\s*;\s*", l):
            fails.append("L%d bare semicolon" % i)
    # 双语注释
    bi = sum(1 for l in lines if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{2,}", l))
    if bi < 5:
        fails.append("bilingual too few: %d" % bi)
    # R33 枚举成员单冒号
    for m in re.finditer(r"TYPE\s+(\w+)\s*:\s*\((.*?)\)", s, re.S):
        for mem in m.group(2).split(","):
            if ":" in mem and ":=" not in mem and mem.strip():
                fails.append("R33 enum %s member single colon" % m.group(1)); break
    # 码位槽 2~6（R124 已裁定按 POU 类型分型）
    seen = []
    for m in CODE_RE.finditer(s):
        u = m.group(0).upper()
        if u not in seen:
            seen.append(u)
    for m in re.finditer(r"16#0002_[0-9A-Fa-f]{4}\b", s):
        u = m.group(0).upper()
        if u.startswith("16#0002_0") and u not in seen:
            seen.append(u)
    if not (2 <= len(seen) <= 6):
        fails.append("code slots=%d (expect 2~6)" % len(seen))
    newcodes[name] = seen
    clash = [c for c in seen if c in oldcodes or c in oldcc]
    if clash:
        fails.append("code clash %s" % clash)
    total_fail += len(fails)
    print("%-32s %-14s %5d lines  %s" % (name, cat, len(lines), "PASS" if not fails else "FAIL: " + "; ".join(fails)))

allc = [c for v in newcodes.values() for c in v]
dup = [c for c in set(allc) if allc.count(c) > 1]
print("\nsummary: fail=%d, intra-round dup=%d %s, files=%d, codes=%d"
      % (total_fail, len(dup), dup if dup else "", len(newcodes), len(set(allc))))
print("total lines: %d" % sum(len(io.open(os.path.join(c, n + ".st"), encoding="utf-8").read().splitlines()) for n, c in FILES.items() if os.path.exists(os.path.join(c, n + ".st"))))
