import json,re,collections
d=json.load(open('INDEX_REGISTRY.json',encoding='utf-8'))
names=[x['name'] for x in d['components']]
def split(n):
    s=re.sub(r'^(FB_DL_|FC_DL_|I_DL_|ST_DL_|E_DL_)','',n)
    parts=re.findall(r'[A-Z]+(?=[A-Z][a-z])|[A-Z][a-z0-9]+|[a-z0-9]+',s)
    return [p.lower() for p in parts]
roots=collections.defaultdict(set)
for n in names:
    for w in split(n): roots[w].add(n.lower())
cands=open('_Staging_Raw/2026-11-24/_r84_cands.txt',encoding='utf-8').read().split()
nameset={n.lower() for n in names}
print("total roots",len(roots))
for c in cands:
    ws=split(c)
    hits=collections.Counter()
    for w in ws:
        for n in roots.get(w,()): hits[n]+=1
    top=[(n,k) for n,k in hits.most_common(5) if k>=2]
    flag=''
    if c.lower() in nameset: flag='DUP_EXACT'
    elif top: flag='NEAR(>=2roots)'
    print(f"{flag:14s} {c:32s} {ws} -> {[(n,k) for n,k in hits.most_common(3)]}")
