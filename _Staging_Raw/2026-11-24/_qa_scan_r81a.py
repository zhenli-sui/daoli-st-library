# -*- coding: utf-8 -*-
import os, re, json
BASE = r"C:\Library"
files = open(r"C:\Library\_Staging_Raw\2026-11-24\_files_r81a.txt", encoding='utf-8').read().split()
res = {}
for f in files:
    p = os.path.join(BASE, f.replace('/', os.sep))
    L = open(p, encoding='utf-8', errors='replace').read().splitlines()
    src = "\n".join(L)
    mi = re.search(r'VAR_INPUT\s*\n(.*?)\n\s*END_VAR', src, re.S | re.I)
    mo = re.search(r'VAR_OUTPUT\s*\n(.*?)\n\s*END_VAR', src, re.S | re.I)
    mc = re.search(r'VAR\s+CONSTANT\s*\n(.*?)\n\s*END_VAR', src, re.S | re.I)
    mv = re.search(r'VAR\s*\n(.*?)\n\s*END_VAR', src, re.S | re.I)

    def decl(m):
        r = []
        if not m:
            return r
        for line in m.group(1).splitlines():
            s = line.split('//')[0].strip()
            if not s:
                continue
            mm = re.match(r'(\w+)\s*:\s*([\w\.]+)', s)
            if mm:
                r.append((mm.group(1), mm.group(2).upper()))
        return r

    IN, OUT, CON, VAR = decl(mi), decl(mo), decl(mc), decl(mv)
    idx = [m.end() for m in [mi, mo, mc, mv] if m]
    boff = max(idx) if idx else 0
    head_nl = src[:boff].count('\n')
    body = src[boff:]
    body_lines = [(head_nl + 1 + k, l) for k, l in enumerate(body.splitlines())]
    code = [(n, l.split('//')[0]) for n, l in body_lines]
    ctext = "\n".join(l for _, l in code)

    findings = []
    def add(item, sev, msg, line=None):
        findings.append(dict(item=item, sev=sev, msg=msg, line=line))

    tmap = {}
    for n, t in IN + OUT + CON + VAR:
        tmap[n] = t

    # item2 dead inputs
    for n, t in IN:
        if len(re.findall(r'\b' + re.escape(n) + r'\b', ctext)) == 0:
            add(2, 'MAJOR', 'DEAD INPUT %s declared but never used in body' % n)
    # item10 output never assigned
    for n, t in OUT:
        if len(re.findall(r'\b' + re.escape(n) + r'\s*:=', ctext)) == 0:
            add(10, 'MAJOR', 'OUTPUT %s never assigned' % n)
    # item6 unused const / var
    for n, t in CON:
        if len(re.findall(r'\b' + re.escape(n) + r'\b', ctext)) == 0:
            add(6, 'MINOR', 'UNUSED CONST %s' % n)
    for n, t in VAR:
        if len(re.findall(r'\b' + re.escape(n) + r'\b', ctext)) == 0:
            add(6, 'MINOR', 'UNUSED VAR %s' % n)
    # item5 output preset before first RETURN
    mret = re.search(r'\bRETURN\s*;', ctext)
    if mret:
        pre = ctext[:mret.start()]
        for n, t in OUT:
            if not re.search(r'\b' + re.escape(n) + r'\s*:=', pre):
                add(5, 'MAJOR', 'OUTPUT %s not preset before first RETURN' % n)
    # item3 guard & divide in same boolean expr
    for n, l in code:
        if re.search(r'(ABS\s*\([^)]*\)\s*<?=\s*[\w\.]+|<?=\s*DL_EPS)', l) and re.search(r'\)\s*OR\s*\(', l) and '/' in l:
            add(3, 'MAJOR', 'GUARD+DIY same-expr: ' + l.strip()[:110], n)
    # item8 REAL equality
    for n, l in code:
        for m in re.finditer(r'(\w+)\s*=\s*(\w+)', l):
            a, b = m.group(1), m.group(2)
            if a == b:
                continue
            if tmap.get(a) == 'REAL' or tmap.get(b) == 'REAL':
                add(8, 'MAJOR', 'REAL equality %s=%s' % (a, b), n)
    # item9 banned non-finite
    if re.search(r'ABS\s*\(\s*(\w+)\s*-\s*\1\s*\)', ctext):
        add(9, 'BLOCK', 'BANNED ABS(x-x) finiteness test')
    if re.search(r'\(\s*(\w+)\s*-\s*\1\s*\)\s*<>', ctext):
        add(9, 'BLOCK', 'BANNED (x-x)<>0 finiteness test')
    # item7 REAL->INT
    for n, l in code:
        if re.search(r'\b(REAL_TO_INT|TRUNC|REAL_TO_DINT|ROUND)\b', l, re.I):
            add(7, 'MINOR', 'REAL->INT cast: ' + l.strip()[:100], n)
    # item12 std func
    for n, l in code:
        if re.search(r'\bSQRT\s*\(', l, re.I):
            add(12, 'MINOR', 'SQRT check arg>=0: ' + l.strip()[:90], n)
        if re.search(r'\b(ATAN|SIN|COS|TAN)\s*\(', l, re.I):
            add(12, 'MINOR', 'trig check deg/rad+quadrant: ' + l.strip()[:90], n)
        if re.search(r'\bMOD\s*\(', l, re.I):
            add(12, 'MINOR', 'MOD negative semantics: ' + l.strip()[:90], n)
    # item10 bilingual comments
    miss = []
    for tag, m in [('IN', mi), ('OUT', mo), ('CON', mc), ('VAR', mv)]:
        if not m:
            continue
        for line in m.group(1).splitlines():
            s = line.strip()
            if not s or not re.match(r'\w+\s*:', s):
                continue
            if '//' not in line:
                miss.append((tag, s[:50]))
            else:
                c = line.split('//', 1)[1]
                if not re.search(r'[\u4e00-\u9fff]', c) or not re.search(r'[A-Za-z]{3}', c):
                    miss.append((tag, s[:50]))
    if miss:
        add(10, 'MINOR', 'BILINGUAL comment gaps %d: %s' % (len(miss), str(miss[:4])))
    # item11 semicolon placement
    for n, l in body_lines:
        s = l.strip()
        if s.startswith('//') or '//' not in s:
            continue
        cp = s.split('//')[0].rstrip()
        if cp and not cp.endswith(';') and re.match(r'^\w+\s*:=', cp):
            add(11, 'BLOCK', 'stmt missing ; before comment: ' + s[:100], n)
    # item4 clamp direction evidence
    for n, l in code:
        m = re.search(r'IF\s+(\w+)\s*<\s*(DL_\w+)\s+THEN', l)
        if m:
            add(4, 'INFO', 'clamp-LO branch %s<%s' % (m.group(1), m.group(2)), n)
        m = re.search(r'ELSIF\s+(\w+)\s*>\s*(DL_\w+)', l)
        if m:
            add(4, 'INFO', 'clamp-HI branch %s>%s' % (m.group(1), m.group(2)), n)

    cvals = {}
    if mc:
        for line in mc.group(1).splitlines():
            mm = re.match(r'\s*(\w+)\s*:\s*(\w+)\s*:=\s*([-\d\.eE+]+)', line)
            if mm:
                try:
                    cvals[mm.group(1)] = float(mm.group(3))
                except Exception:
                    pass
    res[f] = dict(findings=findings, IN=IN, OUT=OUT, CON=CON, VAR=VAR,
                  cvals=cvals, nlines=len(L), head_nl=head_nl)

json.dump(res, open('/tmp/scan.json', 'w'), ensure_ascii=False, indent=1)
tot = {'BLOCK': 0, 'MAJOR': 0, 'MINOR': 0}
for f, d in res.items():
    nd = [x for x in d['findings'] if x['sev'] in ('BLOCK', 'MAJOR', 'MINOR')]
    if nd:
        print("\n### " + f)
        for x in nd:
            tot[x['sev']] += 1
            print("  [%s] i%d L%s: %s" % (x['sev'], x['item'], x['line'], x['msg']))
print("\nTOTALS %s" % tot)
print("INFO counts per file (clamp evidence) skipped verbose")
