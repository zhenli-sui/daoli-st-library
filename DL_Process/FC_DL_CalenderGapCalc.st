(*
  Name: FC_DL_CalenderGapCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 由辊压前（来料）厚度与密度、以及目标压实密度，按质量守恒反算辊压后厚度：
             来料面密度 = 来料厚度 × 来料密度；压实后同一面密度的质量不变，故
             出料厚度 = 来料厚度 × 来料密度 / 目标压实密度。
           质量守恒中的面密度在两侧相等，密度升高则厚度等比例下降，方向不可反写。
        2) 辊压间隙设定值 = 出料厚度 + DL_MILL_COMP_UM（机架弹性变形补偿）。
           补偿量是「轧制力下机架牌坊与辊系弹性伸张」的工程修正，本产线实测为 0，
           故以 VAR CONSTANT 形式预留而非写死在算式中，更换机架时只改组态不改代码。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fGapUm 强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fTargetDensityGcm3) > DL_EPS 与 ABS(fInDensityGcm3) > DL_EPS
           都必须通过，否则判无效（密度为 0 时比例无定义）。
        3) 负值闸：来料厚度为负、任一密度为负判无效（不取绝对值掩盖反向）。
        4) 工艺方向闸：目标压实密度必须严格大于来料密度（辊压的物理目的是增密）。
           若目标密度 <= 来料密度，则反算出的「出料厚度 >= 来料厚度」，即辊压变成减薄的反向过程，
           属工艺参数错误，判无效而不输出该间隙。
        5) 饱和钳制：出料厚度先钳 0 ~ DL_THK_MAX(5000 µm)，间隙再钳同一上限，防极端密度比溢出。
  量纲自证：出料厚度 = µm × (g/cm3) / (g/cm3) = µm，密度比值无因次，量纲保持厚度；
           间隙 = µm + µm = µm，补偿量与厚度同量纲，加法合法。
*)

FUNCTION FC_DL_CalenderGapCalc : BOOL
VAR_INPUT
    fInThickUm       : REAL;   // 来料（辊压前）厚度 [µm] / Incoming thickness before calendering [µm]
    fInDensityGcm3   : REAL;   // 来料涂层密度 [g/cm3] / Incoming coating density [g/cm3]
    fTargetDensityGcm3 : REAL; // 目标压实密度 [g/cm3] / Target compaction density [g/cm3]
END_VAR
VAR_OUTPUT
    fGapUm           : REAL;   // 辊压间隙设定值 [µm] / Calender gap setpoint [µm]
    fOutThickUm      : REAL;   // 反算出的辊压后厚度 [µm] / Calculated outgoing thickness [µm]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDensityRatio   : REAL;   // 来料密度 / 目标密度 [-] / Incoming to target density ratio [-]
    _fOutThickRawUm  : REAL;   // 未钳制的出料厚度 [µm] / Raw outgoing thickness [µm]
    _fGapRawUm       : REAL;   // 未钳制的间隙设定值 [µm] / Raw gap setpoint [µm]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;   // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;   // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_MILL_COMP_UM  : REAL := 0.0;      // 机架弹性变形补偿（本产线实测 0，预留）[µm] / Mill stretch comp
    DL_THK_MAX       : REAL := 5000.0;   // 厚度饱和钳制上限 [µm] / Thickness saturation ceiling [µm]
END_VAR

(* —— 段 1：非有限值闸（R19：三路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fInThickUm > -DL_BIG AND fInThickUm < DL_BIG)
   OR NOT (fInDensityGcm3 > -DL_BIG AND fInDensityGcm3 < DL_BIG)
   OR NOT (fTargetDensityGcm3 > -DL_BIG AND fTargetDensityGcm3 < DL_BIG) THEN
    fGapUm := 0.0;                          // 输出强制 0.0 / Output forced to zero
    fOutThickUm := 0.0;                     // 出料厚度强制 0.0 / Outgoing thickness forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_CalenderGapCalc := FALSE;         // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：两个密度都必须先过 ABS 闸） —— *)
IF (ABS(fTargetDensityGcm3) <= DL_EPS) OR (ABS(fInDensityGcm3) <= DL_EPS) THEN
    fGapUm := 0.0;                          // 输出强制 0.0 / Output forced to zero
    fOutThickUm := 0.0;                     // 出料厚度强制 0.0 / Outgoing thickness forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CalenderGapCalc := FALSE;         // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（厚度与密度均不可为负） —— *)
IF (fInThickUm < 0.0) OR (fInDensityGcm3 < 0.0) OR (fTargetDensityGcm3 < 0.0) THEN
    fGapUm := 0.0;                          // 输出强制 0.0 / Output forced to zero
    fOutThickUm := 0.0;                     // 出料厚度强制 0.0 / Outgoing thickness forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CalenderGapCalc := FALSE;         // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：质量守恒主算式（R22 方向自核：来料密度在分子、目标密度在分母） —— *)
_fDensityRatio := fInDensityGcm3 / fTargetDensityGcm3;            // 密度比 [-]
_fOutThickRawUm := fInThickUm * _fDensityRatio;                   // 出料厚度 [µm]
_fGapRawUm := _fOutThickRawUm + DL_MILL_COMP_UM;                  // 间隙 = 出料厚度 + 弹性补偿 [µm]

(* —— 段 5：输出单点写盘（饱和钳制） —— *)
fOutThickUm := LIMIT(0.0, _fOutThickRawUm, DL_THK_MAX);           // 出料厚度 [µm]
fGapUm := LIMIT(0.0, _fGapRawUm, DL_THK_MAX);                     // 间隙设定值 [µm]

(* —— 段 6：有效位单点聚合（工艺方向闸：目标密度必须严格大于来料密度） —— *)
xValid := (fInThickUm > DL_EPS)                                   // 来料厚度为正
          AND (fInDensityGcm3 > DL_EPS)                           // 来料密度为正
          AND (fTargetDensityGcm3 > DL_EPS)                       // 目标密度为正
          AND (fTargetDensityGcm3 > fInDensityGcm3);              // 必须为增密过程
FC_DL_CalenderGapCalc := xValid;                                  // 返回码：TRUE = 计算可信

END_FUNCTION
