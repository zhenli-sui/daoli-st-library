(*==============================================================================
 * 名称 : FC_DL_AngleTolInside —— 角度容差窗判定（fCenter ± fTol，跨 0° 正确）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 判定 fAngle 是否落在 fCenter ± fTol 的圆周窗内：取 fAngle-fCenter
 *            的最短弧差 d∈[-180,180)（天然跨 0°/360° 正确），当 |d| <= fTol
 *            判在内。窗宽 >180° 时窗覆盖超过半圆，仍按最短弧口径判定。
 *            边界处理：fTol<0 判参数非法（置 eErr 返回 FALSE）；任一角度输入
 *            非有限（NaN/±Inf）或 |角|>1.0E12 置 eErr 返回 FALSE。
 * 错误码 : 16#0001_1B06 = fTol 为负（容差非法），或角度输入非有限 / 超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示判定结论可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/浮点容差比较 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AngleTolInside : BOOL
VAR_INPUT
    fAngle  : LREAL;   // 被判定角 [度] / angle under test in degrees
    fCenter : LREAL;   // 窗中心角 [度] / window center angle in degrees
    fTol    : LREAL;   // 容差半窗宽，须 >=0 [度] / tolerance half-width, must be >= 0
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B06=参数非法或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=判定结论可用 / TRUE when verdict is usable
END_VAR
VAR
    _d : LREAL;        // 最短弧差 [度] / shortest-arc diff
END_VAR

FC_DL_AngleTolInside := FALSE;               // 判定预设 FALSE / preset verdict to FALSE
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF fTol < 0.0 THEN                           // 容差为负：参数非法 / negative tolerance invalid
    eErr   := 16#0001_1B06;                  // 置参数非法码 / set invalid-parameter code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 结论不可用 / verdict not usable
    RETURN;                                  // 返回 FALSE / return FALSE
END_IF

IF (fAngle <> fAngle) OR ((fAngle - fAngle) <> (fAngle - fAngle))     // fAngle 非有限 / NaN or infinite
   OR (fCenter <> fCenter) OR ((fCenter - fCenter) <> (fCenter - fCenter))   // fCenter 非有限 / NaN or infinite
   OR (fTol <> fTol) OR ((fTol - fTol) <> (fTol - fTol))               // fTol 非有限 / NaN or infinite
   OR (ABS(fAngle) > 1.0E12) OR (ABS(fCenter) > 1.0E12) THEN           // 角度量超安全量程 / beyond safe range
    eErr   := 16#0001_1B06;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 结论不可用 / verdict not usable
    RETURN;                                  // 返回 FALSE / return FALSE
END_IF

_d := fAngle - fCenter;                      // 原始差值 / raw difference
_d := _d - 360.0 * TRUNC(_d / 360.0);        // 整圈截断缩圈 / strip whole turns
IF _d >= 180.0 THEN                          // 上越界修正 / fix upper overflow
    _d := _d - 360.0;                        // 减一整圈 / subtract one turn
END_IF
IF _d < -180.0 THEN                          // 下越界修正 / fix lower overflow
    _d := _d + 360.0;                        // 加一整圈 / add one turn
END_IF

IF ABS(_d) <= fTol THEN                      // 最短弧差落在容差窗内 / diff inside tolerance window
    FC_DL_AngleTolInside := TRUE;            // 判在内 / verdict inside
END_IF

END_FUNCTION
