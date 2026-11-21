# -*- coding: utf-8 -*-
"""全库静态审计（R28 注释不可嵌套 / R29 赋值目标声明性）
用法：python audit_library_r9.py
R30 码位唯一性由终审脚本按码表台账核对，本脚本仅输出共用码位信息。
"""
import re, sys, io, os, glob, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
LIB = r"C:\Library"

R9_SET = {
    "FB_DL_FifoBuffer.st", "FB_DL_ArraySearchFirst.st", "FC_DL_BinarySearchLReal.st",
    "FB_DL_ToleranceWindow.st", "FC_DL_LimitClassify.st", "FC_DL_TempUnitConvert.st",
    "FC_DL_BcdToWord.st", "FC_DL_WordToBcd.st", "FC_DL_WordBitPack.st",
    "FB_DL_MonthWindowCheck.st", "FB_DL_PresetCounterSat.st", "FB_DL_SuperimposedMove.st",
    "I_DL_StepperOpenLoop.st", "FB_DL_PulseDirStepper.st", "FB_DL_ModbusPollMaster.st",
    "FB_DL_AndonCallSystem.st",
}

KW = {"IF", "THEN", "ELSE", "ELSIF", "END_IF", "CASE", "OF", "END_CASE", "FOR", "TO", "BY",
      "END_FOR", "WHILE", "DO", "END_WHILE", "REPEAT", "UNTIL", "END_REPEAT", "EXIT",
      "RETURN", "CONTINUE", "AND", "OR", "XOR", "NOT", "MOD", "TRUE", "FALSE"}


def strip_comments(text):
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


def nested_comment_risk(text):
    hits, inside, ln = [], False, 1
    for line in text.splitlines():
        if inside and "(*" in line:
            hits.append((ln, line.strip()[:80]))
        s, e = line.count("(*"), line.count("*)")
        if not inside and s > e:
            inside = True
        elif inside and e:
            inside = False
        ln += 1
    return hits


def r29_check(text):
    """未声明赋值目标：排除函数/方法/属性名、形参传值（括号内）"""
    code = strip_comments(text)
    lines = code.splitlines()
    decl = set(re.findall(r"^\s*(?:FUNCTION|METHOD|PROPERTY)\s+([A-Za-z_]\w*)", code, re.MULTILINE))
    in_var, paren, hits = False, 0, []
    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_STAT|_TEMP|_CONSTANT|_ACCESS)?\b", s):
            in_var = True
            continue
        if re.match(r"^END_VAR\b", s):
            in_var, paren = False, 0
            continue
        if in_var:
            m = re.match(r"^([A-Za-z_]\w*)\s*(?:,\s*([A-Za-z_]\w*))?\s*:", s)
            if m:
                for g in m.groups():
                    if g:
                        decl.add(g)
            continue
        was_in_call = paren > 0
        paren = max(0, paren + s.count("(") - s.count(")"))
        m = re.match(r"^([A-Za-z_]\w*)\s*:=", s)
        if not m or was_in_call:
            continue
        nm = m.group(1)
        if nm.upper() in KW or nm in decl:
            continue
        hits.append((i, nm, s[:70]))
    return hits


def main():
    files = sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))
    r28, r29 = [], []
    seg = collections.defaultdict(set)
    for p in files:
        text = open(p, "rb").read().decode("utf-8")
        nm = os.path.basename(p)
        r28 += [f"{nm}:L{ln} {ctx}" for ln, ctx in nested_comment_risk(text)]
        if nm in R9_SET:
            r29 += [f"{nm}:L{ln} {v}  ← {ctx}" for ln, v, ctx in r29_check(text)]
        for m in re.finditer(r"16#[0-9A-Fa-f]{4}_[0-9A-Fa-f]{4}", text):
            v = m.group(0).upper()
            if not v.endswith("_0000"):
                seg[v].add(nm)

    print(f"扫描文件数：{len(files)}（R29 仅审 R9 新增 16 件）")
    print(f"\n[R28] 嵌套注释风险：{len(r28)} 处")
    for x in r28[:10]:
        print("   " + x)
    print(f"\n[R29] 未声明赋值目标：{len(r29)} 处")
    for x in r29[:10]:
        print("   " + x)
    dup = {k: sorted(v) for k, v in seg.items() if len(v) > 1}
    print(f"\n[R30-信息] 跨文件共用码位 {len(dup)} 个（共用属设计内；族内撞码由终审逐码核对）")
    bad = len(r28) + len(r29)
    print(f"\n结论：{'全部通过' if bad == 0 else f'{bad} 项待处理'}")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
