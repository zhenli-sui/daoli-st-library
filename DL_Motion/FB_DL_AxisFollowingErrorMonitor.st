(*
    FB_DL_AxisFollowingErrorMonitor —— 跟随误差监视
    ------------------------------------------------------------------
    分类      : DL_Motion / Monitor
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T1-6 PLCopen（只借「跟随误差监视属运动控制监视功能」的公开语义，
                不自造轴状态机）；T2-4 监视参数域为次源；
                确认窗、静止带、阈值交换逻辑与码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 消费「指令位置 + 实际位置」两个快照，算跟随误差并做三级判定
                （正常 / 预警 / 故障），带确认时间与静止带豁免；
                本件不自造轴状态、不发运动指令——轴状态唯一属主在 FB_DL_SingleAxis，
                本件只是被动消费者（同 PassiveHomingMonitor 纪律）；
                阈值倒置自动交换而不是报故障：现场参数填反极常见，直接锁死会停线；
                静止带内误差视为正常并清计时，防静止噪声误跳；
                eErr（参数 / 信号类）与 bFault（工艺跟随超差）分开出口，便于 HMI 分组。
    错误码    : 16#0004_01C7 阈值倒置已自动交换 / 阈值超域已钳位——信息级，不置故障
                16#0004_01C8 预留禁用（信息级，不得挪用）
                16#0004_02D5 位置快照非有限（NaN / 正负 INF）——故障级，判定冻结
                16#0004_02D6 越限持续超确认窗（与 bFault 同拍置位，可追溯标识）——故障级
                16#0004_02D7 预留禁用（故障级，不得挪用）
    码位总账  : 16#0004_01C7 用 / 16#0004_01C8 预留 ｜ 16#0004_02D5 用 / 16#0004_02D6 用 / 16#0004_02D7 预留
    状态机    : 无 CASE，判定由两个 TON 与一个故障锁存位承载，非法状态不可能出现
    采样约定  : fbTrigReset 与两个 TON 在本体首部无条件调用；静止时只把定时器 IN 引脚
                置 FALSE，绝不把 TON 调用放进 IF（否则 ET 冻结产生幽灵确认）。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_AxisFollowingErrorMonitor
VAR_INPUT
    bEnable         : BOOL;                    // 使能，FALSE 清判定并按正常输出 / enable, FALSE clears the verdict and reports normal
    bReset          : BOOL;                    // 复位，上升沿清故障与计时 / reset, rising edge clears the fault and the timers
    fSetPosition    : REAL := 0.0;             // 指令位置，由运动层注入 [mm] / commanded position injected by the motion layer [mm]
    fActPosition    : REAL := 0.0;             // 实际位置反馈 [mm] / actual position feedback [mm]
    fWarnLimit      : REAL := 0.5;             // 预警阈值，必须大于 0 [mm] / warning threshold, must exceed zero [mm]
    fFaultLimit     : REAL := 2.0;             // 故障阈值，必须大于 0 且大于预警阈值 [mm] / fault threshold, must exceed zero and the warning threshold [mm]
    tConfirmTime    : TIME := T#200MS;         // 越限持续确认时间，0 = 立即判定 [ms] / over-limit confirmation time, 0 = immediate [ms]
    fStandstillBand : REAL := 0.05;            // 静止带，误差在此内视为正常（噪声容忍）[mm] / standstill band, the error inside it counts as normal [mm]
    bInMotion       : BOOL := FALSE;           // 运动中标志，FALSE 时确认时间不累加 / in-motion flag, the timers do not accumulate when FALSE
END_VAR
VAR_OUTPUT
    fError    : REAL;                          // 跟随误差（指令减实际）[mm] / following error, command minus actual [mm]
    fErrorAbs : REAL;                          // 误差绝对值 [mm] / absolute following error [mm]
    bWarn     : BOOL;                          // 预警（越预警阈值超确认时间）/ warning, over the warning threshold beyond the confirmation time
    bFault    : BOOL;                          // 故障（越故障阈值超确认时间，已锁存）/ fault, over the fault threshold beyond the confirmation time, latched
    tOverTime : TIME;                          // 当前越预警阈值已持续时间 [ms] / time spent above the warning threshold [ms]
    eErr      : UDINT;                         // 错误码（参数 / 信号类），0=正常 / error id of the parameter or signal class, 0=ok
    bError    : BOOL;                          // 故障标志（参数类），与 bFault 区分 / error flag of the parameter class, distinct from bFault
END_VAR
VAR
    fbTrigReset   : R_TRIG;                    // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbConfirmWarn : TON;                       // 预警确认定时器，本体首部无条件刷新 / warning confirmation timer, refreshed unconditionally
    fbConfirmFault: TON;                       // 故障确认定时器，本体首部无条件刷新 / fault confirmation timer, refreshed unconditionally
    fWarnEff      : REAL;                      // 生效预警阈值，交换与钳位后 [mm] / effective warning threshold after swap and clamp [mm]
    fFaultEff     : REAL;                      // 生效故障阈值，交换与钳位后 [mm] / effective fault threshold after swap and clamp [mm]
    fTmpSwap      : REAL;                      // 阈值交换中间量 [mm] / threshold swap intermediate [mm]
    fErrorLast    : REAL;                      // 末次有效误差，非有限时保持 [mm] / last valid error held through non-finite cycles [mm]
    bFaultLatch   : BOOL;                      // 故障锁存位，仅复位清除 / fault latch, cleared by reset only
    bFrozen       : BOOL;                      // 判定冻结标志，快照非有限时为 TRUE / verdict freeze flag, TRUE on a non-finite snapshot
    bNonFin       : BOOL;                      // 快照非有限判定标志 / snapshot non-finite flag
END_VAR
VAR CONSTANT
    DL_FE_MIN_LIMIT  : REAL := 0.001;          // 阈值下限 [mm] / threshold lower bound [mm]
    DL_FE_MAX_LIMIT  : REAL := 1.0E4;          // 阈值上限 [mm] / threshold upper bound [mm]
    DL_FE_INF_GUARD  : REAL := 4.0E38;         // 非有限幅值判定阈值 [mm] / non-finite magnitude guard [mm]
    DL_FLOAT_EPS     : REAL := 1.0E-6;         // 浮点判等容差 [mm] / float equality tolerance [mm]
    DL_FE_ZERO       : REAL := 0.0;            // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_FE_ONE        : REAL := 1.0;            // 一值常量，用于交换判据 [无量纲] / one constant used by the swap criterion [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障标志 / preset no error flag
bWarn := FALSE;                                // 预置无预警 / preset no warning
bFrozen := FALSE;                              // 预置不冻结 / preset not frozen

// 段 3｜失能期的记忆与锁存清理：本件无首扫专用初值，状态由 bFaultLatch 与 fErrorLast 承载 / segment 3, memory and latch clearing while disabled, no dedicated first-scan init needed
IF NOT bEnable THEN
    fErrorLast := DL_FE_ZERO;                  // 失能清误差记忆 / clear the error memory while disabled
    bFaultLatch := FALSE;                      // 失能清故障锁存 / clear the fault latch while disabled
END_IF

// 段 4｜阈值域校正：先钳位再判倒置，倒置自动交换（信息级，绝不锁死生产）/ segment 4, threshold correction
fWarnEff := MIN(MAX(fWarnLimit, DL_FE_MIN_LIMIT), DL_FE_MAX_LIMIT);   // 预警阈值双侧钳位 / clamp the warning threshold both sides
fFaultEff := MIN(MAX(fFaultLimit, DL_FE_MIN_LIMIT), DL_FE_MAX_LIMIT); // 故障阈值双侧钳位 / clamp the fault threshold both sides
IF ABS(fWarnEff - fWarnLimit) > DL_FLOAT_EPS THEN
    eErr := 16#0004_01C7;                      // 钳位提示（信息级不置故障）/ clamp hint, info level never raises a fault
END_IF
IF ABS(fFaultEff - fFaultLimit) > DL_FLOAT_EPS THEN
    eErr := 16#0004_01C7;                      // 钳位提示（信息级不置故障）/ clamp hint, info level never raises a fault
END_IF
IF fWarnEff >= fFaultEff THEN
    fTmpSwap := fWarnEff;                      // 暂存预警阈值 / hold the warning threshold
    fWarnEff := fFaultEff;                     // 交换下限 / swap the lower bound
    fFaultEff := fTmpSwap;                     // 交换上限 / swap the upper bound
    eErr := 16#0004_01C7;                      // 交换提示（信息级不置故障）/ swap hint, info level never raises a fault
END_IF

// 段 5｜误差计算与非有限闸：非有限时保持末次有效误差并冻结判定 / segment 5, error computation and non-finite gate
bNonFin := (fSetPosition <> fSetPosition)
        OR (fSetPosition > DL_FE_INF_GUARD) OR (fSetPosition < -DL_FE_INF_GUARD)
        OR (fActPosition <> fActPosition)
        OR (fActPosition > DL_FE_INF_GUARD) OR (fActPosition < -DL_FE_INF_GUARD); // 双快照同口径检查 / both snapshots checked the same way
IF bNonFin THEN
    eErr := 16#0004_02D5;                      // 快照非有限故障码 / non-finite snapshot fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fError := fErrorLast;                      // 保持末次有效误差 / hold the last valid error
    bFrozen := TRUE;                           // 冻结判定与计时 / freeze the verdict and the timers
ELSE
    fError := fSetPosition - fActPosition;     // 指令减实际 / command minus actual
    fErrorLast := fError;                      // 刷新误差记忆 / refresh the error memory
END_IF
fErrorAbs := ABS(fError);                      // 绝对值出口 / absolute value output

// 段 6｜静止带豁免：带内视为正常且清计时（不改定时器调用位置，只改 IN 引脚）/ segment 6, standstill band exemption
IF fErrorAbs <= fStandstillBand THEN
    bFrozen := TRUE;                           // 静止带内冻结计时，防噪声误跳 / freeze the timers inside the band, prevents noise trips
END_IF

// 段 7｜定时器每拍调用一次且位于条件分支之外，IN 引脚承载全部条件 / segment 7, one call per cycle outside any branch, the IN pin carries every condition
fbConfirmWarn(IN := bEnable AND (NOT bFrozen) AND bInMotion AND (fErrorAbs > fWarnEff), PT := tConfirmTime);
fbConfirmFault(IN := bEnable AND (NOT bFrozen) AND bInMotion AND (fErrorAbs > fFaultEff), PT := tConfirmTime);

// 段 8｜复位沿清故障与计时（优先于判定）/ segment 8, reset clears the fault and the timers
IF fbTrigReset.Q THEN
    bFaultLatch := FALSE;                      // 清故障锁存 / clear the fault latch
    bWarn := FALSE;                            // 清预警 / clear the warning
END_IF

// 段 9｜判定：故障优先于预警，故障锁存后只能复位清除 / segment 9, verdict with the fault taking priority
IF fbConfirmFault.Q THEN
    bFaultLatch := TRUE;                       // 越故障阈值超确认窗，锁存 / above the fault threshold beyond the confirmation time, latch it
    eErr := 16#0004_02D6;                      // 越限持续故障码，与 bFault 同拍置位 / over-limit sustained fault id, set on the same cycle as bFault
    bError := TRUE;                            // 置故障标志，便于 HMI 与 bFault 同屏追溯 / raise the error flag so the HMI can trail both flags together
END_IF
IF (NOT bFaultLatch) AND fbConfirmWarn.Q THEN
    bWarn := TRUE;                             // 越预警阈值超确认窗 / above the warning threshold beyond the confirmation time
END_IF

// 段 10｜输出 / segment 10, publish the outputs
bFault := bFaultLatch;                         // 工艺故障出口 / process fault output
tOverTime := fbConfirmWarn.ET;                 // 越限已持续时间取预警定时器 ET / the elapsed time comes from the warning timer
IF bFaultLatch THEN
    bWarn := FALSE;                            // 故障优先，预警让位 / the fault takes priority, the warning steps aside
END_IF
IF NOT bEnable THEN
    bFault := FALSE;                           // 失能即按正常输出 / disabled reports normal
    bWarn := FALSE;                            // 失能即无预警 / no warning while disabled
    tOverTime := T#0MS;                        // 计时清零 / clear the elapsed time
END_IF
END_FUNCTION_BLOCK
