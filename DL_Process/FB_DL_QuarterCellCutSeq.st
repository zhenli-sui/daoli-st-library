(*
  FB_DL_QuarterCellCutSeq  —  极片分切顺控（刀轴相位 + 张力窗 + 废边回收） / Electrode slitting sequencer with blade phase, tension window and trim recovery
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : roadmap-li-p2 — 锂电极片分切工站真缺口
  溯源 Origin   : 道莅 clean-room 实现；刀轴相位对齐 + 张力窗监督 + 废边回收联锁为公开分切工艺逻辑，未复制任何源码行
  功能 Function : 1) 三段顺控：ePhase 刀轴相位对齐（fBladePhaseDeg 进目标容差带）→
                  eRun 分切运行（张力窗 fTensionN 双向监督 + 废边回收信号 bTrimOk 监督）→
                  eStop 收料停机（tStop 到时）→ eDone；2) 相位对齐超时保护；
                  3) 故障级单码 03A0，归因由 eCause 独立成员承载（R190）；
                  4) 信息级 04C8 = 分切循环完成沿；5) 解除式全当拍量（R240）。
  接口 Interface: 输入相位/张力/废边信号与复位位；输出状态/相位镜像/张力窗镜像/码
  边界 Boundary : ① 组态闸：fPhaseTolDeg <= 0.0、fTensionHiN <= fTensionLoN、tPhaseTmo <= T#0S、
                  tStop <= T#0S → 03A0 锁存；② 相位判据为双向容差式，相位量纲约定
                  0~360 单调注入（跨零归一由调用方完成，本件不内联 MOD 以免非标准扩展）；
                  ③ 浮点禁 = / <> 判等；④ 全部 TON / R_TRIG 段 0 无条件周期调用；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 03A0 / 信息窗口 04C8）:
    16#0005_03A0 故障级：分切故障总码（组态非法 / 相位对齐超时 / 张力越窗 / 废边回收异常），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04C8 信息级：分切循环完成沿（收料停机完成进 eDone 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 1 · 序号 4）
*)

TYPE E_DL_QcsState :
(
    eIdle  := 0,      // 未使能待启动 / Idle, waiting start
    ePhase := 10,     // 刀轴相位对齐中 / Blade phase alignment
    eRun   := 20,     // 分切运行（张力窗 + 废边监督） / Slitting under tension and trim supervision
    eStop  := 30,     // 收料停机中 / Web stop
    eDone  := 50,     // 循环完成 / Done
    eFault := 90      // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_QcsCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    ePhaseTmo   := 2, // 相位对齐超时 / Phase alignment timeout
    eTensionDev := 3, // 张力越窗 / Tension out of window
    eTrimLost   := 4  // 废边回收异常 / Trim recovery lost
);
END_TYPE

FUNCTION_BLOCK FB_DL_QuarterCellCutSeq
VAR_INPUT
    fBladePhaseDeg  : REAL := 0.0;       // 刀轴实测相位 [°]，0~360 单调注入 / Blade shaft phase
    fPhaseTgtDeg    : REAL := 90.0;      // 目标相位 [°] / Target phase
    fPhaseTolDeg    : REAL := 1.0;       // 相位容差带 [°]，域 > 0 / Phase tolerance
    fTensionN       : REAL := 0.0;       // 实测极片张力 [N] / Measured web tension
    fTensionLoN     : REAL := 20.0;      // 张力窗下限 [N] / Tension low limit
    fTensionHiN     : REAL := 60.0;      // 张力窗上限 [N] / Tension high limit
    bTrimOk         : BOOL := FALSE;     // 废边回收正常信号（电平）[-] / Trim recovery healthy
    tPhaseTmo       : TIME := T#5S;      // 相位对齐超时 [ms]，域 > 0 / Phase timeout
    tStop           : TIME := T#2S;      // 收料停机时长 [ms]，域 > 0 / Web stop duration
    bStart          : BOOL := FALSE;     // 启动命令（电平）[-] / Start command
    bReset          : BOOL := FALSE;     // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState          : E_DL_QcsState;     // 状态出口，段 6 单点映射 / State outlet
    eCause          : E_DL_QcsCause;     // 故障成因出口（R190） / Fault cause outlet
    fPhaseDegOut    : REAL;              // 相位镜像 [°] / Phase mirror
    bPhaseOk        : BOOL;              // 相位达窗镜像 [-] / Phase in-window mirror
    bTensionOk      : BOOL;              // 张力在窗镜像 [-] / Tension in-window mirror
    bCycleDone      : BOOL;              // 循环完成标志 [-] / Cycle done flag
    bError          : BOOL;              // 故障锁存标志 [-] / Fault latch flag
    nErrId          : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState         : E_DL_QcsState := E_DL_QcsState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause         : E_DL_QcsCause := E_DL_QcsCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonPhase        : TON;               // 相位对齐计时，每周期无条件调用 / Phase timer
    tonStop         : TON;               // 收料停机计时，每周期无条件调用 / Stop timer
    rtReset         : R_TRIG;            // 复位沿实例，每周期无条件调用 / Reset edge
    _bPhaseOk       : BOOL;              // 相位达窗当拍量 [-] / Phase verdict
    _bTensionOk     : BOOL;              // 张力在窗当拍量 [-] / Tension verdict
    _bCfgBad        : BOOL;              // 组态非法当拍量 [-] / Config illegal
    _bFault         : BOOL;              // 故障锁存位（锁存量） / Latched fault bit
    _uFault         : UDINT;             // 故障码锁存（锁存量） / Latched fault code
    _uInfo          : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 —— *)
_bPhaseOk := ABS(fBladePhaseDeg - fPhaseTgtDeg) <= fPhaseTolDeg;                 // 相位容差判据 / Phase tolerance verdict
_bTensionOk := (fTensionN >= fTensionLoN - 1.0E-6) AND (fTensionN <= fTensionHiN + 1.0E-6);  // 张力容差窗 / Tension window verdict
_bCfgBad := (fPhaseTolDeg <= 0.0) OR (fTensionHiN <= fTensionLoN)
            OR (tPhaseTmo <= T#0S) OR (tStop <= T#0S);                          // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                        // 复位沿，每拍必调 / Reset edge
tonPhase(IN := (_eState = E_DL_QcsState.ePhase), PT := tPhaseTmo);             // 相位对齐计时 / Phase timer
tonStop(IN := (_eState = E_DL_QcsState.eStop), PT := tStop);                   // 收料停机计时 / Stop timer

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
fPhaseDegOut := 0.0;               // 相位镜像缺省 0 / Phase mirror default
bPhaseOk := FALSE;                 // 相位镜像缺省 FALSE / Phase flag default
bTensionOk := FALSE;               // 张力镜像缺省 FALSE / Tension flag default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_QcsCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_QcsState.eFault THEN
        _eState := E_DL_QcsState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0005_03A0;                   // 故障级：分切故障总码 / Process fault code
    _eCause := E_DL_QcsCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF

(* —— 段 3：超时 / 张力越窗 / 废边异常（判据当拍量） —— *)
IF (NOT _bFault) AND tonPhase.Q THEN           // 相位对齐超时 / Phase timeout
    _uFault := 16#0005_03A0;
    _eCause := E_DL_QcsCause.ePhaseTmo;        // 归因：相位超时 / Cause: phase timeout
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_QcsState.eRun) AND (NOT _bTensionOk) THEN   // 运行期张力越窗 / Tension deviation
    _uFault := 16#0005_03A0;
    _eCause := E_DL_QcsCause.eTensionDev;      // 归因：张力越窗 / Cause: tension
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_QcsState.eRun) AND (NOT bTrimOk) THEN       // 废边回收异常 / Trim lost
    _uFault := 16#0005_03A0;
    _eCause := E_DL_QcsCause.eTrimLost;        // 归因：废边异常 / Cause: trim lost
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT tonPhase.Q —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT tonPhase.Q) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_QcsCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_QcsState.eFault) THEN
    _eState := E_DL_QcsState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_QcsState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动条件 / Start gate
        _eState := E_DL_QcsState.ePhase;       // 进相位对齐相 / Enter phase alignment
    END_IF

E_DL_QcsState.ePhase:
    IF _bPhaseOk THEN                          // 出口 1：相位达窗 / Phase reached
        _eState := E_DL_QcsState.eRun;         // 进分切运行相 / Enter slitting
    ELSIF NOT bStart THEN                      // 出口 2：撤启动（R98 双出口） / Start released
        _eState := E_DL_QcsState.eIdle;        // 回未使能 / Back to idle
    END_IF

E_DL_QcsState.eRun:
    IF NOT bStart THEN                         // 撤启动：进停机相 / Start released enters stop
        _eState := E_DL_QcsState.eStop;
    END_IF

E_DL_QcsState.eStop:
    IF tonStop.Q THEN                          // 停机计时到 / Stop elapsed
        _uInfo := 16#0005_04C8;                // 信息级：循环完成沿 / Info: cycle complete edge
        _eState := E_DL_QcsState.eDone;        // 进完成相 / Enter done
    END_IF

E_DL_QcsState.eDone:
    IF bStart THEN                             // 新循环请求 / New cycle request
        _eState := E_DL_QcsState.ePhase;       // 进相位相 / Enter phase
    END_IF

E_DL_QcsState.eFault:
    ;                                          // 故障相：仅段 4 复位沿可迁出 / Only reset exits

ELSE
    _uFault := 16#0005_03A0;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_QcsCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_QcsState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fPhaseDegOut := fBladePhaseDeg;                    // 相位镜像 / Phase mirror
bPhaseOk := _bPhaseOk AND (NOT _bFault);           // 相位达窗镜像 / Phase mirror
bTensionOk := _bTensionOk AND (NOT _bFault);       // 张力窗镜像 / Tension mirror
bCycleDone := (_eState = E_DL_QcsState.eDone);     // 完成标志 / Done flag
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
