(*
  ==================================================================
  组件名 Component  : FB_DL_ShiftHandoverCheck
  分类   Category   : DL_Process
  复杂度 Complexity  : 中
  版本   Version    : 1.0.1
  功能   Purpose    : 班次交接检查。交接开始沿取运行快照（产量与报警计数），
                      交接窗 tHandover 内逐条确认未决事项，全部确认即置完成单拍
                      bHandoverDone；窗到期仍有未决项则升级故障码并转未完成态。
  来源   Source     : self-std（IEC 61131-3 标准时序 + 交接业务语义自研）
  溯源   Origin     : 班次交接检查为公开生产管理语义，道莅 clean-room 自研实现，
                      未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / 比较），三平台通用
  分工声明 Split     : 与 FB_DL_ShiftMonthReport（报表属主）与 FB_DL_ChangeoverSequence
                      （产品换型属主）双向互补——本件只做交接时点的检查与确认闭环，
                      不出报表、不做换型顺控、不改动生产计数本体。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  归属 Ownership     : E_DL_HandoverPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明（D13 返修补行）。
  接口偏离声明       : nProdCnt / nAlarmCnt 为 UDINT 却沿用 n 前缀（D10 返修登记
                      例外，R200）：沿用派单既有引脚名不改，避免破坏调用方接口；
                      族内新件一律用 u 前缀。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 零长窗显式分支（R253）：tHandover ≤ 0 判组态非法故障码，
                         不进交接相（禁靠比较算子隐式分流）；
                      二 同拍竞态让位于合法事件（R275）：交汇段先消化本拍确认沿，
                         再消化窗口到期迁移——到期拍恰有确认沿时按确认处理，
                         不在同拍升级超窗码；
                      三 进入/退出条件逐条取反对偶（R259）：进入 = 开始沿 + 使能 +
                         窗合法 + 无锁存；退出 = 全确认（完成）/ 窗口到期（升级）/
                         失能（弃用）/ 复位沿（清锁存）四条并列；
                      四 快照「最近一次」类出口纳入复位清单（R243）：nSnapProd 与
                         nSnapAlarm 在复位沿一并清零；
                      五 单拍输出 bHandoverDone 统一出口段每拍先预置 FALSE、
                         分支只写 TRUE（R256）；
                      六 使能 bEnable = FALSE 时语义为「弃用本轮交接」（转空闲，
                         不锁存、不出单拍）——R191 声明行；
                      七 故障解除路径：eFault 相由复位沿迁回空闲并清锁存与快照
                         （bReset 为输入引脚，恒可达，R152 自证）。
  错误码   Codes    :
    16#0005_0620【信息级】交接窗内尚有未决事项（逐拍重算，不锁存）
    16#0005_0621【故障级】交接窗时长非法（≤0），组态非法，锁存至复位沿
    16#0005_0622【故障级】交接窗到期仍未全部确认，升级未完成故障，锁存至复位沿
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 3 项未决、窗内 3 个确认沿 → bHandoverDone 单拍、无故障
    V2 窗到期仅确认 2/3 → 码 0622、eFault、未完成
    V3 tHandover = T#0S → 首拍即码 0621，不进交接相
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 3 · 序号 12）
    2026-11-21  v1.0.1  R61 返修：D7 增 _nPendingLock，仅 eIdle 迁入沿赋值，
                        判据与注释对齐（R259）；D10 n 前缀 UDINT 字段登记
                        例外；D13 补 E_DL_HandoverPhase 属主行
  ==================================================================
*)

TYPE E_DL_HandoverPhase :
(
    eIdle  := 0,  // 空闲：等交接开始沿 / idle, waiting for the start edge
    eWait  := 10, // 等待：交接窗内逐条确认 / waiting for the item confirmations inside the window
    eFault := 20  // 故障：窗非法或到期未完成，锁存待复位 / fault, an illegal window or an unfinished overrun, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ShiftHandoverCheck
VAR_INPUT
    bEnable      : BOOL := TRUE;       // 使能，FALSE 时弃用本轮交接（边界六）/ the enable, false discards the round
    bStart       : BOOL := FALSE;      // 交接开始电平，上升沿取快照 / the start level, the rising edge takes the snapshot
    bConfirmItem : BOOL := FALSE;      // 未决事项确认电平，上升沿确认一条 / the item confirmation level, each rising edge confirms one item
    bReset       : BOOL := FALSE;      // 复位沿：清锁存与快照并回空闲 / the reset edge, clears the latch and the snapshot
    tHandover    : TIME := T#10M;      // 交接窗时长 [毫秒]，必须 > 0 / the handover window, must be positive
    nPendingItems : DINT := 3;         // 未决事项条数 [条]，合法域 0..64 / the pending item count, legal from zero to sixty four
    nProdCnt     : UDINT := 0;         // 当前班次产量计数 [件] / the production count of the shift
    nAlarmCnt    : UDINT := 0;         // 当前班次报警计数 [次] / the alarm count of the shift
END_VAR
VAR_OUTPUT
    bRunning       : BOOL := FALSE;               // 交接窗口进行中 [-] / the handover in progress flag
    bHandoverDone  : BOOL := FALSE;               // 交接完成单拍脉冲 [-] / the handover done one shot pulse
    nConfirmedCnt  : DINT := 0;                   // 已确认条数 [条] / the confirmed item count
    nSnapProd      : UDINT := 0;                  // 交接开始时刻的产量快照 [件] / the production snapshot at the start edge
    nSnapAlarm     : UDINT := 0;                  // 交接开始时刻的报警快照 [次] / the alarm snapshot at the start edge
    eState         : E_DL_HandoverPhase;          // 主状态机当前态 [状态] / the current state of the main machine
    bError         : BOOL := FALSE;               // 故障锁存位 [-] / the latched fault bit
    eErr           : UDINT := 16#0000_0000;       // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit      : BOOL := FALSE;                                 // 首拍初始化标志（R310）/ the first scan flag
    _eState     : E_DL_HandoverPhase := E_DL_HandoverPhase.eIdle; // 内部状态寄存器，段 4 唯一写点 / the internal state register, single writer
    _bDone      : BOOL := FALSE;                                 // 完成单拍内部位，段 1 预清段 6 映射 / the internal done bit, preset then mapped
    _nConfirmed : DINT := 0;                                     // 已确认条数副本 / the confirmed count copy
    _nPending   : DINT := 0;                                     // 未决条数钳位工作副本（逐拍重算，仅供迁入沿快照，D7 返修）/ the clamped pending work copy, recomputed every scan
    _nPendingLock : DINT := 0;                                   // 本轮未决条数锁定值（仅 eIdle 迁入沿赋值，D7 返修，R259）/ the locked pending count, assigned only on the idle entry edge
    _uSnapProd  : UDINT := 0;                                    // 产量快照副本 / the production snapshot copy
    _uSnapAlarm : UDINT := 0;                                    // 报警快照副本 / the alarm snapshot copy
    _bFault     : BOOL := FALSE;                                 // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _bCfgBad    : BOOL := FALSE;                                 // 组态非法标记（逐拍重算）[-] / the configuration fault flag
    _bIncomplete : BOOL := FALSE;                                // 未确认标记（逐拍重算）[-] / the unconfirmed flag
    rtStart     : R_TRIG;                                        // 开始沿实例，段 0 无条件刷新 / the start edge instance
    rtConfirm   : R_TRIG;                                        // 确认沿实例，段 0 无条件刷新 / the confirmation edge instance
    rtReset     : R_TRIG;                                        // 复位沿实例，段 0 无条件刷新 / the reset edge instance
    tonWindow   : TON;                                           // 交接窗定时器，段 0 无条件刷新 / the handover window timer
END_VAR
VAR CONSTANT
    DL_SHC_ITMAX : DINT := 64; // 未决事项上界 [条] / the pending item bound
END_VAR

// 段 0｜沿检测与交接窗定时器无条件周期刷新（禁入分支，R7；IN 串故障锁存门控，FB50-1）/ segment 0, the unconditional refresh with the latch gate
rtStart(CLK := bStart); // 开始沿 / the start edge
rtConfirm(CLK := bConfirmItem); // 确认沿 / the confirmation edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonWindow(IN := (_eState = E_DL_HandoverPhase.eWait) AND (NOT _bFault), PT := tHandover); // 交接窗：仅等待相且无锁存时计时 / the window timing only in the waiting phase

// 段 1｜首拍初始化与单拍标志预清（仅单拍标志入清单，R32 FB32-1；R256）/ segment 1, the first scan init and the one shot preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _nConfirmed := 0; // 已确认条数显式清零 / clear the confirmed count explicitly
    _nPending := 0; // 未决条数显式清零 / clear the pending count explicitly
    _nPendingLock := 0; // 未决锁定值显式清零（D7 返修）/ clear the locked pending count explicitly
    _uSnapProd := 0; // 产量快照显式清零 / clear the production snapshot explicitly
    _uSnapAlarm := 0; // 报警快照显式清零 / clear the alarm snapshot explicitly
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_HandoverPhase.eIdle; // 状态显式落空闲 / place the state to idle explicitly
END_IF
_bDone := FALSE; // 完成单拍预清零 / preset the done pulse false
_bCfgBad := FALSE; // 组态非法标记预清零 / preset the configuration flag false
_bIncomplete := FALSE; // 未确认标记预清零 / preset the unconfirmed flag false

// 段 2｜组态域闸（零长窗显式分支，边界一；未决条数越域钳位）/ segment 2, the configuration gate with the explicit zero length branch
IF tHandover <= T#0S THEN // 零长窗：非法组态 / a zero length window, an illegal configuration
    _bCfgBad := TRUE; // 置组态非法标记 / raise the configuration flag
    _bFault := TRUE; // 锁存故障（段 5 迁移相）/ latch the fault, the segment five migrates the phase
END_IF
IF nPendingItems < 0 THEN // 条目数为负（域下界硬限）/ a negative item count
    _nPending := 0; // 按零条处理（无未决即完成）/ treat as zero, an immediate completion
ELSIF nPendingItems > DL_SHC_ITMAX THEN // 条目数越上界 / above the bound
    _nPending := DL_SHC_ITMAX; // 钳到上界 / clamp to the bound
ELSE // 域内 / inside the domain
    _nPending := nPendingItems; // 原值接管 / take the value as is
END_IF

// 段 3｜本拍确认沿预消化（R275：合法事件先于窗口到期迁移消化，段序在段 4 之前）/ segment 3, the confirmation edge pre digest ahead of the window expiry
IF rtConfirm.Q AND (_eState = E_DL_HandoverPhase.eWait) AND (NOT _bFault) THEN // 等待相内的确认沿 / a confirmation edge inside the waiting phase
    IF _nConfirmed < _nPendingLock THEN // 尚有未确认条目（判据用锁定值，D7 返修）/ items remain unconfirmed against the locked count
        _nConfirmed := _nConfirmed + 1; // 确认一条 / confirm one item
    ELSE // 已全部确认（多按的确认沿忽略）/ everything is confirmed, extra presses ignored
        _nConfirmed := _nPendingLock; // 计数饱和于锁定条目数 / saturate the count at the locked item count
    END_IF
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 拦非法态；进入/退出逐条取反对偶，边界三）/ segment 4, the main machine with the paired entry and exit conditions
CASE _eState OF
    E_DL_HandoverPhase.eIdle: // 空闲相：等开始沿（条件：开始沿 + 使能 + 窗合法 + 无锁存）/ the idle phase
        IF rtStart.Q AND bEnable AND (tHandover > T#0S) AND (NOT _bFault) THEN // 迁入判据带全量闸位复检（R274）/ the entry with the full gate recheck
            _nConfirmed := 0; // 新一轮确认计数归零 / reset the confirmed count
            _uSnapProd := nProdCnt; // 取产量快照（最近一次类出口）/ take the production snapshot
            _uSnapAlarm := nAlarmCnt; // 取报警快照 / take the alarm snapshot
            _nPendingLock := _nPending; // 未决条数锁定（仅此迁入沿赋值，窗内改参不影响本轮判据，D7 返修）/ lock the pending count on this entry edge only
            _eState := E_DL_HandoverPhase.eWait; // 迁入等待相 / enter the waiting phase
        END_IF
    E_DL_HandoverPhase.eWait: // 等待相：四条退出（全确认 / 到期 / 失能 / 锁存）/ the waiting phase with four exits
        IF _nConfirmed >= _nPendingLock THEN // 退出条件一：全部确认（判据用锁定值，D7 返修）/ the first exit, everything confirmed against the locked count
            _bDone := TRUE; // 置完成单拍 / raise the done pulse
            _eState := E_DL_HandoverPhase.eIdle; // 迁回空闲 / back to idle
        ELSIF tonWindow.Q THEN // 退出条件二：窗口到期仍未全部确认（边界二：本拍确认沿已在段 3 消化）/ the second exit, the window expired unconfirmed
            _bIncomplete := TRUE; // 置未确认标记 / raise the unconfirmed flag
            _bFault := TRUE; // 锁存超窗故障（0622）/ latch the overrun fault
        ELSIF (NOT bEnable) OR _bFault THEN // 退出条件三：失能弃用或已锁存（前置条件消失）/ the third exit with the prerequisite gone
            _eState := E_DL_HandoverPhase.eIdle; // 迁回空闲（不锁存、不出单拍）/ back to idle without a latch or a pulse
        END_IF
    E_DL_HandoverPhase.eFault: // 故障相：锁存保持，等复位沿（解除可达，边界七）/ the fault phase held until the reset edge
        IF rtReset.Q THEN // 复位沿（复位作用域：清锁存 + 清快照 + 清累计量 + 迁相位）/ the reset with the declared scope
            _bFault := FALSE; // 清故障锁存 / clear the fault latch
            _nConfirmed := 0; // 清确认计数 / clear the confirmed count
            _nPendingLock := 0; // 清未决锁定值（复位作用域含锁定值，D7 返修）/ clear the locked pending count within the reset scope
            _uSnapProd := 0; // 清产量快照（R243 最近一次类出口入复位清单）/ clear the production snapshot
            _uSnapAlarm := 0; // 清报警快照 / clear the alarm snapshot
            _eState := E_DL_HandoverPhase.eIdle; // 故障相迁出边回空闲 / the exit edge back to idle
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_HandoverPhase.eIdle; // 落回空闲 / force back to idle
        _bFault := TRUE; // 置故障锁存 / latch the fault
END_CASE

// 段 5｜故障锁存迁移闸（置于解除段之后防同拍抢迁，R258）/ segment 5, the fault latch to phase gate placed after the release
IF _bFault AND (_eState <> E_DL_HandoverPhase.eFault) THEN // 已锁存但不在故障相 / latched but not in the fault phase
    _eState := E_DL_HandoverPhase.eFault; // 迁入故障相 / enter the fault phase
END_IF

// 段 6｜统一出口（内部副本单点映射，R180；故障码锁存回放，R187）/ segment 6, the unified outlet
_bIncomplete := (_eState = E_DL_HandoverPhase.eWait) AND (_nConfirmed < _nPendingLock); // 未确认提示逐拍重算（判据用锁定值，D7 返修）/ the unconfirmed hint recomputed every scan against the locked count
bRunning := (_eState = E_DL_HandoverPhase.eWait); // 进行中出口 / the in progress outlet
bHandoverDone := _bDone; // 完成单拍出口 / the done pulse outlet
nConfirmedCnt := _nConfirmed; // 确认条数出口 / the confirmed count outlet
nSnapProd := _uSnapProd; // 产量快照出口 / the production snapshot outlet
nSnapAlarm := _uSnapAlarm; // 报警快照出口 / the alarm snapshot outlet
eState := _eState; // 状态出口 / the state outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet from the same latch
IF _bFault THEN // 故障锁存回放优先 / the latched fault replays first
    IF _bCfgBad THEN // 组态成因（独立码值，R190）/ the configuration cause with its own code
        eErr := 16#0005_0621; // 故障级：交接窗时长非法 / fault grade, the window length is illegal
    ELSE // 超窗成因 / the overrun cause
        eErr := 16#0005_0622; // 故障级：到期仍未全部确认 / fault grade, still unconfirmed at the expiry
    END_IF
ELSIF _bIncomplete THEN // 未确认提示（信息级，逐拍重算）/ the informational unconfirmed hint
    eErr := 16#0005_0620; // 信息级：尚有未决事项 / informational, items still pending
    bError := FALSE; // 信息级不置 bError（仅故障级置位，R45 配对口径）/ the informational code never raises the fault bit
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
