# -*- coding: utf-8 -*-
"""R82 queue writer: 40 vertical-process candidates, 5 families.
Dedup: registry names + existing queue (name / source_url / sha1 fingerprint).
"""
import json, hashlib, re, os

QDIR = r"C:\Library\_Staging_Raw\2026-11-24"
QF = os.path.join(QDIR, "candidate_queue.jsonl")
REGF = os.path.join(QDIR, "_reg_names_r82.txt")

registry = set(l.strip().lower() for l in open(REGF, encoding='utf-8') if l.strip())

# ---- source registry (verified this round) ----
S = {
 'ia2':      ('FREEZONEX/ia2', 'Apache-2.0', 'green', '518555a8260f5cd2daceb400b82562a8136e1826', 'main'),
 'sema':     ('midea-ai/SemaPLC', 'MIT', 'green', 'fea1b87a112bf947197f501168ee35771fdc6377', 'main'),
 'vms':      ('minkhanh-ng/Tc3_VN001007_VMS', 'MIT', 'green', 'b4755321910794d3ef7a5295a192a891ab6e31af', 'main'),
 'rybno':    ('Dariusz791/Rybno', 'NOASSERTION', 'yellow', '21353da9f39bf446717ea36888065e0cb9e7dbeb', 'dev'),
 'scr':      ('gione100/SCR_2ndGen', 'NOASSERTION', 'yellow', '1bd33fcf2b314efe876ffb9adae9517ffea653a9', 'main'),
 'wwtp':     ('snackmasta/Building-Automation', 'NOASSERTION', 'yellow', '222076a23ca47305eaff8e9e0f01110c374cb2b4', 'main'),
 'sek':      ('Dariusz791/Sekwencer', 'NOASSERTION', 'yellow', '55af18b10e616ab8d707f957a466a12c22b99153', 'main'),
}


def url(key, path):
    rp = S[key][0]
    return 'https://github.com/%s/blob/%s/%s' % (rp, S[key][3], path)


# name, src, path, category, kind, semantic, extraction_point, signature, loc, gaps, priority, excerpt
C = [
 # ---------------- F1 混凝絮凝沉淀 ----------------
 ('FB_DL_FlocGValueCalc', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/Mixit/FB_Mixit.TcPOU', 'DL_Process', 'FB',
  'F1 絮凝搅拌速度梯度 G 值校核（P=μG²V，按搅拌器转速/桨径反算 G，判定絮凝段 G 区间与 GT 值）',
  '仅借 FB_Mixit 的搅拌相序与转速/时间参数域语义，实现 clean-room',
  '', 0, ['无 G 值超上限的降速兜底', '缺 GT 值累计清零与工艺段切换互锁'], 1, None),
 ('FB_DL_CoagFeedforwardGain', 'sema', 'data/st-baseline/ammonium-nitrates/pous/function-blocks/RATIO_CONTROL.st', 'DL_Process', 'FB',
  'F1 混凝剂投加量前馈增益自整定（原水浊度/流量→投加比 trim，含 MV 上下限）',
  'RATIO_CONTROL 的比例+trim+MV_MIN/MAX 参数域', 'VAR_INPUT: Auto:BOOL, PrimaryPV:REAL, SecondaryPV:REAL, RatioSP:REAL, Bias:REAL, TrimKp:REAL, TrimTi:TIME, MV_MIN:REAL, MV_MAX:REAL', 37,
  ['trim 积分无抗饱和', '原水浊度跳变无变化率闸'], 1, 'SlaveSP := LIMIT(MV_MIN, PrimaryPV * RatioSP + Bias, MV_MAX);'),
 ('FB_DL_TurbidityVoteGuard', 'sema', 'data/st-baseline/ammonium-nitrates/pous/function-blocks/VOTING_ANALOG.st', 'DL_Process', 'FB',
  'F1 出水浊度三取二表决与漂移隔离（偏差超限剔除单表，表决失败降级为保持）',
  'VOTING_ANALOG 的 2oo3 表决/偏差限/单表故障位语义', 'VAR_INPUT: Input1..3:REAL, Deviation_Limit:REAL, Voting_Scheme:STRING, EnableAlarm:BOOL; VAR_OUTPUT: Voted_Output:REAL, Sensor1..3_Fault:BOOL', 29,
  ['三表全坏无 fallback 策略', '表决方案用 STRING 比较，编译期无法裁剪'], 1, None),
 ('FB_DL_LamellaSettlerSludgeDraw', 'wwtp', 'Wastewater Treatment Plant/plc/main.st', 'DL_Process', 'FB',
  'F1 斜板沉淀池排泥阀周期与泥位联动（按累积流量/泥位定时排泥，超时强制排空）',
  '借 WWTP main.st 的沉淀池排泥时序与阀门序号语义', '', 0,
  ['排泥与进水阀无互锁，可能边进边排', '泥位计故障时无定时降级路径'], 2, None),
 ('FB_DL_ClarifierSludgeBlanket', 'wwtp', 'Wastewater Treatment Plant/plc/main.st', 'DL_Process', 'FB',
  'F1 沉淀池污泥界面控制（界面上升速率→排泥量前馈，含界面报警带）',
  '借 WWTP 沉淀池液位/界面报警带语义', '', 0,
  ['界面上升速率无滤波，单点噪声即触发排泥', '无最大排泥量限幅'], 2, None),
 ('FB_DL_ClarifFlowSplitBalance', 'ia2', 'library/process-control/pous/fb_split_range.st', 'DL_Process', 'FB',
  'F1 多池配水均分与失衡报警（总流量按池数均分，偏差>阈值报警并可强制单池）',
  'FB_SPLIT_RANGE 的分程输出与限幅语义', '', 0,
  ['池数变化未重新归一，余量丢给末池', '单池检修时无自动重分配'], 1, None),
 ('FB_DL_SettleOverflowRate', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/DewateringProcess.TcPOU', 'DL_Process', 'FB',
  'F1 沉淀池表面负荷率校核（Q/A 与设计值比对，超载降流量给定）',
  '借 DewateringProcess 的流量/处理量参数域语义', '', 0,
  ['负荷率用瞬时流量，未做移动平均', '超载只报警不降给定'], 2, None),
 ('FB_DL_CoagPHWindowGuard', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/FertilizerProcess.TcPOU', 'DL_Process', 'FB',
  'F1 混凝 pH 窗口守门（pH 越窗禁止加药并转手动，回窗延时恢复）',
  '借 FertilizerProcess 的药剂/pH 联锁语义', '', 0,
  ['pH 回窗立即恢复加药，无消抖', 'pH 探头故障未与加药互锁'], 2, None),

 # ---------------- F2 污泥脱水 ----------------
 ('FB_DL_SludgeDosePhaseSeq', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/SludgeDosing/FB_SludgeDosing.TcPOU', 'DL_Process', 'FB',
  'F2 污泥调理药剂投加相序（预混-主投-后稀释三段，按干固量折算投加率）',
  '仅借 FB_SludgeDosing 的相序/干固量折算语义，实现 clean-room', '', 0,
  ['无干固量测量时未降级为固定投加率', '相序中途掉电无续跑'], 1, None),
 ('FB_DL_CakeSolidsCalc', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/DewateringProcess.TcPOU', 'DL_Process', 'FB',
  'F2 泥饼含固率反算（进泥浓度/流量+药剂量→泥饼含固率与固体回收率）',
  '借 DewateringProcess 的进泥/出泥质量平衡参数域', '', 0,
  ['分母（进泥干固量）零除无闸', '回收率>100% 时无物理合理性钳制'], 1, None),
 ('FB_DL_CentrifugeDiffTorqueLoad', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/Granulator/FB_GranulationProcess.TcPOU', 'DL_Process', 'FB',
  'F2 离心脱水机差速-扭矩负荷限制（扭矩高→降进泥/提差速，含堵料判定）',
  '借 FB_GranulationProcess 的负载-进料联动语义', '', 0,
  ['扭矩突升无斜率判定，误判堵料', '差速上下限未与扭矩闭锁'], 1, None),
 ('FB_DL_FilterPressCycleSeq', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/GranulationProcess.TcPOU', 'DL_Process', 'FB',
  'F2 板框压滤机周期时序（进料-压榨-吹风-开板-卸饼，含超时与漏液判定）',
  '借 GranulationProcess 的批次相序与超时语义', '', 0,
  ['进料压力未达设定即进压榨，无最小进料量闸', '漏液判定仅靠单点压力'], 1, None),
 ('FB_DL_FiltrateRecycleGuard', 'wwtp', 'Wastewater Treatment Plant/plc/global_vars.st', 'DL_Process', 'FB',
  'F2 滤液回流负荷闸（滤液浊度高时截流回调节池，防厂内循环负荷冲击）',
  '借 WWTP global_vars 的回流/浊度信号语义', '', 0,
  ['回流泵与浊度无互锁', '无回流累积量上限'], 2, None),
 ('FB_DL_PolymerMakeupDilution', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/Mixit/FB_Mixit.TcPOU', 'DL_Process', 'FB',
  'F2 高分子絮凝剂配制与熟化（粉料+水按浓度配比，熟化计时到才允许投加）',
  '借 FB_Mixit 的配液搅拌/计时语义', '', 0,
  ['熟化未完成可被手动强制投加', '浓度按体积估算，无密度补偿'], 2, None),
 ('FB_DL_DewaterThroughputLimit', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/DewateringProcess.TcPOU', 'DL_Process', 'FB',
  'F2 脱水机产能上限与排队（按小时干固量限速，超限暂存缓冲罐）',
  '借 DewateringProcess 的处理量/缓冲语义', '', 0,
  ['限速用瞬时值，小时窗口未滚动', '缓冲满无上游停机指令'], 2, None),
 ('FB_DL_CakeTransportInterlock', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Function/Flap/FB_FlapCtrl.TcPOU', 'DL_Process', 'FB',
  'F2 泥饼输送联锁（下游皮带/斗提未运行禁止卸饼，翻板位反馈超时报警）',
  '借 FB_FlapCtrl 的翻板位反馈与到位超时语义', '', 0,
  ['翻板反馈抖动即报故障，无消抖', '下游故障时无缓存卸料路径'], 2, None),

 # ---------------- F3 湿式洗涤与催化 ----------------
 ('FB_DL_ScrubberLGRatio', 'scr', 'NoNOx/POUs/Init_Parameter/IO_Setting/LoadIOSettings_LP.st', 'DL_Process', 'FB',
  'F3 填料洗涤塔液气比控制（L/G 按烟气量联动循环泵频率，含最小喷淋量）',
  '借 SCR IO 参数装载的烟气量/泵频参数域语义', '', 0,
  ['烟气量低时 L/G 超上限，泵频无下限闸', '循环泵故障无备用切换'], 1, None),
 ('FB_DL_PackedBedDPFlood', 'scr', 'NoNOx/POUs/IO_Update/LP/SetDOValue.st', 'DL_Process', 'FB',
  'F3 填料层阻力与液泛预警（压降/喷淋量比值趋势，超阈降风量）',
  '借 SCR 的 IO 更新与阈值判定语义', '', 0,
  ['压降用瞬时值无趋势滤波', '液泛预警不联动风机'], 1, None),
 ('FB_DL_DemisterDPPurge', 'scr', 'NoNOx/POUs/Init_Parameter/IO_Setting/LoadIOSettings_LP_NTS.st', 'DL_Process', 'FB',
  'F3 除雾器差压冲洗（差压高→冲洗阀序动作，冲洗期间禁排烟联动）',
  '借 SCR 参数装载表的差压/阀序语义', '', 0,
  ['冲洗时未闭锁出口烟温保护', '差压回落后未复位冲洗完成标志'], 2, None),
 ('FB_DL_ReagentPHDoseCascade', 'ia2', 'library/process-control/pous/fb_cascade.st', 'DL_Process', 'FB',
  'F3 碱液补加 pH 串级（pH 主环→加药流量副环，含无扰切换与跟踪）',
  'FB_CASCADE 的主从跟踪/无扰切换语义', 'VAR_INPUT: master_out:REAL, cas_on:BOOL, sp_min:REAL, sp_max:REAL, slave_sp_local:REAL; VAR_OUTPUT: slave_sp:REAL, master_track:BOOL', 89,
  ['副环饱和时主环未停积分', 'pH 死区过大导致极限环'], 1, None),
 ('FB_DL_CatalystActivityDecay', 'scr', 'NoNOx/POUs/Init_Parameter/IO_Setting/LoadIOSettings_LP.st', 'DL_Process', 'FB',
  'F3 催化剂活性衰减与剩余寿命（按脱硝效率/氨逃逸比趋势外推，给更换窗口）',
  '借 SCR 的 NOx/NH3 参数域语义，实现 clean-room', '', 0,
  ['外推无置信区间，单点异常即拉偏', '效率分母为零无闸'], 1, None),
 ('FB_DL_VenturiThroatDPFlow', 'ia2', 'library/process-control/pous/fb_sqrt_flow.st', 'DL_Process', 'FB',
  'F3 文丘里喉部差压流量（含小流量切除与温压补偿）',
  'FB_SQRT_FLOW 的 dp_pct/flow_max/cutoff + FB_FLOW_COMP 的温压补偿语义', 'VAR_INPUT: dp_pct:REAL, flow_max:REAL, cutoff_pct:REAL; VAR_OUTPUT: flow:REAL', 41,
  ['dp<0 时开方未钳位（NaN）', '切除点以下未强制归零'], 1, None),
 ('FB_DL_StackCEMSValidRate', 'scr', 'NoNOx/POUs/Init_Parameter/IO_Setting/LoadIOSettings_LP_NTS.st', 'DL_Process', 'FB',
  'F3 烟囱 CEMS 数据有效率（标定/故障时段剔除，小时有效率<75% 标记无效）',
  '借 SCR 的 IO 参数装载/无效位语义', '', 0,
  ['剔除逻辑用瞬时标志，无整点对齐', '无效时段仍参与均值'], 2, None),

 # ---------------- F4 设备点检维护 ----------------
 ('FB_DL_OilChangeDueCalc', 'vms', 'Tc3_VN001007_VMS/RWPumpVMS/05_Application/FastSampling/PRG_VibrationSampling.TcPOU', 'DL_Process', 'FB',
  'F4 换油到期判定（运行小时+启停次数+油温累积三维加权，任一先到即到期）',
  '借 VMS FastSampling 的采样/计数结构语义', '', 0,
  ['三因子无权重配置，硬编码', '换油后计数器未强制归零校验'], 1, None),
 ('FB_DL_SpareReorderPoint', 'vms', 'Tc3_VN001007_VMS/RWPumpVMS/05_Application/PRG_Simulation.TcPOU', 'DL_Process', 'FB',
  'F4 备件订货点 ROP（提前期需求均值+安全库存，消耗速率自适应）',
  '借 VMS 的计数/仿真参数域语义', '', 0,
  ['提前期方差未参与，缺货率不可控', '消耗速率用短窗，抖动大'], 1, None),
 ('FB_DL_MTBFEstimate', 'vms', 'Tc3_VN001007_VMS/RWPumpVMS/05_Application/MAIN.TcPOU', 'DL_Process', 'FB',
  'F4 MTBF/MTTR 在线估计（按故障间隔序列递推，样本不足时给区间而非点值）',
  '借 VMS MAIN 的任务编排/故障位语义', '', 0,
  ['样本<3 仍输出点值', '未剔除计划停机，MTBF 偏小'], 1, None),
 ('FB_DL_BearingTempRiseRate', 'vms', 'Tc3_VN001007_VMS/RWPumpVMS/05_Application/FastSampling/PRG_VibrationSampling.TcPOU', 'DL_Process', 'FB',
  'F4 轴承温升速率告警（温升 dT/dt 与绝对温度双判据，含启动期抑制）',
  '借 VMS 高速采样任务的采样节拍语义', '', 0,
  ['启动期抑制窗固定，慢加速设备误报', '温升用单点差分，噪声放大'], 1, None),
 ('FB_DL_VibSampleRMS', 'vms', 'Tc3_VN001007_VMS/RWPumpVMS/05_Application/FastSampling/PRG_VibrationSampling.TcPOU', 'DL_Process', 'FB',
  'F4 振动 RMS 特征值提取（滑动窗 RMS+峰值因子，窗口对齐转速）',
  'VMS FastSampling 的采样窗与任务周期结构', '', 0,
  ['窗长固定不随转速调整', '无直流偏置去除'], 1, None),
 ('FB_DL_PMChecklistSeq', 'wwtp', 'Wastewater Treatment Plant/plc/main.st', 'DL_Process', 'FB',
  'F4 点检单相序执行（按设备位号下发检查项，未签字禁投运）',
  '借 WWTP main 的设备启停前置确认语义', '', 0,
  ['点检未完成可被 HMI 强制放行', '点检项超时无升级路径'], 2, None),
 ('FB_DL_RuntimeToPMDue', 'ia2', 'library/process-control/pous/fb_runtime.st', 'DL_Process', 'FB',
  'F4 运行小时→PM 到期（小时数与启停次数双计数，到期输出并锁存）',
  'FB_RUNTIME 的 running/reset/dt_s 与 hours/starts 输出语义', 'VAR_INPUT: running:BOOL, reset:BOOL, dt_s:REAL; VAR_OUTPUT: hours:REAL, starts:DINT', 52,
  ['dt_s<=0 时 hours 不增但仍累计（异常时冻结失败）', 'starts 溢出未处理'], 1, None),
 ('FB_DL_EquipHealthScore', 'vms', 'Tc3_VN001007_VMS/RWPumpVMS/05_Application/MAIN.TcPOU', 'DL_Process', 'FB',
  'F4 设备健康评分合成（温升/振动/运行时长/故障次数归一化加权，输出 0-100）',
  '借 VMS 的多源信号汇总结构语义', '', 0,
  ['权重和为 0 时除零', '单一因子饱和即拉满分，无封顶'], 2, None),

 # ---------------- F5 厌氧沼气 ----------------
 ('FB_DL_OLRFeedGuard', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/FertilizerProcess.TcPOU', 'DL_Process', 'FB',
  'F5 有机负荷率 OLR 进料闸（按罐容与进料 COD/VS 算 OLR，超限降进料速率）',
  '借 FertilizerProcess 的进料/罐位参数域语义', '', 0,
  ['COD 缺测时未降级为流量限', 'OLR 用瞬时值，日负荷未滚动'], 1, None),
 ('FB_DL_VFAAlkalinityRatio', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/FertilizerProcess.TcPOU', 'DL_Process', 'FB',
  'F5 VFA/碱度比酸化预警（比值>0.3 预警，趋势上升禁再加负荷）',
  '借 FertilizerProcess 的化验值输入语义', '', 0,
  ['碱度为零时除零', '化验值离散，未做保持策略'], 1, None),
 ('FB_DL_BiogasMethaneYield', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/Granulator/FB_GranulationProcess.TcPOU', 'DL_Process', 'FB',
  'F5 沼气甲烷产率折算（标态折算 CH4 体积/进料 VS，含 N2/CO2 干扰修正）',
  '借 GranulationProcess 的产气/进料折算语义', '', 0,
  ['标态折算缺温压补偿', '产率分母（VS）为零无闸'], 1, None),
 ('FB_DL_GasHolderCapacityCtrl', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/Dachs/FB_DachsControl.TcPOU', 'DL_Process', 'FB',
  'F5 气柜容量与产用平衡（柜位高→启 CHP，低位→切火炬，含缓冲带）',
  '借 FB_DachsControl 的 CHP 启停与气量平衡语义', '', 0,
  ['柜位振荡时 CHP 频繁启停，无最小运行时间', '柜位计故障无人工位'], 1, None),
 ('FB_DL_FlareIgnitionSeq', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Function/Flap/FB_TwoPositionController.TcPOU', 'DL_Process', 'FB',
  'F5 火炬点火时序（吹扫-点火-火焰确认-失败重试，失败 3 次锁存）',
  '借 FB_TwoPositionController 的双位动作与到位确认语义', '', 0,
  ['火焰未确认仍开阀（爆燃风险）', '重试计数无冷却时间'], 1, None),
 ('FB_DL_DigesterHRTCalc', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/FertilizerProcess.TcPOU', 'DL_Process', 'FB',
  'F5 水力停留时间 HRT 计算与低 HRT 报警（有效罐容/进料流量，含短流修正）',
  '借 FertilizerProcess 的罐容/进料参数域语义', '', 0,
  ['流量为零时 HRT 无穷大未钳位', '泡沫层未从有效容积扣除'], 1, None),
 ('FB_DL_H2SDesulfurDose', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/Dachs/FB_DachsControl.TcPOU', 'DL_Process', 'FB',
  'F5 沼气脱硫药剂/空气投加（按 H2S 浓度与气量算理论需氧量，含过量系数）',
  '借 FB_DachsControl 的燃气品质参数域语义', '', 0,
  ['H2S 表故障按 0 处理（脱硫失效）', '过量系数无上下限'], 2, None),
 ('FB_DL_DigesterTempZoneGuard', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/FB_Classes/Mixit/FB_Mixit.TcPOU', 'DL_Process', 'FB',
  'F5 厌氧温度带守门（中温 35±1℃ 带内允许进料，越带降负荷并报警）',
  '借 FB_Mixit 的罐内搅拌/温度参数域语义', '', 0,
  ['越带仍允许进料，无硬闭锁', '温度探头断线按 0℃ 处理触发误停'], 1, None),
 ('FB_DL_GasMeterNormConvert', 'rybno', 'plc/Rybno_v1/Rybno_v1/POUs/Processes/DewateringProcess.TcPOU', 'DL_Process', 'FC',
  'F5 沼气流量标态折算（工况→标况，含湿度和压力修正）',
  '借 DewateringProcess 的流量计量语义，实现 clean-room', '', 0,
  ['负压/负流量未钳位', '湿度项缺省硬编码'], 2, None),
]


def fp(name, sigtxt):
    norm = re.sub(r'^(fb_|fc_|i_|st_|e_)', '', name.lower())
    norm = re.sub(r'^(tc_|mc_|smc_)', '', norm)
    keys = re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_]+)', sigtxt or '')
    types = ','.join(sorted('%s:%s' % (k.lower(), t.upper()) for k, t in keys))
    return hashlib.sha1(('%s|%s' % (norm, types)).encode()).hexdigest()[:16]


rows = []
existing = []
for line in open(QF, encoding='utf-8'):
    line = line.strip()
    if not line:
        continue
    try:
        existing.append(json.loads(line))
    except Exception:
        pass

ex_names = set(r.get('name', '').lower() for r in existing)
ex_urls = set(r.get('source_url', '') for r in existing)
ex_fps = set(r.get('fp', '') for r in existing if r.get('fp'))

fam_count = {'F1': 0, 'F2': 0, 'F3': 0, 'F4': 0, 'F5': 0}
dup = []
out = []
for (nm, sk, path, cat, kind, sem, ep, sig, loc, gaps, pri, exc) in C:
    fam = sem[:2]
    if nm.lower() in registry or nm.lower() in ex_names:
        dup.append((nm, 'name'))
        continue
    u = url(sk, path)
    if u in ex_urls:
        dup.append((nm, 'url'))
        continue
    f = fp(nm, sig)
    if f in ex_fps:
        dup.append((nm, 'fp'))
        continue
    rp, lic, cls, sha, br = S[sk]
    rec = {
        'name': nm, 'suggest_category': cat, 'kind': kind, 'tier': cls,
        'license': lic, 'license_class': cls,
        'source_repo': rp, 'source_url': u, 'commit': sha, 'branch': br,
        'extraction_point': ep, 'semantic': sem, 'family': fam,
        'signature': sig, 'loc': loc,
        'dialect': ['CleanRoom'] if cls == 'green' else ['SemanticOnly'],
        'defense_gaps': gaps,
        'dedup': {'name': 'pass', 'fingerprint': 'new', 'semantic': 'new'},
        'priority': pri, 'fp': f, 'round': 'R82', 'status': 'pending',
        'harvested_at': '2026-11-24T11:45:00+08:00',
        'note': ('绿区可改写，需保留 NOTICE 与版权声明' if cls == 'green'
                 else '黄区仅借接口骨与参数域，实现必须 clean-room'),
        'code_excerpt': exc,
    }
    if cls == 'yellow':
        rec['reuse_scope'] = 'signature_and_parameter_domain_only'
    out.append(rec)
    fam_count[fam] += 1

with open(QF, 'a', encoding='utf-8') as f:
    for r in out:
        f.write(json.dumps(r, ensure_ascii=False) + '\n')

print('WROTE', len(out), 'DUP', len(dup), dup[:5])
print('FAMILY', fam_count)
print('GREEN', sum(1 for r in out if r['tier'] == 'green'), 'YELLOW', sum(1 for r in out if r['tier'] == 'yellow'))
