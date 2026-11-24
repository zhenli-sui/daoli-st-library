# R79 轮次规划表（2026-11-24 首轮｜冲刺模式｜TARGET=45）

- 轮次开始 T = 2026-11-24T02:55:20+08:00（锁已写）
- 当日目标 300，本轮开始前当日累计 **0/300**（新一日首轮）
- 冲刺模式判定：当日累计 0 < 轮次进度 → **复杂件上限降为 4**，其余全部简单件
- 修复名额：**当日首轮，允许 ≤4 件**（不计产出）
- 分档：复杂 4 + 简单 41 = **45 件**

## 一、盘点基线

| 指标 | 数值 |
|---|---|
| 总库 registry | 1,408 / 10,000（14.08%） |
| .st 实体文件（6 子库） | 1,408（与 registry **完全一致**，磁盘差集 0） |
| SFT JSONL 行数 | 1,447（较 registry 高 39 条，R70 前历史遗留待校准，已持续披露） |
| 开源候选队列 | 64 条（绿 60 / 黄 4 / 红 0） |
| 上轮（R78）L2 通过率 | 首裁 97.7%（42/43）→ 返修后终裁 100%，零豁免 |
| L2 存量缺陷 | 1 件隔离待修（`FC_DL_RoundToMultipleInt` DINT 回绕）+ 4 件 bReset 电平判据 MAJOR |
| 距 300 差额 | 300（本轮需至少 45） |

## 二、40+5 目标全表（序号｜组件名｜分类｜前缀｜功能｜来源标签｜复杂度｜批次｜档）

### 家族 1：日历算术族（DL_MathData，FC，9 件）
| 1 | FC_DL_CalIsLeapYear | DL_MathData | FC | 公历闰年判定（1583 起点闸） | internal | C1 | A1 | 简单 |
| 2 | FC_DL_CalMonthDays | DL_MathData | FC | 月天数（闰年 2 月） | internal | C1 | A1 | 简单 |
| 3 | FC_DL_CalDayOfYear | DL_MathData | FC | 年月日→年内序号 1..366 | internal | C2 | A1 | 简单 |
| 4 | FC_DL_CalDateFromDayOfYear | DL_MathData | FC | 年内序号→月日（越界闸） | internal | C2 | A1 | 简单 |
| 5 | FC_DL_CalWeekdayIndex | DL_MathData | FC | 星期索引 0=周一（整数算法） | internal | C2 | A2 | 简单 |
| 6 | FC_DL_CalIsoWeekNo | DL_MathData | FC | ISO 8601 周号 + 归属年 | internal | C2 | A2 | 简单 |
| 7 | FC_DL_CalQuarterIndex | DL_MathData | FC | 月份→季度 | internal | C1 | A2 | 简单 |
| 8 | FC_DL_CalIsWeekend | DL_MathData | FC | 周末判定 | internal | C1 | A2 | 简单 |
| 9 | FC_DL_CalMonthEndDate | DL_MathData | FC | 月末日期 | internal | C1 | A2 | 简单 |

### 家族 2：整数数论族（DL_MathData，FC，8 件，纯整数）
| 10 | FC_DL_IntSqrtFloorUdint | DL_MathData | FC | 整数平方根（牛顿迭代 + 上限闸） | internal | C2 | A1 | 简单 |
| 11 | FC_DL_IntIsPerfectSquareUdint | DL_MathData | FC | 完全平方判定（溢出闸） | internal | C2 | A1 | 简单 |
| 12 | FC_DL_IntDigitSumUdint | DL_MathData | FC | 十进制位和 | internal | C1 | A2 | 简单 |
| 13 | FC_DL_IntDigitCountUdint | DL_MathData | FC | 十进制位数 | internal | C1 | A2 | 简单 |
| 14 | FC_DL_IntPowSatUdint | DL_MathData | FC | 整数幂饱和（快速幂） | internal | C2 | A2 | 简单 |
| 15 | FC_DL_IntDivModSafe | DL_MathData | FC | 商余双出口 + DINT_MIN/-1 特判 | internal | C2 | A3 | 简单 |
| 16 | FC_DL_IntSignExtractLreal | DL_MathData | FC | 符号提取（NaN/Inf 判据，禁 ABS(x-x)） | internal | C2 | A3 | 简单 |
| 17 | FC_DL_IntReverseDigitsUdint | DL_MathData | FC | 数字反转（溢出饱和） | internal | C2 | A3 | 简单 |

### 家族 3：平面几何族（DL_MathData，FC，8 件，LREAL）
| 18 | FC_DL_GeoPointLineDist | DL_MathData | FC | 点到无限长直线距离 | internal | C2 | A3 | 简单 |
| 19 | FC_DL_GeoLineIntersectXY | DL_MathData | FC | 线段求交（参数域闸） | internal | C3 | A3 | 简单 |
| 20 | FC_DL_GeoPointInRectXY | DL_MathData | FC | 轴对齐矩形内含（边界容差） | internal | C1 | A4 | 简单 |
| 21 | FC_DL_GeoPointInConvexQuadXY | DL_MathData | FC | 凸四边形内含（叉积同号） | internal | C2 | A4 | 简单 |
| 22 | FC_DL_GeoCentroid3Pt | DL_MathData | FC | 三顶点质心（共线闸） | internal | C1 | A4 | 简单 |
| 23 | FC_DL_GeoPolylineLenFixed | DL_MathData | FC | 定长折线长度（禁 VLA） | internal | C2 | A4 | 简单 |
| 24 | FC_DL_GeoBBoxFromPtsFixed | DL_MathData | FC | 定长点集包围盒 | internal | C2 | A4 | 简单 |
| 25 | FC_DL_GeoLineAngleXY | DL_MathData | FC | 两点有向角（ATAN2 兜底） | internal | C2 | A5 | 简单 |

### 家族 4：统计扩展族（DL_MathData，FB 2 + FC 6，8 件）
| 26 | FB_DL_StatsWelfordVar | DL_MathData | FB | Welford 在线均值/方差（bReset R_TRIG） | internal | C2 | A5 | 简单 |
| 27 | FB_DL_StatsSkewKurtStream | DL_MathData | FB | 流式偏度/超额峰度 | internal | C3 | A5 | 简单 |
| 28 | FC_DL_StatsMadFixed | DL_MathData | FC | 中位绝对偏差（插入排序自足） | internal | C2 | A5 | 简单 |
| 29 | FC_DL_StatsTrimmedMeanFixed | DL_MathData | FC | 修削均值（钳位保 1 样本） | internal | C2 | A6 | 简单 |
| 30 | FC_DL_StatsPercentileRankFixed | DL_MathData | FC | 最近秩分位 | internal | C2 | A6 | 简单 |
| 31 | FC_DL_StatsZScoreClamp | DL_MathData | FC | 标准化 + 限幅（零方差闸） | internal | C1 | A6 | 简单 |
| 32 | FC_DL_StatsHistogramBin | DL_MathData | FC | 直方图落桶（首末桶钳位） | internal | C1 | A6 | 简单 |
| 33 | FC_DL_StatsRunLengthMax | DL_MathData | FC | 最长同值游程 | internal | C2 | A6 | 简单 |

### 家族 5：校验和族（DL_Algo，FC，8 件）
| 34 | FC_DL_ChkFletcher16 | DL_Algo | FC | Fletcher-16（mod 255） | internal | C2 | A7 | 简单 |
| 35 | FC_DL_ChkFletcher32 | DL_Algo | FC | Fletcher-32（16 位字，奇长补零） | internal | C2 | A7 | 简单 |
| 36 | FC_DL_ChkXor8 | DL_Algo | FC | 逐字节异或 | internal | C1 | A7 | 简单 |
| 37 | FC_DL_ChkSum8 | DL_Algo | FC | 字节和 mod 256 | internal | C1 | A7 | 简单 |
| 38 | FC_DL_ChkTwosCompSum16 | DL_Algo | FC | 16 位二补数和（零值口径） | internal | C2 | A7 | 简单 |
| 39 | FC_DL_ChkSum32Mod | DL_Algo | FC | 32 位字累加 mod 2^32-1 | internal | C2 | A8 | 简单 |
| 40 | FC_DL_ChkParityBlock | DL_Algo | FC | 整块偶校验 | internal | C1 | A8 | 简单 |
| 41 | FC_DL_ChkAdler32 | DL_Algo | FC | Adler-32（mod 65521） | internal | C2 | A8 | 简单 |

### 复杂件（4 件，DL_Process，批 B）
| 42 | FB_DL_CoolingTowerFanStageSeq | DL_Process | FB | 冷却塔风机分级投切 + 主备轮换 + 启动确认超时 | internal | C4 | B | 复杂 |
| 43 | FB_DL_ScrewConveyorDoseSeq | DL_Process | FB | 螺旋给料计量批次（积算 + 稳定延时 + 超时） | internal | C4 | B | 复杂 |
| 44 | FB_DL_PressForceCurveExec | DL_Process | FB | 压机多段力曲线执行（斜坡/保压/释放） | internal | C4 | B | 复杂 |
| 45 | FB_DL_AerationBlowerCycle | DL_Process | FB | 曝气风机间歇循环 + DO 迟滞带 + 仪表失效闸 | internal | C3 | B | 复杂 |

## 三、修复件（≤4 件，当日首轮配额，不计产出）

| # | 件 | 缺陷 | 修法 | 来源 |
|---|---|---|---|---|
| F1 | FC_DL_RoundToMultipleInt | DINT 回绕（`nLo + nMultiple` 溢出；`-nRem` 在 DINT_MIN 域回绕） | 补饱和闸：先判 nValue 距 DINT_MAX/MIN 是否小于 2×nMultiple，超界直接钳位并置 bSat | R78 L1 阻断 |
| F2 | FB_DL_MultiZoneSetpointScheduler | bReset 声明上升沿、实现电平判据 | 加 R_TRIG 实例（CASE 外无条件刷新） | R78 QA J1 |
| F3 | FB_DL_PalletizerLayerBuildSeq | 同上 | 同上 | R78 QA J1 |
| F4 | FB_DL_AnalogSensorHealthClassify | 同上 | 同上 | R78 QA J1 |

> 未纳入本轮：`FB_DL_WinderTensionTaperCalc`（第 5 件，超配额，转 R80 首轮修复）。

## 四、撞名三查（名称/签名/语义邻件）+ 第四查（同义词根召回）

- 关键词实测撞名：Time 34 / Date 10 / Counter 12 / Watch 25 / Signal 18 / Bit 40 / Stats 27 / Crc 5 / Lsum 0
- 已避让：`FC_DL_SqrtEx`（实数平方根）→ 本批改 `IntSqrtFloorUdint`（整数域、Floor 语义，不同阶）；`FC_DL_GcdUdintCalc` 已存在 → **本批不写 GCD/LCM**；`FC_DL_Crc8` 已存在 → 本批**不写 CRC-8 变体**（避免多项式变体被判同构）；`FC_DL_LrcChecksum` 已存在 → 不写 LRC
- 族级避让：位运算/角度归一化/单位换算/滤波/迟滞/字节序/字符串/三角函数/限幅/插值/统计基础/**奇偶校验/BCD/对齐取整/渐变限幅/饱和扩展/字符分类** 均为 R72~R78 已用族 → 本批**全部换族**（日历/数论/几何/统计扩展/校验和）
- 驳回候选（留痕）：`FC_DL_Crc8Maxim`（与 FC_DL_Crc8 多项式变体，去重风险高）、`FC_DL_IntGcdSafe`（撞 GcdUdintCalc）、`FC_DL_GeoDistance2D`（撞 CalcDistance2D）

## 五、里程碑检查点

| 检查点 | 截止 | 要求 |
|---|---|---|
| T+15′ | 03:10 | 本规划表落盘（45 条全表，标档） |
| T+40′ | 03:35 | 编码席交付 ≥28 件（本批要求 45） |
| T+50′ | 03:45 | 编译闸裁决 ≥28 件 |
| T+60′ | 03:55 | 入库 + 战报完成 |

## 六、并行与串行边界

- **并行**：猎人采集（网络 IO）∥ 编码 A 批（生成密集）；A 批过闸时编码 B 批（复杂 4）开跑；文档与飞书播报最后并行。
- **串行**：规划 → 编码 → L2 闸（jobs=1）→ 审校去重 → 入库；registry / JSONL 单点写入。
- 子代理预算：5 个（猎人 1 + 编码 2 + 闸 1 + 审校 1），修复由主控直做不占席位。
