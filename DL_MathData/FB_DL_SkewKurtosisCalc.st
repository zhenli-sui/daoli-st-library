(*
  ==================================================================
  组件名 Component  : FB_DL_SkewKurtosisCalc
  分类   Category   : DL_MathData
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 在线偏度 / 峰度统计。Welford 高阶矩递推（单遍、数值稳
                      定），输出均值 / 偏度 g1 / 超额峰度 g2；非有限样本剔除
                      并计数；样本数不足或方差退化时统计量出口归零并降
                      bValid。与 StdDevOnline / CovarOnline 同族补口（高阶矩）。
  来源   Source     : t2-1-lgf-math（统计族待挖项）
  溯源   Origin     : Welford 递推为公开数值算法（教学资料），clean-room 自研
                      实现；未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: R_TRIG / SQRT，无私有库）
  分工声明 Split     : 与 FB_DL_StdDevOnline / FB_DL_CovarOnline 分工——StdDev
                      为一阶 / 二阶矩在线统计，Covar 为双序列协方差；本件补
                      三阶 / 四阶矩（偏度与峰度），不做双序列与回归。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 有效样本数 nCnt ≥ 4 才出偏度 / 峰度（四阶矩稳定性
                      门槛，不足时出口归零 + bValid = FALSE，信息级降级）；
                      二 二阶矩 _lrM2 ≤ 1E-300 视为方差退化：偏度 / 峰度归零
                      （等值序列无形状信息），bValid 仍为 TRUE；
                      三 非有限样本（NaN 自反 / Inf 差值自减双判据）剔除计
                      数 nNanCnt，不参与递推；
                      四 复位沿作用域：清累计量 / 清出口（两项逐项声明），
                      首扫执行与复位沿同款初始化（R310 _bInit）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 1 · 序号 4）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_SkewKurtosisCalc
VAR_INPUT
    fX     : LREAL := 0.0;  // 样本输入 [工程单位] / the sample input [engineering unit]
    bSample: BOOL := FALSE; // 样本有效电平，TRUE = 本拍样本参与统计 [-] / the sample valid level, true includes this scan
    bReset : BOOL := FALSE; // 复位上升沿清全部统计 [-] / reset rising edge clears all statistics
END_VAR
VAR_OUTPUT
    fMean   : LREAL := 0.0; // 均值出口 [工程单位] / the mean outlet [engineering unit]
    fSkew   : LREAL := 0.0; // 偏度出口 g1（无量纲）/ the skewness outlet, dimensionless
    fKurt   : LREAL := 0.0; // 超额峰度出口 g2（无量纲，正态为 0）/ the excess kurtosis outlet, dimensionless, zero for normal
    nCnt    : UDINT := 0;   // 有效样本数 [个] / the valid sample count
    nNanCnt : UDINT := 0;   // 剔除的非有限样本数 [个] / the excluded non finite sample count
    bValid  : BOOL := FALSE; // 统计量有效（nCnt ≥ 4 且形状可算）[-] / the statistics valid flag
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _lrM2   : LREAL := 0.0;  // 二阶中心矩累加器（Welford M2）[工程单位平方] / the second central moment accumulator [unit squared]
    _lrM3   : LREAL := 0.0;  // 三阶中心矩累加器（Welford M3）[工程单位立方] / the third central moment accumulator [unit cubed]
    _lrM4   : LREAL := 0.0;  // 四阶中心矩累加器（Welford M4）[工程单位四次方] / the fourth central moment accumulator [unit to the fourth]
    _lrN    : LREAL;         // 当前样本数实数副本 [个] / the current count as a real [count]
    _lrDlt  : LREAL;         // 本拍偏差 [工程单位] / the delta this scan [engineering unit]
    _lrDltN : LREAL;         // 归一偏差 [工程单位] / the normalized delta [engineering unit]
    _lrD2   : LREAL;         // 归一偏差平方 [工程单位平方] / the normalized delta squared
    _lrT1   : LREAL;         // Welford 一阶项 [工程单位平方] / the Welford first term
    _lrSd   : LREAL;         // 标准差工作量 [工程单位] / the standard deviation work value
END_VAR
VAR CONSTANT
    DL_SK_MINCNT : UDINT := 4;          // 统计量出口最小样本数 [个]（边界一）/ the minimum sample count for the shape outlets
    DL_SK_TINY   : LREAL := 1.0E-300;   // 方差退化阈值 [工程单位平方]（边界二）/ the variance degeneration threshold
    DL_SK_CNTMAX : UDINT := 4294967294; // 样本数累加钳定界 [个]，防 UDINT 回绕 / the count clamp against a wrap
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首扫初始化（R310）：与复位沿同款初始化块 / segment 1, the first scan init, the same block as the reset edge
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the first scan flag
    _lrM2 := 0.0; // 二阶矩清零 / clear M2
    _lrM3 := 0.0; // 三阶矩清零 / clear M3
    _lrM4 := 0.0; // 四阶矩清零 / clear M4
END_IF

// 段 2｜复位沿作用域：清累计量 / 清出口（两项逐项声明，边界四）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    nCnt := 0; // 作用域一：清有效样本数 / scope one, clear the count
    nNanCnt := 0; // 作用域一：清剔除计数 / scope one, clear the excluded count
    fMean := 0.0; // 作用域一：清均值出口 / scope one, clear the mean
    _lrM2 := 0.0; // 作用域一：清二阶矩 / scope one, clear M2
    _lrM3 := 0.0; // 作用域一：清三阶矩 / scope one, clear M3
    _lrM4 := 0.0; // 作用域一：清四阶矩 / scope one, clear M4
    fSkew := 0.0; // 作用域二：清偏度出口 / scope two, clear the skewness
    fKurt := 0.0; // 作用域二：清峰度出口 / scope two, clear the kurtosis
    bValid := FALSE; // 作用域二：清有效标志 / scope two, clear the valid flag
END_IF

// 段 3｜样本受理与非有限剔除（边界三）/ segment 3, the sample admission and the non finite exclusion
IF bSample THEN // 本拍有样本 / a sample this scan
    IF (fX = fX) AND ((fX - fX) = (fX - fX)) THEN // 有限样本双判据通过（R79）/ a finite sample by the dual verdicts
        IF nCnt < DL_SK_CNTMAX THEN // 计数未到钳定界 / below the count clamp
            _lrN := UDINT_TO_LREAL(nCnt) + 1.0; // 新样本数实数副本（≥1，除子安全）/ the new count as a real
            _lrDlt := fX - fMean; // 本拍偏差 / the delta
            _lrDltN := _lrDlt / _lrN; // 归一偏差（除子已证 ≥1）/ the normalized delta
            _lrD2 := _lrDltN * _lrDltN; // 归一偏差平方 / the normalized delta squared
            _lrT1 := _lrDlt * _lrDltN * (_lrN - 1.0); // Welford 一阶项 / the Welford first term
            _lrM4 := _lrM4 + _lrT1 * _lrD2 * (_lrN * _lrN - 3.0 * _lrN + 3.0) + 6.0 * _lrD2 * _lrM2 - 4.0 * _lrDltN * _lrM3; // 四阶矩递推 / the fourth moment recursion
            _lrM3 := _lrM3 + _lrT1 * _lrDltN * (_lrN - 2.0) - 3.0 * _lrDltN * _lrM2; // 三阶矩递推 / the third moment recursion
            _lrM2 := _lrM2 + _lrT1; // 二阶矩递推 / the second moment recursion
            fMean := fMean + _lrDltN; // 均值推进 / advance the mean
            nCnt := nCnt + 1; // 有效样本数推进 / advance the count
        ELSE // 已在钳定界（防回绕，拒绝新样本计数推进）/ at the clamp, the count frozen
            nCnt := DL_SK_CNTMAX; // 钳定保持 / hold at the clamp
        END_IF
    ELSE // 非有限样本剔除（边界三）/ a non finite sample excluded
        IF nNanCnt < DL_SK_CNTMAX THEN // 剔除计数防回绕 / the exclusion count wrap guard
            nNanCnt := nNanCnt + 1; // 剔除计数推进 / advance the excluded count
        END_IF
    END_IF
END_IF

// 段 4｜形状统计量出口计算（样本数与方差双门槛，边界一二）/ segment 4, the shape outlets
bValid := (nCnt >= DL_SK_MINCNT); // 有效标志：样本数门槛 / the valid flag, the count gate
IF bValid AND (_lrM2 > DL_SK_TINY) THEN // 样本足且方差未退化 / enough samples and a live variance
    _lrSd := SQRT(_lrM2 / UDINT_TO_LREAL(nCnt)); // 标准差工作量（除子已证 ≥4）/ the standard deviation work value
    fSkew := SQRT(UDINT_TO_LREAL(nCnt)) * _lrM3 / (_lrM2 * SQRT(_lrM2)); // g1 = √n·M3 / M2^1.5（除子已证 >0）/ the skewness, the divisor proven positive
    fKurt := UDINT_TO_LREAL(nCnt) * _lrM4 / (_lrM2 * _lrM2) - 3.0; // g2 = n·M4 / M2² - 3（除子已证 >0）/ the excess kurtosis, the divisor proven positive
ELSE // 不足或退化：出口归零（信息级降级，不置故障）/ short or degenerate, the outlets zeroed
    fSkew := 0.0; // 偏度归零 / zero the skewness
    fKurt := 0.0; // 峰度归零 / zero the kurtosis
END_IF

// 段 5｜出口非有限复检兜底（防御纵深，正常路径不可达）/ segment 5, the outlet recheck as defense in depth
IF (fSkew <> fSkew) OR ((fSkew - fSkew) <> (fSkew - fSkew)) THEN // 偏度非有限 / a non finite skewness
    fSkew := 0.0; // 归零兜底 / zero the outlet
    bValid := FALSE; // 降有效标志 / drop the valid flag
END_IF
IF (fKurt <> fKurt) OR ((fKurt - fKurt) <> (fKurt - fKurt)) THEN // 峰度非有限 / a non finite kurtosis
    fKurt := 0.0; // 归零兜底 / zero the outlet
    bValid := FALSE; // 降有效标志 / drop the valid flag
END_IF
END_FUNCTION_BLOCK
