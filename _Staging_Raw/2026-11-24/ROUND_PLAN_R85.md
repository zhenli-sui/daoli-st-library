# ROUND_PLAN_R85 —— 道莅万级工业代码库 & AI 训练集工厂

- 轮次：R85 ｜ 模式：**冲刺模式**（今日 238 < 轮次序号 7×38=266 → 复杂件上限 4）
- 起跑：2026-11-24T18:48:30+08:00 ｜ 目标：40 件（复杂 4 / 简单 36，简单占 90%）
- 修复配额：**0**（非当日首轮，遵守产能铁律一；存量 4 件 FOR..DOWNTO 顺延次日首轮）
- 起跑基线：registry 1,646 ｜ 磁盘 .st 1,646 ｜ **差集 0** ｜ 今日 238/300 ｜ 总库 16.46%
- 族选题依据：词根饱和度实测 —— Ceramic/Extrus/Sinter/Quench/Carbur/DieCast/Brew/Sugar/Malt 命中均 **0**，属真空域；避开已饱和通用层。

## 一、40 个目标全表

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_QuenchOilTempRiseCalc` | DL_Process | DL | 淬火油槽温升与换热负荷计算 | clean-room 自研 | C2 | S1 | 简单 |
| 2 | `FC_DL_AustenitizeHoldTimeCalc` | DL_Process | DL | 奥氏体化保温时间（有效厚度法） | clean-room 自研 | C2 | S1 | 简单 |
| 3 | `FC_DL_CarburizeCaseDepthCalc` | DL_Process | DL | 气体渗碳层深 Harris 公式与时间反算 | OSS 队列（语义邻域） | C2 | S1 | 简单 |
| 4 | `FC_DL_TemperEmpiricalHardnessCalc` | DL_Process | DL | 回火温度-硬度经验曲线插值 | clean-room 自研 | C2 | S1 | 简单 |
| 5 | `FB_DL_InductionHardeningScanCtrl` | DL_Device | DL | 感应淬火扫描加热与喷淋时序 | clean-room 自研 | C2 | S1 | 简单 |
| 6 | `FB_DL_QuenchTankAgitatorCtrl` | DL_Device | DL | 淬火槽搅拌器分级投运与油温联锁 | OSS 队列（语义邻域） | C2 | S1 | 简单 |
| 7 | `FC_DL_MartensiteFinishTempCalc` | DL_MathData | DL | 马氏体终了温度 Ms/Mf 经验式 | clean-room 自研 | C1 | S1 | 简单 |
| 8 | `FB_DL_SoakPitTemperatureCtrl` | DL_Device | DL | 坑式炉均热控制与保温计时 | clean-room 自研 | C2 | S1 | 简单 |
| 9 | `FC_DL_ExtrusionBilletHeatCalc` | DL_Process | DL | 铝挤压铸锭感应加热功率与能耗 | OSS 队列（语义邻域） | C2 | S1 | 简单 |
| 10 | `FC_DL_ExtrusionSpecificPressureCalc` | DL_Process | DL | 挤压比压与挤压比计算 | clean-room 自研 | C2 | S1 | 简单 |
| 11 | `FC_DL_AnodizeBathChargeCalc` | DL_Process | DL | 阳极氧化法拉第电量与电流密度 | clean-room 自研 | C2 | S2 | 简单 |
| 12 | `FC_DL_ExtrusionDieWearIndexCalc` | DL_Process | DL | 挤压模磨损指数与剩余寿命 | OSS 队列（语义邻域） | C2 | S2 | 简单 |
| 13 | `FB_DL_AnodizeRinseCascadeCtrl` | DL_Device | DL | 阳极氧化逆流漂洗级联补水 | clean-room 自研 | C2 | S2 | 简单 |
| 14 | `FB_DL_BilletShearGaugeSeq` | DL_Device | DL | 铸锭定尺剪切与去头尾时序 | clean-room 自研 | C2 | S2 | 简单 |
| 15 | `FC_DL_AnodizeFilmThicknessCalc` | DL_MathData | DL | 阳极氧化膜厚-电量换算 | OSS 队列（语义邻域） | C1 | S2 | 简单 |
| 16 | `FC_DL_AnodizeSealBoilTimeCalc` | DL_Process | DL | 沸水封孔时间与 pH 窗口判定 | clean-room 自研 | C1 | S2 | 简单 |
| 17 | `FC_DL_DieCastShotVelocityCalc` | DL_Process | DL | 压射速度（PQ² 交点与充填时间） | clean-room 自研 | C2 | S2 | 简单 |
| 18 | `FC_DL_DieCastIntensifyPressureCalc` | DL_Process | DL | 增压比压与锁模力校验 | OSS 队列（语义邻域） | C2 | S2 | 简单 |
| 19 | `FC_DL_DieThermalBalanceCalc` | DL_Process | DL | 压铸模热平衡与模温机负荷 | clean-room 自研 | C2 | S2 | 简单 |
| 20 | `FC_DL_CastingSolidificationTimeCalc` | DL_Process | DL | Chvorinov 凝固时间与模数 | clean-room 自研 | C1 | S2 | 简单 |
| 21 | `FB_DL_DieSprayReleaseSeq` | DL_Device | DL | 喷涂脱模剂与吹扫时序 | OSS 队列（语义邻域） | C2 | S3 | 简单 |
| 22 | `FB_DL_LadlePourWeightCtrl` | DL_Device | DL | 浇包定量浇注重量闭环 | clean-room 自研 | C2 | S3 | 简单 |
| 23 | `FC_DL_DieCastPorosityRiskIndexCalc` | DL_Device | DL | 压铸气孔风险指数 | clean-room 自研 | C2 | S3 | 简单 |
| 24 | `FC_DL_PowderFillDensityCalc` | DL_Process | DL | 装粉松装密度与填充高度 | OSS 队列（语义邻域） | C1 | S3 | 简单 |
| 25 | `FC_DL_CompactionPressureCalc` | DL_Process | DL | 压制压力与压坯密度关系 | clean-room 自研 | C2 | S3 | 简单 |
| 26 | `FB_DL_SinterFurnaceRampCtrl` | DL_Process | DL | 烧结炉升温曲线跟踪与露点联锁 | clean-room 自研 | C2 | S3 | 简单 |
| 27 | `FC_DL_GreenStrengthIndexCalc` | DL_Process | DL | 生坯强度指数与脱模安全 | OSS 队列（语义邻域） | C2 | S3 | 简单 |
| 28 | `FC_DL_SinterShrinkageCalc` | DL_MathData | DL | 烧结线收缩率与尺寸补偿 | clean-room 自研 | C1 | S3 | 简单 |
| 29 | `FB_DL_PowderBlendDoseSeq` | DL_Device | DL | 混粉配料称量与放料时序 | clean-room 自研 | C2 | S3 | 简单 |
| 30 | `FC_DL_DelubeResidualCarbonCalc` | DL_Device | DL | 润滑剂烧除残碳估算与判定 | OSS 队列（语义邻域） | C2 | S3 | 简单 |
| 31 | `FC_DL_MashStrikeWaterTempCalc` | DL_Process | DL | 糖化投料水温与醪液平衡 | clean-room 自研 | C2 | S3 | 简单 |
| 32 | `FC_DL_WortExtractYieldCalc` | DL_Process | DL | 麦汁收得率与糖化效率 | clean-room 自研 | C2 | S3 | 简单 |
| 33 | `FC_DL_SugarBoilSupersaturationCalc` | DL_Process | DL | 煮糖过饱和度与晶核窗口 | OSS 队列（语义邻域） | C2 | S3 | 简单 |
| 34 | `FC_DL_MolassesExhaustionCalc` | DL_MathData | DL | 废蜜纯度与糖分排出率 | clean-room 自研 | C1 | S3 | 简单 |
| 35 | `FB_DL_CrystallizerVacuumCtrl` | DL_Device | DL | 结晶罐真空度与沸点升高控制 | clean-room 自研 | C2 | S3 | 简单 |
| 36 | `FB_DL_CipCaneJuiceLineSeq` | DL_Device | DL | 蔗汁线 CIP 五步时序与回液判定 | OSS 队列（语义邻域） | C2 | S3 | 简单 |
| 37 | `FB_DL_QuenchTemperLineSeq` | DL_Process | DL | 淬火-回火联动线全流程状态机 | clean-room 自研 | C4 | C1 | 复杂 |
| 38 | `FB_DL_AnodizeLineTransferSeq` | DL_Device | DL | 阳极氧化线行车转序与槽位互锁 | clean-room 自研 | C4 | C1 | 复杂 |
| 39 | `FB_DL_DieCastCycleSupervise` | DL_Device | DL | 压铸单循环监控与异常分级停机 | OSS 队列（语义邻域） | C4 | C1 | 复杂 |
| 40 | `FB_DL_SugarPanBatchSeq` | DL_Process | DL | 煮糖罐批次进料-浓缩-助晶-放糖时序 | clean-room 自研 | C4 | C1 | 复杂 |

## 二、族结构（简单件按族连号，编码席单次调用批量派生）

| 族 | 主题 | 件数 | 分类分布 | 复杂件 |
|---|---|---|---|---|
| A | 金属热处理（淬火/回火/渗碳/感应） | 8 简单 | DL_Process×4, DL_Device×3, DL_MathData×1 | `FB_DL_QuenchTemperLineSeq` |
| B | 铝型材挤压与阳极氧化 | 8 简单 | DL_Process×5, DL_Device×2, DL_MathData×1 | `FB_DL_AnodizeLineTransferSeq` |
| C | 压铸/重力铸造 | 7 简单 | DL_Process×4, DL_Device×3 | `FB_DL_DieCastCycleSupervise` |
| D | 粉末冶金与烧结 | 7 简单 | DL_Process×4, DL_MathData×1, DL_Device×2 |  |
| E | 酿造/制糖（糖化·煮糖） | 6 简单 | DL_Process×3, DL_MathData×1, DL_Device×2 | `FB_DL_SugarPanBatchSeq` |

## 三、撞名三查结果

- 规划期 token 交集扫描（≥2 个非通用 token 命中即驳回）：首轮 **5 命中** → 改名 5 件；二轮复检 **1 命中** → 再改 1 件；**终版 40 名 0 撞名**。
- 改名留痕：`FB_DL_FurnaceZoneSoakCtrl`→`FB_DL_SoakPitTemperatureCtrl`（↔FiringFurnaceZone，两度改名）｜`FC_DL_ExtrusionPressForceCalc`→`FC_DL_ExtrusionSpecificPressureCalc`（↔PressForceCurveExec）｜`FB_DL_BilletCutLengthSeq`→`FB_DL_BilletShearGaugeSeq`（↔CutLengthDeviationCalc）｜`FB_DL_SinterZoneProfileCtrl`→`FB_DL_SinterFurnaceRampCtrl`（↔DryerZoneProfileSeq）｜`FC_DL_DewPointLubricantBurnoffCalc`→`FC_DL_DelubeResidualCarbonCalc`（↔DewPointToPpmV / DewPointSpreadCalc）。
- 磁盘差集前置：registry 1,646 ≡ 磁盘 .st 1,646，差集 0，无重复写已存在文件风险。

## 四、里程碑检查点（T=18:48:30）

| 检查点 | 时点 | 目标 |
|---|---|---|
| 规划表落盘 | T+15′ ≤19:03 | 本文件 |
| 编码交付 ≥28 件 | T+40′ ≤19:28 | 不足即转简单件冲刺 |
| 编译闸裁决 ≥28 件 | T+50′ ≤19:38 | 闸席原生裁决 |
| 入库与战报完成 | T+60′ ≤19:48 | registry/JSONL/.st 三方对账 |