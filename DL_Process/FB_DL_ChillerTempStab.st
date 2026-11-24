(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ChillerTempStab
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（路线图 L259 已登记项）
 * 所属子库 (Sublibrary) : DL_Process / ProcessStability
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 冷冻水供水温度稳定性监视
 * 功能一句话 (Summary)  : 双代滑窗均值/标准差 + CV 判稳 + 不稳定确认延时。
 * 边界与安全 (Boundary) : ①温度 NaN 或超出 -40~120 ℃ 拒收并置码；
 *                         ②样本数不足最小值 → bStable=FALSE 且不判稳；
 *                         ③均值绝对值近零时 CV 分母防御（除零前判）；
 *                         ④不稳定确认 TON 无条件周期刷新；
 *                         ⑤bReset 清全部统计（重新起窗）。
 * 错误码    : 16#0005_035F 样本非法拒收（NaN 或超量程）——故障级（持续态）
 *             16#0005_0360 判稳确认超时未达成（持续不稳）——故障级（持续态）
 * 码位总账  : 16#0005_035F 用 / 16#0005_0360 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ChillerTempStab
VAR_INPUT
    fSupplyTemp : LREAL; // 供水温度 [℃] / Supply water temperature [degC]
    fCvLimit    : LREAL; // 变异系数判稳门限 [%] / CV stability limit [%]
    tConfirm    : TIME;  // 不稳定确认延时 [ms] / Instability confirm delay [ms]
    bReset      : BOOL;  // 复位：清统计重起窗 / Reset: clear statistics
    bEnable     : BOOL;  // 监视使能 / Monitoring enable
END_VAR
VAR_OUTPUT
    fMean            : LREAL; // 滑窗均值 [℃] / Sliding window mean [degC]
    fStdDev          : LREAL; // 滑窗标准差 [℃] / Sliding window std-dev [degC]
    fCv              : LREAL; // 变异系数 [%] / Coefficient of variation [%]
    bStable          : BOOL;  // 判稳结论 / Stability verdict
    bUnstableConfirm : BOOL;  // 不稳定确认（延时满足）/ Instability confirmed
    eErr             : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cHalves  : DINT  := 10;    // 窗内代数（双代近似滑窗）/ Window generations
    cMinSmp  : UDINT := 30;    // 最小样本数 / Minimum sample count
    cTempLo  : LREAL := -40.0; // 温度下限 [℃] / Temperature lower bound
    cTempHi  : LREAL := 120.0; // 温度上限 [℃] / Temperature upper bound
END_VAR
VAR
    fSumOld : LREAL; // 旧代样本和 / Previous generation sum
    fSqOld  : LREAL; // 旧代平方和 / Previous generation sum of squares
    fSumNew : LREAL; // 新代样本和 / Current generation sum
    fSqNew  : LREAL; // 新代平方和 / Current generation sum of squares
    uCntOld : UDINT; // 旧代样本数 / Previous generation count
    uCntNew : UDINT; // 新代样本数 / Current generation count
    iGen    : INT;   // 当前代序号 / Current generation index
    tonGen  : TON;   // 代轮转定时器（无条件刷新）/ Generation rotation timer
    tonUnst : TON;   // 不稳定确认定时器（无条件刷新）/ Instability confirm timer
    dwGenMs : DINT;  // 单代时长 [ms] / Generation duration [ms]
    fVarAll : LREAL; // 总体方差临时量 / Total variance temp
    bSmpOk  : BOOL;  // 本拍样本合法性 / Sample validity this cycle
END_VAR

// ---------- 代时长：确认窗 / 代数（下限防御） ----------
dwGenMs := TIME_TO_DINT(tConfirm) / cHalves;
IF dwGenMs < 1 THEN
    dwGenMs := 1;                             // 最小 1 ms 代 / Minimum 1 ms generation
END_IF
tonGen(IN := bEnable, PT := DINT_TO_TIME(dwGenMs));

// ---------- 复位与禁能清统计 ----------
IF bReset OR (NOT bEnable) THEN
    fSumOld := 0.0; fSqOld := 0.0; fSumNew := 0.0; fSqNew := 0.0;
    uCntOld := 0;   uCntNew := 0;  iGen := 0;
    fMean := 0.0; fStdDev := 0.0; fCv := 0.0;
    bStable := FALSE;
    bUnstableConfirm := FALSE;
END_IF

// ---------- 样本防御：NaN 或超量程拒收 ----------
bSmpOk := FALSE;
IF bEnable THEN
    eErr := 0;
    IF (fSupplyTemp <> fSupplyTemp) OR ((fSupplyTemp - fSupplyTemp) <> (fSupplyTemp - fSupplyTemp)) THEN
        eErr := 16#0005_035F;                 // NaN 拒收 / NaN rejected
    ELSIF (fSupplyTemp < cTempLo) OR (fSupplyTemp > cTempHi) THEN
        eErr := 16#0005_035F;                 // 超量程拒收 / Out-of-range rejected
    ELSE
        bSmpOk := TRUE;                       // 合法样本 / Valid sample
    END_IF
END_IF

// ---------- 合法样本入新代 ----------
IF bSmpOk THEN
    fSumNew := fSumNew + fSupplyTemp;         // 样本和 / Sample sum
    fSqNew  := fSqNew + fSupplyTemp * fSupplyTemp; // 平方和 / Square sum
    uCntNew := uCntNew + UDINT#1;             // 计数 / Count
END_IF

// ---------- 代轮转（与扭矩监视件同口径双代近似） ----------
IF tonGen.Q THEN
    iGen := iGen + 1;
    IF iGen >= cHalves THEN
        iGen := cHalves / 2;
        fSumOld := fSumNew; fSqOld := fSqNew; uCntOld := uCntNew; // 新代平移 / Shift
        fSumNew := 0.0; fSqNew := 0.0; uCntNew := 0;              // 新代清零 / Clear
    END_IF
END_IF

// ---------- 均值/标准差/CV 计算（除法全部前判零） ----------
IF (uCntOld + uCntNew) >= cMinSmp THEN
    fMean := (fSumOld + fSumNew) / UDINT_TO_LREAL(uCntOld + uCntNew);   // 均值 / Mean
    fVarAll := (fSqOld + fSqNew) / UDINT_TO_LREAL(uCntOld + uCntNew) - fMean * fMean; // 方差 / Variance
    IF fVarAll < 0.0 THEN
        fVarAll := 0.0;                       // 数值误差负方差钳零 / Clamp tiny negative variance
    END_IF
    fStdDev := SQRT(fVarAll);                 // 标准差 / Std-dev
    IF ABS(fMean) > 1.0E-9 THEN
        fCv := fStdDev / ABS(fMean) * 100.0;  // 变异系数 / CV in percent
    ELSE
        fCv := 0.0;                           // 近零均值 CV 防御 / Near-zero mean guard
    END_IF
    bStable := fCv <= fCvLimit;               // 判稳结论 / Stability verdict
ELSE
    fMean := 0.0;                             // 样本不足不出值 / Insufficient samples
    fStdDev := 0.0;
    fCv := 0.0;
    bStable := FALSE;                         // 未满窗不判稳 / No verdict before window filled
END_IF

// ---------- 无条件周期刷新：不稳定确认定时器 ----------
tonUnst(IN := bEnable AND (NOT bStable), PT := tConfirm);
IF tonUnst.Q THEN
    bUnstableConfirm := TRUE;                 // 确认成立 / Confirmed
    eErr := 16#0005_0360;                     // 判稳超时未达成码 / Never-stable confirm code
ELSE
    bUnstableConfirm := FALSE;                // 未确认即撤销 / Withdrawn if unconfirmed
END_IF

END_FUNCTION_BLOCK
