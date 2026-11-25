(*==============================================================================
 * 组件名称 : FC_DL_GeoPointLineDist ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 点到「无限长直线」的垂直距离。以叉积面积除底边长度实现：
 *            d = |(B−A) × (P−A)| / |B−A|。用于切割头对刀线偏差、视觉边缘距、
 *            机器人轨迹避让安全距离核算。
 * 契约     : 返回距离（≥ 0，同工程单位）；A、B 重合（|AB| < 1.0E-9）时返回 −1.0、
 *            bError := TRUE、bValid := FALSE；任一点含 NaN 或算得非有限值时同样按故障处置。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS / SQRT
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 NaN 自反判据 + 无穷上界 + 退化前拦、
 *            除法前判底边长 ｜ R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 距离为「无限长直线」口径，不是线段距离；需要线段距离的场合须另行裁剪到端点。
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 1/8）
 *============================================================================*)
FUNCTION FC_DL_GeoPointLineDist : LREAL
VAR_INPUT
    fPx     : LREAL;    // 被测点 X 坐标 [mm] / X coordinate of the measured point [mm]
    fPy     : LREAL;    // 被测点 Y 坐标 [mm] / Y coordinate of the measured point [mm]
    fAx     : LREAL;    // 直线第一点 X 坐标 [mm] / X coordinate of the first line point [mm]
    fAy     : LREAL;    // 直线第一点 Y 坐标 [mm] / Y coordinate of the first line point [mm]
    fBx     : LREAL;    // 直线第二点 X 坐标 [mm] / X coordinate of the second line point [mm]
    fBy     : LREAL;    // 直线第二点 Y 坐标 [mm] / Y coordinate of the second line point [mm]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 退化直线或非有限输入为真 / TRUE on a degenerate line or a non finite input
    bValid  : BOOL;     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-9;      // 长度容差，底边短于此值即判重合 [mm] / length tolerance for the degenerate test [mm]
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界，超过按无穷处置 [mm] / finiteness ceiling [mm]
    DL_NEG_ONE  : LREAL := -1.0;        // 退化返回哨兵 / degenerate sentinel
    DL_ZERO_L   : LREAL := 0.0;         // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    fDx     : LREAL;    // 底边 X 分量 B−A [mm] / X component of the base vector [mm]
    fDy     : LREAL;    // 底边 Y 分量 B−A [mm] / Y component of the base vector [mm]
    fLen    : LREAL;    // 底边长度 |B−A| [mm] / base length [mm]
    fCross  : LREAL;    // 叉积绝对值，等于两倍三角形面积 [mm²] / absolute cross product, twice the triangle area [mm²]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoPointLineDist := DL_ZERO_L;    // 缺省距离 0 / default distance zero
eErr   := 0;                            // 零码位范式 / zero-code rule
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 计算完成前不认结果 / unusable until the computation ends

// 段 2｜非有限闸：六个坐标任一为 NaN 即拒（x <> x 自反判据） / segment 2, the non finite gate
IF (fPx <> fPx) OR (fPy <> fPy) OR (fAx <> fAx) OR (fAy <> fAy) OR (fBx <> fBx) OR (fBy <> fBy) THEN
    bError := TRUE;                     // 含非数输入 / a not a number input was seen
    FC_DL_GeoPointLineDist := DL_NEG_ONE;
    RETURN;
END_IF

// 段 3｜底边与退化判定：短于容差即两点重合，直线不存在 / segment 3, the base vector and the degenerate test
fDx  := fBx - fAx;                      // X 分量 / the X component
fDy  := fBy - fAy;                      // Y 分量 / the Y component
fLen := SQRT((fDx * fDx) + (fDy * fDy));    // 底边长度，平方和可能溢出为无穷，下一段接住 / the squares may overflow, the next gate catches it
IF (fLen <> fLen) OR (fLen > DL_FIN_LIM) THEN
    bError := TRUE;                     // 长度非有限（坐标量级过大）/ the length is not finite because the coordinates are huge
    FC_DL_GeoPointLineDist := DL_NEG_ONE;
    RETURN;
END_IF
IF fLen < DL_EPS THEN
    bError := TRUE;                     // A、B 重合，直线退化 / the two points coincide and the line degenerates
    FC_DL_GeoPointLineDist := DL_NEG_ONE;
    RETURN;
END_IF

// 段 4｜叉积面积与距离：除法分母已在段 3 证为非零且有限 / segment 4, the cross product and the division
fCross := ABS((fDx * (fPy - fAy)) - (fDy * (fPx - fAx)));   // 两倍三角形面积 / twice the triangle area
IF (fCross <> fCross) OR (fCross > DL_FIN_LIM) THEN
    bError := TRUE;                     // 叉积非有限 / the cross product is not finite
    FC_DL_GeoPointLineDist := DL_NEG_ONE;
    RETURN;
END_IF
FC_DL_GeoPointLineDist := fCross / fLen;    // 面积除底边即高 [mm] / area over base gives the height [mm]
bValid := TRUE;                             // 结果可用 / the result is usable
END_FUNCTION
