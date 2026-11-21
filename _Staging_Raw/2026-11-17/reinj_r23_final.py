# -*- coding: utf-8 -*-
"""R23 final-audit re-injection: 7 components -> v1.0.1, JSONL row replace,
registry sync, full 404-row sha re-verify."""
import json, re, hashlib, os, datetime
os.chdir("C:/Library")
JP = "_AI_Training_Dataset/daoli_st_sft_dataset.jsonl"
RP = "INDEX_REGISTRY.json"

CHANGES = {  # name -> new version
 "FC_DL_DewPointCalc": "1.0.1",
 "FC_DL_HumidAirEnthalpy": "1.0.1",
 "FC_DL_MixAirStateCalc": "1.0.1",
 "FC_DL_WetBulbTempCalc": "1.0.1",
 "FB_DL_BagFeedDancerSync": "1.0.1",
 "FB_DL_HumidityOverride": "1.0.1",
 "FB_DL_ElectrolyteDosingSeq": "1.0.1",
}
# thought 漂移复核：重注入件 thought 内若有「未收敛即故障 2F11」类断言需人工确认——
# 本轮 7 件 thought 均为描述性，无码位/策略描述变化（v1.0.1 全部为防御闸/注释级）。

reg = json.load(open(RP, encoding="utf-8"))
fmap = {c["name"]: c for c in reg["components"]}

lines = open(JP, encoding="utf-8", newline="").readlines()
assert len(lines) == 404, len(lines)
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

# --- full re-verify: all 404 rows vs disk ---
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
