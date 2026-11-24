(*==============================================================================
 * 组件名称 (Component)  : FC_DL_WordFromBytes
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（SHL / AND / OR / 类型转换），零厂商方言
 * 来源标签 (Source)     : t2-1-lgf-converter（字节序组装族，clean-room 编写）
 * 功能描述 (Function)   : BYTE 数组按字节序组装为 WORD / DWORD。返回值以 DWORD 承载：
 *                         nTargetLen = 2 时结果在低 16 位（高 16 位恒零），
 *                         nTargetLen = 4 时为完整 32 位结果。
 *                         四序语义（E_DL_ByteOrder，WORD 目标下三序退化披露）：
 *                           eAbcd：字节 i 落槽位 i（槽 0 = 最高字节，大端直排）
 *                           eDcba：字节 i 落槽位 (nTargetLen-1-i)（全反序）
 *                           eBadc：字节 i 落槽位 (i XOR 1)（寄存器内两两互换）
 *                           eCdab：DWORD 下字节 i 落槽位 (i XOR 2)（高低字互换）；
 *                                  WORD 下退化为字节反序（单字容器内高低字互换
 *                                  不可区分，验收向量 16#1234 即按此口径）。
 *                         组装字节数不足按高段补零并置信息级；映射为对合（ involutive），
 *                         与 FC_DL_WordToBytes 同序构成 round-trip 双向对。
 * 归属声明 (Ownership)  : E_DL_ByteOrder 归属 DL_MathData\FC_DL_SwapBytes32.st，
 *                         本件只引用不重声明（FB51-7）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 指针 NIL 或字节数 <= 0：结构性早退，返回零值 + bValid FALSE（零写入语义），
 *      不触碰调用方内存。
 *   2) 组装字节数大于目标长度：多余低位字节忽略（不计码——调用方传入 nCount
 *      本身即可观测该事实，R90 反证成立不加码）。
 *   3) 移位量上界 (nTargetLen-1-slot)*8 结构性 <= 24 < 32（DWORD 位宽），禁 MOD
 *      归一的不变量由本披露承担（R48 口径：非裸变量超宽移位）。
 *   4) 验收向量：CDAB 序 {16#34, 16#12} -> 16#0000_1234；ABCD {16#12,16#34,16#56,16#78}
 *      -> 16#1234_5678；长度 1 组装 WORD -> 16#0000_1200 高段补零 + 信息级。
 * 故障码表 (Error codes) :
 *   16#0001_03F3 [故障级] 字节指针 NIL 或 nCount <= 0，返回零 + bValid FALSE
 *                 反证：零返回值与「源字节全零」的正常结果组合相同，bValid
 *                 只表达有效性，故障成因必须由码位承载。
 *   16#0001_03F4 [故障级] 字节序枚举越界（非 0..3），回退默认大端 eAbcd 继续服务
 *                 （对齐 Crc8 非法变体先例：先落默认行为再置码）
 *                 反证：eAbcd 回退结果与显式填 eAbcd 输出组合相同，码位承载
 *                 「组态有误」事实。
 *   16#0001_04B8 [信息级] 源字节数不足目标长度，高段槽位补零
 *                 反证：补零结果与「源字节高段本来就是零」组合相同，无码不可区分。
 *   16#0001_04B9 [信息级] nTargetLen 非 2/4，回退默认 WORD（2 字节）继续服务
 *                 反证：回退结果与显式填 2 相同，码位承载组态有误事实。
 * 码位总账 (Code ledger) : 16#0001_03F3 / 03F4 用 ｜ 16#0001_04B8 / 04B9 用
 * 依赖     (Depends)    : TYPE E_DL_ByteOrder（属主 FC_DL_SwapBytes32.st，只引用）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3（指针判空 + 标准移位/转换）
 *                         R4 ✓ 指针 NIL 闸 / 计数域闸 / 枚举域闸 / 全分支码位配对
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯函数，无状态机）
 *                         R7 N/A（无定时器 / 边沿实例）
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 1 · 目标 4）
 *============================================================================*)
FUNCTION FC_DL_WordFromBytes : DWORD
VAR_INPUT
    pBytes     : POINTER TO BYTE;   // 源字节数组首指针，NIL = 无效 / Source byte pointer, NIL invalid
    nCount     : INT;               // 源字节数 [个]，<= 0 无效 / Source byte count, <= 0 invalid
    eOrder     : E_DL_ByteOrder;    // 字节序选择（属主 FC_DL_SwapBytes32.st）/ Byte order selector
    nTargetLen : INT := 2;          // 目标长度 [字节]，2 = WORD，4 = DWORD / Target length in bytes
END_VAR
VAR_OUTPUT
    bValid   : BOOL;    // 本拍组装有效 / Assembly valid this call
    bError   : BOOL;    // 故障标志（0305 / 0306 置位，R45 配对）/ Fault flag, set on 0305 and 0306
    uInfoId  : UDINT;   // 故障码，0 = 无故障（纯函数每拍重算）/ Error code, recomputed per call
END_VAR
VAR
    uAcc     : DWORD;   // 组装累加器 / Assembly accumulator
    nUse     : INT;     // 实际参与组装的字节数 [个] / Bytes actually assembled
    nSlot    : INT;     // 当前字节映射到的槽位 [0..3] / Slot the current byte maps to
    nShift   : DINT;    // 当前槽位移位量 [bit]，结构性 <= 24（ANY_INT 口径）/ Slot shift, structurally <= 24
    uB       : BYTE;    // 当前源字节 / Current source byte
    nLenUse  : INT;     // 钳位后的目标长度 [字节] / Clamped target length
    bOrderOk : BOOL;    // 字节序枚举合法性 / Byte order validity
    i        : INT;     // 遍历索引 / Loop index
END_VAR
VAR CONSTANT
    DL_WFB_LEN_MIN : INT := 2;    // 目标长度下限 [字节]（WORD）/ Target length floor, WORD
    DL_WFB_LEN_MAX : INT := 4;    // 目标长度上限 [字节]（DWORD）/ Target length ceiling, DWORD
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（P-01 范式）：任何异常路径返回零 + bValid FALSE，绝不返回残值
 *      Safe preset: every exceptional path returns zero with bValid FALSE
 *-----------------------------------------------------------------------------*)
FC_DL_WordFromBytes := 16#0000_0000;
bValid  := FALSE;
bError  := FALSE;
uInfoId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜域闸（R151 全枚举：指针 + 计数 + 目标长度 + 枚举四闸，结构性 IF/ELSE 不用 RETURN）
 *      Domain gates: pointer, count, target length and enum, full IF/ELSE coverage
 *-----------------------------------------------------------------------------*)
IF (pBytes = 0) OR (nCount <= 0) THEN
    uInfoId := 16#0001_03F3;    // 故障级：指针 NIL 或计数非法 / Fault: NIL pointer or bad count
    bError  := TRUE;            // R45 配对：故障码同行置位 / Paired with the fault code
    RETURN;                     // 结构性早退：输出已全预置，零写入语义成立（规格明示豁免）
END_IF

IF (nTargetLen < DL_WFB_LEN_MIN) OR (nTargetLen > DL_WFB_LEN_MAX) THEN
    nLenUse := DL_WFB_LEN_MIN;  // 二级回退：钳回默认 WORD（R117 两级参数回退）
    uInfoId := 16#0001_04B9;    // 信息级：目标长度非法回默认 / Info: length defaulted
ELSE
    nLenUse := nTargetLen;      // 合法直通 / Valid pass-through
END_IF

bOrderOk := (eOrder = E_DL_ByteOrder.eAbcd) OR (eOrder = E_DL_ByteOrder.eDcba)
            OR (eOrder = E_DL_ByteOrder.eBadc) OR (eOrder = E_DL_ByteOrder.eCdab);
IF NOT bOrderOk THEN
    uInfoId := 16#0001_03F4;    // 故障级：字节序越界回默认大端（0142 风格先例口径）/ Fault: order defaulted
    bError  := TRUE;            // R45 配对 / Paired with the fault code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组装主体（边界 B1/B3）：映射 -> 取字节 -> 升位 -> 移位 -> 或合
 *      Assembly body: map, fetch, widen, shift, OR-accumulate
 *      nUse 不足 nLenUse 时高位槽不落值 = 高段补零（信息级 0407）
 *-----------------------------------------------------------------------------*)
uAcc := 16#0000_0000;

IF nCount < nLenUse THEN
    nUse := nCount;             // 不足：只组前 nUse 字节，高段零 / Short: assemble what we have
    uInfoId := 16#0001_04B8;    // 信息级：源字节不足补零 / Info: padded with zeros
ELSE
    nUse := nLenUse;            // 充足：全量组装 / Full assembly
END_IF

FOR i := 0 TO (nUse - 1) DO
    (* 槽位映射（对合映射，与 WordToBytes 同口径，round-trip 成立） *)
    (* Slot mapping, involutive, shared with WordToBytes for round-trip *)
    IF eOrder = E_DL_ByteOrder.eDcba THEN
        nSlot := (nLenUse - 1) - i;          // 全反序 / Full reverse
    ELSIF eOrder = E_DL_ByteOrder.eBadc THEN
        nSlot := (i XOR 1) MOD nLenUse;      // 寄存器内两两互换 / Swap within register pairs
    ELSIF eOrder = E_DL_ByteOrder.eCdab THEN
        IF nLenUse = DL_WFB_LEN_MAX THEN
            nSlot := (i XOR 2) MOD nLenUse;  // DWORD：高低字互换 / DWORD: word swap
        ELSE
            nSlot := 1 - i;                  // WORD：退化为字节反序（见头披露）/ WORD: degenerate reverse
        END_IF
    ELSE
        nSlot := i;                          // eAbcd 大端直排（含越界回退默认）/ Big endian, incl. fallback
    END_IF

    uB     := pBytes[i];                       // 取源字节（指针下标访问）/ Fetch source byte
    nShift := (nLenUse - 1 - nSlot) * 8;       // 槽位移位量 [bit]，DINT 承载，结构性 <= 24 / Slot shift
    uAcc   := uAcc OR SHL(BYTE_TO_DWORD(uB), nShift);    // 升位左移按位或 / Widen, shift, OR
END_FOR

(*------------------------------------------------------------------------------
 * 段 4｜结果回写：WORD 目标结果天然落在低 16 位（槽位 0..1 移位量 0/8），无需再掩码
 *      Result write-back: WORD target lands in the low word by construction
 *-----------------------------------------------------------------------------*)
FC_DL_WordFromBytes := uAcc;
bValid := TRUE;
END_FUNCTION
