# R55 构建轮 · 目标锁定与选题台账（2026-11-20 20:40 启动）

规划角色：道莅代码库产品总监｜本轮只做规划与文档，零 .st 代码产出。

## 一、统计段

| 指标 | 数值 |
|---|---|
| 总库组件数 | 977 / 10,000（v2.46.0） |
| 距 1,000 里程碑 | 差 23（本轮 20 件若全落地 → 997，距 1,000 差 3） |
| 500 里程碑 | 已越过（977 − 500 = +477） |
| 1,000→10,000 段余量 | 9,023 |
| 今日（11-20）已入库 | 132 / 200 |
| 子库 counts | Base 111 / MathData 217 / Algo 117 / Device 181 / Motion 109 / Process 242 |
| 源矩阵覆盖 | ☐ 待挖组 = 0（全部 ✔/◐）；T0 八组余量 0，本轮 T0 = 0 |
| ROADMAP 待办 | 34 条（本轮不新增待办；盘点后补勾 3 条脏项 → 剩 31 条组件/治理类） |
| 本轮构成 | ROADMAP 池 17 件 + ◐ 深化替补 3 件（PackML/ModPID/LGF-Math 各 1） |

## 二、三查执行记录（R214 撞名三查：registry 全名表 + ROADMAP 全文 + 六库文件树 glob）

- 候选 22 件 × 三查，全部留痕：
  - **registry 命中 3**：`FB_DL_LabelWeekCode` / `FB_DL_CaseShiftTally` / `FB_DL_FilterWeekWindow` —— registry 已在册且 `DL_Process\*.st` 文件已落盘，属 ROADMAP 漏勾脏项，本轮就地补勾（- [ ] → - [x] 并注记），不重复立项。
  - **变体拒绝 2**：`FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx` —— ROADMAP §948 条目自标"疑似与存量同义"；实测 registry 已有 `FC_DL_ShlEx / FC_DL_ShrEx / FC_DL_ShlLwordEx / FC_DL_ShrLwordEx / FC_DL_RolEx / FC_DL_RorEx / FC_DL_RolLwordEx / FC_DL_RorLwordEx`，DWORD 显式命名属同功能仅参数域不同的凑数变体 → 拒绝。该 ROADMAP 条目建议下轮改判"不立项"而非继续挂 P2。
  - **零命中收录 17**：见选题台账。
- 三查命中数合计：3（台账脏项）+ 2（同义变体，语义命中）= 5；拒绝项合计 5。

## 三、选题台账（20 件，批次即依赖顺序）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 | 分工边界（与既有件） |
|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_NewtonRaphson | DL_MathData | FC_DL_ | 一元非线性方程牛顿-拉夫逊迭代求根（割线降级 + 防死锁计数器） | t2-1-lgf-math | 3 | 1 | 与 `FC_DL_NthRoot`（幂开方）分工：本件解一般方程 f(x)=0，不做幂运算 |
| 2 | FB_DL_FopdtStepIdent | DL_Algo | FB_DL_ | 阶跃响应 FOPDT（一阶+纯滞后）参数辨识，供 PID 整定前置 | t2-5-modpid | 4 | 1 | 与 `FB_DL_PidController` 分工：本件只出 K/T/Lp 参数，不闭环 |
| 3 | FB_DL_EnergyMonthPreset | DL_Process | FB_DL_ | 月度能耗预算预置计数与超限预警 | roadmap-p2-energy | 2 | 1 | 与 `FB_DL_PresetCounterSat` 分工：本件做月窗+能耗语义包装，计数器本体不复刻 |
| 4 | FB_DL_ChamberTempUnitBank | DL_Process | FB_DL_ | 多腔室温标统一换算行（多实例换算 + 温区联动） | roadmap-p2-li-p2 | 2 | 1 | 与 `FC_DL_TempUnitConvert` 分工：单值换算归 FC，本件做多腔编排 |
| 5 | FB_DL_RollPressBitWord | DL_Process | FB_DL_ | 辊压压力报警字位段打包与通道映射 | roadmap-p2-li-p2 | 2 | 1 | 与 `FC_DL_WordBitPack` 分工：位段打包原子归 FC，本件做报警通道语义映射 |
| 6 | FB_DL_FormatMonthAudit | DL_Process | FB_DL_ | 化成/分容月度窗排产审计（月窗 + 班次根因） | roadmap-p2-li-p2 | 3 | 2 | 与 `FB_DL_MonthWindowCheck` 分工：月窗判定归既有件，本件做排产审计语义 |
| 7 | FB_DL_TrayMonthRotate | DL_Process | FB_DL_ | 托盘月度轮换保养排程 | roadmap-p2-li-p2 | 3 | 2 | 与 `FB_DL_DutyStandbyRotation` 分工：轮值算法归既有件，本件做托盘台账域 |
| 8 | FB_DL_ShiftMonthReport | DL_Process | FB_DL_ | 班次/月度窗口产量报表闸 | roadmap-p2-li-p2 | 3 | 2 | 与 `FB_DL_OeeCalculator` 分工：OEE 计算归既有件，本件做报表闸与出数时机 |
| 9 | FB_DL_FormationWeekPlan | DL_Process | FB_DL_ | 化成/分容周计划窗（周序号 + 月窗双闸） | roadmap-p2-li-p2 | 3 | 2 | 与 `FB_DL_MonthWindowCheck` 分工：月闸复用既有件，本件新增周序号维度的双闸 |
| 10 | FB_DL_StringIrrNormalize | DL_Process | FB_DL_ | 组串电流辐照归一化（辐照标定 + 窗口统计） | roadmap-p2-pv-p2 | 3 | 2 | 与 `FC_DL_LinearScale` 分工：标定原子归 FC，本件做组串域归一化判据 |
| 11 | FB_DL_BatchWeekReport | DL_Process | FB_DL_ | 批次周报闸与周批号生成 | roadmap-p2-li-p2 | 3 | 3 | 与 `FB_DL_ShiftMonthReport`（本批 #8）分工：月/班次闸与周闸分开，周批号生成为本件独有 |
| 12 | FB_DL_StringElImageMap | DL_Process | FB_DL_ | EL 图像缺陷坐标归档与批次比对 | roadmap-p2-pv-p2 | 4 | 3 | 与 `FB_DL_BufferMagazine` 分工：槽位台账归既有件，本件做图像索引域 |
| 13 | FB_DL_AmcMonitorStat | DL_Process | FB_DL_ | AMC 气态分子污染物在线统计分级 | roadmap-p2-semi-p2 | 3 | 3 | 与 `FB_DL_SignalStatistics` 分工：统计原子归既有件，本件做 AMC 分级阈值域 |
| 14 | FB_DL_BeltHeatRecovery | DL_Process | FB_DL_ | 转轮热回收输送联锁（温差判据外置） | roadmap-p2-hvac-p2 | 3 | 3 | 与 `FB_DL_ConveyorZone` 分工：输送区联锁归既有件，本件做热回收温差判据 |
| 15 | FB_DL_ElectrolyteDosingTrend | DL_Process | FB_DL_ | 注液量趋势 SPG 判据（多批次重量差统计） | roadmap-p2-li-p2 | 3 | 4 | 与 `FB_DL_BatchDosingControl` 分工：定量结算归既有件，本件只消费结算值做趋势判据 |
| 16 | FB_DL_EvaDosingTare | DL_Process | FB_DL_ | EVA 膜裁剪称重定量（皮重自动 tare 策略） | roadmap-p2-li-p2 | 3 | 4 | 与 `FB_DL_LoadcellTareCtrl` 分工：tare 原子归 Device 既有件，本件做裁剪定量工艺策略 |
| 17 | FB_DL_ChemDosingGrav | DL_Process | FB_DL_ | 化学液定量补给称重（密度温度补偿外置） | roadmap-p2-li-p2 | 3 | 4 | 与 `FB_DL_BatchDosingControl` 分工：批次相骨架复用，密度补偿显式外置为输入 |
| 18 | FB_DL_CoinCellAssembler | DL_Process | FB_DL_ | 扣电组装工站模板（叠片-压紧-封口） | roadmap-p2-li-p2 | 5 | 4 | 与 `I_DL_Cylinder`/`I_DL_TemperatureZone` 分工：器件抽象归接口，本件是工站级编排模板 |
| 19 | FB_DL_PackMlUnitMode | DL_Process | FB_DL_ | PackML UnitMode/PMODE 管理（模式请求仲裁 + 状态化命令过滤） | t2-7-packml | 3 | 4 | 与 `FB_DL_PackMlStateMachine` 分工：17 态流转归既有件，本件管 PROD/MAINT/MANUAL 模式域；与 `FB_DL_ModeArbiter` 分工：通用仲裁归既有件，本件绑定 PackML 契约枚举 |
| 20 | FB_DL_BacdHvacPoll | DL_Process | FB_DL_ | BA 顺控 BACnet/Modbus 轮询行 | roadmap-p2-hvac-p2 | 4 | 4 | 与 `FB_DL_ModbusPollMaster` 分工：轮询主站归既有件，本件派生 TCP 传输 + BA 点表编排 |

批次依赖说明：
- **批 1**：Level 0/1 基石与轻复用件，零内部依赖，全部只引用既有件，先行落库。
- **批 2**：月窗族 5 件，共享 `MonthWindowCheck` / `WeekOfYearCalc` / `OeeCalculator` 基座，彼此零互依。
- **批 3**：周窗/光伏/暖通族，依赖批 1~2 既有件（含 #8 报表闸作对照口径），零互依。
- **批 4**：称重配料与工站模板（重组合件）+ PackML 模式件，依赖面最宽（DosingControl / 接口 / PollMaster），压轴。

## 四、分类与配额自评

- 分类分布：Process 17 / Algo 1 / MathData 1 / Device 0 / Motion 0 / Base 0 —— 偏科为真池现状（ROADMAP 组件类待办 20 条中 17 条为 Process P2），按 R198「池消化型回补不算配额倾斜违规」执行，不跨池凑数。
- 替补 3 件（#1/#2/#19）为 ◐ 深化（t2-1-lgf-math / t2-5-modpid / t2-7-packml），均为 registry 零命中真缺口，非变体。
- T0 类 = 0（八组余量 0，禁凑）。

## 五、拒绝项与挂账

| 拒绝项 | 拒绝原因 | 处置 |
|---|---|---|
| FC_DL_ShlDwordEx | 同义变体（ShlEx 已覆盖） | ROADMAP §948 建议改判不立项 |
| FC_DL_ShrDwordEx | 同义变体（ShrEx 已覆盖） | 同上 |
| FB_DL_LabelWeekCode | 三查命中：已在册 | ROADMAP 已补勾 |
| FB_DL_CaseShiftTally | 三查命中：已在册 | ROADMAP 已补勾 |
| FB_DL_FilterWeekWindow | 三查命中：已在册 | ROADMAP 已补勾 |

挂账：`FB_DL_AutoTuneRelay` / `FB_DL_RelayAutoTune` / `FB_DL_PidRelayAutoTune` 三件语义高度近邻（registry 巡检发现），下轮抽检时核对头注释分工声明是否齐备，缺则按 R216 补分工注记。
