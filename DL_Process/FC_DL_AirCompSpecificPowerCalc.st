(*
  Name: FC_DL_AirCompSpecificPowerCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 比功率按「单位容积流量的轴功率」计算：fSpecificKW = 轴功率[kW] / 自由排气量[m3/min]，
           量纲为 kW/(m3/min)，是空压系统能效的第一评价指标（越小越优）。
        2) 折算单位能耗 fSecPerM3 按 1 kW = 1 kJ/s 换算：1 m3/min = 60 m3/h，故
           kJ/m3 = kW/(m3/min) × (1 kJ/s / 1 kW) × (60 s/min) = 比功率 × 60，
           该输出用于与电价直接相乘做年运行成本估算，单位是 kJ/m3（等价 kWh/1000 m3 需再除 3600）。
        3) 能效等级 iEffClass 按比功率门槛分级：0 = 优（≤ DL_KLASS1）、1 = 良（≤ DL_KLASS2）、
           2 = 及格（≤ DL_KLASS3）、3 = 差（> DL_KLASS3）。等级门槛为螺杆机常见量级，
           由 VAR CONSTANT 统一组态，不写死在算式里。
  边界条件：1) 非有限值闸：两路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0、等级置 3）并置无效（R19）。
        2) 分母零闸：ABS(fFadM3min) > DL_EPS 才允许相除；排气量为 0 表示空压机停机或流量计失流，
           比功率在数学上发散，故判无效而不是输出一个大数。
        3) 负值闸：轴功率为负（四象限变频回馈）与排气量为负（流量计反向）均判无效；
           回馈工况不属于本件的评价范围，不得用绝对值混入能效统计。
        4) 饱和钳制：比功率结果钳到 0 ~ DL_SP_MAX(200 kW/(m3/min))，避免极小排气量放大成无意义巨值；
           折算能耗同样钳到 0 ~ 12000 kJ/m3，与比功率上限按同一换算关系对齐（×60）。
        5) 量纲不一致的加法一律禁止：本件只有乘除，无跨量纲相加，等级判定只比较同量纲比功率。
  量纲自证：fSpecificKW = kW / (m3/min) = kW·min/m3 = kJ/m3 的 1/60（因 1 kW = 1 kJ/s）；
           fSecPerM3 = kW/(m3/min) × 60 (s/min) = kJ/m3，其中 60 为 [s/min] 时间换算因子；
           两输出量纲一致（同为 kJ/m3 的等价表述），等级门槛与 fSpecificKW 同量纲。
*)

FUNCTION FC_DL_AirCompSpecificPowerCalc : BOOL
VAR_INPUT
    fShaftKW      : REAL;   // 空压机轴功率 [kW] / Compressor shaft power [kW]
    fFadM3min     : REAL;   // 自由排气量 FAD [m3/min] / Free air delivery [m3/min]
END_VAR
VAR_OUTPUT
    fSpecificKW   : REAL;   // 比功率 [kW/(m3/min)] / Specific power [kW/(m3/min)]
    fSecPerM3     : REAL;   // 折算单位能耗 [kJ/m3] / Converted specific energy [kJ/m3]
    iEffClass     : INT;    // 能效等级 0..3（0 最优）[-] / Efficiency class 0..3, 0 best [-]
    xValid        : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fSpecRaw     : REAL;   // 未饱和的原始比功率 [kW/(m3/min)] / Raw specific power [kW/(m3/min)]
    _fSpecClamp   : REAL;   // 饱和钳制后的比功率 [kW/(m3/min)] / Clamped specific power [kW/(m3/min)]
END_VAR
VAR CONSTANT
    DL_EPS        : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG        : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_S_PER_MIN  : REAL := 60.0;      // min → s 换算因子 [s/min] / Minute to second factor [s/min]
    DL_SP_MAX     : REAL := 200.0;     // 比功率饱和上限 [kW/(m3/min)] / Specific power saturation ceiling
    DL_KLASS1     : REAL := 5.0;       // 一级能效比功率门槛 [kW/(m3/min)] / Class-1 efficiency threshold
    DL_KLASS2     : REAL := 6.5;       // 二级能效比功率门槛 [kW/(m3/min)] / Class-2 efficiency threshold
    DL_KLASS3     : REAL := 8.5;       // 三级能效比功率门槛 [kW/(m3/min)] / Class-3 efficiency threshold
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不得进入除法） —— *)
IF NOT (fShaftKW > -DL_BIG AND fShaftKW < DL_BIG)
   OR NOT (fFadM3min > -DL_BIG AND fFadM3min < DL_BIG) THEN
    fSpecificKW := 0.0;                     // 输出强制 0.0 / Output forced to zero
    fSecPerM3 := 0.0;                       // 折算能耗强制 0.0 / Converted energy forced to zero
    iEffClass := 3;                         // 等级置最差档，不给误导性「优」/ Worst class only
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirCompSpecificPowerCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：组态与零闸（R4：分母先过 ABS 闸；负功率/负流量同属故障） —— *)
IF (ABS(fFadM3min) <= DL_EPS) OR (fShaftKW < 0.0) OR (fFadM3min < 0.0) THEN
    fSpecificKW := 0.0;                     // 输出强制 0.0 / Output forced to zero
    fSecPerM3 := 0.0;                       // 折算能耗强制 0.0 / Converted energy forced to zero
    iEffClass := 3;                         // 等级置最差档 / Worst class only
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirCompSpecificPowerCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（R22 方向自核：轴功率为分子、排气量为分母，不可取倒数） —— *)
_fSpecRaw := fShaftKW / fFadM3min;                          // 比功率 [kW/(m3/min)]
_fSpecClamp := LIMIT(0.0, _fSpecRaw, DL_SP_MAX);            // 饱和钳 0..200

(* —— 段 4：能效等级分级（IF/ELSIF 单链，iEffClass 只在此处赋值一次） —— *)
IF _fSpecClamp <= DL_KLASS1 THEN
    iEffClass := 0;                         // 一级能效（优）/ Class 1, best
ELSIF _fSpecClamp <= DL_KLASS2 THEN
    iEffClass := 1;                         // 二级能效（良）/ Class 2, good
ELSIF _fSpecClamp <= DL_KLASS3 THEN
    iEffClass := 2;                         // 三级能效（及格）/ Class 3, acceptable
ELSE
    iEffClass := 3;                         // 低于三级（差）/ Below class 3, poor
END_IF

(* —— 段 5：输出单点写盘（折算能耗与比功率同一基准，换算因子 60 s/min） —— *)
fSpecificKW := _fSpecClamp;                                 // 比功率出口 [kW/(m3/min)]
fSecPerM3 := _fSpecClamp * DL_S_PER_MIN;                    // 折算单位能耗 [kJ/m3]
xValid := (fShaftKW >= 0.0) AND (fFadM3min > DL_EPS);       // 有效位单点聚合
FC_DL_AirCompSpecificPowerCalc := xValid;                   // 返回码：TRUE = 计算可信

END_FUNCTION
