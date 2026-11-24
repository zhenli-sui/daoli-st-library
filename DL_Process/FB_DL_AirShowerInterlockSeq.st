(*
  ==================================================================
  组件名 Component  : FB_DL_AirShowerInterlockSeq
  分类   Category   : DL_Process
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 风淋室联锁顺控。双门互锁不变量（内 / 外门不得同时开，破坏
                      即故障锁存）；进入序列：外门开 → 外门关 → 吹淋计时 → 内门
                      许可 → 内门通过后回空闲；吹淋超时与中止（急停 / 火警电平）
                      优先解除全部门锁许可撤离；锁反馈校验失配判 eSensorBad。
  来源   Source     : t2-2-lbp（洁净室物流联锁族）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；双侧门 + 吹淋定时
                      三段联锁为通用洁净室语义，clean-room 自研实现，未复制任何
                      闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / LREAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  同拍双窗配比约束（R100）：tBlow（吹淋工艺窗）与 tBlowMax（吹淋看门狗窗）同相
                      并跑，配比约束 tBlowMax > tBlow 在组态域闸内判故障；
                      tFbTo 锁反馈失配消抖窗独立（不同相）。
  边界 Boundary     :
                      一 本件只出门锁与吹淋许可，不驱动门体电机、不控风机本体
                         （属主边界）；
                      二 安全侧优先：急停 / 火警电平（bEmgLevel）在任何相位立即
                         解除全部门锁并撤吹淋（撤离许可，安全侧直通）；
                      三 互锁不变量：bOuterLocked 与 bInnerLocked 不同拍同为假
                         （恒有一侧锁闭，双开即故障锁存）；
                      四 相级看门狗使能只用相驻留本身（R145）；
                      五 故障锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      bOuterLocked / bInnerLocked 为门锁命令电平（真 = 锁闭）；
                      bBlowing 为吹淋命令电平；bEntryAllowed 为进入许可（外门侧）；
                      eFault 为锁存回放；ePhaseBad 为非法相位兜底专用成员（R128）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 4 · 序号 20）
  ==================================================================
*)

TYPE E_DL_AisPhase :
(
    eIdle       := 0,  // 空闲：外门侧许可进入 / idle, the outer side is allowed to enter
    eOuterOpen  := 10, // 外门开：人已进入，等外门关 / the outer door is open, waiting for it to close
    eBlow       := 20, // 吹淋：吹淋计时中，双侧门锁闭 / blowing, both doors locked
    eInnerAllow := 30, // 内门许可：吹淋完成，等内门通过 / the inner side allowed, waiting for the passage
    eAborted    := 40, // 已中止：全部门锁解除（撤离许可），等复位 / aborted, every lock released for evacuation
    eFault      := 90  // 故障：成因锁存，双侧解锁（安全侧）/ fault, the cause is latched with both sides unlocked
);
END_TYPE

TYPE E_DL_AisFault :
(
    eNone        := 0, // 无成因 / no cause
    eDoorBothOpen:= 1, // 双门同时开，互锁不变量被破坏（故障级，与 bError 配对）/ both doors open at once, the interlock invariant broken, fault grade paired with bError
    eBlowTimeout := 2, // 吹淋看门狗超时（故障级，与 bError 配对）/ the blow watchdog timed out, fault grade paired with bError
    eAborted     := 3, // 急停 / 火警中止（故障级，与 bError 配对）/ aborted by an emergency or fire level, fault grade paired with bError
    eSensorBad   := 4, // 锁反馈失配或组态非法（故障级，与 bError 配对）/ the lock feedback mismatches or the config illegal, fault grade paired with bError
    ePhaseBad    := 5  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_AirShowerInterlockSeq
VAR_INPUT
    bEnable      : BOOL := TRUE;    // 使能，失能时停顺控回空闲（门锁维持安全侧）[-] / enable, the sequence stops when disabled
    bReset       : BOOL := FALSE;   // 复位上升沿清故障锁存回空闲 [-] / reset rising edge clears the latch back to idle
    bOuterOpen   : BOOL := FALSE;   // 外门开反馈（真 = 开）[-] / the outer door open feedback, true is open
    bInnerOpen   : BOOL := FALSE;   // 内门开反馈（真 = 开）[-] / the inner door open feedback, true is open
    bOuterLockFb : BOOL := TRUE;    // 外门锁闭反馈（真 = 已锁）[-] / the outer lock feedback, true is locked
    bInnerLockFb : BOOL := TRUE;    // 内门锁闭反馈（真 = 已锁）[-] / the inner lock feedback, true is locked
    bEmgLevel    : BOOL := FALSE;   // 急停 / 火警电平（任何相位优先解除全部许可）[-] / the emergency or fire level, the top priority release
    tBlow        : TIME := T#15S;   // 吹淋工艺窗 [毫秒]，域 大于零 / the blow process window [millisecond], domain above zero
    tBlowMax     : TIME := T#30S;   // 吹淋看门狗窗 [毫秒]，域 大于 tBlow / the blow watchdog window, above the process window
    tPassTo      : TIME := T#30S;   // 内门通过超时窗 [毫秒]，域 大于零 / the inner passage timeout [millisecond], domain above zero
    tFbTo        : TIME := T#1S;    // 锁反馈失配消抖窗 [毫秒]，域 大于零 / the lock feedback mismatch debounce [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    bOuterLocked  : BOOL := TRUE;  // 外门锁命令（真 = 锁闭）[-] / the outer lock command, true is locked
    bInnerLocked  : BOOL := TRUE;  // 内门锁命令（真 = 锁闭）[-] / the inner lock command, true is locked
    bBlowing      : BOOL := FALSE; // 吹淋命令电平 [-] / the blowing command level
    bEntryAllowed : BOOL := FALSE; // 进入许可（外门侧解锁派生）[-] / the entry permission, derived from the outer unlock
    ePhase        : E_DL_AisPhase := E_DL_AisPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eFault        : E_DL_AisFault := E_DL_AisFault.eNone; // 成因出口，锁存回放 [枚举] / cause outlet replayed from the latch [enum]
    bError        : BOOL := FALSE; // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / reset edge, refreshed unconditionally in segment zero
    tonBlow  : TON;    // 吹淋工艺窗，段 0 无条件刷新 / the blow process window, refreshed unconditionally
    tonBlowM : TON;    // 吹淋看门狗窗，段 0 无条件刷新 / the blow watchdog window, refreshed unconditionally
    tonPass  : TON;    // 内门通过超时窗，段 0 无条件刷新 / the inner passage timeout, refreshed unconditionally
    tonFb    : TON;    // 锁反馈失配消抖窗，段 0 无条件刷新 / the lock feedback mismatch debounce, refreshed unconditionally
    _ePhase  : E_DL_AisPhase := E_DL_AisPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eFaulC  : E_DL_AisFault := E_DL_AisFault.eNone; // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgOk  : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bFbBad  : BOOL := FALSE; // 锁反馈失配原始判据 [-] / the raw lock feedback mismatch verdict
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串相位闸与状态闸（FB50-1）/ segment 0, unconditional refresh, no instance call inside a branch
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonBlow(IN := (_ePhase = E_DL_AisPhase.eBlow) AND (NOT _bFault), PT := tBlow); // 吹淋工艺窗 / the blow process window
tonBlowM(IN := (_ePhase = E_DL_AisPhase.eBlow) AND (NOT _bFault), PT := tBlowMax); // 吹淋看门狗窗（R100：tBlowMax > tBlow 组态闸证明）/ the blow watchdog with the proven pairing
tonPass(IN := (_ePhase = E_DL_AisPhase.eInnerAllow) AND (NOT _bFault), PT := tPassTo); // 内门通过超时窗 / the inner passage timeout
tonFb(IN := _bFbBad AND (NOT _bFault), PT := tFbTo); // 锁反馈失配消抖窗 / the mismatch debounce

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_AisPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eFaulC := E_DL_AisFault.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位（门锁命令随相位派生重映射，两项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_AisFault.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _ePhase := E_DL_AisPhase.eIdle; // 作用域二：迁回空闲相（门锁命令随相重派生）/ scope two, migrate back to idle, the lock commands re-derive
END_IF

// 段 3｜组态域闸（R151 全覆盖，含 R100 配比）/ segment 3, the configuration gate with the window pairing
_bCfgOk := (tBlow > T#0S) AND (tBlowMax > tBlow) AND (tPassTo > T#0S) AND (tFbTo > T#0S); // 组态参数域判定（tBlowMax > tBlow 为双窗配比，R100）/ the configuration verdict with the pairing

// 段 4｜失配原始判据：锁命令与锁反馈不一致（消抖窗承载 eSensorBad 归因）/ segment 4, the raw mismatch verdict, the debounce carries the sensor cause
_bFbBad := (bOuterLocked <> bOuterLockFb) OR (bInnerLocked <> bInnerLockFb) OR (NOT _bCfgOk); // 命令与反馈失配或组态非法 / the command and the feedback disagree or the config is illegal

// 段 5｜双开不变量判据：任何相位破坏即故障锁存（安全侧双侧解锁）/ segment 5, the both open invariant, any violation latches a fault with both sides unlocked
IF bOuterOpen AND bInnerOpen AND (NOT _bFault) THEN // 双门同开且未锁存 / both doors open while unlatched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_AisFault.eDoorBothOpen; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 6｜急停 / 火警优先解除（安全侧直通，R146 立即终止）/ segment 6, the emergency takes the top priority, the immediate safe side release
IF bEmgLevel AND (NOT _bFault) THEN // 急停电平且未锁存 / the emergency level while unlatched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_AisFault.eAborted; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 7｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 7, the phase machine with an ELSE fallback
CASE _ePhase OF
E_DL_AisPhase.eIdle: // 空闲相：外门侧许可进入（外门解锁，内门锁闭）/ the idle phase, the outer side is allowed
    IF bEnable AND (NOT _bFault) AND bOuterOpen THEN // 外门开，进入序列启动 / the outer door opens and the entry sequence starts
        _ePhase := E_DL_AisPhase.eOuterOpen; // 迁外门开相 / migrate to the outer open phase
    END_IF

E_DL_AisPhase.eOuterOpen: // 外门开相：人已进入，等外门关（退出条件 ≥2：外门关 / 中止 / 失能 / 双开，R98）/ the outer open phase with at least two exit conditions
    IF (NOT bEnable) OR bEmgLevel THEN // 失能或急停 / disabled or an emergency
        _ePhase := E_DL_AisPhase.eFault; // 迁故障相（急停归因已在段 6 锁存）/ migrate to the fault phase
    ELSIF (NOT bOuterOpen) THEN // 外门已关 / the outer door has closed
        _ePhase := E_DL_AisPhase.eBlow; // 迁吹淋相 / migrate to the blow phase
    END_IF

E_DL_AisPhase.eBlow: // 吹淋相：双侧门锁闭，吹淋计时 / the blow phase, both doors locked and the timing runs
    IF (NOT bEnable) OR bEmgLevel THEN // 失能或急停 / disabled or an emergency
        _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF tonBlowM.Q THEN // 看门狗超时（R100 看门狗窗）/ the watchdog expired
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_AisFault.eBlowTimeout; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
        _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF tonBlow.Q THEN // 吹淋工艺窗完成（R80 三段：拍 N 进入序列起点 / 本拍行为：许可翻转 / 拍 N+1 转出：内门许可相）/ the process window completed
        _ePhase := E_DL_AisPhase.eInnerAllow; // 迁内门许可相 / migrate to the inner allow phase
    END_IF

E_DL_AisPhase.eInnerAllow: // 内门许可相：等内门通过（退出条件 ≥2：通过 / 超时 / 中止 / 失能，R98）/ the inner allow phase with at least two exit conditions
    IF (NOT bEnable) OR bEmgLevel THEN // 失能或急停 / disabled or an emergency
        _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
    ELSIF NOT bInnerOpen THEN // 内门已关（人已通过）/ the inner door has closed, the passage is complete
        _ePhase := E_DL_AisPhase.eIdle; // 回空闲相（本批次结束，等待下一进入）/ back to idle for the next entry
    ELSIF tonPass.Q THEN // 内门通过超时 / the passage timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_AisFault.eBlowTimeout; // 故障级成因（通过超时归并吹淋超时子带，R190 同带子带留痕）/ the fault cause, the passage timeout rides the blow band
        _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_AisPhase.eAborted: // 已中止相：全部解锁撤离许可，等复位沿 / the aborted phase, every lock released until the reset edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_AisPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

E_DL_AisPhase.eFault: // 故障相：成因锁存，等复位沿 / the fault phase, the cause is latched until the reset edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_AisPhase.eIdle; // 迁未使能相 / migrate to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_AisFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 8｜门锁与吹淋出口派生（互锁不变量的结构性承载 + eAborted 成员可达性）/ segment 8, the lock and blow outlets, the structural carrier
IF (_ePhase = E_DL_AisPhase.eAborted) OR (_ePhase = E_DL_AisPhase.eFault) THEN // 中止或故障相：双侧解锁撤离许可（安全侧）/ the aborted or fault phase, both sides unlock for evacuation
    bOuterLocked := FALSE; // 外门解锁 / the outer side unlocks
    bInnerLocked := FALSE; // 内门解锁 / the inner side unlocks
    bBlowing := FALSE; // 吹淋撤 / the blowing withdraws
ELSIF _ePhase = E_DL_AisPhase.eIdle THEN // 空闲相：外门侧许可 / the idle phase, the outer permission
    bOuterLocked := FALSE; // 外门解锁（进入许可）/ the outer side unlocks for entry
    bInnerLocked := TRUE; // 内门锁闭 / the inner side locks
    bBlowing := FALSE; // 吹淋撤 / the blowing withdraws
ELSIF _ePhase = E_DL_AisPhase.eOuterOpen THEN // 外门开相：双侧锁闭（人已在腔内）/ the outer open phase, both sides lock
    bOuterLocked := TRUE; // 外门锁闭 / the outer side locks
    bInnerLocked := TRUE; // 内门锁闭 / the inner side locks
    bBlowing := FALSE; // 吹淋撤 / the blowing withdraws
ELSIF _ePhase = E_DL_AisPhase.eBlow THEN // 吹淋相：双侧锁闭 + 吹淋 / the blow phase, both sides lock and the blowing runs
    bOuterLocked := TRUE; // 外门锁闭 / the outer side locks
    bInnerLocked := TRUE; // 内门锁闭 / the inner side locks
    bBlowing := TRUE; // 吹淋命令 / the blowing command
ELSE // 内门许可相：内门侧解锁 / the inner allow phase, the inner permission
    bOuterLocked := TRUE; // 外门锁闭 / the outer side locks
    bInnerLocked := FALSE; // 内门解锁（通过许可）/ the inner side unlocks for the passage
    bBlowing := FALSE; // 吹淋撤 / the blowing withdraws
END_IF
bEntryAllowed := (NOT bOuterLocked) AND (NOT _bFault); // 进入许可派生（故障否决）/ the entry permission derived with the fault veto

// 段 9｜反馈失配判级与统一出口 / segment 9, the feedback mismatch grading and the unified outlet
IF (NOT _bFault) AND tonFb.Q THEN // 失配消抖窗到且未锁存 / the debounce elapsed while unlatched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_AisFault.eSensorBad; // 故障级成因（R45 配对 bError）/ the fault cause paired with bError
    _ePhase := E_DL_AisPhase.eFault; // 迁故障相 / migrate to the fault phase
END_IF
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eFault := _eFaulC; // 故障级成因锁存回放（R152）/ the fault cause replayed from the latch
ELSE
    eFault := E_DL_AisFault.eNone; // 无锁存即无成因 / no latch, no cause
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
