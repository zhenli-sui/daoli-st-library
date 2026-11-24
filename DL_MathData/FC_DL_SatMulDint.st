(*
  FC_DL_SatMulDint —— DINT 乘法饱和，先判溢出条件再乘
  分类：DL_MathData | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：有符号双整数乘法，先做「除后比较」溢出判定再执行乘法，越界钳到 DINT 上下界并置 xSat。
  契约：diA / diB 乘数；diOut 饱和积；xSat 报告饱和（信息级）。DINT 上下界在本文件内定义。
  边界：① 零乘数先短路；② DINT_MIN 单独分支（ABS(DINT_MIN) 会溢出，禁走 ABS 路径）；
        ③ 一般情形用 |a| > MAX / |b| 的整除判据（整除结果偏保守，安全方向）；
        ④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatMulDint : DINT
VAR_INPUT
    diA : DINT := 0;                  // 乘数 A [—] / The multiplier A
    diB : DINT := 0;                  // 乘数 B [—] / The multiplier B
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 饱和发生标志（信息级） [—] / The saturation flag, informational
END_VAR
VAR
    xNeg : BOOL;                      // 积的符号（异号） [—] / The product sign, true when opposite
END_VAR
VAR CONSTANT
    DL_DINT_MAX : DINT := 2147483647; // DINT 上界（本件私有） [-] / The DINT maximum, private to this file
    DL_DINT_MIN : DINT := -2147483647 - 1; // DINT 下界（本件私有） [-] / The DINT minimum, private to this file
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
xNeg := ((diA > 0) AND (diB < 0)) OR ((diA < 0) AND (diB > 0)); // 异号判定 / the opposite sign test
IF (diA = 0) OR (diB = 0) THEN                        // 零乘数短路（不溢出） / a zero multiplier never overflows
    FC_DL_SatMulDint := 0;                            // 积为零 / the product is zero
ELSIF diB = 1 THEN                                    // 乘一保持原值 / multiply by one keeps the value
    FC_DL_SatMulDint := diA;                          // 返回被乘数 / return the other operand
ELSIF diA = 1 THEN                                    // 乘一保持原值 / multiply by one keeps the value
    FC_DL_SatMulDint := diB;                          // 返回被乘数 / return the other operand
ELSIF diB = -1 THEN                                   // 乘负一（DINT_MIN 例外） / multiply by minus one
    IF diA = DL_DINT_MIN THEN                         // 唯一上溢组合 / the only overflowing combination
        FC_DL_SatMulDint := DL_DINT_MAX;              // 钳到上界 / clamp to the maximum
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
    ELSE
        FC_DL_SatMulDint := 0 - diA;                  // 取负（界内） / the in range negation
    END_IF
ELSIF diA = -1 THEN                                   // 乘负一（DINT_MIN 例外） / multiply by minus one
    IF diB = DL_DINT_MIN THEN                         // 唯一上溢组合 / the only overflowing combination
        FC_DL_SatMulDint := DL_DINT_MAX;              // 钳到上界 / clamp to the maximum
        xSat := TRUE;                                 // 置饱和标志 / raise the saturation flag
    ELSE
        FC_DL_SatMulDint := 0 - diB;                  // 取负（界内） / the in range negation
    END_IF
ELSIF (diA = DL_DINT_MAX) OR (diB = DL_DINT_MAX) OR (diA = DL_DINT_MIN) OR (diB = DL_DINT_MIN) THEN
    IF xNeg THEN                                      // 异号，积为负，溢出下界 / opposite signs underflow
        FC_DL_SatMulDint := DL_DINT_MIN;              // 钳到下界 / clamp to the minimum
    ELSE                                              // 同号，积为正，溢出上界 / the same signs overflow high
        FC_DL_SatMulDint := DL_DINT_MAX;              // 钳到上界 / clamp to the maximum
    END_IF
    xSat := TRUE;                                     // 置饱和标志 / raise the saturation flag
ELSIF ABS(diA) > (DL_DINT_MAX / ABS(diB)) THEN        // 除后比较（两乘数均已排除 DINT_MIN，ABS 安全） / the divide test
    IF xNeg THEN                                      // 异号下溢 / the negative overflow
        FC_DL_SatMulDint := DL_DINT_MIN;              // 钳到下界 / clamp to the minimum
    ELSE                                              // 同号上溢 / the positive overflow
        FC_DL_SatMulDint := DL_DINT_MAX;              // 钳到上界 / clamp to the maximum
    END_IF
    xSat := TRUE;                                     // 置饱和标志 / raise the saturation flag
ELSE
    FC_DL_SatMulDint := diA * diB;                    // 界内直接相乘 / the safe multiplication
END_IF
END_FUNCTION
