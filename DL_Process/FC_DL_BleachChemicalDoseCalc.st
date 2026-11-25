(*
  Name: FC_DL_BleachChemicalDoseCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 漂白剂投加量分两步计算：
           ① 需投加的有效氯质量：m_Cl[kg] = V[L] * C[g/L] / 1000，
              其中 V 为染浴（工作液）体积、C 为目标有效氯浓度 [g/L]，1000 为 g 到 kg 的折算；
           ② 折算为商品漂白剂质量：m_dose[kg] = m_Cl * 100 / fAvailClPct，
              其中 fAvailClPct 为商品漂白剂的有效氯质量分数 [%]。
        2) 投加上限校验：m_dose 超过 fDoseMaxKg（单批允许最大投加量，受设备与人机工程限制）时
           只置 xDoseOver 并钳到上限，绝不把越限值当作可执行投加指令下发。
        3) 浓度量级校验：目标浓度落在 (0.0, DL_CONC_HI_GPL) 内，有效氯含量落在 (0.0, 100.0] 内，
           越域说明单位用错（g/L 与 %(w/w) 混用）或组态未完成，判无效。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（有效氯质量与投加量强制 0.0），不得只置标志（R19）。
        2) 有效氯零闸：fAvailClPct 必须 > DL_EPS（投加量式的分母），
           为零时投加量发散，判无效并清零，绝不输出「无穷大投加量」。
        3) 液量非负闸：染浴体积不得为负（负体积属液位计反向或组态错），判无效。
        4) 上限域闸：fDoseMaxKg 必须 > DL_EPS，否则钳制会把一切投加量抹平为 0，
           使漂白工序静默失效，故判无效而非输出 0。
        5) 判据取原始值（R24）：投加量越限判定使用钳制前的 _fDoseRawKg，钳制只作用于输出。
        6) 纯函数无状态：实际投加的计量泵行程与流量积分由上层加药 FB 承担。
  量纲自证：V[L] * C[g/L] = g；g / 1000 = kg；
           m_dose = kg * 100 / (无因次百分数) = kg，量纲链闭合。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_BleachChemicalDoseCalc : BOOL
VAR_INPUT
    fLiquorVolL      : REAL;   // 染浴（工作液）体积 [L] / Bleach bath working volume [L]
    fTargetConcGpl   : REAL;   // 目标有效氯浓度 [g/L] / Target available chlorine concentration [g/L]
    fAvailClPct      : REAL;   // 商品漂白剂有效氯质量分数 [%] / Available chlorine mass fraction [%]
    fDoseMaxKg       : REAL;   // 单批允许最大投加量 [kg] / Maximum dose per batch [kg]
END_VAR
VAR_OUTPUT
    fActiveClKg      : REAL;   // 需投加的有效氯质量 [kg] / Required available chlorine mass [kg]
    fDoseKg          : REAL;   // 商品漂白剂投加量 [kg] / Commercial bleach dose [kg]
    xDoseOver        : BOOL;   // 投加量超上限标志 [bool] / Dose overrun flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fClRawKg        : REAL;   // 钳制前的有效氯质量 [kg] / Raw chlorine mass before limiting [kg]
    _fDoseRawKg      : REAL;   // 钳制前的投加量 [kg] / Raw dose before limiting [kg]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_G_PER_KG      : REAL := 1000.0;    // 克到千克的折算 [g/kg] / Grams per kilogram [g/kg]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_CONC_HI_GPL   : REAL := 100.0;     // 有效氯浓度量级闸上限 [g/L] / Concentration magnitude upper bound [g/L]
    DL_PCT_HI        : REAL := 100.0;     // 有效氯含量物理上限 [%] / Available chlorine upper bound [%]
    DL_DOSE_HI_KG    : REAL := 10000.0;   // 投加量物理上限 [kg] / Dose physical upper bound [kg]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fLiquorVolL > -DL_BIG AND fLiquorVolL < DL_BIG)
   OR NOT (fTargetConcGpl > -DL_BIG AND fTargetConcGpl < DL_BIG)
   OR NOT (fAvailClPct > -DL_BIG AND fAvailClPct < DL_BIG)
   OR NOT (fDoseMaxKg > -DL_BIG AND fDoseMaxKg < DL_BIG) THEN
    fActiveClKg := 0.0;                     // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDoseKg := 0.0;                         // 投加量强制 0.0 / Dose forced to zero
    xDoseOver := TRUE;                      // 失效侧按超限处理（保守侧：禁止投加）
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_BleachChemicalDoseCalc := FALSE;  // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：有效氯零闸与域闸（分母为有效氯含量） —— *)
IF (fAvailClPct <= DL_EPS)                                        // 有效氯含量不可为零
   OR (fAvailClPct > DL_PCT_HI)                                   // 有效氯含量不得超 100 %
   OR (fLiquorVolL < 0.0)                                         // 液量不得为负
   OR (fTargetConcGpl < 0.0)                                      // 目标浓度不得为负
   OR (fTargetConcGpl > DL_CONC_HI_GPL)                           // 目标浓度不得超量级闸
   OR (fDoseMaxKg <= DL_EPS) THEN                                 // 投加上限必须已组态
    fActiveClKg := 0.0;                     // 参数不可用即无投加 / No parameter, no dose
    fDoseKg := 0.0;                         // 投加量不可算 / Dose not computable
    xDoseOver := TRUE;                      // 按超限处理（保守侧）/ Treat as over the limit
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_BleachChemicalDoseCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fClRawKg := fLiquorVolL * fTargetConcGpl / DL_G_PER_KG;                          // 有效氯质量 [kg]
_fDoseRawKg := _fClRawKg * DL_PCT / fAvailClPct;                                  // 商品投加量 [kg]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xDoseOver := (_fDoseRawKg > fDoseMaxKg);                                           // 投加量超单批上限
xValid := (_fClRawKg >= 0.0)                                                      // 有效氯质量不得为负
          AND (_fDoseRawKg >= 0.0)                                                // 投加量不得为负
          AND (_fDoseRawKg <= DL_DOSE_HI_KG)                                      // 不超物理上限（量级异常）
          AND (fDoseMaxKg <= DL_DOSE_HI_KG);                                      // 上限须在物理域内

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fActiveClKg := LIMIT(0.0, _fClRawKg, DL_DOSE_HI_KG);                              // 有效氯质量钳物理域 [kg]
fDoseKg := LIMIT(0.0, _fDoseRawKg, fDoseMaxKg);                                   // 投加量钳 0..工艺上限 [kg]
FC_DL_BleachChemicalDoseCalc := xValid;                                           // 返回码：TRUE = 计算可信

END_FUNCTION
