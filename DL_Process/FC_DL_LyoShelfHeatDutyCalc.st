(*
  Name: FC_DL_LyoShelfHeatDutyCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 搁板加热功率按「升华吸热 / 加热效率」计算：
           P = rate * latent / eff / 3600，rate 为升华速率 [kg/h]、latent 为升华潜热 [kJ/kg]，
           3600 为 kJ/h 到 kW 的时基折算；eff 为搁板到制品的综合传热效率。
           该功率是一次干燥期搁板温度控制器的前馈给定。
        2) 功率负荷率 fDutyLoadPct = P / fHeaterMaxKw * 100，用于判断是否已触及加热器额定上限；
           超上限只置 xDutyOver 并钳到额定值，不把越限值当作可执行指令下发。
        3) 效率物理域校验：eff 必须落在 (0.0, 1.0] 内，大于 1 违反热力学第一定律，
           视为组态错误判无效（不钳制，钳制会把非法组态伪装成合法）。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（功率与负荷率强制 0.0），不得只置标志（R19）。
        2) 分母零闸：加热效率 fHeatEff 与加热器额定功率 fHeaterMaxKw 均须 > DL_EPS，
           否则功率式与负荷率式分母为零，直接判无效。
        3) 潜热域闸：升华潜热 fLatentKjKg 必须落在 (DL_LATENT_LO, DL_LATENT_HI) 内，
           越域说明工质不是水（冰的升华潜热约 2838 kJ/kg），判无效以免误算他物质。
        4) 判据取原始值（R24）：超上限判定使用钳制前的 _fDutyRawKw，不得先钳再判。
        5) 物理域钳制：功率钳 0.0 ~ fHeaterMaxKw；负荷率钳 0.0 ~ DL_PCT_HI。
        6) 纯函数无状态：不做功率限幅斜坡，斜坡由搁板温控 FB 承担。
  量纲自证：rate [kg/h] * latent [kJ/kg] = (kJ/h)；除以 3600 (s/h) 得 kJ/s = kW；
           再除以无因次效率 eff 仍为 kW，与 fHeaterMaxKw 同量纲；
           fDutyLoadPct = (kW)/(kW)*100 = 无因次百分数 [%]，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_LyoShelfHeatDutyCalc : BOOL
VAR_INPUT
    fRateKgh         : REAL;   // 升华速率 [kg/h] / Sublimation rate [kg/h]
    fLatentKjKg      : REAL;   // 升华潜热 [kJ/kg] / Latent heat of sublimation [kJ/kg]
    fHeatEff         : REAL;   // 搁板到制品综合传热效率（0~1 无因次）[-] / Shelf-to-product heat efficiency [-]
    fHeaterMaxKw     : REAL;   // 搁板加热器额定功率 [kW] / Rated shelf heater power [kW]
END_VAR
VAR_OUTPUT
    fDutyKw          : REAL;   // 所需加热功率 [kW] / Required heating duty [kW]
    fDutyLoadPct     : REAL;   // 加热功率负荷率 [%] / Heating duty load ratio [%]
    xDutyOver        : BOOL;   // 功率超额定标志 [bool] / Duty overrun flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDutyRawKw      : REAL;   // 钳制前的原始功率 [kW] / Raw duty before limiting [kW]
    _fLoadRawPct     : REAL;   // 钳制前的原始负荷率 [%] / Raw load ratio before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_SEC_PER_H     : REAL := 3600.0;    // 小时到秒的时基折算 [s/h] / Seconds per hour [s/h]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_PCT_HI        : REAL := 100.0;     // 负荷率物理上限 [%] / Load ratio upper bound [%]
    DL_EFF_HI        : REAL := 1.0;       // 传热效率物理上限（热力学第一定律）[-] / Efficiency upper bound [-]
    DL_LATENT_LO     : REAL := 2000.0;    // 冰升华潜热域下限 [kJ/kg] / Ice latent heat domain low [kJ/kg]
    DL_LATENT_HI     : REAL := 4000.0;    // 冰升华潜热域上限 [kJ/kg] / Ice latent heat domain high [kJ/kg]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fRateKgh > -DL_BIG AND fRateKgh < DL_BIG)
   OR NOT (fLatentKjKg > -DL_BIG AND fLatentKjKg < DL_BIG)
   OR NOT (fHeatEff > -DL_BIG AND fHeatEff < DL_BIG)
   OR NOT (fHeaterMaxKw > -DL_BIG AND fHeaterMaxKw < DL_BIG) THEN
    fDutyKw := 0.0;                         // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDutyLoadPct := 0.0;                    // 负荷率强制 0.0 / Load ratio forced to zero
    xDutyOver := FALSE;                     // 失效侧超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LyoShelfHeatDutyCalc := FALSE;    // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与域闸（效率、额定功率为分母；潜热须为水冰） —— *)
IF (fHeatEff <= DL_EPS)                                           // 效率不可为零
   OR (fHeatEff > DL_EFF_HI)                                      // 效率不得大于 1
   OR (fHeaterMaxKw <= DL_EPS)                                    // 额定功率必须已组态
   OR (fLatentKjKg <= DL_LATENT_LO)                               // 潜热不得低于冰升华域下限
   OR (fLatentKjKg >= DL_LATENT_HI)                               // 潜热不得高于冰升华域上限
   OR (fRateKgh < 0.0) THEN                                       // 速率不得为负（方向固定）
    fDutyKw := 0.0;                         // 参数不可用即无功率 / No parameter, no duty
    fDutyLoadPct := 0.0;                    // 负荷率不可算 / Load ratio not computable
    xDutyOver := FALSE;                     // 超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LyoShelfHeatDutyCalc := FALSE;    // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fDutyRawKw := fRateKgh * fLatentKjKg / fHeatEff / DL_SEC_PER_H;                   // 所需功率 [kW]
_fLoadRawPct := _fDutyRawKw / fHeaterMaxKw * DL_PCT;                               // 负荷率 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xDutyOver := (_fDutyRawKw > fHeaterMaxKw);                                        // 功率越额定上限
xValid := (_fDutyRawKw >= 0.0)                                                    // 功率不得为负
          AND (_fLoadRawPct >= 0.0);                                              // 负荷率不得为负

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fDutyKw := LIMIT(0.0, _fDutyRawKw, fHeaterMaxKw);                                 // 功率钳 0..额定 [kW]
fDutyLoadPct := LIMIT(0.0, _fLoadRawPct, DL_PCT_HI);                              // 负荷率钳 0..100 [%]
FC_DL_LyoShelfHeatDutyCalc := xValid;                                             // 返回码：TRUE = 计算可信

END_FUNCTION
