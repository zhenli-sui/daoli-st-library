# -*- coding: utf-8 -*-
rows = [
("FC_DL_WeighNetFromGross","DL_Process","毛重/皮重→净重换算，含零点偏置与负净重抑制","internal-design",1,"A1","简单"),
("FC_DL_WeighTareDriftCheck","DL_Process","皮重漂移超限判定（滑动均值对比标定值）","internal-design",2,"A1","简单"),
("FC_DL_WeighDoseTolBand","DL_Process","配料公差带判定（欠/合格/超），含最小有效量阈值","internal-design",2,"A1","简单"),
("FB_DL_WeighHopperRefillSeq","DL_Process","料斗补料状态机（空闲/开阀/粗加/精加/稳定/超时）","internal-design",3,"A1","简单"),
("FC_DL_WeighMultiHeadSum","DL_Process","多头秤组合求和与最优组合挑选（小数组）","internal-design",2,"A1","简单"),
("FC_DL_WeighBatchYieldCalc","DL_Process","批产率计算（实际投料/理论投料），含除零保护","internal-design",1,"A1","简单"),
("FC_DL_WeighCreepCompensate","DL_Process","蠕变补偿（按加载时长线性修正系数）","internal-design",1,"A1","简单"),
("FC_DL_WeighSpanCalibRatio","DL_Process","量程标定比值计算与合理性校验（对标 OSCAT F_LIN 线性缩放语义）","queue:oscatBasic/F_LIN green",1,"A1","简单"),
("FC_DL_HydroCylForceCalc","DL_Device","液压缸推力/拉力计算（含背压与机械效率）","internal-design",1,"B1","简单"),
("FC_DL_HydroCylFlowNeed","DL_Device","液压缸所需流量与阀口通流能力校核","internal-design",1,"B1","简单"),
("FC_DL_HydroAccumulatorSizing","DL_Device","蓄能器容积估算（绝热/等温双口径）","internal-design",3,"B1","简单"),
("FC_DL_PneuAirConsumeCalc","DL_Device","气缸单次行程耗气量（标准状态折算）","internal-design",1,"B1","简单"),
("FC_DL_PneuCvFlowCalc","DL_Device","Cv 值→额定流量换算（含压差比临界判断）","internal-design",2,"B1","简单"),
("FC_DL_HydroPipePressDrop","DL_Device","管路沿程压降（达西-魏斯巴赫简化）","internal-design",2,"B1","简单"),
("FB_DL_HydroPressRampSeq","DL_Device","液压建压/卸压斜坡状态机（含超时与泄压确认）","internal-design",3,"B1","简单"),
("FC_DL_PneuLeakRateCalc","DL_Device","气路泄漏率估算（压降法，含温度修正）","internal-design",2,"B1","简单"),
("FC_DL_RefCopCalc","DL_Device","制冷 COP/EER 计算（含功率为零保护）","internal-design",1,"C1","简单"),
("FC_DL_RefSuperheatCalc","DL_Device","吸气过热度计算与异常判别","internal-design",1,"C1","简单"),
("FC_DL_RefSubcoolCalc","DL_Device","过冷度计算与充注量倾向判据","internal-design",1,"C1","简单"),
("FC_DL_RefSatPressToTemp","DL_Device","制冷剂饱和压力→温度（R134a/R410A 双系数表）","internal-design",2,"C1","简单"),
("FC_DL_RefSatTempToPress","DL_Device","制冷剂饱和温度→压力（分段线性反查）","internal-design",2,"C1","简单"),
("FC_DL_RefCompressorCapacity","DL_Device","压缩机实际输气量与容积效率估算","internal-design",3,"C1","简单"),
("FC_DL_RefCondApproach","DL_Device","冷凝器逼近温差与脏堵趋势判定","internal-design",2,"C1","简单"),
("FC_DL_StatsRangeCalc","DL_MathData","数组极差（max-min）与有效样本数","internal-design",1,"D1","简单"),
("FC_DL_StatsIqrCalc","DL_MathData","四分位距 IQR 与 Tukey 栅栏上下界","internal-design",2,"D1","简单"),
("FC_DL_StatsPooledStd","DL_MathData","两组合并标准差（pooled），含组内方差为负防护","internal-design",2,"D1","简单"),
("FC_DL_StatsRollingVar","DL_MathData","固定窗滚动方差（环形缓冲，O(1) 更新）","internal-design",3,"D1","简单"),
("FC_DL_StatsGeoMeanCalc","DL_MathData","几何均值（对数域累加，含非正值剔除）","internal-design",2,"D1","简单"),
("FC_DL_StatsDevSumSq","DL_MathData","离差平方和与自由度（供回归/ANOVA 复用）","internal-design",1,"D1","简单"),
("FC_DL_MembraneFluxCalc","DL_Process","膜通量 LMH 计算与衰减率","internal-design",1,"E1","简单"),
("FC_DL_MembraneTmpCalc","DL_Process","跨膜压差 TMP（含平均压力口径双选）","internal-design",1,"E1","简单"),
("FC_DL_WaterRecoveryRatio","DL_Process","系统回收率（产水/进水），含浓水侧校核","internal-design",1,"E1","简单"),
("FC_DL_SludgeAgeCalc","DL_Process","污泥龄 SRT（泥量/排泥速率），含除零保护","internal-design",2,"E1","简单"),
("FC_DL_DoDeficitCalc","DL_Process","溶解氧偏差与曝气需求趋势判据","internal-design",1,"E1","简单"),
("FC_DL_CoagulantDoseCalc","DL_Process","混凝剂投加量（按浊度/流量前馈）","internal-design",2,"E1","简单"),
("FC_DL_WaterLangelierIndex","DL_Process","朗格利尔饱和指数 LSI 结垢/腐蚀判定","internal-design",3,"E1","简单"),
("FB_DL_MultiTankBlendSeq","DL_Process","多罐调和序列（进料/循环/取样/放行），ENUM+CASE 全出口","internal-design",4,"X1","复杂"),
("FB_DL_ConveyorMergePrioritySeq","DL_Process","汇流合流优先权仲裁（含防堵车与抢占恢复）","internal-design",3,"X1","复杂"),
("FB_DL_DryerZoneProfileSeq","DL_Process","多温区烘干升温曲线执行（斜率限制+超温退避）","internal-design",4,"X1","复杂"),
("FB_DL_RefDefrostCycleSeq","DL_Device","冷风机除霜循环（判霜/融霜/滴水/恢复），含超时兜底","internal-design",4,"X1","复杂"),
]

L = []
L.append("# ROUND_PLAN_R80 — 道莅万级工业代码库 第 80 轮\n\n")
L.append("> 轮次：R80 | 开始 2026-11-24T05:41+08:00 | 模式：**冲刺（复杂≤4）**\n")
L.append("> 触发依据：今日累计 44/300，本轮为当日第 2 轮，进度基准 2x38=76 → 44<76 触发冲刺模式\n")
L.append("> 修复配额：0 件（非当日首轮，按产能铁律归零）\n\n")
L.append("## 一、盘点\n\n| 指标 | 值 |\n|---|---|\n")
L.append("| 总库 | 1,453 / 10,000（14.53%） |\n")
L.append("| 今日（11-24） | 44 / 300（14.7%） |\n")
L.append("| JSONL 语料 | 1,492 行 |\n")
L.append("| 开源队列 | 92 条（绿 69 / 黄 23 / 红 0） |\n")
L.append("| 上轮 L2 终裁通过率 | 100%（44/44，零豁免） |\n")
L.append("| 缺口与剩余轮次 | 全日缺 256；按 3h/轮 余约 6 轮 → 需 42.7 件/轮 |\n\n")
L.append("## 二、目标 40 件全表\n\n")
L.append("| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |\n|---|---|---|---|---|---|---|---|---|\n")
for i, (n, c, f, s, cx, b, t) in enumerate(rows, 1):
    pre = n.split("_")[2] if n.count("_") >= 2 else n
    L.append("| %d | %s | %s | %s | %s | %s | C%d | %s | %s |\n" % (i, n, c, pre, f, s, cx, b, t))
L.append("\n## 三、成族组织（简单件按族连号，编码席单次调用批量写盘）\n\n")
fam = [("A1", "称重配料族 8 件（FCx7 + FBx1）"),
       ("B1", "液压气动族 8 件（FCx7 + FBx1）"),
       ("C1", "制冷冷媒族 7 件（全 FC）"),
       ("D1", "统计离散族 6 件（全 FC）"),
       ("E1", "水处理族 7 件（全 FC）"),
       ("X1", "复杂工艺序列 4 件（全 FB）")]
for k, v in fam:
    L.append("- **%s** %s\n" % (k, v))
L.append("\n简单 36 / 复杂 4 = 简单占比 **90%**（≥28 达标，≥70% 铁律超额）\n\n")
L.append("## 四、撞名与语义三查结论\n\n")
L.append("- 40 个名称全部对 1,453 条 registry 做精确匹配：**零精确撞名**。\n")
L.append("- 词根近邻扫描：`FB_DL_ConveyorMergePrioritySeq` 与 `ConveyorAccumGateSeq/ConveyorMetalDetect` 词根近邻，但语义为「汇流仲裁」而非「累积/检测」，判为有效新件；`FC_DL_StatsGeoMeanCalc` 与队列 `HYPOT` 语义不同（几何均值 vs 斜边）。\n")
L.append("- 首版候选已驳回 4 组：`FC_DL_StatsOutlierCount`（精确撞库）、`FB_DL_TankFarmRoutingSeq`（↔TankFarmTransferSeq 同义）、`FB_DL_BatchRecipeSwitchSeq`（↔RecipeSwitchHandover 同义）、OEE 四件族（↔OeeCalculator/TaktPaceMonitor 同义）→ 已整族替换为水处理族 + 回转几何族。\n")
L.append("- R79 教训应用：规划期即做族级词根穷举，赛道全部避开已饱和的通用数学/滤波/限幅/日历/数论。\n\n")
L.append("## 五、里程碑检查点\n\n| 检查点 | 要求 | 实际 |\n|---|---|---|\n")
L.append("| T+15' | 规划表落盘 | 05:52 落盘（T+11'） |\n")
L.append("| T+40' | 编码交付 ≥28 | 待填 |\n")
L.append("| T+50' | 闸裁决 ≥28 | 待填 |\n")
L.append("| T+60' | 入库+战报完成 | 待填 |\n")

open(r"C:\Library\_Staging_Raw\2026-11-24\ROUND_PLAN_R80.md", "w", encoding="utf-8").write("".join(L))
print("plan written rows=%d" % len(rows))
