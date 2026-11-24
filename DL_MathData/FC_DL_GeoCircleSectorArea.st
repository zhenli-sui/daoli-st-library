(*==============================================================================
 * 组件名称 : FC_DL_GeoCircleSectorArea ｜ 子库 : DL_MathData ｜ v1.0.1 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 圆扇形面积 A = 0.5 · r² · θ(rad)。供扇形料片下料、回转台扫掠面积、
 *            风扇扇区通流面积等调用方。角度先按 360 取模归一到 [0,360)，再内联 π/180 转弧度。
 * 契约     : r ≥ 0 且角度有限 → 返回面积、bValid := TRUE（r = 0 合法，面积 0）；
 *            r < 0 或入参非有限 → 返回 0、bError := TRUE、bValid := FALSE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现：π 与度弧换算内联，不调用任何换算件）
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 无除法风险（除数恒 360 与 180）+ 非有限拦截
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换（取整用 TRUNC 泛型，保持 LREAL）R11 全声明行分号
 *            R15 标识符零保留字冲突
 * 遗留假设 : 取模用「TRUNC(θ/360) 后减整圈」实现在 LREAL 域完成，避免 LREAL_TO_DINT
 *            在大角度下的截断溢出；|θ| 超过 1E15 度时整圈数已超出 LREAL 尾数精度，
 *            余角精度下降（工程角度远小于该量级，故不设上限拦截）；
 *            π 取 3.141592653589793（LREAL 双精度 15~16 位有效数字口径）。
 * 修订历史 : 2026-11-24 R79-B 首版（几何族 2/3）
 *============================================================================*)
FUNCTION FC_DL_GeoCircleSectorArea : LREAL
VAR_INPUT
    fRadius   : LREAL := 0.0; // 圆半径，须 ≥ 0 [mm] / the circle radius, zero allowed
    fAngleDeg : LREAL := 0.0; // 扇区圆心角，可负，内部按 360 取模 [度] / the central angle, negative allowed, wrapped by 360
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 半径非法或入参非有限时为真 / TRUE on a negative radius or a non finite input
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_FIN     : LREAL := 1.0E30;  // 有限性判据上界（R477 范式：ABS(x)>FIN 判 Inf，禁用 x-x 差判）/ finiteness ceiling, ABS(x)>FIN flags Inf
    DL_ZERO : LREAL := 0.0;               // 实数零哨兵 [mm] / the real zero sentinel
    DL_HALF : LREAL := 0.5;               // 扇形系数 1/2 [无量纲] / the sector coefficient one half
    DL_FULL : LREAL := 360.0;             // 整圆角度 [度] / the full turn in degrees
    DL_DEG  : LREAL := 180.0;             // 半圆角度，度弧换算分母 [度] / the half turn, the degree to radian divisor
    DL_PI   : LREAL := 3.141592653589793; // 圆周率（内联，不引用换算件）[无量纲] / the inline constant pi
END_VAR
VAR
    fTurns : LREAL; // 整圈数（向零截断，LREAL 域内）[圈] / the whole turn count truncated toward zero
    fAng   : LREAL; // 归一后的圆心角，落在 [0,360) [度] / the wrapped central angle inside one turn
    fRad   : LREAL; // 圆心角弧度值 [弧度] / the central angle in radians
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoCircleSectorArea := DL_ZERO;  // 缺省零 / default zero
eErr   := 0;                           // 零码位范式 / zero-code rule
bError := FALSE;                       // 预置无故障 / preset no fault
bValid := FALSE;                       // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜非有限拦截：NaN 自反判，Inf 自减判 / segment 2, the non finite gate
IF (fRadius <> fRadius) OR (fAngleDeg <> fAngleDeg) THEN
    bError := TRUE;                    // NaN 入参 / a NaN input
    RETURN;                            // 返回 0 / return the preset zero
END_IF
IF (ABS(fRadius) > DL_FIN) OR (ABS(fAngleDeg) > DL_FIN) THEN
    bError := TRUE;                    // Inf 入参 / an infinite input
    RETURN;                            // 返回 0 / return the preset zero
END_IF

// 段 3｜半径域闸：负半径无几何意义，零半径面积为零属合法 / segment 3, the radius gate
IF fRadius < DL_ZERO THEN
    bError := TRUE;                    // 负半径 / a negative radius
    RETURN;                            // 返回 0 / return the preset zero
END_IF

// 段 4｜角度归一：θ − TRUNC(θ/360) × 360 落在 (−360, 360)，负向再补一圈到 [0,360) / segment 4, the angle wrap
fTurns := TRUNC(fAngleDeg / DL_FULL);          // 整圈数，向零截断 [圈] / whole turns truncated toward zero
fAng   := fAngleDeg - (fTurns * DL_FULL);      // 余角，与输入同号 [度] / the remainder carrying the input sign
IF fAng < DL_ZERO THEN fAng := fAng + DL_FULL; END_IF  // 负向补一圈 / add one turn for negative remainders

// 段 5｜度转弧度并求面积：A = 0.5 · r² · θ·π/180 / segment 5, the area
fRad := fAng * (DL_PI / DL_DEG);               // 弧度值 [弧度] / the radian value
FC_DL_GeoCircleSectorArea := DL_HALF * fRadius * fRadius * fRad;  // 面积 [mm²] / the sector area
bValid := TRUE;                                // 返回值可用 / the return value is usable
END_FUNCTION
