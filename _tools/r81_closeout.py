# -*- coding: utf-8 -*-
"""R81 收口：registry 登记 + SFT JSONL 追加（40 件，复杂 4 / 简单 36）"""
import io, json, os, re, datetime

LIB = r'C:\Library'
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
JSONL = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
ROUND = 'R81'
NOW = '2026-11-24T09:05:00+08:00'

# name, category, ctype, complexity, desc_cn, tags, src_mode, src_note
ITEMS = [
    # ---- 复杂 4 ----
    ('FB_DL_RotaryIndexerCycleSeq','DL_Process','FB',5,'转盘八工位索引节拍机（环形杯位寄位器+剔除工位裁决+超时兜底）',
     ['process','asrs','packaging','sequence','open-source','r81'],'open-source','menes97/ayran-mini-fabrika FB_Dolum / MIT / 借鉴点：8 工位回转链节拍推进与每杯 TR_CUP/TR_BAD 移位寄存器语义'),
    ('FB_DL_AsrsSlotAllocSeq','DL_Process','FB',4,'立库货位分配取放握手（ack_seq/res_seq 序号同步+冲突净额回退）',
     ['process','asrs','handshake','sequence','open-source','r81'],'open-source','menes97/ayran-mini-fabrika FB_Asrs / MIT / 借鉴点：货位分配请求-应答序号同步与冲突回退语义'),
    ('FB_DL_FillPreactSelfLearn','DL_Process','FB',4,'灌装预动作量自学习（粗/细流切换+PREACT 限幅学习+下落量补偿）',
     ['process','filling','self-learn','sequence','open-source','r81'],'open-source','menes97/ayran-mini-fabrika FB_Dolum PREACT / MIT / 借鉴点：粗流/细流两段切换与预动作量自学习语义'),
    ('FB_DL_MeasureInputLatch','DL_Motion','FB',3,'探针测量输入锁存（布防-触发-锁存-读取四相+窗口超时）',
     ['motion','robot','latch','sequence','open-source','r81'],'open-source','ThorstenBrach/SRCI_CLIENT_PLC MC_MeasuringInputFB / MIT / 借鉴点：测量输入相序与窗口超时语义'),
    # ---- 族1 立体库 8 ----
    ('FC_DL_ShuttleStrokeTimeEst','DL_Process','FC',1,'穿梭车单行程时间估算（梯形速度曲线加装卸换向时间）',['process','asrs','kinematics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_ShuttleAisleLockChk','DL_Process','FC',1,'穿梭车巷道互锁裁决（放行位+0/1/2/3 拒绝码）',['process','asrs','interlock','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_LifterCycleTimeEst','DL_Process','FC',1,'提升机单循环节拍与产能折算',['process','asrs','kinematics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_StocktakeVarianceCalc','DL_Process','FC',1,'盘点差异数量、差异率与差异金额',['process','asrs','inventory','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_BeamToppleRiskChk','DL_Process','FC',1,'横梁倾覆风险校核（偏心放大后折算承载利用率）',['process','asrs','safety','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_CellOccupyRateCalc','DL_Process','FC',1,'货位占用率（扣除封存货位后求占用百分比与空闲数）',['process','asrs','statistics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_ForkExtendSafeChk','DL_Process','FC',2,'货叉伸出安全校核（通道余量与对齐误差双判据）',['process','asrs','safety','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_BinLabelCheckSum','DL_Process','FC',1,'货位标号校验和（按长度与分隔符数量生成模36校验位）',['process','asrs','string','checksum','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    # ---- 族2 灌装清洗 8 ----
    ('FC_DL_FoamSuppressDutyCalc','DL_Process','FC',1,'抑泡剂投加占空比（液位修正后限幅 0~100）',['process','filling','dosing','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_RinseWaterVolumeCalc','DL_Process','FC',1,'冲洗水量（管容乘冲洗次数乘残留系数）',['process','cip','volume','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_SanitizeHoldTimeCalc','DL_Process','FC',2,'消毒保持时间（浓度比与温度系数修正）',['process','cip','sanitize','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_ConductivityDilutionCalc','DL_Process','FC',1,'电导率稀释比与配水占比',['process','cip','dilution','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_NozzleClogIndexCalc','DL_Process','FC',2,'喷嘴堵塞指数与堵塞报警',['process','filling','diagnostics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_SipResidueVolumeEst','DL_Process','FC',2,'SIP 灭菌残留量估算（坡度排空残留加盲管滞留量）',['process','cip','volume','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_FillValveSealWearEst','DL_Process','FC',2,'灌装阀密封磨损（温度加速因子折算等效循环）',['process','filling','wear','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_BottleNeckLevelMargin','DL_Process','FC',1,'瓶口液位余量与溢泡风险',['process','filling','safety','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    # ---- 族3 空压站 7 ----
    ('FC_DL_ReceiverPressureDropCalc','DL_Process','FC',2,'储气罐压降法流量估算与压降速率',['process','compressed-air','flow','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_AirQualityClassifyCalc','DL_Process','FC',2,'压缩空气质量等级判定（露点、含油、颗粒取最严者）',['process','compressed-air','classify','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_DesiccantLifeEstimate','DL_Process','FC',2,'干燥剂剩余寿命与更换到期判定',['process','compressed-air','wear','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_MotorLoadFactorCalc','DL_Process','FC',1,'电机负载率与视在功率过载判定',['process','compressed-air','electrical','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_CompressorDutyCycleCalc','DL_Process','FC',2,'空压机加载占空比与卸载能耗占比',['process','compressed-air','statistics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_DrainIntervalCalc','DL_Process','FC',1,'自动排水间隔与即时排水请求',['process','compressed-air','timing','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_IdleRunRatioCalc','DL_Process','FC',1,'空转率与空转浪费电量',['process','compressed-air','statistics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    # ---- 族4 真空吸取 7 ----
    ('FC_DL_VacuumPadForceCalc','DL_Device','FC',1,'真空吸盘吸附力与安全系数折算可用力',['device','vacuum','force','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_SuctionFlowEst','DL_Device','FC',2,'真空抽吸流量估算（孔口流量式折算 L/min）',['device','vacuum','flow','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_SheetPeelForceCalc','DL_Device','FC',2,'片材剥离力（粘附分量、静电分量、角度折减系数）',['device','vacuum','force','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_VacHoldDecayChk','DL_Device','FC',1,'真空保持衰减率与泄漏报警',['device','vacuum','diagnostics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_PadWearIndexCalc','DL_Device','FC',2,'吸盘磨损指数与更换到期判定',['device','vacuum','wear','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_VacuumGenDutyCalc','DL_Device','FC',1,'真空发生器占空比与平均耗气量',['device','vacuum','timing','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_SuctionCupCountCalc','DL_Device','FC',1,'吸盘数量配置（手动进位取整加可行性判定）',['device','vacuum','sizing','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    # ---- 族5 输送传动 6 ----
    ('FC_DL_LineSpeedMatchRatio','DL_Motion','FC',1,'主从线速匹配校验与实际速比偏差',['motion','conveying','ratio','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_ChainWearElongation','DL_Motion','FC',2,'链条磨损伸长率与更换到期判定',['motion','conveying','wear','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_RollerSlipRatioCalc','DL_Motion','FC',1,'辊筒打滑率与打滑报警',['motion','conveying','diagnostics','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_SkateWheelLoadCalc','DL_Motion','FC',2,'滑板轮载荷分配（前轴占比加单轮载荷）',['motion','conveying','force','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_LaneDiverterAngleCalc','DL_Motion','FC',1,'道岔最小转角、通过时间与速度许可',['motion','conveying','geometry','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
    ('FC_DL_TrackingOffsetChk','DL_Motion','FC',2,'跟踪偏移校验（脉冲折算距离与漂移报警）',['motion','conveying','tracking','r81'],'internal','道莅原创（R81 批次，工程公式 clean-room）'),
]

def read(p):
    return io.open(p, encoding='utf-8').read()

def version_of(src):
    m = re.search(r'版本 \(Version\)\s*:\s*([0-9.]+)', src) or re.search(r'版本\s*:\s*([0-9.]+)', src)
    return m.group(1) if m else '1.0.0'

reg = json.load(io.open(REG, encoding='utf-8'))
have = {c['name'] for c in reg['components']}
added, skipped = [], []

for name, cat, ctype, cx, desc, tags, mode, note in ITEMS:
    fp = os.path.join(LIB, cat, name + '.st')
    if not os.path.exists(fp):
        skipped.append((name, 'MISSING_FILE')); continue
    if name in have:
        skipped.append((name, 'DUP_IN_REGISTRY')); continue
    src = read(fp)
    ver = version_of(src)
    reg['components'].append({
        'name': name, 'category': cat, 'type': ctype,
        'file_path': fp,
        'function_tags': tags,
        'complexity': cx,
        'registered_at': NOW,
        'origin': {'mode': mode, 'source': note,
                   'license': 'MIT' if mode == 'open-source' else 'internal',
                   'ref_tag': ('open_source' if mode == 'open-source' else 'dl_' + cat.split('_')[1].lower())},
        'l2_status': 'l2-pass',
    })
    added.append((name, cat, ctype, cx, desc, ver, src))

# counts / total
cnt = {}
for c in reg['components']:
    cnt[c['category']] = cnt.get(c['category'], 0) + 1
reg['counts'] = cnt
reg['total_components'] = len(reg['components'])
reg['version'] = '2.73.0'
reg['last_updated'] = NOW

json.dump(reg, io.open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

# ---- JSONL ----
lines = []
for name, cat, ctype, cx, desc, ver, src in added:
    kind = '功能块（FB）' if ctype == 'FB' else '函数（FC）'
    instr = ('在%s类项目的工业场景中，需要实现 %s 组件：%s。请用 IEC 61131-3 结构化文本实现一个%s，'
             '满足跨平台编译（RuSTy 1.0.8 可解析），处理除零/非有限/越界等边界条件，'
             '每个声明变量带中英双语注释，并在无效应答时给出可判别的原因码或无效位。') % (cat, name, desc, kind)
    arch = ('【需求解析】%s；属 %s 子库，复杂度 C%d，类型 %s。\n'
            '【接口分工】VAR_INPUT 承接工况输入与使能/故障闸，VAR_OUTPUT 输出计算结果 + bValid 有效位（FB 另有 eState/bError/iErrCode）；'
            '内部 VAR 仅存放中间量与边沿/定时实例。\n'
            '【防错设计】所有除法前判 |分母| > 1E-12（IEC 不保证短路求值，闸与除法同句前置）；'
            '非有限输入用 x<>x 与 |x|>R_MAX 双判拦截（禁用 ABS(x-x) 作非有限判据，Inf-Inf=NaN 会使比较恒假）；'
            '限幅用顺序 IF/ELSIF 而非可能反序的 MIN/MAX 嵌套。\n'
            '【状态机】（FB 适用）ENUM 定义置于文件顶部，CASE 覆盖全部成员并带 ELSE 兜底；'
            '每个状态有出口，故障态必有 rtReset.Q 复位出口；所有等待收敛相配 TON 超时兜底，避免相驻留无界；'
            'TON/R_TRIG 实例在 CASE 外无条件周期刷新。\n'
            '【OOP 解耦】不引用 GVL、不做 VAR_EXTERNAL、不绑物理地址，依赖注入式参数传递，跨平台可移植。') % (desc, cat, cx, ctype)
    lines.append(json.dumps({
        'instruction': instr, 'architecture_thought': arch,
        'output': src,
        'meta': {'name': name, 'category': cat, 'version': ver, 'round': ROUND}
    }, ensure_ascii=False))

with io.open(JSONL, 'a', encoding='utf-8') as f:
    for l in lines:
        f.write(l + '\n')

# ---- verify ----
st = 0
for d in ['DL_Base','DL_MathData','DL_Algo','DL_Device','DL_Motion','DL_Process']:
    st += len([x for x in os.listdir(os.path.join(LIB, d)) if x.endswith('.st')])
jl = sum(1 for _ in io.open(JSONL, encoding='utf-8'))
print('added', len(added), 'skipped', skipped)
print('registry', reg['total_components'], 'counts', cnt)
print('st_files', st, 'jsonl', jl)
print('DIFF registry-vs-st', reg['total_components'] - st, '| jsonl-registry', jl - reg['total_components'])
