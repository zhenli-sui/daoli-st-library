(*
  ==================================================================
  组件名 Component  : FC_DL_SearchMinMaxDint
  分类   Category   : DL_MathData
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : DINT 域数组单遍扫描求最小值/最大值与双索引同出。前 nCount
                      个元素有效，一次循环同时出 nMin/nMax 与 uMinIdx/uMaxIdx
                      （首命中口径），无效哨兵按开关跳过并计数。
  来源   Source     : t2-1-lgf-math（LGF Math 极值检索族 DINT 变体）
  溯源   Origin     : 极值检索属公开数学语义，clean-room 自研实现，未复制 LGF
                      或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（仅 FOR / 比较 / DINT_TO_UDINT），
                      CODESYS / TwinCAT / InoProShop / Machine Expert 通用
  分工声明 Split     : 与 FC_DL_SearchMinMax（LREAL 属主）互引——后者管 LREAL
                      域并以 x <> x 剔除 NaN；本件为 DINT 域重载，只做整数极值，
                      不做浮点有限性判据。与 FC_DL_SearchMinMaxUdint 同批成对，
                      共用同一规格向量表、码位段同带连号。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 扫描个数钳位 1..4096，钳位置信息级码；
                      二 无效样本域：DINT 域无 NaN（LREAL 属主用 x <> x 判据），
                         本件无效量定义为哨兵 DL_SMM_INVALID（等于 DINT 最小值
                         位型 16#8000_0000），仅当 bIgnoreInvalid 为真时跳过；
                      三 全量无效时不返回 0 号位「伪极值」——bValid = FALSE 且
                         两个索引回 0，由调用方按 bValid 判别（沿 LREAL 属主纪律）；
                      四 索引写出前已证在 [0, nUse-1] 内，回钳后不再复判越界（R241）；
                      五 无状态纯函数：每次调用局部量一律段 1 显式预置（R254）。
  接口偏离声明       : 派单示意 fMin/fMax（浮点命名），DINT 输出按 R265 命名-类型
                      一致性落为 nMin/nMax，语义与引脚数一字不减。
  错误码   Codes    :
    16#0001_0601【信息级】计数越界已钳位（<1 早退，>4096 钳位续扫）
    16#0001_0602【信息级】无效哨兵样本已跳过，个数见 nSkipCnt
    16#0001_0603【故障级】全量无效，无有效极值，bValid = FALSE
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 数据 5 / -3 / 9 / -3，个数 4 → nMin=-3 于索引 1，nMax=9 于索引 2
    V2 数据 7 / 7 / 7 → nMin=nMax=7，双索引均 0（首命中）
    V3 哨兵 16#8000_0000 夹在有效值间，bIgnoreInvalid 真 → 跳过 1 个，码含 0602
    V4 个数 0 → bValid=FALSE、码 0601、双索引 0
    V5 全为哨兵且 bIgnoreInvalid 真 → bValid=FALSE、码 0603
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 1 · 序号 1）
  ==================================================================
*)
FUNCTION FC_DL_SearchMinMaxDint : BOOL
VAR_IN_OUT
    aValues : ARRAY[0..4095] OF DINT; // 待扫描数组 [工程计数]，前 nCount 个有效 / the scanned array, the first nCount entries valid
END_VAR
VAR_INPUT
    nCount         : DINT; // 有效样本数 [个]，钳位 1..4096 / the valid sample count, clamped to one through four thousand ninety six
    bIgnoreInvalid : BOOL; // 是否跳过无效哨兵值 [-] / whether the invalid sentinel entries are skipped
END_VAR
VAR_OUTPUT
    nMin     : DINT;  // 最小值 [工程计数]，无有效样本时为 0 / the minimum value, zero when no valid sample
    nMax     : DINT;  // 最大值 [工程计数]，无有效样本时为 0 / the maximum value, zero when no valid sample
    uMinIdx  : UDINT; // 最小值所在下标 [下标]，无有效样本时为 0 / the minimum index, zero when no valid sample
    uMaxIdx  : UDINT; // 最大值所在下标 [下标]，无有效样本时为 0 / the maximum index, zero when no valid sample
    nSkipCnt : UDINT; // 被跳过的无效哨兵个数 [个] / the skipped invalid sentinel count
    bValid   : BOOL;  // 结果是否有效（全量无效时为假）[-] / the result validity flag
    eErr     : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL;  // 错误标志，eErr 非 0 时为真 / the error flag, true when eErr is nonzero
END_VAR
VAR
    nI      : DINT;  // 扫描索引 [下标] / the scan index
    nUse    : DINT;  // 钳位后的扫描个数 [个] / the clamped scan count
    nSeen   : DINT;  // 已见有效样本数 [个] / the seen valid sample count
    nV      : DINT;  // 当前样本工作副本 [工程计数] / the current sample working copy
    bHave   : BOOL;  // 已取得首个有效样本 [-] / the first valid sample taken flag
    bClamp  : BOOL;  // 钳位发生标记 [-] / the clamp happened flag
END_VAR
VAR CONSTANT
    DL_SMM_DMAX      : DINT := 4096;               // 扫描个数上界 [个]，与数组容量一致 / the scan count bound aligned with the array capacity
    DL_SMM_INVALID   : DINT := -16#7FFF_FFFF - 1;  // 无效哨兵，等于 DINT 最小位型 16#8000_0000（禁用超域字面量写法）/ the invalid sentinel equal to the DINT minimum bit pattern
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 局部量显式预置（R254）/ segment 1, the preset of the return, the codes and the local guards
FC_DL_SearchMinMaxDint := FALSE; // 返回值预置假 / preset the return false
nMin := 0; // 最小值预置零 / preset the minimum zero
nMax := 0; // 最大值预置零 / preset the maximum zero
uMinIdx := 0; // 最小索引预置零 / preset the minimum index zero
uMaxIdx := 0; // 最大索引预置零 / preset the maximum index zero
nSkipCnt := 0; // 跳过计数预置零 / preset the skipped count zero
bValid := FALSE; // 有效标志预置假（无有效样本前不宣称有效）/ preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nUse := 0; // 扫描个数预置零 / preset the scan count zero
nSeen := 0; // 有效样本数预置零 / preset the seen count zero
nV := 0; // 样本工作副本预置零 / preset the sample copy zero
bHave := FALSE; // 首样本标志预置假 / preset the first sample flag false
bClamp := FALSE; // 钳位标记预置假 / preset the clamp flag false

// 段 2｜扫描个数域闸（下界早退 + 上界钳位，边界一）/ segment 2, the scan count domain gate
IF nCount < 1 THEN // 低于下界，无样本可扫 / below the floor, nothing to scan
    eErr := 16#0001_0601; // 信息级：计数越界已钳位 / informational, the count clamped
    bError := TRUE; // 置错误标志（信息级随事件置位惯例）/ raise the error flag
    RETURN; // 早退：bValid 保持 FALSE，双索引保持 0 / early return with the validity false
END_IF
nUse := nCount; // 域内接管 / take the count inside the domain
IF nUse > DL_SMM_DMAX THEN // 高于上界 / above the bound
    nUse := DL_SMM_DMAX; // 钳到数组容量 / clamp to the array capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF bClamp THEN // 钳位发生时置信息级 / raise the informational code on a clamp
    eErr := 16#0001_0601; // 信息级：计数越界已钳位 / informational, the count clamped
    bError := TRUE; // 置错误标志 / raise the error flag
END_IF

// 段 3｜单遍扫描：首命中取极小与极大，索引与值同源写出（边界四）/ segment 3, the single pass scan with the first hit rule
FOR nI := 0 TO nUse - 1 DO // 有界循环（nUse 已钳 ≤4096）/ the bounded loop
    nV := aValues[nI]; // 取样本（索引已证在数组界内）/ take the sample, the index proven inside the bounds
    IF bIgnoreInvalid AND (nV = DL_SMM_INVALID) THEN // 无效哨兵且开关为真 / an invalid sentinel with the switch true
        nSkipCnt := nSkipCnt + 1; // 跳过计数推进 / advance the skipped count
    ELSE // 有效样本参与极值 / a valid sample participates
        nSeen := nSeen + 1; // 有效样本数推进 / advance the seen count
        IF NOT bHave THEN // 首个有效样本：双向装填 / the first valid sample seeds both sides
            nMin := nV; // 最小值装填 / seed the minimum
            nMax := nV; // 最大值装填 / seed the maximum
            uMinIdx := DINT_TO_UDINT(nI); // 最小索引装填 / seed the minimum index
            uMaxIdx := DINT_TO_UDINT(nI); // 最大索引装填 / seed the maximum index
            bHave := TRUE; // 置首样本标志 / raise the first sample flag
        ELSE // 后续样本比较（首命中用严格比较，不覆盖等值）/ the later samples, strict compare keeps the first hit
            IF nV < nMin THEN // 新极小 / a new minimum
                nMin := nV; // 更新最小值 / update the minimum
                uMinIdx := DINT_TO_UDINT(nI); // 更新最小索引（与值同源）/ update the minimum index from the same source
            ELSIF nV > nMax THEN // 新极大（nV ≥ nMin 前提下判极大即可，单调序自证）/ a new maximum, proven since nV is not below the minimum
                nMax := nV; // 更新最大值 / update the maximum
                uMaxIdx := DINT_TO_UDINT(nI); // 更新最大索引（与值同源）/ update the maximum index from the same source
            END_IF
        END_IF
    END_IF
END_FOR

// 段 4｜结果复检兜底：全量无效判故障，信息级与故障级不共码（R258 三件套）/ segment 4, the result recheck
IF (nSeen > 0) AND (nSkipCnt > 0) AND (eErr = 16#0000_0000) THEN // 部分跳过且无先发事件 / a partial skip with no earlier event
    eErr := 16#0001_0602; // 信息级：无效哨兵样本已跳过 / informational, the invalid sentinels skipped
    bError := TRUE; // 置错误标志 / raise the error flag
END_IF
IF nSeen < 1 THEN // 无有效样本 / no valid sample
    eErr := 16#0001_0603; // 故障级：全量无效，无有效极值 / fault grade, no valid extremum
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    nMin := 0; // 双极值回安全值 / both extrema back to the safe zero
    nMax := 0; // 双极值回安全值 / both extrema back to the safe zero
    uMinIdx := 0; // 索引回 0（不冒充 0 号位极值，边界三）/ the index back to zero, not posing as the entry zero
    uMaxIdx := 0; // 索引回 0（不冒充 0 号位极值，边界三）/ the index back to zero, not posing as the entry zero
ELSE // 有有效样本 / with valid samples
    bValid := TRUE; // 结果有效 / the result is valid
    FC_DL_SearchMinMaxDint := TRUE; // 返回成功 / return success
END_IF
END_FUNCTION
