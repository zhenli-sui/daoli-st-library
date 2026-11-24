# -*- coding: utf-8 -*-
import json, os, sys

MINE = """FB_DL_CncToolWearCompLoop FB_DL_CncLoadUnloadSeq FB_DL_ToolMagazinePosSeq FC_DL_CuttingForceCalc
FC_DL_CncMrrCalc FC_DL_CncSpindleLoadRatio FC_DL_CoolantConcCalc FC_DL_ToolWearVbCalc FC_DL_ChipLoadPerToothCalc
FC_DL_ClinkerLsfCalc FC_DL_ClinkerC3sCalc FC_DL_KilnSpecificHeatCalc FC_DL_RawMealResidueCalc FB_DL_KilnPreheatStageSeq
FC_DL_CementMillLoadCalc FC_DL_ClinkerFreeLimeCalc FB_DL_ReactorRunawayGuard FB_DL_TabletWeightAutoCtl
FB_DL_HeadboxJetRatioLoop FB_DL_TabletCompactionSeq FB_DL_ReactorChargeSeq FB_DL_ReactorHeatupProfile
FB_DL_HeadboxSliceSeq FC_DL_TabletWeightRsdCalc FC_DL_FluidBedDryLossCalc FC_DL_CoatingPanSprayCalc
FC_DL_TabletCrushForceCalc FC_DL_BlendUniformityCalc FC_DL_GranuleSizeD50Calc FC_DL_TabletFriabilityCalc
FC_DL_ReactorHeatReleaseCalc FC_DL_ReactorAdiabaticRise FC_DL_MtsrCalc FC_DL_JacketAreaCalc
FC_DL_PaperBasisWeightCalc FC_DL_StockConsistencyCalc FC_DL_RefinerFreenessCalc FC_DL_DryerSteamDemandCalc
FC_DL_PaperFormationIndexCalc FC_DL_PressSectionDewaterCalc""".split()
S = set(MINE)
print("目标件数", len(S))

d = json.load(open(r"C:\Library\_Staging_Raw\_l1_r84.json", encoding="utf-8"))
if not d.get("results"):
    print("no results"); sys.exit(0)
print("样例键:", list(d["results"][0].keys()))
print()

def basename(p):
    p = p.replace("\\", "/")
    return os.path.splitext(os.path.basename(p))[0]

hit = {}
for r in d["results"]:
    n = basename(r.get("file") or r.get("path") or "")
    if n in S:
        hit[n] = r

print("L1 覆盖到的目标件:", len(hit), "/ 40")
missing = sorted(S - set(hit))
if missing:
    print("未覆盖:", missing)
print()
for n in sorted(hit):
    r = hit[n]
    iss = r.get("issues") or []
    st = r.get("status") or r.get("verdict")
    if iss:
        print("%-32s | %s | %d 条" % (n, st, len(iss)))
        for i in iss:
            print("     ", json.dumps(i, ensure_ascii=False)[:260])
print()
print("=== 全库 BLOCK 明细（前 50 条，供交叉核对）===")
cnt = 0
for r in d["results"]:
    for i in (r.get("issues") or []):
        sev = (i.get("severity") or i.get("level") or "").upper()
        if sev == "BLOCK":
            cnt += 1
            if cnt <= 50:
                print("%-34s L%-5s %-28s %s" % (basename(r.get("file") or ""), i.get("line"), i.get("code"), (i.get("msg") or "")[:90]))
print("BLOCK 总数:", cnt)
