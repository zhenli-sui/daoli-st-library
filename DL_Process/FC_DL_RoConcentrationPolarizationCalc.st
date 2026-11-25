(*
  Name: FC_DL_RoConcentrationPolarizationCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 RO/NF 膜法水处理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 浓差极化因子按边界层膜模型 β = EXP(J / k) 估算：J 为膜通量换算成的渗透速度（m/s），
           k 为传质系数（m/s），J/k 为无因次的 Péclet 数；β 表示膜面盐浓度相对主体浓度的倍数，
           β 越大结垢与通量衰减风险越高。
        2) 通量入参按工程单位 LMH 接收，先做 LMH → m/s 的两级换算（/1000 L/m3、/3600 s/h），
           保证与传质系数同量纲后才能相除，禁止 LMH 与 m/s 直接相除。
        3) 膜面横流速度参与可行性判定而非进入算式：横流速度是传质系数 k 的物理来源，
           实测横流为零意味着 k 的标定前提失效（层流边界层崩溃），此时 β 模型不可信，
           故对横流做零闸并判无效，而不是把横流再乘一次导致双重计入。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fCpFactor 强制 0.0）并置无效（R19）。
        2) 传质系数零闸：ABS(fMassTransCoef) > DL_EPS 才允许相除，否则判无效。
        3) 横流速度零闸：fCrossFlowMps <= DL_EPS 判无效（无横流即无稳定边界层）。
        4) Péclet 数上限保护：J/k 先钳到 0 ~ LN(DL_CP_MAX)，防止 EXP 溢出成 Inf；
           β 结果再饱和钳到 DL_CP_MIN ~ DL_CP_MAX（1.0 ~ 3.0），超出即无物理意义。
        5) 通量为负判无效（传感器反向）；通量为 0 属合法工况，β 退化为 1.0。
        6) 无回差环节：纯函数无状态，不做迟滞。
  量纲自证：J = (L/(m2·h)) / 1000 (L/m3) / 3600 (s/h) = m/s；
           J / k = (m/s) / (m/s) = 无因次 Péclet 数 [-]；
           β = EXP([-]) = 无因次浓度比 [-]。
*)

FUNCTION FC_DL_RoConcentrationPolarizationCalc : BOOL
VAR_INPUT
    fFluxLMH         : REAL;   // 膜通量 [L/(m2·h)] / Membrane flux [LMH]
    fCrossFlowMps    : REAL;   // 膜面横流速度 [m/s] / Membrane cross-flow velocity [m/s]
    fMassTransCoef   : REAL;   // 传质系数 k [m/s] / Mass transfer coefficient [m/s]
END_VAR
VAR_OUTPUT
    fCpFactor        : REAL;   // 浓差极化因子 β [-] / Concentration polarization factor [-]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fFluxMps        : REAL;   // 换算后的渗透速度 [m/s] / Permeate velocity [m/s]
    _fPeclet         : REAL;   // Péclet 数 J/k [-] / Peclet number [-]
    _fPecletMax      : REAL;   // Péclet 数上限（由 β 上限反算）[-] / Peclet ceiling [-]
    _fBetaRaw        : REAL;   // 未饱和的极化因子 [-] / Raw polarization factor [-]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_L_PER_M3      : REAL := 1000.0;    // m3 → L 换算因子 [L/m3] / Cubic metre to litre factor [L/m3]
    DL_S_PER_H       : REAL := 3600.0;    // h → s 换算因子 [s/h] / Hour to second factor [s/h]
    DL_CP_MIN        : REAL := 1.0;       // 极化因子饱和下限 [-] / Polarization factor low [-]
    DL_CP_MAX        : REAL := 3.0;       // 极化因子饱和上限 [-] / Polarization factor high [-]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不进 EXP） —— *)
IF NOT (fFluxLMH > -DL_BIG AND fFluxLMH < DL_BIG)
   OR NOT (fCrossFlowMps > -DL_BIG AND fCrossFlowMps < DL_BIG)
   OR NOT (fMassTransCoef > -DL_BIG AND fMassTransCoef < DL_BIG) THEN
    fCpFactor := 0.0;                       // 输出强制 0.0 / Output forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_RoConcentrationPolarizationCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：传质系数零闸 + 横流零闸（R4：两个分母/前提都要闸） —— *)
IF (ABS(fMassTransCoef) <= DL_EPS) OR (fCrossFlowMps <= DL_EPS) THEN
    fCpFactor := 0.0;                       // 前提失效即不给数 / No premise, no number
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_RoConcentrationPolarizationCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：通量单位换算（LMH → m/s，两级因子不可省略） —— *)
_fFluxMps := MAX(0.0, fFluxLMH) / DL_L_PER_M3 / DL_S_PER_H;   // 渗透速度 [m/s]

(* —— 段 4：Péclet 数与上限保护（先钳指数再 EXP，防溢出成 Inf） —— *)
_fPecletMax := LN(DL_CP_MAX);                                  // 由 β 上限反算的指数上限 [-]
_fPeclet := LIMIT(0.0, _fFluxMps / fMassTransCoef, _fPecletMax);   // J/k 钳 0..LN(3)
_fBetaRaw := EXP(_fPeclet);                                    // 极化因子 [-]

(* —— 段 5：有效位单点聚合（通量非负 + 前提量正） —— *)
xValid := (fFluxLMH >= 0.0)                                    // 通量不得为负
          AND (fMassTransCoef > DL_EPS)                        // 传质系数必须为正
          AND (fCrossFlowMps > DL_EPS);                        // 横流必须为正

(* —— 段 6：输出单点写盘（β 饱和钳到物理域） —— *)
fCpFactor := LIMIT(DL_CP_MIN, _fBetaRaw, DL_CP_MAX);           // β 钳 1.0..3.0 [-]
FC_DL_RoConcentrationPolarizationCalc := xValid;               // 返回码：TRUE = 计算可信

END_FUNCTION
