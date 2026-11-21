# ROUND_PLAN_R54 — R54 轮规划（无人值守，2026-11-20）

- 轮次：R54 ｜ 性质：规划轮（只写本文件 + REVIEW_R54 + RAW_NOTES_R54，零编码 / 零 registry / 零已存在文档改动）
- 预算：新增组件规划 16 件（四批 × 4）；T0 快车道余量 0（八组全收口），本轮不取 T0
- 品类配额上限：DL_MathData ≤2 / DL_Process ≤4 / DL_Algo ≤4 / DL_Base·Device·Motion 自由
- 来源纪律：零 WebSearch（0/3）；全部取 ROADMAP 未注册项 + 源矩阵 ◐ 待挖子族 + 现场真实工况缺口（复用 RAW_NOTES R39~R53）
- 撞名纪律：R214 三查（registry 961 名 ∪ ROADMAP 全文 ∪ DL_* 文件树）逐件执行，核验痕迹见第四节

## 一、16 件新组件目标

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度(1-6) | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_BitArrayMultiSegMove | DL_Base | FB_DL_ | 位数组多段一次搬：单遍遍历完成段表（起位+宽度数组）跨字批量搬移，段间重叠预检 | lgf-bitlogic ◐（LWORD/多段一次搬待挖） | 4 | 1 |
| 2 | FC_DL_ChecksumLwordSum | DL_MathData | FC_DL_ | 64 位字累加和校验：LWORD 数组按模 2^64 回卷累加，与预置校验值比对出结论 | lgf-datahandling ◐（校验族余 LWORD 累加和） | 2 | 1 |
| 3 | FB_DL_HealthStatusArbiter | DL_Device | FB_DL_ | 多源 NE107 健康仲裁聚合：N 路健康枚举按编号即优先级最差胜出，聚合出口单一健康态 | t2-8 NE107/ISA-18.2 ◐（多源聚合待挖） | 4 | 1 |
| 4 | FB_DL_PrbsSignal | DL_Base | FB_DL_ | PRBS 伪随机二进序列激励发生（LFSR 整数实现），供回路辨识/继电器整定的持续激励源 | oscat-basic ◐/自研（PRBS 行为定义） | 2 | 1 |
| 5 | FB_DL_PidRelayAutoTune | DL_Algo | FB_DL_ | 继电器反馈自整定：强制振荡测极限周期/幅值，按 Åström-Hägglund 公开公式给 PID 初值 | 自研-公开方法（relay-tuning 公开公式） | 5 | 2 |
| 6 | FB_DL_HistogramBinTally | DL_MathData | FB_DL_ | 分箱直方图累计：等宽 bins 样本落格计数 + 越界钳边计数 + 占比出口 | lgf-measurement ◐（统计族扩） | 3 | 2 |
| 7 | FB_DL_PnDiagAlarmDecode | DL_Device | FB_DL_ | PROFINET 诊断告警语义解码：借 PN_ALARM_DIAG 公开位语义出中文诊断名+严重度+可重试性 | plcnext-community ◐（PN_ALARM_DIAG 待挖） | 4 | 2 |
| 8 | FB_DL_SweepFreqGen | DL_Base | FB_DL_ | 频率扫描激励发生：线性/对数扫频两模式，起止频率+驻留时间表驱动，与 PulseGenerator 职责分立 | lgf-siggen ◐（频率发生族待挖） | 3 | 2 |
| 9 | FB_DL_FirstOrderIdent | DL_Algo | FB_DL_ | 一阶加纯滞后（FOPDT）阶跃响应回归：阶跃前后三点法估 K/T/θ，供自整定与 Smith 补偿取参 | 自研（与 4/5/8 号激励源配套） | 4 | 3 |
| 10 | FB_DL_CamTableLiveTrim | DL_Motion | FB_DL_ | 凸轮表运行中动态修调：相位点增量修调经斜坡平滑注入，单调性随改随验防表破坏 | plcopen-motion ◐（凸轮动态修调待挖） | 4 | 3 |
| 11 | FB_DL_NightFlushPurge | DL_Process | FB_DL_ | HVAC 夜间吹扫编排：低温窗+风机允许双闸进入吹扫相，温降达标或超时退出，复用日历窗件 | oscat-building ◐（夜间吹扫待挖） | 3 | 3 |
| 12 | FB_DL_AirCompressorLoadUnload | DL_Device | FB_DL_ | 空压机加卸载调压：压力带双阈加卸载迟滞 + 卸载超时排空联锁 + 加载最小驻留 | lbp-basic-process ◐/行业池 | 3 | 3 |
| 13 | FB_DL_RecipeSwitchHandover | DL_Process | FB_DL_ | 配方切换交接编排：旧配方排空确认→参数装载复核→新配方放行三相，ISA-88 相语义衔接 | packml/isa88 ◐（配方切换/批次编排待挖） | 4 | 4 |
| 14 | FB_DL_EnthalpyPrioritySwitch | DL_Process | FB_DL_ | 焓值优先切换：新风/回风焓差判据经迟滞带切换经济器模式，与 R6 焓差判据件职责分立（切换 vs 判定） | oscat-building ◐（焓值优先切换待挖） | 3 | 4 |
| 15 | FB_DL_TankAgitationSeq | DL_Process | FB_DL_ | 搅拌槽搅拌时序：低速分散→高速搅拌→维持计时三相，液位低禁高速、扭矩过载降速回退 | isa88 ◐（相语义扩族） | 3 | 4 |
| 16 | FB_DL_AxisTorqueRippleWatch | DL_Motion | FB_DL_ | 轴转矩纹波监视：匀速段转矩波动幅度/周期性判据，识别机械卡滞与联轴器异常 | plcopen-motion ◐/自研 | 3 | 4 |

配额核对：MathData 2≤2 ✓ / Process 4≤4 ✓ / Algo 2≤4 ✓ / Base 3 / Device 3 / Motion 2，合计 16 ✓。
四批分布：批1 = Base1/MathData1/Device1/Base1；批2 = Algo1/MathData1/Device1/Base1；批3 = Algo1/Motion1/Process1/Device1；批4 = Process3/Motion1 ✓ 批内按序号 1→4。

## 二、边界安全条件（每件 3~5 条，编码专家照做）

1. **BitArrayMultiSegMove**：① 段宽 > 64 → 锁故障（拒绝拆半字搬）；② 段间重叠（前段尾 >= 后段起）→ 预检整表一次拒，不搬半截；③ 移位量一律 MOD 32 + 宽 64 走常量掩码，全程无 64 位移位；④ 段数 0 = 幂等直通不置错；⑤ 读写只经 VAR_IN_OUT 数组，零全局。
2. **ChecksumLwordSum**：① 空数组 → bValid=FALSE 哨兵，不返回 0 当有效和；② 回卷累加用条件加减法禁 MOD（回绕归一 R55 教训）；③ 有限数组长度上限常量守卫防 WHILE 死循环；④ 预置校验值比对用位等（整数，无浮点判等）。
3. **HealthStatusArbiter**：① N 路越界钳 NMAX；② 最差态 = 编号最大（eFailure 最大），编号即优先级逐件直比；③ 单路未知 eUnknown 不抬高也不拉低聚合结论（语义：仅已知源参与仲裁，全未知出 eUnknown）；④ 仲裁为纯组合重算（无锁存），每拍全量重判防陈旧；⑤ 出口与 I_DL_DeviceHealth 六态契约同源不重造枚举。
4. **PrbsSignal**：① 抽头多项式合法域校验（阶数 4..31）越域锁故障；② LFSR 全零态检测：遇全零强制注入 1（防死序列）；③ 使能撤除保持相位，重使能不重启序列（bRestart 显式引脚才重启）；④ 输出脉冲宽度以扫描周期为时基，tBit 钳位下限 ≥ 2 周期；⑤ 种子 0 视为非法（与全零态同源）。
5. **PidRelayAutoTune**：① 迟滞带宽/激励幅值/采样周期三重正域闸锁故障；② 振荡周期测量须 ≥ 3 个完整周期才出参数（防半波截断算错 Tu）；③ 出口 PID 初值域钳位（Kp>0、Ti>0、Td≥0），发散（幅值不收敛或周期不稳定）→ bValid=FALSE 不出参数；④ 整定中不写控制输出，只观测（属主边界，防误动作）；⑤ 非有限测量该拍不入振荡检测。
6. **HistogramBinTally**：① bins 数域 2..64，bin 宽 > 0 否则锁故障；② 落格下标由边界值直比算出（不用除法），越下界钳第 1 格、越上界钳末格同时 bClampLow/High 计数出口；③ 非有限样本拒收不入格（bSampleRej）；④ 复位沿幂等清零（计数出口与内部计数器同拍同步）；⑤ 占比除子 = 总入格数，0 时占比出口全 0 不除。
7. **PnDiagAlarmDecode**：① 告警码查表线性扫描带计数上限守卫；② 未知码出「未归类」条目不置 bError（信息级，NE107 eOutOfSpec 口径）；③ 严重度三档（停机/维护/信息）枚举出口，停机档才置 bAlarm；④ 码表为常量数组（零魔法数散布）；⑤ 诊断文本定宽字段走 R37 四步样板（截断先置标志）。
8. **SweepFreqGen**：① 起/止频率正域且不等否则锁故障（相等退化为点频不立）；② 对数扫频禁 log(0)：起频下限 > 0 已由正域闸保证；③ 相位积分逐拍累加防跳频突跳，相位回卷 2π 用条件加减；④ 使能撤除相位保持不归零，bRestart 显式重启；⑤ 驻留表数组越界钳位 + 非有限频率冻结保持。
9. **FirstOrderIdent**：① 阶跃幅值/采样周期正域闸；② 辨识窗须含阶跃前稳态 ≥ N 拍与阶跃后达 63.2%/86.5% 两特征点，缺任一 → bValid=FALSE；③ 三点法公式全代数（无迭代无除零：分母为阶跃幅值，已过正域闸）；④ 非有限测量该拍不入辨识窗（窗计数暂停非快进）；⑤ 输出 K/T/θ 非负域钳位，θ 上限 = 辨识窗长（防无滞后误设大滞后）。
10. **CamTableLiveTrim**：① 修调注入只允许 eRun 相且主轴在相位点 ± 容差窗内（相位闸）；② 修调后表值单调性随改随验，破坏单调立即回滚本点并置 bError（锁存至复位）；③ 修调量饱和上限防累计漂移；④ 斜坡平滑步长 × 周期秒值，非有限修调该拍不注入；⑤ 表经 VAR_IN_OUT 注入，内部零副本（防两份表失同步）。
11. **NightFlushPurge**：① 进入闸 = 日历窗内 AND 风机允许 AND 室外温 < 室内温-Δ（三闸同拍成立）；② 吹扫相 TON 断输入归零（R40 家族）；③ 温降达标判定用差值迟滞防边界抖动；④ 液位/温度传感器失效 → 降级退出吹扫（安全侧）不维持；⑤ 超时退出后冷却驻留窗防夜间反复启停（最小间隔计时）。
12. **AirCompressorLoadUnload**：① 压力带组态闸：加载阈 < 卸载阈否则锁故障；② 双阈迟滞直比（禁浮点等值）；③ 卸载超时排空联锁：卸载持续 > tUnloadMax → 置维护级告警（不自动停机，属主边界）；④ 加载最小驻留防短周期振荡（驻留期内卸载请求暂存不丢）；⑤ 压力传感器非有限 → 保持当前负载态 + bSensorBad 出口。
13. **RecipeSwitchHandover**：① 三相（排空确认/装载复核/放行）各相 TON 断输入归零 + 相超时独立锁故障码（R40/R44）；② 装载复核 = 参数集校验和比对（整数直比），不符不放行不半装载；③ 切换中收到中止命令 → 当前相边界停下（不回滚已装载段，声明状态可查）；④ 放行前复核旧配方累计量已清零（幂等）；⑤ 命令优先级：中止 > 放行 > 装载，低优先直接丢弃不排队。
14. **EnthalpyPrioritySwitch**：① 焓差迟滞带双阈组态闸（切换阈 > 返回阈）；② 切换须满足判据持续 tHold 驻留才生效（防高频抖动）；③ 任一温度/湿度非有限 → 保持当前模式 + bSensorBad（不切换到未知工况）；④ 最小驻留时间双侧对称（新模式下同样不可立即切回）；⑤ 与 R6 EnthalpyCompareCtrl 分工：本件输出模式枚举，不做焓差报警（职责不重叠）。
15. **TankAgitationSeq**：① 液位低 → 禁止高速相（联锁，高速已运行则降速回退相）；② 扭矩过载判据持续确认（TON）才降速，瞬时尖峰不误动；③ 三相 TON 段 0 无条件刷新 + 相位闸（R40）；④ 降速回退相与故障相分离：回退可恢复，故障锁存至复位；⑤ 转速设定斜坡逼近防机械冲击，非有限扭矩该拍不判。
16. **AxisTorqueRippleWatch**：① 只在匀速段（|速度偏差| < 阈且速度 > 最低速）采样（运动相位闸）；② 波动幅度 = 窗内峰峰值/均值占比判据，均值近零除零前置（占比出口 0 + bInvalid）；③ 周期性判据 = 峰间隔方差 < 阈（机械卡滞特征），需 ≥ 3 峰才判；④ 非有限扭矩该拍不入窗；⑤ 诊断层不干预轴指令（属主边界）。

## 三、P0 返修规格

### P0-1 DL_Algo/FB_DL_ControlOutputSlewWatch（R52 五抽「严重」：`_nHead` 首拍越界写）

- **实测定位**：文件在 `C:\Library\DL_Algo\FB_DL_ControlOutputSlewWatch.st`，当前版本 **1.0.1**，头部 Changelog 已记「v1.0.1 R52 五抽终审修复首拍 _nHead=0 越界写（段1 域外自愈）」。
- **现状核验**：三要素中「窗深回钳 + 首拍自愈」已在位——
  - 段 1 行 107-109：`IF (_nHead < 1) OR (_nHead > _nEff) THEN _nHead := 1;`（首拍 0 与窗深缩小后域外自愈，先于段 4 行 159 `_aSign[_nHead] := _nSg` 的唯一写入点，无裸读路径）；
  - 段 1 行 110-112：`IF _nFill > _nEff THEN _nFill := _nEff;`（窗深回钳）。
- **遗留缺口（本轮行级修法）**：行 62 `_nHead : INT;` **声明仍无初值**——首拍依赖段 1 自愈兜底，属「运行时补救」而非「声明期安全」（R194 范式：环窗游标声明即赋初值）。行为变更最小方案：
  - ① 行 62 改 `_nHead : INT := 1;`（声明初值，与 R194 范式对齐；段 1 自愈行保留为双保险，不删）；
  - ② 行 63 `_nFill : INT;` 同步补 `:= 0;`（同族声明期安全）；
  - ③ 版本号维持 1.0.1 不再递增（行为零变更，仅声明防御补强；若执行方按变更纪律要求递增，则升 1.0.2 并在 Changelog 记「声明初值补强」）。
- **自检要点**：窗深 32→4 缩窗后连续运行 1000 拍，`_aSign` 无越界写（静态推演 + 机检下标域闸）；首拍即 eRun 使能路径 `_nHead=1` 入窗；复位沿行 119 `_nHead := 1` 与声明初值同值。

## 四、撞名三查核验痕迹（R214，≥20 候选）

核验口径：registry 961 components name 全量（python 提取）∪ ROADMAP.md 全文 grep ∪ `C:\Library\DL_*\` 文件树 ls。三处任一命中即换名或拒绝。

| 候选 | registry | ROADMAP | 文件树 | 结论 |
|---|---|---|---|---|
| FB_DL_BitArrayMultiSegMove | 未命中 | 未命中 | 未命中 | **收录**（1 号） |
| FC_DL_ChecksumLwordSum | 未命中 | 未命中 | 未命中 | **收录**（2 号） |
| FB_DL_HealthStatusArbiter | 未命中 | 未命中 | 未命中 | **收录**（3 号；与 I_DL_DeviceHealth 为聚合件 vs 单源契约件，语义分立） |
| FB_DL_PrbsSignal | 未命中 | 未命中 | 未命中 | **收录**（4 号；与 FC_DL_RandomNext（LCG 随机数）、FB_DL_PulseGenerator（周期方波）语义分立） |
| FB_DL_PidRelayAutoTune | 未命中 | 未命中 | 未命中 | **收录**（5 号） |
| FB_DL_HistogramAccum | **命中** | — | **命中**（DL_MathData） | 拒 → 换名 **FB_DL_HistogramBinTally** 后三查通过，收录（6 号） |
| FB_DL_HistogramBinTally | 未命中 | 未命中 | 未命中 | 收录（6 号） |
| FB_DL_PnDiagAlarmDecode | 未命中 | 未命中 | 未命中 | **收录**（7 号；与 PortDiagAggregator/PortDiagBoard 分工：PN 告警语义解码 vs 端口四元组聚合，码域不重叠） |
| FB_DL_FrequencySweepGen | **命中** | — | **命中**（DL_Algo） | 拒 → 换名 **FB_DL_SweepFreqGen** 后三查通过，收录（8 号） |
| FB_DL_SweepFreqGen | 未命中 | 未命中 | 未命中 | 收录（8 号） |
| FB_DL_FirstOrderIdent | 未命中 | 未命中 | 未命中 | **收录**（9 号；与 FB_DL_SmithPredictor 分工：辨识出模型 vs 用模型补偿） |
| FB_DL_CamTableLiveTrim | 未命中 | 未命中 | 未命中 | **收录**（10 号；与 FB_DL_ElectronicCam 分工：表装载/校验 vs 运行中修调） |
| FB_DL_NightPurgeCtrl | **命中** | — | **命中**（DL_Process） | 拒 → 换名 **FB_DL_NightFlushPurge** 后三查通过，收录（11 号） |
| FB_DL_NightFlushPurge | 未命中 | 未命中 | 未命中 | 收录（11 号） |
| FB_DL_AirCompressorLoadUnload | 未命中 | 未命中 | 未命中 | **收录**（12 号） |
| FB_DL_RecipeSwitchHandover | 未命中 | 未命中 | 未命中 | **收录**（13 号；与 FB_DL_RecipeManager 分工：配方存储/校验 vs 切换交接时序编排） |
| FB_DL_EnthalpyPrioritySwitch | 未命中 | 未命中 | 未命中 | **收录**（14 号；与 FB_DL_EnthalpyCompareCtrl（R6 存量）分工已核对：模式切换 vs 焓差判定） |
| FB_DL_TankAgitationSeq | 未命中 | 未命中 | 未命中 | **收录**（15 号；与 MixRecipeControl/CipCleaningSeq 工艺语义不同：搅拌时序，非复刻） |
| FB_DL_AxisTorqueRippleWatch | 未命中 | 未命中 | 未命中 | **收录**（16 号；与 FB_DL_TorqueLimitControl 分工：纹波诊断 vs 转矩限幅） |
| FB_DL_Affine2DProject | 未命中 | 未命中 | 未命中 | **拒**（三查通过但 MathData 配额 2/2 已满；仿射族 ◐ 挂下轮首批） |
| FC_DL_Crc16Reflected | 未命中 | 未命中 | 未命中 | **拒**（三查通过但与 FC_DL_Crc16Modbus 同算法族孪生风险 + MathData 配额满；矩阵已记「反射型留独立件」下轮再议） |
| FB_DL_HumidifierAdiabat | **命中** | **命中** | **命中** | **拒**（三重命中，R53 已排除清单内） |
| FB_DL_EnthalpyCompareCtrl | **命中** | — | **命中** | **拒**（registry 存量 R6，排除后 14 号名方可立） |
| FB_DL_RecipeManager | **命中** | **命中** | **命中** | **拒**（存量 R8） |
| FB_DL_SteamTrapSurvey | **命中** | **命中** | **命中** | **拒**（存量） |
| FB_DL_FftSpectrumBlock | 未命中 | 未命中 | 未命中 | **拒**（三查通过但 PLC 周期任务内 FFT 算力不可行、无实时用例，宁少勿滥） |
| FB_DL_MotorBearingTempWatch | 未命中 | 未命中 | 未命中 | **拒**（三查通过但与 R53 BearingVibTrend 判据家族同源单量变体，独立工程意义不足，凑数嫌疑） |

小计：候选 27 个，直接通过 13，换名后通过 3，拒绝 11（拒因：registry/树命中 6、配额满 2、可行性/凑数 3）。**拒绝名单均不新增 ROADMAP 待办（本轮禁令），挂 ROUND_PLAN 下轮排程优先。**
