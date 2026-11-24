(*
  DL Factory R83 | FC_DL_PalletOverhangCalc
  功能：算托盘相对货垛的单侧悬垂量，并按允许悬垂比例校验堆码稳定性。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_PalletOverhangCalc : REAL
VAR_INPUT
    fPalletLenMm : REAL; // 托盘长度 [mm] / Pallet length [mm]
    fPalletWidMm : REAL; // 托盘宽度 [mm] / Pallet width [mm]
    fBoxLenMm    : REAL; // 货垛沿长度方向外形尺寸 [mm] / Load footprint length [mm]
    fBoxWidMm    : REAL; // 货垛沿宽度方向外形尺寸 [mm] / Load footprint width [mm]
    fMaxOverPct  : REAL; // 允许单侧悬垂比例（0~10）[%] / Allowed overhang ratio [%]
END_VAR
VAR_OUTPUT
    fOverLenMm : REAL; // 长度方向单侧悬垂（负值=货垛内缩）[mm] / Length overhang [mm]
    fOverWidMm : REAL; // 宽度方向单侧悬垂 [mm] / Width overhang [mm]
    fOverMaxMm : REAL; // 该托盘允许的单侧悬垂上限（两向较严者）[mm] / Allowed ceiling [mm]
    xOk        : BOOL; // 悬垂合规判定 / Overhang compliance flag
    xValid     : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fLimLenMm : REAL; // 长度向允许悬垂 [mm] / Allowed overhang on length [mm]
    fLimWidMm : REAL; // 宽度向允许悬垂 [mm] / Allowed overhang on width [mm]
END_VAR
fOverLenMm := 0.0; fOverWidMm := 0.0; fOverMaxMm := 0.0; xOk := FALSE; xValid := FALSE; // 出口预置
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fPalletLenMm > -1.0E30 AND fPalletLenMm < 1.0E30) OR NOT (fPalletWidMm > -1.0E30 AND fPalletWidMm < 1.0E30) OR NOT (fBoxLenMm > -1.0E30 AND fBoxLenMm < 1.0E30) OR NOT (fBoxWidMm > -1.0E30 AND fBoxWidMm < 1.0E30) OR NOT (fMaxOverPct > -1.0E30 AND fMaxOverPct < 1.0E30) OR fPalletLenMm <= 0.0 OR fPalletWidMm <= 0.0 OR fBoxLenMm <= 0.0 OR fBoxWidMm <= 0.0 OR fMaxOverPct < 0.0 THEN
    FC_DL_PalletOverhangCalc := -1.0; RETURN;  // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 悬垂比例域闸：0~10% 之外钳位（超 10% 已无稳定可言）
IF fMaxOverPct > 10.0 THEN
    fMaxOverPct := 10.0;            // 上限钳位 [%] / Clamp upper bound
END_IF
// 单侧悬垂：两向外形差 ÷ 2，同量纲（mm）相减；负值表示货垛内缩
fOverLenMm := (fPalletLenMm - fBoxLenMm) / 2.0;   // 长度向单侧悬垂 [mm] / Length overhang [mm]
fOverWidMm := (fPalletWidMm - fBoxWidMm) / 2.0;   // 宽度向单侧悬垂 [mm] / Width overhang [mm]
// 允许上限：托盘该向尺寸 × 比例 ÷ 100（mm × 无量纲 = mm，量纲自洽）
fLimLenMm := fPalletLenMm * (fMaxOverPct / 100.0); // 长度向允许悬垂 [mm] / Allowed length overhang
fLimWidMm := fPalletWidMm * (fMaxOverPct / 100.0); // 宽度向允许悬垂 [mm] / Allowed width overhang
// 上限回显取两向较严者，供上层 HMI 统一显示
IF fLimLenMm <= fLimWidMm THEN
    fOverMaxMm := fLimLenMm;        // 长度向更严 [mm] / Length direction is stricter
ELSE
    fOverMaxMm := fLimWidMm;        // 宽度向更严 [mm] / Width direction is stricter
END_IF
// 合规判定：两向悬垂均不超各自上限（负值内缩恒合规）
xOk    := (fOverLenMm <= fLimLenMm) AND (fOverWidMm <= fLimWidMm); // 合规布尔 / Compliance boolean
xValid := TRUE; FC_DL_PalletOverhangCalc := fOverLenMm; // 返回长度向悬垂 [mm] / Return overhang
END_FUNCTION
