//==============================================================================
// 功能块：FB_DL_RollCompressForceBalance ｜ 中文名称：辊压机两侧轧制力平衡监视与液压纠偏
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：辊压机两侧轧制力差动平衡——压差 = 左力 - 右力，压差绝对值
//           超窗口（fDiffLimitKn）持续去抖窗 → 差动修调输出（液压比例
//           阀方向修调 fTrimPct，正 = 增左/减右向），修调带增益映射与
//           每拍限速（液压平稳性约束）；修调饱和（满幅）后压差仍持续
//           超窗 tSatTimeout → 判液压侧异常（纠偏能力耗尽），锁存故障；
//           压差回窗口内 → 修调按限速回零。压差进入窗口前给预警带信息
//           提示（供提前干预）。
// 遗留假设（R95 代理阈值三句）：① 代理值 = fCycleTimeS 组态扫描周期
//           [秒]（限速积分基量）；② 覆盖 0.001~0.1 秒任务周期范围；
//           ③ 覆盖不到的区间由调用方按实际任务周期重设该引脚负责，
//           该假设挂编译验证债。同拍多窗配比约束（R100）：
//           tSatTimeout > tDiffDebounce——饱和确认窗必须长于去抖窗，
//           否则压差尚未确认即误判饱和异常。
// 开源溯源 (Origin)：道莅原创实现（参考辊压机轧制力平衡与液压差动纠偏工程惯例 分类与参数域）
// 单位表：轧制力[千牛] / 压差[千牛] / 压差窗[千牛] / 修调[百分数] /
//         修调增益[百分数每千牛] / 限速[百分数每秒] / 时间[ms] / 扫描周期[秒]
// 错误码表：16#0005_01FC 信息级（压差进入预警带：超窗去抖计窗中，不置
//           bError）/ 16#0005_01FD 信息级（修调输出达限幅提示，不置
//           bError）/ 16#0005_033F 故障级（组态非法：压差窗/增益/限速/
//           周期域、时间窗 <= 0 或配比倒置（饱和窗 <= 去抖窗），或任一
//           输入非有限，置 bError）/ 16#0005_0340 故障级（压差持续超窗
//           且纠偏饱和：修调满幅后超窗持续 tSatTimeout，判液压侧异常
//           嫌疑，修调冻结，置 bError——该场景不可由 033F 的组态类判据
//           观测，属液压执行独立域）/ 16#0005_0341 故障级兜底（状态机
//           落 ELSE，置 bError 并撤修调）
// 状态机：E_DL_RollBalanceState（四态：eIdle=0 / eBalance=10 / eFrozen=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 0341 并撤修调
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 修调限速双向
//           （逼近与回零均限速，防液压冲击）；③ 修调饱和后压差回窗 →
//           正常回零路径（饱和不锁存，仅持续超窗才锁存故障）；④ 轧力
//           非有限 → 冻结修调安全侧（数据不可信不动液压）＋ 故障 033F
//           复用（R90：组态类「输入非法」语义扩覆盖）；⑤ 未使能修调
//           撤零并 bValid := FALSE；⑥ 安全侧 = 故障/冻结路径修调保持
//           进入时的值不再变化（液压跳变比保持更危险）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §805）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_RollBalanceState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 平衡监视相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_RollBalanceState :
(
    eIdle    := 0,   // 空闲：未使能 / Idle, not enabled
    eBalance := 10,  // 平衡：修调闭环运行 / Balance, trim loop running
    eFrozen  := 20,  // 冻结：纠偏饱和后持续超窗，修调保持 / Frozen, saturated trim held
    eFault   := 99   // 故障：组态非法/非有限/非法状态 / Fault, config, non-finite or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_RollCompressForceBalance
VAR_INPUT
    bEnable        : BOOL;                  // 平衡使能 [—] / Balance enable
    bReset         : BOOL;                  // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    fForceLeftKn   : LREAL;                 // 左侧轧制力 [千牛] / Left roll force [kN]
    fForceRightKn  : LREAL;                 // 右侧轧制力 [千牛] / Right roll force [kN]
    fDiffLimitKn   : LREAL := 10.0;         // 压差窗 [千牛]，须 > 0 / Differential window [kN]
    fTrimGainPctPerKn: LREAL := 1.0;        // 修调增益 [百分数每千牛] / Trim gain [percent/kN]
    fTrimRatePctS  : LREAL := 5.0;          // 修调限速 [百分数每秒]，须 > 0 / Trim slew rate [percent/s]
    fCycleTimeS    : LREAL := 0.01;         // 任务扫描周期 [秒]，须 > 0（R95 代理阈值） / Task scan cycle [s], must be > 0, R95 proxy
    tDiffDebounce  : TIME  := T#2S;         // 压差去抖窗 [ms]，须 > 0 / Differential debounce window [ms]
    tSatTimeout    : TIME  := T#30S;        // 饱和确认窗 [ms]，须 > 去抖窗（R100 配比） / Saturation confirm window [ms], must exceed the debounce
END_VAR
VAR_OUTPUT
    fTrimPct       : LREAL;                 // 差动修调输出 [百分数]，-100..100（正 = 增左向） / Differential trim output [percent], positive raises the left side
    bBalanceOk     : BOOL;                  // 压差在窗内 [—] / Differential inside the window
    bTrimSaturated : BOOL;                  // 修调饱和 [—] / Trim saturated
    eState         : E_DL_RollBalanceState; // 相位出口 [—] / Phase outlet
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0005_01FC 起信息级、16#0005_033F 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbDebounce : TON;                       // 压差去抖计时（每拍无条件刷新）[ms] / Debounce timer, refreshed unconditionally
    fbSat      : TON;                       // 饱和确认计时（每拍无条件刷新）[ms] / Saturation confirm timer, refreshed unconditionally
    _eState    : E_DL_RollBalanceState := E_DL_RollBalanceState.eIdle; // 当前相位 / Current phase
    _bCfgBad   : BOOL;                      // 组态非法锁存 / Illegal config latch
    _bInfoOver : BOOL;                      // 预警信息当拍标志 / Over-window info flag of this scan
    _bInfoSat  : BOOL;                      // 限幅信息当拍标志 / Saturation info flag of this scan
    _fDiff     : LREAL;                     // 压差 [千牛] / Differential [kN]
    _fTrimTarget: LREAL;                    // 修调目标 [百分数] / Trim target [percent]
    _fStep     : LREAL;                     // 本拍限速步进 [百分数] / Per-scan slew step [percent]
    _bIllegal  : BOOL;                      // 非法状态标志 / Illegal state flag
    _bInit     : BOOL := FALSE;             // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_RCF_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_RCF_EPS      : LREAL := 1.0E-6;      // 浮点判零容差 [混合] / Float zero tolerance
    DL_RCF_TRIMMAX  : LREAL := 100.0;       // 修调满幅 [百分数] / Trim full scale [percent]
    DL_RCF_SAT_EPS  : LREAL := 0.5;         // 饱和判定容差 [百分数]（距满幅 0.5% 内判饱和） / Saturation tolerance [percent]
    DL_RCF_ZERO     : LREAL := 0.0;         // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：修调保持语义（预置不清零，冻结/故障须保持），标志预清零
 *      Trim kept by design (held in frozen and fault), flags pre-cleared
 *-----------------------------------------------------------------------------*)
bBalanceOk := FALSE;                     // 压差在窗电平先清（段 5 重置） / In-window level cleared first
bTrimSaturated := FALSE;                 // 饱和电平先清 / Saturated level cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoOver := FALSE;                     // 预警信息预清零 / Over-window info pre-cleared
_bInfoSat  := FALSE;                     // 限幅信息预清零 / Saturation info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState  := E_DL_RollBalanceState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    fTrimPct := DL_RCF_ZERO;             // 修调从零起步 / Trim starts at zero
    _bInit   := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 压差窗/增益/限速/周期/时间窗域（含 R100 配比）
 *      Configuration defense gates with the R100 ratio rule
 *-----------------------------------------------------------------------------*)
IF (fForceLeftKn <> fForceLeftKn) OR (ABS(fForceLeftKn) > DL_RCF_INF)
   OR (fForceRightKn <> fForceRightKn) OR (ABS(fForceRightKn) > DL_RCF_INF)
   OR (fDiffLimitKn <> fDiffLimitKn) OR (ABS(fDiffLimitKn) > DL_RCF_INF)
   OR (fTrimGainPctPerKn <> fTrimGainPctPerKn) OR (ABS(fTrimGainPctPerKn) > DL_RCF_INF)
   OR (fTrimRatePctS <> fTrimRatePctS) OR (ABS(fTrimRatePctS) > DL_RCF_INF)
   OR (fCycleTimeS <> fCycleTimeS) OR (ABS(fCycleTimeS) > DL_RCF_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fDiffLimitKn <= DL_RCF_EPS) OR (fTrimRatePctS <= DL_RCF_EPS)
   OR (fCycleTimeS <= DL_RCF_EPS) OR (tDiffDebounce <= T#0MS)
   OR (tSatTimeout <= tDiffDebounce)) THEN
    _bCfgBad := TRUE;                    // 压差窗/限速/周期/时间窗域非法锁存（饱和窗须长于去抖窗） / Window domains latched, saturation window must exceed the debounce
END_IF
IF bReset THEN
    _bCfgBad := FALSE;                   // 复位清组态锁存 / Reset clears the config latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜双计时无条件刷新（R40：CASE 之外每拍必调）
 *      Two timers refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbDebounce(IN := (_eState = E_DL_RollBalanceState.eBalance)
                AND (ABS(_fDiff) > fDiffLimitKn), PT := tDiffDebounce); // 压差去抖窗 / Differential debounce window
fbSat(IN := (_eState = E_DL_RollBalanceState.eBalance)
           AND bTrimSaturated AND (ABS(_fDiff) > fDiffLimitKn), PT := tSatTimeout); // 饱和确认窗 / Saturation confirm window

(*------------------------------------------------------------------------------
 * 段 5｜相位机与修调链（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine and the trim chain
 *-----------------------------------------------------------------------------*)
_fDiff := fForceLeftKn - fForceRightKn;  // 压差 [千牛] / Differential
CASE _eState OF

    E_DL_RollBalanceState.eIdle:           // 空闲：使能且组态合法进平衡态
        IF bEnable AND (NOT _bCfgBad) THEN
            _eState := E_DL_RollBalanceState.eBalance; // 进平衡 / To balance
        ELSIF bEnable AND _bCfgBad THEN
            _eState := E_DL_RollBalanceState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_RollBalanceState.eBalance:        // 平衡：修调闭环 + 饱和确认
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_RollBalanceState.eFault; // 异常转故障 / Anomaly, fault
        ELSE
            bBalanceOk := ABS(_fDiff) <= fDiffLimitKn; // 压差在窗电平 / In-window level
            _fTrimTarget := MIN(MAX(-fTrimGainPctPerKn * _fDiff,
                              -DL_RCF_TRIMMAX), DL_RCF_TRIMMAX); // 修调目标（负反馈向）双侧满幅钳位 / Trim target, both sides clamped
            _fStep := fTrimRatePctS * fCycleTimeS; // 本拍限速步进 [百分数] / Per-scan slew step
            fTrimPct := MIN(MAX(fTrimPct, _fTrimTarget - _fStep),
                            _fTrimTarget + _fStep); // 限速逼近目标（双向平稳） / Slew approach, smooth both ways
            fTrimPct := MIN(MAX(fTrimPct, -DL_RCF_TRIMMAX), DL_RCF_TRIMMAX); // 满幅终钳 / Final full-scale clamp
            bTrimSaturated := ABS(fTrimPct) >= (DL_RCF_TRIMMAX - DL_RCF_SAT_EPS); // 饱和判定 / Saturation verdict
            IF bTrimSaturated THEN
                _bInfoSat := TRUE;         // 修调达限幅提示（信息级） / Trim at limit, info
            ELSIF ABS(_fDiff) > fDiffLimitKn THEN
                _bInfoOver := TRUE;        // 压差超窗预警（去抖计窗中，信息级） / Over-window warning, info
            END_IF
            IF fbSat.Q THEN
                _eState := E_DL_RollBalanceState.eFrozen; // 饱和后持续超窗：修调冻结（拍 N 进入） / Saturated over-window, trim frozen
            END_IF
        END_IF

    E_DL_RollBalanceState.eFrozen:         // 冻结：修调保持进入时的值；压差回窗且复位后回平衡
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_RollBalanceState.eFault; // 异常转故障 / Anomaly, fault
        ELSIF bReset AND (ABS(_fDiff) <= fDiffLimitKn) THEN
            _eState := E_DL_RollBalanceState.eBalance; // 复位且压差回窗回平衡 / Reset with the window back, to balance
        END_IF

    E_DL_RollBalanceState.eFault:          // 故障：复位沿且原因消失回平衡态
        IF bReset AND (NOT _bCfgBad) THEN
            _eState := E_DL_RollBalanceState.eBalance; // 回平衡 / Back to balance
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        fTrimPct := DL_RCF_ZERO;           // 修调撤零（安全侧） / Trim cleared, safe side
        _eState := E_DL_RollBalanceState.eFault; // 回故障态 / Back to fault
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_0341;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0005_033F;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _eState = E_DL_RollBalanceState.eFrozen THEN
    eErr   := 16#0005_0340;                // 故障级：压差持续超窗且纠偏饱和 / Fault: sustained over-window with saturated trim
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoSat THEN
    eErr := 16#0005_01FD;                  // 信息级：修调输出达限幅 / Info: trim at limit
ELSIF _bInfoOver THEN
    eErr := 16#0005_01FC;                  // 信息级：压差进入预警带 / Info: over-window warning
END_IF

IF (NOT bEnable) THEN
    fTrimPct := DL_RCF_ZERO;               // 未使能修调撤零（R72 显式路径） / Not enabled, trim to zero
END_IF
bValid := (NOT bError) AND bEnable AND (_eState <> E_DL_RollBalanceState.eIdle); // 空闲/故障/未使能输出不可用 / Outputs unusable in idle, fault or disabled
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
