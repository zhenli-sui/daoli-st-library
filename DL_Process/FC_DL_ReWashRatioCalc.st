(*
  Component : FC_DL_ReWashRatioCalc
  Category  : DL_Process
  Function  : 洗涤液配比与洗涤级数反算：按杂质夹带率 n = LN(cOut/cIn) / LN(1/(1+R))
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rImpInPpm 洗涤前杂质夹带 [ppm]、rImpOutPpm 洗涤后目标杂质 [ppm]、
             rWashRatio 洗涤液与有机相体积配比 W/O [-]、rFlowOrgM3h 有机相流量 [m3/h]；
             输出 rWashFlowM3h 洗涤液体积流量 [m3/h]、rStages 理论洗涤级数 [级]、nStagesCeil 向上取整级数 [级]、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 单级杂质残留比 = 1/(1+R)，故 n = LN(入口/出口) / LN(1+R)；R 须 >1.0E-9、
             入口/出口浓度须 >0 且入口 > 出口，否则判 9802；级数上限 1000 判 9804；
             向上取整先 TRUNC 再按余量进位，整除点不自增。
  码位     : 9801 输入非法（故障级）；9802 浓度或配比关系非法（故障级）；9804 级数超上限（故障级）。
*)
FUNCTION FC_DL_ReWashRatioCalc : BOOL
VAR_INPUT
    rImpInPpm  : LREAL := 500.0;    // 洗涤前杂质夹带量 [ppm] EN: the entrained impurity before washing
    rImpOutPpm : LREAL := 20.0;     // 洗涤后目标杂质含量 [ppm] EN: the target impurity after washing
    rWashRatio : LREAL := 0.3;      // 洗涤液与有机相体积配比 W/O [-] EN: the wash liquid to organic volumetric ratio
    rFlowOrgM3h: LREAL := 5.0;      // 有机相体积流量 [m3/h] EN: the volumetric flow of the organic phase
END_VAR
VAR_OUTPUT
    rWashFlowM3h : LREAL;           // 洗涤液体积流量 [m3/h] EN: the wash liquid volumetric flow
    rStages      : LREAL;           // 理论洗涤级数（未取整） [级] EN: the theoretical wash stage number before rounding
    nStagesCeil  : INT;             // 向上取整后的洗涤级数 [级] EN: the wash stage number rounded upward
    xValid       : BOOL;            // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;             // 0=无故障 9801=输入非法 9802=浓度或配比关系非法 9804=级数超上限 EN: zero none, 9801 illegal input, 9802 illegal concentration or ratio, 9804 stage overflow
END_VAR
VAR
    xFinAll  : BOOL;                // 四输入同时有限 EN: all four inputs are finite
    rRatC    : LREAL;               // 进出口杂质浓度比 [-] EN: the inlet to outlet impurity ratio
    rLnC     : LREAL;               // 浓度比对数 [-] EN: the logarithm of the concentration ratio
    rLnR     : LREAL;               // 单级残留系数对数 [-] EN: the logarithm of the single stage retention factor
    rN       : LREAL;               // 级数中间值 [级] EN: the interim stage number
    rTrunc   : LREAL;               // 取整部分 [级] EN: the truncated integer part
    nCeil    : INT;                 // 进位后级数 [级] EN: the ceiling stage count
END_VAR
VAR CONSTANT
    DL_RWR_Z       : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_RWR_ONE     : LREAL := 1.0;    // 浮点壹常量 EN: the floating point one constant
    DL_RWR_MIN     : LREAL := 1.0E-9; // 浓度与配比的下限 EN: the lower bound of the concentration and the ratio
    DL_RWR_STG_MAX : LREAL := 1000.0; // 级数上限 [级] EN: the stage upper bound
    DL_RWR_C_BAD   : INT := 9801;     // 输入非法 EN: an illegal input
    DL_RWR_C_ORDER : INT := 9802;     // 浓度或配比关系非法 EN: an illegal concentration or ratio order
    DL_RWR_C_OVER  : INT := 9804;     // 级数超上限 EN: the stage count overflow
END_VAR

// 段1｜出口预置
FC_DL_ReWashRatioCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rWashFlowM3h := DL_RWR_Z;         // 洗涤液流量预置零 [m3/h] EN: preset the wash flow to zero
rStages := DL_RWR_Z;              // 理论级数预置零 [级] EN: preset the theoretical stages to zero
nStagesCeil := 0;                 // 整数级数预置零 [级] EN: preset the integer stages to zero
xValid := FALSE;                  // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                  // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四输入全列
xFinAll := (rImpInPpm = rImpInPpm) AND ((rImpInPpm - rImpInPpm) = DL_RWR_Z)
        AND (rImpOutPpm = rImpOutPpm) AND ((rImpOutPpm - rImpOutPpm) = DL_RWR_Z)
        AND (rWashRatio = rWashRatio) AND ((rWashRatio - rWashRatio) = DL_RWR_Z)
        AND (rFlowOrgM3h = rFlowOrgM3h) AND ((rFlowOrgM3h - rFlowOrgM3h) = DL_RWR_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                      // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_RWR_C_BAD;                                                          // 输入非法码 EN: the illegal input code
    RETURN;                                                                              // 早退 EN: return early
END_IF

// 段3｜域闸：配比与流量为正、出口杂质为正且小于入口，否则对数式无解
IF (rWashRatio < DL_RWR_MIN) OR (rFlowOrgM3h < DL_RWR_Z)
   OR (rImpOutPpm < DL_RWR_MIN) OR (rImpInPpm <= rImpOutPpm) THEN
    nFaultCode := DL_RWR_C_ORDER;                                                        // 关系非法码 EN: the illegal relation code
    RETURN;                                                                              // 早退 EN: return early
END_IF

// 段4｜主体：级数 n = LN(入口/出口) / LN(1+R)
rRatC := rImpInPpm / rImpOutPpm;                                                         // 浓度比，分母已证 >1.0E-9 [-] EN: the concentration ratio, the divisor is proven positive
rLnC := LN(rRatC);                                                                       // 浓度比对数 [-] EN: the logarithm of the concentration ratio
rLnR := LN(DL_RWR_ONE + rWashRatio);                                                     // 单级残留系数对数，已证 >0 [-] EN: the logarithm of the retention factor, proven positive
IF ABS(rLnR) < DL_RWR_MIN THEN                                                           // 除数下限保护 EN: guard the divisor magnitude
    nFaultCode := DL_RWR_C_ORDER;                                                        // 退化为关系非法码 EN: fall back to the relation code
    RETURN;                                                                              // 早退 EN: return early
END_IF
rN := rLnC / rLnR;                                                                       // 洗涤级数 [级] EN: the wash stage number
IF (rN <> rN) OR (rN < DL_RWR_Z) OR (rN > DL_RWR_STG_MAX) THEN                           // 结果复检 EN: recheck the result
    nFaultCode := DL_RWR_C_OVER;                                                         // 级数超限码 EN: the stage overflow code
    RETURN;                                                                              // 早退 EN: return early
END_IF

// 段5｜向上取整：先 TRUNC 再按余量进位
rTrunc := TRUNC(rN);                                                                     // 取整部分 [级] EN: the truncated part
nCeil := LREAL_TO_INT(rTrunc);                                                           // 转 INT [级] EN: convert to an integer
IF rN > rTrunc THEN                                                                      // 余量判据 EN: the remainder test
    IF nCeil < 1000 THEN                                                                 // 进位上限兜底 EN: bound the carry
        nCeil := nCeil + 1;                                                              // 进一级 EN: carry one stage
    END_IF
END_IF
rWashFlowM3h := rWashRatio * rFlowOrgM3h;                                                // 洗涤液流量 [m3/h] EN: the wash liquid flow
rStages := rN;                                                                           // 理论级数出口 [级] EN: the theoretical stages output
nStagesCeil := nCeil;                                                                    // 整数级数出口 [级] EN: the integer stages output
xValid := TRUE;                                                                          // 结果可信 EN: the results are valid
FC_DL_ReWashRatioCalc := TRUE;                                                           // 返回真 EN: return true
END_FUNCTION
