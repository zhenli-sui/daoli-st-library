# -*- coding: utf-8 -*-
import json,os,difflib,re
reg=json.load(open('INDEX_REGISTRY.json',encoding='utf-8'))
items = reg if isinstance(reg,list) else reg.get('components',reg.get('items',[]))
names=[x.get('name','') for x in items]
nset=set(names)
T=[
# 族A 港口岸桥/场桥防摇与堆场  DL_Motion
("FB_DL_StsCraneAntiSwaySeq","DL_Motion","FB_DL","岸桥小车防摇定位状态机","clean-room","C4",1,"复杂"),
("FC_DL_SwayAngleEstimateCalc","DL_Motion","FC_DL","单摆等效摆角估算（绳长/加速度）","clean-room","C2",2,"简单"),
("FC_DL_TrolleyAccelProfileCalc","DL_Motion","FC_DL","小车梯形加速度给定规划","clean-room","C1",2,"简单"),
("FC_DL_HoistSyncSpeedCalc","DL_Motion","FC_DL","双卷筒起升同步速度给定","clean-room","C2",2,"简单"),
("FC_DL_SpreaderTwistLockChk","DL_Device","FC_DL","吊具旋锁四角到位互锁判定","clean-room","C2",2,"简单"),
("FC_DL_GantrySkewCorrectCalc","DL_Motion","FC_DL","大车行走纠偏量（轮差）","clean-room","C2",2,"简单"),
("FC_DL_CraneWindSpeedLimitChk","DL_Device","FC_DL","风速分级作业限幅判定","clean-room","C1",2,"简单"),
("FC_DL_ContainerStackHeightCalc","DL_Algo","FC_DL","堆场箱位层高与贝位换算","clean-room","C2",2,"简单"),
("FC_DL_CraneCycleTimeEstimate","DL_Algo","FC_DL","单箱作业循环时间估算","clean-room","C2",2,"简单"),
("FC_DL_CraneLoadMomentCalc","DL_Algo","FC_DL","载荷力矩与抗倾覆裕度","clean-room","C2",2,"简单"),
# 族B 制糖 甘蔗压榨与煮糖结晶  DL_Process
("FB_DL_SugarPanCrystallizationSeq","DL_Process","FB_DL","煮糖罐结晶工段序列控制","clean-room","C4",3,"复杂"),
("FC_DL_MillRollPressureCalc","DL_Process","FC_DL","压榨辊比压与油压给定","clean-room","C2",3,"简单"),
("FC_DL_BagasseMoistureCalc","DL_Process","FC_DL","蔗渣水分（料流平衡）","clean-room","C2",3,"简单"),
("FC_DL_JuiceBrixCorrectionCalc","DL_Process","FC_DL","糖度温度校正至20℃","clean-room","C2",3,"简单"),
("FC_DL_MassecuiteSupersaturationCalc","DL_Process","FC_DL","糖膏过饱和度","clean-room","C2",3,"简单"),
("FC_DL_VacuumPanHeatBalanceCalc","DL_Process","FC_DL","煮糖罐蒸发热平衡","clean-room","C2",3,"简单"),
("FC_DL_CrystalGrowthRateCalc","DL_Process","FC_DL","晶体线性生长速率","clean-room","C2",3,"简单"),
("FC_DL_SyrupDensityCalc","DL_Process","FC_DL","糖浆密度（浓度/温度）","clean-room","C1",3,"简单"),
("FC_DL_MolassesExhaustionCalc","DL_Process","FC_DL","废蜜纯度与糖分损失","clean-room","C2",3,"简单"),
("FC_DL_MillImbibitionWaterCalc","DL_Process","FC_DL","浸渗水量与稀释度","clean-room","C2",3,"简单"),
# 族C 数据中心精密空调与冷通道  DL_Device
("FB_DL_CrahGroupEconomizerSeq","DL_Device","FB_DL","机房群控自然冷却切换序列","clean-room","C4",4,"复杂"),
("FC_DL_CrahCoolingCapacityCalc","DL_Device","FC_DL","精密空调显热制冷量","clean-room","C2",4,"简单"),
("FC_DL_RackAirflowDemandCalc","DL_Device","FC_DL","机柜风量需求（热负荷）","clean-room","C2",4,"简单"),
("FC_DL_ChilledWaterDeltaTCalc","DL_Device","FC_DL","冷冻水温差与流量换算","clean-room","C1",4,"简单"),
("FC_DL_DewPointControlCalc","DL_Device","FC_DL","露点与送风温度下限","clean-room","C2",4,"简单"),
("FC_DL_PueInstantCalc","DL_Device","FC_DL","瞬时PUE","clean-room","C1",4,"简单"),
("FC_DL_AisleLeakageMixCalc","DL_Device","FC_DL","冷热通道旁通泄漏混合温度","clean-room","C2",4,"简单"),
("FC_DL_UpsLoadRateCalc","DL_Device","FC_DL","UPS负载率与冗余度","clean-room","C1",4,"简单"),
("FC_DL_BatteryBackupTimeCalc","DL_Device","FC_DL","电池恒功率后备时间","clean-room","C2",4,"简单"),
("FC_DL_FreeCoolingHoursCalc","DL_Device","FC_DL","焓差法自然冷却可用小时","clean-room","C2",4,"简单"),
# 族D 铸造 砂处理与造型线  DL_Process
("FB_DL_MoldingLineSandSeq","DL_Process","FB_DL","造型线砂处理与合型序列","clean-room","C4",5,"复杂"),
("FC_DL_GreenSandMoistureTargetCalc","DL_Process","FC_DL","湿型砂水分目标","clean-room","C2",5,"简单"),
("FC_DL_SandToMetalRatioCalc","DL_Process","FC_DL","砂铁比","clean-room","C1",5,"简单"),
("FC_DL_MullerBatchWeightCalc","DL_Process","FC_DL","混砂机批量配比","clean-room","C2",5,"简单"),
("FC_DL_BentoniteAdditiveCalc","DL_Process","FC_DL","膨润土补加量（MB当量）","clean-room","C2",5,"简单"),
("FC_DL_SandCompactionCalc","DL_Process","FC_DL","紧实率与含水量换算","clean-room","C1",5,"简单"),
("FC_DL_MoldClampForceCalc","DL_Process","FC_DL","合型压铁力与抬箱裕度","clean-room","C2",5,"简单"),
("FC_DL_PouringTimeCalc","DL_Process","FC_DL","浇注时间（浇口杯/阻流）","clean-room","C2",5,"简单"),
("FC_DL_ShakeoutCoolingTimeCalc","DL_Process","FC_DL","落砂冷却时间","clean-room","C1",5,"简单"),
("FC_DL_CoreSandBakeCurveCalc","DL_Process","FC_DL","芯砂烘干升温曲线","clean-room","C2",5,"简单"),
]
print("total",len(T),"complex",sum(1 for x in T if x[7]=="复杂"),"simple",sum(1 for x in T if x[7]=="简单"))
bad=0
for t in T:
    n=t[0]
    if n in nset:
        print("!! EXACT COLLISION",n); bad+=1; continue
    m=difflib.get_close_matches(n,names,n=3,cutoff=0.86)
    if m: print("~ NEAR",n,"->",m)
print("exact collisions:",bad)
json.dump([{"name":a,"category":b,"prefix":c,"func":d,"src":e,"cmplx":f,"batch":g,"tier":h} for a,b,c,d,e,f,g,h in T],
          open('_Staging_Raw/2026-11-25/r93_targets.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
