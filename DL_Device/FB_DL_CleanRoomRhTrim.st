(*
  FB_DL_CleanRoomRhTrim  —  洁净室加湿阀脉冲微调（RH 偏差 + 最小开度保护） / Clean-room humidifier pulse trim with RH deviation and minimum-opening protection
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇洁净室湿度控制族深化
  溯源 Origin   : 道莅 clean-room 实现；脉宽调制加湿（PWM 占空比 + 最小开度 + 高限停加湿）为公开洁净室湿度算法，未复制任何源码行
  功能 Function : 1) 每个脉冲周期起始重算占空比：duty = fKpPctPerPct × (fRhSpPct - fRhPct)，
                  钳制到 [0.0, 100.0]；
                  2) 最小开度保护：fRhPct 低于 fRhLoPct 时 duty 取 max(duty, fMinOpenPct)；
                  3) 高限停加湿：fRhPct 高于 fRhHiPct 时 duty 强制 0（防过湿）；
                  4) 脉宽：开阀时长 = duty × tPeriod / 100.0（除数常量 100.0），关阀时长 = 周期余量；
                  5) 故障级单码 052B / 信息级 0431 = 脉冲周期完成沿（每周期单拍）。
  接口 Interface: 输入 RH 设定/实测/上下限/增益/最小开度/周期；输出阀指令与占空比镜像
  边界 Boundary : ① 组态闸：tPeriod <= T#0S、fMinOpenPct 不在 [0,100]、fKpPctPerPct <= 0.0、
                  fRhHiPct <= fRhLoPct、fRhSpPct 不在 [0,100] → 052B 锁存；
                  ② RH 非有限（NaN 自反 + Inf 差值自减）→ 052B 锁存，阀指令强制关断；
                  ③ 占空比开阀时长按实数乘除后转 TIME，转换前钳制到 [0, tPeriod] 防越界；
                  ④ 两个 TON 段 0 无条件周期调用，IN 由相位/占空比派生，相内自动复位 ET；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Device 分段见下，故障窗口 052B / 信息窗口 0431）:
    16#0003_052B 故障级：加湿脉冲故障总码（组态非法 / RH 非有限），锁存至 bReset 上升沿；
                 归因见 eCause，不新增码位（派单硬约束单码）
    16#0003_0431 信息级：脉冲周期完成沿（占空比重算单拍）
    分段理由：段 0003 故障带 03A0~03FF 于 R42 用尽，启用 05xx 副带续编，避开 0590~0599 判错位段。
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 3 · 序号 15）
*)

TYPE E_DL_CrhState :
(
    eIdle  := 0,      // 未使能：阀关 / Idle, valve closed
    ePulse := 10,     // 脉冲调制中（开/关按时长切换） / Pulse modulation
    eFault := 90      // 故障锁存相（阀强制关） / Fault latched, valve forced closed
);
END_TYPE

TYPE E_DL_CrhCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2  // RH 非有限 / Non-finite RH
);
END_TYPE

FUNCTION_BLOCK FB_DL_CleanRoomRhTrim
VAR_INPUT
    fRhSpPct      : REAL := 45.0;      // RH 设定 [%]，域 [0,100] / RH setpoint
    fRhPct        : REAL := 0.0;       // RH 实测 [%] / Measured RH
    fRhLoPct      : REAL := 40.0;      // 低限（触发最小开度） [%] / Low limit for minimum opening
    fRhHiPct      : REAL := 55.0;      // 高限（停加湿） [%] / High limit stopping humidification
    fKpPctPerPct  : REAL := 8.0;       // 比例增益 [%/ %]，域 > 0 / Proportional gain
    fMinOpenPct   : REAL := 10.0;      // 最小开度 [%]，域 [0,100] / Minimum opening
    tPeriod       : TIME := T#10S;     // 脉冲周期 [ms]，域 > 0 / Pulse period
    bEnable       : BOOL := FALSE;     // 加湿使能（电平）[-] / Humidification enable
    bReset        : BOOL := FALSE;     // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState        : E_DL_CrhState;     // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_CrhCause;     // 故障成因出口（R190） / Fault cause outlet
    bHumValve     : BOOL;              // 加湿阀指令 [-] / Humidifier valve command
    fDutyPct      : REAL;              // 占空比镜像 [%] / Duty mirror
    bMinOpen      : BOOL;              // 最小开度生效镜像 [-] / Minimum opening active
    bCycleDone    : BOOL;              // 脉冲周期完成标志 [-] / Pulse period done flag
    bError        : BOOL;              // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState       : E_DL_CrhState := E_DL_CrhState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_CrhCause := E_DL_CrhCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonOn         : TON;               // 开阀时长计时，每周期无条件调用 / Valve-on timer
    tonOff        : TON;               // 关阀时长计时，每周期无条件调用 / Valve-off timer
    rtReset       : R_TRIG;            // 复位沿实例，每周期无条件调用 / Reset edge
    _fDutyPct     : REAL;              // 占空比保持量（本周期内恒定） / Duty held for the period
    _fOnMs        : REAL;              // 本周期开阀时长 [ms]（钳制后） / On-time in ms
    _fOffMs       : REAL;              // 本周期关阀时长 [ms] / Off-time in ms
    _bOnPhase     : BOOL;              // 当前处于开阀段（内部相位标志） / In on-segment flag
    _bMinOpenOn   : BOOL;              // 最小开度生效当拍量 [-] / Minimum opening flag
    _bNonFin      : BOOL;              // RH 非有限当拍量 [-] / Non-finite RH
    _bCfgBad      : BOOL;              // 组态非法当拍量 [-] / Config illegal
    _bFault       : BOOL;              // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;             // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 + 当拍量判据 —— *)
_bNonFin := (fRhPct <> fRhPct) OR (fRhSpPct <> fRhSpPct)
         OR ((fRhPct - fRhPct) <> (fRhPct - fRhPct))
         OR ((fRhSpPct - fRhSpPct) <> (fRhSpPct - fRhSpPct));                 // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (tPeriod <= T#0S) OR (fKpPctPerPct <= 0.0) OR (fRhHiPct <= fRhLoPct)
            OR (fMinOpenPct < 0.0) OR (fMinOpenPct > 100.0)
            OR (fRhSpPct < 0.0) OR (fRhSpPct > 100.0);                        // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                       // 复位沿，每拍必调 / Reset edge
tonOn(IN := (_bOnPhase AND (_eState = E_DL_CrhState.ePulse)), PT := REAL_TO_TIME(_fOnMs));    // 开阀计时（实数时长转 TIME） / On timer
tonOff(IN := (NOT _bOnPhase) AND (_eState = E_DL_CrhState.ePulse), PT := REAL_TO_TIME(_fOffMs));  // 关阀计时 / Off timer

(* —— 段 1：单拍量预清零（锁存量与占空比保持量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
bHumValve := FALSE;                // 阀指令缺省关 / Valve command default closed
fDutyPct := 0.0;                   // 占空比出口缺省 0 / Duty default
bMinOpen := FALSE;                 // 最小开度镜像缺省 FALSE / Minimum opening default
bCycleDone := FALSE;               // 周期完成标志缺省 FALSE / Period done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CrhCause.eNone;            // 清成因（锁存量） / Clear cause
    _fDutyPct := 0.0;                          // 清占空比保持量 / Clear duty
    _bOnPhase := FALSE;                        // 清开阀段标志 / Clear on-segment
    IF _eState = E_DL_CrhState.eFault THEN
        _eState := E_DL_CrhState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0003_052B;                   // 故障级：加湿脉冲故障总码（05xx 副带） / Device fault code
    _eCause := E_DL_CrhCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0003_052B;
    _eCause := E_DL_CrhCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：占空比重算（周期边界 = 关阀段结束或首次进入） —— *)
IF (NOT _bFault) AND (_eState = E_DL_CrhState.ePulse) AND tonOff.Q THEN
    _fDutyPct := fKpPctPerPct * (fRhSpPct - fRhPct);                  // 比例占空比 [%] / Proportional duty
    IF fRhPct < fRhLoPct THEN                                        // 低限：最小开度保护 / Low limit protection
        IF _fDutyPct < fMinOpenPct THEN
            _fDutyPct := fMinOpenPct;                                // 抬到最小开度 / Raise to minimum
            _bMinOpenOn := TRUE;
        END_IF
    END_IF
    IF fRhPct > fRhHiPct THEN                                        // 高限：停加湿 / High limit stops humidification
        _fDutyPct := 0.0;
        _bMinOpenOn := FALSE;
    END_IF
    IF _fDutyPct < 0.0 THEN                                          // 占空比下限钳制 / Duty low clamp
        _fDutyPct := 0.0;
    ELSIF _fDutyPct > 100.0 THEN                                     // 占空比上限钳制 / Duty high clamp
        _fDutyPct := 100.0;
    END_IF
    _fOnMs := _fDutyPct / 100.0 * TIME_TO_REAL(tPeriod);             // 开阀时长 [ms]（除常量 100.0） / On-time
    IF _fOnMs < 0.0 THEN                                             // 时长下限钳制（防负数） / On-time low clamp
        _fOnMs := 0.0;
    ELSIF _fOnMs > TIME_TO_REAL(tPeriod) THEN                        // 时长上限钳制（不越周期） / On-time high clamp
        _fOnMs := TIME_TO_REAL(tPeriod);
    END_IF
    _fOffMs := TIME_TO_REAL(tPeriod) - _fOnMs;                       // 关阀时长 = 周期余量 / Off-time remainder
    _uInfo := 16#0003_0431;                                          // 信息级：脉冲周期完成沿 / Info: period done edge
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CrhCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（阀强制关） —— *)
IF _bFault AND (_eState <> E_DL_CrhState.eFault) THEN
    _eState := E_DL_CrhState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_CrhState.eIdle:
    IF bEnable AND (NOT _bFault) THEN          // 使能条件 / Enable gate
        _fDutyPct := 0.0;                      // 起始占空比 0 / Start duty zero
        _fOnMs := 0.0;                         // 起始开阀时长 0 / Start on-time zero
        _fOffMs := TIME_TO_REAL(tPeriod);      // 起始关阀时长 = 整周期 / Start off-time full period
        _bOnPhase := FALSE;                    // 从关阀段起步 / Start in off-segment
        _eState := E_DL_CrhState.ePulse;       // 进脉冲相 / Enter pulse
    END_IF

E_DL_CrhState.ePulse:
    IF _bOnPhase THEN                          // 开阀段 / On-segment
        bHumValve := TRUE;                     // 阀开 / Valve open
        IF tonOn.Q THEN                        // 开阀到时 / On-time elapsed
            _bOnPhase := FALSE;                // 转关阀段 / Switch to off-segment
        END_IF
    ELSE
        bHumValve := FALSE;                    // 阀关 / Valve closed
        IF (_fOnMs > 0.0) AND tonOff.Q THEN    // 关阀到时且有开阀时长 / Off-time elapsed with on-time
            _bOnPhase := TRUE;                 // 转开阀段 / Switch to on-segment
        ELSIF (_fOnMs <= 0.0) AND tonOff.Q THEN
            ;                                  // 零占空比：保持关阀（周期照常走完） / Zero duty keeps valve closed
            _bOnPhase := FALSE;
        END_IF
    END_IF
    IF NOT bEnable THEN                        // 撤使能：阀关，回未使能 / Disable closes valve
        _bOnPhase := FALSE;
        _eState := E_DL_CrhState.eIdle;
    END_IF

E_DL_CrhState.eFault:
    ;                                          // 故障相：阀强制关，仅段 4 复位沿可迁出 / Valve closed, reset only

ELSE
    _uFault := 16#0003_052B;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_CrhCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_CrhState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；故障相阀强制关断） —— *)
IF _bFault THEN
    bHumValve := FALSE;                        // 故障相阀强制关（安全侧） / Valve forced closed
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    fDutyPct := 0.0;                           // 故障相占空比强制 0 / Duty forced zero
    bMinOpen := FALSE;                         // 故障相最小开度镜像强制 FALSE / Minimum opening forced false
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
    fDutyPct := _fDutyPct;                     // 占空比镜像 / Duty mirror
    bMinOpen := _bMinOpenOn;                   // 最小开度镜像 / Minimum opening mirror
END_IF
bCycleDone := (_eState = E_DL_CrhState.ePulse) AND tonOff.Q;   // 周期完成标志（当拍量） / Period done flag
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
