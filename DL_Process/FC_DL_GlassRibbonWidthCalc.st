(*
  Name: FC_DL_GlassRibbonWidthCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 玻璃带宽度按「拉边机线速与拉引速度的速度比」投影到目标带宽上估算。
           物理口径：拉边机把玻璃带边缘以 fEdgeRollMps 向外输送，纵向以 fDrawMps 拉引；
           两者相等时带宽维持目标值，比值偏离 1 时带宽按同一比例偏移，
           故 fWidthMm = 目标带宽 × (拉边机线速 / 拉引速度)。
           该式是归一化速度比投影，分子为拉边机线速、分母为拉引速度，方向不可交换
           （交换会得到倒数比，带宽趋势完全反向）。
        2) 与目标带宽比较给出相对偏差 fDevPct = (实测带宽 − 目标带宽) / 目标带宽 × 100，
           正值表示带宽偏宽（拉边过强），负值表示偏窄（拉边不足）。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fDrawMps) > DL_EPS（拉引速度为 0 时速度比发散）与
           ABS(fWidthTargetMm) > DL_EPS（目标带宽为 0 时相对偏差无定义）都必须通过，否则判无效。
        3) 负值闸：拉边机线速、拉引速度、目标带宽、容差任一为负判无效
           （速度为负意味着反向运动，不属本件工况，不取绝对值掩盖）。
        4) 速度比窄闸：速度比钳到 DL_SPEED_RATIO_MIN(0.2) ~ DL_SPEED_RATIO_MAX(5.0)，
           越域钳边界算参考值但置无效，防拉引速度极小把带宽放大到无意义量级。
        5) 饱和钳制：带宽结果钳 0 ~ DL_W_MAX_MM(10000 mm)，偏差钳 −1000 ~ +1000 %。
  量纲自证：fWidthMm = mm × (m/s) / (m/s) = mm，速度比无因次，量纲保持长度；
           fDevPct = (mm − mm) / mm × 100 = 无因次 [%]，减法两侧与分母同量纲。
*)

FUNCTION FC_DL_GlassRibbonWidthCalc : BOOL
VAR_INPUT
    fEdgeRollMps   : REAL;   // 拉边机线速度 [m/s] / Edge roller linear speed [m/s]
    fDrawMps       : REAL;   // 玻璃带拉引速度 [m/s] / Ribbon draw speed [m/s]
    fWidthTargetMm : REAL;   // 目标带宽 [mm] / Target ribbon width [mm]
    fTolPct        : REAL;   // 带宽容差（观测用）[%] / Width tolerance for observation [%]
END_VAR
VAR_OUTPUT
    fWidthMm       : REAL;   // 估算带宽 [mm] / Estimated ribbon width [mm]
    fDevPct        : REAL;   // 带宽相对偏差 [%] / Ribbon width relative deviation [%]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fSpeedRatio   : REAL;   // 速度比（拉边 / 拉引）[-] / Speed ratio, edge to draw [-]
    _fWidthRawMm   : REAL;   // 未饱和的带宽 [mm] / Raw ribbon width [mm]
    _fDevRawPct    : REAL;   // 未饱和的偏差 [%] / Raw deviation [%]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT         : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_RATIO_MIN   : REAL := 0.20;      // 速度比饱和下限 [-] / Speed ratio saturation low [-]
    DL_RATIO_MAX   : REAL := 5.00;      // 速度比饱和上限 [-] / Speed ratio saturation high [-]
    DL_W_MAX_MM    : REAL := 10000.0;   // 带宽饱和上限 [mm] / Width saturation ceiling [mm]
    DL_DEV_MAX     : REAL := 1000.0;    // 偏差饱和上限 [%] / Deviation saturation ceiling [%]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fEdgeRollMps > -DL_BIG AND fEdgeRollMps < DL_BIG)
   OR NOT (fDrawMps > -DL_BIG AND fDrawMps < DL_BIG)
   OR NOT (fWidthTargetMm > -DL_BIG AND fWidthTargetMm < DL_BIG)
   OR NOT (fTolPct > -DL_BIG AND fTolPct < DL_BIG) THEN
    fWidthMm := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fDevPct := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GlassRibbonWidthCalc := FALSE;    // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：拉引速度与目标带宽两个分母） —— *)
IF (ABS(fDrawMps) <= DL_EPS) OR (ABS(fWidthTargetMm) <= DL_EPS) THEN
    fWidthMm := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fDevPct := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GlassRibbonWidthCalc := FALSE;    // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（速度为负意味着反向，不属本工况） —— *)
IF (fEdgeRollMps < 0.0) OR (fDrawMps < 0.0) OR (fWidthTargetMm < 0.0) OR (fTolPct < 0.0) THEN
    fWidthMm := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fDevPct := 0.0;                         // 偏差强制 0.0 / Deviation forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GlassRibbonWidthCalc := FALSE;    // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：速度比归一化（R22 方向自核：拉边机线速在分子、拉引速度在分母） —— *)
_fSpeedRatio := LIMIT(DL_RATIO_MIN, fEdgeRollMps / fDrawMps, DL_RATIO_MAX);   // 速度比 [-]

(* —— 段 5：带宽投影与偏差（分子方向：实测减目标，正值 = 偏宽） —— *)
_fWidthRawMm := fWidthTargetMm * _fSpeedRatio;                    // 带宽 [mm]
_fDevRawPct := (_fWidthRawMm - fWidthTargetMm) / fWidthTargetMm * DL_PCT;   // 偏差 [%]

(* —— 段 6：输出单点写盘（饱和钳制） —— *)
fWidthMm := LIMIT(0.0, _fWidthRawMm, DL_W_MAX_MM);                // 带宽 [mm]
fDevPct := LIMIT(-DL_DEV_MAX, _fDevRawPct, DL_DEV_MAX);           // 偏差 [%]

(* —— 段 7：有效位单点聚合（速度比不越窄闸 + 容差在 0..100 %） —— *)
xValid := (fEdgeRollMps >= 0.0) AND (fDrawMps > DL_EPS)          // 速度为正向
          AND (fWidthTargetMm > DL_EPS)                          // 目标带宽为正
          AND (fTolPct >= 0.0) AND (fTolPct <= DL_PCT)           // 容差在 0..100 %
          AND (fEdgeRollMps / fDrawMps >= DL_RATIO_MIN)          // 速度比不越下限
          AND (fEdgeRollMps / fDrawMps <= DL_RATIO_MAX);         // 速度比不越上限
FC_DL_GlassRibbonWidthCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
