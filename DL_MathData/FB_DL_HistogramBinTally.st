(*
  Name        : FB_DL_HistogramBinTally
  Category    : DL_MathData
  Version     : 1.0.0
  Purpose     : 分箱直方图累计：等宽 bins 样本逐拍落格计数，越界钳边计数，占比出口按总入格数派生；/ Histogram bin tally: equal-width bins with per-scan sample counting, clamped-edge counting, and ratio outlets derived from total tally
  溯源        : 借 lgf-measurement 的统计族扩组织，clean-room 实现
  Boundary    : ① bins 数域 2..64 且 bin 宽 > 0，任一越域锁存故障（计数值冻结不动）；
                ② 落格下标由边界值直比算出（FOR 逐格上界直比，不用除法），越下界钳第 1 格、越上界钳末格，同时钳边计数出口分别累加；
                ③ 非有限样本拒收不入格（bSampleRej 单拍脉冲，R187 出口映射）；
                ④ 复位沿幂等清零：计数出口与内部计数器同拍同步归零（防镜像失步）；
                ⑤ 占比除子 = 总入格数，总数 0 时占比出口全 0 不除（防除零）；
                ⑥ 计数器为 UDINT 饱和累加（达上限不再递增，防回卷）。
*)
TYPE E_DL_HbtState :
(
    eIdle  := 0,                             (* 未使能（计数清零保持） / Disabled, tallies cleared *)
    eRun   := 10,                            (* 直方图累计运行 / Tally running *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_HbtCause :
(
    eNone      := 0,                         (* 无故障成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：bins/格宽越域 / Illegal config *)
    ePhaseBad  := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_HistogramBinTally
VAR_INPUT
    fSample : REAL := 0.0;                   (* 样本输入（任意工程量）[-] / Sample input *)
    fLower  : REAL := 0.0;                   (* 第 1 格下边界 [工程单位] / Lower edge of bin 1 *)
    fBinW   : REAL := 1.0;                   (* 等宽格宽，域 > 0 [工程单位] / Bin width *)
    nBins   : INT := 16;                     (* 格数，域 2..64 [格] / Bin count *)
    bEnable : BOOL := TRUE;                  (* 使能 [-] / Enable *)
    bReset  : BOOL := FALSE;                 (* 复位命令，上升沿幂等清零 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    aBinCnt : ARRAY[1..64] OF UDINT;         (* 各格计数（有效区 1..nBins，其余恒 0）[个] / Bin tallies *)
    nTotal  : UDINT;                         (* 总入格数（含钳边，不含拒收）[个] / Total tallied count *)
    nClampLow: UDINT;                        (* 越下界钳第 1 格累计数 [个] / Clamped-low count *)
    nClampHigh: UDINT;                       (* 越上界钳末格累计数 [个] / Clamped-high count *)
    nLastBin: INT;                           (* 最近样本落格序号（0 = 拒收/未落格）[格] / Last sample bin index *)
    fLastRatio: REAL;                        (* 最近落格占比 = 该格计数 / 总入格数 [-] / Last bin ratio *)
    bSampleRej: BOOL;                        (* 最近样本被拒收（单拍脉冲）[-] / Sample rejected pulse *)
    eState  : E_DL_HbtState;                 (* 状态出口 / State outlet *)
    eCause  : E_DL_HbtCause;                 (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError  : BOOL;                          (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_HbtState := E_DL_HbtState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_HbtCause := E_DL_HbtCause.eNone;  (* 故障成因锁存量 / Latched cause *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                          (* 样本有限性当拍量 / Sample finiteness *)
    _bRejI  : BOOL;                          (* 拒收脉冲内部量（统一出口映射，R187） / Reject pulse internal *)
    _bHit   : BOOL;                          (* 本拍落格成功当拍量 / Binned this scan *)
    _nBin   : INT;                           (* 本拍落格序号 [格] / Bin index this scan *)
    _i      : INT;                           (* 落格扫描游标 [格] / Bin scan cursor *)
    _nBinsE : INT;                           (* 钳位后生效格数 [格] / Effective bin count *)
    _nCntI  : UDINT;                         (* 落格计数中间量（占比派生用）[个] / Bin count intermediate *)
END_VAR
VAR CONSTANT
    DL_HBT_NMIN : INT   := 2;                (* 格数下限（边界①）[格] / Bin count lower bound *)
    DL_HBT_NMAX : INT   := 64;               (* 格数上限（边界①）[格] / Bin count upper bound *)
    DL_HBT_EPS  : REAL  := 1.0E-6;           (* 判零容差 [-] / Epsilon *)
    DL_HBT_CNTMAX: UDINT := 4294967295;      (* 计数饱和上限（边界⑥，R28）[个] / Tally saturation cap *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nBins < DL_HBT_NMIN) OR (nBins > DL_HBT_NMAX) OR (fBinW <= DL_HBT_EPS);   (* 格数/格宽域闸（边界①） / Bin count and width gates *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fSample = fSample) AND ((fSample - fSample) = (fSample - fSample));   (* 样本 NaN 自反 + Inf 差判闸（边界③） / Sample NaN and Inf gate *)
_nBinsE := nBins;                                        (* 生效格数初值 / Effective bins init *)
IF _nBinsE < DL_HBT_NMIN THEN
    _nBinsE := DL_HBT_NMIN;                              (* 格数下限钳位（防越界） / Bin count lower clamp *)
END_IF
IF _nBinsE > DL_HBT_NMAX THEN
    _nBinsE := DL_HBT_NMAX;                              (* 格数上限钳位（防越界） / Bin count upper clamp *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_bRejI := FALSE;                                         (* 拒收脉冲内部量预清 / Reject pulse preset *)
bSampleRej := FALSE;                                     (* 拒收脉冲出口预清 / Reject outlet preset *)
nLastBin := 0;                                           (* 落格序号预清（拒收拍为 0） / Bin index preset *)
fLastRatio := 0.0;                                       (* 占比出口预清（除子零保护默认） / Ratio preset zero *)
_bHit := FALSE;                                          (* 落格成功量预清 / Binned preset *)
_nBin := 0;                                              (* 落格序号中间量预清 / Bin index intermediate *)

(* —— 段 2：复位沿处理（作用域：清故障 + 全计数出口与内部同拍归零，R283/边界④） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_HbtCause.eNone;                      (* 清成因 / Clear cause *)
    FOR _i := 1 TO DL_HBT_NMAX DO
        aBinCnt[_i] := UDINT#0;                          (* 各格计数同拍归零（幂等） / Bin tallies zeroed *)
    END_FOR
    nTotal := UDINT#0;                                   (* 总入格数归零 / Total zeroed *)
    nClampLow := UDINT#0;                                (* 钳下界计数归零 / Clamp-low zeroed *)
    nClampHigh := UDINT#0;                               (* 钳上界计数归零 / Clamp-high zeroed *)
    nLastBin := 0;                                       (* 落格序号归零 / Bin index zeroed *)
    fLastRatio := 0.0;                                   (* 占比归零 / Ratio zeroed *)
    _eState := E_DL_HbtState.eIdle;                      (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_HbtCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_HbtState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_HbtState.eIdle:                                 (* 未使能：计数清零保持（不留陈旧） / Disabled *)
        FOR _i := 1 TO DL_HBT_NMAX DO
            aBinCnt[_i] := UDINT#0;                      (* 失能各格计数清零 / Disabled tallies cleared *)
        END_FOR
        nTotal := UDINT#0;                               (* 失能总数清零 / Disabled total cleared *)
        nClampLow := UDINT#0;                            (* 失能钳下界清零 / Disabled clamp-low cleared *)
        nClampHigh := UDINT#0;                           (* 失能钳上界清零 / Disabled clamp-high cleared *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_HbtState.eRun;               (* 进入累计相 / Enter running *)
        END_IF
    E_DL_HbtState.eRun:                                  (* 累计相：逐拍落格 / Running *)
        IF NOT bEnable THEN
            _eState := E_DL_HbtState.eIdle;              (* 失能回未使能 / Back to idle *)
        ELSIF _bFin THEN                                 (* 非有限样本整拍拒收（边界③） / Non-finite rejected *)
            FOR _i := 1 TO _nBinsE DO                    (* 边界值直比找格（不用除法，边界②） / Edge compare binning *)
                IF fSample < (fLower + fBinW * INT_TO_REAL(_i)) THEN
                    _nBin := _i;                         (* 首个上界大于样本的格即落格 / First upper edge above sample *)
                    _bHit := TRUE;                       (* 落格成功 / Binned *)
                    EXIT;
                END_IF
            END_FOR
            IF NOT _bHit THEN
                IF fSample < fLower THEN
                    _nBin := 1;                          (* 越下界钳第 1 格（边界②） / Clamp to bin 1 *)
                    IF nClampLow < DL_HBT_CNTMAX THEN
                        nClampLow := nClampLow + UDINT#1;    (* 钳下界计数饱和累加 / Clamp-low tally *)
                    END_IF
                ELSE
                    _nBin := _nBinsE;                    (* 越上界钳末格（边界②） / Clamp to last bin *)
                    IF nClampHigh < DL_HBT_CNTMAX THEN
                        nClampHigh := nClampHigh + UDINT#1;  (* 钳上界计数饱和累加 / Clamp-high tally *)
                    END_IF
                END_IF
                _bHit := TRUE;                           (* 钳边落格成功 / Clamped binned *)
            END_IF
            IF _bHit AND (_nBin >= 1) AND (_nBin <= _nBinsE) THEN    (* 双重下标域闸（防越界写） / Index domain gate *)
                IF aBinCnt[_nBin] < DL_HBT_CNTMAX THEN
                    aBinCnt[_nBin] := aBinCnt[_nBin] + UDINT#1;      (* 该格计数饱和累加 / Bin tally *)
                END_IF
                IF nTotal < DL_HBT_CNTMAX THEN
                    nTotal := nTotal + UDINT#1;          (* 总入格数饱和累加 / Total tally *)
                END_IF
                nLastBin := _nBin;                       (* 落格序号出口 / Bin index outlet *)
                _nCntI := aBinCnt[_nBin];                (* 占比分子中间量 / Ratio numerator *)
                IF nTotal > UDINT#0 THEN                 (* 占比除子 = 总数，零保护（边界⑤） / Ratio divisor gate *)
                    fLastRatio := _nCntI / UDINT_TO_REAL(nTotal);    (* 占比派生（除子已过闸） / Ratio derived *)
                END_IF
            END_IF
        ELSE
            _bRejI := TRUE;                              (* 非有限拍置拒收内部脉冲（R187） / Reject internal pulse *)
        END_IF
    E_DL_HbtState.eFault:                                (* 故障相：计数冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_HbtState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_HbtCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bSampleRej := _bRejI;                                    (* 拒收脉冲单拍出口 / Reject pulse outlet *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
