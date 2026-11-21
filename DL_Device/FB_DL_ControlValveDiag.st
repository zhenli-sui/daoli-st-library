(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ControlValveDiag
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（LBP 深化，补调节阀诊断缺口）
 * 所属子库 (Sublibrary) : DL_Device / ValveDiag
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON / R_TRIG
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 调节阀行程偏差与迟滞诊断
 * 功能一句话 (Summary)  : 行程偏差确认 + 迟滞估计 + NE107 健康分级，仅监视不驱动。
 * 边界与安全 (Boundary) : ①反馈小于 -5% 或大于 105% → 传感器故障态优先于偏差态；
 *                         ②bEnable=FALSE → 全部输出复位（安全侧缺省）；
 *                         ③累计行程按反馈逐拍绝对增量累积（寿命估计口径）；
 *                         ④迟滞按指令换向点反馈快照对估计，超带锁存置码；
 *                         ⑤偏差 TON 与换向沿检测各一次、无条件周期刷新；
 *                         ⑥健康分级映射：传感器故障=eFailure，
 *                           偏差确认=eMaintenanceReq，迟滞超带=eOutOfSpec，
 *                           其余=eOk（数值小者即最严级，与库公约一致）。
 * 错误码    : 16#0003_0375 反馈超量程（传感器故障态）——故障级（持续态）
 *             16#0003_0376 行程偏差确认超时——故障级（持续态）
 *             16#0003_0377 迟滞超带（估计值大于容带）——故障级（持续态）
 * 码位总账  : 16#0003_0375 用 / 16#0003_0376 用 / 16#0003_0377 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ControlValveDiag
VAR_INPUT
    fCmdPos   : LREAL; // 指令阀位 [%] / Commanded valve position [%]
    fFbPos    : LREAL; // 反馈阀位 [%] / Feedback valve position [%]
    fDevLimit : LREAL; // 偏差容限 [%] / Deviation limit [%]
    tDevDelay : TIME;  // 偏差确认延时 [ms] / Deviation confirm delay [ms]
    fHystBand : LREAL; // 迟滞容带 [%] / Hysteresis band [%]
    bEnable   : BOOL;  // 监视使能 / Monitoring enable
END_VAR
VAR_OUTPUT
    eHealth        : E_DL_Ne107Status; // NE107 健康分级 / NE107 health classification
    bDeviationAlarm: BOOL; // 偏差确认告警 / Confirmed deviation alarm
    fDeviation     : LREAL; // 当前行程偏差 [%] / Current stroke deviation [%]
    uTravelAccum   : LREAL; // 累计行程 [%]（原规格非标类型按红线 2 改 LREAL）/ Accumulated travel [%]
    eErr           : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    fFbPrev   : LREAL;  // 上拍反馈锁存（行程增量与方向判据源）/ Previous feedback latch
    bFbPrevOk : BOOL;   // 上拍反馈有效性（首拍防假增量）/ Previous feedback validity
    fDevAbs   : LREAL;  // 偏差绝对值 / Absolute deviation
    fDelta    : LREAL;  // 反馈逐拍增量临时量 / Feedback per-cycle delta temp
    tonDev    : TON;    // 偏差确认定时器（单实例无条件刷新）/ Deviation confirm timer
    rDirUp    : R_TRIG; // 指令下转上换向沿（单实例无条件刷新）/ Up-reversal edge
    rDirDn    : R_TRIG; // 指令上转下换向沿（单实例无条件刷新）/ Down-reversal edge
    iCmdDir   : INT;    // 本拍指令方向（1 上 / -1 下 / 0 平）/ Command direction this cycle
    iDirPrev  : INT;    // 上拍指令方向 / Previous command direction
    fSnapUp   : LREAL;  // 上行换向反馈快照 / Feedback snapshot at up-reversal
    bSnapUpOk : BOOL;   // 上行快照有效 / Up snapshot valid
    fHystEst  : LREAL;  // 迟滞估计值 [%] / Hysteresis estimate [%]
    bHystTripped: BOOL; // 迟滞超带锁存 / Hysteresis over-band latch
    fFbGuard  : LREAL;  // 反馈实时守卫副本（内部判定统一用）/ Live feedback guard copy
END_VAR

// ---------- 实时反馈守卫副本：内部判定统一用此副本（对外无副本输出） ----------
fFbGuard := fFbPos;

// ---------- 使能为假：全输出复位（安全侧缺省） ----------
IF NOT bEnable THEN
    eHealth         := E_DL_Ne107Status.eUnknown; // 未监视态 / Unknown when disabled
    bDeviationAlarm := FALSE;
    fDeviation      := 0.0;
    uTravelAccum    := 0.0;
    eErr            := 0;
    bFbPrevOk   := FALSE;                     // 重置首拍防假增量 / Reset first-scan guard
    bSnapUpOk   := FALSE;
    fHystEst    := 0.0;
    bHystTripped := FALSE;
    iDirPrev    := 0;
    // 定时器与沿检测仍在下方无条件刷新（IN 条件含使能，禁能即静止）/ Timers refreshed unconditionally below
ELSE
    // ---------- 行程偏差绝对值（先算后喂定时器，禁先行使用） ----------
    fDeviation := fCmdPos - fFbGuard;         // 实时偏差 / Live deviation
    fDevAbs    := fDeviation;
    IF fDevAbs < 0.0 THEN
        fDevAbs := -fDevAbs;                  // 手工取反绝对值 / Manual absolute value
    END_IF
END_IF

// ---------- 无条件周期刷新：偏差 TON 与双向换向沿（各仅一次） ----------
tonDev(IN := bEnable AND (fDevAbs > fDevLimit) AND (fFbGuard >= -5.0) AND (fFbGuard <= 105.0),
       PT := tDevDelay);

// ---------- 指令方向判定（相邻拍指令差） ----------
iCmdDir := 0;
IF fCmdPos > fFbPrev THEN
    iCmdDir := 1;                             // 上行 / Rising
ELSIF fCmdPos < fFbPrev THEN
    iCmdDir := -1;                            // 下行 / Falling
END_IF
rDirUp(CLK := (iCmdDir = 1) AND (iDirPrev = -1)); // 下转上换向 / Reversal down-to-up
rDirDn(CLK := (iCmdDir = -1) AND (iDirPrev = 1)); // 上转下换向 / Reversal up-to-down

// ---------- 使能门控的主判定（禁能时跳过诊断结论更新） ----------
IF bEnable THEN
    // ---------- 反馈超量程：传感器故障态优先于偏差态 ----------
    IF (fFbGuard < -5.0) OR (fFbGuard > 105.0) THEN
        eHealth := E_DL_Ne107Status.eFailure; // 传感器故障最严级 / Sensor fault strictest
        eErr    := 16#0003_0375;              // 超量程码 / Out-of-range code
        bDeviationAlarm := FALSE;             // 偏差态被覆盖 / Deviation overridden
        fDeviation := 0.0;
        bFbPrevOk := FALSE;                   // 量程外不累积行程 / No travel accumulation
    ELSE
        // ---------- 偏差确认 ----------
        IF tonDev.Q THEN
            bDeviationAlarm := TRUE;          // 偏差确认成立 / Deviation confirmed
            eErr := 16#0003_0376;             // 确认超时码 / Confirm code
        ELSE
            bDeviationAlarm := FALSE;         // 未确认即撤销 / Withdrawn if unconfirmed
        END_IF

        // ---------- 累计行程：反馈逐拍绝对增量（寿命估计口径） ----------
        IF bFbPrevOk THEN
            fDelta := fFbGuard - fFbPrev;     // 逐拍增量 / Per-cycle delta
            IF fDelta < 0.0 THEN
                fDelta := -fDelta;            // 绝对增量 / Absolute delta
            END_IF
            uTravelAccum := uTravelAccum + fDelta; // 累积行程 / Accumulate
        END_IF
        bFbPrevOk := TRUE;
        fFbPrev   := fFbGuard;                // 锁存本拍反馈 / Latch feedback

        // ---------- 迟滞估计：下行换向时与上行快照配对 ----------
        IF rDirUp.Q THEN
            fSnapUp   := fFbGuard;            // 上行换向快照 / Up-reversal snapshot
            bSnapUpOk := TRUE;
        END_IF
        IF rDirDn.Q AND bSnapUpOk THEN
            fHystEst := fSnapUp - fFbGuard;   // 快照对差值 / Snapshot pair difference
            IF fHystEst < 0.0 THEN
                fHystEst := -fHystEst;        // 绝对迟滞 / Absolute hysteresis
            END_IF
            IF fHystEst > fHystBand THEN
                bHystTripped := TRUE;         // 超带锁存（需禁能复位）/ Over-band latch
            END_IF
        END_IF

        // ---------- NE107 分级仲裁（数值小者最严） ----------
        IF bHystTripped THEN
            eHealth := E_DL_Ne107Status.eOutOfSpec;       // 迟滞超带 / Out of spec
            IF eErr = 0 THEN
                eErr := 16#0003_0377;         // 迟滞超带码（不覆盖更严码）/ Hysteresis code
            END_IF
        ELSIF bDeviationAlarm THEN
            eHealth := E_DL_Ne107Status.eMaintenanceReq;  // 偏差确认 / Maintenance required
        ELSE
            eHealth := E_DL_Ne107Status.eOk;  // 监视中无异常 / Monitored, healthy
        END_IF
    END_IF
END_IF

END_FUNCTION_BLOCK
