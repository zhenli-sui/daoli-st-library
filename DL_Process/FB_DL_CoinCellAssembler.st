(*
  ==================================================================
  组件名 Component  : FB_DL_CoinCellAssembler
  分类   Category   : DL_Process
  版本   Version    : 1.0.1
  功能   Purpose    : 扣电组装工站模板（叠片 — 压紧 — 封口）。以 ENUM + CASE 相位机
                      编排七相：空闲 → 上料 → 叠片 → 压紧 → 封口 → 下料 → 完成；
                      每相输出本相命令并等本相就绪信号，各相独立超时（独立成因码，
                      R190 归因唯一）；压紧相另设压力上限保护，超限立即跳故障相。
                      完成相出单拍周期完成脉冲并累加周期计数。
  溯源   Origin     : 扣电组装（叠片 / 压紧 / 封口）为通用小电芯工站时序语义；本件为
                      clean-room 实现，仅借鉴来源分类与参数域组织（来源标签
                      roadmap-p2-coincell），道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / REAL 运算，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  同拍多窗说明（R100）：五个超时窗互斥 —— 每窗的 IN 均串「本相」闸，任一时刻只有一个
                      窗在计时，因此不存在同拍双窗配比约束；若后续改为并行工位，必须补
                      配比约束句后再改 IN 结构。
  边界 Boundary     :
                      一 本件只出工站级相命令与就绪判据，不驱动伺服 / 气缸本体（属主边界）；
                      二 每相命令只在对应相位为真，相外一律撤除（每拍预置撤除）；
                      三 五个超时件全部无条件周期刷新，IN 串相位闸与故障闸（禁分支内调用）；
                      四 压力上限保护独立成码，不与超时码合并（R190）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      五个命令出口为「相位派生电平」，相外恒假；
                      bCycleDone 为单拍脉冲（内部位置置位、统一出口映射后撤销）；
                      nCycleCnt 只在下料就绪那一拍递增，饱和到上限；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 4 · 序号 18）
    2026-11-20  v1.0.1  R56 返修（7.3）：删除死变量 _eCause（信息级成因全文件无任何
                        写入路径、恒为 eNone），段 7 出口简化为故障级成因锁存直映。
  ==================================================================
*)

TYPE E_DL_CcaPhase :
(
    eIdle   := 0,       // 空闲：等启动沿 / idle, waiting for the start edge
    eLoad   := 10,      // 上料：等上料就绪 / loading, waiting for the load ready signal
    eStack  := 20,      // 叠片：等叠片就绪 / stacking, waiting for the stack ready signal
    ePress  := 30,      // 压紧：等压紧就绪（含压力上限保护）/ pressing, waiting for the press ready signal with force protection
    eSeal   := 40,      // 封口：等封口就绪 / sealing, waiting for the seal ready signal
    eUnload := 50,      // 下料：等下料就绪 / unloading, waiting for the unload ready signal
    eDone   := 60,      // 完成：周期完成脉冲已出，驻留一拍以上 / done, the cycle pulse has been raised
    eFault  := 90       // 故障：成因锁存 / fault, the cause is latched
);
END_TYPE

TYPE E_DL_CcaCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：时间或力量程越域（故障级，与 bError 配对）/ illegal config, time or force range out of domain
    eLoadTo     := 2,   // 上料超时（故障级，与 bError 配对）/ load timeout, a fault paired with bError
    eStackTo    := 3,   // 叠片超时（故障级，与 bError 配对）/ stack timeout, a fault paired with bError
    ePressTo    := 4,   // 压紧超时（故障级，与 bError 配对）/ press timeout, a fault paired with bError
    eSealTo     := 5,   // 封口超时（故障级，与 bError 配对）/ seal timeout, a fault paired with bError
    eUnloadTo   := 6,   // 下料超时（故障级，与 bError 配对）/ unload timeout, a fault paired with bError
    eForceOver  := 7    // 压紧力越上限（故障级，与 bError 配对）/ press force above the ceiling, a fault paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoinCellAssembler
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时撤命令回空闲 [-] / enable, disabling withdraws the commands and returns to idle
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存并回空闲 [-] / reset rising edge clears the fault latch and returns to idle
    bStart       : BOOL := FALSE;            // 周期启动脉冲，上升沿受理 [-] / cycle start pulse, accepted on the rising edge
    bLoadOk      : BOOL := FALSE;            // 上料就绪（物料到位）[-] / load ready, the part is in place
    bStackOk     : BOOL := FALSE;            // 叠片就绪（叠片数达标）[-] / stack ready, the layer count is reached
    bPressOk     : BOOL := FALSE;            // 压紧就绪（压力到位）[-] / press ready, the force is reached
    bSealOk      : BOOL := FALSE;            // 封口就绪（封口完成信号）[-] / seal ready
    bUnloadOk    : BOOL := FALSE;            // 下料就绪（物料已取出）[-] / unload ready, the part was removed
    fPressForceN : REAL := 0.0;              // 压紧力实测 [牛顿] / measured press force [newton]
    fPressMaxN   : REAL := 5000.0;           // 压紧力上限 [牛顿]，域 大于零 / press force ceiling [newton], domain above zero
    tLoadTo      : TIME := T#15S;            // 上料超时 [毫秒]，域 大于零 / load timeout [millisecond], domain above zero
    tStackTo     : TIME := T#60S;            // 叠片超时 [毫秒]，域 大于零 / stack timeout [millisecond], domain above zero
    tPressTo     : TIME := T#30S;            // 压紧超时 [毫秒]，域 大于零 / press timeout [millisecond], domain above zero
    tSealTo      : TIME := T#30S;            // 封口超时 [毫秒]，域 大于零 / seal timeout [millisecond], domain above zero
    tUnloadTo    : TIME := T#15S;            // 下料超时 [毫秒]，域 大于零 / unload timeout [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    bLoadCmd     : BOOL := FALSE;            // 上料相命令 [-] / load phase command
    bStackCmd    : BOOL := FALSE;            // 叠片相命令 [-] / stack phase command
    bPressCmd    : BOOL := FALSE;            // 压紧相命令 [-] / press phase command
    bSealCmd     : BOOL := FALSE;            // 封口相命令 [-] / seal phase command
    bUnloadCmd   : BOOL := FALSE;            // 下料相命令 [-] / unload phase command
    bCycleDone   : BOOL := FALSE;            // 周期完成单拍脉冲 [-] / cycle done single-shot pulse
    bBusy        : BOOL := FALSE;            // 工站忙（非空闲非故障）[-] / station busy, neither idle nor faulted
    nCycleCnt    : UDINT := 0;               // 周期完成计数（饱和到上限）[次] / completed cycle count, saturated [cycle]
    ePhase       : E_DL_CcaPhase := E_DL_CcaPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eCause       : E_DL_CcaCause := E_DL_CcaCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStart      : R_TRIG;                   // 启动沿检测，段 0 无条件刷新 / start edge detector, refreshed unconditionally in segment zero
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonLoad      : TON;                      // 上料超时，段 0 无条件刷新 / load timeout, refreshed unconditionally in segment zero
    tonStack     : TON;                      // 叠片超时，段 0 无条件刷新 / stack timeout, refreshed unconditionally in segment zero
    tonPress     : TON;                      // 压紧超时，段 0 无条件刷新 / press timeout, refreshed unconditionally in segment zero
    tonSeal      : TON;                      // 封口超时，段 0 无条件刷新 / seal timeout, refreshed unconditionally in segment zero
    tonUnload    : TON;                      // 下料超时，段 0 无条件刷新 / unload timeout, refreshed unconditionally in segment zero
    _ePhase      : E_DL_CcaPhase := E_DL_CcaPhase.eIdle;  // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaultCause : E_DL_CcaCause := E_DL_CcaCause.eNone;  // 故障级成因，锁存至复位沿（本件全部成因均为故障级，信息级死变量 _eCause 已于 R56 删除）/ fault cause, latched until the reset edge, every cause here is fault grade
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bDoneInt    : BOOL := FALSE;            // 周期完成脉冲内部位，统一出口映射 / internal cycle done bit, mapped at the unified outlet
    _bForceOk    : BOOL := FALSE;            // 压紧力域闸通过 [-] / press force domain gate passed
    _nCycle      : UDINT := 0;               // 周期计数工作值 [次] / cycle count working value [cycle]
END_VAR
VAR CONSTANT
    DL_CCA_FORCE_MAX : REAL := 1.0E7;        // 压紧力量级上限 [牛顿] / press force magnitude ceiling [newton]
    DL_CCA_CYCLE_MAX : UDINT := 2000000000;  // 周期计数饱和上限（常量在 DINT 可表范围内）[次] / cycle count saturation ceiling, the constant fits in DINT
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与故障闸（R212）/ segment 0, unconditional refresh with phase and fault gates on IN only
rtStart(CLK := bStart); // 启动沿无条件刷新 / unconditional refresh of the start edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonLoad(IN := (_ePhase = E_DL_CcaPhase.eLoad) AND (NOT _bFault), PT := tLoadTo); // 上料超时 / load timeout
tonStack(IN := (_ePhase = E_DL_CcaPhase.eStack) AND (NOT _bFault), PT := tStackTo); // 叠片超时 / stack timeout
tonPress(IN := (_ePhase = E_DL_CcaPhase.ePress) AND (NOT _bFault), PT := tPressTo); // 压紧超时 / press timeout
tonSeal(IN := (_ePhase = E_DL_CcaPhase.eSeal) AND (NOT _bFault), PT := tSealTo); // 封口超时 / seal timeout
tonUnload(IN := (_ePhase = E_DL_CcaPhase.eUnload) AND (NOT _bFault), PT := tUnloadTo); // 下料超时 / unload timeout

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_CcaPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaultCause := E_DL_CcaCause.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nCycle := 0; // 周期计数清零 / clear the cycle count
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清脉冲内部位（计数不清，属产量资产）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_CcaCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_CcaPhase.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _bDoneInt := FALSE; // 作用域二：清周期完成脉冲内部位 / scope two, clear the internal cycle done bit
END_IF

// 段 3｜组态域闸（R151 全覆盖）：五个时间引脚与力量程 / segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (tLoadTo <= T#0S) OR (tStackTo <= T#0S) OR (tPressTo <= T#0S) OR (tSealTo <= T#0S) OR (tUnloadTo <= T#0S) THEN // 时间引脚非正 / a time pin is not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fPressMaxN <= 0.0) OR (fPressMaxN <> fPressMaxN) OR (fPressMaxN > DL_CCA_FORCE_MAX) THEN // 力量程越域 / the force range is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_CcaCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 4｜命令预置与压紧力闸：命令为相位派生电平，每拍先撤除 / segment 4, command preset and press force gate
bLoadCmd := FALSE; // 上料命令预置撤除 / preset the load command withdrawn
bStackCmd := FALSE; // 叠片命令预置撤除 / preset the stack command withdrawn
bPressCmd := FALSE; // 压紧命令预置撤除 / preset the press command withdrawn
bSealCmd := FALSE; // 封口命令预置撤除 / preset the seal command withdrawn
bUnloadCmd := FALSE; // 下料命令预置撤除 / preset the unload command withdrawn
_bForceOk := (fPressForceN = fPressForceN) AND ((fPressForceN - fPressForceN) = (fPressForceN - fPressForceN)) AND (fPressForceN <= fPressMaxN); // 压紧力有限且不越上限 / the press force is finite and within the ceiling

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, phase machine with an ELSE fallback for illegal phases
CASE _ePhase OF
E_DL_CcaPhase.eIdle: // 空闲相：等启动沿 / idle, waiting for the start edge
    IF rtStart.Q AND bEnable AND (NOT _bFault) THEN // 启动沿且使能无故障 / start edge while enabled and unfaulted
        _ePhase := E_DL_CcaPhase.eLoad; // 迁上料相 / migrate to the load phase
    END_IF

E_DL_CcaPhase.eLoad: // 上料相：命令自锁于本相 / load phase, the command lives inside this phase
    bLoadCmd := TRUE; // 出上料命令 / raise the load command
    IF bLoadOk THEN // 上料就绪 / load ready
        _ePhase := E_DL_CcaPhase.eStack; // 迁叠片相 / migrate to the stack phase
    ELSIF tonLoad.Q THEN // 上料超时 / load timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_CcaCause.eLoadTo; // 故障级成因（独立码，R45 配对 bError）/ independent fault code paired with bError
        _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CcaPhase.eStack: // 叠片相 / stack phase
    bStackCmd := TRUE; // 出叠片命令 / raise the stack command
    IF bStackOk THEN // 叠片就绪 / stack ready
        _ePhase := E_DL_CcaPhase.ePress; // 迁压紧相 / migrate to the press phase
    ELSIF tonStack.Q THEN // 叠片超时 / stack timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_CcaCause.eStackTo; // 故障级成因（独立码）/ independent fault code
        _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CcaPhase.ePress: // 压紧相：命令 + 压力上限保护双判 / press phase with force protection
    bPressCmd := TRUE; // 出压紧命令 / raise the press command
    IF NOT _bForceOk THEN // 压紧力越上限或非有限 / the force is above the ceiling or non-finite
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_CcaCause.eForceOver; // 故障级成因（独立码，不与超时合并）/ independent fault code, never merged with a timeout
        _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF bPressOk THEN // 压紧就绪 / press ready
        _ePhase := E_DL_CcaPhase.eSeal; // 迁封口相 / migrate to the seal phase
    ELSIF tonPress.Q THEN // 压紧超时 / press timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_CcaCause.ePressTo; // 故障级成因（独立码）/ independent fault code
        _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CcaPhase.eSeal: // 封口相 / seal phase
    bSealCmd := TRUE; // 出封口命令 / raise the seal command
    IF bSealOk THEN // 封口就绪 / seal ready
        _ePhase := E_DL_CcaPhase.eUnload; // 迁下料相 / migrate to the unload phase
    ELSIF tonSeal.Q THEN // 封口超时 / seal timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_CcaCause.eSealTo; // 故障级成因（独立码）/ independent fault code
        _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CcaPhase.eUnload: // 下料相 / unload phase
    bUnloadCmd := TRUE; // 出下料命令 / raise the unload command
    IF bUnloadOk THEN // 下料就绪 / unload ready
        IF _nCycle < DL_CCA_CYCLE_MAX THEN // 计数未达饱和上限 / below the saturation ceiling
            _nCycle := _nCycle + 1; // 周期计数递增 / increment the cycle count
        END_IF
        _bDoneInt := TRUE; // 周期完成脉冲内部位置位（统一出口映射，R187）/ raise the internal cycle done bit, mapped at the unified outlet
        _ePhase := E_DL_CcaPhase.eDone; // 迁完成相 / migrate to the done phase
    ELSIF tonUnload.Q THEN // 下料超时 / unload timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_CcaCause.eUnloadTo; // 故障级成因（独立码）/ independent fault code
        _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CcaPhase.eDone: // 完成相：驻留，等复位或新启动 / done phase, held until reset or a new start
    IF rtStart.Q AND bEnable THEN // 新启动沿 / a new start edge
        _ePhase := E_DL_CcaPhase.eLoad; // 重启上料相 / restart from the load phase
    END_IF

E_DL_CcaPhase.eFault: // 故障相：全撤命令，等复位沿 / fault phase with all commands withdrawn
    bLoadCmd := FALSE; // 撤上料命令 / withdraw the load command
    bStackCmd := FALSE; // 撤叠片命令 / withdraw the stack command
    bPressCmd := FALSE; // 撤压紧命令 / withdraw the press command
    bSealCmd := FALSE; // 撤封口命令 / withdraw the seal command
    bUnloadCmd := FALSE; // 撤下料命令 / withdraw the unload command

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_CcaCause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
    _ePhase := E_DL_CcaPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜失能与故障最终否决：命令一律受故障锁存与失能否决 / segment 6, final veto by the fault latch and the enable
IF _bFault OR (NOT bEnable) THEN // 故障锁存或失能 / fault latched or disabled
    bLoadCmd := FALSE; // 撤上料命令 / withdraw the load command
    bStackCmd := FALSE; // 撤叠片命令 / withdraw the stack command
    bPressCmd := FALSE; // 撤压紧命令 / withdraw the press command
    bSealCmd := FALSE; // 撤封口命令 / withdraw the seal command
    bUnloadCmd := FALSE; // 撤下料命令 / withdraw the unload command
    _bDoneInt := FALSE; // 撤周期完成脉冲内部位 / withdraw the internal cycle done bit
END_IF
IF NOT bEnable THEN // 失能 / disabled
    _ePhase := E_DL_CcaPhase.eIdle; // 回空闲相 / return to idle
END_IF

// 段 7｜统一出口 / segment 7, unified outlet
bCycleDone := _bDoneInt; // 周期完成脉冲映射本拍值 / map the cycle done pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
nCycleCnt := _nCycle; // 周期计数出口 / cycle count outlet
bBusy := (_ePhase <> E_DL_CcaPhase.eIdle) AND (_ePhase <> E_DL_CcaPhase.eFault); // 忙指示（挂相位状态量）/ busy indicator derived from the phase state
ePhase := _ePhase; // 相位出口单点映射 / single-point phase outlet mapping
eCause := _eFaultCause; // 成因出口：全部成因均为故障级，锁存回放（R56 简化，原信息级死变量已删）/ the cause outlet, every cause is fault grade and replayed from the latch
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
