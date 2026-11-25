(*==============================================================================
 * 名称 : FC_DL_SinDeg —— 角度制正弦（度入参，弧度内部换算）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回 sin(fDeg)：内部换算弧度 fDeg * PI / 180 后调用标准 SIN，
 *            PI 取 LREAL 字面量 3.14159265358979323846（双精度最近舍入）。
 *            边界处理：输入非有限（NaN：f<>f；±Inf：(f-f)<>(f-f)）置 eErr
 *            返回 0.0；|fDeg|>1.0E12 时大角换算精度塌陷，同置 eErr 返回 0.0。
 * 错误码 : 16#0001_1B09 = 输入非有限（NaN/±Inf）或角度量超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/量程防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_SinDeg : LREAL
VAR_INPUT
    fDeg : LREAL;    // 输入角 [度] / input angle in degrees
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B09=输入非有限或超量程 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR

FC_DL_SinDeg := 0.0;                         // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fDeg <> fDeg) OR ((fDeg - fDeg) <> (fDeg - fDeg))    // NaN 或 ±Inf / NaN or infinite
   OR (ABS(fDeg) > 1.0E12) THEN              // 超安全量程（精度塌陷防护）/ beyond safe range
    eErr   := 16#0001_1B09;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

FC_DL_SinDeg := SIN(fDeg * 3.14159265358979323846 / 180.0);    // 度转弧度后取正弦 / degrees to radians, then sine

END_FUNCTION
