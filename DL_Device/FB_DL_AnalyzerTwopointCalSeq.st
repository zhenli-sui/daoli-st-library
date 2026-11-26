(*==============================================================================
 * 组件 Component : FB_DL_AnalyzerTwopointCalSeq ｜ DL_Device ｜ v1.0.0 ｜ 2026-11-25
 * 功能 Function  : 水质分析仪两点标定状态机（pH/电位式电极通用）。
 *                 相序：eIdle 待机 → eZeroSettle 零液（pH 7.00）稳定判据
 *                 → eSpanSettle 标液（pH 4.00）稳定判据 → eCompute 斜率计算
 *                 → eWrite 斜率写回（域闸通过才写）→ eDone；
 *                 斜率越出接收带即走 eRollback（回滚到上一次有效斜率）并报码。
 * 边界 Boundary  : ① 稳定判据：连续 uStableCnt 拍内 |ΔmV| ≤ 0.1 mV（本文件常量），
 *                 uStableCnt=0 按 1 处理（防「零拍即稳定」的伪稳定）；
 *                 ② 同拍双窗配比约束：tZeroTmo = tSpanTmo = 120s（对称），
 *                 超时狗仅在对应相驻留时计时（R145 相驻留直驱，不叠业务补集）；
 *                 ③ 复位沿作用域三项：清锁存 / 清稳定计数与电压快照 / 迁 eIdle，
 *                 不动 _bInit；bStart 上升沿亦可重开一轮；
 *                 ④ 斜率接收带 −71.0 ~ −45.0 mV/pH（约 76%~120% 理论斜率），
 *                 越带即 eRollback：出口斜率回放上一次有效值，禁写入坏值；
 *                 ⑤ 出口 fSlopeMvPerPh 初值 = 0.0（未标定即 0，N3 安全侧），
 *                 上电不会被当作有效斜率下发。
 * 依赖 Depends   : 仅 IEC 61131-3 标准库（TON / R_TRIG / ABS）
 * 溯源 Origin    : DLF-D-WATERANA（R95 规划标签，内部原创线，无外部代码抄录）
 * 枚举归属      : E_DL_AnalyzerCalPhase 归属本文件（全库唯一属主，R264）
 * 码位分配      : 零 16# 段位范式；uErrId 常量 0 无 / 1 稳定超时 / 2 入参非有限 /
 *                 3 斜率越带（已回滚）/ 4 非法相位兜底 / 5 相位号超出映射。
 * 红线 Redline   : R1✓ R2✓ R3✓ R4✓ R5✓ R6✓（ENUM + CASE + ELSE 兜底）
 *                 R7✓（tonZero/tonSpan/rtStart/rtReset 段 0 无条件刷新） R8✓ R9✓
 *                 R14✓（无 PROPERTY） R17✓（无数组） R20✓（相位只在 CASE 内写）
 * 验收 Accept    : A1 零液 −1.0 mV 稳定 10 拍 → 标液 −178.5 mV 稳定 10 拍 →
 *                 斜率 −59.17 mV/pH，eWrite 后 bDone=TRUE；
 *                 A2 标液给 0 mV（斜率 0）→ eRollback、uErrId=3、斜率回放旧值；
 *                 A3 稳定判据长期不满足 → 120s 超时 → eFault、uErrId=1。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AnalyzerCalPhase（两点标定相序）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AnalyzerCalPhase :
(
    eIdle       := 0,    // 待机：等待启动沿，斜率出口保持旧值 / Idle, the slope outlet keeps the old value
    eZeroSettle := 10,   // 零液稳定判据（pH 7.00）/ Zero liquid settling with the stability criterion
    eSpanSettle := 20,   // 标液稳定判据（pH 4.00）/ Span liquid settling with the stability criterion
    eCompute    := 30,   // 斜率计算与接收带判定 / Slope computation and acceptance band check
    eWrite      := 40,   // 斜率写回 / Slope written back
    eDone       := 50,   // 完成：等待复位或重新启动 / Finished, waiting for reset or restart
    eRollback   := 60,   // 回滚：斜率越带，恢复上一次有效值 / Rollback to the last valid slope
    eFault      := 90    // 故障：超时或非有限锁存 / Fault latched by timeout or non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnalyzerTwopointCalSeq
VAR_INPUT
    bStart      : BOOL;   // 启动，上升沿开始一轮标定 [-] / Start on the rising edge
    bReset      : BOOL;   // 复位，上升沿清锁存与快照 [-] / Reset on the rising edge
    fMeasMv     : REAL;   // 电极当前电位 [mV] / Current electrode potential in millivolts
    fTempC      : REAL;   // 当前溶液温度 [°C] / Current solution temperature
    uStableCnt  : UINT;   // 稳定判据所需连续拍数，有效域 ≥ 1 [拍] / Consecutive scans required for stability
END_VAR
VAR_OUTPUT
    bDone       : BOOL;   // 本轮标定成功完成 [-] / Calibration finished successfully
    bError      : BOOL;   // 故障或回滚 [-] / Fault or rollback
    fSlopeMvPerPh : REAL; // 当前生效斜率 [mV/pH] / Slope in effect in millivolts per pH
    uErrId      : UDINT;  // 事件码锁存，0 = 无事件 [-] / Latched event code
    uPhase      : UINT;   // 相位号镜像 0/10/20/30/40/50/60/90 [-] / Phase number mirror
END_VAR
VAR
    rtStart  : R_TRIG;                                        // 启动沿实例，段 0 无条件刷新 / Start edge instance
    rtReset  : R_TRIG;                                        // 复位沿实例，段 0 无条件刷新 / Reset edge instance
    tonZero  : TON;                                           // 零液相超时狗，段 0 无条件刷新 / Zero phase watchdog
    tonSpan  : TON;                                           // 标液相超时狗，段 0 无条件刷新 / Span phase watchdog
    _eState  : E_DL_AnalyzerCalPhase := E_DL_AnalyzerCalPhase.eIdle;  // 内部相位 / Internal phase
    _bInit   : BOOL := FALSE;                                 // 首扫初始化已执行 [-] / First scan initialization done
    _bFault  : BOOL := FALSE;                                 // 故障锁存位 [-] / Latched fault bit
    _bRoll   : BOOL := FALSE;                                 // 回滚锁存位 [-] / Latched rollback bit
    _uFault  : UDINT := 0;                                    // 事件码锁存 [-] / Latched event code
    _fMvPrev : REAL := 0.0;                                   // 上一拍电位快照 [mV] / Previous potential snapshot
    _nStable : UINT := 0;                                     // 当前相内连续稳定拍数 [拍] / Consecutive stable scans in the phase
    _fMvZero : REAL := 0.0;                                   // 零液电位记录 [mV] / Recorded zero liquid potential
    _fMvSpan : REAL := 0.0;                                   // 标液电位记录 [mV] / Recorded span liquid potential
    _fSlopeNew : REAL := 0.0;                                 // 本轮新算斜率 [mV/pH] / Newly computed slope
    _fSlopeUse : REAL := 0.0;                                 // 当前生效斜率（保持量）[mV/pH] / Slope in effect
    _fSlopePrev : REAL := 0.0;                                // 上一次有效斜率（回滚目标）[mV/pH] / Last valid slope
    _bNonFin : BOOL;                                          // 入参非有限当拍量 [-] / Non-finite argument flag
    _bStableNow : BOOL;                                       // 本拍判为稳定 [-] / Stable this scan flag
    _uPhaseNew : UINT;                                        // 相位号暂存 [-] / Staged phase number
END_VAR
VAR CONSTANT
    DL_CAL_PHZERO   : REAL := 7.00;      // 零液 pH（7.00）[pH] / pH of the zero liquid
    DL_CAL_PHSPAN   : REAL := 4.00;      // 标液 pH（4.00）[pH] / pH of the span liquid
    DL_CAL_STABLEMV : REAL := 0.10;      // 稳定判据电位带 [mV] / Stability tolerance on the potential
    DL_CAL_SLO      : REAL := -71.0;     // 斜率接收带下限 [mV/pH] / Lower bound of the slope acceptance band
    DL_CAL_SHI      : REAL := -45.0;     // 斜率接收带上限 [mV/pH] / Upper bound of the slope acceptance band
    DL_CAL_TMO      : TIME := T#120S;    // 相超时时间 [ms] / Phase timeout
    DL_CAL_C_NONE   : UDINT := 0;        // 码 0：无事件 / Code zero, no event
    DL_CAL_C_TMO    : UDINT := 1;        // 码 1：稳定超时 / Code one, settling timeout
    DL_CAL_C_FIN    : UDINT := 2;        // 码 2：入参非有限 / Code two, non-finite argument
    DL_CAL_C_BAND   : UDINT := 3;        // 码 3：斜率越带已回滚 / Code three, slope out of band, rolled back
    DL_CAL_C_ILL    : UDINT := 4;        // 码 4：非法相位兜底 / Code four, illegal phase fallback
END_VAR

(* —— 段 0｜沿实例与定时器无条件每拍刷新（R7；IN 串 NOT 锁存，R145 相驻留直驱） —— *)
rtStart (CLK := bStart);
rtReset (CLK := bReset);
tonZero (IN := (_eState = E_DL_AnalyzerCalPhase.eZeroSettle) AND (NOT _bFault), PT := DL_CAL_TMO);
tonSpan (IN := (_eState = E_DL_AnalyzerCalPhase.eSpanSettle) AND (NOT _bFault), PT := DL_CAL_TMO);

(* —— 段 1｜单拍量预清零（锁存量 _bFault/_bRoll/_uFault/_nStable 不入清单，R107） —— *)
_bNonFin    := FALSE;
_bStableNow := FALSE;
_uPhaseNew  := 0;

(* —— 段 2｜首扫初始化（斜率出口落 0，N3） —— *)
IF NOT _bInit THEN
    _bInit     := TRUE;
    _bFault    := FALSE;
    _bRoll     := FALSE;
    _uFault    := DL_CAL_C_NONE;
    _fSlopeUse := 0.0;                       // 未标定：斜率 0（安全侧）
    _fSlopePrev := 0.0;
    _nStable   := 0;
    _eState    := E_DL_AnalyzerCalPhase.eIdle;
END_IF

(* —— 段 3｜复位沿处理（作用域：清锁存 / 清稳定计数与快照 / 迁相位，R311） —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;                       // 作用域①：清锁存 / Scope one, clear the latches
    _bRoll   := FALSE;
    _uFault  := DL_CAL_C_NONE;
    _nStable := 0;                           // 作用域②：清计数与快照 / Scope two, clear counters
    _fMvPrev := 0.0;
    _eState  := E_DL_AnalyzerCalPhase.eIdle; // 作用域③：迁待机 / Scope three, back to idle
END_IF

(* —— 段 4｜非有限闸（覆盖参与判据的两个浮点引脚，R272） —— *)
IF (fMeasMv <> fMeasMv) OR (fTempC <> fTempC)
   OR ((fMeasMv - fMeasMv) <> (fMeasMv - fMeasMv)) THEN
    _bNonFin := TRUE;
END_IF
IF _bNonFin AND (_eState <> E_DL_AnalyzerCalPhase.eIdle) AND (NOT _bFault) THEN
    _bFault := TRUE;                         // 故障级配对（R45）
    _uFault := DL_CAL_C_FIN;
    _eState := E_DL_AnalyzerCalPhase.eFault;
END_IF

(* —— 段 5｜稳定判据（相邻拍电位差在带内即计一拍；出带即清零重计） —— *)
IF ABS(fMeasMv - _fMvPrev) <= DL_CAL_STABLEMV THEN
    _bStableNow := TRUE;
ELSE
    _nStable := 0;                           // 出带：计数清零（跨拍状态随撤销语义清零，N2）
END_IF
_fMvPrev := fMeasMv;                         // 快照唯一写入点 / Single snapshot write point

(* —— 段 6｜主状态机：八相全覆盖 + ELSE 非法相位兜底 —— *)
CASE _eState OF

E_DL_AnalyzerCalPhase.eIdle:
    IF rtStart.Q THEN
        _nStable := 0;                       // 拍 N+1 转出：进入零液稳定相
        _eState  := E_DL_AnalyzerCalPhase.eZeroSettle;
    END_IF

E_DL_AnalyzerCalPhase.eZeroSettle:
    IF _bStableNow THEN
        _nStable := _nStable + 1;
    END_IF
    IF (_nStable >= MAX(uStableCnt, 1)) THEN
        _fMvZero := fMeasMv;                 // 记录零液稳定电位
        _nStable := 0;
        _eState  := E_DL_AnalyzerCalPhase.eSpanSettle;   // 拍 N+1 转出：换标液
    ELSIF tonZero.Q THEN
        _bFault := TRUE;                     // 稳定超时：锁存（R45 配对）
        _uFault := DL_CAL_C_TMO;
        _eState := E_DL_AnalyzerCalPhase.eFault;
    END_IF

E_DL_AnalyzerCalPhase.eSpanSettle:
    IF _bStableNow THEN
        _nStable := _nStable + 1;
    END_IF
    IF (_nStable >= MAX(uStableCnt, 1)) THEN
        _fMvSpan := fMeasMv;                 // 记录标液稳定电位
        _nStable := 0;
        _eState  := E_DL_AnalyzerCalPhase.eCompute;      // 拍 N+1 转出：进入计算相
    ELSIF tonSpan.Q THEN
        _bFault := TRUE;
        _uFault := DL_CAL_C_TMO;
        _eState := E_DL_AnalyzerCalPhase.eFault;
    END_IF

E_DL_AnalyzerCalPhase.eCompute:
    (* 斜率 = ΔmV / ΔpH，ΔpH = 7.00 − 4.00 = 3.00，除子为常量非零 *)
    _fSlopeNew := (_fMvSpan - _fMvZero) / (DL_CAL_PHZERO - DL_CAL_PHSPAN);
    IF (_fSlopeNew <> _fSlopeNew) OR ((_fSlopeNew - _fSlopeNew) <> (_fSlopeNew - _fSlopeNew)) THEN
        _bFault := TRUE;                     // 计算结果非有限：故障级
        _uFault := DL_CAL_C_FIN;
        _eState := E_DL_AnalyzerCalPhase.eFault;
    ELSIF (_fSlopeNew < DL_CAL_SLO) OR (_fSlopeNew > DL_CAL_SHI) THEN
        _bRoll  := TRUE;                     // 越带：走回滚相，禁写坏值
        _uFault := DL_CAL_C_BAND;
        _eState := E_DL_AnalyzerCalPhase.eRollback;
    ELSE
        _eState := E_DL_AnalyzerCalPhase.eWrite;         // 拍 N+1 转出：写回
    END_IF

E_DL_AnalyzerCalPhase.eWrite:
    _fSlopePrev := _fSlopeUse;               // 旧值降级为回滚目标（唯一写入点）
    _fSlopeUse  := _fSlopeNew;               // 写回新斜率
    _uFault     := DL_CAL_C_NONE;
    _eState     := E_DL_AnalyzerCalPhase.eDone;

E_DL_AnalyzerCalPhase.eDone:
    IF rtStart.Q THEN
        _bRoll   := FALSE;
        _nStable := 0;
        _eState  := E_DL_AnalyzerCalPhase.eZeroSettle;   // 再次启动：重开一轮
    ELSIF rtReset.Q THEN
        _eState  := E_DL_AnalyzerCalPhase.eIdle;
    END_IF

E_DL_AnalyzerCalPhase.eRollback:
    _fSlopeUse := _fSlopePrev;               // 回滚到上一次有效斜率
    _bRoll     := TRUE;
    IF rtReset.Q OR rtStart.Q THEN
        _bRoll  := FALSE;
        _uFault := DL_CAL_C_NONE;
        _eState := E_DL_AnalyzerCalPhase.eIdle;
    END_IF

E_DL_AnalyzerCalPhase.eFault:
    _bFault := TRUE;                         // 故障相驻留：码位锁存回放（解除=bReset/bStart 沿）
    IF rtReset.Q THEN
        _uFault := DL_CAL_C_NONE;
        _eState := E_DL_AnalyzerCalPhase.eIdle;
    END_IF

ELSE
    _bFault := TRUE;                         // 非法相位兜底（R6）
    _uFault := DL_CAL_C_ILL;
    _eState := E_DL_AnalyzerCalPhase.eFault;
END_CASE

(* —— 段 7｜故障迁相闸（置于解除段之后，R274） —— *)
IF _bFault AND (_eState <> E_DL_AnalyzerCalPhase.eFault) THEN
    _eState := E_DL_AnalyzerCalPhase.eFault;
END_IF

(* —— 段 8｜统一出口段：判据位与实值单点裁决（N4 / R191） —— *)
bDone  := (_eState = E_DL_AnalyzerCalPhase.eDone);
bError := _bFault OR _bRoll;
uErrId := _uFault;
IF (_fSlopeUse <> _fSlopeUse) OR ((_fSlopeUse - _fSlopeUse) <> (_fSlopeUse - _fSlopeUse)) THEN
    fSlopeMvPerPh := 0.0;                    // 非有限兜底：斜率出口落 0（N1）
ELSE
    fSlopeMvPerPh := _fSlopeUse;
END_IF

(* 相位号镜像：单一 CASE 映射，禁多分支重复写同一状态（R20） *)
CASE _eState OF
    E_DL_AnalyzerCalPhase.eIdle:       _uPhaseNew := 0;
    E_DL_AnalyzerCalPhase.eZeroSettle: _uPhaseNew := 10;
    E_DL_AnalyzerCalPhase.eSpanSettle: _uPhaseNew := 20;
    E_DL_AnalyzerCalPhase.eCompute:    _uPhaseNew := 30;
    E_DL_AnalyzerCalPhase.eWrite:      _uPhaseNew := 40;
    E_DL_AnalyzerCalPhase.eDone:       _uPhaseNew := 50;
    E_DL_AnalyzerCalPhase.eRollback:   _uPhaseNew := 60;
    E_DL_AnalyzerCalPhase.eFault:      _uPhaseNew := 90;
ELSE
    _uPhaseNew := 90;                        // 非法相位镜像为故障号
END_CASE
uPhase := _uPhaseNew;
END_FUNCTION_BLOCK
