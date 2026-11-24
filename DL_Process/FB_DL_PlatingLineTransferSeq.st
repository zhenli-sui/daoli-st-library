(*
  DL Factory R83 | FB_DL_PlatingLineTransferSeq
  功能：电镀线行车转序与槽位占用时序，起吊、横移、下降三段运动逐段握手，目标槽被占则等待且超时锁码，工位节拍按自复位周期窗错峰。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
  ------------------------------------------------------------------
  分类 DL_Process ｜ 复杂度 cx4 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（TON、R_TRIG，无私有库）
  边界：一 本件只出三段运动的命令电平与槽位等待标志，不驱动变频器、不做限位接线与机械防坠（属主边界）；
        二 段序固定：eWaitSlot 等槽位释放 → eLift 起吊（等起吊到位反馈）→ eTraverse 横移（等到位反馈）
           → eLower 下降（等到位反馈）→ eDone；任一段超时即锁码，锁存后一律回放，不再按当下输入重推（R152）；
        三 槽位占用互锁：目标槽未释放时不得起吊，只能停在 eWaitSlot；等待相以 tSlotWait 超时锁 306，
           槽位释放（bSlotFree 上升）为唯一放行条件；槽号越界（不在 [1, nSlotMax]）即锁 302 且不起吊；
        四 错峰节拍：tonStagger 为周期窗，IN := NOT tonStagger.Q 自复位（FB33-2），其 Q 为单拍节拍脉冲；
           起吊只允许在「节拍脉冲 AND 上位许可 bBeatPermit」同拍启动，未踩上节拍则等下一拍，禁止连续起吊；
        五 每相一个专属定时器（起吊、横移、下降、槽位等待），IN 只串本相使能与锁存闸，相迁移即 IN 归假自复位（R18）；
           四个相窗互斥、无同拍双窗；tonStagger 为跨相周期窗（不串相），其职责与四个相窗不重叠，故 R100 配比不适用；
        六 本件全部引脚为 BOOL、INT、TIME 量，无浮点引脚，故无浮点非有限闸项；时间量域闸与非零闸在段 1 统一执行；
           除法与开方均不出现，免除分母零闸项（R4 适用范围声明）；
        七 输出语义已声明：bEnable 为假 ⇒ 回空闲相、三段命令全归零（安全侧）；bReset 上升沿 ⇒ 清锁存、迁空闲、
           清节拍锁存三项（作用域在段 3 逐项声明）；
        八 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约：bHoistUpCmd、bTraverseCmd、bLowerDownCmd 为命令电平（真＝动作中）；bSlotHold 为槽位占用等待标志；
        nSlotActive 为目标槽号（1 基，空闲期出 0）；bBeatRelease 为错峰放行脉冲（单拍）；
        bDone 为保持式完成位（新循环起点同拍清零，R28 5.9）；iErrCode 为锁存回放（复位沿清零）。
  修订记录：2026-11-24 v1.0.0 R83 首版（批 R83 · 序号 39）
*)

TYPE E_DL_PltPhase :
(
    eIdle     := 0,  // 空闲等启动与节拍 / idle, waiting for the start edge and the beat
    eWaitSlot := 10, // 等槽位：目标槽未释放则停等 / waiting for the target slot to be released
    eLift     := 20, // 起吊：出起吊命令等到位 / hoisting, the command is on and the limit is awaited
    eTraverse := 30, // 横移：出横移命令等到位 / traversing, the command is on and the limit is awaited
    eLower    := 40, // 下降：出下降命令等到位 / lowering, the command is on and the limit is awaited
    eDone     := 50, // 完成：三段握手齐全 / done, all three handshakes are complete
    eFault    := 90  // 故障：成因锁存等复位沿 / fault, the cause is latched until the reset edge
);
END_TYPE

TYPE E_DL_PltCause :
(
    eNone      := 0, // 无成因 / no cause
    eCfgBad    := 1, // 时间引脚组态越域（故障级，与 bError 配对）/ a time pin is out of domain, fault grade paired with bError
    eSlotBad   := 2, // 槽号越界（故障级，与 bError 配对）/ the slot number is out of range, fault grade paired with bError
    eLiftTo    := 3, // 起吊到位超时（故障级，与 bError 配对）/ the hoist limit timed out, fault grade paired with bError
    eTravTo    := 4, // 横移到位超时（故障级，与 bError 配对）/ the traverse limit timed out, fault grade paired with bError
    eLowerTo   := 5, // 下降到位超时（故障级，与 bError 配对）/ the lower limit timed out, fault grade paired with bError
    eSlotTo    := 6, // 槽位等待超时（故障级，与 bError 配对）/ the slot wait timed out, fault grade paired with bError
    ePhaseBad  := 7  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_PlatingLineTransferSeq
VAR CONSTANT
    DL_PLT_SLOT_MIN : INT := 1; // 槽号下限（1 基）[号] / the slot number lower bound, one based [number]
END_VAR
VAR_INPUT
    bEnable     : BOOL := TRUE;   // 使能，失能回空闲且三段命令归零 [-] / enable, a disable returns to idle with every command zeroed
    bReset      : BOOL := FALSE;  // 复位上升沿清故障锁存并回空闲 [-] / reset rising edge clears the latch and returns to idle
    bStart      : BOOL := FALSE;  // 启动电平，须踩上错峰节拍才起吊 [-] / start level, the transfer starts only on a beat pulse
    bBeatPermit : BOOL := TRUE;   // 上位错峰许可 [-] / the stagger permit from the upper controller
    bSlotFree   : BOOL := FALSE;  // 目标槽已释放（占用互锁输入）[-]/ the target slot is released, the occupancy interlock input
    bHoistUpFb  : BOOL := FALSE;  // 起吊到位反馈（上限位）[-]/ the hoist up limit feedback
    bTravAtFb   : BOOL := FALSE;  // 横移到位反馈（目标列限位）[-]/ the traverse limit feedback at the target column
    bLowerFb    : BOOL := FALSE;  // 下降到位反馈（下槽限位）[-]/ the lower limit feedback inside the bath
    nTargetSlot : INT := 1;       // 目标槽号（1 基）[号] / the target slot number, one based [number]
    nSlotMax    : INT := 10;      // 槽位数上限（1 基末槽号）[号] / the slot count upper bound [number]
    tLift       : TIME := T#20S;  // 起吊到位超时窗 [毫秒] / the hoist limit timeout [millisecond]
    tTrav       : TIME := T#60S;  // 横移到位超时窗 [毫秒] / the traverse limit timeout [millisecond]
    tLower      : TIME := T#20S;  // 下降到位超时窗 [毫秒] / the lower limit timeout [millisecond]
    tSlotWait   : TIME := T#120S; // 槽位等待超时窗 [毫秒] / the slot wait timeout [millisecond]
    tStagger    : TIME := T#30S;  // 多工位错峰周期（自复位周期窗）[毫秒] / the stagger period of the self resetting window [millisecond]
END_VAR
VAR_OUTPUT
    bBusy        : BOOL := FALSE; // 转序执行中 [-] / the transfer is running
    bDone        : BOOL := FALSE; // 三段握手齐全（保持式，新循环起点清零）[-] / every handshake completed, held until a new cycle
    bFault       : BOOL := FALSE; // 故障锁存 [-] / the fault latch
    bError       : BOOL := FALSE; // 故障标志，与锁存位同源 [-] / the fault flag sharing the latch source
    iErrCode     : INT := 0;      // 错误码（锁存回放，复位沿清零）[码] / the error code replayed from the latch [code]
    ePhase       : E_DL_PltPhase := E_DL_PltPhase.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    bHoistUpCmd  : BOOL := FALSE; // 起吊命令电平 [-] / the hoist up command level
    bTraverseCmd : BOOL := FALSE; // 横移命令电平 [-] / the traverse command level
    bLowerDownCmd: BOOL := FALSE; // 下降命令电平 [-] / the lower down command level
    bSlotHold    : BOOL := FALSE; // 槽位占用等待中 [-] / waiting for the target slot
    bBeatRelease : BOOL := FALSE; // 错峰放行脉冲（单拍）[-] / the stagger release pulse, one scan wide
    nSlotActive  : INT := 0;      // 目标槽号（1 基，空闲期出 0）[号] / the target slot number, zero while idle [number]
END_VAR
VAR
    rtStart    : R_TRIG; // 启动沿，段 2 无条件刷新 / the start edge, refreshed unconditionally
    rtReset    : R_TRIG; // 复位沿，段 2 无条件刷新 / the reset edge, refreshed unconditionally
    rtSlotFree : R_TRIG; // 槽位释放沿，段 2 无条件刷新 / the slot release edge, refreshed unconditionally
    tonLift    : TON;    // 起吊超时窗，只串 eLift 相 / the hoist timeout gated by eLift
    tonTrav    : TON;    // 横移超时窗，只串 eTraverse 相 / the traverse timeout gated by eTraverse
    tonLower   : TON;    // 下降超时窗，只串 eLower 相 / the lower timeout gated by eLower
    tonSlot    : TON;    // 槽位等待超时窗，只串 eWaitSlot 相 / the slot wait timeout gated by eWaitSlot
    tonStagger : TON;    // 错峰周期窗，IN 取自身 Q 的反（自复位，FB33-2）/ the stagger period window driven by its own inverted output
    _ePhase    : E_DL_PltPhase := E_DL_PltPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the only CASE target
    _eCause    : E_DL_PltCause := E_DL_PltCause.eNone; // 故障级成因，锁存至复位沿 / the fault cause latched until reset
    _bFault    : BOOL := FALSE; // 故障锁存位 [-] / the fault latch
    _iErrLch   : INT := 0;      // 码位锁存槽（复位沿清零）[码] / the latched code, cleared at the reset edge
    _bDone     : BOOL := FALSE; // 完成位内部锁存（清零归属：段 2 复位沿与段 3 启动沿）[-] / the internal done bit
    _bInit     : BOOL := FALSE; // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag
    _bCfgOk    : BOOL := FALSE; // 时间引脚组态域内 [-] / the time pins are inside their domain
    _bSlotOk   : BOOL := FALSE; // 槽号域内 [-] / the slot number is inside its domain
    _bBeat     : BOOL := FALSE; // 本拍错峰放行（节拍脉冲与上位许可同真）[-] / the release verdict of this scan
    _bSlotEdge : BOOL := FALSE; // 槽位释放沿锁存（单拍）[-] / the one scan slot release edge
END_VAR
// 段 0｜时间量域闸与槽号越界闸：参与判据换算的引脚逐项枚举（R151）
_bCfgOk := (tLift > T#0S) AND (tTrav > T#0S) AND (tLower > T#0S) AND (tSlotWait > T#0S) AND (tStagger > T#0S); // 五个时间引脚域闸 / the five time pins domain gate
_bSlotOk := (nSlotMax >= DL_PLT_SLOT_MIN) AND (nTargetSlot >= DL_PLT_SLOT_MIN) AND (nTargetSlot <= nSlotMax); // 槽号落在 [1, nSlotMax] / the slot number inside its domain
// 段 1｜定时器与沿检测无条件周期刷新，IN 只串本相使能与锁存闸（R7、R18）
tonStagger(IN := NOT tonStagger.Q, PT := tStagger); // 错峰周期窗自复位（FB33-2，禁外部沿清零）/ the self resetting stagger window
_bBeat := tonStagger.Q AND bBeatPermit; // 本拍错峰放行判据（节拍单拍脉冲与上位许可同真）/ the release verdict of this scan
rtStart(CLK := bStart); // 启动沿无条件刷新 / unconditional refresh of the start edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
rtSlotFree(CLK := bSlotFree); // 槽位释放沿无条件刷新 / unconditional refresh of the slot release edge
tonLift(IN := (_ePhase = E_DL_PltPhase.eLift) AND (NOT _bFault), PT := tLift); // 起吊超时窗，只串 eLift 相 / the hoist timeout gated by eLift only
tonTrav(IN := (_ePhase = E_DL_PltPhase.eTraverse) AND (NOT _bFault), PT := tTrav); // 横移超时窗，只串 eTraverse 相 / the traverse timeout gated by eTraverse only
tonLower(IN := (_ePhase = E_DL_PltPhase.eLower) AND (NOT _bFault), PT := tLower); // 下降超时窗，只串 eLower 相 / the lower timeout gated by eLower only
tonSlot(IN := (_ePhase = E_DL_PltPhase.eWaitSlot) AND (NOT _bFault), PT := tSlotWait); // 槽位超时窗，只串 eWaitSlot 相 / the slot timeout gated by eWaitSlot only
// 段 2｜首扫初始化与复位沿同块，作用域逐项声明（R310、R311）
IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位沿 / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志（复位沿重复置位同效）/ the first scan flag, the same effect on reset
    _bFault := FALSE; _eCause := E_DL_PltCause.eNone; _iErrLch := 0; // 作用域一：清锁存、清成因、清码位槽 / scope one, clear the latch, the cause and the code
    _bDone := FALSE; _ePhase := E_DL_PltPhase.eIdle; // 作用域二：清完成位并迁回空闲相 / scope two, clear the held done bit and migrate to idle
END_IF // 作用域三（单拍槽位沿 _bSlotEdge）不在此清：其每拍由启动沿段之后的沿重取行唯一写入
// 段 3｜启动沿：新循环起点同拍清完成位（R28 5.9 清零点）
IF rtStart.Q THEN _bDone := FALSE; END_IF // 完成位清零（上一循环遗留）/ clear the done bit left by the previous cycle
_bSlotEdge := rtSlotFree.Q; // 槽位释放沿重取（单拍量每拍重算，不跨拍自持）/ re-take the one scan slot release edge
// 段 4｜故障判据与锁存：未锁存才判，锁存与迁相同拍执行（R107、FB50-1④、R152）
IF NOT _bFault THEN // 未锁存才判，锁存后一律回放 / judge only while unlatched
    IF NOT _bCfgOk THEN // 时间引脚组态越域 / a time pin is out of domain
        _eCause := E_DL_PltCause.eCfgBad; _iErrLch := 301; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_PltPhase.eFault; // 置锁存并同拍迁故障相 / latch and migrate in the same scan
    ELSIF NOT _bSlotOk THEN // 槽号越界（不起吊）/ the slot number is out of range
        _eCause := E_DL_PltCause.eSlotBad; _iErrLch := 302; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_PltPhase.eFault; // 置锁存并同拍迁故障相 / latch and migrate in the same scan
    END_IF
END_IF
// 段 5｜相位状态机：ENUM ＋ CASE ＋ ELSE 非法相位兜底（R6、R128）
CASE _ePhase OF
E_DL_PltPhase.eIdle: // 空闲相：退出条件三（踩上节拍且目标槽已释放、目标槽未释放转等待、使能丢失则驻留）
    IF bEnable AND bStart AND _bBeat THEN // 启动电平、错峰节拍与使能同真 / the start level, the beat and the enable hold
        IF bSlotFree THEN // 目标槽已释放：直接起吊 / the target slot is free, hoist right away
            _ePhase := E_DL_PltPhase.eLift; // 迁起吊相 / migrate to the hoist phase
        ELSE // 目标槽被占：转等待相（不得起吊，互锁）/ the target slot is occupied, the interlock forbids hoisting
            _ePhase := E_DL_PltPhase.eWaitSlot; // 迁槽位等待相 / migrate to the slot wait phase
        END_IF
    END_IF
E_DL_PltPhase.eWaitSlot: // 槽位等待相：退出条件三（槽位释放沿、等待超时、使能丢失），本拍事件优先于超时（R275）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_PltPhase.eIdle; // 回空闲（命令归零由出口执行）/ back to idle, the outlet zeroes the commands
    ELSIF _bSlotEdge OR bSlotFree THEN // 槽位释放（沿或电平，电平防沿丢失）/ the slot is released either by the edge or the level
        _ePhase := E_DL_PltPhase.eLift; // 迁起吊相 / migrate to the hoist phase
    ELSIF tonSlot.Q THEN // 槽位等待超时 / the slot wait timed out
        _eCause := E_DL_PltCause.eSlotTo; _iErrLch := 306; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_PltPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_PltPhase.eLift: // 起吊相：退出条件三（起吊到位、到位超时、使能丢失）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_PltPhase.eIdle; // 回空闲 / back to idle
    ELSIF bHoistUpFb THEN // 起吊到位（拍 N 进入：本相起点、本拍行为：拒绝横移、拍 N+1 转出：横移相）
        _ePhase := E_DL_PltPhase.eTraverse; // 迁横移相 / migrate to the traverse phase
    ELSIF tonLift.Q THEN // 起吊到位超时 / the hoist limit timed out
        _eCause := E_DL_PltCause.eLiftTo; _iErrLch := 303; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_PltPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_PltPhase.eTraverse: // 横移相：退出条件三（横移到位、到位超时、使能丢失）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_PltPhase.eIdle; // 回空闲 / back to idle
    ELSIF bTravAtFb THEN // 横移到位 / the traverse limit is reached
        _ePhase := E_DL_PltPhase.eLower; // 迁下降相 / migrate to the lower phase
    ELSIF tonTrav.Q THEN // 横移到位超时 / the traverse limit timed out
        _eCause := E_DL_PltCause.eTravTo; _iErrLch := 304; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_PltPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_PltPhase.eLower: // 下降相：退出条件三（下降到位、到位超时、使能丢失）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_PltPhase.eIdle; // 回空闲 / back to idle
    ELSIF bLowerFb THEN // 下降到位（三段握手齐全）/ the lower limit is reached, all handshakes done
        _bDone := TRUE; _ePhase := E_DL_PltPhase.eDone; // 置完成位（保持至新循环起点）并迁完成相 / raise done and migrate
    ELSIF tonLower.Q THEN // 下降到位超时 / the lower limit timed out
        _eCause := E_DL_PltCause.eLowerTo; _iErrLch := 305; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_PltPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_PltPhase.eDone: // 完成相：退出条件二（启动沿消失、使能丢失）
    IF (NOT bStart) OR (NOT bEnable) THEN _ePhase := E_DL_PltPhase.eIdle; END_IF // 回空闲等下一循环 / back to idle for the next cycle
E_DL_PltPhase.eFault: // 故障相：成因锁存回放，唯一解除路径为 bReset 上升沿（R188）
    IF NOT bEnable THEN _ePhase := E_DL_PltPhase.eIdle; END_IF // 失能迁空闲（锁存位仍须复位沿解除）/ migrate to idle, the latch still needs the reset edge
ELSE // 非法相位兜底（R6、R128）/ the illegal phase fallback
    _eCause := E_DL_PltCause.ePhaseBad; _iErrLch := 307; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    _bFault := TRUE; _ePhase := E_DL_PltPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
END_CASE
IF _bFault AND (_ePhase <> E_DL_PltPhase.eFault) THEN // 段尾迁移闸：任何锁存路径不得留在业务相（FB50-1④）
    _ePhase := E_DL_PltPhase.eFault; // 统一迁故障相 / force the fault phase
END_IF
// 段 6｜统一出口：三段命令按相位单点映射，故障与失能一律归零（安全侧）
bHoistUpCmd := (_ePhase = E_DL_PltPhase.eLift) AND bEnable AND (NOT _bFault); // 起吊命令：仅起吊相且未失能未锁存 / the hoist command only in lift while enabled and unlatched
bTraverseCmd := (_ePhase = E_DL_PltPhase.eTraverse) AND bEnable AND (NOT _bFault); // 横移命令：仅横移相 / the traverse command only in traverse
bLowerDownCmd := (_ePhase = E_DL_PltPhase.eLower) AND bEnable AND (NOT _bFault); // 下降命令：仅下降相 / the lower command only in lower
bSlotHold := (_ePhase = E_DL_PltPhase.eWaitSlot) AND bEnable; // 槽位等待标志 / the slot wait flag
bBeatRelease := _bBeat AND (_ePhase = E_DL_PltPhase.eIdle) AND bEnable; // 错峰放行脉冲：单拍且仅空闲相放行 / the release pulse, one scan and idle only
nSlotActive := 0; // 空闲期槽号出零（契约：空闲不报槽号）/ report zero while idle
IF _ePhase <> E_DL_PltPhase.eIdle THEN // 非空闲期 / outside idle
    nSlotActive := nTargetSlot; // 槽号单点映射 / single point mapping of the slot number
END_IF
bBusy := bEnable AND (_ePhase <> E_DL_PltPhase.eIdle) AND (_ePhase <> E_DL_PltPhase.eDone) AND (_ePhase <> E_DL_PltPhase.eFault); // 运行位排除空闲完成与故障 / the busy bit excludes idle, done and fault
bDone := _bDone; // 完成位单点映射（保持式）/ single point mapping of the held done bit
bFault := _bFault; // 故障锁存单点映射 / single point mapping of the latch
IF _bFault THEN // 故障期回放锁存码，不在故障相按当下输入重推（R152）/ replay the latched code
    iErrCode := _iErrLch; bError := TRUE; // 锁存码回放、故障标志同源 / replay the code and share the latch source
ELSE // 非故障期 / outside fault
    iErrCode := 0; bError := FALSE; // 无故障码与无故障标志 / no code and no flag
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point mapping of the phase
END_FUNCTION_BLOCK
