# -*- coding: utf-8 -*-
import os, re, json, sys
sys.path.insert(0, r"C:\Library\_tools")
LIB = r"C:\Library"
import importlib.util
spec = importlib.util.spec_from_file_location("fp", os.path.join(LIB,"_tools","r82_fp_rebuild.py"))
fp = importlib.util.module_from_spec(spec); spec.loader.exec_module(fp)
analyze = fp.analyze
GEN = fp.GEN

tgt = json.load(open(os.path.join(LIB,"_Staging_Raw","2026-11-24","r85_targets.json"),encoding="utf-8"))
NEW = [(t["name"], t["category"], t["type"], t["complexity"], t.get("desc_en",""), t.get("family","")) for t in tgt]

fpdb = json.load(open(os.path.join(LIB,"_Staging_Raw","_dedup_fingerprints.json"),encoding="utf-8"))
reg  = json.load(open(os.path.join(LIB,"INDEX_REGISTRY.json"),encoding="utf-8"))
regnames = [c["name"] for c in reg["components"]]
newset = set(n for n,_,_,_,_,_ in NEW if n in [c for c in fpdb["components"]])

def toks(name):
    t=[x.lower() for x in re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])", name)]
    return set(x for x in t if x not in GEN and len(x)>2)

def norm(name):
    n = re.sub(r"^(FB_|FC_|I_|ST_|E_)", "", name)
    n = re.sub(r"^DL_", "", n)
    return n.lower()

comps = fpdb["components"]
others = {k:v for k,v in comps.items() if k not in set(n for n,_,_,_,_,_ in NEW)}
by_sig, by_api = {}, {}
for k,v in others.items():
    by_sig.setdefault(v["sig"],[]).append(k)
    by_api.setdefault(v["api"],[]).append(k)

rows=[]
for name,cat,kind,cx,desc,fam in NEW:
    path = os.path.join(LIB,cat,name+".st")
    if not os.path.exists(path):
        rows.append({"name":name,"cat":cat,"MISSING":path}); continue
    rec = analyze(path)
    r = {"name":name,"cat":cat,"kind":rec["kind"],"sig":rec["sig"],"api":rec["api"],
         "in_n":rec["in_n"],"out_n":rec["out_n"],"sm":rec["sm"],"lines":rec["lines"],
         "cx":cx,"desc":desc,"family":fam}
    r["name_exact"] = [x for x in regnames if x.lower()==name.lower()]
    nt = toks(name)
    near=[]
    for rn in regnames:
        if rn==name: continue
        rt = toks(rn)
        if not rt or not nt: continue
        j = len(nt&rt)/len(nt|rt)
        if j>=0.55: near.append((round(j,2),rn))
    r["name_near"] = sorted(near,reverse=True)[:6]
    r["sig_hit"] = by_sig.get(rec["sig"],[])
    r["api_hit"] = by_api.get(rec["api"],[])
    rows.append(r)

os.makedirs(os.path.join(LIB,"_tmp_r85"),exist_ok=True)
json.dump(rows, open(os.path.join(LIB,"_tmp_r85","dedup_raw.json"),"w",encoding="utf-8"),ensure_ascii=False,indent=1)
print("targets",len(NEW),"analyzed",len([r for r in rows if "MISSING" not in r]))
for r in rows:
    if "MISSING" in r: print("!! MISSING",r["name"],r["MISSING"])
print("--- sig hits (same sig group) ---")
for r in rows:
    if "MISSING" in r: continue
    if r["sig_hit"]: print(r["name"],r["kind"],r["in_n"],"/",r["out_n"],"sm=",r["sm"],"->",r["sig_hit"][:8])
print("--- api hits ---")
for r in rows:
    if "MISSING" in r: continue
    if r["api_hit"]: print(r["name"],"->",r["api_hit"][:8])
print("--- name exact ---")
for r in rows:
    if "MISSING" in r: continue
    if r["name_exact"]: print(r["name"],r["name_exact"])
print("--- name near >=0.55 ---")
for r in rows:
    if "MISSING" in r: continue
    if r["name_near"]: print(r["name"],r["name_near"])
