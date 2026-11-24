(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BlindPositionCtrl
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 暖通遮阳 · 电动帘位置控制
 *                         industry-pool / hvac / shading / interlock
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 【R33 已返修】安全相方向 / 位置记账 / 到位判据三者同向：eSafeRetract 改驱动
 *                         上行（oMotorUp），与位置递减记账、bUpLimitSw 到位判据一致。
 * 功能一句话 (Summary)  : 电动遮阳帘位置控制：位置指令按行程时间标定估计，
 *                         风雨联锁强制收回到底，结冰联锁冻结驱动，限位开关校准。
 *
 * 功能描述 (Function)   : 五态状态机：空闲/上行/下行/保持/安全收回。位置估计
 *                         用 100ms 节拍累计行程时间比例（每拍加 100ms/全程
 *                         时间 × 100），限位开关到位即校准端点；风雨联锁任一
 *                         为真立即转安全收回（驱动上行至下限位全收）；结冰联锁
 *                         冻结驱动输出并报故障；行程时间域外标定无效报故障。
 * 与既有件边界 (Boundary): 借 OSCAT BLIND 的行为定义（光照目标 + 风雨联锁 +
 *                         行程时间标定），clean-room 实现；光照闭环采样归
 *                         上层调度，本件只接位置指令。
 * 码位说明 (Codes)      : 信息 16#0006_300F 安全收回激活（风雨联锁）
 *                         故障 16#0006_3010 行程时间域外，标定无效
 *                         故障 16#0006_3011 输出互锁校验失败（上下同出）
 *                         故障 16#0006_3012 结冰联锁，驱动已冻结
 *                         段 16#06_0_0F~13 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / ABS。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q（输出引脚）
 *                         浮点比较带 fEps 容差 ｜ ENUM 配 CASE 且 ELSE 兜底
 *                         定时器每周期无条件刷新 ｜ 全变量双语同行注释
 *                         安全联锁（风雨冰）在 CASE 之前最高优先拦截
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 3）
 *                        2026-11-18  v1.0.1  R33 返修：安全相驱动方向与记账/到位判据同向、节拍计时自复位
 *============================================================================*)

FUNCTION_BLOCK FB_DL_BlindPositionCtrl
VAR_INPUT
    bRun         : BOOL;                    // 控制使能，假则停驱动回空闲 / Enable, FALSE stops and idles
    iCmdPosPct   : INT;                     // 位置指令 [％]，域 0 到 100，0 全收 100 全开 / Position command, 0 to 100
    bWindAlarm   : BOOL;                    // 风速联锁 [事件]，真则强制收回 / Wind interlock, TRUE forces retract
    bRainAlarm   : BOOL;                    // 雨水联锁 [事件]，真则强制收回 / Rain interlock, TRUE forces retract
    bIceAlarm    : BOOL;                    // 结冰联锁 [事件]，真则冻结驱动 / Ice interlock, TRUE freezes the drive
    bUpLimitSw   : BOOL;                    // 上限位开关 [开关]，真为全收到位 / Upper limit switch, fully retracted
    bDnLimitSw   : BOOL;                    // 下限位开关 [开关]，真为全开到位 / Lower limit switch, fully extended
    fTravelTimeS : LREAL := 60.0;           // 全程运行时间 [s]，标定参数 / Full travel time, calibration
    fEps         : LREAL := 1.0E-6;         // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    oMotorUp : BOOL;                    // 电机上行输出 [引脚]，经适配层映射 / Motor up output
    oMotorDn : BOOL;                    // 电机下行输出 [引脚]，经适配层映射 / Motor down output
    iEstPosPct: INT;                    // 估计位置 [％]，行程时间标定 / Estimated position
    eState   : (eIdle := 0, eMovingUp := 1, eMovingDown := 2, eHoldPos := 3, eSafeRetract := 4);  // 状态枚举输出 / State output
    bError   : BOOL;                    // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId : UDINT;                   // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    tonPace  : TON;     // 行程估计节拍定时器 [s]，每拍无条件刷新 / Travel pace timer
    fStepPct : LREAL;   // 单节拍位置步进 [％] / Position step per pace tick
    iPosF    : LREAL;   // 估计位置浮点内部值 [％] / Estimated position, internal float
    bCalOk   : BOOL;    // 行程标定有效标志 / Calibration validity flag
    uCodeLatch: UDINT;  // 故障锁存码 [码] / Latched fault code
    uInfoCode: UDINT;   // 信息级单拍码 [码] / One-shot info code
END_VAR
VAR CONSTANT
    DL_BPC_PACE_MS : TIME := T#100MS;   // 行程估计节拍 [ms] / Travel pace period
    DL_BPC_PACES   : LREAL := 0.1;      // 节拍秒值 [s]，与 PACE_MS 一致 / Pace in seconds
    DL_BPC_MAXTT   : LREAL := 3600.0;   // 行程时间上限 [s]，防标定离谱 / Travel time cap
END_VAR

(* 段 1｜定时器无条件刷新与标定域闸（红线 7）/ Timer refresh and calibration gate *)
tonPace(IN := NOT tonPace.Q, PT := DL_BPC_PACE_MS);     // 节拍自复位振荡（红线 7）/ Self-reset oscillating pace
IF (fTravelTimeS > fEps) AND (fTravelTimeS <= DL_BPC_MAXTT) THEN
    bCalOk := TRUE;                 // 标定有效 / Calibration valid
    fStepPct := DL_BPC_PACES / fTravelTimeS * 100.0;    // 单拍步进导出 / Step per tick
ELSE
    bCalOk := FALSE;                // 标定无效 / Calibration invalid
    fStepPct := 0.0;                // 步进置零禁走 / Zero step, no motion
    uCodeLatch := 16#0006_3010;     // 故障级：标定无效 / Fault: invalid calibration
END_IF

(* 段 2｜最高优先级安全联锁（先于 CASE）：风雨强收、结冰冻结 / Highest-priority safety before the CASE *)
IF bIceAlarm THEN
    oMotorUp := FALSE;              // 冻结上行 / Freeze up
    oMotorDn := FALSE;              // 冻结下行 / Freeze down
    IF bCalOk THEN
        uCodeLatch := 16#0006_3012; // 故障级：结冰冻结（标定有效才报）/ Fault: ice freeze
    END_IF
    eState := eHoldPos;             // 拍 N 保持位置，拍 N+1 由 CASE 复核 / Hold this scan
ELSIF bWindAlarm OR bRainAlarm THEN
    uInfoCode := 16#0006_300F;      // 信息级：安全收回激活 / Info: safe retract active
    eState := eSafeRetract;         // 拍 N 转安全收回，拍 N+1 执行 / To safe retract
END_IF

(* 段 3｜状态机主分派（ENUM 配 CASE，ELSE 兜底）/ State dispatch with ELSE interception *)
CASE eState OF

    eIdle:
        (* 本拍行为：停驱动；指令与使能俱备且不在联锁期拍 N+1 起步 / Stop; start when commanded *)
        oMotorUp := FALSE;              // 停上行 / Stop up
        oMotorDn := FALSE;              // 停下行 / Stop down
        IF bRun AND bCalOk AND (NOT bIceAlarm) AND (NOT bWindAlarm) AND (NOT bRainAlarm) THEN
            IF (iCmdPosPct > iEstPosPct) AND (iCmdPosPct <= 100) THEN
                eState := eMovingDown;  // 指令更大：向全开方向 / Bigger command: extend
            ELSIF (iCmdPosPct < iEstPosPct) AND (iCmdPosPct >= 0) THEN
                eState := eMovingUp;    // 指令更小：向全收方向 / Smaller command: retract
            ELSE
                eState := eHoldPos;     // 已在目标位保持 / Hold at target
            END_IF
        END_IF

    eMovingUp:
        (* 本拍行为：驱动上行并累计位置；到位或到目标转保持 / Drive up and accumulate; stop at target *)
        IF NOT (bRun AND bCalOk) THEN
            eState := eIdle;            // 撤使能或标定失效回空闲 / Disable or bad calibration to idle
        ELSE
            oMotorUp := TRUE;           // 驱动上行 / Drive up
            oMotorDn := FALSE;          // 下行必停 / Down must be off
            IF tonPace.Q THEN
                iPosF := iPosF - fStepPct;      // 位置递减（上行） / Position decreases
            END_IF
            IF bUpLimitSw OR (iPosF <= 0.0) THEN
                iPosF := 0.0;           // 全收校准端点 / Calibrate the endpoint
                oMotorUp := FALSE;      // 停驱动 / Stop the drive
                eState := eHoldPos;     // 拍 N+1 保持 / Hold next scan
            ELSIF iPosF <= DINT_TO_LREAL(iCmdPosPct) THEN
                oMotorUp := FALSE;      // 到目标停 / Stop at the target
                eState := eHoldPos;
            END_IF
        END_IF

    eMovingDown:
        (* 本拍行为：驱动下行并累计位置；到位或到目标转保持 / Drive down and accumulate *)
        IF NOT (bRun AND bCalOk) THEN
            eState := eIdle;            // 撤使能回空闲 / Disable to idle
        ELSE
            oMotorUp := FALSE;          // 上行必停 / Up must be off
            oMotorDn := TRUE;           // 驱动下行 / Drive down
            IF tonPace.Q THEN
                iPosF := iPosF + fStepPct;      // 位置递增（下行）/ Position increases
            END_IF
            IF bDnLimitSw OR (iPosF >= 100.0) THEN
                iPosF := 100.0;         // 全开校准端点 / Calibrate the endpoint
                oMotorDn := FALSE;      // 停驱动 / Stop the drive
                eState := eHoldPos;     // 拍 N+1 保持 / Hold next scan
            ELSIF iPosF >= DINT_TO_LREAL(iCmdPosPct) THEN
                oMotorDn := FALSE;      // 到目标停 / Stop at the target
                eState := eHoldPos;
            END_IF
        END_IF

    eHoldPos:
        (* 本拍行为：停驱动监视指令；新指令转移动相 / Hold and watch the command *)
        oMotorUp := FALSE;              // 停上行 / Stop up
        oMotorDn := FALSE;              // 停下行 / Stop down
        IF bRun AND bCalOk AND (NOT bIceAlarm) AND (NOT bWindAlarm) AND (NOT bRainAlarm) THEN
            IF (iCmdPosPct > iEstPosPct) AND (iCmdPosPct <= 100) THEN
                eState := eMovingDown;  // 起步向全开 / Start to extend
            ELSIF (iCmdPosPct < iEstPosPct) AND (iCmdPosPct >= 0) THEN
                eState := eMovingUp;    // 起步向全收 / Start to retract
            END_IF
        END_IF

    eSafeRetract:
        (* 本拍行为：驱动上行收回到底（与位置递减记账、bUpLimitSw 到位判据同向）；联锁撤清且到位转保持
         * Drive up to fully retracted, same direction as the decreasing position bookkeeping and bUpLimitSw *)
        oMotorDn := FALSE;              // 下行必停 / Down must be off
        oMotorUp := TRUE;               // 强制上行收回（与记账递减同向）/ Forced up retract, same direction
        IF tonPace.Q THEN
            iPosF := iPosF - fStepPct;  // 收回位置递减 / Retract position decreases
        END_IF
        IF bUpLimitSw OR (iPosF <= 0.0) THEN
            iPosF := 0.0;               // 全收校准 / Calibrate fully retracted
            oMotorUp := FALSE;          // 停驱动 / Stop the drive
            eState := eHoldPos;         // 拍 N+1 保持 / Hold next scan
        END_IF

ELSE
    oMotorUp := FALSE;                  // 非法状态双输出必停 / Illegal state, both off
    oMotorDn := FALSE;
    eState := eIdle;                    // 拦截回空闲 / Intercept to idle
    uCodeLatch := 16#0006_3010;         // 故障：状态越界 / Fault: state out of range
END_CASE

(* 段 4｜输出互锁校验（防御闸）与出口装配 / Interlock check and exit assembly *)
IF oMotorUp AND oMotorDn THEN
    oMotorUp := FALSE;                  // 互锁失败双断 / Interlock failure, both off
    oMotorDn := FALSE;
    uCodeLatch := 16#0006_3011;         // 故障级：互锁校验失败 / Fault: interlock broken
END_IF
iEstPosPct := LREAL_TO_DINT(iPosF);     // 估计位置整数输出 / Integer position output
IF iEstPosPct < 0 THEN
    iEstPosPct := 0;                    // 钳下界 / Clamp low
ELSIF iEstPosPct > 100 THEN
    iEstPosPct := 100;                  // 钳上界 / Clamp high
END_IF
IF NOT bRun THEN
    uCodeLatch := 16#0000_0000;         // 撤使能清标定故障（可达解除）/ Run drop clears faults
END_IF
bError := (uCodeLatch <> 16#0000_0000); // 故障锁存回放 / Latched fault replay
IF uCodeLatch <> 16#0000_0000 THEN
    uErrorId := uCodeLatch;             // 故障码优先 / Fault first
    uInfoCode := 16#0000_0000;
ELSE
    uErrorId := uInfoCode;              // 信息码单拍 / Info one shot
    uInfoCode := 16#0000_0000;
END_IF
END_FUNCTION_BLOCK
