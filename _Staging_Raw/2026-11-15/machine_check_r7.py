# -*- coding: utf-8 -*-
"""Round 07 机检脚本：16 个新组件全项独立机检（口径沿用 machine_check_r6.py，码位白名单更新 R7）

检查项（对 16 个新文件逐个执行）：
  1  禁用记号（GVL/VAR_EXTERNAL/%I/%Q/%M/POINTER TO/REFERENCE TO/__SYSTEM/g_ 前缀）全文 0 命中
  2  占位符（TODO/FIXME/待补/待完善/独立省略号）0 命中
  3  POU 终结符成对（R18）且 END_* 位于文件末行
  4  反序首扫范式（R19 禁止）
  5  ENUM+CASE 含 ELSE（R6 / 0.x 公约：每个 CASE 必带 ELSE）
  6  接口 METHOD 数 ≤6
  7  FB 实例（TON/TOF/R_TRIG/F_TRIG/TP）调用不得位于条件分支内（无条件周期刷新，R7/0.5）
  8  浮点 = / <> 判等禁止（NaN 自比范式 fX<>fX / fX=fX 除外）
  9  声明行双语注释覆盖率 100%（VAR 块声明行、TYPE 枚举项行、INTERFACE PROPERTY/METHOD 行必须带 //）
 10  文件头含「开源溯源」或 Origin 字段
 11  跨文件重名扫描（新增 16 文件之间 + 与库内既有全部 .st：类型名/枚举名/POU 名不得同名异型）
 12  故障码冲突核对（16#0001~0005_xxxx 与既有组件实占码对比 + 公共码白名单裁决）
 13  R21 分离抽查（bFault 不得由信息级码直接派生；信息级码只进 uErrorId 分支）
"""
import re, sys, io, os, glob

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

FILES = {
    r"C:\Library\DL_Base\FB_DL_EventCounter.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Base\FB_DL_ModuloCounter.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_BarcodeScanner.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_SerialScanner.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_SafetyDoor.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_GuardLockDoor.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_LightCurtain.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_SafetyLightCurtain.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_FlowMeter.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_PulseFlowMeter.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_LevelSwitch.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_LevelSwitchVib.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Process\FB_DL_OeeCalculator.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Process\FB_DL_ConveyorZone.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Process\FB_DL_BatchDosingControl.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Motion\FB_DL_SoftLimitGuard.st": "FUNCTION_BLOCK",
}

# ---------- 既有库内全部 .st（用于 11 跨文件重名 / 12 故障码冲突） ----------
EXISTING = []
for d in ("DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"):
    for p in sorted(glob.glob(rf"C:\Library\{d}\*.st")):
        if p not in FILES:
            EXISTING.append(p)

# ---------- 1 禁记号 ----------
BANNED = ["GVL", "VAR_EXTERNAL", "%I", "%Q", "%M", "POINTER TO", "REFERENCE TO", "__SYSTEM"]
BANNED_RE = [re.compile(r"\bg_\w+", re.IGNORECASE)]

# ---------- 2 占位符 ----------
PLACEHOLDER_PAT = [r"TODO", r"FIXME", r"待补", r"待完善", r"//\s*略", r"//\s*同上", r"//\s*[…]{1,3}\s*$"]

POU_PAIRS = {
    "FUNCTION_BLOCK": "END_FUNCTION_BLOCK",
    "FUNCTION": "END_FUNCTION",
    "INTERFACE": "END_INTERFACE",
    "PROGRAM": "END_PROGRAM",
}

FB_INSTANCE_TYPES = {"TON", "TOF", "TP", "R_TRIG", "F_TRIG"}

# 跨文件共享公共码白名单（依据各子库 VERSION.md 台账，语义=库级公共码/族码；R7 全部新码位独立分配，不新增白名单项）
COMMON_CODES = {
    "0002_0000", "0002_0001", "0002_0002", "0002_0004", "0002_0005",  # DL_Algo 公共码
    "0003_0201",   # DL_Device 库级「非法状态」族码（PneumaticCylinder/DolMotor 已共用）
    "0003_0208",   # DL_Device「重启抑制期拒绝」同义码（R6 终审裁定）
    "0004_0201",   # DL_Motion 族码「非法状态兜底」
    "0005_0201",   # DL_Process「非法状态兜底」（PackMlStateMachine 既有）
    "0001_0001", "0001_0002", "0001_0003", "0001_0004", "0001_0005",
    "0001_0006", "0001_0007", "0001_0008", "0001_0009", "0001_000A",
    "0001_0201", "0001_0202",  # DL_Base/MathData 公共码族
}


def strip_comment(ln):
    """去掉 // 行注释（不处理 (* *) 块注释——块注释行整体跳过由调用方处理）"""
    i = ln.find("//")
    return ln if i < 0 else ln[:i]


def in_block_comment(lines):
    """返回每行是否处于 (* *) 块注释内"""
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
    """单行 IF/CASE/FOR/WHILE/REPEAT 净深度增量（THEN 数-ELSIF 数+CASE/FOR/WHILE/REPEAT 起 - END_* 数）"""
    inc = len(re.findall(r"\bTHEN\b", code)) - len(re.findall(r"\bELSIF\b", code))
    inc += len(re.findall(r"^\s*CASE\s+\S+", code)) + len(re.findall(r"^\s*FOR\b", code)) \
         + len(re.findall(r"^\s*WHILE\b", code)) + len(re.findall(r"^\s*REPEAT\b", code))
    dec = len(re.findall(r"\bEND_IF\b", code)) + len(re.findall(r"\bEND_CASE\b", code)) \
        + len(re.findall(r"\bEND_FOR\b", code)) + len(re.findall(r"\bEND_WHILE\b", code)) \
        + len(re.findall(r"\bEND_REPEAT\b", code))
    return inc - dec


def analyze(path):
    name = path.replace("C:\\Library\\", "").replace("\\", "/")
    fails, notes = [], []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    lines = text.splitlines()
    n = len(lines)
    bcm = in_block_comment(lines)

    # ---- 1 禁记号 ----
    banned_hits = []
    for tok in BANNED:
        for i, ln in enumerate(lines, 1):
            if tok.lower() in ln.lower():
                banned_hits.append(f"禁记号 {tok} @L{i}")
    for rx in BANNED_RE:
        for i, ln in enumerate(lines, 1):
            m = rx.search(ln)
            if m:
                banned_hits.append(f"禁记号 g_全局 {m.group(0)} @L{i}")
    if banned_hits:
        fails.extend(banned_hits[:10])
    notes.append("禁记号=0" if not banned_hits else f"禁记号={len(banned_hits)}")

    # ---- 2 占位符 ----
    ph = []
    joined = text
    for pat in PLACEHOLDER_PAT:
        for m in re.finditer(pat, joined, re.IGNORECASE if pat in ("TODO", "FIXME") else 0):
            li = joined[:m.start()].count("\n") + 1
            ph.append(f"占位符 {pat} @L{li}")
    if ph:
        fails.extend(ph[:10])
    notes.append("占位符=0" if not ph else f"占位符={len(ph)}")

    # ---- 3 POU 终结符成对 + 末行（R18） ----
    counts = {}
    for kw, endk in POU_PAIRS.items():
        c1 = len(re.findall(rf"^\s*{kw}\b", joined, re.MULTILINE))
        c2 = len(re.findall(rf"^\s*{endk}\b", joined, re.MULTILINE))
        counts[kw] = (c1, c2)
        if c1 != c2:
            fails.append(f"{kw}({c1}) 与 {endk}({c2}) 不成对")
    notes.append("终结符成对: " + " ".join(f"{k}={v[0]}/{v[1]}" for k, v in counts.items() if v[0] or v[1]))

    # TYPE 成对
    c_t = len(re.findall(r"^\s*TYPE\s+\w+", joined, re.MULTILINE))
    c_et = len(re.findall(r"^\s*END_TYPE", joined, re.MULTILINE))
    if c_t != c_et:
        fails.append(f"TYPE({c_t}) 与 END_TYPE({c_et}) 不成对")
    notes.append(f"TYPE={c_t}/{c_et}")

    last = next((l for l in reversed(lines) if l.strip()), "")
    last_s = last.strip()
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
        if last_s != expect:
            fails.append(f"末行 {last_s!r} ≠ {expect}（首 POU {kw}@L{li}）")
        notes.append(f"末行={last_s}")
    else:
        fails.append("未找到 POU 起始关键字")

    # ---- 4 反序首扫 ----
    rev = re.findall(r"IF\s+bInit\s+OR\s+bTrack", joined)
    if rev:
        fails.append(f"反序首扫 'IF bInit OR bTrack' 命中 {len(rev)} 处（R19 禁止）")
    notes.append(f"反序首扫={len(rev)}")

    # ---- 5 CASE 必带 ELSE（结构级解析，逐行净计数，嵌套 IF 的 ELSE 不误认） ----
    case_fail = []
    case_stack = []  # 每元素 [case_start_line, depth, has_else]
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
    notes.append("CASE-ELSE OK" if not case_fail else "CASE-ELSE FAIL")

    # ---- 6 接口 METHOD ≤6 ----
    for m in re.finditer(r"^\s*INTERFACE\s+(\w+)(.*?)^\s*END_INTERFACE", joined, re.MULTILINE | re.DOTALL):
        iname, body = m.group(1), m.group(2)
        nm = len(re.findall(r"^\s*METHOD\s+\w+", body, re.MULTILINE))
        np_ = len(re.findall(r"^\s*PROPERTY\s+\w+", body, re.MULTILINE))
        if nm > 6:
            fails.append(f"接口 {iname} METHOD 数 {nm} > 6（红线）")
        notes.append(f"接口 {iname}: METHOD={nm} PROPERTY={np_}")
    if "INTERFACE" not in joined:
        notes.append("接口: 无（FB 文件）")

    # ---- 结构解析准备：收集声明区信息（供 7/8/9） ----
    real_vars = set()          # REAL/LREAL 变量名
    fb_instances = {}          # 实例名 -> 类型
    decl_issues = []           # 双语注释缺失
    var_depth = 0              # VAR 块嵌套
    pou_stack = []             # 当前 POU 上下文
    for i, ln in enumerate(lines, 1):
        if bcm[i - 1]:
            continue
        code = strip_comment(ln)
        cs = code.strip()
        if not cs:
            continue
        # POU 上下文切换
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
        elif cs == "END_METHOD" or cs == "END_PROPERTY":
            if pou_stack:
                pou_stack.pop()
        # VAR 块跟踪
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_ACCESS|_CONFIG)?\b", cs):
            var_depth += 1
            continue
        if re.match(r"^END_VAR\b", cs):
            var_depth -= 1
            continue
        ctx = pou_stack[-1] if pou_stack else None
        if var_depth > 0:
            # 声明行（含 ':' 的行）；多行 ARRAY 声明的续行无 ':' 不计
            if ":" in cs:
                if "//" not in ln:
                    decl_issues.append(f"声明行缺双语注释 @L{i}: {cs[:48]}")
                m = re.match(r"^([A-Za-z_]\w*)\s*(,[^:]*)?:\s*([A-Za-z_][\w\.]*)", cs)
                if m:
                    vname, _, vtype = m.group(1), m.group(2), m.group(3)
                    if vtype in ("REAL", "LREAL"):
                        real_vars.add(vname)
                    if vtype in FB_INSTANCE_TYPES:
                        fb_instances[vname] = vtype
        elif ctx == "IFC" and (re.match(r"^(PROPERTY|METHOD)\s+\w+\s*:", cs)):
            if "//" not in ln:
                decl_issues.append(f"接口成员声明缺双语注释 @L{i}: {cs[:48]}")
    if decl_issues:
        fails.append(f"双语注释覆盖 {len(decl_issues)} 处缺失: " + "; ".join(decl_issues[:4]))
    notes.append("声明注释覆盖=100%" if not decl_issues else f"声明注释缺失={len(decl_issues)}")

    # ---- 7 FB 实例调用不得位于条件分支内 ----
    inst_hits, inst_bad = [], []
    if fb_instances:
        in_var = False
        body_depth = 0
        for i, ln in enumerate(lines, 1):
            if bcm[i - 1]:
                continue
            code = strip_comment(ln)
            cs = code.strip()
            if re.match(r"^(FUNCTION_BLOCK|FUNCTION|PROGRAM|METHOD|PROPERTY)\b", cs):
                body_depth = 0  # 每个方法/主体边界重置
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
                        inst_bad.append(f"实例 {iname}({fb_instances[iname]}) 调用于分支内 depth={body_depth} @L{i}")
        if inst_bad:
            fails.extend(inst_bad[:6])
        notes.append(f"实例刷新 {len(inst_hits)} 处 全部无条件" if not inst_bad else f"实例分支内={len(inst_bad)}")
    else:
        notes.append("无 TON/TRIG/TP 实例")

    # ---- 8 浮点判等（= / <>），NaN 自比范式（fX<>fX / fX=fX）除外 ----
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
                # NaN 自比范式：同一 REAL 变量两侧自比
                if lid is not None and lid == rid and lid in real_vars:
                    continue
                ctx = code[max(0, m.start() - 24):m.start()].strip()[-24:]
                flt_bad.append(f"浮点判等 {m.group(1)!r} @L{i}: …{ctx} {m.group(1)} {rid or '<num>'}")
    if flt_bad:
        fails.extend(flt_bad[:6])
    notes.append("浮点判等=0" if not flt_bad else f"浮点判等={len(flt_bad)}")

    # ---- 9 文件头溯源 ----
    head = "\n".join(lines[:90])
    if ("开源溯源" not in head) and ("Origin" not in head):
        fails.append("文件头缺「开源溯源/Origin」字段")
    notes.append("溯源 OK")

    # ---- 13 R21 分离抽查：bFault 派生式禁止由信息级码常量直接参与 ----
    r21_bad = []
    for i, ln in enumerate(lines, 1):
        if bcm[i - 1]:
            continue
        code = strip_comment(ln)
        m = re.match(r"^\s*bFault\s*:=\s*(.+)", code)
        if m and re.search(r"16#[0-9A-Fa-f]{4}_01[0-9A-Fa-f]{2}", m.group(1)):
            r21_bad.append(f"bFault 派生混入信息级码 @L{i}")
    if r21_bad:
        fails.extend(r21_bad[:4])
    notes.append("R21 分离 OK" if not r21_bad else "R21 分离 FAIL")

    # ---- 12 故障码提取（冲突在汇总阶段裁决） ----
    codes = set(m.group(1).upper() for m in re.finditer(r"16#(000[1-5]_[0-9A-Fa-f]{3,4})", text))

    ok = len(fails) == 0
    return dict(name=name, n=n, notes=notes, fails=fails, ok=ok, codes=codes)


# ---------- 汇总：11 跨文件重名 / 12 故障码冲突 ----------
def collect_defs(path):
    """提取文件内定义的 POU 名与 TYPE/枚举名"""
    with open(path, encoding="utf-8") as f:
        t = f.read()
    pos = set(re.findall(r"^\s*(?:FUNCTION_BLOCK|FUNCTION|INTERFACE|PROGRAM)\s+([A-Za-z_]\w*)", t, re.MULTILINE))
    tys = set(re.findall(r"^\s*TYPE\s+([A-Za-z_]\w*)", t, re.MULTILINE))
    return pos, tys


new_defs, old_defs = {}, {}
for p in FILES:
    pos, tys = collect_defs(p)
    for d in pos | tys:
        new_defs.setdefault(d, []).append(os.path.basename(p))
for p in EXISTING:
    pos, tys = collect_defs(p)
    for d in pos | tys:
        old_defs.setdefault(d, []).append(os.path.basename(p))

dup_within = {k: v for k, v in new_defs.items() if len(v) > 1}
dup_against = {k: (v, old_defs[k]) for k, v in new_defs.items() if k in old_defs}

# 故障码冲突：新文件码 ∩ 既有文件码，排除公共码白名单
all_new_codes = {}
for p in FILES:
    r = analyze(p)
    all_new_codes[r["name"]] = r
existing_codes = {}
for p in EXISTING:
    with open(p, encoding="utf-8") as f:
        t = f.read()
    cs = set(m.group(1).upper() for m in re.finditer(r"16#(000[1-5]_[0-9A-Fa-f]{3,4})", t))
    base = p.replace("C:\\Library\\", "").replace("\\", "/")
    for c in cs:
        existing_codes.setdefault(c, []).append(base)

code_conflicts = []
for nm, r in all_new_codes.items():
    for c in r["codes"]:
        if c in existing_codes and c not in COMMON_CODES:
            code_conflicts.append(f"{nm} 使用 {c}，与既有 {existing_codes[c][:3]} 冲突")

# ---------- 输出 ----------
all_ok = True
print(f"{'文件':50s} 行数  结果   明细")
print("-" * 112)
total_lines = 0
for p in FILES:
    key = p.replace("C:\\Library\\", "").replace("\\", "/")
    r = all_new_codes[key]
    all_ok &= r["ok"]
    total_lines += r["n"]
    flag = "PASS" if r["ok"] else "FAIL"
    print(f"{r['name']:50s} {r['n']:5d}  {flag:5s}  {' | '.join(r['notes'])}")
    for f_ in r["fails"]:
        print(f"{'':58s}  [FAIL] {f_}")

print("-" * 112)
print(f"16 文件总行数（wc -l 口径）: {total_lines}")
print()
print("== 检查项 11｜跨文件重名扫描 ==")
print(f"  新增 16 文件内部重名: {dup_within if dup_within else '无'}")
print(f"  与库内既有组件重名: {dup_against if dup_against else '无'}")
if dup_within or dup_against:
    all_ok = False
print()
print("== 检查项 12｜故障码冲突核对 ==")
if code_conflicts:
    for c in code_conflicts:
        print("  [FAIL]", c)
    all_ok = False
else:
    print("  新码位与既有实占码零冲突（公共码白名单外）")
    for nm, r in all_new_codes.items():
        shared = sorted(c for c in r["codes"] if c in existing_codes)
        if shared:
            print(f"  {nm}: 复用公共码 {', '.join(shared)}")
print()
print("总体结论:", "ALL 16 PASS" if all_ok else "HAS FAIL")
