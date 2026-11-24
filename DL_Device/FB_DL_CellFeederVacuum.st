(*
  FB_DL_CellFeederVacuum  —  电芯真空上料吸盘（真空窗 + 泄漏率判据 + 掉料重试） / Cell feeder vacuum cup with vacuum window, leakage-rate verdict and drop retry
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t1-5-tcopen — 电芯上料吸盘执行器族深化
  溯源 Origin   : 道莅 clean-room 实现；真空窗确认 + 泄漏率判据 + 有限次重试为公开真空吸取工艺逻辑，未复制任何源码行
  功能 Function : 1) 三段顺控：eVac 抽真空（|fVacKpa - fVacTargetKpa| <= fVacTolKpa 达窗）→
                  eLeak 泄漏率测试窗（tLeak 内 fLeakKpaPerS <= fLeakMaxKpaPerS 且 bPartOn 在位）→
                  eDone；2) 掉料重试：泄漏/在位判据失败或 bPartOn 丢失 → eRetry 重抽，
                  重试计数 nRetry 达 nRetryMax 即故障（计数饱和于 nRetryMax）；
                  3) 抽真空超时、测试窗超时各自归因；
                  4) 故障级单码 052D / 信息级 0433 = 吸取确认完成沿。
  接口 Interface: 输入真空度/泄漏率/在位/三个时间量/重试上限；输出状态 + 吸盘指令 + 码
  边界 Boundary : ① 组态闸：fVacTargetKpa <= 0.0、fVacTolKpa <= 0.0、fLeakMaxKpaPerS <= 0.0、
                  tVacTmo/tLeak/tRetry <= T#0S、nRetryMax = 0 → 052D 锁存；
                  ② 真空度/泄漏率非有限（NaN 自反 + Inf 差值自减）→ 052D 锁存，吸盘保持指令撤销；
                  ③ 重试计数为 UINT，递增前先判饱和（不越界）；④ 三 TON + R_TRIG 段 0 无条件调用；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿（同时清重试计数）；
                  ⑥ 零全局耦合：无 GVL / VAR_EXTERNAL / %I %Q %M 直接地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Device 分段见下，故障窗口 052D / 信息窗口 0433）:
    16#0003_052D 故障级：真空上料故障总码（组态非法 / 抽真空超时 / 泄漏率超限且重试耗尽 / 输入非有限），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0003_0433 信息级：吸取确认完成沿（进 eDone 单拍）
    分段理由：段 0003 故障带 03A0~03FF 于 R42 用尽，启用 05xx 副带续编，避开 0590~0599 判错位段。
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 4 · 序号 17）
*)

TYPE E_DL_CfvState :
(
    eIdle   := 0,     // 未使能：吸盘指令撤销 / Idle, suction withdrawn
    eVac    := 10,    // 抽真空中 / Evacuating
    eLeak   := 20,    // 泄漏率测试窗 / Leakage test window
    eRetry  := 30,    // 掉料重试重抽中 / Retry re-evacuation
    eDone   := 50,    // 吸取完成 / Pick done
    eFault  := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_CfvCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eVacTmo     := 2, // 抽真空超时 / Evacuation timeout
    eLeakHigh   := 3, // 泄漏率超限且重试耗尽 / Leakage high after retries
    eRetryOut   := 4, // 重试次数耗尽 / Retry exhausted
    eNonFinite  := 5  // 输入非有限 / Non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_CellFeederVacuum
VAR_INPUT
    fVacKpa        : REAL := 0.0;      // 吸盘真空度 [kPa]，正压差量纲 / Cup vacuum level
    fVacTargetKpa  : REAL := 60.0;     // 目标真空度 [kPa]，域 > 0 / Target vacuum level
    fVacTolKpa     : REAL := 3.0;      // 真空度容差 [kPa]，域 > 0 / Vacuum tolerance
    fLeakKpaPerS   : REAL := 0.0;      // 实测泄漏率 [kPa/s] / Measured leakage rate
    fLeakMaxKpaPerS: REAL := 0.5;      // 泄漏率上限 [kPa/s]，域 > 0 / Leakage rate limit
    bPartOn        : BOOL := FALSE;    // 料在位检测（电平）[-] / Part-present detection
    tVacTmo        : TIME := T#5S;     // 抽真空超时 [ms]，域 > 0 / Evacuation timeout
    tLeak          : TIME := T#2S;     // 泄漏率测试窗 [ms]，域 > 0 / Leakage test window
    tRetry         : TIME := T#1S;     // 重试泄压间隔 [ms]，域 > 0 / Retry interval
    nRetryMax      : UINT := 3;        // 最大重试次数 [次]，域 > 0 / Maximum retries
    bStart         : BOOL := FALSE;    // 启动命令（电平）[-] / Start command
    bReset         : BOOL := FALSE;    // 复位命令，上升沿清故障与重试计数 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState         : E_DL_CfvState;    // 状态出口，段 6 单点映射 / State outlet
    eCause         : E_DL_CfvCause;    // 故障成因出口（R190） / Fault cause outlet
    bSuctionCmd    : BOOL;             // 吸盘真空指令 [-] / Suction vacuum command
    bVacOk         : BOOL;             // 真空达窗镜像 [-] / Vacuum reached mirror
    nRetryCount    : UINT;             // 已重试次数 [次] / Retry count
    bCycleDone     : BOOL;             // 吸取完成标志 [-] / Pick done flag
    bError         : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId         : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState        : E_DL_CfvState := E_DL_CfvState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause        : E_DL_CfvCause := E_DL_CfvCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonVac         : TON;              // 抽真空超时计时，每周期无条件调用 / Evacuation timer
    tonLeak        : TON;              // 泄漏测试窗计时，每周期无条件调用 / Leakage window timer
    tonRetry       : TON;              // 重试间隔计时，每周期无条件调用 / Retry interval timer
    rtReset        : R_TRIG;           // 复位沿实例，每周期无条件调用 / Reset edge
    _nRetry        : UINT;             // 重试计数保持量（持久） / Retry counter
    _bVacOk        : BOOL;             // 真空达窗当拍量 [-] / Vacuum verdict
    _bLeakOk       : BOOL;             // 泄漏率达标当拍量 [-] / Leakage verdict
    _bNonFin       : BOOL;             // 输入非有限当拍量 [-] / Non-finite input
    _bCfgBad       : BOOL;             // 组态非法当拍量 [-] / Config illegal
    _bFault        : BOOL;             // 故障锁存位（锁存量） / Latched fault bit
    _uFault        : UDINT;            // 故障码锁存（锁存量） / Latched fault code
    _uInfo         : UDINT;            // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 + 当拍量判据 —— *)
_bVacOk := ABS(fVacKpa - fVacTargetKpa) <= fVacTolKpa;                        // 真空容差窗判据 / Vacuum window
_bLeakOk := fLeakKpaPerS <= fLeakMaxKpaPerS;                                  // 泄漏率判据（单侧直比） / Leakage verdict
_bNonFin := (fVacKpa <> fVacKpa) OR (fLeakKpaPerS <> fLeakKpaPerS)
         OR ((fVacKpa - fVacKpa) <> (fVacKpa - fVacKpa))
         OR ((fLeakKpaPerS - fLeakKpaPerS) <> (fLeakKpaPerS - fLeakKpaPerS)); // NaN 自反 + Inf 差值自减 / NaN and Inf
_bCfgBad := (fVacTargetKpa <= 0.0) OR (fVacTolKpa <= 0.0) OR (fLeakMaxKpaPerS <= 0.0)
            OR (tVacTmo <= T#0S) OR (tLeak <= T#0S) OR (tRetry <= T#0S) OR (nRetryMax = 0);   // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                                       // 复位沿，每拍必调 / Reset edge
tonVac(IN := (_eState = E_DL_CfvState.eVac), PT := tVacTmo);                  // 抽真空超时计时 / Evacuation timer
tonLeak(IN := (_eState = E_DL_CfvState.eLeak), PT := tLeak);                  // 泄漏测试窗计时 / Leakage timer
tonRetry(IN := (_eState = E_DL_CfvState.eRetry), PT := tRetry);               // 重试间隔计时 / Retry timer

(* —— 段 1：单拍量预清零（锁存量与重试计数保持量不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
bSuctionCmd := FALSE;              // 吸盘指令缺省撤销 / Suction default withdrawn
bVacOk := FALSE;                   // 真空镜像缺省 FALSE / Vacuum default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CfvCause.eNone;            // 清成因（锁存量） / Clear cause
    _nRetry := 0;                              // 清重试计数（锁存量） / Clear retry counter
    IF _eState = E_DL_CfvState.eFault THEN
        _eState := E_DL_CfvState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0003_052D;                   // 故障级：真空上料故障总码（05xx 副带） / Device fault code
    _eCause := E_DL_CfvCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF
IF (NOT _bFault) AND _bNonFin THEN             // 非有限锁存 / Non-finite latch
    _uFault := 16#0003_052D;
    _eCause := E_DL_CfvCause.eNonFinite;       // 归因：非有限 / Cause: non-finite
    _bFault := TRUE;
END_IF

(* —— 段 3：超时 / 泄漏超限 / 掉料（判据当拍量） —— *)
IF (NOT _bFault) AND tonVac.Q THEN             // 抽真空超时 / Evacuation timeout
    _uFault := 16#0003_052D;
    _eCause := E_DL_CfvCause.eVacTmo;          // 归因：抽真空超时 / Cause: evac timeout
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_CfvState.eLeak) AND tonLeak.Q THEN
    IF (NOT _bLeakOk) OR (NOT bPartOn) THEN    // 泄漏超限或料不在位 / Leak high or part missing
        IF _nRetry >= nRetryMax THEN           // 重试耗尽 → 故障 / Retries exhausted
            _uFault := 16#0003_052D;
            _eCause := E_DL_CfvCause.eRetryOut;   // 归因：重试耗尽 / Cause: retry exhausted
            _bFault := TRUE;
        ELSE
            _eState := E_DL_CfvState.eRetry;   // 未耗尽：进重试相 / Enter retry
        END_IF
    END_IF
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT _bNonFin —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_CfvCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_CfvState.eFault) THEN
    _eState := E_DL_CfvState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_CfvState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动条件 / Start gate
        _nRetry := 0;                          // 新循环清重试计数 / Reset retries for new cycle
        _eState := E_DL_CfvState.eVac;         // 进抽真空相 / Enter evacuation
    END_IF

E_DL_CfvState.eVac:
    bSuctionCmd := TRUE;                       // 真空指令置位（相内承载） / Suction command on
    IF _bVacOk THEN                            // 出口 1：真空达窗 / Vacuum reached
        _eState := E_DL_CfvState.eLeak;        // 进泄漏测试窗 / Enter leakage window
    ELSIF NOT bStart THEN                      // 出口 2：撤启动（R98 双出口） / Start released
        _eState := E_DL_CfvState.eIdle;
    END_IF

E_DL_CfvState.eLeak:
    bSuctionCmd := TRUE;                       // 保持真空指令 / Hold suction
    IF tonLeak.Q THEN                          // 测试窗到时 / Window elapsed
        IF _bLeakOk AND bPartOn THEN           // 泄漏达标且料在位 / Leak OK and part present
            _uInfo := 16#0003_0433;            // 信息级：吸取确认完成沿 / Info: pick confirmed
            _eState := E_DL_CfvState.eDone;    // 进完成相 / Enter done
        ELSE
            _eState := E_DL_CfvState.eRetry;   // 否则进重试相（段 3 已裁决耗尽） / Else retry
        END_IF
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort
        _eState := E_DL_CfvState.eIdle;
    END_IF

E_DL_CfvState.eRetry:
    IF tonRetry.Q THEN                         // 重试间隔到 / Retry interval elapsed
        IF _nRetry < nRetryMax THEN            // 计数饱和判定后再递增（不越界） / Saturating increment
            _nRetry := _nRetry + 1;
        END_IF
        _eState := E_DL_CfvState.eVac;         // 回抽真空相重抽 / Back to evacuation
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort
        _eState := E_DL_CfvState.eIdle;
    END_IF

E_DL_CfvState.eDone:
    bSuctionCmd := TRUE;                       // 完成相保持吸取（搬送中） / Hold suction during transfer
    IF NOT bStart THEN                         // 撤启动：撤销吸取 / Start released withdraws suction
        _eState := E_DL_CfvState.eIdle;
    END_IF

E_DL_CfvState.eFault:
    ;                                          // 故障相：吸盘指令撤销，仅段 4 复位沿可迁出 / Suction off, reset only

ELSE
    _uFault := 16#0003_052D;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_CfvCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_CfvState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；故障相吸盘指令撤销） —— *)
IF _bFault THEN
    bSuctionCmd := FALSE;                      // 故障相吸盘指令强制撤销（安全侧） / Suction forced off
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bVacOk := _bVacOk AND (NOT _bFault);           // 真空达窗镜像 / Vacuum mirror
nRetryCount := _nRetry;                        // 重试计数出口 / Retry count outlet
bCycleDone := (_eState = E_DL_CfvState.eDone); // 完成标志 / Done flag
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
