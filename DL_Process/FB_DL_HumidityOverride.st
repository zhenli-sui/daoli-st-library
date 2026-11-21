//==============================================================================
// 功能块：FB_DL_HumidityOverride ｜ 中文名称：除湿优先模式仲裁
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：湿度越限覆盖温度控制优先级仲裁——湿度达覆盖触发阈值经确认窗
//           进入覆盖态（除湿优先），回落至释放阈值经确认窗退出（迟滞回差
//           防抖振）；覆盖生效期间温度设定值调整由调用方处理（本件只仲裁
//           不写设定值，职责边界声明）。
// 开源溯源 (Origin)：道莅原创实现（参考洁净室/暖通除湿优先控制工程惯例 分类与参数域）
// 单位表：RH[%] / 阈值[%] / 确认窗[ms]
// 错误码表：16#0005_01EE 信息级（覆盖状态切换沿提示，不置 bError）/
//           16#0005_01EF 预留禁用（不得挪用）/ 16#0005_032A 故障级（迟滞
//           倒置 fRhReleasePct >= fRhOverridePct，或湿度非有限转故障态退出覆盖并按 01EE 切换沿显式声明，
//           置 bError）/ 16#0005_032B 预留禁用（不得挪用）/ 16#0005_032C
//           故障级兜底（状态机落 ELSE，置 bError）
// 状态机：E_DL_HumOverrideState（四态：eNormal=0 / eOverride=10 /
//           eReleasePending=20 / eFault=99），CASE 含 ELSE 兜底，ELSE 置
//           032C 并保持末态输出侧安全
// 边界行为：① fRhReleasePct >= fRhOverridePct → 故障 032A（迟滞倒置）；
//           ② 湿度非有限 → 故障 032A 复用（R90）：转故障态退出覆盖，进
//           故障沿 01EE 切换沿显式声明（实现口径：退出非静默——bError
//           与切换沿双通道通知，调用方凭故障做工艺侧处置）；③ 触发/释放均带
//           tConfirmDelay 确认窗（防抖振）；④ 覆盖生效期间温度设定值由
//           调用方处理（本件只仲裁不写设定值，头注释职责边界声明）；
//           ⑤ 切换沿信息 01EE 单发（只置必销）。
// 依赖纪律：仅 Standard.library；零跨层调用。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 暖通 P1 §297）
//           v1.0.1 2026-11-17 R23 终审修复（仅注释对齐，逻辑零改动）：原文
//           「非有限保持末态」与实现不符——实现为转故障态退出覆盖且以
//           01EE 切换沿显式声明（进故障沿即置 _bSwEdge），注释按实现口径
//           对齐；保持/退出语义的工艺裁定随 ROADMAP P1 复核。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_HumOverrideState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 除湿优先仲裁相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_HumOverrideState :
(
    eNormal         := 0,   // 正常：温控优先 / Normal, temperature control has priority
    eOverride       := 10,  // 覆盖：除湿优先生效 / Override, dehumidification has priority
    eReleasePending := 20,  // 释放待确认：湿度已回落，等确认窗 / Release pending, humidity recovered, awaiting the window
    eFault          := 99   // 故障：迟滞倒置/非有限/非法状态 / Fault, inversion, non-finite or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_HumidityOverride
VAR_INPUT
    fRhPct         : LREAL;                 // 实测湿度 [百分数RH] / Measured humidity [%RH]
    fRhOverridePct : LREAL := 70.0;         // 覆盖触发阈值 [百分数RH] / Override trigger threshold [%RH]
    fRhReleasePct  : LREAL := 60.0;         // 释放阈值 [百分数RH]，须 < 触发阈值 / Release threshold [%RH], must be below the trigger
    bTempCtrlActive: BOOL;                  // 温控在投 [—]（诊断参考，不参与仲裁） / Temperature control active, diagnostic reference only
    tConfirmDelay  : TIME  := T#30S;        // 触发/释放确认窗 [ms] / Trigger and release confirm window [ms]
    bReset         : BOOL;                  // 故障复位 [—] / Fault reset
END_VAR
VAR_OUTPUT
    bOverrideActive: BOOL;                  // 除湿优先生效 [—] / Dehumidification priority active
    eOverrideState : E_DL_HumOverrideState; // 仲裁相位 [—] / Arbitration phase
    eErr           : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = no error
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbTrigWin      : TON;                   // 覆盖触发确认窗，段 6 无条件刷新 [ms] / Trigger confirm window
    fbReleaseWin   : TON;                   // 释放确认窗，段 6 无条件刷新 [ms] / Release confirm window
    _eState        : E_DL_HumOverrideState := E_DL_HumOverrideState.eNormal; // 当前相位 / Current phase
    _bInit         : BOOL := FALSE;         // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bHystBad      : BOOL;                  // 迟滞倒置/非有限锁存 / Inversion or non-finite latch
    _bSwEdge       : BOOL;                  // 切换沿单拍标志 / One-scan switch edge flag
    _bIllegal      : BOOL;                  // 非法状态标志 / Illegal state flag
END_VAR
VAR CONSTANT
    DL_HO_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出先算后出，单拍标志预清零（只置必销）
 *      Outputs computed per scan, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bOverrideActive := FALSE;                   // 覆盖输出每拍重算 / Override output recomputed
eErr            := 16#0000_0000;            // 错误码每拍重算 / Error code recomputed
bError          := FALSE;                   // 故障标志每拍重算 / Fault flag recomputed
bValid          := FALSE;                   // 可用标志每拍重算 / Usable flag recomputed
_bSwEdge        := FALSE;                   // 切换沿预清零 / Switch edge pre-cleared
_bIllegal       := FALSE;                   // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState   := E_DL_HumOverrideState.eNormal; // 相位正常起步 / Phase starts normal
    _bHystBad := FALSE;                     // 迟滞锁存清零 / Hysteresis latch cleared
    _bInit    := TRUE;                      // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与输入防御闸（迟滞倒置 / 湿度非有限 → 032A，保持末态）
 *      Configuration and input defense gates, last state held
 *-----------------------------------------------------------------------------*)
IF (fRhOverridePct <> fRhOverridePct) OR (ABS(fRhOverridePct) > DL_HO_INF)
   OR (fRhReleasePct <> fRhReleasePct) OR (ABS(fRhReleasePct) > DL_HO_INF) THEN
    _bHystBad := TRUE;                      // 阈值非有限归入迟滞倒置（R90） / Non-finite thresholds folded into the inversion fault
END_IF
IF (fRhPct <> fRhPct) OR (ABS(fRhPct) > DL_HO_INF) THEN
    _bHystBad := TRUE;                      // 湿度非有限：转故障态（退出覆盖由切换沿 01EE 显式声明） / Non-finite humidity, to fault, exit declared via the switch edge
END_IF
IF (NOT _bHystBad) AND (fRhReleasePct >= fRhOverridePct) THEN
    _bHystBad := TRUE;                      // 迟滞倒置锁存 / Inversion latched
END_IF
IF bReset THEN
    _bHystBad := FALSE;                     // 复位清锁存 / Reset clears the latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜双确认窗无条件刷新（R40：CASE 之外每拍必调，各司其职不复用）
 *      Both confirm windows refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbTrigWin(IN := (NOT _bHystBad) AND (_eState = E_DL_HumOverrideState.eNormal)
              AND (fRhPct >= fRhOverridePct), PT := tConfirmDelay); // 覆盖触发确认窗 / Trigger confirm window
fbReleaseWin(IN := (NOT _bHystBad) AND (_eState = E_DL_HumOverrideState.eReleasePending)
                 AND (fRhPct <= fRhReleasePct), PT := tConfirmDelay); // 释放确认窗 / Release confirm window

(*------------------------------------------------------------------------------
 * 段 5｜相位机（只做迁移；输出在段 6 按相置位）
 *      Phase machine, transitions only, outputs assigned in segment six
 *-----------------------------------------------------------------------------*)
IF _bHystBad THEN
    IF _eState <> E_DL_HumOverrideState.eFault THEN
        _bSwEdge := TRUE;                   // 进故障也按切换沿声明（画面提示） / Entering fault declared as a switch edge
    END_IF
    _eState := E_DL_HumOverrideState.eFault; // 异常转故障（保持末态由输出段承担） / Anomaly to fault
ELSE
CASE _eState OF

    E_DL_HumOverrideState.eNormal:         // 正常：触发确认窗满进覆盖
        IF fbTrigWin.Q THEN
            _bSwEdge := TRUE;               // 切换沿单发 / Switch edge one-shot
            _eState  := E_DL_HumOverrideState.eOverride; // 进覆盖 / To override
        END_IF

    E_DL_HumOverrideState.eOverride:       // 覆盖：湿度回落至释放阈进待确认
        IF fRhPct <= fRhReleasePct THEN
            _eState := E_DL_HumOverrideState.eReleasePending; // 进释放待确认 / To release pending
        END_IF

    E_DL_HumOverrideState.eReleasePending: // 释放待确认：确认窗满回正常；回弹超触发阈返覆盖
        IF fbReleaseWin.Q THEN
            _bSwEdge := TRUE;               // 切换沿单发 / Switch edge one-shot
            _eState  := E_DL_HumOverrideState.eNormal; // 回正常 / Back to normal
        ELSIF fRhPct >= fRhOverridePct THEN
            _eState := E_DL_HumOverrideState.eOverride; // 湿度回弹，返覆盖（窗自然断） / Humidity rebounded, back to override
        END_IF

    E_DL_HumOverrideState.eFault:          // 故障：复位沿且原因消失回正常
        IF bReset AND (NOT _bHystBad) THEN
            _eState := E_DL_HumOverrideState.eNormal; // 回正常 / Back to normal
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_HumOverrideState.eFault; // 回故障态 / Back to fault
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜输出置位与码位出口（职责边界：本件只仲裁，不写温度设定值）
 *      Output assignment and codes, arbitration only, no setpoint writes
 *-----------------------------------------------------------------------------*)
bOverrideActive := (_eState = E_DL_HumOverrideState.eOverride)
                OR (_eState = E_DL_HumOverrideState.eReleasePending); // 覆盖态与待确认期均视为生效 / Active in override and pending
eOverrideState := _eState;                  // 相位出口 / Phase outlet

IF _bIllegal THEN
    eErr   := 16#0005_032C;                 // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bHystBad THEN
    eErr   := 16#0005_032A;                 // 故障级：迟滞倒置或湿度非有限（R90 复用） / Fault: inversion or non-finite, code reused
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
ELSIF _bSwEdge THEN
    eErr := 16#0005_01EE;                   // 信息级：覆盖状态切换沿 / Info: override switch edge
    bValid := TRUE;                         // 输出可用 / Outputs usable
ELSE
    bValid := TRUE;                         // 输出可用 / Outputs usable
END_IF
END_FUNCTION_BLOCK
