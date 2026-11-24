# -*- coding: utf-8 -*-
"""R83 第三轮：补齐 F2 纺织染整 / F3 电镀 —— 前两轮该两族命中近 0"""
import json, time, urllib.request, urllib.parse, collections

TOK = open(r"C:\Library\_tools\.gh_token").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TOK}

def gh(url):
    for k in range(3):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8", "replace"))
        except Exception as e:
            c = getattr(e, "code", None); print("   ERR", c, str(e)[:50])
            if c in (403, 429): time.sleep(20); continue
            return None

Q = [
    ("F2", '"FUNCTION_BLOCK" fabric'),
    ("F2", '"FUNCTION_BLOCK" knitting OR weaving'),
    ("F2", '"VAR_INPUT" dye OR liquor'),
    ("F3", '"FUNCTION_BLOCK" anodize OR cathode'),
    ("F3", '"FUNCTION_BLOCK" rectifier'),
    ("F5", '"FUNCTION_BLOCK" shuttle OR stacker'),
    ("F1", '"FUNCTION_BLOCK" anilox OR ink'),
    ("F4", '"FUNCTION_BLOCK" singulation OR chute'),
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

json.dump(rows, open(r"C:\Library\_Staging_Raw\2026-11-24\_r83_cs3.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
b = collections.Counter(r["repo"] for r in rows)
for repo, c in b.most_common(30):
    ps = [x["path"] for x in rows if x["repo"] == repo][:2]
    print("%-48s %d %-6s %s" % (repo, c, ",".join(sorted({x["fam"] for x in rows if x["repo"] == repo})), ps[0][:70]))
