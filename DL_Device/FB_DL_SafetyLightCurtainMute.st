// FB_DL_SafetyLightCurtainMute v1.0.0
(*==============================================================================
 * 功能描述: C4 安全光栅消隐。双传感器方向判别消隐状态机：eIdle→eArmed→eMuted→
 *           eRestore→eIdle；双模式下行进方向须 S1 先 S2 后（tDirWin 窗内），方向
 *           错误或消隐超窗 tMuteMax 进 eFault 锁存；单模式下光束遮挡直接进入消隐。
 *           bMuteOut 仅在 eMuted 合法窗口励磁——消隐只放行物料方向判别通过，不屏蔽
 *           任何人体进入判别（muted 不等于屏蔽危险），eFault 相 bMuteOut 强制断磁。
 * 接口契约: 输入 bS1/bS2/bDualMode/bMuteReq/tDirWin/tMuteMax/bReset；
 *           输出 bMuteOut/eState/eCause/bError/nErrId。
 * 边界: ① 组态闸：tDirWin<=T#0S、tMuteMax<=T#0S → 故障锁存；② 三枚 R_TRIG + 两枚
 *           TON 段 0 无条件周期刷新；③ 恢复相再次遮挡判超窗违约（安全侧，不续窗）；
 *           ④ 零全局耦合。
 * 码表: 16#0007_0303 故障级总码（组态非法/方向违约/消隐超窗/非法相位，锁存至 bReset
 *       上升沿且光束全清）；16#0007_0403 信息级：消隐窗口有效（励磁中，每拍重算）。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

TYPE E_DL_SlcState :
(
    eIdle    := 0,    // 待命（光束清、无请求）/ Idle, beams clear, no request
    eArmed   := 10,   // 已布防（等待方向判别）/ Armed, awaiting direction discrimination
    eMuted   := 20,   // 消隐励磁中 / Muted, output energised
    eRestore := 30,   // 恢复相（等待光束全清）/ Restore, awaiting beams clear
    eFault   := 90    // 故障锁存相（复位沿 + 光束全清迁出）/ Fault latched
);
END_TYPE

TYPE E_DL_SlcCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eDirWrong   := 2,   // 方向判别违约（S2 先于 S1）/ Direction violation, S2 before S1
    eMuteOver   := 3,   // 消隐超窗或恢复相再遮挡 / Mute window overrun or re-break in restore
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_SafetyLightCurtainMute
VAR_INPUT
    bS1       : BOOL := FALSE;       // 传感器 1（行进侧首束，TRUE=被遮挡）[-] / Sensor 1, entry side, TRUE = blocked
    bS2       : BOOL := FALSE;       // 传感器 2（行进侧次束，TRUE=被遮挡）[-] / Sensor 2, second beam, TRUE = blocked
    bDualMode : BOOL := TRUE;        // 双传感器方向判别模式（FALSE=单传感器）[-] / Dual-sensor direction mode, FALSE = single
    bMuteReq  : BOOL := FALSE;       // 消隐请求（安全控制器电平）[-] / Mute request from safety controller
    tDirWin   : TIME := T#500MS;     // S1→S2 方向判别窗，域 > T#0S [ms] / Direction window, domain > T#0S
    tMuteMax  : TIME := T#10S;       // 消隐最大励磁窗，域 > T#0S [ms] / Maximum mute window, domain > T#0S
    bReset    : BOOL := FALSE;       // 复位，上升沿清故障锁存 [-] / Reset edge clears fault
END_VAR
VAR_OUTPUT
    bMuteOut  : BOOL;                // 消隐励磁输出（仅合法窗口 TRUE）[-] / Mute output, energised in legal window only
    eState    : E_DL_SlcState;       // 状态出口，段尾单点映射 / State outlet
    eCause    : E_DL_SlcCause;       // 故障成因出口（归因唯一） / Fault cause outlet
    bError    : BOOL;                // 故障锁存标志 [-] / Fault latch flag
    nErrId    : UDINT;               // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    _eState  : E_DL_SlcState := E_DL_SlcState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_SlcCause := E_DL_SlcCause.eNone;   // 故障成因锁存量 / Latched cause
    rtS1     : R_TRIG;               // S1 上升沿实例，段 0 无条件刷新 / S1 rising edge instance
    rtS2     : R_TRIG;               // S2 上升沿实例，段 0 无条件刷新 / S2 rising edge instance
    rtReset  : R_TRIG;               // 复位沿实例，段 0 无条件刷新 / Reset edge instance
    tonDir   : TON;                  // 方向判别窗计时（S1 遮挡期间），段 0 无条件刷新 / Direction window timer
    tonMute  : TON;                  // 消隐励磁窗计时，段 0 无条件刷新 / Mute window timer
    _bCfgBad : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration this scan
    _bFault  : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault  : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo   : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
    _bClear  : BOOL;                 // 光束全清当拍量 [-] / All beams clear this scan
    _bArmedOk: BOOL;                 // 布防前置成立当拍量 [-] / Arming precondition this scan
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtS1(CLK := bS1);                                                  // S1 沿，每拍必调 / S1 edge every scan
rtS2(CLK := bS2);                                                  // S2 沿，每拍必调 / S2 edge every scan
rtReset(CLK := bReset);                                            // 复位沿，每拍必调 / Reset edge every scan
tonDir(IN := (_eState = E_DL_SlcState.eArmed) AND bS1, PT := tDirWin);    // 方向窗（布防相 S1 遮挡期）/ Direction timer while armed and S1 blocked
tonMute(IN := (_eState = E_DL_SlcState.eMuted), PT := tMuteMax);   // 消隐窗（励磁相独占）/ Mute timer while muted

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_eCause 不入清单） —— *)
bError := FALSE;                                                   // 故障标志预清（置位处同拍回填） / Error flag preset
bMuteOut := FALSE;                                                 // 励磁输出预清（eMuted 相回填） / Mute output preset
_uInfo := 16#0000_0000;                                            // 信息码每拍重算 / Info recomputed every scan
nErrId := 16#0000_0000;                                            // 事件码缺省无事件 / Event code default none
_bClear := (NOT bS1) AND (NOT bS2);                                // 光束全清当拍量 / Beams clear this scan
_bArmedOk := _bClear AND bMuteReq AND (NOT _bFault);               // 布防前置：光束清 + 请求在 / Arming precondition

(* —— 段 2：组态域闸 —— *)
_bCfgBad := (tDirWin <= T#0S) OR (tMuteMax <= T#0S);               // 时间域闸（防窗口恒成立） / Time domain gates

(* —— 段 3：故障锁存与解除（R45 配对；解除沿 = 复位沿 + 组态合法 + 光束全清） —— *)
IF _bCfgBad THEN                                                   // 组态非法 / Illegal configuration
    _uFault := 16#0007_0303;                                       // 故障级总码 / Fault-level code
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SlcCause.eCfgIllegal;                          // 归因：组态非法 / Cause: illegal configuration
END_IF
IF rtReset.Q AND (NOT _bCfgBad) AND _bClear THEN                   // 解除沿（当拍量，光束全清） / Release edge with beams clear
    _bFault := FALSE;                                              // 清故障锁存 / Clear fault latch
    _uFault := 16#0000_0000;                                       // 清故障码 / Clear fault code
    _eCause := E_DL_SlcCause.eNone;                                // 清成因 / Clear cause
    IF _eState = E_DL_SlcState.eFault THEN
        _eState := E_DL_SlcState.eIdle;                            // 故障相唯一迁出路径 / Sole exit from fault phase
    END_IF
END_IF

(* —— 段 4：相位机（ENUM 全成员显式标签 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_SlcState.eIdle:
    IF _bFault THEN                                                // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_SlcState.eFault;
    ELSIF _bArmedOk THEN                                           // 出口 2：前置成立进布防 / Preconditions met, arm
        _eState := E_DL_SlcState.eArmed;
    END_IF

E_DL_SlcState.eArmed:
    IF _bFault THEN                                                // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_SlcState.eFault;
    ELSIF (NOT bMuteReq) OR _bCfgBad THEN                          // 出口 2：请求撤销或组态坏 → 回待命 / Request dropped, back to idle
        _eState := E_DL_SlcState.eIdle;
    ELSIF bDualMode THEN                                           // 双传感器模式分支 / Dual-sensor branch
        IF rtS2.Q AND (NOT bS1) THEN                               // 方向违约：S2 先遮挡而 S1 未遮挡 / Direction violation, S2 first
            _uFault := 16#0007_0303;
            _bFault := TRUE;
            bError  := TRUE;
            _eCause := E_DL_SlcCause.eDirWrong;                    // 归因：方向违约 / Cause: direction violation
            _eState := E_DL_SlcState.eFault;
        ELSIF rtS2.Q AND bS1 THEN                                  // 合法方向：S1 已遮挡后 S2 到 → 进励磁 / Legal direction, enter muted
            _eState := E_DL_SlcState.eMuted;
        ELSIF tonDir.Q THEN                                        // S1 遮挡超方向窗（判别失败安全退） / S1 blocked over direction window
            _eState := E_DL_SlcState.eIdle;
        END_IF
    ELSE                                                           // 单传感器模式：遮挡即励磁 / Single mode, block enters muted
        IF bS1 THEN
            _eState := E_DL_SlcState.eMuted;
        END_IF
    END_IF

E_DL_SlcState.eMuted:
    IF _bFault THEN                                                // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_SlcState.eFault;
    ELSIF tonMute.Q THEN                                           // 出口 2：励磁超最大窗 → 强制恢复 / Mute window overrun
        _uFault := 16#0007_0303;                                   // 故障级：消隐超窗（超窗不续磁） / Fault, window overrun
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_SlcCause.eMuteOver;                        // 归因：超窗 / Cause: window overrun
        _eState := E_DL_SlcState.eRestore;
    ELSIF (NOT bMuteReq) THEN                                      // 出口 3：请求撤销进恢复 / Request dropped, restore
        _eState := E_DL_SlcState.eRestore;
    ELSE
        _uInfo := 16#0007_0403;                                    // 信息级：消隐励磁中 / Info: mute energised
    END_IF

E_DL_SlcState.eRestore:
    IF _bFault THEN                                                // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_SlcState.eFault;
    ELSIF bS1 OR bS2 THEN                                          // 出口 2：恢复相再遮挡 = 违约（不续窗，安全侧） / Re-break in restore, fault
        _uFault := 16#0007_0303;
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_SlcCause.eMuteOver;                        // 归因：恢复相再遮挡 / Cause: re-break in restore
        _eState := E_DL_SlcState.eFault;
    ELSE
        _eState := E_DL_SlcState.eIdle;                            // 出口 3：光束全清回待命 / Beams clear, back to idle
    END_IF

E_DL_SlcState.eFault:
    ;                                                              // 故障相：仅段 3 解除沿可迁出（励磁强制断） / Only the release edge leaves, output forced off

ELSE
    _uFault := 16#0007_0303;                                       // 故障级：非法相位兜底 / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SlcCause.ePhaseBad;                            // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_SlcState.eFault;                               // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：出口单点映射（名实同源；锁存码回放；故障相励磁强制断） —— *)
IF (_eState = E_DL_SlcState.eMuted) AND (NOT _bFault) THEN
    bMuteOut := TRUE;                                              // 仅合法励磁相输出 / Output only in legal muted phase
END_IF
IF _bFault THEN
    nErrId := _uFault;                                             // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                              // 信息码 / Info code
END_IF
bError := _bFault;                                                 // 故障标志与锁存同源 / Flag from latch
eState := _eState;                                                 // 状态出口 / State outlet
eCause := _eCause;                                                 // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
