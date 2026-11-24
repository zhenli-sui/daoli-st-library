//==============================================================================
// 功能块：FB_DL_AirCompDutyN2 ｜ 中文名称：空压机/制氮机组联产轮值
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：空压机/制氮机组联产轮值调度——按制氮需求从就绪机组池按
//           轮值序投切，输出投运台数与供/需余量（负值即缺口，缺口可观测
//           但不自动超载投切——安全侧）；启动反馈矛盾超窗的机组剔除轮值池。
// 开源溯源 (Origin)：道莅原创实现（参考空压站/制氮站轮值工程惯例 分类与参数域）
// 单位表：需求/能力/余量[Nm3/h] / 台数[台] / 下标[台] / 延时[ms]
// 错误码表：16#0005_01EA 信息级（供气缺口：需求 > 全部已就绪能力，余量
//           为负，可观测不自动超载投切，不置 bError）/ 16#0005_01EB 预留
//           禁用（不得挪用）/ 16#0005_0324 故障级（机组启动失败：命令
//           TRUE 反馈 FALSE 超窗，该台剔除轮值池，置 bError）/
//           16#0005_0325 预留禁用（不得挪用）/ 16#0005_0326 故障级兜底
//           （置 bError）
// 状态机：N/A（轮值为每拍重算的调度逻辑 + 机组剔除锁存，无相位状态机；
//           剔除锁存由 abUnitBanned 保持量承担，bReset 清除）
// 边界行为：① 需求 > 全部已就绪能力 → fSupplyMargin < 0 + 信息 01EA，
//           不自动超载投切（安全侧，投运台数 = 就绪池全量）；② 数组访问
//           一律 <= DL_UNIT_MAX 双闸（字面量上界 4 与常量同源，一致性由
//           本件承担验证责任）；③ 轮值思想内联简化实现（头注释「依赖
//           收窄」声明：Process → Level 0 组合调用 FB_DL_DutyStandbyRotation
//           合法但接口为单机对语义，多机排序轮值内联简化，改动任一侧须
//           复核另一侧）；④ 反馈矛盾（命令 TRUE 反馈 FALSE 超 tStartFbDelay）
//           → 该台故障 0324 + 剔除轮值池；⑤ 非有限需求/能力 → 该台剔除
//           + 0324 复用（R90）。
// 依赖收窄 (R11 留档③)：轮值律内联实现，见边界③。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 公用工程 P1 §393）
//==============================================================================

FUNCTION_BLOCK FB_DL_AirCompDutyN2
VAR_INPUT
    fN2DemandNm3H  : LREAL;                 // 制氮需求 [标立方米/小时] / N2 demand [Nm3/h]
    aN2SupplyNm3H  : ARRAY[1..4] OF LREAL;  // 各机组能力 [标立方米/小时]，下标 1..4 / Capacity per unit [Nm3/h], index 1..4
    abUnitReady    : ARRAY[1..4] OF BOOL;   // 各机组就绪 [—] / Per-unit ready flags
    abUnitRunFb    : ARRAY[1..4] OF BOOL;   // 各机组运行反馈 [—] / Per-unit run feedbacks
    tStartFbDelay  : TIME := T#10S;         // 启动反馈确认延时 [ms] / Start-feedback confirm delay [ms]
    bEnable        : BOOL;                  // 调度使能 [—] / Dispatch enable
    bReset         : BOOL;                  // 故障复位 [—]，清除剔除锁存 / Fault reset, clears the ban latches
END_VAR
VAR_OUTPUT
    abUnitCmd      : ARRAY[1..4] OF BOOL;   // 各机组投运指令 [—] / Per-unit dispatch commands
    uUnitsNeeded   : UINT;                  // 需投台数 [台] / Units needed [count]
    fSupplyMarginNm3H : LREAL;              // 供/需余量 [标立方米/小时]，负值即缺口 / Supply margin [Nm3/h], negative means a gap
    eErr           : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = no error
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    aFbDelay       : ARRAY[1..4] OF TON;    // 各台启动反馈确认计时，段 6 无条件刷新 [ms] / Per-unit feedback confirm timers
    _abUnitBanned  : ARRAY[1..4] OF BOOL;   // 各台剔除轮值池锁存 / Per-unit ban latches
    _aFbBreak      : ARRAY[1..4] OF BOOL;   // 各台计时断输入一拍标志 / Per-unit one-scan break flags
    _fDemandEff    : LREAL;                 // 钳位后的生效需求 [标立方米/小时] / Effective clamped demand [Nm3/h]
    _fReadyCap     : LREAL;                 // 就绪池总能力 [标立方米/小时] / Total ready-pool capacity [Nm3/h]
    _fSupplyCap    : LREAL;                 // 投运池总能力 [标立方米/小时] / Total dispatched capacity [Nm3/h]
    _uIdx          : UINT;                  // 循环下标 [台] / Loop index
    _uNeed         : UINT;                  // 需投台数暂存 [台] / Staged units needed
    _bInit         : BOOL := FALSE;         // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bDemandBad    : BOOL;                  // 需求非有限锁存 / Non-finite demand latch
    _bGap          : BOOL;                  // 供气缺口当拍标志 / Supply gap flag of this scan
    _bAnyBanned    : BOOL;                  // 任一台被剔除当拍标志 / Any-banned flag of this scan
    _bIllegal      : BOOL;                  // 非法状态标志 / Illegal state flag
END_VAR
VAR CONSTANT
    DL_UNIT_MAX    : UINT  := 4;            // 机组上限 [台]，与接口字面量上界 4 同源，改动须同步 / Unit ceiling [count], same source as the literal bound 4
    DL_AC_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：指令先全断（安全侧），单拍标志预清零
 *      Commands cleared first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
FOR _uIdx := 1 TO DL_UNIT_MAX DO
    IF _uIdx <= DL_UNIT_MAX THEN            // 二次闸 / Secondary gate
        abUnitCmd[_uIdx] := FALSE;          // 投运指令先清（安全侧） / Dispatch command cleared first
    END_IF
END_FOR
uUnitsNeeded      := 0;                    // 需投台数预置零 / Units needed preset zero
fSupplyMarginNm3H := 0.0;                  // 余量预置零 / Margin preset zero
eErr              := 16#0000_0000;         // 错误码每拍重算 / Error code recomputed
bError            := FALSE;                // 故障标志每拍重算 / Fault flag recomputed
bValid            := FALSE;                // 可用标志每拍重算 / Usable flag recomputed
_bGap             := FALSE;                // 缺口标志预清零 / Gap flag pre-cleared
_bAnyBanned       := FALSE;                // 剔除标志预清零 / Banned flag pre-cleared
_bIllegal         := FALSE;                // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    FOR _uIdx := 1 TO DL_UNIT_MAX DO
        IF _uIdx <= DL_UNIT_MAX THEN        // 二次闸 / Secondary gate
            _abUnitBanned[_uIdx] := FALSE;  // 剔除锁存清零 / Ban latch cleared
            _aFbBreak[_uIdx]     := TRUE;   // 计时窗从零开始 / The timer starts from zero
        END_IF
    END_FOR
    _bInit := TRUE;                         // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜需求防御闸（非有限 → 0324 复用，R90）与复位
 *      Demand defense gate, code reused per R90, and the reset
 *-----------------------------------------------------------------------------*)
IF (fN2DemandNm3H <> fN2DemandNm3H) OR (ABS(fN2DemandNm3H) > DL_AC_INF) THEN
    _bDemandBad := TRUE;                    // 需求非有限锁存 / Non-finite demand latched
END_IF
IF fN2DemandNm3H < 0.0 THEN
    _fDemandEff := 0.0;                     // 负需求按零（物理下界） / Negative demand treated as zero
ELSE
    _fDemandEff := fN2DemandNm3H;           // 合法需求原值生效 / Valid demand applied as-is
END_IF
IF bReset THEN
    FOR _uIdx := 1 TO DL_UNIT_MAX DO
        IF _uIdx <= DL_UNIT_MAX THEN        // 二次闸 / Secondary gate
            _abUnitBanned[_uIdx] := FALSE;  // 复位清剔除锁存 / Reset clears the ban latches
        END_IF
    END_FOR
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜就绪池能力汇总（剔除台与非有限台不计入）与缺口判定
 *      Ready-pool capacity summary with banned and non-finite units excluded
 *-----------------------------------------------------------------------------*)
_fReadyCap := 0.0;                          // 就绪池能力清零 / Ready capacity cleared
FOR _uIdx := 1 TO DL_UNIT_MAX DO
    IF _uIdx <= DL_UNIT_MAX THEN            // 二次闸 / Secondary gate
        IF abUnitReady[_uIdx] AND (NOT _abUnitBanned[_uIdx]) THEN
            IF (aN2SupplyNm3H[_uIdx] <> aN2SupplyNm3H[_uIdx]) OR (ABS(aN2SupplyNm3H[_uIdx]) > DL_AC_INF) THEN
                _abUnitBanned[_uIdx] := TRUE; // 能力非有限：剔除轮值池（0324 复用，R90） / Non-finite capacity, unit banned
                _bAnyBanned := TRUE;          // 剔除标志置位 / Banned flag raised
            ELSE
                _fReadyCap := _fReadyCap + aN2SupplyNm3H[_uIdx]; // 就绪池能力累加 / Ready capacity accumulated
            END_IF
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 5｜轮值调度内联实现（依赖收窄，见头注释）：按需求从就绪池顺序投切
 *       轮值序 = 数组下标序（简化实现，头注释声明），缺口不超载投切
 *      Inline rotation dispatch, sequential by index, no overload on a gap
 *-----------------------------------------------------------------------------*)
IF bEnable AND (NOT _bDemandBad) THEN
    IF _fDemandEff > _fReadyCap THEN
        _bGap := TRUE;                      // 供气缺口（信息级，不超载投切） / Supply gap, no overload dispatch
        _fDemandEff := _fReadyCap;          // 投切按就绪池全量封顶（安全侧） / Dispatch capped at the ready pool
    END_IF
    _fSupplyCap := 0.0;                     // 投运池能力清零 / Dispatched capacity cleared
    _uNeed := 0;                            // 需投台数清零 / Units needed cleared
    FOR _uIdx := 1 TO DL_UNIT_MAX DO
        IF _uIdx <= DL_UNIT_MAX THEN        // 二次闸 / Secondary gate
            IF abUnitReady[_uIdx] AND (NOT _abUnitBanned[_uIdx])
               AND (_fSupplyCap < _fDemandEff) THEN
                abUnitCmd[_uIdx] := TRUE;   // 投运指令置位 / Dispatch command set
                IF (aN2SupplyNm3H[_uIdx] <> aN2SupplyNm3H[_uIdx]) OR (ABS(aN2SupplyNm3H[_uIdx]) > DL_AC_INF) THEN
                    (* 非有限能力台不参与累加（段 4 已剔除，此处双保险） / Non-finite excluded, double-guarded *)
                    _fSupplyCap := _fSupplyCap + 0.0; // 零贡献 / Zero contribution
                ELSE
                    _fSupplyCap := _fSupplyCap + aN2SupplyNm3H[_uIdx]; // 投运能力累加 / Dispatched capacity accumulated
                END_IF
                _uNeed := _uNeed + 1;       // 需投台数递增 / Units needed increment
            END_IF
        END_IF
    END_FOR
    uUnitsNeeded := _uNeed;                 // 需投台数出口 / Units needed outlet
    fSupplyMarginNm3H := _fReadyCap - fN2DemandNm3H; // 余量出口（负值即缺口，按原始需求算） / Margin outlet, negative means a gap
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜各台启动反馈确认计时无条件刷新（R40：CASE 之外每拍必调）
 *      Per-unit feedback timers refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
FOR _uIdx := 1 TO DL_UNIT_MAX DO
    IF _uIdx <= DL_UNIT_MAX THEN            // 二次闸 / Secondary gate
        aFbDelay[_uIdx](IN := abUnitCmd[_uIdx] AND (NOT abUnitRunFb[_uIdx]) AND (NOT _aFbBreak[_uIdx]),
                        PT := tStartFbDelay); // 启动反馈确认计时 / Start-feedback confirm timer
        _aFbBreak[_uIdx] := FALSE;          // 断输入拍在调用后自清 / Break self-cleared after the call
        IF aFbDelay[_uIdx].Q THEN
            _abUnitBanned[_uIdx] := TRUE;   // 启动失败：剔除轮值池 / Start failure, unit banned
            _bAnyBanned := TRUE;            // 剔除标志置位 / Banned flag raised
            _aFbBreak[_uIdx] := TRUE;       // 窗重启（下次投切重新计时） / The window restarts for the next dispatch
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 7｜码位出口
 *      Code outlet
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_0326;                 // 故障级：状态机兜底 / Fault: fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bDemandBad OR _bAnyBanned THEN
    eErr   := 16#0005_0324;                 // 故障级：启动失败/非有限剔除（R90 复用） / Fault: start failure or non-finite ban
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := TRUE;                         // 调度结果本身可用（剔除台已隔离） / The dispatch result itself is usable
ELSIF _bGap THEN
    eErr := 16#0005_01EA;                   // 信息级：供气缺口（不超载投切） / Info: supply gap, no overload dispatch
    bValid := TRUE;                         // 输出可用 / Outputs usable
ELSE
    bValid := bEnable;                      // 使能且正常：输出可用 / Outputs usable when enabled
END_IF
END_FUNCTION_BLOCK
