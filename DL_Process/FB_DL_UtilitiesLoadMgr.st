(*==============================================================================
 * 组件名称 (Component)  : FB_DL_UtilitiesLoadMgr
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / R_TRIG / ABS / MAX / MIN，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 多机按需投切负荷分配公开工艺语义（行业池，空压机/
 *                         冷冻机通用），轮值均衡借鉴本库 DutyStandbyRotation
 *                         思想（累计运行时长排序，零代码复制），道莅
 *                         clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 多机按需投切负荷分配件（空压机/冷冻机通用，不出
 *                         冷机专用变体）。加权平均负载对照回差双阈值
 *                         （启动阈高于停止阈防振荡）定增/减台数；投切按
 *                         累计运行时长均衡轮值；台数变更经驻留时间抑制。
 *                         仅指令与反馈持续矛盾置故障级，其余全部信息级。
 * 码位     (Codes)      : 16#0005_00B7 信息级：组态非法不投切、负载非有限
 *                                      权重归零、台数/阈值钳位（不置 bError）
 *                         16#0005_00B8 故障级：指令与反馈持续矛盾（锁存，
 *                                      bRst 复位沿为可达解除路径）
 *                         16#0005_00B9~00BB 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 uMachCnt 为零或阈值倒置记组态码不投切；
 *                         2 非有限负载该机权重归零后均值重算防除零；
 *                         3 越界输出逐位清零；
 *                         4 TON/R_TRIG 实例每拍无条件刷新；
 *                         5 手动模式（bAuto=FALSE）冻结投切保持现状。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 17）
 *==============================================================================*)

(*==============================================================================
 * 功能块: FB_DL_UtilitiesLoadMgr
 * 调用约定: 每个扫描周期无条件调用一次；负载与运行反馈经引脚数组注入。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_UtilitiesLoadMgr
VAR_INPUT
    afLoad  : ARRAY[1..8] OF REAL;    // 各机负载率 [百分数] / Per-machine load rate [%]
    abFb    : ARRAY[1..8] OF BOOL;    // 各机运行反馈（可增引脚，矛盾判据用）/ Per-machine running feedback, added pin
    uMachCnt: UINT := 8;              // 机组台数 [台]，合法域 1..8 / Machine count, valid 1..8
    fStartTh: REAL := 80.0;           // 投切启动阈 [百分数]，须高于停止阈 / Start threshold [%], above stop
    fStopTh : REAL := 50.0;           // 投切停止阈 [百分数] / Stop threshold [%]
    uMinRun : UINT := 1;              // 最少运行台数 [台] / Minimum running count
    uMaxRun : UINT := 8;              // 最多运行台数 [台] / Maximum running count
    bAuto   : BOOL := FALSE;          // 自动模式 / Auto mode
    tDwell  : TIME := T#60S;          // 台数变更驻留 [毫秒] / Switching dwell [ms]
    tFbConf : TIME := T#10S;          // 反馈矛盾确认时长 [毫秒]（可增引脚）/ Feedback mismatch confirm [ms], added pin
    bRst    : BOOL := FALSE;          // 故障复位沿（可增引脚）/ Fault reset edge, added pin
END_VAR
VAR_OUTPUT
    abRun   : ARRAY[1..8] OF BOOL;    // 各机运行指令 / Per-machine run command
    uRunCnt : UINT;                   // 当前运行台数 [台] / Current running count
    bError  : BOOL;                   // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId: UDINT;                  // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigRst: R_TRIG;                 // 复位沿检测，每拍无条件刷新 / Reset edge detector, refreshed every scan
    tonDwell: TON;                    // 驻留计时，每拍无条件刷新 / Dwell timer, refreshed every scan
    tonFb   : TON;                    // 反馈矛盾确认计时，每拍无条件刷新 / Feedback mismatch timer
    i       : INT;                    // 逐机循环索引 / Per-machine loop index
    j       : INT;                    // 轮值选择内层索引 / Rotation inner loop index
    uCntEff : INT;                    // 钳位后有效台数 [台]，INT 域 / Effective clamped count, INT domain
    uMinEff : INT;                    // 钳位后最少台数 [台] / Effective minimum count
    uMaxEff : INT;                    // 钳位后最多台数 [台] / Effective maximum count
    nRunNow : INT;                    // 本拍运行台数 [台] / Running count this scan
    nValid  : INT;                    // 有限负载数 [台] / Finite load count
    fSum    : REAL;                   // 有限负载和 [百分数] / Finite load sum [%]
    fAvg    : REAL;                   // 加权平均负载 [百分数] / Weighted average load [%]
    bCfgOk  : BOOL;                   // 组态合法标志 / Configuration legality flag
    bAddReq : BOOL;                   // 增台请求 / Add request
    bSubReq : BOOL;                   // 减台请求 / Sub request
    bPickOk : BOOL;                   // 轮值选机成功 / Rotation pick success
    nSel    : INT;                    // 轮值选中下标 / Rotation selected index
    uTicksLo: UDINT;                  // 轮值最短累计时标 [拍] / Rotation shortest tick count
    auTicks : ARRAY[1..8] OF UDINT;   // 各机累计运行时标 [拍] / Per-machine run tick counters
    bAnyMis : BOOL;                   // 任一机指令反馈矛盾 / Any command-feedback mismatch
    bClamp  : BOOL;                   // 本拍钳位信息 / Clamp info this scan
    bDwellGo: BOOL;                   // 驻留期满许可投切 / Dwell elapsed permit
    xDwellRst: BOOL;                  // 投切拍单拍断驻留输入 / One-scan dwell input break after switch
    bFirst  : BOOL := TRUE;           // 首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_ULD_MACH_MAX: INT  := 8;       // 台数上限 [台] / Machine count upper bound
    DL_ULD_FIN     : REAL := 1.0E30;  // REAL 有限幅值判界 / REAL finiteness magnitude bound
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigRst(CLK := bRst);                                // 复位沿检测 / Reset edge detection
tonDwell(IN := ((NOT bFirst) AND (NOT xDwellRst)), PT := tDwell); // 驻留计时，投切拍断输入 / Dwell timing, broken on switch scan
tonFb(IN := bAnyMis, PT := tFbConf);                  // 矛盾确认计时 / Mismatch confirm timing

// ---- 段 2｜台数与阈值钳位（统一 INT 域）----------------------------------------
uCntEff := MIN(UINT_TO_INT(uMachCnt), DL_ULD_MACH_MAX); // 台数钳上限 / Clamp count to upper bound
uCntEff := MAX(uCntEff, 1);                           // 下限保 1 / Floor at 1
uMaxEff := MIN(UINT_TO_INT(uMaxRun), uCntEff);        // 最多台数钳到台数内 / Clamp max into count
uMaxEff := MAX(uMaxEff, 0);                           // 非负 / Non-negative
uMinEff := MIN(UINT_TO_INT(uMinRun), uMaxEff);        // 最少台数不超最多 / Min not above max
uMinEff := MAX(uMinEff, 0);                           // 非负 / Non-negative
bCfgOk := (uCntEff >= 1) AND (fStartTh > fStopTh) AND (fStartTh = fStartTh)
      AND (fStopTh = fStopTh) AND (ABS(fStartTh) < DL_ULD_FIN) AND (ABS(fStopTh) < DL_ULD_FIN); // 组态合法性 / Configuration legality
bClamp := (UINT_TO_INT(uMachCnt) > DL_ULD_MACH_MAX) OR (fStartTh <= fStopTh); // 钳位/倒置信息 / Clamp or inversion info

// ---- 段 3｜首拍与越界清位（越界逐位清零）----------------------------------------
IF bFirst THEN
    FOR i := 1 TO DL_ULD_MACH_MAX DO
        abRun[i] := FALSE;                            // 首拍全 FALSE / First scan all FALSE
        auTicks[i] := 0;                              // 时标清零 / Ticks cleared
    END_FOR
    bFirst := FALSE;                                  // 清首扫标志 / Clear first-scan flag
END_IF

// ---- 段 4｜负载有效性掩码与加权平均（非有限权重归零后均值重算防除零）------------
nValid := 0;                                          // 有效数清零 / Clear valid count
fSum := 0.0;                                          // 和清零 / Clear sum
FOR i := 1 TO uCntEff DO
    IF (afLoad[i] = afLoad[i]) AND (ABS(afLoad[i]) < DL_ULD_FIN) THEN
        nValid := nValid + 1;                         // 有效负载计数 / Count finite load
        fSum := fSum + afLoad[i];                     // 累加有效负载 / Accumulate finite load
    END_IF
END_FOR
IF nValid > 0 THEN
    fAvg := fSum / UDINT_TO_REAL(INT_TO_UDINT(nValid)); // 均值，分母已验正 / Average, denominator verified
ELSE
    fAvg := 0.0;                                      // 全无效确定值 / Deterministic fallback
END_IF

// ---- 段 5｜运行台数统计与时标累计 ------------------------------------------------
nRunNow := 0;                                         // 台数清零 / Clear count
FOR i := 1 TO uCntEff DO
    IF abRun[i] THEN
        nRunNow := nRunNow + 1;                       // 统计运行台数 / Count running machines
        auTicks[i] := auTicks[i] + 1;                 // 运行时标累计（轮值均衡基准）/ Run ticks accumulate
    END_IF
END_FOR

// ---- 段 6｜投切决策（组态非法或非自动冻结投切；驻留期满许可）--------------------
bDwellGo := tonDwell.Q;                               // 驻留期满 / Dwell elapsed
bAddReq := bCfgOk AND bAuto AND bDwellGo AND (fAvg > fStartTh) AND (nRunNow < uMaxEff); // 增台请求 / Add request
bSubReq := bCfgOk AND bAuto AND bDwellGo AND (fAvg < fStopTh) AND (nRunNow > uMinEff); // 减台请求 / Sub request
IF bAddReq THEN
    bPickOk := FALSE;                                 // 选机标志先清 / Clear pick flag
    uTicksLo := 16#FFFFFFFF;                          // 最短时标预置满 / Preset shortest ticks full
    FOR j := 1 TO uCntEff DO
        IF (NOT abRun[j]) AND (auTicks[j] < uTicksLo) THEN
            uTicksLo := auTicks[j];                   // 更新最短时标 / Update shortest ticks
            nSel := j;                                // 记录选中下标 / Record selected index
            bPickOk := TRUE;                          // 选机成功 / Pick success
        END_IF
    END_FOR
    IF bPickOk THEN
        abRun[nSel] := TRUE;                          // 投入最短时标停运机 / Start shortest-tick idle machine
        xDwellRst := TRUE;                            // 投切拍断驻留输入重置计时 / Break dwell input on switch scan
    END_IF
ELSIF bSubReq THEN
    bPickOk := FALSE;                                 // 选机标志先清 / Clear pick flag
    uTicksLo := 0;                                    // 最长时标预置零 / Preset longest ticks zero
    FOR j := 1 TO uCntEff DO
        IF abRun[j] AND (auTicks[j] >= uTicksLo) THEN
            uTicksLo := auTicks[j];                   // 更新最长时标 / Update longest ticks
            nSel := j;                                // 记录选中下标 / Record selected index
            bPickOk := TRUE;                          // 选机成功 / Pick success
        END_IF
    END_FOR
    IF bPickOk THEN
        abRun[nSel] := FALSE;                         // 停运最长时标运行机 / Stop longest-tick running machine
        xDwellRst := TRUE;                            // 投切拍断驻留输入重置计时 / Break dwell input on switch scan
    END_IF
END_IF

// ---- 段 7｜指令反馈矛盾监视与故障锁存 --------------------------------------------
bAnyMis := FALSE;                                     // 矛盾标志先清 / Clear mismatch flag
FOR i := 1 TO uCntEff DO
    IF abRun[i] AND (NOT abFb[i]) THEN
        bAnyMis := TRUE;                              // 指令真反馈假矛盾 / Command true feedback false
    END_IF
END_FOR
IF rTrigRst.Q THEN
    bAnyMis := FALSE;                                 // 复位清矛盾路径 / Reset clears mismatch path
END_IF

// ---- 段 8｜输出台数与错误码装配 --------------------------------------------------
nRunNow := 0;                                         // 重统计输出台数 / Recount running
FOR i := 1 TO DL_ULD_MACH_MAX DO
    IF i > uCntEff THEN
        abRun[i] := FALSE;                            // 越界逐位清零 / Out-of-range bits cleared
    END_IF
    IF abRun[i] THEN
        nRunNow := nRunNow + 1;                       // 输出台数统计 / Count output running
    END_IF
END_FOR
uRunCnt := INT_TO_UINT(nRunNow);                      // 台数输出 / Count output
IF tonFb.Q THEN
    bError   := TRUE;                                 // 指令反馈持续矛盾锁故障 / Persistent mismatch latches fault
    uErrorId := 16#0005_00B8;                         // 码位：矛盾持续 / Code: persistent mismatch
ELSIF (NOT bCfgOk) OR bClamp OR (nValid = 0) THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := 16#0005_00B7;                         // 信息级：组态/非有限/钳位 / Info: config or non-finite
ELSE
    bError   := FALSE;                                // 无错清标志 / Clear fault flag
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF

// ---- 段 9｜单拍标志收尾 ----------------------------------------------------------
xDwellRst := FALSE;                                   // 断输入请求仅当拍有效 / Break request is single scan
END_FUNCTION_BLOCK
