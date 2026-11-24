// =====================================================================
// FB_DL_DryingOvenZone.st
// 烘箱 8 温区串级控温（比例 + 风量前馈 + 速率限幅 + 独立超温联锁）
// Drying oven 8-zone cascade temperature control FB
// 码位: 16#0002_371F ~ 16#0002_3723 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 5)
// =====================================================================
FUNCTION_BLOCK FB_DL_DryingOvenZone
VAR_INPUT
    bEnable         : BOOL  := FALSE;   // 使能 / Enable
    bReset          : BOOL  := FALSE;   // 复位 / Reset
    abZoneEnable    : ARRAY[1..8] OF BOOL;      // 8 区独立使能 / Per-zone enable
    afPv_C          : ARRAY[1..8] OF REAL;      // 8 区实测温度 -20~300 ℃ / Zone PV [degC]
    afSp_C          : ARRAY[1..8] OF REAL;      // 8 区设定温度 0~250 ℃ / Zone SP [degC]
    afKp            : ARRAY[1..8] OF REAL;      // 8 区比例增益 0.1~20 %/K / Zone gain [%/K]
    fFanPct         : REAL  := 0.0;     // 循环风量 0~100 % / Fan duty [%]
    fKff            : REAL  := 0.0;     // 风量前馈系数 0~1 %/% / Fan feedforward [%/%]
    fOvertemp_C     : REAL  := 260.0;   // 超温阈值 50~300 ℃ / Overtemperature limit [degC]
    fRateMax_pct_s  : REAL  := 5.0;     // 输出速率上限 >0 %/s / Output slew limit [%/s]
    bFanRun         : BOOL  := FALSE;   // 风机运行反馈 / Fan running
    tCycle          : TIME  := T#100MS; // 周期 T#10MS~T#2S / Cycle [s]
END_VAR
VAR_OUTPUT
    afOut_pct       : ARRAY[1..8] OF REAL;      // 8 区加热输出 0~100 % / Heater output [%]
    bOvertemp       : BOOL;             // 任一区超温（锁存）/ Any zone overtemp, latched
    uOvertempZone   : USINT;            // 首个超温区号 0=无 / First overtemp zone, 0=none
    bReady          : BOOL;             // 全部区进入带内 / All zones in band
    eState          : E_DL_OvenState;   // 状态 / State
    eErr            : UDINT;            // 错误码 / Error code
END_VAR
VAR
    uIdx            : UDINT;            // 区循环下标 / Zone loop index
    uZi             : INT;              // 1..8 数组下标 / Array subscript 1..8
    uZj2            : INT;              // 清零循环第二下标 / Second subscript for zero loops
    fDevK           : REAL;             // 区偏差 K / Zone deviation [K]
    fSpSafe         : REAL;             // 处理后设定（≤0 按 1 ℃）/ Sanitized SP [degC]
    fOutRaw         : REAL;             // 计算原始输出 / Raw computed output [%]
    fStepMax        : REAL;             // 单拍步长 / Max step per cycle [%]
    fStep           : REAL;             // 本拍实际步长 / Actual step this cycle [%]
    tCycleS         : REAL;             // 周期秒值（钳 ≥0.01）/ Cycle in seconds, clamped [s]
    bAllEnabled     : BOOL;             // 是否存在使能区 / Any zone enabled
    bFanBad         : BOOL;             // 风量非有限标记 / Fan duty non-finite flag
    fFanPctSafe     : REAL;             // 处理后风量 / Sanitized fan duty [%]
    bAnyOver        : BOOL;             // 本拍超温探测 / Overtemp detected this cycle
    uFirstOver      : USINT;            // 本拍首个超温区 / First overtemp zone this cycle
    xFirstScan      : BOOL := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0002_371F 信息 正常运行
//   16#0002_3720 故障 任一 afPv_C/afSp_C 非有限，或 tCycle 非法
//   16#0002_3721 故障 fOvertemp_C ≤ 0 / fRateMax_pct_s ≤ 0 / 任一 afKp ≤ 0（组态错）
//   16#0002_3722 信息 bFanRun=FALSE → 前馈禁用（fKff 项按 0 计），调节继续
//   16#0002_3723 故障 任一区 afPv_C ≥ fOvertemp_C → 全输出清零、锁存，解除=bReset 且全部 PV < 阈值-5K
// ---------------------------------------------------------------------

// ---- 周期转秒并钳下限 / Cycle to seconds with clamp ----
tCycleS := TIME_TO_REAL(tCycle) / 1000.0;   // 秒值 / Seconds [s]
IF tCycleS < 0.01 THEN
    tCycleS := 0.01;    // 钳 ≥0.01 s 防步长爆炸 / Clamp minimum 10 ms
END_IF

// ---- 单拍步长 / Max step per cycle ----
fStepMax := fRateMax_pct_s * tCycleS;       // %/s × s = % / Step per cycle [%]

// ---- 超温锁存解除路径（必须可达，R28）：bReset 且全部 PV < 阈值-5K 回差 / Reset path with 5K hysteresis ----
IF bOvertemp AND bReset THEN
    bAnyOver := FALSE;          // 回差判据累加器 / Hysteresis accumulator
    FOR uIdx := 1 TO 8 DO
        uZi := UDINT_TO_INT(uIdx);              // 下标转换 / Subscript conversion
        IF afPv_C[uZi] >= (fOvertemp_C - 5.0) THEN
            bAnyOver := TRUE;   // 仍有区未回落 5K / Zone not cooled by 5K
        END_IF
    END_FOR
    IF NOT bAnyOver THEN
        bOvertemp     := FALSE; // 解除锁存 / Release latch
        uOvertempZone := 0;     // 区号清零 / Clear zone number
        eState := E_DL_OvenState.eIdle; // 回空闲 / Back to idle
    END_IF
END_IF

// ---- 非有限与周期合法性闸（故障级）/ Finite and cycle validity gate ----
IF (tCycle = T#0MS) OR (tCycleS > 2.0)
   OR (fFanPct <> fFanPct) OR (ABS(fFanPct) >= 1.0E12)
   OR (fKff <> fKff) OR (ABS(fKff) >= 1.0E12)
   OR (fOvertemp_C <> fOvertemp_C) OR (ABS(fOvertemp_C) >= 1.0E12)
   OR (fRateMax_pct_s <> fRateMax_pct_s) OR (ABS(fRateMax_pct_s) >= 1.0E12) THEN
    bOvertemp     := FALSE;     // 清锁存避免卡死 / Clear latch to avoid deadlock
    uOvertempZone := 0;         // 区号清零 / Clear zone
    FOR uZi := 1 TO 8 DO
        afOut_pct[uZi] := 0.0;  // 全输出清零（安全侧）/ Zero all outputs
    END_FOR
    bReady := FALSE;            // 就绪失效 / Not ready
    eState := E_DL_OvenState.eFault;    // 故障态（本闸不锁存，可自动恢复）/ Fault state
    eErr   := 16#0002_3720;     // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 各区 PV/SP 非有限逐个判界（多 ARRAY 按各自上界逐个判）/ Per-zone finite check ----
FOR uZi := 1 TO 8 DO
    IF (afPv_C[uZi] <> afPv_C[uZi]) OR (ABS(afPv_C[uZi]) >= 1.0E12)
       OR (afSp_C[uZi] <> afSp_C[uZi]) OR (ABS(afSp_C[uZi]) >= 1.0E12) THEN
        FOR uZj2 := 1 TO 8 DO
            afOut_pct[uZj2] := 0.0;  // 全输出清零 / Zero all outputs
        END_FOR
        bReady := FALSE;        // 就绪失效 / Not ready
        eState := E_DL_OvenState.eFault;    // 故障态 / Fault state
        eErr   := 16#0002_3720; // 故障码 / Fault code
        RETURN;                 // 本拍结束 / End of cycle
    END_IF
END_FOR

// ---- 组态错闸 / Configuration fault gate ----
IF (fOvertemp_C <= 0.0) OR (fRateMax_pct_s <= 0.0) THEN
    FOR uZi := 1 TO 8 DO
        afOut_pct[uZi] := 0.0;  // 全输出清零 / Zero all outputs
    END_FOR
    bReady := FALSE;            // 就绪失效 / Not ready
    eState := E_DL_OvenState.eFault;    // 故障态 / Fault state
    eErr   := 16#0002_3721;     // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF
FOR uZi := 1 TO 8 DO
    IF afKp[uZi] <= 0.0 THEN
        FOR uZj2 := 1 TO 8 DO
            afOut_pct[uZj2] := 0.0;  // 全输出清零 / Zero all outputs
        END_FOR
        bReady := FALSE;        // 就绪失效 / Not ready
        eState := E_DL_OvenState.eFault;    // 故障态 / Fault state
        eErr   := 16#0002_3721; // 故障码 / Fault code
        RETURN;                 // 本拍结束 / End of cycle
    END_IF
END_FOR

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    FOR uZi := 1 TO 8 DO
        afOut_pct[uZi] := 0.0;  // 输出从 0 起步 / Outputs start at zero
    END_FOR
    xFirstScan := FALSE;        // 清首扫标记 / Clear flag
END_IF

// ---- 使能撤销：全区输出清零回空闲 / Disable: zero outputs and idle ----
IF NOT bEnable THEN
    FOR uZi := 1 TO 8 DO
        afOut_pct[uZi] := 0.0;  // 全输出清零 / Zero all outputs
    END_FOR
    bReady := FALSE;            // 就绪失效 / Not ready
    eState := E_DL_OvenState.eIdle;     // 空闲态 / Idle state
    eErr   := 16#0002_371F;     // 信息级：空闲正常 / Info: idle normal
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 使能区存在性检查：全关 → eIdle 输出全 0 / No enabled zone → idle ----
bAllEnabled := FALSE;           // 累加器复位 / Reset accumulator
FOR uZi := 1 TO 8 DO
    IF abZoneEnable[uZi] THEN
        bAllEnabled := TRUE;    // 至少一区使能 / At least one zone enabled
    END_IF
END_FOR
IF NOT bAllEnabled THEN
    FOR uZi := 1 TO 8 DO
        afOut_pct[uZi] := 0.0;  // 全输出清零 / Zero all outputs
    END_FOR
    bReady := FALSE;            // 就绪失效 / Not ready
    eState := E_DL_OvenState.eIdle;     // 空闲态 / Idle state
    eErr   := 16#0002_371F;     // 信息级：空闲正常 / Info: idle normal
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 风量前馈有效性：bFanRun=FALSE → 前馈项按 0 计 / Feedforward disabled without fan ----
bFanBad := FALSE;               // 标记复位 / Reset flag
fFanPctSafe := fFanPct;         // 原值采用 / Adopt as-is
IF NOT bFanRun THEN
    fFanPctSafe := 0.0;         // 前馈禁用（不是零输出）/ FF disabled, control continues
END_IF

// ---- 超温探测（超温优先于调节）/ Overtemp detection has priority ----
bAnyOver   := FALSE;            // 探测复位 / Reset detection
uFirstOver := 0;                // 首区清零 / Clear first zone
FOR uZi := 1 TO 8 DO
    IF afPv_C[uZi] >= fOvertemp_C THEN
        bAnyOver := TRUE;       // 探测到超温 / Overtemp found
        IF uFirstOver = 0 THEN
            uFirstOver := INT_TO_USINT(uZi);    // 记录首区 / Record first zone
        END_IF
    END_IF
END_FOR

IF bAnyOver THEN
    // 超温路径：全输出清零 + 故障锁存，绝不边降温边加热 / Overtemp: zero all, latch fault
    FOR uZi := 1 TO 8 DO
        afOut_pct[uZi] := 0.0;  // 全输出清零（安全侧）/ Zero all outputs
    END_FOR
    bOvertemp     := TRUE;      // 锁存 / Latch
    uOvertempZone := uFirstOver;    // 记首区 / First zone
    bReady        := FALSE;     // 就绪失效 / Not ready
    eState        := E_DL_OvenState.eFault;     // 故障态 / Fault state
    eErr          := 16#0002_3723;      // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 正常调节路径（eRun）：逐区比例 + 前馈 + 速率限幅 / Normal control path ----
eState := E_DL_OvenState.eRun;      // 运行态 / Run state
bReady := TRUE;                     // 就绪假设成立，区带外再翻 false / Assume ready, clear per zone
FOR uZi := 1 TO 8 DO
    IF abZoneEnable[uZi] THEN
        // 设定 ≤0 按 1 ℃ 处理（防冻结工况斜率无穷）/ SP ≤0 treated as 1 degC
        IF afSp_C[uZi] <= 0.0 THEN
            fSpSafe := 1.0;     // 防斜率无穷 / Guard slope
        ELSE
            fSpSafe := afSp_C[uZi]; // 原值 / As-is
        END_IF
        fDevK := fSpSafe - afPv_C[uZi];     // 偏差 = SP - PV / Deviation [K]
        // 比例项 + 风量前馈项 / Proportional + fan feedforward term
        fOutRaw := afKp[uZi] * fDevK + fKff * fFanPctSafe;  // 原始输出 [%]
        // 前馈禁用信息级（bFanRun=FALSE 且 fKff>0 时提示）/ FF disabled info
        IF (NOT bFanRun) AND (fKff > 0.0) THEN
            eErr := 16#0002_3722;   // 信息级：前馈禁用 / Info: FF disabled
        END_IF
        // 输出限幅 0~100 % / Clamp 0..100
        IF fOutRaw < 0.0 THEN
            fOutRaw := 0.0;     // 下限 / Lower clamp
        ELSIF fOutRaw > 100.0 THEN
            fOutRaw := 100.0;   // 上限 / Upper clamp
        END_IF
        // 速率限幅（单拍增量 ≤ fStepMax）/ Slew limit per cycle
        fStep := fOutRaw - afOut_pct[uZi];  // 期望步长 / Desired step [%]
        IF fStep > fStepMax THEN
            fStep := fStepMax;      // 正向限速 / Positive slew
        ELSIF fStep < -fStepMax THEN
            fStep := -fStepMax;     // 负向限速 / Negative slew
        END_IF
        afOut_pct[uZi] := afOut_pct[uZi] + fStep;   // 采纳步长 / Adopt step
        // 带内判（±2 K 带容差）/ In-band check (±2 K tolerance)
        IF ABS(fSpSafe - afPv_C[uZi]) > 2.0 THEN
            bReady := FALSE;    // 区带外 → 就绪失效 / Zone out of band
        END_IF
    ELSE
        afOut_pct[uZi] := 0.0;  // 禁用区输出保持 0 / Disabled zone output zero
    END_IF
END_FOR

// 未在任何分支改写 eErr 时补正常码 / Default normal code if untouched
IF eErr <> 16#0002_3722 THEN
    eErr := 16#0002_371F;       // 信息级：正常运行 / Info: normal run
END_IF

END_FUNCTION_BLOCK
