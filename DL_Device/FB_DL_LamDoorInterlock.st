// =====================================================================
// FB_DL_LamDoorInterlock.st
// 层压机炉门-真空-温度三联锁（开门三条件 + 反向联锁 + 首因定位）
// Laminator door-vacuum-temperature interlock FB
// 码位: 16#0003_03CF ~ 16#0003_03D3 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 10)
// =====================================================================
FUNCTION_BLOCK FB_DL_LamDoorInterlock
VAR_INPUT
    bEnable      : BOOL  := FALSE;    // 使能 / Enable
    bReset       : BOOL  := FALSE;    // 复位 / Reset
    bDoorClosed  : BOOL  := FALSE;    // 门关到位 / Door closed
    bDoorLocked  : BOOL  := FALSE;    // 门锁定反馈 / Door locked
    bUnlockReq   : BOOL  := FALSE;    // 开门请求 / Unlock request
    bVacReleased : BOOL  := FALSE;    // 真空已破（常开触点语义外置）/ Vacuum released
    bVacReady    : BOOL  := FALSE;    // 真空泵就绪 / Vacuum pump ready
    fVac_kPa     : REAL  := 101.3;    // 腔体绝压 0~101.3 kPa / Chamber pressure [kPa]
    fTemp_C      : REAL  := 25.0;     // 腔体温度 -20~250 ℃ / Chamber temperature [degC]
    fTempSafe_C  : REAL  := 60.0;     // 允许开门温度 20~120 ℃ / Safe unlock temperature [degC]
    fHeatPct     : REAL  := 0.0;      // 加热输出 0~100 % / Heater output [%]
    tUnlockHold  : TIME  := T#5S;     // 解锁保持超时监控 T#500MS~T#60S / Unlock hold timeout [s]
END_VAR
VAR_OUTPUT
    bDoorRelease : BOOL;              // 门解锁输出 / Door release
    bHeatPermit  : BOOL;              // 允许加热 / Heat permit
    bVacPermit   : BOOL;              // 允许抽真空 / Vacuum permit
    uFirstCause  : USINT;             // 首因码 0=无 1=真空 2=温度 3=加热 4=门信号 / First cause
    bHoldTimeout : BOOL;              // 解锁保持超时 / Unlock hold timeout
    eErr         : UDINT;             // 错误码 / Error code
END_VAR
VAR
    tonHold      : TON;               // 解锁保持超时定时器（无条件周期刷新）/ Unlock hold timer
    tonExempt    : TON;               // 门信号矛盾豁免窗口定时器 / Door-signal exemption timer
    bDoorMismatch: BOOL;              // 门信号矛盾当前值 / Door mismatch current
    bMismatchLatch: BOOL := FALSE;    // 门信号矛盾故障锁存 / Door mismatch fault latch
    bVacOK       : BOOL;              // 条件 1：真空已破 / Cond 1: vacuum released
    bTempOK      : BOOL;              // 条件 2：温度安全 / Cond 2: temp safe
    bHeatOK      : BOOL;              // 条件 3：加热已撤 / Cond 3: heat off
    tHoldS       : REAL;              // 超时秒值 / Hold timeout seconds [s]
    xFirstScan   : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0003_03CF 信息 联锁判定正常
//   16#0003_03D0 故障 温度/压力非有限 / tUnlockHold 非法
//   16#0003_03D1 故障 fTempSafe_C 出域（<20 或 >120）/ fVac_kPa < 0（组态错）
//   16#0003_03D2 信息 解锁保持超时（放行后门未开）→ bHoldTimeout=TRUE，不撤放行
//   16#0003_03D3 故障 bDoorClosed ≠ bDoorLocked（矛盾）→ 禁止加热/抽真空，锁存；解除=bReset 且信号一致
// ---------------------------------------------------------------------

// ---- 超时秒值 / Hold timeout seconds ----
tHoldS := TIME_TO_REAL(tUnlockHold) / 1000.0;   // 秒值 / Seconds [s]

// ---- 非有限与超时合法性闸 / Finite and timeout validity gate ----
IF (tUnlockHold = T#0MS) OR (tHoldS < 0.5) OR (tHoldS > 60.0)
   OR (fTemp_C <> fTemp_C) OR (ABS(fTemp_C) >= 1.0E12)
   OR (fVac_kPa <> fVac_kPa) OR (ABS(fVac_kPa) >= 1.0E12)
   OR (fHeatPct <> fHeatPct) OR (ABS(fHeatPct) >= 1.0E12)
   OR (fTempSafe_C <> fTempSafe_C) OR (ABS(fTempSafe_C) >= 1.0E12) THEN
    bDoorRelease := FALSE;      // 解锁输出撤销（安全侧）/ Release off (safe side)
    bHeatPermit  := FALSE;      // 加热许可撤销 / Heat permit off
    bVacPermit   := FALSE;      // 真空许可撤销 / Vac permit off
    eErr         := 16#0003_03D0;   // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fTempSafe_C < 20.0) OR (fTempSafe_C > 120.0) OR (fVac_kPa < 0.0) THEN
    bDoorRelease := FALSE;      // 解锁输出撤销 / Release off
    bHeatPermit  := FALSE;      // 加热许可撤销 / Heat permit off
    bVacPermit   := FALSE;      // 真空许可撤销 / Vac permit off
    eErr         := 16#0003_03D1;   // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    bDoorRelease := FALSE;      // 解锁初始关 / Release init off
    bHeatPermit  := FALSE;      // 加热许可初始关 / Heat permit init off
    bVacPermit   := FALSE;      // 真空许可初始关 / Vac permit init off
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 使能撤销：三输出全 FALSE（安全侧）/ Disable: all outputs FALSE ----
IF NOT bEnable THEN
    bDoorRelease := FALSE;      // 解锁撤销 / Release off
    bHeatPermit  := FALSE;      // 加热撤销 / Heat off
    bVacPermit   := FALSE;      // 真空撤销 / Vac off
    bHoldTimeout := FALSE;      // 超时复位 / Timeout reset
    bMismatchLatch := FALSE;    // 锁存复位 / Latch reset
    uFirstCause  := 0;          // 首因清零 / Cause cleared
    eErr := 16#0003_03CF;       // 信息级：空闲正常 / Info: idle normal
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 门信号矛盾检测（豁免窗口内不判故障）/ Door mismatch detection with exemption window ----
bDoorMismatch := (bDoorClosed <> bDoorLocked);  // 矛盾当前值 / Mismatch current
IF bDoorMismatch AND bUnlockReq AND (NOT bDoorClosed) THEN
    // 解锁瞬间锁反馈必然滞后 → tUnlockHold 窗口内豁免（防误锁）/ Exemption during unlock window
    tonExempt(IN := TRUE, PT := tUnlockHold);   // 豁免计时（无条件刷新）/ Exemption timing
    IF NOT tonExempt.Q THEN
        bDoorMismatch := FALSE;     // 窗口内豁免 / Exempted in window
    END_IF
ELSE
    tonExempt(IN := FALSE, PT := tUnlockHold);  // 窗口复位 / Window reset
END_IF

// ---- 门信号矛盾故障锁存与解除 / Door mismatch latch and release ----
IF bMismatchLatch THEN
    // 锁存中：禁止加热/抽真空，解锁也拒绝 / Latched: no heat/vac, no release
    bDoorRelease := FALSE;      // 解锁拒绝 / Release denied
    bHeatPermit  := FALSE;      // 加热禁止 / Heat denied
    bVacPermit   := FALSE;      // 真空禁止 / Vac denied
    uFirstCause  := 4;          // 首因：门信号 / Cause: door signal
    eErr         := 16#0003_03D3;   // 故障码回放 / Fault code replay
    IF bReset AND (NOT bDoorMismatch) THEN
        bMismatchLatch := FALSE;    // 解除锁存 / Release latch
    END_IF
    RETURN;                     // 本拍结束 / End of cycle
END_IF
IF bDoorMismatch THEN
    bMismatchLatch := TRUE;     // 置锁存 / Set latch
    bDoorRelease := FALSE;      // 解锁撤销 / Release off
    bHeatPermit  := FALSE;      // 加热禁止 / Heat denied
    bVacPermit   := FALSE;      // 真空禁止 / Vac denied
    uFirstCause  := 4;          // 首因 / Cause
    eErr         := 16#0003_03D3;   // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 开门三条件独立计布尔 / Three unlock conditions independently computed ----
bVacOK  := bVacReleased;        // 条件 1：真空已破 / Cond 1
bTempOK := (fTemp_C < fTempSafe_C);     // 条件 2：温度低于安全限 / Cond 2
bHeatOK := (fHeatPct < 0.5);    // 条件 3：无加热输出 / Cond 3

// ---- 首因定位：固定优先级（真空 → 温度 → 加热 → 门信号）/ First cause by fixed priority ----
uFirstCause := 0;               // 首因清零 / Cause cleared
IF bUnlockReq AND NOT (bVacOK AND bTempOK AND bHeatOK) THEN
    IF NOT bVacOK THEN
        uFirstCause := 1;       // 首因：真空未破 / Cause: vacuum
    ELSIF NOT bTempOK THEN
        uFirstCause := 2;       // 首因：温度过高 / Cause: temp
    ELSIF NOT bHeatOK THEN
        uFirstCause := 3;       // 首因：加热未撤 / Cause: heat
    ELSE
        uFirstCause := 4;       // 兜底：门信号异常 / Fallback: door signal
    END_IF
END_IF

// ---- 开门放行判定（三条件 AND）/ Release verdict (AND of three) ----
bDoorRelease := bUnlockReq AND bVacOK AND bTempOK AND bHeatOK;  // 放行 / Release

// ---- 解锁保持超时监控（放行后 tUnlockHold 内门仍未开）/ Unlock hold timeout monitor ----
bHoldTimeout := FALSE;          // 超时复位 / Reset
tonHold(IN := bDoorRelease AND (NOT bDoorClosed), PT := tUnlockHold);   // 定时器无条件刷新 / Unconditional refresh
IF tonHold.Q THEN
    bHoldTimeout := TRUE;       // 超时标志 / Timeout flag
    eErr := 16#0003_03D2;       // 信息级：保持超时（不撤放行）/ Info: timeout, release held
END_IF

// ---- 反向联锁：门未关严 → 禁止抽真空与加热 / Reverse interlock: door open blocks vac/heat ----
bVacPermit  := bDoorClosed AND bDoorLocked AND bVacReady;   // 抽真空许可 / Vac permit
bHeatPermit := bDoorClosed AND bDoorLocked;                 // 加热许可 / Heat permit

// ---- 正常码（未被超时信息级覆盖时）/ Normal code if not overridden ----
IF eErr <> 16#0003_03D2 THEN
    eErr := 16#0003_03CF;       // 信息级：联锁判定正常 / Info: normal
END_IF

END_FUNCTION_BLOCK
