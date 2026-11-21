// =====================================================================
// FC_DL_CpkCalc.st
// 过程能力指数计算纯函数 (Cp/Cpu/Cpl/Cpk) SPC 自研 T2-8
// Process capability index calculation pure function
// 码位: 16#0001_0480 ~ 16#0001_0484 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 2)
// =====================================================================
FUNCTION FC_DL_CpkCalc : BOOL
VAR_INPUT
    bEnable      : BOOL   := TRUE;      // 使能 / Enable
    fMean        : REAL   := 0.0;       // 样本均值（工程单位）/ Sample mean [unit]
    fSigma       : REAL   := 0.0;       // 样本标准差 ≥0（同单位）/ Sample sigma [unit]
    fUsl         : REAL   := 100.0;     // 规格上限 / Upper spec limit [unit]
    fLsl         : REAL   := 0.0;       // 规格下限 / Lower spec limit [unit]
    uSampleCount : UDINT  := 0;         // 样本数 / Sample count
    uSampleMin   : UDINT  := 25;        // 最小样本数 5~1000 / Minimum sample count
    fSigmaMin    : REAL   := 1.0E-6;    // σ 下限 >0（退化判据）/ Sigma floor [unit]
    fCpkMin      : REAL   := 1.33;      // 合格门限 0.5~3.0 / Capability threshold [-]
END_VAR
VAR_OUTPUT
    fCp          : REAL;                // 潜在能力 / Potential capability [-]
    fCpu         : REAL;                // 上侧能力 / Upper capability [-]
    fCpl         : REAL;                // 下侧能力 / Lower capability [-]
    fCpk         : REAL;                // 实际能力 / Actual capability [-]
    bValid       : BOOL;                // 结论有效 / Result valid
    bCapable     : BOOL;                // 达门限 / Capable
    eErr         : UDINT;               // 错误码 / Error code
END_VAR
VAR
    fSigmaClamp  : REAL;                // 钳下限后的 σ / Clamped sigma [unit]
    fThreeSig    : REAL;                // 3σ 分母 / 3-sigma denominator [unit]
    fSixSig      : REAL;                // 6σ 分母 / 6-sigma denominator [unit]
    fCpkMinSafe  : REAL;                // 非有限兜底后的门限 / Sanitized threshold [-]
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0001_0480 信息 计算完成且结论有效
//   16#0001_0481 故障 fMean/fSigma/fUsl/fLsl 非有限，或 fSigma < 0
//   16#0001_0482 故障 fUsl ≤ fLsl（组态错），或 fSigmaMin ≤ 0
//   16#0001_0483 信息 退化：fSigma < fSigmaMin → Cp/Cpk 置 999.0 哨兵、bValid=FALSE
//   16#0001_0484 信息 样本不足：uSampleCount < uSampleMin → 输出全 0、bValid=FALSE
// ---------------------------------------------------------------------

// 默认输出清零 / Default outputs cleared
fCp      := 0.0;      // Cp 清零 / Reset Cp
fCpu     := 0.0;      // Cpu 清零 / Reset Cpu
fCpl     := 0.0;      // Cpl 清零 / Reset Cpl
fCpk     := 0.0;      // Cpk 清零 / Reset Cpk
bValid   := FALSE;    // 结论无效 / Invalid by default
bCapable := FALSE;    // 未达门限 / Not capable by default
eErr     := 16#0001_0480;  // 预置正常码 / Preset normal code

IF NOT bEnable THEN
    // 使能关闭：输出保持 0，不置故障 / Disabled: outputs zero, no fault
    RETURN;   // 直接返回 / Return
END_IF

// ---- 非有限闸 / Finite guard ----
IF (fMean <> fMean) OR (ABS(fMean) >= 1.0E12)
   OR (fSigma <> fSigma) OR (ABS(fSigma) >= 1.0E12)
   OR (fUsl <> fUsl) OR (ABS(fUsl) >= 1.0E12)
   OR (fLsl <> fLsl) OR (ABS(fLsl) >= 1.0E12) THEN
    eErr := 16#0001_0481;  // 故障：输入非有限 / Fault: non-finite input
    RETURN;                // 输出保持 0 / Outputs stay zero
END_IF

// ---- σ 负值判 / Negative sigma fault ----
IF fSigma < 0.0 THEN
    eErr := 16#0001_0481;  // 故障：σ < 0 / Fault: sigma negative
    RETURN;                // 输出保持 0 / Outputs stay zero
END_IF

// ---- 组态错闸 / Configuration fault ----
IF (fUsl <= fLsl) OR (fSigmaMin <= 0.0) THEN
    eErr := 16#0001_0482;  // 故障：规格区间或 σ 下限非法 / Fault: invalid spec or sigma floor
    RETURN;                // 输出保持 0 / Outputs stay zero
END_IF

// ---- 门限脏值兜底（不置错）/ Sanitize dirty threshold without fault ----
fCpkMinSafe := fCpkMin;                     // 先原样采用 / Adopt as-is first
IF (fCpkMin <> fCpkMin) OR (ABS(fCpkMin) >= 1.0E12) THEN
    fCpkMinSafe := 1.33;                    // 兜底 1.33 / Fallback 1.33
END_IF

// ---- 样本数不足 → 输出全 0 不给结论 / Insufficient samples ----
IF uSampleCount < uSampleMin THEN
    eErr := 16#0001_0484;  // 信息级：样本不足 / Info: insufficient samples
    RETURN;                // 输出保持 0，bValid=FALSE / Outputs zero, invalid
END_IF

// ---- 退化判：σ < σMin → 哨兵 999.0，不得报除零 / Degenerate sigma sentinel ----
IF fSigma < fSigmaMin THEN
    fCp    := 999.0;        // Cp 哨兵 / Cp sentinel
    fCpk   := 999.0;        // Cpk 哨兵 / Cpk sentinel
    bValid := FALSE;        // 结论无效 / Invalid
    eErr   := 16#0001_0483; // 信息级：退化 / Info: degenerate
    RETURN;                 // 直接返回 / Return
END_IF

// ---- 先钳 σ 下限再除，杜绝 3σ/6σ 除零热点 / Clamp sigma before division ----
IF fSigma < fSigmaMin THEN
    fSigmaClamp := fSigmaMin;   // 保险钳位（理论上不可达）/ Defensive clamp
ELSE
    fSigmaClamp := fSigma;      // 正常 σ / Normal sigma
END_IF
fThreeSig := 3.0 * fSigmaClamp; // 3σ 分母 / 3-sigma denominator
fSixSig   := 6.0 * fSigmaClamp; // 6σ 分母 / 6-sigma denominator

// ---- 四项能力指数 / Four capability indices ----
fCp  := (fUsl - fLsl) / fSixSig;   // Cp = (USL-LSL)/(6σ) / Potential capability
fCpu := (fUsl - fMean) / fThreeSig; // Cpu = (USL-μ)/(3σ) / Upper capability
fCpl := (fMean - fLsl) / fThreeSig; // Cpl = (μ-LSL)/(3σ) / Lower capability

// Cpk = MIN(Cpu, Cpl)，负值照实输出禁止钳零 / Cpk as-is, no clamping
IF fCpu <= fCpl THEN
    fCpk := fCpu;   // 取上侧较小值 / Take upper
ELSE
    fCpk := fCpl;   // 取下侧较小值 / Take lower
END_IF

// ---- 结论与达标判 / Validity and capability verdict ----
bValid   := TRUE;              // 结论有效 / Valid
bCapable := (fCpk >= fCpkMinSafe);  // 达门限判 / Threshold verdict

// 正常完成，返回 TRUE / Normal completion
FC_DL_CpkCalc := TRUE;         // 函数返回值 / Function result

END_FUNCTION
