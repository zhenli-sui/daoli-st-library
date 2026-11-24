(*
  Name        : FB_DL_PulseTrainDecoder
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 脉冲串解码：统计脉冲总数，按脉宽宽/窄逐位移入编码字，间隔超窗即判整字完成并锁存输出（编码旋钮/拨码开关读入）；/ Pulse-train decoder: counts pulses, shifts wide/narrow pulse bits into a code word, and latches the word when the inter-pulse gap window elapses (encoder knob / DIP-switch read-in)
  溯源        : 借 t2-1-lgf-bit-logic 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：宽脉冲阈/间隔窗任一 <= 0 或间隔窗 <= 宽阈 → 锁存故障（间隔窗必须显著大于宽阈才可区分字间隔与位间隔）；
                ② 位容量 16 位：位满后继续收到的脉冲只计数不再移位（防溢出回绕破坏编码）；
                ③ 宽窄判据用「脉宽 TON（IN := bPulse）在下降沿读上拍 Q」的上一拍口径，段 0 无 IF 包裹刷新；
                ④ 间隔判定 TON 串 eRx 相位闸（族③），字完成沿由 R_TRIG 提取（R187 两段式）；
                ⑤ nCode/nBits 在 eDone 相保持（锁存副本），直到下一个字首脉冲或复位才刷新（族② 保持语义）；
                ⑥ 本件只解码，不执行旋钮联动逻辑（属主边界）。
*)
TYPE E_DL_PtdState :
(
    eIdle := 0,                              (* 未使能 / Disabled *)
    eRx   := 10,                             (* 收码中（位流移入） / Receiving *)
    eDone := 20,                             (* 字完成（保持编码） / Word complete, held *)
    eFault:= 90                              (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_PtdCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：宽阈/间隔窗越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PulseTrainDecoder
VAR_INPUT
    bPulse   : BOOL := FALSE;                (* 脉冲串输入电平 [-] / Pulse-train input *)
    tWideMin : TIME := T#30MS;               (* 宽脉冲下限（脉宽 >= 此值判 1），域 > T#0S [ms] / Wide-pulse threshold, > 0 *)
    tGapMax  : TIME := T#300MS;              (* 位间隔窗（间隔超此值判整字结束），域 > 宽阈 [ms] / Bit-gap window, > wide threshold *)
    bEnable  : BOOL := TRUE;                 (* 解码使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清计数与编码 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nPulseCnt: UDINT;                        (* 累计脉冲总数（饱和）[个] / Total pulse count, saturated *)
    nCode    : UDINT;                        (* 最近完成字的编码值（eDone 相保持）[-] / Last completed word code, held *)
    nBits    : INT;                          (* 最近完成字位数（eDone 相保持）[位] / Last completed word bit count, held *)
    bWordDone: BOOL;                         (* 字完成单拍脉冲 [-] / Word-complete single-scan pulse *)
    bRxOn    : BOOL;                         (* 收码进行中电平（eRx 相为 TRUE）[-] / Receiving level *)
    eState   : E_DL_PtdState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_PtdCause;                (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_PtdState := E_DL_PtdState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_PtdCause := E_DL_PtdCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtPulse  : R_TRIG;                       (* 脉冲上升沿实例，段 0 无条件调用 / Pulse rising edge *)
    rtFall   : R_TRIG;                       (* 脉冲下降沿实例，段 0 无条件调用 / Pulse falling edge *)
    rtGap    : R_TRIG;                       (* 间隔窗到点沿实例，段 0 无条件调用 / Gap-elapsed edge *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonWidth : TON;                          (* 脉宽测量计时器（IN := bPulse，下降沿读上拍 Q） / Pulse-width timer *)
    tonGap   : TON;                          (* 位间隔窗计时器（IN 串 eRx 相位） / Bit-gap timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bWide   : BOOL;                         (* 当前位宽窄当拍量（宽 = TRUE）[-] / Current bit wide flag *)
    _nCodeI  : UDINT;                        (* 收码移位寄存器内部量 [-] / Code shift register internal *)
    _nBitsI  : INT;                          (* 收码位数内部量 [位] / Bit count internal *)
    _bDoneC  : BOOL;                         (* 字完成内部单拍量（出口统一映射，R187） / Word-done internal pulse *)
END_VAR
VAR CONSTANT
    DL_PTD_CNTMAX : UDINT := 4294967295;     (* 脉冲计数饱和上限（R28）[-] / Pulse count saturation cap *)
    DL_PTD_BITMAX : INT   := 16;             (* 编码位容量上限（UDINT 移位安全域）[位] / Bit capacity limit *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG/TON 全在段 0，无 IF 包裹） —— *)
_bCfgBad := NOT (tWideMin > T#0S)                                              (* 宽脉冲阈正域闸 / Wide threshold gate *)
            OR NOT (tGapMax > T#0S)                                            (* 间隔窗正域闸 / Gap window gate *)
            OR (tGapMax <= tWideMin);                                          (* 间隔窗须大于宽阈（防位间隔误判字结束） / Gap window above wide threshold *)
rtPulse(CLK := bPulse);                                                        (* 上升沿每拍必调 / Rising edge every scan *)
rtFall(CLK := NOT bPulse);                                                     (* 下降沿每拍必调 / Falling edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
tonWidth(IN := bPulse, PT := tWideMin);                                        (* 脉宽测量（下降沿读上拍 Q = 本脉冲是否够宽，边界③） / Width timer, prior-scan read at fall *)
tonGap(IN := (_eState = E_DL_PtdState.eRx) AND NOT bPulse, PT := tGapMax);     (* 位间隔窗（串 eRx 相位闸，族③） / Gap timer with phase gate *)
rtGap(CLK := tonGap.Q);                                                        (* 间隔窗到点沿每拍必调 / Gap edge every scan *)
_bWide := tonWidth.Q;                                                          (* 当前脉宽是否达宽阈（上一拍口径） / Current bit wide verdict *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bDoneC := FALSE;                                                              (* 字完成内部量预清 / Word-done preset *)
bWordDone := FALSE;                                                            (* 字完成出口预清 / Word-done outlet preset *)
bRxOn := FALSE;                                                                (* 收码电平预清 / Rx level preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 清编码 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_PtdCause.eNone;                                            (* 清成因 / Clear cause *)
    nPulseCnt := 0;                                                            (* 清脉冲总数 / Clear pulse count *)
    nCode := 0;                                                                (* 清编码出口 / Clear code outlet *)
    nBits := 0;                                                                (* 清位数出口 / Clear bits outlet *)
    _nCodeI := 0;                                                              (* 清移位寄存器 / Clear shift register *)
    _nBitsI := 0;                                                              (* 清位数内部量 / Clear bit count internal *)
    _eState := E_DL_PtdState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_PtdCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_PtdState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PtdState.eIdle:                                                       (* 未使能：不解码，出口确定值 / Disabled *)
        nPulseCnt := 0;                                                        (* 失能清脉冲总数 / Clear pulse count *)
        nCode := 0;                                                            (* 失能清编码出口 / Clear code outlet *)
        nBits := 0;                                                            (* 失能清位数出口 / Clear bits outlet *)
        _nCodeI := 0;                                                          (* 失能清移位寄存器 / Clear shift register *)
        _nBitsI := 0;                                                          (* 失能清位数内部量 / Clear bit count internal *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_PtdState.eRx;                                      (* 使能进入收码 / Enter receiving *)
        END_IF
    E_DL_PtdState.eRx:                                                         (* 收码相：位流移入 + 间隔判字 / Receiving *)
        IF NOT bEnable THEN
            _eState := E_DL_PtdState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            IF rtPulse.Q THEN                                                  (* 字首脉冲：清移位寄存器重收新字 / First pulse of a word: clear register *)
                _nCodeI := 0;                                                  (* 移位寄存器清零 / Register clear *)
                _nBitsI := 0;                                                  (* 位数清零 / Bit count clear *)
            END_IF
            IF rtPulse.Q THEN                                                  (* 脉冲总数计数（与移位独立） / Total pulse count *)
                IF nPulseCnt < DL_PTD_CNTMAX THEN
                    nPulseCnt := nPulseCnt + 1;                                (* 净额 +1（饱和防回绕，R28） / Net +1, saturated *)
                END_IF
            END_IF
            IF rtFall.Q THEN                                                  (* 脉冲下降沿：本位宽窄已定，移入寄存器 / Bit settle at fall: shift in *)
                IF _nBitsI < DL_PTD_BITMAX THEN
                    _nCodeI := _nCodeI * 2;                                    (* 左移一位（位容量内，无溢出） / Shift left one bit *)
                    IF _bWide THEN
                        _nCodeI := _nCodeI + 1;                                (* 宽脉冲：该位为 1 / Wide bit: 1 *)
                    END_IF
                    _nBitsI := _nBitsI + 1;                                    (* 位数递进 / Bit count advance *)
                END_IF                                                         (* 位满后只计数不移位（边界②） / Beyond capacity: count only *)
            END_IF
            IF rtGap.Q THEN                                                    (* 间隔窗到点：整字结束 / Gap elapsed: word end *)
                IF _nBitsI > 0 THEN                                            (* 至少收到位才算有效字 / Word valid only with bits *)
                    nCode := _nCodeI;                                          (* 编码出口（锁存副本，eDone 相保持） / Code outlet, held *)
                    nBits := _nBitsI;                                          (* 位数出口（锁存副本） / Bits outlet, held *)
                    _bDoneC := TRUE;                                           (* 字完成内部置位（出口统一映射，R187） / Word-done internal *)
                END_IF
                _nCodeI := 0;                                                  (* 寄存器清零（下字重收） / Register clear *)
                _nBitsI := 0;                                                  (* 位数清零 / Bit count clear *)
                IF _bDoneC THEN
                    _eState := E_DL_PtdState.eDone;                            (* 有效字完成迁保持相 / To done on valid word *)
                END_IF
            END_IF
        END_IF
    E_DL_PtdState.eDone:                                                       (* 保持相：编码保持至下字首脉冲 / Done: hold code *)
        IF NOT bEnable THEN
            _eState := E_DL_PtdState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF rtPulse.Q THEN                                                   (* 下一个字首脉冲：回收码相重收 / Next word first pulse: back to rx *)
            _nCodeI := 0;                                                      (* 移位寄存器清零 / Register clear *)
            _nBitsI := 0;                                                      (* 位数清零 / Bit count clear *)
            _eState := E_DL_PtdState.eRx;                                      (* 回收码相 / Back to receiving *)
        END_IF
    E_DL_PtdState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PtdState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_PtdCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出，R187；名实双出口，R191） —— *)
bWordDone := _bDoneC;                                                          (* 字完成单拍出口 / Word-done single-scan outlet *)
bRxOn := (_eState = E_DL_PtdState.eRx);                                        (* 收码电平出口（相位镜像，R191） / Rx level outlet *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
