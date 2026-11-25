# -*- coding: utf-8 -*-
"""R80 静态红线预筛（非编译，仅主控预筛用，不替代闸席裁决）"""
import os, re, sys

BASE = r"C:\Library"
FILES = []
groups = {
    "DL_Process": "FC_DL_WeighNetFromGross FC_DL_WeighTareDriftCheck FC_DL_WeighDoseTolBand FB_DL_WeighHopperRefillSeq FC_DL_WeighMultiHeadSum FC_DL_WeighBatchYieldCalc FC_DL_WeighCreepCompensate FC_DL_WeighSpanCalibRatio FC_DL_MembraneFluxCalc FC_DL_MembraneTmpCalc FC_DL_WaterRecoveryRatio FC_DL_SludgeAgeCalc FC_DL_DoDeficitCalc FC_DL_CoagulantDoseCalc FC_DL_WaterLangelierIndex FB_DL_MultiTankBlendSeq FB_DL_ConveyorMergePrioritySeq FB_DL_DryerZoneProfileSeq",
    "DL_Device": "FC_DL_HydroCylForceCalc FC_DL_HydroCylFlowNeed FC_DL_HydroAccumulatorSizing FC_DL_PneuAirConsumeCalc FC_DL_PneuCvFlowCalc FC_DL_HydroPipePressDrop FB_DL_HydroPressRampSeq FC_DL_PneuLeakRateCalc FC_DL_RefCopCalc FC_DL_RefSuperheatCalc FC_DL_RefSubcoolCalc FC_DL_RefSatPressToTemp FC_DL_RefSatTempToPress FC_DL_RefCompressorCapacity FC_DL_RefCondApproach FB_DL_RefDefrostCycleSeq",
    "DL_MathData": "FC_DL_StatsRangeCalc FC_DL_StatsIqrCalc FC_DL_StatsPooledStd FB_DL_StatsRollingVar FC_DL_StatsGeoMeanCalc FC_DL_StatsDevSumSq",
}
for cat, s in groups.items():
    for n in s.split():
        FILES.append((cat, n, os.path.join(BASE, cat, n + ".st")))

CONV = re.compile(r"\b(LREAL|REAL|DINT|UDINT|INT|UINT|WORD|DWORD|BYTE|SINT|LINT|TIME|BOOL|STRING)\s*\(")
CONV_OK = ("REAL_TO_", "_TO_")
problems = []
missing = []
for cat, name, p in FILES:
    if not os.path.exists(p):
        missing.append((cat, name))
        continue
    txt = open(p, encoding="utf-8", errors="replace").read()
    lines = txt.splitlines()
    tags = []
    if "GVL" in txt or "VAR_EXTERNAL" in txt:
        tags.append("R1:GVL/VAR_EXTERNAL")
    if re.search(r"%[IQ][XBWDL0-9]", txt):
        tags.append("R2:phys-addr")
    if re.search(r"//\s*(略|同上|TODO|待补)", txt) or "..." in txt.replace("..", ".."):
        if re.search(r"(//\s*(略|同上|TODO))|(?<!\.)\.\.\.(?!\.)", txt):
            tags.append("R-placeholder")
    if "ABS(" in txt and re.search(r"ABS\s*\(\s*(\w+)\s*-\s*\1\s*\)\s*>", txt):
        tags.append("R447:dead-Inf-predicate")
    if "PROPERTY" in txt and "FUNCTION_BLOCK" in txt:
        tags.append("R14:PROPERTY-in-FB")
    # 构造函数式转换（排除 X_TO_Y 形式）
    for i, ln in enumerate(lines, 1):
        code = ln.split("(*")[0]
        for m in CONV.finditer(code):
            pre = code[max(0, m.start() - 8):m.start()]
            if "_TO_" in pre.upper() or pre.upper().endswith("_TO_"):
                continue
            tags.append("R10:ctor-conv@%d: %s" % (i, m.group(0).strip()))
            break
    # VAR 声明缺分号（粗略：声明块内以 : 类型结尾无 ; 的行）
    in_var = False
    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        if re.match(r"^(VAR|VAR_INPUT|VAR_OUTPUT|VAR_TEMP|VAR_CONSTANT)\b", s):
            in_var = True
            continue
        if s == "END_VAR":
            in_var = False
            continue
        if in_var and s and not s.startswith("(*") and not s.startswith("//"):
            code = s.split("(*")[0].split("//")[0].rstrip()
            if code and not code.endswith(";") and not code.endswith(":"):
                tags.append("R11:no-semicolon@%d" % i)
    # 块配对
    fb = len(re.findall(r"^FUNCTION_BLOCK\b", txt, re.M))
    ef = len(re.findall(r"^END_FUNCTION_BLOCK\b", txt, re.M))
    fc = len(re.findall(r"^FUNCTION\b", txt, re.M))
    efc = len(re.findall(r"^END_FUNCTION\b", txt, re.M))
    if fb != ef or fc != efc:
        tags.append("BLOCK-PAIR: fb=%d/%d fc=%d/%d" % (fb, ef, fc, efc))
    if tags:
        problems.append((cat, name, tags))

print("checked=%d missing=%d problems=%d" % (len(FILES), len(missing), len(problems)))
for m in missing:
    print("MISSING", m)
for cat, name, tags in problems:
    print("!!", name, "|", "; ".join(tags))
