(*
  Name        : FB_DL_SweepFreqGen
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 频率扫描激励发生：线性/对数两模式按起止频率 + 驻留时间表逐段推进，相位逐拍积分输出瞬时频率与相位；/ Frequency sweep excitation generator: linear or logarithmic mode stepping through a dwell-time table between start and stop frequency, with per-scan phase integration
  溯源        : 借 lgf-siggen 的频率发生族待挖组织，clean-room 实现
  Boundary    : ① 起/止频率正域且相等不立（相等退化点频拒绝），越域锁存故障；
                ② 对数扫频禁对零取对数：起频下限 > 0 由正域闸保证（EXP/LN 仅作用于正比值）；
                ③ 相位积分逐拍累加防跳频突跳，相位回卷 2π 用条件减法（禁取模），回卷循环带上限守卫；
                ④ 使能撤除相位保持不归零，bRestart 上升沿显式重启回首段首相位；
                ⑤ 驻留表下标越界钳位（下标域闸）+ 非正驻留钳最小驻留常量；非有限派生频率该拍冻结保持输出；
                ⑥ 本件只出频率/相位激励量，不直接驱动脉冲输出口（属主边界，与 PulseGenerator 职责分立）。
*)
TYPE E_DL_SwpMode :
(
    eLin := 0,                               (* 线性扫频 / Linear sweep *)
    eLog := 10                               (* 对数扫频 / Logarithmic sweep *)
);
END_TYPE

TYPE E_DL_SwpState :
(
    eIdle  := 0,                             (* 未使能（相位保持） / Disabled, phase held *)
    eRun   := 10,                            (* 扫频运行 / Sweeping *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_SwpCause :
(
    eNone      := 0,                         (* 无故障成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：频率域/步数/周期越域 / Illegal config *)
    ePhaseBad  := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SweepFreqGen
VAR_INPUT
    fStart  : REAL := 1.0;                   (* 起始频率，域 > 0 且不等于止频 [Hz] / Start frequency *)
    fEnd    : REAL := 100.0;                 (* 结束频率，域 > 0 且不等于起频 [Hz] / Stop frequency *)
    eMode   : E_DL_SwpMode := E_DL_SwpMode.eLin;   (* 扫频模式 / Sweep mode *)
    nSteps  : INT := 8;                      (* 驻留段数，域 2..32 [段] / Dwell step count *)
    aDwell  : ARRAY[1..32] OF TIME;          (* 各段驻留时间表（越界/非正钳位）[ms] / Dwell time table *)
    tScan   : TIME := T#10MS;                (* 扫描周期，域 > T#0S [ms] / Scan period *)
    bRepeat : BOOL := TRUE;                  (* 扫完循环重扫 [-] / Repeat sweep *)
    bEnable : BOOL := TRUE;                  (* 使能（撤除相位保持）[-] / Enable *)
    bRestart: BOOL := FALSE;                 (* 重启命令，上升沿回首段 [-] / Restart command *)
    bReset  : BOOL := FALSE;                 (* 复位命令，上升沿清故障与相位 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fFreq   : REAL;                          (* 当前瞬时频率出口 [Hz] / Instantaneous frequency outlet *)
    fPhase  : REAL;                          (* 相位累计出口（撤使能保持）[rad] / Phase accumulator outlet *)
    bSweepDone: BOOL;                        (* 单遍扫完脉冲（单拍）[-] / Sweep done pulse *)
    nSegIdx : INT;                           (* 当前段序号 [段] / Current segment index *)
    eState  : E_DL_SwpState;                 (* 状态出口 / State outlet *)
    eCause  : E_DL_SwpCause;                 (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError  : BOOL;                          (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_SwpState := E_DL_SwpState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_SwpCause := E_DL_SwpCause.eNone;  (* 故障成因锁存量 / Latched cause *)
    rtRestart: R_TRIG;                       (* 重启沿实例，段 0 无条件调用 / Restart edge instance *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bDoneI : BOOL;                          (* 扫完脉冲内部量（统一出口映射，R187） / Done pulse internal *)
    _bFinI  : BOOL;                          (* 派生频率有限性当拍量（边界⑤） / Derived frequency finiteness *)
    _nStepsE: INT;                           (* 钳位后生效段数 [段] / Effective step count *)
    _nSegI  : INT;                           (* 内部当前段序号 [段] / Internal segment index *)
    _fDtSec : REAL;                          (* 扫描周期秒值，域 > eps [s] / Scan period seconds *)
    _fDwellS: REAL;                          (* 当前段驻留秒值（钳位后）[s] / Current dwell seconds *)
    _fTacc  : REAL;                          (* 段内驻留计时累加量 [s] / Dwell time accumulator *)
    _fFreqI : REAL;                          (* 内部瞬时频率中间量 [Hz] / Internal frequency *)
    _fPhaseI: REAL;                          (* 内部相位累计量 [rad] / Internal phase *)
    _fRatio : REAL;                          (* 对数模式频比中间量（恒正）[-] / Log mode ratio *)
    _fWrap  : INT;                           (* 相位回卷守卫计数（防死循环）[次] / Phase wrap guard *)
    _i      : INT;                           (* 驻留表下标中间量 [段] / Dwell table index *)
END_VAR
VAR CONSTANT
    DL_SWP_NMIN  : INT   := 2;               (* 段数下限（边界①域闸配套）[段] / Step count lower bound *)
    DL_SWP_NMAX  : INT   := 32;              (* 段数上限 [段] / Step count upper bound *)
    DL_SWP_EPS   : REAL  := 1.0E-6;          (* 判零容差 [-] / Epsilon *)
    DL_SWP_2PI   : REAL  := 6.2831853;       (* 相位回卷阈（2π 常量）[rad] / Phase wrap threshold *)
    DL_SWP_WRAPMAX: INT  := 64;              (* 相位回卷循环守卫上限（防死循环，边界③）[次] / Wrap loop guard *)
    DL_SWP_TDWMIN: REAL  := 0.01;            (* 最小驻留秒值（非正驻留钳位，边界⑤）[s] / Min dwell seconds *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tScan) / 1000.0;                (* 扫描周期秒化（除子常量 1000） / Scan period seconds *)
_bCfgBad := (fStart <= DL_SWP_EPS) OR (fEnd <= DL_SWP_EPS)              (* 起止频率正域闸（边界①②） / Frequency positive gates *)
            OR (ABS(fStart - fEnd) < DL_SWP_EPS)                        (* 起止相等拒绝（退化点频不立，边界①） / Equal rejected *)
            OR (nSteps < DL_SWP_NMIN) OR (nSteps > DL_SWP_NMAX)         (* 段数域闸 / Step count gate *)
            OR NOT (tScan > T#0S);                                      (* 扫描周期正域闸 / Scan period gate *)
rtRestart(CLK := bRestart);                              (* 重启沿每拍必调 / Restart edge every scan *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_nStepsE := nSteps;                                      (* 生效段数初值 / Effective steps init *)
IF _nStepsE < DL_SWP_NMIN THEN
    _nStepsE := DL_SWP_NMIN;                             (* 段数下限钳位 / Steps lower clamp *)
END_IF
IF _nStepsE > DL_SWP_NMAX THEN
    _nStepsE := DL_SWP_NMAX;                             (* 段数上限钳位 / Steps upper clamp *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_bDoneI := FALSE;                                        (* 扫完脉冲内部量预清 / Done preset *)
bSweepDone := FALSE;                                     (* 扫完脉冲出口预清 / Done outlet preset *)
_fFreqI := fFreq;                                        (* 频率中间量保持上拍（非有限拍冻结语义，边界⑤） / Frequency hold default *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清相位与段序 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_SwpCause.eNone;                      (* 清成因 / Clear cause *)
    _fPhaseI := 0.0;                                     (* 清相位累计 / Clear phase *)
    _nSegI := 1;                                         (* 段序回首段 / Segment to first *)
    _fTacc := 0.0;                                       (* 清驻留计时 / Clear dwell timer *)
    fFreq := 0.0;                                        (* 清频率出口 / Clear frequency outlet *)
    fPhase := 0.0;                                       (* 清相位出口 / Clear phase outlet *)
    _eState := E_DL_SwpState.eIdle;                      (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_SwpCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_SwpState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_SwpState.eIdle:                                 (* 未使能：相位保持不归零（边界④），频率出口确定 0 / Idle *)
        fFreq := 0.0;                                    (* 失能频率出口确定值 / Disabled frequency zero *)
        IF bEnable AND NOT _bFault THEN
            _nSegI := 1;                                 (* 迁入拍段序回首段 / Segment to first *)
            _fTacc := 0.0;                               (* 驻留计时归零 / Dwell timer zero *)
            _eState := E_DL_SwpState.eRun;               (* 进入扫频相 / Enter sweeping *)
        END_IF
    E_DL_SwpState.eRun:                                  (* 扫频相：段推进 + 相位积分 / Sweeping *)
        IF NOT bEnable THEN
            _eState := E_DL_SwpState.eIdle;              (* 失能回未使能（相位保持） / Back to idle *)
        ELSE
            IF rtRestart.Q THEN
                _nSegI := 1;                             (* 显式重启回首段（边界④） / Explicit restart *)
                _fTacc := 0.0;                           (* 驻留计时归零 / Dwell timer zero *)
                _fPhaseI := 0.0;                         (* 重启相位归零 / Phase zero *)
            END_IF
            _i := _nSegI;                                (* 驻留表下标中间量 / Dwell index *)
            IF _i < 1 THEN
                _i := 1;                                 (* 下标下钳（防越界读，边界⑤） / Index lower clamp *)
            END_IF
            IF _i > DL_SWP_NMAX THEN
                _i := DL_SWP_NMAX;                       (* 下标上钳（防越界读，边界⑤） / Index upper clamp *)
            END_IF
            _fDwellS := TIME_TO_LREAL(aDwell[_i]) / 1000.0;   (* 驻留秒化（除子常量 1000） / Dwell seconds *)
            IF _fDwellS < DL_SWP_TDWMIN THEN
                _fDwellS := DL_SWP_TDWMIN;               (* 非正/过小驻留钳最小值（边界⑤） / Dwell clamp *)
            END_IF
            IF _fDtSec > DL_SWP_EPS THEN                 (* 周期秒值有效才推进（防除零/防零步进） / Period gate *)
                IF eMode = E_DL_SwpMode.eLog THEN
                    _fRatio := fEnd / fStart;            (* 对数频比（分子分母均过正域闸，边界②） / Log ratio *)
                    _fFreqI := fStart * EXP(LN(_fRatio) * INT_TO_REAL(_nSegI - 1) / INT_TO_REAL(_nStepsE - 1));   (* 几何步进频率（除子 = 段数-1 >= 1） / Geometric frequency *)
                ELSE
                    _fFreqI := fStart + (fEnd - fStart) * INT_TO_REAL(_nSegI - 1) / INT_TO_REAL(_nStepsE - 1);    (* 线性步进频率（除子 >= 1） / Linear frequency *)
                END_IF
                _bFinI := (_fFreqI = _fFreqI) AND ((_fFreqI - _fFreqI) = (_fFreqI - _fFreqI));   (* 派生频率有限性闸（边界⑤） / Derived finiteness gate *)
                IF _bFinI THEN
                    _fPhaseI := _fPhaseI + DL_SWP_2PI * _fFreqI * _fDtSec;   (* 相位逐拍积分防跳频突跳（边界③） / Phase integrate *)
                    _fWrap := 0;                         (* 回卷守卫计数清零 / Wrap guard clear *)
                    WHILE (_fPhaseI >= DL_SWP_2PI) AND (_fWrap < DL_SWP_WRAPMAX) DO   (* 条件减法回卷（禁取模，边界③） / Conditional wrap *)
                        _fPhaseI := _fPhaseI - DL_SWP_2PI;   (* 相位减 2π / Phase minus 2 pi *)
                        _fWrap := _fWrap + 1;            (* 守卫计数递进 / Guard advance *)
                    END_WHILE
                    fFreq := _fFreqI;                    (* 频率出口（有限拍派生） / Frequency outlet *)
                    fPhase := _fPhaseI;                  (* 相位出口 / Phase outlet *)
                    _fTacc := _fTacc + _fDtSec;          (* 段内驻留计时累加 / Dwell timer advance *)
                    IF _fTacc >= _fDwellS THEN           (* 驻留满迁下一段 / Dwell elapsed *)
                        _fTacc := 0.0;                   (* 驻留计时重置（R227） / Dwell timer reset *)
                        _nSegI := _nSegI + 1;            (* 段序净额 +1 / Segment advance *)
                        IF _nSegI > _nStepsE THEN        (* 末段完成 / Last segment done *)
                            _bDoneI := TRUE;             (* 扫完脉冲内部置位（R187） / Done internal *)
                            IF bRepeat THEN
                                _nSegI := 1;             (* 循环重扫回首段 / Repeat to first *)
                            ELSE
                                _nSegI := _nStepsE;      (* 单遍模式停末段（频率保持） / Hold last segment *)
                            END_IF
                        END_IF
                    END_IF
                END_IF                                   (* 非有限拍：频率/相位冻结保持上拍（边界⑤） *)
            END_IF
            nSegIdx := _nSegI;                           (* 当前段序号出口 / Segment index outlet *)
        END_IF
    E_DL_SwpState.eFault:                                (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_SwpState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_SwpCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bSweepDone := _bDoneI;                                   (* 扫完脉冲单拍出口 / Done pulse outlet *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
