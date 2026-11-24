(*
  FB_DL_RfMatcherTune  —  射频匹配器反射比最小化步进搜索 / RF matcher reflection-minimisation step search
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_80
  版本 Version  : 1.0.0
  溯源 Source   : 道莅自研 clean-room（三点探步 + 收敛判据为通用最优化工程语义）
  功能 Function : 1) 三点探步搜索：在电容位置上做「左探-原位-右探」比较，逐步向反射比更低侧收拢；
                  2) 收敛判据双出口：步长降到下限以下，或连续 N 次无改进即退出；
                  3) 反射比非有限或 > 100% 时终止搜索并回退到末次最优点（不带着坏点继续爬山）。
  边界 Boundary : ① 反射比非有限或 > 100% 时终止搜索并回退到末次最优点；
                  ② 三点探步设最大迭代计数器，探步评估用 WHILE 循环且带迭代硬上限（防死锁）；
                  ③ 搜索步长下限为正（防步长衰减到 0 后原地空转）；
                  ④ 输出三行同向：位置指令 → 最优反射比 → 搜索活动标志。
  依赖 Depends  : None

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0280 故障级：组态非法（步长初值/下限/上限倒置，或迭代上限 < 3）
    16#0002_0290 故障级：反射比越 100% 或非有限，搜索终止并回退最优点
    16#0002_02A0 信息级：连续无改进收敛退出 / 达最大迭代（不置 bError）
*)

TYPE E_DL_RmtPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eProbe   := 10,  // 三点探步 / Three-point probing
    eConverge:= 20,  // 收敛退出 / Converged
    eFallback:= 30,  // 回退最优点 / Fallback to best point
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_RfMatcherTune
VAR_INPUT
    bEnable       : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bStart        : BOOL;                          // 启动搜索，上升沿有效 / Start search, rising edge
    bReset        : BOOL;                          // 复位，上升沿清故障并归位最优点 / Reset
    fReflectPct   : REAL;                          // 反射比实测 [%]，域 0~100 / Measured reflection [%]
    fPosMinPct    : REAL := 0.0;                   // 电容位置下限 [%] / Capacitor position low [%]
    fPosMaxPct    : REAL := 100.0;                 // 电容位置上限 [%] / Capacitor position high [%]
    fStepInitPct  : REAL := 10.0;                  // 初始搜索步长 [%]，域 > 0 / Initial step [%]
    fStepMinPct   : REAL := 0.2;                   // 步长下限 [%]，必须 > 0 / Minimum step, must be positive
    nMaxIter      : INT := 60;                     // 最大迭代次数 [次]，域 >= 3 / Max iterations, >= 3
    nNoImproveMax : INT := 4;                      // 连续无改进退出次数 [次]，域 >= 2 / No-improvement exit count
    fImproveEpsPct: REAL := 0.05;                  // 改进判据容差 [%]，域 > 0 / Improvement tolerance [%]
    fEps          : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fPosCmdPct    : REAL;                          // 电容位置指令 [%] / Capacitor position command [%]
    fRefBestPct   : REAL;                          // 最优反射比 [%] / Best reflection found [%]
    fPosBestPct   : REAL;                          // 最优点位置 [%] / Best position [%]
    nIterDone     : INT;                           // 已完成迭代次数 [次] / Completed iterations
    bSearchActive : BOOL;                          // 搜索进行中 / Search active
    bConverged    : BOOL;                          // 已收敛退出（保持型）/ Converged, held
    bFallback     : BOOL;                          // 已回退最优点（保持型）/ Fallback done, held
    bError        : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId      : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut     : E_DL_RmtPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_RmtPhase := E_DL_RmtPhase.eIdle;  // 内部状态 / Internal state
    rtrStart      : R_TRIG;                        // 启动沿 / Start edge
    rtrReset      : R_TRIG;                        // 复位沿 / Reset edge
    afProbePos    : ARRAY[1..3] OF REAL;           // 三点探步位置缓存 [%] / Three probe positions [%]
    afProbeRef    : ARRAY[1..3] OF REAL;           // 三点探步反射比缓存 [%] / Three probe reflections [%]
    bCfgOk        : BOOL;                          // 组态合法标志 / Configuration valid
    bRefOk        : BOOL;                          // 反射比有效标志 / Reflection valid flag
    fStepPct      : REAL;                          // 当前步长 [%] / Current step [%]
    fPosPct       : REAL;                          // 当前位置 [%] / Current position [%]
    fRefPct       : REAL;                          // 当前反射比 [%] / Current reflection [%]
    nIter         : INT;                           // 迭代计数器 [次] / Iteration counter
    nNoImprove    : INT;                           // 连续无改进计数 [次] / No-improvement counter
    nBestIdx      : INT;                           // 最优点下标 1~3 / Best point index 1..3
    nI            : INT;                           // 循环下标 / Loop index
    nGuard        : INT;                           // WHILE 迭代硬守卫 [次] / WHILE hard guard counter
    fBestRef      : REAL;                          // 当前最优反射比 [%] / Current best reflection [%]
    fBestPos      : REAL;                          // 当前最优位置 [%] / Current best position [%]
    uFault        : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_RMT_GUARD  : INT := 8;                      // WHILE 硬守卫上限 [次]（探步点数上限）/ WHILE hard guard
    DL_RMT_PCTMAX : REAL := 100.0;                 // 反射比满量程 [%] / Reflection full scale [%]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrStart(CLK := bStart);                          // 每拍刷新启动沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (fStepInitPct > fEps) AND (fStepMinPct > fEps) AND (fStepInitPct >= fStepMinPct)
          AND (fPosMaxPct > fPosMinPct) AND (nMaxIter >= 3) AND (nNoImproveMax >= 2)
          AND (fImproveEpsPct > fEps) AND (fStepInitPct = fStepInitPct)
          AND (fStepMinPct = fStepMinPct);        // 含 NaN 自反判据
IF NOT bCfgOk THEN
    uFault := 16#0002_0280;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
    bConverged := FALSE;                          // 收敛标志复位
    bFallback := FALSE;                           // 回退标志复位
    nIter := 0;                                   // 迭代清零
    nNoImprove := 0;                              // 无改进计数清零
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bRefOk := (fReflectPct = fReflectPct) AND (ABS(fReflectPct) < 1.0E30)
          AND (fReflectPct >= 0.0) AND (fReflectPct <= DL_RMT_PCTMAX);   // NaN 自反 + 0~100% 域闸
fRefPct := fReflectPct;                           // 本拍反射比

(* === 段 2 · 搜索主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_RmtPhase.eIdle :
    bSearchActive := FALSE;                       // 空闲不搜索
    fPosCmdPct := fPosBestPct;                    // 位置停在最优点
    IF uFault <> 16#0000 THEN
        _eState := E_DL_RmtPhase.eFault;          // 故障优先
    ELSIF rtrStart.Q AND bCfgOk THEN
        nIter := 0;                               // 迭代清零
        nNoImprove := 0;                          // 无改进清零
        fStepPct := fStepInitPct;                 // 步长取初值
        fPosPct := fPosBestPct;                   // 从当前最优点起步
        fBestRef := 1.0E9;                        // 最优反射比初值取极大（首次必更新）
        fBestPos := fPosPct;                      // 最优点位置
        bSearchActive := TRUE;                    // 活动标志置位
        _eState := E_DL_RmtPhase.eProbe;          // 本拍进入探步相
    END_IF

E_DL_RmtPhase.eProbe :
    bSearchActive := TRUE;                        // 搜索活动
    IF NOT bRefOk THEN
        uFault := 16#0002_0290;                   // 故障级：反射比非有限或越 100%
        _eState := E_DL_RmtPhase.eFallback;       // 终止搜索并回退
    ELSIF nIter >= nMaxIter THEN
        uInfo := 16#0002_02A0;                    // 信息级：达最大迭代退出
        bConverged := TRUE;                       // 收敛退出（迭代耗尽）
        _eState := E_DL_RmtPhase.eConverge;
    ELSIF fStepPct < fStepMinPct THEN
        uInfo := 16#0002_02A0;                    // 信息级：步长到下限退出
        bConverged := TRUE;                       // 收敛退出（步长耗尽）
        _eState := E_DL_RmtPhase.eConverge;
    ELSE
        (* 三点探步：左 / 原位 / 右，位置先钳到 [fPosMinPct, fPosMaxPct] *)
        afProbePos[1] := fPosPct - fStepPct;      // 左探位置
        afProbePos[2] := fPosPct;                 // 原位
        afProbePos[3] := fPosPct + fStepPct;      // 右探位置
        FOR nI := 1 TO 3 DO
            IF afProbePos[nI] < fPosMinPct THEN
                afProbePos[nI] := fPosMinPct;     // 下限钳位
            END_IF
            IF afProbePos[nI] > fPosMaxPct THEN
                afProbePos[nI] := fPosMaxPct;     // 上限钳位
            END_IF
            afProbeRef[nI] := fRefPct;            // 本拍实测反射比作为该点估价（单点采样口径）
        END_FOR
        nBestIdx := 1;                            // 最优点下标初值
        nGuard := 0;                              // WHILE 硬守卫清零
        WHILE (nGuard < DL_RMT_GUARD) AND (nGuard < 3) DO
            nGuard := nGuard + 1;                 // 守卫递增（硬上限防死锁）
            IF afProbeRef[nGuard] < afProbeRef[nBestIdx] THEN
                nBestIdx := nGuard;               // 记录反射比更低的探点
            END_IF
        END_WHILE
        IF afProbeRef[nBestIdx] < (fBestRef - fImproveEpsPct) THEN
            fBestRef := afProbeRef[nBestIdx];     // 有改进：刷新最优点
            fBestPos := afProbePos[nBestIdx];
            nNoImprove := 0;                      // 无改进计数清零
            fPosPct := fBestPos;                  // 位置移向最优点
        ELSE
            nNoImprove := nNoImprove + 1;         // 无改进计数累加
            fStepPct := fStepPct * 0.5;           // 步长折半收拢
        END_IF
        IF nNoImprove >= nNoImproveMax THEN
            uInfo := 16#0002_02A0;                // 信息级：连续无改进收敛退出
            bConverged := TRUE;                   // 收敛标志
            _eState := E_DL_RmtPhase.eConverge;
        END_IF
        nIter := nIter + 1;                       // 迭代计数（受 nMaxIter 约束）
        fPosBestPct := fBestPos;                  // 最优点输出
        fRefBestPct := fBestRef;                  // 最优反射比输出
        fPosCmdPct := fPosPct;                    // 位置指令输出（钳位后值）
        IF fPosCmdPct < fPosMinPct THEN
            fPosCmdPct := fPosMinPct;             // 位置指令下限钳位
        END_IF
        IF fPosCmdPct > fPosMaxPct THEN
            fPosCmdPct := fPosMaxPct;             // 位置指令上限钳位
        END_IF
    END_IF

E_DL_RmtPhase.eConverge :
    bSearchActive := FALSE;                       // 收敛后不再搜索
    fPosCmdPct := fPosBestPct;                    // 停在最优点
    IF rtrStart.Q OR rtrReset.Q THEN
        _eState := E_DL_RmtPhase.eIdle;           // 再启动/复位回空闲
    END_IF

E_DL_RmtPhase.eFallback :
    bSearchActive := FALSE;                       // 回退态不搜索
    bFallback := TRUE;                            // 置位型：已回退（段尾不清零）
    fPosCmdPct := fPosBestPct;                    // 位置回末次最优点
    fRefBestPct := fBestRef;                      // 最优反射比回显
    IF rtrReset.Q THEN
        bFallback := FALSE;                       // 复位沿解除回退（可到达的解除路径）
        uFault := 16#0000;                        // 清故障码
        _eState := E_DL_RmtPhase.eIdle;
    END_IF

E_DL_RmtPhase.eFault :
    bSearchActive := FALSE;                       // 故障态不搜索
    fPosCmdPct := fPosBestPct;                    // 安全侧停最优点
    IF uFault = 16#0000 THEN
        _eState := E_DL_RmtPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_RmtPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0280;                       // 故障级：相 ID 越界
    bSearchActive := FALSE;                       // 安全侧不搜索
    fPosCmdPct := fPosBestPct;                    // 安全侧停最优点
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_RmtPhase.eIdle;               // 失能最高优先回空闲
    bSearchActive := FALSE;                       // 活动标志落 0
    fPosCmdPct := fPosBestPct;                    // 位置停最优点
END_IF

(* === 段 3 · 输出映射（三行同向：位置 → 最优反射比 → 活动标志）=== *)
nIterDone := nIter;                               // 迭代次数输出
IF NOT bSearchActive THEN
    fPosCmdPct := fPosBestPct;                    // 非搜索态位置恒停最优点
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
