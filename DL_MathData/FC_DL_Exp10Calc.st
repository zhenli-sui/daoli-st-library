// FC_DL_Exp10Calc v1.0.0
// 开源溯源：brOscatLib / URL https://github.com/iec-oscat-mirror / 许可证 MIT / 借鉴 EXP10 语义（域闸防溢出），clean-room 重写
(*
  道莅工业代码库 | DL_MathData | FC_DL_Exp10Calc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 10^x 计算（EXP(x·ln10) 实现，域闸防上溢/下溢），与 LogEx/LogBaseEx 成对
  邻件关系: 对数族 FC_DL_LogEx / FC_DL_LogBaseEx 的逆运算补口；同族口径统一
            用信息码 16#0002 段，本件子码 16#0002_1801（18xx 为指数域步进）
*)
FUNCTION FC_DL_Exp10Calc : REAL
VAR_INPUT
    fX : REAL := 0.0;    // 指数 [1]，结果 = 10^x / Exponent, result = 10^x
END_VAR
VAR_OUTPUT
    bValid   : BOOL;     // 结果有效回执 [-] / Result validity receipt
    uErrorId : UDINT;    // 事件码，0 = 无事件；16#0002_1801 = 指数域外 / Event code, 0 = none
END_VAR
VAR CONSTANT
    DL_X10_LN10   : REAL := 2.302585092994;   // ln(10) 常量 [1] / Natural log of 10
    DL_X10_XMAX   : REAL := 38.0;             // 上域闸：10^38 ≈ REAL 上限内 [1] / Upper domain gate near REAL max
    DL_X10_XMIN   : REAL := -38.0;            // 下域闸：10^(-38) 下溢阈值 [1] / Lower domain gate near underflow
END_VAR

// —— 段 0：全路径缺省 —— //
bValid   := FALSE;                                // 有效回执预清 / Validity preset
uErrorId := 16#0000;                              // 事件码预清 / Event code preset
FC_DL_Exp10Calc := 0.0;                           // 返回值缺省零 / Return default zero

// —— 段 1：非有限与域闸 —— //
IF fX <> fX THEN                                  // NaN 自反判 / NaN self-reflexive test
    uErrorId := 16#0002_1801;                     // 指数非法（信息级，不置 bError） / Invalid exponent, info level
    RETURN;                                       // 返回零 / Return zero
END_IF
IF fX >= 3.0E38 THEN                              // 近 Inf 指数闸 / Near-Inf exponent gate
    uErrorId := 16#0002_1801;                     // 指数非法 / Invalid exponent
    RETURN;                                       // 返回零 / Return zero
END_IF
IF fX > DL_X10_XMAX THEN                          // 上溢域闸：结果将超 REAL 可表范围 / Overflow gate beyond REAL range
    uErrorId := 16#0002_1801;                     // 信息级：域外照安全侧返回零 / Info level: out of domain, safe zero
    RETURN;
END_IF
IF fX < DL_X10_XMIN THEN                          // 下溢域闸：结果小于 REAL 最小正规数 / Underflow gate
    FC_DL_Exp10Calc := 0.0;                       // 下溢按零返回（合法确定值） / Underflow returns deterministic zero
    bValid := TRUE;                               // 视为有效（下溢不发散） / Valid (no divergence)
    RETURN;
END_IF

// —— 段 2：主计算（EXP(x·ln10) = 10^x） —— //
FC_DL_Exp10Calc := EXP(fX * DL_X10_LN10);         // 10^x = e^(x·ln10) / 10^x via natural exponential
bValid := TRUE;                                   // 有效回执 / Validity receipt
END_FUNCTION
