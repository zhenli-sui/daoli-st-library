(*
  Name: FC_DL_AirLeakRateCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 停机压降法测泄漏流量：全厂停机（无生产用气）后记录储气罐从 P1 降到 P2 的时长，
           罐内减少的「常压自由空气容积」= 罐容积 × (P1 − P2) / 大气压，
           折算到每分钟即泄漏流量：fLeakM3min = V · (P1 − P2) / P_atm · 60 / t。
           泄漏流量的方向是「从罐内流向大气」，故压降为 P1 − P2（前减后），不可反写。
        2) 泄漏占比：fLeakPct = 泄漏流量 / 平均用气需求 × 100，
           分母是生产期实测平均需求（同量纲 m3/min），用来判断泄漏占总耗气的份额；
           该口径对应「改造泄漏可节省的最大气量比例」，不是压缩机能耗占比。
  边界条件：1) 非有限值闸：五路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fTimeS) > DL_EPS 与 ABS(fAvgDemandM3min) > DL_EPS 都必须通过；
           测量时长为 0 则泄漏流量发散，平均需求为 0 则占比发散（无生产工况无法归一）。
        3) 分母零闸补充：ABS(DL_P_ATM_BAR) 为常量不可能为零，但仍以常量直接使用（编译期确定），
           不引入运行期除法风险。
        4) 压降方向闸：fP1Bar 必须 > fP2Bar，否则压降为负（记录顺序颠倒或罐被充气），判无效；
           压降为 0 属合法但无信息，输出 0 且判无效（无压降无法算出泄漏）。
        5) 负值闸：罐容积、压力、时长、需求任一为负判无效（不取绝对值掩盖反向）。
        6) 饱和钳制：泄漏流量钳 0 ~ DL_LEAK_MAX(10000 m3/min)，占比钳 0 ~ 100 %，
           防极短测量时长把泄漏值放大到无意义量级。
  量纲自证：V·ΔP/P_atm = m3 × bar / bar = m3；× 60 [s/min] / t[s] → m3/min；
           fLeakPct = (m3/min) / (m3/min) × 100 = 无因次百分数 [%]，分母与分子同量纲。
*)

FUNCTION FC_DL_AirLeakRateCalc : BOOL
VAR_INPUT
    fTankM3          : REAL;   // 储气罐有效容积 [m3] / Effective receiver volume [m3]
    fP1Bar           : REAL;   // 起始罐压 [bar] / Initial receiver pressure [bar]
    fP2Bar           : REAL;   // 结束罐压 [bar] / Final receiver pressure [bar]
    fTimeS           : REAL;   // 测量时长 [s] / Measurement duration [s]
    fAvgDemandM3min  : REAL;   // 生产期平均用气需求 [m3/min] / Average production air demand [m3/min]
END_VAR
VAR_OUTPUT
    fLeakM3min       : REAL;   // 泄漏流量 [m3/min] / Leakage flow [m3/min]
    fLeakPct         : REAL;   // 泄漏占平均需求比例 [%] / Leakage share of average demand [%]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDropBar        : REAL;   // 测量期间压降 [bar] / Pressure drop during test [bar]
    _fFreeVolumeM3   : REAL;   // 压降对应的常压自由空气容积 [m3] / Free air volume from drop [m3]
    _fLeakRawM3min   : REAL;   // 未饱和的泄漏流量 [m3/min] / Raw leakage flow [m3/min]
    _fLeakPctRaw     : REAL;   // 未饱和的泄漏占比 [%] / Raw leakage share [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_P_ATM_BAR     : REAL := 1.01325;   // 标准大气压 [bar] / Standard atmospheric pressure [bar]
    DL_S_PER_MIN     : REAL := 60.0;      // min → s 换算因子 [s/min] / Minute to second factor [s/min]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_LEAK_MAX      : REAL := 10000.0;   // 泄漏流量饱和上限 [m3/min] / Leakage saturation ceiling [m3/min]
    DL_DROP_MIN      : REAL := 1.0E-6;    // 压降有效下限 [bar] / Minimum meaningful pressure drop [bar]
END_VAR

(* —— 段 1：非有限值闸（R19：五路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fTankM3 > -DL_BIG AND fTankM3 < DL_BIG)
   OR NOT (fP1Bar > -DL_BIG AND fP1Bar < DL_BIG)
   OR NOT (fP2Bar > -DL_BIG AND fP2Bar < DL_BIG)
   OR NOT (fTimeS > -DL_BIG AND fTimeS < DL_BIG)
   OR NOT (fAvgDemandM3min > -DL_BIG AND fAvgDemandM3min < DL_BIG) THEN
    fLeakM3min := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fLeakPct := 0.0;                        // 占比强制 0.0 / Share forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirLeakRateCalc := FALSE;         // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：测量时长与平均需求两个分母逐一验证） —— *)
IF (ABS(fTimeS) <= DL_EPS) OR (ABS(fAvgDemandM3min) <= DL_EPS) THEN
    fLeakM3min := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fLeakPct := 0.0;                        // 占比强制 0.0 / Share forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirLeakRateCalc := FALSE;         // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸与压降方向闸（R22：压降是前减后，方向颠倒即判无效） —— *)
_fDropBar := fP1Bar - fP2Bar;               // 测量期间压降（前 − 后）[bar]
IF (fTankM3 < 0.0) OR (fTimeS < 0.0) OR (fAvgDemandM3min < 0.0) OR (_fDropBar < 0.0) THEN
    fLeakM3min := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fLeakPct := 0.0;                        // 占比强制 0.0 / Share forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirLeakRateCalc := FALSE;         // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：泄漏流量主算式（压降 → 常压容积 → 每分钟） —— *)
_fFreeVolumeM3 := fTankM3 * _fDropBar / DL_P_ATM_BAR;             // 常压自由空气容积 [m3]
_fLeakRawM3min := _fFreeVolumeM3 * DL_S_PER_MIN / fTimeS;         // 泄漏流量 [m3/min]

(* —— 段 5：泄漏占比（分母为平均需求，同量纲归一化） —— *)
_fLeakPctRaw := _fLeakRawM3min / fAvgDemandM3min * DL_PCT;        // 占比 [%]

(* —— 段 6：有效位单点聚合（压降必须有效，无压降无法算泄漏） —— *)
xValid := (_fDropBar > DL_DROP_MIN)                               // 压降有效
          AND (fTankM3 > 0.0)                                     // 罐容积为正
          AND (fTimeS > DL_EPS)                                   // 测量时长为正
          AND (fAvgDemandM3min > DL_EPS);                         // 平均需求为正（占比可归一）

(* —— 段 7：输出单点写盘（饱和钳制） —— *)
fLeakM3min := LIMIT(0.0, _fLeakRawM3min, DL_LEAK_MAX);            // 泄漏流量 [m3/min]
fLeakPct := LIMIT(0.0, _fLeakPctRaw, DL_PCT);                     // 泄漏占比钳 0..100 [%]
FC_DL_AirLeakRateCalc := xValid;                                  // 返回码：TRUE = 计算可信

END_FUNCTION
