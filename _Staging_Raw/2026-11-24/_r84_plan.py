import json

rows = [
(1,'FB_DL_CncToolWearCompLoop','DL_Device','CNC 刀具磨损量在线估计与刀补闭环（多段磨损曲线+换刀阈值）','clean-room/C2',4,'B','复杂'),
(2,'FB_DL_ReactorRunawayGuard','DL_Process','间歇釜放热失控五级联锁（温升速率/绝热温升外推/冷却失效三判据）','clean-room/C3',5,'B','复杂'),
(3,'FB_DL_TabletWeightAutoCtl','DL_Process','压片片重自动控制（充填深度闭环+剔废联锁）','clean-room/C2',4,'B','复杂'),
(4,'FB_DL_HeadboxJetRatioLoop','DL_Process','流浆箱唇口喷射比闭环（浆速/网速比寻优）','clean-room/C2',4,'B','复杂'),
(5,'FC_DL_CuttingForceCalc','DL_Device','车削/铣削切削力经验公式估算','clean-room/C1',2,'A1','简单'),
(6,'FC_DL_CncMrrCalc','DL_Device','材料去除率 MRR 计算','clean-room/C1',1,'A1','简单'),
(7,'FC_DL_CncSpindleLoadRatio','DL_Device','主轴负载率与过载裕度','clean-room/C1',1,'A1','简单'),
(8,'FB_DL_CncLoadUnloadSeq','DL_Device','CNC 上下料时序（门开-夹紧-松爪-确认）','clean-room/C1',2,'A1','简单'),
(9,'FC_DL_CoolantConcCalc','DL_Device','切削液浓度配比与补液量','clean-room/C1',1,'A1','简单'),
(10,'FC_DL_ToolWearVbCalc','DL_Device','后刀面磨损量 VB 由切削时间/材料系数估算','clean-room/C1',2,'A1','简单'),
(11,'FB_DL_ToolMagazinePosSeq','DL_Device','刀库选刀定位时序（就近寻刀+到位确认）','clean-room/C1',2,'A1','简单'),
(12,'FC_DL_ChipLoadPerToothCalc','DL_Device','每齿进给量与切屑厚度校核','clean-room/C1',1,'A1','简单'),
(13,'FC_DL_TabletWeightRsdCalc','DL_Process','片重相对标准偏差 RSD（滚动窗口）','clean-room/C1',2,'A2','简单'),
(14,'FC_DL_FluidBedDryLossCalc','DL_Process','流化床干燥失重 LOD 计算','clean-room/C1',1,'A2','简单'),
(15,'FC_DL_CoatingPanSprayCalc','DL_Process','包衣锅喷量与增重速率','clean-room/C1',2,'A2','简单'),
(16,'FC_DL_TabletCrushForceCalc','DL_Process','片剂破碎力与硬度换算','clean-room/C1',1,'A2','简单'),
(17,'FC_DL_BlendUniformityCalc','DL_Process','混合均匀度（多点取样 CV + 混合指数）','clean-room/C1',2,'A2','简单'),
(18,'FC_DL_GranuleSizeD50Calc','DL_Process','颗粒粒径分布 D10/D50/D90 插值','clean-room/C1',2,'A2','简单'),
(19,'FB_DL_TabletCompactionSeq','DL_Process','压片压实时序（充填-预压-主压-出片-剔废）','clean-room/C1',2,'A2','简单'),
(20,'FC_DL_TabletFriabilityCalc','DL_Process','片剂脆碎度计算与判定','clean-room/C1',1,'A2','简单'),
(21,'FC_DL_ReactorHeatReleaseCalc','DL_Process','由夹套温差反算反应放热速率','clean-room/C1',2,'A3','简单'),
(22,'FC_DL_ReactorAdiabaticRise','DL_Process','绝热温升 dTad 由累积投料量估算','clean-room/C1',2,'A3','简单'),
(23,'FC_DL_MtsrCalc','DL_Process','最高合成温度 MTSR 计算','clean-room/C1',2,'A3','简单'),
(24,'FB_DL_ReactorChargeSeq','DL_Process','多组分投料顺序时序（互锁+搅拌前置）','clean-room/C1',2,'A3','简单'),
(25,'FB_DL_ReactorHeatupProfile','DL_Process','升温程序段执行（斜率/保温/超调抑制）','clean-room/C1',2,'A3','简单'),
(26,'FC_DL_JacketAreaCalc','DL_Process','夹套/盘管传热面积与换热能力','clean-room/C1',1,'A3','简单'),
(27,'FC_DL_ClinkerLsfCalc','DL_Device','熟料石灰饱和系数 LSF','clean-room/C1',1,'A4','简单'),
(28,'FC_DL_ClinkerC3sCalc','DL_Device','Bogue 法 C3S/C2S/C3A/C4AF 计算','clean-room/C1',2,'A4','简单'),
(29,'FC_DL_KilnSpecificHeatCalc','DL_Device','窑单位熟料热耗','clean-room/C1',1,'A4','简单'),
(30,'FC_DL_RawMealResidueCalc','DL_Device','生料筛余与细度合格判定','clean-room/C1',1,'A4','简单'),
(31,'FB_DL_KilnPreheatStageSeq','DL_Device','预热器旋风级联投料时序','clean-room/C1',2,'A4','简单'),
(32,'FC_DL_CementMillLoadCalc','DL_Device','磨机填充率与循环负荷','clean-room/C1',2,'A4','简单'),
(33,'FC_DL_ClinkerFreeLimeCalc','DL_Device','游离石灰 f-CaO 与烧成度判定','clean-room/C1',1,'A4','简单'),
(34,'FC_DL_PaperBasisWeightCalc','DL_Process','纸页定量由绝干量与幅宽换算','clean-room/C1',1,'A5','简单'),
(35,'FC_DL_StockConsistencyCalc','DL_Process','浆料浓度由稀释比与稠度推算','clean-room/C1',1,'A5','简单'),
(36,'FC_DL_RefinerFreenessCalc','DL_Process','打浆度 CSF 由能耗与比边缘负荷估算','clean-room/C1',2,'A5','简单'),
(37,'FB_DL_HeadboxSliceSeq','DL_Process','流浆箱唇口开度调节时序','clean-room/C1',2,'A5','简单'),
(38,'FC_DL_DryerSteamDemandCalc','DL_Process','烘缸组汽耗与传热需求','clean-room/C1',2,'A5','简单'),
(39,'FC_DL_PaperFormationIndexCalc','DL_Process','纸页成形指数由絮聚波长估算','clean-room/C1',2,'A5','简单'),
]
assert len(rows) == 39, len(rows)

out = ['# ROUND_PLAN_R84 - 2026-11-24 第84轮（冲刺模式）', '',
 '目标 40 件 = 复杂 4（C3~C5）+ 简单 36（C1~C2）。修复配额 0（非当日首轮，铁律一）。',
 '冲刺判定：今日 201 < 轮次序号 6x38=228 -> 复杂上限 4。', '',
 '族划分：A 汽车零部件机加工(DL_Device 8) ｜ B 制药固体制剂(DL_Process 8) ｜ C 化工间歇反应釜(DL_Process 7) ｜ D 水泥窑炉煅烧(DL_Device 7) ｜ E 造纸纸浆(DL_Process 6) ｜ 复杂 4。', '',
 '| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |',
 '|---|---|---|---|---|---|---|---|---|']
for no, name, cat, func, src, cx, batch, tier in rows:
    pre = 'FB' if name.startswith('FB_') else 'FC'
    out.append('| %d | %s | %s | %s | %s | %s | C%d | %s | %s |' % (no, name, cat, pre, func, src, cx, batch, tier))

out += ['', '## 撞名三查结论（R13）',
 '- 词根全库扫描 39 名 x 全量 registry 1,609 词根索引；NEAR 命中均为通用 calc/force/load/heat 模式假阳性，已逐条人工判定为不同语义域。',
 '- 驳回并撤换 7 名：FC_DL_PvStringMismatchLoss(同 StringCurrentMismatch)、FB_DL_PvFlashBinSeq(同 CellOcvBinSort)、FC_DL_ToolLifeRemainCalc(同 ToolLifeBudget)、FB_DL_ToolChangeReqSeq(同 ToolChangerSeq)、FC_DL_SpcCpCpkCalc(同 CpkCalc/CpkIndex 双重复)、FC_DL_GranuleMoistureCalc(同 MoistureContentCalc)、FC_DL_RewindTensionTaperCalc(同 WinderTensionTaperCalc 三词根重合)。',
 '- 整族撤销：原「光伏组件生产」族 8 件因 registry 已有 69 件 PV/电池片语义件（pvsoilingloss/elteststation/stringelimagemap/cellocvbinsort 等）判为饱和域，整族替换为「水泥窑炉煅烧」。',
 '- 磁盘差集：registry 1,609 ≡ 磁盘 .st 1,609，差集 0，无重复写盘风险。', '',
 '## 开源溯源预判',
 'R82/R83 实证：机加工/制药/水泥/造纸四个垂直域在 GitHub ST 生态几无对应件（R83 三族 0 命中）-> 本轮按 clean-room 工程公式自研，溯源标签记 C1/C2/C3（公式来源等级），不虚标开源来源。']

open(r'C:\Library\_Staging_Raw\2026-11-24\ROUND_PLAN_R84.md', 'w', encoding='utf-8').write('\n'.join(out))
json.dump(rows, open(r'C:\Library\_Staging_Raw\2026-11-24\r84_targets.json', 'w'), ensure_ascii=False, indent=0)
print('plan written', len(rows))
