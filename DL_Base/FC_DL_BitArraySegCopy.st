// =====================================================================
// FC_DL_BitArraySegCopy.st
// 位段数组多段一次搬（源到目标多段批量复制, 逐段域校验 + 整段原子性）
// Multi-segment batch bit-array copy with per-segment domain validation
// 所属子库: DL_Base    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0001_048E ~ 16#0001_0491 (本件独占 4 槽, FC 纯函数分型, 勿复用)
// 溯源: IEC 61131-3 标准语义的道莅防御性实现
//       来源组标签: bit-field, array-copy, batch-transfer, lgf-bitlogic
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 20)
// 语义声明: 一次调用搬 N 段; 逐段域校验（起位 + 长度不超过数组位容量）
//           先整体校验后统一搬移, 任一段非法则零段搬移并回放段号;
//           跨字窗口逐位读改写沿用 Extract/Insert 范式（移位量以取余 32
//           归一, 全程仅 32 位移位, 无 64 位移位）; 段表内重叠段不做去重,
//           后段覆盖前段; 与 FC_DL_BitArrayExtract/Insert 逐段对拍位守恒
// =====================================================================
FUNCTION FC_DL_BitArraySegCopy : BOOL   // 返回真 = 全部段搬移完成 / TRUE when all segments copied
VAR_IN_OUT
    aSrc   : ARRAY[*] OF DWORD;     // 源位数组（开数组, 实测边界）/ Source bit array
    aDst   : ARRAY[*] OF DWORD;     // 目标位数组（开数组, 实测边界）/ Destination bit array
END_VAR
VAR_INPUT
    aSrcBit   : ARRAY[*] OF UINT;   // 各段源起始位号 0 起 / Per-segment source start bit
    aDstBit   : ARRAY[*] OF UINT;   // 各段目标起始位号 0 起 / Per-segment destination start bit
    aLen      : ARRAY[*] OF USINT;  // 各段长度（位）1~255 / Per-segment length in bits
    uSegCount : USINT;              // 段数 / Segment count
END_VAR
VAR_OUTPUT
    uErrorId : UDINT;               // 错误码, 见码表 / Error code, see table
    uFailSeg : USINT;               // 非法段号回放 1~N, 0 = 无 / Failed segment replay, 0 = none
END_VAR
VAR
    uSrcCap  : DINT := 0;           // 源数组实测位容量 / Source capacity in bits
    uDstCap  : DINT := 0;           // 目标数组实测位容量 / Destination capacity in bits
    uTabCap1 : DINT := 0;           // 段表 1 实测容量 / Segment table 1 capacity
    uTabCap2 : DINT := 0;           // 段表 2 实测容量 / Segment table 2 capacity
    uTabCap3 : DINT := 0;           // 段表 3 实测容量 / Segment table 3 capacity
    uTabCap  : DINT := 0;           // 段表最小容量 / Minimum table capacity
    uSegUse  : DINT := 0;           // 实际处理段数（钳位后）/ Effective segment count
    iS       : DINT := 0;           // 段循环下标 / Segment loop index
    iJ       : DINT := 0;           // 位循环下标 / Bit loop index
    iSIdx    : DINT := 0;           // 段表元素下标 / Segment table element index
    uSrcPos  : DINT := 0;           // 当前源位号 / Current source bit position
    uDstPos  : DINT := 0;           // 当前目标位号 / Current destination bit position
    iW       : DINT := 0;           // 字下标 / Word index
    dwMask   : DWORD := DWORD#0;    // 位掩码 / Bit mask
    dwWord   : DWORD := DWORD#0;    // 目标字读改写临时量 / Destination word read-modify-write temp
    xBit     : BOOL := FALSE;       // 当前位值 / Current bit value
    uSegLen  : DINT := 0;           // 当前段长度 / Current segment length
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0001_048E 信息 批量搬移完成（含段表重叠时后段覆盖前段语义）
//   16#0001_048F 信息 空段表（段数为 0, 零搬移成功返回）
//   16#0001_0490 故障 段域非法（起位 + 长度超过数组位容量, 段号经 uFailSeg
//                回放, 零段搬移原子回退）; 纯函数无锁存面, 修正段表重新调用即解除
//   16#0001_0491 信息 段计数越界钳位（段数大于段表实测容量, 已按容量截断处理）
// ---------------------------------------------------------------------

// ---- 缺省收口 / Defaults ----
FC_DL_BitArraySegCopy := FALSE;     // 缺省失败 / Default fail
uErrorId := 16#0001_048E;           // 缺省完成码, 异常路径覆盖 / Default done code
uFailSeg := 0;                      // 段号清零 / Clear segment number

// ---- 容量实测（开数组边界实测, 不假设下标起点）/ Measured capacities ----
uSrcCap := 32 * ((UPPER_BOUND(aSrc, 1) - LOWER_BOUND(aSrc, 1)) + 1);    // 源位容量 / Source bits
uDstCap := 32 * ((UPPER_BOUND(aDst, 1) - LOWER_BOUND(aDst, 1)) + 1);    // 目标位容量 / Destination bits
uTabCap1 := (UPPER_BOUND(aSrcBit, 1) - LOWER_BOUND(aSrcBit, 1)) + 1;
uTabCap2 := (UPPER_BOUND(aDstBit, 1) - LOWER_BOUND(aDstBit, 1)) + 1;
uTabCap3 := (UPPER_BOUND(aLen, 1) - LOWER_BOUND(aLen, 1)) + 1;
// 取三段表最小容量 / Minimum of the three table capacities
uTabCap := uTabCap1;
IF uTabCap2 < uTabCap THEN
    uTabCap := uTabCap2;
END_IF
IF uTabCap3 < uTabCap THEN
    uTabCap := uTabCap3;
END_IF

// ---- 空段表: 零搬移成功返回 / Empty segment table ----
IF uSegCount = 0 THEN
    uErrorId := 16#0001_048F;       // 空段表码 / Empty table code
    FC_DL_BitArraySegCopy := TRUE;  // 零搬移成功 / Zero-copy success
    RETURN;
END_IF

// ---- 段计数钳位（信息级, 按段表容量截断）/ Segment count clamp ----
uSegUse := USINT_TO_DINT(uSegCount);
IF uSegUse > uTabCap THEN
    uSegUse := uTabCap;             // 截断处理 / Truncate
    uErrorId := 16#0001_0491;       // 钳位信息码 / Clamp info code
END_IF

// ---- 整体校验: 逐段域校验, 任一非法即零段搬移退出（整段原子性）
//      Whole validation first, any invalid segment aborts with zero moved ----
FOR iS := 1 TO uSegUse DO
    iSIdx := LOWER_BOUND(aSrcBit, 1) + (iS - 1);    // 段表下标映射 / Table index mapping
    uSrcPos := UINT_TO_DINT(aSrcBit[iSIdx]);
    uSegLen := USINT_TO_DINT(aLen[iSIdx]);
    IF (uSrcPos + uSegLen) > uSrcCap THEN
        uErrorId := 16#0001_0490;   // 段域非法码 / Illegal segment domain
        uFailSeg := DINT_TO_USINT(iS);  // 回放段号 / Replay segment number
        RETURN;                     // 零段搬移退出 / Abort with zero moved
    END_IF
    uDstPos := UINT_TO_DINT(aDstBit[iSIdx]);
    IF (uDstPos + uSegLen) > uDstCap THEN
        uErrorId := 16#0001_0490;   // 段域非法码 / Illegal segment domain
        uFailSeg := DINT_TO_USINT(iS);
        RETURN;                     // 零段搬移退出 / Abort
    END_IF
END_FOR

// ---- 统一搬移: 逐段逐位读改写（后段覆盖前段, 不去重）/ Unified copy ----
FOR iS := 1 TO uSegUse DO
    iSIdx := LOWER_BOUND(aSrcBit, 1) + (iS - 1);
    uSegLen := USINT_TO_DINT(aLen[iSIdx]);
    uSrcPos := UINT_TO_DINT(aSrcBit[iSIdx]);    // 源位号复位 / Reset source position
    uDstPos := UINT_TO_DINT(aDstBit[iSIdx]);    // 目标位号复位 / Reset destination position
    FOR iJ := 1 TO uSegLen DO
        // 读源位（跨字窗口, 移位量取余 32 归一, 小于 32 位宽合规）
        // Read source bit across word boundary, shift normalized mod 32
        iW := LOWER_BOUND(aSrc, 1) + (uSrcPos / 32);
        dwMask := SHL(DWORD#1, uSrcPos MOD 32);
        xBit := (aSrc[iW] AND dwMask) <> DWORD#0;
        // 写目标位（读改写保持其余位）/ Write destination bit with read-modify-write
        iW := LOWER_BOUND(aDst, 1) + (uDstPos / 32);
        dwWord := aDst[iW];
        dwMask := SHL(DWORD#1, uDstPos MOD 32);
        IF xBit THEN
            dwWord := dwWord OR dwMask;             // 置位 / Set bit
        ELSE
            dwWord := dwWord AND (NOT dwMask);      // 清位 / Clear bit
        END_IF
        aDst[iW] := dwWord;                         // 回写字 / Write back
        uSrcPos := uSrcPos + 1;                     // 源位推进 / Advance source
        uDstPos := uDstPos + 1;                     // 目标位推进 / Advance destination
    END_FOR
END_FOR

FC_DL_BitArraySegCopy := TRUE;      // 全部段完成 / All segments done

END_FUNCTION
