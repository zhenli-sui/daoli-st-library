(*
  Name        : FB_DL_BearingVibTrend
  Category    : DL_Algo
  Version     : 1.0.0
  Purpose     : 轴承振动 RMS 滑窗趋势分级预警：采样触发下把振动 RMS 入环形窗，按窗内均值与峰值对 ISO 10816 三档门槛（良好/注意/报警）分级；/ Bearing vibration RMS sliding-window trend: RMS samples enter a ring window, graded against ISO 10816 three-band thresholds by window mean and peak
  溯源        : 借 t2-1-lgf-measurement 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：窗长域 4..32 / 注意与报警门槛须正且注意 < 报警 → 锁存故障；
                ② 环窗时间序范式（R194/R205）：_nHead 声明即赋初值 1；窗深变更后回钳 _nHead/_nFill，防越界写与环序破坏；
                ③ 非有限 RMS 该次不入样（拒收计数 bSampleRej 供诊断），不污染统计；
                ④ 分级判据全部 >= 阈值直比（阈值来自组态，非浮点等值比较）；
                ⑤ 本件为趋势诊断层，不停机不联锁（属主边界）。
*)
TYPE E_DL_BvtState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 趋势监视运行 / Monitoring *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_BvtCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：窗长/门槛越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BearingVibTrend
VAR_INPUT
    fVibRms   : REAL := 0.0;                 (* 振动速度 RMS 实测 [mm/s] / Vibration velocity RMS *)
    bSample   : BOOL := FALSE;               (* 采样触发脉冲（上升沿采一个样本）[-] / Sample trigger pulse *)
    nWinLen   : INT := 16;                   (* 滑窗深度，域 4..32 [点] / Window depth, 4..32 *)
    fThGood   : REAL := 2.8;                 (* ISO 10816 良好档上限（A/B 分界），域 > 0 [mm/s] / Good-band limit *)
    fThAlert  : REAL := 7.1;                 (* ISO 10816 报警档下限（C/D 分界），域 > 注意档 [mm/s] / Alarm-band limit *)
    bEnable   : BOOL := TRUE;                (* 监视使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清窗与预警 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fRmsMean  : REAL;                        (* 窗内 RMS 均值 [mm/s] / Window mean *)
    fRmsPeak  : REAL;                        (* 窗内 RMS 峰值 [mm/s] / Window peak *)
    nFill     : INT;                         (* 窗内有效样本数 [点] / Valid samples in window *)
    bGood     : BOOL;                        (* 分级：良好档（均值 <= 良好门槛）[-] / Good band *)
    bAlert    : BOOL;                        (* 分级：注意档（未达报警但超良好门槛）[-] / Alert band *)
    bAlarm    : BOOL;                        (* 分级：报警档（峰值或均值 >= 报警门槛）[-] / Alarm band *)
    bSampleRej: BOOL;                        (* 本拍有非有限样本被拒收 [-] / Sample rejected this scan *)
    eState    : E_DL_BvtState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_BvtCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_BvtState := E_DL_BvtState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_BvtCause := E_DL_BvtCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtSample : R_TRIG;                       (* 采样触发沿实例，段 0 无条件调用 / Sample edge instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFin    : BOOL;                         (* RMS 有限性当拍量 / RMS finiteness *)
    _aRms    : ARRAY[1..32] OF REAL;         (* 振动 RMS 环形样本数组 [mm/s] / Ring buffer of RMS samples *)
    _nHead   : INT := 1;                     (* 环形写头（声明即赋初值 1，R194 教训） / Ring write head, init 1 *)
    _nFill   : INT;                          (* 环窗已填样本数 [点] / Ring fill count *)
    _nEff    : INT;                          (* 钳位后生效窗深 [点] / Effective window depth *)
    _nIdx    : INT;                          (* 统计游标（每趟重置，R227）[-] / Stats cursor *)
    _fSum    : REAL;                         (* Σx 中间量 [mm/s] / Sum intermediate *)
    _fMeanI  : REAL;                         (* 均值中间量 [mm/s] / Mean intermediate *)
    _fPeakI  : REAL;                         (* 峰值中间量 [mm/s] / Peak intermediate *)
END_VAR
VAR CONSTANT
    DL_BVT_EPS    : REAL := 1.0E-6;          (* 判零容差 [-] / Epsilon *)
    DL_BVT_NMAX   : INT  := 32;              (* 窗容量上限 [点] / Window capacity *)
    DL_BVT_NMIN   : INT  := 4;               (* 窗深下限（保证趋势统计有效）[点] / Window depth lower bound *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (nWinLen < DL_BVT_NMIN) OR (nWinLen > DL_BVT_NMAX)                 (* 窗长域闸 / Window-depth gate *)
            OR (fThGood <= DL_BVT_EPS)                                         (* 良好门槛正域闸 / Good-limit gate *)
            OR (fThAlert <= fThGood);                                          (* 报警门槛须大于注意/良好门槛（防档位倒置） / Alarm limit above good limit *)
rtSample(CLK := bSample);                                                      (* 采样沿每拍必调 / Sample edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fVibRms = fVibRms) AND ((fVibRms - fVibRms) = (fVibRms - fVibRms));  (* RMS NaN 自反 + Inf 差判闸 / RMS NaN and Inf gate *)
_nEff := nWinLen;                                                              (* 生效窗深初值 / Effective depth init *)
IF _nEff < DL_BVT_NMIN THEN
    _nEff := DL_BVT_NMIN;                                                      (* 窗深下限钳位 / Lower clamp *)
END_IF
IF _nEff > DL_BVT_NMAX THEN
    _nEff := DL_BVT_NMAX;                                                      (* 窗深上限钳位（R308） / Upper clamp *)
END_IF
IF _nHead > _nEff THEN
    _nHead := 1;                                                               (* 窗深变小后回钳写头（环序重同步，R194/R205） / Re-clamp head after depth shrink *)
END_IF
IF _nFill > _nEff THEN
    _nFill := _nEff;                                                           (* 窗深变小后回钳填充数（防封顶失效） / Re-clamp fill after depth shrink *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
bSampleRej := FALSE;                                                           (* 拒收指示预清 / Reject-sample preset *)
bGood := FALSE;                                                                (* 良好档预清 / Good preset *)
bAlert := FALSE;                                                               (* 注意档预清 / Alert preset *)
bAlarm := FALSE;                                                               (* 报警档预清 / Alarm preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清环窗（仅头/填充数与游标，数据域随填充数失效）+ 清出口 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_BvtCause.eNone;                                            (* 清成因 / Clear cause *)
    _nHead := 1;                                                               (* 写头回 1（声明同值） / Head back to 1 *)
    _nFill := 0;                                                               (* 清填充数（旧数据随计数失效） / Clear fill *)
    nFill := 0;                                                                (* 清填充数出口 / Clear fill outlet *)
    fRmsMean := 0.0;                                                           (* 清均值出口 / Clear mean outlet *)
    fRmsPeak := 0.0;                                                           (* 清峰值出口 / Clear peak outlet *)
    _eState := E_DL_BvtState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_BvtCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_BvtState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_BvtState.eIdle:                                                       (* 未使能：不采样 / Disabled *)
        _nFill := 0;                                                           (* 失能清填充数（防隐性回夹） / Clear fill *)
        nFill := 0;                                                            (* 失能清填充数出口 / Clear fill outlet *)
        fRmsMean := 0.0;                                                       (* 失能清均值出口（eIdle/eFault 出口确定值） / Clear mean outlet *)
        fRmsPeak := 0.0;                                                       (* 失能清峰值出口 / Clear peak outlet *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_BvtState.eMon;                                     (* 使能进入监视 / Enter monitoring *)
        END_IF
    E_DL_BvtState.eMon:                                                        (* 监视相：采样入窗 + 统计分级 / Monitoring *)
        IF NOT bEnable THEN
            _eState := E_DL_BvtState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF rtSample.Q THEN                                                  (* 采样触发：一次入样 / Sample trigger *)
            IF _bFin THEN                                                      (* 有限样本入窗 / Finite sample accepted *)
                _aRms[_nHead] := fVibRms;                                      (* 环窗写入（下标已由段 0 回钳保证 1.._nEff） / Ring write, index clamped *)
                _nHead := _nHead + 1;                                          (* 写头递进 / Head advance *)
                IF _nHead > _nEff THEN
                    _nHead := 1;                                               (* 写头回卷到 1 / Head wrap to 1 *)
                END_IF
                IF _nFill < _nEff THEN
                    _nFill := _nFill + 1;                                      (* 未满窗则填充数递增 / Fill up to depth *)
                END_IF
                nFill := _nFill;                                               (* 填充数出口镜像 / Fill outlet mirror *)
            ELSE
                bSampleRej := TRUE;                                            (* 非有限样本拒收（边界③） / Reject non-finite *)
            END_IF
            _fSum := 0.0;                                                      (* Σx 预清 / Sum preset *)
            _fPeakI := 0.0;                                                    (* 峰值预清（RMS 恒 >= 0，0 起步安全） / Peak preset *)
            _nIdx := 1;                                                        (* 游标起头（R227） / Cursor reset *)
            WHILE _nIdx <= _nFill DO                                           (* 一趟求 Σx/峰值（下标域 1.._nFill 有界） / One pass for sum and peak *)
                _fSum := _fSum + _aRms[_nIdx];                                 (* Σx [mm/s] / Sum *)
                IF _aRms[_nIdx] > _fPeakI THEN
                    _fPeakI := _aRms[_nIdx];                                   (* 更新峰值 / Update peak *)
                END_IF
                _nIdx := _nIdx + 1;                                            (* 游标递进 / Cursor advance *)
            END_WHILE
            IF _nFill >= DL_BVT_NMIN THEN                                      (* 窗内样本足额才刷新统计与分级 / Grade only with enough samples *)
                _fMeanI := _fSum / DINT_TO_REAL(_nFill);                       (* 均值：除子 _nFill >= 4 无除零 [mm/s] / Mean, divisor >= 4 *)
                fRmsMean := _fMeanI;                                           (* 均值出口 / Mean outlet *)
                fRmsPeak := _fPeakI;                                           (* 峰值出口 / Peak outlet *)
                IF (_fPeakI >= fThAlert) OR (_fMeanI >= fThAlert) THEN
                    bAlarm := TRUE;                                            (* 报警档：峰值或均值达报警门槛 / Alarm band *)
                ELSIF (_fPeakI >= fThGood) OR (_fMeanI >= fThGood) THEN
                    bAlert := TRUE;                                            (* 注意档：超良好门槛未达报警 / Alert band *)
                ELSE
                    bGood := TRUE;                                             (* 良好档：均值与峰值均低于良好门槛 / Good band *)
                END_IF
            END_IF
        END_IF
    E_DL_BvtState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_BvtState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_BvtCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
