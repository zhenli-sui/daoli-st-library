(*
 * FC_DL_TobaccoComponentRatioCalc | C1 | DL_Process
 * 功能：叶丝/梗丝/膨胀丝三组分掺配比例求和、平衡判定与主组分识别       单位：比例 [%]、主组分为序号 1/2/3
 * 工况边界：三比例须均为有限且 ≥0；任一为负即判 9501 并置 xValid=FALSE（所有出口取安全值）；平衡判据为 Σ=100±0.1 %，浮点比较用容差而非相等
 * 代数值回代：70.0 / 20.0 / 10.0 → Σ=100.0、|Σ−100|=0 ≤0.1 → xBalanced=TRUE、nDominant=1（叶丝）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_TobaccoComponentRatioCalc : BOOL
VAR_INPUT
    rLeafCutPct  : REAL;             // 叶丝比例 | leaf cut tobacco ratio [%]
    rStemCutPct  : REAL;             // 梗丝比例 | stem cut tobacco ratio [%]
    rExpandedPct : REAL;             // 膨胀丝比例 | expanded tobacco ratio [%]
END_VAR
VAR_OUTPUT
    rSumPct     : REAL;              // 三组分之和 | sum of the three components [%]
    xBalanced   : BOOL;              // 配比平衡（Σ=100±0.1）| ratio balanced within 100 ± 0.1 [%]
    nDominant   : INT;               // 主组分：1=叶丝 / 2=梗丝 / 3=膨胀丝 | dominant component index
    xValid      : BOOL;              // 输出有效 | outputs valid
    nFaultCode  : INT;               // 0=无 / 9501=组分比例非法 | 0 none, 9501 illegal component ratio
END_VAR
VAR
    xFinA : BOOL;                    // 叶丝比例有限性 | leaf ratio is finite
    xFinB : BOOL;                    // 梗丝比例有限性 | stem ratio is finite
    xFinC : BOOL;                    // 膨胀丝比例有限性 | expanded ratio is finite
END_VAR
VAR CONSTANT
    DL_TCR_TOTAL : REAL := 100.0;    // 配比总和基准 | total ratio reference [%]
    DL_TCR_TOL   : REAL := 0.1;      // 平衡容差 | balance tolerance [%]
    DL_TCR_EPS   : REAL := 1.0E-6;   // 浮点比较容差 | floating comparison tolerance [%]
END_VAR

// 段1｜非有限闸（R19）
xFinA := (rLeafCutPct = rLeafCutPct) AND ((rLeafCutPct - rLeafCutPct) = 0.0);
xFinB := (rStemCutPct = rStemCutPct) AND ((rStemCutPct - rStemCutPct) = 0.0);
xFinC := (rExpandedPct = rExpandedPct) AND ((rExpandedPct - rExpandedPct) = 0.0);
IF (NOT xFinA) OR (NOT xFinB) OR (NOT xFinC) THEN
    rSumPct := 0.0;                  // 安全值：和 0 | safe value, zero sum
    xBalanced := FALSE;
    nDominant := 0;
    xValid := FALSE;
    nFaultCode := 9501;
    FC_DL_TobaccoComponentRatioCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：任一比例为负即判非法
IF (rLeafCutPct < 0.0) OR (rStemCutPct < 0.0) OR (rExpandedPct < 0.0) THEN
    rSumPct := 0.0;
    xBalanced := FALSE;
    nDominant := 0;
    xValid := FALSE;
    nFaultCode := 9501;
    FC_DL_TobaccoComponentRatioCalc := FALSE;
    RETURN;
END_IF

// 段3｜求和与平衡判定
rSumPct := rLeafCutPct + rStemCutPct + rExpandedPct;
xBalanced := ABS(rSumPct - DL_TCR_TOTAL) <= (DL_TCR_TOL + DL_TCR_EPS);

// 段4｜主组分识别（严格大于，等值时按叶丝优先，避免不确定主组分）
nDominant := 1;
IF (rStemCutPct > rLeafCutPct) AND (rStemCutPct >= rExpandedPct) THEN
    nDominant := 2;
ELSIF (rExpandedPct > rLeafCutPct) AND (rExpandedPct > rStemCutPct) THEN
    nDominant := 3;
END_IF

// 段5｜出口
nFaultCode := 0;
xValid := TRUE;
FC_DL_TobaccoComponentRatioCalc := TRUE;
END_FUNCTION
