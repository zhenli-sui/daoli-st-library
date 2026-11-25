(*==============================================================================
 * 组件名称 : FC_DL_ChkTwosCompSum16 ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 16 位字求和二补数校验（two's complement checksum，串口协议常用的
 *            「求和取反加一」帧尾）。字节流按 16 位小端字累加，再取 16#10000 − (sum MOD
 *            16#10000)；结果落在 16#0001~16#FFFF，0 用原码 0 表示（不进位到 16#10000）。
 * 契约     : 返回二补数校验值（0~16#FFFF）；nLen 越界钳到 0~16；nLen = 0 返回 0。
 *            奇数长度时末字节作低字节、高字节补零。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: BYTE_TO_UDINT
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 字下标经上界复核、累加上界 8×65535 不溢出、
 *            补码零特判（16#10000 不可表示） ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 标准转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 小端组装；某些协议口径为「大端字序」或「字节和取补」，对接前须核对协议原文。
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 5/8）
 *============================================================================*)
FUNCTION FC_DL_ChkTwosCompSum16 : UDINT
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
    DL_LEN_MAX  : INT := 16;            // 字节块定长上限 [字节] / fixed block capacity [byte]
    DL_LEN_MIN  : INT := 0;             // 长度下界，0 合法 [字节] / lower length bound, zero is legal [byte]
    DL_ONE      : INT := 1;             // 数组首下标 [字节] / first array index [byte]
    DL_TWO      : INT := 2;             // 每字字节数与奇偶基数 [字节] / bytes per word and the parity radix [byte]
    DL_WORD_MOD : UDINT := 65536;       // 16 位字回绕基数 [无量纲] / the sixteen bit wrap modulus
    DL_BYTE_SH  : UDINT := 256;         // 字节移位基数 [无量纲] / byte scaling factor
    DL_ZERO_U   : UDINT := 0;           // 无符号零哨兵 / unsigned zero sentinel
END_VAR
VAR
    nSum    : UDINT;                    // 字累加和，最大 8×65535 远小于上界 / word sum, at most eight times sixty five thousand
    nWord   : UDINT;                    // 当前 16 位小端字 [无量纲] / the current little endian word
    nLo     : UDINT;                    // 字内低字节 [无量纲] / low byte of the word
    nHi     : UDINT;                    // 字内高字节，奇数长度时为 0 [无量纲] / high byte, zero on an odd tail
    nLow16  : UDINT;                    // 累加和的低 16 位 [无量纲] / the low sixteen bits of the sum
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    nWords  : INT;                      // 字数，奇数长度向上取整 [字] / word count rounded up [word]
    k       : INT;                      // 字游标 [字] / word cursor [word]
    nIdx    : INT;                      // 字内第二个字节的下标 [字节] / index of the second byte in the word [byte]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_ChkTwosCompSum16 := DL_ZERO_U;
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 本件不产生故障级 / this component raises no fault
bValid := TRUE;                     // 空块亦有定义 / an empty block is well defined
nSum   := DL_ZERO_U;                // 累加器清零 / clear the accumulator

// 段 2｜长度钳位与字数换算 / segment 2, clamp the length and round the word count up
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF
nWords := (nUse + DL_ONE) / DL_TWO;

// 段 3｜逐字累加：低字节在前，尾字节高半补零 / segment 3, word by word with a zero padded tail
FOR k := DL_ONE TO nWords DO
    nLo  := BYTE_TO_UDINT(aData[(DL_TWO * k) - DL_ONE]);    // 低字节，下标必 ≤ nUse / the low byte, always inside the block
    nHi  := DL_ZERO_U;                                      // 补零缺省 / padding default
    nIdx := DL_TWO * k;                                     // 高字节下标 / the high byte index
    IF nIdx <= nUse THEN
        nHi := BYTE_TO_UDINT(aData[nIdx]);                   // 长度允许才取 / taken only when the length allows
    END_IF
    nWord := nLo + (nHi * DL_BYTE_SH);                       // 小端组装 / little endian assembly
    nSum  := nSum + nWord;                                   // 宽域累加，无回绕 / wide accumulation without wrap
END_FOR

// 段 4｜二补数：低 16 位取反加一；为 0 时用原码 0 表示 / segment 4, the two's complement
nLow16 := nSum MOD DL_WORD_MOD;         // 低 16 位 / the low sixteen bits
IF nLow16 = DL_ZERO_U THEN
    FC_DL_ChkTwosCompSum16 := DL_ZERO_U;    // 补码会得 16#10000，不可表示，用 0 表示 / the complement would be sixteen to the fourth, use zero
ELSE
    FC_DL_ChkTwosCompSum16 := DL_WORD_MOD - nLow16;
END_IF
END_FUNCTION
