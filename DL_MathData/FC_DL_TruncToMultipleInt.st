(*==============================================================================
 * 组件名称 : FC_DL_TruncToMultipleInt ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 整数向零截断到 nMultiple 的倍数（丢弃不足一个倍数的余量，
 *            符号随被除数）。纯整数算术实现：整除（ST 中 DIV 对整数
 *            向零截断）后回乘，即得截断对齐结果。
 * 契约     : 返回向零截断结果；nMultiple <= 0 恒返回 0；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 非法倍数返 0（防除零）
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 对齐取整族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_TruncToMultipleInt : DINT
VAR_INPUT
    nValue : DINT;          // 输入整数 / Input integer value
    nMultiple : DINT;       // 对齐倍数，须 > 0 / Alignment multiple, must be > 0
END_VAR
IF nMultiple <= 0 THEN
    FC_DL_TruncToMultipleInt := 0;      // 非法倍数返 0 / Invalid multiple returns 0
    RETURN;
END_IF
FC_DL_TruncToMultipleInt := (nValue / nMultiple) * nMultiple;   // 整除截断回乘 / Truncate by integer division and remultiply
END_FUNCTION
