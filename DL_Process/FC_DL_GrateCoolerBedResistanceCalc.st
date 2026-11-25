(*
  Name: FC_DL_GrateCoolerBedResistanceCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 水泥窑篦冷机与预热器，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 篦床料层阻力按「Ergun 型阻力式的粒度无关简化形」计算：压损正比于料层厚度、
           风量平方与料层堆积密度，反比于开孔率的三次方，
           即 dP = fK * H * rho * (Q/A_open)^2 / 2，A_open = A_total * phi，
           其中 fK 为综合阻力系数（含篦板结构与料层孔隙率经验项）。
        2) 输出三条派生量：料层压损 fBedDpKpa、按开孔率的等效穿孔风速 fOpenVelMs、
           以及压损相对上限的负荷率 fDpLoadPct（用于判断是否接近风机能力极限）。
        3) 压损上限 fDpMaxKpa 为设备许可值，超限只置 xValid=FALSE 并给出超限标志 xDpOver，
           数值本身钳到上限内输出，绝不把越限值伪装成合格值。
  边界条件：1) 非有限值闸：七路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（全部输出强制 0.0），不得只置标志（R19）。
        2) 分母零闸：料层厚度 fBedHeightM、篦床总面积 fGrateAreaM2 必须 > DL_EPS；
           开孔率 fOpenRatio 必须落在 (DL_PHI_EPS, 1.0] 内 —— 开孔率为 0 或大于 1 均属组态错误，
           直接判无效而非钳制，因为开孔率进三次方，钳制会严重扭曲结果。
        3) 判据取原始值（R24）：压损超限判定使用钳制前的 _fDpRawKpa，
           不得先把压损夹到上限再判是否越限（否则判据恒真）。
        4) 物理域钳制：压损钳 0.0 ~ fDpMaxKpa；穿孔风速钳 0.0 ~ DL_VEL_HI_MS；
           负荷率钳 0.0 ~ DL_LOAD_HI_PCT。
        5) 上限自身校验：fDpMaxKpa 必须 > DL_EPS，为负或零视为未组态，判无效。
        6) 纯函数无状态：不做去抖，堵塞判据的持续性与延时由下游监视 FB 承担。
  量纲自证：开孔面积 A_open = (m2)*(无因次) = m2；
           穿孔风速 = (m3/h)/(m2)/(s/h) = (m3/h)/(m2) * (h/s) = m/s；
           压损 = 无因次 * (m) * (kg/m3) * (m/s)^2 = (kg/m3)*(m2/s2)*(m) = kg/(m*s2) = Pa，
           再除 1000 得 kPa，量纲链自洽。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_GrateCoolerBedResistanceCalc : BOOL
VAR_INPUT
    fCoolingAirNm3h  : REAL;   // 该风室冷却风量 [Nm3/h] / Cooling air flow of the chamber [Nm3/h]
    fBedHeightM      : REAL;   // 篦床上料层厚度 [m] / Clinker bed height on the grate [m]
    fGrateAreaM2     : REAL;   // 该风室篦床有效面积 [m2] / Effective grate area of the chamber [m2]
    fOpenRatio       : REAL;   // 篦板开孔率（0~1 无因次）[-] / Grate open area ratio, dimensionless [-]
    fBulkDensityKgm3 : REAL;   // 料层堆积密度 [kg/m3] / Clinker bulk density [kg/m3]
    fResistCoef      : REAL;   // 综合阻力系数（含孔隙率经验项）[-] / Combined resistance coefficient [-]
    fDpMaxKpa        : REAL;   // 设备许可料层压损上限 [kPa] / Permitted bed pressure drop [kPa]
END_VAR
VAR_OUTPUT
    fBedDpKpa        : REAL;   // 料层压损 [kPa] / Clinker bed pressure drop [kPa]
    fOpenVelMs       : REAL;   // 篦板穿孔风速 [m/s] / Open-area jet velocity [m/s]
    fDpLoadPct       : REAL;   // 压损对上限的负荷率 [%] / Pressure drop load ratio [%]
    xDpOver          : BOOL;   // 压损超限标志（判定用原始值）[bool] / Pressure drop overrun flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fOpenAreaM2     : REAL;   // 篦板有效开孔面积 [m2] / Effective open area of the grate [m2]
    _fOpenVelRawMs   : REAL;   // 钳制前的穿孔风速 [m/s] / Raw open-area velocity [m/s]
    _fDpRawKpa       : REAL;   // 钳制前的原始料层压损 [kPa] / Raw bed pressure drop [kPa]
    _fLoadRawPct     : REAL;   // 钳制前的原始负荷率 [%] / Raw load ratio [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_PHI_EPS       : REAL := 1.0E-6;    // 开孔率下限阈值 [-] / Open-ratio low gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_SEC_PER_H     : REAL := 3600.0;    // 小时到秒的时基折算 [s/h] / Seconds per hour [s/h]
    DL_PA_PER_KPA    : REAL := 1000.0;    // 帕到千帕的折算 [Pa/kPa] / Pascals per kilopascal [Pa/kPa]
    DL_PHI_HI        : REAL := 1.0;       // 开孔率物理上限 [-] / Open-ratio physical upper bound [-]
    DL_VEL_HI_MS     : REAL := 100.0;     // 穿孔风速物理上限 [m/s] / Jet velocity upper bound [m/s]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_LOAD_HI_PCT   : REAL := 100.0;     // 负荷率物理上限 [%] / Load ratio upper bound [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fCoolingAirNm3h > -DL_BIG AND fCoolingAirNm3h < DL_BIG)
   OR NOT (fBedHeightM > -DL_BIG AND fBedHeightM < DL_BIG)
   OR NOT (fGrateAreaM2 > -DL_BIG AND fGrateAreaM2 < DL_BIG)
   OR NOT (fOpenRatio > -DL_BIG AND fOpenRatio < DL_BIG)
   OR NOT (fBulkDensityKgm3 > -DL_BIG AND fBulkDensityKgm3 < DL_BIG)
   OR NOT (fResistCoef > -DL_BIG AND fResistCoef < DL_BIG)
   OR NOT (fDpMaxKpa > -DL_BIG AND fDpMaxKpa < DL_BIG) THEN
    fBedDpKpa := 0.0;                       // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fOpenVelMs := 0.0;                      // 风速同样强制 0.0 / Velocity forced to zero
    fDpLoadPct := 0.0;                      // 负荷率强制 0.0 / Load ratio forced to zero
    xDpOver := FALSE;                       // 超限位不得在失效时置真 / Overrun must stay false when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GrateCoolerBedResistanceCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：几何与组态域闸（开孔率进三次方，越域一律判无效而非钳制） —— *)
IF (fGrateAreaM2 <= DL_EPS)                                       // 篦床面积不可为零
   OR (fBedHeightM <= DL_EPS)                                     // 料层厚度不可为零
   OR (fOpenRatio <= DL_PHI_EPS)                                  // 开孔率不可为零
   OR (fOpenRatio > DL_PHI_HI)                                    // 开孔率不得大于 1
   OR (fDpMaxKpa <= DL_EPS) THEN                                  // 压损上限必须已组态
    fBedDpKpa := 0.0;                       // 几何不可用即无压损 / No geometry, no drop
    fOpenVelMs := 0.0;                      // 风速不可算 / Velocity not computable
    fDpLoadPct := 0.0;                      // 负荷率不可算 / Load ratio not computable
    xDpOver := FALSE;                       // 失效侧超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GrateCoolerBedResistanceCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fOpenAreaM2 := fGrateAreaM2 * fOpenRatio;                                        // 有效开孔面积 [m2]
_fOpenVelRawMs := fCoolingAirNm3h / _fOpenAreaM2 / DL_SEC_PER_H;                  // 穿孔风速 [m/s]
_fDpRawKpa := fResistCoef * fBedHeightM * fBulkDensityKgm3
              * _fOpenVelRawMs * _fOpenVelRawMs / DL_PA_PER_KPA;                  // 动压式压损 [kPa]
_fLoadRawPct := _fDpRawKpa / fDpMaxKpa * DL_PCT;                                  // 原始负荷率 [%]

(* —— 段 4：判据（全部取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xDpOver := (_fDpRawKpa > fDpMaxKpa);                                              // 压损越上限
xValid := (fCoolingAirNm3h >= 0.0)                                                // 风量不得为负
          AND (fBedHeightM >= 0.0)                                                // 料层厚度不得为负
          AND (fBulkDensityKgm3 > 0.0)                                            // 堆积密度必须为正
          AND (fResistCoef > 0.0)                                                 // 阻力系数必须为正
          AND (_fOpenVelRawMs >= 0.0)                                             // 风速不得为负
          AND (_fDpRawKpa >= 0.0);                                                // 压损不得为负（负压损属符号错误）

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fBedDpKpa := LIMIT(0.0, _fDpRawKpa, fDpMaxKpa);                                   // 压损钳 0..上限 [kPa]
fOpenVelMs := LIMIT(0.0, _fOpenVelRawMs, DL_VEL_HI_MS);                           // 风速钳 0..上限 [m/s]
fDpLoadPct := LIMIT(0.0, _fLoadRawPct, DL_LOAD_HI_PCT);                           // 负荷率钳 0..100 [%]
FC_DL_GrateCoolerBedResistanceCalc := xValid;                                     // 返回码：TRUE = 计算可信

END_FUNCTION
