// =====================================================================
// FB_DL_ScreenPrintAlign.st
// 丝网印刷对位（相机 dx/dy/dθ → XY 纠偏相对定位 → 公差判定）
// Screen printing alignment FB via I_DL_MotionAxis contract
// 码位: 16#0004_0340 ~ 16#0004_0344 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 12)
// =====================================================================
// 枚举: E_DL_ScreenPrintState（归属 Ownership：E_DL_ScreenPrintState 归属本文件
//       FB_DL_ScreenPrintAlign，全库唯一定义，本件只定义不重声明）
//       R74 说明：本件原借用 DL_Motion/FB_DL_StringCutAlign 的 E_DL_ScreenPrintState，
//       该枚举成员集为 ( eIdle/eCalc/eWaitPos/eDone/eFault )，无 eMove 与 eVerify，
//       跨件借用即产生 E048 未解析引用；两件相位语义域不同（本件为相机对位四相），
//       故按 R264 归属断言改为携带自有枚举，成员集按本文件实际用到的相位取值。
// =====================================================================
TYPE E_DL_ScreenPrintState :
(
    eIdle   := 0,     // 空闲待触发 / Idle, waiting for trigger
    eCalc   := 10,    // 计算相：θ 补偿换算 / Calculating theta compensation
    eMove   := 20,    // 移动相：XY 逐轴相对定位 / Moving, per-axis relative positioning
    eVerify := 30,    // 验证相：公差判定 / Verifying tolerance verdict
    eDone   := 40,    // 完成态：结论保持至下一触发 / Done, verdict held until next trigger
    eFault  := 90     // 故障锁存态（仅 bReset 沿迁出）/ Fault latched, exits on reset edge
);
END_TYPE

// =====================================================================
FUNCTION_BLOCK FB_DL_ScreenPrintAlign
VAR_INPUT
    bEnable         : BOOL  := FALSE;   // 使能 / Enable
    bTrigger        : BOOL  := FALSE;   // 上升沿启动一次对位 / Trigger on rising edge
    bReset          : BOOL  := FALSE;   // 复位故障 / Reset
    fCamDx_mm       : REAL  := 0.0;     // 相机 X 偏差 -20~20 mm / Camera dX [mm]
    fCamDy_mm       : REAL  := 0.0;     // 相机 Y 偏差 -20~20 mm / Camera dY [mm]
    fCamDTheta_deg  : REAL  := 0.0;     // 相机角度偏差 -10~10 ° / Camera dTheta [deg]
    fRotRadius_mm   : REAL  := 200.0;   // 旋转补偿半径 10~2000 mm / Rotation radius [mm]
    fTol_mm         : REAL  := 0.02;    // XY 公差 0.001~2 mm / XY tolerance [mm]
    fTolTheta_deg   : REAL  := 0.05;    // 角度公差 0.001~2 ° / Theta tolerance [deg]
    fCorrMax_mm     : REAL  := 5.0;     // 最大可纠偏差 0.1~20 mm / Max correctable [mm]
    fSpeed_mmS      : REAL  := 20.0;    // 定位速度 1~200 mm/s / Speed [mm/s]
    tMoveMax        : TIME  := T#5S;    // 单次定位超时 T#100MS~T#60S / Move timeout [s]
    uRetryMax       : USINT  := 3;      // 最大重试次数 1~10 / Max retries
END_VAR
VAR_IN_OUT
    iAxisX          : I_DL_MotionAxis;  // X 轴契约引用 / X axis interface
    iAxisY          : I_DL_MotionAxis;  // Y 轴契约引用 / Y axis interface
END_VAR
VAR_OUTPUT
    fCorrX_mm       : REAL;             // 本次 X 纠偏量 mm / X correction [mm]
    fCorrY_mm       : REAL;             // 本次 Y 纠偏量 mm / Y correction [mm]
    bInTol          : BOOL;             // 纠偏后进公差 / In tolerance
    bDegraded       : BOOL;             // θ 超差不旋转降级 / Theta degraded
    uRetryCnt       : USINT;            // 已重试次数 / Retry count
    eState          : E_DL_ScreenPrintState;  // 状态 / State
    eErr            : UDINT;            // 错误码 / Error code
END_VAR
VAR
    rtrigTrigger    : R_TRIG;           // 触发沿检测（无条件刷新）/ Trigger edge detector
    fThetaRad       : REAL;             // θ 弧度值 / Theta in radians [rad]
    fCorrXTarget    : REAL;             // X 纠偏目标 / X correction target [mm]
    fCorrYTarget    : REAL;             // Y 纠偏目标 / Y correction target [mm]
    bXDone          : BOOL := FALSE;    // X 轴完成标志（换轴前清）/ X done flag, cleared on axis switch
    bXIssued        : BOOL := FALSE;    // X 轴指令已发单锁（防每拍重复下发）/ X single-shot issued lock
    bYIssued        : BOOL := FALSE;    // Y 轴指令已发单锁（防每拍重复下发）/ Y single-shot issued lock
    bAxisOk         : BOOL;             // 轴指令受理标记 / Axis command accepted
    tonMove         : TON;              // 定位超时定时器（无条件刷新）/ Move timeout timer
    tMoveMaxS       : REAL;             // 超时秒值 / Timeout seconds [s]
    xFirstScan      : BOOL  := TRUE;    // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0004_0340 信息 对位完成（eDone）
//   16#0004_0341 故障 偏差/参数非有限 / tMoveMax 非法 / 轴接口未就绪
//   16#0004_0342 故障 fTol_mm ≤ 0 / fSpeed_mmS ≤ 0 / uRetryMax = 0（组态错）
//   16#0004_0343 信息 ABS(fCamDTheta_deg) > fTolTheta_deg → 仅 XY 纠偏（bDegraded=TRUE）
//   16#0004_0344 故障 ABS(dx)>fCorrMax 或 ABS(dy)>fCorrMax → 拒纠；或重试达上限仍未进公差
// ---------------------------------------------------------------------

// ---- 超时秒值 / Timeout seconds ----
tMoveMaxS := TIME_TO_REAL(tMoveMax) / 1000.0;   // 秒值 / Seconds [s]

// ---- 触发沿检测（每拍无条件刷新，R7 纪律）/ Trigger edge, unconditional refresh ----
rtrigTrigger(CLK := bTrigger);  // 沿检测 / Edge detection

// ---- 非有限与时域闸 / Finite and time-domain gate ----
IF (fCamDx_mm <> fCamDx_mm) OR (ABS(fCamDx_mm) >= 1.0E12)
   OR (fCamDy_mm <> fCamDy_mm) OR (ABS(fCamDy_mm) >= 1.0E12)
   OR (fCamDTheta_deg <> fCamDTheta_deg) OR (ABS(fCamDTheta_deg) >= 1.0E12)
   OR (fRotRadius_mm <> fRotRadius_mm) OR (ABS(fRotRadius_mm) >= 1.0E12)
   OR (fTol_mm <> fTol_mm) OR (ABS(fTol_mm) >= 1.0E12)
   OR (fCorrMax_mm <> fCorrMax_mm) OR (ABS(fCorrMax_mm) >= 1.0E12)
   OR (fSpeed_mmS <> fSpeed_mmS) OR (ABS(fSpeed_mmS) >= 1.0E12)
   OR (tMoveMax = T#0MS) OR (tMoveMaxS < 0.1) OR (tMoveMaxS > 60.0) THEN
    eState := E_DL_ScreenPrintState.eFault;   // 故障态 / Fault state
    eErr := 16#0004_0341;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fTol_mm <= 0.0) OR (fSpeed_mmS <= 0.0) OR (uRetryMax = 0) THEN
    eState := E_DL_ScreenPrintState.eFault;   // 故障态 / Fault state
    eErr := 16#0004_0342;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    eState := E_DL_ScreenPrintState.eIdle;    // 空闲态 / Idle
    bInTol := FALSE;            // 结论复位 / Verdict reset
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    eState := E_DL_ScreenPrintState.eIdle;    // 回空闲 / Idle
    bInTol := FALSE;            // 结论复位 / Verdict reset
    bDegraded := FALSE;         // 降级复位 / Degraded reset
    uRetryCnt := 0;             // 重试清零 / Retry cleared
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 故障复位 / Fault reset ----
IF (eState = E_DL_ScreenPrintState.eFault) AND bReset THEN
    eState := E_DL_ScreenPrintState.eIdle;    // 回空闲 / Idle
    uRetryCnt := 0;             // 重试清零 / Retry cleared
    bInTol := FALSE;            // 结论复位 / Verdict reset
END_IF

// ---- θ 降级判（先于状态机，供信息级登记）/ Theta degradation check ----
bDegraded := (ABS(fCamDTheta_deg) > fTolTheta_deg);     // 降级标志 / Degraded flag

// ---- 状态机 / State machine ----
CASE eState OF

    E_DL_ScreenPrintState.eIdle:      // 空闲态 / Idle
        bInTol := FALSE;        // 结论复位 / Verdict reset
        eErr := 16#0004_0340;   // 信息级：空闲正常 / Info: idle
        // 触发沿受理（bBusy 期丢弃新触发不排队）/ Accept trigger edge
        IF rtrigTrigger.Q THEN
            // 拒纠闸：偏差超最大可纠值 → 不动轴直接故障 / Reject oversize deviation
            IF (ABS(fCamDx_mm) > fCorrMax_mm) OR (ABS(fCamDy_mm) > fCorrMax_mm) THEN
                eState := E_DL_ScreenPrintState.eFault;   // 故障态 / Fault
                eErr := 16#0004_0344;   // 故障码：拒纠 / Fault: rejected
            ELSIF (iAxisX = 0) OR (iAxisY = 0) THEN    // 接口引用未注入判定（引用为空判零口径）/ Interface reference not injected, null-reference test
                eState := E_DL_ScreenPrintState.eFault;   // 故障态 / Fault
                eErr := 16#0004_0341;   // 故障码：接口未就绪 / Fault: interface
            ELSE
                eState := E_DL_ScreenPrintState.eCalc;    // 进入计算相 / Go to calc
            END_IF
        END_IF

    E_DL_ScreenPrintState.eCalc:      // 计算相：θ 补偿换算 / Calc: theta compensation
        // 小角度近似适用域注释：|θ|≤10° 内 SIN 近似线性误差 <0.5 %
        // Small-angle approximation valid for |theta| <= 10 deg, error < 0.5 %
        fThetaRad := fCamDTheta_deg * 3.14159265 / 180.0;   // 度转弧度 / Deg to rad
        // 旋转臂分解（θ 补偿项按半径投影）/ Rotational arm decomposition
        fCorrXTarget := fCamDx_mm - fThetaRad * fRotRadius_mm;  // X 目标含 θ 补偿 / X target
        fCorrYTarget := fCamDy_mm;      // Y 目标不含旋转投影 / Y target
        fCorrX_mm := fCorrXTarget;      // 输出 X 纠偏 / Output X
        fCorrY_mm := fCorrYTarget;      // 输出 Y 纠偏 / Output Y
        uRetryCnt := 0;             // 本轮重试清零 / Retry cleared
        eState := E_DL_ScreenPrintState.eMove;    // 进入移动相 / Go to move

    E_DL_ScreenPrintState.eMove:      // 移动相：单轴相对定位 / Move: relative positioning per axis
        tonMove(IN := TRUE, PT := tMoveMax);    // 超时定时器无条件刷新 / Unconditional refresh
        IF tonMove.Q THEN
            // 超时：中止不再发新指令（R27 教训）/ Timeout: abort, no new commands
            eState := E_DL_ScreenPrintState.eFault;   // 故障态 / Fault
            eErr := 16#0004_0341;   // 故障码 / Fault code
            RETURN;                 // 本拍结束 / End of cycle
        END_IF
        IF NOT bXDone THEN
            // X 轴：先发单再等到位（接口契约 MoveRelative(fDist, fVel, fAcc)，无 bDone 引脚，
            // 到位判据取 eState = eStandstill；单发语义由本件 bXIssued 单发锁承担）
            // X axis: issue once, then wait for arrival (contract has no bDone pin;
            // arrival is eState = eStandstill, single-shot owned by bXIssued)
            IF NOT bXIssued THEN
                IF iAxisX.MoveRelative(fDist := fCorrXTarget, fVel := fSpeed_mmS,
                                       fAcc := fSpeed_mmS * 10.0) THEN   // 1/10 秒达速等效加减速度 [mm/s²] / Equivalent accel
                    bXIssued := TRUE;       // 已发单 / Issued
                    bAxisOk := TRUE;        // 受理 / Accepted
                ELSE
                    eState := E_DL_ScreenPrintState.eFault;   // 指令拒绝 → 故障 / Rejected
                    eErr := 16#0004_0341;   // 故障码 / Fault code
                    RETURN;             // 本拍结束 / End of cycle
                END_IF
            ELSIF iAxisX.bError THEN
                eState := E_DL_ScreenPrintState.eFault;   // 轴错误 → 故障 / Axis error
                eErr := 16#0004_0341;   // 故障码 / Fault code
                RETURN;                 // 本拍结束 / End of cycle
            ELSIF iAxisX.eState = E_DL_AxisState.eStandstill THEN
                bXDone := TRUE;         // X 到位（待机态），换 Y 前清 X 标记（R27 教训）/ X arrived
                bXIssued := FALSE;      // 清单发锁，供 Y 轴复用 / Release single-shot
                tonMove(IN := FALSE, PT := tMoveMax);   // 重置超时 / Reset timeout
            END_IF
        ELSE
            // Y 轴：同构（契约三参数口径）/ Y axis, same three-parameter contract
            IF NOT bYIssued THEN
                IF iAxisY.MoveRelative(fDist := fCorrYTarget, fVel := fSpeed_mmS,
                                       fAcc := fSpeed_mmS * 10.0) THEN   // 等效加减速度 [mm/s²] / Equivalent accel
                    bYIssued := TRUE;       // 已发单 / Issued
                    bAxisOk := TRUE;        // 受理 / Accepted
                ELSE
                    eState := E_DL_ScreenPrintState.eFault;   // 指令拒绝 → 故障 / Rejected
                    eErr := 16#0004_0341;   // 故障码 / Fault code
                    RETURN;             // 本拍结束 / End of cycle
                END_IF
            ELSIF iAxisY.bError THEN
                eState := E_DL_ScreenPrintState.eFault;   // 轴错误 → 故障 / Axis error
                eErr := 16#0004_0341;   // 故障码 / Fault code
                RETURN;                 // 本拍结束 / End of cycle
            ELSIF iAxisY.eState = E_DL_AxisState.eStandstill THEN
                bXDone := FALSE;        // 清轴标志（换轴前清，R27 教训）/ Clear axis flag
                bYIssued := FALSE;      // 清单发锁 / Release single-shot
                eState := E_DL_ScreenPrintState.eVerify;  // 进入验证相 / Go to verify
            END_IF
        END_IF

    E_DL_ScreenPrintState.eVerify:    // 验证相：公差判定 / Verify: tolerance verdict
        // 边界含等号 / Boundary inclusive
        IF (ABS(fCamDx_mm) <= fTol_mm) AND (ABS(fCamDy_mm) <= fTol_mm) THEN
            bInTol := TRUE;     // 进公差 / In tolerance
            eState := E_DL_ScreenPrintState.eDone;    // 完成态 / Done
        ELSE
            uRetryCnt := uRetryCnt + 1;     // 重试计数 / Retry count
            IF uRetryCnt >= uRetryMax THEN
                eState := E_DL_ScreenPrintState.eFault;   // 重试耗尽 → 故障锁存 / Fault latch
                eErr := 16#0004_0344;   // 故障码 / Fault code
            ELSE
                eState := E_DL_ScreenPrintState.eMove;    // 重发定位 / Retry move
            END_IF
        END_IF

    E_DL_ScreenPrintState.eDone:      // 完成态 / Done
        bInTol := TRUE;         // 结论保持 / Verdict held
        eErr := 16#0004_0340;   // 信息级：对位完成 / Info: done
        // θ 降级信息级登记（完成且降级时覆盖信息码）/ Degraded info code
        IF bDegraded THEN
            eErr := 16#0004_0343;   // 信息级：仅 XY 纠偏 / Info: XY only
        END_IF
        // 下一触发沿重新进入计算相 / Next trigger restarts
        IF rtrigTrigger.Q THEN
            eState := E_DL_ScreenPrintState.eCalc;    // 重启 / Restart
        END_IF

    E_DL_ScreenPrintState.eFault:     // 故障态 / Fault
        bInTol := FALSE;        // 结论复位 / Verdict reset
        // eErr 已在置故障处赋值，锁存回放不重推断 / Code latched
        IF bReset THEN
            eState := E_DL_ScreenPrintState.eIdle;    // 复位回空闲 / Reset to idle
            uRetryCnt := 0;     // 重试清零 / Retry cleared
        END_IF

    ELSE                        // 非法状态拦截 / Illegal state interception
        eState := E_DL_ScreenPrintState.eFault;   // 落故障态 / Fall to fault
        eErr := 16#0004_0341;   // 故障码 / Fault code
END_CASE

// ---- 降级信息级（非完成态也登记，供上位观察）/ Degraded info outside done ----
IF bDegraded AND (eState = E_DL_ScreenPrintState.eMove) AND (eErr = 16#0004_0340) THEN
    eErr := 16#0004_0343;       // 信息级：仅 XY / Info: XY only
END_IF

END_FUNCTION_BLOCK
