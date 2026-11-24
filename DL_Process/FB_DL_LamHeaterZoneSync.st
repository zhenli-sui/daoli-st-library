//==============================================================================
// 功能块：FB_DL_LamHeaterZoneSync ｜ 中文名称：层压机加热板多温区同步跟随
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：层压机加热板多温区同步监视——计算有效温区两两最大区差与
//           最差温差对，区差超阈值经确认窗（防瞬态抖动）判失步故障；
//           链速参与跟随语义（链速为 0 时跟随斜率冻结，不除零）。
// 开源溯源 (Origin)：道莅原创实现（参考光伏组件层压机工程惯例 分类与参数域）
// 单位表：T[°C] / 区差[K] / 链速[mm/s] / 确认窗[ms] / 温区下标[区]
// 错误码表：16#0005_01E6 信息级（非有限温区剔除声明，不置 bError）/
//           16#0005_01E7 信息级（区数上限已钳位 8，不置 bError）/
//           16#0005_031E 故障级（区差超限经确认窗确认，置 bError）/
//           16#0005_031F 故障级（有效区数 < 2 无法判区差，置 bError）/
//           16#0005_0320 故障级兜底（置 bError）
// 状态机：N/A（阈值确认窗 + 电平逻辑，无相位状态机；故障经确认窗后以
//           bSyncOk 电平与 031E 表达，原因消失自动恢复，无锁存）
// 边界行为：① 区差 > 阈值持续确认窗 → 故障 031E + bSyncOk := FALSE
//           （R13 AhuDamperStuckDiag 确认窗范式复用）；② 任一温区非有限
//           → 该区剔除出区差统计 + 信息 01E6；有效区数 < 2 → 故障 031F；
//           ③ 链速为 0 → 跟随斜率冻结（不除零），区差统计不受影响；
//           ④ 区数上限钳 8 + 信息 01E7（接口字面量上界 8 与 DL_ZONE_MAX
//           同源，一致性由本件承担验证责任）；⑤ 非使能时输出冻结为零
//           值并 bValid := FALSE（不静默沿用旧差值）。
// 依赖纪律：仅 Standard.library；零跨层调用（两两区差为 O(n²) 遍历的
//           监视语义，非统计算法复制，头注释声明此设计取舍）。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 光伏 P1 §416）
//==============================================================================

FUNCTION_BLOCK FB_DL_LamHeaterZoneSync
VAR_INPUT
    aZoneTempC    : ARRAY[1..8] OF LREAL;   // 各温区实测 [摄氏度]，下标 1..8，超编路填 0 且不计 / Measured zone temperatures [degC], index 1..8
    uZoneCount    : UINT;                   // 实际温区数 [区]，有效域 0..8，> 8 钳位 / Actual zone count [zones], 0..8, clamped above
    fZoneDiffMaxK : LREAL := 5.0;           // 区差阈值 [K]，须 > 0 / Zone-difference threshold [K], must be > 0
    fBeltSpeedMmS : LREAL;                  // 链速 [毫米/秒]，0 = 停链（跟随冻结） / Belt speed [mm/s], zero = stopped, follow frozen
    bEnable       : BOOL;                   // 使能 [—] / Enable
    bReset        : BOOL;                   // 故障复位 [—]，清除确认窗 / Fault reset, clears the confirm window
END_VAR
VAR_OUTPUT
    fMaxZoneDiffK : LREAL;                  // 当拍最大区差 [K] / Maximum zone difference this scan [K]
    bSyncOk       : BOOL;                   // 同步正常 [—] / Synchronization OK
    uWorstPairA   : UINT;                   // 最大温差对 A 区下标 [区] / Worst pair index A [zone]
    uWorstPairB   : UINT;                   // 最大温差对 B 区下标 [区] / Worst pair index B [zone]
    eErr          : UDINT;                  // 错误码，0 = 无错 / Error code, 0 = no error
    bError        : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbConfirm     : TON;                    // 区差超限确认窗，段 6 无条件刷新 [ms] / Zone-diff confirm window
    _uCountEff    : UINT;                   // 钳位后的生效区数 [区] / Effective clamped zone count
    _uValidZones  : UINT;                   // 非有限剔除后的有效区数 [区] / Valid zone count after culling
    _uI           : UINT;                   // 外层遍历下标 [区] / Outer loop index
    _uJ           : UINT;                   // 内层遍历下标 [区] / Inner loop index
    _fDiff        : LREAL;                  // 当前对区差 [K] / Current pair difference [K]
    _bInit        : BOOL := FALSE;          // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bCullInfo    : BOOL;                   // 非有限剔除信息当拍标志 / Cull info flag of this scan
    _bClampInfo   : BOOL;                   // 区数钳位信息当拍标志 / Clamp info flag of this scan
    _bIllegal     : BOOL;                   // 非法输入标志（阈值非有限/<= 0） / Illegal input flag
END_VAR
VAR CONSTANT
    DL_ZONE_MAX   : UINT  := 8;             // 温区上限 [区]，与接口字面量上界 8 同源，改动须同步 / Zone ceiling [zones], same source as the literal bound 8, change both together
    DL_LAM_INF    : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_LAM_CONFIRM: TIME  := T#10S;         // 区差超限确认窗 [ms]（R13 范式） / Zone-diff confirm window [ms], R13 pattern
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出先算后出，单拍标志预清零
 *      Outputs computed per scan, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fMaxZoneDiffK := 0.0;                       // 最大区差预置零 / Max difference preset zero
bSyncOk       := FALSE;                     // 同步正常预置 FALSE / Sync OK preset FALSE
uWorstPairA   := 0;                         // 最差对 A 预置零 / Worst A preset zero
uWorstPairB   := 0;                         // 最差对 B 预置零 / Worst B preset zero
eErr          := 16#0000_0000;              // 错误码每拍重算 / Error code recomputed
bError        := FALSE;                     // 故障标志每拍重算 / Fault flag recomputed
bValid        := FALSE;                     // 可用标志每拍重算 / Usable flag recomputed
_bCullInfo    := FALSE;                     // 剔除信息预清零 / Cull info pre-cleared
_bClampInfo   := FALSE;                     // 钳位信息预清零 / Clamp info pre-cleared
_bIllegal     := FALSE;                     // 非法输入预清零 / Illegal input pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _uCountEff := 0;                        // 生效区数从零起步 / Effective count starts at zero
    _bInit     := TRUE;                     // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与输入防御闸（阈值非法 / 区数钳位）
 *      Configuration and input defense gates
 *-----------------------------------------------------------------------------*)
IF (fZoneDiffMaxK <> fZoneDiffMaxK) OR (ABS(fZoneDiffMaxK) > DL_LAM_INF) OR (fZoneDiffMaxK <= 0.0) THEN
    _bIllegal := TRUE;                      // 阈值非法（031F 无法判差的同类防御，R90 精神） / Illegal threshold
END_IF
IF (fBeltSpeedMmS <> fBeltSpeedMmS) OR (ABS(fBeltSpeedMmS) > DL_LAM_INF) THEN
    _bIllegal := TRUE;                      // 链速非有限防御 / Non-finite belt speed
END_IF
IF uZoneCount > DL_ZONE_MAX THEN
    _uCountEff := DL_ZONE_MAX;              // 区数钳位到 8 / Zone count clamped to 8
    _bClampInfo := TRUE;                    // 钳位信息置位 / Clamp info raised
ELSE
    _uCountEff := uZoneCount;               // 合法区数原值生效 / Valid count applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜两两区差扫描（非有限区剔除 + 最差对记录）
 *      Pairwise scan with non-finite culling and worst-pair recording
 *-----------------------------------------------------------------------------*)
_uValidZones := 0;                          // 有效区数清零 / Valid count cleared
FOR _uI := 1 TO _uCountEff DO
    IF _uI <= DL_ZONE_MAX THEN              // 二次闸：越界结构性不可能 / Secondary gate, out-of-bounds impossible
        IF (aZoneTempC[_uI] <> aZoneTempC[_uI]) OR (ABS(aZoneTempC[_uI]) > DL_LAM_INF) THEN
            _bCullInfo := TRUE;             // 非有限区剔除声明 / Non-finite zone culled
        ELSE
            _uValidZones := _uValidZones + 1; // 有效区计数递增 / Valid count increment
        END_IF
        FOR _uJ := _uI + 1 TO _uCountEff DO
            IF _uJ <= DL_ZONE_MAX THEN      // 二次闸 / Secondary gate
                IF (aZoneTempC[_uI] <> aZoneTempC[_uI]) OR (ABS(aZoneTempC[_uI]) > DL_LAM_INF)
                   OR (aZoneTempC[_uJ] <> aZoneTempC[_uJ]) OR (ABS(aZoneTempC[_uJ]) > DL_LAM_INF) THEN
                    (* 任一侧非有限：本对剔除，不计入区差 / Either side non-finite, the pair is culled *)
                    _fDiff := 0.0;          // 本对区差按零计（不参与最差对竞争） / Pair difference counted as zero
                ELSE
                    _fDiff := ABS(aZoneTempC[_uI] - aZoneTempC[_uJ]); // 当前对区差 [K] / Current pair difference [K]
                    IF _fDiff > fMaxZoneDiffK THEN
                        fMaxZoneDiffK := _fDiff; // 更新最大区差 / Update the max difference
                        uWorstPairA := _uI;  // 记录最差对 A / Record worst pair A
                        uWorstPairB := _uJ;  // 记录最差对 B / Record worst pair B
                    END_IF
                END_IF
            END_IF
        END_FOR
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 5｜确认窗无条件刷新（R40：CASE 之外每拍必调）
 *      Confirm window refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbConfirm(IN := bEnable AND (NOT _bIllegal) AND (_uValidZones >= 2)
              AND (NOT bReset) AND (fMaxZoneDiffK > fZoneDiffMaxK), PT := DL_LAM_CONFIRM); // 区差超限确认窗（bReset 电平拦截断窗复位） / Zone-diff confirm window, bReset breaks the input to reset

(*------------------------------------------------------------------------------
 * 段 6｜出口与码位（链速为 0 时跟随斜率冻结——本件无斜率输出引脚，
 *       跟随联动由调用方按 fBeltSpeedMmS = 0 自行冻结，边界声明）
 *      Outlet and codes, belt-speed freeze declared for the caller
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR _bIllegal THEN
    bValid := FALSE;                        // 未使能或输入非法：输出不可用 / Not enabled or illegal input, outputs unusable
ELSIF _uValidZones < 2 THEN
    eErr   := 16#0005_031F;                 // 故障级：有效区数 < 2 无法判区差 / Fault: fewer than two valid zones
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
ELSIF fbConfirm.Q THEN
    eErr   := 16#0005_031E;                 // 故障级：区差超限经确认窗确认 / Fault: zone difference confirmed
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bSyncOk := FALSE;                       // 失步声明 / Desynchronization declared
    bValid := TRUE;                         // 判定结果本身可用 / The verdict itself is usable
ELSE
    bSyncOk := TRUE;                        // 同步正常 / Synchronized
    IF _bCullInfo THEN
        eErr := 16#0005_01E6;               // 信息级：非有限温区已剔除 / Info: non-finite zones culled
    END_IF
    IF _bClampInfo THEN
        eErr := 16#0005_01E7;               // 信息级：区数已钳位 8 / Info: zone count clamped to 8
    END_IF
    bValid := TRUE;                         // 输出可用 / Outputs usable
END_IF
END_FUNCTION_BLOCK
