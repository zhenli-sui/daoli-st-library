// FC_DL_PowerFactorCalc v1.0.0
// 开源溯源：self-cleanroom / 公开公式（功率因数 = 有功/视在）
(*
  道莅工业代码库 | DL_MathData | FC_DL_PowerFactorCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 功率因数计算 pf = P/S（有功/视在比），分母防零 + 领前/滞后判别；
        |pf| > 1 判测量矛盾拒收（物理不可能，疑 CT/PT 接线错误）
  邻件关系: 电能质量族 ThdCalc / HarmonicSpectrumBin（谐波畸变与频谱）——
            差异点：本件为基波功率三角比（cos φ 语义），与谐波族互不重叠
*)
FUNCTION FC_DL_PowerFactorCalc : REAL
VAR_INPUT
    fActiveKW   : REAL := 0.0;   // 有功功率 P [kW]，正=滞后感性 / Active power P [kW], positive = lagging
    fApparentKVA: REAL := 0.0;   // 视在功率 S [kVA]，域 > 0 / Apparent power S [kVA], domain > 0
    fEps        : REAL := 1.0E-6;// 判零容差 [kVA] / Zero tolerance [kVA]
END_VAR
VAR_OUTPUT
    bValid    : BOOL;            // 结果有效回执 [-] / Result validity receipt
    bLeading  : BOOL;            // 领前标志（有功为负即容性领前）[-] / Leading flag (negative P)
    uErrorId  : UDINT;           // 事件码，0 = 无事件；16#0002_1E01 = 视在为零；16#0002_1E02 = |pf|>1 矛盾 / Event code
END_VAR

// —— 段 0：全路径缺省 —— //
bValid   := FALSE;               // 有效回执预清 / Validity preset
bLeading := FALSE;               // 领前标志预清 / Leading preset
uErrorId := 16#0000;             // 事件码预清 / Event code preset
FC_DL_PowerFactorCalc := 0.0;    // 返回值缺省零 / Return default zero

// —— 段 1：非有限闸 —— //
IF (fActiveKW <> fActiveKW) OR (fApparentKVA <> fApparentKVA)
   OR (ABS(fActiveKW) >= 3.0E38) OR (ABS(fApparentKVA) >= 3.0E38) THEN
    uErrorId := 16#0002_1E01;    // 输入非有限：拒收（与视在为零共用域闸码段）/ Non-finite input: reject
    RETURN;
END_IF

// —— 段 2：分母防零闸（R4：除法前判分母） —— //
IF ABS(fApparentKVA) < fEps THEN // 视在功率近零：无法求比 / Apparent near zero: ratio undefined
    uErrorId := 16#0002_1E01;    // 信息级：分母为零 / Info level: zero denominator
    RETURN;                      // 返回零，不除 / Return zero without division
END_IF

// —— 段 3：主计算与物理矛盾闸 —— //
FC_DL_PowerFactorCalc := fActiveKW / fApparentKVA;   // pf = P/S（分母已过闸）/ pf = P/S, denominator gated
bLeading := (fActiveKW < 0.0);   // 有功为负：容性领前 / Negative P: capacitive leading
IF ABS(FC_DL_PowerFactorCalc) > 1.0 + fEps THEN      // |pf| > 1：测量矛盾 / |pf| > 1: measurement contradiction
    uErrorId := 16#0002_1E02;    // 信息级：功率三角矛盾（疑接线错误）/ Info level: power triangle contradiction
    FC_DL_PowerFactorCalc := 0.0;                    // 矛盾值不外发，返回零 / Contradictory value suppressed
    RETURN;
END_IF
bValid := TRUE;                  // 有效回执 / Validity receipt
END_FUNCTION
