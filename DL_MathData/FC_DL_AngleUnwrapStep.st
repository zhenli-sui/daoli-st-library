(*==============================================================================
 * 名称 : FC_DL_AngleUnwrapStep —— 增量解卷绕（跨多圈连续跟踪，步进 [-180,180)）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 编码器增量解卷绕：取 fRaw-fPrev 的最短弧差作为本拍步进
 *            fStep∈[-180,180)，返回 fAccum + fStep 的累计角（不卷绕、跨多圈
 *            连续跟踪）。调用方须把返回值与 fStep 存为下一拍的 fAccum/fPrev。
 *            边界处理：任一输入非有限（NaN/±Inf）或 |量|>1.0E12 置 eErr
 *            返回 fAccum 原值（冻结本拍步进，不引入伪增量）。
 * 错误码 : 16#0001_1B08 = 输入非有限（NaN/±Inf）或角度量超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示步进与累计角均可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，跨拍状态由调用方持有，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/量程防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AngleUnwrapStep : LREAL
VAR_INPUT
    fRaw   : LREAL;    // 本拍原始角 [度] / raw angle of this cycle
    fPrev  : LREAL;    // 上一拍原始角（调用方持有）[度] / previous raw angle, caller-held
    fAccum : LREAL;    // 累计角（调用方持有）[度] / accumulated angle, caller-held
END_VAR
VAR_OUTPUT
    fStep  : LREAL;    // 本拍步进 [-180,180) [度] / step of this cycle within [-180,180)
    eErr   : UDINT;    // 故障码，0=正常，1B08=输入非有限或超量程 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=步进与累计角可用 / TRUE when step and result are usable
END_VAR
VAR
    _d : LREAL;        // 本拍原始差值 [度] / raw delta of this cycle
END_VAR

fStep := 0.0;                                // 步进预设 0.0 / preset step to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag
FC_DL_AngleUnwrapStep := fAccum;             // 返回值预设为累计角原值 / preset return to accum

IF (fRaw <> fRaw) OR ((fRaw - fRaw) <> (fRaw - fRaw))      // fRaw 非有限 / NaN or infinite
   OR (fPrev <> fPrev) OR ((fPrev - fPrev) <> (fPrev - fPrev))   // fPrev 非有限 / NaN or infinite
   OR (fAccum <> fAccum) OR ((fAccum - fAccum) <> (fAccum - fAccum))  // fAccum 非有限 / NaN or infinite
   OR (ABS(fRaw) > 1.0E12) OR (ABS(fPrev) > 1.0E12) THEN     // 角度量超安全量程 / beyond safe range
    eErr   := 16#0001_1B08;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // 冻结本拍，返回 fAccum 原值 / freeze, return accum unchanged
END_IF

_d := fRaw - fPrev;                          // 本拍原始差值 / raw delta
_d := _d - 360.0 * TRUNC(_d / 360.0);        // 整圈截断缩圈 / strip whole turns
IF _d >= 180.0 THEN                          // 上越界修正（取短弧步进）/ fix upper overflow
    _d := _d - 360.0;                        // 减一整圈 / subtract one turn
END_IF
IF _d < -180.0 THEN                          // 下越界修正 / fix lower overflow
    _d := _d + 360.0;                        // 加一整圈 / add one turn
END_IF

fStep := _d;                                 // 回写本拍步进 / write back step
FC_DL_AngleUnwrapStep := fAccum + _d;        // 累计角连续跟踪（不卷绕）/ accumulate unwrapped

END_FUNCTION
