(*
  Component : FC_DL_CathodeMillThroughputCalc
  Category  : DL_Process
  Function  : 粉碎分级产能估算 t/h：由分级轮转速与风量折算，含转速修正与上限钳位
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rAirFlowM3h 系统风量 [m3/h]、rSolidsGm3 气流含尘浓度 [g/m3]、
             nWheelRpm 分级轮实际转速 [r/min]、nWheelRefRpm 分级轮额定转速 [r/min]、
             rSpeedExp 转速修正指数 [-]、rCapMaxTh 产能硬上限 [t/h]；
             输出 rThroughputTh 估算产能 [t/h]、rSpeedFactor 转速修正因子 [-]、
             xCapped 触上限、xValid 有效标志、nFaultCode 故障码。
  边界     : 基础产能 = 风量 × 含尘浓度 / 1.0E6（g→t 与 m3/h→t/h 一次换算）；转速因子 =
             (实际/额定)^指数，指数须 >0 且 ≤2；额定转速为分母须 >1.0E-9 [r/min]；
             产能硬限上限必须具备「极限值→REAL 可表性」反算：上限 1.0E4 [t/h] 远小于 REAL 上限 3.4E38，可表。
  码位     : 9801 输入非有限（故障级）；9802 额定转速或指数越域（故障级）。
*)
FUNCTION FC_DL_CathodeMillThroughputCalc : BOOL
VAR_INPUT
    rAirFlowM3h   : LREAL := 5000.0;   // 系统风量 [m3/h] EN: the air volumetric flow of the classifying system
    rSolidsGm3    : LREAL := 200.0;    // 气流含尘浓度 [g/m3] EN: the solids concentration carried by the air
    nWheelRpm     : INT := 3000;       // 分级轮实际转速 [r/min] EN: the actual rotational speed of the classifying wheel
    nWheelRefRpm  : INT := 3000;       // 分级轮额定转速 [r/min] EN: the rated rotational speed of the classifying wheel
    rSpeedExp     : LREAL := 1.0;      // 转速修正指数 [-] EN: the exponent of the speed correction
    rCapMaxTh     : LREAL := 5.0;      // 产能硬上限 [t/h] EN: the hard upper bound of the throughput
END_VAR
VAR_OUTPUT
    rThroughputTh : LREAL;             // 估算产能 [t/h] EN: the estimated throughput in tonnes per hour
    rSpeedFactor  : LREAL;             // 转速修正因子 [-] EN: the speed correction factor
    xCapped       : BOOL;              // 触产能硬上限 EN: the throughput reached the hard upper bound
    xValid        : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode    : INT;               // 0=无故障 9801=输入非有限 9802=额定转速或指数越域 EN: zero none, 9801 non finite input, 9802 rated speed or exponent out of range
END_VAR
VAR
    xFinAll : BOOL;                    // 浮点入参同时有限 EN: the floating inputs are finite
    rBase   : LREAL;                   // 基础产能（未修正） [t/h] EN: the base throughput before the correction
    rRatio  : LREAL;                   // 转速比 [-] EN: the speed ratio
    rFactor : LREAL;                   // 修正因子中间值 [-] EN: the interim correction factor
    rOut    : LREAL;                   // 产能中间值 [t/h] EN: the interim throughput
END_VAR
VAR CONSTANT
    DL_CMT_Z       : LREAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_CMT_MILLION : LREAL := 1.0E6;    // 克转吨与每小时一次换算系数 EN: the gram to tonne conversion factor
    DL_CMT_EXP_MAX : LREAL := 2.0;      // 修正指数上限 [-] EN: the upper bound of the exponent
    DL_CMT_MIN     : LREAL := 1.0E-9;   // 分母绝对值下限 EN: the lower bound of the divisor magnitude
    DL_CMT_C_BAD   : INT := 9801;       // 输入非有限 EN: a non finite input
    DL_CMT_C_RANGE : INT := 9802;       // 额定转速或指数越域 EN: the rated speed or the exponent is out of range
END_VAR

// 段1｜出口预置
FC_DL_CathodeMillThroughputCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rThroughputTh := DL_CMT_Z;                  // 产能预置零 [t/h] EN: preset the throughput to zero
rSpeedFactor := DL_CMT_Z;                   // 修正因子预置零 [-] EN: preset the correction factor to zero
xCapped := FALSE;                           // 触限标志预置假 EN: preset the capped flag to false
xValid := FALSE;                            // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                            // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：浮点入参全列（硬上限参与钳位，漏则钳位失效）
xFinAll := (rAirFlowM3h = rAirFlowM3h) AND ((rAirFlowM3h - rAirFlowM3h) = DL_CMT_Z)
        AND (rSolidsGm3 = rSolidsGm3) AND ((rSolidsGm3 - rSolidsGm3) = DL_CMT_Z)
        AND (rSpeedExp = rSpeedExp) AND ((rSpeedExp - rSpeedExp) = DL_CMT_Z)
        AND (rCapMaxTh = rCapMaxTh) AND ((rCapMaxTh - rCapMaxTh) = DL_CMT_Z);   // 四浮点输入有限性 EN: the finiteness of the four floating inputs
IF NOT xFinAll THEN                                                             // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CMT_C_BAD;                                                 // 非有限码 EN: the non finite code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段3｜域闸：风量与含尘浓度非负、转速非负、额定转速过分母下限、指数在 (0,2]、硬上限为正
IF (rAirFlowM3h < DL_CMT_Z) OR (rSolidsGm3 < DL_CMT_Z) OR (nWheelRpm < 0) OR (nWheelRefRpm < 0)
   OR (rSpeedExp <= DL_CMT_Z) OR (rSpeedExp > DL_CMT_EXP_MAX) OR (rCapMaxTh <= DL_CMT_Z)
   OR (ABS(INT_TO_LREAL(nWheelRefRpm)) < DL_CMT_MIN) THEN
    nFaultCode := DL_CMT_C_RANGE;                                               // 越域码 EN: the out of range code
    RETURN;                                                                     // 早退 EN: return early
END_IF

// 段4｜主体：基础产能 = 风量 × 含尘 / 1.0E6；因子 = (实际/额定)^指数
rBase := (rAirFlowM3h * rSolidsGm3) / DL_CMT_MILLION;                           // 基础产能 [t/h] EN: the base throughput
rRatio := INT_TO_LREAL(nWheelRpm) / INT_TO_LREAL(nWheelRefRpm);                 // 转速比，分母已证正 [-] EN: the speed ratio, the divisor is proven positive
rFactor := EXP(rSpeedExp * LN(rRatio));                                         // 指数修正 = e^(k·ln r) [-]，避免依赖 EXPT 方言 EN: the exponential correction without a vendor power operator
rOut := rBase * rFactor;                                                        // 修正后产能 [t/h] EN: the corrected throughput

// 段5｜结果复检 + 硬上限钳位（只防上溢，不下抬）
IF (rOut <> rOut) OR (rOut < DL_CMT_Z) THEN                                     // 复检：非有限或负 EN: recheck for a non finite or negative result
    nFaultCode := DL_CMT_C_RANGE;                                               // 复检失败码 EN: the recheck failure code
    RETURN;                                                                     // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
IF rOut > rCapMaxTh THEN                                                        // 硬上限钳位 EN: the hard upper bound
    rOut := rCapMaxTh;                                                          // 钳到上限 [t/h] EN: clamp to the upper bound
    xCapped := TRUE;                                                            // 置触限标志 EN: raise the capped flag
END_IF

// 段6｜出口
rThroughputTh := rOut;                                                          // 产能出口 [t/h] EN: the throughput output
rSpeedFactor := rFactor;                                                        // 因子出口 [-] EN: the factor output
xValid := TRUE;                                                                 // 结果可信 EN: the results are valid
FC_DL_CathodeMillThroughputCalc := TRUE;                                        // 返回真 EN: return true
END_FUNCTION
