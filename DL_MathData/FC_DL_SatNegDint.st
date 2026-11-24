(*
  FC_DL_SatNegDint —— DINT 取负饱和，DINT_MIN 不回绕
  分类：DL_MathData | 复杂度：1 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：双整数取负；DINT_MIN 的相反数超出 DINT 上界，饱和到 DINT_MAX 并置 xSat，绝不回绕成负数。
  契约：diIn 输入；diOut 结果；xSat 报告边界饱和（信息级）。DINT 上下界在本文件内定义。
  边界：不使用一元负号直接作用于 DINT（DINT_MIN 回绕），改用 0 - diIn 并前置边界分支；
        零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatNegDint : DINT
VAR_INPUT
    diIn : DINT := 0;                 // 输入操作数 [—] / The input operand
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 边界饱和标志（信息级） [—] / The boundary saturation flag
END_VAR
VAR CONSTANT
    DL_DINT_MAX : DINT := 2147483647; // DINT 上界（本件私有） [-] / The DINT maximum, private to this file
    DL_DINT_MIN : DINT := -2147483647 - 1; // DINT 下界（本件私有） [-] / The DINT minimum, private to this file
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
IF diIn = DL_DINT_MIN THEN                            // 唯一回绕点 / the only wrapping input
    FC_DL_SatNegDint := DL_DINT_MAX;                  // 饱和到上界 / saturate to the maximum
    xSat := TRUE;                                     // 置饱和标志 / raise the saturation flag
ELSE
    FC_DL_SatNegDint := 0 - diIn;                     // 双字域取负（界内安全） / the in range negation
END_IF
END_FUNCTION
