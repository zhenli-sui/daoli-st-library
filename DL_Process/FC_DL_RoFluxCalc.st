(*
  Name: FC_DL_RoFluxCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 膜通量按「单位时间单位膜面积的产水容积」计算，容积流量由 m3/h 换算为 L/h 后除以面积，
           得 LMH（L/(m2·h)）：fFluxLMH = fPermeateFlowM3h * 1000 / fMembraneAreaM2 * 1，
           其中 1000 为 m3 → L 的换算因子，除的是有效膜面积而非单支膜面积。
        2) 温度校正通量按 25 °C 基准折算：TCF = EXP(LN(DL_TCF_BASE) * (DL_T_REF_C - fTempC))，
           即每偏离基准温度 1 °C 通量按 DL_TCF_BASE 倍率变化；fFluxTempCorrLMH = fFluxLMH * TCF。
           该式用于把不同水温下的通量拉到同一基准比较，禁止直接用实测通量做趋势判定。
  边界条件：1) 面积零闸：ABS(fMembraneAreaM2) > DL_EPS 才允许除法，否则清零输出并置无效。
        2) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即拦断实值通路（两个 REAL 输出强制 0.0），不许把 NaN 透传（R19）。
        3) 温度量程窄闸：fTempC 须在 DL_T_LO_C..DL_T_HI_C（0 ~ 80 °C）内，越域判无效，
           因为温度校正式的适用域只在膜系统实际水温区间；越域仍按边界值算出一个数供参考。
        4) 通量不得为负：产水流量为负判传感器反向，置无效。
        5) 校正通量做饱和硬限：TCF 结果钳到 0.05 ~ 20.0（对应约 0.5 ~ 25 °C 的极端偏离），
           防止极端温度把校正值放大到无物理意义的量级。
  量纲自证：fFluxLMH = (m3/h) * 1000 (L/m3) / (m2) = L/(m2·h) = LMH，量纲闭合；
           TCF = [-]（无因次倍率），fFluxTempCorrLMH = (L/(m2·h)) * [-] = L/(m2·h)，同量纲。
*)

FUNCTION FC_DL_RoFluxCalc : BOOL
VAR_INPUT
    fPermeateFlowM3h : REAL;   // 产水体积流量 [m3/h] / Permeate volumetric flow [m3/h]
    fMembraneAreaM2  : REAL;   // 有效膜面积 [m2] / Effective membrane area [m2]
    fTempC           : REAL;   // 给水温度 [°C] / Feed water temperature [°C]
END_VAR
VAR_OUTPUT
    fFluxLMH         : REAL;   // 实测膜通量 [L/(m2·h)] / Measured membrane flux [LMH]
    fFluxTempCorrLMH : REAL;   // 25 °C 基准校正通量 [L/(m2·h)] / Temperature-corrected flux [LMH]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fTcf            : REAL;   // 温度校正因子 [-] / Temperature correction factor [-]
    _fTClampedC      : REAL;   // 钳制到适用域内的温度 [°C] / Temperature clamped to valid range [°C]
    _fFluxRawLMH     : REAL;   // 未钳制的原始通量 [L/(m2·h)] / Raw flux before limiting [LMH]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_L_PER_M3      : REAL := 1000.0;    // m3 → L 换算因子 [L/m3] / Cubic metre to litre factor [L/m3]
    DL_T_REF_C       : REAL := 25.0;      // 通量基准温度 [°C] / Flux reference temperature [°C]
    DL_TCF_BASE      : REAL := 1.03;      // 每 °C 通量变化倍率 [-] / Flux change ratio per degC [-]
    DL_T_LO_C        : REAL := 0.0;       // 温度适用域下限 [°C] / Temperature validity low [°C]
    DL_T_HI_C        : REAL := 80.0;      // 温度适用域上限 [°C] / Temperature validity high [°C]
    DL_TCF_MIN       : REAL := 0.05;      // 校正因子饱和下限 [-] / TCF saturation low [-]
    DL_TCF_MAX       : REAL := 20.0;      // 校正因子饱和上限 [-] / TCF saturation high [-]
END_VAR

(* —— 段 1：非有限值闸（R19：同时拦 NaN 与 Inf，并闸断两个 REAL 输出通路） —— *)
IF NOT (fPermeateFlowM3h > -DL_BIG AND fPermeateFlowM3h < DL_BIG)
   OR NOT (fMembraneAreaM2 > -DL_BIG AND fMembraneAreaM2 < DL_BIG)
   OR NOT (fTempC > -DL_BIG AND fTempC < DL_BIG) THEN
    fFluxLMH := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fFluxTempCorrLMH := 0.0;                // 校正通量强制 0.0 / Corrected flux forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoFluxCalc := FALSE;              // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：面积零闸（R4：分母先过 ABS 闸） —— *)
IF ABS(fMembraneAreaM2) <= DL_EPS THEN
    fFluxLMH := 0.0;                        // 无面积即无通量 / No area means no flux
    fFluxTempCorrLMH := 0.0;                // 校正通量同样清零 / Corrected flux cleared
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoFluxCalc := FALSE;              // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：实测通量（R22 方向自核：分子为产水容积，分母为膜面积，不取倒数） —— *)
_fFluxRawLMH := fPermeateFlowM3h * DL_L_PER_M3 / fMembraneAreaM2;   // [L/(m2·h)]

(* —— 段 4：温度校正因子（EXPT 的跨平台安全写法：EXP(LN(base) * 指数)） —— *)
_fTClampedC := LIMIT(DL_T_LO_C, fTempC, DL_T_HI_C);                 // 钳到适用域 [°C]
_fTcf := EXP(LN(DL_TCF_BASE) * (DL_T_REF_C - _fTClampedC));         // 25 °C 基准折算 [-]
_fTcf := LIMIT(DL_TCF_MIN, _fTcf, DL_TCF_MAX);                      // 因子饱和硬限 [-]

(* —— 段 5：有效位单点聚合（物理域 + 温度量程 + 非负） —— *)
xValid := (fPermeateFlowM3h >= 0.0)                                 // 产水不得为负
          AND (fMembraneAreaM2 > DL_EPS)                            // 面积必须为正
          AND (fTempC >= DL_T_LO_C)                                 // 温度不越下限
          AND (fTempC <= DL_T_HI_C);                                // 温度不越上限

(* —— 段 6：输出单点写盘（饱和后再写，禁同拍二次赋值） —— *)
fFluxLMH := MAX(0.0, _fFluxRawLMH);                                 // 通量钳 >= 0 [L/(m2·h)]
fFluxTempCorrLMH := MAX(0.0, _fFluxRawLMH * _fTcf);                 // 校正通量钳 >= 0 [L/(m2·h)]
FC_DL_RoFluxCalc := xValid;                                         // 返回码：TRUE = 计算可信

END_FUNCTION
