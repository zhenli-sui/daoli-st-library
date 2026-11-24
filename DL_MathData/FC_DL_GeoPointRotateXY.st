(*==============================================================================
 * 组件名称 : FC_DL_GeoPointRotateXY ｜ 子库 : DL_MathData ｜ v1.0.1 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 平面点绕任意中心旋转。绕 (fCx, fCy) 把点 (fPx, fPy) 逆时针旋转 fAngleDeg 度
 *            （顺时针给负角），输出旋转后坐标。供相机像素坐标与机械坐标对齐、视觉纠偏、
 *            托盘位姿变换使用。
 * 契约     : 入参全有限 → 返回 TRUE、bValid := TRUE、出参有效；任一入参非有限 →
 *            返回 FALSE、bError := TRUE、两出参置 0。角度按 360 取模（负角与超圈角均合法）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），仅用标准库 COS / SIN / TRUNC
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 非有限拦截 + 居中平移后再转（大坐标不丢精度）
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换（取整用 TRUNC 泛型）R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : COS / SIN 取 IEC 61131-3 标准库同名函数（Standard.library），三平台语义一致；
 *            π 内联于常量表，不引用任何度弧换算件；逆时针为正角，与右手坐标系一致，
 *            若目标平台为左手系（Y 向下），调用方取负角即等价。
 * 修订历史 : 2026-11-24 R79-B 首版（几何族 3/3）
 *============================================================================*)
FUNCTION FC_DL_GeoPointRotateXY : BOOL
VAR_INPUT
    fPx       : LREAL := 0.0; // 待旋转点 X 坐标 [mm] / the X coordinate of the point
    fPy       : LREAL := 0.0; // 待旋转点 Y 坐标 [mm] / the Y coordinate of the point
    fAngleDeg : LREAL := 0.0; // 旋转角，逆时针为正，按 360 取模 [度] / the rotation angle, counter clockwise positive, wrapped by 360
    fCx       : LREAL := 0.0; // 旋转中心 X 坐标 [mm] / the X coordinate of the rotation centre
    fCy       : LREAL := 0.0; // 旋转中心 Y 坐标 [mm] / the Y coordinate of the rotation centre
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 任一入参非有限时为真 / TRUE when any input is not finite
    bValid : BOOL;  // 出参可用标志 / TRUE when the outputs are usable
    fOx    : LREAL; // 旋转后 X 坐标 [mm] / the rotated X coordinate
    fOy    : LREAL; // 旋转后 Y 坐标 [mm] / the rotated Y coordinate
END_VAR
VAR CONSTANT
    DL_FIN     : LREAL := 1.0E30;  // 有限性判据上界（R477 范式：ABS(x)>FIN 判 Inf，禁用 x-x 差判）/ finiteness ceiling, ABS(x)>FIN flags Inf
    DL_ZERO : LREAL := 0.0;               // 实数零哨兵 [mm] / the real zero sentinel
    DL_FULL : LREAL := 360.0;             // 整圆角度 [度] / the full turn in degrees
    DL_DEG  : LREAL := 180.0;             // 半圆角度，度弧换算分母 [度] / the half turn, the divisor of the degree to radian chain
    DL_PI   : LREAL := 3.141592653589793; // 圆周率（内联）[无量纲] / the inline constant pi
END_VAR
VAR
    fTurns : LREAL; // 整圈数（向零截断）[圈] / the whole turn count truncated toward zero
    fAng   : LREAL; // 归一后的旋转角 [度] / the wrapped rotation angle
    fRad   : LREAL; // 旋转角弧度值 [弧度] / the rotation angle in radians
    fCos   : LREAL; // 余弦中间量 [无量纲] / the cosine term
    fSin   : LREAL; // 正弦中间量 [无量纲] / the sine term
    fDx    : LREAL; // 点相对中心的 X 偏移 [mm] / the X offset from the centre
    fDy    : LREAL; // 点相对中心的 Y 偏移 [mm] / the Y offset from the centre
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoPointRotateXY := FALSE;  // 缺省失败 / default failure
eErr   := 0;                      // 零码位范式 / zero-code rule
bError := FALSE;                  // 预置无故障 / preset no fault
bValid := FALSE;                  // 域闸前不认出参 / the outputs are unusable until the gates pass
fOx    := DL_ZERO;                // X 出参清零 / clear the rotated X
fOy    := DL_ZERO;                // Y 出参清零 / clear the rotated Y

// 段 2｜非有限拦截（五个入参逐个自检，NaN 自反判 + Inf 自减判）/ segment 2, the non finite gate
IF (fPx <> fPx) OR (fPy <> fPy) OR (fAngleDeg <> fAngleDeg) OR (fCx <> fCx) OR (fCy <> fCy) THEN
    bError := TRUE;               // NaN 入参 / a NaN input
    RETURN;                       // 出参保持 0 / the outputs stay zero
END_IF
IF (ABS(fPx) > DL_FIN) OR (ABS(fPy) > DL_FIN) OR (ABS(fAngleDeg) > DL_FIN) OR (ABS(fCx) > DL_FIN) OR (ABS(fCy) > DL_FIN) THEN
    bError := TRUE;               // Inf 入参 / an infinite input
    RETURN;                       // 出参保持 0 / the outputs stay zero
END_IF

// 段 3｜角度归一：θ − TRUNC(θ/360) × 360，负向补一圈到 [0,360) / segment 3, the angle wrap
fTurns := TRUNC(fAngleDeg / DL_FULL);          // 整圈数 [圈] / the whole turn count
fAng   := fAngleDeg - (fTurns * DL_FULL);      // 余角，与输入同号 [度] / the remainder carrying the input sign
IF fAng < DL_ZERO THEN fAng := fAng + DL_FULL; END_IF  // 负向补一圈 / add one turn for negative remainders
fRad := fAng * (DL_PI / DL_DEG);               // 度转弧度 [弧度] / the radian value
fCos := COS(fRad);                             // 余弦 [无量纲] / the cosine term
fSin := SIN(fRad);                             // 正弦 [无量纲] / the sine term

// 段 4｜居中平移后再旋转：先减中心，避免大坐标直接参与乘法丢有效位 / segment 4, the centred rotation
fDx := fPx - fCx;                              // X 偏移 [mm] / the X offset
fDy := fPy - fCy;                              // Y 偏移 [mm] / the Y offset
fOx := fCx + (fDx * fCos) - (fDy * fSin);      // 旋转后 X [mm] / the rotated X
fOy := fCy + (fDx * fSin) + (fDy * fCos);      // 旋转后 Y [mm] / the rotated Y

// 段 5｜出口 / segment 5, the exit
bValid := TRUE;                   // 出参可用 / the outputs are usable
FC_DL_GeoPointRotateXY := TRUE;   // 旋转完成 / the rotation completed
END_FUNCTION
