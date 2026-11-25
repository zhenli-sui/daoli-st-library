(*
  Name: FC_DL_GlassResidualStressCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 残余应力按「温降速率造成的厚度方向温差」估算，逐步为：
             厚度方向温差 ΔT = 温降速率 × 厚度 × 特征均温时间常数
             残余应力 σ = 弹性模量 × 线膨胀系数 × ΔT
           热应力的物理本质是「表面先冷收缩、内部后收缩」，两者收缩量之差受弹性约束即产生应力，
           故应力与「温降速率 × 厚度」成正比，与线膨胀系数、弹性模量成正比。
           特征均温时间常数 DL_TAU_MIN_PER_MM 是「每 mm 厚度对应的热滞后时间」的工程标定值，
           量纲为 min/mm，乘温降速率与厚度后恰好得 °C，不引入额外量纲。
        2) 与安全阈值 DL_SIGMA_SAFE 比较给出 xSafe。退火玻璃的允许残余应力远低于钢化玻璃，
           超阈值意味着切割炸裂与翘曲风险，故上限是硬约束。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fStressMpa 强制 0.0、xSafe 强制 FALSE）并置无效（R19）。
        2) 分母零闸：本件除数仅为常量，无运行期分母；但三个物性/几何输入都必须为正才具有物理意义，
           故对温降速率、膨胀系数、厚度、弹性模量做 > DL_EPS 的门控（零值判无效）。
        3) 负值闸：温降速率为负（升温）时残余应力符号反转为压应力，本件的判定只面向降温工况，
           故负速率一律判无效而不取绝对值（取绝对值会把升温段误判为有炸裂风险）。
        4) 量程校验：线膨胀系数 0 ~ DL_CTE_MAX(1.0E-4 /°C)、厚度 0 ~ DL_THK_MAX(50 mm)、
           弹性模量 0 ~ DL_E_MAX(300 GPa)、温降速率 0 ~ DL_RATE_MAX(15 °C/min)，越域钳边界但置无效。
        5) 饱和钳制：应力结果钳 0 ~ DL_SIGMA_MAX(1000 MPa)，防组态越界溢出。
  量纲自证：ΔT = (°C/min) × mm × (min/mm) = °C；
           σ = (GPa × 1000 MPa/GPa) × (1/°C) × °C = MPa，量纲闭合；
           1000 为 [MPa/GPa] 弹性模量单位换算因子，无因次混入。
*)

FUNCTION FC_DL_GlassResidualStressCalc : BOOL
VAR_INPUT
    fCoolRateCmin  : REAL;   // 温降速率 [°C/min] / Cooling rate [°C/min]
    fCtePerC       : REAL;   // 线膨胀系数 [1/°C] / Coefficient of thermal expansion [1/°C]
    fThickMm       : REAL;   // 玻璃带厚度 [mm] / Ribbon thickness [mm]
    fYoungGpa      : REAL;   // 弹性模量 [GPa] / Young's modulus [GPa]
END_VAR
VAR_OUTPUT
    fStressMpa     : REAL;   // 估算残余应力 [MPa] / Estimated residual stress [MPa]
    fDeltaTk       : REAL;   // 厚度方向温差（观测用）[°C] / Through-thickness temperature difference [°C]
    xSafe          : BOOL;   // 残余应力安全标志 [bool] / Residual stress safe flag [bool]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fRateClamp    : REAL;   // 钳制后的温降速率 [°C/min] / Clamped cooling rate [°C/min]
    _fThickClamp   : REAL;   // 钳制后的厚度 [mm] / Clamped thickness [mm]
    _fCteClamp     : REAL;   // 钳制后的膨胀系数 [1/°C] / Clamped CTE [1/°C]
    _fYoungClamp   : REAL;   // 钳制后的弹性模量 [GPa] / Clamped Young's modulus [GPa]
    _fDeltaTRaw    : REAL;   // 未饱和的厚度温差 [°C] / Raw through-thickness delta T [°C]
    _fStressRaw    : REAL;   // 未饱和的残余应力 [MPa] / Raw residual stress [MPa]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 零闸阈值 [-] / Zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_MPA_PER_GPA : REAL := 1000.0;    // GPa → MPa 换算因子 [MPa/GPa] / Gigapascal to megapascal factor
    DL_TAU_MIN_PER_MM : REAL := 0.50;   // 热滞后时间常数 [min/mm] / Thermal lag time constant [min/mm]
    DL_RATE_MAX    : REAL := 15.0;      // 温降速率量程上限 [°C/min] / Cooling rate range high [°C/min]
    DL_CTE_MAX     : REAL := 1.0E-4;    // 膨胀系数量程上限 [1/°C] / CTE range high [1/°C]
    DL_THK_MAX     : REAL := 50.0;      // 厚度量程上限 [mm] / Thickness range high [mm]
    DL_E_MAX       : REAL := 300.0;     // 弹性模量量程上限 [GPa] / Young's modulus range high [GPa]
    DL_SIGMA_SAFE  : REAL := 7.0;       // 退火残余应力安全阈值 [MPa] / Safe residual stress limit [MPa]
    DL_SIGMA_MAX   : REAL := 1000.0;    // 应力饱和钳制上限 [MPa] / Stress saturation ceiling [MPa]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fCoolRateCmin > -DL_BIG AND fCoolRateCmin < DL_BIG)
   OR NOT (fCtePerC > -DL_BIG AND fCtePerC < DL_BIG)
   OR NOT (fThickMm > -DL_BIG AND fThickMm < DL_BIG)
   OR NOT (fYoungGpa > -DL_BIG AND fYoungGpa < DL_BIG) THEN
    fStressMpa := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fDeltaTk := 0.0;                        // 温差强制 0.0 / Delta T forced to zero
    xSafe := FALSE;                         // 安全标志强制 FALSE / Safe flag forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GlassResidualStressCalc := FALSE; // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：零闸与负值闸（物性/几何必须为正；升温工况不属本件判定范围） —— *)
IF (fCoolRateCmin < 0.0) OR (fCtePerC <= DL_EPS) OR (fThickMm <= DL_EPS) OR (fYoungGpa <= DL_EPS) THEN
    fStressMpa := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fDeltaTk := 0.0;                        // 温差强制 0.0 / Delta T forced to zero
    xSafe := FALSE;                         // 安全标志强制 FALSE / Safe flag forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GlassResidualStressCalc := FALSE; // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：量程钳制（越域钳边界算参考值，段 6 判无效） —— *)
_fRateClamp := LIMIT(0.0, fCoolRateCmin, DL_RATE_MAX);            // 速率钳 0..15 [°C/min]
_fThickClamp := LIMIT(0.0, fThickMm, DL_THK_MAX);                 // 厚度钳 0..50 [mm]
_fCteClamp := LIMIT(0.0, fCtePerC, DL_CTE_MAX);                   // 膨胀系数钳 [1/°C]
_fYoungClamp := LIMIT(0.0, fYoungGpa, DL_E_MAX);                  // 弹性模量钳 [GPa]

(* —— 段 4：厚度温差与残余应力（R22 方向自核：速率与厚度相乘，被时间常数折算为温差） —— *)
_fDeltaTRaw := _fRateClamp * _fThickClamp * DL_TAU_MIN_PER_MM;    // 厚度温差 [°C]
_fStressRaw := _fYoungClamp * DL_MPA_PER_GPA * _fCteClamp * _fDeltaTRaw;   // 残余应力 [MPa]

(* —— 段 5：输出单点写盘（饱和钳制后判安全，保证判据与出口同源） —— *)
fDeltaTk := LIMIT(0.0, _fDeltaTRaw, DL_BIG);                      // 温差出口 [°C]
fStressMpa := LIMIT(0.0, _fStressRaw, DL_SIGMA_MAX);              // 应力出口 [MPa]

(* —— 段 6：有效位单点聚合（四路量程校验） —— *)
xValid := (fCoolRateCmin >= 0.0) AND (fCoolRateCmin <= DL_RATE_MAX)
          AND (fCtePerC > DL_EPS) AND (fCtePerC <= DL_CTE_MAX)
          AND (fThickMm > DL_EPS) AND (fThickMm <= DL_THK_MAX)
          AND (fYoungGpa > DL_EPS) AND (fYoungGpa <= DL_E_MAX);

(* —— 段 7：安全判定（无效数据不得判安全） —— *)
xSafe := xValid AND (fStressMpa <= DL_SIGMA_SAFE);
FC_DL_GlassResidualStressCalc := xValid;                          // 返回码：TRUE = 计算可信

END_FUNCTION
