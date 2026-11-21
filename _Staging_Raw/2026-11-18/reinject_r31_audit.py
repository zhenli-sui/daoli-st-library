# -*- coding: utf-8 -*-
"""R31 终审修复件回注 JSONL：按 name 定位行，替换持码字段，sha256 复验。"""
import json, hashlib, io, os

JSONL = r"C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl"
FIXED = {
    "FB_DL_ReactorStepCtrl":   r"C:\Library\DL_Process\FB_DL_ReactorStepCtrl.st",
    "FB_DL_ChamberLeakRate":   r"C:\Library\DL_Process\FB_DL_ChamberLeakRate.st",
    "FB_DL_FilmTensionDancer": r"C:\Library\DL_Process\FB_DL_FilmTensionDancer.st",
    "FB_DL_EtchEndpointTrend": r"C:\Library\DL_Algo\FB_DL_EtchEndpointTrend.st",
}

with io.open(JSONL, "r", encoding="utf-8", newline="") as f:
    lines = f.readlines()

# 探测持码字段名
sample = json.loads(lines[0])
code_key = None
for k in ("output", "code", "st_code", "response", "content"):
    if k in sample:
        code_key = k
        break
assert code_key, "未找到持码字段: keys=%s" % list(sample.keys())

name_key = None  # output 内含组件名头注释，按持码内容定位

hit = {n: 0 for n in FIXED}
for i, ln in enumerate(lines):
    if not ln.strip():
        continue
    obj = json.loads(ln)
    out = obj[code_key]
    for nm, path in FIXED.items():
        if nm in out:
            with io.open(FIXED[nm], "r", encoding="utf-8", newline="") as sf:
                new_code = sf.read()
            obj[code_key] = new_code
            lines[i] = json.dumps(obj, ensure_ascii=False) + "\n"
            hit[nm] += 1

assert all(v == 1 for v in hit.values()), "命中数异常: %s" % hit

with io.open(JSONL, "w", encoding="utf-8", newline="") as f:
    f.writelines(lines)

# sha256 复验
ok = 0
with io.open(JSONL, "r", encoding="utf-8", newline="") as f:
    for ln in f:
        if not ln.strip():
            continue
        obj = json.loads(ln)
        out = obj[code_key]
        for nm in FIXED:
            if nm in out:
                with io.open(FIXED[nm], "rb") as sf:
                    fb = hashlib.sha256(sf.read()).hexdigest()
                ob = hashlib.sha256(out.encode("utf-8")).hexdigest()
                st = "MATCH" if fb == ob else "MISMATCH"
                ok += (st == "MATCH")
                print("%s %s lines=%d" % (nm, st, out.count("\n") + 1))
print("TOTAL=%d/4 MATCH" % ok)
