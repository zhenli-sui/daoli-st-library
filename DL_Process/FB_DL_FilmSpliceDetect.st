// =====================================================================
// FB_DL_FilmSpliceDetect.st
// 薄膜接膜位检测与降速段放行（位置锁存消费 + 放行窗 + 接料计数）
// Film splice detection with slow-permit window and splice counting
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_0485 ~ 16#0005_0489 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: packaging, splice-detection, conveyor, film
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 12)
// 分层声明: 位置锁存语义消费 DL_Motion 标记位置锁存件（bLatched/锁存位置
//           输出经引脚注入）; 累计走米经定长计米件注入; 停机后位置锁存
//           不触发放行（run-on 语义沿用输送区件）, 计时器停机期间冻结
// =====================================================================
FUNCTION_BLOCK FB_DL_FilmSpliceDetect
VAR_INPUT
    bEnable         : BOOL := FALSE;    // 使能 / Enable
    bMarkLatchValid : BOOL := FALSE;    // 接膜位锁存有效回读注入（标记锁存件 bLatched 语义）/ Mark latch valid injected
    fMarkLatchPos_m : REAL := 0.0;      // 接膜位锁存位置注入 0~10000 m / Latched splice position [m]
    fConvDist_m     : REAL := 0.0;      // 输送累计走米注入 0~10000 m / Accumulated conveyor distance [m]
    bConvRun        : BOOL := FALSE;    // 输送运行反馈 / Conveyor run feedback
    fConvSpeed_mmin : REAL := 60.0;     // 输送线速度 0~300 m/min / Line speed [m/min]
    fApproachDist_m : REAL := 0.5;      // 接近判定提前量 0~50 m / Approach lead distance [m]
    fMinFilmLen_m   : REAL := 1.0;      // 最小膜长（两膜间距下限）0~100 m / Min film length [m]
    tSlowWin        : TIME := T#2S;     // 降速放行窗 T#10MS~T#60S / Slow permit window [s]
END_VAR
VAR_OUTPUT
    bSpliceApproach : BOOL := FALSE;    // 接膜接近标志 / Splice approach flag
    bSlowPermit     : BOOL := FALSE;    // 降速放行允许 / Slow permit output
    uSpliceCount    : UDINT := 0;       // 接料计数（仅在放行窗完成时递增）/ Splice count
    eErr            : UDINT := 16#0005_0485;  // 错误码 / Error code
END_VAR
VAR
    rtrLatch   : R_TRIG;                // 锁存有效沿, 每拍无条件刷新 / Latch edge, refreshed every cycle
    tonSlow    : TON;                   // 降速放行窗定时器, 每拍无条件刷新 / Slow window timer, refreshed every cycle
    xArmed     : BOOL := FALSE;         // 接膜布防标志 / Splice armed flag
    xApproach  : BOOL := FALSE;         // 接近窗激活标志 / Approach active flag
    fPrevPos_m : REAL := 0.0;           // 上次锁存位置 / Previous latched position [m]
    xHadLatch  : BOOL := FALSE;         // 已有历史锁存标记 / Has previous latch flag
    bSpacingErr: BOOL := FALSE;         // 膜间距不足标记 / Spacing error flag
    bCfgErr    : BOOL := FALSE;         // 组态非法标记 / Configuration error flag
    bSpdErr    : BOOL := FALSE;         // 速度非法标记 / Speed error flag
    fRemain_m  : REAL := 0.0;           // 到接膜位剩余距离 / Remaining distance [m]
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_0485 信息 待机或检测正常
//   16#0005_0486 故障 线速度非有限/为负/超 300 m/min（安全侧: 放行保持禁止）,
//                解除式 = 速度恢复合法域
//   16#0005_0487 故障 组态非法（提前量/最小膜长非有限或不大于 0）,
//                解除式 = 恢复合法组态
//   16#0005_0488 故障 两膜间距小于最小膜长（连续锁存差分不足, 组态或上游异常）,
//                解除式 = 下次锁存间距恢复到最小膜长以上
//   16#0005_0489 信息 降速放行窗进行中
// ---------------------------------------------------------------------

// ---- 边沿与定时器实例无条件周期刷新 / Unconditional edge and timer refresh ----
rtrLatch(CLK := bMarkLatchValid);   // 锁存有效沿 / Latch edge
tonSlow(IN := xArmed AND xApproach AND bConvRun,
        PT := tSlowWin);            // 放行窗计时（停机冻结, run-on 语义）/ Window timing frozen when stopped

// ---- 组态与速度闸 / Configuration and speed gates ----
bCfgErr := FALSE;
IF (fApproachDist_m <> fApproachDist_m) OR (fApproachDist_m <= 0.0) OR (fApproachDist_m > 50.0) THEN
    bCfgErr := TRUE;                // 提前量非法 / Illegal lead distance
END_IF
IF (fMinFilmLen_m <> fMinFilmLen_m) OR (fMinFilmLen_m <= 0.0) OR (fMinFilmLen_m > 100.0) THEN
    bCfgErr := TRUE;                // 最小膜长非法 / Illegal min film length
END_IF
bSpdErr := (fConvSpeed_mmin <> fConvSpeed_mmin)
        OR (fConvSpeed_mmin < 0.0) OR (fConvSpeed_mmin > 300.0);    // 速度越域 / Speed out of domain

// ---- 未使能待机复位 / Standby reset when disabled ----
IF NOT bEnable THEN
    xArmed      := FALSE;           // 清布防 / Clear armed
    xApproach   := FALSE;           // 清接近 / Clear approach
    bSpacingErr := FALSE;           // 清间距错 / Clear spacing error
END_IF

// ---- 锁存沿: 布防与间距校验 / Latch edge: arm and spacing check ----
IF rtrLatch.Q AND bEnable AND (NOT bCfgErr) THEN
    IF xHadLatch AND (fMarkLatchPos_m > fPrevPos_m)
       AND ((fMarkLatchPos_m - fPrevPos_m) < fMinFilmLen_m) THEN
        bSpacingErr := TRUE;        // 间距不足判组态故障 / Spacing below minimum
    ELSIF xHadLatch AND ((fMarkLatchPos_m - fPrevPos_m) >= fMinFilmLen_m) THEN
        bSpacingErr := FALSE;       // 间距恢复解除 / Spacing recovered, release
    END_IF
    fPrevPos_m := fMarkLatchPos_m;  // 更新上次锁存位置 / Update previous position
    xHadLatch  := TRUE;             // 置历史锁存标记 / Set previous-latch flag
    xArmed     := TRUE;             // 拍 N 布防等待接近 / Arm for approach
    xApproach  := FALSE;            // 接近窗复位 / Reset approach
END_IF

// ---- 接近判定与放行窗（输出缺省收口）/ Approach judge and permit window ----
bSpliceApproach := FALSE;           // 缺省不接近 / Default not approaching
bSlowPermit     := FALSE;           // 缺省不放行 / Default no permit
IF xArmed AND bEnable AND (NOT bCfgErr) AND (NOT bSpdErr) AND (NOT bSpacingErr) THEN
    fRemain_m := fMarkLatchPos_m - fConvDist_m;     // 剩余距离 / Remaining distance [m]
    IF bConvRun THEN
        IF (NOT xApproach) AND (fRemain_m <= fApproachDist_m) THEN
            xApproach := TRUE;      // 拍 N 进入接近相 / Enter approach
        END_IF
    END_IF
    IF xApproach THEN
        bSpliceApproach := TRUE;    // 接近标志 / Approach flag
        bSlowPermit     := TRUE;    // 降速放行 / Slow permit
        IF tonSlow.Q THEN
            // 本拍行为: 放行窗运行中完成 → 计数并收口（run-on: 停机不计数）
            // Window completed while running: count and close
            uSpliceCount := uSpliceCount + 1;   // 接料计数 / Count splice
            xArmed    := FALSE;             // 拍 N+1 布防收口 / Disarm
            xApproach := FALSE;             // 接近收口 / Close approach
        END_IF
    END_IF
END_IF

// ---- 错误码仲裁 / Error arbitration ----
IF bCfgErr THEN
    eErr := 16#0005_0487;           // 组态非法 / Config fault
ELSIF bSpdErr THEN
    eErr := 16#0005_0486;           // 速度越域 / Speed fault
ELSIF bSpacingErr THEN
    eErr := 16#0005_0488;           // 膜间距不足 / Spacing fault
ELSIF xApproach THEN
    eErr := 16#0005_0489;           // 放行窗进行中 / Window active
ELSE
    eErr := 16#0005_0485;           // 待机或正常 / Standby or normal
END_IF

END_FUNCTION_BLOCK
