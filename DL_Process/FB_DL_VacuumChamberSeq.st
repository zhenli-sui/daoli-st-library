(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VacuumChamberSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / R_TRIG / ABS，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 真空腔体抽真空顺控公开工艺语义（行业池），
 *                         道莅 clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 纯真空腔体五相顺控原子（不含工艺加热）：粗抽至
 *                         粗抽阈值 → 精抽至目标（迟滞防边界抖动）→ 检漏
 *                         （消费 bLeakOk）→ 放气（数字阀经缓启时序等价
 *                         斜坡限幅防冲击）→ 完成。相转换本拍复验数据源
 *                         （R42）；步超时锁故障；中止安全次序写死：
 *                         先停泵、延时后才开放气阀。
 * 组合建议 (Composition): 与库内 FB_DL_SlitValveInterlock 组合使用——本件
 *                         给出真空工艺时序，闸阀联锁由该件承担，二者经
 *                         bLeakOk/泵指令引脚对接，不互相内嵌。
 * 状态机   (States)     : eIdle/eRough/eFine/eLeakTest/eVent/eFault，
 *                         CASE 带 ELSE 锁安全侧（全阀关、全泵停）。
 * 码位     (Codes)      : 16#0005_009E 信息级：压强数据非有限冻结当前相、
 *                                      迟滞等待提示（不置 bError）
 *                         16#0005_009F 故障级：相超时
 *                         16#0005_00A0 故障级：联锁违例（非空闲相重启）
 *                         16#0005_00A1 故障级：状态非法（ELSE 兜底，锁存）
 *                         16#0005_00A2 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 压强非有限（x<>x 自反判加幅值界）冻结当前相；
 *                         2 精抽到位判定带迟滞：超回差即回信息级等待；
 *                         3 TON/R_TRIG 实例每拍无条件刷新，按相断输入；
 *                         4 CASE 带 ELSE 锁安全侧；
 *                         5 故障锁存可达解除路径：中止沿复归待机；
 *                         6 相转换本拍复验数据源（R42）。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 12）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_VacPhase（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_VacPhase :
(
    eIdle     := 0,    // 空闲：全泵停全阀关 / Idle, all pumps and valves off
    eRough    := 10,   // 粗抽相：粗抽泵运行 / Rough phase, rough pump running
    eFine     := 20,   // 精抽相：精抽泵运行 / Fine phase, fine pump running
    eLeakTest := 30,   // 检漏相：泵停隔离等待结论 / Leak test, pumps off, isolated
    eVent     := 40,   // 放气相：缓启时序后开阀 / Vent phase, valve after ramp delay
    eFault    := 99    // 故障：锁定等待中止复位 / Fault, latched until abort reset
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_VacuumChamberSeq
 * 调用约定: 每个扫描周期无条件调用一次；压强信号经引脚注入。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_VacuumChamberSeq
VAR_INPUT
    bStart   : BOOL := FALSE;         // 启动沿（空闲相受理）/ Start edge, accepted in idle
    bAbort   : BOOL := FALSE;         // 中止沿：任意相安全退出 / Abort edge, safe exit from any phase
    fPNow    : REAL := 101325.0;      // 腔体当前压强 [帕] / Chamber current pressure [Pa]
    fPTgt    : REAL := 10.0;          // 精抽目标压强 [帕] / Fine target pressure [Pa]
    fPRough  : REAL := 500.0;         // 粗抽切换阈值 [帕] / Rough crossover threshold [Pa]
    bLeakOk  : BOOL := FALSE;         // 检漏结论注入（外部检漏件）/ Leak verdict injected by caller
    tStepMax : TIME := T#600S;        // 单相超时 [毫秒] / Per-phase timeout [ms]
    tVentRamp: TIME := T#5S;          // 放气缓启时序 [毫秒]（斜坡限幅等价实现）/ Vent ramp delay [ms]
END_VAR
VAR_OUTPUT
    ePhase    : E_DL_VacPhase;        // 当前相状态 / Current phase
    bPumpRough: BOOL;                 // 粗抽泵指令 / Rough pump command
    bPumpFine : BOOL;                 // 精抽泵指令 / Fine pump command
    bVent     : BOOL;                 // 放气阀指令 / Vent valve command
    bDone     : BOOL;                 // 流程完成单拍脉冲（R27）/ Sequence done one-scan pulse
    bError    : BOOL;                 // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId  : UDINT;                // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigStart: R_TRIG;               // 启动沿检测，每拍无条件刷新 / Start edge detector, refreshed every scan
    rTrigAbort: R_TRIG;               // 中止沿检测，每拍无条件刷新 / Abort edge detector, refreshed every scan
    tonPhase  : TON;                  // 相超时定时器，每拍无条件刷新 / Phase timeout timer, refreshed every scan
    tonVent   : TON;                  // 放气缓启定时器，每拍无条件刷新 / Vent ramp timer, refreshed every scan
    eStatePrev: E_DL_VacPhase;        // 上一拍相快照 / Previous phase snapshot
    bStepRst  : BOOL;                 // 相切换拍单拍断超时输入 / One-scan timeout break on phase change
    bDataOk   : BOOL;                 // 压强三点有效性 / Three pressure points validity
    bHystWait : BOOL;                 // 迟滞等待标志 / Hysteresis waiting flag
    bAborted  : BOOL;                 // 中止退出路径标志 / Abort exit path flag
    uCodeLatch: UDINT;                // 故障级锁存码 / Latched fault code
    bInit     : BOOL := TRUE;         // 首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_VCS_FIN    : REAL := 1.0E30;   // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_VCS_HYST   : REAL := 1.1;      // 精抽迟滞回差系数（超回差回等待）/ Fine hysteresis back factor
    DL_VCS_PATM   : REAL := 90000.0;  // 放气完成压强阈 [帕] / Vent complete pressure threshold [Pa]
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigStart(CLK := bStart);                            // 启动沿检测 / Start edge detection
rTrigAbort(CLK := bAbort);                            // 中止沿检测 / Abort edge detection
tonVent(IN := (ePhase = eVent), PT := tVentRamp);     // 缓启计时按相断输入 / Ramp timing input per phase
tonPhase(IN := (ePhase <> eIdle) AND (ePhase <> eFault) AND (ePhase <> eVent)
         AND (NOT bStepRst), PT := tStepMax);         // 相超时计时，相切换拍断输入 / Phase timeout timing

// ---- 段 2｜相切换检测与数据有效性 ----------------------------------------------
bStepRst := (ePhase <> eStatePrev) OR bInit;          // 相变化即断输入 / Phase change breaks timing input
eStatePrev := ePhase;                                 // 快照留痕 / Snapshot previous phase
bInit := FALSE;                                       // 清首扫标志 / Clear first-scan flag
bDataOk := (fPNow = fPNow) AND (fPTgt = fPTgt) AND (fPRough = fPRough)
       AND (ABS(fPNow) < DL_VCS_FIN) AND (ABS(fPTgt) < DL_VCS_FIN)
       AND (ABS(fPRough) < DL_VCS_FIN);               // 压强三点有限 / Three points finite

// ---- 段 3｜中止沿统一入口：先停泵、缓启延时后才放气（安全次序写死）--------------
IF rTrigAbort.Q AND (ePhase <> eIdle) THEN
    ePhase   := eVent;                                // 转放气相执行退出 / To vent phase for exit
    bAborted := TRUE;                                 // 登记中止路径 / Mark abort path
END_IF

// ---- 段 4｜状态机（CASE 带 ELSE 锁安全侧：全泵停全阀关）--------------------------
CASE ePhase OF
    eIdle:
        bPumpRough := FALSE;                          // 空闲全停 / All off in idle
        bPumpFine  := FALSE;                          // 空闲全停 / All off in idle
        bVent      := FALSE;                          // 空闲阀关 / Valve closed in idle
        bDone      := FALSE;                          // 清完成脉冲 / Clear done pulse
        bAborted   := FALSE;                          // 清中止标志 / Clear abort flag
        IF rTrigStart.Q AND bDataOk AND (fPTgt < fPRough) THEN
            ePhase := eRough;                         // 数据合法且目标低于切换阈才启动 / Legal data and sane targets
        END_IF
    eRough:
        bPumpRough := bDataOk AND NOT bAborted;       // 粗抽泵指令带数据门控 / Rough pump gated by data
        bPumpFine  := FALSE;                          // 精抽泵停 / Fine pump off
        bVent      := FALSE;                          // 阀关 / Valve closed
        IF NOT bDataOk THEN
            uErrorId := 16#0005_009E;                 // 信息级：数据非有限冻结当前相 / Info: non-finite freezes phase
        ELSIF tonPhase.Q THEN
            ePhase := eFault;                         // 相超时锁故障 / Phase timeout, fault
            uCodeLatch := 16#0005_009F;               // 码位：相超时 / Code: phase timeout
        ELSIF bDataOk AND (fPNow <= fPRough) THEN
            ePhase := eFine;                          // 复验后转精抽（R42）/ Recheck then to fine
        END_IF
    eFine:
        bPumpRough := FALSE;                          // 粗抽泵停（交叉点切换）/ Rough pump off at crossover
        bPumpFine  := bDataOk AND NOT bAborted;       // 精抽泵指令带数据门控 / Fine pump gated by data
        bVent      := FALSE;                          // 阀关 / Valve closed
        bHystWait  := bDataOk AND (fPNow > fPTgt * DL_VCS_HYST); // 超回差等待 / Beyond hysteresis, wait
        IF NOT bDataOk THEN
            uErrorId := 16#0005_009E;                 // 信息级：数据非有限冻结当前相 / Info: non-finite freezes phase
        ELSIF tonPhase.Q THEN
            ePhase := eFault;                         // 相超时锁故障 / Phase timeout, fault
            uCodeLatch := 16#0005_009F;               // 码位：相超时 / Code: phase timeout
        ELSIF bHystWait THEN
            uErrorId := 16#0005_009E;                 // 信息级：迟滞等待提示 / Info: hysteresis waiting
        ELSIF bDataOk AND (fPNow <= fPTgt) THEN
            ePhase := eLeakTest;                      // 复验后转检漏（R42）/ Recheck then to leak test
        END_IF
    eLeakTest:
        bPumpRough := FALSE;                          // 检漏隔离全泵停 / Isolated, all pumps off
        bPumpFine  := FALSE;                          // 检漏隔离全泵停 / Isolated, all pumps off
        bVent      := FALSE;                          // 阀关 / Valve closed
        IF tonPhase.Q THEN
            ePhase := eFault;                         // 相超时锁故障 / Phase timeout, fault
            uCodeLatch := 16#0005_009F;               // 码位：相超时 / Code: phase timeout
        ELSIF bLeakOk THEN
            ePhase := eVent;                          // 检漏合格转放气 / Leak OK, to vent
        END_IF
    eVent:
        bPumpRough := FALSE;                          // 放气相全泵停 / All pumps off in vent
        bPumpFine  := FALSE;                          // 放气相全泵停 / All pumps off in vent
        bVent      := tonVent.Q;                      // 缓启时序满才开阀（先停泵后放气）/ Valve after ramp, pumps first
        IF (NOT bAborted) AND bDataOk AND (fPNow >= DL_VCS_PATM) THEN
            ePhase := eIdle;                          // 正常放气完成回待机 / Normal vent complete
            bDone := TRUE;                            // 完成单拍脉冲 / One-scan done pulse
        ELSIF bAborted AND tonVent.Q THEN
            ePhase := eIdle;                          // 中止退出回待机 / Abort exit back to idle
            bDone := FALSE;                           // 中止不置完成 / Abort never sets done
        END_IF
    eFault:
        bPumpRough := FALSE;                          // 故障安全侧全停 / Fault safe side all off
        bPumpFine  := FALSE;                          // 故障安全侧全停 / Fault safe side all off
        bVent      := FALSE;                          // 故障安全侧阀关 / Fault safe side valve closed
        bDone      := FALSE;                          // 故障清完成 / Fault clears done
        IF rTrigAbort.Q THEN
            ePhase := eIdle;                          // 可达解除路径：中止沿复归 / Reachable release: abort edge
            uCodeLatch := 16#0000_0000;               // 清锁存码 / Clear latched code
        END_IF
    ELSE
        ePhase := eFault;                             // 非法状态兜底 / Illegal state fallback
        uCodeLatch := 16#0005_00A1;                   // 码位：状态非法 / Code: illegal state
END_CASE

// ---- 段 5｜联锁违例防御：非空闲相受理启动沿 --------------------------------------
IF rTrigStart.Q AND (eStatePrev <> eIdle) AND (ePhase <> eIdle) AND (ePhase <> eFault) THEN
    ePhase := eFault;                                 // 违例锁故障 / Violation latches fault
    uCodeLatch := 16#0005_00A0;                       // 码位：联锁违例 / Code: interlock violation
END_IF

// ---- 段 6｜错误码装配：故障锁存回放优先，信息级居次 ------------------------------
IF ePhase = eFault THEN
    bError   := TRUE;                                 // 故障标志配对（R45）/ Fault flag paired
    uErrorId := uCodeLatch;                           // 故障码锁存回放 / Latched fault code replayed
ELSIF (NOT bDataOk) OR bHystWait THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := 16#0005_009E;                         // 信息级：冻结/迟滞等待 / Info: frozen or hysteresis wait
ELSE
    bError   := FALSE;                                // 无错清标志 / Clear fault flag
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF
END_FUNCTION_BLOCK
