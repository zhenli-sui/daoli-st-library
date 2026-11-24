(*
  FB_DL_BundleShrinkTemp  —  收缩包装热风温度窗（超温/欠温双判 + 冷却延时） / Shrink-wrap hot-air temperature window with over/under-temperature judgement and cooling delay
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : roadmap-pkg-p2 — 后道收缩包装工站真缺口
  溯源 Origin   : 道莅 clean-room 实现；热风升温-恒温-冷却三段与温度窗双判为公开包装工艺逻辑，未复制任何源码行
  功能 Function : 1) 三段顺控：eHeat 加热（温度进窗 [fTempLoC, fTempHiC] 后由 tHeat 计时，
                  升温超时视为欠温故障）→ eCool 冷却（tCool 到时）→ eDone；
                  2) 超温/欠温双判独立归因（eOverTemp / eUnderTemp，R190 禁共用成员）；
                  3) 故障级单码 03A5，归因由 eCause 独立成员承载；
                  4) 信息级 04CD = 收缩循环完成沿；5) 解除式全当拍量（R240）。
  接口 Interface: 输入热风温度/温度窗/升温与冷却时间；输出状态 + 窗内镜像 + 码
  边界 Boundary : ① 组态闸：fTempHiC <= fTempLoC、tHeat <= T#0S、tCool <= T#0S → 03A5 锁存；
                  ② 温度判据为双向容差式（下限 -1.0E-6 / 上限 +1.0E-6），禁 = / <> 判等；
                  ③ 升温超时仅在温度未进窗时成立（门控为相量而非单拍标志，禁 bError 门控）；
                  ④ 两个 TON + 一个 R_TRIG 段 0 无条件周期调用，IN 由相位派生；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 03A5 / 信息窗口 04CD）:
    16#0005_03A5 故障级：收缩包装温度故障总码（组态非法 / 超温 / 欠温或升温超时），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04CD 信息级：收缩循环完成沿（冷却完成进 eDone 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 2 · 序号 9）
*)

TYPE E_DL_BstState :
(
    eIdle  := 0,      // 未使能待启动 / Idle, waiting start
    eHeat  := 10,     // 加热（温度窗 + 恒温计时） / Heating under window and dwell timing
    eCool  := 20,     // 冷却延时 / Cooling delay
    eDone  := 50,     // 循环完成 / Done
    eFault := 90      // 故障锁存相（加热输出冻结关断） / Fault latched, heater frozen off
);
END_TYPE

TYPE E_DL_BstCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eOverTemp   := 2, // 超温 / Over temperature
    eUnderTemp  := 3  // 欠温（含升温超时） / Under temperature including heat timeout
);
END_TYPE

FUNCTION_BLOCK FB_DL_BundleShrinkTemp
VAR_INPUT
    fTempC     : REAL := 0.0;         // 热风实测温度 [°C] / Measured hot-air temperature
    fTempLoC   : REAL := 150.0;       // 温度窗下限 [°C] / Temperature window low
    fTempHiC   : REAL := 180.0;       // 温度窗上限 [°C] / Temperature window high
    tHeat      : TIME := T#6S;        // 恒温保持时长 [ms]，域 > 0 / Heat dwell duration
    tCool      : TIME := T#3S;        // 冷却延时 [ms]，域 > 0 / Cooling delay
    bHeaterOn  : BOOL := FALSE;       // 加热使能（电平）[-] / Heater enable
    bStart     : BOOL := FALSE;       // 启动命令（电平）[-] / Start command
    bReset     : BOOL := FALSE;       // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState     : E_DL_BstState;       // 状态出口，段 6 单点映射 / State outlet
    eCause     : E_DL_BstCause;       // 故障成因出口（R190） / Fault cause outlet
    bHeaterCmd : BOOL;                // 加热输出指令 [-] / Heater command
    bInWindow  : BOOL;                // 温度在窗镜像 [-] / In-window mirror
    bCycleDone : BOOL;                // 循环完成标志 [-] / Cycle done flag
    bError     : BOOL;                // 故障锁存标志 [-] / Fault latch flag
    nErrId     : UDINT;               // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState    : E_DL_BstState := E_DL_BstState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_BstCause := E_DL_BstCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonHeat    : TON;                 // 恒温保持计时，每周期无条件调用 / Heat dwell timer
    tonCool    : TON;                 // 冷却延时计时，每周期无条件调用 / Cooling timer
    rtReset    : R_TRIG;              // 复位沿实例，每周期无条件调用 / Reset edge
    _bWinOk    : BOOL;                // 温度在窗当拍量 [-] / In-window verdict
    _bOver     : BOOL;                // 超温当拍量 [-] / Over-temperature verdict
    _bCfgBad   : BOOL;                // 组态非法当拍量 [-] / Config illegal
    _bFault    : BOOL;                // 故障锁存位（锁存量） / Latched fault bit
    _uFault    : UDINT;               // 故障码锁存（锁存量） / Latched fault code
    _uInfo     : UDINT;               // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 + 当拍量判据 —— *)
_bWinOk := (fTempC >= fTempLoC - 1.0E-6) AND (fTempC <= fTempHiC + 1.0E-6);   // 温度容差窗判据 / Window verdict
_bOver := fTempC > (fTempHiC + 1.0E-6);                                      // 超温当拍量（上侧直比） / Over-temperature
_bCfgBad := (fTempHiC <= fTempLoC) OR (tHeat <= T#0S) OR (tCool <= T#0S);     // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                      // 复位沿，每拍必调 / Reset edge
tonHeat(IN := (_eState = E_DL_BstState.eHeat), PT := tHeat);                 // 恒温保持计时 / Dwell timer
tonCool(IN := (_eState = E_DL_BstState.eCool), PT := tCool);                 // 冷却延时计时 / Cooling timer

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
bHeaterCmd := FALSE;               // 加热指令缺省关 / Heater command default off
bInWindow := FALSE;                // 窗内镜像缺省 FALSE / Window mirror default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_BstCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_BstState.eFault THEN
        _eState := E_DL_BstState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0005_03A5;                   // 故障级：温度故障总码 / Process fault code
    _eCause := E_DL_BstCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF

(* —— 段 3：超温 / 欠温 / 升温超时（判据当拍量，门控为相位量） —— *)
IF (NOT _bFault) AND (_eState = E_DL_BstState.eHeat) AND _bOver THEN   // 超温 / Over temperature
    _uFault := 16#0005_03A5;
    _eCause := E_DL_BstCause.eOverTemp;        // 归因：超温 / Cause: over temperature
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_BstState.eHeat) AND (NOT _bWinOk) AND (NOT tonHeat.Q)
   AND (fTempC < (fTempLoC - 1.0E-6)) THEN     // 欠温（低于下限且计时未完成） / Under temperature
    _uFault := 16#0005_03A5;
    _eCause := E_DL_BstCause.eUnderTemp;       // 归因：欠温 / Cause: under temperature
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_BstState.eHeat) AND (NOT _bWinOk) AND tonHeat.Q THEN
    _uFault := 16#0005_03A5;
    _eCause := E_DL_BstCause.eUnderTemp;       // 归因：升温超时归并欠温 / Cause: heat timeout as under temp
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bOver / NOT _bWinOk 的当拍态 —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bOver) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_BstCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_BstState.eFault) THEN
    _eState := E_DL_BstState.eFault;           // 锁存即入故障相（加热关断） / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_BstState.eIdle:
    IF bStart AND bHeaterOn AND (NOT _bFault) THEN   // 启动条件（须加热使能） / Start gate
        _eState := E_DL_BstState.eHeat;              // 进加热相 / Enter heating
    END_IF

E_DL_BstState.eHeat:
    bHeaterCmd := bHeaterOn;                         // 加热指令跟随使能（相内承载） / Heater command in phase
    IF tonHeat.Q AND _bWinOk THEN                    // 出口 1：恒温到时且在窗 / Dwell done in window
        _eState := E_DL_BstState.eCool;              // 进冷却相 / Enter cooling
    ELSIF (NOT bStart) OR (NOT bHeaterOn) THEN       // 出口 2：撤启动或撤加热（R98 双出口） / Start or heater released
        _eState := E_DL_BstState.eIdle;
    END_IF

E_DL_BstState.eCool:
    IF tonCool.Q THEN                                // 冷却到时 / Cooling elapsed
        _uInfo := 16#0005_04CD;                      // 信息级：收缩循环完成沿 / Info: cycle complete
        _eState := E_DL_BstState.eDone;              // 进完成相 / Enter done
    ELSIF NOT bStart THEN                            // 撤启动：中止 / Abort
        _eState := E_DL_BstState.eIdle;
    END_IF

E_DL_BstState.eDone:
    IF NOT bStart THEN                               // 撤启动回空闲 / Start released returns idle
        _eState := E_DL_BstState.eIdle;
    END_IF

E_DL_BstState.eFault:
    ;                                                // 故障相：加热关断，仅段 4 复位沿可迁出 / Heater off, reset only

ELSE
    _uFault := 16#0005_03A5;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_BstCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_BstState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；故障相加热强制关断） —— *)
IF _bFault THEN
    bHeaterCmd := FALSE;                       // 故障相加热强制关断（安全侧） / Heater forced off
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bInWindow := _bWinOk AND (NOT _bFault);        // 窗内镜像 / Window mirror
bCycleDone := (_eState = E_DL_BstState.eDone); // 完成标志 / Done flag
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
