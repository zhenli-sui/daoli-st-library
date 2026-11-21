# -*- coding: utf-8 -*-
"""R21 终审修复重注入：.st → JSONL output + registry version/line_count
纪律：单行合法 JSON、sha256 复验、registry 版本同步（R19-2 / R87 五步法）
"""
import json, hashlib, os

JL = 'C:/Library/_AI_Training_Dataset/daoli_st_sft_dataset.jsonl'
RG = 'C:/Library/INDEX_REGISTRY.json'

FIXED = {
    'FC_DL_DateToIsoString': ('DL_MathData', '1.0.0', '1.0.1'),
    'FC_DL_Crc16Generic':    ('DL_MathData', '1.0.0', '1.0.1'),
    'FC_DL_StringToDint':    ('DL_MathData', '1.0.0', '1.0.1'),
    'FB_DL_PulseWidthFilter':('DL_Base',    '1.0.0', '1.0.1'),
}

# 1) 读源码
newtxt, sha = {}, {}
for name, (cat, old, new) in FIXED.items():
    p = 'C:/Library/%s/%s.st' % (cat, name)
    t = open(p, encoding='utf-8').read()
    newtxt[name] = t
    sha[name] = hashlib.sha256(t.encode('utf-8')).hexdigest()
    assert ('当前版本 : %s' % new) in t, name
    assert ('v%s' % new) in t, name

# 2) JSONL 单行替换
lines = open(JL, encoding='utf-8').read().splitlines()
hit = {k: 0 for k in FIXED}
out = []
for ln in lines:
    d = json.loads(ln)
    for name in FIXED:
        if d['output'].lstrip().startswith('(*') and ('组件名称 : %s' % name) in d['output'][:400]:
            d['output'] = newtxt[name]
            hit[name] += 1
    out.append(json.dumps(d, ensure_ascii=False))
assert all(v == 1 for v in hit.values()), hit
open(JL, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')

# 3) registry 版本与行数同步
reg = json.load(open(RG, encoding='utf-8'))
cnt = {k: 0 for k in FIXED}
for c in reg['components']:
    if c['name'] in FIXED:
        cat, old, new = FIXED[c['name']]
        assert c['version'] == old, (c['name'], c['version'])
        c['version'] = new
        c['line_count'] = newtxt[c['name']].count('\n') + (0 if newtxt[c['name']].endswith('\n') else 1)
        cnt[c['name']] += 1
assert all(v == 1 for v in cnt.values()), cnt
reg['last_updated'] = '2026-11-16T21:18:00+08:00'
json.dump(reg, open(RG, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

# 4) 复验：JSONL output == 源文件、sha 一致
lines2 = open(JL, encoding='utf-8').read().splitlines()
ok = {}
for ln in lines2:
    d = json.loads(ln)
    for name in FIXED:
        if ('组件名称 : %s' % name) in d['output'][:400]:
            ok[name] = (d['output'] == newtxt[name],
                        hashlib.sha256(d['output'].encode('utf-8')).hexdigest() == sha[name])
print('JSONL lines =', len(lines2), '(expect 364)')
for k, v in ok.items():
    print('%-24s eq=%s sha=%s len=%d lines=%d' % (k, v[0], v[1], len(newtxt[k]), newtxt[k].count('\n') + 1))
print('registry total =', reg['total_components'], 'counts =', reg['counts'])
