(*==============================================================================
 * 组件名称 : FC_DL_BcdIsValidByte ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 判定字节是否为合法两位 BCD 编码：高 / 低半字节均须 <= 9
 *            （0x0A..0x0F 非法）。纯位运算实现，不用库函数。
 * 契约     : 返回 TRUE = 合法 BCD 字节（00..99 的 BCD 形）；输入 byVal
 *            任意字节；纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 半字节越 9 拒收
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 BCD 校验与算术族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_BcdIsValidByte : BOOL
VAR_INPUT
    byVal : BYTE;       // 待判定字节 / Byte to be validated
END_VAR
IF ((byVal AND 16#0F) > 16#09) OR (SHR(byVal, 4) > 16#09) THEN
    FC_DL_BcdIsValidByte := FALSE;      // 任一半字节 > 9：非法 BCD / Any nibble > 9: invalid BCD
ELSE
    FC_DL_BcdIsValidByte := TRUE;       // 高低半字节均 <= 9：合法 / Both nibbles <= 9: valid
END_IF
END_FUNCTION
