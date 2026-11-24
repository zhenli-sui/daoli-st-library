# -*- coding: utf-8 -*-
import json, io, collections

STG = r"C:\Library\_Staging_Raw\2026-11-24"
Q = STG + r"\candidate_queue.jsonl"
BASE = 215

rows = [json.loads(l) for l in io.open(Q, encoding="utf-8") if l.strip()]
base, tail = rows[:BASE], rows[BASE:]

# 1) 标记工具重复入队的 2 行（不删行）
bnames = {r["name"].lower() for r in base}
bfp = {r.get("fp") for r in base}
marked = []
for r in tail:
    if not r.get("dropped") and (r["name"].lower() in bnames or r.get("fp") in bfp):
        r["dropped"] = True
        r["dropped_reason"] = "duplicate of pre-existing queue row (oss_harvest.py 不查队列缺陷, R84 复现)"
        r["dropped_by"] = "R86"
        marked.append(r["name"])

with io.open(Q, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

valid = [r for r in rows if not r.get("dropped")]
tier = collections.Counter(r["tier"] for r in valid)
stat = collections.Counter(r.get("status", "pending") for r in valid)
new_valid = [r for r in valid if r.get("harvested_at", "").startswith("2026-11-24T21:25")]

stats = {
    "total_rows": len(rows),
    "valid_rows": len(valid),
    "dropped_rows": len(rows) - len(valid),
    "tier": dict(tier),
    "status": dict(stat),
    "added_r86": len(new_valid),
    "added_r86_tier": dict(collections.Counter(r["tier"] for r in new_valid)),
    "marked_dropped_this_round": marked,
}
json.dump(stats, open(STG + r"\_r86_stats.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(json.dumps(stats, ensure_ascii=False, indent=1))
