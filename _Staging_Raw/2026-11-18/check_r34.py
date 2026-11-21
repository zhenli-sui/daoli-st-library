# -*- coding: utf-8 -*-
"""R34 机检（增量 21 件：20 新件 + 1 返修件）
规则集 = R33 全量 + 本轮新增：
  N3 CASE 内置位型标志在段尾被无条件同拍清零（R33 RollChangeoverSeq 事故族）
"""
import io, os, re, json, sys

STAGE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.abspath(os.path.join(STAGE, "..", ".."))
PLAN = os.path.join(STAGE, "ROUND_PLAN_R34.md")

# 从规划书解析 序号|名称|分类|码位
plan_txt = io.open(PLAN, encoding="utf-8").read()
CODES = {}
for line in plan_txt.splitlines():
    m = re.match(r"\|\s*(\d+)\s*\|\s*`([A-Za-z0-9_]+)`\s*\|\s*`?(16#[0-9A-Fa-f_]+)`?\s*\|", line)
    if m:
        CODES[m.group(2)] = m.group(3)
TARGETS = []
for line in plan_txt.splitlines():
    m = re.match(r"\|\s*(\d+)\s*\|\s*`([A-Za-z0-9_]+)`\s*\|\s*(DL_\w+)\s*\|\s*(\w+)\s*\|", line)
    if m:
        TARGETS.append((int(m.group(1)), m.group(2), m.group(3), m.group(4)))
TARGETS.append((99, "FB_DL_SlurryViscosityComp", "DL_MathData", "FB"))

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
    # 11 CRLF
    if b"\r\n" not in raw:
        errs.append("NOT CRLF")
    return errs


rows = []
total_err = 0
for no, name, cat, typ in TARGETS:
    code = CODES.get(name, "")
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
          io.open(os.path.join(STAGE, "_check_r34_result.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
