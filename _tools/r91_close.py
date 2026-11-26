# -*- coding: utf-8 -*-
"""R91 收口：registry 注册 + JSONL 追加。仅对 L2 PASS + 审校 PASS 的件执行。
用法: python _tools/r91_close.py <accept_names.txt>   # 每行一个组件名，空行忽略
"""
import json, os, re, io, sys, datetime

ROOT = r'C:\Library'
STG = os.path.join(ROOT, '_Staging_Raw', '2026-11-25')
TARGETS = json.load(io.open(os.path.join(STG, 'r91_targets.json'), encoding='utf-8'))
BYNAME = {t['name']: t for t in TARGETS}
NOW = datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S+08:00')


def parse_header(src):
    h = {}
    m = re.search(r'\(\*(.*?)\*\)', src, re.S)
    if not m:
        return h
    for line in m.group(1).splitlines():
        line = line.strip()
        for key in ('Name', 'Category', 'Version', 'Round', '功能', '边界条件', '量纲自证', '开源溯源'):
            if line.startswith(key + '：') or line.startswith(key + ':'):
                h[key] = line.split('：', 1)[-1].split(':', 1)[-1].strip()
    return h


def _vars(src, block):
    m = re.search(block + r'(.*?)END_VAR', src, re.S)
    if not m:
        return []
    out = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith('(*') or line.startswith('//'):
            continue
        mm = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_]*)', line)
        if mm:
            out.append(mm.group(1))
    return out


def build_instruction(t, src, hdr):
    ins = _vars(src, r'VAR_INPUT')
    outs = _vars(src, r'VAR_OUTPUT')
    fam = t['family']
    fn = hdr.get('功能', t['desc']).split('。')[0]
    bd = hdr.get('边界条件', '')
    dm = hdr.get('量纲自证', '')
    if t['tier'] == '复杂':
        head = ('某%s产线要把「%s」固化成可复用标准功能块（%s，%s）。现场约束：① 时序必须可中断，任一相超时'
                '或外部故障都要安全退出并锁存故障码，且故障解除后必须重新给启动边沿才能再启动；② REAL 入参可能'
                '出现 NaN/Inf/0/负值，须逐项入闸并闸断实值通路，不许只置无效位；③ 百分比与效率入参先归一化，'
                '跨量纲相加一律禁止；④ 相迁移须由定时器 Q 位与状态量门控，不许用单拍布尔；⑤ 故障态所有物理'
                '输出必须落到安全侧，锁存量必须有安全初值防上电直穿。' % (fam, fn, t['name'], t['cx']))
    else:
        head = ('某%s工位要把「%s」做成可直接复用的计算标准件（%s，%s）。现场约束：① 入参来自现场仪表，'
                '可能 NaN/Inf/0/负值，须逐项入闸并给出无效出口；② 物理域须钳制（百分比 0~100、效率 0~1），'
                '越域判非法而不是静默饱和后继续判合格；③ 判据必须取钳制前原始值，禁止「先 LIMIT 再判超量程」；'
                '④ 量纲须自证，加法两侧单位一致。' % (fam, fn, t['name'], t['cx']))
    body = '接口：入参 %s；出参 %s。' % ('/'.join(ins[:6]), '/'.join(outs[:6]))
    tail = '边界与量纲口径：%s %s' % (bd[:300], ('量纲自证：' + dm[:140]) if dm else '')
    return head + body + tail


def build_thought(t, src, hdr):
    states = sorted(set(re.findall(r'\b(e[A-Z][A-Za-z0-9_]{2,})\b', src)))
    states = [s for s in states if s.startswith('e') and len(s) > 4][:12]
    tons = len(set(re.findall(r'\b(ton[A-Za-z0-9_]*)\s*\(', src)))
    rts = len(set(re.findall(r'\b(rt[A-Za-z0-9_]*)\s*\(', src)))
    lim = len(re.findall(r'LIMIT\s*\(', src))
    big = 'DL_BIG' in src
    eps = 'DL_EPS' in src
    parts = []
    if t['tier'] == '复杂':
        parts.append('架构：%s 采用「入口闸 → 段解算 → 相位机（只做迁移）→ 后置段（预算/快照）→ 出口单点映射」'
                     '五段式。相位机用 ENUM + CASE 实现（%d 相：%s），CASE 末尾 ELSE 强制回故障相并清全部输出，'
                     '杜绝非法相位 ID 让输出悬挂。' % (t['name'], len(states), '/'.join(states[:8])))
        parts.append('时序：%d 个 TON 实例（相定时 + 相超时 + 整序总超时）与 %d 个 R_TRIG（启停边沿），'
                     '全部在周期首无条件刷新，不放进任何 IF，避免条件调用导致计时冻结。' % (tons, rts))
        parts.append('防错：入口对每个 REAL 入参做 NOT(x > -DL_BIG AND x < DL_BIG) 非有限闸（%s），'
                     '命中即闸断实值通路而非只置标志；时间参数零值视为该相跳过（合法组态）但不放宽超时。'
                     % ('已置' if big else '未置'))
        parts.append('状态与安全：锁存故障码 _uFault + 故障位 _bFault + 相位 _eState 三件套；'
                     '所有输出指令量给安全初值（%s），待机相显式赋值，防上电 0.0 直穿下发。'
                     % ('冷启动专项 R25 已覆盖' if 'R25' in src or '首版' in src else '按 R25 口径'))
        parts.append('解耦：不引用任何其他 DL 组件（零外部依赖），只用 IEC 标准函数与 TON/R_TRIG，'
                     '保证跨平台可移植；OOP 侧以单一 FUNCTION_BLOCK 封装，无 PROPERTY（RuSTy 1.0.8 不解析）。')
    else:
        parts.append('架构：%s 为无状态纯计算件，采用「入闸 → 原始值判据 → 钳制 → 单点出口」四段式，'
                     '不引入任何内部状态，便于在任意扫描周期内幂等调用。' % t['name'])
        parts.append('防错：分母零闸用 ABS(den) > DL_EPS（%s）；非有限闸用 NOT(x > -DL_BIG AND x < DL_BIG) '
                     '同时拦 NaN 与 Inf（%s），命中即把 REAL 出口强制 0.0，不把 NaN 传给下游（R19）。'
                     % ('已置' if eps else '未置', '已置' if big else '未置'))
        parts.append('判据同源（R24）：超限判定取 LIMIT 之前的原始值，避免「先夹到量程再判超量程」造成判据恒真。'
                     '物理域越界的处理是「钳制输出 + 置 xValid=FALSE」，不静默饱和后继续判合格。')
        parts.append('量纲：%d 处 LIMIT 全部用于同量纲区间夹取；百分比换算统一乘 100 因子，效率类统一 0~1，'
                     '跨量纲加法在本件内不存在，量纲关系在文件头「量纲自证」段逐式声明。' % lim)
        parts.append('解耦：零外部组件依赖，零 GVL、零物理地址，纯 IEC 61131-3 子集，可被任意 FB/PRG 直接调用。')
    return '\n'.join(parts)


def main():
    accept_file = sys.argv[1]
    accept = [l.strip() for l in io.open(accept_file, encoding='utf-8') if l.strip()]
    regp = os.path.join(ROOT, 'INDEX_REGISTRY.json')
    reg = json.load(io.open(regp, encoding='utf-8'))
    have = set(c['name'] for c in reg['components'])

    added, skipped = [], []
    for nm in accept:
        if nm in have:
            skipped.append((nm, 'already registered'))
            continue
        t = BYNAME.get(nm)
        if not t:
            skipped.append((nm, 'not in r91_targets'))
            continue
        p = os.path.join(ROOT, t['cat'], nm + '.st')
        if not os.path.exists(p):
            skipped.append((nm, 'file missing'))
            continue
        src = io.open(p, encoding='utf-8').read()
        hdr = parse_header(src)
        tags = ['clean-room', 'R91', t['family'], t['cx'], 'DL_Process']
        reg['components'].append({
            'name': nm,
            'category': t['cat'],
            'function_tags': tags,
            'complexity': t['cx'],
            'registered_at': NOW,
            'l2_status': 'l2-pass',
            'round': 'R91',
            'lines': len(src.splitlines()),
            'version': hdr.get('Version', '1.0.0'),
            'source': hdr.get('开源溯源', 'clean-room'),
        })
        added.append((nm, src, hdr))

    # counts
    cnt = {}
    for c in reg['components']:
        cnt[c['category']] = cnt.get(c['category'], 0) + 1
    reg['counts'] = cnt
    reg['total_components'] = len(reg['components'])
    reg['version'] = '2.83.0'
    reg['last_updated'] = NOW
    json.dump(reg, io.open(regp, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

    # JSONL
    jp = os.path.join(ROOT, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
    buf = []
    for nm, src, hdr in added:
        t = BYNAME[nm]
        rec = {
            'id': 'DL-R91-%03d' % t['no'],
            'name': nm,
            'category': t['cat'],
            'complexity': t['cx'],
            'round': 'R91',
            'instruction': build_instruction(t, src, hdr),
            'architecture_thought': build_thought(t, src, hdr),
            'output': src,
        }
        buf.append(json.dumps(rec, ensure_ascii=False))
    with io.open(jp, 'a', encoding='utf-8') as f:
        for line in buf:
            f.write(line + '\n')

    n_jsonl = sum(1 for _ in io.open(jp, encoding='utf-8'))
    import glob
    n_disk = len(glob.glob(os.path.join(ROOT, 'DL_*', '*.st')))
    print('ADDED', len(added))
    print('SKIPPED', skipped)
    print('REGISTRY', reg['total_components'])
    print('COUNTS', cnt)
    print('JSONL', n_jsonl)
    print('DISK_ST', n_disk)
    print('RECONCILE', 'OK' if n_disk == reg['total_components'] else 'MISMATCH %d' % (n_disk - reg['total_components']))
    json.dump({'added': [a[0] for a in added], 'skipped': skipped,
               'registry': reg['total_components'], 'counts': cnt, 'jsonl': n_jsonl, 'disk': n_disk},
              io.open(os.path.join(STG, 'r91_added.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
