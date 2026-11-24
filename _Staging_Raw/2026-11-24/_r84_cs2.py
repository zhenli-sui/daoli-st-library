# -*- coding: utf-8 -*-
"""R84 code search 第二轮：更专有的工艺词（避开通用词噪声）"""
import json, time, urllib.request, urllib.parse

TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TK}

QUERIES = [
    ('A', '"FUNCTION_BLOCK" stringer'),
    ('A', '"FUNCTION_BLOCK" "IV curve"'),
    ('A', '"FUNCTION_BLOCK" electroluminescence'),
    ('B', '"FUNCTION_BLOCK" rewinder'),
    ('B', '"FUNCTION_BLOCK" unwind'),
    ('B', '"FUNCTION_BLOCK" "dancer"'),
    ('C', '"FUNCTION_BLOCK" "spindle"'),
    ('C', '"FUNCTION_BLOCK" "tool breakage"'),
    ('D', '"FUNCTION_BLOCK" "cooling jacket"'),
    ('D', '"FUNCTION_BLOCK" exothermic'),
    ('D', '"FUNCTION_BLOCK" "recipe" "dosing"'),
    ('E', '"FUNCTION_BLOCK" "tablet press"'),
    ('E', '"FUNCTION_BLOCK" "fluid bed"'),
    ('E', '"FUNCTION_BLOCK" "film coating"'),
    ('X', '"FUNCTION_BLOCK" "basis weight"'),
    ('X', '"FUNCTION_BLOCK" "grammage"'),
]

out = []
for fam, q in QUERIES:
    url = "https://api.github.com/search/code?q=%s&per_page=30" % urllib.parse.quote(q)
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.loads(r.read().decode("utf-8", "replace"))
        print("%s %-44s hits=%s" % (fam, q, d.get("total_count")), flush=True)
        for it in d.get("items", []):
            out.append({"family": fam, "query": q, "repo": it["repository"]["full_name"], "path": it["path"]})
    except urllib.error.HTTPError as e:
        print("%s %-44s HTTP %s" % (fam, q, e.code), flush=True)
    except Exception as e:
        print("%s %-44s ERR %s" % (fam, q, e), flush=True)
    time.sleep(7)

json.dump(out, open(r"C:\Library\_Staging_Raw\2026-11-24\_r84_cs2.json", "w",
                    encoding="utf-8"), ensure_ascii=False, indent=1)
print("rows:", len(out))
