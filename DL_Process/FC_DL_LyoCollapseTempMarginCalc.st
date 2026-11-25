(*
  Name: FC_DL_LyoCollapseTempMarginCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 塌陷温度裕度 = 塌陷温度 − 制品温度，即 fMarginK = fCollapseC − fProductC，
           裕度为正表示制品温度仍低于塌陷温度（安全侧），为负表示已越过塌陷边界。
        2) 裕度分级（nGrade）：0 = 合格（裕度 >= fMarginWarnK），1 = 预警（fMarginMinK <= 裕度 < fMarginWarnK），
           2 = 不足（裕度 < fMarginMinK），分级判据全部对原始裕度做，钳制只作用于输出数值。
        3) 冰点约束：制品温度必须低于冰点 fIcePointC，否则一次干燥已进入液态（融冰），
           输出 xAboveIce 供上层立即降温或转二次干燥。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（裕度强制 0.0 且置分级 2 = 不足），不得只置标志（R19）。
        2) 阈值域闸：分级阈值须满足 fMarginMinK < fMarginWarnK（否则两级判据区间为空、分级恒失效），
           越域判无效并把 nGrade 置 2（保守侧）。
        3) 温度域闸：三路温度必须落在 [-DL_T_SPAN, +DL_T_SPAN] 内，越域判无效（量级异常）。
        4) 判据取原始值（R24）：分级与冰点判定使用原始入参，不先把温度夹到工艺带再判。
        5) 物理域钳制：裕度钳到 [-DL_MARGIN_SPAN, +DL_MARGIN_SPAN]，避免极端值污染显示与趋势。
        6) 纯函数无状态：分级不做迟滞，防抖与联锁延时由搁板温控 FB 承担。
  量纲自证：fMarginK = (degC) − (degC) = (K)；与 fMarginMinK / fMarginWarnK 同为温差点量纲 [K]，
           可与温差阈值直接比较；nGrade 为无量纲等级 [level]。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_LyoCollapseTempMarginCalc : BOOL
VAR_INPUT
    fProductC        : REAL;   // 制品（瓶内）温度 [degC] / Product temperature inside the vial [degC]
    fCollapseC       : REAL;   // 配方给出的塌陷温度 [degC] / Formulation collapse temperature [degC]
    fIcePointC       : REAL;   // 配方给出的冰点 [degC] / Formulation ice point [degC]
    fMarginMinK      : REAL;   // 裕度不足阈值（低于即判不足）[K] / Margin insufficient threshold [K]
    fMarginWarnK     : REAL;   // 裕度预警阈值（低于即判预警）[K] / Margin warning threshold [K]
END_VAR
VAR_OUTPUT
    fMarginK         : REAL;   // 塌陷温度裕度 [K] / Collapse temperature margin [K]
    nGrade           : INT;    // 裕度分级 0=合格 1=预警 2=不足 [level] / Margin grade 0/1/2 [level]
    xMarginLow       : BOOL;   // 裕度不足标志（< 下限）[bool] / Margin insufficient flag [bool]
    xAboveIce        : BOOL;   // 制品温度高于冰点标志 [bool] / Product above ice point flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fMarginRawK     : REAL;   // 钳制前的原始裕度 [K] / Raw margin before limiting [K]
END_VAR
VAR CONSTANT
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_T_SPAN        : REAL := 300.0;     // 温度量级闸跨度 [degC] / Temperature magnitude gate span [degC]
    DL_MARGIN_SPAN   : REAL := 200.0;     // 裕度钳制跨度 [K] / Margin clamp span [K]
    DL_GRADE_OK      : INT := 0;          // 分级：合格 [level] / Grade: acceptable [level]
    DL_GRADE_WARN    : INT := 1;          // 分级：预警 [level] / Grade: warning [level]
    DL_GRADE_BAD     : INT := 2;          // 分级：不足 [level] / Grade: insufficient [level]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧分级置不足） —— *)
IF NOT (fProductC > -DL_BIG AND fProductC < DL_BIG)
   OR NOT (fCollapseC > -DL_BIG AND fCollapseC < DL_BIG)
   OR NOT (fIcePointC > -DL_BIG AND fIcePointC < DL_BIG)
   OR NOT (fMarginMinK > -DL_BIG AND fMarginMinK < DL_BIG)
   OR NOT (fMarginWarnK > -DL_BIG AND fMarginWarnK < DL_BIG) THEN
    fMarginK := 0.0;                        // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    nGrade := DL_GRADE_BAD;                 // 失效侧按不足处理（保守侧）/ Treat as insufficient when invalid
    xMarginLow := TRUE;                     // 失效侧不足位置真（保守侧）/ Insufficient flag true when invalid
    xAboveIce := FALSE;                     // 失效侧冰点位保持假 / Ice-point flag stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LyoCollapseTempMarginCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：主算式（不钳制，先出原始值供段 3 判据使用，R24） —— *)
_fMarginRawK := fCollapseC - fProductC;                                           // 塌陷温度裕度 [K]

(* —— 段 3：判据与分级（全部取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xMarginLow := (_fMarginRawK < fMarginMinK);                                       // 裕度不足
xAboveIce := (fProductC > fIcePointC);                                            // 已融冰（高于冰点）
xValid := (fMarginMinK < fMarginWarnK)                                            // 分级阈值必须有效（min < warn）
          AND (ABS(fProductC) <= DL_T_SPAN)                                       // 温度量级闸
          AND (ABS(fCollapseC) <= DL_T_SPAN)
          AND (ABS(fIcePointC) <= DL_T_SPAN)
          AND (fCollapseC > fIcePointC);                                          // 塌陷温度须高于冰点（物理约束）

IF NOT xValid THEN
    nGrade := DL_GRADE_BAD;                 // 参数非法：按不足处理（保守侧）
ELSIF _fMarginRawK >= fMarginWarnK THEN
    nGrade := DL_GRADE_OK;                  // 裕度充足
ELSIF _fMarginRawK >= fMarginMinK THEN
    nGrade := DL_GRADE_WARN;                // 预警带
ELSE
    nGrade := DL_GRADE_BAD;                 // 不足
END_IF

(* —— 段 4：输出单点写盘（钳制到物理域内，分级已在段 3 定案） —— *)
fMarginK := LIMIT(-DL_MARGIN_SPAN, _fMarginRawK, DL_MARGIN_SPAN);                  // 裕度钳到物理域 [K]
FC_DL_LyoCollapseTempMarginCalc := xValid;                                        // 返回码：TRUE = 计算可信

END_FUNCTION
