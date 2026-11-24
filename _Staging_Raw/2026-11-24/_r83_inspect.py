# -*- coding: utf-8 -*-
"""检查零块仓：为何解析不出签名"""
import json, io, os, tarfile, urllib.request, sys

UA = {"User-Agent": "daoli-oss-hunter/1.0"}
ST_EXT = (".st", ".scl", ".exp", ".iecst", ".tcpou", ".tcdut", ".tcpro", ".tcprg")

def show(repo, branch, limit=2):
    url = "https://codeload.github.com/%s/tar.gz/refs/heads/%s" % (repo, branch)
    data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()
    tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")
    n = 0
    for m in tf.getmembers():
        if not m.isfile(): continue
        p = m.name.split("/", 1)[-1]
        if p.lower().endswith(ST_EXT) and m.size < 400000:
            txt = tf.extractfile(m).read().decode("utf-8", "replace")
            print("--- %s :: %s (%d B)" % (repo, p, m.size))
            print(txt[:700].replace("\r", ""))
            n += 1
            if n >= limit: break

for repo, br in [("huuhuannt1998/CPSForge", "main"),
                 ("pcdshub/lcls-twincat-vacuum-sim", "master"),
                 ("Open-Industry-Project/Open-Industry-Project", "main")]:
    try: show(repo, br)
    except Exception as e: print("ERR", repo, e)
    print("=" * 60)
