(*
  FB_DL_StakingPressCtrl  —  叠片台压装顺控（对齐-压紧-保压-泄压 + 压力窗判据） / Stacking-table press-fit sequencer with pressure-window verdict
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : roadmap-li-p1 — 锂电叠片工站压装顺控真缺口
  溯源 Origin   : 道莅 clean-room 实现；压装四段（对齐/压紧/保压/泄压）时序与压力窗判据为公开工艺逻辑，未复制任何源码行
  功能 Function : 1) 四段顺控：eAlign 对齐（等 bAlignInPos 且 tAlign 到时）→ ePress 压紧
                  （等 fPressMpa >= fWinLoMpa）→ eHold 保压（tHold 计时，窗内保持）→
                  eVent 泄压（tVent 计时）→ eDone；2) 压力窗判据：保压相 fPressMpa 越
                  [fWinLoMpa, fWinHiMpa] 即故障；3) 超时保护：对齐/压紧/泄压三相各有独立
                  TON，超时即故障；4) 故障级单码 039D，归因由 eCause 独立枚举成员承载
                  （组态非法/对齐超时/压紧超时/保压越窗/泄压超时，R190 归因唯一）；
                  5) 信息级 04C5 = 压装循环完成沿；6) 解除式全当拍量（R240）。
  接口 Interface: 输入 8 个工艺量 + 4 个时间量 + 3 个命令位；输出状态/压力镜像/原因/故障码
  边界 Boundary : ① 组态闸：fWinLoMpa < 0.0、fWinHiMpa <= fWinLoMpa、四个时间量 <= T#0S
                  任一成立 → 039D 锁存且 eCause = eCfgIllegal；
                  ② 浮点比较全部容差式（ABS 差值 < 1.0E-6），禁 = / <> 判等；
                  ③ 四个 TON 实例均在段 0 无条件每周期调用，IN 由相位判据派生，相切换
                  自动复位 ET，无跨相残留（R176）；
                  ④ 故障相迁出唯一路径 = bReset 上升沿（段 4 承载），禁死锁；
                  ⑤ 零全局耦合：无 GVL / VAR_EXTERNAL / %I %Q %M 直接地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 039D / 信息窗口 04C5）:
    16#0005_039D 故障级：压装故障总码（组态非法 / 对齐超时 / 压紧超时 / 保压越窗 / 泄压超时），
                 锁存至 bReset 上升沿；逐成因归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04C5 信息级：压装循环完成沿（泄压完成进 eDone 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 1 · 序号 1）
*)

TYPE E_DL_SpcState :
(
    eIdle   := 0,     // 未使能待启动 / Idle, waiting for start
    eAlign  := 10,    // 对齐中，等对位信号 / Aligning, waiting alignment
    ePress  := 20,    // 压紧中，等压力达窗下限 / Pressing, waiting pressure reaching window
    eHold   := 30,    // 保压中，计时并在窗内保持 / Holding with window supervision
    eVent   := 40,    // 泄压中，等泄压到时 / Venting, waiting vent time
    eDone   := 50,    // 循环完成，待撤启动 / Done, waiting start release
    eFault  := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_SpcCause :
(
    eNone        := 0,    // 无故障成因 / No cause
    eCfgIllegal  := 1,    // 组态非法（窗口/时间域非法） / Illegal configuration
    eAlignTmo    := 2,    // 对齐超时 / Alignment timeout
    ePressTmo    := 3,    // 压紧超时（未达窗下限） / Press timeout
    eHoldDev     := 4,    // 保压越窗 / Hold pressure out of window
    eVentTmo     := 5     // 泄压超时 / Vent timeout
);
END_TYPE

FUNCTION_BLOCK FB_DL_StakingPressCtrl
VAR_INPUT
    fPressMpa    : REAL := 0.0;        // 实测压装压力 [MPa] / Measured press force
    fWinLoMpa    : REAL := 2.0;        // 压力窗下限 [MPa]，域 >= 0 / Pressure window low limit
    fWinHiMpa    : REAL := 6.0;        // 压力窗上限 [MPa]，域 > 下限 / Pressure window high limit
    tAlign       : TIME := T#2S;       // 对齐超时 [ms]，域 > 0 / Alignment timeout
    tPress       : TIME := T#3S;       // 压紧超时 [ms]，域 > 0 / Press timeout
    tHold        : TIME := T#5S;       // 保压时长 [ms]，域 > 0 / Hold duration
    tVent        : TIME := T#1S;       // 泄压时长 [ms]，域 > 0 / Vent duration
    bAlignInPos  : BOOL := FALSE;      // 对位到位信号（电平）[-] / Alignment-in-position
    bStart       : BOOL := FALSE;      // 启动命令（电平）[-] / Start command, level
    bReset       : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_SpcState;      // 状态出口，段 6 单点映射 / State outlet
    eCause       : E_DL_SpcCause;      // 故障成因出口（R190 归因唯一） / Fault cause outlet
    fPressMpaOut : REAL;               // 压力镜像 [MPa] / Pressure mirror
    bInWindow    : BOOL;               // 压力在窗内镜像 [-] / Pressure-in-window mirror
    bCycleDone   : BOOL;               // 循环完成标志（eDone 电平）[-] / Cycle done flag
    bError       : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState      : E_DL_SpcState := E_DL_SpcState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_SpcCause := E_DL_SpcCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonAlign     : TON;                // 对齐计时实例，每周期无条件调用 / Align timer
    tonPress     : TON;                // 压紧计时实例，每周期无条件调用 / Press timer
    tonHold      : TON;                // 保压计时实例，每周期无条件调用 / Hold timer
    tonVent      : TON;                // 泄压计时实例，每周期无条件调用 / Vent timer
    rtReset      : R_TRIG;             // 复位沿实例，每周期无条件调用 / Reset edge
    _bWinOk      : BOOL;               // 压力在窗内当拍量 [-] / Pressure in window, current scan
    _bCfgBad     : BOOL;               // 组态非法当拍量 [-] / Illegal configuration, current scan
    _bFault      : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;              // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新（禁置于 IF/CASE 内，IN 由相位判据派生） —— *)
_bWinOk := (fPressMpa >= fWinLoMpa - 1.0E-6) AND (fPressMpa <= fWinHiMpa + 1.0E-6);  // 压力窗判据（容差式） / Window verdict with tolerance
_bCfgBad := (fWinLoMpa < 0.0) OR (fWinHiMpa <= fWinLoMpa)
            OR (tAlign <= T#0S) OR (tPress <= T#0S) OR (tHold <= T#0S) OR (tVent <= T#0S);  // 组态非法当拍量 / Config-illegal current scan
rtReset(CLK := bReset);                                   // 复位沿，每拍必调 / Reset edge refresh
tonAlign(IN := (_eState = E_DL_SpcState.eAlign), PT := tAlign);   // 对齐计时，相外自动复位 ET / Align timer, ET reset out of phase
tonPress(IN := (_eState = E_DL_SpcState.ePress), PT := tPress);   // 压紧计时，相外自动复位 ET / Press timer
tonHold(IN := (_eState = E_DL_SpcState.eHold), PT := tHold);      // 保压计时，相外自动复位 ET / Hold timer
tonVent(IN := (_eState = E_DL_SpcState.eVent), PT := tVent);      // 泄压计时，相外自动复位 ET / Vent timer

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_eCause 不入清单，禁同拍抹除 R187） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info code recomputed per scan
fPressMpaOut := 0.0;               // 压力镜像缺省 0 / Pressure mirror default
bInWindow := FALSE;                // 窗内镜像缺省 FALSE / Window mirror default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done flag default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_SpcCause.eNone;            // 清故障成因（锁存量） / Clear cause
    IF _eState = E_DL_SpcState.eFault THEN
        _eState := E_DL_SpcState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸（当拍量） / Config gate, current scan
    _uFault := 16#0005_039D;                   // 故障级：压装故障总码 / Process fault code
    _eCause := E_DL_SpcCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 故障标志与码位配对（R45） / Flag paired with code
END_IF

(* —— 段 3：分相超时与越窗锁存（判据当拍量；锁存后不再重算成因，故障码锁存回放） —— *)
IF (NOT _bFault) AND tonAlign.Q THEN           // 对齐超时（tonXxx.Q 当拍量） / Align timeout
    _uFault := 16#0005_039D;                   // 故障级：压装故障总码 / Same public code
    _eCause := E_DL_SpcCause.eAlignTmo;        // 归因：对齐超时 / Cause: align timeout
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND tonPress.Q THEN           // 压紧超时（未达窗下限） / Press timeout
    _uFault := 16#0005_039D;
    _eCause := E_DL_SpcCause.ePressTmo;        // 归因：压紧超时 / Cause: press timeout
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_SpcState.eHold) AND (NOT _bWinOk) THEN   // 保压越窗 / Hold out of window
    _uFault := 16#0005_039D;
    _eCause := E_DL_SpcCause.eHoldDev;         // 归因：保压越窗 / Cause: hold deviation
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND tonVent.Q THEN            // 泄压超时 / Vent timeout
    _uFault := 16#0005_039D;
    _eCause := E_DL_SpcCause.eVentTmo;         // 归因：泄压超时 / Cause: vent timeout
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240；全当拍量，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT tonAlign.Q / NOT tonPress.Q / NOT tonVent.Q = 当拍量；
     NOT _bCfgBad = 当拍量。组态非法者需先修参数再复位，复位沿当拍组态已合法方可解。 —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT tonAlign.Q) AND (NOT tonPress.Q) AND (NOT tonVent.Q) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_SpcCause.eNone;            // 清故障成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸（置位后强制入故障相，冻结段 5 内一切推进） —— *)
IF _bFault AND (_eState <> E_DL_SpcState.eFault) THEN
    _eState := E_DL_SpcState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_SpcState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动沿条件（电平门 + 无故障） / Start gate
        _eState := E_DL_SpcState.eAlign;       // 进对齐相 / Enter align
    END_IF

E_DL_SpcState.eAlign:
    IF bAlignInPos THEN                        // 出口 1：对位到位（事件量） / Alignment reached
        _eState := E_DL_SpcState.ePress;       // 进压紧相 / Enter press
    ELSIF NOT bStart THEN                      // 出口 2：撤启动（前置消失，R98 双出口） / Start released
        _eState := E_DL_SpcState.eIdle;        // 回未使能 / Back to idle
    END_IF

E_DL_SpcState.ePress:
    IF fPressMpa >= (fWinLoMpa - 1.0E-6) THEN  // 压力达窗下限（容差式） / Pressure reached low limit
        _eState := E_DL_SpcState.eHold;        // 进保压相 / Enter hold
    ELSIF NOT bStart THEN                      // 撤启动：中止本次压装 / Abort on start release
        _eState := E_DL_SpcState.eIdle;
    END_IF

E_DL_SpcState.eHold:
    IF tonHold.Q THEN                          // 保压到时 / Hold elapsed
        _eState := E_DL_SpcState.eVent;        // 进泄压相 / Enter vent
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort on start release
        _eState := E_DL_SpcState.eIdle;
    END_IF

E_DL_SpcState.eVent:
    IF tonVent.Q THEN                          // 泄压到时 / Vent elapsed
        _uInfo := 16#0005_04C5;                // 信息级：循环完成沿 / Info: cycle complete edge
        _eState := E_DL_SpcState.eDone;        // 进完成相 / Enter done
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort on start release
        _eState := E_DL_SpcState.eIdle;
    END_IF

E_DL_SpcState.eDone:
    IF NOT bStart THEN                         // 撤启动后回空闲（等下一循环） / Start released returns idle
        _eState := E_DL_SpcState.eIdle;
    END_IF

E_DL_SpcState.eFault:
    ;                                          // 故障相：仅段 4 复位沿可迁出 / Fault: only reset edge exits

ELSE
    _uFault := 16#0005_039D;                   // 故障级：非法相位兜底（归并总码，码表声明） / Illegal phase fallback
    _eCause := E_DL_SpcCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_SpcState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
fPressMpaOut := fPressMpa;                     // 压力镜像（名实同源） / Pressure mirror
bInWindow := _bWinOk AND (NOT _bFault);        // 窗内镜像（故障相强制 FALSE） / Window mirror
bCycleDone := (_eState = E_DL_SpcState.eDone); // 完成标志（相电平） / Done flag
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码（单拍） / Transient info code
END_IF
bError := _bFault;                             // 故障标志与锁存位同源 / Flag from latch
eState := _eState;                             // 状态出口单点映射 / State outlet
eCause := _eCause;                             // 成因出口单点映射 / Cause outlet

END_FUNCTION_BLOCK
