(*
  DL Factory R83 | FC_DL_ShadeDriftIndexCalc
  功能：把 L*a*b* 三通道色差按亮度权重合成为色差与漂移指数，并给出回修判定。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_ShadeDriftIndexCalc : REAL
VAR_INPUT
    fDeltaL  : REAL; // 明度差 ΔL（正=偏亮）[ΔE 单位] / Lightness difference [dE]
    fDeltaA  : REAL; // 红绿轴差 Δa（正=偏红）[ΔE 单位] / Red-green difference [dE]
    fDeltaB  : REAL; // 黄蓝轴差 Δb（正=偏黄）[ΔE 单位] / Yellow-blue difference [dE]
    fTolDE   : REAL; // 色差容限 ΔE [-] / Colour difference tolerance [dE]
    fWeightL : REAL; // 明度权重（0~1）[-]/ Lightness weight [0..1]
END_VAR
VAR_OUTPUT
    fDE       : REAL; // 加权合成色差 [dE] / Weighted composite colour difference [dE]
    fDriftIdx : REAL; // 漂移指数（色差÷容限，大于 1 越限）[-] / Drift index, above 1 over limit
    xRework   : BOOL; // 回修判定（TRUE=需回修）/ Rework decision, TRUE = rework
    xValid    : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fSq : REAL; // 加权平方和 [dE²] / Weighted sum of squares [dE^2]
END_VAR
// 出口预置：四出口统一预置，回修标志预置 FALSE（安全侧）
fDE := 0.0; fDriftIdx := 0.0; xRework := FALSE; xValid := FALSE;
// 非有限拦截 + 权重/容限域闸（R20/R21）
IF NOT (fDeltaL > -1.0E30 AND fDeltaL < 1.0E30) OR NOT (fDeltaA > -1.0E30 AND fDeltaA < 1.0E30) OR NOT (fDeltaB > -1.0E30 AND fDeltaB < 1.0E30) OR NOT (fTolDE > -1.0E30 AND fTolDE < 1.0E30) OR NOT (fWeightL > -1.0E30 AND fWeightL < 1.0E30) OR fTolDE <= 0.0 OR fWeightL < 0.0 OR fWeightL > 1.0 THEN
    FC_DL_ShadeDriftIndexCalc := -1.0; RETURN;   // 哨兵 -1：非有限或权重/容限越界 / Sentinel -1
END_IF
// 加权平方和：ΔL 乘亮度权重，Δa/Δb 权重恒 1（三项量纲均为 dE²，可直接相加）
fSq := fWeightL * fDeltaL * fDeltaL + fDeltaA * fDeltaA + fDeltaB * fDeltaB; // 平方和 [dE²]
// 合成色差：开方前非负闸（R4）
IF fSq >= 0.0 THEN                  // 开方前非负闸 / Gate before square root
    fDE := SQRT(fSq);               // 合成色差 [dE] / Composite colour difference [dE]
ELSE
    fDE := 0.0;                     // 浮点异常防御缺省 / Float anomaly default
END_IF
// 漂移指数：色差 ÷ 容限，容限分母显式零闸（R4/R21）
IF ABS(fTolDE) > 1.0E-9 THEN        // 容限分母显式零闸 / Explicit zero gate on tolerance
    fDriftIdx := fDE / fTolDE;      // 漂移指数 [-]/ Drift index [-]
ELSE
    fDriftIdx := 0.0;               // 除零防御缺省 / Divide-by-zero default
END_IF
// 回修判定：指数严格大于 1 才回修（禁浮点等号比较）
xRework := fDriftIdx > 1.0;         // 回修判定布尔 / Rework boolean
xValid  := TRUE;                    // 链路有效 / Chain valid
FC_DL_ShadeDriftIndexCalc := fDE;   // 返回合成色差 [dE] / Return composite colour difference
END_FUNCTION
