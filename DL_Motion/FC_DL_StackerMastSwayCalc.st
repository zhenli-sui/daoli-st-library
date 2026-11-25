(*
  DL Factory R83 | FC_DL_StackerMastSwayCalc
  功能：按加减速度与立柱高度估算堆垛机立柱顶部准静态摆幅与残余振荡稳定时间。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_StackerMastSwayCalc : REAL
VAR_INPUT
    fAccMs2    : REAL; // 行走加（减）速度 [m/s²] / Travel acceleration [m/s^2]
    fMastHM    : REAL; // 立柱有效悬臂高度 [m] / Effective mast cantilever height [m]
    fNatHz     : REAL; // 立柱一阶固有频率 [Hz] / First natural frequency of mast [Hz]
    fDampRatio : REAL; // 阻尼比（0.01~0.20）[-]/ Damping ratio [0.01..0.20]
    fDynFactor : REAL; // 悬臂动载放大系数（1.0~2.0）[-]/ Cantilever dynamic amplification [1.0..2.0]
END_VAR
VAR_OUTPUT
    fSwayMm  : REAL; // 立柱顶部准静态摆幅（单侧）[mm] / Quasi-static sway amplitude [mm]
    fSettleS : REAL; // 残余振荡衰减到 5% 的稳定时间 [s] / Settling time to 5 percent [s]
    fSwayDeg : REAL; // 立柱倾角（摆幅÷高度）[°] / Mast tilt angle [deg]
    xValid   : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fAccG  : REAL; // 加速度折算重力倍数 [-] / Acceleration in g units
    fOmega : REAL; // 一阶圆频率 [rad/s] / First angular frequency [rad/s]
    cG     : REAL := 9.80665; // 标准重力加速度常量 [m/s²]，已引用（R19）/ Standard gravity [m/s^2]
END_VAR
// 出口预置：四出口统一预置（R256）
fSwayMm := 0.0; fSettleS := 0.0; fSwayDeg := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 分母零闸（R4/R20/R21）
IF NOT (fAccMs2 > -1.0E30 AND fAccMs2 < 1.0E30) OR NOT (fMastHM > -1.0E30 AND fMastHM < 1.0E30) OR NOT (fNatHz > -1.0E30 AND fNatHz < 1.0E30) OR NOT (fDampRatio > -1.0E30 AND fDampRatio < 1.0E30) OR NOT (fDynFactor > -1.0E30 AND fDynFactor < 1.0E30) OR fAccMs2 < 0.0 OR fMastHM <= 0.0 OR fNatHz <= 0.0 OR fDampRatio <= 0.0 OR fDynFactor <= 0.0 THEN
    FC_DL_StackerMastSwayCalc := -1.0; RETURN;  // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 加速度折算：m/s² ÷ m/s² = 无量纲重力倍数（量纲自洽）
fAccG := fAccMs2 / cG;              // 重力倍数 [-] / Acceleration in g units
// 准静态摆幅：a/g × H × 动载放大，m × 1000 = mm（悬臂顶挠度正比于 aH/g）
fSwayMm := fAccG * fMastHM * fDynFactor * 1000.0;   // 单侧摆幅 [mm] / One-side sway [mm]
// 一阶圆频率：ω = 2πf，f 单位 Hz 得 rad/s（2π 为无量纲弧度量）
fOmega := 2.0 * 3.14159265358979 * fNatHz;          // 圆频率 [rad/s] / Angular frequency [rad/s]
// 稳定时间：4 ÷ (ζω) 近似衰减到 5%，分母显式零闸（R4/R21）
IF ABS(fDampRatio * fOmega) > 1.0E-9 THEN          // 阻尼×频率分母显式零闸 / Zero gate on damped frequency
    fSettleS := 4.0 / (fDampRatio * fOmega);        // 稳定时间 [s] / Settling time [s]
ELSE
    fSettleS := 0.0;                // 无阻尼不可估稳定时间，缺省零 / Undamped, default zero
END_IF
// 倾角：摆幅(mm) ÷ 高度(m×1000=mm) 得无量纲正切，×180/π 转度（小角近似）
fSwayDeg := (fSwayMm / (fMastHM * 1000.0)) * (180.0 / 3.14159265358979); // 倾角 [°] / Tilt [deg]
xValid := TRUE;                             // 链路有效 / Chain valid
FC_DL_StackerMastSwayCalc := fSwayMm;       // 返回单侧摆幅 [mm] / Return one-side sway [mm]
END_FUNCTION
