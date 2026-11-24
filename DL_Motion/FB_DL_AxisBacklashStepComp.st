(*
  Name        : FB_DL_AxisBacklashStepComp
  Category    : DL_Motion
  Version     : 1.0.1
  Purpose     : 轴反向间隙阶跃补偿：跟踪位置命令方向，方向切换拍一次性注入补偿行程（新方向补偿量累加到偏置），输出补偿后位置；/ Axis backlash step compensation: tracks command direction and injects the compensation travel as a one-shot step on each reversal by accumulating the offset into the commanded position
  溯源        : 借 t1-6-plcopen-motion 的分类/参数域组织，clean-room 实现
  Changelog   : v1.0.1 R54 非有限拍 fPosOut 直算 NaN 修复：出口计算移入有限分支，非有限拍保持上拍 fPosOut/fOffset 并置 bInvalid 当拍指示
  撞名说明    : 本件原名 FB_DL_AxisBacklashComp 与既有 R44 件（DL_Motion，换向沿 + 学习值注入 +
                速率爬升口径）撞名，为免 POU/枚举/常量三重重复定义，改名 FB_DL_AxisBacklashStepComp，
                枚举前缀 E_DL_AbsStep*、常量前缀 DL_ABS_ 全部隔离；分工：R44 件为速度指令口径的
                学习值爬升注入，本件为位置命令口径的方向切换拍阶跃注入。
  Boundary    : ① 组态闸：补偿量 < 0 → 锁存故障（0 = 关闭补偿，合法）；
                ② 方向判定：命令增量绝对值 > 判向阈才更新方向（死区防噪声反复触发注入）；
                ③ 注入只在方向切换当拍发生一次（沿语义），同向运行不重复注入；
                ④ 偏置饱和上限防 REAL 有效位耗尽（R28）；bCompPuls 单拍脉冲经内部 _b* 统一出口映射（R187）；
                ⑤ 非有限命令该拍不判向不注入（偏置与输出保持上拍值，防污染）；
                ⑥ 本件为映射层补偿，不替代驱动器内置补偿、不做安全限位（属主边界）。
*)
TYPE E_DL_AbsStepState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 补偿跟踪运行 / Compensating *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_AbsStepCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：补偿量为负 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisBacklashStepComp
VAR_INPUT
    fPosCmd  : REAL := 0.0;                  (* 位置命令输入 [mm] / Command position input *)
    fBacklash: REAL := 0.02;                 (* 反向间隙补偿量，域 >= 0（0 = 关闭补偿）[mm] / Backlash compensation, >= 0 *)
    bEnable  : BOOL := TRUE;                 (* 补偿使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清偏置与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fPosOut  : REAL;                         (* 补偿后位置输出 = 命令 + 偏置 [mm] / Compensated position output *)
    fOffset  : REAL;                         (* 当前累计偏置（镜像）[mm] / Current accumulated offset mirror *)
    bCompPuls: BOOL;                         (* 本拍发生方向切换注入（单拍脉冲）[-] / Injection this scan pulse *)
    nCompCnt : UDINT;                        (* 累计注入次数（诊断，饱和）[次] / Injection count, saturated *)
    bInvalid : BOOL;                         (* 命令非有限当拍指示（出口保持上拍值，v1.0.1）[-] / Non-finite command indicator *)
    eState   : E_DL_AbsStepState;            (* 状态出口 / State outlet *)
    eCause   : E_DL_AbsStepCause;            (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_AbsStepState := E_DL_AbsStepState.eIdle;    (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_AbsStepCause := E_DL_AbsStepCause.eNone;    (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFin    : BOOL;                         (* 位置命令有限性当拍量 / Command finiteness *)
    _bDirC   : BOOL;                         (* 方向切换注入内部单拍量（出口统一映射，R187） / Injection internal pulse *)
    _bBadI   : BOOL;                         (* 非有限命令当拍指示内部量（统一出口映射，R187，v1.0.1） / Invalid internal pulse *)
    _nDir    : INT := 0;                     (* 当前方向（+1 正 / -1 负 / 0 未定）[-] / Current direction *)
    _fPrev   : REAL;                         (* 上拍命令位置快照 [mm] / Previous command snapshot *)
    _fOffI   : REAL;                         (* 累计偏置内部量（fPosOut 的加数）[mm] / Accumulated offset internal *)
    _fDeltaI : REAL;                         (* 命令增量中间量 [mm] / Command delta intermediate *)
END_VAR
VAR CONSTANT
    DL_ABS_EPS    : REAL  := 1.0E-6;         (* 判零容差 [-] / Epsilon *)
    DL_ABS_DIRTH  : REAL  := 0.001;          (* 判向阈：增量绝对值超过此值才更新方向 [mm] / Direction threshold *)
    DL_ABS_OFFMAX : REAL  := 1.0E6;          (* 偏置饱和上限（防 REAL 有效位耗尽，R28）[mm] / Offset saturation cap *)
    DL_ABS_CNTMAX : UDINT := 4294967295;     (* 注入计数饱和上限（R28）[-] / Injection count cap *)
    DL_ABS_PLUS   : INT   := 1;              (* 正方向枚举值 [-] / Positive direction *)
    DL_ABS_MINUS  : INT   := -1;             (* 负方向枚举值 [-] / Negative direction *)
    DL_ABS_UNDEF  : INT   := 0;              (* 未定向值 [-] / Undefined direction *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fBacklash < 0.0);                                                 (* 补偿量非负闸（0 = 关闭补偿合法） / Backlash non-negative gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fPosCmd = fPosCmd) AND ((fPosCmd - fPosCmd) = (fPosCmd - fPosCmd));  (* 命令 NaN 自反 + Inf 差判闸 / Command NaN and Inf gate *)
_fDeltaI := 0.0;                                                               (* 增量中间量预置（非有限拍为 0 不判向） / Delta preset zero *)
IF _bFin AND (_eState = E_DL_AbsStepState.eRun) THEN
    _fDeltaI := fPosCmd - _fPrev;                                              (* 命令增量（运行相才派生）[mm] / Command delta in run phase *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_bDirC := FALSE;                                                               (* 注入脉冲内部量预清 / Injection preset *)
_bBadI := FALSE;                                                               (* 非有限指示内部量预清（v1.0.1） / Invalid preset *)
bCompPuls := FALSE;                                                            (* 注入脉冲出口预清 / Injection outlet preset *)
bInvalid := FALSE;                                                             (* 非有限指示出口预清（v1.0.1） / Invalid outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清偏置与方向 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_AbsStepCause.eNone;                                        (* 清成因 / Clear cause *)
    _fOffI := 0.0;                                                             (* 清偏置内部量 / Clear offset internal *)
    fOffset := 0.0;                                                            (* 清偏置镜像出口 / Clear offset mirror *)
    fPosOut := 0.0;                                                            (* 清位置输出出口 / Clear position outlet *)
    bInvalid := FALSE;                                                         (* 清非有限指示出口（v1.0.1） / Clear invalid outlet *)
    nCompCnt := 0;                                                             (* 清注入计数出口 / Clear injection count *)
    _nDir := DL_ABS_UNDEF;                                                     (* 方向回未定 / Direction undefined *)
    _fPrev := 0.0;                                                             (* 清上拍快照 / Clear previous snapshot *)
    _eState := E_DL_AbsStepState.eIdle;                                        (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_AbsStepCause.eCfgIllegal;                                  (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_AbsStepState.eFault;                                       (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_AbsStepState.eIdle:                                                   (* 未使能：出口确定值 / Disabled *)
        fPosOut := 0.0;                                                        (* 失能清位置输出出口 / Clear position outlet *)
        fOffset := 0.0;                                                        (* 失能清偏置镜像出口 / Clear offset mirror *)
        bCompPuls := FALSE;                                                    (* 失能清注入脉冲出口 / Clear injection outlet *)
        _fOffI := 0.0;                                                         (* 失能清偏置内部量（防隐性回夹） / Clear offset internal *)
        _nDir := DL_ABS_UNDEF;                                                 (* 失能方向回未定（重使能重新定向） / Direction undefined *)
        IF bEnable AND NOT _bFault THEN
            _fPrev := fPosCmd;                                                 (* 迁入拍取命令首快照（首次增量不误判向） / Command snapshot at entry *)
            _eState := E_DL_AbsStepState.eRun;                                 (* 使能进入补偿 / Enter compensating *)
        END_IF
    E_DL_AbsStepState.eRun:                                                    (* 补偿相：判向 + 切换拍注入 / Compensating *)
        IF NOT bEnable THEN
            _eState := E_DL_AbsStepState.eIdle;                                (* 失能回未使能 / Back to idle *)
        ELSE
            IF _bFin THEN
                IF ABS(_fDeltaI) > DL_ABS_DIRTH THEN                           (* 增量超判向阈才更新方向（死区防噪声，边界②） / Direction update above threshold *)
                    IF _fDeltaI > 0.0 THEN
                        IF _nDir = DL_ABS_MINUS THEN                           (* 负 → 正方向切换：注入正补偿 / Reversal to positive *)
                            _bDirC := TRUE;                                    (* 注入脉冲内部置位（R187） / Injection internal *)
                            IF _fOffI < DL_ABS_OFFMAX THEN
                                _fOffI := _fOffI + fBacklash;                  (* 偏置累加补偿量（饱和防有效位耗尽） / Offset accumulate, capped *)
                            END_IF
                            IF nCompCnt < DL_ABS_CNTMAX THEN
                                nCompCnt := nCompCnt + 1;                      (* 注入计数净额 +1（饱和） / Net +1, saturated *)
                            END_IF
                        END_IF
                        _nDir := DL_ABS_PLUS;                                  (* 更新为正方向 / Set positive *)
                    ELSIF _fDeltaI < 0.0 THEN
                        IF _nDir = DL_ABS_PLUS THEN                            (* 正 → 负方向切换：注入负补偿 / Reversal to negative *)
                            _bDirC := TRUE;                                    (* 注入脉冲内部置位（R187） / Injection internal *)
                            IF _fOffI > -DL_ABS_OFFMAX THEN
                                _fOffI := _fOffI - fBacklash;                  (* 偏置累减补偿量（对称饱和） / Offset accumulate negative, capped *)
                            END_IF
                            IF nCompCnt < DL_ABS_CNTMAX THEN
                                nCompCnt := nCompCnt + 1;                      (* 注入计数净额 +1（饱和） / Net +1, saturated *)
                            END_IF
                        END_IF
                        _nDir := DL_ABS_MINUS;                                 (* 更新为负方向 / Set negative *)
                    END_IF
                END_IF
                _fPrev := fPosCmd;                                             (* 每拍刷新命令快照（有限拍才刷） / Refresh snapshot on finite scan *)
                fOffset := _fOffI;                                             (* 偏置镜像出口（有限拍才派生，v1.0.1 移入） / Offset mirror outlet *)
                fPosOut := fPosCmd + _fOffI;                                   (* 补偿后位置输出（有限拍才派生，v1.0.1 修复 NaN 穿透） / Compensated output *)
            ELSE
                _bBadI := TRUE;                                                (* 非有限拍：置失效指示内部量（R187，v1.0.1） / Invalid internal *)
            END_IF                                                             (* 非有限拍：不判向不注入，fPosOut/fOffset 保持上拍值（边界⑤） *)
        END_IF
    E_DL_AbsStepState.eFault:                                                  (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_AbsStepState.eFault;                                   (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_AbsStepCause.ePhaseBad;                                (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bCompPuls := _bDirC;                                                           (* 注入脉冲单拍出口 / Injection single-scan outlet *)
bInvalid := _bBadI;                                                            (* 非有限指示单拍出口（v1.0.1） / Invalid single-scan outlet *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
