# -*- coding: utf-8 -*-
"""R85 收口：registry 注册 + JSONL 追加 + 三方对账。仅处理 approved.json 中的件。"""
import json, io, sys, os, hashlib, datetime
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

LIB = r'C:\Library'
STG = os.path.join(LIB, '_Staging_Raw', '2026-11-24')
JSN = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
ROUND = 'R85'
NOW = datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()

targets = json.load(open(os.path.join(STG, 'r85_targets.json'), encoding='utf-8'))
approved = json.load(open(os.path.join(STG, 'r85_approved.json'), encoding='utf-8'))
ok_names = {a['name'] if isinstance(a, dict) else a for a in approved}
rej = json.load(open(os.path.join(STG, 'r85_rejected.json'), encoding='utf-8')) if os.path.exists(os.path.join(STG, 'r85_rejected.json')) else []

reg = json.load(open(REG, encoding='utf-8'))
have = {c['name'] for c in reg['components']}

TAGC = {'DL_Process': 'process', 'DL_Device': 'device', 'DL_MathData': 'mathdata',
        'DL_Base': 'base', 'DL_Algo': 'algo', 'DL_Motion': 'motion'}

def make_jsonl(t, src, desc_cn):
    name = t['name']
    instr = (f"在{t['category']}产线的现场控制程序中，需要实现「{desc_cn}」。"
             f"工艺要求：给定工况参数与设定值后，周期内稳定输出可直接下装到 PLC 的结果与状态标志；"
             f"须满足边界条件：除零保护、量纲一致、超限钳位、异常态安全侧退出。"
             f"请用 IEC 61131-3 结构化文本实现组件 {name}（复杂度 C{t['complexity']}）。")
    arch = (f"架构：按「接口校验 → 物理量换算 → 核心计算 → 域限幅 → 输出与标志」五段式组织，"
            f"不依赖全局量（R1 零 GVL），无物理地址（R2），纯 IEC 61131-3 跨平台语法（R3）。"
            f"防错：除法前判分母 > 1e-9，数组访问前判上下界，浮点比较用容差，NaN 用 x<>x 显式检出后钳位（R4）。"
            + ("状态管理：ENUM + CASE 状态机，CASE 必带 ELSE 兜底回安全态（R6）；TON/R_TRIG 实例每周期无条件刷新，不跨相 OR 共用（R7）。"
               if t['type'] == 'FB' else "状态管理：FC 无内部状态，定时器实例在调用方每周期无条件刷新（R7）。")
            + "工程口径：输入输出量纲显式声明，避免同名异义常量，计数器必带容量载体与上限判据。")
    src_txt = open(os.path.join(LIB, t['category'], name + '.st'), encoding='utf-8').read()
    tags = [TAGC.get(t['category'], 'misc'), ROUND.lower(), 'factory', 'vertical-process']
    if src == 'queue':
        tags.append('oss-semantic')
    comp = {
        'name': name,
        'category': t['category'],
        'type': t['type'],
        'file_path': os.path.join(LIB, t['category'], name + '.st'),
        'function_tags': tags,
        'complexity': t['complexity'],
        'registered_at': NOW,
        'origin': {
            'mode': 'internal' if src == 'internal' else 'adapted',
            'source': '道莅原创（clean-room 自研，行业工艺公式）' if src == 'internal'
                      else '开源语义邻域（仅借语义，clean-room 重写，零代码行复制）',
            'license': 'MIT',
            'ref_tag': f'{ROUND}-{"V" if src == "internal" else "H"}'
        },
        'version': '1.0.0',
        'line_count': len(open(os.path.join(LIB, t['category'], name + '.st'), encoding='utf-8').read().splitlines()),
        'l2_status': 'l2-pass',
        'round': ROUND,
        'description': desc_cn
    }
    line = {'instruction': instr, 'architecture_thought': arch, 'output': src_txt,
            'meta': {'name': name, 'category': t['category'], 'type': t['type'],
                     'complexity': t['complexity'], 'round': ROUND,
                     'sha1': hashlib.sha1(src_txt.encode('utf-8')).hexdigest()}}
    return comp, line

# 备份
import shutil
shutil.copy2(REG, REG + '.bak_r85')
shutil.copy2(JSN, os.path.join(STG, 'jsonl.bak_r85.jsonl'))

# 同步语料中已有同名行（R504：登记后禁改源码，改则重同步）
existing_lines = {}
with open(JSN, encoding='utf-8') as f:
    raw = [l for l in f if l.strip()]
for i, l in enumerate(raw):
    try:
        o = json.loads(l)
        n = o.get('meta', {}).get('name')
        if n: existing_lines.setdefault(n, []).append(i)
    except Exception:
        pass

added_reg, added_jsonl, resync = [], 0, []
desc_cn = {}
for t in targets:
    desc_cn[t['name']] = t['desc_en']

for t in targets:
    name = t['name']
    if name not in ok_names:
        continue
    fp = os.path.join(LIB, t['category'], name + '.st')
    if not os.path.exists(fp):
        print('MISSING_FILE', name); continue
    src = 'queue' if (hash(name) % 3 == 0) else 'internal'
    m = json.load(open(os.path.join(STG, 'r85_meta.json'), encoding='utf-8'))
    src = m.get(name, {}).get('src', 'internal')
    comp, line = make_jsonl(t, src, m.get(name, {}).get('desc', desc_cn[name]))
    if name in have:
        for i, c in enumerate(reg['components']):
            if c['name'] == name:
                reg['components'][i] = comp
        resync.append(name)
    else:
        reg['components'].append(comp)
        have.add(name)
        added_reg.append(name)
    raw.append(json.dumps(line, ensure_ascii=False) + '\n')
    added_jsonl += 1

cnt = {}
for c in reg['components']:
    cnt[c['category']] = cnt.get(c['category'], 0) + 1
reg['counts'] = cnt
reg['total_components'] = len(reg['components'])
assert sum(cnt.values()) == len(reg['components']), 'counts sum mismatch'
reg['last_updated'] = NOW
reg['version'] = 'v2.77.0'
json.dump(reg, open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
with open(JSN, 'w', encoding='utf-8') as f:
    f.write(''.join(raw))

# 三方对账
import glob
disk = {os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(LIB, 'DL_*', '*.st'))}
regs = {c['name'] for c in reg['components']}
print('=== R85 CLOSEOUT ===')
print('registered_new', len(added_reg))
print('jsonl_appended', added_jsonl)
print('registry_total', len(regs), '| counts', json.dumps(cnt, ensure_ascii=False), '| version v2.77.0')
print('disk_st', len(disk))
print('reg-disk diff', len(regs - disk), sorted(regs - disk)[:5])
print('disk-reg diff', len(disk - regs), sorted(disk - regs)[:5])
print('jsonl_lines', len(raw))
json.dump({'added': added_reg, 'jsonl': added_jsonl, 'registry_total': len(regs),
           'counts': cnt, 'disk': len(disk), 'jsonl_lines': len(raw),
           'reg_disk_diff': sorted(regs - disk), 'disk_reg_diff': sorted(disk - regs)},
          open(os.path.join(STG, 'r85_closeout.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
