(*
  Name: FC_DL_PreheaterCyclonePressureCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 旋风筒压损按局部阻力式 dP = zeta * rho * v^2 / 2 计算，再折 kPa：
           fCycloneDpKpa = zeta * fGasDensityKgm3 * v^2 / 2 / 1000，
           其中 zeta 为旋风筒进出口综合阻力系数（含内筒插入深度经验项）。
        2) 负荷率 fDpLoadPct = 压损 / 设备许可压损上限 * 100，用于判断系统是否接近风机能力极限。
        3) 堵塞风险判据：入口风速低于 fVelBlockMs 时判 xBlockRisk（低风速不能维持旋流的
           携带能力，粉尘易在锥体沉积），该判据与压损超限判据并行独立输出。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置标志（R19）。
        2) 分母零闸：设备许可压损上限 fDpMaxKpa 必须 > DL_EPS（负荷率的分母），否则判无效。
        3) 物理域闸：气体密度 fGasDensityKgm3 必须 > 0（密度为零即非真实气体），
           阻力系数 fResistCoef 必须 > 0，入口风速不得为负；任一越界判无效，不钳制。
        4) 风速上限：入口风速超过 DL_VEL_HI_MS 判无效（超上限说明测点或管径组态错误，
           此时压损式的外推已失真），不把超限值当作高风速使用。
        5) 判据取原始值（R24）：压损越限判定使用钳制前的 _fDpRawKpa。
        6) 物理域钳制：压损钳 0.0 ~ fDpMaxKpa；负荷率钳 0.0 ~ DL_PCT_HI；风速只判不钳（供观测）。
  量纲自证：zeta 无因次；rho*v^2/2 = (kg/m3)*(m2/s2) = kg/(m*s2) = Pa；
           除以 1000 得 kPa，故 fCycloneDpKpa 量纲为 [kPa]；
           fDpLoadPct = (kPa)/(kPa)*100 = 无因次百分数 [%]，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_PreheaterCyclonePressureCalc : BOOL
VAR_INPUT
    fInletVelMs      : REAL;   // 旋风筒入口风速 [m/s] / Cyclone inlet gas velocity [m/s]
    fResistCoef      : REAL;   // 综合阻力系数（无因次）[-] / Combined resistance coefficient [-]
    fGasDensityKgm3  : REAL;   // 工况气体密度 [kg/m3] / Gas density at working condition [kg/m3]
    fDpMaxKpa        : REAL;   // 设备许可压损上限 [kPa] / Permitted pressure drop [kPa]
    fVelBlockMs      : REAL;   // 堵塞风险风速下限 [m/s] / Blockage-risk velocity low limit [m/s]
END_VAR
VAR_OUTPUT
    fCycloneDpKpa    : REAL;   // 旋风筒压损 [kPa] / Cyclone pressure drop [kPa]
    fDpLoadPct       : REAL;   // 压损负荷率 [%] / Pressure drop load ratio [%]
    xDpOver          : BOOL;   // 压损超限标志 [bool] / Pressure drop overrun flag [bool]
    xBlockRisk       : BOOL;   // 堵塞风险标志（入口风速不足）[bool] / Blockage risk flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDynPa          : REAL;   // 动压 [Pa] / Dynamic pressure [Pa]
    _fDpRawKpa       : REAL;   // 钳制前的原始压损 [kPa] / Raw pressure drop before limiting [kPa]
    _fLoadRawPct     : REAL;   // 钳制前的原始负荷率 [%] / Raw load ratio before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_TWO           : REAL := 2.0;       // 动压式系数分母（v^2/2）[-] / Dynamic pressure divisor [-]
    DL_PA_PER_KPA    : REAL := 1000.0;    // 帕到千帕的折算 [Pa/kPa] / Pascals per kilopascal [Pa/kPa]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_PCT_HI        : REAL := 100.0;     // 负荷率物理上限 [%] / Load ratio upper bound [%]
    DL_VEL_HI_MS     : REAL := 40.0;      // 入口风速组态上限 [m/s] / Inlet velocity configuration upper bound [m/s]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fInletVelMs > -DL_BIG AND fInletVelMs < DL_BIG)
   OR NOT (fResistCoef > -DL_BIG AND fResistCoef < DL_BIG)
   OR NOT (fGasDensityKgm3 > -DL_BIG AND fGasDensityKgm3 < DL_BIG)
   OR NOT (fDpMaxKpa > -DL_BIG AND fDpMaxKpa < DL_BIG)
   OR NOT (fVelBlockMs > -DL_BIG AND fVelBlockMs < DL_BIG) THEN
    fCycloneDpKpa := 0.0;                   // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDpLoadPct := 0.0;                      // 负荷率强制 0.0 / Load ratio forced to zero
    xDpOver := FALSE;                       // 失效侧超限位保持假 / Overrun stays false
    xBlockRisk := FALSE;                    // 失效侧堵塞风险位保持假 / Blockage risk stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_PreheaterCyclonePressureCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与物理域闸（负荷率分母 + 密度/系数必须为正） —— *)
IF (fDpMaxKpa <= DL_EPS)                                          // 压损上限必须已组态
   OR (fGasDensityKgm3 <= DL_EPS)                                 // 气体密度必须为正
   OR (fResistCoef <= DL_EPS)                                     // 阻力系数必须为正
   OR (fInletVelMs < 0.0)                                         // 风速不得为负
   OR (fVelBlockMs < 0.0)                                         // 堵塞下限不得为负
   OR (fInletVelMs > DL_VEL_HI_MS) THEN                           // 风速超组态上限：测点或管径错误
    fCycloneDpKpa := 0.0;                   // 参数不可用即无压损 / No parameter, no pressure drop
    fDpLoadPct := 0.0;                      // 负荷率不可算 / Load ratio not computable
    xDpOver := FALSE;                       // 失效侧超限位保持假 / Overrun stays false
    xBlockRisk := FALSE;                    // 失效侧堵塞风险位保持假 / Blockage risk stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_PreheaterCyclonePressureCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fDynPa := fGasDensityKgm3 * fInletVelMs * fInletVelMs / DL_TWO;                  // 动压 [Pa]
_fDpRawKpa := fResistCoef * _fDynPa / DL_PA_PER_KPA;                              // 压损 [kPa]
_fLoadRawPct := _fDpRawKpa / fDpMaxKpa * DL_PCT;                                  // 负荷率 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xDpOver := (_fDpRawKpa > fDpMaxKpa);                                              // 压损越许可上限
xBlockRisk := (fInletVelMs < fVelBlockMs);                                        // 风速不足：旋流携带能力丧失
xValid := (fVelBlockMs < DL_VEL_HI_MS)                                            // 堵塞下限须低于组态上限（否则判据恒真）
          AND (_fLoadRawPct >= 0.0);                                              // 负荷率不得为负

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fCycloneDpKpa := LIMIT(0.0, _fDpRawKpa, fDpMaxKpa);                               // 压损钳 0..上限 [kPa]
fDpLoadPct := LIMIT(0.0, _fLoadRawPct, DL_PCT_HI);                                // 负荷率钳 0..100 [%]
FC_DL_PreheaterCyclonePressureCalc := xValid;                                     // 返回码：TRUE = 计算可信

END_FUNCTION
