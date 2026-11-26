(*
  Component : FC_DL_ReStageEfficiencyCalc
  Category  : DL_Process
  Function  : 单级萃取效率 = 实际萃取量 / 平衡萃取量 × 100，并钳位到 0~100
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rActualExtractGpl 实际萃取量 [g/L]、rEquilExtractGpl 平衡萃取量 [g/L]、
             rEffHighPct 效率合格下限 [%]；输出 rEffRawPct 未钳位效率 [%]、rEffPct 钳位后效率 [%]、
             xClamped 本拍钳位、xEffLow 效率低于合格下限（信息级）、xValid 有效标志、nFaultCode 故障码。
  边界     : 平衡萃取量为分母须 >1.0E-9 [g/L]；实际萃取量为负判 9801（负萃取属测量方向故障）；
             钳位域 0~100 [%]；xEffLow 为信息级，不置故障，仅当效率低于合格下限时置位。
  码位     : 9801 输入非法（故障级）；9802 平衡萃取量过小（故障级）。
*)
FUNCTION FC_DL_ReStageEfficiencyCalc : BOOL
VAR_INPUT
    rActualExtractGpl : LREAL := 8.0;    // 单级实际萃取量 [g/L] EN: the rare earth mass actually extracted in one stage
    rEquilExtractGpl  : LREAL := 10.0;   // 单级平衡萃取量 [g/L] EN: the rare earth mass extracted at equilibrium in one stage
    rEffHighPct       : LREAL := 90.0;   // 单级效率合格下限 [%] EN: the lower acceptance limit of the single stage efficiency
END_VAR
VAR_OUTPUT
    rEffRawPct : LREAL;                  // 未钳位单级效率 [%] EN: the single stage efficiency before clamping
    rEffPct    : LREAL;                  // 钳位后单级效率，域 0~100 [%] EN: the single stage efficiency clamped to zero through one hundred
    xClamped   : BOOL;                   // 本拍发生钳位 EN: a clamp occurred in this cycle
    xEffLow    : BOOL;                   // 效率低于合格下限（信息级） EN: the efficiency is below the acceptance limit, information class only
    xValid     : BOOL;                   // 输出可信标志 EN: the outputs are valid
    nFaultCode : INT;                    // 0=无故障 9801=输入非法 9802=平衡量过小 EN: zero none, 9801 illegal input, 9802 equilibrium mass too small
END_VAR
VAR
    xFinAll : BOOL;                      // 三输入同时有限 EN: all three inputs are finite
    rDen    : LREAL;                     // 分母（平衡萃取量） [g/L] EN: the divisor, the equilibrium extracted mass
    rRaw    : LREAL;                     // 效率中间值 [%] EN: the interim efficiency value
    rClamp  : LREAL;                     // 钳位工作副本 [%] EN: the working copy for clamping
END_VAR
VAR CONSTANT
    DL_RSE_Z       : LREAL := 0.0;       // 浮点零常量 EN: the floating point zero constant
    DL_RSE_HUNDRED : LREAL := 100.0;     // 百分数换算系数 EN: the percent conversion factor
    DL_RSE_DEN_MIN : LREAL := 1.0E-9;    // 分母绝对值下限 [g/L] EN: the lower bound of the divisor magnitude
    DL_RSE_C_BAD   : INT := 9801;        // 输入非法 EN: an illegal input
    DL_RSE_C_DEN   : INT := 9802;        // 平衡萃取量过小 EN: the equilibrium mass is too small
END_VAR

// 段1｜出口预置
FC_DL_ReStageEfficiencyCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rEffRawPct := DL_RSE_Z;                 // 未钳位效率预置零 [%] EN: preset the raw efficiency to zero
rEffPct := DL_RSE_Z;                    // 钳位效率预置零 [%] EN: preset the clamped efficiency to zero
xClamped := FALSE;                      // 钳位标志预置假 EN: preset the clamp flag to false
xEffLow := FALSE;                       // 低效标志预置假 EN: preset the low efficiency flag to false
xValid := FALSE;                        // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                        // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三输入全列（合格下限参与出口判据，漏则低效判据失效）
xFinAll := (rActualExtractGpl = rActualExtractGpl) AND ((rActualExtractGpl - rActualExtractGpl) = DL_RSE_Z)
        AND (rEquilExtractGpl = rEquilExtractGpl) AND ((rEquilExtractGpl - rEquilExtractGpl) = DL_RSE_Z)
        AND (rEffHighPct = rEffHighPct) AND ((rEffHighPct - rEffHighPct) = DL_RSE_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                                     // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_RSE_C_BAD;                                                         // 输入非法码 EN: the illegal input code
    RETURN;                                                                             // 早退 EN: return early
END_IF

// 段3｜域闸：实际量非负、平衡量过分母下限
rDen := rEquilExtractGpl;                                                               // 取分母 [g/L] EN: take the divisor
IF (rActualExtractGpl < DL_RSE_Z) OR (ABS(rDen) < DL_RSE_DEN_MIN) THEN                  // 域闸 EN: the domain gate
    nFaultCode := DL_RSE_C_DEN;                                                         // 分母或域非法码 EN: the divisor or domain code
    RETURN;                                                                             // 早退 EN: return early
END_IF

// 段4｜主体：eff = 实际 / 平衡 × 100
rRaw := (rActualExtractGpl / rDen) * DL_RSE_HUNDRED;                                    // 未钳位效率 [%] EN: the efficiency before clamping
rClamp := rRaw;                                                                         // 钳位工作副本 [%] EN: the working copy for clamping
IF rClamp < DL_RSE_Z THEN                                                               // 下钳位 EN: clamp the lower bound
    rClamp := DL_RSE_Z;                                                                 // 钳到零 [%] EN: clamp to zero
    xClamped := TRUE;                                                                   // 置钳位标志 EN: raise the clamp flag
END_IF
IF rClamp > DL_RSE_HUNDRED THEN                                                         // 上钳位 EN: clamp the upper bound
    rClamp := DL_RSE_HUNDRED;                                                           // 钳到一百 [%] EN: clamp to one hundred
    xClamped := TRUE;                                                                   // 置钳位标志 EN: raise the clamp flag
END_IF

// 段5｜出口：名实双出口同源赋值；低效为信息级，不置故障
rEffRawPct := rRaw;                                                                     // 未钳位出口 [%] EN: the raw efficiency output
rEffPct := rClamp;                                                                      // 钳位出口 [%] EN: the clamped efficiency output
xEffLow := rClamp < rEffHighPct;                                                        // 低效判据（信息级） EN: the low efficiency test, information class only
xValid := TRUE;                                                                         // 结果可信 EN: the results are valid
FC_DL_ReStageEfficiencyCalc := TRUE;                                                    // 返回真 EN: return true
END_FUNCTION
