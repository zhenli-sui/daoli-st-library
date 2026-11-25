(*==============================================================================
 * 名称 : FC_DL_HypotChk —— 2D 斜边（max/min 比值缩放法防中间量溢出）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回 sqrt(x^2 + y^2)，采用缩放算法：取 a=max(|x|,|y|)、
 *            b=min(|x|,|y|)，结果 = a*sqrt(1+(b/a)^2)。中间量 (b/a)^2 <= 1
 *            有界，杜绝直接 x^2+y^2 在大输入（如 1.0E200）下的中间溢出。
 *            边界处理：任一输入非有限（NaN/±Inf）置 eErr 返回 0.0；两输入
 *            全 0 时返回 0.0（合法结果，bValid 保持 TRUE）。
 * 错误码 : 16#0001_1B10 = 输入非有限（NaN/±Inf）
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/缩放防溢出/除零防护（a=0 特判）｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_HypotChk : LREAL
VAR_INPUT
    fX : LREAL;    // 直角边 X [工程单位] / leg X
    fY : LREAL;    // 直角边 Y [工程单位] / leg Y
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B10=输入非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _fA : LREAL;       // 较大边（缩放基准）[工程单位] / larger leg as scale base
    _fB : LREAL;       // 较小边 [工程单位] / smaller leg
    _fR : LREAL;       // b/a 比值 [无量纲] / ratio b/a, bounded by 1
END_VAR

FC_DL_HypotChk := 0.0;                       // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fX <> fX) OR ((fX - fX) <> (fX - fX))    // fX 非有限 / fX is NaN or infinite
   OR (fY <> fY) OR ((fY - fY) <> (fY - fY)) THEN    // fY 非有限 / fY is NaN or infinite
    eErr   := 16#0001_1B10;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

IF ABS(fX) >= ABS(fY) THEN                   // 按绝对值定大小序 / order by absolute value
    _fA := ABS(fX);                          // 大边 = |fX| / larger leg
    _fB := ABS(fY);                          // 小边 = |fY| / smaller leg
ELSE                                         // 反之 / otherwise
    _fA := ABS(fY);                          // 大边 = |fY| / larger leg
    _fB := ABS(fX);                          // 小边 = |fX| / smaller leg
END_IF

IF _fA = 0.0 THEN                            // 两边全 0：斜边 0（合法）/ both zero: hypot 0
    FC_DL_HypotChk := 0.0;                   // 返回 0.0 / return zero
    RETURN;                                  // 提前收口（防下步除零）/ early exit guards division
END_IF

_fR := _fB / _fA;                            // 比值 <=1，有界无溢出 / ratio bounded by one
FC_DL_HypotChk := _fA * SQRT(1.0 + _fR * _fR);    // 缩放法合成斜边 / scaled hypot

END_FUNCTION
