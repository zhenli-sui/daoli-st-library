(*
  Name        : FB_DL_MakeupWaterDosing
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : 补水定量加药：累计补水流量体积，每到设定批量体积即触发一次定比投加（加药量 = 批量 × 投加比），投加脉冲单拍输出并累计批次数；/ Makeup-water proportional dosing: accumulate makeup volume and trigger one proportional dose (dose = batch x ratio) each time the batch volume is reached, with a single-scan dose pulse and batch count
  溯源        : ROADMAP L501（未勾真缺口），IEC 61131-3 标准语义的道莅防御性实现
  Boundary    : ① 组态闸：批量体积/投加比/采样周期任一非正 → 锁存故障；
                ② 体积换算：m³/h → L/s 除子 3.6 为常量，无组态除零风险；采样周期正域由组态闸保证；
                ③ 单次只结算一个批次（净额单点写入），剩余体积保留进位（大流量不丢批）；
                ④ 投加脉冲为单拍（内部置位 → 出口统一映射，R187），批次数饱和累加；
                ⑤ 负流量（回流）不计入累计，防倒吸误触发。
*)
TYPE E_DL_MwdState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eAcc   := 10,                            (* 体积累计 / Accumulating *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_MwdCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：批量/比值/周期越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_MakeupWaterDosing
VAR_INPUT
    fFlowNow  : REAL := 0.0;                 (* 补水瞬时流量（负值为回流），[m³/h] / Makeup flow, negative = backflow *)
    fBatchVol : REAL := 100.0;               (* 触发批量体积，域 > 0 [L] / Batch volume trigger, > 0 *)
    fDoseRatio: REAL := 0.5;                 (* 投加比（加药量/补水体积），域 > 0 [L/m³] / Dose ratio, > 0 *)
    tSample   : TIME := T#100MS;             (* 采样周期，域 > T#0S [ms] / Sampling period, > 0 *)
    bEnable   : BOOL := TRUE;                (* 使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清累计与批次 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fVolAcc   : REAL;                        (* 当前批次已累计体积 [L] / Volume accumulated in current batch *)
    fVolTotal : REAL;                        (* 累计补水总量（生命周期）[L] / Lifetime accumulated volume *)
    fDoseVol  : REAL;                        (* 本次投加量（脉冲拍有效）[L] / Dose volume of this pulse *)
    bDosePulse: BOOL;                        (* 投加触发单拍脉冲 [-] / Dose trigger single-scan pulse *)
    nBatchCnt : UDINT;                       (* 已完成批次数（饱和）[批] / Completed batches, saturated *)
    eState    : E_DL_MwdState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_MwdCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_MwdState := E_DL_MwdState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_MwdCause := E_DL_MwdCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite : BOOL;                         (* 输入有限性当拍量 / Input finiteness *)
    _bDoseC  : BOOL;                         (* 投加脉冲内部单拍量（出口统一映射） / Dose internal pulse *)
    _fDtSec  : REAL;                         (* 采样周期秒值 [s] / Period in seconds *)
    _fDvL     : REAL;                        (* 本拍补水体积增量 [L] / Volume increment this scan *)
    _fAcc    : REAL;                         (* 批次累计内部量 [L] / Batch accumulator *)
    _fTotal  : REAL;                         (* 生命周期累计内部量 [L] / Lifetime accumulator *)
    _fDose   : REAL;                         (* 本次投加量计算值 [L] / Dose calculation *)
    _fZero   : REAL;                         (* 实数零常量 [-] / Zero constant *)
END_VAR
VAR CONSTANT
    DL_MWD_EPS    : REAL  := 1.0E-6;         (* 判零容差 [-] / Epsilon *)
    DL_MWD_M3H2LS : REAL  := 3.6;            (* m³/h → L/s 换算常量（1 m³/h = 1/3.6 L/s）[-] / Conversion constant *)
    DL_MWD_CNTMAX : UDINT := 4294967295;     (* 批次数饱和上限（R28）[批] / Batch count cap *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tSample) / 1000.0;                                    (* 周期秒化（除子常量 1000） / Period to seconds *)
_bCfgBad := (fBatchVol <= DL_MWD_EPS)                                          (* 批量体积正域闸 / Batch volume gate *)
            OR (fDoseRatio <= DL_MWD_EPS)                                      (* 投加比正域闸 / Dose ratio gate *)
            OR NOT (tSample > T#0S);                                           (* 采样周期正域闸 / Period gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fFlowNow = fFlowNow) AND ((fFlowNow - fFlowNow) = (fFlowNow - fFlowNow));   (* NaN 自反 + Inf 差判 / NaN and Inf gate *)
_fZero := 0.0;                                                                 (* 零常量装载 / Zero constant load *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bDoseC := FALSE;                                                              (* 投加脉冲内部量预清 / Dose preset *)
fDoseVol := 0.0;                                                               (* 投加量出口预清（脉冲拍外恒 0） / Dose outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清累计 + 清批次 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_MwdCause.eNone;                                            (* 清成因 / Clear cause *)
    _fAcc := 0.0;                                                              (* 清批次累计 / Clear batch accumulator *)
    _fTotal := 0.0;                                                            (* 清总量累计 / Clear lifetime accumulator *)
    fVolAcc := 0.0;                                                            (* 清批次出口 / Clear batch outlet *)
    fVolTotal := 0.0;                                                          (* 清总量出口 / Clear total outlet *)
    nBatchCnt := 0;                                                            (* 清批次数 / Clear batch count *)
    _eState := E_DL_MwdState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_MwdCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_MwdState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_MwdState.eIdle:                                                       (* 未使能：不累计 / Disabled *)
        fVolAcc := _fAcc;                                                      (* 出口镜像（保持当前批次进度） / Outlet mirror *)
        fVolTotal := _fTotal;                                                  (* 总量出口镜像 / Total outlet mirror *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_MwdState.eAcc;                                     (* 使能进入累计 / Enter accumulating *)
        END_IF
    E_DL_MwdState.eAcc:                                                        (* 累计相：体积积分 + 批量触发 / Accumulating *)
        IF NOT bEnable THEN
            _eState := E_DL_MwdState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF _bFinite AND (_fDtSec > DL_MWD_EPS) THEN
            _fDvL := fFlowNow / DL_MWD_M3H2LS * _fDtSec;                       (* 体积增量 = (m³/h→L/s)·s（除子常量）[L] / Volume increment *)
            IF _fDvL > _fZero THEN                                             (* 负流量（回流）不计入（边界⑤） / Backflow ignored *)
                _fAcc := _fAcc + _fDvL;                                        (* 批次累计 / Batch accumulate *)
                _fTotal := _fTotal + _fDvL;                                    (* 总量累计 / Lifetime accumulate *)
            END_IF
            IF _fAcc >= fBatchVol THEN                                         (* 到批量：触发一次投加 / Batch reached: dose once *)
                _fDose := fBatchVol * fDoseRatio;                              (* 投加量 = 批量 × 比值 [L] / Dose volume *)
                fDoseVol := _fDose;                                            (* 投加量出口（脉冲拍有效） / Dose outlet *)
                _bDoseC := TRUE;                                               (* 脉冲内部置位（出口统一映射，R187） / Pulse internal *)
                _fAcc := _fAcc - fBatchVol;                                    (* 剩余体积进位，不丢批（净额单点写入） / Carry remainder *)
                IF _fAcc < _fZero THEN
                    _fAcc := _fZero;                                           (* 进位后下限保护（浮点舍入） / Carry floor *)
                END_IF
                IF nBatchCnt < DL_MWD_CNTMAX THEN
                    nBatchCnt := nBatchCnt + 1;                                (* 批次净额 +1（同拍不叠加） / Net +1 *)
                END_IF
            END_IF
            fVolAcc := _fAcc;                                                  (* 批次进度出口 / Batch progress outlet *)
            fVolTotal := _fTotal;                                              (* 总量出口 / Total outlet *)
        END_IF                                                                 (* 非有限输入：本拍不累计 / Non-finite: skip *)
    E_DL_MwdState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_MwdState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_MwdCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bDosePulse := _bDoseC;                                                         (* 投加脉冲单拍出口 / Dose pulse outlet *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
