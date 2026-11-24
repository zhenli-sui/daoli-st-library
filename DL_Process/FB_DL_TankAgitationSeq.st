(*
  Name        : FB_DL_TankAgitationSeq
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 搅拌槽搅拌时序：低速分散 → 高速搅拌 → 维持计时三相编排，液位低禁高速，扭矩过载确认降速回退，转速设定斜坡防冲击；/ Tank agitation sequence: low-speed dispersion, high-speed mixing and hold timing phases, level-low interlock against high speed, torque overload confirmed ramp-down, ramped speed setpoint
  溯源        : 借 isa88 的相语义扩族组织，clean-room 实现
  Boundary    : ① 液位低 → 禁止高速相（联锁），高速已运行则降速回退相；
                ② 扭矩过载判据经确认延时（TON）才降速，瞬时尖峰不误动；
                ③ 三相计时 TON 段 0 无条件刷新 + 相位闸（R40）；
                ④ 降速回退相与故障相分离：回退可恢复（液位/扭矩恢复后重回低速相），组态故障才锁存至复位沿；
                ⑤ 转速设定斜坡逼近防机械冲击；非有限扭矩该拍不判过载（保持当前相）；
                ⑥ 本件为时序编排层，输出转速设定值，不直接驱动变频器（属主边界）。
*)
TYPE E_DL_TasState :
(
    eIdle    := 0,                           (* 未运行（设定转速斜坡回零） / Idle *)
    eLowSpd  := 10,                          (* 低速分散相 / Low-speed dispersion *)
    eHighSpd := 20,                          (* 高速搅拌相 / High-speed mixing *)
    eMaintain:= 30,                          (* 维持计时相 / Hold timing *)
    eRampDn  := 40,                          (* 降速回退相（可恢复，边界④） / Ramp-down recovery *)
    eFault   := 90                           (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_TasCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：转速/时长/阈值域越界 / Illegal config *)
    ePhaseBad  := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_TankAgitationSeq
VAR_INPUT
    bStart   : BOOL := FALSE;                (* 启动时序命令，上升沿受理 [-] / Start command *)
    bLevelLow: BOOL := FALSE;                (* 液位低信号（联锁源）[-] / Level low signal *)
    fTorque  : REAL := 0.0;                  (* 搅拌扭矩 [%] / Agitator torque *)
    fTqOverLim: REAL := 90.0;                (* 扭矩过载阈，域 > 0 [%] / Torque overload limit *)
    tTqConf  : TIME := T#2S;                 (* 过载确认延时，域 > T#0S [ms] / Overload confirm delay *)
    tLowDwell: TIME := T#60S;                (* 低速分散时长，域 > T#0S [ms] / Low-speed dwell *)
    tHighDwell: TIME := T#300S;              (* 高速搅拌时长 [ms] / High-speed dwell *)
    tMaintain: TIME := T#120S;               (* 维持计时时长 [ms] / Hold duration *)
    fSpdLow  : REAL := 60.0;                 (* 低速设定转速 [rpm] / Low speed setpoint *)
    fSpdHigh : REAL := 180.0;                (* 高速设定转速，域 > 低速 [rpm] / High speed setpoint *)
    fRampRate: REAL := 30.0;                 (* 斜坡率，域 > 0 [rpm/s] / Ramp rate *)
    tScan    : TIME := T#100MS;              (* 扫描周期，域 > T#0S [ms] / Scan period *)
    bEnable  : BOOL := TRUE;                 (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障回空闲 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fSpdSet  : REAL;                         (* 转速设定出口（斜坡逼近）[rpm] / Ramped speed setpoint outlet *)
    bRunning : BOOL;                         (* 时序运行中指示 [-] / Sequence running indicator *)
    bSeqDone : BOOL;                         (* 时序完成脉冲（单拍）[-] / Sequence done pulse *)
    bRampDn  : BOOL;                         (* 降速回退中指示（状态可查）[-] / Ramp-down indicator *)
    eState   : E_DL_TasState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_TasCause;                (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_TasState := E_DL_TasState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_TasCause := E_DL_TasCause.eNone;  (* 成因锁存量 / Latched cause *)
    rtStart : R_TRIG;                        (* 启动沿实例，段 0 无条件调用 / Start edge instance *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonLow  : TON;                           (* 低速分散计时（IN 串相位闸，边界③） / Low-speed timer *)
    tonHigh : TON;                           (* 高速搅拌计时（IN 串相位闸） / High-speed timer *)
    tonMaint: TON;                           (* 维持计时（IN 串相位闸） / Hold timer *)
    tonTq   : TON;                           (* 扭矩过载确认计时（IN 串相位 + 有限 + 超限判据，边界②⑤） / Torque confirm timer *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                          (* 扭矩有限性当拍量（边界⑤） / Torque finiteness *)
    _bDoneI : BOOL;                          (* 完成脉冲内部量（统一出口映射，R187） / Done pulse internal *)
    _fTarget: REAL;                          (* 当前相目标转速 [rpm] / Phase target speed *)
    _fStep  : REAL;                          (* 本拍斜坡步长 [rpm] / Ramp step this scan *)
    _fDtSec : REAL;                          (* 扫描周期秒值，域 > eps [s] / Scan period seconds *)
END_VAR
VAR CONSTANT
    DL_TAS_EPS : REAL := 1.0E-6;             (* 判零容差 [-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；TON 全段 0 无 IF 包裹，边界③） —— *)
_bCfgBad := (fSpdLow <= DL_TAS_EPS) OR (fSpdHigh <= fSpdLow)             (* 转速域闸（高速 > 低速） / Speed gates *)
            OR (fTqOverLim <= DL_TAS_EPS) OR (fRampRate <= DL_TAS_EPS)   (* 阈值/斜率正域闸（边界⑤） / Limit and rate gates *)
            OR NOT (tTqConf > T#0S) OR NOT (tLowDwell > T#0S)            (* 时长域闸（边界③） / Dwell gates *)
            OR NOT (tHighDwell > T#0S) OR NOT (tMaintain > T#0S) OR NOT (tScan > T#0S);   (* 时长域闸续 / Dwell gates cont. *)
rtStart(CLK := bStart);                                  (* 启动沿每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fTorque = fTorque) AND ((fTorque - fTorque) = (fTorque - fTorque));   (* 扭矩 NaN 自反 + Inf 差判闸（边界⑤） / Torque NaN and Inf gate *)
_fDtSec := TIME_TO_LREAL(tScan) / 1000.0;                (* 扫描周期秒化（除子常量 1000） / Scan period seconds *)
_fStep := fRampRate * _fDtSec;                           (* 斜坡步长 = 率 × 周期秒值（边界⑤） / Ramp step *)
tonLow(IN := (_eState = E_DL_TasState.eLowSpd), PT := tLowDwell);        (* 低速计时：相位闸 + 无条件调用（R40） / Low timer *)
tonHigh(IN := (_eState = E_DL_TasState.eHighSpd), PT := tHighDwell);     (* 高速计时：相位闸 + 无条件调用 / High timer *)
tonMaint(IN := (_eState = E_DL_TasState.eMaintain), PT := tMaintain);    (* 维持计时：相位闸 + 无条件调用 / Hold timer *)
tonTq(IN := (_eState = E_DL_TasState.eHighSpd) AND _bFin AND (fTorque > fTqOverLim), PT := tTqConf);   (* 过载确认：相闸 + 有限闸 + 超限直比（边界②⑤） / Torque confirm *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bDoneI := FALSE;                                        (* 完成脉冲内部量预清 / Done preset *)
bSeqDone := FALSE;                                       (* 完成脉冲出口预清 / Done outlet preset *)
bRunning := FALSE;                                       (* 运行指示出口预清（派生拍覆盖） / Running preset *)
bRampDn := FALSE;                                        (* 回退指示出口预清 / Ramp-down preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 回空闲 + 设定归零，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_TasCause.eNone;                      (* 清成因 / Clear cause *)
    _eState := E_DL_TasState.eIdle;                      (* 回空闲相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_TasCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_TasState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_TasState.eIdle:                                 (* 空闲：目标转速 0（斜坡归零防冲击，边界⑤） / Idle *)
        _fTarget := 0.0;                                 (* 目标转速零 / Target zero *)
        IF rtStart.Q AND bEnable AND NOT _bFault AND NOT bLevelLow THEN   (* 启动受理：液位低禁进入（联锁前置，边界①） / Start gating *)
            _eState := E_DL_TasState.eLowSpd;            (* 进入低速分散相 / Enter low-speed *)
        END_IF
    E_DL_TasState.eLowSpd:                               (* 低速分散相：计时满且液位不低 → 高速 / Low-speed *)
        _fTarget := fSpdLow;                             (* 目标 = 低速设定 / Target low speed *)
        bRunning := TRUE;                                (* 运行指示出口 / Running indicator *)
        IF NOT bEnable THEN
            _eState := E_DL_TasState.eIdle;              (* 失能回空闲 / Back to idle *)
        ELSIF tonLow.Q AND NOT bLevelLow THEN            (* 计时满 + 液位不低才进高速（联锁，边界①） / Dwell done and level ok *)
            _eState := E_DL_TasState.eHighSpd;           (* 进入高速搅拌相 / Enter high-speed *)
        END_IF
    E_DL_TasState.eHighSpd:                              (* 高速搅拌相：液位低/过载回退，计时满 → 维持 / High-speed *)
        _fTarget := fSpdHigh;                            (* 目标 = 高速设定 / Target high speed *)
        bRunning := TRUE;                                (* 运行指示出口 / Running indicator *)
        IF NOT bEnable THEN
            _eState := E_DL_TasState.eIdle;              (* 失能回空闲 / Back to idle *)
        ELSIF bLevelLow OR tonTq.Q THEN                  (* 液位低（边界①）或过载确认（边界②）：降速回退 / Level low or overload confirmed *)
            _eState := E_DL_TasState.eRampDn;            (* 进降速回退相（可恢复，边界④） / Enter ramp-down *)
        ELSIF tonHigh.Q THEN
            _eState := E_DL_TasState.eMaintain;          (* 计时满进维持相 / Enter hold *)
        END_IF
    E_DL_TasState.eMaintain:                             (* 维持计时相：低速维持 + 计时满完成 / Hold *)
        _fTarget := fSpdLow;                             (* 维持相目标 = 低速 / Target low speed *)
        bRunning := TRUE;                                (* 运行指示出口 / Running indicator *)
        IF NOT bEnable THEN
            _eState := E_DL_TasState.eIdle;              (* 失能回空闲 / Back to idle *)
        ELSIF tonMaint.Q THEN
            _bDoneI := TRUE;                             (* 时序完成内部置位（R187） / Done internal *)
            _eState := E_DL_TasState.eIdle;              (* 回空闲（设定斜坡归零） / Back to idle *)
        END_IF
    E_DL_TasState.eRampDn:                               (* 降速回退相：斜坡到低速 → 重回低速相（可恢复，边界④） / Ramp-down *)
        _fTarget := fSpdLow;                             (* 回退目标 = 低速 / Target low speed *)
        bRunning := TRUE;                                (* 回退仍属运行（状态可查） / Running indicator *)
        bRampDn := TRUE;                                 (* 回退指示出口 / Ramp-down indicator *)
        IF NOT bEnable THEN
            _eState := E_DL_TasState.eIdle;              (* 失能回空闲 / Back to idle *)
        ELSIF ABS(fSpdSet - fSpdLow) <= _fStep THEN      (* 斜坡到位（容差直比，非浮点等值） / Ramp arrived *)
            _eState := E_DL_TasState.eLowSpd;            (* 重回低速分散相（恢复，边界④） / Back to low-speed *)
        END_IF
    E_DL_TasState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        _fTarget := 0.0;                                 (* 故障相目标归零（安全侧确定值） / Target zero in fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_TasState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_TasCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 4B：设定斜坡逼近（防机械冲击，边界⑤；容差直比防浮点等值抖动） —— *)
IF fSpdSet < (_fTarget - _fStep) THEN
    fSpdSet := fSpdSet + _fStep;                         (* 正向斜坡步进 / Ramp up *)
ELSIF fSpdSet > (_fTarget + _fStep) THEN
    fSpdSet := fSpdSet - _fStep;                         (* 负向斜坡步进 / Ramp down *)
ELSE
    fSpdSet := _fTarget;                                 (* 步长内直达目标 / Reach target *)
END_IF

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；bError/eState 同源，R191） —— *)
bSeqDone := _bDoneI;                                     (* 完成脉冲单拍出口 / Done pulse outlet *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
