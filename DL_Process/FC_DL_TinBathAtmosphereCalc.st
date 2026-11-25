(*
  Name: FC_DL_TinBathAtmosphereCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 锡槽保护气 H2 配比按「氢耗氧化学计量」估算。漏入锡槽的空气带入氧气，
           氧气与氢按 2H2 + O2 → 2H2O 反应，故 1 体积氧气需要 2 体积氢气中和。
           逐步为：
             氧带入量 = 漏入空气量 × 空气中氧体积分数(0.21)
             需中和氧量 = 氧带入量 − 允许残氧量（目标 ppm 折算为体积流量）
             氢需求 = 2 × 需中和氧量 × 过量系数
             氢配比 = 氢需求 / 保护气总流量 × 100
           允许残氧量按「目标 ppm × 总流量 × 1e-6」折算，使得目标越严格所需氢越多，方向正确。
        2) 过量系数 DL_HSF(1.5) 用于覆盖反应不完全与局部湍流死区，是安全冗余而非效率系数。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fTotalFlowM3h) > DL_EPS 才允许算配比（总流量为 0 时配比无定义）。
        3) 负值闸：漏入量、目标氧含量、总流量任一为负判无效（不取绝对值掩盖反向）。
        4) 配比饱和钳制：H2 配比钳 0 ~ DL_H2_MAX(10 %)。上限的依据是保护气进入爆炸下限区间
           （H2 在空气中的爆炸下限约 4 %，但锡槽内为氮基气氛且需维持正压，工艺上按 10 % 上限组态），
           超过上限必须由安全联锁处理，本件只做钳制与无效标记，不做安全切断。
        5) 需求为负（残氧目标高于带入氧）时氢需求钳 0，属合法工况（无需加氢），不判无效。
        6) 饱和钳制：氢流量钳 0 ~ DL_H2_FLOW_MAX(10000 m3/h)，防溢出。
  量纲自证：氧带入量 = (m3/h) × [-] = m3/h；残氧量 = ppm × (m3/h) × 1E-6 = m3/h；
           需中和氧量 = (m3/h) − (m3/h) = m3/h，减法同量纲；
           氢需求 = [-] × (m3/h) × [-] = m3/h（化学计量比与过量系数均为无因次）；
           配比 = (m3/h) / (m3/h) × 100 = 无因次 [%]，分母与分子同量纲。
*)

FUNCTION FC_DL_TinBathAtmosphereCalc : BOOL
VAR_INPUT
    fO2TargetPpm   : REAL;   // 目标残氧含量 [ppm] / Target residual oxygen [ppm]
    fLeakM3h       : REAL;   // 漏入锡槽的空气量 [m3/h] / Air leakage into tin bath [m3/h]
    fTotalFlowM3h  : REAL;   // 保护气总流量 [m3/h] / Total protective gas flow [m3/h]
END_VAR
VAR_OUTPUT
    fH2Pct         : REAL;   // 氢气体积配比 [%] / Hydrogen volume ratio [%]
    fFlowM3h       : REAL;   // 氢气需求体积流量 [m3/h] / Hydrogen required volumetric flow [m3/h]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fO2IngressM3h : REAL;   // 漏入氧气量 [m3/h] / Oxygen ingress [m3/h]
    _fO2AllowM3h   : REAL;   // 允许残氧量 [m3/h] / Allowable residual oxygen [m3/h]
    _fO2NeedM3h    : REAL;   // 需中和氧量 [m3/h] / Oxygen to be neutralized [m3/h]
    _fH2NeedM3h    : REAL;   // 氢需求（含过量系数）[m3/h] / Hydrogen demand with safety factor [m3/h]
    _fPctRaw       : REAL;   // 未饱和的配比 [%] / Raw ratio [%]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT         : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_O2_AIR_FRAC : REAL := 0.21;      // 空气中氧体积分数 [-] / Oxygen volume fraction in air [-]
    DL_H2_STOICH   : REAL := 2.0;       // 2H2 + O2 化学计量比 [-] / Hydrogen to oxygen stoichiometry [-]
    DL_PPM_FRAC    : REAL := 1.0E-6;    // ppm → 体积分数换算因子 [-] / ppm to volume fraction factor [-]
    DL_HSF         : REAL := 1.5;       // 氢过量系数（安全冗余）[-] / Hydrogen excess factor [-]
    DL_H2_MAX      : REAL := 10.0;      // 氢配比饱和上限 [%] / Hydrogen ratio saturation ceiling [%]
    DL_H2_FLOW_MAX : REAL := 10000.0;   // 氢流量饱和上限 [m3/h] / Hydrogen flow saturation ceiling [m3/h]
END_VAR

(* —— 段 1：非有限值闸（R19：三路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fO2TargetPpm > -DL_BIG AND fO2TargetPpm < DL_BIG)
   OR NOT (fLeakM3h > -DL_BIG AND fLeakM3h < DL_BIG)
   OR NOT (fTotalFlowM3h > -DL_BIG AND fTotalFlowM3h < DL_BIG) THEN
    fH2Pct := 0.0;                          // 输出强制 0.0 / Output forced to zero
    fFlowM3h := 0.0;                        // 氢流量强制 0.0 / Hydrogen flow forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TinBathAtmosphereCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：总流量是配比分母） —— *)
IF ABS(fTotalFlowM3h) <= DL_EPS THEN
    fH2Pct := 0.0;                          // 输出强制 0.0 / Output forced to zero
    fFlowM3h := 0.0;                        // 氢流量强制 0.0 / Hydrogen flow forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TinBathAtmosphereCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（漏入量、目标氧含量、总流量均不可为负） —— *)
IF (fO2TargetPpm < 0.0) OR (fLeakM3h < 0.0) OR (fTotalFlowM3h < 0.0) THEN
    fH2Pct := 0.0;                          // 输出强制 0.0 / Output forced to zero
    fFlowM3h := 0.0;                        // 氢流量强制 0.0 / Hydrogen flow forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TinBathAtmosphereCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：氧衡算（R22 方向自核：漏入氧减去允许残氧，才是需要中和的量） —— *)
_fO2IngressM3h := fLeakM3h * DL_O2_AIR_FRAC;                      // 漏入氧气 [m3/h]
_fO2AllowM3h := fO2TargetPpm * DL_PPM_FRAC * fTotalFlowM3h;       // 允许残氧 [m3/h]
_fO2NeedM3h := MAX(0.0, _fO2IngressM3h - _fO2AllowM3h);           // 需中和氧量 [m3/h]（负值钳 0）

(* —— 段 5：氢需求与配比（化学计量比 2、过量系数 1.5 均为无因次） —— *)
_fH2NeedM3h := DL_H2_STOICH * _fO2NeedM3h * DL_HSF;               // 氢需求 [m3/h]
_fPctRaw := _fH2NeedM3h / fTotalFlowM3h * DL_PCT;                 // 氢配比 [%]

(* —— 段 6：输出单点写盘（饱和钳制） —— *)
fFlowM3h := LIMIT(0.0, _fH2NeedM3h, DL_H2_FLOW_MAX);              // 氢流量 [m3/h]
fH2Pct := LIMIT(0.0, _fPctRaw, DL_H2_MAX);                        // 氢配比 [%]

(* —— 段 7：有效位单点聚合（分母为正 + 入参非负） —— *)
xValid := (fTotalFlowM3h > DL_EPS)                                // 总流量为正
          AND (fO2TargetPpm >= 0.0)                               // 目标残氧非负
          AND (fLeakM3h >= 0.0);                                  // 漏入量非负
FC_DL_TinBathAtmosphereCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
