# ROUND_PLAN_R35 — 阶段一派单（2026-11-18）

> 选题依据：`_REGNAMES_R35.txt`（618 已注册名全量机器去重）+ `ROADMAP.md` 未勾选 183 条（去重后真池 **153 条**）+ `SOURCE_HUNTING_MATRIX.md` §5 台账既有 ◐ 行。
> **WebSearch 配额 0/0（零检索轮）**：全部取 ROADMAP 真池与矩阵既有 ◐ 组语义，来源标签回指既有台账行，不新增外部源。
> **T0 配额如实取 0 件**：真池无 DL_Base/DL_MathData 条目；R34 已裁定 `ShlDwordEx/ShrDwordEx` 同义弃立项，沿用。
> **T2/T1 配额**：14 件带 T2 标签（覆盖 LGF-Technology / LGF-Measurement / LBP / ModPID / ISA-88 / ISA-18.2 / NE107 七族），2 件带 T1 标签（OSCAT Building 暖通语义），满足「≥1 个 T2 组件族或 1 个 T1 组」硬约束。
> **同义弃判沿用**：R34 §5 判弃的 9 条近似项本轮继续排除，不入 20 件。

## 1 目标组件清单（20 件新件）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_TrackerWindStow` | DL_Process | FB | 跟踪支架大风保护收拢（风速阈值 + 趋势判据 → 安全角度命令出口） | `t2-1-lgf-technology` | 中 | 1 |
| 2 | `FB_DL_LaminatorTempProfile` | DL_Process | FB | 层压机多温区升温/保温/降温配方曲线跟随（复用 `FB_DL_RampSoakProfile`） | `t2-1-lgf-technology` | 高 | 1 |
| 3 | `FB_DL_StringerTrend` | DL_Process | FB | 串焊机多通道焊接温度曲线在线监视（峰值窗 + 逐通道分级告警） | `t2-1-lgf-measurement` | 中 | 1 |
| 4 | `FB_DL_PottingDispenseCtrl` | DL_Process | FB | 接线盒灌胶定量（称重减量法 + 双组份混合比闭环 + 混合比偏差窗） | `t2-2-lbp` | 中 | 1 |
| 5 | `FB_DL_PileClampCtrl` | DL_Process | FB | 堆叠压紧板预压/全压两段压力-位移控制（复用 `FB_DL_StepSequencer` + `I_DL_Cylinder`） | `t2-2-lbp` | 中 | 1 |
| 6 | `FB_DL_CvdTempRamp` | DL_Process | FB | CVD/扩散炉多段 Ramp/Soak 曲线跟随 + 均匀性判据（复用 `FB_DL_RampSoakProfile`） | `t2-1-lgf-technology` | 高 | 2 |
| 7 | `FB_DL_AnalyzerSampleSeq` | DL_Process | FB | 在线分析仪取样-吹扫-标定三态轮换顺控（相超时升级 + 标定过期锁存） | `t2-8-isa88` | 中 | 2 |
| 8 | `FB_DL_SteamHeaderSplit` | DL_Process | FB | 蒸汽母管多支路分程分配（按支路优先级映射，复用 `FB_DL_SplitRangeControl`） | `t2-5-modpid` | 中 | 2 |
| 9 | `FB_DL_HydronicDeltaTGuard` | DL_Process | FB | 水系统大/小温差失衡诊断（供回水温差带 + 旁通泄漏判据） | `t1-2-oscat-building` | 中 | 2 |
| 10 | `FB_DL_ChillerApproachTrend` | DL_Process | FB | 冷机逼近度趋势诊断与性能衰减预警（复用 `FB_DL_SignalStatistics`） | `t1-2-oscat-building` | 中 | 2 |
| 11 | `FB_DL_PlatingCurrentCtrl` | DL_Process | FB | 电镀槽位电流密度闭环与液位联锁（面积换算 + 液位禁投 + 密度超窗分级） | `t2-2-lbp` | 高 | 3 |
| 12 | `FB_DL_FiringFurnaceZone` | DL_Process | FB | 烧结炉多温区峰值温度跟随（与链速联动的前馈重置 + 峰值窗判定） | `t2-1-lgf-technology` | 高 | 3 |
| 13 | `FB_DL_ChamberGateValve` | DL_Device | FB | 腔体闸阀双位置互锁驱动（开/关到位双反馈 + 抽气侧联锁，复用 `I_DL_MotorizedValve`） | `t2-2-lbp` | 中 | 3 |
| 14 | `FB_DL_GloveBoxAtmoCtrl` | DL_Device | FB | 手套箱气氛联锁（水氧含量越限禁开门 + 净化循环请求，复用 `FB_DL_InterlockMatrix`） | `t2-8-ne107` | 中 | 3 |
| 15 | `FB_DL_ProcessKitTimer` | DL_Device | FB | 腔体部件保养计时器（累计工艺拍数/时长双口径 + 保养到期锁存） | `t2-8-isa88` | 中 | 3 |
| 16 | `FB_DL_ExhaustDpTrend` | DL_Device | FB | 尾气管路压差趋势监视与堵塞预警（复用 `FB_DL_SignalStatistics`） | `t2-1-lgf-measurement` | 中 | 4 |
| 17 | `FB_DL_BypassValveTrim` | DL_Device | FB | 旁通阀供回水压差 PI 微调（复用 `FB_DL_PidController`，阀位死区与限幅） | `t2-5-modpid` | 中 | 4 |
| 18 | `FB_DL_CaseSealTapeMonitor` | DL_Device | FB | 封箱胶带缺料/断带监视（张力 + 光电双判据，复用 `FB_DL_SignalDebounce`） | `t2-8-isa182` | 中 | 4 |
| 19 | `FB_DL_InvInsulTestSeq` | DL_Process | FB | 逆变器绝缘测试加压-保持-泄放联锁顺控（复用 `FB_DL_InterlockMatrix`） | `t2-8-isa88` | 中 | 4 |
| 20 | `FB_DL_ForelinePressureCtrl` | DL_Process | FB | 真空前级管路压力稳定（调节阀位 PI + 抽速前馈 + 压力越窗分级） | `t2-5-modpid` | 中 | 4 |

**分布**：DL_Process 14 ｜ DL_Device 6 ｜ DL_Motion 0 ｜ DL_Algo 0 ｜ DL_MathData 0 ｜ DL_Base 0（真池无后四类条目，按「宁少勿滥」不跨池改判凑数）。T0 0 件，T2 标签 14 件，T1 标签 2 件。

## 2 码位分配表（自 R34 收口游标续接：Process `06_0` 续 8C、Device `03_2` 续 05，实测无占用冲突）

| 序号 | 组件名 | 码位 |
|---|---|---|
| 1 | `FB_DL_TrackerWindStow` | `16#06_0_8C` |
| 2 | `FB_DL_LaminatorTempProfile` | `16#06_0_8D` |
| 3 | `FB_DL_StringerTrend` | `16#06_0_8E` |
| 4 | `FB_DL_PottingDispenseCtrl` | `16#06_0_8F` |
| 5 | `FB_DL_PileClampCtrl` | `16#06_0_90` |
| 6 | `FB_DL_CvdTempRamp` | `16#06_0_91` |
| 7 | `FB_DL_AnalyzerSampleSeq` | `16#06_0_92` |
| 8 | `FB_DL_SteamHeaderSplit` | `16#06_0_93` |
| 9 | `FB_DL_HydronicDeltaTGuard` | `16#06_0_94` |
| 10 | `FB_DL_ChillerApproachTrend` | `16#06_0_95` |
| 11 | `FB_DL_PlatingCurrentCtrl` | `16#06_0_96` |
| 12 | `FB_DL_FiringFurnaceZone` | `16#06_0_97` |
| 13 | `FB_DL_ChamberGateValve` | `16#03_2_05` |
| 14 | `FB_DL_GloveBoxAtmoCtrl` | `16#03_2_06` |
| 15 | `FB_DL_ProcessKitTimer` | `16#03_2_07` |
| 16 | `FB_DL_ExhaustDpTrend` | `16#03_2_08` |
| 17 | `FB_DL_BypassValveTrim` | `16#03_2_09` |
| 18 | `FB_DL_CaseSealTapeMonitor` | `16#03_2_0A` |
| 19 | `FB_DL_InvInsulTestSeq` | `16#06_0_98` |
| 20 | `FB_DL_ForelinePressureCtrl` | `16#06_0_99` |

> 窗口占用明细（实测脚本扫描 INDEX_REGISTRY.json v2.26.0）：DL_Process `16#06_0_8C`~`16#06_0_99`（14/36 格，续 R34 至 8B）；DL_Device `16#03_2_05`~`16#03_2_0A`（6/16 格，续 R34 至 04）；DL_Motion / DL_Algo / DL_MathData / DL_Base 本轮 **0 件不动**。信息级/故障级细分由编码专家按组件内判据数量在单格窗口内顺排（同 R34 惯例，单件多码在格内 +0x01 递增，不得跨入下一件格）。

## 3 批次切分（4 批 × 5 件，按依赖与同族聚拢，批 1 最独立）

| 批次 | 序号 —— 组件名 | 批内复用依赖（均为已注册件，禁跨批新增依赖） |
|---|---|---|
| **批 1** | 1 `TrackerWindStow` ｜ 2 `LaminatorTempProfile` ｜ 3 `StringerTrend` ｜ 4 `PottingDispenseCtrl` ｜ 5 `PileClampCtrl` | `FB_DL_RampSoakProfile` / `FB_DL_SignalStatistics` / `FB_DL_Differentiator` / `FB_DL_StepSequencer` / `I_DL_Cylinder` / `FB_DL_ToleranceWindow` / `FB_DL_AlarmManager` |
| **批 2** | 6 `CvdTempRamp` ｜ 7 `AnalyzerSampleSeq` ｜ 8 `SteamHeaderSplit` ｜ 9 `HydronicDeltaTGuard` ｜ 10 `ChillerApproachTrend` | `FB_DL_RampSoakProfile` / `FB_DL_StepSequencer` / `FB_DL_SplitRangeControl` / `FB_DL_Differentiator` / `FB_DL_SignalStatistics` / `FB_DL_Hysteresis` |
| **批 3** | 11 `PlatingCurrentCtrl` ｜ 12 `FiringFurnaceZone` ｜ 13 `ChamberGateValve` ｜ 14 `GloveBoxAtmoCtrl` ｜ 15 `ProcessKitTimer` | `FB_DL_PidController` / `FB_DL_InterlockMatrix` / `I_DL_MotorizedValve` / `FB_DL_RuntimeMeter` / `FC_DL_LimitClassify` / `FB_DL_RateLimiter` |
| **批 4** | 16 `ExhaustDpTrend` ｜ 17 `BypassValveTrim` ｜ 18 `CaseSealTapeMonitor` ｜ 19 `InvInsulTestSeq` ｜ 20 `ForelinePressureCtrl` | `FB_DL_SignalStatistics` / `FB_DL_PidController` / `FB_DL_SignalDebounce` / `FB_DL_InterlockMatrix` / `FB_DL_HighPassFilter` / `FB_DL_TimeWindowCheck` |

## 4 P0 口径：结构化语法核验（编译验证债连欠 30 轮，本轮降级口径）

对 20 个新件逐件执行以下 5 项结构化核验，主控按此执行脚本，**任一项失败即判该件不合格，不得进入终审**：

1. **POU/END 成对**：`FUNCTION_BLOCK ... END_FUNCTION_BLOCK` / `FUNCTION ... END_FUNCTION` 成对且各恰好 1 次；
2. **VAR 块开闭配对**：`VAR_INPUT` / `VAR_OUTPUT` / `VAR_IN_OUT` / `VAR` 各自与 `END_VAR` 数量相等，且声明区内无孤行；
3. **结构语句配对**：`IF`/`END_IF`、`CASE`/`END_CASE`、`FOR`/`END_FOR`、`WHILE`/`END_WHILE` 计数相等（按词法 token 计，排除注释与字符串字面量内的关键词）；
4. **枚举引用先声明**：文件内引用的 `E_DL_*` 枚举类型与成员须在本文 `TYPE ... END_TYPE` 内声明，或为库内既有属主（`E_DL_Ne107Status` 等唯一属主件），引用未声明枚举即失败；
5. **分号/括号平衡**：语句分号配平、圆括号 `(` `)` 计数相等（同样排除注释与字符串）。

> 本口径为「结构化核验」非「语义编译」，不承诺平台编译通过；编译债另行排程（R195 闸门），不得以本核验冒充编译验证入账。

## 5 每批需求规格（编码专家任务书）

### 批 1（最独立）

| # | 规格 |
|---|---|
| 1 | **`FB_DL_TrackerWindStow`**（DL_Process/FB）：输入风速 `fWindSpeed`（m/s）及其 10 min 滑动最大值、当前角度 `fAngle`（°）；输出收拢命令 `bStowCmd`、安全角度 `fStowAngle`（°，组态输入）、状态枚举。功能：风速 ≥ 高阈值（带迟滞）或趋势判据（`FB_DL_Differentiator` 风速爬升率超限）持续 N 拍 → 置收拢命令；风速回落后带解除迟滞与最短驻留方可解除。边界：风速非有限或 <0 判无效冻结输出并置码；高/低阈值倒置出厂报码不运行；解除路径必须自证可达（FB33-2）；安全角度钳位到行程域；趋势窗样本数不足不出趋势结论。来源 `t2-1-lgf-technology`。 |
| 2 | **`FB_DL_LaminatorTempProfile`**（DL_Process/FB）：输入段表（升温/保温/降温三段 × 各温区目标 °C、斜率 K/min、保持时间 s）、各温区实测温度；输出段序号、段内进度、`bProfileDone`、`bHoldActive`。复用 `FB_DL_RampSoakProfile` 多实例按温区展开。边界：段表长度 0 或段参数非法（斜率 ≤0、时长 ≤0）出厂报码；实测温度 NE43 无效时该温区冻结判定并置码，禁塞伪值；段切换沿冻结一拍防设定阶跃；超时未达窗升级为段故障而非死等；`bProfileDone` 仅在全部温区过终点窗时置位。来源 `t2-1-lgf-technology`。 |
| 3 | **`FB_DL_StringerTrend`**（DL_Process/FB）：输入 n 通道焊接温度（°C，数组）、链速（mm/s）；输出逐通道峰值窗口判定（OK/偏高/偏低）、首异常通道号、`bBatchOk`。用 `FB_DL_SignalStatistics` 逐通道统计。边界：通道数 <2 不出统计结论；任一通道无效从统计剔除并在掩码标出；链速为 0 时峰值窗不外推、保持上次窗并置 `bHold`；分档边界按 R28 终审二式推「正好整除」与「上限+1」两条向量；告警出口走 `FB_DL_AlarmManager` 分级。来源 `t2-1-lgf-measurement`。 |
| 4 | **`FB_DL_PottingDispenseCtrl`**（DL_Process/FB）：输入目标重量（g）、A/B 组份实时称重、混合比设定；输出计量泵使能、A/B 比例输出、`bDoseDone`、实际灌注重量。减量法：计量 = 灌注前后称重差。边界：称重无效（NE43）时冻结计量并禁止使能；混合比偏差窗上下限倒置出厂报码；灌注中称重回升（回流/抖动）需去抖确认，禁单拍判完成；目标重量 ≤0 拒启动并置码；双组份任一超窗先停 A 侧（安全侧）。来源 `t2-2-lbp`。 |
| 5 | **`FB_DL_PileClampCtrl`**（DL_Process/FB）：输入压紧压力（kN）、位移（mm）、目标压力两段设定；输出缸命令（复用 `I_DL_Cylinder` + `FB_DL_StepSequencer`）、段状态、`bClampDone`、包络越窗码。边界：预压未达窗禁进全压段；压力/位移任一无效冻结并保持当前段；包络窗口上下限倒置出厂报码；保压计时用独立 TON 且 `IN := NOT ton.Q` 自复位（FB33-2）；释压命令与压紧命令互斥，同拍双真取释压（安全侧）。来源 `t2-2-lbp`。 |

### 批 2

| # | 规格 |
|---|---|
| 6 | **`FB_DL_CvdTempRamp`**（DL_Process/FB）：输入多段 Ramp/Soak 工艺曲线（目标 °C、K/min、Soak 时长 s）、多温区实测；输出段跟随状态、`bSoakInWindow`、均匀性结论（复用 `FB_DL_RampSoakProfile` + `FB_DL_SignalStatistics`）。边界：均匀性测点 <2 不出结论；任一温区无效冻结该区判定并置码；Ramp 段斜率与实测温差偏离超限判跟随失败升级；Soak 终点窗带独立超时出口；与 `FB_DL_LaminatorTempProfile` 的职责边界（行业参数集差异）在头注释写明。来源 `t2-1-lgf-technology`。 |
| 7 | **`FB_DL_AnalyzerSampleSeq`**（DL_Process/FB）：输入取样/吹扫/标定三命令与各相反馈；输出当前相、`bSampleValid`、标定过期锁存。复用 `FB_DL_StepSequencer` 三态轮换。边界：相切换须先完成当前相（禁打断取样）；每相超时独立 TON 升级而非死等；标定过期时禁取样出口有效（联锁前置）；吹扫计时分段自复位（FB33-2）；三命令同拍多真按 标定>吹扫>取样 优先级仲裁并置信息码。来源 `t2-8-isa88`。 |
| 8 | **`FB_DL_SteamHeaderSplit`**（DL_Process/FB）：输入母管压力（MPa）、n 支路阀位输出域与优先级表；输出逐支路分程阀位（%）。复用 `FB_DL_SplitRangeControl` 多实例。边界：支路数为 0 拒运行；优先级重复出厂报码；母管压力无效时全支路回安全位并冻结；分程区间必须无缝覆盖且不重叠（重叠/空洞出厂报码）；阀位输出钳到各支路行程域。来源 `t2-5-modpid`。 |
| 9 | **`FB_DL_HydronicDeltaTGuard`**（DL_Process/FB）：输入供/回水温度（°C）、旁通阀位（%）；输出温差失衡分级（大温差/小温差/正常）、旁通泄漏判据、诊断码。边界：两温度任一无效冻结判定保持上次输出；温差 = 0 邻域（|ΔT|<0.5 K）判「无有效流量」而非除零算比率；大/小温差判据带迟滞防抖；旁通开度大且温差小持续 N 分钟才判泄漏（确认窗）；失衡解除路径自证可达（FB33-2）。来源 `t1-2-oscat-building`。 |
| 10 | **`FB_DL_ChillerApproachTrend`**（DL_Process/FB）：输入蒸发器出水温度、饱和蒸发温度（°C）；输出逼近度（K）、滑动趋势（K/天）、衰减预警。复用 `FB_DL_SignalStatistics`。边界：逼近度计算分母（换热量代理量）近零时改绝对差判据；负荷率低于下限时冻结趋势累计并置 `bFrozen`（禁低负荷数据污染趋势）；趋势窗样本 <最小值不出结论；预警阈值带迟滞且解除可达。来源 `t1-2-oscat-building`。 |

### 批 3

| # | 规格 |
|---|---|
| 11 | **`FB_DL_PlatingCurrentCtrl`**（DL_Process/FB）：输入目标电流密度（A/dm²）、槽液位、可镀面积（dm²）、整流器回读电流（A）；输出电流设定、`bPlatingOk`、联锁出口。边界：面积 ≤0 拒算（除零前置）；液位低于下限禁投并保持（联锁可解除）；回读与设定偏差持续超窗分级告警；面积换算结果钳到整流器量程域；液位信号无效按低液位安全侧处理（R42 家族）。来源 `t2-2-lbp`。 |
| 12 | **`FB_DL_FiringFurnaceZone`**（DL_Process/FB）：输入链速（mm/s）、各温区实测/目标峰值（°C）；输出各区设定、峰值窗判定、前馈重置量。边界：链速为 0 用最后有效链速并置 `bHold`，禁外推；前馈系数与链速量纲配比在头注释写死；峰值窗判定需多拍确认；区无效冻结该区；重置量限幅防阶跃。来源 `t2-1-lgf-technology`。 |
| 13 | **`FB_DL_ChamberGateValve`**（DL_Device/FB）：输入开/关到位双反馈、抽气侧联锁条件；输出阀驱动（复用 `I_DL_MotorizedValve`）、`bGateOpen`、矛盾码。边界：双到位同时为真判反馈矛盾锁存；联锁条件为假禁开阀；驱动超时（行程时间 ×1.5）升级故障；反馈无效按「阀未在位」安全侧处理；故障解除条件可达（联锁恢复 + 矛盾消失 + 复位沿）。来源 `t2-2-lbp`。 |
| 14 | **`FB_DL_GloveBoxAtmoCtrl`**（DL_Device/FB）：输入水/氧含量（ppm）双路、舱门请求；输出开门许可、净化循环请求、NE107 出口（复用 `E_DL_Ne107Status` 唯一属主）。边界：任一路无效按「越限」安全侧禁开门；门限带迟滞防反复禁投；净化请求与开门互斥仲裁；越限解除须双路均回窗 + 最短维持时间（FB33-2 可达）；未知状态归 `eUnknown` 不归 `eOk`。来源 `t2-8-ne107`。 |
| 15 | **`FB_DL_ProcessKitTimer`**（DL_Device/FB）：输入工艺拍计数脉冲、运行时长使能、保养阈值（拍/小时双口径）；输出累计值、`bMaintDue`、复位请求确认。复用 `FB_DL_RuntimeMeter`。边界：双阈值任一到即锁存 `bMaintDue`，解除必须经显式复位且运行中禁复位；计数饱和不回绕；时长口径暂停不累计（与 `FB_DL_BatchPhaseBase` 暂停语义一致）；阈值 0 表示禁用该口径（语义写进头注释）。来源 `t2-8-isa88`。 |

### 批 4

| # | 规格 |
|---|---|
| 16 | **`FB_DL_ExhaustDpTrend`**（DL_Device/FB）：输入尾气前后压差（kPa）、风机状态；输出滑动趋势（kPa/天）、堵塞预警分级、`bClogWarn`。复用 `FB_DL_SignalStatistics`。边界：风机停机时冻结趋势累计（禁把停机零流量当堵塞）；压差无效剔除并置掩码；趋势窗样本不足不出结论；预警阈值带迟滞且解除可达。来源 `t2-1-lgf-measurement`。 |
| 17 | **`FB_DL_BypassValveTrim`**（DL_Device/FB）：输入供/回水压差（kPa）、压差设定；输出旁通阀位微调（%）。复用 `FB_DL_PidController`。边界：两压力任一无效冻结输出保持末次阀位；阀位输出钳行程域并置饱和码；死区带宽非法（≤0 或倒置）出厂报码；PID 参数 Ti/Td=0 按「关闭」语义不判非法（T2-5 参数域惯例）；压差传感器量程 0 邻域防除零。来源 `t2-5-modpid`。 |
| 18 | **`FB_DL_CaseSealTapeMonitor`**（DL_Device/FB）：输入胶带张力（N）、光电传感、封箱节拍使能；输出缺料/断带判别、报警出口。复用 `FB_DL_SignalDebounce` 去抖。边界：节拍使能时连续 N 拍无张力 + 光电同态才判断带（防单拍尖峰）；张力传感器无效冻结判定并置码；缺料与断带独立码值（FB33-3 归因唯一）；报警解除需补料确认 + 复位沿。来源 `t2-8-isa182`。 |
| 19 | **`FB_DL_InvInsulTestSeq`**（DL_Process/FB）：输入测试电压命令、保持计时、泄放反馈；输出加压/保持/泄放三态顺控、`bTestOk`、联锁出口（复用 `FB_DL_InterlockMatrix`）。边界：泄放未确认前禁放行下工序（安全侧默认）；加压中急停立即转泄放相；各相超时独立 TON；测试电压反馈无效判「不可判」而非 OK；相完成仅在泄放反馈确认后置位。来源 `t2-8-isa88`。 |
| 20 | **`FB_DL_ForelinePressureCtrl`**（DL_Process/FB）：输入前级压力（Pa）、设定（Pa）、调节阀反馈；输出阀位 PI + 抽速前馈（%）。边界：压力无效冻结输出；设定低于量程下限钳定并置码；阀位饱和与 PI 抗饱和联动（限幅反算）；前馈通道指令非有限拒绝保持末次有效（`FB_DL_SuperimposedMove` 同范式）；越窗分级带迟滞。来源 `t2-5-modpid`。 |

## 6 选题纪律自证

1. **零撞名**：20 件逐一对照 `_REGNAMES_R35.txt`（618 名）机器去重，0 命中；跨子库同名已排除。
2. **同义邻件双查**：R34 §5 判弃 9 条（`AhuEconomizer` / `VavDischargeAirReset` / `HeatExchangerFoulingTrend` / `ChamberPumpDownSeq` / `SteamTrapSurvey` / `FormationChannelQueue` / `CellOcvBinSort` / `ElectrodeGapMark` / `ChwDifferentialPressureReset`）本轮沿用弃判不入池；本轮 20 件与存量件职责边界已逐件在规格中写明（如 6 与 R34 件 2 同用 RampSoakProfile 但行业参数集与均匀性判据分立）。
3. **不用它会怎样**：逐件在 §5 规格「一句话功能」+ 边界中体现工程后果，无凑数变体。
4. **零检索**：WebSearch 0 次；来源标签全部回指 SOURCE_HUNTING_MATRIX.md §5 既有 ◐ 行，收尾时按 R34 式回写台账，状态列均不动（无 ☐→◐ 开组、无 ◐→✔ 收口）。

## 7 异常与报备

- **分布偏科如实报备**：真池 153 条仅含 DL_Process(120)/DL_Device(33) 两类标注，本轮 14+6 分布属实池现状；Motion/Algo/MathData/Base 0 件，不跨池造件。
- **真池余量**：本轮取 20 条，余 133 条留 R36+。
- **编码侧提醒**：FB33-1（CASE 后 5 行不得无条件清零）/ FB33-2（TON 自复位与锁存解除可达）/ FB33-3（归因唯一）三项判据全批适用；`E_DL_Ne107Status` 等既有属主枚举只引用不重复声明（对应 §4-4 核验项）。
