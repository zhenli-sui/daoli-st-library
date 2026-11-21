# -*- coding: utf-8 -*-
"""R12 注册登记与语料落库：18 件新增 + 全量 186 条 sha256 真验（含历史漂移修正）。

纪律：
- 只允许改 INDEX_REGISTRY.json / JSONL / 本脚本 / REGISTRY_JSONL_R12.md
- 既有 168 条注册字段零改动；JSONL 仅允许为修正漂移而重注入 output
- output 一律 bytes 级读取 .st 后 decode('utf-8')，保证 encode 回去 sha256 相等
"""
import json
import os
import re
import hashlib
import shutil
from datetime import datetime, timedelta, timezone

LIB = r'C:\Library'
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
JL = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
STAGING = os.path.join(LIB, '_Staging_Raw', '2026-11-15')
META = os.path.join(STAGING, 'meta')
PLAN = os.path.join(STAGING, 'ROUND_PLAN_R12.md')

CATS = ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']

# 名称 -> 功能标签（首个为规格书 source 组标签）
TAGS = {
    'FC_DL_BitArrayExtract':      ['lgf-bitlogic', 'bit-extraction', 'bit-array', 'bounds-check', 'pure-function'],
    'FC_DL_BitArrayInsert':       ['lgf-bitlogic', 'bit-insertion', 'bit-array', 'mask-merge', 'pure-function'],
    'FC_DL_IntervalMembership':   ['lgf-comparator', 'interval', 'comparison', 'boundary-inclusive', 'pure-function'],
    'FB_DL_BitArrayChangeWatch':  ['lgf-bitlogic', 'change-detection', 'bit-array', 'edge-detection', 'state-machine'],
    'FC_DL_ArrayDiffSummary':     ['lgf-comparator', 'array-compare', 'diff-summary', 'statistics', 'pure-function'],
    'FC_DL_StringReplaceAll':     ['lgf-datahandling', 'string', 'replace-all', 'text-processing', 'pure-function'],
    'FB_DL_StringTokenStream':    ['lgf-datahandling', 'string', 'tokenizer', 'stream', 'state-machine'],
    'FC_DL_SolarPositionCalc':    ['lgf-datetimer', 'solar-geometry', 'astronomy', 'time-of-day', 'pure-function'],
    'FC_DL_ModbusExceptionParse': ['oscat-network', 'modbus', 'exception-code', 'protocol', 'decoder'],
    'FC_DL_WaterEnthalpy':        ['oscat-building', 'hvac', 'enthalpy', 'thermodynamics', 'pure-function'],
    'FB_DL_ValveCharacteristic':  ['isa88-process', 'valve', 'characteristic-curve', 'process-control', 'state-machine'],
    'FB_DL_DeviceParamVerify':    ['codesys-forge-devicereader', 'device-parameter', 'verification', 'range-check', 'state-machine'],
    'FB_DL_PortDiagBoard':        ['plcnext-diag', 'roadmap-p0', 'port-diagnostics', 'profinet', 'state-machine'],
    'FB_DL_EnergyMeterAccum':     ['namur-ne43', 'energy-meter', 'accumulation', 'signal-quality', 'state-machine'],
    'FB_DL_VacuumGaugeMux':       ['namur-ne43', 'oscat-building', 'vacuum-gauge', 'multiplexer', 'signal-quality'],
    'FB_DL_LineInterp2Axis':      ['github-topics-motion', 'motion-control', 'interpolation', '2-axis', 'state-machine'],
    'FB_DL_BatchPhaseBase':       ['isa88-batch', 'phase-state-machine', 'batch-control', 'isa88', 'state-machine'],
    'FB_DL_PollTempBank':         ['roadmap-p0', 'polling-scheduler', 'temperature-bank', 'multi-channel', 'state-machine'],
}
SOURCE = {n: t[0] for n, t in TAGS.items()}


def sha(b):
    return hashlib.sha256(b).hexdigest()


def read_bytes(p):
    with open(p, 'rb') as f:
        return f.read()


def read_text(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def parse_spec():
    """从规格书第 1.2 节解析码段、第 3 节解析目录/类型/复杂度。"""
    txt = read_text(PLAN)
    sec = txt[txt.index('### 1.2'):txt.index('### 1.3')]
    rows = re.findall(r'\| \d+ \| `([A-Za-z_0-9]+)` \| `([^`]+)` \| ([^|]+?) \|', sec)
    seg = {}
    for name, info, fault in rows:
        info = info.strip().strip('`').strip()
        fault = fault.strip().strip('`').strip()
        s = info + '(信息级)'
        if '无' not in fault:
            # 故障级单元格可能并列为 `A~B`(`C`) 形式，逐段去反引号
            seg_codes = [t.strip().strip('`') for t in fault.split('/')]
            s += ' / ' + ' / '.join(seg_codes) + '(故障级)'
        seg[name] = s
    heads = re.findall(r'^### 3\.(\d+) `([A-Za-z_0-9]+)`（([A-Za-z_]+)，(FC|FB)，复杂度 (\d+)，源：(.+?)）', txt, re.M)
    meta = {n: {'cat': c, 'type': t, 'cx': int(x), 'src': s} for _, n, c, t, x, s in heads}
    return seg, meta


def parse_seg_codes(s):
    """把 code_segment 字符串展开成 16#AAAA_BBBB 集合。"""
    out = set()
    for part in s.split(' / '):
        m = re.search(r'16#([0-9A-F]{4})_([0-9A-F]{4})(?:~([0-9A-F]{4}))?', part)
        if not m:
            continue
        hi, lo = m.group(1), int(m.group(2), 16)
        end = int(m.group(3), 16) if m.group(3) else lo
        for c in range(lo, end + 1):
            out.add('16#%s_%04X' % (hi, c))
    return out


def detect(out, name_index):
    """返回 output 归属的组件名；多命中时取最长名（防止前缀包含）。"""
    hits = [n for n, mks in name_index if any(mk in out for mk in mks)]
    if not hits:
        return None
    return max(hits, key=len)


def main():
    now = datetime.now(timezone.utc).astimezone()
    seg_map, spec_meta = parse_spec()
    assert len(seg_map) == 18 and len(spec_meta) == 18, (len(seg_map), len(spec_meta))
    order = ['FC_DL_BitArrayExtract', 'FC_DL_BitArrayInsert', 'FC_DL_IntervalMembership',
             'FB_DL_BitArrayChangeWatch', 'FC_DL_ArrayDiffSummary', 'FC_DL_StringReplaceAll',
             'FB_DL_StringTokenStream', 'FC_DL_SolarPositionCalc', 'FC_DL_ModbusExceptionParse',
             'FC_DL_WaterEnthalpy', 'FB_DL_ValveCharacteristic', 'FB_DL_DeviceParamVerify',
             'FB_DL_PortDiagBoard', 'FB_DL_EnergyMeterAccum', 'FB_DL_VacuumGaugeMux',
             'FB_DL_LineInterp2Axis', 'FB_DL_BatchPhaseBase', 'FB_DL_PollTempBank']

    # ---------- 备份 ----------
    b_reg = REG + '.backup_R12'
    b_jl = JL + '.backup_R12'
    if not os.path.exists(b_reg):
        shutil.copy2(REG, b_reg)
    if not os.path.exists(b_jl):
        shutil.copy2(JL, b_jl)
    print('backup:', b_reg, os.path.getsize(b_reg), '|', b_jl, os.path.getsize(b_jl))

    # ---------- 任务 1 注册表 ----------
    reg = json.loads(read_text(REG))
    before_total = reg['total_components']
    before_counts = dict(reg['counts'])
    names = [c['name'] for c in reg['components']]
    assert len(names) == before_total == 168
    assert len(set(names)) == 168
    existing_snapshot = json.dumps(reg['components'], ensure_ascii=False, sort_keys=True)

    added = []
    for k, name in enumerate(order):
        sm = spec_meta[name]
        assert name not in names, 'dup ' + name
        assert sm['cat'] in CATS
        assert SOURCE[name] == TAGS[name][0]
        path = os.path.join(LIB, sm['cat'], name + '.st')
        assert os.path.isfile(path), path
        ts = (now + timedelta(seconds=3 * k)).replace(microsecond=0).isoformat()
        reg['components'].append({
            'name': name,
            'category': sm['cat'],
            'type': sm['type'],
            'file_path': path,
            'function_tags': TAGS[name],
            'complexity': sm['cx'],
            'registered_at': ts,
            'code_segment': seg_map[name],
            'source': SOURCE[name],
        })
        added.append({'name': name, 'category': sm['cat'], 'type': sm['type'],
                      'code_segment': seg_map[name], 'source': SOURCE[name],
                      'complexity': sm['cx'], 'tags': TAGS[name], 'registered_at': ts})

    reg['total_components'] = len(reg['components'])
    reg['version'] = '2.1.0'
    reg['last_updated'] = now.replace(microsecond=0).isoformat()
    cnt = {c: 0 for c in CATS}
    for c in reg['components']:
        cnt[c['category']] = cnt.get(c['category'], 0) + 1
    reg['counts'] = cnt

    # 既有条目零改动断言
    assert json.dumps(reg['components'][:168], ensure_ascii=False, sort_keys=True) == existing_snapshot

    with open(REG, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(reg, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print('registry: total', reg['total_components'], 'ver', reg['version'], 'counts', cnt)

    # 码位 diff：注册表 code_segment vs 规格书 1.2 全表
    spec_all = set()
    for s in seg_map.values():
        spec_all |= parse_seg_codes(s)
    reg_new = set()
    for c in reg['components'][168:]:
        reg_new |= parse_seg_codes(c['code_segment'])
    print('codes: spec', len(spec_all), 'reg_new', len(reg_new),
          'overlap_spec', len(reg_new & spec_all), 'missing', len(spec_all - reg_new),
          'extra', len(reg_new - spec_all))

    # 与全库旧码求差（R30 口径重跑）
    pat = re.compile(r'16#([0-9A-F]{4})_([0-9A-F]{4})')
    newnames = set(order)
    old_codes = set()
    for d in CATS:
        for f in os.listdir(os.path.join(LIB, d)):
            if not f.endswith('.st'):
                continue
            nm = f[:-3]
            if nm in newnames:
                continue
            txt = read_text(os.path.join(LIB, d, f))
            old_codes |= {'16#%s_%s' % (a, b) for a, b in pat.findall(txt)}
            old_codes |= {'16#%s_%s' % (a, b) for a, b in pat.findall(txt.replace('\r\n', '\n'))}
    sentinel = {'16#0000_0000', '16#FFFF_FFFF', '16#FFFF_FFFE', '16#DEAD_BEEF'}
    collide = (reg_new - sentinel) & old_codes
    print('collision vs 168-old:', len(collide), sorted(collide))

    # ---------- 任务 2 JSONL ----------
    raw_bytes = read_bytes(JL)
    assert not raw_bytes.startswith(b'\xef\xbb\xbf'), 'JSONL 不应有 BOM'
    lines = raw_bytes.decode('utf-8').rstrip('\n').split('\n')
    print('jsonl before', len(lines))

    name_index = []
    for c in reg['components']:
        nm = c['name']
        if c['type'] == 'FB':
            mks = ['FUNCTION_BLOCK ' + nm, 'FUNCTION ' + nm]
        elif c['type'] == 'FC':
            mks = ['FUNCTION ' + nm, 'FUNCTION_BLOCK ' + nm]
        else:
            mks = ['INTERFACE ' + nm]
        name_index.append((nm, mks))

    # 修正历史漂移（bytes 级重注入）
    drift_fixed = []
    for i, ln in enumerate(lines):
        d = json.loads(ln)
        nm = detect(d['output'], name_index)
        assert nm, 'line %d 无法归属组件' % (i + 1)
        c = next(x for x in reg['components'] if x['name'] == nm)
        p = os.path.join(LIB, c['category'], nm + '.st')
        b = read_bytes(p)
        if sha(d['output'].encode('utf-8')) != sha(b):
            d['output'] = b.decode('utf-8')
            lines[i] = json.dumps(d, ensure_ascii=False)
            drift_fixed.append(nm)
    print('drift fixed', len(drift_fixed), drift_fixed)

    # 追加 18 条
    for name in order:
        m = json.loads(read_text(os.path.join(META, name + '.json')))
        assert set(m.keys()) == {'instruction', 'architecture_thought'}, name
        c = next(x for x in reg['components'] if x['name'] == name)
        b = read_bytes(os.path.join(LIB, c['category'], name + '.st'))
        rec = {'instruction': m['instruction'],
               'architecture_thought': m['architecture_thought'],
               'output': b.decode('utf-8')}
        lines.append(json.dumps(rec, ensure_ascii=False))

    with open(JL, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('jsonl after', len(lines))

    # ---------- 全量硬校验 ----------
    chk = read_bytes(JL).decode('utf-8').rstrip('\n').split('\n')
    assert len(chk) == 186, len(chk)
    ok = 0
    bad = []
    for i, ln in enumerate(chk):
        d = json.loads(ln)
        assert set(d.keys()) == {'instruction', 'architecture_thought', 'output'}
        nm = detect(d['output'], name_index)
        assert nm, 'line %d 归属失败' % (i + 1)
        c = next(x for x in reg['components'] if x['name'] == nm)
        b = read_bytes(os.path.join(LIB, c['category'], nm + '.st'))
        if sha(d['output'].encode('utf-8')) == sha(b):
            ok += 1
        else:
            bad.append(nm)
    print('sha256 match %d/186, mismatch %d %s' % (ok, len(bad), bad))
    print('coverage names 186?', len({detect(json.loads(l)['output'], name_index) for l in chk}))

    # 落盘 json 供报告使用
    with open(os.path.join(STAGING, 'r12_register_result.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'before_total': before_total, 'before_counts': before_counts,
                   'after_total': reg['total_components'], 'version': reg['version'],
                   'last_updated': reg['last_updated'], 'counts': cnt,
                   'added': added, 'drift_fixed': drift_fixed,
                   'codes_spec': len(spec_all), 'codes_reg': len(reg_new),
                   'collision': sorted(collide), 'jsonl_rows': len(chk),
                   'sha_ok': ok, 'sha_bad': bad}, f, ensure_ascii=False, indent=2)
    print('DONE')


if __name__ == '__main__':
    main()
