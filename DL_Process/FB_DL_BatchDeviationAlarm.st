//==============================================================================
// 功能块：FB_DL_BatchDeviationAlarm ｜ 中文名称：批次偏差分级报警与首出归因
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：批次偏差四档分级监视——|测量 - 设定| 越档判定：预警档
//           （fBandWarn < |偏差| <= fBandMinor）、次要档（<= fBandMajor）、
//           严重档（> fBandMajor），越限须持续 tDebounce 才确认（防瞬时
//           噪声）；首出归因：首个非正常档确认时锁存档位与方向（高/低
//           向），锁存至 bReset，后续档位波动不重写首因（归因证据链，
//           R81 还原方向不饱和同理）。严重档确认为故障级（置 bError），
//           预警/次要档为信息级。
// 开源溯源 (Origin)：道莅原创实现（参考批次过程偏差分级与首出报警（first-out）工程惯例 分类与参数域）
// 单位表：偏差[工艺量纲（与 fValueMeas/fValueSp 同量纲）] / 带宽[同量纲] /
//         时间[ms]
// 错误码表：16#0005_01FA 信息级（预警/次要档偏差激活确认，不置 bError）/
//           16#0005_01FB 信息级（首出归因锁存已建立，不置 bError）/
//           16#0005_033C 故障级（组态非法：带宽非单调（须 0 < 预警 <
//           次要 < 严重）或任一输入非有限，置 bError）/ 16#0005_033D
//           故障级（严重档偏差确认：去抖后仍 > fBandMajor，置 bError，
//           并建立首出锁存——该场景不可由 033C 的组态类判据观测，属
//           工艺偏差独立域）/ 16#0005_033E 故障级兜底（状态机落 ELSE，
//           置 bError）
// 状态机：E_DL_BatchDevState（四态：eIdle=0 / eMonitor=10 / eFault=99，
//           外加 eDeviated=20 激活保持态），CASE 含 ELSE 兜底，ELSE 置
//           033E 并输出正常档
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 越限去抖未满判据
//           消失 → 不确认（防瞬时噪声）；③ 偏差回落至正常带 → 回监视
//           态（首出锁存保持，bReset 才清）；④ 首出锁存仅在无锁存时
//           建立（首出语义，后续波动不重写）；⑤ 未使能输出正常档且
//           bValid := FALSE；⑥ 安全侧 = 故障路径偏差档位输出严重档
//           （不可信数据按最坏档呈现）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §734）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_BatchDevLevel（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 偏差四档分级（档位 0..3，对应越限带宽递增）。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_BatchDevLevel :
(
    eNormal := 0,   // 正常：偏差在预警带内 / Normal, deviation inside the warn band
    eWarn   := 1,   // 预警：|偏差| > 预警带 / Warn, deviation beyond the warn band
    eMinor  := 2,   // 次要：|偏差| > 次要带 / Minor, deviation beyond the minor band
    eMajor  := 3    // 严重：|偏差| > 严重带（故障级） / Major, deviation beyond the major band, fault class
);
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_BatchDevState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 分级监视相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_BatchDevState :
(
    eIdle     := 0,   // 空闲：未使能 / Idle, not enabled
    eMonitor  := 10,  // 监视：档位判定与去抖 / Monitor, level verdict and debounce
    eDeviated := 20,  // 激活保持：非正常档确认保持 / Deviated, non-normal level held
    eFault    := 99   // 故障：组态非法/非法状态 / Fault, config or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_BatchDeviationAlarm
VAR_INPUT
    bEnable     : BOOL;                     // 分级监视使能 [—] / Monitoring enable
    bReset      : BOOL;                     // 故障/首出复位 [—]，上升沿清首出锁存 / Fault and first-out reset, rising edge clears latches
    fValueMeas  : LREAL;                    // 批次实测值 [工艺量纲] / Batch measured value [process unit]
    fValueSp    : LREAL;                    // 批次设定值 [工艺量纲] / Batch setpoint [process unit]
    fBandWarn   : LREAL := 1.0;             // 预警带宽 [工艺量纲]，须 > 0 / Warn band width [process unit]
    fBandMinor  : LREAL := 2.0;             // 次要带宽 [工艺量纲]，须 > 预警带宽 / Minor band width [process unit]
    fBandMajor  : LREAL := 5.0;             // 严重带宽 [工艺量纲]，须 > 次要带宽 / Major band width [process unit]
    tDebounce   : TIME  := T#2S;            // 越限去抖窗 [ms]，须 > 0 / Violation debounce window [ms]
END_VAR
VAR_OUTPUT
    eDevLevel    : E_DL_BatchDevLevel;      // 当前偏差档位 [—] / Current deviation level
    fDeviation   : LREAL;                   // 当前偏差 [工艺量纲]（带符号，诊断出口） / Current deviation [process unit], signed, diagnostics
    bFirstOut    : BOOL;                    // 首出锁存有效 [—]（bReset 才清） / First-out latch valid, cleared by reset
    eFirstOut    : E_DL_BatchDevLevel;      // 首出档位 [—] / First-out level
    bFirstHigh   : BOOL;                    // 首出方向 [—]，TRUE = 高向 / First-out direction, TRUE high side
    eState       : E_DL_BatchDevState;      // 相位出口 [—] / Phase outlet
    eErr         : UDINT;                   // 错误码，0 = 无错，码位 16#0005_01FA 起信息级、16#0005_033C 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError       : BOOL;                    // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid       : BOOL;                    // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbDebounce : TON;                       // 越限去抖计时（每拍无条件刷新）[ms] / Debounce timer, refreshed unconditionally
    _eState    : E_DL_BatchDevState := E_DL_BatchDevState.eIdle; // 当前相位 / Current phase
    _bCfgBad   : BOOL;                      // 组态非法锁存 / Illegal config latch
    _eLevelNow : E_DL_BatchDevLevel := E_DL_BatchDevLevel.eNormal; // 本拍档位判定 / Level verdict of this scan
    _bViolate  : BOOL;                      // 越限电平（非正常档判定） / Violation level
    _bInfoAct  : BOOL;                      // 预警/次要激活信息当拍标志 / Warn or minor activation info flag
    _bInfoFirst: BOOL;                      // 首出建立信息当拍标志 / First-out-established info flag
    _bIllegal  : BOOL;                      // 非法状态标志 / Illegal state flag
    _bInit     : BOOL := FALSE;             // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_BDA_INF  : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_BDA_EPS  : LREAL := 1.0E-6;          // 浮点判零容差 [工艺量纲] / Float zero tolerance [process unit]
    DL_BDA_ZERO : LREAL := 0.0;             // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：档位出口正常档起步（安全侧），单拍标志预清零
 *      Level outlet starts at normal, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
eDevLevel  := E_DL_BatchDevLevel.eNormal; // 档位出口先置正常（激活态在段 5 重置） / Level preset normal
fDeviation := DL_BDA_ZERO;               // 偏差出口每拍重算 / Deviation outlet recomputed
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoAct  := FALSE;                     // 激活信息预清零 / Activation info pre-cleared
_bInfoFirst := FALSE;                    // 首出信息预清零 / First-out info pre-cleared
_bIllegal   := FALSE;                    // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState  := E_DL_BatchDevState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    bFirstOut := FALSE;                  // 首出锁存清零 / First-out latch cleared
    eFirstOut := E_DL_BatchDevLevel.eNormal; // 首出档位清零 / First-out level reset
    bFirstHigh := FALSE;                 // 首出方向清零 / First-out direction reset
    _bInit   := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 带宽单调域（0 < 预警 < 次要 < 严重）
 *      Configuration defense gates with the band monotonicity rule
 *-----------------------------------------------------------------------------*)
IF (fValueMeas <> fValueMeas) OR (ABS(fValueMeas) > DL_BDA_INF)
   OR (fValueSp <> fValueSp) OR (ABS(fValueSp) > DL_BDA_INF)
   OR (fBandWarn <> fBandWarn) OR (ABS(fBandWarn) > DL_BDA_INF)
   OR (fBandMinor <> fBandMinor) OR (ABS(fBandMinor) > DL_BDA_INF)
   OR (fBandMajor <> fBandMajor) OR (ABS(fBandMajor) > DL_BDA_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fBandWarn <= DL_BDA_EPS) OR (fBandMinor <= fBandWarn)
   OR (fBandMajor <= fBandMinor) OR (tDebounce <= T#0MS)) THEN
    _bCfgBad := TRUE;                    // 带宽非单调或去抖窗非法锁存 / Non-monotonic bands or illegal window latched
END_IF
IF bReset THEN
    _bCfgBad := FALSE;                   // 复位清组态锁存 / Reset clears the config latch
    bFirstOut := FALSE;                  // 复位清首出锁存（归因证据链重开） / Reset clears the first-out latch
    eFirstOut := E_DL_BatchDevLevel.eNormal; // 复位清首出档位 / Reset clears the first-out level
    bFirstHigh := FALSE;                 // 复位清首出方向 / Reset clears the direction
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜档位判定与去抖计时无条件刷新（R40：CASE 之外每拍必调）
 *      Level verdict and debounce timer refreshed unconditionally
 *-----------------------------------------------------------------------------*)
IF (NOT _bCfgBad) AND ((fValueMeas <> fValueMeas) OR (ABS(fValueMeas) > DL_BDA_INF)
   OR (fValueSp <> fValueSp) OR (ABS(fValueSp) > DL_BDA_INF)) THEN
    _eLevelNow := E_DL_BatchDevLevel.eMajor; // 运行中数据非有限按最坏档呈现（R90：033D 域复用） / Non-finite data presented as the worst level
ELSE
    fDeviation := fValueMeas - fValueSp; // 带符号偏差 [工艺量纲] / Signed deviation
    IF ABS(fDeviation) > fBandMajor THEN
        _eLevelNow := E_DL_BatchDevLevel.eMajor; // 严重档 / Major
    ELSIF ABS(fDeviation) > fBandMinor THEN
        _eLevelNow := E_DL_BatchDevLevel.eMinor; // 次要档 / Minor
    ELSIF ABS(fDeviation) > fBandWarn THEN
        _eLevelNow := E_DL_BatchDevLevel.eWarn; // 预警档 / Warn
    ELSE
        _eLevelNow := E_DL_BatchDevLevel.eNormal; // 正常档 / Normal
    END_IF
END_IF
_bViolate := (_eLevelNow <> E_DL_BatchDevLevel.eNormal); // 越限电平（任一非正常档） / Violation level
fbDebounce(IN := (_eState = E_DL_BatchDevState.eMonitor) AND _bViolate
             AND (_eLevelNow = eDevLevel), PT := tDebounce); // 越限去抖窗（同档驻留） / Debounce window on the same level

(*------------------------------------------------------------------------------
 * 段 5｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_BatchDevState.eIdle:              // 空闲：使能且组态合法进监视
        IF bEnable AND (NOT _bCfgBad) THEN
            _eState := E_DL_BatchDevState.eMonitor; // 进监视 / To monitor
        ELSIF bEnable AND _bCfgBad THEN
            _eState := E_DL_BatchDevState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_BatchDevState.eMonitor:           // 监视：同档越限去抖满进激活保持
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_BatchDevState.eFault; // 异常转故障 / Anomaly, fault
        ELSIF fbDebounce.Q THEN
            IF (NOT bFirstOut) THEN
                bFirstOut := TRUE;         // 首出锁存建立（后续波动不重写，R81） / First-out latch established, never rewritten
                eFirstOut := _eLevelNow;   // 首出档位锁定 / First-out level locked
                bFirstHigh := fDeviation > DL_BDA_ZERO; // 首出方向锁定 / First-out direction locked
                _bInfoFirst := TRUE;       // 首出建立提示（信息级，拍 N 进入） / First-out notice, info
            END_IF
            IF _eLevelNow = E_DL_BatchDevLevel.eMajor THEN
                _eState := E_DL_BatchDevState.eDeviated; // 严重档确认进激活保持（故障级在段 6 报） / Major confirmed, to deviated
            ELSE
                _bInfoAct := TRUE;         // 预警/次要档激活（信息级） / Warn or minor activation, info
                _eState := E_DL_BatchDevState.eDeviated; // 进激活保持 / To deviated
            END_IF
        END_IF

    E_DL_BatchDevState.eDeviated:          // 激活保持：偏差回正常带回监视（首出锁存保持）
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_BatchDevState.eFault; // 异常转故障 / Anomaly, fault
        ELSIF _eLevelNow = E_DL_BatchDevLevel.eNormal THEN
            _eState := E_DL_BatchDevState.eMonitor; // 回监视（首出锁存保持） / Back to monitor, first-out held
        END_IF

    E_DL_BatchDevState.eFault:             // 故障：复位沿且组态恢复回监视
        IF bReset AND (NOT _bCfgBad) THEN
            _eState := E_DL_BatchDevState.eMonitor; // 回监视 / Back to monitor
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        eDevLevel := E_DL_BatchDevLevel.eMajor; // 最坏档呈现（安全侧） / Worst level presented
        _eState := E_DL_BatchDevState.eFault; // 回故障态 / Back to fault
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_033E;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0005_033C;                // 故障级：组态非法（带宽非单调） / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF (_eState = E_DL_BatchDevState.eDeviated)
      AND (_eLevelNow = E_DL_BatchDevLevel.eMajor) THEN
    eErr   := 16#0005_033D;                // 故障级：严重档偏差确认 / Fault: major deviation confirmed
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoAct THEN
    eErr := 16#0005_01FA;                  // 信息级：预警/次要档激活 / Info: warn or minor activation
ELSIF _bInfoFirst THEN
    eErr := 16#0005_01FB;                  // 信息级：首出归因锁存建立 / Info: first-out latch established
END_IF

IF _eState <> E_DL_BatchDevState.eFault THEN
    eDevLevel := _eLevelNow;               // 档位出口（非故障态按本拍判定） / Level outlet by the scan verdict
END_IF
bValid := (NOT bError) AND bEnable AND (_eState <> E_DL_BatchDevState.eIdle); // 空闲/故障/未使能输出不可用 / Outputs unusable in idle, fault or disabled
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
