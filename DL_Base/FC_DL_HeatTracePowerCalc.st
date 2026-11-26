(*
  Component : FC_DL_HeatTracePowerCalc
  Category  : DL_Base
  Function  : 电伴热功率 = 单位热损 × 安全系数，给出每米功率、总功率与工作电流
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rLossWm 单位管长设计热损 [W/m]、rSafetyFactor 安全系数 [-]、
             rLengthM 伴热管长 [m]、rVoltageV 供电电压 [V]、rFactorMax 安全系数上限 [-]；
             输出 rPowerWm 每米伴热功率 [W/m]、rPowerTotalW 总伴热功率 [W]、
             rCurrentA 工作电流 [A]、xFactorHigh 安全系数越域（信息级，按上限取值）、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 热损须 ≥0、管长须 ≥0、安全系数须 ≥1 且不超过上限（越域按上限取值并置信息级标志）；
             电压为分母须 >1.0E-6 [V]，否则电流输出 0（不判故障，允许未接线组态）；
             功率上限反算：1.0E4 [W/m] × 1.0E4 [m] ≤ 1.0E8 [W]，远小于 LREAL 上限，可表。
  码位     : 9801 输入非有限（故障级）；9802 热损、管长或安全系数越域（故障级）。
*)
FUNCTION FC_DL_HeatTracePowerCalc : BOOL
VAR_INPUT
    rLossWm      : LREAL := 40.0;    // 单位管长设计热损 [W/m] EN: the design heat loss per metre of pipe
    rSafetyFactor: LREAL := 1.25;    // 安全系数 [-] EN: the safety factor
    rLengthM     : LREAL := 50.0;    // 伴热管长 [m] EN: the traced pipe length
    rVoltageV    : LREAL := 220.0;   // 供电电压 [V] EN: the supply voltage
    rFactorMax   : LREAL := 2.0;     // 安全系数上限 [-] EN: the upper bound of the safety factor
END_VAR
VAR_OUTPUT
    rPowerWm     : LREAL;            // 每米伴热功率 [W/m] EN: the heat tracing power per metre
    rPowerTotalW : LREAL;            // 总伴热功率 [W] EN: the total heat tracing power
    rCurrentA    : LREAL;            // 工作电流 [A] EN: the operating current
    xFactorHigh  : BOOL;             // 安全系数越域（信息级） EN: the safety factor is out of range, information class only
    xValid       : BOOL;             // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;              // 0=无故障 9801=输入非有限 9802=热损或管长或系数越域 EN: zero none, 9801 non finite, 9802 loss, length or factor out of range
END_VAR
VAR
    xFinAll : BOOL;                  // 五输入同时有限 EN: all five inputs are finite
    rFacUse : LREAL;                 // 实际使用的安全系数 [-] EN: the safety factor in use
    rPwm    : LREAL;                 // 每米功率中间值 [W/m] EN: the interim power per metre
    rTotal  : LREAL;                 // 总功率中间值 [W] EN: the interim total power
    rCur    : LREAL;                 // 电流中间值 [A] EN: the interim current
END_VAR
VAR CONSTANT
    DL_HTP_Z      : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_HTP_ONE    : LREAL := 1.0;    // 浮点壹常量 EN: the floating point one constant
    DL_HTP_MIN    : LREAL := 1.0E-6; // 电压与系数下限 EN: the lower bound of the voltage and the factors
    DL_HTP_C_BAD  : INT := 9801;     // 输入非有限 EN: a non finite input
    DL_HTP_C_RANG : INT := 9802;     // 热损或管长或系数越域 EN: the loss, the length or the factor is out of range
END_VAR

// 段1｜出口预置
FC_DL_HeatTracePowerCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rPowerWm := DL_HTP_Z;                // 每米功率预置零 [W/m] EN: preset the power per metre to zero
rPowerTotalW := DL_HTP_Z;            // 总功率预置零 [W] EN: preset the total power to zero
rCurrentA := DL_HTP_Z;               // 电流预置零 [A] EN: preset the current to zero
xFactorHigh := FALSE;                // 系数越域标志预置假 EN: preset the factor flag to false
xValid := FALSE;                     // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                     // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：五输入全列（上限参与域判，漏则越域判据失效）
xFinAll := (rLossWm = rLossWm) AND ((rLossWm - rLossWm) = DL_HTP_Z)
        AND (rSafetyFactor = rSafetyFactor) AND ((rSafetyFactor - rSafetyFactor) = DL_HTP_Z)
        AND (rLengthM = rLengthM) AND ((rLengthM - rLengthM) = DL_HTP_Z)
        AND (rVoltageV = rVoltageV) AND ((rVoltageV - rVoltageV) = DL_HTP_Z)
        AND (rFactorMax = rFactorMax) AND ((rFactorMax - rFactorMax) = DL_HTP_Z);   // 五输入有限性 EN: the finiteness of all five inputs
IF NOT xFinAll THEN                                                                  // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_HTP_C_BAD;                                                      // 非有限码 EN: the non finite code
    RETURN;                                                                          // 早退 EN: return early
END_IF

// 段3｜域闸：热损与管长非负、安全系数 ≥1、上限须 ≥1
IF (rLossWm < DL_HTP_Z) OR (rLengthM < DL_HTP_Z) OR (rSafetyFactor < DL_HTP_ONE)
   OR (rFactorMax < DL_HTP_ONE) THEN
    nFaultCode := DL_HTP_C_RANG;                                                     // 越域码 EN: the out of range code
    RETURN;                                                                          // 早退 EN: return early
END_IF

// 段4｜安全系数域：超上限按上限取值并置信息级标志（不中断功率输出）
IF rSafetyFactor > rFactorMax THEN                                                   // 超上限判据 EN: the upper bound test
    rFacUse := rFactorMax;                                                           // 按上限取值 [-] EN: clamp to the upper bound
    xFactorHigh := TRUE;                                                             // 置信息级标志 EN: raise the information class flag
ELSE
    rFacUse := rSafetyFactor;                                                        // 域内直接使用 [-] EN: use the given factor
END_IF

// 段5｜主体：每米功率 = 热损 × 系数；总功率 = 每米 × 管长；电流按电压折算
rPwm := rLossWm * rFacUse;                                                           // 每米伴热功率 [W/m] EN: the power per metre
rTotal := rPwm * rLengthM;                                                           // 总伴热功率 [W] EN: the total power
IF ABS(rVoltageV) < DL_HTP_MIN THEN                                                  // 电压下限：未接线时电流给零 EN: give zero current when the voltage is unusable
    rCur := DL_HTP_Z;                                                                // 电流给零 [A] EN: give a zero current
ELSE
    rCur := rTotal / rVoltageV;                                                      // 工作电流 [A] EN: the operating current
END_IF

// 段6｜结果复检与出口
IF (rPwm <> rPwm) OR (rTotal <> rTotal) OR (rCur <> rCur) THEN                       // 复检：三路非有限 EN: recheck the three results
    nFaultCode := DL_HTP_C_RANG;                                                     // 复检失败码 EN: the recheck failure code
    RETURN;                                                                          // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rPowerWm := rPwm;                                                                    // 每米功率出口 [W/m] EN: the power per metre output
rPowerTotalW := rTotal;                                                              // 总功率出口 [W] EN: the total power output
rCurrentA := rCur;                                                                   // 电流出口 [A] EN: the current output
xValid := TRUE;                                                                      // 结果可信 EN: the results are valid
FC_DL_HeatTracePowerCalc := TRUE;                                                    // 返回真 EN: return true
END_FUNCTION
