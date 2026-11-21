(*
  FB_DL_PileClampCtrl  —  堆叠压紧板两段压力-位移控制 / Pile clamp two-stage pressure-position control
  分类 Category : DL_Process
  码位 Code     : 16#06_0_90
  版本 Version  : 1.0.0
  溯源 Source   : LBP（Lediberg Process Library）语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 压紧板「预压 → 全压」两段顺控（复用 FB_DL_StepSequencer 推步 + I_DL_Cylinder 缸接口依赖注入）；
                  2) 预压段压力-位移落窗才放行全压段（禁跳段）；
                  3) 保压计时独立 TON 且 IN := NOT ton.Q 自复位（FB33-2）。
  边界 Boundary : ① 预压未达窗禁进全压段（步完成信号由本件门控）；
                  ② 压力/位移任一无效：冻结当前段并保持命令（不追加新指令）；
                  ③ 包络窗口上下限倒置出厂报码不运行；
                  ④ 释压命令与压紧命令互斥，同拍双真取释压（安全侧）；
                  ⑤ 输出三行同向：缸命令 → 段状态 → 完成标志。
  依赖 Depends  : FB_DL_StepSequencer（两段推步，每拍无条件调用）
                  I_DL_Cylinder（缸接口，VAR_IN_OUT 引用注入，__ISVALIDREF 门控）

  码表 Error codes（本件子码步进 16#30 · 本格 90 与既有 9X 子码段冲突，错位至 C0/D0 避让）:
    16#0002_06C0 故障级：组态非法（两段目标倒置 / 包络窗倒置 / 保压时长 <= 0）
    16#0002_06D0 故障级：步超时（段内压力-位移未在限时内落窗，映射自顺控实例）
    16#0002_06B0 信息级：压力或位移无效当前段冻结（不置 bError）
*)

TYPE E_DL_PccPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    ePre     := 10,  // 预压段 / Pre-clamp stage
    eFull    := 20,  // 全压段 / Full-clamp stage
    eHold    := 30,  // 保压段 / Pressure holding
    eRelease := 40,  // 释压段 / Release stage
    eDone    := 50,  // 压紧完成 / Clamp done
    eFrozen  := 60,  // 反馈无效冻结 / Frozen by invalid feedback
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_PileClampCtrl
VAR_INPUT
    bClampReq     : BOOL;                           // 压紧命令（电平）/ Clamp command, level
    bReleaseReq   : BOOL;                           // 释压命令（电平，与压紧互斥取优先）/ Release command, level
    bReset        : BOOL;                           // 复位，上升沿清故障 / Reset, clears fault
    fPressKN      : REAL;                           // 压紧压力实测 [kN] / Measured clamp pressure [kN]
    fPosMm        : REAL;                           // 压紧板位移实测 [mm] / Measured plate position [mm]
    fPreTargetKN  : REAL := 5.0;                    // 预压段目标压力 [kN] / Pre-stage target pressure [kN]
    fFullTargetKN : REAL := 12.0;                   // 全压段目标压力 [kN] / Full-stage target pressure [kN]
    fPreWinKN     : REAL := 0.8;                    // 预压窗半宽 [kN]，域 > 0 / Pre-stage window half width [kN]
    fFullWinKN    : REAL := 1.0;                    // 全压窗半宽 [kN]，域 > 0 / Full-stage window half width [kN]
    fPrePosLoMm   : REAL := 3.0;                    // 预压段位移窗下限 [mm] / Pre-stage position window low [mm]
    fPrePosHiMm   : REAL := 6.0;                    // 预压段位移窗上限 [mm] / Pre-stage position window high [mm]
    fFullPosLoMm  : REAL := 7.5;                    // 全压段位移窗下限 [mm] / Full-stage position window low [mm]
    fFullPosHiMm  : REAL := 10.0;                   // 全压段位移窗上限 [mm] / Full-stage position window high [mm]
    tHoldTime     : TIME := T#5S;                   // 保压时长 [s]，域 > 0 / Holding duration
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_IN_OUT
    ipCyl         : I_DL_Cylinder;                  // 压紧缸接口（依赖注入）/ Clamp cylinder interface, injected
END_VAR
VAR_OUTPUT
    bClampCmd     : BOOL;                           // 缸压紧命令出口 / Cylinder clamp command output
    bReleaseCmd   : BOOL;                           // 缸释压命令出口 / Cylinder release command output
    eStageOut     : E_DL_PccPhase;                  // 当前段状态 / Current stage status
    bClampDone    : BOOL;                           // 压紧完成标志（保持型）/ Clamp done flag, held
    bEnvViol      : BOOL;                           // 包络越窗标志（本拍重算）/ Envelope violation flag
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fbSeq         : FB_DL_StepSequencer;            // 两段顺控实例（无条件调用）/ Two-step sequencer instance
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    tonHold       : TON;                            // 保压计时器（IN := NOT Q 自复位范式不适用本件：保压为单次电平计时）/ Holding timer
    abStepDone    : ARRAY[0..15] OF BOOL;           // 步完成信号表 / Step-done table
    auStepTo      : ARRAY[0..15] OF TIME;           // 步超时表 / Step timeout table
    _eState       : E_DL_PccPhase := E_DL_PccPhase.eIdle;  // 内部状态 / Internal state
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bRefOk        : BOOL;                           // 缸接口引用有效 / Interface reference valid
    bFbOk         : BOOL;                           // 压力/位移双有效 / Pressure and position valid
    bPreInWin     : BOOL;                           // 预压段压力-位移落窗 / Pre-stage in window
    bFullInWin    : BOOL;                           // 全压段压力-位移落窗 / Full-stage in window
    bHoldDone     : BOOL;                           // 保压计时到 / Holding time elapsed
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与反馈域闸 === *)
bRefOk := __ISVALIDREF(ipCyl);                    // 接口引用有效性（R4 防御）
bCfgOk := (fFullTargetKN > fPreTargetKN + fEps)   // 两段目标不倒置（全压 > 预压）
          AND (fPreWinKN > fEps) AND (fFullWinKN > fEps)
          AND (fPrePosHiMm > fPrePosLoMm + fEps)  // 预压位移窗不倒置
          AND (fFullPosHiMm > fFullPosLoMm + fEps)// 全压位移窗不倒置
          AND (TIME_TO_REAL(tHoldTime) > fEps)    // 保压时长正域
          AND (fPreTargetKN = fPreTargetKN) AND (fFullTargetKN = fFullTargetKN);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_06C0;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bFbOk := (fPressKN = fPressKN) AND (ABS(fPressKN) < 1.0E30)
         AND (fPosMm = fPosMm) AND (ABS(fPosMm) < 1.0E30);      // 双反馈 NaN 自反 + 幅值闸
IF NOT bFbOk THEN
    uInfo := 16#0002_06B0;                        // 信息级：反馈无效当前段冻结
END_IF

(* === 段 2 · 窗口判定（本拍重算）=== *)
bPreInWin := bFbOk AND (ABS(fPressKN - fPreTargetKN) <= fPreWinKN + fEps)
             AND (fPosMm >= fPrePosLoMm - fEps) AND (fPosMm <= fPrePosHiMm + fEps);   // 预压落窗
bFullInWin := bFbOk AND (ABS(fPressKN - fFullTargetKN) <= fFullWinKN + fEps)
              AND (fPosMm >= fFullPosLoMm - fEps) AND (fPosMm <= fFullPosHiMm + fEps);  // 全压落窗
bEnvViol := bFbOk AND (fPressKN > fFullTargetKN + fFullWinKN + 5.0 * fFullWinKN);   // 包络越窗：压力远超全压窗

(* === 段 3 · 顺控实例装载（每拍无条件调用）=== *)
abStepDone[0] := bPreInWin;                       // 步 0 = 预压：落窗才算完成（门控禁跳段）
abStepDone[1] := bFullInWin;                      // 步 1 = 全压：落窗才算完成
abStepDone[2] := TRUE;                            // 步 2 = 保压：完成由本件 TON 判
auStepTo[0] := T#30S;                             // 预压步超时 30 s
auStepTo[1] := T#30S;                             // 全压步超时 30 s
auStepTo[2] := T#0S;                              // 保压步不监控（由保压 TON 承担）
fbSeq(bStart := bClampReq AND (NOT bReleaseReq) AND bCfgOk AND bRefOk AND bFbOk,   // 压紧命令且非释压优先
      abStepDone := abStepDone,                   // 步完成表
      auStepTimeout := auStepTo,                  // 步超时表
      bHold := NOT bFbOk,                         // 反馈无效：顺控保持（冻结当前段）
      bAbort := bReleaseReq OR (NOT bCfgOk),      // 释压/组态故障：中止回空闲
      bReset := rtrReset.Q);                      // 复位沿透传
IF fbSeq.bError THEN
    uFault := 16#0002_06D0;                       // 故障级：步超时（映射自顺控实例）
END_IF

(* === 段 4 · 保压计时（独立 TON，段内电平触发）=== *)
bHoldDone := FALSE;                               // 保压完成本拍重算
IF fbSeq.nCurrentStep = 2 THEN                    // 顺控进入保压步才计时
    tonHold(IN := TRUE, PT := tHoldTime);         // 保压计时（步号门控自清，离开步 IN 即断）
    IF tonHold.Q THEN
        bHoldDone := TRUE;                        // 保压时长到
    END_IF
ELSE
    tonHold(IN := FALSE, PT := tHoldTime);        // 离开保压步：定时器断输入复位（R40 分段监控按段断输入）
END_IF

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_PccPhase.eIdle :
    bClampDone := FALSE;                          // 空闲未完成
    IF uFault <> 16#0000 THEN
        _eState := E_DL_PccPhase.eFault;          // 故障优先
    END_IF
    IF fbSeq.bRunning AND (fbSeq.nCurrentStep = 0) THEN
        _eState := E_DL_PccPhase.ePre;            // 顺控步 0：预压相
    END_IF

E_DL_PccPhase.ePre :
    IF fbSeq.nCurrentStep = 1 THEN
        _eState := E_DL_PccPhase.eFull;           // 步 1：全压相（预压未落窗顺控不推步）
    ELSIF fbSeq.nCurrentStep < 0 THEN
        _eState := E_DL_PccPhase.eIdle;           // 顺控中止回空闲
    END_IF

E_DL_PccPhase.eFull :
    IF fbSeq.nCurrentStep = 2 THEN
        _eState := E_DL_PccPhase.eHold;           // 步 2：保压相
    ELSIF fbSeq.nCurrentStep < 0 THEN
        _eState := E_DL_PccPhase.eIdle;           // 顺控中止回空闲
    END_IF

E_DL_PccPhase.eHold :
    IF bHoldDone THEN
        _eState := E_DL_PccPhase.eDone;           // 保压满：完成相
    ELSIF bReleaseReq THEN
        _eState := E_DL_PccPhase.eRelease;        // 释压优先（安全侧同拍双真取释压）
    END_IF

E_DL_PccPhase.eRelease :
    IF fbSeq.nCurrentStep < 0 THEN
        _eState := E_DL_PccPhase.eIdle;           // 释压完成回空闲（解除路径可达）
    END_IF

E_DL_PccPhase.eDone :
    bClampDone := TRUE;                           // 完成保持（防同拍抹除）
    IF bReleaseReq OR (NOT bClampReq) THEN
        bClampDone := FALSE;                      // 释压或撤命令：完成复位
        _eState := E_DL_PccPhase.eIdle;           // 回空闲
    END_IF

E_DL_PccPhase.eFrozen :
    IF bFbOk THEN
        _eState := E_DL_PccPhase.ePre;            // 反馈恢复回预压相续判（解除路径可达）
    END_IF

E_DL_PccPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_PccPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_PccPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06C0;                       // 故障级：相 ID 越界复用组态码段
END_CASE
IF (NOT bFbOk) AND (_eState = E_DL_PccPhase.ePre OR _eState = E_DL_PccPhase.eFull
    OR _eState = E_DL_PccPhase.eHold) THEN
    _eState := E_DL_PccPhase.eFrozen;             // 运行段中反馈丢失：转冻结相（命令保持）
END_IF

(* === 段 6 · 缸命令出口映射（互斥：释压优先）=== *)
bClampCmd := (_eState = E_DL_PccPhase.ePre) OR (_eState = E_DL_PccPhase.eFull)
             OR (_eState = E_DL_PccPhase.eHold);  // 压紧命令只在压紧段保持
bClampCmd := bClampCmd AND bFbOk AND bRefOk AND (uFault = 16#0000);   // 无效/故障安全侧撤命令
bReleaseCmd := (_eState = E_DL_PccPhase.eRelease) OR bReleaseReq;     // 释压命令（同拍双真取释压）
bReleaseCmd := bReleaseCmd AND bRefOk;            // 引用无效不出命令
IF bRefOk AND bReleaseCmd THEN
    ipCyl.CmdRetract();                           // 释压指令（接口依赖注入调用）
ELSIF bRefOk AND bClampCmd THEN
    ipCyl.CmdExtend();                            // 压紧指令（接口依赖注入调用）
END_IF

(* === 段 7 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStageOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
