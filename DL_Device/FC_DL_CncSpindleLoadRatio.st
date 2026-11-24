(*
  DL Factory R84 | FC_DL_CncSpindleLoadRatio
  功能：算主轴负载率并给过载裕度与 85%/100% 两级报警位
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_CncSpindleLoadRatio : REAL
VAR_INPUT
    fActualKw : REAL := 0.0; // 主轴实际输出功率 [kW] / actual spindle power [kW]
    fRatedKw : REAL := 7.5; // 主轴额定（连续）功率 [kW] / rated spindle power [kW]
    fWarnPct : REAL := 85.0; // 预警负载率门限 [%] / warning load threshold [%]
    fTripPct : REAL := 100.0; // 停机建议门限 [%] / trip recommendation threshold [%]
END_VAR
VAR_OUTPUT
    fMarginPct : REAL; // 过载裕度（100 − 负载率） [%] / overload margin [%]
    xWarn : BOOL; // 负载率超预警门限 [-] / load above warning threshold [-]
    xTrip : BOOL; // 负载率超停机建议门限 [-] / load above trip threshold [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fRatioPct : REAL; // 负载率中间量 [%] / load ratio intermediate [%]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_CncSpindleLoadRatio := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fMarginPct := 0.0; // 裕度预置零 [%] / margin preset zero [%]
xWarn := FALSE; // 预警位预置 FALSE [-] / warning preset false [-]
xTrip := FALSE; // 停机位预置 FALSE [-] / trip preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 额定功率分母闸（R4/R20）
IF NOT (fActualKw > -1.0E30 AND fActualKw < 1.0E30) OR NOT (fRatedKw > -1.0E30 AND fRatedKw < 1.0E30) OR NOT (fWarnPct > -1.0E30 AND fWarnPct < 1.0E30) OR NOT (fTripPct > -1.0E30 AND fTripPct < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fRatedKw < 1.0E-9 THEN
    RETURN; // 额定功率正域分母闸（防除零） [kW] / rated power positive denominator gate [kW]
END_IF
IF NOT (fWarnPct < fTripPct) THEN
    RETURN; // 组态闸：预警门限必须严格小于停机门限 [%] / config gate: warn below trip [%]
END_IF

// 段 3｜主算：负载率 = 实际功率 / 额定功率
fRatioPct := (fActualKw / fRatedKw) * 100.0; // kW ÷ kW × 100 = % / [kW] / [kW] × 100 = [%]
IF NOT (fRatioPct > -1.0E30 AND fRatioPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the result [-]
END_IF
fMarginPct := 100.0 - fRatioPct; // % − % = %（负值表示已过载） / [%] minus [%] = [%], negative means overloaded
xWarn := fRatioPct > fWarnPct; // 直比门限，禁浮点等值 [-] / direct compare, no float equality [-]
xTrip := fRatioPct > fTripPct; // 直比门限，禁浮点等值 [-] / direct compare, no float equality [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_CncSpindleLoadRatio := fRatioPct; // 返回负载率 [%] / return the load ratio [%]
END_FUNCTION
