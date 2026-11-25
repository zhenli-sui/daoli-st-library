# -*- coding: utf-8 -*-
rows = []
def add(name, cat, func, tag, cx, batch, tier, src):
    rows.append((name, cat, func, tag, cx, batch, tier, src))

add('FB_DL_DualEncoderDeviationWatch','DL_Motion','双编码器（电机/负载）偏差监测，含启动屏蔽窗口、分级报警、超限停机请求','self-std','C4','B1','复杂','自研（近邻 FB_DL_AxisLoadEncoderLossMonitor 为丢失检测，本件为偏差量监测）')
add('FB_DL_MoldCoolingZoneSeq','DL_Process','注塑模具分区冷却时序：预热→分区通水→温差平衡→吹扫，含超时与单区故障降级','self-std','C4','B1','复杂','自研')
add('FB_DL_AnalogInputRedundancySel','DL_Device','双路模拟量冗余选择：偏差判据、坏值剔除、无扰切换与保持，输出有效性回执','self-std','C3','B1','复杂','自研')
add('FC_DL_ModbusRtuFrameBuild','DL_Algo','Modbus RTU 帧构造：站号+功能码+数据+CRC16，输出帧长与合法性回执（与在库 FrameCheck 构成构造/校验对）','self-std','C3','B1','复杂','自研（近邻 FC_DL_ModbusRtuFrameCheck 为校验侧）')

famA = [
 ('FC_DL_StringPadLeftZeros','左补零至定长（编号/时间戳规范化），超长原样返回并置 bOverflow'),
 ('FC_DL_StringTruncEllipsis','超长截断并补省略标记，返回实际写入长度'),
 ('FC_DL_StringCountChar','统计指定字符出现次数（HMI 报文分隔符计数）'),
 ('FC_DL_StringReverse','字符串反转（回文校验/字节序调试）'),
 ('FC_DL_StringIsNumeric','数值合法性校验（可选符号、单小数点、指数标记）'),
 ('FC_DL_StringRemoveWhitespace','剔除全部空白字符（空格/TAB），压缩报文'),
 ('FC_DL_StringSplitPair','key=value 单对拆分，缺分隔符置无效回执'),
 ('FC_DL_StringRepeat','按次数重复拼接，超缓冲保护并回执截断'),
 ('FC_DL_StringCompareNatural','自然序比较（数字段按数值比较，A2 < A10）'),
 ('FC_DL_StringCsvFieldEscape','CSV 字段转义（含逗号/引号/换行时加引号并双写引号）')]
for i,(n,f) in enumerate(famA,1):
    add(n,'DL_Base',f,'iec-std-wrapper','C1' if i%2 else 'C2','B2','简单','自研（字符串族模板派生）')

famB = [
 ('FC_DL_LengthUnitConvert','长度换算 mm/m/inch/ft，含目标单位枚举与零/负值保护'),
 ('FC_DL_MassUnitConvert','质量换算 kg/g/lb/oz'),
 ('FC_DL_VolumeUnitConvert','体积/容积换算 L/m3/gal(US)/mL'),
 ('FC_DL_AreaUnitConvert','面积换算 m2/mm2/ft2'),
 ('FC_DL_DensityUnitConvert','密度换算 kg/m3、g/cm3、lb/ft3（零密度保护）'),
 ('FC_DL_ViscosityUnitConvert','运动粘度换算 cSt/mm2s，温度不补偿（注明适用域）'),
 ('FC_DL_EnergyUnitConvert','能量换算 kJ/kWh/cal/BTU'),
 ('FC_DL_PowerUnitConvert','功率换算 kW/HP/W'),
 ('FC_DL_HumidityUnitConvert','湿度换算 RH% 与绝对湿度 g/m3（需温度与饱和压近似式）'),
 ('FC_DL_ConcentrationUnitConvert','浓度换算 ppm/%/mg/m3（标况假设注明）')]
for i,(n,f) in enumerate(famB,1):
    add(n,'DL_MathData',f,'lgf-math','C1' if i%2 else 'C2','B2','简单','自研（单位换算族模板派生）')

famC = [
 ('FC_DL_TableLookupDescending','降序表查找定位（区间下标+段内比例），越界钳位'),
 ('FC_DL_TableLookupNearestIndex','最近节点索引查找（等距/非等距通用）'),
 ('FC_DL_InterpLogLinear','对数-线性插值（跨数量级工艺曲线）'),
 ('FC_DL_InterpTwoPointSlope','两点定斜率外推，带外推距离上限保护'),
 ('FC_DL_TableIndexBinarySearch','二分查找定位表区间（大表 O(log n)）'),
 ('FC_DL_InterpHoldLast','保持型查表：超出末节点保持末值，不外推'),
 ('FC_DL_TableReverseLookupX','由 Y 反查 X（单调表反解，非单调置无效）'),
 ('FC_DL_InterpSegmentWeight','段内权重计算（返回相邻两点权重）')]
for n,f in famC:
    add(n,'DL_MathData',f,'lgf-math','C2','B3','简单','自研（插值族模板派生）')

famD = [
 ('FB_DL_RunningAverageN','N 点滑动均值（环形缓冲，N 可配 1..32）'),
 ('FB_DL_PeakHoldFilter','峰值保持，带复位与保持时长'),
 ('FB_DL_RateOfChangeFilter','变化率限幅（每周期最大增量），抑制阶跃冲击'),
 ('FB_DL_GatedUpdateFilter','门控更新滤波：仅在允许窗口内采样，否则保持'),
 ('FB_DL_HoldLastGoodFilter','坏值保持：判据失效时输出上一有效值并计时'),
 ('FB_DL_DeadbandFilter','双向死区+输出保持（近邻 FC_DL_Deadband 为无状态单值死区）'),
 ('FB_DL_QuantizeFilter','量化取整+回差防抖（近邻 FC_DL_QuantizeStep 为无状态取整）')]
for n,f in famD:
    add(n,'DL_Algo',f,'self-std','C2','B3','简单','自研（滤波族模板派生）')

famE = [
 ('FC_DL_StatsMeanStdDev','均值与标准差（Welford 单遍，防溢出）'),
 ('FC_DL_StatsMinMaxWindow','窗口极值与发生时刻'),
 ('FC_DL_StatsPercentile','分位数（P50/P90/P95，排序法，N 不大于 64）'),
 ('FC_DL_StatsRmsCalc','有效值 RMS（交流量监测）'),
 ('FC_DL_StatsZeroCrossRate','过零率统计（振动/流量脉动特征）'),
 ('FC_DL_StatsOutlierCount','离群点计数（3 sigma 判据，带样本不足保护）')]
for n,f in famE:
    add(n,'DL_MathData',f,'self-std','C2','B3','简单','自研（统计族模板派生）')

lines = ['# ROUND_PLAN_R77（2026-11-23，R77 轮）','',
 '目标 45 件：**复杂 C3~C4 x4**（上限 4，冲刺模式）+ **简单 C1~C2 x41**（占比 91%）。修复名额 **0**（当日非首轮，按产能铁律归零），修复件不计产出。',
 '简单件按 5 族模板派生，编码席每批一次调用批量写盘（严禁一件一调用）。','',
 '| # | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |','|---|---|---|---|---|---|---|---|---|']
for i,(n,cat,f,tag,cx,b,tier,src) in enumerate(rows,1):
    pre = 'FB_DL_' if n.startswith('FB_') else 'FC_DL_'
    lines.append('| %d | %s | %s | %s | %s | %s | %s | %s | %s |' % (i,n,cat,pre,f,tag,cx,b,tier))
lines += ['','## 批次编排',
 '- B1（复杂 4）：一次派发，编码席单次调用顺序写盘 4 件。',
 '- B2（简单 20）：族A 字符串 10 + 族B 单位换算 10，编码席单次调用写盘 20 件。',
 '- B3（简单 21）：族C 插值 8 + 族D 滤波 7 + 族E 统计 6，编码席单次调用写盘 21 件。','',
 '## 撞名与语义三查（规划阶段已执行）',
 '- 驳回/改名留痕 6 条：`FC_DL_Crc16ModbusTable`（撞在库 Crc16Modbus/Crc16Generic）、`FC_DL_PolynomialEvalHorner`（在库 PolyEvalHorner 已占）、`FB_DL_TankLevelVote2oo3`（Vote2oo3/VoteKooN 已占，语义重）、`FB_DL_SlewRateLimiter`（撞 FC_DL_SlewRateCalc）、`FB_DL_TrimmedMeanFilter`（撞 FC_DL_TrimmedMeanCalc）、`FB_DL_DebounceFilter`（撞 FB_DL_SignalDebounce）。',
 '- 保留但附邻件声明 2 条：`FB_DL_DeadbandFilter`、`FB_DL_QuantizeFilter`，均为状态型变体（在库为无状态 FC），属有效差异。','',
 '## 里程碑检查点',
 '- T+15 规划表落盘 ｜ T+40 编码交付 41 件 ｜ T+50 闸裁决 41 件 ｜ T+60 入库与战报收口']
open('_Staging_Raw/2026-11-23/ROUND_PLAN_R77.md','w',encoding='utf-8').write('\n'.join(lines))
print('rows', len(rows), 'complex', sum(1 for r in rows if r[6]=='复杂'), 'simple', sum(1 for r in rows if r[6]=='简单'))
