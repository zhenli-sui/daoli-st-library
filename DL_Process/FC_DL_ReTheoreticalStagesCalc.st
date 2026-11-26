(*
  Component : FC_DL_ReTheoreticalStagesCalc
  Category  : DL_Process
  Function  : 逆流萃取理论级数 n = LN((x0-xStar)/(xn-xStar)) / LN(E)，E 为单级萃取比
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rFeedX0 料液浓度 [g/L]、rRaffXn 目标萃余液浓度 [g/L]、rEquilXStar 平衡浓度 [g/L]、
             rExtractRatio 单级萃取比 E [-][>1]；输出 rStages 理论级数 [-]、nStagesCeil 向上取整级数 [级]、
             xValid 有效标志、nFaultCode 故障码；返回 TRUE 表示两输出可信。
  边界     : 须 x0 > xn > xStar；E 须 >1（E≤1 时 LN(E)≤0，理论级数无解，判 9803 并输出无效标志）；
             (x0-xStar) 与 (xn-xStar) 须 >1.0E-9；级数上限 1000，超限判 9804 防 INT 溢出；
             零点五级以下按「先 TRUNC 后按余量进位」向上取整，禁 TRUNC(x)+1。
  码位     : 9801 输入非有限；9802 浓度关系非法；9803 萃取比不足（E≤1）；9804 级数超上限。全部故障级。
*)
FUNCTION FC_DL_ReTheoreticalStagesCalc : BOOL
VAR_INPUT
    rFeedX0       : LREAL := 10.0;   // 料液稀土浓度 x0 [g/L] EN: the rare earth concentration of the feed liquor
    rRaffXn       : LREAL := 0.1;    // 目标萃余液浓度 xn [g/L] EN: the target rare earth concentration of the raffinate
    rEquilXStar   : LREAL := 0.0;    // 平衡浓度 xStar [g/L] EN: the equilibrium concentration of the aqueous phase
    rExtractRatio : LREAL := 3.0;    // 单级萃取比 E，每级浓度下降倍数 [-] EN: the per stage extraction ratio above one
END_VAR
VAR_OUTPUT
    rStages     : LREAL;             // 理论级数（未取整） [级] EN: the theoretical stage number before rounding
    nStagesCeil : INT;               // 向上取整后的工程级数 [级] EN: the engineering stage number rounded upward
    xValid      : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;               // 0=无故障 9801=非有限 9802=浓度关系非法 9803=萃取比不足 9804=级数超限 EN: zero none, 9801 non finite, 9802 illegal concentration order, 9803 ratio too low, 9804 stage overflow
END_VAR
VAR
    xFinAll  : BOOL;                 // 四输入同时有限 EN: all four inputs are finite
    rTopNum  : LREAL;                // 浓度比分子 x0 - x* [g/L] EN: the numerator concentration difference
    rBotNum  : LREAL;                // 浓度比分母 xn - x* [g/L] EN: the denominator concentration difference
    rConcRat : LREAL;                // 浓度比 (x0-xStar)/(xn-xStar) [-] EN: the concentration ratio
    rLnE     : LREAL;                // LN(E) [-] EN: the natural logarithm of the extraction ratio
    rLnRat   : LREAL;                // LN(浓度比) [-] EN: the natural logarithm of the concentration ratio
    rN       : LREAL;                // 理论级数中间值 [级] EN: the interim theoretical stage number
    rTrunc   : LREAL;                // TRUNC 后的整数部分 [级] EN: the truncated integer part
    nCeil    : INT;                  // 进位后的整数级数 [级] EN: the ceiling stage count as an integer
END_VAR
VAR CONSTANT
    DL_RTS_Z       : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_RTS_ONE     : LREAL := 1.0;    // 浮点壹常量 EN: the floating point one constant
    DL_RTS_EPS     : LREAL := 1.0E-9; // 浓度差与对数的下限 EN: the lower bound of the concentration difference and logarithm
    DL_RTS_STG_MAX : LREAL := 1000.0; // 级数上限（防 INT 溢出） [级] EN: the stage upper bound preventing an integer overflow
    DL_RTS_C_BAD   : INT := 9801;     // 输入非有限 EN: a non finite input
    DL_RTS_C_ORDER : INT := 9802;     // 浓度关系非法 EN: an illegal concentration order
    DL_RTS_C_RATIO : INT := 9803;     // 萃取比不足 EN: the extraction ratio is not above one
    DL_RTS_C_OVER  : INT := 9804;     // 级数超上限 EN: the stage count overflow
END_VAR

// 段1｜出口预置
FC_DL_ReTheoreticalStagesCalc := FALSE;  // 返回值预置假 EN: preset the return value to false
rStages := DL_RTS_Z;                     // 理论级数预置零 [级] EN: preset the theoretical stages to zero
nStagesCeil := 0;                        // 整数级数预置零 [级] EN: preset the integer stages to zero
xValid := FALSE;                         // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                         // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四个浮点入参全部列入，缺一个即对应判据静默失效
xFinAll := (rFeedX0 = rFeedX0) AND ((rFeedX0 - rFeedX0) = DL_RTS_Z)
        AND (rRaffXn = rRaffXn) AND ((rRaffXn - rRaffXn) = DL_RTS_Z)
        AND (rEquilXStar = rEquilXStar) AND ((rEquilXStar - rEquilXStar) = DL_RTS_Z)
        AND (rExtractRatio = rExtractRatio) AND ((rExtractRatio - rExtractRatio) = DL_RTS_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                              // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_RTS_C_BAD;                                                                  // 非有限码 EN: the non finite code
    RETURN;                                                                                      // 早退 EN: return early
END_IF

// 段3｜域闸：浓度关系必须 x0 > xn > x*，否则对数式无物理意义
rTopNum := rFeedX0 - rEquilXStar;                                                               // 分子浓度差 [g/L] EN: the numerator concentration difference
rBotNum := rRaffXn - rEquilXStar;                                                               // 分母浓度差 [g/L] EN: the denominator concentration difference
IF (rTopNum <= DL_RTS_EPS) OR (rBotNum <= DL_RTS_EPS) OR (rTopNum <= rBotNum) THEN              // 浓度顺序与量级闸 EN: the concentration order and magnitude gate
    nFaultCode := DL_RTS_C_ORDER;                                                               // 浓度关系非法码 EN: the illegal concentration order code
    RETURN;                                                                                     // 早退 EN: return early
END_IF

// 段4｜萃取比闸：E 须 >1+容差，E≤1 时理论级数无解（本题明确要求输出无效标志）
IF rExtractRatio <= (DL_RTS_ONE + DL_RTS_EPS) THEN                                              // 萃取比不足闸 EN: the extraction ratio is not above one
    nFaultCode := DL_RTS_C_RATIO;                                                               // 萃取比不足码 EN: the ratio too low code
    RETURN;                                                                                     // 早退 EN: return early
END_IF

// 段5｜主体：n = LN((x0-xStar)/(xn-xStar)) / LN(E)
rConcRat := rTopNum / rBotNum;                                                                  // 浓度比，分母已证 >1.0E-9 [-] EN: the concentration ratio, the denominator is proven positive
rLnRat := LN(rConcRat);                                                                         // 浓度比对数 [-] EN: the logarithm of the concentration ratio
rLnE := LN(rExtractRatio);                                                                      // 萃取比对数，已证 >0 [-] EN: the logarithm of the extraction ratio, proven positive
IF ABS(rLnE) < DL_RTS_EPS THEN                                                                  // 除数下限保护 EN: guard the divisor magnitude
    nFaultCode := DL_RTS_C_RATIO;                                                               // 退化为萃取比不足码 EN: fall back to the ratio code
    RETURN;                                                                                     // 早退 EN: return early
END_IF
rN := rLnRat / rLnE;                                                                            // 理论级数 [级] EN: the theoretical stage number
IF (rN <> rN) OR (rN < DL_RTS_Z) OR (rN > DL_RTS_STG_MAX) THEN                                   // 结果复检：非有限/负/超上限 EN: recheck for a non finite, negative or oversized result
    nFaultCode := DL_RTS_C_OVER;                                                                // 级数超限码 EN: the stage overflow code
    RETURN;                                                                                     // 早退 EN: return early
END_IF

// 段6｜向上取整：先 TRUNC 再按余量进位，整除点不自增（禁 TRUNC(x)+1）
rTrunc := TRUNC(rN);                                                                            // 取整数部分 [级] EN: take the integer part
nCeil := LREAL_TO_INT(rTrunc);                                                                  // 转 INT [级] EN: convert the integer part to an integer
IF rN > rTrunc THEN                                                                             // 余量判据：非整点才进位 EN: only carry when there is a remainder
    IF nCeil < 1000 THEN                                                                        // 进位前上限兜底 EN: bound the carry before it happens
        nCeil := nCeil + 1;                                                                     // 进一级 [级] EN: carry one stage
    END_IF
END_IF
rStages := rN;                                                                                  // 理论级数出口 [级] EN: publish the theoretical stages
nStagesCeil := nCeil;                                                                           // 工程级数出口 [级] EN: publish the engineering stage count
xValid := TRUE;                                                                                 // 结果可信 EN: the results are valid
FC_DL_ReTheoreticalStagesCalc := TRUE;                                                          // 返回真 EN: return true
END_FUNCTION
