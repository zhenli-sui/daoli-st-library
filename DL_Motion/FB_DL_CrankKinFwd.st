// FB_DL_CrankKinFwd v1.0.0
// 开源溯源：self-cleanroom / 公开运动学公式（曲柄滑块机构）
(*
  道莅工业代码库 | DL_Motion | FB_DL_CrankKinFwd
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 曲柄滑块机构正运动学：曲柄角 θ → 滑块位移 x = r·cosθ +
        sqrt(L² − r²·sin²θ)；附角速度输入时的滑块速度解析导数
        ẋ = −ω·r·sinθ·(1 + r·cosθ/sqrt(L² − r²·sin²θ))
  邻件关系: robot 族（监视/抓取验证）与本件无运动学属主重叠；并联件
            FB_DL_DeltaRobotIk 为逆解（末端→关节），本件为正解
            （关节→末端），方向互补
  机构约束: 连杆长 L 必须大于曲柄半径 r（L−r > 容差），否则机构无法
            整周回转，判组态故障拒算
*)
FUNCTION_BLOCK FB_DL_CrankKinFwd
VAR_INPUT
    bEnable    : BOOL := FALSE;             // 使能（FALSE 输出保持零）/ Enable
    fCrankDeg  : REAL := 0.0;               // 曲柄角 θ [deg]，0=TDC，域 ±1E6 / Crank angle [deg], 0 at TDC
    fOmegaRadS : REAL := 0.0;               // 曲柄角速度 ω [rad/s]，0 时速度输出零 / Crank angular velocity [rad/s]
    fCrankR    : REAL := 25.0;              // 曲柄半径 r [mm]，域 > 0 / Crank radius [mm]
    fRodL      : REAL := 100.0;             // 连杆长 L [mm]，域 > r + 容差 / Connecting rod length [mm]
    fEps       : REAL := 1.0E-6;            // 判零/判界容差 [mm] / Tolerance [mm]
END_VAR
VAR_OUTPUT
    fSliderPos : REAL;                      // 滑块位移（距曲轴心）[mm] / Slider position from crank center [mm]
    fSliderVel : REAL;                      // 滑块速度 [mm/s] / Slider velocity [mm/s]
    bValid     : BOOL;                      // 结果有效回执 [-] / Result validity receipt
    bError     : BOOL;                      // 故障标志（机构约束违反）/ Fault flag (mechanism constraint violated)
    uErrorId   : UDINT;                     // 事件码，0 = 无事件；16#0002_2701 = 组态非法 / Event code
END_VAR
VAR
    fThetaRad  : REAL;                      // 弧度角 [rad] / Angle in radians
    fSinT      : REAL;                      // sin θ [1] / Sine of angle
    fCosT      : REAL;                      // cos θ [1] / Cosine of angle
    fRad2      : REAL;                      // 根号内 L² − r²sin²θ [mm²] / Radicand
    fRoot      : REAL;                      // sqrt 根号值 [mm] / Square root value
    fRr        : REAL;                      // 曲柄半径平方 [mm²] / Radius squared
    fLr        : REAL;                      // 连杆长平方 [mm²] / Rod length squared
END_VAR

// —— 段 0：全路径缺省 —— //
fSliderPos := 0.0;                       // 位移缺省零 / Position default zero
fSliderVel := 0.0;                       // 速度缺省零 / Velocity default zero
bValid := FALSE;                         // 有效回执预清 / Validity preset
bError := FALSE;                         // 故障预清（约束违反路径置位）/ Fault preset
uErrorId := 16#0000;                     // 事件码预清 / Event code preset

// —— 段 1：机构约束闸与输入闸 —— //
IF (fCrankR <> fCrankR) OR (fRodL <> fRodL) OR (fCrankDeg <> fCrankDeg) OR (fOmegaRadS <> fOmegaRadS) THEN
    bError := TRUE;                      // 故障级：输入含 NaN / Fault level: NaN input
    uErrorId := 16#0002_2701;            // 故障码（27xx 步进）/ Fault code
    RETURN;
END_IF
IF (fCrankR <= fEps) OR (fRodL <= fCrankR + fEps) THEN
    bError := TRUE;                      // 故障级：曲柄非正或连杆不长于曲柄（机构约束）/ Fault level: mechanism constraint
    uErrorId := 16#0002_2701;            // 同码段复用（R90 不加码：同属组态非法）/ Same code family
    RETURN;
END_IF
bValid := TRUE;                          // 组态与输入均有效 / Validity receipt

// —— 段 2：使能门控 —— //
IF NOT bEnable THEN
    fSliderPos := 0.0;                   // 失能输出零 / Disabled zero output
    fSliderVel := 0.0;                   // 速度零 / Velocity zero
    RETURN;                              // 失能不计算 / No computation when disabled
END_IF

// —— 段 3：正运动学主计算 —— //
fThetaRad := fCrankDeg * 0.017453292519943295;   // 角度转弧度（π/180 常数）/ Deg to rad
fSinT := SIN(fThetaRad);                 // sin θ / Sine
fCosT := COS(fThetaRad);                 // cos θ / Cosine
fRr := fCrankR * fCrankR;                // r² [mm²] / Radius squared
fLr := fRodL * fRodL;                    // L² [mm²] / Rod length squared
fRad2 := fLr - fRr * fSinT * fSinT;      // L² − r²sin²θ（≥ L² − r² > 0 已过闸）/ Radicand, positive by gate
fRoot := SQRT(fRad2);                    // 根号值 [mm] / Root value
fSliderPos := fCrankR * fCosT + fRoot;   // 滑块位移 x = r·cosθ + sqrt(...) / Slider position
fSliderVel := -fOmegaRadS * fCrankR * fSinT * (1.0 + fCrankR * fCosT / fRoot);   // 解析速度 [mm/s]（fRoot > 0 已过闸）/ Analytic velocity
END_FUNCTION_BLOCK
