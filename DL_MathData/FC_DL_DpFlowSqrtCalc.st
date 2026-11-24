// =====================================================================
// FC_DL_DpFlowSqrtCalc.st
// 差压式气体流量换算纯函数 (原名 FC_DL_GasFlowSqrt 因 R148 撞名改为本名)
// Differential-pressure gas flow conversion pure function
// 码位: 16#0001_047B ~ 16#0001_047F (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 1)
// =====================================================================
FUNCTION FC_DL_DpFlowSqrtCalc : BOOL
VAR_INPUT
    bEnable         : BOOL  := TRUE;      // 使能，FALSE 时输出全 0 / Enable, outputs forced to zero when FALSE
    fDp_Pa          : REAL  := 0.0;       // 实测差压 0~250000 Pa / Measured differential pressure [Pa]
    fKFactor        : REAL  := 1.0;       // 流量系数 0.001~100（含管道/孔板系数）/ Flow coefficient [-]
    fRhoRef_kgm3    : REAL  := 1.2041;    // 参比密度 >0 kg/m³ / Reference density [kg/m3]
    fTRef_C         : REAL  := 20.0;      // 参比温度 -50~200 ℃ / Reference temperature [degC]
    fTNow_C         : REAL  := 20.0;      // 当前温度 -50~200 ℃ / Actual temperature [degC]
    fPRef_kPa       : REAL  := 101.325;   // 参比绝压 >0 kPa / Reference absolute pressure [kPa]
    fPNow_kPa       : REAL  := 101.325;   // 当前绝压 >0 kPa / Actual absolute pressure [kPa]
    fDpMin_Pa       : REAL  := 50.0;      // 开方死区 0~5000 Pa / Square-root dead band [Pa]
    fFlowMax_m3h    : REAL  := 100000.0;  // 量程上限 >0 m³/h / Full-scale flow [m3/h]
END_VAR
VAR_OUTPUT
    fFlow_m3h       : REAL;               // 工况流量 / Actual flow [m3/h]
    fFlowRef_m3h    : REAL;               // 参比工况流量 / Reference flow [m3/h]
    bLowCut         : BOOL;               // 死区截断生效 / Dead-band cut active
    eErr            : UDINT;              // 错误码 / Error code
END_VAR
VAR
    fComp           : REAL;               // 温压补偿因子 sqrt((P/Pref)*(Tref/T)) / Compensation factor [-]
    fTKelvin        : REAL;               // 当前绝对温度（钳下限 1.0 K）/ Actual absolute temperature, clamped [K]
    fTRefKelvin     : REAL;               // 参比绝对温度（钳下限 1.0 K）/ Reference absolute temperature, clamped [K]
    fRhoRatio       : REAL;               // 密度比值 rhoNow/rhoRef / Density ratio [-]
    fRhoNow         : REAL;               // 工况密度估算值 / Estimated actual density [kg/m3]
    fFlowRaw        : REAL;               // 钳制前原始流量 / Raw flow before clamp [m3/h]
    bClamped        : BOOL;               // 量程钳制标志 / Flow clamped to full-scale
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0001_047B 信息 正常换算完成
//   16#0001_047C 故障 差压 < 0 或任一输入非有限
//   16#0001_047D 故障 参比密度/绝压/温度非法（≤0 或 ≤ -273.15）
//   16#0001_047E 信息 结果超量程已钳制 或 差压落在死区（bLowCut 同拍 TRUE）
//   16#0001_047F 故障 fKFactor ≤ 0 或 fFlowMax_m3h ≤ 0（组态错）
// ---------------------------------------------------------------------

// 默认输出（先清零，故障路径直接返回）
fFlow_m3h    := 0.0;    // 工况流量清零 / Reset actual flow
fFlowRef_m3h := 0.0;    // 参比流量清零 / Reset reference flow
bLowCut      := FALSE;  // 死区标志复位 / Reset dead-band flag
eErr         := 16#0001_047B;  // 预置正常码 / Preset normal code

IF NOT bEnable THEN
    // 使能关闭：输出保持全 0，不置故障级 / Disabled: outputs zero, no fault
    RETURN;  // 直接返回 / Return
END_IF

// ---- 非有限闸（NaN 自反判 + Inf 幅值判，等价 bIsFinite）/ Finite guard ----
IF (fDp_Pa <> fDp_Pa) OR (ABS(fDp_Pa) >= 1.0E12)
   OR (fKFactor <> fKFactor) OR (ABS(fKFactor) >= 1.0E12)
   OR (fRhoRef_kgm3 <> fRhoRef_kgm3) OR (ABS(fRhoRef_kgm3) >= 1.0E12)
   OR (fTRef_C <> fTRef_C) OR (ABS(fTRef_C) >= 1.0E12)
   OR (fTNow_C <> fTNow_C) OR (ABS(fTNow_C) >= 1.0E12)
   OR (fPRef_kPa <> fPRef_kPa) OR (ABS(fPRef_kPa) >= 1.0E12)
   OR (fPNow_kPa <> fPNow_kPa) OR (ABS(fPNow_kPa) >= 1.0E12)
   OR (fDpMin_Pa <> fDpMin_Pa) OR (ABS(fDpMin_Pa) >= 1.0E12)
   OR (fFlowMax_m3h <> fFlowMax_m3h) OR (ABS(fFlowMax_m3h) >= 1.0E12) THEN
    fFlow_m3h    := 0.0;             // 输出走安全侧 / Safe-side output
    fFlowRef_m3h := 0.0;             // 参比输出清零 / Reset reference flow
    eErr         := 16#0001_047C;    // 故障：非有限输入 / Fault: non-finite input
    RETURN;                          // 纯函数不驻留 / Pure function returns
END_IF

// ---- 反接判：差压 < 0 → 故障级，不得取绝对值照算 / Reversed wiring fault ----
IF fDp_Pa < 0.0 THEN
    fFlow_m3h    := 0.0;             // 输出 0 / Zero output
    fFlowRef_m3h := 0.0;             // 参比输出 0 / Zero reference output
    eErr         := 16#0001_047C;    // 故障：差压反接 / Fault: negative dp
    RETURN;                          // 直接返回 / Return
END_IF

// ---- 组态错闸：流量系数与量程 / Configuration fault: K and full scale ----
IF (fKFactor <= 0.0) OR (fFlowMax_m3h <= 0.0) THEN
    fFlow_m3h    := 0.0;             // 输出 0 / Zero output
    fFlowRef_m3h := 0.0;             // 参比输出 0 / Zero reference output
    eErr         := 16#0001_047F;    // 故障：组态错 / Fault: config error
    RETURN;                          // 直接返回 / Return
END_IF

// ---- 参比物性组态错闸 / Reference property configuration fault ----
IF (fRhoRef_kgm3 <= 0.0) OR (fPRef_kPa <= 0.0)
   OR (fTRef_C <= -273.15) OR (fTNow_C <= -273.15) THEN
    fFlow_m3h    := 0.0;             // 输出 0（无状态，不沿用上次值）/ Zero output, no state hold
    fFlowRef_m3h := 0.0;             // 参比输出 0 / Zero reference output
    eErr         := 16#0001_047D;    // 故障：参比物性非法 / Fault: invalid reference property
    RETURN;                          // 直接返回 / Return
END_IF

// ---- 死区判（判在开方前）/ Dead band check before square root ----
IF fDp_Pa <= fDpMin_Pa THEN
    fFlow_m3h    := 0.0;             // 噪声死区截断 / Dead-band cut
    fFlowRef_m3h := 0.0;             // 参比流量同步截断 / Reference flow cut
    bLowCut      := TRUE;            // 截断标志 / Cut active
    eErr         := 16#0001_047E;    // 信息级：死区 / Info: dead band
    RETURN;                          // 直接返回 / Return
END_IF

// ---- 温度转绝对温标，钳下限 1.0 K 防除零 / Convert to K, clamp 1.0 K ----
IF fTNow_C > -272.15 THEN
    fTKelvin := fTNow_C + 273.15;    // 当前温度转 K / Actual temperature to K
ELSE
    fTKelvin := 1.0;                 // 钳下限防除零 / Clamp to 1.0 K
END_IF
IF fTRef_C > -272.15 THEN
    fTRefKelvin := fTRef_C + 273.15; // 参比温度转 K / Reference temperature to K
ELSE
    fTRefKelvin := 1.0;              // 钳下限防除零 / Clamp to 1.0 K
END_IF

// ---- 温压补偿因子 sqrt((P/Pref)*(Tref/T)) / Compensation factor ----
fComp := SQRT((fPNow_kPa / fPRef_kPa) * (fTRefKelvin / fTKelvin));  // 补偿因子 / Compensation factor

// ---- 差压开方 × 流量系数 × 补偿因子 / Square root × K × compensation ----
fFlowRaw := fKFactor * SQRT(fDp_Pa) * fComp;  // 原始工况流量 / Raw actual flow [m3/h]

// ---- 量程钳制（信息级）/ Full-scale clamp (info level) ----
bClamped := FALSE;                       // 钳制标志复位 / Reset clamp flag
IF fFlowRaw > fFlowMax_m3h THEN
    fFlowRaw  := fFlowMax_m3h;           // 钳到量程上限 / Clamp to full scale
    bClamped  := TRUE;                   // 记录钳制 / Mark clamped
END_IF
fFlow_m3h := fFlowRaw;                   // 输出工况流量 / Output actual flow

// ---- 参比流量：fFlow × sqrt(rhoNow/rhoRef) / Reference flow via density ratio ----
fRhoNow := fRhoRef_kgm3 * fComp * fComp; // 由补偿因子反推工况密度 / Actual density from compensation
IF fRhoNow > 0.0 THEN
    fRhoRatio    := fRhoNow / fRhoRef_kgm3;  // 密度比值 / Density ratio [-]
    fFlowRef_m3h := fFlow_m3h * SQRT(fRhoRatio);  // 参比流量 / Reference flow [m3/h]
    IF fFlowRef_m3h > fFlowMax_m3h THEN
        fFlowRef_m3h := fFlowMax_m3h;    // 参比流量同步钳制 / Clamp reference flow
    END_IF
ELSE
    fFlowRef_m3h := fFlow_m3h;           // rhoNow 非法 → 直接复制 / Copy actual flow
    eErr         := 16#0001_047C;        // 槽 2 故障 / Slot 2 fault
    RETURN;                              // 直接返回 / Return
END_IF

// ---- 信息级汇总：钳制优先于正常码 / Info-level aggregation: clamp first ----
IF bClamped THEN
    eErr := 16#0001_047E;                // 信息：超量程钳制 / Info: clamped
END_IF

// 正常完成，返回 TRUE / Normal completion
FC_DL_DpFlowSqrtCalc := TRUE;            // 函数返回值 / Function result

END_FUNCTION
