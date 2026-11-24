# -*- coding: utf-8 -*-
import json, io

STG = r"C:\Library\_Staging_Raw\2026-11-24"
MAN = r"C:\Library\_Staging_Raw\_harvest_manifest.json"

man = json.load(open(MAN, encoding="utf-8"))
man["round"] = "R86"
man["finished"] = "2026-11-24T21:28:00+08:00"
man["note"] = ("前置 3 仓为任务书强制命令 oss_harvest.py --search --max-repos 3 的产出（与 R73/R74 同 3 仓，命中 2 条与存量重复，已标 dropped）；"
               "本轮真实增量来自 code search 定向 + codeload 整仓抽取。")

# 前置 3 仓（强制命令）标注重复
for k in list(man["repos"].keys()):
    man["repos"][k]["origin"] = "mandated --search (rescan of R73/R74, 0 net new)"

meta = json.load(open(STG + r"\_r86_meta.json", encoding="utf-8"))

for full, v in meta.items():
    spdx = v.get("spdx")
    tier = "green" if spdx in ("MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "MPL-2.0", "ISC") else "yellow"
    man["repos"][full] = {
        "spdx": spdx, "tier": tier, "stars": v.get("stars"),
        "url": "https://github.com/" + full, "st_files": v.get("n_st"),
        "files_listed": min(v.get("n_st") or 0, 12), "origin": "code search 定向查询 (R86)",
    }

# 人工裁定：AGPL 红区（GitHub API 报 NOASSERTION，LICENSE 实为 AGPL-3.0）
man["repos"]["mod-bee/modbee-openplc"]["tier"] = "red"
man["repos"]["mod-bee/modbee-openplc"]["license_adjudication"] = (
    "GitHub API license=NOASSERTION，但仓库根 LICENSE 正文为 GNU AFFERO GPL v3 —— 按红区处理；"
    "本地 tar.gz 已删除，零代码入队，仅登记思想（阀位-阀座-行程三参诊断的分级判据结构）")
man["red_quarantine"] = sorted(set(man.get("red_quarantine", []) + ["mod-bee/modbee-openplc"]))

man["repos"]["simatic-ax/LAxisCtrl"]["license_adjudication"] = (
    "SPDX 检测为 NOASSERTION，实际为 Siemens『Royalty-free Licensed Material』v1.4（闭源文档类）→ 按黄区只借骨")
man["repos"]["simatic-ax/LAxisCtrl"]["files_fetched_ok"] = 58
man["repos"]["simatic-ax/LAxisCtrl"]["candidates"] = 10

man["rejected"].extend([
    {"repo": "Chenjie1002/Lee_Workshop", "why": "无 LICENSE(unknown) + 0 个 ST 文本文件"},
    {"repo": "brentjm/chemical-process-digital-twin", "why": "无 LICENSE(unknown) + 0 个 ST 文件（反应釜夹套为 Python 仿真）"},
    {"repo": "DavidWenzler/reAM250", "why": "NOASSERTION + 0 个 ST 文件"},
    {"repo": "Aneesh495/gantry", "why": "MIT 但 0 个 ST 文件（仅 gantry 配置/文档）"},
    {"repo": "Beckhoff-USA-Community/SPT-Libraries", "why": "codeload master 分支 404/非 gzip，本轮未取得内容（不计入）"},
    {"name": "VAR_INPUT", "repo": "OttoMeister/Siemens-Tia-Portal-PID-Controller", "why": ["dup-of-queue"]},
    {"name": "E_SMStatus", "repo": "RWTH-EBC/AixOCAT", "why": ["dup-of-queue"]},
])

man["added"] = 10
man["added_tier"] = {"green": 0, "yellow": 10, "red": 0}
json.dump(man, open(MAN, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("manifest repos:", len(man["repos"]), "| red:", man["red_quarantine"], "| added:", man["added"])
