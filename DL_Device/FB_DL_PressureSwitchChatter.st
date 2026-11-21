(*
  Name        : FB_DL_PressureSwitchChatter
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : 压力开关抖动诊断：在固定时间窗内统计开关翻转次数并按阈值分 0..3 档，给出抖振告警与阻尼（滤波延时）建议值；/ Diagnose pressure-switch chatter by counting transitions in a fixed time window, grading 0..3, and proposing a debounce time
  溯源        : 借 t2-8-ne107·诊断 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：窗口 <= T#0S / 阈值 < 1 / 阻尼上限 <= T#0S → 锁存故障；
                ② 窗口用自复位 TON（IN := NOT tonWin.Q，R188），到点即结算并清计数，禁外部沿清零；
                ③ 翻转速率除子窗：窗口秒值 > eps（组态闸保证），不产生 Inf；
                ④ 阻尼建议按「半周期 = 窗长 / (2·翻转数)」推算并钳到 [下限, 上限]，不做无界外推；
                ⑤ 分档用整数直比（阈值倍数关系），无浮点等值比较。
*)
TYPE E_DL_PscState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 监视运行 / Monitoring *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_PscCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：窗口/阈值/上限越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PressureSwitchChatter
VAR_INPUT
    bSwitch    : BOOL := FALSE;              (* 压力开关原始电平 [-] / Raw pressure-switch level *)
    tWindow    : TIME := T#10S;              (* 统计窗长，域 > T#0S [ms] / Counting window, > 0 *)
    nChatterThr: INT := 6;                   (* 抖振翻转次数阈值（每窗），域 >= 1 [次] / Chatter transition threshold per window *)
    tDampMax   : TIME := T#2S;               (* 阻尼建议上限，域 > T#0S [ms] / Debounce suggestion ceiling *)
    bEnable    : BOOL := TRUE;               (* 监视使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清计数/分档/故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nFlips     : INT;                        (* 当前窗内翻转次数（实时）[次] / Transitions in current window *)
    nFlipsLast : INT;                        (* 上一完整窗翻转次数（结算值）[次] / Transitions of last closed window *)
    fFlipRate  : REAL;                       (* 翻转速率（每分）[1/min] / Transition rate per minute *)
    nSeverity  : INT;                        (* 抖振档位 0 正常 / 1 轻微 / 2 明显 / 3 严重 [-] / Severity grade 0..3 *)
    bChatter   : BOOL;                       (* 抖振告警（档位 >= 2）[-] / Chatter alarm, grade >= 2 *)
    tDampSuggest : TIME;                     (* 阻尼（去抖延时）建议值 [ms] / Suggested debounce time *)
    eState     : E_DL_PscState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_PscCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_PscState := E_DL_PscState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_PscCause := E_DL_PscCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtSwitch : R_TRIG;                       (* 开关上升沿实例，段 0 无条件调用 / Switch rising edge *)
    ftSwitch : F_TRIG;                       (* 开关下降沿实例，段 0 无条件调用 / Switch falling edge *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonWin   : TON;                          (* 统计窗自复位计时器（R188） / Self-resetting window timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _nFlips  : INT;                          (* 窗内翻转累加量 [次] / Transition accumulator *)
    _fWinSec : REAL;                         (* 窗长秒值 [s] / Window length in seconds *)
    _fRate   : REAL;                         (* 速率中间量 [1/min] / Rate intermediate *)
    _fHalf   : REAL;                         (* 半周期推算值 [ms] / Half-period estimate *)
    _fDampMs : REAL;                         (* 阻尼建议毫秒值 [ms] / Debounce suggestion in ms *)
    _fDampMax: REAL;                         (* 阻尼上限毫秒值 [ms] / Debounce ceiling in ms *)
END_VAR
VAR CONSTANT
    DL_PSC_EPS   : REAL := 1.0E-6;           (* 判零容差 [-] / Epsilon *)
    DL_PSC_MINPER: REAL := 60000.0;          (* 分钟毫秒数（速率换算常量）[ms] / Milliseconds per minute *)
    DL_PSC_SEV2  : INT  := 2;                (* 档 2 倍数：> 2×阈值 / Grade 2 multiplier *)
    DL_PSC_SEV3  : INT  := 4;                (* 档 3 倍数：> 4×阈值 / Grade 3 multiplier *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；沿/定时器全在段 0，无 IF 包裹） —— *)
_fWinSec := TIME_TO_LREAL(tWindow) / 1000.0;                                   (* 窗长秒化（除子常量 1000） / Window to seconds *)
_fDampMax := TIME_TO_LREAL(tDampMax);                                          (* 阻尼上限毫秒值 / Ceiling in ms *)
_bCfgBad := NOT (tWindow > T#0S)                                               (* 窗长正域闸 / Window gate *)
            OR (nChatterThr < 1)                                               (* 阈值域闸 / Threshold gate *)
            OR NOT (tDampMax > T#0S);                                          (* 阻尼上限正域闸 / Ceiling gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
rtSwitch(CLK := bSwitch);                                                      (* 上升沿每拍必调 / Rising edge every scan *)
ftSwitch(CLK := bSwitch);                                                      (* 下降沿每拍必调 / Falling edge every scan *)
tonWin(IN := NOT tonWin.Q, PT := tWindow);                                     (* 窗自复位（R188，禁外部沿清零） / Self-resetting window *)

(* —— 段 1：单拍量预清零（R107） —— *)
bChatter := FALSE;                                                             (* 抖振告警预清 / Chatter alarm preset *)
nSeverity := 0;                                                                (* 档位预清为 0 / Severity preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 清分档 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_PscCause.eNone;                                            (* 清成因 / Clear cause *)
    _nFlips := 0;                                                              (* 清窗内计数 / Clear accumulator *)
    nFlips := 0;                                                               (* 清实时出口 / Clear live outlet *)
    nFlipsLast := 0;                                                           (* 清结算出口 / Clear closed outlet *)
    fFlipRate := 0.0;                                                          (* 清速率出口 / Clear rate outlet *)
    tDampSuggest := T#0S;                                                      (* 清阻尼建议 / Clear suggestion *)
    _eState := E_DL_PscState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_PscCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_PscState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PscState.eIdle:                                                       (* 未使能：不计数 / Disabled *)
        _nFlips := 0;                                                          (* 失能清计数（防隐性回夹） / Clear accumulator *)
        nFlips := 0;                                                           (* 实时出口清零 / Live outlet cleared *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_PscState.eMon;                                     (* 使能进入监视 / Enter monitoring *)
        END_IF
    E_DL_PscState.eMon:                                                        (* 监视相：窗内计翻转 + 到点结算 / Monitoring *)
        IF NOT bEnable THEN
            _eState := E_DL_PscState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            IF rtSwitch.Q OR ftSwitch.Q THEN
                _nFlips := _nFlips + 1;                                        (* 双沿均计一次（上升+下降共 2 次/周期） / Count both edges *)
            END_IF
            nFlips := _nFlips;                                                 (* 实时出口 / Live outlet *)
            _fRate := DINT_TO_REAL(_nFlips) / _fWinSec * 60.0;                 (* 折算每分钟（除子窗秒已过闸）[1/min] / Rate per minute *)
            fFlipRate := _fRate;                                               (* 速率出口 / Rate outlet *)
            IF tonWin.Q THEN                                                   (* 窗到点：结算 / Window elapsed: settle *)
                nFlipsLast := _nFlips;                                         (* 结算值锁存到上窗出口 / Latch closed count *)
                IF _nFlips > (nChatterThr * DL_PSC_SEV3) THEN
                    nSeverity := 3;                                            (* 严重：> 4× 阈值 / Severe *)
                    bChatter := TRUE;                                          (* 抖振告警 / Chatter alarm *)
                ELSIF _nFlips > (nChatterThr * DL_PSC_SEV2) THEN
                    nSeverity := 2;                                            (* 明显：> 2× 阈值 / Obvious *)
                    bChatter := TRUE;                                          (* 抖振告警 / Chatter alarm *)
                ELSIF _nFlips > nChatterThr THEN
                    nSeverity := 1;                                            (* 轻微：> 1× 阈值 / Slight *)
                ELSE
                    nSeverity := 0;                                            (* 正常 / Normal *)
                END_IF
                IF _nFlips > 0 THEN
                    _fHalf := TIME_TO_LREAL(tWindow) / DINT_TO_REAL(_nFlips);  (* 平均半周期（除子已判 > 0）[ms] / Mean half period *)
                    _fDampMs := _fHalf * 0.5;                                  (* 建议阻尼取半周期一半（保守取值）[ms] / Suggested debounce *)
                    IF _fDampMs > _fDampMax THEN
                        _fDampMs := _fDampMax;                                 (* 上限钳位（无界外推禁止） / Ceiling clamp *)
                    ELSIF _fDampMs < 1.0 THEN
                        _fDampMs := 1.0;                                       (* 下限钳位 1 ms / Floor clamp *)
                    END_IF
                    tDampSuggest := LREAL_TO_TIME(_fDampMs);                   (* 建议值出口 [ms] / Suggestion outlet *)
                ELSE
                    tDampSuggest := T#0S;                                      (* 无翻转：无需阻尼 / No transitions: no debounce *)
                END_IF
                _nFlips := 0;                                                  (* 计数清零，新窗起算（自复位计时器同拍已回 0） / Restart window *)
            END_IF
        END_IF
    E_DL_PscState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PscState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_PscCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
