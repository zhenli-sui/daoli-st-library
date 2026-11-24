# QA_REVIEW_R81_A — R81 批 A（36 件简单 FC）独立审校与去重

审校席：dlf-qa-dedup　日期：2026-11-24　范围：`_files_r81a.txt` 全 36 件（DL_Process 23 / DL_Device 7 / DL_Motion 6）
前提采信：编译闸席批 A 裁决 35 PASS / 1 FAIL(LOGIC)，`FC_DL_BeamToppleRiskChk` 按在盘 v1.0.1 审。
本报告全部结论均带行号，无行号判断不成立即不入表。

## ① 汇总

| 指标 | 值 |
|---|---|
| 抽检覆盖 | 36 / 36（100%，全量非抽样） |
| PASS | 36 |
| 存疑放行 | 3（语义近邻，见 ④-C） |
| 拒收 | 0 |
| BLOCK | 0 |
| MAJOR | 0 |
| MINOR | 8（分布于 8 件） |

分级口径说明：MINOR 未升格。本批无任何编译阻断、无安全侧缺陷、无除零、无量纲错误、无非有限穿透，故 BLOCK/MAJOR 均为 0，此结论经机器全量校验 + 人工逐件复核双重确认。

## ② 拒收清单

**空。** 36 件全部通过三道去重，无一件判重。详见 ④。

## ③ BLOCK / MAJOR 清单

**空。** 以下为 MINOR 明细（8 条，含修法）。

| # | 件名 | 行号 | 问题 | 分级 | 修法 |
|---|---|---|---|---|---|
| M1 | FC_DL_LaneDiverterAngleCalc | L37 / L82 | `DL_RAD_TO_DEG := 0.0174533`，名与声明单位 `[度/rad]` 要求 57.29578，实存值为 `[rad/度]`。L82 `rAngleDeg := rAngleRad / DL_RAD_TO_DEG` 用**除法**，故算术结果正确（rad÷0.0174533=度）。但名称+单位标签与数值反向，若后续"按名字修正"该常量即引入 **3282×** 静默错误；且全库其余件均用 `DL_DEG_TO_RAD := 0.0174533` 正名（SipResidueVolumeEst L41、SheetPeelForceCalc L42），本件命名与全库口径分裂 | MINOR（潜在 3282× 陷阱） | 改名 `DL_RAD_PER_DEG` 并保留除法；或改为 `DL_RAD_TO_DEG := 57.2957795` + L82 改乘法。二者取其一，不得只改数值不改运算符 |
| M2 | FC_DL_SanitizeHoldTimeCalc | L46 | VAR 注释写"温度系数的倒数，**除法前先算后判**"，而实现为 L86 判零 → L89 取倒数（先判后算）；与同件 L85 段注释"先判零再取倒数，顺序不可颠倒"自相矛盾。代码正确，注释错误 | MINOR | 注释改为"先判零后取倒数，顺序不可颠倒" |
| M3 | FC_DL_ForkExtendSafeChk | L36 | `DL_EPS` 声明后全文未引用（本件无变量除法，仅域闸用 `DL_ZERO`） | MINOR | 删除 `DL_EPS` 声明 |
| M4 | FC_DL_FoamSuppressDutyCalc | L33 | `DL_EPS` 声明未引用（L69/L70 仅除以常量 `DL_PCT`） | MINOR | 删除 `DL_EPS` 声明 |
| M5 | FC_DL_BottleNeckLevelMargin | 常量区 | `DL_EPS` 声明未引用（无变量除法） | MINOR | 删除 `DL_EPS` 声明 |
| M6 | FC_DL_AirQualityClassifyCalc | L36 | `DL_EPS` 声明未引用（分级比较用 `DL_DEW_*`/`DL_OIL_*`） | MINOR | 删除 `DL_EPS` 声明 |
| M7 | FC_DL_SheetPeelForceCalc | 常量区 | `DL_EPS` 声明未引用 | MINOR | 删除 `DL_EPS` 声明 |
| M8 | FC_DL_CellOccupyRateCalc | L34 | `DL_R_MAX` 声明未引用（本件输入全为 INT，无非有限闸需求）；同件 `DL_EPS` 在 L80 有正确使用 | MINOR | 删除 `DL_R_MAX` 声明 |

**同族系统性缺陷上报（触发扩面复审）**：M3~M8 共 **6 件**为同一型——模板常量块（`DL_R_MAX`/`DL_EPS`）随骨架无差别复制，未随"本件是否真有除法/REAL 输入"做裁剪。≥3 件同型，按 SOP 报产品总监：建议对在库 1,490 件做一次"声明常量零引用"机检（可交给编译验证工程师落 `dl_gate.py` 锚点），预期可批量清出死常量噪声。

### 12 项定向扫查逐项结论（全 36 件）

| # | 扫查项 | 结论 | 证据 |
|---|---|---|---|
| 1 | 量纲闭合 | **PASS** | 逐值验算 9 个换算常量：`DL_MM_TO_M=2000`（直径 mm→半径 m，100mm→0.05m ✓，RinseWater L74 / SipResidue L82）；`DL_MM_TO_M=1000`（mm→m，VacuumPadForce L78 / SuctionFlow L84 / LaneDiverter L87）；`DL_KPA_TO_PA=1000`（VacuumPadForce L82 / SuctionFlow L86 / SheetPeel L84）；`DL_M3S_TO_LPM=60000`（1m³/s=1000L/s×60 ✓，SuctionFlow L95）；`DL_M3S_TO_NM3H=3600` ✓；`DL_M3_TO_L=1000` ✓；`DL_MM2_TO_M2=1E-6` ✓；`DL_MIN_PER_H=60` ✓；`DL_SEC_H=3600` ✓；`DL_DEG_TO_RAD=0.0174533` ✓。**无一取倒数**。唯一标签反转见 M1（数值仍正确） |
| 2 | 死输入 | **PASS** | 36 件全部 VAR_INPUT 标识符在函数体内被引用 ≥1 次（机器全量扫描，零命中） |
| 3 | 分母防护同句前置 | **PASS** | 40 处变量除法逐行回溯，**0 处**无闸。典型：SanitizeHold L67 闸→L84 除、L86 闸→L89 取倒数；ReceiverPressureDrop L63 `ABS(rDur_s)<=DL_EPS` 闸→L82 除；IdleRun L62 闸→L78 除；VacHoldDecay L63 闸→L80 除；ConductivityDilution L68 `_rDen<=DL_EPS` 闸→L75 除；StocktakeVariance L81 闸→L89 除；LifterCycle L62 闸→L73/L78。无一处把闸与除法放进同一 IF 布尔式 |
| 4 | 限幅上下界反转 | **PASS** | 逐件核对 `DL_*_LO < DL_*_HI` 与分支方向：SkateWheel L38-39 LO=0.1<HI=0.9，L83 `<LO` 走 ELSIF `>HI` 正确；SanitizeHold FACT_LO=0.5<HI=2.0 L78-82 正确；Desiccant/FoamSuppress/DrainInterval 均一致 |
| 5 | 输出预置于首个 RETURN 前 | **PASS** | 36 件段 1 均为出口预置块并位于首个 RETURN 之前（如 TrackingOffset L45-48 先于 L50 RETURN；AirQuality L55-59 先于 L61，且预置为最差 4 级，方向正确） |
| 6 | 未使用常量/变量 | **MINOR** | 仅 6 件死常量（M3~M8）；VAR 段内部变量零死变量 |
| 7 | 除零以外的数值溢出 | **PASS** | 唯一的 REAL→INT 在 SuctionCupCount L108，其前置 L98 `rNeedRaw >= DL_INT_SAFE` 兜底 + L114/L117 双限幅，无回绕；StocktakeVariance L71-76 DINT 承载后双侧饱和回 INT 正确；CellOccupy L64/L73 全程 DINT 防 INT 减法溢出 |
| 8 | 浮点直接 `=` 判等 | **PASS** | 全套仅 `x = x` 自反式判 NaN（如 L57/L60/L67/L68 各件非有限闸），无 `rA = rB` 形式的实数相等比较 |
| 9 | 非有限判据禁用式 | **PASS** | 0 处 `ABS(x-x)`、0 处 `(x-x)<>0`。全部采用 `(x = x) AND (ABS(x) <= DL_R_MAX)` 双条件式 |
| 10 | 双语注释覆盖率 | **PASS** | 声明行 100%「中文 + 英文」双段注释，机器逐行校验零缺口（含 VAR CONSTANT 与 VAR） |
| 11 | 分号在注释前 | **PASS** | 0 处语句分号缺失或错置于注释之后 |
| 12 | 标准函数误用 | **PASS** | SQRT 2 处参数恒非负：ShuttleStroke L71 `SQRT(rDist_m/rAcc)`，L61 已拒 `rDist_m<0`、L58 已拒 `ABS(rAcc)<=DL_EPS`；SuctionFlow L92 `SQRT(_rTerm)` 前置非负构造。ATAN 1 处（LaneDiverter L81）商式两侧均非负且 `rLaneGap_mm>=DL_GAP_MIN=1.0>0`，象限无歧义。SIN/COS 2 处（SipResidue L92、SheetPeel L85）均先乘 `DL_DEG_TO_RAD=0.0174533` 转弧度，**未混用角度制**。MOD 零使用 |

### 逐件结论表

| 件名 | 目录 | 结论 | 备注 |
|---|---|---|---|
| FC_DL_ShuttleStrokeTimeEst | Process | PASS | SQRT 护栏完备 |
| FC_DL_ShuttleAisleLockChk | Process | PASS | 无除法/无 REAL，逻辑清晰 |
| FC_DL_LifterCycleTimeEst | Process | PASS | 双闸（速度闸+周期闸） |
| FC_DL_StocktakeVarianceCalc | Process | PASS | 账面零值分支正确置告警 |
| FC_DL_BeamToppleRiskChk | Process | PASS | **v1.0.1**：L72 新增 `ABS(rCgOffset)>梁深/2` 域闸，L76 改 `ABS()` 使负偏移同样放大风险，原漏报已闭合；两处除数 L65 均已闸 |
| FC_DL_CellOccupyRateCalc | Process | PASS | M8 死常量 |
| FC_DL_ForkExtendSafeChk | Process | PASS | M3 死常量 |
| FC_DL_BinLabelCheckSum | Process | PASS | 双看门狗 `DL_SCAN_MAX` 防死循环 |
| FC_DL_FoamSuppressDutyCalc | Process | PASS | M4 死常量 |
| FC_DL_RinseWaterVolumeCalc | Process | PASS | 换算 2000/1000 均正确 |
| FC_DL_SanitizeHoldTimeCalc | Process | PASS | M2 注释自相矛盾（代码正确） |
| FC_DL_ConductivityDilutionCalc | Process | PASS | 分母+分子双闸，稀释比区间闸 |
| FC_DL_NozzleClogIndexCalc | Process | PASS | 流量偏差率，分母有闸 |
| FC_DL_SipResidueVolumeEst | Process | PASS | 同 RinseWater（见 ④-C 近邻） |
| FC_DL_FillValveSealWearEst | Process | PASS | 温度加速因子限幅 |
| FC_DL_BottleNeckLevelMargin | Process | PASS | M5 死常量 |
| FC_DL_ReceiverPressureDropCalc | Process | PASS | 压降正闸 + 近似式失真闸 |
| FC_DL_AirQualityClassifyCalc | Process | PASS | M6 死常量；预置最差级方向正确 |
| FC_DL_DesiccantLifeEstimate | Process | PASS | 降额容量有闸 |
| FC_DL_MotorLoadFactorCalc | Process | PASS | 功率因数有闸 |
| FC_DL_CompressorDutyCycleCalc | Process | PASS | 加卸载双占比 |
| FC_DL_DrainIntervalCalc | Process | PASS | min/h 双向换算自闭合 |
| FC_DL_IdleRunRatioCalc | Process | PASS | 加载时间越界闸 + 双限幅 |
| FC_DL_VacuumPadForceCalc | Device | PASS | π/4·d²·P 量纲闭合 |
| FC_DL_SuctionFlowEst | Device | PASS | 60000 系数正确，SQRT 护栏完备 |
| FC_DL_SheetPeelForceCalc | Device | PASS | M7 死常量；角度折减限幅 0~1 |
| FC_DL_VacHoldDecayChk | Device | PASS | 负跌落走疑值分支，不误报泄漏 |
| FC_DL_PadWearIndexCalc | Device | PASS | 加权指数限幅 |
| FC_DL_VacuumGenDutyCalc | Device | PASS | 占空比限幅 |
| FC_DL_SuctionCupCountCalc | Device | PASS | REAL_TO_INT 兜底完备 |
| FC_DL_LineSpeedMatchRatio | Motion | PASS | 速比偏差 |
| FC_DL_ChainWearElongation | Motion | PASS | 节距伸长率 |
| FC_DL_RollerSlipRatioCalc | Motion | PASS | 相对打滑 |
| FC_DL_SkateWheelLoadCalc | Motion | PASS | 占比限幅 0.1~0.9 方向正确 |
| FC_DL_LaneDiverterAngleCalc | Motion | PASS | M1 标签反转（算术正确） |
| FC_DL_TrackingOffsetChk | Motion | PASS | 脉冲折算，负脉冲不拦截（有据） |

## ④ 三道去重结论（全量 36 件，未抽样）

### A. 名称去重 — PASS（0 命中）
- 比对基数：`_names_r81.txt` **1,489 条**在库全名（去 `FC_/FB_/DL_/I_/ST_/E_` 前缀并小写归一后建索引）。
- 结果：36 件归一名 **无一命中**在库名；批内 36 件互相比对 **零重复**（归一名唯一）。
- 同义邻件人工复看：`LaneDiverterAngleCalc` vs 在库无 `AngleCalc` 族冲突；`SuctionFlowEst` vs `SuctionCupCountCalc` 名称词根不同（Flow vs CupCnt），非名称重复。

### B. 签名指纹去重 — PASS（0 结构重复），并附一条**方法学纠正**
- 提取 VAR_INPUT + VAR_OUTPUT 类型序列，按任务口径 `≥80% 参数位相同` 判定：命中 **120 对**。
- **全部为假阳性**。原因：本批 36 件同属"REAL 密集数值 FC"，共享 `bEnable/bErr/bValid` 骨架 + 全 REAL 参数，类型序列在数值族内天然饱和（任一数值件与另一数值件相似度即 0.83~1.00）。该口径对数值计算族**无判别力**。
- 改用**归一化公式核心指纹**（赋值右式去常量名、去字面量后取 sha1）复判：**36 件零碰撞**，无结构重复。
- 结论：结构层**无重复**。建议口径修订（交编译验证工程师）：对数值 FC 族，指纹须用「归一化公式核心 + 量纲向量」双键，单纯类型序列降级为辅助提示，否则 1,490 件规模下会产生大量误判重。

### C. 语义同义去重 — PASS（0 拒收），3 组近邻存疑放行
逐件按「一句话功能 + 主标签族 + 输出语义/量纲」判定，36 件终值物理量两两互异（时间 s / 百分比 % / 力 N / 流量 L·min⁻¹·Nm³h⁻¹ / 等级 / 计数 个 / 长度 mm / 电导比 / 压降 bar·h⁻¹ …）。**同族不同阶、不同量纲、不同行业约束者一律判有效变体，不拒收**。

存疑放行（供总监复议，建议保留，理由已给）：
1. `RinseWaterVolumeCalc` ↔ `SipResidueVolumeEst`：共享 `π·r²·L→L` 管容子式。但前者输出**冲洗耗水量**（×冲洗次数×残留系数，输入含 `iRinseCnt`），后者输出**滞留残量**（主管坡度排空 + 盲管，输入含 `rSlopeDeg`/`rBlindLen_m`）。输出语义与输入形态均不同 → 有效变体。
2. `VacuumPadForceCalc` ↔ `SuctionFlowEst`：共享 `π/4·d²·(kPa→Pa)` 面积子式。前者 `F=P·A·S→N`，后者 `Q=Cd·A·v→L/min`。终端物理量与量纲不同 → 有效变体。
3. `TrackingOffsetChk` ↔ `LineSpeedMatchRatio`：同属"实测 vs 基准 + 容差 + 报警"形状。前者比对**位移**（脉冲折算 vs 基准距离），后者比对**速比**（主从线速 vs 设定速比）。被测物理量不同 → 有效变体。

## ⑤ 一句话总结

R81 批 A 36 件数值 FC 质量显著优于 R59~R64 基线：**零 BLOCK、零 MAJOR、零拒收**，除零/非有限/量纲三大历史高发项经全量机器校验 + 逐件人工复核确认全部闭合（40 处除法 100% 有前置闸，9 个换算常量 100% 方向正确）；仅存 8 条 MINOR，其中 6 条是同一型"模板常量无差别复制"造成的死常量（已按 SOP 上报总监触发扩面复审），另 2 条为注释/命名口径瑕疵，其中 `LaneDiverterAngleCalc` 的 `DL_RAD_TO_DEG` 标签反转虽当前算术正确，但是全批唯一的 3282× 潜在陷阱，建议列为下轮首修。
