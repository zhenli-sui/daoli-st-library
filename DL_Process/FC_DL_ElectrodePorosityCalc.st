(*
  Name: FC_DL_ElectrodePorosityCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 极片孔隙率按「孔隙体积占表观体积的比例」计算。表观体积 V = 涂层质量 / 压实密度，
           固体实体体积 V_s = 涂层质量 / 真密度，孔隙体积 = V − V_s，
           故孔隙率 = 1 − 压实密度 / 真密度，乘 100 转百分数。
           该式与涂层质量无关（质量在比值中消去），只取决于两个密度之比。
        2) 用于辊压工序的压实程度评价：孔隙率过低会导致电解液浸润困难与析锂风险，
           过高则电子导电网络接触不良、能量密度不足，故需落在工艺窗口内。
  边界条件：1) 非有限值闸：两路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fPorosityPct 强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fTrueDensityGcm3) > DL_EPS 才允许相除（真密度为 0 无物理意义）。
        3) 负值闸：两个密度任一为负判无效（不取绝对值掩盖反向）。
        4) 物理域校验：压实密度必须严格小于真密度，否则孔隙率为负（固体体积大于表观体积，
           不可能），判无效且输出钳 0；结果同时钳到 0 ~ 100 % 的物理域。
        5) 量程校验：真密度钳 0 ~ DL_RHO_MAX(10 g/cm3)、压实密度同域，越域钳边界算参考值但置无效；
           真密度为 0 与「三元材料 2.0~5.0 g/cm3」的实际量程差距过大，故另设 DL_RHO_MIN(0.5 g/cm3)
           作为可信下限，低于该值视为组态或传感器异常。
  量纲自证：孔隙率 = 1 − (g/cm3) / (g/cm3) = 1 − 无因次 = 无因次，乘 100 得 [%]；
           密度比无量纲，厚度/质量/体积项均已通过密度定义消去，无跨量纲相加。
*)

FUNCTION FC_DL_ElectrodePorosityCalc : BOOL
VAR_INPUT
    fCompactionGcm3  : REAL;   // 极片压实密度 [g/cm3] / Electrode compaction density [g/cm3]
    fTrueDensityGcm3 : REAL;   // 材料真密度 [g/cm3] / Material true density [g/cm3]
END_VAR
VAR_OUTPUT
    fPorosityPct     : REAL;   // 极片孔隙率 [%] / Electrode porosity [%]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDensityRatio   : REAL;   // 压实密度 / 真密度 [-] / Compaction to true density ratio [-]
    _fPorosityRawPct : REAL;   // 未饱和的孔隙率 [%] / Raw porosity [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_RHO_MIN       : REAL := 0.50;      // 密度可信下限 [g/cm3] / Density credibility low [g/cm3]
    DL_RHO_MAX       : REAL := 10.0;      // 密度量程上限 [g/cm3] / Density range ceiling [g/cm3]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不得进入比值） —— *)
IF NOT (fCompactionGcm3 > -DL_BIG AND fCompactionGcm3 < DL_BIG)
   OR NOT (fTrueDensityGcm3 > -DL_BIG AND fTrueDensityGcm3 < DL_BIG) THEN
    fPorosityPct := 0.0;                    // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_ElectrodePorosityCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：真密度是比值分母） —— *)
IF ABS(fTrueDensityGcm3) <= DL_EPS THEN
    fPorosityPct := 0.0;                    // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_ElectrodePorosityCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（密度为负无物理意义，不取绝对值掩盖） —— *)
IF (fCompactionGcm3 < 0.0) OR (fTrueDensityGcm3 < 0.0) THEN
    fPorosityPct := 0.0;                    // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_ElectrodePorosityCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：主算式（R22 方向自核：压实密度在分子，真密度在分母，二者不可交换） —— *)
_fDensityRatio := fCompactionGcm3 / fTrueDensityGcm3;             // 密度比 [-]
_fPorosityRawPct := (1.0 - _fDensityRatio) * DL_PCT;              // 孔隙率 [%]

(* —— 段 5：输出单点写盘（钳到 0~100 % 物理域，负孔隙率不得流出） —— *)
fPorosityPct := LIMIT(0.0, _fPorosityRawPct, DL_PCT);             // 孔隙率 [%]

(* —— 段 6：有效位单点聚合（物理域 + 密度量程） —— *)
xValid := (fCompactionGcm3 < fTrueDensityGcm3)                    // 压实密度必须小于真密度
          AND (fTrueDensityGcm3 >= DL_RHO_MIN)                    // 真密度不低于可信下限
          AND (fTrueDensityGcm3 <= DL_RHO_MAX)                    // 真密度不越量程
          AND (fCompactionGcm3 <= DL_RHO_MAX);                    // 压实密度不越量程
FC_DL_ElectrodePorosityCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
