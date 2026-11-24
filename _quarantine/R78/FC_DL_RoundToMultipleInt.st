(*==============================================================================
 * 组件名称 : FC_DL_RoundToMultipleInt ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 整数四舍五入到 nMultiple 的最近倍数（半值远离零舍入，
 *            Round Half Away From Zero）。纯整数算术实现，先向零截断得
 *            基准倍数，再按"余量是否过半"进位 / 退位，无浮点精度损失。
 * 契约     : 返回四舍五入后的倍数值；nMultiple <= 0 恒返回 0；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 非法倍数返 0 + 比较用 nHalf
 *            避免 nRem*2 溢出 R5 双语注释 R6 N/A（无状态机） R7 N/A
 * 修订历史 : 2026-11-23 R78-B1 对齐取整族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_RoundToMultipleInt : DINT
VAR_INPUT
    nValue : DINT;          // 输入整数 / Input integer value
    nMultiple : DINT;       // 对齐倍数，须 > 0 / Alignment multiple, must be > 0
END_VAR
VAR
    nLo : DINT;             // 向零截断的基准倍数值 / Truncated-toward-zero base multiple
    nRem : DINT;            // 余量，符号随被除数，绝对值 < nMultiple / Remainder, |nRem| < nMultiple
    nHalf : DINT;           // 倍数半值（向下取整） / Floor half of the multiple
END_VAR
IF nMultiple <= 0 THEN
    FC_DL_RoundToMultipleInt := 0;      // 非法倍数返 0 / Invalid multiple returns 0
    RETURN;
END_IF
nLo := (nValue / nMultiple) * nMultiple;    // 整除截取得基准 / Base via integer division truncation
nRem := nValue - nLo;                       // 余量 / Remainder in (-nMultiple, nMultiple)
nHalf := nMultiple / 2;                     // 半值基准，免 nRem*2 溢出 / Half reference avoids nRem*2 overflow
IF nRem >= 0 THEN
    IF (nRem > nHalf) OR ((nRem = nHalf) AND ((nMultiple MOD 2) = 0)) THEN
        nLo := nLo + nMultiple;             // 正余量过半进位 / Round up at half
    END_IF
ELSIF (-nRem > nHalf) OR ((-nRem = nHalf) AND ((nMultiple MOD 2) = 0)) THEN
    nLo := nLo - nMultiple;                 // 负余量过半退位 / Round down at half
END_IF
FC_DL_RoundToMultipleInt := nLo;            // 输出四舍五入结果 / Output rounded result
END_FUNCTION
