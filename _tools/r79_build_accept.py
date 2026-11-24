# -*- coding: utf-8 -*-
"""R79 生成 accept json：从 ROUND_PLAN_R79.md 解析名称/子库/复杂度，与通过名单求交。

用法：
  python _tools/r79_build_accept.py --passed _Staging_Raw/2026-11-24/_passed.txt
"""
import os, re, json, sys

LIB = r'C:\Library'
STAGE = os.path.join(LIB, '_Staging_Raw', '2026-11-24')
PLAN = os.path.join(STAGE, 'ROUND_PLAN_R79.md')

rows = []
for ln in open(PLAN, encoding='utf-8'):
    m = re.match(r'\|\s*(\d+)\s*\|\s*(FC_DL_\w+|FB_DL_\w+)\s*\|\s*(DL_\w+)\s*\|\s*(\w+)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*(C\d)\s*\|', ln)
    if m:
        rows.append(dict(no=int(m.group(1)), name=m.group(2), category=m.group(3),
                         type=m.group(4), func=m.group(5).strip(), origin=m.group(6).strip(),
                         complexity=int(m.group(7)[1])))

passed = set()
if '--passed' in sys.argv:
    p = sys.argv[sys.argv.index('--passed') + 1]
    passed = {l.strip() for l in open(p, encoding='utf-8') if l.strip()}

FAM = {1: '日历算术族', 2: '整数数论族', 3: '平面几何族', 4: '统计扩展族', 5: '校验和族'}
out = []
for r in rows:
    if passed and r['name'] not in passed:
        continue
    if not os.path.exists(os.path.join(LIB, r['category'], r['name'] + '.st')):
        continue
    if r['no'] <= 9:
        fam = '日历算术族'
    elif r['no'] <= 17:
        fam = '整数数论族'
    elif r['no'] <= 25:
        fam = '平面几何族'
    elif r['no'] <= 33:
        fam = '统计扩展族'
    elif r['no'] <= 41:
        fam = '校验和族'
    else:
        fam = '工艺流程族'
    out.append(dict(name=r['name'], category=r['category'], type=r['type'],
                    complexity=r['complexity'],
                    tags=[r['category'].lower().replace('dl_', ''), fam, 'r79'],
                    origin='道莅原创（%s模板派生，R79）' % fam, license='MIT'))

p = os.path.join(STAGE, '_r79_accept.json')
json.dump(out, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('plan rows', len(rows), '| accept items', len(out), '->', p)
for o in out:
    print(' ', o['name'], o['category'], 'C%d' % o['complexity'])
