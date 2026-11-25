(*
  FC_DL_Q15MulSat —— Q15 乘 Q15 得 Q15，中间 DINT 防溢出，含右移舍入
  分类：DL_Base | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：Q15 × Q15 得 Q30（DINT 承载），加半偏置后除 32768 得 Q15，结果按 Q15 上下界饱和。
  契约：输入 iA / iB 为 Q15 操作数；返回 Q15 积；xSat 报告饱和（信息级）。
  边界：① 舍入偏置前先做「极限值反算」防 DINT 溢出；② 用乘 32768 表达定标，规避 SHL 方言差异；
        ③ 无除法风险（除数恒为常量 32768 非零）；零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_Q15MulSat : INT
VAR_INPUT
    iA : INT := 0;                    // 乘数 A [Q15] / The multiplier A in Q15
    iB : INT := 0;                    // 乘数 B [Q15] / The multiplier B in Q15
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 饱和发生标志（信息级） [—] / The saturation flag, informational
END_VAR
VAR
    diProd : DINT;                    // 乘积（Q30） [Q30] / The product in Q30
    diQ : DINT;                       // 舍入右移后的 Q15 暂存 [Q15] / The rounded Q15 stage
END_VAR
VAR CONSTANT
    Q15_MAX   : DINT := 32767;        // Q15 上界 [-] / The Q15 upper bound
    Q15_MIN   : DINT := -32768;       // Q15 下界 [-] / The Q15 lower bound
    DL_QM_RND : DINT := 16384;        // 四舍五入偏置（2^14） [-] / The rounding bias
    DL_QM_SC  : DINT := 32768;        // 定标因子（2^15） [-] / The Q15 scaling factor
    DL_QM_HI  : DINT := 2147483647;   // DINT 上限（反算用） [-] / The DINT maximum
    DL_QM_LO  : DINT := -2147483647;  // DINT 下限近似（偏置在界侧相加，避下溢） [-] / The DINT minimum approximation
    DL_QM_Z   : DINT := 0;            // 整型零常量 [-] / The integer zero constant
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
diProd := INT_TO_DINT(iA) * INT_TO_DINT(iB);          // Q15 乘 Q15 得 Q30（|积| <= 1.074e9 界内） / Q15 times Q15
IF diProd > (DL_QM_HI - DL_QM_RND) THEN               // 加偏置前上界反算防溢出 / upper bound reverse check before rounding
    FC_DL_Q15MulSat := DINT_TO_INT(Q15_MAX);          // 直接饱和到上界 [Q15] / saturate high
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSIF diProd < (DL_QM_LO + DL_QM_RND) THEN            // 加偏置前下界反算防溢出（偏置加在界侧，避 DINT 下溢） / lower bound reverse check
    FC_DL_Q15MulSat := DINT_TO_INT(Q15_MIN);          // 直接饱和到下界 [Q15] / saturate low
    xSat := TRUE;                                     // 置饱和标志 [—] / raise the saturation flag
ELSE
    IF diProd >= DL_QM_Z THEN                         // 非负做加偏置舍入 / non negative rounding
        diQ := (diProd + DL_QM_RND) / DL_QM_SC;       // 四舍五入右移 15 位 [Q15] / rounded shift right
    ELSE
        diQ := (diProd - DL_QM_RND) / DL_QM_SC;       // 负值做减偏置舍入 [Q15] / rounded shift right
    END_IF
    IF diQ > Q15_MAX THEN                             // 上越界 / above the upper bound
        FC_DL_Q15MulSat := DINT_TO_INT(Q15_MAX);      // 饱和到 Q15_MAX [Q15] / saturate high
        xSat := TRUE;                                 // 置饱和标志 [—] / raise the saturation flag
    ELSIF diQ < Q15_MIN THEN                          // 下越界 / below the lower bound
        FC_DL_Q15MulSat := DINT_TO_INT(Q15_MIN);      // 饱和到 Q15_MIN [Q15] / saturate low
        xSat := TRUE;                                 // 置饱和标志 [—] / raise the saturation flag
    ELSE
        FC_DL_Q15MulSat := DINT_TO_INT(diQ);          // 界内直接转换 [Q15] / in range conversion
    END_IF
END_IF
END_FUNCTION
