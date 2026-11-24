(*
  FB_DL_AxisBrakeDistPredict  —  轴制动距离预判（速度/减速度→停车距离 + 硬限位留量） / Axis braking-distance prediction from velocity and deceleration with hard-limit allowance
  分类 Category : DL_Motion
  版本 Version  : 1.0.0
  来源 Source   : t1-6-plcopen — PLCopen Motion 接口映射层族深化
  溯源 Origin   : 道莅 clean-room 实现；匀减速停车距离 d = v×t_react + v²/(2a) 为公开运动学公式，
                 本件仅做 PLCopen MC 接口的判据映射层，不内联任何轨迹规划内核（复用 DL_Algo 既有件）
  功能 Function : 1) 反应距离 _fReactMm = fActVelMmS × 反应时间(s)；
                  2) 制动距离 _fBrakeMm = v² / (2 × fDecelMmS2)（除零前置判，减速度 <= 1.0E-6 判组态非法）；
                  3) 停车总距离 _fStopMm = 反应距离 + 制动距离 + fSafetyMarginMm；
                  4) 可用距离按运动方向取（正向 = 限位 - 当前；反向 = 当前 - 限位），负值钳制 0；
                  5) 判据：可用距离 > 停车总距离 → bStopOk；否则进 eBrake 相请求减速停车；
                  6) 本件只有故障码、无信息码（派单硬约束）。
  接口 Interface: 输入速度/减速度/位置/限位/余量/反应时间/方向；输出停车距离与判据
  边界 Boundary : ① 组态闸：fDecelMmS2 <= 1.0E-6、tReaction <= T#0S、fSafetyMarginMm < 0.0
                  → 04A6 锁存；② 速度/位置/限位非有限（NaN 自反 + Inf 差值自减）→ 04A6 锁存，
                  判据取安全侧（bStopOk = FALSE，请求停车）；
                  ③ 除零防护在计算前以减速度正域判据完成（不进入除法）；
                  ④ 一个 R_TRIG，段 0 无条件调用；⑤ 故障相迁出唯一路径 = bReset 上升沿；
                  ⑥ 零全局耦合：无 GVL / VAR_EXTERNAL / %I %Q %M 直接地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Motion 段 0004，故障窗口 04A6；本件无信息码）:
    16#0004_04A6 故障级：制动距离预判故障总码（组态非法 / 输入非有限），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 4 · 序号 18）
*)

TYPE E_DL_AbpState :
(
    eIdle  := 0,      // 未使能待预判 / Idle, waiting prediction
    eRun   := 10,     // 预判运行中（距离充足） / Predicting, distance sufficient
    eBrake := 20,     // 距离不足：请求减速停车 / Insufficient distance, stop requested
    eFault := 90      // 故障锁存相（请求停车） / Fault latched, stop requested
);
END_TYPE

TYPE E_DL_AbpCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2  // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisBrakeDistPredict
VAR_INPUT
    fActVelMmS     : REAL := 0.0;      // 轴实际速度 [mm/s]，域 >= 0 / Actual axis velocity
    fDecelMmS2     : REAL := 1000.0;   // 规划减速度 [mm/s²]，域 > 0 / Planned deceleration
    fPosMm         : REAL := 0.0;      // 当前轴位置 [mm] / Current axis position
    fLimitPosMm    : REAL := 0.0;      // 硬限位位置 [mm] / Hard limit position
    fSafetyMarginMm: REAL := 10.0;     // 安全留量 [mm]，域 >= 0 / Safety margin
    tReaction      : TIME := T#50MS;   // 反应时间 [ms]，域 > 0 / Reaction time
    bDirPositive   : BOOL := TRUE;     // 运动方向：TRUE = 正向 [-] / Direction, TRUE = positive
    bEnable        : BOOL := FALSE;    // 预判使能（电平）[-] / Prediction enable
    bReset         : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState         : E_DL_AbpState;    // 状态出口，段 6 单点映射 / State outlet
    eCause         : E_DL_AbpCause;    // 故障成因出口（R190） / Fault cause outlet
    fStopDistMm    : REAL;             // 停车总距离 [mm] / Total stopping distance
    fAvailMm       : REAL;             // 到限位可用距离 [mm] / Available distance to limit
    bStopOk        : BOOL;             // 距离充足判据 [-] / Sufficient-distance verdict
    bStopRequest   : BOOL;             // 停车请求（MC_Halt 触发源）[-] / Stop request for MC_Halt
    bError         : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId         : UDINT;            // 故障码，0 = 无故障（本件无信息码） / Fault code only
END_VAR
VAR
    _eState        : E_DL_AbpState := E_DL_AbpState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause        : E_DL_AbpCause := E_DL_AbpCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtReset        : R_TRIG;           // 复位沿实例，每周期无条件调用 / Reset edge
    _fReactMm      : REAL;             // 反应距离 [mm]（当拍量） / Reaction distance
    _fBrakeMm      : REAL;             // 制动距离 [mm]（当拍量） / Braking distance
    _fStopMm       : REAL;             // 停车总距离 [mm]（当拍量） / Total stopping distance
    _fAvailMm      : REAL;             // 可用距离 [mm]（当拍量） / Available distance
    _bStopOk       : BOOL;             // 判据（当拍量） / Verdict
    _bNonFin       : BOOL;             // 输入非有限当拍量 [-] / Non-finite input
    _bCfgBad       : BOOL;             // 组态非法当拍量 [-] / Config illegal
    _bFault        : BOOL;             // 故障锁存位（锁存量） / Latched fault bit
    _uFault        : UDINT;            // 故障码锁存（锁存量） / Latched fault code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 当拍量判据（除零前置：减速度正域） —— *)
_bNonFin := (fActVelMmS <> fActVelMmS) OR (fPosMm <> fPosMm) OR (fLimitPosMm <> fLimitPosMm)
         OR ((fActVelMmS - fActVelMmS) <> (fActVelMmS - fActVelMmS))
         OR ((fPosMm - fPosMm) <> (fPosMm - fPosMm))
         OR ((fLimitPosMm - fLimitPosMm) <> (fLimitPosMm - fLimitPosMm));      // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (fDecelMmS2 <= 1.0E-6) OR (tReaction <= T#0S) OR (fSafetyMarginMm < 0.0);   // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                       // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
fStopDistMm := 0.0;                // 停车距离缺省 0 / Stopping distance default
fAvailMm := 0.0;                   // 可用距离缺省 0 / Available default
bStopOk := FALSE;                  // 判据缺省 FALSE（安全侧） / Verdict default safe
bStopRequest := TRUE;              // 停车请求缺省 TRUE（安全侧） / Stop request default safe
nErrId := 16#0000_0000;            // 故障码缺省无故障 / Fault code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_AbpCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_AbpState.eFault THEN
        _eState := E_DL_AbpState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0004_04A6;                   // 故障级：预判故障总码 / Motion fault code
    _eCause := E_DL_AbpCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0004_04A6;
    _eCause := E_DL_AbpCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：停车距离与可用距离计算（仅无故障；减速度已校验正域） —— *)
IF NOT _bFault THEN
    _fReactMm := fActVelMmS * (TIME_TO_REAL(tReaction) / 1000.0);              // 反应距离 [mm]（除常量 1000.0） / Reaction distance
    _fBrakeMm := fActVelMmS * fActVelMmS / (2.0 * fDecelMmS2);                 // 制动距离 [mm]（除数为已校验正域） / Braking distance
    _fStopMm := _fReactMm + _fBrakeMm + fSafetyMarginMm;                       // 停车总距离 [mm] / Total stopping distance
    IF bDirPositive THEN
        _fAvailMm := fLimitPosMm - fPosMm;                                     // 正向可用距离 / Positive available distance
    ELSE
        _fAvailMm := fPosMm - fLimitPosMm;                                     // 反向可用距离 / Negative available distance
    END_IF
    IF _fAvailMm < 0.0 THEN                                                    // 已越限位：可用距离钳制 0 / Clamp to zero
        _fAvailMm := 0.0;
    END_IF
    _bStopOk := _fAvailMm > _fStopMm;                                          // 判据（严格大于，含余量） / Verdict
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_AbpCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（请求停车） —— *)
IF _bFault AND (_eState <> E_DL_AbpState.eFault) THEN
    _eState := E_DL_AbpState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_AbpState.eIdle:
    IF bEnable AND (NOT _bFault) THEN          // 使能条件 / Enable gate
        _eState := E_DL_AbpState.eRun;         // 进预判相 / Enter prediction
    END_IF

E_DL_AbpState.eRun:
    IF NOT _bStopOk THEN                       // 出口 1：距离不足（事件） / Insufficient distance
        _eState := E_DL_AbpState.eBrake;       // 进请求停车相 / Enter stop request
    ELSIF NOT bEnable THEN                     // 出口 2：撤使能（前置消失） / Disable
        _eState := E_DL_AbpState.eIdle;
    END_IF

E_DL_AbpState.eBrake:
    IF _bStopOk AND bEnable THEN               // 距离恢复充足：回预判相 / Distance sufficient again
        _eState := E_DL_AbpState.eRun;
    ELSIF NOT bEnable THEN                     // 撤使能：回未使能 / Disable returns idle
        _eState := E_DL_AbpState.eIdle;
    END_IF

E_DL_AbpState.eFault:
    ;                                          // 故障相：请求停车，仅段 4 复位沿可迁出 / Stop requested, reset only

ELSE
    _uFault := 16#0004_04A6;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_AbpCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_AbpState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；故障相请求停车） —— *)
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    bStopOk := FALSE;                          // 故障相判据强制 FALSE（安全侧） / Verdict forced false
    bStopRequest := TRUE;                      // 故障相请求停车 / Stop requested
    fStopDistMm := 0.0;                        // 故障相距离出口强制 0 / Distance forced zero
    fAvailMm := 0.0;                           // 故障相可用距离强制 0 / Available forced zero
ELSE
    nErrId := 16#0000_0000;                    // 无故障：本件无信息码 / No fault, no info code
    bStopOk := _bStopOk;                       // 判据出口 / Verdict outlet
    bStopRequest := (_eState = E_DL_AbpState.eBrake) OR (NOT _bStopOk);   // 停车请求出口 / Stop request outlet
    fStopDistMm := _fStopMm;                   // 停车距离出口 / Distance outlet
    fAvailMm := _fAvailMm;                     // 可用距离出口 / Available outlet
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
