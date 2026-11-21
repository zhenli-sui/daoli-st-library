# -*- coding: utf-8 -*-
"""R11 注册登记与训练集同步：16 件新增 + 7 件存量修复件 output 重注入。"""
import json
import os

REG = 'INDEX_REGISTRY.json'
JL = '_AI_Training_Dataset/daoli_st_sft_dataset.jsonl'
META = '_Staging_Raw/2026-11-15/meta'
LIB = r'C:\Library'

SPEC = [
    ("FB_DL_PressFitStation", "DL_Process", ["lbp-process", "plcopen-motion", "isa-88", "press-fit", "state-machine"], "16#0005_01C0~01C1(信息级) / 16#0005_02C0~02C3(故障级)", "lbp-process"),
    ("FB_DL_RotaryIndexTable", "DL_Process", ["packml-omac", "lgf-bitlogic", "indexing-table", "station-scheduling", "state-machine"], "16#0005_01C2(信息级) / 16#0005_02D0~02D3(故障级)", "packml-omac"),
    ("FB_DL_AgvDockingHandshake", "DL_Process", ["packml-omac", "isa-88", "lbp-process", "agv-handshake", "state-machine"], "16#0005_01C3(信息级) / 16#0005_02E0~02E4(故障级)", "packml-omac"),
    ("FB_DL_EnergySavingMode", "DL_Process", ["isa-88", "lbp-process", "namur-ne43", "energy-saving", "state-machine"], "16#0005_01C4(信息级) / 16#0005_02F0~02F2(故障级)", "isa-88"),
    ("FB_DL_PortDiagAggregator", "DL_Device", ["plcnext-community", "profinet-diag", "port-diagnostics", "first-out", "state-machine"], "16#0003_0140~0141(信息级) / 16#0003_0300~0301,0307(故障级)", "plcnext-community"),
    ("FB_DL_StatusWordSegDecoder", "DL_Device", ["lgf-bitlogic", "rockwell-aoi", "bit-segment", "status-word", "table-driven"], "16#0003_0142~0144(信息级) / 16#0003_0302(故障级)", "lgf-bitlogic"),
    ("FB_DL_NtcTempScan", "DL_Device", ["rockwell-aoi", "oscat-building", "temperature", "multi-channel", "device-level"], "16#0003_0145~0146(信息级) / 16#0003_0303~0304(故障级)", "rockwell-aoi"),
    ("FB_DL_RollerGapAdjust", "DL_Device", ["rockwell-aoi", "lbp-process", "servo-adjust", "backlash", "state-machine"], "16#0003_0147~0148(信息级) / 16#0003_0305~0306,0308(故障级)", "lbp-process"),
    ("FB_DL_YearWindowCheck", "DL_Base", ["lgf-datetime", "calendar", "year-window", "state-machine"], "16#0001_011E~011F(信息级)", "lgf-datetime"),
    ("FB_DL_RolloverCounter", "DL_Base", ["lgf-counter", "wrap-around", "counting", "state-machine"], "16#0001_0120(信息级) / 16#0001_0218(故障级)", "lgf-counter"),
    ("FC_DL_RangeOverlapCheck", "DL_MathData", ["lgf-comparator", "interval", "geometry", "pure-function"], "16#0001_0121(信息级)", "lgf-comparator"),
    ("FC_DL_CalcDistance3D", "DL_MathData", ["lgf-math", "geometry", "distance", "pure-function"], "16#0001_0122(信息级) / 16#0001_0219(故障级)", "lgf-math"),
    ("FC_DL_RandomNext", "DL_MathData", ["lgf-math", "prng", "deterministic", "pure-function"], "16#0001_0123(信息级)", "lgf-math"),
    ("FC_DL_PercentileLReal", "DL_MathData", ["lgf-math", "statistics", "percentile", "pure-function"], "16#0001_0124 / 16#0002_000E(信息级)", "lgf-math"),
    ("FB_DL_R2rEwmaTuner", "DL_Algo", ["semiconductor-apc", "lgf-math", "ewma", "run-to-run", "state-machine"], "16#0002_1F01~1F03(信息级) / 16#0002_1F10(故障级)", "semiconductor-apc"),
    ("FB_DL_WindingTensionCtrl", "DL_Motion", ["lgf-technology", "s7-motion", "tension-control", "taper", "state-machine"], "16#0004_01C0~01C2(信息级) / 16#0004_02D0~02D1(故障级)", "lgf-technology"),
]

REPAIRED = {
    "FB_DL_PneumaticCylinder": "DL_Device",
    "FB_DL_SingleSolenoidCyl": "DL_Device",
    "FC_DL_QuickSortLReal": "DL_MathData",
    "I_DL_AnalogSensor": "DL_Device",
    "I_DL_FlowMeter": "DL_Device",
    "FB_DL_AxisRelativeMove": "DL_Motion",
    "FB_DL_LeakTestStation": "DL_Process",
}


def complexity(n):
    if n <= 230:
        return 4
    if n <= 360:
        return 5
    if n <= 430:
        return 6
    if n <= 500:
        return 7
    if n <= 560:
        return 8
    return 9


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def main():
    now = '2026-11-15T17:55:00+08:00'
    reg = json.loads(read(REG))
    names = {c['name'] for c in reg['components']}
    added = []
    for name, cat, tags, seg, src in SPEC:
        path = os.path.join(LIB, cat, name + '.st')
        assert os.path.isfile(path), path
        assert name not in names, 'duplicate: ' + name
        n = len(read(path).splitlines())
        reg['components'].append({
            "name": name, "category": cat, "type": name[:2],
            "file_path": path, "function_tags": tags,
            "complexity": complexity(n), "registered_at": now,
            "code_segment": seg, "source": src,
        })
        added.append((name, cat, n))
    reg['total_components'] = len(reg['components'])
    reg['version'] = '2.0.0'
    reg['last_updated'] = now
    cnt = {}
    for c in reg['components']:
        cnt[c['category']] = cnt.get(c['category'], 0) + 1
    reg['counts'] = cnt
    with open(REG, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(reg, f, ensure_ascii=False, indent=2)
    print('registry ->', reg['total_components'], cnt, 'v', reg['version'])

    raw = read(JL).rstrip('\n').split('\n')
    before = len(raw)
    print('jsonl before', before)

    resynced = []
    for i, ln in enumerate(raw):
        d = json.loads(ln)
        out = d['output']
        hit = None
        for nm, cat in REPAIRED.items():
            if ('FUNCTION_BLOCK ' + nm) in out or ('FUNCTION ' + nm) in out or ('INTERFACE ' + nm) in out:
                hit = (nm, cat)
                break
        if hit:
            src_text = read(os.path.join(LIB, hit[1], hit[0] + '.st'))
            if src_text != out:
                d['output'] = src_text
                raw[i] = json.dumps(d, ensure_ascii=False)
                resynced.append(hit[0])
    print('resynced', resynced)

    for name, cat, n in added:
        m = json.loads(read(os.path.join(META, name + '.json')))
        src_text = read(os.path.join(LIB, cat, name + '.st'))
        rec = {"instruction": m['instruction'], "architecture_thought": m['architecture_thought'], "output": src_text}
        raw.append(json.dumps(rec, ensure_ascii=False))
    with open(JL, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(raw) + '\n')
    print('jsonl after', len(raw), 'added', len(added))


if __name__ == '__main__':
    main()
