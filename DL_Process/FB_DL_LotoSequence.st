(*
  ==================================================================
  组件名 Component  : FB_DL_LotoSequence
  分类   Category   : DL_Process
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : LOTO 上锁挂牌流程（OSHA 公开流程语义）。能量隔离点逐
                      点确认（8 点上限）+ 挂牌台账确认 → 上锁 eLocked；解锁
                      前试启验证窗：窗内出现运动反馈（bMotionFb）判隔离失效
                      锁存 eFault，窗到期无运动才放行 eUnlocked。与
                      FB_DL_GuardLockDoor 单门互锁分工。
  来源   Source     : self-std（OSHA LOTO 公开流程语义）
  溯源   Origin     : OSHA 1910.147 上锁挂牌公开流程语义，clean-room 自研
                      实现，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_GuardLockDoor 分工——后者做单门互锁，本件
                      做多能量隔离点 LOTO 流程。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 安全语义：eFault / eIsolate / eIdle 相 bLocked 强制
                         假（安全侧只有 eLocked / eTryVerify 两相上锁口径）；
                      二 试启验证窗到期即放行（窗口末退出迁移，纪律④）；窗
                         内运动反馈 = 隔离失效（独立成因 bFault，R190）；
                      三 上锁判据 = 全部隔离点确认 AND 挂牌台账完成（双闸缺
                         一不迁相）；
                      四 组态域闸：nIsoCnt ∈ [1..8]，越域锁存 bError（解除
                         = bReset 沿，R188）；故障解除路径 = bReset 沿（唯
                         一路径，R188 声明）；
                      五 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 3 · 序号 15）
  ==================================================================
*)

TYPE E_DL_LotoPhase :
(
    eLotoIdle      := 0,  // 空闲：等上锁请求 / idle, awaiting the lock request
    eLotoIsolate   := 10, // 隔离确认：逐点确认与挂牌 / the isolating confirm
    eLotoLocked    := 20, // 已上锁：隔离生效 / the locked state
    eLotoTryVerify := 30, // 解锁前试启验证窗 / the try start verify window
    eLotoUnlocked  := 40, // 已解锁：验证通过放行 / the unlocked state
    eLotoFault     := 90  // 隔离失效锁存：仅复位可清 / the isolation failure latch
);
END_TYPE

FUNCTION_BLOCK FB_DL_LotoSequence
VAR_INPUT
    aIsoCfm    : ARRAY[0..7] OF BOOL; // 隔离点逐点确认组（TRUE = 已隔离确认）[-] / the isolation point confirms
    nIsoCnt    : INT  := 4;      // 隔离点数 [点]，域 1..8 / the isolation point count, one through eight
    bTagLedger : BOOL := FALSE;  // 挂牌台账完成确认 [-] / the tag ledger completed confirm
    bReqLock   : BOOL := FALSE;  // 上锁请求，上升沿生效 [-] / the lock request, rising edge effective
    bReqUnlock : BOOL := FALSE;  // 解锁请求，上升沿生效 [-] / the unlock request, rising edge effective
    bMotionFb  : BOOL := FALSE;  // 试启运动反馈，TRUE = 检测到转动 [-] / the try start motion feedback, true = motion detected
    tTryWin    : TIME := T#10S; // 试启验证窗 [毫秒] / the try start verify window [millisecond]
    bReset     : BOOL := FALSE; // 故障与组态复位，上升沿生效 [-] / the fault and config reset, rising edge
END_VAR
VAR_OUTPUT
    eState     : E_DL_LotoPhase := E_DL_LotoPhase.eLotoIdle; // 流程状态输出 [-] / the process state outlet
    bLocked    : BOOL := FALSE; // 上锁口径输出（eLocked / eTryVerify 两相）[-] / the locked verdict outlet
    bReadyUnlock: BOOL := FALSE; // 解锁放行指示（eUnlocked 相）[-] / the unlock release indicator
    nIsoOkCnt  : INT  := 0;   // 已确认隔离点数 [点] / the confirmed isolation point count
    bFault     : BOOL := FALSE; // 隔离失效故障锁存（解除 = bReset 沿）[-] / the isolation failure latch
    bError     : BOOL := FALSE; // 组态域闸故障锁存 [-] / the config gate fault latch
END_VAR
VAR CONSTANT
    DL_LOTO_ISOMAX : INT := 8; // 隔离点容量上界 [点] / the isolation point capacity bound
END_VAR
VAR
    _ePhase  : E_DL_LotoPhase := E_DL_LotoPhase.eLotoIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the single CASE write target
    _nOk     : INT := 0;   // 已确认点数工作量 [点] / the confirmed count work value
    _nI      : DINT;       // 隔离点遍历索引 / the isolation point loop index
    _bInit   : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：首拍安全态预置）/ the first scan flag, real use
    rtLock   : R_TRIG;     // 上锁请求沿，段 0 无条件刷新 / the lock request edge
    rtUnlock : R_TRIG;     // 解锁请求沿，段 0 无条件刷新 / the unlock request edge
    rtReset  : R_TRIG;     // 复位沿，段 0 无条件刷新 / the reset edge
    tonTry   : TON;        // 试启验证窗，段 0 无条件刷新 / the try start verify window
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtLock(CLK := bReqLock); // 上锁沿 / the lock edge
rtUnlock(CLK := bReqUnlock); // 解锁沿 / the unlock edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonTry(IN := (_ePhase = E_DL_LotoPhase.eLotoTryVerify), PT := tTryWin); // 试启验证窗 / the verify window

// 段 1｜首拍初始化（R310 真实使用路径）：安全态显式预置 / segment 1, the first scan init, the safe preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the flag
    _ePhase := E_DL_LotoPhase.eLotoIdle; // 相位显式安全预置 / the explicit safe phase preset
END_IF

// 段 2｜组态域闸与复位（边界四，解除路径 = bReset 沿，R188）/ segment 2, the config gate and the reset
IF (nIsoCnt < 1) OR (nIsoCnt > DL_LOTO_ISOMAX) THEN // 点数越域 / the point count out of domain
    bError := TRUE; // 置域闸锁存 / raise the config latch
END_IF
IF rtReset.Q THEN // 复位沿 / the reset edge
    bError := FALSE; // 清域闸锁存 / clear the config latch
    IF _ePhase = E_DL_LotoPhase.eLotoFault THEN // 仅故障相消化复位迁相 / only the fault phase consumes the reset
        _ePhase := E_DL_LotoPhase.eLotoIdle; // 回空闲（解除路径唯一，R188）/ back to idle, the unique release
    END_IF
END_IF

// 段 3｜隔离点确认计数（逐点确认口径）/ segment 3, the isolation confirm count
_nOk := 0; // 计数清零 / clear the count
FOR _nI := 0 TO DL_LOTO_ISOMAX - 1 DO // 逐点遍历 / per point
    IF (_nI < nIsoCnt) AND aIsoCfm[_nI] THEN // 组态界内已确认点 / a confirmed point inside the config bound
        _nOk := _nOk + 1; // 计数推进 / advance the count
    END_IF
END_FOR
nIsoOkCnt := _nOk; // 确认数出口 / the confirm count outlet

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R6 / R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_LotoPhase.eLotoIdle: // 空闲相 / the idle phase
    IF rtLock.Q AND (NOT bError) AND (NOT bFault) THEN // 受理上锁请求（组态合法且无故障）/ accept the lock request
        _ePhase := E_DL_LotoPhase.eLotoIsolate; // 迁隔离确认相 / to the isolate phase
    END_IF

E_DL_LotoPhase.eLotoIsolate: // 隔离确认相 / the isolate phase
    IF bFault THEN // 隔离期间失效（独立成因）/ a failure during the isolation
        _ePhase := E_DL_LotoPhase.eLotoFault; // 迁故障锁存相 / to the fault phase
    ELSIF rtUnlock.Q THEN // 隔离期撤单 / a request withdrawn
        _ePhase := E_DL_LotoPhase.eLotoIdle; // 回空闲 / back to idle
    ELSIF (_nOk >= nIsoCnt) AND bTagLedger AND (NOT bError) THEN // 双闸齐 + 组态合法（R59 修：堵 0 隔离点上锁）/ the dual gates met and the config sane
        _ePhase := E_DL_LotoPhase.eLotoLocked; // 迁上锁相 / to the locked phase
    END_IF

E_DL_LotoPhase.eLotoLocked: // 已上锁相 / the locked phase
    IF bFault THEN // 锁定期失效 / a failure while locked
        _ePhase := E_DL_LotoPhase.eLotoFault; // 迁故障相 / to the fault phase
    ELSIF rtUnlock.Q THEN // 受理解锁请求进验证窗 / accept the unlock into the verify window
        _ePhase := E_DL_LotoPhase.eLotoTryVerify; // 迁试启验证相 / to the try verify phase
    END_IF

E_DL_LotoPhase.eLotoTryVerify: // 试启验证相（窗口末退出迁移，边界二）/ the try verify phase
    IF bMotionFb THEN // 窗内检测到转动：隔离失效（独立成因，R190）/ a motion detected, the isolation failure
        _ePhase := E_DL_LotoPhase.eLotoFault; // 迁故障锁存相 / to the fault phase
    ELSIF tonTry.Q THEN // 验证窗到期无运动：放行（窗口末退出迁移）/ the window expired without motion, release
        _ePhase := E_DL_LotoPhase.eLotoUnlocked; // 迁已解锁相 / to the unlocked phase
    END_IF

E_DL_LotoPhase.eLotoUnlocked: // 已解锁相 / the unlocked phase
    IF bFault THEN // 解锁态失效 / a failure while unlocked
        _ePhase := E_DL_LotoPhase.eLotoFault; // 迁故障相 / to the fault phase
    ELSIF rtLock.Q AND (NOT bError) THEN // 重新上锁请求 / a new lock request
        _ePhase := E_DL_LotoPhase.eLotoIsolate; // 迁隔离确认相 / to the isolate phase
    END_IF

E_DL_LotoPhase.eLotoFault: // 故障锁存相：仅复位可清（迁相由段 2 复位分支消化，本相驻留无动作）/ the fault latch phase, the migrate in the reset branch

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _ePhase := E_DL_LotoPhase.eLotoIdle; // 回空闲安全相 / back to the safe idle
END_CASE

// 段 5｜统一出口（边界一安全口径）/ segment 5, the unified outlet
bLocked := (_ePhase = E_DL_LotoPhase.eLotoLocked) OR (_ePhase = E_DL_LotoPhase.eLotoTryVerify); // 上锁口径双相 / the locked dual phases
bReadyUnlock := (_ePhase = E_DL_LotoPhase.eLotoUnlocked); // 放行指示 / the release indicator
bFault := (_ePhase = E_DL_LotoPhase.eLotoFault); // 故障锁存位与相位同源（R191 名实双出口）/ the fault latch shares the phase
eState := _ePhase; // 状态出口 / the state outlet
END_FUNCTION_BLOCK
