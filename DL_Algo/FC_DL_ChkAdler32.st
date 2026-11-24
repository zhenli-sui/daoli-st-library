(*==============================================================================
 * 组件名称 : FC_DL_ChkAdler32 ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : Adler-32 校验和（zlib / PNG 同源算法）。A 初值 1、B 初值 0，
 *            每字节 A = (A + byte) MOD 65521、B = (B + A) MOD 65521，
 *            结果 = B × 65536 + A。比 CRC 快而强度略低，适合大配方包与日志块校验。
 * 契约     : 返回 B × 65536 + A（高 16 位 B、低 16 位 A）；nLen 越界钳到 0~16；
 *            nLen = 0 时返回 1（A = 1、B = 0，空串的标准 Adler-32 值）。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: BYTE_TO_UDINT
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 两路累加各步取模（A<65521、B<65521），
 *            和的上界 131040 远小于 UDINT、长度先钳位后进循环 ｜ R5 双语注释
 *            R6 N/A（无状态机）R7 N/A（无定时器/沿实例）R10 标准转换
 *            R11 全声明行分号 R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 模数 65521 为小于 2^16 的最大素数（Adler 原文口径），不可换成 65535。
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 8/8）
 *============================================================================*)
FUNCTION FC_DL_ChkAdler32 : UDINT
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
    DL_MOD65521 : UDINT := 65521;       // Adler 模数，小于 2^16 的最大素数 / the Adler modulus
    DL_SUM_INIT : UDINT := 1;           // A 的初值 / the initial value of the first sum
    DL_SCALE    : UDINT := 65536;       // B 的移位基数 [无量纲] / scaling factor of the second sum
    DL_ZERO_U   : UDINT := 0;           // 无符号零哨兵 / unsigned zero sentinel
END_VAR
VAR
    nSumA   : UDINT;                    // 低半累加 A，恒 < 65521 / the low half accumulator, always below the modulus
    nSumB   : UDINT;                    // 高半累加 B，恒 < 65521 / the high half accumulator, always below the modulus
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    i       : INT;                      // 遍历游标 [字节] / loop cursor [byte]
END_VAR

// 段 1｜出口预置：空串的标准值为 1 / segment 1, preset the exit with the empty stream value
FC_DL_ChkAdler32 := DL_SUM_INIT;    // 缺省 1（A=1、B=0）/ default one, that is A=1 and B=0
eErr    := 0;                       // 零码位范式 / zero-code rule
bError  := FALSE;                   // 本件不产生故障级 / this component raises no fault
bValid  := TRUE;                    // 空块亦有定义 / an empty block is well defined
nSumA   := DL_SUM_INIT;             // A 初值 1 / the first sum starts at one
nSumB   := DL_ZERO_U;               // B 初值 0 / the second sum starts at zero

// 段 2｜长度钳位：越界静默整形 / segment 2, clamp the length
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF

// 段 3｜两路累加：每步取模 65521，累加值恒 < 131042 不溢出 / segment 3, the two accumulators
FOR i := DL_ONE TO nUse DO
    nSumA := (nSumA + BYTE_TO_UDINT(aData[i])) MOD DL_MOD65521;     // A 累加 / accumulate the first sum
    nSumB := (nSumB + nSumA) MOD DL_MOD65521;                       // B 累加 A / accumulate the second sum over the first
END_FOR

// 段 4｜出口：B 在高半、A 在低半 / segment 4, exit with B in the high half
FC_DL_ChkAdler32 := (nSumB * DL_SCALE) + nSumA;
END_FUNCTION
