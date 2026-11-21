(*
  Name        : FB_DL_CaseShiftTally
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 班次箱数台账与计划差异告警：班次激活期逐箱计数，班末与计划量比对，偏差百分比超容差即告警并保持至下班次启动；/ Shift case tally with plan-deviation alarm: counts cases while the shift is active, compares against plan at shift end, alarms when deviation exceeds tolerance and holds until the next shift starts
  溯源        : 借 ROADMAP P2（BidirectionalCounter/OeeCalculator 口径复用），clean-room 实现
  Boundary    : ① 组态闸：计划量 < 1 / 容差 < 0 → 锁存故障（计划量 0 使偏差比无定义）；
                ② 除零前置：偏差比除子为计划量，组态闸保证 >= 1；
                ③ 计数仅在 eCount 相（班次激活）沿触发累加，班末（bShiftEnd 沿）一次性结算；
                ④ 台账语义：eDone 相保持 nActual/fDevPct/bDevAlarm 电平（锁存副本），不随实时量回落（族② 口径）；
                ⑤ 下班次 bShiftStart 沿清台账开新班（唯一清零路径，另有复位沿全清）；
                ⑥ 本件只做台账与告警，不执行停机（属主边界）。
*)
TYPE E_DL_CstState :
(
    eIdle  := 0,                             (* 待班次启动 / Waiting shift start *)
    eCount := 10,                            (* 班次计数中 / Counting *)
    eDone  := 20,                            (* 班末结算完成（保持台账） / Settled, tally held *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_CstCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：计划量/容差越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CaseShiftTally
VAR_INPUT
    bCasePass   : BOOL := FALSE;             (* 单箱过站脉冲（上升沿计一箱）[-] / One case passed pulse *)
    nPlanQty    : UDINT := 100;              (* 班次计划箱数，域 >= 1 [箱] / Planned case quantity, >= 1 *)
    fTolPct     : REAL := 10.0;              (* 偏差告警容差，域 >= 0 [%] / Deviation tolerance, >= 0 *)
    bShiftActive: BOOL := FALSE;             (* 班次激活电平（计数的门控条件）[-] / Shift active level *)
    bShiftStart : BOOL := FALSE;             (* 班次启动脉冲（清台账开新班）[-] / Shift start pulse *)
    bShiftEnd   : BOOL := FALSE;             (* 班末结算脉冲（一次性比对）[-] / Shift end pulse *)
    bEnable     : BOOL := TRUE;              (* 台账使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清台账与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nActual     : UDINT;                     (* 本班实际箱数（eDone 相保持）[箱] / Actual case count, held in done phase *)
    fDevPct     : REAL;                      (* 计划偏差百分比（eDone 相保持）[%] / Plan deviation percentage, held *)
    bDevAlarm   : BOOL;                      (* 偏差超容差告警（eDone 相保持，复位/新班清）[-] / Deviation alarm, held *)
    bSettled    : BOOL;                      (* 班末结算完成电平（eDone 相为 TRUE）[-] / Settled level *)
    eState      : E_DL_CstState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_CstCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_CstState := E_DL_CstState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_CstCause := E_DL_CstCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtCase   : R_TRIG;                       (* 过箱脉冲沿实例，段 0 无条件调用 / Case pulse edge *)
    rtStart  : R_TRIG;                       (* 班次启动沿实例，段 0 无条件调用 / Shift start edge *)
    rtEnd    : R_TRIG;                       (* 班末脉冲沿实例，段 0 无条件调用 / Shift end edge *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _nCnt    : UDINT;                        (* 本班计数内部量（出口锁存副本源）[箱] / Internal tally, source of held outlet *)
    _fDevI   : REAL;                         (* 偏差比中间量 [%] / Deviation intermediate *)
    _bAlarmI : BOOL;                         (* 告警内部量（锁存副本源）[-] / Alarm internal, source of held outlet *)
    _fSign   : REAL;                         (* 偏差方向符号中间量（+超产/-欠产）[-] / Deviation sign intermediate *)
END_VAR
VAR CONSTANT
    DL_CST_EPS    : REAL  := 1.0E-6;         (* 判零容差 [-] / Epsilon *)
    DL_CST_CNTMAX : UDINT := 4294967295;     (* 计数饱和上限（R28）[-] / Count saturation cap *)
    DL_CST_HUND   : REAL  := 100.0;          (* 百分数换算常量（乘性常量）[-] / Percent scale constant *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；四 R_TRIG 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (nPlanQty < 1) OR (fTolPct < 0.0);                                 (* 计划量下限闸 + 容差非负闸 / Plan and tolerance gates *)
rtCase(CLK := bCasePass);                                                      (* 过箱沿每拍必调 / Case edge every scan *)
rtStart(CLK := bShiftStart);                                                   (* 班启动沿每拍必调 / Start edge every scan *)
rtEnd(CLK := bShiftEnd);                                                       (* 班末沿每拍必调 / End edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107；nActual/fDevPct/bDevAlarm 为锁存出口，不在此预清，族② 口径） —— *)
_bAlarmI := FALSE;                                                             (* 告警内部量预清（结算拍重算） / Alarm internal preset *)
_fDevI := 0.0;                                                                 (* 偏差中间量预清 / Deviation preset *)
_fSign := 1.0;                                                                 (* 方向符号预置（默认超产方向） / Sign preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清台账 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CstCause.eNone;                                            (* 清成因 / Clear cause *)
    _nCnt := 0;                                                                (* 清计数内部量 / Clear tally internal *)
    nActual := 0;                                                              (* 清实际数出口 / Clear actual outlet *)
    fDevPct := 0.0;                                                            (* 清偏差出口 / Clear deviation outlet *)
    bDevAlarm := FALSE;                                                        (* 清告警出口 / Clear alarm outlet *)
    bSettled := FALSE;                                                         (* 清结算电平出口 / Clear settled outlet *)
    _eState := E_DL_CstState.eIdle;                                            (* 迁待班相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_CstCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_CstState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_CstState.eIdle:                                                       (* 待班次启动：台账空 / Idle *)
        _nCnt := 0;                                                            (* 待班清计数（防隐性回夹） / Clear tally *)
        nActual := 0;                                                          (* 待班清实际数出口 / Clear actual outlet *)
        fDevPct := 0.0;                                                        (* 待班清偏差出口 / Clear deviation outlet *)
        bDevAlarm := FALSE;                                                    (* 待班清告警出口 / Clear alarm outlet *)
        bSettled := FALSE;                                                     (* 待班清结算电平 / Clear settled outlet *)
        IF bEnable AND NOT _bFault THEN
            IF rtStart.Q THEN                                                  (* 班次启动沿：开新班（唯一清零路径之一） / Shift start edge: open new shift *)
                _nCnt := 0;                                                    (* 新班计数从零起 / New tally from zero *)
                _eState := E_DL_CstState.eCount;                               (* 进计数相 / To counting *)
            END_IF
        END_IF
    E_DL_CstState.eCount:                                                       (* 计数相：班次激活期逐箱累加 / Counting *)
        IF NOT bEnable THEN
            _eState := E_DL_CstState.eIdle;                                    (* 失能回待班（台账清） / Back to idle *)
        ELSE
            IF rtStart.Q THEN                                                  (* 计数中再收启动沿：视为重开班，清零重计 / Restart shift on new start edge *)
                _nCnt := 0;                                                    (* 重开班清零 / Restart from zero *)
            END_IF
            IF rtCase.Q AND bShiftActive THEN                                  (* 班次激活 + 过箱沿：计一箱 / Count on case edge while active *)
                IF _nCnt < DL_CST_CNTMAX THEN
                    _nCnt := _nCnt + 1;                                        (* 计数净额 +1（饱和防回绕，R28） / Net +1, saturated *)
                END_IF
            END_IF
            IF rtEnd.Q THEN                                                    (* 班末沿：一次性结算比对 / Shift end edge: settle once *)
                nActual := _nCnt;                                              (* 实际数出口（锁存副本，eDone 相保持） / Actual outlet, held *)
                _fSign := UDINT_TO_REAL(_nCnt) - UDINT_TO_REAL(nPlanQty);      (* 偏差绝对量（有符号方向）[箱] / Signed deviation *)
                fDevPct := _fSign / UDINT_TO_REAL(nPlanQty) * DL_CST_HUND;     (* 偏差比：除子计划量 >= 1 由组态闸保证 [%] / Deviation ratio, divisor gated *)
                IF ABS(fDevPct) > fTolPct THEN
                    _bAlarmI := TRUE;                                          (* 超容差：告警内部量置位 / Over tolerance *)
                END_IF
                bDevAlarm := _bAlarmI;                                         (* 告警出口（锁存副本，保持至新班/复位） / Alarm outlet, held *)
                bSettled := TRUE;                                              (* 结算完成电平置位 / Settled level *)
                _eState := E_DL_CstState.eDone;                                (* 迁完成相（保持台账） / To done *)
            END_IF
        END_IF
    E_DL_CstState.eDone:                                                        (* 完成相：保持台账至下班次启动（族② 保持语义） / Done: hold tally *)
        IF NOT bEnable THEN
            _eState := E_DL_CstState.eIdle;                                    (* 失能回待班（出口随 eIdle 清） / Back to idle *)
        ELSIF rtStart.Q THEN                                                   (* 新班启动沿：清台账重开（唯一保持出口路径） / New shift: clear and restart *)
            _nCnt := 0;                                                        (* 新班计数从零起 / New tally from zero *)
            nActual := 0;                                                      (* 清实际数出口 / Clear actual outlet *)
            fDevPct := 0.0;                                                    (* 清偏差出口 / Clear deviation outlet *)
            bDevAlarm := FALSE;                                                (* 清告警出口 / Clear alarm outlet *)
            bSettled := FALSE;                                                 (* 清结算电平 / Clear settled outlet *)
            _eState := E_DL_CstState.eCount;                                   (* 进新班计数相 / To counting *)
        END_IF
    E_DL_CstState.eFault:                                                       (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CstState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_CstCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
