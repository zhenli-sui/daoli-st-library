(*
  Component : FC_DL_WebTensionFromDancerCalc
  Category  : DL_Motion
  Function  : 浮辊位置折算张力 T = (F气缸 + k×Δx) / 走带股数，含零位与股数保护
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rDancerPosMm 浮辊实际位置 [mm]、rDancerZeroMm 浮辊零位（张力零点标定位置） [mm]、
             rStiffNPerMm 蓄能弹簧（或配重）等效刚度 [N/mm]、rCylForceN 气缸折算力 [N]、
             nStrandCount 走带股数 [股]；输出 rTensionN 单股张力 [N]、rDeflectMm 相对零位位移 [mm]、
             xNegTension 张力为负（信息级：带材松弛）、xValid 有效标志、nFaultCode 故障码。
  边界     : 股数须在 1~8 内（0 股为组态错误，判 9802）；弹簧刚度须 ≥0；位移可为负（浮辊下沉）；
             力平衡取「2 侧带材张力之和 = 气缸力 + 弹簧力」，故单股张力除以股数。
  码位     : 9801 输入非有限（故障级）；9802 股数或刚度越域（故障级）。
*)
FUNCTION FC_DL_WebTensionFromDancerCalc : BOOL
VAR_INPUT
    rDancerPosMm  : LREAL := 50.0;    // 浮辊实际位置 [mm] EN: the actual dancer position
    rDancerZeroMm : LREAL := 0.0;     // 浮辊张力零位标定值 [mm] EN: the calibrated dancer position at zero tension
    rStiffNPerMm  : LREAL := 0.5;     // 等效刚度（弹簧或配重折算） [N/mm] EN: the equivalent stiffness of the spring or the counterweight
    rCylForceN    : LREAL := 200.0;   // 气缸折算力（已扣自重） [N] EN: the cylinder force with the dead weight removed
    nStrandCount  : INT := 2;         // 走带股数 [股] EN: the number of web strands passing the dancer
END_VAR
VAR_OUTPUT
    rTensionN   : LREAL;              // 单股张力 [N] EN: the tension per strand
    rDeflectMm  : LREAL;              // 相对零位位移 [mm] EN: the displacement from the zero position
    xNegTension : BOOL;               // 张力为负（信息级，带材松弛） EN: a negative tension meaning a slack web, information class only
    xValid      : BOOL;               // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;                // 0=无故障 9801=输入非有限 9802=股数或刚度越域 EN: zero none, 9801 non finite, 9802 strand count or stiffness out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 四个浮点入参有限 EN: the four floating inputs are finite
    rDefl   : LREAL;                  // 位移中间值 [mm] EN: the interim displacement
    rForce  : LREAL;                  // 总力中间值 [N] EN: the interim total force
    rTens   : LREAL;                  // 单股张力中间值 [N] EN: the interim tension per strand
    rN      : LREAL;                  // 股数的实数形式 [股] EN: the strand count as a real number
END_VAR
VAR CONSTANT
    DL_WTD_Z      : LREAL := 0.0;     // 浮点零常量 EN: the floating point zero constant
    DL_WTD_STR_MAX: INT := 8;         // 股数上限 [股] EN: the upper bound of the strand count
    DL_WTD_C_BAD  : INT := 9801;      // 输入非有限 EN: a non finite input
    DL_WTD_C_RANGE: INT := 9802;      // 股数或刚度越域 EN: the strand count or the stiffness is out of range
END_VAR

// 段1｜出口预置
FC_DL_WebTensionFromDancerCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rTensionN := DL_WTD_Z;                      // 张力预置零 [N] EN: preset the tension to zero
rDeflectMm := DL_WTD_Z;                     // 位移预置零 [mm] EN: preset the displacement to zero
xNegTension := FALSE;                       // 负张力标志预置假 EN: preset the negative tension flag to false
xValid := FALSE;                            // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                            // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四浮点入参全列
xFinAll := (rDancerPosMm = rDancerPosMm) AND ((rDancerPosMm - rDancerPosMm) = DL_WTD_Z)
        AND (rDancerZeroMm = rDancerZeroMm) AND ((rDancerZeroMm - rDancerZeroMm) = DL_WTD_Z)
        AND (rStiffNPerMm = rStiffNPerMm) AND ((rStiffNPerMm - rStiffNPerMm) = DL_WTD_Z)
        AND (rCylForceN = rCylForceN) AND ((rCylForceN - rCylForceN) = DL_WTD_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                  // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WTD_C_BAD;                                                      // 非有限码 EN: the non finite code
    RETURN;                                                                          // 早退 EN: return early
END_IF

// 段3｜域闸：股数 1~8、刚度非负
IF (nStrandCount < 1) OR (nStrandCount > DL_WTD_STR_MAX) OR (rStiffNPerMm < DL_WTD_Z) THEN   // 股数与刚度闸 EN: the strand count and stiffness gate
    nFaultCode := DL_WTD_C_RANGE;                                                              // 越域码 EN: the out of range code
    RETURN;                                                                                    // 早退 EN: return early
END_IF

// 段4｜主体：总力 = 气缸力 + 刚度 × 位移；单股张力 = 总力 / 股数
rDefl := rDancerPosMm - rDancerZeroMm;                                                          // 相对零位位移 [mm] EN: the displacement from the zero position
rForce := rCylForceN + rStiffNPerMm * rDefl;                                                    // 总力 [N] EN: the total force
rN := INT_TO_LREAL(nStrandCount);                                                               // 股数实数化，已证 ≥1 [股] EN: the strand count as a real number, proven at least one
rTens := rForce / rN;                                                                           // 单股张力 [N] EN: the tension per strand

// 段5｜结果复检与出口
IF (rTens <> rTens) OR (rDefl <> rDefl) THEN                                                    // 复检：两路输出非有限 EN: recheck both outputs
    nFaultCode := DL_WTD_C_RANGE;                                                               // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                     // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rDeflectMm := rDefl;                                                                            // 位移出口 [mm] EN: the displacement output
rTensionN := rTens;                                                                             // 张力出口 [N] EN: the tension output
xNegTension := rTens < DL_WTD_Z;                                                                // 负张力判据（信息级） EN: the negative tension test, information class only
xValid := TRUE;                                                                                 // 结果可信 EN: the results are valid
FC_DL_WebTensionFromDancerCalc := TRUE;                                                         // 返回真 EN: return true
END_FUNCTION
