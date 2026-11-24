(*
  ==================================================================
  组件名 Component  : FC_DL_PercentileRank
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0653（信息级）｜ 16#0001_0654 / 0656（故障级）
  版本   Version    : 1.0.1
  复杂度 Complexity  : 中
  功能   Purpose    : 值 → 百分位排名（0..100），即「当前值在历史分布中的位置」，
                      SPC / 过程能力定位用；三口径（弱 / 强 / 中位排名）显式可选。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 标准运算符与 §6.6.1 比较/选择语义
  平台   Platform   : 纯 IEC 61131-3（FOR / CASE / 四则 / 委托），三平台通用
  依赖   Depends    : FC_DL_SortIndexLReal（索引排序属主，本件委托排序，R140）
  分工声明 Split     : FC_DL_PercentileLReal（分位→值）/ FC_DL_WeightedPercentile（加权分位）
                      / FC_DL_QuantileCalc（分位族通用）为「分位 → 值」方向；本件是逆运算
                      「值 → 分位」。选型差异：限值设定用分位→值（给定分位求门限值），
                      SPC 定位用本件（给定实测值求它落在历史分布的哪一档）（R216 双向互引）。
  归属 Ownership     : E_DL_RankMethod 属主为本文件（全库唯一定义，R264）；引用件只引用
                      不重声明。委托件码位随其属主回传（R66）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 有效样本口径：非有限（NaN / ±Inf）样本逐条剔除并计入局部 nNonFinite，
                         全部判据的除子一律用剔除后的 nEff，禁用 nCount 直接作除子；
                         nNonFinite 口径定稿（v1.0.1 返修 R63 · 修 R62-D7 轻）：**不外显**
                         （维持局部留档、不出现在输出契约），剔除诊断请用
                         FC_DL_SignalStatistics（非有限样本计数口径属主）；
                      二 nCount 越域（< 1 或 > 256）判故障早退；剔除后 nEff = 0 同码处置
                         （两场景在出口上同为「无可排名样本」，合并为一码，R90 反证句见码表）；
                      三 fValue 非有限（NaN / ±Inf）判故障早退，禁把 NaN 当合格值参与比较；
                      四 排名口径非法（枚举越域）由 CASE ... ELSE 拦为 eMidRank 并置信息级
                         组态码，禁静默；
                      五 三口径公式：eWeak = nBelow / nEff；eStrong = (nBelow + nEqual) / nEff；
                         eMidRank = (nBelow + nEqual / 2) / nEff；全乘 100 得 [%]；
                      六 浮点判等只用于「与待定位值相等」的容差判定，禁用 = / <> 判等；
                      七 委托返回值与 bValid 由两个独立变量承接后合取（R62-D5 教训）；
                      八 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_0653【信息级】排名口径枚举越域，已落中位排名口径（不置 bError）
    16#0001_0654【故障级】有效样本数越域：nCount < 1 或 > 256，或剔除非有限后 nEff = 0
    16#0001_0656【故障级】数值非有限：fValue 为 NaN / ±Inf，或结果复检命中非有限（后者理论上不可达的兜底分支）
  码位反证 Note     :
    0654 合并「入参越域」与「剔净后为空」的理由：两者的出口组合完全相同（均为
    nBelow = 0、nEqual = 0、fPct = 0、bValid = FALSE），三组以内输出无法唯一还原该场景，
    按 R90 不另立码；0656 不可并入 0654，因 bValid 与 nEff 在两种场景下可唯一区分
    （前者 nEff ≥ 1、后者 nEff = 0）；0656 同时承担结果复检兜底：该分支与「fValue 非有限」
    在出口上完全同形（fPct = 0、bValid = FALSE、nBelow / nEqual 保持计数），三组以内输出
    无法区分，故按 R90 共用一码而不另立。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 全同样本、fValue 相等 → eWeak 0 / eStrong 100 / eMidRank 50（逐口径断言）
    V2 fValue 小于最小样本 → 0%；V3 大于最大样本 → 100%
    V4 单样本 nCount = 1 → 三口径 0 / 100 / 50
    V5 含 2 个 NaN + 6 个有效 → nEff = 6（除子已证 ≥ 1），排名按 6 计
    V6 nCount = 0 → 码 0654 + 早退（禁除零）；V7 nCount = 257 → 同码早退
    V8 eMethod = 99（非法枚举）→ 落 eMidRank + 码 0653（bError = FALSE）
    V9 fValue = NaN → 码 0656 + bValid = FALSE
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 3 · 序号 8）
    2026-11-21  v1.0.1  R63 返修 R5（R62-D7 轻）：nNonFinite 口径二选一定稿为「不外显」，
                        头注释与声明行注明诊断请用 FC_DL_SignalStatistics（不改接口）
  ==================================================================
*)
TYPE E_DL_RankMethod :
(
    eWeak    := 0, // 弱排名：只计严格小于的样本（同值全落上沿，保守低估）/ the weak rank counting strictly smaller samples only
    eStrong  := 1, // 强排名：计小于与相等的样本（同值全落上沿，偏乐观）/ the strong rank counting smaller and equal samples
    eMidRank := 2  // 中位排名：相等样本各计一半（同值取中点，统计口径最中性）/ the mid rank giving half credit to equal samples
);
END_TYPE

FUNCTION FC_DL_PercentileRank : BOOL
VAR_IN_OUT
    afSamples : ARRAY[0..255] OF LREAL; // 样本序列 [工程单位]，只读 / the sample series, read only
END_VAR
VAR_INPUT
    nCount  : DINT := 0;                          // 有效样本数入参 [个]，合法域 1..256 / the sample count, legal one to two hundred fifty six
    fValue  : LREAL := 0.0;                       // 待定位值 [工程单位]，必须有限 / the value to locate, must be finite
    eMethod : E_DL_RankMethod := E_DL_RankMethod.eMidRank; // 排名口径 [-] / the ranking convention
END_VAR
VAR_OUTPUT
    fPct   : LREAL; // 百分位排名 [%]，0..100 / the percentile rank in percent
    nBelow : DINT;  // 严格小于待定位值的样本数 [个] / the count of samples strictly below the value
    nEqual : DINT;  // 与待定位值相等的样本数 [个] / the count of samples equal to the value
    bValid : BOOL;  // 结果可用 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志，故障级码置位（R45 配对）/ the error flag raised with a fault level code
END_VAR
VAR
    aVal      : ARRAY[0..255] OF LREAL;        // 剔除非有限后的有效样本副本 [工程单位] / the finite sample copy
    aIdx      : ARRAY[0..255] OF DINT;         // 委托输出的排序索引排列 [下标] / the sorted permutation from the delegate
    k         : DINT := 0;                     // 遍历索引 [下标] / the traversal index
    nEff      : DINT := 0;                     // 剔除非有限后的有效样本数 [个]（除子）/ the effective sample count used as the divisor
    nNonFinite: DINT := 0;                     // 剔除的非有限样本数 [个]（仅局部留档，不外显不作除子，v1.0.1 定稿；诊断请用 FC_DL_SignalStatistics）/ the dropped non finite sample count, local only and never exposed, use the signal statistics component for diagnostics
    nCountUse : DINT := 0;                     // 钳位前的入参样本数接管量 [个] / the raw input count before the domain gate
    fPctUse   : LREAL := 0.0;                  // 排名百分比工作副本 [%] / the working percentile copy
    eUse      : E_DL_RankMethod := E_DL_RankMethod.eMidRank; // 归一后的排名口径 [-] / the normalized ranking convention
    bSortRet  : BOOL := FALSE;                 // 委托返回值承接量（独立承接）/ the delegate return holder
    bSortValid: BOOL := FALSE;                 // 委托 bValid 承接量（独立承接）/ the delegate valid holder
    uSortErr  : UDINT := 16#0000_0000;         // 委托错误码承接量 [码] / the delegate error code holder
    bSortErr  : BOOL := FALSE;                 // 委托故障位承接量 / the delegate fault bit holder
    bSortOk   : BOOL := FALSE;                 // 返回值与可用位合取后的排序可用位 / the conjunction of the return value and the valid flag
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_PRK_NMAX : DINT := 256;         // 样本容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_PRK_ONE : DINT := 1;            // 整型一常量 [个] / the integer one constant
    DL_PRK_ZERO : DINT := 0;           // 整型零常量 [个] / the integer zero constant
    DL_PRK_PCT100 : LREAL := 100.0;    // 百分制换算系数 [%] / the percent scaling factor
    DL_PRK_HALF : LREAL := 2.0;        // 相等样本折半除子 [-] / the halving divisor for the equal samples
    DL_PRK_EQEPS : LREAL := 1.0E-6;    // 相等判定容差 [工程单位]，禁用 = / <> 判等 / the equality tolerance, plain equality operators are forbidden
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）+ 局部量显式预置（R254）/ segment 1, the preset
FC_DL_PercentileRank := FALSE; // 返回值预置假 / preset the return false
fPct := 0.0; // 百分比预置零 [%] / preset the percentage zero
nBelow := 0; // 小于计数预置零 [个] / preset the below count zero
nEqual := 0; // 相等计数预置零 [个] / preset the equal count zero
bValid := FALSE; // 可用标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nEff := DL_PRK_ZERO; // 有效样本数预置零 [个] / preset the effective count zero
nNonFinite := DL_PRK_ZERO; // 剔除计数预置零 [个] / preset the dropped count zero
nCountUse := DL_PRK_ZERO; // 入参计数接管量预置零 [个] / preset the raw count holder zero
fPctUse := 0.0; // 百分比工作副本预置零 [%] / preset the working copy zero
bSortRet := FALSE; // 委托返回值承接量预置假 / preset the return holder false
bSortValid := FALSE; // 委托可用位承接量预置假 / preset the valid holder false
uSortErr := 16#0000_0000; // 委托码承接量预置零 [码] / preset the delegate code zero
bSortErr := FALSE; // 委托故障位承接量预置假 / preset the delegate fault holder false
bSortOk := FALSE; // 排序可用位预置假 / preset the sort usable bit false
eUse := E_DL_RankMethod.eMidRank; // 口径工作量预置中位排名（偏保守的中性口径）/ preset the convention to the neutral mid rank

// 段 2｜样本数域闸（边界二，早退禁除零）/ segment 2, the sample count domain gate
nCountUse := nCount; // 入参计数接管 [个] / take the raw count
IF (nCountUse < DL_PRK_ONE) OR (nCountUse > DL_PRK_NMAX) THEN // 计数越域 / the count is out of the domain
    eErr := 16#0001_0654; // 故障级：有效样本数越域 / fault grade, the effective sample count is out of the domain
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，绝不进入除法 / early return, no division is ever reached
END_IF

// 段 3｜待定位值非有限闸（边界三，NaN 与 ±Inf 逐个点名，R272）/ segment 3, the value finiteness gate
IF (fValue <> fValue) OR ((fValue - fValue) <> (fValue - fValue)) THEN // NaN 或 ±Inf / NaN or an infinity
    eErr := 16#0001_0656; // 故障级：待定位值非有限 / fault grade, the value to locate is not finite
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 4｜样本非有限剔除（边界一：除子口径 = 有效样本数，绝不用入参计数作除子）/ segment 4, drop the non finite samples
FOR k := 0 TO nCountUse - 1 DO // 有界遍历（上界已证 ≤ 256）/ the bounded traversal with a proven ceiling
    IF (afSamples[k] = afSamples[k]) AND ((afSamples[k] - afSamples[k]) = (afSamples[k] - afSamples[k])) THEN // 有限样本 / a finite sample
        aVal[nEff] := afSamples[k]; // 有限样本写入副本 [工程单位] / copy the finite sample
        nEff := nEff + DL_PRK_ONE; // 有效计数推进 [个] / advance the effective count
    ELSE // 非有限样本 / a non finite sample
        nNonFinite := nNonFinite + DL_PRK_ONE; // 剔除计数推进 [个] / advance the dropped count
    END_IF
END_FOR
IF nEff < DL_PRK_ONE THEN // 剔净后无可排名样本（与段 2 同码，出口组合不可区分，R90）/ no sample remains after the drop
    eErr := 16#0001_0654; // 故障级：有效样本数越域（此处为剔净后为空）/ fault grade, the effective count is empty after the drop
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退，除子已证 ≥ 1 才允许进入段 6 / early return, the divisor is proven at least one before the percentage segment
END_IF

// 段 5｜委托索引排序（R140；返回值与可用位分承后合取，R62-D5）/ segment 5, the delegated index sort
bSortRet := FC_DL_SortIndexLReal(afValues := aVal, nCount := nEff, aIdx => aIdx, bValid => bSortValid, eErr => uSortErr, bError => bSortErr); // 委托排序：两路各自承接 / delegate the sort into two distinct holders
bSortOk := bSortRet AND bSortValid; // 返回值与可用位合取（IEC 未规定两者的求值次序）/ conjoin the two signals since their evaluation order is unspecified
IF (NOT bSortOk) OR bSortErr THEN // 委托失败 / the delegate failed
    eErr := uSortErr; // 委托码回传（码随属主，R66）/ replay the delegate code
    bError := bSortErr; // 委托故障位回传 / replay the delegate fault bit
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 6｜排名计数（小于 / 相等，相等用容差判定，禁判等算符）/ segment 6, the rank counting with a tolerance equality test
FOR k := 0 TO nEff - 1 DO // 按排序序有界遍历 / the bounded traversal in the sorted order
    IF aVal[aIdx[k]] < fValue THEN // 严格小于 / strictly below
        nBelow := nBelow + DL_PRK_ONE; // 小于计数推进 [个] / advance the below count
    ELSIF ABS(aVal[aIdx[k]] - fValue) < DL_PRK_EQEPS THEN // 容差相等（浮点禁判等）/ equality inside the tolerance
        nEqual := nEqual + DL_PRK_ONE; // 相等计数推进 [个] / advance the equal count
    END_IF
END_FOR

// 段 7｜排名口径归一并计算百分比（边界四，CASE 必带 ELSE 兜底）/ segment 7, the convention normalization and the percentage
CASE eMethod OF
    E_DL_RankMethod.eWeak: // 弱排名口径 / the weak rank convention
        eUse := E_DL_RankMethod.eWeak; // 口径接管 / take the convention
        fPctUse := (DINT_TO_LREAL(nBelow) / DINT_TO_LREAL(nEff)) * DL_PRK_PCT100; // 弱排名百分比 [%] / the weak rank percentage
    E_DL_RankMethod.eStrong: // 强排名口径 / the strong rank convention
        eUse := E_DL_RankMethod.eStrong; // 口径接管 / take the convention
        fPctUse := ((DINT_TO_LREAL(nBelow) + DINT_TO_LREAL(nEqual)) / DINT_TO_LREAL(nEff)) * DL_PRK_PCT100; // 强排名百分比 [%] / the strong rank percentage
    E_DL_RankMethod.eMidRank: // 中位排名口径 / the mid rank convention
        eUse := E_DL_RankMethod.eMidRank; // 口径接管 / take the convention
        fPctUse := ((DINT_TO_LREAL(nBelow) + (DINT_TO_LREAL(nEqual) / DL_PRK_HALF)) / DINT_TO_LREAL(nEff)) * DL_PRK_PCT100; // 中位排名百分比 [%] / the mid rank percentage
    ELSE // 非法枚举值：落中位排名并置组态码（禁静默，边界四）/ an illegal enumeration falls back to the mid rank with a code
        eUse := E_DL_RankMethod.eMidRank; // 落中性口径 / fall back to the neutral convention
        fPctUse := ((DINT_TO_LREAL(nBelow) + (DINT_TO_LREAL(nEqual) / DL_PRK_HALF)) / DINT_TO_LREAL(nEff)) * DL_PRK_PCT100; // 中位排名百分比 [%] / the mid rank percentage
        eErr := 16#0001_0653; // 信息级：排名口径越域，已落中位排名 / informational, the convention is out of the domain and the mid rank was used
        bError := FALSE; // 信息级不置故障标志（R285）/ keep the error flag false, this is informational
END_CASE

// 段 8｜结果复检兜底（结果非有限必三件套，R258）/ segment 8, the result recheck with the three part fallback
IF (fPctUse <> fPctUse) OR ((fPctUse - fPctUse) <> (fPctUse - fPctUse)) THEN // 结果非有限（理论上不可达，防御保留）/ a non finite result, unreachable by theory, kept as a defence
    fPct := 0.0; // 兜底安全值 [%] / the bottom line safe value
    eErr := 16#0001_0656; // 故障级：待定位值非有限（同族三件套口径）/ fault grade under the same family code
    bError := TRUE; // 置故障标志（R45 配对）/ raise the fault flag
    bValid := FALSE; // 结果不可用 / the result is not usable
    RETURN; // 早退 / early return
END_IF

// 段 9｜统一出口 / segment 9, the unified outlet
fPct := fPctUse; // 百分比出口 [%] / the percentage outlet
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_PercentileRank := TRUE; // 返回成功 / return success
END_FUNCTION
