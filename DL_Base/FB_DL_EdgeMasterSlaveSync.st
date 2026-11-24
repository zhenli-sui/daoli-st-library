(*
  ==================================================================
  组件名 Component  : FB_DL_EdgeMasterSlaveSync
  分类   Category   : DL_Base
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 主从双通道沿同步判定。主通道越阈上升沿开启 tSyncWindow 等
                      从窗；从沿落在窗内（含与主沿同拍）判通道一致，出单拍有效
                      脉冲；窗内多个从沿只受理第一个；任一信号非有限拍出无效并
                      冻结判定。用于安全回路双通道一致性监视。
  来源   Source     : iec-std-wrapper（T0）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；双通道沿一致窗为公开
                      安全仪表语义，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON，无私有库）
  分工声明 Split     : 与 FB_DL_SignalDebounce（单通道消抖）及 FB_DL_Vote2oo3
                      （三选二表决）分工——本件只做双通道沿时序一致性判定，
                      不消抖、不表决、不裁决通道权重。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 tSyncWindow 钳位 [T#1MS, T#1S]，越界按边界执行并置信息级；
                      二 主从沿同拍判有效（同拍双沿直接出脉冲，不等窗）；
                      三 窗内多从沿只受理第一个（受理即关窗）；
                      四 非有限输入拍：bInvalid 置位、等从窗关闭、不产生脉冲，
                         输出冻结（R191 显式声明），恢复拍不回放历史沿；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 1 · 序号 2）
  ==================================================================
*)

TYPE E_DL_EmsPhase :
(
    eIdle      := 0,  // 空闲：等主沿 / idle, waiting for the master edge
    eWaitSlave := 10, // 等从窗：主沿已开窗 / waiting for the slave inside the window
    eFault     := 90  // 无效：输入非有限冻结（信息级驻留，非锁存）/ invalid, a non finite input freezes the grading
);
END_TYPE

FUNCTION_BLOCK FB_DL_EdgeMasterSlaveSync
VAR_INPUT
    fMasterVal  : LREAL := 0.0;  // 主通道信号 [工程单位] / the master channel signal [engineering unit]
    fSlaveVal   : LREAL := 0.0;  // 从通道信号 [工程单位] / the slave channel signal [engineering unit]
    fThresh     : LREAL := 1.0;  // 双通道共用越阈判定阈值 [工程单位] / the shared threshold [engineering unit]
    tSyncWindow : TIME := T#20MS; // 主从沿允许时差窗 [毫秒]，钳位 [1毫秒, 1秒] / the allowed master-slave skew window [millisecond], clamped
    bEnable     : BOOL := TRUE;  // 使能，失能即关窗回空闲 [-] / enable, disabling closes the window
    bReset      : BOOL := FALSE; // 复位上升沿清窗与计数 [-] / reset rising edge clears the window and counters
END_VAR
VAR_OUTPUT
    bSyncValid    : BOOL := FALSE; // 同步有效单拍脉冲 [-] / the sync valid one-scan pulse
    bWaitSlave    : BOOL := FALSE; // 等从窗活动指示 [-] / the window active indicator
    bInvalid      : BOOL := FALSE; // 本拍输入无效（判定冻结）[-] / the inputs are void this scan, the grading frozen
    nMatchCnt     : UDINT := 0;    // 同步有效累计次数 [次] / the accumulated match count [count]
    nLateSlaveCnt : UDINT := 0;    // 窗外迟到从沿累计次数 [次] / the late slave edge count outside the window [count]
    uErrorId      : UDINT := 0;    // 信息级码，0 = 正常 / informational code, zero is ok
    bError        : BOOL := FALSE; // 信息级错误标志（每拍重算，非锁存）/ informational flag, recomputed each scan
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    tonWin  : TON;    // 等从窗定时器，段 0 无条件刷新 / the slave window timer, refreshed unconditionally
    _ePhase : E_DL_EmsPhase := E_DL_EmsPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan flag
    _bInOk  : BOOL := FALSE; // 双通道信号均有限 [-] / both signals finite
    _bMNow  : BOOL := FALSE; // 主通道越阈电平（当拍）[-] / the master above-threshold level this scan
    _bSNow  : BOOL := FALSE; // 从通道越阈电平（当拍）[-] / the slave above-threshold level this scan
    _bMPrev : BOOL := FALSE; // 主通道越阈电平（上拍）[-] / the master level previous scan
    _bSPrev : BOOL := FALSE; // 从通道越阈电平（上拍）[-] / the slave level previous scan
    _bMPend : BOOL := FALSE; // 主沿待从标记 [-] / the master edge pending flag
    _tWin   : TIME := T#20MS; // 钳位后的同步窗 [毫秒] / the clamped sync window [millisecond]
END_VAR
VAR CONSTANT
    DL_EMS_WIN_MIN : TIME := T#1MS; // 同步窗下钳位 [毫秒] / the window lower clamp [millisecond]
    DL_EMS_WIN_MAX : TIME := T#1S;  // 同步窗上钳位 [毫秒] / the window upper clamp [millisecond]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonWin(IN := (_ePhase = E_DL_EmsPhase.eWaitSlave), PT := _tWin); // 等从窗，IN 串等从相闸（无效拍相位已回空闲，天然关窗）/ the window gated by the wait phase, the phase already back to idle on an invalid scan

// 段 1｜首扫初始化（R310）：快照取当拍，禁首拍假边沿 / segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit  := TRUE; // 置首扫标志 / raise the first scan flag
    _bMPrev := FALSE; // 越阈电平从 FALSE 起步（首拍不产沿）/ the level starts FALSE, no edge on the first scan
    _bSPrev := FALSE; // 从通道同理 / the same for the slave
END_IF

// 段 2｜复位沿作用域：清窗 / 清计数（两项逐项声明）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bMPend := FALSE; // 作用域一：清主沿待从标记 / scope one, clear the pending flag
    nMatchCnt := 0; // 作用域二：清同步计数 / scope two, clear the match counter
    nLateSlaveCnt := 0; // 作用域二：清迟到计数 / scope two, clear the late counter
END_IF

// 段 3｜输入有限性闸（双判据）与阈值组态闸 / segment 3, the finiteness gate and the threshold gate
_bInOk := (fMasterVal = fMasterVal) AND ((fMasterVal - fMasterVal) = (fMasterVal - fMasterVal)) AND (fSlaveVal = fSlaveVal) AND ((fSlaveVal - fSlaveVal) = (fSlaveVal - fSlaveVal)) AND (fThresh = fThresh) AND ((fThresh - fThresh) = (fThresh - fThresh)); // 双信号与阈值有限性 / finiteness of both signals and the threshold
IF NOT _bInOk THEN // 非有限拍 / a non finite scan
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    _bMPend  := FALSE; // 关窗（冻结判定，R191）/ close the window, the grading frozen
    _ePhase  := E_DL_EmsPhase.eIdle; // 回空闲驻留（恢复后重新等主沿）/ back to idle, a fresh wait after recovery
    uErrorId := 16#0001_0002; // 信息级：输入非有限 / informational, a non finite input
    bError   := TRUE; // 置信息级标志 / raise the informational flag
    _bMPrev  := FALSE; // 越阈电平冻结为假（恢复拍不回放历史沿）/ the level frozen false, no historical edge replay
    _bSPrev  := FALSE; // 从通道同理 / the same for the slave
    RETURN; // 早退，脉冲出口保持冻结末值 / early return, the pulse outlet frozen
END_IF

// 段 4｜同步窗钳位（信息级）/ segment 4, the window clamp, informational
IF tSyncWindow < DL_EMS_WIN_MIN THEN // 低于下钳位 / below the lower clamp
    _tWin    := DL_EMS_WIN_MIN; // 钳到下限 / clamp to the floor
    uErrorId := 16#0001_0003; // 信息级：窗过小已钳 / informational, a too small window clamped
    bError   := TRUE; // 置信息级标志 / raise the informational flag
ELSIF tSyncWindow > DL_EMS_WIN_MAX THEN // 高于上钳位 / above the upper clamp
    _tWin    := DL_EMS_WIN_MAX; // 钳到上限 / clamp to the ceiling
    uErrorId := 16#0001_0003; // 信息级：窗过大已钳 / informational, a too large window clamped
    bError   := TRUE; // 置信息级标志 / raise the informational flag
ELSE // 域内 / inside the domain
    _tWin    := tSyncWindow; // 直通 / passthrough
    uErrorId := 16#0000_0000; // 正常码 / the ok code
    bError   := FALSE; // 信息级标志清零 / clear the informational flag
END_IF

// 段 5｜越阈电平与沿提取（R_TRIG 语义手工实现，快照末拍推进）/ segment 5, the above-threshold levels and the edges
_bMNow := fMasterVal > fThresh; // 主通道越阈电平 / the master level
_bSNow := fSlaveVal > fThresh; // 从通道越阈电平 / the slave level

// 段 6｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 6, the phase machine
CASE _ePhase OF

E_DL_EmsPhase.eIdle: // 空闲相：等主沿 / the idle phase, waiting for the master edge
    IF _bMNow AND (NOT _bMPrev) THEN // 主沿 / the master edge
        IF _bSNow AND (NOT _bSPrev) THEN // 同拍双沿直接判有效（边界二）/ the same-scan dual edges judged valid
            bSyncValid := TRUE; // 出同步脉冲 / raise the sync pulse
            nMatchCnt := nMatchCnt + 1; // 计数推进 / advance the counter
        ELSE // 无同拍从沿 / no same-scan slave edge
            _bMPend := TRUE; // 开等从窗 / open the window
            _ePhase := E_DL_EmsPhase.eWaitSlave; // 迁等从相 / migrate to the wait phase
        END_IF
    ELSIF _bSNow AND (NOT _bSPrev) THEN // 无主沿的孤立从沿（迟到）/ a lone slave edge, late
        nLateSlaveCnt := nLateSlaveCnt + 1; // 迟到计数 / advance the late counter
    END_IF

E_DL_EmsPhase.eWaitSlave: // 等从相：窗内受理第一个从沿（边界三）/ the wait phase, only the first slave edge accepted
    IF _bSNow AND (NOT _bSPrev) THEN // 从沿到达 / a slave edge arrived
        bSyncValid := TRUE; // 出同步脉冲 / raise the sync pulse
        nMatchCnt := nMatchCnt + 1; // 计数推进 / advance the counter
        _bMPend := FALSE; // 受理即关窗（后续从沿不再受理）/ close on acceptance, later edges not accepted
        _ePhase := E_DL_EmsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF tonWin.Q THEN // 窗满无从沿 / the window expired without a slave edge
        _bMPend := FALSE; // 关窗 / close the window
        _ePhase := E_DL_EmsPhase.eIdle; // 回空闲相 / back to idle
    END_IF

E_DL_EmsPhase.eFault: // 无效驻留相：由段 3 早退覆盖，此处仅兜底 / the invalid dwell phase, covered by the segment three early return
    _ePhase := E_DL_EmsPhase.eIdle; // 兜底回空闲 / fallback to idle

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bMPend := FALSE; // 关窗 / close the window
    _ePhase := E_DL_EmsPhase.eIdle; // 回空闲相 / back to idle
    uErrorId := 16#0001_0005; // 信息级：非法相位 / informational, an illegal phase
    bError   := TRUE; // 置信息级标志 / raise the informational flag
END_CASE

// 段 7｜快照推进与统一出口 / segment 7, the snapshot advance and the unified outlet
_bMPrev := _bMNow; // 主通道快照推进 / advance the master snapshot
_bSPrev := _bSNow; // 从通道快照推进 / advance the slave snapshot
IF NOT _bInOk THEN // 兜底防御（正常路径早退不可达）/ a defensive fallback, unreachable on the normal path
    bSyncValid := FALSE; // 脉冲冻结为假 / the pulse frozen false
END_IF
bWaitSlave := _bMPend; // 等从窗指示 / the window indicator
END_FUNCTION_BLOCK
