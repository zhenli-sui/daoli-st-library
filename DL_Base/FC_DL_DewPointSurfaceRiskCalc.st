(*
  Component : FC_DL_DewPointSurfaceRiskCalc
  Category  : DL_Base
  Function  : 表面结露风险：按 Magnus 公式求露点，与表面温度比较并给出裕度与风险等级
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rAmbientC 环境温度 [℃]、rRelHumPct 相对湿度 [%]、rSurfaceC 表面温度 [℃]、
             rMarginWarnK 预警裕度 [K]、rMarginSafeK 安全裕度 [K]；
             输出 rDewPointC 露点温度 [℃]、rMarginK 表面温度减露点 [K]、eRisk 风险等级、
             xValid 有效标志、nFaultCode 故障码。
  边界     : Magnus 系数 a=17.62、b=243.12 [℃]；γ = ln(RH/100) + a·T/(b+T)，露点 Td = b·γ/(a−γ)；
             (a−γ) 为分母须 >1.0E-6（γ 逼近 a 时露点发散）；相对湿度须在 (0,100] [%] 内；
             裕度判级：裕度 < 0 → eRisky（已结露）；< 预警裕度 → eCaution；≥ 安全裕度 → eSafe；
             预警裕度须 ≤ 安全裕度（否则分级区间为空，判 9803）。
  码位     : 9801 输入非有限（故障级）；9802 湿度或分母越域（故障级）；9803 裕度配比越域（故障级）。
*)
TYPE E_DL_DewRisk :
(
    eSafe    := 0,    // 安全：裕度不小于安全裕度 EN: safe, the margin reaches the safe margin
    eCaution := 1,    // 预警：裕度在预警与安全之间 EN: caution, the margin sits between the two limits
    eRisky   := 2     // 危险：裕度不足或已结露 EN: risky, the margin is insufficient or condensation already occurs
);
END_TYPE

FUNCTION FC_DL_DewPointSurfaceRiskCalc : BOOL
VAR_INPUT
    rAmbientC    : LREAL := 30.0;    // 环境温度 [℃] EN: the ambient temperature
    rRelHumPct   : LREAL := 60.0;    // 相对湿度 [%] EN: the relative humidity
    rSurfaceC    : LREAL := 25.0;    // 表面温度 [℃] EN: the surface temperature
    rMarginWarnK : LREAL := 2.0;     // 预警裕度 [K] EN: the warning margin
    rMarginSafeK : LREAL := 5.0;     // 安全裕度 [K] EN: the safe margin
END_VAR
VAR_OUTPUT
    rDewPointC : LREAL;              // 露点温度 [℃] EN: the dew point temperature
    rMarginK   : LREAL;              // 表面温度减露点 [K] EN: the surface temperature minus the dew point
    eRisk      : E_DL_DewRisk;       // 风险等级 EN: the condensation risk level
    xValid     : BOOL;               // 输出可信标志 EN: the outputs are valid
    nFaultCode : INT;                // 0=无故障 9801=输入非有限 9802=湿度或分母越域 9803=裕度配比越域 EN: zero none, 9801 non finite, 9802 humidity or divisor out of range, 9803 margin ordering out of range
END_VAR
VAR
    xFinAll : BOOL;                  // 五输入同时有限 EN: all five inputs are finite
    rRHFrac : LREAL;                 // 相对湿度分数 [-] EN: the relative humidity fraction
    rGamma  : LREAL;                 // Magnus 中间量 γ [-] EN: the Magnus intermediate value
    rDen    : LREAL;                 // 分母 a−γ [-] EN: the divisor, the coefficient minus gamma
    rTd     : LREAL;                 // 露点中间值 [℃] EN: the interim dew point
    rMarg   : LREAL;                 // 裕度中间值 [K] EN: the interim margin
END_VAR
VAR CONSTANT
    DL_DSR_Z      : LREAL := 0.0;     // 浮点零常量 EN: the floating point zero constant
    DL_DSR_HUND   : LREAL := 100.0;   // 百分数换算系数 EN: the percent conversion factor
    DL_DSR_A      : LREAL := 17.62;   // Magnus 系数 a [-] EN: the Magnus coefficient a
    DL_DSR_B      : LREAL := 243.12;  // Magnus 系数 b [℃] EN: the Magnus coefficient b
    DL_DSR_MIN    : LREAL := 1.0E-6;  // 分母下限 EN: the lower bound of the divisor
    DL_DSR_C_BAD  : INT := 9801;      // 输入非有限 EN: a non finite input
    DL_DSR_C_HUM  : INT := 9802;      // 湿度或分母越域 EN: the humidity or the divisor is out of range
    DL_DSR_C_MARG : INT := 9803;      // 裕度配比越域 EN: the margin ordering is out of range
END_VAR

// 段1｜出口预置
FC_DL_DewPointSurfaceRiskCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rDewPointC := DL_DSR_Z;                   // 露点预置零 [℃] EN: preset the dew point to zero
rMarginK := DL_DSR_Z;                     // 裕度预置零 [K] EN: preset the margin to zero
eRisk := E_DL_DewRisk.eRisky;             // 风险等级预置为危险（安全侧缺省） EN: preset the risk to risky on the safe side
xValid := FALSE;                          // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                          // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：五输入全列
xFinAll := (rAmbientC = rAmbientC) AND ((rAmbientC - rAmbientC) = DL_DSR_Z)
        AND (rRelHumPct = rRelHumPct) AND ((rRelHumPct - rRelHumPct) = DL_DSR_Z)
        AND (rSurfaceC = rSurfaceC) AND ((rSurfaceC - rSurfaceC) = DL_DSR_Z)
        AND (rMarginWarnK = rMarginWarnK) AND ((rMarginWarnK - rMarginWarnK) = DL_DSR_Z)
        AND (rMarginSafeK = rMarginSafeK) AND ((rMarginSafeK - rMarginSafeK) = DL_DSR_Z);   // 五输入有限性 EN: the finiteness of all five inputs
IF NOT xFinAll THEN                                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_DSR_C_BAD;                                                              // 非有限码 EN: the non finite code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：湿度 (0,100]、裕度配比 预警 ≤ 安全、Magnus 分母 b+T 必须远离零点
IF (rRelHumPct <= DL_DSR_Z) OR (rRelHumPct > DL_DSR_HUND) THEN                                // 湿度域闸 EN: the humidity domain gate
    nFaultCode := DL_DSR_C_HUM;                                                              // 湿度越域码 EN: the humidity code
    RETURN;                                                                                  // 早退 EN: return early
END_IF
IF (DL_DSR_B + rAmbientC) < DL_DSR_MIN THEN                                                   // b+T 分母闸（防 −243.12 ℃ 处除零） EN: guard the b plus T divisor
    nFaultCode := DL_DSR_C_HUM;                                                              // 越域码 EN: the out of range code
    RETURN;                                                                                  // 早退 EN: return early
END_IF
IF (rMarginWarnK > rMarginSafeK) OR (rMarginWarnK < DL_DSR_Z) THEN                            // 裕度配比闸 EN: the margin ordering gate
    nFaultCode := DL_DSR_C_MARG;                                                             // 配比越域码 EN: the margin ordering code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段4｜主体：Magnus 露点
rRHFrac := rRelHumPct / DL_DSR_HUND;                                                          // 湿度分数 [-] EN: the humidity fraction
rGamma := LN(rRHFrac) + (DL_DSR_A * rAmbientC) / (DL_DSR_B + rAmbientC);                      // γ [-]，分母 b+T 在工程域内恒正 EN: the Magnus intermediate
rDen := DL_DSR_A - rGamma;                                                                    // 分母 a−γ [-] EN: the divisor
IF ABS(rDen) < DL_DSR_MIN THEN                                                                // 分母下限保护 EN: guard the divisor
    nFaultCode := DL_DSR_C_HUM;                                                               // 越域码 EN: the out of range code
    RETURN;                                                                                   // 早退 EN: return early
END_IF
rTd := (DL_DSR_B * rGamma) / rDen;                                                            // 露点 [℃] EN: the dew point
IF rTd <> rTd THEN                                                                            // 结果复检 EN: recheck the result
    nFaultCode := DL_DSR_C_HUM;                                                               // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                   // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段5｜裕度与分级：先算裕度再分级（分级只依赖裕度与两个限值，单源赋值）
// 两个限值已在段3 完成域闸，故分级区间不会出现空集 EN: the two limits passed the gate in section three, so the bands are never empty
rMarg := rSurfaceC - rTd;                                                                     // 裕度 [K] EN: the margin
IF rMarg < DL_DSR_Z THEN                                                                      // 已结露 EN: condensation already occurs
    eRisk := E_DL_DewRisk.eRisky;                                                             // 危险 EN: risky
ELSIF rMarg < rMarginWarnK THEN                                                               // 低于预警裕度 EN: below the warning margin
    eRisk := E_DL_DewRisk.eRisky;                                                             // 危险 EN: risky
ELSIF rMarg < rMarginSafeK THEN                                                               // 预警区间 EN: the caution band
    eRisk := E_DL_DewRisk.eCaution;                                                           // 预警 EN: caution
ELSE
    eRisk := E_DL_DewRisk.eSafe;                                                              // 安全 EN: safe
END_IF

// 段6｜出口
rDewPointC := rTd;                                                                            // 露点出口 [℃] EN: the dew point output
rMarginK := rMarg;                                                                            // 裕度出口 [K] EN: the margin output
xValid := TRUE;                                                                               // 结果可信 EN: the results are valid
FC_DL_DewPointSurfaceRiskCalc := TRUE;                                                        // 返回真 EN: return true
END_FUNCTION
