(*
  Name: FC_DL_AirReceiverSizingCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 储气罐最小容积按「压降允许量 × 切换间隔」守恒反算：在切换间隔内系统持续用气，
           罐内允许压降所释放的常压自由空气容积必须不小于同期的用气量，即
             V_tank · ΔP_allow / P_atm = Q_demand · (t_interval / 60)
           解得 fTankMinM3 = Q · (t/60) · P_atm / ΔP_allow。
           该式的工程含义：允许压降越小、切换间隔越长，所需罐容积越大（两者均为分母/正相关）。
        2) 用于空压机站房的罐容选型校核，或对既有罐容做「当前切换间隔是否可行」的反算。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fTankMinM3 强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fAllowDropBar) > DL_EPS（允许压降为 0 则罐容趋于无穷，数学上无解）与
           ABS(fAtmBar) > DL_EPS 都必须通过，否则判无效。
        3) 负值闸：用气需求、允许压降、切换间隔、大气压任一为负判无效（不取绝对值掩盖）。
        4) 零值语义：需求为 0 或间隔为 0 时所需罐容为 0，属合法工况（无用气/瞬时切换），
           不判无效，仅输出 0；但间隔为 0 时输出 0 需下游自行判别是否具备选型意义。
        5) 饱和钳制：罐容结果钳 0 ~ DL_V_MAX(10000 m3)，防允许压降极小时反算值溢出。
  量纲自证：Q·(t/60) = (m3/min) × (min) = m3（自由空气容积）；
           再乘 P_atm/ΔP_allow = (bar/bar) = 无因次 → 结果 m3，量纲闭合；
           其中 60 为 [s/min] 时间换算因子，(fIntervalS/60) 已把秒折算为分钟。
*)

FUNCTION FC_DL_AirReceiverSizingCalc : BOOL
VAR_INPUT
    fDemandM3min    : REAL;   // 平均用气需求 [m3/min] / Average air demand [m3/min]
    fAllowDropBar   : REAL;   // 允许压降 [bar] / Allowable pressure drop [bar]
    fIntervalS      : REAL;   // 切换/备用投入间隔 [s] / Switchover interval [s]
    fAtmBar         : REAL;   // 当地大气压 [bar] / Local atmospheric pressure [bar]
END_VAR
VAR_OUTPUT
    fTankMinM3      : REAL;   // 最小储气罐容积 [m3] / Minimum receiver volume [m3]
    xValid          : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fIntervalMin   : REAL;   // 折算后的间隔 [min] / Interval in minutes [min]
    _fFreeAirNeedM3 : REAL;   // 间隔内所需自由空气容积 [m3] / Free air volume needed [m3]
    _fTankRawM3     : REAL;   // 未饱和的罐容反算值 [m3] / Raw receiver volume [m3]
END_VAR
VAR CONSTANT
    DL_EPS          : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG          : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_S_PER_MIN    : REAL := 60.0;      // min → s 换算因子 [s/min] / Minute to second factor [s/min]
    DL_V_MAX        : REAL := 10000.0;   // 罐容饱和钳制上限 [m3] / Receiver volume saturation ceiling [m3]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fDemandM3min > -DL_BIG AND fDemandM3min < DL_BIG)
   OR NOT (fAllowDropBar > -DL_BIG AND fAllowDropBar < DL_BIG)
   OR NOT (fIntervalS > -DL_BIG AND fIntervalS < DL_BIG)
   OR NOT (fAtmBar > -DL_BIG AND fAtmBar < DL_BIG) THEN
    fTankMinM3 := 0.0;                      // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirReceiverSizingCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：允许压降为 0 则罐容无解，必须前置拦截） —— *)
IF (ABS(fAllowDropBar) <= DL_EPS) OR (ABS(fAtmBar) <= DL_EPS) THEN
    fTankMinM3 := 0.0;                      // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirReceiverSizingCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（需求/压降/间隔/大气压均不可为负） —— *)
IF (fDemandM3min < 0.0) OR (fAllowDropBar < 0.0) OR (fIntervalS < 0.0) OR (fAtmBar < 0.0) THEN
    fTankMinM3 := 0.0;                      // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirReceiverSizingCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：主算式（R22 方向自核：需求与间隔在分子，允许压降在分母，方向不可反） —— *)
_fIntervalMin := fIntervalS / DL_S_PER_MIN;                       // 间隔折算为分钟 [min]
_fFreeAirNeedM3 := fDemandM3min * _fIntervalMin;                  // 所需自由空气 [m3]
_fTankRawM3 := _fFreeAirNeedM3 * fAtmBar / fAllowDropBar;         // 最小罐容 [m3]

(* —— 段 5：有效位单点聚合（分母为正 + 入参非负） —— *)
xValid := (fAllowDropBar > DL_EPS)                                // 允许压降为正
          AND (fAtmBar > DL_EPS)                                  // 大气压为正
          AND (fDemandM3min >= 0.0)                               // 需求非负
          AND (fIntervalS >= 0.0);                                // 间隔非负

(* —— 段 6：输出单点写盘（饱和钳制，防极小压降导致溢出） —— *)
fTankMinM3 := LIMIT(0.0, _fTankRawM3, DL_V_MAX);                  // 最小罐容 [m3]
FC_DL_AirReceiverSizingCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
