(*
  ==================================================================
  组件名 Component  : FB_DL_ReworkLotGate
  分类   Category   : DL_Process
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0006_3036（故障级：越权放行锁存）｜ 16#0006_3037
                      （信息级：放行计数饱和钳位）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 返工批拦截闸：返工标记登记期拦截放行指令，复检合格才
                      放行并计数；返工登记期未复检合格的放行指令判「越权
                      放行」并锁存故障；供批次放行合规审计与质量门禁使用。
  开源溯源 Origin    : ISA-88 批次相状态模型（公开条款，R12 沿用）+ PackML
                      纪律次源（T2-7 / T2-8）：仅借「批次相语义」状态命名
                      组织方式；返工闸逻辑完全自研，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 状态机 / R_TRIG 语义；ISA-88
                      批次相状态公开条款（借语义，不抄文）
  平台   Platform   : 纯 IEC 61131-3（R_TRIG / ENUM+CASE / 四则），三平台通用
  依赖   Depends    : 仅 Standard.library（R_TRIG 属标准件）
  分工声明 Split     : FB_DL_BatchPhaseTrack（批次相跟踪）/ FB_DL_HoldResumeSeq
                      （保持恢复顺控）与本件互引；本件只管「返工标记 → 放行
                      合规」单门禁，不做批次全程跟踪（R216）。
  归属 Ownership     : E_DL_ReworkGatePhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态口径（定稿，R90 反证句见码表）：nQuotaMax < 1
                         按「钳位接管为 1」静默接管——上限为 1 的闸仍有
                         完整拦截语义（登记 + 复检合格才放行 + 计数），
                         功能不静默丢失，非永假防御；不为此另立故障码
                         （组态缺省出口与正常运行出口完全同形：闸照常
                         工作、计数照常推进，无任何输出可区分该场景）；
                         3036 专用于越权放行锁存；
                      二 状态机 ENUM + CASE 必带 ELSE（非法态兜底落 eFault +
                         锁存 3036，禁静默）；本拍合法事件（复检合格沿 /
                         登记撤除）优先于越权判据（R275 同拍竞态）；
                      三 越权放行判据（锁存回放，R152）：返工登记电平 +
                         放行指令 + 复检未合格 → 锁存 3036 + bError；
                         锁存解除式（可达自证）：bResetCmd 上升沿清锁存
                         回 eIdle（输入引脚恒可达，无「置位即永久」路径）；
                      四 合规放行计数：放行沿（rtRelease R_TRIG，段 0 无条件
                         刷新）+ 复检合格 + 未锁存才计数；计数达 nQuotaMax
                         饱和钳位 + 信息级 3037（不置 bError，闸功能不受
                         影响，钳位为审计口径不是功能门槛）；
                      五 bEnable = FALSE 的语义写死（FB33-4 声明行）：强制
                         eIdle + 双出口复位（不 faults，使能断开 ≠ 合规故障）；
                      六 首拍 _bInit 全量初始化；无浮点量、无除法、无定时器
                         （纯电平 / 沿 / 计数语义）；无全局、无外部变量、
                         无物理地址。
  错误码 Codes      :
    16#0006_3036【故障级】越权放行（返工登记期放行指令且复检未合格）或非法
                         状态拦截（ELSE 兜底），锁存回放至复位沿
    16#0006_3037【信息级】放行计数已达 nQuotaMax 饱和钳位（不置 bError）
  码位反证 Note     :
    3036 与 3037 不可合并：3036 锁存 + bValid = FALSE + bError = TRUE，
    3037 不锁存 + bValid = TRUE + bError = FALSE，bValid / bError 双通道
    可唯一区分，按 R90 分立；「登记撤除瞬间的放行沿」与「越权」由同拍
    事件优先序区分（边界二），不需第三码。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 无登记 + 放行沿 → nReleased + 1、bReleaseAllow（正常批口径）
    V2 登记 + 复检合格 + 放行沿 → 计数 + 1（返工批合规放行）
    V3 登记 + 复检未合格 + 放行指令 → 锁存 3036 + bError
    V4 锁存态 bResetCmd 上升沿 → 解锁回 eIdle（锁存解除可达向量）
    V5 nQuotaMax = 3、放行 4 次 → nReleased 钳 3 + 码 3037
       （bError = FALSE，闸功能照常）
    V6 nQuotaMax = 0 → 钳位接管为 1（边界一定稿口径，功能不静默丢失）
    V7 失能 → eIdle + 双出口复位（不 faults）
    V8 非法枚举态（强改 eState）→ ELSE 兜底落 eFault + 3036
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 3 · 序号 9，ISA-88 / PackML 纪律次源 + 自研）
  ==================================================================
*)
TYPE E_DL_ReworkGatePhase :
(
    eIdle       := 0,  // 待机：无返工登记 / idle, no rework registered
    eReworkHold := 10, // 返工拦截：登记生效，等复检合格 / the rework hold, waiting for the recheck pass
    eReleased   := 20, // 放行：合规放行相（登记撤除或复检合格放行后驻留一拍语义由调用方承接）/ the released phase
    eFault      := 30  // 锁存故障：越权放行或非法态，复位沿解除 / a latched fault released by the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_ReworkLotGate
VAR_INPUT
    bEnable      : BOOL := TRUE;  // 使能，FALSE 时强制 eIdle + 双出口复位（边界五）/ the enable, false forces the idle and resets both outlets
    bLotRework   : BOOL := FALSE; // 返工标记登记电平 [-]（来自批次履历）/ the rework registration level from the lot history
    bRecheckPass : BOOL := FALSE; // 复检合格电平 [-] / the recheck pass level
    bReleaseCmd  : BOOL := FALSE; // 放行指令电平 [-] / the release command level
    bResetCmd    : BOOL := FALSE; // 故障复位电平，上升沿清锁存回 eIdle（边界三解除式）/ the fault reset level, its rising edge releases the latch
    nQuotaMax    : DINT  := 16;   // 放行计数饱和上限 [个]，须 ≥ 1，< 1 钳位接管为 1（边界一定稿）/ the release count ceiling, at least one, clamped when below
END_VAR
VAR_OUTPUT
    bReleaseAllow : BOOL := FALSE;           // 放行许可电平 [-]（锁存 / 失能强制 FALSE）/ the release permission forced false on a latch or disable
    bReworkHold   : BOOL := FALSE;           // 返工拦截中指示 [-] / the rework hold indicator
    nReleased     : DINT  := 0;              // 合规放行计数 [个]（饱和口径）/ the compliant release count saturated
    eState        : E_DL_ReworkGatePhase;    // 状态机出口 [状态] / the state machine outlet
    bValid        : BOOL := FALSE;           // 判据可用 [-] / the criteria are usable
    eErr          : UDINT := 16#0000_0000;   // 错误码，0 = 正常 / the error code, zero is ok
    bError        : BOOL := FALSE;           // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit      : BOOL := FALSE;  // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _eState     : E_DL_ReworkGatePhase := E_DL_ReworkGatePhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFaultLatch: BOOL := FALSE;  // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _uLatch     : UDINT := 16#0000_0000; // 故障码锁存 [码]（复位沿清除，FB33-1）/ the latched fault code cleared by the reset edge
    _nReleased  : DINT  := 0;     // 计数内部副本 [个]（饱和钳位口径）/ the internal count copy saturated
    _nQuotaUse  : DINT  := 1;     // 上限接管量 [个]（< 1 钳位为 1，边界一）/ the ceiling taken over clamped to one
    _bCountSat  : BOOL := FALSE;  // 计数饱和标记（单拍信息位，段 6 映射）/ the count saturation flag of this scan
    rtReset     : R_TRIG;         // 复位沿实例，段 0 无条件刷新（R7）/ the reset edge instance refreshed unconditionally
    rtRelease   : R_TRIG;         // 合规放行沿实例，段 0 无条件刷新 / the compliant release edge instance refreshed unconditionally
VAR CONSTANT
    DL_RLG_ZEROI: DINT  := 0;  // 整型零常量 [个] / the integer zero constant
    DL_RLG_ONEI : DINT  := 1;  // 整型一常量 [个] / the integer one constant
    DL_RLG_ZEROU: UDINT := 16#0000_0000; // 码零常量 / the code zero constant
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional edge refresh
rtReset(CLK := bResetCmd); // 复位沿 / the reset edge
rtRelease(CLK := bReleaseCmd AND NOT _bFaultLatch AND bEnable
                 AND (NOT bLotRework OR bRecheckPass)); // 合规放行沿（登记撤除或复检合格的放行指令上升沿，R275 事件优先口径）/ the compliant release edge of the legal command

// 段 1｜首拍初始化与复位沿作用域（R310 / R311）/ segment 1, the first scan init and the reset edge scope
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _eState := E_DL_ReworkGatePhase.eIdle; // 状态显式落空闲 / place the state to idle
    _bFaultLatch := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _uLatch := DL_RLG_ZEROU; // 码锁存显式清零 / clear the latched code explicitly
    _nReleased := DL_RLG_ZEROI; // 计数显式清零 [个] / clear the count explicitly
    _nQuotaUse := DL_RLG_ONEI; // 上限接管显式置一 [个] / preset the ceiling one explicitly
END_IF
IF rtReset.Q THEN // 复位沿（作用域声明：清锁存 + 迁相位，不清计数——计数是审计台账，R311）/ the reset edge with the declared scope, the audit count survives
    _bFaultLatch := FALSE; // 清故障锁存（唯一解除路径，边界三自证可达）/ clear the fault latch, the only release path
    _uLatch := DL_RLG_ZEROU; // 清码锁存 / clear the latched code
    _eState := E_DL_ReworkGatePhase.eIdle; // 迁回空闲 / back to idle
END_IF

// 段 2｜上限接管与计数饱和预置（边界一：nQuotaMax < 1 钳位接管为 1，功能不静默丢失）/ segment 2, the ceiling take over and the saturation preset
_nQuotaUse := nQuotaMax; // 上限接管 [个] / take the ceiling
IF _nQuotaUse < DL_RLG_ONEI THEN // 上限 < 1（组态缺省）/ the ceiling below one
    _nQuotaUse := DL_RLG_ONEI; // 钳位接管为 1（拦截闸仍有完整语义）/ clamp to one, the gate keeps its full semantics
END_IF
_bCountSat := FALSE; // 计数饱和标记预清零（单拍信息位，R256 统一出口预置）/ preset the saturation flag false

// 段 3｜失能分支：强制 eIdle + 双出口复位，不 faults（边界五声明行）/ segment 3, the disabled branch
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_ReworkGatePhase.eIdle; // 强制空闲 / force the idle
    _bFaultLatch := FALSE; // 锁存复位（使能断开 ≠ 合规故障）/ clear the latch
    _uLatch := DL_RLG_ZEROU; // 码锁存复位 / clear the code
    eState := _eState; // 状态出口 / the state outlet
    bReleaseAllow := FALSE; // 许可电平复位 / the permission resets
    bReworkHold := FALSE; // 拦截指示复位 / the hold indicator resets
    bValid := FALSE; // 失能即不可用 / the criteria are not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := DL_RLG_ZEROU; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退（计数不动，失能不清审计台账）/ early return, the audit count survives
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 兜底；本拍事件优先于越权判据，R275）/ segment 4, the main machine, the event before the misuse verdict
CASE _eState OF
    E_DL_ReworkGatePhase.eIdle: // 空闲相 / the idle phase
        IF bLotRework THEN // 返工登记生效 / the rework registration is active
            _eState := E_DL_ReworkGatePhase.eReworkHold; // 迁入拦截相 / enter the hold phase
        END_IF
    E_DL_ReworkGatePhase.eReworkHold: // 返工拦截相（本拍合法事件优先：登记撤除或复检合格放行先消化，再消化越权判据，R275）/ the hold phase, the legal event before the misuse
        IF NOT bLotRework THEN // 事件优先：登记撤除 / the registration withdrawn, the event goes first
            _eState := E_DL_ReworkGatePhase.eIdle; // 回空闲 / back to idle
        ELSIF bRecheckPass AND bReleaseCmd THEN // 复检合格 + 放行指令（合规放行，边界四口径）/ the recheck passed with the release command
            _eState := E_DL_ReworkGatePhase.eReleased; // 迁入放行相 / enter the released phase
        ELSIF bReleaseCmd THEN // 越权判据：登记中放行且复检未合格（真实可达：操作员越过复检直接放令）/ the misuse path, reachable by the operator bypassing the recheck
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0006_3036; // 故障级：越权放行 / fault grade, the unauthorized release
            bError := TRUE; // 同拍置故障标志（R45 配对，段 6 故障分支沿用）/ raise the fault flag on the same scan
        END_IF
    E_DL_ReworkGatePhase.eReleased: // 放行相（登记撤除或再登记由电平驱动回迁）/ the released phase driven back by the levels
        IF bLotRework THEN // 再次登记 / registered again
            _eState := E_DL_ReworkGatePhase.eReworkHold; // 迁回拦截相 / back to the hold phase
        ELSIF NOT bReleaseCmd THEN // 放行指令撤回 / the release command withdrawn
            _eState := E_DL_ReworkGatePhase.eIdle; // 回空闲 / back to idle
        END_IF
    E_DL_ReworkGatePhase.eFault: // 锁存故障相（驻留，解除由段 1 复位沿承担）/ the fault phase dwelling, the release belongs to the reset edge
        ; // 驻留语义由注释表达（禁自赋值死语句，R261）/ the dwell is expressed by this comment without a dead statement
    ELSE // 非法枚举值拦截（边界二：落故障相并锁存，禁静默）/ the illegal enumeration guard
        _bFaultLatch := TRUE; // 锁存故障 / latch the fault
        _uLatch := 16#0006_3036; // 故障级：非法状态拦截（归入越权族一码，出口同形锁存回放，R90）/ fault grade, the illegal state under the latch family
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        _eState := E_DL_ReworkGatePhase.eFault; // 落故障相 / force the fault phase
END_CASE

// 段 5｜合规放行计数（边界四：沿 + 未锁存才计数；饱和钳位 + 信息级）/ segment 5, the compliant release counting with the saturation
IF rtRelease.Q AND (NOT _bFaultLatch) THEN // 合规放行沿且未锁存 / a compliant release edge without a latch
    IF _nReleased < _nQuotaUse THEN // 计数未达上限 / the count below the ceiling
        _nReleased := _nReleased + DL_RLG_ONEI; // 计数推进 [个] / advance the count
    ELSE // 计数已达上限：饱和钳位 + 信息级（闸功能不受影响，边界四）/ the count saturated with the info code, the gate unaffected
        _bCountSat := TRUE; // 置饱和标记（单拍信息位）/ raise the saturation flag
    END_IF
END_IF

// 段 6｜故障锁存迁移闸 + 统一出口（名实双出口同源，R191）/ segment 6, the latch gate and the unified outlet
IF _bFaultLatch AND (_eState <> E_DL_ReworkGatePhase.eFault) THEN // 已锁存但不在故障相 / latched outside the fault phase
    _eState := E_DL_ReworkGatePhase.eFault; // 迁入故障相 / enter the fault phase
END_IF
eState := _eState; // 状态出口 / the state outlet
bReleaseAllow := (NOT _bFaultLatch) AND bEnable
              AND ((NOT bLotRework) OR bRecheckPass); // 许可电平与判据同源派生（登记中须复检合格）/ the permission derived from the criteria
bReworkHold := (_eState = E_DL_ReworkGatePhase.eReworkHold); // 拦截指示与状态同源 / the hold indicator from the state
nReleased := _nReleased; // 计数出口 [个] / the count outlet
IF _bFaultLatch THEN // 故障锁存回放优先（不在故障相按当下输入重新推断，R152）/ the latched fault replays first
    bValid := FALSE; // 故障相不可用 / not usable in the fault phase
    bError := TRUE; // 故障位置位（R45 配对）/ raise the fault bit
    eErr := _uLatch; // 锁存码回放 / replay the latched code
ELSIF _bCountSat THEN // 计数饱和（信息级，单拍重算）/ the saturation, informational
    bValid := TRUE; // 闸功能照常可用 / the gate stays usable
    bError := FALSE; // 信息级不置故障标志（R285）/ keep the fault flag false
    eErr := 16#0006_3037; // 信息级：放行计数饱和钳位 / informational, the count saturated
ELSE // 无事件 / no event
    bValid := TRUE; // 判据可用 / the criteria are usable
    bError := FALSE; // 无故障 / no fault
    eErr := DL_RLG_ZEROU; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
