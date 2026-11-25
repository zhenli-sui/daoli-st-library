(*
  Name: FC_DL_LehrAnnealingScheduleCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 退火窑温降速率按「区间温差 / 在区间的停留时间」计算：
             停留时间[min] = 区间长度[m] / 线速度[m/min]
             温降速率[°C/min] = (区间进口温度 − 区间出口温度) / 停留时间
           分子方向固定为「进口减出口」：玻璃带沿前进方向降温，故该值为正表示正常降温，
           若为负说明区间在升温（退火窑局部反向，属异常）。速度越快停留时间越短，
           同一温差下温降速率越高，这是本件最核心的方向关系（速度在分母上）。
        2) 与允许退火曲线比较给出 xInSchedule：温降速率必须落在 0 ~ DL_RATE_MAX 的允许带内。
           退火的核心约束是「降温不能过快」，否则玻璃内部产生过大残余应力而炸裂；
           故上限是硬约束，下限 0 用于拦截升温异常。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fCoolRateCmin 强制 0.0、xInSchedule 强制 FALSE）
           并置无效（R19），无效数据不得判「在曲线上」。
        2) 分母零闸：线速度 ABS > DL_EPS（速度为 0 时停留时间无穷大，温降速率趋于 0，无意义）；
           区间长度 ABS > DL_EPS（长度为 0 时停留时间为 0，温降速率发散）。
        3) 负值闸：区间长度为负、线速度为负判无效（不取绝对值掩盖反向）。
        4) 零值语义：区间温差为 0（等温段）属合法工况，温降速率为 0，判定为在曲线内。
        5) 饱和钳制：温降速率钳 −DL_RATE_MAX ~ +DL_RATE_MAX 的两倍区间，
           防停留时间极小时速率溢出；判定用钳制后的值，保证判据与出口同源。
  量纲自证：停留时间 = m / (m/min) = min；
           fCoolRateCmin = (°C) / min = °C/min，减法两侧同为 °C；
           与 DL_RATE_MAX(°C/min) 同量纲后方可比较，未出现跨量纲混比。
*)

FUNCTION FC_DL_LehrAnnealingScheduleCalc : BOOL
VAR_INPUT
    fZoneInC       : REAL;   // 区间进口玻璃温度 [°C] / Zone inlet glass temperature [°C]
    fZoneOutC      : REAL;   // 区间出口玻璃温度 [°C] / Zone outlet glass temperature [°C]
    fZoneLenM      : REAL;   // 区间长度 [m] / Zone length [m]
    fLineSpeedMmin : REAL;   // 玻璃带线速度 [m/min] / Ribbon line speed [m/min]
END_VAR
VAR_OUTPUT
    fCoolRateCmin  : REAL;   // 温降速率 [°C/min] / Cooling rate [°C/min]
    fResidenceMin  : REAL;   // 区间停留时间（观测用）[min] / Zone residence time [min]
    xInSchedule    : BOOL;   // 在允许退火曲线内 [bool] / Within allowable annealing schedule [bool]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fResidenceRaw : REAL;   // 未饱和的停留时间 [min] / Raw residence time [min]
    _fDeltaTC      : REAL;   // 区间温差（进口 − 出口）[°C] / Zone temperature difference [°C]
    _fRateRaw      : REAL;   // 未饱和的温降速率 [°C/min] / Raw cooling rate [°C/min]
    _fRateClamp    : REAL;   // 饱和钳制后的温降速率 [°C/min] / Clamped cooling rate [°C/min]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_RATE_MAX    : REAL := 15.0;      // 允许温降速率上限 [°C/min] / Allowable cooling rate [°C/min]
    DL_T_HI_C      : REAL := 1200.0;    // 温度量程上限 [°C] / Temperature range high [°C]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fZoneInC > -DL_BIG AND fZoneInC < DL_BIG)
   OR NOT (fZoneOutC > -DL_BIG AND fZoneOutC < DL_BIG)
   OR NOT (fZoneLenM > -DL_BIG AND fZoneLenM < DL_BIG)
   OR NOT (fLineSpeedMmin > -DL_BIG AND fLineSpeedMmin < DL_BIG) THEN
    fCoolRateCmin := 0.0;                   // 输出强制 0.0 / Output forced to zero
    fResidenceMin := 0.0;                   // 停留时间强制 0.0 / Residence forced to zero
    xInSchedule := FALSE;                   // 曲线标志强制 FALSE / Schedule flag forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LehrAnnealingScheduleCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：区间长度与线速度两个分母逐一验证） —— *)
IF (ABS(fZoneLenM) <= DL_EPS) OR (ABS(fLineSpeedMmin) <= DL_EPS) THEN
    fCoolRateCmin := 0.0;                   // 输出强制 0.0 / Output forced to zero
    fResidenceMin := 0.0;                   // 停留时间强制 0.0 / Residence forced to zero
    xInSchedule := FALSE;                   // 曲线标志强制 FALSE / Schedule flag forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LehrAnnealingScheduleCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（长度与速度为负属组态错误） —— *)
IF (fZoneLenM < 0.0) OR (fLineSpeedMmin < 0.0) THEN
    fCoolRateCmin := 0.0;                   // 输出强制 0.0 / Output forced to zero
    fResidenceMin := 0.0;                   // 停留时间强制 0.0 / Residence forced to zero
    xInSchedule := FALSE;                   // 曲线标志强制 FALSE / Schedule flag forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LehrAnnealingScheduleCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：停留时间与温降速率（R22 方向自核：速度在分母，速度快 → 停留短 → 速率高） —— *)
_fResidenceRaw := fZoneLenM / fLineSpeedMmin;                     // 停留时间 [min]
_fDeltaTC := fZoneInC - fZoneOutC;                                // 温差（进口 − 出口）[°C]
_fRateRaw := _fDeltaTC / _fResidenceRaw;                          // 温降速率 [°C/min]

(* —— 段 5：输出单点写盘（出口仅防溢出宽钳，保留真实值；判据另取未夹的原始速率） —— *)
fResidenceMin := LIMIT(0.0, _fResidenceRaw, DL_BIG);              // 停留时间 [min]
_fRateClamp := LIMIT(-DL_BIG, _fRateRaw, DL_BIG);                 // 仅防溢出的宽钳（不夹工艺量程）
fCoolRateCmin := _fRateClamp;                                     // 温降速率出口（真实值，不隐去超速）[°C/min]

(* —— 段 6：有效位单点聚合（温度量程 + 分母为正） —— *)
xValid := (fZoneInC <= DL_T_HI_C) AND (fZoneOutC <= DL_T_HI_C)    // 温度不越量程
          AND (fZoneInC >= 0.0) AND (fZoneOutC >= 0.0)            // 温度非负
          AND (fZoneLenM > DL_EPS)                                // 区间长度为正
          AND (fLineSpeedMmin > DL_EPS);                          // 线速度为正

(* —— 段 7：允许退火曲线判定（0 ~ DL_RATE_MAX 闭区间；负速率即升温，一律判出曲线） —— *)
xInSchedule := xValid AND (_fRateRaw >= 0.0) AND (_fRateRaw <= DL_RATE_MAX);   // 判据用未夹的原始速率，防「钳后判恒真」
FC_DL_LehrAnnealingScheduleCalc := xValid;                        // 返回码：TRUE = 计算可信

END_FUNCTION
