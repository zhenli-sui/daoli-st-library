//==============================================================================
// 功能块：FB_DL_SolderRibbonTension ｜ 中文名称：焊带放卷张力与蛇形纠偏
// 所属子库：DL_Motion ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：光伏焊带（互连条）放卷张力控制——锥度张力设定随卷径递减：
//           SP(D) = fTensionFullN x (1 - fTaperPct/100 x (D - D芯)/
//           (D满 - D芯))，卷芯处设定 = 满卷设定、满卷处设定 = 满卷设定
//           x (1 - 锥度百分比)（卷径越大张力越低，防内层压伤）；张力
//           偏差经比例修调输出（fTrimPct，给放卷驱动张力修调入口）；
//           横动机构行程窗口拦截（|位置| >= 限位即封锁横动输出）+ 接近
//           限位预警带。运行中张力 < 断带阈或 >= 超限阈（双端判据）→
//           断带/超限锁存跳闸请求。
// 开源溯源 (Origin)：道莅原创实现（参考放卷锥度张力控制工程惯例 分类与参数域）
// 单位表：张力[N] / 卷径[毫米] / 锥度[百分数] / 修调[百分数] / 修调增益
//         [百分数每牛] / 横动位置[毫米] / 时间[ms]
// 错误码表：16#0004_01E7 信息级（张力偏差进入预警带，不置 bError）/
//           16#0004_01E8 信息级（横动接近行程限位预警带，不置 bError）/
//           16#0004_0306 故障级（组态非法：卷径/张力/锥度/限位域、时间
//           窗 <= 0 或任一输入非有限，置 bError）/ 16#0004_0307 故障级
//           （断带/超限锁存：运行中张力 < 断带阈或 >= 超限阈持续去抖
//           窗，跳闸请求锁存，置 bError——该场景不可由 0306 的组态类
//           判据观测，属运行张力独立域）/ 16#0004_0308 故障级兜底（状态
//           机落 ELSE，置 bError）
// 状态机：E_DL_RibbonTenState（四态：eIdle=0 / eRun=10 / eTrip=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 0308 并撤修调输出
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 卷径域外钳
//           [D芯, D满] 照算（换卷瞬态照常出设定）；③ 锥度百分比域
//           [0, 100]，= 0 即恒张力；④ 横动 |位置| >= 限位 → 封锁横动
//           输出（电平），>= 90% 限位 → 信息预警；⑤ 跳闸锁存至 bReset；
//           ⑥ 安全侧 = 故障/跳闸路径修调输出撤零，禁止带故障修调。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §703）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_RibbonTenState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 放卷张力相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_RibbonTenState :
(
    eIdle   := 0,   // 空闲：未使能 / Idle, not enabled
    eRun    := 10,  // 运行：锥度设定与修调闭环 / Run, taper setpoint and trim loop
    eTrip   := 20,  // 跳闸：断带/超限锁存 / Trip, break or over-limit latched
    eFault  := 99   // 故障：组态非法/非法状态 / Fault, config or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_SolderRibbonTension
VAR_INPUT
    bEnable        : BOOL;                  // 张力控制使能 [—] / Tension control enable
    bReset         : BOOL;                  // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    bRunning       : BOOL;                  // 放卷运行 [—]（判据与修调的使能前提） / Unwind running
    fTensionMeasN  : LREAL;                 // 张力实测 [牛] / Measured tension [N]
    fDiamNowMm     : LREAL;                 // 当前卷径 [毫米]，域外钳 [D芯, D满] 照算 / Current roll diameter [mm]
    fDiamFullMm    : LREAL := 300.0;        // 满卷直径 [毫米]，须 > 卷芯 / Full roll diameter [mm]
    fDiamCoreMm    : LREAL := 50.0;         // 卷芯直径 [毫米]，须 >= 0 且 < 满卷 / Core diameter [mm]
    fTensionFullN  : LREAL := 20.0;         // 卷芯处张力设定 [牛]，须 > 0 / Tension setpoint at the core [N]
    fTaperPct      : LREAL := 20.0;         // 锥度百分比 [百分数]，域 [0, 100]，0 = 恒张力 / Taper percent [percent], 0 = constant tension
    fTensionBreakN : LREAL := 2.0;          // 断带阈 [牛]，运行中低于此判断带 / Break threshold [N]
    fTensionOverN  : LREAL := 60.0;         // 超限阈 [牛]，运行中高于此判过张力 / Over-tension threshold [N]
    fTrimGainPctPerN: LREAL := 2.0;         // 修调增益 [百分数每牛] / Trim gain [percent/N]
    fLateralPosMm  : LREAL;                 // 横动位置 [毫米] / Lateral position [mm]
    fLateralLimitMm: LREAL := 30.0;         // 横动行程限 [毫米]，须 > 0 / Lateral travel limit [mm]
    tTripDebounce  : TIME  := T#500MS;      // 断带/超限去抖窗 [ms]，须 > 0 / Trip debounce window [ms]
END_VAR
VAR_OUTPUT
    fTensionSpN    : LREAL;                 // 锥度后张力设定 [牛]（诊断出口） / Tapered tension setpoint [N], diagnostics outlet
    fTrimPct       : LREAL;                 // 张力修调输出 [百分数]，-100..100 / Tension trim output [percent]
    bLateralBlock  : BOOL;                  // 横动封锁 [—]（行程限位电平） / Lateral block, limit level
    eState         : E_DL_RibbonTenState;   // 相位出口 [—] / Phase outlet
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0004_01E7 起信息级、16#0004_0306 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbTrip    : TON;                        // 断带/超限去抖计时（每拍无条件刷新）[ms] / Trip debounce timer, refreshed unconditionally
    _eState   : E_DL_RibbonTenState := E_DL_RibbonTenState.eIdle; // 当前相位 / Current phase
    _bCfgBad  : BOOL;                       // 组态非法锁存 / Illegal config latch
    _bTripL   : BOOL;                       // 断带/超限锁存 / Break or over-limit latch
    _bInfoBand: BOOL;                       // 张力预警信息当拍标志 / Tension-band info flag of this scan
    _bInfoLat : BOOL;                       // 横动预警信息当拍标志 / Lateral-band info flag of this scan
    _fDiaUse  : LREAL;                      // 生效卷径（已钳位）[毫米] / Effective diameter, clamped [mm]
    _fSpanMm  : LREAL;                      // 卷径跨度 [毫米]（除零已闸） / Diameter span [mm]
    _bIllegal : BOOL;                       // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_SRT_INF    : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_SRT_EPS    : LREAL := 1.0E-6;        // 浮点判零容差 [混合] / Float zero tolerance
    DL_SRT_TRIMMAX: LREAL := 100.0;         // 修调满幅 [百分数] / Trim full scale [percent]
    DL_SRT_LATWARN: LREAL := 0.9;           // 横动预警带占比 [比值]（90% 限位） / Lateral warning ratio [ratio]
    DL_SRT_ZERO   : LREAL := 0.0;           // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：修调输出先撤（安全侧），单拍标志预清零
 *      Trim cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fTrimPct    := DL_SRT_ZERO;              // 修调输出先撤（运行态在段 5 重置） / Trim cleared first
fTensionSpN := DL_SRT_ZERO;              // 设定出口每拍重算 / Setpoint outlet recomputed
bLateralBlock := FALSE;                  // 横动封锁先清 / Lateral block cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoBand := FALSE;                     // 张力预警预清零 / Tension info pre-cleared
_bInfoLat  := FALSE;                     // 横动预警预清零 / Lateral info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState  := E_DL_RibbonTenState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    _bTripL  := FALSE;                   // 跳闸锁存清零 / Trip latch cleared
    _bInit   := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 卷径/张力/锥度/限位域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fTensionMeasN <> fTensionMeasN) OR (ABS(fTensionMeasN) > DL_SRT_INF)
   OR (fDiamNowMm <> fDiamNowMm) OR (ABS(fDiamNowMm) > DL_SRT_INF)
   OR (fDiamFullMm <> fDiamFullMm) OR (ABS(fDiamFullMm) > DL_SRT_INF)
   OR (fDiamCoreMm <> fDiamCoreMm) OR (ABS(fDiamCoreMm) > DL_SRT_INF)
   OR (fTensionFullN <> fTensionFullN) OR (ABS(fTensionFullN) > DL_SRT_INF)
   OR (fTaperPct <> fTaperPct) OR (ABS(fTaperPct) > DL_SRT_INF)
   OR (fTensionBreakN <> fTensionBreakN) OR (ABS(fTensionBreakN) > DL_SRT_INF)
   OR (fTensionOverN <> fTensionOverN) OR (ABS(fTensionOverN) > DL_SRT_INF)
   OR (fTrimGainPctPerN <> fTrimGainPctPerN) OR (ABS(fTrimGainPctPerN) > DL_SRT_INF)
   OR (fLateralPosMm <> fLateralPosMm) OR (ABS(fLateralPosMm) > DL_SRT_INF)
   OR (fLateralLimitMm <> fLateralLimitMm) OR (ABS(fLateralLimitMm) > DL_SRT_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fDiamFullMm <= (fDiamCoreMm + DL_SRT_EPS))
   OR (fDiamCoreMm < DL_SRT_ZERO) OR (fTensionFullN <= DL_SRT_EPS)
   OR (fTaperPct < DL_SRT_ZERO) OR (fTaperPct > 100.0)
   OR (fTensionBreakN <= DL_SRT_EPS) OR (fTensionOverN <= fTensionBreakN)
   OR (fLateralLimitMm <= DL_SRT_EPS) OR (tTripDebounce <= T#0MS)) THEN
    _bCfgBad := TRUE;                    // 卷径/张力/锥度/限位/时间窗域非法锁存（含 R100 双端判据：超限阈 > 断带阈） / Diameter, tension, taper, limit and window domains latched
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜去抖计时无条件刷新（R40：CASE 之外每拍必调）
 *      Trip debounce timer refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbTrip(IN := (_eState = E_DL_RibbonTenState.eRun) AND bRunning
            AND ((fTensionMeasN < fTensionBreakN) OR (fTensionMeasN > fTensionOverN)),
       PT := tTripDebounce);             // 断带/超限去抖窗（双端判据任一） / Trip debounce window, either end

(*------------------------------------------------------------------------------
 * 段 5｜相位机与锥度/修调链（CASE 含 ELSE 兜底）
 *      Phase machine with the taper and trim chain
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_RibbonTenState.eIdle:             // 空闲：使能且组态合法进运行
        IF bEnable AND (NOT _bCfgBad) THEN
            _eState := E_DL_RibbonTenState.eRun; // 进运行 / To run
        ELSIF bEnable AND _bCfgBad THEN
            _eState := E_DL_RibbonTenState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_RibbonTenState.eRun:              // 运行：锥度设定 + 比例修调 + 双端判据
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_RibbonTenState.eFault; // 异常转故障 / Anomaly, fault
        ELSIF fbTrip.Q THEN
            _bTripL := TRUE;               // 断带/超限锁存（拍 N 进入） / Break or over-limit latched
            _eState := E_DL_RibbonTenState.eTrip; // 本拍转出：进跳闸态 / To trip
        ELSE
            _fSpanMm := fDiamFullMm - fDiamCoreMm; // 卷径跨度 [毫米]，组态闸已保证 > 0 / Diameter span, gated positive
            _fDiaUse := MIN(MAX(fDiamNowMm, fDiamCoreMm), fDiamFullMm); // 卷径域内钳位（换卷瞬态照算） / Diameter clamped into the domain
            fTensionSpN := fTensionFullN * (1.0 - (fTaperPct / 100.0)
                          * (_fDiaUse - fDiamCoreMm) / _fSpanMm); // 锥度张力设定 [牛]，分母已闸 / Tapered setpoint, denominator gated
            fTrimPct := MIN(MAX(fTrimGainPctPerN * (fTensionSpN - fTensionMeasN),
                          -DL_SRT_TRIMMAX), DL_SRT_TRIMMAX); // 比例修调 [百分数]，双侧满幅钳位 / Proportional trim, clamped both sides
            IF ABS(fTensionMeasN - fTensionSpN) > (0.2 * fTensionSpN) THEN
                _bInfoBand := TRUE;        // 张力偏差进入预警带（±20% 设定，信息级） / Tension in the warning band, info
            END_IF
        END_IF

    E_DL_RibbonTenState.eTrip:             // 跳闸：修调撤零保持，bReset 才解除
        IF bReset AND (NOT _bCfgBad) THEN
            _bTripL := FALSE;              // 复位清跳闸锁存 / Reset clears the trip latch
            _eState := E_DL_RibbonTenState.eRun; // 回运行 / Back to run
        END_IF

    E_DL_RibbonTenState.eFault:            // 故障：复位沿且组态恢复回空闲
        IF bReset AND (NOT _bCfgBad) THEN
            _eState := E_DL_RibbonTenState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        fTrimPct := DL_SRT_ZERO;           // 修调撤零（安全侧） / Trim cleared, safe side
        _eState := E_DL_RibbonTenState.eFault; // 回故障态 / Back to fault
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜横动行程窗口（任一使能态均监视，与张力链并行）
 *      Lateral travel window, monitored in parallel
 *-----------------------------------------------------------------------------*)
IF bEnable AND (NOT _bCfgBad) THEN
    bLateralBlock := ABS(fLateralPosMm) >= fLateralLimitMm; // 行程限位封锁电平 / Limit-block level
    IF ABS(fLateralPosMm) >= (DL_SRT_LATWARN * fLateralLimitMm) THEN
        _bInfoLat := TRUE;                 // 接近限位预警带（信息级） / Near-limit warning, info
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0004_0308;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bTripL THEN
    eErr   := 16#0004_0307;                // 故障级：断带/超限锁存 / Fault: break or over-limit latched
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0004_0306;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoLat THEN
    eErr := 16#0004_01E8;                  // 信息级：横动接近限位预警带 / Info: lateral near the limit
ELSIF _bInfoBand THEN
    eErr := 16#0004_01E7;                  // 信息级：张力偏差预警带 / Info: tension warning band
END_IF

IF bError OR _bTripL THEN
    fTrimPct := DL_SRT_ZERO;               // 故障/跳闸路径修调强制撤零（R72 显式安全侧） / Fault and trip paths force the trim to zero
END_IF
bValid := (NOT bError) AND bEnable AND (_eState = E_DL_RibbonTenState.eRun); // 仅运行态放行 / Usable only in the run phase
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
