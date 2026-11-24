// =====================================================================
// FC_DL_PipeFrictionLoss.st
// Darcy-Weisbach 管道压降纯函数（层流/过渡/湍流自动判别）
// Darcy-Weisbach pipe pressure drop pure function
// 码位: 16#0001_0485 ~ 16#0001_0489 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 3)
// =====================================================================
FUNCTION FC_DL_PipeFrictionLoss : BOOL
VAR_INPUT
    bEnable      : BOOL  := TRUE;       // 使能 / Enable
    fFlow_m3h    : REAL  := 0.0;        // 体积流量 ≥0 m³/h / Volumetric flow [m3/h]
    fDia_mm      : REAL  := 50.0;       // 内径 >0 mm / Inner diameter [mm]
    fLen_m       : REAL  := 10.0;       // 直管长度 ≥0 m / Straight length [m]
    fRough_mm    : REAL  := 0.05;       // 绝对粗糙度 ≥0 mm（不锈钢 0.05）/ Absolute roughness [mm]
    fRho_kgm3    : REAL  := 1000.0;     // 密度 >0 kg/m³ / Density [kg/m3]
    fMu_cP       : REAL  := 1.0;        // 动力粘度 >0 cP（水 20℃ 约 1.0）/ Dynamic viscosity [cP]
    fKMinor      : REAL  := 0.0;        // 局部阻力系数和 ≥0 / Minor loss coefficient sum [-]
    fDpMax_kPa   : REAL  := 1000.0;     // 压降量程上限 >0 kPa / Pressure drop full scale [kPa]
    fReLam       : REAL  := 2300.0;     // 层流临界雷诺数 / Laminar critical Re [-]
    fReTurb      : REAL  := 4000.0;     // 湍流起始雷诺数 / Turbulent onset Re [-]
END_VAR
VAR_OUTPUT
    fVel_ms      : REAL;                // 流速 m/s / Velocity [m/s]
    fRe          : REAL;                // 雷诺数 / Reynolds number [-]
    fLambda      : REAL;                // 沿程阻力系数 / Friction factor [-]
    fDp_kPa      : REAL;                // 总压降 kPa / Total pressure drop [kPa]
    bTransition  : BOOL;                // 处于过渡区 / In transition zone
    eErr         : UDINT;               // 错误码 / Error code
END_VAR
VAR
    fArea_m2     : REAL;                // 管道截面积 / Pipe cross-section area [m2]
    fVelSq       : REAL;                // 流速平方 / Velocity squared [(m/s)2]
    fReSafe      : REAL;                // 钳位后安全雷诺数 / Clamped safe Reynolds number [-]
    fLogArg      : REAL;                // log10 参数（钳下限 1E-6）/ log10 argument, clamped [-]
    fLog10Val    : REAL;                // log10 结果 / log10 value [-]
    fDpMaxSafe   : REAL;                // 兜底后量程上限 / Sanitized full scale [kPa]
    fLenSafe     : REAL;                // 长度处理值 / Sanitized length [m]
    bLenNeg      : BOOL;                // 长度负值标记 / Negative length flag
    bClamped     : BOOL;                // 压降钳制标记 / Drop clamped flag
    fDia_m       : REAL;                // 内径转米 / Diameter in meters [m]
    fMu_Pas      : REAL;                // 粘度转 Pa·s / Viscosity in Pa.s [Pa.s]
    fRePow       : REAL;                // Re^0.9 中间量 / Re^0.9 intermediate [-]
    fDpPct       : REAL;                // 直管+局部阻力总系数 / Total resistance factor [-]
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0001_0485 信息 正常计算完成
//   16#0001_0486 故障 fDia_mm ≤ 0 / fMu_cP ≤ 0 / fRho_kgm3 ≤ 0，或任一输入非有限
//   16#0001_0487 故障 fReLam ≤ 0 / fReTurb ≤ fReLam / fRough_mm < 0 / fKMinor < 0（组态错）
//   16#0001_0488 信息 过渡区（fReLam ≤ Re ≤ fReTurb）→ 按湍流式 + bTransition=TRUE；或压降超上限已钳制
//   16#0001_0489 信息 零流量（fFlow_m3h ≤ 0）→ 三项输出 0、bTransition=FALSE
// ---------------------------------------------------------------------

// 默认输出清零 / Default outputs cleared
fVel_ms     := 0.0;      // 流速清零 / Reset velocity
fRe         := 0.0;      // 雷诺数清零 / Reset Reynolds
fLambda     := 0.0;      // 阻力系数清零 / Reset lambda
fDp_kPa     := 0.0;      // 压降清零 / Reset pressure drop
bTransition := FALSE;    // 过渡区标志复位 / Reset transition flag
eErr        := 16#0001_0485;  // 预置正常码 / Preset normal code

IF NOT bEnable THEN
    // 使能关闭：输出保持 0，不置故障 / Disabled: outputs zero, no fault
    RETURN;   // 直接返回 / Return
END_IF

// ---- 非有限闸 / Finite guard ----
IF (fFlow_m3h <> fFlow_m3h) OR (ABS(fFlow_m3h) >= 1.0E12)
   OR (fDia_mm <> fDia_mm) OR (ABS(fDia_mm) >= 1.0E12)
   OR (fLen_m <> fLen_m) OR (ABS(fLen_m) >= 1.0E12)
   OR (fRough_mm <> fRough_mm) OR (ABS(fRough_mm) >= 1.0E12)
   OR (fRho_kgm3 <> fRho_kgm3) OR (ABS(fRho_kgm3) >= 1.0E12)
   OR (fMu_cP <> fMu_cP) OR (ABS(fMu_cP) >= 1.0E12)
   OR (fKMinor <> fKMinor) OR (ABS(fKMinor) >= 1.0E12)
   OR (fDpMax_kPa <> fDpMax_kPa) OR (ABS(fDpMax_kPa) >= 1.0E12)
   OR (fReLam <> fReLam) OR (ABS(fReLam) >= 1.0E12)
   OR (fReTurb <> fReTurb) OR (ABS(fReTurb) >= 1.0E12) THEN
    eErr := 16#0001_0486;  // 故障：非有限输入 / Fault: non-finite input
    RETURN;                // 输出保持 0 / Outputs stay zero
END_IF

// ---- 物性组态错闸 / Physical property configuration fault ----
IF (fDia_mm <= 0.0) OR (fMu_cP <= 0.0) OR (fRho_kgm3 <= 0.0) THEN
    eErr := 16#0001_0486;  // 故障：径/粘/密非法 / Fault: invalid dia/mu/rho
    RETURN;                // 三输出保持 0，不得抛除零 / Outputs stay zero
END_IF

// ---- 流域组态错闸 / Flow regime configuration fault ----
IF (fReLam <= 0.0) OR (fReTurb <= fReLam)
   OR (fRough_mm < 0.0) OR (fKMinor < 0.0) THEN
    eErr := 16#0001_0487;  // 故障：临界雷诺/粗糙度/局部系数非法 / Fault: invalid regime config
    RETURN;                // 输出保持 0 / Outputs stay zero
END_IF

// ---- 长度负值按 0 处理并置槽 3 / Negative length treated as zero with slot 3 ----
fLenSafe := fLen_m;        // 先原样采用 / Adopt as-is
bLenNeg  := FALSE;         // 标记复位 / Reset flag
IF fLen_m < 0.0 THEN
    fLenSafe := 0.0;       // 按 0 处理 / Treat as zero
    bLenNeg  := TRUE;      // 记录标记 / Mark flag
END_IF

// ---- 量程上限兜底（≤0 按 1000.0，不置错）/ Full-scale fallback ----
IF fDpMax_kPa <= 0.0 THEN
    fDpMaxSafe := 1000.0;  // 兜底 1000 kPa / Fallback 1000 kPa
ELSE
    fDpMaxSafe := fDpMax_kPa;  // 原值 / As-is
END_IF

// ---- 零流量短路路径 / Zero-flow short path ----
IF fFlow_m3h <= 0.0 THEN
    fVel_ms     := 0.0;         // 流速 0 / Zero velocity
    fRe         := 0.0;         // 雷诺数 0 / Zero Reynolds
    fLambda     := 0.0;         // 阻力系数 0 / Zero lambda
    fDp_kPa     := 0.0;         // 压降 0 / Zero drop
    bTransition := FALSE;       // 不在过渡区 / Not in transition
    eErr        := 16#0001_0489;  // 信息级：零流量 / Info: zero flow
    RETURN;                     // 直接返回 / Return
END_IF

// ---- 单位换算与流速 / Unit conversion and velocity ----
fDia_m := fDia_mm / 1000.0;              // mm → m / mm to m
fMu_Pas := fMu_cP / 1000.0;              // cP → Pa·s / cP to Pa.s
fArea_m2 := 3.14159265 * fDia_m * fDia_m / 4.0;  // 截面积 π·d²/4 / Cross-section area [m2]
fVel_ms := (fFlow_m3h / 3600.0) / fArea_m2;      // v = Q/(3600·A) / Velocity [m/s]
fVelSq  := fVel_ms * fVel_ms;                    // v² / Velocity squared

// ---- 雷诺数 Re = v·d·ρ/μ / Reynolds number ----
fRe := fVel_ms * fDia_m * fRho_kgm3 / fMu_Pas;   // 雷诺数 / Reynolds number [-]

// ---- Re 钳 1.0 防幂运算溢出（Re=0 时 5.74/Re^0.9 无定义）/ Clamp Re to 1.0 ----
IF fRe < 1.0 THEN
    fReSafe := 1.0;   // 钳下限 / Clamp minimum
ELSE
    fReSafe := fRe;   // 原值 / As-is
END_IF

// ---- 分流域计算 λ / Regime-based lambda ----
bTransition := FALSE;   // 过渡区标志复位 / Reset transition flag
IF fRe < fReLam THEN
    // 层流：λ = 64/Re（ReSafe ≥ 1.0 保证分母安全）/ Laminar
    fLambda := 64.0 / fReSafe;               // 层流阻力系数 / Laminar friction factor
ELSIF fRe <= fReTurb THEN
    // 过渡区：按湍流式算 + 信息级（不中断）/ Transition: turbulent formula + info
    bTransition := TRUE;                     // 标记过渡区 / Mark transition
    eErr        := 16#0001_0488;             // 信息级：过渡区 / Info: transition
    fRePow := EXPT(fReSafe, 0.9);            // Re^0.9 / Re to power 0.9
    fLogArg := (fRough_mm / (3.7 * fDia_mm)) + (5.74 / fRePow);  // Swamee-Jain 内项 / SJ argument
    IF fLogArg < 1.0E-6 THEN
        fLogArg := 1.0E-6;                   // 钳下限防 log10 奇点 / Clamp to avoid singularity
    END_IF
    fLog10Val := LOG(fLogArg) / 2.302585093; // 自然对数换底 log10 / Convert to log10
    IF ABS(fLog10Val) < 1.0E-9 THEN
        fLog10Val := 1.0E-9;                 // 防平方后除零 / Guard division
    END_IF
    fLambda := 0.25 / (fLog10Val * fLog10Val);  // 湍流式 λ / Turbulent friction factor
ELSE
    // 湍流：Swamee-Jain 显式式 / Turbulent: Swamee-Jain explicit
    fRePow := EXPT(fReSafe, 0.9);            // Re^0.9 / Re to power 0.9
    fLogArg := (fRough_mm / (3.7 * fDia_mm)) + (5.74 / fRePow);  // 内项 / SJ argument
    IF fLogArg < 1.0E-6 THEN
        fLogArg := 1.0E-6;                   // 钳下限 / Clamp minimum
    END_IF
    fLog10Val := LOG(fLogArg) / 2.302585093; // 换底 log10 / Convert to log10
    IF ABS(fLog10Val) < 1.0E-9 THEN
        fLog10Val := 1.0E-9;                 // 防除零 / Guard division
    END_IF
    fLambda := 0.25 / (fLog10Val * fLog10Val);  // λ / Friction factor
END_IF

// ---- 总压降 Δp = (λ·L/d + ΣK)·ρ·v²/2 / Total pressure drop ----
fDpPct := (fLambda * fLenSafe / fDia_m) + fKMinor;  // 总阻力系数 / Total resistance factor
fDp_kPa := (fDpPct * fRho_kgm3 * fVelSq / 2.0) / 1000.0;  // Pa → kPa / Pressure drop [kPa]

// ---- 量程钳制（信息级）/ Full-scale clamp (info level) ----
bClamped := FALSE;               // 钳制标记复位 / Reset clamp flag
IF fDp_kPa > fDpMaxSafe THEN
    fDp_kPa  := fDpMaxSafe;      // 钳到上限 / Clamp to full scale
    bClamped := TRUE;            // 记录钳制 / Mark clamped
END_IF

// ---- 信息级汇总：长度负值/钳制覆盖正常码 / Info aggregation ----
IF bLenNeg OR bClamped THEN
    eErr := 16#0001_0488;        // 信息：过渡区或钳制共用槽 4 / Info: transition or clamp slot
END_IF

// 正常完成，返回 TRUE / Normal completion
FC_DL_PipeFrictionLoss := TRUE;  // 函数返回值 / Function result

END_FUNCTION
