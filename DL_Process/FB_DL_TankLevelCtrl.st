(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TankLevelCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / F_TRIG / R_TRIG / ABS / MAX / MIN，
 *                         零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 储罐液位双泵轮值公开工艺语义（行业池，参考库内
 *                         DutyStandbyRotation 轮值范式行为定义），本件带
 *                         液位回差为工艺件，道莅 clean-room 防御性实现，
 *                         未复制任何外部源码行
 * 功能描述 (Function)   : 储罐液位双泵轮值+联锁件。Lo 启 Hi 停回差带控制；
 *                         双泵交替轮值：运行时长达标或手动切换沿交棒，
 *                         停止侧安全执行；交棒时新主泵启确认后才停旧泵
 *                         （不断流时序写死）；最短运行/停机防频启；
 *                         HiHi/LoLo 独立硬联锁直接切输出不进状态机（独立窗）。
 * 码位     (Codes)      : 16#0005_00B2 信息级：液位非有限冻结投切、交棒等待
 *                                      提示（不置 bError）
 *                         16#0005_00B3 故障级：双泵反馈双失效（锁存）
 *                         16#0005_00B4 故障级：硬联锁触发（条件锁存，
 *                                      液位回带自愈解除）
 *                         16#0005_00B5 故障级：状态非法（ELSE 兜底，锁存）
 *                         16#0005_00B6 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 液位非有限（x<>x 自反判加幅值界）冻结投切保持现状；
 *                         2 双泵反馈双失效锁故障，可达解除路径：双泵停（指令
 *                           双 FALSE）后自清；
 *                         3 TON/R_TRIG/F_TRIG 实例每拍无条件刷新；
 *                         4 CASE 带 ELSE 锁安全侧（双泵停）；
 *                         5 HiHi/LoLo 独立窗直接作用于输出，不进状态机。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 16）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_TankPumpState（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TankPumpState :
(
    eIdle    := 0,    // 待机：双泵停等待启泵液位 / Idle, both pumps off awaiting level
    eLeadRun := 10,   // 单主泵运行态 / Lead running state
    eSwapWait := 20,    // 交棒等待态：新主泵已启待反馈确认 / Swap wait, new lead started awaiting feedback
    eFault   := 99    // 故障：锁存等待复归 / Fault, latched until recovered
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_TankLevelCtrl
 * 调用约定: 每个扫描周期无条件调用一次；液位与硬联锁信号经引脚注入。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_TankLevelCtrl
VAR_INPUT
    fLevel  : REAL := 50.0;           // 液位实测 [百分数] / Measured level [%]
    bHiHi   : BOOL := FALSE;          // 高高液位硬联锁（独立信号）/ HiHi hard interlock, independent
    bLoLo   : BOOL := FALSE;          // 低低液位硬联锁（独立信号）/ LoLo hard interlock, independent
    bP1Fb   : BOOL := FALSE;          // 泵 1 运行反馈 / Pump 1 running feedback
    bP2Fb   : BOOL := FALSE;          // 泵 2 运行反馈 / Pump 2 running feedback
    bAuto   : BOOL := FALSE;          // 自动模式 / Auto mode
    bSwap   : BOOL := FALSE;          // 手动轮换沿 / Manual swap edge
    fLoStart: REAL := 30.0;           // 启泵液位阈 [百分数]（可增引脚）/ Pump start level [%], added pin
    fHiStop : REAL := 80.0;           // 停泵液位阈 [百分数]（可增引脚）/ Pump stop level [%], added pin
    tMinRun : TIME := T#30S;          // 最短运行时长 [毫秒] / Minimum run duration [ms]
    tMinOff : TIME := T#30S;          // 最短停机时长 [毫秒] / Minimum off duration [ms]
    tRunSwap: TIME := T#12H;          // 运行时长轮值阈 [毫秒] / Run-time swap threshold [ms]
    tHandover: TIME := T#10S;         // 交棒确认窗口 [毫秒] / Handover confirm window [ms]
END_VAR
VAR_OUTPUT
    bP1Req  : BOOL;                   // 泵 1 启动指令 / Pump 1 start command
    bP2Req  : BOOL;                   // 泵 2 启动指令 / Pump 2 start command
    bLead   : UINT;                   // 当前主泵号 [1 或 2] / Current lead pump [1 or 2]
    bError  : BOOL;                   // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId: UDINT;                  // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigSwap: R_TRIG;                // 手动轮换沿检测，每拍无条件刷新 / Manual swap edge detector
    tonMinRun: TON;                   // 最短运行计时，每拍无条件刷新 / Minimum run timer, refreshed every scan
    tonMinOff: TON;                   // 最短停机计时，每拍无条件刷新 / Minimum off timer, refreshed every scan
    tonRunTim: TON;                   // 主泵运行时长计时，每拍无条件刷新 / Lead run-time timer, refreshed every scan
    tonHandov: TON;                   // 交棒确认计时，每拍无条件刷新 / Handover confirm timer, refreshed every scan
    eState   : E_DL_TankPumpState;    // 内部状态机 / Internal state machine
    bLead1   : BOOL;                  // 主泵 1 标志 / Lead is pump 1 flag
    bLvlOk   : BOOL;                  // 液位输入有效 / Level input validity
    bStartReq: BOOL;                  // 液位低启泵请求 / Level-low start request
    bStopReq : BOOL;                  // 液位高停泵请求 / Level-high stop request
    bSwapReq : BOOL;                  // 本拍轮换请求 / Swap request this scan
    bBothFb  : BOOL;                  // 双泵反馈同时有效 / Both feedbacks valid
    bFbDualFail: BOOL;                // 双泵反馈双失效 / Both feedbacks failed
    bSwapWait: BOOL;                  // 交棒等待中 / Handover waiting flag
    bIntrlk  : BOOL;                  // 硬联锁激活 / Hard interlock active flag
END_VAR
VAR CONSTANT
    DL_TLC_FIN  : REAL := 1.0E30;     // REAL 有限幅值判界 / REAL finiteness magnitude bound
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigSwap(CLK := bSwap);                              // 手动轮换沿检测 / Manual swap edge detection
tonMinRun(IN := (bP1Req OR bP2Req) AND (eState = eLeadRun), PT := tMinRun); // 最短运行计时 / Minimum run timing
tonMinOff(IN := (NOT (bP1Req OR bP2Req)) AND (eState = eIdle), PT := tMinOff); // 最短停机计时 / Minimum off timing
tonRunTim(IN := (eState = eLeadRun) AND (bP1Req OR bP2Req), PT := tRunSwap); // 运行时长轮值计时 / Run-time rotation timing
tonHandov(IN := bSwapWait, PT := tHandover);          // 交棒确认计时 / Handover confirm timing

// ---- 段 2｜输入有效性与回差判据 ------------------------------------------------
bLvlOk := (fLevel = fLevel) AND (ABS(fLevel) < DL_TLC_FIN); // 液位有限 / Level finite
bStartReq := bLvlOk AND (fLevel < fLoStart);          // 液位低于启泵阈 / Level below start threshold
bStopReq  := bLvlOk AND (fLevel > fHiStop);           // 液位高于停泵阈 / Level above stop threshold

// ---- 段 3｜状态机（CASE 带 ELSE 锁安全侧：双泵停）--------------------------------
CASE eState OF
    eIdle:
        bP1Req := FALSE;                              // 待机双泵停 / Both off in idle
        bP2Req := FALSE;                              // 待机双泵停 / Both off in idle
        IF bAuto AND bLvlOk AND bStartReq AND (NOT bLoLo) AND tonMinOff.Q THEN
            eState := eLeadRun;                       // 低液位且停机时满启主泵 / Level low and off-time met, start lead
        END_IF
    eLeadRun:
        IF bLead1 THEN
            bP1Req := bAuto AND (NOT bStopReq) AND (NOT bHiHi); // 主泵 1 指令 / Pump 1 command
            bP2Req := FALSE;                          // 备泵停 / Standby off
        ELSE
            bP2Req := bAuto AND (NOT bStopReq) AND (NOT bHiHi); // 主泵 2 指令 / Pump 2 command
            bP1Req := FALSE;                          // 备泵停 / Standby off
        END_IF
        bSwapReq := (tonRunTim.Q OR rTrigSwap.Q) AND bAuto AND bLvlOk; // 轮值时长满或手动沿请求轮换 / Rotation or manual swap request
        IF bSwapReq AND (NOT bHiHi) AND (NOT bLoLo) THEN
            IF bLead1 THEN
                bP2Req := TRUE;                       // 交棒先启新主泵（不断流时序）/ Handover starts new lead first
            ELSE
                bP1Req := TRUE;                       // 交棒先启新主泵 / Handover starts new lead first
            END_IF
            bSwapWait := TRUE;                        // 进入交棒等待 / Enter handover wait
            eState := eSwapWait;                      // 转交棒等待态 / To swap wait state
        ELSIF ((NOT bAuto) OR bStopReq OR (NOT bLvlOk)) AND tonMinRun.Q THEN
            bP1Req := FALSE;                          // 停泵条件且最短运行时满（防频启）/ Stop conditions with min-run met
            bP2Req := FALSE;                          // 停泵条件双停 / Stop conditions stop both
            IF (NOT bLvlOk) THEN
                uErrorId := 16#0005_00B2;             // 信息级：液位非有限冻结投切 / Info: non-finite freezes switching
            END_IF
            eState := eIdle;                          // 回待机 / Back to idle
        END_IF
    eSwapWait:
        bSwapWait := TRUE;                            // 等待标志保持 / Wait flag held
        IF bLead1 THEN
            bP1Req := TRUE;                           // 旧主泵保持运行 / Old lead kept running
            bP2Req := TRUE;                           // 新主泵等待反馈 / New lead awaiting feedback
            bBothFb := bP1Fb AND bP2Fb;               // 双反馈确认 / Both feedbacks confirmed
        ELSE
            bP2Req := TRUE;                           // 旧主泵保持运行 / Old lead kept running
            bP1Req := TRUE;                           // 新主泵等待反馈 / New lead awaiting feedback
            bBothFb := bP1Fb AND bP2Fb;               // 双反馈确认 / Both feedbacks confirmed
        END_IF
        IF bBothFb THEN
            IF bLead1 THEN
                bP1Req := FALSE;                      // 新主泵确认后停旧泵（停止侧安全执行）/ Stop old lead after confirm
                bLead1 := FALSE;                      // 轮值交棒完成 / Rotation handed over
            ELSE
                bP2Req := FALSE;                      // 新主泵确认后停旧泵 / Stop old lead after confirm
                bLead1 := TRUE;                       // 轮值交棒完成 / Rotation handed over
            END_IF
            bSwapWait := FALSE;                       // 清等待标志 / Clear wait flag
            eState := eLeadRun;                       // 回单主泵运行态 / Back to lead running
        ELSIF tonHandov.Q THEN
            IF bLead1 THEN
                bP2Req := FALSE;                      // 等待超时撤新泵请求撤轮换 / Timeout revokes new lead
            ELSE
                bP1Req := FALSE;                      // 等待超时撤新泵请求撤轮换 / Timeout revokes new lead
            END_IF
            bSwapWait := FALSE;                       // 清等待标志 / Clear wait flag
            eState := eLeadRun;                       // 回原主泵运行态 / Back to original lead
            uErrorId := 16#0005_00B2;                 // 信息级：交棒等待超时回落 / Info: handover wait timeout
        END_IF
    eFault:
        bP1Req := FALSE;                              // 故障态双泵停 / Both off in fault
        bP2Req := FALSE;                              // 故障态双泵停 / Both off in fault
        bSwapWait := FALSE;                           // 故障清等待 / Fault clears wait
        IF (NOT bP1Fb) AND (NOT bP2Fb) THEN
            eState := eIdle;                          // 可达解除路径：双泵实停复归 / Reachable release: both stopped
            uErrorId := 16#0000_0000;                 // 清码 / Clear code
        END_IF
    ELSE
        eState := eFault;                             // 非法状态兜底 / Illegal state fallback
END_CASE

// ---- 段 4｜双泵反馈双失效监视（运行指令下反馈缺失）------------------------------
bFbDualFail := (bP1Req AND NOT bP1Fb) AND (bP2Req AND NOT bP2Fb); // 双指令双无反馈 / Both commanded, both no feedback
IF bFbDualFail THEN
    eState := eFault;                                 // 双失效锁故障 / Dual failure latches fault
END_IF

// ---- 段 5｜HiHi/LoLo 独立硬联锁窗（直接切输出，不进状态机）----------------------
bIntrlk := bHiHi OR bLoLo;                            // 硬联锁激活判定 / Interlock active detection
IF bHiHi THEN
    bP1Req := FALSE;                                  // 高高位独立窗双泵停 / HiHi window stops both
    bP2Req := FALSE;                                  // 高高位独立窗双泵停 / HiHi window stops both
END_IF
IF bLoLo THEN
    bP1Req := TRUE;                                   // 低低位独立窗双泵启（恢复液位安全侧）/ LoLo window starts both
    bP2Req := TRUE;                                   // 低低位独立窗双泵启 / LoLo window starts both
END_IF

// ---- 段 6｜主泵号输出与错误码装配 ----------------------------------------------
IF bLead1 THEN
    bLead := 1;                                       // 主泵号输出 / Lead pump number output
ELSE
    bLead := 2;                                       // 主泵号输出 / Lead pump number output
END_IF
IF bIntrlk THEN
    bError   := TRUE;                                 // 硬联锁故障配对（R45）/ Interlock fault paired
    uErrorId := 16#0005_00B4;                         // 码位：硬联锁触发 / Code: hard interlock
ELSIF eState = eFault THEN
    bError   := TRUE;                                 // 双失效故障配对 / Dual failure fault paired
    uErrorId := 16#0005_00B3;                         // 码位：双泵失效 / Code: dual pump failure
ELSIF eState = eSwapWait THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := 16#0005_00B2;                         // 信息级：交棒等待 / Info: handover wait
ELSE
    bError   := FALSE;                                // 无错清标志 / Clear fault flag
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF
END_FUNCTION_BLOCK
