# -*- coding: utf-8 -*-
"""Round 05 机检脚本：16 个新组件全项独立机检（口径沿用 machine_check_r4p3.py 扩展）"""
import re, sys, io, os

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

FILES = {
    r"C:\Library\DL_Device\I_DL_Cylinder.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_PneumaticCylinder.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_MotorDriver.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_DolMotor.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_AnalogSensor.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_AnalogTransmitter.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Device\I_DL_TemperatureZone.st": "INTERFACE",
    r"C:\Library\DL_Device\FB_DL_HeatCoolZone.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Motion\I_DL_MotionAxis.st": "INTERFACE",
    r"C:\Library\DL_Motion\FB_DL_SingleAxis.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Motion\FB_DL_AxisJogController.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Process\FB_DL_PackMlStateMachine.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Process\FB_DL_PackMlCmdDecoder.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Base\FC_DL_DayOfWeekCalc.st": "FUNCTION",
    r"C:\Library\DL_Base\FB_DL_TimeWindowCheck.st": "FUNCTION_BLOCK",
    r"C:\Library\DL_Algo\FC_DL_HumidAirEnthalpy.st": "FUNCTION",
}

# 禁记号（全库既有口径）+ g_ 前缀全局
BANNED = ["GVL", "VAR_EXTERNAL", "%I", "%Q", "%M", "POINTER TO", "REFERENCE TO", "__SYSTEM"]
BANNED_RE = [re.compile(r"\bg_\w+", re.IGNORECASE)]
PLACEHOLDER_PAT = [r"TODO", r"FIXME", r"待补", r"待完善", r"//\s*略", r"//\s*同上", r"//\s*[…]{1,3}\s*$"]
# 注：范围省略号（如「bit0=Reset … bit9=Complete」「周一=1 … 周日=7」）为合法区间
# 记法，不计占位符；仅当 … 独立充作注释内容（// …）时按占位符判 FAIL。

POU_PAIRS = {
    "FUNCTION_BLOCK": "END_FUNCTION_BLOCK",
    "FUNCTION": "END_FUNCTION",
    "INTERFACE": "END_INTERFACE",
    "PROGRAM": "END_PROGRAM",
}
END_ALL = re.compile(r"^END_(FUNCTION_BLOCK|FUNCTION|INTERFACE|PROGRAM|TYPE|STRUCT|VAR|IF|CASE|FOR|WHILE|REPEAT)$")

def check(path):
    name = path.replace("C:\\Library\\", "").replace("\\", "/")
    fails, notes = [], []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    lines = text.splitlines()
    n = len(lines)
    joined = text

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
    for pat in PLACEHOLDER_PAT:
        for m in re.finditer(pat, joined, re.IGNORECASE if pat in ("TODO", "FIXME") else 0):
            li = joined[:m.start()].count("\n") + 1
            ph.append(f"占位符 {pat} @L{li}")
    if ph:
        fails.extend(ph[:10])
    notes.append("占位符=0" if not ph else f"占位符={len(ph)}")

    # ---- 3 POU 终结符成对 ----
    pair_ok = True
    counts = {}
    for kw, endk in POU_PAIRS.items():
        c1 = len(re.findall(rf"^\s*{kw}\b", joined, re.MULTILINE))
        c2 = len(re.findall(rf"^\s*{endk}\b", joined, re.MULTILINE))
        counts[kw] = (c1, c2)
        if c1 != c2:
            pair_ok = False
            fails.append(f"{kw}({c1}) 与 {endk}({c2}) 不成对")
    notes.append("终结符成对: " + " ".join(f"{k}={v[0]}/{v[1]}" for k, v in counts.items() if v[0] or v[1]))

    # ---- 4 反序首扫范式（R19）----
    rev = re.findall(r"IF\s+bInit\s+OR\s+bTrack", joined)
    if rev:
        fails.append(f"反序首扫 'IF bInit OR bTrack' 命中 {len(rev)} 处（R19 禁止）")
    notes.append(f"反序首扫={len(rev)}")

    # ---- 5 CASE 有 ELSE（R6）----
    in_case = False; has_else = False; case_start = 0; depth = 0
    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        # 跟踪 IF 深度避免把嵌套 IF 的 ELSE 误认
        if re.match(r"^IF\b", s) and s != "END_IF":
            depth += 1 if s.endswith("END_IF") is False else 0
        # 简化：CASE 层级内直接匹配行首 ELSE
        if not in_case and re.match(r"^CASE\s+\S+", s):
            in_case = True; case_start = i; has_else = False
        elif in_case and re.match(r"^END_CASE", s):
            if not has_else:
                fails.append(f"CASE@L{case_start} 缺 ELSE（R6）")
            in_case = False
        elif in_case and re.match(r"^ELSE(\s|//|$)", s):
            has_else = True
    notes.append("CASE-ELSE OK" if not any("CASE@" in x for x in fails) else "CASE-ELSE FAIL")

    # ---- 6 接口方法/属性数 ≤6 ----
    ifc_blocks = re.findall(r"^\s*INTERFACE\s+(\w+)(.*?)(?=^\s*END_INTERFACE)", joined, re.MULTILINE | re.DOTALL)
    ifc_cnt = len(re.findall(r"^\s*INTERFACE\s+\w+", joined, re.MULTILINE))
    for m in re.finditer(r"^\s*INTERFACE\s+(\w+)(.*?)^\s*END_INTERFACE", joined, re.MULTILINE | re.DOTALL):
        iname, body = m.group(1), m.group(2)
        nm = len(re.findall(r"^\s*METHOD\s+\w+", body, re.MULTILINE))
        np_ = len(re.findall(r"^\s*PROPERTY\s+\w+", body, re.MULTILINE))
        if nm > 6:
            fails.append(f"接口 {iname} METHOD 数 {nm} > 6（红线）")
        notes.append(f"接口 {iname}: METHOD={nm} PROPERTY={np_}")
    if ifc_cnt == 0:
        notes.append("接口: 无（FB/FC 文件）")

    # ---- 7 END_* 为配对末行 ----
    last = next((l for l in reversed(lines) if l.strip()), "")
    last_s = last.strip()
    first_pou = None
    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        for kw in ("FUNCTION_BLOCK", "INTERFACE", "FUNCTION", "PROGRAM"):
            if re.match(rf"^{kw}\b", s):
                first_pou = (kw, i); break
        if first_pou: break
    if first_pou:
        kw, li = first_pou
        expect = POU_PAIRS[kw]
        if last_s != expect:
            fails.append(f"末行 {last_s!r} ≠ {expect}（首 POU {kw}@L{li}）")
        # 检查末行确实是该 POU 的配对终结（数量一致已由第3项保证）
        notes.append(f"末行={last_s}")
    else:
        fails.append("未找到 POU 起始关键字")

    ok = len(fails) == 0
    return name, n, notes, fails, ok

all_ok = True
print(f"{'文件':52s} 行数  结果   明细")
print("-" * 110)
for p in FILES:
    name, n, notes, fails, ok = check(p)
    all_ok &= ok
    flag = "PASS" if ok else "FAIL"
    print(f"{name:52s} {n:5d}  {flag:5s}  {' | '.join(notes)}")
    for f_ in fails:
        print(f"{'':60s}  [FAIL] {f_}")

print("-" * 110)
print("总体结论:", "ALL 16 PASS" if all_ok else "HAS FAIL")
