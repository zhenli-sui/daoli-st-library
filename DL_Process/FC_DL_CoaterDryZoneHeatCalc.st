(*
  Name: FC_DL_CoaterDryZoneHeatCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 烘箱溶剂蒸发所需热量按潜热折算：Q_evap[kW] = 溶剂质量流量[kg/h] × 蒸发潜热[kJ/kg]
           / 3600[s/h]，再按热效率归一化（除以效率比例），得到实际需投入的热功率。
           效率归一化的方向是「除以效率」而不是「乘效率」：效率越低，投入必须越多，
           这是本件最容易写反的一处（写成乘会把低效烘箱算成省能）。
        2) 循环风加热所需热量按显热折算：Q_air[kW] = 风量[m3/h] × 密度[kg/m3] × 定压比热[kJ/(kg·K)]
           × 设计温升[K] / 3600，其中设计温升 DL_DT_AIR 是烘箱新风加热的设计工况常数。
           两路热量互为补充：蒸发热是工艺负荷，风加热是设备热惯性负荷，合计为烘箱热负荷。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：热效率比例必须 ABS > DL_EPS，否则「除以效率」发散（效率为 0 表示无热输入，
           物理上无法蒸发任何溶剂）；3600 s/h 为常量，无零风险。
        3) 效率窄闸：必须落在 DL_EFF_MIN(1 %) ~ 100 %，越域钳边界算参考值但置无效；
           超过 100 % 违反热力学第一定律，属组态错误。
        4) 负值闸：溶剂流量、潜热、风量任一为负判无效（不取绝对值掩盖反向）。
        5) 零值语义：溶剂流量为 0（未涂布）属合法工况，蒸发热为 0，不判无效；
           潜热为 0 判无效（潜热是物料属性常数，为 0 表示未组态）。
        6) 饱和钳制：两路热量均钳 0 ~ DL_Q_MAX(10000 kW)，防组态越界溢出。
  量纲自证：Q_evap = (kg/h) × (kJ/kg) / (s/h) = kJ/s = kW，除效率 [-] 后仍为 kW；
           Q_air = (m3/h) × (kg/m3) × (kJ/(kg·K)) × K / (s/h) = kJ/s = kW；
           两输出同为 kW，可相加；本件未出现 kW/kW 无因次量与温度相加的混算。
*)

FUNCTION FC_DL_CoaterDryZoneHeatCalc : BOOL
VAR_INPUT
    fSolventKgH    : REAL;   // 溶剂蒸发质量流量 [kg/h] / Solvent evaporation mass flow [kg/h]
    fLatentKJkg    : REAL;   // 溶剂蒸发潜热 [kJ/kg] / Solvent latent heat of vaporization [kJ/kg]
    fEfficiencyPct : REAL;   // 烘箱热效率 [%] / Oven thermal efficiency [%]
    fAirFlowM3h    : REAL;   // 循环/新风体积流量 [m3/h] / Air volumetric flow [m3/h]
END_VAR
VAR_OUTPUT
    fHeatKW        : REAL;   // 溶剂蒸发所需热功率（已效率归一）[kW] / Evaporation heat demand [kW]
    fAirHeatKW     : REAL;   // 风加热所需热功率 [kW] / Air heating heat demand [kW]
    fTotalKW       : REAL;   // 烘箱总热负荷 [kW] / Total oven heat load [kW]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fEffRatio     : REAL;   // 归一化热效率 [-] / Normalized thermal efficiency [-]
    _fEvapRawKW    : REAL;   // 未效率归一的蒸发热功率 [kW] / Raw evaporation heat [kW]
    _fHeatRawKW    : REAL;   // 效率归一后的蒸发热功率 [kW] / Efficiency-normalized heat [kW]
    _fAirRawKW     : REAL;   // 未饱和的风加热功率 [kW] / Raw air heating heat [kW]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT         : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_S_PER_H     : REAL := 3600.0;    // h → s 换算因子 [s/h] / Hour to second factor [s/h]
    DL_RHO_AIR     : REAL := 1.20;      // 空气密度 [kg/m3] / Air density [kg/m3]
    DL_CP_AIR      : REAL := 1.005;     // 空气定压比热 [kJ/(kg·K)] / Air specific heat [kJ/(kg·K)]
    DL_DT_AIR      : REAL := 100.0;     // 烘箱设计温升 [K] / Oven design temperature rise [K]
    DL_EFF_MIN     : REAL := 1.0;       // 热效率下限 [%] / Thermal efficiency lower bound [%]
    DL_Q_MAX       : REAL := 10000.0;   // 热功率饱和上限 [kW] / Heat power saturation ceiling [kW]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fSolventKgH > -DL_BIG AND fSolventKgH < DL_BIG)
   OR NOT (fLatentKJkg > -DL_BIG AND fLatentKJkg < DL_BIG)
   OR NOT (fEfficiencyPct > -DL_BIG AND fEfficiencyPct < DL_BIG)
   OR NOT (fAirFlowM3h > -DL_BIG AND fAirFlowM3h < DL_BIG) THEN
    fHeatKW := 0.0;                         // 输出强制 0.0 / Output forced to zero
    fAirHeatKW := 0.0;                      // 风加热强制 0.0 / Air heat forced to zero
    fTotalKW := 0.0;                        // 总负荷强制 0.0 / Total load forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_CoaterDryZoneHeatCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：热效率是除数，为 0 则需热量发散） —— *)
IF ABS(fEfficiencyPct / DL_PCT) <= DL_EPS THEN
    fHeatKW := 0.0;                         // 输出强制 0.0 / Output forced to zero
    fAirHeatKW := 0.0;                      // 风加热强制 0.0 / Air heat forced to zero
    fTotalKW := 0.0;                        // 总负荷强制 0.0 / Total load forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterDryZoneHeatCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（流量与潜热均不可为负） —— *)
IF (fSolventKgH < 0.0) OR (fLatentKJkg < 0.0) OR (fAirFlowM3h < 0.0) THEN
    fHeatKW := 0.0;                         // 输出强制 0.0 / Output forced to zero
    fAirHeatKW := 0.0;                      // 风加热强制 0.0 / Air heat forced to zero
    fTotalKW := 0.0;                        // 总负荷强制 0.0 / Total load forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterDryZoneHeatCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：蒸发热功率（R22 方向自核：效率在分母，效率越低投入越大） —— *)
_fEvapRawKW := fSolventKgH * fLatentKJkg / DL_S_PER_H;            // 理论蒸发热 [kW]
_fEffRatio := LIMIT(DL_EFF_MIN, fEfficiencyPct, DL_PCT) / DL_PCT; // 效率归一，并钳到 1~100 %
_fHeatRawKW := _fEvapRawKW / _fEffRatio;                          // 效率归一后热功率 [kW]

(* —— 段 5：风加热功率（显热式：风量 × 密度 × 比热 × 温升，除 3600 得 kW） —— *)
_fAirRawKW := fAirFlowM3h * DL_RHO_AIR * DL_CP_AIR * DL_DT_AIR / DL_S_PER_H;   // [kW]

(* —— 段 6：输出单点写盘（饱和钳制后合计，保证合计值取自同一组出口值） —— *)
fHeatKW := LIMIT(0.0, _fHeatRawKW, DL_Q_MAX);                     // 蒸发热需求 [kW]
fAirHeatKW := LIMIT(0.0, _fAirRawKW, DL_Q_MAX);                   // 风加热需求 [kW]
fTotalKW := LIMIT(0.0, fHeatKW + fAirHeatKW, DL_Q_MAX);           // 总热负荷 [kW]

(* —— 段 7：有效位单点聚合（效率窄闸 + 潜热已组态 + 风量非负） —— *)
xValid := (fEfficiencyPct >= DL_EFF_MIN) AND (fEfficiencyPct <= DL_PCT)   // 效率在 1..100 %
          AND (fLatentKJkg > DL_EPS)                                      // 潜热已组态
          AND (fSolventKgH >= 0.0)                                        // 溶剂流量非负
          AND (fAirFlowM3h >= 0.0);                                       // 风量非负
FC_DL_CoaterDryZoneHeatCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
