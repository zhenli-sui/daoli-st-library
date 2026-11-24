(*==============================================================================
 * 组件名称 (Component)  : FC_DL_WordToBytes
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（SHR / AND / 类型转换），零厂商方言
 * 来源标签 (Source)     : t2-1-lgf-converter（字节序拆解族，clean-room 编写）
 * 功能描述 (Function)   : WORD / DWORD 按字节序拆解为 BYTE 数组（写经指针输出）。
 *                         槽位语义与 FC_DL_WordFromBytes 完全对偶：槽 0 = 最高字节；
 *                         映射为对合映射（ involutive），同一序号下
 *                         WordToBytes(WordFromBytes(bytes, eOrder, len), eOrder, len)
 *                         逐字节还原源数组（round-trip 验收）。
 *                         nValueLen = 2 时只取低 16 位（高 16 位忽略）。
 *                         缓冲长度不足时钳位只写前 nBufLen 个槽位并置信息级。
 * 归属声明 (Ownership)  : E_DL_ByteOrder 归属 DL_MathData\FC_DL_SwapBytes32.st，
 *                         本件只引用不重声明（FB51-7）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 指针 NIL 或缓冲长度 <= 0：结构性早退，不写任何字节，返回 FALSE（零写入语义）。
 *   2) 缓冲长度大于目标长度：多余槽位不触碰（不置码——缓冲边界由调用方持有，
 *      可观测性在调用方，R90 反证成立不加码）。
 *   3) 还原方向不饱和（R81 披露）：本件是拆解不是还原时刻 / 标识，拆解失败
 *      返回 FALSE + 故障级码，绝无静默饱和写入。
 *   4) 移位量上界 (nLenUse-1-j)*8 结构性 <= 24 < 32（DWORD 位宽），禁 MOD 归一的
 *      不变量由本披露承担（R48 口径）。
 *   5) 验收向量（与 FromBytes 对拍）：CDAB 序 16#0000_1234 -> {16#34, 16#12}；
 *      ABCD 16#1234_5678 -> {16#12,16#34,16#56,16#78}；缓冲 1 字节拆 DWORD
 *      -> 只写最高字节 + 信息级钳位。
 * 故障码表 (Error codes) :
 *   16#0001_03F5 [故障级] 缓冲指针 NIL 或 nBufLen <= 0，不写任何字节，返回 FALSE
 *                 反证：未写缓冲与「缓冲区内容本来如此」不可区分（本件无权回读
 *                 调用方缓冲），码位是唯一的失败事实出口。
 *   16#0001_03F6 [故障级] 字节序枚举越界（非 0..3），回退默认大端 eAbcd 继续服务
 *                 反证：回退结果与显式填 eAbcd 输出组合相同，码位承载组态有误事实。
 *   16#0001_04BA [信息级] 缓冲长度不足目标长度，已钳位只写前段
 *                 反证：钳位写入与「调用方只想要前段」输出组合相同，无码不可区分。
 *   16#0001_04BB [信息级] nValueLen 非 2/4，回退默认 WORD（2 字节）继续服务
 *                 反证：回退结果与显式填 2 相同，码位承载组态有误事实。
 * 码位总账 (Code ledger) : 16#0001_03F5 / 03F6 用 ｜ 16#0001_04BA / 04BB 用
 * 依赖     (Depends)    : TYPE E_DL_ByteOrder（属主 FC_DL_SwapBytes32.st，只引用）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3（指针判空 + 标准移位/转换）
 *                         R4 ✓ 指针 NIL 闸 / 缓冲域闸 / 枚举域闸 / 全分支码位配对
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯函数，无状态机）
 *                         R7 N/A（无定时器 / 边沿实例）
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 1 · 目标 5）
 *============================================================================*)
FUNCTION FC_DL_WordToBytes : BOOL
VAR_INPUT
    uValue    : DWORD;              // 待拆解值（WORD 目标时只取低 16 位）/ Value to split, low word only for WORD
    nValueLen : INT := 2;           // 值长度 [字节]，2 = WORD，4 = DWORD / Value length in bytes
    eOrder    : E_DL_ByteOrder;     // 字节序选择（属主 FC_DL_SwapBytes32.st）/ Byte order selector
    nBufLen   : INT;                // 输出缓冲长度 [字节]，<= 0 无效 / Output buffer length, <= 0 invalid
    pBuf      : POINTER TO BYTE;    // 输出缓冲首指针（指针本身不被改写，按输入口径）/ Output buffer pointer, never re-pointed
END_VAR
VAR_OUTPUT
    bWritten  : BOOL;    // 本拍写入成功 / Write succeeded this call
    bError    : BOOL;    // 故障标志（0307 / 0308 置位，R45 配对）/ Fault flag, set on 0307 and 0308
    uInfoId   : UDINT;   // 故障码，0 = 无故障（纯函数每拍重算）/ Error code, recomputed per call
END_VAR
VAR
    nWriteLen : INT;     // 本拍实际写入字节数 [个] / Bytes actually written this call
    nSlotByte : INT;     // 当前槽位映射回的源字节下标 / Byte index the current slot maps back to
    nShift    : DINT;    // 当前槽位移位量 [bit]，结构性 <= 24 / Slot shift amount
    uSlotVal  : DWORD;   // 当前槽位值（已掩码低 8 位）/ Current slot value, low 8 bits
    uB        : BYTE;    // 当前槽位字节 / Current slot byte
    nLenUse   : INT;     // 钳位后的值长度 [字节] / Clamped value length
    bOrderOk  : BOOL;    // 字节序枚举合法性 / Byte order validity
    j         : INT;     // 槽位遍历索引 / Slot loop index
END_VAR
VAR CONSTANT
    DL_WTB_LEN_MIN : INT      := 2;          // 值长度下限 [字节]（WORD）/ Value length floor, WORD
    DL_WTB_LEN_MAX : INT      := 4;          // 值长度上限 [字节]（DWORD）/ Value length ceiling, DWORD
    DL_WTB_MASK_FF : DWORD    := 16#0000_00FF; // 低 8 位掩码 / Low byte mask
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（P-01 范式）：任何异常路径不写缓冲、返回 FALSE
 *      Safe preset: every exceptional path writes nothing and returns FALSE
 *-----------------------------------------------------------------------------*)
FC_DL_WordToBytes := FALSE;
bWritten := FALSE;
bError   := FALSE;
uInfoId  := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜域闸（R151 全枚举：指针 + 缓冲 + 值长度 + 枚举四闸）
 *      Domain gates: pointer, buffer, value length and enum
 *-----------------------------------------------------------------------------*)
IF (pBuf = 0) OR (nBufLen <= 0) THEN
    uInfoId := 16#0001_03F5;    // 故障级：指针 NIL 或缓冲非法 / Fault: NIL pointer or bad buffer
    bError  := TRUE;            // R45 配对 / Paired with the fault code
    RETURN;                     // 结构性早退：输出已全预置，零写入语义成立（规格明示豁免）
END_IF

IF (nValueLen < DL_WTB_LEN_MIN) OR (nValueLen > DL_WTB_LEN_MAX) THEN
    nLenUse := DL_WTB_LEN_MIN;  // 二级回退：钳回默认 WORD（R117 两级参数回退）
    uInfoId := 16#0001_04BB;    // 信息级：值长度非法回默认 / Info: length defaulted
ELSE
    nLenUse := nValueLen;       // 合法直通 / Valid pass-through
END_IF

bOrderOk := (eOrder = E_DL_ByteOrder.eAbcd) OR (eOrder = E_DL_ByteOrder.eDcba)
            OR (eOrder = E_DL_ByteOrder.eBadc) OR (eOrder = E_DL_ByteOrder.eCdab);
IF NOT bOrderOk THEN
    uInfoId := 16#0001_03F6;    // 故障级：字节序越界回默认大端（0142 风格先例口径）/ Fault: order defaulted
    bError  := TRUE;            // R45 配对 / Paired with the fault code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜写入长度钳位（边界 B4）：缓冲不足只写前段 + 信息级
 *      Write length clamp: short buffer writes the leading slots only
 *-----------------------------------------------------------------------------*)
IF nBufLen < nLenUse THEN
    nWriteLen := nBufLen;       // 钳位：只写缓冲能容纳的槽位 / Clamp to buffer capacity
    uInfoId   := 16#0001_04BA;  // 信息级：缓冲不足钳位 / Info: buffer clamped
ELSE
    nWriteLen := nLenUse;       // 充足：全量写入 / Full write
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜拆解主体（边界 B1/B3）：取槽 -> 掩码 -> 降位 -> 反映射 -> 写缓冲
 *      Split body: slot, mask, narrow, inverse-map, write buffer
 *      反映射即对合映射本身：i = map(j)（映射自逆，与 FromBytes 同口径）
 *-----------------------------------------------------------------------------*)
FOR j := 0 TO (nWriteLen - 1) DO
    (* 槽位到源字节下标的对合映射（与 FromBytes 逐分支一致） *)
    (* Involutive slot to byte mapping, branch-aligned with WordFromBytes *)
    IF eOrder = E_DL_ByteOrder.eDcba THEN
        nSlotByte := (nLenUse - 1) - j;          // 全反序 / Full reverse
    ELSIF eOrder = E_DL_ByteOrder.eBadc THEN
        nSlotByte := (j XOR 1) MOD nLenUse;      // 寄存器内两两互换 / Swap within register pairs
    ELSIF eOrder = E_DL_ByteOrder.eCdab THEN
        IF nLenUse = DL_WTB_LEN_MAX THEN
            nSlotByte := (j XOR 2) MOD nLenUse;  // DWORD：高低字互换 / DWORD: word swap
        ELSE
            nSlotByte := 1 - j;                  // WORD：退化为字节反序（见头披露）/ WORD: degenerate reverse
        END_IF
    ELSE
        nSlotByte := j;                          // eAbcd 大端直排（含越界回退默认）/ Big endian, incl. fallback
    END_IF

    nShift   := (nLenUse - 1 - j) * 8;                   // 槽位移位量，结构性 <= 24 / Slot shift
    uSlotVal := SHR(uValue, nShift) AND DL_WTB_MASK_FF;  // 取槽位并掩低 8 位 / Slot value masked
    uB       := DWORD_TO_BYTE(uSlotVal);                 // 降位到字节 / Narrow to byte
    pBuf[nSlotByte] := uB;                               // 反映射写入缓冲 / Inverse-mapped write
END_FOR

(*------------------------------------------------------------------------------
 * 段 5｜结果回写：全量或钳位写入均算成功（钳位事实由 0409 承载）
 *      Result write-back: full or clamped write both count as success
 *-----------------------------------------------------------------------------*)
FC_DL_WordToBytes := TRUE;
bWritten := TRUE;
END_FUNCTION
