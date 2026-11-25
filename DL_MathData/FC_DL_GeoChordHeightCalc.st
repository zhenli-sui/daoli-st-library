(*==============================================================================
 * 组件名称 : FC_DL_GeoChordHeightCalc ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 圆弧弦高（弓高/矢高）h = r − √(r² − (c/2)²)。供圆弧插补弦高误差限、
 *            板材折弯回弹补偿、视觉圆检测圆度评估使用。
 * 契约     : r ≤ 0、c ≤ 0、c > 2r（容差 1.0E-9）、入参非有限 → 返回 0、bError := TRUE、
 *            bValid := FALSE；合法 → 返回 ≥ 0 的弦高、bValid := TRUE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），仅用标准库 SQRT / ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 浮点容差 1.0E-9 + 判别式防负 + 非有限拦截
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : 弦长等于直径时弦高等于半径（半圆），容差带内的 c 略大于 2r 视为合法并按
 *            判别式归零处理；NaN 用自反判（x <> x），Inf 用自减判（x − x 非零）。
 * 修订历史 : 2026-11-24 R79-B 首版（几何族 1/3）
 *============================================================================*)
FUNCTION FC_DL_GeoChordHeightCalc : LREAL
VAR_INPUT
    fRadius : LREAL := 0.0; // 圆弧半径，须 > 0 [mm] / the arc radius, strictly positive
    fChord  : LREAL := 0.0; // 弦长，须 > 0 且 ≤ 2r [mm] / the chord length, positive and at most the diameter
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 定义域非法或入参非有限时为真 / TRUE on an invalid domain or a non finite input
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_ZERO : LREAL := 0.0;      // 实数零哨兵 [mm] / the real zero sentinel
    DL_TWO  : LREAL := 2.0;      // 倍数二，直径与半弦换算 [无量纲] / the factor two used for the diameter and the half chord
    DL_TOL  : LREAL := 1.0E-9;   // 浮点容差（本件唯一比较口径）[无量纲] / the single floating tolerance of this component
END_VAR
VAR
    fHalf  : LREAL; // 半弦长 c/2 [mm] / the half chord length
    fDisc  : LREAL; // 判别式 r² − (c/2)²，防负归零后开方 [mm²] / the discriminant, clamped to zero before the square root
    fDiff  : LREAL; // 非有限检测用的自减量 [无量纲] / the self difference used for the infinity probe
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoChordHeightCalc := DL_ZERO;  // 缺省零 / default zero
eErr   := 0;                          // 零码位范式 / zero-code rule
bError := FALSE;                      // 预置无故障 / preset no fault
bValid := FALSE;                      // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜非有限拦截：NaN 自反判，Inf 自减判（Inf − Inf = NaN 使自减表达式不等自身）/ segment 2, the non finite gate
IF (fRadius <> fRadius) OR (fChord <> fChord) THEN
    bError := TRUE;                   // NaN 入参 / a NaN input
    RETURN;                           // 返回 0 / return the preset zero
END_IF
fDiff := fRadius - fRadius;           // 半径自减 / the radius self difference
IF fDiff <> DL_ZERO THEN
    bError := TRUE;                   // 半径非有限（Inf）/ the radius is not finite
    RETURN;                           // 返回 0 / return the preset zero
END_IF
fDiff := fChord - fChord;             // 弦长自减 / the chord self difference
IF fDiff <> DL_ZERO THEN
    bError := TRUE;                   // 弦长非有限（Inf）/ the chord is not finite
    RETURN;                           // 返回 0 / return the preset zero
END_IF

// 段 3｜定义域闸：r > 0、c > 0、c ≤ 2r + 容差 / segment 3, the domain gates
IF fRadius <= DL_ZERO THEN
    bError := TRUE;                   // 半径非正 / the radius is not positive
    RETURN;                           // 返回 0 / return the preset zero
END_IF
IF fChord <= DL_ZERO THEN
    bError := TRUE;                   // 弦长非正 / the chord is not positive
    RETURN;                           // 返回 0 / return the preset zero
END_IF
IF fChord > ((DL_TWO * fRadius) + DL_TOL) THEN
    bError := TRUE;                   // 弦长超过直径 / the chord exceeds the diameter
    RETURN;                           // 返回 0 / return the preset zero
END_IF

// 段 4｜判别式防负：容差带内 c 略大于 2r 时 r² − (c/2)² 可能为极小负值，归零后开方 / segment 4, the discriminant clamp
fHalf := fChord / DL_TWO;             // 半弦 [mm] / the half chord
fDisc := (fRadius * fRadius) - (fHalf * fHalf);  // 判别式 [mm²] / the discriminant
IF fDisc < DL_ZERO THEN fDisc := DL_ZERO; END_IF  // 防负归零，避免 SQRT 得 NaN / clamp to zero so the square root stays real

// 段 5｜弦高出口 / segment 5, the sagitta
FC_DL_GeoChordHeightCalc := fRadius - SQRT(fDisc);  // h = r − √(r² − (c/2)²) [mm] / the sagitta
bValid := TRUE;                                     // 返回值可用 / the return value is usable
END_FUNCTION
