(*
  Component : FC_DL_InsulationThicknessCalc
  Category  : DL_Base
  Function  : 按单位管长允许热损反求保温层厚度（含表面对流项，不动点迭代 5 次）
  Complexity: C3
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rTiC 管内温度 [℃]、rToC 环境温度 [℃]、rLambdaWmK 保温导热系数 [W/(m·K)]、
             rHWm2K 外表面换热系数 [W/(m2·K)]、rInnerDiaMm 保温内径 [mm]、rQallowWm 允许单位热损 [W/m]；
             输出 rThickMm 所需保温厚度 [mm]、rOuterDiaMm 对应保温外径 [mm]、rQcheckWm 代回校验热损 [W/m]、
             xConverged 迭代收敛、xValid 有效标志、nFaultCode 故障码。
  算法     : 串联热阻方程 ln(r2/r1)/(2πλ) + 1/(2π·h·r2) = ΔT/q 无解析解（r2 同时出现在对数与分母），
             故用不动点迭代：r2(k+1) = r1 × exp( 2πλ × (R目标 − 1/(2π·h·r2(k))) )，初值 r2(0)=2·r1，
             固定迭代 5 次（本件迭代次数为常量，不设输入引脚，避免引脚越多验证面越大）。
             收敛判据：代回热损相对误差 ≤1% 判收敛；不收敛仍输出最后一轮值并置 xConverged=FALSE（信息级）。
  边界     : r1 须 >1.0E-4 [mm]、λ 与 h 须 >0、ΔT 须 >0、允许热损须 >0；
             迭代中 r2 若跌破 r1（热阻方程无正解，通常因允许热损大于裸管散热）判 9802。
  码位     : 9801 输入非有限（故障级）；9802 参数越域或无正解（故障级）。
*)
FUNCTION FC_DL_InsulationThicknessCalc : BOOL
VAR_INPUT
    rTiC        : LREAL := 150.0;    // 管内介质温度 [℃] EN: the medium temperature inside the pipe
    rToC        : LREAL := 25.0;     // 环境温度 [℃] EN: the ambient temperature
    rLambdaWmK  : LREAL := 0.045;    // 保温材料导热系数 [W/(m·K)] EN: the thermal conductivity of the insulation
    rHWm2K      : LREAL := 10.0;     // 外表面换热系数 [W/(m2·K)] EN: the outer surface heat transfer coefficient
    rInnerDiaMm : LREAL := 108.0;    // 保温内径（管外径） [mm] EN: the insulation inner diameter, the pipe outer diameter
    rQallowWm   : LREAL := 40.0;     // 允许单位管长热损 [W/m] EN: the allowed heat loss per metre of pipe
END_VAR
VAR_OUTPUT
    rThickMm    : LREAL;             // 所需保温厚度 [mm] EN: the required insulation thickness
    rOuterDiaMm : LREAL;             // 对应保温外径 [mm] EN: the corresponding insulation outer diameter
    rQcheckWm   : LREAL;             // 代回校验的单位热损 [W/m] EN: the heat loss recomputed from the found thickness
    xConverged  : BOOL;              // 迭代收敛（信息级） EN: the iteration converged, information class only
    xValid      : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;               // 0=无故障 9801=输入非有限 9802=参数越域或无正解 EN: zero none, 9801 non finite, 9802 parameters out of range or no positive solution
END_VAR
VAR
    xFinAll : BOOL;                  // 六个浮点入参有限 EN: all six floating inputs are finite
    i       : INT;                   // 迭代计数 [次] EN: the iteration counter
    rR1     : LREAL;                 // 内半径 [m] EN: the inner radius in metres
    rR2     : LREAL;                 // 外半径迭代值 [m] EN: the iterated outer radius
    rRprev  : LREAL;                 // 上一轮外半径 [m] EN: the previous outer radius
    rRtgt   : LREAL;                 // 目标总热阻 [m·K/W] EN: the target total resistance
    rRes    : LREAL;                 // 代回总热阻 [m·K/W] EN: the recomputed total resistance
    rQ      : LREAL;                 // 代回热损 [W/m] EN: the recomputed heat loss
    rErr    : LREAL;                 // 相对误差 [-] EN: the relative error
END_VAR
VAR CONSTANT
    DL_ITC_Z       : LREAL := 0.0;                  // 浮点零常量 EN: the floating point zero constant
    DL_ITC_TWO     : LREAL := 2.0;                  // 直径转半径与初值倍数 EN: the factor used for the radius and the initial guess
    DL_ITC_PI2     : LREAL := 6.2831853071795865;   // 2π（LREAL 精度） [-] EN: twice the circle ratio at LREAL precision
    DL_ITC_K1000   : LREAL := 1000.0;               // 米转毫米系数 EN: the metre to millimetre factor
    DL_ITC_ITER    : INT := 5;                      // 固定迭代次数 [次] EN: the fixed iteration count
    DL_ITC_TOL     : LREAL := 0.01;                 // 收敛相对容差 [-] EN: the convergence tolerance
    DL_ITC_MIN     : LREAL := 1.0E-4;               // 半径下限 [mm] EN: the lower bound of the radius
    DL_ITC_C_BAD   : INT := 9801;                   // 输入非有限 EN: a non finite input
    DL_ITC_C_RANGE : INT := 9802;                   // 参数越域或无正解 EN: parameters out of range or no positive solution
END_VAR

// 段1｜出口预置
FC_DL_InsulationThicknessCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rThickMm := DL_ITC_Z;                     // 厚度预置零 [mm] EN: preset the thickness to zero
rOuterDiaMm := DL_ITC_Z;                  // 外径预置零 [mm] EN: preset the outer diameter to zero
rQcheckWm := DL_ITC_Z;                    // 校验热损预置零 [W/m] EN: preset the checked loss to zero
xConverged := FALSE;                      // 收敛标志预置假 EN: preset the convergence flag to false
xValid := FALSE;                          // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                          // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：六输入全列
xFinAll := (rTiC = rTiC) AND ((rTiC - rTiC) = DL_ITC_Z)
        AND (rToC = rToC) AND ((rToC - rToC) = DL_ITC_Z)
        AND (rLambdaWmK = rLambdaWmK) AND ((rLambdaWmK - rLambdaWmK) = DL_ITC_Z)
        AND (rHWm2K = rHWm2K) AND ((rHWm2K - rHWm2K) = DL_ITC_Z)
        AND (rInnerDiaMm = rInnerDiaMm) AND ((rInnerDiaMm - rInnerDiaMm) = DL_ITC_Z)
        AND (rQallowWm = rQallowWm) AND ((rQallowWm - rQallowWm) = DL_ITC_Z);   // 六输入有限性 EN: the finiteness of all six inputs
IF NOT xFinAll THEN                                                             // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_ITC_C_BAD;                                                 // 非有限码 EN: the non finite code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段3｜域闸：几何与物性参数正值、温差为正（反向传热无解）
rR1 := (rInnerDiaMm / DL_ITC_TWO) / DL_ITC_K1000;                                // 内半径折米 [m] EN: the inner radius in metres
IF (rInnerDiaMm < DL_ITC_MIN) OR (rLambdaWmK <= DL_ITC_Z) OR (rHWm2K <= DL_ITC_Z)
   OR (rQallowWm <= DL_ITC_Z) OR ((rTiC - rToC) <= DL_ITC_Z) THEN
    nFaultCode := DL_ITC_C_RANGE;                                                // 越域码 EN: the out of range code
    RETURN;                                                                      // 早退 EN: return early
END_IF

// 段4｜目标总热阻与不动点迭代（初值 r2 = 2·r1，固定 5 轮）
rRtgt := (rTiC - rToC) / rQallowWm;                                              // 目标总热阻 [m·K/W] EN: the target total resistance
rR2 := DL_ITC_TWO * rR1;                                                         // 迭代初值 [m] EN: the initial guess
FOR i := 1 TO DL_ITC_ITER DO                                                     // 固定 5 轮，计数器常量化 EN: five fixed rounds
    rRprev := rR2;                                                               // 记上一轮 [m] EN: keep the previous value
    IF (rRprev < DL_ITC_MIN) OR (ABS(rRprev) < DL_ITC_MIN) THEN                  // 迭代值失效保护 EN: guard the iterated value
        rR2 := DL_ITC_TWO * rR1;                                                 // 退回初值 [m] EN: fall back to the initial guess
    ELSE
        rR2 := rR1 * EXP(DL_ITC_PI2 * rLambdaWmK * (rRtgt - (1.0 / (DL_ITC_PI2 * rHWm2K * rRprev))));   // 不动点更新 [m] EN: the fixed point update
    END_IF
    IF rR2 <= rR1 THEN                                                           // 无正解保护：外半径必须大于内半径 EN: the outer radius must exceed the inner one
        nFaultCode := DL_ITC_C_RANGE;                                            // 无正解码 EN: the no positive solution code
        RETURN;                                                                  // 早退 EN: return early
    END_IF
END_FOR

// 段5｜代回校验：q = ΔT / (ln(r2/r1)/(2πλ) + 1/(2π·h·r2))
rRes := LN(rR2 / rR1) / (DL_ITC_PI2 * rLambdaWmK) + (1.0 / (DL_ITC_PI2 * rHWm2K * rR2));   // 代回总热阻 [m·K/W] EN: the recomputed total resistance
IF ABS(rRes) < DL_ITC_TOL THEN                                                             // 热阻下限保护 EN: guard the resistance magnitude
    nFaultCode := DL_ITC_C_RANGE;                                                          // 越域码 EN: the out of range code
    RETURN;                                                                                // 早退 EN: return early
END_IF
rQ := (rTiC - rToC) / rRes;                                                                // 代回热损 [W/m] EN: the recomputed heat loss
rErr := ABS(rQ - rQallowWm) / rQallowWm;                                                    // 相对误差 [-] EN: the relative error
xConverged := rErr <= DL_ITC_TOL;                                                           // 收敛判据（信息级） EN: the convergence verdict, information class only

// 段6｜出口：厚度与热损两出口同源
rThickMm := (rR2 - rR1) * DL_ITC_K1000;                                                     // 所需厚度 [mm] EN: the required thickness
rOuterDiaMm := DL_ITC_TWO * rR2 * DL_ITC_K1000;                                             // 对应外径 [mm] EN: the outer diameter
rQcheckWm := rQ;                                                                            // 校验热损出口 [W/m] EN: the checked loss output
IF rThickMm <= DL_ITC_Z THEN                                                                // 厚度非正判无解 EN: a non positive thickness means no solution
    nFaultCode := DL_ITC_C_RANGE;                                                           // 无正解码 EN: the no solution code
    RETURN;                                                                                 // 早退（返回假） EN: return false
END_IF
xValid := TRUE;                                                                             // 结果可信 EN: the results are valid
FC_DL_InsulationThicknessCalc := TRUE;                                                       // 返回真 EN: return true
END_FUNCTION
