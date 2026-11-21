# -*- coding: utf-8 -*-
"""R33 机检（仅增量 23 件：20 新件 + 3 返修件）
规则集 = R32 全量 + 本轮新增 2 条：
  N1 周期节拍计时不得常真：TON/TOF 实例 IN 不得为字面 TRUE（R176）
  N2 CASE 块内禁止给“输出枚举”左侧赋值（R180）
码位体例改为 16#NN_S_XX（3 段），故障码 16#0000_00XX 不计槽。
"""
import io, os, re, glob, json

STAGE = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(STAGE, "..", ".."))

FILES = [
 ("FB_DL_SlurryViscosityComp", "DL_MathData", "16#02_3_5C"),
 ("FB_DL_ShrinkFilmUsageCalc", "DL_MathData", "16#02_3_5D"),
 ("FB_DL_TrackerSolarAngle", "DL_Algo", "16#02_3_5E"),
 ("FB_DL_FanBeltSlipDetect", "DL_Device", "16#03_1_01"),
 ("FB_DL_UnlockHoldTimeout", "DL_Device", "16#03_1_02"),
 ("FB_DL_VacuumPumpBasePress", "DL_Device", "16#03_1_03"),
 ("FB_DL_InverterDeratingCtrl", "DL_Device", "16#03_1_04"),
 ("FB_DL_PrecursorCanisterWeight", "DL_Device", "16#03_1_05"),
 ("FB_DL_ChillerLiftOptimize", "DL_Process", "16#06_0_37"),
 ("FB_DL_CoolingTowerOpt", "DL_Algo", "16#02_3_5F"),
 ("FB_DL_FreezeStatGuard", "DL_Process", "16#06_0_38"),
 ("FB_DL_StackPressureProfile", "DL_Process", "16#06_0_39"),
 ("FB_DL_PilePressLimitClass", "DL_Process", "16#06_0_3A"),
 ("FB_DL_PressFitCurveArchive", "DL_Process", "16#06_0_3B"),
 ("FB_DL_FilmTaperTension", "DL_Motion", "16#04_0_6C"),
 ("FB_DL_CartonScannerSort", "DL_Process", "16#06_0_3C"),
 ("FB_DL_PigLauncherSeq", "DL_Process", "16#06_0_3D"),
 ("FB_DL_FormationTempRiseRate", "DL_Process", "16#06_0_3E"),
 ("FB_DL_RollChangeoverSeq", "DL_Process", "16#06_0_3F"),
 ("FB_DL_AndonLinePack", "DL_Process", "16#06_0_40"),
 # 返修件（码位沿用）
 ("FB_DL_BlindPositionCtrl", "DL_Process", None),
 ("FB_DL_CompressorFleetStaging", "DL_Process", None),
 ("FB_DL_WaferThermalBudgetAccum", "DL_Process", None),
]

SEG_RE = re.compile(r"16#([0-9A-Fa-f]{2})_([0-9A-Fa-f])_([0-9A-Fa-f]{2})")
FAULT_RE = re.compile(r"16#0000_(?!0000)[0-9A-Fa-f]{4}")

mine = set(n for n, c, s in FILES)
oldseg = {}
for f in glob.glob("DL_*/*.st"):
    base = f.replace("\\", "/").split("/")[-1][:-3]
    if base in mine:
        continue
    txt = io.open(f, encoding="utf-8").read()
    for m in SEG_RE.finditer(txt):
        oldseg.setdefault(m.group(0).upper(), base)


def strip_nested_comments(s):
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", "", s, flags=re.S)
    return s


fails_total = 0
result = {}
for name, cat, want in FILES:
    path = os.path.join(cat, name + ".st")
    if not os.path.exists(path):
        print("%-32s MISSING" % name)
        fails_total += 1
        continue
    s = io.open(path, encoding="utf-8").read()
    lines = s.splitlines()
    f = []
    res = strip_nested_comments(s)
    patched = ("R33" in s) or ("1.0.1" in s)
    for tok in ["GVL", "VAR_EXTERNAL", "VAR_GLOBAL"]:
        if re.search(r"\b" + tok + r"\b", res):
            f.append("banned " + tok)
    if re.search(r"%[IQM][XBWDL]?\d", res):
        f.append("physical addr")
    if re.search(r"\bg_[A-Za-z]", res):
        f.append("global g_*")
    if "(*" in res or "*)" in res:
        f.append("nested/unpaired comment")
    for ph in ["TODO", "FIXME", "......", "同上", "同前", "见上", "待补", "ditto"]:
        if ph in s:
            f.append("placeholder " + ph)
    is_fc = name.startswith("FC_")
    opener = "FUNCTION" if is_fc else "FUNCTION_BLOCK"
    endt = "END_FUNCTION" if is_fc else "END_FUNCTION_BLOCK"
    n_open = len(re.findall(r"^" + opener + r"\s", res, re.M))
    n_close = res.count(endt)
    if n_open != 1 or n_close != n_open:
        f.append("terminator %d/%d" % (n_open, n_close))
    tail = [l for l in res.splitlines() if l.strip()]
    if not tail or tail[-1].strip() != endt:
        f.append("terminator not last")
    if len(re.findall(r"\bTYPE\s+\w+\s*:", s)) != len(re.findall(r"\bEND_TYPE\b", s)):
        f.append("TYPE pair mismatch")
    # 枚举单冒号（内联枚举体）
    for m in re.finditer(r":\s*\(([^()]*:=[^()]*)\)\s*;", res):
        body = m.group(1)
        for chunk in body.split(","):
            if re.search(r"(?<!:):(?!\s*=)", chunk):
                f.append("enum single colon: " + chunk.strip()[:28])
                break
    # CASE-ELSE
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+[\w.]+\s+OF", l, re.I):
            seg = "\n".join(lines[i - 1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"\bELSE\b", block, re.I):
                f.append("L%d CASE without ELSE" % i)
    bi = sum(1 for l in lines if "(" in l and "*)" in l
             and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{3,}", l))
    if bi < 10:
        f.append("bilingual too few: %d" % bi)
    if not re.search(r"防御性实现|clean-room|clean room", s):
        f.append("missing provenance")
    if "VAR_OUTPUT" not in s:
        f.append("missing VAR_OUTPUT")
    # 声明集合
    declared = set()
    for m in re.finditer(r"VAR(?:_INPUT|_OUTPUT|_IN_OUT)?\b(.*?)END_VAR", s, re.S):
        for dm in re.finditer(r"^\s*([A-Za-z_]\w*)\s*:", m.group(1), re.M):
            declared.add(dm.group(1))
    declared.add(name)
    # 输出枚举集合（VAR_OUTPUT 中内联枚举或 E_ 类型）
    outenum = set()
    mo = re.search(r"VAR_OUTPUT\b(.*?)END_VAR", s, re.S)
    if mo:
        for dm in re.finditer(r"^\s*([A-Za-z_]\w*)\s*:\s*(\(|E_)", mo.group(1), re.M):
            outenum.add(dm.group(1))
    balance = 0
    incase = False
    for i, l in enumerate(lines, 1):
        at_start = balance > 0
        balance += l.count("(") - l.count(")")
        if at_start or balance > 0:
            continue
        if re.match(r"\s*CASE\b", l, re.I):
            incase = True
        if re.match(r"\s*END_CASE\b", l, re.I):
            incase = False
        am = re.match(r"\s*([A-Za-z_]\w*)\s*:=", l)
        if am and am.group(1) not in declared:
            f.append("L%d undeclared assign: %s" % (i, am.group(1)))
        # N2
        if incase and am and am.group(1) in outenum:
            f.append("L%d CASE assigns output enum %s" % (i, am.group(1)))
    for i, l in enumerate(lines, 1):
        if re.fullmatch(r"\s*;\s*", l):
            f.append("L%d bare semicolon" % i)
    # N1 计时器常真
    for m in re.finditer(r"\b(ton|tof|tp|rto)[A-Za-z0-9_]*\s*\(\s*IN\s*:=\s*(TRUE|1)\b", res, re.I):
        f.append("timer IN const TRUE: " + m.group(0)[:18])
    # 码位
    segs = [m.group(0).upper() for m in SEG_RE.finditer(s)]
    uniq = []
    for c in segs:
        if c not in uniq:
            uniq.append(c)
    if not uniq:
        f.append("no CodeSeg")
    else:
        if want and uniq[0] != want.upper():
            f.append("CodeSeg %s != plan %s" % (uniq[0], want))
        if len(uniq) > 1:
            f.append("multi CodeSeg %s" % uniq)
        cl = [c for c in uniq if c in oldseg]
        if cl:
            f.append("seg clash " + str([(c, oldseg[c]) for c in cl]))
    if not FAULT_RE.search(s):
        f.append("no fault code slot")
    if is_fc and "FUNCTION_BLOCK" in s:
        f.append("FC file has FUNCTION_BLOCK")
    if not is_fc and not re.search(r"FUNCTION_BLOCK\s+" + re.escape(name) + r"\b", s):
        f.append("FB name mismatch")
    f = list(dict.fromkeys(f))
    fails_total += len(f)
    result[name] = {"cat": cat, "lines": len(lines), "code": uniq[0] if uniq else "",
                    "fails": f, "patched": patched}
    print("%-32s %-12s %4dL %-11s %s" % (name, cat, len(lines),
          uniq[0] if uniq else "-", "PASS" if not f else "FAIL: " + "; ".join(f)))

print("\nsummary: fail=%d files=%d total_lines=%d" % (
    fails_total, len(result), sum(v["lines"] for v in result.values())))
json.dump(result, io.open(os.path.join(STAGE, "_check_r33_result.json"), "w",
                          encoding="utf-8"), ensure_ascii=False, indent=1)
