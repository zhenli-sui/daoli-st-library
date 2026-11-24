(*
  Name        : FB_DL_AxisHomeRepeatVerify
  Category    : DL_Motion
  Version     : 1.0.1
  Purpose     : 回零重复性校验：收集 N 次回零到位位置，求均值/标准差/极差，散布超容差即拒绝放行（bPass = FALSE）；/ Verify homing repeatability: collect N homing positions, compute mean, standard deviation and range, and refuse release when the spread exceeds the tolerance
  溯源        : 借 t1-6-plcopen·homing 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：样本数域 2..16 / 容差 <= 0 → 锁存故障（样本数 < 2 时标准差无意义）；
                ② 除子闸：标准差除子 (n-1) 恒 >= 1（n >= 2 由组态闸保证）；极差无除法；
                ③ 非有限位置该次不入样（拒收计数 bSampleRej 供诊断），不污染统计；
                ④ 完成脉冲单拍化：内部 _bDoneC 置位 → 出口统一映射（R187），不在 CASE 内直写；
                ⑤ 判定用「极差 <= 容差 且 3σ <= 容差」双条件，任一不满足即拒绝。
  修订记录    : 2026-11-20 v1.0.1：bPass/bReject 每拍预清移入 eCollect 结算拍（eDone 相保持判定，R52-02/R191）；eIdle 分支补 nGot 出口同步清零（R52-03）。
*)
TYPE E_DL_AhrState :
(
    eIdle   := 0,                            (* 未使能 / Disabled *)
    eCollect:= 10,                           (* 采样收集中 / Collecting *)
    eDone   := 20,                           (* 判定完成（等复位/等下一次启采） / Verdict done *)
    eFault  := 90                            (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_AhrCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：样本数/容差越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisHomeRepeatVerify
VAR_INPUT
    fHomePos  : REAL := 0.0;                 (* 回零到位位置（实际位置）[mm] / Homing position *)
    bHomeDone : BOOL := FALSE;               (* 单次回零完成脉冲（上升沿采一个样本）[-] / One homing done pulse *)
    nSamples  : INT := 5;                    (* 采样次数，域 2..16 [次] / Sample count, 2..16 *)
    fTolSpread: REAL := 0.05;                (* 允许散布（极差与 3σ 共用），域 > 0 [mm] / Allowed spread, > 0 *)
    bEnable   : BOOL := TRUE;                (* 校验使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清样本与判定 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nGot      : INT;                         (* 已收有效样本数 [次] / Valid samples collected *)
    fMean     : REAL;                        (* 样本均值 [mm] / Sample mean *)
    fStdDev   : REAL;                        (* 样本标准差（n-1 分母）[mm] / Sample standard deviation *)
    fSpread   : REAL;                        (* 极差 = max - min [mm] / Range *)
    bPass     : BOOL;                        (* 判定：重复性合格（可放行）[-] / Repeatability passed *)
    bReject   : BOOL;                        (* 判定：超散拒绝放行 [-] / Rejected *)
    bDone     : BOOL;                        (* 判定完成单拍脉冲 [-] / Verdict done pulse *)
    bSampleRej: BOOL;                        (* 本拍有非有限样本被拒收 [-] / Sample rejected this scan *)
    eState    : E_DL_AhrState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_AhrCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_AhrState := E_DL_AhrState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_AhrCause := E_DL_AhrCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtDone   : R_TRIG;                       (* 完成脉冲上升沿实例，段 0 无条件调用 / Homing done edge *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite : BOOL;                         (* 位置有限性当拍量 / Position finiteness *)
    _bDoneC  : BOOL;                         (* 判定完成内部单拍量（出口统一映射） / Done internal pulse *)
    _bFin    : BOOL;                         (* 本拍样本收下标志 / Sample accepted this scan *)
    _aPos    : ARRAY[1..16] OF REAL;         (* 回零位置样本数组 [mm] / Homing position samples *)
    _nGot    : INT;                          (* 样本计数 [次] / Sample counter *)
    _nIdx    : INT;                          (* 统计游标（每趟重置，R227）[-] / Stats cursor *)
    _nEff    : INT;                          (* 钳位后生效样本数 [次] / Clamped sample count *)
    _fSum    : REAL;                         (* Σx [mm] / Sum *)
    _fMeanI  : REAL;                         (* 均值中间量 [mm] / Mean intermediate *)
    _fVar    : REAL;                         (* Σ(x-x̄)² [mm²] / Sum of squares *)
    _fMin    : REAL;                         (* 样本最小值 [mm] / Minimum *)
    _fMax    : REAL;                         (* 样本最大值 [mm] / Maximum *)
    _fStd    : REAL;                         (* 标准差中间量 [mm] / Std intermediate *)
END_VAR
VAR CONSTANT
    DL_AHR_EPS   : REAL := 1.0E-6;           (* 判零容差 [-] / Epsilon *)
    DL_AHR_NMAX  : INT  := 16;               (* 样本容量上限 [次] / Sample capacity *)
    DL_AHR_NMIN  : INT  := 2;                (* 样本数下限（标准差最少两点）[次] / Sample lower bound *)
    DL_AHR_SIGMA : REAL := 3.0;              (* 散布判据 σ 倍数（3σ 工程惯例）[-] / Sigma multiplier *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (nSamples < DL_AHR_NMIN) OR (nSamples > DL_AHR_NMAX)               (* 样本数域闸 / Sample-count gate *)
            OR (fTolSpread <= DL_AHR_EPS);                                     (* 容差正域闸 / Tolerance gate *)
rtDone(CLK := bHomeDone);                                                      (* 完成沿每拍必调 / Done edge every scan *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fHomePos = fHomePos) AND ((fHomePos - fHomePos) = (fHomePos - fHomePos));   (* NaN 自反 + Inf 差判 / NaN and Inf gate *)
_nEff := nSamples;                                                             (* 生效样本数初值 / Effective count *)
IF _nEff < DL_AHR_NMIN THEN
    _nEff := DL_AHR_NMIN;                                                      (* 下限钳位 / Lower clamp *)
END_IF
IF _nEff > DL_AHR_NMAX THEN
    _nEff := DL_AHR_NMAX;                                                      (* 上限钳位（R308） / Upper clamp *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_bDoneC := FALSE;                                                              (* 完成脉冲内部量预清 / Done preset *)
bSampleRej := FALSE;                                                           (* 拒收指示预清 / Reject-sample preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清样本 + 清统计 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_AhrCause.eNone;                                            (* 清成因 / Clear cause *)
    _nGot := 0;                                                                (* 清样本计数 / Clear sample counter *)
    nGot := 0;                                                                 (* 清出口计数 / Clear outlet count *)
    fMean := 0.0;                                                              (* 清均值出口 / Clear mean *)
    fStdDev := 0.0;                                                            (* 清标准差出口 / Clear std *)
    fSpread := 0.0;                                                            (* 清极差出口 / Clear range *)
    _eState := E_DL_AhrState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_AhrCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_AhrState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_AhrState.eIdle:                                                       (* 未使能：不采样 / Disabled *)
        _nGot := 0;                                                            (* 失能清样本计数（防隐性回夹） / Clear sample counter *)
        nGot := 0;                                                             (* 失能同步清出口计数（R52-03 名实一致） / Clear outlet count *)
        bPass := FALSE;                                                        (* 失能清判定出口（复位/失能路径出口清零） / Clear verdict outlets *)
        bReject := FALSE;                                                      (* 失能清拒绝出口 / Clear reject outlet *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_AhrState.eCollect;                                 (* 使能进入收集 / Enter collecting *)
        END_IF
    E_DL_AhrState.eCollect:                                                    (* 收集相：逐次入样 / Collecting *)
        IF NOT bEnable THEN
            _eState := E_DL_AhrState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF rtDone.Q THEN                                                    (* 一次回零完成 / One homing done *)
            _bFin := _bFinite;                                                 (* 本拍样本有效性 / Sample validity *)
            IF _bFin AND (_nGot < DL_AHR_NMAX) THEN
                _nGot := _nGot + 1;                                            (* 计数先增（<= 容量闸） / Count up within capacity *)
                _aPos[_nGot] := fHomePos;                                      (* 入样（下标已由容量闸限住） / Store sample *)
                nGot := _nGot;                                                 (* 出口计数镜像 / Outlet mirror *)
            ELSIF NOT _bFin THEN
                bSampleRej := TRUE;                                            (* 非有限样本拒收（边界③） / Reject non-finite *)
            END_IF
        END_IF
        IF _nGot >= _nEff THEN                                                 (* 样本到齐：一次性统计 / Enough samples: compute *)
            _fSum := 0.0;                                                      (* Σx 预清 / Sum preset *)
            _nIdx := 1;                                                        (* 游标起头（R227） / Cursor reset *)
            _fMin := _aPos[1];                                                 (* 最小值初值取首样本 / Min init *)
            _fMax := _aPos[1];                                                 (* 最大值初值取首样本 / Max init *)
            WHILE _nIdx <= _nEff DO                                            (* 一趟求 Σx/min/max（下标已钳位） / One pass for sum/min/max *)
                _fSum := _fSum + _aPos[_nIdx];                                 (* Σx [mm] / Sum *)
                IF _aPos[_nIdx] < _fMin THEN
                    _fMin := _aPos[_nIdx];                                     (* 更新最小值 / Update min *)
                END_IF
                IF _aPos[_nIdx] > _fMax THEN
                    _fMax := _aPos[_nIdx];                                     (* 更新最大值 / Update max *)
                END_IF
                _nIdx := _nIdx + 1;                                            (* 游标递进 / Cursor advance *)
            END_WHILE
            _fMeanI := _fSum / DINT_TO_REAL(_nEff);                            (* 均值：除子 nEff >= 2 无除零 [mm] / Mean, divisor >= 2 *)
            fMean := _fMeanI;                                                  (* 均值出口 / Mean outlet *)
            fSpread := _fMax - _fMin;                                          (* 极差（无除法）[mm] / Range *)
            _fVar := 0.0;                                                      (* 平方和预清 / Squares preset *)
            _nIdx := 1;                                                        (* 游标重起 / Cursor reset *)
            WHILE _nIdx <= _nEff DO                                            (* 二趟求 Σ(x-x̄)² / Second pass for variance *)
                _fVar := _fVar + (_aPos[_nIdx] - _fMeanI) * (_aPos[_nIdx] - _fMeanI);   (* 平方项恒非负 [mm²] / Squared deviation *)
                _nIdx := _nIdx + 1;                                            (* 游标递进 / Cursor advance *)
            END_WHILE
            _fStd := SQRT(_fVar / DINT_TO_REAL(_nEff - 1));                    (* 样本标准差：除子 nEff-1 >= 1 [mm] / Sample std, divisor >= 1 *)
            fStdDev := _fStd;                                                  (* 标准差出口 / Std outlet *)
            bPass := FALSE;                                                    (* 结算拍预清合格位（当拍二选一赋值，eDone 相保持） / Preset pass at settle scan *)
            bReject := FALSE;                                                  (* 结算拍预清拒绝位 / Preset reject at settle scan *)
            IF (fSpread <= fTolSpread) AND ((DL_AHR_SIGMA * _fStd) <= fTolSpread) THEN
                bPass := TRUE;                                                 (* 双条件满足：重复性合格 / Both conditions met: pass *)
            ELSE
                bReject := TRUE;                                               (* 任一不满足：超散拒绝放行 / Reject on spread *)
            END_IF
            _bDoneC := TRUE;                                                   (* 完成脉冲内部置位（出口统一映射，R187） / Done pulse internal *)
            _eState := E_DL_AhrState.eDone;                                    (* 迁完成相 / To done *)
        END_IF
    E_DL_AhrState.eDone:                                                       (* 完成相：保持判定，等复位或重新使能 / Done *)
        IF NOT bEnable THEN
            _eState := E_DL_AhrState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        END_IF
    E_DL_AhrState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_AhrState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_AhrCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bDone := _bDoneC;                                                              (* 完成脉冲单拍出口 / Done single-scan outlet *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
