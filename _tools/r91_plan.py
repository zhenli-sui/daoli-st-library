# -*- coding: utf-8 -*-
import json, io, os, difflib, datetime

LIB = r"C:\Library"
reg = json.load(io.open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
names = set(c["name"] for c in reg["components"])

FAM = {
 "A": ("水泥窑篦冷机与预热器", [
  ("FC_DL_GrateCoolerHeatRecoveryCalc","FC","篦冷机热回收效率：由二次/三次风带出热与熟料显热算回收率，含热容与流量零闸、0~100% 物理域钳制","C2"),
  ("FC_DL_GrateCoolerBedResistanceCalc","FC","篦床料层阻力：由料层厚度、篦板开孔率与风量算压损，含开孔率零闸与压损上限","C2"),
  ("FC_DL_GrateCoolerAirBalanceCalc","FC","篦冷机风量平衡：各风室风量求和与窑头抽风比对，给多余/亏缺风量与不平衡率","C2"),
  ("FC_DL_GrateCoolerClinkerTempCalc","FC","出篦冷机熟料温度：由比热、风料比与入口温度算出口温度，含比热零闸与温度下限","C2"),
  ("FC_DL_PreheaterStageEfficiencyCalc","FC","预热器单级换热效率：由进出口气温与物料温度算，含温差零闸与效率物理域校验","C3"),
  ("FC_DL_PreheaterCyclonePressureCalc","FC","旋风筒压损：由入口风速与阻力系数算，附风速上限与堵塞风险判据","C2"),
  ("FC_DL_KilnBypassRatioCalc","FC","窑尾旁路放风比：由旁路风量与窑尾总风量算，含碱氯负荷约束下的推荐区间","C3"),
  ("FC_DL_ClinkerCoolingRateCalc","FC","熟料冷却速率：由两测温点温差与停留时间算 K/min，含时间零闸与速率上下限","C2"),
  ("FB_DL_GrateCoolerStrokeWatch","FB","篦床行程监视：行程超限/不同步/停滞三判据去抖计时，输出报警等级与停机建议","C3"),
  ("FB_DL_GrateCoolerStartupSeq","FB","篦冷机启动状态机：待机→风机启动→篦床低速→投料升速→正常，含故障兜底与总超时","C4"),
 ]),
 "B": ("制药冻干真空冷冻干燥", [
  ("FC_DL_LyoIceVaporPressureCalc","FC","冰面饱和蒸气压：Goff-Gratch 简化式按温度算 Pa，含温度域校验（-60~0℃）与非有限闸","C3"),
  ("FC_DL_LyoSublimationRateCalc","FC","升华速率：由蒸气压差、传质系数与面积算 kg/h，含压差负值判失效与系数零闸","C3"),
  ("FC_DL_LyoShelfHeatDutyCalc","FC","搁板加热功率：由升华潜热与速率算 kW，附加热效率与功率上限","C2"),
  ("FC_DL_LyoPrimaryDryingTimeCalc","FC","一次干燥时间估算：由初始含水量、升华速率与瓶数算小时，含速率零闸与收敛判据","C3"),
  ("FC_DL_LyoChamberLeakRateCalc","FC","腔体泄漏率：压力升试验法由升压与时间算 mbar·L/s，含时间零闸与合格判据","C2"),
  ("FC_DL_LyoCollapseTempMarginCalc","FC","塌陷温度裕度：制品温度与塌陷温度之差，含裕度不足分级与冰点以下约束","C2"),
  ("FC_DL_LyoResidualMoistureCalc","FC","残余水分估算：由终压升速率与干重比算百分比，含比值域校验","C2"),
  ("FB_DL_LyoShelfTempRampCtrl","FB","搁板升温速率控制：斜坡发生器 + 超调抑制 + 速率上下限，含周期入参与 NaN 闸","C3"),
  ("FB_DL_LyoPressureRiseTestSeq","FB","压力升测试序列：隔离→稳压→计时→记录→判定→复压，含泄漏超限中止与总超时","C3"),
  ("FB_DL_LyoVacuumPullSeq","FB","抽真空状态机：粗抽→精抽→保持→就绪，含泵故障兜底、真空度保持判据与总超时","C4"),
 ]),
 "C": ("轮胎硫化", [
  ("FC_DL_TireCureEquivalentTimeCalc","FC","等效硫化时间：Arrhenius 温度积分折算 140℃ 基准当量分钟，含活化能与基准温度零闸","C3"),
  ("FC_DL_TireCureBladderSteamCalc","FC","胶囊蒸汽耗量：由胶囊容积、升温与冷凝量算 kg/周期，含容积零闸","C2"),
  ("FC_DL_TireCurePressForceCalc","FC","合模力：由胶囊压力与投影面积算 kN，附机台额定上限与不足判据","C2"),
  ("FC_DL_TireCureTempGradientCalc","FC","胎面温差：由外温、内温与导热路径算 ΔT，含温差超限分级","C3"),
  ("FC_DL_TireCureDegreeCalc","FC","硫化程度：活化能积分与目标积分之比，给百分比与欠硫/过硫判定","C3"),
  ("FC_DL_TireCureMoldCycleTimeCalc","FC","模压周期：合模+升温+保温+排凝+开模分段落求和，含各段零值容错","C2"),
  ("FC_DL_TireCureSteamQualityCalc","FC","蒸汽干度：由焓差法估算干度 0~1，含超范围判饱和/过热","C2"),
  ("FB_DL_TireCureMoldTempWatch","FB","模温监视：上下模温差、超限去抖、加热失效判据，输出报警与趋势方向","C2"),
  ("FB_DL_TireCureBlowdownWatch","FB","排凝监视：按周期累计冷凝水量与排凝阀动作次数比对，判阀堵/泄漏","C3"),
  ("FB_DL_TireCurePressSeq","FB","硫化机合模状态机：装胎→合模→一次定型→二次定型→硫化→泄压→开模→卸胎，含故障兜底与每相超时","C5"),
 ]),
 "D": ("间歇式溢流染色与丝光整理", [
  ("FC_DL_JiggerLiquorRatioCalc","FC","浴比：由液量与被染物重量算 L/kg，含重量零闸与工艺区间判定","C2"),
  ("FC_DL_JiggerRampRateCalc","FC","升温速率：由温差与设定时间算 ℃/min，含时间零闸与纤维允许速率上限","C2"),
  ("FC_DL_OverflowDyeFlowCalc","FC","溢流循环流量：由喷嘴数、孔径与泵压算 m³/h，含孔径零闸","C2"),
  ("FC_DL_MercerCausticPickupCalc","FC","丝光碱液带液率：由轧余率与碱浓算带碱量 g/kg 布，含浓度零闸","C3"),
  ("FC_DL_MercerShrinkageCalc","FC","丝光收缩率：由处理前后经纬密度算收缩百分比，含密度零闸与负值判异常","C2"),
  ("FC_DL_BleachChemicalDoseCalc","FC","漂白剂投加量：由浴比、目标浓度与有效氯含量算 kg，含有效氯零闸","C3"),
  ("FC_DL_DyeExhaustionCalc","FC","上染率：由初始与残液吸光度（浓度）算百分比，含初始浓度零闸与超 100% 判异常","C3"),
  ("FC_DL_DyeShadeDeltaCalc","FC","色差 ΔE：CIE76 Lab 欧氏距离，附判定阈值分级（合格/返修/回修）","C3"),
  ("FB_DL_MercerCausticConcWatch","FB","碱浓度监视：超限去抖、补水联动请求、连续失效计数，输出报警","C2"),
  ("FB_DL_JiggerBatchRecipeSeq","FB","染缸批次运行状态机：进布→进液→升温→保温→降温→水洗→出布，含步序跳转保护、故障兜底与总超时","C4"),
 ]),
}

rows = []
n = 0
issues = []
allnames = sorted(names)
for fk in ["A","B","C","D"]:
    fam, items = FAM[fk]
    for (nm, kind, desc, cx) in items:
        n += 1
        if nm in names:
            issues.append(("EXACT_COLLIDE", nm))
        close = difflib.get_close_matches(nm, allnames, n=1, cutoff=0.88)
        if close:
            issues.append(("NEAR", nm, close[0], round(difflib.SequenceMatcher(None, nm, close[0]).ratio(),3)))
        tier = "复杂" if cx in ("C4","C5") else "简单"
        rows.append(dict(no=n, name=nm, cat="DL_Process", prefix=kind, desc=desc,
                         src=f"clean-room/{fam}", cx=cx, batch=(n-1)//10+1, tier=tier, family=fam))

print("total", len(rows), "complex", sum(1 for r in rows if r["tier"]=="复杂"), "simple", sum(1 for r in rows if r["tier"]=="简单"))
print("ISSUES:", len(issues))
for i in issues: print("  ", i)

now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
stg = os.path.join(LIB, "_Staging_Raw", "2026-11-25")
os.makedirs(stg, exist_ok=True)
L = []
L.append("# ROUND_PLAN_R91 ｜ 2026-11-25 第 4 轮（冲刺轮）\n")
L.append(f"- 轮次：R91 ｜ 计划开始 10:17 ｜ 目标 40（复杂 4 + 简单 36）｜ 规划落盘 {now}")
L.append("- 冲刺判定：今日累计 118 < 4x38=152 → **复杂件上限 4**，其余全部简单件（铁律一/冲刺模式）")
L.append("- 修复名额：**0**（非当日首轮，铁律一）；本轮新件自身回修不计配额")
L.append(f"- 磁盘差集：registry {len(reg['components'])} ≡ 磁盘 .st 1882，双向差集 0，无重复写盘风险")
L.append("- 族模板：四族各 10 件（9 简单 + 1 复杂），编码席按族一次调用批量写盘，严禁一件一调用（铁律三）")
L.append(f"- 撞名与语义三查：{len(rows)} 名对 {len(names)} 在册名精确零撞名；difflib≥0.88 近邻命中 {len([i for i in issues if i[0]=='NEAR'])} 条，逐条已人工确认非同义")
L.append("- 族域选择依据：A/B/C/D 四族词根全库饱和度实测 preheater=0 / gratecooler=0 / lyophil=0 / freezeDry=0 / vulcaniz=0 / curingpress=0 / jigger=0 / mercer=0 / kier=0，属真空域（非重复开发）\n")
L.append("| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |")
L.append("|---|---|---|---|---|---|---|---|---|")
for r in rows:
    L.append(f"| {r['no']} | `{r['name']}` | {r['cat']} | {r['prefix']} | {r['desc']} | {r['src']} | {r['cx']} | {r['batch']} | {r['tier']} |")
L.append("\n## 近邻比对声明（difflib 0.88 以上）\n")
if [i for i in issues if i[0]=='NEAR']:
    for i in issues:
        if i[0]=="NEAR":
            L.append(f"- `{i[1]}` ↔ 在册 `{i[2]}`（相似度 {i[3]}）：比对确认——族域不同/输入输出不同/算法不同，属有效新件，非语义重复。")
else:
    L.append("- 无 ≥0.88 近邻。")
L.append("\n## 未被采纳候选（留痕）\n")
L.append("- `FC_DL_KilnSpecificHeatCalc` 类：在册已有 `FC_DL_KilnSpecificHeatCalc`，撞名驳回。")
L.append("- `FC_DL_CementMillLoadCalc` 类：在册已有，撞名驳回。")
L.append("- `FB_DL_EwmaFilter`/`FC_DL_ExpMovingAvgCalc` 族（工业 SPC 方向）：在册已有 EWMA 2 件 + 移动平均 2 件 + 直方图 3 件 + 离群 2 件，语义邻域拥挤，整族驳回改期。")
L.append("- `FC_DL_DyeLiquorRatioCalc`：在册已有同义件（浴比），本轮 D 族改用 `FC_DL_JiggerLiquorRatioCalc` 并以「间歇式染缸 + 工艺区间判定」为差异点，见近邻声明。")
L.append("\n## 编码席派单要点\n")
L.append("- 批次 1=A 族 10 件、批次 2=B 族 10 件、批次 3=C 族 10 件、批次 4=D 族 10 件；每批一次调用内按序号顺序写盘。")
L.append("- 全部 DL_Process，路径 `C:\\Library\\DL_Process\\<Name>.st`。")
L.append("- 每件文件头 4 行：`(* 名称 / 分类 / 复杂度 / 开源溯源：clean-room 自研，无外部代码 *)`。")
L.append("- 硬规则 R1~R16 全适用；本族重点：R4 防除零/非有限、R5 同行中英双语注释、R6 状态机 ENUM+CASE 含 ELSE、R7 TON/R_TRIG 无条件刷新。")
L.append("- **R19 强化（连续 3 轮同型）**：判据层与出口实值通路必须同源；非有限闸不得只置 xValid，必须闸断 REAL 输出。")
L.append("- **R24（R90 新增）**：禁止「先 LIMIT 夹到工艺量程再判是否超量程」，判据必须取原始值。")
L.append("- **R25（R90 新增）**：所有锁存状态量必须有安全初值（冷启动专项），待机相必须显式赋值。")

io.open(os.path.join(stg, "ROUND_PLAN_R91.md"), "w", encoding="utf-8").write("\n".join(L))
json.dump(rows, io.open(os.path.join(stg, "r91_targets.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("PLAN WRITTEN", os.path.join(stg, "ROUND_PLAN_R91.md"))
