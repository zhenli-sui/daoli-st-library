# ROUND_PLAN_R86 —— 道莅万级工业代码库 & AI 训练集工厂 第 86 轮规划表

- 生成时间：2026-11-24T21:17:31+08:00
- 当日序号：第 8 轮（2026-11-24）
- 目标数：**40**（复杂 4 / 简单 36，简单件占 **90%** ≥ 七成要求）
- 模式：**冲刺模式**（当日累计 278 < 轮次序号 8×38=304 → 复杂件上限降为 4，其余全简单）
- 名称撞名三查：registry 1,686 / 磁盘 1,686 / 磁盘差集前置驳回 **2** 件（`FC_DL_AccelUnitConvert`、`FC_DL_TimeUnitConvert` 已存在，换为 `FC_DL_EnthalpyUnitConvert`、`FC_DL_SpecificHeatUnitConvert`），终版零撞名

## 一、产能账（本轮前）

| 指标 | 数值 |
|---|---|
| 总库 Y | 1,686 / 10,000（16.86%） |
| 今日 X | 278 / 300（92.7%） |
| 距 300 差额 | 22 件 |
| 今日剩余轮次 | 1（本轮 R86 为当日末轮） |
| 上轮 L2 通过率 | 100%（40/40，零 FAIL 零 EXEMPT） |
| 存量缺陷挂账 | 4 件 `FOR..DOWNTO` + 3 件 MAJOR + 3 件 quarantine(R84) |
| 本轮修复配额 | **0**（非当日首轮，铁律①） |

## 二、目标全表（40 件）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | FB_DL_TrapezoidProfilePlanner | DL_Motion | FB_DL | 梯形/三角速度规划：起止速度不等，距离不足自动降级为三角曲线，逐周期输出设定值与完成/超差标志 | motion,planning,profile | C4 | C1 | 复杂 |
| 2 | FB_DL_AxisProbeTouchOffSeq | DL_Motion | FB_DL | 探针触测状态机：快进-慢进-触发记录-回退，超程与未触发超时双兜底 | motion,probing,sequence | C3 | C1 | 复杂 |
| 3 | FB_DL_SensorConsensusSelector | DL_Algo | FB_DL | 多通道传感器共识选择：中位基准+偏差带剔除+通道不足降级到单通道，ENUM 状态机 | algo,consensus,redundancy | C3 | C1 | 复杂 |
| 4 | FB_DL_Q15BiquadFilter | DL_Algo | FB_DL | Q15 定点二阶 IIR 滤波：系数定点化、中间累加防溢出、移位饱和输出 | algo,dsp,q15 | C3 | C1 | 复杂 |
| 5 | FC_DL_Q15AddSat | DL_Base | FC_DL | Q15 定点加法饱和，越界钳到 Q15_MAX/Q15_MIN | base,fixedpoint,q15 | C2 | C2-1 | 简单 |
| 6 | FC_DL_Q15SubSat | DL_Base | FC_DL | Q15 定点减法饱和 | base,fixedpoint,q15 | C2 | C2-2 | 简单 |
| 7 | FC_DL_Q15MulSat | DL_Base | FC_DL | Q15 乘 Q15 得 Q15，中间 DINT 防溢出，含右移舍入 | base,fixedpoint,q15 | C2 | C2-3 | 简单 |
| 8 | FC_DL_Q15DivSafe | DL_Base | FC_DL | Q15 安全除法，除零与商越界双保护 | base,fixedpoint,q15 | C2 | C2-4 | 简单 |
| 9 | FC_DL_Q15AbsSat | DL_Base | FC_DL | Q15 取绝对值饱和，正确处理 -32768 边界 | base,fixedpoint,q15 | C1 | C2-5 | 简单 |
| 10 | FC_DL_Q15NegSat | DL_Base | FC_DL | Q15 取负饱和，-32768 不回绕 | base,fixedpoint,q15 | C1 | C2-6 | 简单 |
| 11 | FC_DL_Q15Lerp | DL_Base | FC_DL | Q15 线性插值，alpha 定点，端点饱和 | base,fixedpoint,q15 | C2 | C2-7 | 简单 |
| 12 | FC_DL_Q15SqrtFloor | DL_Base | FC_DL | Q15 定点整数平方根（逐位法），结果 Q15 | base,fixedpoint,q15 | C2 | C2-8 | 简单 |
| 13 | FC_DL_RealToQ15Sat | DL_Base | FC_DL | REAL 转 Q15 定点，四舍五入加饱和，非有限值归零 | base,fixedpoint,q15 | C1 | C2-9 | 简单 |
| 14 | FC_DL_EnthalpyUnitConvert | DL_Base | FC_DL | 比焓换算 kJ/kg 与 kcal/kg 与 BTU/lb | base,unit,conversion | C1 | C3-1 | 简单 |
| 15 | FC_DL_SpecificHeatUnitConvert | DL_Base | FC_DL | 比热容换算 kJ/(kg*K) 与 BTU/(lb*F) | base,unit,conversion | C1 | C3-2 | 简单 |
| 16 | FC_DL_ConcUnitConvert | DL_Base | FC_DL | 浓度换算 ppm 与 % 与 mg/L | base,unit,conversion | C1 | C3-3 | 简单 |
| 17 | FC_DL_LevelUnitConvert | DL_Base | FC_DL | 液位换算 m/mm/%，按罐高换算 | base,unit,conversion | C1 | C3-4 | 简单 |
| 18 | FC_DL_CurrentUnitConvert | DL_Base | FC_DL | 电流换算 A/mA/kA | base,unit,conversion | C1 | C3-5 | 简单 |
| 19 | FC_DL_TempDiffUnitConvert | DL_Base | FC_DL | 温差换算 K 与摄氏差值与华氏差值，无偏移项 | base,unit,conversion | C1 | C3-6 | 简单 |
| 20 | FC_DL_HeatFluxUnitConvert | DL_Base | FC_DL | 热流密度换算 W/m2 与 kcal/(h*m2) | base,unit,conversion | C2 | C3-7 | 简单 |
| 21 | FC_DL_HtcUnitConvert | DL_Base | FC_DL | 传热系数换算 W/(m2*K) 与 kcal/(h*m2*C) 与 BTU/(h*ft2*F) | base,unit,conversion | C2 | C3-8 | 简单 |
| 22 | FC_DL_VoltageUnitConvert | DL_Base | FC_DL | 电压换算 V/mV/kV | base,unit,conversion | C1 | C3-9 | 简单 |
| 23 | FC_DL_MapRangeClamped | DL_Base | FC_DL | 双端量程映射并对输入钳位 | base,mapping,range | C2 | C4-1 | 简单 |
| 24 | FC_DL_MapRangeBipolar | DL_Base | FC_DL | 双极性对称映射，中点偏置 | base,mapping,range | C2 | C4-2 | 简单 |
| 25 | FC_DL_MapRangePercent | DL_Base | FC_DL | 百分比与工程值互映，枚举方向 | base,mapping,range | C1 | C4-3 | 简单 |
| 26 | FC_DL_MapRangeInverseSolve | DL_Base | FC_DL | 由工程值反解原始量程值，含钳位 | base,mapping,range | C2 | C4-4 | 简单 |
| 27 | FC_DL_MapRangePiecewise3 | DL_Base | FC_DL | 三段折线映射，分段斜率加断点连续校验 | base,mapping,range | C2 | C4-5 | 简单 |
| 28 | FC_DL_MapRangeDeadband | DL_Base | FC_DL | 带中心死区的量程映射，死区内输出中点 | base,mapping,range | C2 | C4-6 | 简单 |
| 29 | FC_DL_MapRangeSatOut | DL_Base | FC_DL | 输入量程映射后对输出独立饱和限幅 | base,mapping,range | C2 | C4-7 | 简单 |
| 30 | FC_DL_MapRangeIntQuant | DL_Base | FC_DL | 量程映射加整数量化，步长加四舍五入 | base,mapping,range | C2 | C4-8 | 简单 |
| 31 | FC_DL_MapRangeHystSwitch | DL_Base | FC_DL | 带滞环的二态阈值映射 | base,mapping,range | C2 | C4-9 | 简单 |
| 32 | FC_DL_SatAddDint | DL_MathData | FC_DL | DINT 加法饱和，上下界检测 | mathdata,saturation,arithmetic | C2 | C5-1 | 简单 |
| 33 | FC_DL_SatSubDint | DL_MathData | FC_DL | DINT 减法饱和 | mathdata,saturation,arithmetic | C2 | C5-2 | 简单 |
| 34 | FC_DL_SatMulDint | DL_MathData | FC_DL | DINT 乘法饱和，先判溢出条件再乘 | mathdata,saturation,arithmetic | C2 | C5-3 | 简单 |
| 35 | FC_DL_SatAddLreal | DL_MathData | FC_DL | LREAL 加法饱和加非有限值闸 | mathdata,saturation,arithmetic | C2 | C5-4 | 简单 |
| 36 | FC_DL_SatMulLreal | DL_MathData | FC_DL | LREAL 乘法饱和加非有限值闸 | mathdata,saturation,arithmetic | C2 | C5-5 | 简单 |
| 37 | FC_DL_SatNegDint | DL_MathData | FC_DL | DINT 取负饱和，DINT_MIN 不回绕 | mathdata,saturation,arithmetic | C1 | C5-6 | 简单 |
| 38 | FC_DL_SatScaleLreal | DL_MathData | FC_DL | LREAL 增益缩放饱和 | mathdata,saturation,arithmetic | C2 | C5-7 | 简单 |
| 39 | FC_DL_SatSumArrayDint | DL_MathData | FC_DL | DINT 定长数组累加饱和，逐项防溢出 | mathdata,saturation,arithmetic | C2 | C5-8 | 简单 |
| 40 | FC_DL_SatClampLrealBand | DL_MathData | FC_DL | LREAL 区间钳位，带上下限合法性自检 | mathdata,saturation,arithmetic | C1 | C5-9 | 简单 |

## 三、族模板规划（简单件 4 族 × 9 件，供编码席一次调用批量派生）

| 族 | 名称 | 件数 | 分类 | 批次 | 语义边界（防重复声明） |
|---|---|---|---|---|---|
| A | Q15 定点算术 | 9 | DL_Base | C2 | 全库 `q15` 命中 **0**，与 `FC_DL_FixedField*`（字段打包）语义无关 |
| B | 工程单位换算补族 | 9 | DL_Base | C3 | 在册 16 个 `*UnitConvert` 均无「比焓/比热/浓度/液位/电流/温差/热流/传热系数/电压」，本轮补空白量纲 |
| D | 量程映射 | 9 | DL_Base | C4 | 全库 `maprange` 命中 **0**；与 `FC_DL_LinearScale` 差异：本族为双端量程对 + 独立饱和 + 反解 + 折线 + 滞环，非单斜率 |
| C | 饱和算术 | 9 | DL_MathData | C5 | 全库 `satadd` 命中 **0**；与 `FC_DL_SlewLimitLreal`（速率限）语义不同，本族为算术溢出饱和 |

**复杂件 4 件（批次 C1）**：

- `FB_DL_TrapezoidProfilePlanner`（C4）— 梯形/三角速度规划，`strapez` 命中 0，与 `FB_DL_SCurveGenerator`（S 曲线）不同族
- `FB_DL_AxisProbeTouchOffSeq`（C3）— 探针触测状态机，`probing` 命中 0
- `FB_DL_SensorConsensusSelector`（C3）— 多通道共识选择，`consensus`/`voting` 命中 0，与 `FB_DL_VoteKooN`（布尔表决）互补：本件为模拟量中位+偏差剔除
- `FB_DL_Q15BiquadFilter`（C3）— Q15 定点二阶 IIR，与 `FB_DL_SecondOrderFilter`（REAL 浮点）构成精度变体，属有效变体不属重复

## 四、分类配额与平衡策略

| 分类 | 现有 | 本轮 + | 轮后 |
|---|---|---|---|
| DL_Base | 196 | +27 | 223 |
| DL_MathData | 425 | +9 | 434 |
| DL_Algo | 168 | +2 | 170 |
| DL_Device | 302 | +0 | 302 |
| DL_Motion | 144 | +2 | 146 |
| DL_Process | 451 | +0 | 451 |

平衡逻辑：DL_Base(196) 与 DL_Motion(144) 为最薄弱两库，本轮 27 件投向 DL_Base；DL_Process(451) 已过载，本轮 **0 件**。

## 五、里程碑检查点（T = 21:16）

| 检查点 | 计划 | 判定 |
|---|---|---|
| T+15′（21:31） | 规划表落盘 | 实际 21:19 ✔ 提前 12′ |
| T+40′（21:56） | 编码交付 ≥36 件 | 待测 |
| T+50′（22:06） | 编译闸裁决 ≥36 件 | 待测 |
| T+60′（22:16） | 入库与战报完成 | 待测 |

## 六、串并行边界

- **并行**：猎人采集（网络 IO）与编码席（生成密集）同轮同时开跑；文档与飞书播报并行。
- **串行**：编译闸 `jobs=1`（RuSTy 并发会产生 E004 假阳性）；registry / JSONL 单点写入。
- 子代理预算：四席各 1 + 1 返修位 = 5，本轮计划用 4（返修位待命）。

## 七、逐席召唤计划

| 席位 | 召唤名 | 模式 |
|---|---|---|
| 主控 dlf-lead | 主循环直跑 | 原生 |
| 开源供料 | `dlf-oss-hunter` | 原生（回退名 `daoli-oss-hunter`） |
| 编码 | `dlf-plc-coder` | 原生（回退名 `plc-programming-expert`） |
| 编译闸 | `dlf-compile-verifier` | 原生（回退名 `daoli-compile-verifier`） |
| 审校去重 | `dlf-qa-dedup` | 原生（回退名 `daoli-qa-dedup`） |
