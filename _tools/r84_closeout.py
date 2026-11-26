"""R84 收口：registry 注册 + JSONL 语料追加 + 三方对账。仅接受 accepted.json 中的件。"""
import json, os, glob, datetime, shutil, sys

LIB = r'C:\Library'
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
JSONL = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
STAGE = os.path.join(LIB, '_Staging_Raw', '2026-11-24')
ROUND = 'R84'
VERSION = 'v2.76.0'
NOW = datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()

acc = json.load(open(os.path.join(STAGE, '_r84_accepted.json'), encoding='utf-8'))
rej = json.load(open(os.path.join(STAGE, '_r84_rejected.json'), encoding='utf-8')) if os.path.exists(os.path.join(STAGE, '_r84_rejected.json')) else []

# 备份
shutil.copy(REG, REG + '.bak_r84')
shutil.copy(JSONL, os.path.join(STAGE, 'jsonl.bak_r84.jsonl'))

reg = json.load(open(REG, encoding='utf-8'))
have = {c['name'] for c in reg['components']}
added = []
for it in acc:
    name = it['name']
    if name in have:
        print('SKIP dup', name); continue
    cat = it['category']
    fp = os.path.join(LIB, cat, name + '.st')
    if not os.path.exists(fp):
        print('SKIP missing file', fp); continue
    reg['components'].append({
        'name': name,
        'category': cat,
        'type': 'FB' if name.startswith('FB_') else 'FC',
        'file_path': fp,
        'function_tags': [cat.replace('DL_', '').lower(), 'r84', 'factory', 'vertical-process'],
        'complexity': it['complexity'],
        'registered_at': NOW,
        'origin': {'mode': 'internal',
                   'source': '道莅原创（clean-room 自研，行业工艺公式）',
                   'license': 'MIT', 'ref_tag': 'R84-V'},
        'l2_status': 'l2-pass',
        'round': ROUND,
        'description': it['desc'],
    })
    added.append(it)

# counts 重算
counts = {}
for c in reg['components']:
    counts[c['category']] = counts.get(c['category'], 0) + 1
reg['counts'] = counts
reg['total_components'] = len(reg['components'])
reg['version'] = VERSION
reg['last_updated'] = NOW
json.dump(reg, open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

# JSONL 追加
ARCH_TPL = ("架构：按「接口校验 → 物理量换算 → 核心计算 → 域限幅 → 输出与标志」五段式组织，纯函数化不依赖全局量（R1）。"
            "状态管理：{fsm}定时器每周期无条件刷新（R7）且不跨相 OR（R18）。"
            "防错：所有分母显式零闸（R4）、NaN/Inf 用区间判据拦截（R21）、{extra}。"
            "语法：纯 IEC 6311-3 直译写法，禁 DOWNTO（R17）、禁构造式转换（R10），定长数组禁 LOWER_BOUND（R37），"
            "FB 内禁 PROPERTY（R14）。变量声明逐行中英双语带单位注释（R5）。")
ARCH_TPL = ARCH_TPL.replace('IEC 6311-3', 'IEC 61131-3')

lines = []
for it in added:
    src = open(os.path.join(LIB, it['category'], it['name'] + '.st'), encoding='utf-8').read()
    if it['name'].startswith('FB_'):
        fsm = 'FB 采用 ENUM+CASE 且 CASE 必带 ELSE 兜底回安全态（R6），'
    else:
        fsm = 'FC 无状态量，'
    extra = it.get('extra', '输出附有效性与量纲自洽声明，单点异常不得导致下游误动作')
    instr = (f"在{it['category']}产线的现场控制程序中，需要实现「{it['desc']}」。"
             f"工艺要求：给定工况参数与设定值后，周期内稳定输出可直接下装到 PLC 的结果；"
             f"须处理零值/负值/超量程/非有限数（NaN/Inf）等边界条件，输出附有效性标志与单位口径，"
             f"不得因单点异常导致下游执行机构误动作。请用 IEC 61131-3 结构化文本（ST）实现，跨平台可编译，变量声明带中英双语注释。")
    lines.append(json.dumps({
        'instruction': instr,
        'architecture_thought': ARCH_TPL.format(fsm=fsm, extra=extra),
        'output': src,
        'meta': {'name': it['name'], 'category': it['category'],
                 'type': 'FB' if it['name'].startswith('FB_') else 'FC',
                 'complexity': it['complexity'], 'round': ROUND, 'license': 'MIT'},
    }, ensure_ascii=False))

with open(JSONL, 'a', encoding='utf-8') as f:
    for l in lines:
        f.write(l + '\n')

# 三方对账
nreg = len(reg['components'])
njsonl = sum(1 for _ in open(JSONL, encoding='utf-8'))
disk = set()
for f in glob.glob(os.path.join(LIB, 'DL_*', '*.st')):
    disk.add(os.path.splitext(os.path.basename(f))[0])
regnames = {c['name'] for c in reg['components']}
out = {
    'round': ROUND, 'version': VERSION, 'registered': len(added), 'rejected': len(rej),
    'registry': nreg, 'jsonl': njsonl, 'st_files': len(disk),
    'reg_minus_disk': sorted(regnames - disk), 'disk_minus_reg': sorted(disk - regnames),
    'jsonl_minus_reg': njsonl - nreg, 'counts': counts, 'at': NOW,
}
json.dump(out, open(os.path.join(STAGE, '_r84_closeout.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(json.dumps(out, ensure_ascii=False, indent=1))

# R504 逐字节校验：新行 output 与磁盘一致
bad = 0
allines = open(JSONL, encoding='utf-8').read().splitlines()[-len(added):]
for l in allines:
    o = json.loads(l)
    nm = o['meta']['name']; ct = o['meta']['category']
    if o['output'] != open(os.path.join(LIB, ct, nm + '.st'), encoding='utf-8').read():
        bad += 1; print('MISMATCH', nm)
print('R504 byte-identity: %d/%d SAME' % (len(added) - bad, len(added)))
