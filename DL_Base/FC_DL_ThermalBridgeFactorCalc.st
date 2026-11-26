(*
  Component : FC_DL_ThermalBridgeFactorCalc
  Category  : DL_Base
  Function  : 热桥线性修正系数：按支架/法兰间距把点热桥折算为附加系数 f = 1 + k / L
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rSpacingM 支架或法兰间距 [m]、rBridgeCoefM 单点热桥等效附加长度系数 [m]、
             rFactorMax 修正系数上限 [-]，rSpacingMinM 允许最小间距 [m]；
             输出 rFactor 线性修正系数 [-]、rExtraRatioPct 附加散热百分比 [%]、
             xFactorHigh 触修正上限（信息级）、xSpacingBad 间距过小（信息级）、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 间距为分母须 ≥ 允许最小间距（默认 0.1 [m]），小于该值视为不可信布置，按最小间距取值并置
             xSpacingBad（信息级，不中断输出）；热桥系数须 ≥0；修正系数按上限钳位（上限反算：
             1.0E3 远小于 LREAL 上限，可表）。
  码位     : 9801 输入非有限（故障级）；9802 间距或热桥系数越域（故障级）。
*)
FUNCTION FC_DL_ThermalBridgeFactorCalc : BOOL
VAR_INPUT
    rSpacingM      : LREAL := 2.0;    // 支架或法兰间距 [m] EN: the spacing between supports or flanges
    rBridgeCoefM   : LREAL := 0.15;   // 单点热桥等效附加长度系数 [m] EN: the equivalent additional length per thermal bridge
    rFactorMax     : LREAL := 3.0;    // 修正系数上限 [-] EN: the upper bound of the correction factor
    rSpacingMinM   : LREAL := 0.1;    // 允许最小间距 [m] EN: the minimum allowed spacing
END_VAR
VAR_OUTPUT
    rFactor      : LREAL;             // 线性修正系数 [-] EN: the linear correction factor
    rExtraRatioPct: LREAL;            // 附加散热百分比 [%] EN: the additional heat loss in percent
    xFactorHigh  : BOOL;              // 触修正上限（信息级） EN: the correction reached the upper bound, information class only
    xSpacingBad  : BOOL;              // 间距过小（信息级） EN: the spacing is too small, information class only
    xValid       : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;               // 0=无故障 9801=输入非有限 9802=间距或系数越域 EN: zero none, 9801 non finite, 9802 spacing or coefficient out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 四输入同时有限 EN: all four inputs are finite
    rSpUse  : LREAL;                  // 实际使用的间距 [m] EN: the spacing in use
    rFac    : LREAL;                  // 修正系数中间值 [-] EN: the interim correction factor
END_VAR
VAR CONSTANT
    DL_TBF_Z     : LREAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_TBF_ONE   : LREAL := 1.0;      // 浮点壹常量 EN: the floating point one constant
    DL_TBF_HUND  : LREAL := 100.0;    // 百分数换算系数 EN: the percent conversion factor
    DL_TBF_MIN   : LREAL := 1.0E-6;   // 间距分母下限 [m] EN: the lower bound of the spacing divisor
    DL_TBF_C_BAD : INT := 9801;       // 输入非有限 EN: a non finite input
    DL_TBF_C_RANG: INT := 9802;       // 间距或系数越域 EN: the spacing or the coefficient is out of range
END_VAR

// 段1｜出口预置
FC_DL_ThermalBridgeFactorCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rFactor := DL_TBF_Z;                      // 修正系数预置零 [-] EN: preset the factor to zero
rExtraRatioPct := DL_TBF_Z;               // 附加百分比预置零 [%] EN: preset the extra ratio to zero
xFactorHigh := FALSE;                     // 触限标志预置假 EN: preset the bound flag to false
xSpacingBad := FALSE;                     // 间距标志预置假 EN: preset the spacing flag to false
xValid := FALSE;                          // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                          // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四输入全列
xFinAll := (rSpacingM = rSpacingM) AND ((rSpacingM - rSpacingM) = DL_TBF_Z)
        AND (rBridgeCoefM = rBridgeCoefM) AND ((rBridgeCoefM - rBridgeCoefM) = DL_TBF_Z)
        AND (rFactorMax = rFactorMax) AND ((rFactorMax - rFactorMax) = DL_TBF_Z)
        AND (rSpacingMinM = rSpacingMinM) AND ((rSpacingMinM - rSpacingMinM) = DL_TBF_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                        // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_TBF_C_BAD;                                                            // 非有限码 EN: the non finite code
    RETURN;                                                                                // 早退 EN: return early
END_IF

// 段3｜域闸：热桥系数非负、最小间距为正、上限 ≥1
IF (rBridgeCoefM < DL_TBF_Z) OR (rSpacingMinM < DL_TBF_MIN) OR (rFactorMax < DL_TBF_ONE) THEN
    nFaultCode := DL_TBF_C_RANG;                                                           // 越域码 EN: the out of range code
    RETURN;                                                                                // 早退 EN: return early
END_IF

// 段4｜间距域：过小按最小间距取值并置信息级标志（不中断输出）
IF rSpacingM < rSpacingMinM THEN                                                           // 间距过小判据 EN: the small spacing test
    rSpUse := rSpacingMinM;                                                                // 按最小间距取值 [m] EN: clamp to the minimum spacing
    xSpacingBad := TRUE;                                                                   // 置信息级标志 EN: raise the information class flag
ELSE
    rSpUse := rSpacingM;                                                                   // 域内直接使用 [m] EN: use the spacing as given
END_IF

// 段5｜主体：f = 1 + k / L，再按上限钳位
rFac := DL_TBF_ONE + (rBridgeCoefM / rSpUse);                                              // 修正系数，分母已证正 [-] EN: the correction factor, the divisor is proven positive
IF rFac > rFactorMax THEN                                                                  // 上限钳位 EN: clamp the upper bound
    rFac := rFactorMax;                                                                    // 钳到上限 [-] EN: clamp to the upper bound
    xFactorHigh := TRUE;                                                                    // 置触限标志 EN: raise the bound flag
END_IF
IF (rFac <> rFac) OR (rFac < DL_TBF_ONE) THEN                                              // 复检：非有限或小于 1（小于 1 无物理意义） EN: recheck the result
    nFaultCode := DL_TBF_C_RANG;                                                           // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段6｜出口
rFactor := rFac;                                                                           // 修正系数出口 [-] EN: the factor output
rExtraRatioPct := (rFac - DL_TBF_ONE) * DL_TBF_HUND;                                       // 附加散热百分比 [%] EN: the additional loss in percent
xValid := TRUE;                                                                            // 结果可信 EN: the results are valid
FC_DL_ThermalBridgeFactorCalc := TRUE;                                                      // 返回真 EN: return true
END_FUNCTION
