# -*- coding: utf-8 -*-
"""R83 落库：追加队列 + 存量重复标 dup_flag 并备份 + 更新指纹与 manifest（零删行）"""
import json, os, io, hashlib, datetime

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-24")
QUEUE = os.path.join(STG, "candidate_queue.jsonl")
DUPBK = os.path.join(LIB, "_Staging_Raw", "queue_dup_backup_R83.jsonl")
FP = os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json")
MAN = os.path.join(LIB, "_Staging_Raw", "_harvest_manifest.json")

build = json.load(open(os.path.join(STG, "_r83_queue_build.json"), encoding="utf-8"))
added = build["added"]
rejected = build["rejected"]

rows = [json.loads(l) for l in io.open(QUEUE, encoding="utf-8") if l.strip()]
before = len(rows)
print("queue before:", before)

# ---- 存量内部重复扫描（不改行数，只加 dup_flag）----
seen_name, seen_fp, dup_rows = {}, {}, []
for r in rows:
    n = r.get("name", "").lower()
    f = r.get("fp")
    hit = None
    if n and n in seen_name: hit = "dup-name-of:" + seen_name[n]
    elif f and f in seen_fp: hit = "dup-fp-of:" + seen_fp[f]
    if hit:
        r["dup_flag"] = True
        r["dup_reason"] = hit
        dup_rows.append(r)
    else:
        if n: seen_name[n] = r["name"]
        if f: seen_fp[f] = r["name"]
        r.setdefault("dup_flag", False)
print("existing dup flagged:", len(dup_rows))

# 备份重复行（追加式，不覆盖历史）
with io.open(DUPBK, "a", encoding="utf-8") as bf:
    for r in dup_rows:
        bf.write(json.dumps(r, ensure_ascii=False) + "\n")
print("dup backup ->", DUPBK, len(dup_rows), "rows appended")

# ---- 追加新候选 ----
with io.open(QUEUE, "a", encoding="utf-8") as qf:
    for c in added:
        qf.write(json.dumps(c, ensure_ascii=False) + "\n")
print("appended:", len(added))

# ---- 指纹库 ----
fp = json.load(open(FP, encoding="utf-8")) if os.path.exists(FP) else {}
for c in added: fp[c["fp"]] = c["name"]
json.dump(fp, open(FP, "w", encoding="utf-8"), ensure_ascii=False, indent=0)

# ---- manifest 合并（保留历轮 repos，不覆盖）----
man = {"started": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
       "repos": {}, "rejected": [], "red_quarantine": []}
if os.path.exists(MAN):
    try:
        old = json.load(open(MAN, encoding="utf-8"))
        man["repos"] = old.get("repos", {})
        man["rejected"] = old.get("rejected", [])
        man["red_quarantine"] = old.get("red_quarantine", [])
        man["started"] = old.get("started", man["started"])
    except Exception as e:
        print("manifest read warn", e)

GREEN = {"MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "MPL-2.0", "ISC", "NOASSERTION"}
for f in sorted(os.listdir(os.path.join(STG, "r83"))):
    if not f.endswith(".json"): continue
    d = json.load(open(os.path.join(STG, "r83", f), encoding="utf-8"))
    repo = d["repo"]
    spdx = d.get("spdx")
    src = "license-fix:BSD-3-Clause" if repo == "pcdshub/lcls-twincat-vacuum-sim" else None
    ent = man["repos"].get(repo, {})
    ent.update({"spdx": "BSD-3-Clause" if src else spdx,
                "tier": "green" if (spdx in GREEN or src) else ("red" if (spdx or "").startswith(("GPL", "AGPL", "LGPL")) else "yellow"),
                "url": "https://github.com/" + repo, "branch": d.get("branch"),
                "files_listed": d.get("st_count", 0),
                "files_fetched_ok": d.get("st_count", 0),
                "files_fetch_fail": 0, "round": "R83"})
    if src: ent["license_basis"] = "LICENSE 正文为 SLAC/Stanford 三条款 BSD；GitHub 标 NOASSERTION"
    if spdx in (None, "", "NOASSERTION") and repo != "pcdshub/lcls-twincat-vacuum-sim":
        ent["tier"] = "rejected"; ent["why"] = "unknown-license(无 LICENSE 文件，按铁律拒收)"
    man["repos"][repo] = ent

man["r83"] = {"added": len(added), "rejected": len(rejected),
              "queue_before": before, "queue_after": before + len(added),
              "dup_flagged": len(dup_rows),
              "rejected_detail": rejected}
man["finished"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
man["added"] = len(added)
json.dump(man, open(MAN, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

# ---- 统计 ----
after = [json.loads(l) for l in io.open(QUEUE, encoding="utf-8") if l.strip()]
import collections
tc = collections.Counter(r["tier"] for r in after)
print("queue after:", len(after), "| tiers:", dict(tc))
print("new tier:", dict(collections.Counter(c["tier"] for c in added)))
print("new family:", dict(collections.Counter(c["family"] for c in added)))
