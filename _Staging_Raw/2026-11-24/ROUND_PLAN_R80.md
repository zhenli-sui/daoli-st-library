# ROUND_PLAN_R80 — 道莅万级工业代码库 第 80 轮

> 轮次：R80 | 开始 2026-11-24T05:41+08:00 | 模式：**冲刺（复杂≤4）**
> 触发依据：今日累计 44/300，本轮为当日第 2 轮，进度基准 2x38=76 → 44<76 触发冲刺模式
> 修复配额：0 件（非当日首轮，按产能铁律归零）

## 一、盘点

| 指标 | 值 |
|---|---|
| 总库 | 1,453 / 10,000（14.53%） |
| 今日（11-24） | 44 / 300（14.7%） |
| JSONL 语料 | 1,492 行 |
| 开源队列 | 92 条（绿 69 / 黄 23 / 红 0） |
| 上轮 L2 终裁通过率 | 100%（44/44，零豁免） |
| 缺口与剩余轮次 | 全日缺 256；按 3h/轮 余约 6 轮 → 需 42.7 件/轮 |

## 二、目标 40 件全表

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_WeighNetFromGross | DL_Process | WeighNetFromGross | 毛重/皮重→净重换算，含零点偏置与负净重抑制 | internal-design | C1 | A1 | 简单 |
| 2 | FC_DL_WeighTareDriftCheck | DL_Process | WeighTareDriftCheck | 皮重漂移超限判定（滑动均值对比标定值） | internal-design | C2 | A1 | 简单 |
| 3 | FC_DL_WeighDoseTolBand | DL_Process | WeighDoseTolBand | 配料公差带判定（欠/合格/超），含最小有效量阈值 | internal-design | C2 | A1 | 简单 |
| 4 | FB_DL_WeighHopperRefillSeq | DL_Process | WeighHopperRefillSeq | 料斗补料状态机（空闲/开阀/粗加/精加/稳定/超时） | internal-design | C3 | A1 | 简单 |
| 5 | FC_DL_WeighMultiHeadSum | DL_Process | WeighMultiHeadSum | 多头秤组合求和与最优组合挑选（小数组） | internal-design | C2 | A1 | 简单 |
| 6 | FC_DL_WeighBatchYieldCalc | DL_Process | WeighBatchYieldCalc | 批产率计算（实际投料/理论投料），含除零保护 | internal-design | C1 | A1 | 简单 |
| 7 | FC_DL_WeighCreepCompensate | DL_Process | WeighCreepCompensate | 蠕变补偿（按加载时长线性修正系数） | internal-design | C1 | A1 | 简单 |
| 8 | FC_DL_WeighSpanCalibRatio | DL_Process | WeighSpanCalibRatio | 量程标定比值计算与合理性校验（对标 OSCAT F_LIN 线性缩放语义） | queue:oscatBasic/F_LIN green | C1 | A1 | 简单 |
| 9 | FC_DL_HydroCylForceCalc | DL_Device | HydroCylForceCalc | 液压缸推力/拉力计算（含背压与机械效率） | internal-design | C1 | B1 | 简单 |
| 10 | FC_DL_HydroCylFlowNeed | DL_Device | HydroCylFlowNeed | 液压缸所需流量与阀口通流能力校核 | internal-design | C1 | B1 | 简单 |
| 11 | FC_DL_HydroAccumulatorSizing | DL_Device | HydroAccumulatorSizing | 蓄能器容积估算（绝热/等温双口径） | internal-design | C3 | B1 | 简单 |
| 12 | FC_DL_PneuAirConsumeCalc | DL_Device | PneuAirConsumeCalc | 气缸单次行程耗气量（标准状态折算） | internal-design | C1 | B1 | 简单 |
| 13 | FC_DL_PneuCvFlowCalc | DL_Device | PneuCvFlowCalc | Cv 值→额定流量换算（含压差比临界判断） | internal-design | C2 | B1 | 简单 |
| 14 | FC_DL_HydroPipePressDrop | DL_Device | HydroPipePressDrop | 管路沿程压降（达西-魏斯巴赫简化） | internal-design | C2 | B1 | 简单 |
| 15 | FB_DL_HydroPressRampSeq | DL_Device | HydroPressRampSeq | 液压建压/卸压斜坡状态机（含超时与泄压确认） | internal-design | C3 | B1 | 简单 |
| 16 | FC_DL_PneuLeakRateCalc | DL_Device | PneuLeakRateCalc | 气路泄漏率估算（压降法，含温度修正） | internal-design | C2 | B1 | 简单 |
| 17 | FC_DL_RefCopCalc | DL_Device | RefCopCalc | 制冷 COP/EER 计算（含功率为零保护） | internal-design | C1 | C1 | 简单 |
| 18 | FC_DL_RefSuperheatCalc | DL_Device | RefSuperheatCalc | 吸气过热度计算与异常判别 | internal-design | C1 | C1 | 简单 |
| 19 | FC_DL_RefSubcoolCalc | DL_Device | RefSubcoolCalc | 过冷度计算与充注量倾向判据 | internal-design | C1 | C1 | 简单 |
| 20 | FC_DL_RefSatPressToTemp | DL_Device | RefSatPressToTemp | 制冷剂饱和压力→温度（R134a/R410A 双系数表） | internal-design | C2 | C1 | 简单 |
| 21 | FC_DL_RefSatTempToPress | DL_Device | RefSatTempToPress | 制冷剂饱和温度→压力（分段线性反查） | internal-design | C2 | C1 | 简单 |
| 22 | FC_DL_RefCompressorCapacity | DL_Device | RefCompressorCapacity | 压缩机实际输气量与容积效率估算 | internal-design | C3 | C1 | 简单 |
| 23 | FC_DL_RefCondApproach | DL_Device | RefCondApproach | 冷凝器逼近温差与脏堵趋势判定 | internal-design | C2 | C1 | 简单 |
| 24 | FC_DL_StatsRangeCalc | DL_MathData | StatsRangeCalc | 数组极差（max-min）与有效样本数 | internal-design | C1 | D1 | 简单 |
| 25 | FC_DL_StatsIqrCalc | DL_MathData | StatsIqrCalc | 四分位距 IQR 与 Tukey 栅栏上下界 | internal-design | C2 | D1 | 简单 |
| 26 | FC_DL_StatsPooledStd | DL_MathData | StatsPooledStd | 两组合并标准差（pooled），含组内方差为负防护 | internal-design | C2 | D1 | 简单 |
| 27 | FC_DL_StatsRollingVar | DL_MathData | StatsRollingVar | 固定窗滚动方差（环形缓冲，O(1) 更新） | internal-design | C3 | D1 | 简单 |
| 28 | FC_DL_StatsGeoMeanCalc | DL_MathData | StatsGeoMeanCalc | 几何均值（对数域累加，含非正值剔除） | internal-design | C2 | D1 | 简单 |
| 29 | FC_DL_StatsDevSumSq | DL_MathData | StatsDevSumSq | 离差平方和与自由度（供回归/ANOVA 复用） | internal-design | C1 | D1 | 简单 |
| 30 | FC_DL_MembraneFluxCalc | DL_Process | MembraneFluxCalc | 膜通量 LMH 计算与衰减率 | internal-design | C1 | E1 | 简单 |
| 31 | FC_DL_MembraneTmpCalc | DL_Process | MembraneTmpCalc | 跨膜压差 TMP（含平均压力口径双选） | internal-design | C1 | E1 | 简单 |
| 32 | FC_DL_WaterRecoveryRatio | DL_Process | WaterRecoveryRatio | 系统回收率（产水/进水），含浓水侧校核 | internal-design | C1 | E1 | 简单 |
| 33 | FC_DL_SludgeAgeCalc | DL_Process | SludgeAgeCalc | 污泥龄 SRT（泥量/排泥速率），含除零保护 | internal-design | C2 | E1 | 简单 |
| 34 | FC_DL_DoDeficitCalc | DL_Process | DoDeficitCalc | 溶解氧偏差与曝气需求趋势判据 | internal-design | C1 | E1 | 简单 |
| 35 | FC_DL_CoagulantDoseCalc | DL_Process | CoagulantDoseCalc | 混凝剂投加量（按浊度/流量前馈） | internal-design | C2 | E1 | 简单 |
| 36 | FC_DL_WaterLangelierIndex | DL_Process | WaterLangelierIndex | 朗格利尔饱和指数 LSI 结垢/腐蚀判定 | internal-design | C3 | E1 | 简单 |
| 37 | FB_DL_MultiTankBlendSeq | DL_Process | MultiTankBlendSeq | 多罐调和序列（进料/循环/取样/放行），ENUM+CASE 全出口 | internal-design | C4 | X1 | 复杂 |
| 38 | FB_DL_ConveyorMergePrioritySeq | DL_Process | ConveyorMergePrioritySeq | 汇流合流优先权仲裁（含防堵车与抢占恢复） | internal-design | C3 | X1 | 复杂 |
| 39 | FB_DL_DryerZoneProfileSeq | DL_Process | DryerZoneProfileSeq | 多温区烘干升温曲线执行（斜率限制+超温退避） | internal-design | C4 | X1 | 复杂 |
| 40 | FB_DL_RefDefrostCycleSeq | DL_Device | RefDefrostCycleSeq | 冷风机除霜循环（判霜/融霜/滴水/恢复），含超时兜底 | internal-design | C4 | X1 | 复杂 |

## 三、成族组织（简单件按族连号，编码席单次调用批量写盘）

- **A1** 称重配料族 8 件（FCx7 + FBx1）
- **B1** 液压气动族 8 件（FCx7 + FBx1）
- **C1** 制冷冷媒族 7 件（全 FC）
- **D1** 统计离散族 6 件（全 FC）
- **E1** 水处理族 7 件（全 FC）
- **X1** 复杂工艺序列 4 件（全 FB）

简单 36 / 复杂 4 = 简单占比 **90%**（≥28 达标，≥70% 铁律超额）

## 四、撞名与语义三查结论

- 40 个名称全部对 1,453 条 registry 做精确匹配：**零精确撞名**。
- 词根近邻扫描：`FB_DL_ConveyorMergePrioritySeq` 与 `ConveyorAccumGateSeq/ConveyorMetalDetect` 词根近邻，但语义为「汇流仲裁」而非「累积/检测」，判为有效新件；`FC_DL_StatsGeoMeanCalc` 与队列 `HYPOT` 语义不同（几何均值 vs 斜边）。
- 首版候选已驳回 4 组：`FC_DL_StatsOutlierCount`（精确撞库）、`FB_DL_TankFarmRoutingSeq`（↔TankFarmTransferSeq 同义）、`FB_DL_BatchRecipeSwitchSeq`（↔RecipeSwitchHandover 同义）、OEE 四件族（↔OeeCalculator/TaktPaceMonitor 同义）→ 已整族替换为水处理族 + 回转几何族。
- R79 教训应用：规划期即做族级词根穷举，赛道全部避开已饱和的通用数学/滤波/限幅/日历/数论。

## 五、里程碑检查点

| 检查点 | 要求 | 实际 |
|---|---|---|
| T+15' | 规划表落盘 | 05:52 落盘（T+11'） |
| T+40' | 编码交付 ≥28 | 待填 |
| T+50' | 闸裁决 ≥28 | 待填 |
| T+60' | 入库+战报完成 | 待填 |
