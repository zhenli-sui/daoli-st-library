(*
  DL Factory R83 | FC_DL_RegisterErrorCalc
  功能：把纵向与横向套准误差合成偏差幅值与方位角，并按合成允差判定超差。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_RegisterErrorCalc : REAL
VAR_INPUT
    fErrMd    : REAL; // 纵向（走料方向）套准误差，正=超前 [mm] / Machine-direction error [mm]
    fErrCd    : REAL; // 横向（幅宽方向）套准误差，正=右偏 [mm] / Cross-direction error [mm]
    fTolMm    : REAL; // 套准允差（合成偏差上限）[mm] / Tolerance on composite error [mm]
    fSpeedMpm : REAL; // 料带走料速度 [m/min] / Web speed [m/min]
END_VAR
VAR_OUTPUT
    fErrComp  : REAL; // 合成偏差幅值 [mm] / Composite error magnitude [mm]
    fErrAngle : REAL; // 误差方位角，0=纵向 90=横向 [°] / Error azimuth [deg]
    xOutTol   : BOOL; // 超差标志（TRUE=超差需调整）/ Out-of-tolerance flag
END_VAR
VAR
    fSq  : REAL; // 误差平方和 [mm²] / Sum of squared errors [mm^2]
    fRad : REAL; // 方位角弧度 [rad] / Azimuth in radians [rad]
    fPi  : REAL := 3.14159265358979; // 圆周率常量，弧度转度用（R19 已引用）/ Pi constant, referenced
END_VAR
// 出口预置：三出口统一预置（R256）
fErrComp := 0.0; fErrAngle := 0.0; xOutTol := FALSE;
// 非有限拦截 + 量纲自检：允差必须为正（R20/R21）
IF NOT (fErrMd > -1.0E30 AND fErrMd < 1.0E30) OR NOT (fErrCd > -1.0E30 AND fErrCd < 1.0E30) OR NOT (fTolMm > -1.0E30 AND fTolMm < 1.0E30) OR NOT (fSpeedMpm > -1.0E30 AND fSpeedMpm < 1.0E30) OR fTolMm <= 0.0 THEN
    FC_DL_RegisterErrorCalc := -1.0; RETURN;   // 哨兵 -1：非有限或允差非正 / Sentinel -1
END_IF
// 合成偏差：欧氏范数，开方前非负闸（R4）
fSq := fErrMd * fErrMd + fErrCd * fErrCd;  // 平方和 [mm²] / Sum of squares [mm^2]
IF fSq >= 0.0 THEN                  // 开方前非负闸 / Gate before square root
    fErrComp := SQRT(fSq);          // 合成偏差 [mm] / Composite error [mm]
ELSE
    fErrComp := 0.0;                // 浮点异常防御缺省 / Float anomaly default
END_IF
// 方位角：纵向分量为分母，显式零闸后取反正切，纯横向走 ±90° 分支
IF ABS(fErrMd) > 1.0E-6 THEN        // 分母零闸（R4/R21）/ Denominator zero gate
    fRad      := ATAN(fErrCd / fErrMd);   // 象限角 [-π/2, π/2] / Quadrant angle [rad]
    fErrAngle := fRad * 180.0 / fPi;      // 转度 [°] / Convert to degrees [deg]
ELSIF fErrCd >= 0.0 THEN
    fErrAngle := 90.0;              // 纯横向正向 [°] / Pure positive cross direction
ELSE
    fErrAngle := -90.0;             // 纯横向负向 [°] / Pure negative cross direction
END_IF
// 超差判定：合成偏差严格大于允差，禁浮点等号比较
xOutTol := fErrComp > fTolMm;       // 超差布尔 / Out-of-tolerance boolean
FC_DL_RegisterErrorCalc := fErrComp; // 返回合成偏差 [mm] / Return composite error [mm]
END_FUNCTION
