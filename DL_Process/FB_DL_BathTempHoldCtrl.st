(*
  Name        : FB_DL_BathTempHoldCtrl
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 浸洗槽液温保温控制：两点（bang-bang）控温带回差，叠加液位-加热联锁（液位低于下限立即禁加热，安全侧切断优先于控温目标）；/ Bath temperature hold control: two-point control with hysteresis, interlocked with liquid level (level below floor immediately inhibits heating, safe-side cut-off takes precedence)
  溯源        : 自研/行业池（I_DL_TemperatureZone 口径复用），clean-room 实现
  Boundary    : ① 组态闸：设定温度与回差越域（回差 < 0 或回差 >= 设定一半使工作带倒置）→ 锁存故障；
                ② 液位联锁优先级最高：bHeatCmd 在 eHold 相每拍先过液位闸，低液位当拍强制 FALSE（安全回路语义：不锁存等待，立即切断）；
                ③ 非有限温度/液位该拍按安全侧处理：温度非有限禁加热，液位非有限视同低液位禁加热；
                ④ 控温判据全部 < / > / >= 阈值直比（阈值来自组态，非浮点等值比较）；
                ⑤ bHeatCmd 在 eIdle/eFault 恒 FALSE（出口确定值，不留陈旧值）；bLevelLow 电平随实时液位（诊断），不控输出；
                ⑥ 本件只出加热命令，不驱动接触器/SSR（功率级与安全联锁由上层执行，属主边界）。
*)
TYPE E_DL_BthState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eHold  := 10,                            (* 保温控制运行 / Holding *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_BthCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：设定/回差/液位下限越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BathTempHoldCtrl
VAR_INPUT
    fTemp     : REAL := 20.0;                (* 槽液温度实测 [°C] / Measured bath temperature *)
    fTempSP   : REAL := 60.0;                (* 保温设定温度，域 > 回差 × 2（工作带非倒置）[°C] / Hold setpoint *)
    fHyst     : REAL := 2.0;                 (* 控温回差（开带下沿 = SP - 回差），域 >= 0 且 < SP/2 [K] / Control hysteresis *)
    fLevel    : REAL := 100.0;               (* 槽液位实测（任意液位口径）[%] / Measured bath level *)
    fLevelMin : REAL := 30.0;                (* 液位联锁下限（低于即禁加热），域 >= 0 [%] / Level interlock floor *)
    bEnable   : BOOL := TRUE;                (* 保温使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bHeatCmd  : BOOL;                        (* 加热命令输出（两点控温电平；eIdle/eFault 恒 FALSE）[-] / Heat command output *)
    bHeatInhib: BOOL;                        (* 加热联锁抑制电平（低液位/非有限输入生效）[-] / Heat inhibit level *)
    bLevelLow : BOOL;                        (* 低液位诊断电平（随实时液位）[-] / Low-level diagnostic level *)
    bHeating  : BOOL;                        (* 加热进行中电平（= bHeatCmd 名实镜像，R191）[-] / Heating level mirror *)
    eState    : E_DL_BthState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_BthCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_BthState := E_DL_BthState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_BthCause := E_DL_BthCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinT   : BOOL;                         (* 温度有限性当拍量 / Temperature finiteness *)
    _bFinL   : BOOL;                         (* 液位有限性当拍量 / Level finiteness *)
    _bLvOk   : BOOL;                         (* 液位在位当拍量（有限且 >= 下限） / Level OK this scan *)
    _bInhibI : BOOL;                         (* 联锁抑制内部当拍量 / Inhibit internal this scan *)
    _bHeatI  : BOOL;                         (* 加热命令内部量（出口同源）[-] / Heat command internal *)
END_VAR
VAR CONSTANT
    DL_BTH_EPS   : REAL := 1.0E-6;           (* 判零容差 [-] / Epsilon *)
    DL_BTH_TWO   : REAL := 2.0;              (* 工作带倒置校验除子（常量）[-] / Band-inversion divisor *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fHyst < 0.0)                                                      (* 回差非负闸 / Hysteresis gate *)
            OR (fLevelMin < 0.0)                                               (* 液位下限非负闸 / Level floor gate *)
            OR (fTempSP <= fHyst * DL_BTH_TWO)                                 (* 工作带倒置闸：SP 须大于 2×回差（保证开带下沿 > 0） / Band inversion gate *)
            OR (fTempSP <= DL_BTH_EPS);                                        (* 设定正域闸 / Setpoint gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinT := (fTemp = fTemp) AND ((fTemp - fTemp) = (fTemp - fTemp));             (* 温度 NaN 自反 + Inf 差判闸 / Temperature NaN and Inf gate *)
_bFinL := (fLevel = fLevel) AND ((fLevel - fLevel) = (fLevel - fLevel));       (* 液位 NaN 自反 + Inf 差判闸 / Level NaN and Inf gate *)
_bLvOk := _bFinL AND (fLevel >= fLevelMin);                                    (* 液位在位：有限且 >= 下限（非有限视同不在位，安全侧，边界③） / Level OK: finite and above floor *)
_bInhibI := (NOT _bLvOk);                                                      (* 联锁抑制：液位不在位即抑制（边界② 优先级最高） / Inhibit: level not OK *)

(* —— 段 1：单拍量预清零（R107；bHeatCmd/bHeating 由内部量统一映射，不在段 1 预清陈旧） —— *)
bLevelLow := FALSE;                                                            (* 低液位诊断预清 / Low-level preset *)
bHeatInhib := FALSE;                                                           (* 抑制电平预清 / Inhibit preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清加热命令 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_BthCause.eNone;                                            (* 清成因 / Clear cause *)
    _bHeatI := FALSE;                                                          (* 清加热命令内部量 / Clear heat internal *)
    bHeatCmd := FALSE;                                                         (* 清加热命令出口（安全侧 FALSE） / Clear heat outlet, safe side *)
    bHeating := FALSE;                                                         (* 清加热镜像出口 / Clear mirror outlet *)
    bHeatInhib := FALSE;                                                       (* 清抑制出口 / Clear inhibit outlet *)
    bLevelLow := FALSE;                                                        (* 清低液位出口 / Clear low-level outlet *)
    _eState := E_DL_BthState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_BthCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_BthState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_BthState.eIdle:                                                       (* 未使能：加热命令安全侧 FALSE / Disabled *)
        _bHeatI := FALSE;                                                      (* 失能清加热内部量 / Clear heat internal *)
        bHeatCmd := FALSE;                                                     (* 失能加热命令出口 FALSE（出口确定值） / Heat outlet FALSE *)
        bHeating := FALSE;                                                     (* 失能清镜像出口 / Clear mirror outlet *)
        bHeatInhib := FALSE;                                                   (* 失能清抑制出口 / Clear inhibit outlet *)
        bLevelLow := FALSE;                                                    (* 失能清低液位出口 / Clear low-level outlet *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_BthState.eHold;                                    (* 使能进入保温 / Enter holding *)
        END_IF
    E_DL_BthState.eHold:                                                       (* 保温相：液位联锁优先 + 两点控温 / Holding *)
        IF NOT bEnable THEN
            _eState := E_DL_BthState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            bLevelLow := _bFinL AND (fLevel < fLevelMin);                      (* 低液位诊断电平（有限拍才派生） / Low-level diagnostic *)
            bHeatInhib := _bInhibI;                                            (* 抑制电平出口（名实同源，R191） / Inhibit outlet *)
            IF _bInhibI THEN
                _bHeatI := FALSE;                                              (* 联锁优先：抑制当拍强制断热（安全侧切断优先于控温目标，边界②） / Interlock first: force heat off *)
            ELSIF NOT _bFinT THEN
                _bHeatI := FALSE;                                              (* 温度非有限：禁加热（防误开带，安全侧，边界③） / Non-finite temp: heat off *)
            ELSIF (NOT _bHeatI) AND (fTemp < (fTempSP - fHyst)) THEN
                _bHeatI := TRUE;                                               (* 低于开带下沿：开热（两点控温下沿） / Below band floor: heat on *)
            ELSIF _bHeatI AND (fTemp >= fTempSP) THEN
                _bHeatI := FALSE;                                              (* 达设定值：关热（回差内保持，防频繁切换） / At setpoint: heat off *)
            END_IF
            bHeatCmd := _bHeatI;                                               (* 加热命令出口（同源映射，R191） / Heat command outlet *)
            bHeating := _bHeatI;                                               (* 加热镜像出口（名实双出口） / Heating mirror outlet *)
        END_IF
    E_DL_BthState.eFault:                                                      (* 故障相：加热命令安全侧 FALSE / Fault *)
        _bHeatI := FALSE;                                                      (* 故障相清加热内部量 / Clear heat internal *)
        bHeatCmd := FALSE;                                                     (* 故障相加热命令 FALSE（出口确定值） / Heat outlet FALSE *)
        bHeating := FALSE;                                                     (* 故障相清镜像出口 / Clear mirror outlet *)
        bHeatInhib := FALSE;                                                   (* 故障相清抑制出口 / Clear inhibit outlet *)
        bLevelLow := FALSE;                                                    (* 故障相清低液位出口 / Clear low-level outlet *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _bHeatI := FALSE;                                                      (* 兜底清加热内部量 / Clear heat internal *)
        bHeatCmd := FALSE;                                                     (* 兜底加热命令 FALSE / Heat outlet FALSE *)
        _eState := E_DL_BthState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_BthCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
