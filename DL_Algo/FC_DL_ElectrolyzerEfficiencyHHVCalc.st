(*
  DL Factory R88 | FC_DL_ElectrolyzerEfficiencyHHVCalc
  功能：按 HHV 热中性电压算电解效率 η=1.48/U，再乘辅机功率折损系数，按 70% 判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式 HHV 效率式 η_HHV=1.48/U_cell，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_ElectrolyzerEfficiencyHHVCalc : REAL
VAR_INPUT
    fCellV : REAL := 1.8; // 实测单槽电压 U [V] / measured cell voltage [V]
    fAuxPowerKW : REAL := 20.0; // 辅机功耗（泵/风机/控制，不计入堆功率） [kW] / auxiliary power [kW]
    fStackPowerKW : REAL := 500.0; // 电堆直流输入功率 [kW] / stack DC input power [kW]
    fAcceptPct : REAL := 70.0; // 系统效率合格下限（含辅机折损） [%] / acceptance efficiency [%]
END_VAR
VAR_OUTPUT
    fEffPct : REAL; // 系统 HHV 效率（已含辅机折损） [%] / system HHV efficiency [%]
    xAccept : BOOL; // TRUE=系统效率不低于合格下限 [-] / TRUE when the efficiency meets the threshold [-]
END_VAR
VAR
    fThermoV : REAL; // HHV 热中性电压常数 1.48 [V] / HHV thermoneutral voltage [V]
    fTotalKW : REAL; // 总输入功率 = 堆功率 + 辅机功率（除零判据） [kW] / total input power, the divisor [kW]
    fAuxFactor : REAL; // 辅机折损系数 = 堆功率/总功率 [-] / auxiliary penalty factor [-]
END_VAR

// 段 1｜出口预置
FC_DL_ElectrolyzerEfficiencyHHVCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fEffPct := 0.0; // 系统效率预置零 [%] / efficiency preset zero [%]
xAccept := FALSE; // 合格位预置 FALSE（未判定前不认合格） [-] / accept flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fCellV > -1.0E30 AND fCellV < 1.0E30) OR NOT (fAuxPowerKW > -1.0E30 AND fAuxPowerKW < 1.0E30) OR NOT (fStackPowerKW > -1.0E30 AND fStackPowerKW < 1.0E30) THEN
    RETURN; // 单槽电压/辅机功率/堆功率任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fAcceptPct > -1.0E30 AND fAcceptPct < 1.0E30) THEN
    RETURN; // 合格下限非有限则判据静默失效，故先拦 [%] / the threshold must be finite [%]
END_IF
IF fCellV < 1.0E-9 THEN
    RETURN; // 单槽电压正域闸（同时是分母，防除零） [V] / positive cell voltage, also the divisor [V]
END_IF
IF fAuxPowerKW < 0.0 OR fStackPowerKW <= 0.0 OR fAcceptPct <= 0.0 OR fAcceptPct > 100.0 THEN
    RETURN; // 功率符号闸 + 合格下限区间闸 (0,100] [kW, %] / power signs and threshold gate
END_IF

// 段 3｜计算
fThermoV := 1.48; // HHV 热中性电压常数装入 [V] / load the HHV thermoneutral voltage [V]
fTotalKW := fStackPowerKW + fAuxPowerKW; // kW + kW = kW，总输入功率 [kW] / [kW] + [kW] = [kW]
IF fTotalKW < 1.0E-9 THEN
    RETURN; // 除法前分母闸：总功率必须大于 1E-9 才可作除数 [kW] / denominator gate before the division [kW]
END_IF
fAuxFactor := fStackPowerKW / fTotalKW; // kW ÷ kW = 无量纲，辅机折损系数 ≤1 [-] / auxiliary penalty factor [-]
fEffPct := fThermoV / fCellV * 100.0 * fAuxFactor; // (V ÷ V) × 100 × 无量纲 = %，系统效率 [%] / [%]

// 段 4｜判定与饱和
IF NOT (fEffPct > -1.0E30 AND fEffPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
IF fEffPct > 100.0 THEN
    fEffPct := 100.0; // 上饱和：效率不可能超过 100%，超出按 100% 夹紧 [%] / saturate at 100 percent [%]
END_IF
xAccept := fEffPct >= fAcceptPct; // 系统效率与下限直比（含边界） [%] / compare against the threshold [%]

// 段 5｜出口自检
IF fEffPct < 0.0 THEN
    RETURN; // 出口自检：效率不得为负（负值说明功率符号错） [%] / efficiency must not be negative [%]
END_IF
FC_DL_ElectrolyzerEfficiencyHHVCalc := fEffPct; // 返回系统 HHV 效率 [%] / return the system efficiency [%]
END_FUNCTION
