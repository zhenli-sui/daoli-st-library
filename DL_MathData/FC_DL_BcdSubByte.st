(*==============================================================================
 * 组件名称 : FC_DL_BcdSubByte ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 两位 BCD 字节减法：先解码为二进制求差，差 < 0（借位下溢）
 *            置错并饱和到 0，再编码回 BCD。输入含非法 BCD 半字节时置错
 *            并返 0。
 * 契约     : 返回 BCD 差 [两位 BCD 形]；xError = TRUE 表示下溢 / 非法输入，
 *            此时返回 0（下溢饱和）；纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现，不引用库内其他件）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC（*_TO_* 显式转换）
 *            R4 非法 BCD 拒收 + 下溢饱和不回绕 R5 双语注释
 *            R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 BCD 校验与算术族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_BcdSubByte : BYTE
VAR_INPUT
    byA : BYTE;         // BCD 被减数 / BCD minuend
    byB : BYTE;         // BCD 减数 / BCD subtrahend
END_VAR
VAR_OUTPUT
    xError : BOOL;      // 置错标志：输入非法或借位下溢 / Error flag: invalid input or borrow underflow
END_VAR
VAR
    nA : INT;           // byA 解码二进制值 [0..99] / Binary value decoded from byA
    nB : INT;           // byB 解码二进制值 [0..99] / Binary value decoded from byB
    nD : INT;           // 二进制差 [0..99] / Binary difference
    nTens : INT;        // 十位数字 [0..9] / Tens digit
    nOnes : INT;        // 个位数字 [0..9] / Ones digit
END_VAR
xError := FALSE;                    // 置错标志预清 / Preset error flag cleared
FC_DL_BcdSubByte := 16#00;          // 返回值预置 0 / Preset return 0
IF ((byA AND 16#0F) > 16#09) OR (SHR(byA, 4) > 16#09)
    OR ((byB AND 16#0F) > 16#09) OR (SHR(byB, 4) > 16#09) THEN
    xError := TRUE;                 // 输入含非法 BCD 半字节 / Invalid BCD nibble in input
    RETURN;
END_IF
nA := BYTE_TO_INT(SHR(byA, 4)) * 10 + BYTE_TO_INT(byA AND 16#0F);   // 解码 byA / Decode byA
nB := BYTE_TO_INT(SHR(byB, 4)) * 10 + BYTE_TO_INT(byB AND 16#0F);   // 解码 byB / Decode byB
nD := nA - nB;                      // 二进制求差 / Binary difference
IF nD < 0 THEN
    xError := TRUE;                 // 借位下溢出两位 BCD 域 / Borrow underflow
    nD := 0;                        // 饱和到 0，不回绕 / Saturate at 0, no wrap
END_IF
nTens := nD / 10;                   // 取十位 / Extract tens digit
nOnes := nD MOD 10;                 // 取个位 / Extract ones digit
FC_DL_BcdSubByte := SHL(INT_TO_BYTE(nTens), 4) OR INT_TO_BYTE(nOnes);   // 编码回 BCD / Encode back to BCD
END_FUNCTION
