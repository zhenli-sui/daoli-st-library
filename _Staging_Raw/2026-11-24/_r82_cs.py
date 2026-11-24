import json, os, subprocess, time, sys

TOK = open(r"C:\Library\_tools\.gh_token").read().strip()
OUT = r"C:\Library\_Staging_Raw\2026-11-24\_r82_codesearch.json"

QUERIES = [
    # family 1: floc/coag/clarify/settle/turbidity/SVI
    ('F1', 'clarifier extension:st OR flocculant extension:st OR turbidity extension:st'),
    ('F1', 'flocculant'),
    ('F1', 'SVI OR "sludge volume index"'),
    # family 2: sludge dewatering
    ('F2', 'centrifuge extension:st OR "screw press" OR dewatering'),
    ('F2', '"polymer dosing" OR "cake solids" OR filtrate'),
    # family 3: scrubber / catalytic / stack
    ('F3', 'scrubber OR "packed bed" OR demister'),
    ('F3', 'venturi OR "reagent dosing" OR "stack"'),
    # family 4: maintenance / RUL / PM
    ('F4', 'MTBF OR "mean time between" OR "remaining useful life"'),
    ('F4', '"oil change" OR "bearing temperature" OR "preventive maintenance"'),
    # family 5: biogas / anaerobic
    ('F5', 'biogas OR methane OR "gas holder" OR flare'),
    ('F5', '"anaerobic" OR VFA OR alkalinity OR OLR'),
]


def cs(q, per_page=30):
    url = "https://api.github.com/search/code?q=%s&per_page=%d" % (
        subprocess.run(['python', '-c', 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))', q],
                       capture_output=True, text=True).stdout.strip(), per_page)
    r = subprocess.run(['curl', '-s', '--max-time', '30', '-H', 'Authorization: Bearer ' + TOK,
                        '-H', 'Accept: application/vnd.github+json', url],
                       capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"_raw": r.stdout[:200]}


results = {}
allrepo = {}
for fam, q in QUERIES:
    d = cs(q)
    if 'items' not in d:
        print("ERR", fam, q, str(d)[:160], flush=True)
        time.sleep(7)
        continue
    print("OK", fam, "|", q, "->", d.get('total_count'), flush=True)
    for it in d['items']:
        rp = it['repository']['full_name']
        allrepo.setdefault(rp, {'fam': set(), 'files': [], 'hits': 0})
        allrepo[rp]['fam'].add(fam)
        allrepo[rp]['hits'] += 1
        if len(allrepo[rp]['files']) < 5:
            allrepo[rp]['files'].append(it['path'])
    time.sleep(6.5)

for k in allrepo:
    allrepo[k]['fam'] = sorted(allrepo[k]['fam'])

json.dump(allrepo, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print("\n=== REPOS ===", len(allrepo))
for rp, v in sorted(allrepo.items(), key=lambda x: -x[1]['hits']):
    print("%3d %-6s %s  %s" % (v['hits'], ','.join(v['fam']), rp, v['files'][:2]))
