(*
  ==================================================================
  组件名 Component  : FC_DL_WeightedPercentile
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.1
  功能   Purpose    : 加权百分位数插值（PercentileLReal 升版邻位，权向量参与排序序）。
  来源   Source     : t2-1-lgf-math（LGF Math 百分位族加权变体）
  平台   Platform   : 纯 IEC 61131-3（FOR / 委托 / 四则），三平台通用
  分工声明 Split     : 与 FC_DL_PercentileLReal（等权属主）与 FC_DL_SortIndexLReal
                      （索引排序属主）分工——本件逐级委托后者排序，不重实现
                      排序内核（R140 委托优先，R216 双向互引）。
  依赖     Depends  : FC_DL_SortIndexLReal（DL_MathData 属主，本件委托排序）
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 分位 p 钳位 [0,1]：p < 0 钳 0、p > 1 钳 1，置信息级码；
                         p = 0 → 排序首元，p = 1 → 排序末元（两端点向量自证）；
                      二 权向量闸：任一 wᵢ < 0、非有限或 Σw = 0 判故障级拒绝
                         （无权可分即无分位可言）；
                      三 插值除子 (cum_k − cum_{k-1}) ≤ 0 时直接取右元值（禁除零）；
                      四 结果复检兜底同拍置 eErr + bError + bValid 三件套（R258）；
                      五 只读入参数组，不改调用方数据（PercentileLReal 纪律）；
                      六 无状态纯函数：局部量段 1 显式预置（R254）。
  错误码   Codes    :
    16#0001_0639【信息级】计数越域已钳位或分位 p 越域已钳位到 [0,1]
    16#0001_063A【故障级】权向量非法（负权 / 非有限 / Σw = 0），拒绝出值
    16#0001_063B【故障级】结果非有限（复检兜底）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 值 1/2/3 权 1/1/2、p=0.5 → 目标 2.0 落第 2 位 → 2.0
    V2 p=0 → 首元；p=1 → 末元；p=1.5 → 钳 1 码 0639
    V3 权全零 → 码 063A、bValid=FALSE
    V4 正常 8 样本 → 结果与 v1.0.0 逐位一致（无行为回退，v1.0.1 回归向量）
    V5 委托件返回 TRUE 但内部 bValid=FALSE（构造）→ bSortOk=FALSE（v1.0.1 新增可捕获组合）
  无回退断言 Regression  :
    v1.0.1 仅改委托调用的承接方式（返回值落 _bSortRet、bValid 映射落 _bSortValid，再合取），
    不触碰段 2 / 段 3 / 段 5 / 段 6 的任何判据、钳位与插值公式，故三平台同一输入下
    结果与 v1.0.0 逐位一致（位级相等，非容差相等）。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 2 · 序号 6）
    2026-11-21  v1.0.1  R62-D5 返修：委托返回值落 _bSortRet、bValid => 落 _bSortValid，再 bSortOk := _bSortRet AND _bSortValid（禁双写同一变量）；头注释补「与 v1.0.0 结果逐位一致」无回退断言说明
  ==================================================================
*)
FUNCTION FC_DL_WeightedPercentile : BOOL
VAR_IN_OUT
    afValues : ARRAY[0..255] OF LREAL; // 数值序列 [工程单位]，只读 / the value series, read only
    afWeights : ARRAY[0..255] OF LREAL; // 权序列 [权]，只读 / the weight series, read only
END_VAR
VAR_INPUT
    nCount : DINT;  // 序列个数 [个]，合法域 1..256 / the count, legal from one to two hundred fifty six
    fP     : LREAL; // 目标分位 [-]，域 [0,1] 钳位 / the target quantile, clamped to the unit domain
END_VAR
VAR_OUTPUT
    fOut   : LREAL; // 加权百分位结果 [工程单位] / the weighted percentile result
    bValid : BOOL;  // 结果可用标志 [-] / the result usable flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志，故障级码置位（R45 配对）/ the error flag
END_VAR
VAR
    aOrd    : ARRAY[0..255] OF DINT; // 排序索引排列（委托输出）/ the sorted permutation from the delegate
    k       : DINT;  // 遍历索引 [下标] / the traversal index
    nUse    : DINT;  // 钳位后的个数 [个] / the clamped count
    fPUse   : LREAL; // 钳位后的分位 [-] / the clamped quantile
    fWsum   : LREAL; // 权和 [权] / the weight sum
    fTarget : LREAL; // 目标累积权 [权] / the target cumulative weight
    fCum    : LREAL; // 当前累积权 [权] / the current cumulative weight
    fCumPrv : LREAL; // 前一位置累积权 [权] / the previous cumulative weight
    fVL     : LREAL; // 插值左元值 [工程单位] / the left interpolation value
    fVR     : LREAL; // 插值右元值 [工程单位] / the right interpolation value
    fFrac   : LREAL; // 插值分数 [-] / the interpolation fraction
    nHit    : DINT;  // 命中位置 [下标] / the hit position
    bFound  : BOOL;  // 命中标记 [-] / the hit flag
    bSortOk : BOOL;  // 委托排序可用位（返回值与 bValid 合取）/ the delegate sort usable bit, the conjunction
    _bSortRet : BOOL; // 委托函数返回值承接变量（独立承接，禁双写，R62-D5）/ the delegate return value holder, never double written
    _bSortValid : BOOL; // 委托 bValid 输出承接变量（独立承接，禁双写）/ the delegate valid output holder, never double written
    bSortEr : BOOL;  // 委托排序故障位 [-] / the delegate sort fault bit
    uSortEr : UDINT; // 委托排序错误码 [码] / the delegate error code
    bClamp  : BOOL;  // 钳位发生标记 [-] / the clamp happened flag
END_VAR
VAR CONSTANT
    DL_WPC_NMAX : DINT := 256; // 序列容量上界 [个]，与数组容量一致 / the capacity aligned with the array
END_VAR

// 段 1｜返回值与错误状态预置安全值 + 局部量显式预置（R45 / R254）/ segment 1, the preset
FC_DL_WeightedPercentile := FALSE; // 返回值预置假 / preset the return false
fOut := 0.0; // 结果预置零 / preset the result zero
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nUse := 0; // 个数预置零 / preset the count zero
fPUse := 0.0; // 分位预置零 / preset the quantile zero
fWsum := 0.0; // 权和预置零 / preset the weight sum zero
fTarget := 0.0; // 目标累积权预置零 / preset the target zero
fCum := 0.0; // 累积权预置零 / preset the cumulative zero
fCumPrv := 0.0; // 前位累积权预置零 / preset the previous zero
fVL := 0.0; // 左元值预置零 / preset the left value zero
fVR := 0.0; // 右元值预置零 / preset the right value zero
fFrac := 0.0; // 分数预置零 / preset the fraction zero
nHit := 0; // 命中位置预置零 / preset the hit zero
bFound := FALSE; // 命中标记预置假 / preset the hit flag false
bSortOk := FALSE; // 委托成功位预置假 / preset the delegate bit false
_bSortRet := FALSE; // 委托返回值承接量预置假 / preset the return holder false
_bSortValid := FALSE; // 委托可用位承接量预置假 / preset the valid holder false
bSortEr := FALSE; // 委托故障位预置假 / preset the delegate fault bit false
uSortEr := 16#0000_0000; // 委托码预置零 / preset the delegate code zero
bClamp := FALSE; // 钳位标记预置假 / preset the clamp flag false
FOR k := 0 TO 255 DO // 排列数组预置恒等 / preset the permutation array
    aOrd[k] := k; // 恒等索引 / the identity index
END_FOR

// 段 2｜计数与分位域闸（钳位显式，边界一）/ segment 2, the count and quantile gates
IF nCount < 1 THEN // 空序列无分位 / an empty series has no percentile
    eErr := 16#0001_0639; // 信息级：计数越域已钳位（信息级不置 bError）/ informational, the count clamped
    RETURN; // 早退：fOut 保持零、bValid 保持假 / early return
END_IF
nUse := nCount; // 域内接管 / take the count
IF nUse > DL_WPC_NMAX THEN // 超容量 / above the capacity
    nUse := DL_WPC_NMAX; // 钳到容量 / clamp to the capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
fPUse := fP; // 分位接管 / take the quantile
IF fPUse < 0.0 THEN // 低于下界 / below the floor
    fPUse := 0.0; // 钳到零 / clamp to zero
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF fPUse > 1.0 THEN // 高于上界 / above the ceiling
    fPUse := 1.0; // 钳到一 / clamp to one
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF (fPUse <> fPUse) OR ((fPUse - fPUse) <> (fPUse - fPUse)) THEN // 分位非有限（NaN 钳位序闸兜不住，逐个点名，R272）/ a non finite quantile
    eErr := 16#0001_063A; // 故障级：入参非法归权向量闸同码口径（判据集合内非法）/ fault grade, an illegal input
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    RETURN; // 早退 / early return
END_IF
IF bClamp THEN // 钳位发生置信息级 / the clamp raises the informational code
    eErr := 16#0001_0639; // 信息级：计数或分位越域已钳位 / informational, clamped
END_IF

// 段 3｜权向量闸：逐元素负权 / 非有限点名 + Σw 判（边界二，R272）/ segment 3, the weight gate
FOR k := 0 TO nUse - 1 DO // 有界遍历 / the bounded traversal
    IF (afWeights[k] < 0.0)
    OR (afWeights[k] <> afWeights[k])
    OR ((afWeights[k] - afWeights[k]) <> (afWeights[k] - afWeights[k])) THEN // 负权或非有限 / a negative or non finite weight
        eErr := 16#0001_063A; // 故障级：权向量非法 / fault grade, an illegal weight vector
        bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
        RETURN; // 早退 / early return
    END_IF
    fWsum := fWsum + afWeights[k]; // 权和累加 / accumulate the weight sum
END_FOR
IF fWsum <= 0.0 THEN // 权和为零（权和已证非负，本判覆盖恰零）/ a zero weight sum
    eErr := 16#0001_063A; // 故障级：权向量和为零 / fault grade, the zero weight sum
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    RETURN; // 早退 / early return
END_IF

// 段 4｜委托稳定排序（R140 委托优先；返回值与 bValid 分承，禁双写，R62-D5）/ segment 4, the delegated stable sort with two separate holders
_bSortRet := FC_DL_SortIndexLReal(afValues := afValues, nCount := nUse, aIdx => aOrd, bValid => _bSortValid, eErr => uSortEr, bError => bSortEr); // 委托索引排序：返回值落 _bSortRet、可用位映射落 _bSortValid / delegate the index sort with two distinct holders
bSortOk := _bSortRet AND _bSortValid; // 返回值与可用位各自承接后合取（IEC 未规定返回值与输出映射的求值次序）/ conjoin the return value and the valid flag, since IEC leaves their evaluation order unspecified
IF (NOT bSortOk) OR bSortEr THEN // 委托失败（含其非有限故障码回传）/ the delegate failed
    eErr := uSortEr; // 委托码回传（码随属主，R66）/ replay the delegate code
    bError := bSortEr; // 委托故障位回传 / replay the delegate fault bit
    RETURN; // 早退 / early return
END_IF

// 段 5｜加权累积定位与邻位插值（边界一三）/ segment 5, the weighted location and the neighbour interpolation
fTarget := fPUse * fWsum; // 目标累积权（p=0 取首元、p=1 取末元，两端点自证）/ the target cumulative weight
fCum := 0.0; // 累积权清零 / reset the cumulative
FOR k := 0 TO nUse - 1 DO // 按排序序累积（命中后余轮守卫跳过，禁改循环变量）/ accumulate in the sorted order, the rounds after the hit are guarded out
    IF NOT bFound THEN // 未命中才继续累积 / accumulate only before the hit
        fCumPrv := fCum; // 前位累积权快照 / snapshot the previous cumulative
        fCum := fCum + afWeights[aOrd[k]]; // 累进当前权 / add the current weight
        IF fCum >= fTarget THEN // 越过目标即命中（p=0 时首位置即命中）/ the target crossed
            nHit := k; // 记录命中位置 / register the hit position
            bFound := TRUE; // 置命中标记 / raise the hit flag
        END_IF
    END_IF
END_FOR
IF NOT bFound THEN // 全遍历未越过（浮点和误差兜底）：取末元 / the fallback to the last element
    nHit := nUse - 1; // 命中末位置 / the last position
END_IF
fVR := afValues[aOrd[nHit]]; // 右元值 = 命中位值 / the right value is the hit value
IF nHit = 0 THEN // 命中首位：无左邻（p=0 端点）/ the first position, no left neighbour
    fOut := fVR; // 直接取右元 / take the right value directly
ELSE // 邻位插值 / the neighbour interpolation
    fVL := afValues[aOrd[nHit - 1]]; // 左元值 / the left value
    IF (fCum - fCumPrv) > 0.0 THEN // 插值除子已证 > 0（边界三）/ the proven positive divisor
        fFrac := (fTarget - fCumPrv) / (fCum - fCumPrv); // 插值分数 / the interpolation fraction
        IF fFrac < 0.0 THEN // 分数越下界（浮点和误差兜底钳位）/ the fraction below the floor
            fFrac := 0.0; // 钳到零（取左元）/ clamp to zero
        END_IF
        IF fFrac > 1.0 THEN // 分数越上界 / the fraction above the ceiling
            fFrac := 1.0; // 钳到一（取右元）/ clamp to one
        END_IF
        fOut := fVL + (fVR - fVL) * fFrac; // 线性插值出结果 / the linear interpolation
    ELSE // 除子非正（零权相邻）：直接取右元（禁除零，边界三）/ a non positive divisor, take the right value
        fOut := fVR; // 直接取右元 / take the right value directly
    END_IF
END_IF

// 段 6｜结果复检兜底（非有限同拍三件套，边界四）/ segment 6, the result recheck
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut)) THEN // 结果非有限 / the result is not finite
    fOut := 0.0; // 兜底安全值 / the bottom line safe value
    eErr := 16#0001_063B; // 故障级：结果非有限 / fault grade, the non finite result
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
    bValid := FALSE; // 结果不可用 / the result void
    RETURN; // 早退 / early return
END_IF
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_WeightedPercentile := TRUE; // 返回成功 / return success
END_FUNCTION
