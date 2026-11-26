(*
  Component : FC_DL_CathodeLiExcessCalc
  Category  : DL_Process
  Function  : 锂电正极材料 Li/M 摩尔比与实际过量率，并做目标区间判定
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rLiMolPerM 实测 Li/M 摩尔比 [-]、rTargetRatio 目标 Li/M 摩尔比 [-]、
             rBandTolPct 目标区间半宽 [%]；输出 rExcessPct 相对目标过量率 [%]、rLiMolPerM 摩尔比直通、
             xInBand 摩尔比落在目标区间、xValid 有效标志、nFaultCode 故障码。
  边界     : 目标摩尔比为分母须 >1.0E-9；区间半宽须在 (0, 50] [%] 内，越域判 9803（半宽越域使判定
             恒真或恒假，属组态域闸缺失）；过量率可正可负，负值表达欠锂，不做钳位（方向信息不得丢失）。
  码位     : 9801 输入非法（故障级）；9802 目标摩尔比过小（故障级）；9803 区间半宽越域（故障级）。
*)
FUNCTION FC_DL_CathodeLiExcessCalc : BOOL
VAR_INPUT
    rLiMolPerM    : LREAL := 1.03;   // 实测 Li/M 摩尔比 [-] EN: the measured lithium to metal molar ratio
    rTargetRatio  : LREAL := 1.03;   // 目标 Li/M 摩尔比 [-] EN: the target lithium to metal molar ratio
    rBandTolPct   : LREAL := 1.0;    // 目标区间半宽 [%] EN: the half width of the target band in percent
END_VAR
VAR_OUTPUT
    rExcessPct  : LREAL;             // 相对目标摩尔比的过量率 [%] EN: the excess rate against the target molar ratio
    rRatioEcho  : LREAL;             // 摩尔比直通（供趋势记录） [-] EN: the molar ratio passed through for trending
    xInBand     : BOOL;              // 摩尔比落在目标区间 EN: the molar ratio is inside the target band
    xValid      : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;               // 0=无故障 9801=输入非法 9802=目标比过小 9803=半宽越域 EN: zero none, 9801 illegal input, 9802 target too small, 9803 half width out of range
END_VAR
VAR
    xFinAll  : BOOL;                 // 三输入同时有限 EN: all three inputs are finite
    rDev     : LREAL;                // 相对偏差 [-] EN: the relative deviation
    rDevPct  : LREAL;                // 相对偏差百分数 [%] EN: the relative deviation in percent
    rDen     : LREAL;                // 分母（目标摩尔比） [-] EN: the divisor, the target molar ratio
END_VAR
VAR CONSTANT
    DL_CLE_Z       : LREAL := 0.0;   // 浮点零常量 EN: the floating point zero constant
    DL_CLE_HUNDRED : LREAL := 100.0; // 百分数换算系数 EN: the percent conversion factor
    DL_CLE_TOL_MAX : LREAL := 50.0;  // 区间半宽上限 [%] EN: the upper bound of the band half width
    DL_CLE_MIN     : LREAL := 1.0E-9;// 分母绝对值下限 EN: the lower bound of the divisor magnitude
    DL_CLE_C_BAD   : INT := 9801;    // 输入非法 EN: an illegal input
    DL_CLE_C_TGT   : INT := 9802;    // 目标摩尔比过小 EN: the target molar ratio is too small
    DL_CLE_C_TOL   : INT := 9803;    // 区间半宽越域 EN: the half width is out of range
END_VAR

// 段1｜出口预置
FC_DL_CathodeLiExcessCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rExcessPct := DL_CLE_Z;                // 过量率预置零 [%] EN: preset the excess rate to zero
rRatioEcho := DL_CLE_Z;                // 摩尔比直通预置零 [-] EN: preset the ratio echo to zero
xInBand := FALSE;                      // 区间标志预置假 EN: preset the band flag to false
xValid := FALSE;                       // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                       // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三输入全列（半宽参与区间判据，漏则判定失效）
xFinAll := (rLiMolPerM = rLiMolPerM) AND ((rLiMolPerM - rLiMolPerM) = DL_CLE_Z)
        AND (rTargetRatio = rTargetRatio) AND ((rTargetRatio - rTargetRatio) = DL_CLE_Z)
        AND (rBandTolPct = rBandTolPct) AND ((rBandTolPct - rBandTolPct) = DL_CLE_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                                     // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CLE_C_BAD;                                                         // 输入非法码 EN: the illegal input code
    RETURN;                                                                             // 早退 EN: return early
END_IF

// 段3｜域闸：目标比为分母须过下限；半宽须在 (0,50] 内
rDen := rTargetRatio;                                                                   // 取分母 [-] EN: take the divisor
IF ABS(rDen) < DL_CLE_MIN THEN                                                          // 分母下限 EN: the divisor magnitude gate
    nFaultCode := DL_CLE_C_TGT;                                                         // 目标比过小码 EN: the target ratio code
    RETURN;                                                                             // 早退 EN: return early
END_IF
IF (rBandTolPct <= DL_CLE_Z) OR (rBandTolPct > DL_CLE_TOL_MAX) THEN                     // 半宽域闸 EN: the half width domain gate
    nFaultCode := DL_CLE_C_TOL;                                                         // 半宽越域码 EN: the half width code
    RETURN;                                                                             // 早退 EN: return early
END_IF

// 段4｜主体：过量率 = (实测/目标 − 1) × 100，不钳位以保留欠锂方向
rDev := (rLiMolPerM / rDen) - 1.0;                                                      // 相对偏差 [-] EN: the relative deviation
rDevPct := rDev * DL_CLE_HUNDRED;                                                       // 相对偏差百分数 [%] EN: the relative deviation in percent

// 段5｜出口：区间判定按绝对值比较（欠锂与过锂同带宽）
rExcessPct := rDevPct;                                                                  // 过量率出口 [%] EN: the excess rate output
rRatioEcho := rLiMolPerM;                                                               // 摩尔比直通 [-] EN: the ratio echo output
xInBand := ABS(rDevPct) <= rBandTolPct;                                                 // 区间判定 EN: the band verdict
xValid := TRUE;                                                                         // 结果可信 EN: the results are valid
FC_DL_CathodeLiExcessCalc := TRUE;                                                      // 返回真 EN: return true
END_FUNCTION
