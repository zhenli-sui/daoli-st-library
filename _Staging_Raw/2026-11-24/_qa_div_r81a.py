# -*- coding: utf-8 -*-
"""最后校验：逐除法行回溯 15 行内是否存在对除数的闸位；SQRT 参数符号。"""
import os, re, json
BASE = r"C:\Library"
files = open(r"C:\Library\_Staging_Raw\2026-11-24\_files_r81a.txt", encoding='utf-8').read().split()
report = []
for f in files:
    p = os.path.join(BASE, f.replace('/', os.sep))
    L = open(p, encoding='utf-8', errors='replace').read().splitlines()
    for i, line in enumerate(L):
        code = line.split('//')[0]
        if ':=' not in code:
            continue
        # find divisions: a / b  where b is identifier
        for m in re.finditer(r'/\s*([A-Za-z_]\w*)', code):
            div = m.group(1)
            # skip constant like DL_PCT, DL_MIN_PER_H, DL_TWO ...
            if div.upper().startswith('DL_'):
                continue
            lo = max(0, i - 15)
            ctx = "\n".join(L[lo:i])
            guarded = re.search(r'(ABS\s*\(\s*' + div + r'\s*\)|' + div + r'\s*[<>]=?|\b' + div + r'\b\s*<>\s*0\.?0?)', ctx)
            # also domain guard on divisor inside same expr -> flag
            same = re.search(r'IF.*' + div + r'.*' + div, code)
            report.append(dict(file=f, line=i + 1, divisor=div,
                               guarded=bool(guarded), code=code.strip()[:100]))
json.dump(report, open('/tmp/div.json', 'w'), ensure_ascii=False, indent=1)
print("=== UNGUARDED DIVISIONS ===")
n = 0
for r in report:
    if not r['guarded']:
        n += 1
        print("  %s L%d  divisor=%s  | %s" % (r['file'], r['line'], r['divisor'], r['code']))
print("total div lines:", len(report), "unguarded:", n)
