# -*- coding: utf-8 -*-
import json, re, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
d = json.load(open(r'C:\Library\INDEX_REGISTRY.json', encoding='utf-8'))
exist = {c['name'] for c in d['components']}
GEN = {'DL','FB','FC','I','ST','E','Calc','Ctrl','Seq','Loop','Chk','Mon','Mgr','Unit','Base','Std','Proc','Dev','Algo','Math','Data','Main','Gen','Util','Simple','Value','Index','Line','Risk','Time','Temp'}
def toks(n):
    out = set()
    for p in n.split('_'):
        for w in re.findall(r'[A-Z][a-z]+|[A-Z]+(?![a-z])|[a-z]+', p):
            if w not in GEN and len(w) > 2:
                out.add(w.lower())
    return out
P = [
 ('FC_DL_QuenchOilTempRiseCalc','DL_Process','FC',2,'Quench oil tank temperature rise and heat load calc','A'),
 ('FC_DL_AustenitizeHoldTimeCalc','DL_Process','FC',2,'Austenitizing hold time by effective thickness','A'),
 ('FC_DL_CarburizeCaseDepthCalc','DL_Process','FC',2,'Gas carburizing case depth Harris formula','A'),
 ('FC_DL_TemperEmpiricalHardnessCalc','DL_Process','FC',2,'Tempering temperature vs hardness empirical curve','A'),
 ('FB_DL_InductionHardeningScanCtrl','DL_Device','FB',2,'Induction hardening scan heating and spray sequence','A'),
 ('FB_DL_QuenchTankAgitatorCtrl','DL_Device','FB',2,'Quench tank agitator staging with oil temp interlock','A'),
 ('FC_DL_MartensiteFinishTempCalc','DL_MathData','FC',1,'Martensite start finish temperature empirical','A'),
 ('FB_DL_SoakPitTemperatureCtrl','DL_Device','FB',2,'Heat treat furnace multi zone soak and overtemp interlock','A'),
 ('FC_DL_ExtrusionBilletHeatCalc','DL_Process','FC',2,'Aluminium extrusion billet induction heating power','B'),
 ('FC_DL_ExtrusionSpecificPressureCalc','DL_Process','FC',2,'Extrusion specific pressure and ratio with friction','B'),
 ('FC_DL_AnodizeBathChargeCalc','DL_Process','FC',2,'Anodizing bath Faraday charge and current density','B'),
 ('FC_DL_ExtrusionDieWearIndexCalc','DL_Process','FC',2,'Extrusion die wear index and remaining life','B'),
 ('FB_DL_AnodizeRinseCascadeCtrl','DL_Device','FB',2,'Anodizing counterflow rinse cascade make up control','B'),
 ('FB_DL_BilletShearGaugeSeq','DL_Device','FB',2,'Billet cut to length with head tail trim sequence','B'),
 ('FC_DL_AnodizeFilmThicknessCalc','DL_MathData','FC',1,'Anodize film thickness charge time conversion','B'),
 ('FC_DL_AnodizeSealBoilTimeCalc','DL_Process','FC',1,'Boiling water sealing dwell time and pH window','B'),
 ('FC_DL_DieCastShotVelocityCalc','DL_Process','FC',2,'Die cast shot velocity PQ2 intersection fill time','C'),
 ('FC_DL_DieCastIntensifyPressureCalc','DL_Process','FC',2,'Intensification pressure and clamping force check','C'),
 ('FC_DL_DieThermalBalanceCalc','DL_Process','FC',2,'Die thermal balance and die heater load','C'),
 ('FC_DL_CastingSolidificationTimeCalc','DL_Process','FC',1,'Chvorinov solidification time and modulus','C'),
 ('FB_DL_DieSprayReleaseSeq','DL_Device','FB',2,'Die spray release agent and blow off sequence','C'),
 ('FB_DL_LadlePourWeightCtrl','DL_Device','FB',2,'Ladle metered pour weight closed loop','C'),
 ('FC_DL_DieCastPorosityRiskIndexCalc','DL_Device','FC',2,'Die cast porosity risk index','C'),
 ('FC_DL_PowderFillDensityCalc','DL_Process','FC',1,'Powder apparent fill density and fill height','D'),
 ('FC_DL_CompactionPressureCalc','DL_Process','FC',2,'Compaction pressure vs green density','D'),
 ('FB_DL_SinterFurnaceRampCtrl','DL_Process','FB',2,'Sinter furnace zone profile with dew point interlock','D'),
 ('FC_DL_GreenStrengthIndexCalc','DL_Process','FC',2,'Green strength index and eject safety','D'),
 ('FC_DL_SinterShrinkageCalc','DL_MathData','FC',1,'Sinter linear shrinkage and size compensation','D'),
 ('FB_DL_PowderBlendDoseSeq','DL_Device','FB',2,'Powder blend weigh and discharge sequence','D'),
 ('FC_DL_DelubeResidualCarbonCalc','DL_Device','FC',2,'Lubricant burn off dew point and residual carbon','D'),
 ('FC_DL_MashStrikeWaterTempCalc','DL_Process','FC',2,'Mash strike water temperature equilibrium','E'),
 ('FC_DL_WortExtractYieldCalc','DL_Process','FC',2,'Wort extract yield and mash efficiency','E'),
 ('FC_DL_SugarBoilSupersaturationCalc','DL_Process','FC',2,'Sugar boil supersaturation and nucleation window','E'),
 ('FC_DL_MolassesExhaustionCalc','DL_MathData','FC',1,'Molasses purity and sugar exhaustion','E'),
 ('FB_DL_CrystallizerVacuumCtrl','DL_Device','FB',2,'Crystallizer vacuum and boiling point elevation','E'),
 ('FB_DL_CipCaneJuiceLineSeq','DL_Device','FB',2,'Cane juice line CIP five step sequence','E'),
 ('FB_DL_QuenchTemperLineSeq','DL_Process','FB',4,'Quench temper linked line full state machine','A'),
 ('FB_DL_AnodizeLineTransferSeq','DL_Device','FB',4,'Anodizing line transfer with tank interlock','B'),
 ('FB_DL_DieCastCycleSupervise','DL_Device','FB',4,'Die cast single cycle supervision and graded stop','C'),
 ('FB_DL_SugarPanBatchSeq','DL_Process','FB',4,'Sugar pan batch charge concentrate graining discharge','E'),
]
bad = []
for n, cat, kind, cx, desc, fam in P:
    if n in exist:
        bad.append({'name': n, 'why': 'EXACT_DUP'}); continue
    t = toks(n); hits = []
    for e in exist:
        if abs(len(e) - len(n)) > 26: continue
        ov = t & toks(e)
        if len(ov) >= 2:
            hits.append({'e': e, 'ov': sorted(ov)})
    if hits:
        bad.append({'name': n, 'hits': hits[:2]})
print('TOTAL_PLAN', len(P))
print('BAD', len(bad))
for b in bad: print(json.dumps(b, ensure_ascii=False))
json.dump([{'name':a,'category':b,'type':c,'complexity':d2,'desc_en':e,'family':f} for a,b,c,d2,e,f in P],
          open(r'C:\Library\_Staging_Raw\2026-11-24\r85_targets.json','w',encoding='utf-8'), ensure_ascii=False, indent=1)
