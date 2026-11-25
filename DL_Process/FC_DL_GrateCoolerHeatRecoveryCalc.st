(*
  Name: FC_DL_GrateCoolerHeatRecoveryCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 回收热量取「二次风显热 + 三次风显热」，两者均以环境温度为基准，风侧按定压比热折算，
           即 fRecoveredHeatKw = (V2*cp*(T2-Tamb) + V3*cp*(T3-Tamb)) / 3600，单位 kW，
           3600 为 kJ/h 到 kW 的时基折算系数。
        2) 熟料可供显热取「熟料量 × 熟料比热 × (入篦床温度 − 出篦床温度)」，
           即 fClinkerHeatKw = m*1000*cpCli*(Tin-Tout) / 3600，单位 kW，
           1000 为 t 到 kg 的质量折算系数；该项是回收率的物理分母（可供热上限）。
        3) 热回收率 fRecoveryPct = 回收热量 / 熟料可供显热 * 100，钳制 0.0 ~ 100.0 %，
           回收率超过 100 % 在物理上不可能，判为测量链路故障而非效率优异。
  边界条件：1) 非有限值闸：九路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，该式同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置 xValid 而把 NaN 传给下游（R19）。
        2) 分母零闸：风侧比热 fAirCpKjNm3K 与熟料比热 fClinkerCp 均须 > DL_EPS，
           熟料可供显热 |fClinkerHeatKw| > DL_EPS 才允许做除法，否则判无效并清零。
        3) 判据取原始值（R24）：回收率越限判定使用 LIMIT 之前的原始值 _fRecoveryRawPct，
           不得先把回收率夹到 0~100 再判超域（否则判据恒真，域闸静默失效）。
        4) 物理域钳制：回收率钳 0.0 ~ 100.0 %；两路风量与熟料量不得为负（负值即传感器反向，判无效）。
        5) 温度方向校验：二次/三次风温低于环境温度、或熟料出口温度高于入口温度，均属非冷却工况，
           判无效而不取绝对值掩盖符号错误。
        6) 纯函数无状态：本件不做迟滞与去抖，滤波与报警延时由下游监视 FB 承担。
  量纲自证：fRecoveredHeatKw = (Nm3/h)*(kJ/(Nm3*K))*(K) / (s/h) = (kJ/h)/(s/h) = kJ/s = kW；
           fClinkerHeatKw   = (t/h)*(kg/t)*(kJ/(kg*K))*(K) / (s/h) = (kJ/h)/(s/h) = kW；
           fRecoveryPct     = (kW)/(kW)*100 = 无因次百分数 [%]，比量两侧同量纲，量纲关系合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_GrateCoolerHeatRecoveryCalc : BOOL
VAR_INPUT
    fSecAirNm3h      : REAL;   // 二次风标态体积流量 [Nm3/h] / Secondary air normal flow [Nm3/h]
    fTerAirNm3h      : REAL;   // 三次风标态体积流量 [Nm3/h] / Tertiary air normal flow [Nm3/h]
    fSecAirTempC     : REAL;   // 二次风温度 [degC] / Secondary air temperature [degC]
    fTerAirTempC     : REAL;   // 三次风温度 [degC] / Tertiary air temperature [degC]
    fAmbientC        : REAL;   // 环境基准温度 [degC] / Ambient reference temperature [degC]
    fClinkerTph      : REAL;   // 熟料产量 [t/h] / Clinker production rate [t/h]
    fClinkerInC      : REAL;   // 入篦床熟料温度 [degC] / Clinker inlet temperature [degC]
    fClinkerOutC     : REAL;   // 出篦床熟料温度 [degC] / Clinker outlet temperature [degC]
    fAirCpKjNm3K     : REAL;   // 风侧定压比热 [kJ/(Nm3*K)] / Air specific heat at constant pressure [kJ/(Nm3*K)]
    fClinkerCpKjKgK  : REAL;   // 熟料比热 [kJ/(kg*K)] / Clinker specific heat [kJ/(kg*K)]
END_VAR
VAR_OUTPUT
    fRecoveredHeatKw : REAL;   // 二次+三次风回收热量 [kW] / Recovered heat by secondary and tertiary air [kW]
    fClinkerHeatKw   : REAL;   // 熟料可供显热 [kW] / Clinker available sensible heat [kW]
    fRecoveryPct     : REAL;   // 热回收率 [%] / Heat recovery ratio [%]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fSecHeatKjh     : REAL;   // 二次风显热 [kJ/h] / Secondary air sensible heat [kJ/h]
    _fTerHeatKjh     : REAL;   // 三次风显热 [kJ/h] / Tertiary air sensible heat [kJ/h]
    _fRecoveredKjh   : REAL;   // 回收热量合计（钳制前）[kJ/h] / Total recovered heat before limiting [kJ/h]
    _fClinkerKjh     : REAL;   // 熟料可供显热（钳制前）[kJ/h] / Clinker sensible heat before limiting [kJ/h]
    _fRecoveryRawPct : REAL;   // 钳制前的原始回收率 [%] / Raw recovery before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_SEC_PER_H     : REAL := 3600.0;    // 小时到秒的时基折算 [s/h] / Seconds per hour [s/h]
    DL_KG_PER_T      : REAL := 1000.0;    // 吨到千克的质量折算 [kg/t] / Kilograms per tonne [kg/t]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_REC_LO_PCT    : REAL := 0.0;       // 回收率物理域下限 [%] / Recovery physical domain low [%]
    DL_REC_HI_PCT    : REAL := 100.0;     // 回收率物理域上限 [%] / Recovery physical domain high [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN/Inf 一律不得流到输出） —— *)
IF NOT (fSecAirNm3h > -DL_BIG AND fSecAirNm3h < DL_BIG)
   OR NOT (fTerAirNm3h > -DL_BIG AND fTerAirNm3h < DL_BIG)
   OR NOT (fSecAirTempC > -DL_BIG AND fSecAirTempC < DL_BIG)
   OR NOT (fTerAirTempC > -DL_BIG AND fTerAirTempC < DL_BIG)
   OR NOT (fAmbientC > -DL_BIG AND fAmbientC < DL_BIG)
   OR NOT (fClinkerTph > -DL_BIG AND fClinkerTph < DL_BIG)
   OR NOT (fClinkerInC > -DL_BIG AND fClinkerInC < DL_BIG)
   OR NOT (fClinkerOutC > -DL_BIG AND fClinkerOutC < DL_BIG)
   OR NOT (fAirCpKjNm3K > -DL_BIG AND fAirCpKjNm3K < DL_BIG)
   OR NOT (fClinkerCpKjKgK > -DL_BIG AND fClinkerCpKjKgK < DL_BIG) THEN
    fRecoveredHeatKw := 0.0;                // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fClinkerHeatKw := 0.0;                  // 熟料显热同样强制 0.0 / Clinker heat forced to zero
    fRecoveryPct := 0.0;                    // 回收率强制 0.0 / Recovery forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GrateCoolerHeatRecoveryCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：比热零闸（R4：除法前先过零闸，且闸的是分母本身） —— *)
IF ABS(fAirCpKjNm3K) <= DL_EPS OR ABS(fClinkerCpKjKgK) <= DL_EPS THEN
    fRecoveredHeatKw := 0.0;                // 比热缺失即无法折算 / No specific heat, no conversion
    fClinkerHeatKw := 0.0;                  // 熟料显热不可算 / Clinker heat not computable
    fRecoveryPct := 0.0;                    // 回收率不可算 / Recovery not computable
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GrateCoolerHeatRecoveryCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不做任何钳制，先出原始值供段 4 判据使用，R24） —— *)
_fSecHeatKjh := fSecAirNm3h * fAirCpKjNm3K * (fSecAirTempC - fAmbientC);          // 二次风显热 [kJ/h]
_fTerHeatKjh := fTerAirNm3h * fAirCpKjNm3K * (fTerAirTempC - fAmbientC);          // 三次风显热 [kJ/h]
_fRecoveredKjh := _fSecHeatKjh + _fTerHeatKjh;                                    // 回收热量合计 [kJ/h]
_fClinkerKjh := fClinkerTph * DL_KG_PER_T * fClinkerCpKjKgK
                * (fClinkerInC - fClinkerOutC);                                   // 熟料可供显热 [kJ/h]

(* —— 段 4：分母零闸（熟料可供显热为回收率的分母） —— *)
IF ABS(_fClinkerKjh) <= DL_EPS THEN
    fRecoveredHeatKw := 0.0;                // 无可供热即无回收率 / No source heat, no recovery
    fClinkerHeatKw := 0.0;                  // 分母侧同步清零 / Denominator side zeroed
    fRecoveryPct := 0.0;                    // 回收率清零 / Recovery zeroed
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GrateCoolerHeatRecoveryCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

_fRecoveryRawPct := _fRecoveredKjh / _fClinkerKjh * DL_PCT;                       // 原始回收率 [%]

(* —— 段 5：物理域与符号校验（判据全部取原始值，单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xValid := (fSecAirNm3h >= 0.0)                                        // 二次风量不得为负
          AND (fTerAirNm3h >= 0.0)                                    // 三次风量不得为负
          AND (fClinkerTph >= 0.0)                                    // 熟料量不得为负
          AND (_fRecoveredKjh >= 0.0)                                 // 风温低于环境温度属非回收工况
          AND (_fClinkerKjh > 0.0)                                    // 熟料出口必须低于入口
          AND (_fRecoveryRawPct >= DL_REC_LO_PCT)                     // 不低于物理域下限
          AND (_fRecoveryRawPct <= DL_REC_HI_PCT);                    // 不高于物理域上限（>100 % 物理不可能）

(* —— 段 6：输出单点写盘（数值钳制到物理域内，有效位已在段 5 定案） —— *)
fRecoveredHeatKw := _fRecoveredKjh / DL_SEC_PER_H;                                        // 折算为 kW
fClinkerHeatKw := _fClinkerKjh / DL_SEC_PER_H;                                            // 折算为 kW
fRecoveryPct := LIMIT(DL_REC_LO_PCT, _fRecoveryRawPct, DL_REC_HI_PCT);                    // 回收率钳 0..100 [%]
FC_DL_GrateCoolerHeatRecoveryCalc := xValid;                                              // 返回码：TRUE = 计算可信

END_FUNCTION
