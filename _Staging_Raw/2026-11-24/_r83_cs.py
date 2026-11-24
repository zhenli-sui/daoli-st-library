# -*- coding: utf-8 -*-
"""R83 定向 code search：五族垂直工艺词，找出真实存在 ST 代码的仓库"""
import json, time, urllib.request, urllib.parse, os, collections

TOK = open(r"C:\Library\_tools\.gh_token").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TOK}

def gh(url):
    for k in range(3):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8", "replace"))
        except Exception as e:
            code = getattr(e, "code", None)
            print("   ERR", code, str(e)[:60])
            if code in (403, 429):
                time.sleep(15); continue
            return None
    return None

QUERIES = [
    # F2 纺织染整
    ("F2", "dyeing extension:st"),
    ("F2", "stenter extension:st"),
    ("F2", "yarn tension extension:st"),
    ("F2", "jigger OR winch dyeing extension:st"),
    # F3 表面处理电镀
    ("F3", "plating rectifier extension:st"),
    ("F3", "anodizing extension:st"),
    ("F3", "electroplating extension:st"),
    # F4 输送分拣
    ("F4", "sorter conveyor extension:st"),
    ("F4", "accumulation conveyor extension:st"),
    # F1 印刷包装
    ("F1", "web guide tension extension:st"),
    ("F1", "flexo printing extension:st"),
    # F5 立库周边
    ("F5", "stretch wrapper pallet extension:st"),
]

rows = []
for fam, q in QUERIES:
    url = ("https://api.github.com/search/code?q=%s&per_page=20" % urllib.parse.quote(q))
    d = gh(url)
    n = (d or {}).get("total_count", 0)
    items = (d or {}).get("items", [])
    print("%-3s total=%-5s got=%-3s %s" % (fam, n, len(items), q))
    for it in items:
        rows.append({"fam": fam, "query": q, "repo": it["repository"]["full_name"],
                     "path": it["path"],
                     "stars": it["repository"].get("stargazers_count", 0),
                     "branch": it["repository"].get("default_branch", "main")})
    time.sleep(7)

json.dump(rows, open(r"C:\Library\_Staging_Raw\2026-11-24\_r83_cs.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)

by = collections.Counter(r["repo"] for r in rows)
print("\n=== repos by hit count ===")
for r, c in by.most_common(40):
    fams = sorted({x["fam"] for x in rows if x["repo"] == r})
    print("%-52s %-3d %s" % (r, c, ",".join(fams)))
print("\nunique repos:", len(by), "| total hits:", len(rows))
