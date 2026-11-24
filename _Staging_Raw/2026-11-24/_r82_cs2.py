import json, subprocess, time, urllib.parse

TOK = open(r"C:\Library\_tools\.gh_token").read().strip()
OUT = r"C:\Library\_Staging_Raw\2026-11-24\_r82_codesearch2.json"

# (family, keyword, extension)
Q = []
for fam, kws in [
    ('F1', ['sludge', 'clarifier', 'flocculant', 'coagulant', 'turbidity', 'settling']),
    ('F2', ['centrifuge', 'dewatering', 'polymer', 'filtrate']),
    ('F3', ['scrubber', 'demister', 'catalyst', 'venturi', 'reagent']),
    ('F4', ['maintenance', 'vibration', 'MTBF', 'lubrication']),
    ('F5', ['biogas', 'methane', 'digester', 'alkalinity']),
]:
    for k in kws:
        for ext in ['st', 'TcPOU']:
            Q.append((fam, k, ext))


def run(q):
    url = "https://api.github.com/search/code?q=" + urllib.parse.quote(q) + "&per_page=40"
    r = subprocess.run(['curl', '-s', '--max-time', '30', '-H', 'Authorization: Bearer ' + TOK,
                        '-H', 'Accept: application/vnd.github+json', url], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"_raw": r.stdout[:200]}


allrepo = {}
done = 0
for fam, k, ext in Q:
    q = '%s extension:%s' % (k, ext)
    d = run(q)
    if 'items' not in d:
        print('ERR', q, str(d)[:100], flush=True)
        time.sleep(8)
        continue
    n = d.get('total_count', 0)
    print('OK %-3s %-12s %-6s -> %s' % (fam, k, ext, n), flush=True)
    for it in d['items']:
        rp = it['repository']['full_name']
        e = allrepo.setdefault(rp, {'fam': set(), 'files': [], 'hits': 0})
        e['fam'].add(fam); e['hits'] += 1
        if len(e['files']) < 8:
            e['files'].append(it['path'])
    done += 1
    time.sleep(6.5)

for k in allrepo:
    allrepo[k]['fam'] = sorted(allrepo[k]['fam'])
json.dump(allrepo, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('\nQUERIES_RUN', done, 'REPOS', len(allrepo))
for rp, v in sorted(allrepo.items(), key=lambda x: -x[1]['hits'])[:35]:
    print('%3d %-6s %-55s %s' % (v['hits'], ','.join(v['fam']), rp, v['files'][:1]))
