# -*- coding: utf-8 -*-
"""R84 候选仓体检：license / ST 文件数（REST 2 次/仓）"""
import json, urllib.request, urllib.parse

TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TK}
ST_EXT = (".st", ".scl", ".exp", ".iecst", ".tcpou", ".tcdut", ".tcpro", ".tcprg")

REPOS = [
    "Billal-MOKHTARI/ics_battery_manufacturing_under_normal_and_attack_conditions",
    "Beckhoff-USA-Community/SPT-Libraries",
    "dberlin/Beckhoff-CNC-PLC",
    "NiklasEngineering/Jacob-Formschaumtechnik-ISEL-CNC-Retrofit",
    "Prathap20/siemens-s7-1500-robotic-cnc-cell",
    "EstebanQuerol/UJI_CNC_IEC61499",
    "ZzzJjt/Industrial-Control",
    "ZzzJjt/IC-100",
    "DziadekMateusz/Przewijarka_BR_Praktyki",
    "joyautomation/nautilus",
    "brentjm/chemical-process-digital-twin",
    "Aneesh495/gantry",
    "CristhianARV/pi",
    "mrcjkb/Polysun-4diac-ControllerPlugin",
    "trianglexx/fse",
    "Gorke07/OpenDVP",
]

def get(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"_err": str(e)}

out = {}
for full in REPOS:
    m = get("https://api.github.com/repos/" + full)
    if "_err" in m or "full_name" not in m:
        print("%-60s META-FAIL %s" % (full, str(m)[:60])); out[full] = {"err": str(m)[:80]}; continue
    spdx = (m.get("license") or {}).get("spdx_id")
    br = m.get("default_branch")
    t = get("https://api.github.com/repos/%s/git/trees/%s?recursive=1" % (full, br))
    files = [x for x in t.get("tree", []) if x.get("type") == "blob"
             and x["path"].lower().endswith(ST_EXT)]
    tot = sum(f.get("size", 0) for f in files)
    print("%-58s %-14s br=%-8s ST=%-4d %6.1fMB stars=%s" %
          (full[:58], spdx, br, len(files), tot / 1e6, m.get("stargazers_count")))
    out[full] = {"spdx": spdx, "branch": br, "st_files": len(files),
                 "size_mb": round(tot / 1e6, 2), "files": [f["path"] for f in files][:400]}

json.dump(out, open(r"C:\Library\_Staging_Raw\2026-11-24\_r84_repos.json", "w",
                    encoding="utf-8"), ensure_ascii=False, indent=1)
