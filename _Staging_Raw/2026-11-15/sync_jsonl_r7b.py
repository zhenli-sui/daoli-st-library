# -*- coding: utf-8 -*-
"""R7b: JSONL 字节级再同步——16 条 R7 组件 output 用当前 .st 文件重注入。"""
import json, hashlib, shutil, io

REG = 'C:/Library/INDEX_REGISTRY.json'
ST_ROOT = 'C:/Library/'
JSONL = 'C:/Library/_AI_Training_Dataset/daoli_st_sft_dataset.jsonl'
BAK = JSONL + '.backup_R7b'

# 1) 备份
shutil.copyfile(JSONL, BAK)
print('backup ->', BAK)

# 2) R7 16 条（registered_at=2026-11-15T08:36:23+08:00）
reg = json.load(open(REG, encoding='utf-8'))
r7 = [c for c in reg['components'] if c['registered_at'] == '2026-11-15T08:36:23+08:00']
assert len(r7) == 16, len(r7)
name2path = {c['name']: c['file_path'].replace('\\', '/') for c in r7}

# 3) 读 JSONL，按 POU 头匹配行
raw = open(JSONL, encoding='utf-8', newline='').read()
lines = raw.splitlines()
assert len(lines) == 104, len(lines)

def pou_of(out):
    for l in out.splitlines():
        s = l.strip()
        if s.startswith(('FUNCTION_BLOCK ', 'INTERFACE ')):
            # FUNCTION_BLOCK FB_DL_Xxx / INTERFACE I_DL_Xxx
            tok = s.split()[1]
            return tok
    return None

changed = []
for i, l in enumerate(lines):
    j = json.loads(l)
    pou = pou_of(j['output'])
    if pou in name2path:
        new_out = open(name2path[pou], 'r', encoding='utf-8', newline='').read()
        if j['output'] != new_out:
            changed.append((i + 1, pou, len(j['output']), len(new_out)))
        j['output'] = new_out
        lines[i] = json.dumps(j, ensure_ascii=False)

print('changed outputs:', len(changed))
for c in changed:
    print('  line %d %s  %d -> %d bytes' % c)

# 4) 写回（UTF-8 无 BOM，\n 行结束）
with io.open(JSONL, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(lines) + '\n')

# 5) 校验：104 条合法 JSON + output sha256 与源码一致
ok = 0
for i, l in enumerate(open(JSONL, encoding='utf-8').read().splitlines()):
    j = json.loads(l)  # 合法性
    pou = pou_of(j['output'])
    if pou in name2path:
        src = open(name2path[pou], 'rb').read()
        out = j['output'].encode('utf-8')
        assert hashlib.sha256(src).hexdigest() == hashlib.sha256(out).hexdigest(), 'MISMATCH %d %s' % (i + 1, pou)
        ok += 1
print('verified %d/16 byte-identical, 104 lines all valid JSON' % ok)
# BOM 检查
head = open(JSONL, 'rb').read(3)
print('BOM:', head == b'\xef\xbb\xbf')
