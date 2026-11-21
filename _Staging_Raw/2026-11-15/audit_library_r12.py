# -*- coding: utf-8 -*-
"""道莅代码库全库机检 R12 / LIBRARY MACHINE AUDIT R12
用法：
  python audit_library_r12.py                  # 全库 DL_*/*.st
  python audit_library_r12.py --files a.st b.st # 仅指定文件（canonical 路径或文件名）
  python audit_library_r12.py --rules case_else,undefined_identifier
输出末行：SUMMARY: files=N fail=M  （机器可读；fail 只计 FAIL 级规则，INFO 不计）

十二条机检项：
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
返回码：0 = 无 FAIL，1 = 有 FAIL，2 = 参数错误。
"""
import re, sys, os, io, glob, json, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

LIB = r"C:\Library"
CATS = ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]

ALL_RULES = ["banned_hits", "placeholder", "terminator", "bilingual_comment", "case_else",
             "enum_case_completeness", "enum_separator", "nested_comment",
             "undefined_identifier", "single_colon_or_semicolon", "line_count", "duplicate_pou_name"]

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
        if "duplicate_pou_name" in rules:
            for m in re.finditer(r"^\s*(?:FUNCTION_BLOCK|FUNCTION|PROGRAM)\s+([A-Za-z_]\w*)", code, re.MULTILINE):
                pou_map[m.group(1)].append(rel)

    if "duplicate_pou_name" in rules:
        for nm, where in sorted(pou_map.items()):
            if len(where) > 1:
                res["duplicate_pou_name"].append((where[1], 0, f"POU 重名 {nm}：{', '.join(where)}"))

    print("=" * 78)
    print(f"道莅代码库机检 R12 ｜ 文件 {len(files)} 件 ｜ 规则 {len(rules)} 项")
    print("=" * 78)
    for k in res:
        res[k].sort(key=lambda x: (x[0], x[1]))

    order = [r for r in ALL_RULES if r in rules]
    fail_total = 0
    for r in order:
        if r in ("line_count", "duplicate_pou_name"):
            continue
        hits = res.get(r, [])
        stat = "PASS" if not hits else "FAIL"
        if hits:
            fail_total += len(hits)
        print(f"\n[{r}] {stat}  命中 {len(hits)}")
        for f, l, msg in hits[:40]:
            print(f"   {f}:L{l}  {msg}")
        if len(hits) > 40:
            print(f"   … 其余 {len(hits) - 40} 条已省略（完整清单见 AUDIT_BASELINE_R12.md）")

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
        n = len(res.get(r, []))
        flag = "PASS" if n == 0 else "FAIL"
        if r in ("line_count",):
            flag = "INFO"
        print(f"   {r:<28} {flag:<5} {n}")
    print(f"\nSUMMARY: files={len(files)} fail={fail_total}")
    return 0 if fail_total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
