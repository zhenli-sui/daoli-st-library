(*
  Component : FC_DL_ReExtractionFactorCalc
  Category  : DL_Process
  Function  : 稀土溶剂萃取分配比 D 与单级萃取率 E 换算，E = D / (D + O/A)
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rDistCoefD 分配比 [-]，rRatioOA 相比 O/A [-]；输出 rExtractFrac 萃取率 [0~1]、
             rExtractPct 萃取率 [%]、xValid 有效标志、nFaultCode 故障码；返回 TRUE 表示两输出可信。
  边界     : 分配比须 ≥0、相比须 >0；分母 D+O/A 绝对值 <1.0E-9 判 9802；任一浮点输入非有限判 9801；
             无除法以外的失效面，零全局、零物理地址、零库件依赖。
  码位     : 9801 输入非法（故障级）；9802 分母过小（故障级）。二者不并存，9801 先判。
*)
FUNCTION FC_DL_ReExtractionFactorCalc : BOOL
VAR_INPUT
    rDistCoefD : LREAL := 1.0;        // 分配比 D，有机相稀土浓度与水相稀土浓度之比 [-] EN: distribution ratio D of organic to aqueous rare earth concentration
    rRatioOA   : LREAL := 1.0;        // 相比 O/A，有机相体积流量与水相体积流量之比 [-] EN: organic to aqueous volumetric phase ratio O over A
END_VAR
VAR_OUTPUT
    rExtractFrac : LREAL;             // 单级萃取率 E 的无量纲值，域 0~1 [-] EN: single stage extraction fraction within the range zero to one
    rExtractPct  : LREAL;             // 单级萃取率 E 的百分数 [%] EN: single stage extraction efficiency expressed in percent
    xValid       : BOOL;              // 两输出可信标志 EN: both outputs are valid
    nFaultCode   : INT;               // 0=无故障 9801=分配比或相比非法 9802=分母过小 EN: zero none, 9801 illegal input, 9802 denominator too small
END_VAR
VAR
    xFinD  : BOOL;                    // 分配比有限性 EN: the distribution ratio is finite
    xFinOA : BOOL;                    // 相比有限性 EN: the phase ratio is finite
    xFinAll: BOOL;                    // 两输入同时有限 EN: both inputs are finite at the same time
    rDen   : LREAL;                   // 萃取率分母 D + O/A [-1] EN: the denominator of the extraction rate
    rFrac  : LREAL;                   // 萃取率中间值，钳位后写入出口 [-] EN: the interim extraction fraction before clamping
END_VAR
VAR CONSTANT
    DL_REF_Z       : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_REF_ONE     : LREAL := 1.0;    // 浮点壹常量 EN: the floating point one constant
    DL_REF_HUNDRED : LREAL := 100.0;  // 百分数换算系数 EN: the percent conversion factor
    DL_REF_DEN_MIN : LREAL := 1.0E-9; // 分母绝对值下限 EN: the lower bound of the denominator magnitude
    DL_REF_C_BAD   : INT := 9801;     // 分配比或相比非法 EN: illegal distribution ratio or phase ratio
    DL_REF_C_DEN   : INT := 9802;     // 分母过小不可除 EN: the denominator is too small to divide
END_VAR

// 段1｜出口预置：函数名即返回值，先置假与哨兵零，任何早退分支都停在此状态
FC_DL_ReExtractionFactorCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rExtractFrac := DL_REF_Z;                // 萃取率预置零 [0~1] EN: preset the extraction fraction to zero
rExtractPct := DL_REF_Z;                 // 萃取率百分数预置零 [%] EN: preset the extraction percent to zero
xValid := FALSE;                         // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                         // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：NaN 用自反判、Inf 用差值自减判，两输入全部列入闸内
xFinD := (rDistCoefD = rDistCoefD) AND ((rDistCoefD - rDistCoefD) = DL_REF_Z);   // 分配比有限性 EN: the distribution ratio is finite
xFinOA := (rRatioOA = rRatioOA) AND ((rRatioOA - rRatioOA) = DL_REF_Z);           // 相比有限性 EN: the phase ratio is finite
xFinAll := xFinD AND xFinOA;                                                     // 合并有限性 EN: the combined finiteness
IF NOT xFinAll THEN                                                              // 非有限直接出口 EN: leave early on a non finite input
    nFaultCode := DL_REF_C_BAD;                                                  // 输入非法码 EN: the illegal input code
    RETURN;                                                                      // 早退：出口保持预置值 EN: return early, the outputs keep the preset values
END_IF

// 段3｜域闸：分配比非负、相比为正，否则物理上无意义
IF (rDistCoefD < DL_REF_Z) OR (rRatioOA <= DL_REF_Z) THEN                        // 域闸：负分配比或非正相比 EN: a negative distribution ratio or a non positive phase ratio
    nFaultCode := DL_REF_C_BAD;                                                  // 输入非法码 EN: the illegal input code
    RETURN;                                                                      // 早退 EN: return early
END_IF

// 段4｜分母下限保护：分母由两项正量相加，仍按绝对值下限硬校验防浮点下溢
rDen := rDistCoefD + rRatioOA;                                                   // 组成萃取率分母 [-] EN: build the denominator of the extraction rate
IF ABS(rDen) < DL_REF_DEN_MIN THEN                                               // 分母下限判据 EN: the denominator magnitude gate
    nFaultCode := DL_REF_C_DEN;                                                  // 分母过小码 EN: the denominator too small code
    RETURN;                                                                      // 早退 EN: return early
END_IF

// 段5｜主体换算：E = D / (D + O/A)，两输出同一来源，避免名实不一致
rFrac := rDistCoefD / rDen;                                                      // 计算萃取率 [-] EN: compute the extraction fraction
IF rFrac < DL_REF_Z THEN                                                         // 钳位下界（仅防御浮点残差） EN: clamp the lower bound against a residual sign error
    rFrac := DL_REF_Z;                                                           // 钳到零 EN: clamp to zero
END_IF
IF rFrac > DL_REF_ONE THEN                                                       // 钳位上界 EN: clamp the upper bound
    rFrac := DL_REF_ONE;                                                         // 钳到壹 EN: clamp to one
END_IF
rExtractFrac := rFrac;                                                           // 无量纲出口 [-] EN: the dimensionless output
rExtractPct := rFrac * DL_REF_HUNDRED;                                           // 百分数出口 [%] EN: the percent output
xValid := TRUE;                                                                  // 结果可信 EN: the results are valid
nFaultCode := 0;                                                                 // 无故障 EN: no fault
FC_DL_ReExtractionFactorCalc := TRUE;                                            // 返回真 EN: return true
END_FUNCTION
