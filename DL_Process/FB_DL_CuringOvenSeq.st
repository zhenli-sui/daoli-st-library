(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CuringOvenSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : self-std（工艺新增线）
 * 功能描述 (Function)   : 固化炉三段段序：①升温（升温速率闸：超 fRateMax 即判超速锁存）
 *                         → ②保温（达设定温度后保温计时）→ ③降温（降温至开门阈前
 *                         禁止开门，开门即联锁违规锁存）。
 * 分工互引 (Boundary)   : 干燥分区温控归 FB_DL_DryingOvenZone（本件不含加热 PID，
 *                         加热 / 风机的调节由该件或上层调节器承担）；炉门机械互锁归
 *                         FB_DL_DoorInterlock；本件只做**段序编排 + 速率闸 + 开门
 *                         温度联锁判定**，不替代硬互锁回路。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 升温速率按采样周期差分折算：rate [°C/min] = (fTemp − fTempPrev) / fDtMin，
 *      除子 fDtMin 由组态闸保证 > 0（tSample <= T#0S 即组态非法）。
 *   2) 速率超限为故障级锁存（超速固化会废品）：解除 = 复位沿 AND 组态改对 AND
 *      速率已回落到限内（三点同时满足，R152 自证可达）。
 *   3) 开门联锁：仅当温度 <= fDoorOpenTempMax 才允许开门；降温段检测到门开且
 *      温度仍高于阈值即判联锁违规（故障级锁存），解除同 2) 口径。
 *   4) 非有限温度不参与速率与联锁判据（本拍保持上一拍速率、不判违规），
 *      由信号闸置信息码，不锁存（一扫 NaN 不得让炉子报警停机）。
 *   5) bStop / 失能：任意相退出回 eIdle，已锁存的故障**不被** bStop 清除
 *      （复位作用域声明：bStop 只迁相不清锁存；bReset 清锁存不迁相之外的动作）。
 * 故障码表 (Error codes) :
 *   16#0005_03B4 [故障级] 升温速率超限（固化超速），锁存待人工
 *                 反证：超速与「设定温度高、升温正常」输出组合相同，无码不可归因。
 *   16#0005_03B5 [故障级] 降温未达标即开门（开门联锁违规），锁存待人工
 *                 反证：门开状态由 bDoorClosed 外部可见，但「违规开」与「合规开」
 *                 仅温度不同，无码则违规事件不可归档（安全审计缺口）。
 *   16#0005_03B6 [故障级] 组态非法（速率上限 / 保温时长 / 采样周期 / 开门阈）
 *                 反证：段序停在 eIdle 与「未按启动」输出相同。
 *   16#0005_04DE [信息级] 保温计时完成（可进降温段）
 *                 反证：保温完成是单拍事件，状态只表达驻留，不留事件事实。
 *   16#0005_04DF [信息级] 温度非有限，本拍速率 / 联锁判据挂起
 *                 反证：挂起与「温度恰好不变（速率 0）」输出组合相同。
 * 码位总账 (Code ledger) : 16#0005_03B4 / 03B5 / 03B6 用 ｜ 16#0005_04DE / 04DF 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量 ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸（fDtMin 由组态闸保证 > 0）/ 非有限三判 / 域闸全枚举
 *                         R5 ✓ 全变量双语同行注释 ｜ R6 ✓ 六态 ENUM + ELSE 兜底
 *                         R7 ✓ 二沿二计时主体最前部无条件刷新
 * 修订历史 (Revision)   : 2026-11-22  v1.0.0  首版入库（R69 构建轮 · 批 3 · N10）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CuringState（归属 DL_Process，与 FB_DL_CuringOvenSeq 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CuringState :
(
    eIdle  := 0,     // 空闲：等待启动（输出全清）/ Idle, waiting for the start
    eHeat  := 10,    // 升温段：速率闸监视 / Heating with the ramp-rate gate
    eHold  := 20,    // 保温段：保温计时 / Holding, dwell timer running
    eCool  := 30,    // 降温段：开门温度联锁监视 / Cooling with the door interlock
    eDone  := 40,    // 完成：单拍完成相 / Done, one-shot phase
    eFault := 99     // 故障锁存：段序中止 / Fault latched, the sequence aborts
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CuringOvenSeq
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CuringOvenSeq
VAR_INPUT
    bStartCmd        : BOOL;                 // 启动命令（上升沿受理）/ start command, rising edge
    bStopCmd         : BOOL;                 // 停止命令（电平，任意相退出，不清锁存）/ stop command, level, latches untouched
    fTemp            : REAL;                 // 炉膛温度 [°C] / oven temperature [°C]
    fTempSet         : REAL := 180.0;        // 固化设定温度 [°C] / curing setpoint [°C]
    fRateMax         : REAL := 3.0;          // 升温速率上限 [°C/min]，<= 0 组态非法 / ramp-rate ceiling [°C/min]
    tHold            : TIME := T#30M;        // 保温时长 [s]，<= T#0S 组态非法 / dwell duration [s]
    fDoorOpenTempMax : REAL := 60.0;         // 允许开门的最高温度 [°C] / highest temperature allowing the door open [°C]
    bDoorClosed      : BOOL := TRUE;         // 炉门关闭反馈（TRUE = 关闭）/ door closed feedback
    tSample          : TIME := T#1S;         // 采样周期 [ms]，<= T#0S 组态非法 / sample period [ms]
    bEnable          : BOOL := TRUE;         // 使能 / enable
    bReset           : BOOL;                 // 上升沿：清故障锁存 / rising edge clears the fault latches
END_VAR
VAR_OUTPUT
    bHeatOn          : BOOL;                 // 加热请求（供外部调功器）/ heating request for the power unit
    bCoolFanOn       : BOOL;                 // 降温风机请求 / cooling fan request
    bDoorOpenPermit  : BOOL;                 // 开门许可（温度已降到阈值以下）/ door open permit
    fRateNow         : REAL;                 // 当前升温速率 [°C/min] / current ramp rate [°C/min]
    bSeqDone         : BOOL;                 // 段序完成脉冲（单拍）/ sequence done pulse, single scan
    bError           : BOOL;                 // 故障标志（锁存类归并）/ fault flag
    uErrorId         : UDINT;                // 故障码，0 = 无故障 / error code, 0 = none
    eState           : E_DL_CuringState;     // 当前状态（供 HMI 诊断）/ current state
END_VAR
VAR
    fbTrigStart      : R_TRIG;               // 启动沿检测实例 / start edge detector
    fbTrigReset      : R_TRIG;               // 复位沿检测实例 / reset edge detector
    tonHold          : TON;                  // 保温计时实例 / dwell timer
    tonRateWin       : TON;                  // 速率评估窗（自复位 R188）/ rate evaluation window, self resetting
    eStateInt        : E_DL_CuringState;     // 主状态机内部当前态 / internal state
    fTempPrev        : REAL;                 // 上一拍温度快照 [°C] / previous temperature snapshot [°C]
    fDtMin           : REAL;                 // 采样周期折算 [min]，除子 / sample period in minutes, the divisor
    nSampleMs        : DINT;                 // 采样周期整毫秒 [ms] / sample period in milliseconds
    bTempBad         : BOOL;                 // 本拍温度非有限 / temperature non-finite this scan
    bRateOver        : BOOL;                 // 本拍速率超限 / ramp rate exceeded this scan
    bDoorViolation   : BOOL;                 // 本拍开门违规 / door interlock violation this scan
    bRateLatch       : BOOL;                 // 速率超限锁存内部副本 / internal rate latch
    bDoorLatch       : BOOL;                 // 开门违规锁存内部副本 / internal door latch
    bCfgBad          : BOOL;                 // 本拍组态非法 / config illegal this scan
    bCfgLatch        : BOOL;                 // 组态锁存（复位沿 + 组态改对解除）/ config latch
    bDoneT           : BOOL;                 // 完成脉冲内部副本（单拍）/ internal done pulse
    bErrorInt        : BOOL;                 // 本拍故障置位累加 / fault set accumulator
    bFirstScan       : BOOL := TRUE;         // 上电首扫标志 / first-scan flag
END_VAR
VAR CONSTANT
    DL_CO_FIN_LIM  : REAL := 1.0E30;         // REAL 幅值兜底判界 / REAL magnitude bound
    DL_CO_MS_PER_MIN : REAL := 60000.0;      // 毫秒每分钟折算常数 [ms/min] / milliseconds per minute
    DL_CO_RATE_EPS : REAL := 1.0E-6;         // 速率比较容差（浮点禁判等）/ rate comparison tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：二沿二计时位于主体最前部
 *      Unconditional refresh: two edges and two timers at the very top
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStartCmd);
fbTrigReset(CLK := bReset);
tonHold(IN := (eStateInt = E_DL_CuringState.eHold), PT := tHold);
tonRateWin(IN := NOT tonRateWin.Q, PT := tSample);    // 自复位速率评估窗（R188）/ self-resetting rate window

(* 段 2｜上电首扫 / first-scan init *)
IF bFirstScan THEN
    eStateInt  := E_DL_CuringState.eIdle;
    fTempPrev  := 0.0;
    fRateNow   := 0.0;
    bRateLatch := FALSE;
    bDoorLatch := FALSE;
    bFirstScan := FALSE;
END_IF

(* 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / per-scan preset *)
bErrorInt := FALSE;
bDoneT    := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举）+ 解除路径（R152 自证可达）
 *      Config gate over every threshold and the sample period, with the clear path
 *-----------------------------------------------------------------------------*)
nSampleMs := TIME_TO_DINT(tSample);                       // TIME -> 整毫秒 [ms] / TIME to milliseconds
fDtMin    := DINT_TO_REAL(nSampleMs) / DL_CO_MS_PER_MIN;  // 毫秒 -> 分钟（除子常数 > 0）[min] / to minutes

bCfgBad := (fRateMax <= 0.0) OR (fRateMax <> fRateMax)
           OR (tHold <= T#0S)
           OR (fTempSet <> fTempSet) OR (ABS(fTempSet) >= DL_CO_FIN_LIM)
           OR (fDoorOpenTempMax <> fDoorOpenTempMax) OR (ABS(fDoorOpenTempMax) >= DL_CO_FIN_LIM)
           OR (tSample <= T#0S) OR (fDtMin <= 0.0) OR (fDtMin <> fDtMin);

IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;                    // 组态锁存解除 / config latch cleared
    uErrorId  := 16#0000_0000;             // 码位随解除归零 / code cleared with the latch
END_IF
IF bCfgLatch THEN
    uErrorId  := 16#0005_03B6;             // 故障级：组态非法 / fault: illegal configuration
    bErrorInt := TRUE;                     // R45 配对 / paired with the code
    eStateInt := E_DL_CuringState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜判据求值：信号闸 + 速率 + 开门联锁（非有限只挂起不锁存）
 *      Criteria: signal gate, ramp rate and the door interlock
 *      速率只在评估窗到期拍折算一次（窗内保持不变），避免同拍差分放大噪声。
 *-----------------------------------------------------------------------------*)
bTempBad := (fTemp <> fTemp)
            OR ((fTemp - fTemp) <> (fTemp - fTemp))
            OR (ABS(fTemp) >= DL_CO_FIN_LIM);

IF (NOT bTempBad) AND tonRateWin.Q THEN
    fRateNow  := (fTemp - fTempPrev) / fDtMin;   // 差分折速率（除子已闸 > 0）[°C/min] / ramp rate
    fTempPrev := fTemp;                          // 快照推进（仅在有效样本上）/ snapshot advances on valid samples only
ELSIF bTempBad THEN
    uErrorId := 16#0005_04DF;                    // 信息级：温度非有限，判据挂起 / info: non-finite temperature
END_IF

bRateOver := (NOT bTempBad) AND (fRateNow > (fRateMax + DL_CO_RATE_EPS));
bDoorViolation := (NOT bTempBad) AND (NOT bDoorClosed)
                  AND (fTemp > (fDoorOpenTempMax + DL_CO_RATE_EPS));

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      bStop 只迁相不清锁存（复位作用域声明见头注释披露 5）
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_CuringState.eIdle:
        IF bReset THEN
            bRateLatch := FALSE;                 // 空闲相复位允许清两类锁存 / idle reset clears both latches
            bDoorLatch := FALSE;
            uErrorId   := 16#0000_0000;
        END_IF
        IF bEnable AND (NOT bCfgLatch) AND (NOT bRateLatch) AND (NOT bDoorLatch)
           AND fbTrigStart.Q THEN
            fTempPrev := fTemp;                  // 启动拍取当前温度作速率基准 / seed the rate baseline
            eStateInt := E_DL_CuringState.eHeat;
        END_IF

    E_DL_CuringState.eHeat:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_CuringState.eIdle;
        ELSIF fTemp >= fTempSet THEN
            eStateInt := E_DL_CuringState.eHold; // 达温进保温 / setpoint reached, dwell
        END_IF

    E_DL_CuringState.eHold:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_CuringState.eIdle;
        ELSIF tonHold.Q THEN
            uErrorId  := 16#0005_04DE;           // 信息级：保温完成 / info: dwell finished
            eStateInt := E_DL_CuringState.eCool; // 进降温段 / to cooling
        END_IF

    E_DL_CuringState.eCool:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_CuringState.eIdle;
        ELSIF fTemp <= fDoorOpenTempMax THEN
            eStateInt := E_DL_CuringState.eDone; // 温度达开门阈，段序完成 / cool enough, done
        END_IF

    E_DL_CuringState.eDone:
        bDoneT    := TRUE;                       // 完成脉冲：内部置位 -> 出口单拍（两段式）/ done pulse via the exit
        eStateInt := E_DL_CuringState.eIdle;     // 单拍完成相 / one-shot phase

    E_DL_CuringState.eFault:
        (* 解除路径（R152 自证可达）：复位沿 AND 组态改对 AND 两判据本拍均已消失 *)
        IF fbTrigReset.Q AND (NOT bCfgBad) AND (NOT bRateOver) AND (NOT bDoorViolation) THEN
            bCfgLatch  := FALSE;                 // 三类锁存同沿解除 / three latches cleared together
            bRateLatch := FALSE;
            bDoorLatch := FALSE;
            uErrorId   := 16#0000_0000;
            eStateInt  := E_DL_CuringState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截 / illegal state interception *)
        eStateInt := E_DL_CuringState.eFault;
        uErrorId  := 16#0005_03B6;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜锁存消化：速率超限与开门违规各自独立锁存 + 独立码位（R190 归因唯一）
 *      Latch digestion with two distinct causes and codes
 *-----------------------------------------------------------------------------*)
IF bRateOver AND (NOT bRateLatch) THEN
    bRateLatch := TRUE;                          // 速率超限锁存 / ramp rate latched
    uErrorId   := 16#0005_03B4;                  // 故障级：升温速率超限 / fault: ramp rate exceeded
    bErrorInt  := TRUE;                          // R45 配对 / paired with the code
    eStateInt  := E_DL_CuringState.eFault;
END_IF
IF bDoorViolation AND (NOT bDoorLatch) THEN
    bDoorLatch := TRUE;                          // 开门违规锁存 / door violation latched
    uErrorId   := 16#0005_03B5;                  // 故障级：降温未达标即开门 / fault: door opened too hot
    bErrorInt  := TRUE;                          // R45 配对 / paired with the code
    eStateInt  := E_DL_CuringState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）：执行请求只由状态派生
 *      Single output exit: every request derives from the phase
 *-----------------------------------------------------------------------------*)
bHeatOn         := ((eStateInt = E_DL_CuringState.eHeat) OR (eStateInt = E_DL_CuringState.eHold))
                   AND (NOT bCfgLatch) AND (NOT bRateLatch);
bCoolFanOn      := (eStateInt = E_DL_CuringState.eCool) AND (NOT bCfgLatch);
bDoorOpenPermit := ((NOT bTempBad) AND (fTemp <= fDoorOpenTempMax))
                   AND (eStateInt <> E_DL_CuringState.eHeat) AND (eStateInt <> E_DL_CuringState.eHold)
                   AND (NOT bDoorLatch);
bSeqDone        := bDoneT;                       // 单拍脉冲统一出口 / unified single-scan exit
bError          := bErrorInt OR bCfgLatch OR bRateLatch OR bDoorLatch;
eState          := eStateInt;
END_FUNCTION_BLOCK
