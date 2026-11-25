(*
  ============================================================
  组件名 : FC_DL_PneuAirConsumeCalc
  分类   : DL_Device
  功能   : 气缸耗气量计算，按缸径行程、表压与动作频次求单次与每分钟标准状态耗气量
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_PneuAirConsumeCalc : REAL
VAR_INPUT
    rBoreDia_mm    : REAL; // 缸径 [mm] bore diameter [mm]
    rStroke_mm     : REAL; // 行程 [mm] stroke [mm]
    rPressBar      : REAL; // 工作表压 [bar] working gauge pressure [bar]
    nCyclesPerMin  : INT; // 每分钟动作次数 [次/分] cycles per minute [cycle per minute]
    bDoubleActing  : BOOL; // 真为双作用，假为单作用 double acting when true, single acting when false
END_VAR
VAR_OUTPUT
    rAirPerCycle_Nl : REAL; // 单次耗气量（标准状态）[Nl] air per cycle at standard state [normal litre]
    rAirPerMin_Nl   : REAL; // 每分钟耗气量（标准状态）[Nl/min] air per minute at standard state [normal litre per minute]
    bValid          : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_PI_4      : REAL := 0.7853982; // 四分之圆周率 pi divided by four
    DL_MM3_PER_L : REAL := 1000000.0; // 每升立方毫米数 cubic millimetres per litre
    DL_ATM_BAR   : REAL := 1.013; // 标准大气压 [bar] standard atmosphere [bar]
    DL_TWO       : REAL := 2.0; // 双作用腔数因子 the double acting chamber factor
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 三实数输入有限性判定 finiteness verdict of the three real inputs
    _rArea : REAL := 0.0; // 缸径截面面积 [mm2] bore section area [mm2]
    _rVolL : REAL := 0.0; // 单行程几何容积 [l] geometric volume per stroke [litre]
    _rStdL : REAL := 0.0; // 单次标准状态容积 [Nl] standard state volume per cycle [normal litre]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_PneuAirConsumeCalc := 0.0; // 缺省返回零 default zero return
rAirPerCycle_Nl := 0.0; // 单次耗气预置零 air per cycle preset to zero
rAirPerMin_Nl := 0.0; // 分钟耗气预置零 air per minute preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rBoreDia_mm = rBoreDia_mm) AND (rStroke_mm = rStroke_mm) AND (rPressBar = rPressBar); // 三输入自反判定 self comparison of the three inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜几何与频次闸 geometry and cycle gate
IF (rBoreDia_mm <= 0.0) OR (rStroke_mm < 0.0) OR (rPressBar < 0.0) THEN
    RETURN; // 几何或压力非法 an illegal geometry or pressure
END_IF
IF nCyclesPerMin < 0 THEN
    RETURN; // 负频次属配置非法 a negative cycle count is an illegal configuration
END_IF
// 段 4｜几何容积与双作用折算 geometric volume and the double acting factor
_rArea := DL_PI_4 * rBoreDia_mm * rBoreDia_mm; // 缸径截面面积 bore section area
_rVolL := _rArea * rStroke_mm / DL_MM3_PER_L; // 单行程几何容积 volume per stroke
IF bDoubleActing THEN
    _rVolL := _rVolL * DL_TWO; // 双作用按两腔估算，杆径影响按忽略处理 double acting counts both chambers with the rod ignored
END_IF
// 段 5｜标准状态折算与分钟耗气 standard state conversion and the minute consumption
_rStdL := _rVolL * (rPressBar + DL_ATM_BAR); // 表压折算到标准状态 gauge pressure converted to the standard state
rAirPerCycle_Nl := _rStdL; // 单次耗气落定 land the per cycle consumption
rAirPerMin_Nl := _rStdL * INT_TO_REAL(nCyclesPerMin); // 分钟耗气落定 land the per minute consumption
bValid := TRUE; // 结果可用 result usable
FC_DL_PneuAirConsumeCalc := rAirPerMin_Nl; // 函数返回分钟耗气 return the per minute consumption
END_FUNCTION
