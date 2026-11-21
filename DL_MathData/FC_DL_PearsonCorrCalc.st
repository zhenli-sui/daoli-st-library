(*
  ==================================================================
  组件名 Component  : FC_DL_PearsonCorrCalc
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_065B / 065C / 065D（故障级）｜ 16#0001_065E（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 双通道皮尔逊相关系数 r ∈ [−1, 1]，测点交叉诊断基元
                      （同源传感器相关失效、通道接错线检测）。
  开源溯源 Origin    : 公开公式 clean-room，参考公开统计学教材的皮尔逊积矩相关
                      定义（分类与公式借鉴，零代码复制），本件实现、闸门与码位
                      100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；Pearson r = Sxy /
                      SQRT(Sxx×Syy) 公开统计定义
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / SQRT），三平台通用
  依赖   Depends    : 仅 Standard.library（SQRT 属标准内建）
  分工声明 Split     : FB_DL_CrossCorrelationDelay 为互相关时延估计属主（求滞后
                      拍数）；FB_DL_SensorPairPlausibility 为偏差 / 漂移互校；
                      本件为归一化相关强度；三件互引（R216）。SQRT 原语经派单
                      规格明写授权（除子 SQRT(Sxx×Syy)），本件为相关系数属主。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 配对剔除口径（写死）：X 或 Y 任一为非有限则**整对剔除**
                         （非各自剔除）——相关系数定义在样本对上，拆对剔除会
                         引入伪相关；nPairs = 剔除后有效对数；
                      二 nPairs ≤ 2（相关系数无定义）→ 故障码 065C 早退；
                      三 常量通道退化：Sxx ≤ 0 或 Syy ≤ 0（单通道方差为零，
                         相关系数无定义）→ 故障码 065D 早退（禁除零）；
                         ABS(Sxx×Syy) < 1.0E-12 防下溢分支同码处置（两场景出口
                         同形：fCorr = 0、bValid = FALSE，R90 不另立）；
                      四 数值口径：单遍累加 Σx / Σy / Σx² / Σy² / Σxy 后按
                         定义式展开（nPairs ≥ 3 已证，除子安全）；
                      五 |r| > 1.0（浮点数值误差）→ 钳回 ±1 并置信息级 065E
                         （不置 bError，R285）；
                      六 结果复检非有限 → 三件套兜底（R258）；
                      七 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      八 无全局、无外部变量、无物理地址、无指针。
  错误码 Codes      :
    16#0001_065B【故障级】样本对数越域（nCount < 1 / > 256）
    16#0001_065C【故障级】有效样本对数 ≤ 2（相关系数无定义）
    16#0001_065D【故障级】常量通道退化（Sxx ≤ 0 或 Syy ≤ 0）或乘积下溢
                         （ABS(Sxx×Syy) < 1.0E-12）
    16#0001_065E【信息级】|r| > 1.0 浮点数值误差，已钳回 ±1（不置 bError）
  码位反证 Note     :
    065B / 065C / 065D 三码不可合并：三者出口 nPairs 互异（越域 nPairs = 0、
    对数不足 nPairs ∈ [1,2]、常量退化 nPairs ≥ 3），可由 nPairs 唯一还原场景
    （R90）；065D 合并「常量通道」与「乘积下溢」：两场景出口组合同形
    （fCorr = 0、nPairs ≥ 3、bValid = FALSE），按 R90 不另立。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 完全线性 y = 2x → r ≈ +1（|r| ≤ 1 断言）；V2 y = −x → r ≈ −1
    V3 独立随机 → |r| < 0.1；V4 X 常数 → 码 065D 早退
    V5 单样本 / 双样本 → 码 065C 早退；V6 X 含 1 个 NaN → 整对剔除，
       nPairs 量化断言；V7 nCount = 0 → 码 065B
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 2 · 序号 5）
  ==================================================================
*)
FUNCTION FC_DL_PearsonCorrCalc : BOOL
VAR_IN_OUT
    afX : ARRAY[0..255] OF LREAL; // 通道 X 样本 [工程单位]，只读 / the channel X samples, read only
    afY : ARRAY[0..255] OF LREAL; // 通道 Y 样本 [工程单位]，只读 / the channel Y samples, read only
END_VAR
VAR_INPUT
    nCount  : DINT := 0; // 样本对数入参 [对]，合法域 1..256 / the pair count, legal from one to two hundred fifty six
END_VAR
VAR_OUTPUT
    fCorr   : LREAL := 0.0; // 相关系数 [−]，−1..1 / the correlation coefficient inside the unit interval
    nPairs  : DINT := 0;    // 有效样本对数 [对]（配对剔除后）/ the effective pair count after the paired drop
    bValid  : BOOL := FALSE; // 结果可用 [-] / the result usable flag
    eErr    : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL := FALSE; // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    aXVal     : ARRAY[0..255] OF LREAL; // 剔除后 X 有效副本 [工程单位] / the effective copy of channel X
    aYVal     : ARRAY[0..255] OF LREAL; // 剔除后 Y 有效副本 [工程单位] / the effective copy of channel Y
    k         : DINT := 0;    // 遍历索引 [下标] / the traversal index
    nCountUse : DINT := 0;    // 入参对数接管量 [对] / the raw input count holder
    fSx       : LREAL := 0.0; // Σx 累加量 [工程单位] / the sum of x
    fSy       : LREAL := 0.0; // Σy 累加量 [工程单位] / the sum of y
    fSxx      : LREAL := 0.0; // Σx² 累加量 [工程单位²] / the sum of x squared
    fSyy      : LREAL := 0.0; // Σy² 累加量 [工程单位²] / the sum of y squared
    fSxy      : LREAL := 0.0; // Σxy 累加量 [工程单位²] / the sum of the cross products
    fMx       : LREAL := 0.0; // X 均值 [工程单位] / the mean of x
    fMy       : LREAL := 0.0; // Y 均值 [工程单位] / the mean of y
    fDxx      : LREAL := 0.0; // 中心化离差平方和 Sxx [工程单位²] / the centered sum of squares of x
    fDyy      : LREAL := 0.0; // 中心化离差平方和 Syy [工程单位²] / the centered sum of squares of y
    fDxy      : LREAL := 0.0; // 中心化叉积和 Sxy [工程单位²] / the centered cross product sum
    fDen      : LREAL := 0.0; // 归一化除子 SQRT(Sxx×Syy) [工程单位²] / the normalization divisor
    fCorrUse  : LREAL := 0.0; // 相关系数工作副本 [−] / the working correlation copy
    nPairsUse : DINT := 0;    // 有效对数工作副本 [对] / the working pair count
VAR CONSTANT
    DL_PCC_NMAX  : DINT := 256;       // 样本容量上界 [对]，与数组容量一致 / the capacity aligned with the arrays
    DL_PCC_MIN   : DINT := 3;         // 相关系数可定义最少对数 [对] / the minimum pair count for a defined correlation
    DL_PCC_ONE   : DINT := 1;         // 整型一常量 [对] / the integer one constant
    DL_PCC_ZERO  : DINT := 0;         // 整型零常量 [对] / the integer zero constant
    DL_PCC_DENMIN: LREAL := 1.0E-12;  // 除子防下溢门限 [工程单位⁴] / the divisor underflow threshold
    DL_PCC_ONE_R : LREAL := 1.0;      // 单位一常量 [−]（钳位界）[-] / the unit constant used as the clamp bound
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and every outlet
FC_DL_PearsonCorrCalc := FALSE; // 返回值预置假 / preset the return false
fCorr := 0.0; // 相关系数预置零 [−] / preset the correlation zero
nPairs := DL_PCC_ZERO; // 有效对数预置零 [对] / preset the pair count zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the error flag false
nCountUse := DL_PCC_ZERO; // 入参对数接管量预置零 [对] / preset the raw count holder zero
nPairsUse := DL_PCC_ZERO; // 有效对数工作副本预置零 [对] / preset the working pair count zero
fSx := 0.0; // Σx 预置零 [工程单位] / preset the sum of x zero
fSy := 0.0; // Σy 预置零 [工程单位] / preset the sum of y zero
fSxx := 0.0; // Σx² 预置零 [工程单位²] / preset the sum of x squared zero
fSyy := 0.0; // Σy² 预置零 [工程单位²] / preset the sum of y squared zero
fSxy := 0.0; // Σxy 预置零 [工程单位²] / preset the cross sum zero
fMx := 0.0; // X 均值预置零 [工程单位] / preset the mean of x zero
fMy := 0.0; // Y 均值预置零 [工程单位] / preset the mean of y zero
fDxx := 0.0; // Sxx 预置零 [工程单位²] / preset the centered sum of squares zero
fDyy := 0.0; // Syy 预置零 [工程单位²] / preset the centered sum of squares zero
fDxy := 0.0; // Sxy 预置零 [工程单位²] / preset the centered cross sum zero
fDen := 0.0; // 除子预置零 [工程单位²] / preset the divisor zero
fCorrUse := 0.0; // 相关系数工作副本预置零 [−] / preset the working correlation zero
k := DL_PCC_ZERO; // 索引预置零 / preset the index zero

// 段 2｜样本对数域闸（边界八，早退禁除零）/ segment 2, the pair count domain gate
nCountUse := nCount; // 入参对数接管 [对] / take the raw count
IF (nCountUse < DL_PCC_ONE) OR (nCountUse > DL_PCC_NMAX) THEN // 对数越域 / the count is out of the domain
    eErr := 16#0001_065B; // 故障级：样本对数越域 / fault grade, the pair count is out of the domain
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 3｜配对剔除（边界一：任一通道非有限则整对剔除）/ segment 3, the paired drop
FOR k := DL_PCC_ZERO TO nCountUse - DL_PCC_ONE DO // 有界遍历（上界已证 ≤ 256）/ the bounded traversal with a proven ceiling
    IF ((afX[k] = afX[k]) AND ((afX[k] - afX[k]) = (afX[k] - afX[k]))
    AND (afY[k] = afY[k]) AND ((afY[k] - afY[k]) = (afY[k] - afY[k]))) THEN // 整对有限 / the whole pair is finite
        aXVal[nPairsUse] := afX[k]; // X 写入有效副本 [工程单位] / copy the x sample
        aYVal[nPairsUse] := afY[k]; // Y 写入有效副本 [工程单位] / copy the y sample
        nPairsUse := nPairsUse + DL_PCC_ONE; // 有效对数推进 [对] / advance the pair count
    END_IF // 任一通道非有限：整对丢弃（不拆对）/ either channel broken, the whole pair is dropped
END_FOR
nPairs := nPairsUse; // 有效对数出口 [对] / export the pair count
IF nPairsUse < DL_PCC_MIN THEN // 有效对数 ≤ 2：相关系数无定义（边界二）/ too few pairs for a defined correlation
    eErr := 16#0001_065C; // 故障级：有效样本对数不足 / fault grade, the effective pairs are too few
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，除子段不可达 / early return, the divisor segment is unreachable
END_IF

// 段 4｜单遍累加（nPairs ≥ 3 已证，除子安全，边界四）/ segment 4, the single pass accumulation
FOR k := DL_PCC_ZERO TO nPairsUse - DL_PCC_ONE DO // 有界遍历有效对 / the bounded traversal over the effective pairs
    fSx := fSx + aXVal[k]; // Σx 累加 [工程单位] / accumulate the sum of x
    fSy := fSy + aYVal[k]; // Σy 累加 [工程单位] / accumulate the sum of y
    fSxx := fSxx + (aXVal[k] * aXVal[k]); // Σx² 累加 [工程单位²] / accumulate the sum of squares
    fSyy := fSyy + (aYVal[k] * aYVal[k]); // Σy² 累加 [工程单位²] / accumulate the sum of squares
    fSxy := fSxy + (aXVal[k] * aYVal[k]); // Σxy 累加 [工程单位²] / accumulate the cross products
END_FOR
fMx := fSx / DINT_TO_LREAL(nPairsUse); // X 均值 [工程单位]，除子已证 ≥ 3 / the mean of x with the proven divisor
fMy := fSy / DINT_TO_LREAL(nPairsUse); // Y 均值 [工程单位] / the mean of y
fDxx := fSxx - (DINT_TO_LREAL(nPairsUse) * fMx * fMx); // Sxx = Σx² − n·mx² [工程单位²] / the centered sum of squares of x
fDyy := fSyy - (DINT_TO_LREAL(nPairsUse) * fMy * fMy); // Syy = Σy² − n·my² [工程单位²] / the centered sum of squares of y
fDxy := fSxy - (DINT_TO_LREAL(nPairsUse) * fMx * fMy); // Sxy = Σxy − n·mx·my [工程单位²] / the centered cross product sum

// 段 5｜常量通道退化与除子防下溢闸（边界三，禁除零）/ segment 5, the constant channel and the underflow gate
IF (fDxx <= 0.0) OR (fDyy <= 0.0) OR (ABS(fDxx * fDyy) < DL_PCC_DENMIN) THEN // 常量通道或乘积下溢 / a constant channel or an underflowing product
    fCorr := 0.0; // 兜底安全值 [−] / the bottom line safe value
    eErr := 16#0001_065D; // 故障级：常量通道退化 / fault grade, a constant channel degeneration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，除法不可达 / early return, the division is unreachable
END_IF

// 段 6｜相关系数计算（除子已证 > 0 且 ≥ 下溢门限）/ segment 6, the correlation computation
fDen := SQRT(fDxx * fDyy); // 归一化除子 [工程单位²]，已证有限且非零 / the normalization divisor proven finite and nonzero
fCorrUse := fDxy / fDen; // 皮尔逊相关系数 [−] / the Pearson correlation coefficient

// 段 7｜|r| > 1 钳位（浮点数值误差，信息级 065E，不置 bError）/ segment 7, the unit interval clamp with an informational code
IF ABS(fCorrUse) > DL_PCC_ONE_R THEN // 数值误差越单位圆 / a numerical overshoot beyond the unit circle
    IF fCorrUse > 0.0 THEN // 正向越界 / a positive overshoot
        fCorrUse := DL_PCC_ONE_R; // 钳回 +1 [−] / clamp to plus one
    ELSE // 负向越界 / a negative overshoot
        fCorrUse := -DL_PCC_ONE_R; // 钳回 −1 [−] / clamp to minus one
    END_IF
    eErr := 16#0001_065E; // 信息级：|r| 越界已钳回（不置 bError，R285）/ informational, the coefficient was clamped
END_IF

// 段 8｜结果复检兜底（三件套，R258）/ segment 8, the result recheck with the three part fallback
IF (fCorrUse <> fCorrUse) OR ((fCorrUse - fCorrUse) <> (fCorrUse - fCorrUse)) THEN // 结果非有限（理论上不可达，防御保留）/ a non finite result, unreachable by theory, kept as a defence
    fCorr := 0.0; // 兜底安全值 [−] / the bottom line safe value
    eErr := 16#0001_065D; // 故障级：常量通道退化（同族一码，出口组合不可区分，R90）/ fault grade under the same family code
    bError := TRUE; // 置故障标志（R45 配对）/ raise the fault flag
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 9｜统一出口 / segment 9, the unified outlet
fCorr := fCorrUse; // 相关系数出口 [−] / the correlation outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_PearsonCorrCalc := TRUE; // 返回成功 / return success
END_FUNCTION
