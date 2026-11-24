import json,re
roots=json.load(open('_Staging_Raw/2026-11-24/_r84_roots.json',encoding='utf-8'))
d=json.load(open('INDEX_REGISTRY.json',encoding='utf-8'))
names={x['name'].lower() for x in d['components']}
cands="""FC_DL_PvIrSeriesResCalc
FC_DL_PvCellEffCalc
FC_DL_PvStringMismatchLoss
FC_DL_LaminateCureDegreeCalc
FC_DL_SolderRibPullStrengthCalc
FB_DL_ElDefectCountSeq
FB_DL_PvFlashBinSeq
FC_DL_PvTempCoeffPowerCalc
FC_DL_CoatingArealDensityCalc
FC_DL_CoatingDryRatioCalc
FB_DL_CoatingGapAdjustSeq
FC_DL_CalenderCompactionCalc
FC_DL_SlitWidthTrimCalc
FB_DL_WebTensionZoneSeq
FC_DL_ElectrodePorosityCalc
FB_DL_CoatingHeadTrackSeq
FC_DL_ToolLifeRemainCalc
FC_DL_CncSpindleLoadRatio
FB_DL_CncLoadUnloadSeq
FC_DL_MachiningCycleTimeCalc
FB_DL_ToolChangeReqSeq
FC_DL_SpcCpCpkCalc
FC_DL_CoolantConcCalc
FC_DL_ReactorHeatReleaseCalc
FC_DL_ReactorAdiabaticRise
FB_DL_ReactorChargeSeq
FB_DL_ReactorRampSeq
FC_DL_MtsrCalc
FB_DL_RunawayInterlockSeq
FC_DL_JacketAreaCalc
FC_DL_TabletWeightCvCalc
FC_DL_GranuleMoistureCalc
FC_DL_CoatingPanSprayCalc
FB_DL_TabletPressWeightSeq
FC_DL_BlendUniformityCalc
FC_DL_TabletHardnessRatio
FB_DL_CoatingDensityLoop
FB_DL_ReactorRunawayPredict
FB_DL_ToolLifePredictSeq
FB_DL_TabletWeightAutoCtl""".strip().split()
bad=[]
for c in cands:
    lc=c.lower()
    s=lc.replace('fb_dl_','').replace('fc_dl_','')
    words=re.findall('[a-z]+',s)
    hits=set()
    for w in words:
        if len(w)<4: continue
        for n in roots.get(w,[]):
            hits.add(n)
    exact = lc in names
    # also check 2-gram root coexistence
    print(f"{c:34s} exact={exact} roots={words} hits={sorted(hits)[:6]}")
