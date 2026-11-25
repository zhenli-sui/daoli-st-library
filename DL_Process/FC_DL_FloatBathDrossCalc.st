(*
  Name: FC_DL_FloatBathDrossCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 锡渣生成速率按乘性模型估算：以基准工况（参考氧势 DL_O2_REF、参考锡液温度 DL_TIN_REF、
           单位面积）的基准速率 DL_KD0 为锚点，分别乘以氧势比与温度系数，再乘锡液面积：
             fDrossKgH = KD0 × 面积 × (氧势/参考氧势) × (1 + 温度系数 × (锡液温度 − 参考温度))
           氧势比与温度系数均为无因次，故乘法链不改变量纲；氧势越高、温度越高，锡渣越多。
        2) 清渣周期按「单次清渣可容纳的锡渣量 / 生成速率」反算：fCleanPeriodH = 容量 / 速率。
           该值是「必然溢出前必须清一次」的时限，用于排产与检修窗口安排。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：算清渣周期前必须 ABS(fDrossKgH) > DL_EPS（速率为 0 则周期无穷大，
           用哨兵值 DL_PERIOD_MAX 表示而不是除零）；氧势参考值 DL_O2_REF 为常量非零。
        3) 负值闸：锡液温度、氧势、面积任一为负判无效（不取绝对值掩盖反向）；
           温度为负同时会使命中温度系数下探到负值，故温度系数本身另有下限钳制。
        4) 量程校验：锡液温度 200 ~ 1200 °C、氧势 0 ~ 1000 ppm、锡液面积 0 ~ 500 m2，
           越域钳边界算参考值但置无效。
        5) 乘性因子钳制：氧势比钳 DL_O2_RATIO_MIN(0.01) ~ DL_O2_RATIO_MAX(100)，
           温度系数钳 DL_TF_MIN(0.05) ~ DL_BIG，防极端组态把速率放大到无意义量级。
        6) 饱和钳制：锡渣速率钳 0 ~ DL_DROSS_MAX(1000 kg/h)，清渣周期钳 0 ~ DL_PERIOD_MAX(100000 h)。
  量纲自证：KD0 = kg/(h·m2)；× m2 × 无因次比 × 无因次系数 = kg/h，量纲闭合；
           清渣周期 = kg / (kg/h) = h，容量与速率的 kg 对消，量纲为时间。
*)

FUNCTION FC_DL_FloatBathDrossCalc : BOOL
VAR_INPUT
    fTinTempC    : REAL;   // 锡液温度 [°C] / Molten tin temperature [°C]
    fO2Ppm       : REAL;   // 锡槽气氛氧势（氧含量）[ppm] / Tin bath atmosphere oxygen [ppm]
    fBathAreaM2  : REAL;   // 锡液有效面积 [m2] / Effective tin bath surface area [m2]
END_VAR
VAR_OUTPUT
    fDrossKgH    : REAL;   // 锡渣生成速率 [kg/h] / Dross generation rate [kg/h]
    fCleanPeriodH: REAL;   // 清渣周期 [h] / Dross cleaning period [h]
    xValid       : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fO2Ratio    : REAL;   // 氧势比（实测/参考）[-] / Oxygen ratio to reference [-]
    _fTempFactor : REAL;   // 温度乘性系数 [-] / Temperature multiplicative factor [-]
    _fDrossRaw   : REAL;   // 未饱和的锡渣速率 [kg/h] / Raw dross rate [kg/h]
    _fPeriodRaw  : REAL;   // 未饱和的清渣周期 [h] / Raw cleaning period [h]
    _fDrossClamp : REAL;   // 钳制后的锡渣速率 [kg/h] / Clamped dross rate [kg/h]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_KD0        : REAL := 0.02;      // 基准锡渣速率 [kg/(h·m2)] / Baseline dross rate [kg/(h·m2)]
    DL_O2_REF     : REAL := 5.0;       // 参考氧势 [ppm] / Reference oxygen potential [ppm]
    DL_O2_RATIO_MIN : REAL := 0.01;    // 氧势比饱和下限 [-] / Oxygen ratio saturation low [-]
    DL_O2_RATIO_MAX : REAL := 100.0;   // 氧势比饱和上限 [-] / Oxygen ratio saturation high [-]
    DL_TIN_REF    : REAL := 1000.0;    // 参考锡液温度 [°C] / Reference tin temperature [°C]
    DL_KT         : REAL := 0.002;     // 温度系数 [1/°C] / Temperature coefficient [1/°C]
    DL_TF_MIN     : REAL := 0.05;      // 温度系数饱和下限 [-] / Temperature factor low clamp [-]
    DL_DRESS_CAP_KG : REAL := 50.0;    // 单次清渣容纳量 [kg] / Dross capacity per cleaning [kg]
    DL_T_LO_C     : REAL := 200.0;     // 锡液温度量程下限 [°C] / Tin temperature range low [°C]
    DL_T_HI_C     : REAL := 1200.0;    // 锡液温度量程上限 [°C] / Tin temperature range high [°C]
    DL_O2_MAX     : REAL := 1000.0;    // 氧势量程上限 [ppm] / Oxygen range ceiling [ppm]
    DL_AREA_MAX   : REAL := 500.0;     // 锡液面积量程上限 [m2] / Bath area range ceiling [m2]
    DL_DROSS_MAX  : REAL := 1000.0;    // 锡渣速率饱和上限 [kg/h] / Dross rate saturation ceiling [kg/h]
    DL_PERIOD_MAX : REAL := 100000.0;  // 清渣周期饱和上限 [h] / Cleaning period saturation ceiling [h]
END_VAR

(* —— 段 1：非有限值闸（R19：三路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fTinTempC > -DL_BIG AND fTinTempC < DL_BIG)
   OR NOT (fO2Ppm > -DL_BIG AND fO2Ppm < DL_BIG)
   OR NOT (fBathAreaM2 > -DL_BIG AND fBathAreaM2 < DL_BIG) THEN
    fDrossKgH := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fCleanPeriodH := 0.0;                   // 周期强制 0.0 / Period forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_FloatBathDrossCalc := FALSE;      // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：负值闸（温度/氧势/面积均不可为负） —— *)
IF (fTinTempC < 0.0) OR (fO2Ppm < 0.0) OR (fBathAreaM2 < 0.0) THEN
    fDrossKgH := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fCleanPeriodH := 0.0;                   // 周期强制 0.0 / Period forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_FloatBathDrossCalc := FALSE;      // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：量程钳制（越域钳边界算参考值，段 6 判无效） —— *)
_fO2Ratio := LIMIT(DL_O2_RATIO_MIN, fO2Ppm / DL_O2_REF, DL_O2_RATIO_MAX);   // 氧势比 [-]
_fTempFactor := LIMIT(DL_TF_MIN,
                      1.0 + DL_KT * (LIMIT(DL_T_LO_C, fTinTempC, DL_T_HI_C) - DL_TIN_REF),
                      DL_BIG);                                    // 温度系数 [-]

(* —— 段 4：锡渣速率（R22 方向自核：面积与两个乘性因子全部在分子，无除法） —— *)
_fDrossRaw := DL_KD0 * LIMIT(0.0, fBathAreaM2, DL_AREA_MAX) * _fO2Ratio * _fTempFactor;   // [kg/h]

(* —— 段 5：清渣周期（分母零闸：速率过小则给哨兵上限，不除零） —— *)
_fDrossClamp := LIMIT(0.0, _fDrossRaw, DL_DROSS_MAX);            // 速率钳制 [kg/h]
IF _fDrossClamp > DL_EPS THEN
    _fPeriodRaw := DL_DRESS_CAP_KG / _fDrossClamp;               // 周期 = 容量 / 速率 [h]
ELSE
    _fPeriodRaw := DL_PERIOD_MAX;                                // 速率为 0：周期取哨兵上限
END_IF

(* —— 段 6：输出单点写盘（饱和钳制） —— *)
fDrossKgH := _fDrossClamp;                                       // 锡渣速率 [kg/h]
fCleanPeriodH := LIMIT(0.0, _fPeriodRaw, DL_PERIOD_MAX);         // 清渣周期 [h]

(* —— 段 7：有效位单点聚合（三路量程校验） —— *)
xValid := (fTinTempC >= DL_T_LO_C) AND (fTinTempC <= DL_T_HI_C)   // 温度在量程内
          AND (fO2Ppm <= DL_O2_MAX)                              // 氧势不越上限
          AND (fBathAreaM2 <= DL_AREA_MAX);                      // 面积不越上限
FC_DL_FloatBathDrossCalc := xValid;                              // 返回码：TRUE = 计算可信

END_FUNCTION
