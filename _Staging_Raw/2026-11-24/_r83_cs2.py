# -*- coding: utf-8 -*-
"""R83 第二轮 code search：用 ST 语法 token + 五族工艺词，排除 Smalltalk 噪音"""
import json, time, urllib.request, urllib.parse, collections

TOK = open(r"C:\Library\_tools\.gh_token").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TOK}
OUT = r"C:\Library\_Staging_Raw\2026-11-24\_r83_cs2.json"

def gh(url):
    for k in range(3):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8", "replace"))
        except Exception as e:
            c = getattr(e, "code", None)
            print("   ERR", c, str(e)[:60])
            if c in (403, 429): time.sleep(20); continue
            return None
    return None

Q = [
    ("F2", '"FUNCTION_BLOCK" dyeing'),
    ("F2", '"FUNCTION_BLOCK" textile'),
    ("F2", '"FUNCTION_BLOCK" yarn'),
    ("F2", '"FUNCTION_BLOCK" warp beam'),
    ("F3", '"FUNCTION_BLOCK" plating'),
    ("F3", '"FUNCTION_BLOCK" electroplating'),
    ("F3", '"FUNCTION_BLOCK" anodizing OR degreasing'),
    ("F3", '"VAR_INPUT" rectifier current'),
    ("F4", '"FUNCTION_BLOCK" sorter'),
    ("F4", '"FUNCTION_BLOCK" conveyor accumulation'),
    ("F4", '"FUNCTION_BLOCK" diverter'),
    ("F1", '"FUNCTION_BLOCK" web guide'),
    ("F1", '"FUNCTION_BLOCK" printing register'),
    ("F5", '"FUNCTION_BLOCK" pallet wrapper OR stretch'),
]
rows = []
for fam, q in Q:
    d = gh("https://api.github.com/search/code?q=%s&per_page=20" % urllib.parse.quote(q))
    items = (d or {}).get("items", [])
    print("%-3s total=%-5s got=%-3s %s" % (fam, (d or {}).get("total_count", 0), len(items), q))
    for it in items:
        rows.append({"fam": fam, "query": q, "repo": it["repository"]["full_name"],
                     "path": it["path"], "branch": it["repository"].get("default_branch", "main")})
    time.sleep(6.5)

json.dump(rows, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
b = collections.Counter(r["repo"] for r in rows)
print("\n=== repos ===")
for repo, c in b.most_common(40):
    print("%-50s %d %s" % (repo, c, ",".join(sorted({x["fam"] for x in rows if x["repo"] == repo}))))
print("unique:", len(b), "hits:", len(rows))
