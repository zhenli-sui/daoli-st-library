(*==============================================================================
 * 组件名称 : FC_DL_GeoCentroid3Pt ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 三顶点三角形质心（重心）坐标。出参 fCx = (x1+x2+x3)/3、fCy = (y1+y2+y3)/3。
 *            用于三点示教求工位中心、三点视觉定位求零件中心、夹具三支撑点配平。
 * 契约     : 成功返回 TRUE 并写出质心；三点共线（|叉积| < 1.0E-9）返回 FALSE、
 *            bError := TRUE、出参置 0 —— 共线三角形无质心可言，不得返回中点冒充。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 NaN 自反判据 + 无穷上界 + 共线前拦、
 *            除数为常量 3 ｜ R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 5/8）
 *============================================================================*)
FUNCTION FC_DL_GeoCentroid3Pt : BOOL
VAR_INPUT
    fX1     : LREAL;    // 顶点一 X [mm] / X of the first vertex [mm]
    fY1     : LREAL;    // 顶点一 Y [mm] / Y of the first vertex [mm]
    fX2     : LREAL;    // 顶点二 X [mm] / X of the second vertex [mm]
    fY2     : LREAL;    // 顶点二 Y [mm] / Y of the second vertex [mm]
    fX3     : LREAL;    // 顶点三 X [mm] / X of the third vertex [mm]
    fY3     : LREAL;    // 顶点三 Y [mm] / Y of the third vertex [mm]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 三点共线或输入非有限为真 / TRUE on collinear points or non finite inputs
    bValid  : BOOL;     // 出参可用标志 / TRUE when the outputs are usable
    fCx     : LREAL;    // 质心 X 坐标，故障时 0 [mm] / centroid X, zero on fault [mm]
    fCy     : LREAL;    // 质心 Y 坐标，故障时 0 [mm] / centroid Y, zero on fault [mm]
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-9;      // 共线判据容差，小于它视为共线 [mm²] / collinearity tolerance [mm²]
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界 [mm] / finiteness ceiling [mm]
    DL_THREE    : LREAL := 3.0;         // 顶点数，质心的除数 [个] / vertex count, the centroid divisor
    DL_ZERO_L   : LREAL := 0.0;         // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    fCross  : LREAL;    // 两倍有向面积的叉积 [mm²] / cross product, twice the signed area [mm²]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoCentroid3Pt := FALSE;      // 缺省失败 / default failure
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 域闸前不认出参 / the outputs are unusable until the gates pass
fCx    := DL_ZERO_L;                // 质心 X 清零 / clear the centroid X
fCy    := DL_ZERO_L;                // 质心 Y 清零 / clear the centroid Y

// 段 2｜非有限闸：六个坐标任一为 NaN 即拒 / segment 2, the non finite gate
IF (fX1 <> fX1) OR (fY1 <> fY1) OR (fX2 <> fX2) OR (fY2 <> fY2) OR (fX3 <> fX3) OR (fY3 <> fY3) THEN
    bError := TRUE;                 // 含非数输入 / a not a number input was seen
    RETURN;
END_IF

// 段 3｜共线闸：叉积即两倍有向面积，近零则三点共线 / segment 3, the collinearity gate
fCross := ((fX2 - fX1) * (fY3 - fY1)) - ((fY2 - fY1) * (fX3 - fX1));
IF (fCross <> fCross) OR (ABS(fCross) > DL_FIN_LIM) THEN
    bError := TRUE;                 // 叉积非有限 / the cross product is not finite
    RETURN;
END_IF
IF ABS(fCross) < DL_EPS THEN
    bError := TRUE;                 // 三点共线，无质心 / the points are collinear and no centroid exists
    RETURN;
END_IF

// 段 4｜质心：三坐标算术平均，除数为常量 3 / segment 4, the arithmetic mean of the three vertices
fCx := (fX1 + fX2 + fX3) / DL_THREE;    // 质心 X / centroid X
fCy := (fY1 + fY2 + fY3) / DL_THREE;    // 质心 Y / centroid Y
bValid := TRUE;                         // 出参可用 / the outputs are usable
FC_DL_GeoCentroid3Pt := TRUE;           // 求解成功 / the request succeeded
END_FUNCTION
