# -*- coding: utf-8 -*-
"""R32 机检（20 件增量）：禁记号/拆分注释剥离/占位符/终结符成对/TYPE成对/
枚举单冒号/枚举⊆CASE/CASE-ELSE/双语注释/溯源/赋值目标已声明/孤立分号/码位槽块/撞码/前缀一致
码位格式适配 16#NN_S_XX（R32 起新体例）。"""
import io, os, re, glob, json

STAGE = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(STAGE, "..", ".."))  # C:/Library

FILES = [
 ("FC_DL_StringToUpperEx", "DL_MathData"),
 ("FC_DL_StringStripCharsEx", "DL_MathData"),
 ("FC_DL_BytesToHexString", "DL_MathData"),
 ("FC_DL_HexStringToLword", "DL_MathData"),
 ("FC_DL_ReverseBitsWord", "DL_MathData"),
 ("FC_DL_DtAddSecondsSat", "DL_MathData"),
 ("FC_DL_DivDintSafeChk", "DL_MathData"),
 ("FC_DL_ModLrealSafe", "DL_MathData"),
 ("FC_DL_BitArrayReverse", "DL_MathData"),
 ("FB_DL_SteamTrapDiagTrend", "DL_Process"),
 ("FB_DL_ColumnDpSteadyWatch", "DL_Process"),
 ("FB_DL_VavCouplingFeedforward", "DL_Process"),
 ("FB_DL_BlindPositionCtrl", "DL_Process"),
 ("FB_DL_CompressorFleetStaging", "DL_Process"),
 ("FB_DL_AhuSupplyAirReset", "DL_Process"),
 ("FB_DL_BatteryModuleBalanceMonitor", "DL_Process"),
 ("FB_DL_WaferThermalBudgetAccum", "DL_Process"),
 ("FB_DL_CaseSealerFlapFoldSeq", "DL_Process"),
 ("FB_DL_NitrideFurnaceAmmoniaPurge", "DL_Process"),
 ("FB_DL_BusbarWeldMonitor", "DL_Process"),
]
CODE_RE = re.compile(r"16#\d{4}_[0-9A-Fa-f]{4}")
ENUM_RE = re.compile(r"TYPE\s+(\w+)\s*:\s*\(\s*(.*?)\)\s*(?:UINT|UDINT|INT|DINT)?\s*;\s*END_TYPE", re.S)
EXEMPT_ENUM_OWNERS = {"E_DL_Ne107Status": "I_DL_DeviceHealth"}

mine = set(n for n, c in FILES)
oldcodes = {}
old_enum_owners = {}
for f in glob.glob("DL_*/*.st"):
    base = f.replace("\\", "/").split("/")[-1][:-3]
    if base in mine:
        continue
    txt = io.open(f, encoding="utf-8").read()
    for m in CODE_RE.finditer(txt):
        if m.group(0).upper() == "16#0000_0000":
            continue
        oldcodes.setdefault(m.group(0).upper(), base)
    for m in re.finditer(r"TYPE\s+(\w+)\s*:", txt):
        old_enum_owners.setdefault(m.group(1), base)

FIXES = []
total_fail = 0
newcodes = {}


def strip_nested_comments(s):
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", "", s, flags=re.S)
    return s


for name, cat in FILES:
    path = os.path.join(cat, name + ".st")
    if not os.path.exists(path):
        print("%-32s MISSING" % name)
        total_fail += 1
        continue
    s = io.open(path, encoding="utf-8").read()
    lines = s.splitlines()
    fails = []
    res = strip_nested_comments(s)
    for tok in ["GVL", "VAR_EXTERNAL", "VAR_GLOBAL"]:
        if re.search(r"\b" + tok + r"\b", res):
            fails.append("banned " + tok)
    if re.search(r"%[IQM][XBWDL]?\d", res):
        fails.append("physical addr")
    if re.search(r"\bg_[A-Za-z]", res):
        fails.append("global g_*")
    if "(*" in res or "*)" in res:
        fails.append("nested/unpaired comment")
    for ph in ["TODO", "FIXME", "......", "同上", "同前", "见上", "待补", "<...>", "ditto", "idem", "etc..."]:
        if ph in s:
            fails.append("placeholder " + ph)
    is_fc = name.startswith("FC_")
    is_iface = name.startswith("I_")
    opener = "FUNCTION" if is_fc else "FUNCTION_BLOCK"
    endt = "END_FUNCTION" if is_fc else "END_FUNCTION_BLOCK"
    sc = strip_nested_comments(s)
    n_open = len(re.findall(r"^" + opener + r"\s", sc, re.M))
    n_close = sc.count(endt)
    if not is_iface and (n_open != 1 or n_close != n_open):
        fails.append("terminator pair %d/%d" % (n_open, n_close))
    tail = [l for l in sc.splitlines() if l.strip()]
    if not is_iface and (not tail or tail[-1].strip() != endt):
        fails.append("terminator not last line")
    n_type = len(re.findall(r"\bTYPE\s+\w+\s*:", s))
    n_endtype = len(re.findall(r"\bEND_TYPE\b", s))
    if n_type != n_endtype:
        fails.append("TYPE pair %d/%d" % (n_type, n_endtype))
    body_nc = re.sub(r"//[^\n]*", "", res)
    for m in ENUM_RE.finditer(body_nc):
        body = m.group(2)
        for chunk in body.split(","):
            if ":" in chunk.replace(":=", ""):
                fails.append("enum %s single colon" % m.group(1))
                break
        members = []
        for chunk in body.split(","):
            mm = re.match(r"\s*([A-Za-z_]\w*)", chunk)
            if mm:
                members.append(mm.group(1))
        for mem in members:
            if not (re.search(r"\b" + re.escape(mem) + r"\s*:", body_nc)
                    or re.search(r"\.\s*" + re.escape(mem) + r"\b", body_nc)):
                fails.append("enum %s member %s no CASE label" % (m.group(1), mem))
    for m in re.finditer(r"TYPE\s+(\w+)\s*:", res):
        en = m.group(1)
        if en in old_enum_owners and en not in EXEMPT_ENUM_OWNERS:
            fails.append("enum owner clash %s=%s" % (en, old_enum_owners[en]))
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+[\w.]+\s+OF", l, re.I):
            seg = "\n".join(lines[i - 1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"\bELSE\b", block, re.I):
                fails.append("L%d CASE without ELSE" % i)
    bi = sum(1 for l in lines if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{2,}", l))
    if bi < 5:
        fails.append("bilingual too few: %d" % bi)
    if not re.search(r"防御性实现|clean-room|clean room", s):
        fails.append("missing provenance tag")
    if "VAR_OUTPUT" not in s and not is_iface:
        fails.append("missing VAR_OUTPUT")
    declared = set()
    for m in re.finditer(r"(VAR(?:_INPUT|_OUTPUT|_IN_OUT)?)\b(.*?)(?:END_VAR)", s, re.S):
        for dm in re.finditer(r"^\s*([A-Za-z_]\w*)\s*:", m.group(2), re.M):
            declared.add(dm.group(1))
    declared.add(name)
    balance = 0
    for i, l in enumerate(lines, 1):
        at_start = balance > 0
        balance += l.count("(") - l.count(")")
        if at_start or balance > 0:
            continue
        am = re.match(r"\s*([A-Za-z_]\w*)\s*:=", l)
        if am and am.group(1) not in declared:
            fails.append("L%d assign target undeclared: %s" % (i, am.group(1)))
    for i, l in enumerate(lines, 1):
        if re.fullmatch(r"\s*;\s*", l):
            fails.append("L%d bare semicolon" % i)
    seen = []
    for m in CODE_RE.finditer(s):
        u = m.group(0).upper()
        if u == "16#0000_0000":
            continue
        if u not in seen:
            seen.append(u)
    expect = 4 if is_fc else 5
    if not is_iface and not (2 <= len(seen) <= expect):
        fails.append("code slots=%d (expect<=%d)" % (len(seen), expect))
    newcodes[name] = seen
    clash = [c for c in seen if c in oldcodes]
    if clash:
        fails.append("code clash %s" % [(c, oldcodes[c]) for c in clash])
    if is_fc:
        if not re.search(r"\bFUNCTION\s+" + re.escape(name) + r"\b", s):
            fails.append("FC_ file without matching FUNCTION name")
        if "FUNCTION_BLOCK" in s:
            fails.append("FC_ file contains FUNCTION_BLOCK")
    else:
        if not re.search(r"FUNCTION_BLOCK\s+" + re.escape(name) + r"\b", s):
            fails.append("FB_ file without matching FUNCTION_BLOCK name")
    total_fail += len(fails)
    print("%-32s %-12s %4dL %d codes %s" % (name, cat, len(lines), len(seen),
          "PASS" if not fails else "FAIL: " + "; ".join(fails)))

allc = [c for v in newcodes.values() for c in v]
dup = sorted(c for c in set(allc) if allc.count(c) > 1)
if dup:
    total_fail += len(dup)
    print("INTRA-ROUND DUP:", dup)
print("\nsummary: fail=%d intra_dup=%d files=%d total_lines=%d" % (
    total_fail, len(dup), len(newcodes),
    sum(len(io.open(os.path.join(c, n + ".st"), encoding="utf-8").read().splitlines())
        for n, c in FILES if os.path.exists(os.path.join(c, n + ".st")))))
json.dump({"codes": newcodes, "fails": total_fail},
          io.open(os.path.join(STAGE, "_check_r32_result.json"), "w", encoding="utf-8"), indent=1)
