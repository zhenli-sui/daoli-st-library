(*
  DL Factory R83 | FC_DL_SlotHeightFitCalc
  功能：校验货位净高对托盘货高的容纳能力，给出净余量与高度利用率。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_SlotHeightFitCalc : REAL
VAR_INPUT
    fSlotClearHmm  : REAL; // 货位净高（横梁下沿到地面）[mm] / Slot clear height [mm]
    fPalletHmm     : REAL; // 托盘货高（含托盘本体）[mm] / Pallet load height incl. pallet [mm]
    fLiftClearMm   : REAL; // 存取所需起升余量 [mm] / Required lift clearance [mm]
    fTolMm         : REAL; // 允许最小安全余量 [mm] / Required minimum safety margin [mm]
END_VAR
VAR_OUTPUT
    fMarginMm : REAL; // 净余量（净高-货高-起升余量）[mm] / Net margin [mm]
    fUtilPct  : REAL; // 高度利用率（货高÷净高）[%] / Height utilisation [%]
    xFit      : BOOL; // 匹配判定（余量不低于安全余量）/ Fit decision
    xValid    : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR

// ---------- 输出预置 ----------
fMarginMm := 0.0;                   // 余量清零 [mm] / Margin zeroed
fUtilPct  := 0.0;                   // 利用率清零 [%] / Utilisation zeroed
xFit      := FALSE;                 // 预置不匹配（安全侧）/ Preset no-fit (safe side)
xValid    := FALSE;                 // 有效性预置 FALSE / Validity preset FALSE

// ---------- 非有限拦截 + 量纲自检（R20/R21） ----------
IF NOT (fSlotClearHmm > -1.0E30 AND fSlotClearHmm < 1.0E30) OR NOT (fPalletHmm > -1.0E30 AND fPalletHmm < 1.0E30) OR NOT (fLiftClearMm > -1.0E30 AND fLiftClearMm < 1.0E30) OR NOT (fTolMm > -1.0E30 AND fTolMm < 1.0E30) OR fSlotClearHmm <= 0.0 OR fPalletHmm <= 0.0 OR fLiftClearMm < 0.0 OR fTolMm < 0.0 THEN
    FC_DL_SlotHeightFitCalc := -1.0; // 哨兵 -1：非有限或量纲越界 / Sentinel -1: non-finite or out of domain
    RETURN;
END_IF

// ---------- 净余量：同量纲相减（mm），三件均以 mm 输入故无需换算 ----------
fMarginMm := fSlotClearHmm - fPalletHmm - fLiftClearMm; // 净余量 [mm] / Net margin [mm]

// ---------- 高度利用率：货高 ÷ 净高 × 100，净高分母显式零闸（R4/R21） ----------
IF ABS(fSlotClearHmm) > 1.0E-9 THEN               // 净高分母显式零闸 / Explicit zero gate on clear height
    fUtilPct := (fPalletHmm / fSlotClearHmm) * 100.0; // 高度利用率 [%] / Height utilisation [%]
ELSE
    fUtilPct := 0.0;                // 除零防御缺省 [%] / Divide-by-zero default
END_IF

// ---------- 匹配判定：余量不低于安全余量（单一比较，禁浮点等号） ----------
xFit   := fMarginMm >= fTolMm;      // 匹配布尔 / Fit boolean
xValid := TRUE;                     // 链路有效 / Chain valid
FC_DL_SlotHeightFitCalc := fMarginMm; // 返回净余量 [mm] / Return net margin [mm]
END_FUNCTION
