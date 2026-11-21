(*
  Name        : FB_DL_EnthalpyPrioritySwitch
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 焓值优先切换：新风/回风焓差判据经迟滞双阈 + 驻留确认切换经济器模式，出口为模式枚举（与焓差判定件职责分立）；/ Enthalpy priority switch: outside/return air enthalpy difference through hysteresis band with dwell confirmation switches economizer mode, mode-enum outlet only
  溯源        : 借 oscat-building 的焓值优先切换待挖组织，clean-room 实现
  Boundary    : ① 焓差迟滞带双阈组态闸：切换阈 > 返回阈否则锁存故障（相等不立）；
                ② 切换判据须持续 tHold 驻留才生效（防高频抖动），驻留 TON 断输入归零（R40）；
                ③ 任一温度/湿度派生焓值非有限 → 保持当前模式 + bSensorBad 当拍出口（不切到未知工况）；
                ④ 最小驻留双侧对称：新模式下判据同样须持续 tHold 才切回（双向同参数天然对称）；
                ⑤ 与 R6 焓差判据件分工：本件只输出模式枚举，不做焓差报警（职责不重叠）；
                ⑥ 焓值由属主计算输入，本件零焓值公式内嵌（单一职责）。
*)
TYPE E_DL_EntMode :
(
    eRecirc := 0,                            (* 回风循环模式（经济器关闭） / Recirculation mode *)
    eEcon   := 10                            (* 经济器模式（新风优先） / Economizer mode *)
);
END_TYPE

TYPE E_DL_EntState :
(
    eIdle  := 0,                             (* 未使能（模式保持） / Disabled, mode held *)
    eRun   := 10,                            (* 切换仲裁运行 / Arbitration running *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_EntCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：迟滞带倒挂/驻留越域 / Illegal config *)
    ePhaseBad  := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_EnthalpyPrioritySwitch
VAR_INPUT
    fHOut    : REAL := 30.0;                 (* 新风焓值（属主计算输入）[kJ/kg] / Outside air enthalpy *)
    fHRet    : REAL := 40.0;                 (* 回风焓值（属主计算输入）[kJ/kg] / Return air enthalpy *)
    fSwOn    : REAL := 2.0;                  (* 切换阈：焓差超过此值切经济器，域 > 返回阈 [kJ/kg] / Switch-on threshold *)
    fSwOff   : REAL := 0.5;                  (* 返回阈：焓差低于此值切回循环 [kJ/kg] / Switch-back threshold *)
    tHold    : TIME := T#120S;               (* 判据驻留时间，域 > T#0S [ms] / Dwell time *)
    tScan    : TIME := T#1S;                 (* 扫描周期，域 > T#0S [ms] / Scan period *)
    bEnable  : BOOL := TRUE;                 (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障回循环模式 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    eMode    : E_DL_EntMode;                 (* 当前模式出口（枚举，边界⑤） / Mode outlet *)
    bSensorBad: BOOL;                        (* 焓值失效当拍出口（边界③）[-] / Sensor bad outlet *)
    bEconAct : BOOL;                         (* 经济器激活指示（名实双出口）[-] / Economizer active indicator *)
    eState   : E_DL_EntState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_EntCause;                (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_EntState := E_DL_EntState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_EntCause := E_DL_EntCause.eNone;  (* 成因锁存量 / Latched cause *)
    _eModeI : E_DL_EntMode := E_DL_EntMode.eRecirc;  (* 内部模式（初值循环侧，安全默认） / Internal mode *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonHold : TON;                           (* 判据驻留计时（IN 串判据 + 相位闸，边界②④） / Dwell timer *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFinH  : BOOL;                          (* 双焓值有限性当拍量（边界③） / Enthalpies finiteness *)
    _bToEcon: BOOL;                          (* 切经济器判据当拍量 / To-economizer verdict *)
    _bToRec : BOOL;                          (* 切回循环判据当拍量 / To-recirc verdict *)
    _fDH    : REAL;                          (* 焓差中间量（回风 - 新风）[kJ/kg] / Enthalpy difference *)
END_VAR
VAR CONSTANT
    DL_ENT_EPS : REAL := 1.0E-6;             (* 判零容差 [-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；TON 段 0 无 IF 包裹，边界②） —— *)
_bCfgBad := NOT (fSwOn > fSwOff)                         (* 迟滞带组态闸：切换阈 > 返回阈（边界①） / Band config gate *)
            OR (fSwOff < (-DL_ENT_EPS))                  (* 返回阈非负域闸 / Return threshold gate *)
            OR NOT (tHold > T#0S) OR NOT (tScan > T#0S); (* 驻留/周期域闸（边界②） / Dwell and period gates *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFinH := (fHOut = fHOut) AND ((fHOut - fHOut) = (fHOut - fHOut))        (* 新风焓 NaN 自反 + Inf 差判闸（边界③） / Outdoor NaN and Inf gate *)
         AND (fHRet = fHRet) AND ((fHRet - fHRet) = (fHRet - fHRet));   (* 回风焓 NaN 自反 + Inf 差判闸 / Return NaN and Inf gate *)
_fDH := fHRet - fHOut;                                   (* 焓差 = 回风 - 新风（有限派生） / Enthalpy difference *)
IF NOT _bFinH THEN
    _fDH := 0.0;                                         (* 非有限拍焓差归零（判据失效不误切，边界③） / Difference zeroed *)
END_IF
_bToEcon := _bFinH AND (_fDH > fSwOn);                   (* 切经济器判据（迟滞上阈直比） / To-econ verdict *)
_bToRec := _bFinH AND (_fDH < fSwOff);                   (* 切回循环判据（迟滞下阈直比，边界②） / To-recirc verdict *)
tonHold(IN := ((_eState = E_DL_EntState.eRun) AND (_eModeI = E_DL_EntMode.eRecirc) AND _bToEcon)
             OR ((_eState = E_DL_EntState.eRun) AND (_eModeI = E_DL_EntMode.eEcon) AND _bToRec), PT := tHold);   (* 双向对称驻留（边界②④，R40） / Symmetric dwell timer *)

(* —— 段 1：单拍量预清零（R107） —— *)
bSensorBad := FALSE;                                     (* 传感器失效当拍出口预清 / Sensor bad preset *)
bEconAct := FALSE;                                       (* 激活指示出口预清（派生拍覆盖） / Active preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 模式回循环侧 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_EntCause.eNone;                      (* 清成因 / Clear cause *)
    _eModeI := E_DL_EntMode.eRecirc;                     (* 模式回循环侧（安全默认） / Mode to recirculation *)
    eMode := E_DL_EntMode.eRecirc;                       (* 模式出口同步 / Mode outlet sync *)
    _eState := E_DL_EntState.eIdle;                      (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_EntCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_EntState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_EntState.eIdle:                                 (* 未使能：模式出口保持确定值（状态镜像） / Idle *)
        eMode := _eModeI;                                (* 模式出口镜像（不留陈旧） / Mode outlet mirror *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_EntState.eRun;               (* 进入仲裁相 / Enter arbitration *)
        END_IF
    E_DL_EntState.eRun:                                  (* 仲裁相：判据 + 驻留 + 切换 / Arbitration *)
        IF NOT bEnable THEN
            _eState := E_DL_EntState.eIdle;              (* 失能回未使能（模式保持） / Back to idle *)
        ELSE
            IF NOT _bFinH THEN
                bSensorBad := TRUE;                      (* 焓值失效：保持当前模式（边界③） / Sensor bad hold *)
            ELSIF tonHold.Q THEN                         (* 判据持续满驻留：切换（边界②④） / Dwell elapsed, switch *)
                IF _eModeI = E_DL_EntMode.eRecirc THEN
                    _eModeI := E_DL_EntMode.eEcon;       (* 循环 → 经济器 / To economizer *)
                ELSE
                    _eModeI := E_DL_EntMode.eRecirc;     (* 经济器 → 循环（双向对称，边界④） / To recirculation *)
                END_IF
            END_IF
            eMode := _eModeI;                            (* 模式出口镜像（状态镜像，R191） / Mode outlet mirror *)
        END_IF
    E_DL_EntState.eFault:                                (* 故障相：模式冻结保持，仅复位沿出 / Fault *)
        eMode := _eModeI;                                (* 故障相模式出口保持镜像（确定值） / Mode mirror in fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_EntState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_EntCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（名实双出口，R191；bError/eState 同源） —— *)
bEconAct := (_eModeI = E_DL_EntMode.eEcon);              (* 经济器激活指示镜像 / Economizer active mirror *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
