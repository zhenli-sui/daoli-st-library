(*
  Component : FC_DL_SurfaceConvectionCalc
  Category  : DL_Base
  Function  : 表面换热系数：自然对流（垂直/水平）与强制对流分式选取
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 eMode 对流模式枚举、rDeltaTK 表面与环境的温差（取绝对值参与公式） [K]、
             rCharLenM 特征尺寸（垂直取高、水平取宽） [m]、rVelMs 风速（强制模式用） [m/s]；
             输出 rHWm2K 表面换热系数 [W/(m2·K)]、rModeEcho 实际使用模式、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 自然对流派生式 h = 1.42×(ΔT/L)^0.25（垂直）/ 1.32×(ΔT/L)^0.25（水平），
             强制对流简式 h = 10.45×v^0.8；四次方根与 0.8 次幂一律用 EXP(k×LN(x)) 实现，
             禁用 EXPT 等方言算子；ΔT 与 L 须 >0、v 须 >0（强制模式）。
  码位     : 9801 输入非有限（故障级）；9802 特征尺寸或温差越域（故障级）；9803 模式未知（故障级）。
*)
TYPE E_DL_ConvMode :
(
    eNatVertical   := 0,    // 自然对流-垂直面 EN: natural convection on a vertical surface
    eNatHorizontal := 1,    // 自然对流-水平面 EN: natural convection on a horizontal surface
    eForced        := 2     // 强制对流 EN: forced convection
);
END_TYPE

FUNCTION FC_DL_SurfaceConvectionCalc : BOOL
VAR_INPUT
    eMode     : E_DL_ConvMode;   // 对流模式 [-] EN: the convection mode
    rDeltaTK  : LREAL := 30.0;   // 表面与环境温差（取绝对值） [K] EN: the surface to ambient temperature difference taken as a magnitude
    rCharLenM : LREAL := 1.0;    // 特征尺寸 [m] EN: the characteristic length
    rVelMs    : LREAL := 1.0;    // 风速（强制模式） [m/s] EN: the air velocity used in the forced mode
END_VAR
VAR_OUTPUT
    rHWm2K   : LREAL;            // 表面换热系数 [W/(m2·K)] EN: the surface heat transfer coefficient
    rModeEcho: INT;              // 实际使用模式的枚举值 EN: the enumeration value of the mode in use
    xValid   : BOOL;             // 输出可信标志 EN: the outputs are valid
    nFaultCode: INT;             // 0=无故障 9801=输入非有限 9802=尺寸或温差越域 9803=模式未知 EN: zero none, 9801 non finite, 9802 length or difference out of range, 9803 unknown mode
END_VAR
VAR
    xFinAll : BOOL;              // 三个浮点入参有限 EN: the three floating inputs are finite
    rRatio  : LREAL;             // ΔT/L 比 [-] EN: the ratio of the difference to the length
    rPow    : LREAL;             // 幂运算中间值 [-] EN: the interim power value
    rH      : LREAL;             // 换热系数中间值 [W/(m2·K)] EN: the interim coefficient
END_VAR
VAR CONSTANT
    DL_SCV_Z      : LREAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_SCV_KV     : LREAL := 1.42;     // 垂直自然对流系数 EN: the vertical natural convection factor
    DL_SCV_KH     : LREAL := 1.32;     // 水平自然对流系数 EN: the horizontal natural convection factor
    DL_SCV_KF     : LREAL := 10.45;    // 强制对流系数 EN: the forced convection factor
    DL_SCV_E_NAT  : LREAL := 0.25;     // 自然对流指数 [-] EN: the natural convection exponent
    DL_SCV_E_FRC  : LREAL := 0.8;      // 强制对流指数 [-] EN: the forced convection exponent
    DL_SCV_MIN    : LREAL := 1.0E-6;   // 尺寸与温差的下限 EN: the lower bound of the length and the difference
    DL_SCV_C_BAD  : INT := 9801;       // 输入非有限 EN: a non finite input
    DL_SCV_C_RANG : INT := 9802;       // 尺寸或温差越域 EN: the length or the difference is out of range
    DL_SCV_C_MODE : INT := 9803;       // 模式未知 EN: the mode is unknown
END_VAR

// 段1｜出口预置
FC_DL_SurfaceConvectionCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rHWm2K := DL_SCV_Z;                     // 换热系数预置零 [W/(m2·K)] EN: preset the coefficient to zero
rModeEcho := 0;                         // 模式回显预置零 EN: preset the mode echo to zero
xValid := FALSE;                        // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                        // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三浮点入参全列（强制模式的风速亦在闸内）
xFinAll := (rDeltaTK = rDeltaTK) AND ((rDeltaTK - rDeltaTK) = DL_SCV_Z)
        AND (rCharLenM = rCharLenM) AND ((rCharLenM - rCharLenM) = DL_SCV_Z)
        AND (rVelMs = rVelMs) AND ((rVelMs - rVelMs) = DL_SCV_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                  // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_SCV_C_BAD;                                      // 非有限码 EN: the non finite code
    RETURN;                                                          // 早退 EN: return early
END_IF

// 段3｜域闸：特征尺寸为正、温差取绝对值后须为正（零温差无对流）
IF (rCharLenM < DL_SCV_MIN) OR (ABS(rDeltaTK) < DL_SCV_MIN) THEN      // 尺寸与温差闸 EN: the length and difference gate
    nFaultCode := DL_SCV_C_RANG;                                     // 越域码 EN: the out of range code
    RETURN;                                                          // 早退 EN: return early
END_IF

// 段4｜模式分派：ENUM + CASE 且 ELSE 兜底
rRatio := ABS(rDeltaTK) / rCharLenM;                                 // ΔT/L，分母已证正 [-] EN: the ratio, the divisor is proven positive
CASE eMode OF
    E_DL_ConvMode.eNatVertical:
        rPow := EXP(DL_SCV_E_NAT * LN(rRatio));                      // (ΔT/L)^0.25 EN: the quarter power of the ratio
        rH := DL_SCV_KV * rPow;                                      // 垂直面自然对流 [W/(m2·K)] EN: the vertical natural convection
        rModeEcho := 0;                                              // 模式回显 EN: the mode echo
    E_DL_ConvMode.eNatHorizontal:
        rPow := EXP(DL_SCV_E_NAT * LN(rRatio));                      // (ΔT/L)^0.25 EN: the quarter power of the ratio
        rH := DL_SCV_KH * rPow;                                      // 水平面自然对流 [W/(m2·K)] EN: the horizontal natural convection
        rModeEcho := 1;                                              // 模式回显 EN: the mode echo
    E_DL_ConvMode.eForced:
        IF rVelMs < DL_SCV_MIN THEN                                  // 强制模式需有效风速 EN: the forced mode needs a usable velocity
            nFaultCode := DL_SCV_C_RANG;                             // 风速越域码 EN: the velocity code
            RETURN;                                                  // 早退 EN: return early
        END_IF
        rPow := EXP(DL_SCV_E_FRC * LN(rVelMs));                      // v^0.8 EN: the point eight power of the velocity
        rH := DL_SCV_KF * rPow;                                      // 强制对流 [W/(m2·K)] EN: the forced convection
        rModeEcho := 2;                                              // 模式回显 EN: the mode echo
ELSE
    nFaultCode := DL_SCV_C_MODE;                                     // 未知模式码 EN: the unknown mode code
    RETURN;                                                          // 早退 EN: return early
END_CASE

// 段5｜结果复检与出口
IF (rH <> rH) OR (rH <= DL_SCV_Z) THEN                               // 复检：非有限或非正 EN: recheck for a non finite or non positive value
    nFaultCode := DL_SCV_C_RANG;                                     // 复检失败码 EN: the recheck failure code
    RETURN;                                                          // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rHWm2K := rH;                                                        // 换热系数出口 [W/(m2·K)] EN: the coefficient output
xValid := TRUE;                                                      // 结果可信 EN: the results are valid
FC_DL_SurfaceConvectionCalc := TRUE;                                 // 返回真 EN: return true
END_FUNCTION
