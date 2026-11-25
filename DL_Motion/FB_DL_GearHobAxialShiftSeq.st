//==============================================================================
// 功能块：FB_DL_GearHobAxialShiftSeq ｜ 中文名称：滚齿机滚刀轴向窜刀顺控（复杂度 C4）
// 所属子库：DL_Motion ｜ 版本 VERSION: v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：滚刀磨损后沿刀轴窜动一个切削区宽度换新切削区——松刀轴夹紧 → 轴向进给
//           到目标位 → 到位稳定 → 重新夹紧确认 → 对刀校验 → 完成，累计窜刀量在完成
//           拍提交；超可用行程拒动、未松夹不得进给、未夹紧不得对刀、步超时落故障；
//           中止走两段化（先停进给 → 轴静止窗 → 再按安全序重新夹紧）。
// 开源溯源 (Origin)：道莅原创实现（参考 GB/T 1356 圆柱齿轮滚齿工艺与滚刀轴向窜刀
//           量工程惯例 分类与参数域，许可证=MIT，借鉴点=「按切削区宽度分步窜刀并
//           累计至刀轴可用行程上限」的工艺序）
// 单位表：长度[mm] / 时间[ms] / 计数[次]
// 错误码表（Motion 段 0008，故障窗口 0A01~0A08，信息窗口 0101）：
//   16#0008_0A01 故障级：组态非法（步长/上限/容差 <= 0、累计初值 < 0、时间量 <= 0）
//   16#0008_0A02 故障级：目标位 > fMaxTravelMm，拒动并置 xTravelLimit
//   16#0008_0A03 故障级：松夹相超时未到位，或进给期松夹信号丢失，禁进给
//   16#0008_0A04 故障级：夹紧相或中止再夹紧窗超时未确认，禁对刀
//   16#0008_0A05 故障级：进给步超时，或稳定窗满仍未判轴到位
//   16#0008_0A06 故障级：轴位置入口非有限（NaN / Inf）或幅值超合法上限，拒算
//   16#0008_0A07 故障级：对刀校验偏差 > fPosTolMm
//   16#0008_0A08 故障级兜底：状态机落 ELSE 非法态，全输出断
//   16#0008_0101 信息级：单步窜刀完成（完成拍，不置 bError）
//           故障级码全部锁存回放（R187），唯一清除路径 = bReset 上升沿。
// 状态机：E_DL_HobShiftState（八态：eIdle=0 / eRelease=10 / eShift=20 / eSettle=30 /
//           eReclamp=40 / eVerify=50 / eDone=60 / eFault=99）。八态为纯相序机，中止
//           两段化不占相位（八态契约锁定），由内部段号 _uAbortStage 驱动（0 无 /
//           1 已停进给待轴静止 / 2 再夹紧中）。
// 边界行为：① 组态非法与入口非有限一律锁存故障，故障相不按当下输入重推断；② 故障
//           相迁出唯一路径 = bReset 上升沿且组态合法、未超程；③ 中止段 A 拍内
//           xCmdMove 立即断、夹紧两命令均不动（O 型中位液压锁保持），机检断言：中止
//           段 A 不得出现 xClampCmd / xUnclampCmd 置位；④ 八态 CASE 每态显式 + ELSE
//           兜底 → 0A08 全断；⑤ 目标位在启动拍锁定一次。
// 语义假设：① fTotalShiftMm 为累计窜刀量初值，只在首扫且未窜过刀时载入内部累计量，
//           运行期不参与运算（避免累计量双属主），掉电保持由上层把 fShiftUsedMm 回写
//           该引脚，且只允许在 eIdle 且 xStart = FALSE 期间回写；② 夹紧电磁阀为双电控
//           O 型中位机能——两命令全 FALSE 时液压锁保持，故故障相「全输出断」不会松开
//           刀轴；③ 位置反馈为刀轴轴向绝对位 [mm]，正方向为离开主轴端面的窜刀方向。
// 依赖纪律：仅 Standard.library（TON / R_TRIG）；零 GVL、零 VAR_EXTERNAL、零物理地
//           址直连，业务侧只经引脚注入。
// 修订历史：v1.0.0 2026-11-25 R88 首版（无人值守批次 · 复杂件 C4 · 序号 1）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_HobShiftState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 窜刀顺控相位，与段 8 输出置位、段 9 码映射一一对应。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_HobShiftState :
(
    eIdle    := 0,   // 空闲：等启动沿 / Idle, awaiting the start edge
    eRelease := 10,  // 松夹：发松开命令并等松开到位 / Release the arbor clamp and wait for feedback
    eShift   := 20,  // 轴向进给：发运动命令至目标位 / Axial feed towards the target position
    eSettle  := 30,  // 到位稳定：等稳定窗与到位标志 / Settle, stability window and in-position flag
    eReclamp := 40,  // 夹紧确认：发夹紧命令并等夹紧反馈 / Reclamp and wait for clamp feedback
    eVerify  := 50,  // 对刀校验：实测位与目标位比对 / Tool-position verification against the target
    eDone    := 60,  // 完成：累计窜刀量已提交 / Done, accumulated shift committed
    eFault   := 99   // 故障：组态/超程/联锁/超时/非法态 / Fault, configuration, travel, interlock, timeout or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_GearHobAxialShiftSeq
VAR_INPUT
    xEnable       : BOOL;   // 使能，FALSE 期间按中止处理 [—] / Enable, a drop is treated as an abort
    xStart        : BOOL;   // 启动请求，上升沿生效 [—] / Start request, rising edge effective
    xAbort        : BOOL;   // 中止请求，任意拍生效 [—] / Abort request, effective on any scan
    xReset        : BOOL;   // 故障复位，上升沿清全部锁存 [—] / Fault reset, rising edge clears all latches
    fShiftStepMm  : LREAL;  // 单步窜刀量 [mm]，须 > 0 / Per-step axial shift [mm], must be > 0
    fTotalShiftMm : LREAL;  // 累计窜刀量初值 [mm]，仅首扫载入 / Initial accumulated shift [mm], first scan only
    fAxisPosMm    : LREAL;  // 刀轴实际轴向位置 [mm] / Hob arbor actual axial position [mm]
    xAxisInPos    : BOOL;   // 轴到位标志 [—] / Axis in-position flag
    xClampClosed  : BOOL;   // 夹紧到位反馈 [—] / Clamp-closed feedback
    xClampOpen    : BOOL;   // 松开到位反馈 [—] / Clamp-open feedback
    tMoveTimeout  : TIME;   // 进给/校验步超时 [ms] / Feed and verification step timeout [ms]
    tSettleTime   : TIME;   // 到位稳定窗 [ms] / In-position settle window [ms]
    fPosTolMm     : LREAL;  // 对刀位置容差 [mm]，须 > 0 / Verification position tolerance [mm]
    fMaxTravelMm  : LREAL;  // 刀轴可用窜刀总行程 [mm] / Total usable axial shift travel [mm]
END_VAR
VAR_OUTPUT
    xCmdMove      : BOOL;   // 轴向进给命令 [—] / Axial feed command
    fCmdPosMm     : LREAL;  // 目标位命令 [mm] / Target position command [mm]
    xClampCmd     : BOOL;   // 夹紧命令（双电控 O 型中位，断电保持） [—] / Clamp command, O-centre holds on power loss
    xUnclampCmd   : BOOL;   // 松开命令（双电控 O 型中位，断电保持） [—] / Unclamp command, holds on power loss
    bRunning      : BOOL;   // 顺控运行中（非空闲非完成非故障非中止） [—] / Sequencing active
    bDone         : BOOL;   // 单步窜刀完成相电平 [—] / Single shift step done, level in the done phase
    bError        : BOOL;   // 故障级标志，仅故障级码置位 [—] / Fault-class flag, fault-level codes only
    nErrCode      : UDINT;  // 错误码，0 = 无错 [—] / Error code, 0 = none
    fShiftUsedMm  : LREAL;  // 累计窜刀量出口 [mm] / Accumulated axial shift outlet [mm]
    nShiftCount   : UDINT;  // 累计窜刀次数 [次] / Accumulated shift step count
    xTravelLimit  : BOOL;   // 窜刀行程上限已达（拒动锁存） [—] / Travel limit reached, refuse-to-move latch
END_VAR
VAR
    _eState       : E_DL_HobShiftState := E_DL_HobShiftState.eIdle; // 当前相位 [—] / Current phase
    _bInit        : BOOL := FALSE;      // 首扫标志，取非判定 [—] / First-scan flag, tested negated
    _fShiftUsedMm : LREAL;              // 内部累计窜刀量 [mm] / Internal accumulated shift [mm]
    _fTargetPosMm : LREAL;              // 本步目标位 [mm] = 累计 + 步长 / Step target [mm] = accumulated + step
    _fPosPrevMm   : LREAL;              // 上拍轴位快照 [mm]，静止判据用 / Previous-scan position [mm]
    _nShiftCount  : UDINT;              // 内部累计窜刀次数 [次] / Internal shift step counter
    _bCfgBad      : BOOL;               // 组态非法锁存 / Illegal configuration latch
    _bCfgOk       : BOOL;               // 本拍组态合法（派生量不锁存） [—] / Configuration legal this scan, derived
    _bAxisBad     : BOOL;               // 轴位置非有限锁存 / Non-finite axis position latch
    _bOverTravel  : BOOL;               // 超窜刀行程锁存 / Over-travel latch
    _bReleaseTmo  : BOOL;               // 松夹未到位/信号丢失锁存 / Release-not-reached latch
    _bClampTmo    : BOOL;               // 夹紧未确认锁存 / Clamp-not-confirmed latch
    _bFeedTmo     : BOOL;               // 进给步超时锁存 / Feed step timeout latch
    _bVerifyErr   : BOOL;               // 对刀超差锁存 / Verification error latch
    _bIllegal     : BOOL;               // 非法状态标志 / Illegal state flag
    _bInfoDone    : BOOL;               // 单步完成信息当拍标志 / Step-done info flag of this scan
    _bAbortReq    : BOOL;               // 中止请求合成（xAbort 或失能） [—] / Combined abort request
    _bFeedPermit  : BOOL;               // 进给许可（松开到位且未夹紧） [—] / Feed permit, released and not clamped
    _bStandstill  : BOOL;               // 轴静止判据（本拍位移小于阈值） [—] / Axis standstill criterion
    _uAbortStage  : UINT;               // 中止段号 0=无 1=待静止 2=再夹紧 / Abort stage 0 none 1 standstill 2 reclamp
    rtStart       : R_TRIG;             // 启动沿，段 5 无条件刷新 [—] / Start edge, refreshed in segment 5
    rtReset       : R_TRIG;             // 复位沿，段 5 无条件刷新 [—] / Reset edge, refreshed in segment 5
    tonRelease    : TON;                // 松夹相超时计时 [ms] / Release phase timeout [ms]
    tonMove       : TON;                // 进给相超时计时 [ms] / Feed phase timeout [ms]
    tonSettle     : TON;                // 稳定窗计时 [ms] / Settle window timer [ms]
    tonReclamp    : TON;                // 夹紧确认超时计时 [ms] / Reclamp timeout [ms]
    tonVerify     : TON;                // 对刀校验超时计时 [ms] / Verification timeout [ms]
    tonStandstill : TON;                // 中止段 A 静止窗计时 [ms] / Abort stage A standstill window [ms]
    tonAbortClamp : TON;                // 中止段 B 再夹紧确认窗计时 [ms] / Abort stage B reclamp window [ms]
END_VAR
VAR CONSTANT
    DL_EPS           : LREAL := 1.0E-9;      // 浮点容差零点，兼作除法分母下限 / Float epsilon, also the divisor floor
    DL_HOB_STILL_MM  : LREAL := 0.005;       // 静止窗每拍位移阈值 [mm] / Per-scan displacement threshold [mm]
    DL_HOB_ABORT_T   : TIME  := T#1500MS;    // 中止静止窗时长 [ms] / Abort standstill window [ms]
    DL_HOB_CLAMP_T   : TIME  := T#3000MS;    // 中止再夹紧确认窗 [ms] / Abort reclamp confirm window [ms]
    DL_HOB_POS_MAX   : LREAL := 1.0E9;       // 位置幅值合法上限 [mm] / Legal position magnitude ceiling [mm]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：全部输出先落安全侧，单拍标志预清零
 *      All outputs preset to the safe side, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
xCmdMove := FALSE;  fCmdPosMm := 0.0;       // 进给命令与目标位先清 / Feed command and target cleared first
xClampCmd := FALSE; xUnclampCmd := FALSE;   // 夹紧两命令先断（O 型中位保持） / Both clamp commands cleared, O-centre holds
bRunning := FALSE;  bDone := FALSE;         // 运行与完成标志每拍重算 / Running and done flags recomputed
bError := FALSE;    nErrCode := 16#0000_0000; // 故障标志与错误码每拍重算 / Fault flag and code recomputed
xTravelLimit := FALSE;                      // 超程标志每拍重算 / Travel limit flag recomputed
_bIllegal := FALSE; _bInfoDone := FALSE;    // 非法态与完成信息预清零 / Illegal and done-info flags pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：相位、累计量、计数与中止段号复位
 *      First-scan initialisation of phase, accumulated shift, counter and abort stage
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState       := E_DL_HobShiftState.eIdle;   // 相位从空闲起步 / Phase starts idle
    _fShiftUsedMm := 0.0;  _fTargetPosMm := 0.0; // 累计量与目标位先清零 / Accumulated shift and target at zero
    _fPosPrevMm   := 0.0;  _nShiftCount  := 0;   // 位置快照与窜刀计数清零 / Position snapshot and counter at zero
    _uAbortStage  := 0;                          // 中止段号从零起步 / Abort stage starts at zero
    _bInit        := TRUE;                       // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜入口非有限闸 + 组态闸 + 目标位预计算 + 超行程拒动判定
 *      Non-finite inlet gate, configuration gates, target computation, travel check
 *-----------------------------------------------------------------------------*)
IF NOT (fAxisPosMm > -1.0E30 AND fAxisPosMm < 1.0E30) THEN _bAxisBad := TRUE; END_IF    // 轴位非有限 → 0A06 / Non-finite position, 0A06
IF ABS(fAxisPosMm) > DL_HOB_POS_MAX THEN _bAxisBad := TRUE; END_IF                     // 轴位幅值超上限 → 0A06 / Beyond the ceiling, 0A06
IF NOT (fShiftStepMm > -1.0E30 AND fShiftStepMm < 1.0E30) THEN _bCfgBad := TRUE; END_IF  // 步长非有限 → 0A01 / Non-finite step, 0A01
IF NOT (fMaxTravelMm > -1.0E30 AND fMaxTravelMm < 1.0E30) THEN _bCfgBad := TRUE; END_IF // 行程上限非有限 → 0A01 / Non-finite limit, 0A01
IF NOT (fPosTolMm > -1.0E30 AND fPosTolMm < 1.0E30) THEN _bCfgBad := TRUE; END_IF      // 容差非有限 → 0A01 / Non-finite tolerance, 0A01
IF NOT (fTotalShiftMm > -1.0E30 AND fTotalShiftMm < 1.0E30) THEN _bCfgBad := TRUE; END_IF // 累计初值非有限 → 0A01 / Non-finite initial shift, 0A01
IF (fShiftStepMm <= DL_EPS) OR (fMaxTravelMm <= DL_EPS) OR (fPosTolMm <= DL_EPS) THEN _bCfgBad := TRUE; END_IF // 三者须为正 → 0A01 / All three must be positive
IF fTotalShiftMm < 0.0 THEN _bCfgBad := TRUE; END_IF                                   // 累计初值负值非法 → 0A01 / Negative initial shift, 0A01
IF (tMoveTimeout <= T#0MS) OR (tSettleTime <= T#0MS) THEN _bCfgBad := TRUE; END_IF      // 时间量须为正 → 0A01 / Time values must be positive
_bCfgOk := NOT _bCfgBad;                    // 本拍组态合法派生量 / Configuration-legal derived flag of this scan
IF (_nShiftCount = 0) AND (_eState = E_DL_HobShiftState.eIdle) AND (NOT _bCfgBad) THEN
    _fShiftUsedMm := fTotalShiftMm;         // 累计初值载入（仅未窜过刀时） / Initial shift loaded before the first step
END_IF
IF (_eState = E_DL_HobShiftState.eIdle) OR (_eState = E_DL_HobShiftState.eDone)
   OR (_eState = E_DL_HobShiftState.eFault) THEN
    _fTargetPosMm := _fShiftUsedMm + fShiftStepMm; // 目标位 = 累计窜刀量 + 步长 [mm]，仅非运行相更新，运行期锁定 / Target updated outside running phases only
END_IF
IF (_bCfgOk) AND (NOT _bAxisBad) AND (_fTargetPosMm > fMaxTravelMm) THEN
    _bOverTravel := TRUE;                   // 目标位超可利用行程，拒动锁存 → 0A02 / Beyond usable travel, 0A02
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜中止入口（段 0→1）、静止判据与复位
 *      Abort entry, standstill criterion and the reset edge
 *-----------------------------------------------------------------------------*)
_bAbortReq   := xAbort OR (NOT xEnable);    // 中止请求合成：显式中止或失能 / Combined abort: explicit abort or enable loss
_bFeedPermit := xClampOpen AND (NOT xClampClosed); // 进给许可：松开到位且未夹紧 / Feed permit: released and not clamped
IF _bAbortReq AND (_uAbortStage = 0) AND (_eState <> E_DL_HobShiftState.eIdle)
   AND (_eState <> E_DL_HobShiftState.eDone) AND (_eState <> E_DL_HobShiftState.eFault) THEN
    _uAbortStage := 1;                      // 进中止段 A：先停进给待轴静止 / Enter abort stage A, await standstill
END_IF
_bStandstill := ABS(fAxisPosMm - _fPosPrevMm) < DL_HOB_STILL_MM; // 本拍位移小于阈值视为静止 / A per-scan move below the threshold is standstill
IF rtReset.Q THEN
    _bCfgBad := FALSE;  _bAxisBad := FALSE; _bOverTravel := FALSE; // 复位清组态/非有限/超程锁存 / Clears configuration, non-finite and travel
    _bReleaseTmo := FALSE; _bClampTmo := FALSE; _bFeedTmo := FALSE; // 复位清松夹/夹紧/超时锁存 / Clears release, clamp and timeout
    _bVerifyErr := FALSE;                   // 复位清对刀校验锁存 / Clears the verification latch
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜定时器与边沿无条件周期刷新（R7：CASE 之外每拍必调，各司其职不复用）
 *      Timers and edges refreshed unconditionally every scan, outside the CASE
 *-----------------------------------------------------------------------------*)
rtStart(CLK := xStart);                     // 启动沿刷新 / Start edge refreshed
rtReset(CLK := xReset);                     // 复位沿刷新 / Reset edge refreshed
tonRelease(IN := (_eState = E_DL_HobShiftState.eRelease) AND (_uAbortStage = 0), PT := tMoveTimeout); // 松夹相超时 / Release timeout
tonMove(IN := (_eState = E_DL_HobShiftState.eShift) AND (_uAbortStage = 0), PT := tMoveTimeout);      // 进给相超时 / Feed timeout
tonSettle(IN := (_eState = E_DL_HobShiftState.eSettle) AND (_uAbortStage = 0), PT := tSettleTime);    // 稳定窗计时 / Settle window
tonReclamp(IN := (_eState = E_DL_HobShiftState.eReclamp) AND (_uAbortStage = 0), PT := tMoveTimeout); // 夹紧确认超时 / Reclamp timeout
tonVerify(IN := (_eState = E_DL_HobShiftState.eVerify) AND (_uAbortStage = 0), PT := tMoveTimeout);   // 对刀校验超时 / Verification timeout
tonStandstill(IN := (_uAbortStage = 1) AND _bStandstill, PT := DL_HOB_ABORT_T); // 中止段 A 静止窗 / Abort stage A standstill window
tonAbortClamp(IN := (_uAbortStage = 2), PT := DL_HOB_CLAMP_T);                  // 中止段 B 再夹紧窗 / Abort stage B reclamp window

(*------------------------------------------------------------------------------
 * 段 6｜中止段推进（1→2 轴静止后按安全序再夹紧，2→0 收口）
 *      Abort stage progression, reclamp only after the axis is standstill
 *-----------------------------------------------------------------------------*)
IF (_uAbortStage = 1) AND tonStandstill.Q THEN
    _uAbortStage := 2;                      // 轴静止窗满，进再夹紧段 / Standstill elapsed, enter reclamp
END_IF
IF _uAbortStage = 2 THEN
    IF xClampClosed THEN
        _uAbortStage := 0;                  // 再夹紧已确认，中止收口 / Reclamp confirmed, abort closed
        _eState      := E_DL_HobShiftState.eIdle; // 回空闲 / Back to idle
    ELSIF tonAbortClamp.Q THEN
        _bClampTmo   := TRUE;               // 再夹紧窗满无反馈 → 0A04 / Window elapsed without feedback, 0A04
        _uAbortStage := 0;                  // 中止段收口 / Abort stage closed
        _eState      := E_DL_HobShiftState.eFault; // 落故障 / Fall to fault
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜状态机（中止期间迁移冻结；本段只做迁移，输出在段 8）
 *      Phase machine, transitions frozen while aborting, outputs in segment 8
 *-----------------------------------------------------------------------------*)
IF _uAbortStage = 0 THEN
    CASE _eState OF
        E_DL_HobShiftState.eIdle:           // 空闲：启动沿 + 组态合法 + 未超程才进松夹 / Idle, legal start edge only
            IF rtStart.Q AND _bCfgOk AND (NOT _bAxisBad) AND (NOT _bOverTravel) AND (NOT _bAbortReq) THEN
                _fTargetPosMm := _fShiftUsedMm + fShiftStepMm; // 启动拍锁定目标位 / Target locked at the start edge
                _eState := E_DL_HobShiftState.eRelease;        // 进松夹相 / To the release phase
            END_IF
        E_DL_HobShiftState.eRelease:        // 松夹：松开到位才允许进给 / Release, feeding only once released
            IF _bFeedPermit THEN _eState := E_DL_HobShiftState.eShift; // 松开到位，进进给相 / Released, to feed
            ELSIF tonRelease.Q THEN _bReleaseTmo := TRUE; _eState := E_DL_HobShiftState.eFault; // 超时未到位 → 0A03 / Timeout, 0A03
            END_IF
        E_DL_HobShiftState.eShift:          // 进给：松夹信号丢失即故障，到位进稳定相 / Feed, permit loss faults
            IF NOT _bFeedPermit THEN _bReleaseTmo := TRUE; _eState := E_DL_HobShiftState.eFault; // 松夹丢失 → 0A03 / Permit lost, 0A03
            ELSIF xAxisInPos THEN _eState := E_DL_HobShiftState.eSettle; // 到位，进稳定相 / In position, to settle
            ELSIF tonMove.Q THEN _bFeedTmo := TRUE; _eState := E_DL_HobShiftState.eFault; // 进给步超时 → 0A05 / Feed timeout, 0A05
            END_IF
        E_DL_HobShiftState.eSettle:         // 稳定：稳定窗满且仍到位才进夹紧 / Settle, reclamp after the window
            IF tonSettle.Q AND xAxisInPos THEN _eState := E_DL_HobShiftState.eReclamp; // 稳定到位，进夹紧 / Stable, to reclamp
            ELSIF tonSettle.Q THEN _bFeedTmo := TRUE; _eState := E_DL_HobShiftState.eFault; // 窗满未到位 → 0A05 / Elapsed, 0A05
            END_IF
        E_DL_HobShiftState.eReclamp:        // 夹紧：夹紧确认才允许对刀校验 / Reclamp, verification only once clamped
            IF xClampClosed AND (NOT xClampOpen) THEN _eState := E_DL_HobShiftState.eVerify; // 夹紧确认，进校验 / Clamped, verify
            ELSIF tonReclamp.Q THEN _bClampTmo := TRUE; _eState := E_DL_HobShiftState.eFault; // 超时未夹紧 → 0A04 / Clamp timeout, 0A04
            END_IF
        E_DL_HobShiftState.eVerify:         // 对刀校验：夹紧须保持，偏差在容差内即完成 / Verify with the clamp held
            IF NOT xClampClosed THEN _bClampTmo := TRUE; _eState := E_DL_HobShiftState.eFault; // 夹紧丢失 → 0A04 / Clamp lost, 0A04
            ELSIF ABS(fAxisPosMm - _fTargetPosMm) <= fPosTolMm THEN
                _fShiftUsedMm := _fShiftUsedMm + fShiftStepMm; // 完成拍提交累计窜刀量 / Accumulated shift committed
                _nShiftCount := _nShiftCount + 1; _bInfoDone := TRUE; // 次数递增 + 完成信息 / Counter plus done info
                _eState := E_DL_HobShiftState.eDone;           // 进完成相 / To the done phase
            ELSIF tonVerify.Q THEN _bVerifyErr := TRUE; _eState := E_DL_HobShiftState.eFault; // 超差 → 0A07 / Deviation, 0A07
            END_IF
        E_DL_HobShiftState.eDone:           // 完成：启动撤销且无中止请求才回空闲 / Done, back to idle once start drops
            IF (NOT xStart) AND (NOT _bAbortReq) THEN _eState := E_DL_HobShiftState.eIdle; END_IF
        E_DL_HobShiftState.eFault:          // 故障：复位沿且组态合法且未超程才回空闲 / Fault, reset edge only
            IF rtReset.Q AND _bCfgOk AND (NOT _bAxisBad) AND (NOT _bOverTravel) THEN _eState := E_DL_HobShiftState.eIdle; END_IF
        ELSE                                // 非法状态兜底（R6：CASE 必带 ELSE）/ Illegal-state fallback
            _bIllegal := TRUE; _eState := E_DL_HobShiftState.eFault; // 非法态 → 0A08，落故障 / Illegal state, 0A08
    END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出置位（次序即安全：进给受许可闸，夹紧两命令互斥）
 *      Output assignment, feed gated by the permit, clamp commands exclusive
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_HobShiftState.eRelease:            // 松夹相：只发松开命令 / Release phase, unclamp only
        xUnclampCmd := TRUE;                // 松开命令 / Unclamp command
    E_DL_HobShiftState.eShift:              // 进给相：命令位 + 进给许可双重闸 / Feed phase, target plus permit
        fCmdPosMm := _fTargetPosMm;         // 目标位命令 / Target position command
        xCmdMove  := _bFeedPermit;          // 未松夹到位不得进给 / Feeding forbidden unless released
    E_DL_HobShiftState.eSettle:             // 稳定相：保持命令位不撤 / Settle phase, command held
        fCmdPosMm := _fTargetPosMm;         // 目标位保持 / Target position held
    E_DL_HobShiftState.eReclamp:            // 夹紧相：只发夹紧命令 / Reclamp phase, clamp only
        xClampCmd := TRUE;                  // 夹紧命令 / Clamp command
    E_DL_HobShiftState.eDone:               // 完成相：完成电平 / Done phase, done level
        bDone := TRUE;                      // 单步完成 / Single step done
    ELSE                                    // 其余相（空闲/校验/故障）全断 / Other phases, all off
        xCmdMove := FALSE; xClampCmd := FALSE; xUnclampCmd := FALSE; // 全输出断 / All outputs off
END_CASE
IF _uAbortStage >= 1 THEN
    xCmdMove    := FALSE;                   // 中止段 A：进给立即断（安全侧） / Abort A, feed cut immediately
    xClampCmd   := FALSE; xUnclampCmd := FALSE; // 静止窗内两夹紧命令均不动（O 型中位保持） / Both idle in the window
    fCmdPosMm   := _fTargetPosMm;           // 命令位保持，禁回零溜刀 / Command held, no return-to-zero creep
    IF _uAbortStage = 2 THEN
        xClampCmd := NOT xClampClosed;      // 中止段 B：未夹紧则发夹紧（安全序） / Abort B, clamp unless clamped
    END_IF
END_IF
bRunning := (_eState <> E_DL_HobShiftState.eIdle) AND (_eState <> E_DL_HobShiftState.eDone)
            AND (_eState <> E_DL_HobShiftState.eFault) AND (_uAbortStage = 0); // 运行标志 / Running flag

(*------------------------------------------------------------------------------
 * 段 9｜出口量与错误码映射（锁存回放，R187：故障相不按当下输入重推断）
 *      Outlet quantities and the error-code map, latched replay
 *-----------------------------------------------------------------------------*)
fShiftUsedMm := _fShiftUsedMm;              // 累计窜刀量出口 [mm] / Accumulated shift outlet [mm]
nShiftCount  := _nShiftCount;               // 窜刀次数出口 [次] / Shift count outlet
xTravelLimit := _bOverTravel;               // 超程拒动出口 / Travel-limit outlet
IF _bIllegal THEN nErrCode := 16#0008_0A08; bError := TRUE;        // 故障级兜底：非法态 / Fault, illegal state fallback
ELSIF _bCfgBad THEN nErrCode := 16#0008_0A01; bError := TRUE;      // 故障级：组态非法 / Fault, illegal configuration
ELSIF _bAxisBad THEN nErrCode := 16#0008_0A06; bError := TRUE;     // 故障级：轴位非有限 / Fault, non-finite position
ELSIF _bOverTravel THEN nErrCode := 16#0008_0A02; bError := TRUE;  // 故障级：超窜刀行程 / Fault, over travel
ELSIF _bReleaseTmo THEN nErrCode := 16#0008_0A03; bError := TRUE;  // 故障级：松夹不到位 / Fault, release not reached
ELSIF _bClampTmo THEN nErrCode := 16#0008_0A04; bError := TRUE;    // 故障级：夹紧未确认 / Fault, clamp not confirmed
ELSIF _bFeedTmo THEN nErrCode := 16#0008_0A05; bError := TRUE;     // 故障级：进给步超时 / Fault, feed step timeout
ELSIF _bVerifyErr THEN nErrCode := 16#0008_0A07; bError := TRUE;   // 故障级：对刀超差 / Fault, verification out of tolerance
ELSIF _bInfoDone THEN nErrCode := 16#0008_0101;                    // 信息级：单步完成，不置 bError / Info, step done
END_IF
_fPosPrevMm := fAxisPosMm;                  // 位置快照推进（供下拍静止判据） / Position snapshot advanced for the next scan
END_FUNCTION_BLOCK
