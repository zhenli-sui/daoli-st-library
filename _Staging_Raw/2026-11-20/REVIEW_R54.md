# REVIEW_R54 — R53 十六件五抽语义终审（2026-11-20）

> 抽样口径：从 ROUND_PLAN_R53 的 16 件中按复杂度取前 5 件读源码（PumpSurgeGuard cx4；BearingVibTrend / WetBulbCalc / SensorDriftBaseline / AxisBacklashStepComp cx3）。**本轮实抽 5/5 件**，逐条一行结论 + 一句行级修法。

| 件 | 分类 | 版本 | 判定 | 结论与修法 |
|---|---|---|---|---|
| FB_DL_PumpSurgeGuard | DL_Algo | 1.0.0 | **PASS** | 组态闸/除零前置/有限性闸/饱和最后一次写齐备，非有限拍斜坡保持与边界③声明一致；轻注：`_fFac`（行 66）声明无初值，但 eIdle 迁入拍（行 117）与复位沿（行 97）均先置 1，无裸读路径，建议下轮巡检补 `:= 1.0` 声明初值（与 R194 范式对齐），零行为变更。 |
| FB_DL_BearingVibTrend | DL_Algo | 1.0.0 | **PASS** | 族①整改到位：`_nHead` 行 60 声明即赋 1 + 行 88-93 缩窗回钳头/填充数；统计游标 1.._nFill 有界，均值除子 ≥4 无除零；非有限样本拒收不入窗不污染统计；分级判据全直比无浮点判等。无修法。 |
| FC_DL_WetBulbCalc | DL_MathData | 1.0.0 | **PASS** | 三输入有限性闸（NaN 自反 + Inf 差判）→ 哨兵早退；除子 `_fT+243.04` 由域钳位保证恒正，导数近零发散退出（边界③）；迭代不收敛落 bValid=FALSE 安全侧。轻注：收敛判定（行 118）取递进后的步长，边界一致，无行为缺口。 |
| FB_DL_SensorDriftBaseline | DL_Algo | 1.0.0 | **中** | ①行 110：eIdle 迁入拍 `_fBaseI := fValue` **未做有限性闸**——使能拍 fValue=NaN 将建立 NaN 基线，此后 EMA 更新（行 121）被 _bFin 拦截但基线永久保持 NaN，行 120 `fDeviation := _fDevI` 使 NaN 穿透出口，违背边界②「非有限不污染」的自我声明。修法：行 109-113 迁入段改 `IF _bFin THEN _fBaseI := fValue; _bBase := TRUE; _eState := eMon; END_IF`（非有限拍滞留 eIdle，下一拍有限再迁入），版本升 1.0.1。 |
| FB_DL_AxisBacklashStepComp | DL_Motion | 1.0.0 | **中** | ①行 150-151：`fOffset := _fOffI; fPosOut := fPosCmd + _fOffI;` 位于 `IF _bFin` 块外——非有限命令拍 fPosOut 直算 NaN 穿透出口，违背自声明边界⑤「偏置与输出保持上拍值」。修法：行 150-151 移入 IF _bFin 分支内（非有限拍出口保持上拍），版本升 1.0.1。②轻注：行 84 与行 162 对 bCompPuls 双写（R187 两段式冗余预清），无害可留。 |

## 汇总

- 抽样 **5 件**：PASS 3（含 2 轻注）、**中 2**（SensorDriftBaseline / AxisBacklashStepComp，均属「非有限值穿透」族，修法均为出口侧相位/有限性闸，版本升 1.0.1）。
- **严重 0 条**；族①（环窗初值/回钳）在 R53 新件中已按 R194 范式落地（BearingVibTrend 为正例自证）。
- 两条「中」级缺陷同族同因（非有限值穿透出口），建议 R55 编码轮将其并入 P0 返修清单首位，与 ControlOutputSlewWatch 声明初值补强同批执行。
