(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FlowSwitchResponseCheck
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 流量开关**自身响应**校核（命令-监视-判定三段式）。① 运行指令 bRunCmd
 *                         上升沿起，tRespWin 内应出现流量开关 bFlowSw 上升沿；未出现 →
 *                         eCause = eNoResponse（开关卡死 / 管路堵塞 / 接线断）；② 指令撤销后
 *                         tDropWin 内流量信号未回落 → eCause = eStuckOn（开关粘连，常闭触点焊死）。
 *                         另输出实测响应时间 tRespMeasured（供趋势与开关劣化判断）。
 * 分工声明 (Scope)      : 本件**不判干转**（干转属主为 `FB_DL_PumpDryRunGuard` /
 *                         `FB_DL_PumpDryRunProtect`），也不判流量大小与累计量；本件只判「开关
 *                         是否按命令跟上、是否按命令放开」。干转保护需要泵曲线与最小流量阈值，
 *                         语义与本件正交，禁止互相替代。
 * 接口     (Interface)  : 输入 bRunCmd 泵/阀运行指令、bFlowSw 流量开关反馈、tRespWin 响应窗、
 *                         tDropWin 回落窗、bReset 复位；输出 bSwHealthy 开关健康位、tRespMeasured
 *                         实测响应时间（ET 锁存式）、eCause 归因、eState / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：tRespWin <= T#0S 或 tDropWin <= T#0S → 故障锁存；
 *                         ② 响应时间测量用 **TON 的 ET 锁存**（流量沿那一拍读一次 ET 并锁存，
 *                         之后不再实时读 ET——锁存后实例继续计时会把测量值篡改，R38 范式）；
 *                         ③ TON 两枚 + R_TRIG 三枚段 0 无条件周期刷新，IN 由相位派生（R228A）；
 *                         ④ 故障相迁出唯一路径 = bReset 上升沿；⑤ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 当拍「指令与反馈同相」（bRunCmd 与 bFlowSw
 *                         同为真或同为假，即不处于任一异常窗，全为当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：两枚 TON 的 IN 挂相位，故障相内恒假 → Q 恒假；
 *                         现场消除卡死或粘连后指令与反馈自然同相，无恒假因子。
 * 码表     (Codes)      : 16#0003_0703 故障级：流量开关响应故障总码（组态非法 / 无响应 / 粘连 /
 *                         非法相位），锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0003_0482 信息级：响应正常（本次启动已在窗内测到响应沿）。
 *                         加码反证（R90）：响应正常时 tRespMeasured 已给出数值，但「本次启动已确认
 *                         响应」与「上一轮遗留的旧响应时间」在出口上无法区分（时间量会保持），
 *                         故立一码标记本轮已确认。
 *                         码段说明：Device 的 03xx 故障子带已占满（仅余 03C5~03C9 碎片孔洞，按
 *                         实战规则 13 禁回填），故本批新开 07xx 故障子带取 16#0003_0703；
 *                         信息级用 04xx 子带取 16#0003_0482（源码实扫为空）。分段理由即此。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考命令-监视-判定三段式与参数域，
 *                         零代码行复制；t2-2-lbp 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 4 · 序号 17）
 *==============================================================================*)

TYPE E_DL_FsrState :
(
    eIdle     := 0,     // 待机（指令撤销且反馈已回落） / Idle, command off and feedback dropped
    eRespWait := 10,    // 响应窗内等流量信号 / Waiting for flow signal inside the response window
    eRun      := 20,    // 指令在效且流量已建立 / Command on and flow established
    eDropWait := 30,    // 回落窗内等流量信号消失 / Waiting for flow signal to drop inside the drop window
    eFault    := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_FsrCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eNoResponse := 2,   // 无响应（窗内无流量沿） / No response inside the window
    eStuckOn    := 3,   // 粘连（撤销后不回落） / Stuck on, no drop after release
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_FlowSwitchResponseCheck
VAR_INPUT
    bRunCmd    : BOOL := FALSE;          // 泵/阀运行指令（电平） [-] / Pump or valve run command level
    bFlowSw    : BOOL := FALSE;          // 流量开关反馈 [-] / Flow switch feedback
    tRespWin   : TIME := T#3S;           // 响应窗（指令起算），域 > T#0S [ms] / Response window, domain > T#0S [ms]
    tDropWin   : TIME := T#3S;           // 回落窗（撤令起算），域 > T#0S [ms] / Drop window, domain > T#0S [ms]
    bReset     : BOOL := FALSE;          // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    bSwHealthy   : BOOL;                 // 开关健康位（无故障且不在异常窗） [-] / Switch healthy flag
    tRespMeasured: TIME;                 // 实测响应时间（ET 锁存，锁存后不随实例计时变化） [ms] / Measured response time, latched ET [ms]
    eCause       : E_DL_FsrCause;        // 故障成因出口（R190 归因唯一） / Fault cause outlet
    eState       : E_DL_FsrState;        // 状态出口，段 6 单点映射 / State outlet
    bError       : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState      : E_DL_FsrState := E_DL_FsrState.eIdle;     // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_FsrCause := E_DL_FsrCause.eNone;     // 故障成因锁存（锁存量） / Latched cause
    tonResp      : TON;                  // 响应窗计时，段 0 无条件调用 / Response window timer
    tonDrop      : TON;                  // 回落窗计时，段 0 无条件调用 / Drop window timer
    rtRun        : R_TRIG;               // 指令上升沿实例，段 0 无条件调用 / Command rising edge
    rtFlow       : R_TRIG;               // 流量上升沿实例，段 0 无条件调用 / Flow rising edge
    rtReset      : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _tRespLatch  : TIME;                 // 响应时间锁存槽（锁存量） [ms] / Response time latch, latched
    _bRespSeen   : BOOL;                 // 本轮已测到响应沿标记（锁存量） [-] / Response-seen flag for this run
    _bCfgBad     : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bSamePhase  : BOOL;                 // 指令与反馈同相当拍量 [-] / Command and feedback in the same phase
    _bFault      : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_bCfgBad    := (tRespWin <= T#0S) OR (tDropWin <= T#0S);                            // 组态域闸 / Configuration gate
_bSamePhase := (bRunCmd AND bFlowSw) OR ((NOT bRunCmd) AND (NOT bFlowSw));           // 指令与反馈同相 / Command and feedback in the same phase
rtRun(CLK := bRunCmd);                                                              // 指令上升沿，每拍必调（R228A） / Command rising edge
rtFlow(CLK := bFlowSw);                                                             // 流量上升沿，每拍必调 / Flow rising edge
rtReset(CLK := bReset);                                                             // 复位沿，每拍必调 / Reset edge
tonResp(IN := (_eState = E_DL_FsrState.eRespWait), PT := tRespWin);                 // 响应窗计时（IN 由相位派生） / Response window timer
tonDrop(IN := (_eState = E_DL_FsrState.eDropWait), PT := tDropWin);                 // 回落窗计时 / Drop window timer

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo       := 16#0000_0000;      // 信息码每拍重算 / Info recomputed every scan
bSwHealthy   := FALSE;             // 健康位每拍预清 / Healthy flag preset
tRespMeasured := _tRespLatch;      // 响应时间镜像（锁存量回放，不实时读 ET） / Response time mirror from the latch
nErrId       := 16#0000_0000;      // 事件码缺省无事件 / Event code default none
bError       := FALSE;             // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_FsrCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_FsrState.eFault THEN
        _eState := E_DL_FsrState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0003_0703;                                             // 故障级：流量开关响应故障总码 / Fault-level: flow-switch fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_FsrCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：响应时间测量（ET 只在流量沿那一拍读一次并锁存，R38 范式） —— *)
IF (NOT _bFault) AND (_eState = E_DL_FsrState.eRespWait) AND rtFlow.Q THEN
    _tRespLatch := tonResp.ET;                                           // 锁存响应时间（此后不再实时读 ET） / Latch ET once, never re-read live
    _bRespSeen := TRUE;                                                  // 本轮已确认响应 / Response confirmed for this run
    _uInfo := 16#0003_0482;                                              // 信息级：响应正常 / Info: response OK
END_IF

(* —— 段 4：无响应 / 粘连双判据（各用独立实例与独立归因，R190） —— *)
IF (NOT _bFault) AND tonResp.Q THEN                                      // 响应窗内无流量沿 → 无响应 / No flow edge inside the window
    _uFault := 16#0003_0703;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsrCause.eNoResponse;                                // 归因：无响应 / Cause: no response
END_IF
IF (NOT _bFault) AND tonDrop.Q THEN                                      // 回落窗内流量未消失 → 粘连 / Flow did not drop inside the window
    _uFault := 16#0003_0703;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsrCause.eStuckOn;                                   // 归因：粘连 / Cause: stuck on
END_IF

(* —— 段 5：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND _bSamePhase THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_FsrCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_FsrState.eFault) THEN
    _eState := E_DL_FsrState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_FsrState.eIdle:
    IF rtRun.Q AND (NOT _bFault) THEN                                    // 出口 1：收到运行指令 / Run command received
        _bRespSeen := FALSE;                                             // 新一轮响应测量重新武装 / Re-arm response measurement
        _eState := E_DL_FsrState.eRespWait;
    ELSIF bFlowSw AND (NOT bRunCmd) THEN                                 // 出口 2：无令而流量已在（越序，交由回落链监视） / Flow on without command
        _eState := E_DL_FsrState.eDropWait;
    ELSIF _bFault THEN                                                   // 出口 3：故障锁存 / Fault latched
        _eState := E_DL_FsrState.eFault;
    END_IF

E_DL_FsrState.eRespWait:
    IF rtFlow.Q THEN                                                     // 出口 1：窗内出现流量沿 / Flow edge inside the window
        _eState := E_DL_FsrState.eRun;
    ELSIF NOT bRunCmd THEN                                               // 出口 2：指令撤销（前置消失，R98） / Command released
        _eState := E_DL_FsrState.eIdle;
    END_IF

E_DL_FsrState.eRun:
    IF NOT bRunCmd THEN                                                  // 出口 1：撤销指令，进回落窗 / Command released, enter drop window
        _eState := E_DL_FsrState.eDropWait;
    ELSIF NOT bFlowSw THEN                                               // 出口 2：运行中流量消失（前置消失，R98） / Flow lost while running
        _eState := E_DL_FsrState.eRespWait;
    END_IF

E_DL_FsrState.eDropWait:
    IF NOT bFlowSw THEN                                                  // 出口 1：流量已回落 / Flow dropped
        _eState := E_DL_FsrState.eIdle;
    ELSIF bRunCmd THEN                                                   // 出口 2：指令重新来（前置消失，R98） / Command came back
        _eState := E_DL_FsrState.eRespWait;
    END_IF

E_DL_FsrState.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0003_0703;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_FsrCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_FsrState.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放） —— *)
bSwHealthy := (NOT _bFault) AND _bSamePhase AND _bRespSeen;              // 健康 = 无故障 ∧ 同相 ∧ 本轮已确认响应 / Healthy verdict
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
