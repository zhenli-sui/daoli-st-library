(*
  FB_DL_ValueHoldMonitor  —  信号冻结保持监视：域外/超时保持最后有效值 + 掩码标记 / Value hold monitor with mask flags
  分类 Category : DL_Base
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat — 域外显式化纪律零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 输入域外或冻结超时 → 输出保持最后有效值 fHoldVal，掩码 uMask 置位
                  （bit0 = 域外，bit1 = 超时冻结），恢复输出须域内连续 nConfirm 拍；
                  2) 域判据全部使用当拍量（fIn 与组态引脚），无锁存量自指；
                  3) 掩码位序与故障码一一对应：域外→04A8、超时→04A9；
                  4) 域外/超时为保持态（故障级 03E5 锁存至 bReset），恢复且复位后清。
  边界 Boundary : ① 组态闸：fLoLim < fHiLim、nConfirm >= 1、fChgTol >= 0 必须成立，
                  违例置故障级 03E4，输出冻结为最后有效值；
                  ② 保持相 CASE 全覆盖 + ELSE 兜底落 03E6；
                  ③ 恢复计数仅在域内且非冻结拍递增，域外即清零；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG）
  码表 Error codes（Base 段 0001，窗口 03E4~03E6 / 04A7~04A9）:
    16#0001_03E4 故障级：组态非法（量程颠倒 / nConfirm < 1 / 容差为负），锁存至 bReset
    16#0001_03E5 故障级：信号保持激活（域外或冻结超时），锁存至 bReset + 域内恢复
    16#0001_03E6 故障级：保持相位落 ELSE 兜底（非法相位 ID），锁存至 bReset
    16#0001_04A7 信息级：新值恢复确认（nConfirm 拍域内沿）
    16#0001_04A8 信息级：域外检出（伴随态，掩码 bit0）
    16#0001_04A9 信息级：冻结超时检出（伴随态，掩码 bit1）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 2 · 序号 1）
*)

TYPE E_DL_VhmState :
(
    eLive := 0,    // 实时透传：输出跟随输入 / Live, output follows the input
    eHold := 10,   // 保持：输出冻结最后有效值 / Hold, output frozen to last valid value
    eConf := 20    // 恢复确认：域内连续计数中 / Confirm, counting in-domain scans
);
END_TYPE

FUNCTION_BLOCK FB_DL_ValueHoldMonitor
VAR_INPUT
    fIn          : LREAL := 0.0;      // 被监视输入 [EU] / Monitored input
    fLoLim       : LREAL := -100.0;   // 有效域下限 [EU]，必须 < fHiLim / Valid span lower bound
    fHiLim       : LREAL := 100.0;    // 有效域上限 [EU]，必须 > fLoLim / Valid span upper bound
    fChgTol      : LREAL := 1.0E-6;   // 冻结判定容差 [EU]，域 >= 0 / Freeze tolerance on change
    tHoldTo      : TIME := T#5S;      // 冻结确认超时 [ms]，域 > 0 / Freeze confirm timeout
    nConfirm     : INT := 3;          // 恢复确认拍数 [拍]，域 >= 1 / Recovery confirm scans
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    fOut         : LREAL;             // 输出：实时值或保持值 [EU] / Output: live or held value
    bHeld        : BOOL;              // 保持中标志 [-] / Holding flag
    uMask        : WORD;              // 掩码：bit0 域外 / bit1 超时冻结 / Mask flags
    bValid       : BOOL;              // 输出有效（实时相 TRUE）/ Output usable flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonHoldTo    : TON;               // 冻结确认定时器，无条件周期刷新 / Freeze confirm timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件周期刷新 / Reset edge instance
    _eState      : E_DL_VhmState := E_DL_VhmState.eLive;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fHoldVal    : LREAL := 0.0;      // 最后有效值快照 [EU] / Last valid value snapshot
    _nConfCnt    : INT;               // 恢复确认计数 [拍] / Recovery confirm counter
    _bInDom      : BOOL;              // 域内判定（当拍量）/ In-domain current-scan flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bLivePrev   : BOOL;              // 上拍实时相镜像（恢复沿判据）/ Previous live mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bInDom := (fIn >= fLoLim) AND (fIn <= fHiLim);         // 域内判定（当拍量）
tonHoldTo(IN := (ABS(fIn - _fHoldVal) <= fChgTol), PT := tHoldTo);  // 冻结确认（每拍必调）
rtReset(CLK := bReset);                                 // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_fHoldVal 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
uMask := 16#0000;                   // 掩码每拍重算
bValid := FALSE;                    // 有效出口缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿（唯一故障解除路径，全当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF

(* —— 段 3：组态域闸（覆盖参与判据换算的全部组态引脚） —— *)
IF (fLoLim >= fHiLim) OR (nConfirm < 1) OR (fChgTol < 0.0) OR (TIME_TO_DINT(tHoldTo) <= 0) THEN
    _uFault := 16#0001_03E4;        // 故障级：组态非法
    _bFault := TRUE;
END_IF

(* —— 段 4：保持相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_VhmState.eLive:
    IF NOT _bInDom THEN
        uMask := uMask OR 16#0001;      // 掩码 bit0：域外
        _uInfo := 16#0001_04A8;         // 信息级：域外检出
        _eState := E_DL_VhmState.eHold; // 进保持相
    ELSIF tonHoldTo.Q THEN
        uMask := uMask OR 16#0002;      // 掩码 bit1：超时冻结
        _uInfo := 16#0001_04A9;         // 信息级：冻结超时
        _eState := E_DL_VhmState.eHold; // 进保持相
    ELSE
        _fHoldVal := fIn;               // 实时相刷新最后有效值快照
    END_IF

E_DL_VhmState.eHold:
    uMask := uMask OR 16#0001;          // 保持相：掩码 bit0 维持（域外/超时聚合保持）
    IF tonHoldTo.Q THEN
        uMask := uMask OR 16#0002;      // 掩码 bit1：冻结持续
    END_IF
    IF _bInDom AND (NOT tonHoldTo.Q) THEN
        _nConfCnt := 0;                 // 域内首拍：确认计数清零起步
        _eState := E_DL_VhmState.eConf; // 进恢复确认相
    END_IF

E_DL_VhmState.eConf:
    IF _bInDom AND (NOT tonHoldTo.Q) THEN
        _nConfCnt := _nConfCnt + 1;     // 域内连续计数递增
        IF _nConfCnt >= nConfirm THEN
            _uInfo := 16#0001_04A7;     // 信息级：新值恢复确认沿
            _eState := E_DL_VhmState.eLive;  // 回实时透传相
        END_IF
    ELSE
        _nConfCnt := 0;                 // 域外即清零
        _eState := E_DL_VhmState.eHold; // 回保持相
    END_IF

ELSE
    _uFault := 16#0001_03E6;        // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_VhmState.eHold; // 强制回保持相（安全侧）

END_CASE

(* —— 段 5：保持聚合故障锁存（03E5：保持态持续或组态闸；解除 = 复位沿 + 恢复确认） —— *)
IF (_eState <> E_DL_VhmState.eLive) OR _bFault THEN
    IF NOT _bFault THEN
        _uFault := 16#0001_03E5;    // 故障级：信号保持激活（首次进入锁存）
    END_IF
    _bFault := TRUE;                // 锁存位维持（恢复相不自动清，须复位沿）
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _eState = E_DL_VhmState.eLive THEN
    fOut := fIn;                    // 实时透传
    bValid := NOT _bFault;          // 有效出口（故障期保持 FALSE）
ELSE
    fOut := _fHoldVal;              // 保持最后有效值
    bValid := FALSE;                // 保持相输出不可用
END_IF
bHeld := (_eState <> E_DL_VhmState.eLive);   // 保持中派生位
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
_bLivePrev := (_eState = E_DL_VhmState.eLive);  // 恢复沿判据快照

END_FUNCTION_BLOCK
