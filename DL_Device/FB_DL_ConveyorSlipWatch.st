(*
  Name        : FB_DL_ConveyorSlipWatch
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : 输送带打滑检测：带速与驱动辊线速差折算打滑率，叠加电流负载判据（轻载不判滑），超限经确认延时锁存报警；/ Conveyor slip watch: slip ratio from belt vs drive-roll surface speed, gated by a current load criterion, confirmed then latched over the threshold
  溯源        : 借 t2-2-lbp 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：速度下限/打滑率上限/电流下限/确认延时任一越域 → 锁存故障；
                ② 除零前置：打滑率除子取驱动辊速绝对值，须 >= 速度下限（组态闸保证）才计算；
                ③ 非有限速度/电流该拍不判（保留上拍结果，防污染判据）；
                ④ 确认延时 TON 串 eMon 相位闸（族③：eIdle/eFault 不计时），段 0 无 IF 包裹；
                ⑤ 负打滑（带速 > 辊速，属测量倒置）不判滑但置诊断位 bRatioInvert；
                ⑥ 本件为诊断层，不停机（属主边界）。
*)
TYPE E_DL_CswState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 打滑监视运行 / Monitoring *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_CswCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：速度/比率/电流/延时越域 / Illegal config *)
    eSlip       := 2,                        (* 打滑确认（带速滞后辊速） / Confirmed slip *)
    ePhaseBad   := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ConveyorSlipWatch
VAR_INPUT
    fBeltSpeed  : REAL := 0.0;               (* 带速实测（带秤/编码器折算）[m/s] / Measured belt speed *)
    fRollSpeed  : REAL := 0.0;               (* 驱动辊线速度实测 [m/s] / Drive-roll surface speed *)
    fSpdMin     : REAL := 0.2;               (* 速度计算下限（除子域 + 运行判定），域 > 0 [m/s] / Speed floor for divisor and run gating *)
    fSlipMax    : REAL := 5.0;               (* 打滑率报警上限，域 > 0 [%] / Slip ratio limit, > 0 *)
    fCurrent    : REAL := 0.0;               (* 驱动电机电流实测 [A] / Drive motor current *)
    fCurrentMin : REAL := 2.0;               (* 负载电流下限（轻载不判滑），域 > 0 [A] / Load current floor *)
    tConfirm    : TIME := T#2S;              (* 打滑确认延时，域 > T#0S [ms] / Slip confirm delay, > 0 *)
    bRunning    : BOOL := FALSE;             (* 输送机运行命令电平 [-] / Conveyor run command *)
    bEnable     : BOOL := TRUE;              (* 监视使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清报警与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fSlipRatio  : REAL;                      (* 打滑率（实时派生，速度不足时为 0）[%] / Slip ratio *)
    bLoaded     : BOOL;                      (* 负载在位（电流 >= 下限）[-] / Load present *)
    bRatioInvert: BOOL;                      (* 打滑率为负（测量倒置诊断位）[-] / Negative slip ratio diagnostic *)
    bSlip       : BOOL;                      (* 打滑报警锁存（复位沿清）[-] / Slip alarm latched *)
    eState      : E_DL_CswState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_CswCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_CswState := E_DL_CswState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_CswCause := E_DL_CswCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonConf  : TON;                          (* 打滑确认延时计时器（IN 由判据派生 + 相位闸） / Slip confirm timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFin    : BOOL;                         (* 输入有限性当拍量（三输入联合） / Input finiteness joint *)
    _bRun    : BOOL;                         (* 速度达标运行当拍量（两速度均 >= 下限） / Speeds above floor *)
    _bLoad   : BOOL;                         (* 负载在位当拍量 / Load present this scan *)
    _fRatio  : REAL;                         (* 打滑率中间量 [%] / Slip ratio intermediate *)
    _bSlipRaw: BOOL;                         (* 打滑原始判据当拍量 / Raw slip verdict *)
END_VAR
VAR CONSTANT
    DL_CSW_EPS    : REAL := 1.0E-6;          (* 判零容差 [-] / Epsilon *)
    DL_CSW_HUND   : REAL := 100.0;           (* 百分数换算常量（乘性常量）[-] / Percent scale constant *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG/TON 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (fSpdMin <= DL_CSW_EPS)                                            (* 速度下限正域闸（兼除子域闸） / Speed floor gate *)
            OR (fSlipMax <= DL_CSW_EPS)                                        (* 打滑率上限正域闸 / Slip limit gate *)
            OR (fCurrentMin <= DL_CSW_EPS)                                     (* 电流下限正域闸 / Current floor gate *)
            OR NOT (tConfirm > T#0S);                                          (* 确认延时正域闸 / Confirm delay gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fBeltSpeed = fBeltSpeed) AND (fRollSpeed = fRollSpeed)               (* 速度 NaN 自反闸 / Speeds NaN gates *)
            AND (fCurrent = fCurrent)                                          (* 电流 NaN 自反闸 / Current NaN gate *)
            AND ((fBeltSpeed - fBeltSpeed) = (fBeltSpeed - fBeltSpeed))        (* 带速 Inf 差判闸 / Belt speed Inf gate *)
            AND ((fRollSpeed - fRollSpeed) = (fRollSpeed - fRollSpeed))        (* 辊速 Inf 差判闸 / Roll speed Inf gate *)
            AND ((fCurrent - fCurrent) = (fCurrent - fCurrent));               (* 电流 Inf 差判闸 / Current Inf gate *)
_bRun := _bFin AND (ABS(fRollSpeed) >= fSpdMin) AND (ABS(fBeltSpeed) >= fSpdMin);   (* 两速度均达下限才计算比率（除子域闸边界②） / Both speeds above floor *)
_fRatio := 0.0;                                                                (* 打滑率中间量预置（速度不足时保持 0，出口确定值） / Ratio preset zero *)
IF _bRun THEN
    _fRatio := (fRollSpeed - fBeltSpeed) / ABS(fRollSpeed) * DL_CSW_HUND;      (* 打滑率 = (辊速-带速)/|辊速|：除子 |辊速| >= 下限已闸 [%] / Slip ratio, divisor gated *)
END_IF
_bLoad := _bFin AND (fCurrent >= fCurrentMin);                                 (* 负载在位：电流达下限 / Load present *)
_bSlipRaw := _bFin AND _bRun AND _bLoad AND (_fRatio > fSlipMax);              (* 原始判据：运行 + 负载 + 超限（三者同证） / Raw slip verdict *)
tonConf(IN := (_eState = E_DL_CswState.eMon) AND bRunning AND _bSlipRaw, PT := tConfirm);   (* 确认延时：判据持续才计时，串 eMon 相位闸 / Confirm timer with phase gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
bLoaded := FALSE;                                                              (* 负载指示预清 / Load preset *)
bRatioInvert := FALSE;                                                         (* 倒置诊断位预清 / Invert preset *)
fSlipRatio := 0.0;                                                             (* 打滑率出口预清 / Ratio outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清报警 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CswCause.eNone;                                            (* 清成因 / Clear cause *)
    bSlip := FALSE;                                                            (* 清打滑报警锁存 / Clear slip latch *)
    _eState := E_DL_CswState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_CswCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_CswState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_CswState.eIdle:                                                       (* 未使能：出口确定值 / Disabled *)
        fSlipRatio := 0.0;                                                     (* 失能清打滑率出口 / Clear ratio outlet *)
        bSlip := FALSE;                                                        (* 失能清报警出口 / Clear slip outlet *)
        bLoaded := FALSE;                                                      (* 失能清负载出口 / Clear load outlet *)
        bRatioInvert := FALSE;                                                 (* 失能清倒置出口 / Clear invert outlet *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_CswState.eMon;                                     (* 使能进入监视 / Enter monitoring *)
        END_IF
    E_DL_CswState.eMon:                                                        (* 监视相：比率派生 + 确认锁存 / Monitoring *)
        IF NOT bEnable THEN
            _eState := E_DL_CswState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            fSlipRatio := _fRatio;                                             (* 打滑率出口（实时派生，R191） / Ratio outlet *)
            bLoaded := _bLoad;                                                 (* 负载出口（名实同源） / Load outlet *)
            bRatioInvert := _bFin AND _bRun AND (_fRatio < 0.0);               (* 负比率诊断：带速 > 辊速（测量倒置） / Inverted ratio diagnostic *)
            IF tonConf.Q THEN                                                  (* 判据持续满确认延时：锁存报警 / Confirm elapsed: latch alarm *)
                bSlip := TRUE;                                                 (* 打滑报警锁存（复位沿清） / Latch slip *)
                _bFault := TRUE;                                               (* 同步故障锁存（R45 配对） / Latch fault *)
                _eCause := E_DL_CswCause.eSlip;                                (* 成因：打滑 / Cause: slip *)
            END_IF
        END_IF
    E_DL_CswState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CswState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_CswCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
