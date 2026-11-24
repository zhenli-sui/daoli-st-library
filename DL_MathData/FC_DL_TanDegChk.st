(*==============================================================================
 * 名称 : FC_DL_TanDegChk —— 角度制正切（含 |cos| 不可定义防护）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回 tan(fDeg)：内部换算弧度后先求 COS 判可定义性，|cos|<1.0E-12
 *            （90°/270° 等渐近角附近）时判不可定义，返回 0.0、bValid=FALSE
 *            并置 eErr；可定义时返回标准 TAN。
 *            边界处理：输入非有限（NaN/±Inf）或 |fDeg|>1.0E12 置 eErr 返回 0.0。
 * 错误码 : 16#0001_1B0B = |cos|<1.0E-12（正切不可定义），或输入非有限 / 超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/除零防护（渐近角）/量程防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_TanDegChk : LREAL
VAR_INPUT
    fDeg : LREAL;    // 输入角 [度] / input angle in degrees
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B0B=不可定义或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _fRad : LREAL;     // 换算后的弧度角 [rad] / converted angle in radians
    _fCos : LREAL;     // 余弦值（可定义性判据）/ cosine value used as guard
END_VAR

FC_DL_TanDegChk := 0.0;                      // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fDeg <> fDeg) OR ((fDeg - fDeg) <> (fDeg - fDeg))    // NaN 或 ±Inf / NaN or infinite
   OR (ABS(fDeg) > 1.0E12) THEN              // 超安全量程 / beyond safe range
    eErr   := 16#0001_1B0B;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

_fRad := fDeg * 3.14159265358979323846 / 180.0;    // 度转弧度 / degrees to radians
_fCos := COS(_fRad);                         // 求余弦作渐近防护判据 / cosine as asymptote guard

IF ABS(_fCos) < 1.0E-12 THEN                 // 渐近角附近不可定义 / near-asymptote undefined
    eErr   := 16#0001_1B0B;                  // 置不可定义码 / set undefined code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    FC_DL_TanDegChk := 0.0;                  // 返回 0.0（契约约定）/ return zero per contract
    RETURN;                                  // 提前收口 / early exit
END_IF

FC_DL_TanDegChk := TAN(_fRad);               // 可定义域内取正切 / tangent in defined domain

END_FUNCTION
