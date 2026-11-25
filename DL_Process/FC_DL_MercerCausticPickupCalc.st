(*
  Name: FC_DL_MercerCausticPickupCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 丝光碱液带液量（带碱率）按「轧余率 × 碱浓度 / 碱液密度」计算：
           pickup[g/kg 布] = (fPickupPct / 100) * fConcGpl / fDensityKgl，
           其中 fPickupPct 为轧余率（带液量占布重的百分数）、fConcGpl 为碱质量浓度 [g/L]、
           fDensityKgl 为碱液密度 [kg/L]。
           量纲推导： (kg液/kg布) * (g/L) / (kg/L) = (kg液/kg布) * (g/kg液) = g/kg布，故无额外折算因子。
        2) 派生量：fLiquorKgKg = 每公斤布带走的碱液质量 [kg/kg]，用于核算碱液损耗与回收负荷。
        3) 工艺域判定：带碱率低于 fPickupMinGkg 判丝光不足（纤维膨化不够、光泽与尺寸稳定性差），
           高于 fPickupMaxGkg 判过轧（碱耗高、后续中和负荷大）。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（带碱率与带液量强制 0.0 且置不足位，保守侧），不得只置标志（R19）。
        2) 密度零闸：fDensityKgl 必须 > DL_EPS（带碱率式的分母），为零则结果发散，判无效。
        3) 浓度量级闸：fConcGpl 必须落在 (0.0, DL_CONC_HI_GPL) 内 ——
           丝光碱浓工程带约 180 ~ 300 g/L，越域说明单位用错（g/L 与 %(w/w) 混用）或测点失效。
        4) 轧余率域闸：fPickupPct 必须落在 [0.0, DL_PICKUP_HI_PCT] 内（超过 200 % 不具物理意义）。
        5) 工艺域闸：须满足 0.0 < fPickupMinGkg < fPickupMaxGkg，越域判无效（判据重叠则永不同时报）。
        6) 判据取原始值（R24）：工艺域判定使用钳制前的 _fPickupRawGkg，钳制只作用于输出。
  量纲自证：见功能 1) 的量纲推导，最终量纲为 g/kg（每公斤布带的纯碱克数）；
           fLiquorKgKg = (kg 液)/(kg 布) = kg/kg，无因次质量比。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_MercerCausticPickupCalc : BOOL
VAR_INPUT
    fPickupPct       : REAL;   // 轧余率（带液量占布重百分比）[%] / Wet pickup percentage [%]
    fConcGpl         : REAL;   // 碱液质量浓度 [g/L] / Caustic mass concentration [g/L]
    fDensityKgl      : REAL;   // 碱液密度 [kg/L] / Caustic liquor density [kg/L]
    fPickupMinGkg    : REAL;   // 带碱率工艺下限 [g/kg] / Caustic pickup process low limit [g/kg]
    fPickupMaxGkg    : REAL;   // 带碱率工艺上限 [g/kg] / Caustic pickup process high limit [g/kg]
END_VAR
VAR_OUTPUT
    fPickupGkg       : REAL;   // 带碱率（每公斤布的纯碱克数）[g/kg] / Caustic pickup per kg of fabric [g/kg]
    fLiquorKgKg      : REAL;   // 每公斤布带走的碱液质量 [kg/kg] / Caustic liquor carried per kg of fabric [kg/kg]
    xPickupLow       : BOOL;   // 带碱率不足标志 [bool] / Caustic pickup below the low limit flag [bool]
    xPickupHigh      : BOOL;   // 带碱率过高标志 [bool] / Caustic pickup above the high limit flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fLiquorRawKgKg  : REAL;   // 钳制前的带液量 [kg/kg] / Raw liquor mass ratio before limiting [kg/kg]
    _fPickupRawGkg   : REAL;   // 钳制前的带碱率 [g/kg] / Raw caustic pickup before limiting [g/kg]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_CONC_HI_GPL   : REAL := 1000.0;    // 碱浓量级闸上限 [g/L] / Concentration magnitude upper bound [g/L]
    DL_PICKUP_HI_PCT : REAL := 200.0;     // 轧余率物理上限 [%] / Wet pickup physical upper bound [%]
    DL_PICKUP_HI_GKG : REAL := 1000.0;    // 带碱率物理上限 [g/kg] / Caustic pickup upper bound [g/kg]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧置不足位，保守侧） —— *)
IF NOT (fPickupPct > -DL_BIG AND fPickupPct < DL_BIG)
   OR NOT (fConcGpl > -DL_BIG AND fConcGpl < DL_BIG)
   OR NOT (fDensityKgl > -DL_BIG AND fDensityKgl < DL_BIG)
   OR NOT (fPickupMinGkg > -DL_BIG AND fPickupMinGkg < DL_BIG)
   OR NOT (fPickupMaxGkg > -DL_BIG AND fPickupMaxGkg < DL_BIG) THEN
    fPickupGkg := 0.0;                      // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fLiquorKgKg := 0.0;                     // 带液量强制 0.0 / Liquor ratio forced to zero
    xPickupLow := TRUE;                     // 失效侧按不足处理（保守侧）/ Treat as insufficient when invalid
    xPickupHigh := FALSE;                   // 失效侧过高位保持假 / High flag stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_MercerCausticPickupCalc := FALSE; // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：密度零闸与域闸（密度为带碱率分母） —— *)
IF (fDensityKgl <= DL_EPS)                                        // 密度不可为零
   OR (fConcGpl <= 0.0)                                           // 碱浓必须为正（无碱即无丝光）
   OR (fConcGpl > DL_CONC_HI_GPL)                                 // 碱浓不得超量级闸
   OR (fPickupPct < 0.0)                                          // 轧余率不得为负
   OR (fPickupPct > DL_PICKUP_HI_PCT)                             // 轧余率不得超物理上限
   OR (fPickupMinGkg <= 0.0)                                      // 工艺下限必须为正
   OR (fPickupMaxGkg <= fPickupMinGkg) THEN                       // 工艺上限必须严格大于下限
    fPickupGkg := 0.0;                      // 参数不可用即不可算 / No parameter, no pickup
    fLiquorKgKg := 0.0;                     // 带液量不可算 / Liquor ratio not computable
    xPickupLow := TRUE;                     // 按不足处理（保守侧）/ Treat as insufficient
    xPickupHigh := FALSE;                   // 过高位保持假 / High flag stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_MercerCausticPickupCalc := FALSE; // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fLiquorRawKgKg := fPickupPct / DL_PCT;                                           // 带液量 [kg/kg]
_fPickupRawGkg := _fLiquorRawKgKg * fConcGpl / fDensityKgl;                        // 带碱率 [g/kg]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xPickupLow := (_fPickupRawGkg < fPickupMinGkg);                                    // 丝光不足
xPickupHigh := (_fPickupRawGkg > fPickupMaxGkg);                                   // 过轧
xValid := (_fPickupRawGkg >= 0.0)                                                  // 带碱率不得为负
          AND (_fPickupRawGkg <= DL_PICKUP_HI_GKG)                                 // 不超物理上限（量级异常）
          AND (fPickupMaxGkg <= DL_PICKUP_HI_GKG)                                  // 工艺上限须在物理域内
          AND (_fLiquorRawKgKg >= 0.0);                                            // 带液量不得为负

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fPickupGkg := LIMIT(0.0, _fPickupRawGkg, DL_PICKUP_HI_GKG);                        // 带碱率钳物理域 [g/kg]
fLiquorKgKg := LIMIT(0.0, _fLiquorRawKgKg, DL_PICKUP_HI_PCT / DL_PCT);             // 带液量钳物理域 [kg/kg]
FC_DL_MercerCausticPickupCalc := xValid;                                           // 返回码：TRUE = 计算可信

END_FUNCTION
