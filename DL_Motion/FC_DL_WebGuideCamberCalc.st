(*
  Component : FC_DL_WebGuideCamberCalc
  Category  : DL_Motion
  Function  : 镰刀弯曲率（三点弦高法）：camber = 8000 × h / L²，输出 mm/m 与等效曲率半径
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rChordMm 测量弦长（两基准点间距） [mm]、rSagittaMm 中点弦高（带符号） [mm]、
             rCamberMaxMmM 弯曲率工艺上限 [mm/m]；
             输出 rCamberMmM 带符号弯曲率 [mm/m]、rRadiusM 等效曲率半径 [m]、
             xCamberHigh 超上限（信息级）、xValid 有效标志、nFaultCode 故障码。
  边界     : 弦长须 >1.0E-6 [mm]；曲率半径 R = L²/(8h)，h 趋零时 R 趋于无穷，此时半径输出给 0 表示「直」；
             弯曲率 = 1000/R (R 以 mm 计时为 mm/m)，等价式 8000h/L²，符号随弦高；
             上限 1.0E4 [mm/m] 远小于 LREAL 上限，可表。
  码位     : 9801 输入非有限（故障级）；9802 弦长越域（故障级）。
*)
FUNCTION FC_DL_WebGuideCamberCalc : BOOL
VAR_INPUT
    rChordMm      : LREAL := 1000.0;  // 测量弦长 [mm] EN: the measured chord length
    rSagittaMm    : LREAL := 2.0;     // 中点弦高，正负表示弯曲方向 [mm] EN: the mid point sagitta, the sign carries the camber direction
    rCamberMaxMmM : LREAL := 5.0;     // 弯曲率工艺上限 [mm/m] EN: the technological upper bound of the camber rate
END_VAR
VAR_OUTPUT
    rCamberMmM  : LREAL;              // 带符号弯曲率 [mm/m] EN: the signed camber rate
    rRadiusM    : LREAL;              // 等效曲率半径，零表示直 [m] EN: the equivalent curvature radius, zero means straight
    xCamberHigh : BOOL;               // 超工艺上限（信息级） EN: above the technological limit, information class only
    xValid      : BOOL;               // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;                // 0=无故障 9801=输入非有限 9802=弦长越域 EN: zero none, 9801 non finite, 9802 chord out of range
END_VAR
VAR
    xFinAll : BOOL;                   // 三输入同时有限 EN: all three inputs are finite
    rDen    : LREAL;                  // 分母 L²/8 [mm] EN: the divisor, the squared chord over eight
    rCam    : LREAL;                  // 弯曲率中间值 [mm/m] EN: the interim camber rate
    rRad    : LREAL;                  // 半径中间值 [m] EN: the interim radius
END_VAR
VAR CONSTANT
    DL_WGC_Z       : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_WGC_EIGHT   : LREAL := 8.0;    // 弦高法几何系数 EN: the geometric factor of the sagitta method
    DL_WGC_K1000   : LREAL := 1000.0; // 毫米转米系数 EN: the millimetre to metre factor
    DL_WGC_MIN     : LREAL := 1.0E-6; // 弦长与除数的下限 [mm] EN: the lower bound of the chord and the divisor
    DL_WGC_C_BAD   : INT := 9801;     // 输入非有限 EN: a non finite input
    DL_WGC_C_CHORD : INT := 9802;     // 弦长越域 EN: the chord is out of range
END_VAR

// 段1｜出口预置
FC_DL_WebGuideCamberCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rCamberMmM := DL_WGC_Z;               // 弯曲率预置零 [mm/m] EN: preset the camber rate to zero
rRadiusM := DL_WGC_Z;                 // 半径预置零 [m] EN: preset the radius to zero
xCamberHigh := FALSE;                 // 超限标志预置假 EN: preset the over camber flag to false
xValid := FALSE;                      // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                      // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：三输入全列（上限参与出口判据）
xFinAll := (rChordMm = rChordMm) AND ((rChordMm - rChordMm) = DL_WGC_Z)
        AND (rSagittaMm = rSagittaMm) AND ((rSagittaMm - rSagittaMm) = DL_WGC_Z)
        AND (rCamberMaxMmM = rCamberMaxMmM) AND ((rCamberMaxMmM - rCamberMaxMmM) = DL_WGC_Z);   // 三输入有限性 EN: the finiteness of all three inputs
IF NOT xFinAll THEN                                                                             // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WGC_C_BAD;                                                                 // 非有限码 EN: the non finite code
    RETURN;                                                                                     // 早退 EN: return early
END_IF

// 段3｜域闸：弦长必须足够大（分母 L²/8 直接依赖弦长）
rDen := (rChordMm * rChordMm) / DL_WGC_EIGHT;                                                   // 分母 L²/8 [mm] EN: the divisor
IF ABS(rDen) < DL_WGC_MIN THEN                                                                  // 分母下限 EN: the divisor magnitude gate
    nFaultCode := DL_WGC_C_CHORD;                                                               // 弦长越域码 EN: the chord code
    RETURN;                                                                                     // 早退 EN: return early
END_IF

// 段4｜主体：camber = h / (L²/8) × 1000 = 8000h/L²
rCam := (rSagittaMm / rDen) * DL_WGC_K1000;                                                     // 弯曲率 [mm/m]，符号随弦高 EN: the camber rate carrying the sagitta sign
IF rCam <> rCam THEN                                                                            // 结果复检 EN: recheck the result
    nFaultCode := DL_WGC_C_CHORD;                                                               // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                     // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段5｜等效半径：弦高趋零时半径趋于无穷，统一给 0 表示直（不输出 Inf 污染上层）
IF ABS(rSagittaMm) < DL_WGC_MIN THEN                                                            // 近似直带 EN: the nearly straight band
    rRad := DL_WGC_Z;                                                                           // 半径给零表示直 [m] EN: give zero to mean straight
ELSE
    rRad := (rDen / rSagittaMm) / DL_WGC_K1000;                                                 // 半径 R = (L²/8)/h，由毫米折米 [m] EN: the radius folded to metres
END_IF

// 段6｜出口
rCamberMmM := rCam;                                                                             // 弯曲率出口 [mm/m] EN: the camber rate output
rRadiusM := rRad;                                                                               // 半径出口 [m] EN: the radius output
xCamberHigh := ABS(rCam) > rCamberMaxMmM;                                                       // 超限判据（信息级，双向均判） EN: the over camber test, information class, both directions
xValid := TRUE;                                                                                 // 结果可信 EN: the results are valid
FC_DL_WebGuideCamberCalc := TRUE;                                                               // 返回真 EN: return true
END_FUNCTION
