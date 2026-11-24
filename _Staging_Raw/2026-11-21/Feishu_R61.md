**道莅代码库 · R61 批处理巡检战报**（2026-11-21 12:21–12:54）

**看板**
- 总库 **1,101 / 10,000（11.01%）**｜今日 104/200｜500 冲刺超额 **+601**（已回归常态节奏）
- JSONL 语料 **1,108 条**（+16 新增、+5 返修重注入，bad=0）
- 源矩阵：☐ 11 组 / ◐ 24 组，T0 八组 8/8 ✔（维护模式）

**四批完成（16/16，4 批 × 4 件）**
- 批 1 位域/标量纯函数 4/4 ✔：ReverseBitsLword、BitScanLword、Hypot3D、TrapezoidArea
- 批 2 统计深化+时序 4/4 ✔：SortIndexLReal、WeightedPercentile、MeanAbsDevCalc、LongPressButton
- 批 3 设备守卫/参数闸 4/4 ✔：RailPowerSequence、AxisLimitSwitchBank、PidParamGuard、PhaseLossGuard
- 批 4 H 状态机 4/4 ✔：SensorPairPlausibility、AirDryerDiag、TurretToolSelect、LineClearanceVerify
- 分布 Base 4 / MathData 5 / Device 3 / Motion 2 / Algo 1 / Process 1（R267 族避让达标），2,306 行，双语注释 100%

**返修闭环**：R60 挂账 6 项全清（AxisCmdArbiter 双通道+锁存 / Table3D·Affine 信息级码口径 / Affine 单级链奇异判 / Table3D 轴向量有限性 / ShiftHandover _nPending 锁存）+ D8~D13 轻项顺手 + TwoStepConfirm v1.0.2

**机检**：16/16 PASS fail=0（首跑误判系判据误设，已修正并留痕）

**终审**：严重 1 / 中 3 / 轻 2 —— RailPowerSequence 空轨断电起步下标 -1 越界读（**已就地修 v1.0.1**，安全侧例外）；挂 R62：TurretToolSelect 死相位、SensorPair 环窗残留、RailPower 单轨超时计时点

**专家进化**：双账本 +6 条，游标续接 **R296**；FB-51 已于 R60 固化，本轮不固化

**风险一句话**：撞名拒单 24/40 = 60%（连续第 2 轮触线 R228），概念池进入枯竭期；编译验证债连挂 **56 轮**，须值守轮接真编译

**下轮 R62**：P0 五抽挂账返修 + P1 豁免登记机检化 + P2 常态 16~18 件 → 约 1,117~1,119
