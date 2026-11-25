(*==============================================================================
 * 组件名称 : FC_DL_GeoPointInRectXY ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 点是否落在轴对齐矩形内（含边界，容差 1.0E-9）。矩形以任意两个对角顶点给出，
 *            宽或高为负时自动换序归一 —— 现场示教常把左上与右下顺序录反，
 *            本件保证录入顺序不影响判定。
 * 契约     : 在内返回 TRUE；任一点含非有限值或矩形退化（宽高均小于容差）时返回 FALSE、
 *            bError := TRUE。边界点按「含」处理（外扩容差）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS / MIN / MAX
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 NaN 自反判据、浮点无等号判等（全部走容差窗口）
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 矩形必须轴对齐；旋转框请改用 FC_DL_GeoPointInConvexQuadXY（四边形叉积法）。
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 3/8）
 *============================================================================*)
FUNCTION FC_DL_GeoPointInRectXY : BOOL
VAR_INPUT
    fPx     : LREAL;    // 被测点 X 坐标 [mm] / X coordinate of the measured point [mm]
    fPy     : LREAL;    // 被测点 Y 坐标 [mm] / Y coordinate of the measured point [mm]
    fX1     : LREAL;    // 对角顶点一 X，可为大值或小值 [mm] / X of the first corner, may be the larger one [mm]
    fY1     : LREAL;    // 对角顶点一 Y，可为大值或小值 [mm] / Y of the first corner, may be the larger one [mm]
    fX2     : LREAL;    // 对角顶点二 X，可与顶点一顺序任意 [mm] / X of the second corner, order free [mm]
    fY2     : LREAL;    // 对角顶点二 Y，可与顶点一顺序任意 [mm] / Y of the second corner, order free [mm]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 非有限输入或矩形退化为真 / TRUE on non finite inputs or a degenerate rectangle
    bValid  : BOOL;     // 判定可用标志 / TRUE when the verdict is usable
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-9;      // 边界容差，边界点按「在内」处理 [mm] / boundary tolerance, edge points count as inside [mm]
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界 [mm] / finiteness ceiling [mm]
END_VAR
VAR
    fMinX   : LREAL;    // 归一后的 X 下界 [mm] / normalised lower X bound [mm]
    fMaxX   : LREAL;    // 归一后的 X 上界 [mm] / normalised upper X bound [mm]
    fMinY   : LREAL;    // 归一后的 Y 下界 [mm] / normalised lower Y bound [mm]
    fMaxY   : LREAL;    // 归一后的 Y 上界 [mm] / normalised upper Y bound [mm]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoPointInRectXY := FALSE;    // 缺省不在矩形内 / default outside
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 判定完成前不可用 / unusable until the verdict ends

// 段 2｜非有限闸与量级闸：六个坐标任一为 NaN 或超上界即拒 / segment 2, the non finite and magnitude gates
IF (fPx <> fPx) OR (fPy <> fPy) OR (fX1 <> fX1) OR (fY1 <> fY1) OR (fX2 <> fX2) OR (fY2 <> fY2) THEN
    bError := TRUE;                 // 含非数输入 / a not a number input was seen
    RETURN;
END_IF
IF (ABS(fPx) > DL_FIN_LIM) OR (ABS(fPy) > DL_FIN_LIM) OR (ABS(fX1) > DL_FIN_LIM) OR (ABS(fY1) > DL_FIN_LIM) OR (ABS(fX2) > DL_FIN_LIM) OR (ABS(fY2) > DL_FIN_LIM) THEN
    bError := TRUE;                 // 量级非有限 / the magnitude is not finite
    RETURN;
END_IF

// 段 3｜对角顶点归一：宽高为负说明录入顺序相反，交换即可 / segment 3, normalise the two corners
fMinX := MIN(fX1, fX2);             // X 下界 / lower X bound
fMaxX := MAX(fX1, fX2);             // X 上界 / upper X bound
fMinY := MIN(fY1, fY2);             // Y 下界 / lower Y bound
fMaxY := MAX(fY1, fY2);             // Y 上界 / upper Y bound
IF ((fMaxX - fMinX) < DL_EPS) AND ((fMaxY - fMinY) < DL_EPS) THEN
    bError := TRUE;                 // 两顶点重合，矩形退化 / the corners coincide and the rectangle degenerates
    RETURN;
END_IF

// 段 4｜四点窗口判定：全走容差窗口，不使用等号 / segment 4, the four sided tolerance window
IF ((fPx > (fMinX - DL_EPS)) AND (fPx < (fMaxX + DL_EPS))) AND ((fPy > (fMinY - DL_EPS)) AND (fPy < (fMaxY + DL_EPS))) THEN
    FC_DL_GeoPointInRectXY := TRUE; // 落在矩形内（含边界） / inside the rectangle, edges included
END_IF
bValid := TRUE;                     // 判定可用 / the verdict is usable
END_FUNCTION
