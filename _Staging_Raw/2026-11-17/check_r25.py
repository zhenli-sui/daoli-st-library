# -*- coding: utf-8 -*-
"""R25-RESUME 红线机检（增量 20 件）：禁记号/物理地址/嵌套注释/占位符/终结符/双语/码位槽/跨库撞码"""
import io, os, re

FILES = {
 "FC_DL_Affine2DInvert":"DL_MathData",
 "FB_DL_ParticleCounterStat":"DL_Algo",
 "FB_DL_CoolingTowerApproachCalc":"DL_Algo",
 "FB_DL_InverterGridSync":"DL_Device",
 "FB_DL_HeatPumpDefrost":"DL_Device",
 "FB_DL_VavBoxCtrl":"DL_Device",
 "FB_DL_WaferMapping":"DL_Device",
 "FB_DL_DuctStaticReset":"DL_Algo",
 "FB_DL_DewpointReset":"DL_Algo",
 "FB_DL_RoomClimateCtrl":"DL_Process",
 "FB_DL_StackingAlignCtrl":"DL_Motion",
 "FB_DL_WeightCheckReject":"DL_Process",
 "FB_DL_LabelApplySync":"DL_Motion",
 "FB_DL_CasePackerPattern":"DL_Process",
 "FB_DL_BatteryTestCycler":"DL_Process",
 "FB_DL_PalletizerLayerSeq":"DL_Process",
 "FB_DL_SplicerAutoJoint":"DL_Process",
 "FB_DL_ChillerSeqMgr":"DL_Process",
 "FB_DL_FormationChannelMgr":"DL_Process",
 "FB_DL_SolarStringGroundFault":"DL_Process",
}
CODE_RE = re.compile(r"16#000[1-5]_[0-9A-F]{4}")
total_fail = 0
newcodes = {}
oldcodes = set()
for f in os.listdir("."):
    pass
import glob
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
    if not re.search(r"道莅.{0,30}防御性实现", s) and not re.search(r"道莅原创实现", s):
        fails.append("missing provenance tag")
    if "VAR_OUTPUT" not in s:
        fails.append("missing VAR_OUTPUT")
    # CASE 必须含 ELSE
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+\w+\s+OF", l, re.I):
            seg = "\n".join(lines[i-1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"ELSE", block, re.I):
                fails.append("L%d CASE without ELSE" % i)
    # 双语注释数量
    bi = 0
    for l in lines:
        if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{2,}", l):
            bi += 1
    if bi < 5:
        fails.append("bilingual comments too few: %d" % bi)
    # 码位槽 5~6
    head = s[:6000]
    seen = []
    for m in CODE_RE.finditer(head):
        u = m.group(0).upper()
        if u not in seen:
            seen.append(u)
    if not (5 <= len(seen) <= 6):
        fails.append("code slots=%d (expect 5~6)" % len(seen))
    newcodes[name] = seen
    clash = [c for c in seen if c in oldcodes]
    if clash:
        fails.append("code clash %s" % clash)
    total_fail += len(fails)
    print("%-32s %s" % (name, "PASS" if not fails else "FAIL: " + "; ".join(fails)))

allc = [c for v in newcodes.values() for c in v]
dup = len(allc) - len(set(allc))
dups = [c for c in set(allc) if allc.count(c) > 1]
print("\nsummary: fail=%d, intra-round dup=%d %s" % (total_fail, dup, dups if dup else ""))
print("files=%d, codes=%d" % (len(FILES), len(set(allc))))
