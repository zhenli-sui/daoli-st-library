(*
  Name: FC_DL_OverflowDyeFlowCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 溢流循环流量按喷嘴孔口出流式计算：
           Q = n * Cd * A * SQRT(2 * dP / rho)，
           其中 n 为喷嘴数、Cd 为流量系数（0.6 ~ 0.95）、A 为单孔面积、dP 为泵压折绝对压差 [Pa]、
           rho 为染液密度 [kg/m3]；结果由 m3/s 折算为 m3/h（× 3600）。
           单孔面积由孔径换算：A = pi/4 * d^2，d 以 mm 给出，故需乘 1E-6 折算为 m2。
        2) 派生量：等效喷嘴出口流速 fVelMs 与总开孔面积 fNozzleAreaMm2，
           后者用于判断喷嘴堵塞（面积应与设计值一致，实际流量偏低即堵塞）。
        3) 流量上限保护：结果超过 fFlowMaxM3h 只置 xFlowOver 并钳到上限，
           识别「泵压过高导致超流量」的工况（超流量会拉断布卷并损伤织物组织）。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（流量与流速强制 0.0），不得只置标志（R19）。
        2) 孔径零闸：fNozzleDiaMm 必须 > DL_EPS（面积为孔径平方的乘子），
           为零会把「未组态孔径」伪装成「零流量」，判无效而非输出 0。
        3) 密度零闸：fDensityKgm3 必须 > DL_EPS（压差式分母），否则根号内发散。
        4) 系数与数量闸：fDischCoef 必须落在 (0.0, 1.0] 内（大于 1 违反能量守恒）；
           喷嘴数 nNozzle 必须 >= 1（为零即无通路）。
        5) 压差非负闸：fPumpPressKpa 不得为负（负压差会使根号内为负、结果为 NaN），判无效。
        6) 判据取原始值（R24）：超上限判定使用钳制前的 _fFlowRawM3h，钳制只作用于输出。
  量纲自证：A = (mm)^2 * 1E-6 = m2；2*dP/rho = (Pa)/(kg/m3) = (N/m2)*(m3/kg) = m2/s2，
           开方得 m/s；A * v = m2 * m/s = m3/s；再乘 3600 得 m3/h，量纲链闭合。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_OverflowDyeFlowCalc : BOOL
VAR_INPUT
    nNozzle          : INT;    // 溢流喷嘴数量 [count] / Number of overflow nozzles [count]
    fNozzleDiaMm     : REAL;   // 单喷嘴孔径 [mm] / Single nozzle bore diameter [mm]
    fPumpPressKpa    : REAL;   // 循环泵出口压力（表压）[kPa] / Circulation pump discharge pressure [kPa]
    fDensityKgm3     : REAL;   // 染液密度 [kg/m3] / Dye liquor density [kg/m3]
    fDischCoef       : REAL;   // 喷嘴流量系数（0~1 无因次）[-] / Nozzle discharge coefficient [-]
    fFlowMaxM3h      : REAL;   // 允许循环流量上限 [m3/h] / Permitted circulation flow upper limit [m3/h]
END_VAR
VAR_OUTPUT
    fFlowM3h         : REAL;   // 溢流循环总流量 [m3/h] / Total overflow circulation flow [m3/h]
    fVelMs           : REAL;   // 喷嘴等效出口流速 [m/s] / Equivalent nozzle exit velocity [m/s]
    fNozzleAreaMm2   : REAL;   // 喷嘴总开孔面积 [mm2] / Total nozzle open area [mm2]
    xFlowOver        : BOOL;   // 流量超上限标志 [bool] / Flow overrun flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fAreaOneM2      : REAL;   // 单孔面积 [m2] / Single nozzle area [m2]
    _fAreaTotalM2    : REAL;   // 总开孔面积 [m2] / Total open area [m2]
    _fPressPa        : REAL;   // 泵压折算为帕 [Pa] / Pump pressure converted to pascals [Pa]
    _fVelRawMs       : REAL;   // 钳制前的出口流速 [m/s] / Raw exit velocity [m/s]
    _fFlowRawM3s     : REAL;   // 未折算的流量 [m3/s] / Flow before hourly conversion [m3/s]
    _fFlowRawM3h     : REAL;   // 钳制前的原始流量 [m3/h] / Raw flow before limiting [m3/h]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PI            : REAL := 3.14159265; // 圆周率 [-] / Pi [-]
    DL_QUARTER       : REAL := 0.25;      // 圆面积折算系数（pi/4 的 1/4 部分）[-] / Circle area factor [-]
    DL_MM2_PER_M2    : REAL := 1.0E6;     // 平方米到平方毫米的折算 [mm2/m2] / Square mm per square metre [mm2/m2]
    DL_PA_PER_KPA    : REAL := 1000.0;    // 帕到千帕的折算 [Pa/kPa] / Pascals per kilopascal [Pa/kPa]
    DL_TWO           : REAL := 2.0;       // 孔口出流式的系数 2 [-] / Orifice equation factor 2 [-]
    DL_SEC_PER_H     : REAL := 3600.0;    // 小时到秒的时基折算 [s/h] / Seconds per hour [s/h]
    DL_COEF_HI       : REAL := 1.0;       // 流量系数物理上限 [-]/ Discharge coefficient upper bound [-]
    DL_FLOW_HI_M3H   : REAL := 10000.0;   // 流量量级闸上限 [m3/h] / Flow magnitude upper bound [m3/h]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fNozzleDiaMm > -DL_BIG AND fNozzleDiaMm < DL_BIG)
   OR NOT (fPumpPressKpa > -DL_BIG AND fPumpPressKpa < DL_BIG)
   OR NOT (fDensityKgm3 > -DL_BIG AND fDensityKgm3 < DL_BIG)
   OR NOT (fDischCoef > -DL_BIG AND fDischCoef < DL_BIG)
   OR NOT (fFlowMaxM3h > -DL_BIG AND fFlowMaxM3h < DL_BIG) THEN
    fFlowM3h := 0.0;                        // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fVelMs := 0.0;                          // 流速强制 0.0 / Velocity forced to zero
    fNozzleAreaMm2 := 0.0;                  // 面积强制 0.0 / Area forced to zero
    xFlowOver := FALSE;                     // 失效侧超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_OverflowDyeFlowCalc := FALSE;     // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：孔径/密度零闸与系数域闸（面积为孔径平方乘子，密度为根号分母） —— *)
IF (fNozzleDiaMm <= DL_EPS)                                       // 孔径不可为零
   OR (fDensityKgm3 <= DL_EPS)                                    // 密度不可为零
   OR (fDischCoef <= 0.0)                                         // 流量系数必须为正
   OR (fDischCoef > DL_COEF_HI)                                   // 流量系数不得大于 1
   OR (nNozzle < 1)                                               // 喷嘴数至少一个
   OR (fPumpPressKpa < 0.0)                                       // 压差不得为负（根号内不可为负）
   OR (fFlowMaxM3h <= DL_EPS) THEN                                // 流量上限必须已组态
    fFlowM3h := 0.0;                        // 参数不可用即无流量 / No parameter, no flow
    fVelMs := 0.0;                          // 流速不可算 / Velocity not computable
    fNozzleAreaMm2 := 0.0;                  // 面积不可算 / Area not computable
    xFlowOver := FALSE;                     // 超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_OverflowDyeFlowCalc := FALSE;     // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fAreaOneM2 := DL_PI * DL_QUARTER * fNozzleDiaMm * fNozzleDiaMm / DL_MM2_PER_M2;   // 单孔面积 [m2]
_fAreaTotalM2 := _fAreaOneM2 * INT_TO_REAL(nNozzle);                              // 总开孔面积 [m2]
_fPressPa := fPumpPressKpa * DL_PA_PER_KPA;                                       // 泵压 [Pa]
_fVelRawMs := SQRT(DL_TWO * _fPressPa / fDensityKgm3);                            // 出口流速 [m/s]
_fFlowRawM3s := fDischCoef * _fAreaTotalM2 * _fVelRawMs;                          // 流量 [m3/s]
_fFlowRawM3h := _fFlowRawM3s * DL_SEC_PER_H;                                      // 流量 [m3/h]
fNozzleAreaMm2 := _fAreaTotalM2 * DL_MM2_PER_M2;                                  // 总开孔面积 [mm2]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xFlowOver := (_fFlowRawM3h > fFlowMaxM3h);                                        // 流量越上限
xValid := (_fVelRawMs >= 0.0)                                                     // 流速不得为负（开方恒非负）
          AND (_fFlowRawM3h >= 0.0)                                               // 流量不得为负
          AND (_fFlowRawM3h <= DL_FLOW_HI_M3H)                                    // 不超量级闸上限
          AND (fFlowMaxM3h <= DL_FLOW_HI_M3H);                                    // 上限须在量级闸内

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fFlowM3h := LIMIT(0.0, _fFlowRawM3h, fFlowMaxM3h);                                // 流量钳 0..工艺上限 [m3/h]
fVelMs := LIMIT(0.0, _fVelRawMs, DL_FLOW_HI_M3H);                                 // 流速钳物理域 [m/s]
FC_DL_OverflowDyeFlowCalc := xValid;                                              // 返回码：TRUE = 计算可信

END_FUNCTION
