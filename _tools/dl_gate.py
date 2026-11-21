# -*- coding: utf-8 -*-
"""dl_gate.py - 道莅 ST 静态门（L1）

设计原则：
1. 不依赖第三方库（tree-sitter 在本机不可用），自研 tokenizer + 构造栈。
2. 只做「结构性语法 + 项目红线 + 声明完整性」，不做类型推导；真语义编译交给 MatIEC（CI）。
3. 每条判定都带行号；每次改判据必须先跑 --selftest 回归。

用法：
    python dl_gate.py --all                      # 全库扫描（每天最多 1 次）
    python dl_gate.py --changed-only --round R65 # 只扫本轮变更
    python dl_gate.py --file DL_Base/FC_DL_X.st  # 单文件
    python dl_gate.py --selftest                 # 判据回归（10 反例 + 10 正例）
"""
import argparse, json, os, re, sys, io, glob, tempfile, datetime, shutil

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw")

KEYWORDS = {
    "IF","THEN","ELSIF","ELSE","END_IF","CASE","OF","END_CASE","FOR","TO","BY","DO","END_FOR",
    "WHILE","END_WHILE","REPEAT","UNTIL","END_REPEAT","EXIT","CONTINUE","RETURN",
    "FUNCTION","END_FUNCTION","FUNCTION_BLOCK","END_FUNCTION_BLOCK","PROGRAM","END_PROGRAM",
    "INTERFACE","END_INTERFACE","METHOD","END_METHOD","PROPERTY","END_PROPERTY","GET","SET",
    "TYPE","END_TYPE","STRUCT","END_STRUCT","UNION","END_UNION","VAR","VAR_INPUT","VAR_OUTPUT",
    "VAR_IN_OUT","VAR_GLOBAL","VAR_TEMP","VAR_STAT","VAR_INST","VAR_EXTERNAL","CONSTANT",
    "RETAIN","NON_RETAIN","PERSISTENT","END_VAR","EXTENDS","IMPLEMENTS","ABSTRACT","FINAL",
    "PUBLIC","PRIVATE","PROTECTED","INTERNAL","OVERRIDE","THIS","SUPER","ACTION","END_ACTION",
    "NAMESPACE","END_NAMESPACE","AT","ARRAY","STRING","WSTRING","REFERENCE","POINTER","ALIAS",
    "AND","OR","XOR","NOT","MOD","TRUE","FALSE","NULL",
    # 类型关键字
    "BOOL","BYTE","WORD","DWORD","LWORD","SINT","INT","DINT","LINT","USINT","UINT","UDINT",
    "ULINT","REAL","LREAL","TIME","LTIME","DATE","LDATE","TOD","LTOD","DT","LDT","CHAR","WCHAR",
    "ANY","ANY_NUM","ANY_INT","ANY_REAL","ANY_BIT","ANY_STRING","ANY_DATE",
}
SECTION_OPEN = {"VAR","VAR_INPUT","VAR_OUTPUT","VAR_IN_OUT","VAR_GLOBAL","VAR_TEMP",
                "VAR_STAT","VAR_INST","VAR_EXTERNAL"}
BLOCK_PAIRS = {  # opener -> closer
    "IF":"END_IF","CASE":"END_CASE","FOR":"END_FOR","WHILE":"END_WHILE","REPEAT":"END_REPEAT",
    "FUNCTION":"END_FUNCTION","FUNCTION_BLOCK":"END_FUNCTION_BLOCK","PROGRAM":"END_PROGRAM",
    "INTERFACE":"END_INTERFACE","METHOD":"END_METHOD","PROPERTY":"END_PROPERTY",
    "TYPE":"END_TYPE","STRUCT":"END_STRUCT","UNION":"END_UNION","ACTION":"END_ACTION",
    "NAMESPACE":"END_NAMESPACE",
}
REQUIRED_INNER = {"IF":"THEN","CASE":"OF","FOR":"DO","WHILE":"DO","REPEAT":"UNTIL"}
CLOSERS = set(BLOCK_PAIRS.values())

STD_FUNCS = set("""
ABS SQRT LN LOG EXP EXPT SIN COS TAN ASIN ACOS ATAN ATAN2 ADD SUB MUL DIV MOD MOVE SEL MAX MIN
LIMIT MUX GT GE EQ LE LT NE AND OR XOR NOT SHL SHR ROL ROR ADD_TIME SUB_TIME MUL_TIME DIV_TIME
CONCAT INSERT DELETE REPLACE FIND LEFT RIGHT MID LEN TRUNC ROUND FLOOR CEIL
BOOL_TO_INT INT_TO_BOOL INT_TO_DINT DINT_TO_INT INT_TO_REAL REAL_TO_INT REAL_TO_LREAL
LREAL_TO_REAL LREAL_TO_DINT DINT_TO_LREAL TIME_TO_DINT DINT_TO_TIME TIME_TO_LREAL
USINT_TO_DINT UINT_TO_DINT UDINT_TO_DINT SINT_TO_DINT BYTE_TO_INT WORD_TO_INT DWORD_TO_DINT
DINT_TO_UDINT INT_TO_UDINT UDINT_TO_REAL REAL_TO_UDINT LWORD_TO_DINT DINT_TO_LWORD
BIT_AND BIT_OR BIT_XOR BIT_NOT LREAL_TO_UDINT UDINT_TO_LREAL
""".split())

TYPE_PAT = re.compile(r'^(BOOL|BYTE|WORD|DWORD|LWORD|SINT|INT|DINT|LINT|USINT|UINT|UDINT|ULINT|'
                      r'REAL|LREAL|TIME|LTIME|DATE|LDATE|TOD|LTOD|DT|LDT|STRING|WSTRING|CHAR|WCHAR)'
                      r'(\[\s*\d+\s*\])?$', re.I)
CJK = re.compile(r'[\u4e00-\u9fff]')
ASCII_WORD = re.compile(r'[A-Za-z]{2,}')

# ---------------- tokenizer ----------------
class Tok:
    __slots__ = ("kind","val","line")
    def __init__(self,k,v,l): self.kind,self.val,self.line=k,v,l
    def __repr__(self): return f"{self.kind}:{self.val}@{self.line}"

def strip_and_tokenize(src):
    """返回 (tokens, comments{line:text}, nested_comment_flag)"""
    toks, comments = [], {}
    i, n, line = 0, len(src), 1
    nested = False
    depth_comment = 0
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1; i += 1; continue
        if src.startswith("(*", i):
            depth_comment += 1
            if depth_comment > 1: nested = True
            i += 2
            buf = []
            while i < n and depth_comment > 0:
                if src.startswith("(*", i): depth_comment += 1; i += 2; buf.append(" ")
                elif src.startswith("*)", i): depth_comment -= 1; i += 2; buf.append(" ")
                else:
                    if src[i] == "\n": line += 1
                    buf.append(src[i]); i += 1
            comments[line] = (comments.get(line,"") + " " + "".join(buf))
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            if j < 0: j = n
            comments[line] = (comments.get(line,"") + " " + src[i+2:j])
            i = j
            continue
        if c in "'\"":
            q, j, buf = c, i+1, []
            while j < n:
                if src[j] == q:
                    if j+1 < n and src[j+1] == q: buf.append(q); j += 2; continue
                    break
                if src[j] == "\n": line += 1
                buf.append(src[j]); j += 1
            toks.append(Tok("str", "".join(buf), line)); i = j+1; continue
        if c.isdigit():
            j = i
            while j < n and (src[j].isalnum() or src[j] in "._#"): j += 1
            toks.append(Tok("num", src[i:j], line)); i = j; continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (src[j].isalnum() or src[j] == "_"): j += 1
            toks.append(Tok("id", src[i:j], line)); i = j; continue
        if c in ":=><":
            two = src[i:i+2]
            if two in (":=","=>","<=",">=","<>","**","->"):
                toks.append(Tok("op", two, line)); i += 2; continue
        if c in "+-*/&.,;:()[]#%":
            toks.append(Tok("op", c, line)); i += 1; continue
        if c.isspace(): i += 1; continue
        toks.append(Tok("op", c, line)); i += 1
    return toks, comments, nested

def strip_comments_keep_lines(src):
    """把注释替换为空格，保留行数与字符串字面量（供声明/红线检查）"""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("(*", i):
            i += 2; depth = 1
            while i < n and depth:
                if src.startswith("(*", i): depth += 1; i += 2
                elif src.startswith("*)", i): depth -= 1; i += 2
                else:
                    out.append("\n" if src[i] == "\n" else " "); i += 1
            continue
        if src.startswith("//", i):
            while i < n and src[i] != "\n": out.append(" "); i += 1
            continue
        if src[i] in "'\"":
            q = src[i]; out.append(src[i]); i += 1
            while i < n:
                if src[i] == q:
                    out.append(src[i]); i += 1
                    if i < n and src[i] == q: out.append(src[i]); i += 1; continue
                    break
                out.append(src[i]); i += 1
            continue
        out.append(src[i]); i += 1
    return "".join(out)

# ---------------- checks ----------------
def gate_file(path, registry_index=None, strict_decl=False):
    return gate_source(io.open(path, encoding="utf-8", errors="replace").read(),
                       os.path.basename(path), registry_index, strict_decl)

def gate_source(src, basename, registry_index=None, strict_decl=False):
    name = os.path.splitext(basename)[0]
    code_src = strip_comments_keep_lines(src)
    toks, comments, nested = strip_and_tokenize(src)
    issues = []  # (level, code, line, detail)
    def add(level, code, line, detail=""):
        issues.append({"level":level,"code":code,"line":line,"detail":detail})

    # 红线 1/2/3：只在「去注释」后判定，避免头部注释里的「零 GVL / 零 %I」误命中
    if re.search(r"\bVAR_EXTERNAL\b", code_src, re.I): add("BLOCK","R1_VAR_EXTERNAL",0,"禁止 VAR_EXTERNAL")
    if re.search(r"\bGVL\b", code_src): add("BLOCK","R2_GVL",0,"禁止 GVL 引用")
    if re.search(r"%[IQM]", code_src): add("BLOCK","R3_DIRECT_IO",0,"禁止直接物理地址 %I/%Q/%M")
    if nested: add("BLOCK","R4_NESTED_COMMENT",0,"禁止注释嵌套 (* (* *) *)")

    # 构造栈：帧 = [opener, line, kind, inner_ok]
    stack = []
    INNER_OF = {v: k for k, v in REQUIRED_INNER.items()}   # THEN->IF, OF->CASE, DO->FOR/WHILE, UNTIL->REPEAT
    for t in toks:
        if t.kind != "id": continue
        up = t.val.upper()
        if up in SECTION_OPEN:
            stack.append([up, t.line, "VAR", True]); continue
        if up == "END_VAR":
            if not stack or stack[-1][2] != "VAR":
                add("BLOCK","SYN_END_VAR",t.line,"END_VAR 无匹配的 VAR 段")
            else: stack.pop()
            continue
        if up in BLOCK_PAIRS:
            stack.append([up, t.line, "BLOCK", False]); continue
        if up in ("THEN","OF","DO","UNTIL"):
            want = INNER_OF[up]
            cands = ("FOR","WHILE") if up == "DO" else (want,)
            for k in range(len(stack)-1,-1,-1):
                if stack[k][0] in cands:
                    stack[k][3] = True; break
            continue
        if up in CLOSERS:
            want = [o for o,c in BLOCK_PAIRS.items() if c == up]
            if not stack or stack[-1][2] != "BLOCK":
                add("BLOCK","SYN_STRAY_END",t.line,f"{up} 无匹配开块"); continue
            op = stack[-1]
            if op[0] in want:
                need = REQUIRED_INNER.get(op[0])
                if need and not op[3]:
                    add("BLOCK","SYN_MISSING_%s"%need,op[1],f"{op[0]} 缺 {need}")
                stack.pop()
            else:
                add("BLOCK","SYN_CROSS_END",t.line,f"{up} 与最近开块 {op[0]}(L{op[1]}) 交叉")
                for k in range(len(stack)-1,-1,-1):
                    if stack[k][0] in want: del stack[k:]; break
    for frame in stack:
        add("BLOCK","SYN_UNCLOSED", frame[1], f"{frame[0]} 未闭合")

    # CASE 必须含 ELSE（区分大小写；code_src 已剥离注释）
    for m in re.finditer(r"\bCASE\b(.*?)\bEND_CASE\b", code_src, re.S):
        if not re.search(r"\bELSE\b", m.group(1)):
            add("MAJOR","R6_CASE_NO_ELSE", code_src[:m.start()].count("\n")+1,
                "CASE 缺 ELSE 兜底")

    # 声明区解析（用去注释后的行解析；用原始行判定中文注释）
    declared, outputs, enum_members, inited = set(), set(), set(), set()
    in_var, cur_section = False, ""
    buf = []
    decl_re = re.compile(r"^\s*([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*(?::=|:)\s*(.+?)\s*;\s*$", re.S)
    lines_code = code_src.split("\n")
    lines_raw = src.split("\n")
    for idx, ln in enumerate(lines_code, 1):
        up = ln.strip().upper()
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_GLOBAL|_TEMP|_STAT|_INST|_EXTERNAL)?\b", up):
            in_var, cur_section, buf = True, re.match(r"^(VAR_\w+|VAR)", up).group(1), []
            continue
        if up.startswith("END_VAR"):
            in_var = False; continue
        if not in_var: continue
        if not ln.strip(): continue
        buf.append((idx, ln))
        joined = " ".join(x[1] for x in buf).strip()
        if not joined.endswith(";"): continue
        start_line = buf[0][0]
        raw_joined = " ".join(lines_raw[x[0]-1] for x in buf)
        buf = []
        m = decl_re.match(joined)
        if not m:
            add("MAJOR","DECL_FORM",start_line,"声明格式不合规：" + joined[:60]); continue
        names, typ = m.group(1), m.group(2)
        # 中文注释（同行，按原始行判定）
        if not CJK.search(raw_joined):
            add("MINOR","DECL_NO_CJK",start_line,"声明行缺中文注释")
        for nm in [x.strip() for x in names.split(",")]:
            declared.add(nm)
            if ":=" in typ: inited.add(nm)
            if cur_section == "VAR_OUTPUT": outputs.add(nm)
        is_enum = typ.strip().startswith("(")
        typ_core = typ.strip() if is_enum else typ.split(":=")[0].strip()
        # 枚举声明：Name : (A, B, C)
        if is_enum:
            if not typ_core.rstrip().endswith(")"):
                add("BLOCK","DECL_ENUM_PAREN",start_line,"枚举声明括号不配对")
            else:
                for item in typ_core.strip("()").split(","):
                    if item.strip(): enum_members.add(item.strip().split(":=")[0].strip())
        else:
            base = typ_core.split("[")[0].split(".")[-1].strip()
            if not (TYPE_PAT.match(typ_core) or base in declared or base.upper() in KEYWORDS):
                # 可能是自定义 STRUCT/FB 类型或数组
                if not re.match(r"^ARRAY\s*\[", typ_core, re.I) and not re.match(r"^REFERENCE\s+TO\b", typ_core, re.I):
                    add("WARN","DECL_UNKNOWN_TYPE",start_line,f"类型未识别：{typ_core[:40]}")

    # 声明完整性 F 检：项目前缀标识符被引用但未声明
    body = re.sub(r"\(\*.*?\*\)","",src,flags=re.S)
    body = re.sub(r"//[^\n]*","",body)
    used = {}
    for t in strip_and_tokenize(body)[0]:
        if t.kind != "id": continue
        v = t.val
        if v.upper() in KEYWORDS or v.upper() in STD_FUNCS: continue
        used.setdefault(v, t.line)
    declared_upper = {d.upper() for d in declared} | {e.upper() for e in enum_members}
    local_pat = re.compile(r"^(_[a-zA-Z]\w*|rt[A-Z_]\w*|[bnfiud]?[_]?[A-Z]\w*)$")
    for v, ln in used.items():
        if v.upper() in declared_upper: continue
        if v in ("E_DL","FB_DL","FC_DL","I_DL","ST_DL"): continue
        # 只对项目约定的局部命名做硬判（_x / rtX / 单字母前缀+驼峰）
        if v.startswith("_") or v.startswith("rt"):
            add("BLOCK","F_DECL_MISSING",ln,f"标识符 {v} 未声明（F 检）")
        elif strict_decl and local_pat.match(v) and not v.isupper():
            add("MAJOR","F_DECL_MAYBE",ln,f"疑似未声明：{v}")

    # VAR_OUTPUT 未被赋值
    for o in outputs:
        if o in inited: continue
        if not re.search(r"\b%s\s*(\[[^\]]*\])?\s*(\.[A-Za-z_]\w*)?\s*:=" % re.escape(o), body):
            add("MAJOR","OUT_NO_ASSIGN",0,f"输出 {o} 从未赋值")

    # 版本头
    vm = re.search(r"VERSION\s*[:：]\s*v?(\d+\.\d+\.\d+)", src[:1200], re.I)
    if not vm:
        add("MINOR","VER_HEADER",0,"文件头缺 VERSION: x.y.z")
    else:
        if registry_index and name in registry_index:
            rv = str(registry_index[name].get("version","1.0.0"))
            if rv and rv != vm.group(1):
                add("MAJOR","VER_MISMATCH",0,f"文件头 {vm.group(1)} ≠ registry {rv}")

    # 码段唯一（仅当注册表传入）
    if registry_index and name in registry_index:
        cs = re.search(r"16#([0-9A-Fa-f_~]+)", src[:2000])
        if cs:
            seg = "16#" + cs.group(1)
            for other, meta in registry_index.items():
                if other != name and meta.get("code_segment") == seg:
                    add("BLOCK","SEG_DUP",0,f"码段 {seg} 与 {other} 重复")

    level_rank = {"BLOCK":0,"MAJOR":1,"MINOR":2,"WARN":3}
    worst = min([level_rank[i["level"]] for i in issues], default=9)
    verdict = "PASS" if worst >= 2 else ("BLOCK" if worst == 0 else "MAJOR")
    return {"file": basename, "name": name, "issues": issues,
            "verdict": verdict, "lines": len(lines_code)}

def load_registry_index():
    p = os.path.join(LIB, "INDEX_REGISTRY.json")
    if not os.path.exists(p): return {}
    d = json.load(open(p, encoding="utf-8"))
    return {c["name"]: c for c in d["components"]}

def collect_changed(hours=3):
    cutoff = datetime.datetime.now().timestamp() - hours*3600
    out = []
    for p in glob.glob(os.path.join(LIB, "DL_*", "*.st")):
        if os.path.getmtime(p) >= cutoff: out.append(p)
    return out

# ---------------- selftest ----------------
BAD = {
 "unclosed_if": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\nEND_VAR\nIF a > 1.0 THEN\n a := 0.0;\nEND_FUNCTION_BLOCK\n",
 "cross_end": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\nEND_VAR\nCASE a OF\n1: a := 1.0;\nEND_IF\n",
 "case_no_else": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : INT; // a 输入\nEND_VAR\nCASE a OF\n1: a := 1;\nEND_CASE\n",
 "gvl": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\nEND_VAR\nGVL.fX := a;\nEND_FUNCTION_BLOCK\n",
 "direct_io": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\nEND_VAR\n%IX0.0 := a;\nEND_FUNCTION_BLOCK\n",
 "nested_comment": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\n(* outer (* inner *) *)\nEND_FUNCTION_BLOCK\n",
 "missing_decl": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\nEND_VAR\n_bMissing := a;\nEND_FUNCTION_BLOCK\n",
 "out_no_assign": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\nVAR_OUTPUT b : REAL; // b 输出\nEND_VAR\nb := a;\n",
 "end_var_missing": "FUNCTION_BLOCK FB_X\nVAR_INPUT a : REAL; // a 输入\n a := 1.0;\nEND_FUNCTION_BLOCK\n",
 "var_external": "FUNCTION_BLOCK FB_X\nVAR_EXTERNAL\n g : REAL; // g 全局\nEND_VAR\nEND_FUNCTION_BLOCK\n",
}
GOOD = {
 "simple_fb": "FUNCTION_BLOCK FB_DL_X\nVAR_INPUT\n fIn : LREAL; // 输入值 input value\nEND_VAR\nVAR_OUTPUT\n fOut : LREAL; // 输出值 output value\n bValid : BOOL; // 有效 valid flag\nEND_VAR\nfOut := fIn; // 直通 passthrough\nbValid := TRUE; // 置有效 set valid\nEND_FUNCTION_BLOCK\n",
 "with_case_else": "FUNCTION_BLOCK FB_DL_Y\nVAR_INPUT\n nSel : INT; // 选择 selection\nEND_VAR\nVAR_OUTPUT\n fOut : LREAL; // 输出 output\nEND_VAR\nCASE nSel OF\n0: fOut := 0.0; // 零 zero\n1: fOut := 1.0; // 一 one\nELSE\n fOut := -1.0; // 兜底 fallback\nEND_CASE\nEND_FUNCTION_BLOCK\n",
 "with_if": "FUNCTION_BLOCK FB_DL_Z\nVAR_INPUT\n fA : LREAL; // 甲 a\nEND_VAR\nVAR_OUTPUT\n fB : LREAL; // 乙 b\nEND_VAR\nIF fA > 0.0 THEN\n fB := fA; // 正 positive\nELSE\n fB := 0.0; // 零 zero\nEND_IF\nEND_FUNCTION_BLOCK\n",
 "func_array": "FUNCTION FC_DL_S : LREAL\nVAR_INPUT\n afX : ARRAY[1..8] OF LREAL; // 数组 array\n n : INT; // 个数 count\nEND_VAR\nVAR_TEMP\n i : INT; // 循环 loop\n fS : LREAL; // 累加 sum\nEND_VAR\nfS := 0.0; // 清零 reset\nFOR i := 1 TO n DO\n fS := fS + afX[i]; // 累加 accumulate\nEND_FOR\nFC_DL_S := fS; // 返回 return\nEND_FUNCTION\n",
 "while_loop": "FUNCTION_BLOCK FB_DL_W\nVAR_INPUT\n n : DINT; // 计数 count\nEND_VAR\nVAR_TEMP\n i : DINT; // 索引 index\nEND_VAR\nVAR_OUTPUT\n nOut : DINT; // 输出 out\nEND_VAR\ni := 0; // 初始化 init\nWHILE i < n DO\n i := i + 1; // 递增 increment\nEND_WHILE\nnOut := i; // 赋值 assign\nEND_FUNCTION_BLOCK\n",
}

def selftest():
    ok = True
    tmp = tempfile.mkdtemp()
    for k, src in BAD.items():
        p = os.path.join(tmp, "BAD_" + k + ".st")
        io.open(p, "w", encoding="utf-8").write(src)
        r = gate_file(p)
        hit = r["verdict"] in ("BLOCK","MAJOR")
        if not hit: ok = False
        print(("  OK  " if hit else "  MISS") + f" 反例 {k:18s} verdict={r['verdict']:5s} " +
              ",".join(sorted({i['code'] for i in r['issues']}))[:70])
    for k, src in GOOD.items():
        p = os.path.join(tmp, "GOOD_" + k + ".st")
        io.open(p, "w", encoding="utf-8").write(src)
        r = gate_file(p)
        hard = [i for i in r["issues"] if i["level"] in ("BLOCK","MAJOR")]
        if hard: ok = False
        print(("  OK  " if not hard else "  FALSE+") + f" 正例 {k:18s} verdict={r['verdict']:5s} " +
              ",".join(sorted({i['code'] for i in hard}))[:70])
    print("SELFTEST", "PASS" if ok else "FAIL")
    return 0 if ok else 1

FIXABLE = {"VAR":"END_VAR", **{k:v for k,v in BLOCK_PAIRS.items()}}

def fix_structural(path, dry_run=True, max_iter=12):
    """按门禁报出的 SYN_STRAY_END/SYN_CROSS_END/SYN_UNCLOSED 机械补齐闭合词。
    只插入 END_*，不改任何语义行；每步后重跑校验，收敛即停。"""
    actions = []
    cur = io.open(path, encoding="utf-8").read()
    for _ in range(max_iter):
        r = gate_source(cur, os.path.basename(path))
        syn = [i for i in r["issues"] if i["code"] in ("SYN_STRAY_END","SYN_CROSS_END","SYN_UNCLOSED")]
        if not syn: break
        lines = cur.split("\n")
        # 优先处理"交叉/游离"：在报错行前插入最近开块的闭合词
        only_var = os.environ.get("DL_FIX_ONLY_VAR","1") == "1"
        tgt = next((i for i in syn if i["code"] == "SYN_CROSS_END"), None)
        if tgt and only_var and "METHOD" in tgt["detail"] or (tgt and only_var and "PROPERTY" in tgt["detail"]):
            actions.append((tgt["line"], "SKIP(方言待 CI 裁决): " + tgt["detail"][:40])); break
        if tgt:
            closer = {"END_FUNCTION_BLOCK":"END_FUNCTION_BLOCK"}.get("", None)
            m = re.search(r"与最近开块 (\w+)", tgt["detail"])
            if m:
                opener = m.group(1)
                close = FIXABLE.get(opener)
                if not close: break
                pos = max(0, tgt["line"]-1)
                lines.insert(pos, close + "  // R64 结构补齐：缺失的 " + close + "（门禁机械修复）")
                actions.append((tgt["line"], "insert " + close))
            else:
                # 无开块信息的游离 END_*：不擅自删行，留人工
                actions.append((tgt["line"], "MANUAL: stray closer, needs human"))
                break
        else:
            un = syn[0]
            opener = re.match(r"(\S+)", un["detail"]).group(1)
            if only_var and opener != "VAR":
                actions.append((un["line"], "SKIP(方言待 CI 裁决): " + opener)); break
            close = FIXABLE.get(opener)
            if not close: break
            # 未闭合：插到文件末尾前（END_FUNCTION_BLOCK 之前若存在则在其前）
            idx = len(lines)
            for k in range(len(lines)-1, -1, -1):
                if lines[k].strip().upper().startswith("END_FUNCTION_BLOCK"):
                    idx = k; break
            lines.insert(idx, close + "  // R64 结构补齐：缺失的 " + close + "（门禁机械修复）")
            actions.append((un["line"], "insert " + close + " at EOF-block"))
        cur = "\n".join(lines)
    if actions and not dry_run:
        shutil.copy(path, path + ".bak_gate")
        io.open(path, "w", encoding="utf-8").write(cur)
    return actions

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--changed-only", action="store_true")
    ap.add_argument("--hours", type=float, default=3.0)
    ap.add_argument("--file")
    ap.add_argument("--round", default="MANUAL")
    ap.add_argument("--strict-decl", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--json-out")
    ap.add_argument("--fix-structural", action="store_true")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    if a.selftest: return selftest()

    if a.fix_structural:
        reg = load_registry_index()
        files = ([a.file if os.path.isabs(a.file) else os.path.join(LIB, a.file)] if a.file
                 else (collect_changed(a.hours) if a.changed_only
                       else sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))))
        tot = 0
        for p in files:
            acts = fix_structural(p, dry_run=not a.apply)
            if acts:
                tot += len(acts)
                print(("  FIXED " if a.apply else "  DRY   ") + os.path.relpath(p, LIB) +
                      "  " + str(len(acts)) + " 处: " + "; ".join(x[1] for x in acts[:4]))
        print(("APPLIED " if a.apply else "DRY-RUN ") + str(tot) + " structural fixes over " + str(len(files)) + " files")
        return 0

    reg = load_registry_index()
    if a.file:
        files = [a.file if os.path.isabs(a.file) else os.path.join(LIB, a.file)]
    elif a.changed_only:
        files = collect_changed(a.hours)
    else:
        files = sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))
    if not files:
        print("no files to scan"); return 0

    results, blocks = [], 0
    for p in files:
        r = gate_file(p, reg, a.strict_decl)
        results.append(r)
        if r["verdict"] == "BLOCK": blocks += 1
    summary = {
        "round": a.round, "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "total": len(results), "pass": sum(1 for r in results if r["verdict"]=="PASS"),
        "major": sum(1 for r in results if r["verdict"]=="MAJOR"),
        "block": blocks,
        "results": results,
    }
    print("GATE %s: %d files | PASS %d | MAJOR %d | BLOCK %d" %
          (a.round, summary["total"], summary["pass"], summary["major"], summary["block"]))
    for r in results:
        hard = [i for i in r["issues"] if i["level"] in ("BLOCK","MAJOR")]
        if hard:
            print("  %-6s %s" % (r["verdict"], r["file"]))
            for i in hard[:6]:
                print("         L%-4d %-18s %s" % (i["line"], i["code"], i["detail"][:64]))
    out = a.json_out or os.path.join(STG, datetime.date.today().isoformat(), "_gate_%s.json" % a.round)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(summary, io.open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("report ->", out)
    return 1 if blocks else 0

if __name__ == "__main__":
    sys.exit(main())
