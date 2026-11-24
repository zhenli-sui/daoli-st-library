(*
  Name        : FB_DL_LabelWeekCode
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 标签周码/批码打印窗：由年 + 年内日序折算 YYWW 周码，打印请求沿在打印机就绪时发出打印脉冲并锁存周码至请求撤除；/ Label week-code print window: derives a YYWW week code from year and day-of-year, issues a print pulse on request edge when the printer is ready, and latches the code until the request clears
  溯源        : 借 ROADMAP P2（WeekOfYearCalc/DateCoderSync 口径复用），clean-room 实现
  Boundary    : ① 组态闸：年份域 2020..2099 / 年内日序域 1..366 / 打印窗长 > 0 → 锁存故障；
                ② 周码折算：周数 = TRUNC((年内日序 - 1) / 7) + 1（1..53，除子为常量 7，无运行期除零）；
                ③ 打印脉冲 _bPrnC 内部置位 → 段 5 统一出口映射单拍（R187），CASE 内不直写；
                ④ 打印窗计时用 TON 串 ePrint 相位闸（族③），段 0 无 IF 包裹；
                ⑤ nWeekCode 在 eDone 相保持（锁存副本），bPrintReq 撤除沿才回落（族② 保持语义）；
                ⑥ 本件只产生码与脉冲，不驱动打印头（属主边界）。
*)
TYPE E_DL_LwcState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eReady := 10,                            (* 就绪：等待打印请求（已算码） / Ready *)
    ePrint := 20,                            (* 打印窗进行中 / Printing window *)
    eDone  := 30,                            (* 打印完成（保持周码） / Done, code held *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_LwcCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：年份/日序/窗长越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_LabelWeekCode
VAR_INPUT
    nYear     : INT := 2026;                 (* 当前年份，域 2020..2099 [年] / Current year, 2020..2099 *)
    nDayOfYear: INT := 1;                    (* 年内日序（1..366），域 1..366 [日] / Day of year, 1..366 *)
    bPrintReq : BOOL := FALSE;               (* 打印请求电平（上升沿发起）[-] / Print request level *)
    bPrnReady : BOOL := FALSE;               (* 打印机就绪电平 [-] / Printer ready level *)
    tWinLen   : TIME := T#500MS;             (* 打印脉冲窗长，域 > T#0S [ms] / Print pulse window, > 0 *)
    bEnable   : BOOL := TRUE;                (* 使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清周码与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nWeekCode : INT;                         (* YYWW 周码（eDone 相保持；低 2 位周数、高位年份后两位）[-] / YYWW week code, held *)
    nWeekNo   : INT;                         (* 年内周数 1..53 [周] / Week number, 1..53 *)
    bPrintPuls: BOOL;                        (* 打印脉冲（窗长电平，tWinLen 定义宽度）[-] / Print pulse level over window *)
    bCodeValid: BOOL;                        (* 周码有效电平（eDone 相为 TRUE）[-] / Code-valid level *)
    eState    : E_DL_LwcState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_LwcCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_LwcState := E_DL_LwcState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_LwcCause := E_DL_LwcCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReq    : R_TRIG;                       (* 打印请求沿实例，段 0 无条件调用 / Request edge instance *)
    rtReqOff : R_TRIG;                       (* 请求撤除沿实例，段 0 无条件调用 / Request-clear edge instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonWin   : TON;                          (* 打印脉冲窗计时器（IN 串 ePrint 相位） / Print window timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bPrnC   : BOOL;                         (* 打印脉冲窗电平内部量（出口统一映射，R187） / Print-pulse internal level *)
    _nWeekI  : INT;                          (* 周数中间量（折算）[周] / Week number intermediate *)
    _nCodeI  : INT;                          (* 周码中间量（YYWW）[-] / Week code intermediate *)
END_VAR
VAR CONSTANT
    DL_LWC_YMIN  : INT := 2020;              (* 年份域下限 [年] / Year domain floor *)
    DL_LWC_YMAX  : INT := 2099;              (* 年份域上限（YY 码两位十进制安全域）[年] / Year domain ceiling *)
    DL_LWC_DMAX  : INT := 366;               (* 年内日序域上限（含闰年）[日] / Day-of-year domain ceiling *)
    DL_LWC_WMAX  : INT := 53;                (* 周数域上限（折算自洽校验用）[周] / Week number ceiling *)
    DL_LWC_SEVEN : INT := 7;                 (* 周折算除子（常量，无运行期除零）[日/周] / Week divisor *)
    DL_LWC_HUND  : INT := 100;               (* YYWW 折算乘数（常量）[-] / YYWW multiplier *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG/TON 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (nYear < DL_LWC_YMIN) OR (nYear > DL_LWC_YMAX)                     (* 年份域闸 / Year gate *)
            OR (nDayOfYear < 1) OR (nDayOfYear > DL_LWC_DMAX)                  (* 日序域闸 / Day-of-year gate *)
            OR NOT (tWinLen > T#0S);                                           (* 窗长正域闸 / Window gate *)
rtReq(CLK := bPrintReq);                                                       (* 请求沿每拍必调 / Request edge every scan *)
rtReqOff(CLK := NOT bPrintReq);                                                (* 请求撤除沿每拍必调 / Request-clear edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
tonWin(IN := (_eState = E_DL_LwcState.ePrint) AND bPrintReq, PT := tWinLen);   (* 打印窗计时（串 ePrint 相位闸，族③） / Print timer with phase gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bPrnC := FALSE;                                                               (* 打印脉冲内部量预清 / Print-pulse preset *)
bPrintPuls := FALSE;                                                           (* 打印脉冲出口预清 / Print-pulse outlet preset *)
bCodeValid := FALSE;                                                           (* 码有效电平预清 / Code-valid preset *)
_nWeekI := 0;                                                                  (* 周数中间量预清 / Week intermediate preset *)
_nCodeI := 0;                                                                  (* 码中间量预清 / Code intermediate preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清周码 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_LwcCause.eNone;                                            (* 清成因 / Clear cause *)
    nWeekCode := 0;                                                            (* 清周码出口 / Clear code outlet *)
    nWeekNo := 0;                                                              (* 清周数出口 / Clear week outlet *)
    bCodeValid := FALSE;                                                       (* 清码有效电平 / Clear validity level *)
    _eState := E_DL_LwcState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_LwcCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_LwcState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_LwcState.eIdle:                                                       (* 未使能：出口确定值 / Disabled *)
        nWeekCode := 0;                                                        (* 失能清周码出口 / Clear code outlet *)
        nWeekNo := 0;                                                          (* 失能清周数出口 / Clear week outlet *)
        bCodeValid := FALSE;                                                   (* 失能清码有效电平 / Clear validity level *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_LwcState.eReady;                                   (* 使能进入就绪 / Enter ready *)
        END_IF
    E_DL_LwcState.eReady:                                                      (* 就绪相：折算周码待打印请求 / Ready *)
        IF NOT bEnable THEN
            _eState := E_DL_LwcState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            _nWeekI := TRUNC(INT_TO_REAL(nDayOfYear - 1) / INT_TO_REAL(DL_LWC_SEVEN)) + 1;   (* 周数折算 = TRUNC((日序-1)/7)+1（除子常量，边界②） / Week number derivation *)
            IF _nWeekI > DL_LWC_WMAX THEN
                _nWeekI := DL_LWC_WMAX;                                        (* 周数上限饱和（最后一次写） / Week ceiling, last write *)
            END_IF
            nWeekNo := _nWeekI;                                                (* 周数出口 / Week outlet *)
            _nCodeI := (nYear MOD DL_LWC_HUND) * DL_LWC_HUND + _nWeekI;        (* YYWW 码 = (年 MOD 100)×100 + 周（乘除均为常量） / YYWW code *)
            nWeekCode := _nCodeI;                                              (* 周码出口（就绪相即为当前码） / Code outlet *)
            IF rtReq.Q AND bPrnReady THEN                                      (* 请求沿 + 就绪：发起打印 / Request edge with ready *)
                _bPrnC := TRUE;                                                (* 打印脉冲内部置位（出口统一映射，R187） / Print-pulse internal *)
                _eState := E_DL_LwcState.ePrint;                               (* 进打印窗相 / To printing *)
            END_IF
        END_IF
    E_DL_LwcState.ePrint:                                                       (* 打印窗相：脉冲电平保持窗长 / Printing *)
        IF NOT bEnable THEN
            _eState := E_DL_LwcState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            _bPrnC := TRUE;                                                    (* 打印窗内脉冲电平保持（窗长由 tonWin 定义） / Pulse level held over window *)
            bCodeValid := TRUE;                                                (* 打印期码有效电平 / Validity level during print *)
            IF rtReqOff.Q THEN                                                 (* 请求撤除沿：提前结束窗 / Request cleared: end window *)
                _eState := E_DL_LwcState.eDone;                                (* 迁完成相（保持周码） / To done *)
            ELSIF tonWin.Q THEN                                                (* 窗长到点：打印完成 / Window elapsed: done *)
                _eState := E_DL_LwcState.eDone;                                (* 迁完成相 / To done *)
            END_IF
        END_IF
    E_DL_LwcState.eDone:                                                       (* 完成相：保持周码至请求撤除后的新请求（族② 保持语义） / Done: hold code *)
        IF NOT bEnable THEN
            _eState := E_DL_LwcState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF rtReq.Q THEN                                                     (* 新打印请求沿：重新折算再打印 / New request: re-derive and print *)
            _eState := E_DL_LwcState.eReady;                                   (* 回就绪相重折算 / Back to ready *)
        END_IF
    E_DL_LwcState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_LwcState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_LwcCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出，R187；名实双出口，R191） —— *)
bPrintPuls := _bPrnC;                                                          (* 打印脉冲单拍出口 / Print-pulse single-scan outlet *)
bCodeValid := bCodeValid OR (_eState = E_DL_LwcState.eDone);                   (* 码有效电平（打印期与保持期均为 TRUE，族②） / Validity level held in done *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
