(*
  FC_DL_Q15AbsSat —— Q15 取绝对值饱和，正确处理 -32768 边界
  分类：DL_Base | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：Q15 取绝对值；-32768 的绝对值 32768 超出 Q15 上界，饱和回 32767 并置 xSat。
  契约：iIn 输入 [Q15]；返回绝对值 [Q15]；xSat 报告 -32768 边界饱和（信息级）。
  边界：不走 ABS(INT)（-32768 上溢），先升 DINT 再取绝对值；零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_Q15AbsSat : INT
VAR_INPUT
    iIn : INT := 0;                   // 输入操作数 [Q15] / The input operand in Q15
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 边界饱和标志（信息级） [—] / The boundary saturation flag
END_VAR
VAR
    diAbs : DINT;                     // 双字绝对值暂存 [Q15] / The double word absolute stage
END_VAR
VAR CONSTANT
    Q15_MAX : DINT := 32767;          // Q15 上界 [-] / The Q15 upper bound
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
diAbs := ABS(INT_TO_DINT(iIn));                       // 升 DINT 后取绝对值（-32768 在 DINT 域安全） [Q15] / absolute in DINT
IF diAbs > Q15_MAX THEN                               // 仅 -32768 会命中此分支 / only minus 32768 hits this branch
    FC_DL_Q15AbsSat := DINT_TO_INT(Q15_MAX);          // 饱和到 Q15_MAX [Q15] / saturate high
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSE
    FC_DL_Q15AbsSat := DINT_TO_INT(diAbs);            // 界内直接转换 [Q15] / in range conversion
END_IF
END_FUNCTION
