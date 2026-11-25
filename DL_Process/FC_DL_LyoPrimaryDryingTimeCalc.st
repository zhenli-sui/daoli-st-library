(*
  Name: FC_DL_LyoPrimaryDryingTimeCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 一次干燥时间按「可去除水量 / 升华速率」估算：
           可去除水量 W = 装量质量 * (初始含水率 − 目标含水率) / 100，单位 kg；
           时间 t = W / rate，单位 h；rate 为该批量的实测升华速率 [kg/h]。
        2) 水量守恒校验：目标含水率必须低于初始含水率，否则水量为负（配方错），
           判无效而不取绝对值 —— 负水量意味着「越干越湿」的错误配方。
        3) 收敛判据：估算时间超过 fMaxTimeH（工艺允许最长一次干燥时间）时置 xNotConverge，
           表示按当前速率无法在允许时间内达到目标含水率，需提高搁板温度或降低装量。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（时间与水量强制 0.0），不得只置标志（R19）。
        2) 速率零闸：升华速率 fRateKgh 必须 > DL_EPS（时间式的分母），否则判无效并清零，
           不得输出「无穷长时间」这种不可执行值。
        3) 含水率域闸：初始与目标含水率必须落在 [0.0, 100.0] % 内，
           装量质量须 > DL_EPS；任一越域判无效，不做钳制。
        4) 判据取原始值（R24）：不收敛判定使用钳制前的 _fTimeRawH，不得先钳再判。
        5) 物理域钳制：时间钳 0.0 ~ DL_TIME_HI_H；水量钳 0.0 ~ 装量质量（水量不可能大于装量）。
        6) 纯函数无状态：不累计已干燥时间，累计与阶段切换由干燥序 FB 承担。
  量纲自证：W = (kg) * (无因次百分数/100) = kg；
           t = (kg)/(kg/h) = h，与 fMaxTimeH 同量纲 [h]，可直接比较。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_LyoPrimaryDryingTimeCalc : BOOL
VAR_INPUT
    fFillMassKg      : REAL;   // 单批装量质量 [kg] / Batch fill mass [kg]
    fInitMoistPct    : REAL;   // 初始含水率 [%] / Initial moisture content [%]
    fTargetMoistPct  : REAL;   // 目标含水率 [%] / Target moisture content [%]
    fRateKgh         : REAL;   // 该批量实测升华速率 [kg/h] / Measured batch sublimation rate [kg/h]
    fMaxTimeH        : REAL;   // 工艺允许最长一次干燥时间 [h] / Permitted maximum primary drying time [h]
END_VAR
VAR_OUTPUT
    fTimeH           : REAL;   // 一次干燥估算时间 [h] / Estimated primary drying time [h]
    fWaterKg         : REAL;   // 需去除水量 [kg] / Water mass to be removed [kg]
    xNotConverge     : BOOL;   // 超允许时间标志（不收敛）[bool] / Non-convergence flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fWaterRawKg     : REAL;   // 钳制前的原始水量 [kg] / Raw water mass before limiting [kg]
    _fTimeRawH       : REAL;   // 钳制前的原始时间 [h] / Raw time before limiting [h]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子（含水率分母）[%] / Percent conversion factor [%]
    DL_PCT_HI        : REAL := 100.0;     // 含水率物理上限 [%] / Moisture content upper bound [%]
    DL_TIME_HI_H     : REAL := 10000.0;   // 时间物理上限 [h] / Time physical upper bound [h]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fFillMassKg > -DL_BIG AND fFillMassKg < DL_BIG)
   OR NOT (fInitMoistPct > -DL_BIG AND fInitMoistPct < DL_BIG)
   OR NOT (fTargetMoistPct > -DL_BIG AND fTargetMoistPct < DL_BIG)
   OR NOT (fRateKgh > -DL_BIG AND fRateKgh < DL_BIG)
   OR NOT (fMaxTimeH > -DL_BIG AND fMaxTimeH < DL_BIG) THEN
    fTimeH := 0.0;                          // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fWaterKg := 0.0;                        // 水量强制 0.0 / Water mass forced to zero
    xNotConverge := TRUE;                   // 失效侧按不收敛处理（安全侧）/ Treat as non-converged when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LyoPrimaryDryingTimeCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与域闸（时间式分母为速率；含水率须在 0~100 %） —— *)
IF (fRateKgh <= DL_EPS)                                           // 速率不可为零
   OR (fFillMassKg <= DL_EPS)                                     // 装量不可为零
   OR (fInitMoistPct < 0.0)                                       // 含水率不得为负
   OR (fInitMoistPct > DL_PCT_HI)                                 // 含水率不得超 100 %
   OR (fTargetMoistPct < 0.0)                                     // 目标含水率不得为负
   OR (fTargetMoistPct > DL_PCT_HI)                               // 目标含水率不得超 100 %
   OR (fMaxTimeH <= DL_EPS) THEN                                  // 允许时间必须已组态
    fTimeH := 0.0;                          // 参数不可用即无时间 / No parameter, no time
    fWaterKg := 0.0;                        // 水量不可算 / Water mass not computable
    xNotConverge := TRUE;                   // 按不收敛处理 / Treat as non-converged
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LyoPrimaryDryingTimeCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fWaterRawKg := fFillMassKg * (fInitMoistPct - fTargetMoistPct) / DL_PCT;          // 需去除水量 [kg]
_fTimeRawH := _fWaterRawKg / fRateKgh;                                            // 估算时间 [h]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xNotConverge := (_fTimeRawH > fMaxTimeH);                                         // 超允许时间：不收敛
xValid := (_fWaterRawKg >= 0.0)                                                   // 水量不得为负（配方方向固定）
          AND (_fTimeRawH >= 0.0)                                                 // 时间不得为负
          AND (fMaxTimeH <= DL_TIME_HI_H)                                         // 允许时间不得超物理上限
          AND (fInitMoistPct > fTargetMoistPct);                                  // 初始必须高于目标（方向固定）

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fWaterKg := LIMIT(0.0, _fWaterRawKg, fFillMassKg);                                // 水量钳 0..装量 [kg]
fTimeH := LIMIT(0.0, _fTimeRawH, DL_TIME_HI_H);                                   // 时间钳 0..物理上限 [h]
FC_DL_LyoPrimaryDryingTimeCalc := xValid;                                         // 返回码：TRUE = 计算可信

END_FUNCTION
