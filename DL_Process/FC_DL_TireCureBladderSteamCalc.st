(*
  Name: FC_DL_TireCureBladderSteamCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 单周期胶囊蒸汽耗量按「充装量 + 升温量 + 排凝损失」三段求和：
           充装量 = 胶囊容积 * 蒸汽密度；
           升温量 = 胶囊内容物质量 * 比热 * 温升 / 潜热（把显热需求折成蒸汽质量）；
           排凝损失 = (充装量 + 升温量) * fDrainPct / 100。
           即 m = (V*rho + m*cp*dT/hfg) * (1 + drainPct/100)，单位 kg/周期。
        2) 输出分解量 fFillKg 与 fHeatUpKg，便于按段归因能耗（充装段与升温段的节能措施完全不同）。
        3) 容积零闸与潜热零闸：胶囊容积为充装量的乘子、潜热为升温量的分母，
           任一为零会把「未组态」伪装成「零耗量」，必须判无效而非输出 0。
  边界条件：1) 非有限值闸：七路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（三段耗量与总耗量强制 0.0），不得只置标志（R19）。
        2) 分母零闸：升华/汽化潜热 fLatentKjKg 必须 > DL_EPS；胶囊内容物比热 fWaterCpKjKgK 必须 > DL_EPS。
        3) 容积零闸：fBladderVolL 必须 > DL_EPS；蒸汽密度 fSteamDensityKgm3 必须 > DL_EPS。
        4) 排凝率域闸：fDrainPct 必须落在 [0.0, DL_DRAIN_HI] 内（排凝率超 100 % 不具物理意义），
           越域判无效不钳制。
        5) 判据取原始值（R24）：总量越域判定使用钳制前的 _fTotalRawKg，钳制只作用于输出。
        6) 纯函数无状态：单周期耗量的累计与班产统计由上层计量模块承担。
  量纲自证：V [L] * rho [kg/m3] / 1000 [L/m3] = kg；
           m [kg] * cp [kJ/(kg*K)] * dT [K] = kJ；kJ / hfg [kJ/kg] = kg；
           三段同为 kg，求和合法；排凝率为无因次百分数，乘 kg 仍为 kg。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_TireCureBladderSteamCalc : BOOL
VAR_INPUT
    fBladderVolL     : REAL;   // 胶囊有效容积 [L] / Effective bladder volume [L]
    fSteamDensityKgm3 : REAL;  // 工作压力下蒸汽密度 [kg/m3] / Steam density at working pressure [kg/m3]
    fContentMassKg   : REAL;   // 胶囊内容物（水/氮）质量 [kg] / Bladder content mass [kg]
    fWaterCpKjKgK    : REAL;   // 内容物比热 [kJ/(kg*K)] / Content specific heat [kJ/(kg*K)]
    fTempRiseK       : REAL;   // 升温幅度 [K] / Temperature rise [K]
    fLatentKjKg      : REAL;   // 工作压力下汽化潜热 [kJ/kg] / Latent heat of vaporisation [kJ/kg]
    fDrainPct        : REAL;   // 排凝损失占充装与升温之和的百分比 [%] / Blowdown loss percentage [%]
END_VAR
VAR_OUTPUT
    fFillKg          : REAL;   // 充装段蒸汽量 [kg] / Steam for initial filling [kg]
    fHeatUpKg        : REAL;   // 升温段蒸汽量 [kg] / Steam for heat-up [kg]
    fSteamKg         : REAL;   // 单周期蒸汽总耗量 [kg/cycle] / Total steam consumption per cycle [kg/cycle]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fFillRawKg      : REAL;   // 钳制前的充装量 [kg] / Raw fill mass [kg]
    _fHeatRawKg      : REAL;   // 钳制前的升温量 [kg] / Raw heat-up mass [kg]
    _fTotalRawKg     : REAL;   // 钳制前的总量 [kg] / Raw total mass [kg]
    _fDrainFactor    : REAL;   // 排凝放大因子（1 + 排凝率/100）[-] / Blowdown multiplier [-]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_L_PER_M3      : REAL := 1000.0;    // 立方米到升的折算 [L/m3] / Litres per cubic metre [L/m3]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_DRAIN_HI      : REAL := 100.0;     // 排凝率物理上限 [%] / Blowdown percentage upper bound [%]
    DL_STEAM_HI_KG   : REAL := 5000.0;    // 单周期耗量物理上限 [kg] / Steam mass physical upper bound [kg]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fBladderVolL > -DL_BIG AND fBladderVolL < DL_BIG)
   OR NOT (fSteamDensityKgm3 > -DL_BIG AND fSteamDensityKgm3 < DL_BIG)
   OR NOT (fContentMassKg > -DL_BIG AND fContentMassKg < DL_BIG)
   OR NOT (fWaterCpKjKgK > -DL_BIG AND fWaterCpKjKgK < DL_BIG)
   OR NOT (fTempRiseK > -DL_BIG AND fTempRiseK < DL_BIG)
   OR NOT (fLatentKjKg > -DL_BIG AND fLatentKjKg < DL_BIG)
   OR NOT (fDrainPct > -DL_BIG AND fDrainPct < DL_BIG) THEN
    fFillKg := 0.0;                         // 充装量强制 0.0 / Fill mass forced to zero
    fHeatUpKg := 0.0;                       // 升温量强制 0.0 / Heat-up mass forced to zero
    fSteamKg := 0.0;                        // 总量强制 0.0，切断污染源 / Total forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TireCureBladderSteamCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与域闸（容积/密度为乘子，潜热/比热为分母） —— *)
IF (fBladderVolL <= DL_EPS)                                       // 容积不可为零
   OR (fSteamDensityKgm3 <= DL_EPS)                               // 蒸汽密度不可为零
   OR (fContentMassKg < 0.0)                                      // 内容物质量不得为负
   OR (fWaterCpKjKgK <= DL_EPS)                                   // 比热不可为零
   OR (fTempRiseK < 0.0)                                          // 升温幅度不得为负（方向固定）
   OR (fLatentKjKg <= DL_EPS)                                     // 潜热不可为零
   OR (fDrainPct < 0.0)                                           // 排凝率不得为负
   OR (fDrainPct > DL_DRAIN_HI) THEN                              // 排凝率不得超 100 %
    fFillKg := 0.0;                         // 参数不可用即无耗量 / No parameter, no consumption
    fHeatUpKg := 0.0;                       // 升温量不可算 / Heat-up mass not computable
    fSteamKg := 0.0;                        // 总量不可算 / Total not computable
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureBladderSteamCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fFillRawKg := fBladderVolL / DL_L_PER_M3 * fSteamDensityKgm3;                     // 充装段 [kg]
_fHeatRawKg := fContentMassKg * fWaterCpKjKgK * fTempRiseK / fLatentKjKg;          // 升温段折蒸汽 [kg]
_fDrainFactor := 1.0 + fDrainPct / DL_PCT;                                        // 排凝放大因子 [-]
_fTotalRawKg := (_fFillRawKg + _fHeatRawKg) * _fDrainFactor;                       // 单周期总量 [kg]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xValid := (_fFillRawKg >= 0.0)                                                    // 充装量不得为负
          AND (_fHeatRawKg >= 0.0)                                                // 升温量不得为负
          AND (_fTotalRawKg >= 0.0)                                               // 总量不得为负
          AND (_fTotalRawKg <= DL_STEAM_HI_KG);                                   // 不得超物理上限（量级异常）

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fFillKg := LIMIT(0.0, _fFillRawKg, DL_STEAM_HI_KG);                               // 充装段钳物理域 [kg]
fHeatUpKg := LIMIT(0.0, _fHeatRawKg, DL_STEAM_HI_KG);                             // 升温段钳物理域 [kg]
fSteamKg := LIMIT(0.0, _fTotalRawKg, DL_STEAM_HI_KG);                             // 总量钳物理域 [kg/cycle]
FC_DL_TireCureBladderSteamCalc := xValid;                                         // 返回码：TRUE = 计算可信

END_FUNCTION
