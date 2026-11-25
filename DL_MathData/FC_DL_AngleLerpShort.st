(*==============================================================================
 * 名称 : FC_DL_AngleLerpShort —— 两角度最短弧线性插值（跨 0/360 正确）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 沿 fA→fB 最短弧做线性插值：先求 fB-fA 的最短弧差 d∈[-180,180)，
 *            结果 = fA + fT*d，再归一到 [0,360)。fT=0 得 fA 方向，fT=1 得 fB
 *            方向；跨 0/360（如 350°→10°）走 +20° 短弧而非 -340° 长弧。
 *            边界处理：fT 越界 [0,1] 钳位使用（不置故障，属容错钳位）；任一
 *            输入非有限（NaN/±Inf）置 eErr 返回 0.0；|fA|>1.0E12 置 eErr。
 * 错误码 : 16#0001_1B02 = 输入非有限（NaN/±Inf）或角度量超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/钳位/量程防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AngleLerpShort : LREAL
VAR_INPUT
    fA : LREAL;    // 插值起点角 [度] / interpolation start angle in degrees
    fB : LREAL;    // 插值终点角 [度] / interpolation end angle in degrees
    fT : LREAL;    // 插值比例 0..1，越界钳位 [无量纲] / interpolation ratio, clamped into [0,1]
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B02=输入非有限或超量程 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _d : LREAL;        // fA→fB 最短弧差 [度] / shortest-arc diff from A to B
    _n : LREAL;        // 整圈数（TRUNC 截断）[圈] / whole turns via truncation
    _t : LREAL;        // 钳位后的插值比例 [无量纲] / clamped ratio
    _r : LREAL;        // 插值中间结果 [度] / interpolated raw result
END_VAR

FC_DL_AngleLerpShort := 0.0;                 // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fA <> fA) OR ((fA - fA) <> (fA - fA))    // fA 非有限 / fA is NaN or infinite
   OR (fB <> fB) OR ((fB - fB) <> (fB - fB)) // fB 非有限 / fB is NaN or infinite
   OR (fT <> fT) OR ((fT - fT) <> (fT - fT)) // fT 非有限 / fT is NaN or infinite
   OR (ABS(fA) > 1.0E12) OR (ABS(fB) > 1.0E12) THEN    // 角度量超安全量程 / beyond safe range
    eErr   := 16#0001_1B02;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

_t := fT;                                    // 取比例 / take ratio
IF _t < 0.0 THEN _t := 0.0; END_IF           // 下界钳位 / clamp lower bound
IF _t > 1.0 THEN _t := 1.0; END_IF           // 上界钳位 / clamp upper bound

_d := fB - fA;                               // 原始差值 / raw difference
_d := _d - 360.0 * TRUNC(_d / 360.0);        // 整圈截断缩圈 / strip whole turns
IF _d >= 180.0 THEN                          // 上越界修正 / fix upper overflow
    _d := _d - 360.0;                        // 减一整圈 / subtract one turn
END_IF
IF _d < -180.0 THEN                          // 下越界修正 / fix lower overflow
    _d := _d + 360.0;                        // 加一整圈 / add one turn
END_IF

_r := fA + _t * _d;                          // 沿最短弧插值 / interpolate along shortest arc
_r := _r - 360.0 * TRUNC(_r / 360.0);        // 归一缩圈 / normalize by stripping turns
IF _r < 0.0 THEN                             // 负角修正 / fix negative angle
    _r := _r + 360.0;                        // 加一整圈 / add one turn
END_IF

FC_DL_AngleLerpShort := _r;                  // 回写 [0,360) 插值结果 / write back result

END_FUNCTION
