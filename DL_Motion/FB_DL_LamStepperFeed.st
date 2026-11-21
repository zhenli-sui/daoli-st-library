// =====================================================================
// FB_DL_LamStepperFeed.st
// 层压机铺膜步进送料（开环步进契约消费 + 膜长累计 + 保养窗冻结 + 堵转判据）
// Laminator film stepper feeding with maintenance freeze and stall judge
// 所属子库: DL_Motion    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0004_0359 ~ 16#0004_035D (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: photovoltaic, laminator, stepper-open-loop, maintenance
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 15)
// 分层声明: 本件为组合编排件, 开环步进运动语义全部经引脚注入消费
//           （就绪/完成/故障回读对应开环步进契约, 不自造轴状态枚举）;
//           累计送料经定长计米件注入; 保养窗经保养窗管理件注入
// =====================================================================
FUNCTION_BLOCK FB_DL_LamStepperFeed
VAR_INPUT
    bStepperReady    : BOOL := FALSE;   // 步进驱动就绪回读注入 / Stepper ready feedback injected
    bStepperDone     : BOOL := FALSE;   // 步进完成回读注入 / Stepper done feedback injected
    bStepperFault    : BOOL := FALSE;   // 步进故障回读注入 / Stepper fault feedback injected
    bFeedStart       : BOOL := FALSE;   // 送料步启动命令 / Feed step start command
    fFilmLen_m       : REAL := 300.0;   // 单卷膜长 0~2000 m / Film roll length [m]
    fStepLen_m       : REAL := 0.5;     // 单步步长 0~10 m / Step length [m]
    fChangeReserve_m : REAL := 5.0;     // 换膜余量 0~50 m / Change reserve [m]
    fFedLen_m        : REAL := 0.0;     // 累计送料反馈注入 0~2000 m / Fed length feedback injected [m]
    bMaintWin        : BOOL := FALSE;   // 保养窗激活注入 / Maintenance window injected
    tFeedTimeout     : TIME := T#10S;   // 送料超时窗（理论耗时×1.5 口径）T#100MS~T#120S / Feed timeout [s]
END_VAR
VAR_OUTPUT
    bFeedCmd    : BOOL := FALSE;        // 送料指令输出 / Feed command output
    bFeedDone   : BOOL := FALSE;        // 步完成脉冲（单拍自清）/ Step done pulse, one cycle
    fRemainLen_m: REAL := 0.0;          // 剩余膜长 / Remaining film length [m]
    bMaintHold  : BOOL := FALSE;        // 保养窗冻结标志（安全侧不启动）/ Maintenance hold flag
    eErr        : UDINT := 16#0004_0359;  // 错误码 / Error code
END_VAR
VAR
    rtrStart  : R_TRIG;                 // 启动沿检测, 每拍无条件刷新 / Start edge, refreshed every cycle
    rtrDone   : R_TRIG;                 // 完成沿检测, 每拍无条件刷新 / Done edge, refreshed every cycle
    tonFeed   : TON;                    // 送料超时定时器, 每拍无条件刷新 / Feed timeout timer, refreshed every cycle
    xFeedAct  : BOOL := FALSE;          // 送料步进行中标志 / Feed step active flag
    bTmoLatch : BOOL := FALSE;          // 超时堵转锁存 / Timeout stall latch
    bCfgErr   : BOOL := FALSE;          // 组态非法标记 / Configuration error flag
    bWarn     : BOOL := FALSE;          // 膜长耗尽预警标记 / Film-end warning flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0004_0359 信息 送料正常
//   16#0004_035A 故障 送料超时判堵转（指令后未在窗内完成, 指令立即收口）,
//                解除式 = 步进就绪恢复 且 送料步已收口
//   16#0004_035B 故障 步进驱动故障回读有效（指令立即收口）,
//                解除式 = 故障回读消失
//   16#0004_035C 信息 膜长耗尽预警（剩余膜长低于换膜余量, 送料继续）
//   16#0004_035D 故障 组态非法（膜长/步长/余量非有限或不大于 0）,
//                解除式 = 恢复合法组态
// ---------------------------------------------------------------------

// ---- 边沿与定时器实例无条件周期刷新 / Unconditional edge and timer refresh ----
rtrStart(CLK := bFeedStart);        // 启动沿 / Start edge
rtrDone(CLK := bStepperDone);       // 完成沿 / Done edge
tonFeed(IN := xFeedAct, PT := tFeedTimeout);    // 超时计时 / Timeout timing

// ---- 组态闸 / Configuration gate ----
bCfgErr := FALSE;
IF (fFilmLen_m <> fFilmLen_m) OR (fFilmLen_m <= 0.0) OR (fFilmLen_m > 2000.0) THEN
    bCfgErr := TRUE;                // 膜长非法 / Illegal film length
END_IF
IF (fStepLen_m <> fStepLen_m) OR (fStepLen_m <= 0.0) OR (fStepLen_m > 10.0) THEN
    bCfgErr := TRUE;                // 步长非法 / Illegal step length
END_IF
IF (fChangeReserve_m <> fChangeReserve_m) OR (fChangeReserve_m <= 0.0) OR (fChangeReserve_m > 50.0) THEN
    bCfgErr := TRUE;                // 余量非法 / Illegal reserve
END_IF
IF (fFedLen_m <> fFedLen_m) OR (fFedLen_m < 0.0) THEN
    bCfgErr := TRUE;                // 累计送料非法 / Illegal fed length
END_IF

// ---- 保养窗冻结（安全侧: 冻结期指令保持断开）/ Maintenance freeze, safe side ----
bMaintHold := bMaintWin;

// ---- 剩余膜长（负差钳零）/ Remaining film length, negative clamped ----
fRemainLen_m := fFilmLen_m - fFedLen_m;
IF fRemainLen_m < 0.0 THEN
    fRemainLen_m := 0.0;            // 负差钳零 / Clamp to zero
END_IF

// ---- 超时堵转锁存与解除 / Timeout stall latch and release ----
IF tonFeed.Q THEN
    bTmoLatch := TRUE;              // 窗内未完成判堵转锁存 / Stall latch
END_IF
IF bStepperReady AND (NOT xFeedAct) THEN
    bTmoLatch := FALSE;             // 就绪恢复且步已收口 → 解除 / Release on ready recovery
END_IF

// ---- 输出缺省（完成脉冲单拍自清）/ Output defaults, done pulse self-clearing ----
bFeedCmd  := FALSE;
bFeedDone := FALSE;

// ---- 启动沿派步（保养冻结/组态错/堵转/驱动故障/膜尽均不派）/ Start dispatch ----
IF rtrStart.Q AND (NOT bMaintHold) AND (NOT bCfgErr) AND (NOT bTmoLatch)
   AND (NOT bStepperFault) AND bStepperReady AND (fRemainLen_m > 0.0) AND (NOT xFeedAct) THEN
    xFeedAct := TRUE;               // 拍 N 进入送料步 / Enter feed step
END_IF

// ---- 送料步执行与收口 / Feed step execution and closing ----
IF xFeedAct THEN
    IF bMaintHold OR bCfgErr OR bStepperFault THEN
        xFeedAct := FALSE;          // 冻结或故障立即收口（安全侧指令断）/ Close on freeze or fault
    ELSE
        bFeedCmd := TRUE;           // 指令输出 / Command on
        IF rtrDone.Q THEN
            bFeedDone := TRUE;      // 单拍完成脉冲 / One-cycle done pulse
            xFeedAct := FALSE;      // 拍 N+1 步收口 / Close step
        ELSIF tonFeed.Q THEN
            xFeedAct := FALSE;      // 超时收口, 锁存已置 / Close on timeout
        END_IF
    END_IF
END_IF

// ---- 膜长耗尽预警（低于换膜余量, 送料继续）/ Film-end warning, feeding continues ----
bWarn := fRemainLen_m < fChangeReserve_m;

// ---- 错误码仲裁 / Error arbitration ----
IF bCfgErr THEN
    eErr := 16#0004_035D;           // 组态非法 / Config fault
ELSIF bTmoLatch THEN
    eErr := 16#0004_035A;           // 堵转锁存回放 / Stall latch replay
ELSIF bStepperFault THEN
    eErr := 16#0004_035B;           // 驱动故障 / Drive fault
ELSIF bWarn THEN
    eErr := 16#0004_035C;           // 耗尽预警 / Film-end warning
ELSE
    eErr := 16#0004_0359;           // 送料正常 / Feeding normal
END_IF

END_FUNCTION_BLOCK
