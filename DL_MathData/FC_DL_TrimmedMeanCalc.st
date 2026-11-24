(*
  ==================================================================
  组件名 Component  : FC_DL_TrimmedMeanCalc
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0659 / 065A（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 双端截尾均值（稳健统计，抗野点污染的位置估计）：剔除非有限
                      样本后按升序索引对中段区间求均值。
  开源溯源 Origin    : 公开公式 clean-room，参考公开稳健统计教材的双端截尾均值
                      定义（分类与公式借鉴，零代码复制），本件实现、闸门与码位
                      100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；trimmed mean 公开统计定义
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / 委托），三平台通用
  依赖   Depends    : FC_DL_SortIndexLReal（索引排序属主，本件委托排序，R140）
  分工声明 Split     : FC_DL_MeanAbsDevCalc（离散度）/ FC_DL_MedianAbsDev（稳健
                      离散度）/ FB_DL_MovingAverage（滑窗均值）互引；本件为双端
                      截尾均值（稳健位置估计），填位置量缺口（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
                      委托件码位随其属主回传（R66）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限样本逐条剔除并计入局部 nNonFinite；nNonFinite 口径
                         **不外显**（R62-D7 定稿口径固化），剔除诊断请用
                         FC_DL_SignalStatistics；除子一律用剔除后的 nEff；
                      二 nCount 越域（< 1 或 > 256）或剔净后 nEff = 0 → 故障码
                         0659 早退（除子已证 ≥ 1 才进入均值段）；
                      三 uTrimLo + uTrimHi >= nEff → 组态码 065A 早退（禁把截尾
                         做成空集）；trim 以剔除后有效样本为基准（非入参计数）；
                      四 委托排序返回值与 bValid 由两个独立变量承接后合取
                         （R295 双承接）；委托码随属主回传（R66）；
                      五 均值区间 [uTrimLo, nEff−1−uTrimHi]，除子
                         (nEff − uTrimLo − uTrimHi) ≥ 1 由段 3 闸证明（禁除零）；
                      六 结果复检非有限 → 三件套兜底（R258）；
                      七 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
                      八 无全局、无外部变量、无物理地址、无指针。
  错误码 Codes      :
    16#0001_0659【故障级】有效样本数越域（nCount < 1 / > 256，或剔净后 nEff = 0）
    16#0001_065A【故障级】截尾组态非法（uTrimLo + uTrimHi >= nEff，截尾成空集）
  码位反证 Note     :
    0659 与 065A 不可合并：前者出口 nEff = 0（无任何有效样本），后者出口 nEff ≥ 1
    （有效样本存在但被截空），nEff 可由输出唯一还原场景（R90）；0659 合并
    「入参越域」与「剔净为空」的理由：两者出口组合完全同形（fMean = 0、nEff = 0、
    bValid = FALSE），按 R90 不另立。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 全同样本 + 任意 trim → 均值 = 该值
    V2 trim = 0/0 → 等价普通均值；V3 uTrimLo+uTrimHi = nEff → 码 065A 早退
    V4 nEff − trim = 1（只余 1 个）→ 均值 = 该样本
    V5 nCount = 0 → 码 0659；V6 nCount = 257 → 码 0659 早退
    V7 含 2 个 NaN → nEff 正确缩减（量化断言）
    V8 trim 单端不对称（lo = 2, hi = 0）→ 区间正确
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 2 · 序号 4）
  ==================================================================
*)
FUNCTION FC_DL_TrimmedMeanCalc : BOOL
VAR_IN_OUT
    afSamples : ARRAY[0..255] OF LREAL; // 样本序列 [工程单位]，只读 / the sample series, read only
END_VAR
VAR_INPUT
    nCount  : DINT := 0;    // 有效样本数入参 [个]，合法域 1..256 / the sample count, legal from one to two hundred fifty six
    uTrimLo : USINT := 0;   // 低端截去个数 [个] / the count trimmed from the low end
    uTrimHi : USINT := 0;   // 高端截去个数 [个] / the count trimmed from the high end
END_VAR
VAR_OUTPUT
    fMean   : LREAL := 0.0; // 截尾均值 [工程单位] / the trimmed mean
    nEff    : DINT := 0;    // 参与均值样本数 [个]（剔除非有限后）/ the effective sample count after dropping non finite samples
    bValid  : BOOL := FALSE; // 结果可用 [-] / the result usable flag
    eErr    : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
    bError  : BOOL := FALSE; // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    aVal      : ARRAY[0..255] OF LREAL; // 剔除非有限后的有效样本副本 [工程单位] / the finite sample copy
    aIdx      : ARRAY[0..255] OF DINT;  // 委托输出的排序索引排列 [下标] / the sorted permutation from the delegate
    k         : DINT := 0;    // 遍历索引 [下标] / the traversal index
    nNonFinite: DINT := 0;    // 剔除的非有限样本数 [个]（仅局部留档，不外显，R62-D7 口径；诊断请用 FC_DL_SignalStatistics）/ the dropped non finite count, local only and never exposed
    nCountUse : DINT := 0;    // 入参样本数接管量 [个] / the raw input count holder
    nTrim     : DINT := 0;    // 双端截去总数 [个]（升位防 USINT 和溢出）/ the total trimmed count widened before the sum
    nTrimLo   : DINT := 0;    // 低端截去数升位副本 [个] / the low trim count widened
    nTrimHi   : DINT := 0;    // 高端截去数升位副本 [个] / the high trim count widened
    nKeep     : DINT := 0;    // 参与均值样本数（除子）[个] / the kept sample count used as the divisor
    fSum      : LREAL := 0.0; // 区间样本和 [工程单位] / the interval sample sum
    fMeanUse  : LREAL := 0.0; // 均值工作副本 [工程单位] / the working mean copy
    bSortRet  : BOOL := FALSE; // 委托返回值承接量（独立承接，R295）/ the delegate return holder
    bSortValid: BOOL := FALSE; // 委托 bValid 承接量（独立承接，R295）/ the delegate valid holder
    uSortErr  : UDINT := 16#0000_0000; // 委托错误码承接量 [码] / the delegate error code holder
    bSortErr  : BOOL := FALSE; // 委托故障位承接量 / the delegate fault bit holder
    bSortOk   : BOOL := FALSE; // 返回值与可用位合取后的排序可用位 / the conjunction of the return value and the valid flag
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_TMC_NMAX  : DINT := 256;      // 样本容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_TMC_ONE   : DINT := 1;        // 整型一常量 [个] / the integer one constant
    DL_TMC_ZERO  : DINT := 0;        // 整型零常量 [个] / the integer zero constant
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, the preset of the return and every outlet
FC_DL_TrimmedMeanCalc := FALSE; // 返回值预置假 / preset the return false
fMean := 0.0; // 均值预置零 [工程单位] / preset the mean zero
nEff := DL_TMC_ZERO; // 有效样本数预置零 [个] / preset the effective count zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the error flag false
nNonFinite := DL_TMC_ZERO; // 剔除计数预置零 [个] / preset the dropped count zero
nCountUse := DL_TMC_ZERO; // 入参计数接管量预置零 [个] / preset the raw count holder zero
nTrim := DL_TMC_ZERO; // 截去总数预置零 [个] / preset the trimmed total zero
nTrimLo := DL_TMC_ZERO; // 低端截去数预置零 [个] / preset the low trim zero
nTrimHi := DL_TMC_ZERO; // 高端截去数预置零 [个] / preset the high trim zero
nKeep := DL_TMC_ZERO; // 除子预置零 [个] / preset the divisor zero
fSum := 0.0; // 区间和预置零 [工程单位] / preset the interval sum zero
fMeanUse := 0.0; // 均值工作副本预置零 [工程单位] / preset the working mean zero
bSortRet := FALSE; // 委托返回值承接量预置假 / preset the delegate return holder false
bSortValid := FALSE; // 委托可用位承接量预置假 / preset the delegate valid holder false
uSortErr := 16#0000_0000; // 委托码承接量预置零 [码] / preset the delegate code zero
bSortErr := FALSE; // 委托故障位承接量预置假 / preset the delegate fault holder false
bSortOk := FALSE; // 排序可用位预置假 / preset the sort usable bit false

// 段 2｜样本数域闸（边界二，早退禁除零）/ segment 2, the sample count domain gate
nCountUse := nCount; // 入参计数接管 [个] / take the raw count
IF (nCountUse < DL_TMC_ONE) OR (nCountUse > DL_TMC_NMAX) THEN // 计数越域 / the count is out of the domain
    eErr := 16#0001_0659; // 故障级：有效样本数越域 / fault grade, the effective sample count is out of the domain
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 3｜非有限样本剔除（边界一：除子口径 = 剔除后有效样本数）/ segment 3, drop the non finite samples
FOR k := DL_TMC_ZERO TO nCountUse - DL_TMC_ONE DO // 有界遍历（上界已证 ≤ 256）/ the bounded traversal with a proven ceiling
    IF (afSamples[k] = afSamples[k]) AND ((afSamples[k] - afSamples[k]) = (afSamples[k] - afSamples[k])) THEN // 有限样本 / a finite sample
        aVal[nEff] := afSamples[k]; // 有限样本写入副本 [工程单位] / copy the finite sample
        nEff := nEff + DL_TMC_ONE; // 有效计数推进 [个] / advance the effective count
    ELSE // 非有限样本 / a non finite sample
        nNonFinite := nNonFinite + DL_TMC_ONE; // 剔除计数推进（仅局部留档，不外显）/ advance the dropped count, local only
    END_IF
END_FOR
IF nEff < DL_TMC_ONE THEN // 剔净后无有效样本（与段 2 同码，出口组合不可区分，R90）/ no sample remains after the drop
    eErr := 16#0001_0659; // 故障级：有效样本数越域（此处为剔净后为空）/ fault grade, the effective count is empty after the drop
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 4｜截尾组态闸（边界三，trim 以 nEff 为基准；升位防 USINT 和回绕）/ segment 4, the trim configuration gate
nTrimLo := USINT_TO_DINT(uTrimLo); // 低端截去数升位 [个] / widen the low trim count
nTrimHi := USINT_TO_DINT(uTrimHi); // 高端截去数升位 [个] / widen the high trim count
nTrim := nTrimLo + nTrimHi; // 双端总数（DINT 域无回绕）[个] / the trimmed total in the widened domain
IF nTrim >= nEff THEN // 截尾成空集 / the trim leaves an empty set
    eErr := 16#0001_065A; // 故障级：截尾组态非法 / fault grade, the trim configuration is illegal
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，除子 nKeep 不可为零 / early return, the divisor can never reach zero
END_IF
nKeep := nEff - nTrim; // 参与均值样本数（除子）[个]，已证 ≥ 1 / the kept count, proven at least one

// 段 5｜委托索引排序（R140；返回值与可用位分承后合取，R295）/ segment 5, the delegated index sort
bSortRet := FC_DL_SortIndexLReal(afValues := aVal, nCount := nEff, aIdx => aIdx, bValid => bSortValid, eErr => uSortErr, bError => bSortErr); // 委托排序：两路各自承接 / delegate the sort into two distinct holders
bSortOk := bSortRet AND bSortValid; // 返回值与可用位合取（IEC 未规定两者的求值次序）/ conjoin the two signals since their evaluation order is unspecified
IF (NOT bSortOk) OR bSortErr THEN // 委托失败 / the delegate failed
    eErr := uSortErr; // 委托码回传（码随属主，R66）/ replay the delegate code
    bError := bSortErr; // 委托故障位回传 / replay the delegate fault bit
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 6｜区间求和（索引区间 [uTrimLo, nEff−1−uTrimHi]；除子 nKeep 已证 ≥ 1，边界五）/ segment 6, the interval sum over the trimmed range
FOR k := nTrimLo TO (nEff - DL_TMC_ONE) - nTrimHi DO // 有界遍历中段区间（区间端点已证合法）/ the bounded traversal over the kept range with proven endpoints
    fSum := fSum + aVal[aIdx[k]]; // 区间样本累加 [工程单位] / accumulate the kept samples
END_FOR
fMeanUse := fSum / DINT_TO_LREAL(nKeep); // 截尾均值 = 和 ÷ 参与数 [工程单位]，除子已证 ≥ 1 / the trimmed mean with the proven divisor

// 段 7｜结果复检兜底（三件套，R258）/ segment 7, the result recheck with the three part fallback
IF (fMeanUse <> fMeanUse) OR ((fMeanUse - fMeanUse) <> (fMeanUse - fMeanUse)) THEN // 结果非有限（理论上不可达，防御保留）/ a non finite result, unreachable by theory, kept as a defence
    fMean := 0.0; // 兜底安全值 [工程单位] / the bottom line safe value
    nEff := DL_TMC_ZERO; // 有效数清零（出口与故障场景同形）/ clear the effective count
    eErr := 16#0001_0659; // 故障级：结果非有限（与样本数越域同族一码，出口组合不可区分，R90）/ fault grade under the same family code
    bError := TRUE; // 置故障标志（R45 配对）/ raise the fault flag
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 8｜统一出口 / segment 8, the unified outlet
fMean := fMeanUse; // 均值出口 [工程单位] / the mean outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_TrimmedMeanCalc := TRUE; // 返回成功 / return success
END_FUNCTION
