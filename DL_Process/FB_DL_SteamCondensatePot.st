//==============================================================================
// 功能块：FB_DL_SteamCondensatePot ｜ 中文名称：凝液罐液位-排放顺控
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：凝液罐液位双限排放顺控——液位达排放启位开排水阀、降至停位
//           关阀（迟滞对），单次排放限时保护（超时液位未降判排放堵塞），
//           排放计数累计。
// 开源溯源 (Origin)：道莅原创实现（参考蒸汽凝液回收系统工程惯例 分类与参数域）
// 单位表：液位[%] / 阈值[%] / 时间[ms] / 计数[次]
// 错误码表：16#0005_01E8 信息级（液位域外已钳位 0~100，不置 bError）/
//           16#0005_01E9 预留禁用（不得挪用）/ 16#0005_0321 故障级（迟滞
//           倒置：停位 >= 启位，组态非法，置 bError）/ 16#0005_0322 故障级
//           （排放超时液位未降，判排放堵塞，关阀，置 bError）/
//           16#0005_0323 故障级兜底（状态机落 ELSE，置 bError）
// 状态机：E_DL_CondPotState（五态：eIdle=0 / eDraining=10 / eTimeout=20 /
//           eReady=30 / eFault=99），CASE 含 ELSE 兜底，ELSE 置 0323 并关阀
// 边界行为：① fPumpLevelLoPct >= fPumpLevelHiPct → 故障 0321（迟滞倒置）；
//           ② 排放超 tDrainMax 液位未降 → 故障 0322 + 关阀（转 eTimeout，
//           bReset 或液位回落解除）；③ 液位域外钳 0~100 + 信息 01E8；
//           ④ 排放计数饱和 4294967295 不回绕；⑤ 液位非有限 → 故障 0321
//           复用（R90，安全侧关阀）。
// 依赖纪律：仅 Standard.library；零跨层调用。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 公用工程 P1 §392）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_CondPotState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 凝液罐排放相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_CondPotState :
(
    eIdle     := 0,   // 空闲：等使能 / Idle, awaiting enable
    eReady    := 10,  // 就绪：液位低于启位，等排放条件 / Ready, level below the start threshold
    eDraining := 20,  // 排放中：排水阀开，等液位降至停位 / Draining, valve open, waiting for the stop level
    eTimeout  := 30,  // 排放超时：判堵塞，阀已关，等解除 / Drain timeout, clog suspected, valve closed
    eFault    := 99   // 故障：组态非法/非有限/非法状态 / Fault, illegal config, non-finite or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_SteamCondensatePot
VAR_INPUT
    fLevelPct        : LREAL;             // 液位实测 [百分数]，有效域 0..100，域外钳位 / Measured level [percent], 0..100, clamped outside
    fPumpLevelHiPct  : LREAL := 80.0;     // 排放启位液位 [百分数] / Drain-start level [percent]
    fPumpLevelLoPct  : LREAL := 30.0;     // 排放停位液位 [百分数]，须 < 启位 / Drain-stop level [percent], must be below the start
    bDrainValveFb    : BOOL;              // 排水阀开反馈 [—] / Drain valve open feedback
    tDrainMax        : TIME  := T#30S;    // 单次排放上限 [ms] / Single-drain ceiling [ms]
    bEnable          : BOOL;              // 使能 [—] / Enable
    bReset           : BOOL;              // 故障复位 [—]，清除超时态 / Fault reset, clears the timeout state
END_VAR
VAR_OUTPUT
    bDrainOut        : BOOL;              // 排水阀输出 [—] / Drain valve output
    ePotState        : E_DL_CondPotState; // 排放相位 [—] / Drain phase
    uDrainCount      : UDINT;             // 排放计数 [次]，饱和不回绕 / Drain counter [count], saturated without wrap
    eErr             : UDINT;             // 错误码，0 = 无错 / Error code, 0 = no error
    bError           : BOOL;              // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid           : BOOL;              // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbDrainMax       : TON;               // 单次排放限时计时，段 6 无条件刷新 [ms] / Single-drain timer
    _eState          : E_DL_CondPotState := E_DL_CondPotState.eIdle; // 当前相位 / Current phase
    _fLevelEff       : LREAL;             // 钳位后的生效液位 [百分数] / Effective clamped level [percent]
    _bInit           : BOOL := FALSE;     // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bHystBad        : BOOL;              // 迟滞倒置/非有限锁存 / Hysteresis inversion or non-finite latch
    _bLevelInfo      : BOOL;              // 液位钳位信息当拍标志 / Level clamp info flag of this scan
    _bIllegal        : BOOL;              // 非法状态标志 / Illegal state flag
END_VAR
VAR CONSTANT
    DL_POT_INF       : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_POT_LVL_MIN   : LREAL := 0.0;      // 液位钳位下限 [百分数] / Level clamp floor [percent]
    DL_POT_LVL_MAX   : LREAL := 100.0;    // 液位钳位上限 [百分数] / Level clamp ceiling [percent]
    DL_POT_CNT_MAX   : UDINT := 4294967295; // 排放计数饱和上限 [次] / Drain counter saturation ceiling [count]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：阀输出先断（安全侧），单拍标志预清零
 *      Valve output cleared first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bDrainOut := FALSE;                         // 排水阀输出先清（安全侧） / Drain output cleared first
eErr      := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError    := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid    := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bIllegal := FALSE;                         // 非法状态标志预清零 / Illegal flag pre-cleared
_bLevelInfo := FALSE;                       // 钳位信息预清零 / Clamp info pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState   := E_DL_CondPotState.eIdle;   // 相位空闲起步 / Phase starts idle
    uDrainCount := 0;                       // 计数清零 / Counter cleared
    _bHystBad := FALSE;                     // 迟滞锁存清零 / Hysteresis latch cleared
    _bInit    := TRUE;                      // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与输入防御闸（迟滞倒置 / 非有限液位 → 0321 复用，R90）
 *      Configuration and input defense gates, code reused per R90
 *-----------------------------------------------------------------------------*)
IF (fLevelPct <> fLevelPct) OR (ABS(fLevelPct) > DL_POT_INF)
   OR (fPumpLevelHiPct <> fPumpLevelHiPct) OR (ABS(fPumpLevelHiPct) > DL_POT_INF)
   OR (fPumpLevelLoPct <> fPumpLevelLoPct) OR (ABS(fPumpLevelLoPct) > DL_POT_INF) THEN
    _bHystBad := TRUE;                      // 非有限液位/阈值归入迟滞倒置（R90 复用） / Non-finite folded into the inversion fault
END_IF
IF (NOT _bHystBad) AND (fPumpLevelLoPct >= fPumpLevelHiPct) THEN
    _bHystBad := TRUE;                      // 迟滞倒置锁存 / Hysteresis inversion latched
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜液位钳位（域外信息级照算）
 *      Level clamping with an info notice
 *-----------------------------------------------------------------------------*)
IF (NOT _bHystBad) AND ((fLevelPct < DL_POT_LVL_MIN) OR (fLevelPct > DL_POT_LVL_MAX)) THEN
    _fLevelEff := MIN(MAX(fLevelPct, DL_POT_LVL_MIN), DL_POT_LVL_MAX); // 双侧钳位到 0~100 / Two-sided clamp into 0..100
    _bLevelInfo := TRUE;                    // 钳位信息置位 / Clamp info raised
ELSE
    _fLevelEff := fLevelPct;                // 合法液位原值生效 / Valid level applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜排放限时计时无条件刷新（R40：CASE 之外每拍必调）
 *      Drain timer refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbDrainMax(IN := (_eState = E_DL_CondPotState.eDraining) AND bDrainValveFb, PT := tDrainMax); // 排放限时 / Single-drain timer

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；输出在段 7 按相置位）
 *      Phase machine, transitions only, outputs assigned in segment seven
 *-----------------------------------------------------------------------------*)
IF _bHystBad THEN
    _eState := E_DL_CondPotState.eFault;    // 组态/输入异常直接转故障 / Config or input anomaly goes to fault
ELSE
CASE _eState OF

    E_DL_CondPotState.eIdle:               // 空闲：使能即进就绪
        IF bEnable THEN
            _eState := E_DL_CondPotState.eReady; // 进就绪 / To ready
        END_IF

    E_DL_CondPotState.eReady:              // 就绪：液位达启位开排
        IF NOT bEnable THEN
            _eState := E_DL_CondPotState.eIdle; // 撤使能回空闲 / Disabled back to idle
        ELSIF _fLevelEff >= fPumpLevelHiPct THEN
            IF uDrainCount < DL_POT_CNT_MAX THEN
                uDrainCount := uDrainCount + 1; // 排放计数递增（饱和不回绕） / Drain counter increment, saturated
            END_IF
            _eState := E_DL_CondPotState.eDraining; // 进排放 / To draining
        END_IF

    E_DL_CondPotState.eDraining:           // 排放中：降至停位关阀或超时判堵
        IF fbDrainMax.Q AND (_fLevelEff > fPumpLevelLoPct) THEN
            _eState := E_DL_CondPotState.eTimeout; // 超时液位未降，判堵塞 / Timeout without level drop, clog
        ELSIF _fLevelEff <= fPumpLevelLoPct THEN
            _eState := E_DL_CondPotState.eReady; // 降至停位，回就绪（阀在段 7 关） / Level at the stop threshold, back to ready
        ELSIF NOT bEnable THEN
            _eState := E_DL_CondPotState.eIdle; // 撤使能回空闲 / Disabled back to idle
        END_IF

    E_DL_CondPotState.eTimeout:            // 排放超时：等复位或液位自行回落
        IF bReset OR (_fLevelEff <= fPumpLevelLoPct) THEN
            _eState := E_DL_CondPotState.eReady; // 解除回就绪 / Cleared back to ready
        END_IF

    E_DL_CondPotState.eFault:              // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bHystBad) THEN
            _eState := E_DL_CondPotState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_CondPotState.eFault; // 回故障态（阀关） / Back to fault, valve closed
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出置位与码位出口（故障/超时态阀显式关——安全侧）
 *      Output assignment and codes, valve explicitly closed on fault
 *-----------------------------------------------------------------------------*)
bDrainOut := (_eState = E_DL_CondPotState.eDraining) AND bEnable AND (NOT _bHystBad); // 仅排放中且合法时开阀 / Valve open only while draining and legal
ePotState := _eState;                       // 相位出口 / Phase outlet

IF _bIllegal THEN
    eErr   := 16#0005_0323;                 // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bHystBad THEN
    eErr   := 16#0005_0321;                 // 故障级：迟滞倒置或非有限（R90 复用） / Fault: inversion or non-finite, code reused
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _eState = E_DL_CondPotState.eTimeout THEN
    eErr   := 16#0005_0322;                 // 故障级：排放超时判堵塞 / Fault: drain timeout, clog suspected
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bLevelInfo THEN
    eErr := 16#0005_01E8;                   // 信息级：液位域外已钳位 / Info: level clamped
END_IF

bValid := (NOT bError) AND (_eState <> E_DL_CondPotState.eIdle); // 空闲/故障输出不可用 / Outputs unusable in idle or fault
END_FUNCTION_BLOCK
