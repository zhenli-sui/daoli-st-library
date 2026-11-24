# -*- coding: utf-8 -*-
"""R83 采集器：codeload 整仓 tar.gz（raw.githubusercontent 本机 000 不可达）
只读：api.github.com 元数据 + codeload 归档。红区零拉取。
"""
import json, os, re, sys, tarfile, urllib.request, urllib.error, io, datetime

TOK = open(r"C:\Library\_tools\.gh_token").read().strip()
UA = {"User-Agent": "daoli-oss-hunter/1.0", "Authorization": "Bearer " + TOK}
OUT = r"C:\Library\_Staging_Raw\2026-11-24\r83"
os.makedirs(OUT, exist_ok=True)

ST_EXT = (".st", ".scl", ".exp", ".iecst", ".tcpou", ".tcdut", ".tcpro", ".tcprg")
GREEN = {"MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "MPL-2.0", "ISC", "Unlicense", "0BSD"}
RED = {"GPL-2.0", "GPL-3.0", "AGPL-3.0", "LGPL-2.1", "LGPL-3.0", "GPL-2.0-only",
       "GPL-3.0-only", "GPL-2.0-or-later", "GPL-3.0-or-later", "LGPL-2.1-only", "LGPL-3.0-only"}

def gh(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        print("   HTTP", e.code, url[:80]); return None
    except Exception as e:
        print("   ERR", str(e)[:60]); return None

def codeload(repo, branch):
    url = "https://codeload.github.com/%s/tar.gz/refs/heads/%s" % (repo, branch)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA["User-Agent"]})
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
        print("   tar %s/%s %.1f MB" % (repo, branch, len(data) / 1e6))
        return data
    except urllib.error.HTTPError as e:
        print("   tar HTTP", e.code, repo, branch); return None
    except Exception as e:
        print("   tar ERR", str(e)[:60]); return None

def unwrap_tc_xml(txt):
    txt = txt.lstrip("\ufeff")          # TcPOU/TcDUT 常带 BOM，不清会误判为非 XML
    if not txt.lstrip().startswith("<"): return txt
    parts = []
    for m in re.finditer(r"<(Declaration|ST)>(.*?)</\1>", txt, re.S):
        b = m.group(2).replace("<![CDATA[", "").replace("]]>", "")
        for a, c in (("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&quot;", '"'), ("&apos;", "'")):
            b = b.replace(a, c)
        parts.append(b)
    return "\n".join(parts) if parts else txt

SIG = re.compile(r"^[ \t]*(FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE)[ \t]+"
                 r"(?:(?:PUBLIC|PRIVATE|PROTECTED|INTERNAL|FINAL|ABSTRACT)[ \t]+)?([A-Za-z_]\w*)",
                 re.I | re.M)

def parse_block(text, start):
    seg = text[start:start + 6000]
    m = re.search(r"VAR_INPUT(.*?)END_VAR", seg, re.I | re.S)
    inp = []
    if m:
        for line in m.group(1).split("\n"):
            mm = re.match(r"\s*([A-Za-z_]\w*)\s*(?:AT\s+%\S+\s*)?:\s*([A-Za-z_][\w.\[\]\.]*)", line)
            if mm: inp.append("%s:%s" % (mm.group(1), mm.group(2)))
    mo = re.search(r"VAR_OUTPUT(.*?)END_VAR", seg, re.I | re.S)
    out = []
    if mo:
        for line in mo.group(1).split("\n"):
            mm = re.match(r"\s*([A-Za-z_]\w*)\s*(?:AT\s+%\S+\s*)?:\s*([A-Za-z_][\w.\[\]\.]*)", line)
            if mm: out.append("%s:%s" % (mm.group(1), mm.group(2)))
    return inp, out

def main(repos):
    for repo in repos:
        safe = repo.replace("/", "__")
        dest = os.path.join(OUT, safe + ".json")
        if os.path.exists(dest):
            print("== cached", repo); continue
        print("==", repo)
        meta = gh("https://api.github.com/repos/" + repo)
        if not meta:
            json.dump({"repo": repo, "error": "meta-fail"}, open(dest, "w", encoding="utf-8"))
            continue
        spdx = (meta.get("license") or {}).get("spdx_id")
        branch = meta.get("default_branch", "main")
        rec = {"repo": repo, "spdx": spdx, "stars": meta.get("stargazers_count", 0),
               "pushed_at": meta.get("pushed_at"), "branch": branch,
               "desc": (meta.get("description") or "")[:200], "files": []}
        if spdx in RED:
            rec["red"] = True
            print("   RED zone -> idea only, no download")
            json.dump(rec, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            continue
        data = codeload(repo, branch)
        if data is None:
            rec["error"] = "tar-fail"
            json.dump(rec, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            continue
        try:
            tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")
        except Exception as e:
            rec["error"] = "tar-open:" + str(e)[:40]
            json.dump(rec, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            continue
        lic_txt = ""
        st_files = []
        for m in tf.getmembers():
            if not m.isfile(): continue
            n = m.name.split("/", 1)[-1]
            base = os.path.basename(n).lower()
            if base in ("license", "license.md", "license.txt", "copying", "licence"):
                try: lic_txt += tf.extractfile(m).read().decode("utf-8", "replace")[:3000]
                except Exception: pass
            if n.lower().endswith(ST_EXT) and m.size < 400000:
                st_files.append(m)
        rec["license_head"] = lic_txt[:600]
        rec["st_count"] = len(st_files)
        print("   spdx=%s st_files=%d" % (spdx, len(st_files)))
        for m in st_files[:80]:
            n = m.name.split("/", 1)[-1]
            try:
                txt = tf.extractfile(m).read().decode("utf-8", "replace")
            except Exception:
                continue
            txt = unwrap_tc_xml(txt)
            for sm in SIG.finditer(txt):
                k, nm = sm.group(1).upper(), sm.group(2)
                if nm.upper() in ("TYPE", "STRUCT", "END_TYPE", "VAR", "METHOD", "PROPERTY"):
                    continue
                inp, out = parse_block(txt, sm.start())
                rec["files"].append({
                    "kind": "FB" if k == "FUNCTION_BLOCK" else ("FC" if k == "FUNCTION" else ("PRG" if k == "PROGRAM" else k[:4])),
                    "name": nm, "path": n, "inputs": inp, "outputs": out,
                    "loc": txt.count("\n") + 1,
                    "dialect": [d for d in ("__SYSTEM", "SysFile", "TC_", "System.", "AXIS_REF", "SM3_")
                                if d in txt],
                    "ext": n.rsplit(".", 1)[-1].lower(),
                    "body": txt[sm.start():sm.start() + 2600],
                })
        json.dump(rec, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("   blocks=%d" % len(rec["files"]))
    print("done")

if __name__ == "__main__":
    main(sys.argv[1:])
