# -*- coding: utf-8 -*-
"""道莅代码库全库机检 R13 / LIBRARY MACHINE AUDIT R13
用法：
  python audit_library_r13.py                  # 全库 DL_*/*.st
  python audit_library_r13.py --files a.st b.st # 仅指定文件（canonical 路径或文件名）
  python audit_library_r13.py --rules case_else,undefined_identifier
  python audit_library_r13.py --rules r37_left_clamp,r38_dual_source,r39_pre_case_override,r40_ton_cross_segment
输出末行：SUMMARY: files=N fail=M warn=K  （机器可读；fail 只计 FAIL 级命中，WARN 单列不计入 fail）

十六条机检项（R12 的 12 项 + R13 新增 4 项）：
  1  banned_hits              禁用记号 GV L / VAR_EXTERNAL / VAR_GLOBAL / %I / %Q / %M 全文零命中
  2  placeholder              `// 略`、`// 同上`、TODO、FIXME、`...` 省略符
  3  terminator               POU 的 END_FUNCTION(_BLOCK) 配对且位于文件最后一个非空非注释行
  4  bilingual_comment        VAR 区每个变量行注释须中英双语
  5  case_else                每个 CASE 块须有 ELSE 兜底
  6  enum_case_completeness   文件内 ENUM 成员须被 CASE 标签集合覆盖（R31 / R10 致命缺陷型）
  7  enum_separator           ENUM 成员须 `:=` 赋值或纯列表，禁 `成员:` 畸形写法（R33）
  8  nested_comment           `(* ... *)` 内不得再出现 `(*`（R28）
  9  undefined_identifier     赋值目标/表达式标识符须已声明（R29 扩展，已降噪）
 10  single_colon_or_semicolon 孤立分号空语句（R26）
 11  line_count / char_count 规模统计（INFO）
 12  duplicate_pou_name      全库 POU 重名
 13  r37_left_clamp           定长串回夹：LEFT 自赋值 / 拼接无上界判定 / 截断标志死码（R37）
 14  r38_dual_source          锁存副本与实时镜像量双源（R38）
 15  r39_pre_case_override    CASE 前置停机分支屏蔽状态复位沿（R39）
 16  r40_ton_cross_segment    分段监控定时器 IN 跨段恒真（R40）

—— R12 收紧口径（针对存量 168 件的噪声控制，逐条记录）——
  [R29 undefined_identifier]
    a) 只检查「标识符根」，`a.b` / `a^.b` 中的 b 一律不查（成员访问右侧不可静态判定）。
    b) 函数/FB/方法调用名（后紧跟 `(`）不查；调用括号内 `形参 :=` / `形参 =>` 不查。
    c) 全大写标识符不查（类型名、常量、枚举成员、IEC 类型转换函数的混淆源）。
    d) 类型转换/标准函数按白名单 `*_TO_*` 与 BUILTIN 表放行。
    e) 注释文本、字符串、数值/时间/十六进制字面量先置空，不参与扫描。
    f) METHOD/PROPERTY 体内的 `SELF.` / `THIS^.` 前缀剥离后再判根。
  [R31 enum_case_completeness]
    仅对「被 CASE 选择子实际使用」的 ENUM 判覆盖；未被 CASE 引用的 ENUM（纯状态输出枚举、
    报警码枚举）不判，避免把「枚举+IF」写法误判为缺陷。CASE 标签取文件级并集（同一 ENUM
    允许拆成多个 CASE 分支块，并集覆盖即 PASS）。
  [R5 case_else]
    以块栈解析，ELSE 必须与 CASE 同层；ELSIF 不计 ELSE；嵌套 IF 的 ELSE 不会被误算到外层 CASE。
  [R4 bilingual_comment]
    只看「含 `:` 且带 `//` 注释」的声明行；纯注释行、空行、`END_VAR` 跳过；英文判定要求
    注释中出现 ≥2 个连续 ASCII 字母，避免单个 `x` 轴符号误判为英文。
  [R2 placeholder]
    `...` 仅在「非数值上下文」判定（排除 `0...9` 之类误配）；中文省略号 `…` 不算违规。

—— R13 新增 R37~R40 口径（分级：确定性 = FAIL，启发式 = WARN）——
  [R37 r37_left_clamp]
    r37.1 LEFT 自赋值回夹（同一变量既作源又作目标）           → FAIL（确定性）
    r37.2 出现 CONCAT(/INSERT( 但全文无 LEN( 与上界的比较      → WARN（启发式：上界判定可能在调用方）
    r37.3 声明了 Truncated/Overflow 类标志且仅有 := FALSE 赋值 → FAIL（确定性：标志恒假）
    剥离注释与字符串字面量后再匹配；只读 LEFT（不写回原变量）不报。
  [R38 r38_dual_source]
    r38.a 同基名「锁存量 LEN(xLatched)」与「实时量 LEN(x)」并存 → FAIL（A-D02 指纹）
    r38.b 镜像量（*Live/*Real/*Raw）有效引用 > 3 次            → WARN（需人工指出唯一消费点）
    声明行不计引用数；实时量仅做 <> 不等比较视为变化检测，合法。
  [R39 r39_pre_case_override]
    CASE 紧邻前置的 IF 块内把状态强置空闲类枚举，且条件未显式排除故障态 → FAIL；
    块内同时清码（uErrorId := 0 且 bError := FALSE）或已含 bReset 沿判据 → 降 WARN / 豁免。
  [R40 r40_ton_cross_segment]
    TON/TOF 的 IN 根变量：全文被置 TRUE、从未被置 FALSE、且所在 CASE 有段推进写 → 跨段恒真；
    实例名含 Watch/Step/Seg/Phase → FAIL，其余 → WARN；IN 含 NOT xxxBreak 或纯比较式 → 豁免。
返回码：0 = 无 FAIL，1 = 有 FAIL，2 = 参数错误。
"""
import re, sys, os, io, glob, json, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

LIB = r"C:\Library"
CATS = ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]

ALL_RULES = ["banned_hits", "placeholder", "terminator", "bilingual_comment", "case_else",
             "enum_case_completeness", "enum_separator", "nested_comment",
             "undefined_identifier", "single_colon_or_semicolon", "line_count", "duplicate_pou_name",
             "r37_left_clamp", "r38_dual_source", "r39_pre_case_override", "r40_ton_cross_segment"]

KW = {"IF", "THEN", "ELSE", "ELSIF", "END_IF", "CASE", "OF", "END_CASE", "FOR", "TO", "BY",
      "END_FOR", "WHILE", "DO", "END_WHILE", "REPEAT", "UNTIL", "END_REPEAT", "EXIT",
      "RETURN", "CONTINUE", "AND", "OR", "XOR", "NOT", "MOD", "TRUE", "FALSE",
      "FUNCTION", "FUNCTION_BLOCK", "END_FUNCTION", "END_FUNCTION_BLOCK", "PROGRAM",
      "METHOD", "END_METHOD", "PROPERTY", "END_PROPERTY", "VAR", "VAR_INPUT", "VAR_OUTPUT",
      "VAR_IN_OUT", "VAR_TEMP", "VAR_STAT", "VAR_CONSTANT", "VAR_RETAIN", "VAR_PERSISTENT",
      "END_VAR", "TYPE", "END_TYPE", "STRUCT", "END_STRUCT", "ARRAY", "OF", "AT", "RETAIN",
      "PERSISTENT", "CONSTANT", "THIS", "SUPER", "SELF", "REFERENCE", "POINTER", "INTERFACE",
      "IMPLEMENTS", "EXTENDS", "PUBLIC", "PRIVATE", "PROTECTED", "INTERNAL", "ABSTRACT",
      "FINAL", "OVERRIDE", "ACTION", "END_ACTION", "JMP", "GOTO", "NULL"}

# 标准函数 / 类型转换白名单（Standard.library + 常用运算符函数）
BUILTIN = {
    "ABS", "SQRT", "LN", "LOG", "EXP", "EXPT", "SIN", "COS", "TAN", "ASIN", "ACOS", "ATAN",
    "ATAN2", "TRUNC", "ROUND", "LIMIT", "MIN", "MAX", "SEL", "MUX", "MOVE", "SHL", "SHR",
    "ROL", "ROR", "ADR", "SIZEOF", "MEMCPY", "MEMSET", "XOR", "NOT", "AND", "OR",
    "R_TRIG", "F_TRIG", "TON", "TOF", "TP", "CTU", "CTD", "CTUD", "SR", "RS", "BLINK",
}
CONV_RE = re.compile(r"^(?:[A-Z][A-Z0-9]*_)+TO_(?:[A-Z][A-Z0-9]*_?)+$")

# IEC 61131-3 基础数据类型（全大写，理论上已被 toUpperCase 放行，显式列出便于阅读）
DATA_TYPES = {"BOOL", "SINT", "INT", "DINT", "LINT", "USINT", "UINT", "UDINT", "ULINT",
              "BYTE", "WORD", "DWORD", "LWORD", "REAL", "LREAL", "TIME", "LTIME", "DATE",
              "LDATE", "TOD", "TODT", "DT", "LDT", "STRING", "WSTRING", "CHAR", "WCHAR",
              "ANY", "ANY_NUM", "ANY_INT", "ANY_REAL", "ANY_BIT", "ANY_STRING", "ANY_DATE"}


# ----------------------------------------------------------------------------- 基础清洗
def strip_comments(text):
    """注释置空（保留换行与长度），同时记录注释区间以支持嵌套检测"""
    out, i, n, depth = [], 0, len(text), 0
    while i < n:
        if depth == 0 and text.startswith("(*", i):
            depth, i = 1, i + 2
            out.append("  ")
            continue
        if depth > 0:
            if text.startswith("(*", i):
                depth, i = depth + 1, i + 2
                out.append("  ")
                continue
            if text.startswith("*)", i):
                depth, i = depth - 1, i + 2
                out.append("  ")
                continue
            out.append("\n" if text[i] == "\n" else " ")
            i += 1
            continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def strip_pragmas(code):
    """{attribute 'x'} 之类编译指示整体置空"""
    return re.sub(r"\{[^}]*\}", lambda m: " " * len(m.group(0)), code)


def blank_literals(code):
    """字符串与数值/时间/十六进制字面量置空，避免 token 化误判"""
    code = re.sub(r"'[^'\n]*'", lambda m: " " * len(m.group(0)), code)
    code = re.sub(r'"[^"\n]*"', lambda m: " " * len(m.group(0)), code)
    code = re.sub(r"\b[A-Za-z_]\w*#[\w.#+\-]*", lambda m: " " * len(m.group(0)), code)   # T#1S / 16#0002_0001 / INT#5
    code = re.sub(r"\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b", lambda m: " " * len(m.group(0)), code)
    return code


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


# ----------------------------------------------------------------------------- 结构解析
VAR_OPEN = re.compile(r"^\s*(VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR_TEMP|VAR_STAT|VAR_CONSTANT|VAR_RETAIN|VAR_PERSISTENT|VAR)\b")


def var_regions(code_lines):
    """返回 [(start_idx, end_idx)]（0-based，含 END_VAR 行）与逐行是否在 VAR 区内"""
    regions, inside, start = [], False, 0
    for i, ln in enumerate(code_lines):
        if not inside and VAR_OPEN.match(ln):
            inside, start = True, i
            continue
        if inside and re.match(r"^\s*END_VAR\b", ln):
            regions.append((start, i))
            inside = False
    if inside:
        regions.append((start, len(code_lines) - 1))
    return regions


def mask_regions(lines, regions):
    out = list(lines)
    for s, e in regions:
        for i in range(s, min(e + 1, len(out))):
            out[i] = ""
    return out


def parse_decls(code):
    """收集声明标识符、类型映射、ENUM 定义"""
    lines = code.splitlines()
    regions = var_regions(lines)
    names, vartype = set(), {}
    for s, e in regions:
        body = " ".join(lines[s + 1:e])
        for stmt in body.split(";"):
            stmt = stmt.strip()
            if not stmt or ":" not in stmt:
                continue
            head, _, tail = stmt.partition(":")
            if head.strip().upper().startswith(("VAR", "END_VAR")):
                continue
            ty = re.split(r":=", tail)[0].strip()
            ty = re.sub(r"\b(AT\s+\S+)\b", "", ty).strip()
            for nm in re.split(r"[,\s]+", head.strip()):
                nm = nm.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", nm or ""):
                    names.add(nm)
                    vartype[nm] = ty.split("[")[0].strip()
    # POU / 方法 / 属性名
    for m in re.finditer(r"^\s*(?:FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY|INTERFACE)\s+([A-Za-z_]\w*)",
                         code, re.MULTILINE):
        names.add(m.group(1))
    # ENUM 定义
    enums = {}
    for m in re.finditer(r"\bTYPE\s+([A-Za-z_]\w*)\s*:\s*(?:\(([^;]*?)\)|(STRUCT)\b(.*?)\bEND_STRUCT)",
                         code, re.DOTALL):
        nm, body = m.group(1), m.group(2)
        if body is not None:
            members = re.findall(r"([A-Za-z_]\w*)\s*(?::=|\s*:)\s*[^,)]*", body)
            if not members:
                members = re.findall(r"([A-Za-z_]\w*)", body)
            enums[nm] = members
            names.update(members)
        else:
            for f in re.findall(r"^\s*([A-Za-z_]\w*)\s*:", m.group(4) or "", re.MULTILINE):
                names.add(f)
    return names, vartype, enums, regions


# ----------------------------------------------------------------------------- 规则实现
def r_banned(text):
    hits = []
    pats = [("GVL", re.compile(r"\bGVL\b", re.I)),
            ("VAR_EXTERNAL", re.compile(r"\bVAR_EXTERNAL\b", re.I)),
            ("VAR_GLOBAL", re.compile(r"\bVAR_GLOBAL\b", re.I)),
            ("%I", re.compile(r"%[Ii](?=[0-9XBWDL])")),
            ("%Q", re.compile(r"%[Qq](?=[0-9XBWDL])")),
            ("%M", re.compile(r"%[Mm](?=[0-9XBWDL])"))]
    for label, p in pats:
        for m in p.finditer(text):
            hits.append((line_of(text, m.start()), label, text.splitlines()[line_of(text, m.start()) - 1].strip()[:70]))
    return hits


def r_placeholder(text):
    hits = []
    lines = text.splitlines()
    pats = [("// 略", re.compile(r"//\s*略")), ("// 同上", re.compile(r"//\s*同上")),
            ("TODO", re.compile(r"\bTODO\b")), ("FIXME", re.compile(r"\bFIXME\b"))]
    for label, p in pats:
        for m in p.finditer(text):
            hits.append((line_of(text, m.start()), label, lines[line_of(text, m.start()) - 1].strip()[:70]))
    # 省略符 ...（排除数值上下文 0..1 / 1...2）
    for m in re.finditer(r"\.\.\.", text):
        s, e = m.start(), m.end()
        prev = text[s - 1] if s > 0 else ""
        nxt = text[e] if e < len(text) else ""
        if prev.isdigit() or nxt.isdigit():
            continue
        hits.append((line_of(text, s), "省略符 ...", lines[line_of(text, s) - 1].strip()[:70]))
    return sorted(set(hits))


def r_terminator(text, code):
    """POU / INTERFACE 头部 → 终结符配对；终结符必须是文件最后一个非空代码行"""
    clines = code.splitlines()
    hits = []
    heads = [(i + 1, m.group(1), m.group(2)) for i, l in enumerate(clines)
             for m in [re.match(r"^\s*(FUNCTION_BLOCK|FUNCTION)\s+([A-Za-z_]\w*)", l)] if m]
    ifaces = [(i + 1, m.group(1)) for i, l in enumerate(clines)
              for m in [re.match(r"^\s*INTERFACE\s+([A-Za-z_]\w*)", l)] if m]
    if not heads and not ifaces:
        return [(1, "未检测到 POU / INTERFACE 头部（无 FUNCTION / FUNCTION_BLOCK / INTERFACE）")]
    ends = collections.Counter()
    for l in clines:
        mm = re.match(r"^\s*(END_FUNCTION_BLOCK|END_FUNCTION|END_INTERFACE)\b", l)
        if mm:
            ends[mm.group(1)] += 1
    need_fb = sum(1 for _, k, _ in heads if k == "FUNCTION_BLOCK")
    need_f = sum(1 for _, k, _ in heads if k == "FUNCTION")
    if ends["END_FUNCTION_BLOCK"] < need_fb:
        hits.append((heads[0][0], f"FUNCTION_BLOCK 数 {need_fb} 与 END_FUNCTION_BLOCK 数 {ends['END_FUNCTION_BLOCK']} 不配对"))
    if ends["END_FUNCTION"] < need_f:
        hits.append((heads[0][0], f"FUNCTION 数 {need_f} 与 END_FUNCTION 数 {ends['END_FUNCTION']} 不配对"))
    if ifaces and ends["END_INTERFACE"] < len(ifaces):
        hits.append((ifaces[0][0], f"INTERFACE 数 {len(ifaces)} 与 END_INTERFACE 数 {ends['END_INTERFACE']} 不配对"))
    tail = [(i + 1, l) for i, l in enumerate(clines) if l.strip()]
    if tail:
        tl, txt = tail[-1]
        if not re.match(r"^\s*END_(?:FUNCTION_BLOCK|FUNCTION|INTERFACE)\b", txt):
            hits.append((tl, f"文件末尾非空行不是终结符：{txt.strip()[:60]}"))
    return hits


def r_bilingual(text, regions):
    """VAR 区内变量声明行须中英双语同行注释"""
    hits, lines = [], text.splitlines()
    cjk = re.compile(r"[\u4e00-\u9fff]")
    eng = re.compile(r"[A-Za-z]{2,}")
    for s, e in regions:
        for i in range(s + 1, e):
            raw = lines[i]
            st = raw.strip()
            if not st or st.startswith(("(*", "*", "//")):
                continue
            if "//" not in raw:
                hits.append((i + 1, "变量行缺注释（无 //）：" + st[:60]))
                continue
            decl, _, cmt = raw.partition("//")
            if ":" not in decl:
                continue
            if not cjk.search(cmt) or not eng.search(cmt):
                hits.append((i + 1, "注释非中英双语：" + st[:60]))
    return hits


def r_case_else(code):
    """块栈解析：CASE ... END_CASE 内同层必须有 ELSE"""
    hits, stack = [], []
    for i, ln in enumerate(code.splitlines(), 1):
        for m in re.finditer(r"\b(IF|ELSIF|ELSE|END_IF|CASE|END_CASE)\b", ln):
            t = m.group(1)
            if t == "IF":
                stack.append(["IF", False])
            elif t == "CASE":
                stack.append(["CASE", False, i])
            elif t == "ELSE":
                if stack:
                    stack[-1][1] = True
            elif t == "END_IF":
                if stack and stack[-1][0] == "IF":
                    stack.pop()
            elif t == "END_CASE":
                if stack and stack[-1][0] == "CASE":
                    kind, els, cl = stack.pop()
                    if not els:
                        hits.append((cl, f"CASE（第 {cl} 行开始）缺 ELSE 兜底"))
    return hits



def _label_group_before(text, pos):
    """从冒号位置向前回溯「逗号分隔的限定标识符组」，返回各成员末段名。
    支持 `A.eX, A.eY:` 与多行并列写法（调用前已折叠逗号换行）。"""
    res, i = [], pos - 1
    while True:
        while i >= 0 and text[i] in " \t\r\n":
            i -= 1
        j = i
        while j >= 0 and (text[j].isalnum() or text[j] in "_."):
            j -= 1
        chunk = text[j + 1:i + 1]
        if not chunk:
            break
        last = chunk.split(".")[-1]
        if not re.fullmatch(r"[A-Za-z_]\w*|\d+", last):
            break
        res.append(last)
        i = j
        while i >= 0 and text[i] in " \t\r\n":
            i -= 1
        if i >= 0 and text[i] == ",":
            i -= 1
            continue
        break
    return res


def r_enum_completeness(code, enums, vartype):
    """被 CASE 选择子使用的 ENUM：文件级 CASE 标签并集须覆盖全部成员"""
    if not enums:
        return []
    case_selectors = re.findall(r"\bCASE\s+([A-Za-z_]\w*)\s+OF\b", code)
    used = {vartype.get(s, "") for s in case_selectors}
    used_direct = {s for s in case_selectors if s in enums}      # CASE 直接写类型名（罕见）
    targets = {e for e in enums if e in used or e in used_direct}
    if not targets:
        return []
    # 文件级标签集合：行首 `标识符:` / `类型.成员:` / `数字:`；先折叠「逗号换行」以兼容
    # 多行并列标签（如 `A.eX, A.eY,` 换行后 `A.eZ:`）
    flat = re.sub(r",[ 	]*\r?\n[ 	]*", ", ", code)
    labels = set()
    for m in re.finditer(r":(?!=)", flat):
        labels.update(_label_group_before(flat, m.start()))
    hits = []
    for e in sorted(targets):
        missing = [m for m in enums[e] if m not in labels]
        if missing:
            hits.append((1, f"ENUM {e} 成员未被任何 CASE 标签覆盖：{', '.join(missing[:6])}"
                            + ("…" if len(missing) > 6 else "")))
    return hits


def r_enum_separator(code):
    hits = []
    for m in re.finditer(r"\bTYPE\s+([A-Za-z_]\w*)\s*:\s*\(([^;()]*)\)\s*;", code):
        base = line_of(code, m.start(2))
        body = m.group(2)
        for j, ln in enumerate(body.splitlines()):
            st = ln.strip().rstrip(",").strip()
            if not st or st.startswith("(*"):
                continue
            if re.match(r"^[A-Za-z_]\w*\s*:(?!=)", st):
                hits.append((base + j, f"ENUM 成员畸形分隔（单冒号，应为 := ）：{st[:50]}"))
    return hits


def r_nested_comment(text):
    hits, depth, ln = [], 0, 1
    i, n = 0, len(text)
    while i < n:
        if text.startswith("(*", i):
            if depth > 0:
                hits.append((ln, f"注释内嵌套 (* ：{text.splitlines()[ln - 1].strip()[:60]}"))
            depth += 1
            i += 2
            continue
        if text.startswith("*)", i) and depth > 0:
            depth -= 1
            i += 2
            continue
        if text[i] == "\n":
            ln += 1
        i += 1
    return hits


def r_undefined(code, names, enums, regions, gtypes=frozenset()):
    """R29 扩展：赋值目标根标识符 + 表达式标识符须已声明（收紧口径见文件头）"""
    lines = code.splitlines()
    masked = mask_regions(lines, regions)
    # TYPE 段整体屏蔽（枚举/结构体定义体不参与表达式扫描）
    in_type = False
    for i, ln in enumerate(masked):
        if re.match(r"^\s*TYPE\b", ln):
            in_type = True
        if in_type:
            masked[i] = ""
        if in_type and re.match(r"^\s*END_TYPE\b", ln):
            in_type = False
    body = blank_literals("\n".join(masked))
    enum_members = {m for ms in enums.values() for m in ms}
    known = names | enum_members | KW | BUILTIN | set(enums) | set(gtypes) | DATA_TYPES
    hits = []
    for m in re.finditer(r"[A-Za-z_]\w*", body):
        tok, s = m.group(0), m.start()
        prev = body[s - 1] if s else ""
        if prev in ".^%":                       # 成员访问右侧 / 地址前缀
            continue
        after = body[m.end():m.end() + 12]
        nxt = after.lstrip()[:2]
        if nxt.startswith("("):                 # 调用名
            continue
        if nxt.startswith("=>"):                # 输出形参绑定
            continue
        if nxt.startswith(":") and not nxt.startswith(":="):
            continue                            # 标签 / 形参声明 / 类型注解
        if nxt.startswith(":=") and _in_paren(body, s):
            continue                            # 调用内具名形参
        if tok.upper() in known or tok in known:
            continue
        if tok.isupper():                       # 全大写：类型/常量/枚举，降噪放行
            continue
        if tok in ("THIS", "SUPER", "SELF"):
            continue
        hits.append((line_of(body, s), tok))
    # 去重（同 token 同行只报一次）
    seen, out = set(), []
    for ln, tok in hits:
        if (ln, tok) in seen:
            continue
        seen.add((ln, tok))
        out.append((ln, f"疑似未声明标识符：{tok}"))
    return out


def _in_paren(body, pos):
    depth = 0
    for ch in body[:pos]:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
    return depth > 0


def r_semicolon(code):
    hits = []
    for i, ln in enumerate(code.splitlines(), 1):
        st = ln.strip()
        if re.fullmatch(r";{1,}", st):
            hits.append((i, "孤立分号空语句"))
        elif re.fullmatch(r":\s*;", st):
            hits.append((i, "孤立冒号分号"))
    return hits


# --------------------------------------------------------------- R13 新增：R37~R40 公共工具
SEV_FAIL, SEV_WARN = "FAIL", "WARN"
BOOL_KW = {"AND", "OR", "XOR", "NOT", "TRUE", "FALSE", "MOD", "THEN"}


def _assignments(code):
    """逐行提取 `目标 := 右值;`，返回 [(行号, 目标, 右值)]（右值截至分号，已剥注释）"""
    out = []
    for i, ln in enumerate(code.splitlines(), 1):
        for m in re.finditer(r"\b([A-Za-z_]\w*)\s*:=", ln):
            rhs = ln[m.end():].split(";")[0].strip()
            out.append((i, m.group(1), rhs))
    return out


def _strip_member(tok):
    return tok.split(".")[-1]


def _if_blocks(code):
    """块栈解析 IF/ELSIF/ELSE/END_IF；返回 [{start,end,conds[],assigns[(行,目标,右值)]}]"""
    blocks, stack = [], []
    for i, ln in enumerate(code.splitlines(), 1):
        for m in re.finditer(r"\b(IF|ELSIF|ELSE|END_IF)\b", ln):
            t = m.group(1)
            if t == "IF":
                stack.append({"start": i, "conds": [ln[m.end():]], "assigns": []})
            elif t == "ELSIF":
                if stack:
                    stack[-1]["conds"].append(ln[m.end():])
            elif t == "END_IF":
                if stack:
                    b = stack.pop()
                    b["end"] = i
                    blocks.append(b)
        if stack:
            for am in re.finditer(r"\b([A-Za-z_]\w*)\s*:=\s*([^;]*)", ln):
                stack[-1]["assigns"].append((i, am.group(1), am.group(2).strip()))
    return blocks


def _case_ranges(code):
    """块栈解析 CASE/END_CASE；返回 [(起始行, 结束行, 选择子)]"""
    out, stack = [], []
    for i, ln in enumerate(code.splitlines(), 1):
        for m in re.finditer(r"\b(CASE|END_CASE)\b", ln):
            if m.group(1) == "CASE":
                sel = re.search(r"CASE\s+([A-Za-z_]\w*)\s+OF", ln[m.end(1) - 4:])
                stack.append((i, sel.group(1) if sel else ""))
            elif stack:
                s, sel = stack.pop()
                out.append((s, i, sel))
    return out


def _is_state_var(name, vartype):
    if re.search(r"(?i)(state|phase|step|mode)", name):
        return True
    return bool(re.search(r"(?i)E_\w*(State|Phase|Step|Mode)$", vartype.get(name, "")))


# --------------------------------------------------------------------- R37 定长串回夹
BOUND_WORDS = r"(?:LEN\s*\(|\w*(?:LEN|Len|Length|MAX|MaxLen|MAXLEN|Width)\w*)"


def r37_left_clamp(code, vartype):
    hits = []
    lines = code.splitlines()
    # r37.1 自赋值回夹：LEFT 结果写回同一变量（确定性 → FAIL）
    for m in re.finditer(r"(?m)^[ \t]*([A-Za-z_]\w*)[ \t]*:=[ \t]*LEFT[ \t]*\([ \t]*\1[ \t]*,", code):
        ln = line_of(code, m.start())
        # 误报抑制：紧邻上文处于「长度与上界比较」的 IF 守卫内（合规回夹，如 IF nLen > nMax THEN x := LEFT(x, nMax)）
        guarded = False
        for k in range(ln - 1, max(0, ln - 7), -1):
            s = lines[k - 1]
            if re.search(r"\bEND_IF\b", s):
                break
            if re.match(r"[ \t]*(IF|ELSIF)\b", s) and re.search(BOUND_WORDS, s) and re.search(r"[<>]=?", s):
                guarded = True
                break
        # 误报抑制：回夹前已在邻近块内预判并置截断/溢出标志（先判后夹的合规写法，如 StringReplaceAll 段 5）
        if not guarded:
            guarded = any(re.search(r"(?i)\b\w*(trunc|overflow|saturat)\w*\s*:=\s*(TRUE|1)\b", s)
                          for s in lines[max(0, ln - 25):ln - 1])
        if guarded:
            continue
        hits.append((ln, SEV_FAIL,
                     f"r37.1 自赋值回夹 {m.group(1)} := LEFT({m.group(1)}, N)：回夹动作无判据，截断事件不可观测"))
    # r37.2 拼接无上界判定（启发式 → WARN：上界判定可能落在调用方）
    cat = re.search(r"\b(CONCAT|INSERT)\s*\(", code)
    if cat:
        has_bound = any(re.search(BOUND_WORDS, ln) and re.search(r"[<>]=?", ln) for ln in lines)
        if not has_bound:
            hits.append((line_of(code, cat.start()), SEV_WARN,
                         "r37.2 存在 CONCAT/INSERT 拼接，但全文未见长度量与上界（DL_STR_MAX / STRING 宽度）的比较"))
    # r37.3 截断标志死码（确定性 → FAIL）
    assigns = _assignments(code)
    for nm in sorted(vartype):
        if nm.isupper() or not re.search(r"(?i)(?:truncated|overflow|overflowed|saturated|clamped)$", nm):
            continue
        if vartype.get(nm, "").strip().upper() not in ("BOOL", "BOOL;"):
            continue
        vals = [v for _, t, v in assigns if _strip_member(t) == nm]
        live = [v for v in vals if v.strip().upper() not in ("FALSE", "0")]
        if not live:
            dl = next((i for i, ln in enumerate(lines, 1) if re.search(rf"\b{nm}\b\s*:", ln)), 1)
            why = "从未赋值" if not vals else "仅被置 FALSE"
            hits.append((dl, SEV_FAIL,
                         f"r37.3 截断/溢出标志 {nm} {why}：标志恒假，截断或溢出事件永不上报"))
    return hits


# ----------------------------------------------------------- R38 锁存副本与实时镜像量双源
def r38_dual_source(code, regions, vartype):
    hits = []
    lines = code.splitlines()
    body = "\n".join(mask_regions(lines, regions))      # 声明区屏蔽，避免把声明当引用
    len_use = collections.defaultdict(list)
    for m in re.finditer(r"\bLEN\s*\(\s*([A-Za-z_]\w*)\s*\)", body):
        len_use[m.group(1)].append(line_of(body, m.start()))

    def involved(lns):
        return any(re.search(r"[<>]=?", lines[l - 1]) or "[" in lines[l - 1] or ":=" in lines[l - 1]
                   for l in lns if 0 < l <= len(lines))

    for nm in sorted(len_use):
        if not re.search(r"(?i)(latch|latched|snap|snapshot|buf|buffer|mirror)$", nm):
            continue
        base = re.sub(r"(?i)(latch|latched|snap|snapshot|buf|buffer|mirror)$", "", nm)
        if not base or base == nm or base not in len_use:
            continue
        if involved(len_use[nm]) and involved(len_use[base]):
            # 误报抑制：锁存副本只被「取段后立即比较」（逐字符变化检测）时属合法用法，不报
            ext = [i + 1 for i, s in enumerate(lines)
                   if re.search(rf"\b(MID|LEFT|RIGHT|INSERT|DELETE)\s*\(\s*{nm}\b", s)]
            plain = [l for l in ext if not re.search(r"<>|(?<![<>=])=(?!=)", lines[l - 1])]
            if ext and not plain:
                continue
            hits.append((len_use[nm][0], SEV_FAIL,
                         f"r38.a 双源边界：LEN({nm})（锁存副本）与 LEN({base})（实时入参）并存且参与边界判定，"
                         f"分拍处理会切出「有效但为空」的假段"))

    for nm, c in sorted(collections.Counter(re.findall(r"\b([A-Za-z_]\w*)\b", body)).items()):
        if c <= 3 or nm.isupper() or len(nm) < 4:
            continue
        if not re.search(r"(?i)(live|real|raw)$", nm) or re.search(r"(?i)lreal$", nm):
            continue
        if re.search(r"(?i)^(l?real|e_|st_|fb_|i_|fc_)", nm):
            continue
        # 镜像量指纹：全文**仅一次**整体拷贝（x := <来源>），且被多处消费；
        # 多次赋值说明是「中间计算量」而非入参镜像，不报（降噪，避免把 Raw 中间量当镜像量）
        writes = [ln for ln in lines if re.search(rf"\b{nm}\s*:=", ln)]
        copies = [ln for ln in writes if re.search(rf"\b{nm}\s*:=\s*[A-Za-z_][\w\.\[\]]*\s*;", ln)]
        if len(writes) != 1 or len(copies) != 1:
            continue
        lns = [line_of(body, m.start()) for m in re.finditer(rf"\b{nm}\b", body)]
        hits.append((lns[0], SEV_WARN,
                     f"r38.b 镜像量 {nm} 有效引用 {c} 次（>3）：镜像量只应参与变化检测，须能指出唯一消费点"))
    return hits


# ------------------------------------------------------ R39 CASE 前置停机分支屏蔽复位沿
IDLE_MEMBERS = r"(?i)\b(?:E_\w+\.)?(?:eIdle|eStopped|eDisabled|eReset|eWait)\b"


def r39_pre_case_override(code, vartype):
    hits, seen = [], set()
    lines = code.splitlines()
    blocks = _if_blocks(code)
    for ci, ln in enumerate(lines, 1):
        if not re.match(r"[ \t]*CASE\s+([A-Za-z_]\w*)\s+OF\b", ln):
            continue
        cand = None
        for b in blocks:
            if b["end"] < ci and all(not lines[k - 1].strip() for k in range(b["end"] + 1, ci)):
                if cand is None or b["end"] > cand["end"]:
                    cand = b
        if not cand:
            continue
        cond = " ".join(cand["conds"])
        # ③ 条件已显式排除故障态（或做了上下界比较）→ 不属本缺陷
        if re.search(r"(?i)<>|NOT\s*\(\s*\w+\s*=", cond) or "<=" in cond or ">=" in cond:
            continue
        # 豁免：块内已出现复位沿判据（R39 的合法替代写法）
        if any(re.search(r"(?i)bReset|TrigReset|_fbTrigReset", lines[k - 1])
               for k in range(cand["start"], cand["end"] + 1)):
            continue
        clears = {t for _, t, _ in cand["assigns"]}
        body_lines = lines[cand["start"] - 1:cand["end"]]
        # 完整初始化分支：同时清故障码与故障标志（首扫初始化、整体置安全态）
        full_init = (any(re.search(r"(?i)\b\w*(errorid|errint|errid|errcode)\w*\s*:=\s*(0|16#0+(?:_0+)*)\b", s)
                         for s in body_lines)
                     and any(re.search(r"(?i)\b\w*(fault|error)\w*\s*:=\s*FALSE\b", s) for s in body_lines))
        # 该块自身在置故障（锁存标志 / 非零码）→ 不是「故障被抹掉」，降 WARN 待人工确认
        fault_entry = any(re.search(r"(?i)\b\w*(fault|latch|error)\w*\s*:=\s*(TRUE|1)\b", s) or
                          re.search(r"(?i)\bu?ErrorId\w*\s*:=\s*16#(?!0+_?0*\b)[0-9A-Fa-f_]+", s)
                          for s in body_lines)
        for li, tgt, val in cand["assigns"]:
            if not _is_state_var(tgt, vartype) or not re.search(IDLE_MEMBERS, val):
                continue
            key = (cand["start"], tgt)
            if key in seen:
                continue
            seen.add(key)
            sev = SEV_WARN if (full_init or fault_entry) else SEV_FAIL
            note = ""
            if full_init:
                note = "（块内同时清码，降级待人工确认）"
            elif fault_entry:
                note = "（块内另置故障锁存，降级待人工确认）"
            hits.append((li, sev,
                         f"r39 CASE（第 {ci} 行）前置 IF 块无条件改写 {tgt} := {val.split(';')[0].strip()}，"
                         f"条件未见故障态排除：故障复位沿整拍被跳" + note))
    return hits


# ------------------------------------------------------ R40 分段监控定时器 IN 跨段恒真
def r40_ton_cross_segment(code):
    hits, seen = [], set()
    cases = _case_ranges(code)
    for m in re.finditer(r"\bIN\s*:=", code):
        head = code[:m.start()]
        pm = head.rfind("(")
        if pm < 0:
            continue
        im = re.search(r"([A-Za-z_]\w*)\s*$", head[:pm])
        if not im:
            continue
        inst = im.group(1)
        if inst.upper() in BUILTIN:
            continue
        expr, depth = [], 1
        for ch in code[m.end():]:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
            elif ch == "," and depth == 1:
                break
            if ch != "\n":
                expr.append(ch)
        e = "".join(expr).strip()
        if not e or re.search(r"[<>]|\s=\s", e):
            continue                                    # 纯比较式：计时即条件成立，跨段合法
        if re.search(r"(?i)\bNOT\b", e) and re.search(r"(?i)break|brk|abort|cancel|clear", e):
            continue                                    # 合规写法指纹：断输入拍标志
        roots = {t for t in re.findall(r"[A-Za-z_]\w*", e)
                 if t.upper() not in BOOL_KW and not t.isupper()}
        if not roots:
            continue
        ln = line_of(code, m.start())
        owner = next((c for c in cases if c[0] <= ln <= c[1]), None)
        if not owner:
            continue
        seg = "\n".join(code.splitlines()[owner[0] - 1:owner[1]])
        if not (re.search(r"(?i)\b\w*(step|seg|phase|seq)\w*\s*:=\s*\w+\s*\+\s*1", seg)
                or re.search(r":=\s*E_\w+\.e\w+", seg)):
            continue                                    # ③ 无段推进写：不构成跨段
        for v in sorted(roots):
            if not re.search(rf"\b{v}\s*:=\s*(TRUE|1)\b", code):
                continue                                # ① 从未置 TRUE
            if re.search(rf"\b{v}\s*:=\s*(FALSE|0)\b", code):
                continue                                # ② 会被清零：非跨段保持型
            key = (inst, v)
            if key in seen:
                continue
            seen.add(key)
            sev = SEV_FAIL if re.search(r"(?i)watch|step|seg|phase", inst) else SEV_WARN
            hits.append((ln, sev,
                         f"r40 定时器 {inst} 的 IN 根变量 {v} 在 CASE（第 {owner[0]} 行）内跨段保持恒真、全文无清零，"
                         f"ET 将跨段累加（{owner[2] or 'CASE'}: 存在段推进写）"))
    return hits


# ----------------------------------------------------------------------------- 主流程
def collect_files(argv):
    files = []
    if "--files" in argv:
        idx = argv.index("--files")
        for a in argv[idx + 1:]:
            if a.startswith("--"):
                break
            p = a if os.path.isabs(a) else os.path.join(LIB, a)
            if not os.path.exists(p):
                cand = glob.glob(os.path.join(LIB, "DL_*", a))
                p = cand[0] if cand else p
            if os.path.exists(p):
                files.append(os.path.abspath(p))
            else:
                print(f"[SKIP] 文件不存在：{a}")
    else:
        for cat in CATS:
            files += sorted(glob.glob(os.path.join(LIB, cat, "*.st")))
    return files


def main():
    argv = sys.argv[1:]
    rules = ALL_RULES
    if "--rules" in argv:
        i = argv.index("--rules")
        if i + 1 >= len(argv):
            print("参数错误：--rules 需要列表")
            return 2
        rules = [r.strip() for r in argv[i + 1].split(",") if r.strip()]
        bad = [r for r in rules if r not in ALL_RULES]
        if bad:
            print(f"参数错误：未知规则 {bad}")
            return 2
    files = collect_files(argv)
    if not files:
        print("无文件可检")
        return 2

    res = collections.defaultdict(list)     # rule -> [(file, line, msg)]
    total_lines = total_chars = 0
    pou_map = collections.defaultdict(list)
    sizes = []

    # 预扫描：全库级类型/接口/POU/枚举成员（跨文件引用合法，须放行，否则 R29 噪声爆炸）
    gtypes = set()
    cache = {}
    for p in files:
        text = open(p, "rb").read().decode("utf-8", errors="replace")
        code = strip_pragmas(strip_comments(text))
        names, vartype, enums, regions = parse_decls(code)
        cache[p] = (text, code, names, vartype, enums, regions)
        gtypes |= {m.group(1) for m in re.finditer(
            r"^\s*(?:TYPE|INTERFACE|FUNCTION_BLOCK|FUNCTION|PROGRAM)\s+([A-Za-z_]\w*)", code, re.MULTILINE)}
        for ms in enums.values():
            gtypes |= set(ms)

    for p in files:
        text, code, names, vartype, enums, regions = cache[p]
        rel = os.path.relpath(p, LIB).replace("\\", "/")
        total_chars += len(text)
        nl = text.count("\n") + (0 if text.endswith("\n") else 1)
        total_lines += nl
        sizes.append((nl, rel))

        if "banned_hits" in rules:
            res["banned_hits"] += [(rel, l, f"{lab}  ← {ctx}") for l, lab, ctx in r_banned(text)]
        if "placeholder" in rules:
            res["placeholder"] += [(rel, l, f"{lab}  ← {ctx}") for l, lab, ctx in r_placeholder(text)]
        if "terminator" in rules:
            res["terminator"] += [(rel, l, msg) for l, msg in r_terminator(text, code)]
        if "bilingual_comment" in rules:
            res["bilingual_comment"] += [(rel, l, msg) for l, msg in r_bilingual(text, regions)]
        if "case_else" in rules:
            res["case_else"] += [(rel, l, msg) for l, msg in r_case_else(code)]
        if "enum_case_completeness" in rules:
            res["enum_case_completeness"] += [(rel, l, msg) for l, msg in r_enum_completeness(code, enums, vartype)]
        if "enum_separator" in rules:
            res["enum_separator"] += [(rel, l, msg) for l, msg in r_enum_separator(code)]
        if "nested_comment" in rules:
            res["nested_comment"] += [(rel, l, msg) for l, msg in r_nested_comment(text)]
        if "undefined_identifier" in rules:
            res["undefined_identifier"] += [(rel, l, msg) for l, msg in r_undefined(code, names, enums, regions, gtypes)]
        if "single_colon_or_semicolon" in rules:
            res["single_colon_or_semicolon"] += [(rel, l, msg) for l, msg in r_semicolon(code)]
        if "r37_left_clamp" in rules:
            res["r37_left_clamp"] += [(rel, l, f"[{sev}] {msg}") for l, sev, msg in r37_left_clamp(code, vartype)]
        if "r38_dual_source" in rules:
            res["r38_dual_source"] += [(rel, l, f"[{sev}] {msg}")
                                       for l, sev, msg in r38_dual_source(code, regions, vartype)]
        if "r39_pre_case_override" in rules:
            res["r39_pre_case_override"] += [(rel, l, f"[{sev}] {msg}")
                                             for l, sev, msg in r39_pre_case_override(code, vartype)]
        if "r40_ton_cross_segment" in rules:
            res["r40_ton_cross_segment"] += [(rel, l, f"[{sev}] {msg}")
                                             for l, sev, msg in r40_ton_cross_segment(code)]
        if "duplicate_pou_name" in rules:
            for m in re.finditer(r"^\s*(?:FUNCTION_BLOCK|FUNCTION|PROGRAM)\s+([A-Za-z_]\w*)", code, re.MULTILINE):
                pou_map[m.group(1)].append(rel)

    if "duplicate_pou_name" in rules:
        for nm, where in sorted(pou_map.items()):
            if len(where) > 1:
                res["duplicate_pou_name"].append((where[1], 0, f"POU 重名 {nm}：{', '.join(where)}"))

    print("=" * 78)
    print(f"道莅代码库机检 R13 ｜ 文件 {len(files)} 件 ｜ 规则 {len(rules)} 项")
    print("=" * 78)
    for k in res:
        res[k].sort(key=lambda x: (x[0], x[1]))

    def sev_of(msg):
        return SEV_WARN if msg.startswith("[WARN]") else SEV_FAIL

    order = [r for r in ALL_RULES if r in rules]
    fail_total = warn_total = 0
    for r in order:
        if r in ("line_count", "duplicate_pou_name"):
            continue
        hits = res.get(r, [])
        nf = sum(1 for h in hits if sev_of(h[2]) == SEV_FAIL)
        nw = len(hits) - nf
        stat = "PASS" if not hits else ("FAIL" if nf else "WARN")
        fail_total += nf
        warn_total += nw
        tag = f"（FAIL {nf} / WARN {nw}）" if nw or nf else ""
        print(f"\n[{r}] {stat}  命中 {len(hits)}{tag}")
        for f, l, msg in hits[:40]:
            print(f"   {f}:L{l}  {msg}")
        if len(hits) > 40:
            print(f"   … 其余 {len(hits) - 40} 条已省略（完整清单见 AUDIT_BASELINE_R13.md）")

    if "duplicate_pou_name" in rules:
        hits = res.get("duplicate_pou_name", [])
        print(f"\n[duplicate_pou_name] {'PASS' if not hits else 'FAIL'}  命中 {len(hits)}（POU 定义 {len(pou_map)} 个）")
        for f, l, msg in hits:
            print(f"   {f}:L{l}  {msg}")

    if "line_count" in rules:
        sizes.sort(reverse=True)
        print(f"\n[line_count / char_count] INFO  合计 {total_lines} 行 / {total_chars} 字符；"
              f"最大 {sizes[0][0]} 行（{sizes[0][1]}）/ 最小 {sizes[-1][0]} 行（{sizes[-1][1]}）")

    print("\n" + "-" * 78)
    print("规则汇总：")
    for r in order:
        hits = res.get(r, [])
        nf = sum(1 for h in hits if sev_of(h[2]) == SEV_FAIL)
        nw = len(hits) - nf
        flag = "PASS" if not hits else ("FAIL" if nf else "WARN")
        if r in ("line_count",):
            flag = "INFO"
        print(f"   {r:<28} {flag:<5} {len(hits):<4}" + (f"(FAIL {nf}/WARN {nw})" if hits else ""))
    print(f"\nSUMMARY: files={len(files)} fail={fail_total} warn={warn_total}")
    return 0 if fail_total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
