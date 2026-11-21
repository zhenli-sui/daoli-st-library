(*
  ==================================================================
  组件名 Component  : FB_DL_PassboxInterlockSeq
  分类   Category   : DL_Process
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.1
  功能   Purpose    : 传递窗（Passbox）A/B 门三段互锁顺控。三段分层（借 LBP
                      命令-监视-判定）：单门互斥仲裁（双侧命令同拍拒绝）→
                      入侧门开-放件-关门传递就绪 → 对侧门放行取件。门反馈矛盾
                      按保守侧处理（命令开而反馈关 = 视为门未开，不推进），
                      由确认窗超时兜底置故障。
  来源   Source     : t2-lbp（借鉴 LBP「命令-监视-判定」三段分层，clean-room
                      自研实现，未复制 LBP 任何源码行）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；传递窗双门互锁为
                      公开洁净室工艺语义。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_AirShowerInterlockSeq / FB_DL_ProofTestSeq 分工
                      ——本件只做传递窗双门互锁顺控，不做风淋吹扫与联锁
                      自证试验。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 双侧开门命令同拍互斥仲裁：A/B 请求同拍一律拒绝
                         （复位优先 = 安全侧不动作），置信息级单拍；
                      二 反馈矛盾保守侧：命令开而反馈关视为门未开，
                         只等待不推进，由 tOpenConfirm 超时兜底置故障；
                      三 组态配比约束（R100）：tTransferTo > tOpenConfirm，
                         越域判故障级；
                      四 锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 4 · 序号 19）
    2026-11-21  v1.0.1  R58 返修：bReqRejected 原全文件无清零路径（首次拒绝后
                        单拍信号永久保持，违反 R25 单拍标志生命周期三律），段 3b
                        新增每拍预清零点；置位点（段 4 eIdle 分支）不动，已核全
                        文无其它读点依赖其锁存语义（仅出口使用）。
  ==================================================================
*)

TYPE E_DL_PbiPhase :
(
    eIdle       := 0,  // 空闲：等单侧开门请求 / idle, waiting for a one side request
    eOpenIn     := 10, // 开入侧门：等门开反馈 / opening the entry door, waiting for the open feedback
    eWaitItem   := 20, // 传递就绪：等放件且入侧门复位 / the transfer ready, waiting for the item and the entry door closed
    eReleaseOut := 30, // 对侧放行：开出侧门等取件复位 / releasing the exit door, waiting for the pickup and closed
    eFault      := 90  // 故障：成因锁存 / fault, the cause latched
);
END_TYPE

TYPE E_DL_PbiFault :
(
    eNone        := 0, // 无成因 / no cause
    eCfgBad      := 1, // 组态非法：窗配比越域（故障级，与 bError 配对）/ an illegal config
    eOpenTimeout := 2, // 开门确认超时（含反馈矛盾保守等待）（故障级，与 bError 配对）/ an open confirm timeout
    eTrsTimeout  := 3, // 传递 / 取件超时（故障级，与 bError 配对）/ a transfer or pickup timeout
    ePhaseBad    := 4  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_PassboxInterlockSeq
VAR_INPUT
    bEnable      : BOOL := TRUE;   // 使能，失能即冻结顺控回空闲 [-] / enable, disabling freezes the sequence
    bReset       : BOOL := FALSE;  // 复位上升沿清锁存 [-] / reset rising edge clears the latch
    bReqOpenA    : BOOL := FALSE;  // A 侧开门请求电平 [-] / the A side open request level
    bReqOpenB    : BOOL := FALSE;  // B 侧开门请求电平 [-] / the B side open request level
    bDoorAClosed : BOOL := TRUE;   // A 门关到位反馈 [-] / the A door closed feedback
    bDoorBClosed : BOOL := TRUE;   // B 门关到位反馈 [-] / the B door closed feedback
    bItemReady   : BOOL := FALSE;  // 传递就绪（工件已放入且入侧门复位）[-] / the item placed and the entry door closed
    tOpenConfirm : TIME := T#10S;  // 开门确认窗 [毫秒] / the open confirm window [millisecond]
    tTransferTo  : TIME := T#120S; // 传递 / 取件超时窗 [毫秒]，域 大于 tOpenConfirm / the transfer timeout, above the open confirm
END_VAR
VAR_OUTPUT
    bCmdOpenA    : BOOL := FALSE; // A 门开门命令输出 [-] / the A door open command outlet
    bCmdOpenB    : BOOL := FALSE; // B 门开门命令输出 [-] / the B door open command outlet
    bPermitTrs   : BOOL := FALSE; // 对侧放行指示（B 侧可开取件）[-] / the exit release indicator
    bReqRejected : BOOL := FALSE; // 双侧同拍拒绝信息级单拍 [-] / the dual request rejected pulse
    ePhase       : E_DL_PbiPhase := E_DL_PbiPhase.eIdle; // 相位出口 [枚举] / the phase outlet
    eFault       : E_DL_PbiFault := E_DL_PbiFault.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError       : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    rtReqA   : R_TRIG; // A 请求沿检测，段 0 无条件刷新 / the A request edge
    rtReqB   : R_TRIG; // B 请求沿检测，段 0 无条件刷新 / the B request edge
    tonOpen  : TON;    // 开门确认窗，段 0 无条件刷新 / the open confirm window
    tonTrs   : TON;    // 传递 / 取件超时窗，段 0 无条件刷新 / the transfer timeout
    _ePhase  : E_DL_PbiPhase := E_DL_PbiPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC  : E_DL_PbiFault := E_DL_PbiFault.eNone; // 故障级成因，锁存至复位沿 / the fault cause, latched
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _bCfgOk  : BOOL := FALSE; // 组态域内 [-] / the config inside the domain
    _bAtoB   : BOOL := TRUE;  // 传递方向记忆：TRUE = A 进 B 出 [-] / the direction memory, true for A in B out
    _bInWasOp: BOOL := FALSE; // 入侧门曾开标记（防取件段误判）[-] / the entry door was open flag
    _bOutWasOp: BOOL := FALSE; // 出侧门曾开标记 [-] / the exit door was open flag
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
rtReqA(CLK := bReqOpenA); // A 请求沿 / the A request edge
rtReqB(CLK := bReqOpenB); // B 请求沿 / the B request edge
tonOpen(IN := (_ePhase = E_DL_PbiPhase.eOpenIn) AND (NOT _bFault) AND bEnable, PT := tOpenConfirm); // 开门确认窗，IN 串开门相闸 / the confirm window gated by the open phase
tonTrs(IN := ((_ePhase = E_DL_PbiPhase.eWaitItem) OR (_ePhase = E_DL_PbiPhase.eReleaseOut)) AND (NOT _bFault) AND bEnable, PT := tTransferTo); // 传递超时窗，IN 串传递 / 放行相闸 / the timeout gated by the transfer phases

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清锁存 / 清方向与曾开标记 / 迁空闲（三项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_PbiFault.eNone; // 作用域一：清成因 / scope one, clear the cause
    _bAtoB := TRUE; // 作用域二：方向记忆回默认 / scope two, the memory to default
    _bInWasOp := FALSE; // 作用域二：清入侧曾开 / scope two, clear the entry flag
    _bOutWasOp := FALSE; // 作用域二：清出侧曾开 / scope two, clear the exit flag
    _ePhase := E_DL_PbiPhase.eIdle; // 作用域三：迁空闲相 / scope three, back to idle
END_IF

// 段 3｜组态域闸：窗配比（R100，边界三）/ segment 3, the config gate, the window pairing
_bCfgOk := (tTransferTo > tOpenConfirm) AND (tOpenConfirm > T#0S); // 传递窗 > 确认窗配比 / the transfer above confirm pairing
IF NOT _bCfgOk THEN // 配比越域 / a pairing violation
    IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PbiFault.eCfgBad; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PbiPhase.eFault; // 迁故障相 / migrate to fault
    END_IF
END_IF

// 段 3b｜单拍标志预清零（v1.0.1，R25：有置位点必须有每拍清零点）/ segment 3b, the single shot preset clear
bReqRejected := FALSE; // 双侧拒绝单拍标志每拍预清（置位点在段 4 eIdle 分支）/ the reject pulse preset false each scan, raised in the idle branch

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_PbiPhase.eIdle: // 空闲相：单门互斥仲裁（边界一）/ the idle phase, the single door arbitration
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PbiPhase.eIdle; // 停摆驻留 / dwell
    ELSIF rtReqA.Q AND rtReqB.Q THEN // 双侧同拍请求一律拒绝（复位优先 = 安全侧不动作）/ the dual same scan requests rejected
        bReqRejected := TRUE; // 信息级拒绝单拍 / the informational reject pulse
    ELSIF rtReqA.Q AND bDoorBClosed AND (NOT bReqOpenB) THEN // A 请求且对侧门关 / an A request with the other door closed
        _bAtoB := TRUE; // 方向 A 进 B 出 / the direction A in B out
        _ePhase := E_DL_PbiPhase.eOpenIn; // 迁开门相 / migrate to open
    ELSIF rtReqB.Q AND bDoorAClosed AND (NOT bReqOpenA) THEN // B 请求且对侧门关 / a B request with the other door closed
        _bAtoB := FALSE; // 方向 B 进 A 出 / the direction B in A out
        _ePhase := E_DL_PbiPhase.eOpenIn; // 迁开门相 / migrate to open
    END_IF

E_DL_PbiPhase.eOpenIn: // 开入侧门相：等门开反馈（边界二保守侧：反馈矛盾只等待）/ the open phase, conservative on a feedback contradiction
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PbiPhase.eIdle; // 回空闲相 / back to idle
    ELSIF (NOT bDoorAClosed) AND _bAtoB THEN // A 门已开反馈 / the A door open feedback
        _bInWasOp := TRUE; // 记曾开 / mark the open
        _ePhase := E_DL_PbiPhase.eWaitItem; // 迁就绪相 / migrate to ready
    ELSIF (NOT bDoorBClosed) AND (NOT _bAtoB) THEN // B 门已开反馈 / the B door open feedback
        _bInWasOp := TRUE; // 记曾开 / mark the open
        _ePhase := E_DL_PbiPhase.eWaitItem; // 迁就绪相 / migrate to ready
    ELSIF tonOpen.Q THEN // 确认窗超时（含命令开而反馈关的矛盾保守等待）/ the confirm timeout, covering the contradiction wait
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PbiFault.eOpenTimeout; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PbiPhase.eFault; // 迁故障相 / migrate to fault
    END_IF

E_DL_PbiPhase.eWaitItem: // 传递就绪相：等放件且入侧门复位 / the ready phase, the item and the entry door closed
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PbiPhase.eIdle; // 回空闲相 / back to idle
    ELSIF bItemReady AND _bInWasOp THEN // 就绪且入侧门曾开 / ready and the entry was open
        _ePhase := E_DL_PbiPhase.eReleaseOut; // 迁放行相（方向由出口映射消化）/ migrate to release
    ELSIF tonTrs.Q THEN // 传递超时 / the transfer timeout
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PbiFault.eTrsTimeout; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PbiPhase.eFault; // 迁故障相 / migrate to fault
    END_IF

E_DL_PbiPhase.eReleaseOut: // 对侧放行相：等取件且出侧门复位 / the release phase, the pickup and the exit door closed
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PbiPhase.eIdle; // 回空闲相 / back to idle
    ELSIF (NOT bDoorBClosed) AND _bAtoB THEN // B 门已开 / the B door open
        _bOutWasOp := TRUE; // 记曾开 / mark the open
    ELSIF (NOT bDoorAClosed) AND (NOT _bAtoB) THEN // A 门已开 / the A door open
        _bOutWasOp := TRUE; // 记曾开 / mark the open
    ELSIF _bOutWasOp AND bDoorAClosed AND bDoorBClosed THEN // 取件完成双侧门复位 / the pickup done, both doors closed
        _bOutWasOp := FALSE; // 清曾开标记 / clear the flag
        _bInWasOp := FALSE; // 清入侧曾开 / clear the entry flag
        _ePhase := E_DL_PbiPhase.eIdle; // 回空闲相 / back to idle
    ELSIF tonTrs.Q THEN // 取件超时 / the pickup timeout
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PbiFault.eTrsTimeout; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PbiPhase.eFault; // 迁故障相 / migrate to fault
    END_IF

E_DL_PbiPhase.eFault: // 故障相：成因锁存，等复位沿；命令输出安全侧断开 / the fault phase, the commands open on the safe side
ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_PbiFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause
    _ePhase := E_DL_PbiPhase.eFault; // 迁故障相 / migrate to fault
END_CASE

// 段 5｜统一出口：命令输出按方向与相位单点映射 / segment 5, the unified outlet
IF (_ePhase = E_DL_PbiPhase.eOpenIn) OR (_ePhase = E_DL_PbiPhase.eWaitItem) THEN // 入侧命令段 / the entry command segment
    IF _bAtoB THEN // A 进 / A in
        bCmdOpenA := (_ePhase = E_DL_PbiPhase.eOpenIn); // 开门命令只在开门相保持 / the command held only in the open phase
        bCmdOpenB := FALSE; // 对侧命令断开 / the other command open
    ELSE // B 进 / B in
        bCmdOpenB := (_ePhase = E_DL_PbiPhase.eOpenIn); // 开门命令 / the command
        bCmdOpenA := FALSE; // 对侧命令断开 / the other command open
    END_IF
ELSIF _ePhase = E_DL_PbiPhase.eReleaseOut THEN // 对侧放行段 / the release segment
    IF _bAtoB THEN // B 出 / B out
        bCmdOpenA := FALSE; // 入侧命令断开 / the entry command open
        bCmdOpenB := TRUE; // 出侧命令保持 / the exit command held
    ELSE // A 出 / A out
        bCmdOpenB := FALSE; // 入侧命令断开 / the entry command open
        bCmdOpenA := TRUE; // 出侧命令保持 / the exit command held
    END_IF
    bPermitTrs := TRUE; // 放行指示 / the release indicator
ELSE // 其余相位命令全断（安全侧）/ the other phases open all commands
    bCmdOpenA := FALSE; // A 命令断开 / the A command open
    bCmdOpenB := FALSE; // B 命令断开 / the B command open
    bPermitTrs := FALSE; // 放行指示断开 / the release indicator open
END_IF
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eFault := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
ELSE // 无锁存 / no latch
    eFault := E_DL_PbiFault.eNone; // 无成因 / no cause
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the flag shares the latch
END_FUNCTION_BLOCK
