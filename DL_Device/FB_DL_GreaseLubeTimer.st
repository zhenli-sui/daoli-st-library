(*
  Name        : FB_DL_GreaseLubeTimer
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : 加脂保养窗：运行小时数与动作循环数双触发（任一达限即报「该加脂」，先到先报），保养完成后复位清零重计；/ Grease lubrication window: running hours and cycle count both trigger (whichever reaches its limit first reports), cleared and restarted after maintenance
  溯源        : 借 t2-8 ◐/自研 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：小时限/循环限任一 < 0 → 锁存故障（两限可独立为 0 表示该源不触发，但不可为负）；
                ② 运行小时用 1 s 自复位 TON 节拍累计（IN 串 eRun 相位 + bRunning，R188/族③），段 0 无 IF 包裹；
                ③ 双触发独立判据独立归因（R190）：eHoursFirst / eCyclesFirst 各自成因，同拍同到按小时优先归因（不共用成员）；
                ④ 秒计数饱和累加（R28 防回绕），循环数沿计数净额 +1 饱和；
                ⑤ bLubeDue 锁存至复位沿或 bLubeDone 沿（保养完成脉冲，唯一业务清零路径）；
                ⑥ 本件只报保养到期，不执行加脂动作（属主边界）。
*)
TYPE E_DL_GltState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 保养窗计时计数运行 / Accumulating *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_GltCause :
(
    eNone        := 0,                       (* 无故障成因 / No cause *)
    eCfgIllegal  := 1,                       (* 组态非法：时限/循环限越域 / Illegal config *)
    eHoursFirst  := 2,                       (* 运行小时先达限（先到先报） / Hours limit reached first *)
    eCyclesFirst := 3,                       (* 动作循环先达限（先到先报） / Cycles limit reached first *)
    ePhaseBad    := 4                        (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_GreaseLubeTimer
VAR_INPUT
    bRunning   : BOOL := FALSE;              (* 设备运行电平（运行小时累计门控）[-] / Equipment running level *)
    bCyclePulse: BOOL := FALSE;              (* 动作循环脉冲（上升沿计一次）[-] / One action-cycle pulse *)
    fHoursLimit: REAL := 2000.0;             (* 运行小时触发限，域 >= 0（0 = 该源禁用）[h] / Hours trigger limit, >= 0 *)
    nCycleLimit: UDINT := 100000;            (* 循环数触发限，域 >= 0（0 = 该源禁用）[次] / Cycle trigger limit, >= 0 *)
    bLubeDone  : BOOL := FALSE;              (* 保养完成脉冲（业务清零路径，重开保养窗）[-] / Maintenance done pulse *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清累计与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fRunHours  : REAL;                       (* 累计运行小时（窗内）[h] / Accumulated running hours *)
    nCycles    : UDINT;                      (* 累计动作循环数（窗内，饱和）[次] / Accumulated cycles, saturated *)
    bLubeDue   : BOOL;                       (* 加脂到期锁存（复位沿或保养完成沿清）[-] / Lubrication due latched *)
    eState     : E_DL_GltState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_GltCause;              (* 成因出口（R190 双触发独立归因） / Cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_GltState := E_DL_GltState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_GltCause := E_DL_GltCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtCycle  : R_TRIG;                       (* 循环脉冲沿实例，段 0 无条件调用 / Cycle pulse edge *)
    rtLube   : R_TRIG;                       (* 保养完成沿实例，段 0 无条件调用 / Lube-done edge instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonTick  : TON;                          (* 1 s 节拍计时器（自复位，IN 串相位 + 运行电平） / 1 s tick timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _fSec    : REAL;                         (* 窗内累计运行秒数（节拍累加）[s] / Accumulated seconds *)
    _fHoursI : REAL;                         (* 运行小时中间量（秒→小时换算）[h] / Hours intermediate *)
    _bDueI   : BOOL;                         (* 到期内部量（锁存副本源）[-] / Due internal, source of latch *)
END_VAR
VAR CONSTANT
    DL_GLT_EPS    : REAL  := 1.0E-6;         (* 判零容差 [-] / Epsilon *)
    DL_GLT_CNTMAX : UDINT := 4294967295;     (* 循环计数饱和上限（R28）[-] / Cycle count saturation cap *)
    DL_GLT_SECMAX : REAL  := 3.0E9;          (* 秒累计上限（防 REAL 有效位耗尽，约 95 年）[s] / Seconds accumulation cap *)
    DL_GLT_H2S    : REAL  := 3600.0;         (* 小时→秒换算常量（乘性常量）[-] / Hours to seconds factor *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG/TON 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (fHoursLimit < 0.0) OR (nCycleLimit < 0);                          (* 两触发限非负闸（0 = 禁用该源，合法） / Limits non-negative gates *)
rtCycle(CLK := bCyclePulse);                                                   (* 循环沿每拍必调 / Cycle edge every scan *)
rtLube(CLK := bLubeDone);                                                      (* 保养完成沿每拍必调 / Done edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
tonTick(IN := (_eState = E_DL_GltState.eRun) AND bRunning AND NOT tonTick.Q, PT := T#1S);   (* 1 s 节拍自复位（R188）+ eRun 相位与运行电平闸 / 1 s tick with phase and run gates *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bDueI := FALSE;                                                               (* 到期内部量预清（判据拍重算） / Due internal preset *)
_fHoursI := 0.0;                                                               (* 小时中间量预清 / Hours intermediate preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清累计 + 清到期 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_GltCause.eNone;                                            (* 清成因 / Clear cause *)
    _fSec := 0.0;                                                              (* 清秒累计 / Clear seconds *)
    nCycles := 0;                                                              (* 清循环计数出口 / Clear cycles outlet *)
    bLubeDue := FALSE;                                                         (* 清到期锁存出口 / Clear due outlet *)
    _eState := E_DL_GltState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_GltCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_GltState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_GltState.eIdle:                                                       (* 未使能：不累计，出口确定值 / Disabled *)
        _fSec := 0.0;                                                          (* 失能清秒累计（防隐性回夹） / Clear seconds *)
        fRunHours := 0.0;                                                      (* 失能清小时出口 / Clear hours outlet *)
        nCycles := 0;                                                          (* 失能清循环出口 / Clear cycles outlet *)
        bLubeDue := FALSE;                                                     (* 失能清到期出口 / Clear due outlet *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_GltState.eRun;                                     (* 使能进入累计 / Enter accumulating *)
        END_IF
    E_DL_GltState.eRun:                                                        (* 累计相：小时 + 循环双源 / Accumulating *)
        IF NOT bEnable THEN
            _eState := E_DL_GltState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            IF rtLube.Q THEN                                                   (* 保养完成沿：业务清零重开窗（唯一业务清零路径） / Done edge: clear and reopen window *)
                _fSec := 0.0;                                                  (* 清秒累计 / Clear seconds *)
                nCycles := 0;                                                  (* 清循环计数 / Clear cycles *)
                bLubeDue := FALSE;                                             (* 清到期锁存 / Clear due latch *)
                _eCause := E_DL_GltCause.eNone;                                (* 成因复位 / Cause reset *)
            END_IF
            IF tonTick.Q THEN                                                  (* 1 s 节拍到点：秒累计 +1 / Tick elapsed: +1 second *)
                IF _fSec < DL_GLT_SECMAX THEN
                    _fSec := _fSec + 1.0;                                      (* 秒累计（饱和防有效位耗尽，R28） / Seconds accumulate, capped *)
                END_IF
            END_IF
            IF rtCycle.Q THEN                                                  (* 动作循环沿：循环计数 +1 / Cycle edge: +1 *)
                IF nCycles < DL_GLT_CNTMAX THEN
                    nCycles := nCycles + 1;                                    (* 循环计数净额 +1（饱和防回绕） / Net +1, saturated *)
                END_IF
            END_IF
            _fHoursI := _fSec / DL_GLT_H2S;                                    (* 秒→小时换算（除子为常量）[h] / Seconds to hours *)
            fRunHours := _fHoursI;                                             (* 小时出口 / Hours outlet *)
            IF (fHoursLimit > DL_GLT_EPS) AND (_fHoursI >= fHoursLimit) THEN   (* 小时源触发（源限 0 = 禁用不判） / Hours trigger *)
                _bDueI := TRUE;                                                (* 到期内部量置位 / Due set *)
                IF NOT bLubeDue THEN
                    _eCause := E_DL_GltCause.eHoursFirst;                      (* 先到先报：小时源归因（R190） / Hours-first attribution *)
                END_IF
            END_IF
            IF (nCycleLimit > 0) AND (nCycles >= nCycleLimit) THEN             (* 循环源触发（源限 0 = 禁用不判） / Cycle trigger *)
                _bDueI := TRUE;                                                (* 到期内部量置位 / Due set *)
                IF NOT bLubeDue THEN
                    _eCause := E_DL_GltCause.eCyclesFirst;                     (* 先到先报：循环源归因（小时已报则保持小时归因） / Cycles-first attribution *)
                END_IF
            END_IF
            IF _bDueI THEN
                bLubeDue := TRUE;                                              (* 到期锁存（复位沿/保养沿清） / Latch due *)
            END_IF
        END_IF
    E_DL_GltState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_GltState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_GltCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
