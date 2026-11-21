# -*- coding: utf-8 -*-
"""Round 04 Phase 3 机检脚本：5 个 DL_Algo 组件质量红线检查"""
import re, sys, io, os

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

FILES = [
    r"C:\Library\DL_Algo\FB_DL_RampGenerator.st",
    r"C:\Library\DL_Algo\FB_DL_SCurveGenerator.st",
    r"C:\Library\DL_Algo\FB_DL_PwmDutyController.st",
    r"C:\Library\DL_Algo\FB_DL_Integrator.st",
    r"C:\Library\DL_Algo\FB_DL_Differentiator.st",
]

BANNED = ["GVL", "VAR_EXTERNAL", "%I", "%Q", "%M", "POINTER TO", "REFERENCE TO", "__SYSTEM"]
PLACEHOLDER_PAT = [r"TODO", r"FIXME", r"待补", r"待完善", r"//\s*略", r"//\s*同上", r"\.\.\.", r"…"]
DECL_RE = re.compile(r"^\s*[A-Za-z_][\w]*\s*:\s*.*;")

def check(path):
    name = os.path.basename(path)
    result, fails = [], []
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    n = len(lines)
    # 1 行数区间
    if not (200 <= n <= 340):
        fails.append(f"行数 {n} 不在 200~340")
    result.append(f"行数={n}")
    # 2 禁用记号（全文含注释，忽略大小写）
    for tok in BANNED:
        for i, ln in enumerate(lines, 1):
            if tok.lower() in ln.lower():
                fails.append(f"禁用记号 {tok} @L{i}")
    result.append("禁用记号=0" if not any(t.lower() in "\n".join(lines).lower() for t in BANNED) else "禁用记号>0")
    # 3 占位符
    joined = "\n".join(lines)
    for pat in PLACEHOLDER_PAT:
        m = re.search(pat, joined, re.IGNORECASE if pat in ("TODO", "FIXME") else 0)
        if m:
            li = joined[:m.start()].count("\n") + 1
            fails.append(f"占位符 {pat} @L{li}")
    result.append("占位符=0" if not fails or all("占位符" not in x for x in fails) else "占位符>0")
    # 4 END_ 终结符
    last = next((l for l in reversed(lines) if l.strip()), "")
    if last.strip() not in ("END_FUNCTION_BLOCK", "END_FUNCTION"):
        fails.append(f"末行非 END_ 终结符: {last.strip()!r}")
    result.append(f"终结符={last.strip()}")
    # 5 CASE 有 ELSE
    in_case = False; has_else = False; case_start = 0
    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        if not in_case and re.match(r"^CASE\s+\w+", s):
            in_case = True; case_start = i; has_else = False
        elif in_case and s == "END_CASE;":
            if not has_else:
                fails.append(f"CASE@L{case_start} 缺 ELSE")
            in_case = False
        elif in_case and re.match(r"^ELSE(\s|//|$)", s):
            has_else = True
    result.append("CASE-ELSE OK")
    # 6 声明行注释覆盖
    total, covered = 0, 0
    in_var = False; in_type = False
    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_CONSTANT|TEMP)?\b", s) and s.endswith("END_VAR") is False:
            in_var = True; continue
        if s == "END_VAR":
            in_var = False; continue
        if s.startswith("TYPE ") or s.startswith("TYPE\t"):
            in_type = True; continue
        if s == "END_TYPE":
            in_type = False; continue
        if (in_var or in_type) and DECL_RE.match(s) and not s.startswith("//"):
            total += 1
            if "//" in s:
                covered += 1
            else:
                fails.append(f"声明缺同行注释 @L{i}: {s[:60]}")
    cov = 100.0 if total == 0 else covered * 100.0 / total
    result.append(f"声明行 {total} 条，注释覆盖 {cov:.1f}%")
    ok = len(fails) == 0
    return name, n, result, fails, ok

all_ok = True
for p in FILES:
    name, n, res, fails, ok = check(p)
    all_ok &= ok
    print(f"\n=== {name} ({n} 行) {'PASS' if ok else 'FAIL'} ===")
    for r in res:
        print("  ", r)
    for f_ in fails:
        print("  [FAIL]", f_)

print("\n总体结论:", "ALL PASS" if all_ok else "HAS FAIL")
