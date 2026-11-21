# -*- coding: utf-8 -*-
"""R24 final-audit re-injection: 2 components -> v1.0.1, JSONL row replace,
registry sync, full 424-row sha re-verify. (R19-2/R87 五步法，含 thought 复核：
两件 thought 均为描述性，码位与策略描述无变化，无需修正。)"""
import json, re, hashlib, os, datetime
os.chdir("C:/Library")
JP = "_AI_Training_Dataset/daoli_st_sft_dataset.jsonl"
RP = "INDEX_REGISTRY.json"

CHANGES = {  # name -> new version
 "FB_DL_CartonErectorStation": "1.0.1",  # fbSeq.bReset 死锁修复
 "FB_DL_PumpDryRunGuard": "1.0.1",       # 默认参数自违反 R100 配比修复
}

reg = json.load(open(RP, encoding="utf-8"))
fmap = {c["name"]: c for c in reg["components"]}

lines = open(JP, encoding="utf-8", newline="").readlines()
assert len(lines) == 424, len(lines)
objs = [json.loads(l) for l in lines]

def pou_of(txt):
    m = re.search(r"FUNCTION(?:_BLOCK)?\s+(F[BC]_DL_\w+)", txt)
    return m.group(1) if m else None

hit = {}
for i, o in enumerate(objs):
    p = pou_of(o["output"])
    if p and p in CHANGES:
        assert p not in hit, "dup row: " + p
        hit[p] = i
assert set(hit) == set(CHANGES), set(CHANGES) - set(hit)

for name, idx in hit.items():
    c = fmap[name]
    fp = c["file_path"].replace("\\\\", "\\")
    txt = open(fp, encoding="utf-8", newline="").read()
    objs[idx]["output"] = txt
    c["version"] = CHANGES[name]
    c["line_count"] = len(txt.splitlines())
    assert hashlib.sha256(objs[idx]["output"].encode("utf-8")).hexdigest() == \
           hashlib.sha256(txt.encode("utf-8")).hexdigest()
    print("reinject %-28s v%s lines=%d row=%d" % (name, CHANGES[name], c["line_count"], idx + 1))

reg["last_updated"] = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S") + "+08:00"
json.dump(reg, open(RP, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

with open(JP, "w", encoding="utf-8", newline="") as fh:
    for o in objs:
        fh.write(json.dumps(o, ensure_ascii=False) + "\n")

# --- full re-verify: all 424 rows vs disk ---
bad = []
for o in objs:
    p = pou_of(o["output"])
    if not p:
        bad.append(("noPOU", None)); continue
    c = fmap.get(p)
    if not c:
        bad.append((p, "not-in-registry")); continue
    disk = open(c["file_path"].replace("\\\\", "\\"), encoding="utf-8", newline="").read()
    if hashlib.sha256(o["output"].encode("utf-8")).hexdigest() != \
       hashlib.sha256(disk.encode("utf-8")).hexdigest():
        bad.append((p, "sha-mismatch"))
print("FULL VERIFY: rows=%d mismatches=%d" % (len(objs), len(bad)), bad[:5])
print("registry total:", reg["total_components"], "counts:", reg["counts"], "ver:", reg["version"])
