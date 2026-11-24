(*==============================================================================
 * 名称 : FC_DL_AngleToCompass —— 方位角转 16 方位码（0=北，顺时针）与 8 方位码
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将方位角归一到 [0,360) 后按每扇区 22.5° 映射到 16 方位码
 *            0..15（0=北、4=东、8=南、12=西，顺时针），并以 45° 扇区同步
 *            给出 8 方位码 nBand 0..7（0=北、2=东、4=南、6=西），供下游
 *            粗分级直接使用。扇区中心对齐：加半扇区 11.25°/22.5° 后取整。
 *            边界处理：输入非有限（NaN/±Inf）或 |角|>1.0E12 置 eErr 返回 0。
 * 错误码 : 16#0001_1B05 = 输入非有限（NaN/±Inf）或角度量超安全量程 ±1.0E12
 *          eErr=0 且 bValid=TRUE 表示两码均可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/量程防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_AngleToCompass : INT
VAR_INPUT
    fAngle : LREAL;    // 方位角（0=北，顺时针为正）[度] / bearing angle, clockwise from north
END_VAR
VAR_OUTPUT
    nBand  : INT;      // 8 方位码 0..7（0=北）/ 8-point compass code
    eErr   : UDINT;    // 故障码，0=正常，1B05=输入非有限或超量程 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=两码均可用 / TRUE when both codes are usable
END_VAR
VAR
    _r    : LREAL;     // 归一后的方位角 [度] / normalized bearing
    _n16  : LREAL;     // 16 扇区整数值 / 16-sector integer value
    _n8   : LREAL;     // 8 扇区整数值 / 8-sector integer value
END_VAR

FC_DL_AngleToCompass := 0;                   // 16 码预设 0（北）/ preset 16-code to north
nBand := 0;                                  // 8 码预设 0（北）/ preset 8-code to north
eErr  := 16#0000_0000;                       // 故障码清零 / clear error code
bError:= FALSE;                              // 故障标志清零 / clear error flag
bValid:= TRUE;                               // 预设输出可用 / preset valid flag

IF (fAngle <> fAngle) OR ((fAngle - fAngle) <> (fAngle - fAngle))    // 非有限 / NaN or infinite
   OR (ABS(fAngle) > 1.0E12) THEN            // 超安全量程 / beyond safe range
    eErr   := 16#0001_1B05;                  // 置故障码 / set error code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 输出不可用 / outputs not usable
    RETURN;                                  // 返回 0 / return north codes
END_IF

_r := fAngle;                                // 取输入角 / take input
_r := _r - 360.0 * TRUNC(_r / 360.0);        // 整圈截断缩圈 / strip whole turns
IF _r < 0.0 THEN                             // 负角修正 / fix negative angle
    _r := _r + 360.0;                        // 加一整圈，得 [0,360) / add one turn
END_IF

_n16 := TRUNC((_r + 11.25) / 22.5);          // 16 扇区中心对齐取整 / 16-sector center-aligned
_n8  := TRUNC((_r + 22.5) / 45.0);           // 8 扇区中心对齐取整 / 8-sector center-aligned

FC_DL_AngleToCompass := DINT_TO_INT(LREAL_TO_DINT(_n16) MOD 16);    // 折回 0..15 / fold into 0..15
nBand := DINT_TO_INT(LREAL_TO_DINT(_n8) MOD 8);           // 折回 0..7 / fold into 0..7

END_FUNCTION
