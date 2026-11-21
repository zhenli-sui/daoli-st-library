// =====================================================================
// FB_DL_HeatExchangerCtrl.st
// 换热器出口温度分程控制（低温段蒸汽阀加热 / 高温段凝水阀冷却）
// Heat exchanger split-range outlet temperature control FB
// 码位: 16#0002_3724 ~ 16#0002_3728 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 6)
// =====================================================================
FUNCTION_BLOCK FB_DL_HeatExchangerCtrl
VAR_INPUT
    bEnable       : BOOL  := FALSE;    // 使能 / Enable
    bPvValid      : BOOL  := FALSE;    // 温度有效 / PV valid
    fPv_C         : REAL  := 20.0;     // 出口温度 -20~250 ℃ / Outlet temperature [degC]
    fSp_C         : REAL  := 80.0;     // 设定 0~200 ℃ / Setpoint [degC]
    fDeadBand_C   : REAL  := 1.0;      // 分程死区 0~10 K / Split dead band [K]
    fKp           : REAL  := 3.0;      // 比例增益 0.1~50 %/K / Gain [%/K]
    fTi_s         : REAL  := 60.0;     // 积分时间 >0 s / Integral time [s]
    fBiasPct      : REAL  := 2.0;      // 交接偏置 0~20 % / Handover bias [%]
    fCondSafe_pct : REAL  := 30.0;     // 凝水阀安全位 0~100 % / Condensate safe position [%]
    bSteamAvail   : BOOL  := TRUE;     // 蒸汽可用 / Steam available
    bCondAvail    : BOOL  := TRUE;     // 凝水可用 / Condensate available
    tCycle        : TIME  := T#200MS;  // 周期 T#20MS~T#5S / Cycle [s]
END_VAR
VAR_OUTPUT
    fSteamOut_pct : REAL;               // 蒸汽阀 0~100 % / Steam valve [%]
    fCondOut_pct  : REAL;               // 凝水阀 0~100 % / Condensate valve [%]
    fErr_C        : REAL;               // 温度偏差 K / Deviation [K]
    bSplitActive  : BOOL;               // 分程动作中 / Split active
    bDegraded     : BOOL;               // 单支路降级 / Degraded single branch
    eErr          : UDINT;              // 错误码 / Error code
END_VAR
VAR
    fIntegral     : REAL  := 0.0;       // 积分项 / Integral term [%]
    fTerm         : REAL  := 0.0;       // 本支路计算项 / Branch computed term [%]
    fIncr         : REAL  := 0.0;       // 本拍积分增量 / Integral increment this cycle [%]
    tCycleS       : REAL;               // 周期秒值 / Cycle in seconds [s]
    fDbSafe       : REAL;               // 兜底死区 / Sanitized dead band [K]
    bMutexLatch   : BOOL  := FALSE;     // 分程互斥失效锁存 / Split mutex fault latch
    xFirstScan    : BOOL  := TRUE;      // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0002_3724 信息 正常运行
//   16#0002_3725 故障 输入非有限 / tCycle 非法 / fTi_s ≤ 0（含 PV=NaN 安全侧分支）
//   16#0002_3726 故障 fKp ≤ 0 / fDeadBand_C < 0 / fBiasPct < 0（组态错）
//   16#0002_3727 信息 单支路降级（蒸汽或凝水不可用）→ bDegraded=TRUE；bPvValid=FALSE 安全侧同登记
//   16#0002_3728 故障 双阀同时 >0.5 % 且 ABS(fErr_C) > fDeadBand_C → 双阀归 0 锁存，解除=bReset 且带内
// ---------------------------------------------------------------------

// ---- 周期转秒 / Cycle to seconds ----
tCycleS := TIME_TO_REAL(tCycle) / 1000.0;   // 秒值 / Seconds [s]

// ---- 非有限与时域合法性闸（故障级）/ Finite and time-domain gate ----
IF (tCycle = T#0MS) OR (tCycleS < 0.02) OR (tCycleS > 5.0)
   OR (fTi_s <= 0.0)
   OR (fPv_C <> fPv_C) OR (ABS(fPv_C) >= 1.0E12)
   OR (fSp_C <> fSp_C) OR (ABS(fSp_C) >= 1.0E12)
   OR (fCondSafe_pct <> fCondSafe_pct) OR (ABS(fCondSafe_pct) >= 1.0E12) THEN
    fSteamOut_pct := 0.0;       // 蒸汽阀安全关闭 / Steam safe closed
    fCondOut_pct  := fCondSafe_pct; // 凝水阀安全位 / Condensate safe position
    bSplitActive  := FALSE;     // 分程退出 / Split inactive
    bDegraded     := TRUE;      // 登记降级 / Mark degraded
    eErr          := 16#0002_3725;  // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fKp <= 0.0) OR (fDeadBand_C < 0.0) OR (fBiasPct < 0.0) THEN
    fSteamOut_pct := 0.0;       // 蒸汽阀关闭 / Steam closed
    fCondOut_pct  := 0.0;       // 凝水阀关闭 / Condensate closed
    bSplitActive  := FALSE;     // 分程退出 / Split inactive
    eErr          := 16#0002_3726;  // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 死区兜底：0 按 0.5 K 防抖振 / Dead-band fallback: 0 to 0.5 K ----
IF fDeadBand_C = 0.0 THEN
    fDbSafe := 0.5;             // 兜底 0.5 K / Fallback 0.5 K
ELSE
    fDbSafe := fDeadBand_C;     // 原值 / As-is
END_IF

// ---- 首扫初始化 / First-scan initialization ----
IF xFirstScan THEN
    fSteamOut_pct := 0.0;       // 蒸汽阀初始关 / Steam init closed
    fCondOut_pct  := 0.0;       // 凝水阀初始关 / Condensate init closed
    fIntegral     := 0.0;       // 积分清零 / Integral cleared
    xFirstScan    := FALSE;     // 清标记 / Clear flag
END_IF

// ---- 使能撤销：双阀回关 / Disable: both valves closed ----
IF NOT bEnable THEN
    fSteamOut_pct := 0.0;       // 蒸汽阀关 / Steam closed
    fCondOut_pct  := 0.0;       // 凝水阀关 / Condensate closed
    bSplitActive  := FALSE;     // 分程退出 / Split inactive
    bDegraded     := FALSE;     // 降级复位 / Reset degraded
    eErr          := 16#0002_3724;  // 信息级：空闲正常 / Info: idle normal
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 偏差计算 / Deviation computation ----
fErr_C := fSp_C - fPv_C;        // 偏差 = SP - PV / Deviation [K]

// ---- 分程互斥失效锁存与解除 / Split mutex latch and release ----
IF bMutexLatch THEN
    // 锁存中：双阀归 0，解除 = bReset 且 ABS(fErr_C) ≤ fDbSafe / Latched: valves 0, release on reset+in-band
    fSteamOut_pct := 0.0;       // 蒸汽阀归 0 / Steam zero
    fCondOut_pct  := 0.0;       // 凝水阀归 0 / Condensate zero
    bSplitActive  := FALSE;     // 分程退出 / Split inactive
    eErr := 16#0002_3728;       // 故障码回放 / Fault code replay
    IF bReset AND (ABS(fErr_C) <= fDbSafe) THEN
        bMutexLatch := FALSE;   // 解除锁存 / Release latch
        fIntegral   := 0.0;     // 积分清零重新起步 / Clear integral
    END_IF
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- PV 无效安全侧：蒸汽关、凝水安全位 / PV invalid safe side ----
IF NOT bPvValid THEN
    fSteamOut_pct := 0.0;       // 蒸汽关 / Steam closed
    fCondOut_pct  := fCondSafe_pct; // 凝水安全位 / Condensate safe
    bSplitActive  := FALSE;     // 分程退出 / Split inactive
    bDegraded     := TRUE;      // 登记降级（信息级，不置故障）/ Mark degraded (info only)
    eErr          := 16#0002_3727;  // 信息级：降级 / Info: degraded
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 单支路可用性降级登记 / Single-branch availability degrade ----
bDegraded := (NOT bSteamAvail) OR (NOT bCondAvail);  // 降级标志 / Degraded flag

// ---- 分程 PI 计算（内联，交接偏置防抢动）/ Split-range PI with handover bias ----
bSplitActive := FALSE;          // 默认分程未动作 / Default inactive
IF fErr_C > fDbSafe THEN
    // 低温段：开蒸汽阀加热 / Low side: steam heating
    fIncr := (fErr_C / fTi_s) * tCycleS;    // 积分增量 / Integral increment [%]
    // 抗饱和：蒸汽支路到 100 % 边沿停同向积分 / Anti-windup at 100 %
    IF (fSteamOut_pct >= 100.0) AND (fIncr > 0.0) THEN
        fIncr := 0.0;           // 停同向积分 / Freeze integral
    END_IF
    fIntegral := fIntegral + fIncr;     // 积分累计 / Integrate
    fTerm := fKp * (fErr_C - fDbSafe) + fIntegral + fBiasPct;   // 计算项含交接偏置 / Term with bias [%]
    IF fTerm < 0.0 THEN
        fTerm := 0.0;           // 下限钳 / Lower clamp
    ELSIF fTerm > 100.0 THEN
        fTerm := 100.0;         // 上限钳（下一拍抗饱和生效）/ Upper clamp
    END_IF
    IF bSteamAvail THEN
        fSteamOut_pct := fTerm; // 蒸汽阀输出 / Steam output
    ELSE
        fSteamOut_pct := 0.0;   // 蒸汽不可用 → 支路 0 / Steam unavailable
    END_IF
    fCondOut_pct := 0.0;        // 凝水阀关 / Condensate closed
    bSplitActive := TRUE;       // 分程动作中 / Split active
    eErr := 16#0002_3724;       // 信息级：正常 / Info: normal
ELSIF fErr_C < -fDbSafe THEN
    // 高温段：开凝水阀冷却 / High side: condensate cooling
    fIncr := (-fErr_C / fTi_s) * tCycleS;   // 积分增量 / Integral increment [%]
    // 抗饱和：凝水支路到 100 % 边沿停同向积分 / Anti-windup at 100 %
    IF (fCondOut_pct >= 100.0) AND (fIncr > 0.0) THEN
        fIncr := 0.0;           // 停同向积分 / Freeze integral
    END_IF
    fIntegral := fIntegral + fIncr;     // 积分累计 / Integrate
    fTerm := fKp * (-fErr_C - fDbSafe) + fIntegral + fBiasPct;  // 计算项含交接偏置 / Term with bias [%]
    IF fTerm < 0.0 THEN
        fTerm := 0.0;           // 下限钳 / Lower clamp
    ELSIF fTerm > 100.0 THEN
        fTerm := 100.0;         // 上限钳 / Upper clamp
    END_IF
    IF bCondAvail THEN
        fCondOut_pct := fTerm;  // 凝水阀输出 / Condensate output
    ELSE
        fCondOut_pct := 0.0;    // 凝水不可用 → 支路 0 / Condensate unavailable
    END_IF
    fSteamOut_pct := 0.0;       // 蒸汽阀关 / Steam closed
    bSplitActive := TRUE;       // 分程动作中 / Split active
    eErr := 16#0002_3724;       // 信息级：正常 / Info: normal
ELSE
    // 死区带内：双阀同关 / In dead band: both closed
    fSteamOut_pct := 0.0;       // 蒸汽阀关 / Steam closed
    fCondOut_pct  := 0.0;       // 凝水阀关 / Condensate closed
    eErr := 16#0002_3724;       // 信息级：正常 / Info: normal
END_IF

// ---- 分程互斥闸（防御性复核，越过分程死区双阀非零 → 故障锁存）/ Mutex recheck ----
IF (fSteamOut_pct > 0.5) AND (fCondOut_pct > 0.5) AND (ABS(fErr_C) > fDbSafe) THEN
    fSteamOut_pct := 0.0;       // 双阀归 0 / Both valves zero
    fCondOut_pct  := 0.0;       // 双阀归 0 / Both valves zero
    bMutexLatch   := TRUE;      // 锁存 / Latch
    eErr          := 16#0002_3728;  // 故障码 / Fault code
END_IF

// ---- 单支路降级信息级覆盖 / Degraded info code override ----
IF bDegraded AND (eErr = 16#0002_3724) THEN
    eErr := 16#0002_3727;       // 信息级：单支路降级 / Info: degraded
END_IF

END_FUNCTION_BLOCK
