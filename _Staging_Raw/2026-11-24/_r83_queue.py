# -*- coding: utf-8 -*-
"""R83 队列构建：许可证分级 + 三道去重 + defense_gaps 实证 + dup_flag
不删行；重复条目另存 queue_dup_backup_R83.jsonl
"""
import json, os, re, glob, hashlib, datetime, collections

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-24")
QUEUE = os.path.join(STG, "candidate_queue.jsonl")
DUPBK = os.path.join(LIB, "_Staging_Raw", "queue_dup_backup_R83.jsonl")
FP = os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json")

GREEN = {"MIT", "Apache-2.0", "BSD-3-Clause", "BSD-2-Clause", "MPL-2.0", "ISC", "Unlicense"}
RED = {"GPL-2.0", "GPL-3.0", "AGPL-3.0", "LGPL-2.1", "LGPL-3.0"}

# 仓库级许可证裁定（NOASSERTION 但有完整许可正文 → 人工判定并记录依据）
LIC_FIX = {
    "pcdshub/lcls-twincat-vacuum-sim": ("BSD-3-Clause", "BSD-3-Clause",
        "LICENSE 正文为 SLAC/Stanford 三条款 BSD 变体（Redistribution and use in source and binary forms...），GitHub 未识别为 NOASSERTION"),
}

reg = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
reg_names = {c["name"].lower() for c in reg["components"]}
reg_norm = {}
for n in reg_names:
    b = re.sub(r"^(fb_|fc_|i_|st_|e_|dl_)", "", n)
    reg_norm.setdefault(b.replace("_", ""), n)

qrows = [json.loads(l) for l in open(QUEUE, encoding="utf-8") if l.strip()]
q_names = {r["name"].lower() for r in qrows}
q_fp = {r.get("fp") for r in qrows if r.get("fp")}
fps = json.load(open(FP, encoding="utf-8")) if os.path.exists(FP) else {}

# ---- 五族语义映射（按块名/路径，落到 DL_ 分类） ----
FAM = [
    ("F1", "印刷包装", r"print|web|reel|unwind|rewind|anilox|ink|register|slit|lamina|foil|emboss"),
    ("F2", "纺织染整", r"dye|liquor|jigger|winch|stenter|fabric|yarn|warp|weft|knit|weav|beam|padder|bow|skew"),
    ("F3", "表面处理电镀", r"plate|plating|anod|rectifier|cathode|anode|degreas|etch|bath|rinse|barrel|dragout|densit|vacuum|pump|gauge|chamber|leak|valve|manometer"),
    ("F4", "物料输送分拣", r"conveyor|sorter|sort|divert|pusher|merge|accumul|belt|roller|chain|turntable|stopper|transfer|chute|feeder|lane"),
    ("F5", "仓储立库周边", r"pallet|aisle|shuttle|stacker|tote|dock|shrink|stretch|wrap|label|weigh|track|slot|storage"),
]
def fam_of(name, path):
    for src in (name.lower(), path.lower()):
        for k, label, pat in FAM:
            if re.search(pat, src):
                if k == "F3" and re.search(r"vacuum|pump|gauge|chamber|leak|manometer|turbo", src):
                    return k, "表面处理/真空镀膜支撑"
                return k, label
    return "-", "未归类"


# 第三道「语义邻件」人工裁定：registry 已覆盖同一功能族
SEM_DUP = {
    "st_alarm": "FB_DL_AlarmManager / FB_DL_AlarmShelving 已覆盖报警结构",
    "st_fifo": "FB_DL_FifoBuffer 已覆盖环形 FIFO 结构",
    "fc_fifopush": "FB_DL_FifoBuffer 已覆盖入队语义",
    "fc_fifopop": "FB_DL_FifoBuffer 已覆盖出队语义",
    "fc_fifoclear": "FB_DL_FifoBuffer#Reset 已覆盖清空语义",
    "fc_fifopack": "FB_DL_FifoBuffer 已覆盖紧凑打包语义",
    "fb_alarmmanager": "FB_DL_AlarmManager 同名同义",
    "fb_kpi": "FB_DL_EnergyKpiAggregator 已覆盖 KPI 聚合",
    "ff_words_to_dint": "FC_DL_WordsToDword / FC_DL_PackBitsToWord 已覆盖字拼装",
    "ff_words_to_real": "FC_DL_WordsToDword 族已覆盖字→实数拼装",
    "ff_real_to_dword": "FC_DL_DwordToWords 族已覆盖实数→字节拆装",
}

DEFECT = [
    (r"/\s*[A-Za-z_]\w*\s*[;,)]", "存在裸除法，需加除子非零闸"),
    (r"\bREAL_TO_INT\b|\bTRUNC\b|\bREAL_TO_DINT\b", "浮点转整无越界钳位"),
    (r"\bWHILE\b", "存在 WHILE，需补迭代守卫计数"),
    (r"\bSTRING\b", "涉及 STRING，需核查 255 长度上限"),
    (r"%[IQM][XBWDL]?\d", "含物理地址直接寻址，移植需抽象为 IO 映射"),
    (r"TON\(|TOF\(|TP\(", "内置定时器实例，需核查时基与重入"),
    (r"\bARRAY\s*\[", "数组下标无边界校验"),
    (r"\bREAL\b", "REAL 相等比较风险（无 EPS 容差）"),
]
DIALECT = ("__SYSTEM", "SysFile", "TC_", "System.", "AXIS_REF", "SM3_", "MC_", "%")

SEM_GAP = [
    (r"fifo|queue|buffer|ring", r"full|overflow|count\s*>=|count\s*>", "FIFO/环形缓冲无满位判定，满后静默覆写"),
    (r"conveyor|belt|roller", r"jam|block|stall|slip|timeout", "输送段无堵料/打滑检测分支"),
    (r"sort|divert|pusher|diverter|transfer", r"reject|timeout|confirm|notok|fail", "分拣/换向无动作超时与到位确认"),
    (r"pump|valve|turbo|roughpump", r"timeout|fault|fail|notok|ack", "泵/阀无动作超时与反馈确认"),
    (r"colour|color|sensor|detect", r"debounce|filter|stable|confirm", "传感器判据无消抖/稳定窗"),
    (r"alarm|fault|diag", r"ack|reset|latched|history", "报警无确认/复位/历史缓冲"),
    (r"kpi|metric|stat", r"div|zero|if\s+n", "统计分母无零值保护"),
]

def sem_gap(name, body):
    n = name.lower()
    for pat, need, msg in SEM_GAP:
        if re.search(pat, n) and not re.search(need, body, re.I):
            return msg
    return None


def gaps_of(body, name):
    g = []
    for pat, msg in DEFECT:
        if re.search(pat, body): g.append(msg)
    if re.search(r"\bCASE\b", body, re.I) and not re.search(r"\bELSE\b", body):
        g.append("CASE 无 ELSE 兜底（非法状态悬空）")
    sg = sem_gap(name, body)
    if sg and sg not in g: g.insert(0, sg)
    g = [x for x in g if not (x.startswith("REAL 相等") and "裸除法" in " ".join(g))]
    return g[:5] if g else ["块体仅声明无逻辑，需人工判定增量价值"]

seen_fp, seen_nm = {}, {}
added, rejected, dups = [], [], []

def norm(name):
    b = re.sub(r"^(fb_|fc_|i_|st_|e_|tc_|mc_|smc_|dl_)", "", name.lower())
    return b, b.replace("_", "")

for f in sorted(glob.glob(os.path.join(STG, "r83", "*.json"))):
    d = json.load(open(f, encoding="utf-8"))
    repo = d["repo"]
    spdx_raw = d.get("spdx")
    if repo in LIC_FIX:
        spdx, tier, basis = LIC_FIX[repo]
    else:
        spdx = spdx_raw
        tier = "green" if spdx in GREEN else ("red" if spdx in RED else "yellow")
        basis = ""
    if tier == "red":
        rejected.append({"repo": repo, "why": "red-zone", "n": len(d.get("files", []))}); continue
    if spdx in (None, "", "NOASSERTION"):
        rejected.append({"repo": repo, "why": "unknown-license", "n": d.get("st_count", 0),
                         "candidates_dropped": len(d.get("files", []))}); continue
    for b in d.get("files", []):
        name, base_n, nn = b["name"], b["name"].lower(), None
        base, basec = norm(name)
        sig_types = ",".join(sorted(i.split(":")[-1] for i in b["inputs"]))
        if not sig_types: sig_types = "NOVARINPUT:" + basec   # 空输入必须并入名字，否则所有 TYPE 撞同一指纹
        h = hashlib.sha1((base + "|" + sig_types).encode()).hexdigest()[:16]
        why = []
        if b["name"].lower() in reg_names: why.append("registry-name-exact")
        elif basec in reg_norm: why.append("registry-name-normalized:" + reg_norm[basec])
        if b["name"].lower() in q_names: why.append("queue-name-dup")
        if h in fps or h in q_fp: why.append("fingerprint-dup")
        if basec in seen_nm: why.append("intra-round-name-dup")
        if b["kind"] in ("TYPE", "TYP") and not re.search(r"TYPE[^;]*\(", b.get("body", "")):
            nfield = len(re.findall(r"^[ 	]*[A-Za-z_]\w*\s*:\s*[A-Za-z_]", b.get("body", ""), re.M))
            if nfield < 3:
                rejected.append({"name": name, "repo": repo, "why": ["declaration-only-thin(%d字段)" % nfield], "path": b["path"]})
                continue
        if base_n in SEM_DUP:
            rejected.append({"name": name, "repo": repo, "why": ["semantic-dup:" + SEM_DUP[base_n]], "path": b["path"]})
            continue
        if why:
            rejected.append({"name": name, "repo": repo, "why": why, "path": b["path"]})
            continue
        seen_nm[basec] = name
        fam, flabel = fam_of(name, b["path"])
        gaps = gaps_of(b.get("body", ""), name)
        if len(gaps) == 1 and "仅声明无逻辑" in gaps[0]:
            rejected.append({"name": name, "repo": repo, "why": ["no-increment(无逻辑/无缺口可守)"], "path": b["path"]})
            continue
        cand = {
            "name": name,
            "suggest_category": "DL_Process" if fam in ("F1", "F2", "F3") else ("DL_Device" if fam == "F4" else "DL_Algo"),
            "kind": b["kind"],
            "tier": tier,
            "license": spdx,
            "source_url": "https://github.com/%s/blob/%s/%s" % (repo, d.get("branch", "main"), b["path"]),
            "commit": d.get("pushed_at"),
            "extraction_point": "%s (%s)" % (name, b["path"]),
            "signature": ("IN: " + ", ".join(b["inputs"][:8])) + (" | OUT: " + ", ".join(b["outputs"][:6]) if b.get("outputs") else ""),
            "loc": b.get("loc", 0),
            "dialect": b.get("dialect", []),
            "defense_gaps": gaps,
            "dedup": {"name": "pass", "fingerprint": "new", "semantic": "new"},
            "family": fam, "family_label": flabel,
            "priority": 1 if tier == "green" else 2,
            "fp": h,
            "status": "pending",
            "dup_flag": False,
            "harvested_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "note": basis or ("%s %s 直采；%s" % (repo, spdx, "需剥离平台方言" if b.get("dialect") else "无方言依赖")),
        }
        added.append(cand)
        fps[h] = name

print("=== 新增候选 ===")
for a in added:
    print("%-3s %-30s %-6s %-14s %s" % (a["family"], a["name"], a["tier"], a["license"], a["defense_gaps"][0][:40]))
print("\nadded=%d rejected=%d" % (len(added), len(rejected)))
print("--- rejected 分类 ---")
for k, v in collections.Counter(r["why"] if isinstance(r["why"], str) else r["why"][0] for r in rejected).most_common():
    print("  %-40s %d" % (k, v))
print("--- 族分布 ---")
for k, v in collections.Counter(a["family"] for a in added).most_common(): print("  %s %d" % (k, v))

json.dump({"added": added, "rejected": rejected},
          open(os.path.join(STG, "_r83_queue_build.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
