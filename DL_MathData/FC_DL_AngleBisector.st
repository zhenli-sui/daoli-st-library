(*==============================================================================
 * 名称 : FC_DL_AngleBisector —— 两角平分线（钝角取短弧中点，结果 [0,360)）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 求 fA 与 fB 的角平分线：先取 fB-fA 的最短弧差 d∈[-180,180)
 *            （恒取短弧，即使两角相差为钝角侧也走短弧中点），平分角 =
 *            fA + 0.5*d，最后归一到 [0,360)。与 FC_DL_AngleLerpShort 的
 *            fT=0.5 特例一致，独立内联实现（无库内跨件依赖）。
 *            边界处理：任一输入非有限（NaN/±Inf）或 |角|>1.0E12 置 eErr 返回 0.0。
 * 错误码 : 16#0001_1B04 = 输入非有限（NaN/±Inf）或角度量超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/量程防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AngleBisector : LREAL
VAR_INPUT
    fA : LREAL;    // 角 A [度] / angle A in degrees
    fB : LREAL;    // 角 B [度] / angle B in degrees
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B04=输入非有限或超量程 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _d : LREAL;        // fB-fA 最短弧差 [度] / shortest-arc diff
    _m : LREAL;        // 平分角中间值 [度] / bisector raw value
END_VAR

FC_DL_AngleBisector := 0.0;                  // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fA <> fA) OR ((fA - fA) <> (fA - fA))    // fA 非有限 / fA is NaN or infinite
   OR (fB <> fB) OR ((fB - fB) <> (fB - fB)) // fB 非有限 / fB is NaN or infinite
   OR (ABS(fA) > 1.0E12) OR (ABS(fB) > 1.0E12) THEN    // 角度量超安全量程 / beyond safe range
    eErr   := 16#0001_1B04;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

_d := fB - fA;                               // 原始差值 / raw difference
_d := _d - 360.0 * TRUNC(_d / 360.0);        // 整圈截断缩圈 / strip whole turns
IF _d >= 180.0 THEN                          // 上越界修正（恒取短弧）/ fix upper overflow
    _d := _d - 360.0;                        // 减一整圈 / subtract one turn
END_IF
IF _d < -180.0 THEN                          // 下越界修正 / fix lower overflow
    _d := _d + 360.0;                        // 加一整圈 / add one turn
END_IF

_m := fA + 0.5 * _d;                         // 短弧中点即平分角 / midpoint of short arc
_m := _m - 360.0 * TRUNC(_m / 360.0);        // 归一缩圈 / normalize by stripping turns
IF _m < 0.0 THEN                             // 负角修正 / fix negative angle
    _m := _m + 360.0;                        // 加一整圈 / add one turn
END_IF

FC_DL_AngleBisector := _m;                   // 回写 [0,360) 平分角 / write back bisector

END_FUNCTION
