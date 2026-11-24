(*
  ==================================================================
  组件名 Component  : FC_DL_SortIndexLReal
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 稳定排序仅输出索引排列，不改调用方数组（只读纪律）。
  来源   Source     : self-std（公开排序语义自研，索引间接排序实现）
  平台   Platform   : 纯 IEC 61131-3（FOR / WHILE / 比较 / 数组），三平台通用
  分工声明 Split     : 与 FC_DL_PercentileLReal（百分位属主）分工——后者只读
                      求分位；本件出索引排列供上层复用，两件共用只读纪律
                      （R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 稳定性判据写死下标序：比较用严格小于，相等元素保持
                         原下标先后（插入序即下标序），不交换等值对；
                      二 nCount = 0 / 1 退化直返恒等索引（aIdx[i] = i），不置码；
                      三 非有限元素判故障拒绝（NaN 与任何比较均假会静默破坏
                         排序，必须逐个点名，R272）；
                      四 索引写出前已证在 [0, nUse-1] 内，回钳量不再复判越界
                         （R241）；扫描禁裸 WHILE 死循环（计数器上界护栏）；
                      五 只读入参数组，不改调用方数据；
                      六 无状态纯函数：局部量段 1 显式预置（R254）。
  错误码   Codes    :
    16#0001_0637【信息级】计数越域已钳位（<0 早退，>256 钳位续扫）
    16#0001_0638【故障级】元素含非有限值，拒绝排序
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 值 3/1/2 → 索引 1/2/0；V2 值 2/2/1 → 索引 2/0/1（稳定性）
    V3 nCount=1 → 恒等索引 [0]；V4 含 NaN → 码 0638、bValid=FALSE
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 2 · 序号 5）
  ==================================================================
*)
FUNCTION FC_DL_SortIndexLReal : BOOL
VAR_IN_OUT
    afValues : ARRAY[0..255] OF LREAL; // 待排序数值 [工程单位]，只读 / the values to sort, read only
END_VAR
VAR_INPUT
    nCount : DINT; // 参与排序个数 [个]，合法域 0..256 / the count, legal from zero to two hundred fifty six
END_VAR
VAR_OUTPUT
    aIdx   : ARRAY[0..255] OF DINT; // 排序后索引排列（aIdx[0] 为最小值原下标）/ the sorted index permutation
    bValid : BOOL;                  // 结果可用标志 [-] / the result usable flag
    eErr   : UDINT;                 // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;                  // 错误标志，故障级码置位（R45 配对）/ the error flag
END_VAR
VAR
    k      : DINT;  // 外层插入索引 [下标] / the outer insertion index
    m      : DINT;  // 内层前移索引 [下标] / the inner shifting index
    nUse   : DINT;  // 钳位后的个数 [个] / the clamped count
    nKey   : DINT;  // 待插元素原下标暂存 [下标] / the key original index in staging
    fKey   : LREAL; // 待插元素值暂存 [工程单位] / the key value in staging
    nGuard : DINT;  // 死循环护栏计数 [次] / the dead loop guard counter
END_VAR
VAR CONSTANT
    DL_SIL_NMAX : DINT := 256; // 排序容量上界 [个]，与数组容量一致 / the sort capacity aligned with the array
    DL_SIL_GMAX : DINT := 70000; // 护栏计数上界 [次]，大于最坏比较次数 / the guard bound above the worst case
END_VAR

// 段 1｜返回值与错误状态预置安全值 + 局部量显式预置（R45 / R254）/ segment 1, the preset
FC_DL_SortIndexLReal := FALSE; // 返回值预置假 / preset the return false
bValid := FALSE; // 有效标志预置假 / preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nUse := 0; // 个数预置零 / preset the count zero
nKey := 0; // 键下标预置零 / preset the key index zero
fKey := 0.0; // 键值预置零 / preset the key value zero
nGuard := 0; // 护栏预置零 / preset the guard zero
FOR k := 0 TO 255 DO // 索引数组全量预置恒等 / preset the index array to the identity
    aIdx[k] := k; // 恒等索引 / the identity index
END_FOR

// 段 2｜计数域闸（<0 早退，>256 钳位，边界二四）/ segment 2, the count gate
IF nCount < 0 THEN // 负数非法 / a negative count
    eErr := 16#0001_0637; // 信息级：计数越域已钳位 / informational, the count clamped
    bValid := TRUE; // 空排列合法（aIdx 已全量恒等）/ the empty permutation is legal
    FC_DL_SortIndexLReal := TRUE; // 返回成功 / return success
    RETURN; // 早退 / early return
END_IF
nUse := nCount; // 域内接管 / take the count
IF nUse > DL_SIL_NMAX THEN // 超容量 / above the capacity
    nUse := DL_SIL_NMAX; // 钳到容量 / clamp to the capacity
    eErr := 16#0001_0637; // 信息级：计数越域已钳位 / informational, the count clamped
END_IF

// 段 3｜非有限元素逐个点名（R272，边界三）/ segment 3, the element wise finiteness gate
FOR k := 0 TO nUse - 1 DO // 有界遍历 / the bounded traversal
    IF (afValues[k] <> afValues[k]) OR ((afValues[k] - afValues[k]) <> (afValues[k] - afValues[k])) THEN // 元素非有限 / the element is not finite
        eErr := 16#0001_0638; // 故障级：元素含非有限值 / fault grade, a non finite element
        bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag
        bValid := FALSE; // 结果不可用 / the result void
        RETURN; // 早退（aIdx 保持恒等，不外泄坏排列）/ early return with the identity kept
    END_IF
END_FOR

// 段 4｜插入排序（索引间接，严格比较保稳定，边界一；护栏防死循环，边界四）/ segment 4, the stable insertion sort on the indices
FOR k := 1 TO nUse - 1 DO // 有界外层 / the bounded outer loop
    nKey := aIdx[k]; // 待插元素原下标 / the key original index
    fKey := afValues[nKey]; // 待插元素值 / the key value
    m := k - 1; // 内层从前一位置起 / the inner scan starts here
    nGuard := 0; // 护栏清零 / reset the guard
    WHILE (m >= 0) AND (afValues[aIdx[m]] > fKey) DO // 前驱更大才前移（严格大于，等值不交换，稳定性自证）/ shift while the predecessor is strictly greater
        aIdx[m + 1] := aIdx[m]; // 索引后移一位 / shift the index right
        m := m - 1; // 内层前移 / step the inner scan left
        nGuard := nGuard + 1; // 护栏计数推进 / advance the guard
        IF nGuard > DL_SIL_GMAX THEN // 护栏命中（结构性不可达兜底）/ the guard tripped, kept as a structural guard
            eErr := 16#0001_0638; // 故障级：排序失控复用非有限码前先判——此处不置码、强制收尾 / the forced stop without a new code
            m := -1; // 强制退出内层 / force the inner loop out
        END_IF
    END_WHILE
    aIdx[m + 1] := nKey; // 键落位（m+1 已证在 [0, k] 内，边界四）/ the key lands with a proven bound
END_FOR

// 段 5｜出口（nUse = 0/1 时 aIdx 已为恒等，边界二）/ segment 5, the outlet with the degenerate identity
bValid := TRUE; // 结果可用 / the result is usable
FC_DL_SortIndexLReal := TRUE; // 返回成功 / return success
END_FUNCTION
