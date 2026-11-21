# -*- coding: utf-8 -*-
"""R10 机检：16 文件 x 7 项编码红线（全文口径）+ R29 赋值目标声明性 + 码位重叠"""
import re, sys, io, os, json, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

BASE = r"C:\Library"
FILES = [
    (r"DL_Base\FC_DL_BitFieldExtract.st", "DL_Base", "FC"),
    (r"DL_Base\FC_DL_WeekOfYearCalc.st", "DL_Base", "FC"),
    (r"DL_Base\FB_DL_BidirectionalCounter.st", "DL_Base", "FB"),
    (r"DL_MathData\FC_DL_SearchMinMax.st", "DL_MathData", "FC"),
    (r"DL_MathData\FC_DL_NthRoot.st", "DL_MathData", "FC"),
    (r"DL_MathData\FC_DL_FactorialSat.st", "DL_MathData", "FC"),
    (r"DL_Algo\FB_DL_SineGenerator.st", "DL_Algo", "FB"),
    (r"DL_Algo\FB_DL_SawtoothGenerator.st", "DL_Algo", "FB"),
    (r"DL_Algo\FC_DL_CoilDiameterCalc.st", "DL_Algo", "FC"),
    (r"DL_Algo\FC_DL_AirDensity.st", "DL_Algo", "FC"),
    (r"DL_Device\I_DL_RfidReader.st", "DL_Device", "I"),
    (r"DL_Device\FB_DL_RfidTagHandler.st", "DL_Device", "FB"),
    (r"DL_Device\FB_DL_AxiolineDiagLatch.st", "DL_Device", "FB"),
    (r"DL_Device\FB_DL_PdiReadScheduler.st", "DL_Device", "FB"),
    (r"DL_Motion\FB_DL_WindingTraverse.st", "DL_Motion", "FB"),
    (r"DL_Process\FB_DL_PickAndPlaceStation.st", "DL_Process", "FB"),
]

BANNED_LITERAL = ["GVL", "VAR_EXTERNAL", "VAR_GLOBAL", "%I", "%Q", "%M", "%X",
                  "%IB", "%QB", "POINTER TO", "REFERENCE TO", "__SYSTEM",
                  "__ISVALIDREF", "AT %"]
BANNED_RE = [("g_ 前缀", re.compile(r"\bg_[A-Za-z0-9_]+"))]
PLACEHOLDER_PAT = [
    (r"\bTODO\b", "TODO"), (r"\bFIXME\b", "FIXME"), (r"\bXXX\b", "XXX"),
    (r"待补", "待补"), (r"待完善", "待完善"), (r"待补充", "待补充"),
    (r"//\s*略", "// 略"), (r"//\s*同上", "// 同上"), (r"//\s*同前", "// 同前"),
    (r"\.\.\.", "..."), (r"…", "…"),
]
POU_PAIRS = {"FUNCTION_BLOCK": "END_FUNCTION_BLOCK", "FUNCTION": "END_FUNCTION",
             "INTERFACE": "END_INTERFACE", "PROGRAM": "END_PROGRAM"}
FB_INSTANCE_TYPES = {"TON", "TOF", "TP", "R_TRIG", "F_TRIG"}
VAR_KW = re.compile(r"^VAR(\s+(CONSTANT|RETAIN|NON_RETAIN|PERSISTENT))?"
                    r"(_INPUT|_OUTPUT|_IN_OUT|_ACCESS|_CONFIG|_STAT|_TEMP)?$")
TIME_LITERAL = re.compile(r"T#[0-9A-Za-z_\.]+")


def strip_cmt(ln):
    i = ln.find("//")
    return ln if i < 0 else ln[:i]


def block_flags(lines):
    flags, inside = [], False
    for ln in lines:
        s, e = ln.count("(*"), ln.count("*)")
        if inside:
            flags.append(True)
            if e:
                inside = False
        else:
            flags.append(False)
            if s > e:
                inside = True
    return flags


def net(code):
    inc = len(re.findall(r"\bTHEN\b", code)) - len(re.findall(r"\bELSIF\b", code))
    inc += len(re.findall(r"^\s*CASE\s+\S+", code))
    inc += len(re.findall(r"^\s*FOR\b", code)) + len(re.findall(r"^\s*WHILE\b", code)) \
        + len(re.findall(r"^\s*REPEAT\b", code))
    dec = len(re.findall(r"\bEND_IF\b", code)) + len(re.findall(r"\bEND_CASE\b", code)) \
        + len(re.findall(r"\bEND_FOR\b", code)) + len(re.findall(r"\bEND_WHILE\b", code)) \
        + len(re.findall(r"\bEND_REPEAT\b", code))
    return inc - dec


def collect_decls(lines, bf):
    """收集声明区标识符：VAR 块内的 name : type，以及 TYPE 块内的结构体成员"""
    names, in_var = set(), 0
    for i, ln in enumerate(lines):
        if bf[i]:
            continue
        cs = strip_cmt(ln).strip()
        if not cs:
            continue
        if VAR_KW.match(cs):
            in_var += 1
            continue
        if re.match(r"^END_VAR$", cs):
            in_var = max(0, in_var - 1)
            continue
        if in_var > 0:
            m = re.match(r"^([A-Za-z_]\w*)\s*(?::|,)", cs)
            if m:
                names.add(m.group(1))
    # TYPE 块内成员（含枚举项）
    in_type = False
    for i, ln in enumerate(lines):
        if bf[i]:
            continue
        cs = strip_cmt(ln).strip()
        if re.match(r"^TYPE\s+\w+", cs):
            in_type = True
            continue
        if re.match(r"^END_TYPE", cs):
            in_type = False
            continue
        if in_type:
            m = re.match(r"^([A-Za-z_]\w*)\s*(?::|=|,)", cs)
            if m:
                names.add(m.group(1))
    # 函数名 / POU 名
    for ln in lines:
        m = re.match(r"^(FUNCTION|FUNCTION_BLOCK)\s+([A-Za-z_]\w*)", strip_cmt(ln).strip())
        if m:
            names.add(m.group(2))
        m = re.match(r"^(METHOD|PROPERTY)\s+([A-Za-z_]\w*)", strip_cmt(ln).strip())
        if m:
            names.add(m.group(2))
    return names


def analyze(rel, cat, kind):
    path = os.path.join(BASE, rel)
    name = os.path.basename(path)
    raw = open(path, "rb").read()
    R = {"name": name, "rel": rel, "cat": cat, "kind": kind, "fails": [], "warn": [], "notes": {}}

    bom = raw[:3] == b"\xef\xbb\xbf"
    try:
        text = raw.decode("utf-8")
        dec_ok = True
    except UnicodeDecodeError as ex:
        dec_ok, text = False, ""
        R["fails"].append(f"UTF-8 解码失败: {ex}")
    if bom:
        R["fails"].append("文件含 UTF-8 BOM")

    lines = text.splitlines()
    bf = block_flags(lines)

    # 1 被禁记号（全文）
    hits = []
    for tok in BANNED_LITERAL:
        for i, ln in enumerate(lines, 1):
            if tok.lower() in ln.lower():
                hits.append(f"禁记号[{tok}] L{i}: {ln.strip()[:70]}")
    for label, rx in BANNED_RE:
        for i, ln in enumerate(lines, 1):
            if bf[i - 1]:
                continue
            m = rx.search(strip_cmt(ln))
            if m:
                hits.append(f"禁记号[{label}] L{i}: {m.group(0)}")
    if hits:
        R["fails"].extend(hits[:10])
    R["notes"]["被禁记号"] = f"{len(hits)} 命中" if hits else "0"

    # 占位符
    ph = []
    for pat, label in PLACEHOLDER_PAT:
        for m in re.finditer(pat, text, re.MULTILINE):
            li = text[:m.start()].count("\n") + 1
            ph.append(f"占位符[{label}] L{li}: {lines[li-1].strip()[:60]}")
    if ph:
        R["fails"].extend(ph[:8])
    R["notes"]["占位符"] = f"{len(ph)} 命中" if ph else "0"

    # 2 终结符成对 + 末行
    pair_issue = []
    for kw, endk in POU_PAIRS.items():
        c1 = len(re.findall(rf"^\s*{kw}\b", text, re.MULTILINE))
        c2 = len(re.findall(rf"^\s*{endk}\b", text, re.MULTILINE))
        R["notes"][kw] = f"{c1}/{c2}"
        if c1 != c2:
            pair_issue.append(f"{kw}({c1}) ↔ {endk}({c2}) 不成对")
    c_t = len(re.findall(r"^\s*TYPE\s+\w+", text, re.MULTILINE))
    c_et = len(re.findall(r"^\s*END_TYPE", text, re.MULTILINE))
    R["notes"]["TYPE"] = f"{c_t}/{c_et}"
    if c_t != c_et:
        pair_issue.append(f"TYPE({c_t}) ↔ END_TYPE({c_et}) 不成对")

    depth, bal_bad = 0, []
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        d = net(strip_cmt(ln))
        depth += d
        if depth < 0:
            bal_bad.append(f"分支净额为负 L{i}: {ln.strip()[:60]}")
            depth = 0
    if depth != 0:
        bal_bad.append(f"文件末尾分支净额 {depth} ≠ 0")
    pair_issue.extend(bal_bad)

    last = next((l for l in reversed(lines) if l.strip()), "")
    first_pou = None
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        s = ln.strip()
        for kw in ("FUNCTION_BLOCK", "INTERFACE", "FUNCTION", "PROGRAM"):
            if re.match(rf"^{kw}\b", s):
                first_pou = (kw, i)
                break
        if first_pou:
            break
    if not first_pou:
        pair_issue.append("未找到 POU 起始关键字")
    else:
        kw, li = first_pou
        R["notes"]["末行"] = last.strip()
        if last.strip() != POU_PAIRS[kw]:
            pair_issue.append(f"末行 {last.strip()!r} ≠ {POU_PAIRS[kw]}")
    if pair_issue:
        R["fails"].extend(pair_issue[:8])
    R["notes"]["终结符"] = "OK" if not pair_issue else f"{len(pair_issue)} 异常"

    # 3 声明行注释覆盖（中英双语）
    decl_bad, decl_total, mono = [], 0, []
    in_var = 0
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        code = strip_cmt(ln)
        cs = code.strip()
        if not cs:
            continue
        if VAR_KW.match(cs):
            in_var += 1
            continue
        if re.match(r"^END_VAR$", cs):
            in_var = max(0, in_var - 1)
            continue
        if in_var > 0:
            if ":" not in cs:
                continue
            if re.match(r"^(STRUCT|END_STRUCT)$", cs):
                continue
            decl_total += 1
            if "//" not in ln:
                decl_bad.append(f"声明行缺同行注释 L{i}: {cs[:56]}")
                continue
            cmt = ln.split("//", 1)[1]
            if not re.search(r"[A-Za-z]{2,}", cmt):
                mono.append(f"注释缺英文 L{i}: {cmt.strip()[:50]}")
    if decl_bad:
        R["fails"].extend(decl_bad[:6])
    if mono:
        R["fails"].extend(mono[:6])
    R["notes"]["声明行"] = f"{decl_total} 行/缺注释{len(decl_bad)}/非双语{len(mono)}"

    # 4 CASE-ELSE 兜底
    case_miss, stack = [], []
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        code = strip_cmt(ln)
        cs = code.strip()
        if re.match(r"^CASE\s+\S+", cs):
            stack.append([i, 0, False])
            continue
        if not stack:
            continue
        top = stack[-1]
        if re.match(r"^ELSE\b", cs) and top[1] == 0:
            top[2] = True
        top[1] += net(code)
        if top[1] < 0:
            top[1] = 0
        if re.match(r"^END_CASE", cs):
            if not top[2]:
                case_miss.append(f"CASE@L{top[0]} 缺 ELSE")
            stack.pop()
    if case_miss:
        R["fails"].extend(case_miss)
    ncase = len(re.findall(r"^\s*CASE\s+\S+", text, re.MULTILINE))
    R["notes"]["CASE"] = f"{ncase} 个/" + ("ELSE 齐全" if not case_miss else f"缺 {len(case_miss)}")

    # 5 实例无条件刷新
    fb_inst = {}
    in_var2 = False
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        cs = strip_cmt(ln).strip()
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_CONFIG|_STAT|_TEMP)?\b", cs):
            in_var2 = True
            continue
        if re.match(r"^END_VAR\b", cs):
            in_var2 = False
            continue
        if in_var2 and ":" in cs:
            m = re.match(r"^([A-Za-z_]\w*)\s*(,[^:]*)?:\s*([A-Za-z_][\w\.]*)", cs)
            if m and m.group(3) in FB_INSTANCE_TYPES:
                fb_inst[m.group(1)] = m.group(3)
    body_bad = []
    if fb_inst:
        in_var3, depth2 = False, 0
        for i, ln in enumerate(lines, 1):
            if bf[i - 1]:
                continue
            code = strip_cmt(ln)
            cs = code.strip()
            if re.match(r"^(FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY)\b", cs) or \
               re.match(r"^END_(FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY)\b", cs):
                depth2, in_var3 = 0, False
                continue
            if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_CONFIG|_STAT|_TEMP)?\b", cs):
                in_var3 = True
                continue
            if re.match(r"^END_VAR\b", cs):
                in_var3 = False
                continue
            if in_var3:
                continue
            depth2 = max(0, depth2 + net(code))
            for iname in fb_inst:
                if re.search(rf"\b{re.escape(iname)}\s*\(", code) and depth2 > 0:
                    body_bad.append(f"实例 {iname} 分支内调用 L{i}")
    if body_bad:
        R["fails"].extend(body_bad[:6])
    R["notes"]["实例"] = f"{len(fb_inst)} 个/分支内 {len(body_bad)}"

    # 6 R29 赋值目标声明性
    decls = collect_decls(lines, bf)
    assign_bad = []
    in_var4 = False
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        code = strip_cmt(ln)
        cs = code.strip()
        if VAR_KW.match(cs):
            in_var4 = True
            continue
        if re.match(r"^END_VAR$", cs):
            in_var4 = False
            continue
        if in_var4:
            continue
        for m in re.finditer(r"([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*:=", code):
            tgt = m.group(1)
            prev = code[:m.start()].rstrip()
            if prev.endswith("."):
                # 结构体成员赋值：回溯到最外层变量名（如 stTag.bValid := TRUE）
                base = prev[:-1].rstrip()
                root = re.search(r"([A-Za-z_]\w*)(?:\.[A-Za-z_]\w*)*$", base)
                if root:
                    tgt = root.group(1)
                    prev = base[:root.start()].rstrip()
            if prev.endswith("(") or prev.endswith(",") or prev.endswith(":="):
                continue          # 具名实参（如 CLK := x）不算赋值目标
            if re.match(r"^(INT|DINT|LREAL|REAL|BOOL|UDINT|UINT|USINT|WORD|DWORD|TIME|STRING|BYTE)$", tgt):
                continue          # 声明行内的类型名不参与判定
            if tgt not in decls:
                assign_bad.append(f"未声明赋值目标 {tgt} L{i}")
    if assign_bad:
        R["fails"].extend(sorted(set(assign_bad))[:8])
    R["notes"]["赋值目标"] = f"{len(decls)} 声明/未声明 {len(set(assign_bad))}"

    # 7 孤立分号 / 浮点判等（启发式）
    lone = []
    for i, ln in enumerate(lines, 1):
        cs = strip_cmt(ln).strip()
        if cs == ";":
            lone.append(f"孤立分号 L{i}")
    if lone:
        R["fails"].extend(lone[:6])
    R["notes"]["孤立分号"] = str(len(lone))

    flo = []
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        code = strip_cmt(ln)
        code = TIME_LITERAL.sub("T#0", code)
        if re.search(r"\b[fF][A-Za-z0-9_]*\s*(=|<>)\s*[-0-9]", code) or \
           re.search(r"\b[fF][A-Za-z0-9_]*\s*(=|<>)\s*\b[fF][A-Za-z0-9_]*", code):
            if re.search(r"\b[fF][A-Za-z0-9_]*\s*(=|<>)\s*\b[fF][A-Za-z0-9_]*", code) and \
               re.search(r"\b[fF][A-Za-z0-9_]*\s*<>\s*\b[fF][A-Za-z0-9_]*", code):
                # NaN 判据 x <> x 属登记豁免
                if not re.search(r"(\b[fF][A-Za-z0-9_]*)\s*<>\s*\1\b", code):
                    flo.append(f"浮点判等 L{i}: {cs[:60]}")
            else:
                flo.append(f"浮点判等 L{i}: {cs[:60]}")
    R["notes"]["浮点判等"] = str(len(flo))
    if flo:
        R["warn"].extend(flo[:6])

    R["lines"] = len(lines)
    R["bytes"] = len(raw)
    R["ok"] = not R["fails"]
    return R


def main():
    rows, all_ok = [], True
    for rel, cat, kind in FILES:
        r = analyze(rel, cat, kind)
        rows.append(r)
        all_ok &= r["ok"]
        print(f"[{'PASS' if r['ok'] else 'FAIL'}] {r['name']:30s} {r['cat']:11s} {r['lines']:4d}行 {r['bytes']:7d}B")
        print("        " + " | ".join(f"{k}={v}" for k, v in r["notes"].items()))
        for f_ in r["fails"]:
            print("        [FAIL] " + f_)
        for w in r["warn"]:
            print("        [warn] " + w)
    print("=" * 100)
    npass = sum(1 for r in rows if r["ok"])
    print(f"结论: {npass}/{len(rows)} PASS   总行数 {sum(r['lines'] for r in rows)}")

    # 码位跨文件重叠
    codes = collections.defaultdict(list)
    for r in rows:
        txt = open(os.path.join(BASE, r["rel"]), encoding="utf-8").read()
        for m in re.finditer(r"16#([0-9A-F]{4})_([0-9A-F]{4})", txt):
            codes[f"{m.group(1)}_{m.group(2)}"].append(r["name"])
    dup = {k: v for k, v in codes.items() if len(set(v)) > 1}
    print(f"码位（含注释与文档示例）唯一值 {len(codes)} 个；跨文件重复 {len(dup)} 组")
    for k, v in sorted(dup.items()):
        print("        [dup] " + k + " -> " + ",".join(sorted(set(v))))

    json.dump(rows, open(r"C:\Library\_Staging_Raw\2026-11-15\machine_check_r10_reg.json", "w",
                         encoding="utf-8"), ensure_ascii=False, indent=1)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
