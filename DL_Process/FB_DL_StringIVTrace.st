//==============================================================================
// 功能块：FB_DL_StringIVTrace ｜ 中文名称：组串 IV 曲线扫描与特征点提取
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：光伏组串 IV 扫描顺控——恒压步进扫描（fVCmdV 由 0 按步距
//           递增至扫描上限），每步等驻留窗并握手 bMeasReady 采样电压/
//           电流，特征点提取：Isc = 起始电压步电流（V 约为零）、Voc =
//           电流首次跌破开路阈值的步电压、Pmax/Vmp/Imp = 全程功率最大
//           步、FF = Pmax/(Voc·Isc)（填充因子）。Voc 捕获后可提前收扫
//           （曲线尾段无信息量）。测量步超时（tMeasTimeout 窗满仍未
//           就绪）→ 故障中止扫描。
// 开源溯源 (Origin)：道莅原创实现（参考 IEC 61829 光伏方阵 IV 特性现场测量 分类与参数域）
// 单位表：电压[V] / 电流[A] / 功率[W] / 步距[V] / 填充因子[无量纲] /
//         阈值电流[A] / 时间[ms]
// 错误码表：16#0005_01F0 信息级（扫描完成且 Voc/Isc/Pmax 全捕获，不置
//           bError）/ 16#0005_01F1 信息级（特征点降级：Voc 或 Isc 未
//           有效捕获，FF 置 0 照常输出，不置 bError）/ 16#0005_032D
//           故障级（组态非法：步距/上限/阈值 <= 0、时间窗 <= 0 或任一
//           输入非有限，置 bError）/ 16#0005_032E 故障级（测量步超时：
//           tMeasTimeout 窗满 bMeasReady 仍未就绪，扫描中止锁存，置
//           bError——该场景不可由 032D 的组态类判据观测，属运行握手
//           独立域）/ 16#0005_032F 故障级兜底（状态机落 ELSE，置
//           bError）
// 状态机：E_DL_IvTracePhase（四态：eIdle=0 / eSweep=10 / eDone=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 032F 并清扫描输出
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② bAbort → 本拍
//           拒绝扫描推进、清命令电压，回空闲（中止不占相位，单拍标志
//           不外泄）；③ Voc 提前捕获 → 扫描立即收尾（曲线尾段无信息量，
//           缩短扫拍）；④ Voc/Isc 缺失 → FF 置 0 + 信息 01F1 降级照常
//           输出（除零防御，不置故障）；⑤ 未启动/故障态命令电压冻结
//           为 0 并 bValid := FALSE；⑥ eDone 等启动撤销回空闲（同拍
//           重启防抖，R39 范式）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P0 §228）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_IvTracePhase（归属本功能块，同文件发布，全库唯一定义）
 * 含义: IV 扫描相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_IvTracePhase :
(
    eIdle   := 0,   // 空闲：等启动沿 / Idle, awaiting start edge
    eSweep  := 10,  // 扫描：步进采集中 / Sweep, stepping and sampling
    eDone   := 20,  // 完成：特征点锁存，等启动撤销 / Done, features latched, awaiting start drop
    eFault  := 99   // 故障：组态非法/测量超时/非法状态 / Fault, config, measurement timeout or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_StringIVTrace
VAR_INPUT
    bStart       : BOOL;                    // 启动请求 [—]，上升沿生效 / Start request, rising edge
    bAbort       : BOOL;                   // 中止请求 [—]，任意拍生效 / Abort request, effective on any scan
    bReset       : BOOL;                   // 故障复位 [—]，上升沿清故障态 / Fault reset, rising edge clears the fault state
    fMeasV       : LREAL;                  // 测量电压回读 [V] / Measured voltage feedback [V]
    fMeasI       : LREAL;                  // 测量电流回读 [A] / Measured current feedback [A]
    bMeasReady   : BOOL;                   // 测量就绪握手 [—]（每步采样条件） / Measurement ready handshake
    fVStepV      : LREAL := 0.5;           // 电压步距 [V]，须 > 0 / Voltage step [V], must be > 0
    fVMaxV       : LREAL := 50.0;          // 扫描电压上限 [V]，须 > 步距 / Sweep voltage ceiling [V], must exceed the step
    fIocThreshA  : LREAL := 0.002;         // 开路阈值电流 [A]，电流低于此判 Voc，须 > 0 / Open-circuit current threshold [A], must be > 0
    tStepDwell   : TIME  := T#50MS;        // 每步驻留窗 [ms]，须 > 0 / Per-step dwell window [ms]
    tMeasTimeout : TIME  := T#1S;          // 测量超时窗 [ms]，须 > 驻留窗（R100 配比） / Measurement timeout window [ms], must exceed the dwell
END_VAR
VAR_OUTPUT
    fVCmdV    : LREAL;                     // 扫描命令电压 [V]（给电子负载/扫频源） / Sweep command voltage [V]
    fVocV     : LREAL;                     // 开路电压特征点 [V]，未捕获为 0 / Open-circuit voltage feature [V], zero when not captured
    fIscA     : LREAL;                     // 短路电流特征点 [A]，未捕获为 0 / Short-circuit current feature [A], zero when not captured
    fPmaxW    : LREAL;                     // 最大功率点功率 [W] / Maximum power point [W]
    fVmpV     : LREAL;                     // 最大功率点电压 [V] / Maximum power point voltage [V]
    fImpA     : LREAL;                     // 最大功率点电流 [A] / Maximum power point current [A]
    fFillFactor : LREAL;                   // 填充因子 [无量纲]，Voc·Isc 无效时置 0 / Fill factor, zero when Voc or Isc invalid
    ePhase    : E_DL_IvTracePhase;         // 扫描相位 [—] / Sweep phase
    bTraceDone: BOOL;                      // 扫描完成 [—]（完成态电平） / Trace done, completion level
    eErr      : UDINT;                     // 错误码，0 = 无错，码位 16#0005_01F0 起信息级、16#0005_032D 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError    : BOOL;                      // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid    : BOOL;                      // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbDwell   : TON;                       // 每步驻留计时（每拍无条件刷新）[ms] / Dwell timer, refreshed unconditionally
    fbMeasTo  : TON;                       // 测量超时计时（每拍无条件刷新）[ms] / Measurement timeout timer, refreshed unconditionally
    fbStart   : R_TRIG;                    // 启动沿检测（待机/故障分支同样无条件刷新） / Start edge detector, refreshed unconditionally
    _ePhase   : E_DL_IvTracePhase := E_DL_IvTracePhase.eIdle; // 当前相位 / Current phase
    _bCfgBad  : BOOL;                      // 组态非法锁存 / Illegal config latch
    _fVSweep  : LREAL;                     // 当前扫描电压 [V] / Current sweep voltage [V]
    _fVocCap  : LREAL;                     // Voc 捕获暂存 [V] / Voc capture staging [V]
    _fIscCap  : LREAL;                     // Isc 捕获暂存 [A] / Isc capture staging [A]
    _bVocOk   : BOOL;                      // Voc 捕获有效标志 / Voc captured flag
    _bIscOk   : BOOL;                      // Isc 捕获有效标志 / Isc captured flag
    _bInfoFull: BOOL;                      // 全捕获信息当拍标志 / Full-capture info flag of this scan
    _bInfoDeg : BOOL;                      // 降级信息当拍标志 / Degraded info flag of this scan
    _bIllegal : BOOL;                      // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;             // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_IVT_INF    : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_IVT_EPS    : LREAL := 1.0E-6;        // 浮点判零容差 [混合] / Float zero tolerance
    DL_IVT_ZERO   : LREAL := 0.0;           // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
    DL_IVT_FF_MIN : LREAL := 0.0;           // 填充因子下限 [无量纲] / Fill factor floor
    DL_IVT_FF_MAX : LREAL := 1.0;           // 填充因子上限 [无量纲] / Fill factor ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：命令电压安全侧清零，特征输出每拍重算，单拍标志预清零
 *      Command voltage cleared fail-safe, features recomputed, flags pre-cleared
 *-----------------------------------------------------------------------------*)
fVCmdV   := DL_IVT_ZERO;                 // 命令电压先清（安全侧；扫描态在段 3 重置） / Command voltage cleared first
fVocV    := DL_IVT_ZERO;                 // 特征出口每拍重算 / Feature outlets recomputed
fIscA    := DL_IVT_ZERO;                 // 特征出口每拍重算 / Feature outlets recomputed
fPmaxW   := DL_IVT_ZERO;                 // 特征出口每拍重算 / Feature outlets recomputed
fVmpV    := DL_IVT_ZERO;                 // 特征出口每拍重算 / Feature outlets recomputed
fImpA    := DL_IVT_ZERO;                 // 特征出口每拍重算 / Feature outlets recomputed
fFillFactor := DL_IVT_ZERO;              // 填充因子每拍重算 / Fill factor recomputed
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoFull := FALSE;                     // 全捕获信息预清零 / Full-capture info pre-cleared
_bInfoDeg  := FALSE;                     // 降级信息预清零 / Degraded info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _ePhase  := E_DL_IvTracePhase.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    _fVSweep := DL_IVT_ZERO;             // 扫描电压从零起步 / Sweep voltage starts at zero
    _bInit   := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸 + 沿检测无条件刷新（R40）
 *      Config gates and unconditional edge/timer refresh
 *-----------------------------------------------------------------------------*)
fbStart(CLK := bStart);                  // 启动沿检测 / Start edge detection
IF (fVStepV <> fVStepV) OR (ABS(fVStepV) > DL_IVT_INF)
   OR (fVMaxV <> fVMaxV) OR (ABS(fVMaxV) > DL_IVT_INF)
   OR (fIocThreshA <> fIocThreshA) OR (ABS(fIocThreshA) > DL_IVT_INF)
   OR (fMeasV <> fMeasV) OR (ABS(fMeasV) > DL_IVT_INF)
   OR (fMeasI <> fMeasI) OR (ABS(fMeasI) > DL_IVT_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fVStepV <= DL_IVT_EPS) OR (fVMaxV <= fVStepV)
   OR (fIocThreshA <= DL_IVT_EPS) OR (tStepDwell <= T#0MS)
   OR (tMeasTimeout <= tStepDwell)) THEN
    _bCfgBad := TRUE;                    // 步距/上限/阈值/时间窗非法锁存（含 R100 配比：超时窗 > 驻留窗） / Step, ceiling, threshold and window domains latched
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜双计时无条件刷新（R40：CASE 之外每拍必调）
 *      Two timers refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbDwell(IN := (_ePhase = E_DL_IvTracePhase.eSweep) AND (NOT bAbort), PT := tStepDwell); // 步驻留窗 / Step dwell window
fbMeasTo(IN := (_ePhase = E_DL_IvTracePhase.eSweep) AND (NOT bAbort)
              AND (NOT bMeasReady), PT := tMeasTimeout); // 测量超时窗 / Measurement timeout window

(*------------------------------------------------------------------------------
 * 段 5｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF

    E_DL_IvTracePhase.eIdle:               // 空闲：启动沿且组态合法进扫描
        IF fbStart.Q AND (NOT _bCfgBad) THEN
            _fVSweep := DL_IVT_ZERO;       // 扫描电压归零起步 / Sweep voltage reset to zero
            _bVocOk  := FALSE;             // 捕获标志复位 / Capture flags reset
            _bIscOk  := FALSE;             // 捕获标志复位 / Capture flags reset
            _ePhase  := E_DL_IvTracePhase.eSweep; // 进扫描 / To sweep
        ELSIF fbStart.Q AND _bCfgBad THEN
            _ePhase := E_DL_IvTracePhase.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_IvTracePhase.eSweep:              // 扫描：采样、判 Voc、步进、收尾
        IF _bCfgBad OR bAbort THEN
            fVCmdV := DL_IVT_ZERO;         // 中止拍拒绝推进并清命令（拍 N 进入行为） / Abort scan rejects progress and clears the command
            _ePhase := E_DL_IvTracePhase.eIdle; // 拍 N+1 转出：回空闲（中止不占相位） / Back to idle, abort holds no phase
        ELSIF fbMeasTo.Q THEN
            _ePhase := E_DL_IvTracePhase.eFault; // 测量超时进故障 / Measurement timeout to fault
        ELSIF fbDwell.Q AND bMeasReady THEN
            IF (NOT _bIscOk) AND (_fVSweep <= fVStepV) THEN
                _fIscCap := fMeasI;        // Isc：起始电压步电流（V 约为零） / Isc from the first near-zero step
                _bIscOk  := TRUE;          // Isc 捕获有效 / Isc captured
            END_IF
            IF (NOT _bVocOk) AND (fMeasI < fIocThreshA) THEN
                _fVocCap := fMeasV;        // Voc：电流首次跌破开路阈值步电压 / Voc at the first sub-threshold step
                _bVocOk  := TRUE;          // Voc 捕获有效 / Voc captured
            END_IF
            IF (fMeasV * fMeasI) > fPmaxW THEN
                fPmaxW := fMeasV * fMeasI; // 最大功率点功率 [W] / Maximum power [W]
                fVmpV  := fMeasV;          // 最大功率点电压 [V] / MPP voltage
                fImpA  := fMeasI;          // 最大功率点电流 [A] / MPP current
            END_IF
            IF _bVocOk OR (_fVSweep + fVStepV > fVMaxV) THEN
                _ePhase := E_DL_IvTracePhase.eDone; // Voc 已捕获或达上限：收扫 / Voc captured or ceiling reached, close the sweep
            ELSE
                _fVSweep := _fVSweep + fVStepV; // 步进推进 / Step advance
            END_IF
        END_IF

    E_DL_IvTracePhase.eDone:               // 完成：等启动撤销回空闲（同拍重启防抖）
        IF NOT bStart THEN
            _ePhase := E_DL_IvTracePhase.eIdle; // 回空闲 / Back to idle
        END_IF

    E_DL_IvTracePhase.eFault:              // 故障：复位沿且组态恢复回空闲
        IF bReset AND (NOT _bCfgBad) THEN
            _ePhase := E_DL_IvTracePhase.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        fVCmdV := DL_IVT_ZERO;             // 命令电压清零（安全侧） / Command cleared, safe side
        _ePhase := E_DL_IvTracePhase.eFault; // 回故障态 / Back to fault
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜扫描命令出口与特征点换算（除零防御 + 填充因子钳域）
 *      Command outlet and feature scaling with divide guards
 *-----------------------------------------------------------------------------*)
IF _ePhase = E_DL_IvTracePhase.eSweep THEN
    fVCmdV := _fVSweep;                    // 扫描态命令电压 = 当前扫描点 / Sweep command equals the current point
END_IF
IF _bVocOk THEN
    fVocV := _fVocCap;                     // Voc 出口 / Voc outlet
END_IF
IF _bIscOk THEN
    fIscA := _fIscCap;                     // Isc 出口 / Isc outlet
END_IF
IF _bVocOk AND _bIscOk THEN
    IF ABS(_fVocCap * _fIscCap) > DL_IVT_EPS THEN
        fFillFactor := MIN(MAX(fPmaxW / (_fVocCap * _fIscCap), DL_IVT_FF_MIN), DL_IVT_FF_MAX); // 填充因子 [无量纲]，分母已闸且钳域 / Fill factor, denominator gated and clamped
    END_IF
    IF _ePhase = E_DL_IvTracePhase.eDone THEN
        _bInfoFull := TRUE;                // 全捕获完成（信息级） / Full capture done, info
    END_IF
ELSIF _ePhase = E_DL_IvTracePhase.eDone THEN
    _bInfoDeg := TRUE;                     // 特征点降级：Voc 或 Isc 未捕获，FF 置 0（信息级） / Degraded features, FF zero, info
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_032F;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0005_032D;                // 故障级：组态非法（触发前或扫描中漂移同域） / Fault: illegal configuration, drift folded
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _ePhase = E_DL_IvTracePhase.eFault THEN
    eErr   := 16#0005_032E;                // 故障级：测量步超时（组态恢复后落此域即超时） / Fault: measurement timeout
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoDeg THEN
    eErr := 16#0005_01F1;                  // 信息级：特征点降级 / Info: degraded features
ELSIF _bInfoFull THEN
    eErr := 16#0005_01F0;                  // 信息级：扫描完成全捕获 / Info: sweep done, full capture
END_IF

bTraceDone := (_ePhase = E_DL_IvTracePhase.eDone); // 完成电平挂状态量（R99） / Done level bound to the state
bValid := (NOT bError) AND (_ePhase = E_DL_IvTracePhase.eDone); // 仅完成态放行 / Usable only in the done phase
ePhase := _ePhase;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
