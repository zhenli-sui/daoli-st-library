(*
    FB_DL_PumpPrimingWatch —— 离心泵灌泵期监视（充水确认窗 + 起立判据 + 干转前预警）
    ------------------------------------------------------------------
    组件名称  : FB_DL_PumpPrimingWatch
    分类      : DL_Device / PumpHealth
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 内部台账 T2-2 行「命令 - 监视 - 判定」三段分层骨架
                （R11 / R13 先例，self 判据）。
                本件只借**骨架**，灌泵窗口 / 双判据 / 码位 100% 自有。
                clean-room 声明 —— 零代码行复制；定时与沿检测仅用 IEC 61131-3
                标准库 TON / R_TRIG。
                许可证 —— 本件 MIT；来源标签 t2-2-lbp 为闭源内部台账，
                按最严口径零代码行接触。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R71 构建轮 · 批 2 · 序号 8）
    ------------------------------------------------------------------
    功能说明  : 灌泵期（启动前充水确认）监视顺控：
                eIdle 待机 →（bStartCmd 上升沿）ePriming 灌泵确认窗计时
                →（流量 ∧ 压力双判据同拍持续 tConfirm）ePrimed 灌泵完成放行
                →（命令撤销）eIdle；窗满仍无起立 → ePrimeFail 失败相 +
                锁存码（干转前预警，锁存待复位）。
                双窗设计（R41 / R42 口径）：
                _tonWin 灌泵总窗（PT = tPrimeWin，IN = 相为 ePriming），
                _tonCfm 起立判据驻留确认（PT = tConfirm，IN = 相为 ePriming
                且流量 ∧ 压力本拍实时复验成立）——两实例每周期无条件调用，
                IN 为显式条件，选窗不依赖可跳过分支。
                窗满迁移判据（R41 同拍竞态收敛）：失败 = 窗满 ∧ 反馈**仍**
                无效（窗满拍复验一次）；反馈迟到但在窗满拍有效 → 不判失败，
                由 _tonCfm 驻留确认路径继续收敛至 ePrimed（驻留上限
                tConfirm 有界，不会无限延窗）。
                起立判据「先判后信」（R42）：bFlowOK / bPressOK 为本拍复验的
                实时反馈，沿上不锁存旧反馈。
                失败锁存语义：ePrimeFail 相锁存（37C1），bReset 上升沿唯一
                解除回 eIdle —— 干转前预警属安全结论，不允许命令撤销顺手
                清除（R303 失能不清锁存同口径）。
    错误码    : 16#0002_37C0 组态非法（tPrimeWin / tConfirm 非正，或
                            tConfirm >= tPrimeWin 配比吞没失败判据），锁存
                            —— 故障级
                16#0002_37C1 灌泵窗满且起立判据仍无效（干转前预警），锁存
                            —— 故障级
                16#0002_37C2 非法相枚举（CASE ELSE 兜底），锁存 —— 故障级
    码位总账  : 37C0 / 37C1 / 37C2 用（均故障级，本件无信息级码）
    状态机    : ENUM E_DL_PpwPhase 五态，CASE 全覆盖 + ELSE 兜底（锁存 37C2
                回 eFault）。迁移表见功能说明；bReset 上升沿：解锁存（含
                ePrimeFail）→ eIdle（唯一可到达的解除边，R188）。
    边界与披露: 一 组态判据逐项点名（R272）：tPrimeWin <= T#0S 拦截；
                   tConfirm < T#0S 拦截（TIME 非负语义下的防御复检）；
                   **同拍双窗配比约束（R100）：tConfirm >= tPrimeWin 拦截** ——
                   确认驻留窗大于等于总窗时，失败判据（窗满 ∧ 反馈无效）
                   永不成立，干转预警静默失效，属组态级禁止；
                二 布尔反馈输入（bFlowOK / bPressOK / bStartCmd）无非有限面，
                   不设数值闸；反馈真值即判据源，无换算无死区（无魔法数）；
                三 失能（bEn = FALSE）语义写死（R303）：bPriming / bPrimed /
                   bPrimeFail 输出全清零、bError 清零、码清零、状态回 eIdle，
                   但 _bFault 锁存位**不被失能清除**（失能是操作态，不是
                   复位），必须 bReset 上升沿才解除 —— 两者语义分离；
                四 定时器 _tonWin / _tonCfm 无论失能 / 故障 / 正常均在段 7
                   无条件调用，IN 为段 6 计算出的显式条件；
                五 ePrimed 相命令撤销即回 eIdle（电平判定，非沿 —— 命令
                   保持则持续放行，命令撤销即收回放行资格，名实一致）；
                六 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标、
                   无除法、无浮点量。
    分工声明  : FB_DL_PumpDryRunProtect（DL_Device，运行期干转保护）、
                FB_DL_PumpCavitationGuard（DL_Device，运行期汽蚀防护）、
                FB_DL_PumpAlternationLead（DL_Process，多泵轮值）——本件专管
                **灌泵期**（启动前充水确认），运行期判据归既有三件，
                四者互引分工边界，不互代。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R71 构建轮 · 批 2 · 序号 8）
*)
TYPE E_DL_PpwPhase :
(
    eIdle      := 0,   (* 待机，等启泵命令沿 / idle, waiting for a start command edge *)
    ePriming   := 10,  (* 灌泵确认窗相（双窗计时 + 起立判据监视）/ the priming phase, the dual window timing plus the primed criteria watch *)
    ePrimed    := 20,  (* 灌泵完成相（放行，命令撤销即回待机）/ the primed phase, released, back to idle on command withdrawal *)
    ePrimeFail := 30,  (* 灌泵失败相（窗满无起立，锁存待复位）/ the prime fail phase, the window full without priming, latched for a reset *)
    eFault     := 40   (* 故障相（非法枚举兜底锁存）/ the fault phase, the illegal enumeration guard latch *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PumpPrimingWatch
VAR_INPUT
    bEn       : BOOL := TRUE;              (* 使能，[标志]，FALSE 时出口清零且状态回待机（R303）/ the enable, FALSE clears the outlets and returns to idle *)
    bReset    : BOOL := FALSE;             (* 故障 / 失败复位（上升沿有效），[标志] / the reset, rising edge effective, the only release *)
    bStartCmd : BOOL := FALSE;             (* 启泵命令（上升沿启动 / 电平保持放行），[标志] / the pump start command *)
    bFlowOK   : BOOL := FALSE;             (* 流量起立反馈（本拍实时复验），[标志] / the flow established feedback, verified live this scan *)
    bPressOK  : BOOL := FALSE;             (* 压力起立反馈（本拍实时复验），[标志] / the pressure established feedback, verified live this scan *)
    tPrimeWin : TIME := T#10S;             (* 灌泵确认总窗，[ms]，须 > T#0S / the priming window *)
    tConfirm  : TIME := T#2S;              (* 起立判据驻留确认时长，[ms]，须 < tPrimeWin（配比约束）/ the criteria hold duration, must be under tPrimeWin *)
END_VAR
VAR_OUTPUT
    eState    : E_DL_PpwPhase := E_DL_PpwPhase.eIdle; (* 相状态出口，[相] / the phase outlet *)
    bPriming  : BOOL;                      (* 灌泵进行中（确认窗计时相），[标志] / the priming in progress flag *)
    bPrimed   : BOOL;                      (* 灌泵完成放行，[标志] / the primed release flag *)
    bPrimeFail: BOOL;                      (* 灌泵失败（干转前预警，锁存），[标志] / the prime fail flag, latched *)
    bError    : BOOL;                      (* 故障标志，锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode  : UDINT;                     (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed from the latch *)
END_VAR
VAR
    _rtStart    : R_TRIG;                  (* 启泵命令上升沿实例（无条件调用）/ the start command rising edge instance *)
    _rtReset    : R_TRIG;                  (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonWin     : TON;                     (* 灌泵总窗实例（无条件调用）/ the priming window timer *)
    _tonCfm     : TON;                     (* 起立判据驻留确认实例（无条件调用）/ the criteria hold confirmation timer *)
    _ePhase     : E_DL_PpwPhase := E_DL_PpwPhase.eIdle; (* 相状态寄存器 / the internal phase register *)
    _bFault     : BOOL;                    (* 故障锁存位（含灌泵失败锁存），仅 bReset 上升沿解除 / the latched fault bit, including the prime fail latch *)
    _nCodeLatch : UDINT;                   (* 锁存成因码，故障期回放 / the latched cause code, replayed *)
    _bCfgBad    : BOOL;                    (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bCriteria  : BOOL;                    (* 起立判据本拍复验值（流量 ∧ 压力）/ the primed criteria verified this scan *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置）/ segment 1, preset every outlet
eState    := _ePhase;                     // 相出口先镜像寄存器 / mirror the phase register first
bPriming  := FALSE;                       // 灌泵进行中预清零 / preset the priming flag false
bPrimed   := FALSE;                       // 放行预清零 / preset the primed flag false
bPrimeFail:= FALSE;                       // 失败预清零 / preset the fail flag false
bError    := FALSE;                       // 故障标志预清零 / preset the error flag false
nErrCode  := 0;                           // 错误码预置无错 / preset the code to zero
_bCriteria:= FALSE;                       // 起立判据预清零 / preset the criteria false

// 段 2｜沿检测实例无条件调用（规则 ⑦）/ segment 2, the edge instances, called unconditionally
_rtStart(CLK := bStartCmd);               // 启泵沿，每周期无条件刷新 / the start edge, refreshed every scan
_rtReset(CLK := bReset);                  // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜锁存解除：仅 bReset 上升沿，锁存码同步清零（唯一解除边，R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                        // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                 // 解除故障锁存（含灌泵失败）/ release the fault latch, including the prime fail
    _nCodeLatch := 0;                     // 清锁存码（可到达的清除边）/ clear the latched code, a reachable clearing edge
    _ePhase     := E_DL_PpwPhase.eIdle;   // 回待机相（安全相）/ back to the safe idle phase
END_IF

// 段 4｜组态守卫（边界一逐项点名 + 双窗配比约束，R272 / R100）/ segment 4, the configuration guard
_bCfgBad := (tPrimeWin <= T#0S)           // 总窗非正 / a non positive window
         OR (tConfirm < T#0S)             // 驻留为负（TIME 非负语义下的防御复检）/ a negative hold duration
         OR (tConfirm >= tPrimeWin);      // 配比约束：驻留吞没总窗 → 失败判据永不成立（干转预警静默失效）/ the hold swallows the window, the fail verdict unreachable

// 段 5｜首次成因锁存（故障期不重推断，回放锁存码，R189）/ segment 5, the first-cause latch
IF NOT _bFault THEN                       // 未锁存才登记成因 / a cause is registered only while not latched
    IF _bCfgBad THEN                      // 组态非法（根因）/ the configuration, the root cause
        _bFault     := TRUE;              // 置锁存 / latch it
        _nCodeLatch := 16#0002_37C0;      // 故障级：组态非法 / fault level: an illegal configuration
        _ePhase     := E_DL_PpwPhase.eFault; // 迁入故障相 / enter the fault phase
    END_IF
END_IF

// 段 6｜起立判据本拍复验（R42 先判后信，显式条件供定时器与状态机共用）/ segment 6, the criteria verified this scan
_bCriteria := bFlowOK AND bPressOK;       // 流量 ∧ 压力双判据同拍成立 / the flow and the pressure both hold this scan

// 段 7｜双定时器无条件周期调用（规则 ⑦，IN 为显式条件）/ segment 7, the dual timers, called unconditionally
_tonWin(IN := (_ePhase = E_DL_PpwPhase.ePriming), PT := tPrimeWin);  // 灌泵总窗计时 / the priming window timer
_tonCfm(IN := ((_ePhase = E_DL_PpwPhase.ePriming) AND _bCriteria), PT := tConfirm); // 驻留确认计时 / the hold confirmation timer

// 段 8｜失能相输出回夹（R57 + R303，先于状态机执行）/ segment 8, the disable phase output clamping
IF (NOT bEn) AND (NOT _bFault) THEN       // 失能且无锁存故障（操作态不发码）/ disabled without a latched fault
    _ePhase := E_DL_PpwPhase.eIdle;       // 状态回待机 / back to idle
END_IF                                    // 输出清零由段 1 预置 + 状态机仅在运行许可时执行共同保证

// 段 9｜相状态机（ENUM + CASE + ELSE 兜底，仅运行许可时执行）/ segment 9, the phase machine, run permit only
IF bEn AND NOT _bFault THEN               // 运行许可成立 / the run permit holds
CASE _ePhase OF
    E_DL_PpwPhase.eIdle:                  // 待机相 / the idle phase
        IF _rtStart.Q THEN                // 启泵命令上升沿 / a start command edge
            _ePhase := E_DL_PpwPhase.ePriming; // 进入灌泵确认窗相 / enter the priming phase
        END_IF
    E_DL_PpwPhase.ePriming:               // 灌泵确认窗相 / the priming phase
        IF _tonCfm.Q THEN                 // 起立判据驻留确认完成（双判据持续 tConfirm）/ the criteria hold confirmed
            _ePhase := E_DL_PpwPhase.ePrimed; // 进入灌泵完成相 / enter the primed phase
        ELSIF _tonWin.Q AND (NOT _bCriteria) THEN // 窗满拍复验一次：反馈仍无效才判失败（R41 同拍竞态收敛）/ the window full and the feedback still invalid
            _bFault     := TRUE;          // 锁存故障（干转前预警）/ latch the fault
            _nCodeLatch := 16#0002_37C1;  // 故障级：窗满无起立 / fault level: the window full without priming
            _ePhase     := E_DL_PpwPhase.ePrimeFail; // 迁入失败相（锁存待复位）/ enter the prime fail phase
        END_IF                            // 窗满但反馈已有效 → 不判失败，驻留路径继续收敛（有界 tConfirm）
    E_DL_PpwPhase.ePrimed:                // 灌泵完成相（放行）/ the primed phase
        IF NOT bStartCmd THEN             // 命令撤销（电平判定，边界五）/ the command withdrawn, a level verdict
            _ePhase := E_DL_PpwPhase.eIdle; // 回待机（放行资格随预置收回）/ back to idle, the release withdrawn by the preset
        END_IF
    E_DL_PpwPhase.ePrimeFail:             // 灌泵失败相（锁存保持）/ the prime fail phase, latched
        bError   := TRUE;                 // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;          // 回放锁存码（不按当下输入重推断）/ replay the latched code
    E_DL_PpwPhase.eFault:                 // 故障相（锁存保持）/ the fault phase, latched
        bError   := TRUE;                 // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;          // 回放锁存码 / replay the latched code
    ELSE                                  // 非法枚举兜底（回安全相 + 置码，规则 ⑥）/ the illegal enumeration guard
        _bFault     := TRUE;              // 置锁存 / latch it
        _nCodeLatch := 16#0002_37C2;      // 故障级：非法相枚举 / fault level: an illegal phase value
        _ePhase     := E_DL_PpwPhase.eFault; // 回安全相（故障相）/ force the safe fault phase
        bError      := TRUE;              // 故障标志置位（禁静默）/ raise the flag
        nErrCode    := _nCodeLatch;       // 回放锁存码 / replay the latched code
END_CASE
END_IF

// 段 10｜出口映射（名实双出口同源，单点写入，R191）/ segment 10, the outlet mapping
bPriming   := (_ePhase = E_DL_PpwPhase.ePriming); // 灌泵进行中出口与相寄存器同源 / the priming outlet shares the register
bPrimed    := (_ePhase = E_DL_PpwPhase.ePrimed);    // 放行出口与相寄存器同源 / the primed outlet shares the register
bPrimeFail := (_ePhase = E_DL_PpwPhase.ePrimeFail); // 失败出口与相寄存器同源 / the fail outlet shares the register
eState     := _ePhase;                    // 相出口 = 寄存器（段 9 之后不再触碰）/ the phase outlet, not touched after segment 9
IF _bFault THEN                           // 锁存故障相出口补充 / the latched fault supplement
    bError   := TRUE;                     // 故障标志 / the fault flag
    nErrCode := _nCodeLatch;              // 回放锁存码 / replay the latched code
END_IF
END_FUNCTION_BLOCK
