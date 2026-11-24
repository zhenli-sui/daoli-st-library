(*
    FB_DL_RecipeStepExec —— 配方步序执行器（步推进 / 步超时 / 暂停恢复 / 禁跳步）
    ------------------------------------------------------------------
    组件名称  : FB_DL_RecipeStepExec
    分类      : DL_Base / Sequencing
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— PackML / ISA-TR88.00.02 状态模型的「执行态 + 保持（暂停）态 +
                完成态 + 中止」四类状态语义，以及配方步序「逐步等待动作完成信号」
                的通行做法；步超时、暂停恢复、禁跳步三项为工程惯例约束。
                本件只借鉴**状态语义与约束项**，不借用其状态表实现。
                clean-room 声明 —— 零代码行复制；状态机为本件自有 ENUM + CASE，
                定时仅用 IEC 61131-3 标准库 TON，沿检测仅用标准库 R_TRIG。
                许可证 —— 本件 MIT；来源标签 packml 指标准状态模型术语，
                标准文本不属代码，无许可继承。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 3 · N9）
    ------------------------------------------------------------------
    功能说明  : 步号从 1 走到 nStepTotal。每步等待 bStepDone 上升沿推进，
                推进即「步号 + 1」；超过 nStepTotal 则完成。
                步超时：_tonStep 的 PT = tStep，IN = 运行态 且 非「步切换复位拍」；
                步号一旦切换（推进 / 跳步 / 暂停恢复）就置 _bTimerRestart，
                使下一拍 IN 断开一拍、计时器复位、本步重新从 0 计时 —— 若不这样做，
                计时器会跨步累计，第二步必然立刻超时（历史教训：定时器不自复位）。
                暂停恢复：bPause 为电平（TRUE 即暂停）。暂停期间步超时计时**复位**
                （IN 断开），恢复后本步重新计时；该语义写死于边界三，不留歧义。
                禁跳步：仅允许跳到「当前步 + 1」（等价于立即完成本步）；其余目标
                一律拒绝，置信息级码 0703，bError 保持 FALSE，状态与步号不变。
    错误码    : 16#0002_0701 组态非法（nStepTotal < 1 或 tStep <= T#0S），锁存 —— 故障级
                16#0002_0702 步超时（当前步未在 tStep 内收到完成信号），锁存 —— 故障级
                16#0002_0703 跳步被拒（目标非「当前步 + 1」或越出总量），不锁存 —— 信息级
                16#0002_0704 非法状态枚举值（CASE ELSE 兜底），锁存 —— 故障级
    码位总账  : 0701 / 0702 / 0704 用（故障级，锁存回放）｜ 0703 用（信息级，每拍重算）
    状态机    : ENUM E_DL_RseState 五态，CASE 全覆盖 + ELSE 兜底（回 eFault 置 0704）。
                迁移：eIdle -启动沿-> eRun -完成-> 步号+1（超总量 -> eDone）
                      eRun -bPause-> ePause -NOT bPause-> eRun
                      任意态 -bAbort-> eIdle（操作态，不发码）
                      任意态 -锁存故障-> eFault；eFault -bReset 沿-> eIdle（唯一解除边）
    边界与披露: 一 组态闸（R272 逐项点名）：nStepTotal < 1 拦截（无步可执行）；
                   tStep <= T#0S 拦截（零超时使第一步即失败，属组态错误）；
                二 输入闸：nJumpTo 为整型无 NaN 面，按 1..nStepTotal 区间校验，
                   越界即判为「跳步被拒」，不参与任何数组索引（本件无数组）；
                三 暂停恢复语义（R191 声明）：暂停期间步超时计时器复位，恢复后
                   本步从头计时 —— 即「暂停不计入步超时」，这是本件的判定口径；
                四 失能语义：本件无 bEn 引脚，停机由 bAbort 承担（电平有效），
                   bAbort 为真即回 eIdle 且步号清零、bStepActive / bPaused / bDone
                   全清零，不发码（操作态）；
                五 单拍位口径（R256）：bJumpRejected 为单拍信息位，段 1 统一预置，
                   仅在被拒的那一拍由 CASE 置真；bDone 为保持位（完成态持续为真）；
                六 定时器 _tonStep 与四个沿实例 _rtStart / _rtReset / _rtDone / _rtJump
                   全部每周期无条件调用（规则 ⑦）；
                七 零全局变量、零 VAR_EXTERNAL、零物理地址、零除法、零数组下标。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 3 · N9）
*)
TYPE E_DL_RseState :
(
    eIdle  := 0,   (* 待机，等待启动 / idle, waiting for a start *)
    eRun   := 10,  (* 执行态（某一步激活中）/ running, a step is active *)
    ePause := 20,  (* 暂停态（步保持，超时计时复位）/ paused, the step holds and its timer resets *)
    eDone  := 30,  (* 完成态（全部步执行完毕，保持）/ done, every step finished, held *)
    eFault := 40   (* 故障态（锁存待复位）/ fault, latched for a reset *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_RecipeStepExec
VAR_INPUT
    bStart     : BOOL := FALSE;            (* 启动序列（上升沿有效），[标志] / the sequence start, rising edge *)
    bStepDone  : BOOL := FALSE;            (* 当前步动作完成（上升沿有效），[标志] / the current step finished, rising edge *)
    bPause     : BOOL := FALSE;            (* 暂停（电平有效，TRUE 即暂停），[标志] / the pause, level effective *)
    bAbort     : BOOL := FALSE;            (* 中止（电平有效），[标志] / the abort, level effective *)
    bReset     : BOOL := FALSE;            (* 故障复位（上升沿有效），[标志] / the fault reset, rising edge *)
    bJumpReq   : BOOL := FALSE;            (* 跳步请求（上升沿有效），[标志] / the jump request, rising edge *)
    nJumpTo    : INT := 0;                 (* 跳步目标步号，[号]，域 1..nStepTotal / the jump target step number *)
    nStepTotal : INT := 10;               (* 步总数，[步]，须 >= 1 / the total number of steps, must be at least one *)
    tStep      : TIME := T#30S;            (* 单步超时，[ms]，须 > T#0S / the per step timeout *)
END_VAR
VAR_OUTPUT
    eState      : E_DL_RseState := E_DL_RseState.eIdle; (* 状态出口，[状态] / the state outlet *)
    nStepNo     : INT;                     (* 当前步号，0 = 无步激活，[号] / the current step number, 0 = none *)
    bStepActive : BOOL;                    (* 当前步激活中，[标志] / the current step is active *)
    bPaused     : BOOL;                    (* 暂停中，[标志] / paused *)
    bDone       : BOOL;                    (* 序列完成（保持），[标志] / the sequence completed, held *)
    bJumpRejected : BOOL;                  (* 跳步被拒单拍位，[标志] / the jump was rejected, single scan *)
    bBusy       : BOOL;                    (* 序列占用中（执行或暂停），[标志] / the sequence is occupied *)
    bValid      : BOOL;                    (* 出口可信（非故障态），[标志] / the outlets are trustworthy *)
    bError      : BOOL;                    (* 故障标志，故障级码时为 TRUE / the error flag, TRUE on fault level *)
    nErrCode    : UDINT;                   (* 错误码，0 = 正常 / the error id, 0 = ok *)
END_VAR
VAR
    _rtStart     : R_TRIG;                 (* 启动上升沿实例（无条件调用）/ the start edge instance *)
    _rtReset     : R_TRIG;                 (* 复位上升沿实例（无条件调用）/ the reset edge instance *)
    _rtDone      : R_TRIG;                 (* 步完成上升沿实例（无条件调用）/ the step done edge instance *)
    _rtJump      : R_TRIG;                 (* 跳步请求上升沿实例（无条件调用）/ the jump request edge instance *)
    _tonStep     : TON;                    (* 步超时计时实例（无条件调用）/ the step timeout timer *)
    _eState      : E_DL_RseState := E_DL_RseState.eIdle; (* 状态寄存器，[状态] / the internal state register *)
    _nStep       : INT;                    (* 当前步号寄存器，[号] / the internal step register *)
    _bFault      : BOOL;                   (* 故障锁存位，仅 bReset 上升沿解除 / the latched fault bit *)
    _nCodeLatch  : UDINT;                  (* 锁存成因码，故障期回放 / the latched cause code *)
    _bCfgBad     : BOOL;                   (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bTimerIn    : BOOL;                   (* 步计时器 IN 条件（显式条件）/ the timer IN condition *)
    _bTimerRestart : BOOL;                 (* 步切换复位拍标志（使计时器下一拍复位）/ the timer restart flag *)
    _bJumpOk     : BOOL;                   (* 跳步目标合法标志，[标志] / the jump target is legal *)
    _bAdvanced   : BOOL;                   (* 本拍发生过步号推进，[标志] / the step advanced this scan *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置，单拍位在此清零）/ segment 1, preset every outlet
eState       := _eState;                   // 状态出口先镜像寄存器 / mirror the state register first
nStepNo      := _nStep;                    // 步号出口先镜像寄存器 / mirror the step register first
bStepActive  := FALSE;                     // 步激活位预清零 / preset the step active flag false
bPaused      := FALSE;                     // 暂停位预清零 / preset the paused flag false
bDone        := FALSE;                     // 完成位预清零（保持态另由 eDone 分支置真）/ preset the done flag false
bJumpRejected := FALSE;                    // 跳步被拒单拍位预清零（R256）/ preset the jump rejected flag false
bBusy        := FALSE;                     // 占用标志预清零 / preset the busy flag false
bValid       := TRUE;                      // 可用标志预置真（故障态再清）/ preset valid true
bError       := FALSE;                     // 故障标志预清零 / preset the error flag false
nErrCode     := 0;                         // 错误码预置无错 / preset the code to zero
_bAdvanced   := FALSE;                     // 推进标志预清零 / preset the advanced flag false

// 段 2｜沿实例与定时器无条件周期调用（规则 ⑦）/ segment 2, the edges and the timer, called unconditionally
_rtStart(CLK := bStart);                   // 启动沿，每周期无条件刷新 / the start edge, refreshed every scan
_rtReset(CLK := bReset);                   // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan
_rtDone(CLK := bStepDone);                 // 步完成沿，每周期无条件刷新 / the step done edge, refreshed every scan
_rtJump(CLK := bJumpReq);                  // 跳步沿，每周期无条件刷新 / the jump edge, refreshed every scan
_bTimerIn := (_eState = E_DL_RseState.eRun) AND NOT _bTimerRestart; // 运行态且非复位拍才计时
_tonStep(IN := _bTimerIn, PT := tStep);    // 步超时计时，每周期无条件调用 / the step timeout timer
_bTimerRestart := FALSE;                   // 复位拍已消费，本拍清标志 / the restart flag is consumed

// 段 3｜复位解除：唯一可到达的清除边（R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除故障锁存 / release the fault latch
    _nCodeLatch := 0;                      // 清锁存码 / clear the latched code
    _eState     := E_DL_RseState.eIdle;    // 回待机（安全相）/ back to the safe idle phase
    _nStep      := 0;                      // 步号清零 / clear the step number
    _bTimerRestart := TRUE;                // 计时器下一拍复位 / restart the timer next scan
END_IF

// 段 4｜组态守卫（R272 逐项点名）/ segment 4, the configuration guard
_bCfgBad := (nStepTotal < 1) OR (tStep <= T#0S); // 步总数为零 或 超时非正 / no steps or a non positive timeout

// 段 5｜首次成因锁存（故障期不重推断，R189）/ segment 5, the first cause latch
IF NOT _bFault THEN                        // 未锁存才登记 / register only while healthy
    IF _bCfgBad THEN                       // 组态非法 / an illegal configuration
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0701;       // 故障级：组态非法 / fault level: an illegal configuration
        _eState     := E_DL_RseState.eFault; // 迁入故障态 / enter the fault state
    END_IF
END_IF

// 段 6｜中止命令（操作态，不发码）/ segment 6, the abort command
IF bAbort AND NOT _bFault THEN             // 中止有效且无锁存故障 / an abort without a latched fault
    _eState := E_DL_RseState.eIdle;        // 回待机 / back to idle
    _nStep  := 0;                          // 步号清零 / clear the step number
END_IF

// 段 7｜状态机（ENUM + CASE + ELSE 兜底）/ segment 7, the state machine
CASE _eState OF
    E_DL_RseState.eIdle:                   // 待机态 / the idle state
        bValid := TRUE;                    // 待机出口可信 / the idle outlets are trustworthy
        IF _rtStart.Q AND NOT _bFault THEN // 启动沿且无锁存故障 / a start edge without a latched fault
            _nStep  := 1;                  // 从第 1 步开始 / start from step one
            _eState := E_DL_RseState.eRun; // 进入执行态 / enter the running state
            _bTimerRestart := TRUE;        // 计时器下一拍复位（本步从 0 计时）/ restart the timer for the new step
        END_IF
    E_DL_RseState.eRun:                    // 执行态 / the running state
        bStepActive := TRUE;               // 当前步激活 / the step is active
        bBusy       := TRUE;               // 序列占用 / the sequence is occupied
        IF bPause THEN                     // 暂停命令（电平）/ the pause command, level
            _eState := E_DL_RseState.ePause; // 进入暂停态 / enter the paused state
        ELSIF _rtJump.Q THEN               // 跳步请求沿 / a jump request edge
            IF (nJumpTo >= 1) AND (nJumpTo <= nStepTotal) AND (nJumpTo = (_nStep + 1)) THEN
                _bJumpOk := TRUE;          // 目标为「当前步 + 1」，合法 / the target is the next step, legal
            ELSE                           // 其余目标一律拒绝（禁跳步）/ every other target is refused
                _bJumpOk := FALSE;         // 非法目标 / an illegal target
            END_IF
            IF _bJumpOk THEN               // 合法跳步 / a legal jump
                IF _nStep >= nStepTotal THEN // 已是最后一步 / already the last step
                    _eState := E_DL_RseState.eDone; // 进入完成态 / enter the done state
                ELSE                       // 非最后一步 / not the last step
                    _nStep := _nStep + 1;  // 步号推进 / advance the step
                    _bAdvanced := TRUE;    // 标记推进 / mark the advance
                END_IF
            ELSE                           // 跳步被拒 / the jump is refused
                bJumpRejected := TRUE;     // 单拍被拒位（R256）/ the single scan rejected flag
                nErrCode      := 16#0002_0703; // 信息级：跳步被拒（不置 bError，R45）/ info level, no fault flag
            END_IF
        ELSIF _rtDone.Q THEN               // 步完成沿 / the step done edge
            IF _nStep >= nStepTotal THEN   // 最后一步完成 / the last step finished
                _eState := E_DL_RseState.eDone; // 进入完成态 / enter the done state
            ELSE                           // 非最后一步 / not the last step
                _nStep := _nStep + 1;      // 步号推进 / advance the step
                _bAdvanced := TRUE;        // 标记推进 / mark the advance
            END_IF
        ELSIF _tonStep.Q THEN              // 步超时 / the step timed out
            _bFault     := TRUE;           // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_0702;   // 故障级：步超时 / fault level: a step timeout
            _eState     := E_DL_RseState.eFault; // 迁入故障态 / enter the fault state
        END_IF
    E_DL_RseState.ePause:                  // 暂停态 / the paused state
        bStepActive := TRUE;               // 步保持（不推进也不超时）/ the step holds, neither advanced nor timed
        bPaused     := TRUE;               // 暂停标志 / the paused flag
        bBusy       := TRUE;               // 序列仍占用 / the sequence is still occupied
        IF NOT bPause THEN                 // 暂停解除 / the pause released
            _eState := E_DL_RseState.eRun; // 回执行态 / back to running
            _bTimerRestart := TRUE;        // 本步重新计时（边界三口径）/ the step is timed from zero again
        END_IF
    E_DL_RseState.eDone:                   // 完成态（保持）/ the done state, held
        bDone  := TRUE;                    // 完成标志 / the done flag
        bValid := TRUE;                    // 完成态出口可信 / the done outlets are trustworthy
        IF _rtStart.Q THEN                 // 再次启动 = 新一轮 / a new start begins a new run
            _nStep  := 1;                  // 回到第 1 步 / back to step one
            _eState := E_DL_RseState.eRun; // 进入执行态 / enter the running state
            _bTimerRestart := TRUE;        // 计时器复位 / restart the timer
        END_IF
    E_DL_RseState.eFault:                  // 故障态（锁存保持）/ the fault state, latched
        bValid   := FALSE;                 // 出口不可信 / the outlets are not trustworthy
        bError   := TRUE;                  // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;           // 回放锁存码 / replay the latched code
    ELSE                                   // 非法枚举兜底（回安全相 + 置码，规则 ⑥）/ the illegal enumeration guard
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0704;       // 故障级：非法状态枚举 / fault level: an illegal state value
        _eState     := E_DL_RseState.eFault; // 回安全相 / force the safe fault state
        bValid      := FALSE;              // 出口不可信 / the outlets are not trustworthy
        bError      := TRUE;               // 故障标志置位 / raise the fault flag
        nErrCode    := _nCodeLatch;        // 回放锁存码 / replay the latched code
END_CASE

// 段 8｜步推进后的计时器复位请求（下一拍生效）/ segment 8, request a timer restart after an advance
IF _bAdvanced THEN                         // 本拍发生过推进 / the step advanced this scan
    _bTimerRestart := TRUE;                // 下一拍断 IN 一拍，新步从 0 计时 / drop IN next scan so the new step times from zero
END_IF

// 段 9｜出口映射（名实双出口同源，R191；单点写入，无自赋值）/ segment 9, the outlet mapping
eState  := _eState;                        // 状态出口 = 寄存器 / the state outlet mirrors the register
nStepNo := _nStep;                         // 步号出口 = 寄存器 / the step outlet mirrors the register
END_FUNCTION_BLOCK
