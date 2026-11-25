(*==============================================================================
 * 组件名称 : FC_DL_BcdIncrementByte ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : BCD 字节加 1（如计数器 / 计数值递增）：99 进位回 0。
 *            输入含非法 BCD 半字节时防御性返回 0。
 * 契约     : 返回 BCD 加 1 结果 [两位 BCD 形]；非法输入返回 0；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现，不引用库内其他件）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC（*_TO_* 显式转换）
 *            R4 非法 BCD 返 0 + 99 进位回 0 不越域 R5 双语注释
 *            R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 BCD 校验与算术族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_BcdIncrementByte : BYTE
VAR_INPUT
    byVal : BYTE;       // 待递增 BCD 字节 / BCD byte to be incremented
END_VAR
VAR
    nV : INT;           // 解码二进制值 [0..99] / Decoded binary value
    nTens : INT;        // 十位数字 [0..9] / Tens digit
    nOnes : INT;        // 个位数字 [0..9] / Ones digit
END_VAR
FC_DL_BcdIncrementByte := 16#00;    // 返回值预置 0 / Preset return 0
IF ((byVal AND 16#0F) > 16#09) OR (SHR(byVal, 4) > 16#09) THEN
    RETURN;                         // 非法 BCD 输入防御性返 0 / Invalid BCD input returns 0
END_IF
nV := BYTE_TO_INT(SHR(byVal, 4)) * 10 + BYTE_TO_INT(byVal AND 16#0F);   // 解码 / Decode
nV := nV + 1;                       // 二进制加 1 / Increment in binary
IF nV > 99 THEN
    nV := 0;                        // 99 进位回 0 / Carry 99 back to 0
END_IF
nTens := nV / 10;                   // 取十位 / Extract tens digit
nOnes := nV MOD 10;                 // 取个位 / Extract ones digit
FC_DL_BcdIncrementByte := SHL(INT_TO_BYTE(nTens), 4) OR INT_TO_BYTE(nOnes);     // 编码回 BCD / Encode back to BCD
END_FUNCTION
