(*==============================================================================
 * 组件名称 : FC_DL_GeoPointInConvexQuadXY ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 点是否落在凸四边形内（含边界）。顶点须按序（顺或逆时针）给出，
 *            用叉积同号法：点对四条有向边的叉积若全同号（或全近零）即在内部。
 *            用于相机视野分区、机器人安全区、视觉 ROI 的旋转框判定。
 * 契约     : 在内返回 TRUE；四边形退化（|鞋带面积| < 1.0E-6）返回 FALSE、bError := TRUE；
 *            点恰在边上按「在内」处理（容差 1.0E-9）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 NaN 自反判据 + 无穷上界 + 退化面积极小判据、
 *            浮点无等号判等 ｜ R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 顶点序错乱（如 1-3-2-4）会让叉积法失效并可能误判在外 —— 顶点序由调用方保证，
 *            函数内不做自交检测（自交检测为另件职责）。
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 4/8）
 *============================================================================*)
FUNCTION FC_DL_GeoPointInConvexQuadXY : BOOL
VAR_INPUT
    fPx     : LREAL;    // 被测点 X 坐标 [mm] / X coordinate of the measured point [mm]
    fPy     : LREAL;    // 被测点 Y 坐标 [mm] / Y coordinate of the measured point [mm]
    fX1     : LREAL;    // 顶点一 X [mm] / X of the first vertex [mm]
    fY1     : LREAL;    // 顶点一 Y [mm] / Y of the first vertex [mm]
    fX2     : LREAL;    // 顶点二 X [mm] / X of the second vertex [mm]
    fY2     : LREAL;    // 顶点二 Y [mm] / Y of the second vertex [mm]
    fX3     : LREAL;    // 顶点三 X [mm] / X of the third vertex [mm]
    fY3     : LREAL;    // 顶点三 Y [mm] / Y of the third vertex [mm]
    fX4     : LREAL;    // 顶点四 X [mm] / X of the fourth vertex [mm]
    fY4     : LREAL;    // 顶点四 Y [mm] / Y of the fourth vertex [mm]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 退化四边形或非有限输入为真 / TRUE on a degenerate quad or non finite inputs
    bValid  : BOOL;     // 判定可用标志 / TRUE when the verdict is usable
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-9;      // 叉积容差，边上的点按「在内」处理 [mm²] / cross tolerance, edge points count as inside [mm²]
    DL_AREA_MIN : LREAL := 1.0E-6;      // 四边形面积下限，小于它判退化 [mm²] / degenerate area threshold [mm²]
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界 [mm] / finiteness ceiling [mm]
    DL_TWO      : LREAL := 2.0;         // 鞋带面积的二分之一换算 [无量纲] / halving factor of the shoelace sum
END_VAR
VAR
    fArea2  : LREAL;    // 鞋带和，等于两倍面积 [mm²] / shoelace sum, twice the area [mm²]
    fC1     : LREAL;    // 边 1→2 对点的叉积 [mm²] / cross product of edge one to two [mm²]
    fC2     : LREAL;    // 边 2→3 对点的叉积 [mm²] / cross product of edge two to three [mm²]
    fC3     : LREAL;    // 边 3→4 对点的叉积 [mm²] / cross product of edge three to four [mm²]
    fC4     : LREAL;    // 边 4→1 对点的叉积 [mm²] / cross product of edge four to one [mm²]
    bPos    : BOOL;     // 四条叉积是否全为正 / TRUE when every cross product is positive
    bNeg    : BOOL;     // 四条叉积是否全为负 / TRUE when every cross product is negative
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoPointInConvexQuadXY := FALSE;  // 缺省不在四边形内 / default outside
eErr   := 0;                            // 零码位范式 / zero-code rule
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 判定完成前不可用 / unusable until the verdict ends

// 段 2｜非有限闸：十个坐标任一为 NaN 即拒 / segment 2, the non finite gate
IF (fPx <> fPx) OR (fPy <> fPy) OR (fX1 <> fX1) OR (fY1 <> fY1) OR (fX2 <> fX2) OR (fY2 <> fY2) OR (fX3 <> fX3) OR (fY3 <> fY3) OR (fX4 <> fX4) OR (fY4 <> fY4) THEN
    bError := TRUE;                     // 含非数输入 / a not a number input was seen
    RETURN;
END_IF

// 段 3｜退化闸：鞋带公式求两倍面积，过小即判退化 / segment 3, the shoelace area and the degenerate gate
fArea2 := ABS((fX1 * (fY2 - fY4)) + (fX2 * (fY3 - fY1)) + (fX3 * (fY4 - fY2)) + (fX4 * (fY1 - fY3)));
IF (fArea2 <> fArea2) OR (fArea2 > DL_FIN_LIM) THEN
    bError := TRUE;                     // 面积非有限 / the area is not finite
    RETURN;
END_IF
IF (fArea2 / DL_TWO) < DL_AREA_MIN THEN
    bError := TRUE;                     // 四边形退化（三点共线或重合）/ the quad degenerates
    RETURN;
END_IF

// 段 4｜四条边的叉积：点对每条有向边的相对位置 / segment 4, the four edge cross products
fC1 := ((fX2 - fX1) * (fPy - fY1)) - ((fY2 - fY1) * (fPx - fX1));   // 边 1→2 / edge one to two
fC2 := ((fX3 - fX2) * (fPy - fY2)) - ((fY3 - fY2) * (fPx - fX2));   // 边 2→3 / edge two to three
fC3 := ((fX4 - fX3) * (fPy - fY3)) - ((fY4 - fY3) * (fPx - fX3));   // 边 3→4 / edge three to four
fC4 := ((fX1 - fX4) * (fPy - fY4)) - ((fY1 - fY4) * (fPx - fX4));   // 边 4→1 / edge four to one

// 段 5｜同号判定：全正或全负（近零点按同号处理）/ segment 5, the same sign verdict
bPos := (fC1 > -DL_EPS) AND (fC2 > -DL_EPS) AND (fC3 > -DL_EPS) AND (fC4 > -DL_EPS);
bNeg := (fC1 < DL_EPS) AND (fC2 < DL_EPS) AND (fC3 < DL_EPS) AND (fC4 < DL_EPS);
IF bPos OR bNeg THEN
    FC_DL_GeoPointInConvexQuadXY := TRUE;   // 叉积同号即在凸四边形内 / same signed crosses mean inside
END_IF
bValid := TRUE;                             // 判定可用 / the verdict is usable
END_FUNCTION
