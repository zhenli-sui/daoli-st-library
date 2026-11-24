(*==============================================================================
 * 组件名称 : FC_DL_ChkFletcher16 ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 标准 Fletcher-16 校验和。两路累加：sum1 逐字节累加、sum2 累加 sum1，
 *            二者每步各取模 255，结果 = sum2 × 256 + sum1。相比简单字节和，
 *            Fletcher 对字节换位与丢字节敏感，适合串口帧、条码回读、配方块校验。
 * 契约     : 返回 32 位结果（高 16 位 sum2、低 16 位 sum1，各 < 255）；
 *            nLen 越界钳到 0~16（钳位不报错，属输入整形）；nLen = 0 返回 0。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: BYTE_TO_UDINT
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 长度先钳位后进循环、取模除数恒为常量 255、
 *            累加上界 255+254 不溢出 ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 标准转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 模数取 255（Fletcher 原始口径，非 256）；与某些实现的 255 vs 256 差异
 *            会导致校验不一致，对接第三方协议前须核对其模数口径。
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 1/8）
 *============================================================================*)
FUNCTION FC_DL_ChkFletcher16 : UDINT
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
    DL_MOD255  : UDINT := 255;          // Fletcher 模数 [无量纲] / the Fletcher modulus
    DL_SCALE   : UDINT := 256;          // 高字节移位基数 [无量纲] / high byte scaling factor
    DL_ZERO_U  : UDINT := 0;            // 无符号零哨兵 / unsigned zero sentinel
END_VAR
VAR
    nSum1   : UDINT;                    // 字节累加和 [无量纲] / running byte sum
    nSum2   : UDINT;                    // sum1 的累加和 [无量纲] / running sum of the first sum
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    i       : INT;                      // 遍历游标 [字节] / loop cursor [byte]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_ChkFletcher16 := DL_ZERO_U;   // 缺省 0 / default zero
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 本件不产生故障级 / this component raises no fault
bValid := TRUE;                     // 空块亦有定义，结果恒可用 / an empty block is well defined
nSum1  := DL_ZERO_U;                // 第一路累加器清零 / clear the first accumulator
nSum2  := DL_ZERO_U;                // 第二路累加器清零 / clear the second accumulator

// 段 2｜长度钳位：越界静默整形，不进故障态 / segment 2, clamp the length
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF

// 段 3｜两路累加：每步取模 255，累加值恒 < 255 故不会溢出 / segment 3, the two accumulators
FOR i := DL_ONE TO nUse DO
    nSum1 := (nSum1 + BYTE_TO_UDINT(aData[i])) MOD DL_MOD255;   // 字节和 / byte sum
    nSum2 := (nSum2 + nSum1) MOD DL_MOD255;                     // 字节和的累加 / sum of the sums
END_FOR

// 段 4｜出口：高半 sum2、低半 sum1 / segment 4, exit with sum two in the high half
FC_DL_ChkFletcher16 := (nSum2 * DL_SCALE) + nSum1;
END_FUNCTION
