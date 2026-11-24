# -*- coding: utf-8 -*-
"""R86 收口：registry 注册 + JSONL 追加 + 三方对账"""
import json, os, io, datetime, shutil

TS = datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S+08:00')
ROOT = 'C:\\Library'
STAGE = os.path.join(ROOT, '_Staging_Raw', '2026-11-24')
targets = json.load(open(os.path.join(STAGE, 'r86_targets.json'), encoding='utf-8'))['targets']
approved = json.load(open(os.path.join(STAGE, 'r86_approved.json'), encoding='utf-8'))
appr = set(approved['approved'])
notes = approved.get('notes', {})

regpath = os.path.join(ROOT, 'INDEX_REGISTRY.json')
reg = json.load(open(regpath, encoding='utf-8'))
have = {c['name'] for c in reg['components']}

JSONL = os.path.join(ROOT, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl')

ARCH = {
    'familyA': ('采用「DINT 中间量 + 出口饱和」两段式结构：所有运算在 32 位整数域完成，避免 INT 域回绕；'
                '出口统一经饱和函数钳到 Q15_MAX/Q15_MIN，保证任何输入组合都不产生未定义值。'
                '防错要点：乘除先判溢出条件再执行、除零前置早退、NaN/Inf 在入口归零。OOP 解耦：'
                '全部为无状态 FC，纯函数式，便于在 FB 内多次内联而不共享状态。'),
    'familyB': ('采用「枚举选择 + 换算因子常量表 + 有效性出口」结构。先校验枚举合法性与输入有限性，'
                '不合法立即置 xValid=FALSE 并输出 0.0，绝不返回未定义值；换算因子集中为带注释常量，'
                '便于审计量纲。防错要点：非有限输入闸、未知枚举兜底、温差类严禁叠加 273.15 偏移。'
                'OOP 解耦：无状态 FC，同一接口签名，可直接映射到 HMI 单位选择下拉。'),
    'familyD': ('采用「双端量程对 + 输入钳位 + 独立输出饱和」三段式：先校验 fInMax<>fInMin 防除零，'
                '再归一化到 0~1，最后按输出量程放缩。反解件用逆映射求解并钳位；折线件校验断点单调、'
                '分段斜率连续；滞环件用双阈值状态保持消除抖动。防错要点：区间退化、反向量程(Min>Max)、'
                '死区宽度超量程、量化步长为 0。OOP 解耦：量程参数成组传入，不依赖外部配置。'),
    'familyC': ('采用「先判界后运算」的饱和算术：DINT 域先用上下界与操作数符号判定是否溢出，'
                '再执行原生运算，避免先溢出后纠正的错误路径；LREAL 域先过非有限值闸再运算，'
                '结果用 MIN/MAX 双向钳位。防错要点：DINT_MIN 取负必饱和、乘法用除法反判、'
                '数组累加逐项防溢出而非先和后判。OOP 解耦：全为纯 FC，可在任意表达式位置调用。'),
}
COMPLEX_ARCH = {
    'FB_DL_TrapezoidProfilePlanner': (
        '架构：状态机 E_TrapSegment（IDLE/ACCEL/CRUISE/DECEL/DONE/FAULT）+ CASE 全分支 + ELSE→FAULT。'
        '三段时间先离线求解再逐周期推进，避免每周期重算带来的累积误差。距离不足时降级三角曲线：'
        '以 v0、v1、a 解峰值速度，判别式<0 判定不可达并直接 FAULT，开方前钳非负。'
        '防错：fDt<=0 早退、加速度<=0 早退、位移为 0 直接 DONE、每段剩余时间负值钳零防越界。'
        'OOP 解耦：规划(纯计算)与执行(周期推进)分离，规划结果存为段表，便于回放与单元测试。'),
    'FB_DL_AxisProbeTouchOffSeq': (
        '架构：E_ProbeState 七态（IDLE/FAST_APPROACH/SLOW_APPROACH/DWELL/RETRACT/RECORD/FAULT）+ CASE + ELSE 兜底。'
        'TON 实例全部在 CASE 之外无条件每周期调用（R7），保证计时基准不因分支跳变而漂移。'
        '双兜底：超程看门狗（fPosAct > fSoftMax 即刻 FAULT）与未触发超时（慢进阶段 TON 到期仍无触发信号 → FAULT）。'
        'FAULT 时保持最后有效 fProbePos 不刷新，防止上位机读到 0 造成误判。'
        'OOP 解耦：与轴接口解耦，只吃位置反馈与输出指令，可套任意伺服。'),
    'FB_DL_SensorConsensusSelector': (
        '架构：E_ConsMode 三态（NORMAL/DEGRADED/LOST）+ CASE + ELSE 兜底；每周期先统计有效通道数再择路。'
        '≥3 通道：取中位数为基准，剔除偏离超 fDevBand 的通道后对剩余平均，兼具抗单点故障与降噪；'
        '=2 均值降级；=1 直通降级；=0 保持上值并置 xLost，绝不输出 0 冒充真实测量。'
        '防错：通道数组定长 R15 无 VLA、有效位与数值分开判、上值保持用独立保持变量。'
        'OOP 解耦：通道数与偏差带参数化，ARRAY[0..4] 定长直接映射到任意冗余配置。'),
    'FB_DL_Q15BiquadFilter': (
        '架构：直接 II 型转置结构（Direct Form II Transposed），状态仅两级，定点下数值条件最好。'
        '系数与历史全为 INT(Q15)，中间累加用 DINT 并在每级后右移饱和，防止级间溢出。'
        '内部自写 Q15 乘加（R16 零外部依赖），不调用同轮未过闸的 FC。'
        '防错：xEnable 下降沿清历史防残值冲击、每级饱和置 xOverflow 供上游诊断、系数全零时直通防死锁。'
        'OOP 解耦：系数外部整组下发，滤波器本体不含整定逻辑，便于在线切换。'),
}

for t in targets:
    if t['name'] not in appr:
        continue
    n = t['name']
    if n in have:
        continue
    fam = [x for x in t['function_tags'] if x.startswith('family')]
    arch = COMPLEX_ARCH.get(n) or ARCH.get(fam[0] if fam else 'familyC')
    reg['components'].append(dict(
        name=n, category=t['category'], type=t['type'],
        file_path=os.path.join(ROOT, t['category'], n + '.st'),
        function_tags=t['function_tags'] + ['l2-pass'],
        complexity=t['complexity'],
        registered_at=TS,
        origin=dict(mode='internal', source='道莅原创（clean-room 自研，IEC 61131-3 通用算法）',
                    license='MIT', ref_tag='R86-V'),
        version='1.0.0',
        l2_status='l2-pass',
        qa_status=notes.get(n, 'pass'),
        function=t['function'],
    ))
    have.add(n)

# counts
counts = {}
for c in reg['components']:
    counts[c['category']] = counts.get(c['category'], 0) + 1
reg['counts'] = counts
reg['total_components'] = len(reg['components'])
reg['version'] = 'v2.78.0'
reg['last_updated'] = TS
shutil.copy(regpath, regpath + '.bak_r86')
json.dump(reg, open(regpath, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

# JSONL 追加
existing_lines = sum(1 for _ in open(JSONL, encoding='utf-8'))
shutil.copy(JSONL, JSONL + '.bak_r86')
newcnt = 0
with open(JSONL, 'a', encoding='utf-8') as f:
    for t in targets:
        if t['name'] not in appr:
            continue
        n = t['name']
        src = open(os.path.join(ROOT, t['category'], n + '.st'), encoding='utf-8').read()
        fam = [x for x in t['function_tags'] if x.startswith('family')]
        arch = COMPLEX_ARCH.get(n) or ARCH.get(fam[0] if fam else 'familyC')
        instr = ('【工况需求】在工业控制器（IEC 61131-3 / CODESYS / RuSTy 兼容）中实现 %s：%s。'
                 '【边界条件】输入须做除零与越界防护、浮点比较须带容差、非法枚举与输入须返回有效性标志而非未定义值；'
                 '不得使用物理地址、全局变量或外部依赖，须可在任意平台独立编译。') % (n, t['function'])
        obj = dict(instruction=instr, architecture_thought=arch, output=src,
                   meta=dict(name=n, category=t['category'], complexity=t['complexity'],
                             tags=t['function_tags'], round='R86', license='MIT'))
        f.write(json.dumps(obj, ensure_ascii=False) + '\n')
        newcnt += 1

jl_lines = sum(1 for _ in open(JSONL, encoding='utf-8'))
st_count = 0
for cat in ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']:
    st_count += len([x for x in os.listdir(os.path.join(ROOT, cat)) if x.endswith('.st')])

res = dict(ts=TS, registry=len(reg['components']), jsonl=jl_lines, st_files=st_count,
           new_registered=newcnt, counts=counts,
           jsonl_before=existing_lines, jsonl_added=newcnt)
json.dump(res, open(os.path.join(STAGE, 'r86_closeout.json'), 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print(json.dumps(res, ensure_ascii=False, indent=1))
