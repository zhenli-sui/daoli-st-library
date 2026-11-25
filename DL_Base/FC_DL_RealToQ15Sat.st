(*
  FC_DL_RealToQ15Sat —— REAL 转 Q15 定点，四舍五入加饱和，非有限值归零
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把归一化实数 fIn（-1.0..+1.0 对应 -32768..32767）转成 Q15 整数：
        非有限值（NaN / Inf）一律归零；放大 32768 后按符号做四舍五入，再按 Q15 上下界饱和。
  契约：fIn 输入 [归一化实数 -1.0..1.0]；返回 Q15 值；xInvalid 报告输入为非有限值（信息级）。
  边界：① NaN 用自反判（fIn <> fIn）、Inf 用绝对上限判（ABS(fIn) > 1.0E30），禁用近似阈值；
        ② 实数转整前的上限兜底：放大值越 40000 时直接饱和，避免 LREAL_TO_DINT 越域未定义；
        ③ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_RealToQ15Sat : INT
VAR_INPUT
    fIn : REAL := 0.0;                // 归一化输入实数 [归一化] / The normalised real input
END_VAR
VAR_OUTPUT
    xInvalid : BOOL;                  // 输入为非有限值（信息级，已归零） [—] / The input was not finite and was zeroed
    xSat     : BOOL;                  // 越界饱和标志（信息级） [—] / The range saturation flag
END_VAR
VAR
    fScaled : LREAL;                  // 放大 32768 倍后的实数 [Q15 实数域] / The scaled real value
    diR     : DINT;                   // 四舍五入后的整数暂存 [Q15] / The rounded integer stage
END_VAR
VAR CONSTANT
    Q15_MAX    : DINT  := 32767;      // Q15 上界 [-] / The Q15 upper bound
    Q15_MIN    : DINT  := -32768;     // Q15 下界 [-] / The Q15 lower bound
    DL_QR_SC   : LREAL := 32768.0;    // 定标因子（2^15） [-] / The Q15 scaling factor
    DL_QR_HALF : LREAL := 0.5;        // 四舍五入偏置 [-] / The rounding bias
    DL_QR_LIM  : LREAL := 40000.0;    // 转整前的实数上限兜底 [-] / The real upper guard before conversion
    DL_QR_INF  : REAL  := 1.0E30;     // 非有限 / 越界判据上限 [-] / The magnitude gate for non finite detection
    DL_QR_TINY : LREAL := 1.0E-9;     // 浮点零比较容差 [-] / The floating point zero tolerance
    DL_QR_Z    : DINT  := 0;          // 整型零常量 [-] / The integer zero constant
END_VAR

xInvalid := FALSE;                                    // 非有限标志预置假 / preset the non finite flag false
xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
IF (fIn <> fIn) OR (ABS(fIn) > DL_QR_INF) THEN        // 自反判 NaN 或越限判 Inf（R 规则禁用近似阈值） / NaN or Inf
    FC_DL_RealToQ15Sat := DINT_TO_INT(DL_QR_Z);       // 非有限值归零 [Q15] / zero the non finite input
    xInvalid := TRUE;                                 // 置非有限标志 [—] / raise the non finite flag
ELSE
    fScaled := REAL_TO_LREAL(fIn) * DL_QR_SC;         // 放大 32768 倍 [Q15 实数域] / scale by the Q15 factor
    IF fScaled > DL_QR_LIM THEN                       // 转整前上限兜底（正溢出） / the positive conversion guard
        FC_DL_RealToQ15Sat := DINT_TO_INT(Q15_MAX);   // 直接饱和到 Q15_MAX [Q15] / saturate high
        xSat := TRUE;                                 // 置饱和标志 [—] / raise the saturation flag
    ELSIF fScaled < -DL_QR_LIM THEN                   // 转整前下限兜底（负溢出） / the negative conversion guard
        FC_DL_RealToQ15Sat := DINT_TO_INT(Q15_MIN);   // 直接饱和到 Q15_MIN [Q15] / saturate low
        xSat := TRUE;                                 // 置饱和标志 [—] / raise the saturation flag
    ELSE
        IF fScaled >= DL_QR_HALF THEN                 // 非负做加偏置四舍五入 / non negative rounding
            diR := LREAL_TO_DINT(fScaled + DL_QR_HALF); // 加 0.5 后截断 [Q15] / add a half then truncate
        ELSIF fScaled <= -DL_QR_HALF THEN             // 非正做减偏置四舍五入 / non positive rounding
            diR := LREAL_TO_DINT(fScaled - DL_QR_HALF); // 减 0.5 后截断 [Q15] / subtract a half then truncate
        ELSE
            diR := DL_QR_Z;                           // |值| < 0.5 归零（近零带） [Q15] / the near zero band
        END_IF
        IF diR > Q15_MAX THEN                         // 上越界 / above the upper bound
            FC_DL_RealToQ15Sat := DINT_TO_INT(Q15_MAX); // 饱和到 Q15_MAX [Q15] / saturate high
            xSat := TRUE;                             // 置饱和标志 [—] / raise the saturation flag
        ELSIF diR < Q15_MIN THEN                      // 下越界 / below the lower bound
            FC_DL_RealToQ15Sat := DINT_TO_INT(Q15_MIN); // 饱和到 Q15_MIN [Q15] / saturate low
            xSat := TRUE;                             // 置饱和标志 [—] / raise the saturation flag
        ELSE
            FC_DL_RealToQ15Sat := DINT_TO_INT(diR);   // 界内直接转换 [Q15] / in range conversion
        END_IF
    END_IF
END_IF
END_FUNCTION
