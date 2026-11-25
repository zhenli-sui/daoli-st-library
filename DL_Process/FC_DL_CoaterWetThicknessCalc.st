(*
  Name: FC_DL_CoaterWetThicknessCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 由目标干膜面密度与浆料固含量反算湿膜厚度，供涂布模头间隙（湿膜）设定使用。
           推导链：干燥后保留的固体质量面密度即目标面密度；湿膜中固体占质量比例为固含量，
           故湿膜质量面密度 = 干面密度 / 固含量；再由湿膜密度换算为体积厚度。
           逐步为：mg/cm2 → g/m2 乘 10；除以固含量比例得湿膜 g/m2；
           除以密度 g/cm3 直接得 µm（因为 1 g/m2 ÷ 1 g/cm3 = 1 µm，量纲恰好对消）。
        2) 固含量按百分比入参，先归一化到 0~1 再作分母，禁止直接用百分数当比例。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fWetUm 强制 0.0）并置无效（R19）。
        2) 分母零闸：固含量比例必须 ABS > DL_EPS（固含量为 0 表示全溶剂，湿膜厚度趋于无穷，
           物理上不可能）；密度必须 ABS > DL_EPS（密度为 0 无意义）。
        3) 固含量窄闸：必须落在 DL_SOLID_MIN(0.1 %) ~ 100 %，越域判无效；
           上限 100 % 是「无溶剂」极限，此时湿膜 = 干膜，属合法边界值。
        4) 负值闸：面密度为负、密度为负判无效（不取绝对值掩盖反向）。
        5) 饱和钳制：湿膜厚度钳 0 ~ DL_WET_MAX(5000 µm)，防极小固含量把厚度放大到溢出。
  量纲自证：fArealMgCm2 [mg/cm2] × 10 (g/m2 per mg/cm2) = g/m2；
           除以固含量 [-]= g/m2（湿膜）；
           除以密度 [g/cm3]：g/m2 ÷ g/cm3 = cm3/m2 = 1e-6 m3/m2 = 1e-6 m = 1 µm，故结果 [µm]。
*)

FUNCTION FC_DL_CoaterWetThicknessCalc : BOOL
VAR_INPUT
    fArealMgCm2   : REAL;   // 目标干膜面密度 [mg/cm2] / Target dry areal loading [mg/cm2]
    fSolidPct     : REAL;   // 浆料固含量 [%] / Slurry solid content [%]
    fDensityGcm3  : REAL;   // 湿膜密度 [g/cm3] / Wet film density [g/cm3]
END_VAR
VAR_OUTPUT
    fWetUm        : REAL;   // 湿膜厚度 [µm] / Wet film thickness [µm]
    xValid        : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fSolidRatio  : REAL;   // 归一化固含量 [-] / Normalized solid ratio [-]
    _fDryGm2      : REAL;   // 干膜面密度 [g/m2] / Dry areal loading [g/m2]
    _fWetGm2      : REAL;   // 湿膜面密度 [g/m2] / Wet areal loading [g/m2]
    _fWetRawUm    : REAL;   // 未饱和的湿膜厚度 [µm] / Raw wet thickness [µm]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT        : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_MGCM2_TO_GM2 : REAL := 10.0;    // mg/cm2 → g/m2 换算因子 [g/m2 per mg/cm2] / Areal unit factor
    DL_SOLID_MIN  : REAL := 0.10;      // 固含量下限 [%] / Solid content lower bound [%]
    DL_WET_MAX    : REAL := 5000.0;    // 湿膜厚度饱和上限 [µm] / Wet thickness saturation ceiling [µm]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不得进入除法链） —— *)
IF NOT (fArealMgCm2 > -DL_BIG AND fArealMgCm2 < DL_BIG)
   OR NOT (fSolidPct > -DL_BIG AND fSolidPct < DL_BIG)
   OR NOT (fDensityGcm3 > -DL_BIG AND fDensityGcm3 < DL_BIG) THEN
    fWetUm := 0.0;                          // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_CoaterWetThicknessCalc := FALSE;  // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：固含量与密度两个分母都必须先过 ABS 闸） —— *)
IF (ABS(fSolidPct / DL_PCT) <= DL_EPS) OR (ABS(fDensityGcm3) <= DL_EPS) THEN
    fWetUm := 0.0;                          // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterWetThicknessCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（面密度/密度为负属变送器故障，不取 ABS 掩盖） —— *)
IF (fArealMgCm2 < 0.0) OR (fDensityGcm3 < 0.0) THEN
    fWetUm := 0.0;                          // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterWetThicknessCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：主算式（R22 方向自核：固含量在分母，固含量越高湿膜越薄） —— *)
_fSolidRatio := fSolidPct / DL_PCT;                              // 固含量归一 [-]
_fDryGm2 := fArealMgCm2 * DL_MGCM2_TO_GM2;                       // 干膜面密度 [g/m2]
_fWetGm2 := _fDryGm2 / _fSolidRatio;                             // 湿膜面密度 [g/m2]
_fWetRawUm := _fWetGm2 / fDensityGcm3;                           // 湿膜厚度 [µm]

(* —— 段 5：输出单点写盘（饱和钳制） —— *)
fWetUm := LIMIT(0.0, _fWetRawUm, DL_WET_MAX);                    // 湿膜厚度 [µm]

(* —— 段 6：有效位单点聚合（固含量窄闸 + 非负） —— *)
xValid := (fSolidPct >= DL_SOLID_MIN) AND (fSolidPct <= DL_PCT)  // 固含量在窄闸内
          AND (fArealMgCm2 >= 0.0)                               // 面密度非负
          AND (fDensityGcm3 > DL_EPS);                           // 密度为正
FC_DL_CoaterWetThicknessCalc := xValid;                          // 返回码：TRUE = 计算可信

END_FUNCTION
