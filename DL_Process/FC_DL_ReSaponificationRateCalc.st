(*
  Component : FC_DL_ReSaponificationRateCalc
  Category  : DL_Process
  Function  : 皂化率 = 实际皂化碱量 / 理论碱量 × 100，并钳位到 0~100
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rAlkaliActual 实际皂化碱量 [kg/h]、rAlkaliTheory 理论皂化碱量 [kg/h]、
             rRateHighLimit 判定上限 [%]；输出 rRateRaw 未钳位皂化率 [%]、rRatePct 钳位后皂化率 [%]、
             xClamped 钳位发生标志、xOverRate 超判定上限标志、xValid 有效标志、nFaultCode 故障码。
  边界     : 理论碱量须 >1.0E-9 [kg/h]，否则判 9802；实际碱量为负判 9801（负投加不可能，属测量故障）；
             钳位范围 0~100 [%] 为物理可实现域；xClamped 只表达本拍是否发生钳位，不置故障。
  码位     : 9801 输入非法（故障级）；9802 理论碱量过小（故障级）。信息级钳位不派码，由 xClamped 表达。
*)
FUNCTION FC_DL_ReSaponificationRateCalc : BOOL
VAR_INPUT
    rAlkaliActual   : LREAL := 10.0;   // 实际皂化碱量 [kg/h] EN: the actual alkali mass flow used for saponification
    rAlkaliTheory   : LREAL := 12.0;   // 理论皂化碱量 [kg/h] EN: the theoretical alkali mass flow required by stoichiometry
    rRateHighLimit  : LREAL := 100.0;  // 皂化率合格上限 [%] EN: the upper limit of an acceptable saponification rate
END_VAR
VAR_OUTPUT
    rRateRaw   : LREAL;                // 未钳位皂化率 [%] EN: the saponification rate before clamping
    rRatePct   : LREAL;                // 钳位后皂化率，域 0~100 [%] EN: the saponification rate clamped to zero through one hundred
    xClamped   : BOOL;                 // 本拍发生钳位 EN: a clamp occurred in this cycle
    xOverRate  : BOOL;                 // 超判定上限（信息级） EN: the rate exceeds the upper limit, an information class flag
    xValid     : BOOL;                 // 输出可信标志 EN: the outputs are valid
    nFaultCode : INT;                  // 0=无故障 9801=输入非法 9802=理论碱量过小 EN: zero none, 9801 illegal input, 9802 theoretical alkali too small
END_VAR
VAR
    xFinAll  : BOOL;                   // 三输入同时有限 EN: all three inputs are finite
    xNegAct  : BOOL;                   // 实际碱量为负 EN: the actual alkali flow is negative
    rDen     : LREAL;                  // 分母（理论碱量） [kg/h] EN: the divisor, the theoretical alkali flow
    rRaw     : LREAL;                  // 皂化率中间值 [%] EN: the interim saponification rate
    rClamp   : LREAL;                  // 钳位结果 [%] EN: the clamped result
END_VAR
VAR CONSTANT
    DL_SSR_Z       : LREAL := 0.0;     // 浮点零常量 EN: the floating point zero constant
    DL_SSR_HUNDRED : LREAL := 100.0;   // 百分数换算系数 EN: the percent conversion factor
    DL_SSR_DEN_MIN : LREAL := 1.0E-9;  // 分母绝对值下限 [kg/h] EN: the lower bound of the divisor magnitude
    DL_SSR_C_BAD   : INT := 9801;      // 输入非法 EN: an illegal input
    DL_SSR_C_DEN   : INT := 9802;      // 理论碱量过小 EN: the theoretical alkali flow is too small
END_VAR

// 段1｜出口预置
FC_DL_ReSaponificationRateCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rRateRaw := DL_SSR_Z;                      // 未钳位皂化率预置零 [%] EN: preset the raw rate to zero
rRatePct := DL_SSR_Z;                      // 钳位皂化率预置零 [%] EN: preset the clamped rate to zero
xClamped := FALSE;                         // 钳位标志预置假 EN: preset the clamp flag to false
xOverRate := FALSE;                        // 超限标志预置假 EN: preset the over rate flag to false
xValid := FALSE;                           // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                           // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三个浮点入参逐一列入（上限限值同样参与判据换算，不可漏）
xFinAll := (rAlkaliActual = rAlkaliActual) AND ((rAlkaliActual - rAlkaliActual) = DL_SSR_Z)
        AND (rAlkaliTheory = rAlkaliTheory) AND ((rAlkaliTheory - rAlkaliTheory) = DL_SSR_Z)
        AND (rRateHighLimit = rRateHighLimit) AND ((rRateHighLimit - rRateHighLimit) = DL_SSR_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                                                  // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_SSR_C_BAD;                                                                      // 输入非法码 EN: the illegal input code
    RETURN;                                                                                          // 早退 EN: return early
END_IF

// 段3｜域闸：理论碱量为分母须足够大；实际碱量不得为负（负投加属测量方向故障）
rDen := rAlkaliTheory;                                                                               // 取分母 [kg/h] EN: take the divisor
xNegAct := rAlkaliActual < DL_SSR_Z;                                                                 // 负投加判据 EN: the negative dosing test
IF (ABS(rDen) < DL_SSR_DEN_MIN) OR xNegAct OR (rRateHighLimit <= DL_SSR_Z) THEN                     // 域闸 EN: the domain gate
    nFaultCode := DL_SSR_C_DEN;                                                                      // 分母或域非法码 EN: the divisor or domain code
    RETURN;                                                                                          // 早退 EN: return early
END_IF

// 段4｜主体：raw = 实际 / 理论 × 100，钳位 0~100
rRaw := (rAlkaliActual / rDen) * DL_SSR_HUNDRED;                                                     // 未钳位皂化率 [%] EN: the saponification rate before clamping
rClamp := rRaw;                                                                                      // 钳位工作副本 [%] EN: the working copy for clamping
IF rClamp < DL_SSR_Z THEN                                                                            // 下钳位 EN: clamp the lower bound
    rClamp := DL_SSR_Z;                                                                              // 钳到零 [%] EN: clamp to zero
    xClamped := TRUE;                                                                                // 置钳位标志 EN: raise the clamp flag
END_IF
IF rClamp > DL_SSR_HUNDRED THEN                                                                      // 上钳位 EN: clamp the upper bound
    rClamp := DL_SSR_HUNDRED;                                                                        // 钳到一百 [%] EN: clamp to one hundred
    xClamped := TRUE;                                                                                // 置钳位标志 EN: raise the clamp flag
END_IF

// 段5｜出口：名实双出口同源赋值，超限为信息级不置故障
rRateRaw := rRaw;                                                                                    // 未钳位出口 [%] EN: the raw rate output
rRatePct := rClamp;                                                                                  // 钳位出口 [%] EN: the clamped rate output
xOverRate := rClamp > rRateHighLimit;                                                                // 超判定上限（信息级） EN: above the acceptance limit, information class only
xValid := TRUE;                                                                                      // 结果可信 EN: the results are valid
FC_DL_ReSaponificationRateCalc := TRUE;                                                              // 返回真 EN: return true
END_FUNCTION
