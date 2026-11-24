# -*- coding: utf-8 -*-
"""R85 入队：ia2(Apache-2.0) process-control 五件，签名抽取 + 指纹去重 + 追加式写入"""
import json, sys, io, re, hashlib, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
Q = r'C:\Library\_Staging_Raw\2026-11-24\candidate_queue.jsonl'
FP = r'C:\Library\_Staging_Raw\_dedup_fingerprints.json'
files = json.load(open(r'C:\Library\_Staging_Raw\2026-11-24\r85\FREEZONEX_ia2_st.json', encoding='utf-8'))
by = {f['path']: f for f in files}
try:
    fps = json.load(open(FP, encoding='utf-8'))
    if isinstance(fps, dict): fps = fps
except Exception:
    fps = {}
fpset = set(fps.keys()) if isinstance(fps, dict) else set()

PICK = [
 ('library/process-control/pous/fb_rampsoak8.st', 'FB_RAMPSOAK8', 'A',
  '八段升温-保温(ramp/soak)曲线发生器：热处理炉/回火炉工艺曲线设定与相序推进', 2),
 ('library/process-control/pous/fb_deadtime8.st', 'FB_DEADTIME8', 'A',
  '八阶纯滞后(dead time)补偿器：淬火槽/加热炉测温大滞后回路的 Smith 预估算子', 2),
 ('library/process-control/pous/fb_interlock8.st', 'FB_INTERLOCK8', 'A',
  '八路联锁首出(first-out)记忆：炉温超温/急停联锁链的因果定位', 1),
 ('library/process-control/pous/fb_pid_3step.st', 'FB_PID_3STEP', 'C',
  '三步式(开/关/双向)执行器 PID：压铸模温机/燃烧器高低火位阶跃输出', 2),
 ('library/process-control/pous/fb_gain_sched3.st', 'FB_GAIN_SCHED3', 'A',
  '三区增益调度 PID：随负荷/温区切换增益表，适配升温段与保温段不同动态', 2),
]
def sig(txt):
    m = re.search(r'VAR_INPUT(.*?)END_VAR', txt, re.S | re.I)
    if not m: return ''
    out = []
    for ln in m.group(1).split('\n'):
        ln = ln.strip()
        if not ln or ln.startswith('//') or ln.startswith('(*'): continue
        ln = ln.split('//')[0].split('(')[0].strip()
        if ':' in ln:
            out.append(ln.replace('\t', ' '))
    return ', '.join(out)[:900]
rows = []
for path, name, fam, sem, pri in PICK:
    f = by.get(path)
    if not f:
        print('MISS', path); continue
    s = sig(f['text'])
    fp = hashlib.sha1((name.lower() + '|' + s).encode('utf-8')).hexdigest()[:16]
    row = {"name": name, "suggest_category": "DL_Process", "kind": "FB", "tier": "green",
           "license": "Apache-2.0", "source_url": "https://github.com/FREEZONEX/ia2/blob/HEAD/" + path,
           "commit": "HEAD(2026-11-24 codeload)", "extraction_point": name + " — " + path,
           "signature": "VAR_INPUT: " + s, "loc": f['loc'], "dialect": [],
           "defense_gaps": ["未做 NaN/除零输入闸（纯滞后/增益表除零）" if fam != 'C' else "三步输出未限最小步距，易抖动",
                            "无 ELOOP 兜底，环内自调用会溢出" if fam == 'A' else "未限斜坡速率上限"],
           "dedup": {"name": "pass", "fingerprint": "pass" if fp not in fpset else "dup", "semantic": "new"},
           "priority": pri, "family": fam, "fp": fp, "note": sem,
           "harvested_round": "R85", "status": "pending"}
    if fp in fpset:
        row['dup_flag'] = True
    rows.append(row)
    print('%-16s loc=%-4d fp=%s %s' % (name, f['loc'], fp, 'DUP' if fp in fpset else 'NEW'))

with open(Q, 'a', encoding='utf-8') as fh:
    for r in rows:
        fh.write(json.dumps(r, ensure_ascii=False) + '\n')
# 更新指纹库（只增）
if isinstance(fps, dict):
    for r in rows: fps[r['fp']] = {'name': r['name'], 'round': 'R85'}
    json.dump(fps, open(FP, 'w', encoding='utf-8'), ensure_ascii=False)
print('APPENDED', len(rows))
