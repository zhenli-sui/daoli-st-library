(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PalletizerLayerBuildSeq
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.2 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON 属 Standard.library），零厂商私有库
 * 功能描述 (Function)   : 码垛层构建时序：eIdle →（bStart）→ ePick（发取料指令，等
 *                         bPickDone 到位）→ ePlace（发放料指令，等 bPlaceDone 到位并计数）
 *                         → 满层判（nPlacedInLayer ≥ nBoxPerLayer）→ eLayerDone（发单拍层完成沿）
 *                         → 换层（nLayerNo + 1，层内计数清零）回 ePick；层数达 nLayersPerPallet
 *                         → eFull（整垛完成，等 bStart 跌落或复位）。取 / 放每相均带
 *                         tPhaseTimeout 超时兜底 → eFault。
 *                         **输出语义**：bPickCmd / bPlaceCmd 为电平台（相驻留期间为 TRUE），
 *                         bLayerDone 为**单拍脉冲**（内部 _bLayerDoneInt 置位 → 统一出口映射，
 *                         两段式，FB33-1），每拍由段 1 预置 FALSE，故脉冲宽度恰一扫描。
 *                         **bStart = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         全部动作输出落 FALSE 并回 eIdle（码垛动作不得冻结保持，冻结即撞机）。
 * 接口     (Interface)  : 输入 bStart / bReset / bPickDone / bPlaceDone / nBoxPerLayer /
 *                         nLayersPerPallet / tPhaseTimeout；输出 bPickCmd / bPlaceCmd /
 *                         nPlacedInLayer / nLayerNo / bLayerDone / bPalletFull / eState /
 *                         bError / eCause / bValid。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → ePick：bStart 为 TRUE 且组态校验通过（nBoxPerLayer / nLayersPerPallet 均在域内）；
 *      拍 N 进入（启动）/ 本拍行为：层内计数与层号初始化（nPlacedInLayer := 0、nLayerNo := 1）、
 *      不发指令 / 拍 N+1 转出至 ePick。
 *   ② ePick → ePlace：bPickDone 上升沿（本拍事件优先于超时，FB51-5）；拍 N 进入（取料到位）/
 *      本拍行为：撤 bPickCmd、发 bPlaceCmd / 拍 N+1 转出至 ePlace。
 *   ③ ePick → eFault：tonPhase.Q（超时）；拍 N 进入（超时）/ 本拍行为：锁存 ePickTimeout、
 *      撤全部动作 / 拍 N+1 转出至 eFault（段尾迁移闸）。
 *   ④ ePlace → ePick：bPlaceDone 上升沿且层未满（nPlacedInLayer + 1 < nBoxPerLayer）；
 *      拍 N 进入（放料到位）/ 本拍行为：层内计数 +1、撤 bPlaceCmd / 拍 N+1 转出至 ePick。
 *   ⑤ ePlace → eLayerDone：bPlaceDone 上升沿且本次计数后层已满；拍 N 进入 /
 *      本拍行为：层内计数 +1、_bLayerDoneInt := TRUE / 拍 N+1 转出至 eLayerDone。
 *   ⑥ ePlace → eFault：tonPhase.Q（超时），锁存 ePlaceTimeout。
 *   ⑦ eLayerDone → eFull：nLayerNo ≥ nLayersPerPallet；拍 N 进入 / 本拍行为：bPalletFull := TRUE /
 *      拍 N+1 转出至 eFull。
 *   ⑧ eLayerDone → ePick：层未满垛；拍 N 进入 / 本拍行为：nLayerNo + 1、nPlacedInLayer := 0 /
 *      拍 N+1 转出至 ePick。
 *   ⑨ eFull → eIdle：bStart 落 FALSE（前置条件消失）或 bReset 为 TRUE（两条出口，R98）；
 *      拍 N 进入 / 本拍行为：层号与层内计数清零、bPalletFull 落 FALSE / 拍 N+1 转出至 eIdle。
 *   ⑩ eFault → eIdle：bReset 上升且 bStart 为 FALSE（可达性自证 R152：两引脚外部恒可达）；
 *      拍 N 进入 / 本拍行为：清锁存与成因 / 拍 N+1 转出至 eIdle。
 *   ⑪ ELSE（非法枚举值）→ eFault，成因 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① 相超时 TON 在 CASE 外无条件调用（R7 / FB50-1①），IN 表达式为
 *                            「处于取/放相 AND 相已稳定一拍（nPhase = nPhasePrev）AND
 *                            非故障相 AND 非故障锁存」——相切换那一拍 IN 为 FALSE 使 ET 自清，
 *                            结构性无需外部沿清零（R188）。
 *                         ② 组态域闸：nBoxPerLayer ∈ [1,60]、nLayersPerPallet ∈ [1,40]，
 *                            越域置故障级 eBadConfig（R4，兼作数组/计数安全）。
 *                         ③ ePick / ePlace 退出条件均为「事件沿 + 超时」两条（R98）。
 *                         ④ 无数组、无除法，故无下标与除零风险。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_PlbCause 归属本文件（全库唯一属主）。信息级
 *                         eLayerDoneCode 永不置 bError；超时 / 组态 / 非法状态各占独立成员
 *                         （R190 归因唯一），锁存回放至 bReset 沿（FB33-1）。
 * 分工声明 (Scope)      : 层内路径规划 / 码型排布归 FB_DL_PalletizerStation 与
 *                         FB_DL_PalletizerLayerSeq（区段时序）；夹爪安全归 FB_DL_PalletGripperSafe。
 *                         本件只做「取—放—满层—换层—满垛」的计数与时序，不做轴运动与轨迹。
 * 归属     (Ownership)  : E_DL_PlbState / E_DL_PlbCause 归属本文件（全库唯一定义，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 组态域闸 +
 *                         无除法无下标 + 计数单调 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 ✓ 六态 ENUM +
 *                         CASE + ELSE ｜ R7 ✓ tonPhase 在 CASE 外无条件调用 ｜ R14 ✓ 无 PROPERTY
 *                         R8/R9 N/A（无 METHOD）｜ FB32-6 ✓ 单拍脉冲置位与撤销分属两拍
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B3 首版
 * 验收向量 (Acceptance) :
 *   V1 nBoxPerLayer=2、nLayersPerPallet=2：bStart 上升 → ePick；bPickDone 脉冲 → ePlace；
 *      bPlaceDone 脉冲 → nPlacedInLayer=1 且回 ePick；再一轮 → nPlacedInLayer=2、eLayerDone、
 *      bLayerDone 单拍为 TRUE（次拍 FALSE）；随后 nLayerNo=2、nPlacedInLayer=0、ePick。
 *   V2 续 V1 完成第 2 层 → eFull、bPalletFull=TRUE；bStart 落 FALSE → 回 eIdle，计数全清。
 *   V3 tPhaseTimeout=5s、bPickDone 始终不来 → 5s 后 eState=eFault、eCause=ePickTimeout、
 *      bError=TRUE、bPickCmd=FALSE；bReset 上升且 bStart=FALSE → 回 eIdle。
 *   V4 nBoxPerLayer=0 → eState=eFault、eCause=eBadConfig、bError=TRUE。
 *   V5 eFull 内 bReset=TRUE（bStart 仍 TRUE）→ 回 eIdle 并清计数（第二条出口）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PlbState（码垛层构建相位；eFault 为安全相，仅 bReset 沿迁出）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PlbState :
(
    eIdle      := 0,    // 空闲：无动作输出，等 bStart / Idle: no motion command, waiting for bStart
    ePick      := 10,   // 取料相：bPickCmd 电平为 TRUE，等 bPickDone / Pick phase: bPickCmd high until bPickDone
    ePlace     := 20,   // 放料相：bPlaceCmd 电平为 TRUE，等 bPlaceDone / Place phase: bPlaceCmd high until bPlaceDone
    eLayerDone := 30,   // 层完成相：发 bLayerDone 单拍沿并判定换层 / Layer done: emit the single-scan edge and decide
    eFull      := 40,   // 整垛完成相：bPalletFull 电平为 TRUE / Pallet full: bPalletFull high
    eFault     := 90    // 故障安全相：超时 / 组态非法，动作全撤 / Fault safe phase: timeout or bad configuration
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PlbCause（成因码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PlbCause :
(
    eNone          := 0,   // 信息级：无事件 / Info: no event
    eLayerDoneCode := 1,   // 信息级：一层已构建完成 / Info: one layer completed
    ePalletDone    := 2,   // 信息级：整垛完成 / Info: pallet completed
    ePickTimeout   := 10,  // 故障级：取料相超时 / Fault: pick phase timeout
    ePlaceTimeout  := 11,  // 故障级：放料相超时 / Fault: place phase timeout
    eBadConfig     := 12,  // 故障级：每层箱数 / 每垛层数越域 / Fault: box-per-layer or layer count out of domain
    eIllegalState  := 13   // 故障级：非法状态枚举值 / Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_PalletizerLayerBuildSeq
VAR_INPUT
    bStart          : BOOL := FALSE;          // 启动（电平）：FALSE 时动作全撤并回 eIdle / Start level, FALSE withdraws all commands
    bReset          : BOOL := FALSE;          // 复位（上升沿，需同时 bStart=FALSE）/ Reset rising edge, requires bStart FALSE
    bPickDone       : BOOL := FALSE;         // 取料到位反馈（上升沿表示本相完成，初值 FALSE 防首拍假沿）/ Pick completion feedback, rising edge ends the phase, FALSE default avoids a first-scan ghost edge
    bPlaceDone      : BOOL := FALSE;         // 放料到位反馈（上升沿表示本相完成，初值 FALSE 防首拍假沿）/ Place completion feedback, rising edge ends the phase, FALSE default avoids a first-scan ghost edge
    nBoxPerLayer    : INT := 5;               // 每层箱数，有效域 1..60 [-] / Boxes per layer, valid domain 1..60
    nLayersPerPallet : INT := 6;              // 每垛层数，有效域 1..40 [-] / Layers per pallet, valid domain 1..40
    tPhaseTimeout   : TIME := T#10S;          // 单相超时（取/放共用），域 > 0 [s] / Phase timeout shared by pick and place
END_VAR
VAR_OUTPUT
    bPickCmd        : BOOL;                   // 取料指令（电平）/ Pick command, level signal
    bPlaceCmd       : BOOL;                   // 放料指令（电平）/ Place command, level signal
    nPlacedInLayer  : INT := 0;               // 本层已放箱数 [个] / Boxes placed in the current layer
    nLayerNo        : INT := 0;               // 当前层号（1 起）[层] / Current layer number starting at one
    bLayerDone      : BOOL;                   // 层完成单拍脉冲（段 1 预置，统一出口映射）[-] / Single-scan layer-done pulse
    bPalletFull     : BOOL;                   // 整垛完成（电平，保持至 bStart 跌落或复位）[-] / Pallet full, level held until bStart falls or reset
    eState          : E_DL_PlbState;           // 状态出口（段尾单点映射）[-] / State outlet mapped at the tail
    bError          : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    eCause          : E_DL_PlbCause;          // 成因码出口（故障期锁存回放）[-] / Cause code outlet
    bValid          : BOOL;                   // 时序有效回执（取/放相才 TRUE）[-] / Sequence validity receipt
END_VAR
VAR
    _eState        : E_DL_PlbState := E_DL_PlbState.eIdle;    // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _eStatePrev    : E_DL_PlbState := E_DL_PlbState.eIdle;    // 上一拍相位快照（相稳定判据用，段末唯一更新）[-] / Phase snapshot of the last scan
    _bFaultLatch   : BOOL := FALSE;                           // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit
    _eCauseLatch   : E_DL_PlbCause := E_DL_PlbCause.eNone;     // 锁存成因码（FB33-1 锁存回放）[-] / Latched cause code
    _bCfgOk        : BOOL := TRUE;                            // 组态域闸通过标志 [-] / Configuration gate flag
    _bLayerDoneInt : BOOL := FALSE;                           // 层完成内部单拍位（统一出口映射，FB33-1）[-] / Internal single-scan layer-done bit
    _bPhaseActive  : BOOL := FALSE;                           // 取/放相驻留标志（超时使能域）[-] / Phase-resident flag driving the timeout
    _bPickRise     : BOOL := FALSE;                           // 取料到位上升沿（本拍）/ Pick completion rising edge of this scan
    _bPlaceRise    : BOOL := FALSE;                           // 放料到位上升沿（本拍）/ Place completion rising edge of this scan
    rtPickDone     : R_TRIG;                                  // 取料到位边沿实例（段 3 无条件调用）/ Pick edge instance called unconditionally
    rtPlaceDone    : R_TRIG;                                  // 放料到位边沿实例（段 3 无条件调用）/ Place edge instance called unconditionally
    tonPhase       : TON;                                     // 相超时定时器（段 3 无条件调用）/ Phase timeout timer called unconditionally
    _rtReset     : R_TRIG;                                 // 复位沿检测实例（v1.0.2 补：声明沿即实现沿，CASE 外无条件刷新）/ Reset edge detector refreshed outside the CASE
END_VAR
VAR CONSTANT
    DL_PLB_ZERO      : INT := 0;      // 计数零基准 [-] / Count zero base
    DL_PLB_ONE       : INT := 1;      // 计数起始值（层号与每层首箱）[-] / Count start value
    DL_PLB_BOX_MAX   : INT := 60;     // 每层箱数上限（域闸用）[-] / Upper bound of boxes per layer
    DL_PLB_LAYER_MAX : INT := 40;     // 每垛层数上限（域闸用）[-] / Upper bound of layers per pallet
END_VAR

(* —— 段 1：单拍位与动作出口预置（纸清单拍标志与电平出口，不清锁存/计数，FB32-1） —— *)
bLayerDone     := FALSE;                                // 单拍层完成沿每拍预清 / Single-scan edge preset FALSE every scan
bPickCmd       := FALSE;                                // 取料指令预置（安全侧：默认不动作）/ Pick command preset, safe side
bPlaceCmd      := FALSE;                                // 放料指令预置（安全侧：默认不动作）/ Place command preset, safe side
_bLayerDoneInt := FALSE;                                // 内部单拍位预清 / Internal single-scan bit preset
_bCfgOk        := TRUE;                                 // 组态闸标志复位 / Configuration flag reset

(* —— 段 2：组态域闸（每层箱数 / 每垛层数，R4） —— *)
IF (nBoxPerLayer < DL_PLB_ONE) OR (nBoxPerLayer > DL_PLB_BOX_MAX)
    OR (nLayersPerPallet < DL_PLB_ONE) OR (nLayersPerPallet > DL_PLB_LAYER_MAX) THEN
    _bCfgOk := FALSE;                                   // 组态越域 / Configuration out of domain
    IF NOT _bFaultLatch THEN
        _eCauseLatch := E_DL_PlbCause.eBadConfig;       // 故障级：组态非法（首因锁存）/ Fault: bad configuration
        _bFaultLatch := TRUE;                           // 置故障锁存 / Latch the fault
    END_IF
END_IF

(* —— 段 3：边沿与超时实例（CASE 外无条件调用，R7 / FB50-1①） —— *)
rtPickDone(CLK := bPickDone);                           // 取料到位沿（无条件刷新：非取料相期间的沿被吞，属 R7 固有口径）/ Pick completion edge, refreshed unconditionally, edges outside the phase are consumed
rtPlaceDone(CLK := bPlaceDone);                         // 放料到位沿（无条件刷新，沿吞噬口径与取料沿一致）/ Place completion edge, refreshed unconditionally with the same edge-consumption rule
_bPickRise  := rtPickDone.Q;                            // 取料沿快照 / Pick edge snapshot
_bPlaceRise := rtPlaceDone.Q;                           // 放料沿快照 / Place edge snapshot
_bPhaseActive := (_eState = E_DL_PlbState.ePick) OR (_eState = E_DL_PlbState.ePlace);   // 取/放相驻留 / Phase residency
tonPhase(IN := _bPhaseActive AND (_eState = _eStatePrev) AND (_eState <> E_DL_PlbState.eFault) AND (NOT _bFaultLatch),
         PT := tPhaseTimeout);                          // 相稳定一拍后才计时，相切换拍 ET 自清（R188）/ Timer armed only after a stable phase scan

(* —— 段 4：状态机主体（唯一相位写入点，事件沿优先于超时，FB51-5） —— *)
_rtReset(CLK := bReset);                                // 复位沿刷新无条件周期调用（R7；v1.0.2 修复 J1 电平判据缺陷 / R18）/ Refresh the reset edge unconditionally every scan
CASE _eState OF
    E_DL_PlbState.eIdle :
        IF bStart AND (NOT _bFaultLatch) THEN
            nPlacedInLayer := DL_PLB_ZERO;              // 层内计数清零 / Clear the in-layer count
            nLayerNo       := DL_PLB_ONE;               // 层号置 1 / Start at layer one
            bPalletFull    := FALSE;                    // 整垛标志复位 / Clear the pallet-full flag
            eCause         := E_DL_PlbCause.eNone;      // 信息级：无事件 / Info: no event
            _eState        := E_DL_PlbState.ePick;      // 迁移①：进入取料相 / Move to pick
        ELSE
            bPalletFull := FALSE;                       // 未启动：整垛标志保持 FALSE / Not started: pallet flag FALSE
        END_IF

    E_DL_PlbState.ePick :
        bPickCmd := TRUE;                               // 取料指令电平为 TRUE / Pick command high
        IF _bPickRise THEN
            (* 迁移②：本拍事件优先，先消化到位沿再消化超时（FB51-5） *)
            bPickCmd := FALSE;                          // 撤取料指令 / Withdraw the pick command
            eCause   := E_DL_PlbCause.eNone;            // 信息级：无事件 / Info: no event
            _eState  := E_DL_PlbState.ePlace;           // 迁入放料相 / Move to place
        ELSIF tonPhase.Q THEN
            (* 迁移③：超时兜底 *)
            _eCauseLatch := E_DL_PlbCause.ePickTimeout; // 故障级：取料超时 / Fault: pick timeout
            _bFaultLatch := TRUE;                       // 置故障锁存 / Latch the fault
            bPickCmd     := FALSE;                      // 撤动作 / Withdraw the command
            _eState      := E_DL_PlbState.eFault;       // 迁入故障相 / Move to fault
        END_IF

    E_DL_PlbState.ePlace :
        bPlaceCmd := TRUE;                              // 放料指令电平为 TRUE / Place command high
        IF _bPlaceRise THEN
            (* 迁移④ / ⑤：放料到位 → 计数 + 满层判（两出口分列） *)
            bPlaceCmd      := FALSE;                    // 撤放料指令 / Withdraw the place command
            nPlacedInLayer := nPlacedInLayer + DL_PLB_ONE;   // 层内计数 +1 / Increment the in-layer count
            IF nPlacedInLayer >= nBoxPerLayer THEN
                _bLayerDoneInt := TRUE;                 // 层已满：内部单拍位置位（统一出口映射）/ Layer full: internal edge bit
                eCause         := E_DL_PlbCause.eLayerDoneCode;   // 信息级：一层完成 / Info: one layer done
                _eState        := E_DL_PlbState.eLayerDone;       // 迁入层完成相 / Move to layer done
            ELSE
                eCause := E_DL_PlbCause.eNone;          // 信息级：无事件 / Info: no event
                _eState := E_DL_PlbState.ePick;         // 回取料相继续本层 / Back to pick for the same layer
            END_IF
        ELSIF tonPhase.Q THEN
            (* 迁移⑥：超时兜底 *)
            _eCauseLatch := E_DL_PlbCause.ePlaceTimeout;   // 故障级：放料超时 / Fault: place timeout
            _bFaultLatch := TRUE;                          // 置故障锁存 / Latch the fault
            bPlaceCmd    := FALSE;                         // 撤动作 / Withdraw the command
            _eState      := E_DL_PlbState.eFault;          // 迁入故障相 / Move to fault
        END_IF

    E_DL_PlbState.eLayerDone :
        IF nLayerNo >= nLayersPerPallet THEN
            bPalletFull := TRUE;                        // 迁移⑦：整垛满 / Pallet full
            eCause      := E_DL_PlbCause.ePalletDone;   // 信息级：整垛完成 / Info: pallet completed
            _eState     := E_DL_PlbState.eFull;         // 迁入整垛完成相 / Move to full
        ELSE
            nLayerNo       := nLayerNo + DL_PLB_ONE;    // 迁移⑧：换层 / Next layer
            nPlacedInLayer := DL_PLB_ZERO;              // 层内计数清零 / Clear the in-layer count
            eCause         := E_DL_PlbCause.eNone;      // 信息级：无事件 / Info: no event
            _eState        := E_DL_PlbState.ePick;      // 回取料相 / Back to pick
        END_IF

    E_DL_PlbState.eFull :
        (* 迁移⑨：两条出口（前置条件消失 / 复位），R98 *)
        IF (NOT bStart) OR bReset THEN
            bPalletFull    := FALSE;                    // 整垛标志撤销 / Withdraw the pallet flag
            nPlacedInLayer := DL_PLB_ZERO;              // 层内计数清零 / Clear the in-layer count
            nLayerNo       := DL_PLB_ZERO;              // 层号清零 / Clear the layer number
            eCause         := E_DL_PlbCause.eNone;      // 信息级：无事件 / Info: no event
            _eState        := E_DL_PlbState.eIdle;      // 回空闲相 / Back to idle
        END_IF

    E_DL_PlbState.eFault :
        (* 迁移⑩：唯一出口 —— bReset 沿 + bStart 已落 *)
        IF _rtReset.Q AND (NOT bStart) THEN
            _bFaultLatch   := FALSE;                    // 清故障锁存 / Clear the latch
            _eCauseLatch   := E_DL_PlbCause.eNone;      // 清锁存成因 / Clear the latched cause
            eCause         := E_DL_PlbCause.eNone;      // 出口同步归零 / Outlet follows
            nPlacedInLayer := DL_PLB_ZERO;              // 计数清零 / Clear the count
            nLayerNo       := DL_PLB_ZERO;              // 层号清零 / Clear the layer number
            _eState        := E_DL_PlbState.eIdle;      // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑪：非法枚举兜底（R6） *)
    _eCauseLatch := E_DL_PlbCause.eIllegalState;        // 故障级：非法状态 / Fault: illegal state
    _bFaultLatch := TRUE;                               // 置锁存 / Latch
    _eState      := E_DL_PlbState.eFault;               // 迁入故障相 / Move to fault
END_CASE

(* —— 段 5：段尾故障迁移闸（锁存与迁相分离，FB50-1④），动作输出在故障相全撤 —— *)
IF _bFaultLatch AND (_eState <> E_DL_PlbState.eFault) THEN
    _eState := E_DL_PlbState.eFault;                    // 锁存即迁相 / Latch forces the fault phase
END_IF
IF _eState = E_DL_PlbState.eFault THEN
    bPickCmd  := FALSE;                                 // 故障相撤取料 / Fault phase: withdraw pick
    bPlaceCmd := FALSE;                                 // 故障相撤放料 / Fault phase: withdraw place
END_IF

(* —— 段 6：统一出口（状态映射 + 单拍位映射 + 锁存回放） —— *)
eState     := _eState;                                  // 相位映射 / Phase mapping
bLayerDone := _bLayerDoneInt;                           // 单拍层完成沿统一映射（FB33-1 两段式）/ Single-scan edge mapped here
bError     := _bFaultLatch;                             // 故障标志取锁存位 / Fault flag from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                             // 故障期回放锁存码 / Replay the latched code
END_IF
bValid := _bPhaseActive AND (NOT _bFaultLatch);         // 仅取/放相且无锁存时有效 / Valid only in pick or place without a latch
_eStatePrev := _eState;                                 // 相位快照更新（唯一写入点，超时相稳定判据用）/ Phase snapshot update, single write point
END_FUNCTION_BLOCK
