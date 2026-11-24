# -*- coding: utf-8 -*-
import json, os, datetime

TS = datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S+08:00')
reg = json.load(open('INDEX_REGISTRY.json', encoding='utf-8'))
existing = {i['name'] for i in reg['components']}
disk = set()
for cat in ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Device', 'DL_Motion', 'DL_Process']:
    for f in os.listdir(cat):
        if f.endswith('.st'):
            disk.add(f[:-3])

T = []


def add(name, cat, typ, cplx, tags, func, band, batch):
    T.append(dict(name=name, category=cat, type=typ, complexity=cplx,
                  function_tags=tags, function=func, band=band, batch=batch))


# ================= 复杂 4 件 =================
add('FB_DL_TrapezoidProfilePlanner', 'DL_Motion', 'FB', 4,
    ['motion', 'planning', 'profile', 'r86', 'factory'],
    '梯形/三角速度规划：起止速度不等，距离不足自动降级为三角曲线，逐周期输出设定值与完成/超差标志',
    'complex', 'C1')
add('FB_DL_AxisProbeTouchOffSeq', 'DL_Motion', 'FB', 3,
    ['motion', 'probing', 'sequence', 'r86', 'factory'],
    '探针触测状态机：快进-慢进-触发记录-回退，超程与未触发超时双兜底',
    'complex', 'C1')
add('FB_DL_SensorConsensusSelector', 'DL_Algo', 'FB', 3,
    ['algo', 'consensus', 'redundancy', 'r86', 'factory'],
    '多通道传感器共识选择：中位基准+偏差带剔除+通道不足降级到单通道，ENUM 状态机',
    'complex', 'C1')
add('FB_DL_Q15BiquadFilter', 'DL_Algo', 'FB', 3,
    ['algo', 'dsp', 'q15', 'filter', 'r86', 'factory'],
    'Q15 定点二阶 IIR 滤波：系数定点化、中间累加防溢出、移位饱和输出',
    'complex', 'C1')

# ================= 族A：Q15 定点算术（DL_Base, C1~C2） =================
famA = [
    ('FC_DL_Q15AddSat', 'Q15 定点加法饱和，越界钳到 Q15_MAX/Q15_MIN', 2),
    ('FC_DL_Q15SubSat', 'Q15 定点减法饱和', 2),
    ('FC_DL_Q15MulSat', 'Q15 乘 Q15 得 Q15，中间 DINT 防溢出，含右移舍入', 2),
    ('FC_DL_Q15DivSafe', 'Q15 安全除法，除零与商越界双保护', 2),
    ('FC_DL_Q15AbsSat', 'Q15 取绝对值饱和，正确处理 -32768 边界', 1),
    ('FC_DL_Q15NegSat', 'Q15 取负饱和，-32768 不回绕', 1),
    ('FC_DL_Q15Lerp', 'Q15 线性插值，alpha 定点，端点饱和', 2),
    ('FC_DL_Q15SqrtFloor', 'Q15 定点整数平方根（逐位法），结果 Q15', 2),
    ('FC_DL_RealToQ15Sat', 'REAL 转 Q15 定点，四舍五入加饱和，非有限值归零', 1),
]
for i, (n, f, c) in enumerate(famA, 1):
    add(n, 'DL_Base', 'FC', c, ['base', 'fixedpoint', 'q15', 'r86', 'familyA'], f, 'simple', 'C2-' + str(i))

# ================= 族B：工程单位换算补族（DL_Base, C1~C2） =================
famB = [
    ('FC_DL_EnthalpyUnitConvert', '比焓换算 kJ/kg 与 kcal/kg 与 BTU/lb', 1),
    ('FC_DL_SpecificHeatUnitConvert', '比热容换算 kJ/(kg*K) 与 BTU/(lb*F)', 1),
    ('FC_DL_ConcUnitConvert', '浓度换算 ppm 与 % 与 mg/L', 1),
    ('FC_DL_LevelUnitConvert', '液位换算 m/mm/%，按罐高换算', 1),
    ('FC_DL_CurrentUnitConvert', '电流换算 A/mA/kA', 1),
    ('FC_DL_TempDiffUnitConvert', '温差换算 K 与摄氏差值与华氏差值，无偏移项', 1),
    ('FC_DL_HeatFluxUnitConvert', '热流密度换算 W/m2 与 kcal/(h*m2)', 2),
    ('FC_DL_HtcUnitConvert', '传热系数换算 W/(m2*K) 与 kcal/(h*m2*C) 与 BTU/(h*ft2*F)', 2),
    ('FC_DL_VoltageUnitConvert', '电压换算 V/mV/kV', 1),
]
for i, (n, f, c) in enumerate(famB, 1):
    add(n, 'DL_Base', 'FC', c, ['base', 'unit', 'conversion', 'r86', 'familyB'], f, 'simple', 'C3-' + str(i))

# ================= 族D：量程映射（DL_Base, C1~C2） =================
famD = [
    ('FC_DL_MapRangeClamped', '双端量程映射并对输入钳位', 2),
    ('FC_DL_MapRangeBipolar', '双极性对称映射，中点偏置', 2),
    ('FC_DL_MapRangePercent', '百分比与工程值互映，枚举方向', 1),
    ('FC_DL_MapRangeInverseSolve', '由工程值反解原始量程值，含钳位', 2),
    ('FC_DL_MapRangePiecewise3', '三段折线映射，分段斜率加断点连续校验', 2),
    ('FC_DL_MapRangeDeadband', '带中心死区的量程映射，死区内输出中点', 2),
    ('FC_DL_MapRangeSatOut', '输入量程映射后对输出独立饱和限幅', 2),
    ('FC_DL_MapRangeIntQuant', '量程映射加整数量化，步长加四舍五入', 2),
    ('FC_DL_MapRangeHystSwitch', '带滞环的二态阈值映射', 2),
]
for i, (n, f, c) in enumerate(famD, 1):
    add(n, 'DL_Base', 'FC', c, ['base', 'mapping', 'range', 'r86', 'familyD'], f, 'simple', 'C4-' + str(i))

# ================= 族C：饱和算术（DL_MathData, C1~C2） =================
famC = [
    ('FC_DL_SatAddDint', 'DINT 加法饱和，上下界检测', 2),
    ('FC_DL_SatSubDint', 'DINT 减法饱和', 2),
    ('FC_DL_SatMulDint', 'DINT 乘法饱和，先判溢出条件再乘', 2),
    ('FC_DL_SatAddLreal', 'LREAL 加法饱和加非有限值闸', 2),
    ('FC_DL_SatMulLreal', 'LREAL 乘法饱和加非有限值闸', 2),
    ('FC_DL_SatNegDint', 'DINT 取负饱和，DINT_MIN 不回绕', 1),
    ('FC_DL_SatScaleLreal', 'LREAL 增益缩放饱和', 2),
    ('FC_DL_SatSumArrayDint', 'DINT 定长数组累加饱和，逐项防溢出', 2),
    ('FC_DL_SatClampLrealBand', 'LREAL 区间钳位，带上下限合法性自检', 1),
]
for i, (n, f, c) in enumerate(famC, 1):
    add(n, 'DL_MathData', 'FC', c, ['mathdata', 'saturation', 'arithmetic', 'r86', 'familyC'], f, 'simple', 'C5-' + str(i))

# ---- 撞名与磁盘差集前置 ----
dup_reg = [t['name'] for t in T if t['name'] in existing]
dup_disk = [t['name'] for t in T if t['name'] in disk]
assert not dup_reg and not dup_disk, 'NAME COLLISION reg=%s disk=%s' % (dup_reg, dup_disk)
names = [t['name'] for t in T]
assert len(names) == len(set(names)) == 40, (len(names), len(set(names)))

n_complex = sum(1 for t in T if t['band'] == 'complex')
n_simple = sum(1 for t in T if t['band'] == 'simple')
assert n_complex <= 4 and n_simple >= 36, (n_complex, n_simple)

out = dict(round='R86', ts=TS, total=40, complex=n_complex, simple=n_simple,
           targets=T, dup_checked=dict(registry=len(existing), disk=len(disk), collided=0))
json.dump(out, open('_Staging_Raw/2026-11-24/r86_targets.json', 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print('OK targets=40 complex=%d simple=%d' % (n_complex, n_simple))
print('registry=%d disk=%d collision=0' % (len(existing), len(disk)))
