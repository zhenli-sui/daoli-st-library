(*==============================================================================
 * 组件名称 : FC_DL_ChkFletcher32 ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : Fletcher-32 校验和 —— 把字节流按 16 位小端字处理，两路累加各取模 65535，
 *            结果 = sum2 × 65536 + sum1。奇数长度时末字节作低字节、高字节补零成字
 *            （与「末字节补零」的通行口径一致）。用于长帧（>512 字节）与文件块校验。
 * 契约     : 返回 32 位结果；nLen 越界钳到 0~16；nLen = 0 返回 0。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: BYTE_TO_UDINT
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 字下标经上界复核（2k ≤ nUse 才取高字节）、
 *            累加上界 65535+65534 < 2^32、取模除数恒为常量 ｜ R5 双语注释
 *            R6 N/A（无状态机）R7 N/A（无定时器/沿实例）R10 标准转换
 *            R11 全声明行分号 R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 小端组装（低字节在前）；大端协议须调用方先换序，本件不做字节序猜测。
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 2/8）
 *============================================================================*)
FUNCTION FC_DL_ChkFletcher32 : UDINT
VAR_INPUT
    aData   : ARRAY[1..16] OF BYTE;     // 待校验字节块，1..16 定长 [字节] / byte block of fixed length [byte]
    nLen    : INT;                      // 有效字节数 0~16，越界钳位 [字节] / effective length from zero to sixteen, clamped [byte]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;                    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;                     // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid  : BOOL;                     // 结果可用标志，空块亦可用 / TRUE even for an empty block
END_VAR
VAR CONSTANT
    DL_LEN_MAX : INT := 16;             // 字节块定长上限 [字节] / fixed block capacity [byte]
    DL_LEN_MIN : INT := 0;              // 长度下界，0 合法 [字节] / lower length bound, zero is legal [byte]
    DL_ONE     : INT := 1;              // 数组首下标 [字节] / first array index [byte]
    DL_TWO     : INT := 2;              // 每字字节数与奇偶判断基数 [字节] / bytes per word and the parity radix [byte]
    DL_MOD16   : UDINT := 65535;        // Fletcher-32 模数 [无量纲] / the Fletcher thirty two modulus
    DL_SCALE   : UDINT := 65536;        // 高半字移位基数 [无量纲] / high word scaling factor
    DL_BYTE_SH : UDINT := 256;          // 字节移位基数 [无量纲] / byte scaling factor
    DL_ZERO_U  : UDINT := 0;            // 无符号零哨兵 / unsigned zero sentinel
END_VAR
VAR
    nSum1   : UDINT;                    // 字累加和 [无量纲] / running word sum
    nSum2   : UDINT;                    // sum1 的累加和 [无量纲] / running sum of the first sum
    nWord   : UDINT;                    // 当前 16 位小端字 [无量纲] / the current little endian word
    nLo     : UDINT;                    // 字内低字节 [无量纲] / low byte of the word
    nHi     : UDINT;                    // 字内高字节，奇数长度时为 0 [无量纲] / high byte, zero on an odd tail
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    nWords  : INT;                      // 字数，奇数长度向上取整 [字] / word count rounded up [word]
    k       : INT;                      // 字游标 [字] / word cursor [word]
    nIdx    : INT;                      // 字内第二个字节的数组下标 [字节] / index of the second byte in the word [byte]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_ChkFletcher32 := DL_ZERO_U;   // 缺省 0 / default zero
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 本件不产生故障级 / this component raises no fault
bValid := TRUE;                     // 空块亦有定义 / an empty block is well defined
nSum1  := DL_ZERO_U;                // 第一路累加器清零 / clear the first accumulator
nSum2  := DL_ZERO_U;                // 第二路累加器清零 / clear the second accumulator

// 段 2｜长度钳位与字数换算：奇数长度向上取整成字 / segment 2, clamp the length and round the word count up
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF
nWords := (nUse + DL_ONE) / DL_TWO; // 向上取整的字数 / the word count rounded up

// 段 3｜逐字累加：低字节在前，奇数尾字节高半补零 / segment 3, word by word with a zero padded tail
FOR k := DL_ONE TO nWords DO
    nLo  := BYTE_TO_UDINT(aData[(DL_TWO * k) - DL_ONE]);    // 低字节，下标必 ≤ nUse / the low byte, its index never exceeds the length
    nHi  := DL_ZERO_U;                                      // 高字节缺省 0，即补零成字 / the high byte defaults to zero, padding the word
    nIdx := DL_TWO * k;                                     // 高字节下标 / the index of the high byte
    IF nIdx <= nUse THEN
        nHi := BYTE_TO_UDINT(aData[nIdx]);                   // 长度允许才取高字节 / take the high byte only when the length allows
    END_IF
    nWord := nLo + (nHi * DL_BYTE_SH);                       // 小端组装 / little endian assembly
    nSum1 := (nSum1 + nWord) MOD DL_MOD16;                   // 字和 / word sum
    nSum2 := (nSum2 + nSum1) MOD DL_MOD16;                   // 字和的累加 / sum of the sums
END_FOR

// 段 4｜出口：高半 sum2、低半 sum1 / segment 4, exit with sum two in the high half
FC_DL_ChkFletcher32 := (nSum2 * DL_SCALE) + nSum1;
END_FUNCTION
