(*
  Name: FC_DL_CoaterArealLoadingCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 由干膜厚度与涂层密度算面密度：面密度 = 厚度 × 密度，
           单位换算后为 mg/cm2。推导：厚度 µm × 密度 g/cm3 得 mg/cm2 需先除 10，
           因为 1 µm × 1 g/cm3 = 1e-4 cm × 1 g/cm3 = 1e-4 g/cm2 = 0.1 mg/cm2，
           故 fArealMgCm2 = fDryThickUm × fDensityGcm3 / 10。
        2) 与目标面密度比较给出相对偏差 fDevPct = (实测 − 目标) / 目标 × 100，
           方向为「实测减目标」：正值表示超涂（面密度偏高），负值表示欠涂。
           偏差绝对值不超过容差 fTolPct 则判合格 xPass。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0、xPass 强制 FALSE）
           并置无效（R19），无效数据不得判合格。
        2) 分母零闸：ABS(fTargetMgCm2) > DL_EPS 才允许算相对偏差（目标为 0 时相对偏差无定义），
           否则判无效；厚度为 0 属合法工况（未涂布），面密度 0，但相对偏差仍可算。
        3) 负值闸：干膜厚度为负、密度为负、目标面密度为负、容差为负均判无效
           （容差为负会使合格判据恒假，属组态错误）。
        4) 容差窄闸：fTolPct 钳 0 ~ 100 %，越域判无效；容差为 0 表示零公差（严判），属合法组态。
        5) 饱和钳制：面密度钳 0 ~ DL_AREAL_MAX(1000 mg/cm2)，偏差钳 −1000 ~ +1000 %，
           防极端输入溢出。
  量纲自证：fArealMgCm2 = µm × (g/cm3) / 10 (mg/cm2 per µm·g/cm3) = mg/cm2，量纲闭合；
           fDevPct = (mg/cm2 − mg/cm2) / (mg/cm2) × 100 = 无因次百分数 [%]，
           分子分母同量纲，减法两侧同量纲。
*)

FUNCTION FC_DL_CoaterArealLoadingCalc : BOOL
VAR_INPUT
    fDryThickUm   : REAL;   // 干膜厚度 [µm] / Dry film thickness [µm]
    fDensityGcm3  : REAL;   // 涂层压实密度 [g/cm3] / Coating density [g/cm3]
    fTargetMgCm2  : REAL;   // 目标面密度 [mg/cm2] / Target areal loading [mg/cm2]
    fTolPct       : REAL;   // 面密度容差 [%] / Areal loading tolerance [%]
END_VAR
VAR_OUTPUT
    fArealMgCm2   : REAL;   // 实测面密度 [mg/cm2] / Measured areal loading [mg/cm2]
    fDevPct       : REAL;   // 相对偏差（实测 − 目标）[%] / Relative deviation [%]
    xPass         : BOOL;   // 面密度合格标志 [bool] / Areal loading pass flag [bool]
    xValid        : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fArealRaw    : REAL;   // 未饱和的面密度 [mg/cm2] / Raw areal loading [mg/cm2]
    _fDevRawPct   : REAL;   // 未饱和的相对偏差 [%] / Raw relative deviation [%]
    _fTolClampPct : REAL;   // 钳制后的容差 [%] / Clamped tolerance [%]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT        : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_UM_TO_MGCM2: REAL := 10.0;      // µm·g/cm3 → mg/cm2 的除数 [-] / Thickness-density divisor [-]
    DL_AREAL_MAX  : REAL := 1000.0;    // 面密度饱和上限 [mg/cm2] / Areal loading saturation ceiling
    DL_DEV_MAX    : REAL := 1000.0;    // 偏差饱和上限 [%] / Deviation saturation ceiling [%]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fDryThickUm > -DL_BIG AND fDryThickUm < DL_BIG)
   OR NOT (fDensityGcm3 > -DL_BIG AND fDensityGcm3 < DL_BIG)
   OR NOT (fTargetMgCm2 > -DL_BIG AND fTargetMgCm2 < DL_BIG)
   OR NOT (fTolPct > -DL_BIG AND fTolPct < DL_BIG) THEN
    fArealMgCm2 := 0.0;                     // 输出强制 0.0 / Output forced to zero
    fDevPct := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xPass := FALSE;                         // 合格标志强制 FALSE / Pass forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_CoaterArealLoadingCalc := FALSE;  // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：目标面密度是相对偏差的分母） —— *)
IF ABS(fTargetMgCm2) <= DL_EPS THEN
    fArealMgCm2 := 0.0;                     // 输出强制 0.0 / Output forced to zero
    fDevPct := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xPass := FALSE;                         // 合格标志强制 FALSE / Pass forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterArealLoadingCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（负容差会使合格判据恒假，属组态错误） —— *)
IF (fDryThickUm < 0.0) OR (fDensityGcm3 < 0.0) OR (fTargetMgCm2 < 0.0) OR (fTolPct < 0.0) THEN
    fArealMgCm2 := 0.0;                     // 输出强制 0.0 / Output forced to zero
    fDevPct := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xPass := FALSE;                         // 合格标志强制 FALSE / Pass forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterArealLoadingCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：面密度主算式（R22 方向自核：厚度乘密度，除 10 做单位换算） —— *)
_fArealRaw := fDryThickUm * fDensityGcm3 / DL_UM_TO_MGCM2;       // [mg/cm2]

(* —— 段 5：相对偏差（分子方向：实测减目标，正值 = 超涂） —— *)
_fDevRawPct := (_fArealRaw - fTargetMgCm2) / fTargetMgCm2 * DL_PCT;   // [%]

(* —— 段 6：输出单点写盘（饱和钳制后判合格，保证判据与出口同源） —— *)
fArealMgCm2 := LIMIT(0.0, _fArealRaw, DL_AREAL_MAX);             // 面密度 [mg/cm2]
fDevPct := LIMIT(-DL_DEV_MAX, _fDevRawPct, DL_DEV_MAX);          // 偏差 [%]
_fTolClampPct := LIMIT(0.0, fTolPct, DL_PCT);                    // 容差钳 0..100 [%]

(* —— 段 7：有效位与合格位单点聚合 —— *)
xValid := (fDryThickUm >= 0.0) AND (fDensityGcm3 > DL_EPS)
          AND (fTargetMgCm2 > DL_EPS) AND (fTolPct <= DL_PCT);   // 有效位聚合
xPass := xValid AND (ABS(fDevPct) <= _fTolClampPct);             // 偏差绝对值不超容差即合格
FC_DL_CoaterArealLoadingCalc := xValid;                          // 返回码：TRUE = 计算可信

END_FUNCTION
