(*
  FC_DL_Q15NegSat —— Q15 取负饱和，-32768 不回绕
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：Q15 取负；-32768 的相反数 32768 超出 Q15 上界，饱和回 32767 并置 xSat。
  契约：iIn 输入 [Q15]；返回相反数 [Q15]；xSat 报告 -32768 边界饱和（信息级）。
  边界：不使用一元负号直接作用于 INT（-32768 回绕），先在 DINT 域取负；零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_Q15NegSat : INT
VAR_INPUT
    iIn : INT := 0;                   // 输入操作数 [Q15] / The input operand in Q15
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 边界饱和标志（信息级） [—] / The boundary saturation flag
END_VAR
VAR
    diNeg : DINT;                     // 双字取负暂存 [Q15] / The double word negation stage
END_VAR
VAR CONSTANT
    Q15_MAX : DINT := 32767;          // Q15 上界 [-] / The Q15 upper bound
    Q15_MIN : DINT := -32768;         // Q15 下界 [-] / The Q15 lower bound
    DL_QN_Z : DINT := 0;              // 整型零常量 [-] / The integer zero constant
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
diNeg := DL_QN_Z - INT_TO_DINT(iIn);                  // 双字域取负（-32768 → 32768 在 DINT 域安全） [Q15] / negate in DINT
IF diNeg > Q15_MAX THEN                               // 仅 -32768 会命中此分支 / only minus 32768 hits this branch
    FC_DL_Q15NegSat := DINT_TO_INT(Q15_MAX);          // 饱和到 Q15_MAX [Q15] / saturate high
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSIF diNeg < Q15_MIN THEN                            // 下越界（本件数学上不可达，防御保留） / below the lower bound
    FC_DL_Q15NegSat := DINT_TO_INT(Q15_MIN);          // 饱和到 Q15_MIN [Q15] / saturate low
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSE
    FC_DL_Q15NegSat := DINT_TO_INT(diNeg);            // 界内直接转换 [Q15] / in range conversion
END_IF
END_FUNCTION
