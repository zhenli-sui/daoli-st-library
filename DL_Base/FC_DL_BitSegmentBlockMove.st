(*
    FC_DL_BitSegmentBlockMove —— 跨字多段位段一次搬运
    ------------------------------------------------------------------
    分类      : DL_Base / BitString
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : T2-1 LGF · Bit Logic（只借「读 / 写 / 监视 三层粒度 + 批量段」的组内
                分类事实；库内已收口 Extract / Insert / ChangeWatch 三件，本件补
                「多段一次搬」缺口）；掩码、段表结构、判界顺序、码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 段表驱动，一次调用把源 128 位窗口里的至多 8 个位段搬到目标窗口的指定
                位置（位段可跨 32 位字边界）。库内 BitArrayInsert 每次只能搬一段，
                多段场景要调用方自己循环并托管中间量，本件即补此缺口；
                核心防御是「先快照后写」：先把所有段值读进快照数组，全部读完后统一
                写目标，杜绝「段 1 的写覆盖段 2 的源」这类顺序缺陷；
                第二道防御是「逐位搬运」，任何宽度都不需要 32 位整字移位，
                彻底规避移位量等于 32 的未定义行为；
                越界段绝不部分写入，只跳过并计数；目标段重叠按段序后者覆盖前者并提示。
    错误码    : 16#0001_023B 存在越界 / 重叠段，已跳过并计数——信息级，正常防御
                16#0001_023C 预留禁用（信息级，不得挪用）
                16#0001_030F 段数为 0 或宽度全为 0——故障级，本拍不搬运
                16#0001_0310 段表自相矛盾（段数超段表容量）——故障级，本拍不搬运
                16#0001_0311 循环守卫超限（防死锁计数触发）——故障级，本拍结果作废
    码位总账  : 16#0001_023B 用 / 16#0001_023C 预留 ｜ 16#0001_030F 用 / 16#0001_0310 用 / 16#0001_0311 用
    状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 纯组合函数，无定时器、无内部驻留状态，调用即出结果；
                目标窗口由调用方通过 VAR_IN_OUT 注入，本件绝不初始化目标数组。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION FC_DL_BitSegmentBlockMove : BOOL
VAR_INPUT
    auSrcBit  : ARRAY[0..7] OF UINT;           // 各段源起始位（相对 128 位窗口）[位]，范围 0~127 / segment source start bit in the 128-bit window [bit], range 0~127
    auDstBit  : ARRAY[0..7] OF UINT;           // 各段目标起始位 [位]，范围 0~127 / segment destination start bit [bit], range 0~127
    auWidth   : ARRAY[0..7] OF UINT;           // 各段宽度 [位]，范围 1~32 / segment width [bit], range 1~32
    uSegCount : UINT := 1;                     // 有效段数 [段]，范围 1~8 / valid segment count [seg], range 1~8
    auSrcWord : ARRAY[0..3] OF DWORD;          // 源 128 位窗口，索引 0 = 最低字 [位图] / source 128-bit window, index 0 = lowest word [bitmap]
END_VAR
VAR_IN_OUT
    auDstWord : ARRAY[0..3] OF DWORD;          // 目标 128 位窗口，由调用方注入，本件不初始化 [位图] / destination window injected by the caller, never initialised here [bitmap]
END_VAR
VAR_OUTPUT
    uMovedSeg   : UINT;                        // 实际搬运段数 [段] / segments actually moved [seg]
    uSkippedSeg : UINT;                        // 因越界 / 重叠被跳过的段数 [段] / segments skipped due to range or overlap [seg]
    eErr        : UDINT;                       // 错误码，0=正常 / error id, 0=ok
    bError      : BOOL;                        // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    uSeg      : UINT;                          // 段游标 [段] / segment cursor [seg]
    uBit      : UINT;                          // 段内位游标 [位] / bit cursor inside a segment [bit]
    uWr       : UINT;                          // 已写段遍历游标 [段] / written segment traversal cursor [seg]
    uGuard    : UINT;                          // 循环守卫计数 [次] / loop guard counter [times]
    uSrcAbs   : UINT;                          // 源窗口绝对位号 [位] / absolute bit number in the source window [bit]
    uDstAbs   : UINT;                          // 目标窗口绝对位号 [位] / absolute bit number in the destination window [bit]
    uWordIdx  : UINT;                          // 字索引 0~3 [字] / word index 0~3 [word]
    uBitPos   : UINT;                          // 字内位号 0~31 [位] / bit position inside a word 0~31 [bit]
    uBitMask  : DWORD;                         // 单比特掩码 [位图] / single bit mask [bitmap]
    abUse     : ARRAY[0..7] OF BOOL;           // 段可用标志（宽度合法且判界通过）/ usable segment flag, width legal and range checked
    auSnap    : ARRAY[0..7] OF DWORD;          // 段值快照，先快照后写 [位图] / segment value snapshot, read all before writing any [bitmap]
    auWrStart : ARRAY[0..7] OF UINT;           // 已写段起始位，重叠检测用 [位] / written segment start bit for overlap detection [bit]
    auWrEnd   : ARRAY[0..7] OF UINT;           // 已写段结束位，重叠检测用 [位] / written segment end bit for overlap detection [bit]
    uWrCnt    : UINT;                          // 已写段计数 [段] / written segment count [seg]
    bOverlap  : BOOL;                          // 本段与已写段重叠标志 / overlap flag against the written segments
    uValidN   : UINT;                          // 宽度合法的段数 [段] / segments with a legal width [seg]
END_VAR
VAR CONSTANT
    DL_SEG_MAX      : UINT := 8;               // 段表容量上限 [段] / segment table capacity [seg]
    DL_SEG_WIN_BITS : UINT := 128;             // 窗口位宽 [位] / window width [bit]
    DL_SEG_WORD_BITS: UINT := 32;              // 单字位宽 [位] / word width [bit]
    DL_SEG_MAX_LOOP : UINT := 8;               // 循环守卫硬上限 [次] / hard loop guard limit [times]
    DL_SEG_WIDTH_MAX: UINT := 32;              // 单段最大宽度 [位] / maximum single segment width [bit]
    DL_SEG_BIT_ONE  : DWORD := 16#0000_0001;   // 最低位掩码，移位量恒小于 32 [位图] / least significant bit mask, shift count always below 32 [bitmap]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_BitSegmentBlockMove := FALSE;            // 故障缺省返回 FALSE / fault default returns FALSE
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
uMovedSeg := 0;                                // 搬运段数清零 / clear the moved count
uSkippedSeg := 0;                              // 跳过段数清零 / clear the skipped count
uWrCnt := 0;                                   // 已写段计数清零 / clear the written count
uValidN := 0;                                  // 合法宽度段数清零 / clear the legal width count
uGuard := 0;                                   // 守卫计数清零 / clear the guard counter

// 段 2｜段数闸：0 段与超容量分别归入两个故障码，绝不索引越界 / segment 2, segment count gate
IF uSegCount < 1 THEN
    eErr := 16#0001_030F;                      // 段数为 0 故障码 / zero segment count fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF
IF uSegCount > DL_SEG_MAX THEN
    eErr := 16#0001_0310;                      // 段表自相矛盾故障码 / contradictory segment table fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 3｜段表预清与宽度预筛：宽度不在 1~32 的段直接判不可用 / segment 3, clear the table and pre-screen the widths
FOR uSeg := 0 TO DL_SEG_MAX - 1 DO
    abUse[uSeg] := FALSE;                      // 先全部判不可用 / mark every segment unusable first
    auSnap[uSeg] := 0;                         // 快照清零 / clear the snapshot
    auWrStart[uSeg] := 0;                      // 写区间记录清零 / clear the written range start
    auWrEnd[uSeg] := 0;                        // 写区间记录清零 / clear the written range end
END_FOR
FOR uSeg := 0 TO uSegCount - 1 DO
    IF (auWidth[uSeg] >= 1) AND (auWidth[uSeg] <= DL_SEG_WIDTH_MAX) THEN
        abUse[uSeg] := TRUE;                   // 宽度合法，进入判界 / legal width, proceed to the range check
        uValidN := uValidN + 1;                // 合法段计数 / count the legal segment
    END_IF
END_FOR
IF uValidN < 1 THEN
    eErr := 16#0001_030F;                      // 宽度全为 0 故障码 / all widths zero fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 4｜第一遍：判界 + 快照读（此遍绝不写目标）/ segment 4, first pass, range check and snapshot read only
FOR uSeg := 0 TO uSegCount - 1 DO
    uGuard := uGuard + 1;                      // 守卫累加 / accumulate the guard
    IF uGuard > DL_SEG_MAX_LOOP THEN
        eErr := 16#0001_0311;                  // 守卫超限故障码 / guard exceeded fault id
        bError := TRUE;                        // 置故障标志 / raise the error flag
        RETURN;                                // 结果作废 / discard the whole result
    END_IF
    IF abUse[uSeg] THEN
        IF ((auSrcBit[uSeg] + auWidth[uSeg]) > DL_SEG_WIN_BITS)
           OR ((auDstBit[uSeg] + auWidth[uSeg]) > DL_SEG_WIN_BITS)
           OR (auSrcBit[uSeg] >= DL_SEG_WIN_BITS)
           OR (auDstBit[uSeg] >= DL_SEG_WIN_BITS) THEN
            abUse[uSeg] := FALSE;              // 越界段判不可用，绝不部分写入 / out-of-range segment unusable, never partially written
            uSkippedSeg := uSkippedSeg + 1;    // 跳过计数 / count the skip
            eErr := 16#0001_023B;              // 越界提示（信息级不置故障）/ range hint, info level never raises a fault
        ELSE
            FOR uBit := 0 TO auWidth[uSeg] - 1 DO
                uSrcAbs := auSrcBit[uSeg] + uBit;             // 源绝对位号 / absolute source bit
                uWordIdx := uSrcAbs / DL_SEG_WORD_BITS;        // 字索引，绝对位号不超过 127 故不超过 3 / word index, absolute bit never exceeds 127 so never exceeds 3
                uBitPos := uSrcAbs - uWordIdx * DL_SEG_WORD_BITS; // 字内位号 0~31 / bit position inside the word 0~31
                uBitMask := SHL(DL_SEG_BIT_ONE, uBitPos);      // 掩码，移位量恒小于 32 / mask, shift count always below 32
                IF (auSrcWord[uWordIdx] AND uBitMask) <> 0 THEN
                    auSnap[uSeg] := auSnap[uSeg] OR SHL(DL_SEG_BIT_ONE, uBit); // 位收敛进快照 / gather the bit into the snapshot
                END_IF
            END_FOR
        END_IF
    ELSE
        uSkippedSeg := uSkippedSeg + 1;        // 宽度非法段同样计数跳过 / count the illegal width segment as skipped
        eErr := 16#0001_023B;                  // 跳过提示（信息级不置故障）/ skip hint, info level never raises a fault
    END_IF
END_FOR

// 段 5｜第二遍：统一写目标（快照已完整，读写互不污染）/ segment 5, second pass, single write phase
FOR uSeg := 0 TO uSegCount - 1 DO
    IF abUse[uSeg] THEN
        bOverlap := FALSE;                     // 重叠标志先清 / clear the overlap flag
        FOR uWr := 0 TO uWrCnt - 1 DO
            IF (auDstBit[uSeg] < auWrEnd[uWr]) AND ((auDstBit[uSeg] + auWidth[uSeg]) > auWrStart[uWr]) THEN
                bOverlap := TRUE;              // 与已写区间相交 / overlaps a written range
            END_IF
        END_FOR
        IF bOverlap THEN
            eErr := 16#0001_023B;              // 重叠提示，按段序后者覆盖前者（信息级）/ overlap hint, later segment overwrites the earlier one (info level)
        END_IF
        FOR uBit := 0 TO auWidth[uSeg] - 1 DO
            uDstAbs := auDstBit[uSeg] + uBit;                  // 目标绝对位号 / absolute destination bit
            uWordIdx := uDstAbs / DL_SEG_WORD_BITS;            // 字索引，判界已保证不超过 3 / word index, guaranteed below 4 by the range check
            uBitPos := uDstAbs - uWordIdx * DL_SEG_WORD_BITS;  // 字内位号 0~31 / bit position inside the word 0~31
            uBitMask := SHL(DL_SEG_BIT_ONE, uBitPos);          // 掩码，移位量恒小于 32 / mask, shift count always below 32
            IF (auSnap[uSeg] AND SHL(DL_SEG_BIT_ONE, uBit)) <> 0 THEN
                auDstWord[uWordIdx] := auDstWord[uWordIdx] OR uBitMask;      // 置位 / set the bit
            ELSE
                auDstWord[uWordIdx] := auDstWord[uWordIdx] AND NOT uBitMask; // 清位 / clear the bit
            END_IF
        END_FOR
        auWrStart[uWrCnt] := auDstBit[uSeg];   // 记录本次写区间起点 / record the written range start
        auWrEnd[uWrCnt] := auDstBit[uSeg] + auWidth[uSeg]; // 记录本次写区间终点 / record the written range end
        uWrCnt := uWrCnt + 1;                  // 已写段加一，上界由段数闸保证 / increment the written count, bounded by the segment gate
        uMovedSeg := uMovedSeg + 1;            // 搬运段数加一 / increment the moved count
        uGuard := uGuard + 1;                  // 守卫累加 / accumulate the guard
        IF uGuard > (DL_SEG_MAX_LOOP * 2) THEN
            eErr := 16#0001_0311;              // 守卫超限故障码 / guard exceeded fault id
            bError := TRUE;                    // 置故障标志 / raise the error flag
            RETURN;                            // 结果作废 / discard the whole result
        END_IF
    END_IF
END_FOR

// 段 6｜出口：至少搬成一段且无故障级码才返回 TRUE / segment 6, exit with TRUE only when something moved and no fault occurred
FC_DL_BitSegmentBlockMove := (NOT bError) AND (uMovedSeg > 0); // 成败判据 / success criterion
END_FUNCTION
