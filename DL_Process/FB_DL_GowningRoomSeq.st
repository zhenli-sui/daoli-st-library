(*
  ==================================================================
  组件名 Component  : FB_DL_GowningRoomSeq
  分类   Category   : DL_Process
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 洁净室更衣室顺控。进入请求 → 开入侧门（人进 + 门关反
                      馈）→ 更衣中（完成信号或时限）→ 开出侧门（人出 + 门
                      关反馈）→ 回空闲。双门互锁绝不同开（双命令硬互锁）；
                      更衣时限超时判故障；与 AirShowerInterlockSeq /
                      PassboxInterlockSeq 构成人流三件（ROADMAP 1087 行）。
  来源   Source     : roadmap-p2（R56 评估项落地）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；更衣室双门互锁
                      为公开洁净室工艺语义，clean-room 自研实现，未复制任何
                      厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_AirShowerInterlockSeq 分工——风淋件做吹扫除
                      尘互锁，本件只做更衣流程双门顺控；与
                      FB_DL_PassboxInterlockSeq 分工——传递窗做物件传递，
                      本件做人员进出，两者门数与传感语义不同。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 双门硬互锁：bDoorInCmd 与 bDoorOutCmd 互为反闸（统
                         一出口单点映射保证绝不同时为真，命令级互锁）；
                      二 更衣时限 tGownMax（执行相看门狗，使能只用相驻留
                         R145）；超时判故障级锁存，双门命令安全侧全断；
                      三 等待类相退出条件 ≥2（R98）：eEnterExit 相 = 人出
                         检测沿或门关反馈（事件）+ 门关前置消失；eChanging
                         相 = 更衣完成信号（事件）+ 时限超时（前置消失）；
                      四 门确认窗配比约束（R100）：tDoorConfirm < tGownMax；
                         越域判故障级；
                      五 故障锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 4 · 序号 14）
  ==================================================================
*)

TYPE E_DL_GrpPhase :
(
    eGrpIdle    := 0,  // 空闲：双门关闭等请求 / idle, both doors closed
    eGrpEnter   := 10, // 进入：入侧门开，等人进且门关 / entering, the inner door open
    eGrpChanging:= 20, // 更衣中：双门全闭，等完成信号或时限 / changing, both doors closed
    eGrpExit    := 30, // 离开：出侧门开，等人出且门关 / exiting, the outer door open
    eGrpFault   := 90  // 故障锁存 / the latched fault
);
END_TYPE

TYPE E_DL_GrpFault :
(
    eNone         := 0, // 无成因 / no cause
    eCfgBad       := 1, // 组态非法：门确认窗与更衣时限配比越域（故障级，与 bError 配对）/ an illegal config
    eDoorInTo     := 2, // 入侧门确认超时（故障级，与 bError 配对）/ an inner door confirm timeout
    eGownTimeout  := 3, // 更衣时限超时（故障级，与 bError 配对）/ a gowning timeout
    eDoorOutTo    := 4, // 出侧门确认超时（故障级，与 bError 配对）/ an outer door confirm timeout
    ePhaseBad     := 5  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_GowningRoomSeq
VAR_INPUT
    bEnable      : BOOL := TRUE;   // 使能，失能回空闲双门关 [-] / enable, disabling returns idle with both doors closed
    bReset       : BOOL := FALSE;  // 复位上升沿清故障锁存 [-] / reset rising edge clears the latch
    bReqEnter    : BOOL := FALSE;  // 进入请求电平 [-] / the enter request level
    bDoorInClosed: BOOL := TRUE;   // 入侧门关到位反馈 [-] / the inner door closed feedback
    bDoorOutClosed: BOOL := TRUE;  // 出侧门关到位反馈 [-] / the outer door closed feedback
    bPersonIn    : BOOL := FALSE;  // 室内有人检测（更衣室内）[-] / the person inside detection
    bGownDone    : BOOL := FALSE;  // 更衣完成信号（更衣室按钮或工装传感）[-] / the gowning done signal
    tDoorConfirm : TIME := T#10S;  // 门开确认窗 [毫秒] / the door confirm window [millisecond]
    tGownMax     : TIME := T#300S; // 更衣时限 [毫秒] / the gowning max duration [millisecond]
END_VAR
VAR_OUTPUT
    bDoorInCmd : BOOL := FALSE; // 入侧门开门命令输出 [-] / the inner door open command outlet
    bDoorOutCmd: BOOL := FALSE; // 出侧门开门命令输出 [-] / the outer door open command outlet
    bChanging  : BOOL := FALSE; // 更衣进行指示 [-] / the changing indicator
    ePhase     : E_DL_GrpPhase := E_DL_GrpPhase.eGrpIdle; // 相位出口 [枚举] / the phase outlet
    eFault     : E_DL_GrpFault := E_DL_GrpFault.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError     : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    tonDoor : TON;    // 门开确认窗，段 0 无条件刷新（入 / 出两相共用，相闸区分）/ the door confirm window shared by both door phases
    tonGown : TON;    // 更衣时限窗，段 0 无条件刷新 / the gowning max window
    _ePhase : E_DL_GrpPhase := E_DL_GrpPhase.eGrpIdle; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC : E_DL_GrpFault := E_DL_GrpFault.eNone; // 故障级成因，锁存至复位沿 / the fault cause latched
    _bFault : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bCfgOk : BOOL := FALSE; // 组态域内 [-] / the config inside the domain
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，FB50-1）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonDoor(IN := ((_ePhase = E_DL_GrpPhase.eGrpEnter) OR (_ePhase = E_DL_GrpPhase.eGrpExit)) AND (NOT _bFault) AND bEnable, PT := tDoorConfirm); // 门确认窗，IN 串两个开门相闸 / the door window gated by the two open phases
tonGown(IN := (_ePhase = E_DL_GrpPhase.eGrpChanging) AND (NOT _bFault) AND bEnable, PT := tGownMax); // 更衣时限窗，IN 串更衣相闸（纯相驻留，R145）/ the gown window gated by the changing phase

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 迁空闲（两项逐项声明，边界五）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_GrpFault.eNone; // 作用域一：清成因 / scope one, clear the cause
    _ePhase := E_DL_GrpPhase.eGrpIdle; // 作用域二：迁空闲相 / scope two, back to idle
END_IF

// 段 3｜组态域闸（边界四，R100 配比：门确认窗 < 更衣时限）/ segment 3, the config gate
_bCfgOk := (tDoorConfirm > T#0S) AND (tGownMax > tDoorConfirm); // 确认窗域与配比判定 / the window domain and the pairing verdict
IF NOT _bCfgOk THEN // 配比越域 / a pairing violation
    IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_GrpFault.eCfgBad; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_GrpPhase.eGrpFault; // 迁故障相（锁存与迁相同分支，FB50-1）/ migrate to the fault phase
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_GrpPhase.eGrpIdle: // 空闲相：等进入请求（双门关反馈一致性预检）/ the idle phase, awaiting the enter request
    IF NOT bEnable THEN // 失能驻留 / dwell while disabled
        _ePhase := E_DL_GrpPhase.eGrpIdle; // 停摆驻留 / dwell
    ELSIF bReqEnter AND bDoorInClosed AND bDoorOutClosed AND (NOT _bFault) THEN // 请求且双门关确认 / a request with both doors confirmed closed
        _ePhase := E_DL_GrpPhase.eGrpEnter; // 迁进入相 / migrate to the enter phase
    END_IF

E_DL_GrpPhase.eGrpEnter: // 进入相：入侧门开，等人进且门关（R98 事件 + 前置消失）/ the enter phase
    IF NOT bEnable THEN // 失能回空闲 / a disable returns idle
        _ePhase := E_DL_GrpPhase.eGrpIdle; // 回空闲相 / back to idle
    ELSIF bPersonIn AND bDoorInClosed THEN // 人进且入侧门关（事件与前置消失双条件）/ the person in with the door closed
        _ePhase := E_DL_GrpPhase.eGrpChanging; // 迁更衣相 / migrate to the changing phase
    ELSIF tonDoor.Q THEN // 门确认窗超时（R190 独立成因）/ the door confirm timeout, an independent cause
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_GrpFault.eDoorInTo; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_GrpPhase.eGrpFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_GrpPhase.eGrpChanging: // 更衣相：双门全闭，等完成信号或时限（边界三双出口）/ the changing phase, the dual exit
    IF NOT bEnable THEN // 失能回空闲（R191 显式：门命令安全侧全断）/ a disable returns idle
        _ePhase := E_DL_GrpPhase.eGrpIdle; // 回空闲相 / back to idle
    ELSIF bGownDone THEN // 更衣完成信号（事件）/ the gowning done event
        _ePhase := E_DL_GrpPhase.eGrpExit; // 迁离开相 / migrate to the exit phase
    ELSIF tonGown.Q THEN // 更衣时限超时（前置消失路径，R190 独立成因）/ the gown timeout, the precondition lost path
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_GrpFault.eGownTimeout; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_GrpPhase.eGrpFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_GrpPhase.eGrpExit: // 离开相：出侧门开，等人出且门关 / the exit phase
    IF NOT bEnable THEN // 失能回空闲 / a disable returns idle
        _ePhase := E_DL_GrpPhase.eGrpIdle; // 回空闲相 / back to idle
    ELSIF (NOT bPersonIn) AND bDoorOutClosed THEN // 人出且出侧门关 / the person out with the door closed
        _ePhase := E_DL_GrpPhase.eGrpIdle; // 回空闲相 / back to idle
    ELSIF tonDoor.Q THEN // 门确认窗超时（R190 独立成因）/ the door confirm timeout
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_GrpFault.eDoorOutTo; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_GrpPhase.eGrpFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_GrpPhase.eGrpFault: // 故障相：成因锁存等复位沿；双门命令安全侧全断 / the fault phase
ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_GrpFault.ePhaseBad; // 故障级成因（R45 配对）/ the fault cause
    _ePhase := E_DL_GrpPhase.eGrpFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口：双门互锁单点映射（边界一）/ segment 5, the unified outlet with the interlock
bDoorInCmd := (_ePhase = E_DL_GrpPhase.eGrpEnter) AND bEnable AND (NOT _bFault); // 入侧命令仅进入相（互锁）/ the inner command in the enter phase only
bDoorOutCmd := (_ePhase = E_DL_GrpPhase.eGrpExit) AND bEnable AND (NOT _bFault); // 出侧命令仅离开相（互锁）/ the outer command in the exit phase only
bChanging := _ePhase = E_DL_GrpPhase.eGrpChanging; // 更衣指示 / the changing indicator
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eFault := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
ELSE // 无锁存 / no latch
    eFault := E_DL_GrpFault.eNone; // 无成因 / no cause
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the flag shares the latch
END_FUNCTION_BLOCK
