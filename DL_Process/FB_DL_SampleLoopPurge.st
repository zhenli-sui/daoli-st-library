(*
  FB_DL_SampleLoopPurge  —  取样回路吹扫与取样窗（阀序 + 吹扫/静置计时） / Sample-loop purge and sampling window with valve sequence and purge/settle timers
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇/工艺分析取样回路阀序族深化
  溯源 Origin   : 道莅 clean-room 实现；吹扫-静置-取样三段阀序与计时为公开取样系统工艺逻辑，未复制任何源码行
  功能 Function : 1) 三段阀序：ePurge 吹扫（吹扫阀开 + 需 bFlowOk 有流，tPurge 到时）→
                  eSettle 静置（全阀关，tSettle 到时）→ eSample 取样窗（取样阀开，tSample 到时）→
                  eDone；2) 吹扫超时（无流）判故障；3) 取样窗内 bSampleReady 丢失判故障；
                  4) 故障级单码 03A4，归因由 eCause 独立成员承载（R190）；
                  5) 信息级 04CC = 取样窗完成沿；6) 解除式全当拍量（R240）。
  接口 Interface: 输入有流/取样就绪/三个时间量；输出状态 + 三阀位 + 码
  边界 Boundary : ① 组态闸：三个时间量 <= T#0S 任一成立 → 03A4 锁存；
                  ② 三阀位由相位单点映射（段 6），故障相全阀关断（安全侧）；
                  ③ 三个 TON 段 0 无条件周期调用，IN 由相位派生，相切换自动复位 ET（R176）；
                  ④ 取样窗内就绪丢失为「事件消失」判据，非单拍标志门控（禁 bError 门控）；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 03A4 / 信息窗口 04CC）:
    16#0005_03A4 故障级：取样回路故障总码（组态非法 / 吹扫超时无流 / 取样窗就绪丢失），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04CC 信息级：取样窗完成沿（进 eDone 单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 2 · 序号 8）
*)

TYPE E_DL_SlpState :
(
    eIdle   := 0,     // 未使能：全阀关 / Idle, all valves closed
    ePurge  := 10,    // 吹扫中 / Purging
    eSettle := 20,    // 静置中（全阀关） / Settling with valves closed
    eSample := 30,    // 取样窗中 / Sampling window
    eDone   := 50,    // 循环完成 / Done
    eFault  := 90     // 故障锁存相（全阀关） / Fault latched, valves closed
);
END_TYPE

TYPE E_DL_SlpCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    ePurgeTmo   := 2, // 吹扫超时无流 / Purge timeout without flow
    eSampleLost := 3  // 取样窗就绪丢失 / Sampling readiness lost
);
END_TYPE

FUNCTION_BLOCK FB_DL_SampleLoopPurge
VAR_INPUT
    bFlowOk      : BOOL := FALSE;      // 吹扫有流反馈（电平）[-] / Purge flow feedback
    bSampleReady : BOOL := FALSE;      // 取样就绪（电平）[-] / Sampling ready
    tPurge       : TIME := T#30S;      // 吹扫时长 [ms]，域 > 0 / Purge duration
    tSettle      : TIME := T#5S;       // 静置时长 [ms]，域 > 0 / Settle duration
    tSample      : TIME := T#10S;      // 取样窗时长 [ms]，域 > 0 / Sampling window
    bStart       : BOOL := FALSE;      // 启动命令（电平）[-] / Start command
    bReset       : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_SlpState;      // 状态出口，段 6 单点映射 / State outlet
    eCause       : E_DL_SlpCause;      // 故障成因出口（R190） / Fault cause outlet
    bPurgeValve  : BOOL;               // 吹扫阀指令 [-] / Purge valve command
    bSampleValve : BOOL;               // 取样阀指令 [-] / Sample valve command
    bVentValve   : BOOL;               // 排放阀指令 [-] / Vent valve command
    bCycleDone   : BOOL;               // 循环完成标志 [-] / Cycle done flag
    bError       : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState      : E_DL_SlpState := E_DL_SlpState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_SlpCause := E_DL_SlpCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonPurge     : TON;                // 吹扫计时，每周期无条件调用 / Purge timer
    tonSettle    : TON;                // 静置计时，每周期无条件调用 / Settle timer
    tonSample    : TON;                // 取样窗计时，每周期无条件调用 / Sampling timer
    rtReset      : R_TRIG;             // 复位沿实例，每周期无条件调用 / Reset edge
    _bCfgBad     : BOOL;               // 组态非法当拍量 [-] / Config illegal
    _bFault      : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;              // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新（IN 由相位派生，相内自动清零 ET） —— *)
_bCfgBad := (tPurge <= T#0S) OR (tSettle <= T#0S) OR (tSample <= T#0S);     // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                     // 复位沿，每拍必调 / Reset edge
tonPurge(IN := (_eState = E_DL_SlpState.ePurge), PT := tPurge);             // 吹扫计时 / Purge timer
tonSettle(IN := (_eState = E_DL_SlpState.eSettle), PT := tSettle);          // 静置计时 / Settle timer
tonSample(IN := (_eState = E_DL_SlpState.eSample), PT := tSample);          // 取样窗计时 / Sampling timer

(* —— 段 1：单拍量预清零（锁存量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
bPurgeValve := FALSE;              // 吹扫阀缺省关 / Purge valve default closed
bSampleValve := FALSE;             // 取样阀缺省关 / Sample valve default closed
bVentValve := FALSE;               // 排放阀缺省关 / Vent valve default closed
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_SlpCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_SlpState.eFault THEN
        _eState := E_DL_SlpState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0005_03A4;                   // 故障级：取样回路故障总码 / Process fault code
    _eCause := E_DL_SlpCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF

(* —— 段 3：吹扫超时无流 / 取样窗就绪丢失（判据当拍量） —— *)
IF (NOT _bFault) AND (_eState = E_DL_SlpState.ePurge) AND (NOT bFlowOk) THEN
    _uFault := 16#0005_03A4;
    _eCause := E_DL_SlpCause.ePurgeTmo;        // 归因：吹扫无流 / Cause: purge without flow
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_SlpState.eSample) AND (NOT bSampleReady) THEN
    _uFault := 16#0005_03A4;
    _eCause := E_DL_SlpCause.eSampleLost;      // 归因：取样就绪丢失 / Cause: readiness lost
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT tonPurge.Q / bFlowOk —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT tonPurge.Q) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_SlpCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_SlpState.eFault) THEN
    _eState := E_DL_SlpState.eFault;           // 锁存即入故障相（全阀关） / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_SlpState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动条件 / Start gate
        _eState := E_DL_SlpState.ePurge;       // 进吹扫相 / Enter purge
    END_IF

E_DL_SlpState.ePurge:
    bPurgeValve := TRUE;                       // 吹扫阀开 / Purge valve open
    bVentValve := TRUE;                        // 排放阀开（吹扫排空） / Vent valve open
    IF tonPurge.Q AND bFlowOk THEN             // 出口 1：吹扫到时且有流 / Purge done with flow
        _eState := E_DL_SlpState.eSettle;      // 进静置相 / Enter settle
    ELSIF NOT bStart THEN                      // 出口 2：撤启动（R98 双出口） / Start released
        _eState := E_DL_SlpState.eIdle;
    END_IF

E_DL_SlpState.eSettle:
    IF tonSettle.Q THEN                        // 静置到时（全阀关） / Settle elapsed
        _eState := E_DL_SlpState.eSample;      // 进取样窗 / Enter sampling
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort
        _eState := E_DL_SlpState.eIdle;
    END_IF

E_DL_SlpState.eSample:
    bSampleValve := TRUE;                      // 取样阀开 / Sample valve open
    IF tonSample.Q THEN                        // 取样窗到时 / Sampling elapsed
        _uInfo := 16#0005_04CC;                // 信息级：取样窗完成沿 / Info: sampling complete
        _eState := E_DL_SlpState.eDone;        // 进完成相 / Enter done
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort
        _eState := E_DL_SlpState.eIdle;
    END_IF

E_DL_SlpState.eDone:
    IF NOT bStart THEN                         // 撤启动回空闲 / Start released returns idle
        _eState := E_DL_SlpState.eIdle;
    END_IF

E_DL_SlpState.eFault:
    ;                                          // 故障相：全阀关断，仅段 4 复位沿可迁出 / Valves closed, reset only

ELSE
    _uFault := 16#0005_03A4;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_SlpCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_SlpState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；故障相全阀关断为安全侧） —— *)
IF _bFault THEN
    bPurgeValve := FALSE;                      // 故障相吹扫阀强制关 / Purge valve forced closed
    bSampleValve := FALSE;                     // 故障相取样阀强制关 / Sample valve forced closed
    bVentValve := FALSE;                       // 故障相排放阀强制关 / Vent valve forced closed
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bCycleDone := (_eState = E_DL_SlpState.eDone);// 完成标志 / Done flag
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
