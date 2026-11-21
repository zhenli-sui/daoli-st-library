(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ReactorStepCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / R_TRIG / ABS / MAX / MIN 与库内
 *                         FB_DL_RampGenerator（IN-OUT 注入消费，斜坡不内联），
 *                         零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 反应釜工步顺控公开工艺语义（行业池）与 ISA-88 相
 *                         语义公开框架（暂停在步骤边界生效、恢复不重头，
 *                         主源记 T2-8），道莅 clean-room 防御性实现，
 *                         未复制任何外部源码行
 * 功能描述 (Function)   : 反应釜四工步顺控件：升温 → 保温 → 滴加 → 冷却。
 *                         温度设定经库内 FB_DL_RampGenerator 斜坡给出
 *                         （IN-OUT 注入，配方斜率单位 摄氏度每分钟 换算为
 *                         斜坡件的 摄氏度每秒 后下发）；滴加相以 bFeedAck
 *                         为终点带步超时；超温/超压独立监视层与顺控层
 *                         分离；暂停（bHold）在当前工步边界生效、恢复
 *                         不重头。不内联 PID（上层闭环外置）。
 * 复用清单 (Reuse)      : FB_DL_RampGenerator（斜坡设定，IN-OUT 注入）；
 *                         ISA-88 相语义（行为定义，零代码复制）。
 * 状态机   (States)     : eIdle/eHeat/eSoak/eFeed/eCool/eDone/ePaused/eFault，
 *                         CASE 带 ELSE 锁安全侧（fTSet 回零、停滴加）。
 * 码位     (Codes)      : 16#0005_00A8 信息级：配方域非法拒启动、配方钳位、
 *                                      暂停挂起提示（不置 bError）
 *                         16#0005_00A9 故障级：超温（独立监视层，锁存）
 *                         16#0005_00AA 故障级：超压（独立监视层，锁存）
 *                         16#0005_00AB 故障级：工步超时（滴加反馈缺失）
 *                         16#0005_00AC 故障级：状态非法（ELSE 兜底，锁存）
 * 边界防错 (Boundary)   : 1 配方域校验先于启动（斜率不大于零/温带倒置拒启动）；
 *                         2 bHold 仅在工步边界转暂停态，恢复续走原工步；
 *                         3 TON/R_TRIG 实例每拍无条件刷新；
 *                         4 CASE 带 ELSE 锁安全侧；
 *                         5 故障锁存可达解除路径：中止沿复归待机；
 *                         6 超温/超压监视独立于顺控相，任一相均生效。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 14）
 *                         2026-11-18 v1.0.1 R31 终审修复：中止/故障释放路径
 *                         补清 bError 与 uErrorId，消除释放后故障标志粘滞
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_ReactorRecipe（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE ST_DL_ReactorRecipe :
STRUCT
    fRampUp   : REAL := 2.0;    // 升温斜率 [摄氏度每分钟]，须大于 0 / Heat-up rate [degC per min], > 0
    fRampDown : REAL := 3.0;    // 降温斜率 [摄氏度每分钟]，须大于 0 / Cool-down rate [degC per min], > 0
    fSoakLo   : REAL := 80.0;   // 保温温带下限 [摄氏度] / Soak band lower [degC]
    fSoakHi   : REAL := 85.0;   // 保温温带上限 [摄氏度]，须高于下限 / Soak band upper [degC], above lower
    fFeedMl   : REAL := 50.0;   // 滴加量 [毫升] / Feed amount [mL]
    fCoolTgt  : REAL := 40.0;   // 冷却目标温度 [摄氏度] / Cool target temperature [degC]
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_ReactorStep（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ReactorStep :
(
    eIdle   := 0,     // 待机：等待启动 / Idle, waiting for start
    eHeat   := 10,    // 升温工步：斜坡逼近温带 / Heat step, ramp to band
    eSoak   := 20,    // 保温工步：温带保持计时 / Soak step, hold band with timing
    eFeed   := 30,    // 滴加工步：等滴加反馈 / Feed step, wait feed acknowledgement
    eCool   := 40,    // 冷却工步：斜坡降到目标 / Cool step, ramp to target
    eDone   := 50,    // 完成：单拍脉冲后回待机 / Done, one-scan pulse then idle
    ePaused := 60,    // 暂停挂起：工步边界生效 / Paused, effective at step boundary
    eFault  := 99     // 故障：锁定等待中止复位 / Fault, latched until abort reset
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ReactorStepCtrl
 * 调用约定: 每个扫描周期无条件调用一次；ioRamp 为调用方持有的斜坡实例
 *           （IN-OUT 注入），本件驱动其引脚并读取其输出。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ReactorStepCtrl
VAR_INPUT
    bStart   : BOOL := FALSE;         // 启动沿（待机且配方合法时受理）/ Start edge, accepted in idle with legal recipe
    bHold    : BOOL := FALSE;         // 暂停请求，工步边界生效 / Hold request, effective at step boundary
    bAbort   : BOOL := FALSE;         // 中止沿：任意态安全退出 / Abort edge, safe exit from any state
    fTNow    : REAL := 25.0;          // 釜温实测 [摄氏度] / Reactor temperature [degC]
    fPNow    : REAL := 101.0;         // 釜压实测 [千帕] / Reactor pressure [kPa]
    fPLimMax : REAL := 300.0;         // 超压监视限 [千帕]（可增引脚）/ Overpressure limit [kPa], added pin
    stRecipe : ST_DL_ReactorRecipe;   // 配方注入 / Recipe injected
    bFeedAck : BOOL := FALSE;         // 滴加完成反馈 / Feed acknowledgement feedback
    tSoak    : TIME := T#600S;        // 保温时长 [毫秒]（可增引脚）/ Soak duration [ms], added pin
    tFeedMax : TIME := T#600S;        // 滴加步超时 [毫秒]（可增引脚）/ Feed step timeout [ms], added pin
END_VAR
VAR_IN_OUT
    ioRamp   : FB_DL_RampGenerator;   // 斜坡发生器实例注入（库内复用）/ Ramp generator instance injected
END_VAR
VAR_OUTPUT
    eStep    : E_DL_ReactorStep;      // 当前工步 / Current step
    fTSet    : REAL;                  // 温度设定 [摄氏度]（斜坡输出）/ Temperature setpoint [degC]
    bFeedReq : BOOL;                  // 滴加请求 / Feed request
    bDone    : BOOL;                  // 全工步完成单拍脉冲（R27）/ All steps done one-scan pulse
    bError   : BOOL;                  // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigStart: R_TRIG;               // 启动沿检测，每拍无条件刷新 / Start edge detector, refreshed every scan
    rTrigAbort: R_TRIG;               // 中止沿检测，每拍无条件刷新 / Abort edge detector, refreshed every scan
    tonSoak   : TON;                  // 保温计时，每拍无条件刷新 / Soak timer, refreshed every scan
    tonStep   : TON;                  // 步超时计时，每拍无条件刷新 / Step timeout timer, refreshed every scan
    bStepRst  : BOOL;                 // 步切换拍单拍断超时输入 / One-scan timeout break on step change
    eStatePrev: E_DL_ReactorStep;     // 上一拍步快照 / Previous step snapshot
    eResume   : E_DL_ReactorStep;     // 暂停前工步（恢复不重头）/ Step before pause, resume without restart
    bRcpOk    : BOOL;                 // 配方域合法标志 / Recipe legality flag
    bTValid   : BOOL;                 // 温度输入有效 / Temperature input validity
    bPValid   : BOOL;                 // 压力输入有效 / Pressure input validity
    bOverT    : BOOL;                 // 超温判定 / Over-temperature verdict
    bOverP    : BOOL;                 // 超压判定 / Over-pressure verdict
    uCodeLatch: UDINT;                // 故障级锁存码 / Latched fault code
    bInit     : BOOL := TRUE;         // 首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_RSC_FIN   : REAL := 1.0E30;    // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_RSC_OTMAR : REAL := 10.0;      // 超温监视裕度 [摄氏度] / Over-temp monitor margin [degC]
    DL_RSC_MIN2S : REAL := 60.0;      // 每分钟到每秒换算系数 / Per-min to per-sec factor
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigStart(CLK := bStart);                            // 启动沿检测 / Start edge detection
rTrigAbort(CLK := bAbort);                            // 中止沿检测 / Abort edge detection
tonSoak(IN := (eStep = eSoak) AND (NOT bHold), PT := tSoak); // 保温计时，暂停断输入 / Soak timing, broken on hold
tonStep(IN := (eStep = eFeed) AND (NOT bStepRst), PT := tFeedMax); // 滴加超时按步断输入 / Feed timeout per step

// ---- 段 2｜步切换检测 ------------------------------------------------------------
bStepRst := (eStep <> eStatePrev) OR bInit;           // 步变化即断输入 / Step change breaks timing
eStatePrev := eStep;                                  // 快照留痕 / Snapshot previous step
bInit := FALSE;                                       // 清首扫标志 / Clear first-scan flag

// ---- 段 3｜输入有效性与独立监视层判定（与顺控相分离）------------------------------
bTValid := (fTNow = fTNow) AND (ABS(fTNow) < DL_RSC_FIN);   // 温度有限 / Temperature finite
bPValid := (fPNow = fPNow) AND (ABS(fPNow) < DL_RSC_FIN);   // 压力有限 / Pressure finite
bOverT  := bTValid AND (eStep <> eIdle) AND (fTNow > stRecipe.fSoakHi + DL_RSC_OTMAR); // 超温：带外裕度判 / Over-temp beyond margin
bOverP  := bPValid AND (eStep <> eIdle) AND (fPNow > fPLimMax); // 超压独立判 / Over-pressure independent
IF bOverT THEN
    uCodeLatch := 16#0005_00A9;                       // 码位：超温 / Code: over temperature
END_IF
IF bOverP THEN
    uCodeLatch := 16#0005_00AA;                       // 码位：超压 / Code: over pressure
END_IF
IF bOverT OR bOverP THEN
    eStep := eFault;                                  // 监视层直接锁故障 / Monitor layer latches fault directly
END_IF

// ---- 段 4｜中止沿统一入口：停滴加、温度设定回零、复归待机 ------------------------
IF rTrigAbort.Q THEN
    eStep := eIdle;                                   // 中止复归待机 / Abort returns to idle
    bFeedReq := FALSE;                                // 停滴加请求 / Stop feed request
    bError := FALSE;                                  // 中止含故障态释放路径，清故障标志（R28 终审）/ Abort is fault release path, clears flag
    uErrorId := 16#0000_0000;                         // 中止清错误码防粘滞（R28 终审）/ Abort clears error code against stickiness
END_IF

// ---- 段 5｜状态机（CASE 带 ELSE 锁安全侧：fTSet 回零、停滴加）---------------------
CASE eStep OF
    eIdle:
        fTSet := 0.0;                                 // 待机设定回零（安全侧）/ Idle setpoint zero, safe side
        bFeedReq := FALSE;                            // 待机停滴加 / Idle stops feed
        bDone := FALSE;                               // 清完成脉冲 / Clear done pulse
        ioRamp(bEnable := FALSE, bTrack := TRUE, fTrackValue := fTNow); // 斜坡跟踪实测免扰动 / Ramp tracks actual
        IF rTrigStart.Q THEN
            bRcpOk := (stRecipe.fRampUp > 0.0) AND (stRecipe.fRampDown > 0.0)
                  AND (stRecipe.fSoakLo < stRecipe.fSoakHi)
                  AND (stRecipe.fFeedMl >= 0.0) AND (stRecipe.fCoolTgt < stRecipe.fSoakLo)
                  AND (stRecipe.fRampUp < DL_RSC_FIN) AND (stRecipe.fRampDown < DL_RSC_FIN); // 配方域校验先于启动 / Recipe check before start
            IF bRcpOk THEN
                eStep := eHeat;                       // 配方合法进升温 / Legal recipe, to heat
            ELSE
                uErrorId := 16#0005_00A8;             // 信息级：配方非法拒启动 / Info: illegal recipe, start rejected
            END_IF
        END_IF
    eHeat:
        bFeedReq := FALSE;                            // 升温停滴加 / Heat stops feed
        ioRamp(bEnable := TRUE, fTarget := stRecipe.fSoakHi,
               fRateUp := stRecipe.fRampUp / DL_RSC_MIN2S,
               fRateDown := stRecipe.fRampDown / DL_RSC_MIN2S,
               bHold := FALSE);                       // 斜坡下发，配方斜率换算每秒 / Ramp driven, rate per second
        fTSet := ioRamp.fOut;                         // 温度设定取斜坡输出 / Setpoint from ramp output
        IF ioRamp.bDone AND bTValid AND (fTNow >= stRecipe.fSoakLo) THEN
            eStep := eSoak;                           // 到带复验后转保温（R42）/ Recheck then to soak
        END_IF
        IF bHold AND ioRamp.bDone THEN
            eResume := eSoak;                         // 边界暂停登记续点（ISA-88）/ Boundary pause books resume step
            eStep := ePaused;                         // 转暂停挂起 / To paused
        END_IF
    eSoak:
        bFeedReq := FALSE;                            // 保温停滴加 / Soak stops feed
        ioRamp(bEnable := TRUE, fTarget := stRecipe.fSoakHi,
               fRateUp := stRecipe.fRampUp / DL_RSC_MIN2S,
               fRateDown := stRecipe.fRampDown / DL_RSC_MIN2S,
               bHold := FALSE);                       // 保温维持带顶设定 / Soak holds band top
        fTSet := ioRamp.fOut;                         // 温度设定取斜坡输出 / Setpoint from ramp output
        IF tonSoak.Q THEN
            eStep := eFeed;                           // 保温满转滴加 / Soak elapsed, to feed
        END_IF
        IF bHold THEN
            eResume := eSoak;                         // 边界暂停登记续点 / Boundary pause books resume step
            eStep := ePaused;                         // 转暂停挂起 / To paused
        END_IF
    eFeed:
        bFeedReq := TRUE;                             // 滴加请求置位 / Feed request set
        fTSet := ioRamp.fOut;                         // 温度设定维持 / Setpoint maintained
        IF tonStep.Q THEN
            eStep := eFault;                          // 滴加反馈缺失锁故障（步超时）/ Feed ack missing, fault
            uCodeLatch := 16#0005_00AB;               // 码位：步超时/反馈缺失 / Code: step timeout
        ELSIF bFeedAck THEN
            eStep := eCool;                           // 滴加完成转冷却 / Feed done, to cool
        END_IF
    eCool:
        bFeedReq := FALSE;                            // 冷却停滴加 / Cool stops feed
        ioRamp(bEnable := TRUE, fTarget := stRecipe.fCoolTgt,
               fRateUp := stRecipe.fRampUp / DL_RSC_MIN2S,
               fRateDown := stRecipe.fRampDown / DL_RSC_MIN2S,
               bHold := FALSE);                       // 斜坡降到冷却目标 / Ramp down to cool target
        fTSet := ioRamp.fOut;                         // 温度设定取斜坡输出 / Setpoint from ramp output
        IF ioRamp.bDone AND bTValid AND (fTNow <= stRecipe.fCoolTgt + 1.0) THEN
            eStep := eDone;                           // 到目标复验后转完成（R42）/ Recheck then to done
        END_IF
        IF bHold AND ioRamp.bDone THEN
            eResume := eDone;                         // 边界暂停登记续点 / Boundary pause books resume step
            eStep := ePaused;                         // 转暂停挂起 / To paused
        END_IF
    eDone:
        fTSet := ioRamp.fOut;                         // 完成态维持设定 / Done maintains setpoint
        bFeedReq := FALSE;                            // 完成停滴加 / Done stops feed
        bDone := TRUE;                                // 完成单拍脉冲 / One-scan done pulse
        eStep := eIdle;                               // 下拍回待机 / Back to idle next scan
    ePaused:
        fTSet := ioRamp.fOut;                         // 暂停冻结设定（斜坡 bHold 语义由态承载）/ Pause freezes setpoint
        bFeedReq := FALSE;                            // 暂停停滴加 / Pause stops feed
        uErrorId := 16#0005_00A8;                     // 信息级：暂停挂起提示 / Info: paused notice
        IF (NOT bHold) AND (eResume <> ePaused) THEN
            eStep := eResume;                         // 恢复不重头续走原工步 / Resume without restart
        END_IF
    eFault:
        fTSet := 0.0;                                 // 故障安全侧设定回零 / Fault safe side setpoint zero
        bFeedReq := FALSE;                            // 故障停滴加 / Fault stops feed
        bDone := FALSE;                               // 故障清完成 / Fault clears done
        IF rTrigAbort.Q THEN
            eStep := eIdle;                           // 可达解除路径：中止沿复归 / Reachable release: abort edge
            uCodeLatch := 16#0000_0000;               // 清锁存码 / Clear latched code
            bError := FALSE;                          // 释放同步清故障标志（R28 终审）/ Release clears fault flag
            uErrorId := 16#0000_0000;                 // 释放同步清错误码 / Release clears error code
        END_IF
    ELSE
        eStep := eFault;                              // 非法状态兜底 / Illegal state fallback
        uCodeLatch := 16#0005_00AC;                   // 码位：状态非法 / Code: illegal state
        fTSet := 0.0;                                 // 兜底设定回零（安全侧）/ Fallback setpoint zero
        bFeedReq := FALSE;                            // 兜底停滴加 / Fallback stops feed
END_CASE

// ---- 段 6｜错误码装配：故障锁存回放优先，信息级居次 ------------------------------
IF eStep = eFault THEN
    bError   := TRUE;                                 // 故障标志配对（R45）/ Fault flag paired
    uErrorId := uCodeLatch;                           // 故障码锁存回放 / Latched fault code replayed
END_IF
END_FUNCTION_BLOCK
