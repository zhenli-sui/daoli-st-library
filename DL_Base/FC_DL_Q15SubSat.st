(*
  FC_DL_Q15SubSat —— Q15 定点减法饱和
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：Q15 域 iA - iB，中间用 DINT 承载，结果按 Q15 上下界饱和（含 -32768 边界）。
  契约：输入 iA / iB 为 Q15 操作数；返回 Q15 差；xSat 报告本拍发生饱和（信息级）。
  边界：DINT 中间量 + 上下界双判，无除法、无浮点比较；零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_Q15SubSat : INT
VAR_INPUT
    iA : INT := 0;                    // 被减数 A [Q15] / The minuend A in Q15
    iB : INT := 0;                    // 减数 B [Q15] / The subtrahend B in Q15
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 饱和发生标志（信息级） [—] / The saturation flag, informational
END_VAR
VAR
    diDiff : DINT;                    // 双字中间差 [Q15] / The double word intermediate difference
END_VAR
VAR CONSTANT
    Q15_MAX : DINT := 32767;          // Q15 上界 [-] / The Q15 upper bound
    Q15_MIN : DINT := -32768;         // Q15 下界 [-] / The Q15 lower bound
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
diDiff := INT_TO_DINT(iA) - INT_TO_DINT(iB);          // 双字域求差（|差| <= 65535 不溢出） [Q15] / subtract in DINT
IF diDiff > Q15_MAX THEN                              // 上越界 / above the upper bound
    FC_DL_Q15SubSat := DINT_TO_INT(Q15_MAX);          // 饱和到 Q15_MAX [Q15] / saturate high
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSIF diDiff < Q15_MIN THEN                           // 下越界 / below the lower bound
    FC_DL_Q15SubSat := DINT_TO_INT(Q15_MIN);          // 饱和到 Q15_MIN [Q15] / saturate low
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSE
    FC_DL_Q15SubSat := DINT_TO_INT(diDiff);           // 界内直接转换 [Q15] / in range conversion
END_IF
END_FUNCTION
