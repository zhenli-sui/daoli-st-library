(*
  FC_DL_SatMulLreal —— LREAL 乘法饱和加非有限值闸
  分类：DL_MathData | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：实数乘法后按 [fMin, fMax] 饱和；四个浮点入参逐一非有限闸，任一非法即归零并置 xValid = FALSE。
  契约：fA / fB 乘数、fMin / fMax 饱和区间；fOut 结果；xSat 报告饱和；xValid 结果可信。
  边界：① 区间倒置判非法；② 乘积非有限自检（1.0E30 量级输入相乘可达 1.0E60，仍属有限，但保留自检闸）；
        ③ 零乘数短路为 0（不进入饱和路径）；④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatMulLreal : LREAL
VAR_INPUT
    fA   : LREAL := 1.0;              // 乘数 A [工程单位] / The multiplier A
    fB   : LREAL := 1.0;              // 乘数 B [—] / The multiplier B
    fMin : LREAL := -1000.0;          // 饱和下限 [工程单位] / The saturation low limit
    fMax : LREAL := 1000.0;           // 饱和上限 [工程单位] / The saturation high limit
END_VAR
VAR_OUTPUT
    xSat   : BOOL;                    // 饱和发生标志（信息级） [—] / The saturation flag, informational
    xValid : BOOL;                    // 结果可信 [—] / The result is valid
END_VAR
VAR
    fProd : LREAL;                    // 乘积中间量 [工程单位] / The product intermediate
END_VAR
VAR CONSTANT
    DL_ML_INF : LREAL := 1.0E30;      // 非有限 / 越界判据上限 [-] / The magnitude gate
    DL_ML_Z   : LREAL := 0.0;         // 浮点零常量 [工程单位] / The floating point zero constant
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
xValid := FALSE;                                      // 可信位预置假 / preset the valid flag false
FC_DL_SatMulLreal := DL_ML_Z;                         // 返回值预置零 / preset the return zero
IF (fA <> fA) OR (ABS(fA) > DL_ML_INF) THEN           // 乘数 A 非有限闸 / the multiplier A gate
    FC_DL_SatMulLreal := DL_ML_Z;                     // 非有限归零 / zero the non finite input
ELSIF (fB <> fB) OR (ABS(fB) > DL_ML_INF) THEN        // 乘数 B 非有限闸 / the multiplier B gate
    FC_DL_SatMulLreal := DL_ML_Z;                     // 非有限归零 / zero the non finite input
ELSIF (fMin <> fMin) OR (ABS(fMin) > DL_ML_INF) THEN  // 下限非有限闸 / the low limit gate
    FC_DL_SatMulLreal := DL_ML_Z;                     // 非有限归零 / zero the non finite input
ELSIF (fMax <> fMax) OR (ABS(fMax) > DL_ML_INF) THEN  // 上限非有限闸 / the high limit gate
    FC_DL_SatMulLreal := DL_ML_Z;                     // 非有限归零 / zero the non finite input
ELSIF fMax < fMin THEN                                // 饱和区间倒置 / the saturated band is inverted
    FC_DL_SatMulLreal := DL_ML_Z;                     // 非法区间归零 / zero on an invalid band
ELSE
    fProd := fA * fB;                                 // 求积 [工程单位] / the product
    IF fProd <> fProd THEN                            // 乘积非有限自检 / the product self check
        FC_DL_SatMulLreal := DL_ML_Z;                 // 非有限归零 / zero the non finite product
    ELSIF fProd > fMax THEN                           // 上越界 / above the high limit
        FC_DL_SatMulLreal := fMax;                    // 钳到上限 [工程单位] / clamp to the high limit
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
        xValid := TRUE;                               // 饱和输出仍可信 / a saturated output is still valid
    ELSIF fProd < fMin THEN                           // 下越界 / below the low limit
        FC_DL_SatMulLreal := fMin;                    // 钳到下限 [工程单位] / clamp to the low limit
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
        xValid := TRUE;                               // 饱和输出仍可信 / a saturated output is still valid
    ELSE
        FC_DL_SatMulLreal := fProd;                   // 界内直接输出 / the in range product
        xValid := TRUE;                               // 结果可信 / the result is valid
    END_IF
END_IF
END_FUNCTION
