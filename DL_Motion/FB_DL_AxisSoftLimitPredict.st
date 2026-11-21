(*
  Name        : FB_DL_AxisSoftLimitPredict
  Category    : DL_Motion
  Version     : 1.0.0
  Purpose     : 软限位超程预测：按当前速度与最大减速度预算停车距离 s = v²/(2a)，与到限位余量比较，提前发出减速请求（预测式，非反应式拦截）；/ Predict soft-limit overtravel: budget the stopping distance s = v^2/(2a) from current velocity and maximum deceleration, compare with the remaining margin and raise a deceleration request in advance
  溯源        : 借 t2-4-s7-motion 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：最大减速度 <= eps / 余量 <= 0 / 上限须大于下限 / 扫描周期 <= 0 → 锁存故障；
                ② 除子闸：2a 在组态闸后使用（a > eps 已保证）；v² 为乘性无除法；
                ③ 仅对「朝限位运动」的方向预测：速度为 0 时不请求减速（无预测语义）；
                ④ 输出为「请求」，不直接写速度/位置（属主边界：执行由运动控制层完成）；
                ⑤ 所有比较用容差或直比，禁浮点等值比较。
*)
TYPE E_DL_AslpState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    ePred  := 10,                            (* 预测运行 / Predicting *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_AslpCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：减速度/余量/限位越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisSoftLimitPredict
VAR_INPUT
    fPosNow   : REAL := 0.0;                 (* 当前实际位置 [mm] / Current position *)
    fVelNow   : REAL := 0.0;                 (* 当前速度（带符号）[mm/s] / Current velocity, signed *)
    fDecMax   : REAL := 5000.0;              (* 最大可用减速度，域 > 0 [mm/s²] / Maximum deceleration, > 0 *)
    fLimPos   : REAL := 1000.0;              (* 正向软限位 [mm] / Positive soft limit *)
    fLimNeg   : REAL := -1000.0;             (* 负向软限位 [mm] / Negative soft limit *)
    fMargin   : REAL := 5.0;                 (* 提前量（在停车距离上附加），域 >= 0 [mm] / Lead margin, >= 0 *)
    bEnable   : BOOL := TRUE;                (* 预测使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清输出与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fStopDist : REAL;                        (* 停车距离预算 v²/(2a) [mm] / Budgeted stopping distance *)
    fDistPos  : REAL;                        (* 到正向限位的余量 [mm] / Remaining distance to positive limit *)
    fDistNeg  : REAL;                        (* 到负向限位的余量 [mm] / Remaining distance to negative limit *)
    bDecelReq : BOOL;                        (* 减速请求（预算 + 余量 >= 可用余量）[-] / Deceleration request *)
    bOvershoot: BOOL;                        (* 已判定越界（余量 <= 提前量）[-] / Already out of margin *)
    nDir      : INT;                         (* 运动方向：+1 正 / -1 负 / 0 停 [-] / Motion direction *)
    eState    : E_DL_AslpState;              (* 状态出口 / State outlet *)
    eCause    : E_DL_AslpCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_AslpState := E_DL_AslpState.eIdle;   (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_AslpCause := E_DL_AslpCause.eNone;   (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite : BOOL;                         (* 输入有限性当拍量 / Input finiteness *)
    _fStop   : REAL;                         (* 停车距离中间量 [mm] / Stopping distance intermediate *)
    _fNeed   : REAL;                         (* 预算 + 提前量（总需距）[mm] / Required distance *)
    _fAbsVel : REAL;                         (* 速度绝对値（距离预算用）[mm/s] / Absolute velocity *)
    _nDir    : INT;                          (* 方向判定中间量 [-] / Direction intermediate *)
    _fZero   : REAL;                         (* 实数零常量 [-] / Real zero constant *)
END_VAR
VAR CONSTANT
    DL_ASLP_EPS : REAL := 1.0E-6;            (* 判零容差（速度/减速度）[mm/s] / Epsilon *)
    DL_ASLP_TWO : REAL := 2.0;               (* 停车距离公式常量 2 [-] / Formula constant *)
    DL_ASLP_DIRP: INT  := 1;                 (* 正方向编码 [-] / Positive direction code *)
    DL_ASLP_DIRN: INT  := -1;                (* 负方向编码 [-] / Negative direction code *)
    DL_ASLP_DIR0: INT  := 0;                 (* 静止编码 [-] / Standstill code *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fDecMax <= DL_ASLP_EPS)                                           (* 减速度正域闸（除零前置） / Deceleration gate *)
            OR (fMargin < 0.0)                                                 (* 提前量非负闸 / Margin gate *)
            OR ((fLimPos - fLimNeg) <= DL_ASLP_EPS);                           (* 限位区间正域闸 / Limit span gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fPosNow = fPosNow) AND (fVelNow = fVelNow)                        (* NaN 自反闸 / NaN reflex gates *)
            AND ((fPosNow - fPosNow) = (fPosNow - fPosNow))                    (* 位置 Inf 闸 / Position Inf gate *)
            AND ((fVelNow - fVelNow) = (fVelNow - fVelNow));                   (* 速度 Inf 闸 / Velocity Inf gate *)
_fZero := 0.0;                                                                 (* 零常量装载 / Zero constant load *)

(* —— 段 1：单拍量预清零（R107） —— *)
bDecelReq := FALSE;                                                            (* 减速请求预清 / Request preset *)
bOvershoot := FALSE;                                                           (* 越界判据预清 / Overshoot preset *)
nDir := DL_ASLP_DIR0;                                                          (* 方向出口预清为静止 / Direction preset *)
fStopDist := 0.0;                                                              (* 停车距离预清 / Stop distance preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清输出 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_AslpCause.eNone;                                           (* 清成因 / Clear cause *)
    fStopDist := 0.0;                                                          (* 清距离预算出口 / Clear budget outlet *)
    fDistPos := 0.0;                                                           (* 清正向余量出口 / Clear positive margin *)
    fDistNeg := 0.0;                                                           (* 清负向余量出口 / Clear negative margin *)
    bDecelReq := FALSE;                                                        (* 清减速请求 / Clear request *)
    bOvershoot := FALSE;                                                       (* 清越界判据 / Clear overshoot *)
    nDir := DL_ASLP_DIR0;                                                      (* 方向回静止 / Direction to standstill *)
    _eState := E_DL_AslpState.eIdle;                                           (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_AslpCause.eCfgIllegal;                                     (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_AslpState.eFault;                                          (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_AslpState.eIdle:                                                      (* 未使能：不预测 / Disabled *)
        fDistPos := fLimPos - fPosNow;                                         (* 正向余量仍实时镜像（只读观测） / Positive margin mirror *)
        fDistNeg := fPosNow - fLimNeg;                                         (* 负向余量镜像 / Negative margin mirror *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_AslpState.ePred;                                   (* 使能进入预测 / Enter predicting *)
        END_IF
    E_DL_AslpState.ePred:                                                      (* 预测相：停车距离预算 + 双侧余量判据 / Predicting *)
        IF NOT bEnable THEN
            _eState := E_DL_AslpState.eIdle;                                   (* 失能回未使能 / Back to idle *)
        ELSIF _bFinite THEN
            fDistPos := fLimPos - fPosNow;                                     (* 到正向限位余量（可负 = 已越界）[mm] / Margin to positive limit *)
            fDistNeg := fPosNow - fLimNeg;                                     (* 到负向限位余量 [mm] / Margin to negative limit *)
            IF fVelNow > DL_ASLP_EPS THEN
                _nDir := DL_ASLP_DIRP;                                         (* 正方向运动 / Positive motion *)
            ELSIF fVelNow < (-DL_ASLP_EPS) THEN
                _nDir := DL_ASLP_DIRN;                                         (* 负方向运动 / Negative motion *)
            ELSE
                _nDir := DL_ASLP_DIR0;                                         (* 带内：按静止处理（不请求） / Deadband: standstill *)
            END_IF
            nDir := _nDir;                                                     (* 方向出口（名实同源，R191） / Direction outlet *)
            IF _nDir <> DL_ASLP_DIR0 THEN
                _fAbsVel := ABS(fVelNow);                                      (* 速度绝对値（距离与方向无关）[mm/s] / Absolute velocity *)
                _fStop := (_fAbsVel * _fAbsVel) / (DL_ASLP_TWO * fDecMax);     (* 停车距离 v²/(2a)：除子 2a > 0 已过闸 [mm] / Stopping distance *)
                fStopDist := _fStop;                                           (* 距离预算出口 / Budget outlet *)
                _fNeed := _fStop + fMargin;                                    (* 总需距 = 预算 + 提前量 [mm] / Required distance *)
                IF _nDir = DL_ASLP_DIRP THEN
                    IF fDistPos <= fMargin THEN
                        bOvershoot := TRUE;                                    (* 余量已不足提前量：实质越界 / Within margin: overshoot *)
                    END_IF
                    IF _fNeed >= fDistPos THEN
                        bDecelReq := TRUE;                                     (* 需距 >= 余量：提前请求减速 / Need >= margin: request *)
                    END_IF
                ELSE
                    IF fDistNeg <= fMargin THEN
                        bOvershoot := TRUE;                                    (* 负向余量不足 / Negative overshoot *)
                    END_IF
                    IF _fNeed >= fDistNeg THEN
                        bDecelReq := TRUE;                                     (* 负向请求减速 / Negative request *)
                    END_IF
                END_IF
            ELSE
                fStopDist := 0.0;                                              (* 静止：无停车距离预算 / Standstill: zero budget *)
            END_IF
        END_IF                                                                 (* 非有限输入：本拍不预测，保持输出 / Non-finite: hold *)
    E_DL_AslpState.eFault:                                                     (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_AslpState.eFault;                                      (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_AslpCause.ePhaseBad;                                   (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
