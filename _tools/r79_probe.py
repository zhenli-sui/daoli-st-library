# -*- coding: utf-8 -*-
"""r79_probe.py - codeload 整仓探测（零 REST 配额）

背景：本机 raw.githubusercontent.com 不可达(000)，contents API 每文件 1 core 配额(60/h)，
而 codeload.github.com/tar.gz 可用且不计 REST 配额 → 整仓下载 + 本地抽取是唯一可行的高产通道。

用法：python r79_probe.py owner/name[:branch] [更多...]
输出：每个仓的文件清单摘要 + 家族命中统计，tarball 留在 _tools/_tmp_r79/
"""
import io, os, re, sys, tarfile, subprocess, collections

WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_tmp_r79")
os.makedirs(WORK, exist_ok=True)

ST_EXT = (".st", ".scl", ".exp", ".iecst", ".tcpou", ".tcdut", ".tcgvl", ".tcprg", ".st.txt")

FAMILY = {
    "cal": r"(?i)\b(day_of_year|dayofyear|doy|weekday|day_of_week|isoweek|iso_week|week_number|leap|leapyear|month_end|day_in_month|days_in_month|easter)\b",
    "num": r"(?i)\b(isqrt|int_sqrt|sqrt_int|digitsum|digit_sum|divmod|div_mod|isprime|is_prime|gcd|lcm|factorial|pow_sat|ipow|sat_add|sat_mul)\b",
    "geo": r"(?i)\b(point_line|line_intersect|intersection|point_in_rect|inside_rect|centroid|polyline|distance_to_line|perpendicular|segment)\b",
    "stat": r"(?i)\b(welford|variance|stddev|skew|kurtosis|mad|trimmed|quantile|percentile|median|rank)\b",
    "cksum": r"(?i)\b(fletcher|crc_?8|crc_?16|crc_?32|xor_?8|bcc|lrc|checksum|parity|adler)\b",
}

LIC_PAT = [
    ("MIT", r"(?i)\bMIT License\b|permission is hereby granted, free of charge"),
    ("Apache-2.0", r"(?i)Apache License.{0,40}2\.0"),
    ("BSD-3-Clause", r"(?i)BSD 3-Clause|redistribution and use in source and binary forms"),
    ("GPL-3.0", r"(?i)GNU GENERAL PUBLIC LICENSE.{0,60}Version 3"),
    ("GPL-2.0", r"(?i)GNU GENERAL PUBLIC LICENSE.{0,60}Version 2"),
    ("LGPL-3.0", r"(?i)GNU LESSER GENERAL PUBLIC LICENSE"),
    ("EPL-2.0", r"(?i)Eclipse Public License.{0,20}2\.0"),
    ("EPL-1.0", r"(?i)Eclipse Public License.{0,20}1\.0"),
    ("MPL-2.0", r"(?i)Mozilla Public License.{0,20}2\.0"),
]


def download(full, branch):
    slug = full.replace("/", "__")
    tgz = os.path.join(WORK, slug + ".tar.gz")
    if os.path.exists(tgz) and os.path.getsize(tgz) > 1000:
        return tgz
    url = "https://codeload.github.com/%s/tar.gz/refs/heads/%s" % (full, branch)
    r = subprocess.run(["curl", "-s", "-L", "-o", tgz, "-w", "%{http_code}",
                        "--max-time", "180", url], capture_output=True, text=True)
    code = (r.stdout or "").strip()[-3:]
    if code != "200" or os.path.getsize(tgz) < 1000:
        return None
    return tgz


def probe(full, branch):
    tgz = download(full, branch)
    if not tgz:
        print("  %-45s DOWNLOAD FAIL" % full); return None
    out = {"repo": full, "branch": branch, "files": [], "license": None, "verdict": ""}
    lic_txt = ""
    with tarfile.open(tgz, "r:gz") as t:
        members = [m for m in t.getmembers() if m.isfile()]
        for m in members:
            low = m.name.lower()
            base = low.rsplit("/", 1)[-1]
            if base in ("license", "license.md", "license.txt", "copying", "licence") and m.size < 60000:
                f = t.extractfile(m)
                if f: lic_txt += f.read().decode("utf-8", "replace")
            if low.endswith(ST_EXT) and m.size < 250000:
                out["files"].append((m.name, m.size))
    for name, pat in LIC_PAT:
        if re.search(pat, lic_txt):
            out["license"] = name; break
    if not out["license"]:
        out["license"] = "NOASSERTION" if lic_txt else "NONE"
    fam = collections.Counter()
    with tarfile.open(tgz, "r:gz") as t:
        for path, _sz in out["files"]:
            f = t.extractfile(path)
            if not f: continue
            txt = f.read().decode("utf-8", "replace")
            for k, pat in FAMILY.items():
                if re.search(pat, txt): fam[k] += 1
    print("  %-45s lic=%-12s st_files=%-4d fam=%s" %
          (full, out["license"], len(out["files"]), dict(fam)))
    out["fam"] = dict(fam)
    return out


if __name__ == "__main__":
    for a in sys.argv[1:]:
        full, _, br = a.partition(":")
        probe(full, br or "main")
