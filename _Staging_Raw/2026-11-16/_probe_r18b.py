import json, re, glob, os, collections

CAT = ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']
d = json.load(open('INDEX_REGISTRY.json', encoding='utf-8'))
names = {c['name'] for c in d['components']}

# 每类实际使用的 (seg) 分布
for cat in CAT:
    segs = collections.Counter()
    used = collections.defaultdict(set)
    files = glob.glob(cat + '/*.st')
    for f in files:
        t = open(f, encoding='utf-8', errors='ignore').read()
        for m in re.finditer(r'16#([0-9A-Fa-f]{4})_([0-9A-Fa-f]{4})', t):
            s = m.group(1).upper(); v = int(m.group(2), 16)
            segs[s] += 1
            used[s].add(v)
    print('==', cat, 'files', len(files), 'segments', dict(segs))
    for s in sorted(used):
        vs = used[s]
        print('   seg', s, 'count', len(vs), 'min', hex(min(vs)), 'max', hex(max(vs)))

def ranges(lst):
    out = []; s = None; p = None
    for x in lst:
        if s is None:
            s = p = x
        elif x == p + 1:
            p = x
        else:
            out.append((s, p)); s = p = x
    if s is not None:
        out.append((s, p))
    return out

print()
for cat, seg, lo, hi in [('DL_Algo', '0002', 0x0200, 0x0900),
                         ('DL_Device', '0003', 0x0200, 0x0900),
                         ('DL_Motion', '0004', 0x0200, 0x0900),
                         ('DL_Process', '0005', 0x0200, 0x0900)]:
    used = set()
    for f in glob.glob(cat + '/*.st'):
        t = open(f, encoding='utf-8', errors='ignore').read()
        for m in re.finditer(r'16#' + seg + r'_([0-9A-Fa-f]{4})', t):
            used.add(int(m.group(1), 16))
    free = [i for i in range(lo, hi) if i not in used]
    print(cat, seg, 'free ranges in', hex(lo), '-', hex(hi), ':', [(hex(a), hex(b)) for a, b in ranges(free)][:14])
