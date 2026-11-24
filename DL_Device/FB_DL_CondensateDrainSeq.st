(*
  ==================================================================
  组件名 Component  : FB_DL_CondensateDrainSeq
  分类   Category   : DL_Device
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 储气罐 / 空压机冷凝水自动排污阀时序。定时触发与液位高
                      双触发源并联起排；开阀确认反馈 → 排放（触发消失且最
                      小排放时长满足）→ 关阀确认反馈；三窗超时诊断（开阀 /
                      排放 / 关阀独立成因独立码位语义，R190）。
  来源   Source     : t2-2-lbp（命令→监视→判定三段）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；冷凝水排污双触
                      发与阀反馈确认窗为行业公知工程语义，clean-room 自研实
                      现，未复制 LBP 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 DL_Device 存量阀类执行件（电磁阀直控类）分工——直
                      控件只做单阀开关映射，本件为排污全过程顺控（三窗监视
                      与诊断）；不做压力 / 温度工艺调节。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态配比约束（R100）：tMinDrain < tDrainMax（最小排
                         放短于排放超时）且 tOpenConfirm > T#0S 且 tCloseConfirm
                         > T#0S；越域判故障级锁存；
                      二 触发为电平语义：定时触发与液位高任一为真且许可满
                         足即起排；排放相退出 = 触发消失（事件）AND 最小排放
                         时长满足（双条件，R98 精神）；
                      三 故障相阀命令安全侧断开（排污阀断电 = 关闭，R191 显
                         式声明）；故障锁存解除路径 = bReset 上升沿（唯一路
                         径，R188）；
                      四 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 3 · 序号 11）
  ==================================================================
*)

TYPE E_DL_CdsPhase :
(
    eCdsIdle    := 0,  // 空闲：等触发 / idle, waiting for a trigger
    eCdsOpening := 10, // 开阀：等阀开反馈确认 / opening, awaiting the open feedback
    eCdsDraining := 20, // 排放中：等触发消失且最小时长满足 / draining, awaiting the trigger gone with the minimum met
    eCdsClosing := 30, // 关阀：等阀关反馈确认 / closing, awaiting the closed feedback
    eCdsFault   := 90  // 故障锁存 / the latched fault
);
END_TYPE

TYPE E_DL_CdsCause :
(
    eNone         := 0, // 无成因 / no cause
    eCfgBad       := 1, // 组态非法：时间窗配比越域（故障级，与 bError 配对）/ an illegal config
    eValveOpenTo  := 2, // 开阀确认超时（故障级，与 bError 配对）/ an open confirm timeout
    eDrainTimeout := 3, // 排放超时（液位不回落，故障级，与 bError 配对）/ a drain timeout
    eValveCloseTo := 4, // 关阀确认超时（故障级，与 bError 配对）/ a close confirm timeout
    ePhaseBad     := 5  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_CondensateDrainSeq
VAR_INPUT
    bEnable       : BOOL := TRUE;   // 使能，失能回空闲关阀 [-] / enable, disabling returns idle with the valve closed
    bReset        : BOOL := FALSE;  // 复位上升沿清故障锁存 [-] / reset rising edge clears the latch
    bTimTrig      : BOOL := FALSE;  // 定时触发电平（调用方定时器给出）[-] / the timer trigger level
    bLevelHigh    : BOOL := FALSE;  // 液位高触发电平 [-] / the level high trigger level
    bPermitDrain  : BOOL := TRUE;   // 排放许可（压力低联锁给出）[-] / the drain permit from the pressure interlock
    bFbValveOpen  : BOOL := FALSE;  // 排污阀开到位反馈 [-] / the valve open feedback
    bFbValveClosed: BOOL := TRUE;   // 排污阀关到位反馈 [-] / the valve closed feedback
    tOpenConfirm  : TIME := T#5S;   // 开阀确认窗 [毫秒] / the open confirm window [millisecond]
    tDrainMax     : TIME := T#60S;  // 排放超时窗 [毫秒] / the drain timeout window [millisecond]
    tCloseConfirm : TIME := T#5S;   // 关阀确认窗 [毫秒] / the close confirm window [millisecond]
    tMinDrain     : TIME := T#2S;   // 最小排放时长 [毫秒] / the minimum drain duration [millisecond]
END_VAR
VAR_OUTPUT
    bValveCmd   : BOOL := FALSE; // 排污阀命令输出（TRUE = 开阀）[-] / the valve command outlet, true = open
    bDrainActive: BOOL := FALSE; // 排放进行指示 [-] / the drain active indicator
    ePhase      : E_DL_CdsPhase := E_DL_CdsPhase.eCdsIdle; // 相位出口 [枚举] / the phase outlet
    eCause      : E_DL_CdsCause := E_DL_CdsCause.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError      : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    tonOpen : TON;    // 开阀确认窗，段 0 无条件刷新 / the open confirm window
    tonDrain: TON;    // 排放超时窗，段 0 无条件刷新 / the drain timeout window
    tonClose: TON;    // 关阀确认窗，段 0 无条件刷新 / the close confirm window
    tonMin  : TON;    // 最小排放窗，段 0 无条件刷新 / the minimum drain window
    _ePhase : E_DL_CdsPhase := E_DL_CdsPhase.eCdsIdle; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC : E_DL_CdsCause := E_DL_CdsCause.eNone; // 故障级成因，锁存至复位沿 / the fault cause latched
    _bFault : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bCfgOk : BOOL := FALSE; // 组态域内 [-] / the config inside the domain
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，FB50-1）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonOpen(IN := (_ePhase = E_DL_CdsPhase.eCdsOpening) AND (NOT _bFault) AND bEnable, PT := tOpenConfirm); // 开阀窗，IN 串开阀相闸 / the open window gated by the opening phase
tonDrain(IN := (_ePhase = E_DL_CdsPhase.eCdsDraining) AND (NOT _bFault) AND bEnable, PT := tDrainMax); // 排放窗，IN 串排放相闸 / the drain window gated by the draining phase
tonClose(IN := (_ePhase = E_DL_CdsPhase.eCdsClosing) AND (NOT _bFault) AND bEnable, PT := tCloseConfirm); // 关阀窗，IN 串关阀相闸 / the close window gated by the closing phase
tonMin(IN := (_ePhase = E_DL_CdsPhase.eCdsDraining) AND (NOT _bFault) AND bEnable, PT := tMinDrain); // 最小排放窗，与排放窗同相起算（配比约束见边界一）/ the minimum window co-started with the drain window

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 迁空闲（两项逐项声明，边界三）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_CdsCause.eNone; // 作用域一：清成因 / scope one, clear the cause
    _ePhase := E_DL_CdsPhase.eCdsIdle; // 作用域二：迁空闲相 / scope two, back to idle
END_IF

// 段 3｜组态域闸（边界一，R100 配比）/ segment 3, the config gate
_bCfgOk := (tOpenConfirm > T#0S) AND (tCloseConfirm > T#0S) AND (tMinDrain < tDrainMax) AND (tDrainMax > T#0S); // 确认窗 / 排放窗 / 配比判定 / the confirm, drain and pairing verdicts
IF NOT _bCfgOk THEN // 配比越域 / a pairing violation
    IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_CdsCause.eCfgBad; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_CdsPhase.eCdsFault; // 迁故障相（锁存与迁相同分支，FB50-1）/ migrate to the fault phase
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_CdsPhase.eCdsIdle: // 空闲相：双触发源并联评估（边界二）/ the idle phase, the dual trigger evaluation
    IF NOT bEnable THEN // 失能驻留 / dwell while disabled
        _ePhase := E_DL_CdsPhase.eCdsIdle; // 停摆驻留 / dwell
    ELSIF (bTimTrig OR bLevelHigh) AND bPermitDrain THEN // 触发且许可 / a trigger with the permit
        _ePhase := E_DL_CdsPhase.eCdsOpening; // 迁开阀相 / migrate to the opening phase
    END_IF

E_DL_CdsPhase.eCdsOpening: // 开阀相：等阀开反馈确认 / the opening phase
    IF NOT bEnable THEN // 失能回空闲关阀（R191 显式）/ a disable returns idle
        _ePhase := E_DL_CdsPhase.eCdsIdle; // 回空闲相 / back to idle
    ELSIF bFbValveOpen THEN // 阀开反馈确认 / the open feedback confirmed
        _ePhase := E_DL_CdsPhase.eCdsDraining; // 迁排放相 / migrate to the draining phase
    ELSIF tonOpen.Q THEN // 开阀确认窗超时（R190 独立成因）/ the open timeout, an independent cause
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_CdsCause.eValveOpenTo; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_CdsPhase.eCdsFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CdsPhase.eCdsDraining: // 排放相：双退出条件（边界二，R98 精神）/ the draining phase, the dual exit
    IF NOT bEnable THEN // 失能回空闲关阀 / a disable returns idle
        _ePhase := E_DL_CdsPhase.eCdsIdle; // 回空闲相 / back to idle
    ELSIF (NOT bTimTrig) AND (NOT bLevelHigh) AND tonMin.Q THEN // 触发消失且最小排放时长满足 / the trigger gone with the minimum met
        _ePhase := E_DL_CdsPhase.eCdsClosing; // 迁关阀相 / migrate to the closing phase
    ELSIF tonDrain.Q THEN // 排放超时（液位不回落，R190 独立成因）/ the drain timeout, an independent cause
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_CdsCause.eDrainTimeout; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_CdsPhase.eCdsFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CdsPhase.eCdsClosing: // 关阀相：等阀关反馈确认 / the closing phase
    IF NOT bEnable THEN // 失能回空闲 / a disable returns idle
        _ePhase := E_DL_CdsPhase.eCdsIdle; // 回空闲相 / back to idle
    ELSIF bFbValveClosed THEN // 阀关反馈确认 / the closed feedback confirmed
        _ePhase := E_DL_CdsPhase.eCdsIdle; // 回空闲相 / back to idle
    ELSIF tonClose.Q THEN // 关阀确认窗超时（R190 独立成因）/ the close timeout, an independent cause
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_CdsCause.eValveCloseTo; // 故障级成因（R45 配对）/ the fault cause
        _ePhase := E_DL_CdsPhase.eCdsFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_CdsPhase.eCdsFault: // 故障相：成因锁存等复位沿；阀命令安全侧断开 / the fault phase
ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_CdsCause.ePhaseBad; // 故障级成因（R45 配对）/ the fault cause
    _ePhase := E_DL_CdsPhase.eCdsFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口（边界三安全侧）/ segment 5, the unified outlet
bValveCmd := ((_ePhase = E_DL_CdsPhase.eCdsOpening) OR (_ePhase = E_DL_CdsPhase.eCdsDraining)) AND bEnable AND (NOT _bFault); // 阀命令仅开阀与排放相 / the valve command in the opening and draining phases
bDrainActive := (_ePhase = E_DL_CdsPhase.eCdsDraining) AND (NOT _bFault); // 排放指示 / the drain indicator
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eCause := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
ELSE // 无锁存 / no latch
    eCause := E_DL_CdsCause.eNone; // 无成因 / no cause
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the flag shares the latch
END_FUNCTION_BLOCK
