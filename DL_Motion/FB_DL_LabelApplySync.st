//==============================================================================
// 功能块：FB_DL_LabelApplySync ｜ 中文名称：贴标同步出标控制
// 所属子库：DL_Motion ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：卷料贴标机的出标同步件。编码器累计脉冲差分求卷材位移（差分按带符号减法，
//           32 位回绕时符号自然正确，禁止按绝对值比较），按标签节距分频出标扳机，扣
//           除出标提前量，并给出相位误差、线速度与低速禁止出标判据。低速时相位估算不
//           可靠，硬出标会贴歪，故低速一律抑制出标并提示。本件只输出出标扳机与诊断
//           量，不改轴状态、不发运动指令（轴状态唯一属主是运动层，T1-6 纪律），也不
//           驱动贴标头气缸与真空（执行器归设备层）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：累计脉冲[脉冲] / 脉冲当量[脉冲每毫米] / 节距与提前量[mm] / 线速度[米每分] /
//         相位误差[mm] / 触发脉宽[ms] / 扫描间隔[ms] / 出标计数[张]
// 错误码表：16#0004_01ED 信息级（提前量超一个节距被饱和钳位，钳到节距，不置 bError）/
//           16#0004_01EE 信息级（编码器低速，相位估算不可靠，暂停出标，不置 bError）/
//           16#0004_030F 故障级（脉冲当量或标签节距组态非法，置 bError，先判后除）/
//           16#0004_0310 故障级（输入非有限，置 bError）/ 16#0004_0311 故障级兜底
//           （状态机落 ELSE 非法状态，置 bError）。码位 16#0004 段，不越段不挪预留槽。
// 状态机：E_DL_LabelSyncState（eIdle=0 失能/待机 / eSync=10 同步出标 / eLowSpeed=20
//           低速抑制出标 / eFault=99 故障兜底），CASE 含 ELSE 兜底，ELSE 置 0311 并撤
//           出标扳机与许可。
// 边界行为：① 脉冲差分 nDelta := nNow − nPrev（DINT 回绕安全；上电首拍以当前脉冲为
//           基准，避免首拍巨量假位移）；② fPulsePerMm <= 0 或 fLabelPitchMm <= 0 → 故障
//           030F，全部除法位于该闸之后（先判后除）；③ 线速度低于 fSpeedMinMpm → 不出
//           标 + 信息 01EE + bLowSpeed，相位继续累计（回速后按相位补出，不丢位置）；
//           ④ 提前量超一个节距 → 钳到节距 + 信息 01ED；⑤ bLabelPresent := FALSE → 不出
//           标且 bMissedLabel 锁存（漏标次数由上层按本标志上升沿自行计数，本件不设死
//           计数器）；⑥ 失能 → bFireTrigger := FALSE + bValid := FALSE（R72）；⑦ 非有限
//           或解算溢出（NaN 自反判 + Inf 幅值上限判）→ 故障 0310，扳机撤。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.13）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_LabelSyncState（归属 DL_Motion，与 FB_DL_LabelApplySync 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LabelSyncState :
(
    eIdle     := 0,   // 失能/待机：扳机撤，相位基准重新对齐 / Disabled, trigger dropped, phase re-based
    eSync     := 10,  // 同步出标：线速度达标，按节距分频出标 / Synchronised firing at the label pitch
    eLowSpeed := 20,  // 低速抑制：速度低于下限，不出标只累计相位 / Low speed, firing suppressed, phase still accumulated
    eFault    := 99   // 故障兜底：组态非法/非有限/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_LabelApplySync
 * 调用约定: 每个扫描周期无条件调用一次；nEncoderPulse 由高速计数或编码器模块刷新，
 *           uDeltaTimeMs 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_LabelApplySync
VAR_INPUT
    nEncoderPulse  : DINT;                        // 编码器累计脉冲 [脉冲]，允许 32 位回绕 / Encoder accumulated pulses [pulse], 32-bit wrap allowed
    fPulsePerMm    : LREAL := 100.0;              // 脉冲当量 [脉冲每毫米]，须 > 0 / Pulse equivalent [pulse per mm], must be > 0
    fLabelPitchMm  : LREAL := 50.0;               // 标签节距 [mm]，须 > 0 / Label pitch [mm], must be > 0
    fLeadMm        : LREAL := 2.0;                // 出标提前量 [mm]，超一个节距被钳位 / Label lead [mm], clamped to one pitch
    fSpeedMinMpm   : LREAL := 5.0;                // 最低同步线速度 [米每分] / Minimum synchronised web speed [m per min]
    bLabelPresent  : BOOL;                        // 标签在位（缺标检测）/ Label present, missing-label detection
    tTriggerHold   : TIME := T#20MS;              // 出标触发脉宽 [ms] / Trigger pulse width [ms]
    uDeltaTimeMs   : UDINT;                       // 扫描间隔 [ms]，调用方注入，禁系统时间函数 / Scan interval [ms], caller-injected
    bEnable        : BOOL;                        // 总使能 / Master enable
    bReset         : BOOL;                        // 复位，上升沿清漏标/饱和提示/故障与计数 / Reset, rising edge clears the missed-label latch, hints, fault and counter
END_VAR
VAR_OUTPUT
    bFireTrigger   : BOOL;                        // 出标触发（脉宽 tTriggerHold）/ Label fire trigger, width tTriggerHold
    uLabelsApplied : UDINT;                       // 已出标计数 [张]，饱和 / Labels applied [pcs], saturating
    bMissedLabel   : BOOL;                        // 漏标标志，锁存至 bReset / Missed-label flag, latched until reset
    fPhaseErrMm    : LREAL;                       // 相位误差 [mm]，相对出标点：负 = 尚差，正 = 已滞后 / Phase error [mm] relative to the fire point
    fWebSpeedMpm   : LREAL;                       // 卷材线速度 [米每分] / Web line speed [m per min]
    bLowSpeed      : BOOL;                        // 低速抑制出标标志 / Low-speed firing suppression flag
    eErr           : UDINT;                       // 错误码，0 = 无错，码位 16#0004_01ED 起信息级、16#0004_030F 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                        // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                        // 出标扳机可用标志，失能/故障闸显式 FALSE / Trigger usable flag, explicit FALSE on disable/fault gates
    eState         : E_DL_LabelSyncState;         // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset        : R_TRIG;                      // 复位上升沿检测实例 / Reset rising edge detector
    fbTonHold      : TON;                         // 触发脉宽定时器实例 / Trigger pulse width timer
    nPrevPulse     : DINT;                        // 上拍累计脉冲 [脉冲] / Previous accumulated pulses [pulse]
    nDeltaPulse    : DINT;                        // 本拍脉冲差分 [脉冲]，带符号 / Pulse delta of this scan [pulse], signed
    fDeltaMm       : LREAL;                       // 本拍位移 [mm]，带符号 / Displacement of this scan [mm], signed
    fPhaseMm       : LREAL;                       // 距上次出标的累计相位 [mm] / Accumulated phase since the last fire [mm]
    fTrigPointMm   : LREAL;                       // 出标相位点 = 节距 − 生效提前量 [mm] / Fire phase point [mm]
    fLeadEff       : LREAL;                       // 生效提前量（钳位后）[mm] / Effective lead after clamping [mm]
    fDtSec         : LREAL;                       // 扫描间隔换算成秒 [s] / Scan interval in seconds [s]
    fAbsDeltaMm    : LREAL;                       // 位移绝对值 [mm]，算线速度用 / Absolute displacement for the speed [mm]
    uDtEff         : UDINT;                       // 钳位后的扫描间隔 [ms] / Clamped scan interval [ms]
    bTrigReq       : BOOL;                        // 出标请求（脉宽未撤前后保持）/ Fire request held until the pulse width elapses
    bLeadClamped   : BOOL;                        // 提前量饱和钳位标志 / Lead saturation flag
    bFirstScan     : BOOL := TRUE;                // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_LAS_CODE_INFO_1 : UDINT := 16#0004_01ED;   // 信息级槽 1（提前量饱和钳位） / info slot 1
    DL_LAS_CODE_INFO_2 : UDINT := 16#0004_01EE;   // 信息级槽 2（编码器低速暂停出标） / info slot 2
    DL_LAS_CODE_FLT_1  : UDINT := 16#0004_030F;   // 故障级槽 1（脉冲当量/节距组态非法） / fault slot 1
    DL_LAS_CODE_FLT_2  : UDINT := 16#0004_0310;   // 故障级槽 2（输入非有限） / fault slot 2
    DL_LAS_CODE_FLT_3  : UDINT := 16#0004_0311;   // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_LAS_CNT_MAX     : UDINT := 16#FFFF_FFFE;   // 出标计数饱和值 [张] / Label counter saturation [pcs]
    DL_LAS_DT_MIN_MS   : UDINT := 1;              // 扫描间隔下限 [ms]，防除零与死判 / Scan interval floor [ms], prevents divide-by-zero
    DL_LAS_MS_PER_S    : LREAL := 1000.0;         // 毫秒转秒系数 [ms/s] / Milliseconds per second
    DL_LAS_MM_PER_M    : LREAL := 1000.0;         // 毫米转米系数 [mm/m] / Millimetres per metre
    DL_LAS_S_PER_MIN   : LREAL := 60.0;           // 秒转分系数 [s/min] / Seconds per minute
    DL_LAS_ZERO        : LREAL := 0.0;            // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_LAS_TOL         : LREAL := 1.0E-6;         // 浮点比较容差 [—] / Float comparison tolerance
    DL_LAS_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿与脉宽定时器在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbTonHold(IN := bTrigReq, PT := tTriggerHold);     // 脉宽定时器无条件刷新 / pulse-width timer refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）：清漏标锁存与计数并重新对齐相位
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_LabelSyncState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    bMissedLabel := FALSE;                         // 漏标锁存清 / missed-label latch cleared
    bLeadClamped := FALSE;                         // 饱和提示清 / saturation hint cleared
    uLabelsApplied := 16#0000_0000;                // 出标计数清 / label counter cleared
    fPhaseMm := DL_LAS_ZERO;                       // 相位清零 / phase cleared
    bTrigReq := FALSE;                             // 出标请求清 / fire request cleared
    bFirstScan := TRUE;                            // 重新首拍化（相位基准重新对齐）/ re-initialize first scan, phase re-based
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（NaN 自反判 + Inf 幅值上限判，R79）
 *----------------------------------------------------------------------------*)
IF (fPulsePerMm <> fPulsePerMm) OR (ABS(fPulsePerMm) >= DL_LAS_INF)
   OR (fLabelPitchMm <> fLabelPitchMm) OR (ABS(fLabelPitchMm) >= DL_LAS_INF)
   OR (fLeadMm <> fLeadMm) OR (ABS(fLeadMm) >= DL_LAS_INF)
   OR (fSpeedMinMpm <> fSpeedMinMpm) OR (ABS(fSpeedMinMpm) >= DL_LAS_INF) THEN
    eState := E_DL_LabelSyncState.eFault;          // 进故障相 / enter fault state
    eErr   := DL_LAS_CODE_FLT_2;                   // 故障级：输入非有限 / fault: non-finite input
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 扳机不可用 / trigger unusable
    bFireTrigger := FALSE;                         // 扳机撤安全侧 / trigger dropped, safe side
    bTrigReq := FALSE;                             // 请求撤 / request dropped
    bLowSpeed := FALSE;                            // 低速标志撤 / low-speed flag withdrawn
    fPhaseErrMm := DL_LAS_ZERO;                    // 相位误差回零 / phase error zeroed
    fWebSpeedMpm := DL_LAS_ZERO;                   // 线速度回零 / web speed zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸：脉冲当量与节距必须为正——本件全部除法严格位于此闸之后
 *       （先判后除，禁把判零写在除子表达式里）
 *----------------------------------------------------------------------------*)
IF (fPulsePerMm <= DL_LAS_TOL) OR (fLabelPitchMm <= DL_LAS_TOL) THEN
    eState := E_DL_LabelSyncState.eFault;          // 进故障相 / enter fault state
    eErr   := DL_LAS_CODE_FLT_1;                   // 故障级：脉冲当量/节距组态非法 / fault: pulse equivalent or pitch invalid
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 扳机不可用 / trigger unusable
    bFireTrigger := FALSE;                         // 扳机撤安全侧 / trigger dropped, safe side
    bTrigReq := FALSE;                             // 请求撤 / request dropped
    bLowSpeed := FALSE;                            // 低速标志撤 / low-speed flag withdrawn
    fPhaseErrMm := DL_LAS_ZERO;                    // 相位误差回零 / phase error zeroed
    fWebSpeedMpm := DL_LAS_ZERO;                   // 线速度回零 / web speed zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜提前量饱和钳位：提前量不得超一个节距（超出会让出标点跑到上一节距之前）
 *----------------------------------------------------------------------------*)
fLeadEff := fLeadMm;                               // 先取引脚值 / take the pin value first
bLeadClamped := FALSE;                             // 饱和标志逐拍重判 / saturation flag re-judged per scan
IF fLeadEff > fLabelPitchMm - DL_LAS_TOL THEN
    fLeadEff := fLabelPitchMm;                     // 钳到节距（出标点落在相位 0）/ clamped to one pitch, fire point at phase zero
    bLeadClamped := TRUE;                          // 饱和标志置位 / saturation flag raised
END_IF
IF fLeadEff < DL_LAS_ZERO THEN
    fLeadEff := DL_LAS_ZERO;                       // 负提前量钳到零（不提前即到位出标）/ negative lead clamped to zero
    bLeadClamped := TRUE;                          // 越界同样提示 / out-of-range hint raised
END_IF
fTrigPointMm := fLabelPitchMm - fLeadEff;          // 出标相位点 [mm] / fire phase point [mm]

(*------------------------------------------------------------------------------
 * 段 6｜脉冲差分与线速度：nDelta := nNow − nPrev，DINT 回绕时补码减法自然正确，
 *       禁止用 ABS(nNow − nPrev) 之类绝对值比较（正反转会被抹平）
 *----------------------------------------------------------------------------*)
IF bFirstScan THEN
    nPrevPulse := nEncoderPulse;                   // 上电首拍以当前脉冲为基准 / first scan re-bases on the current pulse
    bFirstScan := FALSE;                           // 首拍标志清除 / first-scan flag cleared
END_IF
nDeltaPulse := nEncoderPulse - nPrevPulse;         // 本拍脉冲差分（带符号，回绕安全）[脉冲] / signed pulse delta, wrap safe
nPrevPulse := nEncoderPulse;                       // 基准刷新 / refresh the reference
fDeltaMm := DINT_TO_LREAL(nDeltaPulse) / fPulsePerMm;   // 位移（除子已由段 4 保证为正）[mm] / displacement, divisor proven positive
IF uDeltaTimeMs < DL_LAS_DT_MIN_MS THEN
    uDtEff := DL_LAS_DT_MIN_MS;                    // 间隔过小按 1 ms 下限 / floored interval
ELSE
    uDtEff := uDeltaTimeMs;                        // 间隔原值 / interval as-is
END_IF
fDtSec := UDINT_TO_LREAL(uDtEff) / DL_LAS_MS_PER_S;    // 间隔换算成秒 [s] / interval in seconds
fAbsDeltaMm := ABS(fDeltaMm);                      // 位移绝对值 [mm] / absolute displacement
IF fDtSec > DL_LAS_TOL THEN
    fWebSpeedMpm := fAbsDeltaMm / fDtSec / DL_LAS_MM_PER_M * DL_LAS_S_PER_MIN;   // 线速度 [米每分] / web speed [m per min]
ELSE
    fWebSpeedMpm := DL_LAS_ZERO;                   // 间隔不可用时线速度记零 / speed reads zero when the interval is unusable
END_IF
IF (fWebSpeedMpm <> fWebSpeedMpm) OR (ABS(fWebSpeedMpm) >= DL_LAS_INF) THEN
    fWebSpeedMpm := DL_LAS_ZERO;                   // 解算非有限兜到零（诊断量不冒充有效值）/ non-finite falls back to zero
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜相位累计与出标判据：低速时只累计不出标（回速后按相位补出，不丢位置）；
 *       每拍最多出一次标，残余相位留待下一拍（不写 WHILE，避免单拍突发多标）
 *----------------------------------------------------------------------------*)
IF bEnable THEN
    fPhaseMm := fPhaseMm + fDeltaMm;               // 相位累计（正反转自然增减）[mm] / phase accumulation, signed
END_IF
bLowSpeed := (fWebSpeedMpm < fSpeedMinMpm);        // 低速判据 [米每分] / low-speed predicate [m per min]
IF bTrigReq AND fbTonHold.Q THEN
    bTrigReq := FALSE;                             // 脉宽到点撤请求（单拍标志自清）/ request cleared when the pulse width elapses
END_IF
IF bEnable AND (NOT bLowSpeed) AND bLabelPresent AND (NOT bTrigReq)
   AND (fPhaseMm >= fTrigPointMm - DL_LAS_TOL) THEN
    bTrigReq := TRUE;                              // 出标请求置位（脉宽由定时器收口）/ fire request raised, width bounded by the timer
    fPhaseMm := fPhaseMm - fLabelPitchMm;          // 相位扣一个节距，残余留待下一拍补出 / phase reduced by one pitch, the residual fires later
    IF uLabelsApplied < DL_LAS_CNT_MAX THEN
        uLabelsApplied := uLabelsApplied + 1;      // 出标计数饱和自增 [张] / saturating label increment
    END_IF
END_IF
IF bEnable AND (NOT bLabelPresent) THEN
    bMissedLabel := TRUE;                          // 缺标锁存（本拍不出标，等补标）/ missing-label latched, no fire
END_IF
IF fPhaseMm > fLabelPitchMm THEN
    fPhaseMm := fPhaseMm - fLabelPitchMm;          // 相位越一个节距仍未出标：钳回一节距内，防累计漂移 / one-pitch guard against unbounded phase drift
    bMissedLabel := TRUE;                          // 越节距即漏标 / overrunning a pitch is a missed label
END_IF
fPhaseErrMm := fPhaseMm - fTrigPointMm;            // 相位误差 [mm]：负 = 尚差，正 = 已过出标点 / phase error, negative = short, positive = past the fire point
bFireTrigger := bTrigReq;                          // 扳机输出（脉宽由定时器收口）/ trigger output, width bounded by the timer

(*------------------------------------------------------------------------------
 * 段 8｜状态机：CASE 含 ELSE 兜底（非法状态 → 0311 + 扳机与许可全撤）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_LabelSyncState.eIdle:
        bFireTrigger := FALSE;                     // 待机扳机撤 / trigger dropped in idle
        bTrigReq := FALSE;                         // 请求撤 / request dropped
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        bLowSpeed := FALSE;                        // 待机不报低速 / no low-speed hint in idle
        fPhaseErrMm := DL_LAS_ZERO;                // 相位误差回零 / phase error zeroed
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF bEnable THEN
            fPhaseMm := fTrigPointMm - fLabelPitchMm;   // 重新对齐相位基准（下次到点即出标）/ phase re-based
            eState := E_DL_LabelSyncState.eSync;   // 使能进同步相 / enable enters synchronised firing
        END_IF

    E_DL_LabelSyncState.eSync:
        bValid := TRUE;                            // 扳机可用 / trigger usable
        bError := FALSE;                           // 同步相无故障 / no fault in the synchronised state
        eErr := 16#0000_0000;                      // 同步相先清码 / clear the code first
        IF bLeadClamped THEN
            eErr := DL_LAS_CODE_INFO_1;            // 信息级：提前量饱和钳位 / info: lead saturated
        END_IF
        IF bLowSpeed THEN
            eErr := DL_LAS_CODE_INFO_2;            // 信息级：低速暂停出标（优先于钳位提示）/ info: low speed outranks the lead hint
            eState := E_DL_LabelSyncState.eLowSpeed;   // 转低速抑制相 / enter the low-speed state
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_LabelSyncState.eIdle;   // 失能回待机 / disable returns to idle
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
            bFireTrigger := FALSE;                 // 扳机撤 / trigger dropped
        END_IF

    E_DL_LabelSyncState.eLowSpeed:
        bValid := FALSE;                           // 低速不出标，扳机不可用（R72）/ no fire at low speed, explicit FALSE
        bFireTrigger := FALSE;                     // 扳机撤（硬出标会贴歪）/ trigger dropped, firing would misplace the label
        bTrigReq := FALSE;                         // 请求撤 / request dropped
        bError := FALSE;                           // 信息级不置 bError（R45/R101）/ info never raises bError
        eErr := DL_LAS_CODE_INFO_2;                // 信息级：编码器低速，无法同步 / info: low speed, cannot synchronise
        IF NOT bEnable THEN
            eState := E_DL_LabelSyncState.eIdle;   // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        ELSIF (NOT bLowSpeed) THEN
            eState := E_DL_LabelSyncState.eSync;   // 速度恢复回同步相（退出条件二）/ speed recovered, second exit
        END_IF

    E_DL_LabelSyncState.eFault:
        bValid := FALSE;                           // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
        bFireTrigger := FALSE;                     // 扳机撤安全侧 / trigger dropped, safe side
        bTrigReq := FALSE;                         // 请求撤 / request dropped
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        IF eErr = 16#0000_0000 THEN
            eErr := DL_LAS_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
        END_IF
        IF bEnable AND (fPulsePerMm > DL_LAS_TOL) AND (fLabelPitchMm > DL_LAS_TOL) THEN
            eState := E_DL_LabelSyncState.eIdle;   // 组态恢复且使能才回待机（退出条件 ≥2）/ recover only when the configuration is sane again
        END_IF

    ELSE
        eState := E_DL_LabelSyncState.eFault;      // 非法状态兜底 / illegal-state fallback
        eErr := DL_LAS_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 扳机不可用 / trigger unusable
        bFireTrigger := FALSE;                     // 扳机撤安全侧 / trigger dropped, safe side
        bTrigReq := FALSE;                         // 请求撤 / request dropped
        fPhaseErrMm := DL_LAS_ZERO;                // 相位误差回零 / phase error zeroed

END_CASE
END_FUNCTION_BLOCK
