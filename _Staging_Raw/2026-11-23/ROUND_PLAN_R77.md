# ROUND_PLAN_R77（2026-11-23，R77 轮）

目标 45 件：**复杂 C3~C4 x4**（上限 4，冲刺模式）+ **简单 C1~C2 x41**（占比 91%）。修复名额 **0**（当日非首轮，按产能铁律归零），修复件不计产出。
简单件按 5 族模板派生，编码席每批一次调用批量写盘（严禁一件一调用）。

| # | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | FB_DL_DualEncoderDeviationWatch | DL_Motion | FB_DL_ | 双编码器（电机/负载）偏差监测，含启动屏蔽窗口、分级报警、超限停机请求 | self-std | C4 | B1 | 复杂 |
| 2 | FB_DL_MoldCoolingZoneSeq | DL_Process | FB_DL_ | 注塑模具分区冷却时序：预热→分区通水→温差平衡→吹扫，含超时与单区故障降级 | self-std | C4 | B1 | 复杂 |
| 3 | FB_DL_AnalogInputRedundancySel | DL_Device | FB_DL_ | 双路模拟量冗余选择：偏差判据、坏值剔除、无扰切换与保持，输出有效性回执 | self-std | C3 | B1 | 复杂 |
| 4 | FC_DL_ModbusRtuFrameBuild | DL_Algo | FC_DL_ | Modbus RTU 帧构造：站号+功能码+数据+CRC16，输出帧长与合法性回执（与在库 FrameCheck 构成构造/校验对） | self-std | C3 | B1 | 复杂 |
| 5 | FC_DL_StringPadLeftZeros | DL_Base | FC_DL_ | 左补零至定长（编号/时间戳规范化），超长原样返回并置 bOverflow | iec-std-wrapper | C1 | B2 | 简单 |
| 6 | FC_DL_StringTruncEllipsis | DL_Base | FC_DL_ | 超长截断并补省略标记，返回实际写入长度 | iec-std-wrapper | C2 | B2 | 简单 |
| 7 | FC_DL_StringCountChar | DL_Base | FC_DL_ | 统计指定字符出现次数（HMI 报文分隔符计数） | iec-std-wrapper | C1 | B2 | 简单 |
| 8 | FC_DL_StringReverse | DL_Base | FC_DL_ | 字符串反转（回文校验/字节序调试） | iec-std-wrapper | C2 | B2 | 简单 |
| 9 | FC_DL_StringIsNumeric | DL_Base | FC_DL_ | 数值合法性校验（可选符号、单小数点、指数标记） | iec-std-wrapper | C1 | B2 | 简单 |
| 10 | FC_DL_StringRemoveWhitespace | DL_Base | FC_DL_ | 剔除全部空白字符（空格/TAB），压缩报文 | iec-std-wrapper | C2 | B2 | 简单 |
| 11 | FC_DL_StringSplitPair | DL_Base | FC_DL_ | key=value 单对拆分，缺分隔符置无效回执 | iec-std-wrapper | C1 | B2 | 简单 |
| 12 | FC_DL_StringRepeat | DL_Base | FC_DL_ | 按次数重复拼接，超缓冲保护并回执截断 | iec-std-wrapper | C2 | B2 | 简单 |
| 13 | FC_DL_StringCompareNatural | DL_Base | FC_DL_ | 自然序比较（数字段按数值比较，A2 < A10） | iec-std-wrapper | C1 | B2 | 简单 |
| 14 | FC_DL_StringCsvFieldEscape | DL_Base | FC_DL_ | CSV 字段转义（含逗号/引号/换行时加引号并双写引号） | iec-std-wrapper | C2 | B2 | 简单 |
| 15 | FC_DL_LengthUnitConvert | DL_MathData | FC_DL_ | 长度换算 mm/m/inch/ft，含目标单位枚举与零/负值保护 | lgf-math | C1 | B2 | 简单 |
| 16 | FC_DL_MassUnitConvert | DL_MathData | FC_DL_ | 质量换算 kg/g/lb/oz | lgf-math | C2 | B2 | 简单 |
| 17 | FC_DL_VolumeUnitConvert | DL_MathData | FC_DL_ | 体积/容积换算 L/m3/gal(US)/mL | lgf-math | C1 | B2 | 简单 |
| 18 | FC_DL_AreaUnitConvert | DL_MathData | FC_DL_ | 面积换算 m2/mm2/ft2 | lgf-math | C2 | B2 | 简单 |
| 19 | FC_DL_DensityUnitConvert | DL_MathData | FC_DL_ | 密度换算 kg/m3、g/cm3、lb/ft3（零密度保护） | lgf-math | C1 | B2 | 简单 |
| 20 | FC_DL_ViscosityUnitConvert | DL_MathData | FC_DL_ | 运动粘度换算 cSt/mm2s，温度不补偿（注明适用域） | lgf-math | C2 | B2 | 简单 |
| 21 | FC_DL_EnergyUnitConvert | DL_MathData | FC_DL_ | 能量换算 kJ/kWh/cal/BTU | lgf-math | C1 | B2 | 简单 |
| 22 | FC_DL_PowerUnitConvert | DL_MathData | FC_DL_ | 功率换算 kW/HP/W | lgf-math | C2 | B2 | 简单 |
| 23 | FC_DL_HumidityUnitConvert | DL_MathData | FC_DL_ | 湿度换算 RH% 与绝对湿度 g/m3（需温度与饱和压近似式） | lgf-math | C1 | B2 | 简单 |
| 24 | FC_DL_ConcentrationUnitConvert | DL_MathData | FC_DL_ | 浓度换算 ppm/%/mg/m3（标况假设注明） | lgf-math | C2 | B2 | 简单 |
| 25 | FC_DL_TableLookupDescending | DL_MathData | FC_DL_ | 降序表查找定位（区间下标+段内比例），越界钳位 | lgf-math | C2 | B3 | 简单 |
| 26 | FC_DL_TableLookupNearestIndex | DL_MathData | FC_DL_ | 最近节点索引查找（等距/非等距通用） | lgf-math | C2 | B3 | 简单 |
| 27 | FC_DL_InterpLogLinear | DL_MathData | FC_DL_ | 对数-线性插值（跨数量级工艺曲线） | lgf-math | C2 | B3 | 简单 |
| 28 | FC_DL_InterpTwoPointSlope | DL_MathData | FC_DL_ | 两点定斜率外推，带外推距离上限保护 | lgf-math | C2 | B3 | 简单 |
| 29 | FC_DL_TableIndexBinarySearch | DL_MathData | FC_DL_ | 二分查找定位表区间（大表 O(log n)） | lgf-math | C2 | B3 | 简单 |
| 30 | FC_DL_InterpHoldLast | DL_MathData | FC_DL_ | 保持型查表：超出末节点保持末值，不外推 | lgf-math | C2 | B3 | 简单 |
| 31 | FC_DL_TableReverseLookupX | DL_MathData | FC_DL_ | 由 Y 反查 X（单调表反解，非单调置无效） | lgf-math | C2 | B3 | 简单 |
| 32 | FC_DL_InterpSegmentWeight | DL_MathData | FC_DL_ | 段内权重计算（返回相邻两点权重） | lgf-math | C2 | B3 | 简单 |
| 33 | FB_DL_RunningAverageN | DL_Algo | FB_DL_ | N 点滑动均值（环形缓冲，N 可配 1..32） | self-std | C2 | B3 | 简单 |
| 34 | FB_DL_PeakHoldFilter | DL_Algo | FB_DL_ | 峰值保持，带复位与保持时长 | self-std | C2 | B3 | 简单 |
| 35 | FB_DL_RateOfChangeFilter | DL_Algo | FB_DL_ | 变化率限幅（每周期最大增量），抑制阶跃冲击 | self-std | C2 | B3 | 简单 |
| 36 | FB_DL_GatedUpdateFilter | DL_Algo | FB_DL_ | 门控更新滤波：仅在允许窗口内采样，否则保持 | self-std | C2 | B3 | 简单 |
| 37 | FB_DL_HoldLastGoodFilter | DL_Algo | FB_DL_ | 坏值保持：判据失效时输出上一有效值并计时 | self-std | C2 | B3 | 简单 |
| 38 | FB_DL_DeadbandFilter | DL_Algo | FB_DL_ | 双向死区+输出保持（近邻 FC_DL_Deadband 为无状态单值死区） | self-std | C2 | B3 | 简单 |
| 39 | FB_DL_QuantizeFilter | DL_Algo | FB_DL_ | 量化取整+回差防抖（近邻 FC_DL_QuantizeStep 为无状态取整） | self-std | C2 | B3 | 简单 |
| 40 | FC_DL_StatsMeanStdDev | DL_MathData | FC_DL_ | 均值与标准差（Welford 单遍，防溢出） | self-std | C2 | B3 | 简单 |
| 41 | FC_DL_StatsMinMaxWindow | DL_MathData | FC_DL_ | 窗口极值与发生时刻 | self-std | C2 | B3 | 简单 |
| 42 | FC_DL_StatsPercentile | DL_MathData | FC_DL_ | 分位数（P50/P90/P95，排序法，N 不大于 64） | self-std | C2 | B3 | 简单 |
| 43 | FC_DL_StatsRmsCalc | DL_MathData | FC_DL_ | 有效值 RMS（交流量监测） | self-std | C2 | B3 | 简单 |
| 44 | FC_DL_StatsZeroCrossRate | DL_MathData | FC_DL_ | 过零率统计（振动/流量脉动特征） | self-std | C2 | B3 | 简单 |
| 45 | FC_DL_StatsOutlierCount | DL_MathData | FC_DL_ | 离群点计数（3 sigma 判据，带样本不足保护） | self-std | C2 | B3 | 简单 |

## 批次编排
- B1（复杂 4）：一次派发，编码席单次调用顺序写盘 4 件。
- B2（简单 20）：族A 字符串 10 + 族B 单位换算 10，编码席单次调用写盘 20 件。
- B3（简单 21）：族C 插值 8 + 族D 滤波 7 + 族E 统计 6，编码席单次调用写盘 21 件。

## 撞名与语义三查（规划阶段已执行）
- 驳回/改名留痕 6 条：`FC_DL_Crc16ModbusTable`（撞在库 Crc16Modbus/Crc16Generic）、`FC_DL_PolynomialEvalHorner`（在库 PolyEvalHorner 已占）、`FB_DL_TankLevelVote2oo3`（Vote2oo3/VoteKooN 已占，语义重）、`FB_DL_SlewRateLimiter`（撞 FC_DL_SlewRateCalc）、`FB_DL_TrimmedMeanFilter`（撞 FC_DL_TrimmedMeanCalc）、`FB_DL_DebounceFilter`（撞 FB_DL_SignalDebounce）。
- 保留但附邻件声明 2 条：`FB_DL_DeadbandFilter`、`FB_DL_QuantizeFilter`，均为状态型变体（在库为无状态 FC），属有效差异。

## 里程碑检查点
- T+15 规划表落盘 ｜ T+40 编码交付 41 件 ｜ T+50 闸裁决 41 件 ｜ T+60 入库与战报收口