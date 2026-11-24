//==============================================================================
// 功能块：FB_DL_InverterGridSync ｜ 中文名称：逆变器并网同步条件监视
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：并网前/并网中同步条件四窗监视：电压幅值窗（网侧三相幅值
//           相对其均值的最大偏差，百分比口径，见边界行为①的窗语义披
//           露）、频率差窗（Hz）、相角差窗（归一 ±180 度）、相序窗
//           （由上游判定给出布尔），四窗全过并持续 tConfirm 才置同步
//           与合闸许可建议。阻塞掩码逐位可观测（电压/频率/相角/相序/
//           输入非法）。仅监视不控合闸（合闸执行由上位断路器逻辑裁
//           决，本件零执行输出）。规格引脚表未提供逆变器侧电压幅值输
//           入，电压窗按「网侧三相幅值相对均值的最大偏差」实现（窗判
//           据不变：偏差超容差即阻塞 bit0），网-逆幅值差需上游增补引
//           脚后切换口径（主动偏离披露，见修订历史）。
// 开源溯源 (Origin)：道莅原创实现（参考 并网同步条件公开工程惯例（电压/频率/相角/相序四窗） 分类与参数域）
// 单位表：电压[V] / 频率[Hz] / 相角[度] / 电压偏差[%] / 容差[%/Hz/度] / 确认延时[ms]
// 错误码表：16#0003_0190 信息级（网侧或逆变侧频率小于等于 0：断线/停机，
//           频率差不判，不置 bError）/ 16#0003_0191 信息级（相角差跨
//           ±180 度发生归一，提示原始差超出半圆，不置 bError）/
//           16#0003_0369 故障级（任一输入非有限，置 bError）/
//           16#0003_036A 故障级（容差组态非法：电压/频率容差非正或相
//           角容差非正、不小于 180 度，置 bError）/ 16#0003_036B 故障
//           级兜底（状态机落 ELSE 或非法状态，置 bError 并撤许可）
// 状态机：E_DL_GridSyncState（eIdle=0 / eChecking=10 / eConfirmed=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 036B 并撤许可、
//           全掩码置位（安全侧 = 合闸许可绝不残留）
// 边界行为：① 电压窗语义披露：fVoltDiffPct = max|V相 − V均值| / |V均值|
//           乘 100（三相幅值偏差窗）；V 均值绝对值小于容差（断线/无
//           压）→ 偏差置 0 且窗判失败阻塞 bit0，不做除法；② 相角差
//           归一用条件加减循环（禁 MOD：负数取余三平台不一致，R10 家
//           族），WHILE 带防死锁计数器（上限 4 次迭代），归一后仍出
//           ±180 度 → 相角窗判失败阻塞 bit2；归一发生 → 信息 0191；
//           ③ 任一输入非有限（NaN 自反判 + Inf 幅值上限判，R79）→ 故
//           障 0369 + 掩码 bit4 + bPermitClose := FALSE；④ 网侧或逆变
//           侧频率小于等于 0 → 信息 0190，频率差不判（防除零/防伪同
//           步），掩码 bit1；⑤ 相序不 OK → 掩码 bit3；⑥ 容差组态非
//           法 → 故障 036A + 掩码 bit4；⑦ 失能 → bPermitClose :=
//           FALSE（R72）、bSyncOk := FALSE、回 eIdle；⑧ 确认定时器
//           无条件周期刷新，四窗任一失守即时撤许可并回 eChecking
//           （许可是逐拍实时判定，不锁存）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.4）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_GridSyncState（归属 DL_Device，与 FB_DL_InverterGridSync 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_GridSyncState :
(
    eIdle      := 0,   // 失能/待机：许可撤、掩码全零待刷新 / Idle: permit withdrawn, mask pending refresh
    eChecking  := 10,  // 四窗评估中：确认延时未满 / Checking: windows evaluated, confirm timer running
    eConfirmed := 20,  // 同步确认：四窗全过且持续满 tConfirm / Confirmed: all windows passed for tConfirm
    eFault     := 99   // 故障兜底态：非有限/组态非法/非法状态 / Fault fallback
);
END_TYPE
FUNCTION_BLOCK FB_DL_InverterGridSync
VAR_INPUT
    afGridVoltV  : ARRAY[0..2] OF LREAL;       // 网侧三相电压幅值 [V] / Grid three-phase voltage magnitudes [V]
    fGridFreqHz  : LREAL;                      // 网侧频率 [Hz] / Grid frequency [Hz]
    fInvFreqHz   : LREAL;                      // 逆变侧频率 [Hz] / Inverter frequency [Hz]
    fGridPhaseDeg : LREAL;                     // 网侧相角 [度] / Grid phase angle [deg]
    fInvPhaseDeg : LREAL;                      // 逆变侧相角 [度] / Inverter phase angle [deg]
    fVoltTolPct  : LREAL := 10.0;              // 电压窗容差 [百分数] / Voltage window tolerance [percent]
    fFreqTolHz   : LREAL := 0.2;               // 频率窗容差 [Hz] / Frequency window tolerance [Hz]
    fPhaseTolDeg : LREAL := 10.0;              // 相角窗容差 [度]，域 0~180 开区间 / Phase window tolerance [deg], domain 0..180 open
    tConfirm     : TIME := T#2S;               // 同步确认延时 [ms] / Sync confirmation delay [ms]
    bPhaseSeqOk  : BOOL;                       // 相序判定结果，由上游给出 / Phase-sequence verdict, given by upstream
    bEnable      : BOOL;                       // 总使能 / Master enable
    bReset       : BOOL;                       // 复位，上升沿清状态与掩码 / Reset, rising edge clears state and mask
END_VAR
VAR_OUTPUT
    bSyncOk      : BOOL;                       // 四窗全过且确认延时满 / All windows passed and confirmed
    bPermitClose : BOOL;                       // 合闸许可建议，只读语义，仅监视不控合闸 / Close-permit suggestion, read-only semantics
    fVoltDiffPct : LREAL;                      // 电压幅值偏差 [百分数]（三相幅值偏差窗口径）/ Voltage deviation [percent], three-phase deviation window
    fFreqDiffHz  : LREAL;                      // 频率差 [Hz]，频率无效时保持 0 / Frequency difference [Hz], zero when invalid
    fPhaseDiffDeg : LREAL;                     // 相角差 [度]，已归一 ±180 / Phase difference [deg], normalized to plus-minus 180
    uBlockMask   : WORD;                       // 阻塞掩码：bit0 电压 / bit1 频率 / bit2 相角 / bit3 相序 / bit4 输入或组态非法 / Block mask bits
    eErr         : UDINT;                      // 错误码，0 = 无错，码位 16#0003_0190 起信息级、16#0003_0369 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid       : BOOL;                       // 监视数据可用标志，失能/故障闸显式 FALSE / Monitoring usable flag, explicit FALSE on disable/fault gates
    eState       : E_DL_GridSyncState;         // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset      : R_TRIG;                     // 复位上升沿检测实例 / Reset rising edge detector
    fbConfirm    : TON;                        // 同步确认定时器 / Sync confirmation timer
    fVoltAvg     : LREAL;                      // 三相电压均值 [V] / Mean of three-phase voltages [V]
    fVoltDev     : LREAL;                      // 当前相电压偏差绝对值 [V] / Absolute deviation of current phase [V]
    fVoltDevMax  : LREAL;                      // 三相最大偏差绝对值 [V] / Max absolute deviation across phases [V]
    uPh          : INT;                        // 相循环索引 [—] / Phase loop index
    fPhaseRaw    : LREAL;                      // 归一前相角差 [度] / Raw phase difference before normalization [deg]
    nNormGuard   : INT;                        // 归一循环防死锁计数器 [次] / Normalization loop anti-deadlock counter
    bPhaseNorm   : BOOL;                       // 本拍发生 ±180 度归一 / Normalization occurred this scan
    bVoltOk      : BOOL;                       // 电压窗通过 / Voltage window passed
    bFreqOk      : BOOL;                       // 频率窗通过（频率无效时恒假）/ Frequency window passed (always FALSE when invalid)
    bPhaseAngleOk : BOOL;                      // 相角窗独立判据（不含相序）/ Phase-angle window verdict, sequence excluded
    bPhaseOk     : BOOL;                       // 四窗综合判据：相角 ∧ 相序 / Combined window verdict: angle AND sequence
    bFreqValid   : BOOL;                       // 两侧频率均大于 0，频率差可判 / Both frequencies positive, difference judgeable
END_VAR
VAR CONSTANT
    DL_GSY_CODE_INFO_1 : UDINT := 16#0003_0190;   // 信息级槽 1（频率小于等于 0） / info slot 1
    DL_GSY_CODE_INFO_2 : UDINT := 16#0003_0191;   // 信息级槽 2（相角差归一提示） / info slot 2
    DL_GSY_CODE_FLT_1  : UDINT := 16#0003_0369;   // 故障级槽 1（输入非有限） / fault slot 1
    DL_GSY_CODE_FLT_2  : UDINT := 16#0003_036A;   // 故障级槽 2（容差组态非法） / fault slot 2
    DL_GSY_CODE_FLT_3  : UDINT := 16#0003_036B;   // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_GS_ZERO   : LREAL := 0.0;               // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_GS_EPS    : LREAL := 1.0E-6;            // 浮点比较容差 [—] / Float comparison tolerance
    DL_GS_INF    : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_GS_HALF   : LREAL := 180.0;             // 相角归一半圆 [度] / Phase normalization half-circle [deg]
    DL_GS_FULL   : LREAL := 360.0;             // 相角整圆 [度] / Phase full circle [deg]
    DL_GS_NORM_MAX : INT := 4;                 // 归一循环最大迭代 [次]，防死锁 / Normalization loop max iterations, anti-deadlock
    DL_GS_BIT0   : WORD := 16#0001;            // 掩码 bit0：电压窗 / mask bit 0: voltage window
    DL_GS_BIT1   : WORD := 16#0002;            // 掩码 bit1：频率窗 / mask bit 1: frequency window
    DL_GS_BIT2   : WORD := 16#0004;            // 掩码 bit2：相角窗 / mask bit 2: phase window
    DL_GS_BIT3   : WORD := 16#0008;            // 掩码 bit3：相序窗 / mask bit 3: phase-sequence window
    DL_GS_BIT4   : WORD := 16#0010;            // 掩码 bit4：输入或组态非法 / mask bit 4: input or config illegal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿检测在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState       := E_DL_GridSyncState.eIdle;
    eErr         := 16#0000_0000;              // 复位清码 / reset clears code
    bError       := FALSE;                     // 复位清故障 / reset clears fault
    uBlockMask   := 16#0000;                   // 掩码清零 / mask zeroed
    bSyncOk      := FALSE;                     // 同步撤 / sync withdrawn
    bPermitClose := FALSE;                     // 许可撤（安全侧）/ permit withdrawn, safe side
    bValid       := FALSE;                     // 可用撤 / usable withdrawn
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（三相电压 + 四标量：NaN 自反判 + Inf 幅值上限判，R79）
 *----------------------------------------------------------------------------*)
IF (afGridVoltV[0] <> afGridVoltV[0]) OR (ABS(afGridVoltV[0]) >= DL_GS_INF)
   OR (afGridVoltV[1] <> afGridVoltV[1]) OR (ABS(afGridVoltV[1]) >= DL_GS_INF)
   OR (afGridVoltV[2] <> afGridVoltV[2]) OR (ABS(afGridVoltV[2]) >= DL_GS_INF)
   OR (fGridFreqHz <> fGridFreqHz) OR (ABS(fGridFreqHz) >= DL_GS_INF)
   OR (fInvFreqHz <> fInvFreqHz) OR (ABS(fInvFreqHz) >= DL_GS_INF)
   OR (fGridPhaseDeg <> fGridPhaseDeg) OR (ABS(fGridPhaseDeg) >= DL_GS_INF)
   OR (fInvPhaseDeg <> fInvPhaseDeg) OR (ABS(fInvPhaseDeg) >= DL_GS_INF) THEN
    eState       := E_DL_GridSyncState.eFault;
    eErr         := DL_GSY_CODE_FLT_1;         // 故障级：任一输入非有限 / fault: non-finite input
    bError       := TRUE;                      // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid       := FALSE;                     // 输出不可用 / outputs unusable
    bSyncOk      := FALSE;                     // 同步撤 / sync withdrawn
    bPermitClose := FALSE;                     // 许可撤（R72，安全侧）/ permit withdrawn, safe side
    uBlockMask   := DL_GS_BIT4;                // 掩码 bit4：输入非法 / mask bit 4: input illegal
    fVoltDiffPct := DL_GS_ZERO;                // 偏差出口清零 / deviation outputs zeroed
    fFreqDiffHz  := DL_GS_ZERO;                // 偏差出口清零 / deviation outputs zeroed
    fPhaseDiffDeg := DL_GS_ZERO;               // 偏差出口清零 / deviation outputs zeroed
    fbConfirm(IN := FALSE, PT := tConfirm);    // 确认定时器断输入（无条件调用保持）/ confirm timer input broken, still called
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜容差组态闸（电压/频率容差非正、相角容差非正或不小于 180 度）
 *----------------------------------------------------------------------------*)
IF (fVoltTolPct <= DL_GS_EPS) OR (fFreqTolHz <= DL_GS_EPS)
   OR (fPhaseTolDeg <= DL_GS_EPS) OR (fPhaseTolDeg >= DL_GS_HALF) THEN
    eState       := E_DL_GridSyncState.eFault;
    eErr         := DL_GSY_CODE_FLT_2;         // 故障级：容差组态非法 / fault: tolerance config invalid
    bError       := TRUE;                      // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid       := FALSE;                     // 输出不可用 / outputs unusable
    bSyncOk      := FALSE;                     // 同步撤 / sync withdrawn
    bPermitClose := FALSE;                     // 许可撤（R72，安全侧）/ permit withdrawn, safe side
    uBlockMask   := DL_GS_BIT4;                // 掩码 bit4：组态非法 / mask bit 4: config illegal
    fbConfirm(IN := FALSE, PT := tConfirm);    // 确认定时器断输入（无条件调用保持）/ confirm timer input broken, still called
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜四窗评估（电压/频率/相角/相序），先算窗口再刷定时器（定时器无条件调用）
 *----------------------------------------------------------------------------*)
(*--- 5.1 电压窗：三相幅值相对均值最大偏差（见边界行为①口径披露）---*)
fVoltAvg := (afGridVoltV[0] + afGridVoltV[1] + afGridVoltV[2]) / 3.0;  // 三相均值 [V] / three-phase mean [V]
fVoltDevMax := DL_GS_ZERO;                     // 最大偏差复位 / max deviation reset
FOR uPh := 0 TO 2 DO
    fVoltDev := ABS(afGridVoltV[uPh] - fVoltAvg);  // 当前相偏差绝对值 [V] / current phase deviation [V]
    IF fVoltDev > fVoltDevMax THEN
        fVoltDevMax := fVoltDev;               // 保留最大 / keep the max
    END_IF
END_FOR
IF ABS(fVoltAvg) > DL_GS_EPS THEN
    fVoltDiffPct := fVoltDevMax / ABS(fVoltAvg) * 100.0;  // 相对偏差百分比口径，除子已判 / relative deviation, divisor checked
    bVoltOk := fVoltDiffPct <= fVoltTolPct;    // 窗判 / window verdict
ELSE
    fVoltDiffPct := DL_GS_ZERO;                // 无压/断线：偏差不可算，置 0 / no voltage: deviation not computable, zeroed
    bVoltOk := FALSE;                          // 窗判失败 / window fails
END_IF

(*--- 5.2 频率窗：两侧频率大于 0 才判差（信息 0190，防伪同步）---*)
IF (fGridFreqHz > DL_GS_EPS) AND (fInvFreqHz > DL_GS_EPS) THEN
    bFreqValid := TRUE;                        // 频率差可判 / difference judgeable
    fFreqDiffHz := fInvFreqHz - fGridFreqHz;   // 频率差 [Hz] / frequency difference [Hz]
    bFreqOk := ABS(fFreqDiffHz) <= fFreqTolHz; // 窗判 / window verdict
ELSE
    bFreqValid := FALSE;                       // 频率无效：断线/停机 / frequency invalid: offline or stopped
    fFreqDiffHz := DL_GS_ZERO;                 // 频率差出口清零 / difference output zeroed
    bFreqOk := FALSE;                          // 频率差不判，窗判失败 / difference not judged, window fails
END_IF

(*--- 5.3 相角窗：条件加减归一 ±180 度（禁 MOD，R10 家族；WHILE 防死锁计数器）---*)
fPhaseRaw := fInvPhaseDeg - fGridPhaseDeg;     // 归一前相角差 [度] / raw phase difference [deg]
fPhaseDiffDeg := fPhaseRaw;                    // 归一工作副本 / working copy
nNormGuard := 0;                               // 防死锁计数清零 / anti-deadlock counter zeroed
WHILE ((fPhaseDiffDeg > DL_GS_HALF) OR (fPhaseDiffDeg < -DL_GS_HALF)) AND (nNormGuard < DL_GS_NORM_MAX) DO
    IF fPhaseDiffDeg > DL_GS_HALF THEN
        fPhaseDiffDeg := fPhaseDiffDeg - DL_GS_FULL;   // 越上半圆减整圆 / above half-circle subtract full circle
    ELSE
        fPhaseDiffDeg := fPhaseDiffDeg + DL_GS_FULL;   // 越下半圆加整圆 / below half-circle add full circle
    END_IF
    nNormGuard := nNormGuard + 1;              // 迭代计数 / iteration count
END_WHILE
bPhaseNorm := ABS(fPhaseRaw) > DL_GS_HALF;     // 原始差超半圆即发生归一 / normalization occurred when raw beyond half-circle
bPhaseAngleOk := (ABS(fPhaseDiffDeg) <= fPhaseTolDeg) AND (nNormGuard < DL_GS_NORM_MAX);  // 相角窗独立判，归一失败亦判失败 / phase-angle window verdict, failed normalization also fails
bPhaseOk := bPhaseAngleOk AND bPhaseSeqOk;     // 四窗综合判：相角 ∧ 相序 / combined window verdict: angle AND sequence

(*--- 5.5 确认定时器：无条件周期刷新（红线 5）---*)
fbConfirm(IN := bEnable AND bVoltOk AND bFreqOk AND bPhaseOk,  // 四窗全过且使能才计时 / timer runs when enabled and all windows pass
          PT := tConfirm);                     // 确认延时 / confirmation delay

(*------------------------------------------------------------------------------
 * 段 6｜阻塞掩码逐拍装配（先清后置，逐位可观测）
 *----------------------------------------------------------------------------*)
uBlockMask := 16#0000;                         // 掩码逐拍重装配 / mask reassembled per scan
IF NOT bVoltOk THEN
    uBlockMask := uBlockMask OR DL_GS_BIT0;    // bit0：电压窗 / bit 0: voltage window
END_IF
IF NOT bFreqOk THEN
    uBlockMask := uBlockMask OR DL_GS_BIT1;    // bit1：频率窗（含频率无效）/ bit 1: frequency window, incl. invalid
END_IF
IF NOT bPhaseAngleOk THEN
    uBlockMask := uBlockMask OR DL_GS_BIT2;    // bit2：相角窗（含归一失败）/ bit 2: phase-angle window
END_IF
IF NOT bPhaseSeqOk THEN
    uBlockMask := uBlockMask OR DL_GS_BIT3;    // bit3：相序窗 / bit 3: phase-sequence window
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜状态机：CASE 含 ELSE 兜底（非法状态 → 036B + 撤许可，安全侧）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_GridSyncState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        bSyncOk := FALSE;                      // 同步撤 / sync withdrawn
        bPermitClose := FALSE;                 // 许可撤（安全侧）/ permit withdrawn, safe side
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_GridSyncState.eChecking;    // 使能进评估 / enable enters checking
        END_IF

    E_DL_GridSyncState.eChecking:
        IF NOT bEnable THEN
            eState := E_DL_GridSyncState.eIdle;        // 失能回待机 / disable returns to idle
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
            bPermitClose := FALSE;             // 许可撤（安全侧）/ permit withdrawn, safe side
            bSyncOk := FALSE;                  // 同步撤 / sync withdrawn
        ELSE
            bValid := TRUE;                    // 评估态监视数据可用 / monitoring usable in checking
            eErr := 16#0000_0000;              // 评估态先清码 / checking clears code first
            IF bPhaseNorm THEN
                eErr := DL_GSY_CODE_INFO_2;    // 信息级：相角差跨 ±180 度归一 / info: phase normalized across half-circle
            END_IF
            IF NOT bFreqValid THEN
                eErr := DL_GSY_CODE_INFO_1;    // 信息级：频率无效优先于归一提示 / info: invalid frequency outranks normalization hint
            END_IF
            bError := FALSE;                   // 信息级不置 bError / info never raises bError
            bSyncOk := FALSE;                  // 未确认前同步撤 / sync withdrawn before confirmation
            bPermitClose := FALSE;             // 未确认前许可撤 / permit withdrawn before confirmation
            IF fbConfirm.Q THEN
                eState := E_DL_GridSyncState.eConfirmed;   // 确认延时满进确认态 / delay elapsed enters confirmed
            END_IF
        END_IF

    E_DL_GridSyncState.eConfirmed:
        IF NOT bEnable THEN
            eState := E_DL_GridSyncState.eIdle;
            bValid := FALSE;
            bPermitClose := FALSE;             // 许可撤（安全侧）/ permit withdrawn, safe side
            bSyncOk := FALSE;
        ELSE
            bValid := TRUE;                    // 确认态监视数据可用 / monitoring usable in confirmed
            eErr := 16#0000_0000;              // 先清码 / clear code first
            IF bPhaseNorm THEN
                eErr := DL_GSY_CODE_INFO_2;    // 信息级：归一提示 / info: normalization hint
            END_IF
            IF NOT bFreqValid THEN
                eErr := DL_GSY_CODE_INFO_1;    // 信息级：频率无效优先 / info: invalid frequency outranks
            END_IF
            bError := FALSE;                   // 信息级不置 bError / info never raises bError
            bSyncOk := fbConfirm.Q;            // 同步逐拍实时判定，不锁存 / sync judged per scan, not latched
            bPermitClose := fbConfirm.Q AND bFreqValid;  // 许可逐拍实时判定，频率无效不许可 / permit judged per scan, invalid frequency blocks
            IF NOT fbConfirm.Q THEN
                eState := E_DL_GridSyncState.eChecking;    // 四窗任一失守回评估（定时器自动重启）/ any window lost returns to checking
            END_IF
        END_IF

    ELSE
        eState := E_DL_GridSyncState.eFault;   // 非法状态兜底 / illegal-state fallback
        eErr   := DL_GSY_CODE_FLT_3;           // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        bSyncOk := FALSE;                      // 同步撤 / sync withdrawn
        bPermitClose := FALSE;                 // 许可撤（安全侧，绝不残留）/ permit withdrawn, never residual
END_CASE
END_FUNCTION_BLOCK
