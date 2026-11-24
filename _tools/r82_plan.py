# -*- coding: utf-8 -*-
rows = [
(1,'FC_DL_CoagDoseFromJarTest','DL_Process','FC_DL_','由烧杯试验结果反算混凝剂投加量 (mg/L 到 L/h)','clean-room/工程公式','C2','A','简单'),
(2,'FC_DL_FlocDilutionRatio','DL_Process','FC_DL_','絮凝剂母液稀释比与配液体积','clean-room/工程公式','C2','A','简单'),
(3,'FC_DL_SettleVelocityCalc','DL_Process','FC_DL_','Stokes 沉降末速度（含雷诺数域判定）','clean-room/工程公式','C2','A','简单'),
(4,'FC_DL_SludgeBlanketLevel','DL_Process','FC_DL_','静压差法污泥界面高度（含密度温补）','clean-room/工程公式','C2','A','简单'),
(5,'FC_DL_ClarifierSurfaceLoad','DL_Process','FC_DL_','沉淀池表面水力负荷校核','clean-room/工程公式','C2','A','简单'),
(6,'FC_DL_SviCalc','DL_Process','FC_DL_','SVI 污泥容积指数（30min 沉降）','clean-room/工程公式','C2','A','简单'),
(7,'FC_DL_NtuCoagDoseAdj','DL_Process','FC_DL_','出水浊度反馈的投加量微调（限幅爬坡）','clean-room/工程公式','C2','A','简单'),
(8,'FC_DL_LamellaAreaCalc','DL_Process','FC_DL_','斜板斜管沉淀投影面积与板间距','clean-room/工程公式','C2','A','简单'),
(9,'FC_DL_ScrewPressThroughput','DL_Process','FC_DL_','螺旋压榨机干固体处理量','clean-room/工程公式','C2','A','简单'),
(10,'FC_DL_CakeSolidsCalc','DL_Process','FC_DL_','泥饼含固率（进泥滤液质量平衡）','clean-room/工程公式','C2','A','简单'),
(11,'FC_DL_PolymerDoseCalc','DL_Process','FC_DL_','PAM 聚合物投加量（DS 基比投）','clean-room/工程公式','C2','A','简单'),
(12,'FC_DL_CentrateTurbidityIdx','DL_Process','FC_DL_','离心液浊度指数与跑料判据','clean-room/工程公式','C2','A','简单'),
(13,'FC_DL_FiltrateRecycleRatio','DL_Process','FC_DL_','滤液回流比与固体负荷回算','clean-room/工程公式','C2','A','简单'),
(14,'FC_DL_DewaterMassBalance','DL_Process','FC_DL_','脱水段全物料平衡（含回收率）','clean-room/工程公式','C2','A','简单'),
(15,'FC_DL_BeltPressLoadRate','DL_Process','FC_DL_','带式压滤机比负荷率','clean-room/工程公式','C2','A','简单'),
(16,'FC_DL_ScrubberLiquidGasRatio','DL_Process','FC_DL_','湿式洗涤塔液气比 L/G','clean-room/工程公式','C2','A','简单'),
(17,'FC_DL_PackedBedHtu','DL_Process','FC_DL_','填料层传质单元高度 HTU 与塔高估算','clean-room/工程公式','C2','A','简单'),
(18,'FC_DL_ReagentConsumeCalc','DL_Process','FC_DL_','洗涤药剂日耗与储罐可用天数','clean-room/工程公式','C2','A','简单'),
(19,'FC_DL_CatalystActivityDecay','DL_Process','FC_DL_','SCR 催化剂活性衰减与剩余寿命','clean-room/工程公式','C2','A','简单'),
(20,'FC_DL_VenturiScrubDpEst','DL_Process','FC_DL_','文丘里洗涤器压降估算','clean-room/工程公式','C2','A','简单'),
(21,'FC_DL_DemisterVelocityChk','DL_Process','FC_DL_','除雾器截面流速与临界携液校核','clean-room/工程公式','C2','A','简单'),
(22,'FC_DL_StackEmissionDilute','DL_Process','FC_DL_','烟囱排放浓度干基与标态折算','clean-room/工程公式','C2','A','简单'),
(23,'FC_DL_ComponentRulEstimate','DL_Device','FC_DL_','部件剩余寿命线性与指数外推','clean-room/工程公式','C2','A','简单'),
(24,'FC_DL_BrgThermalDriftRate','DL_Device','FC_DL_','轴承温升速率与热平衡判据','clean-room/工程公式','C2','A','简单'),
(25,'FC_DL_OilChangeInterval','DL_Device','FC_DL_','按运行小时与污染度折算换油周期','clean-room/工程公式','C2','A','简单'),
(26,'FC_DL_MtbfCalc','DL_Device','FC_DL_','MTBF MTTR 与可用率联算','clean-room/工程公式','C2','A','简单'),
(27,'FC_DL_SpareReorderPoint','DL_Device','FC_DL_','备件订货点（用量乘提前期加安全库存）','clean-room/工程公式','C2','A','简单'),
(28,'FC_DL_PmScheduleNext','DL_Device','FC_DL_','下次预防性保养日期与逾期天数','clean-room/工程公式','C2','A','简单'),
(29,'FC_DL_LubeIntervalCalc','DL_Device','FC_DL_','润滑间隔（负荷温度污染修正）','clean-room/工程公式','C2','A','简单'),
(30,'FC_DL_BiogasYieldCalc','DL_Process','FC_DL_','沼气产率（VS 降解乘产气系数）','clean-room/工程公式','C2','A','简单'),
(31,'FC_DL_MethaneRatioCalc','DL_Process','FC_DL_','甲烷含量（CO2 折算与热值）','clean-room/工程公式','C2','A','简单'),
(32,'FC_DL_OrganicLoadRate','DL_Process','FC_DL_','厌氧有机负荷率 OLR (kgVS/m3 d)','clean-room/工程公式','C2','A','简单'),
(33,'FC_DL_VfaAlkalinityRatio','DL_Process','FC_DL_','VFA 碱度比与酸化预警','clean-room/工程公式','C2','A','简单'),
(34,'FC_DL_GasHolderLevel','DL_Process','FC_DL_','气柜储量（压力温度折算标准体积）','clean-room/工程公式','C2','A','简单'),
(35,'FC_DL_DigesterRetentionTime','DL_Process','FC_DL_','消化器水力停留时间 SRT HRT','clean-room/工程公式','C2','A','简单'),
(36,'FC_DL_FlareFlowSizing','DL_Process','FC_DL_','火炬最小放空流量与管径','clean-room/工程公式','C2','A','简单'),
(37,'FB_DL_CoagDoseJarTestSeq','DL_Process','FB_DL_','混凝加药闭环序列（前馈浊度加烧杯反馈加沉后复核）','clean-room/工程公式','C4','B','复杂'),
(38,'FB_DL_ScrewPressDewaterSeq','DL_Process','FB_DL_','螺旋压榨脱水序列（进泥加药压榨冲洗退让）','clean-room/工程公式','C4','B','复杂'),
(39,'FB_DL_ScrubberReagentDoseSeq','DL_Process','FB_DL_','洗涤塔药剂投加闭环（pH 反馈加电导补排加耗尽锁）','clean-room/工程公式','C4','B','复杂'),
(40,'FB_DL_AnaerobDigesterLoadCtrl','DL_Process','FB_DL_','厌氧消化有机负荷控制（VFA碱度加产气联动加超限降载）','clean-room/工程公式','C4','B','复杂'),
]

hdr = """# ROUND_PLAN_R82 - 2026-11-24 第 82 轮（冲刺模式）

**轮次基准**：T0 = 2026-11-24 11:04:30 (+08:00)｜目标 40 件 = 复杂 4 + 简单 36｜修复配额 **0**（非当日首轮，铁律一）
**冲刺判定**：今日累计 122 < 轮次序号 4 x 38 = 152，触发冲刺模式，复杂件上限 4，其余全简单件。
**词根规划法**：先 grep 词根频次挑低饱和域（Floc/Clarif/Dewater/Centrif/Scrub/Catalyst/Mixer/Maint/Spare/Kwh/F0/Anaerob 全 0~2 命中，已弃 chiller/steam/pump/mix/membrane/energy 饱和域），再对 40 名做 token 交集扫描（≥2 非通用 token 命中即驳回）。

**驳回与改名留痕**：
- `FC_DL_TurbidityDoseTrim`（↔FB_DL_WaterChlorineDoseTrim，dose+trim 2 token）→ 改名 `FC_DL_NtuCoagDoseAdj`
- `FC_DL_VenturiPressureDrop`（↔FC_DL_ReceiverPressureDropCalc，pressure+drop）→ 改名 `FC_DL_VenturiScrubDpEst`
- `FC_DL_VibIsoZoneClassify`（↔FB_DL_VibZoneClassify，vib+zone+classify 3 token 直接同义）→ **整条撤换** 为 `FC_DL_ComponentRulEstimate`
- `FC_DL_BearingTempTrend`（↔FB_DL_BearingVibTrend，bearing+trend）→ 改名 `FC_DL_BrgThermalDriftRate`
- `FB_DL_SipF0SterilAccum`（↔FB_DL_SipLineSterilSeq / FB_DL_AutoclaveSterilSeq 双重近邻）→ **整条撤换** 为 `FB_DL_ScrubberReagentDoseSeq`
- 终版 40 名 token 交集 **0 命中**

**磁盘差集前置**：registry 1,530 与磁盘 .st 1,530 完全一致，差集 0，无重复写盘风险。

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
"""
lines = [hdr]
for r in rows:
    lines.append('| %d | `%s` | %s | %s | %s | %s | %s | %s | %s |\n' % r)

lines.append("""
## 族结构（简单件 5 族同族连号，编码席一次调用按序写盘）
- **族 A 混凝絮凝沉淀** 1-8（8 件）：加药反算 / 稀释比 / 沉降速度 / 泥位 / 表面负荷 / SVI / 浊度微调 / 斜板面积
- **族 B 污泥脱水** 9-15（7 件）：螺旋压榨 / 含固率 / 聚合物 / 离心液 / 滤液回流 / 物料平衡 / 带压负荷
- **族 C 湿式洗涤与催化** 16-22（7 件）：液气比 / HTU / 药剂耗 / 催化衰减 / 文丘里压降 / 除雾流速 / 排放折算
- **族 D 设备点检维护** 23-29（7 件）：RUL / 轴承热漂 / 换油 / MTBF / 订货点 / PM 日期 / 润滑间隔
- **族 E 厌氧沼气** 30-36（7 件）：产气率 / 甲烷比 / OLR / VFA碱度 / 气柜 / 停留时间 / 火炬
- **复杂件 B 批** 37-40（4 件）：混凝闭环 / 螺旋脱水序列 / 洗涤加药闭环 / 厌氧负荷控制

## 里程碑（T0 = 11:04:30）
| 检查点 | 目标时刻 | 内容 | 实际 |
|---|---|---|---|
| T+15' | 11:19 | 规划表落盘（本文件） | 11:11 ✔ |
| T+40' | 11:44 | 编码交付 ≥36 件 | - |
| T+50' | 11:54 | 编译闸裁决 ≥36 件 | - |
| T+60' | 12:04 | 入库与战报完成 | - |
""")
open(r'C:\Library\_Staging_Raw\2026-11-24\ROUND_PLAN_R82.md','w',encoding='utf-8').write(''.join(lines))
print('plan written', len(rows))
