//==============================================================================
// 功能块：FB_DL_TankN2BlanketCtrl ｜ 中文名称：储罐氮封压力双分程控制
// 所属子库：DL_Device ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：储罐氮封双分程——罐压低于低压分界按比例开补氮阀位（0~100%
//           连续段），高于高压分界关量泄放；两段互斥断言（任一拍
//           NOT(fN2ChargePct > 0 AND bVentCmd)）结构性成立；分界滞环提示；
//           压力冻结/非有限判传感器断线。v1.0.1 补迟滞回差（R23 终审
//           挂账修复）：泄放段退出阈值 = fPressHiKpa - fVentHystKpa
//           （进入阈值不变，退出沿以回差带下沿为准）；补氮段审计同理
//           （进入/退出阈值分离）：退出阈值 = fPressLoKpa + fVentHystKpa，
//           两段共用同一回差带宽度语义（不新占码位）。回差非法（<= 0
//           或 >= 分界跨度）→ 故障 0357 复用并回退默认 0.2 kPa；默认仍
//           越跨度时按跨度半宽钳定（防死循环），仍报 0357。
// 开源溯源 (Origin)：道莅原创实现（参考储罐氮封系统工程惯例 分类与参数域）
// 单位表：p[kPa]（表压）/ 分界[kPa] / 阀位[%] / 延时[ms]
// 错误码表：16#0003_0184 信息级（分界点附近滞环提示，或回差带内驻留
//           提示，不置 bError）/ 16#0003_0185 预留禁用（不得挪用）/
//           16#0003_0357 故障级（分程倒置 fPressHiKpa <= fPressLoKpa、
//           回差非法 fVentHystKpa <= 0 或 >= 分界跨度，或罐压非有限
//           全关安全侧，置 bError）/ 16#0003_0358 故障级（压力冻结超窗
//           判传感器断线，置 bError）/ 16#0003_0359 故障级兜底（置
//           bError）
// 状态机：E_DL_N2BlanketState（五态：eIdle=0 / eCharging=10 / eHold=20 /
//           eVenting=30 / eFault=99），CASE 含 ELSE 兜底，ELSE 置 0359 并全关
// 边界行为：① fPressHiKpa <= fPressLoKpa → 故障 0357（分程倒置）；② 两段
//           互斥由 IF/ELSE 单源赋值结构性保证（低压段才算阀位、高压段才
//           置泄放，中间保持段两路全断）；③ 罐压非有限 → 全关（安全侧）
//           + 故障 0357 复用（R90）；④ 压力冻结超 tPressLossDelay 判断线
//           → 故障 0358；⑤ 未使能输出冻结为零并 bValid := FALSE；⑥
//           泄放退出沿 = 罐压 < fPressHiKpa - fVentHystKpa（回差带下沿），
//           补氮退出沿 = 罐压 > fPressLoKpa + fVentHystKpa（回差带上沿），
//           进入阈值两侧均不变；回差非法回退默认 0.2 kPa 仍越跨度时按
//           跨度半宽钳定并保持 0357 报警。
// 依赖收窄 (R11 留档③)：Device 不得调用 DL_Algo——分程律在本件内联实现
//           （低压段线性补氮 + 高压段开关量泄放），与 FB_DL_SplitRangeControl
//           的参数域一致性（分界点语义、0~100% 线性段）由本件头注释承担
//           验证责任，改动任一侧须复核另一侧。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP P1 §396）
//           v1.0.1 2026-11-17 R24 挂账修复：补泄放退出迟滞回差（新增
//           输入引脚 fVentHystKpa : LREAL := 0.2 [kPa]，默认非魔法数，
//           不新占码位），eVenting 退出沿以回差带下沿为准；补氮段迟滞
//           同理审计（进入/退出阈值分离，共用同一回差带宽）；回差非法
//           → 0357 复用并回退默认；0003_0184 信息级语义扩展为滞环/回差
//           驻留提示。引脚契约其余不变，枚举不变。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_N2BlanketState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 氮封工作相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_N2BlanketState :
(
    eIdle     := 0,   // 空闲：未使能 / Idle, not enabled
    eCharging := 10,  // 补氮中：罐压低于低压分界，补氮阀位有效 / Charging, pressure below the low boundary
    eHold     := 20,  // 保持：罐压在两分界之间，两路全断 / Hold, pressure between the boundaries, both off
    eVenting  := 30,  // 泄放中：罐压达高压分界，泄放阀开 / Venting, pressure at the high boundary
    eFault    := 99   // 故障：组态非法/断线/非有限/非法状态 / Fault, illegal config, loss, non-finite or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_TankN2BlanketCtrl
VAR_INPUT
    fTankPressKpa   : LREAL;                // 罐压实测 [千帕]，表压 / Measured tank pressure [kPa], gauge
    fPressLoKpa     : LREAL := 0.5;         // 低压分界 [千帕]，低于此补氮 / Low boundary [kPa], charge below
    fPressHiKpa     : LREAL := 2.0;         // 高压分界 [千帕]，须 > 低压分界，达此泄放 / High boundary [kPa], must exceed the low, vent at
    fVentHystKpa    : LREAL := 0.2;         // 泄放/补氮退出迟滞回差 [千帕]，有效域 (0, 分界跨度)，v1.0.1 新增 / Vent and charge exit hysteresis [kPa], added in v1.0.1
    fN2ValveOutFb   : BOOL;                 // 补氮阀开反馈 [—] / N2 charge valve open feedback
    bEnable         : BOOL;                 // 控制使能 [—] / Control enable
    bReset          : BOOL;                 // 故障复位 [—] / Fault reset
END_VAR
VAR_OUTPUT
    fN2ChargePct    : LREAL;                // 补氮阀位 [百分数]，0~100，仅低压段有效 / N2 charge valve position [percent], 0..100, low band only
    bVentCmd        : BOOL;                 // 泄放阀指令 [—]，开关量，仅高压段 / Vent valve command, on/off, high band only
    eBlanketState   : E_DL_N2BlanketState;  // 氮封相位 [—] / Blanket phase
    eErr            : UDINT;                // 错误码，0 = 无错 / Error code, 0 = no error
    bError          : BOOL;                 // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                 // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbFrozen        : TON;                  // 压力冻结判窗（断线检测），段 6 无条件刷新 [ms] / Frozen-pressure window, loss detection
    _fPressPrev     : LREAL;                // 上拍罐压快照（冻结检测基准） / Previous-scan pressure snapshot
    _bInit          : BOOL := FALSE;        // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bSplitBad      : BOOL;                 // 分程倒置/非有限锁存 / Inversion or non-finite latch
    _bFrozenBad     : BOOL;                 // 压力冻结锁存 / Frozen-pressure latch
    _bNearBand      : BOOL;                 // 分界滞环当拍标志 / Near-boundary flag of this scan
    _fHystEff       : LREAL;                // 生效回差带宽度 [千帕]（非法回退默认/钳定） / Effective hysteresis width [kPa]
    _bHystBad       : BOOL;                 // 回差非法锁存（0357 复用） / Illegal hysteresis latch
    _bIllegal       : BOOL;                 // 非法状态标志 / Illegal state flag
    _eState         : E_DL_N2BlanketState := E_DL_N2BlanketState.eIdle; // 当前相位 / Current phase
END_VAR
VAR CONSTANT
    DL_N2_INF       : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_N2_LOSS_TOL  : LREAL := 1.0E-9;      // 冻结判据容差 [千帕] / Frozen detection tolerance [kPa]
    DL_N2_LOSS_WIN  : TIME  := T#5S;        // 压力冻结判窗 [ms] / Frozen-pressure window [ms]
    DL_N2_BAND_TOL  : LREAL := 0.05;        // 分界滞环提示带 [千帕] / Near-boundary notice band [kPa]
    DL_N2_HYST_DEF  : LREAL := 0.2;         // 回差带宽度默认值 [千帕]，非法时回退目标（v1.0.1） / Hysteresis default [kPa], fallback target in v1.0.1
    DL_N2_EPS       : LREAL := 1.0E-6;      // 浮点判零容差 [千帕] / Float zero tolerance [kPa]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：双输出先全关（安全侧），单拍标志预清零
 *      Both outputs closed first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fN2ChargePct  := 0.0;                       // 补氮阀位先清（安全侧） / Charge position cleared first
bVentCmd      := FALSE;                     // 泄放指令先清（安全侧） / Vent command cleared first
eErr          := 16#0000_0000;              // 错误码每拍重算 / Error code recomputed
bError        := FALSE;                     // 故障标志每拍重算 / Fault flag recomputed
bValid        := FALSE;                     // 可用标志每拍重算 / Usable flag recomputed
_bNearBand    := FALSE;                     // 滞环标志预清零 / Near-band flag pre-cleared
_bIllegal     := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_N2BlanketState.eIdle; // 相位空闲起步 / Phase starts idle
    _fPressPrev := 0.0;                     // 压力快照从零起步 / Pressure snapshot starts at zero
    _bSplitBad  := FALSE;                   // 分程锁存清零 / Inversion latch cleared
    _bFrozenBad := FALSE;                   // 冻结锁存清零 / Frozen latch cleared
    _bHystBad   := FALSE;                   // 回差锁存清零（v1.0.1） / Hysteresis latch cleared, v1.0.1
    _fHystEff   := DL_N2_HYST_DEF;          // 回差从默认起步（v1.0.1） / Hysteresis starts at the default, v1.0.1
    _bInit      := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与输入防御闸（分程倒置 / 非有限 → 0357 复用，R90）
 *      Configuration and input defense gates, code reused per R90
 *-----------------------------------------------------------------------------*)
IF (fTankPressKpa <> fTankPressKpa) OR (ABS(fTankPressKpa) > DL_N2_INF)
   OR (fPressLoKpa <> fPressLoKpa) OR (ABS(fPressLoKpa) > DL_N2_INF)
   OR (fPressHiKpa <> fPressHiKpa) OR (ABS(fPressHiKpa) > DL_N2_INF) THEN
    _bSplitBad := TRUE;                     // 非有限输入归入分程非法（安全侧全关） / Non-finite folded into the inversion fault, fail-safe closed
END_IF
IF (NOT _bSplitBad) AND (fPressHiKpa <= fPressLoKpa) THEN
    _bSplitBad := TRUE;                     // 分程倒置锁存 / Inversion latched
END_IF

(*------------------------------------------------------------------------------
 * 段 3b｜回差带宽度合法性闸（v1.0.1）：非法回退默认，默认仍越跨度按半宽钳定
 *      Hysteresis validity gate, fallback to default, half-span clamp
 *-----------------------------------------------------------------------------*)
IF (NOT _bSplitBad)
   AND ((fVentHystKpa <> fVentHystKpa) OR (ABS(fVentHystKpa) > DL_N2_INF)
        OR (fVentHystKpa <= DL_N2_LOSS_TOL)
        OR (fVentHystKpa >= (fPressHiKpa - fPressLoKpa))) THEN
    _bHystBad := TRUE;                      // 回差非法锁存（0357 复用，R90：滞环语义扩展不新占码位） / Illegal hysteresis latched
    _fHystEff := DL_N2_HYST_DEF;            // 回退默认值 / Fallback to the default
    IF _fHystEff >= (fPressHiKpa - fPressLoKpa) THEN
        _fHystEff := 0.5 * (fPressHiKpa - fPressLoKpa); // 默认仍越跨度：按跨度半宽钳定（防死循环） / Default beyond span, clamped to half span
    END_IF
ELSIF NOT _bSplitBad THEN
    _fHystEff := fVentHystKpa;              // 合法回差原值生效 / Legal hysteresis applied as-is
ELSE
    _fHystEff := DL_N2_HYST_DEF;            // 分程已非法：回差取默认（不重复报码，R90） / Split already illegal, default width, no duplicate code
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜压力冻结检测：罐压与上拍差 < 容差持续超窗 → 判传感器断线
 *      Frozen-pressure detection, loss suspected beyond the window
 *-----------------------------------------------------------------------------*)
fbFrozen(IN := bEnable AND (NOT _bSplitBad)
             AND (ABS(fTankPressKpa - _fPressPrev) < DL_N2_LOSS_TOL), PT := DL_N2_LOSS_WIN); // 压力冻结判窗 / Frozen-pressure window
_fPressPrev := fTankPressKpa;               // 快照推进 / Snapshot advanced
IF fbFrozen.Q THEN
    _bFrozenBad := TRUE;                    // 断线锁存（安全侧全关） / Loss latched, fail-safe closed
END_IF
IF bReset THEN
    _bFrozenBad := FALSE;                   // 复位清冻结锁存 / Reset clears the frozen latch
    _bHystBad   := FALSE;                   // 复位清回差非法锁存（v1.0.1） / Reset clears the hysteresis latch, v1.0.1
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜相位机与分程律内联（互斥断言：低压段才算阀位、高压段才置泄放）
 *      Phase machine and the inline split-range law, mutually exclusive
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR _bSplitBad OR _bFrozenBad THEN
    _eState := E_DL_N2BlanketState.eFault;  // 未使能或异常转故障态（全关） / Not enabled or anomaly, fault with all closed
ELSE
CASE _eState OF

    E_DL_N2BlanketState.eIdle:             // 空闲：使能即进保持
        IF bEnable THEN
            _eState := E_DL_N2BlanketState.eHold; // 进保持 / To hold
        END_IF

    E_DL_N2BlanketState.eHold:             // 保持：分界判定进补氮或泄放
        IF fTankPressKpa <= fPressLoKpa THEN
            _eState := E_DL_N2BlanketState.eCharging; // 进补氮 / To charging
        ELSIF fTankPressKpa >= fPressHiKpa THEN
            _eState := E_DL_N2BlanketState.eVenting; // 进泄放 / To venting
        END_IF
        IF (ABS(fTankPressKpa - fPressLoKpa) < DL_N2_BAND_TOL)
           OR (ABS(fTankPressKpa - fPressHiKpa) < DL_N2_BAND_TOL) THEN
            _bNearBand := TRUE;             // 分界滞环提示 / Near-boundary notice
        END_IF

    E_DL_N2BlanketState.eCharging:         // 补氮：罐压超回差带上沿（v1.0.1 阈值分离）即回保持
        IF fTankPressKpa > (fPressLoKpa + _fHystEff) THEN
            _eState := E_DL_N2BlanketState.eHold; // 回保持 / Back to hold
        END_IF

    E_DL_N2BlanketState.eVenting:          // 泄放：罐压跌破回差带下沿（v1.0.1 退出沿）即回保持
        IF fTankPressKpa < (fPressHiKpa - _fHystEff) THEN
            _eState := E_DL_N2BlanketState.eHold; // 回保持 / Back to hold
        END_IF

    E_DL_N2BlanketState.eFault:            // 故障：复位沿且原因消失回保持
        IF bReset AND (NOT _bSplitBad) AND (NOT _bFrozenBad) AND bEnable THEN
            _eState := E_DL_N2BlanketState.eHold; // 回保持 / Back to hold
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_N2BlanketState.eFault; // 回故障态（全关） / Back to fault, all closed
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜输出置位：IF/ELSE 单源赋值，两段互斥结构性成立
 *      Output assignment, mutual exclusion holds structurally
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_N2BlanketState.eCharging:         // 补氮段：阀位按低压段深度线性（0~100%） / Charging: position linear in the low band
        IF ABS(fPressLoKpa) > DL_N2_EPS THEN
            fN2ChargePct := MIN(MAX((fPressLoKpa - fTankPressKpa) / fPressLoKpa, 0.0), 1.0) * 100.0; // 补氮阀位 [百分数]，分母已闸 / Charge position, denominator gated
        ELSE
            fN2ChargePct := 100.0;          // 低压分界为 0：全开补氮（退化域防御） / Zero boundary, full charge
        END_IF
        bVentCmd := FALSE;                  // 泄放指令断（互斥断言） / Vent command off, mutually exclusive
    E_DL_N2BlanketState.eVenting:          // 泄放段：泄放开、补氮全关 / Venting: vent on, charge fully closed
        fN2ChargePct := 0.0;               // 补氮全关 / Charge fully closed
        bVentCmd := TRUE;                  // 泄放指令开 / Vent command on
    ELSE                                   // 其余相两路全关（含保持/故障） / Otherwise both closed, hold and fault
        fN2ChargePct := 0.0;               // 补氮全关 / Charge fully closed
        bVentCmd := FALSE;                 // 泄放指令断 / Vent command off
END_CASE
eBlanketState := _eState;                   // 相位出口 / Phase outlet

(*------------------------------------------------------------------------------
 * 段 7｜码位出口
 *      Code outlet
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0003_0359;                 // 故障级：状态机兜底 / Fault: fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bSplitBad OR _bFrozenBad OR _bHystBad THEN
    IF _bFrozenBad AND (NOT _bSplitBad) AND (NOT _bHystBad) THEN
        eErr   := 16#0003_0358;             // 故障级：压力冻结判断线 / Fault: frozen pressure, loss suspected
    ELSE
        eErr   := 16#0003_0357;             // 故障级：分程倒置/回差非法/非有限（R90 复用） / Fault: inversion, illegal hysteresis or non-finite, code reused
    END_IF
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bNearBand THEN
    eErr := 16#0003_0184;                   // 信息级：分界滞环提示 / Info: near-boundary notice
END_IF

bValid := (NOT bError) AND bEnable AND (_eState <> E_DL_N2BlanketState.eIdle); // 空闲/故障/未使能输出不可用 / Outputs unusable in idle, fault or disabled
END_FUNCTION_BLOCK
