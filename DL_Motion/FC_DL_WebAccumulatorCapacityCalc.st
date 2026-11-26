(*
  Component : FC_DL_WebAccumulatorCapacityCalc
  Category  : DL_Motion
  Function  : 储料架容量与可缓冲时间：由储料长度、卷径与线速度折算圈数与缓冲秒数
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rAccumLenM 储料架可储料长度（全行程对应带长） [m]、rLineSpeedMpm 线速度 [m/min]、
             rRollDiaMm 当前卷径 [mm]、rCoreDiaMm 卷芯直径 [mm]、rBufTimeMinS 缓冲时间下限 [s]；
             输出 rBufferTimeS 可缓冲时间 [s]、rWrapCount 折合圈数 [圈]、rMeanDiaM 平均卷径 [m]、
             xBufferLow 缓冲时间不足（信息级）、xValid 有效标志、nFaultCode 故障码。
  边界     : 线速度为分母须 >1.0E-6 [m/min]（零速时缓冲时间趋于无穷，此时输出饱和上限 1.0E6 [s] 并置
             xBufferLow=FALSE，饱和依据：1.0E6 s ≈ 11.6 天，已远超任何换卷窗口，向下可表）；
             卷芯直径须 >1.0E-6 [mm]；圈数 = 储料长度 / (π × 平均卷径)，平均卷径取 (D + D0)/2；
             π 取 LREAL 精度字面量，禁 REAL 精度常数进入除法链。
  码位     : 9801 输入非有限（故障级）；9802 线速度或卷芯直径越域（故障级）。
*)
FUNCTION FC_DL_WebAccumulatorCapacityCalc : BOOL
VAR_INPUT
    rAccumLenM    : LREAL := 20.0;    // 储料长度 [m] EN: the accumulated web length
    rLineSpeedMpm : LREAL := 100.0;   // 线速度 [m/min] EN: the line speed
    rRollDiaMm    : LREAL := 600.0;   // 当前卷径 [mm] EN: the current roll diameter
    rCoreDiaMm    : LREAL := 150.0;   // 卷芯直径 [mm] EN: the core diameter
    rBufTimeMinS  : LREAL := 60.0;    // 缓冲时间下限 [s] EN: the lower bound of the buffer time
END_VAR
VAR_OUTPUT
    rBufferTimeS : LREAL;             // 可缓冲时间 [s] EN: the buffer time available
    rWrapCount   : LREAL;             // 折合圈数 [圈] EN: the equivalent number of wraps
    rMeanDiaM    : LREAL;             // 平均卷径 [m] EN: the mean roll diameter
    xBufferLow   : BOOL;              // 缓冲时间不足（信息级） EN: the buffer time is insufficient, information class only
    xValid       : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;               // 0=无故障 9801=输入非有限 9802=线速度或卷芯直径越域 EN: zero none, 9801 non finite, 9802 line speed or core diameter out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 五输入同时有限 EN: all five inputs are finite
    rMeanMm : LREAL;                  // 平均卷径 [mm] EN: the mean diameter in millimetres
    rPerimM : LREAL;                  // 平均周长 [m] EN: the mean circumference
    rWrap   : LREAL;                  // 圈数中间值 [圈] EN: the interim wrap count
    rTimeS  : LREAL;                  // 缓冲时间中间值 [s] EN: the interim buffer time
    rSpeedMs: LREAL;                  // 线速度折算每秒 [m/s] EN: the line speed in metres per second
END_VAR
VAR CONSTANT
    DL_WAC_Z       : LREAL := 0.0;                  // 浮点零常量 EN: the floating point zero constant
    DL_WAC_TWO     : LREAL := 2.0;                  // 平均卷径系数 EN: the mean diameter factor
    DL_WAC_PI      : LREAL := 3.1415926535897932;   // 圆周率（LREAL 精度） [-] EN: the circle ratio at LREAL precision
    DL_WAC_K1000   : LREAL := 1000.0;               // 毫米转米系数 EN: the millimetre to metre factor
    DL_WAC_SECMIN  : LREAL := 60.0;                 // 分钟转秒系数 EN: the minute to second factor
    DL_WAC_T_MAX   : LREAL := 1.0E6;                // 缓冲时间饱和上限 [s] EN: the saturation upper bound of the buffer time
    DL_WAC_MIN     : LREAL := 1.0E-6;               // 分母绝对值下限 EN: the lower bound of the divisor magnitude
    DL_WAC_C_BAD   : INT := 9801;                   // 输入非有限 EN: a non finite input
    DL_WAC_C_RANGE : INT := 9802;                   // 线速度或卷芯直径越域 EN: the line speed or the core diameter is out of range
END_VAR

// 段1｜出口预置
FC_DL_WebAccumulatorCapacityCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rBufferTimeS := DL_WAC_Z;                    // 缓冲时间预置零 [s] EN: preset the buffer time to zero
rWrapCount := DL_WAC_Z;                      // 圈数预置零 [圈] EN: preset the wrap count to zero
rMeanDiaM := DL_WAC_Z;                       // 平均卷径预置零 [m] EN: preset the mean diameter to zero
xBufferLow := FALSE;                         // 缓冲不足标志预置假 EN: preset the low buffer flag to false
xValid := FALSE;                             // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                             // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：五浮点入参全列
xFinAll := (rAccumLenM = rAccumLenM) AND ((rAccumLenM - rAccumLenM) = DL_WAC_Z)
        AND (rLineSpeedMpm = rLineSpeedMpm) AND ((rLineSpeedMpm - rLineSpeedMpm) = DL_WAC_Z)
        AND (rRollDiaMm = rRollDiaMm) AND ((rRollDiaMm - rRollDiaMm) = DL_WAC_Z)
        AND (rCoreDiaMm = rCoreDiaMm) AND ((rCoreDiaMm - rCoreDiaMm) = DL_WAC_Z)
        AND (rBufTimeMinS = rBufTimeMinS) AND ((rBufTimeMinS - rBufTimeMinS) = DL_WAC_Z);   // 五输入有限性 EN: the finiteness of all five inputs
IF NOT xFinAll THEN                                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WAC_C_BAD;                                                              // 非有限码 EN: the non finite code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：储料长度与卷径非负、卷芯直径与线速度过分母下限
IF (rAccumLenM < DL_WAC_Z) OR (rRollDiaMm < DL_WAC_Z)
   OR (ABS(rCoreDiaMm) < DL_WAC_MIN) OR (ABS(rLineSpeedMpm) < DL_WAC_MIN) THEN
    nFaultCode := DL_WAC_C_RANGE;                                                            // 越域码 EN: the out of range code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段4｜主体：平均卷径 → 周长 → 圈数；线速度折每秒 → 缓冲时间（含饱和上限）
rMeanMm := (rRollDiaMm + rCoreDiaMm) / DL_WAC_TWO;                                           // 平均卷径 [mm] EN: the mean diameter
rMeanDiaM := rMeanMm / DL_WAC_K1000;                                                         // 平均卷径 [m] EN: the mean diameter in metres
rPerimM := DL_WAC_PI * rMeanDiaM;                                                            // 平均周长 [m] EN: the mean circumference
IF ABS(rPerimM) < DL_WAC_MIN THEN                                                            // 周长分母下限 EN: the circumference gate
    nFaultCode := DL_WAC_C_RANGE;                                                            // 越域码 EN: the out of range code
    RETURN;                                                                                  // 早退 EN: return early
END_IF
rWrap := rAccumLenM / rPerimM;                                                               // 折合圈数 [圈] EN: the equivalent wrap count
rSpeedMs := rLineSpeedMpm / DL_WAC_SECMIN;                                                   // 线速度 [m/s] EN: the line speed in metres per second
rTimeS := rAccumLenM / rSpeedMs;                                                             // 缓冲时间 [s] EN: the buffer time
IF rTimeS > DL_WAC_T_MAX THEN                                                                // 饱和上限（零速附近） EN: saturate near standstill
    rTimeS := DL_WAC_T_MAX;                                                                  // 饱和到上限 [s] EN: saturate to the upper bound
END_IF

// 段5｜结果复检与出口
IF (rWrap <> rWrap) OR (rTimeS <> rTimeS) OR (rWrap < DL_WAC_Z) OR (rTimeS < DL_WAC_Z) THEN   // 复检 EN: recheck the results
    nFaultCode := DL_WAC_C_RANGE;                                                            // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                  // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rBufferTimeS := rTimeS;                                                                      // 缓冲时间出口 [s] EN: the buffer time output
rWrapCount := rWrap;                                                                         // 圈数出口 [圈] EN: the wrap count output
xBufferLow := rTimeS < rBufTimeMinS;                                                         // 缓冲不足判据（信息级） EN: the low buffer test, information class only
xValid := TRUE;                                                                              // 结果可信 EN: the results are valid
FC_DL_WebAccumulatorCapacityCalc := TRUE;                                                    // 返回真 EN: return true
END_FUNCTION
