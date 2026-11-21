# -*- coding: utf-8 -*-
"""R42 终审返修收口：ElTestStation / HydronicMeterAudit 修复至 v1.0.1 → 机检 + registry 更新 + JSONL 原地重注入"""
import os, re, io, glob, json

LIB = "C:/Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JSONL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
FIXED = [("FB_DL_ElTestStation", "DL_Process"), ("FB_DL_HydronicMeterAudit", "DL_Process")]

def strip_comments(t):
    t = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    return t

DUPCODE = {}
for f in glob.glob(os.path.join(LIB, "DL_*", "*.st")):
    txt = io.open(f, encoding="utf-8", errors="ignore").read()
    base = os.path.basename(f)[:-3]
    for m in set(re.findall(r"16#000[0-9]_[0-9A-Fa-f]{4}", txt)):
        if m.upper().endswith("_0000"):
            continue
        DUPCODE.setdefault(m.upper(), set()).add(base)

def check(name, cat):
    p = os.path.join(LIB, cat, name + ".st")
    raw = io.open(p, "rb").read()
    txt = raw.decode("utf-8", "replace")
    body = strip_comments(txt)
    errs = []
    for b in [r"\bVAR_EXTERNAL\b", r"\bGVL\b", r"%[IQM][XBWDL]?\d"]:
        for m in re.finditer(b, body):
            errs.append("BANNED %s" % b)
    ncase = len(re.findall(r"^\s*CASE\b", body, re.M))
    nelse = len(re.findall(r"^\s*ELSE\s*$", body, re.M))
    if ncase and nelse < ncase:
        errs.append("CASE WITHOUT ELSE")
    if re.search(r"\(\*(?:(?!\*\)).)*\(\*", txt, flags=re.S):
        errs.append("NESTED COMMENT")
    if re.search(r"\bTODO\b|待补充|待完善|占位", txt):
        errs.append("PLACEHOLDER")
    if re.search(r"同上", txt):
        errs.append("BANNED-WORD 同上")
    if not re.search(r"^\s*END_FUNCTION(_BLOCK)?\b", body, re.M):
        errs.append("NO POU TERMINATOR")
    if b"\r\n" not in raw:
        errs.append("NOT CRLF")
    # 终审专查：CASE 使用的 _eState 必须在 VAR 区声明
    if re.search(r"\b_eState\b", body) and not re.search(r"\b_eState\s*:\s*E_DL_\w+", body):
        errs.append("_eState NOT DECLARED")
    for seg in set(re.findall(r"16#000[0-9]_[0-9A-Fa-f]{4}", txt)):
        if seg.upper().endswith("_0000"):
            continue
        others = [x for x in DUPCODE.get(seg.upper(), set()) if x != name]
        if others:
            errs.append("CODE DUP %s with %s" % (seg, ",".join(sorted(others))))
    return errs

ok = True
for name, cat in FIXED:
    e = check(name, cat)
    if e: ok = False
    print("%-28s %s" % (name, "PASS" if not e else "FAIL: " + "; ".join(e)))
print("MACHINE CHECK:", "ALL PASS" if ok else "HAS FAIL")
if not ok:
    raise SystemExit(1)

# registry 更新（版本 1.0.1 + 行数）
reg = json.load(io.open(REG, encoding="utf-8"))
for c in reg["components"]:
    if (c["name"], c["category"]) in FIXED:
        c["version"] = "1.0.1"
        c["line_count"] = len(io.open(c["file_path"], encoding="utf-8", errors="ignore").read().splitlines())
        print("REG UPD: %s v1.0.1 lines=%d" % (c["name"], c["line_count"]))
reg["last_updated"] = "2026-11-19T20:30:00+08:00"
io.open(REG, "w", encoding="utf-8", newline="\n").write(json.dumps(reg, ensure_ascii=False, indent=2))

# JSONL 原地重注入（output 与新源码不一致则替换，保持行序与 instruction/architecture_thought 不动）
lines = io.open(JSONL, encoding="utf-8").read().splitlines()
res = []
for name, cat in FIXED:
    src = io.open(os.path.join(LIB, cat, name + ".st"), "rb").read().decode("utf-8")
    hit = -1
    for idx, ln in enumerate(lines):
        try:
            o = json.loads(ln)
        except Exception:
            continue
        if name in o.get("output", "")[:600]:
            hit = idx
    if hit < 0:
        res.append(name + ":NOT FOUND"); continue
    o = json.loads(lines[hit])
    if o["output"] != src:
        o["output"] = src
        lines[hit] = json.dumps(o, ensure_ascii=False)
        res.append(name + ":FIXED")
    else:
        res.append(name + ":MATCH")
if any(x.endswith(":FIXED") for x in res):
    io.open(JSONL, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")

# 全量校验
bad = 0
for ln in lines:
    try:
        json.loads(ln)
    except Exception:
        bad += 1
print("REINJECT:", res)
print("JSONL VERIFY: total=%d badjson=%d" % (len(lines), bad))
