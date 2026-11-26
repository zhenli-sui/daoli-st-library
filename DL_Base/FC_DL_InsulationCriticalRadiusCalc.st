(*
  Component : FC_DL_InsulationCriticalRadiusCalc
  Category  : DL_Base
  Function  : 临界保温半径 rc = λ/h，并判定当前外径下加保温是否真的减少散热
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rLambdaWmK 保温材料导热系数 [W/(m·K)]、rHWm2K 表面换热系数 [W/(m2·K)]、
             rOuterRadiusMm 当前保温外半径 [mm]；
             输出 rCritRadiusMm 临界半径 [mm]、xEffective 加保温有效（外半径 ≥ 临界半径）、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 换热系数为分母须 >1.0E-6 [W/(m2·K)]；导热系数须 >0；外半径须 ≥0；
             临界半径判据针对小管径场景：外半径小于临界半径时，增加保温反而使散热增大，
             此时 xEffective=FALSE（信息级，不置故障）。
  码位     : 9801 输入非有限（故障级）；9802 换热系数或导热系数越域（故障级）。
*)
FUNCTION FC_DL_InsulationCriticalRadiusCalc : BOOL
VAR_INPUT
    rLambdaWmK    : LREAL := 0.045;   // 保温材料导热系数 [W/(m·K)] EN: the thermal conductivity of the insulation
    rHWm2K        : LREAL := 10.0;    // 表面换热系数 [W/(m2·K)] EN: the surface heat transfer coefficient
    rOuterRadiusMm: LREAL := 80.0;    // 当前保温外半径 [mm] EN: the current insulation outer radius
END_VAR
VAR_OUTPUT
    rCritRadiusMm : LREAL;            // 临界保温半径 [mm] EN: the critical insulation radius
    xEffective    : BOOL;             // 加保温对散热有效 EN: the insulation reduces the heat loss
    xValid        : BOOL;             // 输出可信标志 EN: the outputs are valid
    nFaultCode    : INT;              // 0=无故障 9801=输入非有限 9802=换热或导热系数越域 EN: zero none, 9801 non finite, 9802 transfer coefficient or conductivity out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 三输入同时有限 EN: all three inputs are finite
    rDen    : LREAL;                  // 分母（换热系数） [W/(m2·K)] EN: the divisor, the heat transfer coefficient
    rCrit   : LREAL;                  // 临界半径中间值 [mm] EN: the interim critical radius
END_VAR
VAR CONSTANT
    DL_ICR_Z     : LREAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_ICR_K1000 : LREAL := 1000.0;   // 米转毫米系数 EN: the metre to millimetre factor
    DL_ICR_MIN   : LREAL := 1.0E-6;   // 换热系数下限 EN: the lower bound of the heat transfer coefficient
    DL_ICR_C_BAD : INT := 9801;       // 输入非有限 EN: a non finite input
    DL_ICR_C_RANG: INT := 9802;       // 换热或导热系数越域 EN: the transfer coefficient or the conductivity is out of range
END_VAR

// 段1｜出口预置
FC_DL_InsulationCriticalRadiusCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rCritRadiusMm := DL_ICR_Z;                     // 临界半径预置零 [mm] EN: preset the critical radius to zero
xEffective := FALSE;                           // 有效保温标志预置假 EN: preset the effective flag to false
xValid := FALSE;                               // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                               // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三输入全列
xFinAll := (rLambdaWmK = rLambdaWmK) AND ((rLambdaWmK - rLambdaWmK) = DL_ICR_Z)
        AND (rHWm2K = rHWm2K) AND ((rHWm2K - rHWm2K) = DL_ICR_Z)
        AND (rOuterRadiusMm = rOuterRadiusMm) AND ((rOuterRadiusMm - rOuterRadiusMm) = DL_ICR_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                                                  // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_ICR_C_BAD;                                                                      // 非有限码 EN: the non finite code
    RETURN;                                                                                          // 早退 EN: return early
END_IF

// 段3｜域闸：换热系数过分母下限、导热系数为正、外半径非负
rDen := rHWm2K;                                                                                       // 取分母 [W/(m2·K)] EN: take the divisor
IF (ABS(rDen) < DL_ICR_MIN) OR (rLambdaWmK <= DL_ICR_Z) OR (rOuterRadiusMm < DL_ICR_Z) THEN            // 域闸 EN: the domain gate
    nFaultCode := DL_ICR_C_RANG;                                                                      // 越域码 EN: the out of range code
    RETURN;                                                                                            // 早退 EN: return early
END_IF

// 段4｜主体：rc = λ/h（单位 m），折毫米输出
rCrit := (rLambdaWmK / rDen) * DL_ICR_K1000;                                                           // 临界半径 [mm] EN: the critical radius in millimetres
IF (rCrit <> rCrit) OR (rCrit < DL_ICR_Z) THEN                                                         // 结果复检 EN: recheck the result
    nFaultCode := DL_ICR_C_RANG;                                                                       // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                            // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段5｜出口：外半径不小于临界半径才判「加保温有效」
rCritRadiusMm := rCrit;                                                                                // 临界半径出口 [mm] EN: the critical radius output
xEffective := rOuterRadiusMm >= rCrit;                                                                 // 有效性判定（信息级） EN: the effectiveness verdict, information class only
xValid := TRUE;                                                                                        // 结果可信 EN: the results are valid
FC_DL_InsulationCriticalRadiusCalc := TRUE;                                                            // 返回真 EN: return true
END_FUNCTION
