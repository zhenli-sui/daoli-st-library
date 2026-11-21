# R55 源狩猎记录（RAW NOTES）

轮次性质：**零检索轮（WebSearch 0/3）**——复用既有池与矩阵台账，零外部仓库抓取、零代码行复制。

## 1. 来源明细

| 序号 | 组件名 | 来源标签 | 来源/URL | 许可证 | 提取点 |
|---|---|---|---|---|---|
| 1 | FC_DL_NewtonRaphson | t2-1-lgf-math | 矩阵既有 ◐ 行「T2-1 LGF · Math」数值分析子族（台账 R48 行）；算法取公开数值分析教材定义 | 无代码复制，仅借分类事实 | 牛顿迭代 x_{n+1}=x_n−f(x_n)/f'(x_n) 公开数学定义，clean-room |
| 2 | FB_DL_FopdtStepIdent | t2-5-modpid | 矩阵既有 ◐ 行「T2-5 Mod_PID_Control」（R18 深化台账）；FOPDT 模型语义取公开过程控制教材 | 无代码复制 | 一阶+纯滞后阶跃辨识（切线法/两点法公开公式），clean-room |
| 3 | FB_DL_EnergyMonthPreset | roadmap-p2-energy | ROADMAP §13.6 行 584 未勾条目 | — | 复用 PresetCounterSat + Integrator 既有池 |
| 4 | FB_DL_ChamberTempUnitBank | roadmap-p2-li-p2 | ROADMAP §15.x 行 564 未勾条目 | — | 复用 TempUnitConvert 多实例 |
| 5 | FB_DL_RollPressBitWord | roadmap-p2-li-p2 | ROADMAP §14.x 行 548 未勾条目 | — | 复用 WordBitPack + AlarmManager |
| 6 | FB_DL_FormatMonthAudit | roadmap-p2-li-p2 | ROADMAP §14.x 行 549 未勾条目 | — | 复用 MonthWindowCheck + OeeCalculator |
| 7 | FB_DL_TrayMonthRotate | roadmap-p2-li-p2 | ROADMAP §14.x 行 559 未勾条目 | — | 复用 MonthWindowCheck + DutyStandbyRotation |
| 8 | FB_DL_ShiftMonthReport | roadmap-p2-li-p2 | ROADMAP §14.x 行 574 未勾条目 | — | 复用 MonthWindowCheck + OeeCalculator |
| 9 | FB_DL_FormationWeekPlan | roadmap-p2-li-p2 | ROADMAP §16.x 行 630 未勾条目 | — | 复用 WeekOfYearCalc + MonthWindowCheck |
| 10 | FB_DL_StringIrrNormalize | roadmap-p2-pv-p2 | ROADMAP §16.x 行 635 未勾条目 | — | 复用 LinearScale + SignalStatistics |
| 11 | FB_DL_BatchWeekReport | roadmap-p2-li-p2 | ROADMAP §17.x 行 669 未勾条目 | — | 复用 WeekOfYearCalc + OeeCalculator |
| 12 | FB_DL_StringElImageMap | roadmap-p2-pv-p2 | ROADMAP §19.x 行 699 未勾条目（R11 新增） | — | 复用 BufferMagazine + RingBufferLReal |
| 13 | FB_DL_AmcMonitorStat | roadmap-p2-semi-p2 | ROADMAP §7.x 行 371 未勾条目 | — | 复用 SignalStatistics + AlarmManager |
| 14 | FB_DL_BeltHeatRecovery | roadmap-p2-hvac-p2 | ROADMAP §9.x 行 502 未勾条目 | — | 复用 ConveyorZone，温差判据外置 |
| 15 | FB_DL_ElectrolyteDosingTrend | roadmap-p2-li-p2 | ROADMAP §10.x 行 467 未勾条目 | — | 复用 SignalStatistics + BatchDosingControl 结算值 |
| 16 | FB_DL_EvaDosingTare | roadmap-p2-li-p2 | ROADMAP §10.x 行 479 未勾条目 | — | 复用 BatchDosingControl + tare 策略 |
| 17 | FB_DL_ChemDosingGrav | roadmap-p2-li-p2 | ROADMAP §10.x 行 485 未勾条目 | — | 复用 BatchDosingControl，密度补偿外置 |
| 18 | FB_DL_CoinCellAssembler | roadmap-p2-li-p2 | ROADMAP §6.x 行 355 未勾条目 | — | 注入 I_DL_Cylinder + I_DL_TemperatureZone |
| 19 | FB_DL_PackMlUnitMode | t2-7-packml | 矩阵既有 ◐ 行「T2-7 PackML / OMAC」（R5/R7/R9 台账）；UnitMode/PMODE 语义取 ISA-TR88.0.02 PackML 公开模型 | 无代码复制 | PackML UnitMode 状态化命令过滤矩阵为公开标准条款，clean-room |
| 20 | FB_DL_BacdHvacPoll | roadmap-p2-hvac-p2 | ROADMAP §14.x 行 582 未勾条目 | — | 复用 ModbusPollMaster 派生 TCP 传输块 |

## 2. 合规结论

- 本轮零 WebSearch、零仓库抓取，全部选题可溯源至 `ROADMAP.md` 未勾条目行号或 `SOURCE_HUNTING_MATRIX.md` 既有 ◐ 台账行。
- 17 件 ROADMAP 池件：池行即反证句底座（R197 池认领制）；3 件 ◐ 深化件只借「分类组织/公开标准语义」，算法与公式 100% clean-room。
- 无新开 ☐ 组：源矩阵 ☐ 待挖组已为 0（全 ✔/◐），T0 八组余量 0 本轮禁用。

## 3. 三查与拒绝留痕

- 22 候选 × 三查（registry 全名表 977 条 + ROADMAP 全文计数 + 六库文件树 glob）：零命中 17、registry+文件树双证命中 3（LabelWeekCode / CaseShiftTally / FilterWeekWindow，ROADMAP 漏勾已补）、同义变体拒绝 2（ShlDwordEx / ShrDwordEx，存量 ShlEx/ShrEx/RolEx/RorEx 八件已覆盖 DWORD 域）。
- 拒单率 5/22 ≈ 23%，高于 R228 的 2:1 警戒线（收录:候选 = 20:22），选题池健康。
