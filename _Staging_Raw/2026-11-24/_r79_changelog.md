## v2.71.0（2026-11-24 · R79 首轮冲刺）

### Added（44 件，复杂 4 / 简单 40）
- **日历算术族（DL_MathData，4 件经审校放行）**：CalDayOfYear / CalDateFromDayOfYear / CalQuarterIndex / CalIsWeekend。原计划 9 件，5 件因与在库 `FC_DL_LeapYearChk` / `FC_DL_DaysInMonthChk` / `FC_DL_DayOfWeekCalc` / `FC_DL_WeekNumIso` 同义被拒收。
- **整数数论族（DL_MathData，6 件）**：IntSqrtFloorUdint / IntIsPerfectSquareUdint / IntDigitSumUdint / IntDigitCountUdint / IntPowSatUdint / IntReverseDigitsUdint。IntDivModSafe（撞 DivDintSafeChk）、IntSignExtractLreal（撞 SignumCalc）拒收。
- **平面几何族（DL_MathData，7 件）**：GeoPointLineDist / GeoPointInRectXY / GeoPointInConvexQuadXY / GeoCentroid3Pt / GeoPolylineLenFixed / GeoBBoxFromPtsFixed / GeoLineAngleXY。GeoLineIntersectXY 撞 LineIntersection 拒收。
- **统计扩展族（DL_MathData，3 件）**：StatsWelfordVar（Welford 在线方差）/ StatsZScoreClamp / StatsRunLengthMax / StatsHistogramBin / StatsPercentileRankFixed（后两件为存疑放行，见 QA 报告）。
- **校验和族（DL_Algo，5 件）**：ChkFletcher16 / ChkFletcher32 / ChkTwosCompSum16 / ChkSum32Mod / ChkAdler32 / ChkParityBlock（存疑放行）。
- **替换批（DL_MathData，12 件）**：CalAddMonths / CalDateSpanMonths / IntLcmSafeUdint / IntIsPrimeUdint / IntModPowUdint / IntFloorLog2Udint / IntNextPrimeUdint / GeoChordHeightCalc / GeoCircleSectorArea / GeoPointRotateXY / StatsCoeffVarCalc / StatsEntropyCalc。
- **复杂工艺件（DL_Process，4 件）**：CoolingTowerFanStageSeq（C4，冷却塔风机分级投切+主备轮换）/ ScrewConveyorDoseSeq（C4，螺旋给料计量批次）/ PressForceCurveExec（C4，压机多段力曲线）/ AerationBlowerCycle（C3，曝气间歇循环+DO 迟滞带）。

### Fixed（修复件 4，不计产出）
- `FC_DL_RoundToMultipleInt` v1.0.1：补 DINT 上下饱和闸（进位 `nLo+nMultiple`、退位 `nLo-nMultiple` 越界回绕），新增 `bSat` 出口。
- `FB_DL_MultiZoneSetpointScheduler` v1.0.2：bReset 电平判据 → R_TRIG 沿（CASE 外无条件刷新）+ eHold 复位沿同步清锁存 + Inf 判据改 `ABS(x)>DL_MZS_FIN`。
- `FB_DL_PalletizerLayerBuildSeq` v1.0.2：bReset 电平判据 → R_TRIG 沿。
- `FB_DL_AnalogSensorHealthClassify` v1.0.2：bReset 电平判据 → R_TRIG 沿 + 超量程分级改用窗极值重算（原单拍标志跨拍读取致 eOverHigh 恒不成立）。

### Rejected（13 件，移 `_quarantine/R79/`）
CalIsLeapYear / CalMonthDays / CalMonthEndDate / CalWeekdayIndex / CalIsoWeekNo / IntDivModSafe / IntSignExtractLreal / GeoLineIntersectXY / StatsSkewKurtStream / StatsMadFixed / StatsTrimmedMeanFixed / ChkXor8 / ChkSum8——均与在库件语义重复；行数 159。

### Known Issues（挂账）
- `FB_DL_CoolingTowerFanStageSeq` eRotate 相结构性不可达（tRunAccum 仅 eRunning 累加、轮换阈值判定在 eStageUp/eStageDown 之外），主备轮换功能失效，P0 挂 R80。
- 6 件新件仍用 `(x−x)<>0` 判 Inf（闸席批 3 已确认该写法在 IEEE 语义下有效，非缺陷，但与本库 `ABS(x)>FIN` 范式不一致），列入风格统一 P1。
