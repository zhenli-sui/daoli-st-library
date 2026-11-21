(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SolarPositionCalc
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（SIN / COS / TAN / ASIN / ATAN2 / ABS / LIMIT）
 * 功能描述 (Function)   : 由本地标准时（年 / 月 / 日 / 时 / 分）、纬度、经度与时区偏移，
 *                         按 NOAA 公开的简化天文算法求太阳赤纬、均时差、真太阳时、时角、
 *                         高度角与方位角。现场用途：光伏跟踪支架逆跟踪角、建筑遮阳帘、
 *                         日光温室补光窗口、日照辐射计的姿态修正。
 *                         方位角约定：正北 0 度、顺时针递增（东 90、南 180、西 270）。
 *                         天顶约定：高度角高于 89.5 度（或高度角余弦小于 0.00873）时，
 *                         方位角在物理上不可辨，本件统一置 180.0 度（正南）并保持该约定不变，
 *                         上层如另有偏好须在调用侧追加判别，不得依赖本件给出「就近方位」。
 * 出口契约 (Exit)       : 函数返回值 = 太阳高度角（与出口 fElevation 同值）；输入域外一律
 *                         返回 0.0 且 bValid = FALSE，绝不输出「看起来合理」的错值。
 * 开源溯源 (Origin)     : 来源标签 lgf-datetimer。许可证：LGF 为免费闭源发布，未取得源码，
 *                         不构成衍生作品。借鉴点仅为「Date and Timer 组把日历天数、周数、
 *                         天文钟、多段定时并列」的分类骨架，以及天文钟「本地时间 + 经纬度
 *                         求太阳位置」的参数域划分。全部公式取 NOAA 公开算法（公共领域），
 *                         实现、常量、归一策略、域守护与错误码 100% clean-room 自有。
 * 码位说明 (Codes)      : 信息级 16#0001_0136（年月时分 / 经纬度 / 时区域外）/
 *                         16#0001_0137（日超出当月实际天数，含闰年判定）。共 2 码，
 *                         落在 R12 计划第 1.2 节本件码段内，无段外码。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library 三角函数与 LIMIT
 * 红线自检 (Redline)    : 1 ✓ 零全局变量表依赖、零外部变量声明、零物理地址
 *                         2 ✓ 纯 IEC 61131-3，无指针、无厂商库
 *                         3 ✓ 经纬度与时区域外早退、ASIN 入参钳位、ATAN2 双零守护、
 *                             时角与方位角归一用条件加减（不用 MOD）、循环带守卫
 *                         4 ✓ 全变量中英双语同行注释
 *                         5 N/A 纯函数无状态机 ｜ 6 N/A 无定时器与边沿实例
 *                         7 ✓ END_FUNCTION 位于文件最后有效行
 * 算法出处与精度声明    :
 *   NOAA Solar Calculator 公开的傅里叶级数（赤纬 7 项、均时差 5 项），
 *   在 1970~2100 年、纬度绝对值不超过 90 度的域内，高度角误差优于 0.5 度。
 *   本件不做大气折射修正（折射在地平线附近可达 0.5 度），日出日落判据请以
 *   bSunUp 为「几何高度角为正」而非「可见日面出地平」。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R12 · Level 0 DL_MathData 天文钟族）
 *============================================================================*)
FUNCTION FC_DL_SolarPositionCalc : REAL
VAR_INPUT
    nYear        : INT;                  // 年 [年]，域 1970~2100 / Year, 1970..2100
    nMonth       : INT;                  // 月 [月]，域 1~12 / Month, 1..12
    nDay         : INT;                  // 日 [日]，域 1~31，按当月实际天数校验 / Day, 1..31, checked against the month
    nHour        : INT;                  // 时 [h]，域 0~23，本地标准时 / Hour, local standard time
    nMinute      : INT;                  // 分 [min]，域 0~59 / Minute, 0..59
    fLatitude    : REAL;                 // 纬度 [度]，北纬为正，域 −90~90 / Latitude in degrees, north positive
    fLongitude   : REAL;                 // 经度 [度]，东经为正，域 −180~180 / Longitude in degrees, east positive
    nUtcOffsetMin : INT := 480;          // 本地时区偏移 [min]，东八区 = 480 / Time zone offset in minutes
END_VAR
VAR_OUTPUT
    fDeclination : REAL;                 // 太阳赤纬 [度]，约 −23.45~+23.45 / Solar declination in degrees
    fHourAngle   : REAL;                 // 时角 [度]，正午为 0，下午为正 / Hour angle in degrees
    fElevation   : REAL;                 // 太阳高度角 [度]，地平线上为正 / Solar elevation in degrees
    fAzimuth     : REAL;                 // 方位角 [度]，正北 0 顺时针增 / Azimuth clockwise from north
    fEquationOfTime : REAL;              // 均时差 [min] / Equation of time in minutes
    bSunUp       : BOOL;                 // 高度角大于 0 = TRUE / Sun above the horizon
    uErrorId     : UDINT;                // 事件码，0 = 无事件 / Event code, zero means none
    bValid       : BOOL;                 // 日期、时区、经纬度均合法 = TRUE / All inputs legal
END_VAR
VAR
    nDoy         : INT;                  // 年内日序，1 月 1 日 = 1 [日] / Day of year, January the first is one
    fGamma       : REAL;                 // 小数年角 [rad] / Fractional year angle in radians
    fDeclRad     : REAL;                 // 赤纬中间量 [rad] / Declination in radians
    fEotMin      : REAL;                 // 均时差中间量 [min] / Equation of time intermediate
    fTstMin      : REAL;                 // 真太阳时 [min] / True solar time in minutes
    fHaDeg       : REAL;                 // 时角中间量 [度] / Hour angle intermediate in degrees
    fLatRad      : REAL;                 // 纬度 [rad] / Latitude in radians
    fSinElev     : REAL;                 // 高度角正弦中间量 [-] / Sine of the elevation
    fCosElev     : REAL;                 // 高度角余弦中间量 [-] / Cosine of the elevation
    fY           : REAL;                 // 方位角反正切分子 [-] / Azimuth arc tangent numerator
    fX           : REAL;                 // 方位角反正切分母 [-] / Azimuth arc tangent denominator
    fAzRad       : REAL;                 // 方位角中间量 [rad] / Azimuth in radians
    nDayMax      : INT;                  // 当月天数 [日] / Days in the month
    bLeap        : BOOL;                 // 闰年标志 / Leap year flag
    i            : INT;                  // 月份累加索引 [月] / Month accumulation index
    nGuard       : DINT;                 // 循环守卫 / Loop guard
END_VAR
VAR CONSTANT
    DL_RAD2DEG   : REAL := 57.29577951;  // 弧度转度 [度] / Radians to degrees
    DL_DEG2RAD   : REAL := 0.01745329;   // 度转弧度 [rad] / Degrees to radians
    DL_PI        : REAL := 3.14159265;   // 圆周率 [-] / Pi
    DL_DAYS_YEAR : REAL := 365.0;        // 平年天数 [日] / Days in a common year
    DL_TWO_PI    : REAL := 6.28318531;   // 二倍圆周率 [rad] / Two pi
    DL_HA_LIM    : REAL := 180.0;        // 时角归一上限 [度] / Hour angle normalisation bound
    DL_AZ_FULL   : REAL := 360.0;        // 方位角整圈 [度] / Full azimuth circle in degrees
    DL_SIN_LIM   : REAL := 1.0;          // 反正弦定义域边界 [-] / Arc sine domain bound
    DL_ZENITH_DEG : REAL := 89.5;        // 天顶不可辨阈值 [度] / Zenith ambiguity threshold in degrees
    DL_COS_MIN   : REAL := 0.00873;      // 天顶不可辨的余弦阈值 [-] / Cosine threshold for the zenith case
    DL_EPS       : REAL := 1.0E-6;       // 浮点判零容差 [-] / Float zero tolerance
    DL_LAT_MAX   : REAL := 90.0;         // 纬度绝对值上限 [度] / Latitude absolute bound
    DL_LON_MAX   : REAL := 180.0;        // 经度绝对值上限 [度] / Longitude absolute bound
    DL_UTC_MAX   : INT  := 840;          // 时区偏移绝对值上限 [min] / Time zone absolute bound
    DL_YEAR_MIN  : INT  := 1970;         // 年份下限 [年] / Lower year bound
    DL_YEAR_MAX  : INT  := 2100;         // 年份上限 [年] / Upper year bound
    DL_GUARD_MAX : DINT := 16;           // 循环守卫上限 [次] / Loop guard limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜结果预置：全部角度出口先落 0.0，早退路径不留未初始化量
 *      Safe preset: all angle outputs fall back to 0.0 on every early exit
 *-----------------------------------------------------------------------------*)
FC_DL_SolarPositionCalc := 0.0;
fDeclination    := 0.0;
fHourAngle      := 0.0;
fElevation      := 0.0;
fAzimuth        := 0.0;
fEquationOfTime := 0.0;
bSunUp          := FALSE;
uErrorId        := 16#0000_0000;
bValid          := FALSE;
nDoy            := 0;
nDayMax         := 0;
bLeap           := FALSE;
nGuard          := 0;
i               := 1;

(*------------------------------------------------------------------------------
 * 段 2｜日期时间域闸门：年月时分越界一律早退（码 0136），不做任何夹取
 *      Date and time domain gates: out of range exits with 0136, never clamped
 *-----------------------------------------------------------------------------*)
IF (nYear < DL_YEAR_MIN) OR (nYear > DL_YEAR_MAX) THEN
    uErrorId := 16#0001_0136;
    RETURN;
END_IF
IF (nMonth < 1) OR (nMonth > 12) THEN
    uErrorId := 16#0001_0136;
    RETURN;
END_IF
IF (nHour < 0) OR (nHour > 23) THEN
    uErrorId := 16#0001_0136;
    RETURN;
END_IF
IF (nMinute < 0) OR (nMinute > 59) THEN
    uErrorId := 16#0001_0136;
    RETURN;
END_IF
IF (nUtcOffsetMin < -DL_UTC_MAX) OR (nUtcOffsetMin > DL_UTC_MAX) THEN
    uErrorId := 16#0001_0136;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜地理位置域闸门：写成「正向区间取反」形式，非有限值（NaN / Inf）自然被拒
 *      Geographic gates written as inverted positive ranges so NaN is rejected too
 *      NaN 参与任何比较均为假，取反后必为真，无需额外的自比较判据
 *      NaN compares false with everything, so the inverted range catches it
 *-----------------------------------------------------------------------------*)
IF NOT ((fLatitude >= -DL_LAT_MAX) AND (fLatitude <= DL_LAT_MAX)) THEN
    uErrorId := 16#0001_0136;
    RETURN;
END_IF
IF NOT ((fLongitude >= -DL_LON_MAX) AND (fLongitude <= DL_LON_MAX)) THEN
    uErrorId := 16#0001_0136;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜闰年与当月天数：4 / 100 / 400 三级判定，日越界早退（码 0137）
 *      Leap year by the 4 / 100 / 400 rule, day overflow exits with 0137
 *-----------------------------------------------------------------------------*)
bLeap := ((nYear MOD 4 = 0) AND (nYear MOD 100 <> 0)) OR (nYear MOD 400 = 0);

IF nMonth = 2 THEN
    IF bLeap THEN
        nDayMax := 29;
    ELSE
        nDayMax := 28;
    END_IF
ELSIF (nMonth = 4) OR (nMonth = 6) OR (nMonth = 9) OR (nMonth = 11) THEN
    nDayMax := 30;
ELSE
    nDayMax := 31;
END_IF

IF (nDay < 1) OR (nDay > nDayMax) THEN
    uErrorId := 16#0001_0137;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜年内日序：逐月累加（不查表，规避各平台常量数组初始化差异），带守卫
 *      Day of year by month accumulation with a guard, no lookup table
 *-----------------------------------------------------------------------------*)
nDoy   := nDay;
nGuard := 0;
FOR i := 1 TO (nMonth - 1) DO
    IF nGuard >= DL_GUARD_MAX THEN
        EXIT;
    END_IF
    nGuard := nGuard + 1;
    IF i = 2 THEN
        IF bLeap THEN
            nDoy := nDoy + 29;
        ELSE
            nDoy := nDoy + 28;
        END_IF
    ELSIF (i = 4) OR (i = 6) OR (i = 9) OR (i = 11) THEN
        nDoy := nDoy + 30;
    ELSE
        nDoy := nDoy + 31;
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 6｜小数年角与赤纬、均时差（NOAA 公开傅里叶级数）
 *      Fractional year angle, declination and equation of time
 *-----------------------------------------------------------------------------*)
fGamma := DL_TWO_PI / DL_DAYS_YEAR * (INT_TO_REAL(nDoy - 1) + (INT_TO_REAL(nHour) - 12.0) / 24.0);

fDeclRad := 0.006918
          - 0.399912 * COS(fGamma)
          + 0.070257 * SIN(fGamma)
          - 0.006758 * COS(2.0 * fGamma)
          + 0.000907 * SIN(2.0 * fGamma)
          - 0.002697 * COS(3.0 * fGamma)
          + 0.00148  * SIN(3.0 * fGamma);
fDeclination := fDeclRad * DL_RAD2DEG;

fEotMin := 229.18 * (0.000075
        + 0.001868 * COS(fGamma)
        - 0.032077 * SIN(fGamma)
        - 0.014615 * COS(2.0 * fGamma)
        - 0.040849 * SIN(2.0 * fGamma));
fEquationOfTime := fEotMin;

(*------------------------------------------------------------------------------
 * 段 7｜真太阳时与时角：经度按每度四分钟折算，时区偏移直接扣减
 *      True solar time and hour angle: four minutes per degree of longitude
 *-----------------------------------------------------------------------------*)
fTstMin := INT_TO_REAL(nHour * 60 + nMinute) + fEotMin + 4.0 * fLongitude - INT_TO_REAL(nUtcOffsetMin);
fHaDeg  := 15.0 * (fTstMin / 60.0 - 12.0);

(* 时角归一：条件加减，禁用取模（负数取余在各平台口径不一致）*)
(* Hour angle normalisation by conditional add and subtract, never by MOD *)
nGuard := 0;
WHILE (fHaDeg > DL_HA_LIM) AND (nGuard < DL_GUARD_MAX) DO
    fHaDeg := fHaDeg - DL_AZ_FULL;
    nGuard := nGuard + 1;
END_WHILE;
WHILE (fHaDeg < -DL_HA_LIM) AND (nGuard < DL_GUARD_MAX) DO
    fHaDeg := fHaDeg + DL_AZ_FULL;
    nGuard := nGuard + 1;
END_WHILE;
fHourAngle := fHaDeg;

(*------------------------------------------------------------------------------
 * 段 8｜高度角：先钳正弦到定义域，再取反正弦，杜绝 NaN 传播
 *      Elevation: clamp the sine into the arc sine domain before calling ASIN
 *-----------------------------------------------------------------------------*)
fLatRad := fLatitude * DL_DEG2RAD;
fSinElev := SIN(fLatRad) * SIN(fDeclRad)
          + COS(fLatRad) * COS(fDeclRad) * COS(fHaDeg * DL_DEG2RAD);
fSinElev := LIMIT(-DL_SIN_LIM, fSinElev, DL_SIN_LIM);

fElevation := ASIN(fSinElev) * DL_RAD2DEG;
fCosElev   := COS(fElevation * DL_DEG2RAD);

(*------------------------------------------------------------------------------
 * 段 9｜方位角：反正切求「相对正南」的偏角，再加 180 度换算到正北起算
 *      Azimuth: arc tangent gives the offset from south, plus 180 degrees
 *      公式成立前提为赤纬绝对值不超过 23.45 度，切不可把本式复用到高赤纬天体
 *      The formula assumes a declination within 23.45 degrees, never reuse it widely
 *-----------------------------------------------------------------------------*)
fY := SIN(fHaDeg * DL_DEG2RAD);
fX := COS(fHaDeg * DL_DEG2RAD) * SIN(fLatRad) - TAN(fDeclRad) * COS(fLatRad);

IF (ABS(fX) < DL_EPS) AND (ABS(fY) < DL_EPS) THEN
    fAzRad := 0.0;
ELSE
    fAzRad := ATAN2(fY, fX);
END_IF

fAzimuth := fAzRad * DL_RAD2DEG + 180.0;

(* 天顶不可辨：高度角余弦趋零时方位角无物理意义，统一置正南 *)
(* Zenith ambiguity: the azimuth is meaningless near the zenith, forced to south *)
IF (fElevation > DL_ZENITH_DEG) OR (fCosElev < DL_COS_MIN) THEN
    fAzimuth := 180.0;
ELSE
    nGuard := 0;
    WHILE (fAzimuth < 0.0) AND (nGuard < DL_GUARD_MAX) DO
        fAzimuth := fAzimuth + DL_AZ_FULL;
        nGuard   := nGuard + 1;
    END_WHILE;
    WHILE (fAzimuth >= DL_AZ_FULL) AND (nGuard < DL_GUARD_MAX) DO
        fAzimuth := fAzimuth - DL_AZ_FULL;
        nGuard   := nGuard + 1;
    END_WHILE;
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜日出判定与出口收口：几何高度角为正即视为在地平线之上
 *      Sun up verdict and output closure based on the geometric elevation
 *-----------------------------------------------------------------------------*)
bSunUp := fElevation > 0.0;
bValid := TRUE;

FC_DL_SolarPositionCalc := fElevation;
END_FUNCTION
