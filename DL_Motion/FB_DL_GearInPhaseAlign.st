(*
  FB_DL_GearInPhaseAlign  —  电子齿轮啮合相位对齐（相位差窗 + 从轴偏置补偿） / Electronic gear-in phase alignment with phase-error window and slave offset compensation
  分类 Category : DL_Motion
  版本 Version  : 1.0.0
  来源 Source   : t1-6-plcopen — PLCopen Motion 接口映射层族深化
  溯源 Origin   : 道莅 clean-room 实现；从轴相位 = 主轴位置×传动比 + 偏置 为公开电子齿轮运动学关系，
                 本件仅做 MC_GearIn 前置相位判据与偏置补偿的映射层，不内联轨迹规划内核
  功能 Function : 1) 理想从轴相位 _fIdealDeg = fMasterPosDeg × fGearRatio；
                  2) 相位差 _fPhaseErrDeg = 归一化(fSlavePosDeg - _fIdealDeg - fPhaseTargetDeg)，
                  归一化按 ±360° 折算（除以常量 360.0，禁 MOD 非标准扩展）；
                  3) 判据：|相位差| <= fPhaseTolDeg → bInPhase（可啮合）；
                  4) 偏置补偿：补偿量按 -相位差 × fGainDegPerDeg 计算，钳制到
                  ±fOffsetMaxDeg 并限速（单次不超过 fOffsetStepDeg）；
                  5) 本件只有故障码、无信息码（派单硬约束）。
  接口 Interface: 输入主轴/从轴位置、传动比、目标相位、容差、偏置域；输出相位差与偏置
  边界 Boundary : ① 组态闸：fGearRatio <= 0.0、fPhaseTolDeg <= 0.0、fOffsetMaxDeg <= 0.0、
                  fOffsetStepDeg <= 0.0、fGainDegPerDeg <= 0.0 → 04A7 锁存；
                  ② 位置或传动比非有限（NaN 自反 + Inf 差值自减）→ 04A7 锁存，偏置冻结保持；
                  ③ 归一化除法除数为常量 360.0（无除零风险）；
                  ④ 一个 R_TRIG，段 0 无条件调用；⑤ 故障相迁出唯一路径 = bReset 上升沿；
                  ⑥ 零全局耦合：无 GVL / VAR_EXTERNAL / %I %Q %M 直接地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Motion 段 0004，故障窗口 04A7；本件无信息码）:
    16#0004_04A7 故障级：相位对齐故障总码（组态非法 / 位置或传动比非有限），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 4 · 序号 19）
*)

TYPE E_DL_GpaState :
(
    eIdle   := 0,     // 未使能待对齐 / Idle, waiting alignment
    eAlign  := 10,    // 相位对齐中（偏置补偿） / Aligning with offset compensation
    eReady  := 20,    // 相位在窗：可啮合 / In phase, gear-in permitted
    eFault  := 90     // 故障锁存相（偏置冻结） / Fault latched, offset frozen
);
END_TYPE

TYPE E_DL_GpaCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eNonFinite  := 2  // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_GearInPhaseAlign
VAR_INPUT
    fMasterPosDeg  : REAL := 0.0;      // 主轴位置 [°] / Master position
    fSlavePosDeg   : REAL := 0.0;      // 从轴位置 [°] / Slave position
    fGearRatio     : REAL := 1.0;      // 传动比 [从轴°/主轴°]，域 > 0 / Gear ratio
    fPhaseTargetDeg: REAL := 0.0;      // 目标相位差 [°] / Target phase difference
    fPhaseTolDeg   : REAL := 2.0;      // 相位差窗 [°]，域 > 0 / Phase window
    fGainDegPerDeg : REAL := 0.8;      // 补偿增益 [°/°]，域 > 0 / Compensation gain
    fOffsetMaxDeg  : REAL := 30.0;     // 偏置限幅 [°]，域 > 0 / Offset limit
    fOffsetStepDeg : REAL := 5.0;      // 单周期偏置步长 [°]，域 > 0 / Offset step
    bEnable        : BOOL := FALSE;    // 对齐使能（电平）[-] / Alignment enable
    bReset         : BOOL := FALSE;    // 复位命令，上升沿清故障与偏置 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState         : E_DL_GpaState;    // 状态出口，段 6 单点映射 / State outlet
    eCause         : E_DL_GpaCause;    // 故障成因出口（R190） / Fault cause outlet
    fPhaseErrDeg   : REAL;             // 归一化相位差 [°] / Normalised phase error
    fOffsetDeg     : REAL;             // 从轴偏置补偿 [°] / Slave offset compensation
    bInPhase       : BOOL;             // 相位在窗（MC_GearIn 许可）[-] / In-phase permit
    bError         : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId         : UDINT;            // 故障码，0 = 无故障（本件无信息码） / Fault code only
END_VAR
VAR
    _eState        : E_DL_GpaState := E_DL_GpaState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause        : E_DL_GpaCause := E_DL_GpaCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtReset        : R_TRIG;           // 复位沿实例，每周期无条件调用 / Reset edge
    _fOffsetDeg    : REAL;             // 偏置保持量（持久） / Offset holding slot
    _fIdealDeg     : REAL;             // 理想从轴相位 [°]（当拍量） / Ideal slave phase
    _fErrRawDeg    : REAL;             // 未归一化相位差 [°]（当拍量） / Raw phase error
    _fErrDeg       : REAL;             // 归一化相位差 [°]（当拍量） / Normalised phase error
    _fCmdDeg       : REAL;             // 目标偏置 [°]（当拍量） / Target offset
    _bInPhase      : BOOL;             // 相位在窗当拍量 [-] / In-phase verdict
    _bNonFin       : BOOL;             // 输入非有限当拍量 [-] / Non-finite input
    _bCfgBad       : BOOL;             // 组态非法当拍量 [-] / Config illegal
    _bFault        : BOOL;             // 故障锁存位（锁存量） / Latched fault bit
    _uFault        : UDINT;            // 故障码锁存（锁存量） / Latched fault code
END_VAR

(* —— 段 0：沿实例无条件周期刷新 + 相位差归一化（除数为常量 360.0） —— *)
_fIdealDeg := fMasterPosDeg * fGearRatio;                                    // 理想从轴相位 / Ideal slave phase
_fErrRawDeg := fSlavePosDeg - _fIdealDeg - fPhaseTargetDeg;                  // 未归一化相位差 / Raw phase error
_fErrDeg := _fErrRawDeg;                                                     // 归一化初值 / Normalisation start
IF _fErrDeg > 180.0 THEN                                                     // 超半周：折算到负半周 / Wrap to negative half
    _fErrDeg := _fErrDeg - 360.0;
ELSIF _fErrDeg < -180.0 THEN                                                 // 低于负半周：折算到正半周 / Wrap to positive half
    _fErrDeg := _fErrDeg + 360.0;
END_IF
_bInPhase := ABS(_fErrDeg) <= fPhaseTolDeg;                                  // 相位窗判据（容差式） / Phase window verdict
_bNonFin := (fMasterPosDeg <> fMasterPosDeg) OR (fSlavePosDeg <> fSlavePosDeg) OR (fGearRatio <> fGearRatio)
         OR ((fMasterPosDeg - fMasterPosDeg) <> (fMasterPosDeg - fMasterPosDeg))
         OR ((fSlavePosDeg - fSlavePosDeg) <> (fSlavePosDeg - fSlavePosDeg))
         OR ((fGearRatio - fGearRatio) <> (fGearRatio - fGearRatio));        // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (fGearRatio <= 0.0) OR (fPhaseTolDeg <= 0.0) OR (fOffsetMaxDeg <= 0.0)
            OR (fOffsetStepDeg <= 0.0) OR (fGainDegPerDeg <= 0.0);           // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                      // 复位沿，每拍必调 / Reset edge

(* —— 段 1：单拍量预清零（锁存量与偏置保持量不入清单） —— *)
fPhaseErrDeg := 0.0;               // 相位差出口缺省 0 / Phase error default
bInPhase := FALSE;                 // 在窗镜像缺省 FALSE（安全侧） / In-phase default safe
nErrId := 16#0000_0000;            // 故障码缺省无故障 / Fault code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_GpaCause.eNone;            // 清成因（锁存量） / Clear cause
    _fOffsetDeg := 0.0;                        // 清偏置保持量（锁存量） / Clear offset
    IF _eState = E_DL_GpaState.eFault THEN
        _eState := E_DL_GpaState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0004_04A7;                   // 故障级：相位对齐故障总码 / Motion fault code
    _eCause := E_DL_GpaCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0004_04A7;
    _eCause := E_DL_GpaCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：偏置补偿（目标偏置 → 限幅 → 限速；仅无故障且未在窗时动作） —— *)
IF (NOT _bFault) AND (_eState = E_DL_GpaState.eAlign) AND (NOT _bInPhase) THEN
    _fCmdDeg := -_fErrDeg * fGainDegPerDeg;                    // 反向补偿目标 / Target compensation
    IF _fCmdDeg > fOffsetMaxDeg THEN                           // 偏置上限钳制 / Offset high clamp
        _fCmdDeg := fOffsetMaxDeg;
    ELSIF _fCmdDeg < -fOffsetMaxDeg THEN                       // 偏置下限钳制 / Offset low clamp
        _fCmdDeg := -fOffsetMaxDeg;
    END_IF
    IF (_fCmdDeg - _fOffsetDeg) > fOffsetStepDeg THEN          // 向上限速 / Upward rate limit
        _fOffsetDeg := _fOffsetDeg + fOffsetStepDeg;
    ELSIF (_fOffsetDeg - _fCmdDeg) > fOffsetStepDeg THEN       // 向下限速 / Downward rate limit
        _fOffsetDeg := _fOffsetDeg - fOffsetStepDeg;
    ELSE
        _fOffsetDeg := _fCmdDeg;                               // 直接跟随 / Follow target
    END_IF
    IF _fOffsetDeg > fOffsetMaxDeg THEN                        // 限速后二次复核上限 / Post-limit high
        _fOffsetDeg := fOffsetMaxDeg;
    ELSIF _fOffsetDeg < -fOffsetMaxDeg THEN                    // 限速后二次复核下限 / Post-limit low
        _fOffsetDeg := -fOffsetMaxDeg;
    END_IF
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_GpaCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（偏置冻结保持） —— *)
IF _bFault AND (_eState <> E_DL_GpaState.eFault) THEN
    _eState := E_DL_GpaState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_GpaState.eIdle:
    IF bEnable AND (NOT _bFault) THEN          // 使能条件 / Enable gate
        _fOffsetDeg := 0.0;                    // 起始偏置清零（无扰） / Reset offset on start
        _eState := E_DL_GpaState.eAlign;       // 进对齐相 / Enter alignment
    END_IF

E_DL_GpaState.eAlign:
    IF _bInPhase THEN                          // 出口 1：相位在窗 / In phase
        _eState := E_DL_GpaState.eReady;       // 进可啮合相 / Enter ready
    ELSIF NOT bEnable THEN                     // 出口 2：撤使能（前置消失） / Disable
        _eState := E_DL_GpaState.eIdle;
    END_IF

E_DL_GpaState.eReady:
    IF NOT _bInPhase THEN                      // 相位漂出窗口：回对齐相 / Phase drifted out
        _eState := E_DL_GpaState.eAlign;
    ELSIF NOT bEnable THEN                     // 撤使能：回未使能 / Disable returns idle
        _eState := E_DL_GpaState.eIdle;
    END_IF

E_DL_GpaState.eFault:
    ;                                          // 故障相：偏置冻结，仅段 4 复位沿可迁出 / Frozen, reset only

ELSE
    _uFault := 16#0004_04A7;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_GpaCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_GpaState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；故障相偏置冻结、许可撤销） —— *)
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
    fPhaseErrDeg := 0.0;                       // 故障相相位差出口强制 0 / Error forced zero
    bInPhase := FALSE;                         // 故障相啮合许可强制撤销（安全侧） / Permit forced off
    fOffsetDeg := _fOffsetDeg;                 // 故障相偏置冻结保持 / Offset frozen
ELSE
    nErrId := 16#0000_0000;                    // 无故障：本件无信息码 / No fault, no info code
    fPhaseErrDeg := _fErrDeg;                  // 相位差出口 / Error outlet
    bInPhase := _bInPhase;                     // 啮合许可出口 / Permit outlet
    fOffsetDeg := _fOffsetDeg;                 // 偏置出口 / Offset outlet
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
