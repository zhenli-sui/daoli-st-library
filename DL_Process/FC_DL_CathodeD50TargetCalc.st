(*
  Component : FC_DL_CathodeD50TargetCalc
  Category  : DL_Process
  Function  : 目标 D50 与分级轮转速反算：d50 = k / rpm，含上下限钳位
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 nWheelRpm 分级轮转速 [r/min]、rCoefUmRpm 切割系数 [μm·r/min]、
             rD50MinUm 目标下限 [μm]、rD50MaxUm 目标上限 [μm]；
             输出 rD50Um 钳位后目标 D50 [μm]、rD50RawUm 未钳位计算值 [μm]、
             xClamped 触限、xValid 有效标志、nFaultCode 故障码。
  边界     : 转速为分母须 >1（转速过低无切割效应，模型外推发散）；上下限须 上限 > 下限 > 0；
             切割系数须 >1.0E-9 [μm·r/min]；钳位后仍给出未钳位值以便上层判断模型是否越界。
  码位     : 9801 输入非有限（故障级）；9802 转速、系数或限值越域（故障级）。
*)
FUNCTION FC_DL_CathodeD50TargetCalc : BOOL
VAR_INPUT
    nWheelRpm  : INT := 3000;        // 分级轮转速 [r/min] EN: the rotational speed of the classifying wheel
    rCoefUmRpm : LREAL := 30000.0;   // 切割系数（D50 × 转速） [μm·r/min] EN: the cut coefficient, the product of D50 and the speed
    rD50MinUm  : LREAL := 1.0;       // 目标 D50 下限 [μm] EN: the lower bound of the target median size
    rD50MaxUm  : LREAL := 30.0;      // 目标 D50 上限 [μm] EN: the upper bound of the target median size
END_VAR
VAR_OUTPUT
    rD50Um    : LREAL;               // 钳位后目标 D50 [μm] EN: the clamped target median size
    rD50RawUm : LREAL;               // 未钳位计算值 [μm] EN: the unclamped computed median size
    xClamped  : BOOL;                // 触上下限 EN: the bound was reached
    xValid    : BOOL;                // 输出可信标志 EN: the outputs are valid
    nFaultCode: INT;                 // 0=无故障 9801=输入非有限 9802=转速或限值越域 EN: zero none, 9801 non finite, 9802 speed or limits out of range
END_VAR
VAR
    xFinAll : BOOL;                  // 浮点入参有限 EN: the floating inputs are finite
    rDen    : LREAL;                 // 分母（转速实数化） [r/min] EN: the divisor, the speed as a real number
    rRaw    : LREAL;                 // 计算中间值 [μm] EN: the interim computed value
    rOut    : LREAL;                 // 钳位后中间值 [μm] EN: the interim clamped value
END_VAR
VAR CONSTANT
    DL_CDT_Z     : LREAL := 0.0;     // 浮点零常量 EN: the floating point zero constant
    DL_CDT_ONE   : LREAL := 1.0;     // 浮点壹常量 EN: the floating point one constant
    DL_CDT_MIN   : LREAL := 1.0E-9;  // 分母绝对值下限 EN: the lower bound of the divisor magnitude
    DL_CDT_C_BAD : INT := 9801;      // 输入非有限 EN: a non finite input
    DL_CDT_C_RANG: INT := 9802;      // 转速或限值越域 EN: the speed or the limits are out of range
END_VAR

// 段1｜出口预置
FC_DL_CathodeD50TargetCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rD50Um := DL_CDT_Z;                    // 钳位值预置零 [μm] EN: preset the clamped value to zero
rD50RawUm := DL_CDT_Z;                 // 未钳位值预置零 [μm] EN: preset the unclamped value to zero
xClamped := FALSE;                     // 触限标志预置假 EN: preset the clamp flag to false
xValid := FALSE;                       // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                       // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三浮点入参全列（两限值参与钳位）
xFinAll := (rCoefUmRpm = rCoefUmRpm) AND ((rCoefUmRpm - rCoefUmRpm) = DL_CDT_Z)
        AND (rD50MinUm = rD50MinUm) AND ((rD50MinUm - rD50MinUm) = DL_CDT_Z)
        AND (rD50MaxUm = rD50MaxUm) AND ((rD50MaxUm - rD50MaxUm) = DL_CDT_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                             // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CDT_C_BAD;                                                 // 非有限码 EN: the non finite code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段3｜域闸：转速 >1 [r/min]、系数为正、限值 上限 > 下限 > 0
rDen := INT_TO_LREAL(nWheelRpm);                                                // 转速实数化 [r/min] EN: the speed as a real number
IF (rDen <= DL_CDT_ONE) OR (ABS(rCoefUmRpm) < DL_CDT_MIN)
   OR (rD50MinUm <= DL_CDT_Z) OR (rD50MaxUm <= rD50MinUm) THEN
    nFaultCode := DL_CDT_C_RANG;                                                // 越域码 EN: the out of range code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段4｜主体：d50 = k / rpm
rRaw := rCoefUmRpm / rDen;                                                      // 计算 D50 [μm] EN: the computed median size
IF (rRaw <> rRaw) OR (rRaw <= DL_CDT_Z) THEN                                    // 结果复检 EN: recheck the result
    nFaultCode := DL_CDT_C_RANG;                                                // 复检失败码 EN: the recheck failure code
    RETURN;                                                                     // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段5｜上下限钳位（不饱和报表：xClamped 表达模型是否越界）
rOut := rRaw;                                                                   // 钳位工作副本 [μm] EN: the working copy for clamping
IF rOut < rD50MinUm THEN                                                        // 下钳位 EN: clamp the lower bound
    rOut := rD50MinUm;                                                          // 抬到下限 [μm] EN: raise to the lower bound
    xClamped := TRUE;                                                           // 置触限标志 EN: raise the clamp flag
END_IF
IF rOut > rD50MaxUm THEN                                                        // 上钳位 EN: clamp the upper bound
    rOut := rD50MaxUm;                                                          // 压到上限 [μm] EN: clamp to the upper bound
    xClamped := TRUE;                                                           // 置触限标志 EN: raise the clamp flag
END_IF

// 段6｜出口
rD50Um := rOut;                                                                 // 钳位值出口 [μm] EN: the clamped value output
rD50RawUm := rRaw;                                                              // 未钳位值出口 [μm] EN: the unclamped value output
xValid := TRUE;                                                                 // 结果可信 EN: the results are valid
FC_DL_CathodeD50TargetCalc := TRUE;                                             // 返回真 EN: return true
END_FUNCTION
