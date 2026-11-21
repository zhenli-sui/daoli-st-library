# -*- coding: utf-8 -*-
"""R24 诊断：定位全量复验 20 条 mismatch 的性质（noPOU vs sha-mismatch）"""
import json, re, hashlib
os_path = "C:/Library/"
lines = open(os_path + "_AI_Training_Dataset/daoli_st_sft_dataset.jsonl", encoding="utf-8", newline="").readlines()
reg = json.load(open(os_path + "INDEX_REGISTRY.json", encoding="utf-8"))
fmap = {c["name"]: c for c in reg["components"]}

def pou_of(t):
    m = re.search(r"FUNCTION(?:_BLOCK)?\s+(F[BC]_DL_\w+)", t)
    return m.group(1) if m else None

n_nopou = 0
for i, l in enumerate(lines):
    o = json.loads(l)
    p = pou_of(o["output"])
    if not p:
        n_nopou += 1
        print("row %d noPOU | instr: %s | out_head: %s" % (
            i + 1, o.get("instruction", "")[:50], o["output"][:70].replace("\n", " ")))
    else:
        c = fmap.get(p)
        if not c:
            print("row %d %s NOT-IN-REGISTRY" % (i + 1, p)); continue
        fp = c["file_path"].replace("\\\\", "\\")
        if not fp.startswith("C:"):
            fp = os_path + fp.lstrip("/\\")
        d = open(fp, encoding="utf-8", newline="").read()
        if hashlib.sha256(o["output"].encode("utf-8")).hexdigest() != hashlib.sha256(d.encode("utf-8")).hexdigest():
            print("row %d %s SHA-MISMATCH reg_ver=%s" % (i + 1, p, c.get("version")))
print("total noPOU rows:", n_nopou)
