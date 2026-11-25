(*
  Name: FC_DL_TireCureDegreeCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 硫化程度按「实际等效硫化时间 / 目标等效硫化时间」计算并折百分比：
           degree = t_equiv / t_target * 100，其中 t_equiv 由 FC_DL_TireCureEquivalentTimeCalc
           给出的 140 degC 基准当量时间（本件不重复其换算，只做比值判据，故本件仍自包含无依赖）。
        2) 欠硫 / 过硫判定：degree < fUnderPct 判欠硫（物理性能不达标，须延长硫化）；
           degree > fOverPct 判过硫（返原、断裂伸长下降，须缩短硫化或降低模温）。
           两个阈值各占一个独立布尔出口，供上层分别处置（欠硫可补救，过硫不可逆）。
        3) 输出硫化程度百分比同时钳到 [0.0, DL_DEG_HI]（DL_DEG_HI = 200 %），
           保留超硫观测余量的同时避免极端值污染趋势曲线。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（程度强制 0.0 且置欠硫位，保守侧），不得只置标志（R19）。
        2) 分母零闸：目标等效时间 fTargetEquivMin 必须 > DL_EPS（比值式分母），
           否则判无效并清零 —— 输出「未组态即 0 %」会被误读为「完全没有硫化」。
        3) 阈值域闸：须满足 0.0 < fUnderPct < fOverPct <= DL_DEG_HI，否则两级判据重叠或倒置，
           越域判无效并把欠硫位置真（保守侧）。
        4) 时间非负闸：实际等效时间不得为负（负值属积分方向错误），判无效。
        5) 判据取原始值（R24）：欠硫/过硫判定使用钳制前的 _fDegreeRawPct，不得先钳再判。
        6) 纯函数无状态：等效时间本身的积分与累计由上层硫化序 FB 承担。
  量纲自证：degree = (min)/(min)*100 = 无因次百分数 [%]；
           fUnderPct / fOverPct 同为百分数，可与 degree 直接比较，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_TireCureDegreeCalc : BOOL
VAR_INPUT
    fEquivTimeMin    : REAL;   // 实际等效硫化时间（140 degC 基准）[min] / Actual equivalent cure time [min]
    fTargetEquivMin  : REAL;   // 目标等效硫化时间 [min] / Target equivalent cure time [min]
    fUnderPct        : REAL;   // 欠硫判定阈值 [%] / Under-cure threshold [%]
    fOverPct         : REAL;   // 过硫判定阈值 [%] / Over-cure threshold [%]
END_VAR
VAR_OUTPUT
    fDegreePct       : REAL;   // 硫化程度 [%] / Degree of cure [%]
    xUnderCure       : BOOL;   // 欠硫标志 [bool] / Under-cure flag [bool]
    xOverCure        : BOOL;   // 过硫标志 [bool] / Over-cure flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDegreeRawPct   : REAL;   // 钳制前的原始硫化程度 [%] / Raw degree of cure before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_DEG_HI        : REAL := 200.0;     // 硫化程度显示上限（留过硫观测余量）[%] / Degree display ceiling [%]
    DL_ZERO_PCT      : REAL := 0.0;       // 百分数零基准 [%] / Zero percent reference [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧置欠硫位，保守侧） —— *)
IF NOT (fEquivTimeMin > -DL_BIG AND fEquivTimeMin < DL_BIG)
   OR NOT (fTargetEquivMin > -DL_BIG AND fTargetEquivMin < DL_BIG)
   OR NOT (fUnderPct > -DL_BIG AND fUnderPct < DL_BIG)
   OR NOT (fOverPct > -DL_BIG AND fOverPct < DL_BIG) THEN
    fDegreePct := 0.0;                      // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    xUnderCure := TRUE;                     // 失效侧按欠硫处理（保守侧：宁可延长不可放行）
    xOverCure := FALSE;                     // 失效侧过硫位保持假 / Over-cure stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TireCureDegreeCalc := FALSE;      // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与阈值域闸（目标时间为比值分母） —— *)
IF (fTargetEquivMin <= DL_EPS)                                    // 目标时间不可为零
   OR (fEquivTimeMin < 0.0)                                       // 实际时间不得为负
   OR (fUnderPct <= DL_ZERO_PCT)                                  // 欠硫阈值必须为正
   OR (fOverPct <= fUnderPct)                                     // 过硫阈值必须大于欠硫阈值
   OR (fOverPct > DL_DEG_HI) THEN                                 // 过硫阈值不得超显示上限
    fDegreePct := 0.0;                      // 参数不可用即无程度 / No parameter, no degree
    xUnderCure := TRUE;                     // 按欠硫处理（保守侧）/ Treat as under-cured
    xOverCure := FALSE;                     // 过硫位保持假 / Over-cure stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureDegreeCalc := FALSE;      // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fDegreeRawPct := fEquivTimeMin / fTargetEquivMin * DL_PCT;                       // 硫化程度 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xUnderCure := (_fDegreeRawPct < fUnderPct);                                       // 欠硫
xOverCure := (_fDegreeRawPct > fOverPct);                                         // 过硫
xValid := (_fDegreeRawPct >= DL_ZERO_PCT)                                         // 程度不得为负（方向固定）
          AND (_fDegreeRawPct <= DL_DEG_HI);                                      // 不得超显示上限（量级异常）

(* —— 段 5：输出单点写盘（钳制到显示域内，判定结果已在段 4 定案） —— *)
fDegreePct := LIMIT(DL_ZERO_PCT, _fDegreeRawPct, DL_DEG_HI);                      // 程度钳 0..200 [%]
FC_DL_TireCureDegreeCalc := xValid;                                               // 返回码：TRUE = 计算可信

END_FUNCTION
