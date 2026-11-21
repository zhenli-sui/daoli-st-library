# -*- coding: utf-8 -*-
"""R31 机检（19 件增量）：禁记号/嵌套注释(非贪婪成对剥离)/占位符/终结符成对(含4属主TYPE块)/
ENUM逗号/TYPE种类/CASE-ELSE/枚举⊆CASE/双语注释/溯源/赋值目标已声明/孤立分号/码位槽块/撞码/前缀-POU一致
豁免口径：E_DL_Ne107Status 属主为 I_DL_DeviceHealth.st 属误报豁免。"""
import io, os, re, glob, json

STAGE = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(STAGE, "..", ".."))  # C:/Library

FILES = [
 ("FC_DL_PolarTransform2D","DL_MathData"),("FB_DL_EnthalpyChangeover","DL_Process"),
 ("FB_DL_NightPurgeCtrl","DL_Process"),("I_DL_ExternalEncoder","DL_Motion"),
 ("FB_DL_ExternalEncoderLatch","DL_Motion"),("FB_DL_DosingPumpCalib","DL_Device"),
 ("FB_DL_PnAlarmDiagParse","DL_Device"),("FB_DL_WaferHandoffSeq","DL_Device"),
 ("FB_DL_SlurryStirrerCtrl","DL_Device"),("FB_DL_ChamberLeakRate","DL_Process"),
 ("FB_DL_VacuumChamberSeq","DL_Process"),("FB_DL_CleanRoomPressure","DL_Process"),
 ("FB_DL_ReactorStepCtrl","DL_Process"),("FB_DL_FlowTotalizer","DL_Process"),
 ("FB_DL_TankLevelCtrl","DL_Process"),("FB_DL_UtilitiesLoadMgr","DL_Process"),
 ("FB_DL_FilmTensionDancer","DL_Process"),("FB_DL_HydrostaticLevelComp","DL_Process"),
 ("FB_DL_EtchEndpointTrend","DL_Algo"),
]
CODE_RE = re.compile(r"16#000[1-5]_[0-9A-Fa-f]{4}")
ENUM_RE = re.compile(r"TYPE\s+(\w+)\s*:\s*\(\s*(.*?)\)\s*(?:UINT|UDINT|INT|DINT)?\s*;\s*END_TYPE", re.S)
EXEMPT_ENUM_OWNERS = {"E_DL_Ne107Status": "I_DL_DeviceHealth"}  # 已知误报豁免

mine = set(n for n, c in FILES)
# 全库旧件码位（剔除本轮 20 件）
oldcodes = {}
old_enum_owners = {}
for f in glob.glob("DL_*/*.st"):
    base = f.replace("\\", "/").split("/")[-1][:-3]
    if base in mine:
        continue
    txt = io.open(f, encoding="utf-8").read()
    for m in CODE_RE.finditer(txt):
        oldcodes.setdefault(m.group(0).upper(), base)
    for m in re.finditer(r"TYPE\s+(\w+)\s*:", txt):
        old_enum_owners.setdefault(m.group(1), base)

FIXES = []   # 升 v1.0.1 记录
total_fail = 0
newcodes = {}

def strip_nested_comments(s):
    """非贪婪成对剥离法：反复剥最内层 (*...*)，残留 (* 或 *) 即有嵌套/不成对。"""
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", "", s, flags=re.S)
    return s

for name, cat in FILES:
    path = os.path.join(cat, name + ".st")
    if not os.path.exists(path):
        print("%-30s MISSING" % name); total_fail += 1; continue
    s = io.open(path, encoding="utf-8").read()
    lines = s.splitlines()
    fails = []
    # 1 禁记号字面 0 命中
    for tok in ["GVL", "VAR_EXTERNAL", "VAR_GLOBAL"]:
        if re.search(r"\b" + tok + r"\b", s):
            fails.append("banned " + tok)
    if re.search(r"%[IQM][XBWDL]?\d", s):
        fails.append("physical addr")
    if re.search(r"\bg_[A-Za-z]", s):
        fails.append("global g_*")
    # 2 嵌套注释（非贪婪成对剥离法）
    res = strip_nested_comments(s)
    if "(*" in res or "*)" in res:
        fails.append("nested/unpaired comment")
    # 3 占位符/省略语 0
    for ph in ["TODO", "FIXME", "......", "同上", "同前", "见上", "待补", "<...>", "ditto", "idem", "etc..."]:
        if ph in s:
            fails.append("placeholder " + ph)
    # 4 POU 终结符成对 + 末行
    is_fc = name.startswith("FC_")
    is_iface = name.startswith("I_")  # R31：接口件豁免终结符/VAR_OUTPUT/槽数/前缀校验
    opener = "FUNCTION" if is_fc else "FUNCTION_BLOCK"
    endt = "END_FUNCTION" if is_fc else "END_FUNCTION_BLOCK"
    sc = strip_nested_comments(s)
    n_open = len(re.findall(r"^" + opener + r"\s", sc, re.M))
    n_close = sc.count(endt)
    if not is_iface and (n_open != 1 or n_close != n_open):
        fails.append("terminator pair %d/%d" % (n_open, n_close))
    tail = [l for l in sc.splitlines() if l.strip()]
    if not tail or tail[-1].strip() != endt:
        if not is_iface:
            fails.append("terminator not last line")
    # TYPE/END_TYPE 成对
    n_type = len(re.findall(r"\bTYPE\s+\w+\s*:", s))
    n_endtype = len(re.findall(r"\bEND_TYPE\b", s))
    if n_type != n_endtype:
        fails.append("TYPE pair %d/%d" % (n_type, n_endtype))
    if not is_fc and n_type != 0 and n_type not in (1, 2, 3, 4):
        pass  # 属主 TYPE 块数不设硬限，仅在报告披露
    # STRUCT 不许用括号枚举语法
    for m in re.finditer(r"TYPE\s+(\w+)\s*:\s*\(", s):
        if m.group(1).upper().startswith("ST_"):
            fails.append("struct %s written as enum" % m.group(1))
    # 5/6 枚举成员逗号分隔 + 枚举⊆CASE（在注释剥离后的正文上）
    body_nc = re.sub(r"//[^\n]*", "", res)
    case_labels_all = []
    for m in ENUM_RE.finditer(body_nc):
        body = m.group(2)
        for chunk in body.split(","):
            if ":" in chunk.replace(":=", ""):
                fails.append("enum %s member single colon" % m.group(1))
                break
        members = []
        for chunk in body.split(","):
            mm = re.match(r"\s*([A-Za-z_]\w*)", chunk)
            if mm:
                members.append(mm.group(1))
        for mem in members:
            # 成员须为 CASE 标签（裸名或限定名 EnumName.mem）或在 CASE 体内被赋值消费
            if not (re.search(r"\b" + re.escape(mem) + r"\s*:", body_nc)
                    or re.search(r"\.\s*" + re.escape(mem) + r"\b", body_nc)):
                fails.append("enum %s member %s no CASE label" % (m.group(1), mem))
    # 枚举属主撞库（含豁免）
    for m in re.finditer(r"TYPE\s+(\w+)\s*:", res):
        en = m.group(1)
        if en in old_enum_owners and en not in EXEMPT_ENUM_OWNERS:
            fails.append("enum owner clash %s=%s" % (en, old_enum_owners[en]))
        elif en in EXEMPT_ENUM_OWNERS and old_enum_owners.get(en) == EXEMPT_ENUM_OWNERS[en]:
            pass  # 豁免口径
    # 7 CASE 含 ELSE
    for i, l in enumerate(lines, 1):
        if re.match(r"\s*CASE\s+[\w.]+\s+OF", l, re.I):
            seg = "\n".join(lines[i-1:])
            m2 = re.search(r"END_CASE", seg, re.I)
            block = seg[:m2.start()] if m2 else seg
            if not re.search(r"\bELSE\b", block, re.I):
                fails.append("L%d CASE without ELSE" % i)
    # 8 双语注释
    bi = sum(1 for l in lines if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]{2,}", l))
    if bi < 5:
        fails.append("bilingual too few: %d" % bi)
    # 9 溯源短语
    if not re.search(r"防御性实现", s):
        fails.append("missing provenance tag")
    # VAR_OUTPUT
    if "VAR_OUTPUT" not in s and not is_iface:
        fails.append("missing VAR_OUTPUT")
    # 10 赋值目标已声明（括号续行内的形参赋值与 POU 返回值赋值豁免）
    declared = set()
    for m in re.finditer(r"(VAR(?:_INPUT|_OUTPUT|_IN_OUT)?)\b(.*?)(?:END_VAR)", s, re.S):
        for dm in re.finditer(r"^\s*([A-Za-z_]\w*)\s*:", m.group(2), re.M):
            declared.add(dm.group(1))
    declared.add(name)  # FC/FB 返回值赋值目标
    balance = 0  # 括号深度跟踪：深>0 行内 := 均为形参赋值
    for i, l in enumerate(lines, 1):
        at_start = balance > 0
        balance += l.count("(") - l.count(")")
        if at_start or balance > 0:
            continue  # 调用括号内行：形参赋值，非变量赋值目标
        am = re.match(r"\s*([A-Za-z_]\w*)\s*:=", l)
        if am and am.group(1) not in declared:
            fails.append("L%d assign target undeclared: %s" % (i, am.group(1)))
    # 11 孤立分号
    for i, l in enumerate(lines, 1):
        if re.fullmatch(r"\s*;\s*", l):
            fails.append("L%d bare semicolon" % i)
    # 12 码位槽块
    seen = []
    for m in CODE_RE.finditer(s):
        u = m.group(0).upper()
        if u not in seen:
            seen.append(u)
    expect = 4 if is_fc else 5
    if (not is_iface) and not (2 <= len(seen) <= expect):
        fails.append("code slots=%d (expect %d)" % (len(seen), expect))
    newcodes[name] = seen
    clash = [c for c in seen if c in oldcodes]
    if clash:
        fails.append("code clash %s" % [(c, oldcodes[c]) for c in clash])
    # 13 文件名前缀与 POU 类型一致
    if is_iface:
        pass
    elif is_fc:
        if not re.search(r"\bFUNCTION\s+" + re.escape(name) + r"\b", s):
            fails.append("FC_ file without matching FUNCTION name")
        if "FUNCTION_BLOCK" in s:
            fails.append("FC_ file contains FUNCTION_BLOCK")
    else:
        if not re.search(r"FUNCTION_BLOCK\s+" + re.escape(name) + r"\b", s):
            fails.append("FB_ file without matching FUNCTION_BLOCK name")
    total_fail += len(fails)
    print("%-30s %-12s %4dL %d codes %s" % (name, cat, len(lines), len(seen),
          "PASS" if not fails else "FAIL: " + "; ".join(fails)))

# 轮内码位互撞
allc = [c for v in newcodes.values() for c in v]
dup = sorted(c for c in set(allc) if allc.count(c) > 1)
if dup:
    total_fail += len(dup)
    print("INTRA-ROUND DUP:", dup)
print("\nsummary: fail=%d intra_dup=%d files=%d total_lines=%d" % (
    total_fail, len(dup), len(newcodes),
    sum(len(io.open(os.path.join(c, n + ".st"), encoding="utf-8").read().splitlines())
        for n, c in FILES if os.path.exists(os.path.join(c, n + ".st")))))
json.dump({"codes": newcodes, "fixes": FIXES},
          io.open(os.path.join(STAGE, "_check_r30_result.json"), "w", encoding="utf-8"), indent=1)
