(*
  Name: FC_DL_FloatBathTempProfileCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 锡槽温度剖面按三段折线插值：三个温度给定点 T1（入口段）、T2（中段）、T3（出口段）
           把整条锡槽长度等分为前后两个插值区间，段号为 iZone 的区间中心位置 z 落在哪个区间，
           就在该区间内做线性插值，得到该段代表温度 fLocalC。
           位置口径：z = (段号 − 1) × 段长 + 段长/2，即取该段的几何中心；
           归一化位置 u = z / 总长，钳制到 0~1（首末端越界由钳制吸收，不外推）。
        2) 温度梯度 fGradCpm 取所在插值区间的斜率：(区间末端温度 − 区间起点温度) / 区间物理长度，
           单位为 °C/m。梯度方向定义为「沿玻璃带前进方向」，故入口→中段为正升温、中段→出口为负降温。
        3) 段号 iZone 做 1 ~ N 的闭区间钳制（N = 总长 / 段长 取整，至少 1 段），
           越界不报错而是钳制，因为段号越界属于组态提示而非测量故障。
  边界条件：1) 非有限值闸：五个实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：总长 fZoneLenM 与段长 fZoneSpanM 都必须 ABS > DL_EPS，
           否则归一化位置与插值区间长度无定义。
        3) 负值闸：总长与段长为负判无效；温度为负属合法（锡槽不会负温，但算式本身不禁止，
           由量程校验统一处理）。
        4) 量程校验：三个温度给定点须落在 DL_T_LO_C(0 °C) ~ DL_T_HI_C(1200 °C)，
           越域钳边界算参考值但置无效（超出浮法锡槽的物理温度域）。
        5) 单段退化：N = 1 时无插值区间，梯度定义为 0（不设梯度信息），fLocalC 取 T1。
        6) 无回差环节：纯函数无状态，不做迟滞。
  量纲自证：z = (段) × m + m = m；u = m / m = 无因次；
           fLocalC = °C + (°C) × 无因次 = °C；
           fGradCpm = (°C) / m = °C/m，减法两侧同为 °C，量纲闭合。
*)

FUNCTION FC_DL_FloatBathTempProfileCalc : BOOL
VAR_INPUT
    fT1C        : REAL;   // 入口段温度给定 [°C] / Inlet zone temperature setpoint [°C]
    fT2C        : REAL;   // 中段温度给定 [°C] / Middle zone temperature setpoint [°C]
    fT3C        : REAL;   // 出口段温度给定 [°C] / Outlet zone temperature setpoint [°C]
    fZoneLenM   : REAL;   // 锡槽总长 [m] / Total bath length [m]
    iZone       : INT;    // 段号（1 起）[-] / Zone index, one based [-]
    fZoneSpanM  : REAL;   // 单段长度 [m] / Single zone length [m]
END_VAR
VAR_OUTPUT
    fLocalC     : REAL;   // 该段代表温度 [°C] / Representative zone temperature [°C]
    fGradCpm    : REAL;   // 沿带前进方向的温度梯度 [°C/m] / Temperature gradient along ribbon [°C/m]
    iZoneClamp  : INT;    // 钳制后的段号 [-] / Clamped zone index [-]
    xValid      : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _iZoneCount : INT;    // 总段数 [-] / Total zone count [-]
    _fPosM      : REAL;   // 该段几何中心位置 [m] / Zone centre position [m]
    _fU         : REAL;   // 归一化位置 0..1 [-] / Normalized position 0..1 [-]
    _fSegLenM   : REAL;   // 单个插值区间物理长度 [m] / Interpolation segment length [m]
    _fT1Clamp   : REAL;   // 钳制后的入口温度 [°C] / Clamped inlet temperature [°C]
    _fT2Clamp   : REAL;   // 钳制后的中段温度 [°C] / Clamped middle temperature [°C]
    _fT3Clamp   : REAL;   // 钳制后的出口温度 [°C] / Clamped outlet temperature [°C]
    _fLocalRaw  : REAL;   // 未饱和的插值温度 [°C] / Raw interpolated temperature [°C]
    _fGradRaw   : REAL;   // 未饱和的梯度 [°C/m] / Raw gradient [°C/m]
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG      : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_TWO      : REAL := 2.0;       // 段中心除数 [-] / Zone centre divisor [-]
    DL_HALF     : REAL := 0.5;       // 插值区间归一化中点 [-] / Interpolation midpoint [-]
    DL_T_LO_C   : REAL := 0.0;       // 温度量程下限 [°C] / Temperature range low [°C]
    DL_T_HI_C   : REAL := 1200.0;    // 温度量程上限 [°C] / Temperature range high [°C]
    DL_ZONE_MAX : INT  := 1000;      // 段号钳制上限（防组态异常）[-] / Zone index ceiling [-]
END_VAR

(* —— 段 1：非有限值闸（R19：五路实值入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fT1C > -DL_BIG AND fT1C < DL_BIG)
   OR NOT (fT2C > -DL_BIG AND fT2C < DL_BIG)
   OR NOT (fT3C > -DL_BIG AND fT3C < DL_BIG)
   OR NOT (fZoneLenM > -DL_BIG AND fZoneLenM < DL_BIG)
   OR NOT (fZoneSpanM > -DL_BIG AND fZoneSpanM < DL_BIG) THEN
    fLocalC := 0.0;                         // 输出强制 0.0 / Output forced to zero
    fGradCpm := 0.0;                        // 梯度强制 0.0 / Gradient forced to zero
    iZoneClamp := 1;                        // 段号退到 1 / Zone index falls back to 1
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_FloatBathTempProfileCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：总长与段长都是插值基准） —— *)
IF (ABS(fZoneLenM) <= DL_EPS) OR (ABS(fZoneSpanM) <= DL_EPS) THEN
    fLocalC := 0.0;                         // 输出强制 0.0 / Output forced to zero
    fGradCpm := 0.0;                        // 梯度强制 0.0 / Gradient forced to zero
    iZoneClamp := 1;                        // 段号退到 1 / Zone index falls back to 1
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_FloatBathTempProfileCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（长度不可为负） —— *)
IF (fZoneLenM < 0.0) OR (fZoneSpanM < 0.0) THEN
    fLocalC := 0.0;                         // 输出强制 0.0 / Output forced to zero
    fGradCpm := 0.0;                        // 梯度强制 0.0 / Gradient forced to zero
    iZoneClamp := 1;                        // 段号退到 1 / Zone index falls back to 1
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_FloatBathTempProfileCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：段号钳制（1 ~ N 闭区间，N 由总长/段长取整，至少 1 段） —— *)
_iZoneCount := REAL_TO_INT(fZoneLenM / fZoneSpanM);               // 总段数 [-]（向下取整）
_iZoneCount := MAX(1, MIN(_iZoneCount, DL_ZONE_MAX));             // 段数钳 1..1000
iZoneClamp := MAX(1, MIN(iZone, _iZoneCount));                    // 段号钳 1..N

(* —— 段 5：位置归一化（R22 方向自核：段中心位置从 0 起算，除总长得 0..1） —— *)
_fPosM := (INT_TO_REAL(iZoneClamp - 1) * fZoneSpanM) + (fZoneSpanM / DL_TWO);   // 段中心 [m]
_fU := LIMIT(0.0, _fPosM / fZoneLenM, 1.0);                       // 归一化位置 [-]

(* —— 段 6：温度量程钳制 —— *)
_fT1Clamp := LIMIT(DL_T_LO_C, fT1C, DL_T_HI_C);                   // 入口温度钳 [°C]
_fT2Clamp := LIMIT(DL_T_LO_C, fT2C, DL_T_HI_C);                   // 中段温度钳 [°C]
_fT3Clamp := LIMIT(DL_T_LO_C, fT3C, DL_T_HI_C);                   // 出口温度钳 [°C]

(* —— 段 7：三段折线插值与区间梯度（u <= 0.5 属前区间，否则属后区间） —— *)
_fSegLenM := fZoneLenM * DL_HALF;                                 // 单区间物理长度 [m]
IF _iZoneCount <= 1 THEN
    _fLocalRaw := _fT1Clamp;                                      // 单段退化：取入口温度
    _fGradRaw := 0.0;                                             // 单段无梯度
ELSIF _fU <= DL_HALF THEN
    _fLocalRaw := _fT1Clamp + (_fT2Clamp - _fT1Clamp) * (_fU / DL_HALF);         // 前区间插值 [°C]
    _fGradRaw := (_fT2Clamp - _fT1Clamp) / _fSegLenM;                            // 前区间梯度 [°C/m]
ELSE
    _fLocalRaw := _fT2Clamp + (_fT3Clamp - _fT2Clamp) * ((_fU - DL_HALF) / DL_HALF);   // 后区间插值
    _fGradRaw := (_fT3Clamp - _fT2Clamp) / _fSegLenM;                            // 后区间梯度 [°C/m]
END_IF

(* —— 段 8：输出单点写盘（饱和钳制） —— *)
fLocalC := LIMIT(DL_T_LO_C, _fLocalRaw, DL_T_HI_C);               // 段温度 [°C]
fGradCpm := LIMIT(-DL_BIG, _fGradRaw, DL_BIG);                    // 梯度 [°C/m]

(* —— 段 9：有效位单点聚合（三个温度给定点在量程内） —— *)
xValid := (fT1C >= DL_T_LO_C) AND (fT1C <= DL_T_HI_C)
          AND (fT2C >= DL_T_LO_C) AND (fT2C <= DL_T_HI_C)
          AND (fT3C >= DL_T_LO_C) AND (fT3C <= DL_T_HI_C);
FC_DL_FloatBathTempProfileCalc := xValid;                         // 返回码：TRUE = 计算可信

END_FUNCTION
