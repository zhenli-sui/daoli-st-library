# -*- coding: utf-8 -*-
"""R45 落盘自检：红线 7 项 + 派单新增（枚举 ⊆ CASE 标签）+ CRLF + 禁用词。
用法：python selfcheck_r45.py <文件1> [文件2 ...]
"""
import sys, re, os

BANNED_WORDS = ["TODO", "FIXME", "placeholder", "待补"]
SELF_NAN = re.compile(r"(f[A-Za-z0-9_]*)\s*<>\s*\1(?![A-Za-z0-9_])")


def strip_comments(text):
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("(*", i):
            j = text.find("*)", i + 2)
            j = n if j < 0 else j + 2
            out.append("\n" * text.count("\n", i, j))
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def check(path):
    raw = open(path, "rb").read()
    text = raw.decode("utf-8")
    errs = []

    lf_only = text.count("\n") - text.count("\r\n")
    if lf_only > 0:
        errs.append("R-CRLF(裸 LF %d 行)" % lf_only)
    if raw[:3] == b"\xef\xbb\xbf":
        errs.append("R-BOM")

    code = strip_comments(text)

    if re.search(r"\bg_[A-Za-z]", code):
        errs.append("R1(g_ 全局访问)")
    if "VAR_EXTERNAL" in code.upper():
        errs.append("R1(VAR_EXTERNAL)")
    if re.search(r"%[IQM][XWBD]?", text):
        errs.append("R2(物理地址)")
    for bad in ("POINTER TO", "REFERENCE TO", "__ISVALIDREF", "__SYSTEM", "Tc2_", "Tc3_", "SM3_"):
        if bad in code:
            errs.append("R3(%s)" % bad)
    if re.search(r"\bAS\s+[A-Z]", code):
        errs.append("R3(AS 方言转换)")

    code = SELF_NAN.sub("NANCHK", code)
    for m in re.finditer(r"(?<![:<>=!])(<>|=)(?![=>:])\s*(f[A-Z][A-Za-z0-9_]*)", code):
        errs.append("R4(浮点判等 %s%s)" % (m.group(1), m.group(2)))

    lines = text.split("\r\n")
    in_var = False
    for ln, line in enumerate(lines, 1):
        s = line.strip()
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_TEMP)?\b", s) or s.startswith("VAR CONSTANT"):
            in_var = True
            continue
        if s.startswith("END_VAR"):
            in_var = False
            continue
        if in_var and s and not s.startswith("//") and "//" not in line:
            errs.append("R5(L%d 声明无同行注释: %s)" % (ln, s[:40]))

    enum_body = re.findall(r"TYPE\s+\w+\s*:\s*\((.*?)\)\s*;\s*END_TYPE", text, re.S)
    members = []
    for body in enum_body:
        for ln in body.split("\n"):
            t = ln.strip()
            if not t or t.startswith("//"):
                continue
            m = re.match(r"^(\w+)\s*:=", t)
            if not m:
                errs.append("R6(枚举成员非 := 写法: %s)" % t[:40])
            else:
                members.append(m.group(1))
            if "//" not in ln:
                errs.append("R6(枚举成员无同行注释: %s)" % t[:40])

    for mem in members:
        if not re.search(r"\b%s\s*:" % mem, code):
            errs.append("R6(枚举成员 %s 无独立 CASE 标签)" % mem)

    for w in BANNED_WORDS:
        if w in text:
            errs.append("R7(禁用词 %s)" % w)

    ls = code.split("\n")
    for i, ln in enumerate(ls):
        if re.search(r"_uFault\s*:=\s*16#(?!0000_0000)", ln):
            win = "\n".join(ls[i:i + 4])
            if "bError" not in win:
                errs.append("R45配对(L%d 码赋值后 3 行无 bError)" % (i + 1))

    case_pos = code.find("\nCASE ")
    decl = set(re.findall(r"^\s*(\w+)\s*:\s*(?:TON|TOF|R_TRIG|F_TRIG|CTU)\s*;", text, re.M))
    for inst in decl:
        m = re.search(r"^\s*%s\s*\(" % inst, code, re.M)
        if not m:
            errs.append("R7(实例 %s 未无条件调用)" % inst)
        elif case_pos > 0 and m.start() > case_pos:
            errs.append("R7(实例 %s 调用在 CASE 之后)" % inst)
    return errs


def main():
    fails = 0
    paths = sys.argv[1:]
    for p in paths:
        errs = check(p)
        name = os.path.basename(p)
        if errs:
            fails += 1
            print("FAIL", name)
            for e in sorted(set(errs))[:12]:
                print("   -", e)
        else:
            print("PASS", name)
    print("\nTOTAL %d files, FAIL %d" % (len(paths), fails))


if __name__ == "__main__":
    main()
