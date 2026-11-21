(*
  ==================================================================
  组件名 Component  : FC_DL_SearchMinMaxUdint
  分类   Category   : DL_MathData
  复杂度 Complexity  : 低
  版本   Version    : 1.0.0
  功能   Purpose    : UDINT 域数组单遍扫描求最小值/最大值与双索引同出。前 nCount
                      个元素有效，一次循环同时出 uMin/uMax 与 uMinIdx/uMaxIdx
                      （首命中口径），无效哨兵按开关跳过并计数。
  来源   Source     : t2-1-lgf-math（LGF Math 极值检索族 UDINT 变体）
  溯源   Origin     : 极值检索属公开数学语义，clean-room 自研实现，未复制 LGF
                      或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（仅 FOR / 比较 / DINT_TO_UDINT），
                      CODESYS / TwinCAT / InoProShop / Machine Expert 通用
  分工声明 Split     : 与 FC_DL_SearchMinMax（LREAL 属主）及
                      FC_DL_SearchMinMaxDint（DINT 域同批连号件）三角互引——
                      本件为无符号域同构件，判式一律全序（<= / >=），不使用
                      任何减法比较（无符号域差值会回绕成大正数）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 扫描个数钳位 1..4096，钳位置信息级码；
                      二 无效样本域：UDINT 域无 NaN，本件无效量定义为哨兵
                         DL_SMU_INVALID（= UDINT 最大位型 16#FFFF_FFFF），仅当
                         bIgnoreInvalid 为真时跳过（与 DINT 件哨兵取最小位型的
                         对称口径，头注释留痕）；
                      三 全量无效时 bValid = FALSE 且双索引回 0，不冒充 0 号位极值；
                      四 无符号比较只允许全序判式 <= / >=，禁用 a - b 差值判序；
                      五 无状态纯函数：每次调用局部量一律段 1 显式预置（R254）。
  接口偏离声明       : 派单示意 fMin/fMax（浮点命名），UDINT 输出按 R265 命名-类型
                      一致性落为 uMin/uMax，语义与引脚数一字不减。
  错误码   Codes    :
    16#0001_0604【信息级】计数越界已钳位（<1 早退，>4096 钳位续扫）
    16#0001_0605【信息级】无效哨兵样本已跳过，个数见 nSkipCnt
    16#0001_0606【故障级】全量无效，无有效极值，bValid = FALSE
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 数据 5 / 3 / 9 / 3，个数 4 → uMin=3 于索引 1，uMax=9 于索引 2
    V2 数据 16#FFFF_FFFE / 0 → uMin=0 于索引 1，uMax=16#FFFF_FFFE 于索引 0
    V3 哨兵 16#FFFF_FFFF 夹在有效值间，bIgnoreInvalid 真 → 跳过 1 个，码含 0605
    V4 个数 0 → bValid=FALSE、码 0604、双索引 0
    V5 全为哨兵且 bIgnoreInvalid 真 → bValid=FALSE、码 0606
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 1 · 序号 2）
  ==================================================================
*)
FUNCTION FC_DL_SearchMinMaxUdint : BOOL
VAR_IN_OUT
    auValues : ARRAY[0..4095] OF UDINT; // 待扫描数组 [计数值]，前 nCount 个有效 / the scanned array, the first nCount entries valid
END_VAR
VAR_INPUT
    nCount         : DINT; // 有效样本数 [个]，钳位 1..4096 / the valid sample count, clamped to one through four thousand ninety six
    bIgnoreInvalid : BOOL; // 是否跳过无效哨兵值 [-] / whether the invalid sentinel entries are skipped
END_VAR
VAR_OUTPUT
    uMin     : UDINT; // 最小值 [计数值]，无有效样本时为 0 / the minimum value, zero when no valid sample
    uMax     : UDINT; // 最大值 [计数值]，无有效样本时为 0 / the maximum value, zero when no valid sample
    uMinIdx  : UDINT; // 最小值所在下标 [下标]，无有效样本时为 0 / the minimum index, zero when no valid sample
    uMaxIdx  : UDINT; // 最大值所在下标 [下标]，无有效样本时为 0 / the maximum index, zero when no valid sample
    nSkipCnt : UDINT; // 被跳过的无效哨兵个数 [个] / the skipped invalid sentinel count
    bValid   : BOOL;  // 结果是否有效（全量无效时为假）[-] / the result validity flag
    eErr     : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL;  // 错误标志，eErr 非 0 时为真 / the error flag, true when eErr is nonzero
END_VAR
VAR
    nI     : DINT;  // 扫描索引 [下标] / the scan index
    nUse   : DINT;  // 钳位后的扫描个数 [个] / the clamped scan count
    nSeen  : DINT;  // 已见有效样本数 [个] / the seen valid sample count
    uV     : UDINT; // 当前样本工作副本 [计数值] / the current sample working copy
    bHave  : BOOL;  // 已取得首个有效样本 [-] / the first valid sample taken flag
    bClamp : BOOL;  // 钳位发生标记 [-] / the clamp happened flag
END_VAR
VAR CONSTANT
    DL_SMU_DMAX    : DINT := 4096;          // 扫描个数上界 [个]，与数组容量一致 / the scan count bound aligned with the array capacity
    DL_SMU_INVALID : UDINT := 16#FFFF_FFFF; // 无效哨兵，等于 UDINT 最大位型（与 DINT 件取最小位型对称）/ the invalid sentinel equal to the UDINT maximum bit pattern
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 局部量显式预置（R254）/ segment 1, the preset of the return, the codes and the local guards
FC_DL_SearchMinMaxUdint := FALSE; // 返回值预置假 / preset the return false
uMin := 0; // 最小值预置零 / preset the minimum zero
uMax := 0; // 最大值预置零 / preset the maximum zero
uMinIdx := 0; // 最小索引预置零 / preset the minimum index zero
uMaxIdx := 0; // 最大索引预置零 / preset the maximum index zero
nSkipCnt := 0; // 跳过计数预置零 / preset the skipped count zero
bValid := FALSE; // 有效标志预置假（无有效样本前不宣称有效）/ preset the validity false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nUse := 0; // 扫描个数预置零 / preset the scan count zero
nSeen := 0; // 有效样本数预置零 / preset the seen count zero
uV := 0; // 样本工作副本预置零 / preset the sample copy zero
bHave := FALSE; // 首样本标志预置假 / preset the first sample flag false
bClamp := FALSE; // 钳位标记预置假 / preset the clamp flag false

// 段 2｜扫描个数域闸（下界早退 + 上界钳位，边界一）/ segment 2, the scan count domain gate
IF nCount < 1 THEN // 低于下界，无样本可扫 / below the floor, nothing to scan
    eErr := 16#0001_0604; // 信息级：计数越界已钳位 / informational, the count clamped
    bError := TRUE; // 置错误标志（信息级随事件置位惯例）/ raise the error flag
    RETURN; // 早退：bValid 保持 FALSE，双索引保持 0 / early return with the validity false
END_IF
nUse := nCount; // 域内接管 / take the count inside the domain
IF nUse > DL_SMU_DMAX THEN // 高于上界 / above the bound
    nUse := DL_SMU_DMAX; // 钳到数组容量 / clamp to the array capacity
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF bClamp THEN // 钳位发生时置信息级 / raise the informational code on a clamp
    eErr := 16#0001_0604; // 信息级：计数越界已钳位 / informational, the count clamped
    bError := TRUE; // 置错误标志 / raise the error flag
END_IF

// 段 3｜单遍扫描：首命中取极小与极大，索引与值同源写出（边界四）/ segment 3, the single pass scan with the first hit rule
FOR nI := 0 TO nUse - 1 DO // 有界循环（nUse 已钳 ≤4096）/ the bounded loop
    uV := auValues[nI]; // 取样本（索引已证在数组界内）/ take the sample, the index proven inside the bounds
    IF bIgnoreInvalid AND (uV >= DL_SMU_INVALID) THEN // 无效哨兵且开关为真（全序判式，不用等号）/ an invalid sentinel with the switch true, a total order test
        nSkipCnt := nSkipCnt + 1; // 跳过计数推进 / advance the skipped count
    ELSE // 有效样本参与极值 / a valid sample participates
        nSeen := nSeen + 1; // 有效样本数推进 / advance the seen count
        IF NOT bHave THEN // 首个有效样本：双向装填 / the first valid sample seeds both sides
            uMin := uV; // 最小值装填 / seed the minimum
            uMax := uV; // 最大值装填 / seed the maximum
            uMinIdx := DINT_TO_UDINT(nI); // 最小索引装填 / seed the minimum index
            uMaxIdx := DINT_TO_UDINT(nI); // 最大索引装填 / seed the maximum index
            bHave := TRUE; // 置首样本标志 / raise the first sample flag
        ELSE // 后续样本比较（首命中用严格判式，不覆盖等值）/ the later samples, strict tests keep the first hit
            IF uV < uMin THEN // 新极小 / a new minimum
                uMin := uV; // 更新最小值 / update the minimum
                uMinIdx := DINT_TO_UDINT(nI); // 更新最小索引（与值同源）/ update the minimum index from the same source
            ELSIF uV > uMax THEN // 新极大（uV ≥ uMin 前提下判极大即可，全序自证）/ a new maximum, proven by the total order
                uMax := uV; // 更新最大值 / update the maximum
                uMaxIdx := DINT_TO_UDINT(nI); // 更新最大索引（与值同源）/ update the maximum index from the same source
            END_IF
        END_IF
    END_IF
END_FOR

// 段 4｜结果复检兜底：全量无效判故障，信息级与故障级不共码（R258 三件套）/ segment 4, the result recheck
IF (nSeen > 0) AND (nSkipCnt > 0) AND (eErr = 16#0000_0000) THEN // 部分跳过且无先发事件 / a partial skip with no earlier event
    eErr := 16#0001_0605; // 信息级：无效哨兵样本已跳过 / informational, the invalid sentinels skipped
    bError := TRUE; // 置错误标志 / raise the error flag
END_IF
IF nSeen < 1 THEN // 无有效样本 / no valid sample
    eErr := 16#0001_0606; // 故障级：全量无效，无有效极值 / fault grade, no valid extremum
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    bValid := FALSE; // 结果不可用 / the result void
    uMin := 0; // 双极值回安全值 / both extrema back to the safe zero
    uMax := 0; // 双极值回安全值 / both extrema back to the safe zero
    uMinIdx := 0; // 索引回 0（不冒充 0 号位极值，边界三）/ the index back to zero, not posing as the entry zero
    uMaxIdx := 0; // 索引回 0（不冒充 0 号位极值，边界三）/ the index back to zero, not posing as the entry zero
ELSE // 有有效样本 / with valid samples
    bValid := TRUE; // 结果有效 / the result is valid
    FC_DL_SearchMinMaxUdint := TRUE; // 返回成功 / return success
END_IF
END_FUNCTION
