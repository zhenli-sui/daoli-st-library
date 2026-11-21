import json,os,shutil,io,re,datetime
now="2026-11-21T12:47:00+08:00"
shutil.copy('INDEX_REGISTRY.json','INDEX_REGISTRY.json.bak_r61')
d=json.load(open('INDEX_REGISTRY.json',encoding='utf-8'))
aud={x['name']:x for x in json.load(open('_audit_r61.json',encoding='utf-8'))}
plan={
'FC_DL_ReverseBitsLword':('DL_Base','FC','t2-1-lgf-bitlogic',['bitlogic','lword','reverse','wrapper']),
'FC_DL_BitScanLword':('DL_Base','FC','t2-1-lgf-bitlogic',['bitlogic','lword','scan','priority']),
'FC_DL_Hypot3D':('DL_MathData','FC','iec-std-wrapper',['math','hypot','3d','sqrt']),
'FC_DL_TrapezoidArea':('DL_MathData','FC','iec-std-wrapper',['math','integration','trapezoid']),
'FC_DL_SortIndexLReal':('DL_MathData','FC','t2-1-lgf-math',['math','sort','index']),
'FC_DL_WeightedPercentile':('DL_MathData','FC','t2-1-lgf-math',['math','statistics','percentile']),
'FC_DL_MeanAbsDevCalc':('DL_MathData','FC','t2-1-lgf-math',['math','statistics','deviation']),
'FB_DL_LongPressButton':('DL_Base','FB','self-std',['hmi','button','edge','timing']),
'FB_DL_RailPowerSequence':('DL_Base','FB','self-std',['power','sequence','interlock']),
'FB_DL_AxisLimitSwitchBank':('DL_Motion','FB','t1-6-plcopen',['motion','limit','switch','bank']),
'FB_DL_PidParamGuard':('DL_Algo','FB','t2-5-modpid',['pid','parameter','guard','online']),
'FB_DL_PhaseLossGuard':('DL_Device','FB','t2-1-lgf-measurement',['power','phase','guard','diagnostic']),
'FB_DL_SensorPairPlausibility':('DL_Device','FB','self-std',['sensor','plausibility','voting','diagnostic']),
'FB_DL_AirDryerDiag':('DL_Device','FB','t2-2-lbp',['compressed-air','dryer','dewpoint','diagnostic']),
'FB_DL_TurretToolSelect':('DL_Motion','FB','t2-4-s7-motion',['motion','turret','tool','select']),
'FB_DL_LineClearanceVerify':('DL_Process','FB','t2-7-packml',['packml','line','clearance','sequence']),
}
names=set(c['name'] for c in d['components'])
added=[];dupe=[]
for nm,(cat,typ,src,tags) in plan.items():
    if nm in names: dupe.append(nm); continue
    p=os.path.join(cat,nm+'.st')
    fp=os.path.abspath(p)
    n=aud[nm]['lines']
    d['components'].append({'name':nm,'category':cat,'type':typ,'file_path':fp,
      'function_tags':[src]+tags+[nm.lower()],'complexity':3,'version':'1.0.0',
      'registered_at':now,'line_count':n,'code_segment':'','source':'r61-plan'})
    added.append(nm)
# repair entries version bump
rep={'FB_DL_AxisCmdArbiter':'1.0.1','FC_DL_InterpolateTable3D':'1.0.1','FC_DL_Affine2DChain':'1.0.1','FB_DL_ShiftHandoverCheck':'1.0.1','FB_DL_TwoStepConfirm':'1.0.2'}
bumped=[]
for c in d['components']:
    if c['name'] in rep:
        c['version']=rep[c['name']]
        # refresh line count
        for dd in os.listdir('.'):
            if dd.startswith('DL_') and os.path.exists(os.path.join(dd,c['name']+'.st')):
                c['line_count']=len(open(os.path.join(dd,c['name']+'.st'),encoding='utf-8').read().splitlines())
                c['file_path']=os.path.abspath(os.path.join(dd,c['name']+'.st'))
                c['category']=dd
        bumped.append(c['name'])
counts={}
for c in d['components']: counts[c['category']]=counts.get(c['category'],0)+1
d['counts']=counts; d['total_components']=len(d['components']); d['version']='2.53.0'; d['last_updated']=now
json.dump(d,open('INDEX_REGISTRY.json','w',encoding='utf-8'),ensure_ascii=False,indent=2)
print('added',len(added),'dupe',dupe,'counts',counts,'total',d['total_components'],'bumped',bumped)
json.dump({'added':added,'bumped':bumped,'counts':counts,'total':d['total_components']},open('_r61_closeout.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
