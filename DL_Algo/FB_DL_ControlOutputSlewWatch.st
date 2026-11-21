(*
  Name        : FB_DL_ControlOutputSlewWatch
  Category    : DL_Algo
  Version     : 1.0.1
  Purpose     : 控制输出变化率监视：逐拍算输出速率（%/s），判超速（超 fSlewMax）、爬行（推动但速率低于 fSlewCreep）、振荡（窗口内速率符号翻转次数超阈），供回路诊断定性；/ Watch control output slew rate: detect over-speed, creeping and oscillation via sign-flip count within a time-ordered window
  Changelog   : v1.0.1 R52 五抽终审修复首拍 _nHead=0 越界写（段1 域外自愈）
  Fix R54     : _nHead/_nFill 声明初值补齐（R52 五抽严重项），运行时自愈保留作双保险
  溯源        : 借 t2-1-lgf·measurement 的分类/参数域组织，clean-room 实现
  Boundary    : ① 扫描周期闸：tScan <= T#0S → 锁存故障（速率除零前置）；
                ② 符号翻转统计按时间序环回遍历（_nOldest→_nIdx，R52 环窗时间序范式），不做下标序直读；
                ③ 死区判据：|速率| <= eps 视为无方向（不参与符号翻转计数，防噪声刷计数）；
                ④ 窗口深度钳位 4..32，翻转阈 = 窗深 / 2（整数直比，无浮点）；
                ⑤ 全部判据为观测级，不写输出侧（属主边界：本件不动控制量）。
*)
TYPE E_DL_CswState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 监视运行 / Watching *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_CswCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：周期/速率阈值/窗深越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ControlOutputSlewWatch
VAR_INPUT
    fOut       : REAL := 0.0;                (* 被监视控制输出（阀位/频率给定）[%] / Monitored control output *)
    tScan      : TIME := T#10MS;             (* 采样周期（速率除子），域 > T#0S [ms] / Sampling period, > 0 *)
    fSlewMax   : REAL := 50.0;               (* 允许速率上限，域 > 0 [%/s] / Allowed slew limit, > 0 *)
    fSlewCreep : REAL := 0.5;                (* 爬行判定下限（有效但过慢），域 0 < x < fSlewMax [%/s] / Creep lower limit *)
    nWinLen    : INT := 16;                  (* 符号翻转统计窗深，域 4..32 [点] / Flip window depth *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清窗口与全部标志 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fSlew      : REAL;                       (* 本拍输出速率 [%/s] / Output slew this scan *)
    fSlewPeak  : REAL;                       (* 窗口内 |速率| 峰值 [%/s] / Window peak absolute slew *)
    nFlips     : INT;                        (* 窗口内速率符号翻转次数 [-] / Sign flips within window *)
    bSlewHigh  : BOOL;                       (* 超速判据 [-] / Over-speed verdict *)
    bCreep     : BOOL;                       (* 爬行判据 [-] / Creeping verdict *)
    bOscillate : BOOL;                       (* 振荡判据（翻转次数超半窗）[-] / Oscillation verdict *)
    eState     : E_DL_CswState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_CswCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_CswState := E_DL_CswState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_CswCause := E_DL_CswCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bInit   : BOOL;                         (* 前值初始化标志（首拍速率按 0） / First-scan init *)
    _fPrev   : REAL;                         (* 上拍输出快照 [%] / Previous output snapshot *)
    _fDtSec  : REAL;                         (* 周期折算秒值，域 > eps [s] / Period in seconds *)
    _fPeak   : REAL;                         (* 窗口峰值累加量 [%/s] / Peak accumulator *)
    _aSign   : ARRAY[1..32] OF INT;          (* 速率符号环窗（-1/0/+1）[-] / Slew sign ring window *)
    _nHead   : INT := 1;                     (* 环形写入头游标（声明期安全初值，R194）[-] / Ring head cursor, declared init *)
    _nFill   : INT := 0;                     (* 窗口填充数（声明期安全初值，R194）[点] / Fill count, declared init *)
    _nEff    : INT;                          (* 钳位后生效窗深 [点] / Clamped depth *)
    _nOldest : INT;                          (* 最旧样本槽位（每趟重算）[-] / Oldest slot *)
    _nIdx    : INT;                          (* 时间序 → 环形槽位换算下标 [-] / Time-order to slot index *)
    _nJ      : INT;                          (* 时间序游标 0.._nFill-1 [-] / Time cursor *)
    _nFlip   : INT;                          (* 翻转计数累加量 [-] / Flip accumulator *)
    _nPrevSg : INT;                          (* 上一非零符号（时间序传播）[-] / Previous non-zero sign *)
    _nSg     : INT;                          (* 本点符号 [-] / Sign of current point *)
    _nFlipThr: INT;                          (* 翻转阈值 = 窗深 / 2 [-] / Flip threshold *)
END_VAR
VAR CONSTANT
    DL_CSW_EPS    : REAL := 1.0E-6;          (* 速率死区判零容差 [%/s] / Slew deadband epsilon *)
    DL_CSW_NMAX   : INT  := 32;              (* 窗深容量上限 [点] / Window capacity limit *)
    DL_CSW_NMIN   : INT  := 4;               (* 窗深下限 [点] / Window depth lower bound *)
    DL_CSW_SG_P   : INT  := 1;               (* 正符号编码 [-] / Positive sign code *)
    DL_CSW_SG_N   : INT  := -1;              (* 负符号编码 [-] / Negative sign code *)
    DL_CSW_SG_Z   : INT  := 0;               (* 零符号编码（无方向，不参与翻转）[-] / Zero sign code *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tScan) / 1000.0;                                      (* 周期秒化（除子常量 1000） / Period to seconds *)
_bCfgBad := NOT (tScan > T#0S)                                                 (* 周期正域闸 / Period gate *)
            OR (fSlewMax <= DL_CSW_EPS)                                        (* 速率上限正域闸 / Slew limit gate *)
            OR (fSlewCreep < 0.0) OR (fSlewCreep >= fSlewMax)                  (* 爬行下限域闸 0 <= x < max / Creep gate *)
            OR (nWinLen < DL_CSW_NMIN) OR (nWinLen > DL_CSW_NMAX);             (* 窗深域闸（也保证翻转统计有界） / Depth gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_nEff := nWinLen;                                                              (* 生效窗深初值 / Depth init *)
IF _nEff < DL_CSW_NMIN THEN
    _nEff := DL_CSW_NMIN;                                                      (* 下限钳位 / Lower clamp *)
END_IF
IF _nEff > DL_CSW_NMAX THEN
    _nEff := DL_CSW_NMAX;                                                      (* 上限钳位（R308） / Upper clamp *)
END_IF
IF _nEff < 2 THEN
    _nEff := 2;                                                                (* 兜底防除零（阈计算分母） / Fallback guard *)
END_IF
_nFlipThr := _nEff / 2;                                                        (* 翻转阈值（整数除，分母 >= 2） / Flip threshold *)

(* —— 段 1：单拍量预清零（R107） —— *)
bSlewHigh := FALSE;                                                            (* 超速判据预清 / Over-speed preset *)
bCreep := FALSE;                                                               (* 爬行判据预清 / Creep preset *)
bOscillate := FALSE;                                                           (* 振荡判据预清 / Oscillation preset *)
nFlips := 0;                                                                   (* 翻转数预清 / Flip count preset *)
fSlew := 0.0;                                                                  (* 速率预清（首拍/失能路径） / Slew preset *)
IF (_nHead < 1) OR (_nHead > _nEff) THEN
    _nHead := 1;                                                               (* 头游标域外自愈：首拍 0 与窗深缩小后回钳（v1.0.1） / Head self-heal *)
END_IF
IF _nFill > _nEff THEN
    _nFill := _nEff;                                                           (* 填充数随窗深回钳 / Fill clamped to depth *)
END_IF

(* —— 段 2：复位沿处理（作用域：清故障 + 清窗 + 清峰值 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CswCause.eNone;                                            (* 清成因 / Clear cause *)
    _nFill := 0;                                                               (* 清窗填充 / Clear fill *)
    _nHead := 1;                                                               (* 头游标复位 / Head reset *)
    _nOldest := 1;                                                             (* 最旧槽复位 / Oldest reset *)
    _fPeak := 0.0;                                                             (* 清峰值 / Clear peak *)
    _fPrev := 0.0;                                                             (* 清前值 / Clear previous *)
    _bInit := FALSE;                                                           (* 清初始化标志 / Clear init *)
    fSlewPeak := 0.0;                                                          (* 清峰值出口 / Clear peak outlet *)
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
    E_DL_CswState.eIdle:                                                       (* 未使能：不采集，出口保持 0 / Disabled *)
        _bInit := FALSE;                                                       (* 失能清初始化（重使能重新对齐） / Clear init *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_CswState.eRun;                                     (* 使能进入监视 / Enter watching *)
        END_IF
    E_DL_CswState.eRun:                                                        (* 监视相：速率 + 符号窗 + 三判据 / Watching *)
        IF NOT bEnable THEN
            _eState := E_DL_CswState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF (_fDtSec > DL_CSW_EPS) THEN
            IF NOT _bInit THEN
                _fPrev := fOut;                                                (* 首拍对齐：速率按 0，不产虚假尖峰 / First-scan alignment *)
                _bInit := TRUE;                                                (* 立初始化标志 / Set init *)
            END_IF
            fSlew := (fOut - _fPrev) / _fDtSec;                                (* 输出速率：除子已过闸 [%/s] / Slew, divisor gated *)
            _fPrev := fOut;                                                    (* 快照推进 / Advance snapshot *)
            IF fSlew > DL_CSW_EPS THEN
                _nSg := DL_CSW_SG_P;                                           (* 正方向 / Rising *)
            ELSIF fSlew < (-DL_CSW_EPS) THEN
                _nSg := DL_CSW_SG_N;                                           (* 负方向 / Falling *)
            ELSE
                _nSg := DL_CSW_SG_Z;                                           (* 带内：无方向（不参与翻转） / Deadband: no direction *)
            END_IF
            _aSign[_nHead] := _nSg;                                            (* 符号入环窗（下标已 1.._nEff 钳位） / Sign into ring *)
            _nHead := _nHead + 1;                                              (* 头游标递进 / Head advance *)
            IF _nHead > _nEff THEN
                _nHead := 1;                                                   (* 环回卷 / Ring wrap *)
            END_IF
            IF _nFill < _nEff THEN
                _nFill := _nFill + 1;                                          (* 填充封顶 / Fill cap *)
            END_IF
            IF _nFill >= 1 THEN
                _nOldest := _nHead - _nFill;                                   (* 最旧槽：未满窗 = 1 / Oldest while filling *)
                IF _nOldest < 1 THEN
                    _nOldest := _nOldest + _nEff;                              (* 满窗回卷：最旧在 _nHead 槽（R52 时间序） / Wrapped oldest *)
                END_IF
            END_IF
            _nFlip := 0;                                                       (* 翻转计数每趟重置（R227） / Flips reset per pass *)
            _nPrevSg := DL_CSW_SG_Z;                                           (* 前符号预置为零（时间序起点） / Previous sign preset *)
            _fPeak := 0.0;                                                     (* 峰值每趟重算 / Peak recompute *)
            _nJ := 0;                                                          (* 时间序游标起头 / Time cursor reset *)
            WHILE _nJ < _nFill DO                                              (* 按时间序环回遍历（R52 范式） / Time-ordered ring walk *)
                _nIdx := _nOldest + _nJ;                                       (* 时间序 → 槽位映射 / Time order to slot *)
                IF _nIdx > _nEff THEN
                    _nIdx := _nIdx - _nEff;                                    (* 槽位环回 / Slot wrap *)
                END_IF
                _nSg := _aSign[_nIdx];                                         (* 该点符号 / Sign of point *)
                IF _nSg <> DL_CSW_SG_Z THEN
                    IF (_nPrevSg <> DL_CSW_SG_Z) AND (_nSg <> _nPrevSg) THEN
                        _nFlip := _nFlip + 1;                                  (* 非零符号相反：计一次翻转 / Opposite non-zero signs *)
                    END_IF
                    _nPrevSg := _nSg;                                          (* 有效符号向前传播 / Propagate last valid sign *)
                END_IF
                _nJ := _nJ + 1;                                                (* 游标递进 / Cursor advance *)
            END_WHILE
            nFlips := _nFlip;                                                  (* 翻转数出口 / Flip outlet *)
            IF ABS(fSlew) > _fPeak THEN
                _fPeak := ABS(fSlew);                                          (* 本拍更新窗口 |速率| 峰值 / Update peak *)
            END_IF
            fSlewPeak := _fPeak;                                               (* 峰值出口 / Peak outlet *)
            IF ABS(fSlew) > fSlewMax THEN
                bSlewHigh := TRUE;                                             (* 超速判据（ABS 差比较，禁单侧） / Over-speed verdict *)
            END_IF
            IF (ABS(fSlew) > DL_CSW_EPS) AND (ABS(fSlew) < fSlewCreep) THEN
                bCreep := TRUE;                                                (* 爬行判据：动了但过慢 / Creeping verdict *)
            END_IF
            IF _nFlip >= _nFlipThr THEN
                bOscillate := TRUE;                                            (* 振荡判据：翻转过半窗 / Oscillation verdict *)
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
