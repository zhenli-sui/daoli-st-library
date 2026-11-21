(*
    组件名称 : FC_DL_Crc16Generic
    所属子库 : DL_MathData
    当前版本 : 1.0.1
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 参数化 CRC-16，poly / init / xorout / 输入反射 / 输出反射全部引脚化，一张实现覆盖任意从站协议。
              取舍 ①：参数化的动因 —— 库内 Crc16Modbus / Crc16Ccitt 把参数写死，遇到非标从站（自定义 poly 或只反射
              输入不反射输出）只能现场改源码，一改就失去可移植性；本件把参数域全部抬到引脚，算法内核只剩一份。
              取舍 ②：逐位算法，零查表零内存 —— 查表版快 8 倍但要 512 字节常量表，而跨平台移植时表初始化语法
              （数组常量初始化）恰恰是最容易踩坑的地方；本件优先可移植性，用 8 次定长位循环换「拷到任何平台都能编」。
              取舍 ③：反射不用专用位反指令 —— IEC 61131-3 没有标准位反函数，各平台扩展名不同；改用
              「右移 + 判最低位」的 8 次定长循环自建反射，只依赖 SHR/SHL/AND/OR。
              取舍 ④：帧长超上限拒绝而不截断 —— 截断后算出的 CRC 格式完全合法，却必然在校验端失败，
              这种「看起来对」的错误比明确报错贵得多。
    开源溯源 : T2-1 LGF CRC 子族，只借其参数域（initValue / finalXorValue / reflectInput / reflectResult）这一；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。
              分类级事实；逐位算法、反射实现、码位与错误分级 100% 自有，零代码行与注释复制。
    本文件内含 : FUNCTION FC_DL_Crc16Generic（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 多项式零闸 + 帧长闸 + 空帧短路 + 位循环定长（无 WHILE、无需守卫）
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 位宽、循环边界、缓冲上限全常量化
    校验向量 : 对 ASCII "123456789"（9 字节，DL_CRC_VECT_LEN = 9）：
              ① CRC-16/ARC  poly=16#8005 init=16#0000 xorout=16#0000 入出双反射 → 16#BB3D
              ② CCITT-FALSE poly=16#1021 init=16#FFFF xorout=16#0000 不反射   → 16#29B1
              ③ XMODEM      poly=16#1021 init=16#0000 xorout=16#0000 不反射   → 16#31C3
              编码时以同构逐位算法做等价复算，三组向量全部命中（三元组与公开 CRC 参数目录一致）。
              任一不符即判定实现错误、禁止入库（R1 式规格向量错误防线）。
    错误码   : 16#0001_0445 [信息级] 空帧，返回 init XOR xorout，bValid = TRUE
               16#0001_0444 [信息级] 输出反射为真但多项式最高位为 0，疑似参数不匹配，bValid = TRUE
               16#0001_0384 [故障级] 多项式为零，CRC 无意义，返回 init XOR xorout，bValid = FALSE
               16#0001_0385 [故障级] 帧长超 DL_CRC_BUF_MAX，拒绝计算（不截断），返回 0，bValid = FALSE
               16#0001_0386 [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0445 用 / 16#0001_0444 用 ｜ 16#0001_0384 用 / 16#0001_0385 用 / 16#0001_0386 预留
    遗留假设 : ① 三组校验向量由等价算法脚本复算命中，未在 PLC 上实机运行 —— 属「算法已证、编译器未证」，
              交付门槛：须在 CODESYS / TwinCAT 3 / InoProShop 各编译并跑一次向量。
              ② WORD 上的 SHL/SHR 按 16 位容器截断（IEC 语义推导），若某平台按 32 位提升，位循环结果会偏离；
              该假设是本件唯一实质平台风险，需在门槛项里一并验证。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 2 入库
        2026-11-16  v1.0.1  R21 终审修复（中等）：空帧分支原写 `uInit XOR uXorOut`，未过输出反射，
                            与本件自身的段 6 反射口径自相矛盾。零字节数据的正确结果应为
                            反射16(初值) XOR 终值：初值为回文（16#0000 / 16#FFFF）时两式同值，
                            非回文初值 + bReflectOut = TRUE 的参设下必错（典型如 init = 16#1234 的自定义从站）。
                            现空帧分支复用 16 次定长反射循环后再异或终值，与主体路径完全同构。
                            三组公开校验向量（非空帧）不受影响，仍为 BB3D / 29B1 / 31C3。
*)
FUNCTION FC_DL_Crc16Generic : WORD
VAR_INPUT
    nLen            : UINT;   // 待校验字节数，0~DL_CRC_BUF_MAX，0 = 空帧 [字节] / number of bytes, zero means an empty frame [byte]
    uPoly           : WORD;   // 生成多项式，如 16#8005 / 16#1021，为 0 即判故障 [无量纲] / generator polynomial, zero is a fault [dimensionless]
    uInit           : WORD;   // 寄存器初值 [无量纲] / initial register value [dimensionless]
    uXorOut         : WORD;   // 结果异或值 [无量纲] / final xor value [dimensionless]
    bReflectIn      : BOOL;   // 输入字节按位反射 / reflect every input byte
    bReflectOut     : BOOL;   // 结果 16 位反射 / reflect the sixteen bit result
END_VAR
VAR_IN_OUT
    afData          : ARRAY[0..DL_CRC_BUF_MAX] OF BYTE;   // 待校验字节数组，仅前 nLen 个有效 [字节] / data buffer, only the first nLen bytes are used [byte]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用 / result usable flag
END_VAR
VAR
    uCrc            : WORD;   // CRC 寄存器 [无量纲] / CRC register [dimensionless]
    uByte           : BYTE;   // 当前处理字节 [字节] / byte under processing [byte]
    uByteRefl       : WORD;   // 字节反射中间量 [位图] / byte reflection scratch [bitmap]
    uCrcRefl        : WORD;   // 结果反射中间量 [位图] / result reflection scratch [bitmap]
    uIdx            : UINT;   // 字节游标 [字节] / byte cursor [byte]
    nBit            : INT;    // 位游标 0~7 [位] / bit cursor 0..7 [bit]
    nReflBit        : INT;    // 反射循环位游标 0~15 [位] / reflection cursor 0..15 [bit]
END_VAR
VAR CONSTANT
    DL_CRC_BUF_MAX      : UINT := 255;                    // 单帧字节数上限（Modbus RTU / 645 远小于此）[字节] / frame length upper bound [byte]
    DL_CRC_BITS         : USINT := 16;                    // CRC 位宽，仅供上层核对位宽一致性；逻辑用 DL_CRC_REFL_LAST = 本值 − 1，故此处为说明性常量而非死码 [位] / CRC width kept as an advisory constant, the logic uses the last index instead [bit]
    DL_CRC_BIT_LAST     : INT := 7;                       // 字节位循环末值 [位] / last index of the byte bit loop [bit]
    DL_CRC_REFL_LAST    : INT := 15;                      // 结果反射循环末值 [位] / last index of the result reflection loop [bit]
    DL_CRC_SHIFT_BYTE   : INT := 8;                       // 字节左移量，恒为 8 [位] / constant left shift for one byte [bit]
    DL_CRC_LEN_NONE     : UINT := 0;                      // 空帧长度哨兵，减法前必判 [字节] / empty frame sentinel, tested before any subtraction [byte]
    DL_CRC_MSB_MASK     : WORD := 16#8000;                // 最高位掩码 [位图] / most significant bit mask [bitmap]
    DL_CRC_LSB_MASK     : WORD := 16#0001;                // 最低位掩码 [位图] / least significant bit mask [bitmap]
    DL_CRC_BYTE_MASK    : WORD := 16#00FF;                // 低字节掩码，反射结果收敛到字节 [位图] / low byte mask for the reflected byte [bitmap]
    DL_CRC_WORD_ZERO    : WORD := 16#0000;                // 零哨兵 [无量纲] / zero sentinel [dimensionless]
    DL_ERR_NONE         : UDINT := 16#0000_0000;          // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_Crc16Generic := DL_CRC_WORD_ZERO;   // 故障缺省返回 0 / fault default returns zero
eErr   := DL_ERR_NONE;                    // 预置无错误 / preset no error
bError := FALSE;                          // 预置无故障 / preset no fault
bValid := FALSE;                          // 预置结果不可用 / preset unusable
uCrc   := uInit;                          // 寄存器装载初值 / load the initial value

// 段 2｜多项式闸：零多项式等于没有校验，必须拒算 / segment 2, zero polynomial gate
IF uPoly = DL_CRC_WORD_ZERO THEN
    FC_DL_Crc16Generic := uInit XOR uXorOut;   // 退化情形返回「初值异或终值」，口径与空帧一致 / degenerate case returns init xor xorout
    eErr   := 16#0001_0384;                    // 多项式为零（故障级）/ zero polynomial, fault level
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    RETURN;                                    // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 3｜帧长闸：超上限拒绝，绝不截断（截断的 CRC 必然校验失败却看着合法）/ segment 3, length gate, refuse instead of truncating
IF nLen > DL_CRC_BUF_MAX THEN
    FC_DL_Crc16Generic := DL_CRC_WORD_ZERO;    // 不给可疑结果 / never emit a suspicious result
    eErr   := 16#0001_0385;                    // 帧长超上限（故障级）/ frame too long, fault level
    bError := TRUE;                            // 置故障标志 / raise the fault flag
    RETURN;                                    // bValid 保持 FALSE / bValid stays FALSE
END_IF
IF nLen = DL_CRC_LEN_NONE THEN
    // 空帧同样必须过输出反射：寄存器一个字节都没进过，结果 = 反射16(初值) XOR 终值。
    // 漏这一步在初值为回文（16#0000 / 16#FFFF）时看不出差异，换非回文参设立刻错值，故不可省。
    uCrc := uInit;                             // 寄存器回到初值 / put the register back to the initial value
    IF bReflectOut THEN
        uCrcRefl := DL_CRC_WORD_ZERO;          // 反射累加器清零 / clear the reflection accumulator
        FOR nReflBit := 0 TO DL_CRC_REFL_LAST DO
            uCrcRefl := SHL(uCrcRefl, 1);                          // 左移腾位 / shift to make room
            uCrcRefl := uCrcRefl OR (uCrc AND DL_CRC_LSB_MASK);    // 取寄存器最低位 / take the lowest register bit
            uCrc     := SHR(uCrc, 1);                              // 寄存器右移 / shift the register down
        END_FOR
        uCrc := uCrcRefl;                      // 回写反射结果 / write the reflected value back
    END_IF
    FC_DL_Crc16Generic := uCrc XOR uXorOut;    // 空帧返回 反射(初值) XOR 终值（标准行为）/ an empty frame returns the reflected initial value xor xorout
    eErr   := 16#0001_0445;                    // 空帧（信息级，不置 bError）/ empty frame, info level
    bValid := TRUE;                            // 空帧是协议合法输入 / an empty frame is a legal protocol input
    RETURN;                                    // 提前出口，绝不进循环 / early exit, never enter the loop
END_IF

// 段 4｜反射参数一致性提示：输出反射却给了最高位为 0 的 poly，多半是参数抄错 / segment 4, reflection parameter sanity hint
IF bReflectOut AND ((uPoly AND DL_CRC_MSB_MASK) = DL_CRC_WORD_ZERO) THEN
    eErr := 16#0001_0444;                      // 反射参数与多项式最高位疑似不匹配（信息级）/ reflection parameter looks inconsistent, info level
END_IF

// 段 5｜逐字节位算法主体：nLen 已保证 ≥ 1，nLen − 1 不会回绕 / segment 5, byte by byte kernel, nLen is at least one
FOR uIdx := 0 TO nLen - 1 DO
    uByte := afData[uIdx];                     // 取当前字节，索引上界由长度闸保证 / fetch the byte, the upper bound is guaranteed by the length gate
    IF bReflectIn THEN
        uByteRefl := DL_CRC_WORD_ZERO;         // 反射累加器清零 / clear the reflection accumulator
        FOR nBit := 0 TO DL_CRC_BIT_LAST DO
            uByteRefl := SHL(uByteRefl, 1);                              // 左移腾位 / shift to make room
            uByteRefl := uByteRefl OR (BYTE_TO_WORD(uByte) AND DL_CRC_LSB_MASK);   // 取源字节最低位 / take the lowest source bit
            uByte     := SHR(uByte, 1);                                  // 源字节右移 / shift the source byte down
        END_FOR
        uByte := WORD_TO_BYTE(uByteRefl AND DL_CRC_BYTE_MASK);           // 收敛回一个字节 / converge back to one byte
    END_IF

    uCrc := uCrc XOR SHL(BYTE_TO_WORD(uByte), DL_CRC_SHIFT_BYTE);        // 字节置入高 8 位 / place the byte into the high half

    FOR nBit := 0 TO DL_CRC_BIT_LAST DO
        IF (uCrc AND DL_CRC_MSB_MASK) <> DL_CRC_WORD_ZERO THEN
            uCrc := SHL(uCrc, 1) XOR uPoly;    // 最高位为 1：左移后异或多项式 / top bit set, shift and xor the polynomial
        ELSE
            uCrc := SHL(uCrc, 1);              // 最高位为 0：只左移 / top bit clear, shift only
        END_IF
    END_FOR
END_FOR

// 段 6｜输出反射：16 次定长位循环，不用平台专用位反指令 / segment 6, output reflection with a fixed sixteen bit loop
IF bReflectOut THEN
    uCrcRefl := DL_CRC_WORD_ZERO;              // 反射累加器清零 / clear the reflection accumulator
    FOR nReflBit := 0 TO DL_CRC_REFL_LAST DO
        uCrcRefl := SHL(uCrcRefl, 1);                          // 左移腾位 / shift to make room
        uCrcRefl := uCrcRefl OR (uCrc AND DL_CRC_LSB_MASK);    // 取寄存器最低位 / take the lowest register bit
        uCrc     := SHR(uCrc, 1);                              // 寄存器右移 / shift the register down
    END_FOR
    uCrc := uCrcRefl;                          // 回写反射结果 / write the reflected value back
END_IF

// 段 7｜终值异或与出口 / segment 7, final xor and exit
FC_DL_Crc16Generic := uCrc XOR uXorOut;        // 异或终值 / apply the final xor
bValid := TRUE;                                // 结果可用 / the result is usable
END_FUNCTION
