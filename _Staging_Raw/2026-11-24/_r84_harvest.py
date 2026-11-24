# -*- coding: utf-8 -*-
"""R84 真采集：codeload 整仓 tar.gz → 本地抽取签名 → 五族语义分档 → 构建候选（写 build 文件，不直连队列）"""
import base64, hashlib, io, json, os, re, tarfile, urllib.request, collections

TK = open(r"C:\Library\_tools\.gh_token", encoding="utf-8").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TK}
LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-24")
ST_EXT = (".st", ".scl", ".exp", ".iecst", ".tcpou", ".tcdut", ".tcpro", ".tcprg", ".xml")

REPOS = [
    ("mutito/PV-RTPP", "MIT", "A"),
    ("joyautomation/nautilus", "Apache-2.0", "DE"),
    ("Beckhoff-USA-Community/PackML_PLC_Example", "MIT", "CE"),
    ("Inxton/tcopen-app-templates", "MIT", "C"),
    ("Gorke07/OpenDVP", "MIT", "E"),
    ("Beckhoff-USA-Community/XPlanarApplicationLibrary", "MIT", "C"),
]

FAM_KW = {
    "A": ["pv", "photovolta", "solar", "mppt", "irradiance", "rtpp", "inverter", "string", "module temp", "yield"],
    "B": ["coat", "tension", "dancer", "web", "slit", "calender", "electrode", "areal", "basis weight", "unwrap", "rewind"],
    "C": ["cnc", "tool", "spindle", "chuck", "pallet", "load", "unload", "clamp", "fixture", "dimens", "spc", "probe"],
    "D": ["reactor", "batch", "jacket", "exotherm", "reflux", "dosing", "recipe", "charge", "agitat", "cool", "ramp"],
    "E": ["tablet", "granul", "coating", "blend", "capsule", "blister", "pharma", "feed", "weigh", "dosage", "batch"],
}

SIG = re.compile(r"^\s*(FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE|CLASS)\s+(?:[\w\.]+\s+)?([A-Za-z_]\w*)", re.I | re.M)
VARBLK = re.compile(r"VAR(_INPUT|_OUTPUT|_IN_OUT)?\b(.*?)END_VAR", re.I | re.S)
BAD_NAME = {"VAR_INPUT", "VAR_OUTPUT", "VAR", "END_VAR", "METHOD", "EXTENDS", "IMPLEMENTS", "PROPERTY",
            "VAR_IN_OUT", "VAR_GLOBAL", "VAR_TEMP", "VAR_STAT", "TYPE", "INTERFACE", "ST", "ACTION"}


def unwrap_tc_xml(txt):
    if not txt.lstrip().startswith("<"):
        return txt
    parts = []
    for m in re.finditer(r"<(Declaration|ST|Implementation)>(.*?)</\1>", txt, re.S):
        b = m.group(2).replace("<![CDATA[", "").replace("]]>", "")
        for a, c in (("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&quot;", '"'), ("&apos;", "'")):
            b = b.replace(a, c)
        parts.append(b)
    return "\n".join(parts) if parts else txt


def vars_of(text, which):
    out = []
    for m in VARBLK.finditer(text):
        kind = (m.group(1) or "").upper()
        if which == "IN" and kind not in ("_INPUT", "_IN_OUT", ""):
            continue
        if which == "OUT" and kind not in ("_OUTPUT", "_IN_OUT"):
            continue
        for line in m.group(2).split("\n"):
            mm = re.match(r"\s*([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w\.\[\]\.]*)\s*(?::=.*)?[;:]", line)
            if mm:
                out.append("%s:%s" % (mm.group(1), mm.group(2)))
    return out


DEFECT_HINTS = [
    (r"/\s*[A-Za-z_]\w*\s*(?:;|,|\))", "存在裸除法，需检查除子闸"),
    (r"\bREAL_TO_INT\b|\bTRUNC\b|\bLREAL_TO_INT\b", "存在浮点转整，需检查越界钳位"),
    (r"\bWHILE\b", "存在 WHILE，需检查守卫计数"),
    (r"\bSTRING\b", "涉及字符串，需检查 255 长度上限"),
    (r"%[IQM]", "含物理地址直接寻址，移植时需抽象"),
    (r"__SYSTEM|SysFile|TC_|System\.|Tc2_|PlcApp", "含平台方言依赖，clean-room 时需剥离"),
    (r"\bTO_UDINT\b|\bUDINT_TO\b", "存在 32 位无符号转换，需检查负值截断"),
]


def gaps_of(text):
    g = [msg for pat, msg in DEFECT_HINTS if re.search(pat, text)]
    if re.search(r"\bCASE\b", text, re.I) and not re.search(r"(?-i:\bELSE\b)", text):
        g.append("CASE 无 ELSE 兜底（非法相号无默认分支）")
    return g[:5]


def dialect_of(text):
    d = set()
    for pat, tag in [(r"__SYSTEM", "__SYSTEM"), (r"SysFile", "SysFile"), (r"\bTC_|Tc2_|Tc3_", "TC_"),
                     (r"\bSystem\.", "System."), (r"%[IQM]", "%I/%Q"), (r"\bAxSHARP|\baxsharp", "AX#")]:
        if re.search(pat, text):
            d.add(tag)
    return sorted(d)


def norm_base(name):
    b = name.lower()
    b = re.sub(r"^(fb_|fc_|i_|st_|e_|tc_|mc_|smc_|dl_|tco)", "", b)
    return b


def fingerprint(name, ins):
    base = norm_base(name)
    sig = ",".join(sorted(i.split(":")[1] for i in ins))
    return hashlib.sha1((base + "|" + sig if sig else base + "|" + base).encode()).hexdigest()[:16]


def load_known():
    reg = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
    reg_names = {c["name"].lower() for c in reg["components"]}
    reg_norm = {norm_base(n).replace("_", "") for n in reg_names}
    qpath = os.path.join(STG, "candidate_queue.jsonl")
    qnames, qfps = set(), {}
    for line in io.open(qpath, encoding="utf-8"):
        if not line.strip():
            continue
        r = json.loads(line)
        qnames.add(r["name"].lower())
        if r.get("fp"):
            qfps[r["fp"]] = r["name"]
    fps = json.load(open(os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json"), encoding="utf-8"))
    return reg_names, reg_norm, qnames, qfps, fps


def download(full):
    for ref in ("HEAD", "main", "master"):
        url = "https://codeload.github.com/%s/tar.gz/%s" % (full, ref)
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read()
            if raw[:2] == b"\x1f\x8b":
                return raw
        except Exception:
            continue
    return None


def main():
    reg_names, reg_norm, qnames, qfps, fps = load_known()
    print("registry=%d queue=%d fp=%d" % (len(reg_names), len(qnames), len(fps)))
    build, log = [], []
    for full, lic, fams in REPOS:
        blob = download(full)
        if not blob:
            print("DL-FAIL", full); log.append({"repo": full, "status": "dl-fail"}); continue
        tf = tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz")
        members = [m for m in tf.getmembers() if m.isfile() and m.name.lower().endswith(ST_EXT)]
        members.sort(key=lambda m: m.size)
        pick = members[:12]
        added, seen_in_repo = 0, set()
        print("%-48s files=%d pick=%d" % (full, len(members), len(pick)))
        for m in pick:
            try:
                txt = tf.extractfile(m).read().decode("utf-8", "replace")
            except Exception:
                continue
            txt = unwrap_tc_xml(txt)
            rel = m.name.split("/", 1)[1] if "/" in m.name else m.name
            low = txt.lower()
            for s in SIG.finditer(txt):
                kind, name = s.group(1).upper(), s.group(2)
                if name.upper() in BAD_NAME or len(name) < 3:
                    continue
                if name in seen_in_repo:
                    continue
                seg = txt[s.start(): s.start() + 6000]
                ins, outs = vars_of(seg, "IN"), vars_of(seg, "OUT")
                # 语义相关度（对块名 + 段文本）
                scope = (name + " " + seg[:2500]).lower()
                hit = {f: sum(1 for k in FAM_KW[f] if k in scope) for f in "ABCDE"}
                best = max(hit, key=lambda f: hit[f])
                score = hit[best]
                # 去重
                nb = norm_base(name)
                why = []
                if name.lower() in reg_names: why.append("registry-exact")
                if nb.replace("_", "") in reg_norm: why.append("registry-normalized")
                if name.lower() in qnames: why.append("queue-exact")
                fpv = fingerprint(name, ins)
                if fpv in fps or fpv in qfps: why.append("fingerprint")
                if why:
                    log.append({"repo": full, "name": name, "skip": why}); continue
                if score == 0:
                    log.append({"repo": full, "name": name, "skip": ["semantic-0"]}); continue
                seen_in_repo.add(name)
                build.append({
                    "name": name,
                    "suggest_category": {"A": "DL_Process", "B": "DL_Process", "C": "DL_Motion",
                                         "D": "DL_Process", "E": "DL_Process"}[best],
                    "kind": "FB" if kind == "FUNCTION_BLOCK" else ("FC" if kind == "FUNCTION" else kind[:4]),
                    "tier": "green", "license": lic,
                    "source_url": "https://github.com/%s/blob/HEAD/%s" % (full, rel),
                    "commit": "HEAD",
                    "extraction_point": "%s (%s)" % (name, rel),
                    "signature": "VAR_INPUT: " + ", ".join(ins[:10]) + (" || VAR_OUTPUT: " + ", ".join(outs[:6]) if outs else ""),
                    "loc": txt.count("\n") + 1,
                    "dialect": dialect_of(seg),
                    "defense_gaps": gaps_of(seg) or ["未见明显防御缺口，需人工判定增量价值"],
                    "dedup": {"name": "pass", "fingerprint": "new", "semantic": "new"},
                    "priority": 1,
                    "family": best, "family_score": score,
                    "fp": fpv,
                    "note": "绿区 %s，可直接改写并保留版权声明；族%s 相关度 %d" % (lic, best, score),
                })
                added += 1
        print("   -> candidates:", added)
        log.append({"repo": full, "status": "ok", "files": len(members), "picked": len(pick), "cand": added})
    json.dump({"build": build, "log": log}, open(os.path.join(STG, "_r84_build.json"), "w",
                                                 encoding="utf-8"), ensure_ascii=False, indent=1)
    print("BUILD total:", len(build), collections.Counter(b["family"] for b in build))


if __name__ == "__main__":
    main()
