// FC_DL_Median3Vote v1.0.0
(*==============================================================================
 * 功能描述: 三取二中值表决。三输入排序取中值输出；极差 (max-min) 超 fSpreadThr
 *           置 bSpread 诊断（输入分歧大，表决可信度降级）；任一输入非有限 →
 *           bValid=FALSE 并返回 0。
 * 接口契约: 输入 fA/fB/fC/fSpreadThr；输出 bValid/bSpread，返回中值。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

FUNCTION FC_DL_Median3Vote : REAL
VAR_INPUT
    fA         : REAL := 0.0;   // 表决输入 A [工程单位] / Vote input A
    fB         : REAL := 0.0;   // 表决输入 B [工程单位] / Vote input B
    fC         : REAL := 0.0;   // 表决输入 C [工程单位] / Vote input C
    fSpreadThr : REAL := 1.0;   // 极差诊断阈值，域 > 0 [工程单位] / Spread diagnosis threshold
END_VAR
VAR_OUTPUT
    bValid  : BOOL;             // 结果有效回执 [-] / Result validity receipt
    bSpread : BOOL;             // 极差超阈诊断标志 [-] / Spread over threshold flag
END_VAR
VAR
    fMax : REAL;                // 三输入最大值 [工程单位] / Maximum of the three
    fMin : REAL;                // 三输入最小值 [工程单位] / Minimum of the three
END_VAR

(* —— 段 0：全路径赋值缺省（无效安全侧） —— *)
bValid := FALSE;                             // 有效回执预清 / Validity preset
bSpread := FALSE;                            // 分歧诊断预清 / Spread preset
FC_DL_Median3Vote := 0.0;                    // 返回值缺省零 / Result default zero

(* —— 段 1：非有限闸（任一 NaN 即表决失效） —— *)
IF (fA <> fA) OR (fB <> fB) OR (fC <> fC) THEN   // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF

(* —— 段 2：极值派生与中值合成（中值 = 和 - 最大 - 最小，三值和幅值受输入域约束） —— *)
fMax := MAX(MAX(fA, fB), fC);                // 三输入最大值 / Maximum of the three
fMin := MIN(MIN(fA, fB), fC);                // 三输入最小值 / Minimum of the three
IF ABS(fMax) >= 1.0E38 THEN                  // 近 Inf 幅值闸 / Near-Inf magnitude gate
    RETURN;                                  // 无效返回零 / Invalid, return zero
END_IF
FC_DL_Median3Vote := (fA + fB + fC) - fMax - fMin;   // 中值合成（三值代数恒等式） / Median by algebraic identity
bValid := TRUE;                              // 有效回执 / Validity receipt
IF fSpreadThr > 0.0 THEN                     // 阈值正值闸（R4 防无效比较域） / Threshold positive gate
    bSpread := (fMax - fMin) > fSpreadThr;   // 极差超阈诊断 / Spread over threshold diagnosis
END_IF

END_FUNCTION
