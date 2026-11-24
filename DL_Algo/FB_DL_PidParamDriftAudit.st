(*
  Name        : FB_DL_PidParamDriftAudit
  Category    : DL_Algo
  Version     : 1.0.1
  Purpose     : 整定参数漂移审计：逐拍比对现行 Kp/Ti/Td 与基准快照，按相对容差判漂移并累计越差次数，供「谁改了参数」留痕；/ Audit PID parameter drift: compare live Kp/Ti/Td against baseline snapshots with relative tolerance, accumulate excursions for an auditable trail
  溯源        : 借 t2-3-风格指南·审计 的分类/参数域组织，clean-room 实现
  Boundary    : ① 基准近零分支：|基准| <= eps 时相对偏差无定义，改走绝对差判据（fTolAbs），不产生除零/Inf；
                ② 现行与基准同为近零 → 判无漂移（0/0 语义按「一致」处理）；
                ③ 容差与近零判据全部 ABS 差比较，禁 `=`/`<>`；
                ④ 越差计数饱和累加，防 UDINT 回绕；
                ⑤ 本件只审计不改参数，输出仅供上位留痕（属主边界）。
  修订记录    : 2026-11-20 v1.0.1：六参数有限性闸补 Inf 差判（NaN+Inf 双闸，R52-05）；bDriftAny 改由三确认位 OR 同源重算（R52-06）；_fHun 迁入 VAR CONSTANT c_fHun 收口魔法数。
*)
TYPE E_DL_PdaState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eAudit := 10,                            (* 审计运行 / Auditing *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_PdaCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：容差/参考值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PidParamDriftAudit
VAR_INPUT
    fKp        : REAL := 1.0;                (* 现行比例增益 [-] / Live proportional gain *)
    fTi        : REAL := 1.0;                (* 现行积分时间，P 模式可为 0 [s] / Live integral time, 0 allowed *)
    fTd        : REAL := 0.0;                (* 现行微分时间，P/PI 模式可为 0 [s] / Live derivative time, 0 allowed *)
    fKpRef     : REAL := 1.0;                (* 基准比例增益（签核快照）[-] / Baseline proportional gain *)
    fTiRef     : REAL := 1.0;                (* 基准积分时间 [s] / Baseline integral time *)
    fTdRef     : REAL := 0.0;                (* 基准微分时间 [s] / Baseline derivative time *)
    fTolRel    : REAL := 0.05;               (* 相对漂移容差（5% = 0.05），域 > 0 [-] / Relative tolerance, > 0 *)
    fTolAbs    : REAL := 0.01;               (* 基准近零时改用的绝对差容差，域 > 0 [参数单位] / Absolute tolerance for near-zero baselines *)
    nConfirm   : INT := 3;                   (* 越差确认拍数，域 >= 1 [拍] / Consecutive excursion scans to confirm *)
    bEnable    : BOOL := TRUE;               (* 审计使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清漂移标志与计数 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fDriftKp   : REAL;                       (* Kp 相对漂移（% / 近零基准时为绝对差）[%] / Kp drift *)
    fDriftTi   : REAL;                       (* Ti 相对漂移 [%] / Ti drift *)
    fDriftTd   : REAL;                       (* Td 相对漂移 [%] / Td drift *)
    bDriftKp   : BOOL;                       (* Kp 越差确认位 [-] / Kp drift confirmed *)
    bDriftTi   : BOOL;                       (* Ti 越差确认位 [-] / Ti drift confirmed *)
    bDriftTd   : BOOL;                       (* Td 越差确认位 [-] / Td drift confirmed *)
    bDriftAny  : BOOL;                       (* 任一参数越差（汇总位）[-] / Any parameter drifted *)
    nDriftCnt  : UDINT;                      (* 累计确认越差次数（饱和）[-] / Confirmed drift count, saturated *)
    eState     : E_DL_PdaState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_PdaCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_PdaState := E_DL_PdaState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_PdaCause := E_DL_PdaCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite : BOOL;                         (* 六参数有限性联合闸 / Finiteness of all six parameters *)
    _bExKp   : BOOL;                         (* Kp 当拍越差（未确认） / Kp excursion this scan *)
    _bExTi   : BOOL;                         (* Ti 当拍越差 / Ti excursion this scan *)
    _bExTd   : BOOL;                         (* Td 当拍越差 / Td excursion this scan *)
    _bAny    : BOOL;                         (* 任一当拍越差 / Any excursion this scan *)
    _nHold   : INT;                          (* 越差连续拍计数 [-] / Consecutive excursion counter *)
    _fDkp    : REAL;                         (* Kp 偏差绝对值/相对值中间量 [%] / Kp deviation intermediate *)
    _fDti    : REAL;                         (* Ti 偏差中间量 [%] / Ti deviation intermediate *)
    _fDtd    : REAL;                         (* Td 偏差中间量 [%] / Td deviation intermediate *)
END_VAR
VAR CONSTANT
    DL_PDA_EPS    : REAL  := 1.0E-6;         (* 近零/容差判零容差（REAL 量级）[-] / Epsilon *)
    DL_PDA_CNTMAX : UDINT := 4294967295;     (* 计数饱和上限（R28）[-] / Count saturation cap *)
    DL_PDA_NMAX   : INT   := 100;            (* 确认拍数上限（防长时间不判）[拍] / Confirm scans cap *)
    c_fHun        : LREAL := 100.0;          (* 百分数换算常量（v1.0.1 由 VAR 迁入收口）[-] / Percent scale constant *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fTolRel <= DL_PDA_EPS) OR (fTolAbs <= DL_PDA_EPS)                 (* 容差正域闸（两口径均须有效） / Tolerance gates *)
            OR (nConfirm < 1) OR (nConfirm > DL_PDA_NMAX);                     (* 确认拍数域闸 / Confirm-count gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fKp = fKp) AND ((fKp - fKp) = (fKp - fKp))                        (* Kp NaN 自反 + Inf 差判闸（v1.0.1）/ Kp NaN and Inf gates *)
            AND (fTi = fTi) AND ((fTi - fTi) = (fTi - fTi))                    (* Ti NaN 自反 + Inf 差判闸 / Ti NaN and Inf gates *)
            AND (fTd = fTd) AND ((fTd - fTd) = (fTd - fTd))                    (* Td NaN 自反 + Inf 差判闸 / Td NaN and Inf gates *)
            AND (fKpRef = fKpRef) AND ((fKpRef - fKpRef) = (fKpRef - fKpRef))  (* 基准 Kp NaN + Inf 闸 / Baseline Kp NaN and Inf gates *)
            AND (fTiRef = fTiRef) AND ((fTiRef - fTiRef) = (fTiRef - fTiRef))  (* 基准 Ti NaN + Inf 闸 / Baseline Ti NaN and Inf gates *)
            AND (fTdRef = fTdRef) AND ((fTdRef - fTdRef) = (fTdRef - fTdRef)); (* 基准 Td NaN + Inf 闸（Inf-Inf→NaN 漏报收口）/ Baseline Td NaN and Inf gates *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bExKp := FALSE;                                                               (* Kp 越差预清 / Kp excursion preset *)
_bExTi := FALSE;                                                               (* Ti 越差预清 / Ti excursion preset *)
_bExTd := FALSE;                                                               (* Td 越差预清 / Td excursion preset *)
_bAny := FALSE;                                                                (* 汇总位预清 / Any preset *)
(* bDriftAny 不再每拍独立预清：改由段 5 由三确认位 OR 同源重算（v1.0.1，R52-06 汇总不回落） *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清三个确认位 + 清计数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_PdaCause.eNone;                                            (* 清成因 / Clear cause *)
    bDriftKp := FALSE;                                                         (* 清 Kp 确认位 / Clear Kp confirm *)
    bDriftTi := FALSE;                                                         (* 清 Ti 确认位 / Clear Ti confirm *)
    bDriftTd := FALSE;                                                         (* 清 Td 确认位 / Clear Td confirm *)
    nDriftCnt := 0;                                                            (* 清越差计数 / Clear count *)
    _nHold := 0;                                                               (* 清连续拍计数 / Clear hold counter *)
    fDriftKp := 0.0;                                                           (* 清 Kp 漂移出口 / Clear Kp drift outlet *)
    fDriftTi := 0.0;                                                           (* 清 Ti 漂移出口 / Clear Ti drift outlet *)
    fDriftTd := 0.0;                                                           (* 清 Td 漂移出口 / Clear Td drift outlet *)
    _eState := E_DL_PdaState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_PdaCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_PdaState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PdaState.eIdle:                                                       (* 未使能：不审计，出口保持 / Disabled *)
        _nHold := 0;                                                           (* 失能清连续计数（防隐性回夹） / Clear hold *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_PdaState.eAudit;                                   (* 使能进入审计 / Enter audit *)
        END_IF
    E_DL_PdaState.eAudit:                                                      (* 审计相：三参数双口径比对 / Auditing *)
        IF NOT bEnable THEN
            _eState := E_DL_PdaState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF _bFinite THEN
            IF ABS(fKpRef) > DL_PDA_EPS THEN
                _fDkp := LREAL_TO_REAL(ABS(fKp - fKpRef) / ABS(fKpRef) * c_fHun);   (* 相对漂移 %：除子已过闸，显式窄化转换 / Relative drift, divisor gated *)
                _bExKp := _fDkp > LREAL_TO_REAL(fTolRel * c_fHun);             (* 越差判据：相对口径 / Excursion, relative *)
            ELSE
                _fDkp := ABS(fKp - fKpRef);                                    (* 基准近零：退化为绝对差（边界①） / Near-zero baseline: absolute *)
                _bExKp := _fDkp > fTolAbs;                                     (* 越差判据：绝对口径 / Excursion, absolute *)
            END_IF
            IF ABS(fTiRef) > DL_PDA_EPS THEN
                _fDti := LREAL_TO_REAL(ABS(fTi - fTiRef) / ABS(fTiRef) * c_fHun);   (* Ti 相对漂移 % / Ti relative drift *)
                _bExTi := _fDti > LREAL_TO_REAL(fTolRel * c_fHun);             (* Ti 越差判据 / Ti excursion *)
            ELSE
                _fDti := ABS(fTi - fTiRef);                                    (* Ti 基准为 0：绝对差（P 模式常见） / Ti near-zero: absolute *)
                _bExTi := _fDti > fTolAbs;                                     (* Ti 越差判据（绝对） / Ti excursion, absolute *)
            END_IF
            IF ABS(fTdRef) > DL_PDA_EPS THEN
                _fDtd := LREAL_TO_REAL(ABS(fTd - fTdRef) / ABS(fTdRef) * c_fHun);   (* Td 相对漂移 % / Td relative drift *)
                _bExTd := _fDtd > LREAL_TO_REAL(fTolRel * c_fHun);             (* Td 越差判据 / Td excursion *)
            ELSE
                _fDtd := ABS(fTd - fTdRef);                                    (* Td 基准为 0：绝对差 / Td near-zero: absolute *)
                _bExTd := _fDtd > fTolAbs;                                     (* Td 越差判据（绝对） / Td excursion, absolute *)
            END_IF
            fDriftKp := _fDkp;                                                 (* Kp 漂移出口（实时派生） / Kp drift outlet *)
            fDriftTi := _fDti;                                                 (* Ti 漂移出口 / Ti drift outlet *)
            fDriftTd := _fDtd;                                                 (* Td 漂移出口 / Td drift outlet *)
            _bAny := _bExKp OR _bExTi OR _bExTd;                               (* 任一越差汇总 / Any excursion *)
            IF _bAny THEN
                _nHold := _nHold + 1;                                          (* 连续越差拍递增 / Increment hold *)
            ELSE
                _nHold := 0;                                                   (* 有拍未越差即清零（降抖） / Reset on clean scan *)
            END_IF
            IF _nHold >= nConfirm THEN                                         (* 连续确认拍数到齐 / Confirm reached *)
                IF _bExKp THEN
                    bDriftKp := TRUE;                                          (* Kp 确认位锁存 / Latch Kp confirm *)
                END_IF
                IF _bExTi THEN
                    bDriftTi := TRUE;                                          (* Ti 确认位锁存 / Latch Ti confirm *)
                END_IF
                IF _bExTd THEN
                    bDriftTd := TRUE;                                          (* Td 确认位锁存 / Latch Td confirm *)
                END_IF
                IF nDriftCnt < DL_PDA_CNTMAX THEN
                    nDriftCnt := nDriftCnt + 1;                                (* 越差事件净额 +1（同拍多次不叠加） / Net +1 per confirmed event *)
                END_IF
                _nHold := 0;                                                   (* 计数归零，下一轮重新累积 / Restart accumulation *)
            END_IF
        END_IF                                                                 (* 非有限参数：本拍不判（保留确认位） / Non-finite: skip verdict *)
    E_DL_PdaState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PdaState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_PdaCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191；bDriftAny 由三确认位 OR 同源重算，v1.0.1） —— *)
bDriftAny := bDriftKp OR bDriftTi OR bDriftTd;                                 (* 汇总出口同源重算（非有限拍不回落） / Any outlet re-derived *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
