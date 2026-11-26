# -*- coding: utf-8 -*-
import json,difflib
reg=json.load(open('INDEX_REGISTRY.json',encoding='utf-8'))
items = reg if isinstance(reg,list) else reg.get('components',reg.get('items',[]))
names=[x.get('name','') for x in items]
T=[
("FB_DL_GantryCraneAnchoringSeq","DL_Motion","FB_DL","大车自动锚定与防风防滑序列（风速分级→减速→夹轨→锚定→解除）","clean-room","C4"),
("FC_DL_TrolleyPendulumAngleCalc","DL_Motion","FC_DL","小车加减速引起的单摆等效摆角估算","clean-room","C2"),
("FC_DL_TrolleyAccelProfileCalc","DL_Motion","FC_DL","小车梯形加速度给定规划（加加速限幅）","clean-room","C1"),
("FC_DL_HoistSyncSpeedCalc","DL_Motion","FC_DL","双卷筒起升同步速度给定与偏差分配","clean-room","C2"),
("FC_DL_SpreaderTwistLockChk","DL_Device","FC_DL","吊具旋锁四角到位互锁判定","clean-room","C2"),
("FC_DL_StsCraneRailClampChk","DL_Device","FC_DL","夹轨器/顶轨器状态与联锁判定","clean-room","C1"),
("FC_DL_CraneWindSpeedLimitChk","DL_Device","FC_DL","风速分级作业限幅判定（作业/降速/停工）","clean-room","C1"),
("FC_DL_ContainerStackHeightCalc","DL_Algo","FC_DL","堆场贝位层高与箱位换算","clean-room","C2"),
("FC_DL_CraneCycleTimeEstimate","DL_Algo","FC_DL","单箱作业循环时间估算（分工序）","clean-room","C2"),
("FC_DL_CraneLoadMomentCalc","DL_Algo","FC_DL","载荷力矩与抗倾覆安全裕度","clean-room","C2"),
("FB_DL_TobaccoCuttingLineSeq","DL_Process","FB_DL","制丝线切丝-烘丝-掺配工段序列控制","clean-room","C4"),
("FC_DL_CutTobaccoWidthCalc","DL_Process","FC_DL","切丝宽度与丝宽合格率（刀辊/线速）","clean-room","C2"),
("FC_DL_StemExpansionRateCalc","DL_Process","FC_DL","梗丝膨胀率（蒸汽/CO2 膨胀）","clean-room","C2"),
("FC_DL_DryerMoistureRemovalCalc","DL_Process","FC_DL","烘丝水分去除量（进出口含水率）","clean-room","C2"),
("FC_DL_CasingRateCalc","DL_Process","FC_DL","叶片加料比例与料液流量","clean-room","C2"),
("FC_DL_FlavorDosingCalc","DL_Process","FC_DL","加香比例与香精瞬时流量","clean-room","C2"),
("FC_DL_TobaccoComponentRatioCalc","DL_Process","FC_DL","叶丝/梗丝/膨胀丝掺配比例","clean-room","C1"),
("FC_DL_LeafConditioningMoistureCalc","DL_Process","FC_DL","松散回潮出口水分与温度给定","clean-room","C2"),
("FC_DL_TobaccoFillValueCalc","DL_Process","FC_DL","烟丝填充值（膨胀后单位质量体积）","clean-room","C1"),
("FC_DL_CutTobaccoFinesCalc","DL_Process","FC_DL","碎丝率（≤0.5mm 占比）与整丝率","clean-room","C1"),
("FB_DL_CrahGroupEconomizerSeq","DL_Device","FB_DL","机房群控自然冷却切换序列（焓差→新风→混合→机械）","clean-room","C4"),
("FC_DL_CrahCoolingCapacityCalc","DL_Device","FC_DL","精密空调显热制冷量与显热比","clean-room","C2"),
("FC_DL_RackAirflowDemandCalc","DL_Device","FC_DL","机柜风量需求（热负荷/温升）","clean-room","C2"),
("FC_DL_ChilledWaterDeltaTCalc","DL_Device","FC_DL","冷冻水温差与流量换算（Q=cmΔT）","clean-room","C1"),
("FC_DL_CrahSupplyTempResetCalc","DL_Device","FC_DL","送风温度重置曲线（最不利机柜反馈）","clean-room","C2"),
("FC_DL_PueInstantCalc","DL_Device","FC_DL","瞬时 PUE 与 IT 负载占比","clean-room","C1"),
("FC_DL_AisleLeakageMixCalc","DL_Device","FC_DL","冷热通道旁通泄漏混合温度","clean-room","C2"),
("FC_DL_UpsLoadRateCalc","DL_Device","FC_DL","UPS 负载率与 N+1 冗余度","clean-room","C1"),
("FC_DL_BatteryBackupTimeCalc","DL_Device","FC_DL","电池恒功率放电后备时间","clean-room","C2"),
("FC_DL_FreeCoolingHoursCalc","DL_Device","FC_DL","焓差法自然冷却可用小时数","clean-room","C2"),
("FB_DL_MoldingLineSandSeq","DL_Process","FB_DL","造型线砂处理与合型浇注序列","clean-room","C4"),
("FC_DL_GreenSandMoistureTargetCalc","DL_Process","FC_DL","湿型砂水分目标（紧实率反算）","clean-room","C2"),
("FC_DL_SandToMetalRatioCalc","DL_Process","FC_DL","砂铁比与砂循环量","clean-room","C1"),
("FC_DL_MullerBatchWeightCalc","DL_Process","FC_DL","混砂机批量配比（新砂/旧砂/辅料）","clean-room","C2"),
("FC_DL_BentoniteAdditiveCalc","DL_Process","FC_DL","膨润土补加量（亚甲基蓝当量）","clean-room","C2"),
("FC_DL_GreenSandCompactabilityCalc","DL_Process","FC_DL","紧实率与含水量换算","clean-room","C1"),
("FC_DL_MoldClampForceCalc","DL_Process","FC_DL","合型压铁力与抬箱裕度","clean-room","C2"),
("FC_DL_PouringTimeCalc","DL_Process","FC_DL","浇注时间（浇口杯/阻流断面）","clean-room","C2"),
("FC_DL_ShakeoutCoolingTimeCalc","DL_Process","FC_DL","落砂后铸件冷却时间","clean-room","C1"),
("FC_DL_CoreSandBakeCurveCalc","DL_Process","FC_DL","芯砂烘干升温曲线与残余水分","clean-room","C2"),
]
out=[];bad=0
for i,(n,cat,pre,func,src,cx) in enumerate(T,1):
    if n in names: print("!! COLLISION",n); bad+=1; continue
    m=difflib.get_close_matches(n,names,n=3,cutoff=0.88)
    if m: print("~NEAR",n,m)
    out.append({"no":i,"name":n,"category":cat,"prefix":pre,"func":func,"src":src,"cmplx":cx,
                "tier":"复杂" if cx in("C3","C4","C5") else "简单","batch":(i-1)//10+1})
print("total",len(T),"collisions",bad,"complex",sum(1 for x in out if x["tier"]=="复杂"),"simple",sum(1 for x in out if x["tier"]=="简单"))
json.dump(out,open('_Staging_Raw/2026-11-25/r93_targets.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
rows=["| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |",
      "|---|---|---|---|---|---|---|---|---|"]
for x in out:
    rows.append("| %d | %s | %s | %s | %s | %s | %s | %d | %s |"%(x["no"],x["name"],x["category"],x["prefix"],x["func"],x["src"],x["cmplx"],x["batch"],x["tier"]))
open('_Staging_Raw/2026-11-25/_plan_rows_r93.md','w',encoding='utf-8').write("\n".join(rows))
