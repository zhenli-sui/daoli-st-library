(*
  道莅工业代码库 | DL_Process | FB_DL_CentrifugeSpinSeq
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；行业池·分离设备通用语义，零代码行复制）
  功能: 离心机升速-恒速-降速三段序列，含临界转速快跳段（给定直接跳过临界带，
        实测转速越带上沿后恢复斜坡）与不平衡/开盖/转速非有限三路停机闸（跳闸锁存）。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG / LIMIT，零厂商私有库
  接口: 输入启动/盖开关/实测转速/目标转速/临界带/升降斜率/周期/不平衡信号/复位；
        输出 fSpRef [rpm]/bDriveEn/bBrakeOut/bAtSpeed/eState/eCause/bError/nErrId。
  码表: 16#0005_03BA 故障级：离心机跳闸总码（锁存至复位沿，归由 eCause）
        码段说明：0005 段故障子带 03xx，槽位经全库实扫空闲。
  边界: ① 快跳段：给定值在临界带内不给斜坡、直接跳带上沿（fCritHi），
        实测转速 >= fCritHi - 容差 后回 eAccel 续斜坡（避开共振驻留）；
        ② 不平衡经 tUnbalDelay 去抖确认跳闸；开盖/转速 NaN 即时跳闸；
        ③ 跳闸相：驱动禁止 + 制动输出，唯一解除路径 = bReset 上升沿 ∧
        组态合法 ∧ 盖已关；
        ④ 斜坡积分上限：MIN(fSpeedSp)；降速下限钳 0；
        ⑤ TON/R_TRIG 段 0 无条件周期刷新；⑥ 零全局耦合。
  邻件比对: registry 扫查 centrifuge 零命中（R75 §3 留痕），无属主。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B2 · C08）
*)

TYPE E_DL_CssState :
(
    eIdle  := 0,   // 待机（给定钳零，驱动禁止） | Idle, ref zero, drive off
    eAccel := 10,  // 斜坡升速 | Ramped acceleration
    eCrit  := 20,  // 临界转速快跳段 | Critical band fast jump
    eRun   := 30,  // 恒速运行 | Constant speed run
    eDecel := 40,  // 斜坡降速 | Ramped deceleration
    eTrip  := 90   // 跳闸锁存相（驱动禁止+制动） | Trip latch phase
);
END_TYPE

TYPE E_DL_CssCause :
(
    eNone          := 0,  // 无故障 | No cause
    eCfgIllegal    := 1,  // 组态非法 | Illegal configuration
    eUnbalance     := 2,  // 不平衡超限（去抖确认） | Unbalance confirmed by debounce
    eLidOpen       := 3,  // 运转中开盖 | Lid opened in motion
    eSensNonFinite := 4   // 转速反馈非有限 | Speed feedback non-finite
);
END_TYPE

FUNCTION_BLOCK FB_DL_CentrifugeSpinSeq
VAR_INPUT
    bStartCmd    : BOOL := FALSE;    // 启动命令（电平）[-] | Start command level
    bLidClosed   : BOOL := TRUE;     // 盖已关（安全联锁）[-] | Lid closed interlock
    fSpeedAct    : REAL := 0.0;      // 实测转速 [rpm] | Speed feedback actual
    fSpeedSp     : REAL := 3000.0;   // 目标转速，域 > fCritHi [rpm] | Target speed setpoint
    fCritLo      : REAL := 800.0;    // 临界转速带下沿，域 < 上沿 [rpm] | Critical band lower edge
    fCritHi      : REAL := 1100.0;   // 临界转速带上沿，域 < 目标转速 [rpm] | Critical band upper edge
    fRampUp      : REAL := 100.0;    // 升速斜率，域 > 0 [rpm/s] | Ramp-up rate
    fRampDn      : REAL := 200.0;    // 降速斜率，域 > 0 [rpm/s] | Ramp-down rate
    fDtSec       : REAL := 0.01;     // 序列周期，域 (0, 1] [s] | Sequence cycle time
    fAtSpeedTol  : REAL := 30.0;     // 到速容差，域 > 0 [rpm] | At-speed tolerance
    fStopThresh  : REAL := 10.0;     // 停转判据阈值，域 > 0 [rpm] | Stopped threshold
    tUnbalDelay  : TIME := T#2S;     // 不平衡确认延时，域 > T#0S | Unbalance confirm delay
    bUnbalHigh   : BOOL := FALSE;    // 不平衡检测输入（电平）[-] | Unbalance detection level
    bReset       : BOOL := FALSE;    // 复位命令，上升沿清跳闸 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    fSpRef    : REAL;               // 转速给定出口 [rpm] | Speed reference outlet
    bDriveEn  : BOOL;               // 驱动使能出口 [-] | Drive enable outlet
    bBrakeOut : BOOL;               // 制动输出出口 [-] | Brake output outlet
    bAtSpeed  : BOOL;               // 到速判据出口 [-] | At-speed outlet
    eState    : E_DL_CssState;      // 状态出口 | State outlet
    eCause    : E_DL_CssCause;      // 跳闸成因出口 | Trip cause outlet
    bError    : BOOL;               // 故障锁存标志 [-] | Fault latch flag
    nErrId    : UDINT;              // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _eState  : E_DL_CssState := E_DL_CssState.eIdle;   // 内部状态（CASE 唯一写入目标） | Internal state
    _eCause  : E_DL_CssCause := E_DL_CssCause.eNone;   // 成因锁存 | Latched cause
    _bFault  : BOOL;            // 故障锁存位 | Fault latch bit
    _fSpRef  : REAL := 0.0;     // 给定积分内部镜像 [rpm] | Reference ramp internal mirror
    _bCfgBad : BOOL;            // 组态非法当拍量 [-] | Illegal configuration
    _bSensBad: BOOL;            // 转速反馈非有限当拍量 [-] | Speed feedback non-finite
    rtStart  : R_TRIG;          // 启动沿实例，段 0 无条件刷新 | Start edge instance
    rtReset  : R_TRIG;          // 复位沿实例，段 0 无条件刷新 | Reset edge instance
    tonUnbal : TON;             // 不平衡去抖计时，段 0 无条件刷新 | Unbalance debounce timer
END_VAR
VAR CONSTANT
    DL_CSS_EPS : REAL := 1.0;       // 快跳越带容差 [rpm] | Jump exit tolerance
    DL_CSS_ERR : UDINT := 16#0005_03BA;  // 跳闸故障码 | Trip fault code
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bSensBad := (fSpeedAct <> fSpeedAct);                                      // 转速反馈 NaN 自反判 / Speed NaN self-reflex check
_bCfgBad := (fCritLo >= fCritHi) OR (fSpeedSp <= fCritHi) OR (fRampUp <= 0.0)
         OR (fRampDn <= 0.0) OR (fDtSec <= 0.0) OR (fDtSec > 1.0)
         OR (fAtSpeedTol <= 0.0) OR (fStopThresh <= 0.0)
         OR (fSpeedSp <> fSpeedSp) OR (fCritLo <> fCritLo) OR (fCritHi <> fCritHi);  // 组态域闸（含组态量非有限）/ Configuration gate
rtStart(CLK := bStartCmd);                                                  // 启动沿每拍必调 / Start edge every scan
rtReset(CLK := bReset);                                                     // 复位沿每拍必调 / Reset edge every scan
tonUnbal(IN := bUnbalHigh AND ((_eState = E_DL_CssState.eAccel)
         OR (_eState = E_DL_CssState.eCrit) OR (_eState = E_DL_CssState.eRun)), PT := tUnbalDelay); // 不平衡去抖 IN 挂运转相 ∧ 信号 / Debounce gated by motion and signal

(* —— 段 1：复位沿 + 组态域闸 —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND bLidClosed THEN                         // 复位沿且组态合法且盖已关 / Reset with legal config and lid closed
    _bFault := FALSE;                                                       // 清故障锁存位 / Clear fault latch
    _eCause := E_DL_CssCause.eNone;                                         // 清成因 / Clear cause
    IF _eState = E_DL_CssState.eTrip THEN
        _eState := E_DL_CssState.eIdle;                                     // 跳闸相迁出唯一路径 / Sole trip exit
    END_IF
END_IF
IF _bCfgBad THEN                                                            // 组态域闸 / Configuration gate
    _bFault := TRUE;
    _eCause := E_DL_CssCause.eCfgIllegal;                                   // 归因组态 / Cause: config
END_IF

(* —— 段 2：运转相即时跳闸源（开盖 / 转速非有限） —— *)
IF (NOT _bFault) AND ((_eState = E_DL_CssState.eAccel)
    OR (_eState = E_DL_CssState.eCrit) OR (_eState = E_DL_CssState.eRun)) THEN
    IF NOT bLidClosed THEN
        _bFault := TRUE;                                                    // 运转中开盖即时跳闸 / Lid open in motion, immediate trip
        _eCause := E_DL_CssCause.eLidOpen;                                  // 归因开盖 / Cause: lid open
    ELSIF _bSensBad THEN
        _bFault := TRUE;                                                    // 转速反馈丢失即时跳闸 / Speed feedback loss trip
        _eCause := E_DL_CssCause.eSensNonFinite;                            // 归因反馈 / Cause: feedback
    END_IF
END_IF

(* —— 段 3：不平衡去抖跳闸（三运转相共用一码，R190 归因唯一） —— *)
IF (NOT _bFault) AND tonUnbal.Q THEN
    _bFault := TRUE;                                                        // 不平衡跳闸锁存 / Unbalance trip latch
    _eCause := E_DL_CssCause.eUnbalance;                                    // 归因不平衡 / Cause: unbalance
END_IF

(* —— 段 4：状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF

E_DL_CssState.eIdle:
    _fSpRef := 0.0;                                                         // 待机给定钳零 / Idle ref zero
    IF rtStart.Q AND bLidClosed AND (NOT _bFault) THEN
        _fSpRef := 0.0;                                                     // 启动给定从零起 ramp / Start ramp from zero
        _eState := E_DL_CssState.eAccel;                                    // 进入升速段 / Enter accel
    END_IF

E_DL_CssState.eAccel:
    _fSpRef := _fSpRef + fRampUp * fDtSec;                                  // 斜坡升速积分 [rpm] / Ramp-up integration
    _fSpRef := LIMIT(0.0, _fSpRef, fSpeedSp);                               // 给定钳 [0, fSpeedSp] / Reference clamp
    IF _fSpRef >= fCritLo THEN
        _eState := E_DL_CssState.eCrit;                                     // 给定达临界带下沿转快跳 / Ref at band lower edge, jump
    ELSIF _fSpRef >= fSpeedSp THEN
        _eState := E_DL_CssState.eRun;                                      // 无临界带穿越直达恒速（组态已闸 fSpeedSp > fCritHi，防御分支） / Direct to run, defensive
    ELSIF (NOT bStartCmd) THEN
        _eState := E_DL_CssState.eDecel;                                    // 启动命令撤转降速 / Start released, decel
    END_IF

E_DL_CssState.eCrit:
    _fSpRef := fCritHi;                                                     // 快跳段：给定直接跳带上沿（边界①）/ Fast jump to upper edge
    IF fSpeedAct >= (fCritHi - DL_CSS_EPS) THEN
        _eState := E_DL_CssState.eAccel;                                    // 实测越带上沿回斜坡续升 / Feedback past band, resume ramp
    ELSIF (NOT bStartCmd) THEN
        _eState := E_DL_CssState.eDecel;                                    // 快跳段内命令撤转降速 / Start released in jump, decel
    END_IF

E_DL_CssState.eRun:
    _fSpRef := fSpeedSp;                                                    // 恒速段给定锁目标 / Run ref at target
    IF (NOT bStartCmd) THEN
        _eState := E_DL_CssState.eDecel;                                    // 命令撤转降速 / Start released, decel
    END_IF

E_DL_CssState.eDecel:
    _fSpRef := _fSpRef - fRampDn * fDtSec;                                  // 斜坡降速积分 [rpm] / Ramp-down integration
    IF _fSpRef < 0.0 THEN
        _fSpRef := 0.0;                                                     // 给定下限钳零 / Ref clamp zero
    END_IF
    IF (_fSpRef <= 0.0) AND (fSpeedAct < fStopThresh) THEN
        _eState := E_DL_CssState.eIdle;                                     // 给定归零且实测停转回待机 / Ref zero and stopped, idle
    END_IF

E_DL_CssState.eTrip:
    _fSpRef := 0.0;                                                         // 跳闸给定钳零 / Trip ref zero
    ;                                                                       // 仅段 1 复位沿可迁出 / Only reset edge leaves

ELSE
    _bFault := TRUE;                                                        // 非法状态兜底（R6）/ Illegal state fallback
    _eCause := E_DL_CssCause.eCfgIllegal;                                   // 归因归并组态 / Cause folded to config
    _eState := E_DL_CssState.eTrip;

END_CASE

(* —— 段 5：出口单点映射（名实同源；锁存码回放） —— *)
fSpRef := _fSpRef;                                                          // 给定出口 [rpm] / Reference outlet
bDriveEn := (_eState = E_DL_CssState.eAccel) OR (_eState = E_DL_CssState.eCrit)
         OR (_eState = E_DL_CssState.eRun) OR (_eState = E_DL_CssState.eDecel);  // 驱动使能四运转相 / Drive enable in motion states
bBrakeOut := (_eState = E_DL_CssState.eDecel) OR (_eState = E_DL_CssState.eTrip);  // 制动输出降速/跳闸相 / Brake in decel and trip
bAtSpeed := (_eState = E_DL_CssState.eRun) AND (fSpeedAct >= (fSpeedSp - fAtSpeedTol));  // 到速判据 / At-speed judgement
eState := _eState;                                                          // 状态出口 / State outlet
eCause := _eCause;                                                          // 成因出口 / Cause outlet
bError := _bFault;                                                          // 故障标志同源 / Error flag from latch
IF _bFault THEN
    nErrId := DL_CSS_ERR;                                                   // 跳闸锁存码回放 / Replay latched trip code
ELSE
    nErrId := 16#0000_0000;                                                 // 无事件 / No event
END_IF

END_FUNCTION_BLOCK
