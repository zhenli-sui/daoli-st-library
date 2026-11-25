(*
  Name: FC_DL_AirNozzleConsumptionCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 单喷嘴耗气量按喷管临界（声速）流模型计算：当供气压力与背压之比超过临界比时，
           喉部达到声速，质量流量只取决于上游绝对压力而与背压无关，即
             m_dot = Cd · A · P_abs · sqrt(k/(R·T)) · (2/(k+1))^((k+1)/(2(k-1)))
           其中 k = 1.4、R = 287 J/(kg·K)、T = 293.15 K，合并为一个常数 DL_MDOT_K，
           故 m_dot = Cd · A · P_abs · DL_MDOT_K [kg/s]。
        2) 质量流量折算为常压自由空气体积流量：除以常压密度 DL_RHO_N(1.2046 kg/m3)，
           再乘 60 得 m3/min，即 fPerNozzleM3min。
        3) 总耗气量 = 单喷嘴耗气量 × 喷嘴数量 × 同时使用率 / 100。使用率是「同时吹气的比例」，
           按百分比归一化后乘入，方向为放大系数（使用率越高总耗气越大）。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：本件除数均为常量（DL_RHO_N、100.0），无常量零风险；
           但喷嘴口径与绝对压力的乘积必须为正，故对 fOrificeMm 做 DL_D_MIN_MM(0.1 mm) 下限钳制，
           防口径为 0 使耗气量恒为 0 而掩盖配置错误。
        3) 数量零闸：iCount < 0 判无效（负数量无物理意义）；iCount = 0 属合法（该支路无喷嘴），
           总耗气输出 0，不判无效。
        4) 使用率窄闸：fUsePct 必须落在 0 ~ 100 %，越域钳到边界并置无效；
           负使用率不取绝对值（会虚增耗气）。
        5) 饱和钳制：绝对压力按 DL_P_ABS_MAX(101 bar) 上限钳制，单喷嘴耗气钳 0 ~ 100 m3/min，
           总耗气钳 0 ~ 100000 m3/min，防数量与口径同时极端时溢出。
  量纲自证：A = m2，P_abs = Pa，DL_MDOT_K = kg/(s·m2·Pa)，故 m_dot = kg/s；
           除以 DL_RHO_N(kg/m3) → m3/s，乘 60 s/min → m3/min；
           总耗气 = (m3/min) × [-] × (%/100) = m3/min，百分比为无因次比例。
*)

FUNCTION FC_DL_AirNozzleConsumptionCalc : BOOL
VAR_INPUT
    fOrificeMm     : REAL;   // 喷嘴等效口径 [mm] / Nozzle equivalent orifice diameter [mm]
    fSupplyBar     : REAL;   // 供气表压 [bar] / Supply gauge pressure [bar]
    iCount         : INT;    // 喷嘴数量 [个] / Nozzle count [pcs]
    fUsePct        : REAL;   // 同时使用率 [%] / Simultaneous use ratio [%]
END_VAR
VAR_OUTPUT
    fPerNozzleM3min: REAL;   // 单喷嘴耗气量 [m3/min] / Consumption per nozzle [m3/min]
    fTotalM3min    : REAL;   // 总耗气量 [m3/min] / Total consumption [m3/min]
    fVelMps        : REAL;   // 喷嘴出口等效流速（观测用）[m/s] / Equivalent exit velocity [m/s]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDClampMm     : REAL;   // 钳制后的口径 [mm] / Clamped orifice diameter [mm]
    _fAreaM2       : REAL;   // 喷嘴截面积 [m2] / Nozzle cross-section area [m2]
    _fPAbsPa       : REAL;   // 供气绝对压力 [Pa] / Supply absolute pressure [Pa]
    _fMDotKgS      : REAL;   // 质量流量 [kg/s] / Mass flow rate [kg/s]
    _fPerRawM3min  : REAL;   // 未饱和的单喷嘴耗气量 [m3/min] / Raw per-nozzle consumption [m3/min]
    _fUseRatio     : REAL;   // 归一化使用率 [-] / Normalized use ratio [-]
    _fCountReal    : REAL;   // 数量的实数形态 [个] / Nozzle count as real [pcs]
    _fTotalRaw     : REAL;   // 未饱和的总耗气量 [m3/min] / Raw total consumption [m3/min]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT         : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_PI          : REAL := 3.14159265;   // 圆周率 [-] / Pi [-]
    DL_MM_PER_M    : REAL := 1000.0;    // m → mm 换算因子 [mm/m] / Metre to millimetre factor [mm/m]
    DL_S_PER_MIN   : REAL := 60.0;      // min → s 换算因子 [s/min] / Minute to second factor [s/min]
    DL_PA_PER_BAR  : REAL := 1.0E5;     // Pa → bar 换算因子 [Pa/bar] / Pascal to bar factor [Pa/bar]
    DL_P_ATM_BAR   : REAL := 1.01325;   // 标准大气压 [bar] / Standard atmospheric pressure [bar]
    DL_P_ABS_MAX   : REAL := 101.0;     // 绝对压力饱和上限 [bar] / Absolute pressure saturation ceiling [bar]
    DL_CD          : REAL := 0.65;      // 喷嘴流量系数 Cd [-] / Nozzle discharge coefficient Cd [-]
    DL_MDOT_K      : REAL := 2.362E-3;  // 临界流合并常数 [kg/(s·m2·Pa)] / Choked-flow lumped constant
    DL_RHO_N       : REAL := 1.2046;    // 常压 20 °C 空气密度 [kg/m3] / Air density at 20 degC 1 atm [kg/m3]
    DL_D_MIN_MM    : REAL := 0.10;      // 口径下限钳制值 [mm] / Orifice lower clamp [mm]
    DL_PER_MAX     : REAL := 100.0;     // 单喷嘴耗气饱和上限 [m3/min] / Per-nozzle saturation ceiling [m3/min]
    DL_TOT_MAX     : REAL := 100000.0;  // 总耗气饱和上限 [m3/min] / Total saturation ceiling [m3/min]
END_VAR

(* —— 段 1：非有限值闸（R19：三路实值入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fOrificeMm > -DL_BIG AND fOrificeMm < DL_BIG)
   OR NOT (fSupplyBar > -DL_BIG AND fSupplyBar < DL_BIG)
   OR NOT (fUsePct > -DL_BIG AND fUsePct < DL_BIG) THEN
    fPerNozzleM3min := 0.0;                 // 输出强制 0.0 / Output forced to zero
    fTotalM3min := 0.0;                     // 总耗气强制 0.0 / Total forced to zero
    fVelMps := 0.0;                         // 观测流速强制 0.0 / Velocity forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirNozzleConsumptionCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：组态闸（口径为正、数量非负、供压非负） —— *)
IF (fOrificeMm <= DL_EPS) OR (iCount < 0) OR (fSupplyBar < 0.0) THEN
    fPerNozzleM3min := 0.0;                 // 输出强制 0.0 / Output forced to zero
    fTotalM3min := 0.0;                     // 总耗气强制 0.0 / Total forced to zero
    fVelMps := 0.0;                         // 观测流速强制 0.0 / Velocity forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirNozzleConsumptionCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：几何与压力换算（口径下限钳制，绝对压上限钳制） —— *)
_fDClampMm := MAX(DL_D_MIN_MM, fOrificeMm);                        // 口径下限钳 [mm]
_fAreaM2 := DL_PI * (_fDClampMm / DL_MM_PER_M) * (_fDClampMm / DL_MM_PER_M) / 4.0;   // 截面积 [m2]
_fPAbsPa := LIMIT(0.0, fSupplyBar + DL_P_ATM_BAR, DL_P_ABS_MAX) * DL_PA_PER_BAR;      // 绝对压 [Pa]

(* —— 段 4：临界流质量流量（R22 方向自核：压力在分子，临界比已并入常数） —— *)
_fMDotKgS := DL_CD * _fAreaM2 * _fPAbsPa * DL_MDOT_K;              // 质量流量 [kg/s]

(* —— 段 5：质量流量 → 常压体积流量；再乘数量与使用率 —— *)
_fPerRawM3min := _fMDotKgS / DL_RHO_N * DL_S_PER_MIN;              // 单喷嘴耗气 [m3/min]
_fUseRatio := LIMIT(0.0, fUsePct, DL_PCT) / DL_PCT;                // 使用率归一 [-]
_fCountReal := INT_TO_REAL(iCount);                                // 数量实数化 [个]
_fTotalRaw := _fPerRawM3min * _fCountReal * _fUseRatio;            // 总耗气 [m3/min]

(* —— 段 6：输出单点写盘（饱和钳制，观测流速按单喷嘴流量反算等效出口流速） —— *)
fPerNozzleM3min := LIMIT(0.0, _fPerRawM3min, DL_PER_MAX);          // 单喷嘴耗气 [m3/min]
fTotalM3min := LIMIT(0.0, _fTotalRaw, DL_TOT_MAX);                 // 总耗气 [m3/min]
fVelMps := LIMIT(0.0, (fPerNozzleM3min / DL_S_PER_MIN) / _fAreaM2, DL_BIG);   // 等效流速 [m/s]

(* —— 段 7：有效位单点聚合（使用率不越域 + 口径与数量合法） —— *)
xValid := (fUsePct >= 0.0) AND (fUsePct <= DL_PCT)                 // 使用率在 0..100 %
          AND (fOrificeMm > DL_EPS)                                // 口径为正
          AND (iCount >= 0)                                        // 数量非负
          AND (fSupplyBar >= 0.0);                                 // 供压非负
FC_DL_AirNozzleConsumptionCalc := xValid;                          // 返回码：TRUE = 计算可信

END_FUNCTION
