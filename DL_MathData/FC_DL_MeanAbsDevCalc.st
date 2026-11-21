(*
  ==================================================================
  组件名 Component  : FC_DL_MeanAbsDevCalc
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : 均值绝对偏差 MAD-mean = mean(|xᵢ − mean|)，两遍法。
  来源   Source     : self-std（公开统计语义自研）
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / ABS），三平台通用
  分工声明 Split     : 与 FC_DL_MedianAbsDev（中位数域属主）分工——后者以中位数
                      为中心（对离群点稳健）；本件以均值为中心（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 nCount < 1 置信息级码不计算（nCount = 0 无均值可言）；
                      二 计数 > 256 钳位续算置信息级；
                      三 元素非有限逐个点名判故障拒绝（R272 全量）；
                      四 均值非有限传播闸：均值算出后复检，非有限同判故障；
                      五 除子 nUse 已证 ≥ 1（域闸下界），无除零风险；
                      六 结果复检兜底同拍置 eErr + bError + bValid 三件套（R258）；
                      七 只读入参数组，不改调用方数据；无状态纯函数（R254）。
  错误码   Codes    :
    16#0001_063C【信息级】计数越域已钳位（<1 早退，>256 钳位续算）
    16#0001_063D【故障级】元素或均值非有限，拒绝出值
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 值 1/2/3 → mean=2、MAD-mean=2/3；V2 值 5/5/5 → 0
    V3 nCount=0 → 码 063C、bValid=FALSE；V4 含 NaN → 码 063D、bError=TRUE
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 2 · 序号 7）
  ==================================================================
*)
FUNCTION FC_DL_MeanAbsDevCalc : BOOL
VAR_IN_OUT
    afValues : ARRAY[0..255] OF LREAL; // 数值序列 [工程单位]，只读 / the value series, read only
END_VAR
VAR_INPUT
    nCount : DINT; // 序列个数 [个]，合法域 1..256 / the count, legal from one to two hundred fifty six
END_VAR
VAR_OUTPUT
    fMad   : LREAL; // 均值绝对偏差 [工程单位] / the mean absolute deviation
    fMean  : LREAL; // 序列均值 [工程单位] / the series mean
    bValid : BOOL;  // 结果可用标志 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志，故障级码置位（R45 配对）/ the error flag
END_VAR
VAR
    k     : DINT;  // 遍历索引 [下标] / the traversal index
    nUse  : DINT;  // 钳位后的个数 [个] / the clamped count
    fSum  : LREAL; // 一遍和累加器 [工程单位] / the first pass sum accumulator
    fDev  : LREAL; // 二遍偏差累加器 [工程单位] / the second pass deviation accumulator
END_VAR
VAR CONSTANT
    DL_MAD_NMAX : DINT := 256; // 序列容量上界 [个]，与数组容量一致 / the capacity aligned with the array
END_VAR

// 段 1｜返回值与错误状态预置安全值 + 局部量显式预置（R45 / R254）/ segment 1, the preset
FC_DL_MeanAbsDevCalc := FALSE; // 返回值预置假 / preset the return false
fMad := 0.0; // 偏差预置零 / preset the deviation zero
fMean := 0.0; // 均值预置零 / preset the mean zero
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nUse := 0; // 个数预置零 / preset the count zero
fSum := 0.0; // 一遍和预置零 / preset the sum zero
fDev := 0.0; // 二遍偏差预置零 / preset the deviation accumulator zero

// 段 2｜计数域闸（<1 早退，>256 钳位，边界一二）/ segment 2, the count gate
IF nCount < 1 THEN // 空序列无均值（边界一）/ an empty series has no mean
    eErr := 16#0001_063C; // 信息级：计数越域已钳位（信息级不置 bError）/ informational, the count clamped
    RETURN; // 早退 / early return
END_IF
nUse := nCount; // 域内接管 / take the count
IF nUse > DL_MAD_NMAX THEN // 超容量（边界二）/ above the capacity
    nUse := DL_MAD_NMAX; // 钳到容量 / clamp to the capacity
    eErr := 16#0001_063C; // 信息级：计数越域已钳位 / informational, the count clamped
END_IF

// 段 3｜一遍求和 + 元素非有限逐个点名（R272，边界三）/ segment 3, the first pass sum with the element wise gate
FOR k := 0 TO nUse - 1 DO // 有界遍历 / the bounded traversal
    IF (afValues[k] <> afValues[k]) OR ((afValues[k] - afValues[k]) <> (afValues[k] - afValues[k])) THEN // 元素非有限 / the element is not finite
        eErr := 16#0001_063D; // 故障级：元素非有限 / fault grade, a non finite element
        bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
        RETURN; // 早退 / early return
    END_IF
    fSum := fSum + afValues[k]; // 求和累加 / accumulate the sum
END_FOR
fMean := fSum / DINT_TO_LREAL(nUse); // 均值（除子已证 ≥ 1，边界五）/ the mean with a proven divisor
IF (fMean <> fMean) OR ((fMean - fMean) <> (fMean - fMean)) THEN // 均值非有限传播闸（边界四）/ the mean finiteness gate
    eErr := 16#0001_063D; // 故障级：均值非有限 / fault grade, a non finite mean
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    RETURN; // 早退 / early return
END_IF

// 段 4｜二遍偏差累加（均值已证有限）/ segment 4, the second pass deviation accumulation
FOR k := 0 TO nUse - 1 DO // 有界遍历 / the bounded traversal
    fDev := fDev + ABS(afValues[k] - fMean); // 绝对偏差累加 / accumulate the absolute deviation
END_FOR
fMad := fDev / DINT_TO_LREAL(nUse); // 偏差均值（除子 nUse 已证 ≥ 1，同段 3 口径）/ the deviation mean with the proven divisor

// 段 5｜结果复检兜底（非有限同拍三件套，边界六）/ segment 5, the result recheck
IF (fMad <> fMad) OR ((fMad - fMad) <> (fMad - fMad)) THEN // 结果非有限 / the result is not finite
    fMad := 0.0; // 兜底安全值 / the bottom line safe value
    eErr := 16#0001_063D; // 故障级：结果非有限 / fault grade, the non finite result
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_MeanAbsDevCalc := TRUE; // 返回成功 / return success
END_FUNCTION
