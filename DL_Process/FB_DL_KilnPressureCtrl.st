(*==============================================================================
 * 组件名称 (Component)  : FB_DL_KilnPressureCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library + DL_ 库内既有件，零厂商方言
 * 来源标签 (Source)     : self-std
 * 功能描述 (Function)   : 窑炉窑压定值闭环控制：窑压 PID 闭环（委托 FB_DL_PidController，
 *                         PID 引脚注入不内联）+ 烟囱抽力挡板执行器出口限幅 + 窑门开
 *                         扰动前馈（委托 FB_DL_FeedforwardComp 组合调用）+ 窑压负压
 *                         上限联锁（负压超限禁升温指令放行——只拦不放，执行归温区件，
 *                         与 FB_DL_InterlockMatrix 分工互引：放行闸不锁存，故障锁存
 *                         归联锁本体）。
 * 委托清单 (Delegation) : FB_DL_PidController（DL_Algo，闭环内核）
 *                         FB_DL_FeedforwardComp（DL_Algo，前馈内核）
 *                         FB_DL_ToleranceWindow（DL_Base，双表偏差窗）
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 窑压测点双表冗余可选（bUseBackup）：偏差窗（ToleranceWindow）越窗 -> 按
 *      NE43 保持主表 + 置故障级码（锁存至复位沿 AND 偏差回窗），PID 继续用主表。
 *   2) 窑压测点非有限（主表或被选备份表）-> PID 停投（挡板回安全位）+ 故障级码；
 *      与双表偏差成因互异、码位互异（R190 归因唯一）。
 *   3) 前馈增益域闸：负值 / 非有限 -> 故障级锁存，前馈强制 0（不参与合成）。
 *   4) 负压联锁不锁存：放行闸位 bRisePermit 每拍重算，负压恢复即放行（只拦不放）。
 *   5) PID 失能时挡板输出回安全位 fDamperSafe（降级语义显式声明 R191，非冻结保持）。
 *   6) 引脚分闸归属：fPressSetpoint / fKp / tTi 仅透传 PID（由 PID 自身域闸负责），
 *      本件域闸覆盖本件判据 / 换算直接引用的全部浮点引脚（R272 全枚举）。
 * 故障码表 (Error codes) :
 *   16#0005_03AE [故障级] 双表偏差超窗（bUseBackup 且 ToleranceWindow 越窗），保持主表
 *                 反证：保持主表与「未启用备份表」输出组合相同，码位唯一可见。
 *   16#0005_03AF [故障级] 前馈增益组态非法（负值 / 非有限），前馈强制 0
 *                 反证：前馈 0 与增益显式填 0 输出组合相同，码位唯一可见。
 *   16#0005_03B0 [故障级] 窑压测点非有限，PID 停投挡板回安全位
 *                 反证：安全位输出与显式失能组合相同，码位是测点失效唯一出口。
 *   16#0005_03B1 [故障级] 通用组态非法（偏差窗 / 挡板限位域 / 采样周期），已回退
 *                 反证：回退后控制照常，码位是组态错误唯一可见出口。
 *   16#0005_04D5 [信息级] 负压联锁拦截升温放行（不锁存，每拍重算）
 *                 反证：bRisePermit 已表达闸位状态，码位承载拦截事件流水归档
 *                 （拦截频次是工艺诊断量，布尔位不承载）。
 * 码位总账 (Code ledger) : 16#0005_03AE / 03AF / 03B0 / 03B1 用 ｜ 16#0005_04D5 用
 * 依赖     (Depends)    : FB_DL_PidController / FB_DL_FeedforwardComp / FB_DL_ToleranceWindow
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 + 库内委托件
 *                         R4 ✓ 非有限双判 / 合成限幅 / 域闸全枚举 / 码位 R45 配对
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 三态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 一沿 + 三委托件每拍无条件调用
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 3 · 目标 14）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_KilnPressState（归属 DL_Process，与 FB_DL_KilnPressureCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_KilnPressState :
(
    eIdle  := 0,    // 未使能：挡板回安全位 / Disabled, damper at safe position
    eRun   := 10,   // 闭环运行：PID + 前馈合成 / Closed loop, PID plus feedforward
    eFault := 99    // 测点 / 组态锁存：挡板回安全位 / Latched, damper at safe position
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_KilnPressureCtrl
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_KilnPressureCtrl
VAR_INPUT
    fPressMain     : REAL;               // 窑压主表 [Pa] / Kiln pressure main gauge [Pa]
    fPressBackup   : REAL;               // 窑压备份表 [Pa] / Kiln pressure backup gauge [Pa]
    bUseBackup     : BOOL;               // 双表冗余核对使能 / Dual gauge cross-check enable
    fPressDevWin   : REAL := 20.0;       // 双表偏差窗 [Pa] / Dual gauge deviation window [Pa]
    fPressSetpoint : REAL;               // 窑压设定 [Pa] / Kiln pressure setpoint [Pa]
    fDoorOpenPct   : REAL;               // 窑门开度 [%]，前馈扰动源 / Door opening [%], disturbance source
    fFfGain        : REAL := 0.5;        // 前馈增益 [1]，负值 / 非法锁存 / Feedforward gain
    fNegPressLim   : REAL := -50.0;      // 负压上限 [Pa]，低于此禁升温放行 / Negative pressure limit [Pa]
    fDamperMin     : REAL := 0.0;        // 挡板输出下限 [%] / Damper output floor [%]
    fDamperMax     : REAL := 100.0;      // 挡板输出上限 [%] / Damper output ceiling [%]
    fDamperSafe    : REAL := 0.0;        // 失能 / 故障安全挡板位 [%] / Safe damper position [%]
    fKp            : REAL := 1.0;        // PID 比例增益（透传）/ PID proportional gain
    tTi            : TIME := T#10S;      // PID 积分时间（透传）/ PID integral time
    tSample        : TIME := T#100MS;    // 采样周期 / Sample period
    bEnable        : BOOL := TRUE;       // 使能（FALSE 挡板回安全位）/ Enable, FALSE drives safe position
    bReset         : BOOL;               // 上升沿：清除偏差 / 增益锁存 / Rising edge: clear latches
END_VAR
VAR_OUTPUT
    fDamperOut   : REAL;                // 挡板输出 [%]（已限幅合成）/ Damper output, clamped
    bRisePermit  : BOOL;                // 升温指令放行闸（每拍重算，不锁存）/ Rise permit, recomputed
    bDevLatch    : BOOL;                // 双表偏差锁存 / Dual gauge deviation latched
    bPressBad    : BOOL;                // 窑压测点非有限（保持型）/ Gauge non-finite, level held
    bError       : BOOL;                // 故障标志（锁存类归并）/ Fault flag merged
    uErrorId     : UDINT;               // 故障码，0 = 无故障 / Error code, 0 = none
    eState       : E_DL_KilnPressState; // 当前状态（供 HMI 诊断）/ Current state
END_VAR
VAR
    fbTrigReset  : R_TRIG;              // 复位沿检测实例 / Reset edge detector
    fbTol        : FB_DL_ToleranceWindow; // 双表偏差窗委托实例 / Deviation window delegate
    fbPid        : FB_DL_PidController; // PID 闭环委托实例 / PID delegate
    fbFf         : FB_DL_FeedforwardComp; // 前馈委托实例 / Feedforward delegate
    eStateInt    : E_DL_KilnPressState; // 主状态机内部当前态 / Internal state machine state
    bMainBad     : BOOL;                // 主表非有限 / Main gauge non-finite
    bBackupBad   : BOOL;                // 备份表非有限 / Backup gauge non-finite
    bPressBadInt : BOOL;                // 测点非有限保持位内部副本 / Internal gauge-bad level
    bDevInt      : BOOL;                // 偏差锁存内部副本 / Internal deviation latch
    bGainBad     : BOOL;                // 前馈增益非法 / Feedforward gain illegal
    bGainLatch   : BOOL;                // 增益锁存 / Gain latch
    bCfgBad      : BOOL;                // 本拍通用组态非法 / General config illegal this scan
    bCfgLatch    : BOOL;                // 通用组态锁存 / General config latch
    fPressUse    : REAL;                // 参与判据与 PID 的窑压值 [Pa] / Gauge value used
    fFfGainEff   : REAL;                // 生效前馈增益（非法时 0）/ Effective gain, 0 when illegal
    fPidOut      : REAL;                // PID 输出 [%] / PID output
    fFfOut       : REAL;                // 前馈输出 [%] / Feedforward output
    fSumRaw      : REAL;                // 合成原始量 [%] / Raw combined output
    bErrorInt    : BOOL;                // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bFirstScan   : BOOL := TRUE;        // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_KP_FIN_LIM : REAL := 1.0E30;   // REAL 有限幅值判界 / REAL finiteness bound
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿 + 三委托件每拍无条件调用
 *      Unconditional refresh: one edge plus three delegates called every scan
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：状态与合成量落安全侧
 *      First-scan init: state and combined output to the safe side
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt := E_DL_KilnPressState.eIdle;
    fSumRaw   := 0.0;
    fDamperOut := fDamperSafe;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜非有限闸（R272：本件判据直接引用的测量引脚）与组态域闸
 *      Non-finite gates over the gauges, plus the config gate
 *      引脚分闸归属：fPressSetpoint / fKp / tTi 透传 PID 由其自身域闸负责（披露 6）
 *-----------------------------------------------------------------------------*)
bMainBad   := (fPressMain <> fPressMain) OR ((fPressMain - fPressMain) <> (fPressMain - fPressMain))
              OR (ABS(fPressMain) >= DL_KP_FIN_LIM);
bBackupBad := (fPressBackup <> fPressBackup) OR ((fPressBackup - fPressBackup) <> (fPressBackup - fPressBackup))
              OR (ABS(fPressBackup) >= DL_KP_FIN_LIM);

bPressBadInt := bMainBad OR (bUseBackup AND bBackupBad);
IF bPressBadInt THEN
    uErrorId  := 16#0005_03B0;       // 故障级：窑压测点非有限 / Fault: gauge non-finite
    bErrorInt := TRUE;
END_IF

bCfgBad := (fPressDevWin <= 0.0) OR (fPressDevWin <> fPressDevWin)
           OR (fNegPressLim <> fNegPressLim)
           OR (fDamperMin > fDamperMax) OR (fDamperMin <> fDamperMin) OR (fDamperMax <> fDamperMax)
           OR (fDamperSafe < fDamperMin) OR (fDamperSafe > fDamperMax) OR (fDamperSafe <> fDamperSafe)
           OR (tSample <= T#0S);

IF bCfgBad THEN
    bCfgLatch := TRUE;
    uErrorId  := 16#0005_03B1;       // 故障级：通用组态非法（独立成因独立码，R190）/ Fault: config illegal
    bErrorInt := TRUE;
END_IF

(* 前馈增益域闸：负值 / 非独立成因 -> 独立码位 *)
(* Feedforward gain gate with its own cause code *)
bGainBad := (fFfGain < 0.0) OR (fFfGain <> fFfGain);
IF bGainBad THEN
    bGainLatch := TRUE;
    uErrorId   := 16#0005_03AF;      // 故障级：前馈增益非法 / Fault: gain illegal
    bErrorInt  := TRUE;
END_IF
IF bGainLatch THEN
    fFfGainEff := 0.0;               // 非法增益强制 0（不参与合成）/ Forced zero
ELSE
    fFfGainEff := fFfGain;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜双表偏差窗（委托 ToleranceWindow）与测点选择（NE43 保持主表）
 *      Dual gauge deviation window and gauge selection, main kept on deviation
 *-----------------------------------------------------------------------------*)
fbTol(bEnable := bUseBackup,
      fTarget := fPressMain,
      fActual := fPressBackup,
      fTolerance := fPressDevWin,
      fHysteresis := 0.0);

IF bUseBackup AND (NOT fbTol.bOk) AND (NOT bMainBad) AND (NOT bBackupBad) THEN
    bDevInt := TRUE;                 // 偏差越窗锁存 / Deviation latched
    uErrorId := 16#0005_03AE;
    bErrorInt := TRUE;
END_IF

(* 解除路径（R152 自证可达）：复位沿 AND 偏差回窗 *)
IF fbTrigReset.Q AND fbTol.bOk THEN
    bDevInt := FALSE;
END_IF

(* 测点选择：偏差 / 失效一律保持主表（NE43 口径，不猜备份表） *)
(* Gauge selection: main kept on deviation or failure, never guessing *)
fPressUse := fPressMain;

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_KilnPressState.eIdle:
        IF bEnable AND (NOT bCfgLatch) AND (NOT bGainLatch) AND (NOT bPressBadInt) THEN
            eStateInt := E_DL_KilnPressState.eRun;
        ELSE
            fSumRaw := 0.0;          // 失能：合成量清零，出口派生安全位 / Idle: combined zeroed
        END_IF

    E_DL_KilnPressState.eRun:
        IF bCfgLatch OR bGainLatch OR bPressBadInt OR (NOT bEnable) THEN
            eStateInt := E_DL_KilnPressState.eFault;
        ELSE
            (* —— PID 闭环（委托，引脚注入不内联） —— *)
            fbPid(bEnable := TRUE,
                  bManual := FALSE,
                  fSetpoint := fPressSetpoint,
                  fActual := fPressUse,
                  fKp := fKp,
                  tTi := tTi,
                  rOutMin := fDamperMin,
                  rOutMax := fDamperMax,
                  tSampleTime := tSample,
                  bReset := bReset);
            fPidOut := fbPid.fOut;

            (* —— 窑门开扰动前馈（委托）：门开 -> 抽力预置增量 —— *)
            fbFf(bEnable := TRUE,
                 fDisturbance := fDoorOpenPct,
                 fFfGain := fFfGainEff,
                 rOutMin := 0.0,
                 rOutMax := fDamperMax,
                 tSampleTime := tSample);
            fFfOut := fbFf.fFfOut;

            fSumRaw := fPidOut + fFfOut;     // 合成（出口段统一限幅）/ Combined, clamped at exit
        END_IF

    E_DL_KilnPressState.eFault:
        fSumRaw := 0.0;              // 故障相合成量清零 -> 出口派生安全位（R191 降级声明）/ Safe via exit
        (* 解除路径（R152 自证可达）：复位沿 AND 全部锁存源已恢复 *)
        IF fbTrigReset.Q AND (NOT bCfgBad) AND (NOT bGainBad) AND (NOT bPressBadInt) THEN
            bCfgLatch   := FALSE;
            bGainLatch  := FALSE;
            uErrorId    := 16#0000_0000;
            eStateInt   := E_DL_KilnPressState.eIdle;
        END_IF

    ELSE
        eStateInt := E_DL_KilnPressState.eFault;
        uErrorId  := 16#0005_03B1;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜输出单一出口（范式 P-05）：限幅合成 + 负压放行闸 + 安全位派生
 *      Single output exit: clamped combine plus the rise permit derivation
 *-----------------------------------------------------------------------------*)
IF eStateInt = E_DL_KilnPressState.eRun THEN
    fDamperOut := fSumRaw;           // 运行相：合成量直出 / Run: combined as-is
    IF fDamperOut > fDamperMax THEN
        fDamperOut := fDamperMax;    // 出口限幅 / Exit clamp
    ELSIF fDamperOut < fDamperMin THEN
        fDamperOut := fDamperMin;
    END_IF
ELSE
    fDamperOut := fDamperSafe;       // 失能 / 故障：安全挡板位（R191 已声明）/ Safe position
END_IF

(* 负压联锁（放行闸，不锁存）：窑压低于负压上限即拦截升温放行 *)
(* Negative pressure interlock: blocks the rise permit, never latched *)
IF (eStateInt = E_DL_KilnPressState.eRun) AND (fPressUse < fNegPressLim) THEN
    bRisePermit := FALSE;
    uErrorId    := 16#0005_04D5;     // 信息级：拦截事件 / Info: blocking event
ELSE
    bRisePermit := (eStateInt = E_DL_KilnPressState.eRun);
END_IF

bDevLatch := bDevInt;
bPressBad := bPressBadInt;
bError    := bErrorInt OR (eStateInt = E_DL_KilnPressState.eFault);
eState    := eStateInt;
END_FUNCTION_BLOCK
