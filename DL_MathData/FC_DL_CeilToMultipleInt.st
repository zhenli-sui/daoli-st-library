(*==============================================================================
 * 组件名称 : FC_DL_CeilToMultipleInt ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 整数向上（朝 +∞ 方向）对齐到 nMultiple 的倍数。纯整数算术
 *            实现：整除截取得基准，仅当值大于基准时进位一个倍数；
 *            进位前做 DINT 上限反算防饱和溢出，越限饱和到 2147483647。
 * 契约     : 返回向上对齐结果；nMultiple <= 0 恒返回 0；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 非法倍数返 0 + 上限反算防溢出
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 对齐取整族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_CeilToMultipleInt : DINT
VAR_INPUT
    nValue : DINT;          // 输入整数 / Input integer value
    nMultiple : DINT;       // 对齐倍数，须 > 0 / Alignment multiple, must be > 0
END_VAR
VAR
    nLo : DINT;             // 向零截断的基准倍数值 / Truncated-toward-zero base multiple
END_VAR
IF nMultiple <= 0 THEN
    FC_DL_CeilToMultipleInt := 0;       // 非法倍数返 0 / Invalid multiple returns 0
    RETURN;
END_IF
nLo := (nValue / nMultiple) * nMultiple;    // 整除截取得基准 / Base via integer division truncation
IF nValue > nLo THEN
    IF nLo <= (2147483647 - nMultiple) THEN
        nLo := nLo + nMultiple;             // 向 +∞ 对齐到下一倍数 / Align up to next multiple
    ELSE
        nLo := 2147483647;                  // 进位将溢出，饱和到 DINT 上限 / Saturation at DINT max
    END_IF
END_IF
FC_DL_CeilToMultipleInt := nLo;             // 输出向上对齐结果 / Output ceil-aligned result
END_FUNCTION
