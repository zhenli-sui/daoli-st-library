# -*- coding: utf-8 -*-
"""R85 codeload 整仓抽取 + 签名抽取 + 工艺词命中诚实计数"""
import json, sys, io, os, re, tarfile, urllib.request
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
OUT = r'C:\Library\_Staging_Raw\2026-11-24\r85'
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "daoli-oss-hunter/1.0"}
REPOS = [("ZzzJjt/Industrial-Control", "none"),
         ("Eguono22/PLC-Extruder-project", "none"),
         ("FREEZONEX/ia2", "Apache-2.0"),
         ("lusipad/plcopen", "Apache-2.0")]
EXT = ('.st', '.scl', '.exp', '.iecst', '.tcgvl', '.tcpou', '.tcdut')
res = []
for full, lic in REPOS:
    tgz = os.path.join(OUT, full.replace('/', '_') + '.tar.gz')
    ok = False
    for br in ('main', 'master'):
        try:
            u = 'https://codeload.github.com/%s/tar.gz/refs/heads/%s' % (full, br)
            r = urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=90)
            data = r.read()
            open(tgz, 'wb').write(data)
            ok = True
            break
        except Exception as e:
            err = str(e)[:90]
    if not ok:
        print('DL_FAIL', full, err); res.append({'repo': full, 'license': lic, 'dl': False, 'err': err}); continue
    files = []
    try:
        tf = tarfile.open(tgz)
        for m in tf.getmembers():
            if not m.isfile(): continue
            p = m.name.split('/', 1)[-1]
            if p.lower().endswith(EXT):
                try:
                    txt = tf.extractfile(m).read().decode('utf-8', 'replace')
                except Exception:
                    continue
                files.append({'path': p, 'text': txt, 'loc': txt.count('\n') + 1})
    except Exception as e:
        print('TAR_FAIL', full, e)
    print('%-40s %-12s dl=OK st_files=%d  bytes=%d' % (full, lic, len(files), os.path.getsize(tgz)))
    res.append({'repo': full, 'license': lic, 'dl': True, 'files': len(files),
                'detail': [{'path': f['path'], 'loc': f['loc']} for f in files]})
    json.dump([{'repo': f['repo'], 'path': f['path'], 'loc': f['loc'], 'text': f['text']}
               for f in files], open(os.path.join(OUT, full.replace('/', '_') + '_st.json'), 'w',
                                     encoding='utf-8'), ensure_ascii=False)
json.dump(res, open(os.path.join(OUT, '_dl.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('DONE')
