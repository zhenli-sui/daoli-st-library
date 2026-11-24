(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DeviceParamVerify
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / MAX / R_TRIG / TON）
 * 功能描述 (Function)   : 把「组态期望参数块」与「设备回读参数块」逐项按逐项容差比对，
 *                         给出差异项数、首个超差项下标、最大偏差与其下标，以及
 *                         「一致 / 不一致」结论。不一致结论锁存，须显式确认才清除。
 *                         现场用途：伺服与变频器换板、参数被误改后设备带着错参数运行，
 *                         人工翻参数页核几十项既慢又漏；上电自动核对能把「参数被改」
 *                         从一条偶发工艺异常变成一条明确报警。
 *                         回读未就绪约定：回读块全部为零视为「设备尚未回传」，
 *                         在回读超时窗内持续等待，超时即判故障；该约定写死在本件，
 *                         调用方若确有「全零合法」的参数块，须自行叠加就绪位后再调用。
 * 出口契约 (Exit)       : bVerified 为「本轮核对全部项在容差内」；bMismatch 为锁存结论，
 *                         由 bAcknowledge 上升沿清除；nDiffCount / fMaxDev 等明细在核对拍
 *                         刷新并在结论驻留相保持（HMI 可同时看到「锁存结论」与「最近明细」）；
 *                         bError 只由 030D / 030E / 030F 三码置位，bReset 上升沿统一清除。
 * 不内联姊妹件的理由    : 姊妹件 FC_DL_ArrayDiffSummary 是「统一容差」的通用双数组比对；
 *                         本件是「逐项容差 + 结论锁存 + 回读超时」的设备参数域件。若复用该函数，
 *                         逐项容差会被拆成最多 64 次函数调用，破坏「单拍内完成一次完整核对」
 *                         的一致性（每次调用之间的数组不可能被冻结），故本件自带单次遍历循环，
 *                         两次循环的职责并不重复：一个算差异摘要，一个判设备参数一致性并锁存。
 * 开源溯源 (Origin)     : 来源标签 codesys-forge-devicereader。许可证：该示例页面未显式声明
 *                         许可，按最严口径处置——零代码行复制、零注释引用、零结构体搬运。
 *                         借鉴点仅为「读出 → 比对 → 出报告」三段式流程骨架与函数域划分。
 *                         状态机、逐项容差回落规则、结论锁存、非有限值处置、码位全部自有，
 *                         clean-room 独立实现。
 * 码位说明 (Codes)      : 信息级 16#0003_014D（比对本数越界已钳位）/ 014E（核对一致）/
 *                         014F（负容差已取绝对值）；故障级 16#0003_030D（回读出现非有限值）/
 *                         030E（回读超时未就绪）/ 030F（非法相位兜底）。
 *                         共 6 码，全部落在 R12 计划第 1.2 节本件码段内。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS / MAX / R_TRIG / TON
 * 红线自检 (Redline)    : 1 ✓ 零全局变量表依赖、零外部变量声明、零物理地址
 *                         2 ✓ 纯 IEC 61131-3，无指针、无厂商库
 *                         3 ✓ 数组先判界（遍历上界取钳位后的项数）、容差先收敛到正数、
 *                             非有限值前置拦截、循环带守卫、超时仅在等待相计时
 *                         4 ✓ 全变量中英双语同行注释
 *                         5 ✓ 六态 ENUM + CASE 全覆盖 + ELSE 兜底（030F）
 *                         6 ✓ R_TRIG / TON 实例在 CASE 之外每拍无条件刷新
 *                         7 ✓ END_FUNCTION_BLOCK 位于文件最后有效行
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R12 · Level 1 DL_Device 参数域校验）
 *   2026-11-15  v1.0.1  终审修复：事件码跨核对周期不清。原实现只在复位沿清 uErrorId，
 *                       一轮核对留下的 014E 会一直驻留：后续轮次的 014D / 014F 因「仅在
 *                       uErrorId 为零时置码」被永久压住，且不一致轮次里会出现「码说一致、
 *                       结论说不一致」。改为进入新一轮核对（空闲转等待）时清信息级码
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ParamVerifyPhase（归属 DL_Device，与本功能块同文件）
 * 含义: 参数核对流程的离散相位。步长留空位，便于后续插态。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ParamVerifyPhase :
(
    eIdle      := 0,     // 空闲：等待使能 / Idle: waiting for enable
    eWaiting   := 10,    // 等待：等设备回读就绪，同时跑回读超时 / Waiting for the readback or the timeout
    eComparing := 20,    // 比对：单拍内完成全项遍历 / Comparing: one pass over every item in a single scan
    eMatch     := 30,    // 一致：结论驻留，等待复位 / Match: verdict held until reset
    eMismatch  := 40,    // 不一致：结论锁存，等待确认 / Mismatch: latched until acknowledged
    eFault     := 99     // 故障：回读非法或超时，等待复位 / Fault: bad readback or timeout
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_ParamVerifyState（归属 DL_Device，与本功能块同文件）
 * 含义: 跨周期状态包，由调用方持有并在多台设备间独立维护。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_ParamVerifyState :
STRUCT
    bLastVerdict  : BOOL;     // 上次核对结论，TRUE = 一致 / Last verdict, TRUE means consistent
    nLastDiffCount : INT;     // 上次超差项数 [项] / Last out of tolerance count
    nLastFirstIdx : INT;      // 上次首个超差项下标，0 = 无 [索引] / Last first offending index
    fLastMaxDev   : REAL;     // 上次最大绝对偏差 [工程单位] / Last maximum absolute deviation
    uVerifyCount  : UDINT;    // 累计核对次数 [次] / Accumulated verification count
END_STRUCT
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_DeviceParamVerify
 * 调用约定: 每个扫描周期无条件调用一次；bEnable 为 FALSE 时相位与结论全部冻结。
 * 无状态泄漏: 除调用方持有的状态包外，全部状态驻留于实例私有 VAR，零全局引用。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_DeviceParamVerify
VAR_INPUT
    bEnable       : BOOL;                        // 使能，FALSE 时结论与相位冻结 / Enable, freezes the verdict when FALSE
    bReset        : BOOL;                        // 上升沿复位故障与结论锁存 / Rising edge clears fault and verdict latch
    bAcknowledge  : BOOL;                        // 上升沿确认「不一致」结论 / Rising edge acknowledges a mismatch
    nItemCount    : INT := 1;                    // 比对本数 [项]，域 1~64 / Item count, 1..64
    afExpected    : ARRAY[1..64] OF REAL;        // 组态期望参数块 [工程单位] / Configured expectation block
    afActual      : ARRAY[1..64] OF REAL;        // 设备回读参数块 [工程单位] / Device readback block
    afTolerance   : ARRAY[1..64] OF REAL;        // 逐项容差 [工程单位]，0 或负值回落默认 / Per item tolerance
    fDefaultTol   : REAL := 0.01;                // 默认容差 [工程单位]，域不小于 1E-6 / Default tolerance
    tVerifyTimeout : TIME := T#5S;               // 回读超时 [毫秒]，零表示不监控 / Readback timeout, zero disables it
END_VAR
VAR_OUTPUT
    bVerified     : BOOL;                        // 全部项在容差内 TRUE / All items within tolerance
    bMismatch     : BOOL;                        // 不一致结论锁存，需确认 / Mismatch latched until acknowledged
    nDiffCount    : INT;                         // 超差项数 [项] / Out of tolerance item count
    nFirstDiffIdx : INT;                         // 首个超差项下标，0 = 无 [索引] / First offending index
    fMaxDev       : REAL;                        // 最大绝对偏差 [工程单位] / Maximum absolute deviation
    nMaxDevIdx    : INT;                         // 最大偏差下标，0 = 无 [索引] / Index of the maximum deviation
    bError        : BOOL;                        // 故障级锁存，仅 030D~030F 置位 / Latched fault
    uErrorId      : UDINT;                       // 事件码，0 = 无事件 / Event code, zero means none
    eState        : E_DL_ParamVerifyPhase;       // 主状态机当前相位 / Current phase
END_VAR
VAR_IN_OUT
    stVerify      : ST_DL_ParamVerifyState;      // 跨周期状态：上次结论与累计核对次数 / Persistent state bag
END_VAR
VAR
    fbTrigReset   : R_TRIG;                      // 复位沿，CASE 之外每拍刷新 / Reset edge, refreshed outside CASE
    fbTrigAck     : R_TRIG;                      // 确认沿，CASE 之外每拍刷新 / Acknowledge edge, refreshed outside CASE
    fbTimeout     : TON;                         // 回读超时，CASE 之外每拍刷新 / Readback timer, refreshed outside CASE
    ePhase        : E_DL_ParamVerifyPhase := E_DL_ParamVerifyPhase.eIdle;  // 内部相位 / Internal phase
    bInit         : BOOL := FALSE;               // 首扫标志，首扫不做任何比对 / First scan flag, no comparison on it
    nCountUse     : INT;                         // 生效比对本数 [项] / Effective item count
    fTolDef       : REAL;                        // 生效默认容差 [工程单位] / Effective default tolerance
    fTolUse       : REAL;                        // 单项生效容差 [工程单位] / Per item effective tolerance
    fDev          : REAL;                        // 单项绝对偏差 [工程单位] / Per item deviation
    fExp          : REAL;                        // 期望值快照 [工程单位] / Expected snapshot
    fAct          : REAL;                        // 回读值快照 [工程单位] / Actual snapshot
    bNonFinite    : BOOL;                        // 本轮出现非有限值 / Non finite value encountered
    bReadbackReady : BOOL;                       // 回读块已非全零 / Readback block is no longer all zero
    bAckUse       : BOOL;                        // 本轮确认沿快照 / Acknowledge edge snapshot
    nGuard        : DINT;                        // 循环守卫 / Loop guard
    i             : INT;                         // 遍历索引 [项] / Loop index
END_VAR
VAR CONSTANT
    DL_ITEM_MAX   : INT  := 64;                  // 项数上限，与数组维度一致 [项] / Item count ceiling
    DL_TOL_MIN    : REAL := 1.0E-6;              // 最小容差 [工程单位] / Minimum tolerance
    DL_ABS_MAX    : REAL := 1.0E30;              // 有限值判定上界 [工程单位] / Finite value bound
    DL_ZERO_EPS   : REAL := 1.0E-9;              // 回读就绪判零容差 [工程单位] / Readback zero tolerance
    DL_NO_TIMEOUT : TIME := T#0S;                // 超时关闭标记 [毫秒] / Timeout disabled marker
    DL_GUARD_MAX  : DINT := 128;                 // 循环守卫上限 [次] / Loop guard limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜边沿与定时器每拍无条件刷新（严禁放进 CASE 或 IF 内部）
 *      Edge instances and the timer refreshed unconditionally on every scan
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTrigAck(CLK := bAcknowledge);
fbTimeout(IN := (ePhase = E_DL_ParamVerifyPhase.eWaiting) AND bEnable, PT := tVerifyTimeout);
bAckUse := fbTrigAck.Q;

(*------------------------------------------------------------------------------
 * 段 1｜首扫闸：未初始化的回读块全为零，直接比对会误判不一致，首扫只做初始化
 *      First scan gate: an uninitialised readback block would be misjudged
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    bInit  := TRUE;
    ePhase := E_DL_ParamVerifyPhase.eIdle;
    eState := ePhase;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜复位沿：故障、结论锁存、事件码一次性清干净，相位回空闲
 *      Reset edge clears the fault, the latch and the event code in one go
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    bError    := FALSE;
    bMismatch := FALSE;
    bVerified := FALSE;
    uErrorId  := 16#0000_0000;
    ePhase    := E_DL_ParamVerifyPhase.eIdle;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜比对本数钳位：越界钳位后照常核对，只发信息码
 *      Item count clamp: clamp and keep verifying, informational only
 *-----------------------------------------------------------------------------*)
nCountUse := nItemCount;
IF nCountUse < 1 THEN
    nCountUse := 1;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0003_014D;
    END_IF
ELSIF nCountUse > DL_ITEM_MAX THEN
    nCountUse := DL_ITEM_MAX;
    IF uErrorId = 16#0000_0000 THEN
        uErrorId := 16#0003_014D;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜默认容差收敛：取绝对值后再抬到下限，非有限值一律落到下限
 *      Default tolerance: absolute value, floored to the minimum
 *-----------------------------------------------------------------------------*)
fTolDef := ABS(fDefaultTol);
IF NOT (fTolDef >= DL_TOL_MIN) THEN
    fTolDef := DL_TOL_MIN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机：六态全覆盖 + ELSE 兜底
 *      Main state machine with every enum member and an ELSE fallback
 *-----------------------------------------------------------------------------*)
IF bEnable THEN

    CASE ePhase OF
        E_DL_ParamVerifyPhase.eIdle:
            (* 空闲转为等待：开新一轮核对，先清上一轮的信息级码，其余出口保持 *)
            (* Idle arms the wait phase and clears the previous cycle's info code *)
            uErrorId   := 16#0000_0000;     // 清陈旧信息级码（014E 若不清会压住本轮的 014D / 014F，并与本轮结论矛盾） / Clear the stale info code
            bNonFinite := FALSE;
            ePhase     := E_DL_ParamVerifyPhase.eWaiting;

        E_DL_ParamVerifyPhase.eWaiting:
            (* 就绪判据：回读块出现任何一个非零量即视为已回传 *)
            (* Readiness: any non zero value in the readback block counts as arrived *)
            bReadbackReady := FALSE;
            i              := 1;
            nGuard         := 0;
            WHILE (i <= nCountUse) AND (NOT bReadbackReady) AND (nGuard < DL_GUARD_MAX) DO
                nGuard := nGuard + 1;
                IF NOT (ABS(afActual[i]) <= DL_ZERO_EPS) THEN
                    bReadbackReady := TRUE;
                END_IF
                i := i + 1;
            END_WHILE;

            IF tVerifyTimeout = DL_NO_TIMEOUT THEN
                (* 调用方关闭超时监控：直接进入比对 *)
                (* Timeout monitoring disabled by the caller: go straight to comparing *)
                ePhase := E_DL_ParamVerifyPhase.eComparing;
            ELSIF fbTimeout.Q AND (NOT bReadbackReady) THEN
                bError    := TRUE;
                uErrorId  := 16#0003_030E;
                bVerified := FALSE;
                ePhase    := E_DL_ParamVerifyPhase.eFault;
            ELSIF bReadbackReady THEN
                ePhase := E_DL_ParamVerifyPhase.eComparing;
            END_IF

        E_DL_ParamVerifyPhase.eComparing:
            (* 单拍单次遍历：逐项容差、非有限值、首差、最大偏差一次算全 *)
            (* One pass computes tolerance fallback, non finite values, first and worst item *)
            nDiffCount    := 0;
            nFirstDiffIdx := 0;
            fMaxDev       := 0.0;
            nMaxDevIdx    := 0;
            bNonFinite    := FALSE;
            i             := 1;
            nGuard        := 0;

            WHILE (i <= nCountUse) AND (nGuard < DL_GUARD_MAX) DO
                nGuard := nGuard + 1;
                fExp   := afExpected[i];
                fAct   := afActual[i];

                (* 容差回落：负值取绝对值并留痕，零值回落默认，最后抬到下限 *)
                (* Tolerance fallback: absolute value, then default, then the floor *)
                fTolUse := afTolerance[i];
                IF fTolUse < 0.0 THEN
                    fTolUse := ABS(fTolUse);
                    IF uErrorId = 16#0000_0000 THEN
                        uErrorId := 16#0003_014F;
                    END_IF
                END_IF
                IF fTolUse <= 0.0 THEN
                    fTolUse := fTolDef;
                END_IF
                fTolUse := MAX(fTolUse, DL_TOL_MIN);

                IF NOT ((fExp >= -DL_ABS_MAX) AND (fExp <= DL_ABS_MAX))
                   OR NOT ((fAct >= -DL_ABS_MAX) AND (fAct <= DL_ABS_MAX)) THEN
                    (* 非有限值：该项计超差，且不参与最大偏差竞争（非数比较无意义）*)
                    (* Non finite: counted as a difference, excluded from the worst deviation *)
                    bNonFinite := TRUE;
                    nDiffCount := nDiffCount + 1;
                    IF nFirstDiffIdx = 0 THEN
                        nFirstDiffIdx := i;
                    END_IF
                ELSE
                    fDev := ABS(fExp - fAct);
                    IF fDev > fTolUse THEN
                        nDiffCount := nDiffCount + 1;
                        IF nFirstDiffIdx = 0 THEN
                            nFirstDiffIdx := i;
                        END_IF
                    END_IF
                    IF fDev > fMaxDev THEN
                        fMaxDev    := fDev;
                        nMaxDevIdx := i;
                    END_IF
                END_IF

                i := i + 1;
            END_WHILE;

            IF bNonFinite THEN
                (* 数据源已坏：锁故障，结论与明细同时落盘供取证 *)
                (* Broken data source: latch a fault and store the details for evidence *)
                bError    := TRUE;
                uErrorId  := 16#0003_030D;
                bVerified := FALSE;
                stVerify.bLastVerdict   := FALSE;
                stVerify.nLastDiffCount := nDiffCount;
                stVerify.nLastFirstIdx  := nFirstDiffIdx;
                stVerify.fLastMaxDev    := fMaxDev;
                ePhase := E_DL_ParamVerifyPhase.eFault;
            ELSIF nDiffCount = 0 THEN
                (* 一致：清锁存，累计次数只在进入一致相时加一 *)
                (* Match: clear the latch, the counter increments only on entry *)
                bVerified := TRUE;
                bMismatch := FALSE;
                IF uErrorId = 16#0000_0000 THEN
                    uErrorId := 16#0003_014E;
                END_IF
                stVerify.bLastVerdict   := TRUE;
                stVerify.nLastDiffCount := 0;
                stVerify.nLastFirstIdx  := 0;
                stVerify.fLastMaxDev    := 0.0;
                stVerify.uVerifyCount   := stVerify.uVerifyCount + 1;
                ePhase := E_DL_ParamVerifyPhase.eMatch;
            ELSE
                (* 不一致：结论锁存，明细随结论一同落盘 *)
                (* Mismatch: latch the verdict and store the details *)
                bVerified := FALSE;
                bMismatch := TRUE;
                stVerify.bLastVerdict   := FALSE;
                stVerify.nLastDiffCount := nDiffCount;
                stVerify.nLastFirstIdx  := nFirstDiffIdx;
                stVerify.fLastMaxDev    := fMaxDev;
                stVerify.uVerifyCount   := stVerify.uVerifyCount + 1;
                ePhase := E_DL_ParamVerifyPhase.eMismatch;
            END_IF

        E_DL_ParamVerifyPhase.eMatch:
            (* 一致相驻留：结论保持不变，只认复位沿（在段 2 统一处理）*)
            (* Match dwell: the verdict stays, only the reset edge leaves it *)
            bVerified := TRUE;
            bMismatch := FALSE;

        E_DL_ParamVerifyPhase.eMismatch:
            (* 不一致相驻留：锁存结论与明细，确认沿清除锁存并重新武装 *)
            (* Mismatch dwell: the latch is cleared by the acknowledge edge only *)
            bMismatch := TRUE;
            bVerified := FALSE;
            IF bAckUse THEN
                bMismatch := FALSE;
                ePhase    := E_DL_ParamVerifyPhase.eIdle;
            END_IF

        E_DL_ParamVerifyPhase.eFault:
            (* 故障相驻留：输出冻结，只认复位沿 *)
            (* Fault dwell: the outputs are frozen until the reset edge *)
            bError := TRUE;

        ELSE
            (* 兜底：枚举被在线改坏或跨版本不兼容，置终端安全态并锁存 *)
            (* Fallback: terminal safe state with the segment last code *)
            bError    := TRUE;
            uErrorId  := 16#0003_030F;
            bVerified := FALSE;
            ePhase    := E_DL_ParamVerifyPhase.eFault;
    END_CASE

END_IF

(*------------------------------------------------------------------------------
 * 段 6｜相位出口：内部相位镜像到出口引脚
 *      Phase mirror to the output pin
 *-----------------------------------------------------------------------------*)
eState := ePhase;
END_FUNCTION_BLOCK
