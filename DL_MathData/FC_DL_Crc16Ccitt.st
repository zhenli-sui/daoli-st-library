(*
    FC_DL_Crc16Ccitt —— CRC-16 三变体位算法（多项式 0x1021 族）
    ------------------------------------------------------------------
    分类      : DL_MathData / Checksum
    前缀      : FC_DL_
    版本      : 1.0.1
    溯源      : T2-1 LGF · Data Handling（源矩阵明列「校验族尚余 CRC-16 反射待挖」）；
                T1-3 OSCAT Network 校验族分类为次源，不复制实现；
                参数集与校验值经一次公开资料核对（三家在线 CRC 计算器一致）；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 一个函数覆盖 CRC-16 三个最常用参数集（同一多项式 0x1021 的三种参数化），
                解决现场「设备手册只写 CRC-16 CCITT，不说 init / 反射」导致的对接失败；
                库内 FC_DL_Crc16Modbus 已占 0x8005 反射族，本件补 0x1021 族；
                反射变体不使用任何位反指令（跨平台可用性风险），改用「右移 + 判最低位」
                循环实现，三个变体共用同一份位循环骨架；
                位循环定长 8 次，无 WHILE，循环次数可静态界定。
    验收向量  : 对 "123456789"（9 字节）逐字节调用后应得
                eCrc16CcittFalse = 16#29B1 ｜ eCrc16Xmodem = 16#31C3 ｜ eCrc16Kermit = 16#2189
    错误码    : 16#0001_023D uLen 超 256 已截断，仅校验前 256 字节——信息级，正常防御
                16#0001_023E 预留禁用（信息级，不得挪用）
                16#0001_0312 预留禁用（故障级，不得挪用；空帧非法方言的预留归属，实现体内零赋值）
                16#0001_0313 变体枚举值非法（CASE 落 ELSE）——故障级，返回 0
                16#0001_0314 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_023D 用 / 16#0001_023E 预留 ｜ 16#0001_0312 预留 / 16#0001_0313 用 / 16#0001_0314 预留
    状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写（变体枚举选择用 CASE 且含 ELSE 兜底）
    采样约定  : 纯组合函数，无定时器、无内部驻留状态；uLen = 0 为空帧，返回 init 值且 bValid 为 TRUE，
                空帧是协议合法输入，不按故障处理。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
                2026-11-16 v1.0.1 R18 终审修复：uLen = 0 时 FOR 终止表达式 uLenEff - 1 在 UINT 下回绕成
                65535，越界读 auData[256..65535] 触发运行时数组越界；改为空帧短路提前返回 init 值，
                循环段保证 uLenEff >= 1。对外引脚与校验值零变更。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_Crc16Vari（归属本函数，与其同文件发布）
 * 含义: CRC-16 参数集选择，成员值写死便于工程持久化
 *----------------------------------------------------------------------------*)
TYPE E_DL_Crc16Vari :
(
    eCrc16CcittFalse := 0,   // CCITT-FALSE：poly 0x1021 / init 0xFFFF / 不反射 / 无终值异或 / CCITT-FALSE, init 0xFFFF, no reflection, no final xor
    eCrc16Xmodem     := 1,   // XMODEM：poly 0x1021 / init 0x0000 / 不反射 / 无终值异或 / XMODEM, init 0x0000, no reflection, no final xor
    eCrc16Kermit     := 2    // KERMIT：poly 0x8408（位反形式）/ init 0x0000 / 入出均反射 / KERMIT, reflected poly 0x8408, init 0x0000, reflected in and out
) UINT;
END_TYPE

FUNCTION FC_DL_Crc16Ccitt : WORD
VAR_INPUT
    auData : ARRAY[0..255] OF BYTE;                          // 待校验字节数组，定长 256，超长由 uLen 截断 [字节] / data bytes, fixed length 256, truncated by uLen [byte]
    uLen   : UINT := 0;                                      // 有效长度 [字节]，范围 0~256，0 = 空帧 / valid length [byte], range 0~256, 0 = empty frame
    eVari  : E_DL_Crc16Vari := E_DL_Crc16Vari.eCrc16CcittFalse; // 参数集选择 / parameter set selection
END_VAR
VAR_OUTPUT
    eErr   : UDINT;                                          // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;                                           // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid : BOOL;                                           // 结果是否可用，故障态 FALSE / result usable flag, FALSE in fault state
END_VAR
VAR
    uCrc     : WORD;                                         // CRC 寄存器 [无量纲] / CRC register [dimensionless]
    uPoly    : WORD;                                         // 生效多项式，由变体决定 [无量纲] / active polynomial selected by the variant [dimensionless]
    uIdx     : UINT;                                         // 字节游标 [字节] / byte cursor [byte]
    nBit     : INT;                                          // 位游标 0~7 [位] / bit cursor 0~7 [bit]
    uByte    : BYTE;                                         // 当前处理字节 [字节] / byte under processing [byte]
    bReflect : BOOL;                                         // 反射变体标志，TRUE 走右移分支 / reflected variant flag, TRUE takes the right-shift branch
    uLenEff  : UINT;                                         // 生效长度，截断后使用 [字节] / effective length after truncation [byte]
END_VAR
VAR CONSTANT
    DL_CRC16_LEN_MAX     : UINT := 256;                      // 长度上限 [字节] / length upper bound [byte]
    DL_CRC16_POLY_MSB    : WORD := 16#1021;                  // 高位先行多项式 [无量纲] / most significant bit first polynomial [dimensionless]
    DL_CRC16_POLY_LSB    : WORD := 16#8408;                  // 低位先行（位反）多项式 [无量纲] / least significant bit first (reflected) polynomial [dimensionless]
    DL_CRC16_INIT_FFFF   : WORD := 16#FFFF;                  // 全一初值 [无量纲] / all ones initial value [dimensionless]
    DL_CRC16_INIT_ZERO   : WORD := 16#0000;                  // 全零初值 [无量纲] / all zeros initial value [dimensionless]
    DL_CRC16_BIT_MSB     : WORD := 16#8000;                  // 最高位掩码 [位图] / most significant bit mask [bitmap]
    DL_CRC16_BIT_LSB     : WORD := 16#0001;                  // 最低位掩码 [位图] / least significant bit mask [bitmap]
    DL_CRC16_SHIFT_BYTE  : INT := 8;                         // 字节位宽，左移量恒为 8 [位] / byte width, the left shift is always 8 [bit]
    DL_CRC16_BIT_LAST    : INT := 7;                         // 位循环末值 [位] / last index of the bit loop [bit]
    DL_CRC16_LEN_NONE    : UINT := 0;                        // 空帧长度哨兵，用于 UINT 减法前判零 [字节] / empty frame length sentinel, guards the UINT subtraction [byte]
    DL_CRC16_CHECK_CCITT : WORD := 16#29B1;                  // "123456789" 的 CCITT-FALSE 校验值（验收向量）[无量纲] / check value for "123456789", CCITT-FALSE [dimensionless]
    DL_CRC16_CHECK_XMODEM: WORD := 16#31C3;                  // "123456789" 的 XMODEM 校验值（验收向量）[无量纲] / check value for "123456789", XMODEM [dimensionless]
    DL_CRC16_CHECK_KERMIT: WORD := 16#2189;                  // "123456789" 的 KERMIT 校验值（验收向量）[无量纲] / check value for "123456789", KERMIT [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_Crc16Ccitt := DL_CRC16_INIT_ZERO;        // 故障缺省返回 0 / fault default returns zero
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bValid := FALSE;                               // 预置结果不可用，通过闸门后置位 / preset unusable, set TRUE after the gates
uLenEff := uLen;                               // 默认沿用输入长度 / default to the input length

// 段 2｜长度闸：超上限先截断再校验，绝不越界读 / segment 2, length gate truncates before any read
IF uLen > DL_CRC16_LEN_MAX THEN
    uLenEff := DL_CRC16_LEN_MAX;               // 截断到 256 字节 / truncate to 256 bytes
    eErr := 16#0001_023D;                      // 截断提示（信息级不置故障）/ truncation hint, info level never raises a fault
END_IF

// 段 3｜变体参数装载（CASE 必须含 ELSE 兜底，红线）/ segment 3, load the variant parameters
CASE eVari OF
    E_DL_Crc16Vari.eCrc16CcittFalse :
        uCrc := DL_CRC16_INIT_FFFF;            // 全一初值 / all ones initial value
        uPoly := DL_CRC16_POLY_MSB;            // 高位先行多项式 / most significant bit first polynomial
        bReflect := FALSE;                     // 不反射 / no reflection
    E_DL_Crc16Vari.eCrc16Xmodem :
        uCrc := DL_CRC16_INIT_ZERO;            // 全零初值 / all zeros initial value
        uPoly := DL_CRC16_POLY_MSB;            // 高位先行多项式 / most significant bit first polynomial
        bReflect := FALSE;                     // 不反射 / no reflection
    E_DL_Crc16Vari.eCrc16Kermit :
        uCrc := DL_CRC16_INIT_ZERO;            // 全零初值 / all zeros initial value
        uPoly := DL_CRC16_POLY_LSB;            // 位反多项式 / reflected polynomial
        bReflect := TRUE;                      // 入出均反射 / reflected in and out
ELSE
    eErr := 16#0001_0313;                      // 变体枚举非法故障码 / illegal variant enum fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bValid := FALSE;                           // 结果不可用 / result unusable
    FC_DL_Crc16Ccitt := DL_CRC16_INIT_ZERO;    // 返回 0 / return zero
    RETURN;                                    // 故障级提前返回 / early return on fault
END_CASE

// 段 4｜空帧短路：UINT 下 uLenEff - 1 在 uLenEff = 0 时回绕成 65535，直接进循环会越界读 / segment 4, empty frame short circuit
// 说明：IEC 61131-3 的 FOR 终止表达式在进入循环时求值一次，故 0 - 1 必然回绕，必须先判零再做减法
IF uLenEff = DL_CRC16_LEN_NONE THEN
    FC_DL_Crc16Ccitt := uCrc;                  // 空帧返回 init 值 / an empty frame returns the initial value
    bValid := TRUE;                            // 空帧是协议合法输入 / an empty frame is a legal protocol input
    RETURN;                                    // 提前出口，绝不进循环 / early exit, never enter the loop
END_IF

// 段 4b｜逐字节位算法：uLenEff 已保证 >= 1，减法安全 / segment 4b, byte by byte bit algorithm with a safe subtraction
FOR uIdx := 0 TO uLenEff - 1 DO
    uByte := auData[uIdx];                     // 取当前字节，索引上界已由长度闸保证 / fetch the byte, the upper bound is guaranteed by the length gate
    IF bReflect THEN
        uCrc := uCrc XOR BYTE_TO_WORD(uByte);  // 反射变体：低字节对齐异或 / reflected variant, low byte aligned xor
        FOR nBit := 0 TO DL_CRC16_BIT_LAST DO
            IF (uCrc AND DL_CRC16_BIT_LSB) <> 0 THEN
                uCrc := SHR(uCrc, 1) XOR uPoly; // 最低位为 1 则右移后异或多项式 / shift right and xor the polynomial when the lowest bit is set
            ELSE
                uCrc := SHR(uCrc, 1);          // 最低位为 0 只右移 / shift right only when the lowest bit is clear
            END_IF
        END_FOR
    ELSE
        uCrc := uCrc XOR SHL(BYTE_TO_WORD(uByte), DL_CRC16_SHIFT_BYTE); // 高位先行：字节左移 8 位异或 / msb first, xor the byte shifted left by eight
        FOR nBit := 0 TO DL_CRC16_BIT_LAST DO
            IF (uCrc AND DL_CRC16_BIT_MSB) <> 0 THEN
                uCrc := SHL(uCrc, 1) XOR uPoly; // 最高位为 1 则左移后异或多项式 / shift left and xor the polynomial when the highest bit is set
            ELSE
                uCrc := SHL(uCrc, 1);          // 最高位为 0 只左移 / shift left only when the highest bit is clear
            END_IF
        END_FOR
    END_IF
END_FOR

// 段 5｜出口：空帧是协议合法输入，bValid 仍为 TRUE / segment 5, exit, an empty frame is a legal protocol input
FC_DL_Crc16Ccitt := uCrc;                      // 输出寄存器值 / publish the register value
bValid := TRUE;                                // 结果可用 / the result is usable
END_FUNCTION
