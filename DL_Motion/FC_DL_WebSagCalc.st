(*
  Component : FC_DL_WebSagCalc
  Category  : DL_Motion
  Function  : 卷材跨距垂度（悬链近似）sag = w·g·L²/(8T)，并给出垂度上限判定
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rSpanM 跨距（两支撑点间距） [m]、rLinearDensityKgM 卷材线密度 [kg/m]、
             rTensionN 带材张力 [N]、rSagMaxMm 垂度允许上限 [mm]；
             输出 rSagMm 垂度 [mm]、rSagRatioPct 垂度占跨距百分比 [%]、
             xSagHigh 超上限（信息级）、xValid 有效标志、nFaultCode 故障码。
  边界     : 张力为分母须 >1.0E-6 [N]（张力趋零垂度发散，悬链近似失效）；跨距与线密度须 ≥0；
             重力加速度取 9.80665 [m/s2]；垂度小于跨距的 1/8 时悬链近似误差 <2%，超出时仅作趋势参考。
  码位     : 9801 输入非有限（故障级）；9802 张力过小或跨距/线密度为负（故障级）。
*)
FUNCTION FC_DL_WebSagCalc : BOOL
VAR_INPUT
    rSpanM           : LREAL := 3.0;      // 跨距 [m] EN: the span between the two supports
    rLinearDensityKgM: LREAL := 0.5;      // 卷材线密度 [kg/m] EN: the linear density of the web
    rTensionN        : LREAL := 500.0;    // 带材张力 [N] EN: the web tension
    rSagMaxMm        : LREAL := 10.0;     // 垂度允许上限 [mm] EN: the allowed upper bound of the sag
END_VAR
VAR_OUTPUT
    rSagMm      : LREAL;                  // 垂度 [mm] EN: the sag in millimetres
    rSagRatioPct: LREAL;                  // 垂度占跨距百分比 [%] EN: the sag expressed as a percent of the span
    xSagHigh    : BOOL;                   // 超垂度上限（信息级） EN: above the sag limit, information class only
    xValid      : BOOL;                   // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;                    // 0=无故障 9801=输入非有限 9802=张力过小或参数越域 EN: zero none, 9801 non finite, 9802 tension too small or parameters out of range
END_VAR
VAR
    xFinAll : BOOL;                       // 四输入同时有限 EN: all four inputs are finite
    rDen    : LREAL;                      // 分母 8T [N] EN: the divisor, eight times the tension
    rSagM   : LREAL;                      // 垂度中间值 [m] EN: the interim sag in metres
    rRatio  : LREAL;                      // 垂度比 [%] EN: the sag ratio in percent
END_VAR
VAR CONSTANT
    DL_WSC_Z       : LREAL := 0.0;        // 浮点零常量 EN: the floating point zero constant
    DL_WSC_G       : LREAL := 9.80665;    // 标准重力加速度 [m/s2] EN: the standard gravity acceleration
    DL_WSC_EIGHT   : LREAL := 8.0;        // 悬链近似几何系数 EN: the geometric factor of the catenary approximation
    DL_WSC_K1000   : LREAL := 1000.0;     // 米转毫米系数 EN: the metre to millimetre factor
    DL_WSC_HUNDRED : LREAL := 100.0;      // 百分数换算系数 EN: the percent conversion factor
    DL_WSC_MIN     : LREAL := 1.0E-6;     // 张力下限 [N] EN: the lower bound of the tension
    DL_WSC_C_BAD   : INT := 9801;         // 输入非有限 EN: a non finite input
    DL_WSC_C_RANGE : INT := 9802;         // 张力过小或参数越域 EN: the tension is too small or the parameters are out of range
END_VAR

// 段1｜出口预置
FC_DL_WebSagCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rSagMm := DL_WSC_Z;          // 垂度预置零 [mm] EN: preset the sag to zero
rSagRatioPct := DL_WSC_Z;    // 垂度比预置零 [%] EN: preset the sag ratio to zero
xSagHigh := FALSE;           // 超限标志预置假 EN: preset the over sag flag to false
xValid := FALSE;             // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;             // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四输入全列（上限参与出口判据）
xFinAll := (rSpanM = rSpanM) AND ((rSpanM - rSpanM) = DL_WSC_Z)
        AND (rLinearDensityKgM = rLinearDensityKgM) AND ((rLinearDensityKgM - rLinearDensityKgM) = DL_WSC_Z)
        AND (rTensionN = rTensionN) AND ((rTensionN - rTensionN) = DL_WSC_Z)
        AND (rSagMaxMm = rSagMaxMm) AND ((rSagMaxMm - rSagMaxMm) = DL_WSC_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                             // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WSC_C_BAD;                                                 // 非有限码 EN: the non finite code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段3｜域闸：张力过分母下限、跨距与线密度非负
rDen := DL_WSC_EIGHT * rTensionN;                                              // 分母 8T [N] EN: the divisor
IF (ABS(rDen) < DL_WSC_MIN) OR (rSpanM < DL_WSC_Z) OR (rLinearDensityKgM < DL_WSC_Z) THEN
    nFaultCode := DL_WSC_C_RANGE;                                              // 越域码 EN: the out of range code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段4｜主体：sag = w·g·L²/(8T)
rSagM := (rLinearDensityKgM * DL_WSC_G * rSpanM * rSpanM) / rDen;              // 垂度 [m] EN: the sag in metres
rSagMm := rSagM * DL_WSC_K1000;                                                // 垂度 [mm] EN: the sag in millimetres
IF (rSagMm <> rSagMm) OR (rSagMm < DL_WSC_Z) THEN                              // 结果复检 EN: recheck the result
    nFaultCode := DL_WSC_C_RANGE;                                              // 复检失败码 EN: the recheck failure code
    RETURN;                                                                     // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段5｜垂度占跨距百分比：跨距为零时不可比，给零
IF rSpanM > DL_WSC_MIN THEN                                                    // 跨距有效 EN: the span is usable
    rRatio := (rSagM / rSpanM) * DL_WSC_HUNDRED;                               // 垂度比 [%] EN: the sag ratio
ELSE
    rRatio := DL_WSC_Z;                                                        // 不可比给零 [%] EN: give zero when not comparable
END_IF

// 段6｜出口（垂度值在段4 已写入出口，此处只落定比值与超限判据，避免自赋值死语句）
rSagRatioPct := rRatio;                                                        // 垂度比出口 [%] EN: the sag ratio output
xSagHigh := rSagMm > rSagMaxMm;                                                // 超限判据（信息级） EN: the over sag test, information class only
xValid := TRUE;                                                               // 结果可信 EN: the results are valid
FC_DL_WebSagCalc := TRUE;                                                     // 返回真 EN: return true
END_FUNCTION
