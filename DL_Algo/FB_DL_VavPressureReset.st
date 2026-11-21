(*
  FB_DL_VavPressureReset  —  VAV 静压重置（最不利末端阀位寻优 + 步长限幅） / VAV duct static-pressure reset by worst-case terminal damper optimisation with step limiting
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇变风量静压重置算法族深化
  溯源 Origin   : 道莅 clean-room 实现；以最不利末端阀位为反馈的静压爬坡重置（死区 + 步长限幅）为公开 VAV 节能算法，未复制任何源码行
  功能 Function : 1) 偏差 _fErrPct = fDamperTargetPct - fWorstDamperPct（最不利末端阀位对目标阀位）；
                  2) 死区保持：|偏差| <= fDeadbandPct 时设定保持不变（不动作）；
                  3) 爬坡寻优：偏差为正（阀位偏小，需更大静压）每周期加 fStepKpa，
                  偏差为负每周期减 fStepKpa，单周期变化量恒等于步长（限速内置）；
                  4) 硬限幅：设定钳制到 [fSpMinKpa, fSpMaxKpa]，限幅后二次复核；
                  5) 本件只有故障码、无信息码（派单硬约束）。
  接口 Interface: 输入最不利阀位/目标阀位/死区/步长/上下限；输出静压设定与动作镜像
  边界 Boundary : ① 组态闸：fSpMaxKpa <= fSpMinKpa、fStepKpa <= 0.0、fDeadbandPct < 0.0、
                  fDamperTargetPct 不在 (0, 100) 开区间 → 0387 锁存；
                  ② 阀位与设定量非有限（NaN 自反 + Inf 差值自减）→ 0387 锁存，输出冻结保持
                  （本件为设定类算法，冻结保持不降级，语义已在头注释声明，R191）；
                  ③ 浮点判据全容差式，禁 = / <> 判等；④ 仅一个 R_TRIG 复位沿，段 0 无条件调用；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Algo 段 0002，故障窗口 0387；本件无信息码）:
    16#0002_0387 故障级：VAV 静压重置故障总码（组态非法 / 阀位或设定非有限），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 3 · 序号 11）
*)

TYPE E_DL_VprState :
(
    eIdle  := 0,      // 未使能：设定冻结 / Idle, setpoint frozen
    eRun   := 10,     // 寻优运行中 / Optimisation active
    eFault := 90      // 故障锁存相（设定冻结保持） / Fault latched, setpoint frozen
);
END_TYPE

TYPE E_DL_VprCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2  // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_VavPressureReset
VAR_INPUT
    fWorstDamperPct : REAL := 0.0;     // 最不利末端阀位 [%]，0~100 / Worst-case terminal damper position
    fDamperTargetPct: REAL := 90.0;    // 目标阀位 [%]，开区间 (0,100) / Target damper position
    fDeadbandPct    : REAL := 5.0;     // 阀位死区 [%]，域 >= 0 / Damper deadband
    fStepKpa        : REAL := 2.0;     // 单周期静压步长 [kPa]，域 > 0 / Static pressure step
    fSpMinKpa       : REAL := 100.0;   // 静压设定下限 [kPa] / Setpoint low limit
    fSpMaxKpa       : REAL := 500.0;   // 静压设定上限 [kPa] / Setpoint high limit
    fSpInitKpa      : REAL := 250.0;   // 设定初值（使能沿装载） [kPa] / Initial setpoint
    bEnable         : BOOL := FALSE;   // 寻优使能（电平）[-] / Optimisation enable
    bReset          : BOOL := FALSE;   // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState          : E_DL_VprState;   // 状态出口，段 6 单点映射 / State outlet
    eCause          : E_DL_VprCause;   // 故障成因出口（R190） / Fault cause outlet
    fSpKpa          : REAL;            // 静压设定输出 [kPa] / Static pressure setpoint
    bRaise          : BOOL;            // 本周期升压动作镜像 [-] / Raise action mirror
    bLower          : BOOL;            // 本周期降压动作镜像 [-] / Lower action mirror
    bError          : BOOL;            // 故障锁存标志 [-] / Fault latch flag
    nErrId          : UDINT;           // 故障码，0 = 无故障（本件无信息码） / Fault code only
END_VAR
VAR
    _eState         : E_DL_VprState := E_DL_VprState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause         : E_DL_VprCause := E_DL_VprCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtEnable        : R_TRIG;          // 使能沿实例，每周期无条件调用 / Enable edge
    rtReset         : R_TRIG;          // 复位沿实例，每周期无条件调用 / Reset edge
    _fSp            : REAL;            // 设定保持槽（持久） / Setpoint holding slot
    _fErrPct        : REAL;            // 阀位偏差 [%]（当拍量） / Damper deviation
    _bRaiseOn       : BOOL;            // 升压当拍量 [-] / Raise action
    _bLowerOn       : BOOL;            // 降压当拍量 [-] / Lower action
    _bNonFin        : BOOL;            // 输入非有限当拍量 [-] / Non-finite input
    _bCfgBad        : BOOL;            // 组态非法当拍量 [-] / Config illegal
    _bFault         : BOOL;            // 故障锁存位（锁存量） / Latched fault bit
    _uFault         : UDINT;           // 故障码锁存（锁存量） / Latched fault code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 当拍量判据 —— *)
_fErrPct := fDamperTargetPct - fWorstDamperPct;                              // 阀位偏差 [%] / Damper deviation
_bNonFin := (fWorstDamperPct <> fWorstDamperPct) OR (fSpMinKpa <> fSpMinKpa)
         OR ((fWorstDamperPct - fWorstDamperPct) <> (fWorstDamperPct - fWorstDamperPct))
         OR ((fSpMinKpa - fSpMinKpa) <> (fSpMinKpa - fSpMinKpa));            // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (fSpMaxKpa <= fSpMinKpa) OR (fStepKpa <= 0.0) OR (fDeadbandPct < 0.0)
            OR (fDamperTargetPct <= 0.0) OR (fDamperTargetPct >= 100.0);     // 组态非法当拍量 / Config illegal
rtEnable(CLK := bEnable);                                                    // 使能沿，每拍必调 / Enable edge
rtReset(CLK := bReset);                                                      // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量与设定保持槽不入清单） —— *)
bRaise := FALSE;                   // 升压镜像缺省 FALSE / Raise default
bLower := FALSE;                   // 降压镜像缺省 FALSE / Lower default
nErrId := 16#0000_0000;            // 故障码缺省无故障 / Fault code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_VprCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_VprState.eFault THEN
        _eState := E_DL_VprState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0002_0387;                   // 故障级：重置故障总码 / Algo fault code
    _eCause := E_DL_VprCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0002_0387;
    _eCause := E_DL_VprCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：寻优动作（仅在运行相且无故障；死区优先于动作） —— *)
IF (NOT _bFault) AND (_eState = E_DL_VprState.eRun) THEN
    IF ABS(_fErrPct) <= fDeadbandPct THEN                 // 死区内保持（容差式） / Deadband hold
        ;                                                // 保持：不动作 / Hold, no action
    ELSIF _fErrPct > fDeadbandPct THEN                    // 阀位偏小：升压 / Damper small: raise
        _fSp := _fSp + fStepKpa;                          // 单周期升压一个步长 / Raise one step
        _bRaiseOn := TRUE;
    ELSE                                                  // 阀位偏大：降压 / Damper large: lower
        _fSp := _fSp - fStepKpa;                          // 单周期降压一个步长 / Lower one step
        _bLowerOn := TRUE;
    END_IF
    IF _fSp < fSpMinKpa THEN                              // 下限钳制 / Low clamp
        _fSp := fSpMinKpa;
    ELSIF _fSp > fSpMaxKpa THEN                           // 上限钳制 / High clamp
        _fSp := fSpMaxKpa;
    END_IF
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_VprCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（设定冻结保持） —— *)
IF _bFault AND (_eState <> E_DL_VprState.eFault) THEN
    _eState := E_DL_VprState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_VprState.eIdle:
    IF rtEnable.Q AND (NOT _bFault) THEN       // 使能上升沿：装载初值并钳制 / Enable edge loads initial value
        _fSp := fSpInitKpa;                    // 装载初值 / Load initial setpoint
        IF _fSp < fSpMinKpa THEN               // 初值下限钳制 / Initial low clamp
            _fSp := fSpMinKpa;
        ELSIF _fSp > fSpMaxKpa THEN            // 初值上限钳制 / Initial high clamp
            _fSp := fSpMaxKpa;
        END_IF
        _eState := E_DL_VprState.eRun;         // 进运行相 / Enter run
    END_IF

E_DL_VprState.eRun:
    IF NOT bEnable THEN                        // 撤使能：设定冻结，回未使能 / Disable: freeze and idle
        _eState := E_DL_VprState.eIdle;
    END_IF

E_DL_VprState.eFault:
    ;                                          // 故障相：设定冻结保持，仅段 4 复位沿可迁出 / Frozen, reset only

ELSE
    _uFault := 16#0002_0387;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_VprCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_VprState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fSpKpa := _fSp;                                // 设定值出口 / Setpoint outlet
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    bRaise := FALSE;                           // 故障相动作镜像强制 FALSE / Raise forced false
    bLower := FALSE;                           // 故障相动作镜像强制 FALSE / Lower forced false
ELSE
    nErrId := 16#0000_0000;                    // 无故障：本件无信息码 / No fault, no info code
    bRaise := _bRaiseOn;                       // 升压镜像 / Raise mirror
    bLower := _bLowerOn;                       // 降压镜像 / Lower mirror
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
