(*
  Component : FC_DL_WebGuideRateLimitCalc
  Category  : DL_Motion
  Function  : 纠偏执行速率限幅：由剩余偏移量与最大加速度求允许速度 v = √(2·a·|e|)，并受最大速度钳制
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rOffsetMm 剩余偏移（带符号） [mm]、rAccelMmS2 允许最大加速度 [mm/s2]、
             rVmaxMmS 执行机构最大速度 [mm/s]、rDeadbandMm 纠偏死区 [mm]；
             输出 rVallowMmS 带符号允许速度 [mm/s]、rWithinDb 偏移在死区内、
             xLimited 触最大速度、xValid 有效标志、nFaultCode 故障码。
  边界     : 加速度与最大速度须 >0；偏移绝对值小于死区时允许速度给零（防抖）；
             速度符号随偏移符号，绝不取绝对值输出（符号即纠偏方向）；开方前乘子已证非负。
  码位     : 9801 输入非有限（故障级）；9802 加速度或最大速度越域（故障级）。
*)
FUNCTION FC_DL_WebGuideRateLimitCalc : BOOL
VAR_INPUT
    rOffsetMm   : LREAL := 1.0;      // 剩余带符号偏移 [mm] EN: the remaining signed offset
    rAccelMmS2  : LREAL := 50.0;     // 允许最大加速度 [mm/s2] EN: the allowed maximum acceleration
    rVmaxMmS    : LREAL := 20.0;     // 执行机构最大速度 [mm/s] EN: the maximum actuator velocity
    rDeadbandMm : LREAL := 0.2;      // 纠偏死区 [mm] EN: the guide dead band
END_VAR
VAR_OUTPUT
    rVallowMmS : LREAL;              // 带符号允许速度 [mm/s] EN: the signed allowed velocity
    rWithinDb  : BOOL;               // 偏移在死区内 EN: the offset is inside the dead band
    xLimited   : BOOL;               // 触最大速度 EN: the maximum velocity was reached
    xValid     : BOOL;               // 输出可信标志 EN: the outputs are valid
    nFaultCode : INT;                // 0=无故障 9801=输入非有限 9802=加速度或最大速度越域 EN: zero none, 9801 non finite, 9802 acceleration or maximum velocity out of range
END_VAR
VAR
    xFinAll : BOOL;                  // 四输入同时有限 EN: all four inputs are finite
    rAbsOff : LREAL;                 // 偏移绝对值 [mm] EN: the magnitude of the offset
    rEffOff : LREAL;                 // 扣死区后的有效偏移 [mm] EN: the effective offset after the dead band
    rVcalc  : LREAL;                 // 开方得到的限制速度 [mm/s] EN: the velocity limit from the square root
    rVout   : LREAL;                 // 允许速度幅值 [mm/s] EN: the allowed velocity magnitude
END_VAR
VAR CONSTANT
    DL_WRL_Z     : LREAL := 0.0;     // 浮点零常量 EN: the floating point zero constant
    DL_WRL_TWO   : LREAL := 2.0;     // 匀加速公式系数 EN: the uniform acceleration factor
    DL_WRL_C_BAD : INT := 9801;      // 输入非有限 EN: a non finite input
    DL_WRL_C_RANG: INT := 9802;      // 加速度或最大速度越域 EN: the acceleration or the maximum velocity is out of range
END_VAR

// 段1｜出口预置
FC_DL_WebGuideRateLimitCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rVallowMmS := DL_WRL_Z;                 // 允许速度预置零 [mm/s] EN: preset the allowed velocity to zero
rWithinDb := FALSE;                     // 死区标志预置假 EN: preset the dead band flag to false
xLimited := FALSE;                      // 触限标志预置假 EN: preset the limited flag to false
xValid := FALSE;                        // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                        // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四输入全列（死区参与有效偏移，漏则防抖判据失效）
xFinAll := (rOffsetMm = rOffsetMm) AND ((rOffsetMm - rOffsetMm) = DL_WRL_Z)
        AND (rAccelMmS2 = rAccelMmS2) AND ((rAccelMmS2 - rAccelMmS2) = DL_WRL_Z)
        AND (rVmaxMmS = rVmaxMmS) AND ((rVmaxMmS - rVmaxMmS) = DL_WRL_Z)
        AND (rDeadbandMm = rDeadbandMm) AND ((rDeadbandMm - rDeadbandMm) = DL_WRL_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                      // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WRL_C_BAD;                                                          // 非有限码 EN: the non finite code
    RETURN;                                                                              // 早退 EN: return early
END_IF

// 段3｜域闸：加速度与最大速度为正、死区非负
IF (rAccelMmS2 <= DL_WRL_Z) OR (rVmaxMmS <= DL_WRL_Z) OR (rDeadbandMm < DL_WRL_Z) THEN    // 域闸 EN: the domain gate
    nFaultCode := DL_WRL_C_RANG;                                                          // 越域码 EN: the out of range code
    RETURN;                                                                               // 早退 EN: return early
END_IF

// 段4｜主体：扣死区后按匀加速公式求限制速度，再与最大速度取小
rAbsOff := ABS(rOffsetMm);                                                                // 偏移绝对值 [mm] EN: the offset magnitude
rWithinDb := rAbsOff <= rDeadbandMm;                                                      // 死区判据 EN: the dead band test
rEffOff := rAbsOff - rDeadbandMm;                                                         // 有效偏移 [mm] EN: the effective offset
IF rWithinDb OR (rEffOff <= DL_WRL_Z) THEN                                                // 死区内或扣完无余量 EN: inside the band or nothing left
    rVout := DL_WRL_Z;                                                                    // 允许速度给零 [mm/s] EN: allow no motion
ELSE
    rVcalc := SQRT(DL_WRL_TWO * rAccelMmS2 * rEffOff);                                    // 匀加速限制速度，乘子已证正 [mm/s] EN: the square root limit, the operand is proven positive
    IF rVcalc > rVmaxMmS THEN                                                             // 与最大速度取小 EN: take the smaller bound
        rVout := rVmaxMmS;                                                                // 压到最大速度 [mm/s] EN: clamp to the maximum velocity
        xLimited := TRUE;                                                                 // 置触限标志 EN: raise the limited flag
    ELSE
        rVout := rVcalc;                                                                  // 采用公式值 [mm/s] EN: use the computed value
    END_IF
END_IF

// 段5｜出口：符号随偏移符号落定（R94 早退分支同样施加该变换）
IF rOffsetMm < DL_WRL_Z THEN                                                              // 偏移为负 EN: the offset is negative
    rVallowMmS := -rVout;                                                                 // 负向速度 [mm/s] EN: the negative velocity
ELSE
    rVallowMmS := rVout;                                                                  // 正向（含零）速度 [mm/s] EN: the positive velocity including zero
END_IF
xValid := TRUE;                                                                           // 结果可信 EN: the results are valid
FC_DL_WebGuideRateLimitCalc := TRUE;                                                      // 返回真 EN: return true
END_FUNCTION
