(*
  FC_DL_Q15Lerp —— Q15 线性插值，alpha 定点，端点饱和
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：按 Q15 权重做线性插值：out = A + (B - A) * alpha / 32767；alpha = 0 得 A，alpha = 32767 得 B。
  契约：iA 起点 [Q15]、iB 终点 [Q15]、iAlpha 权重 [Q15 归一化 0..32767]；返回插值 [Q15]；xSat 报告饱和。
  边界：① 乘积 |diD * alpha| <= 65535 * 32767 = 2.147e9 界内已证；② 除数恒为常量 32767 非零；
        ③ 端点经饱和钳位保证不越 Q15；零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_Q15Lerp : INT
VAR_INPUT
    iA      : INT := 0;               // 插值起点值 [Q15] / The interpolation start value in Q15
    iB      : INT := 0;               // 插值终点值 [Q15] / The interpolation end value in Q15
    iAlpha  : INT := 0;               // 归一化权重 0..32767 [Q15] / The normalised weight in Q15
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 饱和发生标志（信息级） [—] / The saturation flag, informational
END_VAR
VAR
    diD   : DINT;                     // 端点差 [Q15] / The endpoint difference
    diP   : DINT;                     // 差乘权重（Q30 量级，界内已证） [Q30] / The scaled product
    diQ   : DINT;                     // 插值增量 [Q15] / The interpolation increment
    diR   : DINT;                     // 插值结果暂存 [Q15] / The interpolation result stage
END_VAR
VAR CONSTANT
    Q15_MAX   : DINT := 32767;        // Q15 上界 [-] / The Q15 upper bound
    Q15_MIN   : DINT := -32768;       // Q15 下界 [-] / The Q15 lower bound
    DL_QL_ONE : DINT := 32767;        // 归一化满量程（2^15 - 1） [-] / The normalisation full scale
    DL_QL_Z   : DINT := 0;            // 整型零常量 [-] / The integer zero constant
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
diD := INT_TO_DINT(iB) - INT_TO_DINT(iA);             // 端点差（|差| <= 65535） [Q15] / the endpoint difference
diP := diD * INT_TO_DINT(iAlpha);                     // 差乘权重（|积| <= 2.147e9 界内已证） [Q30] / the scaled product
diQ := diP / DL_QL_ONE;                               // 除以归一化满量程（常量非零） [Q15] / divide by the full scale
diR := INT_TO_DINT(iA) + diQ;                         // 起点加增量 [Q15] / the start plus the increment
IF diR > Q15_MAX THEN                                 // 上越界 / above the upper bound
    FC_DL_Q15Lerp := DINT_TO_INT(Q15_MAX);            // 饱和到 Q15_MAX [Q15] / saturate high
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSIF diR < Q15_MIN THEN                              // 下越界 / below the lower bound
    FC_DL_Q15Lerp := DINT_TO_INT(Q15_MIN);            // 饱和到 Q15_MIN [Q15] / saturate low
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSE
    FC_DL_Q15Lerp := DINT_TO_INT(diR);                // 界内直接转换 [Q15] / in range conversion
END_IF
END_FUNCTION
