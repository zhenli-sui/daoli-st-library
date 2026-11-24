(*==============================================================================
 * 名称 : FC_DL_AngleQuadrant —— 角度象限判定（0..3）与坐标轴命中标志
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将输入角归一到 [0,360) 后判定象限：0=[0,90) 1=[90,180)
 *            2=[180,270) 3=[270,360)。归一角恰为 0/90/180/270（容差
 *            1.0E-9，浮点禁用 = 直接比较）时 bOnAxis=TRUE，象限取该轴线
 *            后一侧区间编号（0°→0、90°→1、180°→2、270°→3）。
 *            边界处理：输入非有限（NaN/±Inf）或 |角|>1.0E12 置 eErr 返回 0。
 * 错误码 : 16#0001_1B03 = 输入非有限（NaN/±Inf）或角度量超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示象限与轴标志均可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/浮点容差比较 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AngleQuadrant : INT
VAR_INPUT
    fAngle : LREAL;    // 输入角（任意实数，内部归一）[度] / input angle, normalized internally
END_VAR
VAR_OUTPUT
    bOnAxis : BOOL;    // TRUE=归一角命中 0/90/180/270（容差 1.0E-9）/ TRUE when on axis within 1.0E-9
    eErr    : UDINT;   // 故障码，0=正常，1B03=输入非有限或超量程 / error code
    bError  : BOOL;    // TRUE=本件发生故障 / TRUE when fault occurred
    bValid  : BOOL;    // TRUE=象限与轴标志可用 / TRUE when outputs are usable
END_VAR
VAR
    _r : LREAL;        // 归一后的角 [度] / normalized angle
    _n : LREAL;        // 整圈数（TRUNC 截断）[圈] / whole turns via truncation
END_VAR

FC_DL_AngleQuadrant := 0;                    // 象限预设 0 / preset quadrant to zero
bOnAxis := FALSE;                            // 轴标志预设 FALSE / preset on-axis to FALSE
eErr    := 16#0000_0000;                     // 故障码清零 / clear error code
bError  := FALSE;                            // 故障标志清零 / clear error flag
bValid  := TRUE;                             // 预设输出可用 / preset valid flag

IF (fAngle <> fAngle) OR ((fAngle - fAngle) <> (fAngle - fAngle))    // 非有限 / NaN or infinite
   OR (ABS(fAngle) > 1.0E12) THEN            // 超安全量程 / beyond safe range
    eErr   := 16#0001_1B03;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // 返回 0 / return zero
END_IF

_r := fAngle;                                // 取输入角 / take input
_r := _r - 360.0 * TRUNC(_r / 360.0);        // 整圈截断缩圈 / strip whole turns
IF _r < 0.0 THEN                             // 负角修正 / fix negative angle
    _r := _r + 360.0;                        // 加一整圈，得 [0,360) / add one turn
END_IF

IF ABS(_r - 0.0) < 1.0E-9                    // 轴线 0°（含容差）/ on axis 0 deg
   OR ABS(_r - 90.0) < 1.0E-9                // 轴线 90°（含容差）/ on axis 90 deg
   OR ABS(_r - 180.0) < 1.0E-9               // 轴线 180°（含容差）/ on axis 180 deg
   OR ABS(_r - 270.0) < 1.0E-9 THEN          // 轴线 270°（含容差）/ on axis 270 deg
    bOnAxis := TRUE;                         // 置轴线命中标志 / set on-axis flag
END_IF

IF _r >= 270.0 THEN                          // [270,360) 第 4 象限 / quadrant 4
    FC_DL_AngleQuadrant := 3;                // 象限码 3 / quadrant code 3
ELSIF _r >= 180.0 THEN                       // [180,270) 第 3 象限 / quadrant 3
    FC_DL_AngleQuadrant := 2;                // 象限码 2 / quadrant code 2
ELSIF _r >= 90.0 THEN                        // [90,180) 第 2 象限 / quadrant 2
    FC_DL_AngleQuadrant := 1;                // 象限码 1 / quadrant code 1
ELSE                                         // [0,90) 第 1 象限 / quadrant 1
    FC_DL_AngleQuadrant := 0;                // 象限码 0 / quadrant code 0
END_IF

END_FUNCTION
