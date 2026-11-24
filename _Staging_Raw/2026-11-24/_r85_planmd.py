# -*- coding: utf-8 -*-
import json, io, sys, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
T = json.load(open(r'C:\Library\_Staging_Raw\2026-11-24\r85_targets.json', encoding='utf-8'))
CN = {
 'FC_DL_QuenchOilTempRiseCalc': '淬火油槽温升与换热负荷计算',
 'FC_DL_AustenitizeHoldTimeCalc': '奥氏体化保温时间（有效厚度法）',
 'FC_DL_CarburizeCaseDepthCalc': '气体渗碳层深 Harris 公式与时间反算',
 'FC_DL_TemperEmpiricalHardnessCalc': '回火温度-硬度经验曲线插值',
 'FB_DL_InductionHardeningScanCtrl': '感应淬火扫描加热与喷淋时序',
 'FB_DL_QuenchTankAgitatorCtrl': '淬火槽搅拌器分级投运与油温联锁',
 'FC_DL_MartensiteFinishTempCalc': '马氏体终了温度 Ms/Mf 经验式',
 'FB_DL_SoakPitTemperatureCtrl': '坑式炉均热控制与保温计时',
 'FC_DL_ExtrusionBilletHeatCalc': '铝挤压铸锭感应加热功率与能耗',
 'FC_DL_ExtrusionSpecificPressureCalc': '挤压比压与挤压比计算',
 'FC_DL_AnodizeBathChargeCalc': '阳极氧化法拉第电量与电流密度',
 'FC_DL_ExtrusionDieWearIndexCalc': '挤压模磨损指数与剩余寿命',
 'FB_DL_AnodizeRinseCascadeCtrl': '阳极氧化逆流漂洗级联补水',
 'FB_DL_BilletShearGaugeSeq': '铸锭定尺剪切与去头尾时序',
 'FC_DL_AnodizeFilmThicknessCalc': '阳极氧化膜厚-电量换算',
 'FC_DL_AnodizeSealBoilTimeCalc': '沸水封孔时间与 pH 窗口判定',
 'FC_DL_DieCastShotVelocityCalc': '压射速度（PQ² 交点与充填时间）',
 'FC_DL_DieCastIntensifyPressureCalc': '增压比压与锁模力校验',
 'FC_DL_DieThermalBalanceCalc': '压铸模热平衡与模温机负荷',
 'FC_DL_CastingSolidificationTimeCalc': 'Chvorinov 凝固时间与模数',
 'FB_DL_DieSprayReleaseSeq': '喷涂脱模剂与吹扫时序',
 'FB_DL_LadlePourWeightCtrl': '浇包定量浇注重量闭环',
 'FC_DL_DieCastPorosityRiskIndexCalc': '压铸气孔风险指数',
 'FC_DL_PowderFillDensityCalc': '装粉松装密度与填充高度',
 'FC_DL_CompactionPressureCalc': '压制压力与压坯密度关系',
 'FB_DL_SinterFurnaceRampCtrl': '烧结炉升温曲线跟踪与露点联锁',
 'FC_DL_GreenStrengthIndexCalc': '生坯强度指数与脱模安全',
 'FC_DL_SinterShrinkageCalc': '烧结线收缩率与尺寸补偿',
 'FB_DL_PowderBlendDoseSeq': '混粉配料称量与放料时序',
 'FC_DL_DelubeResidualCarbonCalc': '润滑剂烧除残碳估算与判定',
 'FC_DL_MashStrikeWaterTempCalc': '糖化投料水温与醪液平衡',
 'FC_DL_WortExtractYieldCalc': '麦汁收得率与糖化效率',
 'FC_DL_SugarBoilSupersaturationCalc': '煮糖过饱和度与晶核窗口',
 'FC_DL_MolassesExhaustionCalc': '废蜜纯度与糖分排出率',
 'FB_DL_CrystallizerVacuumCtrl': '结晶罐真空度与沸点升高控制',
 'FB_DL_CipCaneJuiceLineSeq': '蔗汁线 CIP 五步时序与回液判定',
 'FB_DL_QuenchTemperLineSeq': '淬火-回火联动线全流程状态机',
 'FB_DL_AnodizeLineTransferSeq': '阳极氧化线行车转序与槽位互锁',
 'FB_DL_DieCastCycleSupervise': '压铸单循环监控与异常分级停机',
 'FB_DL_SugarPanBatchSeq': '煮糖罐批次进料-浓缩-助晶-放糖时序',
}
FAM = {'A': '金属热处理（淬火/回火/渗碳/感应）', 'B': '铝型材挤压与阳极氧化',
       'C': '压铸/重力铸造', 'D': '粉末冶金与烧结', 'E': '酿造/制糖（糖化·煮糖）'}
L = []
L.append('# ROUND_PLAN_R85 —— 道莅万级工业代码库 & AI 训练集工厂\n')
L.append('- 轮次：R85 ｜ 模式：**冲刺模式**（今日 238 < 轮次序号 7×38=266 → 复杂件上限 4）')
L.append('- 起跑：2026-11-24T18:48:30+08:00 ｜ 目标：40 件（复杂 4 / 简单 36，简单占 90%）')
L.append('- 修复配额：**0**（非当日首轮，遵守产能铁律一；存量 4 件 FOR..DOWNTO 顺延次日首轮）')
L.append('- 起跑基线：registry 1,646 ｜ 磁盘 .st 1,646 ｜ **差集 0** ｜ 今日 238/300 ｜ 总库 16.46%')
L.append('- 族选题依据：词根饱和度实测 —— Ceramic/Extrus/Sinter/Quench/Carbur/DieCast/Brew/Sugar/Malt 命中均 **0**，属真空域；避开已饱和通用层。')
L.append('')
L.append('## 一、40 个目标全表\n')
L.append('| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |')
L.append('|---|---|---|---|---|---|---|---|---|')
for i, t in enumerate(T, 1):
    pre = t['name'].split('_')[1]
    src = 'clean-room 自研' if i % 3 else 'OSS 队列（语义邻域）'
    tier = '复杂' if t['complexity'] >= 3 else '简单'
    batch = 'C1' if t['complexity'] >= 3 else ('S1' if i <= 10 else 'S2' if i <= 20 else 'S3')
    L.append(f"| {i} | `{t['name']}` | {t['category']} | {pre} | {CN.get(t['name'], t['desc_en'])} | {src} | C{t['complexity']} | {batch} | {tier} |")
L.append('')
L.append('## 二、族结构（简单件按族连号，编码席单次调用批量派生）\n')
L.append('| 族 | 主题 | 件数 | 分类分布 | 复杂件 |')
L.append('|---|---|---|---|---|')
for f in 'ABCDE':
    sub = [t for t in T if t['family'] == f]
    simp = [t for t in sub if t['complexity'] < 3]
    cplx = [t for t in sub if t['complexity'] >= 3]
    cat = {}
    for t in simp: cat[t['category']] = cat.get(t['category'], 0) + 1
    L.append(f"| {f} | {FAM[f]} | {len(simp)} 简单 | {', '.join(f'{k}×{v}' for k, v in cat.items())} | {', '.join(f'`{x[chr(110)+chr(97)+chr(109)+chr(101)]}`' for x in cplx)} |")
L.append('')
L.append('## 三、撞名三查结果\n')
L.append('- 规划期 token 交集扫描（≥2 个非通用 token 命中即驳回）：首轮 **5 命中** → 改名 5 件；二轮复检 **1 命中** → 再改 1 件；**终版 40 名 0 撞名**。')
L.append('- 改名留痕：`FB_DL_FurnaceZoneSoakCtrl`→`FB_DL_SoakPitTemperatureCtrl`（↔FiringFurnaceZone，两度改名）｜`FC_DL_ExtrusionPressForceCalc`→`FC_DL_ExtrusionSpecificPressureCalc`（↔PressForceCurveExec）｜`FB_DL_BilletCutLengthSeq`→`FB_DL_BilletShearGaugeSeq`（↔CutLengthDeviationCalc）｜`FB_DL_SinterZoneProfileCtrl`→`FB_DL_SinterFurnaceRampCtrl`（↔DryerZoneProfileSeq）｜`FC_DL_DewPointLubricantBurnoffCalc`→`FC_DL_DelubeResidualCarbonCalc`（↔DewPointToPpmV / DewPointSpreadCalc）。')
L.append('- 磁盘差集前置：registry 1,646 ≡ 磁盘 .st 1,646，差集 0，无重复写已存在文件风险。')
L.append('')
L.append('## 四、里程碑检查点（T=18:48:30）\n')
L.append('| 检查点 | 时点 | 目标 |')
L.append('|---|---|---|')
L.append('| 规划表落盘 | T+15′ ≤19:03 | 本文件 |')
L.append('| 编码交付 ≥28 件 | T+40′ ≤19:28 | 不足即转简单件冲刺 |')
L.append('| 编译闸裁决 ≥28 件 | T+50′ ≤19:38 | 闸席原生裁决 |')
L.append('| 入库与战报完成 | T+60′ ≤19:48 | registry/JSONL/.st 三方对账 |')
open(r'C:\Library\_Staging_Raw\2026-11-24\ROUND_PLAN_R85.md', 'w', encoding='utf-8').write('\n'.join(L))
print('plan written', len(L), 'lines')
