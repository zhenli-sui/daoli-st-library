// FC_DL_DewPointSpreadCalc v1.0.0
(*==============================================================================
 * 功能描述: 露点温差计算。fSpreadK = 干球温度 - 露点温度 [K]；负值物理无效
 *           （露点不可能高于干球）→ bValid=FALSE 并返回饱和零域；任一输入非有限
 *           同样无效。
 * 接口契约: 输入 fTempC/fDewPointC [°C]；输出 bValid 回执，返回温差 [K]。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_DewPointSpreadCalc : REAL
VAR_INPUT
    fTempC      : REAL := 20.0;   // 干球温度 [°C] / Dry-bulb temperature [degC]
    fDewPointC  : REAL := 10.0;   // 露点温度 [°C] / Dew-point temperature [degC]
END_VAR
VAR_OUTPUT
    bValid : BOOL;                // 结果有效回执 [-] / Result validity receipt
END_VAR

(* —— 段 0：全路径赋值缺省（无效安全侧） —— *)
bValid := FALSE;                             // 有效回执预清 / Validity preset
FC_DL_DewPointSpreadCalc := 0.0;             // 返回值缺省零 / Result default zero

(* —— 段 1：非有限闸（NaN 自反判） —— *)
IF (fTempC <> fTempC) OR (fDewPointC <> fDewPointC) THEN   // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF

(* —— 段 2：温差换算与物理域校验（负温差判无效，浮点容差口径） —— *)
IF (fTempC - fDewPointC) < 0.0 THEN          // 负温差物理无效（露点高于干球） / Negative spread physically invalid
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF
FC_DL_DewPointSpreadCalc := fTempC - fDewPointC;   // 露点温差 [K] / Dew-point spread [K]
bValid := TRUE;                              // 有效回执 / Validity receipt

END_FUNCTION
