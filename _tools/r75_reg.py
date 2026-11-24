import json, os, datetime

REG = r'C:\Library\INDEX_REGISTRY.json'
d = json.load(open(REG, encoding='utf-8'))
comps = d['components']
names = {c['name'] for c in comps}
TS = datetime.datetime.now().astimezone().isoformat(timespec='seconds')

new = [
 ("FB_DL_BurnerFlameGuard","DL_Device","FB",5,["burner","flame-safety","safety-interlock","state-machine","purge-sequence","thermal"],"internal","self-cleanroom (industry pool - thermal safety)","MIT","burner-flame-safety"),
 ("FB_DL_InjectionMoldClampSeq","DL_Process","FB",5,["injection-molding","clamp-sequence","process-sequencer","mold-protection","state-machine"],"internal","self-cleanroom (industry pool - molding)","MIT","injection-mold-sequence"),
 ("FB_DL_DeltaRobotIk","DL_Motion","FB",5,["delta-robot","inverse-kinematics","parallel-kinematics","singularity-guard","motion"],"internal","self-cleanroom (kinematics)","MIT","delta-ik"),
 ("FB_DL_VfdStateWordMatch","DL_Device","FB",3,["vfd","drive","status-word","state-match","diagnostics"],"queue","brOscatLib / MIT","MIT","ISC_NUM"),
 ("FB_DL_PaintBoothAirBalance","DL_Process","FB",4,["paint-booth","air-balance","differential-pressure","fan-interlock","hvac"],"internal","self-cleanroom (industry pool - coating)","MIT","paint-booth-air"),
 ("FC_DL_WeirFlowCalc","DL_MathData","FC",3,["weir","open-channel-flow","flow-measurement","submerged-flow","hydraulics"],"internal","self-cleanroom (public formula)","MIT","weir-flow"),
 ("FB_DL_WaterChlorineDoseTrim","DL_Process","FB",4,["water-treatment","chlorine","dosing","trim-control","turbidity"],"internal","self-cleanroom (water treatment)","MIT","chlorine-dose"),
 ("FB_DL_CentrifugeSpinSeq","DL_Process","FB",4,["centrifuge","spin-sequence","critical-speed","imbalance-trip","state-machine"],"internal","self-cleanroom (industry pool - separation)","MIT","centrifuge-seq"),
 ("FC_DL_AkimaInterp1D","DL_MathData","FC",4,["akima","interpolation","curve-fit","anti-oscillation","numerics"],"internal","self-cleanroom (public algorithm)","MIT","akima-interp"),
 ("FB_DL_VfdCtrlWordBuild","DL_Device","FB",3,["vfd","drive","control-word","bit-encoding","state-command"],"queue","brOscatLib / MIT","MIT","ISC_CTRL"),
 ("FB_DL_ManualOverride","DL_Base","FB",3,["manual-override","hand-auto","force-mode","timeout-fallback","operator"],"queue","brOscatLib / MIT","MIT","MANUAL"),
 ("FB_DL_IoLinkPortDiag","DL_Device","FB",3,["io-link","port-diagnostics","quality-code","watchdog","fieldbus"],"internal","self-cleanroom (protocol diagnostics)","MIT","iolink-diag"),
 ("FB_DL_PeltierTempCtrl","DL_Algo","FB",4,["peltier","tec","bidirectional-control","anti-windup","temperature"],"internal","self-cleanroom (precision thermal)","MIT","peltier-temp"),
 ("FC_DL_CabsComplexCalc","DL_MathData","FC",2,["complex","magnitude","overflow-safe","scaling","numerics"],"queue","brOscatLib / MIT","MIT","CABS"),
 ("FC_DL_Exp10Calc","DL_MathData","FC",1,["exponential","base10","domain-guard","numerics"],"queue","brOscatLib / MIT","MIT","EXP10"),
 ("FC_DL_SpeedUnitConvert","DL_MathData","FC",2,["unit-conversion","velocity","ms-kmh","bidirectional"],"queue","brOscatLib / MIT","MIT","MS_TO_KMH"),
 ("E_DL_ControlModeSel","DL_Base","E",1,["enum","control-mode","manual-auto-stop","type-definition"],"queue","AixOCAT / MIT","MIT","CONTROL_MODE"),
 ("FB_DL_FirstOrderImpResp","DL_MathData","FB",2,["first-order","impulse-response","system-identification","discrete-time"],"queue","brOscatLib / MIT","MIT","FT_IMP"),
 ("FC_DL_DwRealReinterp","DL_Base","FC",1,["bit-reinterpret","dword-real","ieee754","packing","bidirectional"],"queue","brOscatLib / MIT","MIT","DW_TO_REAL"),
 ("FB_DL_DualWindowBandCmp","DL_Base","FB",2,["window-comparator","dual-band","three-state","hysteresis"],"queue","brOscatLib / MIT","MIT","WINDOW2"),
 ("FC_DL_QuartileCalc","DL_MathData","FC",2,["statistics","quartile","percentile","data-analysis"],"internal","self-cleanroom (statistics family)","MIT","quartile"),
 ("FC_DL_PowerFactorCalc","DL_MathData","FC",2,["power-factor","electrical","power-quality","reactive","measurement"],"internal","self-cleanroom (public formula)","MIT","power-factor"),
 ("ST_DL_EtSlaveDiagBase","DL_Device","ST",2,["ethercat","slave-diagnostics","structure","fieldbus","clean-room"],"queue","TcOpen / MIT","MIT","EtcSlaveBase"),
 ("ST_DL_EtSyncUnitDiagBase","DL_Device","ST",2,["ethercat","sync-unit","diagnostics","structure","distributed-clock"],"queue","TcOpen / MIT","MIT","SyncUnitsBase"),
 ("FB_DL_DitherSignalGen","DL_MathData","FB",2,["dither","signal-generation","adc","noise","lcg"],"internal","self-cleanroom (signal generation)","MIT","dither-gen"),
 ("FC_DL_MoistureContentCalc","DL_MathData","FC",1,["moisture","loss-on-drying","ratio","domain-guard","quality"],"internal","self-cleanroom (public formula)","MIT","moisture"),
 ("FB_DL_ParamSnapshotRestore","DL_Base","FB",2,["parameter-management","snapshot","rollback","double-buffer","recipe"],"internal","self-cleanroom (parameter management)","MIT","param-snapshot"),
 ("FB_DL_SignalCrossbar8","DL_Base","FB",2,["signal-routing","crossbar","matrix","8x8","multiplex"],"internal","self-cleanroom (signal routing)","MIT","crossbar8"),
 ("FC_DL_WorkdayCalendarCalc","DL_Base","FC",2,["calendar","workday","holiday-table","julian-day","scheduling"],"internal","self-cleanroom (calendar family)","MIT","workday"),
 ("FB_DL_SmokeDetZoneMon","DL_Base","FB",2,["fire-alarm","smoke-detector","zone-monitor","latch","three-state"],"internal","self-cleanroom (fire protection)","MIT","smoke-zone"),
 ("FB_DL_VocVentTrim","DL_Process","FB",2,["voc","demand-ventilation","hvac","trim-control","air-quality"],"internal","self-cleanroom (HVAC extension)","MIT","voc-vent"),
 ("FC_DL_GearRatioCalc","DL_Motion","FC",1,["gear-ratio","reduction","inertia-ratio","mechanical-drive"],"internal","self-cleanroom (mechanical drive)","MIT","gear-ratio"),
 ("FB_DL_CrankKinFwd","DL_Motion","FB",2,["crank-slider","forward-kinematics","mechanism","position"],"internal","self-cleanroom (kinematics)","MIT","crank-kin"),
 ("FC_DL_BeltLengthCalc","DL_Motion","FC",1,["belt-drive","pitch-length","center-distance","mechanical"],"internal","self-cleanroom (mechanical drive)","MIT","belt-length"),
 ("FC_DL_OvershootPctCalc","DL_Algo","FC",1,["step-response","overshoot","loop-kpi","control-performance"],"internal","self-cleanroom (loop KPI)","MIT","overshoot"),
 ("FC_DL_SettleTimeCalc","DL_Algo","FC",2,["step-response","settling-time","tolerance-band","loop-kpi"],"internal","self-cleanroom (loop KPI)","MIT","settle-time"),
]

added = []
skip = []
for (n, cat, t, cx, tags, mode, src, lic, ref) in new:
    if n in names:
        skip.append(n)
        continue
    fp = os.path.join(r'C:\Library', cat, n + '.st')
    comps.append({
        "name": n, "category": cat, "type": t, "file_path": fp,
        "function_tags": tags, "complexity": cx, "registered_at": TS,
        "l2_status": "l2-pass",
        "origin": {"mode": mode, "source": src, "license": lic, "ref_tag": ref},
    })
    names.add(n)
    added.append(n)

bumped = []
bump_map = {
    "FC_DL_CamTableInterp": "1.0.2",
    "FB_DL_CamOverrideTrim": "1.0.1",
    "FB_DL_DryerExhaustHumidityCtl": "1.0.1",
    "FB_DL_WeightClassifySort": "1.0.1",
    "FB_DL_ChamberPurgeDry": "1.0.1",
}
for c in comps:
    if c['name'] in bump_map:
        c['version'] = bump_map[c['name']]
        c['updated_at'] = TS
        c['l2_status'] = 'l2-pass'
        bumped.append(c['name'])

cnt = {}
for c in comps:
    cnt[c['category']] = cnt.get(c['category'], 0) + 1

d['components'] = comps
d['counts'] = cnt
d['total_components'] = len(comps)
d['version'] = '2.67.0'
d['last_updated'] = TS
assert sum(cnt.values()) == len(comps)
json.dump(d, open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

print("ADDED", len(added), "SKIP", skip)
print("TOTAL", len(comps), "counts", cnt, "sum", sum(cnt.values()))
print("BUMPED", bumped)
json.dump({"added": added, "bumped": bumped},
          open(r'C:\Library\_Staging_Raw\2026-11-23\_r75_added.json', 'w', encoding='utf-8'),
          ensure_ascii=False)
