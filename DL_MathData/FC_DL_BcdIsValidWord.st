(*==============================================================================
 * 组件名称 : FC_DL_BcdIsValidWord ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 判定 16 位字是否为合法 4 位 BCD 编码：4 个半字节均须 <= 9
 *            （任一半字节 0x0A..0x0F 非法）。纯位运算 FOR 循环实现，
 *            不用库函数。
 * 契约     : 返回 TRUE = 合法 BCD 字（0000..9999 的 BCD 形）；输入 wVal
 *            任意字；循环轮次固定 4，结构有界；纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 半字节越 9 拒收 + FOR 上界常量
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 BCD 校验与算术族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_BcdIsValidWord : BOOL
VAR_INPUT
    wVal : WORD;        // 待判定 16 位字 / Word to be validated
END_VAR
VAR
    i : INT;            // 半字节序号 0..3 / Nibble index 0..3
END_VAR
FC_DL_BcdIsValidWord := TRUE;       // 预置合法，逐位复核 / Preset valid, recheck nibble by nibble
FOR i := 0 TO 3 DO                  // 4 个半字节逐一校验 / Check all 4 nibbles
    IF (SHR(wVal, i * 4) AND 16#000F) > 16#0009 THEN
        FC_DL_BcdIsValidWord := FALSE;      // 该半字节 > 9：非法 BCD / Nibble > 9: invalid BCD
    END_IF
END_FOR
END_FUNCTION
