(*==============================================================================
 * 组件名称 : FC_DL_ChkSum32Mod ｜ 子库 : DL_Algo ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 32 位字求和取模校验。字节流按 4 字节小端组装成 32 位字累加，
 *            最后返回 sum MOD 16#FFFF_FFFF。文件块、固件包、大配方块的轻量完整性校验。
 *            实现要点：不先做「四字组装再求和」——那样最多 4×16#FFFF_FFFF 会溢出 UDINT；
 *            改为按字节加权（权 1/256/65536/16777216 循环）并用「减模数」法逐步归一，
 *            nAcc 恒 < 16#FFFF_FFFF，任何一步都不溢出。尾字节不足 4 个即权值循环自然补零。
 * 契约     : 返回 sum MOD 16#FFFF_FFFF（0~16#FFFF_FFFE）；nLen 越界钳到 0~16；nLen = 0 返回 0。
 *            数组定长 ARRAY[1..16] OF BYTE（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: BYTE_TO_UDINT
 * 错误码   : R297 零码位范式：eErr 恒 0，本件结构性不置 bError
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 单项 ≤ 255×2^24 < 模数故累加一次归一即足、
 *            权值乘前先判上界防回绕、NOT 用位反 ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 标准转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 小端组装；「sum MOD 16#FFFF_FFFF」为协议原始口径（不是 2^32 回绕），
 *            两者在第 16#FFFF_FFFF 个字节才分岔，本件按协议原文实现。
 * 修订历史 : 2026-11-24 R79-A 首版（校验和族 6/8）
 *============================================================================*)
FUNCTION FC_DL_ChkSum32Mod : UDINT
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
    DL_MOD_MASK : UDINT := 16#FFFF_FFFF;    // 取模的模数 [无量纲] / the modulus of the protocol
    DL_SHIFT_MAX : UDINT := 16#0100_0000;   // 最高字节权 2^24，再乘 256 会回绕 [无量纲] / the top byte weight, the next step would wrap
    DL_ONE_U    : UDINT := 1;           // 无符号一，权值循环起点 [无量纲] / unsigned one, the first weight
    DL_BYTE_SH  : UDINT := 256;         // 字节权倍数 [无量纲] / weight multiplier per byte
    DL_ZERO_U   : UDINT := 0;           // 无符号零哨兵 / unsigned zero sentinel
END_VAR
VAR
    nAcc    : UDINT;                    // 逐步归一的累加器，恒 < 模数 / the reduced accumulator, always below the modulus
    nTerm   : UDINT;                    // 当前字节的加权项，最大 255×2^24 / the weighted term of one byte
    nShift  : UDINT;                    // 当前字节权 1/256/65536/16777216 循环 [无量纲] / the weight cycling over four bytes
    nUse    : INT;                      // 钳位后的有效长度 [字节] / effective length after clamping [byte]
    i       : INT;                      // 遍历游标 [字节] / loop cursor [byte]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_ChkSum32Mod := DL_ZERO_U;
eErr    := 0;                       // 零码位范式 / zero-code rule
bError  := FALSE;                   // 本件不产生故障级 / this component raises no fault
bValid  := TRUE;                    // 空块亦有定义 / an empty block is well defined
nAcc    := DL_ZERO_U;               // 累加器清零 / clear the accumulator
nShift  := DL_ONE_U;                // 首字节权为 1 / the first byte weighs one

// 段 2｜长度钳位：越界静默整形 / segment 2, clamp the length
nUse := nLen;
IF nUse < DL_LEN_MIN THEN
    nUse := DL_LEN_MIN;             // 下越界钳到 0 / clamp to zero
ELSIF nUse > DL_LEN_MAX THEN
    nUse := DL_LEN_MAX;             // 上越界钳到定长 / clamp to the fixed capacity
END_IF

// 段 3｜逐字节加权并减模数归一：单项必小于模数，故一次减法即够 / segment 3, weighted accumulation with a single reduction
FOR i := DL_ONE TO nUse DO
    nTerm := BYTE_TO_UDINT(aData[i]) * nShift;      // 加权项 ≤ 255×2^24 = 16#FF00_0000，远小于模数 / the term stays well below the modulus
    IF nAcc >= (DL_MOD_MASK - nTerm) THEN
        nAcc := nAcc - (DL_MOD_MASK - nTerm);       // 等价于 nAcc + nTerm − 模数，且不产生中间溢出 / equals the sum minus the modulus
    ELSE
        nAcc := nAcc + nTerm;                       // 未越模数直接加上 / plain accumulation when no reduction is needed
    END_IF
    IF nShift = DL_SHIFT_MAX THEN
        nShift := DL_ONE_U;                         // 第 5 个字节权回到 1，相当于补齐成 4 字节字 / the fifth byte restarts the word
    ELSE
        nShift := nShift * DL_BYTE_SH;              // 乘前已判上界，不会回绕 / the bound was checked, no wrap
    END_IF
END_FOR

// 段 4｜出口：累加器已归一到 [0, 模数) / segment 4, exit with a reduced accumulator
FC_DL_ChkSum32Mod := nAcc;
END_FUNCTION
