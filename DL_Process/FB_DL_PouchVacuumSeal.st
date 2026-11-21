(*
  FB_DL_PouchVacuumSeal  —  铝塑膜真空封装顺控（真空度窗 + 封头温度 + 封合延时） / Aluminium-laminate pouch vacuum sealing with vacuum window, head-temperature window and seal dwell
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : roadmap-li-p1 — 锂电软包封装工站真缺口
  溯源 Origin   : 道莅 clean-room 实现；真空封装「抽真空-封合-冷却」时序与真空度/温度窗判据为公开工艺逻辑，未复制任何源码行
  功能 Function : 1) 三段顺控：eEvac 抽真空（真空度 fVacKpa 达 fVacTargetKpa 容差带内）→
                  eSeal 封合（封头温度在 [fSealTempLoC, fSealTempHiC] 窗内且 tSeal 到时）→
                  eCool 冷却（tCool 到时）→ eDone；2) 抽真空超时 tEvacTmo 保护；
                  3) 封合相温度越窗即故障，温度窗判据为双向容差式；
                  4) 故障级单码 039E，归因由 eCause 独立成员承载（R190）；
                  5) 信息级 04C6 = 封装循环完成沿；6) 解除式全当拍量（R240）。
  接口 Interface: 输入真空度/封头温度/三个时间量/命令位；输出状态/真空镜像/窗内镜像/原因/码
  边界 Boundary : ① 组态闸：fVacTargetKpa > 0.0（目标真空度按正压差量纲给出，域 > 0）、
                  fSealTempHiC <= fSealTempLoC、三个时间量 <= T#0S → 039E 锁存；
                  ② 真空度判据用 fVacKpa - fVacTargetKpa 的容差带（|Δ| <= fVacTolKpa），
                  禁用 = / <> 判等；③ 封头温度判据同样容差式；
                  ④ 三个 TON + 一个 R_TRIG 全部段 0 无条件每周期调用，IN 由相位派生，
                  相切换自动复位 ET；⑤ 故障相迁出唯一路径 = bReset 上升沿；
                  ⑥ 零全局耦合：无 GVL / VAR_EXTERNAL / %I %Q %M。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 039E / 信息窗口 04C6）:
    16#0005_039E 故障级：真空封装故障总码（组态非法 / 抽真空超时 / 封头温度越窗），
                 锁存至 bReset 上升沿；逐成因归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04C6 信息级：封装循环完成沿（冷却完成进 eDone 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 1 · 序号 2）
*)

TYPE E_DL_PvsState :
(
    eIdle   := 0,     // 未使能待启动 / Idle, waiting start
    eEvac   := 10,    // 抽真空中 / Evacuating
    eSeal   := 20,    // 封合中（温度窗 + 延时） / Sealing under temperature window
    eCool   := 30,    // 冷却中 / Cooling
    eDone   := 50,    // 循环完成 / Done
    eFault  := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_PvsCause :
(
    eNone       := 0,    // 无故障成因 / No cause
    eCfgIllegal := 1,    // 组态非法 / Illegal configuration
    eEvacTmo    := 2,    // 抽真空超时 / Evacuation timeout
    eSealTemp   := 3     // 封头温度越窗 / Seal head temperature out of window
);
END_TYPE

FUNCTION_BLOCK FB_DL_PouchVacuumSeal
VAR_INPUT
    fVacKpa      : REAL := 0.0;        // 实测真空度 [kPa]，相对大气压正压差量纲 / Measured vacuum level
    fVacTargetKpa: REAL := 95.0;       // 目标真空度 [kPa]，域 > 0 / Target vacuum level
    fVacTolKpa   : REAL := 2.0;        // 真空度容差带 [kPa]，域 > 0 / Vacuum tolerance band
    fSealTempC   : REAL := 0.0;        // 实测封头温度 [°C] / Measured seal head temperature
    fSealTempLoC : REAL := 150.0;      // 封头温度窗下限 [°C] / Head temperature low limit
    fSealTempHiC : REAL := 175.0;      // 封头温度窗上限 [°C] / Head temperature high limit
    tEvacTmo     : TIME := T#20S;      // 抽真空超时 [ms]，域 > 0 / Evacuation timeout
    tSeal        : TIME := T#3S;       // 封合延时 [ms]，域 > 0 / Seal dwell
    tCool        : TIME := T#2S;       // 冷却时长 [ms]，域 > 0 / Cooling duration
    bStart       : BOOL := FALSE;      // 启动命令（电平）[-] / Start command
    bReset       : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_PvsState;      // 状态出口，段 6 单点映射 / State outlet
    eCause       : E_DL_PvsCause;      // 故障成因出口（R190） / Fault cause outlet
    fVacKpaOut   : REAL;               // 真空度镜像 [kPa] / Vacuum mirror
    bVacOk       : BOOL;               // 真空度达窗镜像 [-] / Vacuum reached mirror
    bTempOk      : BOOL;               // 封头温度在窗镜像 [-] / Head temperature in window
    bCycleDone   : BOOL;               // 循环完成标志 [-] / Cycle done flag
    bError       : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState      : E_DL_PvsState := E_DL_PvsState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_PvsCause := E_DL_PvsCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonEvac      : TON;                // 抽真空超时实例，每周期无条件调用 / Evacuation timeout timer
    tonSeal      : TON;                // 封合延时实例，每周期无条件调用 / Seal dwell timer
    tonCool      : TON;                // 冷却计时实例，每周期无条件调用 / Cooling timer
    rtReset      : R_TRIG;             // 复位沿实例，每周期无条件调用 / Reset edge
    _bVacOk      : BOOL;               // 真空度达窗当拍量 [-] / Vacuum window verdict
    _bTempOk     : BOOL;               // 温度在窗当拍量 [-] / Temperature window verdict
    _bCfgBad     : BOOL;               // 组态非法当拍量 [-] / Config illegal
    _bFault      : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;              // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 —— *)
_bVacOk := ABS(fVacKpa - fVacTargetKpa) <= fVacTolKpa;                          // 真空度容差窗判据 / Vacuum tolerance window verdict
_bTempOk := (fSealTempC >= fSealTempLoC - 1.0E-6) AND (fSealTempC <= fSealTempHiC + 1.0E-6);  // 温度容差窗判据 / Temperature window verdict
_bCfgBad := (fVacTargetKpa <= 0.0) OR (fVacTolKpa <= 0.0)
            OR (fSealTempHiC <= fSealTempLoC) OR (tEvacTmo <= T#0S)
            OR (tSeal <= T#0S) OR (tCool <= T#0S);                              // 组态非法当拍量 / Config illegal, current scan
rtReset(CLK := bReset);                                                        // 复位沿，每拍必调 / Reset edge refresh
tonEvac(IN := (_eState = E_DL_PvsState.eEvac), PT := tEvacTmo);                // 抽真空超时计时  / Evacuation timer
tonSeal(IN := (_eState = E_DL_PvsState.eSeal), PT := tSeal);                   // 封合延时计时 / Seal dwell timer
tonCool(IN := (_eState = E_DL_PvsState.eCool), PT := tCool);                   // 冷却计时 / Cooling timer

(* —— 段 1：单拍量预清零（锁存量不入清单，禁同拍抹除 R187） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
fVacKpaOut := 0.0;                 // 真空镜像缺省 0 / Vacuum mirror default
bVacOk := FALSE;                   // 达窗镜像缺省 FALSE / Vacuum flag default
bTempOk := FALSE;                  // 温度镜像缺省 FALSE / Temperature flag default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_PvsCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_PvsState.eFault THEN
        _eState := E_DL_PvsState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0005_039E;                   // 故障级：真空封装故障总码 / Process fault code
    _eCause := E_DL_PvsCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF

(* —— 段 3：抽真空超时与封合温度越窗（判据当拍量） —— *)
IF (NOT _bFault) AND tonEvac.Q THEN            // 抽真空超时 / Evacuation timeout
    _uFault := 16#0005_039E;                   // 故障级：总码 / Public code
    _eCause := E_DL_PvsCause.eEvacTmo;         // 归因：抽真空超时 / Cause: evac timeout
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_PvsState.eSeal) AND (NOT _bTempOk) THEN  // 封合期温度越窗 / Seal temp deviation
    _uFault := 16#0005_039E;
    _eCause := E_DL_PvsCause.eSealTemp;        // 归因：封头温度越窗 / Cause: seal temperature
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT tonEvac.Q / NOT tonSeal.Q 皆当拍量 —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT tonEvac.Q) AND (NOT tonSeal.Q) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_PvsCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_PvsState.eFault) THEN
    _eState := E_DL_PvsState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_PvsState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动条件 / Start gate
        _eState := E_DL_PvsState.eEvac;        // 进抽真空相 / Enter evacuation
    END_IF

E_DL_PvsState.eEvac:
    IF _bVacOk THEN                            // 出口 1：真空度达窗 / Vacuum reached
        _eState := E_DL_PvsState.eSeal;        // 进封合相 / Enter sealing
    ELSIF NOT bStart THEN                      // 出口 2：撤启动（R98 双出口） / Start released
        _eState := E_DL_PvsState.eIdle;
    END_IF

E_DL_PvsState.eSeal:
    IF tonSeal.Q AND _bTempOk THEN             // 封合延时到且温度在窗 / Dwell done within window
        _eState := E_DL_PvsState.eCool;        // 进冷却相 / Enter cooling
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort
        _eState := E_DL_PvsState.eIdle;
    END_IF

E_DL_PvsState.eCool:
    IF tonCool.Q THEN                          // 冷却到时 / Cooling elapsed
        _uInfo := 16#0005_04C6;                // 信息级：循环完成沿 / Info: cycle complete edge
        _eState := E_DL_PvsState.eDone;        // 进完成相 / Enter done
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort
        _eState := E_DL_PvsState.eIdle;
    END_IF

E_DL_PvsState.eDone:
    IF NOT bStart THEN                         // 撤启动回空闲 / Start released returns idle
        _eState := E_DL_PvsState.eIdle;
    END_IF

E_DL_PvsState.eFault:
    ;                                          // 故障相：仅段 4 复位沿可迁出 / Only reset exits

ELSE
    _uFault := 16#0005_039E;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_PvsCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_PvsState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
fVacKpaOut := fVacKpa;                         // 真空镜像 / Vacuum mirror
bVacOk := _bVacOk AND (NOT _bFault);           // 达窗镜像 / Vacuum verdict mirror
bTempOk := _bTempOk AND (NOT _bFault);         // 温度窗镜像 / Temperature verdict mirror
bCycleDone := (_eState = E_DL_PvsState.eDone);// 完成标志 / Done flag
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
