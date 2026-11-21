# -*- coding: utf-8 -*-
"""R8 泳道 A 自检：按 machine_check_r7.py 口径对本泳道 6 个文件逐项校验"""
import re, sys, io, glob, os

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

FILES = [
    r"C:\Library\DL_Motion\FB_DL_ElectronicGear.st",
    r"C:\Library\DL_Motion\FB_DL_ElectronicCam.st",
    r"C:\Library\DL_Motion\FB_DL_GantrySyncAxis.st",
    r"C:\Library\DL_Motion\FB_DL_TorqueLimitControl.st",
    r"C:\Library\DL_Motion\FB_DL_MarkPositionLatch.st",
    r"C:\Library\DL_Motion\FC_DL_CalcMoveTime.st",
]

BANNED = ["GVL", "VAR_EXTERNAL", "%I", "%Q", "%M", "POINTER TO", "REFERENCE TO", "__SYSTEM"]
BANNED_RE = [re.compile(r"\bg_\w+", re.IGNORECASE)]
PLACEHOLDER_PAT = [r"TODO", r"FIXME", r"待补", r"待完善", r"//\s*略", r"//\s*同上", r"//\s*[…]{1,3}\s*$"]

POU_PAIRS = {"FUNCTION_BLOCK": "END_FUNCTION_BLOCK", "FUNCTION": "END_FUNCTION",
             "INTERFACE": "END_INTERFACE", "PROGRAM": "END_PROGRAM"}
FB_INSTANCE_TYPES = {"TON", "TOF", "TP", "R_TRIG", "F_TRIG"}


def strip_comment(ln):
    i = ln.find("//")
    return ln if i < 0 else ln[:i]


def in_block_comment(lines):
    flags, inside = [], False
    for ln in lines:
        starts = ln.count("(*")
        ends = ln.count("*)")
        if inside:
            flags.append(True)
            if ends:
                inside = False
        else:
            flags.append(False)
            if starts > ends:
                inside = True
    return flags


def line_net(code):
    inc = len(re.findall(r"\bTHEN\b", code)) - len(re.findall(r"\bELSIF\b", code))
    inc += len(re.findall(r"^\s*CASE\s+\S+", code)) + len(re.findall(r"^\s*FOR\b", code)) \
         + len(re.findall(r"^\s*WHILE\b", code)) + len(re.findall(r"^\s*REPEAT\b", code))
    dec = len(re.findall(r"\bEND_IF\b", code)) + len(re.findall(r"\bEND_CASE\b", code)) \
        + len(re.findall(r"\bEND_FOR\b", code)) + len(re.findall(r"\bEND_WHILE\b", code)) \
        + len(re.findall(r"\bEND_REPEAT\b", code))
    return inc - dec


def analyze(path):
    name = os.path.basename(path)
    fails, notes = [], []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    lines = text.splitlines()
    n = len(lines)
    bcm = in_block_comment(lines)

    banned_hits = []
    for tok in BANNED:
        for i, ln in enumerate(lines, 1):
            if tok.lower() in ln.lower():
                banned_hits.append(f"禁记号 {tok} @L{i}: {ln.strip()[:60]}")
    for rx in BANNED_RE:
        for i, ln in enumerate(lines, 1):
            m = rx.search(ln)
            if m:
                banned_hits.append(f"禁记号 g_前缀 {m.group(0)} @L{i}")
    if banned_hits:
        fails.extend(banned_hits[:10])
    notes.append("禁记号=0" if not banned_hits else f"禁记号={len(banned_hits)}")

    ph = []
    for pat in PLACEHOLDER_PAT:
        for m in re.finditer(pat, text, re.IGNORECASE if pat in ("TODO", "FIXME") else 0):
            li = text[:m.start()].count("\n") + 1
            ph.append(f"占位符 {pat} @L{li}")
    if ph:
        fails.extend(ph[:10])
    notes.append("占位符=0" if not ph else f"占位符={len(ph)}")

    counts = {}
    for kw, endk in POU_PAIRS.items():
        c1 = len(re.findall(rf"^\s*{kw}\b", text, re.MULTILINE))
        c2 = len(re.findall(rf"^\s*{endk}\b", text, re.MULTILINE))
        counts[kw] = (c1, c2)
        if c1 != c2:
            fails.append(f"{kw}({c1}) 与 {endk}({c2}) 不成对")
    notes.append("终结符 " + " ".join(f"{k}={v[0]}/{v[1]}" for k, v in counts.items() if v[0] or v[1]))

    c_t = len(re.findall(r"^\s*TYPE\s+\w+", text, re.MULTILINE))
    c_et = len(re.findall(r"^\s*END_TYPE", text, re.MULTILINE))
    if c_t != c_et:
        fails.append(f"TYPE({c_t}) 与 END_TYPE({c_et}) 不成对")
    notes.append(f"TYPE={c_t}/{c_et}")

    last = next((l for l in reversed(lines) if l.strip()), "")
    first_pou = None
    for i, ln in enumerate(lines, 1):
        if bcm[i - 1]:
            continue
        s = ln.strip()
        for kw in ("FUNCTION_BLOCK", "INTERFACE", "FUNCTION", "PROGRAM"):
            if re.match(rf"^{kw}\b", s):
                first_pou = (kw, i)
                break
        if first_pou:
            break
    if first_pou:
        kw, li = first_pou
        expect = POU_PAIRS[kw]
        if last.strip() != expect:
            fails.append(f"末行 {last.strip()!r} ≠ {expect}（首 POU {kw}@L{li}）")
        notes.append(f"末行={last.strip()}")
    else:
        fails.append("未找到 POU 起始关键字")

    rev = re.findall(r"IF\s+bInit\s+OR\s+bTrack", text)
    if rev:
        fails.append(f"反序首扫命中 {len(rev)} 处（R19 禁止）")

    case_fail, case_stack = [], []
    for i, ln in enumerate(lines, 1):
        if bcm[i - 1]:
            continue
        code = strip_comment(ln)
        cs = code.strip()
        if re.match(r"^CASE\s+\S+", cs):
            case_stack.append([i, 0, False])
            continue
        if not case_stack:
            continue
        top = case_stack[-1]
        if re.match(r"^ELSE\b", cs) and top[1] == 0:
            top[2] = True
        top[1] += line_net(code)
        if top[1] < 0:
            top[1] = 0
        if re.match(r"^END_CASE", cs):
            if not top[2]:
                case_fail.append(f"CASE@L{top[0]} 缺 ELSE")
            case_stack.pop()
    for f_ in case_fail:
        fails.append(f_)
    notes.append(f"CASE 数={len(re.findall(r'^CASE', text, re.MULTILINE))} ELSE 齐全={'是' if not case_fail else '否'}")

    real_vars, fb_instances, decl_issues = set(), {}, []
    var_depth, pou_stack = 0, []
    for i, ln in enumerate(lines, 1):
        if bcm[i - 1]:
            continue
        code = strip_comment(ln)
        cs = code.strip()
        if not cs:
            continue
        if re.match(r"^(FUNCTION_BLOCK|FUNCTION|PROGRAM)\b", cs):
            pou_stack = ["FB"]
        elif re.match(r"^INTERFACE\b", cs):
            pou_stack = ["IFC"]
        elif re.match(r"^METHOD\s+\w+", cs):
            pou_stack.append("METHOD")
        elif re.match(r"^PROPERTY\s+\w+", cs):
            pou_stack.append("PROPERTY")
        elif re.match(r"^END_(FUNCTION_BLOCK|FUNCTION|PROGRAM|INTERFACE)\b", cs):
            pou_stack = []
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_ACCESS|_CONFIG)?\b", cs):
            var_depth += 1
            continue
        if re.match(r"^END_VAR\b", cs):
            var_depth -= 1
            continue
        if var_depth > 0:
            if ":" in cs:
                if "//" not in ln:
                    decl_issues.append(f"声明行缺双语注释 @L{i}: {cs[:56]}")
                m = re.match(r"^([A-Za-z_]\w*)\s*(,[^:]*)?:\s*([A-Za-z_][\w\.]*)", cs)
                if m:
                    vname, vtype = m.group(1), m.group(3)
                    if vtype in ("REAL", "LREAL"):
                        real_vars.add(vname)
                    if vtype in FB_INSTANCE_TYPES:
                        fb_instances[vname] = vtype
    if decl_issues:
        fails.append(f"双语注释缺 {len(decl_issues)} 处: " + "; ".join(decl_issues[:4]))
    notes.append("声明注释=100%" if not decl_issues else f"声明注释缺 {len(decl_issues)}")

    inst_bad, inst_hits = [], []
    if fb_instances:
        in_var, body_depth = False, 0
        for i, ln in enumerate(lines, 1):
            if bcm[i - 1]:
                continue
            code = strip_comment(ln)
            cs = code.strip()
            if re.match(r"^(FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY)\b", cs):
                body_depth = 0
                continue
            if re.match(r"^END_(FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY)\b", cs):
                body_depth = 0
                continue
            if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_ACCESS|_CONFIG)?\b", cs):
                in_var = True
                continue
            if re.match(r"^END_VAR\b", cs):
                in_var = False
                continue
            if in_var:
                continue
            body_depth += line_net(code)
            if body_depth < 0:
                body_depth = 0
            for iname in fb_instances:
                if re.search(rf"\b{re.escape(iname)}\s*\(", code):
                    inst_hits.append((iname, i, body_depth))
                    if body_depth > 0:
                        inst_bad.append(f"实例 {iname} 调用于分支内 depth={body_depth} @L{i}")
        if inst_bad:
            fails.extend(inst_bad[:6])
        notes.append(f"实例刷新 {len(inst_hits)} 处{'全无条件' if not inst_bad else ' 有分支内'}")
    else:
        notes.append("无 TON/TRIG/TP 实例")

    flt_bad = []
    if real_vars:
        for i, ln in enumerate(lines, 1):
            if bcm[i - 1]:
                continue
            code = strip_comment(ln)
            for m in re.finditer(r"(?<![<>=:!])(<>|=)(?![=>])", code):
                lm = re.search(r"([A-Za-z_]\w*)\s*$", code[:m.start()])
                rm = re.match(r"\s*([A-Za-z_]\w*)", code[m.end():])
                lid = lm.group(1) if lm else None
                rid = rm.group(1) if rm else None
                if lid not in real_vars and rid not in real_vars:
                    continue
                if lid is not None and lid == rid and lid in real_vars:
                    continue
                ctx = code[max(0, m.start() - 24):m.start()].strip()[-24:]
                flt_bad.append(f"浮点判等 {m.group(1)!r} @L{i}: …{ctx} {m.group(1)} {rid or '<num>'}")
    if flt_bad:
        fails.extend(flt_bad[:6])
    notes.append("浮点判等=0" if not flt_bad else f"浮点判等={len(flt_bad)}")

    head = "\n".join(lines[:95])
    if ("开源溯源" not in head) and ("Origin" not in head):
        fails.append("文件头缺「开源溯源/Origin」字段")

    r21 = []
    for i, ln in enumerate(lines, 1):
        if bcm[i - 1]:
            continue
        code = strip_comment(ln)
        m = re.match(r"^\s*b(Error|Fault)\s*:=\s*(.+)", code)
        if m and re.search(r"16#[0-9A-Fa-f]{4}_01[0-9A-Fa-f]{2}", m.group(2)):
            r21.append(f"bError/bFault 派生混入信息级码 @L{i}")

    # 行数区间
    if n < 300 or n > 600:
        fails.append(f"行数 {n} 超出 300~600 区间")
    notes.append(f"行数={n}")

    codes = sorted(set(m.group(1).upper() for m in re.finditer(r"16#(0004_[0-9A-Fa-f]{4})", text)))
    return dict(name=name, n=n, notes=notes, fails=fails, ok=len(fails) == 0, codes=codes)


all_ok = True
total = 0
for p in FILES:
    if not os.path.exists(p):
        print(f"{os.path.basename(p):34s}  [未生成]")
        all_ok = False
        continue
    r = analyze(p)
    all_ok &= r["ok"]
    total += r["n"]
    print(f"{r['name']:34s} {r['n']:4d}  {'PASS' if r['ok'] else 'FAIL'}")
    print("    " + " | ".join(r["notes"]))
    print("    码位: " + (", ".join(r["codes"]) if r["codes"] else "无"))
    for f_ in r["fails"]:
        print("    [FAIL] " + f_)
print("-" * 100)
print(f"总行数={total}  总结论={'全部 PASS' if all_ok else '存在 FAIL'}")
