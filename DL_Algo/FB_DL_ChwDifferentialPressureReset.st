(*
  FB_DL_ChwDifferentialPressureReset  —  冷冻水压差重置（阀位反馈反算设定 + 死区保持） / Chilled-water differential-pressure reset by valve-position back-calculation with deadband hold
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇冷冻水压差重置算法族深化
  溯源 Origin   : 道莅 clean-room 实现；阀位反馈线性反算压差设定 + 死区保持 + 限速为公开水系统节能算法，未复制任何源码行
  功能 Function : 1) 反算：fDpSpRawKpa = fDpBaseKpa + fDpGainKpaPerPct × (fValveFbPct - fValveTargetPct)
                  （阀位大于目标阀位意味着压差不足 → 抬高设定）；
                  2) 死区保持：|反算值 - 当前输出| < fDeadbandKpa 时输出保持不变；
                  3) 限速：单次调用变化量不超过 fMaxStepKpa（与逐周期积分爬坡不同，本件为
                  反算直给的限速钳制，超限时按步长逼近）；
                  4) 硬限幅 [fDpMinKpa, fDpMaxKpa]，限幅后二次复核；
                  5) 本件只有故障码、无信息码（派单硬约束）。
  接口 Interface: 输入阀位反馈/目标阀位/基准/增益/死区/步长/上下限；输出压差设定
  边界 Boundary : ① 组态闸：fDpMaxKpa <= fDpMinKpa、fMaxStepKpa <= 0.0、fDeadbandKpa < 0.0、
                  fDpGainKpaPerPct <= 0.0 → 0388 锁存；
                  ② 阀位与压差量非有限（NaN 自反 + Inf 差值自减）→ 0388 锁存，设定冻结保持
                  （R191：语义为冻结保持，非降级置标志）；
                  ③ 浮点判据全容差式；④ 仅一个 R_TRIG 复位沿，段 0 无条件调用；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Algo 段 0002，故障窗口 0388；本件无信息码）:
    16#0002_0388 故障级：压差重置故障总码（组态非法 / 阀位或压差量非有限），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 3 · 序号 12）
*)

TYPE E_DL_CdpState :
(
    eIdle   := 0,     // 未使能：设定冻结 / Idle, setpoint frozen
    eRun    := 10,    // 反算运行中 / Back-calculation active
    eFault  := 90     // 故障锁存相（设定冻结保持） / Fault latched, setpoint frozen
);
END_TYPE

TYPE E_DL_CdpCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2  // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChwDifferentialPressureReset
VAR_INPUT
    fValveFbPct       : REAL := 0.0;     // 末端阀位反馈 [%]，0~100 / Terminal valve feedback
    fValveTargetPct   : REAL := 85.0;    // 目标阀位 [%]，开区间 (0,100) / Target valve position
    fDpBaseKpa        : REAL := 150.0;   // 压差基准 [kPa] / Base differential pressure
    fDpGainKpaPerPct  : REAL := 2.0;     // 反算增益 [kPa/%]，域 > 0 / Back-calculation gain
    fDeadbandKpa      : REAL := 3.0;     // 死区 [kPa]，域 >= 0 / Deadband
    fMaxStepKpa       : REAL := 10.0;    // 单次限速步长 [kPa]，域 > 0 / Rate limit step
    fDpMinKpa         : REAL := 50.0;    // 压差设定下限 [kPa] / Setpoint low limit
    fDpMaxKpa         : REAL := 300.0;   // 压差设定上限 [kPa] / Setpoint high limit
    fDpInitKpa        : REAL := 150.0;   // 设定初值（使能沿装载） [kPa] / Initial setpoint
    bEnable           : BOOL := FALSE;   // 反算使能（电平）[-] / Reset enable
    bReset            : BOOL := FALSE;   // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState            : E_DL_CdpState;   // 状态出口，段 6 单点映射 / State outlet
    eCause            : E_DL_CdpCause;   // 故障成因出口（R190） / Fault cause outlet
    fDpSpKpa          : REAL;            // 压差设定输出 [kPa] / Differential pressure setpoint
    fDpSpRawKpa       : REAL;            // 反算原始值镜像 [kPa] / Raw back-calculated value
    bDbHold           : BOOL;            // 死区保持镜像 [-] / Deadband hold mirror
    bError            : BOOL;            // 故障锁存标志 [-] / Fault latch flag
    nErrId            : UDINT;           // 故障码，0 = 无故障（本件无信息码） / Fault code only
END_VAR
VAR
    _eState           : E_DL_CdpState := E_DL_CdpState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause           : E_DL_CdpCause := E_DL_CdpCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtEnable          : R_TRIG;          // 使能沿实例，每周期无条件调用 / Enable edge
    rtReset           : R_TRIG;          // 复位沿实例，每周期无条件调用 / Reset edge
    _fSp              : REAL;            // 设定保持槽（持久） / Setpoint holding slot
    _fRawKpa          : REAL;            // 反算原始值 [kPa]（当拍量） / Raw value
    _fCandKpa         : REAL;            // 限幅-限速后候选 [kPa]（当拍量） / Candidate value
    _bDbHoldOn        : BOOL;            // 死区保持当拍量 [-] / Deadband hold flag
    _bNonFin          : BOOL;            // 输入非有限当拍量 [-] / Non-finite input
    _bCfgBad          : BOOL;            // 组态非法当拍量 [-] / Config illegal
    _bFault           : BOOL;            // 故障锁存位（锁存量） / Latched fault bit
    _uFault           : UDINT;           // 故障码锁存（锁存量） / Latched fault code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 当拍量判据 —— *)
_fRawKpa := fDpBaseKpa + fDpGainKpaPerPct * (fValveFbPct - fValveTargetPct);   // 阀位反算压差 [kPa] / Back-calculated pressure
_bNonFin := (fValveFbPct <> fValveFbPct) OR (fDpBaseKpa <> fDpBaseKpa)
         OR ((fValveFbPct - fValveFbPct) <> (fValveFbPct - fValveFbPct))
         OR ((fDpBaseKpa - fDpBaseKpa) <> (fDpBaseKpa - fDpBaseKpa));           // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (fDpMaxKpa <= fDpMinKpa) OR (fMaxStepKpa <= 0.0) OR (fDeadbandKpa < 0.0)
            OR (fDpGainKpaPerPct <= 0.0) OR (fValveTargetPct <= 0.0) OR (fValveTargetPct >= 100.0);   // 组态非法当拍量 / Config illegal
rtEnable(CLK := bEnable);                                                       // 使能沿，每拍必调 / Enable edge
rtReset(CLK := bReset);                                                         // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量与设定保持槽不入清单） —— *)
fDpSpRawKpa := 0.0;                // 反算镜像缺省 0 / Raw mirror default
bDbHold := FALSE;                  // 死区镜像缺省 FALSE / Deadband default
nErrId := 16#0000_0000;            // 故障码缺省无故障 / Fault code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CdpCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_CdpState.eFault THEN
        _eState := E_DL_CdpState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0002_0388;                   // 故障级：重置故障总码 / Algo fault code
    _eCause := E_DL_CdpCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0002_0388;
    _eCause := E_DL_CdpCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：反算 + 死区 + 限速 + 限幅（仅运行相且无故障） —— *)
IF (NOT _bFault) AND (_eState = E_DL_CdpState.eRun) THEN
    _fCandKpa := _fRawKpa;                                 // 候选 = 反算原始值 / Candidate from raw
    IF _fCandKpa < fDpMinKpa THEN                          // 下限钳制 / Low clamp
        _fCandKpa := fDpMinKpa;
    ELSIF _fCandKpa > fDpMaxKpa THEN                       // 上限钳制 / High clamp
        _fCandKpa := fDpMaxKpa;
    END_IF
    IF ABS(_fCandKpa - _fSp) < fDeadbandKpa THEN           // 死区内保持（容差式） / Deadband hold
        _bDbHoldOn := TRUE;
    ELSIF (_fCandKpa - _fSp) > fMaxStepKpa THEN            // 向上限速 / Upward rate limit
        _fSp := _fSp + fMaxStepKpa;
    ELSIF (_fSp - _fCandKpa) > fMaxStepKpa THEN            // 向下限速 / Downward rate limit
        _fSp := _fSp - fMaxStepKpa;
    ELSE
        _fSp := _fCandKpa;                                 // 直接跟随反算值 / Follow candidate
    END_IF
    IF _fSp < fDpMinKpa THEN                               // 限速后二次下限复核 / Post-limit low check
        _fSp := fDpMinKpa;
    ELSIF _fSp > fDpMaxKpa THEN                            // 限速后二次上限复核 / Post-limit high check
        _fSp := fDpMaxKpa;
    END_IF
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CdpCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（设定冻结保持） —— *)
IF _bFault AND (_eState <> E_DL_CdpState.eFault) THEN
    _eState := E_DL_CdpState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_CdpState.eIdle:
    IF rtEnable.Q AND (NOT _bFault) THEN       // 使能上升沿：装载初值并钳制 / Enable edge loads initial value
        _fSp := fDpInitKpa;                    // 装载初值 / Load initial setpoint
        IF _fSp < fDpMinKpa THEN               // 初值下限钳制 / Initial low clamp
            _fSp := fDpMinKpa;
        ELSIF _fSp > fDpMaxKpa THEN            // 初值上限钳制 / Initial high clamp
            _fSp := fDpMaxKpa;
        END_IF
        _eState := E_DL_CdpState.eRun;         // 进运行相 / Enter run
    END_IF

E_DL_CdpState.eRun:
    IF NOT bEnable THEN                        // 撤使能：设定冻结，回未使能 / Disable: freeze and idle
        _eState := E_DL_CdpState.eIdle;
    END_IF

E_DL_CdpState.eFault:
    ;                                          // 故障相：设定冻结保持，仅段 4 复位沿可迁出 / Frozen, reset only

ELSE
    _uFault := 16#0002_0388;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_CdpCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_CdpState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fDpSpKpa := _fSp;                              // 设定值出口 / Setpoint outlet
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    fDpSpRawKpa := 0.0;                        // 故障相反算镜像强制 0 / Raw mirror forced zero
    bDbHold := FALSE;                          // 故障相死区镜像强制 FALSE / Deadband forced false
ELSE
    nErrId := 16#0000_0000;                    // 无故障：本件无信息码 / No fault, no info code
    fDpSpRawKpa := _fRawKpa;                   // 反算镜像 / Raw mirror
    bDbHold := _bDbHoldOn;                     // 死区镜像 / Deadband mirror
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
