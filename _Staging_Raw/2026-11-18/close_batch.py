# -*- coding: utf-8 -*-
"""R35 batch closure: CRLF normalize + structural check + registry/JSONL/ROADMAP."""
import json, re, sys, os, datetime

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JSONL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
ROADMAP = os.path.join(LIB, "ROADMAP.md")

KW_PAIRS = [("IF", "END_IF"), ("CASE", "END_CASE"), ("FOR", "END_FOR"), ("WHILE", "END_WHILE")]

def strip_comments_strings(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("(*", i):
            j = text.find("*)", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            out.append(" ")
        elif text[i] == "'":
            j = i + 1
            while j < n:
                if text[j] == "'" and j + 1 < n and text[j+1] == "'":
                    j += 2; continue
                if text[j] == "'":
                    j += 1; break
                j += 1
            i = j
            out.append("''")
        else:
            out.append(text[i]); i += 1
    return "".join(out)

def structural_check(path, fname):
    rawb = open(path, "rb").read().decode("utf-8")
    raw = rawb.replace("\r\n", "\n")
    code = strip_comments_strings(raw)
    errs = []
    fb = len(re.findall(r"\bFUNCTION_BLOCK\b", code)); efb = len(re.findall(r"\bEND_FUNCTION_BLOCK\b", code))
    fu = len(re.findall(r"\bFUNCTION\b", code)); efu = len(re.findall(r"\bEND_FUNCTION\b", code))
    if not (fb == 1 and efb == 1) and not (fu == 1 and efu == 1):
        errs.append(f"POU/END mismatch fb={fb}/{efb} fu={fu}/{efu}")
    for v in ["VAR_INPUT", "VAR_OUTPUT", "VAR_IN_OUT", "VAR", "VAR_CONSTANT"]:
        o = len(re.findall(rf"\b{v}\b", code)); c = len(re.findall(r"\bEND_VAR\b", code))
    # per-block pairing
    opens = 0
    for v in ["VAR_INPUT", "VAR_OUTPUT", "VAR_IN_OUT", "VAR_CONSTANT", "VAR"]:
        opens += len(re.findall(rf"\b{v}\b", code))
    closes = len(re.findall(r"\bEND_VAR\b", code))
    if opens != closes:
        errs.append(f"VAR blocks {opens} vs END_VAR {closes}")
    for a, b in KW_PAIRS:
        ca = len(re.findall(rf"\b{a}\b", code)); cb = len(re.findall(rf"\b{b}\b", code))
        if ca != cb:
            errs.append(f"{a}={ca} vs {b}={cb}")
    if code.count("(") != code.count(")"):
        errs.append(f"paren {code.count('(')}/{code.count(')')}")
    # enum members: single-colon declaration defect check inside TYPE blocks
    for m in re.finditer(r"TYPE\s+E_DL_\w+\s*:\s*\((.*?)\)\s*;", code, re.S):
        body = m.group(1)
        for line in body.splitlines():
            line = line.split("//")[0].strip().rstrip(",")
            if not line: continue
            if ":" in line and ":=" not in line:
                errs.append(f"enum single-colon: {line}")
    if "\n" in rawb and "\r" not in rawb:
        errs.append("no-CRLF")
    if re.search(r"%[IQ]", code):
        errs.append("physical address")
    if re.search(r"\bg_", code):
        errs.append("global var")
    if re.search(r"VAR_EXTERNAL", code):
        errs.append("VAR_EXTERNAL")
    return errs, raw.count("\n") + (0 if raw.endswith("\n") else 1)

def close_batch(items):
    """items: list of dicts name/category/subdir/code_segment/complexity/tags/instruction/cot"""
    reg = json.load(open(REG, encoding="utf-8"))
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    added, total_lines = [], 0
    for it in items:
        path = os.path.join(LIB, it["subdir"], it["name"] + ".st")
        raw0 = open(path, encoding="utf-8").read().replace("\r\n", "\n").replace("\n", "\r\n")
        open(path, "w", encoding="utf-8", newline="").write(raw0)
        errs, lines = structural_check(path, it["name"])
        if errs:
            print(f"FAIL {it['name']}: {errs}"); sys.exit(1)
        total_lines += lines
        entry = {"name": it["name"], "category": it["category"], "type": "FB",
                 "file_path": path.replace("/", "\\"),
                 "function_tags": it["tags"] + ["r35-plan"], "complexity": it["complexity"],
                 "version": "1.0.0", "registered_at": now, "line_count": lines,
                 "code_segment": it["code_segment"], "source": "r35-plan"}
        reg["components"].append(entry); added.append(it["name"])
        src = open(path, encoding="utf-8", newline="").read()
        rec = {"instruction": it["instruction"], "architecture_thought": it["cot"], "output": src}
        with open(JSONL, "a", encoding="utf-8", newline="") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\r\n")
        # ROADMAP tick
        rm = open(ROADMAP, encoding="utf-8").read()
        pat = f"- [ ] `{it['name']}`"
        if pat in rm:
            rm = rm.replace(pat, f"- [x] `{it['name']}`", 1)
            open(ROADMAP, "w", encoding="utf-8", newline="").write(rm)
        else:
            print(f"WARN roadmap entry not found: {it['name']}")
    reg["total_components"] = len(reg["components"])
    open(REG, "w", encoding="utf-8", newline="\n").write(json.dumps(reg, ensure_ascii=False, indent=1))
    print(f"OK {len(added)} registered: {added}; lines={total_lines}; total={reg['total_components']}")

if __name__ == "__main__":
    batch = json.load(open(sys.argv[1], encoding="utf-8"))
    close_batch(batch)
