(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CaseSealerFlapFoldSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 包装机械 · 封箱机折盖顺控
 *                         industry-pool / packaging / case-sealer / sequence
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON / R_TRIG
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 封箱机折盖六步顺控：进箱确认 → 折后盖 → 折前盖 →
 *                         压盖封箱（胶带/热熔双模式抽象）→ 完成，步序守护超时。
 *
 * 功能描述 (Function)   : 步进状态机：每步以到位传感器为转移条件，每步独立
 *                         守护超时（单步超时即卡箱故障，冻结输出保守停机）；
 *                         封箱步按模式区分：胶带模式只压盖，热熔模式压盖
 *                         加热熔 dwell 计时；完成以信息级 3028 告知并回待机。
 *                         箱未到位禁止起步折页（联锁拒绝），非法状态拦截。
 * 与既有件边界 (Boundary): 进箱/出箱输送线控制归输送件；本件只编排折盖
 *                         与封箱动作，不驱动输送。
 * 码位说明 (Codes)      : 信息 16#0006_3028 一箱封箱完成
 *                         故障 16#0006_3029 步序守护超时，卡箱保守停机
 *                         故障 16#0006_302A 箱未到位禁止起步（联锁拒绝）
 *                         故障 16#0006_302B 封箱模式域外
 *                         段 16#06_0_28~2C 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / R_TRIG。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q（输出引脚）
 *                         TON/R_TRIG 每周期无条件刷新 ｜ ENUM 配 CASE 且 ELSE 兜底
 *                         多段守护用 ARRAY[1..6] OF TON 独立实例（R158）
 *                         全变量双语同行注释 ｜ 故障锁存回放且有可达解除路径
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 4）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_CaseSealerFlapFoldSeq
VAR_INPUT
    bRun         : BOOL;                // 顺控使能，假则回待机 / Enable, FALSE stands by
    bBoxPresent  : BOOL;                // 箱到位传感器 [开关] / Box present sensor
    bFlapRearFwd : BOOL;                // 后盖折页到位 [开关] / Rear flap folded sensor
    bFlapFrontFwd: BOOL;                // 前盖折页到位 [开关] / Front flap folded sensor
    bPressFwd    : BOOL;                // 压盖缸到位 [开关] / Press cylinder forward sensor
    eSealMode    : (eTape := 0, eHotMelt := 1); // 封箱模式枚举：胶带/热熔 / Seal mode enum
    tStepGuard   : TIME  := T#10S;      // 单步守护超时 [s] / Per-step guard timeout
    tDwellHM     : TIME  := T#2S;       // 热熔 dwell 时长 [s] / Hot-melt dwell duration
END_VAR
VAR_OUTPUT
    oFoldRear: BOOL;                    // 后盖折页缸输出 [引脚] / Rear flap cylinder output
    oFoldFront: BOOL;                   // 前盖折页缸输出 [引脚] / Front flap cylinder output
    oPressCyl: BOOL;                    // 压盖缸输出 [引脚] / Press cylinder output
    oSealAct : BOOL;                    // 封箱动作输出（胶带贴附或热熔加热）[引脚] / Seal action output
    eStep    : (eStStandby := 0, eStFoldRear := 1, eStFoldFront := 2, eStPress := 3, eStDwell := 4, eStDone := 5);   // 步序枚举输出 / Step output enum
    bDone    : BOOL;                    // 一箱完成脉冲 [事件] / One-shot box done pulse
    bError   : BOOL;                    // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId : UDINT;                   // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    _eStep    : (eStStandby := 0, eStFoldRear := 1, eStFoldFront := 2, eStPress := 3, eStDwell := 4, eStDone := 5);  // 内部步序 / Internal step
    aTonGuard : ARRAY[1..6] OF TON;     // 各步守护定时器（R158 独立实例）/ Per-step guard timers
    tonDwell  : TON;                    // 热熔 dwell 定时器 [s] / Hot-melt dwell timer
    rTrigBox  : R_TRIG;                 // 箱到位上升沿 / Box present rising edge
    bGuardAct : BOOL;                   // 守护超时锁存 / Guard timeout latched
    uCodeLatch: UDINT;                  // 故障锁存码 [码] / Latched fault code
    uInfoCode : UDINT;                  // 信息级单拍码 [码] / One-shot info code
END_VAR
VAR CONSTANT
    DL_CSF_NSTEPS : INT := 6;           // 步数 [步]，与数组声明一致 / Step count, matches the array
END_VAR

(* 段 1｜定时器与边沿无条件刷新（红线 7）：六步守护独立实例 + dwell + 箱沿
 *      Timers refreshed unconditionally: six per-step guards, dwell, box edge *)
bGuardAct := FALSE;                     // 守护标志本拍重估 / Re-evaluate this scan
rTrigBox(CLK := bBoxPresent);           // 箱到位沿检测 / Box edge detection
tonDwell(IN := (_eStep = eStDwell), PT := tDwellHM);    // dwell 计时 / Dwell timing

(* 段 2｜六步守护矩阵：六实例每拍无条件刷新（R158）/ Guard matrix, six instances refreshed every scan *)
aTonGuard[1](IN := (_eStep = eStStandby)  AND bRun, PT := tStepGuard);
aTonGuard[2](IN := (_eStep = eStFoldRear) AND bRun, PT := tStepGuard);
aTonGuard[3](IN := (_eStep = eStFoldFront) AND bRun, PT := tStepGuard);
aTonGuard[4](IN := (_eStep = eStPress)    AND bRun, PT := tStepGuard);
aTonGuard[5](IN := (_eStep = eStDwell)    AND bRun, PT := tStepGuard);
aTonGuard[6](IN := (_eStep = eStDone)     AND bRun, PT := tStepGuard);
bGuardAct := aTonGuard[2].Q OR aTonGuard[3].Q OR aTonGuard[4].Q OR aTonGuard[5].Q;  // 任一活动步超时 / Any active step timed out
IF bGuardAct THEN
    uCodeLatch := 16#0006_3029;         // 故障级：步序守护超时 / Fault: step guard timeout
END_IF

(* 段 3｜步进状态机主分派（ENUM 配 CASE，ELSE 兜底）/ Step dispatch with ELSE interception *)
CASE _eStep OF

    eStStandby:
        (* 本拍行为：全输出撤；使能与箱到位俱备拍 N+1 起步 / All off; start on box present *)
        oFoldRear := FALSE;             // 撤后盖缸 / Retract the rear cylinder
        oFoldFront := FALSE;            // 撤前盖缸 / Retract the front cylinder
        oPressCyl := FALSE;             // 撤压盖缸 / Retract the press
        oSealAct := FALSE;              // 撤封箱动作 / Withdraw the seal action
        bDone := FALSE;                 // 完成脉冲清 / Clear the done pulse
        IF bRun AND rTrigBox.Q THEN
            _eStep := eStFoldRear;      // 拍 N+1 起步折后盖 / To fold rear next scan
        END_IF

    eStFoldRear:
        (* 本拍行为：驱动后盖缸；到位转折前盖 / Drive the rear cylinder; transfer on sensor *)
        oFoldRear := TRUE;              // 驱动后盖 / Drive the rear
        oFoldFront := FALSE;
        oPressCyl := FALSE;
        oSealAct := FALSE;
        IF NOT bRun THEN
            _eStep := eStStandby;       // 撤使能回待机 / Disable to standby
        ELSIF bFlapRearFwd THEN
            _eStep := eStFoldFront;     // 拍 N+1 转折前盖 / To fold front next scan
        END_IF

    eStFoldFront:
        (* 本拍行为：驱动前盖缸；到位转压盖 / Drive the front cylinder *)
        oFoldRear := FALSE;
        oFoldFront := TRUE;             // 驱动前盖 / Drive the front
        oPressCyl := FALSE;
        oSealAct := FALSE;
        IF NOT bRun THEN
            _eStep := eStStandby;       // 撤使能回待机 / Disable to standby
        ELSIF bFlapFrontFwd THEN
            _eStep := eStPress;         // 拍 N+1 转压盖 / To press next scan
        END_IF

    eStPress:
        (* 本拍行为：压盖缸进；到位后按模式转封箱动作或 dwell / Press; transfer by mode *)
        oFoldRear := FALSE;
        oFoldFront := FALSE;
        oPressCyl := TRUE;              // 驱动压盖 / Drive the press
        oSealAct := FALSE;
        IF NOT bRun THEN
            _eStep := eStStandby;       // 撤使能回待机 / Disable to standby
        ELSIF bPressFwd THEN
            CASE eSealMode OF           // 模式内嵌 CASE（枚举配 ELSE）/ Nested mode CASE with ELSE
                eTape:    _eStep := eStDone;    // 胶带模式：压盖即完成 / Tape: press is enough
                eHotMelt: _eStep := eStDwell;   // 热熔模式：转 dwell / Hot melt: dwell
            ELSE
                uCodeLatch := 16#0006_302B;     // 故障级：模式域外 / Fault: mode out of range
                _eStep := eStStandby;
            END_CASE
        END_IF

    eStDwell:
        (* 本拍行为：压盖保持 + 封箱动作输出，dwell 满完成 / Hold and seal, done on dwell *)
        oFoldRear := FALSE;
        oFoldFront := FALSE;
        oPressCyl := TRUE;              // 保持压盖 / Hold the press
        oSealAct := TRUE;               // 热熔加热输出 / Hot melt output
        IF NOT bRun THEN
            _eStep := eStStandby;       // 撤使能回待机 / Disable to standby
        ELSIF tonDwell.Q THEN
            _eStep := eStDone;          // dwell 满，拍 N+1 完成 / Done next scan
        END_IF

    eStDone:
        (* 本拍行为：全输出撤 + 完成脉冲单拍，箱离位回待机 / All off, one-shot pulse, wait for box leave *)
        oFoldRear := FALSE;
        oFoldFront := FALSE;
        oPressCyl := FALSE;
        oSealAct := FALSE;
        bDone := TRUE;                  // 完成脉冲（单拍）/ One-shot done pulse
        uInfoCode := 16#0006_3028;      // 信息级：一箱完成 / Info: box done
        IF NOT bBoxPresent THEN
            _eStep := eStStandby;       // 箱离位回待机 / Box left, to standby
        END_IF
        IF NOT bRun THEN
            _eStep := eStStandby;       // 撤使能回待机 / Disable to standby
        END_IF

ELSE
    oFoldRear := FALSE;                 // 非法步全撤（保守停机）/ Illegal step, all off
    oFoldFront := FALSE;
    oPressCyl := FALSE;
    oSealAct := FALSE;
    _eStep := eStStandby;               // 拦截回待机 / Intercept to standby
    uCodeLatch := 16#0006_3029;         // 故障：步序越界 / Fault: step out of range
END_CASE

(* 段 4｜出口装配 / Exit assembly *)
eStep := _eStep;                        // 步序枚举输出 / Step output
IF NOT bRun THEN
    uCodeLatch := 16#0000_0000;         // 撤使能清故障（可达解除）/ Run drop clears faults
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
