(*==============================================================================
 * 组件名称 : FC_DL_RoundToMultipleReal ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 实数四舍五入到 fMultiple 的最近倍数。先除到倍数域，经标准
 *            就近舍入型转换 REAL_TO_DINT 取最近整倍数序号，再映射回倍数域。
 * 契约     : 返回四舍五入后的倍数值 [fMultiple 单位]；fMultiple <= 0 或
 *            输入 NaN/Inf 恒返回 0.0；商超出 DINT 安全域时按原值近直返；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC（*_TO_* 显式转换）R4 非法倍数/
 *            NaN/Inf 返 0 + 商域闸防 REAL_TO_DINT 溢出 R5 双语注释
 *            R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 对齐取整族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_RoundToMultipleReal : REAL
VAR_INPUT
    fValue : REAL;          // 输入实数 / Input real value
    fMultiple : REAL;       // 对齐倍数，须 > 0 / Multiple, must be > 0
END_VAR
VAR
    fQ : REAL;              // 倍数域商 / Ratio in multiple domain
    nQ : DINT;              // 最近整倍数序号 / Nearest multiple index
END_VAR
VAR CONSTANT
    DL_Q_SAFE_MAX : REAL := 2.0E9;      // DINT 安全商上限，防转换溢出 / Safe ratio cap guarding conversion overflow
END_VAR
IF (fMultiple <= 0.0) OR (fValue <> fValue) OR ((fValue - fValue) <> 0.0) THEN
    FC_DL_RoundToMultipleReal := 0.0;   // 非法倍数或 NaN/Inf 输入返 0 / Invalid multiple or NaN/Inf returns 0
    RETURN;
END_IF
fQ := fValue / fMultiple;                           // 商 / Ratio
IF (fQ <> fQ) OR ((fQ - fQ) <> 0.0) OR (fQ > DL_Q_SAFE_MAX) OR (fQ < -DL_Q_SAFE_MAX) THEN
    FC_DL_RoundToMultipleReal := fQ * fMultiple;    // 商 NaN/Inf/超域按原值近直返 / NaN/Inf/out-of-domain ratio returns near-original
    RETURN;
END_IF
nQ := REAL_TO_DINT(fQ);                             // 最近邻取整（IEC 实转整为就近舍入）/ Round to nearest via typed conversion
FC_DL_RoundToMultipleReal := DINT_TO_REAL(nQ) * fMultiple;      // 映射回倍数域 / Map back to multiple domain
END_FUNCTION
