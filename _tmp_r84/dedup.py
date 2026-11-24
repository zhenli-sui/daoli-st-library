# -*- coding: utf-8 -*-
import os, re, json, hashlib, sys
sys.path.insert(0, r"C:\Library\_tools")
LIB = r"C:\Library"
# reuse analyze() from r82_fp_rebuild
import importlib.util
spec = importlib.util.spec_from_file_location("fp", os.path.join(LIB,"_tools","r82_fp_rebuild.py"))
fp = importlib.util.module_from_spec(spec); spec.loader.exec_module(fp)
analyze = fp.analyze

NEW_DEV = """FB_DL_CncToolWearCompLoop FB_DL_CncLoadUnloadSeq FB_DL_ToolMagazinePosSeq FC_DL_CuttingForceCalc FC_DL_CncMrrCalc FC_DL_CncSpindleLoadRatio FC_DL_CoolantConcCalc FC_DL_ToolWearVbCalc FC_DL_ChipLoadPerToothCalc FC_DL_ClinkerLsfCalc FC_DL_ClinkerC3sCalc FC_DL_KilnSpecificHeatCalc FC_DL_RawMealResidueCalc FB_DL_KilnPreheatStageSeq FC_DL_CementMillLoadCalc FC_DL_ClinkerFreeLimeCalc""".split()
NEW_PRC = """FB_DL_ReactorRunawayGuard FB_DL_TabletWeightAutoCtl FB_DL_HeadboxJetRatioLoop FB_DL_TabletCompactionSeq FB_DL_ReactorChargeSeq FB_DL_ReactorHeatupProfile FB_DL_HeadboxSliceSeq FC_DL_TabletWeightRsdCalc FC_DL_FluidBedDryLossCalc FC_DL_CoatingPanSprayCalc FC_DL_TabletCrushForceCalc FC_DL_BlendUniformityCalc FC_DL_GranuleSizeD50Calc FC_DL_TabletFriabilityCalc FC_DL_ReactorHeatReleaseCalc FC_DL_ReactorAdiabaticRise FC_DL_MtsrCalc FC_DL_JacketAreaCalc FC_DL_PaperBasisWeightCalc FC_DL_StockConsistencyCalc FC_DL_RefinerFreenessCalc FC_DL_DryerSteamDemandCalc FC_DL_PaperFormationIndexCalc FC_DL_PressSectionDewaterCalc""".split()
NEW = [(n,"DL_Device") for n in NEW_DEV] + [(n,"DL_Process") for n in NEW_PRC]

fpdb = json.load(open(os.path.join(LIB,"_Staging_Raw","_dedup_fingerprints.json"),encoding="utf-8"))
reg  = json.load(open(os.path.join(LIB,"INDEX_REGISTRY.json"),encoding="utf-8"))
regnames = [c["name"] for c in reg["components"]]
regmeta  = {c["name"]:c for c in reg["components"]}
newset = set(n for n,_ in NEW)

GEN = fp.GEN
def toks(name):
    t=[x.lower() for x in re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])", name)]
    return set(x for x in t if x not in GEN and len(x)>2)

# strip DL_ prefix for normalization
def norm(name):
    n = re.sub(r"^(FB_|FC_|I_|ST_|E_)", "", name)
    n = re.sub(r"^DL_", "", n)
    return n.lower()

comps = fpdb["components"]
others = {k:v for k,v in comps.items() if k not in newset}
by_sig, by_api = {}, {}
for k,v in others.items():
    by_sig.setdefault(v["sig"],[]).append(k)
    by_api.setdefault(v["api"],[]).append(k)

rows=[]
for name,cat in NEW:
    path = os.path.join(LIB,cat,name+".st")
    rec = analyze(path)
    r = {"name":name,"cat":cat,"kind":rec["kind"],"sig":rec["sig"],"api":rec["api"],
         "in_n":rec["in_n"],"out_n":rec["out_n"],"sm":rec["sm"],"lines":rec["lines"],
         "tokens":rec["tokens"]}
    # 1 name channel
    r["name_exact"] = [x for x in regnames if x.lower()==name.lower()]
    nt = toks(name)
    near=[]
    for rn in regnames:
        if rn==name: continue
        rt = toks(rn)
        if not rt or not nt: continue
        j = len(nt&rt)/len(nt|rt)
        if j>=0.6: near.append((round(j,2),rn))
    r["name_near"] = sorted(near,reverse=True)[:6]
    # 2 fingerprint
    r["sig_hit"] = by_sig.get(rec["sig"],[])
    r["api_hit"] = by_api.get(rec["api"],[])
    rows.append(r)

json.dump(rows, open(os.path.join(LIB,"_tmp_r84","dedup_raw.json"),"w",encoding="utf-8"),ensure_ascii=False,indent=1)
print("new",len(rows))
print("--- sig hits ---")
for r in rows:
    if r["sig_hit"]: print(r["name"], r["kind"], r["in_n"],"/",r["out_n"], "sm=",r["sm"], "->", r["sig_hit"][:6])
print("--- api hits ---")
for r in rows:
    if r["api_hit"]: print(r["name"], "->", r["api_hit"][:6])
print("--- name exact ---")
for r in rows:
    if r["name_exact"]: print(r["name"], r["name_exact"])
print("--- name near (j>=0.6) ---")
for r in rows:
    if r["name_near"]: print(r["name"], r["name_near"])
