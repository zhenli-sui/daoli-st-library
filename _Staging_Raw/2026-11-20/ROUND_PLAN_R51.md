# R51 轮次计划（2026-11-20 09:58，只做规划，不写代码）

## 统计快照
- 总库 registry：905 / 10000（v2.42.0，JSONL 906 条）
- 今日产出：60 / 200（30.0%）
- 500 计划：已超额 +405（905 vs 500）
- 源矩阵覆盖率：T0 八组全 ✔（余量 0）；台账 ☐ 残留 0 行、◐ 深化行待挖子族若干（T2-1 Math 三角/极分解、T2-1 Measurement 统计族等既有备注）
- ROADMAP 未勾待办：54 条（其中可立项组件 41 条）≥ 30 → **按纪律禁止新增条目，只认领**

## 本轮 20 目标（18 件 ROADMAP 池认领 + 2 件矩阵 ◐ 待挖子项均衡补充）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_AhuFanArrayTrim | DL_Process | FB_ | 空调箱风机阵列静压微调（分级投切+静压闭环） | ROADMAP §16.5 R11 池 P1（L724） | 4 | 1 |
| 2 | FB_DL_ElectrodeGapMark | DL_Process | FB_ | 极片留白区位置标记与对齐判定 | ROADMAP §13.x P1（L626） | 4 | 1 |
| 3 | FB_DL_FormationChannelQueue | DL_Process | FB_ | 化成柜通道排队与优先级抢占（故障自动摘除） | ROADMAP §16.1 R11 池（L694） | 4 | 1 |
| 4 | FB_DL_SlurryDensityTrim | DL_Process | FB_ | 浆料面密度与密度交叉校核双源分档告警 | ROADMAP §16.1 R11 池（L695） | 3 | 1 |
| 5 | FB_DL_FilmSpliceWeekPlan | DL_Process | FB_ | 接膜保养周窗与耗材台账提醒 | ROADMAP §16.4 R11 池（L718） | 3 | 1 |
| 6 | FB_DL_CasePackerPatternVerify | DL_Process | FB_ | 装箱排列模式校验防错（重叠即拒启） | ROADMAP §16.4 R11 池（L720） | 3 | 2 |
| 7 | FB_DL_ChillerYearWinStart | DL_Process | FB_ | 冷机年度启停窗与保养互锁（非窗禁启） | ROADMAP §16.5 R11 池（L725） | 3 | 2 |
| 8 | FB_DL_ReactorYearWinClean | DL_Process | FB_ | 反应釜年度清洗窗与批次闸门 | ROADMAP §16.6 R11 池（L733） | 3 | 2 |
| 9 | FB_DL_LoopAuditTrailWindow | DL_Process | FB_ | 回路整定审计时间窗与变更留痕（双人确认位） | ROADMAP §16.6 R11 池（L736） | 4 | 2 |
| 10 | FB_DL_LamEvaGelContent | DL_Process | FB_ | 层压 EVA 交联度估算与合格窗判定 | ROADMAP §19.2 R12 池（L814） | 3 | 2 |
| 11 | FB_DL_PalletLabelVerify | DL_Process | FB_ | 托盘标签/EAN 校验与错标拦截 | ROADMAP §19.4 R12 池（L832） | 3 | 3 |
| 12 | FB_DL_ElectrolyteFillVacuum | DL_Process | FB_ | 注液真空度与静置计时台账 | ROADMAP §21.1 R13 池（L879） | 3 | 3 |
| 13 | FB_DL_DateCoderPosition | DL_Process | FB_ | 喷码日期位置偏移与缺失检测 | ROADMAP §21.4 R13 池（L907） | 3 | 3 |
| 14 | FB_DL_SteamTrapSurvey | DL_Device | FB_ | 疏水阀温度周期特征普查与失效分级 | ROADMAP §21.5 R13 池（L920） | 3 | 3 |
| 15 | FC_DL_PolarDecomp2D | DL_MathData | FC_ | 2D 矩阵极分解（正交×对称，主方向提取） | 源矩阵 T2-1 LGF Math ◐ 待挖子项（R25 备注既有） | 3 | 3 |
| 16 | FB_DL_TrayLoadVacuum | DL_Process | FB_ | 电池片花篮真空取放（破真空吹气定宽脉冲） | ROADMAP §9.3 P2（L418） | 3 | 4 |
| 17 | FB_DL_CupFillDenest | DL_Process | FB_ | 杯装灌装机取杯-灌装-封口节拍链 | ROADMAP §9.4 P2（L435） | 4 | 4 |
| 18 | FB_DL_HumidifierAdiabat | DL_Process | FB_ | 绝热加湿器补水顺控（水位双限+排水周期） | ROADMAP §9.5 P2（L443） | 3 | 4 |
| 19 | FB_DL_NgBinDosing | DL_Process | FB_ | NG 料返投称重定量（学习禁用组态） | ROADMAP §9.6 P2（L471） | 4 | 4 |
| 20 | FC_DL_MadZScore | DL_MathData | FC_ | 中位数绝对偏差（MAD）稳健离群评分 | 源矩阵 T2-1 LGF Measurement ◐ 统计族待挖（R18 备注既有） | 2 | 4 |

构成核对：常态池认领 18 件 + 复杂度 ≤4 均衡补充 2 件（MathData ×2，纠正本轮子库偏斜：Process 17 / Device 1 / MathData 2）。前置件（FanArrayStageCtrl / BitFieldExtract / ToleranceWindow / LifoStack / RecipeManager / YearWindowCheck / CipCleaningSeq / Crc16Modbus / StringFixedField 等）已逐一 grep registry 核验存在。`FB_DL_CoinCellAssembler`、`FB_DL_AmcMonitorStat` 等大工站/利基件本轮让位；`FC_DL_ShlDwordEx/ShrDwordEx`（L948）按条目自带警示「疑似与存量同义」不予立项。

## 反证句（逐件：为何不是库里已有组件的凑数变体）
1. AhuFanArrayTrim：既有 `FanArrayStageCtrl` 只做分级投切，本件在其上叠加静压 PID 微调，是「投切+连续调节」双层结构，非重复。
2. ElectrodeGapMark：既有 `ScreenPrintAlign` 面向丝印对位，本件针对极片 Gap 位域提取+留白带判定，视觉标志位语义不同。
3. FormationChannelQueue：既有 `MotionCmdQueue`/`FifoBuffer` 是通用队列，本件是通道资源排队+优先级抢占+故障摘除的调度语义。
4. SlurryDensityTrim：既有 `ToleranceWindow` 是单源判窗，本件做双源交叉校核分档告警，属多源一致性新判据。
5. FilmSpliceWeekPlan：既有 `RuntimeMeter` 只累计时长，本件把周窗判定与耗材台账、提醒输出绑成保养闭环。
6. CasePackerPatternVerify：既有 `RangeOverlapCheck` 是纯区间关系函数，本件是装箱模式放行顺控，重叠只是其拒启判据之一。
7. ChillerYearWinStart：既有 `YearWindowCheck` 是年窗原子，本件叠加轮值互锁「非窗禁启」的设备控制语义。
8. ReactorYearWinClean：既有 `CipCleaningSeq` 是清洗执行顺控，本件是「过窗未洗禁投料」的批次闸门，职责在门不在洗。
9. LoopAuditTrailWindow：既有 `RecipeManager` 管参数快照，本件管维护窗内变更留痕与双人确认位，是审计生命周期。
10. LamEvaGelContent：既有 `Integrator` 是纯积分，本件做温度-时间积分→交联度标定曲线→合格窗的三段工艺换算。
11. PalletLabelVerify：既有 `Crc16Modbus`/`StringTrim` 是原子件，本件是标签分段+校验位复算+错标拦截的组合契约件。
12. ElectrolyteFillVacuum：既有 `VacuumGaugeMux` 是计融合，本件是注液工艺的静置窗+门限+批次计数台账。
13. DateCoderPosition：既有 `MarkPositionLatch` 是喷印位锁存，本件做字段定宽解析+位置容差判偏移/缺失的诊断件。
14. SteamTrapSurvey：既有 `SteamTrapMonitor`/`DiagTrend` 是单阀监测与温差趋势，本件是跨管网周期特征普查与失效分级。
15. PolarDecomp2D：既有 `Matrix3Inverse` 是求逆、`Affine2D*` 是仿射组合，本件是 R×S 极分解提取主方向，谱语义首次入库。
16. TrayLoadVacuum：既有 `VacuumEjector` 是真空发生设备件，本件是取放顺控中破真空定宽脉冲的时序件。
17. CupFillDenest：既有 `StepSequencer` 是通用步序器，本件是取杯-灌装-封口三段节拍链的工艺编排实例。
18. HumidifierAdiabat：既有 `HumidityRatioCalc`/`RoomClimateCtrl` 是计算与房间控制，本件是绝热加湿补水+排水周期顺控。
19. NgBinDosing：既有 `BatchDosingControl` 是正向定量，本件复用其单料相做 NG 返投称重并带学习禁用组态，方向与组态均新。
20. MadZScore：既有 `SignalStatistics`/`OscillationIndex` 是均值域统计，本件用中位数/MAD 稳健口径抗粗大误差，是鲁棒统计缺口。

## 去重登记
- 候选 22 个名称（含 2 个矩阵件）对照 registry 905 条小写全量比对：**拦截 0 条，零撞名**。
- 撞名段：无（本轮不触发改名件三处记账）。

## 检索结论
**零新增检索轮**：18 件取自 ROADMAP 既有未勾条目（不扩写、不新增条目），2 件取自源矩阵既有 ◐ 行已留档的待挖子项备注（T2-1 Math R25 行、T2-1 Measurement R18 行），WebSearch 预算 0/3。

*R51 规划线 ｜ 2026-11-20 ｜ 道莅工控代码库产品总监*
