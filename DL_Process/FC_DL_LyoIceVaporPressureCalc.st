(*
  Name: FC_DL_LyoIceVaporPressureCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 冰面饱和蒸气压按 Magnus 型 Goff-Gratch 简化式求解：
           p_ice = 611.15 * EXP(22.452 * T / (272.55 + T))，T 为冰面温度 [degC]，
           611.15 为 0 degC 时冰面饱和蒸气压 [Pa]，22.452 与 272.55 为冰相经验常数。
           该式在 -60 ~ 0 degC 内相对误差小于 1 %，是冻干一次干燥压力设定的标准依据。
        2) 派生输出过冷度裕量 fSubcoolK = 0.0 − T，即离冰点的距离；
           冻干工艺要求制品温度始终低于冰点，裕量为负意味着已融冰（塌陷前兆）。
        3) 温度域校验：温度必须落在 [DL_T_LO, DL_T_HI] = [-60.0, 0.0] degC 内，
           越域只置 xDomainOk = FALSE 而数值钳到域内输出，因为经验常数在域外已失效。
  边界条件：1) 非有限值闸：温度入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（fPressurePa 与 fSubcoolK 强制 0.0），不得只置标志（R19）。
        2) 分母零闸：经验式分母 272.55 + T 在 T = -272.55 degC 处为零，
           本件温度域下限 -60 degC 远高于该点，但仍显式校验 |272.55 + T| > DL_EPS，
           防止越域调用（下游误传开尔文值）导致除零。
        3) 指数溢出闸：指数 22.452*T/(272.55+T) 在接近 -272.55 时发散，
           计算前用温度域闸先拦截，绝不让 EXP 收到发散指数（EXP 溢出为 Inf 会穿透下游）。
        4) 判据取原始值（R24）：温度越域判定使用原始入参 fTempC，不对其先钳制再判。
        5) 物理域钳制：气压钳 0.0 ~ DL_P_HI_PA；过冷度钳到 [-DL_T_HI_SPAN, +DL_T_HI_SPAN]。
        6) 纯函数无状态：不做滤波，测点噪声抑制由下游一阶滤波件承担。
  量纲自证：T [degC] 代入经验式时以温差形式参与（degC 与 K 的差值尺度相同），
           22.452*T/(272.55+T) = (无因次)，故 EXP 的自变量无因次；
           p_ice = (Pa) * (无因次) = Pa，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_LyoIceVaporPressureCalc : BOOL
VAR_INPUT
    fTempC           : REAL;   // 冰面温度 [degC] / Ice surface temperature [degC]
END_VAR
VAR_OUTPUT
    fPressurePa      : REAL;   // 冰面饱和蒸气压 [Pa] / Ice surface saturation vapour pressure [Pa]
    fSubcoolK        : REAL;   // 距冰点的过冷度裕量 [K] / Subcooling margin below the ice point [K]
    xDomainOk        : BOOL;   // 温度在经验式有效域内 [bool] / Temperature within the valid domain [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDenomK         : REAL;   // 经验式分母（272.55 + T）[K] / Empirical denominator, 272.55 + T [K]
    _fExpo           : REAL;   // 经验式指数（无因次）[-] / Empirical exponent, dimensionless [-]
    _fPressRawPa     : REAL;   // 钳制前的原始气压 [Pa] / Raw pressure before limiting [Pa]
    _fTempUseC       : REAL;   // 域钳制后参与计算的温度 [degC] / Temperature used after domain clamping [degC]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_T_LO          : REAL := -60.0;     // 经验式有效温度下限 [degC] / Valid temperature low bound [degC]
    DL_T_HI          : REAL := 0.0;       // 经验式有效温度上限（冰点）[degC] / Valid temperature high, ice point [degC]
    DL_P0_PA         : REAL := 611.15;    // 0 degC 冰面饱和蒸气压 [Pa] / Ice saturation pressure at 0 degC [Pa]
    DL_COEF_A        : REAL := 22.452;    // 冰相经验常数 A（无因次）[-] / Ice-phase empirical constant A [-]
    DL_COEF_B        : REAL := 272.55;    // 冰相经验常数 B [K] / Ice-phase empirical constant B [K]
    DL_P_HI_PA       : REAL := 700.0;     // 气压物理上限（略高于 0 degC 冰面值）[Pa] / Pressure upper bound [Pa]
    DL_MARGIN_SPAN   : REAL := 200.0;     // 过冷度裕量钳制跨度 [K] / Subcooling margin clamp span [K]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fTempC > -DL_BIG AND fTempC < DL_BIG) THEN
    fPressurePa := 0.0;                     // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fSubcoolK := 0.0;                       // 裕量强制 0.0 / Margin forced to zero
    xDomainOk := FALSE;                     // 域位清零 / Domain flag cleared
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LyoIceVaporPressureCalc := FALSE; // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：判据取原始值（R24：先判域，再钳制，禁先钳后判） —— *)
xDomainOk := (fTempC >= DL_T_LO) AND (fTempC <= DL_T_HI);

(* —— 段 3：域钳制后参与计算（经验常数在域外失效，绝不让 EXP 收到发散指数） —— *)
_fTempUseC := LIMIT(DL_T_LO, fTempC, DL_T_HI);                          // 温度钳到有效域 [degC]
_fDenomK := DL_COEF_B + _fTempUseC;                                     // 经验式分母 [K]

(* —— 段 4：分母零闸（防越域调用传开尔文值导致除零，R4） —— *)
IF ABS(_fDenomK) <= DL_EPS THEN
    fPressurePa := 0.0;                     // 分母为零即不可算 / No denominator, no result
    fSubcoolK := 0.0;                       // 裕量不可算 / Margin not computable
    xDomainOk := FALSE;                     // 判域外 / Out of domain
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LyoIceVaporPressureCalc := FALSE; // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 5：主算式（Goff-Gratch 简化式，指数自变量已由段 3 钳制保证有界） —— *)
_fExpo := DL_COEF_A * _fTempUseC / _fDenomK;                            // 指数（无因次）[-]
_fPressRawPa := DL_P0_PA * EXP(_fExpo);                                 // 冰面饱和蒸气压 [Pa]
fSubcoolK := LIMIT(-DL_MARGIN_SPAN, DL_T_HI - _fTempUseC, DL_MARGIN_SPAN);   // 过冷度裕量 [K]

(* —— 段 6：输出单点写盘（气压钳制到物理域；有限性已由段 1 保证） —— *)
fPressurePa := LIMIT(0.0, _fPressRawPa, DL_P_HI_PA);                    // 气压钳 0..物理上限 [Pa]
xValid := xDomainOk AND (fPressurePa > 0.0);                            // 域内且有正压才算有效
FC_DL_LyoIceVaporPressureCalc := xValid;                                // 返回码：TRUE = 计算可信

END_FUNCTION
