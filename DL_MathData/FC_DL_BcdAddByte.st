(*==============================================================================
 * 组件名称 : FC_DL_BcdAddByte ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 两位 BCD 字节加法：先解码为二进制求和，和 > 99 置错并饱和
 *            到 99，再编码回 BCD。输入含非法 BCD 半字节时置错并返 0。
 * 契约     : 返回 BCD 和 [两位 BCD 形]；xError = TRUE 表示溢出 / 非法输入，
 *            此时返回 99（溢出饱和）或 0（非法输入）；纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现，不引用库内其他件）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC（*_TO_* 显式转换）
 *            R4 非法 BCD 拒收 + 溢出饱和不回绕 R5 双语注释
 *            R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 BCD 校验与算术族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_BcdAddByte : BYTE
VAR_INPUT
    byA : BYTE;         // BCD 加数 / First BCD addend
    byB : BYTE;         // BCD 被加数 / Second BCD addend
END_VAR
VAR_OUTPUT
    xError : BOOL;      // 置错标志：输入非法或和溢出 / Error flag: invalid input or overflow
END_VAR
VAR
    nA : INT;           // byA 解码二进制值 [0..99] / Binary value decoded from byA
    nB : INT;           // byB 解码二进制值 [0..99] / Binary value decoded from byB
    nS : INT;           // 二进制和 [0..99] / Binary sum
    nTens : INT;        // 十位数字 [0..9] / Tens digit
    nOnes : INT;        // 个位数字 [0..9] / Ones digit
END_VAR
xError := FALSE;                    // 置错标志预清 / Preset error flag cleared
FC_DL_BcdAddByte := 16#00;          // 返回值预置 0 / Preset return 0
IF ((byA AND 16#0F) > 16#09) OR (SHR(byA, 4) > 16#09)
    OR ((byB AND 16#0F) > 16#09) OR (SHR(byB, 4) > 16#09) THEN
    xError := TRUE;                 // 输入含非法 BCD 半字节 / Invalid BCD nibble in input
    RETURN;
END_IF
nA := BYTE_TO_INT(SHR(byA, 4)) * 10 + BYTE_TO_INT(byA AND 16#0F);   // 解码 byA / Decode byA
nB := BYTE_TO_INT(SHR(byB, 4)) * 10 + BYTE_TO_INT(byB AND 16#0F);   // 解码 byB / Decode byB
nS := nA + nB;                      // 二进制求和 / Binary sum
IF nS > 99 THEN
    xError := TRUE;                 // 和溢出两位 BCD 域 / Sum overflows two-digit BCD
    nS := 99;                       // 饱和到 99，不回绕 / Saturate at 99, no wrap
END_IF
nTens := nS / 10;                   // 取十位 / Extract tens digit
nOnes := nS MOD 10;                 // 取个位 / Extract ones digit
FC_DL_BcdAddByte := SHL(INT_TO_BYTE(nTens), 4) OR INT_TO_BYTE(nOnes);   // 编码回 BCD / Encode back to BCD
END_FUNCTION
