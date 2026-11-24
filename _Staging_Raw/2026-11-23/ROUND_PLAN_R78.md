# ROUND_PLAN_R78（2026-11-23 23:13，主控直跑）

- 目标 45 = 复杂 4 + 简单 41（族模板派生）。修复件 0（非当日首轮，铁律 1 分轨归零；`FB_DL_RunningAverageN` 修复顺延 R79 首轮）。
- 今日 166/300，4×38=152 < 166，非冲刺模式（按上轮口径）。
- 撞名三查：族内候选名已对 INDEX_REGISTRY.json 全量精确匹配（无同名）；语义邻件避让已核（StringPad/StringTrim/BitCount/Crc8-32/LrcChecksum/RateLimiter FB/SaturateAdd~Sub 等属主在册，本 plan 选名避开）。

## 简单件 41（C1~C2，20~50 行，7 族连号批量派生）

| 批 | 族 | 序号 | 组件名 | 前缀 | 功能 | 来源标签 | 档 |
|---|---|---|---|---|---|---|---|
| B1 | 字符分类族 | 1 | FC_DL_CharIsDigit | MathData | 单字符判十进制数字 | t1-TcDynStringKit(绿MIT) | 简单 |
| B1 | 字符分类族 | 2 | FC_DL_CharIsAlpha | MathData | 单字符判英文字母 | 同上 | 简单 |
| B1 | 字符分类族 | 3 | FC_DL_CharIsAlnum | MathData | 单字符判字母或数字 | 同上 | 简单 |
| B1 | 字符分类族 | 4 | FC_DL_CharIsUpper | MathData | 单字符判大写 | 同上 | 简单 |
| B1 | 字符分类族 | 5 | FC_DL_CharIsLower | MathData | 单字符判小写 | 同上 | 简单 |
| B1 | 字符分类族 | 6 | FC_DL_CharIsSpace | MathData | 单字符判空白（空格/Tab） | 同上 | 简单 |
| B1 | 字符分类族 | 7 | FC_DL_CharIsHexDigit | MathData | 单字符判十六进制位 | 同上 | 简单 |
| B1 | 字符分类族 | 8 | FC_DL_CharToUpper | MathData | 小写转大写（其余原样） | 同上 | 简单 |
| B1 | 奇偶校验族 | 9 | FC_DL_ParityEvenByte | Base | 字节偶校验位 | self-std | 简单 |
| B1 | 奇偶校验族 | 10 | FC_DL_ParityOddByte | Base | 字节奇校验位 | self-std | 简单 |
| B1 | 奇偶校验族 | 11 | FC_DL_ParityEvenWord | Base | 字偶校验位 | self-std | 简单 |
| B1 | 奇偶校验族 | 12 | FC_DL_ParityOddWord | Base | 字奇校验位 | self-std | 简单 |
| B1 | 奇偶校验族 | 13 | FC_DL_ParityEvenLword | Base | 双字偶校验位 | self-std | 简单 |
| B1 | 奇偶校验族 | 14 | FC_DL_ParityOddLword | Base | 双字奇校验位 | self-std | 简单 |
| B1 | 对齐取整族 | 15 | FC_DL_RoundToMultipleInt | MathData | 整数四舍五入到 N 的倍数（N<=0 返 0） | self-std | 简单 |
| B1 | 对齐取整族 | 16 | FC_DL_RoundToMultipleReal | MathData | 实数四舍五入到 N 的倍数（N<=0 返 0） | self-std | 简单 |
| B1 | 对齐取整族 | 17 | FC_DL_CeilToMultipleInt | MathData | 整数向上对齐 N 倍数 | self-std | 简单 |
| B1 | 对齐取整族 | 18 | FC_DL_FloorToMultipleInt | MathData | 整数向下对齐 N 倍数 | self-std | 简单 |
| B1 | 对齐取整族 | 19 | FC_DL_TruncToMultipleInt | MathData | 整数截断到 N 倍数 | self-std | 简单 |
| B1 | 对齐取整族 | 20 | FC_DL_QuantizeStepReal | MathData | 实数量化到步距网格 | self-std | 简单 |
| B1 | 对齐取整族 | 21 | FC_DL_SnapToStepLreal | MathData | LREAL 吸附到步距网格 | self-std | 简单 |
| B1 | 工程单位换算族 | 22 | FC_DL_PressureUnitConvert | MathData | kPa/Bar/Psi/MPa 互转（枚举源/目标） | self-std | 简单 |
| B1 | 工程单位换算族 | 23 | FC_DL_VolumeUnitConvert | MathData | L/m³/gal 互转 | self-std | 简单 |
| B1 | 工程单位换算族 | 24 | FC_DL_MassUnitConvert | MathData | kg/t/lb 互转 | self-std | 简单 |
| B1 | 工程单位换算族 | 25 | FC_DL_SpeedUnitConvert | MathData | m/s/kmh/rpm 线速互转 | self-std | 简单 |
| B1 | 工程单位换算族 | 26 | FC_DL_TorqueUnitConvert | MathData | Nm/lb·ft 互转 | self-std | 简单 |
| B1 | 工程单位换算族 | 27 | FC_DL_EnergyUnitConvert | MathData | kWh/MJ 互转 | self-std | 简单 |
| B1 | 工程单位换算族 | 28 | FC_DL_ForceUnitConvert | MathData | N/kN/lbf 互转 | self-std | 简单 |
| B1 | 工程单位换算族 | 29 | FC_DL_TimeUnitConvert | MathData | s/min/h 互转 | self-std | 简单 |
| B1 | BCD 校验与算术族 | 30 | FC_DL_BcdIsValidByte | MathData | 判字节是否合法 BCD | self-std | 简单 |
| B1 | BCD 校验与算术族 | 31 | FC_DL_BcdIsValidWord | MathData | 判字是否合法 BCD | self-std | 简单 |
| B1 | BCD 校验与算术族 | 32 | FC_DL_BcdAddByte | MathData | 两位 BCD 加法（溢出置错） | self-std | 简单 |
| B1 | BCD 校验与算术族 | 33 | FC_DL_BcdSubByte | MathData | 两位 BCD 减法（借位下溢置错） | self-std | 简单 |
| B1 | BCD 校验与算术族 | 34 | FC_DL_BcdIncrementByte | MathData | BCD 字节加 1（99 进位回 0） | self-std | 简单 |
| B1 | BCD 校验与算术族 | 35 | FC_DL_BcdDecrementByte | MathData | BCD 字节减 1（0 借位回 99） | self-std | 简单 |
| B2 | 渐变限幅族 | 36 | FC_DL_RateLimitReal | MathData | FC 形态斜率限幅（FB_DL_RateLimiter 为 FB 形态，形状不同） | self-std | 简单 |
| B2 | 渐变限幅族 | 37 | FC_DL_RampStepReal | MathData | 单步逼近目标的固定步长爬坡 | self-std | 简单 |
| B2 | 渐变限幅族 | 38 | FC_DL_SlewLimitLreal | MathData | LREAL 斜率限幅 | self-std | 简单 |
| B2 | 渐变限幅族 | 39 | FC_DL_DeltaClampReal | MathData | 相邻两拍增量钳位 | self-std | 简单 |
| B2 | 饱和算术扩展族 | 40 | FC_DL_SaturateIncr | MathData | 带上下限的原地递增饱和 | self-std | 简单 |
| B2 | 饱和算术扩展族 | 41 | FC_DL_SaturateDecr | MathData | 带上下限的原地递减饱和 | self-std | 简单 |

## 复杂件 4（C3~C4）

| 序号 | 组件名 | 分类 | 功能 | 档 |
|---|---|---|---|---|
| 42 | FB_DL_MultiZoneSetpointScheduler | Process | 多区温度/工艺设定值按日时段表自动切换，ENUM 状态机 + 时间窗比较 + 生效沿输出 | 复杂 |
| 43 | FB_DL_WinderTensionTaperCalc | Motion | 收卷锥度张力设定计算，卷径分段锥度曲线 + 上下限钳位 + 参数有效性闸 | 复杂 |
| 44 | FB_DL_AnalogSensorHealthClassify | Device | 模拟量通道健康分级（卡滞/超量程/噪声/正常），滑动统计 + ENUM 分类输出 | 复杂 |
| 45 | FB_DL_PalletizerLayerBuildSeq | Process | 码垛层构建状态机（取放计数/满层/换层/故障复位，ENUM+CASE+ELSE 兜底） | 复杂 |

## 批次派发口径
- B1 = 序号 1~35（简单族 35 件，编码席**一次调用**按序写盘）
- B2 = 序号 36~41（简单族 6 件，一次调用写盘）
- B3 = 序号 42~45（复杂 4 件，一次调用写盘，R451 口径先写状态迁移表）
- 修复件 0。来源标签自上轮队列 TcDynStringKit 4 条语义溯源 + self-std。
