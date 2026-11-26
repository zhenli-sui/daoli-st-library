(*
  Component : FC_DL_RePhaseRatioCalc
  Category  : DL_Process
  Function  : 相比 O/A、两相总流量核算与总流量一致性校验
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rFlowOrgM3h 有机相流量 [m3/h]、rFlowAqM3h 水相流量 [m3/h]、
             rFlowTotalMeasM3h 实测混合前总流量 [m3/h]、rTotalTolPct 总流量相对容差 [%]；
             输出 rRatioOA 相比 [-]、rFlowTotalM3h 计算总流量 [m3/h]、rDevPct 相对偏差 [%]、
             xTotalMatch 总流量一致、xValid 有效标志、nFaultCode 故障码。
  边界     : 水相流量为分母须 >1.0E-9 [m3/h]；两流量均须 ≥0；总流量容差须在 (0, 100] [%] 内，
             否则判 9803（容差非法会使一致性判据恒真或恒假，属组态域闸缺失）；
             相对偏差以计算总流量为分母，故须先证计算总流量 >1.0E-9。
  码位     : 9801 输入非法（故障级）；9802 水相流量过小（故障级）；9803 容差越域（故障级）。
*)
FUNCTION FC_DL_RePhaseRatioCalc : BOOL
VAR_INPUT
    rFlowOrgM3h       : LREAL := 5.0;    // 有机相体积流量 [m3/h] EN: the volumetric flow of the organic phase
    rFlowAqM3h        : LREAL := 5.0;    // 水相体积流量 [m3/h] EN: the volumetric flow of the aqueous phase
    rFlowTotalMeasM3h : LREAL := 10.0;   // 实测总流量（混合前两路之和） [m3/h] EN: the measured total flow of both phases before mixing
    rTotalTolPct      : LREAL := 2.0;    // 总流量相对容差 [%] EN: the relative tolerance of the total flow
END_VAR
VAR_OUTPUT
    rRatioOA     : LREAL;                // 相比 O/A [-] EN: the organic to aqueous phase ratio
    rFlowTotalM3h: LREAL;                // 计算总流量 [m3/h] EN: the computed total flow
    rDevPct      : LREAL;                // 实测相对计算值的偏差 [%] EN: the deviation of the measurement from the computed total
    xTotalMatch  : BOOL;                 // 总流量一致（在容差内） EN: the total flow agrees within the tolerance
    xValid       : BOOL;                 // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;                  // 0=无故障 9801=输入非法 9802=水相流量过小 9803=容差越域 EN: zero none, 9801 illegal input, 9802 aqueous flow too small, 9803 tolerance out of range
END_VAR
VAR
    xFinAll   : BOOL;                    // 四输入同时有限 EN: all four inputs are finite
    xNegFlow  : BOOL;                    // 存在负流量 EN: some flow is negative
    rDen      : LREAL;                   // 分母（水相流量） [m3/h] EN: the divisor, the aqueous phase flow
    rTotal    : LREAL;                   // 计算总流量中间值 [m3/h] EN: the interim computed total flow
    rDev      : LREAL;                   // 偏差中间值 [%] EN: the interim deviation value
END_VAR
VAR CONSTANT
    DL_RPR_Z       : LREAL := 0.0;       // 浮点零常量 EN: the floating point zero constant
    DL_RPR_HUNDRED : LREAL := 100.0;     // 百分数换算系数 EN: the percent conversion factor
    DL_RPR_DEN_MIN : LREAL := 1.0E-9;    // 分母绝对值下限 [m3/h] EN: the lower bound of the divisor magnitude
    DL_RPR_C_BAD   : INT := 9801;        // 输入非法 EN: an illegal input
    DL_RPR_C_DEN   : INT := 9802;        // 水相流量过小 EN: the aqueous phase flow is too small
    DL_RPR_C_TOL   : INT := 9803;        // 容差越域 EN: the tolerance is out of range
END_VAR

// 段1｜出口预置
FC_DL_RePhaseRatioCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rRatioOA := DL_RPR_Z;              // 相比预置零 [-] EN: preset the phase ratio to zero
rFlowTotalM3h := DL_RPR_Z;         // 总流量预置零 [m3/h] EN: preset the total flow to zero
rDevPct := DL_RPR_Z;               // 偏差预置零 [%] EN: preset the deviation to zero
xTotalMatch := FALSE;              // 一致标志预置假 EN: preset the agreement flag to false
xValid := FALSE;                   // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                   // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四个浮点入参全列，容差虽为限值但不入闸则一致性判据可被 NaN 击穿
xFinAll := (rFlowOrgM3h = rFlowOrgM3h) AND ((rFlowOrgM3h - rFlowOrgM3h) = DL_RPR_Z)
        AND (rFlowAqM3h = rFlowAqM3h) AND ((rFlowAqM3h - rFlowAqM3h) = DL_RPR_Z)
        AND (rFlowTotalMeasM3h = rFlowTotalMeasM3h) AND ((rFlowTotalMeasM3h - rFlowTotalMeasM3h) = DL_RPR_Z)
        AND (rTotalTolPct = rTotalTolPct) AND ((rTotalTolPct - rTotalTolPct) = DL_RPR_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_RPR_C_BAD;                                                              // 输入非法码 EN: the illegal input code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：两流量非负、水相流量过分母下限、容差落在 (0,100] 域内
xNegFlow := (rFlowOrgM3h < DL_RPR_Z) OR (rFlowAqM3h < DL_RPR_Z);                             // 负流量判据 EN: the negative flow test
rDen := rFlowAqM3h;                                                                          // 取分母 [m3/h] EN: take the divisor
IF xNegFlow OR (ABS(rDen) < DL_RPR_DEN_MIN) THEN                                             // 流量域闸 EN: the flow domain gate
    nFaultCode := DL_RPR_C_DEN;                                                              // 流量非法码 EN: the flow code
    RETURN;                                                                                  // 早退 EN: return early
END_IF
IF (rTotalTolPct <= DL_RPR_Z) OR (rTotalTolPct > DL_RPR_HUNDRED) THEN                        // 容差域闸 EN: the tolerance domain gate
    nFaultCode := DL_RPR_C_TOL;                                                              // 容差越域码 EN: the tolerance code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段4｜主体：相比与计算总流量
rTotal := rFlowOrgM3h + rFlowAqM3h;                                                          // 计算总流量 [m3/h] EN: the computed total flow
rRatioOA := rFlowOrgM3h / rDen;                                                              // 相比 O/A [-] EN: the phase ratio
rFlowTotalM3h := rTotal;                                                                     // 总流量出口 [m3/h] EN: the total flow output

// 段5｜一致性校验：偏差以计算总流量为分母，先证其过下限
IF ABS(rTotal) < DL_RPR_DEN_MIN THEN                                                         // 总流量分母下限 EN: the total flow divisor gate
    rDev := DL_RPR_Z;                                                                        // 偏差给零 [%] EN: give a zero deviation
    xTotalMatch := FALSE;                                                                    // 不可比，判不一致 EN: not comparable, report a mismatch
ELSE
    rDev := (rFlowTotalMeasM3h - rTotal) / rTotal * DL_RPR_HUNDRED;                         // 相对偏差 [%] EN: the relative deviation
    xTotalMatch := ABS(rDev) <= rTotalTolPct;                                                // 容差比较 EN: the tolerance comparison
END_IF
rDevPct := rDev;                                                                             // 偏差出口 [%] EN: the deviation output
xValid := TRUE;                                                                              // 结果可信 EN: the results are valid
FC_DL_RePhaseRatioCalc := TRUE;                                                              // 返回真 EN: return true
END_FUNCTION
