# -*- coding: utf-8 -*-
"""R84 code search 第三轮：工艺专属术语（MPPT/失重秤/砂轮修整/压片）"""
import json, time, urllib.request, urllib.parse

TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TK}

QUERIES = [
    ('A', '"FUNCTION_BLOCK" MPPT'),
    ('A', '"FUNCTION_BLOCK" irradiance'),
    ('A', '"FUNCTION_BLOCK" pyranometer'),
    ('A', '"FUNCTION_BLOCK" "string monitoring"'),
    ('B', '"FUNCTION_BLOCK" "loss in weight"'),
    ('B', '"FUNCTION_BLOCK" "weigh feeder"'),
    ('B', '"FUNCTION_BLOCK" slitting'),
    ('B', '"FUNCTION_BLOCK" "web guide"'),
    ('C', '"FUNCTION_BLOCK" dressing'),
    ('C', '"FUNCTION_BLOCK" "wear compensation"'),
    ('C', '"FUNCTION_BLOCK" "tool offset"'),
    ('D', '"FUNCTION_BLOCK" autoclave'),
    ('D', '"FUNCTION_BLOCK" reflux'),
    ('D', '"FUNCTION_BLOCK" reactor'),
    ('E', '"FUNCTION_BLOCK" blister'),
    ('E', '"FUNCTION_BLOCK" capsule'),
    ('E', '"FUNCTION_BLOCK" "coating drum"'),
    ('X', '"FUNCTION_BLOCK" "closed loop" density'),
]

out = []
for fam, q in QUERIES:
    url = "https://api.github.com/search/code?q=%s&per_page=20" % urllib.parse.quote(q)
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.loads(r.read().decode("utf-8", "replace"))
        print("%s %-46s hits=%s" % (fam, q, d.get("total_count")), flush=True)
        for it in d.get("items", []):
            out.append({"family": fam, "query": q, "repo": it["repository"]["full_name"], "path": it["path"]})
    except urllib.error.HTTPError as e:
        print("%s %-46s HTTP %s" % (fam, q, e.code), flush=True)
    except Exception as e:
        print("%s %-46s ERR %s" % (fam, q, e), flush=True)
    time.sleep(7)

json.dump(out, open(r"C:\Library\_Staging_Raw\2026-11-24\_r84_cs3.json", "w",
                    encoding="utf-8"), ensure_ascii=False, indent=1)
print("rows:", len(out))
