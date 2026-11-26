# -*- coding: utf-8 -*-
"""R82 收口：registry 登记 + SFT JSONL 追加（40 件计划，按 accepted 名单过滤）
用法: python r82_closeout.py <accepted_names.txt>
accepted_names.txt 每行一个组件名（仅 L2 PASS 且审校 PASS 的件）
"""
import io, json, os, re, sys, datetime

LIB = r'C:\Library'
REG = os.path.join(LIB, 'INDEX_REGISTRY.json')
JSONL = os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')
ROUND = 'R82'
NOW = '2026-11-24T11:55:00+08:00'

# 序号, name, category, ctype, cmplx, 中文功能, 英文标签, 关键出参
P = [
(1,'FC_DL_CoagDoseFromJarTest','DL_Process','FC',2,'由烧杯试验反算混凝剂投加量（mg/L 换算 L/h，含上限限幅）',
 ['process','water-treatment','coagulation','dosing'],'rDoseLh/bValid/sMsg'),
(2,'FC_DL_FlocDilutionRatio','DL_Process','FC',2,'絮凝剂母液稀释比与配液体积（禁止向高浓度稀释）',
 ['process','water-treatment','flocculation','dilution'],'rRatio/rStockVolL/bValid'),
(3,'FC_DL_SettleVelocityCalc','DL_Process','FC',2,'Stokes 沉降末速度（含雷诺数域判定与密度反转处理）',
 ['process','water-treatment','sedimentation','kinematics'],'rVsMmS/bValid'),
(4,'FC_DL_SludgeBlanketLevel','DL_Process','FC',2,'静压差法污泥界面高度（密度差闸与量程限幅）',
 ['process','water-treatment','sludge','level'],'rLevelM/bValid'),
(5,'FC_DL_ClarifierSurfaceLoad','DL_Process','FC',2,'沉淀池表面水力负荷校核与超限标志',
 ['process','water-treatment','clarifier','load'],'rLoadM3m2h/bOver/bValid'),
(6,'FC_DL_SviCalc','DL_Process','FC',2,'SVI 污泥容积指数与合理域告警',
 ['process','water-treatment','sludge','index'],'rSviMlg/bValid'),
(7,'FC_DL_NtuCoagDoseAdj','DL_Process','FC',2,'出水浊度反馈的投加量微调（步长限幅与总量限幅）',
 ['process','water-treatment','coagulation','feedback'],'rDoseOut/bValid'),
(8,'FC_DL_LamellaAreaCalc','DL_Process','FC',2,'斜板斜管沉淀投影面积（倾角余弦修正与安全系数）',
 ['process','water-treatment','clarifier','sizing'],'rAreaM2/bValid'),
(9,'FC_DL_ScrewPressThroughput','DL_Process','FC',2,'螺旋压榨机干固体处理量（时与日双口径）',
 ['process','dewatering','screw-press','throughput'],'rDsKgH/rDsKgDay/bValid'),
(10,'FC_DL_CakeSolidsCalc','DL_Process','FC',2,'泥饼含固率与固体回收率（质量平衡判据）',
 ['process','dewatering','mass-balance','solids'],'rCakeTsPct/rRecoveryPct/bValid'),
(11,'FC_DL_PolymerDoseCalc','DL_Process','FC',2,'PAM 聚合物投加量（DS 基比投与母液体积换算）',
 ['process','dewatering','polymer','dosing'],'rPolyKgH/rPolyLh/bValid'),
(12,'FC_DL_CentrateTurbidityIdx','DL_Process','FC',2,'离心液浊度指数与跑料判据',
 ['process','dewatering','centrifuge','diagnostics'],'rIdx/bCarryOver/bValid'),
(13,'FC_DL_FiltrateRecycleRatio','DL_Process','FC',2,'滤液回流比与固体回流量（回流过高告警）',
 ['process','dewatering','filtrate','ratio'],'rRatio/rSolidRecycleKgH/bValid'),
(14,'FC_DL_DewaterMassBalance','DL_Process','FC',2,'脱水段全物料平衡（泥饼量/滤液量/回收率三算）',
 ['process','dewatering','mass-balance'],'rCakeM3h/rFiltrateM3h/rRecoveryPct/bValid'),
(15,'FC_DL_BeltPressLoadRate','DL_Process','FC',2,'带式压滤机比负荷率与超载判定',
 ['process','dewatering','belt-press','load'],'rLoadKgM2h/bOver/bValid'),
(16,'FC_DL_ScrubberLiquidGasRatio','DL_Process','FC',2,'湿式洗涤塔液气比与低液气比告警',
 ['process','scrubber','mass-transfer','ratio'],'rLG/rLiquidNeedM3h/bLow/bValid'),
(17,'FC_DL_PackedBedHtu','DL_Process','FC',2,'填料层传质单元高度与塔高估算（含 20% 余量）',
 ['process','scrubber','packed-bed','sizing'],'rHtuM/rHeightM/bValid'),
(18,'FC_DL_ReagentConsumeCalc','DL_Process','FC',2,'洗涤药剂日耗与储罐可用天数',
 ['process','scrubber','reagent','consumption'],'rKgH/rKgDay/rDaysLeft/bValid'),
(19,'FC_DL_CatalystActivityDecay','DL_Process','FC',2,'SCR 催化剂活性衰减（Arrhenius 温度加速）与剩余寿命',
 ['process','scrubber','catalyst','degradation'],'rActivity/rRulHours/bValid'),
(20,'FC_DL_VenturiScrubDpEst','DL_Process','FC',2,'文丘里洗涤器压降估算（喉速与液气动量项）',
 ['process','scrubber','venturi','pressure-drop'],'rDpKpa/bValid'),
(21,'FC_DL_DemisterVelocityChk','DL_Process','FC',2,'除雾器截面流速与临界携液校核（Souders-Brown）',
 ['process','scrubber','demister','safety'],'rVelMs/rVcritMs/bCarryOver/bValid'),
(22,'FC_DL_StackEmissionDilute','DL_Process','FC',2,'烟囱排放浓度干基与基准氧折算',
 ['process','emission','normalization'],'rDryMgNm3/rRefMgNm3/bValid'),
(23,'FC_DL_ComponentRulEstimate','DL_Device','FC',2,'部件剩余寿命线性外推（无退化与非有限双闸）',
 ['device','maintenance','rul','prediction'],'rRulHours/rSlopePerH/bValid'),
(24,'FC_DL_BrgThermalDriftRate','DL_Device','FC',2,'轴承温升速率与快速升温告警',
 ['device','maintenance','bearing','thermal'],'rRisePerMin/rOverAmbC/bFastRise/bValid'),
(25,'FC_DL_OilChangeInterval','DL_Device','FC',2,'换油周期（负荷/温度/污染三因子修正）与到期判定',
 ['device','maintenance','lubrication','interval'],'rIntervalH/rRemainH/bDue/bValid'),
(26,'FC_DL_MtbfCalc','DL_Device','FC',2,'MTBF/MTTR 与可用率联算（零失效样本处理）',
 ['device','maintenance','reliability','kpi'],'rMtbfH/rMttrH/rAvailPct/bValid'),
(27,'FC_DL_SpareReorderPoint','DL_Device','FC',2,'备件订货点与缺口量（用量乘提前期加安全天数）',
 ['device','maintenance','spare-parts','inventory'],'rRop/rShortQty/bReorder/bValid'),
(28,'FC_DL_PmScheduleNext','DL_Device','FC',2,'下次预防性保养日期与逾期天数（DT 域运算）',
 ['device','maintenance','pm','schedule'],'dtNext/iOverdueDays/bOverdue/bValid'),
(29,'FC_DL_LubeIntervalCalc','DL_Device','FC',2,'润滑间隔（负荷/温度/粉尘三因子反向修正）',
 ['device','maintenance','lubrication','interval'],'rIntervalH/bValid'),
(30,'FC_DL_BiogasYieldCalc','DL_Process','FC',2,'沼气产率（VS 降解率乘产气系数，日与时双口径）',
 ['process','anaerobic','biogas','yield'],'rGasM3Day/rGasM3h/bValid'),
(31,'FC_DL_MethaneRatioCalc','DL_Process','FC',2,'甲烷含量差减法与低位热值（H2S 超标告警）',
 ['process','anaerobic','biogas','composition'],'rCh4Pct/rLhvMJm3/bValid'),
(32,'FC_DL_OrganicLoadRate','DL_Process','FC',2,'厌氧有机负荷率 OLR（COD 折算 VS 与超限判定）',
 ['process','anaerobic','loading','olr'],'rOlrKgVsM3d/rVsKgDay/bOver/bValid'),
(33,'FC_DL_VfaAlkalinityRatio','DL_Process','FC',2,'VFA/碱度比与三级酸化风险分级',
 ['process','anaerobic','vfa','risk'],'rRatio/iRisk/bValid'),
(34,'FC_DL_GasHolderLevel','DL_Process','FC',2,'气柜储量标态折算与折算能量',
 ['process','anaerobic','gas-holder','normalization'],'rNormM3/rEnergyKwh/bValid'),
(35,'FC_DL_DigesterRetentionTime','DL_Process','FC',2,'消化器 HRT/SRT 与容积负荷（SRT 不得小于 HRT）',
 ['process','anaerobic','retention','sizing'],'rHrtDay/rSrtDay/rLoadingKgM3d/bValid'),
(36,'FC_DL_FlareFlowSizing','DL_Process','FC',2,'火炬放空管径与出口流速（实况流量折算）',
 ['process','anaerobic','flare','sizing'],'rDiaM/rVelMs/bOver/bValid'),
(37,'FB_DL_CoagDoseJarTestSeq','DL_Process','FB',4,'混凝加药闭环序列（前馈分段基准+烧杯反馈修正+沉后浊度复核+循环次数上限）',
 ['process','water-treatment','coagulation','sequence','state-machine'],'rDoseLh/bDoseOn/iErrCode/sMsg'),
(38,'FB_DL_ScrewPressDewaterSeq','DL_Process','FB',4,'螺旋压榨脱水序列（进泥/混合/压榨/冲洗/退让五相，过压提前退让与故障硬断）',
 ['process','dewatering','screw-press','sequence','state-machine'],'bFeedValve/bPressMotor/iErrCode'),
(39,'FB_DL_ScrubberReagentDoseSeq','DL_Process','FB',4,'洗涤塔药剂投加闭环（pH 简化 PI+抗饱和积分+电导补排+药剂耗尽锁）',
 ['process','scrubber','reagent','sequence','state-machine'],'rPumpLh/bMakeupValve/iErrCode'),
(40,'FB_DL_AnaerobDigesterLoadCtrl','DL_Process','FB',4,'厌氧消化负荷控制（VFA/碱度降载+产气骤降联动+两级确认恢复）',
 ['process','anaerobic','loading','control','state-machine'],'rFeedOutM3h/iLoadLevel/iErrCode'),
]

SRC_INTERNAL = '道莅原创（R82 批次，clean-room 工程公式自研；参考公开工艺计算公式，未复制受版权保护代码）'


def read_body(name):
    for cat in ('DL_Base','DL_MathData','DL_Algo','DL_Device','DL_Motion','DL_Process'):
        p = os.path.join(LIB, cat, name + '.st')
        if os.path.exists(p):
            return io.open(p, encoding='utf-8', errors='replace').read()
    return None


def make_record(name, cat, ctype, cmplx, desc_cn, tags, body):
    ins, outs = [], []
    cur = None
    for ln in body.split('\n'):
        u = ln.strip()
        if re.match(r'^VAR_INPUT\b', u, re.I): cur = ins; continue
        if re.match(r'^VAR_OUTPUT\b', u, re.I): cur = outs; continue
        if re.match(r'^(VAR|VAR_IN_OUT|VAR_TEMP)\b', u, re.I): cur = None; continue
        if re.match(r'^END_VAR\b', u, re.I): cur = None; continue
        if cur is None or not u or u.startswith('//'): continue
        m = re.match(r'^([A-Za-z_]\w*)\s*:\s*([^;]+);', u)
        if m:
            cur.append((m.group(1), m.group(2).strip()))
    ins_s = '、'.join('%s(%s)' % (a, b) for a, b in ins) or '无'
    outs_s = '、'.join('%s(%s)' % (a, b) for a, b in outs) or '无'
    instruction = (
        '【工业控制现场需求】%s\n'
        '【类型】IEC 61131-3 %s，分类 %s，复杂度 C%d\n'
        '【输入】%s\n【输出】%s\n'
        '【边界条件】所有分母须有零闸、开方前须非负、对数前须为正，结果越 ±1.0E15 判非有限并否决 bValid；'
        '量纲按 SI 内部一致，跨单位换算在入口一次完成并注释量纲链。\n'
        '【验收】给定典型工况应落在工程合理域内，越域须给出错误码而非静默饱和。'
        % (desc_cn, ctype, cat, cmplx, ins_s, outs_s)
    )
    thought = (
        '1) 物理建模：先确认该量属于「守恒量 / 速率量 / 比值量 / 判据量」哪一类，'
        '据此决定用质量平衡、经验式还是阈值比较实现，避免把比值当守恒量传递。\n'
        '2) 量纲先行：每个中间量先写量纲链注释（如 (mg/L)*(m3/h)/1000 = kg/h），'
        '再落代码，杜绝「公式对但单位错 1000 倍」这类最隐蔽缺陷。\n'
        '3) 防错分层：入口做入参域校验（分母、浓度、百分比），中段做域饱和，出口用 bValid 汇总而非逐处 return，'
        '使调用方能区分「值可信」与「值仅为占位」。\n'
        '4) 状态机解耦：序列类逻辑用 ENUM + CASE 单相推进，所有 TON/R_TRIG 实例置于 CASE 之外无条件刷新，'
        'CASE 必带 ELSE 兜底转安全态，故障相必须有出口，保证任何异常输入都不会把设备锁死在动作相。\n'
        '5) OOP 解耦：把「算」与「判」分离——纯计算留在 FC 便于单测，序列与互锁留在 FB 便于复用，'
        '两者通过显式入出参通信，不共享全局状态。'
    )
    return {
        'instruction': instruction,
        'architecture_thought': thought,
        'output': body,
        'meta': {'name': name, 'category': cat, 'ctype': ctype, 'complexity': cmplx,
                 'round': ROUND, 'l2': 'l2-pass'},
    }


def main():
    acc_path = sys.argv[1]
    acc = [x.strip() for x in io.open(acc_path, encoding='utf-8') if x.strip()]
    accset = set(acc)
    d = json.load(open(REG, encoding='utf-8'))
    have = {c['name'] for c in d['components']}
    added, missing, skipped = [], [], []
    for (seq, name, cat, ctype, cmplx, desc, tags, outs) in P:
        if name not in accset:
            skipped.append(name); continue
        if name in have:
            missing.append(name + '(已存在，跳过)'); continue
        body = read_body(name)
        if body is None:
            missing.append(name + '(无源文件)'); continue
        d['components'].append({
            'name': name, 'category': cat, 'ctype': ctype, 'complexity': cmplx,
            'description': desc,
            'function_tags': tags + [ROUND.lower(), 'internal'],
            'origin': SRC_INTERNAL,
            'version': '1.0.0',
            'l2_status': 'l2-pass',
            'registered_at': NOW,
            'file': '%s/%s.st' % (cat, name),
        })
        added.append((name, cat, ctype, cmplx, desc, tags, body))
    # counts
    from collections import Counter
    cc = Counter(c['category'] for c in d['components'])
    cm = Counter(c['complexity'] for c in d['components'])
    d['counts'] = {k: cc[k] for k in ('DL_Base','DL_MathData','DL_Algo','DL_Device','DL_Motion','DL_Process')}
    d['counts']['complexity'] = {str(k): cm[k] for k in sorted(cm)}
    d['total_components'] = len(d['components'])
    assert sum(v for k, v in d['counts'].items() if k != 'complexity') == d['total_components'], 'counts sum mismatch'
    d['version'] = '2.74.0'
    d['last_updated'] = NOW
    json.dump(d, open(REG, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

    with io.open(JSONL, 'a', encoding='utf-8') as f:
        for (name, cat, ctype, cmplx, desc, tags, body) in added:
            f.write(json.dumps(make_record(name, cat, ctype, cmplx, desc, tags, body), ensure_ascii=False) + '\n')

    print('accepted list', len(acc), '| registered', len(added), '| skipped(not accepted)', len(skipped), '| problems', len(missing))
    for m in missing: print('  !', m)
    print('registry total', d['total_components'])
    print('counts', d['counts'])
    nl = sum(1 for _ in io.open(JSONL, encoding='utf-8'))
    print('jsonl lines', nl)


if __name__ == '__main__':
    main()
