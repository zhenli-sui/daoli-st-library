# -*- coding: utf-8 -*-
"""R22 stage-5 reinject: 4 terminal-review fixes -> JSONL line replace -> registry sync -> full sha verify."""
import json, re, hashlib, glob as g, os

os.chdir("C:/Library")
FIXED = {"FB_DL_MotionCmdQueue", "FB_DL_VirtualMasterAxis",
         "FB_DL_AxisBrakeSeq", "FB_DL_BatchTransferSeq"}

path = "_AI_Training_Dataset/daoli_st_sft_dataset.jsonl"
lines = open(path, encoding="utf-8", newline="").read().splitlines()
assert len(lines) == 384, len(lines)

reg = json.load(open("INDEX_REGISTRY.json", encoding="utf-8"))
comp = {c["name"]: c for c in reg["components"]}
replaced = 0
out_lines = []
for ln in lines:
    obj = json.loads(ln)
    m = re.search(r"\b(FB_|FC_|I_)DL_\w+", obj["output"])
    name = m.group(0)
    if name in FIXED:
        src = open("%s/%s.st" % (comp[name]["category"], name),
                   encoding="utf-8", newline="").read()
        obj["output"] = src                                   # 1) output 替换为新源码
        obj["architecture_thought"] = obj["architecture_thought"].replace("v1.0.0", "v1.0.1") \
            if "v1.0.0" in obj.get("architecture_thought", "") else obj["architecture_thought"]
        comp[name]["version"] = "1.0.1"                       # 2) 注册表 version 同步
        comp[name]["line_count"] = src.count("\n") + 1        # 3) line_count 同步
        out_lines.append(json.dumps(obj, ensure_ascii=False))
        replaced += 1
    else:
        out_lines.append(ln)
assert replaced == 4, replaced
open(path, "w", encoding="utf-8", newline="").write("\n".join(out_lines) + "\n")

reg["last_updated"] = "2026-11-16T23:59:00+08:00"
json.dump(reg, open("INDEX_REGISTRY.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# 全量 384 条 sha256 复验
bad = 0
for ln in open(path, encoding="utf-8", newline="").read().splitlines():
    obj = json.loads(ln)
    name = re.search(r"\b(FB_|FC_|I_)DL_\w+", obj["output"]).group(0)
    src = open("%s/%s.st" % (comp[name]["category"], name), encoding="utf-8", newline="").read()
    if hashlib.sha256(obj["output"].encode("utf-8")).hexdigest() != hashlib.sha256(src.encode("utf-8")).hexdigest():
        bad += 1
        print("DRIFT", name)
print("replaced:", replaced, "| total lines:", len(out_lines), "| sha check bad:", bad)
print("versions:", {n: comp[n]["version"] for n in sorted(FIXED)})
print("line_counts:", {n: comp[n]["line_count"] for n in sorted(FIXED)})
