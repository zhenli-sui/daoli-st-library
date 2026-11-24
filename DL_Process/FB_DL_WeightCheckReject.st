//==============================================================================
// 功能块：FB_DL_WeightCheckReject ｜ 中文名称：动态称重与剔除控制
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：包装线动态称重站：滑动窗均值滤波 → 欠重/合格/超重分级 → 剔除指令与
//           完成反馈握手 → 剔除器拒动检测。无料在位时一律不称重也不判定（空秤 0 g
//           会把「无料」判成「欠重」并触发剔除，是本件的核心防错点）。稳定等待以
//           调用方注入的扫描间隔累加计时，与任务周期解耦；剔除反馈窗用 TON 计时。
//           本件不做重量分选配方管理、不驱动称重仪表、不控输送线主传动（停线仅给
//           建议位 bStopLine，最终是否停线由线控层决定）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：重量[g] / 剔除反馈窗[s] / 称重稳定等待[ms] / 扫描间隔[ms] / 样本数[个] /
//         计数[件]
// 错误码表：16#0005_0402 信息级（滤波窗有效样本不足 nFilterSamples，本拍不判、不给
//           剔除命令，不置 bError）/ 16#0005_0403 信息级（无料在位，跳过称重并清滤波
//           窗，不置 bError）/ 16#0005_0345 故障级（合格域上下限倒置 fWeightMinG >=
//           fWeightMaxG，置 bError）/ 16#0005_0346 故障级（剔除器拒动：剔除指令发出后
//           反馈窗内无 bRejectFb，置 bError + bRejectFailed + bStopLine 锁存）/
//           16#0005_0347 故障级（输入非有限独立分支显式映射入本槽，且兼作状态机 ELSE
//           非法状态兜底）。非有限与非法状态共用 0347 的反证句：二者在现有输出组合下
//           不可观测出差异——均为 bError+t 全部输出撤（剔除命令撤、bPass 撤、bValid
//           撤），bStopLine 不因非有限而置位，故 §3 未另给独立槽，本件显式复用不越段。
// 状态机：E_DL_WeightRejectState（eIdle=0 待机 / eSettling=10 稳定等待 /
//           eJudging=20 判定 / eRejecting=30 剔除握手 / eFault=99 故障兜底），
//           CASE 含 ELSE 兜底，ELSE 置 0347 且剔除命令与许可全部撤销。
// 边界行为：① bProductPresent := FALSE → 不判定、撤销剔除命令、清滤波窗（防空秤样本
//           污染下一件）+ 信息 0403；② 有效样本 < nFilterSamples → bValid := FALSE +
//           信息 0402，本拍不判且不给剔除命令；③ fWeightMinG >= fWeightMaxG（容差判）
//           → 故障 0345；④ 剔除指令发出后 tRejectWindow 内无反馈 → 故障 0346 +
//           bRejectFailed + bStopLine := TRUE 锁存（漏剔流入下游属安全级，只建议停线
//           不直接停线）；⑤ 非有限（NaN 自反判 + Inf 幅值上限判）→ 独立分支显式置
//           0347，剔除命令撤、许可撤；⑥ 同一件只判一次（bJudged 锁存，料离开才清），
//           防欠重件滞留时反复剔除与反复报拒动；⑦ 失能 → 剔除命令撤 + bPass := FALSE
//           + bValid := FALSE（R72），计数与停线建议锁存保留。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.12）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_WeightRejectState（归属 DL_Process，与 FB_DL_WeightCheckReject 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_WeightRejectState :
(
    eIdle      := 0,   // 待机：无料或失能，剔除命令撤 / Idle: no product or disabled, reject command dropped
    eSettling  := 10,  // 稳定等待：料在位但未达 tSettle，不采样 / Settling: product present, sampling not yet allowed
    eJudging   := 20,  // 判定：按滑窗均值分级 / Judging: grading on the sliding-window mean
    eRejecting := 30,  // 剔除握手：命令已发，等反馈 / Rejecting: command issued, waiting for feedback
    eFault     := 99   // 故障兜底：拒动/组态非法/非有限/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_WeightCheckReject
 * 调用约定: 每个扫描周期无条件调用一次；uDeltaTimeMs 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_WeightCheckReject
VAR_INPUT
    fWeightG        : LREAL;                      // 毛重实测 [g] / Gross weight measured [g]
    fWeightMinG     : LREAL;                      // 合格域下限 [g] / Acceptable weight floor [g]
    fWeightMaxG     : LREAL;                      // 合格域上限 [g] / Acceptable weight ceiling [g]
    nFilterSamples  : INT := 5;                   // 滤波窗样本数 [个]，合法域 1~15，域外钳位 / Filter window length [samples], domain 1..15, clamped
    bProductPresent : BOOL;                       // 产品在位（称重台上有料）/ Product present on the weighing platform
    bRejectFb       : BOOL;                       // 剔除完成反馈 / Reject completed feedback
    tRejectWindow   : TIME := T#500MS;            // 剔除反馈窗 [ms]，窗内无反馈判拒动 / Reject feedback window [ms]
    tSettle         : TIME := T#200MS;            // 称重稳定等待 [ms] / Weighing settle time [ms]
    uDeltaTimeMs    : UDINT;                      // 扫描间隔 [ms]，调用方注入，禁系统时间函数 / Scan interval [ms], caller-injected
    bEnable         : BOOL;                       // 总使能 / Master enable
    bReset          : BOOL;                       // 复位，上升沿清拒动锁存、停线建议与计数 / Reset, rising edge clears the reject-failure latch, stop hint and counters
END_VAR
VAR_OUTPUT
    fWeightFilteredG : LREAL;                     // 滑窗均值滤波重量 [g] / Sliding-window mean weight [g]
    bPass           : BOOL;                       // 合格判定（仅本件判过且合格时为 TRUE）/ Pass verdict, TRUE only when judged and within limits
    bRejectCmd      : BOOL;                       // 剔除指令（脉宽 ≥ 反馈窗，命令语义）/ Reject command, held for the feedback window
    nUnderCount     : UDINT;                      // 欠重计数 [件]，饱和 / Underweight counter [pcs], saturating
    nOverCount      : UDINT;                      // 超重计数 [件]，饱和 / Overweight counter [pcs], saturating
    nRejectCount    : UDINT;                      // 剔除指令计数 [件]，饱和（按指令发出口径）/ Reject command counter [pcs], saturating
    bRejectFailed   : BOOL;                       // 剔除器拒动标志（锁存至 bReset）/ Rejector refusal flag, latched until reset
    bNoProduct      : BOOL;                       // 无料在位标志（信息 0403 的出口）/ No-product flag, outlet of info 0403
    bStopLine       : BOOL;                       // 停线建议（只建议不执行，锁存至 bReset）/ Stop-line recommendation only, latched until reset
    eErr            : UDINT;                      // 错误码，0 = 无错，码位 16#0005_0402 起信息级、16#0005_0345 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError          : BOOL;                       // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                       // 重量结论可用标志，样本不足/失能/故障闸显式 FALSE / Verdict usable flag, explicit FALSE on insufficient samples, disable and fault gates
    eState          : E_DL_WeightRejectState;     // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset         : R_TRIG;                     // 复位上升沿检测实例 / Reset rising edge detector
    fbTonReject     : TON;                        // 剔除反馈窗定时器实例 / Reject feedback window timer
    afWindow        : ARRAY[0..14] OF LREAL;      // 滑窗样本缓冲 [g]，定长 15 / Sliding-window sample buffer [g], fixed length 15
    nWinIdx         : INT;                        // 滑窗写指针 [—] / Sliding-window write index
    nWinCnt         : INT;                        // 滑窗内有效样本数 [个] / Valid sample count in the window
    nSamplesEff     : INT;                        // 钳位后的滤波窗长度 [个] / Clamped filter length [samples]
    nLoop           : INT;                        // 清零循环索引 [—] / Clearing loop index
    nSampUse        : INT;                        // 本拍参与均值的样本数 [个] / Samples used by the mean this scan
    uSettleAccMs    : UDINT;                      // 稳定等待累计 [ms]，按注入间隔累加 / Settle accumulator [ms], by injected interval
    uSettleMs       : UDINT;                      // 稳定等待目标值 [ms] / Settle target [ms]
    uDtEff          : UDINT;                      // 钳位后的扫描间隔 [ms] / Clamped scan interval [ms]
    uCntMax         : UDINT;                      // 计数器饱和上限 [件] / Counter saturation ceiling [pcs]
    fSumG           : LREAL;                      // 窗口样本求和 [g] / Window sample sum [g]
    bSampleNow      : BOOL;                       // 本拍允许采样 / Sampling allowed this scan
    bSettled        : BOOL;                       // 稳定等待已满足 / Settle time satisfied
    bJudged         : BOOL;                       // 同一件已判定锁存 / One verdict per product latched
    bUnder          : BOOL;                       // 本件欠重判定 / Underweight verdict of this product
    bOver           : BOOL;                       // 本件超重判定 / Overweight verdict of this product
    bRejectAct      : BOOL;                       // 剔除动作进行中（内部）/ Reject action in progress, internal
    bNonFin         : BOOL;                       // 非有限判定中间标志 / Non-finite detection intermediate flag
    bFirstScan      : BOOL := TRUE;               // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_WCR_CODE_INFO_1 : UDINT := 16#0005_0402;   // 信息级槽 1（有效样本不足，本拍不判） / info slot 1
    DL_WCR_CODE_INFO_2 : UDINT := 16#0005_0403;   // 信息级槽 2（无料在位跳过称重） / info slot 2
    DL_WCR_CODE_FLT_1  : UDINT := 16#0005_0345;   // 故障级槽 1（合格域上下限倒置） / fault slot 1
    DL_WCR_CODE_FLT_2  : UDINT := 16#0005_0346;   // 故障级槽 2（剔除器拒动） / fault slot 2
    DL_WCR_CODE_FLT_3  : UDINT := 16#0005_0347;   // 故障级槽 3（输入非有限/非法状态兜底） / fault slot 3
    DL_WCR_WIN_MAX     : INT := 15;               // 滤波窗定长上限 [个] / Fixed filter window width [samples]
    DL_WCR_WIN_MIN     : INT := 1;                // 滤波窗下限 [个] / Filter window floor [samples]
    DL_WCR_CNT_MAX     : UDINT := 16#FFFF_FFFE;   // 计数器饱和值 [件] / Counter saturation [pcs]
    DL_WCR_DT_MIN_MS   : UDINT := 1;              // 扫描间隔下限 [ms]，防死等 / Scan interval floor [ms], prevents a dead wait
    DL_WCR_ZERO        : LREAL := 0.0;            // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_WCR_TOL         : LREAL := 1.0E-6;         // 浮点比较容差 [—] / Float comparison tolerance
    DL_WCR_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
    DL_WCR_U32_MAX     : UDINT := 16#FFFF_FFFE;   // 毫秒累加饱和上限 [ms] / Millisecond accumulator saturation [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿与剔除窗定时器在任何分支之外周期调用。
 *       定时器 IN 取上拍动作状态（单拍滞后对 ≥500 ms 窗无影响），
 *       保证待机/故障/各分支下计时链永不断流
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbTonReject(IN := bRejectAct AND (NOT bRejectFb),  // 动作中且未收到反馈则计时 / timing while active without feedback
            PT := tRejectWindow);                  // 反馈窗长度 [ms] / feedback window length

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_WeightRejectState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    bRejectFailed := FALSE;                        // 拒动锁存清 / refusal latch cleared
    bStopLine := FALSE;                            // 停线建议清（人工确认后再复位）/ stop hint cleared after manual confirmation
    nUnderCount := 16#0000_0000;                   // 欠重计数清 / underweight counter cleared
    nOverCount := 16#0000_0000;                    // 超重计数清 / overweight counter cleared
    nRejectCount := 16#0000_0000;                  // 剔除计数清 / reject counter cleared
    bRejectAct := FALSE;                           // 动作状态清 / action state cleared
    bJudged := FALSE;                              // 判定锁存清 / verdict latch cleared
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸：独立分支显式映射入 0347（头注释给出共用反证句），
 *       剔除命令撤、bPass 撤、bValid 撤；bStopLine 不因非有限置位
 *----------------------------------------------------------------------------*)
bNonFin := (fWeightG <> fWeightG) OR (ABS(fWeightG) >= DL_WCR_INF)
        OR (fWeightMinG <> fWeightMinG) OR (ABS(fWeightMinG) >= DL_WCR_INF)
        OR (fWeightMaxG <> fWeightMaxG) OR (ABS(fWeightMaxG) >= DL_WCR_INF);   // 重量引脚非有限汇总判定 / weight pins non-finite check
IF bNonFin THEN
    eState := E_DL_WeightRejectState.eFault;       // 进故障相 / enter fault state
    eErr   := DL_WCR_CODE_FLT_3;                   // 故障级：输入非有限（显式映射入 0347）/ fault: non-finite input, explicitly mapped onto 0347
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 结论不可用 / verdict unusable
    bPass := FALSE;                                // 合格判定撤 / pass verdict dropped
    bRejectCmd := FALSE;                           // 剔除命令撤安全侧 / reject command dropped, safe side
    bRejectAct := FALSE;                           // 动作状态撤 / action state dropped
    fWeightFilteredG := DL_WCR_ZERO;               // 滤波值回零 / filtered value zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸：合格域上下限倒置（容差判，禁浮点判等）
 *----------------------------------------------------------------------------*)
IF (fWeightMinG >= fWeightMaxG - DL_WCR_TOL) THEN
    eState := E_DL_WeightRejectState.eFault;       // 进故障相 / enter fault state
    eErr   := DL_WCR_CODE_FLT_1;                   // 故障级：上下限倒置 / fault: limits inverted
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 结论不可用 / verdict unusable
    bPass := FALSE;                                // 合格判定撤 / pass verdict dropped
    bRejectCmd := FALSE;                           // 剔除命令撤安全侧 / reject command dropped, safe side
    bRejectAct := FALSE;                           // 动作状态撤 / action state dropped
    fWeightFilteredG := DL_WCR_ZERO;               // 滤波值回零 / filtered value zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜剔除器拒动检测（安全级）：动作中且反馈窗计时到点仍未收到反馈 →
 *       0346 + bRejectFailed + bStopLine 锁存。漏剔会流入下游，故只建议停线
 *       由线控层决策，本件不直接停传动
 *----------------------------------------------------------------------------*)
IF bRejectAct AND fbTonReject.Q AND (NOT bRejectFb) THEN
    bRejectFailed := TRUE;                         // 拒动锁存 / refusal latched
    bStopLine := TRUE;                             // 停线建议锁存（只建议）/ stop-line recommendation latched
    bRejectCmd := FALSE;                           // 剔除命令撤（不再反复打击剔除器）/ command dropped, do not hammer the rejector
    bRejectAct := FALSE;                           // 动作状态撤 / action state dropped
    eState := E_DL_WeightRejectState.eFault;       // 进故障相 / enter fault state
    eErr   := DL_WCR_CODE_FLT_2;                   // 故障级：剔除器拒动 / fault: rejector refused
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 结论不可用 / verdict unusable
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜滤波窗长度钳位与扫描间隔下限（域外按边界钳位，不新占码位：
 *       现有输出组合不可观测出独立信息）
 *----------------------------------------------------------------------------*)
nSamplesEff := nFilterSamples;                     // 先取引脚值 / take the pin value first
IF nSamplesEff < DL_WCR_WIN_MIN THEN
    nSamplesEff := DL_WCR_WIN_MIN;                 // 下限钳位 / clipped to the floor
END_IF
IF nSamplesEff > DL_WCR_WIN_MAX THEN
    nSamplesEff := DL_WCR_WIN_MAX;                 // 上限钳位 / clipped to the ceiling
END_IF
IF uDeltaTimeMs < DL_WCR_DT_MIN_MS THEN
    uDtEff := DL_WCR_DT_MIN_MS;                    // 间隔过小按 1 ms 下限，防稳定等待死等 / floored delta prevents a dead wait
ELSE
    uDtEff := uDeltaTimeMs;                        // 间隔原值 / interval as-is
END_IF
uSettleMs := DINT_TO_UDINT(TIME_TO_DINT(tSettle)); // 稳定等待目标换算 [ms] / settle target in ms

(*------------------------------------------------------------------------------
 * 段 7｜稳定等待累计（按注入间隔，与任务周期解耦）与采样门控
 *----------------------------------------------------------------------------*)
IF bEnable AND bProductPresent THEN
    IF uSettleAccMs < DL_WCR_U32_MAX THEN
        uSettleAccMs := uSettleAccMs + uDtEff;     // 料在位累计稳定时间 [ms] / accumulate settle time while product present
    END_IF
ELSE
    uSettleAccMs := 16#0000_0000;                  // 料离开或失能：稳定计时清零 / product gone or disabled: settle timer cleared
END_IF
bSettled := (uSettleAccMs >= uSettleMs) AND bProductPresent;   // 稳定且料在位 / settled with the product still present
bSampleNow := bEnable AND bProductPresent AND bSettled AND (NOT bJudged);   // 每件在判定前逐拍采样 / sample every scan before the verdict of this product
IF bSampleNow THEN
    afWindow[nWinIdx] := fWeightG;                 // 写入当前样本 [g] / write the current sample
    nWinIdx := nWinIdx + 1;                        // 写指针前移 / advance the write index
    IF nWinIdx >= DL_WCR_WIN_MAX THEN
        nWinIdx := 0;                              // 环形回绕 / ring wrap-around
    END_IF
    IF nWinCnt < DL_WCR_WIN_MAX THEN
        nWinCnt := nWinCnt + 1;                    // 样本计数增（上限 15）/ sample count increments up to 15
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜滑窗均值（只用最近 nSamplesEff 个样本；环形缓冲按逆序回溯取最近样本）
 *----------------------------------------------------------------------------*)
nSampUse := nWinCnt;                               // 先取窗口内有效样本数 / take the valid sample count
IF nSampUse > nSamplesEff THEN
    nSampUse := nSamplesEff;                       // 只用最近 nSamplesEff 个 / use only the newest nSamplesEff samples
END_IF
fSumG := DL_WCR_ZERO;                              // 求和初值 / sum seed
IF nSampUse > 0 THEN
    FOR nLoop := 1 TO nSampUse DO
        fSumG := fSumG + afWindow[(nWinIdx - nLoop + DL_WCR_WIN_MAX * 2) MOD DL_WCR_WIN_MAX];   // 逆序回溯取最近样本 [g] / newest samples in reverse order
    END_FOR
    fWeightFilteredG := fSumG / INT_TO_LREAL(nSampUse);   // 均值（除子已判非零）/ mean, divisor proven non-zero
ELSE
    fWeightFilteredG := DL_WCR_ZERO;               // 无样本时滤波值为 0 / no sample, filtered value zeroed
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜状态机：CASE 含 ELSE 兜底（非法状态 → 0347 + 命令与许可全撤）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_WeightRejectState.eIdle:
        bRejectCmd := FALSE;                       // 待机剔除命令撤 / reject command dropped in idle
        bRejectAct := FALSE;                       // 动作状态撤 / action state dropped
        bPass := FALSE;                            // 合格判定撤 / pass verdict dropped
        bValid := FALSE;                           // 结论不可用（R72 失能闸）/ verdict unusable on the disable gate
        bNoProduct := NOT bProductPresent;         // 无料标志出口 / no-product flag outlet
        nWinCnt := 0;                              // 无料清窗计数（防空秤污染）/ window count cleared, anti-pollution
        nWinIdx := 0;                              // 写指针复位 / write index reset
        FOR nLoop := 0 TO DL_WCR_WIN_MAX - 1 DO
            afWindow[nLoop] := DL_WCR_ZERO;        // 逐格清零（显式清窗，不留残值）/ explicit per-cell clearing
        END_FOR
        bJudged := FALSE;                          // 判定锁存清（新件重新判）/ verdict latch cleared for the next product
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF NOT bProductPresent THEN
            eErr := DL_WCR_CODE_INFO_2;            // 信息级：无料在位跳过称重（空秤不出结论）/ info: no product, weighing skipped
        END_IF
        IF bEnable AND bProductPresent THEN
            eState := E_DL_WeightRejectState.eSettling;   // 料在位且使能进稳定等待 / product present and enabled enters settling
        END_IF

    E_DL_WeightRejectState.eSettling:
        bRejectCmd := FALSE;                       // 稳定等待不出剔除 / no reject while settling
        bRejectAct := FALSE;                       // 动作状态撤 / action state dropped
        bPass := FALSE;                            // 未判不出合格 / no pass verdict before judging
        bValid := FALSE;                           // 未判结论不可用 / verdict unusable before judging
        bNoProduct := NOT bProductPresent;         // 无料标志出口 / no-product flag outlet
        eErr := 16#0000_0000;                      // 稳定等待无错 / no error while settling
        bError := FALSE;                           // 稳定等待无故障 / no fault while settling
        IF bEnable AND (NOT bProductPresent) THEN
            eState := E_DL_WeightRejectState.eIdle;   // 料离开回待机（退出条件一）/ product gone, first exit
            eErr := DL_WCR_CODE_INFO_2;            // 信息级：无料在位跳过称重 / info: no product, weighing skipped
        ELSIF bEnable AND bSettled AND (nWinCnt >= nSamplesEff) THEN
            eState := E_DL_WeightRejectState.eJudging;   // 稳定且样本够进判定（退出条件二）/ settled with enough samples, second exit
        END_IF

    E_DL_WeightRejectState.eJudging:
        bError := FALSE;                           // 判定相无故障 / no fault in judging
        bNoProduct := NOT bProductPresent;         // 无料标志出口 / no-product flag outlet
        IF (NOT bProductPresent) THEN
            eState := E_DL_WeightRejectState.eIdle;   // 料离开回待机（退出条件一）/ product gone, first exit
            eErr := DL_WCR_CODE_INFO_2;            // 信息级：无料在位跳过称重 / info: no product, weighing skipped
            bValid := FALSE;                       // 结论不可用 / verdict unusable
            bPass := FALSE;                        // 合格判定撤 / pass verdict dropped
        ELSIF nWinCnt < nSamplesEff THEN
            bValid := FALSE;                       // 样本不足结论不可用（R72）/ insufficient samples, verdict unusable
            bPass := FALSE;                        // 样本不足不判合格 / no pass verdict on insufficient samples
            eErr := DL_WCR_CODE_INFO_1;            // 信息级：有效样本不足，本拍不判 / info: insufficient samples, not judged this scan
            bRejectCmd := FALSE;                   // 样本不足不给剔除命令 / no reject command on insufficient samples
        ELSE
            bValid := TRUE;                        // 样本足够，结论可用 / enough samples, verdict usable
            eErr := 16#0000_0000;                  // 判定相无错 / no error in judging
            IF NOT bJudged THEN
                bUnder := (fWeightFilteredG < fWeightMinG);    // 欠重判据（容差外）/ underweight predicate beyond tolerance
                bOver := (fWeightFilteredG > fWeightMaxG);     // 超重判据（容差外）/ overweight predicate beyond tolerance
                bJudged := TRUE;                   // 本件判定锁存（同件只判一次）/ one verdict per product
                IF bUnder THEN
                    IF nUnderCount < DL_WCR_CNT_MAX THEN
                        nUnderCount := nUnderCount + 1;    // 欠重计数饱和自增 [件] / saturating underweight increment
                    END_IF
                    bPass := FALSE;                // 欠重不合格 / underweight fails
                    bRejectCmd := TRUE;            // 欠重给剔除命令 / reject on underweight
                    bRejectAct := TRUE;            // 动作状态置位（窗计时由此起）/ action state raised, window starts
                    IF nRejectCount < DL_WCR_CNT_MAX THEN
                        nRejectCount := nRejectCount + 1;  // 剔除指令计数 [件] / reject command counter
                    END_IF
                    eState := E_DL_WeightRejectState.eRejecting;   // 进剔除握手相 / enter the reject handshake
                ELSIF bOver THEN
                    IF nOverCount < DL_WCR_CNT_MAX THEN
                        nOverCount := nOverCount + 1;      // 超重计数饱和自增 [件] / saturating overweight increment
                    END_IF
                    bPass := FALSE;                // 超重不合格 / overweight fails
                    bRejectCmd := TRUE;            // 超重给剔除命令 / reject on overweight
                    bRejectAct := TRUE;            // 动作状态置位 / action state raised
                    IF nRejectCount < DL_WCR_CNT_MAX THEN
                        nRejectCount := nRejectCount + 1;  // 剔除指令计数 [件] / reject command counter
                    END_IF
                    eState := E_DL_WeightRejectState.eRejecting;   // 进剔除握手相 / enter the reject handshake
                ELSE
                    bPass := TRUE;                 // 合格放行 / pass and release
                    bRejectCmd := FALSE;           // 合格不剔除 / no reject on pass
                    bRejectAct := FALSE;           // 动作状态撤 / action state dropped
                    eState := E_DL_WeightRejectState.eJudging;     // 留在判定相等料离开 / stay in judging until the product leaves
                END_IF
            ELSE
                bPass := (NOT bUnder) AND (NOT bOver);   // 已判件结论保持 / verdict held for an already-judged product
                IF bUnder OR bOver THEN
                    eState := E_DL_WeightRejectState.eRejecting;   // 不合格件回到握手相等反馈 / unqualified product returns to the handshake
                END_IF
            END_IF
        END_IF

    E_DL_WeightRejectState.eRejecting:
        bValid := TRUE;                            // 结论可用（已判）/ verdict usable, already judged
        bPass := FALSE;                            // 剔除件不合格 / rejected product fails
        bError := FALSE;                           // 握手相无故障（拒动已由段 5 早期判定）/ no fault here, refusal handled earlier
        bRejectCmd := TRUE;                        // 剔除命令保持（脉宽 ≥ 反馈窗）/ command held for at least the feedback window
        bRejectAct := TRUE;                        // 动作状态保持 / action state held
        eErr := 16#0000_0000;                      // 握手相无错 / no error in the handshake
        IF NOT bProductPresent THEN
            bRejectCmd := FALSE;                   // 料已离开：命令撤（退出条件一）/ product gone, first exit
            bRejectAct := FALSE;                   // 动作状态撤 / action state dropped
            eState := E_DL_WeightRejectState.eIdle;   // 回待机 / back to idle
            eErr := DL_WCR_CODE_INFO_2;            // 信息级：无料在位 / info: no product present
        ELSIF bRejectFb THEN
            bRejectCmd := FALSE;                   // 收到反馈：命令撤（退出条件二）/ feedback received, second exit
            bRejectAct := FALSE;                   // 动作状态撤 / action state dropped
            eState := E_DL_WeightRejectState.eJudging;     // 回到判定相等料离开 / back to judging until the product leaves
        END_IF

    E_DL_WeightRejectState.eFault:
        bValid := FALSE;                           // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
        bPass := FALSE;                            // 合格判定撤 / pass verdict dropped
        bRejectCmd := FALSE;                       // 剔除命令撤安全侧 / reject command dropped, safe side
        bRejectAct := FALSE;                       // 动作状态撤 / action state dropped
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        IF eErr = 16#0000_0000 THEN
            eErr := DL_WCR_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback so bError always maps to a code
        END_IF
        IF bEnable AND bProductPresent AND (NOT bRejectFailed) THEN
            eState := E_DL_WeightRejectState.eSettling;   // 拒动锁存未清则不得自动恢复；其余条件齐备回稳定等待 / refuse auto-recovery until the latch is cleared
            bJudged := FALSE;                      // 重新判定 / re-judge from scratch
        END_IF

    ELSE
        eState := E_DL_WeightRejectState.eFault;   // 非法状态兜底 / illegal-state fallback
        eErr := DL_WCR_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 结论不可用 / verdict unusable
        bPass := FALSE;                            // 合格判定撤 / pass verdict dropped
        bRejectCmd := FALSE;                       // 剔除命令撤安全侧 / reject command dropped, safe side
        bRejectAct := FALSE;                       // 动作状态撤 / action state dropped
        fWeightFilteredG := DL_WCR_ZERO;           // 滤波值回零 / filtered value zeroed

END_CASE
END_FUNCTION_BLOCK
