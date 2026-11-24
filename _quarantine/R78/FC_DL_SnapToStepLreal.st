(*==============================================================================
 * 组件名称 : FC_DL_SnapToStepLreal ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : LREAL 吸附到 fStep 步距网格的最近格点。双精度版量化件：
 *            先除到步距域，经标准就近舍入型转换 LREAL_TO_LINT 取最近
 *            格点序号（64 位序号域），再映射回步距域。
 * 契约     : 返回吸附后的网格值 [fStep 单位]；fStep <= 0 或输入 NaN 恒
 *            返回 0.0；商为 Inf 或超出 LINT 安全域时按原值近直返；
 *            纯函数无状态、同输入同输出。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC（*_TO_* 显式转换）R4 非法步距/
 *            NaN 返 0 + 商域闸防转换溢出 R5 双语注释
 *            R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 对齐取整族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_SnapToStepLreal : LREAL
VAR_INPUT
    fValue : LREAL;         // 输入双精度实数 / Input LREAL value
    fStep : LREAL;          // 量化步距，须 > 0 / Quantization step, must be > 0
END_VAR
VAR
    fQ : LREAL;             // 步距域商 / Ratio in step domain
    nQ : LINT;              // 最近格点序号（64 位域） / Nearest grid index (64-bit domain)
END_VAR
VAR CONSTANT
    DL_Q_SAFE_MAX : LREAL := 9.0E18;    // LINT 安全商上限，防转换溢出 / Safe ratio cap guarding conversion overflow
END_VAR
IF (fStep <= 0.0) OR (fValue <> fValue) OR ((fValue - fValue) <> 0.0) THEN
    FC_DL_SnapToStepLreal := 0.0;       // 非法步距或 NaN 输入返 0 / Invalid step or NaN returns 0
    RETURN;
END_IF
fQ := fValue / fStep;                           // 商 / Ratio
IF (fQ <> fQ) OR ((fQ - fQ) <> 0.0) OR (fQ > DL_Q_SAFE_MAX) OR (fQ < -DL_Q_SAFE_MAX) THEN
    FC_DL_SnapToStepLreal := fQ * fStep;        // 商 NaN/Inf/超域按原值近直返 / NaN/Inf/out-of-domain ratio returns near-original
    RETURN;
END_IF
nQ := LREAL_TO_LINT(fQ);                        // 最近邻取整（IEC 实转整为就近舍入）/ Round to nearest via typed conversion
FC_DL_SnapToStepLreal := LINT_TO_LREAL(nQ) * fStep;     // 映射回步距域 / Map back to step domain
END_FUNCTION
