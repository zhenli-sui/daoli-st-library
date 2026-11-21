//==============================================================================
// 功能块：FB_DL_TankDosingMulti ｜ 中文名称：多罐轮流定量投加
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：多罐（2~4 罐）轮流定量投加——轮值指针在可用罐间循环推进
//           （跳过不可用罐，最多探测罐数轮次；全部不可用 → 可用罐枯竭
//           故障），选中罐后以「启动基线 + 目标增量」监视投加（秤读数
//           增量达目标 → 稳定窗 → 完成），单罐定量超时（无进展）→
//           称重异常锁存。完成拍推进轮值指针，下一启动自动切换下一罐
//           （罐切换信息级提示）。秤读数在投加执行期回退超容差 → 归入
//           称重异常（与 FB_DL_ElectrolyteDosingSeq 同判据口径）。
// 开源溯源 (Origin)：道莅原创实现（参考 ISA-88 相-步骤语义与多罐定量投加工程惯例 分类与参数域）
// 单位表：质量[克] / 占比[倍] / 时间[ms] / 罐号[罐] / 计数[次]
// 错误码表：16#0005_01F8 信息级（罐切换提示：轮值指针推进到下一罐，不置
//           bError）/ 16#0005_01F9 信息级（定量完成提示，不置 bError）/
//           16#0005_0339 故障级（组态非法：罐数域外、目标量 <= 0、稳定
//           窗/超时窗 <= 0 或任一输入非有限，置 bError）/ 16#0005_033A
//           故障级（称重异常/可用罐枯竭：投加期秤回退超容差、定量超时
//           无进展或轮值探测满轮次无可用罐，置 bError——该场景不可由
//           0339 的组态类判据观测，属秤数据与轮值运行独立域）/
//           16#0005_033B 故障级兜底（状态机落 ELSE，置 bError 并全输出断）
// 状态机：E_DL_TankDosingPhase（六态：eIdle=0 / ePick=10 / eDosing=20 /
//           eStable=30 / eDone=40 / eFault=99），CASE 含 ELSE 兜底，
//           ELSE 置 033B 并全输出断
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 可用罐枯竭 →
//           故障 033A，bAbort 或复位后重探测；③ 启动拍锁定基线；④
//           秤回退（比上拍小超容差，投加执行期）→ 故障 033A；⑤ 中止
//           两段化：阀先断、泵惰转窗后关（xCoastAbort 语义同
//           FB_DL_ElectrolyteDosingSeq）；⑥ eDone 等启动撤销推进轮值
//           回空闲（同拍重启防抖，R39 范式）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §510）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_TankDosingPhase（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 多罐投加相位。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_TankDosingPhase :
(
    eIdle   := 0,   // 空闲：等启动 / Idle, awaiting start
    ePick   := 10,  // 选罐：轮值探测可用罐 / Pick, round-robin probing for an available tank
    eDosing := 20,  // 投加：阀开监视增量 / Dosing, valve open, delta monitoring
    eStable := 30,  // 稳定：秤读数稳定窗 / Stable, scale stability window
    eDone   := 40,  // 完成：放行，等启动撤销推进轮值 / Done, awaiting start drop to advance the cursor
    eFault  := 99   // 故障：组态/称重/枯竭/非法状态 / Fault, config, weighing, exhaustion or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_TankDosingMulti
VAR_INPUT
    bStart      : BOOL;                     // 启动请求 [—]，上升沿生效 / Start request, rising edge
    bAbort      : BOOL;                     // 中止请求 [—]，任意拍生效 / Abort request, effective on any scan
    bReset      : BOOL;                     // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    nTankCount  : USINT;                    // 罐数 [罐]，有效域 2..4 / Tank count [tanks], valid range 2..4
    afTankAvail : ARRAY[0..3] OF BOOL;      // 各罐可用 [—]（false = 备用/故障罐跳过） / Tank availability flags
    afScaleG    : ARRAY[0..3] OF LREAL;     // 各罐秤读数 [克]（投加目标侧） / Per-tank scale readings [g], target side
    fTargetG    : LREAL := 1000.0;          // 单罐目标量 [克]，须 > 0 / Per-tank target mass [g], must be > 0
    tSettleTime : TIME  := T#2S;            // 稳定窗 [ms]，须 > 0 / Stability window [ms]
    tDoseTimeout: TIME  := T#120S;          // 单罐定量超时窗 [ms]，须 > 稳定窗（R100 配比） / Dose timeout window [ms], must exceed the stability window
    fScaleTolG  : LREAL := 0.5;             // 秤稳定/回退容差 [克] / Scale stability and regression tolerance [g]
END_VAR
VAR_OUTPUT
    ePhase    : E_DL_TankDosingPhase;      // 投加相位 [—] / Dosing phase
    nActiveTank: USINT;                    // 当前投加罐号 [罐]，0 基 / Active tank index, zero-based
    fDosedG   : LREAL;                     // 已投量 [克] = 读数 - 基线 / Dosed mass [g] = reading minus baseline
    bDosingOut: BOOL;                      // 投加阀输出 [—] / Dosing valve output
    eErr      : UDINT;                     // 错误码，0 = 无错，码位 16#0005_01F8 起信息级、16#0005_0339 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError    : BOOL;                      // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid    : BOOL;                      // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbStable  : TON;                       // 稳定窗计时（每拍无条件刷新）[ms] / Stability window timer, refreshed unconditionally
    fbTimeout : TON;                       // 定量超时计时（每拍无条件刷新）[ms] / Dose timeout timer, refreshed unconditionally
    fbStart   : R_TRIG;                     // 启动沿检测（待机/故障分支同样无条件刷新） / Start edge detector, refreshed unconditionally
    _ePhase   : E_DL_TankDosingPhase := E_DL_TankDosingPhase.eIdle; // 当前相位 / Current phase
    _bCfgBad  : BOOL;                      // 组态非法锁存 / Illegal config latch
    _bWeighBad: BOOL;                      // 称重异常锁存 / Weighing fault latch
    _bNoTank  : BOOL;                      // 可用罐枯竭锁存 / Tank-exhaustion latch
    _nCursor  : USINT;                     // 轮值指针 [罐]，0 基 / Round-robin cursor, zero-based
    _nProbe   : USINT;                     // 本轮探测计数 [次] / Probe count of this round [count]
    _nTankUse : UINT;                      // 罐数 UINT 副本 [罐]（域闸后转换安全） / UINT copy of the tank count
    _fBaseG   : LREAL;                     // 投加基线 [克]，启动拍锁定 / Baseline mass [g], locked at start
    _fScalePrevG: LREAL;                   // 上拍秤读数快照 [克] / Previous-scan scale snapshot [g]
    _bInfoSwitch: BOOL;                    // 罐切换信息当拍标志 / Tank-switch info flag of this scan
    _bInfoDone: BOOL;                      // 完成信息当拍标志 / Done info flag of this scan
    _bIllegal : BOOL;                      // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;             // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_TDM_INF    : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_TDM_TANK_MAX: UINT := 4;            // 罐数上限 [罐] / Tank count ceiling [tanks]
    DL_TDM_TANK_MIN: UINT := 2;            // 罐数下限 [罐] / Tank count floor [tanks]
    DL_TDM_ZERO   : LREAL := 0.0;          // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
    DL_TDM_NO_TANK: USINT := 255;          // 无效罐号哨兵 [罐] / Invalid-tank sentinel [tanks]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：阀输出先断（安全侧），单拍标志预清零
 *      Valve cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bDosingOut := FALSE;                     // 投加阀先断（安全侧） / Valve cleared first
fDosedG    := DL_TDM_ZERO;               // 已投量每拍重算 / Dosed mass recomputed
nActiveTank := DL_TDM_NO_TANK;           // 罐号出口先置哨兵（有效态在段 4 重置） / Tank outlet preset to the sentinel
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoSwitch := FALSE;                   // 切换信息预清零 / Switch info pre-cleared
_bInfoDone   := FALSE;                   // 完成信息预清零 / Done info pre-cleared
_bIllegal    := FALSE;                   // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _ePhase   := E_DL_TankDosingPhase.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad  := FALSE;                  // 组态锁存清零 / Config latch cleared
    _bWeighBad := FALSE;                 // 称重锁存清零 / Weighing latch cleared
    _bNoTank  := FALSE;                  // 枯竭锁存清零 / Exhaustion latch cleared
    _nCursor  := 0;                      // 轮值指针从 0 起步 / Cursor starts at zero
    _fScalePrevG := DL_TDM_ZERO;         // 秤快照从零起步 / Scale snapshot starts at zero
    _bInit    := TRUE;                   // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态闸 + 沿/计时无条件刷新（R40：CASE 之外每拍必调）
 *      Config gate plus unconditional refresh per R40
 *-----------------------------------------------------------------------------*)
fbStart(CLK := bStart);                  // 启动沿检测 / Start edge detection
IF (afScaleG[0] <> afScaleG[0]) OR (ABS(afScaleG[0]) > DL_TDM_INF)
   OR (afScaleG[1] <> afScaleG[1]) OR (ABS(afScaleG[1]) > DL_TDM_INF)
   OR (afScaleG[2] <> afScaleG[2]) OR (ABS(afScaleG[2]) > DL_TDM_INF)
   OR (afScaleG[3] <> afScaleG[3]) OR (ABS(afScaleG[3]) > DL_TDM_INF)
   OR (fTargetG <> fTargetG) OR (ABS(fTargetG) > DL_TDM_INF)
   OR (fScaleTolG <> fScaleTolG) OR (ABS(fScaleTolG) > DL_TDM_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
_nTankUse := UINT(nTankCount);           // 罐数副本（窄类型升位复制，R55） / UINT copy of the count, widened per R55
IF (_nTankUse < DL_TDM_TANK_MIN) OR (_nTankUse > DL_TDM_TANK_MAX)
   OR (fTargetG <= DL_TDM_ZERO) OR (fScaleTolG <= DL_TDM_ZERO)
   OR (tSettleTime <= T#0MS) OR (tDoseTimeout <= tSettleTime) THEN
    _bCfgBad := TRUE;                    // 罐数/目标量/容差/时间窗域非法锁存（含 R100 配比：超时窗 > 稳定窗） / Count, target, tolerance and window domains latched
END_IF
IF bReset THEN
    _bCfgBad   := FALSE;                 // 复位清组态锁存 / Reset clears the config latch
    _bWeighBad := FALSE;                 // 复位清称重锁存 / Reset clears the weighing latch
    _bNoTank   := FALSE;                 // 复位清枯竭锁存 / Reset clears the exhaustion latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜双计时无条件刷新（R40：CASE 之外每拍必调）
 *      Two timers refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbStable(IN := (_ePhase = E_DL_TankDosingPhase.eStable), PT := tSettleTime); // 稳定窗 / Stability window
fbTimeout(IN := (_ePhase = E_DL_TankDosingPhase.eDosing), PT := tDoseTimeout); // 定量超时窗 / Dose timeout window

(*------------------------------------------------------------------------------
 * 段 5｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF

    E_DL_TankDosingPhase.eIdle:            // 空闲：启动沿且组态合法进选罐
        IF fbStart.Q AND (NOT _bCfgBad) AND (NOT _bNoTank) THEN
            _nProbe := 0;                  // 本轮探测计数清零 / Probe count reset
            _ePhase := E_DL_TankDosingPhase.ePick; // 进选罐 / To pick
        ELSIF fbStart.Q AND (_bCfgBad OR _bNoTank) THEN
            _ePhase := E_DL_TankDosingPhase.eFault; // 组态非法或枯竭进故障 / Illegal config or exhaustion to fault
        END_IF

    E_DL_TankDosingPhase.ePick:            // 选罐：轮值探测（最多罐数轮次）
        IF _bCfgBad OR bAbort THEN
            _ePhase := E_DL_TankDosingPhase.eFault; // 异常转故障 / Anomaly, fault
        ELSIF (_nTankUse > 0) AND afTankAvail[_nCursor] THEN
            nActiveTank := _nCursor;       // 选中罐号出口 / Active tank outlet
            _fBaseG := afScaleG[_nCursor]; // 基线锁定 / Baseline locked
            _fScalePrevG := afScaleG[_nCursor]; // 秤快照同步 / Scale snapshot synced
            _ePhase := E_DL_TankDosingPhase.eDosing; // 进投加 / To dosing
        ELSE
            _nCursor := USINT((_nCursor + 1) MOD UINT_TO_USINT(_nTankUse)); // 轮值推进（模罐数，归一安全） / Cursor advance, modulo-normalised
            _nProbe := _nProbe + 1;        // 探测计数推进 / Probe count advanced
            IF _nProbe >= _nTankUse THEN
                _bNoTank := TRUE;          // 探测满轮次无可用罐（拍 N 进入） / Full round probed without an available tank
                _ePhase := E_DL_TankDosingPhase.eFault; // 本拍转出：进故障 / To fault
            END_IF
        END_IF

    E_DL_TankDosingPhase.eDosing:          // 投加：增量监视 + 回退检测 + 超时判
        IF (_bCfgBad OR bAbort) THEN
            _ePhase := E_DL_TankDosingPhase.eFault; // 异常转故障 / Anomaly, fault
        ELSE
            nActiveTank := _nCursor;       // 罐号出口保持 / Tank outlet held
            fDosedG := afScaleG[_nCursor] - _fBaseG; // 已投量 [克] / Dosed mass [g]
            IF fDosedG < DL_TDM_ZERO THEN
                fDosedG := DL_TDM_ZERO;    // 负增量钳 0（换批/去皮期） / Negative delta clamped to zero
            END_IF
            IF afScaleG[_nCursor] <> afScaleG[_nCursor] THEN
                _bWeighBad := TRUE;        // 秤读数非有限归称重异常（R90 复用） / Non-finite scale folded into the weighing fault
            ELSIF afScaleG[_nCursor] < (_fScalePrevG - fScaleTolG) THEN
                _bWeighBad := TRUE;        // 秤回退超容差锁存 / Scale regression latched
            ELSIF fbTimeout.Q THEN
                _bWeighBad := TRUE;        // 定量超时无进展归称重异常域 / Dose timeout folded into the weighing fault
            ELSIF fDosedG >= fTargetG THEN
                _ePhase := E_DL_TankDosingPhase.eStable; // 达目标进稳定窗 / Target reached, to stable
            END_IF
        END_IF
        _fScalePrevG := afScaleG[_nCursor]; // 快照推进 / Snapshot advanced

    E_DL_TankDosingPhase.eStable:          // 稳定：稳定窗满进完成
        IF _bCfgBad OR bAbort THEN
            _ePhase := E_DL_TankDosingPhase.eFault; // 异常转故障 / Anomaly, fault
        ELSIF fbStable.Q THEN
            _bInfoDone := TRUE;            // 定量完成（信息级，拍 N 进入） / Dosing done, info
            _ePhase := E_DL_TankDosingPhase.eDone; // 本拍转出：进完成 / To done
        END_IF

    E_DL_TankDosingPhase.eDone:            // 完成：等启动撤销推进轮值回空闲
        IF NOT bStart THEN
            _nCursor := USINT((_nCursor + 1) MOD UINT_TO_USINT(_nTankUse)); // 轮值推进（下一启动自动换罐） / Cursor advance, next start switches tanks
            _bInfoSwitch := TRUE;          // 罐切换提示（信息级，拍 N 进入） / Tank-switch notice, info
            _ePhase := E_DL_TankDosingPhase.eIdle; // 本拍转出：回空闲 / Back to idle
        END_IF

    E_DL_TankDosingPhase.eFault:           // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bCfgBad) AND (NOT _bWeighBad) AND (NOT _bNoTank) THEN
            _ePhase := E_DL_TankDosingPhase.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        bDosingOut := FALSE;               // 全输出断 / All outputs off
        _ePhase := E_DL_TankDosingPhase.eFault; // 回故障态 / Back to fault
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜输出置位与码位出口（故障级码 3 行内置 bError，R45/R101 配对）
 *      Output assignment and code outlet, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
bDosingOut := (_ePhase = E_DL_TankDosingPhase.eDosing); // 投加阀挂投加态 / Valve bound to the dosing phase

IF _bIllegal THEN
    eErr   := 16#0005_033B;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bNoTank THEN
    eErr   := 16#0005_033A;                // 故障级：可用罐枯竭 / Fault: tank exhaustion
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bWeighBad THEN
    eErr   := 16#0005_033A;                // 故障级：称重异常（回退/超时/非有限同域，R90） / Fault: weighing fault, code shared per R90
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0005_0339;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoSwitch THEN
    eErr := 16#0005_01F8;                  // 信息级：罐切换提示 / Info: tank switch
ELSIF _bInfoDone THEN
    eErr := 16#0005_01F9;                  // 信息级：定量完成 / Info: dosing done
END_IF

bValid := (NOT bError) AND (_ePhase <> E_DL_TankDosingPhase.eIdle)
          AND (_ePhase <> E_DL_TankDosingPhase.eFault); // 空闲/故障输出不可用 / Outputs unusable in idle or fault
ePhase := _ePhase;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
