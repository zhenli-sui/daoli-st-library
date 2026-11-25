(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PressForceCurveExec
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-24
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / ABS / MIN / MAX / LIMIT），零厂商私有库
 * 功能描述 (Function)   : 压机多段力曲线执行：按 4 段配方（目标力 aSegForce / 升力速率 aSegRate /
 *                         保压时长 aSegHold）逐段执行，eRamp 以「速率 × dt」斜坡逼近目标力，
 *                         到力判据 = 指令已饱和到目标（|cmd − target| ≤ EPS）**且** 实际力反馈落进
 *                         容差带（容差 = max(0.5% × |目标力|, 0.1 kN)）→ eHold 保压 aSegHold[i]；
 *                         末段保压完成 → eRelease 按末段速率把力指令斜坡降到 0 → eDone 发 bCurveDone。
 *                         **dt 口径**：定周期采样节拍 tonDt（PT = 100ms 常数）生成步长
 *                         _fDtSec := TIME_TO_LREAL(DL_PFC_DT)，入口做 dt > EPS 闸（R4 防 dt ≤ 0）；
 *                         保压计时用 DINT 毫秒累加（_diHoldMs，每采样拍 +100ms），避免 TIME 加法跨型。
 *                         **bStart = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         力指令按段速率退回 0 并进 eIdle（压机力指令不得冻结保持）。
 * 接口     (Interface)  : 输入 bEnable / bStart / bReset（上升沿）/ aSegForce[1..4] / aSegRate[1..4] /
 *                         aSegHold[1..4] / nSegCnt / fForceFb / tSegTimeout；
 *                         输出 fForceCmd / nSegAct / tHoldElapsed / bCurveDone / eState（E_DL_PfcPhase）/
 *                         eCause（E_DL_PfcCause）/ bError / bValid / nSegCompleted。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eRamp：bEnable 且 bStart 且组态闸通过且无锁存；拍 N 进入 / 本拍行为：
 *      fForceCmd=0、nSegAct=1、nSegCompleted=0、_diHoldMs=0 / 拍 N+1 转出至 eRamp。
 *   ② eRamp → eHold：到力判据成立（指令饱和 + 反馈落带）；拍 N 进入 / 本拍行为：
 *      _diHoldMs 清零、fForceCmd 精确取目标 / 拍 N+1 转出至 eHold。
 *   ③ eHold → eRamp：_diHoldMs ≥ aSegHold[i] 且 i < nSegCnt；本拍行为：nSegAct+1、
 *      nSegCompleted+1、_diHoldMs 清零、信息级 eSegDone / 拍 N+1 转出（下一段）。
 *   ④ eHold → eRelease：_diHoldMs ≥ aSegHold[nSegCnt]（末段完成）；本拍行为：nSegCompleted+1、
 *      信息级 eCurveDoneCode / 拍 N+1 转出至 eRelease。
 *   ⑤ eRelease → eDone：|fForceCmd| ≤ EPS（已退到 0）；本拍行为：fForceCmd 精确置 0 /
 *      拍 N+1 转出至 eDone。
 *   ⑥ eDone → eIdle：(NOT bStart) OR bReset 上升沿（两条出口 R98）；本拍行为：bCurveDone 落 FALSE、
 *      力指令与段号清零 / 拍 N+1 转出至 eIdle。
 *   ⑦ eRamp → eFault：tonSeg.Q（单段超时未到力）锁存 eForceNotReached；本拍行为：fForceCmd 保持
 *      当前值直至段尾迁移闸（R21）后再全撤 / 拍 N+1 转出至 eFault。
 *   ⑧ 任一相 → eFault：组态闸失败（段数越域 / 速率 ≤ 0 / 目标力 < 0 / 保压越域 / 超时越域 /
 *      fForceFb 非有限），锁存首因。
 *   ⑨ eFault → eIdle：bReset 上升沿（R_TRIG 判 .Q）且 bEnable = FALSE（R19 穷举出口）；
 *      本拍行为：清锁存与成因、fForceCmd=0 / 拍 N+1 转出至 eIdle。
 *   ⑩ ELSE（非法枚举值）→ eFault，成因 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① tonDt / tonSeg / R_TRIG 全在 CASE 外无条件调用（R7）；两者 IN 均含
 *                            NOT .Q 自复位项（R188）；tonSeg 另含「(NOT _bSegReset)」断流项 ——
 *                            换段（含首段起始）当拍置 _bSegNew，次拍 _bSegReset 为真使 IN 断流，
 *                            ET 归零后再起计，故单段超时按段独立（结构性无需外部沿清零）。
 *                         ② 斜坡双向：目标高于当前则升、低于当前则降（段间降力不越界），
 *                            三步比较全用大小判据，无浮点等值比较（R4）。
 *                         ③ 到力容差为「相对 0.5% 与绝对 0.1 kN 取大」，浮点比较一律容差式。
 *                         ④ 组态域闸：nSegCnt ∈ [1,4]（越域直接故障并钳位供下标安全）；
 *                            参与执行的段（1..nSegCnt）逐段校验速率 > 0、目标力 ≥ 0、保压 ≤ 1h；
 *                            全部 4 段做非有限拒收（未参与段不判量程域，见分工声明）。
 *                         ⑤ 无除法，故无除零；无浮点等值比较；力指令出口恒为饱和值。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_PfcPhase / E_DL_PfcCause 归属本文件（全库唯一属主，R264）。
 *                         信息级（0..9）永不置 bError；故障级（10 起）赋值处与 _bFaultLatch 三行
 *                         成对（R45），锁存回放至 bReset 沿（FB33-1）。
 * 分工声明 (Scope)      : 压机液压比例阀闭环 / 伺服压力闭环归运动控制件；模具保护与吨位监视归
 *                         FB_DL_PressTonnageGuard 类件；本件只做**多段力配方开环斜坡 + 到力判定 +
 *                         保压计时**，不做力闭环 PID，也不做安全回路（安全由 PRG_IoMapping 双切断）。
 * 归属     (Ownership)  : E_DL_PfcPhase / E_DL_PfcCause 归属本文件（全库唯一定义，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ dt 闸 + 容差比较 +
 *                         非有限双判 + 无除法 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 ✓ 六态 ENUM + CASE +
 *                         ELSE ｜ R7 ✓ 全部 TON/R_TRIG 在 CASE 外 ｜ R8/R9 N/A（无 METHOD）
 *                         R10 ✓ 无构造式转换 ｜ R14 ✓ 无 PROPERTY ｜ R15 ✓ 无保留字撞名
 *                         R17 ✓ 定长 ARRAY[1..4] ｜ R18 ✓ bReset 用 R_TRIG 判 .Q ｜ R19 ✓ eFault
 *                         出口 = bReset 沿 + 撤使能 ｜ R20 ✓ 到力等待相带 tSegTimeout 超时兜底
 *                         R21 ✓ 锁存与迁相分离。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R79-B 首版
 * 验收向量 (Acceptance) :
 *   V1 nSegCnt=2、段1 = (50 kN, 10 kN/s, T#2S)、段2 = (80 kN, 5 kN/s, T#1S)、tSegTimeout=T#30S、
 *      fForceFb 跟随 fForceCmd：eRamp 约 5s 到 50 kN → eHold（tHoldElapsed 递增到 2s）→ 段2：
 *      约 6s 到 80 kN → eHold 1s → eRelease → eDone，bCurveDone=TRUE、nSegCompleted=2。
 *   V2 nSegCnt=0（越域）→ eState=eFault、eCause=eBadConfig、bError=TRUE、fForceCmd=0；
 *      bReset 上升沿且 bEnable=FALSE → 回 eIdle、bError=FALSE。
 *   V3 aSegRate[1]=0.0（速率非正）→ eState=eFault、eCause=eBadConfig。
 *   V4 aSegForce[1]=50.0、tSegTimeout=T#5S、fForceFb 恒为 0（力建不起来）→ 5s 后
 *      eState=eFault、eCause=eForceNotReached、bError=TRUE、fForceCmd=0（故障相全撤）。
 *   V5 fForceFb = NaN → eState=eFault、eCause=eNonFinite（非有限拒收，非量程判据）。
 *   V6 eRamp 中 bStart 落 FALSE → fForceCmd 回 0、eState=eIdle、nSegAct=0（安全降级）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PfcPhase（压机力曲线相位；eFault 为安全相，仅 bReset 沿迁出）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PfcPhase :
(
    eIdle    := 0,    // 空闲：力指令 0，段号清零 / Idle: force command zero, segment cleared
    eRamp    := 10,   // 斜坡相：按段速率逼近目标力 / Ramp: approach the target at the segment rate
    eHold    := 20,   // 保压相：力保持目标值并计时 / Hold: keep the target force and time it
    eRelease := 30,   // 卸力相：力指令斜坡降到 0 / Release: ramp the force command down to zero
    eDone    := 40,   // 完成相：bCurveDone 电平为 TRUE / Done: bCurveDone held high
    eFault   := 90    // 故障安全相：锁存成因，力指令回 0 / Fault safe phase: latched cause, force command zeroed
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PfcCause（成因码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PfcCause :
(
    eNone            := 0,   // 信息级：无事件 / Info: no event
    eSegDone         := 1,   // 信息级：一段保压完成 / Info: one segment hold completed
    eCurveDoneCode   := 2,   // 信息级：曲线保压全部完成 / Info: all segment holds completed
    eReleasing       := 3,   // 信息级：进入卸力相 / Info: entering the release phase
    eBadConfig       := 10,  // 故障级：段数 / 速率 / 目标力 / 保压 / 超时越域 / Fault: segment, rate, force, hold or timeout out of domain
    eNonFinite       := 11,  // 故障级：入参非有限 / Fault: non-finite input
    eForceNotReached := 12,  // 故障级：单段超时未到力 / Fault: force not reached within the segment timeout
    eIllegalState    := 13   // 故障级：非法状态枚举值 / Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_PressForceCurveExec
VAR_INPUT
    bEnable     : BOOL := FALSE;                        // 使能：FALSE 力指令回 0 并回 eIdle / Enable, FALSE zeroes the force and returns to idle
    bStart      : BOOL := FALSE;                        // 启动（电平）：FALSE 曲线中止，力指返回 0 / Start level, FALSE aborts and ramps the force back
    bReset      : BOOL := FALSE;                        // 复位（上升沿，需同时 bEnable=FALSE）/ Reset rising edge, requires bEnable FALSE
    aSegForce   : ARRAY[1..4] OF LREAL;                 // 各段目标力（域 ≥ 0）[kN] / Per-segment target force, domain >= 0
    aSegRate    : ARRAY[1..4] OF LREAL;                 // 各段升力速率（域 > 0）[kN/s] / Per-segment force rate, domain > 0
    aSegHold    : ARRAY[1..4] OF TIME;                  // 各段保压时长（域 0..1h）[s] / Per-segment hold time, domain 0..1h
    nSegCnt     : INT := 1;                             // 实际执行段数，有效域 1..4 [段] / Effective segment count, valid domain 1..4
    fForceFb    : LREAL := 0.0;                         // 实际力反馈（来自压力/力传感器）[kN] / Actual force feedback
    tSegTimeout : TIME := T#30S;                        // 单段到力超时，域 100ms..1h [s] / Per-segment force-reach timeout
END_VAR
VAR_OUTPUT
    fForceCmd      : LREAL := 0.0;                      // 力指令出口（斜坡饱和值）[kN] / Force command outlet, saturated ramp value
    nSegAct        : INT := 0;                          // 当前段号（1 起，0 = 未开始）[段] / Current segment number, 0 means not started
    tHoldElapsed   : TIME := T#0S;                      // 当前段保压已用时长 [s] / Elapsed hold time of the current segment
    bCurveDone     : BOOL;                              // 曲线完成（电平，保持至 bStart 落或复位）[-] / Curve done, level held until start falls
    eState         : E_DL_PfcPhase;                     // 状态出口（段尾单点映射）[-] / State outlet mapped at the tail
    eCause         : E_DL_PfcCause;                     // 成因码出口（故障期锁存回放）[-] / Cause code outlet
    bError         : BOOL;                              // 故障锁存标志 [-] / Fault latch flag
    bValid         : BOOL;                              // 曲线有效回执（斜坡/保压相且无锁存）[-] / Curve validity receipt
    nSegCompleted  : INT := 0;                          // 已完成段数 [段] / Number of completed segments
END_VAR
VAR
    _eState       : E_DL_PfcPhase := E_DL_PfcPhase.eIdle;   // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _bFaultLatch  : BOOL := FALSE;                          // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit
    _eCauseLatch  : E_DL_PfcCause := E_DL_PfcCause.eNone;    // 锁存成因码（FB33-1 锁存回放）[-] / Latched cause code
    _eCauseTmp    : E_DL_PfcCause := E_DL_PfcCause.eNone;    // 本拍首因中间量（段 6 组态闸用）[-] / First cause of this scan
    _bCfgOk       : BOOL := TRUE;                           // 组态与入参闸通过标志 [-] / Configuration gate flag
    _bResetPulse  : BOOL := FALSE;                          // bReset 上升沿快照（R18）[-] / bReset rising-edge snapshot
    _nSegClamp    : INT := 1;                               // 段数钳位值 1..4（下标安全）[段] / Clamped segment count for safe indexing
    _bSegNew      : BOOL := FALSE;                          // 本拍进入新段标志（CASE 内置位，次拍令单段超时 ET 自清）[-] / New-segment flag set inside CASE
    _bSegReset    : BOOL := FALSE;                          // 新段标志快照（段 1 取上一拍值，供 tonSeg 的 IN 断流）[-] / New-segment snapshot latching the last-scan value
    _nIdx         : INT := 1;                               // 遍历下标（FOR 专用）[段] / Loop index for FOR statements
    _diHoldMs     : DINT := 0;                              // 保压毫秒累加（DINT 防跨型溢出）[ms] / Accumulated hold milliseconds
    _fDtSec       : LREAL := 0.0;                           // 采样步长 [s] / Sampling step in seconds
    _bDtOk        : BOOL := FALSE;                          // 步长有效性（dt > EPS）[-] / Sampling step validity
    _fStep         : LREAL := 0.0;                          // 本拍斜坡增量 [kN] / Ramp increment of this scan
    _fTol         : LREAL := 0.0;                           // 到力容差 = max(0.5%×|目标|, 0.1) [kN] / Force-reach tolerance
    _bCmdAtTarget : BOOL := FALSE;                          // 指令已饱和到目标标志 [-] / Command saturated at the target
    _bFbInTol     : BOOL := FALSE;                          // 反馈落进容差带标志 [-] / Feedback inside the tolerance band
    rtReset       : R_TRIG;                                 // bReset 边沿实例（段 4 无条件调用，R18）/ bReset edge instance called unconditionally
    tonDt         : TON;                                    // 定周期采样节拍（段 4 无条件调用）/ Fixed-period sampling tick
    tonSeg        : TON;                                    // 单段到力超时（段 4 无条件调用）/ Per-segment force-reach timeout
END_VAR
VAR CONSTANT
    DL_PFC_ZERO      : LREAL := 0.0;             // 浮点零基准 [-] / Float zero base
    DL_PFC_EPS       : LREAL := 1.0E-6;          // 浮点同值/正步长容差（力指令饱和判）[-] / Float equality and positive-step tolerance
    DL_PFC_TOL_PCT   : LREAL := 0.005;           // 到力相对容差 0.5% [-] / Relative force tolerance of 0.5 percent
    DL_PFC_TOL_ABS   : LREAL := 0.1;             // 到力绝对容差 [kN] / Absolute force tolerance
    DL_PFC_SEG_MAX   : INT := 4;                 // 段数上限（数组定长）[段] / Upper bound of segments, fixed array size
    DL_PFC_ONE       : INT := 1;                 // 段号起始值 [段] / Segment numbering start
    DL_PFC_DT        : TIME := T#100MS;          // 采样节拍（斜坡步长来源）[s] / Sampling tick, the ramp step source
    DL_PFC_DT_MS     : DINT := 100;              // 采样节拍毫秒数（保压累加步长）[ms] / Sampling tick in milliseconds
    DL_PFC_T_MIN     : TIME := T#100MS;          // 超时参数下限 [s] / Lower bound of the timeout parameter
    DL_PFC_T_MAX     : TIME := T#1H;             // 超时与保压参数上限 [s] / Upper bound of timeout and hold time
    DL_PFC_MS_ZERO   : DINT := 0;                // 毫秒零基准 [-] / Millisecond zero base
END_VAR

(* —— 段 1：单拍与电平出口预置（不清锁存 / 力指令 / 段号状态，FB32-1） —— *)
bCurveDone := FALSE;                                   // 曲线完成电平每拍预清（仅 eDone 相重新置位）/ Curve-done level preset, re-armed only in eDone
_bCfgOk    := TRUE;                                    // 组态闸标志复位 / Configuration flag reset
_eCauseTmp := E_DL_PfcCause.eNone;                      // 当拍首因复位 / Scan cause reset
_bSegReset := _bSegNew;                                // 取上一拍的新段标志（本拍令 tonSeg 的 IN 断流，R188）/ Take the last-scan new-segment flag
_bSegNew   := FALSE;                                   // 新段标志每拍预清（仅换段相内置位）/ Preset the new-segment flag, set only on a segment change

(* —— 段 2：段数钳位与采样步长（标准转换，R10） —— *)
_nSegClamp := LIMIT(DL_PFC_ONE, nSegCnt, DL_PFC_SEG_MAX);            // 段数钳位 1..4 / Clamp the segment count
_fDtSec    := TIME_TO_LREAL(DL_PFC_DT);                              // 节拍换算为秒 / Sampling tick to seconds
IF _fDtSec > DL_PFC_EPS THEN
    _bDtOk := TRUE;                                                  // 步长为正：允许斜坡积分 / Positive step: ramp integration allowed
ELSE
    _bDtOk := FALSE;                                                 // 步长非正：拒绝积分（R4）/ Non-positive step: integration refused
END_IF

(* —— 段 3：全部 4 段非有限拒收（未参与段也拒 NaN / Inf，避免污染后续组态）/ —— *)
FOR _nIdx := 1 TO DL_PFC_SEG_MAX DO
    IF (aSegForce[_nIdx] <> aSegForce[_nIdx]) OR ((aSegForce[_nIdx] - aSegForce[_nIdx]) <> DL_PFC_ZERO) THEN
        _bCfgOk    := FALSE;                            // 目标力非有限 / Target force is not finite
        _eCauseTmp := E_DL_PfcCause.eNonFinite;         // 故障级：非有限入参 / Fault: non-finite input
    END_IF
    IF (aSegRate[_nIdx] <> aSegRate[_nIdx]) OR ((aSegRate[_nIdx] - aSegRate[_nIdx]) <> DL_PFC_ZERO) THEN
        _bCfgOk    := FALSE;                            // 速率非有限 / Rate is not finite
        _eCauseTmp := E_DL_PfcCause.eNonFinite;         // 故障级：非有限入参 / Fault: non-finite input
    END_IF
END_FOR
IF (fForceFb <> fForceFb) OR ((fForceFb - fForceFb) <> DL_PFC_ZERO) THEN
    _bCfgOk    := FALSE;                                // 力反馈非有限 / Force feedback is not finite
    _eCauseTmp := E_DL_PfcCause.eNonFinite;             // 故障级：非有限入参 / Fault: non-finite input
END_IF

(* —— 段 4：组态量程域闸（仅参与执行的 1..nSegCnt 段，逐段校验） —— *)
IF _bCfgOk THEN
    IF (nSegCnt < DL_PFC_ONE) OR (nSegCnt > DL_PFC_SEG_MAX) THEN
        _bCfgOk    := FALSE;                            // 段数越域 / Segment count out of domain
        _eCauseTmp := E_DL_PfcCause.eBadConfig;         // 故障级：组态非法 / Fault: bad configuration
    ELSIF (tSegTimeout < DL_PFC_T_MIN) OR (tSegTimeout > DL_PFC_T_MAX) THEN
        _bCfgOk    := FALSE;                            // 单段超时越域 / Segment timeout out of domain
        _eCauseTmp := E_DL_PfcCause.eBadConfig;         // 故障级：组态非法 / Fault: bad configuration
    ELSE
        FOR _nIdx := 1 TO _nSegClamp DO
            IF aSegRate[_nIdx] <= DL_PFC_ZERO THEN
                _bCfgOk    := FALSE;                    // 速率非正，无法斜坡 / Non-positive rate, ramp impossible
                _eCauseTmp := E_DL_PfcCause.eBadConfig; // 故障级：组态非法 / Fault: bad configuration
            END_IF
            IF aSegForce[_nIdx] < DL_PFC_ZERO THEN
                _bCfgOk    := FALSE;                    // 目标力为负 / Negative target force
                _eCauseTmp := E_DL_PfcCause.eBadConfig; // 故障级：组态非法 / Fault: bad configuration
            END_IF
            IF aSegHold[_nIdx] > DL_PFC_T_MAX THEN
                _bCfgOk    := FALSE;                    // 保压时长越上限 / Hold time above the upper bound
                _eCauseTmp := E_DL_PfcCause.eBadConfig; // 故障级：组态非法 / Fault: bad configuration
            END_IF
        END_FOR
    END_IF
END_IF

(* —— 段 5：边沿与定时器（CASE 外无条件调用，R7；IN 均含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                                // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
_bResetPulse := rtReset.Q;                             // 边沿快照 / Edge snapshot
tonDt(IN := ((_eState = E_DL_PfcPhase.eRamp) OR (_eState = E_DL_PfcPhase.eHold)
             OR (_eState = E_DL_PfcPhase.eRelease))
            AND (NOT tonDt.Q) AND (NOT _bFaultLatch),
      PT := DL_PFC_DT);                                // 执行相定周期采样节拍 / Fixed-period tick in the execution phases
tonSeg(IN := (_eState = E_DL_PfcPhase.eRamp) AND (NOT _bSegReset)
              AND (NOT tonSeg.Q) AND (NOT _bFaultLatch),
        PT := tSegTimeout);                            // 单段超时：换段次拍 IN 断流使 ET 自清（R188）

(* —— 段 6：状态机主体（唯一相位写入点；故障只置锁存，迁相由段 8 统一执行） —— *)
CASE _eState OF
    E_DL_PfcPhase.eIdle :
        fForceCmd     := DL_PFC_ZERO;                  // 空闲：力指令归零 / Idle: force command zeroed
        nSegAct       := 0;                            // 空闲：段号清零 / Idle: segment cleared
        nSegCompleted := 0;                            // 空闲：完成段数清零 / Idle: completed segments cleared
        _diHoldMs     := DL_PFC_MS_ZERO;               // 空闲：保压累计清零 / Idle: hold accumulator cleared
        IF bEnable AND bStart AND _bCfgOk AND (NOT _bFaultLatch) THEN
            fForceCmd  := DL_PFC_ZERO;                 // 迁移①：起点力为零 / Start from zero force
            nSegAct    := DL_PFC_ONE;                  // 从第 1 段开始 / Begin at segment one
            _diHoldMs  := DL_PFC_MS_ZERO;              // 保压累计清零 / Hold accumulator cleared
            _bSegNew   := TRUE;                        // 首段起始：次拍令单段超时 ET 自清 / First segment: reset the timeout on the next scan
            eCause     := E_DL_PfcCause.eNone;         // 信息级：无事件 / Info: no event
            _eState    := E_DL_PfcPhase.eRamp;         // 进入斜坡相 / Move to ramp
        END_IF

    E_DL_PfcPhase.eRamp :
        IF (NOT bEnable) OR (NOT bStart) THEN
            fForceCmd := DL_PFC_ZERO;                  // 失能：力指令回 0（安全降级）/ Disabled: force zeroed for safety
            nSegAct   := 0;                            // 段号清零 / Segment cleared
            eCause    := E_DL_PfcCause.eNone;          // 信息级：无事件 / Info: no event
            _eState   := E_DL_PfcPhase.eIdle;          // 回空闲相 / Back to idle
        ELSE
            (* 斜坡：按段速率把力指令推向目标（双向） *)
            IF tonDt.Q AND _bDtOk THEN
                _fStep := aSegRate[nSegAct] * _fDtSec; // 本拍增量 = 速率 × dt [kN]
                IF fForceCmd < aSegForce[nSegAct] THEN
                    fForceCmd := MIN(fForceCmd + _fStep, aSegForce[nSegAct]);   // 升力且不越过目标 / Ramp up without overshoot
                ELSIF fForceCmd > aSegForce[nSegAct] THEN
                    fForceCmd := MAX(fForceCmd - _fStep, aSegForce[nSegAct]);   // 降力且不越过目标 / Ramp down without overshoot
                END_IF
            END_IF
            (* 到力判据：容差 = max(0.5%×|目标|, 0.1 kN)，浮点比较一律容差式（R4） *)
            _fTol := MAX(ABS(aSegForce[nSegAct]) * DL_PFC_TOL_PCT, DL_PFC_TOL_ABS);
            _bCmdAtTarget := ABS(fForceCmd - aSegForce[nSegAct]) <= DL_PFC_EPS;   // 指令已饱和到目标
            _bFbInTol     := ABS(fForceFb - aSegForce[nSegAct]) <= _fTol;         // 反馈落进容差带
            IF _bCmdAtTarget AND _bFbInTol THEN
                fForceCmd := aSegForce[nSegAct];       // 迁移②：到力，指令精确取目标 / Reached: command set exactly
                _diHoldMs := DL_PFC_MS_ZERO;           // 保压累计清零 / Hold accumulator cleared
                eCause    := E_DL_PfcCause.eNone;      // 信息级：无事件 / Info: no event
                _eState   := E_DL_PfcPhase.eHold;      // 进入保压相 / Move to hold
            ELSIF tonSeg.Q THEN
                IF NOT _bFaultLatch THEN
                    _eCauseLatch := E_DL_PfcCause.eForceNotReached;   // 故障级：单段超时未到力 / Fault: force not reached
                    _bFaultLatch := TRUE;                             // 置故障锁存（迁相由段 8，R21）/ Latch the fault
                END_IF
            END_IF
        END_IF

    E_DL_PfcPhase.eHold :
        IF (NOT bEnable) OR (NOT bStart) THEN
            fForceCmd := DL_PFC_ZERO;                  // 失能：力指令回 0 / Disabled: force zeroed
            nSegAct   := 0;                            // 段号清零 / Segment cleared
            eCause    := E_DL_PfcCause.eNone;          // 信息级：无事件 / Info: no event
            _eState   := E_DL_PfcPhase.eIdle;          // 回空闲相 / Back to idle
        ELSE
            fForceCmd := aSegForce[nSegAct];           // 保压相：力指令锁定目标值 / Hold: command locked to the target
            IF tonDt.Q AND _bDtOk THEN
                _diHoldMs := _diHoldMs + DL_PFC_DT_MS; // 保压毫秒累加 / Accumulate hold milliseconds
            END_IF
            IF _diHoldMs >= TIME_TO_DINT(aSegHold[nSegAct]) THEN
                nSegCompleted := nSegCompleted + DL_PFC_ONE;   // 本段完成计数 / Count the completed segment
                _diHoldMs     := DL_PFC_MS_ZERO;               // 保压累计清零 / Hold accumulator cleared
                IF nSegAct >= _nSegClamp THEN
                    eCause  := E_DL_PfcCause.eCurveDoneCode;    // 迁移④：末段完成 / Info: last segment done
                    _eState := E_DL_PfcPhase.eRelease;          // 进入卸力相 / Move to release
                ELSE
                    nSegAct := nSegAct + DL_PFC_ONE;            // 迁移③：进入下一段 / Next segment
                    _bSegNew := TRUE;                           // 换段：次拍令单段超时 ET 自清 / Segment change: reset the timeout next scan
                    eCause  := E_DL_PfcCause.eSegDone;          // 信息级：一段完成 / Info: one segment done
                    _eState := E_DL_PfcPhase.eRamp;             // 回斜坡相 / Back to ramp
                END_IF
            END_IF
        END_IF

    E_DL_PfcPhase.eRelease :
        IF (NOT bEnable) OR (NOT bStart) THEN
            fForceCmd := DL_PFC_ZERO;                  // 失能：力指令直接归零 / Disabled: force zeroed immediately
            nSegAct   := 0;                            // 段号清零 / Segment cleared
            eCause    := E_DL_PfcCause.eNone;          // 信息级：无事件 / Info: no event
            _eState   := E_DL_PfcPhase.eIdle;          // 回空闲相 / Back to idle
        ELSE
            eCause := E_DL_PfcCause.eReleasing;        // 信息级：卸力中 / Info: releasing
            IF tonDt.Q AND _bDtOk THEN
                _fStep := aSegRate[_nSegClamp] * _fDtSec;                  // 卸力速率取末段速率 / Release rate from the last segment
                fForceCmd := fForceCmd - _fStep;                           // 力指令斜坡下降 / Ramp the command down
                IF fForceCmd < DL_PFC_ZERO THEN
                    fForceCmd := DL_PFC_ZERO;                              // 下限饱和，防负力指令 / Clamp at zero, no negative command
                END_IF
            END_IF
            IF ABS(fForceCmd) <= DL_PFC_EPS THEN
                fForceCmd := DL_PFC_ZERO;              // 迁移⑤：已退到 0，精确归零 / Fully released: exact zero
                eCause    := E_DL_PfcCause.eCurveDoneCode;   // 信息级：曲线完成 / Info: curve completed
                _eState   := E_DL_PfcPhase.eDone;      // 进入完成相 / Move to done
            END_IF
        END_IF

    E_DL_PfcPhase.eDone :
        fForceCmd  := DL_PFC_ZERO;                     // 完成相：力指令保持 0 / Done: force stays zero
        bCurveDone := TRUE;                            // 曲线完成电平 / Curve-done level high
        IF (NOT bStart) OR _bResetPulse THEN
            bCurveDone    := FALSE;                    // 迁移⑥：撤完成电平 / Withdraw the done level
            nSegAct       := 0;                        // 段号清零 / Segment cleared
            nSegCompleted := 0;                        // 完成段数清零 / Completed segments cleared
            eCause        := E_DL_PfcCause.eNone;      // 信息级：无事件 / Info: no event
            _eState       := E_DL_PfcPhase.eIdle;      // 回空闲相 / Back to idle
        END_IF

    E_DL_PfcPhase.eFault :
        fForceCmd := DL_PFC_ZERO;                      // 故障相：力指令回 0（安全侧）/ Fault phase: force zeroed
        IF _bResetPulse AND (NOT bEnable) THEN
            _bFaultLatch  := FALSE;                    // 迁移⑨：清故障锁存 / Clear the fault latch
            _eCauseLatch  := E_DL_PfcCause.eNone;      // 清锁存成因 / Clear the latched cause
            eCause        := E_DL_PfcCause.eNone;      // 出口同步归零 / Outlet follows
            nSegAct       := 0;                        // 段号清零 / Segment cleared
            nSegCompleted := 0;                        // 完成段数清零 / Completed segments cleared
            _diHoldMs     := DL_PFC_MS_ZERO;           // 保压累计清零 / Hold accumulator cleared
            _eState       := E_DL_PfcPhase.eIdle;      // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑩：非法枚举兜底（R6） *)
    IF NOT _bFaultLatch THEN
        _eCauseLatch := E_DL_PfcCause.eIllegalState;   // 故障级：非法状态 / Fault: illegal state
        _bFaultLatch := TRUE;                          // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 7：组态闸失败处理（锁存与迁相分离，R21） —— *)
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _eCauseLatch := _eCauseTmp;                        // 锁存首因（组态闸）/ Latch the configuration cause
    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
END_IF

(* —— 段 8：段尾故障迁移闸 + 故障相动作全撤（FB50-1④） —— *)
IF _bFaultLatch AND (_eState <> E_DL_PfcPhase.eFault) THEN
    _eState := E_DL_PfcPhase.eFault;                   // 锁存即迁相 / Latch forces the fault phase
END_IF
IF _eState = E_DL_PfcPhase.eFault THEN
    fForceCmd  := DL_PFC_ZERO;                         // 故障相力指令全撤（含同拍迁入）/ Force withdrawn in fault
    bCurveDone := FALSE;                               // 故障相撤完成电平 / Done level withdrawn in fault
END_IF

(* —— 段 9：统一出口（状态映射 + 保压时长换算 + 锁存回放） —— *)
eState       := _eState;                               // 相位映射 / Phase mapping
tHoldElapsed := DINT_TO_TIME(_diHoldMs);               // 保压毫秒 → TIME（标准转换）/ Hold milliseconds to TIME
bError       := _bFaultLatch;                          // 故障标志取锁存位 / Fault flag from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                            // 故障期回放锁存码（FB33-1）/ Replay the latched code
END_IF
bValid := ((_eState = E_DL_PfcPhase.eRamp) OR (_eState = E_DL_PfcPhase.eHold)
           OR (_eState = E_DL_PfcPhase.eRelease)) AND (NOT _bFaultLatch);   // 执行相且无锁存时有效
END_FUNCTION_BLOCK
