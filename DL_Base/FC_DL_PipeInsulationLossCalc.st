(*
  Component : FC_DL_PipeInsulationLossCalc
  Category  : DL_Base
  Function  : 圆筒管道保温散热 q = 2πλ(Ti−To)/ln(r2/r1)，单位 W/m
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rTiC 管内介质温度 [℃]、rToC 环境温度 [℃]、rLambdaWmK 保温材料导热系数 [W/(m·K)]、
             rInnerDiaMm 管道外径（保温内径） [mm]、rThickMm 保温层厚度 [mm]；
             输出 rQwm 单位管长热损 [W/m]、rQTotalW 给定管长总热损 [W]、rOuterDiaMm 保温外径 [mm]、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 半径比 r2/r1 为无量纲量，故内外径可用 [mm] 直接参与对数（无需折米）；
             r1 须 >1.0E-6 [mm]、r2 须 > r1（厚度 >0）；ln(r2/r1) 须 >1.0E-9；
             导热系数须 >0；管长 rLengthM 用于总热损，为 0 时总热损输出 0（不判故障）。
  码位     : 9801 输入非有限（故障级）；9802 半径比或导热系数越域（故障级）。
*)
FUNCTION FC_DL_PipeInsulationLossCalc : BOOL
VAR_INPUT
    rTiC        : LREAL := 150.0;     // 管内介质温度 [℃] EN: the medium temperature inside the pipe
    rToC        : LREAL := 25.0;      // 环境温度 [℃] EN: the ambient temperature
    rLambdaWmK  : LREAL := 0.045;     // 保温材料导热系数 [W/(m·K)] EN: the thermal conductivity of the insulation
    rInnerDiaMm : LREAL := 108.0;     // 管道外径即保温内径 [mm] EN: the pipe outer diameter acting as the insulation inner diameter
    rThickMm    : LREAL := 50.0;      // 保温层厚度 [mm] EN: the insulation thickness
    rLengthM    : LREAL := 10.0;      // 参与总热损的管长 [m] EN: the pipe length used for the total loss
END_VAR
VAR_OUTPUT
    rQwm       : LREAL;               // 单位管长热损 [W/m] EN: the heat loss per metre of pipe
    rQTotalW   : LREAL;               // 管长总热损 [W] EN: the total heat loss over the given length
    rOuterDiaMm: LREAL;               // 保温外径 [mm] EN: the insulation outer diameter
    xValid     : BOOL;                // 输出可信标志 EN: the outputs are valid
    nFaultCode : INT;                 // 0=无故障 9801=输入非有限 9802=半径比或导热系数越域 EN: zero none, 9801 non finite, 9802 radius ratio or conductivity out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 六个浮点入参有限 EN: all six floating inputs are finite
    rR1     : LREAL;                  // 保温内半径 [mm] EN: the insulation inner radius
    rR2     : LREAL;                  // 保温外半径 [mm] EN: the insulation outer radius
    rRat    : LREAL;                  // 半径比 r2/r1 [-] EN: the radius ratio
    rLn     : LREAL;                  // 半径比对数 [-] EN: the logarithm of the radius ratio
    rQ      : LREAL;                  // 单位热损中间值 [W/m] EN: the interim loss per metre
END_VAR
VAR CONSTANT
    DL_PIL_Z       : LREAL := 0.0;                  // 浮点零常量 EN: the floating point zero constant
    DL_PIL_TWO     : LREAL := 2.0;                  // 直径转半径系数 EN: the diameter to radius factor
    DL_PIL_PI2     : LREAL := 6.2831853071795865;   // 2π（LREAL 精度） [-] EN: twice the circle ratio at LREAL precision
    DL_PIL_MIN     : LREAL := 1.0E-9;               // 对数与半径的下限 EN: the lower bound of the logarithm and the radius
    DL_PIL_C_BAD   : INT := 9801;                   // 输入非有限 EN: a non finite input
    DL_PIL_C_RANGE : INT := 9802;                   // 半径比或导热系数越域 EN: the radius ratio or the conductivity is out of range
END_VAR

// 段1｜出口预置
FC_DL_PipeInsulationLossCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rQwm := DL_PIL_Z;                        // 单位热损预置零 [W/m] EN: preset the loss per metre to zero
rQTotalW := DL_PIL_Z;                    // 总热损预置零 [W] EN: preset the total loss to zero
rOuterDiaMm := DL_PIL_Z;                 // 外径预置零 [mm] EN: preset the outer diameter to zero
xValid := FALSE;                         // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                         // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：六输入全列
xFinAll := (rTiC = rTiC) AND ((rTiC - rTiC) = DL_PIL_Z)
        AND (rToC = rToC) AND ((rToC - rToC) = DL_PIL_Z)
        AND (rLambdaWmK = rLambdaWmK) AND ((rLambdaWmK - rLambdaWmK) = DL_PIL_Z)
        AND (rInnerDiaMm = rInnerDiaMm) AND ((rInnerDiaMm - rInnerDiaMm) = DL_PIL_Z)
        AND (rThickMm = rThickMm) AND ((rThickMm - rThickMm) = DL_PIL_Z)
        AND (rLengthM = rLengthM) AND ((rLengthM - rLengthM) = DL_PIL_Z);   // 六输入有限性 EN: the finiteness of all six inputs
IF NOT xFinAll THEN                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_PIL_C_BAD;                                              // 非有限码 EN: the non finite code
    RETURN;                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：内半径为分母须够大、厚度为正、导热系数为正、管长非负
rR1 := rInnerDiaMm / DL_PIL_TWO;                                             // 保温内半径 [mm] EN: the insulation inner radius
rR2 := rR1 + rThickMm;                                                       // 保温外半径 [mm] EN: the insulation outer radius
rOuterDiaMm := rInnerDiaMm + DL_PIL_TWO * rThickMm;                          // 保温外径 [mm] EN: the insulation outer diameter
IF (rR1 < DL_PIL_MIN) OR (rThickMm <= DL_PIL_Z) OR (rLambdaWmK <= DL_PIL_Z) OR (rLengthM < DL_PIL_Z) THEN
    nFaultCode := DL_PIL_C_RANGE;                                            // 越域码 EN: the out of range code
    RETURN;                                                                  // 早退 EN: return early
END_IF

// 段4｜主体：q = 2πλΔT / ln(r2/r1)
rRat := rR2 / rR1;                                                           // 半径比，分母已过下限 [-] EN: the radius ratio, the divisor passed the gate
rLn := LN(rRat);                                                             // 半径比对数 [-] EN: the logarithm of the radius ratio
IF ABS(rLn) < DL_PIL_MIN THEN                                                // 对数下限（厚度趋零） EN: the logarithm gate for a vanishing thickness
    nFaultCode := DL_PIL_C_RANGE;                                            // 越域码 EN: the out of range code
    RETURN;                                                                  // 早退 EN: return early
END_IF
rQ := (DL_PIL_PI2 * rLambdaWmK * (rTiC - rToC)) / rLn;                        // 单位管长热损，正负随温差 [W/m] EN: the loss per metre carrying the temperature difference sign

// 段5｜结果复检与出口
IF rQ <> rQ THEN                                                             // 复检：非有限 EN: recheck for a non finite value
    nFaultCode := DL_PIL_C_RANGE;                                            // 复检失败码 EN: the recheck failure code
    RETURN;                                                                  // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rQwm := rQ;                                                                  // 单位热损出口 [W/m] EN: the loss per metre output
rQTotalW := rQ * rLengthM;                                                   // 总热损 = 单位热损 × 管长 [W] EN: the total loss over the length
xValid := TRUE;                                                              // 结果可信 EN: the results are valid
FC_DL_PipeInsulationLossCalc := TRUE;                                         // 返回真 EN: return true
END_FUNCTION
