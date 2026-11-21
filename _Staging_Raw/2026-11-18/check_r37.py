# -*- coding: utf-8 -*-
"""R34 机检（增量 21 件：20 新件 + 1 返修件）
规则集 = R33 全量 + 本轮新增：
  N3 CASE 内置位型标志在段尾被无条件同拍清零（R33 RollChangeoverSeq 事故族）
"""
import io, os, re, json, sys, glob

STAGE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.abspath(os.path.join(STAGE, "..", ".."))
PLAN = os.path.join(STAGE, "DISPATCH_R37.md")

TARGETS = [
 (4,"FB_DL_ResonanceTrackNotch","DL_Algo","16#02_3_82"),
 (5,"FB_DL_LineShaftClutch","DL_Motion","16#04_0_A2"),
 (6,"FB_DL_FlyingCutSync","DL_Motion","16#04_0_A3"),
 (7,"FB_DL_WaferCoolChuck","DL_Device","16#03_2_0B"),
 (8,"FB_DL_CurtainEFEMZone","DL_Device","16#03_2_0C"),
 (9,"FB_DL_VentPurgeDuty","DL_Device","16#03_2_0D"),
 (10,"FB_DL_SlurryLevelBank","DL_Device","16#03_2_0E"),
 (11,"FB_DL_FoupPurgeN2Flow","DL_Device","16#03_2_0F"),
 (12,"FB_DL_CartonErectVacMonitor","DL_Device","16#03_2_10"),
 (13,"FB_DL_CoderRibbonLife","DL_Device","16#03_2_11"),
]
CODES = {t[1]: t[3] for t in TARGETS}

BANNED = [r"\bVAR_EXTERNAL\b", r"\bGVL\b", r"%[IQM][XBWDL]?\d", r"\bORD\s*\(",
          r"\bCHR\s*\(", r"__ISVALIDREF", r"\bREF\s*="]
PLACEHOLDER = [r"\bTODO\b", r"\bFIXME\b", r"CHR\?", r"\.\.\.\s*$"]


def strip_comments(t):
    t = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    return t


def check(name, cat, code):
    p = os.path.join(LIB, cat, name + ".st")
    if not os.path.exists(p):
        return ["MISSING FILE"]
    raw = io.open(p, "rb").read()
    txt = raw.decode("utf-8", "replace")
    body = strip_comments(txt)
    errs = []
    # 1 禁记号（正文）
    for b in BANNED:
        for m in re.finditer(b, body):
            errs.append("BANNED %s @%d" % (b, body[:m.start()].count("\n") + 1))
    # 2 占位符（全文）
    for b in PLACEHOLDER:
        if re.search(b, txt, flags=re.M):
            errs.append("PLACEHOLDER %s" % b)
    # 3 POU 终结符
    if not re.search(r"^\s*END_FUNCTION_BLOCK\b", body, re.M) and not re.search(r"^\s*END_FUNCTION\b", body, re.M):
        errs.append("NO POU TERMINATOR")
    # 4 TYPE 块种类
    for m in re.finditer(r"TYPE\s+(\w+)\s*:\s*(.*?)END_TYPE", body, flags=re.S):
        blk = m.group(2)
        if "END_STRUCT" in blk and re.search(r"TYPE\s+\w+\s*:\s*\(", body):
            errs.append("STRUCT AS ENUM PAREN %s" % m.group(1))
        if blk.count("STRUCT") != blk.count("END_STRUCT"):
            errs.append("STRUCT PAIR MISMATCH %s" % m.group(1))
    # 5 ENUM 成员单冒号
    for m in re.finditer(r"TYPE\s+\w+\s*:\s*\(([^)]*)\)", body, flags=re.S):
        for mem in m.group(1).split(","):
            if re.search(r":(?!s*=)", mem):   # 单冒号才是缺陷；":=" 带值为库内惯例
                errs.append("ENUM COLON %s" % mem.strip()[:24])
    # 6 CASE 必带 ELSE
    ncase = len(re.findall(r"^\s*CASE\b", body, re.M))
    nelse = len(re.findall(r"^\s*ELSE\s*$", body, re.M))
    if ncase and nelse < ncase:
        errs.append("CASE WITHOUT ELSE ncase=%d nelse=%d" % (ncase, nelse))
    # 7 N1 定时器常真
    for m in re.finditer(r"\b(ton\w*|tof\w*)\s*\(\s*IN\s*:=\s*TRUE\s*\)", body, re.I):
        errs.append("N1 TIMER IN:=TRUE %s" % m.group(1))
    # 8 N2 CASE 内给输出枚举赋值
    outs = set()
    mvo = re.search(r"VAR_OUTPUT(.*?)END_VAR", body, flags=re.S)
    if mvo:
        for m in re.finditer(r"(\w+)\s*:\s*(E_DL_\w+)", mvo.group(1)):
            outs.add(m.group(1))
    if outs:
        for m in re.finditer(r"^\s*(%s)\s*:=" % "|".join(map(re.escape, outs)), body, re.M):
            line_no = body[:m.start()].count("\n") + 1
            # 是否落在 CASE...END_CASE 之间
            pre = body[:m.start()]
            # 只在真正的 CASE...END_CASE 区间内判（END_CASE 内含 CASE 子串，须用词边界）
            i_ec = pre.rfind("END_CASE")
            i_cs = max(pre.rfind("\nCASE "), pre.rfind("\nCASE\t"))
            if i_cs > -1 and i_cs > i_ec:
                errs.append("N2 OUTPUT ENUM IN CASE %s @%d" % (m.group(1), line_no))
    # 9 码位存在且匹配
    if code:
        if code.replace("16#", "16#") not in txt:
            errs.append("CODE SEGMENT NOT IN FILE (expect %s)" % code)
    # 10 双语注释率
    lines = [l for l in txt.splitlines() if l.strip()]
    bi = [l for l in lines if "//" in l and re.search(r"[\u4e00-\u9fff]", l) and re.search(r"[A-Za-z]", l.split("//", 1)[1])]
    decl = [l for l in lines if re.match(r"^\s*\w+\s*:\s*\w", l) and "//" in l]
    if decl and len(bi) < 0.5 * len(decl):
        errs.append("BILINGUAL LOW %d/%d" % (len(bi), len(decl)))
    # 12 溯源标签
    if "IEC 61131-3 标准语义的道莅防御性实现" not in txt:
        errs.append("NO SOURCE TRACE HEADER")
    # 13 码位重复（全库）
    if code:
        others = [x for x in DUPCODE.get(code.upper(), []) if x != name + ".st"]
        if others:
            errs.append("CODE DUP with %s" % ",".join(others))
    # 14 TON 自复位（周期节拍死锁风险，WARN 级）
    for m in re.finditer(r"(ton\w*)\s*\(", body, re.I):
        inst = m.group(1)
        if not re.search(r"%s\s*\.\s*IN\s*:=\s*FALSE" % inst, body, re.I) and not re.search(r"NOT\s+%s\s*\.\s*Q" % inst, body, re.I):
            errs.append("TON NO SELFRESET %s" % inst)
            break
    # 11 CRLF
    if b"\r\n" not in raw:
        errs.append("NOT CRLF")
    return errs


# 全库码位占用（含本批）
DUPCODE = {}
for f in glob.glob(os.path.join(LIB,"DL_*","*.st")):
    h = io.open(f,encoding="utf-8",errors="ignore").read(2000)
    m = re.search(r"16#([0-9A-Fa-f]{2})_([0-9A-Fa-f])_([0-9A-Fa-f]{2})", h)
    if m and "Code" in h[:2000]:
        key = m.group(0).upper()
        DUPCODE.setdefault(key, []).append(os.path.basename(f))

rows = []
total_err = 0
for no, name, cat, code in TARGETS:
    e = check(name, cat, code)
    if e:
        total_err += len(e)
    rows.append((no, name, cat, code, e))

print("=" * 72)
for no, name, cat, code, e in rows:
    print("%-3s %-32s %-12s %-12s %s" % (no, name, cat, code, "PASS" if not e else "FAIL"))
    for x in e:
        print("      - " + x)
print("=" * 72)
print("FILES=%d  FAIL=%d  ERRS=%d" % (len(rows), sum(1 for r in rows if r[4]), total_err))
json.dump([{"no": r[0], "name": r[1], "cat": r[2], "code": r[3], "errors": r[4]} for r in rows],
          io.open(os.path.join(STAGE, "_check_r37_result.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
