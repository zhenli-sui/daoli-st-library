# -*- coding: utf-8 -*-
"""R84 定向 code search：六族工艺词 + ST 语法 token（R83 经验：extension:st 撞 Smalltalk）"""
import json, sys, time, urllib.request, urllib.parse, os

TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Accept": "application/vnd.github.text-match+json",
      "Authorization": "Bearer " + TK}

QUERIES = [
    # 族A 光伏
    ('A', '"FUNCTION_BLOCK" photovoltaic'),
    ('A', '"FUNCTION_BLOCK" solar cell'),
    ('A', '"FUNCTION_BLOCK" laminator'),
    # 族B 锂电涂布
    ('B', '"FUNCTION_BLOCK" coating weight'),
    ('B', '"FUNCTION_BLOCK" web tension'),
    ('B', '"FUNCTION_BLOCK" calender'),
    # 族C 机加工
    ('C', '"FUNCTION_BLOCK" tool wear'),
    ('C', '"FUNCTION_BLOCK" tool life'),
    ('C', '"FUNCTION_BLOCK" CNC'),
    # 族D 反应釜
    ('D', '"FUNCTION_BLOCK" batch reactor'),
    ('D', '"FUNCTION_BLOCK" exotherm'),
    ('D', '"FUNCTION_BLOCK" jacket temperature'),
    # 族E 制药
    ('E', '"FUNCTION_BLOCK" tablet'),
    ('E', '"FUNCTION_BLOCK" granulation'),
    ('E', '"FUNCTION_BLOCK" coating pan'),
    # 复杂件
    ('X', '"FUNCTION_BLOCK" areal density'),
    ('X', '"FUNCTION_BLOCK" runaway'),
    ('X', '"FUNCTION_BLOCK" dosage'),
]

out = []
for fam, q in QUERIES:
    url = ("https://api.github.com/search/code?q=%s&per_page=30"
           % urllib.parse.quote(q))
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.loads(r.read().decode("utf-8", "replace"))
        items = d.get("items", [])
        print("%s %-42s hits=%s" % (fam, q, d.get("total_count")), flush=True)
        for it in items:
            out.append({"family": fam, "query": q, "repo": it["repository"]["full_name"],
                        "path": it["path"],
                        "url": it["html_url"]})
    except urllib.error.HTTPError as e:
        print("%s %-42s HTTP %s %s" % (fam, q, e.code, e.read()[:160]), flush=True)
    except Exception as e:
        print("%s %-42s ERR %s" % (fam, q, e), flush=True)
    time.sleep(7)  # code search 10/min

json.dump(out, open(r"C:\Library\_Staging_Raw\2026-11-24\_r84_cs.json", "w",
                    encoding="utf-8"), ensure_ascii=False, indent=1)
print("total hits rows:", len(out))
