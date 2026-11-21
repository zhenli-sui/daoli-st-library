#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""道莅静态语法闸 v0（R46）—— 非真实编译，仅结构性正则/配平检查
检查项：
  G1 VAR/VAR_INPUT/... 与 END_VAR 配对
  G2 IF/FOR/WHILE/CASE/REPEAT + TYPE/STRUCT 与 END_* 配对
  G3 圆括号 / 方括号配平
  G4 语句行尾分号粗查（跨行续表达式不计）
  G5 块注释 (* *) 未闭合 / 行注释与块注释符冲突
  G6 红线：VAR_EXTERNAL / VAR_GLOBAL / %I %Q %M 物理地址
"""
import io, os, re


def strip_comments(src):
    issues, out = [], []
    i, n, in_block = 0, len(src), False
    while i < n:
        two = src[i:i + 2]
        if not in_block and two == "//":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if not in_block and two == "(*":
            in_block = True
            i += 2
            out.append(" ")
            continue
        if in_block and two == "*)":
            in_block = False
            i += 2
            continue
        if in_block:
            out.append("\n" if src[i] == "\n" else " ")
            i += 1
            continue
        out.append(src[i])
        i += 1
    if in_block:
        issues.append("G5 块注释 (* 未闭合")
    return "".join(out), issues


CONT_TOK = re.compile(r"^(AND|OR|XOR|THEN|DO|TO|BY|ELSE|\)|\]|\.|\+|-|\*|/|&|:|:=|<|>|=|,)")


def _is_continuation(cur, nxt):
    """cur 为本行（已去注释 strip），nxt 为下一非空行；判定是否跨行续写"""
    if re.search(r"(\+|-|\*|/|&|,|\()$", cur):
        return True
    if CONT_TOK.match(nxt or ""):
        return True
    return False


def gate_file(path):
    src = io.open(path, encoding="utf-8", errors="replace").read()
    code, issues = strip_comments(src)
    up = code.upper()

    # G6 红线
    if re.search(r"\bVAR_EXTERNAL\b", up):
        issues.append("G6 红线：出现 VAR_EXTERNAL")
    if re.search(r"\bVAR_GLOBAL\b", up):
        issues.append("G6 红线：出现 VAR_GLOBAL")
    if re.search(r"%[IQMW][XBWDL]?\d", code):
        issues.append("G6 红线：出现 %I/%Q/%M 物理地址")

    # G3 括号
    for a, b in (("(", ")"), ("[", "]")):
        if code.count(a) != code.count(b):
            issues.append("G3 括号不配平：%s=%d %s=%d" % (a, code.count(a), b, code.count(b)))

    # G1 VAR 配对
    nvar = len(re.findall(r"\bVAR(_INPUT|_OUTPUT|_IN_OUT|_GLOBAL|_TEMP|_STAT)?\b", up))
    nend = len(re.findall(r"\bEND_VAR\b", up))
    if nvar != nend:
        issues.append("G1 VAR 块不配对：开头 %d / END_VAR %d" % (nvar, nend))

    # G2 结构配对
    for kw, endkw in (("IF", "END_IF"), ("FOR", "END_FOR"), ("WHILE", "END_WHILE"),
                      ("CASE", "END_CASE"), ("REPEAT", "END_REPEAT"),
                      ("TYPE", "END_TYPE"), ("STRUCT", "END_STRUCT")):
        opens = len(re.findall(r"(?<![_A-Z0-9])%s(?![_A-Z0-9])" % kw, up))
        closes = len(re.findall(r"\b%s\b" % endkw, up))
        if opens != closes:
            issues.append("G2 %s/%s 不配对：%d / %d" % (kw, endkw, opens, closes))

    # G4 分号粗查（跳过跨行续写）
    lines = code.split("\n")
    miss = []
    for i, ln in enumerate(lines):
        t = ln.strip()
        if not t or not re.match(r"^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*\s*:=", t) or t.endswith(";"):
            continue
        nxt = ""
        for j in range(i + 1, min(i + 4, len(lines))):
            if lines[j].strip():
                nxt = lines[j].strip()
                break
        if not _is_continuation(t, nxt):
            miss.append(i + 1)
    if miss:
        issues.append("G4 疑似缺语句分号，行号 %s" % ",".join(map(str, miss[:8])))

    return src, issues


def pick_samples(folder, n=5):
    st = [os.path.join(folder, x) for x in os.listdir(folder) if x.endswith(".st")]
    st.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    prefer = ["FB_DL_SingleAxis.st", "FB_DL_AxisDualFeedbackGuard.st",
              "FB_DL_ElectronicCam.st", "FB_DL_AxisHomingSeq.st"]
    seen, out = set(), []
    for p in st[:2]:                      # 最近新增 2 件
        if p not in seen:
            seen.add(p); out.append(p)
    for nm in prefer:                     # 核心样本
        for p in st:
            if os.path.basename(p) == nm and p not in seen:
                seen.add(p); out.append(p)
                break
    for p in st:
        if len(out) >= n:
            break
        if p not in seen:
            seen.add(p); out.append(p)
    return out[:n]


def run(folder, n=5):
    res = []
    for p in pick_samples(folder, n):
        src, issues = gate_file(p)
        res.append({"file": os.path.basename(p), "lines": len(src.split("\n")),
                    "issues": issues})
    return res


if __name__ == "__main__":
    for r in run(r"C:\Library\DL_Motion"):
        print(r["file"], r["lines"], "OK" if not r["issues"] else r["issues"])
