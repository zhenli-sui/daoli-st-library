//==============================================================================
// 功能块：FB_DL_HealthAggregator ｜ 中文名称：多源 NE107 健康聚合仲裁
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：多源 NE107 健康态聚合仲裁件——对至多 16 路健康源按枚举序号
//           "最差者胜"（编号最小者优先）聚合出总健康态，并给出最差源
//           下标与失效/维护两级计数。HMI 顶部健康横幅的单一事实源。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现
// 单位表：健康态[—]（E_DL_Ne107Status 序号）／源路数[路]／下标[路]
// 错误码表：16#0003_017A 信息级（源数 > 16 已钳位 16 照常仲裁，不置
//           bError）/ 16#0003_017B 信息级（全部源均为 eUnknown，输出
//           eUnknown 是合法结论非错误）/ 16#0003_0348 故障级（源数为 0，
//           无可仲裁对象，置 bError）/ 16#0003_0349 预留禁用（不得挪用）/
//           16#0003_034A 故障级兜底（置 bError，本件纯当拍仲裁无状态机，
//           兜底码保留给未来状态化扩展误用拦截）
// 状态机：N/A（纯当拍仲裁，无状态机、无迟滞、无跨拍锁存；聚合无迟滞，
//           调用方如需防抖自行组合 FB_DL_SignalDebounce 后再接入 aHealth）
// 边界行为：① uSourceCount > 16 → 钳 16 + 信息 017A，数组访问一律有
//           uIdx <= 16 二次闸（字面量上界与 DL_HEALTH_MAX 一致性由本件
//           承担验证责任，两处同源 16）；② uSourceCount = 0 → 故障 0348、
//           eOverall := eUnknown、bValid := FALSE；③ 全部源 eUnknown →
//           输出 eUnknown + 信息 017B（合法结论，不置故障）；④ bArbitrate
//           = FALSE → 本拍不仲裁，eOverall := eUnknown、bValid := FALSE
//           （不冻结旧值，横幅显示"未仲裁"口径）；⑤ 数组访问下标越界
//           理论不可能（钳位 + 二次闸双保险），仍以防御闸兜底。
// 依赖纪律：仅 Standard.library + 同库契约 E_DL_Ne107Status（属主
//           I_DL_DeviceHealth.st，只引用不重声明，R70）；零同层调用。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · T2-8 NE107 待挖项落地）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：HMI_Health(IN := aHealth, uSourceCount := uN, bArbitrate := TRUE);
 *   HMI 横幅：IF fbHMI.eOverall <= E_DL_Ne107Status.eCheckFunction THEN
 *                 红色横幅; ELSIF fbHMI.eOverall <= eOutOfSpec THEN 黄色; 其余态类似降档
 *   仅当 bValid = TRUE 且 eErr 属信息级（017A/017B）时聚合结果可用于
 *   画面/报表；eErr = 0348 时横幅显示"组态错误"。
 *-----------------------------------------------------------------------------*)
FUNCTION_BLOCK FB_DL_HealthAggregator
VAR_INPUT
    aHealth     : ARRAY[1..16] OF E_DL_Ne107Status; // 各源健康态 [—]，下标 1..16，超编路填 eUnknown / Health status per source, index 1..16, over-count lanes fill eUnknown
    uSourceCount: UINT;                     // 实际源数 [路]，有效域 0..16，> 16 钳位照仲裁 / Actual source count [lanes], 0..16, clamped above
    bArbitrate  : BOOL;                     // 仲裁使能 [—]，FALSE = 本拍不仲裁输出 eUnknown / Arbitration enable, FALSE = skip and report eUnknown
END_VAR
VAR_OUTPUT
    eOverall    : E_DL_Ne107Status;         // 聚合结果 [—]，编号最小者优先即最差者胜 / Aggregated status, lowest ordinal wins, the worst prevails
    uWorstIdx   : UINT;                     // 最差源下标 [路]，0 = 无（未仲裁或源数为 0） / Worst source index [lanes], 0 = none
    uFailCount  : UINT;                     // eFailure 源计数 [路] / Count of eFailure sources [lanes]
    uMaintCount : UINT;                     // eMaintenanceReq 源计数 [路] / Count of eMaintenanceReq sources [lanes]
    eErr        : UDINT;                    // 错误码，0 = 无错 / Error code, 0 = no error
    bError      : BOOL;                     // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid      : BOOL;                     // 输出可用标志 / Outputs usable flag
END_VAR
VAR CONSTANT
    DL_HEALTH_MAX : UINT := 16;             // 数组上界 [路]，与接口字面量上界 16 同源，改动须同步 / Array ceiling [lanes], same source as the literal bound 16, change both together
END_VAR
VAR
    uCountEff   : UINT;                     // 钳位后的生效源数 [路] / Effective clamped source count [lanes]
    uIdx        : UINT;                     // 扫描循环下标 [路] / Scan loop index [lanes]
    eWorst      : E_DL_Ne107Status;         // 当前最差态暂存 [—] / Staged worst status so far
    uWorstStaged: UINT;                     // 当前最差源下标暂存 [路] / Staged worst index so far
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：纯当拍仲裁，全部输出每拍重算，无保持量、无首扫分支
 *      Pure per-scan arbitration, every output recomputed, no held state
 *-----------------------------------------------------------------------------*)
eOverall     := E_DL_Ne107Status.eUnknown;   // 聚合结果预置未知 / Aggregated result preset unknown
uWorstIdx    := 0;                           // 最差源下标预置无 / Worst index preset to none
uFailCount   := 0;                           // 失效计数清零 / Failure count cleared
uMaintCount  := 0;                           // 维护计数清零 / Maintenance count cleared
eErr         := 16#0000_0000;                // 错误码每拍重算 / Error code recomputed
bError       := FALSE;                       // 故障标志每拍重算 / Fault flag recomputed
bValid       := FALSE;                       // 可用标志每拍重算 / Usable flag recomputed
uCountEff    := 0;                           // 生效源数预置零 / Effective count preset zero
eWorst       := E_DL_Ne107Status.eUnknown;   // 最差态暂存预置未知 / Staged worst preset unknown
uWorstStaged := 0;                           // 最差下标暂存预置零 / Staged worst index preset zero

(*------------------------------------------------------------------------------
 * 段 2｜仲裁使能与源数闸门（0 → 故障；> 16 → 钳位 + 信息）
 *      Arbitration enable and source-count gates
 *-----------------------------------------------------------------------------*)
IF NOT bArbitrate THEN
    eOverall := E_DL_Ne107Status.eUnknown;  // 未仲裁口径：输出未知 / Not arbitrating, report unknown
    RETURN;                                 // bValid 保持 FALSE / bValid stays FALSE
END_IF
IF uSourceCount = 0 THEN
    eOverall := E_DL_Ne107Status.eUnknown;  // 无可仲裁对象 / Nothing to arbitrate
    eErr   := 16#0003_0348;                 // 故障级：源数为 0 / Fault: zero sources
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
    RETURN;
END_IF
IF uSourceCount > DL_HEALTH_MAX THEN
    uCountEff := DL_HEALTH_MAX;             // 源数钳位到 16 路照仲裁 / Count clamped to 16 lanes
    eErr := 16#0003_017A;                   // 信息级：源数已钳位（不置 bError） / Info: count clamped, no fault flag
ELSE
    uCountEff := uSourceCount;              // 合法源数原值生效 / Valid count applied as-is
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜最差者胜扫描：编号最小者优先（eFailure=0 最差，eOk=40 最好）；
 *       下标访问带 uIdx <= 16 二次闸（R 二次闸纪律），并统计两级计数
 *       Worst-prevails scan with the secondary index gate and two counters
 *-----------------------------------------------------------------------------*)
FOR uIdx := 1 TO uCountEff DO
    IF uIdx <= DL_HEALTH_MAX THEN           // 二次闸：越界访问结构性不可能 / Secondary gate, out-of-bounds structurally impossible
        IF aHealth[uIdx] < eWorst THEN      // 序号更小 = 更差 / Lower ordinal means worse
            eWorst := aHealth[uIdx];        // 更新最差态 / Update the worst status
            uWorstStaged := uIdx;           // 记录最差源下标 / Record the worst source index
        END_IF
        IF aHealth[uIdx] = E_DL_Ne107Status.eFailure THEN
            uFailCount := uFailCount + 1;   // 失效源计数递增 / Failure counter increment
        END_IF
        IF aHealth[uIdx] = E_DL_Ne107Status.eMaintenanceReq THEN
            uMaintCount := uMaintCount + 1; // 维护源计数递增 / Maintenance counter increment
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 4｜出口：全未知声明 + 可用性
 *      Outlet: all-unknown notice and usability
 *-----------------------------------------------------------------------------*)
eOverall  := eWorst;                        // 聚合结果出口 / Aggregated result outlet
uWorstIdx := uWorstStaged;                  // 最差源下标出口 / Worst index outlet
IF eWorst = E_DL_Ne107Status.eUnknown THEN
    eErr := 16#0003_017B;                   // 信息级：全部源未知，合法结论（不置 bError） / Info: all sources unknown, a legal conclusion
END_IF
bValid := TRUE;                             // 输出可用（含信息级情形） / Outputs usable, including info-level cases
END_FUNCTION_BLOCK
