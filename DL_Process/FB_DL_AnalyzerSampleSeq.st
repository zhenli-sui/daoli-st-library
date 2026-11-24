(*
  FB_DL_AnalyzerSampleSeq  —  在线分析仪取样-吹扫-标定三态轮换顺控 / Online analyzer sample-purge-calibrate sequence
  分类 Category : DL_Process
  码位 Code     : 16#06_0_92
  版本 Version  : 1.0.0
  溯源 Source   : ISA-88 相模型语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 取样-吹扫-标定三态轮换顺控（取样周期经 FB_DL_StepSequencer 两步推进：取样 → 吹扫）；
                  2) 各相超时独立 TON 升级（相超时转故障相，非死等）；
                  3) 标定过期锁存：过期期间禁取样出口有效（联锁前置）。
  边界 Boundary : ① 相切换须先完成当前相（禁打断取样，仅故障/急停可打断）；
                  ② 三命令同拍多真按 标定 > 吹扫 > 取样 优先级仲裁并置信息码；
                  ③ 吹扫计时分段自复位（相离开即断输入，R40）；
                  ④ 标定过期锁存仅标定完成可解除（解除路径可达）；
                  ⑤ 输出三行同向：当前相 → 取样有效 → 标定过期。
  依赖 Depends  : FB_DL_StepSequencer × 1（取样周期两步推进，每拍无条件调用）

  码表 Error codes（本件子码步进 16#30 · 本格 92 与既有 9X 子码段冲突，错位至 C2/D2 避让）:
    16#0002_06C2 故障级：组态非法（任一相时长 <= 0 / 标定周期 <= 0）
    16#0002_06D2 故障级：相超时（取样/吹扫/标定任一相在限时内未完成，锁存需复位）
    16#0002_06B2 信息级：三命令同拍多真已仲裁 / 标定过期取样出口已闭锁（不置 bError）
*)

TYPE E_DL_AnaPhase :
(
    eIdle   := 0,   // 空闲 / Idle
    eSample := 10,  // 取样相 / Sampling
    ePurge  := 20,  // 吹扫相 / Purging
    eCal    := 30,  // 标定相 / Calibrating
    eFault  := 90   // 相超时故障锁定 / Phase timeout fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnalyzerSampleSeq
VAR_INPUT
    bSampleReq    : BOOL;                           // 取样命令 / Sample request
    bPurgeReq     : BOOL;                           // 吹扫命令 / Purge request
    bCalReq       : BOOL;                           // 标定命令 / Calibration request
    bSampleDone   : BOOL;                           // 取样完成反馈（取样体积/流路到位）/ Sample done feedback
    bPurgeDone    : BOOL;                           // 吹扫完成反馈 / Purge done feedback
    bCalDone      : BOOL;                           // 标定完成反馈 / Calibration done feedback
    bReset        : BOOL;                           // 复位，上升沿清故障 / Reset, clears fault
    tSampleMax    : TIME := T#120S;                 // 取样相限时 [s]，域 > 0 / Sample phase timeout
    tPurgeMax     : TIME := T#60S;                  // 吹扫相限时 [s]，域 > 0 / Purge phase timeout
    tCalMax       : TIME := T#600S;                 // 标定相限时 [s]，域 > 0 / Calibration phase timeout
    tPurgeMin     : TIME := T#10S;                  // 吹扫最短时长 [s]，域 > 0 / Purge minimum duration
    uCalAgeMin    : UDINT;                          // 距上次标定累计分钟 [min]（调用方注入）/ Minutes since last calibration
    uCalPeriodMin : UDINT := 1440;                  // 标定周期 [min]，域 > 0 / Calibration period [min]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    ePhaseOut     : E_DL_AnaPhase;                  // 当前相出口 / Current phase output
    bSampleValid  : BOOL;                           // 取样出口有效（联锁前置：标定未过期 + 相完成）/ Sample output valid
    bCalOverdue   : BOOL;                           // 标定过期锁存 / Calibration overdue latched
    bAbortSample  : BOOL;                           // 取样被打断标志（诊断）/ Sample aborted flag
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fbSeq         : FB_DL_StepSequencer;            // 取样周期两步顺控实例（无条件调用）/ Sample-cycle sequencer
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    tonSample     : TON;                            // 取样相超时（独立 TON）/ Sample phase timeout timer
    tonPurge      : TON;                            // 吹扫相超时 / Purge phase timeout timer
    tonPurgeMin   : TON;                            // 吹扫最短时长 / Purge minimum duration timer
    tonCal        : TON;                            // 标定相超时 / Calibration phase timeout timer
    abStepDone    : ARRAY[0..15] OF BOOL;           // 步完成表 / Step-done table
    auStepTo      : ARRAY[0..15] OF TIME;           // 步超时表 / Step timeout table
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    _eState       : E_DL_AnaPhase := E_DL_AnaPhase.eIdle;  // 内部状态 / Internal state
    bSampleReqEff : BOOL;                           // 仲裁后取样请求 / Arbitrated sample request
    bPurgeReqEff  : BOOL;                           // 仲裁后吹扫请求 / Arbitrated purge request
    bMultiCmd     : BOOL;                           // 同拍多真标志 / Multi-command this scan
    bPurgeMinOk   : BOOL;                           // 吹扫最短时长已满足 / Purge minimum duration met
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与命令仲裁 === *)
bCfgOk := (TIME_TO_REAL(tSampleMax) > fEps) AND (TIME_TO_REAL(tPurgeMax) > fEps)
          AND (TIME_TO_REAL(tCalMax) > fEps) AND (TIME_TO_REAL(tPurgeMin) > fEps)
          AND (uCalPeriodMin > UDINT#0);          // 相时长与标定周期正域
IF NOT bCfgOk THEN
    uFault := 16#0002_06C2;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bMultiCmd := bSampleReq AND bPurgeReq OR bSampleReq AND bCalReq OR bPurgeReq AND bCalReq;  // 同拍多真判据
bSampleReqEff := bSampleReq AND (NOT bPurgeReq) AND (NOT bCalReq);   // 仲裁：标定 > 吹扫 > 取样
bPurgeReqEff := bPurgeReq AND (NOT bCalReq);      // 吹扫次优先
IF bMultiCmd THEN
    uInfo := 16#0002_06B2;                        // 信息级：同拍多真已按优先级仲裁
END_IF

(* === 段 2 · 相超时定时器（独立 TON，相离开即断输入自复位，R40）=== *)
tonSample(IN := (_eState = E_DL_AnaPhase.eSample), PT := tSampleMax);   // 取样相超时计时
tonPurge(IN := (_eState = E_DL_AnaPhase.ePurge), PT := tPurgeMax);     // 吹扫相超时计时
tonCal(IN := (_eState = E_DL_AnaPhase.eCal), PT := tCalMax);           // 标定相超时计时
IF tonSample.Q OR tonPurge.Q OR tonCal.Q THEN
    uFault := 16#0002_06D2;                       // 故障级：任一相超时（锁存，非死等）
END_IF
tonPurgeMin(IN := (_eState = E_DL_AnaPhase.ePurge), PT := tPurgeMin);   // 吹扫最短时长（相离开即断输入，R40 分段断电）
bPurgeMinOk := tonPurgeMin.Q;                     // 最短时长计时到（Q = 已满足最短吹扫时长）

(* === 段 3 · 取样周期顺控实例（无条件调用：取样步 → 吹扫步）=== *)
abStepDone[0] := bSampleDone;                     // 步 0 = 取样：完成反馈门控
abStepDone[1] := bPurgeDone AND bPurgeMinOk;      // 步 1 = 吹扫：完成反馈且最短时长已过
auStepTo[0] := T#0S;                              // 取样步超时由相级 tonSample 承担（避免双口径）
auStepTo[1] := T#0S;                              // 吹扫步同上
fbSeq(bStart := bSampleReqEff AND (uFault = 16#0000) AND (NOT bCalOverdue),   // 取样请求且未过期才启动
      abStepDone := abStepDone,                   // 步完成表
      auStepTimeout := auStepTo,                  // 步超时表（相级承担）
      bHold := FALSE,                             // 不外持（相级超时承担升级）
      bAbort := (uFault <> 16#0000) OR bPurgeReqEff OR bCalReq,   // 故障/吹扫/标定命令中止顺控
      bReset := rtrReset.Q);                      // 复位沿透传

(* === 段 4 · 标定过期锁存 === *)
IF (uCalAgeMin >= uCalPeriodMin) AND (uCalPeriodMin > UDINT#0) THEN
    bCalOverdue := TRUE;                          // 到期锁存
    uInfo := 16#0002_06B2;                        // 信息级：过期取样出口闭锁
END_IF
IF _eState = E_DL_AnaPhase.eCal AND bCalDone THEN
    bCalOverdue := FALSE;                         // 标定完成反馈解除锁存（解除路径可达）
END_IF

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_AnaPhase.eIdle :
    bSampleValid := FALSE;                        // 空闲不出有效
    IF uFault <> 16#0000 THEN
        _eState := E_DL_AnaPhase.eFault;          // 故障优先
    ELSIF bCalReq THEN
        _eState := E_DL_AnaPhase.eCal;            // 标定命令最高优先
    ELSIF bPurgeReqEff THEN
        _eState := E_DL_AnaPhase.ePurge;          // 吹扫次优先
    ELSIF bSampleReqEff AND (NOT bCalOverdue) THEN
        _eState := E_DL_AnaPhase.eSample;         // 取样联锁前置：过期禁取样
    END_IF

E_DL_AnaPhase.eSample :
    bSampleValid := FALSE;                        // 取样中出口未有效（相完成才有效）
    IF uFault <> 16#0000 THEN
        bAbortSample := TRUE;                     // 故障打断取样（仅故障可打断，禁其他相打断）
        _eState := E_DL_AnaPhase.eFault;          // 转故障相
    ELSIF fbSeq.nCurrentStep = 1 THEN
        _eState := E_DL_AnaPhase.ePurge;          // 顺控推到吹扫步：转吹扫相（先完成当前相才切换）
    END_IF

E_DL_AnaPhase.ePurge :
    bSampleValid := FALSE;                        // 吹扫相不出有效
    IF uFault <> 16#0000 THEN
        _eState := E_DL_AnaPhase.eFault;          // 故障转出
    ELSIF bPurgeDone AND bPurgeMinOk THEN
        bSampleValid := TRUE;                     // 吹扫完成且最短时长满足：取样出口有效（本轮吹扫后样本可用）
        _eState := E_DL_AnaPhase.eIdle;           // 回空闲待下轮
    END_IF

E_DL_AnaPhase.eCal :
    bSampleValid := FALSE;                        // 标定相不出有效
    IF uFault <> 16#0000 THEN
        _eState := E_DL_AnaPhase.eFault;          // 故障转出
    ELSIF bCalDone THEN
        bCalOverdue := FALSE;                     // 标定完成解除过期锁存
        _eState := E_DL_AnaPhase.eIdle;           // 回空闲
    END_IF

E_DL_AnaPhase.eFault :
    bSampleValid := FALSE;                        // 故障相闭锁出口
    IF uFault = 16#0000 THEN
        bAbortSample := FALSE;                    // 解锁同步清打断标志
        _eState := E_DL_AnaPhase.eIdle;           // 回空闲
    END_IF

ELSE
    _eState := E_DL_AnaPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06C2;                       // 故障级：相 ID 越界复用组态码段
END_CASE

(* === 段 6 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
ePhaseOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
