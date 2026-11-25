(*
  Name: FC_DL_GrateCoolerClinkerTempCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 出篦冷机熟料温度按「熟料放热 = 空气吸热」的稳态能量平衡求解：
           熟料放热 = m_cli * cp_cli * (T_in − T_out)，空气吸热 = m_cli * ratio * cp_air * (T_airOut − T_airIn)，
           两式相等并引入换热效率 eff 后反解出口温度：
           T_out = T_in − eff * ratio * (cp_air / cp_cli) * (T_airOut − T_airIn)。
        2) 输出熟料降温幅度 fCoolDropK，即 T_in − T_out，用于判断冷却能力是否达标。
        3) 温度下限保护：反解结果不得低于 DL_TEMP_LO（环境温度下限），低于即判无效，
           因为能量平衡模型在该区间外已不成立（潜热与辐射项未建模）。
  边界条件：1) 非有限值闸：七路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置标志（R19）。
        2) 分母零闸：熟料比热 fClinkerCpKjKgK 与风料比 fAirClinkerRatio 均须 > DL_EPS，
           否则反解式分母为零、结果发散，直接判无效。
        3) 参数域闸：换热效率 fEffRatio 必须落在 (0.0, 1.0] 内（效率大于 1 违反热力学第一定律），
           越域视为组态错误判无效，不钳制（钳制会把非法组态伪装成合法）。
        4) 温差方向闸：空气出口温度必须高于空气入口温度，否则无吸热过程，判无效。
        5) 温度下限：反解出口温度 < DL_TEMP_LO 判无效；上限 DL_TEMP_HI 越限判无效。
        6) 判据取原始值（R24）：温度越域判定使用原始反解值 _fOutRawC，钳制只作用于输出量。
  量纲自证：ratio 为风料质量比 [kg/kg] 无因次；cp_air / cp_cli = (kJ/(kg*K))/(kJ/(kg*K)) 无因次；
           eff 无因次；故 eff*ratio*(cp_air/cp_cli)*(T_airOut−T_airIn) 的量纲为 (K)，
           与 T_in [degC] 相减合法（温差以 K 计、绝对温度以 degC 计，差值同尺度）。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_GrateCoolerClinkerTempCalc : BOOL
VAR_INPUT
    fClinkerInC      : REAL;   // 入篦冷机熟料温度 [degC] / Clinker inlet temperature [degC]
    fAirInC          : REAL;   // 冷却风入口温度（环境）[degC] / Cooling air inlet temperature [degC]
    fAirOutC         : REAL;   // 冷却风出口温度（窑头抽风）[degC] / Cooling air outlet temperature [degC]
    fAirClinkerRatio : REAL;   // 风料质量比 [kg/kg] / Air to clinker mass ratio [kg/kg]
    fAirCpKjKgK      : REAL;   // 空气定压比热 [kJ/(kg*K)] / Air specific heat at constant pressure [kJ/(kg*K)]
    fClinkerCpKjKgK  : REAL;   // 熟料比热 [kJ/(kg*K)] / Clinker specific heat [kJ/(kg*K)]
    fEffRatio        : REAL;   // 篦床换热效率（0~1 无因次）[-] / Grate heat exchange efficiency, dimensionless [-]
END_VAR
VAR_OUTPUT
    fClinkerOutC     : REAL;   // 出篦冷机熟料温度 [degC] / Clinker outlet temperature [degC]
    fCoolDropK       : REAL;   // 熟料降温幅度 [K] / Clinker temperature drop [K]
    xTempLow         : BOOL;   // 出口温度低于下限标志 [bool] / Outlet below lower bound flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fCpRatio        : REAL;   // 空气与熟料比热之比 [-] / Ratio of air to clinker specific heat [-]
    _fAirDeltaK      : REAL;   // 空气温升 [K] / Air temperature rise [K]
    _fOutRawC        : REAL;   // 钳制前的原始出口温度 [degC] / Raw outlet temperature before limiting [degC]
    _fDropRawK       : REAL;   // 钳制前的原始降温幅度 [K] / Raw temperature drop before limiting [K]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_TEMP_LO       : REAL := -50.0;     // 熟料出口温度物理下限 [degC] / Clinker outlet lower bound [degC]
    DL_TEMP_HI       : REAL := 400.0;     // 熟料出口温度物理上限 [degC] / Clinker outlet upper bound [degC]
    DL_EFF_HI        : REAL := 1.0;       // 换热效率物理上限（热力学第一定律）[-] / Efficiency upper bound [-]
    DL_ZERO_K        : REAL := 0.0;       // 温差零基准 [K] / Zero temperature-difference reference [K]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fClinkerInC > -DL_BIG AND fClinkerInC < DL_BIG)
   OR NOT (fAirInC > -DL_BIG AND fAirInC < DL_BIG)
   OR NOT (fAirOutC > -DL_BIG AND fAirOutC < DL_BIG)
   OR NOT (fAirClinkerRatio > -DL_BIG AND fAirClinkerRatio < DL_BIG)
   OR NOT (fAirCpKjKgK > -DL_BIG AND fAirCpKjKgK < DL_BIG)
   OR NOT (fClinkerCpKjKgK > -DL_BIG AND fClinkerCpKjKgK < DL_BIG)
   OR NOT (fEffRatio > -DL_BIG AND fEffRatio < DL_BIG) THEN
    fClinkerOutC := 0.0;                    // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fCoolDropK := 0.0;                      // 降温幅度强制 0.0 / Drop forced to zero
    xTempLow := FALSE;                      // 失效侧不得报低温 / Must not report low temp when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GrateCoolerClinkerTempCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与参数域闸（比热、风料比为零则反解发散） —— *)
IF (fClinkerCpKjKgK <= DL_EPS)                                    // 熟料比热不可为零
   OR (fAirClinkerRatio <= DL_EPS)                                // 风料比不可为零
   OR (fAirCpKjKgK <= DL_EPS)                                     // 空气比热不可为零
   OR (fEffRatio <= DL_EPS)                                       // 换热效率不可为零
   OR (fEffRatio > DL_EFF_HI) THEN                                // 换热效率不得大于 1（热力学第一定律）
    fClinkerOutC := 0.0;                    // 参数不可用即无出口温度 / No parameter, no outlet temperature
    fCoolDropK := 0.0;                      // 降温幅度不可算 / Drop not computable
    xTempLow := FALSE;                      // 失效侧低温位保持假 / Low-temp flag stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GrateCoolerClinkerTempCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fCpRatio := fAirCpKjKgK / fClinkerCpKjKgK;                                       // 比热之比 [-]
_fAirDeltaK := fAirOutC - fAirInC;                                                // 空气温升 [K]
_fOutRawC := fClinkerInC - fEffRatio * fAirClinkerRatio * _fCpRatio * _fAirDeltaK; // 出口温度反解 [degC]
_fDropRawK := fClinkerInC - _fOutRawC;                                            // 降温幅度 [K]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xTempLow := (_fOutRawC < DL_TEMP_LO);                                             // 出口低于物理下限
xValid := (_fAirDeltaK > DL_ZERO_K)                                               // 空气必须吸热（出口高于入口）
          AND (_fOutRawC >= DL_TEMP_LO)                                           // 不跌破物理下限
          AND (_fOutRawC <= DL_TEMP_HI)                                           // 不超出物理上限
          AND (_fDropRawK >= DL_ZERO_K)                                           // 降温幅度不得为负（方向固定）
          AND (fClinkerInC > DL_TEMP_LO);                                         // 入口温度本身须在物理域内

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fClinkerOutC := LIMIT(DL_TEMP_LO, _fOutRawC, DL_TEMP_HI);                          // 出口温度钳物理域 [degC]
fCoolDropK := MAX(DL_ZERO_K, _fDropRawK);                                          // 降温幅度钳 >= 0 [K]
FC_DL_GrateCoolerClinkerTempCalc := xValid;                                        // 返回码：TRUE = 计算可信

END_FUNCTION
