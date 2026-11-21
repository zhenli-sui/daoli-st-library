import glob, re, collections

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

for cat, seg in [('DL_Algo', '0002'), ('DL_Device', '0003'), ('DL_Motion', '0004'), ('DL_Process', '0005')]:
    used = set()
    for f in glob.glob(cat + '/*.st'):
        t = open(f, encoding='utf-8', errors='ignore').read()
        for m in re.finditer(r'16#' + seg + r'_([0-9A-Fa-f]{4})', t):
            v = int(m.group(1), 16)
            if v != 0:
                used.add(v)
    info = sorted(v for v in used if 0x100 <= v < 0x200)
    flt = sorted(v for v in used if 0x200 <= v < 0x400)
    print('==', cat, seg)
    print('   info(01xx) used n=%d max=%s ; free tail ranges:' % (len(info), hex(info[-1]) if info else '-'),
          [(hex(a), hex(b)) for a, b in ranges([i for i in range(0x100, 0x200) if i not in used])][-6:])
    print('   fault(02xx-03xx) used n=%d max=%s ; free tail ranges:' % (len(flt), hex(flt[-1]) if flt else '-'),
          [(hex(a), hex(b)) for a, b in ranges([i for i in range(0x200, 0x400) if i not in used])][-6:])
