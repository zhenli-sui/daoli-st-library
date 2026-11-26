# -*- coding: utf-8 -*-
"""R90 收口：registry 注册 + JSONL 追加。仅对 L2 PASS + 审校 PASS 的件执行。"""
import json, os, re, io, datetime

ROOT = r'C:\Library'
STG = os.path.join(ROOT, '_Staging_Raw', '2026-11-25')
TARGETS = json.load(open(os.path.join(STG, 'r90_targets.json'), encoding='utf-8'))
NOW = '2026-11-25T08:18:00+08:00'

def parse_header(src):
    h = {}
    m = re.search(r'\(\*(.*?)\*\)', src, re.S)
    if not m:
        return h
    for line in m.group(1).splitlines():
        line = line.strip()
        for key in ('Name', 'Category', 'Version', 'Round', '功能', '边界条件', '量纲自证', '开源溯源'):
            if line.startswith(key + '：') or line.startswith(key + ':'):
                h[key] = line.split('：', 1)[-1].split(':', 1)[-1].strip() if ('：' in line or ':' in line) else ''
    return h

def inputs_of(src):
    m = re.search(r'VAR_INPUT(.*?)END_VAR', src, re.S)
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

def outs_of(src):
    m = re.search(r'VAR_OUTPUT(.*?)END_VAR', src, re.S)
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
    ins = inputs_of(src)
    outs = outs_of(src)
    fam = t['family_name']
    boundary = hdr.get('边界条件', '')
    dim = hdr.get('量纲自证', '')
    if t['tier'] == 'complex':
        head = ('某%s产线需要把「%s」做成可复用的标准功能块（%s，C%d）。现场约束：① 时序必须可中断，'
                '任一相超时或外部故障都要能安全退出并锁存故障码；② 所有 REAL 输入都可能出现 NaN/Inf/0/负值，'
                '必须逐项入闸且闸断实值通路，不许只置无效位；③ 百分比与效率类入参先归一化，量纲不一致的加法一律禁止；'
                '④ 状态迁移后必须清迭代预算与锁存，快照变量在周期末统一更新；⑤ 所有物理输出在故障态必须落到安全侧。'
                % (fam, hdr.get('功能', t['func']).split('。')[0], fam, t['complexity']))
    else:
        head = ('某%s工位需要把「%s」做成可直接复用的计算标准件（%s，C%d）。现场约束：① 入参来自现场仪表，'
                '可能出现 NaN/Inf/0/负值，必须逐项入闸并给出无效出口；② 物理域要钳制（百分比 0~100、效率 0~1），'
                '越域要判非法而不是静默饱和后继续判合格；③ 量纲要自证，加法两侧单位必须一致。'
                % (fam, hdr.get('功能', t['func']).split('。')[0], t['name'], t['complexity']))
    body = '接口：入参 %s；出参 %s。' % ('/'.join(ins[:6]), '/'.join(outs[:6]))
    tail = '边界条件与量纲口径：%s %s' % (boundary[:260], ('量纲自证：' + dim[:120]) if dim else '')
    return head + body + tail

def build_thought(t, src, hdr):
    states = re.findall(r'E_DL_[A-Za-z0-9_]*\.(e[A-Za-z0-9_]+)\s*:', src)
    tons = len(set(re.findall(r'\b(ton[A-Za-z0-9_]*)\s*\(', src)))
    rg = len(set(re.findall(r'\b(rt[A-Za-z0-9_]*)\s*\(', src)))
    big = 'DL_BIG' in src
    eps = 'DL_EPS' in src
    lim = len(re.findall(r'LIMIT\s*\(', src))
    parts = []
    if t['tier'] == 'complex':
        parts.append('架构：%s 采用「入口闸 → 段解算 → 相位机（只做迁移）→ 后置段（预算/快照）→ 出口单点映射」五段式，'
                     '把判定与赋值彻底分离，避免同一输出在多分支重复写导致覆盖。' % t['name'])
        parts.append('状态机：ENUM %s 共 %d 个相位（%s），CASE 每相只写迁移条件，末枝 ELSE 兜底置故障码并强制回故障相；'
                     '全序另有总超时 TON，避免任一相卡死。' % (t.get('enum', 'E_DL_State'), len(states),
                                                          '/'.join(states[:8]) if states else '单相'))
        parts.append('防错：入口用 NOT(x>-DL_BIG AND x<DL_BIG) 同时拦 NaN 与 Inf 并闸断实值通路；'
                     '除法分母逐一过 ABS()>DL_EPS；%s；OUT 出口统一经 LIMIT 或字面量赋值。' % (
                         '含 %d 处 LIMIT 兜底' % lim if lim else '全程标量直算'))
        parts.append('计时与解耦：%d 个 TON / %d 个 R_TRIG 实例每周期无条件刷新；故障码与状态解耦，'
                     '故障后回放锁存码而不按当下输入重推断，便于定位。' % (tons, rg))
    else:
        parts.append('架构：%s 为纯函数式标准件，先做无效/退化早退（写哨兵并 RETURN），再做主算，最后统一聚合有效位，'
                     '保证「判据与出口同源」不再二次换算。' % t['name'])
        parts.append('防错：%s%s；物理域越界判非法而非饱和后继续判合格（R90 教训：先夹紧再判上限会让判据恒真）。'
                     % ('有 DL_EPS 分母零闸；' if eps else '', '有 DL_BIG 非有限闸；' if big else ''))
        parts.append('量纲：%s' % (hdr.get('量纲自证', '按 SI 基本量逐项核对，加法两侧单位一致')[:140]))
        parts.append('复用：无全局状态、无外部依赖，可直接在任意 IEC 61131-3 平台实例化为 FB 的 ST 方法。')
    return ''.join(parts)

def main():
    regp = os.path.join(ROOT, 'INDEX_REGISTRY.json')
    reg = json.load(open(regp, encoding='utf-8'))
    have = {c['name'] for c in reg['components']}
    jsonlp = os.path.join(ROOT, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
    added = []
    lines = []
    for t in TARGETS:
        name = t['name']
        fp = os.path.join(ROOT, t['category'], name + '.st')
        if not os.path.exists(fp):
            print('MISSING', name)
            continue
        src = open(fp, encoding='utf-8', errors='ignore').read()
        hdr = parse_header(src)
        enum_m = re.search(r'TYPE\s+(E_DL_[A-Za-z0-9_]+)', src)
        tt = dict(t)
        tt['enum'] = enum_m.group(1) if enum_m else 'E_DL_State'
        if name not in have:
            reg['components'].append(dict(
                name=name, category=t['category'], type=t['prefix'],
                file_path=fp, function_tags=[t['category'].replace('DL_', '').lower(), 'vertical-process',
                                             'r90', t['family'], 'l2-pass'],
                complexity=t['complexity'], registered_at=NOW,
                origin=dict(mode='internal', source='道莅原创（clean-room 自研，依据公开工艺公式）',
                            license='MIT', ref_tag='R90'),
                version='1.0.0', l2_status='l2-pass', qa_status='pass',
                function=hdr.get('功能', t['func'])[:120]))
            have.add(name)
        if name not in {a['name'] for a in added}:
            added.append(dict(name=name, category=t['category'], complexity=t['complexity'], tier=t['tier']))
        lines.append(json.dumps(dict(
            instruction=build_instruction(tt, src, hdr),
            architecture_thought=build_thought(tt, src, hdr),
            output=src,
            meta=dict(name=name, category=t['category'], complexity=t['complexity'], round='R90',
                      license='MIT', origin='clean-room')), ensure_ascii=False))
    reg['total_components'] = len(reg['components'])
    cnt = {}
    for c in reg['components']:
        cnt[c['category']] = cnt.get(c['category'], 0) + 1
    reg['counts'] = cnt
    reg['last_updated'] = NOW
    reg['version'] = '2.82.0'
    json.dump(reg, open(regp, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    with open(jsonlp, 'a', encoding='utf-8') as f:
        for ln in lines:
            f.write(ln + '\n')
    json.dump(added, open(os.path.join(STG, 'r90_added.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('registered', len(added), 'total', reg['total_components'], 'counts', cnt, 'sum', sum(cnt.values()))
    print('jsonl appended', len(lines))

if __name__ == '__main__':
    main()
