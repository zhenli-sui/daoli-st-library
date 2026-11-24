(*
  FB_DL_FanPressureTrim  —  风机静压微调（偏差积分微调 + 抗饱和回退） / Fan static-pressure trim with integral adjustment and anti-windup back-off
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : t2-7-packml — 包装线风系统微调算法深化
  溯源 Origin   : 道莅 clean-room 实现；死区 + 积分微调 + 饱和回退（条件积分抗饱和）为公开过程控制算法，未复制任何源码行
  功能 Function : 1) 偏差 _fErrKpa = fSpKpa - fPvKpa；2) 死区内（|偏差| <= fDeadbandKpa）冻结积分；
                  3) 积分微调：_fIntKpa += fKiKpaPerS × Δt（Δt 由 tCycle 换算，除数 1000.0 常量）；
                  4) 输出 = fTrimBaseKpa + _fIntKpa，钳制 [fOutMinKpa, fOutMaxKpa]；
                  5) 抗饱和回退：输出已顶上限且偏差仍为正（同向推高）时回退本周期积分增量；
                  输出已抵下限且偏差仍为负时同样回退，禁止积分继续累积（条件积分法）；
                  6) 上拍积分快照 _fIntPrevKpa 保存（R19 累计量快照，禁跨拍重算）；
                  7) 本件只有故障码、无信息码（派单硬约束）。
  接口 Interface: 输入设定/反馈/基准/增益/死区/周期/上下限；输出微调输出与积分镜像
  边界 Boundary : ① 组态闸：tCycle <= T#0S、fKiKpaPerS < 0.0、fDeadbandKpa < 0.0、
                  fOutMaxKpa <= fOutMinKpa → 038A 锁存；
                  ② 设定或反馈非有限（NaN 自反 + Inf 差值自减）→ 038A 锁存，输出冻结保持上一值
                  （R191：冻结保持，不降级置标志）；
                  ③ 积分器本身为限幅量，回退后仍钳制在 [fIntMinKpa, fIntMaxKpa] 域内；
                  ④ 浮点判据全容差式；⑤ 仅一个 R_TRIG 复位沿，段 0 无条件调用；
                  ⑥ 故障相迁出唯一路径 = bReset 上升沿；⑦ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Algo 段 0002，故障窗口 038A；本件无信息码）:
    16#0002_038A 故障级：静压微调故障总码（组态非法 / 设定或反馈非有限），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 3 · 序号 14）
*)

TYPE E_DL_FptState :
(
    eIdle  := 0,      // 未使能：输出冻结 / Idle, output frozen
    eRun   := 10,     // 微调运行中 / Trim active
    eFault := 90      // 故障锁存相（输出冻结保持） / Fault latched, output frozen
);
END_TYPE

TYPE E_DL_FptCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2  // 设定或反馈非有限 / Non-finite setpoint or feedback
);
END_TYPE

FUNCTION_BLOCK FB_DL_FanPressureTrim
VAR_INPUT
    fSpKpa       : REAL := 0.0;        // 静压设定 [kPa] / Static pressure setpoint
    fPvKpa       : REAL := 0.0;        // 静压反馈 [kPa] / Static pressure feedback
    fTrimBaseKpa : REAL := 200.0;      // 微调基准输出 [kPa] / Trim base output
    fKiKpaPerS   : REAL := 0.5;        // 积分增益 [kPa/s]，域 >= 0 / Integral gain
    fDeadbandKpa : REAL := 2.0;        // 偏差死区 [kPa]，域 >= 0 / Deviation deadband
    fIntMinKpa   : REAL := -50.0;      // 积分量下限 [kPa] / Integral low limit
    fIntMaxKpa   : REAL := 50.0;       // 积分量上限 [kPa] / Integral high limit
    fOutMinKpa   : REAL := 100.0;      // 输出下限 [kPa] / Output low limit
    fOutMaxKpa   : REAL := 400.0;      // 输出上限 [kPa] / Output high limit
    tCycle       : TIME := T#100MS;    // 调用周期 [ms]，域 > 0 / Task cycle
    bEnable      : BOOL := FALSE;      // 微调使能（电平）[-] / Trim enable
    bReset       : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_FptState;      // 状态出口，段 6 单点映射 / State outlet
    eCause       : E_DL_FptCause;      // 故障成因出口（R190） / Fault cause outlet
    fOutKpa      : REAL;               // 微调输出 [kPa] / Trim output
    fIntKpa      : REAL;               // 积分量镜像 [kPa] / Integral mirror
    bWindup      : BOOL;               // 抗饱和回退生效镜像 [-] / Anti-windup back-off mirror
    bError       : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;              // 故障码，0 = 无故障（本件无信息码） / Fault code only
END_VAR
VAR
    _eState      : E_DL_FptState := E_DL_FptState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_FptCause := E_DL_FptCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtReset      : R_TRIG;             // 复位沿实例，每周期无条件调用 / Reset edge
    _fIntKpa     : REAL;               // 积分器保持量（持久） / Integral holding slot
    _fIntPrevKpa : REAL;               // 上拍积分快照（R19 累计量快照） / Previous-scan integral snapshot
    _fOutKpa     : REAL;               // 输出保持量（持久） / Output holding slot
    _fErrKpa     : REAL;               // 偏差 [kPa]（当拍量） / Deviation
    _fDeltaKpa   : REAL;               // 本周期积分增量 [kPa]（当拍量） / Integral increment
    _fOutCandKpa : REAL;               // 未钳制候选输出 [kPa]（当拍量） / Unclamped candidate
    _bWindupOn   : BOOL;               // 抗饱和回退当拍量 [-] / Anti-windup flag
    _bNonFin     : BOOL;               // 输入非有限当拍量 [-] / Non-finite input
    _bCfgBad     : BOOL;               // 组态非法当拍量 [-] / Config illegal
    _bFault      : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;              // 故障码锁存（锁存量） / Latched fault code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 当拍量判据 —— *)
_fErrKpa := fSpKpa - fPvKpa;                                                // 偏差 [kPa] / Deviation
_bNonFin := (fSpKpa <> fSpKpa) OR (fPvKpa <> fPvKpa)
         OR ((fSpKpa - fSpKpa) <> (fSpKpa - fSpKpa))
         OR ((fPvKpa - fPvKpa) <> (fPvKpa - fPvKpa));                       // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (tCycle <= T#0S) OR (fKiKpaPerS < 0.0) OR (fDeadbandKpa < 0.0)
            OR (fOutMaxKpa <= fOutMinKpa) OR (fIntMaxKpa <= fIntMinKpa);    // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                     // 复位沿，每拍必调 / Reset edge
_fIntPrevKpa := _fIntKpa;                                                   // 上拍积分快照（每拍无条件） / Previous integral snapshot

(* —— 段 1：单拍量预清零（锁存量与积分/输出保持槽不入清单） —— *)
bWindup := FALSE;                  // 抗饱和镜像缺省 FALSE / Anti-windup default
nErrId := 16#0000_0000;            // 故障码缺省无故障 / Fault code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_FptCause.eNone;            // 清成因（锁存量） / Clear cause
    _fIntKpa := 0.0;                           // 清积分器 / Clear integrator
    _fIntPrevKpa := 0.0;                       // 清积分快照 / Clear snapshot
    IF _eState = E_DL_FptState.eFault THEN
        _eState := E_DL_FptState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0002_038A;                   // 故障级：微调故障总码 / Algo fault code
    _eCause := E_DL_FptCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0002_038A;
    _eCause := E_DL_FptCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：积分微调 + 抗饱和回退 + 输出钳制（仅运行相且无故障） —— *)
IF (NOT _bFault) AND (_eState = E_DL_FptState.eRun) THEN
    IF ABS(_fErrKpa) <= fDeadbandKpa THEN                    // 死区内：冻结积分（不动作） / Deadband freezes integrator
        _fDeltaKpa := 0.0;
    ELSE
        _fDeltaKpa := fKiKpaPerS * (TIME_TO_REAL(tCycle) / 1000.0);   // 周期加权积分增量（除常量 1000.0） / Cycle-weighted increment
        IF _fErrKpa < 0.0 THEN                               // 偏差为负：积分反向 / Negative deviation subtracts
            _fDeltaKpa := -_fDeltaKpa;
        END_IF
        _fIntKpa := _fIntKpa + _fDeltaKpa;                   // 积分累加 / Integrate
        IF _fIntKpa < fIntMinKpa THEN                        // 积分下限钳制 / Integral low clamp
            _fIntKpa := fIntMinKpa;
        ELSIF _fIntKpa > fIntMaxKpa THEN                     // 积分上限钳制 / Integral high clamp
            _fIntKpa := fIntMaxKpa;
        END_IF
    END_IF
    _fOutCandKpa := fTrimBaseKpa + _fIntKpa;                 // 候选输出 / Candidate output
    IF _fOutCandKpa > fOutMaxKpa THEN                        // 顶上限 / Hit high limit
        IF _fErrKpa > 0.0 THEN                               // 偏差仍同向推高：回退本周期增量 / Same-direction saturation
            _fIntKpa := _fIntPrevKpa;                        // 抗饱和回退到上拍快照 / Back-off to snapshot
            _bWindupOn := TRUE;
        END_IF
        _fOutKpa := fOutMaxKpa;                              // 输出钳制上限 / Output clamped high
    ELSIF _fOutCandKpa < fOutMinKpa THEN                     // 抵下限 / Hit low limit
        IF _fErrKpa < 0.0 THEN                               // 偏差仍同向推低：回退 / Same-direction saturation
            _fIntKpa := _fIntPrevKpa;                        // 抗饱和回退 / Back-off
            _bWindupOn := TRUE;
        END_IF
        _fOutKpa := fOutMinKpa;                              // 输出钳制下限 / Output clamped low
    ELSE
        _fOutKpa := _fOutCandKpa;                            // 未饱和：直接跟随 / Follow candidate
    END_IF
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_FptCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（输出冻结保持上一值） —— *)
IF _bFault AND (_eState <> E_DL_FptState.eFault) THEN
    _eState := E_DL_FptState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_FptState.eIdle:
    IF bEnable AND (NOT _bFault) THEN          // 使能条件 / Enable gate
        _fIntKpa := 0.0;                       // 起始清积分（无扰切换） / Reset integrator on start
        _fOutKpa := fTrimBaseKpa;              // 起始输出取基准并钳制 / Start from base
        IF _fOutKpa < fOutMinKpa THEN
            _fOutKpa := fOutMinKpa;
        ELSIF _fOutKpa > fOutMaxKpa THEN
            _fOutKpa := fOutMaxKpa;
        END_IF
        _eState := E_DL_FptState.eRun;         // 进运行相 / Enter run
    END_IF

E_DL_FptState.eRun:
    IF NOT bEnable THEN                        // 撤使能：输出冻结，回未使能 / Disable: freeze and idle
        _eState := E_DL_FptState.eIdle;
    END_IF

E_DL_FptState.eFault:
    ;                                          // 故障相：输出冻结保持，仅段 4 复位沿可迁出 / Frozen, reset only

ELSE
    _uFault := 16#0002_038A;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_FptCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_FptState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fOutKpa := _fOutKpa;                           // 输出出口 / Output outlet
fIntKpa := _fIntKpa;                           // 积分镜像 / Integral mirror
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    bWindup := FALSE;                          // 故障相抗饱和镜像强制 FALSE / Anti-windup forced false
ELSE
    nErrId := 16#0000_0000;                    // 无故障：本件无信息码 / No fault, no info code
    bWindup := _bWindupOn;                     // 抗饱和镜像 / Anti-windup mirror
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
