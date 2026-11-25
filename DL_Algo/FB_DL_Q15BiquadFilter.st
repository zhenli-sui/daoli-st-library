(*
  FB_DL_Q15BiquadFilter —— Q15 定点二阶 IIR 滤波：系数定点化、中间累加防溢出、移位饱和输出
  分类：DL_Algo | 复杂度：3 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT

  职责：以直接 II 型转置（DF2T）结构实现二阶 IIR：y[n] = b0*x[n] + z1[n-1]；
        z1[n] = b1*x[n] - a1*y[n] + z2[n-1]；z2[n] = b2*x[n] - a2*y[n]。
        全部乘加在 DINT 内完成（Q15 × Q15 得 Q30），统一做「四舍五入右移 15 位 + Q15 饱和」，不调用任何外部库件。
  输入契约：arrCoef[0..4] = b0 / b1 / b2 / a1 / a2，均为 Q15 系数（±1.0 对应 ±32767）；
            iIn 为 Q15 输入；xReset 上升至真清历史；xEnable = FALSE 时清历史并输出 0。
  输出契约：iOut 为 Q15 输出；xOverflow 表示本拍发生了乘法累加或输出的饱和（信息级，可每拍重算）。
  边界：① 无除法、无开方，除零风险为零；② 所有移位用「乘 32768 / 除 32768」表达，避免方言 SHL/SHR 语义差异；
        ③ 定点饱和阈值 Q15_MAX / Q15_MIN 用 VAR CONSTANT 钉死；④ 零全局耦合、零物理地址、零库件依赖（R16）。
*)

FUNCTION_BLOCK FB_DL_Q15BiquadFilter
VAR_INPUT
    xEnable  : BOOL := TRUE;                              // 使能，FALSE 时清历史并输出零 [—] / Enable, false clears history
    xReset   : BOOL := FALSE;                             // 复位，真时清历史（单拍即可，无需沿） [—] / Reset, clears the history
    iIn      : INT  := 0;                                 // Q15 定点输入 [Q15] / The Q15 fixed point input
    arrCoef  : ARRAY[0..4] OF INT;                        // Q15 系数 b0/b1/b2/a1/a2 [Q15] / The Q15 coefficients
END_VAR
VAR_OUTPUT
    iOut      : INT;                                      // Q15 定点输出 [Q15] / The Q15 fixed point output
    xOverflow : BOOL;                                     // 本拍发生饱和（信息级） [—] / A saturation occurred this scan
END_VAR
VAR
    arrHist   : ARRAY[0..3] OF INT;                       // 历史：0=z1 1=z2 2=上拍输入 3=上拍输出 [Q15] / History slots
    diProd1   : DINT;                                     // 第一乘积项（Q30） [Q30] / The first product term
    diProd2   : DINT;                                     // 第二乘积项（Q30） [Q30] / The second product term
    diAcc     : DINT;                                     // 累加器（Q30） [Q30] / The Q30 accumulator
    diSh      : DINT;                                     // 四舍五入右移后的 Q15 暂存 [Q15] / The rounded Q15 stage
    diSum     : DINT;                                     // Q15 域饱和加法暂存 [Q15] / The Q15 domain saturating sum
    iNewZ1    : INT;                                      // 新的 z1 状态 [Q15] / The new z1 state
    iNewZ2    : INT;                                      // 新的 z2 状态 [Q15] / The new z2 state
    iSat      : INT;                                      // 饱和后的输出暂存 [Q15] / The saturated output stage
END_VAR
VAR CONSTANT
    Q15_MAX   : DINT := 32767;                            // Q15 上界 [-] / The Q15 upper bound
    Q15_MIN   : DINT := -32768;                           // Q15 下界 [-] / The Q15 lower bound
    DL_BQ_RND : DINT := 16384;                            // 右移 15 位的四舍五入偏置（2^14） [-] / The rounding bias
    DL_BQ_SC  : DINT := 32768;                            // Q15 定标因子（2^15） [-] / The Q15 scaling factor
    DL_BQ_Z   : DINT := 0;                                // 整型零常量 [Q15] / The integer zero constant
    DL_BQ_I0  : INT := 0;                                 // 整型零常量（INT 域） [Q15] / The integer zero constant in INT domain
    DL_BQ_I1  : INT := 1;                                 // 整型一常量（下标） [下标] / The integer one constant
    DL_BQ_I2  : INT := 2;                                 // 整型二常量（下标） [下标] / The integer two constant
    DL_BQ_I3  : INT := 3;                                 // 整型三常量（下标） [下标] / The integer three constant
    DL_BQ_I4  : INT := 4;                                 // 整型四常量（下标） [下标] / The integer four constant
END_VAR

// 段 1｜出口预置（本拍饱和标志每拍重算，属信息级）
xOverflow := FALSE;                                       // 饱和标志预置假 / preset the saturation flag false
iOut := DL_BQ_I0;                                         // 输出预置零 [Q15] / preset the output zero

// 段 2｜复位 / 失能闸：清全部历史并输出零（唯一复位路径）
IF xReset OR NOT xEnable THEN                             // 复位或失能 / reset asserted or disabled
    arrHist[DL_BQ_I0] := DL_BQ_I0;                        // z1 清零 [Q15] / clear z1
    arrHist[DL_BQ_I1] := DL_BQ_I0;                        // z2 清零 [Q15] / clear z2
    arrHist[DL_BQ_I2] := DL_BQ_I0;                        // 上拍输入清零 [Q15] / clear the previous input
    arrHist[DL_BQ_I3] := DL_BQ_I0;                        // 上拍输出清零 [Q15] / clear the previous output
    iOut := DL_BQ_I0;                                     // 输出零 [Q15] / output zero
    xOverflow := FALSE;                                   // 清饱和标志 [—] / clear the saturation flag
ELSE
    // 段 3｜y[n] = b0*x[n] + z1[n-1]（两项之和界内可证：|b0*x| <= 1.073e9，|z1*2^15| <= 1.073e9）
    diProd1 := INT_TO_DINT(arrCoef[DL_BQ_I0]) * INT_TO_DINT(iIn);          // b0*x [Q30] / b0 times x
    diProd2 := INT_TO_DINT(arrHist[DL_BQ_I0]) * DL_BQ_SC;                  // z1 左移 15 位 [Q30] / z1 scaled to Q30
    diAcc := diProd1 + diProd2;                                            // 两项求和 [Q30] / sum the two terms
    IF diAcc >= DL_BQ_Z THEN                                               // 非负做加偏置舍入 / non negative rounding
        diSh := (diAcc + DL_BQ_RND) / DL_BQ_SC;                            // 四舍五入右移 15 位 [Q15] / rounded shift right
    ELSE
        diSh := (diAcc - DL_BQ_RND) / DL_BQ_SC;                            // 负值做减偏置舍入 [Q15] / rounded shift right
    END_IF
    IF diSh > Q15_MAX THEN                                                 // 输出上越界 / the output exceeds the upper bound
        iSat := DINT_TO_INT(Q15_MAX);                                      // 饱和到 Q15_MAX [Q15] / saturate high
        xOverflow := TRUE;                                                 // 置饱和标志 [—] / raise the saturation flag
    ELSIF diSh < Q15_MIN THEN                                              // 输出下越界 / the output exceeds the lower bound
        iSat := DINT_TO_INT(Q15_MIN);                                      // 饱和到 Q15_MIN [Q15] / saturate low
        xOverflow := TRUE;                                                 // 置饱和标志 [—] / raise the saturation flag
    ELSE
        iSat := DINT_TO_INT(diSh);                                         // 界内直接转换 [Q15] / in range conversion
    END_IF
    iOut := iSat;                                                          // 本拍输出 [Q15] / the output of this scan

    // 段 4｜z1[n] = b1*x[n] - a1*y[n] + z2[n-1]（先算 Q30 两项差，再移位，再在 Q15 域饱和加 z2）
    diProd1 := INT_TO_DINT(arrCoef[DL_BQ_I1]) * INT_TO_DINT(iIn);          // b1*x [Q30] / b1 times x
    diProd2 := INT_TO_DINT(arrCoef[DL_BQ_I3]) * INT_TO_DINT(iSat);         // a1*y [Q30] / a1 times y
    diAcc := diProd1 - diProd2;                                            // 两项差（界内 |差| <= 2.147e9 可证） [Q30]
    IF diAcc >= DL_BQ_Z THEN                                               // 非负做加偏置舍入 / non negative rounding
        diSh := (diAcc + DL_BQ_RND) / DL_BQ_SC;                            // 四舍五入右移 15 位 [Q15] / rounded shift right
    ELSE
        diSh := (diAcc - DL_BQ_RND) / DL_BQ_SC;                            // 负值做减偏置舍入 [Q15] / rounded shift right
    END_IF
    diSum := diSh + INT_TO_DINT(arrHist[DL_BQ_I1]);                        // 加上 z2（|和| <= 98304 界内） [Q15] / add z2
    IF diSum > Q15_MAX THEN                                                // z1 上越界 / z1 exceeds the upper bound
        iNewZ1 := DINT_TO_INT(Q15_MAX);                                    // 饱和到 Q15_MAX [Q15] / saturate high
        xOverflow := TRUE;                                                 // 置饱和标志 [—] / raise the saturation flag
    ELSIF diSum < Q15_MIN THEN                                             // z1 下越界 / z1 exceeds the lower bound
        iNewZ1 := DINT_TO_INT(Q15_MIN);                                    // 饱和到 Q15_MIN [Q15] / saturate low
        xOverflow := TRUE;                                                 // 置饱和标志 [—] / raise the saturation flag
    ELSE
        iNewZ1 := DINT_TO_INT(diSum);                                      // 界内直接转换 [Q15] / in range conversion
    END_IF

    // 段 5｜z2[n] = b2*x[n] - a2*y[n]（同段 4 的判溢出 + 舍入 + 饱和口径）
    diProd1 := INT_TO_DINT(arrCoef[DL_BQ_I2]) * INT_TO_DINT(iIn);          // b2*x [Q30] / b2 times x
    diProd2 := INT_TO_DINT(arrCoef[DL_BQ_I4]) * INT_TO_DINT(iSat);         // a2*y [Q30] / a2 times y
    diAcc := diProd1 - diProd2;                                            // 两项差 [Q30] / the difference of the two terms
    IF diAcc >= DL_BQ_Z THEN                                               // 非负做加偏置舍入 / non negative rounding
        diSh := (diAcc + DL_BQ_RND) / DL_BQ_SC;                            // 四舍五入右移 15 位 [Q15] / rounded shift right
    ELSE
        diSh := (diAcc - DL_BQ_RND) / DL_BQ_SC;                            // 负值做减偏置舍入 [Q15] / rounded shift right
    END_IF
    IF diSh > Q15_MAX THEN                                                 // z2 上越界 / z2 exceeds the upper bound
        iNewZ2 := DINT_TO_INT(Q15_MAX);                                    // 饱和到 Q15_MAX [Q15] / saturate high
        xOverflow := TRUE;                                                 // 置饱和标志 [—] / raise the saturation flag
    ELSIF diSh < Q15_MIN THEN                                              // z2 下越界 / z2 exceeds the lower bound
        iNewZ2 := DINT_TO_INT(Q15_MIN);                                    // 饱和到 Q15_MIN [Q15] / saturate low
        xOverflow := TRUE;                                                 // 置饱和标志 [—] / raise the saturation flag
    ELSE
        iNewZ2 := DINT_TO_INT(diSh);                                       // 界内直接转换 [Q15] / in range conversion
    END_IF

    // 段 6｜状态统一提交（两段式：先算新值后写回，避免同拍读写串扰）
    arrHist[DL_BQ_I2] := iIn;                                             // 记录上拍输入 [Q15] / record the previous input
    arrHist[DL_BQ_I3] := iSat;                                            // 记录上拍输出 [Q15] / record the previous output
    arrHist[DL_BQ_I0] := iNewZ1;                                          // 提交新的 z1 [Q15] / commit z1
    arrHist[DL_BQ_I1] := iNewZ2;                                          // 提交新的 z2 [Q15] / commit z2
END_IF
END_FUNCTION_BLOCK
