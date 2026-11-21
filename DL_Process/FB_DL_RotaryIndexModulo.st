// =====================================================================
// FB_DL_RotaryIndexModulo.st
// 转盘工位索引与入料放行联锁（显式回绕禁 MOD+1、到位去抖 2 拍）
// Rotary table index and entry permit interlock FB
// 码位: 16#0005_045D ~ 16#0005_0461 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 19)
// =====================================================================
FUNCTION_BLOCK FB_DL_RotaryIndexModulo
VAR_INPUT
    bEnable      : BOOL  := FALSE;    // 使能 / Enable
    bIndexReq    : BOOL  := FALSE;    // 分度请求（上升沿受理）/ Index request on edge
    bReset       : BOOL  := FALSE;    // 复位 / Reset
    bAtPos       : BOOL  := FALSE;    // 转盘到位信号 / At position
    bIndexDone   : BOOL  := FALSE;    // 分度电机完成 / Index done
    bEntryClear  : BOOL  := FALSE;    // 入料通道已清空 / Entry clear
    uStationCnt  : USINT  := 8;       // 工位数 1~64 / Station count
    uStationInit : USINT  := 1;       // 初始工位号 1~64 / Initial station
    tIndexMax    : TIME  := T#5S;     // 分度超时 T#200MS~T#60S / Index timeout [s]
END_VAR
VAR_OUTPUT
    uStationIdx  : USINT;             // 当前工位号 1~64 / Station index
    bPermitEntry : BOOL;              // 入料放行 / Entry permit
    bIndexing    : BOOL;              // 分度中 / Indexing
    uIndexCnt    : UDINT;             // 累计分度次数 / Index count
    eErr         : UDINT;             // 错误码 / Error code
END_VAR
VAR
    rtrigReq     : R_TRIG;            // 分度请求沿检测（无条件刷新）/ Request edge detector
    tonIndex     : TON;               // 分度超时定时器（无条件刷新）/ Index timeout timer
    uAtPosDeb    : USINT;             // 到位去抖计数（连续 2 拍稳定）/ At-position debounce counter
    bAtPosStable : BOOL;              // 去抖后到位 / Stable at-position
    bTimeoutLatch: BOOL := FALSE;     // 超时锁存 / Timeout latch
    tIndexMaxS   : REAL;              // 超时秒值 / Timeout seconds [s]
    xFirstScan   : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0005_045D 信息 正常（等待分度 / 已放行）
//   16#0005_045E 故障 tIndexMax 非法
//   16#0005_045F 故障 uStationCnt = 0 / uStationInit > uStationCnt（组态错）
//   16#0005_0460 信息 分度被拒（bEntryClear=FALSE 或 bAtPos=FALSE）→ bPermitEntry 保持 TRUE
//   16#0005_0461 故障 分度超 tIndexMax 未到位 → 关闭入料并锁存；解除=bReset 且 bAtPos 且 bEntryClear
// ---------------------------------------------------------------------

// ---- 超时秒值 / Timeout seconds ----
tIndexMaxS := TIME_TO_REAL(tIndexMax) / 1000.0;     // 秒值 / Seconds [s]

// ---- 请求沿检测（无条件刷新）/ Request edge, unconditional ----
rtrigReq(CLK := bIndexReq);     // 沿检测 / Edge detection

// ---- 超时参数闸 / Timeout validity gate ----
IF (tIndexMax = T#0MS) OR (tIndexMaxS < 0.2) OR (tIndexMaxS > 60.0) THEN
    bPermitEntry := FALSE;      // 放行撤销（安全侧）/ Permit off
    bIndexing := FALSE;         // 非分度 / Not indexing
    eErr := 16#0005_045E;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (uStationCnt = 0) OR (uStationInit > uStationCnt) THEN
    bPermitEntry := FALSE;      // 放行撤销 / Permit off
    bIndexing := FALSE;         // 非分度 / Not indexing
    uStationIdx := 0;           // 工位号失效 / Index invalid
    eErr := 16#0005_045F;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律：bPermitEntry=FALSE 等首次到位确认）/ First-scan init ----
IF xFirstScan THEN
    uStationIdx := uStationInit;    // 初始工位号 / Init station
    bPermitEntry := FALSE;      // 首扫不放行 / No release on first scan
    bIndexing := FALSE;         // 非分度 / Not indexing
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    bPermitEntry := FALSE;      // 放行撤销 / Permit off
    bIndexing := FALSE;         // 非分度 / Not indexing
    bTimeoutLatch := FALSE;     // 锁存复位 / Latch reset
    eErr := 16#0005_045D;       // 信息级：空闲 / Info: idle
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 超时锁存路径（解除 = bReset 且 bAtPos 且 bEntryClear）/ Timeout latch path ----
IF bTimeoutLatch THEN
    bPermitEntry := FALSE;      // 绝不带转盘运转放料 / Never release while latched
    bIndexing := FALSE;         // 非分度 / Not indexing
    eErr := 16#0005_0461;       // 故障码回放 / Fault code replay
    IF bReset AND bAtPos AND bEntryClear THEN
        bTimeoutLatch := FALSE;     // 解除锁存 / Release latch
        bPermitEntry := TRUE;       // 恢复放行 / Restore permit
        eErr := 16#0005_045D;       // 信息级：恢复 / Info: restored
    END_IF
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 到位去抖（连续 2 拍稳定才认到位，防抖动）/ At-position debounce, 2 cycles ----
IF bAtPos THEN
    IF uAtPosDeb < 2 THEN
        uAtPosDeb := uAtPosDeb + 1;     // 稳定计数 / Stability count
    END_IF
ELSE
    uAtPosDeb := 0;             // 抖动复位 / Jitter reset
END_IF
bAtPosStable := (uAtPosDeb >= 2);   // 稳定到位 / Stable

// ---- 分度进行路径 / Indexing active path ----
IF bIndexing THEN
    tonIndex(IN := TRUE, PT := tIndexMax);  // 无条件刷新 / Unconditional refresh
    IF tonIndex.Q THEN
        // 分度超时未到位：关入料 + 锁存 / Timeout: close entry, latch
        bTimeoutLatch := TRUE;  // 锁存 / Latch
        bIndexing := FALSE;     // 非分度 / Not indexing
        bPermitEntry := FALSE;  // 关闭入料 / Close entry
        eErr := 16#0005_0461;   // 故障码 / Fault code
        RETURN;                 // 本拍结束 / End of cycle
    END_IF
    IF bIndexDone AND bAtPosStable THEN
        // 到位确认：工位号显式回绕（禁 MOD+1，防整除点出 0 工位）/ Explicit wrap, no MOD
        uStationIdx := uStationIdx + 1;     // 递增 / Increment
        IF uStationIdx > uStationCnt THEN
            uStationIdx := 1;   // 回绕到 1 / Wrap to 1
        END_IF
        uIndexCnt := uIndexCnt + 1;     // 累计分度 / Count
        bIndexing := FALSE;     // 分度结束 / Indexing off
        bPermitEntry := TRUE;   // 放行 / Release
        eErr := 16#0005_045D;   // 信息级：已放行 / Info: released
    END_IF
ELSE
    tonIndex(IN := FALSE, PT := tIndexMax);     // 定时器复位 / Timer reset

    // ---- 等待态：受理分度请求沿 / Waiting: accept request edge ----
    IF rtrigReq.Q AND bAtPosStable THEN
        IF bEntryClear THEN
            // 放行一次分度：先关入料 / Permit one index: close entry first
            bPermitEntry := FALSE;  // 关闭入料 / Close entry
            bIndexing := TRUE;      // 分度中 / Indexing
            eErr := 16#0005_045D;   // 信息级：分度中 / Info: indexing
        ELSE
            // 入料未清：拒绝分度（不停机但拒动），保持放行不误关料 / Entry not clear: reject, keep permit
            eErr := 16#0005_0460;   // 信息级：分度被拒 / Info: rejected
        END_IF
    ELSIF rtrigReq.Q AND (NOT bAtPosStable) THEN
        // 不在位：拒绝分度，保持放行 / Not at position: reject, keep permit
        eErr := 16#0005_0460;   // 信息级：分度被拒 / Info: rejected
    ELSE
        // 空闲等待：正常码（首扫确认后可放行）/ Idle waiting
        IF (NOT bPermitEntry) AND bAtPosStable AND bEntryClear THEN
            bPermitEntry := TRUE;   // 首次到位确认后放行 / Release after first confirm
        END_IF
        eErr := 16#0005_045D;   // 信息级：正常 / Info: normal
    END_IF
END_IF

END_FUNCTION_BLOCK
