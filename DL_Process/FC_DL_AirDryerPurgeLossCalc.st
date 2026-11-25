(*
  Name: FC_DL_AirDryerPurgeLossCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 吸附式干燥机再生耗气量按「额定处理流量 × 再生耗气率」计算：
           fLossM3min = fRatedFlowM3min × fPurgePct / 100。再生耗气是无谓损耗，
           它同时意味着上游空压机要多产这部分气，故必须计入系统能耗。
        2) 年运行成本按「损耗气量 → 等效电耗 → 电费」三段折算：
             等效比功率 = 额定轴功率 / 额定处理流量，量纲 kW/(m3/min)；
             年电耗[kWh] = 损耗气量[m3/min] × 比功率[kW/(m3/min)] × 年运行小时[h]；
             年成本 = 年电耗 × 电价。注意比功率已按「每分钟气量」定义，
             故乘年小时数即可，不得再乘 60 做时间换算（这是本件最容易写错的一处方向问题）。
  边界条件：1) 非有限值闸：五路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fRatedFlowM3min) > DL_EPS 才能得到比功率，
           额定流量为 0 表示铭牌未录入，判无效而不是输出无意义成本。
        3) 负值闸：额定流量、再生耗气率、年运行小时、电价、额定功率任一为负判无效
           （再生耗气率为负会得出「负成本」，属组态错误，不取绝对值掩盖）。
        4) 量程校验：再生耗气率必须落在 0 ~ 100 %（超过 100 % 意味着再生耗气大于处理量，
           干燥机不可能工作），年运行小时钳 0 ~ 8760 h，电价钳 0 ~ DL_PRICE_MAX。
        5) 饱和钳制：耗气量钳 0 ~ DL_LOSS_MAX，年成本钳 0 ~ DL_COST_MAX，防溢出。
  量纲自证：fLossM3min = (m3/min) × (%/100) = m3/min；
           比功率 = kW / (m3/min) = kW·min/m3；
           年电耗 = (m3/min) × (kW·min/m3) × h = kW·h，量纲闭合（min 与 min 对消）；
           年成本 = kWh × (货币/kWh) = 货币，三项内部量纲一致，未出现 kW/kW 去加温度的混算。
*)

FUNCTION FC_DL_AirDryerPurgeLossCalc : BOOL
VAR_INPUT
    fRatedFlowM3min : REAL;   // 干燥机额定处理流量 [m3/min] / Dryer rated flow [m3/min]
    fPurgePct       : REAL;   // 再生耗气率 [%] / Regeneration purge ratio [%]
    fHoursYear      : REAL;   // 年运行小时数 [h] / Annual operating hours [h]
    fPricePerKWh    : REAL;   // 电价 [货币/kWh] / Electricity price [currency/kWh]
    fRatedKW        : REAL;   // 空压机额定轴功率 [kW] / Compressor rated shaft power [kW]
END_VAR
VAR_OUTPUT
    fLossM3min      : REAL;   // 再生耗气量 [m3/min] / Regeneration purge loss [m3/min]
    fSpecKW         : REAL;   // 等效比功率 [kW/(m3/min)] / Equivalent specific power [kW/(m3/min)]
    fCostYear       : REAL;   // 年运行成本 [货币] / Annual operating cost [currency]
    xValid          : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fSpecRaw       : REAL;   // 未饱和的等效比功率 [kW/(m3/min)] / Raw specific power
    _fPurgeRatio    : REAL;   // 归一化再生耗气率 [-] / Normalized purge ratio [-]
    _fLossRaw       : REAL;   // 未饱和的耗气量 [m3/min] / Raw purge loss [m3/min]
    _fHoursClamp    : REAL;   // 钳制后的年运行小时 [h] / Clamped annual hours [h]
    _fCostRaw       : REAL;   // 未饱和的年成本 [货币] / Raw annual cost [currency]
END_VAR
VAR CONSTANT
    DL_EPS          : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG          : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT          : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_HOURS_YEAR   : REAL := 8760.0;    // 全年小时数上限 [h] / Hours per year upper bound [h]
    DL_PRICE_MAX    : REAL := 100.0;     // 电价量程上限 [货币/kWh] / Electricity price ceiling
    DL_LOSS_MAX     : REAL := 10000.0;   // 耗气量饱和上限 [m3/min] / Purge loss saturation ceiling [m3/min]
    DL_COST_MAX     : REAL := 1.0E9;     // 年成本饱和上限 [货币] / Annual cost saturation ceiling
END_VAR

(* —— 段 1：非有限值闸（R19：五路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fRatedFlowM3min > -DL_BIG AND fRatedFlowM3min < DL_BIG)
   OR NOT (fPurgePct > -DL_BIG AND fPurgePct < DL_BIG)
   OR NOT (fHoursYear > -DL_BIG AND fHoursYear < DL_BIG)
   OR NOT (fPricePerKWh > -DL_BIG AND fPricePerKWh < DL_BIG)
   OR NOT (fRatedKW > -DL_BIG AND fRatedKW < DL_BIG) THEN
    fLossM3min := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fSpecKW := 0.0;                         // 比功率强制 0.0 / Specific power forced to zero
    fCostYear := 0.0;                       // 成本强制 0.0 / Cost forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirDryerPurgeLossCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：额定流量是比功率的分母，必须先过 ABS 闸） —— *)
IF ABS(fRatedFlowM3min) <= DL_EPS THEN
    fLossM3min := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fSpecKW := 0.0;                         // 比功率强制 0.0 / Specific power forced to zero
    fCostYear := 0.0;                       // 成本强制 0.0 / Cost forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirDryerPurgeLossCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（负耗气率会得出负成本，属组态错误） —— *)
IF (fRatedFlowM3min < 0.0) OR (fPurgePct < 0.0) OR (fHoursYear < 0.0)
   OR (fPricePerKWh < 0.0) OR (fRatedKW < 0.0) THEN
    fLossM3min := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fSpecKW := 0.0;                         // 比功率强制 0.0 / Specific power forced to zero
    fCostYear := 0.0;                       // 成本强制 0.0 / Cost forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirDryerPurgeLossCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：等效比功率（R22 方向自核：额定功率在分子，额定流量在分母） —— *)
_fSpecRaw := fRatedKW / fRatedFlowM3min;                          // [kW/(m3/min)]

(* —— 段 5：再生耗气量与年成本（比功率已按每分钟定义，故不再乘 60） —— *)
_fPurgeRatio := fPurgePct / DL_PCT;                               // 归一化 [-] 
_fLossRaw := fRatedFlowM3min * _fPurgeRatio;                      // 耗气量 [m3/min]
_fHoursClamp := LIMIT(0.0, fHoursYear, DL_HOURS_YEAR);            // 年小时钳制 [h]
_fCostRaw := _fLossRaw * _fSpecRaw * _fHoursClamp * fPricePerKWh; // 年成本 [货币]

(* —— 段 6：输出单点写盘（饱和钳制） —— *)
fSpecKW := LIMIT(0.0, _fSpecRaw, DL_BIG);                         // 比功率 [kW/(m3/min)]
fLossM3min := LIMIT(0.0, _fLossRaw, DL_LOSS_MAX);                 // 耗气量 [m3/min]
fCostYear := LIMIT(0.0, _fCostRaw, DL_COST_MAX);                  // 年成本 [货币]

(* —— 段 7：有效位单点聚合（耗气率窄闸 + 电价量程） —— *)
xValid := (fRatedFlowM3min > DL_EPS)                              // 额定流量为正
          AND (fPurgePct <= DL_PCT)                               // 耗气率不超 100 %
          AND (fHoursYear <= DL_HOURS_YEAR)                       // 年小时不超 8760
          AND (fPricePerKWh <= DL_PRICE_MAX)                      // 电价在量程内
          AND (fRatedKW >= 0.0);                                  // 额定功率非负
FC_DL_AirDryerPurgeLossCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
