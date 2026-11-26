# -*- coding: utf-8 -*-
"""R88 收口：标脏行 dropped（不删行）+ append 12 条绿区候选 + 更新指纹库 + 统计。"""
import json, collections, datetime

Q = r"C:\Library\_Staging_Raw\2026-11-25\candidate_queue.jsonl"
FP = r"C:\Library\_Staging_Raw\_dedup_fingerprints.json"

lines = [l for l in open(Q, encoding="utf-8") if l.strip()]
rows = [json.loads(l) for l in lines]

# 1) 强制命令直写的 2 行：垃圾名 / 存量重复 -> 标 dropped
marked = 0
for r in rows[209:]:
    if r["name"] == "VAR_INPUT":
        r["status"] = "dropped"; r["drop_reason"] = "SIG 正则从注释/多行声明误捕关键字，非块名（R84 已知缺陷）"; marked += 1
    elif r["name"] == "E_SMStatus" and r["license"] == "MIT" and "AixOCAT" in r.get("source_url", ""):
        r["status"] = "dropped"; r["drop_reason"] = "跨轮重名，队列已有同名同源条目（R87 同类）"; marked += 1

# 2) append 新候选
add = json.load(open(r"C:\Library\_Staging_Raw\2026-11-25\_r88_add.json", encoding="utf-8"))
rows.extend(add)

# 3) 回写队列
with open(Q, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

# 4) 指纹库
fp = json.load(open(FP, encoding="utf-8"))
for a in add:
    fp[a["fp"]] = a["name"]
json.dump(fp, open(FP, "w", encoding="utf-8"), ensure_ascii=False, indent=0)

# 5) 统计
eff = [r for r in rows if r.get("status") != "dropped"]
tc = collections.Counter(r["tier"] for r in eff)
print("total lines      :", len(rows))
print("dropped lines    :", len(rows) - len(eff))
print("effective        :", len(eff))
print("tier distribution:", dict(tc))
print("added this round :", len(add))
print("new tier dist    :", dict(collections.Counter(a["tier"] for a in add)))
print("licenses added   :", dict(collections.Counter(a["license"] for a in add)))
print("categories added :", dict(collections.Counter(a["suggest_category"] for a in add)))
print("fingerprints     :", len(fp))
