# -*- coding: utf-8 -*-
import importlib.util, sys, os
sys.path.insert(0, r'C:\Library\_tools')
spec = importlib.util.spec_from_file_location('p77', r'C:\Library\_tools\r77_plan.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
rows = m.rows
out = ['# CODING_SPEC_R77 —— 编码席派发清单（45 件，按批次顺序写盘）', '']
for b in ['B2', 'B3', 'B1']:
    sub = [r for r in rows if r[5] == b]
    out.append('## 批次 %s（%d 件）' % (b, len(sub)))
    for i, (n, cat, f, tag, cx, batch, tier, src) in enumerate(sub, 1):
        d = r'C:\Library\%s\%s.st' % (cat, n)
        out.append('%d. `%s` → %s ｜ %s ｜ %s' % (i, n, d, cx, f))
    out.append('')
open(r'C:\Library\_Staging_Raw\2026-11-23\CODING_SPEC_R77.md', 'w', encoding='utf-8').write('\n'.join(out))
print('ok', len(rows), [len([r for r in rows if r[5]==b]) for b in ['B2','B3','B1']])
