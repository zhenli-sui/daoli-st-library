(*==============================================================================
 * 组件名称 : FC_DL_GeoLineAngleXY ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 两点连线相对 X 轴的有向角 [rad]，域 (−π, π]。实现取 ATAN(dy/dx) 加象限补偿，
 *            刻意不用 ATAN2 —— ATAN2 的形参序（先 x 后 y 还是先 y 后 x）在 CODESYS 手册、
 *            TwinCAT 与标准桩之间互不相同，跨平台移植时必出错；ATAN 单形参无此歧义。
 * 契约     : 返回有向角 ∈ (−π, π]；两点重合（距离 < 1.0E-9）返回 0、bError := TRUE、
 *            bValid := FALSE；输入含 NaN 或非有限值时同样按故障处置。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ATAN / ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 NaN 自反判据 + 无穷上界 + 竖直线单列
 *            （除法前判 dx 容差）｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 无类型转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 象限补偿四分支已覆盖 dx<0 的两种情形与 dx 近零的两种竖直方向，
 *            dx>0 时 ATAN 值本身即落在 (−π/2, π/2)，无需补偿。
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 8/8）
 *============================================================================*)
FUNCTION FC_DL_GeoLineAngleXY : LREAL
VAR_INPUT
    fAx     : LREAL;    // 起点 X 坐标 [mm] / X coordinate of the start point [mm]
    fAy     : LREAL;    // 起点 Y 坐标 [mm] / Y coordinate of the start point [mm]
    fBx     : LREAL;    // 终点 X 坐标 [mm] / X coordinate of the end point [mm]
    fBy     : LREAL;    // 终点 Y 坐标 [mm] / Y coordinate of the end point [mm]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 两点重合或输入非有限为真 / TRUE on coincident points or non finite inputs
    bValid  : BOOL;     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-9;                  // 长度容差，短于此值判重合 [mm] / length tolerance for the coincident test [mm]
    DL_FIN_LIM  : LREAL := 1.0E308;                 // 有限性上界 [mm] / finiteness ceiling [mm]
    DL_PI       : LREAL := 3.14159265358979323846;  // 圆周率 [rad] / pi in radians [rad]
    DL_PI_HALF  : LREAL := 1.57079632679489661923;  // 半圆周率，竖直方向角 [rad] / half pi, the vertical angle [rad]
    DL_ZERO_L   : LREAL := 0.0;                     // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    fDx     : LREAL;    // X 方向的增量 [mm] / increment along X [mm]
    fDy     : LREAL;    // Y 方向的增量 [mm] / increment along Y [mm]
    fAng    : LREAL;    // 角度中间量 [rad] / angle interim value [rad]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoLineAngleXY := DL_ZERO_L;  // 缺省角 0 / default angle zero
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 解算完成前不认结果 / unusable until the solve ends

// 段 2｜非有限闸：四个坐标任一为 NaN 即拒 / segment 2, the non finite gate
IF (fAx <> fAx) OR (fAy <> fAy) OR (fBx <> fBx) OR (fBy <> fBy) THEN
    bError := TRUE;                 // 含非数输入 / a not a number input was seen
    RETURN;
END_IF

// 段 3｜增量与重合判定：两点重合时角度无定义 / segment 3, the increments and the coincident test
fDx := fBx - fAx;
fDy := fBy - fAy;
IF (ABS(fDx) > DL_FIN_LIM) OR (ABS(fDy) > DL_FIN_LIM) THEN
    bError := TRUE;                 // 增量非有限 / the increments are not finite
    RETURN;
END_IF
IF (ABS(fDx) < DL_EPS) AND (ABS(fDy) < DL_EPS) THEN
    bError := TRUE;                 // 两点重合，方向无定义 / the points coincide and no direction exists
    RETURN;
END_IF

// 段 4｜竖直方向单列：dx 近零时角为 ±π/2，避免除以近零量放大误差 / segment 4, the vertical branches
IF ABS(fDx) < DL_EPS THEN
    IF fDy > DL_ZERO_L THEN
        FC_DL_GeoLineAngleXY := DL_PI_HALF;     // 正上方 90° / straight up
    ELSE
        FC_DL_GeoLineAngleXY := -DL_PI_HALF;    // 正下方 −90° / straight down
    END_IF
    bValid := TRUE;                 // 结果可用 / the result is usable
    RETURN;
END_IF

// 段 5｜象限补偿：dx<0 时 ATAN 值需平移 ±π 才能落回 (−π, π] / segment 5, the quadrant compensation
fAng := ATAN(fDy / fDx);            // 主值域 (−π/2, π/2)，除数为已证非零的 dx / principal value with a proven non zero divisor
IF fDx < DL_ZERO_L THEN
    IF fDy > DL_ZERO_L THEN
        fAng := fAng + DL_PI;       // 第二象限 / the second quadrant
    ELSE
        fAng := fAng - DL_PI;       // 第三象限，含 dy = 0 时取 −π 再归到 +π 的边界 / the third quadrant
        IF ABS(fAng) > (DL_PI - DL_EPS) THEN
            fAng := DL_PI;          // 负 X 轴归一到 +π，保证值域 (−π, π] / the negative X axis normalises to plus pi
        END_IF
    END_IF
END_IF

// 段 6｜出口 / segment 6, exit
FC_DL_GeoLineAngleXY := fAng;       // 有向角 [rad] / the signed angle in radians
bValid := TRUE;                     // 结果可用 / the result is usable
END_FUNCTION
