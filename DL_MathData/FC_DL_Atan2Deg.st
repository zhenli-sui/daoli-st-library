(*==============================================================================
 * 名称 : FC_DL_Atan2Deg —— 四象限反正切 → 角度 [0,360)（原点双重合防护）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回 atan2(fY, fX) 的角度制结果并归一到 [0,360)（数学域
 *            (-180,180] 中负角加 360°）。两输入同时为 0 时方向无定义，
 *            返回 0.0、bValid=FALSE 并置 eErr。
 *            边界处理：任一输入非有限（NaN/±Inf）置 eErr 返回 0.0；fX=0 且
 *            fY≠0 的 ±90° 轴向情形由 ATAN2 数值语义原生支持，无需特判。
 * 错误码 : 16#0001_1B0E = fX 与 fY 同时为 0（方向无定义），或输入非有限（NaN/±Inf）
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/原点零向量防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_Atan2Deg : LREAL
VAR_INPUT
    fY : LREAL;    // 纵向分量 [工程单位] / vertical component
    fX : LREAL;    // 横向分量 [工程单位] / horizontal component
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B0E=零向量或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _d : LREAL;        // 角度中间值 [度] / angle intermediate in degrees
END_VAR

FC_DL_Atan2Deg := 0.0;                       // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fY <> fY) OR ((fY - fY) <> (fY - fY))    // fY 非有限 / fY is NaN or infinite
   OR (fX <> fX) OR ((fX - fX) <> (fX - fX)) THEN    // fX 非有限 / fX is NaN or infinite
    eErr   := 16#0001_1B0E;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

IF (fY = 0.0) AND (fX = 0.0) THEN            // 零向量：方向无定义 / zero vector: no direction
    eErr   := 16#0001_1B0E;                  // 置零向量故障码 / set zero-vector code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    FC_DL_Atan2Deg := 0.0;                   // 返回 0.0（契约约定）/ return zero per contract
    RETURN;                                  // 提前收口 / early exit
END_IF

_d := ATAN2(fY, fX) * 180.0 / 3.14159265358979323846;    // 四象限反正弦转角度 / atan2 to degrees
IF _d < 0.0 THEN                             // 负角修正到 [0,360) / fold negative into [0,360)
    _d := _d + 360.0;                        // 加一整圈 / add one turn
END_IF

FC_DL_Atan2Deg := _d;                        // 回写 [0,360) 方向角 / write back direction

END_FUNCTION
