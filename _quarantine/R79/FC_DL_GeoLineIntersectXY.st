(*==============================================================================
 * 组件名称 : FC_DL_GeoLineIntersectXY ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 两线段求交点（参数式）。以行列式解出 t、u 两个线段参数，二者都落在 [0,1]
 *            才认为线段真实相交。用于视觉十字标定、激光对刀、两轴限位线交叉判定。
 * 契约     : 相交返回 TRUE 并写出 fX / fY；平行（|denom| < 1.0E-9）返回 FALSE 且
 *            bError := TRUE（几何病态）；共面但交点落在线段延长线上返回 FALSE 且
 *            bError := FALSE（正常无交点，不得当故障上报）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除法前判 |denom| 容差、NaN 自反判据、
 *            无穷上界 ｜ R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 参数域容差取 1.0E-9，端点恰好落在对方端点上的情形判为相交（含边界）。
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 2/8）
 *============================================================================*)
FUNCTION FC_DL_GeoLineIntersectXY : BOOL
VAR_INPUT
    fAx     : LREAL;    // 线段一 起点 X [mm] / start X of the first segment [mm]
    fAy     : LREAL;    // 线段一 起点 Y [mm] / start Y of the first segment [mm]
    fBx     : LREAL;    // 线段一 终点 X [mm] / end X of the first segment [mm]
    fBy     : LREAL;    // 线段一 终点 Y [mm] / end Y of the first segment [mm]
    fCx     : LREAL;    // 线段二 起点 X [mm] / start X of the second segment [mm]
    fCy     : LREAL;    // 线段二 起点 Y [mm] / start Y of the second segment [mm]
    fDx     : LREAL;    // 线段二 终点 X [mm] / end X of the second segment [mm]
    fDy     : LREAL;    // 线段二 终点 Y [mm] / end Y of the second segment [mm]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 平行或非有限输入为真 / TRUE on parallel lines or non finite inputs
    bValid  : BOOL;     // 交点可用标志 / TRUE when the intersection point is usable
    fX      : LREAL;    // 交点 X 坐标，无交点时 0 [mm] / intersection X, zero when there is none [mm]
    fY      : LREAL;    // 交点 Y 坐标，无交点时 0 [mm] / intersection Y, zero when there is none [mm]
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-9;      // 行列式容差，小于它判为平行 [无量纲] / determinant tolerance, below it the lines are parallel
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界 [无量纲] / finiteness ceiling
    DL_ONE      : LREAL := 1.0;         // 参数域上界 / upper bound of the segment parameter
    DL_ZERO_L   : LREAL := 0.0;         // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    fD1x    : LREAL;    // 线段一方向 X 分量 B−A [mm] / direction X of the first segment [mm]
    fD1y    : LREAL;    // 线段一方向 Y 分量 B−A [mm] / direction Y of the first segment [mm]
    fD2x    : LREAL;    // 线段二方向 X 分量 D−C [mm] / direction X of the second segment [mm]
    fD2y    : LREAL;    // 线段二方向 Y 分量 D−C [mm] / direction Y of the second segment [mm]
    fDen    : LREAL;    // 两方向叉积（行列式）[mm²] / cross product of the two directions [mm²]
    fT      : LREAL;    // 线段一上的参数 [无量纲] / parameter along the first segment
    fU      : LREAL;    // 线段二上的参数 [无量纲] / parameter along the second segment
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoLineIntersectXY := FALSE;  // 缺省无交点 / default no intersection
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 求解完成前不认交点 / the point is unusable until the solve ends
fX     := DL_ZERO_L;                // X 清零 / clear X
fY     := DL_ZERO_L;                // Y 清零 / clear Y

// 段 2｜非有限闸：八个坐标任一为 NaN 即拒 / segment 2, the non finite gate
IF (fAx <> fAx) OR (fAy <> fAy) OR (fBx <> fBx) OR (fBy <> fBy) OR (fCx <> fCx) OR (fCy <> fCy) OR (fDx <> fDx) OR (fDy <> fDy) THEN
    bError := TRUE;                 // 含非数输入 / a not a number input was seen
    RETURN;
END_IF

// 段 3｜方向与行列式：denom 为 0 即两线平行或重合 / segment 3, directions and the determinant
fD1x := fBx - fAx;
fD1y := fBy - fAy;
fD2x := fDx - fCx;
fD2y := fDy - fCy;
fDen := (fD1x * fD2y) - (fD1y * fD2x);     // 行列式 / the determinant
IF (fDen <> fDen) OR (ABS(fDen) > DL_FIN_LIM) THEN
    bError := TRUE;                 // 行列式非有限 / the determinant is not finite
    RETURN;
END_IF
IF ABS(fDen) < DL_EPS THEN
    bError := TRUE;                 // 平行或重合，交点不唯一 / parallel or coincident, no unique point
    RETURN;
END_IF

// 段 4｜解参数 t、u：分母已在段 3 证为非零 / segment 4, solve the two parameters
fT := (((fCx - fAx) * fD2y) - ((fCy - fAy) * fD2x)) / fDen;   // 线段一参数 / parameter on the first segment
fU := (((fCx - fAx) * fD1y) - ((fCy - fAy) * fD1x)) / fDen;   // 线段二参数 / parameter on the second segment

// 段 5｜线段域闸：任一参数越出 [0,1] 即延长线相交，按正常无交点处置 / segment 5, the segment domain gate
IF (fT < -DL_EPS) OR (fT > (DL_ONE + DL_EPS)) OR (fU < -DL_EPS) OR (fU > (DL_ONE + DL_EPS)) THEN
    RETURN;                         // bError 保持 FALSE，属正常无交点 / bError stays FALSE, this is a normal miss
END_IF

// 段 6｜交点与出口 / segment 6, the intersection point and the exit
fX := fAx + (fT * fD1x);            // 交点 X / intersection X
fY := fAy + (fT * fD1y);            // 交点 Y / intersection Y
bValid := TRUE;                     // 交点可用 / the point is usable
FC_DL_GeoLineIntersectXY := TRUE;   // 线段真实相交 / the segments really intersect
END_FUNCTION
