# -*- coding: utf-8 -*-
"""R82 OSS harvest: codeload tar.gz -> local extract -> signature sniff.
Read-only on the network (no push). Writes only under _Staging_Raw/2026-11-24/r82/.
"""
import os, re, sys, json, tarfile, subprocess, hashlib, io

BASE = r"C:\Library\_Staging_Raw\2026-11-24\r82"
STEXT = ('.st', '.ST', '.scl', '.SCL', '.iecst', '.exp', '.TcPOU', '.TcDUT', '.tcgvl', '.TcGVL', '.TcIO')
LICFILE = ('license', 'licence', 'copying', 'license.md', 'license.txt', 'copying.txt')

# spdx keyword -> (spdx, class)
LIC_MAP = [
    ('gnu affero', 'AGPL-3.0', 'red'), ('agpl', 'AGPL-3.0', 'red'),
    ('gnu lesser general public', 'LGPL', 'red'), ('lgpl', 'LGPL', 'red'),
    ('gnu general public', 'GPL', 'red'), ('gpl-3', 'GPL-3.0', 'red'), ('gpl-2', 'GPL-2.0', 'red'),
    ('gpl', 'GPL', 'red'),
    ('mozilla public', 'MPL-2.0', 'green'), ('mpl-2.0', 'MPL-2.0', 'green'),
    ('apache license', 'Apache-2.0', 'green'), ('apache-2.0', 'Apache-2.0', 'green'),
    ('mit license', 'MIT', 'green'), ('permission is hereby granted, free of charge', 'MIT', 'green'),
    ('bsd 3', 'BSD-3-Clause', 'green'), ('bsd 2', 'BSD-2-Clause', 'green'),
    ('redistribution and use in source and binary forms', 'BSD', 'green'),
    ('isc', 'ISC', 'green'),
    ('eclipse public license', 'EPL', 'yellow'), ('epl', 'EPL', 'yellow'),
    ('oscat', 'OSCAT', 'yellow'), ('wtfpl', 'WTFPL', 'yellow'), ('cc0', 'CC0', 'yellow'),
    ('creative commons', 'CC', 'yellow'),
]

RE_BLOCK = re.compile(r'^\s*(FUNCTION_BLOCK|FUNCTION|INTERFACE|TYPE|PROGRAM|CLASS)\b\s+(?:ABSTRACT\s+|FINAL\s+|PUBLIC\s+|INTERNAL\s+)*([A-Za-z_][A-Za-z0-9_]*)', re.M | re.I)
RE_VAR = re.compile(r'^\s*(VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT)\b(.*?)^\s*END_VAR', re.M | re.S | re.I)
RE_VARLINE = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:AT\s+%[A-Za-z0-9.*]+)?\s*:\s*([A-Za-z_][A-Za-z0-9_.\[\]0-9]*)', re.M)


def sh(cmd, timeout=300):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def dl(owner_repo, branch=None):
    name = owner_repo.replace('/', '__')
    dest = os.path.join(BASE, name)
    os.makedirs(dest, exist_ok=True)
    tgz = os.path.join(dest, '_src.tgz')
    branches = [branch] if branch else ['main', 'master']
    for br in branches:
        url = 'https://codeload.github.com/%s/tar.gz/refs/heads/%s' % (owner_repo, br)
        r = subprocess.run(['curl', '-sL', '--max-time', '120', '-o', tgz, '-w', '%{http_code}',
                            url], capture_output=True, text=True)
        code = (r.stdout or '').strip()
        if code == '200' and os.path.getsize(tgz) > 1000:
            try:
                with tarfile.open(tgz, 'r:gz') as t:
                    t.extractall(dest)
            except Exception as e:
                return dest, 'extract_fail:%s' % e, os.path.getsize(tgz)
            return dest, 'ok:%s' % br, os.path.getsize(tgz)
    return dest, 'http_%s' % code, (os.path.getsize(tgz) if os.path.exists(tgz) else 0)


def lic_of(dest):
    cand = []
    for root, dirs, files in os.walk(dest):
        d = root[len(dest):].count(os.sep)
        if d > 2:
            continue
        for f in files:
            fl = f.lower()
            if fl.startswith(('license', 'licence', 'copying')) or fl in LICFILE:
                cand.append(os.path.join(root, f))
    if not cand:
        return 'unknown', 'unknown', None
    txt = ''
    for c in cand[:3]:
        try:
            txt += open(c, encoding='utf-8', errors='ignore').read(40000)
        except Exception:
            pass
    low = txt.lower()
    for kw, spdx, cls in LIC_MAP:
        if kw in low:
            return spdx, cls, os.path.basename(cand[0])
    return 'unknown', 'unknown', os.path.basename(cand[0])


def stfiles(dest):
    out = []
    for root, dirs, files in os.walk(dest):
        for f in files:
            if f.endswith(STEXT):
                out.append(os.path.join(root, f))
    return out


def sig_extract(path, rel):
    try:
        txt = open(path, encoding='utf-8', errors='ignore').read()
    except Exception:
        return []
    if len(txt) > 900000:
        return []
    res = []
    for m in RE_BLOCK.finditer(txt):
        kind, nm = m.group(1).upper(), m.group(2)
        if nm.upper() in ('OF', 'VAR', 'REFERENCE', 'INPUT', 'OUTPUT', 'METHOD', 'EXTENDS', 'IMPLEMENTS'):
            continue
        body = txt[m.start(): m.start() + 6000]
        vars_ = []
        for vm in RE_VAR.finditer(body):
            sec = vm.group(1).upper()
            for lm in RE_VARLINE.finditer(vm.group(2)):
                vars_.append((sec, lm.group(1), lm.group(2)))
        lines = txt.count('\n') + 1
        res.append({
            'name': nm, 'kind': kind, 'file': rel, 'loc': lines,
            'inputs': [(v[1], v[2]) for v in vars_ if v[0] == 'VAR_INPUT'],
            'outputs': [(v[1], v[2]) for v in vars_ if v[0] == 'VAR_OUTPUT'],
            'inouts': [(v[1], v[2]) for v in vars_ if v[0] == 'VAR_IN_OUT'],
            'raw_vars': vars_,
            'text_head': txt[:400],
        })
    return res


def scan(owner_repo, branch=None):
    dest, st, size = dl(owner_repo, branch)
    if not st.startswith('ok'):
        return {'repo': owner_repo, 'dl': st, 'bytes': size, 'license': None, 'files': 0, 'blocks': []}
    spdx, cls, lf = lic_of(dest)
    fs = stfiles(dest)
    blocks = []
    for f in fs:
        rel = os.path.relpath(f, dest)
        blocks.extend(sig_extract(f, rel))
    return {'repo': owner_repo, 'dl': st, 'bytes': size, 'license': spdx, 'lic_class': cls,
            'licfile': lf, 'files': len(fs), 'blocks': blocks,
            'stlist': [os.path.relpath(f, dest) for f in fs]}


if __name__ == '__main__':
    repos = sys.argv[1:]
    res = []
    for rp in repos:
        try:
            r = scan(rp)
        except Exception as e:
            r = {'repo': rp, 'dl': 'exc:%s' % e, 'files': 0, 'blocks': []}
        res.append(r)
        print('%-58s dl=%-12s lic=%-12s files=%-4s blocks=%s' % (
            rp, r.get('dl'), r.get('license'), r.get('files'), len(r.get('blocks', []))), flush=True)
    outp = os.path.join(BASE, '_scan_%s.json' % hashlib.sha1(
        '|'.join(repos).encode()).hexdigest()[:8])
    json.dump(res, open(outp, 'w', encoding='utf-8'), ensure_ascii=False)
    print('OUT', outp)
