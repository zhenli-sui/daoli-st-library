import json, os, glob, datetime
now = datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S+08:00')
QZ = 'FB_DL_CoilTaperTensionSeq'
targets = json.load(open(r'C:\Library\_Staging_Raw\2026-11-25\r89_targets.json', encoding='utf-8'))

disk = {}
for p in glob.glob(r'C:\Library\DL_*\*.st'):
    base = os.path.basename(p)[:-3]
    cat = os.path.basename(os.path.dirname(p))
    disk[base] = (cat, p)

for t in targets:
    if t['name'] in disk and t['name'] != QZ:
        t['cat'] = disk[t['name']][0]
json.dump(targets, open(r'C:\Library\_Staging_Raw\2026-11-25\r89_targets.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

reg = json.load(open(r'C:\Library\INDEX_REGISTRY.json', encoding='utf-8'))
have = set(c['name'] for c in reg['components'])
added = []
for t in targets:
    n = t['name']
    if n == QZ:
        continue
    if n in have:
        continue
    if n not in disk:
        print('MISSING', n)
        continue
    cat, p = disk[n]
    typ = 'FB' if n.startswith('FB') else 'FC'
    cx = int(t['cx'][1:])
    if t['i'] <= 9:
        tag = 'a'
    elif t['i'] <= 18:
        tag = 'b'
    elif t['i'] <= 27:
        tag = 'c'
    elif t['i'] <= 36:
        tag = 'd'
    else:
        tag = 'e'
    reg['components'].append({
        "name": n, "category": cat, "type": typ, "file_path": p,
        "function_tags": [cat.lower().replace('dl_', ''), "vertical-process", "r89", "fam" + tag, "l2-pass"],
        "complexity": cx, "registered_at": now,
        "origin": {"mode": "internal", "source": "道莅原创（clean-room 自研，依据公开工艺公式）",
                   "license": "MIT", "ref_tag": "R89"},
        "version": "1.0.0", "l2_status": "l2-pass", "qa_status": "pass", "function": t['func']})
    added.append([n, cat, cx, t['func']])

reg['counts'] = {}
for c in reg['components']:
    reg['counts'][c['category']] = reg['counts'].get(c['category'], 0) + 1
reg['total_components'] = len(reg['components'])
reg['version'] = 'v2.81.0'
reg['last_updated'] = now
assert sum(reg['counts'].values()) == reg['total_components']
json.dump(reg, open(r'C:\Library\INDEX_REGISTRY.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('added', len(added), 'total', reg['total_components'], reg['counts'])
json.dump(added, open(r'C:\Library\_Staging_Raw\2026-11-25\r89_added.json', 'w', encoding='utf-8'), ensure_ascii=False)
