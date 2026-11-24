# -*- coding: utf-8 -*-
"""R85 元数据+许可判定 + codeload 整仓抽取"""
import json, sys, io, os, re, tarfile, urllib.request, subprocess, hashlib
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TK}
REPOS = ["ZzzJjt/Industrial-Control", "ZzzJjt/IC-100", "Eguono22/PLC-Extruder-project",
         "FREEZONEX/ia2", "lusipad/plcopen", "Open-Industry-Project/Open-Industry-Project"]
meta = {}
for full in REPOS:
    try:
        r = urllib.request.urlopen(urllib.request.Request(
            "https://api.github.com/repos/" + full, headers=UA), timeout=30)
        d = json.loads(r.read().decode('utf-8'))
        lic = (d.get('license') or {}).get('spdx_id') or 'none'
        meta[full] = {'license': lic, 'size_kb': d.get('size'), 'stars': d.get('stargazers_count'),
                      'desc': (d.get('description') or '')[:120], 'default_branch': d.get('default_branch'),
                      'pushed': d.get('pushed_at')}
        print('%-42s %-16s size=%-7s star=%-4s %s' % (full, lic, d.get('size'), d.get('stargazers_count'), meta[full]['desc']))
    except Exception as e:
        meta[full] = {'license': 'ERR', 'err': str(e)[:80]}
        print('%-42s ERR %s' % (full, str(e)[:100]))
json.dump(meta, open(r'C:\Library\_Staging_Raw\2026-11-24\_r85_meta.json', 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
