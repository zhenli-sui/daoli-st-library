# -*- coding: utf-8 -*-
"""R38 增量验收：registry / 磁盘 / JSONL 三向 + 新增行 sha256 字节比对 + badjson 计数"""
import io, os, json, glob, hashlib, collections

LIB = 'C:/Library'
STAGE = os.path.join(LIB, '_Staging_Raw', '2026-11-18')
targets = [x[1] for x in json.load(io.open(os.path.join(STAGE, 'targets_r38.json'), encoding='utf-8'))]

reg = json.load(io.open(os.path.join(LIB, 'INDEX_REGISTRY.json'), encoding='utf-8'))
names = [c['name'] for c in reg['components']]
disk = [os.path.splitext(os.path.basename(f))[0] for f in glob.glob(os.path.join(LIB, 'DL_*', '*.st'))]

print('REG', reg['total_components'], 'COMP', len(names), 'DISK', len(disk), 'JSONL',
      sum(1 for _ in io.open(os.path.join(LIB, '_AI_Training_Dataset/daoli_st_sft_dataset.jsonl'), encoding='utf-8')))
print('COUNTS', dict(collections.Counter(c['category'] for c in reg['components'])))

missing = [n for n in targets if n not in names]
print('TARGETS_MISSING_IN_REG', missing)

# JSONL 校验
bad, match, total, seen = 0, 0, 0, collections.Counter()
outmap = {}
for ln in io.open(os.path.join(LIB, '_AI_Training_Dataset/daoli_st_sft_dataset.jsonl'), encoding='utf-8'):
    total += 1
    if not ln.strip():
        continue
    try:
        d = json.loads(ln)
    except Exception:
        bad += 1
        continue
    out = d.get('output', '')
    seen[hashlib.sha256(out.encode('utf-8')).hexdigest()[:12]] += 1
    outmap[hashlib.sha256(out.encode('utf-8')).hexdigest()[:12]] = len(out)
print('JSONL_TOTAL', total, 'BADJSON', bad)

# 新 20 行是否与磁盘字节一致
ok = 0
for n in targets:
    f = None
    for c in reg['components']:
        if c['name'] == n:
            f = c['file_path']
            break
    if not f or not os.path.exists(f):
        print('SKIP', n)
        continue
    src = io.open(f, encoding='utf-8').read()
    h = hashlib.sha256(src.encode('utf-8')).hexdigest()[:12]
    if h in outmap:
        ok += 1
    else:
        print('JSONL_MISMATCH', n)
print('JSONL_BYTE_MATCH %d/%d' % (ok, len(targets)))

# CRLF 检查
badcrlf = [n for n in targets for f in [glob.glob(os.path.join(LIB, 'DL_*', n + '.st'))]
           if f and b'\r\n' not in io.open(f[0], 'rb').read()]
print('NOT_CRLF', badcrlf)
