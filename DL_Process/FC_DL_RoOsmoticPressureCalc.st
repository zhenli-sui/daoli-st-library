(*
  Name: FC_DL_RoOsmoticPressureCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 按 van't Hoff 简化式计算给水渗透压：π = i · C · R · T，其中溶质按 NaCl 双离子
           （i = 2）、摩尔质量折算并入常数项，得到工程式 π[Pa] = DL_VANT_HOFF · T[K] · TDS[mg/L]，
           再除 1.0E5 转 bar；温度以开尔文参与，故必须先做 °C → K 的偏移。
        2) TDS 先做量程钳制（0 ~ DL_TDS_MAX mg/L）再进算式，超域值不让其把渗透压推到无物理意义量级；
           钳制动作本身不置无效，只有负值或非有限才判无效。
  边界条件：1) 非有限值闸：两路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即拦断实值通路（fOsmoticBar 强制 0.0）并置 xValid=FALSE（R19）。
        2) TDS 负值判无效（浓度不可能为负，属变送器故障），不取绝对值掩盖。
        3) TDS 上限饱和钳制 DL_TDS_MAX = 60000 mg/L（覆盖海水级高盐工况），超限钳到上限并判无效；
           下限钳 0.0（纯水渗透压为 0，属合法工况，不判无效）。
        4) 温度量程窄闸 0 ~ 90 °C：水温越域钳到边界算参考值并置无效，因为开尔文偏移在负温度附近
           会使简化式显著偏离实测渗透压。
        5) 无回差环节：纯函数无状态，不做迟滞。
  量纲自证：DL_VANT_HOFF = 0.28451 Pa·L/(mg·K)，故 Pa·L/(mg·K) × K × mg/L = Pa，量纲闭合；
           fOsmoticBar = Pa / 1.0E5 (Pa/bar) = bar。
*)

FUNCTION FC_DL_RoOsmoticPressureCalc : BOOL
VAR_INPUT
    fTdsMgL      : REAL;   // 给水总溶解固体 [mg/L] / Feed total dissolved solids [mg/L]
    fTempC       : REAL;   // 给水温度 [°C] / Feed water temperature [°C]
END_VAR
VAR_OUTPUT
    fOsmoticBar  : REAL;   // 给水渗透压 [bar] / Feed osmotic pressure [bar]
    xValid       : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fTdsClamp   : REAL;   // 钳制到量程内的 TDS [mg/L] / TDS clamped into range [mg/L]
    _fTClampC    : REAL;   // 钳制到量程内的温度 [°C] / Temperature clamped into range [°C]
    _fTKelvin    : REAL;   // 绝对温度 [K] / Absolute temperature [K]
    _fOsmPa      : REAL;   // 渗透压中间量 [Pa] / Osmotic pressure intermediate [Pa]
END_VAR
VAR CONSTANT
    DL_EPS       : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG       : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_K0        : REAL := 273.15;    // 摄氏转开尔文偏移 [K] / Celsius to Kelvin offset [K]
    DL_VANT_HOFF : REAL := 0.28451;   // van't Hoff 合并常数 [Pa·L/(mg·K)] / Lumped van't Hoff constant
    DL_PA_PER_BAR: REAL := 1.0E5;     // Pa → bar 换算因子 [Pa/bar] / Pascal to bar factor [Pa/bar]
    DL_TDS_MAX   : REAL := 60000.0;   // TDS 量程上限（饱和钳制点）[mg/L] / TDS saturation ceiling [mg/L]
    DL_T_LO_C    : REAL := 0.0;       // 温度量程下限 [°C] / Temperature range low [°C]
    DL_T_HI_C    : REAL := 90.0;      // 温度量程上限 [°C] / Temperature range high [°C]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不得进入乘加链） —— *)
IF NOT (fTdsMgL > -DL_BIG AND fTdsMgL < DL_BIG)
   OR NOT (fTempC > -DL_BIG AND fTempC < DL_BIG) THEN
    fOsmoticBar := 0.0;                     // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoOsmoticPressureCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：TDS 负值闸（浓度不可为负 = 变送器故障，不取 ABS 掩盖） —— *)
IF fTdsMgL < 0.0 THEN
    fOsmoticBar := 0.0;                     // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoOsmoticPressureCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：量程钳制（饱和硬限，TDS 上限 / 温度双边界） —— *)
_fTdsClamp := LIMIT(0.0, fTdsMgL, DL_TDS_MAX);        // TDS 钳 0..60000 [mg/L]
_fTClampC := LIMIT(DL_T_LO_C, fTempC, DL_T_HI_C);     // 温度钳 0..90 [°C]
_fTKelvin := _fTClampC + DL_K0;                       // °C → K [K]

(* —— 段 4：van't Hoff 简化式（R22 方向自核：乘温度、乘浓度，均为正相关） —— *)
_fOsmPa := DL_VANT_HOFF * _fTKelvin * _fTdsClamp;     // 渗透压 [Pa]

(* —— 段 5：有效位单点聚合（越量程判无效，钳制值仍输出供参考） —— *)
xValid := (fTdsMgL <= DL_TDS_MAX)                     // TDS 不越上限
          AND (fTempC >= DL_T_LO_C)                   // 温度不越下限
          AND (fTempC <= DL_T_HI_C);                  // 温度不越上限

(* —— 段 6：输出单点写盘（Pa → bar，饱和保护防溢出） —— *)
fOsmoticBar := LIMIT(0.0, _fOsmPa / DL_PA_PER_BAR, DL_BIG);   // 渗透压钳 0..DL_BIG [bar]
FC_DL_RoOsmoticPressureCalc := xValid;                        // 返回码：TRUE = 计算可信

END_FUNCTION
