(*
  Name: FC_DL_AirCompFreeAirDeliveryCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 储气罐压降法测自由排气量 FAD：空压机向储气罐充气（或罐内气体对外供气）期间，
           罐内绝对压降对应的「常压自由空气容积」= 罐容积 × 压降 / 大气压，
           再按测量时长折算到每分钟即得 FAD：fFadM3min = V_tank · ΔP / P_atm · 60 / t。
           该法假设过程等温（罐体与外界充分换热），适用于离线产能测试。
        2) 标准状态折算：把实测工况（fTempC、fAtmBar）下的自由空气折算到 0 °C、1013.25 mbar
           的标准状态，用于跨季节、跨海拔的产能对比：fFadNorm = fFad · (273.15/(273.15+t)) · (P_atm/P_std)。
           温度项与压力项均为无因次比值，且方向相反（温度升高使标准容积变小、压力升高使其变大）。
  边界条件：1) 非有限值闸：五路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fTimeS) > DL_EPS（测量时长为 0 则流速发散）与
           ABS(fAtmBar) > DL_EPS（大气压为 0 则折算无意义）都必须通过，否则判无效。
        3) 开尔文偏移零闸：fTempC 必须 > DL_K0_NEG（−273.15 °C）之上，否则 273.15 + t 为 0 或负，
           标准状态折算的温度分母发散；同时对温度做 −50 ~ 80 °C 的工况量程校验，越域判无效。
        4) 负值与零压降：罐容积为负、压降为负（压力反向上升）均判无效；
           压降为 0 属合法但无信息（FAD = 0），不判无效，仅输出 0。
        5) 饱和钳制：FAD 与标准 FAD 结果均钳到 0 ~ DL_FAD_MAX(10000 m3/min)，
           防测量时长极短导致折算值溢出。
  量纲自证：V·ΔP/P_atm = m3 × bar / bar = m3（自由空气容积，bar 消去）；
           再乘 60 s/min 除 t[s] → m3/min，量纲闭合；
           标准折算两个因子 (K/K) 与 (mbar/mbar) 均为无因次，不改变量纲。
*)

FUNCTION FC_DL_AirCompFreeAirDeliveryCalc : BOOL
VAR_INPUT
    fTankM3       : REAL;   // 储气罐有效容积 [m3] / Effective receiver volume [m3]
    fDropBar      : REAL;   // 测量期间罐内压降 [bar] / Pressure drop during test [bar]
    fTimeS        : REAL;   // 测量时长 [s] / Measurement duration [s]
    fAtmBar       : REAL;   // 当地大气压 [bar] / Local atmospheric pressure [bar]
    fTempC        : REAL;   // 环境温度 [°C] / Ambient temperature [°C]
END_VAR
VAR_OUTPUT
    fFadM3min     : REAL;   // 工况自由排气量 [m3/min] / Free air delivery at site conditions [m3/min]
    fFadNormM3min : REAL;   // 标准状态自由排气量 [m3/min] / Free air delivery at standard conditions
    xValid        : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fFreeVolumeM3: REAL;   // 压降对应的常压自由空气容积 [m3] / Free air volume from pressure drop [m3]
    _fFadRawM3min : REAL;   // 未饱和的工况 FAD [m3/min] / Raw site FAD [m3/min]
    _fTempFactor  : REAL;   // 标准状态温度折算因子 [-] / Standard-state temperature factor [-]
    _fPressFactor : REAL;   // 标准状态压力折算因子 [-] / Standard-state pressure factor [-]
    _fNormRawM3min: REAL;   // 未饱和的标准状态 FAD [m3/min] / Raw standard FAD [m3/min]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_K0         : REAL := 273.15;    // 摄氏转开尔文偏移 [K] / Celsius to Kelvin offset [K]
    DL_S_PER_MIN  : REAL := 60.0;      // min → s 换算因子 [s/min] / Minute to second factor [s/min]
    DL_P_STD_MBAR : REAL := 1013.25;   // 标准大气压 [mbar] / Standard atmospheric pressure [mbar]
    DL_T_LO_C     : REAL := -50.0;     // 环境温度量程下限 [°C] / Ambient temperature range low [°C]
    DL_T_HI_C     : REAL := 80.0;      // 环境温度量程上限 [°C] / Ambient temperature range high [°C]
    DL_FAD_MAX    : REAL := 10000.0;   // FAD 饱和钳制上限 [m3/min] / FAD saturation ceiling [m3/min]
END_VAR

(* —— 段 1：非有限值闸（R19：五路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fTankM3 > -DL_BIG AND fTankM3 < DL_BIG)
   OR NOT (fDropBar > -DL_BIG AND fDropBar < DL_BIG)
   OR NOT (fTimeS > -DL_BIG AND fTimeS < DL_BIG)
   OR NOT (fAtmBar > -DL_BIG AND fAtmBar < DL_BIG)
   OR NOT (fTempC > -DL_BIG AND fTempC < DL_BIG) THEN
    fFadM3min := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fFadNormM3min := 0.0;                   // 标准 FAD 强制 0.0 / Standard FAD forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirCompFreeAirDeliveryCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：测量时长与大气压两个分母都要闸） —— *)
IF (ABS(fTimeS) <= DL_EPS) OR (ABS(fAtmBar) <= DL_EPS) THEN
    fFadM3min := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fFadNormM3min := 0.0;                   // 标准 FAD 强制 0.0 / Standard FAD forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirCompFreeAirDeliveryCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：开尔文偏移零闸与负值闸（温度分母 / 负容积 / 负压降 / 负时长） —— *)
IF ((fTempC + DL_K0) <= DL_EPS)
   OR (fTankM3 < 0.0) OR (fDropBar < 0.0) OR (fTimeS < 0.0) OR (fAtmBar < 0.0) THEN
    fFadM3min := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fFadNormM3min := 0.0;                   // 标准 FAD 强制 0.0 / Standard FAD forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirCompFreeAirDeliveryCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：压降法主算式（R22 方向自核：压降越大自由空气越多，除的是大气压不是工况压力） —— *)
_fFreeVolumeM3 := fTankM3 * fDropBar / fAtmBar;                        // 常压自由空气容积 [m3]
_fFadRawM3min := _fFreeVolumeM3 * DL_S_PER_MIN / fTimeS;               // 折算到每分钟 [m3/min]

(* —— 段 5：标准状态折算（温度项与压力项方向相反，均为无因次比值） —— *)
_fTempFactor := DL_K0 / (DL_K0 + fTempC);                              // 温度折算 [-]
_fPressFactor := fAtmBar / (DL_P_STD_MBAR / 1000.0);                   // 压力折算（mbar → bar）[-]
_fNormRawM3min := _fFadRawM3min * _fTempFactor * _fPressFactor;        // 标准状态 FAD [m3/min]

(* —— 段 6：有效位单点聚合（温度工况量程校验） —— *)
xValid := (fTempC >= DL_T_LO_C) AND (fTempC <= DL_T_HI_C)              // 温度在工况量程内
          AND (fTankM3 >= 0.0) AND (fDropBar >= 0.0)                   // 容积与压降非负
          AND (fTimeS > DL_EPS) AND (fAtmBar > DL_EPS);                // 两个分母均为正

(* —— 段 7：输出单点写盘（饱和钳制，防极短测量时长溢出） —— *)
fFadM3min := LIMIT(0.0, _fFadRawM3min, DL_FAD_MAX);                    // 工况 FAD [m3/min]
fFadNormM3min := LIMIT(0.0, _fNormRawM3min, DL_FAD_MAX);               // 标准 FAD [m3/min]
FC_DL_AirCompFreeAirDeliveryCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
