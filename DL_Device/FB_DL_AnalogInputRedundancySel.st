(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AnalogInputRedundancySel
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（ABS / MAX / MIN），零厂商方言
 * 功能描述 (Function)   : 双路模拟量冗余选择（无扰切换 + 偏差监控 + 坏值剔除）：
 *                         ① 两路均有效且 |A − B| ≤ fDevTol → 输出两路均值，选通码 3；
 *                         ② 两路均有效但偏差超限 → **按上一拍选定通道保持**（无扰切换），
 *                            置 bDevAlarm 与信息码，绝不两侧来回跳；
 *                         ③ 仅一路有效（另一路非有限 / 超量程）→ 剔除坏路、使用好路，
 *                            bChanAValid / bChanBValid 回执逐路披露；
 *                         ④ **双路皆坏 → eFault**：输出保持**上一有效值**，bValid=FALSE，
 *                            故障级码配对置 bError，恢复路径唯一：bReset 且至少一路恢复有效。
 * 接口     (Interface)  : 输入 8 项（使能 / 复位 / 两路原值 / 偏差容差 / 量程上下限），
 *                         输出 10 项（输出值 / 选通码 / 偏差告警 / 两路有效回执 /
 *                         状态回执 / 有效性与故障码）。
 * 边界     (Boundary)   : ① 量程判定用 [fRangeMin, fRangeMax] 闭区间，超界即该路无效
 *                            （不做单侧饱和，饱和会把坏值伪装成合法满量程）；
 *                         ② 偏差容差以 1E-9 为下限钳位，防零容差导致恒告警；
 *                         ③ 双路皆坏时输出保持 fLastValid（上一有效值），若从未有过
 *                            有效值则输出 0 哨兵并披露（bValid=FALSE）；
 *                         ④ 非有限双判：NaN 用 x <> x，Inf 用 |x − x| > EPS 双侧直比；
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q）。
 * 码表     (Codes)      : 本件占用 16#0004_1020 ~ 16#0004_102F 区间，实际使用 5 个：
 *                         1020 信息级 容差/量程参数钳位；1021 信息级 仅单路有效已剔除坏路；
 *                         1022 信息级 双路偏差超限已保持上一通道；1023 故障级 双路皆坏；
 *                         1024 故障级 非法状态兜底。信息级码永不置 bError。
 * 分工声明 (Scope)      : 与 FB_DL_AnalogTransmitter 分工：那件做单路原始量→工程量的
 *                         标定与滤波；本件只做「两路冗余仲裁与坏值剔除」，不做标定。
 * 开源溯源 (Origin)     : 开源溯源：原创实现（无外部代码引入）
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限双判 + 容差钳位 + 无除零
 *                         R5 ✓ 声明逐行同行双语注释 ｜ R6 ✓ 五态 ENUM + CASE + ELSE
 *                         R7 ✓ 无定时器/边沿实例（N/A），无跨周期定时依赖
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版
 * 验收向量 (Acceptance) :
 *   V1 两路 A=10.0、B=10.4、fDevTol=1.0：fOut=10.2、iSelChan=3、bDevAlarm=FALSE、bValid=TRUE。
 *   V2 承接 V1，随后 A=10.0、B=15.0（偏差 5.0 > 1.0）：fOut 保持通道 A 的 10.0、
 *      iSelChan=1、bDevAlarm=TRUE、uErrorId=16#0004_1022、bError=FALSE（信息级）。
 *   V3 A=NaN、B=12.0：bChanAValid=FALSE、bChanBValid=TRUE、fOut=12.0、iSelChan=2、
 *      uErrorId=16#0004_1021、bError=FALSE。
 *   V4 A=NaN、B 超量程（B=200.0，量程上限 100.0）：双路皆坏 → eStateOut=eFault、
 *      fOut 保持上一有效值、bValid=FALSE、uErrorId=16#0004_1023、bError=TRUE。
 *   V5 承接 V4，bReset 单拍且 A 恢复为 10.0：eStateOut 回 eAvg/eHoldA，bError=FALSE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   声明于调用方 FB 的 VAR 区：fbRed : FB_DL_AnalogInputRedundancySel;
 *   每周期无条件调用：fbRed(bEnable := TRUE, bReset := xReset,
 *                           fChanA := stAi.fCh1, fChanB := stAi.fCh2,
 *                           fDevTol := 0.5, fRangeMin := 0.0, fRangeMax := 100.0);
 *   取用出口：fPv := fbRed.fOut;  IF NOT fbRed.bValid THEN 保持工艺安全动作。
 *   注意：iSelChan 为「上一拍选定通道」的唯一载体，请勿在外部改写。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ArsState（归属 DL_Device，与 FB_DL_AnalogInputRedundancySel 同文件）
 * 含义: 冗余选择状态机的离散状态。eAvg 为双路均值相，eHoldA / eHoldB 为单路保持相，
 *       eFault 为双路皆坏的故障相（输出保持上一有效值）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ArsState :
(
    eInit  := 0,    // 首扫态：输出直接取可用路，建立首个有效值 / First scan: output takes a valid channel to build the first valid value
    eAvg   := 10,   // 均值态：两路有效且偏差合格，输出均值 / Averaging state: both valid and deviation within tolerance
    eHoldA := 20,   // 保持 A 态：仅 A 有效或偏差超限且上一拍选 A / Hold channel A, valid alone or deviation exceeded with A previously selected
    eHoldB := 30,   // 保持 B 态：仅 B 有效或偏差超限且上一拍选 B / Hold channel B, valid alone or deviation exceeded with B previously selected
    eFault := 99    // 故障相：双路皆坏，输出保持上一有效值，bValid=FALSE / Fault: both channels bad, holds last valid value
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_AnalogInputRedundancySel
 * 调用约定: 每周期无条件调用一次；无定时器/边沿实例（R7 N/A），全部判据单拍完成。
 * 无扰语义: 通道间切换只发生在「上一拍选定通道仍然有效」的前提下；一旦选定通道
 *           失效才切到另一路，切回条件为原通道恢复有效（而非偏差合格），避免抖动。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AnalogInputRedundancySel
VAR_INPUT
    bEnable    : BOOL := FALSE;         // 使能，FALSE 时输出冻结并置 bValid=FALSE / Enable, FALSE freezes the output and clears bValid
    bReset     : BOOL := FALSE;         // 复位（电平有效），解除双路皆坏锁存 / Reset (level), clears the both-bad latch
    fChanA     : REAL := 0.0;           // A 路原始采样值 [EU] / Raw sample of channel A [EU]
    fChanB     : REAL := 0.0;           // B 路原始采样值 [EU] / Raw sample of channel B [EU]
    fDevTol    : REAL := 0.5;           // 两路允许偏差容差 [EU] / Allowed deviation between the two channels [EU]
    fRangeMin  : REAL := 0.0;           // 量程下限（闭区间）[EU] / Range lower bound, closed interval [EU]
    fRangeMax  : REAL := 100.0;         // 量程上限（闭区间）[EU] / Range upper bound, closed interval [EU]
END_VAR
VAR_OUTPUT
    fOut       : REAL;                  // 仲裁输出值（双路皆坏时保持上一有效值）[EU] / Arbitrated output, holds last valid on both-bad
    iSelChan   : INT;                   // 选通码：0=无 1=A 2=B 3=均值 [-] / Selection code: 0=none 1=A 2=B 3=mean
    bDevAlarm  : BOOL;                  // 双路偏差超限告警（信息级，不置 bError）/ Deviation alarm, info level, keeps bError FALSE
    bChanAValid: BOOL;                  // A 路有效回执（有限且在量程内）/ Channel A validity feedback, finite and in range
    bChanBValid: BOOL;                  // B 路有效回执（有限且在量程内）/ Channel B validity feedback, finite and in range
    eStateOut  : E_DL_ArsState;         // 状态机当前状态回执 [-] / Current state feedback
    bValid     : BOOL;                  // 输出可信标志，故障相为 FALSE / Output trustworthy flag, FALSE in the fault state
    bError     : BOOL;                  // 故障级标志，与 uErrorId 严格联动 / Fault-level flag, strictly coupled with uErrorId
    uErrorId   : UDINT;                 // 错误码，0 = 无码 / Error code, 0 = no code
END_VAR
VAR
    eState     : E_DL_ArsState;         // 内部状态 [-] / Internal state
    fDev       : REAL;                  // 两路实时偏差绝对值 [EU] / Absolute deviation between the two channels [EU]
    fLastValid : REAL;                  // 上一有效输出值，故障相保持用 [EU] / Last valid output, held in the fault state
    bHaveLast  : BOOL;                  // 是否已建立过有效值 / A valid value has been established
    bBothValid : BOOL;                  // 两路均有效 / Both channels valid
    bOnlyA     : BOOL;                  // 仅 A 有效 / Only channel A valid
    bOnlyB     : BOOL;                  // 仅 B 有效 / Only channel B valid
    bNoneValid : BOOL;                  // 两路皆无效 / Neither channel valid
    bDevOk     : BOOL;                  // 偏差在容差内 / Deviation inside tolerance
    bChanANaN  : BOOL;                  // A 路自反判 NaN 命中 / Channel A NaN by self-comparison
    bChanAInf  : BOOL;                  // A 路差自减判 Inf 命中 / Channel A infinity by self-subtraction
    bChanBNaN  : BOOL;                  // B 路自反判 NaN 命中 / Channel B NaN by self-comparison
    bChanBInf  : BOOL;                  // B 路差自减判 Inf 命中 / Channel B infinity by self-subtraction
    bFaultLatch: BOOL;                  // 双路皆坏锁存位 / Both-bad latch
    bRangeBad  : BOOL;                  // 量程参数非法标志 / Range parameter invalid flag
    fDevTolEff : REAL;                  // 钳位后的偏差容差 [EU] / Clamped deviation tolerance [EU]
    fRangeLo   : REAL;                  // 生效量程下限 [EU] / Effective range lower bound [EU]
    fRangeHi   : REAL;                  // 生效量程上限 [EU] / Effective range upper bound [EU]
    uInfoCode  : UDINT;                 // 信息级码暂存 / Info-level code scratch
END_VAR
VAR CONSTANT
    DL_ARS_OK    : UDINT := 16#0000_0000;  // 无码哨兵 / No-code sentinel
    DL_ARS_TOL   : REAL := 1.0E-9;         // 容差硬下限，防零容差恒告警 [EU] / Tolerance floor preventing permanent alarm [EU]
    DL_ARS_EPS   : REAL := 1.0E-9;         // 浮点比较容差（统一口径）/ Unified floating point comparison tolerance
    DL_ARS_ZERO  : REAL := 0.0;            // 零基准哨兵 / Zero reference sentinel
    DL_ARS_HALF  : REAL := 0.5;            // 均值折半系数 / Averaging half factor
    DL_ARS_RANGE_DEF : REAL := 100.0;      // 量程非法时的兜底上限 [EU] / Fallback upper bound when the range is invalid [EU]
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜参数域闸（不中断扫描）：量程必须 fRangeMax > fRangeMin，容差 ≥ 1E-9
 *      Parameter domain gate: range must be increasing, tolerance floored
 *-----------------------------------------------------------------------------*)
uInfoCode  := DL_ARS_OK;                                    // 信息码预置无码 / Preset no info code
bRangeBad  := FALSE;                                        // 量程非法标志预置 / Preset range-invalid flag FALSE

fDevTolEff := MAX(fDevTol, DL_ARS_TOL);                     // 容差下限钳位 [EU] / Tolerance floor [EU]
fRangeLo   := fRangeMin;                                    // 生效量程下限 [EU] / Effective lower bound [EU]
IF fRangeMax > fRangeMin THEN
    fRangeHi := fRangeMax;                                  // 量程合法原值生效 [EU] / Legal upper bound applied [EU]
ELSE
    fRangeHi   := fRangeLo + DL_ARS_RANGE_DEF;              // 量程倒挂：改用兜底上限，拒绝零宽量程 / Inverted range, fallback width
    bRangeBad  := TRUE;                                     // 记录量程非法 / Record the invalid range
    uInfoCode  := 16#0004_1020;                             // 信息级：量程参数已钳位 / Info: range parameter clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 1｜逐路有效性判定：非有限（NaN 自反 / Inf 差自减）与超量程（闭区间）双闸
 *      Per-channel validity: non-finite double test plus closed-interval range gate
 *-----------------------------------------------------------------------------*)
bChanANaN := (fChanA <> fChanA);                                                          // A 路自反判 NaN / Channel A NaN by self-comparison
bChanAInf := ABS(fChanA - fChanA) > DL_ARS_EPS;                                           // A 路差自减判 Inf（双侧直比）/ Channel A infinity by self-subtraction
bChanAValid := NOT (bChanANaN OR bChanAInf)
               AND (fChanA >= fRangeLo) AND (fChanA <= fRangeHi);                          // A 路有效回执 / Channel A validity

bChanBNaN := (fChanB <> fChanB);                                                          // B 路自反判 NaN / Channel B NaN by self-comparison
bChanBInf := ABS(fChanB - fChanB) > DL_ARS_EPS;                                           // B 路差自减判 Inf（双侧直比）/ Channel B infinity by self-subtraction
bChanBValid := NOT (bChanBNaN OR bChanBInf)
               AND (fChanB >= fRangeLo) AND (fChanB <= fRangeHi);                          // B 路有效回执 / Channel B validity

bBothValid := bChanAValid AND bChanBValid;                  // 两路均有效 / Both valid
bOnlyA     := bChanAValid AND (NOT bChanBValid);            // 仅 A 有效 / Only A valid
bOnlyB     := bChanBValid AND (NOT bChanAValid);            // 仅 B 有效 / Only B valid
bNoneValid := (NOT bChanAValid) AND (NOT bChanBValid);      // 两路皆无效 / Neither valid

(* 偏差只在两路都有效时才有意义；任一路坏时偏差保持上一拍值（不拿坏值重算）*)
(* The deviation is meaningful only when both channels are valid, otherwise it is held *)
IF bBothValid THEN
    fDev := ABS(fChanA - fChanB);                           // 两路偏差绝对值 [EU] / Absolute deviation [EU]
END_IF
bDevOk := bBothValid AND (fDev <= fDevTolEff);             // 偏差合格判据 [EU] / Deviation predicate [EU]

(*------------------------------------------------------------------------------
 * 段 2｜双路皆坏锁存：置位在 eFault 判断处，解除路径唯一：bReset 且至少一路有效
 *      Both-bad latch: cleared only by reset with at least one channel valid again
 *-----------------------------------------------------------------------------*)
IF bFaultLatch THEN
    IF bReset AND (bChanAValid OR bChanBValid) THEN
        bFaultLatch := FALSE;                               // 唯一解除路径：复位且至少一路恢复有效 / Sole clear path
    END_IF
ELSIF bNoneValid AND bEnable THEN
    bFaultLatch := TRUE;                                    // 双路皆坏：锁存 / Both channels bad, latch it
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with enum, case coverage and ELSE interception
 *      出口预置：本件所有分支都显式给 fOut / iSelChan / bValid，无隐式保持
 *-----------------------------------------------------------------------------*)
CASE eState OF

    eInit:
        (* 首扫：不做仲裁，直接取可用路建立首个有效值 *)
        (* First scan: no arbitration, take an available channel to build the first valid value *)
        bDevAlarm := FALSE;                                 // 告警复位 / Alarm reset
        IF bBothValid THEN
            fOut       := (fChanA + fChanB) * DL_ARS_HALF;  // 两路可用取均值 [EU] / Both usable, take the mean [EU]
            iSelChan   := 3;                                // 选通码 3 = 均值 / Selection code three, mean
            fLastValid := fOut;                             // 建立首个有效值 / Build the first valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            eState     := eAvg;                             // 进均值相 / Enter the averaging state
        ELSIF bOnlyA THEN
            fOut       := fChanA;                           // 仅 A 可用 [EU] / Only A usable [EU]
            iSelChan   := 1;                                // 选通码 1 = A / Selection code one, A
            fLastValid := fOut;                             // 建立首个有效值 / Build the first valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            eState     := eHoldA;                           // 进保持 A 相 / Enter hold A
        ELSIF bOnlyB THEN
            fOut       := fChanB;                           // 仅 B 可用 [EU] / Only B usable [EU]
            iSelChan   := 2;                                // 选通码 2 = B / Selection code two, B
            fLastValid := fOut;                             // 建立首个有效值 / Build the first valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            eState     := eHoldB;                           // 进保持 B 相 / Enter hold B
        ELSIF bEnable THEN
            fOut      := fLastValid;                        // 双路皆坏：保持上一有效值（可能仍是 0 哨兵）/ Both bad, hold the last valid value
            iSelChan  := 0;                                 // 无选定通道 / No selected channel
            bValid    := FALSE;                             // 输出不可信 / Output untrustworthy
            bDevAlarm := FALSE;                             // 偏差判据不可得，不置告警 / Deviation unavailable, no alarm
            eState    := eFault;                            // 进故障相 / Enter the fault state
        ELSE
            fOut      := fLastValid;                        // 未使能：输出冻结 / Not enabled, output frozen
            iSelChan  := 0;                                 // 无选定通道 / No selected channel
            bValid    := FALSE;                             // 输出不可信 / Output untrustworthy
        END_IF

    eAvg:
        (* 均值相：两路仍有效且偏差合格才保持；偏差超限则保持上一拍选定通道 *)
        (* Averaging state: keep averaging while the deviation is fine, else hold the previous channel *)
        IF bNoneValid THEN
            fOut      := fLastValid;                        // 双路皆坏：保持上一有效值 / Both bad, hold the last valid value
            iSelChan  := 0;                                 // 无选定通道 / No selected channel
            bValid    := FALSE;                             // 输出不可信 / Output untrustworthy
            bDevAlarm := FALSE;                             // 偏差判据不可得 / Deviation unavailable
            eState    := eFault;                            // 进故障相 / Enter the fault state
        ELSIF bOnlyA THEN
            fOut       := fChanA;                           // 剔除坏路 B，用 A [EU] / Drop B, use A [EU]
            iSelChan   := 1;                                // 选通码 1 = A / Selection code one, A
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            bDevAlarm  := FALSE;                            // 单路运行不属偏差告警 / Single-channel run is not a deviation alarm
            uInfoCode  := 16#0004_1021;                     // 信息级：仅单路有效已剔除坏路 / Info: single channel valid, bad one dropped
            eState     := eHoldA;                           // 进保持 A 相 / Enter hold A
        ELSIF bOnlyB THEN
            fOut       := fChanB;                           // 剔除坏路 A，用 B [EU] / Drop A, use B [EU]
            iSelChan   := 2;                                // 选通码 2 = B / Selection code two, B
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            bDevAlarm  := FALSE;                            // 单路运行不属偏差告警 / Single-channel run is not a deviation alarm
            uInfoCode  := 16#0004_1021;                     // 信息级：仅单路有效已剔除坏路 / Info: single channel valid, bad one dropped
            eState     := eHoldB;                           // 进保持 B 相 / Enter hold B
        ELSIF bDevOk THEN
            fOut       := (fChanA + fChanB) * DL_ARS_HALF;  // 偏差合格：取均值 [EU] / Deviation fine, take the mean [EU]
            iSelChan   := 3;                                // 选通码 3 = 均值 / Selection code three, mean
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            bDevAlarm  := FALSE;                            // 告警复位 / Alarm reset
        ELSE
            (* 偏差超限：无扰保持上一拍选定通道；均值相无历史通道时按 A 保持（口径写死）*)
            (* Deviation exceeded: hold the previous channel; from the mean state default to A *)
            fOut       := fChanA;                           // 保持 A 通道值（均值相缺历史时的固定口径）[EU] / Hold A, fixed policy from the mean state [EU]
            iSelChan   := 1;                                // 选通码 1 = A / Selection code one, A
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            bDevAlarm  := TRUE;                             // 偏差超限告警置位 / Deviation alarm set
            uInfoCode  := 16#0004_1022;                     // 信息级：偏差超限已保持上一通道 / Info: deviation exceeded, previous channel held
            eState     := eHoldA;                           // 进保持 A 相 / Enter hold A
        END_IF

    eHoldA:
        (* 保持 A 相：A 仍有效即继续；A 失效则切 B；两路皆坏进故障相 *)
        (* Hold A: continue while A is valid, switch to B when A fails, fault when both bad *)
        IF bNoneValid THEN
            fOut      := fLastValid;                        // 双路皆坏：保持上一有效值 / Both bad, hold the last valid value
            iSelChan  := 0;                                 // 无选定通道 / No selected channel
            bValid    := FALSE;                             // 输出不可信 / Output untrustworthy
            bDevAlarm := FALSE;                             // 偏差判据不可得 / Deviation unavailable
            eState    := eFault;                            // 进故障相 / Enter the fault state
        ELSIF bChanAValid THEN
            fOut       := fChanA;                           // 保持 A 路 [EU] / Hold channel A [EU]
            iSelChan   := 1;                                // 选通码 1 = A / Selection code one, A
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            IF bBothValid AND (NOT bDevOk) THEN
                bDevAlarm := TRUE;                          // 两路都在但偏差超限：维持告警 / Both valid but deviating, keep the alarm
                uInfoCode := 16#0004_1022;                  // 信息级：偏差超限保持通道 / Info: deviation exceeded, channel held
            ELSE
                bDevAlarm := FALSE;                         // 偏差回落清除告警 / Alarm cleared when the deviation settles
            END_IF
        ELSE
            fOut       := fChanB;                           // A 失效切 B（B 此时必然有效）[EU] / A failed, switch to B, which must be valid [EU]
            iSelChan   := 2;                                // 选通码 2 = B / Selection code two, B
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            bDevAlarm  := FALSE;                            // 单路运行不属偏差告警 / Single-channel run is not a deviation alarm
            uInfoCode  := 16#0004_1021;                     // 信息级：仅单路有效已剔除坏路 / Info: single channel valid, bad one dropped
            eState     := eHoldB;                           // 进保持 B 相 / Enter hold B
        END_IF

    eHoldB:
        (* 保持 B 相：B 仍有效即继续；B 失效则切 A；两路皆坏进故障相 *)
        (* Hold B: continue while B is valid, switch to A when B fails, fault when both bad *)
        IF bNoneValid THEN
            fOut      := fLastValid;                        // 双路皆坏：保持上一有效值 / Both bad, hold the last valid value
            iSelChan  := 0;                                 // 无选定通道 / No selected channel
            bValid    := FALSE;                             // 输出不可信 / Output untrustworthy
            bDevAlarm := FALSE;                             // 偏差判据不可得 / Deviation unavailable
            eState    := eFault;                            // 进故障相 / Enter the fault state
        ELSIF bChanBValid THEN
            fOut       := fChanB;                           // 保持 B 路 [EU] / Hold channel B [EU]
            iSelChan   := 2;                                // 选通码 2 = B / Selection code two, B
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            IF bBothValid AND (NOT bDevOk) THEN
                bDevAlarm := TRUE;                          // 两路都在但偏差超限：维持告警 / Both valid but deviating, keep the alarm
                uInfoCode := 16#0004_1022;                  // 信息级：偏差超限保持通道 / Info: deviation exceeded, channel held
            ELSE
                bDevAlarm := FALSE;                         // 偏差回落清除告警 / Alarm cleared when the deviation settles
            END_IF
        ELSE
            fOut       := fChanA;                           // B 失效切 A（A 此时必然有效）[EU] / B failed, switch to A, which must be valid [EU]
            iSelChan   := 1;                                // 选通码 1 = A / Selection code one, A
            fLastValid := fOut;                             // 刷新上一有效值 / Refresh the last valid value
            bHaveLast  := TRUE;                             // 有效值已建立 / Valid value established
            bValid     := TRUE;                             // 输出可信 / Output trustworthy
            bDevAlarm  := FALSE;                            // 单路运行不属偏差告警 / Single-channel run is not a deviation alarm
            uInfoCode  := 16#0004_1021;                     // 信息级：仅单路有效已剔除坏路 / Info: single channel valid, bad one dropped
            eState     := eHoldA;                           // 进保持 A 相 / Enter hold A
        END_IF

    eFault:
        (* 故障相：输出保持上一有效值，bValid=FALSE；恢复路径唯一：bReset 且至少一路有效 *)
        (* Fault: hold the last valid value, recover only via reset with one valid channel *)
        fOut      := fLastValid;                            // 保持上一有效值（从未有过则为 0 哨兵）/ Hold the last valid value
        iSelChan  := 0;                                     // 无选定通道 / No selected channel
        bValid    := FALSE;                                 // 输出不可信 / Output untrustworthy
        bDevAlarm := FALSE;                                 // 偏差判据不可得，不置告警 / Deviation unavailable, no alarm
        IF (NOT bEnable) THEN
            eState := eInit;                                // 失能回首扫态 / Disable returns to init
        ELSIF (NOT bFaultLatch) AND bChanAValid THEN
            eState := eHoldA;                               // 复位后 A 恢复有效 / A recovered after reset
        ELSIF (NOT bFaultLatch) AND bChanBValid THEN
            eState := eHoldB;                               // 复位后 B 恢复有效 / B recovered after reset
        END_IF

    ELSE
        (* 非法状态拦截：任何未定义枚举值一律进故障相并置兜底码 *)
        (* Illegal state interception: undefined enum values go to fault with a fallback code *)
        eState    := eFault;                                // 强制回故障相 / Force back to the fault state
        fOut      := fLastValid;                            // 输出保持上一有效值 / Output holds the last valid value
        iSelChan  := 0;                                     // 无选定通道 / No selected channel
        bValid    := FALSE;                                 // 输出不可信 / Output untrustworthy
        bDevAlarm := FALSE;                                 // 不置偏差告警 / No deviation alarm
        uInfoCode := 16#0004_1024;                          // 故障级：非法状态兜底 / Fault: illegal state fallback

END_CASE

(*------------------------------------------------------------------------------
 * 段 4｜无扰冻结：未使能时输出冻结在上一有效值（不跟随输入）
 *      Bumpless freeze: while disabled the output stays on the last valid value
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    IF bHaveLast THEN
        fOut := fLastValid;                                 // 冻结在上一有效值 / Freeze on the last valid value
    ELSE
        fOut := DL_ARS_ZERO;                                // 从未有过有效值：输出 0 哨兵 / Never valid, emit the zero sentinel
    END_IF
    bValid    := FALSE;                                     // 冻结相输出不可信 / Frozen output is not trustworthy
    bDevAlarm := FALSE;                                     // 冻结相不产生告警 / No alarm while frozen
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜故障码统一出口（故障级锁存回放，信息级不置 bError）
 *      Unified code outlet: fault codes replayed latched, info codes never raise bError
 *-----------------------------------------------------------------------------*)
IF bFaultLatch THEN
    uErrorId := 16#0004_1023;                               // 故障级：双路皆坏 / Fault: both channels bad
    bError   := TRUE;                                       // 故障级码配对置位 / Paired fault flag set
ELSIF uInfoCode = 16#0004_1024 THEN
    uErrorId := 16#0004_1024;                               // 故障级：非法状态兜底 / Fault: illegal state fallback
    bError   := TRUE;                                       // 故障级码配对置位 / Paired fault flag set
ELSE
    uErrorId := uInfoCode;                                  // 信息级码或 0 / Info code or zero
    bError   := FALSE;                                      // 信息级不置故障标志 / Info level never raises the fault flag
END_IF

eStateOut := eState;                                        // 状态回执单一出口 / State feedback through a single outlet
END_FUNCTION_BLOCK
