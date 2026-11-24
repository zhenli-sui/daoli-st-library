# -*- coding: utf-8 -*-
"""R83 收口：registry 登记 + SFT JSONL 追加 + 三方对账
用法: python r83_closeout.py <accepted_names.txt>
"""
import json, os, sys, datetime, io

LIB = r'C:\Library'
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
JSONL = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
ROUND = 'R83'
NOW = datetime.datetime.now().astimezone().isoformat(timespec='seconds')

acc = [l.strip() for l in open(sys.argv[1], encoding='utf-8') if l.strip()]
targets = json.load(open(os.path.join(LIB, '_Staging_Raw', '2026-11-24', 'r83_targets.json'), encoding='utf-8'))
tmap = {t['name']: t for t in targets}

reg = json.load(open(REG, encoding='utf-8'))
comps = reg['components']
have = {c['name'] for c in comps}

now_added, skipped = [], []
for name in acc:
    if name in have:
        skipped.append(name)
        continue
    t = tmap[name]

    def read(p):
        with io.open(p, encoding='utf-8') as f:
            return f.read()

    path = os.path.join(LIB, t['cat'], name + '.st')
    if not os.path.exists(path):
        skipped.append(name + ' (NO_FILE)')
        continue
    src = read(path)
    tags = [t['cat'].replace('DL_', '').lower(), 'r83', 'factory']
    comps.append({
        'name': name,
        'category': t['cat'],
        'type': t['kind'],
        'file_path': path,
        'function_tags': tags + ['vertical-process'],
        'complexity': t['cmplx'],
        'registered_at': NOW,
        'origin': {'mode': 'internal',
                   'source': '道莅原创（clean-room 自研，行业工艺公式）',
                   'license': 'MIT',
                   'ref_tag': 'R83-' + t['fam']},
        'l2_status': 'l2-pass',
        'round': ROUND,
        'description': t['desc'],
    })
    have.add(name)
    now_added.append(name)

# 写 registry
reg['version'] = 'v2.75.0'
reg['counts'] = {}
from collections import Counter
cnt = Counter(c['category'] for c in comps)
reg['counts'] = {k: cnt[k] for k in ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']}
assert sum(reg['counts'].values()) == len(comps)
json.dump(reg, open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

# JSONL
n0 = sum(1 for _ in open(JSONL, encoding='utf-8'))
added = 0
with io.open(JSONL, 'a', encoding='utf-8', newline='\n') as f:
    for name in now_added:
        t = tmap[name]
        src = read(os.path.join(LIB, t['cat'], name + '.st'))
        inst = ('在%s产线的现场控制程序中，需要实现「%s」。工艺要求：给定工况参数与设定值后，'
                '周期内稳定输出可直接下装到 PLC 的结果；须处理零值/负值/超量程/非有限数（NaN/Inf）等边界条件，'
                '输出附有效性标志与单位口径，不得因单点异常导致下游执行机构误动作。'
                '请用 IEC 61131-3 结构化文本（ST）实现该%s，跨平台可编译，变量声明带中英双语注释。' % (t['cat'], t['desc'], '功能块' if t['kind'] == 'FB' else '函数'))
        thought = ('架构：按「接口校验 → 物理量换算 → 核心计算 → 域限幅 → 输出与标志」五段式组织，'
                   '纯函数化不依赖全局量（R1）。状态管理：%s 采用 ENUM+CASE 且 CASE 必带 ELSE 兜底（R6），'
                   '定时器每周期无条件刷新（R7）且不跨相 OR（R18）。防错：所有分母显式零闸（R4）、'
                   'NaN/Inf 用区间判据拦截（R21）、比率类输出确保非恒等式（R20）。'
                   '语法：纯 IEC 61131-3，禁 DOWNTO（R17）、禁构造式类型转换（R10）、声明分号齐全（R11）。'
                   '解耦：不引用其他 DL 件，所需逻辑内联（R16）；跨平台无物理地址绑定（R2）。'
                   % ('FB' if t['kind'] == 'FB' else '无状态机（纯计算）'))
        row = {'instruction': inst, 'architecture_thought': thought, 'output': src,
               'meta': {'name': name, 'category': t['cat'], 'type': t['kind'],
                        'complexity': t['cmplx'], 'round': ROUND, 'license': 'MIT'}}
        f.write(json.dumps(row, ensure_ascii=False) + '\n')
        added += 1

n1 = sum(1 for _ in open(JSONL, encoding='utf-8'))
st = 0
for d in ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']:
    p = os.path.join(LIB, d)
    st += sum(1 for x in os.listdir(p) if x.endswith('.st')) if os.path.isdir(p) else 0

print('ADDED', len(now_added), 'SKIPPED', skipped)
print('REGISTRY', len(comps), reg['counts'])
print('JSONL', n0, '->', n1, 'diff', n1 - len(comps))
print('ST_FILES', st, 'REG_MINUS_ST', len(comps) - st)
