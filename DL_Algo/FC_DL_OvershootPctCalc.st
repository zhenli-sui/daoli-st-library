// FC_DL_OvershootPctCalc v1.0.0
// 开源溯源：self-cleanroom / 回路 KPI 族
(*
  道莅工业代码库 | DL_Algo | FC_DL_OvershootPctCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 阶跃响应超调量百分比：σ% = (y_peak − y_final)/(y_final − y_init) × 100；
        稳态幅差分母域闸；单调响应（无超调）返回负值按 0 收口
  邻件关系: 与 FC_DL_SettleTimeCalc（本批 S23，整定时间）成对 —— 差异点：
            超调件算峰值越界幅度，整定件算进入容差带时刻，两件共享
            阶跃响应特征入参口径（yInit/yFinal），码位独立
*)
FUNCTION FC_DL_OvershootPctCalc : REAL
VAR_INPUT
    fYInit    : REAL := 0.0;    // 阶跃前稳态值 [工程单位] / Pre-step steady value
    fYFinal   : REAL := 0.0;    // 目标稳态值 [工程单位] / Target steady value
    fYPeak    : REAL := 0.0;    // 响应峰值 [工程单位] / Response peak value
    fEps      : REAL := 1.0E-6; // 幅差判零容差 [工程单位] / Amplitude tolerance
END_VAR
VAR_OUTPUT
    bValid    : BOOL;           // 结果有效回执 [-] / Result validity receipt
    uErrorId  : UDINT;          // 事件码，0 = 无事件；16#0002_2901 = 域外/矛盾拒收 / Event code
END_VAR
VAR
    fDenom    : REAL;           // 分母 = y_final − y_init [工程单位] / Denominator
    fOver     : REAL;           // 超调绝对量 [工程单位] / Overshoot amount
    fResult   : REAL;           // 结果中间量 [%] / Result intermediate
END_VAR

// —— 段 0：全路径缺省 —— //
bValid := FALSE;                // 有效回执预清 / Validity preset
uErrorId := 16#0000;            // 事件码预清 / Event code preset
fOver := 0.0;                   // 超调量预清 / Overshoot preset
fResult := 0.0;                 // 结果预清 / Result preset
FC_DL_OvershootPctCalc := 0.0;  // 返回值缺省零 / Return default zero

// —— 段 1：非有限闸 —— //
IF (fYInit <> fYInit) OR (fYFinal <> fYFinal) OR (fYPeak <> fYPeak)
   OR (ABS(fYInit) >= 3.0E38) OR (ABS(fYFinal) >= 3.0E38) OR (ABS(fYPeak) >= 3.0E38) THEN
    uErrorId := 16#0002_2901;   // 输入非有限拒收 / Non-finite reject
    RETURN;
END_IF

// —— 段 2：分母域闸（R4：除法前判分母） —— //
fDenom := fYFinal - fYInit;     // 稳态幅差 [工程单位] / Steady amplitude difference
IF ABS(fDenom) < fEps THEN      // 幅差近零：阶跃幅值无效 / Near-zero step amplitude
    uErrorId := 16#0002_2901;   // 信息级：分母为零 / Info level: zero denominator
    RETURN;                     // 不计算返回 / Return without computation
END_IF

// —— 段 3：主计算（峰值须高于终值的正向超调口径） —— //
IF fDenom > 0.0 THEN
    fOver := fYPeak - fYFinal;  // 正向阶跃：峰值超终值量 / Positive step overshoot
ELSE
    fOver := fYFinal - fYPeak;  // 负向阶跃：口径镜像 / Negative step mirrored
END_IF
IF fOver <= 0.0 THEN
    fResult := 0.0;             // 无超调（单调响应）：按零收口 / No overshoot: zero
ELSE
    fResult := fOver / fDenom * 100.0;   // σ% = 超调量/幅差 ×100（分母非零已过闸）/ Overshoot percent
END_IF
FC_DL_OvershootPctCalc := fResult;   // 返回值 = 超调百分比 / Return equals overshoot percent
bValid := TRUE;                 // 有效回执 / Validity receipt
END_FUNCTION
