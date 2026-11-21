# -*- coding: utf-8 -*-
"""道莅库 R11 红线自检机检（9 项）

用法：
    python redline_check_r11.py <file1.st> [file2.st ...]
    python redline_check_r11.py DL_Base/FB_DL_XXX.st --quiet

输出：
    先打印 JSON 数组，元素结构 = {file, lines, defects:[{rule, line, msg}], pass}
    再打印人读汇总（--quiet 可关闭）
    退出码：全部 pass 返回 0，否则 1

机检 9 项（前 7 项对应 coding-standard 的 7 项红线，8/9 为 R31/R9 增量）：
    R1 禁用记号       全局变量表缩写 / 外部变量声明 / 物理地址百分号前缀 / 指针 / 厂商对象
    R2 占位符        未完成标记、单独成行的省略号、中文简写占位
    R3 终结符成对     FUNCTION_BLOCK / FUNCTION / INTERFACE / TYPE / PROGRAM
    R4 双语同行注释   声明区每行须带 // 注释，且注释同时含中文与 ASCII 英文
    R5 CASE 兜底      每个 CASE 必须有自己的 ELSE（IF 的 ELSE 不算）
    R6 注释不可嵌套   (* ... (* ... *) 形式
    R7 赋值前先声明   := 左侧根标识符必须出现在声明区或 POU 结果名中
    R8 枚举→CASE     ENUM 成员与 CASE 标签双向覆盖（提示级，只报告不判 fail）
    R9 文件完整性     行数、结尾闭合、悬空终结符

注意：R1 的禁记号正则全部用字符串拼接构造（如 "GV" + "L_"），
      避免脚本自身被同一规则误报；本脚本可直接对自己跑一遍验证。
"""

import sys
import os
import re
import json

# ----------------------------------------------------------------------------
# 0. 编码与常量
# ----------------------------------------------------------------------------

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

PCT = chr(37)          # 百分号，拼接构造避免脚本自身命中物理地址规则
DOT = "."
CRLF = "\r\n"

CJK_RE = re.compile(r"[\u4e00-\u9fff]")
ASCII_ALPHA_RE = re.compile(r"[A-Za-z]")

VAR_BLOCK_RE = re.compile(
    r"^\s*VAR(_INPUT|_OUTPUT|_IN_OUT|_STAT|_TEMP|_CONSTANT|_ACCESS|_GLOBAL|_CONFIG)?\s*$", re.I)
END_VAR_RE = re.compile(r"^\s*END_VAR\b", re.I)
DECL_LINE_RE = re.compile(
    r"^([A-Za-z_]\w*)(\s*,\s*[A-Za-z_]\w*)*(?:\s+AT\s+\S+)?\s*:\s*\S")
ENUM_MEMBER_RE = re.compile(r"^\s*([A-Za-z_]\w*)\s*:=")
TYPE_HEAD_RE = re.compile(r"^\s*TYPE\s+([A-Za-z_]\w*)\s*:", re.I)
END_TYPE_RE = re.compile(r"^\s*END_TYPE\b", re.I)

POU_OPEN = {
    "FUNCTION_BLOCK": "END_FUNCTION_BLOCK",
    "FUNCTION": "END_FUNCTION",
    "INTERFACE": "END_INTERFACE",
    "PROGRAM": "END_PROGRAM",
    "TYPE": "END_TYPE",
}

# 合法的「终结符之后可能出现」的新构造头（CODESYS 允许 METHOD / PROPERTY 附在 POU 之后）
NEXT_CONSTRUCT_RE = re.compile(
    r"^\s*(?:\{[^}]*\}\s*)*(FUNCTION_BLOCK|FUNCTION|INTERFACE|PROGRAM|TYPE|METHOD|PROPERTY|"
    r"VAR_GLOBAL|VAR_CONFIG|ACTION|TRANSITION)\b", re.I)

# ----------------------------------------------------------------------------
# 1. R1 禁记号表（字符串拼接构造，防自伤）
# ----------------------------------------------------------------------------

TBL_ABBR_PAT = r"\bGV" + r"L_\w+"
GLOBAL_VAR_PAT = r"(?<![A-Za-z0-9_])g" + r"_\w+"
EXT_DECL_PAT = r"\bVAR_" + r"EXTERNAL\b"
PHYS_ADDR = re.escape(PCT) + r"(?:[IQM]|I[XBWD]|Q[XBWD]|M[XBWD]|MW|MD)\d"
PTR_KW = r"\bPOINTER" + r"\s+TO\b"
REF_KW = r"\bREFERENCE" + r"\s+TO\b"
VENDOR_KW = r"__SY" + r"STEM\b|\bSys" + r"[A-Z]\w+|\bTc" + r"[A-Z]\w+|\bSM3_\w+"

BANNED = [
    ("GV" + "L_TABLE", re.compile(TBL_ABBR_PAT, re.I), "命中全局变量表缩写（GVL 前缀）"),
    ("GLOBAL_VAR", re.compile(GLOBAL_VAR_PAT), "命中全局变量前缀（g_）"),
    ("VAR_" + "EXTERNAL", re.compile(EXT_DECL_PAT, re.I), "命中外部变量声明关键字"),
    ("PHYS_ADDR", re.compile(PHYS_ADDR, re.I), "命中物理地址（百分号 I/Q/M 前缀）"),
    ("POINTER", re.compile(PTR_KW, re.I), "命中指针声明（跨平台行为不一致）"),
    ("REFERENCE", re.compile(REF_KW, re.I), "命中引用声明（本库禁用）"),
    ("VENDOR", re.compile(VENDOR_KW), "命中厂商专有对象"),
]

# ----------------------------------------------------------------------------
# 2. R2 占位符表（同样拼接构造）
# ----------------------------------------------------------------------------

TODO_W = "TO" + "DO"
FIXME_W = "FIX" + "ME"
TBD_W = "TB" + "D"
# 任意位置命中：英文标记 + 省略号
PLACEHOLDER_ANY = [
    (re.compile(r"\b" + TODO_W + r"\b", re.I), "占位符 " + TODO_W),
    (re.compile(r"\b" + FIXME_W + r"\b", re.I), "占位符 " + FIXME_W),
    (re.compile(r"\b" + TBD_W + r"\b", re.I), "占位符 " + TBD_W),
    (re.compile(r"^\s*(?://\s*)?" + r"\." + r"{3,}\s*$"), "整行省略号（未写完）"),
    (re.compile(r"^\(\*\s*" + r"\." + r"{3,}\s*\*\)\s*$"), "块注释内整行省略号（未写完）"),
    (re.compile(r"\." + r"{3}\s*$"), "行尾省略号（未写完）"),
]
# 仅当「注释正文整段就是这个词」才算占位（避开正文里正常行文用词，如「W2 同上 nDay=31」「周号待定」）
PLACEHOLDER_EXACT = [
    ("同" + "上", "整段注释仅为「同" + "上」占位"),
    ("略", "整段注释仅为「略」占位"),
    ("待" + "补", "整段注释仅为「待" + "补」占位"),
    ("待" + "完" + "善", "整段注释仅为「待" + "完" + "善」占位"),
    ("待" + "实" + "现", "整段注释仅为「待" + "实" + "现」占位"),
]

# ----------------------------------------------------------------------------
# 3. 词法辅助
# ----------------------------------------------------------------------------


def read_text(path):
    raw = open(path, "rb").read()
    for enc in ("utf-8-sig", "utf-8", "gbk", "latin-1"):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace"), "utf-8(replace)"


def strip_comments(text):
    """把注释替换为等长空白（保留换行与列位置）"""
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


def mask_block_comments_only(text):
    """只屏蔽 (* *) 块注释，保留 // 行注释（R1 需要区分代码区与注释区）"""
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
        out.append(text[i])
        i += 1
    return "".join(out)


def code_only_lines(text):
    """返回 [(lineno, code_line_no_comments)]"""
    masked = strip_comments(text).splitlines()
    return list(enumerate(masked, 1))


def line_comment(raw_line):
    """返回该行 // 注释文本（不含 //），无则 None。跳过 (* *) 块内的 //"""
    # 简化：先看是否存在 //；若 // 出现在 (* 之前则认为是行注释
    j = raw_line.find("//")
    if j < 0:
        return None
    k = raw_line.find("(*")
    if 0 <= k < j:
        return None
    return raw_line[j + 2:]


# ----------------------------------------------------------------------------
# 4. 单项检查
# ----------------------------------------------------------------------------


def check_r1(text, defects):
    """禁用记号：代码区命中=缺陷；注释区命中=提示"""
    masked = mask_block_comments_only(text)
    code_lines = []
    for ln, line in enumerate(masked.splitlines(), 1):
        # 去掉 // 之后的内容，得到纯代码
        j = line.find("//")
        code_lines.append((ln, line if j < 0 else line[:j], line))
    for ln, code, full in code_lines:
        for tag, pat, msg in BANNED:
            for m in pat.finditer(code):
                defects.append(("R1", ln, "%s：%r" % (msg, m.group(0)[:40])))
    # 注释区提及（提示级，不计 fail）
    for ln, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("*") or "//" in line or "(*" in line:
            for tag, pat, msg in BANNED:
                if pat.search(line) and not pat.search(
                        (code_lines[ln - 1][1] if ln - 1 < len(code_lines) else "")):
                    defects.append(("R1-INFO", ln, "注释区提及禁记号（仅提示）：%s" % msg))
                    break


def check_r2(text, defects):
    punct = "。.，,；;：:！!？?、 \t"
    for ln, line in enumerate(text.splitlines(), 1):
        for pat, msg in PLACEHOLDER_ANY:
            if pat.search(line):
                defects.append(("R2", ln, msg))
        cmt = line_comment(line)
        body = cmt if cmt is not None else strip_comments(line)
        body = body.strip().strip(punct).strip()
        for word, msg in PLACEHOLDER_EXACT:
            if body == word:
                defects.append(("R2", ln, msg))
                break


def check_r3(text, defects):
    code = strip_comments(text)
    for opener, closer in POU_OPEN.items():
        if opener == "FUNCTION":
            o = len(re.findall(r"(?<!END_)" + r"\bFUNCTION\b(?!\s*_BLOCK)", code))
            c = len(re.findall(r"\bEND_FUNCTION\b(?!\s*_BLOCK)", code))
        elif opener == "TYPE":
            o = len(re.findall(r"^\s*TYPE\b", code, re.M))
            c = len(re.findall(r"^\s*END_TYPE\b", code, re.M))
        else:
            o = len(re.findall(r"^\s*" + opener + r"\b", code, re.M))
            c = len(re.findall(r"\b" + closer + r"\b", code))
        if o != c:
            line = first_line_of(code, opener)
            defects.append(("R3", line,
                            "%s 与 %s 数量不匹配（%d 开 / %d 闭）" % (opener, closer, o, c)))


def first_line_of(code, kw):
    for ln, line in enumerate(code.splitlines(), 1):
        if re.match(r"^\s*" + kw + r"\b", line, re.I):
            return ln
    return 0


def check_r4(text, defects):
    """声明区每行必须带 // 注释，且注释同时含中文与 ASCII 英文"""
    lines = text.splitlines()
    in_var, in_enum, depth_type = False, False, 0
    for ln, raw in enumerate(lines, 1):
        code = strip_comments(raw).strip()
        if not code:
            continue
        if VAR_BLOCK_RE.match(code):
            in_var = True
            continue
        if END_VAR_RE.match(code):
            in_var = False
            continue
        m = TYPE_HEAD_RE.match(code)
        if m:
            depth_type += 1
            in_enum = "(" in code or "(" in "".join(lines[ln - 1:ln + 1])
            continue
        if END_TYPE_RE.match(code):
            depth_type = max(0, depth_type - 1)
            in_enum = False
            continue

        is_decl = False
        if in_var and DECL_LINE_RE.match(code):
            is_decl = True
        elif in_enum and ENUM_MEMBER_RE.match(code):
            is_decl = True
        if not is_decl:
            continue
        # 只有语句完整结束的行才判（避开跨行声明续行）
        tail = code.rstrip()
        if not (tail.endswith(";") or tail.endswith(",") or tail.endswith(")") or tail.endswith("]")):
            continue

        cmt = line_comment(raw)
        if cmt is None:
            defects.append(("R4", ln, "声明行缺 // 同行注释：%s" % code[:48]))
            continue
        has_cn = bool(CJK_RE.search(cmt))
        has_en = bool(ASCII_ALPHA_RE.search(cmt))
        if not has_cn and not has_en:
            defects.append(("R4", ln, "注释既无中文也无英文：%s" % cmt.strip()[:40]))
        elif not has_cn:
            defects.append(("R4", ln, "注释缺中文：%s" % cmt.strip()[:40]))
        elif not has_en:
            defects.append(("R4", ln, "注释缺 ASCII 英文：%s" % cmt.strip()[:40]))


def check_r5(text, defects):
    """CASE 必须有自己的 ELSE（IF 的 ELSE 不顶替）"""
    code = strip_comments(text)
    stack = []          # 元素：{"kind": "CASE"/"IF", "line": n, "has_else": bool}
    for ln, line in enumerate(code.splitlines(), 1):
        for tok in re.finditer(r"\b(CASE|END_CASE|IF|END_IF|ELSE|ELSIF)\b", line, re.I):
            t = tok.group(1).upper()
            if t == "CASE":
                stack.append({"kind": "CASE", "line": ln, "else": False})
            elif t == "IF":
                stack.append({"kind": "IF", "line": ln, "else": False})
            elif t == "ELSE":
                if stack and stack[-1]["kind"] in ("CASE", "IF"):
                    stack[-1]["else"] = True
            elif t == "END_IF":
                for i in range(len(stack) - 1, -1, -1):
                    if stack[i]["kind"] == "IF":
                        del stack[i:]
                        break
            elif t == "END_CASE":
                for i in range(len(stack) - 1, -1, -1):
                    if stack[i]["kind"] == "CASE":
                        if not stack[i]["else"]:
                            defects.append(("R5", stack[i]["line"],
                                            "CASE 缺 ELSE 兜底分支"))
                        del stack[i:]
                        break
    for item in stack:
        if item["kind"] == "CASE":
            defects.append(("R5", item["line"], "CASE 未闭合（缺 END_CASE）"))


def check_r6(text, defects):
    inside = False
    for ln, line in enumerate(text.splitlines(), 1):
        i = 0
        while i < len(line):
            if not inside and line.startswith("(*", i):
                inside, i = True, i + 2
                continue
            if inside:
                if line.startswith("(*", i):
                    defects.append(("R6", ln, "块注释内再次出现 (* ，构成嵌套注释"))
                    i += 2
                    continue
                if line.startswith("*)", i):
                    inside, i = False, i + 2
                    continue
            i += 1


def collect_declared(text):
    """收集声明区标识符 + POU 结果名 + 结构体成员类型映射"""
    code = strip_comments(text)
    declared, var_type = set(), {}
    in_var = False
    for line in code.splitlines():
        s = line.strip()
        if VAR_BLOCK_RE.match(s):
            in_var = True
            continue
        if END_VAR_RE.match(s):
            in_var = False
            continue
        if not in_var:
            continue
        m = re.match(r"^([A-Za-z_]\w*)((?:\s*,\s*[A-Za-z_]\w*)*)"
                     r"(?:\s+AT\s+\S+)?\s*:\s*([A-Za-z_]\w*)", s)
        if not m:
            continue
        names = [m.group(1)] + re.findall(r"[A-Za-z_]\w*", m.group(2))
        for nm in names:
            declared.add(nm)
            var_type[nm] = m.group(3)
    for m in re.finditer(r"^\s*(?:FUNCTION|METHOD|PROPERTY)\s+([A-Za-z_]\w*)", code, re.M):
        declared.add(m.group(1))
    for m in re.finditer(r"^\s*(?:FUNCTION_BLOCK|INTERFACE|PROGRAM)\s+([A-Za-z_]\w*)", code, re.M):
        declared.add(m.group(1))
    return declared, var_type


def check_r7(text, defects):
    code = strip_comments(text)
    declared, _ = collect_declared(text)
    kw = {"TRUE", "FALSE"}
    depth = 0
    in_var = False
    for ln, line in enumerate(code.splitlines(), 1):
        s = line.strip()
        if VAR_BLOCK_RE.match(s):
            in_var = True
            continue
        if END_VAR_RE.match(s):
            in_var = False
            continue
        depth_at_start = depth
        depth = max(0, depth + s.count("(") - s.count(")"))
        if in_var:
            continue
        pos = s.find(":=")
        if pos < 0:
            continue
        before = s[:pos]
        # 括号内的 := 是命名实参（fbPin := x），不是赋值目标
        if before.count("(") - before.count(")") + depth_at_start > 0:
            continue
        lhs = before.strip()
        if not lhs or lhs.endswith("(") or lhs.endswith(","):
            continue
        m = re.match(r"^([A-Za-z_]\w*)(\s*(\.\s*[A-Za-z_]\w*|\[[^\]]*\])+)?$", lhs)
        if not m:
            continue
        root = m.group(1)
        if root.upper() in kw:
            continue
        if root not in declared:
            defects.append(("R7", ln, "赋值目标未在声明区找到：%s" % root))


def parse_enums(text):
    """返回 {enum_name: [(member, line)]}

    兼容三种书写：`TYPE X : (` 同行、`TYPE X :` 换行后 `(`（本库主流）、单行枚举。
    """
    code = strip_comments(text)
    enums, cur, pending = {}, None, None
    for ln, line in enumerate(code.splitlines(), 1):
        s = line.strip()
        m = TYPE_HEAD_RE.match(s)
        if m and cur is None and pending is None:
            if re.match(r"^TYPE\s+\w+\s*:\s*STRUCT\b", s, re.I):
                continue
            pending = {"name": m.group(1), "members": []}
            if "(" not in s:
                continue
        if pending is not None:
            if re.match(r"^STRUCT\b", s, re.I):
                pending = None
                continue
            if "(" not in s:
                continue
            # 同行开括号：可能同一行就闭合
            inline = s[s.find("(") + 1:]
            if ")" in inline:
                for part in inline[:inline.find(")")].split(","):
                    mm = re.match(r"\s*([A-Za-z_]\w*)\s*:=", part)
                    if mm:
                        pending["members"].append((mm.group(1), ln))
                enums[pending["name"]] = pending["members"]
                pending = None
                continue
            cur, pending = pending, None
            rest = inline
            mm = ENUM_MEMBER_RE.match(rest)
            if mm:
                cur["members"].append((mm.group(1), ln))
            continue
        if cur is not None:
            mm = ENUM_MEMBER_RE.match(s)
            if mm:
                cur["members"].append((mm.group(1), ln))
            if ")" in s:
                enums[cur["name"]] = cur["members"]
                cur = None
    return enums


def check_r8(text, defects):
    """枚举 → CASE 双向完备性（提示级）"""
    enums = parse_enums(text)
    if not enums:
        return
    code = strip_comments(text)
    if not re.search(r"\bCASE\b", code, re.I):
        return
    _, var_type = collect_declared(text)
    lines = code.splitlines()

    for i, line in enumerate(lines):
        if not re.match(r"^\s*CASE\b", line, re.I):
            continue
        sel = re.sub(r"^\s*CASE\b", "", line, flags=re.I)
        sel = re.sub(r"\bOF\b.*$", "", sel, flags=re.I).strip()
        root = re.match(r"^([A-Za-z_]\w*)", sel)
        enum_name = var_type.get(root.group(1)) if root else None
        block, depth, start = [], 0, i
        for j in range(i, len(lines)):
            if re.match(r"^\s*CASE\b", lines[j], re.I):
                depth += 1
            if re.search(r"\bEND_CASE\b", lines[j], re.I):
                depth -= 1
            block.append(lines[j])
            if depth == 0:
                break
        body = "\n".join(block)
        used = set()
        for en in (enums if enum_name is None else [enum_name]):
            if en not in enums:
                continue
            refs = set(re.findall(r"\b" + re.escape(en) + r"\.([A-Za-z_]\w*)", body))
            if not refs:
                member_names = {m for m, _ in enums[en]}
                refs = {w for w in re.findall(r"\b([A-Za-z_]\w*)\b", body) if w in member_names}
                if len(refs) < 2:
                    continue
            used |= refs
            missing = [m for m, _ in enums[en] if m not in refs]
            if missing:
                defects.append(("R8-INFO", start + 1,
                                "CASE 未覆盖枚举 %s 的成员：%s（提示级）"
                                % (en, "、".join(missing))))
            extra = sorted(refs - {m for m, _ in enums[en]})
            if extra:
                defects.append(("R8-INFO", start + 1,
                                "CASE 标签不在枚举 %s 定义内：%s（提示级）"
                                % (en, "、".join(extra))))


def check_r9(text, defects, lines_count):
    lines = text.splitlines()
    if not text.strip():
        defects.append(("R9", 0, "空文件"))
        return
    # 结尾闭合
    last = ""
    for ln in range(len(lines), 0, -1):
        if lines[ln - 1].strip():
            last = lines[ln - 1].rstrip()
            last_ln = ln
            break
    if last and not (last.endswith(";") or last.endswith(")") or last.endswith("*）")
                    or re.match(r"^\s*(END_[A-Z_]+|\})\s*$", last, re.I)):
        defects.append(("R9", last_ln, "文件结尾疑似未闭合：%r" % last[-40:]))
    # 悬空终结符（终结符之后还有游离代码，且不是新构造头）
    masked = strip_comments(text).splitlines()
    for ln in range(len(masked)):
        if not re.match(r"^\s*(END_FUNCTION_BLOCK|END_FUNCTION|END_INTERFACE|"
                        r"END_PROGRAM)\b", masked[ln], re.I):
            continue
        nxt = None
        for k in range(ln + 1, len(masked)):
            s = masked[k].strip()
            if not s or s.startswith("{"):
                continue
            nxt = (k + 1, s)
            break
        if nxt and not NEXT_CONSTRUCT_RE.match(nxt[1]):
            defects.append(("R9", ln + 1,
                            "终结符后存在游离代码（第 %d 行）：%r" % (nxt[0], nxt[1][:40])))
    if lines_count < 5:
        defects.append(("R9", 0, "文件行数异常偏少（%d 行）" % lines_count))



def check_r10(text, defects):
    """R33 枚举成员分隔符语法：成员赋值必须用 `:=`，单冒号 `:` 为 IEC 文法错误（编译阻断）。

    机检盲区实证：parse_enums 的成员正则只认 `:=`，单冒号成员会被静默丢弃，
    导致「枚举少了成员 → CASE 少标签」被误报为 R8 提示而非 R33 硬缺陷。
    """
    code = strip_comments(text).splitlines()
    in_enum = False
    depth = 0
    for ln, line in enumerate(code, 1):
        s = line.strip()
        if not in_enum:
            m = re.match(r"^TYPE\s+\w+\s*:\s*(.*)$", s, re.I)
            if m and not re.match(r"^STRUCT", m.group(1), re.I):
                in_enum = True
                depth = s.count("(") - s.count(")")
                continue
            continue
        # 枚举体内：成员行形如 ident : value（单冒号）
        m = re.match(r"^([A-Za-z_]\w*)\s*:(?!\=)\s*(.+?)\s*(?:,\s*)?$", s)
        if m:
            defects.append(("R10", ln,
                            "枚举成员分隔符笔误：成员 %r 使用单冒号 `:`，IEC 61131-3 要求 `:=`（编译阻断）"
                            % m.group(1)))
        depth += s.count("(") - s.count(")")
        if depth <= 0 or re.match(r"^END_TYPE", s, re.I):
            in_enum = False
            depth = 0


# ----------------------------------------------------------------------------
# 5. 主流程
# ----------------------------------------------------------------------------


def analyze(path):
    text, enc = read_text(path)
    lines_count = len(text.splitlines())
    raw_defects = []
    check_r1(text, raw_defects)
    check_r2(text, raw_defects)
    check_r3(text, raw_defects)
    check_r4(text, raw_defects)
    check_r5(text, raw_defects)
    check_r6(text, raw_defects)
    check_r7(text, raw_defects)
    check_r8(text, raw_defects)
    check_r9(text, raw_defects, lines_count)
    check_r10(text, raw_defects)

    raw_defects.sort(key=lambda d: (d[1], d[0]))
    defects = [{"rule": r, "line": l, "msg": m} for r, l, m in raw_defects]
    hard = [d for d in defects if not d["rule"].endswith("-INFO")]
    # 对外 JSON 严格只保留规范四键（file / lines / defects / pass），其余字段走内部键
    return {
        "file": os.path.basename(path),
        "lines": lines_count,
        "defects": defects,
        "pass": len(hard) == 0,
        "_path": os.path.abspath(path),
        "_encoding": enc,
    }


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("-")]
    quiet = any(a in ("-q", "--quiet") for a in argv[1:])
    if not args:
        print("用法: python redline_check_r11.py <file.st> [more.st ...] [--quiet]")
        return 2
    results = []
    for p in args:
        if not os.path.isfile(p):
            results.append({"file": os.path.basename(p), "lines": 0,
                            "defects": [{"rule": "R0", "line": 0, "msg": "文件不存在"}],
                            "pass": False, "_path": os.path.abspath(p), "_encoding": "-"})
            continue
        results.append(analyze(p))

    public = [{k: v for k, v in r.items() if not k.startswith("_")} for r in results]
    print(json.dumps(public, ensure_ascii=False, indent=2))
    if quiet:
        return 0 if all(r["pass"] for r in results) else 1

    print("")
    print("=" * 72)
    print("R11 红线机检汇总 / Redline Check Summary")
    print("=" * 72)
    rules = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8-INFO", "R9"]
    for r in results:
        cnt = {}
        for d in r["defects"]:
            cnt[d["rule"]] = cnt.get(d["rule"], 0) + 1
        hard = sum(v for k, v in cnt.items() if not k.endswith("-INFO"))
        info = sum(v for k, v in cnt.items() if k.endswith("-INFO"))
        print("%-34s %5d 行  %s  缺陷 %d（提示 %d）"
              % (r["file"], r["lines"], "PASS" if r["pass"] else "FAIL", hard, info))
        for k in rules:
            if cnt.get(k):
                print("      %-9s × %d" % (k, cnt[k]))
    total_files = len(results)
    failed = [r for r in results if not r["pass"]]
    total_hard = sum(1 for r in results for d in r["defects"] if not d["rule"].endswith("-INFO"))
    total_info = sum(1 for r in results for d in r["defects"] if d["rule"].endswith("-INFO"))
    print("-" * 72)
    print("文件 %d 个｜通过 %d｜失败 %d｜硬缺陷 %d｜提示 %d"
          % (total_files, total_files - len(failed), len(failed), total_hard, total_info))
    for r in failed:
        print("  FAIL 路径：%s" % r["_path"])
    print("结论：%s" % ("全部通过，可进入人工终审" if not failed else "存在硬缺陷，禁止入库"))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
