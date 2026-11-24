# -*- coding: utf-8 -*-
"""R84 许可证人工裁定：spdx=null 的仓，检查 LICENSE/COPYING/README 里的明确许可声明"""
import json, base64, urllib.request, urllib.parse, re

TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TK}

REPOS = ["Billal-MOKHTARI/ics_battery_manufacturing_under_normal_and_attack_conditions",
         "dberlin/Beckhoff-CNC-PLC",
         "NiklasEngineering/Jacob-Formschaumtechnik-ISEL-CNC-Retrofit",
         "DziadekMateusz/Przewijarka_BR_Praktyki",
         "Prathap20/siemens-s7-1500-robotic-cnc-cell",
         "trianglexx/fse"]

def get(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"_err": str(e)}

PAT = re.compile(r"(MIT License|Apache License|BSD 3-Clause|BSD 2-Clause|GNU (?:LESSER )?GENERAL PUBLIC LICENSE|"
                 r"GPL-?[23]|AGPL|Mozilla Public License|Eclipse Public License|ISC License|"
                 r"Permission is hereby granted, free of charge|Licensed under the Apache License)", re.I)

for full in REPOS:
    d = get("https://api.github.com/repos/%s/contents/" % full)
    if isinstance(d, dict):
        print("%-50s ROOT-FAIL" % full[:50]); continue
    names = [x["name"] for x in d]
    lic = [n for n in names if re.match(r"(LICEN[SC]E|COPYING|NOTICE)", n, re.I)]
    readme = [n for n in names if re.match(r"README", n, re.I)]
    print("==", full)
    print("   root license files:", lic, "| readme:", readme[:1])
    for fn in lic[:2]:
        c = get("https://api.github.com/repos/%s/contents/%s" % (full, urllib.parse.quote(fn)))
        if isinstance(c, dict) and c.get("content"):
            txt = base64.b64decode(c["content"]).decode("utf-8", "replace")
            m = PAT.search(txt)
            print("   [%s] %d bytes | first-line: %s | match: %s" %
                  (fn, len(txt), txt.strip().split("\n")[0][:70], m.group(0) if m else "NONE"))
    if readme:
        c = get("https://api.github.com/repos/%s/contents/%s" % (full, urllib.parse.quote(readme[0])))
        if isinstance(c, dict) and c.get("content"):
            txt = base64.b64decode(c["content"]).decode("utf-8", "replace")
            m = PAT.search(txt)
            print("   [README] %d bytes | license mention: %s" % (len(txt), m.group(0) if m else "NONE"))
