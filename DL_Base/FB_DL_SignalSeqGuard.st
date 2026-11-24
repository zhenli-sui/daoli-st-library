(*
  ==================================================================
  组件名 Component  : FB_DL_SignalSeqGuard
  分类   Category   : DL_Base
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 多路信号到达顺序守卫。N = 4 路布尔信号按期望序（ENUM 四选一：
                      升序 1→2→3→4 / 降序 4→3→2→1 / 对 1→2 / 对 3→4）在 tWindow
                      内逐沿校验到达顺序；乱序即置 eFault = eOrderViolation 并锁存，
                      窗内未完成置 eWindowTimeout；正常序完成置 bSeqOk 单拍脉冲。
                      复位上升沿清全部锁存。同拍多沿按 1..4 固定序检查（确定性口径）。
  来源   Source     : t2-1-lgf-converter
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；到达顺序校验为通用
                      联锁语义，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / ARRAY，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做到达顺序校验，不产生任何输出命令（属主边界）；
                      二 eWait 类相（eRun）退出条件 ≥2 条：完成沿 / 超时 / 乱序 /
                         失能，四条并列（R98）；
                      三 序列表在组态相一次性落定，乱序判据只用序表与步进游标；
                      四 故障锁存解除路径 = bReset 上升沿（唯一路径，头注释声明，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      bSeqOk 为单拍脉冲（内部 _bOkInt 置位、统一出口映射后撤销，R187）；
                      eFault 为锁存回放；eModeBad 为模式枚举非法兜底（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 2 · 序号 7）
  ==================================================================
*)

TYPE E_DL_SsgMode :
(
    eAscending  := 0, // 升序：1→2→3→4 / ascending, one to four
    eDescending := 1, // 降序：4→3→2→1 / descending, four to one
    ePair12     := 2, // 对序：1→2 / pair order, one then two
    ePair34     := 3  // 对序：3→4 / pair order, three then four
);
END_TYPE

TYPE E_DL_SsgPhase :
(
    eIdle  := 0,  // 空闲：等待启动 / idle, waiting for the start
    eRun   := 10, // 校验中：逐沿核对到达顺序 / running, the arrivals are checked edge by edge
    eDone  := 20, // 完成：顺序通过，驻留一拍 / done, the order passed and the phase holds one scan
    eFault := 90  // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_SsgFault :
(
    eNone          := 0, // 无成因 / no cause
    eOrderViolation:= 1, // 到达顺序违例（故障级，与 bError 配对）/ the arrival order was violated, fault grade paired with bError
    eWindowTimeout := 2, // 时窗内未完成（故障级，与 bError 配对）/ the window expired without completion, fault grade paired with bError
    eModeBad       := 3, // 模式枚举非法（故障级，与 bError 配对）/ the mode enumeration is illegal, fault grade paired with bError
    ePhaseBad      := 4  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_SignalSeqGuard
VAR_INPUT
    bEnable   : BOOL := TRUE;    // 使能，失能时停校验回空闲 [-] / enable, the check stops when disabled
    bReset    : BOOL := FALSE;   // 复位上升沿清全部锁存 [-] / reset rising edge clears every latch
    bIn1      : BOOL := FALSE;   // 信号 1 [-] / signal one
    bIn2      : BOOL := FALSE;   // 信号 2 [-] / signal two
    bIn3      : BOOL := FALSE;   // 信号 3 [-] / signal three
    bIn4      : BOOL := FALSE;   // 信号 4 [-] / signal four
    eSeqMode  : E_DL_SsgMode := E_DL_SsgMode.eAscending; // 期望到达序 [枚举] / the expected arrival order [enum]
    tWindow   : TIME := T#2S;    // 到达顺序时窗 [毫秒]，域 大于零 / arrival order window [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    bSeqOk    : BOOL := FALSE; // 顺序通过单拍脉冲 [-] / the order passed single shot pulse
    nStep     : INT := 0;      // 已到位步数 [步] / the arrived step count [step]
    ePhase    : E_DL_SsgPhase := E_DL_SsgPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault    : E_DL_SsgFault := E_DL_SsgFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError    : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtIn1     : R_TRIG;  // 信号 1 沿检测，段 0 无条件刷新 / signal one edge, refreshed unconditionally in segment zero
    rtIn2     : R_TRIG;  // 信号 2 沿检测，段 0 无条件刷新 / signal two edge, refreshed unconditionally in segment zero
    rtIn3     : R_TRIG;  // 信号 3 沿检测，段 0 无条件刷新 / signal three edge, refreshed unconditionally in segment zero
    rtIn4     : R_TRIG;  // 信号 4 沿检测，段 0 无条件刷新 / signal four edge, refreshed unconditionally in segment zero
    rtReset   : R_TRIG;  // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonWindow : TON;     // 到达顺序时窗，段 0 无条件刷新 / arrival window timer, refreshed unconditionally in segment zero
    _ePhase   : E_DL_SsgPhase := E_DL_SsgPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC   : E_DL_SsgFault := E_DL_SsgFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault   : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit    : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bOkInt   : BOOL := FALSE; // 通过脉冲内部位，统一出口映射 / internal passed bit, mapped at the unified outlet
    _nStep    : INT := 0;      // 已到位步数 [步] / the arrived step count [step]
    _nSeqLen  : INT := 4;      // 序列长度（四序或两序）[步] / the sequence length, four or two steps
    _nSig     : INT := 0;      // 本拍到沿的信号号 [信号号] / the signal number that edged this scan
    _anOrder  : ARRAY[1..4] OF INT := [0, 0, 0, 0]; // 期望到达序表（0 = 空槽）[信号号] / the expected order table, zero is an empty slot
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸（FB50-1）/ segment 0, unconditional refresh, no instance call inside a branch
rtIn1(CLK := bIn1); // 信号 1 沿 / the signal one edge
rtIn2(CLK := bIn2); // 信号 2 沿 / the signal two edge
rtIn3(CLK := bIn3); // 信号 3 沿 / the signal three edge
rtIn4(CLK := bIn4); // 信号 4 沿 / the signal four edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonWindow(IN := (_ePhase = E_DL_SsgPhase.eRun) AND (NOT _bFault), PT := tWindow); // 到达顺序时窗，IN 串校验相闸与故障闸 / the arrival window with the phase and fault gates on IN

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_SsgPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaulC := E_DL_SsgFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nStep := 0; // 步数清零 / clear the step count
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清步数（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_SsgFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_SsgPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _nStep := 0; // 作用域三：清步数 / scope three, clear the step count
END_IF

// 段 3｜序表组态：按模式一次性落定，非法模式判故障 / segment 3, the order table settles per the mode, an illegal mode faults
CASE eSeqMode OF // 模式分派 / the mode dispatch
E_DL_SsgMode.eAscending: // 升序 / ascending
    _anOrder[1] := 1; // 第一位信号 1 / the first slot takes signal one
    _anOrder[2] := 2; // 第二位信号 2 / the second slot takes signal two
    _anOrder[3] := 3; // 第三位信号 3 / the third slot takes signal three
    _anOrder[4] := 4; // 第四位信号 4 / the fourth slot takes signal four
    _nSeqLen := 4; // 序列长度四 / the length is four
E_DL_SsgMode.eDescending: // 降序 / descending
    _anOrder[1] := 4; // 第一位信号 4 / the first slot takes signal four
    _anOrder[2] := 3; // 第二位信号 3 / the second slot takes signal three
    _anOrder[3] := 2; // 第三位信号 2 / the third slot takes signal two
    _anOrder[4] := 1; // 第四位信号 1 / the fourth slot takes signal one
    _nSeqLen := 4; // 序列长度四 / the length is four
E_DL_SsgMode.ePair12: // 对序 1→2 / pair one then two
    _anOrder[1] := 1; // 第一位信号 1 / the first slot takes signal one
    _anOrder[2] := 2; // 第二位信号 2 / the second slot takes signal two
    _anOrder[3] := 0; // 空槽 / an empty slot
    _anOrder[4] := 0; // 空槽 / an empty slot
    _nSeqLen := 2; // 序列长度二 / the length is two
E_DL_SsgMode.ePair34: // 对序 3→4 / pair three then four
    _anOrder[1] := 3; // 第一位信号 3 / the first slot takes signal three
    _anOrder[2] := 4; // 第二位信号 4 / the second slot takes signal four
    _anOrder[3] := 0; // 空槽 / an empty slot
    _anOrder[4] := 0; // 空槽 / an empty slot
    _nSeqLen := 2; // 序列长度二 / the length is two
ELSE // 非法模式兜底（R128）/ the illegal mode fallback
    IF (NOT _bFault) AND (_ePhase <> E_DL_SsgPhase.eFault) THEN // 未锁存才迁移（防同拍抹除）/ migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_SsgFault.eModeBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_SsgPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF
END_CASE

// 段 4｜本拍到沿信号号判定：同拍多沿按 1..4 固定序（确定性口径）/ segment 4, the edged signal number, multiple edges resolve in the fixed one to four order
_nSig := 0; // 信号号预置零 / preset the signal number to zero
IF rtIn1.Q THEN // 信号 1 到沿 / signal one edged
    _nSig := 1; // 记信号 1 / take signal one
ELSIF rtIn2.Q THEN // 信号 2 到沿 / signal two edged
    _nSig := 2; // 记信号 2 / take signal two
ELSIF rtIn3.Q THEN // 信号 3 到沿 / signal three edged
    _nSig := 3; // 记信号 3 / take signal three
ELSIF rtIn4.Q THEN // 信号 4 到沿 / signal four edged
    _nSig := 4; // 记信号 4 / take signal four
END_IF

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_SsgPhase.eIdle: // 空闲相：使能且无故障即起校验 / idle, the check starts when enabled and unfaulted
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _nStep := 0; // 步数清零 / clear the step count
        _ePhase := E_DL_SsgPhase.eRun; // 迁校验相 / migrate to the run phase
    END_IF

E_DL_SsgPhase.eRun: // 校验相：逐沿核对到达顺序（退出条件 ≥2：完成 / 超时 / 乱序 / 失能，R98）/ the run phase with at least two exit conditions
    nStep := _nStep; // 步数出口跟随 / the step outlet follows
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_SsgPhase.eIdle; // 回空闲相 / return to idle
    ELSIF tonWindow.Q THEN // 时窗耗尽未完成 / the window expired without completion
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_SsgFault.eWindowTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_SsgPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF _nSig > 0 THEN // 本拍有信号到沿 / a signal edged this scan
        IF _nSig = _anOrder[_nStep + 1] THEN // 与期望序位一致 / the arrival matches the expected slot
            _nStep := _nStep + 1; // 步数推进 / advance the step
            IF _nStep >= _nSeqLen THEN // 序列完成 / the sequence is complete
                _bOkInt := TRUE; // 通过脉冲内部位置位（统一出口映射，R187）/ raise the internal passed bit, mapped at the unified outlet
                _ePhase := E_DL_SsgPhase.eDone; // 迁完成相 / migrate to the done phase
            END_IF
        ELSE // 乱序 / an out of order arrival
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_SsgFault.eOrderViolation; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
            _ePhase := E_DL_SsgPhase.eFault; // 迁故障相 / migrate to the fault phase
        END_IF
    END_IF

E_DL_SsgPhase.eDone: // 完成相：脉冲已交付（拍 N 进入：序到位 / 本拍行为：脉冲映射 / 拍 N+1 转出：无条件回空闲，R80 三段）/ the done phase, the pulse was delivered
    _ePhase := E_DL_SsgPhase.eIdle; // 无条件回空闲相准备下一轮（失能态下同样回到空闲语义）/ back to idle for the next round unconditionally, the same idle semantics under a disable

E_DL_SsgPhase.eFault: // 故障相：成因锁存，等待复位沿 / the fault phase, the cause is latched until the reset edge
    nStep := _nStep; // 步数出口冻结保持 / the step outlet holds frozen

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_SsgFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_SsgPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜统一出口 / segment 6, the unified outlet
bSeqOk := _bOkInt; // 通过脉冲映射本拍值 / map the passed pulse for this scan
_bOkInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single scan width
nStep := _nStep; // 步数出口 / the step outlet
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
eFault := _eFaulC; // 成因出口锁存回放 / the cause outlet replayed from the latch
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
