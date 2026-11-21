# -*- coding: utf-8 -*-
"""oss_harvest.py - 开源资产采集器（第一版）

流程：GitHub 检索 → 许可证分级 → 目录树过滤 → 原始文件抓取 → 签名抽取 → 三道去重 → 候选队列
约束：
  - 只用匿名 API（60 次/小时 core，10 次/分钟 search）；不做任何写操作。
  - 红区（GPL/AGPL）不入队，只记 manifest 供人工读思想。
  - 每条候选必须带 source_url / license / tier / defense_gaps。

用法：
  python oss_harvest.py --search --max-repos 18 --max-files-per-repo 25
  python oss_harvest.py --repo TcOpen/TcOpen --max-files 40
  python oss_harvest.py --stats
"""
import argparse, base64, hashlib, io, json, os, re, sys, time, urllib.request, urllib.error, datetime

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", datetime.date.today().isoformat())
QUEUE = os.path.join(STG, "candidate_queue.jsonl")
FP = os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json")
MANIFEST = os.path.join(LIB, "_Staging_Raw", "_harvest_manifest.json")
UA = {"User-Agent": "daoli-oss-hunter/1.0 (research; contact: local)"}
ST_EXT = (".st", ".scl", ".exp", ".iecst", ".tcpou", ".tcdut", ".tcpro", ".tcprg", ".st.txt")
GREEN = {"MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "MPL-2.0", "ISC", "Unlicense"}
YELLOW = {"EPL-1.0", "EPL-2.0", "OSCAT", "NOASSERTION", None, ""}
RED = {"GPL-2.0", "GPL-3.0", "AGPL-3.0", "LGPL-2.1", "LGPL-3.0", "GPL-2.0-only", "GPL-2.0-or-later"}

def api(url, tries=3):
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=25) as r:
                return json.loads(r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):
                print("   rate-limited, sleep 20s"); time.sleep(20); continue
            if e.code == 404: return None
            print("   HTTP", e.code, url[:90]); return None
        except Exception as e:
            print("   ERR", e); time.sleep(3)
    return None

def raw(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None

def load_registry_names():
    d = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
    names = {c["name"].lower() for c in d["components"]}
    norm = set()
    for n in names:
        m = re.sub(r"^(fb_|fc_|i_|st_|e_|dl_)", "", n)
        m = re.sub(r"^(dl_)", "", m)
        norm.add(m.replace("_", ""))
    return names, norm

def load_fingerprints():
    if os.path.exists(FP): return json.load(open(FP, encoding="utf-8"))
    return {}

def save_fingerprints(fp):
    json.dump(fp, open(FP, "w", encoding="utf-8"), ensure_ascii=False, indent=0)

SIG = re.compile(r"^\s*(FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE)\s+(?:[\w]+\s+)?([A-Za-z_]\w*)", re.I | re.M)
VARIN = re.compile(r"VAR_INPUT(.*?)END_VAR", re.I | re.S)

def unwrap_tc_xml(txt):
    """TwinCAT/CODESYS XML POU：抽 <Declaration> 与 <ST> CDATA，拼成可解析文本。"""
    if not txt.lstrip().startswith("<"):
        return txt
    parts = []
    for m in re.finditer(r"<(Declaration|ST)>(.*?)</\1>", txt, re.S):
        body = m.group(2)
        body = body.replace("<![CDATA[", "").replace("]]>", "")
        body = re.sub(r"&lt;", "<", body); body = re.sub(r"&gt;", ">", body)
        body = re.sub(r"&amp;", "&", body); body = re.sub(r"&quot;", '"', body)
        parts.append(body)
    return "\n".join(parts) if parts else txt

def extract_signatures(text, rel):
    out = []
    for m in SIG.finditer(text):
        kind, name = m.group(1).upper(), m.group(2)
        seg = text[m.start(): m.start() + 4000]
        vi = VARIN.search(seg)
        inputs = []
        if vi:
            for line in vi.group(1).split("\n"):
                mm = re.match(r"\s*([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.\[\]\.]*)\s*[;:]", line)
                if mm: inputs.append(f"{mm.group(1)}:{mm.group(2)}")
        loc = text.count("\n") + 1
        out.append({"kind": "FB" if kind == "FUNCTION_BLOCK" else ("FC" if kind == "FUNCTION" else kind[:4]),
                    "name": name, "inputs": inputs, "rel": rel, "loc": loc})
    return out

def dedup(name, inputs, names, norm, fp):
    low = name.lower()
    base = re.sub(r"^(fb_|fc_|i_|st_|e_|tc_|mc_|smc_|dl_)", "", low)
    norm_base = base.replace("_", "")
    hits = []
    if low in names: hits.append("name-exact")
    if norm_base in norm: hits.append("name-normalized")
    h = hashlib.sha1((base + "|" + ",".join(sorted(i.split(":")[1] for i in inputs))).encode()).hexdigest()[:16]
    if h in fp: hits.append("fingerprint:" + fp[h])
    return hits, h

def tier_of(spdx):
    if spdx in RED: return "red"
    if spdx in GREEN: return "green"
    return "yellow"

def guess_category(name, text):
    t = (name + " " + text[:3000]).lower()
    if any(k in t for k in ("axis", "motion", "servo", "cam", "jog", "homing")): return "DL_Motion"
    if any(k in t for k in ("valve", "pump", "vfd", "motor", "sensor", "drive", "heater")): return "DL_Device"
    if any(k in t for k in ("batch", "pack", "pallet", "conveyor", "bottle", "cip", "recipe")): return "DL_Process"
    if any(k in t for k in ("filter", "pid", "control", "observer", "kalman", "fft")): return "DL_Algo"
    if any(k in t for k in ("sqrt", "sin", "cos", "stat", "mean", "median", "matrix", "array")): return "DL_MathData"
    return "DL_Base"

DEFECT_HINTS = [
    (r"/\s*[A-Za-z_]\w*\s*(?:;|,)", "存在裸除法，需检查除子闸"),
    (r"\bREAL_TO_INT\b|\bTRUNC\b", "存在浮点转整，需检查越界钳位"),
    (r"\bWHILE\b", "存在 WHILE，需检查守卫计数"),
    (r"\bSTRING\b", "涉及字符串，需检查 255 长度上限"),
    (r"%[IQM]", "含物理地址直接寻址，移植时需抽象"),
    (r"__SYSTEM|SysFile|TC_|System\.", "含平台方言依赖，clean-room 时需剥离"),
]

def gaps_of(text):
    g = []
    for pat, msg in DEFECT_HINTS:
        if re.search(pat, text): g.append(msg)
    if not re.search(r"(?-i:\bELSE\b)", text) and re.search(r"\bCASE\b", text, re.I):
        g.append("CASE 无 ELSE 兜底")
    if not g: g.append("未见明显防御缺口，需人工判定增量价值")
    return g[:5]

def harvest_repo(full, max_files, names, norm, fp, queue_f, manifest):
    meta = api("https://api.github.com/repos/" + full)
    if not meta:
        print("  skip (meta null)", full); return 0
    spdx = (meta.get("license") or {}).get("spdx_id")
    tier = tier_of(spdx)
    stars = meta.get("stargazers_count", 0)
    print("  repo %-40s stars=%-5s spdx=%-12s tier=%s" % (full, stars, spdx, tier))
    manifest["repos"][full] = {"spdx": spdx, "tier": tier, "stars": stars,
                               "url": meta.get("html_url"), "pushed_at": meta.get("pushed_at")}
    if tier == "red":
        manifest["red_quarantine"].append(full)
        print("    -> red zone: idea-only, no code enters queue"); return 0
    tree = api("https://api.github.com/repos/%s/git/trees/%s?recursive=1" %
               (full, meta.get("default_branch", "HEAD")))
    if not tree: return 0
    files = [t for t in tree.get("tree", []) if t.get("type") == "blob"
             and t["path"].lower().endswith(ST_EXT) and t.get("size", 0) < 220000]
    files.sort(key=lambda x: x.get("size", 0))
    added = 0
    for f in files[:max_files]:
        txt = raw("https://raw.githubusercontent.com/%s/%s/%s" % (full, meta.get("default_branch", "HEAD"), f["path"]))
        if not txt: continue
        txt = unwrap_tc_xml(txt)
        for s in extract_signatures(txt, f["path"]):
            hits, h = dedup(s["name"], s["inputs"], names, norm, fp)
            if set(hits) & {"name-exact", "name-normalized"}:
                manifest["rejected"].append({"name": s["name"], "repo": full, "why": hits}); continue
            cand = {
                "name": s["name"], "suggest_category": guess_category(s["name"], txt), "kind": s["kind"],
                "tier": tier, "license": spdx, "source_url": "https://github.com/%s/blob/%s/%s" %
                (full, meta.get("default_branch", "HEAD"), f["path"]),
                "commit": meta.get("pushed_at"), "extraction_point": "%s (%s)" % (s["name"], s["rel"]),
                "signature": ", ".join(s["inputs"][:8]), "loc": s["loc"], "dialect": [],
                "defense_gaps": gaps_of(txt), "dedup": {"name": "pass", "fingerprint": "new", "semantic": "todo"},
                "priority": 1 if tier == "green" else 2, "fp": h,
                "harvested_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            }
            if "name-normalized" in hits: cand["dedup"]["name"] = "warn-close"
            queue_f.write(json.dumps(cand, ensure_ascii=False) + "\n"); added += 1
            fp[h] = cand["name"]
    print("    files=%d scanned, candidates added=%d" % (len(files[:max_files]), added))
    return added

def search_repos(queries, per_q=8):
    seen, out = set(), []
    for q in queries:
        url = ("https://api.github.com/search/repositories?q=%s&sort=stars&order=desc&per_page=%d"
               % (urllib.parse.quote(q), per_q))
        d = api(url)
        for it in (d or {}).get("items", []):
            full = it["full_name"]
            if full in seen: continue
            seen.add(full)
            out.append(full)
        time.sleep(2)
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--search", action="store_true")
    ap.add_argument("--repo", action="append", default=[])
    ap.add_argument("--max-repos", type=int, default=15)
    ap.add_argument("--max-files-per-repo", type=int, default=20)
    ap.add_argument("--max-files", type=int, default=30)
    ap.add_argument("--queries", default=("OSCAT|TcOpen|org:PLCnext-Community|"
                                          "\"IEC 61131-3\" in:name,description|"
                                          "codesys library in:name|twincat library in:name|"
                                          "plc library structured text in:description"))
    ap.add_argument("--stats", action="store_true")
    a = ap.parse_args()

    os.makedirs(STG, exist_ok=True)
    if a.stats:
        if not os.path.exists(QUEUE): print("queue empty"); return
        rows = [json.loads(l) for l in io.open(QUEUE, encoding="utf-8") if l.strip()]
        import collections
        c = collections.Counter((r["tier"], r["suggest_category"]) for r in rows)
        print("queue depth:", len(rows))
        for k, v in c.most_common(): print("  %-8s %-12s %d" % (k[0], k[1], v))
        return

    names, norm = load_registry_names()
    fp = load_fingerprints()
    manifest = {"started": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
                "repos": {}, "rejected": [], "red_quarantine": []}
    repos = list(a.repo)
    if a.search:
        repos += search_repos(a.queries.split(","))
    repos = repos[:a.max_repos]
    print("repos to scan:", len(repos))
    total = 0
    with io.open(QUEUE, "a", encoding="utf-8") as qf:
        for full in repos:
            total += harvest_repo(full, a.max_files_per_repo, names, norm, fp, qf, manifest)
    save_fingerprints(fp)
    manifest["finished"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    manifest["added"] = total
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("TOTAL candidates added:", total, "->", QUEUE)
    print("rejected(name dup):", len(manifest["rejected"]), "| red quarantine:", manifest["red_quarantine"])

if __name__ == "__main__":
    import urllib.parse
    sys.exit(main())
