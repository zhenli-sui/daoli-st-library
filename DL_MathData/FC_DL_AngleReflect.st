(*==============================================================================
 * 名称 : FC_DL_AngleReflect —— 关于轴线角 fAxis 的镜像反射（结果 [0,360)）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 求入射角 fAngle 关于镜像轴 fAxis 的反射角：r = 2*fAxis - fAngle
 *            （数值语义恒正确，含跨 0°/360° 情形），归一到 [0,360)。
 *            例：轴 45°、入射 10° → 反射 80°；轴 0°、入射 350° → 反射 10°。
 *            边界处理：任一输入非有限（NaN/±Inf）或 |量|>1.0E12 置 eErr 返回 0.0。
 * 错误码 : 16#0001_1B07 = 输入非有限（NaN/±Inf）或角度量超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/量程防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AngleReflect : LREAL
VAR_INPUT
    fAngle : LREAL;    // 入射角 [度] / incident angle in degrees
    fAxis  : LREAL;    // 镜像轴角 [度] / mirror axis angle in degrees
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B07=输入非有限或超量程 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _r : LREAL;        // 反射角中间值 [度] / reflected raw angle
END_VAR

FC_DL_AngleReflect := 0.0;                   // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fAngle <> fAngle) OR ((fAngle - fAngle) <> (fAngle - fAngle))    // fAngle 非有限 / NaN or infinite
   OR (fAxis <> fAxis) OR ((fAxis - fAxis) <> (fAxis - fAxis))        // fAxis 非有限 / NaN or infinite
   OR (ABS(fAngle) > 1.0E12) OR (ABS(fAxis) > 1.0E12) THEN            // 角度量超安全量程 / beyond safe range
    eErr   := 16#0001_1B07;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

_r := 2.0 * fAxis - fAngle;                  // 关于轴镜像反射 / reflect about axis
_r := _r - 360.0 * TRUNC(_r / 360.0);        // 整圈截断缩圈 / strip whole turns
IF _r < 0.0 THEN                             // 负角修正 / fix negative angle
    _r := _r + 360.0;                        // 加一整圈，得 [0,360) / add one turn
END_IF

FC_DL_AngleReflect := _r;                    // 回写 [0,360) 反射角 / write back reflection

END_FUNCTION
