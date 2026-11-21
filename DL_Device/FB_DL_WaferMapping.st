//==============================================================================
// 功能块：FB_DL_WaferMapping ｜ 中文名称：晶圆花篮（FOUP）Mapping 传感器序列解析
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：25 槽在位传感器序列解析 → 逐槽片位图 + 空位/单片/斜插（eCross，
//           相邻槽同时置位）识别 + 在片数统计。序列经 tScanTimeout 稳
//           定判定后才置映射有效（稳定期内任何跳变即重新计时，防抖）。
//           全槽为 0 = 合法空盒，不判故障。只解析与判定，不做机械手
//           动作（取放由上位调度，本件零执行输出）。规格引脚表未提供
//           厚度量测输入，eDouble（双片）判据在本版不可达：枚举保留
//           语义槽，fDoubleThickPct 仅作组态域校验（小于 1.0 判组态非
//           法），待厚度型传感器引脚增补后启用双片判据（主动偏离披露，
//           见修订历史）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：槽数[槽] / 槽索引[—] / 厚度倍率[倍] / 扫描稳定超时[ms] / 计数[片]
// 错误码表：16#0003_0196 信息级（存在斜插异常槽但映射整体可判，不置
//           bError）/ 16#0003_0197 信息级（序列含噪跳变提示：同槽连续
//           两拍翻转，不置 bError）/ 16#0003_0372 故障级（在用槽数非
//           法、厚度倍率组态非法或非有限，或全通道同拍跳变（传感器串
//           扰/接线故障），置 bError）/ 16#0003_0373 故障级（片位索引
//           越界：内部访问越界防御槽，正常流程不可达，置 bError）/
//           16#0003_0374 故障级兜底（状态机落 ELSE 或非法状态，置
//           bError 并撤映射）
// 状态机：E_DL_WaferMapState（eIdle=0 / eSampling=10 / eMapped=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 0374 并撤映射
//           bMapValid（安全侧：无效映射不得被上位取用）
// 边界行为：① nSlotCount 域 1~25，越界 → 故障 0372；数组访问统一
//           IF nIdx >= 0 AND nIdx < nSlotCount 界检，邻位索引另加
//           nIdx < 25 物理界检（防御槽 0373：正常流程不可达，命中即
//           内部越界防御）；② 全槽 0 = 合法空盒，正常出图，不判故障
//           （空 FOUP 正常工况）；③ 斜插判据：本槽置位且相邻槽（i−1/
//           i+1，双侧边界防护）也置位 → 两槽均判 eCross；④ 全通道同
//           拍跳变（上一拍全 0 本拍全 1 或反之）→ 故障 0372（传感器
//           串扰/接线故障），映射撤，故障锁存待 bReset 或失能恢复；
//           ⑤ 异常但可判（有斜插槽）→ 信息 0196；同槽连续两拍翻转 →
//           信息 0197（含噪跳变提示，优先级低于 0196 不覆盖）；⑥ 厚
//           度倍率组态非法（小于 1.0）或非有限 → 故障 0372（数据不可
//           信同语义，复用组态槽不新占码位）；⑦ 失能 → 撤映射、计数
//           清零；⑧ 序列稳定（tScanTimeout 内无跳变）才置 bMapValid，
//           稳定定时器经跳变「断输入一拍」重启（R40 家族）；⑨ 上电
//           首拍 bMapValid := FALSE。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.7）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_SlotKind / E_DL_WaferMapState（归属 DL_Device，与 FB_DL_WaferMapping 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SlotKind :
(
    eEmpty   := 0,   // 空位：传感器未置位 / Empty: sensor off
    eSingle  := 1,   // 单片：本槽置位且相邻无片 / Single: occupied with no occupied neighbor
    eDouble  := 2,   // 双片（斜插厚度型）：本版不可达，语义保留槽 / Double wafer: unreachable this version, semantic slot reserved
    eCross   := 3,   // 斜插：本槽与相邻槽同时置位 / Crossed wafer: occupied with an occupied neighbor
    eUnknown := 4    // 未知：本版 BOOL 序列不可达，语义保留槽 / Unknown: unreachable with BOOL sequence this version
);
END_TYPE
TYPE E_DL_WaferMapState :
(
    eIdle     := 0,   // 失能/待机：映射撤、计数清零 / Idle: mapping withdrawn, counts zeroed
    eSampling := 10,  // 采样中：序列未稳定，映射暂不可取用 / Sampling: sequence not stable, mapping not usable yet
    eMapped   := 20,  // 映射有效：序列稳定期满，结果可取用 / Mapped: stable period elapsed, results usable
    eFault    := 99   // 故障兜底态：组态非法/串扰/非法状态，映射撤 / Fault fallback, mapping withdrawn
);
END_TYPE
FUNCTION_BLOCK FB_DL_WaferMapping
VAR_INPUT
    abSlotSensor  : ARRAY[0..24] OF BOOL;      // 逐槽在位信号，长度固定 25 [—] / Per-slot wafer-present signals, fixed length 25
    nSlotCount    : INT := 25;                 // 在用槽数 [槽]，1~25 / Slots in use, 1~25
    fDoubleThickPct : LREAL := 1.5;            // 厚度倍率判双片 [倍]，本版仅做组态域校验 / Thickness ratio for double detection, config-validated only this version
    tScanTimeout  : TIME := T#10S;             // 扫描稳定超时 [ms]，稳定期满映射生效 / Scan stability timeout [ms]
    bEnable       : BOOL;                      // 总使能 / Master enable
    bReset        : BOOL;                      // 复位，上升沿清状态与计数 / Reset, rising edge clears state and counters
END_VAR
VAR_OUTPUT
    abSlotOccupied : ARRAY[0..24] OF BOOL;     // 逐槽在位映射（稳定期内可取用）/ Per-slot occupancy map, usable while stable
    aeSlotKind    : ARRAY[0..24] OF E_DL_SlotKind;  // 逐槽片型判定 / Per-slot wafer kind verdict
    nOccupiedCount : INT;                      // 在片数 [片] / Occupied slot count
    bMapValid     : BOOL;                      // 映射有效标志：序列稳定期满且无故障 / Mapping valid: stable period elapsed and no fault
    bAnyAnomaly   : BOOL;                      // 存在异常槽（斜插等）但映射整体可判 / Any anomalous slot while map still judgeable
    nAnomalyCount : INT;                       // 异常槽数 [槽] / Anomalous slot count
    eErr          : UDINT;                     // 错误码，0 = 无错，码位 16#0003_0196 起信息级、16#0003_0372 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError        : BOOL;                      // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                      // 判定数据可用标志，失能/故障闸显式 FALSE / Verdict usable flag, explicit FALSE on disable/fault gates
    eState        : E_DL_WaferMapState;        // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset       : R_TRIG;                    // 复位上升沿检测实例 / Reset rising edge detector
    fbStableT     : TON;                       // 序列稳定定时器（跳变断输入一拍重启）/ Sequence stability timer, kicked on change
    bStableKick   : BOOL;                      // 稳定定时器断输入一拍标志（R40 家族）/ Stability timer one-scan kick flag
    abPrev        : ARRAY[0..24] OF BOOL;      // 上一拍逐槽快照（跳变检测）/ Previous-scan per-slot snapshot for change detection
    abChg         : ARRAY[0..24] OF BOOL;      // 本拍逐槽跳变标志 / Per-slot change flag this scan
    abChgPrev     : ARRAY[0..24] OF BOOL;      // 上一拍逐槽跳变标志（含噪翻转检测）/ Previous-scan change flags for flap detection
    nChgCount     : INT;                       // 本拍跳变槽总数 [槽] / Total changed slots this scan
    bAllSameNow   : BOOL;                      // 本拍全槽同值判据 / All slots equal this scan
    bAllValNow    : BOOL;                      // 本拍全槽同值时的值 / The common value when all equal this scan
    bAllSamePrev  : BOOL;                      // 上一拍全槽同值判据 / All slots equal previous scan
    bAllValPrev   : BOOL;                      // 上一拍全槽同值时的值 / The common value when all equal previous scan
    bCrossJump    : BOOL;                      // 全通道同拍跳变（串扰判据）/ Whole-array same-scan jump (crosstalk criterion)
    bNoiseFlap    : BOOL;                      // 含噪跳变：同槽连续两拍翻转 / Noisy flap: same slot toggling two scans in a row
    uIdx          : INT;                       // 槽循环索引 [—] / Slot loop index
    nNb           : INT;                       // 邻位槽索引 [—] / Neighbor slot index
    bNbOccupied   : BOOL;                      // 邻位在位判据（双侧边界防护）/ Neighbor occupied predicate, double-side bounded
    nOccCount     : INT;                       // 在片数暂存 [片] / Occupied count staging
    nAnomCount    : INT;                       // 异常槽数暂存 [槽] / Anomaly count staging
    bPrevValid    : BOOL;                      // 上一拍快照有效标志（首拍跳变检测屏蔽）/ Previous snapshot valid, first-scan jump masked
END_VAR
VAR CONSTANT
    DL_WMAP_CODE_INFO_1 : UDINT := 16#0003_0196;  // 信息级槽 1（异常但映射可判） / info slot 1
    DL_WMAP_CODE_INFO_2 : UDINT := 16#0003_0197;  // 信息级槽 2（序列含噪跳变提示） / info slot 2
    DL_WMAP_CODE_FLT_1  : UDINT := 16#0003_0372;  // 故障级槽 1（槽数非法或串扰跳变） / fault slot 1
    DL_WMAP_CODE_FLT_2  : UDINT := 16#0003_0373;  // 故障级槽 2（片位索引越界防御） / fault slot 2
    DL_WMAP_CODE_FLT_3  : UDINT := 16#0003_0374;  // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_WM_SLOT_MAX : INT := 25;                // 槽数硬上限 [槽]，数组物理长度 / Slot hard ceiling, array physical length
    DL_WM_ZERO     : INT := 0;                 // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_WM_ONE      : INT := 1;                 // 一值常量，避免裸字面量 [—] / One constant, avoids a bare literal
    DL_WM_RATIO_MIN : LREAL := 1.0;            // 厚度倍率组态下限 [倍] / Thickness ratio config floor
    DL_WM_INF      : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿与稳定定时器在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbStableT(IN := bEnable AND (NOT bStableKick),  // 稳定计时：使能且本拍无跳变断输入（R40 家族）/ stability timing, kicked on any change
          PT := tScanTimeout);                 // 稳定期门槛 / stability threshold
bStableKick := FALSE;                          // kick 标志单拍自清（跳变时由采样段重置位）/ kick self-clears, re-set on change

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState     := E_DL_WaferMapState.eIdle;
    eErr       := 16#0000_0000;                // 复位清码 / reset clears code
    bError     := FALSE;                       // 复位清故障 / reset clears fault
    bMapValid  := FALSE;                       // 映射撤 / mapping withdrawn
    bAnyAnomaly := FALSE;                      // 异常标志清 / anomaly flag cleared
    nAnomalyCount := DL_WM_ZERO;               // 异常计数清零 / anomaly count zeroed
    nOccupiedCount := DL_WM_ZERO;              // 在片数清零 / occupied count zeroed
    bPrevValid := FALSE;                       // 首拍跳变检测重新屏蔽 / first-scan jump masked again
    FOR uIdx := 0 TO 24 DO
        abPrev[uIdx] := FALSE;                 // 上一拍快照清零 / previous snapshot zeroed
        abChg[uIdx] := FALSE;                  // 跳变标志清零 / change flags zeroed
        abChgPrev[uIdx] := FALSE;              // 上一拍跳变标志清零 / previous change flags zeroed
        abSlotOccupied[uIdx] := FALSE;         // 映射输出清零 / occupancy outputs zeroed
        aeSlotKind[uIdx] := E_DL_SlotKind.eEmpty;  // 片型输出清空位 / kind outputs to empty
    END_FOR
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与非有限闸（槽数域 / 厚度倍率域，非有限复用 0372 不新占码位）
 *----------------------------------------------------------------------------*)
IF (nSlotCount < DL_WM_ONE) OR (nSlotCount > DL_WM_SLOT_MAX)
   OR (fDoubleThickPct <> fDoubleThickPct) OR (ABS(fDoubleThickPct) >= DL_WM_INF)
   OR (fDoubleThickPct < DL_WM_RATIO_MIN) THEN
    eState    := E_DL_WaferMapState.eFault;
    eErr      := DL_WMAP_CODE_FLT_1;               // 故障级：槽数非法或厚度倍率组态非法/非有限 / fault: slot count or ratio config invalid
    bError    := TRUE;                         // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid    := FALSE;                        // 输出不可用 / outputs unusable
    bMapValid := FALSE;                        // 映射撤（安全侧）/ mapping withdrawn, safe side
    bAnyAnomaly := FALSE;                      // 故障态不判异常 / anomaly not judged in fault
    nAnomalyCount := DL_WM_ZERO;               // 异常计数清零 / anomaly count zeroed
    nOccupiedCount := DL_WM_ZERO;              // 在片数清零 / occupied count zeroed
    fbStableT(IN := FALSE, PT := tScanTimeout);  // 稳定定时器断输入（无条件调用保持）/ stability timer input broken, still called
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜逐槽界检快照对比：跳变标志、全同判据、串扰判据（防御槽 0373）
 *----------------------------------------------------------------------------*)
nChgCount := DL_WM_ZERO;                       // 跳变计数清零 / change count zeroed
bAllSameNow := TRUE;                           // 全同判据种子 / all-equal predicate seed
bAllValNow := abSlotSensor[0];                 // 全同参考值种子 / all-equal reference seed
FOR uIdx := 0 TO 24 DO
    IF (uIdx < DL_WM_ZERO) OR (uIdx >= DL_WM_SLOT_MAX) THEN
        eState := E_DL_WaferMapState.eFault;   // 片位索引越界（内部防御，正常不可达）/ slot index out of bounds, defensive
        eErr := DL_WMAP_CODE_FLT_2;                // 故障级：片位索引越界 / fault: slot index out of bounds
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        bMapValid := FALSE;                    // 映射撤（安全侧）/ mapping withdrawn, safe side
        fbStableT(IN := FALSE, PT := tScanTimeout);  // 稳定定时器断输入（无条件调用保持）/ stability timer input broken
        RETURN;
    END_IF
    IF abSlotSensor[uIdx] <> bAllValNow THEN
        bAllSameNow := FALSE;                  // 有异值即非全同 / any differing value breaks all-equal
    END_IF
    abChg[uIdx] := bPrevValid AND (abSlotSensor[uIdx] <> abPrev[uIdx]);  // 逐槽跳变标志（首拍屏蔽）/ per-slot change flag, masked on first scan
    IF abChg[uIdx] THEN
        nChgCount := nChgCount + DL_WM_ONE;    // 跳变槽计数 / count changed slot
        bStableKick := TRUE;                   // 任一跳变：稳定定时器断输入一拍重启 / any change kicks the stability timer
    END_IF
END_FOR
bCrossJump := bPrevValid AND bAllSameNow AND bAllSamePrev AND (bAllValNow <> bAllValPrev);  // 全通道同拍跳变判据 / whole-array jump predicate
bNoiseFlap := FALSE;                           // 含噪判据复位 / noise criterion reset
FOR uIdx := 0 TO 24 DO
    IF abChg[uIdx] AND abChgPrev[uIdx] THEN
        bNoiseFlap := TRUE;                    // 同槽连续两拍翻转 → 信息 0197 / same slot toggling two scans in a row
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 5｜分类与计数：逐槽界检 + 邻位双侧边界防护，斜插两槽均判 eCross
 *----------------------------------------------------------------------------*)
nOccCount := DL_WM_ZERO;                       // 在片数清零 / occupied count zeroed
nAnomCount := DL_WM_ZERO;                      // 异常数清零 / anomaly count zeroed
FOR uIdx := 0 TO 24 DO
    IF uIdx < nSlotCount THEN
        abSlotOccupied[uIdx] := abSlotSensor[uIdx];  // 在用槽：照抄传感器 / in-use slot: copy sensor
        IF abSlotSensor[uIdx] THEN
            bNbOccupied := FALSE;              // 邻位在位判据复位 / neighbor predicate reset
            nNb := uIdx - DL_WM_ONE;           // 左邻索引 / left neighbor index
            IF (nNb >= DL_WM_ZERO) AND (nNb < nSlotCount) AND (nNb < DL_WM_SLOT_MAX) THEN
                IF abSlotSensor[nNb] THEN
                    bNbOccupied := TRUE;       // 左邻在位 / left neighbor occupied
                END_IF
            END_IF
            nNb := uIdx + DL_WM_ONE;           // 右邻索引 / right neighbor index
            IF (nNb >= DL_WM_ZERO) AND (nNb < nSlotCount) AND (nNb < DL_WM_SLOT_MAX) THEN
                IF abSlotSensor[nNb] THEN
                    bNbOccupied := TRUE;       // 右邻在位 / right neighbor occupied
                END_IF
            END_IF
            IF bNbOccupied THEN
                aeSlotKind[uIdx] := E_DL_SlotKind.eCross;  // 斜插：相邻同时置位 / crossed: adjacent occupied
                nAnomCount := nAnomCount + DL_WM_ONE;      // 异常槽计数 / count anomalous slot
            ELSE
                aeSlotKind[uIdx] := E_DL_SlotKind.eSingle; // 单片：邻位无片 / single: no occupied neighbor
            END_IF
            nOccCount := nOccCount + DL_WM_ONE;        // 在片计数 / count occupied slot
        ELSE
            aeSlotKind[uIdx] := E_DL_SlotKind.eEmpty;  // 空位 / empty
        END_IF
    ELSE
        abSlotOccupied[uIdx] := FALSE;         // 超出在用槽数：按空位出图 / beyond in-use count: mapped empty
        aeSlotKind[uIdx] := E_DL_SlotKind.eEmpty;  // 片型空位 / kind empty
    END_IF
END_FOR
nOccupiedCount := nOccCount;                   // 在片数出口 / occupied count output
nAnomalyCount := nAnomCount;                   // 异常数出口 / anomaly count output
bAnyAnomaly := nAnomCount > DL_WM_ZERO;        // 异常标志 / anomaly flag

(*------------------------------------------------------------------------------
 * 段 6｜历史快照滚动：本拍值与跳变标志存为上一拍（供下拍对比）
 *----------------------------------------------------------------------------*)
FOR uIdx := 0 TO 24 DO
    abPrev[uIdx] := abSlotSensor[uIdx];        // 滚动值快照 / roll value snapshot
    abChgPrev[uIdx] := abChg[uIdx];            // 滚动跳变快照 / roll change snapshot
END_FOR
bPrevValid := TRUE;                            // 快照有效 / snapshot valid
bAllSamePrev := bAllSameNow;                   // 滚动全同判据 / roll all-equal predicate
bAllValPrev := bAllValNow;                     // 滚动全同参考值 / roll all-equal reference

(*------------------------------------------------------------------------------
 * 段 7｜状态机：CASE 含 ELSE 兜底（非法状态 → 0374 + 撤映射，安全侧）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_WaferMapState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        bMapValid := FALSE;                    // 映射撤 / mapping withdrawn
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_WaferMapState.eSampling;    // 使能进采样 / enable enters sampling
            bPrevValid := FALSE;               // 重新首拍屏蔽跳变检测 / mask jump detection on fresh start
            bStableKick := TRUE;               // 稳定定时器重启 / stability timer restarted
        END_IF

    E_DL_WaferMapState.eSampling:
        bValid := TRUE;                        // 采样态判定数据可用（bMapValid 仍假）/ verdict usable in sampling, map still not valid
        bMapValid := FALSE;                    // 序列未稳定，映射暂不可取用 / sequence not stable, mapping not usable
        IF NOT bEnable THEN
            eState := E_DL_WaferMapState.eIdle;        // 失能回待机 / disable returns to idle
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
        ELSIF bCrossJump THEN
            eState := E_DL_WaferMapState.eFault;       // 全通道同拍跳变进故障（锁存待复位）/ whole-array jump enters fault, latched
            eErr := DL_WMAP_CODE_FLT_1;            // 故障级：传感器串扰/接线故障 / fault: crosstalk or wiring
            bError := TRUE;                    // 故障级必置 bError / fault-class pairs with bError
            bMapValid := FALSE;                // 映射撤（安全侧）/ mapping withdrawn, safe side
        ELSIF fbStableT.Q THEN
            eState := E_DL_WaferMapState.eMapped;      // 稳定期满映射生效 / stability elapsed, mapping valid
        END_IF

    E_DL_WaferMapState.eMapped:
        bValid := TRUE;                        // 映射态判定数据可用 / verdict usable in mapped
        bMapValid := TRUE;                     // 映射有效 / mapping valid
        IF NOT bEnable THEN
            eState := E_DL_WaferMapState.eIdle;
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
            bMapValid := FALSE;                // 映射撤 / mapping withdrawn
        ELSIF bCrossJump THEN
            eState := E_DL_WaferMapState.eFault;       // 全通道同拍跳变进故障（锁存待复位）/ whole-array jump enters fault, latched
            eErr := DL_WMAP_CODE_FLT_1;
            bError := TRUE;
            bMapValid := FALSE;                // 映射撤（安全侧）/ mapping withdrawn, safe side
        ELSIF nChgCount > DL_WM_ZERO THEN
            eState := E_DL_WaferMapState.eSampling;    // 稳定期内出现跳变回采样 / change during stable period returns to sampling
            bMapValid := FALSE;                // 映射暂撤 / mapping withdrawn temporarily
        END_IF

    E_DL_WaferMapState.eFault:
        bValid := FALSE;                       // 故障闸显式不可用 / explicit FALSE on fault gate
        bMapValid := FALSE;                    // 映射撤（安全侧）/ mapping withdrawn, safe side
        eErr := DL_WMAP_CODE_FLT_1;                // 故障级保持（串扰或组态，见进入路径）/ fault held
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        IF NOT bEnable THEN
            eState := E_DL_WaferMapState.eIdle;        // 仅失能解锁（串扰故障锁存，见边界行为④；bReset 走段 2 路径）/ only disable unlocks, crosstalk latched, reset via section 2
        END_IF

    ELSE
        eState := E_DL_WaferMapState.eFault;   // 非法状态兜底 / illegal-state fallback
        eErr := DL_WMAP_CODE_FLT_3;                // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        bMapValid := FALSE;                    // 映射撤（安全侧，无效映射不得被取用）/ mapping withdrawn, safe side
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜信息级收口：0196 异常可判 与 0197 含噪提示（均不置 bError）
 *----------------------------------------------------------------------------*)
IF bAnyAnomaly AND (eState = E_DL_WaferMapState.eMapped) THEN
    eErr := DL_WMAP_CODE_INFO_1;               // 信息级：存在斜插异常但映射整体可判 / info: anomaly present, map judgeable
    bError := FALSE;                           // 信息级不置 bError / info never raises bError
END_IF
IF bNoiseFlap AND (eState = E_DL_WaferMapState.eSampling OR eState = E_DL_WaferMapState.eMapped) THEN
    eErr := DL_WMAP_CODE_INFO_2;               // 信息级：同槽连续两拍翻转含噪提示 / info: noisy same-slot flap
    bError := FALSE;                           // 信息级不置 bError / info never raises bError
END_IF
END_FUNCTION_BLOCK
