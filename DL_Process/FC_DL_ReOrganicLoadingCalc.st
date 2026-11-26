(*
  Component : FC_DL_ReOrganicLoadingCalc
  Category  : DL_Process
  Function  : 有机相稀土负载 g/L = 水相浓度 × 水相流量 / 有机相流量
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rAqConcGpl 水相稀土浓度 [g/L]、rFlowAqM3h 水相流量 [m3/h]、rFlowOrgM3h 有机相流量 [m3/h]、
             rLoadMaxGpl 负载上限 [g/L]；输出 rLoadingGpl 有机相负载 [g/L]、rLoadingPct 占上限百分比 [%]、
             xOverLoad 超负载上限（信息级）、xValid 有效标志、nFaultCode 故障码。
  边界     : 有机相流量须 >1.0E-9 [m3/h]（分母下限）；水相浓度须 ≥0；负流量属测量故障判 9801；
             浓度与流量同单位相乘再除，量纲为 g/L，体积流量单位在分子分母相消，无需额外换算系数。
  码位     : 9801 输入非法（故障级）；9802 有机相流量过小（故障级）。
*)
FUNCTION FC_DL_ReOrganicLoadingCalc : BOOL
VAR_INPUT
    rAqConcGpl    : LREAL := 100.0;  // 水相稀土浓度 [g/L] EN: the rare earth concentration of the aqueous phase
    rFlowAqM3h    : LREAL := 5.0;    // 水相体积流量 [m3/h] EN: the volumetric flow of the aqueous phase
    rFlowOrgM3h   : LREAL := 5.0;    // 有机相体积流量 [m3/h] EN: the volumetric flow of the organic phase
    rLoadMaxGpl   : LREAL := 25.0;   // 有机相负载上限 [g/L] EN: the upper limit of the organic phase loading
END_VAR
VAR_OUTPUT
    rLoadingGpl : LREAL;             // 有机相稀土负载 [g/L] EN: the rare earth loading of the organic phase
    rLoadingPct : LREAL;             // 负载占上限的百分比 [%] EN: the loading expressed as a percent of the limit
    xOverLoad   : BOOL;              // 超负载上限（信息级，不置故障） EN: above the loading limit, information class only
    xValid      : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;               // 0=无故障 9801=输入非法 9802=有机相流量过小 EN: zero none, 9801 illegal input, 9802 organic flow too small
END_VAR
VAR
    xFinAll : BOOL;                  // 四输入同时有限 EN: all four inputs are finite
    rDen    : LREAL;                 // 分母（有机相流量） [m3/h] EN: the divisor, the organic phase flow
    rLoad   : LREAL;                 // 负载中间值 [g/L] EN: the interim loading value
END_VAR
VAR CONSTANT
    DL_ROL_Z       : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_ROL_HUNDRED : LREAL := 100.0;  // 百分数换算系数 EN: the percent conversion factor
    DL_ROL_DEN_MIN : LREAL := 1.0E-9; // 分母绝对值下限 [m3/h] EN: the lower bound of the divisor magnitude
    DL_ROL_C_BAD   : INT := 9801;     // 输入非法 EN: an illegal input
    DL_ROL_C_DEN   : INT := 9802;     // 有机相流量过小 EN: the organic phase flow is too small
END_VAR

// 段1｜出口预置
FC_DL_ReOrganicLoadingCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rLoadingGpl := DL_ROL_Z;               // 负载预置零 [g/L] EN: preset the loading to zero
rLoadingPct := DL_ROL_Z;               // 负载百分比预置零 [%] EN: preset the loading percent to zero
xOverLoad := FALSE;                    // 超限标志预置假 EN: preset the overload flag to false
xValid := FALSE;                       // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                       // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四个浮点入参全列（上限参与百分比判据，漏则超限判据静默失效）
xFinAll := (rAqConcGpl = rAqConcGpl) AND ((rAqConcGpl - rAqConcGpl) = DL_ROL_Z)
        AND (rFlowAqM3h = rFlowAqM3h) AND ((rFlowAqM3h - rFlowAqM3h) = DL_ROL_Z)
        AND (rFlowOrgM3h = rFlowOrgM3h) AND ((rFlowOrgM3h - rFlowOrgM3h) = DL_ROL_Z)
        AND (rLoadMaxGpl = rLoadMaxGpl) AND ((rLoadMaxGpl - rLoadMaxGpl) = DL_ROL_Z);         // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_ROL_C_BAD;                                                              // 输入非法码 EN: the illegal input code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：浓度非负、两流量非负，有机相流量为分母须过下限
rDen := rFlowOrgM3h;                                                                         // 取分母 [m3/h] EN: take the divisor
IF (rAqConcGpl < DL_ROL_Z) OR (rFlowAqM3h < DL_ROL_Z) OR (ABS(rDen) < DL_ROL_DEN_MIN) THEN   // 域闸 EN: the domain gate
    nFaultCode := DL_ROL_C_DEN;                                                              // 流量或域非法码 EN: the flow or domain code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段4｜主体：负载 = 浓度 × 水相流量 / 有机相流量
rLoad := (rAqConcGpl * rFlowAqM3h) / rDen;                                                   // 负载 [g/L] EN: the organic phase loading
IF (rLoad <> rLoad) OR (rLoad < DL_ROL_Z) THEN                                               // 结果复检：非有限或负 EN: recheck for a non finite or negative result
    nFaultCode := DL_ROL_C_BAD;                                                              // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                  // 早退，出口保持零哨兵 EN: return early with the zero sentinel
END_IF

// 段5｜出口：百分比仅在限值 >0 时计算，否则以 0 表达不可比
rLoadingGpl := rLoad;                                                                        // 负载出口 [g/L] EN: the loading output
IF rLoadMaxGpl > DL_ROL_Z THEN                                                               // 限值有效性 EN: the limit is usable
    rLoadingPct := (rLoad / rLoadMaxGpl) * DL_ROL_HUNDRED;                                   // 占限百分比 [%] EN: the percent of the limit
ELSE
    rLoadingPct := DL_ROL_Z;                                                                 // 限值无效时给零 [%] EN: give zero when the limit is unusable
END_IF
xOverLoad := (rLoadMaxGpl > DL_ROL_Z) AND (rLoad > rLoadMaxGpl);                             // 超限判据（信息级） EN: the overload test, information class only
xValid := TRUE;                                                                              // 结果可信 EN: the results are valid
FC_DL_ReOrganicLoadingCalc := TRUE;                                                          // 返回真 EN: return true
END_FUNCTION
