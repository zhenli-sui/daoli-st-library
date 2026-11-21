(*
  Name        : FB_DL_FirstOrderIdent
  Category    : DL_Algo
  Version     : 1.0.0
  Purpose     : 一阶加纯滞后（FOPDT）阶跃响应回归：阶跃前后双特征点三点法估增益/时间常数/纯滞后，供自整定与 Smith 补偿取参；/ FOPDT step-response regression: two feature points before and after the step estimate gain, time constant and dead time for auto-tuning and Smith predictor
  溯源        : 自研（与 PRBS/继电器整定/扫频激励源配套），clean-room 实现
  Boundary    : ① 阶跃幅值/采样周期/窗长三重域闸，任一越域锁存故障；
                ② 辨识窗须含阶跃前稳态（>= 8 有效拍均值）与阶跃后 28.3%/63.2% 两特征点，缺任一 → 有效性 FALSE 不出参数（信息级）；
                ③ 三点法公式全代数无迭代（增益分母 = 阶跃幅值，已过正域闸；除子常量均非零）；
                ④ 非有限测量该拍不入辨识窗（窗计数暂停非快进，防污染统计）；
                ⑤ 输出 K/T/θ 非负域钳位，θ 上限 = 辨识窗时长（防无滞后误设大滞后）；
                ⑥ 本件为辨识观测层，不输出任何控制量（属主边界）。
*)
TYPE E_DL_FoiState :
(
    eIdle  := 0,                             (* 未辨识 / Not identifying *)
    eWait  := 10,                            (* 阶跃前稳态采集 / Pre-step steady sampling *)
    ePost  := 20,                            (* 阶跃后窗采集 / Post-step window sampling *)
    eReady := 30,                            (* 辨识完成（有效性查 bValid） / Finished, see bValid *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_FoiCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：幅值/周期/窗长越域 / Illegal config *)
    eNoFeat    := 2,                        (* 信息级：缺稳态/特征点或增益反号 / Info: feature missing *)
    ePhaseBad  := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_FirstOrderIdent
VAR_INPUT
    fMeas   : REAL := 0.0;                   (* 回路测量值（任意工程量）[-] / Loop measurement *)
    fStepAmp: REAL := 10.0;                  (* 阶跃幅值，域 > 0 [工程单位] / Step amplitude *)
    tSample : TIME := T#100MS;               (* 采样周期，域 > T#0S [ms] / Sampling period *)
    nWin    : INT := 128;                    (* 阶跃后窗长，域 20..256 [拍] / Post-step window length *)
    bStart  : BOOL := FALSE;                 (* 启动辨识命令，上升沿进入稳态采集 [-] / Start command *)
    bEnable : BOOL := TRUE;                  (* 使能 [-] / Enable *)
    bReset  : BOOL := FALSE;                 (* 复位命令，上升沿清故障与结果 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fK      : REAL;                          (* 增益出口 = 稳态增量 / 阶跃幅值 [-] / Gain outlet *)
    fTau    : REAL;                          (* 时间常数出口 [s] / Time constant outlet *)
    fTheta  : REAL;                          (* 纯滞后出口（非负，上限 = 窗时长）[s] / Dead time outlet *)
    bValid  : BOOL;                          (* 结果有效性出口 [-] / Result validity *)
    nSamples: INT;                           (* 阶跃后窗内有效样本数 [拍] / Valid samples in window *)
    eState  : E_DL_FoiState;                 (* 状态出口 / State outlet *)
    eCause  : E_DL_FoiCause;                 (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError  : BOOL;                          (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_FoiState := E_DL_FoiState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_FoiCause := E_DL_FoiCause.eNone;  (* 成因锁存量 / Latched cause *)
    rtStart : R_TRIG;                        (* 启动沿实例，段 0 无条件调用 / Start edge instance *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                          (* 测量有限性当拍量（边界④） / Measurement finiteness *)
    _nWinE  : INT;                           (* 钳位后生效窗长 [拍] / Effective window length *)
    _nPreN  : INT;                           (* 稳态已采有效拍数 [拍] / Pre samples collected *)
    _fPreSum: REAL;                          (* 稳态样本累加和 [工程单位] / Pre samples sum *)
    _fY0    : REAL;                          (* 阶跃前稳态均值 [工程单位] / Baseline mean *)
    _nRecN  : INT;                           (* 窗内已收有效样本数 [拍] / Window samples count *)
    _aRec   : ARRAY[1..256] OF REAL;         (* 窗内样本记录（连续有效区）[工程单位] / Window sample record *)
    _fYinf  : REAL;                          (* 窗末稳态均值 [工程单位] / Final steady mean *)
    _fDelta : REAL;                          (* 稳态增量中间量 [工程单位] / Steady delta *)
    _fKI    : REAL;                          (* 增益中间量 [-] / Gain intermediate *)
    _fT1    : REAL;                          (* 28.3% 特征时刻 [s] / Feature time 1 *)
    _fT2    : REAL;                          (* 63.2% 特征时刻 [s] / Feature time 2 *)
    _fTauI  : REAL;                          (* 时间常数中间量 [s] / Tau intermediate *)
    _fThI   : REAL;                          (* 滞后中间量 [s] / Theta intermediate *)
    _i      : INT;                           (* 窗扫描游标 [拍] / Window scan cursor *)
    _fDtSec : REAL;                          (* 采样周期秒值，域 > eps [s] / Sampling period seconds *)
END_VAR
VAR CONSTANT
    DL_FOI_NPRE   : INT  := 8;               (* 阶跃前稳态最少有效拍数（边界②）[拍] / Pre-step minimum samples *)
    DL_FOI_NTAIL  : INT  := 8;               (* 窗末稳态平均样本数 [拍] / Tail averaging samples *)
    DL_FOI_WMIN   : INT  := 20;              (* 窗长下限（边界①）[拍] / Window lower bound *)
    DL_FOI_WMAX   : INT  := 256;             (* 窗长上限（数组容量）[拍] / Window upper bound *)
    DL_FOI_EPS    : REAL := 1.0E-6;          (* 判零容差 [-] / Epsilon *)
    DL_FOI_L1     : REAL := 0.283;           (* 特征点 1 归一化水平（1-exp(-1/3)）[-] / Feature level 1 *)
    DL_FOI_L2     : REAL := 0.632;           (* 特征点 2 归一化水平（1-exp(-1)）[-] / Feature level 2 *)
    DL_FOI_STEPDET: REAL := 0.1;             (* 阶跃检测阈（幅值占比）[-] / Step detect threshold *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tSample) / 1000.0;              (* 采样周期秒化（除子常量 1000） / Sampling period seconds *)
_bCfgBad := (fStepAmp <= DL_FOI_EPS)                     (* 阶跃幅值正域闸（边界①） / Step amplitude gate *)
            OR NOT (tSample > T#0S)                      (* 采样周期正域闸（边界①） / Sampling gate *)
            OR (nWin < DL_FOI_WMIN) OR (nWin > DL_FOI_WMAX);   (* 窗长域闸（边界①） / Window gate *)
rtStart(CLK := bStart);                                  (* 启动沿每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fMeas = fMeas) AND ((fMeas - fMeas) = (fMeas - fMeas));   (* 测量 NaN 自反 + Inf 差判闸（边界④） / Measurement NaN and Inf gate *)
_nWinE := nWin;                                          (* 生效窗长初值 / Effective window init *)
IF _nWinE < DL_FOI_WMIN THEN
    _nWinE := DL_FOI_WMIN;                               (* 窗长下限钳位 / Window lower clamp *)
END_IF
IF _nWinE > DL_FOI_WMAX THEN
    _nWinE := DL_FOI_WMAX;                               (* 窗长上限钳位（防数组越界） / Window upper clamp *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
nSamples := 0;                                           (* 样本数出口预清（派生拍覆盖） / Samples outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清辨识状态 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_FoiCause.eNone;                      (* 清成因 / Clear cause *)
    bValid := FALSE;                                     (* 清有效性出口 / Clear validity *)
    fK := 0.0; fTau := 0.0; fTheta := 0.0;               (* 清 K/T/θ 出口 / Clear K T theta *)
    _nPreN := 0; _fPreSum := 0.0;                        (* 清稳态采集量 / Clear pre sampling *)
    _nRecN := 0;                                         (* 清窗样本数 / Clear window count *)
    _eState := E_DL_FoiState.eIdle;                      (* 迁未辨识相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_FoiCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_FoiState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_FoiState.eIdle:                                 (* 未辨识：出口保持确定值 / Idle *)
        bValid := FALSE;                                 (* 未辨识有效性 FALSE（不留陈旧） / Validity false *)
        IF rtStart.Q AND bEnable AND NOT _bFault THEN
            _nPreN := 0; _fPreSum := 0.0;                (* 清稳态采集（新一轮） / Clear pre sampling *)
            _nRecN := 0;                                 (* 清窗样本（新一轮） / Clear window samples *)
            _eState := E_DL_FoiState.eWait;              (* 进入稳态采集相 / Enter pre sampling *)
        END_IF
    E_DL_FoiState.eWait:                                 (* 稳态采集相：阶跃前基线 / Pre-step sampling *)
        IF NOT bEnable THEN
            _eState := E_DL_FoiState.eIdle;              (* 失能回未辨识 / Back to idle *)
        ELSIF _bFin THEN                                 (* 非有限拍不入窗（计数暂停，边界④） / Skip non-finite *)
            _fPreSum := _fPreSum + fMeas;                (* 稳态样本累加 / Pre sample accumulate *)
            _nPreN := _nPreN + 1;                        (* 有效拍数净额 +1 / Valid count *)
            IF _nPreN >= DL_FOI_NPRE THEN
                _fY0 := _fPreSum / INT_TO_REAL(_nPreN);  (* 稳态均值（除子 = 有效拍数 >= 8） / Baseline mean *)
                IF ABS(fMeas - _fY0) > DL_FOI_STEPDET * fStepAmp THEN   (* 阶跃检测（幅值占比直比） / Step detected *)
                    _nRecN := 0;                         (* 窗样本从阶跃后重计 / Window from step *)
                    _eState := E_DL_FoiState.ePost;      (* 进入阶跃后窗相 / Enter post window *)
                END_IF
            END_IF
        END_IF
    E_DL_FoiState.ePost:                                 (* 阶跃后窗相：连续采样至窗满 / Post window *)
        IF NOT bEnable THEN
            _eState := E_DL_FoiState.eIdle;              (* 失能回未辨识 / Back to idle *)
        ELSIF _bFin THEN                                 (* 非有限拍不入窗（暂停非快进，边界④） / Skip non-finite *)
            IF _nRecN < _nWinE THEN
                _nRecN := _nRecN + 1;                    (* 窗样本净额 +1（写入点下标域内） / Window count *)
                _aRec[_nRecN] := fMeas;                  (* 样本入记录（下标 1.._nWinE 钳定） / Sample recorded *)
            END_IF
            IF _nRecN >= _nWinE THEN
                nSamples := _nRecN;                      (* 窗内有效样本数出口 / Samples outlet *)
                _fYinf := 0.0;                           (* 窗末均值累加清零 / Tail mean clear *)
                FOR _i := _nRecN - DL_FOI_NTAIL + 1 TO _nRecN DO   (* 末 8 样本均值（区段域内） / Tail mean *)
                    _fYinf := _fYinf + _aRec[_i];        (* 尾段累加 / Tail accumulate *)
                END_FOR
                _fYinf := _fYinf / INT_TO_REAL(DL_FOI_NTAIL);   (* 尾段均值（除子常量 8） / Tail mean *)
                _fDelta := _fYinf - _fY0;                (* 稳态增量（阶跃后末均值 - 阶跃前均值） / Steady delta *)
                _fKI := _fDelta / fStepAmp;              (* 增益（除子 = 幅值已过正域闸，边界③） / Gain *)
                _fT1 := 0.0; _fT2 := 0.0;                (* 特征时刻清零（未命中哨兵） / Feature times clear *)
                FOR _i := 1 TO _nRecN DO
                    IF (_fT1 <= DL_FOI_EPS) AND (_aRec[_i] >= _fY0 + DL_FOI_L1 * _fDelta) THEN
                        _fT1 := INT_TO_REAL(_i) * _fDtSec;   (* 首过 28.3% 时刻（边界②） / First level 1 time *)
                    END_IF
                    IF (_fT2 <= DL_FOI_EPS) AND (_aRec[_i] >= _fY0 + DL_FOI_L2 * _fDelta) THEN
                        _fT2 := INT_TO_REAL(_i) * _fDtSec;   (* 首过 63.2% 时刻（边界②） / First level 2 time *)
                    END_IF
                END_FOR
                IF (_fT1 > DL_FOI_EPS) AND (_fT2 > DL_FOI_EPS) AND (_fT2 > _fT1) AND (_fKI > 0.0) THEN
                    _fTauI := 1.5 * (_fT2 - _fT1);       (* 两点法时间常数（公开代数式，除子常量） / Two-point tau *)
                    _fThI := _fT2 - _fTauI;              (* 两点法纯滞后 / Two-point theta *)
                    IF _fTauI < 0.0 THEN
                        _fTauI := 0.0;                   (* 时间常数非负钳位（边界⑤） / Tau clamp *)
                    END_IF
                    IF _fThI < 0.0 THEN
                        _fThI := 0.0;                    (* 滞后非负钳位（边界⑤） / Theta clamp *)
                    END_IF
                    IF _fThI > INT_TO_REAL(_nRecN) * _fDtSec THEN
                        _fThI := INT_TO_REAL(_nRecN) * _fDtSec;   (* 滞后上限 = 窗时长（边界⑤） / Theta window cap *)
                    END_IF
                    fK := _fKI;                          (* 增益出口（非负已闸） / Gain outlet *)
                    fTau := _fTauI;                      (* 时间常数出口 / Tau outlet *)
                    fTheta := _fThI;                     (* 滞后出口 / Theta outlet *)
                    bValid := TRUE;                      (* 有效性 TRUE / Validity true *)
                    _eState := E_DL_FoiState.eReady;     (* 迁完成相 / To ready *)
                ELSE
                    bValid := FALSE;                     (* 缺特征点或增益反号：不出参数（边界②⑤） / Invalid *)
                    _eCause := E_DL_FoiCause.eNoFeat;    (* 信息级成因（不置 bError） / Info cause *)
                    _eState := E_DL_FoiState.eReady;     (* 迁完成相（无效结论） / To ready invalid *)
                END_IF
            END_IF
        END_IF
    E_DL_FoiState.eReady:                                (* 完成相：结论冻结保持 / Ready *)
        IF rtStart.Q THEN
            _eState := E_DL_FoiState.eIdle;              (* 新启动沿经 eIdle 重入（防隐性回夹） / Restart via idle *)
        END_IF
    E_DL_FoiState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_FoiState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_FoiCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
