// =====================================================================
// FB_DL_CoolantFlowAudit.st
// 机台冷却水多支路流量审计（欠流确认窗 + 迟滞锁存 + 首出三律定位）
// Multi-branch coolant flow audit with underflow confirm and first-out
// 所属子库: DL_Device    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0003_03E3 ~ 16#0003_03E7 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: semiconductor, coolant, flow-audit, alarm-management
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 3)
// =====================================================================
FUNCTION_BLOCK FB_DL_CoolantFlowAudit
VAR_INPUT
    bEnable       : BOOL  := FALSE;   // 使能 / Enable
    afFlow_Lpm    : ARRAY[1..8] OF REAL;   // 各支路流量 0~500 L/min / Branch flow [L/min]
    afMinFlow_Lpm : ARRAY[1..8] OF REAL;   // 各支路欠流阈值 0~500 L/min / Branch underflow threshold [L/min]
    tConfirm      : TIME  := T#2S;    // 欠流确认窗 T#10MS~T#60S / Underflow confirm window [s]
    fHyst_Lpm     : REAL  := 2.0;     // 欠流解除迟滞 0~50 L/min / Release hysteresis [L/min]
END_VAR
VAR_OUTPUT
    uwUnderMask   : WORD  := 0;       // 欠流位掩码, 位 0..7 对应支路 1..8 / Underflow mask, bit0..7 = branch 1..8
    uFirstOut     : USINT := 0;       // 首出支路号 1~8, 0 = 无 / First-out branch, 0 = none
    bAllOk        : BOOL  := FALSE;   // 全部支路正常 / All branches ok
    eErr          : UDINT := 16#0003_03E3;  // 错误码 / Error code
END_VAR
VAR
    aTonConf      : ARRAY[1..8] OF TON;   // 各支路欠流确认定时器, 每拍无条件刷新 / Per-branch confirm timers, refreshed every cycle
    abUnderLatch  : ARRAY[1..8] OF BOOL;  // 各支路欠流锁存 / Per-branch underflow latch
    abSensorFlt   : ARRAY[1..8] OF BOOL;  // 各支路传感器故障标记 / Per-branch sensor fault flag
    bCfgErr       : BOOL  := FALSE;   // 组态非法标记 / Configuration error flag
    bSnsErr       : BOOL  := FALSE;   // 任一支路传感器故障标记 / Any-branch sensor fault flag
    uFirstLatch   : USINT := 0;       // 首出锁存支路号 / First-out latched branch
    uZi           : INT   := 1;       // 1..8 数组下标 / Array subscript 1..8
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0003_03E3 信息 全部支路正常
//   16#0003_03E4 故障 组态非法（欠流阈值或迟滞非有限, 或越出 0~500/0~50 L/min 合法域）
//   16#0003_03E5 故障 任一支路流量非有限/为负/超量程（传感器故障, 独立于欠流判据）
//   16#0003_03E6 故障 存在确认欠流支路（掩码非零）, 解除式 = 对应支路流量恢复到阈值+迟滞以上
//   16#0003_03E7 信息 待机未使能
// ---------------------------------------------------------------------

// ---- 守卫闸: 迟滞与逐支路阈值合法域 / Gate: hysteresis and per-branch threshold validity ----
bCfgErr := FALSE;               // 组态错误标记复位 / Reset config error flag
IF (fHyst_Lpm <> fHyst_Lpm) OR (fHyst_Lpm < 0.0) OR (fHyst_Lpm > 50.0) THEN
    bCfgErr := TRUE;            // 迟滞非法 / Illegal hysteresis
END_IF
IF NOT bCfgErr THEN
    FOR uZi := 1 TO 8 DO
        IF (afMinFlow_Lpm[uZi] <> afMinFlow_Lpm[uZi])
           OR (afMinFlow_Lpm[uZi] < 0.0) OR (afMinFlow_Lpm[uZi] > 500.0) THEN
            bCfgErr := TRUE;    // 阈值越界即组态故障 / Threshold out of domain = config fault
        END_IF
    END_FOR
END_IF

// ---- 逐支路传感器故障判: 非有限/负值/超量程, 独立于欠流判据 / Per-branch sensor fault judge ----
bSnsErr := FALSE;               // 传感器故障标记复位 / Reset sensor fault flag
FOR uZi := 1 TO 8 DO
    abSensorFlt[uZi] := (afFlow_Lpm[uZi] <> afFlow_Lpm[uZi])
                     OR (afFlow_Lpm[uZi] < 0.0)
                     OR (afFlow_Lpm[uZi] > 500.0);  // 非有限自反判或越域 / Non-finite or out of domain
    IF abSensorFlt[uZi] THEN
        bSnsErr := TRUE;        // 置总传感器故障标记 / Set overall sensor fault flag
    END_IF
END_FOR

// ---- 欠流确认定时器无条件周期刷新 + 锁存/解除 / Confirm timers unconditional refresh, latch and release ----
FOR uZi := 1 TO 8 DO
    IF bEnable AND (NOT bCfgErr) AND (NOT abSensorFlt[uZi]) AND (NOT abUnderLatch[uZi]) THEN
        // 进入条件: 流量低于阈值计时, 窗内瞬时恢复自动清零计时（抖动不误报）
        // Enter: below threshold timing; transient recovery resets timing in window
        aTonConf[uZi](IN := afFlow_Lpm[uZi] < afMinFlow_Lpm[uZi], PT := tConfirm);
        IF aTonConf[uZi].Q AND (afFlow_Lpm[uZi] < afMinFlow_Lpm[uZi]) THEN
            abUnderLatch[uZi] := TRUE;      // 确认欠流锁存 / Confirm underflow latch
        END_IF
    ELSE
        aTonConf[uZi](IN := FALSE, PT := tConfirm);     // 非候选支路显式复位 / Explicit reset for non-candidates
    END_IF
    // 解除: 流量恢复到阈值+迟滞以上 / Release: flow above threshold plus hysteresis
    IF abUnderLatch[uZi] AND (NOT abSensorFlt[uZi])
       AND (afFlow_Lpm[uZi] >= (afMinFlow_Lpm[uZi] + fHyst_Lpm)) THEN
        abUnderLatch[uZi] := FALSE;     // 解除欠流锁存 / Release underflow latch
    END_IF
    // 传感器故障拍欠流判据失效, 强制解除该支路锁存 / Sensor fault voids underflow judge
    IF abSensorFlt[uZi] THEN
        abUnderLatch[uZi] := FALSE;     // 强制解除 / Forced release
    END_IF
END_FOR

// ---- 欠流位掩码汇总 / Underflow mask aggregation ----
uwUnderMask := 0;                   // 掩码复位 / Reset mask
FOR uZi := 1 TO 8 DO
    IF abUnderLatch[uZi] THEN
        uwUnderMask := uwUnderMask OR SHL(WORD#1, uZi - 1);     // 移位量 0..7 小于字宽, 合规 / Shift 0..7 within word width
    END_IF
END_FOR

// ---- 首出三律: 未锁存才仲裁, 同拍取最小支路号, 解除在仲裁后（掩码全清时释放）
//      First-out laws: arbitrate only if not latched, min branch per cycle, release after mask clears ----
IF (uFirstLatch = 0) AND (uwUnderMask <> 0) THEN
    FOR uZi := 1 TO 8 DO
        IF (uFirstLatch = 0) AND abUnderLatch[uZi] THEN
            uFirstLatch := INT_TO_USINT(uZi);   // 升序扫描, 首个命中即最小支路号 / Ascending scan picks min branch
        END_IF
    END_FOR
END_IF
IF uwUnderMask = 0 THEN
    uFirstLatch := 0;               // 全部支路恢复后释放首出锁存 / Release first-out when all clear
END_IF
uFirstOut := uFirstLatch;           // 输出首出支路号 / Output first-out branch

// ---- 全正常输出 / All-ok output ----
bAllOk := bEnable AND (NOT bCfgErr) AND (NOT bSnsErr) AND (uwUnderMask = 0);

// ---- 错误码仲裁（每拍重算, 故障解除可达）/ Error arbitration, releasable ----
IF bCfgErr THEN
    eErr := 16#0003_03E4;           // 组态非法 / Configuration fault
ELSIF bSnsErr THEN
    eErr := 16#0003_03E5;           // 传感器故障 / Sensor fault
ELSIF uwUnderMask <> 0 THEN
    eErr := 16#0003_03E6;           // 存在欠流支路 / Underflow present
ELSIF NOT bEnable THEN
    eErr := 16#0003_03E7;           // 待机未使能 / Standby
ELSE
    eErr := 16#0003_03E3;           // 全部正常 / All normal
END_IF

END_FUNCTION_BLOCK
