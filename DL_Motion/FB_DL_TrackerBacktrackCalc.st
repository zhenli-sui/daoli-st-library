// =====================================================================
// FB_DL_TrackerBacktrackCalc.st
// 光伏跟踪支架逆跟踪角度修正（阵列阴影几何, 逐排互遮挡角计算）
// PV tracker backtracking angle with array shading geometry
// 所属子库: DL_Motion    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0004_0354 ~ 16#0004_0358 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: photovoltaic, solar-tracker, backtrack, geometry
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 14)
// 分层声明: 太阳高度角/方位角经引脚注入（上游消费太阳位置计算件输出）,
//           本件为逐排阴影几何层, 每拍全量重算
// 几何模型: 面板绕南北轴旋转角 R, 收集宽度 W, 排间距 P;
//           面板端点高 h = (W/2)·sin(R), 水平投影 d = (W/2)·cos(R);
//           无遮挡约束 d + h/tan(高角) ≤ P − W/2;
//           解 a·cos(R) + b·sin(R) = K（a=W/2, b=W/(2·tan(高角)), K=P−W/2）
//           得 R_limit = asin(K/√(a²+b²)) − atan(b/a), 全程 arctan/asin 防除零
// =====================================================================
FUNCTION_BLOCK FB_DL_TrackerBacktrackCalc
VAR_INPUT
    fSunElev_deg   : REAL := 30.0;  // 太阳高度角 -90~90 度（注入）/ Sun elevation [deg]
    fSunAzi_deg    : REAL := 180.0; // 太阳方位角 0~360 度（注入）/ Sun azimuth [deg]
    fRowPitch_m    : REAL := 6.0;   // 排间距 0.5~20 m / Row pitch [m]
    fCollectWidth_m: REAL := 2.0;   // 收集宽度（面板展开占宽）0~50 m / Collector width [m]
    fMaxAngle_deg  : REAL := 60.0;  // 机械限位角 0~90 度 / Mechanical limit angle [deg]
END_VAR
VAR_OUTPUT
    fTrackAngle_deg  : REAL := 0.0;   // 跟踪支架角度, 安全侧 0 度 / Track angle [deg]
    bBacktrackActive : BOOL := FALSE; // 逆跟踪激活标志 / Backtracking active flag
    fShadeLimit_deg  : REAL := 0.0;   // 阴影约束限角 0~90 度 / Shade limit angle [deg]
    eErr             : UDINT := 16#0004_0354;  // 错误码 / Error code
END_VAR
VAR
    rPi       : REAL := 3.14159265358979;   // 圆周率 / Pi constant
    bCfgErr   : BOOL := FALSE;        // 组态非法标记 / Configuration error flag
    bClampInfo: BOOL := FALSE;        // 输出限幅信息标记 / Output clamp info flag
    fElevR    : REAL := 0.0;          // 高度角弧度 / Elevation in radian [rad]
    fAziR     : REAL := 0.0;          // 方位角弧度 / Azimuth in radian [rad]
    fXew      : REAL := 0.0;          // 太阳矢量东西向投影 / Sun east-west projection
    fZup      : REAL := 0.0;          // 太阳矢量天顶向投影 / Sun up projection
    fIdealR   : REAL := 0.0;          // 理想跟踪角弧度 / Ideal track angle [rad]
    fA        : REAL := 0.0;          // 几何系数 a = W/2 / Geometry coefficient a
    fB        : REAL := 0.0;          // 几何系数 b = W/(2·tan(高角)) / Geometry coefficient b
    fK        : REAL := 0.0;          // 几何常数 K = P − W/2 / Geometry constant K
    fDen      : REAL := 0.0;          // 系数模长 / Coefficient modulus
    fRatio    : REAL := 0.0;          // 反正弦自变量 / Arcsine argument
    fPhiR     : REAL := 0.0;          // 相位角弧度 / Phase angle [rad]
    fRlimR    : REAL := 0.0;          // 阴影限角弧度 / Shade limit [rad]
    fIdealD   : REAL := 0.0;          // 理想跟踪角度 / Ideal track angle [deg]
    fLastAng  : REAL := 0.0;          // 上次有效输出角保持量 / Last valid angle hold [deg]
    xHasLast  : BOOL := FALSE;        // 已有有效输出标记 / Has valid output flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0004_0354 信息 跟踪角正常（未触发逆跟踪, 含太阳高度角不大于 0 时归位 0 度）
//   16#0004_0355 信息 逆跟踪激活（阴影约束生效, 限角压向跟踪输出）
//   16#0004_0356 信息 输出限幅生效（理想角越出机械限位, 信息级）
//   16#0004_0357 故障 太阳角输入非有限（保持上次有效角, 不新增动作）,
//                解除式 = 输入恢复有限
//   16#0004_0358 故障 组态非法（排间距越出 0.5~20 m, 宽度/限位角非法）,
//                解除式 = 恢复合法组态
// ---------------------------------------------------------------------

// ---- 组态闸 / Configuration gate ----
bCfgErr := FALSE;                   // 复位 / Reset
IF (fRowPitch_m <> fRowPitch_m) OR (fRowPitch_m < 0.5) OR (fRowPitch_m > 20.0) THEN
    bCfgErr := TRUE;                // 排间距非法 / Illegal row pitch
END_IF
IF (fCollectWidth_m <> fCollectWidth_m) OR (fCollectWidth_m <= 0.0) OR (fCollectWidth_m > 50.0) THEN
    bCfgErr := TRUE;                // 收集宽度非法 / Illegal width
END_IF
IF (fMaxAngle_deg <> fMaxAngle_deg) OR (fMaxAngle_deg <= 0.0) OR (fMaxAngle_deg > 90.0) THEN
    bCfgErr := TRUE;                // 限位角非法 / Illegal limit angle
END_IF

// ---- 输出缺省 / Output defaults ----
bBacktrackActive := FALSE;          // 缺省非逆跟踪 / Default no backtrack
bClampInfo := FALSE;                // 缺省无限幅 / Default no clamp
fShadeLimit_deg := 0.0;             // 缺省零 / Default zero

// ---- 非有限太阳角: 保持上次有效角（安全侧不新增动作）/ Non-finite sun: hold last ----
IF bCfgErr THEN
    fTrackAngle_deg := 0.0;         // 组态非法安全侧归零 / Config fault safe zero
    eErr := 16#0004_0358;           // 组态码 / Config code
ELSIF (fSunElev_deg <> fSunElev_deg) OR (ABS(fSunElev_deg) >= 1.0E12)
   OR (fSunAzi_deg <> fSunAzi_deg) OR (ABS(fSunAzi_deg) >= 1.0E12) THEN
    fTrackAngle_deg := fLastAng;    // 保持上次有效角 / Hold last valid angle
    eErr := 16#0004_0357;           // 非有限码 / Non-finite code
ELSIF fSunElev_deg <= 0.0 THEN
    // 太阳高度角不大于 0 → 归位停跟踪（安全侧 0 度）/ Night: park at 0 degree
    fTrackAngle_deg := 0.0;
    fLastAng := 0.0;                // 保持量同步归位 / Hold value parked
    xHasLast := TRUE;               // 置有效标记 / Set valid flag
    eErr := 16#0004_0354;           // 正常归位 / Normal park
ELSE
    // ---- 每拍全量重算 / Full recalculation each cycle ----
    fElevR := fSunElev_deg * rPi / 180.0;   // 高度角弧度 / Elevation radian
    fAziR  := fSunAzi_deg * rPi / 180.0;    // 方位角弧度 / Azimuth radian
    fXew   := COS(fElevR) * SIN(fAziR);     // 东西向投影 / East-west projection
    fZup   := SIN(fElevR);                  // 天顶向投影 / Up projection
    IF fZup < 0.05 THEN
        fZup := 0.05;           // 天顶分量下限防除零 / Up floor against division
    END_IF
    fIdealR := ATAN(fXew / fZup);           // 理想跟踪角弧度 / Ideal angle [rad]
    fIdealD := fIdealR * 180.0 / rPi;       // 理想角度数 / Ideal angle [deg]

    // ---- 阴影几何求限角 / Shading geometry limit ----
    IF fSunElev_deg < 1.0 THEN
        fRlimR := 0.0;          // 近地平角限角归零（贴平放） / Near horizon: flat limit
    ELSE
        fA := fCollectWidth_m * 0.5;                    // a = W/2 / Coefficient a
        fB := fA / TAN(fElevR);                         // b = W/(2·tan) / Coefficient b
        fK := fRowPitch_m - fA;                         // K = P − W/2 / Constant K
        fDen := SQRT((fA * fA) + (fB * fB));            // 模长 / Modulus
        fRatio := fK / fDen;                            // 反正弦自变量 / Arcsine argument
        IF fRatio > 1.0 THEN
            fRlimR := fMaxAngle_deg * rPi / 180.0;      // 阳光充足无阴影约束 / No shade constraint
        ELSIF fRatio < -1.0 THEN
            fRlimR := 0.0;      // 几何不可达, 限角归零 / Unreachable geometry, flat limit
        ELSE
            fPhiR  := ATAN(fB / fA);                    // 相位角（a 恒正防除零）/ Phase angle
            fRlimR := ASIN(fRatio) - fPhiR;             // 解临界角 / Solve critical angle
        END_IF
    END_IF
    // 限角归一到 0~限位 / Normalize limit to 0..max
    IF fRlimR < 0.0 THEN
        fRlimR := 0.0;          // 下界钳位 / Clamp lower
    END_IF
    IF fRlimR > (fMaxAngle_deg * rPi / 180.0) THEN
        fRlimR := fMaxAngle_deg * rPi / 180.0;      // 上界钳位 / Clamp upper
    END_IF
    fShadeLimit_deg := fRlimR * 180.0 / rPi;        // 输出限角度数 / Output limit [deg]

    // ---- 逆跟踪判定与输出 / Backtracking decision and output ----
    IF ABS(fIdealD) <= fShadeLimit_deg THEN
        fTrackAngle_deg := fIdealD;             // 未越限直接跟踪 / Track ideal
        bBacktrackActive := FALSE;              // 非逆跟踪 / Not backtracking
    ELSE
        bBacktrackActive := TRUE;               // 拍 N 进入逆跟踪 / Backtracking active
        IF fIdealD >= 0.0 THEN
            fTrackAngle_deg := fShadeLimit_deg; // 正向压到限角 / Positive side limited
        ELSE
            fTrackAngle_deg := -fShadeLimit_deg;    // 反向压到限角 / Negative side limited
        END_IF
    END_IF
    // 机械限位钳位（信息级）/ Mechanical clamp with info code
    IF fTrackAngle_deg > fMaxAngle_deg THEN
        fTrackAngle_deg := fMaxAngle_deg;       // 上限钳位 / Clamp upper
        bClampInfo := TRUE;                     // 置限幅信息 / Set clamp info
    END_IF
    IF fTrackAngle_deg < (-fMaxAngle_deg) THEN
        fTrackAngle_deg := -fMaxAngle_deg;      // 下限钳位 / Clamp lower
        bClampInfo := TRUE;
    END_IF
    fLastAng := fTrackAngle_deg;    // 更新有效保持量 / Update hold value
    xHasLast := TRUE;               // 置有效标记 / Set valid flag

    // ---- 错误码仲裁 / Error arbitration ----
    IF bClampInfo THEN
        eErr := 16#0004_0356;       // 限幅信息 / Clamp info
    ELSIF bBacktrackActive THEN
        eErr := 16#0004_0355;       // 逆跟踪信息 / Backtrack info
    ELSE
        eErr := 16#0004_0354;       // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
