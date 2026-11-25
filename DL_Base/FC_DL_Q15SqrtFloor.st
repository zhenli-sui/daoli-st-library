(*
  FC_DL_Q15SqrtFloor —— Q15 定点整数平方根（逐位法），结果 Q15
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：把 Q15 输入按 Q15 语义开方（即 out = floor(sqrt(in / 32768) * 32768)）：
        先把被开方数放大 15 位成 Q30，再用逐位法（bit-by-bit）求整数平方根，结果天然是 Q15。
  契约：iIn 输入 [Q15]；返回平方根 [Q15]；负输入钳 0（置 xClamp 报告）。
  边界：① 输入钳 ≥0（负数无实数根）；② 逐位法只用整数加减与除 2 / 除 4，无浮点、无开方库依赖；
        ③ 被开方数 <= 32767 * 32768 = 1.073e9 界内；④ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_Q15SqrtFloor : INT
VAR_INPUT
    iIn : INT := 0;                   // 被开方数 [Q15] / The radicand in Q15
END_VAR
VAR_OUTPUT
    xClamp : BOOL;                    // 负输入钳零标志（信息级） [—] / The negative input clamp flag
END_VAR
VAR
    diV    : DINT;                    // 已放大 15 位的被开方数 [Q30] / The radicand scaled to Q30
    diRem  : DINT;                    // 逐位法余数 [Q30] / The remainder of the bit by bit method
    diRoot : DINT;                    // 逐位法根累加器 [Q30] / The root accumulator
    diBit  : DINT;                    // 逐位法试探位（4 的幂递减） [Q30] / The trial bit decreasing by four
END_VAR
VAR CONSTANT
    DL_QS_SC   : DINT := 32768;       // 定标因子（2^15） [-] / The Q15 scaling factor
    DL_QS_TOP  : DINT := 1073741824;  // 试探位初值 2^30 [-] / The initial trial bit
    DL_QS_Z    : DINT := 0;           // 整型零常量 [-] / The integer zero constant
    DL_QS_TWO  : DINT := 2;           // 除二常量 [-] / The divide by two constant
    DL_QS_FOUR : DINT := 4;           // 除四常量 [-] / The divide by four constant
END_VAR

xClamp := FALSE;                                      // 钳位标志预置假 / preset the clamp flag false
IF iIn < DINT_TO_INT(DL_QS_Z) THEN                    // 负输入（无实数根） / a negative input has no real root
    FC_DL_Q15SqrtFloor := DINT_TO_INT(DL_QS_Z);       // 结果钳零 [Q15] / clamp the result to zero
    xClamp := TRUE;                                   // 置钳位标志 [—] / raise the clamp flag
ELSE
    diV := INT_TO_DINT(iIn) * DL_QS_SC;               // 放大 15 位成 Q30 被开方数（界内已证） [Q30] / scale to Q30
    diRem := diV;                                     // 余数初值取被开方数 [Q30] / the initial remainder
    diRoot := DL_QS_Z;                                // 根累加器清零 [Q30] / clear the root accumulator
    diBit := DL_QS_TOP;                               // 试探位从 2^30 起 [Q30] / start from the top trial bit
    WHILE diBit > diV DO                              // 试探位降到不超被开方数（逐位法前置归一） / normalise the trial bit
        diBit := diBit / DL_QS_FOUR;                  // 试探位每次降 4 倍 [Q30] / decrease the trial bit by four
    END_WHILE
    WHILE diBit > DL_QS_Z DO                          // 主循环：16 次迭代后试探位归零 / the main loop ends at zero
        IF diRem >= (diRoot + diBit) THEN              // 余数够减 / the remainder is large enough
            diRem := diRem - diRoot - diBit;          // 扣减根与试探位 [Q30] / subtract the root and the trial bit
            diRoot := (diRoot / DL_QS_TWO) + diBit;   // 根累加器置位 [Q30] / set the root accumulator bit
        ELSE
            diRoot := diRoot / DL_QS_TWO;             // 根累加器右移一位 [Q30] / shift the root accumulator
        END_IF
        diBit := diBit / DL_QS_FOUR;                  // 试探位每次降 4 倍 [Q30] / decrease the trial bit by four
    END_WHILE
    FC_DL_Q15SqrtFloor := DINT_TO_INT(diRoot);        // 逐位法根即 Q15 结果 [Q15] / the root is the Q15 result
END_IF
END_FUNCTION
