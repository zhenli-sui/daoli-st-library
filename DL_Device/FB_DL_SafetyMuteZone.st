(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SafetyMuteZone
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / F_TRIG），
 *                         零厂商私有库
 * 功能描述 (Function)   : 静默区（Muting）顺序时序判据：光幕遮挡（bLightCurtain=
 *                         TRUE=被遮挡）期间， mute 传感器须按 1→2 顺序激活才
 *                         合法静默（bMuted=TRUE）；2 先于 1 激活 → 乱序故障
 *                         锁存 bMuteFault（规格指定，R189 锁存回放）；静默窗
 *                         tMuteMax 超时 → 强制撤销静默回待机并置信息码
 *                         eMuteTimeout。合法时序：eIdle →（sen1 激活沿 ∧ 遮挡）
 *                         → eS1 →（sen2 激活沿）→ eMuted →（双释放 ∧ 光幕
 *                         恢复）→ eIdle。
 *                         **本件不作安全认证声明：仅作工艺物流静默时序编排，
 *                         人身安全由认证安全回路（安全 PLC/安全继电器）保证，
 *                         本件输出不得作为唯一安全切断依据。**
 * 接口     (Interface)  : 输入 bMuteSen1 静默传感器 1（TRUE=被物料遮挡）、
 *                         bMuteSen2 静默传感器 2、bLightCurtain 光幕（TRUE=
 *                         被遮挡）、tMuteMax 静默窗上限、bReset 复位；输出
 *                         bMuted 静默有效、bMuteFault 乱序故障锁存、ePhase
 *                         相位出口、eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做静默时序判据，不切断
 *                         光幕回路、不接管安全认证**（头注释安全声明）。
 *                         ② 四态 CASE + ELSE 兜底（R6）；tonMuteMax IN 挂
 *                         相驻留本身（eS1 ∨ eMuted 均计时，覆盖静默全程，
 *                         R145 使能域覆盖）；三沿实例段 0 无条件调用（R7）。
 *                         ③ 乱序归因唯一：sen2 先激活沿（eIdle 相内）→
 *                         eMuteFault 锁存 + eErrCode=eOrderBad；光幕未遮挡
 *                         期间传感器激活不作乱序（无静默语境）。
 *                         ④ 静默窗覆盖 eS1 与 eMuted 两相全程；超时强制撤销
 *                         回 eIdle（安全侧：静默撤销 = 光幕判据恢复有效），
 *                         信息码 eMuteTimeout 不锁存 bMuteFault（撤销本身为
 *                         安全侧动作）。
 *                         ⑤ 故障锁存解除路径：bMuteFault 解除边 = 传感器全
 *                         释放 ∧ bReset 上升沿（可达，头注释声明，R188）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_ElMutingGantry` 分工：龙门式静默布置归那件、
 *                         双传感器顺序静默区归本件；与 `FB_DL_FilmSpliceCurtain`
 *                         分工：拼接光幕归那件。
 * 来源标签 (Source Tag) : 自研线（双传感器静默顺序判据为公开物流静默模式
 *                         clean-room，不作安全认证声明）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 组 +
 *                         ENUM 相位/错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 乱序锁存解除可达 + 超时强制撤销安全侧 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 CASE 含 ELSE ｜ R7 ✓ 一 TON 三沿段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 4 · 序号 17）
 * 验收向量 (Acceptance) : ① 光幕遮挡后 sen1 激活、100ms 后 sen2 激活 → eMuted、
 *                         bMuted=TRUE；② 双传感器释放 ∧ 光幕恢复 → eIdle、
 *                         bMuted=FALSE；③ eIdle 相内 sen2 先激活 → bMuteFault
 *                         锁存、eErrCode=eOrderBad；④ 静默持续 > tMuteMax
 *                         → 强制回 eIdle、eErrCode=eMuteTimeout、bMuted=FALSE。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SmzPhase（静默区相位，全库唯一属主本文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SmzPhase :
(
    eIdle  := 0,   // 待机（无静默语境） / Idle, no muting context
    eS1    := 10,  // 传感器 1 已激活（合法序列第 1 步） / Sensor 1 active, legal step one
    eMuted := 20,  // 静默有效（双传感器激活） / Muted, both sensors active
    eFault := 90   // 乱序故障（等复位） / Order fault, awaiting reset
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SmzErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SmzErr :
(
    eOk          := 0,   // 正常 / Normal
    eOrderBad    := 1,   // 故障级：传感器乱序（2 先于 1） / Fault: sensor order violation
    eCfgBad      := 2,   // 故障级：静默窗组态非法（<= T#0S） / Fault: mute window config illegal
    eMuteTimeout := 3    // 信息级：静默窗超时强制撤销 / Info: mute window timeout, forced revoke
);
END_TYPE

FUNCTION_BLOCK FB_DL_SafetyMuteZone
VAR_INPUT
    bMuteSen1    : BOOL := FALSE;     // 静默传感器 1（TRUE=被物料遮挡） [-] / Muting sensor 1, TRUE blocked
    bMuteSen2    : BOOL := FALSE;     // 静默传感器 2（TRUE=被物料遮挡） [-] / Muting sensor 2, TRUE blocked
    bLightCurtain: BOOL := FALSE;     // 光幕（TRUE=被遮挡，静默语境前提） [-] / Light curtain, TRUE blocked
    tMuteMax     : TIME := T#30S;     // 静默窗上限，域 > T#0S [ms] / Mute window ceiling
    bReset       : BOOL := FALSE;     // 复位（须传感器全释放后上升沿才清故障锁存） [-] / Reset, clears fault when sensors released
END_VAR
VAR_OUTPUT
    bMuted   : BOOL;                  // 静默有效指示（eMuted 相电平） [-] / Muted indicator
    bMuteFault: BOOL;                 // 乱序故障锁存（解除 = 全释放 ∧ 复位沿） [-] / Order fault latch
    ePhase   : E_DL_SmzPhase;         // 相位出口 [-] / Phase outlet
    eErrCode : E_DL_SmzErr;           // 错误码出口 / Error code outlet
    bError   : BOOL;                  // 故障标志（乱序或组态） [-] / Error flag
END_VAR
VAR
    _eState   : E_DL_SmzPhase := E_DL_SmzPhase.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _bFault   : BOOL;                 // 乱序故障锁存位（解除路径见头注释⑤） / Latched order fault bit
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bCfgLatch: BOOL;                 // 组态故障锁存位（解除沿 = 全释放 ∧ bReset 上升沿） / Latched config fault
    _bTimeout : BOOL;                 // 静默窗超时当拍量（信息级） [-] / Mute timeout this scan
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
    rtSen1    : R_TRIG;               // 传感器 1 激活沿实例，段 0 无条件调用 / Sensor 1 rising edge instance
    rtSen2    : R_TRIG;               // 传感器 2 激活沿实例，段 0 无条件调用 / Sensor 2 rising edge instance
    tonMuteMax: TON;                  // 静默窗 TON，段 0 无条件调用（IN 挂静默两相驻留，R145） / Mute window TON
END_VAR

(* —— 段 0：组态闸 + 全部沿/定时器无条件周期刷新（R6/R7） —— *)
_bCfgBad := (tMuteMax <= T#0S);       // 静默窗域闸 / Window configuration gate
rtReset(CLK := bReset);               // 复位沿，每拍必调 / Reset edge, every scan
rtSen1(CLK := bMuteSen1);             // 传感器 1 激活沿，每拍必调 / Sen 1 edge, every scan
rtSen2(CLK := bMuteSen2);             // 传感器 2 激活沿，每拍必调 / Sen 2 edge, every scan
tonMuteMax(IN := (_eState = E_DL_SmzPhase.eS1) OR (_eState = E_DL_SmzPhase.eMuted),
           PT := tMuteMax);           // 静默窗（覆盖 eS1/eMuted 全程，出相自复位） / Mute window covers both phases

(* —— 段 1：复位沿（须传感器全释放才清锁存，安全侧前提） —— *)
IF rtReset.Q AND (NOT bMuteSen1) AND (NOT bMuteSen2) THEN
    _bFault := FALSE;                 // 清乱序锁存（可达解除路径，头注释⑤） / Clear order fault
    _bCfgLatch := FALSE;              // 清组态锁存 / Clear config latch
    _eState := E_DL_SmzPhase.eIdle;   // 回待机 / Back to idle
END_IF
IF _bCfgBad AND (NOT _bCfgLatch) THEN
    _bCfgLatch := TRUE;               // 组态锁存 / Latch config fault
END_IF

(* —— 段 2：静默窗超时强制撤销（信息级；先于 CASE，撤销语义优先） —— *)
_bTimeout := tonMuteMax.Q AND (NOT _bFault) AND (NOT _bCfgLatch);   // 超时当拍量 / Timeout this scan
IF _bTimeout THEN
    _eState := E_DL_SmzPhase.eIdle;   // 强制撤销回待机（安全侧：光幕判据恢复有效） / Forced revoke to idle
END_IF

(* —— 段 3：四态顺控（故障/组态期冻结推进） —— *)
IF (NOT _bFault) AND (NOT _bCfgLatch) THEN
    CASE _eState OF

    E_DL_SmzPhase.eIdle:
        IF rtSen2.Q AND bLightCurtain THEN
            _bFault := TRUE;          // 乱序：sen2 先于 sen1 激活（规格③，归因唯一） / Order violation: sen 2 first
            _eState := E_DL_SmzPhase.eFault;   // 入故障相 / Enter fault
        ELSIF rtSen1.Q AND bLightCurtain THEN
            _eState := E_DL_SmzPhase.eS1;   // 合法第 1 步 / Legal step one
        END_IF

    E_DL_SmzPhase.eS1:
        IF rtSen2.Q THEN
            _eState := E_DL_SmzPhase.eMuted;   // 合法第 2 步：双激活静默 / Legal step two: muted
        ELSIF NOT bMuteSen1 THEN
            _eState := E_DL_SmzPhase.eIdle;   // sen1 提前释放：序列中止回待机 / Sequence aborted to idle
        END_IF

    E_DL_SmzPhase.eMuted:
        IF (NOT bMuteSen1) AND (NOT bMuteSen2) AND (NOT bLightCurtain) THEN
            _eState := E_DL_SmzPhase.eIdle;   // 双释放 ∧ 光幕恢复：静默结束 / Both released, curtain clear: end mute
        END_IF

    E_DL_SmzPhase.eFault:
        ;                            // 故障相驻留（由复位沿迁出链处理） / Held by reset chain

    ELSE
        _bFault := TRUE;             // 非法相位兜底（R45 配对见段 5） / Illegal phase fallback
        _eState := E_DL_SmzPhase.eFault;   // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
bMuted := (_eState = E_DL_SmzPhase.eMuted) AND (NOT _bFault) AND (NOT _bCfgLatch)
          AND (NOT _bTimeout);       // 静默有效出口（超时拍强制撤销） / Muted outlet
bMuteFault := _bFault;               // 故障锁存出口 / Fault latch outlet
ePhase := _eState;                   // 相位出口 / Phase outlet
IF _bCfgLatch THEN
    bError := TRUE;                  // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_SmzErr.eCfgBad; // 组态级码 / Config fault code
ELSIF _bFault THEN
    bError := TRUE;                  // 故障标志（乱序级） / Error flag
    eErrCode := E_DL_SmzErr.eOrderBad;   // 乱序锁存回放码（R189） / Order fault replay
ELSE
    bError := FALSE;                 // 无故障级条件 / No fault
    IF _bTimeout THEN
        eErrCode := E_DL_SmzErr.eMuteTimeout;   // 信息级：超时撤销 / Info: timeout revoke
    ELSE
        eErrCode := E_DL_SmzErr.eOk;            // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
