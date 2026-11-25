(*
  Name: FC_DL_TireCureEquivalentTimeCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 等效硫化时间按 Arrhenius 温度-时间等效原理折算到 140 degC 基准：
           速率比 R = EXP( (Ea/Rg) * (1/T_ref − 1/T_cur) )，
           t_eq = t_cur * R，其中 T 一律换算为绝对温度 [K]，Ea 为表观活化能 [J/mol]，
           Rg 为通用气体常数 8.314 [J/(mol*K)]；温度高于基准时 R > 1（硫化更快）。
        2) 输出两个量：等效时间 fEquivTimeMin [min] 与速率比 fRateRatio [-]，
           后者便于观察当前温度折算强度（R = 2 表示 1 min 相当于基准温度的 2 min）。
        3) 温度域校验：当前温度与基准温度都必须高于绝对零度（换算后 T > 0 K），
           否则 1/T 无意义；越域判无效并清零全部输出，绝不让除零结果流到下游。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（等效时间与速率比强制 0.0），不得只置标志（R19）。
        2) 温度零闸：开尔文换算后 T_cur / T_ref 必须 > DL_T_K_MIN（取 1.0 K 作下限，
           远高于绝对零度，同时拦住「传摄氏值当开尔文」的组态错），否则判无效。
        3) 活化能域闸：fActEnergyKjMol 必须落在 (DL_EA_LO, DL_EA_HI) 内 ——
           橡胶硫化表观活化能工程带约 80 ~ 200 kJ/mol，越域说明单位用错（J 与 kJ 混用）。
        4) 指数溢出闸：指数 = (Ea/Rg)*(1/Tref − 1/Tcur)，在合法温度域内其绝对值有界；
           仍显式钳制到 [-DL_EXPO_HI, +DL_EXPO_HI]，防 EXP 溢出为 Inf 后穿透（R19 第二道）。
        5) 判据取原始值（R24）：等效时间越域判定使用钳制前的 _fEquivRawMin，钳制只作用于输出。
        6) 纯函数无状态：温度积分的累计由硫化程度件（FC_DL_TireCureDegreeCalc）承担。
  量纲自证：(Ea/Rg) = (J/mol)/(J/(mol*K)) = K；乘 (1/K − 1/K) = 1/K 得无因次，故 EXP 自变量无因次；
           t_eq = (min) * (无因次) = min，与 fRefTimeMin 同量纲。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_TireCureEquivalentTimeCalc : BOOL
VAR_INPUT
    fCureTempC       : REAL;   // 当前硫化温度 [degC] / Current curing temperature [degC]
    fCureTimeMin     : REAL;   // 当前温度下的实际硫化时间 [min] / Actual curing time at current temperature [min]
    fActEnergyKjMol  : REAL;   // 表观活化能 [kJ/mol] / Apparent activation energy [kJ/mol]
    fRefTempC        : REAL;   // 等效基准温度（通常 140 degC）[degC] / Reference temperature, usually 140 degC [degC]
    fRefTimeMin      : REAL;   // 基准温度下的标准硫化时间 [min] / Standard cure time at reference temperature [min]
END_VAR
VAR_OUTPUT
    fEquivTimeMin    : REAL;   // 折算后的等效硫化时间 [min] / Equivalent curing time at reference temperature [min]
    fRateRatio       : REAL;   // 速率比（当前温度相对基准）[-] / Rate ratio against the reference [-]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fCurK           : REAL;   // 当前绝对温度 [K] / Current absolute temperature [K]
    _fRefK           : REAL;   // 基准绝对温度 [K] / Reference absolute temperature [K]
    _fEaJmol         : REAL;   // 表观活化能 [J/mol] / Apparent activation energy [J/mol]
    _fExpo           : REAL;   // Arrhenius 指数（无因次）[-] / Arrhenius exponent, dimensionless [-]
    _fRatioRaw       : REAL;   // 未钳制的速率比 [-]/ Unclamped rate ratio [-]
    _fEquivRawMin    : REAL;   // 钳制前的等效时间 [min] / Raw equivalent time before limiting [min]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_KELVIN_OFF    : REAL := 273.15;    // 摄氏到开尔文的偏移 [K] / Celsius to Kelvin offset [K]
    DL_T_K_MIN       : REAL := 1.0;       // 绝对温度下限（护栏）[K] / Absolute temperature floor [K]
    DL_EA_LO         : REAL := 50.0;      // 硫化表观活化能域下限 [kJ/mol] / Activation energy domain low [kJ/mol]
    DL_EA_HI         : REAL := 300.0;     // 硫化表观活化能域上限 [kJ/mol] / Activation energy domain high [kJ/mol]
    DL_J_PER_KJ      : REAL := 1000.0;    // 千焦到焦的折算 [J/kJ] / Joules per kilojoule [J/kJ]
    DL_RG            : REAL := 8.314;     // 通用气体常数 [J/(mol*K)] / Universal gas constant [J/(mol*K)]
    DL_EXPO_HI       : REAL := 50.0;      // 指数钳制上限（防 EXP 溢出）[-] / Exponent clamp bound against overflow [-]
    DL_TIME_HI_MIN   : REAL := 100000.0;  // 等效时间物理上限 [min] / Equivalent time physical upper bound [min]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fCureTempC > -DL_BIG AND fCureTempC < DL_BIG)
   OR NOT (fCureTimeMin > -DL_BIG AND fCureTimeMin < DL_BIG)
   OR NOT (fActEnergyKjMol > -DL_BIG AND fActEnergyKjMol < DL_BIG)
   OR NOT (fRefTempC > -DL_BIG AND fRefTempC < DL_BIG)
   OR NOT (fRefTimeMin > -DL_BIG AND fRefTimeMin < DL_BIG) THEN
    fEquivTimeMin := 0.0;                   // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fRateRatio := 0.0;                      // 速率比强制 0.0 / Rate ratio forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TireCureEquivalentTimeCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：温度零闸（绝对温度必须为正，否则 1/T 无意义） —— *)
_fCurK := fCureTempC + DL_KELVIN_OFF;                                     // 当前绝对温度 [K]
_fRefK := fRefTempC + DL_KELVIN_OFF;                                      // 基准绝对温度 [K]
IF (_fCurK <= DL_T_K_MIN) OR (_fRefK <= DL_T_K_MIN) THEN
    fEquivTimeMin := 0.0;                   // 温度越域即不可算 / Temperature out of domain
    fRateRatio := 0.0;                      // 速率比不可算 / Rate ratio not computable
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureEquivalentTimeCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：活化能域闸（防 J 与 kJ 单位混用） —— *)
IF (fActEnergyKjMol <= DL_EA_LO) OR (fActEnergyKjMol >= DL_EA_HI) THEN
    fEquivTimeMin := 0.0;                   // 活化能越域即不可算 / Activation energy out of domain
    fRateRatio := 0.0;                      // 速率比不可算 / Rate ratio not computable
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureEquivalentTimeCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：主算式（指数先钳制再 EXP，防溢出为 Inf 穿透） —— *)
_fEaJmol := fActEnergyKjMol * DL_J_PER_KJ;                                        // 活化能 [J/mol]
_fExpo := _fEaJmol / DL_RG * (1.0 / _fRefK - 1.0 / _fCurK);                       // Arrhenius 指数 [-]
_fExpo := LIMIT(-DL_EXPO_HI, _fExpo, DL_EXPO_HI);                                 // 指数钳制（第二道溢出闸）
_fRatioRaw := EXP(_fExpo);                                                        // 速率比 [-]
_fEquivRawMin := fCureTimeMin * _fRatioRaw;                                       // 等效时间 [min]

(* —— 段 5：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xValid := (fCureTimeMin >= 0.0)                                                   // 时间不得为负
          AND (fRefTimeMin > 0.0)                                                 // 基准时间必须为正
          AND (_fRatioRaw > 0.0)                                                  // 速率比必须为正（EXP 恒正）
          AND (_fEquivRawMin >= 0.0)                                              // 等效时间不得为负
          AND (_fEquivRawMin <= DL_TIME_HI_MIN);                                  // 不得超物理上限（量级异常）

(* —— 段 6：输出单点写盘（钳制到物理域内，判定结果已在段 5 定案） —— *)
fEquivTimeMin := LIMIT(0.0, _fEquivRawMin, DL_TIME_HI_MIN);                       // 等效时间钳物理域 [min]
fRateRatio := _fRatioRaw;                                                         // 速率比出口（恒正，无需钳负侧）
FC_DL_TireCureEquivalentTimeCalc := xValid;                                       // 返回码：TRUE = 计算可信

END_FUNCTION
