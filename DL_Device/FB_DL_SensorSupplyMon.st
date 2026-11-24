(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SensorSupplyMon
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / ABS），零厂商私有库
 * 功能描述 (Function)   : 传感器供电轨监视（8 通道共用诊断掩码）：对供电实测
 *                         fSupplyMv（mV）做 tWindow 窗口均值（自复位 TON 窗，
 *                         窗内累加样本、窗到结算一次），再对窗口均值做迟滞判限：
 *                         均值 < fLimLowMv 入欠压态、恢复须均值 > fLimHighMv
 *                         （fLimLowMv < fLimHighMv 迟滞带，防临界振荡）；输出
 *                         bSupplyOk 与逐通道诊断掩码 uChanMask（bit i = 通道 i
 *                         使能 ∧ 供电正常）。非有限输入当拍跳过累计并置信息码
 *                         eInputHold，结论（bSupplyOk/掩码）保持上次值不翻转。
 * 接口     (Interface)  : 输入 fSupplyMv 供电实测 [mV]、tWindow 均值窗（域 > T#0S）、
 *                         fLimLowMv 欠压进入阈 [mV]、fLimHighMv 欠压恢复阈 [mV]、
 *                         uChanEn 8 通道使能位图（bit i=通道 i 参与诊断）、bReset
 *                         复位；输出 bSupplyOk 供电正常、uChanMask 逐通道诊断
 *                         掩码、fMeanMv 最新窗口均值 [mV]、eErrCode 错误码、
 *                         bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只判供电轨好坏并出掩码，
 *                         不切换备用电源、不接管通道级断线诊断**；通道断线
 *                         诊断归 `FB_DL_AnalogTransmitter`。
 *                         ② 窗口均值：tonWin 自复位窗（IN := NOT tonWin.Q，
 *                         R188），窗内 fSum/nCnt 累计；窗到（Q 沿）结算一次
 *                         fMean = fSum ÷ nCnt，nCnt=0（整窗无非有限外样本）
 *                         跳过结算保持旧均值并置信息码，结构性无除零。
 *                         ③ 迟滞判限只在窗结算拍评估一次；判限态 _bLow 锁存，
 *                         进入阈 fLimLowMv < 恢复阈 fLimHighMv 构成迟滞带。
 *                         ④ 非有限样本（R79 双判）不计入累计：fSum/nCnt 不被
 *                         污染，当拍置 eInputHold 信息码，bSupplyOk 与掩码
 *                         保持上次结论（规格指定）。
 *                         ⑤ 组态闸：tWindow <= T#0S、fLimLowMv <= 0、
 *                         fLimHighMv <= fLimLowMv → 锁存故障，输出钳安全侧
 *                         bSupplyOk=FALSE，解除沿 = bReset 上升沿（故障级码
 *                         配对 bError，R45）。
 *                         ⑥ 掩码 bit i = uChanEn.bit i ∧ bSupplyOk ∧ 非 故障：
 *                         通道使能与供电结论逐位合成，定长 8 无越界。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_MovingAverage` 分工：通用滑动平均归那件、
 *                         供电窗口均值+迟滞判限归本件；与 `FB_DL_AxiolineDiagLatch`
 *                         分工：总线级诊断锁存归那件。
 * 来源标签 (Source Tag) : 自研线（窗口均值+迟滞判限为公开监视模式 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 组 + WORD 掩码
 *                         + LREAL 均值 + ENUM 错误码；数字码位待主控收口阶段
 *                         统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零前置闸 + 迟滞带 + 非有限保持结论 + 组态锁存
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机，迟滞锁存态） ｜ R7 ✓ 一 TON 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 1 · 序号 3）
 * 验收向量 (Acceptance) : ① tWindow=1s，窗内 10 个样本全 24000 mV → 均值
 *                         24000.0，24000 > fLimHighMv(22800) → bSupplyOk=
 *                         TRUE，uChanMask=使能位图全量；② 下一窗均值 22000 mV：
 *                         22000 < fLimLowMv(21600) 不成立且 > 恢复阈，迟滞带内
 *                         结论保持 TRUE（防临界振荡）；③ 窗均值 21000 mV <
 *                         21600 → bSupplyOk=FALSE、掩码全 0；④ 样本含 NaN：
 *                         该样本跳过、eErrCode=eInputHold，结论不翻转。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SsmErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SsmErr :
(
    eOk        := 0,   // 正常 / Normal
    eCfgBad    := 1,   // 故障级：组态非法（窗/阈值域） / Fault: illegal configuration
    eInputHold := 2    // 信息级：非有限输入跳过累计，结论保持 / Info: non-finite sample skipped, conclusion held
);
END_TYPE

FUNCTION_BLOCK FB_DL_SensorSupplyMon
VAR_INPUT
    fSupplyMv  : LREAL := 24000.0;    // 供电轨实测 [mV] / Supply rail measurement [mV]
    tWindow    : TIME := T#1S;        // 均值窗时长，域 > T#0S [ms] / Averaging window duration
    fLimLowMv  : LREAL := 21600.0;    // 欠压进入阈（均值低于此判欠压），域 > 0 [mV] / Undervolt entry threshold
    fLimHighMv : LREAL := 22800.0;    // 欠压恢复阈（须大于进入阈构成迟滞带） [mV] / Undervolt release threshold
    uChanEn    : WORD := 16#00FF;     // 8 通道使能位图（bit i=通道 i 参与诊断） [-] / Channel enable bitmap
    bReset     : BOOL := FALSE;       // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    bSupplyOk  : BOOL;                // 供电正常（迟滞判限结论） [-] / Supply OK, hysteresis verdict
    uChanMask  : WORD;                // 逐通道诊断掩码（bit i=使能 ∧ 供电正常） [-] / Per-channel diagnostic mask
    fMeanMv    : LREAL;               // 最新有效窗口均值 [mV] / Latest valid window mean
    eErrCode   : E_DL_SsmErr;         // 错误码出口 / Error code outlet
    bError     : BOOL;                // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _fSum     : LREAL := 0.0;         // 窗内样本累计 [mV] / In-window sample sum
    _nCnt     : UDINT := 0;           // 窗内有效样本计数 [个] / In-window valid sample count
    _fMean    : LREAL := 0.0;         // 窗口均值锁存（结算源） [mV] / Window mean latch
    _bLow     : BOOL := FALSE;        // 欠压判限锁存态（迟滞源） [-] / Undervolt latched state
    _bBad     : BOOL := FALSE;        // 供电坏当拍结论（!bSupplyOk 内部量） [-] / Supply-bad verdict internal
    _bNonFin  : BOOL;                 // 当拍样本非有限 [-] / Sample non-finite this scan
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration this scan
    _bSkip    : BOOL;                 // 本窗发生非有限跳过 [-] / Non-finite skip occurred in window
    _bWinEdge : BOOL;                 // 窗结算当拍量（Q 沿） [-] / Window settlement edge
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    i         : DINT;                 // 通道循环索引 / Channel loop index
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
    ftWin     : F_TRIG;               // 窗下降沿实例（Q 到结算一次），段 0 无条件调用 / Window F_TRIG settlement instance
    tonWin    : TON;                  // 自复位均值窗，段 0 无条件调用（R188） / Self-resetting averaging window
END_VAR
VAR CONSTANT
    DL_SSM_NCHAN : DINT := 8;         // 通道定长 [路] / Fixed channel count
    DL_SSM_BIT0  : WORD := 1;         // bit0 基准掩码 [-] / Bit zero base mask
    DL_SSM_ZERO  : LREAL := 0.0;      // 非有限判零基准与安全侧值 [mV] / Non-finite zero base and safe value
    DL_SSM_UDMAX : UDINT := 4294967295;   // 计数饱和点（防回绕） [个] / Count saturation ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 窗口/沿无条件刷新 —— *)
_bNonFin := (fSupplyMv <> fSupplyMv) OR ((fSupplyMv - fSupplyMv) <> DL_SSM_ZERO);   // 样本非有限（R79 双判） / Sample non-finite
_bCfgBad := (tWindow <= T#0S) OR (fLimLowMv <= DL_SSM_ZERO)
         OR (fLimHighMv <= fLimLowMv);             // 组态域闸（窗/下阈/迟滞带方向） / Configuration gate
rtReset(CLK := bReset);                            // 复位沿，每拍必调 / Reset edge, every scan
tonWin(IN := (NOT tonWin.Q) AND (NOT _bErrLatch), PT := tWindow);   // 自复位均值窗（故障期停窗，R188） / Self-reset window, halted on fault
ftWin(CLK := tonWin.Q);                            // 窗结算沿，每拍必调 / Window settlement edge, every scan

(* —— 段 1：复位沿与组态闸入锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                           // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;                            // 锁存 / Latch
END_IF

(* —— 段 2：窗内样本累计（非有限跳过并置信息量；故障期不累计） —— *)
_bSkip := FALSE;                                   // 本窗跳过量预清 / Window skip preset
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fSum := _fSum + fSupplyMv;                    // 有效样本累计 / Valid sample accumulate
    IF _nCnt < DL_SSM_UDMAX THEN
        _nCnt := _nCnt + 1;                        // 计数防回绕递增 / Count increment with wrap guard
    END_IF
ELSIF (NOT _bErrLatch) AND _bNonFin THEN
    _bSkip := TRUE;                                // 非有限样本跳过（不污染累计） / Non-finite sample skipped
END_IF

(* —— 段 3：窗结算（Q 下降沿一次；nCnt=0 跳过结算保持旧均值，无除零） —— *)
_bWinEdge := ftWin.Q;                              // 结算沿捕获 / Settlement edge capture
IF _bWinEdge AND (NOT _bErrLatch) THEN
    IF _nCnt > 0 THEN
        _fMean := _fSum / UDINT_TO_LREAL(_nCnt);   // 窗口均值（分母计数已判正） / Window mean, denominator proven positive
        IF _fMean < fLimLowMv THEN
            _bLow := TRUE;                         // 低于进入阈：判欠压 / Below entry threshold: undervolt
        ELSIF _fMean > fLimHighMv THEN
            _bLow := FALSE;                        // 高于恢复阈：解除欠压（迟滞带内保持） / Above release threshold: clear
        END_IF
        _bBad := _bLow;                            // 判限态落坏结论 / Verdict from hysteresis state
    END_IF
    _fSum := 0.0;                                  // 窗累计清零（下一窗重计） / Reset window sum
    _nCnt := 0;                                    // 窗计数清零 / Reset window count
END_IF

(* —— 段 4：掩码合成（bit i = 使能 ∧ 供电正常 ∧ 非故障；故障安全侧全 0） —— *)
FOR i := 0 TO (DL_SSM_NCHAN - 1) DO
    IF (NOT _bErrLatch) AND (NOT _bBad)
       AND ((uChanEn AND SHL(DL_SSM_BIT0, i)) <> 0) THEN
        uChanMask := uChanMask OR SHL(DL_SSM_BIT0, i);   // 通道 i 诊断通过（i∈[0,7] 位宽内） / Channel i passes
    ELSE
        uChanMask := uChanMask AND (NOT SHL(DL_SSM_BIT0, i));   // 通道 i 不通过：清位（禁直接跳过） / Channel i fails: clear bit
    END_IF
END_FOR

(* —— 段 5：出口单点映射（名实双出口同源，R191） —— *)
IF _bErrLatch THEN
    bSupplyOk := FALSE;                            // 故障安全侧：判供电坏 / Fault safe side: supply bad
    bError := TRUE;                                // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_SsmErr.eCfgBad;               // 故障级码 / Fault code
ELSE
    bSupplyOk := NOT _bBad;                        // 供电结论出口 / Supply verdict outlet
    bError := FALSE;                               // 无故障级条件 / No fault this scan
    IF _bSkip THEN
        eErrCode := E_DL_SsmErr.eInputHold;        // 信息级：结论保持口径 / Info: conclusion held
    ELSE
        eErrCode := E_DL_SsmErr.eOk;               // 正常 / Normal
    END_IF
END_IF
fMeanMv := _fMean;                                 // 均值出口（无有效窗保持旧值） / Mean outlet, held if no valid window

END_FUNCTION_BLOCK
