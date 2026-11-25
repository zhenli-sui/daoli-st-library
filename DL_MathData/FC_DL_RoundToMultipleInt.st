(*==============================================================================
 * 组件名称 : FC_DL_RoundToMultipleInt ｜ 子库 : DL_MathData ｜ v1.0.1 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 整数四舍五入到 nMultiple 的最近倍数（半值远离零舍入，
 *            Round Half Away From Zero）。纯整数算术实现，先向零截断得
 *            基准倍数，再按"余量是否过半"进位 / 退位，无浮点精度损失。
 * 契约     : 返回四舍五入后的倍数值；nMultiple <= 0 恒返回 0 并置 bError；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 修订历史 :
 *        2026-11-23  v1.0.0  R78-B1 对齐取整族模板派生首版
 *        2026-11-24  v1.0.1  R79-F1 修 DINT 回绕（R78 闸 L1 阻断项）：
 *                    ① 进位侧 nLo + nMultiple 在 nLo 接近 DINT_MAX 时溢出回绕成负数
 *                       （例：nValue=DINT_MAX-1, nMultiple=4 → 结果变负）；
 *                    ② 退位侧 nLo - nMultiple 在 nLo 接近 DINT_MIN 时同理溢出。
 *                    修法：加显式上/下饱和闸 —— 进位前判 nLo > DINT_MAX - nMultiple，
 *                    退位前判 nLo < DINT_MIN + nMultiple，命中即钳到域端点并置
 *                    bSat := TRUE（饱和出口），不再做算术进位 / 退位。
 *                    该闸使"整数域内不可表示的四舍五入结果"饱和而非回绕，符合安全侧
 *                    优先（宁可饱和到端点让上位机看见 bSat，不可回绕成反向大数）。
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 非法倍数返 0 + 比较用 nHalf
 *            避免 nRem*2 溢出 + 上/下饱和闸防 nLo±nMultiple 回绕 (v1.0.1)
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A R10 无构造式转换
 *============================================================================*)
FUNCTION FC_DL_RoundToMultipleInt : DINT
VAR_INPUT
    nValue : DINT;          // 输入整数 / Input integer value
    nMultiple : DINT;       // 对齐倍数，须 > 0 / Alignment multiple, must be > 0
END_VAR
VAR_OUTPUT
    bSat : BOOL;            // 结果已饱和到 DINT 域端点（未真四舍五入）/ Result saturated at the DINT domain end
    bError : BOOL;          // 倍数非法（<= 0）/ Invalid multiple (<= 0)
END_VAR
VAR
    nLo : DINT;             // 向零截断的基准倍数值 / Truncated-toward-zero base multiple
    nRem : DINT;            // 余量，符号随被除数，绝对值 < nMultiple / Remainder, |nRem| < nMultiple
    nHalf : DINT;           // 倍数半值（向下取整） / Floor half of the multiple
END_VAR
VAR CONSTANT
    DL_RMI_MAX : DINT := 2147483647;    // DINT 上端 / Upper end of DINT
    DL_RMI_MIN : DINT := -2147483648;   // DINT 下端 / Lower end of DINT
END_VAR
bSat := FALSE;                          // 饱和标志每调用先清 / Clear the saturation flag every call
bError := FALSE;                        // 错误标志每调用先清 / Clear the error flag every call
IF nMultiple <= 0 THEN
    bError := TRUE;                     // 倍数非法回执 / Invalid multiple receipt
    FC_DL_RoundToMultipleInt := 0;      // 非法倍数返 0 / Invalid multiple returns 0
    RETURN;
END_IF
nLo := (nValue / nMultiple) * nMultiple;    // 整除截取得基准 / Base via integer division truncation
nRem := nValue - nLo;                       // 余量 / Remainder in (-nMultiple, nMultiple)
nHalf := nMultiple / 2;                     // 半值基准，免 nRem*2 溢出 / Half reference avoids nRem*2 overflow
IF nRem >= 0 THEN
    IF (nRem > nHalf) OR ((nRem = nHalf) AND ((nMultiple MOD 2) = 0)) THEN
        IF nLo > (DL_RMI_MAX - nMultiple) THEN
            nLo := DL_RMI_MAX;              // 进位将溢出 → 饱和到上端 / Round up would overflow, saturate high
            bSat := TRUE;                   // 置饱和标志 / Raise the saturation flag
        ELSE
            nLo := nLo + nMultiple;         // 正余量过半进位 / Round up at half
        END_IF
    END_IF
ELSIF (-nRem > nHalf) OR ((-nRem = nHalf) AND ((nMultiple MOD 2) = 0)) THEN
    IF nLo < (DL_RMI_MIN + nMultiple) THEN
        nLo := DL_RMI_MIN;                  // 退位将溢出 → 饱和到下端 / Round down would overflow, saturate low
        bSat := TRUE;                       // 置饱和标志 / Raise the saturation flag
    ELSE
        nLo := nLo - nMultiple;             // 负余量过半退位 / Round down at half
    END_IF
END_IF
FC_DL_RoundToMultipleInt := nLo;            // 输出四舍五入结果 / Output rounded result
END_FUNCTION
