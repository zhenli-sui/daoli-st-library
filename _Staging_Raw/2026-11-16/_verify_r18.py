import json, glob, re, os

NEW = ['FB_DL_FirstOutLatch', 'FB_DL_PulseStretch', 'FB_DL_EdgeDivider', 'FC_DL_BitSegmentBlockMove',
       'FC_DL_Crc16Ccitt', 'FC_DL_InterpolateTable2D', 'FC_DL_AffineTransformPoint', 'FC_DL_CpkIndex',
       'FB_DL_GainScheduler', 'FB_DL_BumplessTransfer', 'FB_DL_NotchFilter', 'FB_DL_ThermalI2tModel',
       'FB_DL_AxisFollowingErrorMonitor', 'FB_DL_AxisSynchronizedStop', 'FB_DL_BacklashCompensator',
       'I_DL_Gripper', 'FB_DL_ParallelGripper', 'FB_DL_SsrHeaterDrive',
       'FB_DL_DowntimeClassifier', 'FB_DL_ChangeoverSequence']

d = json.load(open('INDEX_REGISTRY.json', encoding='utf-8'))
reg = {c['name'] for c in d['components']}
files = {os.path.splitext(os.path.basename(p))[0] for p in glob.glob('DL_*/*.st')}
print('name dup vs registry:', [n for n in NEW if n in reg])
print('name dup vs files   :', [n for n in NEW if n in files])
print('unique count:', len(set(NEW)))

CAND = {}
# 0001_ (DL_Base / DL_MathData) 8 件 × (2 info + 3 fault)
c1 = []
for i in range(8):
    c1.append(('info', 0x0235 + 2 * i)); c1.append(('info', 0x0236 + 2 * i))
    for k in range(3):
        c1.append(('fault', 0x0306 + 3 * i + k))
CAND['0001'] = c1
# 0002_ DL_Algo 4 件：CC=23..26，info 01/02，fault 10/11/12
c2 = []
for cc in (0x23, 0x24, 0x25, 0x26):
    c2 += [(cc << 8) | 0x01, (cc << 8) | 0x02, (cc << 8) | 0x10, (cc << 8) | 0x11, (cc << 8) | 0x12]
CAND['0002'] = c2
# 0003_ DL_Device 2 件（第三件为接口无码）info 0166/0167/0168/0169, fault 032A..032F
CAND['0003'] = [0x0166, 0x0167, 0x0168, 0x0169, 0x032A, 0x032B, 0x032C, 0x032D, 0x032E, 0x032F]
# 0004_ DL_Motion 3 件
CAND['0004'] = [0x01C7, 0x01C8, 0x01C9, 0x01CA, 0x01CB, 0x01CC,
                0x02D5, 0x02D6, 0x02D7, 0x02D8, 0x02D9, 0x02DA, 0x02DB, 0x02DC, 0x02DD]
# 0005_ DL_Process 2 件
CAND['0005'] = [0x01D2, 0x01D3, 0x01D4, 0x01D5, 0x02FF, 0x0300, 0x0301, 0x0302, 0x0303, 0x0304]

for seg, lst in CAND.items():
    used = set()
    for f in glob.glob('DL_*/*.st'):
        t = open(f, encoding='utf-8', errors='ignore').read()
        for m in re.finditer('16#' + seg + '_([0-9A-Fa-f]{4})', t):
            used.add(int(m.group(1), 16))
    vals = [v[1] if isinstance(v, tuple) else v for v in lst]
    clash = sorted({hex(v) for v in vals if v in used})
    print('seg', seg, 'n=', len(vals), 'unique=', len(set(vals)), 'CLASH=', clash)
