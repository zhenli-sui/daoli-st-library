# -*- coding: utf-8 -*-
"""R8 注册收口终审机检：16 文件 × 6 项硬指标（全文口径）"""
import re, sys, io, os, json

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

FILES = [
    (r"C:\Library\DL_MathData\FB_DL_FifoBuffer.st", "DL_MathData"),
    (r"C:\Library\DL_MathData\FB_DL_ArraySearchFirst.st", "DL_MathData"),
    (r"C:\Library\DL_MathData\FC_DL_BinarySearchLReal.st", "DL_MathData"),
    (r"C:\Library\DL_Base\FB_DL_ToleranceWindow.st", "DL_Base"),
    (r"C:\Library\DL_Base\FC_DL_LimitClassify.st", "DL_Base"),
    (r"C:\Library\DL_MathData\FC_DL_TempUnitConvert.st", "DL_MathData"),
    (r"C:\Library\DL_MathData\FC_DL_BcdToWord.st", "DL_MathData"),
    (r"C:\Library\DL_MathData\FC_DL_WordToBcd.st", "DL_MathData"),
    (r"C:\Library\DL_Base\FC_DL_WordBitPack.st", "DL_Base"),
    (r"C:\Library\DL_Base\FB_DL_MonthWindowCheck.st", "DL_Base"),
    (r"C:\Library\DL_Base\FB_DL_PresetCounterSat.st", "DL_Base"),
    (r"C:\Library\DL_Motion\FB_DL_SuperimposedMove.st", "DL_Motion"),
    (r"C:\Library\DL_Device\I_DL_StepperOpenLoop.st", "DL_Device"),
    (r"C:\Library\DL_Device\FB_DL_PulseDirStepper.st", "DL_Device"),
    (r"C:\Library\DL_Process\FB_DL_ModbusPollMaster.st", "DL_Process"),
    (r"C:\Library\DL_Process\FB_DL_AndonCallSystem.st", "DL_Process"),
]

BANNED_LITERAL = ["GVL", "VAR_EXTERNAL", "VAR_GLOBAL", "%I", "%Q", "%M", "%X", "%IB", "%QB",
                  "POINTER TO", "REFERENCE TO", "__SYSTEM", "__ISVALIDREF", "AT %"]
BANNED_RE = [("g_ 前缀", re.compile(r"\bg_[A-Za-z0-9_]+")),
             ("物理地址 AT", re.compile(r"\bAT\s+%[IQM]"))]
PLACEHOLDER_PAT = [
    (r"\bTODO\b", "TODO"), (r"\bFIXME\b", "FIXME"), (r"\bXXX\b", "XXX"),
    (r"待补", "待补"), (r"待完善", "待完善"), (r"待补充", "待补充"),
    (r"//\s*略", "// 略"), (r"//\s*同上", "// 同上"), (r"//\s*同前", "// 同前"),
    (r"\.\.\.", "..."), (r"…", "…"),
]
POU_PAIRS = {"FUNCTION_BLOCK": "END_FUNCTION_BLOCK", "FUNCTION": "END_FUNCTION",
             "INTERFACE": "END_INTERFACE", "PROGRAM": "END_PROGRAM"}
FB_INSTANCE_TYPES = {"TON", "TOF", "TP", "R_TRIG", "F_TRIG"}
VAR_KW = re.compile(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_ACCESS|_CONFIG|_STAT|_TEMP|_CONSTANT)?$")
# 结构化块内的成员声明也算声明行
STRUCT_KW = re.compile(r"^(STRUCT)$")


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


def analyze(path):
    name = os.path.basename(path)
    raw = open(path, "rb").read()
    R = {"name": name, "fails": [], "warn": [], "notes": {}}

    # --- 6. UTF-8 无 BOM ---
    bom = raw[:3] == b"\xef\xbb\xbf"
    try:
        text = raw.decode("utf-8")
        dec_ok = True
    except UnicodeDecodeError as ex:
        dec_ok, text = False, ""
        R["fails"].append(f"UTF-8 解码失败: {ex}")
    if bom:
        R["fails"].append("文件含 UTF-8 BOM")
    R["notes"]["BOM"] = "无" if not bom else "有"
    R["notes"]["编码"] = "UTF-8" if dec_ok else "非UTF-8"

    lines = text.splitlines()
    bf = block_flags(lines)
    n = len(lines)

    # --- 1. 被禁记号字面量（全文口径，含注释） ---
    hits = []
    low = text.lower()
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
        R["fails"].extend(hits[:12])
    R["notes"]["禁记号"] = f"{len(hits)} 命中" if hits else "0 命中"

    # --- 3. 占位符 ---
    ph = []
    for pat, label in PLACEHOLDER_PAT:
        for m in re.finditer(pat, text, re.MULTILINE):
            li = text[:m.start()].count("\n") + 1
            ctx = lines[li - 1].strip()[:70]
            ph.append(f"占位符[{label}] L{li}: {ctx}")
    if ph:
        R["fails"].extend(ph[:12])
    R["notes"]["占位符"] = f"{len(ph)} 命中" if ph else "0 命中"

    # --- 2. POU 终结符成对 + 末行 ---
    pair_issue = []
    for kw, endk in POU_PAIRS.items():
        c1 = len(re.findall(rf"^\s*{kw}\b", text, re.MULTILINE))
        c2 = len(re.findall(rf"^\s*{endk}\b", text, re.MULTILINE))
        R["notes"][f"{kw}"] = f"{c1}/{c2}"
        if c1 != c2:
            pair_issue.append(f"{kw}({c1}) ↔ {endk}({c2}) 不成对")
    c_t = len(re.findall(r"^\s*TYPE\s+\w+", text, re.MULTILINE))
    c_et = len(re.findall(r"^\s*END_TYPE", text, re.MULTILINE))
    R["notes"]["TYPE"] = f"{c_t}/{c_et}"
    if c_t != c_et:
        pair_issue.append(f"TYPE({c_t}) ↔ END_TYPE({c_et}) 不成对")

    # 非终结符失衡：ELSE 与 THEN 之类，用 IF/END_IF 净额
    depth, bal_bad = 0, []
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        code = strip_cmt(ln)
        d = net(code)
        depth += d
        if depth < 0:
            bal_bad.append(f"分支净额为负 L{i}: {ln.strip()[:60]}")
            depth = 0
    if depth != 0:
        bal_bad.append(f"文件末尾分支净额 {depth} ≠ 0（IF/CASE/FOR 未闭合）")
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
        expect = POU_PAIRS[kw]
        R["notes"]["末行"] = last.strip()
        if last.strip() != expect:
            pair_issue.append(f"末行 {last.strip()!r} ≠ {expect}")
    if pair_issue:
        R["fails"].extend(pair_issue[:8])
    R["notes"]["终结符"] = "成对且末行合规" if not pair_issue else f"{len(pair_issue)} 项异常"

    # --- 4. 声明行注释覆盖（含中英双语判定） ---
    decl_bad, decl_total, mono = [], 0, []
    in_var = 0
    in_struct_depth = 0
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
        R["fails"].extend(decl_bad[:8])
    if mono:
        R["fails"].extend(mono[:8])
    R["notes"]["声明行"] = f"{decl_total} 行，注释缺 {len(decl_bad)}，非双语 {len(mono)}"

    # --- 5. CASE-ELSE 兜底 ---
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
                case_miss.append(f"CASE@L{top[0]} 缺 ELSE 兜底")
            stack.pop()
    if case_miss:
        R["fails"].extend(case_miss)
    ncase = len(re.findall(r"^\s*CASE\s+\S+", text, re.MULTILINE))
    R["notes"]["CASE"] = f"{ncase} 个，ELSE 兜底 {'齐全' if not case_miss else '缺失 ' + str(len(case_miss))}"

    # 补充：FB 实例无条件刷新（仅告警提示）
    fb_inst = {}
    in_var2 = False
    for i, ln in enumerate(lines, 1):
        if bf[i - 1]:
            continue
        code = strip_cmt(ln)
        cs = code.strip()
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
        in_var3, depth = False, 0
        for i, ln in enumerate(lines, 1):
            if bf[i - 1]:
                continue
            code = strip_cmt(ln)
            cs = code.strip()
            if re.match(r"^(FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY)\b", cs) or \
               re.match(r"^END_(FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY)\b", cs):
                depth, in_var3 = 0, False
                continue
            if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_CONFIG|_STAT|_TEMP)?\b", cs):
                in_var3 = True
                continue
            if re.match(r"^END_VAR\b", cs):
                in_var3 = False
                continue
            if in_var3:
                continue
            depth = max(0, depth + net(code))
            for iname in fb_inst:
                if re.search(rf"\b{re.escape(iname)}\s*\(", code) and depth > 0:
                    body_bad.append(f"实例 {iname} 分支内调用 L{i}")
    if body_bad:
        R["warn"].extend(body_bad[:6])
    R["notes"]["实例"] = f"{len(fb_inst)} 个实例，分支内调用 {len(body_bad)}"

    R["lines"] = n
    R["bytes"] = len(raw)
    R["ok"] = not R["fails"]
    return R


def main():
    rows, all_ok = [], True
    for p, cat in FILES:
        r = analyze(p)
        r["cat"] = cat
        rows.append(r)
        all_ok &= r["ok"]
        print(f"[{'PASS' if r['ok'] else 'FAIL'}] {r['name']:32s} {r['cat']:11s} {r['lines']:4d}行 {r['bytes']:6d}B")
        print("        " + " | ".join(f"{k}={v}" for k, v in r["notes"].items()))
        for f_ in r["fails"]:
            print("        [FAIL] " + f_)
        for w in r["warn"]:
            print("        [warn] " + w)
    print("=" * 96)
    print(f"结论: {sum(1 for r in rows if r['ok'])}/{len(rows)} PASS" + ("" if all_ok else "  ← 存在不通过项"))
    json.dump([{k: v for k, v in r.items()} for r in rows],
              open(r"C:\Library\_Staging_Raw\2026-11-15\machine_check_r9_reg.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
