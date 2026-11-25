# -*- coding: utf-8 -*-
"""r79_extract.py - 从 codeload tarball 本地抽取签名 + 家族归类 + 三道去重

用法:
  python r79_extract.py --list  owner/name:branch [pat]        # 只列文件
  python r79_extract.py --emit  owner/name:branch --tier yellow --license "..."  # 抽候选到 _tools/_tmp_r79/out/*.json
"""
import argparse, hashlib, io, json, os, re, sys, tarfile, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "_tmp_r79")
OUT = os.path.join(WORK, "out"); os.makedirs(OUT, exist_ok=True)
LIB = r"C:\Library"
ST_EXT = (".st", ".scl", ".exp", ".iecst", ".tcpou", ".tcdut", ".tcgvl", ".tcprg", ".st.txt")

FAMILY = {
    "cal": r"(?i)\b(day_of_year|dayofyear|doy|weekday|day_of_week|isoweek|iso_week|week_number|leap|leapyear|month_end|day_in_month|days_in_month|easter)\b",
    "num": r"(?i)\b(isqrt|int_sqrt|sqrt_int|digitsum|digit_sum|divmod|div_mod|isprime|is_prime|gcd|lcm|factorial|pow_sat|ipow|sat_add|sat_mul)\b",
    "geo": r"(?i)\b(point_line|line_intersect|intersection|point_in_rect|inside_rect|centroid|polyline|distance_to_line|perpendicular)\b",
    "stat": r"(?i)\b(welford|variance|stddev|skew|kurtosis|\bmad\b|trimmed|quantile|percentile|median|rank)\b",
    "cksum": r"(?i)\b(fletcher|crc_?8|crc_?16|crc_?32|xor_?8|\bbcc\b|\blrc\b|checksum|adler)\b",
}
FAM_DESC = {"cal": "日历/日期算术", "num": "整数数论/位宽安全", "geo": "二维平面几何",
            "stat": "统计扩展", "cksum": "校验和"}

SIG = re.compile(r"^[ \t]*(FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE)[ \t]+(?:[\w.]+[ \t]+)?([A-Za-z_]\w*)",
                 re.I | re.M)
KW = {"METHOD", "PROPERTY", "ACTION", "EXTENDS", "IMPLEMENTS", "VAR", "VAR_INPUT", "VAR_OUTPUT",
      "VAR_IN_OUT", "VAR_GLOBAL", "VAR_TEMP", "END_VAR", "IF", "THEN", "ELSE", "CASE", "FOR",
      "WHILE", "REPEAT", "RETURN", "STRUCT", "END_STRUCT", "CONSTANT", "RETAIN", "PERSISTENT"}

FAKE_NAMES = re.compile(r"(?i)^(__SYSTEM|SysFile|TC_|System)")


def unwrap_xml(txt):
    if not txt.lstrip().startswith("<"): return txt
    parts = []
    for m in re.finditer(r"<(Declaration|ST)>(.*?)</\1>", txt, re.S):
        b = m.group(2).replace("<![CDATA[", "").replace("]]>", "")
        for a, c in (("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&quot;", '"'), ("&apos;", "'")):
            b = b.replace(a, c)
        parts.append(b)
    return "\n".join(parts) if parts else txt


def load_registry():
    d = json.load(io.open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
    names, norm = set(), set()
    for c in d["components"]:
        n = c["name"].lower(); names.add(n)
        m = re.sub(r"^(fb_|fc_|i_|st_|e_|dl_)", "", n)
        m = re.sub(r"^(dl_)", "", m)
        norm.add(m.replace("_", ""))
    return names, norm


def load_fp():
    p = os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json")
    return json.load(io.open(p, encoding="utf-8")) if os.path.exists(p) else {}


DEFECT = [
    (r"/\s*[A-Za-z_]\w*\s*(?:;|,)", "存在裸除法，需检查除子闸"),
    (r"\bREAL_TO_INT\b|\bTRUNC\b|\bDINT_TO_INT\b", "存在窄化转换，需检查越界钳位"),
    (r"\bWHILE\b|\bREPEAT\b", "存在不定次循环，需检查守卫计数"),
    (r"\bSTRING\b", "涉及字符串，需检查 255 长度上限"),
    (r"%[IQM]", "含物理地址直接寻址，移植时需抽象"),
    (r"__SYSTEM|SysFile|\bTC_|System\.", "含平台方言依赖，clean-room 时需剥离"),
    (r"(?i)SHL|SHR|ROL|ROR", "含位移，需检查移位量越界（>=位宽 UB）"),
    (r"(?i)\bABS\b|\bSQRT\b", "含绝对值/开方，需检查负数与溢出"),
]


def gaps_of(txt):
    g = []
    for pat, msg in DEFECT:
        if re.search(pat, txt): g.append(msg)
    if re.search(r"\bCASE\b", txt, re.I) and not re.search(r"(?-i:\bELSE\b)", txt):
        g.append("CASE 无 ELSE 兜底")
    return g[:4] or ["未见明显防御缺口，需人工判定增量价值"]


def norm_base(name):
    low = name.lower()
    b = re.sub(r"^(fb_|fc_|i_|st_|e_|tc_|mc_|smc_|dl_|oscat_)", "", low)
    return b


def fingerprints_of(name, inputs, fp, norm_names, names):
    base = norm_base(name)
    hits = []
    if name.lower() in names: hits.append("name-exact")
    if base.replace("_", "") in norm_names: hits.append("name-normalized")
    types = ",".join(sorted(i.split(":")[1] for i in inputs))
    h = hashlib.sha1((base + "|" + types).encode()).hexdigest()[:16]
    if h in fp: hits.append("fingerprint:" + str(fp[h]))
    return hits, h


def open_tar(full, branch):
    slug = full.replace("/", "__")
    tgz = os.path.join(WORK, slug + ".tar.gz")
    if not os.path.exists(tgz):
        print("  missing tarball, run r79_probe.py first:", tgz); return None
    return tarfile.open(tgz, "r:gz")


def iter_st(t):
    for m in t.getmembers():
        if m.isfile() and m.name.lower().endswith(ST_EXT) and m.size < 250000:
            yield m


def do_list(full, branch, pat):
    t = open_tar(full, branch)
    if not t: return
    n = 0
    with t:
        for m in iter_st(t):
            if pat and not re.search(pat, m.name, re.I): continue
            n += 1
            print("%8d  %s" % (m.size, m.name))
    print("-- %d files" % n)


def do_emit(full, branch, tier, license_, fams, maxper, commit):
    names, norm_names = load_registry()
    fp = load_fp()
    t = open_tar(full, branch)
    if not t: return 0
    recs = []
    seen_names = set()
    with t:
        for m in iter_st(t):
            f = t.extractfile(m)
            if not f: continue
            txt = unwrap_xml(f.read().decode("utf-8", "replace"))
            fam_hit = [k for k, p in FAMILY.items() if k in fams and re.search(p, txt)]
            if not fam_hit: continue
            for s in SIG.finditer(txt):
                kind, name = s.group(1).upper(), s.group(2)
                if name.upper() in KW or len(name) < 3: continue
                if FAKE_NAMES.match(name): continue
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name): continue
                seg = txt[s.start(): s.start() + 3000]
                inputs = []
                vi = re.search(r"VAR_INPUT(.*?)END_VAR", seg, re.I | re.S)
                if vi:
                    for line in vi.group(1).split("\n"):
                        mm = re.match(r"\s*([A-Za-z_]\w*)\s*(?:,\s*\w+\s*)*:\s*([A-Za-z_][\w.\[\]\.]*)", line)
                        if mm: inputs.append("%s:%s" % (mm.group(1), mm.group(2)))
                hits, h = fingerprints_of(name, inputs, fp, norm_names, names)
                key = (name.lower(), h)
                if key in seen_names: continue
                seen_names.add(key)
                rec = {
                    "name": name, "family": fam_hit[0], "families": fam_hit,
                    "kind": "FB" if kind == "FUNCTION_BLOCK" else ("FC" if kind == "FUNCTION" else kind[:4]),
                    "tier": tier, "license": license_,
                    "source_url": "https://github.com/%s/blob/%s/%s" % (full, branch, m.name),
                    "commit": commit, "extraction_point": "%s @ %s" % (name, m.name.split("/", 1)[-1]),
                    "signature": ", ".join(inputs[:8]), "loc": txt.count("\n") + 1,
                    "dialect": [], "defense_gaps": gaps_of(txt),
                    "dedup": {"name": "pass" if not hits else "hit", "fingerprint": "new" if h not in fp else "hit",
                              "semantic": "todo", "hits": hits},
                    "priority": 1 if tier == "green" else 2, "fp": h,
                }
                recs.append(rec)
    # 每个家族取前 maxper 条，按去重干净度 + 有输入参数优先
    picked = []
    cnt = {}
    recs.sort(key=lambda r: (r["dedup"]["name"] != "pass", r["dedup"]["fingerprint"] != "new",
                             -len(r["signature"]), r["loc"]))
    for r in recs:
        k = r["family"]
        if cnt.get(k, 0) >= maxper: continue
        cnt[k] = cnt.get(k, 0) + 1
        picked.append(r)
    slug = full.replace("/", "__")
    json.dump(picked, io.open(os.path.join(OUT, slug + ".json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("  %-45s emit %d (raw %d) %s -> %s.json" % (full, len(picked), len(recs), cnt, slug))
    for r in picked:
        print("     [%s] %-28s %-4s in=%d hi=%s" % (r["family"], r["name"], r["kind"],
                                                    len(r["signature"].split(",")) if r["signature"] else 0,
                                                    ",".join(r["dedup"]["hits"]) or "-"))
    return len(picked)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", nargs=2, metavar=("REPO:BR", "PAT"))
    ap.add_argument("--emit", metavar="REPO:BR")
    ap.add_argument("--tier", default="green")
    ap.add_argument("--license", dest="lic", default="MIT")
    ap.add_argument("--fams", default="cal,num,geo,stat,cksum")
    ap.add_argument("--maxper", type=int, default=4)
    ap.add_argument("--commit", default="")
    a = ap.parse_args()
    if a.list:
        full, _, br = a.list[0].partition(":")
        do_list(full, br or "main", a.list[1] if len(a.list) > 1 else None)
    elif a.emit:
        full, _, br = a.emit.partition(":")
        do_emit(full, br or "main", a.tier, a.lic, a.fams.split(","), a.maxper, a.commit)
