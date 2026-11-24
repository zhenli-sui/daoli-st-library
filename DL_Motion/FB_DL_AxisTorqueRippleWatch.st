(*
  Name        : FB_DL_AxisTorqueRippleWatch
  Category    : DL_Motion
  Version     : 1.0.0
  Purpose     : 轴转矩纹波监视：匀速段窗内峰峰值/均值占比与峰间隔规律性双判据，识别机械卡滞与联轴器异常；/ Axis torque ripple watch: peak-to-mean ripple ratio and peak-interval regularity in a steady-speed window to identify mechanical sticking and coupling anomalies
  溯源        : 借 plcopen-motion 的运动诊断组织，clean-room 实现
  Boundary    : ① 只在匀速段采样（|速度 - 速度命令| < 容差 且 速度 > 最低速），运动相位闸（容差/最低速域 > 0）；
                ② 波动幅度 = 窗内峰峰值 / 均值占比判据，均值近零时占比出口置 0 + bInvalid（除零前置）；
                ③ 周期性判据 = 峰间隔极差 < 阈（机械卡滞特征），需窗内 >= 3 个局部峰才判；
                ④ 非有限扭矩该拍不入窗（窗保持不滑动，防污染统计）；
                ⑤ 本件为诊断观测层，不干预轴指令输出（属主边界，零控制量引脚）；
                ⑥ 窗长 32 固定常量，窗内统计每趟全量重算防陈旧（R227）。
*)
TYPE E_DL_TrwState :
(
    eIdle  := 0,                             (* 未使能（窗清空） / Disabled, window cleared *)
    eRun   := 10,                            (* 纹波监视运行 / Watching *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_TrwCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：容差/最低速/阈值/周期越域 / Illegal config *)
    ePhaseBad  := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisTorqueRippleWatch
VAR_INPUT
    fTorque  : REAL := 0.0;                  (* 轴转矩反馈 [Nm] / Axis torque feedback *)
    fVel     : REAL := 0.0;                 (* 轴实际速度 [mm/s] / Actual velocity *)
    fVelCmd  : REAL := 0.0;                 (* 轴速度命令（匀速判据基准）[mm/s] / Velocity command *)
    fVelTol  : REAL := 5.0;                  (* 匀速判据容差，域 > 0 [mm/s] / Steady-speed tolerance *)
    fVelMin  : REAL := 10.0;                 (* 最低采样速度，域 > 0 [mm/s] / Minimum sampling speed *)
    fTqLimRip: REAL := 10.0;                 (* 纹波占比报警阈，域 > 0 [%] / Ripple ratio limit *)
    fGapSpreadMax: REAL := 0.05;             (* 峰间隔极差阈，域 > 0 [s] / Gap spread limit *)
    tSample  : TIME := T#10MS;               (* 采样周期，域 > T#0S [ms] / Sampling period *)
    bEnable  : BOOL := TRUE;                 (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清窗与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fRipplePct: REAL;                        (* 纹波占比出口 = 峰峰值 / |均值| × 100 [%] / Ripple ratio outlet *)
    bRippleHigh: BOOL;                       (* 纹波超阈判据出口 [-] / Ripple high verdict *)
    bPeriodic: BOOL;                         (* 周期性卡滞特征出口（>= 3 峰且间隔规律）[-] / Periodic sticking verdict *)
    bInvalid : BOOL;                         (* 本拍统计无效指示（均值近零/样本不足）[-] / Invalid indicator *)
    eState   : E_DL_TrwState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_TrwCause;                (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_TrwState := E_DL_TrwState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_TrwCause := E_DL_TrwCause.eNone;  (* 成因锁存量 / Latched cause *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                          (* 扭矩有限性当拍量（边界④） / Torque finiteness *)
    _bSteady: BOOL;                          (* 匀速段当拍判据（边界①） / Steady-speed verdict *)
    _aWin   : ARRAY[1..32] OF REAL;          (* 扭矩滑窗（线性平移式）[Nm] / Torque sliding window *)
    _nFill  : INT;                           (* 窗填充数 [点] / Window fill count *)
    _i      : INT;                           (* 窗扫描游标 [点] / Window scan cursor *)
    _fMean  : REAL;                          (* 窗均值中间量 [Nm] / Window mean *)
    _fPk    : REAL;                          (* 窗峰值中间量 [Nm] / Window peak *)
    _fTr    : REAL;                          (* 窗谷值中间量 [Nm] / Window trough *)
    _fSum   : REAL;                          (* 窗求和中间量 [Nm] / Window sum *)
    _nPkN   : INT;                           (* 本趟局部峰计数 [个] / Local peak count *)
    _nLastPk: INT;                           (* 上一峰样本序号（间隔派生）[点] / Last peak index *)
    _aGap   : ARRAY[1..4] OF REAL;           (* 最近峰间隔表（秒值）[s] / Recent peak gaps *)
    _nGapN  : INT;                           (* 已存间隔数 [个] / Stored gap count *)
    _fGapMax: REAL;                          (* 间隔极差上界中间量 [s] / Gap spread upper *)
    _fGapMin: REAL;                          (* 间隔极差下界中间量 [s] / Gap spread lower *)
    _fDtSec : REAL;                          (* 采样周期秒值，域 > eps [s] / Sampling period seconds *)
    _bPerI  : BOOL;                          (* 周期性判据内部量 / Periodic verdict internal *)
END_VAR
VAR CONSTANT
    DL_TRW_NMAX : INT   := 32;               (* 滑窗容量（固定常量，边界⑥）[点] / Window capacity *)
    DL_TRW_NMIN : INT   := 8;                (* 统计生效最少样本数（防小样本误判）[点] / Minimum samples *)
    DL_TRW_NPKMIN: INT  := 3;                (* 周期性判据最少峰数（边界③）[个] / Minimum peaks *)
    DL_TRW_EPS  : REAL  := 1.0E-6;           (* 判零容差 [-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tSample) / 1000.0;              (* 采样周期秒化（除子常量 1000） / Sampling period seconds *)
_bCfgBad := (fVelTol <= DL_TRW_EPS) OR (fVelMin <= DL_TRW_EPS)           (* 匀速容差/最低速正域闸（边界①） / Tolerance and speed gates *)
            OR (fTqLimRip <= DL_TRW_EPS) OR (fGapSpreadMax <= DL_TRW_EPS)   (* 报警阈正域闸（边界②③） / Verdict limit gates *)
            OR NOT (tSample > T#0S);                     (* 采样周期正域闸 / Sampling gate *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fTorque = fTorque) AND ((fTorque - fTorque) = (fTorque - fTorque));   (* 扭矩 NaN 自反 + Inf 差判闸（边界④） / Torque NaN and Inf gate *)
_bSteady := (ABS(fVel - fVelCmd) < fVelTol) AND (fVel > fVelMin);        (* 匀速段判据：速度差容差内且高于最低速（边界①） / Steady-speed verdict *)

(* —— 段 1：单拍量预清零（R107；出口在段 4 每趟重算前预置确定值） —— *)
fRipplePct := 0.0;                                       (* 占比出口预清（无效拍默认 0） / Ripple preset zero *)
bRippleHigh := FALSE;                                    (* 超阈出口预清 / High preset *)
bPeriodic := FALSE;                                      (* 周期性出口预清 / Periodic preset *)
bInvalid := FALSE;                                       (* 无效指示预清 / Invalid preset *)
_bPerI := FALSE;                                         (* 周期性内部量预清（R227） / Periodic internal clear *)
_nPkN := 0;                                              (* 峰计数每趟重置 / Peak count reset *)
_nLastPk := 0;                                           (* 峰序号快照重置 / Peak index reset *)
_nGapN := 0;                                             (* 间隔表计数每趟重算 / Gap count reset *)
_fGapMax := 0.0;                                         (* 极差上界重置 / Spread upper reset *)
_fGapMin := 0.0;                                         (* 极差下界重置 / Spread lower reset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清窗 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_TrwCause.eNone;                      (* 清成因 / Clear cause *)
    FOR _i := 1 TO DL_TRW_NMAX DO
        _aWin[_i] := 0.0;                                (* 清滑窗 / Clear window *)
    END_FOR
    FOR _i := 1 TO 4 DO
        _aGap[_i] := 0.0;                                (* 清间隔表 / Clear gap table *)
    END_FOR
    _nFill := 0;                                         (* 清窗填充数 / Clear fill *)
    fRipplePct := 0.0;                                   (* 清占比出口 / Clear ripple outlet *)
    _eState := E_DL_TrwState.eIdle;                      (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_TrwCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_TrwState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_TrwState.eIdle:                                 (* 未使能：窗清空出口确定值 / Idle *)
        FOR _i := 1 TO DL_TRW_NMAX DO
            _aWin[_i] := 0.0;                            (* 失能清滑窗 / Disabled clear window *)
        END_FOR
        _nFill := 0;                                     (* 失能清填充数 / Disabled clear fill *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_TrwState.eRun;               (* 进入监视相 / Enter watching *)
        END_IF
    E_DL_TrwState.eRun:                                  (* 监视相：匀速闸采样 + 全窗重算 / Watching *)
        IF NOT bEnable THEN
            _eState := E_DL_TrwState.eIdle;              (* 失能回未使能 / Back to idle *)
        ELSE
            IF _bSteady AND _bFin AND (_fDtSec > DL_TRW_EPS) THEN   (* 匀速闸 + 有限闸 + 周期闸（边界①④） / Sampling gates *)
                IF _nFill < DL_TRW_NMAX THEN
                    _nFill := _nFill + 1;                (* 填充数递进（写入点域内） / Fill advance *)
                    _aWin[_nFill] := fTorque;            (* 样本入窗 / Sample into window *)
                ELSE
                    FOR _i := 1 TO DL_TRW_NMAX - 1 DO
                        _aWin[_i] := _aWin[_i + 1];      (* 满窗线性平移（有界循环） / Shift window *)
                    END_FOR
                    _aWin[DL_TRW_NMAX] := fTorque;       (* 新样本入窗尾 / Sample into tail *)
                END_IF
            END_IF                                       (* 不满足闸：本拍不入窗（窗保持，边界①④） *)
            IF _nFill >= DL_TRW_NMIN THEN                (* 统计生效下限（防小样本误判） / Statistics gate *)
                _fSum := 0.0; _fPk := _aWin[1]; _fTr := _aWin[1];   (* 均值/峰谷初值（R227） / Init mean peak trough *)
                FOR _i := 1 TO _nFill DO
                    _fSum := _fSum + _aWin[_i];          (* 窗求和 / Window sum *)
                    IF _aWin[_i] > _fPk THEN
                        _fPk := _aWin[_i];               (* 窗峰值刷新 / Peak update *)
                    END_IF
                    IF _aWin[_i] < _fTr THEN
                        _fTr := _aWin[_i];               (* 窗谷值刷新 / Trough update *)
                    END_IF
                END_FOR
                _fMean := _fSum / INT_TO_REAL(_nFill);   (* 窗均值（除子 = 填充数 >= 8） / Window mean *)
                IF ABS(_fMean) > DL_TRW_EPS THEN
                    fRipplePct := (_fPk - _fTr) / ABS(_fMean) * 100.0;   (* 纹波占比（除子已过闸，边界②） / Ripple ratio *)
                    bRippleHigh := fRipplePct > fTqLimRip;   (* 占比超阈判据（直比阈值） / Ripple high verdict *)
                ELSE
                    fRipplePct := 0.0;                   (* 均值近零：占比出口 0（除零前置，边界②） / Zero ratio *)
                    bInvalid := TRUE;                    (* 无效指示 / Invalid indicator *)
                END_IF
                FOR _i := 2 TO _nFill - 1 DO             (* 局部峰检测（内点扫描，边界③） / Local peak scan *)
                    IF (_aWin[_i] > _aWin[_i - 1]) AND (_aWin[_i] > _aWin[_i + 1]) AND (_aWin[_i] > _fMean) THEN
                        _nPkN := _nPkN + 1;              (* 局部峰计数 / Peak count *)
                        IF _nLastPk >= 1 THEN
                            _nGapN := _nGapN + 1;        (* 间隔数净额 +1 / Gap count *)
                            IF _nGapN > 4 THEN
                                _aGap[1] := _aGap[2]; _aGap[2] := _aGap[3]; _aGap[3] := _aGap[4];   (* 间隔表平移 / Shift gaps *)
                                _nGapN := 4;             (* 间隔表封顶 / Gap cap *)
                            END_IF
                            _aGap[_nGapN] := INT_TO_REAL(_i - _nLastPk) * _fDtSec;   (* 间隔秒值入表 / Gap into table *)
                        END_IF
                        _nLastPk := _i;                  (* 峰序号快照 / Peak index snapshot *)
                    END_IF
                END_FOR
                IF _nGapN >= 2 THEN                      (* >= 3 峰（2 个间隔）才判（边界③） / Peak count gate *)
                    _fGapMax := _aGap[1]; _fGapMin := _aGap[1];   (* 极差初值 / Spread init *)
                    FOR _i := 2 TO _nGapN DO
                        IF _aGap[_i] > _fGapMax THEN
                            _fGapMax := _aGap[_i];       (* 间隔上界刷新 / Gap upper *)
                        END_IF
                        IF _aGap[_i] < _fGapMin THEN
                            _fGapMin := _aGap[_i];       (* 间隔下界刷新 / Gap lower *)
                        END_IF
                    END_FOR
                    _bPerI := (_fGapMax - _fGapMin) < fGapSpreadMax;   (* 间隔规律性判据（边界③） / Regularity verdict *)
                END_IF
                bPeriodic := _bPerI;                     (* 周期性出口 / Periodic outlet *)
            ELSE
                bInvalid := TRUE;                        (* 样本不足：统计无效（确定值） / Not enough samples *)
            END_IF
        END_IF
    E_DL_TrwState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_TrwState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_TrwCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
