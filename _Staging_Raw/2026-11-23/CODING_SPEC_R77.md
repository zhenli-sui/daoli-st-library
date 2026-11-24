# CODING_SPEC_R77 —— 编码席派发清单（45 件，按批次顺序写盘）

## 批次 B2（20 件）
1. `FC_DL_StringPadLeftZeros` → C:\Library\DL_Base\FC_DL_StringPadLeftZeros.st ｜ C1 ｜ 左补零至定长（编号/时间戳规范化），超长原样返回并置 bOverflow
2. `FC_DL_StringTruncEllipsis` → C:\Library\DL_Base\FC_DL_StringTruncEllipsis.st ｜ C2 ｜ 超长截断并补省略标记，返回实际写入长度
3. `FC_DL_StringCountChar` → C:\Library\DL_Base\FC_DL_StringCountChar.st ｜ C1 ｜ 统计指定字符出现次数（HMI 报文分隔符计数）
4. `FC_DL_StringReverse` → C:\Library\DL_Base\FC_DL_StringReverse.st ｜ C2 ｜ 字符串反转（回文校验/字节序调试）
5. `FC_DL_StringIsNumeric` → C:\Library\DL_Base\FC_DL_StringIsNumeric.st ｜ C1 ｜ 数值合法性校验（可选符号、单小数点、指数标记）
6. `FC_DL_StringRemoveWhitespace` → C:\Library\DL_Base\FC_DL_StringRemoveWhitespace.st ｜ C2 ｜ 剔除全部空白字符（空格/TAB），压缩报文
7. `FC_DL_StringSplitPair` → C:\Library\DL_Base\FC_DL_StringSplitPair.st ｜ C1 ｜ key=value 单对拆分，缺分隔符置无效回执
8. `FC_DL_StringRepeat` → C:\Library\DL_Base\FC_DL_StringRepeat.st ｜ C2 ｜ 按次数重复拼接，超缓冲保护并回执截断
9. `FC_DL_StringCompareNatural` → C:\Library\DL_Base\FC_DL_StringCompareNatural.st ｜ C1 ｜ 自然序比较（数字段按数值比较，A2 < A10）
10. `FC_DL_StringCsvFieldEscape` → C:\Library\DL_Base\FC_DL_StringCsvFieldEscape.st ｜ C2 ｜ CSV 字段转义（含逗号/引号/换行时加引号并双写引号）
11. `FC_DL_LengthUnitConvert` → C:\Library\DL_MathData\FC_DL_LengthUnitConvert.st ｜ C1 ｜ 长度换算 mm/m/inch/ft，含目标单位枚举与零/负值保护
12. `FC_DL_MassUnitConvert` → C:\Library\DL_MathData\FC_DL_MassUnitConvert.st ｜ C2 ｜ 质量换算 kg/g/lb/oz
13. `FC_DL_VolumeUnitConvert` → C:\Library\DL_MathData\FC_DL_VolumeUnitConvert.st ｜ C1 ｜ 体积/容积换算 L/m3/gal(US)/mL
14. `FC_DL_AreaUnitConvert` → C:\Library\DL_MathData\FC_DL_AreaUnitConvert.st ｜ C2 ｜ 面积换算 m2/mm2/ft2
15. `FC_DL_DensityUnitConvert` → C:\Library\DL_MathData\FC_DL_DensityUnitConvert.st ｜ C1 ｜ 密度换算 kg/m3、g/cm3、lb/ft3（零密度保护）
16. `FC_DL_ViscosityUnitConvert` → C:\Library\DL_MathData\FC_DL_ViscosityUnitConvert.st ｜ C2 ｜ 运动粘度换算 cSt/mm2s，温度不补偿（注明适用域）
17. `FC_DL_EnergyUnitConvert` → C:\Library\DL_MathData\FC_DL_EnergyUnitConvert.st ｜ C1 ｜ 能量换算 kJ/kWh/cal/BTU
18. `FC_DL_PowerUnitConvert` → C:\Library\DL_MathData\FC_DL_PowerUnitConvert.st ｜ C2 ｜ 功率换算 kW/HP/W
19. `FC_DL_HumidityUnitConvert` → C:\Library\DL_MathData\FC_DL_HumidityUnitConvert.st ｜ C1 ｜ 湿度换算 RH% 与绝对湿度 g/m3（需温度与饱和压近似式）
20. `FC_DL_ConcentrationUnitConvert` → C:\Library\DL_MathData\FC_DL_ConcentrationUnitConvert.st ｜ C2 ｜ 浓度换算 ppm/%/mg/m3（标况假设注明）

## 批次 B3（21 件）
1. `FC_DL_TableLookupDescending` → C:\Library\DL_MathData\FC_DL_TableLookupDescending.st ｜ C2 ｜ 降序表查找定位（区间下标+段内比例），越界钳位
2. `FC_DL_TableLookupNearestIndex` → C:\Library\DL_MathData\FC_DL_TableLookupNearestIndex.st ｜ C2 ｜ 最近节点索引查找（等距/非等距通用）
3. `FC_DL_InterpLogLinear` → C:\Library\DL_MathData\FC_DL_InterpLogLinear.st ｜ C2 ｜ 对数-线性插值（跨数量级工艺曲线）
4. `FC_DL_InterpTwoPointSlope` → C:\Library\DL_MathData\FC_DL_InterpTwoPointSlope.st ｜ C2 ｜ 两点定斜率外推，带外推距离上限保护
5. `FC_DL_TableIndexBinarySearch` → C:\Library\DL_MathData\FC_DL_TableIndexBinarySearch.st ｜ C2 ｜ 二分查找定位表区间（大表 O(log n)）
6. `FC_DL_InterpHoldLast` → C:\Library\DL_MathData\FC_DL_InterpHoldLast.st ｜ C2 ｜ 保持型查表：超出末节点保持末值，不外推
7. `FC_DL_TableReverseLookupX` → C:\Library\DL_MathData\FC_DL_TableReverseLookupX.st ｜ C2 ｜ 由 Y 反查 X（单调表反解，非单调置无效）
8. `FC_DL_InterpSegmentWeight` → C:\Library\DL_MathData\FC_DL_InterpSegmentWeight.st ｜ C2 ｜ 段内权重计算（返回相邻两点权重）
9. `FB_DL_RunningAverageN` → C:\Library\DL_Algo\FB_DL_RunningAverageN.st ｜ C2 ｜ N 点滑动均值（环形缓冲，N 可配 1..32）
10. `FB_DL_PeakHoldFilter` → C:\Library\DL_Algo\FB_DL_PeakHoldFilter.st ｜ C2 ｜ 峰值保持，带复位与保持时长
11. `FB_DL_RateOfChangeFilter` → C:\Library\DL_Algo\FB_DL_RateOfChangeFilter.st ｜ C2 ｜ 变化率限幅（每周期最大增量），抑制阶跃冲击
12. `FB_DL_GatedUpdateFilter` → C:\Library\DL_Algo\FB_DL_GatedUpdateFilter.st ｜ C2 ｜ 门控更新滤波：仅在允许窗口内采样，否则保持
13. `FB_DL_HoldLastGoodFilter` → C:\Library\DL_Algo\FB_DL_HoldLastGoodFilter.st ｜ C2 ｜ 坏值保持：判据失效时输出上一有效值并计时
14. `FB_DL_DeadbandFilter` → C:\Library\DL_Algo\FB_DL_DeadbandFilter.st ｜ C2 ｜ 双向死区+输出保持（近邻 FC_DL_Deadband 为无状态单值死区）
15. `FB_DL_QuantizeFilter` → C:\Library\DL_Algo\FB_DL_QuantizeFilter.st ｜ C2 ｜ 量化取整+回差防抖（近邻 FC_DL_QuantizeStep 为无状态取整）
16. `FC_DL_StatsMeanStdDev` → C:\Library\DL_MathData\FC_DL_StatsMeanStdDev.st ｜ C2 ｜ 均值与标准差（Welford 单遍，防溢出）
17. `FC_DL_StatsMinMaxWindow` → C:\Library\DL_MathData\FC_DL_StatsMinMaxWindow.st ｜ C2 ｜ 窗口极值与发生时刻
18. `FC_DL_StatsPercentile` → C:\Library\DL_MathData\FC_DL_StatsPercentile.st ｜ C2 ｜ 分位数（P50/P90/P95，排序法，N 不大于 64）
19. `FC_DL_StatsRmsCalc` → C:\Library\DL_MathData\FC_DL_StatsRmsCalc.st ｜ C2 ｜ 有效值 RMS（交流量监测）
20. `FC_DL_StatsZeroCrossRate` → C:\Library\DL_MathData\FC_DL_StatsZeroCrossRate.st ｜ C2 ｜ 过零率统计（振动/流量脉动特征）
21. `FC_DL_StatsOutlierCount` → C:\Library\DL_MathData\FC_DL_StatsOutlierCount.st ｜ C2 ｜ 离群点计数（3 sigma 判据，带样本不足保护）

## 批次 B1（4 件）
1. `FB_DL_DualEncoderDeviationWatch` → C:\Library\DL_Motion\FB_DL_DualEncoderDeviationWatch.st ｜ C4 ｜ 双编码器（电机/负载）偏差监测，含启动屏蔽窗口、分级报警、超限停机请求
2. `FB_DL_MoldCoolingZoneSeq` → C:\Library\DL_Process\FB_DL_MoldCoolingZoneSeq.st ｜ C4 ｜ 注塑模具分区冷却时序：预热→分区通水→温差平衡→吹扫，含超时与单区故障降级
3. `FB_DL_AnalogInputRedundancySel` → C:\Library\DL_Device\FB_DL_AnalogInputRedundancySel.st ｜ C3 ｜ 双路模拟量冗余选择：偏差判据、坏值剔除、无扰切换与保持，输出有效性回执
4. `FC_DL_ModbusRtuFrameBuild` → C:\Library\DL_Algo\FC_DL_ModbusRtuFrameBuild.st ｜ C3 ｜ Modbus RTU 帧构造：站号+功能码+数据+CRC16，输出帧长与合法性回执（与在库 FrameCheck 构成构造/校验对）
