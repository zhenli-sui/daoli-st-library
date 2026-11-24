(*
  Name        : FB_DL_CamTableLiveTrim
  Category    : DL_Motion
  Version     : 1.0.0
  Purpose     : 凸轮表运行中动态修调：指定相位点修调请求经斜坡平滑注入运行表，每次写表随改随验单调性，破坏即回滚本点锁故障；/ Live cam table trim: point trim request ramped smoothly into the running table, monotonicity verified on every write with instant rollback of the point on violation
  溯源        : 借 plcopen-motion 的凸轮动态修调待挖组织，clean-room 实现
  Boundary    : ① 修调注入只允许运行相且主轴相位在目标点 ± 容差窗内（相位闸，容差域 > 0）；
                ② 修调后表值单调性随改随验，破坏单调立即回滚本点至基线快照并锁存故障至复位沿；
                ③ 修调量饱和上限（绝对值钳位）防累计漂移，饱和上限域 > 0；
                ④ 斜坡平滑步长 = 斜坡率 × 周期秒值；非有限修调请求/主轴位置该拍不注入（保持上拍）；
                ⑤ 表经输入输出引用参数注入，内部零表副本（仅存单点基线快照，防两份表失同步）；
                ⑥ 表点数域 2..16，修调点序号越域直接拒绝申请（不置故障，属申请级）。
*)
TYPE E_DL_CltState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 修调待触发/斜坡注入运行 / Trim running *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_CltCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：点数/容差/斜率/饱和域越界 / Illegal config *)
    eMonotonic:= 2,                         (* 单调性破坏（回滚 + 锁存，边界②） / Monotonicity violated *)
    ePhaseBad := 3                          (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CamTableLiveTrim
VAR_INPUT
    fMasterPos: REAL := 0.0;                (* 主轴相位当前位置 [度] / Master phase position *)
    fMasterSpan: REAL := 360.0;             (* 主轴相位量程，域 > 0 [度] / Master span *)
    nPts     : INT := 16;                   (* 表点数，域 2..16 [点] / Table point count *)
    nIdx     : INT := 1;                    (* 修调目标点序号（1 基）[点] / Trim target point index *)
    fTrim    : REAL := 0.0;                 (* 修调请求量（正 = 增大表值）[表值单位] / Trim request amount *)
    fTrimMax : REAL := 1.0;                 (* 单点修调饱和上限，域 > 0 [表值单位] / Trim saturation cap *)
    fRampRate: REAL := 10.0;                (* 斜坡注入率，域 > 0 [表值单位/s] / Ramp rate *)
    fTol     : REAL := 1.0;                 (* 相位闸容差，域 > 0 [度] / Phase gate tolerance *)
    tScan    : TIME := T#10MS;              (* 扫描周期，域 > T#0S [ms] / Scan period *)
    bApply   : BOOL := FALSE;               (* 修调申请，上升沿受理 [-] / Apply request *)
    bEnable  : BOOL := TRUE;                (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;               (* 复位命令，上升沿清故障 [-] / Reset command *)
END_VAR
VAR_IN_OUT
    aTable   : ARRAY[1..16] OF REAL;        (* 凸轮表（从动值，零内部副本，边界⑤） / Cam table by reference *)
END_VAR
VAR_OUTPUT
    fApplied : REAL;                        (* 当前已注入修调量（镜像）[表值单位] / Applied trim mirror *)
    bTrimDone: BOOL;                        (* 本拍修调注入完成（单拍脉冲）[-] / Trim done pulse *)
    eState   : E_DL_CltState;               (* 状态出口 / State outlet *)
    eCause   : E_DL_CltCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError   : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_CltState := E_DL_CltState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_CltCause := E_DL_CltCause.eNone;  (* 故障成因锁存量 / Latched cause *)
    rtApply : R_TRIG;                       (* 申请沿实例，段 0 无条件调用 / Apply edge instance *)
    rtReset : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                         (* 主轴相位/修调量有限性当拍量（边界④） / Inputs finiteness *)
    _bDoneI : BOOL;                         (* 完成脉冲内部量（统一出口映射，R187） / Done pulse internal *)
    _bInj   : BOOL;                         (* 斜坡注入进行中标志 / Ramping flag *)
    _nIdxE  : INT;                          (* 受理后生效点序号 [点] / Effective index *)
    _fTarget: REAL;                         (* 饱和钳位后修调目标量 [表值单位] / Clamped trim target *)
    _fApplI : REAL;                         (* 已注入量内部量 [表值单位] / Applied internal *)
    _fBase  : REAL;                         (* 注入起始拍该点基线快照 [表值单位] / Point baseline snapshot *)
    _fStep  : REAL;                         (* 本拍斜坡步长 [表值单位] / Ramp step this scan *)
    _fNew   : REAL;                         (* 本拍写表候选值 [表值单位] / Candidate table value *)
    _fPtPos : REAL;                         (* 目标点主轴相位位置 [度] / Target point master position *)
    _fDtSec : REAL;                         (* 扫描周期秒值，域 > eps [s] / Scan period seconds *)
    _nLo    : INT;                          (* 左邻点序号（单调验证）[点] / Left neighbor index *)
    _nHi    : INT;                          (* 右邻点序号（单调验证）[点] / Right neighbor index *)
END_VAR
VAR CONSTANT
    DL_CLT_NMIN : INT   := 2;               (* 表点数下限（边界⑥）[点] / Point count lower bound *)
    DL_CLT_NMAX : INT   := 16;              (* 表点数上限（数组容量）[点] / Point count upper bound *)
    DL_CLT_EPS  : REAL  := 1.0E-6;          (* 判零容差 [-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tScan) / 1000.0;                (* 扫描周期秒化（除子常量 1000） / Scan period seconds *)
_bCfgBad := (nPts < DL_CLT_NMIN) OR (nPts > DL_CLT_NMAX) (* 点数域闸（边界⑥） / Point count gate *)
            OR (fTrimMax <= DL_CLT_EPS)                  (* 饱和上限正域闸（边界③） / Saturation gate *)
            OR (fRampRate <= DL_CLT_EPS)                 (* 斜坡率正域闸（边界④） / Ramp rate gate *)
            OR (fTol <= DL_CLT_EPS)                      (* 容差正域闸（边界①） / Tolerance gate *)
            OR (fMasterSpan <= DL_CLT_EPS)               (* 量程正域闸 / Span gate *)
            OR NOT (tScan > T#0S);                       (* 周期正域闸 / Period gate *)
rtApply(CLK := bApply);                                  (* 申请沿每拍必调 / Apply edge every scan *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fMasterPos = fMasterPos) AND ((fMasterPos - fMasterPos) = (fMasterPos - fMasterPos))   (* 主轴相位 NaN 自反 + Inf 差判闸（边界④） / Master pos NaN and Inf gate *)
         AND (fTrim = fTrim) AND ((fTrim - fTrim) = (fTrim - fTrim));   (* 修调量 NaN 自反 + Inf 差判闸 / Trim NaN and Inf gate *)
_fStep := fRampRate * _fDtSec;                           (* 斜坡步长 = 率 × 周期秒值（边界④） / Ramp step *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bDoneI := FALSE;                                        (* 完成脉冲内部量预清 / Done preset *)
bTrimDone := FALSE;                                      (* 完成脉冲出口预清 / Done outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清注入状态 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CltCause.eNone;                      (* 清成因 / Clear cause *)
    _bInj := FALSE;                                      (* 清注入标志 / Clear ramping flag *)
    _fApplI := 0.0;                                      (* 清已注入量 / Clear applied *)
    fApplied := 0.0;                                     (* 清镜像出口 / Clear mirror *)
    _eState := E_DL_CltState.eIdle;                      (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_CltCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_CltState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_CltState.eIdle:                                 (* 未使能：出口确定值 / Idle *)
        fApplied := 0.0;                                 (* 失能镜像出口清零 / Disabled mirror zero *)
        bTrimDone := FALSE;                              (* 失能完成脉冲清零 / Disabled done pulse *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_CltState.eRun;               (* 进入修调运行相 / Enter running *)
        END_IF
    E_DL_CltState.eRun:                                  (* 运行相：申请受理 + 相位闸斜坡注入 / Running *)
        IF NOT bEnable THEN
            _eState := E_DL_CltState.eIdle;              (* 失能回未使能（注入中止保持现状） / Back to idle *)
        ELSE
            IF rtApply.Q AND NOT _bInj AND NOT _bFault AND _bFin THEN   (* 申请受理（非注入中 + 组态在域 + 有限） / Accept request *)
                IF (nIdx >= 1) AND (nIdx <= nPts) THEN   (* 点序号域内才受理（边界⑥，申请级拒绝） / Index gate *)
                    _nIdxE := nIdx;                      (* 受理生效序号 / Effective index *)
                    _fTarget := fTrim;                   (* 目标量初值 / Target init *)
                    IF _fTarget > fTrimMax THEN
                        _fTarget := fTrimMax;            (* 正向饱和钳位（边界③） / Positive saturation *)
                    END_IF
                    IF _fTarget < (-fTrimMax) THEN
                        _fTarget := (-fTrimMax);         (* 负向饱和钳位（对称，边界③） / Negative saturation *)
                    END_IF
                    _fBase := aTable[_nIdxE];            (* 注入前基线快照（回滚锚点，边界②⑤） / Baseline snapshot *)
                    _fApplI := 0.0;                      (* 已注入量清零 / Applied zero *)
                    _bInj := TRUE;                       (* 置注入进行标志 / Ramping set *)
                END_IF
            END_IF
            IF _bInj THEN                                (* 注入进行中：相位闸 + 斜坡写表 / Ramping *)
                _fPtPos := fMasterSpan * INT_TO_REAL(_nIdxE - 1) / INT_TO_REAL(nPts - 1);   (* 目标点主轴位置（除子 = 点数-1 >= 1） / Point position *)
                IF _bFin AND (ABS(fMasterPos - _fPtPos) <= fTol) THEN   (* 相位闸：点 ± 容差窗内（边界①） / Phase gate *)
                    IF ABS(_fTarget - _fApplI) <= _fStep THEN
                        _fApplI := _fTarget;             (* 步长内直达目标 / Reach target *)
                        _bDoneI := TRUE;                 (* 完成脉冲内部置位（R187） / Done internal *)
                        _bInj := FALSE;                  (* 注入收口 / Ramping clear *)
                    ELSE
                        IF _fTarget > _fApplI THEN
                            _fApplI := _fApplI + _fStep; (* 正向斜坡步进 / Ramp up *)
                        ELSE
                            _fApplI := _fApplI - _fStep; (* 负向斜坡步进 / Ramp down *)
                        END_IF
                    END_IF
                    _fNew := _fBase + _fApplI;           (* 写表候选值 = 基线 + 已注入 / Candidate value *)
                    _nLo := _nIdxE - 1;                  (* 左邻序号 / Left neighbor *)
                    _nHi := _nIdxE + 1;                  (* 右邻序号 / Right neighbor *)
                    IF (_nLo >= 1) AND NOT (_fNew > aTable[_nLo] + DL_CLT_EPS) THEN   (* 左单调验证（容差直比） / Left monotonic check *)
                        aTable[_nIdxE] := _fBase;        (* 破坏单调回滚本点（边界②） / Rollback point *)
                        _bFault := TRUE;                 (* 锁存故障至复位沿 / Latch fault *)
                        _eCause := E_DL_CltCause.eMonotonic;   (* 成因：单调破坏 / Cause monotonic *)
                        _bInj := FALSE;                  (* 停止注入 / Stop ramping *)
                        _fApplI := 0.0;                  (* 已注入量清零 / Applied zero *)
                    ELSIF (_nHi <= nPts) AND NOT (_fNew < aTable[_nHi] - DL_CLT_EPS) THEN   (* 右单调验证 / Right monotonic check *)
                        aTable[_nIdxE] := _fBase;        (* 破坏单调回滚本点（边界②） / Rollback point *)
                        _bFault := TRUE;                 (* 锁存故障至复位沿 / Latch fault *)
                        _eCause := E_DL_CltCause.eMonotonic;   (* 成因：单调破坏 / Cause monotonic *)
                        _bInj := FALSE;                  (* 停止注入 / Stop ramping *)
                        _fApplI := 0.0;                  (* 已注入量清零 / Applied zero *)
                    ELSE
                        aTable[_nIdxE] := _fNew;         (* 单调保持：写表（随改随验） / Write table *)
                        fApplied := _fApplI;             (* 已注入量镜像出口 / Applied mirror *)
                    END_IF
                END_IF                                   (* 相位窗外：本拍不注入不写表（边界①④） *)
            END_IF
        END_IF
    E_DL_CltState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CltState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_CltCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bTrimDone := _bDoneI;                                    (* 完成脉冲单拍出口 / Done pulse outlet *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
