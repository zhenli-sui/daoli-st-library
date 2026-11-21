# -*- coding: utf-8 -*-
"""R13 注册登记与语料落库：18 件新增 + 存量 2 条再同步 + 全量 204 条 sha256 真验。

纪律：
- 只允许改 INDEX_REGISTRY.json / JSONL / 本脚本 / REGISTRY_JSONL_R13.md
- 既有 186 条注册字段零改动；JSONL 仅允许为再同步而重注入 output
- output 一律 bytes 级读取 .st 后 decode('utf-8')，保证 encode 回去 sha256 相等
"""
import json
import os
import re
import hashlib
from datetime import datetime, timedelta, timezone

LIB = r'C:\Library'
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
JL = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
STAGING = os.path.join(LIB, '_Staging_Raw', '2026-11-15')
META = os.path.join(STAGING, 'meta')

CATS = ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']

# 名称 -> (category, type, complexity, version, 必含来源组标签, 追加功能标签)
ITEMS = {
    'I_DL_DeviceHealth':            ('DL_Device', 'IF', 4, '1.0.0', ['namur-ne107'], []),
    'I_DL_PowerMeter':              ('DL_Device', 'IF', 4, '1.0.0', ['namur-ne107', 'forge-devicereader'], []),
    'FB_DL_ModbusPowerMeter':       ('DL_Device', 'FB', 9, '1.0.1', ['namur-ne107', 'modbus-meter'], []),
    'FB_DL_ValveStictionDetect':    ('DL_Device', 'FB', 9, '1.0.1', ['namur-ne107', 'stiction-diag'], []),
    'FB_DL_AhuDamperStuckDiag':     ('DL_Device', 'FB', 8, '1.0.1', ['rockwell-aoi', 'namur-ne107'], []),
    'FB_DL_PumpCavitationGuard':    ('DL_Device', 'FB', 8, '1.0.1', ['namur-ne107', 'lbp-basic-process'], []),
    'FC_DL_BitArrayRotate':         ('DL_Base', 'FC', 5, '1.0.0', ['lgf-bitlogic'], []),
    'FC_DL_MaskCompare':            ('DL_Base', 'FC', 4, '1.0.0', ['lgf-bitlogic', 'lgf-comparator'], []),
    'FC_DL_Crc8':                   ('DL_MathData', 'FC', 5, '1.0.0', ['lgf-datahandling', 'oscat-network'], []),
    'FC_DL_StringToLReal':          ('DL_MathData', 'FC', 8, '1.0.0', ['lgf-datahandling'], []),
    'FC_DL_StringFixedField':       ('DL_MathData', 'FC', 5, '1.0.0', ['lgf-datahandling'], []),
    'FC_DL_Matrix3Inverse':         ('DL_MathData', 'FC', 7, '1.0.1', ['lgf-math'], []),
    'FB_DL_FoulingResistanceEstimator': ('DL_Algo', 'FB', 7, '1.0.0', ['oscat-building', 'heat-transfer'], []),
    'FB_DL_PassiveHomingMonitor':   ('DL_Motion', 'FB', 7, '1.0.1', ['plcopen-motion'], []),
    'FB_DL_CapperTorqueTrend':      ('DL_Process', 'FB', 8, '1.0.1', ['rockwell-aoi', 'lbp-process'], []),
    'FB_DL_EscHeLeakCheck':         ('DL_Process', 'FB', 8, '1.0.1', ['semiconductor-esc'], []),
    'FB_DL_ChamberSeasoningTrack':  ('DL_Process', 'FB', 7, '1.0.0', ['semiconductor-esc', 'isa-88'], []),
    'FB_DL_ReactorJacketDeltaT':    ('DL_Process', 'FB', 8, '1.0.0', ['lbp-process', 'isa-88'], []),
}
ORDER = list(ITEMS.keys())

# 名称 -> (信息级码位, 故障级码位)，来自三份终审报告；脚本会与源码实扫集合互验
SEG = {
    'FB_DL_ModbusPowerMeter':       ('16#0003_0156~015B', '16#0003_0316~031B'),
    'FB_DL_ValveStictionDetect':    ('16#0003_015C~015E', '16#0003_031D~031F'),
    'FB_DL_AhuDamperStuckDiag':     ('16#0003_0160~0161', '16#0003_0321~0325'),
    'FB_DL_PumpCavitationGuard':    ('16#0003_0164~0165', '16#0003_0326~0329'),
    'FC_DL_BitArrayRotate':         ('16#0001_013D~013E', '16#0001_021F'),
    'FC_DL_MaskCompare':            ('16#0001_013F~0140', '16#0001_0220'),
    'FC_DL_Crc8':                   ('16#0001_0141~0142', '16#0001_0221'),
    'FC_DL_StringToLReal':          ('16#0001_0143~0146', '16#0001_0222~0223'),
    'FC_DL_StringFixedField':       ('16#0001_0147~0149', '16#0001_0224'),
    'FC_DL_Matrix3Inverse':         ('16#0001_014A~014C', '16#0001_0225'),
    'FB_DL_FoulingResistanceEstimator': ('16#0002_2201~2204', '16#0002_2210~2212'),
    'FB_DL_PassiveHomingMonitor':   ('16#0004_01C3~01C6', '16#0004_02D2~02D4'),
    'FB_DL_CapperTorqueTrend':      ('16#0005_01C5~01C7', '16#0005_02F3~02F5'),
    'FB_DL_EscHeLeakCheck':         ('16#0005_01C8~01CA', '16#0005_02F6~02F8'),
    'FB_DL_ChamberSeasoningTrack':  ('16#0005_01CB~01CE', '16#0005_02F9~02FB'),
    'FB_DL_ReactorJacketDeltaT':    ('16#0005_01CF~01D1', '16#0005_02FC~02FE'),
}
NO_SEG = {'I_DL_DeviceHealth', 'I_DL_PowerMeter'}

# 存量再同步（本轮终审与 R39 修复改动的已注册件，均升 v1.0.1）
RESYNC = {'FB_DL_InterlockMatrix', 'FB_DL_AgvDockingHandshake'}


def sha(b):
    return hashlib.sha256(b).hexdigest()


def read_bytes(p):
    with open(p, 'rb') as f:
        return f.read()


def read_text(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def expand_seg(s):
    """'16#0003_0156~015B' -> 集合。"""
    out = set()
    for part in s.split(' / '):
        m = re.match(r'16#([0-9A-F]{4})_([0-9A-F]{4})(?:~([0-9A-F]{4}))?$', part)
        hi, lo = m.group(1), int(m.group(2), 16)
        end = int(m.group(3), 16) if m.group(3) else lo
        for c in range(lo, end + 1):
            out.add((hi, c))
    return out


def scan_codes(txt, hi_expect):
    """实扫文件内 16#XXXX_YYYY 诊断码（限家族前缀，低位域 0x0100~0x2FFF）。"""
    pat = re.compile(r'16#([0-9A-Fa-f]{4})_([0-9A-Fa-f]{4})')
    out = set()
    for hi, lo in pat.findall(txt):
        if hi.upper() != hi_expect:
            continue
        v = int(lo, 16)
        if 0x0100 <= v <= 0x2FFF:
            out.add((hi.upper(), v))
    return out


def build_code_segment(name):
    """由终审报告码位构建 code_segment 字符串，并与源码实扫互验。"""
    info, fault = SEG[name]
    cat = ITEMS[name][0]
    exp = expand_seg(info) | expand_seg(fault)
    txt = read_text(os.path.join(LIB, cat, name + '.st'))
    got = scan_codes(txt, next(iter(exp))[0])
    assert got == exp, (name, 'report-only', sorted(exp - got), 'file-only', sorted(got - exp))
    return '%s(信息级) / %s(故障级)' % (info, fault)


def detect(out, name_index):
    """返回 output 归属的组件名；多命中时取最长名（防止前缀包含）。"""
    hits = [n for n, mks in name_index if any(mk in out for mk in mks)]
    if not hits:
        return None
    return max(hits, key=len)


def main():
    now = datetime.now(timezone.utc).astimezone()

    # ---------- 注册表 ----------
    reg = json.loads(read_text(REG))
    before_total = reg['total_components']
    before_counts = dict(reg['counts'])
    names = [c['name'] for c in reg['components']]
    assert len(names) == before_total == 186, (len(names), before_total)
    assert len(set(names)) == 186
    assert reg['version'] == '2.1.0'
    existing_snapshot = json.dumps(reg['components'], ensure_ascii=False, sort_keys=True)

    added = []
    for k, name in enumerate(ORDER):
        cat, typ, cx, ver, src_tags, extra_tags = ITEMS[name]
        assert name not in names, 'dup ' + name
        assert cat in CATS
        path = os.path.join(LIB, cat, name + '.st')
        assert os.path.isfile(path), path
        # function_tags：meta 既有标签 + 必含来源组标签（来源组在前，去重保序）
        meta = json.loads(read_text(os.path.join(META, name + '.json')))
        tags = list(src_tags)
        for t in meta.get('function_tags', []):
            if t not in tags:
                tags.append(t)
        assert all(s in tags for s in src_tags), (name, tags)
        lc = read_bytes(path).decode('utf-8').count('\n') + (
            0 if read_bytes(path).endswith(b'\n') else 1)
        cs = '无（接口契约不发布故障码，码位由实现块承担）' if name in NO_SEG else build_code_segment(name)
        ts = (now + timedelta(seconds=3 * k)).replace(microsecond=0).isoformat()
        reg['components'].append({
            'name': name,
            'category': cat,
            'type': typ,
            'file_path': path,
            'function_tags': tags,
            'complexity': cx,
            'version': ver,
            'registered_at': ts,
            'line_count': lc,
            'code_segment': cs,
            'source': src_tags[0],
        })
        added.append({'name': name, 'category': cat, 'type': typ, 'version': ver,
                      'line_count': lc, 'code_segment': cs, 'source': src_tags[0],
                      'complexity': cx, 'tags': tags, 'registered_at': ts})

    reg['total_components'] = len(reg['components'])
    reg['version'] = '2.2.0'
    reg['last_updated'] = now.replace(microsecond=0).isoformat()
    cnt = {c: 0 for c in CATS}
    for c in reg['components']:
        cnt[c['category']] = cnt.get(c['category'], 0) + 1
    reg['counts'] = cnt
    expect_counts = {'DL_Base': 40, 'DL_MathData': 42, 'DL_Algo': 28,
                     'DL_Device': 50, 'DL_Motion': 18, 'DL_Process': 26}
    assert cnt == expect_counts, cnt

    # 既有条目零改动断言
    assert json.dumps(reg['components'][:186], ensure_ascii=False, sort_keys=True) == existing_snapshot

    with open(REG, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(reg, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print('registry: total', reg['total_components'], 'ver', reg['version'], 'counts', cnt)

    # ---------- JSONL ----------
    raw_bytes = read_bytes(JL)
    assert not raw_bytes.startswith(b'\xef\xbb\xbf'), 'JSONL 不应有 BOM'
    lines = raw_bytes.decode('utf-8').rstrip('\n').split('\n')
    assert len(lines) == 186, len(lines)

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

    # 存量再同步：漂移检测全量跑；点名的 2 件必须漂移，额外漂移件（历史遗留注释级未回写）一并重注入并留痕
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
    assert not (RESYNC - set(drift_fixed)), '点名再同步件未出现漂移（.st 与 JSONL 已一致？）: %s' % (RESYNC - set(drift_fixed))
    print('drift fixed', len(drift_fixed), drift_fixed)

    # 追加 18 条
    for name in ORDER:
        m = json.loads(read_text(os.path.join(META, name + '.json')))
        assert m.get('instruction') and m.get('architecture_thought'), name
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
    assert len(chk) == 204, len(chk)
    ok = 0
    bad = []
    seen = set()
    for i, ln in enumerate(chk):
        d = json.loads(ln)
        assert set(d.keys()) == {'instruction', 'architecture_thought', 'output'}
        nm = detect(d['output'], name_index)
        assert nm, 'line %d 归属失败' % (i + 1)
        seen.add(nm)
        c = next(x for x in reg['components'] if x['name'] == nm)
        b = read_bytes(os.path.join(LIB, c['category'], nm + '.st'))
        if sha(d['output'].encode('utf-8')) == sha(b):
            ok += 1
        else:
            bad.append(nm)
    print('sha256 match %d/204, mismatch %d %s' % (ok, len(bad), bad))
    assert ok == 204 and not bad
    print('coverage names %d (expect 204)' % len(seen))
    assert len(seen) == 204, '有组件未被覆盖'

    # 磁盘 .st 数与 counts 互验
    disk = {c: 0 for c in CATS}
    for d in CATS:
        disk[d] = len([f for f in os.listdir(os.path.join(LIB, d)) if f.endswith('.st')])
    assert disk == expect_counts, disk
    print('disk .st counts', disk)

    # 落盘 json 供报告使用
    with open(os.path.join(STAGING, 'r13_register_result.json'), 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'before_total': before_total, 'before_counts': before_counts,
                   'after_total': reg['total_components'], 'version': reg['version'],
                   'last_updated': reg['last_updated'], 'counts': cnt,
                   'added': added, 'resync_fixed': sorted(drift_fixed),
                   'jsonl_rows': len(chk), 'sha_ok': ok, 'sha_bad': bad,
                   'disk_counts': disk}, f, ensure_ascii=False, indent=2)
    print('DONE')


if __name__ == '__main__':
    main()
