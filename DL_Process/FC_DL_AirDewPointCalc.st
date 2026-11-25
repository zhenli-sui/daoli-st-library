(*
  Name: FC_DL_AirDewPointCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 压力露点 → 常压露点换算。物理口径：露点由「水蒸气分压」唯一确定，而分压等于
           摩尔分数乘总压。压缩空气从工作压力膨胀到大气压时摩尔分数不变、总压下降，
           故分压按 P_atm / P_abs 等比缩小，再由缩小后的分压反解露点即为常压露点。
           逐步为：Magnus 正解求工作压力下的饱和分压 → 按总压比缩小 → Magnus 反解温度。
        2) 含水量按理想气体状态方程在「压力露点温度」下计算：
           ρ[g/m3] = 1000 · p_v[Pa] / (R_v · T[K])，R_v = 461.5 J/(kg·K) 为水蒸气气体常数，
           合并常数后为 ρ = 2.1667 · p_v[Pa] / T[K]，表示工作压力下每立方米压缩空气的饱和含水量。
  边界条件：1) 非有限值闸：两路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) Magnus 分母零闸：DL_MAG_C + fPdpC 必须 ABS > DL_EPS，否则正解分母发散；
           反解分母 DL_MAG_B − L 同样必须 ABS > DL_EPS，否则常压露点发散。
        3) 开尔文偏移零闸：fPdpC + 273.15 > DL_EPS，否则含水量式温度分母为 0。
        4) 绝对值分母零闸：工作绝压 fWorkBar + DL_P_ATM_BAR 必须 ABS > DL_EPS（真空工况拦截）。
        5) 量程校验：压力露点 −90 ~ 100 °C（覆盖吸附式干燥机 −70 °C 到无油机高温工况），
           工作表压 0 ~ 100 bar；越域钳到边界算参考值但置无效。
        6) 饱和钳制：含水量钳 0 ~ 1000 g/m3，常压露点钳 −100 ~ 100 °C，防极端输入溢出。
  量纲自证：p_v = hPa × EXP([-]) = hPa，EXP 的自变量 (B·t)/(C+t) 中 (1/°C·°C) = 无因次；
           p_v_atm / p_v = (bar/bar) = 无因次，故分压换算不改变量纲；
           ADP 反解式 C·L/(B − L)：L = LN(hPa/hPa) 无因次，故结果为 °C；
           含水量 = 1000 [g/kg] × Pa / (J/(kg·K) × K) = g/m3，量纲闭合。
*)

FUNCTION FC_DL_AirDewPointCalc : BOOL
VAR_INPUT
    fPdpC         : REAL;   // 压力露点 [°C] / Pressure dew point [°C]
    fWorkBar      : REAL;   // 工作表压 [bar] / Working gauge pressure [bar]
END_VAR
VAR_OUTPUT
    fAdpC         : REAL;   // 常压露点 [°C] / Atmospheric dew point [°C]
    fMoistGm3     : REAL;   // 工作压力下饱和含水量 [g/m3] / Saturated moisture content [g/m3]
    xValid        : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fPdpClampC   : REAL;   // 钳制后的压力露点 [°C] / Clamped pressure dew point [°C]
    _fPAbsBar     : REAL;   // 工作绝对压力 [bar] / Working absolute pressure [bar]
    _fPvHpa       : REAL;   // 工作压力下饱和水蒸气分压 [hPa] / Saturation vapour pressure [hPa]
    _fPvAtmHpa    : REAL;   // 膨胀到常压后的水蒸气分压 [hPa] / Vapour pressure after expansion [hPa]
    _fL           : REAL;   // Magnus 反解中间量 LN(p_v/6.112) [-] / Magnus inverse intermediate [-]
    _fAdpRawC     : REAL;   // 未饱和的常压露点 [°C] / Raw atmospheric dew point [°C]
    _fMoistRaw    : REAL;   // 未饱和的含水量 [g/m3] / Raw moisture content [g/m3]
    _bDenOk       : BOOL;   // 三个分母合法性聚合 [bool] / Three denominator validity aggregate [bool]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_MAG_A      : REAL := 6.112;     // Magnus 系数 A（0 °C 饱和压）[hPa] / Magnus coefficient A [hPa]
    DL_MAG_B      : REAL := 17.62;     // Magnus 系数 B [-]/ Magnus coefficient B [-]
    DL_MAG_C      : REAL := 243.12;    // Magnus 系数 C [°C] / Magnus coefficient C [°C]
    DL_K0         : REAL := 273.15;    // 摄氏转开尔文偏移 [K] / Celsius to Kelvin offset [K]
    DL_P_ATM_BAR  : REAL := 1.01325;   // 标准大气压 [bar] / Standard atmospheric pressure [bar]
    DL_RHOV_K     : REAL := 2.1667;    // 水蒸气密度合并常数 [g·K/(m3·Pa)] / Vapour density constant
    DL_PDP_LO_C   : REAL := -90.0;     // 压力露点量程下限 [°C] / Pressure dew point range low [°C]
    DL_PDP_HI_C   : REAL := 100.0;     // 压力露点量程上限 [°C] / Pressure dew point range high [°C]
    DL_P_LO_BAR   : REAL := 0.0;       // 工作表压量程下限 [bar] / Gauge pressure range low [bar]
    DL_P_HI_BAR   : REAL := 100.0;     // 工作表压量程上限 [bar] / Gauge pressure range high [bar]
    DL_ADP_LO_C   : REAL := -100.0;    // 常压露点饱和下限 [°C] / Atmospheric dew point low [°C]
    DL_ADP_HI_C   : REAL := 100.0;     // 常压露点饱和上限 [°C] / Atmospheric dew point high [°C]
    DL_MOIST_MAX  : REAL := 1000.0;    // 含水量饱和上限 [g/m3] / Moisture saturation ceiling [g/m3]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不得进 EXP/LN） —— *)
IF NOT (fPdpC > -DL_BIG AND fPdpC < DL_BIG)
   OR NOT (fWorkBar > -DL_BIG AND fWorkBar < DL_BIG) THEN
    fAdpC := 0.0;                           // 输出强制 0.0 / Output forced to zero
    fMoistGm3 := 0.0;                       // 含水量强制 0.0 / Moisture forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirDewPointCalc := FALSE;         // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：Magnus 分母、绝对压分母、开尔文分母三处逐一验证） —— *)
_fPAbsBar := fWorkBar + DL_P_ATM_BAR;       // 工作绝压 [bar]
_bDenOk := (ABS(DL_MAG_C + fPdpC) > DL_EPS)                       // Magnus 正解分母
           AND (_fPAbsBar > DL_EPS)                               // 绝对压分母（真空拦截）
           AND ((fPdpC + DL_K0) > DL_EPS);                        // 含水量开尔文分母
IF NOT _bDenOk THEN
    fAdpC := 0.0;                           // 输出强制 0.0 / Output forced to zero
    fMoistGm3 := 0.0;                       // 含水量强制 0.0 / Moisture forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirDewPointCalc := FALSE;         // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：量程钳制（越域钳边界算参考值，段 6 判无效） —— *)
_fPdpClampC := LIMIT(DL_PDP_LO_C, fPdpC, DL_PDP_HI_C);            // 压力露点钳 −90..100 [°C]

(* —— 段 4：Magnus 正解求分压（R22 方向自核：露点升高→分压升高，指数为正） —— *)
_fPvHpa := DL_MAG_A * EXP(DL_MAG_B * _fPdpClampC / (DL_MAG_C + _fPdpClampC));   // [hPa]
_fPvAtmHpa := _fPvHpa * DL_P_ATM_BAR / _fPAbsBar;                                // 膨胀后分压 [hPa]

(* —— 段 5：Magnus 反解常压露点（分母 B − L 已闸，L >= B 时判无效） —— *)
_fL := LN(MAX(DL_EPS, _fPvAtmHpa / DL_MAG_A));                     // LN(p_v/A) [-]
IF ABS(DL_MAG_B - _fL) > DL_EPS THEN
    _fAdpRawC := DL_MAG_C * _fL / (DL_MAG_B - _fL);                // 常压露点 [°C]
ELSE
    _fAdpRawC := DL_ADP_LO_C;                                      // 分母发散：退下限哨兵值
END_IF

(* —— 段 6：含水量（工作压力、压力露点温度下的饱和含水量） —— *)
_fMoistRaw := DL_RHOV_K * (_fPvHpa * 100.0) / (_fPdpClampC + DL_K0);   // ρ [g/m3]

(* —— 段 7：有效位单点聚合（量程 + 反解分母合法） —— *)
xValid := (fPdpC >= DL_PDP_LO_C) AND (fPdpC <= DL_PDP_HI_C)        // 压力露点在量程内
          AND (fWorkBar >= DL_P_LO_BAR) AND (fWorkBar <= DL_P_HI_BAR)   // 工作压力在量程内
          AND (ABS(DL_MAG_B - _fL) > DL_EPS);                      // 反解分母不发散

(* —— 段 8：输出单点写盘（饱和钳制） —— *)
fAdpC := LIMIT(DL_ADP_LO_C, _fAdpRawC, DL_ADP_HI_C);               // 常压露点 [°C]
fMoistGm3 := LIMIT(0.0, _fMoistRaw, DL_MOIST_MAX);                 // 含水量 [g/m3]
FC_DL_AirDewPointCalc := xValid;                                   // 返回码：TRUE = 计算可信

END_FUNCTION
