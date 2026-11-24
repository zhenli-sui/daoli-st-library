# DL_Algo — 版本记录 / Version History

> **子库定位 / Role**：Level 1 工业控制算法层：闭环控制律（PID 家族、串级、分程）、轨迹规划（斜坡、S 曲线）、信号运算（积分、微分、滤波族）与过程补偿（前馈、史密斯、露点、流量温压）。
> **兼容平台 / Platforms**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop ｜ Schneider Machine Expert
> **依赖 / Depends**：Level 0 仅 `Standard.library`（`R_TRIG` / `LIMIT` / `MIN` / `MAX` / `ABS` / `LN` / `EXP` / `TAN` / `SQRT` / `TIME_TO_REAL` 等标准算符与函数）；不引用 `DL_Base` / `DL_MathData` / 更高层任何子库。子库内部依赖仅两条：`FB_DL_CascadePid` 与 `FB_DL_SmithPredictor` 引用 `FB_DL_PidController`，随子库整体导入即可。

---

> R37 增量行：组件总数 59→**64**（registry 实测口径，本轮 +1 `FB_DL_ResonanceTrackNotch` 16#02_3_82）；机检 10/10 PASS；码位零撞车。

## v1.26 — 2026-11-21（R59）

R59 新增 MracAdaptiveCtrl / CraneAntiSway；PmvComfortIndex 与 PeriodicDisturbComp 升 v1.0.1（非有限复检、环块双清声明、常量名实对齐）。

## 当前版本 / Current Version

| 项 / Item | 值 / Value |
|---|---|
| 子库版本 / Sublibrary Version | **v1.18.0** |
| 组件总数 / Components | **67**（registry 实测口径，R30 新增见下方增量行：56→58） |
| 发布日期 / Release Date | 2026-11-18 |
| 库总版本 / Library Version | 2.30.0 |
| 依赖层级 / Dependency Level | Level 1（仅依赖 Level 0 与 `Standard.library`；R13 新件 `FB_DL_FoulingResistanceEstimator` 引用 `E_DL_Ne107Status`（DL_Device 契约件 A1）作健康出口类型，属契约类型引用而非算法依赖） |
| 故障码段 / Error Code Family | **`16#0002_xxxx`**（公共码 `0002_0001`~`0005` 全子库共用 ｜ R12 子块 `0002_2001`~`2003`、`2010`~`2012`（阀特性族）与 `0002_2101`~`2102`（水焓族）｜ **R13 新开子块 `0002_2201`~`2204` 与 `2210`~`2212`（污垢趋势族）**） |


## v1.17.0 ｜ 2026-11-18 ｜ R38：3 件（PidLambdaTune / HeatExchangerLmtd / CrossCorrelationDelay）

| # | 组件 / Component | 类型 | 码位 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|
| 5 | FC_DL_PidLambdaTune | FC | `16#02_3_83` | t2-1-lgf-math | IMC/λ 整定纯换算（K/T/τ/λ → Kc/Ti/Td），不产生激励、不闭环 |
| 6 | FC_DL_HeatExchangerLmtd | FC | `16#02_3_84` | t2-1-lgf-technology | LMTD + ε-NTU 效能（逆流/并流/1-2 程 F 修正，端差趋零退算术平均） |
| 7 | FB_DL_CrossCorrelationDelay | FB | `16#02_3_85` | t2-4-s7-motion | 互相关时延估计（峰值定位 + 抛物线亚采样插值 + 置信度门限） |

> R38 增量行：组件总数 → **67**（registry 实测口径）；库总版本 2.30.0。

## v1.14.0 ｜ 2026-11-18 ｜ R30 暖通算法批：2 件

- `FB_DL_FanArraySeq`：风机阵列轮值与变频/工频混拖调度（轮值委托 DutyStandbyRotation 范式 + 分级投切消费 FanArrayStageCtrl + 一台同拍至多一种模式）（0002_3729~372D）。
- `FB_DL_ChwDifferentialPressure`：冷冻水差压旁通控制（压差平滑消费 MovingAverage + 设定值重置限速消费 RateLimiter + 阀位限幅饱和信息码；并入 ROADMAP L837 压差重置条目）（0002_372E~3732）。

> R30 增量行：组件总数 56→**58**（registry 实测口径）；非有限压差 → 阀位保持 + 故障码（安全侧不新增动作）。

---

## v1.9.0 ｜ 2026-11-16 ｜ R19 控制律批：流量开方/比值控制/超前滞后/继电自整定 4 件

- `FB_DL_FlowSqrtExtract`：差压流量开方与低切切除（迟滞切除 + 阻尼）（码位见 .st 头注释码位总账）。
- `FB_DL_RatioController`：比值控制器（从动量跟随主动量比值）（码位见 .st 头注释码位总账）。
- `FB_DL_LeadLagCompensator`：超前滞后补偿 Kc(1+T_lead·s)/(1+T_lag·s)，Tustin 离散化 + 改参保状态（码位见 .st 头注释码位总账）。
- `FB_DL_AutoTuneRelay`：继电反馈自整定（描述函数 Ku + ZN/AH 四规则，五态机，撤继电最高危点）（码位见 .st 头注释码位总账）。

> `16#0002_` 段游标：组件序号 **CC = 2B**（下件起点，实测 2B00~2BFF 空闲）。

---

## v1.8.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：无扰切换 + 增益调度 + 陷波 + I2t 热模型 4 件 / R18 Scenario Lane — 4 Control Compensation Components

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。

### 新增组件（4 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_BumplessTransfer` | FB | 手动末值按限斜率过渡到 PID 输出，手动期反算跟踪 | `fPidOut` / `fRateMax` / `fOut` |
| `FB_DL_GainScheduler` | FB | 按调度变量落区间输出该段一组 PID 参数 | `fScheduleVar` |
| `FB_DL_NotchFilter` | FB | 中心频率 + Q 可调二阶陷波，改参只重算系数不清状态 | `fCenterFreq` / `fQuality` / `tSampleTime` |
| `FB_DL_ThermalI2tModel` | FB | 按 d(theta)/dt = ((I/Ir)^2 - theta)/tau 累积热容量 | `fCurrent` |

> 码位以注册表 `code_segment` 为准；全库重叠复测 = 0。

## v1.7.0 ｜ 2026-11-16 ｜ R13 换热器污垢热阻趋势估计（DL_Algo 第 28 件，工艺退化算法底座）/ R13 Fouling Resistance Trend Estimator

**变更性质**：MINOR（新增 1 个组件），无破坏性变更，无迁移动作。对应 Round 13「换热器本体退化算法底座：只做『算一个值 + 算一个趋势』」定位（来源标签 oscat-building / heat-transfer，行为定义与引脚组织借鉴、公式取公开传热学常识 Q = m·cp·ΔT、LMTD、Rf = 1/K − 1/K_clean，clean-room 未复制源码）。终审 **零修改 PASS**。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 28 | `FB_DL_FoulingResistanceEstimator` | FB | 558 | 1.0.0 | oscat-building / heat-transfer | 换热器污垢趋势算法底座：由两侧进出口温度与体积流量算热负荷 Q、对数平均温差 LMTD、实测传热系数 K，再以清洁态基准 K_clean 反算污垢热阻 Rf = 1/K − 1/K_clean，趋势窗内最小二乘拟合增长斜率并给出清洗建议；不做 PID、不控阀门、不做结垢成分分析；数据不可信（温差过小 / 流量过低 / 热负荷不平衡 / 输入非有限）时**拒绝更新并保持上次有效值**——宁可不给数，也不给脏数（R42）；流型切换趋势基准重置留档 2204 / Fouling resistance estimator with least-squares trend and cleaning advice |

### 故障码台账追加（R13 码位登记，经终审全库复核 0 重叠）/ Error Code Ledger Additions (R13)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0002_2201` | 信息级 | LMTD 低于最小可用温差 | FB_DL_FoulingResistanceEstimator |
| `0002_2202` | 信息级 | 流量低于下限比例 | FB_DL_FoulingResistanceEstimator |
| `0002_2203` | 信息级 | 两侧热负荷偏差超容差 | FB_DL_FoulingResistanceEstimator |
| `0002_2204` | 信息级 | 逆/顺流口径切换，趋势基准已重置 | FB_DL_FoulingResistanceEstimator |
| `0002_2210` | 故障级 | 换热面积/清洁 K 非正或输入非有限 | FB_DL_FoulingResistanceEstimator |
| `0002_2211` | 故障级 | LMTD ≤ 0（温度交叉或流型用错） | FB_DL_FoulingResistanceEstimator |
| `0002_2212` | 故障级 | 非法状态兜底 | FB_DL_FoulingResistanceEstimator |

---

## v1.6.0 ｜ 2026-11-15 ｜ R12 调节阀特性补偿 + 水比焓（工艺参数域与 OSCAT Building 续深，2 件）/ R12 Valve Characteristic & Water Enthalpy

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 12「工艺参数域（阀特性）+ 建筑热工（水焓）」定位（来源标签 isa88-process 参数域 / oscat-building，clean-room 未复制源码）。终审 **2 件中 1 件零修改 PASS，1 件修复后 PASS**（`FB_DL_ValveCharacteristic` 1 条严重缺陷，升 v1.0.1）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 26 | `FC_DL_WaterEnthalpy` | FC | 131 | 1.0.0 | oscat-building | 水比焓（0 ℃ 基准）：三次多项式比热积分给出 `fEnthalpy`，同出 0 ℃ 到当前温度的平均比热 `fCpMean`；温度域 0~150 ℃，域外拒绝并置码而不外插（外插在 100 ℃ 相变附近会给出物理上不存在的值） / Water specific enthalpy from a cubic cp polynomial with a 0..150 ℃ domain |
| 27 | `FB_DL_ValveCharacteristic` | FB | 308 | **1.0.1** | isa88-process | **v1.0.1** —— 调节阀固有特性补偿：线性 / 等百分比 / 快开三种特性折算为阀位给定，含行程上下限限幅、输出死区、可调比域守护与饱和方向报码；等百分比低于可调比下限时阀位归零；行程倒置直接判故障而不静默交换上下限；v1.0.1 投运与复位首拍改为「保持上次阀位并夹进行程」（R43） / Inherent valve characteristic compensation with travel clamp, deadband and rangeability guard |

### 故障码台账追加（R12 码位登记，经终审全库复核）/ Error Code Ledger Additions (R12)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0002_2001` | 信息级 | 输出被行程下限截断（含流量给定越下限钳位），`bSaturated` 置位 | FB_DL_ValveCharacteristic |
| `0002_2002` | 信息级 | 输出被行程上限截断（含流量给定越上限钳位），`bSaturated` 置位 | FB_DL_ValveCharacteristic |
| `0002_2003` | 信息级 | 输出变化小于死区，保持上次阀位 | FB_DL_ValveCharacteristic |
| `0002_2010` | 故障级 | 行程配置非法（上下限越 0~100 或倒置），锁存并保持上次阀位 | FB_DL_ValveCharacteristic |
| `0002_2011` | 故障级 | 可调比对数分母的二次守卫触发（正常钳位下不可达，防调用方绕过钳位注入） | FB_DL_ValveCharacteristic |
| `0002_2012` | 故障级 | 非法特性枚举兜底，锁存并保持上次阀位 | FB_DL_ValveCharacteristic |
| `0002_2101` | 信息级 | 水温越 0~150 ℃ 域，已拒绝并置 `bValid` 假（不返 NaN、不外插） | FC_DL_WaterEnthalpy |
| `0002_2102` | 信息级 | 零度点附近平均比热退化为一次项系数（分母保护生效） | FC_DL_WaterEnthalpy |

**号段占用声明**：本批 `DL_Algo` 取 `0002` 段两个新带——阀特性族 `2001`~`2003` 与 `2010`~`2012`、水焓族 `2101`~`2102`，均为 R11 `1F` 之后的顺延，未跳号、未回填 `0900` / `1300` 两处历史空置带。终审逐码求差：与全库既有码位零重叠。

### 缺陷修复 / Fixed

| 组件 / Component | 级别 | 缺陷 / Defect | 修复 / Fix |
|---|---|---|---|
| `FB_DL_ValveCharacteristic` | **严重** | 故障复位或首次投运当拍，阀位由上次值**直跳行程下限**（默认 0%）——调节阀突跳（水锤 / 批量扰动）；冷启动时 `fTravel` 还可能低于 `fMinTravel`（域外值），与「出口域为生效行程之间」的契约矛盾 | `eIdle` 成功分支由「清零式初始化」改为 `fLast := MIN(MAX(fLast, fLoTravel), fHiTravel); fTravel := fLast`：保持上次阀位并夹进有效行程，同时补齐行程域的出口保证 |

### 变更说明 / Change Notes

- **规格冲突的处置留痕**：计划 3.11 节正文提到 `2004` / `2005` / `2006` 三个「输入钳位」码，但同计划第 1.2 节只给本件分配 `2001`~`2003` 与 `2010`~`2012`。按「码位表为准、不得自创」的纪律，实现把流量给定越界钳位并入 `2001` / `2002`（越界必然让输出打端点，语义与截断一致），可调比与死区的钳位属整定参数修正、不单独置码，已在文件头注释「规格偏离留档」登记。
- **水焓件不复用湿空气焓件**：`FC_DL_HumidAirEnthalpy` 处理湿空气（含含湿量与潜热），本件处理液态水（仅显热多项式），两者量纲与适用域不同，互相调用只会引入错误基准。
- **红线状态**：R1~R44 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v1.5.0 ｜ 2026-11-15 ｜ R11 批级工艺微调族开族（Run-to-Run EWMA，1 件）/ R11 Run-to-Run EWMA Tuner

**变更性质**：MINOR（新增 1 个组件），无破坏性变更，无迁移动作。对应 Round 11「DL_Algo 1F00 带开带件」（来源标签 semiconductor-APC / lgf-technology，仅借鉴批事务四段功能分类与参数域命名，clean-room 未复制源码）。终审 **PASS（零修改）**。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 25 | `FB_DL_R2rEwmaTuner` | FB | 389 | 1.0.0 | semiconductor-APC / lgf-technology | Run-to-Run 批级工艺参数自动微调器：一批只动一次（`bNewLot` 上升沿开事务，`eCompute` 算 / `eApply` 写各驻留一拍），实测偏差经 EWMA 平滑后按工艺增益倒数折算修正量；**双约束次序固定**——先限单次修正量（工艺侧安全）再限参数域（设备侧安全），颠倒会把「参数到界」误报成「修正被限」；首样本直取不让 0 参与平均（否则前若干批严重偏置）；批次计数饱和、偏差写深度 10 环缓冲，投运期可完整审计 / Lot-level Run-to-Run tuner with EWMA smoothing and dual clamping |

### 故障码台账追加（R11 码位登记，经终审全库复核）/ Error Code Ledger Additions (R11)

| 码位 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0002_1F01` | 信息级 | EWMA 权重 λ 越出 0~1，已双向钳位 | FB_DL_R2rEwmaTuner |
| `0002_1F02` | 信息级 | 历史无 EWMA 样本，本批按首样本直取（不与 0 平均） | FB_DL_R2rEwmaTuner |
| `0002_1F03` | 信息级 | 单次修正量达限幅，已钳到正负限幅值 | FB_DL_R2rEwmaTuner |
| `0002_1F10` | 故障级 | 实测值 / 目标值 / 增益倒数非有限值，拒绝本批并锁存 | FB_DL_R2rEwmaTuner |

**号段占用声明**：本批在 `DL_Algo` 既有 `0002_xxxx` 段内**新开 `1Fxx` 子块**（`1F01`~`1F03` 信息级 / `1F10` 故障级），与既有 `0002_000x`（公共码）、`0002_01xx`~`0002_18xx`（各组件私有码）不重叠；码优先级 `1F03 > 1F02 > 1F01`，同拍多条件命中时高者上报。参数域上界到界只置 `bAtLimit`、不另占码位（按 R30 不越块取码）。

### 变更说明 / Change Notes

- **时间尺度分层**：`FB_DL_PidController` 是拍级连续闭环、`FB_DL_RateLimiter` 限信号变化率、本件是批级离散更新（一批只动一次），三者时间尺度差三到四个数量级，不可互替。本件刻意不复用 `DL_MathData` 滤波件，EWMA 与限幅全部内联，避免拍级滤波语义与批级更新语义混淆。
- **规格偏离留档**：① 规格的历史成员名带数组前缀却定义为 BOOL，与「布尔量 b 前缀」红线冲突，实现定名 `bHasEwma`（语义不变）；② 规格未给参数域非法分配码位，实现只置 `bAtLimit` 并保持参数域下限，不越块取码。
- **红线状态**：R1~R32 全部通过，机检 0 命中；本批未触碰既有文件，`DL_Algo` 跨文件码位重叠 = 0。

---

## v1.4.0 ｜ 2026-11-15 ｜ R10 信号发生族 + 卷绕/空气密度工艺算法（4 件）/ R10 Signal Generators & Process Algorithms

**变更性质**：MINOR（新增 4 个组件）+ PATCH（2 个本轮件注释级修复 → v1.0.1），无破坏性变更，无迁移动作。对应 Round 10「DL_Algo 信号发生族 + 技术算法」（来源标签 lgf-signalgen / lgf-technology / oscat-building，RAW_NOTES_R10 S-2/S-4/S-5：仅借鉴 LGF 组粒度与公开物理公式，clean-room）。终审 **PASS with fixes**：`FB_DL_SineGenerator` / `FB_DL_SawtoothGenerator` 各修 1 处注释级（D-15/D-16：验收向量与逐拍推演矛盾，改为逐拍序列 + 相位采样约定段）→ v1.0.1；`FC_DL_CoilDiameterCalc` / `FC_DL_AirDensity` 零修改 PASS。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 行数 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 21 | `FB_DL_SineGenerator` | FB | 401 | **1.0.1** | lgf-signalgen | 相位累加正弦发生器（任务周期 + 频率引脚推进，三态 待机/运行/故障 + CASE 兜底）：相位回绕用减法 + 单拍回绕次数上限防死锁（欠采样时一次减多个 2π 但不得无界循环）+ 幅值非负化 + 输出双侧限幅 + 完整周期计数；失能与频率 0 均冻结相位不归零；**一拍固有延迟已在头注释显式约定** / Phase-accumulating sine generator with explicit one-scan latency |
| 22 | `FB_DL_SawtoothGenerator` | FB | 404 | **1.0.1** | lgf-signalgen | 对称度参数化锯齿 / 三角波（`fSymmetry` 0.01~0.99，0.5 = 对称三角）：上升/下降分段斜率独立、周期回绕清零 + `bRising` 段标志 + 周期内相位百分比；与 Sine 同族不同波形，禁 `eWaveform` 合并 / Symmetry-parameterised sawtooth/triangle generator |
| 23 | `FC_DL_CoilDiameterCalc` | FC | 298 | 1.0.0 | lgf-technology | 卷径瞬时几何反算纯函数（`D = v · i / (π · n)`）：低速保护先于除法（转速 < 0.5 rpm 沿用 `fPrevDia` 注入的上次值，状态由调用方持有）+ 卷芯保护（反算小于卷芯按卷芯修正，疑似打滑）+ 一阶低通首拍无滞后 + 卷径变化率先算再更新历史 + 层数与未滤波值双出口；层厚积分递推与排线执行归 `FB_DL_WindingTraverse`，两件零调用互为校验 / Coil diameter inverse calculation with low-speed and core guards |
| 24 | `FC_DL_AirDensity` | FC | 219 | 1.0.0 | oscat-building | 湿空气密度计算（Magnus-Tetens 饱和蒸汽压 + 干/湿分压叠加）：分母 `243.12 + T` 在工况域恒正、分压防负、密度域 0~20 kg/m³ 钳位；精度承诺限 -10~50 ℃ / Moist air density via Magnus-Tetens and partial-pressure superposition |

### 故障码台账追加（R10 编号带登记：算法族每件独占一个 `1x` 带）/ Error Code Ledger Additions (R10)

| 码位带 | 级别 | 语义 / Meaning | 组件 |
|---|---|---|---|
| `0002_1B01~1B04` | 信息级 | 任务周期 / 频率 / 幅值 / 初相越界钳位 | FB_DL_SineGenerator |
| `0002_1B10` | 故障级 | 参数非有限值，锁存 `bError`，输出保持值 | FB_DL_SineGenerator |
| `0002_1B11` | 故障级 | 相位回绕超限（欠采样）或非法状态兜底 | FB_DL_SineGenerator |
| `0002_1C01~1C03` | 信息级 | 周期 / 对称度越界钳位、高低值区间过窄抬高上限 | FB_DL_SawtoothGenerator |
| `0002_1C10` | 故障级 | 参数非有限、回绕超限或非法状态兜底 | FB_DL_SawtoothGenerator |
| `0002_1D01~1D04` | 信息级 | 线速度 / 传动比 / 卷芯或厚度钳位、反算卷径小于卷芯（疑似打滑） | FC_DL_CoilDiameterCalc |
| `0002_1D10` | 信息级 | 转速过低不可信或入参非有限，沿用上次有效值 | FC_DL_CoilDiameterCalc |
| `0002_1E01~1E04` | 信息级 | 温度 / 压力 / 湿度钳位、干空气分压为负钳到 0 | FC_DL_AirDensity |
| `0002_1E10` | 信息级 | 入参非有限，返回 0 | FC_DL_AirDensity |

### 变更说明 / Change Notes

- **编号带惯例（R10 观察项 7.4 采纳）**：算法族每件独占一个 `1x00` 编号带（`1B` 正弦 / `1C` 锯齿 / `1D` 卷径 / `1E` 空气密度），带内 `01~0F` 事件码、`10+` 信息码；建议写入 coding-standard 作为算法族的推荐做法。
- **职责分离**：Sine / Sawtooth 按「波形形状」切块（LGF Signal Generators 组粒度），与既有 `FB_DL_RampGenerator`（线性斜坡） / `FB_DL_SCurveGenerator`（S 曲线轨迹） / `FB_DL_PwmDutyController`（时间比例 PWM）四点正交；`FC_DL_CoilDiameterCalc` 与 `FB_DL_WindingTraverse`（DL_Motion，含排线执行）为「纯函数估算 vs 状态机执行」分工。
- **已知限制**：`FC_DL_CoilDiameterCalc` 常量 `DL_NMAX` 声明后未使用（卷径上限判据改用引脚），列为观察项 O-1，下一 PATCH 删除或接入钳位。
- **红线状态**：R1~R32 全部通过，机检 0 命中；全库码位跨文件重叠 = 0。

---

## v1.3.0 ｜ 2026-11-15 ｜ R8 峰值检测 + 多级步进控制器（LGF Math / LBP 深化）/ R8 Peak Detector & Step Controller

**变更性质**：MINOR（新增 2 个组件），无破坏性变更，无迁移动作。对应 Round 08「DL_Algo 统计/分级族深化」（来源标签 lgf-math / lbp-step-ctrl，T2-1 LGF Math 组统计族平移 + T2-2 LBP CtrlStp 平移，clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 19 | `FB_DL_PeakDetector` | FB | 4 | 1.0.0 | lgf-math | 峰值/谷值检测器：极值只升不降（除衰减与复位）+ 衰减模型（fDecayRate [EU/s]，0=无限保持）+ 谷值独立使能 + 峰值变化率（正值=仍在爬升）+ 阈值超限电平位 + 峰值更新单拍事件与冲击计数；与 `FB_DL_SignalStatistics` 的窗口统计量职责分离（本块做全周期极值保持，统计块做窗口聚合） / Peak/valley detector with decay model and threshold events |
| 20 | `FB_DL_StepController` | FB | 6 | 1.0.0 | lbp-step-ctrl | 多级步进控制器（1..8 级，LBP CtrlStp 语义平移）：偏差归一化分级 + 级间死区（迟滞半宽）+ 最小驻留（换级后须停留）+ 累积（多级依次投入）/单级（互斥）双拓扑 + 均衡轮换偏移（同型设备轮换）+ 满出力/回零警示 / Multi-stage step controller with hysteresis, dwell and rotation |

### 变更说明 / Change Notes

- **LGF Math 统计族平移（实测修正落地）**：LGF V1.0.1 公开手册中统计/极值函数实际归在 Math 组内，并无独立的 Measurement 功能组——`SOURCE_HUNTING_MATRIX.md` 第 2 节「Measurement Operations」单列行的假设已更正，本块及后续统计-峰值族一律在 Math 行记账。
- **与 SignalStatistics 的职责边界**：PeakDetector 只做「全周期极值保持 + 事件」，不做窗口聚合——两个块可串联（统计块供趋势、本块供报警阈值），不互相替代；禁止把两者合并成带 MODE 的巨无霸（公约 0.16 反面教材禁令）。
- **衰减模型**：fDecayRate > 0 时峰值按 EU/s 衰减（冲击型信号回落后极值缓慢下降，避免一次冲击永久占住峰值）；衰减步长 = 速率 × 采样周期秒值，tSample=T#0S 不衰减。
- **LBP CtrlStp 平移**：借「偏差分级 + 级间迟滞 + 最小驻留 + 均衡轮换」语义 clean-room 重写；LBP V2.8 实测 23 块无独立混合/定量组（见 T2-2 行实测修正），分级语义按本库 1..8 级数组输出承载。
- **换级纪律**：级间死区为迟滞半宽（fDeadband），加/减级判据在死区两侧分离；最小驻留 `tMinDwell` 内换级请求被拒并出信息级 `0002_1A01`（每拍重算）；轮换偏移按级数取模归约，仅累积拓扑 + 同型设备场景使用。
- **故障码**：信息级 `0002_19xx`（PeakDetector：1901 输入非有限值已保持 / 1902 阈值非有限已禁用 / 1903 衰减率非法 / 1904 采样周期越界钳位）与 `0002_1Axx`（StepController：1A01 驻留未到 / 1A02 级数钳位 / 1A03 带宽非法回默认 / 1A04 死区过大钳半级带 / 1A05 输入非有限级数保持；故障级 1A06 级带宽退化无法运算）——独立 19xx/1Axx 族段，经子库码表核对顺延，冲突 0。信息级不置 bError（R21）；PeakDetector 全信息级故 bError 恒 FALSE。
- **红线状态**：R1~R7 全部通过，机检 0 命中；R19 首扫范式（PeakDetector `_bInit` 初值 FALSE、首采直通基准）；R25 单拍标志三律（峰值/谷值更新事件每拍预清零、事件置位一拍）。

### 已知限制 / Known Limitations

1. `FB_DL_PeakDetector` 衰减模型为线性速率衰减，非指数衰减；指数衰减族留扩产评估。
2. `FB_DL_StepController` 级数上限 8（`abStage` 维度 8 字面量，同 DL_CAM 系理由——FB 内部常量不能用于自身引脚声明）；更多级数由两实例串联或扩产变体。
3. `FB_DL_StepController` 轮换偏移不校验「各物理设备是否同型」——不同容量级混布时轮换语义由调用方保证（头注释声明）。

---

## v1.2.0 ｜ 2026-11-15 ｜ R6 Ramp/Soak 程序曲线（LGF Technology 组曲线族深化）/ R6 RampSoak Profile

**变更性质**：MINOR（新增 1 个组件），无破坏性变更，无迁移动作。对应 Round 06（R6）「DL_Algo 曲线族深化」（来源标签 lgf-technology，T2-1 LGF Technology clean-room）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 18 | `FB_DL_RampSoakProfile` | FB | 6 | **1.0.1** | lgf-technology | 多段 Ramp/Soak 程序曲线发生器（1..16 段）：段目标+斜坡+保温三数组、段切换沿单发、外部保持（冻结当前值与段内计时）/跳段/循环运行、中途跟踪无扰重启；温控区设定源，烘箱/烧结炉/化成工步共用 / Multi-segment Ramp/Soak profile generator |

### 随组件同文件发布的枚举 / Enums Shipped with Host Files

`E_DL_RampSoakPhase`（eIdle/eRamp/eSoak/eDone/eFault 五态，编号步长 10）随 `FB_DL_RampSoakProfile` 同文件发布。

### 故障码（18xx 独立族段，终审裁定）/ Error Codes

- **族段裁定**：规格原分配信息级 `0110~0113`、故障级 `0220` 侵入既有 01xx PID / 02xx 串级族段（数值未撞码但族段语义冲突），终审裁定划**独立族段 `18xx`（Ramp/Soak 程序曲线族）**并已修正——信息级 `0002_1801`（末段跳段完成）/ `0002_1802`（段数钳位至 1）/ `0002_1803`（零斜坡阶跃直达）/ `0002_1804`（采样周期钳位），故障级 `0002_1810`（段目标非有限值，锁存进故障态仅复位可清）。语义零变更，仅码位重排；白名单复核与全库既有实占码零冲突。
- 既有公共码复用：`0002_0005` 非法状态兜底（子库族码）。
- v1.0.0 节故障码族段口径行已按授权补记 `17xx`/`18xx` 两行。

### 变更说明 / Change Notes

- **保温计时自实现（TON 不适用）**：外部保持需冻结段内计时，TON 无保持冻结语义——采用时间戳累加自实现（头注释声明理由）；换算与量纲推导注释齐备（R20）。
- **终审修复（→ v1.0.1）**：即上述故障码族段归位（唯一改动；其余逻辑零变更，机检 ALL PASS）。
- **跟踪/首扫范式**：`IF bTrack OR (NOT bInit)`（R19），跟踪释放后从当前值继续本段；验收向量含「中途跟踪脉冲→释放后连续」必测项。

### 已知限制 / Known Limitations

1. 段数上限 16：更多段数需求由上层串联两实例或扩产变体，不在本块加模式开关（禁止巨无霸）。
2. 段目标非有限值时段目标取前段目标（不可达防御）并锁存 `0002_1810`——不猜值、不静默。

---

## v1.1.0 ｜ 2026-11-15 ｜ R5 湿空气热力学补强 / R5 Psychrometrics Reinforcement

**变更性质**：MINOR（新增 1 个组件），无破坏性变更，无迁移动作。对应 Round 05（R5）「DL_Algo 补强」交付（来源标签 oscat-building / psychrolib）。

### 新增组件 / Added

| # | 组件 / Component | 类型 | 复杂度 | 版本 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 17 | `FC_DL_HumidAirEnthalpy` | FC | 4 | 1.0.0 | oscat-building+psychrolib | 湿空气比焓计算函数：Magnus-Tetens 饱和蒸汽压（与 `FC_DL_DewPointCalc` 同系数口径常量复用）→ 含湿量 → 焓公式链；大气压引脚注入（默认 101.325 kPa 非魔法数）；洁净室/干燥房表冷与再热功率预算、焓差控制 / Moist-air specific enthalpy via Magnus-Tetens chain |

### 变更说明 / Change Notes

- **故障码**：按公约 0.7 沿用 DL_Algo 既有 `16#0002_xxxx` 段，细分 17xx（15xx 露点 / 16xx 流量已占用顺延）：`0002_1701` 温度/湿度越界已钳位照算、`0002_1702` 大气压越界已钳位照算、`0002_1703` 饱和退化分母已保护——全部信息级；公共码 `0002_0004` 输入非有限值已拒绝。
- **行为定义对标**：OSCAT Building `AIR_ENTHALPY`（0~100 ℃ 域）与 PsychroLib `GetMoistAirEnthalpy` 的公开物理公式链；公开物理公式无版权义务，100% clean-room 重写并按本库防御规范加严。
- **防御口径**：全部 REAL 输入非有限值检测；`fRelHum` 钳位 [1,100] 防 W 发散；`fAtmPress` 越界钳 [80,110] kPa 并置码；饱和退化分母 1 Pa 下限保护输出有限值。
- **红线状态**：R1~R7 全部通过，机检 0 命中。

### 已知限制 / Known Limitations

1. 返回值为「每公斤干空气」比焓：做能量平衡时风量须乘干空气密度换算，勿直接乘湿空气总流量。
2. 100 ℃ / 100% RH 附近含湿量 W 发散是物理事实，该域结果无工程意义（1 Pa 分母下限保护仅保证输出有限），勿用于工艺联锁。
3. 高海拔厂房（大气压 < 80 kPa）会被钳位并置 `0002_1702`，含湿量系统性偏小——高海拔工程须评估适用性。

---

## v1.0.0 ｜ 2026-11-15 ｜ Level 1 首库开库 / Initial Release — Level 1 Opening

**变更性质**：初始发布（Initial release），无破坏性变更，无迁移动作。全部 16 个组件自 v1.0.0 起入库，其中 8 个于本轮阶段五终审后以 PATCH（v1.0.1）交付精修版（引脚契约不变）。

### 组件清单 / Component Inventory

| # | 组件 / Component | 类型 | 版本 | 复杂度 | 来源标签 | 一句话说明 / Summary |
|---|---|---|---|---|---|---|
| 1 | `FB_DL_PidController` | FB | **1.0.1** | 8 | mod-pid-control+oscat-basic+lgf-technology | 单回路位置式/增量式 PID：死区、积分分离、两级抗饱和、手自动无扰与跟踪回投 / Single-loop PID with anti-windup and bumpless transfer |
| 2 | `FB_DL_CascadePid` | FB | 1.0.0 | 8 | mod-pid-control+lgf-technology | 主副双回路串级，内部组合两个 `FB_DL_PidController` 实例 / Master-slave cascade PID |
| 3 | `FB_DL_SplitRangeControl` | FB | 1.0.0 | 5 | mod-pid-control+lgf-technology | 分程输出分配（加热/冷却双执行器），中央死区防双阀同开 / Split-range allocation |
| 4 | `FB_DL_FeedforwardComp` | FB | **1.0.1** | 6 | lgf-technology | 静态 + 动态前馈补偿，含 10 槽纯滞后队列 / Static and dynamic feedforward |
| 5 | `FB_DL_SmithPredictor` | FB | **1.0.1** | 9 | lgf-technology+mod-pid-control | 史密斯预估器，一阶模型 + 20 槽滞后缓冲，长滞后对象 / Smith dead-time compensator |
| 6 | `FB_DL_RateLimiter` | FB | 1.0.0 | 4 | lgf-technology+lgf-signalgen | 变化率限制，升降斜率独立 + 保持，速率为 0 表示不限 / Slew-rate limiter |
| 7 | `FB_DL_RampGenerator` | FB | **1.0.1** | 4 | lgf-signalgen+lgf-technology | 线性斜坡发生器，斜率独立 + 暂停保持 + 跟踪投切 / Linear setpoint ramp |
| 8 | `FB_DL_SCurveGenerator` | FB | **1.0.1** | 9 | lgf-signalgen+lgf-technology | 七段式 S 型轨迹，jerk→acc→vel→pos 四级积分链真实推进 / Seven-phase jerk-limited S-curve |
| 9 | `FB_DL_PwmDutyController` | FB | **1.0.1** | 6 | lgf-signalgen+mod-pid-control | 时间比例慢速 PWM，最小 ON/OFF 抑制（欠脉冲债务补偿），SSR 加热 / Time-proportional slow PWM |
| 10 | `FB_DL_Integrator` | FB | **1.0.1** | 4 | oscat-basic+lgf-math | 梯形法积分（LREAL 双精度累加），限幅/复位/保持，流量累计 / Trapezoidal integrator |
| 11 | `FB_DL_Differentiator` | FB | **1.0.1** | 5 | oscat-basic+lgf-measurement | 带一阶低通 + 速率限幅的实用微分器 / Practical differentiator |
| 12 | `FB_DL_LowPassFilter` | FB | 1.0.0 | 3 | lgf-measurement | 一阶低通（PT1），时间常数运行时可调 / First-order low-pass |
| 13 | `FB_DL_SecondOrderFilter` | FB | **1.0.1** | 6 | lgf-measurement | 二阶巴特沃斯低通（双线性离散，ζ=0.7071，-40dB/dec） / Second-order Butterworth |
| 14 | `FB_DL_HighPassFilter` | FB | 1.0.0 | 4 | lgf-measurement | 一阶高通（HP1），动态分量提取 / 振动监测 / First-order high-pass |
| 15 | `FC_DL_DewPointCalc` | FC | 1.0.0 | 3 | oscat-basic+psychrometrics | Magnus-Tetens 露点计算（-40..60°C，0.1..100%RH） / Magnus-Tetens dew point |
| 16 | `FC_DL_FlowCompensate` | FC | **1.0.1** | 5 | oscat-basic+gas-metering | 气体/蒸汽流量温压补偿（工况 → 标况 Nm³/h） / Flow temperature-pressure compensation |

> 来源口径：仅借鉴各来源库的**功能分类与参数域**（T2-1 LGF Signal Generators / Technology / Measurement、T2-5 Mod_PID_Control、T1-1 OSCAT Basic 等公开语义描述），实现代码 100% 独立编写（clean-room），未复制任何厂商源码；OSCAT 为 EPL-2.0 / BSD 类许可，语义借鉴合规。

### 随组件同文件发布的枚举 / Enums Shipped with Host Components

`E_DL_PidState`（随 #1）、`E_DL_CascadeState`（随 #2）、`E_DL_SplitState`（随 #3）、`E_DL_FfState`（随 #4）、`E_DL_SmithState`（随 #5）、`E_DL_RateState`（随 #6）、`E_DL_RampState`（随 #7）、`E_DL_SCurveState`（随 #8）、`E_DL_PwmState`（随 #9）、`E_DL_IntState`（随 #10）、`E_DL_DiffState`（随 #11）、`E_DL_LpfState`（随 #12）、`E_DL_SofState`（随 #13）、`E_DL_HpfState`（随 #14）——共 14 个，与宿主功能块同文件发布，导入 `.st` 即随宿主一并入库。

### 变更说明 / Change Notes

- **接口契约**：16 个组件的引脚名称、类型、方向、默认值与终审后源码逐字一致；引脚级细节以 `DL_Algo/*.st` 声明区为准，完整接口表见 `MANUAL_DL_Algo.md`。
- **故障码**：全部使用 `16#0002_xxxx` 段并按组件细分（01xx PID / 02xx 串级 / 03xx 分程 / 04xx 前馈 / 05xx 史密斯 / 06xx 斜坡 / 07xx S 曲线 / 08xx PWM / 10xx 低通 / 11xx 二阶 / 12xx 高通 / 14xx 微分 / 15xx 露点 / 16xx 流量；17xx 湿空气焓值见 v1.1.0；18xx Ramp/Soak 程序曲线族——R6 终审裁定自 01xx/02xx 顺延占位归位的独立族段，承载 `FB_DL_RampSoakProfile` 信息级 1801~1804 与故障级 1810，口径以该组件 v1.0.1 头注释为准），公共码 `0001`（参数越界已钳位）、`0002`（采样周期已钳位）、`0004`（输入非有限值已拒绝）、`0005`（非法状态兜底）子库内语义统一；完整表见 `MANUAL_DL_Algo.md` 各节与总表登记说明。
- **通用约定**：`tSampleTime` 小于 10ms 一律钳位为 10ms 并置 `16#0002_0002`，不中断扫描；量程/限幅参数 Min > Max 自动对调修复并置码；非有限值输入当拍拒绝更新、保持上一拍输出。
- **终审状态**：16/16 PASS，红线 R1~R7 全部通过，机检 0 命中；终审修复 16 处缺陷（含 `FB_DL_Integrator` / `FB_DL_SCurveGenerator` 两处首扫判据反向致命锁死），并沉淀 R8 首扫标志唯一合法范式。

### 已知限制 / Known Limitations

1. `FB_DL_FeedforwardComp` 纯滞后队列固定 10 槽、`FB_DL_SmithPredictor` 模型滞后队列固定 20 槽：`tDelayTime` / `tModelLag` 折算深度超上限时**截断并置码**，不做动态扩容；长滞后对象须核对「周期 × 槽数 ≥ 滞后时间」。
2. `FB_DL_SCurveGenerator` 采用自适应减速行程估算（乘裕量 1.05），非段间精确对称闭式解；三约束（速度/加速度/Jerk）逐拍限幅仍全部满足。
3. `FC_DL_DewPointCalc` 采用过水面 Magnus 参数化，冰点以下为霜点近似；精密工艺（锂电干燥房对标）建议上层做冰面修正。
4. `FC_DL_FlowCompensate` 压缩因子比 Zs/Za 按中低压（绝压 < 2 MPa）口径简化为 1；高压计量需上层引入真实气体因子修正。
5. 子库故障码与 Level 0 早期登记的 `16#0002_xxxx` 业务语义（同步超时、联锁配置非法等）存在段内编号并行使用，判读以各组件手册节为准，全库归并登记于 `LIBRARY_MANUAL.md` 第四节。

---


## v1.11.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 5 件（T1-2 焓湿图原子族（族属主 VaporPressureSat，族内其余件一律调用取饱和压））

- `FC_DL_VaporPressureSat`：饱和水蒸气压计算（Magnus-Tetens 过水面参数化，焓湿图全参族公式唯一属主件）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_HumidityRatioCalc`：含湿量计算（水汽分压反算 W = 0.622·pv/(p−pv)，饱和压取族属主）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_WetBulbTempCalc`：湿球温度估算（Stull 2011 湿度计方程迭代；**v1.0.1 挂账警示：R24 立项修迭代格式前禁用于生产**）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_RhFromDewPoint`：露点反算相对湿度（Magnus 反解，与属主件同口径）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_MixAirStateCalc`：回风/新风混合点状态计算（质量守恒加权 + 内联混合焓 + 结露预警，v1.0.1 补六输入非有限闸）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Algo] = 43，本文档原记 34（历史批次漏计，随本节一并校正）；本轮已校正为注册表口径。

> **终审留痕**：3 件终审修复（WetBulb v1.0.1 挂账警示 / MixAir v1.0.1 闸门补全 / DewPointCalc·HumidAirEnthalpy v1.0.1 属主转移声明）。


## v1.11.0 ｜ 2026-11-17 ｜ R23 行业纵深轮 5 件（T1-2 焓湿图原子族（族属主 VaporPressureSat，族内其余件一律调用取饱和压））

- `FC_DL_VaporPressureSat`：饱和水蒸气压计算（Magnus-Tetens 过水面参数化，焓湿图全参族公式唯一属主件）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_HumidityRatioCalc`：含湿量计算（水汽分压反算 W = 0.622·pv/(p−pv)，饱和压取族属主）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_WetBulbTempCalc`：湿球温度估算（Stull 2011 湿度计方程迭代；**v1.0.1 挂账警示：R24 立项修迭代格式前禁用于生产**）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_RhFromDewPoint`：露点反算相对湿度（Magnus 反解，与属主件同口径）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。
- `FC_DL_MixAirStateCalc`：回风/新风混合点状态计算（质量守恒加权 + 内联混合焓 + 结露预警，v1.0.1 补六输入非有限闸）（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。

> **R86 组件数断言**：注册表 counts[DL_Algo] = 43，本文档原记 43（一致）；本轮已校正为注册表口径。

> **终审留痕**：3 件终审修复（WetBulb v1.0.1 挂账警示 / MixAir v1.0.1 闸门补全 / DewPointCalc·HumidAirEnthalpy v1.0.1 属主转移声明）。

## 版本号约定 / Versioning Policy

子库遵循 SemVer，且与库总版本联动：

- **MAJOR**：任一组件删除引脚、改引脚语义、改默认值、改故障码含义。
- **MINOR**：新增组件，或为已有组件新增可选输入（带默认值）。
- **PATCH**：内部实现修正、注释与手册补全、性能优化，接口与行为不变。

破坏性变更必须在本文档写明迁移指引（旧调用 → 新调用）与影响的组件清单。

---

## 后续计划 / Next

`DL_Algo` 现累计 27 项（v1.0.0 首库 16 项 + v1.1.0 湿空气焓值 + v1.2.0 Ramp/Soak 曲线 + v1.3.0 峰值检测/步进控制器 + v1.4.0 信号发生族 4 项 + v1.5.0 R2R 批级微调 + v1.6.0（R12）水焓值与阀特性两件）。

v1.6.0 两件补的是**同一类工艺上游缺口**：`FC_DL_WaterEnthalpy` 把湿空气焓值（`FC_DL_MoistAirEnthalpy`）的能力面沿到**液态水/蒸汽**侧，使空调与蒸汽加热场景可共用一套物性口径；`FB_DL_ValveCharacteristic` 把调节阀的**流量特性曲线 + 等百分比/线性切换 + 行程限幅**做成单件，供 PID 输出直接串接。阀特性件的输入钳位码按码位表收敛到 `2001`/`2002`（流量越界），整定参数钳位不置码，细节见本文件 v1.6.0 段。

后续候选按 `ROADMAP.md` 推进：PID 自整定、选择性/超弛控制、稀疏表蒸汽焓值、陷波滤波器（机械共振）、增益调度（按工作点切换 PID 参数）、指数衰减峰值族等；`DL_Device` / `DL_Motion` 已开库并经 R6~R12 深化。本子库只接受 PATCH 级修正与既有组件可选引脚扩展。


---

## v1.10.0 ｜ 2026-11-16 ｜ R22 结构补位轮 2 件

**批次**：本子库 R22 新增 2 件（全库 20 件 6,618 行；机检 20/20 PASS fail=0）
**码位**：本子库本轮占用见各件头注释「码位总账」；收口后全库游标（注册表实测 2026-11-16）：`0001` 信息 `0466` / 故障 `03B7`、`0002` 下一 CC `2D`、`0003` 信息 `017A` / 故障 `0348`、`0004` 信息 `01DF` / 故障 `02F9`、`0005` 信息 `01E2` / 故障 `0317`
**终审结论**：R22 抽检 12 件高风险件，4 件轻微缺陷修复升 v1.0.1（MotionCmdQueue / VirtualMasterAxis / AxisBrakeSeq / BatchTransferSeq），1 件中等安全相关挂账 R23（BatchTransferSeq 中止时序），其余零缺陷 PASS
**码位跨文件冲突断言**：R22 100 槽定向复测 CLASH=NONE；JSONL 384 条全量 sha256 MATCH（本轮另修复 2 件历史换行口径漂移）

- `FB_DL_CrossLimitSelect`：燃烧双交叉限幅（空气/燃气先行选择律，先行裕度 < 1.0 双侧给定归零安全侧，非有限保持末次给定，依赖收窄：迟滞/限幅内联实现）。
- `FB_DL_ExcessAirTrim`：氧量修正（死区 + tConfirm 确认 + 固定步长累加双侧钳抗饱和 + 负荷变化率冻结）。

**终审**：本子库 1 件抽检（ExcessAirTrim）推演零缺陷 PASS。

---

## v1.12.0 ｜ 2026-11-17 ｜ R24 行业纵深轮：气体密度温压补偿 1 件 + WetBulb 挂账修复

**新增 1 件 + 修复 1 件**（新件码位 0002_32xx，CC 0x32；修复件码位 2F 系全保留）：

| 组件 | 版本 | 说明 |
|---|---|---|
| `FB_DL_GasDensityComp` | v1.0.0 | 理想气体定律密度温压补偿（rho = p·M/(R·T_K)，介质摩尔质量引脚化自持；复用 FC_DL_AirDensity 域校验骨架，零调用依赖）。终审 PASS：单位约化 p[Pa]·M[kg/mol] / (R·T[K]) → kg/m³ 自洽；轻微留档两条（eIdle 退化相、bReset 注释「上升沿」实为电平） |
| `FC_DL_WetBulbTempCalc` | v1.0.1→**v1.1.0** | **R23 P0 挂账关闭**：γ 量纲错位 + 定点迭代结构性发散 → 二分法重写（区间 [−40, T] 残差 g 单调增、精度 0.05 摄氏度、迭代上限 40 防死锁计数器），引脚契约与码位 2F01/2F02/2F10/2F11/2F12 全保留语义重映射，Magnus-Tetens 内联自洽解除族依赖。终审 PASS：RH=100% 退化根在上界、低压域外 2F10 拒绝、40 次兜底与 11 次理论收敛余量 |

---

## v1.13.0 ｜ 2026-11-17 ｜ R25 R25 新增暖通/洁净室算法 4 件（0x33~0x36 四个 CC 子块） / R25 Batch

**批次**：本轮 20 件中本子库 **4 件**，合计 **1335 行**（全库 20 件 7,097 行，终审修复后 7,174 行）
**码位游标（收口后实测）**：下一 CC 子块 **`0x37`**

| 组件 | 版本 | 一句话功能 / 终审结论 | 来源 |
|---|---|---|---|
| `FB_DL_ParticleCounterStat` | v1.0.0 | 洁净室粒子计数 ISO 14644-1 等级判定（表驱动 + 失采识别） | ROADMAP P1 §253 |
| `FB_DL_CoolingTowerApproachCalc` | v1.0.0 | 冷却塔逼近度计算与加/减风机台数建议（湿球组合调用） | R24 增补池 |
| `FB_DL_DuctStaticReset` | v1.0.0 | 风管静压设定重置（最不利阀位 + 死区 + 限斜率） | ROADMAP P1 §291 |
| `FB_DL_DewpointReset` | v1.0.0 | 冷冻水供水温度按露点重置（露点 + 余量 + 斜率限制） | ROADMAP P1 §293 |

---

## v1.15.0 ｜ 2026-11-18 ｜ R31 刻蚀终点趋势 1 件：1 件

| 组件 | 版本 | 码位起始 |
|---|---|---|
| `FB_DL_EtchEndpointTrend` | v1.0.1（R31 终审修复） | 16#0002_3033 |

> R31 增量行：组件总数 58→**59**（registry 实测口径）；机检 19/19 PASS fail=0；终审抽 5 件（本库 1 件），修 1 处升 v1.0.1（`FB_DL_EtchEndpointTrend`）。

### R33 增量（1.12.0 → 1.13.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_TrackerSolarAngle` | v1.0.0 | 16#02_3_5E |
| `FB_DL_CoolingTowerOpt` | v1.0.0 | 16#02_3_5F |

> R33 增量行：本库 59 → **61**；机检本库新增件全 PASS；码位全窗口独占无冲突（主控实测）。

### R34 增量（1.13.0 → 1.14.0）

| 组件 | 版本 | 码位 |
|---|---|---|
| `FB_DL_RfMatcherTune` | v1.0.0 | 16#02_3_80 |

> R34 增量行：本库 1.13.0 → **62**（registry 实测口径）；机检新增件全 PASS；码位全窗口独占无冲突（主控实测 06_0_80~/03_2_00~/04_0_A0~/02_3_80）。

## v1.15.0 — 2026-11-18（R36）
- +1：`FB_DL_DisturbanceObserver`（02_3_81）。计 63 件。

- **v1.16.0**（2026-11-18，R37 续作）：+ResonanceTrackNotch（16#02_3_82）

## R39（2026-11-19）— +3（FB_DL_FrequencyGenerator / FB_DL_TriangleGenerator / FB_DL_LaminatorPressCtrl）

- 本轮增量已入册（registry v2.31.0），机检全 PASS；详见 CHANGELOG v2.31.0。

## v1.18.0 — 2026-11-19（R41 · 20 新件批次 2/3）
- 新增 4 件：FB_DL_OverrideSelector（高/低选超驰仲裁 + 胜出通道号）/ FB_DL_StepResponseIdent（切线法 K/T/θ 阶跃辨识）/ FB_DL_RatioStationCalc（比值/固定双模式比值站）/ FB_DL_CascadeWindupLink（串级抗饱和联动，引用 FB_DL_PidController 引脚契约不改其接口）；组件总数 70 → 74。
- 码位：段 0002 推进——故障 16#0002_03A3~03AE、信息 16#0002_0489~0494。

### v1.17.0 — 2026-11-19（R43）
- 新增组件 5 件；码位窗口 0386~038A 零冲突。
- 由 v1.16.0 升位，向后兼容（纯新增，无接口破坏）。

## v1.18.0 — 2026-11-19（R44 · 零检索轮）
- 新增 3 件：FB_DL_GainSchedPid（增益调度 PID：分区线性插值参数集 + 过渡加权平滑）/ FB_DL_RelayAutoTune（继电器反馈法自整定，只出 Z-N 公开判据初值不闭环）/ FB_DL_BumplessHandAuto（手/自动无扰切换：双向跟踪 + 切换偏差限幅 + 跟踪失效报警）；组件总数 79 → 82。
- 码位：派单建议窗口 02_3_89~8B，registry 全文口径实测零冲突。
- 向后兼容（纯新增，无接口破坏）。

## v1.19.0 — 2026-11-19（R45）

- R45：+5 新件（KalmanFilter1D / TensionObserver / StictionCompensator / LoopPerfIndex / ThermalRampPredict）｜码位 16#0002_03AF~03B3 / 04B2~04B6


## v1.20.0 — 2026-11-19（R46）

- R46：+4 新件（StribeckFrictionComp / LuenbergerObserver / RlsEstimator / AdaptiveLeadLag）｜零码位硬编码：BOOL+ENUM 出口，码位待主控统一派号｜机检 4/4 PASS
- 向后兼容（纯新增，无接口破坏）。
---

## v1.18.0 — 2026-11-20（R48）

- 新增组件 5 件：FB_DL_SensorFusion2 / FB_DL_BiasAdaptiveTrim / FB_DL_FuzzyTrim2In / FB_DL_Decouple2x2 / FB_DL_GapForceSwitchover
- 子库组件总数：**96**（registry 实测口径）
- 机检：本轮 21/21 PASS（含 FB_DL_ModulePottingVac v1.0.1 轻返修）

## v1.19.0 — 2026-11-20（R49）

- 新增组件 5 件：FB_DL_SignalReconstruct / FB_DL_LoopSignGuard / FB_DL_ExtremumSeekCtrl / FB_DL_LoopCoupleDetect / FB_DL_RulEstimator
- 子库组件总数：**101**（registry 实测口径）
- 机检：本轮 20/20 PASS（增量仅扫本轮新增件）

## v2.42.0（R49 批次入册 · R50 收口，2026-11-20）
- 新增组件 5 件：FB_DL_SignalReconstruct / FB_DL_LoopSignGuard / FB_DL_ExtremumSeekCtrl / FB_DL_LoopCoupleDetect / FB_DL_RulEstimator
- 子库组件总数：**107**（registry v2.42.0 counts 口径）
- 机检 25/25 PASS；R50 终审本子库挂账 2 件（RulEstimator 严重：环窗乱序回归 / ExtremumSeekCtrl 中：相位 2× 因子+累计口径），挂账 R51 返修

## v1.19 — 2026-11-20（R52）
- 变更：+5（ZnTune 临界比例度整定 / AdaptiveDeadbandZone 噪声自适应死区 / DerivativeNoiseWeight 微分降权 / ControlOutputSlewWatch 输出速率监视 / PidParamDriftAudit 参数漂移审计）
- 子库计数：**112 件**（全库 945 / v2.44.0）
- 机检：本子库本轮新增/返修件全部 PASS（audit_r52.py，22/22 全绿）

## v1.20 — 2026-11-20（R53）

- +3：FB_DL_BearingVibTrend / FB_DL_PumpSurgeGuard / FB_DL_SensorDriftBaseline（ISO 10816 三档 / 喘振裕度 / 长时基线漂移）
- 机检：本轮 20/20 PASS（含 4 件 v1.0.1 返修）；JSONL 同步 962 条。

## R54 追加（2026-11-20，子库 v1.21）
- 新增：FB_DL_PidRelayAutoTune / FB_DL_FirstOrderIdent
- 子库存量：117 件

## R55 追加（2026-11-20，子库 v1.22）
- 新增：FB_DL_FopdtStepIdent
- 子库存量：118 件

## v1.23 — 2026-11-21（R56 追加）
- 新增 3 件（TwoDofPid / LossInWeightFeeder / UvDoseCtrl）。
- 子库累计 121 件。
## v1.24 — 2026-11-21（R57 追加）
- 返修：FB_DL_LossInWeightFeeder v1.0.1（安全侧归零三路径）/ FB_DL_TwoDofPid v1.0.1（手动相有限性闸）
- 子库累计 121 件。

## v1.25 — 2026-11-21（R58 追加）
- 3 件（PmvComfortIndex / OptimalStartStop / PeriodicDisturbComp）。
- 子库累计 124 件。

## v1.27 — 2026-11-21（R60 追加）
- 新增 1 件：FB_DL_InputShaperZv（ZV 双脉冲输入整形）
- 子库累计 127 件。

## v1.28 — 2026-11-21（R61 追加）
- 新增 1 件：PidParamGuard（在线参数闸）
- 子库累计 128 件。

## v1.29 — 2026-11-21（R62 追加）
- 新增 1 件：`FB_DL_BiquadFilter`（通用二阶 IIR 直接 I 型节，五系数下发 + 稳定域闸 + 变更沿清状态 + 输出钳位抗 windup；与 LowPass / HighPass / Notch / Fir 四件结构专用件分工声明写死）。
- **已知未关闭（R63 P0）**：段 3 稳定域判据用 `|a2 − a1| < 1` 代替 Jury 下边界 `a2 > |a1| − 1`，(a1 = −1.9, a2 = −0.95) 反例可过闸；本版**不建议用于安全相关回路**，详见 `REVIEW_R62.md` D2。
- 子库累计 129 件。

## v1.30 — 2026-11-21（R63 追加）
- 新增 5 件（族① 二阶/结构滤波族深化，R193 扩面）：`FB_DL_EwmaFilter`（EWMA 统计口径 α 直接入参，域闸 (0,1] 结构早退）、`FC_DL_BiquadCoeff`（低通/高通/带通/陷波四型系数生成，RBJ 类公开公式 clean-room，与 Jury 闸口径一致性声明）、`FB_DL_OutlierFilter`（MAD 野点剔除 + 保持上限 + 真阶跃重基线）、`FB_DL_BiquadCascade`（≤4 节 Direct Form II 级联，逐节 Jury 稳定闸 + 死节豁免 + 系数变更沿全链清零）、`FB_DL_AdaptiveLmsFilter`（LMS 在线权重更新，输入非有限冻结防污染 + `fWEnergy` 发散监视）。
- 返修 1 件：`FB_DL_BiquadFilter` v1.0.0 → **v1.0.1**（R62-D2 严重 / D5 轻：稳定判据换 Jury 三条件 + V2b/V2c 双向向量 + 373A 独立出口表达；R62 挂账全清，恢复可用于安全相关回路）。
- 子库累计 134 件。
## v1.31 — 2026-11-22（R69 追加）
- 新增 1 件：`FB_DL_CascadeCtrl`（串级骨架：三态切换无扰 + 双向抗饱和回投，与既有 FB_DL_CascadePid 分工——本件为通用骨架件，终审裁决保留双件）。

## v1.34 — 2026-11-23（R73）

- 新增/变更：FB_DL_FanSurgeMarginCalc / FC_DL_TcToFilterCoeff / FC_DL_DeadtimeTapCalc + 3 件全回执点修
- L2 编译闸：PASS（RuSTy 1.0.8 串行）

## R76 · v2.68.0 · 2026-11-23
- 新增 6 件（4 迟滞 + 2 限幅），本库累计 **148** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1），审校 12 项扫查 + 三道去重通过。

## R77 · v2.69.0 · 2026-11-23
- 新增 7 件（滤波族 6 + Modbus RTU 帧构造），本库累计 **155** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。

## R79 · v2.71.0 · 2026-11-24
- 新增 校验和族 5 件，本库累计 **161** 件。
- 全部经本地 RuSTy L2 真编译闸 PASS（串行 jobs=1，闸席独立裁决），审校 12 项扫查 + 三道去重通过。
