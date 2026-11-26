(*
  Component : FC_DL_WebRewindTaperCalc
  Category  : DL_Motion
  Function  : 收卷锥度张力 T = T0 / (1 + taper × (D/D0 − 1))，卷径增大张力递减
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rT0N 初始（卷芯处）张力 [N]、rTaper 锥度系数 [-]、rDiaMm 当前卷径 [mm]、
             rCoreDiaMm 卷芯直径 D0 [mm]、rTaperMax 锥度系数上限 [-]；
             输出 rTensionN 当前张力 [N]、rDiaRatio 卷径比 D/D0 [-]、
             xTaperBad 锥度系数越域（信息级，按 0 处理并留痕）、xValid 有效标志、nFaultCode 故障码。
  边界     : 卷芯直径为分母须 >1.0E-6 [mm]；锥度分母 1 + taper×(ratio−1) 须 >1.0E-6（taper=−1 且卷径比
             恰为 2 时分母为零，属参数越域，判 9802）；初始张力须 ≥0；锥度系数按 [0, rTaperMax] 判域。
  码位     : 9801 输入非有限（故障级）；9802 卷芯直径或锥度分母越域（故障级）。
*)
FUNCTION FC_DL_WebRewindTaperCalc : BOOL
VAR_INPUT
    rT0N      : LREAL := 300.0;      // 卷芯处初始张力 [N] EN: the initial tension at the core
    rTaper    : LREAL := 0.3;        // 锥度系数 [-] EN: the taper coefficient
    rDiaMm    : LREAL := 600.0;      // 当前卷径 [mm] EN: the current roll diameter
    rCoreDiaMm: LREAL := 150.0;      // 卷芯直径 [mm] EN: the core diameter
    rTaperMax : LREAL := 1.0;        // 锥度系数上限 [-] EN: the upper bound of the taper coefficient
END_VAR
VAR_OUTPUT
    rTensionN : LREAL;               // 当前锥度张力 [N] EN: the current taper tension
    rDiaRatio : LREAL;               // 卷径比 D/D0 [-] EN: the diameter ratio
    xTaperBad : BOOL;                // 锥度系数越域（信息级） EN: the taper coefficient is out of range, information class only
    xValid    : BOOL;                // 输出可信标志 EN: the outputs are valid
    nFaultCode: INT;                 // 0=无故障 9801=输入非有限 9802=卷芯直径或锥度分母越域 EN: zero none, 9801 non finite, 9802 core diameter or taper divisor out of range
END_VAR
VAR
    xFinAll : BOOL;                  // 五输入同时有限 EN: all five inputs are finite
    rRatio  : LREAL;                 // 卷径比中间值 [-] EN: the interim diameter ratio
    rTaperU : LREAL;                 // 实际使用的锥度系数（越域时取零） [-] EN: the taper coefficient in use, zero when out of range
    rDen    : LREAL;                 // 锥度分母 [-] EN: the taper divisor
    rTens   : LREAL;                 // 张力中间值 [N] EN: the interim tension
END_VAR
VAR CONSTANT
    DL_WRT_Z     : LREAL := 0.0;     // 浮点零常量 EN: the floating point zero constant
    DL_WRT_ONE   : LREAL := 1.0;     // 浮点壹常量 EN: the floating point one constant
    DL_WRT_MIN   : LREAL := 1.0E-6;  // 分母绝对值下限 EN: the lower bound of the divisor magnitude
    DL_WRT_C_BAD : INT := 9801;      // 输入非有限 EN: a non finite input
    DL_WRT_C_DEN : INT := 9802;      // 卷芯直径或锥度分母越域 EN: the core diameter or the taper divisor is out of range
END_VAR

// 段1｜出口预置
FC_DL_WebRewindTaperCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rTensionN := DL_WRT_Z;               // 张力预置零 [N] EN: preset the tension to zero
rDiaRatio := DL_WRT_Z;               // 卷径比预置零 [-] EN: preset the diameter ratio to zero
xTaperBad := FALSE;                  // 锥度越域标志预置假 EN: preset the taper flag to false
xValid := FALSE;                     // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                     // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：五浮点入参全列
xFinAll := (rT0N = rT0N) AND ((rT0N - rT0N) = DL_WRT_Z)
        AND (rTaper = rTaper) AND ((rTaper - rTaper) = DL_WRT_Z)
        AND (rDiaMm = rDiaMm) AND ((rDiaMm - rDiaMm) = DL_WRT_Z)
        AND (rCoreDiaMm = rCoreDiaMm) AND ((rCoreDiaMm - rCoreDiaMm) = DL_WRT_Z)
        AND (rTaperMax = rTaperMax) AND ((rTaperMax - rTaperMax) = DL_WRT_Z);   // 五输入有限性 EN: the finiteness of all five inputs
IF NOT xFinAll THEN                                                            // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WRT_C_BAD;                                                // 非有限码 EN: the non finite code
    RETURN;                                                                    // 早退 EN: return early
END_IF

// 段3｜域闸：初始张力非负、卷芯直径为正、卷径非负、锥度上限非负
IF (rT0N < DL_WRT_Z) OR (rDiaMm < DL_WRT_Z) OR (rCoreDiaMm < DL_WRT_MIN) OR (rTaperMax < DL_WRT_Z) THEN
    nFaultCode := DL_WRT_C_DEN;                                                // 越域码 EN: the out of range code
    RETURN;                                                                    // 早退 EN: return early
END_IF

// 段4｜锥度系数域：越域按零（等效无锥度）处理并置信息级标志，不中断输出
IF (rTaper < DL_WRT_Z) OR (rTaper > rTaperMax) THEN                            // 锥度域判据 EN: the taper domain test
    rTaperU := DL_WRT_Z;                                                       // 越域取零（无锥度） [-] EN: fall back to zero
    xTaperBad := TRUE;                                                         // 置信息级标志 EN: raise the information class flag
ELSE
    rTaperU := rTaper;                                                         // 域内直接使用 [-] EN: use the coefficient as given
END_IF

// 段5｜主体：T = T0 / (1 + taper × (D/D0 − 1))
rRatio := rDiaMm / rCoreDiaMm;                                                 // 卷径比，分母已证正 [-] EN: the diameter ratio, the divisor is proven positive
rDen := DL_WRT_ONE + rTaperU * (rRatio - DL_WRT_ONE);                          // 锥度分母 [-] EN: the taper divisor
IF ABS(rDen) < DL_WRT_MIN THEN                                                 // 锥度分母下限 EN: the taper divisor gate
    nFaultCode := DL_WRT_C_DEN;                                                // 分母越域码 EN: the divisor code
    RETURN;                                                                    // 早退 EN: return early
END_IF
rTens := rT0N / rDen;                                                          // 锥度张力 [N] EN: the taper tension
IF (rTens <> rTens) OR (rTens < DL_WRT_Z) THEN                                 // 结果复检 EN: recheck the result
    nFaultCode := DL_WRT_C_DEN;                                                // 复检失败码 EN: the recheck failure code
    RETURN;                                                                    // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段6｜出口
rTensionN := rTens;                                                            // 张力出口 [N] EN: the tension output
rDiaRatio := rRatio;                                                           // 卷径比出口 [-] EN: the diameter ratio output
xValid := TRUE;                                                                // 结果可信 EN: the results are valid
FC_DL_WebRewindTaperCalc := TRUE;                                              // 返回真 EN: return true
END_FUNCTION
