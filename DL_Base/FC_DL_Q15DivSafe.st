(*
  FC_DL_Q15DivSafe —— Q15 安全除法，除零与商越界双保护
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：Q15 除以 Q15 得 Q15：先把被除数放大 32768 倍（DINT 界内），再整除并按 Q15 饱和。
  契约：iNum 被除数 [Q15]、iDen 除数 [Q15]；返回商 [Q15]；xValid 除数为零时为 FALSE（商给零哨兵）。
  边界：① 除零前置判（R4）；② 商越界双侧饱和；③ 被除数放大后 |值| <= 1.074e9 已证不溢出；
        ④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_Q15DivSafe : INT
VAR_INPUT
    iNum : INT := 0;                  // 被除数 [Q15] / The dividend in Q15
    iDen : INT := 0;                  // 除数 [Q15] / The divisor in Q15
END_VAR
VAR_OUTPUT
    xValid : BOOL;                    // 商可信（除数非零） [—] / The quotient is valid when the divisor is non zero
    xSat   : BOOL;                    // 商越界饱和标志（信息级） [—] / The quotient saturation flag
END_VAR
VAR
    diNum : DINT;                     // 放大后的被除数 [Q30] / The scaled dividend in Q30
    diQ   : DINT;                     // 商暂存 [Q15] / The quotient stage
END_VAR
VAR CONSTANT
    Q15_MAX  : DINT := 32767;         // Q15 上界 [-] / The Q15 upper bound
    Q15_MIN  : DINT := -32768;        // Q15 下界 [-] / The Q15 lower bound
    DL_QD_SC : DINT := 32768;         // 定标因子（2^15） [-] / The Q15 scaling factor
    DL_QD_Z  : DINT := 0;             // 整型零常量 [-] / The integer zero constant
END_VAR

xValid := FALSE;                                      // 可信位预置假 / preset the valid flag false
xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
IF iDen = DL_QD_Z THEN                                // 除数为零（除零防护，前置判） / the divisor is zero
    FC_DL_Q15DivSafe := DINT_TO_INT(DL_QD_Z);         // 商给零哨兵 [Q15] / the zero sentinel quotient
ELSE
    diNum := INT_TO_DINT(iNum) * DL_QD_SC;            // 被除数放大 15 位（|值| <= 1.074e9 界内） [Q30] / scale the dividend
    diQ := diNum / INT_TO_DINT(iDen);                 // 整除得商（分母已证非零） [Q15] / integer division
    IF diQ > Q15_MAX THEN                             // 商上越界 / the quotient above the upper bound
        FC_DL_Q15DivSafe := DINT_TO_INT(Q15_MAX);     // 饱和到 Q15_MAX [Q15] / saturate high
        xSat := TRUE;                                 // 置饱和标志 [—] / raise the saturation flag
    ELSIF diQ < Q15_MIN THEN                          // 商下越界 / the quotient below the lower bound
        FC_DL_Q15DivSafe := DINT_TO_INT(Q15_MIN);     // 饱和到 Q15_MIN [Q15] / saturate low
        xSat := TRUE;                                 // 置饱和标志 [—] / raise the saturation flag
    ELSE
        FC_DL_Q15DivSafe := DINT_TO_INT(diQ);         // 界内直接转换 [Q15] / in range conversion
    END_IF
    xValid := TRUE;                                   // 除法成功，商可信 [—] / the division succeeded
END_IF
END_FUNCTION
