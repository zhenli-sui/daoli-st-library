(*
  Component : FC_DL_WebGuideDeadbandCalc
  Category  : DL_Motion
  Function  : 随线速度线性缩放的纠偏死区，含最小/最大钳位与速度上限保护
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rSpeedMpm 当前线速度 [m/min]、rSpeedRefMpm 速度归一化基准 [m/min]、
             rDeadbandMinMm 静止死区下限 [mm]、rDeadbandMaxMm 满速死区上限 [mm]；
             输出 rDeadbandMm 当前死区 [mm]、rSpeedRatio 速度比（未钳位） [-]、
             xSpeedCapped 速度比触上限、xValid 有效标志、nFaultCode 故障码。
  边界     : 速度比 = 当前速度 / 基准速度，基准速度须 >1.0E-6 [m/min]；速度比钳在 0~1（超基准速度不再放大死区，
             超速由运动层限速处理，本件不承担）；死区上下限须 0 ≤ min ≤ max。
  码位     : 9801 输入非有限（故障级）；9802 速度基准或死区上下限越域（故障级）。
*)
FUNCTION FC_DL_WebGuideDeadbandCalc : BOOL
VAR_INPUT
    rSpeedMpm      : LREAL := 100.0;  // 当前线速度 [m/min] EN: the current line speed
    rSpeedRefMpm   : LREAL := 200.0;  // 速度归一化基准 [m/min] EN: the reference speed used for normalisation
    rDeadbandMinMm : LREAL := 0.2;    // 静止死区下限 [mm] EN: the dead band at standstill
    rDeadbandMaxMm : LREAL := 1.0;    // 满速死区上限 [mm] EN: the dead band at the reference speed
END_VAR
VAR_OUTPUT
    rDeadbandMm  : LREAL;             // 当前纠偏死区 [mm] EN: the current guide dead band
    rSpeedRatio  : LREAL;             // 速度比（钳位后） [-] EN: the speed ratio after clamping
    xSpeedCapped : BOOL;              // 速度比触上限 EN: the speed ratio reached the upper bound
    xValid       : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;               // 0=无故障 9801=输入非有限 9802=基准或限值越域 EN: zero none, 9801 non finite, 9802 reference or limits out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 四输入同时有限 EN: all four inputs are finite
    rRatio  : LREAL;                  // 速度比中间值 [-] EN: the interim speed ratio
    rRatioC : LREAL;                  // 钳位后速度比 [-] EN: the clamped speed ratio
    rDb     : LREAL;                  // 死区中间值 [mm] EN: the interim dead band
END_VAR
VAR CONSTANT
    DL_WGD_Z     : LREAL := 0.0;      // 浮点零常量 EN: the floating point zero constant
    DL_WGD_ONE   : LREAL := 1.0;      // 浮点壹常量 EN: the floating point one constant
    DL_WGD_MIN   : LREAL := 1.0E-6;   // 速度基准下限 [m/min] EN: the lower bound of the reference speed
    DL_WGD_C_BAD : INT := 9801;       // 输入非有限 EN: a non finite input
    DL_WGD_C_RANG: INT := 9802;       // 基准或限值越域 EN: the reference or the limits are out of range
END_VAR

// 段1｜出口预置
FC_DL_WebGuideDeadbandCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rDeadbandMm := DL_WGD_Z;               // 死区预置零 [mm] EN: preset the dead band to zero
rSpeedRatio := DL_WGD_Z;               // 速度比预置零 [-] EN: preset the speed ratio to zero
xSpeedCapped := FALSE;                 // 触限标志预置假 EN: preset the capped flag to false
xValid := FALSE;                       // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                       // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四输入全列
xFinAll := (rSpeedMpm = rSpeedMpm) AND ((rSpeedMpm - rSpeedMpm) = DL_WGD_Z)
        AND (rSpeedRefMpm = rSpeedRefMpm) AND ((rSpeedRefMpm - rSpeedRefMpm) = DL_WGD_Z)
        AND (rDeadbandMinMm = rDeadbandMinMm) AND ((rDeadbandMinMm - rDeadbandMinMm) = DL_WGD_Z)
        AND (rDeadbandMaxMm = rDeadbandMaxMm) AND ((rDeadbandMaxMm - rDeadbandMaxMm) = DL_WGD_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                                 // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WGD_C_BAD;                                                                     // 非有限码 EN: the non finite code
    RETURN;                                                                                         // 早退 EN: return early
END_IF

// 段3｜域闸：基准速度分母下限、速度非负、死区限值 0 ≤ min ≤ max
IF (ABS(rSpeedRefMpm) < DL_WGD_MIN) OR (rSpeedMpm < DL_WGD_Z)
   OR (rDeadbandMinMm < DL_WGD_Z) OR (rDeadbandMaxMm < rDeadbandMinMm) THEN
    nFaultCode := DL_WGD_C_RANG;                                                                    // 越域码 EN: the out of range code
    RETURN;                                                                                         // 早退 EN: return early
END_IF

// 段4｜主体：死区 = min + (max − min) × 速度比，速度比钳在 0~1
rRatio := rSpeedMpm / rSpeedRefMpm;                                                                 // 速度比 [-] EN: the speed ratio
rRatioC := rRatio;                                                                                  // 钳位工作副本 [-] EN: the working copy for clamping
IF rRatioC > DL_WGD_ONE THEN                                                                        // 上钳位 EN: clamp the upper bound
    rRatioC := DL_WGD_ONE;                                                                          // 钳到壹 [-] EN: clamp to one
    xSpeedCapped := TRUE;                                                                           // 置触限标志 EN: raise the capped flag
END_IF
IF rRatioC < DL_WGD_Z THEN                                                                          // 下钳位 EN: clamp the lower bound
    rRatioC := DL_WGD_Z;                                                                            // 钳到零 [-] EN: clamp to zero
END_IF
rDb := rDeadbandMinMm + (rDeadbandMaxMm - rDeadbandMinMm) * rRatioC;                                // 死区 [mm] EN: the dead band

// 段5｜出口：死区已在 [min,max] 内，另做一次非有限复检
IF (rDb <> rDb) OR (rDb < DL_WGD_Z) THEN                                                            // 复检 EN: recheck the result
    nFaultCode := DL_WGD_C_RANG;                                                                    // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                         // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rDeadbandMm := rDb;                                                                                 // 死区出口 [mm] EN: the dead band output
rSpeedRatio := rRatioC;                                                                             // 速度比出口 [-] EN: the speed ratio output
xValid := TRUE;                                                                                     // 结果可信 EN: the results are valid
FC_DL_WebGuideDeadbandCalc := TRUE;                                                                 // 返回真 EN: return true
END_FUNCTION
