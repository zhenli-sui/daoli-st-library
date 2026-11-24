(*
  FC_DL_SatScaleLreal —— LREAL 增益缩放饱和
  分类：DL_MathData | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：实数增益缩放（out = fIn * fGain）后按 [fMin, fMax] 饱和；四个浮点入参逐一非有限闸，
        任一非法即归零并置 xValid = FALSE。
  契约：fIn 输入、fGain 增益、fMin / fMax 饱和区间；fOut 结果；xSat 报告饱和；xValid 结果可信。
  边界：① 区间倒置判非法；② 乘积非有限自检；③ 增益为 0 时输出 0（不进入饱和路径）；
        ④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatScaleLreal : LREAL
VAR_INPUT
    fIn   : LREAL := 0.0;             // 输入值 [工程单位] / The input value
    fGain : LREAL := 1.0;             // 缩放增益 [—] / The scaling gain
    fMin  : LREAL := -1000.0;         // 饱和下限 [工程单位] / The saturation low limit
    fMax  : LREAL := 1000.0;          // 饱和上限 [工程单位] / The saturation high limit
END_VAR
VAR_OUTPUT
    xSat   : BOOL;                    // 饱和发生标志（信息级） [—] / The saturation flag, informational
    xValid : BOOL;                    // 结果可信 [—] / The result is valid
END_VAR
VAR
    fScaled : LREAL;                  // 缩放中间量 [工程单位] / The scaled intermediate
END_VAR
VAR CONSTANT
    DL_SL_INF : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_SL_Z   : LREAL := 0.0;         // 浮点零常量 [工程单位] / The floating point zero constant
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
xValid := FALSE;                                      // 可信位预置假 / preset the valid flag false
FC_DL_SatScaleLreal := DL_SL_Z;                       // 返回值预置零 / preset the return zero
IF (fIn <> fIn) OR (ABS(fIn) > DL_SL_INF) THEN        // 输入非有限闸 / the input gate
    FC_DL_SatScaleLreal := DL_SL_Z;                   // 非有限归零 / zero the non finite input
ELSIF (fGain <> fGain) OR (ABS(fGain) > DL_SL_INF) THEN // 增益非有限闸 / the gain gate
    FC_DL_SatScaleLreal := DL_SL_Z;                   // 非有限归零 / zero the non finite gain
ELSIF (fMin <> fMin) OR (ABS(fMin) > DL_SL_INF) THEN  // 下限非有限闸 / the low limit gate
    FC_DL_SatScaleLreal := DL_SL_Z;                   // 非有限归零 / zero the non finite limit
ELSIF (fMax <> fMax) OR (ABS(fMax) > DL_SL_INF) THEN  // 上限非有限闸 / the high limit gate
    FC_DL_SatScaleLreal := DL_SL_Z;                   // 非有限归零 / zero the non finite limit
ELSIF fMax < fMin THEN                                // 饱和区间倒置 / the saturated band is inverted
    FC_DL_SatScaleLreal := DL_SL_Z;                   // 非法区间归零 / zero on an invalid band
ELSE
    fScaled := fIn * fGain;                           // 增益缩放 [工程单位] / the scaled value
    IF fScaled <> fScaled THEN                        // 缩放结果非有限自检 / the scaled value self check
        FC_DL_SatScaleLreal := DL_SL_Z;               // 非有限归零 / zero the non finite value
    ELSIF fScaled > fMax THEN                         // 上越界 / above the high limit
        FC_DL_SatScaleLreal := fMax;                  // 钳到上限 [工程单位] / clamp to the high limit
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
        xValid := TRUE;                               // 饱和输出仍可信 / a saturated output is still valid
    ELSIF fScaled < fMin THEN                         // 下越界 / below the low limit
        FC_DL_SatScaleLreal := fMin;                  // 钳到下限 [工程单位] / clamp to the low limit
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
        xValid := TRUE;                               // 饱和输出仍可信 / a saturated output is still valid
    ELSE
        FC_DL_SatScaleLreal := fScaled;               // 界内直接输出 / the in range value
        xValid := TRUE;                               // 结果可信 / the result is valid
    END_IF
END_IF
END_FUNCTION
