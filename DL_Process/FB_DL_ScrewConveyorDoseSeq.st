(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ScrewConveyorDoseSeq
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-24
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / ABS / MAX），零厂商私有库
 * 功能描述 (Function)   : 螺旋给料计量批次序列：预检 → 喂料（按 fFlowKgh × dt 定周期积算，
 *                         达提前量停料）→ 停料稳定 tSettle → 称量结算（算误差百分比、批次 +1、
 *                         发 bBatchDone 单拍）→ 完成相（bStart 仍 TRUE 则自动进入下一批）。
 *                         **积算口径**：dt 由定周期采样节拍 tonDt（PT = 100ms 常数）生成，
 *                         积分步长 _fDtSec = TIME_TO_LREAL(DL_SCD_DT)，且入口做 dt > EPS 闸
 *                         （防 dt ≤ 0 / 非正步长导致积分反向或除零，R4）；非采样拍不积分。
 *                         **提前量**：停料阈值 _fStopThr := fTargetKg × (1 − fTolPct/100)，
 *                         使停料后的空中料流残量落进容差带；eWeigh 再按实际 fDosedKg 结算。
 *                         **bStart = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         bMotorRun 落 FALSE 并回 eIdle（螺旋不得冻结保持，冻结即过量给料）。
 * 接口     (Interface)  : 输入 bEnable / bStart / bReset（上升沿）/ fTargetKg / fFlowKgh /
 *                         tSettle / tTimeout / fTolPct / bMotorFb；
 *                         输出 bMotorRun / fDosedKg / fErrPct / nBatchCnt / bBatchDone（单拍）/
 *                         eState（E_DL_ScdPhase）/ eCause（E_DL_ScdCause）/ bError / bValid。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → ePreCheck：bEnable 且 bStart 且组态闸通过且 fTargetKg > 0 且无锁存；
 *      拍 N 进入 / 本拍行为：清 fDosedKg、fErrPct、nBatchCnt、bMotorRun=FALSE / 拍 N+1 转出。
 *   ② ePreCheck → eFeeding：预检相单拍驻留（本拍清零 fDosedKg / fErrPct，保证连续批次每批独立）；
 *      拍 N 进入 / 本拍行为：置 bMotorRun=TRUE / 拍 N+1 转出至 eFeeding。
 *   ③ eFeeding → eSettle：fDosedKg ≥ _fStopThr 或 fDosedKg ≥ fTargetKg（达量，事件优先于超时，
 *      FB51-5）；拍 N 进入 / 本拍行为：bMotorRun=FALSE、清积分节拍 / 拍 N+1 转出至 eSettle。
 *   ④ eSettle → eWeigh：tonSettle.Q（停料稳定到时）；拍 N 进入 / 本拍行为：bMotorRun=FALSE /
 *      拍 N+1 转出至 eWeigh。
 *   ⑤ eWeigh → eDone：单拍结算；本拍行为：nBatchCnt+1、置 _bBatchDoneInt（统一出口映射，
 *      FB33-1）、按 |fErrPct| 与 fTolPct 发 eBatchDone / eOutOfTol（均信息级）/ 拍 N+1 转出。
 *   ⑥ eDone → ePreCheck：bStart 仍 TRUE（连续批次）；拍 N 进入 / 本拍行为：bMotorRun=FALSE /
 *      拍 N+1 转出至 ePreCheck。⑦ eDone → eIdle：bStart 落 FALSE（前置消失，R98 两条出口）。
 *   ⑧ eFeeding → eFault：fFlowKgh < 0（eBadFlow，即时）/ 流量为 0 持续 tTimeout（eNoFlow）/
 *      总超时 tTimeout（eTimeout）/ bMotorRun 与 bMotorFb 不一致达 3s（eMotorNoFb）/
 *      全相入参非有限（eNonFinite）。锁存后由段尾迁移闸迁相（R21）。
 *   ⑨ eFault → eIdle：bReset 上升沿（R_TRIG 判 .Q）且 bEnable = FALSE（R19 穷举出口）；
 *      拍 N 进入 / 本拍行为：清锁存、成因、bMotorRun=FALSE / 拍 N+1 转出至 eIdle。
 *   ⑩ ELSE（非法枚举值）→ eFault，成因 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① 五个 TON 与 R_TRIG 全在 CASE 外无条件调用（R7）；tonDt / tonTotal /
 *                            tonNoFlow / tonSettle / tonMotFb 的 IN 均含 NOT .Q 自复位项（R188）。
 *                         ② 积分步长闸：_fDtSec > DL_SCD_EPS 才积分（R4 防 dt ≤ 0）；
 *                            fTargetKg ≤ EPS 时不做百分比除法，fErrPct 置 0 哨兵（除零不可达）。
 *                         ③ 浮点比较一律容差或大小比较，禁 `=`/`<>`（R4）；零流量判据为
 *                            ABS(fFlowKgh) < DL_SCD_EPS。
 *                         ④ 非有限判据：fTargetKg / fFlowKgh / fTolPct 逐拍双判（x<>x 判 NaN，
 *                            (x−x)<>0 判 Inf）。
 *                         ⑤ 无数组、无下标，故无越界风险；nBatchCnt 为 UDINT 单调累加不溢出。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_ScdPhase / E_DL_ScdCause 归属本文件（全库唯一属主，R264）。
 *                         信息级（0..9）永不置 bError；故障级（10 起）赋值处与 _bFaultLatch 三行
 *                         成对（R45），锁存回放至 bReset 沿（FB33-1）。
 * 分工声明 (Scope)      : 失重式连续给料控制（喂料闭环）归 FB_DL_ChemDosingGrav / FB_DL_BatchDosingControl；
 *                         批次报表与追溯归 DL_Process 报表件；本件只做**单批"喂料—稳定—称量"时序
 *                         与流量积算**，不做喂料闭环整定，也不做螺旋电机保护。
 * 归属     (Ownership)  : E_DL_ScdPhase / E_DL_ScdCause 归属本文件（全库唯一定义，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ dt 闸 + 除零闸 +
 *                         非有限双判 + 容差比较 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 ✓ 七态 ENUM +
 *                         CASE + ELSE ｜ R7 ✓ 全部 TON/R_TRIG 在 CASE 外 ｜ R8/R9 N/A（无 METHOD）
 *                         R10 ✓ 无构造式转换（TIME_TO_LREAL / 标准函数）｜ R14 ✓ 无 PROPERTY
 *                         R15 ✓ 无保留字撞名 ｜ R17 ✓ 无数组｜ R18 ✓ bReset 用 R_TRIG 判 .Q
 *                         R19 ✓ eFault 出口 = bReset 沿 + 撤使能 ｜ R20 ✓ 稳定/供料等待相带超时
 *                         R21 ✓ 锁存与迁相分离。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R79-B 首版
 * 验收向量 (Acceptance) :
 *   V1 fTargetKg=10.0、fFlowKgh=3600.0（=1 kg/s）、fTolPct=1.0、tSettle=T#2S、tTimeout=T#60S：
 *      bEnable=bStart=TRUE → ePreCheck → eFeeding（bMotorRun=TRUE）；fDosedKg 每 100ms 增 0.1kg，
 *      达 9.9kg（_fStopThr）→ eSettle；2s 后 eWeigh → fErrPct≈−1.0、nBatchCnt=1、
 *      bBatchDone 单拍 TRUE（次拍 FALSE）→ eDone。
 *   V2 续 V1，bStart 保持 TRUE → eDone → ePreCheck 自动进入第 2 批；bStart 落 FALSE → 回 eIdle，
 *      nBatchCnt 清零。
 *   V3 fTargetKg=0.0 → eState=eFault、eCause=eBadConfig、bError=TRUE、bMotorRun=FALSE；
 *      bReset 上升沿且 bEnable=FALSE → 回 eIdle、bError=FALSE。
 *   V4 fFlowKgh=0.0 持续 tTimeout=T#5S → eState=eFault、eCause=eNoFlow、bError=TRUE。
 *   V5 fFlowKgh=−5.0（负流量）→ 当拍 eState=eFault、eCause=eBadFlow、bMotorRun=FALSE。
 *   V6 bMotorRun=TRUE 而 bMotorFb 保持 FALSE 超 3s → eState=eFault、eCause=eMotorNoFb。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ScdPhase（螺旋给料批次相位；eFault 为安全相，仅 bReset 沿迁出）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ScdPhase :
(
    eIdle     := 0,    // 空闲：电机停，计数值清零 / Idle: motor stopped, counters cleared
    ePreCheck := 10,   // 预检相：单拍，置电机启动命令 / Pre-check: single scan, arm the motor command
    eFeeding  := 20,   // 喂料相：电机运行，按流量 × dt 积算 / Feeding: motor on, integrate flow times dt
    eSettle   := 30,   // 稳定相：停料后等空中料流落净 / Settle: motor off, waiting for the in-flight material
    eWeigh    := 40,   // 称量相：单拍结算误差与批次 / Weigh: single-scan settlement of error and batch count
    eDone     := 50,   // 完成相：本批完成，等下一批或退出 / Done: batch finished, waiting for the next one
    eFault    := 90    // 故障安全相：锁存成因，电机全停 / Fault safe phase: latched cause, motor stopped
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ScdCause（成因码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ScdCause :
(
    eNone       := 0,   // 信息级：无事件 / Info: no event
    eBatchDone  := 1,   // 信息级：一批完成且误差在容差内 / Info: batch completed within tolerance
    eOutOfTol   := 2,   // 信息级：一批完成但误差超容差（记录，不锁存）/ Info: batch completed out of tolerance, recorded only
    eSettling   := 3,   // 信息级：进入停料稳定相 / Info: entering the settle phase
    eBadConfig  := 10,  // 故障级：目标重量 / 容差 / 时间参数越域 / Fault: target, tolerance or time parameter out of domain
    eNonFinite  := 11,  // 故障级：入参非有限 / Fault: non-finite input
    eBadFlow    := 12,  // 故障级：流量为负 / Fault: negative flow
    eNoFlow     := 13,  // 故障级：流量为零持续超时（供料中断）/ Fault: zero flow persisted beyond the timeout
    eTimeout    := 14,  // 故障级：喂料总超时 / Fault: total feeding timeout
    eMotorNoFb  := 15,  // 故障级：电机命令与反馈不一致超 3s / Fault: motor command and feedback mismatch beyond 3 s
    eIllegalState := 16 // 故障级：非法状态枚举值 / Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_ScrewConveyorDoseSeq
VAR_INPUT
    bEnable    : BOOL := FALSE;        // 使能：FALSE 停电机并回 eIdle / Enable, FALSE stops the motor and returns to idle
    bStart     : BOOL := FALSE;        // 启动（电平）：FALSE 本批中止并回 eIdle / Start level, FALSE aborts the batch
    bReset     : BOOL := FALSE;        // 复位（上升沿，需同时 bEnable=FALSE）/ Reset rising edge, requires bEnable FALSE
    fTargetKg  : LREAL := 0.0;         // 批次目标重量，域 > 0 [kg] / Batch target weight, domain > 0
    fFlowKgh   : LREAL := 0.0;         // 当前给料流量（瞬时，来自流量计）[kg/h] / Instantaneous feed flow from the flow meter
    tSettle    : TIME := T#2S;         // 停料后稳定延时，域 0..1h [s] / Settle delay after the motor stops, domain 0..1h
    tTimeout   : TIME := T#60S;        // 喂料总超时，域 ≥ 100ms [s] / Total feeding timeout, domain >= 100ms
    fTolPct    : LREAL := 1.0;         // 允许误差，域 (0,100) [%] / Allowed error in percent, domain (0,100)
    bMotorFb   : BOOL := FALSE;        // 螺旋电机运行反馈（TRUE = 在转）[-] / Screw motor running feedback
END_VAR
VAR_OUTPUT
    bMotorRun  : BOOL;                 // 螺旋电机启动命令（电平）[-] / Screw motor run command, level
    fDosedKg   : LREAL := 0.0;         // 本批累计给料量 [kg] / Accumulated dose of this batch
    fErrPct    : LREAL := 0.0;         // 本批误差百分比（正 = 超量）[%] / Batch error percentage, positive means over-dose
    nBatchCnt  : UDINT := 0;           // 已完成批次数 [批] / Completed batch counter
    bBatchDone : BOOL;                 // 批次完成单拍脉冲（段 1 预置，统一出口映射）[-] / Single-scan batch-done pulse
    eState     : E_DL_ScdPhase;        // 状态出口（段尾单点映射）[-] / State outlet mapped at the tail
    eCause     : E_DL_ScdCause;        // 成因码出口（故障期锁存回放）[-] / Cause code outlet
    bError     : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    bValid     : BOOL;                 // 序列有效回执（喂料/稳定相且无锁存）[-] / Sequence validity receipt
END_VAR
VAR
    _eState      : E_DL_ScdPhase := E_DL_ScdPhase.eIdle;   // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _bFaultLatch : BOOL := FALSE;                          // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit
    _eCauseLatch : E_DL_ScdCause := E_DL_ScdCause.eNone;    // 锁存成因码（FB33-1 锁存回放）[-] / Latched cause code
    _eCauseTmp   : E_DL_ScdCause := E_DL_ScdCause.eNone;    // 本拍首因中间量（段 8 组态闸用）[-] / First cause of this scan
    _bCfgOk      : BOOL := TRUE;                           // 组态与入参闸通过标志 [-] / Configuration gate flag
    _bResetPulse : BOOL := FALSE;                          // bReset 上升沿快照（R18）[-] / bReset rising-edge snapshot
    _bBatchDoneInt : BOOL := FALSE;                        // 批次完成内部单拍位（统一出口映射）[-] / Internal single-scan batch-done bit
    _fDtSec      : LREAL := 0.0;                           // 积分步长：[s] / Integration step in seconds
    _bDtOk       : BOOL := FALSE;                          // 积分步长有效性（dt > EPS）[-] / Integration step validity
    _fStopThr    : LREAL := 0.0;                           // 停料阈值 = 目标 × (1 − 容差%) [kg] / Stop threshold of the feed
    _fStepKg     : LREAL := 0.0;                           // 本采样拍积算增量 [kg] / Dose increment of this sampling scan
    _fErrCalc    : LREAL := 0.0;                           // 误差百分比中间量 [%] / Error percentage intermediate
    _bMotMismatch : BOOL := FALSE;                         // 电机命令与反馈不一致标志 [-] / Motor command and feedback mismatch
    _bMotRunPrev  : BOOL := FALSE;                         // 上一拍电机命令快照（段 4 不一致判据用，一拍延迟）/ Motor command snapshot of the last scan
    rtReset      : R_TRIG;                                 // bReset 边沿实例（段 4 无条件调用，R18）/ bReset edge instance called unconditionally
    tonDt        : TON;                                    // 定周期采样节拍（段 4 无条件调用）/ Fixed-period sampling tick
    tonTotal     : TON;                                    // 喂料总超时（段 4 无条件调用）/ Total feeding timeout
    tonNoFlow    : TON;                                    // 零流量持续判（段 4 无条件调用）/ Zero-flow persistence timer
    tonSettle    : TON;                                    // 停料稳定延时（段 4 无条件调用）/ Settle delay timer
    tonMotFb     : TON;                                    // 电机反馈不一致持续判（段 4 无条件调用）/ Motor feedback mismatch timer
END_VAR
VAR CONSTANT
    DL_SCD_ZERO      : LREAL := 0.0;            // 浮点零基准 [-] / Float zero base
    DL_SCD_ONE       : LREAL := 1.0;            // 浮点一基准 [-] / Float one base
    DL_SCD_HUNDRED   : LREAL := 100.0;          // 百分比基数 [%] / Percent base
    DL_SCD_SEC_HOUR  : LREAL := 3600.0;         // 每小时秒数（kg/h → kg）[s/h] / Seconds per hour converting kg/h to kg
    DL_SCD_EPS       : LREAL := 1.0E-6;         // 浮点同值/正步长容差 [-] / Float equality and positive-step tolerance
    DL_SCD_DT        : TIME := T#100MS;         // 采样节拍（积分步长来源）[s] / Sampling tick, the integration step source
    DL_SCD_FB_WIN    : TIME := T#3S;            // 电机反馈不一致持续窗 [s] / Motor feedback mismatch window
    DL_SCD_T_MIN     : TIME := T#100MS;         // 超时参数下限 [s] / Lower bound of the timeout parameters
    DL_SCD_T_MAX     : TIME := T#1H;            // 稳定/超时参数上限 [s] / Upper bound of the settle and timeout parameters
    DL_SCD_BATCH_INC : UDINT := 1;              // 批次计数步长（UDINT 显式常量）[批] / Batch counter increment
END_VAR

(* —— 段 1：单拍位与动作出口预置（不清锁存 / 累加量，FB32-1） —— *)
bBatchDone     := FALSE;                               // 单拍批次沿每拍预清 / Single-scan batch edge preset FALSE every scan
bMotorRun      := FALSE;                               // 电机命令预置（安全侧：默认不动作）/ Motor command preset, safe side
_bBatchDoneInt := FALSE;                               // 内部单拍位预清 / Internal single-scan bit preset
_bCfgOk        := TRUE;                                // 组态闸标志复位 / Configuration flag reset
_eCauseTmp     := E_DL_ScdCause.eNone;                  // 当拍首因复位 / Scan cause reset

(* —— 段 2：步长与阈值换算（浮点域闸前置） —— *)
_fDtSec   := TIME_TO_LREAL(DL_SCD_DT);                 // 采样节拍换算为秒（标准转换，R10）/ Sampling tick converted to seconds
IF _fDtSec > DL_SCD_EPS THEN
    _bDtOk := TRUE;                                    // 步长为正：允许积分 / Positive step: integration allowed
ELSE
    _bDtOk := FALSE;                                   // 步长非正：拒绝积分（R4 防 dt <= 0）/ Non-positive step: integration refused
END_IF
_fStopThr := DL_SCD_ZERO;                              // 停料阈值预置零 / Stop threshold preset
_fErrCalc := DL_SCD_ZERO;                               // 误差中间量预置零 / Error intermediate preset

(* —— 段 3：组态与入参域闸（R272 全量枚举浮点与时间引脚） —— *)
IF (fTargetKg <> fTargetKg) OR ((fTargetKg - fTargetKg) <> DL_SCD_ZERO)
    OR (fFlowKgh <> fFlowKgh) OR ((fFlowKgh - fFlowKgh) <> DL_SCD_ZERO)
    OR (fTolPct <> fTolPct) OR ((fTolPct - fTolPct) <> DL_SCD_ZERO) THEN
    _bCfgOk    := FALSE;                               // 入参非有限 / Non-finite input
    _eCauseTmp := E_DL_ScdCause.eNonFinite;            // 故障级：非有限入参 / Fault: non-finite input
END_IF
IF _bCfgOk THEN
    IF fTargetKg <= DL_SCD_EPS THEN
        _bCfgOk    := FALSE;                           // 目标重量非正 / Target weight not positive
        _eCauseTmp := E_DL_ScdCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF (fTolPct <= DL_SCD_EPS) OR (fTolPct >= DL_SCD_HUNDRED) THEN
        _bCfgOk    := FALSE;                           // 容差越域（0,100）/ Tolerance out of domain
        _eCauseTmp := E_DL_ScdCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF (tTimeout < DL_SCD_T_MIN) OR (tTimeout > DL_SCD_T_MAX) THEN
        _bCfgOk    := FALSE;                           // 超时参数越域 / Timeout out of domain
        _eCauseTmp := E_DL_ScdCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF tSettle > DL_SCD_T_MAX THEN
        _bCfgOk    := FALSE;                           // 稳定延时越上限 / Settle delay above the upper bound
        _eCauseTmp := E_DL_ScdCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF fFlowKgh < DL_SCD_ZERO THEN
        _bCfgOk    := FALSE;                           // 流量为负（传感器或工艺异常）/ Negative flow from the meter or process
        _eCauseTmp := E_DL_ScdCause.eBadFlow;          // 故障级：负流量 / Fault: negative flow
    END_IF
END_IF
IF _bCfgOk THEN
    (* 停料阈值 = 目标 × (1 − 容差%/100)；除数 100 为常量，除零结构性不可达 *)
    _fStopThr := fTargetKg * (DL_SCD_ONE - (fTolPct / DL_SCD_HUNDRED));
    IF _fStopThr <= DL_SCD_ZERO THEN
        _fStopThr := DL_SCD_ZERO;                      // 阈值负值兜底归零 / Clamp a negative threshold to zero
    END_IF
END_IF

(* —— 段 4：边沿与定时器（CASE 外无条件调用，R7；IN 均含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                                // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
_bResetPulse := rtReset.Q;                             // 边沿快照 / Edge snapshot
tonDt(IN := (_eState = E_DL_ScdPhase.eFeeding) AND (NOT tonDt.Q) AND (NOT _bFaultLatch),
      PT := DL_SCD_DT);                                // 喂料相定周期积分节拍 / Fixed-period integration tick while feeding
tonTotal(IN := (_eState = E_DL_ScdPhase.eFeeding) AND (NOT tonTotal.Q) AND (NOT _bFaultLatch),
         PT := tTimeout);                              // 喂料总超时 / Total feeding timeout
tonNoFlow(IN := (_eState = E_DL_ScdPhase.eFeeding) AND (ABS(fFlowKgh) < DL_SCD_EPS)
               AND (NOT tonNoFlow.Q) AND (NOT _bFaultLatch),
          PT := tTimeout);                             // 零流量持续判（供料中断）/ Zero-flow persistence check
tonSettle(IN := (_eState = E_DL_ScdPhase.eSettle) AND (NOT tonSettle.Q) AND (NOT _bFaultLatch),
          PT := tSettle);                              // 停料稳定延时 / Settle delay
_bMotMismatch := (_bMotRunPrev AND (NOT bMotorFb)) OR ((NOT _bMotRunPrev) AND bMotorFb);   // 命令与反馈不一致（用上一拍命令快照）/ Command and feedback mismatch using the last-scan command
tonMotFb(IN := _bMotMismatch AND (_eState = E_DL_ScdPhase.eFeeding)
              AND (NOT tonMotFb.Q) AND (NOT _bFaultLatch),
         PT := DL_SCD_FB_WIN);                         // 仅喂料相监视反馈一致性 / Feedback consistency monitored while feeding only

(* —— 段 5：误差百分比刷新（除零闸：目标重量非正时置零哨兵，R4） —— *)
IF fTargetKg > DL_SCD_EPS THEN
    _fErrCalc := ((fDosedKg - fTargetKg) / fTargetKg) * DL_SCD_HUNDRED;   // 误差百分比 / Error percentage
    fErrPct   := _fErrCalc;                                               // 误差出口 / Error outlet
ELSE
    fErrPct := DL_SCD_ZERO;                                               // 目标非正：置零哨兵（除零不可达）/ Zero sentinel, division unreachable
END_IF

(* —— 段 6：状态机主体（唯一相位写入点；故障只置锁存，迁相由段 8 统一执行） —— *)
CASE _eState OF
    E_DL_ScdPhase.eIdle :
        bMotorRun := FALSE;                            // 空闲：电机不动作 / Idle: motor idle
        fDosedKg  := DL_SCD_ZERO;                      // 累计量清零 / Dose counter cleared
        fErrPct   := DL_SCD_ZERO;                      // 误差清零 / Error cleared
        nBatchCnt := 0;                                // 批次计数清零 / Batch counter cleared
        IF bEnable AND bStart AND _bCfgOk AND (fTargetKg > DL_SCD_EPS) AND (NOT _bFaultLatch) THEN
            eCause  := E_DL_ScdCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_ScdPhase.ePreCheck;        // 迁移①：进入预检相 / Move to pre-check
        END_IF

    E_DL_ScdPhase.ePreCheck :
        IF (NOT bEnable) OR (NOT bStart) THEN
            bMotorRun := FALSE;                        // 失能：电机停 / Disabled: motor stopped
            eCause    := E_DL_ScdCause.eNone;          // 信息级：无事件 / Info: no event
            _eState   := E_DL_ScdPhase.eIdle;          // 回空闲相 / Back to idle
        ELSE
            fDosedKg  := DL_SCD_ZERO;                  // 每批起点：累计量清零 / Batch start: dose counter cleared
            fErrPct   := DL_SCD_ZERO;                  // 每批起点：误差清零 / Batch start: error cleared
            bMotorRun := TRUE;                         // 迁移②：预检通过，启动螺旋 / Pre-check passed: start the screw
            eCause    := E_DL_ScdCause.eNone;          // 信息级：无事件 / Info: no event
            _eState   := E_DL_ScdPhase.eFeeding;       // 进入喂料相 / Move to feeding
        END_IF

    E_DL_ScdPhase.eFeeding :
        bMotorRun := TRUE;                             // 喂料相电机保持运行 / Motor stays on while feeding
        IF (NOT bEnable) OR (NOT bStart) THEN
            bMotorRun := FALSE;                        // 失能：电机停 / Disabled: motor stopped
            eCause    := E_DL_ScdCause.eNone;          // 信息级：无事件 / Info: no event
            _eState   := E_DL_ScdPhase.eIdle;          // 回空闲相 / Back to idle
        ELSE
            (* 定周期积算：只有节拍拍且步长为正才积分（R4） *)
            IF tonDt.Q AND _bDtOk THEN
                _fStepKg  := (fFlowKgh * _fDtSec) / DL_SCD_SEC_HOUR;   // 增量 = 流量 × dt / 3600 [kg]
                fDosedKg  := fDosedKg + _fStepKg;                      // 累计给料量 / Accumulate the dose
            END_IF
            IF fFlowKgh < DL_SCD_ZERO THEN
                IF NOT _bFaultLatch THEN
                    _eCauseLatch := E_DL_ScdCause.eBadFlow;            // 故障级：负流量 / Fault: negative flow
                    _bFaultLatch := TRUE;                              // 置故障锁存（迁相由段 8，R21）/ Latch the fault
                END_IF
            ELSIF tonNoFlow.Q THEN
                IF NOT _bFaultLatch THEN
                    _eCauseLatch := E_DL_ScdCause.eNoFlow;             // 故障级：供料中断 / Fault: feed interrupted
                    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
                END_IF
            ELSIF tonTotal.Q THEN
                IF NOT _bFaultLatch THEN
                    _eCauseLatch := E_DL_ScdCause.eTimeout;            // 故障级：喂料总超时 / Fault: total feeding timeout
                    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
                END_IF
            ELSIF tonMotFb.Q THEN
                IF NOT _bFaultLatch THEN
                    _eCauseLatch := E_DL_ScdCause.eMotorNoFb;          // 故障级：电机反馈不一致 / Fault: motor feedback mismatch
                    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
                END_IF
            ELSIF (fDosedKg >= _fStopThr) OR (fDosedKg >= fTargetKg) THEN
                bMotorRun := FALSE;                                    // 迁移③：达提前量，停料 / Reached the threshold: stop the feed
                eCause    := E_DL_ScdCause.eSettling;                  // 信息级：进入稳定相 / Info: entering settle
                _eState   := E_DL_ScdPhase.eSettle;                    // 进入稳定相 / Move to settle
            END_IF
        END_IF

    E_DL_ScdPhase.eSettle :
        bMotorRun := FALSE;                            // 稳定相电机保持停止 / Motor stays off while settling
        IF (NOT bEnable) OR (NOT bStart) THEN
            eCause  := E_DL_ScdCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_ScdPhase.eIdle;            // 回空闲相 / Back to idle
        ELSIF tonSettle.Q THEN
            eCause  := E_DL_ScdCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_ScdPhase.eWeigh;           // 迁移④：稳定到时进入称量相 / Settle elapsed: move to weigh
        END_IF

    E_DL_ScdPhase.eWeigh :
        bMotorRun      := FALSE;                       // 称量相电机停止 / Motor off during settlement
        nBatchCnt      := nBatchCnt + DL_SCD_BATCH_INC; // 迁移⑤：批次计数 +1 / Increment the batch counter
        _bBatchDoneInt := TRUE;                        // 批次完成内部单拍位置位 / Internal single-scan batch bit
        IF ABS(fErrPct) > fTolPct THEN
            eCause := E_DL_ScdCause.eOutOfTol;         // 信息级：误差超容差（记录，不锁存）/ Info: out of tolerance, recorded only
        ELSE
            eCause := E_DL_ScdCause.eBatchDone;        // 信息级：批次合格完成 / Info: batch completed within tolerance
        END_IF
        _eState := E_DL_ScdPhase.eDone;                // 进入完成相 / Move to done

    E_DL_ScdPhase.eDone :
        bMotorRun := FALSE;                            // 完成相电机停止 / Motor off in the done phase
        IF NOT bStart THEN
            eCause  := E_DL_ScdCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_ScdPhase.eIdle;            // 迁移⑦：前置消失回空闲 / Start gone: back to idle
        ELSIF NOT bEnable THEN
            eCause  := E_DL_ScdCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_ScdPhase.eIdle;            // 失能回空闲 / Disabled: back to idle
        ELSIF bStart AND bEnable THEN
            eCause  := E_DL_ScdCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_ScdPhase.ePreCheck;        // 迁移⑥：连续批次 / Continuous batches
        END_IF

    E_DL_ScdPhase.eFault :
        bMotorRun := FALSE;                            // 故障相：电机全停（安全侧）/ Fault phase: motor stopped
        IF _bResetPulse AND (NOT bEnable) THEN
            _bFaultLatch := FALSE;                     // 迁移⑨：清故障锁存 / Clear the fault latch
            _eCauseLatch := E_DL_ScdCause.eNone;       // 清锁存成因 / Clear the latched cause
            eCause       := E_DL_ScdCause.eNone;       // 出口同步归零 / Outlet follows
            fDosedKg     := DL_SCD_ZERO;               // 累计量清零 / Dose counter cleared
            fErrPct      := DL_SCD_ZERO;               // 误差清零 / Error cleared
            _eState      := E_DL_ScdPhase.eIdle;       // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑩：非法枚举兜底（R6） *)
    IF NOT _bFaultLatch THEN
        _eCauseLatch := E_DL_ScdCause.eIllegalState;   // 故障级：非法状态 / Fault: illegal state
        _bFaultLatch := TRUE;                          // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 7：组态闸失败处理（锁存与迁相分离，R21） —— *)
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _eCauseLatch := _eCauseTmp;                        // 锁存首因（组态闸）/ Latch the configuration cause
    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
END_IF

(* —— 段 8：段尾故障迁移闸 + 故障相动作全撤（FB50-1④） —— *)
IF _bFaultLatch AND (_eState <> E_DL_ScdPhase.eFault) THEN
    _eState := E_DL_ScdPhase.eFault;                   // 锁存即迁相 / Latch forces the fault phase
END_IF
IF _eState = E_DL_ScdPhase.eFault THEN
    bMotorRun := FALSE;                                // 故障相动作全撤（含同拍迁入）/ Motor withdrawn in fault
END_IF

(* —— 段 9：统一出口（状态映射 + 单拍位映射 + 锁存回放） —— *)
eState     := _eState;                                 // 相位映射 / Phase mapping
bBatchDone := _bBatchDoneInt;                          // 单拍批次沿统一映射（FB33-1 两段式）/ Single-scan batch edge mapped here
bError     := _bFaultLatch;                            // 故障标志取锁存位 / Fault flag from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                            // 故障期回放锁存码（FB33-1）/ Replay the latched code
END_IF
bValid := ((_eState = E_DL_ScdPhase.eFeeding) OR (_eState = E_DL_ScdPhase.eSettle))
          AND (NOT _bFaultLatch);                      // 喂料/稳定相且无锁存时有效 / Valid while feeding or settling without a latch
_bMotRunPrev := bMotorRun;                             // 电机命令快照更新（唯一写入点，段 4 用）/ Motor command snapshot, single write point
END_FUNCTION_BLOCK
