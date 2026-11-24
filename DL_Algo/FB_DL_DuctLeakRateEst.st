(*
  FB_DL_DuctLeakRateEst  —  风管漏风率估算（流量差法 + 静压修正 + 分级判据） / Duct air-leakage rate estimation by flow difference with static-pressure correction and class grading
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇风管验收算法族深化
  溯源 Origin   : 道莅 clean-room 实现；漏风率 = 100×(送风-回风)/送风 与静压线性修正为公开暖通测试算法，未复制任何源码行
  功能 Function : 1) 流量差法：_fLeakPct = 100 × (fSupplyM3h - fReturnM3h) / fSupplyM3h，
                  分母 <= 1.0E-6 判非法（除零前置守卫）；
                  2) 静压修正：_fCorrPct = (fStaticPa - fStaticRefPa) / 10.0 × fPressCorrPctPer10Pa，
                  修正后 _fLeakCorr = _fLeakPct - _fCorrPct（除数为常量 10.0）；
                  3) 向上取整到 0.1%：先实数上限兜底 → 截断 → 按余量进位（正好整除不 +1，
                  禁 TRUNC(x)+1 写法，R28-2）；
                  4) 分级：A/B/C 三档阈值判据，越 C 档为不合格（eReject）。
                  5) 本件只有故障码、无信息码（派单硬约束）。
  接口 Interface: 输入送/回风量、静压与参考静压、修正系数、三档阈值；输出漏风率/分级/码
  边界 Boundary : ① 组态闸：fSupplyM3h <= 1.0E-6、fPressCorrPctPer10Pa < 0.0、
                  fClassAPct < 0.0 或 fClassBPct <= fClassAPct 或 fClassCPct <= fClassBPct
                  → 0386 锁存；② 送/回风量或静压非有限（NaN 自反 + Inf 差值自减）→ 0386 锁存；
                  ③ 取整前实数上限兜底（2.147483E9 对应 DINT 可表上界），防 LREAL→DINT 溢出；
                  ④ 回风量大于送风量时漏风率为负，按死区归 0（-0.05% 容差带），不判故障；
                  ⑤ 零全局耦合：无 GVL / VAR_EXTERNAL / %I %Q %M 直接地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Algo 段 0002，故障窗口 0386；本件无信息码）:
    16#0002_0386 故障级：漏风率估算故障总码（组态非法 / 风量或静压非有限 / 送风量为零导致除零），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 2 · 序号 10）
*)

TYPE E_DL_DlrState :
(
    eIdle  := 0,      // 未使能待估算 / Idle, waiting evaluation
    eRun   := 10,     // 估算运行中 / Evaluation active
    eFault := 90      // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_DlrClass :
(
    eNone    := 0,    // 未分级 / Not graded
    eClassA  := 1,    // A 级（最严） / Class A, tightest
    eClassB  := 2,    // B 级 / Class B
    eClassC  := 3,    // C 级 / Class C
    eReject  := 4     // 不合格（越 C 档） / Rejected, beyond class C
);
END_TYPE

TYPE E_DL_DlrCause :
(
    eNone      := 0,  // 无故障成因 / No cause
    eCfgIllegal:= 1,  // 组态非法 / Illegal configuration
    eNonFinite := 2,  // 输入非有限 / Non-finite input
    eDivZero   := 3   // 送风量过小（除零风险） / Supply flow too small
);
END_TYPE

FUNCTION_BLOCK FB_DL_DuctLeakRateEst
VAR_INPUT
    fSupplyM3h        : REAL := 0.0;      // 送风量 [m³/h]，域 > 0 / Supply air flow
    fReturnM3h        : REAL := 0.0;      // 回风量 [m³/h] / Return air flow
    fStaticPa         : REAL := 0.0;      // 实测静压 [Pa] / Measured static pressure
    fStaticRefPa      : REAL := 0.0;      // 参考静压 [Pa] / Reference static pressure
    fPressCorrPctPer10Pa : REAL := 0.5;   // 每 10 Pa 修正百分比 [%/10Pa]，域 >= 0 / Correction per 10 Pa
    fClassAPct        : REAL := 1.0;      // A 级上限 [%] / Class A limit
    fClassBPct        : REAL := 3.0;      // B 级上限 [%] / Class B limit
    fClassCPct        : REAL := 6.0;      // C 级上限 [%] / Class C limit
    fNegDeadbandPct   : REAL := 0.05;     // 负值死区 [%]，域 >= 0 / Negative deadband
    bEnable           : BOOL := FALSE;    // 估算使能（电平）[-] / Evaluation enable
    bReset            : BOOL := FALSE;    // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState            : E_DL_DlrState;    // 状态出口，段 6 单点映射 / State outlet
    eClass            : E_DL_DlrClass;    // 分级出口 / Grading outlet
    eCause            : E_DL_DlrCause;    // 故障成因出口（R190） / Fault cause outlet
    fLeakPct          : REAL;             // 原始漏风率 [%] / Raw leakage rate
    fLeakCorrPct      : REAL;             // 静压修正后漏风率 [%] / Corrected leakage rate
    fLeakCeilPct      : REAL;             // 向上取整到 0.1% 的漏风率 [%] / Ceil to 0.1 %
    bError            : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId            : UDINT;            // 故障码，0 = 无故障（本件无信息码） / Fault code only
END_VAR
VAR
    _eState           : E_DL_DlrState := E_DL_DlrState.eIdle;     // 内部相位（CASE 唯一写入目标） / Internal phase
    _eClass           : E_DL_DlrClass := E_DL_DlrClass.eNone;     // 分级槽（每拍重算） / Grading slot
    _eCause           : E_DL_DlrCause := E_DL_DlrCause.eNone;     // 故障成因锁存（锁存量） / Latched cause
    rtReset           : R_TRIG;           // 复位沿实例，每周期无条件调用 / Reset edge
    _fDiffM3h         : REAL;             // 送回风量差 [m³/h]（当拍量） / Flow difference
    _fCorrPct         : REAL;             // 静压修正量 [%]（当拍量） / Pressure correction
    _fScaled          : REAL;             // 取整中间量（×10 后） / Scaling intermediate
    _iScaled          : DINT;             // 截断后整数（×10） / Truncated integer
    _bNonFin          : BOOL;             // 输入非有限当拍量 [-] / Non-finite input
    _bDivRisk         : BOOL;             // 除零风险当拍量 [-] / Divide risk
    _bCfgBad          : BOOL;             // 组态非法当拍量 [-] / Config illegal
    _bFault           : BOOL;             // 故障锁存位（锁存量） / Latched fault bit
    _uFault           : UDINT;            // 故障码锁存（锁存量） / Latched fault code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 当拍量判据 —— *)
_bNonFin := (fSupplyM3h <> fSupplyM3h) OR (fReturnM3h <> fReturnM3h) OR (fStaticPa <> fStaticPa)
         OR ((fSupplyM3h - fSupplyM3h) <> (fSupplyM3h - fSupplyM3h))
         OR ((fReturnM3h - fReturnM3h) <> (fReturnM3h - fReturnM3h))
         OR ((fStaticPa - fStaticPa) <> (fStaticPa - fStaticPa));            // NaN 自反 + Inf 差值自减 / NaN and Inf detection
_bDivRisk := fSupplyM3h <= 1.0E-6;                                           // 送风量过小（除零风险） / Divide risk
_bCfgBad := _bDivRisk OR (fPressCorrPctPer10Pa < 0.0) OR (fClassAPct < 0.0)
            OR (fClassBPct <= fClassAPct) OR (fClassCPct <= fClassBPct)
            OR (fNegDeadbandPct < 0.0);                                      // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                      // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量不入清单；分级槽每拍重算） —— *)
eClass := E_DL_DlrClass.eNone;      // 分级出口缺省未分级 / Grading default
eCause := _eCause;                  // 成因出口映射（锁存量回放，段 6 复核） / Cause outlet
fLeakPct := 0.0;                    // 原始漏风率缺省 0 / Raw rate default
fLeakCorrPct := 0.0;                // 修正后漏风率缺省 0 / Corrected rate default
fLeakCeilPct := 0.0;                // 取整漏风率缺省 0 / Ceil rate default
nErrId := 16#0000_0000;             // 故障码缺省无故障 / Fault code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_DlrCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_DlrState.eFault THEN
        _eState := E_DL_DlrState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bNonFin THEN                               // 非有限锁存（独立归因） / Non-finite latch
    _uFault := 16#0002_0386;                   // 故障级：估算故障总码 / Algo fault code
    _eCause := E_DL_DlrCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0002_0386;
    IF _bDivRisk THEN
        _eCause := E_DL_DlrCause.eDivZero;     // 归因：除零风险 / Cause: divide risk
    ELSE
        _eCause := E_DL_DlrCause.eCfgIllegal;  // 归因：组态非法 / Cause: illegal config
    END_IF
    _bFault := TRUE;
END_IF

(* —— 段 3：漏风率与分级（仅无故障时计算；除数为已校验正域） —— *)
IF (NOT _bFault) AND (_eState = E_DL_DlrState.eRun) THEN
    _fDiffM3h := fSupplyM3h - fReturnM3h;                          // 流量差 / Flow difference
    fLeakPct := 100.0 * _fDiffM3h / fSupplyM3h;                    // 原始漏风率（分母已守卫） / Raw rate
    _fCorrPct := (fStaticPa - fStaticRefPa) / 10.0 * fPressCorrPctPer10Pa;   // 静压修正（除常量 10.0） / Correction
    fLeakCorrPct := fLeakPct - _fCorrPct;                          // 修正后漏风率 / Corrected rate
    IF (fLeakCorrPct < 0.0) AND (ABS(fLeakCorrPct) <= fNegDeadbandPct) THEN
        fLeakCorrPct := 0.0;                                       // 负值死区归 0 / Negative deadband
    END_IF
    _fScaled := fLeakCorrPct * 10.0;                               // 放大 10 倍进入整数域 / Scale by ten
    IF _fScaled >= 2.147483E9 THEN                                 // 实数上限兜底（DINT 可表上界） / Real upper guard
        _fScaled := 2.147483E9;
    ELSIF _fScaled <= -2.147483E9 THEN                             // 实数下限兜底 / Real lower guard
        _fScaled := -2.147483E9;
    END_IF
    _iScaled := LREAL_TO_DINT(LREAL(_fScaled));                    // 截断取整 / Truncate
    IF LREAL(_iScaled) < LREAL(_fScaled) - 1.0E-9 THEN             // 余量进位（正好整除不进位） / Ceiling by remainder
        _iScaled := _iScaled + 1;
    END_IF
    fLeakCeilPct := DINT_TO_REAL(_iScaled) * 0.1;                  // 还原为 0.1% 步长 / Restore 0.1 % step
    IF fLeakCeilPct <= fClassAPct THEN
        _eClass := E_DL_DlrClass.eClassA;                          // A 级 / Class A
    ELSIF fLeakCeilPct <= fClassBPct THEN
        _eClass := E_DL_DlrClass.eClassB;                          // B 级 / Class B
    ELSIF fLeakCeilPct <= fClassCPct THEN
        _eClass := E_DL_DlrClass.eClassC;                          // C 级 / Class C
    ELSE
        _eClass := E_DL_DlrClass.eReject;                          // 不合格（ELSE 兜底） / Rejected fallback
    END_IF
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bNonFin / NOT _bCfgBad —— *)
IF rtReset.Q AND (NOT _bNonFin) AND (NOT _bCfgBad) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_DlrCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_DlrState.eFault) THEN
    _eState := E_DL_DlrState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_DlrState.eIdle:
    IF bEnable AND (NOT _bFault) THEN          // 使能条件 / Enable gate
        _eState := E_DL_DlrState.eRun;         // 进估算相 / Enter evaluation
    END_IF

E_DL_DlrState.eRun:
    IF NOT bEnable THEN                        // 撤使能：回未使能（前置消失） / Disable returns idle
        _eState := E_DL_DlrState.eIdle;
    END_IF

E_DL_DlrState.eFault:
    ;                                          // 故障相：仅段 4 复位沿可迁出 / Only reset exits

ELSE
    _uFault := 16#0002_0386;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_DlrCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_DlrState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    eClass := E_DL_DlrClass.eNone;             // 故障相分级强制未分级 / Grading forced none
    fLeakCeilPct := 0.0;                       // 故障相取整值强制 0（安全侧） / Ceil forced zero
ELSE
    nErrId := 16#0000_0000;                    // 无故障：本件无信息码 / No fault, no info code
    eClass := _eClass;                         // 分级出口 / Grading outlet
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
