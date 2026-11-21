// =====================================================================
// FB_DL_TrackerMotDiag.st
// 跟踪支架回转减速机健康诊断（电流偏差 + 跟随误差 EWMA → 0~100 评分）
// Tracker drive health diagnosis FB
// 码位: 16#0004_034A ~ 16#0004_034E (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 14)
// =====================================================================
FUNCTION_BLOCK FB_DL_TrackerMotDiag
VAR_INPUT
    bEnable        : BOOL  := FALSE;   // 使能 / Enable
    bReset         : BOOL  := FALSE;   // 复位锁存 / Reset
    fCurrent_A     : REAL  := 0.0;     // 电机电流 0~200 A / Motor current [A]
    fBaseCurrent_A : REAL  := 5.0;     // 标定基线电流 >0 A / Baseline current [A]
    fFollowErr_deg : REAL  := 0.0;     // 跟随误差 -10~10 ° / Following error [deg]
    fSpeed_degS    : REAL  := 0.0;     // 转速 -5~5 °/s / Speed [deg/s]
    fSpeedMin_degS : REAL  := 0.05;    // 判定运行的最小转速 >0 °/s / Min speed [deg/s]
    fErrMax_deg    : REAL  := 1.0;     // 跟随误差报警 0.01~20 ° / Max following error [deg]
    fCurDevMax_pct : REAL  := 60.0;    // 电流偏差报警 5~300 % / Max current deviation [%]
    fAlpha         : REAL  := 0.2;     // EWMA 系数 (0,1] / EWMA factor [-]
END_VAR
VAR_OUTPUT
    fCurDev_pct    : REAL;             // 电流相对偏差 % / Current deviation [%]
    fEwmaErr_deg   : REAL;             // 跟随误差 EWMA ° / EWMA error [deg]
    uScore         : USINT;            // 健康评分 0~100 / Health score
    bWarn          : BOOL;             // 预警（评分 < 60）/ Warning
    bAlarm         : BOOL;             // 报警（评分 < 30 或越限，锁存）/ Alarm latched
    eErr           : UDINT;            // 错误码 / Error code
END_VAR
VAR
    fScoreR        : REAL;             // 评分实数中间量 / Score real intermediate [-]
    fAlphaSafe     : REAL;             // 钳位后 EWMA 系数 / Clamped alpha [-]
    bMoving        : BOOL;             // 运行判 / Moving flag
    xFirstScan     : BOOL  := TRUE;    // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0004_034A 信息 诊断正常（评分 ≥ 60）
//   16#0004_034B 故障 输入非有限
//   16#0004_034C 故障 fBaseCurrent_A ≤ 0 / fAlpha ≤ 0 或 >1 / fErrMax_deg ≤ 0（组态错）
//   16#0004_034D 信息 静止（ABS(fSpeed_degS) < fSpeedMin_degS）→ 电流项保持上次值，仅更误差项
//   16#0004_034E 故障 fCurDev_pct > fCurDevMax_pct 或 ABS(fEwmaErr_deg) > fErrMax_deg → bAlarm=TRUE 锁存
// ---------------------------------------------------------------------

// ---- 非有限闸 / Finite gate ----
IF (fCurrent_A <> fCurrent_A) OR (ABS(fCurrent_A) >= 1.0E12)
   OR (fBaseCurrent_A <> fBaseCurrent_A) OR (ABS(fBaseCurrent_A) >= 1.0E12)
   OR (fFollowErr_deg <> fFollowErr_deg) OR (ABS(fFollowErr_deg) >= 1.0E12)
   OR (fSpeed_degS <> fSpeed_degS) OR (ABS(fSpeed_degS) >= 1.0E12)
   OR (fSpeedMin_degS <> fSpeedMin_degS) OR (ABS(fSpeedMin_degS) >= 1.0E12)
   OR (fErrMax_deg <> fErrMax_deg) OR (ABS(fErrMax_deg) >= 1.0E12)
   OR (fCurDevMax_pct <> fCurDevMax_pct) OR (ABS(fCurDevMax_pct) >= 1.0E12)
   OR (fAlpha <> fAlpha) OR (ABS(fAlpha) >= 1.0E12) THEN
    eErr := 16#0004_034B;       // 故障码 / Fault code
    RETURN;                     // 输出保持 / Outputs hold
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fBaseCurrent_A <= 0.0) OR (fAlpha <= 0.0) OR (fAlpha > 1.0) OR (fErrMax_deg <= 0.0) THEN
    eErr := 16#0004_034C;       // 故障码 / Fault code
    RETURN;                     // 输出保持 / Outputs hold
END_IF

// ---- 首扫：EWMA 初值 = 当拍误差（R16 首扫纪律）/ First scan: EWMA init = current error ----
IF xFirstScan THEN
    fEwmaErr_deg := fFollowErr_deg;     // 初值 / Init
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    bWarn := FALSE;             // 预警复位 / Warn reset
    eErr := 16#0004_034A;       // 信息级：空闲 / Info: idle
    RETURN;                     // 评分与报警锁存保持 / Score and latch hold
END_IF

// ---- 运行判 / Moving check ----
bMoving := (ABS(fSpeed_degS) >= fSpeedMin_degS);    // 运行标志 / Moving flag

// ---- 跟随误差 EWMA（3 行内联）/ EWMA inline ----
fEwmaErr_deg := fEwmaErr_deg + fAlpha * (fFollowErr_deg - fEwmaErr_deg);    // EWMA / EWMA update

// ---- 电流偏差（分母下限闸已由组态错保证 >0）/ Current deviation ----
IF bMoving THEN
    fCurDev_pct := (fCurrent_A - fBaseCurrent_A) / fBaseCurrent_A * 100.0;  // 相对偏差 % / Deviation [%]
    IF fCurDev_pct < 0.0 THEN
        fCurDev_pct := 0.0;     // 轻载不算负偏差 / Light load not negative
    END_IF
END_IF
// 静止时电流项保持上次值（电流无意义，不误判堵转）/ Stationary: hold current term

// ---- 报警锁存（越限判 + 解除路径）/ Alarm latch with release path ----
IF bAlarm THEN
    // 锁存回放，不按当下输入重推断 / Latched replay
    eErr := 16#0004_034E;       // 故障码回放 / Fault code replay
    IF bReset
       AND (fCurDev_pct <= fCurDevMax_pct)
       AND (ABS(fEwmaErr_deg) <= fErrMax_deg) THEN
        bAlarm := FALSE;        // 解除：越限量已回落 / Release when back under limits
    END_IF
    RETURN;                     // 锁存中评分冻结 / Score frozen while latched
END_IF

// ---- 越限直接报警（堵转/异物 或 跟随误差超限）/ Direct alarm on limits ----
IF (fCurDev_pct > fCurDevMax_pct) OR (ABS(fEwmaErr_deg) > fErrMax_deg) THEN
    bAlarm := TRUE;             // 锁存 / Latch
    eErr := 16#0004_034E;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 健康评分 / Health score ----
// 公式：100 - 0.5×max(0, fCurDev_pct-20) - 20×ABS(fEwmaErr_deg)/fErrMax_deg
fScoreR := 100.0
           - 0.5 * (fCurDev_pct - 20.0)      // 电流偏差罚项（负值由判 max 处理）/ Current penalty
           - 20.0 * ABS(fEwmaErr_deg) / fErrMax_deg;     // 误差罚项 / Error penalty
IF fCurDev_pct <= 20.0 THEN
    // 电流偏差 ≤20 % 无电流罚项 / No current penalty under 20 %
    fScoreR := 100.0 - 20.0 * ABS(fEwmaErr_deg) / fErrMax_deg;  // 只含误差罚项 / Error only
END_IF
// 结果钳 [0,100] / Clamp score
IF fScoreR > 100.0 THEN
    fScoreR := 100.0;           // 上限 / Upper clamp
ELSIF fScoreR < 0.0 THEN
    fScoreR := 0.0;             // 下限 / Lower clamp
END_IF
// TRUNC 取整（禁止 TRUNC+1，R28 整数进位纪律）/ Truncate, no +1
uScore := REAL_TO_USINT(TRUNC(fScoreR));    // 评分输出 / Score output

// ---- 预警判 / Warn verdict ----
bWarn := (uScore < 60);         // 评分 < 60 预警 / Warn under 60

// ---- 错误码 / Error code ----
IF bWarn THEN
    eErr := 16#0004_034D;       // 信息级：预警或静止登记 / Info: warn or stationary
ELSE
    eErr := 16#0004_034A;       // 信息级：诊断正常 / Info: normal
END_IF

// ---- 静止信息级覆盖 / Stationary info override ----
IF NOT bMoving THEN
    eErr := 16#0004_034D;       // 信息级：静止只更误差项 / Info: stationary
END_IF

END_FUNCTION_BLOCK
