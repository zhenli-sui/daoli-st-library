(*==============================================================================
 * 名称 : FC_DL_AsinDegChk —— 反正弦 → 角度（输入钳位 [-1,1]，越界仍按钳位计算）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回 asin(x) 的角度制结果 [-90,90]。输入越出 [-1,1] 时钳位到
 *            边界后仍按钳位值计算（bValid=FALSE、eErr 置码提示越界），不产生
 *            NaN。恒等式 asin(x)=atan2(x, sqrt(1-x^2))（弧度）转角度输出，
 *            纯 ATAN2/SQRT 内联实现，无库内跨件依赖。
 *            边界处理：输入非有限（NaN/±Inf）置 eErr 返回 0.0（不钳位计算）。
 * 错误码 : 16#0001_1B0C = 输入越出 [-1,1]（已钳位计算），或输入非有限（NaN/±Inf）
 *          eErr=0 且 bValid=TRUE 表示输入在域内、返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/域钳位防 NaN ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AsinDegChk : LREAL
VAR_INPUT
    fX : LREAL;    // 正弦值输入 [-1,1]，越界钳位 / sine value input, clamped into [-1,1]
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B0C=越界钳位或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=输入在域内且返回值可用 / TRUE when input in domain and result usable
END_VAR
VAR
    _x   : LREAL;      // 钳位后的输入 [无量纲] / clamped input
    _fR  : LREAL;      // 弧度制反正弦结果 [rad] / arcsine result in radians
END_VAR

FC_DL_AsinDegChk := 0.0;                     // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fX <> fX) OR ((fX - fX) <> (fX - fX)) THEN    // NaN 或 ±Inf / NaN or infinite
    eErr   := 16#0001_1B0C;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

_x := fX;                                    // 取输入 / take input
IF _x > 1.0 THEN                             // 上越界钳位 / clamp upper
    _x := 1.0;                               // 钳到 +1 / clamp to +1
    eErr   := 16#0001_1B0C;                  // 置越界码 / set out-of-domain code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 提示越界（仍按钳位值出结果）/ flag clamped compute
ELSIF _x < -1.0 THEN                         // 下越界钳位 / clamp lower
    _x := -1.0;                              // 钳到 -1 / clamp to -1
    eErr   := 16#0001_1B0C;                  // 置越界码 / set out-of-domain code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 提示越界（仍按钳位值出结果）/ flag clamped compute
END_IF

_fR := ATAN2(_x, SQRT(1.0 - _x * _x));       // asin(x)=atan2(x,sqrt(1-x^2))，弧度 / arcsine via atan2
FC_DL_AsinDegChk := _fR * 180.0 / 3.14159265358979323846;    // 弧度转角度 / radians to degrees

END_FUNCTION
