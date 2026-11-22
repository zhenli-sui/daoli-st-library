(*
  ==================================================================
  组件名 Component  : FB_DL_FanVfdBypassSwap
  分类   Category   : DL_Device
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 单台风机变频 → 工频旁通切换顺控。相位机 eIdle → eStopVfd →
                      eWaitSpinDown → eCloseBypass → eRunDurance → eStable / eFault；
                      任何中间态严格双断（bVfdRun 与 bBypassRun 不同拍同为真）；
                      含降速阈值判据、切换最小间隔窗 tGapMin、旁通接触器确认反馈
                      bBypassFb、失败重试 nRetryMax 与超时 eSwapTimeout。
  来源   Source     : t2-2-lbp
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；变频 / 工频旁通切换
                      时序为通用电气传动语义，clean-room 自研实现，未复制任何
                      闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / LREAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  同拍多窗配比约束（R100）：五个窗职责分离 —— tStopTo 判变频反馈消失（短），
                      tGapMin 切换最小间隔（中），tSpinMax 降速总窗（长），
                      tCloseTo 旁通反馈确认窗，tStableMin 稳定驻留窗；
                      配比约束 tSpinMax > tGapMin 在组态域闸内直接判故障，
                      其余各窗互斥（每窗 IN 串本相闸），任一时刻只有一个窗在计时。
  边界 Boundary     :
                      一 本件只出切换命令与诊断，不做接触器本体驱动、不写变频器参数
                         （属主边界）；
                      二 互斥不变量：bVfdRun 与 bBypassRun 恒不同拍为真（结构性成立，
                         出口为相位派生电平）；
                      三 相级看门狗使能只用「相驻留」本身（R145），不叠加业务条件补集；
                      四 故障锁存解除路径 = bReset 上升沿（唯一路径，头注释声明，R188）；
                      五 eWaitSpinDown 相退出条件 ≥2 条（转速达标 / 超时 / 失能，R98）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      bVfdRun / bBypassRun 为相位派生命令电平，相外恒假；
                      bBothOff 为双断指示（两命令均假的派生量）；
                      eFault 为锁存回放；ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 3 · 序号 12）
  ==================================================================
*)

TYPE E_DL_FbsPhase :
(
    eIdle        := 0,  // 空闲：变频运行保持，等切换申请 / idle, the VFD holds and waits for a swap request
    eStopVfd     := 10, // 停变频：撤变频命令等反馈消失 / stopping, the VFD command is withdrawn and the feedback awaited
    eWaitSpinDown:= 20,  // 等降速：转速阈值 + 最小间隔窗双判 / waiting, the speed threshold and the gap window
    eCloseBypass := 30,  // 关旁通：出旁通命令等反馈确认 / closing, the bypass command waits for the feedback
    eRunDurance  := 40, // 稳定中：旁通保持，驻留稳定窗 / running in, the bypass holds through the stability window
    eStable      := 50, // 已稳定：旁通运行，监视反馈 / stable, the bypass runs with feedback watch
    eFault       := 90  // 故障：成因锁存，双断 / fault, the cause is latched with both commands off
);
END_TYPE

TYPE E_DL_FbsFault :
(
    eNone          := 0, // 无成因 / no cause
    eSwapTimeout   := 1, // 切换超时（停变频或降速窗耗尽，故障级，与 bError 配对）/ the swap timed out, fault grade paired with bError
    eFbLost        := 2, // 旁通反馈丢失（故障级，与 bError 配对）/ the bypass feedback was lost, fault grade paired with bError
    eRetryExhausted := 3, // 重试用尽（故障级，与 bError 配对）/ the retries were exhausted, fault grade paired with bError
    eCfgIllegal    := 4, // 组态非法（故障级，与 bError 配对）/ illegal configuration, fault grade paired with bError
    ePhaseBad      := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_FanVfdBypassSwap
VAR_INPUT
    bEnable    : BOOL := TRUE;    // 使能，失能时停顺控回空闲 [-] / enable, the sequence stops when disabled
    bReset     : BOOL := FALSE;   // 复位上升沿清故障锁存与重试计数 [-] / reset rising edge clears the fault latch and the retry count
    bStartSwap : BOOL := FALSE;   // 切换申请脉冲，上升沿受理 [-] / the swap request pulse, accepted on the rising edge
    bAbort     : BOOL := FALSE;   // 中止（电平），任何中间态立即双断回空闲 [-] / abort level, any middle phase goes both off and back to idle
    bVfdFb     : BOOL := TRUE;    // 变频运行反馈 [-] / the VFD running feedback
    bBypassFb  : BOOL := FALSE;   // 旁通接触器确认反馈 [-] / the bypass contactor feedback
    fSpeed     : LREAL := 0.0;    // 风机实际转速 [转每分] / the actual fan speed [rpm]
    fSpeedMin  : LREAL := 50.0;   // 旁通投入转速阈值 [转每分]，域 大于零 / the bypass engagement speed threshold [rpm], domain above zero
    nRetryMax  : INT := 2;        // 旁通重试上限 [次]，域 0..9 / the retry ceiling [count], domain zero to nine
    tStopTo    : TIME := T#10S;   // 变频反馈消失窗 [毫秒]，域 大于零 / the VFD feedback drop window [millisecond], domain above zero
    tGapMin    : TIME := T#2S;    // 切换最小间隔窗 [毫秒]，域 大于零 / the minimum swap gap window [millisecond], domain above zero
    tSpinMax   : TIME := T#60S;   // 降速总窗 [毫秒]，域 大于 tGapMin / the spin down window [millisecond], above the gap
    tCloseTo   : TIME := T#5S;    // 旁通反馈确认窗 [毫秒]，域 大于零 / the bypass feedback confirm window [millisecond], domain above zero
    tStableMin : TIME := T#10S;   // 稳定驻留窗 [毫秒]，域 大于零 / the stability dwell window [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    bVfdRun    : BOOL := FALSE;  // 变频运行保持命令（相位派生电平）[-] / the VFD hold command, a phase derived level
    bBypassRun : BOOL := FALSE;  // 旁通运行命令（相位派生电平）[-] / the bypass run command, a phase derived level
    bBothOff   : BOOL := TRUE;   // 双断指示（两命令均假）[-] / the both off indicator
    nRetry     : INT := 0;       // 当前重试次数 [次] / the current retry count [count]
    ePhase     : E_DL_FbsPhase := E_DL_FbsPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault     : E_DL_FbsFault := E_DL_FbsFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError     : BOOL := FALSE;  // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtSwap     : R_TRIG; // 切换申请沿检测，段 0 无条件刷新 / swap request edge, refreshed unconditionally in segment zero
    rtReset    : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonStop    : TON;    // 变频反馈消失窗，段 0 无条件刷新 / the VFD feedback drop window, refreshed unconditionally
    tonGap     : TON;    // 切换最小间隔窗，段 0 无条件刷新 / the minimum gap window, refreshed unconditionally
    tonSpin    : TON;    // 降速总窗，段 0 无条件刷新 / the spin down window, refreshed unconditionally
    tonClose   : TON;    // 旁通反馈确认窗，段 0 无条件刷新 / the feedback confirm window, refreshed unconditionally
    tonStable  : TON;    // 稳定驻留窗，段 0 无条件刷新 / the stability dwell window, refreshed unconditionally
    _ePhase    : E_DL_FbsPhase := E_DL_FbsPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC    : E_DL_FbsFault := E_DL_FbsFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault    : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit     : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad   : BOOL := FALSE; // 组态非法判定 [-] / the illegal configuration verdict
    _nRetry    : INT := 0;      // 重试计数工作值 [次] / the retry count working value [count]
    _nRetryUse : INT := 2;      // 钳定后的重试上限 [次] / the clamped retry ceiling [count]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸（FB50-1）/ segment 0, unconditional refresh, no instance call inside a branch
rtSwap(CLK := bStartSwap); // 切换申请沿 / the swap request edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonStop(IN := (_ePhase = E_DL_FbsPhase.eStopVfd) AND (NOT _bFault), PT := tStopTo); // 变频反馈消失窗 / the VFD feedback drop window
tonGap(IN := (_ePhase = E_DL_FbsPhase.eWaitSpinDown) AND (NOT bVfdFb) AND (NOT _bFault), PT := tGapMin); // 最小间隔窗，自变频反馈消失起计 / the gap window from the feedback drop
tonSpin(IN := (_ePhase = E_DL_FbsPhase.eWaitSpinDown) AND (NOT _bFault), PT := tSpinMax); // 降速总窗 / the spin down window
tonClose(IN := (_ePhase = E_DL_FbsPhase.eCloseBypass) AND (NOT _bFault), PT := tCloseTo); // 旁通反馈确认窗 / the feedback confirm window
tonStable(IN := (_ePhase = E_DL_FbsPhase.eRunDurance) AND (NOT _bFault), PT := tStableMin); // 稳定驻留窗 / the stability dwell window

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_FbsPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaulC := E_DL_FbsFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nRetry := 0; // 重试计数清零 / clear the retry count
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清重试计数（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_FbsFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_FbsPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _nRetry := 0; // 作用域三：清重试计数 / scope three, clear the retry count
END_IF

// 段 3｜组态域闸（R151 全覆盖，含 R100 配比约束）/ segment 3, the configuration gate with the window pairing constraint
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (fSpeedMin <= 0.0) OR (fSpeedMin <> fSpeedMin) OR ((fSpeedMin - fSpeedMin) <> (fSpeedMin - fSpeedMin)) THEN // 转速阈值越域 / the speed threshold is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nRetryMax < 0) OR (nRetryMax > 9) THEN // 重试上限越域 / the retry ceiling is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (tStopTo <= T#0S) OR (tGapMin <= T#0S) OR (tSpinMax <= T#0S) OR (tCloseTo <= T#0S) OR (tStableMin <= T#0S) THEN // 时间引脚非正 / a time pin is not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF tSpinMax <= tGapMin THEN // 降速总窗不大于最小间隔窗，违反双窗配比（R100）/ the spin window does not exceed the gap window
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_FbsFault.eCfgIllegal; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_FbsPhase.eFault; // 迁故障相 / migrate to the fault phase
END_IF
_nRetryUse := nRetryMax; // 重试上限直通 / the retry ceiling passes through
IF _nRetryUse < 0 THEN // 下越界 / below the floor
    _nRetryUse := 0; // 回钳到零 / clamp to zero
ELSIF _nRetryUse > 9 THEN // 上越界 / above the ceiling
    _nRetryUse := 9; // 回钳到九 / clamp to nine
END_IF

// 段 4｜中止电平优先处理：任何中间态立即双断回空闲 / segment 4, the abort level takes priority, any middle phase goes both off
IF bAbort AND (NOT _bFault) THEN // 中止且未锁存 / abort while unlatched
    _ePhase := E_DL_FbsPhase.eIdle; // 回空闲相（双断由出口派生）/ back to idle, both off by derivation
END_IF

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_FbsPhase.eIdle: // 空闲相：变频保持，等切换申请 / idle, the VFD holds and waits
    IF bEnable AND (NOT _bFault) AND (NOT bAbort) AND rtSwap.Q THEN // 申请沿受理 / the request edge is accepted
        _nRetry := 0; // 重试计数清零 / clear the retry count
        _ePhase := E_DL_FbsPhase.eStopVfd; // 迁停变频相 / migrate to the stop phase
    END_IF

E_DL_FbsPhase.eStopVfd: // 停变频相：等变频反馈消失 / the stop phase, the feedback drop is awaited
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_FbsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF NOT bVfdFb THEN // 变频反馈已消失 / the VFD feedback has dropped
        _ePhase := E_DL_FbsPhase.eWaitSpinDown; // 迁等降速相 / migrate to the wait phase
    ELSIF tonStop.Q THEN // 反馈消失窗耗尽 / the drop window expired
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_FbsFault.eSwapTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_FbsPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_FbsPhase.eWaitSpinDown: // 等降速相：转速阈值 + 最小间隔窗 + 总窗三判（退出条件 ≥2，R98）/ the wait phase, three verdicts and at least two exit conditions
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_FbsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF tonSpin.Q THEN // 降速总窗耗尽 / the spin window expired
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_FbsFault.eSwapTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_FbsPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF (fSpeed <= fSpeedMin) AND tonGap.Q THEN // 转速达标且最小间隔窗已过 / the speed is low and the gap window elapsed
        _ePhase := E_DL_FbsPhase.eCloseBypass; // 迁关旁通相 / migrate to the close phase
    END_IF

E_DL_FbsPhase.eCloseBypass: // 关旁通相：出命令等反馈，失败重试 / the close phase, the command waits for the feedback with retries
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_FbsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF bBypassFb THEN // 旁通反馈确认 / the bypass feedback confirmed
        _ePhase := E_DL_FbsPhase.eRunDurance; // 迁稳定中相 / migrate to the run in phase
    ELSIF tonClose.Q THEN // 确认窗耗尽 / the confirm window expired
        IF _nRetry < _nRetryUse THEN // 重试未用尽 / retries remain
            _nRetry := _nRetry + 1; // 重试计数递增 / increment the retry count
            _ePhase := E_DL_FbsPhase.eWaitSpinDown; // 回等降速相重走间隔窗 / back to the wait phase for a fresh gap
        ELSE // 重试用尽 / retries exhausted
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_FbsFault.eRetryExhausted; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_FbsPhase.eFault; // 迁故障相 / migrate to the fault phase
        END_IF
    END_IF

E_DL_FbsPhase.eRunDurance: // 稳定中相：旁通保持，驻留稳定窗 / the run in phase, the bypass holds through the dwell window
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_FbsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF NOT bBypassFb THEN // 旁通反馈丢失 / the bypass feedback was lost
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_FbsFault.eFbLost; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_FbsPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF tonStable.Q THEN // 稳定驻留窗已过 / the dwell window elapsed
        _ePhase := E_DL_FbsPhase.eStable; // 迁已稳定相 / migrate to the stable phase
    END_IF

E_DL_FbsPhase.eStable: // 已稳定相：旁通运行，持续监视反馈 / the stable phase, the bypass runs with a continuous feedback watch
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_FbsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF NOT bBypassFb THEN // 旁通反馈丢失 / the bypass feedback was lost
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_FbsFault.eFbLost; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_FbsPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_FbsPhase.eFault: // 故障相：双断，等复位沿 / the fault phase, both off until the reset edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_FbsPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_FbsFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_FbsPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜命令出口派生（互斥不变量的结构性承载）/ segment 6, the command outlets, the structural carrier of the mutual exclusion
bVfdRun := (_ePhase = E_DL_FbsPhase.eIdle) AND bEnable AND (NOT _bFault) AND (NOT bAbort); // 变频保持命令：仅空闲相派生 / the VFD hold command, derived in the idle phase only
bBypassRun := (_ePhase = E_DL_FbsPhase.eCloseBypass) OR (_ePhase = E_DL_FbsPhase.eRunDurance) OR (_ePhase = E_DL_FbsPhase.eStable); // 旁通命令：三旁通相派生 / the bypass command, derived in the three bypass phases
bBothOff := (NOT bVfdRun) AND (NOT bBypassRun); // 双断指示派生 / the both off indicator derived
nRetry := _nRetry; // 重试计数出口 / the retry count outlet

// 段 7｜统一出口 / segment 7, the unified outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_FbsFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
