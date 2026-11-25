(* ===========================================================================
   组件名   : FC_DL_StrainRosettePrincipal
   分类     : DL_Device / 应变花主应变
   一句话   : 由 0°/45°/90° 三向应变算主应变、主方向角与最大剪应变
   复杂度   : 3        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fEpsA 0° 应变 [µε]；fEpsB 45° 应变 [µε]；fEpsC 90° 应变 [µε]
   输出契约 : 返回值 = 第一主应变 ε1 [µε]
              fEps2 第二主应变 [µε]；fAngRad 主方向角 [rad]（−π/2, π/2]
              fShearMax 最大剪应变 [µε]；fCenter 应变圆心 [µε]；xValid 输入有效
   算法说明 : 令 C=(a+c)/2、A=(a−c)/2、B=(2b−a−c)/2，则 ε(θ)=C+A·cos2θ+B·sin2θ
              ε1,2 = C ± √(A²+B²)，2θp = atan2(B, A)，θp = 0.5·atan2(B, A)
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_StrainRosettePrincipal : REAL
VAR_INPUT
    fEpsA : REAL;                      // 0° 向应变 [µε] | 0 deg strain [µε]
    fEpsB : REAL;                      // 45° 向应变 [µε] | 45 deg strain [µε]
    fEpsC : REAL;                      // 90° 向应变 [µε] | 90 deg strain [µε]
END_VAR
VAR_OUTPUT
    fEps2 : REAL;                      // 第二主应变 [µε] | second principal strain [µε]
    fAngRad : REAL;                    // 主方向角 [rad] | principal direction [rad]
    fShearMax : REAL;                  // 最大剪应变 [µε] | maximum shear strain [µε]
    fCenter : REAL;                    // 应变圆心 [µε] | strain circle center [µε]
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fC : REAL;                        // 圆心 (a+c)/2 [µε] | center [µε]
    _fA : REAL;                        // 余弦分量 (a−c)/2 [µε] | cosine component [µε]
    _fB : REAL;                        // 正弦分量 (2b−a−c)/2 [µε] | sine component [µε]
    _fR : REAL;                        // 半径（最大剪应变） [µε] | radius [µε]
    _fAng2 : REAL;                     // 二倍主方向角 [rad] | twice principal angle [rad]
    _fAng : REAL;                      // 主方向角 [rad] | principal angle [rad]
END_VAR

// ---- 输出预置 ----
fEps2 := 0.0;
fAngRad := 0.0;
fShearMax := 0.0;
fCenter := 0.0;
xValid := FALSE;
FC_DL_StrainRosettePrincipal := 0.0;

// ---- 非有限值拦截 ----
IF (fEpsA <> fEpsA) OR ((fEpsA - fEpsA) <> (fEpsA - fEpsA)) THEN
    RETURN;
END_IF
IF (fEpsB <> fEpsB) OR ((fEpsB - fEpsB) <> (fEpsB - fEpsB)) THEN
    RETURN;
END_IF
IF (fEpsC <> fEpsC) OR ((fEpsC - fEpsC) <> (fEpsC - fEpsC)) THEN
    RETURN;
END_IF

// ---- 应变圆三要素 ----
_fC := (fEpsA + fEpsC) * 0.5;
_fA := (fEpsA - fEpsC) * 0.5;
_fB := (2.0 * fEpsB - fEpsA - fEpsC) * 0.5;
fCenter := _fC;
_fR := SQRT(_fA * _fA + _fB * _fB);                // 平方和非负，SQRT 安全
fShearMax := _fR;

// ---- 主应变 ----
FC_DL_StrainRosettePrincipal := _fC + _fR;
fEps2 := _fC - _fR;

// ---- 手工 atan2：避免依赖非标准 ATAN2，先判分母再补象限 ----
_fAng2 := 0.0;
IF ABS(_fA) < 0.000000001 THEN
    IF _fB > 0.0 THEN
        _fAng2 := 1.570796327;                     // 分母近零且 B>0 → +π/2
    ELSIF _fB < 0.0 THEN
        _fAng2 := -1.570796327;                    // 分母近零且 B<0 → −π/2
    END_IF
ELSE
    _fAng2 := ATAN(_fB / _fA);                     // 分母已守卫
    IF _fA < 0.0 THEN
        IF _fB >= 0.0 THEN
            _fAng2 := _fAng2 + 3.141592654;        // 第二象限补偿
        ELSE
            _fAng2 := _fAng2 - 3.141592654;        // 第三象限补偿
        END_IF
    END_IF
END_IF

// ---- 主方向角：除以 2 并归一化到 (−π/2, π/2] ----
_fAng := _fAng2 * 0.5;
IF _fAng > 1.570796327 THEN
    _fAng := _fAng - 3.141592654;
ELSIF _fAng <= -1.570796327 THEN
    _fAng := _fAng + 3.141592654;
END_IF
fAngRad := _fAng;

xValid := TRUE;
END_FUNCTION
